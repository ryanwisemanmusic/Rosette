//! Executable memory for compiled PowerPC blocks.
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
    /// Bumped on every reset so a stale block handle can be recognised rather
    /// than followed into memory that now holds something else.
    generation: u64 = 0,

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
        const aligned = std.mem.alignForward(usize, self.used, 16);
        const bytes = count * @sizeOf(u32);
        if (aligned + bytes > self.memory.len) return Error.OutOfCodeSpace;
        const start = aligned;
        self.used = aligned + bytes;
        const raw: [*]u32 = @ptrCast(@alignCast(self.memory.ptr + start));
        return raw[0..count];
    }

    /// Drop every block. The caller is responsible for having removed the
    /// handles first: the generation bump makes a missed one detectable, not
    /// harmless.
    pub fn reset(self: *CodeCache) void {
        self.used = 0;
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
