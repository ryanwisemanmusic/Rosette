//! Darwin thread-local variables.
//!
//! A `__thread` variable is reached through a descriptor:
//!
//! ```c
//! struct tlv_descriptor {
//!   void* (*thunk)(struct tlv_descriptor*);  // +0
//!   unsigned long key;                       // +8
//!   unsigned long offset;                    // +16
//! };
//! ```
//!
//! and `_tlv_get_addr` returns `per_thread_block + offset`. **One** block per
//! thread holds every thread-local in the image, sized by the linker as
//! `__thread_data` followed by `__thread_bss`, with `__thread_data`'s contents
//! as the initialisation template and the rest zeroed. The `offset` field is
//! what places a variable inside that block.
//!
//! This previously allocated a fixed 4 KiB block **per descriptor** and returned
//! its base, discarding `offset`. For small thread-locals that is
//! indistinguishable from correct — every variable lands in its own region and
//! nothing overlaps. For a large one it is silent heap corruption: a 64 KiB
//! `thread_local` buffer (which is exactly what a translated program's logger
//! uses) writes 60 KiB past its allocation into whatever the bump allocator
//! handed out next, on every use.
//!
//! The observable symptom is not a crash. It is another thread's data appearing
//! inside yours — log lines spliced together mid-word, and, wherever the
//! overrun happens to land, values that were written correctly and read back
//! wrong. Nothing reports it, because from the runtime's side every access was
//! in bounds of the block it *thought* it had.
//!
//! So the block is now sized from the sections, shared per thread as the ABI
//! specifies, initialised from the template, and `offset` is applied. A size the
//! sections cannot supply is reported rather than assumed.

const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

pub const bootstrap_thunk: u64 = 0xFFFF_F700_0000_0000;
const descriptor_size: u64 = 3 * @sizeOf(u64);
const descriptor_offset_field: u64 = 16;

/// Used only when the image exposes no `__thread_data`/`__thread_bss` sizes.
/// Generous on purpose: the previous value was a plausible-looking 4 KiB, and
/// plausible-looking is what let a 64 KiB overrun go unnoticed.
const fallback_block_size: u64 = 256 * 1024;

const max_threads = 64;

const Block = struct {
    thread: u64 = 0,
    storage: u64 = 0,
};

