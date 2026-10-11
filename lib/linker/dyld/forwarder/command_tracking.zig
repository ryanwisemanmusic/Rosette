// Split implementation for Forwarder; wrappers keep the public state API stable.
const process = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = process.__ForwarderInternals;
const Forwarder = process.Forwarder;
const DescriptorBindRejectReason = __ForwarderInternals._DescriptorBindRejectReason;
const DescriptorUpdateFailureDetails = __ForwarderInternals._DescriptorUpdateFailureDetails;
const DescriptorUpdateRefusal = __ForwarderInternals._DescriptorUpdateRefusal;
const DescriptorUpdateTemplateRecord = __ForwarderInternals._DescriptorUpdateTemplateRecord;
const GraphicsStateTrace = __ForwarderInternals._GraphicsStateTrace;
const HandleMap = __ForwarderInternals._HandleMap;
const MAX_TRACKED_DESCRIPTOR_IMAGES = __ForwarderInternals._MAX_TRACKED_DESCRIPTOR_IMAGES;
const MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND = __ForwarderInternals._MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND;
const MAX_TRACKED_PASS_EDGES = __ForwarderInternals._MAX_TRACKED_PASS_EDGES;
const MAX_TRACKED_RESOURCE_TRANSFERS = __ForwarderInternals._MAX_TRACKED_RESOURCE_TRANSFERS;
const MAX_TRACKED_TARGET_ATTACHMENTS = __ForwarderInternals._MAX_TRACKED_TARGET_ATTACHMENTS;
const RealHandle = __ForwarderInternals._RealHandle;
const TargetOverflowKind = __ForwarderInternals._TargetOverflowKind;
const TrackedCommandDescriptorSet = __ForwarderInternals._TrackedCommandDescriptorSet;
const TrackedCommandTargets = __ForwarderInternals._TrackedCommandTargets;
const TrackedDescriptorSet = __ForwarderInternals._TrackedDescriptorSet;
const TrackedFramebuffer = __ForwarderInternals._TrackedFramebuffer;
const TrackedImageTransfer = __ForwarderInternals._TrackedImageTransfer;
const TrackedImageView = __ForwarderInternals._TrackedImageView;
const TrackedPassEdge = __ForwarderInternals._TrackedPassEdge;
const TrackedRenderPass = __ForwarderInternals._TrackedRenderPass;
const VK_ATTACHMENT_LOAD_OP_CLEAR = __ForwarderInternals._VK_ATTACHMENT_LOAD_OP_CLEAR;
const WriteKind = __ForwarderInternals._WriteKind;
const abi = __ForwarderInternals._abi;
const frame_content = __ForwarderInternals._frame_content;
const fsi_diagnostics = __ForwarderInternals._fsi_diagnostics;
const gpu_vulkan = __ForwarderInternals._gpu_vulkan;
const guest_context = __ForwarderInternals._guest_context;
const machoCapturePrint = __ForwarderInternals._machoCapturePrint;
const marshal = __ForwarderInternals._marshal;
const rangeContains = __ForwarderInternals._rangeContains;
const rosette_gpu = __ForwarderInternals._rosette_gpu;
const sparseVulkanSuccessLog = __ForwarderInternals._sparseVulkanSuccessLog;
const std = __ForwarderInternals._std;
const vkErrorInitializationFailed = __ForwarderInternals._vkErrorInitializationFailed;
const vkErrorOutOfHostMemory = __ForwarderInternals._vkErrorOutOfHostMemory;
const CommandPassTarget = __ForwarderInternals._CommandPassTarget;
const callNativeVulkanCommand = Forwarder.callNativeVulkanCommand;
const copyGuestBytes = Forwarder.copyGuestBytes;
const copyGuestHandleArray = Forwarder.copyGuestHandleArray;
const copyGuestStructs = Forwarder.copyGuestStructs;
const copyGuestValue = Forwarder.copyGuestValue;
const destroyRealDevice = Forwarder.destroyRealDevice;
const ensureFsiZpdSink = Forwarder.ensureFsiZpdSink;
const findResource = Forwarder.findResource;
const findVulkanMemoryRecord = Forwarder.findVulkanMemoryRecord;
const forgetGraphicsPipeline = Forwarder.forgetGraphicsPipeline;
const forgetPipelineLayout = Forwarder.forgetPipelineLayout;
const forgetRectangleExpandedPipeline = Forwarder.forgetRectangleExpandedPipeline;
const fsiForgetCommandBuffer = Forwarder.fsiForgetCommandBuffer;
const fsiForgetRenderPass = Forwarder.fsiForgetRenderPass;
const fsiResetCommandPool = Forwarder.fsiResetCommandPool;
const graphicsStateTrackingEnabled = Forwarder.graphicsStateTrackingEnabled;
const noteRealVulkanResult = Forwarder.noteRealVulkanResult;
const noteVulkanCommandRefusal = Forwarder.noteVulkanCommandRefusal;
const realDeviceLostResult = Forwarder.realDeviceLostResult;
const releaseResource = Forwarder.releaseResource;
const resetCommandBuffer = Forwarder.resetCommandBuffer;
const trackedGraphicsPipeline = Forwarder.trackedGraphicsPipeline;

pub fn updateDescriptorSetsNative(self: anytype, state: anytype, failure: *DescriptorUpdateFailureDetails) ?DescriptorUpdateRefusal {
    const write_count = guest_context.registers(state).rsi;
    const copy_count = guest_context.registers(state).rcx;
    if (self.real_vulkan.device_lost or !self.real_vulkan.hasDevice() or self.real_vulkan.fn_ptrs.update_descriptor_sets == null) return .no_device;
    if (write_count > 64 or copy_count > 64) return .too_many_writes;
    var writes: [64]abi.WriteDescriptorSet = undefined;
    var copies: [64]abi.CopyDescriptorSet = undefined;
    var images: [256]abi.DescriptorImageInfo = undefined;
    var buffers: [256]abi.DescriptorBufferInfo = undefined;
    var texel_views: [256]u64 = undefined;
    var inline_blocks: [64]abi.WriteDescriptorSetInlineUniformBlock = undefined;
    var inline_data: [64][256]u8 = undefined;
    if (!copyGuestStructs(abi.WriteDescriptorSet, state, guest_context.registers(state).rdx, write_count, &writes)) return .guest_read;
    if (!copyGuestStructs(abi.CopyDescriptorSet, state, guest_context.registers(state).r8, copy_count, &copies)) return .guest_read;
    const fsi_guest_set = if (copy_count == 0 and write_count == 3) writes[0].dst_set else 0;
    const is_fsi_edram_zpd_update = copy_count == 0 and write_count == 3 and
        gpu_vulkan.fsi_descriptor_repair.isSharedMemoryEdramZpdSetUpdate(writes[0..3], fsi_guest_set);
    var fsi_descriptor_evidence: fsi_diagnostics.DescriptorUpdateEvidence = .{
        .update_call = self.vulkan_descriptor_update_calls,
        .guest_set = fsi_guest_set,
    };
    var image_cursor: usize = 0;
    var buffer_cursor: usize = 0;
    var texel_cursor: usize = 0;
    for (writes[0..@as(usize, @intCast(write_count))], 0..) |*write, write_index| {
        const guest_set = write.dst_set;
        const is_fsi_zpd_sink_write = is_fsi_edram_zpd_update and
            gpu_vulkan.fsi_descriptor_repair.isZpdSinkDescriptor(write.*, fsi_guest_set);
        failure.* = .{
            .write_index = @intCast(write_index),
            .descriptor_type = write.descriptor_type,
            .binding = write.dst_binding,
            .descriptor_set = guest_set,
        };
        write.dst_set = self.real_vulkan.realDescriptorSet(guest_set) orelse return .unmapped_set;
        if (is_fsi_edram_zpd_update) fsi_descriptor_evidence.native_set = write.dst_set;
        const count: usize = @intCast(write.descriptor_count);
        if (write.descriptor_type == abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
            if (write.p_next == null or count > inline_data[write_index].len) return .inline_block;
            var block: abi.WriteDescriptorSetInlineUniformBlock = undefined;
            if (!copyGuestValue(abi.WriteDescriptorSetInlineUniformBlock, state, @intFromPtr(write.p_next.?), &block) or
                block.s_type != abi.STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK or
                block.p_next != null or block.data_size != count)
            {
                return .inline_block;
            }
            const data_address = if (block.data) |pointer| @intFromPtr(pointer) else 0;
            if (!copyGuestBytes(state, data_address, count, &inline_data[write_index])) return .guest_read;
            block.p_next = null;
            block.data = if (count == 0) null else @ptrCast(@alignCast(inline_data[write_index][0..].ptr));
            inline_blocks[write_index] = block;
            write.p_next = &inline_blocks[write_index];
            write.image_info = null;
            write.buffer_info = null;
            write.texel_buffer_view = null;
        } else {
            if (write.p_next != null) return .p_next;
            write.p_next = null;
            switch (write.descriptor_type) {
                // Sampler, combined image sampler, sampled image, storage
                // image and input attachment all carry VkDescriptorImageInfo.
                0, 1, 2, 3, 10 => {
                    if (image_cursor + count > images.len) return .array_capacity;
                    const address = if (write.image_info) |pointer| @intFromPtr(pointer) else 0;
                    if (count != 0 and address == 0) return .null_array;
                    if (!copyGuestStructs(abi.DescriptorImageInfo, state, address, count, images[image_cursor..])) return .guest_read;
                    for (images[image_cursor .. image_cursor + count]) |*image| {
                        // Unused members are not required to contain valid
                        // handles (sampled/storage images ignore sampler;
                        // sampler-only descriptors ignore imageView).
                        if (write.descriptor_type == 0 or write.descriptor_type == 1) {
                            if (image.sampler != 0) image.sampler = self.real_vulkan.realSampler(image.sampler) orelse return .unmapped_sampler;
                        } else image.sampler = 0;
                        if (write.descriptor_type != 0) {
                            if (image.image_view != 0) image.image_view = self.real_vulkan.realImageView(image.image_view) orelse return .unmapped_image_view;
                        } else {
                            image.image_view = 0;
                            image.image_layout = 0;
                        }
                    }
                    write.image_info = if (count == 0) null else images[image_cursor..].ptr;
                    write.buffer_info = null;
                    write.texel_buffer_view = null;
                    image_cursor += count;
                },
                // Uniform and storage buffer descriptors carry VkDescriptorBufferInfo.
                6, 7, 8, 9 => {
                    if (buffer_cursor + count > buffers.len) return .array_capacity;
                    const address = if (write.buffer_info) |pointer| @intFromPtr(pointer) else 0;
                    if (count != 0 and address == 0) return .null_array;
                    if (!copyGuestStructs(abi.DescriptorBufferInfo, state, address, count, buffers[buffer_cursor..])) return .guest_read;
                    for (buffers[buffer_cursor .. buffer_cursor + count], 0..) |*buffer, element_index| {
                        const guest_buffer = buffer.buffer;
                        const guest_offset = buffer.offset;
                        const guest_range = buffer.range;
                        var repaired = false;
                        failure.resource = guest_buffer;
                        failure.element_index = @intCast(element_index);
                        const sink_bytes = gpu_vulkan.fsi_descriptor_repair.XENIA_ZPD_COUNTER_SINK_BYTES;
                        if (is_fsi_zpd_sink_write and element_index == 0 and
                            gpu_vulkan.fsi_descriptor_repair.zpdSinkInfoNeedsRepair(
                                guest_buffer != 0 and self.real_vulkan.realBuffer(guest_buffer) != null,
                                buffer.offset,
                                buffer.range,
                            ))
                        {
                            buffer.buffer = self.ensureFsiZpdSink(sink_bytes) orelse return .unmapped_buffer;
                            buffer.offset = 0;
                            buffer.range = sink_bytes;
                            repaired = true;
                            self.fsi_zpd_descriptor_repairs +|= 1;
                            machoCapturePrint(
                                "macho-processor: FSI ZPD descriptor repaired: update_call={d} set=0x{x} binding={d} guest_info(buffer/offset/range)=0x{x}/{d}/{d} replacement_buffer=0x{x} offset=0 range={d}; Xenia's SetupContext reads this VkDescriptorBufferInfo after its scope ends and the compiler dropped its stores, so the shared-memory and EDRAM writes in the same call are forwarded with Xenia's intended zeroed sink\n",
                                .{ self.vulkan_descriptor_update_calls, fsi_guest_set, write.dst_binding, guest_buffer, guest_offset, guest_range, buffer.buffer, sink_bytes },
                            );
                        } else {
                            buffer.buffer = self.real_vulkan.realBuffer(guest_buffer) orelse return .unmapped_buffer;
                        }
                        if (is_fsi_edram_zpd_update and write.dst_binding < 3 and element_index == 0) {
                            const binding_index: usize = @intCast(write.dst_binding);
                            const mask = @as(u8, 1) << @intCast(binding_index);
                            if (fsi_descriptor_evidence.binding_mask & mask == 0) {
                                fsi_descriptor_evidence.binding_mask |= mask;
                                fsi_descriptor_evidence.binding_count += 1;
                            }
                            fsi_descriptor_evidence.bindings[binding_index] = .{
                                .binding = write.dst_binding,
                                .descriptor_count = write.descriptor_count,
                                .guest_buffer = guest_buffer,
                                .native_buffer = buffer.buffer,
                                .guest_offset = guest_offset,
                                .guest_range = guest_range,
                                .offset = buffer.offset,
                                .range = buffer.range,
                                .repaired = repaired,
                            };
                        }
                    }
                    write.buffer_info = if (count == 0) null else buffers[buffer_cursor..].ptr;
                    write.image_info = null;
                    write.texel_buffer_view = null;
                    buffer_cursor += count;
                },
                // Uniform/storage texel buffers carry an array of VkBufferView.
                4, 5 => {
                    if (texel_cursor + count > texel_views.len) return .array_capacity;
                    const address = if (write.texel_buffer_view) |pointer| @intFromPtr(pointer) else 0;
                    if (count != 0 and address == 0) return .null_array;
                    if (!copyGuestStructs(u64, state, address, count, texel_views[texel_cursor..])) return .guest_read;
                    for (texel_views[texel_cursor .. texel_cursor + count]) |*view| {
                        view.* = self.real_vulkan.realBufferView(view.*) orelse return .unmapped_buffer_view;
                    }
                    write.texel_buffer_view = if (count == 0) null else texel_views[texel_cursor..].ptr;
                    write.image_info = null;
                    write.buffer_info = null;
                    texel_cursor += count;
                },
                // Inline uniform blocks have a different pNext-shaped payload;
                // every other descriptor type is intentionally refused rather
                // than sent with a mismatched pointer union.
                else => return .descriptor_type,
            }
        }
    }
    for (copies[0..@as(usize, @intCast(copy_count))]) |*copy| {
        if (copy.p_next != null) return .p_next;
        copy.p_next = null;
        copy.src_set = self.real_vulkan.realDescriptorSet(copy.src_set) orelse return .unmapped_set;
        copy.dst_set = self.real_vulkan.realDescriptorSet(copy.dst_set) orelse return .unmapped_set;
    }
    self.real_vulkan.fn_ptrs.update_descriptor_sets.?(
        self.real_vulkan.device.?,
        @intCast(write_count),
        if (write_count == 0) null else &writes,
        @intCast(copy_count),
        if (copy_count == 0) null else &copies,
    );
    if (self.native_texture_state) |native| {
        for (writes[0..@intCast(write_count)]) |write| native.noteWrite(write);
        for (copies[0..@intCast(copy_count)]) |copy| native.noteCopy(copy);
    }
    if (is_fsi_edram_zpd_update) {
        self.vulkan_fsi_tracker.noteDescriptorUpdate(fsi_descriptor_evidence);
        if (sparseVulkanSuccessLog(self.vulkan_fsi_tracker.descriptor_updates)) {
            const b0 = fsi_descriptor_evidence.bindings[0];
            const b1 = fsi_descriptor_evidence.bindings[1];
            const b2 = fsi_descriptor_evidence.bindings[2];
            machoCapturePrint(
                "macho-processor: Vulkan FSI DESCRIPTOR UPDATE: call={d} guest_set=0x{x} native_set=0x{x} bindings={d}/3 mask=0x{x} b0(guest/native/offset/range/count)=0x{x}/0x{x}/{d}/{d}/{d} b1=0x{x}/0x{x}/{d}/{d}/{d} b2=0x{x}/0x{x}/{d}/{d}/{d} zpd_repaired={}; only fully admitted writes reach the driver, and this tuple identifies the EDRAM inputs consumed by later FSI draws\n",
                .{ fsi_descriptor_evidence.update_call, fsi_descriptor_evidence.guest_set, fsi_descriptor_evidence.native_set, fsi_descriptor_evidence.binding_count, fsi_descriptor_evidence.binding_mask, b0.guest_buffer, b0.native_buffer, b0.offset, b0.range, b0.descriptor_count, b1.guest_buffer, b1.native_buffer, b1.offset, b1.range, b1.descriptor_count, b2.guest_buffer, b2.native_buffer, b2.offset, b2.range, b2.descriptor_count, b2.repaired },
            );
        }
    }
    self.vulkan_descriptor_update_forwarded +|= 1;
    self.vulkan_descriptor_native_writes +|= write_count;
    self.vulkan_descriptor_native_copies +|= copy_count;
    // Commit provenance only AFTER complete admission and the native
    // call. A refused later write must not make earlier writes appear
    // installed. Re-read original guest identities, not translated ones.
    if (copyGuestStructs(abi.WriteDescriptorSet, state, guest_context.registers(state).rdx, write_count, &writes) and
        copyGuestStructs(abi.CopyDescriptorSet, state, guest_context.registers(state).r8, copy_count, &copies))
    {
        self.trackDescriptorImageWrites(state, writes[0..@as(usize, @intCast(write_count))]);
        self.trackTexelDescriptorWrites(state, writes[0..@as(usize, @intCast(write_count))]);
        self.trackDescriptorSetCopies(copies[0..@as(usize, @intCast(copy_count))]);
    }
    self.vulkan_tiers.note(.descriptor_set, .real);
    return null;
}

