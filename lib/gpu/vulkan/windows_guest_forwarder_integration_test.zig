//! Exercise the actual PE register state through the Windows/SysV adapter.
const std = @import("std");
const ElfState = @import("elf_processor_state").ElfState;
const Bridge = @import("windows_guest_forwarder").Bridge;

test "PE depth state reaches the native Vulkan ABI and preserves Windows registers" {
    const Capture = struct {
        var values: [3]f32 = @splat(0);
        fn bias(_: ?*anyopaque, a: f32, b: f32, c: f32) callconv(.c) void {
            values = .{ a, b, c };
        }
    };
    var state = ElfState.init(std.testing.allocator);
    defer state.deinit();
    var bridge = Bridge{};
    defer bridge.deinit();
    bridge.forwarder.real_vulkan.command_buffer_map[0] = .{ .synthetic = 0x111, .real = 0x222 };
    bridge.forwarder.real_vulkan.fn_ptrs.cmd_set_depth_bias = Capture.bias;
    state.regs.rcx = 0x111;
    state.regs.rsp = state.mem_base + 0x1000;
    const expected = [_]f32{ 1.5, -0.5, 2.0 };
    for (expected, 1..) |value, index| std.mem.writeInt(u32, state.xmm[index][0..4], @bitCast(value), .little);
    const saved_xmm = state.xmm;
    const saved_rsp = state.regs.rsp;
    try std.testing.expect(bridge.dispatch(&state, "vkCmdSetDepthBias", 0x9876));
    try std.testing.expectEqualDeep(expected, Capture.values);
    try std.testing.expectEqualDeep(saved_xmm, state.xmm);
    try std.testing.expectEqual(saved_rsp, state.regs.rsp);
    try std.testing.expectEqual(@as(u64, 0x111), state.regs.rcx);
    try std.testing.expectEqual(@as(u64, 0x9876), state.regs.rip);
}