pub const Runtime = struct {
    blocks: [max_threads]Block = [_]Block{.{}} ** max_threads,
    descriptor_count: u64 = 0,
    allocation_count: u64 = 0,
    /// Size of one thread's block, derived from the image.
    block_size: u64 = 0,
    /// Bytes of initialised template copied into each new block.
    template_address: u64 = 0,
    template_size: u64 = 0,
    /// True when `block_size` came from the sections rather than the fallback.
    size_derived: bool = false,
    /// Accesses whose `offset` fell outside the block. Each one is a variable
    /// the runtime cannot place, and silently clamping would put two
    /// thread-locals at one address.
    offset_overflows: u64 = 0,
    /// Threads that arrived after the table was full.
    thread_overflows: u64 = 0,

    pub fn installDescriptors(self: *Runtime, state: anytype) void {
        // The block spans __thread_data then __thread_bss; descriptor offsets
        // are relative to the start of that span.
        const data = state.metadata.sectionNamed("__DATA", "__thread_data");
        const bss = state.metadata.sectionNamed("__DATA", "__thread_bss");
        if (data) |section| {
            self.template_address = section.address;
            self.template_size = section.size;
        }
        var span_start: u64 = 0;
        var span_end: u64 = 0;
        if (data) |section| {
            span_start = section.address;
            span_end = section.address +| section.size;
        }
        if (bss) |section| {
            if (span_start == 0 or section.address < span_start) span_start = section.address;
            if (section.address +| section.size > span_end) span_end = section.address +| section.size;
        }
        if (span_end > span_start) {
            self.block_size = span_end - span_start;
            self.size_derived = true;
        } else {
            self.block_size = fallback_block_size;
            self.size_derived = false;
        }

        const section = state.metadata.sectionNamed("__DATA", "__thread_vars") orelse return;
        var descriptor = section.address;
        const end = section.address +| section.size;
        while (descriptor + descriptor_size <= end) : (descriptor += descriptor_size) {
            if (state.guestMemory(descriptor, descriptor_size) == null) break;
            state.write64(descriptor, bootstrap_thunk);
            self.descriptor_count +|= 1;
        }
        if (self.descriptor_count != 0) {
            machoCapturePrint(
                "macho-processor: installed Darwin TLV bootstrap for {d} descriptor(s); per-thread block={d} bytes (derived={}) template={d} bytes at 0x{x}. One block per thread holds every thread-local, and each descriptor's offset places a variable inside it — a fixed per-descriptor block would silently truncate any thread-local larger than it\n",
                .{ self.descriptor_count, self.block_size, self.size_derived, self.template_size, self.template_address },
            );
        }
    }

    pub fn handles(address: u64) bool {
        return address == bootstrap_thunk;
    }

    /// The per-thread block, allocating and initialising it on first use.
    fn blockFor(self: *Runtime, state: anytype, thread_key: u64) ?u64 {
        for (&self.blocks) |*block| {
            if (block.storage != 0 and block.thread == thread_key) return block.storage;
        }
        for (&self.blocks) |*block| {
            if (block.storage != 0) continue;
            const storage = state.guestAlloc(self.block_size, 16) orelse return null;
            if (state.guestMemory(storage, self.block_size)) |bytes| {
                @memset(bytes, 0);
                // Darwin copies __thread_data over the head of the block and
                // leaves the __thread_bss tail zeroed. Skipping the copy gives
                // every thread zeroed initialised thread-locals, which is wrong
                // in a way that only shows up for variables with initialisers.
                if (self.template_size != 0) {
                    const copy_len = @min(self.template_size, self.block_size);
                    if (state.guestMemoryConst(self.template_address, copy_len)) |template| {
                        @memcpy(bytes[0..@intCast(copy_len)], template[0..@intCast(copy_len)]);
                    }
                }
            }
            block.* = .{ .thread = thread_key, .storage = storage };
            self.allocation_count +|= 1;
            return storage;
        }
        self.thread_overflows +|= 1;
        return null;
    }

    pub fn resolve(self: *Runtime, state: anytype, descriptor: u64, thread: u64) ?u64 {
        const thread_key = if (thread == 0) @as(u64, 1) else thread;
        const storage = self.blockFor(state, thread_key) orelse return null;
        const offset = state.read64(descriptor +| descriptor_offset_field);
        if (offset >= self.block_size) {
            // Refused rather than clamped: clamping would place two distinct
            // thread-locals at one address, which is the corruption this exists
            // to prevent, reintroduced by the fix.
            self.offset_overflows +|= 1;
            machoCapturePrint(
                "macho-processor: TLV offset out of range: descriptor=0x{x} offset={d} block_size={d} derived={}; refusing to place this thread-local rather than clamping it onto another. If the block size was not derived from __thread_data/__thread_bss, that is the thing to fix\n",
                .{ descriptor, offset, self.block_size, self.size_derived },
            );
            return null;
        }
        return storage +| offset;
    }

    pub fn logSummary(self: *const Runtime) void {
        if (self.descriptor_count == 0) return;
        machoCapturePrint(
            "macho-processor: Darwin TLV runtime: descriptors={d} thread_blocks={d} block_size={d} size_derived={} offset_overflows={d} thread_overflows={d}\n",
            .{ self.descriptor_count, self.allocation_count, self.block_size, self.size_derived, self.offset_overflows, self.thread_overflows },
        );
    }
};

const TestState = struct {
    memory: [1 << 20]u8 = [_]u8{0} ** (1 << 20),
    next: u64 = 0x1000,

    fn guestAlloc(self: *TestState, size: u64, alignment: u64) ?u64 {
        const mask = alignment - 1;
        const base = (self.next + mask) & ~mask;
        if (base + size > self.memory.len) return null;
        self.next = base + size;
        return base;
    }

    fn guestMemory(self: *TestState, address: u64, size: u64) ?[]u8 {
        if (address + size > self.memory.len) return null;
        return self.memory[@intCast(address)..@intCast(address + size)];
    }

    fn guestMemoryConst(self: *TestState, address: u64, size: u64) ?[]const u8 {
        return self.guestMemory(address, size);
    }

    fn read64(self: *TestState, address: u64) u64 {
        const slice = self.guestMemory(address, 8) orelse return 0;
        return std.mem.readInt(u64, slice[0..8], .little);
    }
};