pub fn forwardPushDescriptorSet(self: anytype, state: anytype, command_buffer: abi.CommandBuffer) void {
    const function = self.real_vulkan.fn_ptrs.cmd_push_descriptor_set orelse return self.noteVulkanCommandRefusal(@src().line);
    const count = guest_context.registers(state).r8;
    if (count > 64) return self.noteVulkanCommandRefusal(@src().line);
    var writes: [64]abi.WriteDescriptorSet = undefined;
    var images: [256]abi.DescriptorImageInfo = undefined;
    var buffers: [256]abi.DescriptorBufferInfo = undefined;
    var texel_views: [256]u64 = undefined;
    var inline_blocks: [64]abi.WriteDescriptorSetInlineUniformBlock = undefined;
    var inline_data: [64][256]u8 = undefined;
    if (!copyGuestStructs(abi.WriteDescriptorSet, state, guest_context.registers(state).r9, count, &writes)) return self.noteVulkanCommandRefusal(@src().line);
    self.noteCommandDescriptorImages(state, guest_context.registers(state).rdi, writes[0..@as(usize, @intCast(count))]);
    var image_cursor: usize = 0;
    var buffer_cursor: usize = 0;
    var texel_cursor: usize = 0;
    for (writes[0..@as(usize, @intCast(count))], 0..) |*write, write_index| {
        if (write.s_type != abi.WriteDescriptorSet_structure_type) return self.noteVulkanCommandRefusal(@src().line);
        // The push-descriptor command supplies the destination layout/set
        // separately; dstSet in each write is ignored by Vulkan.
        write.dst_set = 0;
        const descriptor_count: usize = @intCast(write.descriptor_count);
        if (write.descriptor_type == abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
            if (write.p_next == null or descriptor_count > inline_data[write_index].len) return self.noteVulkanCommandRefusal(@src().line);
            var block: abi.WriteDescriptorSetInlineUniformBlock = undefined;
            if (!copyGuestValue(abi.WriteDescriptorSetInlineUniformBlock, state, @intFromPtr(write.p_next.?), &block) or
                block.s_type != abi.STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK or
                block.p_next != null or block.data_size != descriptor_count)
            {
                return self.noteVulkanCommandRefusal(@src().line);
            }
            const data_address = if (block.data) |pointer| @intFromPtr(pointer) else 0;
            if (!copyGuestBytes(state, data_address, descriptor_count, &inline_data[write_index])) return self.noteVulkanCommandRefusal(@src().line);
            block.p_next = null;
            block.data = if (descriptor_count == 0) null else @ptrCast(@alignCast(inline_data[write_index][0..].ptr));
            inline_blocks[write_index] = block;
            write.p_next = &inline_blocks[write_index];
            write.image_info = null;
            write.buffer_info = null;
            write.texel_buffer_view = null;
        } else {
            if (write.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
            switch (write.descriptor_type) {
                0, 1, 2, 3, 10 => {
                    if (image_cursor + descriptor_count > images.len) return self.noteVulkanCommandRefusal(@src().line);
                    const address = if (write.image_info) |pointer| @intFromPtr(pointer) else 0;
                    if (descriptor_count != 0 and address == 0) return self.noteVulkanCommandRefusal(@src().line);
                    if (!copyGuestStructs(abi.DescriptorImageInfo, state, address, descriptor_count, images[image_cursor..])) return self.noteVulkanCommandRefusal(@src().line);
                    for (images[image_cursor .. image_cursor + descriptor_count]) |*image| {
                        if (image.sampler != 0) image.sampler = self.real_vulkan.realSampler(image.sampler) orelse return self.noteVulkanCommandRefusal(@src().line);
                        if (image.image_view != 0) image.image_view = self.real_vulkan.realImageView(image.image_view) orelse return self.noteVulkanCommandRefusal(@src().line);
                    }
                    write.image_info = if (descriptor_count == 0) null else images[image_cursor..].ptr;
                    image_cursor += descriptor_count;
                },
                4, 5 => {
                    if (texel_cursor + descriptor_count > texel_views.len) return self.noteVulkanCommandRefusal(@src().line);
                    const address = if (write.texel_buffer_view) |pointer| @intFromPtr(pointer) else 0;
                    if (descriptor_count != 0 and address == 0) return self.noteVulkanCommandRefusal(@src().line);
                    if (!copyGuestStructs(u64, state, address, descriptor_count, texel_views[texel_cursor..])) return self.noteVulkanCommandRefusal(@src().line);
                    for (texel_views[texel_cursor .. texel_cursor + descriptor_count]) |*view|
                        view.* = self.real_vulkan.realBufferView(view.*) orelse return self.noteVulkanCommandRefusal(@src().line);
                    write.texel_buffer_view = if (descriptor_count == 0) null else texel_views[texel_cursor..].ptr;
                    texel_cursor += descriptor_count;
                },
                6, 7, 8, 9 => {
                    if (buffer_cursor + descriptor_count > buffers.len) return self.noteVulkanCommandRefusal(@src().line);
                    const address = if (write.buffer_info) |pointer| @intFromPtr(pointer) else 0;
                    if (descriptor_count != 0 and address == 0) return self.noteVulkanCommandRefusal(@src().line);
                    if (!copyGuestStructs(abi.DescriptorBufferInfo, state, address, descriptor_count, buffers[buffer_cursor..])) return self.noteVulkanCommandRefusal(@src().line);
                    for (buffers[buffer_cursor .. buffer_cursor + descriptor_count]) |*buffer|
                        buffer.buffer = self.real_vulkan.realBuffer(buffer.buffer) orelse return self.noteVulkanCommandRefusal(@src().line);
                    write.buffer_info = if (descriptor_count == 0) null else buffers[buffer_cursor..].ptr;
                    buffer_cursor += descriptor_count;
                },
                else => return,
            }
            write.p_next = null;
        }
    }
    const layout = self.real_vulkan.realPipelineLayout(guest_context.registers(state).rdx) orelse return self.noteVulkanCommandRefusal(@src().line);
    self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), layout, @intCast(guest_context.registers(state).rcx), @intCast(count), &writes });
    self.vulkan_descriptor_push_calls +|= 1;
    self.vulkan_tiers.note(.descriptor_set, .real);
}

pub fn pipelineCachePath(self: anytype) ?[]const u8 {
    if (!self.vulkan_pipeline_cache_path_checked) {
        self.vulkan_pipeline_cache_path_checked = true;
        if (std.c.getenv("ROSETTE_VULKAN_PIPELINE_CACHE")) |raw| {
            const value = std.mem.sliceTo(raw, 0);
            if (value.len != 0 and value.len < self.vulkan_pipeline_cache_path.len) {
                @memcpy(self.vulkan_pipeline_cache_path[0..value.len], value);
                self.vulkan_pipeline_cache_path_len = @intCast(value.len);
            }
        }
    }
    if (self.vulkan_pipeline_cache_path_len == 0) return null;
    return self.vulkan_pipeline_cache_path[0..self.vulkan_pipeline_cache_path_len];
}

pub fn readPipelineCacheFile(self: anytype, destination: []u8) usize {
    const path = self.pipelineCachePath() orelse return 0;
    var path_z: [1024 + 1]u8 = [_]u8{0} ** (1024 + 1);
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;
    var flags: std.c.O = .{};
    flags.ACCMODE = .RDONLY;
    const fd = std.c.open(@ptrCast(&path_z), flags, @as(std.c.mode_t, 0));
    if (fd < 0) return 0;
    defer _ = std.c.close(fd);
    var total: usize = 0;
    while (total < destination.len) {
        const amount = std.c.read(fd, destination.ptr + total, destination.len - total);
        if (amount <= 0) break;
        total += @intCast(amount);
    }
    if (total != 0) self.vulkan_pipeline_cache_loads +|= 1;
    return total;
}

pub fn savePipelineCacheFile(self: anytype, data: []const u8) void {
    const path = self.pipelineCachePath() orelse return;
    if (data.len == 0 or data.len > marshal.scratch_bytes) return;
    var path_z: [1024 + 1]u8 = [_]u8{0} ** (1024 + 1);
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;
    var flags: std.c.O = .{};
    flags.ACCMODE = .WRONLY;
    flags.CREAT = true;
    flags.TRUNC = true;
    const fd = std.c.open(@ptrCast(&path_z), flags, @as(std.c.mode_t, 0o600));
    if (fd < 0) return;
    defer _ = std.c.close(fd);
    var written: usize = 0;
    while (written < data.len) {
        const amount = std.c.write(fd, data.ptr + written, data.len - written);
        if (amount <= 0) return;
        written += @intCast(amount);
    }
    self.vulkan_pipeline_cache_saves +|= 1;
}

pub fn persistPipelineCache(self: anytype, cache: abi.PipelineCache) void {
    if (self.real_vulkan.device_lost) return;
    if (self.pipelineCachePath() == null) return;
    const get_data = self.real_vulkan.fn_ptrs.get_pipeline_cache_data orelse return;
    var data: [marshal.scratch_bytes]u8 = undefined;
    var size: usize = data.len;
    const result = get_data(self.real_vulkan.device orelse return, cache, &size, &data);
    self.noteRealVulkanResult(result, "vkGetPipelineCacheData during persistence");
    if (result == abi.SUCCESS and size <= data.len) self.savePipelineCacheFile(data[0..size]);
}

