//! Exercise the actual PE register state through the Windows/SysV adapter.
const std = @import("std");
const ElfState = @import("elf_processor_state").ElfState;
const Bridge = @import("windows_guest_forwarder").Bridge;
const abi = @import("gpu").vulkan.abi;

test "PE Vulkan mapped memory retains native byte identity across stores and unmap" {
    const Driver = struct {
        var bytes: [64]u8 align(4096) = @splat(0);
        var maps: u32 = 0;
        var unmaps: u32 = 0;
        fn map(_: abi.Device, memory: abi.DeviceMemory, offset: u64, size: u64, _: u32, output: *?*anyopaque) callconv(.c) abi.Result {
            std.debug.assert(memory == 0x401 and offset == 16 and size == 16);
            output.* = @ptrCast(&bytes[16]);
            maps += 1;
            return abi.SUCCESS;
        }
        fn unmap(_: abi.Device, _: abi.DeviceMemory) callconv(.c) void {
            unmaps += 1;
        }
    };
    Driver.maps = 0;
    Driver.unmaps = 0;
    var state = ElfState.init(std.testing.allocator);
    defer state.deinit();
    var bridge = Bridge{};
    defer bridge.deinit();
    bridge.library_token = 1;
    const forwarder = &bridge.forwarder;
    forwarder.guest_libraries[0] = .{ .token = 1, .virtual_vulkan = true };
    forwarder.real_vulkan.device = @ptrFromInt(0x100);
    std.mem.writeInt(u64, forwarder.real_vulkan.physical_device_properties[600..608], 64, .little);
    forwarder.real_vulkan.memory_map[0] = .{ .synthetic = 0x301, .real = 0x401 };
    forwarder.vulkan_memory_records[0] = .{ .handle = 0x301, .requested_size = 64, .memory_flags_known = true, .memory_flags = abi.MEMORY_PROPERTY_HOST_COHERENT_BIT | abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT };
    forwarder.real_vulkan.fn_ptrs.map_memory = Driver.map;
    forwarder.real_vulkan.fn_ptrs.unmap_memory = Driver.unmap;
    state.regs.rsp = state.mem_base + 0x1000;
    const output = state.mem_base + 0x2000;
    const heap_before = state.heap_next;
    var first_alias: u64 = 0;
    // Repeated maps reuse vacant bounded alias slots, not a new allocation
    // and monotonically exhausted guest heap on each upload.
    for (0..300) |iteration| {
        Driver.bytes[16] = 100;
        state.regs.rcx = 0x100;
        state.regs.rdx = 0x301;
        state.regs.r8 = 16;
        state.regs.r9 = 16;
        state.write64(state.regs.rsp + 32, 0);
        state.write64(state.regs.rsp + 40, output);
        try std.testing.expect(bridge.dispatch(&state, "vkMapMemory", 0x9876));
        try std.testing.expectEqual(@as(u64, abi.SUCCESS), state.regs.rax);
        const alias = state.read64(output);
        try std.testing.expectEqual(@as(u64, 0), (alias - 16) % 64);
        try std.testing.expectEqual(@intFromPtr(&Driver.bytes[16]) & 0xffffffff, alias & 0xffffffff);
        try std.testing.expectEqual(@as(u8, 100), state.read8(alias));
        if (iteration == 0) first_alias = alias else try std.testing.expectEqual(first_alias, alias);
        try std.testing.expect(state.windowsGuestRangeContains(alias, 16));
        try std.testing.expect(!state.windowsGuestRangeContains(alias + 16, 1));
        try std.testing.expect(state.guestMemory(alias - 1, 2) == null);
        // A same-value CPU store after a native change must not disappear
        // because it happens to equal a stale CPU-shadow baseline.
        Driver.bytes[16] = 50;
        state.write8(alias, 100);
        try std.testing.expectEqual(@as(u8, 100), Driver.bytes[16]);
        const vector: [16]u8 = @splat(9);
        state.writeMem128(alias, vector);
        try std.testing.expectEqualSlices(u8, &vector, Driver.bytes[16..32]);
        Driver.bytes[21] = 77;
        try std.testing.expectEqual(@as(u8, 77), state.read8(alias + 5));
        try std.testing.expectEqual(@intFromPtr(&Driver.bytes[16]), @intFromPtr(state.guestMemory(alias, 16).?.ptr));
        state.regs.rcx = 0x100;
        state.regs.rdx = 0x301;
        try std.testing.expect(bridge.dispatch(&state, "vkUnmapMemory", 0x9876));
        try std.testing.expect(state.guestMemory(alias, 1) == null);
        try std.testing.expectEqual(@as(u64, 9), Driver.bytes[17]);
    }
    // Only the adapter's small scratch-stack allocation remains; no 64-byte
    // shadow or duplicate baseline is allocated on any of the 300 maps.
    try std.testing.expect(state.heap_next - heap_before < 300 * 400);
    try std.testing.expect(forwarder.vulkan_memory_records[0].shadow_baseline == null);
    try std.testing.expectEqual(@as(u32, 300), Driver.maps);
    try std.testing.expectEqual(Driver.maps, Driver.unmaps);
    try std.testing.expectEqual(@as(usize, 0), state.native_memory_alias_count);
    std.mem.writeInt(u64, forwarder.real_vulkan.physical_device_properties[600..608], 0, .little);
    state.regs.rcx = 0x100;
    state.regs.rdx = 0x301;
    state.regs.r8 = 16;
    state.regs.r9 = 16;
    try std.testing.expect(bridge.dispatch(&state, "vkMapMemory", 0x9876));
    try std.testing.expectEqual(@as(u64, @as(u32, @bitCast(abi.ERROR_MEMORY_MAP_FAILED))), state.regs.rax);
    try std.testing.expectEqual(@as(u32, 300), Driver.maps);
}

