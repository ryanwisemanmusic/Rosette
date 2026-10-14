//! Shared CPU-only guest memory fixture for forwarder tests.
const std = @import("std");
pub const TestState = struct {
    xmm: [16][16]u8 = @splat(@splat(0)),
    mem: [16 * 1024]u8 = [_]u8{0} ** (16 * 1024),
    parallel_guest_execution: bool = false,
    regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0, r8: u64 = 0, r9: u64 = 0, rsp: u64 = 0, rax: u64 = 0 } = .{},
    executed_steps: u64 = 10,
    active_guest_thread: u64 = 0x7FFF_2020,
    active_idle_source: u64 = 1,
    monotonic_nanoseconds: u64 = 0,
    last_opaque_handle: u64 = 0,
    last_opaque_owner: []const u8 = "",
    last_synthetic_thunk: u64 = 0,
    last_synthetic_thunk_size: u64 = 0,
    last_synthetic_thunk_owner: []const u8 = "",
    heap_next: u64 = 1024,

    pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
        if (self.parallel_guest_execution) return null;
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }

    pub fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }

    /// The ordered writer, which stays available when `parallel_guest_execution`
    /// refuses raw views - the case these tests use to prove a path does not
    /// depend on one.
    pub fn copyToGuest(self: *@This(), address: u64, source: []const u8) bool {
        if (address + source.len > self.mem.len) return false;
        @memcpy(self.mem[@intCast(address)..][0..source.len], source);
        return true;
    }

    pub fn guestCString(self: *@This(), address: u64, maximum: usize) ?[]const u8 {
        if (address >= self.mem.len) return null;
        const start: usize = @intCast(address);
        const available = self.mem[start..@min(self.mem.len, start + maximum)];
        const length = std.mem.indexOfScalar(u8, available, 0) orelse return null;
        return available[0..length];
    }

    pub fn read32(self: *@This(), address: u64) u32 {
        return std.mem.readInt(u32, self.mem[@intCast(address)..][0..4], .little);
    }

    pub fn read64(self: *@This(), address: u64) u64 {
        return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
    }

    pub fn write32(self: *@This(), address: u64, value: u32) void {
        std.mem.writeInt(u32, self.mem[@intCast(address)..][0..4], value, .little);
    }

    pub fn write64(self: *@This(), address: u64, value: u64) void {
        std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
    }

    pub fn guestAlloc(self: *@This(), requested_size: u64, alignment: u64) ?u64 {
        if (alignment == 0 or alignment & (alignment - 1) != 0) return null;
        const start = std.mem.alignForward(u64, self.heap_next, alignment);
        const end = std.math.add(u64, start, @max(requested_size, 1)) catch return null;
        if (end > self.mem.len) return null;
        @memset(self.mem[@intCast(start)..@intCast(end)], 0);
        self.heap_next = end;
        return start;
    }

    pub fn validateNativeMetalLayerToken(_: *@This(), token: u64) bool {
        return token == 0xCAFE_BABE;
    }

    pub fn registerOpaqueApiHandle(self: *@This(), handle: u64, owner: []const u8) void {
        self.last_opaque_handle = handle;
        self.last_opaque_owner = owner;
    }

    pub fn registerSyntheticThunk(self: *@This(), address: u64, size: u64, owner: []const u8) void {
        self.last_synthetic_thunk = address;
        self.last_synthetic_thunk_size = size;
        self.last_synthetic_thunk_owner = owner;
    }

    pub fn nativeWindowWidth(_: *@This()) u32 {
        return 1280;
    }

    pub fn nativeWindowHeight(_: *@This()) u32 {
        return 720;
    }
};
