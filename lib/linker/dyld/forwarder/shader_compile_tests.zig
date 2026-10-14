//! Shader-module ownership at the production forwarder boundary.
const forwarder_root = @import("../dynamic_library_forwarder.zig");
const Forwarder = forwarder_root.Forwarder;
const std = forwarder_root.__ForwarderInternals._std;
const abi = forwarder_root.__ForwarderInternals._abi;
const marshal = forwarder_root.__ForwarderInternals._marshal;
const TestState = @import("tests.zig").TestState;

test "FSI native shader compile survives marshal arena reuse and concurrent result overwrite" {
    const State = struct {
        guest: TestState = .{},
        forwarder: *Forwarder,
        releases: u32 = 0,
        pub fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
            return self.guest.guestMemoryConst(address, length);
        }
        pub fn read32(self: *@This(), address: u64) u32 {
            return self.guest.read32(address);
        }
        pub fn read64(self: *@This(), address: u64) u64 {
            return self.guest.read64(address);
        }
        pub fn withWindowsRuntimeLockReleasedFor(self: *@This(), purpose: anytype, context: anytype, callback: anytype) @TypeOf(callback(context)) {
            std.debug.assert(purpose == .native_shader_module);
            self.releases += 1;
            self.forwarder.vulkan_scratch.reset();
            const bytes = self.forwarder.vulkan_scratch.alloc(4096).?;
            @memset(bytes, 0xba);
            self.forwarder.real_create_result = abi.ERROR_OUT_OF_HOST_MEMORY;
            return callback(context);
        }
    };
    const Driver = struct {
        var calls: usize = 0;
        fn create(_: abi.Device, raw: *const anyopaque, allocator: ?*const anyopaque, out: *u64) callconv(.c) i32 {
            const info: *const marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(raw));
            std.debug.assert(allocator == null and info.s_type == 16 and info.p_next == null);
            const code: [*]const u32 = @ptrCast(@alignCast(info.code.?));
            std.debug.assert(code[0] == 0x07230203 and code[5] == 0x20011 and code[6] == 1);
            calls += 1;
            out.* = 0x4567;
            return abi.SUCCESS;
        }
    };
    var forwarder: Forwarder = .{};
    defer forwarder.vulkan_scratch.deinit();
    var state: State = .{ .forwarder = &forwarder };
    const words = [_]u32{
        0x07230203, 0x10000, 0,       16,      0,  0x20011, 1,
        0x3000e,    0,       1,       0x5000f, 5,  10,      0x6e69616d,
        0,          0x60010, 10,      17,      1,  1,       1,
        0x20013,    1,       0x30021, 2,       1,  0x50036, 1,
        10,         0,       2,       0x200f8, 11, 0x100fd, 0x10038,
    };
    const root: marshal.ShaderModuleCreateInfo = .{ .s_type = 16, .code_size = @sizeOf(@TypeOf(words)), .code = @ptrFromInt(2048) };
    try std.testing.expect(state.guest.copyToGuest(1024, std.mem.asBytes(&root)));
    try std.testing.expect(state.guest.copyToGuest(2048, std.mem.sliceAsBytes(&words)));
    forwarder.robust_access_configured = true;
    forwarder.rect_expand_configured = true;
    forwarder.fsi_pixel_frequency_configured = true;
    forwarder.hdr_resolve_configured = true;
    forwarder.real_vulkan.device = @ptrFromInt(0x1234);
    forwarder.real_vulkan.fn_ptrs.create_shader_module = Driver.create;
    Driver.calls = 0;
    try forwarder.createRealVulkanObject(&state, 0x321, 1024, "vkCreateShaderModule");
    try std.testing.expectEqual(@as(usize, 1), Driver.calls);
    try std.testing.expectEqual(@as(u32, 1), state.releases);
    try std.testing.expectEqual(abi.SUCCESS, forwarder.real_create_result);
    try std.testing.expect(forwarder.realVulkanObjectMapped(0x321, "vkCreateShaderModule"));
}