test "acquired-image readback hands binary waits to WSI exactly once on the present family" {
    const Capture = struct {
        const Mode = enum { success, no_transfer, submit_failure, invalidate_failure, completion_failure, content, dim_content, uniform_content, present_failure, per_result_failure, present_completion_failure, wrong_acquired_image };
        var mode: Mode = .success;
        var submits: u32 = 0;
        var presents: u32 = 0;
        var idle_calls: u32 = 0;
        var wait_counts: [2]u32 = @splat(99);
        var present_wait_count: u32 = 99;
        var pixels: [16]u8 = .{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };

        fn reset(_: abi.CommandBuffer, _: u32) callconv(.c) abi.Result {
            return abi.SUCCESS;
        }
        fn begin(_: abi.CommandBuffer, _: *const abi.CommandBufferBeginInfo) callconv(.c) abi.Result {
            return abi.SUCCESS;
        }
        fn end(_: abi.CommandBuffer) callconv(.c) abi.Result {
            return abi.SUCCESS;
        }
        fn barrier(_: abi.CommandBuffer, _: u32, _: u32, _: u32, _: u32, _: ?*const anyopaque, _: u32, _: ?*const anyopaque, _: u32, _: ?[*]const abi.ImageMemoryBarrier) callconv(.c) void {}
        fn copy(_: abi.CommandBuffer, _: abi.Image, _: u32, _: abi.Buffer, _: u32, _: [*]const abi.BufferImageCopy) callconv(.c) void {}
        fn submit(queue: abi.Queue, count: u32, info: ?[*]const abi.SubmitInfo, _: abi.Fence) callconv(.c) abi.Result {
            std.debug.assert(@intFromPtr(queue) == 0x302); // present family, NOT graphics queue
            std.debug.assert(count == 1 and submits < 2);
            const record = info.?[0];
            wait_counts[submits] = record.wait_semaphore_count;
            if (record.wait_semaphore_count != 0) {
                std.debug.assert(record.wait_semaphore_count == 2);
                std.debug.assert(record.wait_semaphores.?[0] == 0x901 and record.wait_semaphores.?[1] == 0x902);
                std.debug.assert(record.wait_dst_stage_mask.?[0] == abi.PIPELINE_STAGE_ALL_COMMANDS_BIT);
            }
            submits += 1;
            return if (mode == .submit_failure) abi.ERROR_OUT_OF_HOST_MEMORY else abi.SUCCESS;
        }
        fn idle(_: abi.Queue) callconv(.c) abi.Result {
            idle_calls += 1;
            if (mode == .present_completion_failure and idle_calls == 3) return abi.ERROR_OUT_OF_HOST_MEMORY;
            return if (mode == .completion_failure) abi.ERROR_DEVICE_LOST else abi.SUCCESS;
        }
        fn present(queue: abi.Queue, info: *const abi.PresentInfoKHR) callconv(.c) abi.Result {
            std.debug.assert(@intFromPtr(queue) == 0x302);
            presents += 1;
            present_wait_count = info.wait_semaphore_count;
            for (0..info.swapchain_count) |index| info.results.?[index] = if (mode == .present_failure or mode == .per_result_failure) abi.ERROR_OUT_OF_DATE_KHR else abi.SUCCESS;
            return if (mode == .present_failure) abi.ERROR_OUT_OF_DATE_KHR else abi.SUCCESS;
        }
    };
    for (std.enums.values(Capture.Mode)) |mode| {
        Capture.mode = mode;
        Capture.submits = 0;
        Capture.presents = 0;
        Capture.idle_calls = 0;
        Capture.pixels = .{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
        if (mode == .dim_content or mode == .uniform_content) {
            Capture.pixels = .{ 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255 };
            if (mode == .dim_content) Capture.pixels[4] = 1;
        }
        Capture.wait_counts = @splat(99);
        Capture.present_wait_count = 99;
        var state = ElfState.init(std.testing.allocator);
        defer state.deinit();
        var bridge = Bridge{};
        defer bridge.deinit();
        const forwarder = &bridge.forwarder;
        // Use a virtual loader fixture; no host Vulkan provider is opened.
        bridge.library_token = 1;
        forwarder.guest_libraries[0] = .{ .token = 1, .virtual_vulkan = true };
        forwarder.real_vulkan.device = @ptrFromInt(0x100);
        forwarder.real_vulkan.graphics_queue = @ptrFromInt(0x301);
        forwarder.real_vulkan.graphics_queue_family_index = 0;
        forwarder.real_vulkan.queue_family_count = 2;
        forwarder.real_vulkan.queue_family_properties[1] = .{ .queue_flags = abi.QUEUE_GRAPHICS_BIT, .queue_count = 1 };
        forwarder.real_vulkan.queue_map[0] = .{ .synthetic = 0x302, .real = 0x302 };
        forwarder.real_vulkan.queue_family_indices[0] = 1;
        forwarder.real_vulkan.semaphore_map[0] = .{ .synthetic = 0x801, .real = 0x901 };
        forwarder.real_vulkan.semaphore_map[1] = .{ .synthetic = 0x802, .real = 0x902 };
        forwarder.pixel_probe.staging_buffer = 0x501;
        forwarder.pixel_probe.staging_memory = 0x502;
        forwarder.pixel_probe.staging_size = 16;
        forwarder.pixel_probe.mapped = &Capture.pixels;
        forwarder.pixel_probe.mapped_coherent = mode != .invalidate_failure;
        forwarder.pixel_probe.command_pool = 0x503;
        forwarder.pixel_probe.command_pool_family = 1;
        forwarder.pixel_probe.command_buffer = @ptrFromInt(0x504);
        forwarder.pixel_probe.capture_configured = true;
        forwarder.pixel_probe.capture_enabled = false;
        forwarder.pixel_probe.preview_enabled = false;
        forwarder.real_vulkan.fn_ptrs.reset_command_buffer = Capture.reset;
        forwarder.real_vulkan.fn_ptrs.begin_command_buffer = Capture.begin;
        forwarder.real_vulkan.fn_ptrs.end_command_buffer = Capture.end;
        forwarder.real_vulkan.fn_ptrs.cmd_pipeline_barrier = Capture.barrier;
        forwarder.real_vulkan.fn_ptrs.cmd_copy_image_to_buffer = Capture.copy;
        forwarder.real_vulkan.fn_ptrs.queue_submit = Capture.submit;
        forwarder.real_vulkan.fn_ptrs.queue_wait_idle = Capture.idle;
        forwarder.real_vulkan.fn_ptrs.queue_present = Capture.present;
        const present_info = state.mem_base + 0x2000;
        const waits = present_info + 0x100;
        const swapchains = present_info + 0x120;
        const indices = present_info + 0x140;
        for (0..2) |index| {
            const offset: u64 = @intCast(index);
            forwarder.real_vulkan.swapchain_map[index] = .{ .synthetic = 0x601 + offset, .real = 0x701 + offset };
            forwarder.real_vulkan.image_map[index] = .{ .synthetic = 0xa01 + offset, .real = 0xb01 + offset };
            forwarder.real_vulkan.swapchain_records[index] = .{ .synthetic = 0x601 + offset, .real = 0x701 + offset, .image_count = 1 };
            forwarder.real_vulkan.swapchain_records[index].image_handles[0] = 0xa01 + offset;
            forwarder.present_chain.noteSwapchain(.{
                .handle = 0x701 + offset,
                .width = 2,
                .height = 2,
                .format = 37,
                .image_count = 1,
                .image_usage = if (mode == .no_transfer) 0 else abi.IMAGE_USAGE_TRANSFER_SRC_BIT,
            });
            if (@intFromEnum(mode) >= @intFromEnum(Capture.Mode.content)) {
                // Native identities in the command ledger, guest identities
                // in the mapped readback packet. The actual bridge must join
                // both before opening picture frame one.
                const native_images = [_]u64{ 0xb01 + offset, 0xc01 + offset };
                forwarder.present_chain.noteSwapchainImages(0x701 + offset, &native_images);
                forwarder.present_chain.noteAcquire(0x701 + offset, if (mode == .wrong_acquired_image) 1 else 0);
                forwarder.present_chain.noteContent(0x701 + offset);
            }
            state.write64(waits + offset * 8, 0x801 + offset);
            state.write64(swapchains + offset * 8, 0x601 + offset);
            state.write32(indices + offset * 4, 0);
        }
        state.write32(present_info, 1000001001);
        state.write32(present_info + 16, 2);
        state.write64(present_info + 24, waits);
        state.write32(present_info + 32, 2);
        state.write64(present_info + 40, swapchains);
        state.write64(present_info + 48, indices);
        state.regs.rcx = 0x302;
        state.regs.rdx = present_info;
        state.regs.rsp = state.mem_base + 0x1000;
        try std.testing.expect(bridge.dispatch(&state, "vkQueuePresentKHR", 0x9876));
        // The guest structure is unchanged: only the native wait responsibility moves.
        try std.testing.expectEqual(@as(u32, 2), state.read32(present_info + 16));
        if (mode == .completion_failure) {
            try std.testing.expectEqual(@as(u32, 0), Capture.presents);
            try std.testing.expectEqual(@as(u32, 1), Capture.submits);
            try std.testing.expectEqual(@as(u64, @as(u32, @bitCast(abi.ERROR_DEVICE_LOST))), state.regs.rax);
        } else {
            try std.testing.expectEqual(@as(u32, 1), Capture.presents);
            const original_waits = mode == .no_transfer or mode == .submit_failure;
            try std.testing.expectEqual(@as(u32, if (original_waits) 2 else 0), Capture.present_wait_count);
            if (mode != .no_transfer) {
                try std.testing.expectEqual(@as(u32, 2), Capture.submits);
                try std.testing.expectEqual(@as(u32, 2), Capture.wait_counts[0]);
                try std.testing.expectEqual(@as(u32, if (mode == .submit_failure) 2 else 0), Capture.wait_counts[1]);
            }
        }
        if (mode == .success) {
            try std.testing.expectEqual(@as(u64, 2), forwarder.pixel_probe.successes);
            try std.testing.expectEqual(@as(u64, 1), forwarder.pixel_probe.readback_wait_handoffs);
            try std.testing.expectEqual(@as(u64, 4), forwarder.pixel_probe.capture_last_stats.bright_pixels);
            try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_real_present_completions);
        }
        const opens_picture = mode == .content or mode == .dim_content;
        try std.testing.expectEqual(@as(u64, if (opens_picture) 1 else 0), forwarder.picture_sequence.frames);
        if (opens_picture) {
            try std.testing.expectEqual(@as(u64, 1), forwarder.picture_sequence.first_present);
            try std.testing.expectEqual(@as(u64, 0xa01), forwarder.picture_sequence.first_image);
            // Two swapchains in one native request are one content tick.
            try std.testing.expectEqual(@as(u64, 1), forwarder.picture_sequence.last_present);
        }
    }
}

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

