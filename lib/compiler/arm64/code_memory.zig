//! Executable memory for compiled guest blocks (PowerPC and x86-64 alike).
//!
//! Apple Silicon does not allow a mapping to be writable and executable at the
//! same time. A JIT gets one region mapped `MAP_JIT` and flips its own thread
//! between write mode and execute mode; the flip is per thread, not per page,
//! so two threads can be in different modes over the same memory. Getting this
//! wrong does not produce a subtle bug - it produces a bus error on the first
//! store or the first call, which is the good kind of failure.
//!
//! Two things are easy to forget and are handled here rather than left to the
//! caller:
//!
//!   * The instruction cache must be invalidated after writing. Without it the
//!     processor may execute whatever was at that address before, which on a
//!     reused code cache is a *different function* - a failure that looks like
//!     miscompilation and moves when you add logging.
//!   * The `MAP_JIT` mapping needs the `com.apple.security.cs.allow-jit`
//!     entitlement under the hardened runtime. Rosette's adhoc entitlements
//!     already carry it; a build that loses it fails here, at allocation, with
//!     a reason - not later, at an address with no context.

const std = @import("std");
const builtin = @import("builtin");
const branch_islands = @import("branch_islands.zig");

pub const Error = error{
    /// The host refused an executable mapping. On macOS this is usually a
    /// missing JIT entitlement rather than a lack of memory.
    MappingRefused,
    /// The requested code does not fit in the remaining region.
    OutOfCodeSpace,
    /// This host has no supported way to allocate executable memory.
    Unsupported,
};

const is_darwin = builtin.os.tag.isDarwin();
const is_aarch64 = builtin.cpu.arch == .aarch64;

extern "c" fn pthread_jit_write_protect_np(enabled: c_int) void;
extern "c" fn sys_icache_invalidate(start: ?*anyopaque, len: usize) void;

