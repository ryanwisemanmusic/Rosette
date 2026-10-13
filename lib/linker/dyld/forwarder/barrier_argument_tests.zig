//! Actual guest -> handle translation -> owned FIFO -> native callback proof.
const std = @import("std");
const root = @import("../dynamic_library_forwarder.zig");
const internal = root.__ForwarderInternals;
const abi = internal._abi;
const clock = internal._transport_timing;

const Calls = struct {
    var entered: std.atomic.Value(bool) = .init(false);
    var release: std.atomic.Value(bool) = .init(false);
    var events: u32 = 0;
    var errors: u32 = 0;
    var expected_memory: u32 = 1;
    fn block(_: abi.CommandBuffer, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {
        entered.store(true, .release);
        const deadline = clock.nowNs() + 2_000_000_000;
        while (!release.load(.acquire) and clock.nowNs() < deadline) std.atomic.spinLoopHint();
    }
    fn barrier(command: abi.CommandBuffer, source: u32, destination: u32, dependencies: u32, n: u32, memory: ?*const anyopaque, b: u32, buffers: ?*const anyopaque, i: u32, images: ?[*]const abi.ImageMemoryBarrier) callconv(.c) void {
        const m: [*]const abi.MemoryBarrier = @ptrCast(@alignCast(memory.?));
        const v: [*]const abi.BufferMemoryBarrier = @ptrCast(@alignCast(buffers.?));
        const image = images.?[0];
        if (events != 0 or @intFromPtr(command.?) != 0x222 or source != 0x80 or destination != 0x1000 or dependencies != 1 or n != expected_memory or b != 1 or i != 1) errors += 1;
        if (m[0].src_access_mask != 0x20 or m[0].dst_access_mask != 0x40 or m[0].p_next != null) errors += 1;
        if (v[0].buffer != 0x444 or v[0].offset != 123 or v[0].size != 4096 or v[0].src_queue_family_index != 2 or v[0].dst_queue_family_index != 3) errors += 1;
        if (image.image != 0x666 or image.old_layout != 1 or image.new_layout != 5 or image.subresource_range.base_array_layer != 4 or image.subresource_range.layer_count != 3) errors += 1;
        events += 1;
    }
    fn boundary(_: abi.CommandBuffer) callconv(.c) void {
        if (events != 1) errors += 1;
        events += 1;
    }
};

pub fn check(comptime State: type) !void {
    try std.testing.expect(internal._async_vulkan_command.isCandidate("vkCmdPipelineBarrier"));
    try std.testing.expect(!internal._async_vulkan_command.isCandidate("vkCmdPipelineBarrier2"));
    for (0..3) |mode| {
        var forwarder = root.Forwarder{};
        var state = State{};
        defer forwarder.stopAsyncVulkanCommandWorker();
        const map = internal._HandleMap;
        _ = map.alloc(&forwarder.real_vulkan.command_buffer_map, 0x111, 0x222);
        _ = map.alloc(&forwarder.real_vulkan.buffer_map, 0x333, 0x444);
        _ = map.alloc(&forwarder.real_vulkan.image_map, 0x555, 0x666);
        forwarder.real_vulkan.fn_ptrs.cmd_pipeline_barrier = Calls.barrier;
        forwarder.real_vulkan.fn_ptrs.cmd_end_render_pass = Calls.boundary;
        forwarder.vulkan_async_command_worker_decided = true;
        forwarder.vulkan_async_command_worker_enabled = mode != 0;
        Calls.events = 0;
        Calls.errors = 0;
        Calls.expected_memory = if (mode == 2) 3 else 1;
        Calls.entered.store(false, .monotonic);
        Calls.release.store(false, .monotonic);
        defer Calls.release.store(true, .release);
        if (mode == 1) {
            try std.testing.expect(forwarder.queueAsyncVulkanCommand(.{ .draw = .{ .function = Calls.block, .command_buffer = @ptrFromInt(0x222), .vertex_count = 3, .instance_count = 1, .first_vertex = 0, .first_instance = 0 } }));
            const deadline = clock.nowNs() + 2_000_000_000;
            while (!Calls.entered.load(.acquire) and clock.nowNs() < deadline) std.atomic.spinLoopHint();
            try std.testing.expect(Calls.entered.load(.acquire));
        }
        const memory: [3]abi.MemoryBarrier = @splat(.{ .src_access_mask = 0x20, .dst_access_mask = 0x40 });
        const buffer = abi.BufferMemoryBarrier{ .buffer = 0x333, .offset = 123, .size = 4096, .src_queue_family_index = 2, .dst_queue_family_index = 3 };
        const image = abi.ImageMemoryBarrier{ .image = 0x555, .old_layout = 1, .new_layout = 5, .subresource_range = .{ .base_array_layer = 4, .layer_count = 3 } };
        @memcpy(state.mem[512..][0..@sizeOf(@TypeOf(memory))], std.mem.asBytes(&memory));
        @memcpy(state.mem[640..][0..@sizeOf(abi.BufferMemoryBarrier)], std.mem.asBytes(&buffer));
        @memcpy(state.mem[768..][0..@sizeOf(abi.ImageMemoryBarrier)], std.mem.asBytes(&image));
        state.regs = .{ .rdi = 0x111, .rsi = 0x80, .rdx = 0x1000, .rcx = 1, .r8 = Calls.expected_memory, .r9 = 512, .rsp = 128 };
        state.write64(136, 1);
        state.write64(144, 640);
        state.write64(152, 1);
        state.write64(160, 768);
        forwarder.forwardVulkanCommand(&state, internal._vulkanNameHash("vkCmdPipelineBarrier"), "vkCmdPipelineBarrier");
        if (mode == 1) {
            try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_async_command_worker.?.stats().barrier_snapshots);
            try std.testing.expectEqual(@as(u32, 0), Calls.events);
            @memset(state.mem[512..900], 0xee);
            Calls.release.store(true, .release);
        } else try std.testing.expectEqual(@as(u32, 1), Calls.events);
        forwarder.forwardVulkanCommand(&state, internal._vulkanNameHash("vkCmdEndRenderPass"), "vkCmdEndRenderPass");
        try std.testing.expectEqual(@as(u32, 2), Calls.events);
        try std.testing.expectEqual(@as(u32, 0), Calls.errors);
    }
}