test "PE descriptor updates respect ignored members and commit only admitted native writes" {
    const Capture = struct {
        var calls: u32 = 0;
        var sets: [2]u64 = @splat(0);
        var infos: [2]abi.DescriptorImageInfo = @splat(.{});
        var inactive_pointers_cleared: bool = false;
        fn update(_: abi.Device, count: u32, writes: ?[*]const abi.WriteDescriptorSet, copies: u32, _: ?[*]const abi.CopyDescriptorSet) callconv(.c) void {
            std.debug.assert(count == 2 and copies == 0);
            calls += 1;
            for (0..2) |index| {
                sets[index] = writes.?[index].dst_set;
                infos[index] = writes.?[index].image_info.?[0];
            }
            inactive_pointers_cleared = writes.?[0].buffer_info == null and writes.?[0].texel_buffer_view == null;
        }
    };
    Capture.calls = 0;
    var state = ElfState.init(std.testing.allocator);
    defer state.deinit();
    var bridge = Bridge{};
    defer bridge.deinit();
    bridge.library_token = 1;
    const forwarder = &bridge.forwarder;
    forwarder.guest_libraries[0] = .{ .token = 1, .virtual_vulkan = true };
    forwarder.real_vulkan.device = @ptrFromInt(0x100);
    forwarder.real_vulkan.fn_ptrs.update_descriptor_sets = Capture.update;
    forwarder.real_vulkan.descriptor_set_map[0] = .{ .synthetic = 0x301, .real = 0x401 };
    forwarder.real_vulkan.descriptor_set_map[1] = .{ .synthetic = 0x302, .real = 0x402 };
    forwarder.real_vulkan.image_view_map[0] = .{ .synthetic = 0x501, .real = 0x601 };
    forwarder.real_vulkan.sampler_map[0] = .{ .synthetic = 0x701, .real = 0x801 };
    forwarder.tracked_image_views[0] = .{ .synthetic = 0x501, .image = 0xa01 };
    const writes_address = state.mem_base + 0x2000;
    const infos_address = writes_address + 0x100;
    const infos = [_]abi.DescriptorImageInfo{
        .{ .sampler = 0xdead, .image_view = 0x501, .image_layout = 5 }, // sampled image ignores sampler
        .{ .sampler = 0x701, .image_view = 0xdead, .image_layout = 0xdead }, // sampler ignores image
    };
    var writes = [_]abi.WriteDescriptorSet{
        .{ .s_type = 35, .dst_set = 0x301, .descriptor_count = 1, .descriptor_type = 2, .image_info = @ptrFromInt(infos_address), .buffer_info = @ptrFromInt(0xdead0), .texel_buffer_view = @ptrFromInt(0xdead0) },
        .{ .s_type = 35, .dst_set = 0x302, .descriptor_count = 1, .descriptor_type = 0, .image_info = @ptrFromInt(infos_address + @sizeOf(abi.DescriptorImageInfo)) },
    };
    @memcpy(state.guestMemory(infos_address, @sizeOf(@TypeOf(infos))).?, std.mem.asBytes(&infos));
    state.regs.rsp = state.mem_base + 0x1000;
    state.write64(state.regs.rsp + 0x28, 0);
    for (0..2) |attempt| {
        if (attempt == 1) writes[1].dst_set = 0xbad;
        @memcpy(state.guestMemory(writes_address, @sizeOf(@TypeOf(writes))).?, std.mem.asBytes(&writes));
        state.regs.rcx = 0x100;
        state.regs.rdx = 2;
        state.regs.r8 = writes_address;
        state.regs.r9 = 0;
        try std.testing.expect(bridge.dispatch(&state, "vkUpdateDescriptorSets", 0x9876));
        try std.testing.expectEqual(@as(u32, 1), Capture.calls);
        try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_descriptor_update_forwarded);
        try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_descriptor_image_infos_observed);
    }
    try std.testing.expectEqual([2]u64{ 0x401, 0x402 }, Capture.sets);
    try std.testing.expectEqual(@as(u64, 0), Capture.infos[0].sampler);
    try std.testing.expectEqual(@as(u64, 0x601), Capture.infos[0].image_view);
    try std.testing.expectEqual(@as(u64, 0x801), Capture.infos[1].sampler);
    try std.testing.expectEqual(@as(u64, 0), Capture.infos[1].image_view);
    try std.testing.expect(Capture.inactive_pointers_cleared);
    try std.testing.expectEqual(@as(u64, 2), forwarder.vulkan_descriptor_native_writes);
}