pub fn updateDescriptorSetWithTemplate(self: anytype, state: anytype) void {
    self.vulkan_descriptor_template_update_calls +|= 1;
    if (self.real_vulkan.device_lost) return;
    const function = self.real_vulkan.fn_ptrs.update_descriptor_set_with_template orelse return;
    const destination = self.real_vulkan.realDescriptorSet(guest_context.registers(state).rsi) orelse return;
    const template = self.real_vulkan.realDescriptorUpdateTemplate(guest_context.registers(state).rdx) orelse return;
    const record_index = self.real_vulkan.descriptorUpdateTemplateIndex(guest_context.registers(state).rdx) orelse return;
    const record = &self.real_vulkan.descriptor_update_template_records[record_index];

    var required: u64 = 0;
    for (record.entries[0..record.entry_count]) |entry| {
        if (entry.descriptor_count == 0) continue;
        const element_size: u64 = switch (entry.descriptor_type) {
            0, 1, 2, 3, 10 => @sizeOf(abi.DescriptorImageInfo),
            4, 5 => @sizeOf(u64),
            6, 7, 8, 9 => @sizeOf(abi.DescriptorBufferInfo),
            abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK => 1,
            else => return,
        };
        if (entry.stride < element_size) return;
        const last = std.math.mul(u64, @as(u64, entry.descriptor_count - 1), entry.stride) catch return;
        const end = std.math.add(u64, entry.offset, std.math.add(u64, last, element_size) catch return) catch return;
        required = @max(required, end);
    }
    if (required > marshal.scratch_bytes) return;
    if (required != 0 and guest_context.registers(state).rcx == 0) return;
    self.vulkan_scratch.reset();
    const host_data = self.vulkan_scratch.alloc(@intCast(required)) orelse return;
    if (required != 0) {
        const guest_data = state.guestMemoryConst(guest_context.registers(state).rcx, required) orelse return;
        @memcpy(host_data, guest_data);
    }
    self.trackDescriptorTemplateImages(state, guest_context.registers(state).rsi, record, guest_context.registers(state).rcx);
    for (record.entries[0..record.entry_count]) |entry| {
        if (entry.descriptor_count == 0) continue;
        const element_size: usize = switch (entry.descriptor_type) {
            0, 1, 2, 3, 10 => @sizeOf(abi.DescriptorImageInfo),
            4, 5 => @sizeOf(u64),
            6, 7, 8, 9 => @sizeOf(abi.DescriptorBufferInfo),
            abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK => 1,
            else => return,
        };
        for (0..@as(usize, @intCast(entry.descriptor_count))) |element_index| {
            const relative = std.math.add(u64, entry.offset, std.math.mul(u64, @as(u64, @intCast(element_index)), entry.stride) catch return) catch return;
            const offset: usize = @intCast(relative);
            if (offset + element_size > host_data.len) return;
            switch (entry.descriptor_type) {
                0, 1, 2, 3, 10 => {
                    const sampler = std.mem.readInt(u64, host_data[offset..][0..8], .little);
                    const image_view = std.mem.readInt(u64, host_data[offset + 8 ..][0..8], .little);
                    if (sampler != 0) {
                        const real = self.real_vulkan.realSampler(sampler) orelse return;
                        std.mem.writeInt(u64, host_data[offset..][0..8], real, .little);
                    }
                    if (image_view != 0) {
                        const real = self.real_vulkan.realImageView(image_view) orelse return;
                        std.mem.writeInt(u64, host_data[offset + 8 ..][0..8], real, .little);
                    }
                },
                4, 5 => {
                    const view = std.mem.readInt(u64, host_data[offset..][0..8], .little);
                    if (view != 0) {
                        const real = self.real_vulkan.realBufferView(view) orelse return;
                        std.mem.writeInt(u64, host_data[offset..][0..8], real, .little);
                    }
                },
                6, 7, 8, 9 => {
                    const buffer = std.mem.readInt(u64, host_data[offset..][0..8], .little);
                    if (buffer != 0) {
                        const real = self.real_vulkan.realBuffer(buffer) orelse return;
                        std.mem.writeInt(u64, host_data[offset..][0..8], real, .little);
                    }
                },
                abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK => {},
                else => return,
            }
        }
    }
    function(self.real_vulkan.device.?, destination, template, if (required == 0) null else @ptrCast(host_data.ptr));
    if (self.native_texture_state) |native| {
        for (record.entries[0..record.entry_count]) |entry| {
            if (entry.dst_binding != 0 or entry.dst_array_element != 0) continue;
            var write = abi.WriteDescriptorSet{ .dst_set = destination, .descriptor_count = entry.descriptor_count, .descriptor_type = entry.descriptor_type };
            if (entry.descriptor_type == 7 and entry.descriptor_count == 1) write.buffer_info = @ptrCast(@alignCast(host_data[@intCast(entry.offset)..].ptr));
            native.noteWrite(write);
        }
    }
    self.vulkan_tiers.note(.descriptor_set, .real);
}

pub fn getPipelineCacheData(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |lost| return lost;
    const function = self.real_vulkan.fn_ptrs.get_pipeline_cache_data orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const cache = self.real_vulkan.realPipelineCache(guest_context.registers(state).rsi) orelse return vkErrorInitializationFailed();
    const size_address = guest_context.registers(state).rdx;
    if (size_address == 0 or state.guestMemory(size_address, 8) == null) return vkErrorInitializationFailed();
    const requested = state.read64(size_address);
    var required: usize = 0;
    const query_result = function(self.real_vulkan.device.?, cache, &required, null);
    self.noteRealVulkanResult(query_result, "vkGetPipelineCacheData");
    if (query_result != abi.SUCCESS) return @as(u32, @bitCast(query_result));
    if (guest_context.registers(state).rcx == 0) {
        state.write64(size_address, required);
        self.vulkan_tiers.note(.pipeline, .real);
        return abi.SUCCESS;
    }
    const capacity = @min(@as(usize, @intCast(@min(requested, std.math.maxInt(usize)))), marshal.scratch_bytes);
    if (capacity != 0 and state.guestMemory(guest_context.registers(state).rcx, capacity) == null) return vkErrorInitializationFailed();
    self.vulkan_scratch.reset();
    const host_bytes = if (capacity == 0) null else self.vulkan_scratch.alloc(capacity);
    if (capacity != 0 and host_bytes == null) return vkErrorOutOfHostMemory();
    var data_size: usize = capacity;
    const result = function(
        self.real_vulkan.device.?,
        cache,
        &data_size,
        if (host_bytes) |bytes| @ptrCast(bytes.ptr) else null,
    );
    self.noteRealVulkanResult(result, "vkGetPipelineCacheData");
    if (host_bytes) |bytes| {
        if (data_size > bytes.len) data_size = bytes.len;
        if (state.guestMemory(guest_context.registers(state).rcx, data_size)) |destination| @memcpy(destination, bytes[0..data_size]);
    }
    state.write64(size_address, data_size);
    self.vulkan_tiers.note(.pipeline, .real);
    return @as(u32, @bitCast(result));
}

