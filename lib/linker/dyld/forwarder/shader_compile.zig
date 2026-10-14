//! Shader creation may compile for seconds. Its input must outlive reuse of
//! the shared marshal arena before the Windows runtime lock can be released.
const std = @import("std");
const abi = @import("gpu").vulkan.abi;
const marshal = @import("gpu").vulkan.marshal;
pub const Function = *const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32;
pub const Owned = struct {
    allocator: std.mem.Allocator,
    storage: []u64,
    pub fn copy(allocator: std.mem.Allocator, source: []const u8) !Owned {
        if (source.len < @sizeOf(marshal.ShaderModuleCreateInfo)) return error.InvalidInfo;
        const root: *const marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(source.ptr));
        if (root.p_next != null or root.code_size > marshal.max_spill_bytes or (root.code_size != 0 and root.code == null)) return error.InvalidInfo;
        const length = std.math.add(usize, @sizeOf(marshal.ShaderModuleCreateInfo), root.code_size) catch return error.InvalidInfo;
        const storage = try allocator.alloc(u64, std.math.divCeil(usize, length, 8) catch return error.InvalidInfo);
        var owned: Owned = .{ .allocator = allocator, .storage = storage };
        const backing = std.mem.sliceAsBytes(storage);
        @memcpy(backing[0..@sizeOf(marshal.ShaderModuleCreateInfo)], source[0..@sizeOf(marshal.ShaderModuleCreateInfo)]);
        const header = owned.info();
        if (root.code_size == 0) header.code = null else {
            const code = backing[@sizeOf(marshal.ShaderModuleCreateInfo)..][0..root.code_size];
            @memcpy(code, @as([*]const u8, @ptrCast(root.code.?))[0..root.code_size]);
            header.code = code.ptr;
        }
        return owned;
    }
    pub fn info(self: *Owned) *marshal.ShaderModuleCreateInfo {
        return @ptrCast(self.storage.ptr);
    }
    pub fn bytes(self: *Owned) []u8 {
        return std.mem.sliceAsBytes(self.storage)[0..@sizeOf(marshal.ShaderModuleCreateInfo)];
    }
    pub fn deinit(self: *Owned) void {
        self.allocator.free(self.storage);
        self.* = undefined;
    }
};
const Call = struct {
    function: Function,
    device: abi.Device,
    info: *const marshal.ShaderModuleCreateInfo,
    output: *u64,
    fn invoke(self: @This()) i32 {
        return self.function(self.device, self.info, null, self.output);
    }
};
/// The caller owns the original SPIR-V and all transform allocations until
/// this returns. Only the driver runs outside the lock; all proof, handle and
/// result bookkeeping remains under the reacquired dispatch lock.
pub fn call(state: anytype, function: Function, device: abi.Device, info: *const marshal.ShaderModuleCreateInfo, output: *u64) i32 {
    const request: Call = .{ .function = function, .device = device, .info = info, .output = output };
    if (comptime @hasDecl(@TypeOf(state.*), "withWindowsRuntimeLockReleasedFor")) {
        return state.withWindowsRuntimeLockReleasedFor(.native_shader_module, request, Call.invoke);
    }
    return Call.invoke(request);
}
test "FSI shader compile snapshot owns header and code independently of marshal arena" {
    var words = [_]u32{ 0x07230203, 0x10000, 0, 50, 0, 0x20011, 1 };
    var root: marshal.ShaderModuleCreateInfo = .{ .s_type = 16, .flags = 123, .code = &words, .code_size = @sizeOf(@TypeOf(words)) };
    var owned = try Owned.copy(std.testing.allocator, std.mem.asBytes(&root));
    defer owned.deinit();
    const expected = words;
    @memset(&words, 0xbaadbaad);
    root = .{};
    try std.testing.expectEqual(@as(u32, 16), owned.info().s_type);
    try std.testing.expectEqual(@as(u32, 123), owned.info().flags);
    try std.testing.expectEqualSlices(u32, &expected, @as([*]const u32, @ptrCast(@alignCast(owned.info().code.?)))[0..expected.len]);
    try std.testing.expect(@intFromPtr(owned.info().code.?) % 4 == 0);
    try std.testing.expect(owned.info().p_next == null);
}
test "FSI shader compile snapshot refuses extension chains missing code and allocation failure" {
    var root: marshal.ShaderModuleCreateInfo = .{ .p_next = @ptrFromInt(8) };
    try std.testing.expectError(error.InvalidInfo, Owned.copy(std.testing.allocator, std.mem.asBytes(&root)));
    root = .{ .code_size = 4 };
    try std.testing.expectError(error.InvalidInfo, Owned.copy(std.testing.allocator, std.mem.asBytes(&root)));
    root = .{};
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, Owned.copy(failing.allocator(), std.mem.asBytes(&root)));
}