test "PE descriptor binding translates Microsoft stack arguments to native Vulkan" {
    const Capture = struct {
        var calls: u32 = 0;
        var command_buffer: usize = 0;
        var pipeline_bind_point: u32 = 0;
        var layout: u64 = 0;
        var first_set: u32 = 0;
        var set_count: u32 = 0;
        var dynamic_count: u32 = 0;
        var dynamic_pointer: usize = 0;
        var sets: [2]u64 = @splat(0);
        var dynamic_offsets: [2]u32 = @splat(0);

        fn bind(
            captured_command_buffer: ?*anyopaque,
            captured_pipeline_bind_point: u32,
            captured_layout: u64,
            captured_first_set: u32,
            descriptor_set_count: u32,
            captured_sets: [*]const u64,
            dynamic_offset_count: u32,
            captured_dynamic_offsets: ?[*]const u32,
        ) callconv(.c) void {
            calls += 1;
            command_buffer = @intFromPtr(captured_command_buffer);
            pipeline_bind_point = captured_pipeline_bind_point;
            layout = captured_layout;
            first_set = captured_first_set;
            set_count = descriptor_set_count;
            dynamic_count = dynamic_offset_count;
            dynamic_pointer = @intFromPtr(captured_dynamic_offsets);
            if (descriptor_set_count <= sets.len) {
                @memcpy(sets[0..descriptor_set_count], captured_sets[0..descriptor_set_count]);
            }
            if (dynamic_offset_count == dynamic_offsets.len) {
                dynamic_offsets = captured_dynamic_offsets.?[0..dynamic_offsets.len].*;
            }
        }
    };

    Capture.calls = 0;
    Capture.command_buffer = 0;
    Capture.pipeline_bind_point = 0;
    Capture.layout = 0;
    Capture.first_set = 0;
    Capture.set_count = 0;
    Capture.dynamic_count = 0;
    Capture.dynamic_pointer = 0;
    Capture.sets = @splat(0);
    Capture.dynamic_offsets = @splat(0);

    var state = ElfState.init(std.testing.allocator);
    defer state.deinit();
    var bridge = Bridge{};
    defer bridge.deinit();

    const synthetic_command_buffer: u64 = 0x111;
    const synthetic_layout: u64 = 0x222;
    const synthetic_sets = [_]u64{ 0x331, 0x332 };
    const real_sets = [_]u64{ 0x441, 0x442 };
    const dynamic_offsets = [_]u32{ 0x51, 0x52 };
    bridge.forwarder.real_vulkan.command_buffer_map[0] = .{
        .synthetic = synthetic_command_buffer,
        .real = 0x551,
    };
    bridge.forwarder.real_vulkan.pipeline_layout_map[0] = .{
        .synthetic = synthetic_layout,
        .real = 0x661,
    };
    for (synthetic_sets, real_sets, 0..) |synthetic, real, index| {
        bridge.forwarder.real_vulkan.descriptor_set_map[index] = .{
            .synthetic = synthetic,
            .real = real,
        };
    }
    bridge.forwarder.real_vulkan.fn_ptrs.cmd_bind_descriptor_sets = Capture.bind;

    const guest_sets = state.guestAlloc(@sizeOf(@TypeOf(synthetic_sets)), @alignOf(u64)).?;
    for (synthetic_sets, 0..) |set, index| state.write64(guest_sets + index * 8, set);
    const guest_dynamic_offsets = state.guestAlloc(@sizeOf(@TypeOf(dynamic_offsets)), @alignOf(u32)).?;
    for (dynamic_offsets, 0..) |offset, index| state.write32(guest_dynamic_offsets + index * 4, offset);
    const windows_stack = state.guestAlloc(128, 16).?;
    const return_rip: u64 = 0x9876;
    state.write64(windows_stack, return_rip);

    // Microsoft x64 arguments 1..4 are registers. Arguments 5..8 follow the
    // return address and 32-byte shadow space at rsp+0x28 through rsp+0x40.
    state.regs.rcx = synthetic_command_buffer;
    state.regs.rdx = 0x1234_5678_0000_0000;
    state.regs.r8 = synthetic_layout;
    state.regs.r9 = 0xDEAD_BEEF_0000_0003;
    state.regs.rsp = windows_stack;
    // A DWORD store does not initialize the upper half of its eight-byte
    // argument slot. Reproduce the exact 0x1_00000002 / dirty zero shape in
    // the September 16 run instead of accidentally zeroing it with write64.
    state.write64(windows_stack + 40, 0x0000_0001_0000_0000);
    state.write32(windows_stack + 40, synthetic_sets.len);
    state.write64(windows_stack + 48, guest_sets);
    state.write64(windows_stack + 56, 0x0000_0800_0000_0000);
    state.write32(windows_stack + 56, dynamic_offsets.len);
    state.write64(windows_stack + 64, guest_dynamic_offsets);

    try std.testing.expect(bridge.dispatch(&state, "vkCmdBindDescriptorSets", null));
    try std.testing.expectEqual(@as(u32, 1), Capture.calls);
    try std.testing.expectEqual(@as(usize, 0x551), Capture.command_buffer);
    try std.testing.expectEqual(@as(u32, 0), Capture.pipeline_bind_point);
    try std.testing.expectEqual(@as(u64, 0x661), Capture.layout);
    try std.testing.expectEqual(@as(u32, 3), Capture.first_set);
    try std.testing.expectEqual(@as(u32, 2), Capture.set_count);
    try std.testing.expectEqual(@as(u32, 2), Capture.dynamic_count);
    try std.testing.expectEqualDeep(real_sets, Capture.sets);
    try std.testing.expectEqualDeep(dynamic_offsets, Capture.dynamic_offsets);
    try std.testing.expectEqual(return_rip, state.regs.rip);
    try std.testing.expectEqual(@as(u64, 1), bridge.forwarder.vulkan_descriptor_bind_calls);
    try std.testing.expectEqual(@as(u64, synthetic_sets.len), bridge.forwarder.vulkan_descriptor_sets_bound);
    try std.testing.expectEqual(@as(u64, 1), bridge.forwarder.vulkan_descriptor_bind_admission.entries);
    try std.testing.expectEqual(@as(u64, 1), bridge.forwarder.vulkan_descriptor_bind_admission.forwarded);
    try std.testing.expectEqual(@as(u64, 0), bridge.forwarder.vulkan_descriptor_bind_admission.rejected);

    // The import callback shortcut has no pushed return address. The same
    // typed-width rule must also turn a dirty dynamic-count zero into NULL.
    state.regs.rcx = synthetic_command_buffer;
    state.regs.rdx = 0;
    state.regs.r8 = synthetic_layout;
    state.regs.r9 = 0;
    state.regs.rsp = windows_stack;
    state.write64(windows_stack + 32, 0xBEEF_CAFE_0000_0001);
    state.write64(windows_stack + 40, guest_sets);
    state.write64(windows_stack + 48, 0x0000_0800_0000_0000);
    state.write64(windows_stack + 56, 0xDEAD);
    try std.testing.expect(bridge.dispatch(&state, "vkCmdBindDescriptorSets", return_rip));
    try std.testing.expectEqual(@as(u32, 2), Capture.calls);
    try std.testing.expectEqual(@as(u32, 1), Capture.set_count);
    try std.testing.expectEqual(@as(u32, 0), Capture.dynamic_count);
    try std.testing.expectEqual(@as(usize, 0), Capture.dynamic_pointer);
    try std.testing.expectEqual(windows_stack, state.regs.rsp);
    try std.testing.expectEqual(return_rip, state.regs.rip);

    // A missing native layout used to be indistinguishable from a successful
    // void command. Keep the guest alive, but prove that the native call and
    // the PE graphics-success counters are not advanced.
    state.regs.rcx = synthetic_command_buffer;
    state.regs.rdx = 0;
    state.regs.r8 = 0xDEAD;
    state.regs.r9 = 3;
    state.regs.rsp = windows_stack;
    state.write64(windows_stack, return_rip);
    state.write64(windows_stack + 40, synthetic_sets.len);
    state.write64(windows_stack + 48, guest_sets);
    state.write64(windows_stack + 56, dynamic_offsets.len);
    state.write64(windows_stack + 64, guest_dynamic_offsets);
    const native_calls_before_refusal = state.windows_graphics.native_vulkan_calls;
    const commands_before_refusal = state.windows_graphics.command_calls;
    try std.testing.expect(bridge.dispatch(&state, "vkCmdBindDescriptorSets", null));
    try std.testing.expectEqual(@as(u32, 2), Capture.calls);
    try std.testing.expectEqual(@as(u64, 2), bridge.forwarder.vulkan_descriptor_bind_calls);
    try std.testing.expectEqual(@as(u64, 3), bridge.forwarder.vulkan_descriptor_bind_admission.entries);
    try std.testing.expectEqual(@as(u64, 2), bridge.forwarder.vulkan_descriptor_bind_admission.forwarded);
    try std.testing.expectEqual(@as(u64, 1), bridge.forwarder.vulkan_descriptor_bind_admission.rejected);
    try std.testing.expectEqualStrings(
        "pipeline_layout_unmapped",
        @tagName(bridge.forwarder.vulkan_descriptor_bind_admission.last_reason),
    );
    try std.testing.expectEqual(native_calls_before_refusal, state.windows_graphics.native_vulkan_calls);
    try std.testing.expectEqual(commands_before_refusal, state.windows_graphics.command_calls);
    try std.testing.expectEqual(@as(u64, 2), bridge.forwarder.vulkan_real_command_calls);
    try std.testing.expectEqual(@as(u64, 1), bridge.forwarder.vulkan_command_admission_rejected);
}