pub fn destroyVulkanObject(self: anytype, state: anytype, name: []const u8) u64 {
    if (!self.real_vulkan.hasDevice()) return 0;
    // After VK_ERROR_DEVICE_LOST, the native child handles are no longer
    // valid driver objects.  Keep destruction a guest-visible no-op until
    // destroyRealDevice performs the quarantined teardown; calling any
    // child destructor here can turn recoverable guest teardown into a
    // second host crash.
    if (self.real_vulkan.device_lost) return 0;
    const device = self.real_vulkan.device.?;
    const handle = guest_context.registers(state).rsi;
    if (std.mem.eql(u8, name, "vkDestroySampler")) {
        if (self.real_vulkan.realSampler(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_sampler) |function| function(device, real, null);
        _ = self.releaseVulkanHandle(&self.real_vulkan.sampler_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyDescriptorSetLayout")) {
        if (self.real_vulkan.realDescriptorSetLayout(handle)) |real| {
            if (self.native_texture_state) |native| _ = native.set_layouts.remove(real);
            if (self.real_vulkan.fn_ptrs.destroy_descriptor_set_layout) |function| function(device, real, null);
        }
        _ = self.releaseVulkanHandle(&self.real_vulkan.descriptor_set_layout_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyPipelineLayout")) {
        if (self.real_vulkan.realPipelineLayout(handle)) |real| {
            if (self.real_vulkan.fn_ptrs.destroy_pipeline_layout) |function| function(device, real, null);
            self.forgetPipelineLayout(real);
            if (self.native_texture_state) |native| native.forgetLayout(&self.real_vulkan, real);
        }
        _ = self.releaseVulkanHandle(&self.real_vulkan.pipeline_layout_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyShaderModule")) {
        if (self.real_vulkan.realShaderModule(handle)) |real| {
            if (self.native_texture_state) |native| _ = native.shaders.remove(real);
            if (self.real_vulkan.fn_ptrs.destroy_shader_module) |function| function(device, real, null);
        }
        self.vulkan_fsi_tracker.forgetShader(handle);
        _ = self.releaseVulkanHandle(&self.real_vulkan.shader_module_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyRenderPass")) {
        if (self.real_vulkan.realRenderPass(handle)) |real| self.fsiForgetRenderPass(real);
        if (self.real_vulkan.realRenderPass(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_render_pass) |function| function(device, real, null);
        _ = self.releaseVulkanHandle(&self.real_vulkan.render_pass_map, handle);
        self.forgetRenderPass(handle);
    } else if (std.mem.eql(u8, name, "vkDestroyFramebuffer")) {
        if (self.real_vulkan.realFramebuffer(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_framebuffer) |function| function(device, real, null);
        _ = self.releaseVulkanHandle(&self.real_vulkan.framebuffer_map, handle);
        self.forgetFramebuffer(handle);
    } else if (std.mem.eql(u8, name, "vkDestroyPipeline")) {
        if (self.real_vulkan.realPipeline(handle)) |real| {
            if (self.trackedGraphicsPipeline(real)) |metadata| {
                if (metadata.repair_real != 0 and metadata.repair_real != real) {
                    if (self.real_vulkan.fn_ptrs.destroy_pipeline) |function| function(device, metadata.repair_real, null);
                }
            }
            if (self.real_vulkan.fn_ptrs.destroy_pipeline) |function| function(device, real, null);
            self.forgetGraphicsPipeline(real);
            self.forgetRectangleExpandedPipeline(real);
        }
        _ = self.releaseVulkanHandle(&self.real_vulkan.pipeline_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyBuffer")) {
        if (self.real_vulkan.realBuffer(handle)) |real| {
            if (self.native_texture_state) |native| native.forgetBuffer(real);
            if (real == self.rect_expand_builtin_index_buffer) self.rect_expand_builtin_index_buffer = 0;
            if (self.real_vulkan.fn_ptrs.destroy_buffer) |function| function(device, real, null);
        }
        _ = self.releaseVulkanHandle(&self.real_vulkan.buffer_map, handle);
        _ = self.releaseResource(handle);
    } else if (std.mem.eql(u8, name, "vkDestroyImage")) {
        if (self.real_vulkan.realImage(handle)) |real| {
            if (self.real_vulkan.fn_ptrs.destroy_image) |function| function(device, real, null);
            self.present_chain.forgetResourceImage(real);
        }
        _ = self.releaseVulkanHandle(&self.real_vulkan.image_map, handle);
        _ = self.releaseResource(handle);
    } else if (std.mem.eql(u8, name, "vkDestroyImageView")) {
        if (self.real_vulkan.realImageView(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_image_view) |function| function(device, real, null);
        _ = self.releaseVulkanHandle(&self.real_vulkan.image_view_map, handle);
        self.forgetImageView(handle);
    } else if (std.mem.eql(u8, name, "vkDestroyBufferView")) {
        for (&self.tracked_buffer_views) |*view| {
            if (view.synthetic == handle) view.* = .{};
        }
        if (self.real_vulkan.realBufferView(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_buffer_view) |function| function(device, real, null);
        _ = self.releaseVulkanHandle(&self.real_vulkan.buffer_view_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyFence")) {
        if (self.real_vulkan.realFence(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_fence) |function| function(device, real, null);
        _ = self.releaseVulkanHandle(&self.real_vulkan.fence_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroySemaphore")) {
        if (self.real_vulkan.realSemaphore(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_semaphore) |function| function(device, real, null);
        _ = self.releaseVulkanHandle(&self.real_vulkan.semaphore_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyCommandPool")) {
        if (self.real_vulkan.realCommandPool(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_command_pool) |function| function(device, real, null);
        _ = self.releaseVulkanHandle(&self.real_vulkan.command_pool_map, handle);
        self.fsiResetCommandPool(handle, true);
    } else if (std.mem.eql(u8, name, "vkDestroyDescriptorPool")) {
        if (self.real_vulkan.realDescriptorPool(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_descriptor_pool) |function| function(device, real, null);
        // Vulkan pool destruction implicitly frees every descriptor set
        // allocated from that pool.  Leaving the reverse mappings behind
        // was the direct cause of the overnight run's 1,024-entry map
        // exhaustion even though the guest had already destroyed its
        // pools.
        _ = self.reclaimDescriptorSetsForPool(handle, "destroy");
        _ = self.releaseVulkanHandle(&self.real_vulkan.descriptor_pool_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyQueryPool")) {
        if (self.real_vulkan.realQueryPool(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_query_pool) |function| function(device, real, null);
        _ = self.releaseVulkanHandle(&self.real_vulkan.query_pool_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyPipelineCache")) {
        if (self.real_vulkan.realPipelineCache(handle)) |real| {
            self.persistPipelineCache(real);
            if (self.real_vulkan.fn_ptrs.destroy_pipeline_cache) |function| function(device, real, null);
            self.vulkan_real_objects_destroyed +|= 1;
        }
        _ = self.releaseVulkanHandle(&self.real_vulkan.pipeline_cache_map, handle);
    } else if (std.mem.eql(u8, name, "vkDestroyDescriptorUpdateTemplate")) {
        if (self.real_vulkan.realDescriptorUpdateTemplate(handle)) |real| {
            if (self.real_vulkan.fn_ptrs.destroy_descriptor_update_template) |function| function(device, real, null);
            self.vulkan_real_objects_destroyed +|= 1;
        }
        if (self.real_vulkan.descriptorUpdateTemplateIndex(handle)) |record_index| self.real_vulkan.descriptor_update_template_records[record_index] = .{};
        _ = self.releaseVulkanHandle(&self.real_vulkan.descriptor_update_template_map, handle);
    } else if (std.mem.eql(u8, name, "vkFreeMemory")) {
        if (self.findVulkanMemoryRecord(handle)) |record| {
            if (comptime @hasDecl(@TypeOf(state.*), "releaseNativeMemory")) {
                if (record.native_alias_base != 0) state.releaseNativeMemory(record.native_alias_base);
            }
        }
        if (self.real_vulkan.realMemory(handle)) |real| {
            if (self.real_vulkan.fn_ptrs.unmap_memory) |function| {
                for (&self.vulkan_memory_records) |*record| if (record.handle == handle and record.host_mapped_ptr != null) function(device, real);
            }
            if (self.real_vulkan.fn_ptrs.free_memory) |function| function(device, real, null);
        }
        _ = self.releaseVulkanHandle(&self.real_vulkan.memory_map, handle);
        if (self.findVulkanMemoryRecord(handle)) |record| {
            record.releaseBaseline();
            record.* = .{};
        }
    } else if (std.mem.eql(u8, name, "vkFreeCommandBuffers")) {
        const pool = self.real_vulkan.realCommandPool(guest_context.registers(state).rsi) orelse return 0;
        const count = guest_context.registers(state).rdx;
        var buffers: [256]u64 = undefined;
        if (count > buffers.len or !copyGuestHandleArray(self, state, guest_context.registers(state).rcx, count, &buffers, .command_buffer)) return 0;
        if (self.real_vulkan.fn_ptrs.free_command_buffers) |function| function(device, pool, @intCast(count), @ptrCast(&buffers));
        for (0..@as(usize, @intCast(count))) |index| {
            const synthetic = state.read64(guest_context.registers(state).rcx + @as(u64, @intCast(index)) * 8);
            _ = self.releaseVulkanHandle(&self.real_vulkan.command_buffer_map, synthetic);
            if (self.native_texture_state) |native| native.resetCommand(synthetic);
            self.vulkan_fsi_tracker.forgetCommandBuffer(synthetic);
            self.fsiForgetCommandBuffer(synthetic);
            for (&self.tracked_command_targets) |*record| {
                if (record.synthetic == synthetic) record.* = .{};
            }
        }
    } else if (std.mem.eql(u8, name, "vkFreeDescriptorSets")) {
        const pool = self.real_vulkan.realDescriptorPool(guest_context.registers(state).rsi) orelse return 0;
        const count = guest_context.registers(state).rdx;
        var sets: [256]u64 = undefined;
        if (!copyGuestHandleArray(self, state, guest_context.registers(state).rcx, count, &sets, .descriptor_set)) return 0;
        if (self.real_vulkan.fn_ptrs.free_descriptor_sets) |function| _ = function(device, pool, @intCast(count), &sets);
        for (0..@as(usize, @intCast(count))) |index| {
            const synthetic = state.read64(guest_context.registers(state).rcx + @as(u64, @intCast(index)) * 8);
            self.forgetDescriptorSet(synthetic);
            if (self.releaseVulkanHandle(&self.real_vulkan.descriptor_set_map, synthetic)) {
                self.vulkan_descriptor_set_free_reclaims +|= 1;
            }
        }
    }
    return 0;
}

pub fn nextVulkanObject(self: anytype) u64 {
    const result = self.next_vulkan_object;
    self.next_vulkan_object +%= 0x10;
    return result;
}

pub fn mapVulkanHandle(self: anytype, map: []HandleMap, synthetic: u64, real: RealHandle, entry_point: []const u8) bool {
    return self.mapVulkanHandleOwned(map, synthetic, real, 0, entry_point);
}

pub fn mapVulkanHandleOwned(self: anytype, map: []HandleMap, synthetic: u64, real: RealHandle, owner: u64, entry_point: []const u8) bool {
    const result = HandleMap.allocOrFindOwned(map, synthetic, real, owner);
    switch (result) {
        .inserted => {
            self.vulkan_handle_map_allocations +|= 1;
            if (std.mem.eql(u8, entry_point, "vkAllocateDescriptorSets")) {
                self.vulkan_descriptor_set_map_high_water = @max(
                    self.vulkan_descriptor_set_map_high_water,
                    HandleMap.occupied(map),
                );
            }
        },
        .existing => {},
        .replaced => self.vulkan_handle_map_replacements +|= 1,
        .invalid => {
            self.vulkan_handle_map_invalid +|= 1;
            if (self.vulkan_handle_map_invalid <= 8 or sparseVulkanSuccessLog(self.vulkan_handle_map_invalid)) {
                machoCapturePrint(
                    "macho-processor: Vulkan handle mapping refused: entry={s} synthetic=0x{x} real=0x{x} owner=0x{x} reason=invalid_handle; no panic and no guest mapping was published\n",
                    .{ entry_point, synthetic, real, owner },
                );
            }
        },
        .exhausted => {
            self.vulkan_handle_map_exhaustions +|= 1;
            if (self.vulkan_handle_map_exhaustions <= 8 or sparseVulkanSuccessLog(self.vulkan_handle_map_exhaustions)) {
                machoCapturePrint(
                    "macho-processor: Vulkan handle mapping exhausted: entry={s} synthetic=0x{x} real=0x{x} owner=0x{x} occupied={d} capacity={d}; returning VK_ERROR_OUT_OF_HOST_MEMORY instead of panicking\n",
                    .{ entry_point, synthetic, real, owner, HandleMap.occupied(map), map.len },
                );
            }
        },
    }
    return result == .inserted or result == .existing or result == .replaced;
}

pub fn releaseVulkanHandle(self: anytype, map: []HandleMap, synthetic: u64) bool {
    if (!HandleMap.remove(map, synthetic)) return false;
    self.vulkan_handle_map_releases +|= 1;
    return true;
}

pub fn availableVulkanMapSlots(self: anytype, entry_point: []const u8) ?usize {
    const slots = if (std.mem.eql(u8, entry_point, "vkCreateDescriptorUpdateTemplate"))
        HandleMap.freeSlots(&self.real_vulkan.descriptor_update_template_map)
    else if (std.mem.eql(u8, entry_point, "vkCreatePipelineCache"))
        HandleMap.freeSlots(&self.real_vulkan.pipeline_cache_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateImage"))
        HandleMap.freeSlots(&self.real_vulkan.image_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateBuffer"))
        HandleMap.freeSlots(&self.real_vulkan.buffer_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateSampler"))
        HandleMap.freeSlots(&self.real_vulkan.sampler_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateShaderModule"))
        HandleMap.freeSlots(&self.real_vulkan.shader_module_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateRenderPass"))
        HandleMap.freeSlots(&self.real_vulkan.render_pass_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateFramebuffer"))
        HandleMap.freeSlots(&self.real_vulkan.framebuffer_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateDescriptorSetLayout"))
        HandleMap.freeSlots(&self.real_vulkan.descriptor_set_layout_map)
    else if (std.mem.eql(u8, entry_point, "vkCreatePipelineLayout"))
        HandleMap.freeSlots(&self.real_vulkan.pipeline_layout_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateDescriptorPool"))
        HandleMap.freeSlots(&self.real_vulkan.descriptor_pool_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateBufferView"))
        HandleMap.freeSlots(&self.real_vulkan.buffer_view_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateImageView"))
        HandleMap.freeSlots(&self.real_vulkan.image_view_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateCommandPool"))
        HandleMap.freeSlots(&self.real_vulkan.command_pool_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateFence"))
        HandleMap.freeSlots(&self.real_vulkan.fence_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateSemaphore"))
        HandleMap.freeSlots(&self.real_vulkan.semaphore_map)
    else if (std.mem.eql(u8, entry_point, "vkCreateQueryPool"))
        HandleMap.freeSlots(&self.real_vulkan.query_pool_map)
    else
        return null;
    return slots;
}

pub fn noteVulkanMapCapacityRefusal(self: anytype, entry_point: []const u8, required: usize, available: usize) void {
    self.vulkan_handle_map_exhaustions +|= 1;
    if (self.vulkan_handle_map_exhaustions <= 8 or sparseVulkanSuccessLog(self.vulkan_handle_map_exhaustions)) {
        machoCapturePrint(
            "macho-processor: REAL {s} refused before driver: reverse handle map has available={d} required={d}; return=VK_ERROR_OUT_OF_HOST_MEMORY so the long run remains diagnosable\n",
            .{ entry_point, available, required },
        );
    }
}

pub fn reclaimDescriptorSetsForPool(self: anytype, pool: u64, reason: []const u8) usize {
    if (pool == 0) return 0;
    if (self.native_texture_state) |native| {
        for (&self.real_vulkan.descriptor_set_map) |*entry| {
            const mapped = HandleMap.snapshot(entry) orelse continue;
            if (mapped.owner == pool) native.forgetSet(&self.real_vulkan, mapped.real);
        }
        for (self.tracked_descriptor_sets[0..self.tracked_descriptor_set_index.highWater()]) |record| {
            if (record.synthetic != 0 and record.pool == pool) {
                if (self.real_vulkan.realDescriptorSet(record.synthetic)) |real| native.forgetSet(&self.real_vulkan, real);
            }
        }
    }
    var reclaimed = HandleMap.removeOwned(&self.real_vulkan.descriptor_set_map, pool);
    for (self.tracked_descriptor_sets[0..self.tracked_descriptor_set_index.highWater()]) |*record| {
        if (record.synthetic == 0 or record.pool != pool) continue;
        if (HandleMap.remove(&self.real_vulkan.descriptor_set_map, record.synthetic)) reclaimed += 1;
        _ = self.tracked_descriptor_set_index.remove(record.synthetic);
        record.* = .{};
    }
    if (reclaimed != 0) {
        self.vulkan_handle_map_releases +|= @intCast(reclaimed);
        if (std.mem.eql(u8, reason, "reset"))
            self.vulkan_descriptor_set_pool_reset_reclaims +|= @intCast(reclaimed)
        else
            self.vulkan_descriptor_set_pool_destroy_reclaims +|= @intCast(reclaimed);
        machoCapturePrint(
            "macho-processor: Vulkan descriptor-set mappings reclaimed: pool=0x{x} count={d} reason={s} live_after={d} free_after={d}; pool lifetime is the authoritative child lifetime\n",
            .{ pool, reclaimed, reason, HandleMap.occupied(&self.real_vulkan.descriptor_set_map), HandleMap.freeSlots(&self.real_vulkan.descriptor_set_map) },
        );
    }
    return reclaimed;
}

pub fn reclaimOrphanedDescriptorSets(self: anytype) usize {
    var reclaimed: usize = 0;
    for (&self.real_vulkan.descriptor_set_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.owner == 0) continue;
        if (HandleMap.findReal(&self.real_vulkan.descriptor_pool_map, mapped.owner) != null) continue;
        const synthetic = mapped.synthetic;
        self.forgetDescriptorSet(synthetic);
        if (!HandleMap.remove(&self.real_vulkan.descriptor_set_map, synthetic)) continue;
        reclaimed += 1;
    }
    if (reclaimed != 0) {
        self.vulkan_handle_map_releases +|= @intCast(reclaimed);
        self.vulkan_descriptor_set_pool_destroy_reclaims +|= @intCast(reclaimed);
        machoCapturePrint(
            "macho-processor: Vulkan orphaned descriptor-set mappings reclaimed: count={d} live_after={d} free_after={d}; their descriptor pools were already gone\n",
            .{ reclaimed, HandleMap.occupied(&self.real_vulkan.descriptor_set_map), HandleMap.freeSlots(&self.real_vulkan.descriptor_set_map) },
        );
    }
    return reclaimed;
}

pub fn logVulkanHandleMapState(self: anytype) void {
    const descriptor_sets_live = HandleMap.occupied(&self.real_vulkan.descriptor_set_map);
    const descriptor_sets_free = HandleMap.freeSlots(&self.real_vulkan.descriptor_set_map);
    machoCapturePrint(
        "macho-processor: VULKAN HANDLE MAPS: allocations={d} replacements={d} releases={d} invalid={d} exhaustions={d}; descriptor_sets live/free/capacity={d}/{d}/{d} high_water={d} pool_reclaims(reset/destroy/free)={d}/{d}/{d}\n",
        .{
            self.vulkan_handle_map_allocations,
            self.vulkan_handle_map_replacements,
            self.vulkan_handle_map_releases,
            self.vulkan_handle_map_invalid,
            self.vulkan_handle_map_exhaustions,
            descriptor_sets_live,
            descriptor_sets_free,
            self.real_vulkan.descriptor_set_map.len,
            self.vulkan_descriptor_set_map_high_water,
            self.vulkan_descriptor_set_pool_reset_reclaims,
            self.vulkan_descriptor_set_pool_destroy_reclaims,
            self.vulkan_descriptor_set_free_reclaims,
        },
    );
    machoCapturePrint(
        "macho-processor: VULKAN HANDLE MAP OCCUPANCY: memory={d}/{d} buffers={d}/{d} images={d}/{d} image_views={d}/{d} samplers={d}/{d} pipelines={d}/{d} descriptor_pools={d}/{d} command_buffers={d}/{d}; live/capacity, zero free slots is a bounded bridge refusal rather than a process panic\n",
        .{
            HandleMap.occupied(&self.real_vulkan.memory_map),
            self.real_vulkan.memory_map.len,
            HandleMap.occupied(&self.real_vulkan.buffer_map),
            self.real_vulkan.buffer_map.len,
            HandleMap.occupied(&self.real_vulkan.image_map),
            self.real_vulkan.image_map.len,
            HandleMap.occupied(&self.real_vulkan.image_view_map),
            self.real_vulkan.image_view_map.len,
            HandleMap.occupied(&self.real_vulkan.sampler_map),
            self.real_vulkan.sampler_map.len,
            HandleMap.occupied(&self.real_vulkan.pipeline_map),
            self.real_vulkan.pipeline_map.len,
            HandleMap.occupied(&self.real_vulkan.descriptor_pool_map),
            self.real_vulkan.descriptor_pool_map.len,
            HandleMap.occupied(&self.real_vulkan.command_buffer_map),
            self.real_vulkan.command_buffer_map.len,
        },
    );
}

pub fn trackedImageView(self: anytype, synthetic: u64) ?TrackedImageView {
    const slot = self.tracked_image_view_index.find(synthetic) orelse return null;
    return self.tracked_image_views[slot];
}

pub fn recordImageView(self: anytype, synthetic: u64, image: u64) bool {
    const claimed = self.tracked_image_view_index.findOrInsert(synthetic) orelse return false;
    self.tracked_image_views[claimed.slot] = .{ .synthetic = synthetic, .image = image };
    return true;
}

pub fn trackedFramebuffer(self: anytype, synthetic: u64) ?TrackedFramebuffer {
    if (synthetic == 0) return null;
    for (self.tracked_framebuffers) |record| {
        if (record.synthetic == synthetic) return record;
    }
    return null;
}

pub fn trackedRenderPass(self: anytype, synthetic: u64) ?TrackedRenderPass {
    if (synthetic == 0) return null;
    for (self.tracked_render_passes) |record| {
        if (record.synthetic == synthetic) return record;
    }
    return null;
}

pub fn trackedDescriptorSet(self: anytype, synthetic: u64) ?TrackedDescriptorSet {
    const slot = self.tracked_descriptor_set_index.find(synthetic) orelse return null;
    return self.tracked_descriptor_sets[slot];
}

pub fn noteTargetOverflow(self: anytype, kind: TargetOverflowKind) void {
    self.target_overflow_events +|= 1;
    const slot = &self.target_overflow_by_kind[@intFromEnum(kind)];
    slot.* +|= 1;
    // The first few occurrences identify the exact bounded ledger in the
    // live stream.  Subsequent events stay counter-only so this forensic
    // path cannot become the graphics bottleneck it is measuring.
    if (slot.* <= 2) {
        machoCapturePrint(
            "macho-processor: Vulkan provenance capacity finding: kind={s} occurrence={d}; native command admission is unaffected, but detailed image ancestry was not retained\n",
            .{ kind.label(), slot.* },
        );
    }
}

pub fn mutableDescriptorSet(self: anytype, synthetic: u64) ?*TrackedDescriptorSet {
    if (synthetic == 0) return null;
    const claimed = self.tracked_descriptor_set_index.findOrInsert(synthetic) orelse {
        self.noteTargetOverflow(.descriptor_set_table);
        return null;
    };
    const record = &self.tracked_descriptor_sets[claimed.slot];
    if (claimed.inserted) record.* = .{ .synthetic = synthetic };
    return record;
}

pub fn noteDescriptorSetPool(self: anytype, synthetic: u64, pool: u64) void {
    const record = self.mutableDescriptorSet(synthetic) orelse return;
    record.pool = pool;
}

pub fn isDescriptorImageType(descriptor_type: u32) bool {
    return switch (descriptor_type) {
        // A sampler-only descriptor carries image-info storage but no
        // image identity. Its ignored imageView cannot be provenance.
        1, 2, 3, 10 => true,
        else => false,
    };
}

pub fn noteDescriptorSetImage(self: anytype, set: u64, binding: u32, array_element: u32, image: u64, image_view: u64, unknown: bool) void {
    const record = self.mutableDescriptorSet(set) orelse return;
    for (record.images[0..@as(usize, @intCast(record.image_count))]) |*known| {
        if (known.binding != binding or known.array_element != array_element) continue;
        known.image = image;
        known.image_view = image_view;
        if (unknown) record.unknown_image_views = true;
        return;
    }
    if (@as(usize, @intCast(record.image_count)) == record.images.len) {
        self.noteTargetOverflow(.descriptor_image_entries);
        return;
    }
    record.images[@as(usize, @intCast(record.image_count))] = .{
        .binding = binding,
        .array_element = array_element,
        .image = image,
        .image_view = image_view,
    };
    record.image_count += 1;
    if (unknown) record.unknown_image_views = true;
}

pub fn markDescriptorSetUnknown(self: anytype, set: u64) void {
    const record = self.mutableDescriptorSet(set) orelse return;
    record.unknown_image_views = true;
}

pub fn noteDescriptorImageInfo(self: anytype, set: u64, binding: u32, array_element: u32, info: abi.DescriptorImageInfo) void {
    self.vulkan_descriptor_image_infos_observed +|= 1;
    var image: u64 = 0;
    var unknown = false;
    if (info.image_view != 0) {
        if (self.trackedImageView(info.image_view)) |view| {
            image = view.image;
            unknown = image == 0;
            if (unknown) self.vulkan_descriptor_unknown_image_views +|= 1;
        } else {
            unknown = true;
            self.vulkan_descriptor_unknown_image_views +|= 1;
            self.target_unknown_events +|= 1;
        }
    }
    self.noteDescriptorSetImage(set, binding, array_element, image, info.image_view, unknown);
}

pub fn trackDescriptorImageWrites(self: anytype, state: anytype, writes: []const abi.WriteDescriptorSet) void {
    for (writes) |write| {
        if (!isDescriptorImageType(write.descriptor_type)) continue;
        const count: usize = @intCast(write.descriptor_count);
        const address = if (write.image_info) |pointer| @intFromPtr(pointer) else 0;
        if (count != 0 and address == 0) {
            self.target_unknown_events +|= 1;
            self.markDescriptorSetUnknown(write.dst_set);
            continue;
        }
        const observed = @min(count, MAX_TRACKED_DESCRIPTOR_IMAGES);
        if (count > observed) self.noteTargetOverflow(.descriptor_image_array);
        for (0..observed) |index| {
            var info: abi.DescriptorImageInfo = undefined;
            const offset = @as(u64, @intCast(index)) * @sizeOf(abi.DescriptorImageInfo);
            if (!copyGuestValue(abi.DescriptorImageInfo, state, address + offset, &info)) {
                self.target_unknown_events +|= 1;
                self.markDescriptorSetUnknown(write.dst_set);
                break;
            }
            const array_element = std.math.add(u32, write.dst_array_element, @intCast(index)) catch {
                self.noteTargetOverflow(.descriptor_address_arithmetic);
                break;
            };
            self.noteDescriptorImageInfo(write.dst_set, write.dst_binding, array_element, info);
        }
    }
}

pub fn trackTexelDescriptorWrites(self: anytype, state: anytype, writes: []const abi.WriteDescriptorSet) void {
    for (writes) |write| {
        if (write.descriptor_type != 4) continue; // uniform lookup data only
        const record = self.mutableDescriptorSet(write.dst_set) orelse continue;
        const address = if (write.texel_buffer_view) |pointer| @intFromPtr(pointer) else 0;
        for (0..@min(write.descriptor_count, 8)) |index| {
            var view: u64 = 0;
            if (!copyGuestValue(u64, state, address + @as(u64, @intCast(index)) * 8, &view)) break;
            const element = std.math.add(u32, write.dst_array_element, @intCast(index)) catch break;
            var replaced = false;
            for (record.texels[0..record.texel_count]) |*known| {
                if (known.binding != write.dst_binding or known.element != element) continue;
                known.view = view;
                replaced = true;
                break;
            }
            if (!replaced and record.texel_count < record.texels.len) {
                record.texels[record.texel_count] = .{ .binding = write.dst_binding, .element = element, .view = view };
                record.texel_count += 1;
            } else if (!replaced) self.noteTargetOverflow(.texel_entries);
        }
        if (write.descriptor_count > 8) self.noteTargetOverflow(.texel_array);
    }
}

pub fn auditCommandTexelCustody(self: anytype, command_buffer: u64) void {
    for (self.tracked_command_targets) |command| {
        if (command.synthetic != command_buffer) continue;
        for (command.bound_descriptor_sets[0..command.bound_descriptor_set_count]) |bound| {
            const set = self.trackedDescriptorSet(bound.synthetic) orelse continue;
            for (set.texels[0..set.texel_count]) |binding| {
                for (&self.tracked_buffer_views) |*view| {
                    if (view.synthetic != binding.view or (view.format != 64 and view.format != 81) or view.range == 0 or view.range > 4096) continue;
                    const resource = self.findResource(view.buffer) orelse continue;
                    const memory = self.findVulkanMemoryRecord(resource.memory) orelse continue;
                    const offset = std.math.add(u64, resource.memory_offset, view.offset) catch continue;
                    if (memory.host_mapped_ptr == null or !rangeContains(memory.mapped_offset, memory.host_mapped_size, offset, view.range)) {
                        self.texel_custody_missing +|= 1;
                        if (self.texel_custody_missing == 1) machoCapturePrint("macho-processor: TEXEL CUSTODY: unavailable set=0x{x} binding={d} view=0x{x} buffer=0x{x} memory=0x{x}; no readable native mapping, not proof of a zero gamma ramp\n", .{ bound.synthetic, binding.binding, view.synthetic, view.buffer, resource.memory });
                        continue;
                    }
                    const start: usize = @intCast(offset - memory.mapped_offset);
                    const bytes = @as([*]const u8, @ptrCast(memory.host_mapped_ptr.?))[start..][0..@as(usize, @intCast(view.range))];
                    const stats = rosette_gpu.vulkan.texel_custody.analyze(bytes, view.format) catch continue;
                    self.texel_custody_samples +|= 1;
                    if (stats.nonzero_bytes == 0) self.texel_custody_zero +|= 1;
                    self.texel_custody_last_format = view.format;
                    self.texel_custody_last_channel_pairs_differ = stats.channel_pairs_differ;
                    self.texel_custody_last_shape = stats.shape;
                    self.texel_custody_last_out_rgb = .{ stats.out_max_rgb, stats.out_7e3_one_rgb, stats.out_mid_rgb };
                    switch (stats.shape) {
                        .xenia_default_linear => self.texel_custody_default_samples +|= 1,
                        .programmed => self.texel_custody_programmed_samples +|= 1,
                        else => {},
                    }
                    if ((!view.observed or view.last_hash != stats.hash) and self.texel_custody_printed < 24) {
                        self.texel_custody_printed += 1;
                        machoCapturePrint("macho-processor: TEXEL CUSTODY: command=0x{x} set_index={d} set=0x{x} binding={d} view=0x{x} native_view=0x{x} buffer=0x{x} native_buffer=0x{x} memory=0x{x} offset={d} format={d} bytes={d} hash=0x{x} nonzero_bytes={d} entries={d} min={d}/{d}/{d} max={d}/{d}/{d} ramp_shape={s} ramp_out_rgb(max/7e3_one/mid)=({d},{d},{d})/({d},{d},{d})/({d},{d},{d}) of 1023; channels are red/green/blue, native mapped lookup bytes after shadow publication, not an exposure correction. A shape of xenia_default_linear is the ramp Xenia seeds before any title write reaches DC_LUT\n", .{ command_buffer, bound.set_index, bound.synthetic, binding.binding, view.synthetic, self.real_vulkan.realBufferView(view.synthetic) orelse 0, view.buffer, self.real_vulkan.realBuffer(view.buffer) orelse 0, resource.memory, offset, view.format, view.range, stats.hash, stats.nonzero_bytes, stats.entries, stats.min[0], stats.min[1], stats.min[2], stats.max[0], stats.max[1], stats.max[2], stats.shape.label(), stats.out_max_rgb[0], stats.out_max_rgb[1], stats.out_max_rgb[2], stats.out_7e3_one_rgb[0], stats.out_7e3_one_rgb[1], stats.out_7e3_one_rgb[2], stats.out_mid_rgb[0], stats.out_mid_rgb[1], stats.out_mid_rgb[2] });
                    }
                    view.observed = true;
                    view.last_hash = stats.hash;
                }
            }
        }
        break;
    }
}

pub fn copyDescriptorSetImages(self: anytype, copy: abi.CopyDescriptorSet) void {
    const observed: usize = @min(@as(usize, @intCast(copy.descriptor_count)), MAX_TRACKED_DESCRIPTOR_IMAGES);
    if (@as(usize, @intCast(copy.descriptor_count)) > observed) self.noteTargetOverflow(.descriptor_image_array);
    const source = self.trackedDescriptorSet(copy.src_set) orelse {
        if (copy.descriptor_count != 0) {
            self.target_unknown_events +|= 1;
            self.markDescriptorSetUnknown(copy.dst_set);
        }
        return;
    };
    const source_texels = source.texels;
    const source_texel_count = source.texel_count;
    if (self.mutableDescriptorSet(copy.dst_set)) |destination| {
        for (destination.texels[0..destination.texel_count]) |*texel| {
            if (texel.binding == copy.dst_binding and texel.element >= copy.dst_array_element and texel.element - copy.dst_array_element < copy.descriptor_count) texel.view = 0;
        }
        for (source_texels[0..source_texel_count]) |texel| {
            if (texel.binding != copy.src_binding or texel.element < copy.src_array_element) continue;
            const delta = texel.element - copy.src_array_element;
            if (delta >= copy.descriptor_count) continue;
            const element = std.math.add(u32, copy.dst_array_element, delta) catch continue;
            var replaced = false;
            for (destination.texels[0..destination.texel_count]) |*known| {
                if (known.binding == copy.dst_binding and known.element == element) {
                    known.view = texel.view;
                    replaced = true;
                    break;
                }
            }
            if (!replaced and destination.texel_count < destination.texels.len) {
                destination.texels[destination.texel_count] = .{ .binding = copy.dst_binding, .element = element, .view = texel.view };
                destination.texel_count += 1;
            } else if (!replaced) self.noteTargetOverflow(.texel_entries);
        }
    }
    if (source.unknown_image_views) self.markDescriptorSetUnknown(copy.dst_set);
    for (0..observed) |index| {
        const dst_array_element = std.math.add(u32, copy.dst_array_element, @intCast(index)) catch {
            self.noteTargetOverflow(.descriptor_address_arithmetic);
            break;
        };
        // Clear a destination slot before copying so a descriptor that was
        // not previously tracked cannot leave a stale sampled image in the
        // route ledger.
        self.noteDescriptorSetImage(copy.dst_set, copy.dst_binding, dst_array_element, 0, 0, false);
    }
    for (source.images[0..@as(usize, @intCast(source.image_count))]) |image| {
        if (image.binding != copy.src_binding or image.array_element < copy.src_array_element) continue;
        const delta = image.array_element - copy.src_array_element;
        if (delta >= observed) continue;
        const dst_array_element = std.math.add(u32, copy.dst_array_element, delta) catch {
            self.noteTargetOverflow(.descriptor_address_arithmetic);
            continue;
        };
        self.noteDescriptorSetImage(copy.dst_set, copy.dst_binding, dst_array_element, image.image, image.image_view, false);
    }
}

pub fn trackDescriptorSetCopies(self: anytype, copies: []const abi.CopyDescriptorSet) void {
    for (copies) |copy| self.copyDescriptorSetImages(copy);
}

pub fn trackDescriptorTemplateImages(
    self: anytype,
    state: anytype,
    destination: u64,
    record: *const DescriptorUpdateTemplateRecord,
    guest_data: u64,
) void {
    for (record.entries[0..record.entry_count]) |entry| {
        if (!isDescriptorImageType(entry.descriptor_type)) continue;
        const count: usize = @intCast(entry.descriptor_count);
        const observed = @min(count, MAX_TRACKED_DESCRIPTOR_IMAGES);
        if (count > observed) self.noteTargetOverflow(.descriptor_image_array);
        for (0..observed) |index| {
            const relative = std.math.add(
                u64,
                entry.offset,
                std.math.mul(u64, @as(u64, @intCast(index)), entry.stride) catch {
                    self.noteTargetOverflow(.descriptor_address_arithmetic);
                    break;
                },
            ) catch {
                self.noteTargetOverflow(.descriptor_address_arithmetic);
                break;
            };
            var info: abi.DescriptorImageInfo = undefined;
            if (!copyGuestValue(abi.DescriptorImageInfo, state, guest_data + relative, &info)) {
                self.target_unknown_events +|= 1;
                self.markDescriptorSetUnknown(destination);
                break;
            }
            const array_element = std.math.add(u32, entry.dst_array_element, @intCast(index)) catch {
                self.noteTargetOverflow(.descriptor_address_arithmetic);
                break;
            };
            self.noteDescriptorImageInfo(destination, entry.dst_binding, array_element, info);
        }
    }
}

pub fn addCommandSampledImage(self: anytype, command_buffer: u64, image: u64) void {
    if (image == 0) return;
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    for (record.sampled_images[0..@as(usize, @intCast(record.sampled_image_count))]) |known| {
        if (known == image) return;
    }
    if (@as(usize, @intCast(record.sampled_image_count)) == record.sampled_images.len) {
        self.noteTargetOverflow(.command_sampled_images);
        return;
    }
    record.sampled_images[@as(usize, @intCast(record.sampled_image_count))] = image;
    record.sampled_image_count += 1;
    self.vulkan_descriptor_sampled_images_recorded +|= 1;
}

pub fn noteCommandSampledImageUnknown(self: anytype, command_buffer: u64) void {
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    if (!record.sampled_images_unknown) self.vulkan_descriptor_sampled_unknown +|= 1;
    record.sampled_images_unknown = true;
}

pub fn noteCommandDescriptorSet(self: anytype, command_buffer: u64, set: u64) void {
    const record = self.trackedDescriptorSet(set) orelse {
        self.vulkan_descriptor_sets_unknown +|= 1;
        self.target_unknown_events +|= 1;
        self.noteCommandSampledImageUnknown(command_buffer);
        return;
    };
    self.vulkan_descriptor_sets_resolved +|= 1;
    for (record.images[0..@as(usize, @intCast(record.image_count))]) |image| {
        self.addCommandSampledImage(command_buffer, image.image);
    }
    if (record.unknown_image_views) self.noteCommandSampledImageUnknown(command_buffer);
}

pub fn noteCommandBoundDescriptorSet(self: anytype, command_buffer: u64, set_index: u32, set: u64) void {
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    self.addCommandPassEdge(record, set);
    for (record.bound_descriptor_sets[0..@as(usize, @intCast(record.bound_descriptor_set_count))]) |*bound| {
        if (bound.set_index != set_index) continue;
        bound.synthetic = set;
        return;
    }
    if (@as(usize, @intCast(record.bound_descriptor_set_count)) == record.bound_descriptor_sets.len) {
        self.noteTargetOverflow(.command_bound_sets);
        self.noteCommandSampledImageUnknown(command_buffer);
        return;
    }
    record.bound_descriptor_sets[@as(usize, @intCast(record.bound_descriptor_set_count))] = .{
        .set_index = set_index,
        .synthetic = set,
    };
    record.bound_descriptor_set_count += 1;
}

pub fn noteCommandPassTarget(self: anytype, command_buffer: u64, framebuffer: u64) void {
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    record.current_pass_target = 0;
    record.current_pass_target_source = .unknown;
    self.vulkan_fsi_tracker.setTarget(command_buffer, 0, .unknown);
    const frame = self.trackedFramebuffer(framebuffer) orelse return;
    if (frame.attachment_count == 0) return;
    const view = self.trackedImageView(frame.attachments[0]) orelse return;
    record.current_pass_target = view.image;
    record.current_pass_target_source = .render_pass;
    self.vulkan_fsi_tracker.setTarget(command_buffer, view.image, .render_pass);
}

pub fn commandPassTarget(self: anytype, command_buffer: u64) ?CommandPassTarget {
    for (self.tracked_command_targets) |record| {
        if (record.synthetic != command_buffer) continue;
        return .{ .image = record.current_pass_target, .source = record.current_pass_target_source };
    }
    return null;
}

pub fn noteCommandDynamicTarget(self: anytype, command_buffer: u64, guest_image_view: u64) void {
    const target_image = if (guest_image_view != 0)
        (if (self.trackedImageView(guest_image_view)) |view| view.image else 0)
    else
        0;
    if (self.mutableCommandTargets(command_buffer)) |record| {
        record.current_pass_target = target_image;
        record.current_pass_target_source = .dynamic_rendering;
    }
    if (target_image == 0) {
        if (self.vulkan_fsi_tracker.isFsiPipelineBound(command_buffer)) {
            self.vulkan_fsi_tracker.noteDynamicTargetUnresolved();
            if (self.vulkan_fsi_tracker.dynamic_targets_unresolved <= 4) machoCapturePrint(
                "macho-processor: Vulkan FSI target unresolved: source=dynamic_rendering command_buffer=0x{x} guest_image_view=0x{x}; the draw can still be forwarded, but image attribution is unavailable\n",
                .{ command_buffer, guest_image_view },
            );
        }
        return;
    }
    self.vulkan_fsi_tracker.setTarget(command_buffer, target_image, .dynamic_rendering);
}

pub fn clearCommandPassTarget(self: anytype, command_buffer: u64) void {
    self.vulkan_fsi_tracker.setTarget(command_buffer, 0, .unknown);
    for (&self.tracked_command_targets) |*record| {
        if (record.synthetic == command_buffer) {
            record.current_pass_target = 0;
            record.current_pass_target_source = .unknown;
            return;
        }
    }
}

pub fn addCommandPassEdge(self: anytype, record: *TrackedCommandTargets, set: u64) void {
    if (record.current_pass_target == 0 or set == 0) return;
    for (record.pass_edges[0..record.pass_edge_count]) |edge| {
        if (edge.target == record.current_pass_target and edge.set == set) return;
    }
    if (record.pass_edge_count == record.pass_edges.len) {
        self.noteTargetOverflow(.command_pass_edges);
        return;
    }
    record.pass_edges[record.pass_edge_count] = .{ .target = record.current_pass_target, .set = set };
    record.pass_edge_count += 1;
}

pub fn commitCommandPassSources(self: anytype, command_buffer: u64) void {
    var edges: [MAX_TRACKED_PASS_EDGES]TrackedPassEdge = @splat(.{});
    var count: usize = 0;
    for (self.tracked_command_targets) |record| {
        if (record.synthetic != command_buffer) continue;
        count = record.pass_edge_count;
        if (count != 0) @memcpy(edges[0..count], record.pass_edges[0..count]);
        break;
    }
    for (edges[0..count]) |edge| {
        const real_target = self.real_vulkan.realImage(edge.target) orelse continue;
        const set = self.trackedDescriptorSet(edge.set) orelse continue;
        for (set.images[0..@as(usize, @intCast(set.image_count))]) |image| {
            if (image.image == 0) continue;
            const real_sampled = self.real_vulkan.realImage(image.image) orelse continue;
            var sampling: rosette_gpu.PresentPassSourceView = .{ .image = real_sampled, .view = image.image_view };
            if (self.trackedImageView(image.image_view)) |view| {
                sampling.format = view.format;
                sampling.components = view.components;
                sampling.base_mip = view.base_mip;
                sampling.base_layer = view.base_layer;
                sampling.view_type = view.view_type;
                sampling.known = view.format != 0;
            }
            self.present_chain.noteRenderPassSourceView(real_target, sampling);
            self.vulkan_pass_source_edges +|= 1;
        }
    }
}

pub fn rejectDescriptorBind(
    self: anytype,
    reason: DescriptorBindRejectReason,
    command_buffer: u64,
    layout: u64,
    set_count: u64,
    sets: u64,
    dynamic_count: u64,
    dynamic_offsets: u64,
    unmapped_handle: u64,
) void {
    std.debug.assert(reason != .none and reason != .count);
    const admission = &self.vulkan_descriptor_bind_admission;
    admission.rejected +|= 1;
    admission.rejected_by_reason[@intFromEnum(reason)] +|= 1;
    admission.last_reason = reason;
    admission.last_command_buffer = command_buffer;
    admission.last_layout = layout;
    admission.last_set_count = set_count;
    admission.last_sets = sets;
    admission.last_dynamic_count = dynamic_count;
    admission.last_dynamic_offsets = dynamic_offsets;
    admission.last_unmapped_handle = unmapped_handle;

    const reason_count = admission.rejected_by_reason[@intFromEnum(reason)];
    if (reason_count <= 4 or (reason_count & (reason_count - 1)) == 0) {
        machoCapturePrint(
            "macho-processor: Vulkan descriptor bind refused before native call: reason={s} reason_count={d} entries={d} forwarded={d} command_buffer=0x{x} layout=0x{x} set_count={d} sets=0x{x} dynamic_count={d} dynamic_offsets=0x{x} unmapped_handle=0x{x}; the command was handled but is not counted as native graphics work\n",
            .{
                @tagName(reason),
                reason_count,
                admission.entries,
                admission.forwarded,
                command_buffer,
                layout,
                set_count,
                sets,
                dynamic_count,
                dynamic_offsets,
                unmapped_handle,
            },
        );
    }
}

pub fn noteCommandDescriptorSets(self: anytype, state: anytype, command_buffer: u64, first_set: u64, guest_sets: u64, set_count: u64) void {
    if (set_count == 0) return;
    const observed = @min(set_count, MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND);
    self.vulkan_descriptor_sets_bound +|= observed;
    if (set_count > observed) {
        self.noteTargetOverflow(.command_set_array);
        self.noteCommandSampledImageUnknown(command_buffer);
    }
    for (0..@as(usize, @intCast(observed))) |index| {
        const set = state.read64(guest_sets + @as(u64, @intCast(index)) * 8);
        const set_index_value = std.math.add(u64, first_set, @as(u64, @intCast(index))) catch {
            self.noteTargetOverflow(.command_set_index);
            self.noteCommandSampledImageUnknown(command_buffer);
            break;
        };
        const set_index = std.math.cast(u32, set_index_value) orelse {
            self.noteTargetOverflow(.command_set_index);
            self.noteCommandSampledImageUnknown(command_buffer);
            break;
        };
        self.noteCommandBoundDescriptorSet(command_buffer, set_index, set);
    }
}

pub fn resolveCommandDescriptorSets(self: anytype, command_buffer: u64) void {
    var bound: [MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND]TrackedCommandDescriptorSet = [_]TrackedCommandDescriptorSet{.{}} ** MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND;
    var count: usize = 0;
    for (self.tracked_command_targets) |record| {
        if (record.synthetic != command_buffer) continue;
        count = @as(usize, @intCast(record.bound_descriptor_set_count));
        if (count != 0) @memcpy(bound[0..count], record.bound_descriptor_sets[0..count]);
        break;
    }
    if (count == 0) return;
    self.vulkan_descriptor_late_resolutions +|= @intCast(count);
    for (bound[0..count]) |descriptor| {
        self.noteCommandDescriptorSet(command_buffer, descriptor.synthetic);
    }
}

pub fn noteCommandDescriptorImages(self: anytype, state: anytype, command_buffer: u64, writes: []const abi.WriteDescriptorSet) void {
    for (writes) |write| {
        if (!isDescriptorImageType(write.descriptor_type)) continue;
        const count: usize = @intCast(write.descriptor_count);
        const address = if (write.image_info) |pointer| @intFromPtr(pointer) else 0;
        if (count != 0 and address == 0) {
            self.target_unknown_events +|= 1;
            self.noteCommandSampledImageUnknown(command_buffer);
            continue;
        }
        const observed = @min(count, MAX_TRACKED_DESCRIPTOR_IMAGES);
        if (count > observed) self.noteTargetOverflow(.descriptor_image_array);
        for (0..observed) |index| {
            var info: abi.DescriptorImageInfo = undefined;
            const offset = @as(u64, @intCast(index)) * @sizeOf(abi.DescriptorImageInfo);
            if (!copyGuestValue(abi.DescriptorImageInfo, state, address + offset, &info)) {
                self.target_unknown_events +|= 1;
                self.noteCommandSampledImageUnknown(command_buffer);
                break;
            }
            self.vulkan_descriptor_image_infos_observed +|= 1;
            if (info.image_view == 0) continue;
            if (self.trackedImageView(info.image_view)) |view| {
                self.addCommandSampledImage(command_buffer, view.image);
                if (view.image == 0) {
                    self.vulkan_descriptor_unknown_image_views +|= 1;
                    self.noteCommandSampledImageUnknown(command_buffer);
                }
            } else {
                self.vulkan_descriptor_unknown_image_views +|= 1;
                self.target_unknown_events +|= 1;
                self.noteCommandSampledImageUnknown(command_buffer);
            }
        }
    }
}

pub fn mutableCommandTargets(self: anytype, synthetic: u64) ?*TrackedCommandTargets {
    if (synthetic == 0) return null;
    for (&self.tracked_command_targets) |*record| {
        if (record.synthetic == synthetic) return record;
    }
    for (&self.tracked_command_targets) |*record| {
        if (record.synthetic == 0) {
            record.* = .{ .synthetic = synthetic };
            return record;
        }
    }
    self.noteTargetOverflow(.command_target_table);
    return null;
}

pub fn resetCommandTargets(self: anytype, synthetic: u64) void {
    // Pipeline and index bindings are command-buffer recording state. A
    // recycled buffer must not inherit the rectangle expansion decision
    // from its previous recording, even if its first draw precedes a new
    // graphics pipeline or index bind.
    for (&self.rect_expand_command_states) |*entry| {
        if (entry.command_buffer == synthetic) {
            entry.* = .{ .command_buffer = synthetic };
            break;
        }
    }
    self.vulkan_fsi_tracker.resetCommandBuffer(synthetic);
    const record = self.mutableCommandTargets(synthetic) orelse return;
    record.* = .{ .synthetic = synthetic };
}

pub fn addCommandImage(self: anytype, command_buffer: u64, image: u64) void {
    if (image == 0) {
        self.target_unknown_events +|= 1;
        return;
    }
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    for (record.images[0..@as(usize, @intCast(record.image_count))]) |known| {
        if (known == image) return;
    }
    if (@as(usize, @intCast(record.image_count)) == record.images.len) {
        self.noteTargetOverflow(.command_images);
        return;
    }
    record.images[@as(usize, @intCast(record.image_count))] = image;
    record.image_count += 1;
}

pub fn addCommandImageView(self: anytype, command_buffer: u64, image_view: u64) void {
    const view = self.trackedImageView(image_view) orelse {
        self.target_unknown_events +|= 1;
        return;
    };
    self.addCommandImage(command_buffer, view.image);
}

pub fn addCommandTransfer(self: anytype, command_buffer: u64, source: u64, destination: u64, kind: rosette_gpu.PresentTransferKind) void {
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    if (@as(usize, @intCast(record.transfer_count)) == record.transfers.len) {
        self.noteTargetOverflow(.command_transfers);
        return;
    }
    record.transfers[@as(usize, @intCast(record.transfer_count))] = .{
        .source = source,
        .destination = destination,
        .kind = kind,
    };
    record.transfer_count += 1;
}

pub fn noteCommandTransfer(self: anytype, command_buffer: u64, source: u64, destination: u64, kind: rosette_gpu.PresentTransferKind) void {
    self.noteCommandImageTarget(command_buffer, destination, .content);
    self.addCommandTransfer(command_buffer, source, destination, kind);
}

pub fn noteCommandImageViewTransfer(
    self: anytype,
    command_buffer: u64,
    source_view: u64,
    destination_view: u64,
    kind: rosette_gpu.PresentTransferKind,
) void {
    if (source_view == 0 or destination_view == 0) return;
    const source = self.trackedImageView(source_view) orelse {
        self.target_unknown_events +|= 1;
        self.addCommandTransfer(command_buffer, 0, 0, kind);
        return;
    };
    const destination = self.trackedImageView(destination_view) orelse {
        self.target_unknown_events +|= 1;
        self.addCommandTransfer(command_buffer, source.image, 0, kind);
        return;
    };
    self.addCommandImage(command_buffer, destination.image);
    // A resolve is itself a producer of the destination image. It can be
    // the only operation that touches the acquired image in this command
    // buffer, so do not require a separate draw/dispatch mark before the
    // present chain can classify it as content.
    self.noteCommandTargets(command_buffer, .content);
    self.addCommandTransfer(command_buffer, source.image, destination.image, kind);
}

pub fn noteCommandImageTarget(self: anytype, command_buffer: u64, synthetic_image: u64, write: WriteKind) void {
    self.addCommandImage(command_buffer, synthetic_image);
    self.noteCommandTargets(command_buffer, write);
}

pub fn trackImageView(self: anytype, state: anytype, synthetic: u64, create_info: u64) void {
    var info: marshal.ImageViewCreateInfo = undefined;
    if (!copyGuestValue(marshal.ImageViewCreateInfo, state, create_info, &info)) {
        self.target_unknown_events +|= 1;
        return;
    }
    if (!self.recordImageView(synthetic, info.image)) self.noteTargetOverflow(.image_view_table);
    if (self.tracked_image_view_index.find(synthetic)) |slot| {
        self.tracked_image_views[slot].format = info.format;
        self.tracked_image_views[slot].components = info.components;
        self.tracked_image_views[slot].base_mip = info.subresource_range[1];
        self.tracked_image_views[slot].base_layer = info.subresource_range[3];
        self.tracked_image_views[slot].view_type = info.view_type;
    }
}

pub fn trackFramebuffer(self: anytype, state: anytype, synthetic: u64, create_info: u64) void {
    var info: marshal.FramebufferCreateInfo = undefined;
    if (!copyGuestValue(marshal.FramebufferCreateInfo, state, create_info, &info)) {
        self.target_unknown_events +|= 1;
        return;
    }
    if (info.attachment_count > MAX_TRACKED_TARGET_ATTACHMENTS) {
        self.noteTargetOverflow(.framebuffer_attachments);
        return;
    }
    var attachments: [MAX_TRACKED_TARGET_ATTACHMENTS]u64 = [_]u64{0} ** MAX_TRACKED_TARGET_ATTACHMENTS;
    const attachment_address = if (info.attachments) |pointer| @intFromPtr(pointer) else 0;
    if (!copyGuestStructs(u64, state, attachment_address, info.attachment_count, &attachments)) {
        self.target_unknown_events +|= 1;
        return;
    }
    for (&self.tracked_framebuffers) |*record| {
        if (record.synthetic == synthetic or record.synthetic == 0) {
            record.* = .{ .synthetic = synthetic, .attachment_count = @intCast(info.attachment_count) };
            if (info.attachment_count != 0) {
                const count = @as(usize, @intCast(info.attachment_count));
                @memcpy(record.attachments[0..count], attachments[0..count]);
            }
            return;
        }
    }
    self.noteTargetOverflow(.framebuffer_table);
}

pub fn trackRenderPass(self: anytype, state: anytype, synthetic: u64, create_info: u64) void {
    var info: marshal.RenderPassCreateInfo = undefined;
    if (!copyGuestValue(marshal.RenderPassCreateInfo, state, create_info, &info)) {
        self.target_unknown_events +|= 1;
        return;
    }
    var attachments: [32]marshal.AttachmentDescription = [_]marshal.AttachmentDescription{.{}} ** 32;
    var subpasses: [32]marshal.SubpassDescription = [_]marshal.SubpassDescription{.{}} ** 32;
    if (info.attachment_count > attachments.len or info.subpass_count > subpasses.len or
        !copyGuestStructs(marshal.AttachmentDescription, state, if (info.attachments) |pointer| @intFromPtr(pointer) else 0, info.attachment_count, &attachments) or
        !copyGuestStructs(marshal.SubpassDescription, state, if (info.subpasses) |pointer| @intFromPtr(pointer) else 0, info.subpass_count, &subpasses))
    {
        self.target_unknown_events +|= 1;
        return;
    }

    var color_load_clear = false;
    var resolve_count: usize = 0;
    var resolve_sources: [MAX_TRACKED_TARGET_ATTACHMENTS]u32 = [_]u32{0} ** MAX_TRACKED_TARGET_ATTACHMENTS;
    var resolve_destinations: [MAX_TRACKED_TARGET_ATTACHMENTS]u32 = [_]u32{0} ** MAX_TRACKED_TARGET_ATTACHMENTS;
    for (subpasses[0..@as(usize, @intCast(info.subpass_count))]) |subpass| {
        if (subpass.color_attachment_count > MAX_TRACKED_TARGET_ATTACHMENTS) {
            self.noteTargetOverflow(.render_pass_attachments);
            return;
        }
        var colors: [MAX_TRACKED_TARGET_ATTACHMENTS]marshal.AttachmentReference = [_]marshal.AttachmentReference{.{}} ** MAX_TRACKED_TARGET_ATTACHMENTS;
        if (!copyGuestStructs(marshal.AttachmentReference, state, if (subpass.color_attachments) |pointer| @intFromPtr(pointer) else 0, subpass.color_attachment_count, &colors)) {
            self.target_unknown_events +|= 1;
            return;
        }
        for (colors[0..@as(usize, @intCast(subpass.color_attachment_count))]) |reference| {
            if (reference.attachment == 0xFFFF_FFFF or reference.attachment >= info.attachment_count) continue;
            if (attachments[@as(usize, @intCast(reference.attachment))].load_op == VK_ATTACHMENT_LOAD_OP_CLEAR) {
                color_load_clear = true;
            }
        }
        if (subpass.resolve_attachments) |pointer| {
            var resolves: [MAX_TRACKED_TARGET_ATTACHMENTS]marshal.AttachmentReference = [_]marshal.AttachmentReference{.{}} ** MAX_TRACKED_TARGET_ATTACHMENTS;
            if (!copyGuestStructs(marshal.AttachmentReference, state, @intFromPtr(pointer), subpass.color_attachment_count, &resolves)) {
                self.target_unknown_events +|= 1;
                return;
            }
            for (0..@as(usize, @intCast(subpass.color_attachment_count))) |index| {
                const source = colors[index].attachment;
                const destination = resolves[index].attachment;
                if (source == 0xFFFF_FFFF or destination == 0xFFFF_FFFF or
                    source >= info.attachment_count or destination >= info.attachment_count) continue;
                if (resolve_count == MAX_TRACKED_TARGET_ATTACHMENTS) {
                    self.noteTargetOverflow(.render_pass_resolves);
                    return;
                }
                resolve_sources[resolve_count] = source;
                resolve_destinations[resolve_count] = destination;
                resolve_count += 1;
            }
        }
    }

    for (&self.tracked_render_passes) |*record| {
        if (record.synthetic == synthetic or record.synthetic == 0) {
            record.* = .{
                .synthetic = synthetic,
                .color_load_clear = color_load_clear,
                .resolve_count = @intCast(resolve_count),
                .resolve_sources = resolve_sources,
                .resolve_destinations = resolve_destinations,
            };
            return;
        }
    }
    self.noteTargetOverflow(.render_pass_table);
}

pub fn trackFramebufferTargets(self: anytype, command_buffer: u64, framebuffer: u64) void {
    const record = self.trackedFramebuffer(framebuffer) orelse {
        self.target_unknown_events +|= 1;
        return;
    };
    for (record.attachments[0..@as(usize, @intCast(record.attachment_count))]) |image_view| {
        self.addCommandImageView(command_buffer, image_view);
    }
}

pub fn trackRenderPassTransfers(self: anytype, command_buffer: u64, render_pass: u64, framebuffer: u64) void {
    const pass = self.trackedRenderPass(render_pass) orelse return;
    const frame = self.trackedFramebuffer(framebuffer) orelse {
        if (pass.resolve_count != 0) self.target_unknown_events +|= 1;
        return;
    };
    for (0..@as(usize, @intCast(pass.resolve_count))) |index| {
        const source_attachment = pass.resolve_sources[index];
        const destination_attachment = pass.resolve_destinations[index];
        if (source_attachment >= @as(u32, @intCast(frame.attachment_count)) or destination_attachment >= @as(u32, @intCast(frame.attachment_count))) {
            self.target_unknown_events +|= 1;
            continue;
        }
        self.noteCommandImageViewTransfer(
            command_buffer,
            frame.attachments[@as(usize, @intCast(source_attachment))],
            frame.attachments[@as(usize, @intCast(destination_attachment))],
            .render_pass_resolve,
        );
    }
}

pub fn noteCommandTargets(self: anytype, command_buffer: u64, write: WriteKind) void {
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    const merged = WriteKind.strongest(record.write_kind, write);
    if (merged != record.write_kind) {
        record.write_kind = merged;
        self.vulkan_command_write_marks +|= 1;
        if (merged == .content) self.vulkan_command_content_marks +|= 1;
    }
}

pub fn noteLoadClearTarget(self: anytype, command_buffer: u64, source: []const u8) void {
    self.vulkan_render_pass_load_clear_calls +|= 1;
    if (self.vulkan_render_pass_load_clear_calls == 1) {
        machoCapturePrint(
            "macho-processor: Vulkan render-pass loadOp clear attributed as image write: source={s} command_buffer=0x{x}\n",
            .{ source, command_buffer },
        );
    }
    // A load clear writes the attachment and can only write one colour.
    // Both halves of that matter: dropping it would lose the write, and
    // promoting it to content is what certified an empty frame.
    self.noteCommandTargets(command_buffer, frame_content.renderPassLoadKind(true));
}

pub fn mergeCommandTargets(self: anytype, destination: u64, source: u64) void {
    if (destination == source) return;
    self.vulkan_fsi_tracker.mergeCommandBuffer(destination, source);
    var images: [MAX_TRACKED_TARGET_ATTACHMENTS]u64 = [_]u64{0} ** MAX_TRACKED_TARGET_ATTACHMENTS;
    var sampled_images: [MAX_TRACKED_DESCRIPTOR_IMAGES]u64 = [_]u64{0} ** MAX_TRACKED_DESCRIPTOR_IMAGES;
    var transfers: [MAX_TRACKED_RESOURCE_TRANSFERS]TrackedImageTransfer = [_]TrackedImageTransfer{.{}} ** MAX_TRACKED_RESOURCE_TRANSFERS;
    var bound_descriptor_sets: [MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND]TrackedCommandDescriptorSet = [_]TrackedCommandDescriptorSet{.{}} ** MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND;
    var count: usize = 0;
    var sampled_count: usize = 0;
    var transfer_count: usize = 0;
    var bound_descriptor_set_count: usize = 0;
    var sampled_unknown = false;
    var write_kind: WriteKind = .none;
    var graphics_state: GraphicsStateTrace = .{};
    var graphics_state_seen = false;
    for (self.tracked_command_targets) |record| {
        if (record.synthetic != source) continue;
        count = @as(usize, @intCast(record.image_count));
        if (count != 0) @memcpy(images[0..count], record.images[0..count]);
        sampled_count = @as(usize, @intCast(record.sampled_image_count));
        if (sampled_count != 0) @memcpy(sampled_images[0..sampled_count], record.sampled_images[0..sampled_count]);
        transfer_count = @as(usize, @intCast(record.transfer_count));
        if (transfer_count != 0) @memcpy(transfers[0..transfer_count], record.transfers[0..transfer_count]);
        bound_descriptor_set_count = @as(usize, @intCast(record.bound_descriptor_set_count));
        if (bound_descriptor_set_count != 0) @memcpy(bound_descriptor_sets[0..bound_descriptor_set_count], record.bound_descriptor_sets[0..bound_descriptor_set_count]);
        sampled_unknown = record.sampled_images_unknown;
        write_kind = record.write_kind;
        graphics_state = record.graphics_state;
        graphics_state_seen = record.graphics_state.pipeline_bound or record.graphics_state.push_constants_valid or
            record.graphics_state.viewport_valid or record.graphics_state.scissor_valid;
        break;
    }
    for (images[0..count]) |image| self.addCommandImage(destination, image);
    for (sampled_images[0..sampled_count]) |image| self.addCommandSampledImage(destination, image);
    if (sampled_unknown) self.noteCommandSampledImageUnknown(destination);
    for (bound_descriptor_sets[0..bound_descriptor_set_count]) |descriptor| {
        self.noteCommandBoundDescriptorSet(destination, descriptor.set_index, descriptor.synthetic);
    }
    for (transfers[0..transfer_count]) |transfer| self.addCommandTransfer(destination, transfer.source, transfer.destination, transfer.kind);
    if (write_kind != .none) self.noteCommandTargets(destination, write_kind);
    if (graphics_state_seen and self.graphicsStateTrackingEnabled()) {
        if (self.mutableCommandTargets(destination)) |record| record.graphics_state = graphics_state;
    }
    var pass_edges: [MAX_TRACKED_PASS_EDGES]TrackedPassEdge = @splat(.{});
    var pass_edge_count: usize = 0;
    for (self.tracked_command_targets) |record| {
        if (record.synthetic != source) continue;
        pass_edge_count = record.pass_edge_count;
        if (pass_edge_count != 0) @memcpy(pass_edges[0..pass_edge_count], record.pass_edges[0..pass_edge_count]);
        break;
    }
    if (pass_edge_count != 0) {
        if (self.mutableCommandTargets(destination)) |record| {
            const saved_target = record.current_pass_target;
            for (pass_edges[0..pass_edge_count]) |edge| {
                record.current_pass_target = edge.target;
                self.addCommandPassEdge(record, edge.set);
            }
            record.current_pass_target = saved_target;
        }
    }
}

pub fn noteFsiSubmittedCommandBuffer(self: anytype, command_buffer: u64, queue_submit_ordinal: u64, batch_index: u32) void {
    if (self.vulkan_fsi_tracker.noteSubmitted(command_buffer, queue_submit_ordinal, batch_index)) |submitted| {
        if (sparseVulkanSuccessLog(self.vulkan_fsi_tracker.submitted_command_buffers)) machoCapturePrint(
            "macho-processor: Vulkan FSI SUBMIT: ordinal={d} queue_submit={d} batch={d} command_buffer=0x{x} fsi_commands={d} last(kind/pipeline_hash/shader_hash/module/target/source/draw_ordinal)={s}/0x{x}/0x{x}/{d}/0x{x}/{s}/{d}; host success proves MoltenVK accepted this recorded interlock draw sequence\n",
            .{ self.vulkan_fsi_tracker.submitted_command_buffers, submitted.queue_submit_ordinal, submitted.batch_index, submitted.draw.command_buffer, submitted.fsi_draws_in_command_buffer, @tagName(submitted.draw.kind), submitted.draw.pipeline_hash, submitted.draw.shader_hash, submitted.draw.module_id, submitted.draw.target_image, @tagName(submitted.draw.target_source), submitted.draw.draw_ordinal },
        );
    }
}

pub fn noteSubmittedCommandTargets(self: anytype, command_buffer: u64) void {
    self.resolveCommandDescriptorSets(command_buffer);
    self.auditCommandTexelCustody(command_buffer);
    self.commitCommandPassSources(command_buffer);
    var images: [MAX_TRACKED_TARGET_ATTACHMENTS]u64 = [_]u64{0} ** MAX_TRACKED_TARGET_ATTACHMENTS;
    var sampled_images: [MAX_TRACKED_DESCRIPTOR_IMAGES]u64 = [_]u64{0} ** MAX_TRACKED_DESCRIPTOR_IMAGES;
    var transfers: [MAX_TRACKED_RESOURCE_TRANSFERS]TrackedImageTransfer = [_]TrackedImageTransfer{.{}} ** MAX_TRACKED_RESOURCE_TRANSFERS;
    var count: usize = 0;
    var sampled_count: usize = 0;
    var transfer_count: usize = 0;
    var sampled_unknown = false;
    var write_kind: WriteKind = .none;
    for (self.tracked_command_targets) |record| {
        if (record.synthetic != command_buffer) continue;
        count = @as(usize, @intCast(record.image_count));
        if (count != 0) @memcpy(images[0..count], record.images[0..count]);
        sampled_count = @as(usize, @intCast(record.sampled_image_count));
        if (sampled_count != 0) @memcpy(sampled_images[0..sampled_count], record.sampled_images[0..sampled_count]);
        transfer_count = @as(usize, @intCast(record.transfer_count));
        if (transfer_count != 0) @memcpy(transfers[0..transfer_count], record.transfers[0..transfer_count]);
        sampled_unknown = record.sampled_images_unknown;
        write_kind = record.write_kind;
        break;
    }
    self.vulkan_target_submission_events +|= 1;
    if (sparseVulkanSuccessLog(self.vulkan_target_submission_events)) {
        machoCapturePrint(
            "macho-processor: Vulkan target submission sample: serial={d} command_buffer=0x{x} images={d} sampled_images={d} transfers={d} sampled_unknown={} write={s} first_image=0x{x}\n",
            .{ self.vulkan_target_submission_events, command_buffer, count, sampled_count, transfer_count, sampled_unknown, write_kind.label(), if (count == 0) 0 else images[0] },
        );
    }
    var real_images: [MAX_TRACKED_TARGET_ATTACHMENTS]u64 = [_]u64{0} ** MAX_TRACKED_TARGET_ATTACHMENTS;
    var real_count: usize = 0;
    for (images[0..count]) |image| {
        const real_image = self.real_vulkan.realImage(image) orelse {
            self.noteGuestImageTarget(image, write_kind);
            continue;
        };
        real_images[real_count] = real_image;
        real_count += 1;
        self.noteGuestImageTarget(image, write_kind);
    }

    var real_sampled_images: [MAX_TRACKED_DESCRIPTOR_IMAGES]u64 = [_]u64{0} ** MAX_TRACKED_DESCRIPTOR_IMAGES;
    var real_sampled_count: usize = 0;
    for (sampled_images[0..sampled_count]) |image| {
        if (real_sampled_count == real_sampled_images.len) {
            self.noteTargetOverflow(.submission_sampled_images);
            break;
        }
        const real_image = self.real_vulkan.realImage(image) orelse {
            self.target_unknown_events +|= 1;
            sampled_unknown = true;
            continue;
        };
        real_sampled_images[real_sampled_count] = real_image;
        real_sampled_count += 1;
    }
    if (sampled_unknown) {
        if (real_sampled_count < real_sampled_images.len) {
            real_sampled_images[real_sampled_count] = 0;
            real_sampled_count += 1;
        } else {
            self.noteTargetOverflow(.submission_sampled_sentinel);
        }
    }

    var real_transfers: [MAX_TRACKED_RESOURCE_TRANSFERS]rosette_gpu.PresentResourceTransfer = [_]rosette_gpu.PresentResourceTransfer{.{}} ** MAX_TRACKED_RESOURCE_TRANSFERS;
    var real_transfer_count: usize = 0;
    for (transfers[0..transfer_count]) |transfer| {
        if (real_transfer_count == real_transfers.len) {
            self.noteTargetOverflow(.submission_transfers);
            break;
        }
        const real_source = if (transfer.source == 0)
            0
        else
            self.real_vulkan.realImage(transfer.source) orelse blk: {
                self.target_unknown_events +|= 1;
                break :blk 0;
            };
        const real_destination = if (transfer.destination == 0)
            0
        else
            self.real_vulkan.realImage(transfer.destination) orelse blk: {
                self.target_unknown_events +|= 1;
                break :blk 0;
            };
        real_transfers[real_transfer_count] = .{
            .source = real_source,
            .destination = real_destination,
            .kind = transfer.kind,
        };
        real_transfer_count += 1;
    }
    self.present_chain.noteResourceSubmission(
        real_images[0..real_count],
        write_kind,
        real_sampled_images[0..real_sampled_count],
        real_transfers[0..real_transfer_count],
    );
}

pub fn noteGuestImageTarget(self: anytype, synthetic_image: u64, write_kind: WriteKind) void {
    const real_image = self.real_vulkan.realImage(synthetic_image) orelse {
        self.target_unknown_events +|= 1;
        if (self.target_unknown_events <= 4) {
            machoCapturePrint(
                "macho-processor: Vulkan target attribution unknown: guest_image=0x{x} mapped=false write={s}\n",
                .{ synthetic_image, write_kind.label() },
            );
        }
        return;
    };
    self.target_attribution_events +|= 1;
    switch (self.present_chain.noteTargetImage(real_image, write_kind)) {
        .offscreen_image => self.target_offscreen_events +|= 1,
        .unknown => self.target_unknown_events +|= 1,
        .none, .swapchain_image => {},
    }
}

pub fn forgetImageView(self: anytype, synthetic: u64) void {
    if (self.tracked_image_view_index.remove(synthetic)) |slot| self.tracked_image_views[slot] = .{};
}

pub fn forgetDescriptorSet(self: anytype, synthetic: u64) void {
    if (self.native_texture_state) |native| if (self.real_vulkan.realDescriptorSet(synthetic)) |real| native.forgetSet(&self.real_vulkan, real);
    if (self.tracked_descriptor_set_index.remove(synthetic)) |slot| self.tracked_descriptor_sets[slot] = .{};
}

pub fn forgetRenderPass(self: anytype, synthetic: u64) void {
    for (&self.tracked_render_passes) |*record| {
        if (record.synthetic == synthetic) record.* = .{};
    }
}

pub fn forgetFramebuffer(self: anytype, synthetic: u64) void {
    for (&self.tracked_framebuffers) |*record| {
        if (record.synthetic == synthetic) record.* = .{};
    }
}
