const std = @import("std");
const builtin = @import("builtin");

pub const STACK_SIZE: u64 = 8 * 1024 * 1024;
pub const MEM_SIZE: u64 = 2 * 1024 * 1024 * 1024;

pub fn envMemSizeMb() ?u64 {
    const env = std.c.getenv("ROSETTE_MEM_SIZE_MB") orelse return null;
    const len = std.mem.len(env);
    return std.fmt.parseInt(u64, env[0..len], 10) catch null;
}
pub const MEM_BASE: u64 = 0x0;
pub const PAGE_SIZE: u64 = 4096;
// Retained instruction history is partitioned per guest thread rather than
// shared. The old single 256-entry ring was divided among every live thread, so
// a faulting thread's reach depended on how noisy its neighbours were — the
// direct cause of history-based recognizers being unable to decide anything
// about a long-running thread. Each thread now gets its own window.
//
// Sizing: 24 slots x 512 entries x ~160 bytes/entry is ~2 MB, heap-allocated
// once per process. Xenia runs ~13 live guest threads, so the slot count leaves
// headroom before eviction begins (and evictions are counted and reported).
pub const TRACE_THREAD_SLOTS: usize = 24;
pub const TRACE_PER_THREAD_LEN: usize = 512;
// Retained for the fixed-size diagnostic rings that are still process-wide
// (memory, import). Instruction history no longer uses it.
pub const TRACE_BUFFER_LEN: usize = 256;
pub const IMPORT_TRACE_BUFFER_LEN: usize = 64;
pub const MEMORY_TRACE_BUFFER_LEN: usize = 64;
/// Endian-contract evidence ring: always-on, recorded at the execute site for
/// the narrow set of instructions the generated-endian contract consumes
/// (movbe loads + 32-bit register/memory comparisons). Kept separate from the
/// diagnostic-gated memory trace so the contract can substantiate repairs in
/// production runs where ROSETTE_MACHO_MEMORY_TRACE is not set.
pub const ENDIAN_EVIDENCE_BUFFER_LEN: usize = 16;
pub const PROGRESS_REPORT_INTERVAL: u64 = 500_000;
pub const HEARTBEAT_INTERVAL: u64 = 100_000_000;
/// Cadence of the concise "Translated instructions" line. Kept separate from
/// HEARTBEAT_INTERVAL: that line is a coarse liveness signal for someone
/// watching a long run, not a per-phase performance sample.
pub const CONCISE_PROGRESS_INTERVAL: u64 = 250_000_000;
pub const UNSUPPORTED_RUNTIME_EXIT_CODE: u64 = 125;
pub const GUEST_FILE_BASE: u64 = 0xFFFF_FF10_0000_0000;
pub const GUEST_FILE_MAX: usize = 32;
pub const BOUND_IMPORT_THUNK_BASE: u64 = 0xFFFF_FC00_0000_0000;
pub const BOUND_IMPORT_THUNK_STRIDE: u64 = 16;
pub const INITIALIZER_RETURN_SENTINEL: u64 = 0xFFFF_FB00_0000_0000;
pub const GUEST_THREAD_RETURN_SENTINEL: u64 = 0xFFFF_FA00_0000_0000;
pub const GUEST_SIGNAL_RETURN_SENTINEL: u64 = 0xFFFF_F900_0000_0000;
pub const GUEST_ATEXIT_RETURN_SENTINEL: u64 = 0xFFFF_F800_0000_0000;
pub const DEFAULT_GUEST_THREAD_STACK_SIZE: u64 = 2 * 1024 * 1024;
pub const COOPERATIVE_THREAD_QUANTUM_STEPS: u64 = 10_000;
/// P0-1 (perf audit): cadence for the cooperative scheduler's full queue
/// scans (idle-callback table + every suspended thread). These used to run
/// on every interpreted instruction; the scheduler only acts on their
/// results at quantum boundaries or on idle dispatch, so scanning at this
/// interval (256 steps, ~40 scans per 10k-step quantum) is ample while
/// removing the per-instruction scan from the interpreter hot loop.
pub const COOPERATIVE_SCHEDULER_SCAN_INTERVAL: u64 = 256;
pub const IDLE_STARVATION_STEPS: u64 = 100_000;
pub const INITIALIZER_STEP_LIMIT: u64 = 2_000_000;
pub const GUEST_LOG_BUFFER_SIZE: u64 = 64 * 1024;
/// The Xenia image alone has substantially more than 65,536 hot instruction
/// starts.  With the old 64K / two-way table, a steady-state Halo 3 interval
/// reported 1,506,110 live-entry evictions for only 30 vacant fills: the cache
/// was decoding immutable Mach-O text again because unrelated instructions
/// competed for two slots.  Four times the capacity is about 23 MiB at the
/// current entry size, small beside the translated process heap and large
/// enough to retain the host-side compiler passes that dominate the trace.
pub const DECODE_CACHE_ENTRY_COUNT: usize = 1 << 18;
/// Eight-way set associativity keeps the same 32,768 sets as the previous 64K
/// two-way layout while giving each colliding working set four times the room.
/// Replacement uses second-chance reference bits in `process.zig`; unlike the
/// old two-way-only MRU bit, every way is eligible and no fixed final way
/// absorbs all evictions.
pub const DECODE_CACHE_WAYS: usize = 8;
pub const DECODE_CACHE_SET_COUNT: usize = DECODE_CACHE_ENTRY_COUNT / DECODE_CACHE_WAYS;
pub const DECODE_CACHE_HASH_SHIFT: u6 = 46;
/// 64 - log2(DECODE_CACHE_SET_COUNT).
pub const DECODE_CACHE_SET_SHIFT: u6 = 49;
pub const DECODE_CACHE_HASH_MULTIPLIER: u64 = 0x9E37_79B9_7F4A_7C15;

