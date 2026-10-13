//! Real guest marshalling -> FIFO -> native callback, without a Vulkan device.
const std = @import("std");
const root = @import("../dynamic_library_forwarder.zig");
const internal = root.__ForwarderInternals;
const abi = internal._abi;
const clock = internal._transport_timing;
const fifo = internal._async_vulkan_command;

const Calls = struct {
    var entered: std.atomic.Value(bool) = .init(false);
    var release: std.atomic.Value(bool) = .init(false);
    var events: u32 = 0;
    var errors: u32 = 0;
    fn block(_: abi.CommandBuffer, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {
        entered.store(true, .release);
        const deadline = clock.nowNs() + 2_000_000_000;
        while (!release.load(.acquire) and clock.nowNs() < deadline) std.atomic.spinLoopHint();
    }
    fn sets(buffer: abi.CommandBuffer, point: u32, layout: u64, first: u32, count: u32, values: [*]const u64, n: u32, offsets: ?[*]const u32) callconv(.c) void {
        if (events != 0 or @intFromPtr(buffer.?) != 0x222 or point != 0 or layout != 0x444 or first != 2 or count != 2 or n != 2 or values[0] != 0x666 or values[1] != 0x888 or offsets.?[0] != 12 or offsets.?[1] != 28) errors += 1;
        events += 1;
    }
    fn push(buffer: abi.CommandBuffer, layout: u64, stages: u32, offset: u32, size: u32, data: ?*const anyopaque) callconv(.c) void {
        const values: [*]const u8 = @ptrCast(data.?);
        if (events != 1 or @intFromPtr(buffer.?) != 0x222 or layout != 0x444 or stages != 0x10 or offset != 8 or size != 16 or std.mem.readInt(u32, values[0..4], .little) != 0x12345678) errors += 1;
        events += 1;
    }
    fn boundary(_: abi.CommandBuffer) callconv(.c) void {
        if (events != 2) errors += 1;
        events += 1;
    }
};

pub fn check(comptime State: type) !void {
    try @import("barrier_argument_tests.zig").check(State);
    try std.testing.expect(fifo.isCandidate("vkCmdBindDescriptorSets"));
    try std.testing.expect(fifo.isCandidate("vkCmdPushConstants"));
    inline for (.{ "vkUpdateDescriptorSets", "vkFreeDescriptorSets", "vkResetCommandPool", "vkDestroyPipelineLayout", "vkQueueSubmit", "vkCmdEndRenderPass" }) |name| try std.testing.expect(!fifo.isCandidate(name));
    for (0..2) |mode| {
        var forwarder = root.Forwarder{};
        var state = State{};
        defer forwarder.stopAsyncVulkanCommandWorker();
        const map = internal._HandleMap;
        _ = map.alloc(&forwarder.real_vulkan.command_buffer_map, 0x111, 0x222);
        _ = map.alloc(&forwarder.real_vulkan.pipeline_layout_map, 0x333, 0x444);
        _ = map.alloc(&forwarder.real_vulkan.descriptor_set_map, 0x555, 0x666);
        _ = map.alloc(&forwarder.real_vulkan.descriptor_set_map, 0x777, 0x888);
        forwarder.real_vulkan.fn_ptrs.cmd_bind_descriptor_sets = Calls.sets;
        forwarder.real_vulkan.fn_ptrs.cmd_push_constants = Calls.push;
        forwarder.real_vulkan.fn_ptrs.cmd_end_render_pass = Calls.boundary;
        forwarder.vulkan_async_command_worker_decided = true;
        forwarder.vulkan_async_command_worker_enabled = mode == 1;
        Calls.events = 0;
        Calls.errors = 0;
        Calls.entered.store(false, .monotonic);
        Calls.release.store(false, .monotonic);
        defer Calls.release.store(true, .release);
        if (mode == 1) {
            try std.testing.expect(forwarder.queueAsyncVulkanCommand(.{ .draw = .{ .function = Calls.block, .command_buffer = @ptrFromInt(0x222), .vertex_count = 3, .instance_count = 1, .first_vertex = 0, .first_instance = 0 } }));
            const deadline = clock.nowNs() + 2_000_000_000;
            while (!Calls.entered.load(.acquire) and clock.nowNs() < deadline) std.atomic.spinLoopHint();
            try std.testing.expect(Calls.entered.load(.acquire));
        }
        state.regs = .{ .rdi = 0x111, .rsi = 0, .rdx = 0x333, .rcx = 2, .r8 = 2, .r9 = 256, .rsp = 128 };
        state.write64(256, 0x555);
        state.write64(264, 0x777);
        state.write64(136, 2);
        state.write64(144, 320);
        state.write32(320, 12);
        state.write32(324, 28);
        forwarder.forwardVulkanCommand(&state, internal._vulkanNameHash("vkCmdBindDescriptorSets"), "vkCmdBindDescriptorSets");
        state.regs.rsi = 0x333;
        state.regs.rdx = 0x10;
        state.regs.rcx = 8;
        state.regs.r8 = 16;
        state.regs.r9 = 384;
        state.write32(384, 0x12345678);
        forwarder.forwardVulkanCommand(&state, internal._vulkanNameHash("vkCmdPushConstants"), "vkCmdPushConstants");
        @memset(state.mem[256..400], 0xee);
        if (mode == 1) {
            try std.testing.expectEqual(@as(u64, 3), forwarder.vulkan_async_command_worker.?.stats().submitted);
            Calls.release.store(true, .release);
        }
        // Real synchronous API call must publish both snapshots first.
        forwarder.forwardVulkanCommand(&state, internal._vulkanNameHash("vkCmdEndRenderPass"), "vkCmdEndRenderPass");
        try std.testing.expectEqual(@as(u32, 3), Calls.events);
        try std.testing.expectEqual(@as(u32, 0), Calls.errors);
        try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_descriptor_bind_admission.forwarded);
        try std.testing.expectEqual(@as(u64, 0), forwarder.vulkan_descriptor_bind_admission.rejected);
    }
}

pub fn checkAvailability() !void {
    try std.testing.expect(!internal._isForwardableVulkanSymbol("vkCmdUnknownRosetteCommand"));
    try std.testing.expect(internal._isForwardableVulkanSymbol("vkCmdSetDepthTestEnableEXT"));
    try std.testing.expectEqualStrings("vkCmdSetDepthTestEnable", internal._canonicalVulkanCommand("vkCmdSetDepthTestEnableEXT"));
    try std.testing.expect(!internal._isForwardableVulkanSymbol("rosette_xenia_launch_assist_query"));
}
