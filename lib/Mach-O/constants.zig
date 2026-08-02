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
pub const TRACE_BUFFER_LEN: usize = 256;
pub const IMPORT_TRACE_BUFFER_LEN: usize = 64;
pub const MEMORY_TRACE_BUFFER_LEN: usize = 64;
pub const PROGRESS_REPORT_INTERVAL: u64 = 500_000;
pub const HEARTBEAT_INTERVAL: u64 = 25_000_000;
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
pub const IDLE_STARVATION_STEPS: u64 = 100_000;
pub const INITIALIZER_STEP_LIMIT: u64 = 2_000_000;
pub const GUEST_LOG_BUFFER_SIZE: u64 = 64 * 1024;
pub const DECODE_CACHE_ENTRY_COUNT: usize = 1 << 16;
pub const DECODE_CACHE_HASH_SHIFT: u6 = 48;
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