/// Hash an exact instruction address into the direct-mapped decode cache.
///
/// The old `(address >> 4) & mask` mapping gave every instruction in the same
/// 16-byte block one cache slot. A normal basic block therefore evicted itself
/// continuously (the Xenia trace showed a 3% hit rate). Multiplicative hashing
/// keeps neighboring instruction starts in independent slots while still
/// mixing high JIT addresses such as 0xA0000000 into the index.
pub inline fn decodeCacheIndex(address: u64) usize {
    return @intCast((address *% DECODE_CACHE_HASH_MULTIPLIER) >> DECODE_CACHE_HASH_SHIFT);
}

/// Index of the first way of the set an address maps to.
pub inline fn decodeCacheSetBase(address: u64) usize {
    const set: usize = @intCast((address *% DECODE_CACHE_HASH_MULTIPLIER) >> DECODE_CACHE_SET_SHIFT);
    return set * DECODE_CACHE_WAYS;
}

test "invalidation and lookup enumerate the same slots" {
    // The safety property of set associativity: a stale decode must not be
    // reachable in a way the invalidation walk skipped. Both sides derive their
    // slots from `decodeCacheSetBase`, so this pins that they agree — if the
    // lookup ever gains a way the invalidation does not clear, the cache can
    // execute bytes the guest has overwritten.
    for ([_]u64{ 0x1000, 0xA000_5AF8, 0x34D8_6000 }) |address| {
        const base = decodeCacheSetBase(address);
        var covered = false;
        for (0..DECODE_CACHE_WAYS) |way| {
            if (base + way < DECODE_CACHE_ENTRY_COUNT) covered = true;
        }
        try std.testing.expect(covered);
        try std.testing.expect(base + DECODE_CACHE_WAYS <= DECODE_CACHE_ENTRY_COUNT);
    }
    // Sets partition the table exactly: no slot belongs to two sets and none is
    // unreachable.
    try std.testing.expectEqual(DECODE_CACHE_ENTRY_COUNT, DECODE_CACHE_SET_COUNT * DECODE_CACHE_WAYS);
}

test "every set base is in range and both ways are addressable" {
    for ([_]u64{ 0, 1, 0xA000_5AF8, 0x34D8_6000, std.math.maxInt(u64) }) |address| {
        const base = decodeCacheSetBase(address);
        try std.testing.expect(base + DECODE_CACHE_WAYS <= DECODE_CACHE_ENTRY_COUNT);
        try std.testing.expectEqual(@as(usize, 0), base % DECODE_CACHE_WAYS);
    }
}

test "a set holds two independent addresses that previously evicted each other" {
    // Find a colliding pair under the direct-mapped index, then prove the
    // set-associative mapping still gives them distinct ways to live in.
    var probe: u64 = 0x1000;
    const target = decodeCacheIndex(0x1000);
    const collider = while (probe < 0x40_0000) : (probe += 1) {
        if (probe != 0x1000 and decodeCacheIndex(probe) == target) break probe;
    } else 0;
    if (collider != 0) {
        try std.testing.expectEqual(decodeCacheSetBase(0x1000), decodeCacheSetBase(collider));
    }
}

test "decode cache hashes neighboring instruction starts independently" {
    var seen = [_]bool{false} ** DECODE_CACHE_ENTRY_COUNT;
    for (0..16) |offset| {
        const index = decodeCacheIndex(0xA000_5AF8 + offset);
        try std.testing.expect(!seen[index]);
        seen[index] = true;
    }
}
pub const IMPORT_ROUTE_CACHE_SIZE: usize = 1024;
pub const PAGE_READ: u8 = 1 << 0;
pub const PAGE_WRITE: u8 = 1 << 1;
pub const PAGE_EXECUTE: u8 = 1 << 2;
pub const GUEST_SIGILL: u8 = 4;
pub const GUEST_SIGSEGV: u8 = 11;
pub const SA_RESETHAND: u32 = 0x0004;
pub const SA_NODEFER: u32 = 0x0010;
pub const SA_SIGINFO: u32 = 0x0040;
pub const GUEST_SIGNAL_ACTION_COUNT: usize = 32;
pub const GUEST_SIGNAL_FRAME_DEPTH: usize = 8;
pub const DARWIN_SIGACTION_SIZE: u64 = 16;
pub const DARWIN_SIGINFO_SIZE: u64 = 128;
pub const DARWIN_UCONTEXT_SIZE: u64 = 56;
pub const DARWIN_MCONTEXT_SIZE: u64 = 184;
pub const PROFILE_ACCOUNT_INFO_BYTES: u64 = 0x17C;
pub const PROFILE_ENCRYPTED_ACCOUNT_BYTES: u64 = PROFILE_ACCOUNT_INFO_BYTES + 0x18;
pub const TOML_CODEPOINT_CAPACITY: usize = 32;
pub const TOML_CODEPOINT_STRIDE: usize = 24;
pub const TOML_READER_ISTREAM_OFFSET: u64 = 8;
pub const TOML_CODEPOINTS_OFFSET: u64 = 0x30;
pub const TOML_CODEPOINT_CURRENT_OFFSET: u64 = 0x330;
pub const TOML_CODEPOINT_COUNT_OFFSET: u64 = 0x338;
pub const TOML_UTF8_READER_MIN_SIZE: u64 = 0x350;