test "FSI shader creation returns while owned guest and native evidence disk writes are blocked" {
    const gpu = @import("gpu");
    const Sink = struct {
        permit: std.atomic.Value(bool) = .init(false),
        entered: std.atomic.Value(bool) = .init(false),
        count: usize = 0,
        correct: bool = true,
        expected: []const u32 = &.{},
        fn save(raw: ?*anyopaque, job: gpu.vulkan.fsi.evidence_async.Request) gpu.vulkan.fsi.evidence.Result {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.entered.store(true, .release);
            while (!self.permit.load(.acquire)) std.Thread.yield() catch {};
            self.correct = self.correct and job.guest == 0x321 and std.mem.eql(u32, self.expected, job.words);
            if (self.count == 0) self.correct = self.correct and job.version == .guest else self.correct = self.correct and job.version == .native;
            self.count += 1;
            return .saved;
        }
    };
    const Driver = struct {
        var calls: usize = 0;
        fn create(_: abi.Device, raw: *const anyopaque, _: ?*const anyopaque, out: *u64) callconv(.c) i32 {
            const info: *const marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(raw));
            std.debug.assert(info.code_size != 0 and info.code != null);
            calls += 1;
            out.* = 0x4567;
            return abi.SUCCESS;
        }
    };
    var sink: Sink = .{};
    var forwarder: Forwarder = .{};
    const writer = try gpu.vulkan.fsi.evidence_async.Writer.create(std.testing.allocator, Sink.save, &sink);
    // Always release the test's blocked sink before teardown, including failures.
    defer {
        sink.permit.store(true, .release);
        forwarder.deinit();
    }
    forwarder.fsi_evidence_io.writer = writer;
    forwarder.fsi_evidence_io.enabled = true;
    var state: TestState = .{};
    const code = [_]u32{ 0x07230203, 0x10000, 0, 16, 0, 0x20011, 1, 0x3000e, 0, 1, 0x5000f, 5, 10, 0x6e69616d, 0, 0x60010, 10, 17, 1, 1, 1, 0x20013, 1, 0x30021, 2, 1, 0x50036, 1, 10, 0, 2, 0x200f8, 11, 0x100fd, 0x10038 };
    const info: marshal.ShaderModuleCreateInfo = .{ .s_type = 16, .code_size = @sizeOf(@TypeOf(code)), .code = @ptrFromInt(2048) };
    sink.expected = &code;
    try std.testing.expect(state.copyToGuest(1024, std.mem.asBytes(&info)));
    try std.testing.expect(state.copyToGuest(2048, std.mem.sliceAsBytes(&code)));
    forwarder.robust_access_configured = true;
    forwarder.rect_expand_configured = true;
    forwarder.fsi_pixel_frequency_configured = true;
    forwarder.hdr_resolve_configured = true;
    forwarder.real_vulkan.device = @ptrFromInt(0x1234);
    forwarder.real_vulkan.fn_ptrs.create_shader_module = Driver.create;
    Driver.calls = 0;
    try forwarder.createRealVulkanObject(&state, 0x321, 1024, "vkCreateShaderModule");
    try std.testing.expectEqual(@as(usize, 1), Driver.calls);
    try std.testing.expectEqual(@as(u64, 1), forwarder.shader_host_profile.calls);
    try std.testing.expectEqual(@as(u64, 2), writer.snapshot().accepted);
    try std.testing.expectEqual(@as(u64, 0), writer.snapshot().saved);
    try std.testing.expectEqual(abi.SUCCESS, forwarder.real_create_result);
    try std.testing.expect(forwarder.realVulkanObjectMapped(0x321, "vkCreateShaderModule"));
    // Original, rewritten and marshal backing can all be reused immediately.
    @memset(&state.mem, 0xba);
    forwarder.vulkan_scratch.reset();
    sink.permit.store(true, .release);
    writer.flush();
    try std.testing.expect(sink.correct);
    try std.testing.expectEqual(@as(usize, 2), sink.count);
}