test "PE barrier DWORD counts normalize across all ten parameters" {
    const Capture = struct {
        var calls: u32 = 0;
        var values: [6]u32 = @splat(0);
        var empty_pointers: bool = false;
        fn barrier(
            _: ?*anyopaque,
            source_stage: u32,
            destination_stage: u32,
            dependency_flags: u32,
            memory_count: u32,
            memory: ?*const anyopaque,
            buffer_count: u32,
            buffers: ?*const anyopaque,
            image_count: u32,
            images: ?[*]const abi.ImageMemoryBarrier,
        ) callconv(.c) void {
            calls += 1;
            values = .{ source_stage, destination_stage, dependency_flags, memory_count, buffer_count, image_count };
            empty_pointers = memory == null and buffers == null and images == null;
        }
    };
    Capture.calls = 0;
    Capture.values = @splat(0);
    Capture.empty_pointers = false;
    var state = ElfState.init(std.testing.allocator);
    defer state.deinit();
    var bridge = Bridge{};
    defer bridge.deinit();
    bridge.forwarder.real_vulkan.command_buffer_map[0] = .{ .synthetic = 0x111, .real = 0x222 };
    bridge.forwarder.real_vulkan.fn_ptrs.cmd_pipeline_barrier = Capture.barrier;
    const stack = state.guestAlloc(128, 16).?;
    state.regs.rcx = 0x111;
    state.regs.rdx = 0xDEAD_BEEF_0000_0001;
    state.regs.r8 = 0xCAFE_BEEF_0000_0002;
    state.regs.r9 = 0xDEAD_BEEF_0000_0000;
    state.regs.rsp = stack;
    // Zero counts have dirty upper halves and deliberately invalid pointers.
    // Only zero counts are normalized; their unused arrays must stay NULL.
    for ([_]u64{ 32, 48, 64 }) |offset| state.write64(stack + offset, 0x0000_0800_0000_0000);
    for ([_]u64{ 40, 56, 72 }) |offset| state.write64(stack + offset, 0xDEAD);
    try std.testing.expect(bridge.dispatch(&state, "vkCmdPipelineBarrier", 0x9876));
    try std.testing.expectEqual(@as(u32, 1), Capture.calls);
    try std.testing.expectEqualDeep([_]u32{ 1, 2, 0, 0, 0, 0 }, Capture.values);
    try std.testing.expect(Capture.empty_pointers);
    try std.testing.expectEqual(@as(u64, 6), bridge.scalar_width_normalizations);
    try std.testing.expectEqual(@as(u64, 1), bridge.forwarder.vulkan_real_command_calls);
    try std.testing.expectEqual(@as(u64, 0), bridge.forwarder.vulkan_command_admission_rejected);
}