test "a thread-local is placed at its descriptor's offset, not at the block base" {
    var state = TestState{};
    var runtime = Runtime{ .block_size = 0x20000, .size_derived = true };

    // Two descriptors, at different offsets within the one per-thread block.
    const descriptor_a: u64 = 0x100;
    const descriptor_b: u64 = 0x200;
    std.mem.writeInt(u64, state.guestMemory(descriptor_a + 16, 8).?[0..8], 0, .little);
    std.mem.writeInt(u64, state.guestMemory(descriptor_b + 16, 8).?[0..8], 0x10000, .little);

    const a = runtime.resolve(&state, descriptor_a, 7) orelse return error.TestFailed;
    const b = runtime.resolve(&state, descriptor_b, 7) orelse return error.TestFailed;

    // Same block, different addresses — a 64 KiB variable at offset 0 reaches
    // exactly up to the one at 0x10000 and no further.
    try std.testing.expectEqual(a + 0x10000, b);
    try std.testing.expectEqual(@as(u64, 1), runtime.allocation_count);
}

// The defect this replaces: every descriptor got its own fixed block and the
// offset was discarded, so a thread-local larger than that block wrote past it.
test "one block per thread, sized for every thread-local at once" {
    var state = TestState{};
    var runtime = Runtime{ .block_size = 0x20000, .size_derived = true };
    const descriptor: u64 = 0x100;
    std.mem.writeInt(u64, state.guestMemory(descriptor + 16, 8).?[0..8], 0, .little);

    const first = runtime.resolve(&state, descriptor, 7) orelse return error.TestFailed;
    const again = runtime.resolve(&state, descriptor, 7) orelse return error.TestFailed;
    try std.testing.expectEqual(first, again);

    // A different thread gets its own block, and the two do not overlap.
    const other = runtime.resolve(&state, descriptor, 9) orelse return error.TestFailed;
    try std.testing.expect(other != first);
    try std.testing.expect(other >= first + runtime.block_size or first >= other + runtime.block_size);
    try std.testing.expectEqual(@as(u64, 2), runtime.allocation_count);
}

test "an offset outside the block is refused rather than clamped" {
    var state = TestState{};
    var runtime = Runtime{ .block_size = 0x1000, .size_derived = true };
    const descriptor: u64 = 0x100;
    std.mem.writeInt(u64, state.guestMemory(descriptor + 16, 8).?[0..8], 0x4000, .little);
    try std.testing.expect(runtime.resolve(&state, descriptor, 1) == null);
    try std.testing.expectEqual(@as(u64, 1), runtime.offset_overflows);
}

test "the initialised template is copied into each new thread's block" {
    var state = TestState{};
    var runtime = Runtime{
        .block_size = 0x1000,
        .size_derived = true,
        .template_address = 0x800,
        .template_size = 4,
    };
    const template = state.guestMemory(0x800, 4).?;
    template[0] = 0xAA;
    template[1] = 0xBB;

    const descriptor: u64 = 0x100;
    std.mem.writeInt(u64, state.guestMemory(descriptor + 16, 8).?[0..8], 0, .little);
    const block = runtime.resolve(&state, descriptor, 3) orelse return error.TestFailed;
    const bytes = state.guestMemory(block, 8).?;
    try std.testing.expectEqual(@as(u8, 0xAA), bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xBB), bytes[1]);
    // Everything past the template is zeroed, as __thread_bss requires.
    try std.testing.expectEqual(@as(u8, 0), bytes[4]);
}

test "thread zero is a distinct key rather than an unallocated block" {
    var state = TestState{};
    var runtime = Runtime{ .block_size = 0x1000, .size_derived = true };
    const descriptor: u64 = 0x100;
    std.mem.writeInt(u64, state.guestMemory(descriptor + 16, 8).?[0..8], 0, .little);
    const zero = runtime.resolve(&state, descriptor, 0) orelse return error.TestFailed;
    const one = runtime.resolve(&state, descriptor, 1) orelse return error.TestFailed;
    try std.testing.expectEqual(zero, one);
}