/// A bump-allocated region of executable memory.
///
/// Blocks are never individually freed. A code cache that reclaims individual
/// blocks needs to know that nothing is executing inside one, which for a
/// multi-threaded guest means a quiescence protocol; resetting the whole region
/// at a safe point is both simpler and what a guest's own module unload maps
/// onto anyway.
pub const CodeCache = struct {
    memory: []align(std.heap.page_size_min) u8,
    used: usize = 0,
    branch_islands_enabled: bool = false,
    branch_islands: branch_islands.State = .{},
    /// Bumped on every reset so a stale block handle can be recognised rather
    /// than followed into memory that now holds something else.
    generation: u64 = 0,
    /// The open split window (`reserveSplit`), [`window_start`,
    /// `window_end`): everything in it is within `split_window` bytes of
    /// everything else, the reach of `cbz`/`b.cond` from a block's hot path
    /// to its cold paths. Hot and cold parts each fill a run of pages, and
    /// the next run of either kind is the window's next free page
    /// (`window_next`), so hot pages are dense yet spread through the window
    /// in proportion to the code: packing every hot part into one stretch
    /// per window put all of it in the same fraction of a cache's sets.
    window_start: usize = 0,
    window_end: usize = 0,
    window_next: usize = 0,
    hot_at: usize = 0,
    hot_end: usize = 0,
    cold_at: usize = 0,
    cold_end: usize = 0,
    /// Bytes actually handed out, hot and cold; `used` also counts the
    /// unfilled rest of the open window.
    reserved_bytes: usize = 0,
    /// The size of each split window: at most `split_window`.
    window_bytes: usize = split_window,

    /// A split window's size: within the +-1 MiB reach of a 19-bit branch.
    pub const split_window: usize = 1 << 20;
    /// The unit hot and cold runs are taken in: the host page.
    pub const split_page: usize = 16 << 10;

    pub const SplitCode = struct { hot: []u32, cold: []u32 };

    pub fn init(capacity_bytes: usize) Error!CodeCache {
        if (!is_darwin or !is_aarch64) return Error.Unsupported;

        const page = std.heap.pageSize();
        const size = std.mem.alignForward(usize, capacity_bytes, page);
        const result = std.c.mmap(
            null,
            size,
            .{ .READ = true, .WRITE = true, .EXEC = true },
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .JIT = true },
            -1,
            0,
        );
        if (@intFromPtr(result) == @as(usize, @bitCast(@as(isize, -1)))) {
            return Error.MappingRefused;
        }
        const bytes: [*]align(std.heap.page_size_min) u8 = @ptrCast(@alignCast(result));
        return .{ .memory = bytes[0..size], .used = 0, .generation = 1 };
    }

    pub fn deinit(self: *CodeCache) void {
        if (self.memory.len == 0) return;
        _ = std.c.munmap(self.memory.ptr, self.memory.len);
        self.memory = self.memory[0..0];
    }

    pub fn capacity(self: *const CodeCache) usize {
        return self.memory.len;
    }

    pub fn remaining(self: *const CodeCache) usize {
        return self.memory.len - self.used;
    }

    /// Reserve space for `count` instructions. The returned slice is writable
    /// only between `beginWrite` and `endWrite`.
    pub fn reserve(self: *CodeCache, count: usize) Error![]u32 {
        // Every block starts on a 16-byte boundary: it keeps a block from
        // straddling a cache line it did not need to, and it makes a code
        // address printable without a modulo in the reader's head.
        const bytes = count * @sizeOf(u32);
        const aligned = if (self.branch_islands_enabled and self.memory.len >= branch_islands.minimum_capacity)
            try self.branch_islands.place(self.memory.len, self.used, bytes)
        else
            std.mem.alignForward(usize, self.used, 16);
        if (aligned + bytes > self.memory.len) return Error.OutOfCodeSpace;
        const start = aligned;
        self.used = aligned + bytes;
        const raw: [*]u32 = @ptrCast(@alignCast(self.memory.ptr + start));
        return raw[0..count];
    }

    /// Reserve a block whose hot and cold parts are placed apart in one
    /// split window: hot parts of consecutive blocks are adjacent within hot
    /// pages, and every branch from a hot part to its cold part stays within
    /// the window. A block too large for a window is `OutOfCodeSpace` here;
    /// the caller can still place it contiguously with `reserve`.
    pub fn reserveSplit(self: *CodeCache, hot_count: usize, cold_count: usize) Error!SplitCode {
        const hot_bytes = std.mem.alignForward(usize, hot_count * @sizeOf(u32), 16);
        const cold_bytes = std.mem.alignForward(usize, cold_count * @sizeOf(u32), 16);
        const window = @min(self.window_bytes, split_window);
        const hot_run = std.mem.alignForward(usize, hot_bytes, split_page);
        const cold_run = std.mem.alignForward(usize, cold_bytes, split_page);
        if (hot_run + cold_run > window) return Error.OutOfCodeSpace;
        const hot_fits = self.hot_at + hot_bytes <= self.hot_end;
        const cold_fits = self.cold_at + cold_bytes <= self.cold_end;
        const needed = (if (hot_fits) 0 else hot_run) + (if (cold_fits) 0 else cold_run);
        if (self.window_end == 0 or self.window_next + needed > self.window_end) {
            // Open the next window where contiguous reservations left off.
            const start = std.mem.alignForward(usize, self.used, split_page);
            if (start + window > self.memory.len) return Error.OutOfCodeSpace;
            self.window_start = start;
            self.window_end = start + window;
            self.window_next = start;
            self.hot_at = 0;
            self.hot_end = 0;
            self.cold_at = 0;
            self.cold_end = 0;
            self.used = self.window_end;
        }
        if (self.hot_at + hot_bytes > self.hot_end) {
            self.hot_at = self.window_next;
            self.hot_end = self.window_next + hot_run;
            self.window_next = self.hot_end;
        }
        if (self.cold_at + cold_bytes > self.cold_end) {
            self.cold_at = self.window_next;
            self.cold_end = self.window_next + cold_run;
            self.window_next = self.cold_end;
        }
        const hot: [*]u32 = @ptrCast(@alignCast(self.memory.ptr + self.hot_at));
        const cold: [*]u32 = @ptrCast(@alignCast(self.memory.ptr + self.cold_at));
        self.hot_at += hot_bytes;
        self.cold_at += cold_bytes;
        self.reserved_bytes += hot_bytes + cold_bytes;
        return .{ .hot = hot[0..hot_count], .cold = cold[0..cold_count] };
    }

    /// Bytes in use: everything `reserve` handed out and both parts of every
    /// split reservation.
    pub fn bytesInUse(self: *const CodeCache) usize {
        if (self.window_end == 0) return self.used;
        const unfilled = (self.window_end - self.window_next) + (self.hot_end - self.hot_at) + (self.cold_end - self.cold_at);
        return self.used - unfilled;
    }

    /// Drop every block. The caller is responsible for having removed the
    /// handles first: the generation bump makes a missed one detectable, not
    /// harmless.
    pub fn reset(self: *CodeCache) void {
        self.used = 0;
        self.branch_islands = .{};
        self.window_start = 0;
        self.window_end = 0;
        self.window_next = 0;
        self.hot_at = 0;
        self.hot_end = 0;
        self.cold_at = 0;
        self.cold_end = 0;
        self.reserved_bytes = 0;
        self.generation +%= 1;
    }

    /// Enter write mode for this thread. Executing compiled code while in write
    /// mode faults, so the window has to be closed before any block runs.
    pub fn beginWrite(self: *const CodeCache) void {
        _ = self;
        if (is_darwin and is_aarch64) pthread_jit_write_protect_np(0);
    }

    /// Leave write mode and make `code` visible to the instruction fetcher.
    pub fn endWrite(self: *const CodeCache, code: []const u32) void {
        _ = self;
        if (is_darwin and is_aarch64) {
            pthread_jit_write_protect_np(1);
            // Order matters: the data cache has to be flushed and the
            // instruction cache invalidated *after* the last store, or the
            // processor may fetch the previous contents of these addresses.
            sys_icache_invalidate(
                @ptrCast(@constCast(code.ptr)),
                code.len * @sizeOf(u32),
            );
        }
    }

    /// True when this host can allocate executable memory at all.
    pub fn available() bool {
        return is_darwin and is_aarch64;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "a code cache reserves aligned space and reports exhaustion" {
    if (!CodeCache.available()) return error.SkipZigTest;
    var cache = try CodeCache.init(4096);
    defer cache.deinit();

    const first = try cache.reserve(3);
    try testing.expectEqual(@as(usize, 3), first.len);
    const second = try cache.reserve(1);
    // The second block starts on a 16-byte boundary, not immediately after the
    // three words of the first.
    try testing.expectEqual(@as(usize, 0), @intFromPtr(second.ptr) % 16);
    try testing.expect(@intFromPtr(second.ptr) > @intFromPtr(first.ptr));

    try testing.expectError(Error.OutOfCodeSpace, cache.reserve(cache.capacity()));
}

test "a reset returns the space and moves the generation" {
    if (!CodeCache.available()) return error.SkipZigTest;
    var cache = try CodeCache.init(4096);
    defer cache.deinit();
    _ = try cache.reserve(100);
    const before = cache.generation;
    cache.reset();
    try testing.expectEqual(cache.capacity(), cache.remaining());
    // A handle taken before the reset can be recognised as stale.
    try testing.expect(cache.generation != before);
}

test "code written into the cache actually executes" {
    if (!CodeCache.available()) return error.SkipZigTest;
    var cache = try CodeCache.init(4096);
    defer cache.deinit();

    // mov x0, #42 ; ret
    const code = try cache.reserve(2);
    cache.beginWrite();
    code[0] = 0xD2800540; // movz x0, #42
    code[1] = 0xD65F03C0; // ret
    cache.endWrite(code);

    const fn_ptr: *const fn () callconv(.c) u64 = @ptrCast(code.ptr);
    try testing.expectEqual(@as(u64, 42), fn_ptr());
}

test "a second block written after the first executes as its own function" {
    if (!CodeCache.available()) return error.SkipZigTest;
    var cache = try CodeCache.init(4096);
    defer cache.deinit();

    const first = try cache.reserve(2);
    cache.beginWrite();
    first[0] = 0xD2800020; // movz x0, #1
    first[1] = 0xD65F03C0; // ret
    cache.endWrite(first);

    const second = try cache.reserve(2);
    cache.beginWrite();
    second[0] = 0xD2800040; // movz x0, #2
    second[1] = 0xD65F03C0; // ret
    cache.endWrite(second);

    const call_first: *const fn () callconv(.c) u64 = @ptrCast(first.ptr);
    const call_second: *const fn () callconv(.c) u64 = @ptrCast(second.ptr);
    // If the instruction cache were not invalidated after the second write,
    // this is where the processor would run stale bytes.
    try testing.expectEqual(@as(u64, 1), call_first());
    try testing.expectEqual(@as(u64, 2), call_second());
}

test "compiled code can take arguments and touch memory" {
    if (!CodeCache.available()) return error.SkipZigTest;
    var cache = try CodeCache.init(4096);
    defer cache.deinit();

    // ldr x2, [x0] ; add x2, x2, x1 ; str x2, [x0] ; ret
    const code = try cache.reserve(4);
    cache.beginWrite();
    code[0] = 0xF9400002;
    code[1] = 0x8B010042;
    code[2] = 0xF9000002;
    code[3] = 0xD65F03C0;
    cache.endWrite(code);

    var slot: u64 = 10;
    const fn_ptr: *const fn (*u64, u64) callconv(.c) void = @ptrCast(code.ptr);
    fn_ptr(&slot, 32);
    try testing.expectEqual(@as(u64, 42), slot);
}

test "split reservations keep hot parts adjacent and every cold part in reach" {
    if (!CodeCache.available()) return error.SkipZigTest;
    var cache = try CodeCache.init(4 * CodeCache.split_window);
    defer cache.deinit();
    const first = try cache.reserveSplit(10, 100);
    const second = try cache.reserveSplit(6, 50);
    // Hot parts follow each other in the hot page, cold parts in the cold one.
    try testing.expectEqual(@intFromPtr(first.hot.ptr) + 48, @intFromPtr(second.hot.ptr));
    try testing.expectEqual(@intFromPtr(first.cold.ptr) + 400, @intFromPtr(second.cold.ptr));
    try testing.expectEqual(@intFromPtr(first.hot.ptr) + CodeCache.split_page, @intFromPtr(first.cold.ptr));
    for ([_]CodeCache.SplitCode{ first, second }) |part| {
        const distance = @intFromPtr(part.cold.ptr + part.cold.len) - @intFromPtr(part.hot.ptr);
        try testing.expect(distance <= CodeCache.split_window);
    }
    // A contiguous block goes after the open window; the window keeps filling.
    const plain = try cache.reserve(8);
    try testing.expect(@intFromPtr(plain.ptr) >= @intFromPtr(first.hot.ptr) + CodeCache.split_window);
    const third = try cache.reserveSplit(4, 4);
    try testing.expectEqual(@intFromPtr(second.hot.ptr) + 32, @intFromPtr(third.hot.ptr));
    try testing.expectEqual(@as(usize, 48 + 400 + 32 + 208 + 16 + 16), cache.reserved_bytes);
    // A hot part that does not fit its page takes the window's next free
    // pages, after the cold page: hot and cold pages interleave.
    const big = try cache.reserveSplit(CodeCache.split_page / 4 * 3, 4);
    try testing.expectEqual(@intFromPtr(first.hot.ptr) + 2 * CodeCache.split_page, @intFromPtr(big.hot.ptr));
    try testing.expectEqual(@intFromPtr(third.cold.ptr) + 16, @intFromPtr(big.cold.ptr));
    // A block larger than a window can only be placed contiguously.
    try testing.expectError(Error.OutOfCodeSpace, cache.reserveSplit(CodeCache.split_window / 4, 1));
    cache.reset();
    try testing.expectEqual(@as(usize, 0), cache.bytesInUse());
}

test "split code runs: a hot path branches to a cold part most of a window away and back" {
    if (!CodeCache.available()) return error.SkipZigTest;
    const assembler = @import("assembler.zig");
    const a64 = @import("encode.zig");
    var cache = try CodeCache.init(CodeCache.split_window);
    defer cache.deinit();
    // Hot-heavy blocks fill hot pages while the first cold page keeps room:
    // the last block's hot part is near the window's end, its cold part at
    // its start.
    _ = try cache.reserveSplit(4, 4);
    while (cache.window_next + CodeCache.split_page <= cache.window_end - CodeCache.split_page) _ = try cache.reserveSplit(CodeCache.split_page / 4, 4);
    var asm_ = assembler.Assembler.init(testing.allocator);
    defer asm_.deinit();
    const slow = try asm_.createLabel();
    const back = try asm_.createLabel();
    // x0 = 1; if x0 != 0 goto slow; back: ret.  slow: x0 = 42; goto back.
    try asm_.loadConstant(0, 1);
    try asm_.branchIfNonZero(.x64, 0, slow);
    asm_.placeLabel(back);
    try asm_.emit(a64.ret());
    asm_.section = .cold;
    asm_.placeLabel(slow);
    try asm_.loadConstant(0, 42);
    try asm_.branch(back);
    asm_.section = .hot;
    const parts = try cache.reserveSplit(asm_.words.items.len, asm_.cold_words.items.len);
    try testing.expect(@intFromPtr(parts.hot.ptr) - @intFromPtr(parts.cold.ptr) > CodeCache.split_window / 2);
    const code = try asm_.finishSplit(@intFromPtr(parts.hot.ptr), @intFromPtr(parts.cold.ptr));
    cache.beginWrite();
    @memcpy(parts.hot, code.hot);
    @memcpy(parts.cold, code.cold);
    cache.endWrite(parts.hot);
    cache.endWrite(parts.cold);
    const fn_ptr: *const fn () callconv(.c) u64 = @ptrCast(parts.hot.ptr);
    try testing.expectEqual(@as(u64, 42), fn_ptr());
}

test {
    _ = @import("branch_islands.zig");
}