test "PE indexed draw preserves signed DWORDs and legitimate large uint32 counts" {
    const Capture = struct {
        var calls: u32 = 0;
        var count: u32 = 0;
        var vertex_offset: i32 = 0;
        var first_instance: u32 = 0;
        fn draw(_: ?*anyopaque, index_count: u32, _: u32, _: u32, offset: i32, instance: u32) callconv(.c) void {
            calls += 1;
            count = index_count;
            vertex_offset = offset;
            first_instance = instance;
        }
    };
    Capture.calls = 0;
    var state = ElfState.init(std.testing.allocator);
    defer state.deinit();
    var bridge = Bridge{};
    defer bridge.deinit();
    bridge.forwarder.real_vulkan.command_buffer_map[0] = .{ .synthetic = 0x111, .real = 0x222 };
    bridge.forwarder.real_vulkan.fn_ptrs.cmd_draw_indexed = Capture.draw;
    const stack = state.guestAlloc(128, 16).?;
    state.regs.rcx = 0x111;
    state.regs.rdx = 0xCAFE_BEEF_F000_0000;
    state.regs.r8 = 0xDEAD_BEEF_0000_0001;
    state.regs.r9 = 0xDEAD_BEEF_0000_0002;
    state.regs.rsp = stack;
    state.write64(stack + 32, 0xCAFE_BEEF_FFFF_FFFD);
    state.write64(stack + 40, 0xDEAD_BEEF_0000_0004);
    try std.testing.expect(bridge.dispatch(&state, "vkCmdDrawIndexed", 0x9876));
    try std.testing.expectEqual(@as(u32, 1), Capture.calls);
    try std.testing.expectEqual(@as(u32, 0xF000_0000), Capture.count);
    try std.testing.expectEqual(@as(i32, -3), Capture.vertex_offset);
    try std.testing.expectEqual(@as(u32, 4), Capture.first_instance);
    try std.testing.expectEqual(@as(u64, 1), bridge.forwarder.vulkan_command_draw_calls);
}

test "PE rejected void commands cannot inflate native or graphics health counters" {
    const Capture = struct {
        var calls: u32 = 0;
        fn draw(_: ?*anyopaque, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {
            calls += 1;
        }
    };
    Capture.calls = 0;
    var state = ElfState.init(std.testing.allocator);
    defer state.deinit();
    var bridge = Bridge{};
    defer bridge.deinit();
    bridge.forwarder.real_vulkan.command_buffer_map[0] = .{ .synthetic = 0x111, .real = 0x222 };
    const stack = state.guestAlloc(128, 16).?;
    state.regs.rcx = 0x111;
    state.regs.rdx = 3;
    state.regs.r8 = 1;
    state.regs.r9 = 0;
    state.regs.rsp = stack;
    state.write64(stack + 32, 0);
    // Mapped command buffer, absent native entry point: thunk handling is not
    // driver invocation, even though this void API returns no VkResult.
    try std.testing.expect(bridge.dispatch(&state, "vkCmdDraw", 0x9876));
    try std.testing.expectEqual(@as(u64, 0), bridge.forwarder.vulkan_real_command_calls);
    try std.testing.expectEqual(@as(u64, 0), state.windows_graphics.native_vulkan_calls);
    try std.testing.expectEqual(@as(u64, 0), state.windows_graphics.command_calls);
    var saw_missing_entry_point = false;
    for (bridge.forwarder.vulkan_command_admission) |record| {
        if (record.rejected != 0) saw_missing_entry_point = std.mem.eql(u8, @tagName(record.last_reason), "native_entry_point_missing");
    }
    try std.testing.expect(saw_missing_entry_point);

    bridge.forwarder.real_vulkan.fn_ptrs.cmd_draw = Capture.draw;
    try std.testing.expect(bridge.dispatch(&state, "vkCmdDraw", 0x9876));
    try std.testing.expectEqual(@as(u32, 1), Capture.calls);
    try std.testing.expectEqual(@as(u64, 1), bridge.forwarder.vulkan_real_command_calls);
    try std.testing.expectEqual(@as(u64, 1), state.windows_graphics.native_vulkan_calls);
    try std.testing.expectEqual(@as(u64, 1), state.windows_graphics.command_calls);

    state.regs.rcx = 0xDEAD;
    try std.testing.expect(bridge.dispatch(&state, "vkCmdDraw", 0x9876));
    try std.testing.expectEqual(@as(u32, 1), Capture.calls);
    try std.testing.expectEqual(@as(u64, 1), bridge.forwarder.vulkan_real_command_calls);
    try std.testing.expectEqual(@as(u64, 1), state.windows_graphics.native_vulkan_calls);
    try std.testing.expectEqual(@as(u64, 1), state.windows_graphics.command_calls);
    try std.testing.expectEqual(@as(u64, 3), bridge.forwarder.vulkan_command_admission_entries);
    try std.testing.expectEqual(@as(u64, 2), bridge.forwarder.vulkan_command_admission_rejected);
    var saw_unmapped_buffer = false;
    for (bridge.forwarder.vulkan_command_admission) |record| {
        if (record.rejected != 0) {
            saw_unmapped_buffer = std.mem.eql(u8, @tagName(record.last_reason), "command_buffer_unmapped") and
                record.last_arguments[0] == 0xDEAD and record.last_refusal_line != 0;
        }
    }
    try std.testing.expect(saw_unmapped_buffer);
}
