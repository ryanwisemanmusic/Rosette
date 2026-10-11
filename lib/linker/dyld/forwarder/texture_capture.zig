// Split implementation for Forwarder; wrappers keep the public state API stable.
const process = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = process.__ForwarderInternals;
const Forwarder = process.Forwarder;
const BrightnessLoss = __ForwarderInternals._BrightnessLoss;
const HandleMap = __ForwarderInternals._HandleMap;
const HostFrameCaptureResolver = __ForwarderInternals._HostFrameCaptureResolver;
const HostFrameCounterResolver = __ForwarderInternals._HostFrameCounterResolver;
const LadderStage = __ForwarderInternals._LadderStage;
const PIXEL_PROBE_INITIAL_SAMPLES = __ForwarderInternals._PIXEL_PROBE_INITIAL_SAMPLES;
const PIXEL_PROBE_MAX_BYTES = __ForwarderInternals._PIXEL_PROBE_MAX_BYTES;
const PendingReadbackCapture = __ForwarderInternals._PendingReadbackCapture;
const ReadbackSample = __ForwarderInternals._ReadbackSample;
const VulkanMemoryAllocation = __ForwarderInternals._VulkanMemoryAllocation;
const WriteKind = __ForwarderInternals._WriteKind;
const abi = __ForwarderInternals._abi;
const campaignDiagnosticFrame = __ForwarderInternals._campaignDiagnosticFrame;
const frame_capture = __ForwarderInternals._frame_capture;
const fsi_diagnostics = __ForwarderInternals._fsi_diagnostics;
const gpu_vulkan = __ForwarderInternals._gpu_vulkan;
const guest_context = __ForwarderInternals._guest_context;
const imageReadbackAugmentable = __ForwarderInternals._imageReadbackAugmentable;
const machoCapturePrint = __ForwarderInternals._machoCapturePrint;
const marshal = __ForwarderInternals._marshal;
const present_pacing = __ForwarderInternals._present_pacing;
const rangeContains = __ForwarderInternals._rangeContains;
const registerOpaqueHandle = __ForwarderInternals._registerOpaqueHandle;
const resolvedPresentResult = __ForwarderInternals._resolvedPresentResult;
const rosette_gpu = __ForwarderInternals._rosette_gpu;
const shouldForceContentPixelProbe = __ForwarderInternals._shouldForceContentPixelProbe;
const sparseVulkanSuccessLog = __ForwarderInternals._sparseVulkanSuccessLog;
const std = __ForwarderInternals._std;
const transport_timing = __ForwarderInternals._transport_timing;
const vkErrorInitializationFailed = __ForwarderInternals._vkErrorInitializationFailed;
const vkErrorOutOfHostMemory = __ForwarderInternals._vkErrorOutOfHostMemory;
const NativeComputePipelineCall = __ForwarderInternals._NativeComputePipelineCall;
const NativeGraphicsPipelineCall = __ForwarderInternals._NativeGraphicsPipelineCall;
const PipelineMarshalFailure = __ForwarderInternals._PipelineMarshalFailure;
const SpecializationScratch = __ForwarderInternals._SpecializationScratch;
const copyGuestBytes = Forwarder.copyGuestBytes;
const copyGuestStructs = Forwarder.copyGuestStructs;
const copyMappedBytes = Forwarder.copyMappedBytes;
const findResource = Forwarder.findResource;
const forgetDescriptorSet = Forwarder.forgetDescriptorSet;
const fsiNoteCommandBuffersAllocated = Forwarder.fsiNoteCommandBuffersAllocated;
const invoke = Forwarder.invoke;
const lockVulkanQueueApi = Forwarder.lockVulkanQueueApi;
const mapVulkanHandle = Forwarder.mapVulkanHandle;
const mapVulkanHandleOwned = Forwarder.mapVulkanHandleOwned;
const nextVulkanObject = Forwarder.nextVulkanObject;
const noteDescriptorSetPool = Forwarder.noteDescriptorSetPool;
const noteRealVulkanResult = Forwarder.noteRealVulkanResult;
const noteVulkanMapCapacityRefusal = Forwarder.noteVulkanMapCapacityRefusal;
const presentWindowFrame = Forwarder.presentWindowFrame;
const realDeviceLostResult = Forwarder.realDeviceLostResult;
const reclaimOrphanedDescriptorSets = Forwarder.reclaimOrphanedDescriptorSets;
const refuseVulkanCall = Forwarder.refuseVulkanCall;
const releaseVulkanHandle = Forwarder.releaseVulkanHandle;
const reportPresentChain = Forwarder.reportPresentChain;
const retireNativePresenterForGuestSwapchain = Forwarder.retireNativePresenterForGuestSwapchain;
const trackPresentCompletion = Forwarder.trackPresentCompletion;

pub fn pixelProbeBytesPerPixel(format: u32) ?u64 {
    return switch (format) {
        abi.FORMAT_R8G8B8A8_UNORM,
        abi.FORMAT_R8G8B8A8_SRGB,
        abi.FORMAT_B8G8R8A8_UNORM,
        abi.FORMAT_B8G8R8A8_SRGB,
        abi.FORMAT_A8B8G8R8_UNORM_PACK32,
        abi.FORMAT_A2B10G10R10_UNORM_PACK32,
        => 4,
        else => null,
    };
}

pub fn notePixelProbeResult(
    self: anytype,
    swapchain: abi.SwapchainKHR,
    evidence: rosette_gpu.PresentPixelEvidence,
    hash: u64,
    frame: u64,
    uniform_value: u32,
    image: u64,
    write_kind: WriteKind,
) void {
    if (evidence.showsDetail()) self.pixel_probe.detail_observed = true;
    self.present_chain.notePixelProbe(swapchain, evidence, hash, frame, uniform_value);
    self.present_chain.notePixelProbeContext(swapchain, image, write_kind);
}

pub fn pixelProbeFailure(
    self: anytype,
    swapchain: abi.SwapchainKHR,
    frame: u64,
    result: abi.Result,
    reason: []const u8,
    image: u64,
    write_kind: WriteKind,
) void {
    self.pixel_probe.failures +|= 1;
    self.pixel_probe.last_result = result;
    self.pixel_probe.last_swapchain = swapchain;
    self.notePixelProbeResult(swapchain, .unavailable, 0, frame, 0, image, write_kind);
    if (self.pixel_probe.failures <= 4) {
        machoCapturePrint(
            "macho-processor: PIXEL PROBE failed: swapchain=0x{x} frame={d} image=0x{x} write_kind={s} result={d} reason={s}\n",
            .{ swapchain, frame, image, write_kind.label(), result, reason },
        );
    }
}

pub fn destroyFsiZpdSinkResources(self: anytype) void {
    const device = self.real_vulkan.device;
    if (device != null and !self.real_vulkan.device_lost) {
        if (self.fsi_zpd_sink.buffer != 0) {
            if (self.real_vulkan.fn_ptrs.destroy_buffer) |destroy| {
                destroy(device.?, self.fsi_zpd_sink.buffer, null);
            }
        }
        if (self.fsi_zpd_sink.memory != 0) {
            if (self.real_vulkan.fn_ptrs.free_memory) |free| {
                free(device.?, self.fsi_zpd_sink.memory, null);
            }
        }
    }
    // A lost device owns and releases its remaining allocations as part
    // of vkDestroyDevice; do not call child destructors on that device.
    self.fsi_zpd_sink = .{};
}

pub fn ensureFsiZpdSink(self: anytype, range: u64) ?abi.Buffer {
    if (!gpu_vulkan.fsi_descriptor_repair.isExpectedZpdSinkRange(0, range)) return null;
    if (self.fsi_zpd_sink.buffer != 0 and self.fsi_zpd_sink.range == range) {
        return self.fsi_zpd_sink.buffer;
    }
    if (self.fsi_zpd_sink.buffer != 0 or self.real_vulkan.device_lost) return null;

    const device = self.real_vulkan.device orelse return null;
    const create_buffer = self.real_vulkan.fn_ptrs.create_buffer orelse return null;
    const get_requirements = self.real_vulkan.fn_ptrs.get_buffer_memory_requirements orelse return null;
    const allocate_memory = self.real_vulkan.fn_ptrs.allocate_memory orelse return null;
    const bind_memory = self.real_vulkan.fn_ptrs.bind_buffer_memory orelse return null;
    const map_memory = self.real_vulkan.fn_ptrs.map_memory orelse return null;
    const unmap_memory = self.real_vulkan.fn_ptrs.unmap_memory orelse return null;

    var complete = false;
    defer if (!complete) self.destroyFsiZpdSinkResources();

    const buffer_info = abi.BufferCreateInfo{
        .size = range,
        .usage = abi.BUFFER_USAGE_STORAGE_BUFFER_BIT,
    };
    var buffer: abi.Buffer = 0;
    var result = create_buffer(device, &buffer_info, null, &buffer);
    if (result != abi.SUCCESS or buffer == 0) {
        machoCapturePrint("macho-processor: FSI ZPD sink create failed: VkResult={d} buffer=0x{x} range={d}\n", .{ result, buffer, range });
        return null;
    }
    self.fsi_zpd_sink.buffer = buffer;
    self.fsi_zpd_sink.range = range;

    var requirements: abi.MemoryRequirements = .{};
    get_requirements(device, buffer, &requirements);
    if (requirements.size < range or requirements.memory_type_bits == 0) {
        machoCapturePrint("macho-processor: FSI ZPD sink requirements invalid: size={d} alignment={d} memory_type_bits=0x{x} range={d}\n", .{ requirements.size, requirements.alignment, requirements.memory_type_bits, range });
        return null;
    }

    const memory_type_count = @min(self.real_vulkan.physical_device_memory.memory_type_count, @as(u32, abi.MAX_MEMORY_TYPES));
    var selected_type: ?u32 = null;
    var selected_coherent = false;
    // A host-visible type lets us initialize the sink to zero before any
    // FSI shader can consume it. Prefer coherent unified memory, then a
    // non-coherent host-visible type that we explicitly flush.
    for (0..@as(usize, @intCast(memory_type_count))) |index| {
        const bit = @as(u32, 1) << @as(u5, @intCast(index));
        if ((requirements.memory_type_bits & bit) == 0) continue;
        const flags = self.real_vulkan.physical_device_memory.memory_types[index].property_flags;
        if ((flags & abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT) == 0) continue;
        if ((flags & abi.MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0) {
            selected_type = @intCast(index);
            selected_coherent = true;
            break;
        }
        if (selected_type == null) selected_type = @intCast(index);
    }
    const memory_type_index = selected_type orelse {
        machoCapturePrint("macho-processor: FSI ZPD sink refused: no host-visible compatible memory type; range={d} type_bits=0x{x}\n", .{ range, requirements.memory_type_bits });
        return null;
    };
    const allocate_info = abi.MemoryAllocateInfo{
        .allocation_size = requirements.size,
        .memory_type_index = memory_type_index,
    };
    var memory: abi.DeviceMemory = 0;
    result = allocate_memory(device, &allocate_info, null, &memory);
    if (result != abi.SUCCESS or memory == 0) {
        machoCapturePrint("macho-processor: FSI ZPD sink allocation failed: VkResult={d} memory=0x{x} bytes={d} type={d}\n", .{ result, memory, requirements.size, memory_type_index });
        return null;
    }
    self.fsi_zpd_sink.memory = memory;
    result = bind_memory(device, buffer, memory, 0);
    if (result != abi.SUCCESS) {
        machoCapturePrint("macho-processor: FSI ZPD sink bind failed: VkResult={d} buffer=0x{x} memory=0x{x}\n", .{ result, buffer, memory });
        return null;
    }

    var mapped: ?*anyopaque = null;
    result = map_memory(device, memory, 0, abi.WHOLE_SIZE, 0, &mapped);
    if (result != abi.SUCCESS or mapped == null) {
        machoCapturePrint("macho-processor: FSI ZPD sink map failed: VkResult={d} memory=0x{x}\n", .{ result, memory });
        return null;
    }
    defer unmap_memory(device, memory);
    @memset(@as([*]u8, @ptrCast(mapped.?))[0..@intCast(range)], 0);
    if (!selected_coherent) {
        const flush = self.real_vulkan.fn_ptrs.flush_mapped_memory_ranges orelse {
            machoCapturePrint("macho-processor: FSI ZPD sink refused: non-coherent host memory requires vkFlushMappedMemoryRanges\n", .{});
            return null;
        };
        const mapped_range = abi.MappedMemoryRange{
            .memory = memory,
            .offset = 0,
            .size = abi.WHOLE_SIZE,
        };
        result = flush(device, 1, @ptrCast(&mapped_range));
        if (result != abi.SUCCESS) {
            machoCapturePrint("macho-processor: FSI ZPD sink flush failed: VkResult={d} memory=0x{x}\n", .{ result, memory });
            return null;
        }
    }
    complete = true;
    machoCapturePrint("macho-processor: FSI ZPD sink ready: buffer=0x{x} memory=0x{x} range={d} memory_type={d} coherent={} initialized=zero\n", .{ buffer, memory, range, memory_type_index, selected_coherent });
    return buffer;
}

pub fn destroyPixelProbeResources(self: anytype) void {
    if (self.real_vulkan.device) |device| {
        if (!self.real_vulkan.device_lost) {
            if (self.pixel_probe.mapped != null) {
                if (self.real_vulkan.fn_ptrs.unmap_memory) |unmap| {
                    if (self.pixel_probe.staging_memory != 0) unmap(device, self.pixel_probe.staging_memory);
                }
            }
            if (self.pixel_probe.command_buffer) |command_buffer| {
                if (self.real_vulkan.fn_ptrs.free_command_buffers) |free| {
                    var buffers = [_]abi.CommandBuffer{command_buffer};
                    if (self.pixel_probe.command_pool != 0) free(device, self.pixel_probe.command_pool, 1, &buffers);
                }
            }
            if (self.pixel_probe.command_pool != 0) {
                if (self.real_vulkan.fn_ptrs.destroy_command_pool) |destroy| destroy(device, self.pixel_probe.command_pool, null);
            }
            if (self.pixel_probe.staging_buffer != 0) {
                if (self.real_vulkan.fn_ptrs.destroy_buffer) |destroy| destroy(device, self.pixel_probe.staging_buffer, null);
            }
            if (self.pixel_probe.staging_memory != 0) {
                if (self.real_vulkan.fn_ptrs.free_memory) |free| free(device, self.pixel_probe.staging_memory, null);
            }
        }
    }
    // Resource replacement/teardown must not erase the retained evidence,
    // preview configuration or bounded per-run capture budget.
    self.pixel_probe.staging_buffer = 0;
    self.pixel_probe.staging_memory = 0;
    self.pixel_probe.staging_size = 0;
    self.pixel_probe.mapped_coherent = false;
    self.pixel_probe.mapped = null;
    self.pixel_probe.command_pool = 0;
    self.pixel_probe.command_pool_family = abi.QUEUE_FAMILY_IGNORED;
    self.pixel_probe.command_buffer = null;
}

pub fn ensurePixelProbeResources(self: anytype, size: u64, queue_family: u32) bool {
    if (self.pixel_probe.staging_buffer != 0 and
        self.pixel_probe.command_pool != 0 and
        self.pixel_probe.command_buffer != null and
        self.pixel_probe.mapped != null and
        self.pixel_probe.command_pool_family == queue_family and
        self.pixel_probe.staging_size >= size)
    {
        return true;
    }
    self.destroyPixelProbeResources();
    var complete = false;
    defer {
        if (!complete) self.destroyPixelProbeResources();
    }
    const device = self.real_vulkan.device orelse return false;
    const create_buffer = self.real_vulkan.fn_ptrs.create_buffer orelse return false;
    const get_requirements = self.real_vulkan.fn_ptrs.get_buffer_memory_requirements orelse return false;
    const allocate_memory = self.real_vulkan.fn_ptrs.allocate_memory orelse return false;
    const bind_memory = self.real_vulkan.fn_ptrs.bind_buffer_memory orelse return false;
    const map_memory = self.real_vulkan.fn_ptrs.map_memory orelse return false;
    const create_command_pool = self.real_vulkan.fn_ptrs.create_command_pool orelse return false;
    const allocate_command_buffers = self.real_vulkan.fn_ptrs.allocate_command_buffers orelse return false;

    var buffer_info = abi.BufferCreateInfo{
        .size = size,
        .usage = abi.BUFFER_USAGE_TRANSFER_DST_BIT,
    };
    var buffer: abi.Buffer = 0;
    var result = create_buffer(device, &buffer_info, null, &buffer);
    if (result != abi.SUCCESS or buffer == 0) return false;
    self.pixel_probe.staging_buffer = buffer;

    var requirements: abi.MemoryRequirements = .{};
    get_requirements(device, buffer, &requirements);
    if (requirements.size == 0) return false;
    var memory_type_index: ?u32 = null;
    var mapped_coherent = false;
    const memory_type_count = @min(self.real_vulkan.physical_device_memory.memory_type_count, @as(u32, abi.MAX_MEMORY_TYPES));
    for (0..@as(usize, @intCast(memory_type_count))) |index| {
        const bit = @as(u32, 1) << @as(u5, @intCast(index));
        if ((requirements.memory_type_bits & bit) == 0) continue;
        const flags = self.real_vulkan.physical_device_memory.memory_types[index].property_flags;
        if ((flags & abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT) == 0) continue;
        if ((flags & abi.MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0) {
            memory_type_index = @intCast(index);
            mapped_coherent = true;
            break;
        }
        if (memory_type_index == null) memory_type_index = @intCast(index);
    }
    const selected_memory_type = memory_type_index orelse return false;
    var allocate_info = abi.MemoryAllocateInfo{
        .allocation_size = @max(requirements.size, size),
        .memory_type_index = selected_memory_type,
    };
    var memory: abi.DeviceMemory = 0;
    result = allocate_memory(device, &allocate_info, null, &memory);
    if (result != abi.SUCCESS or memory == 0) return false;
    self.pixel_probe.staging_memory = memory;
    result = bind_memory(device, buffer, memory, 0);
    if (result != abi.SUCCESS) return false;
    var mapped: ?*anyopaque = null;
    // Map the whole allocation so WHOLE_SIZE invalidation never reaches
    // outside the mapped range when the driver's requirements add padding.
    result = map_memory(device, memory, 0, abi.WHOLE_SIZE, 0, &mapped);
    if (result != abi.SUCCESS or mapped == null) return false;
    self.pixel_probe.mapped = mapped;
    self.pixel_probe.mapped_coherent = mapped_coherent;
    self.pixel_probe.staging_size = size;

    var pool_info = abi.CommandPoolCreateInfo{
        .flags = abi.COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queue_family_index = queue_family,
    };
    var command_pool: abi.CommandPool = 0;
    result = create_command_pool(device, &pool_info, null, &command_pool);
    if (result != abi.SUCCESS or command_pool == 0) return false;
    self.pixel_probe.command_pool = command_pool;
    self.pixel_probe.command_pool_family = queue_family;
    var allocate_info_commands = abi.CommandBufferAllocateInfo{
        .command_pool = command_pool,
        .level = abi.COMMAND_BUFFER_LEVEL_PRIMARY,
        .command_buffer_count = 1,
    };
    var commands = [_]abi.CommandBuffer{null};
    result = allocate_command_buffers(device, &allocate_info_commands, &commands);
    if (result != abi.SUCCESS or commands[0] == null) return false;
    self.pixel_probe.command_buffer = commands[0];
    complete = true;
    return true;
}

pub fn notePresentationProgress(self: anytype, now_ns: u64) void {
    if (self.frame_hud_last_sample_ns == 0 or
        (now_ns >= self.frame_hud_last_sample_ns and
            now_ns - self.frame_hud_last_sample_ns >= 250_000_000))
    {
        self.frame_hud_fps_milli = self.transport_cost.accepted_present_recent.activeFpsMilli(self.transport_cost.last_accepted_present_ns, now_ns);
        self.frame_hud_last_sample_ns = now_ns;
    }
    const callback = HostFrameCounterResolver.resolve() orelse {
        if (!self.frame_hud_bridge_reported) {
            self.frame_hud_bridge_reported = true;
            machoCapturePrint("macho-processor: FRAME HUD BRIDGE: callback=unavailable accepted_presents={d}; native overlay cannot receive its numeric rate until the bridge symbol resolves\n", .{self.vulkan_real_presents});
        }
        return;
    };
    if (!self.frame_hud_bridge_reported) {
        self.frame_hud_bridge_reported = true;
        self.frame_hud_callback_resolved = true;
        machoCapturePrint("macho-processor: FRAME HUD BRIDGE: callback=resolved source=successful_native_presents accepted_presents={d} fps_milli={d}; the overlay reports accepted Vulkan WSI cadence, not Xbox simulation FPS\n", .{ self.vulkan_real_presents, self.frame_hud_fps_milli });
    }
    self.frame_hud_callback_resolved = true;
    callback(self.vulkan_real_presents, self.frame_hud_fps_milli);
}

pub fn configureFrameCapture(self: anytype) void {
    if (self.pixel_probe.capture_configured) return;
    self.pixel_probe.capture_configured = true;
    if (std.c.getenv("ROSETTE_VULKAN_CAPTURE")) |raw| {
        self.pixel_probe.capture_enabled = !std.mem.eql(u8, std.mem.span(raw), "0");
    }
    if (std.c.getenv("ROSETTE_VULKAN_COCOA_PREVIEW")) |raw| {
        self.pixel_probe.preview_enabled = std.mem.eql(u8, std.mem.span(raw), "1");
    }
    if (std.c.getenv("ROSETTE_VULKAN_DIAGNOSTIC_EXPOSURE")) |raw| {
        self.pixel_probe.exposure_enabled = !std.mem.eql(u8, std.mem.span(raw), "0");
    }
    if (std.c.getenv("ROSETTE_VULKAN_PREVIEW_INTERVAL_MS")) |raw| {
        const milliseconds = std.fmt.parseInt(u64, std.mem.span(raw), 10) catch 250;
        self.pixel_probe.preview_interval_ns = @as(u64, @min(milliseconds, 60_000)) * 1_000_000;
    }
}

pub fn captureReadback(self: anytype, capture: PendingReadbackCapture, picture_frame: u64) void {
    const sample = capture.sample;
    const stats = sample.stats;
    const probe = &self.pixel_probe;
    probe.capture_last_frame = sample.frame;
    probe.capture_last_stats = stats;
    var flags = probe.capture_policy.flags(sample.frame, capture.write_kind == .content, picture_frame, capture.preview);
    if (!probe.capture_enabled) flags &= ~frame_capture.save_png;
    if (flags == 0) return;
    flags |= frame_capture.picture_numbering;
    if (probe.exposure_enabled) flags |= frame_capture.diagnostic_exposure;
    const callback = HostFrameCaptureResolver.resolve() orelse {
        probe.capture_missing +|= 1;
        if (probe.capture_missing == 1) machoCapturePrint(
            "macho-processor: FRAME CAPTURE: native Cocoa callback missing; readback statistics remain available but no PNG/preview was delivered\n",
            .{},
        );
        return;
    };
    const packet = frame_capture.Frame{
        .pixels = capture.bytes.ptr,
        .length = capture.bytes.len,
        .frame = sample.frame,
        .swapchain = sample.swapchain,
        .image = sample.image,
        .hash = stats.hash,
        .width = sample.width,
        .height = sample.height,
        .format = sample.format,
        .flags = flags,
        .visible_pixels = stats.visible_pixels,
        .bright_pixels = stats.bright_pixels,
        .transparent_pixels = stats.transparent_pixels,
        .rgb_sum = stats.rgb_sum,
        .rgb_different_pixels = stats.rgb_different_pixels,
        .min_rgb = stats.min_rgb,
        .max_rgb = stats.max_rgb,
        .content_frame = picture_frame,
    };
    const capture_started = transport_timing.nowNs();
    const result = callback(&packet);
    self.transport_cost.finish(.cpu_capture, capture_started);
    probe.capture_calls +|= 1;
    if (result & frame_capture.result_saved != 0) probe.capture_saved +|= 1;
    if (result & frame_capture.result_previewed != 0) probe.capture_previewed +|= 1;
    if (result & frame_capture.result_failed != 0) probe.capture_failures +|= 1;
}

pub fn probeGuestSwapchainImage(
    self: anytype,
    synthetic_swapchain: u64,
    real_swapchain: abi.SwapchainKHR,
    image_index: u32,
    frame: u64,
    write_kind: WriteKind,
    force_content_probe: bool,
    present_queue: abi.Queue,
    present_waits: []const abi.Semaphore,
    waits_consumed: *bool,
    capture: *?PendingReadbackCapture,
    capture_bytes: *u64,
) void {
    self.configureFrameCapture();
    const probe_now = transport_timing.nowNs();
    const preview_due = self.pixel_probe.preview_enabled and transport_timing.previewDue(self.pixel_probe.last_preview_probe_ns, probe_now, self.pixel_probe.preview_interval_ns);
    // Readback discovery cannot depend on an already-open picture epoch.
    // Keep four initial proofs, eight first-content retries, then a host
    // time cadence: 1 Hz for fills, 4 Hz for content (not every 60 clears).
    const first_picture_probes = write_kind == .content and self.picture_sequence.frames != 0 and self.picture_sequence.frames < 8;
    const probe_interval_ns: u64 = if (write_kind == .content) 250_000_000 else 1_000_000_000;
    const campaign_probe = write_kind == .content and campaignDiagnosticFrame(frame);
    const discovery = frame <= PIXEL_PROBE_INITIAL_SAMPLES or force_content_probe or first_picture_probes or preview_due or campaign_probe;
    // The steady cadence exists to feed the capture files and the preview
    // window. With neither enabled it bought nothing and cost 9.5% of the
    // run: on 2026-09-20 2,526 readbacks took 114.5 s, because each one
    // ends in `vkQueueWaitIdle` and every guest thread shares the host
    // thread that waits. Discovery - the first samples, the pre-detail
    // content retries and the first picture frames, all bounded - still
    // runs, so the picture epoch opens and the validity chain still has
    // its evidence.
    if (!discovery and !self.pixel_probe.capture_enabled and !self.pixel_probe.preview_enabled) return;
    if (!self.pixel_probe.probe_schedule.choose(real_swapchain, probe_now, probe_interval_ns, discovery)) return;
    self.pixel_probe.last_preview_probe_ns = probe_now;
    defer self.transport_cost.finish(.readback_inclusive, probe_now);
    self.pixel_probe.attempts +|= 1;
    if (force_content_probe and write_kind == .content) self.pixel_probe.content_probe_attempts +|= 1;
    self.pixel_probe.frame = frame;
    self.pixel_probe.last_swapchain = real_swapchain;

    var width: u32 = 0;
    var height: u32 = 0;
    var format: u32 = abi.FORMAT_UNDEFINED;
    var usage: u32 = 0;
    for (self.present_chain.swapchains[0..self.present_chain.swapchain_count]) |record| {
        if (record.handle != real_swapchain) continue;
        width = record.width;
        height = record.height;
        format = record.format;
        usage = record.image_usage;
        break;
    }
    if ((usage & abi.IMAGE_USAGE_TRANSFER_SRC_BIT) == 0) {
        self.notePixelProbeResult(real_swapchain, .unavailable, 0, frame, 0, 0, write_kind);
        return;
    }
    const bytes_per_pixel = pixelProbeBytesPerPixel(format) orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FORMAT_NOT_SUPPORTED, "unsupported swapchain format", 0, write_kind);
        return;
    };
    if (width == 0 or height == 0 or width > PIXEL_PROBE_MAX_BYTES / bytes_per_pixel / @as(u64, height)) {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_OUT_OF_HOST_MEMORY, "bounded readback size rejected", 0, write_kind);
        return;
    }
    const size = @as(u64, width) * @as(u64, height) * bytes_per_pixel;
    const swapchain_record = self.real_vulkan.swapchainRecord(synthetic_swapchain) orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_INITIALIZATION_FAILED, "swapchain image record missing", 0, write_kind);
        return;
    };
    if (image_index >= swapchain_record.image_count) {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_INITIALIZATION_FAILED, "acquired image index outside mapped record", 0, write_kind);
        return;
    }
    const synthetic_image = swapchain_record.image_handles[@as(usize, @intCast(image_index))];
    const image = self.real_vulkan.realImage(synthetic_image) orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_INITIALIZATION_FAILED, "acquired image has no native mapping", synthetic_image, write_kind);
        return;
    };
    // The image has been released to its present queue. Reading on the
    // first graphics queue can violate exclusive queue-family ownership.
    // Use the actual present queue and a pool created for that family.
    var queue_family: u32 = abi.QUEUE_FAMILY_IGNORED;
    for (&self.real_vulkan.queue_map, 0..) |*entry, index| {
        const mapping = HandleMap.snapshot(entry) orelse continue;
        if (mapping.real == @intFromPtr(present_queue)) {
            queue_family = self.real_vulkan.queue_family_indices[index];
            break;
        }
    }
    if (queue_family == abi.QUEUE_FAMILY_IGNORED and present_queue == self.real_vulkan.graphics_queue)
        queue_family = self.real_vulkan.graphics_queue_family_index;
    if (queue_family >= self.real_vulkan.queue_family_count or
        self.real_vulkan.queue_family_properties[queue_family].queue_flags &
            (abi.QUEUE_TRANSFER_BIT | abi.QUEUE_GRAPHICS_BIT | abi.QUEUE_COMPUTE_BIT) == 0)
    {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "present queue transfer family unknown or unsupported", synthetic_image, write_kind);
        return;
    }
    if (!self.ensurePixelProbeResources(size, queue_family)) {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "staging resources unavailable", synthetic_image, write_kind);
        return;
    }
    const command_buffer = self.pixel_probe.command_buffer orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "probe command buffer unavailable", synthetic_image, write_kind);
        return;
    };
    const queue = present_queue;
    const reset = self.real_vulkan.fn_ptrs.reset_command_buffer orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "command buffer reset unavailable", synthetic_image, write_kind);
        return;
    };
    var result = reset(command_buffer, 0);
    if (result != abi.SUCCESS) {
        self.pixelProbeFailure(real_swapchain, frame, result, "command buffer reset failed", synthetic_image, write_kind);
        return;
    }
    const begin = self.real_vulkan.fn_ptrs.begin_command_buffer orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "command buffer begin unavailable", synthetic_image, write_kind);
        return;
    };
    const end = self.real_vulkan.fn_ptrs.end_command_buffer orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "command buffer end unavailable", synthetic_image, write_kind);
        return;
    };
    const barrier_fn = self.real_vulkan.fn_ptrs.cmd_pipeline_barrier orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "pipeline barrier unavailable", synthetic_image, write_kind);
        return;
    };
    const copy_fn = self.real_vulkan.fn_ptrs.cmd_copy_image_to_buffer orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "image readback command unavailable", synthetic_image, write_kind);
        return;
    };
    const submit_fn = self.real_vulkan.fn_ptrs.queue_submit orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "probe queue submit unavailable", synthetic_image, write_kind);
        return;
    };
    const wait_idle = self.real_vulkan.fn_ptrs.queue_wait_idle orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "probe queue completion unavailable", synthetic_image, write_kind);
        return;
    };
    var begin_info = abi.CommandBufferBeginInfo{ .flags = abi.COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    result = begin(command_buffer, &begin_info);
    if (result != abi.SUCCESS) {
        self.pixelProbeFailure(real_swapchain, frame, result, "command buffer begin failed", synthetic_image, write_kind);
        return;
    }
    var to_transfer = [_]abi.ImageMemoryBarrier{.{
        .src_access_mask = abi.ACCESS_MEMORY_READ_BIT | abi.ACCESS_MEMORY_WRITE_BIT,
        .dst_access_mask = abi.ACCESS_TRANSFER_READ_BIT,
        .old_layout = abi.IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .new_layout = abi.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .image = image,
    }};
    barrier_fn(
        command_buffer,
        abi.PIPELINE_STAGE_ALL_COMMANDS_BIT,
        abi.PIPELINE_STAGE_TRANSFER_BIT,
        0,
        0,
        null,
        0,
        null,
        1,
        &to_transfer,
    );
    var region = [_]abi.BufferImageCopy{.{
        .image_subresource = .{ .aspect_mask = abi.IMAGE_ASPECT_COLOR_BIT, .layer_count = 1 },
        .image_extent = .{ .width = width, .height = height, .depth = 1 },
    }};
    copy_fn(command_buffer, image, abi.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, self.pixel_probe.staging_buffer, 1, &region);
    var to_host = [_]abi.BufferMemoryBarrier{.{
        .src_access_mask = abi.ACCESS_TRANSFER_WRITE_BIT,
        .dst_access_mask = abi.ACCESS_HOST_READ_BIT,
        .buffer = self.pixel_probe.staging_buffer,
        .size = abi.WHOLE_SIZE,
    }};
    barrier_fn(command_buffer, abi.PIPELINE_STAGE_TRANSFER_BIT, abi.PIPELINE_STAGE_HOST_BIT, 0, 0, null, 1, &to_host, 0, null);
    var to_present = [_]abi.ImageMemoryBarrier{.{
        .src_access_mask = abi.ACCESS_TRANSFER_READ_BIT,
        .dst_access_mask = 0,
        .old_layout = abi.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .new_layout = abi.IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .image = image,
    }};
    barrier_fn(
        command_buffer,
        abi.PIPELINE_STAGE_TRANSFER_BIT,
        abi.PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        0,
        0,
        null,
        0,
        null,
        1,
        &to_present,
    );
    result = end(command_buffer);
    if (result != abi.SUCCESS) {
        self.pixelProbeFailure(real_swapchain, frame, result, "command buffer end failed", synthetic_image, write_kind);
        return;
    }
    var command_buffers = [_]abi.CommandBuffer{command_buffer};
    // Wait on the guest's render-finished semaphores HERE, including when
    // their producer is another queue. Binary waits have exactly one
    // consumer: successful submission hands that responsibility from WSI
    // to the readback, whose host-observed completion then precedes WSI.
    // No device-wide idle (which could wait on unrelated future work).
    var wait_stages: [16]u32 = @splat(abi.PIPELINE_STAGE_ALL_COMMANDS_BIT);
    const waits = if (waits_consumed.*) present_waits[0..0] else present_waits;
    var submits = [_]abi.SubmitInfo{.{
        .wait_semaphore_count = @intCast(waits.len),
        .wait_semaphores = if (waits.len == 0) null else waits.ptr,
        .wait_dst_stage_mask = if (waits.len == 0) null else &wait_stages,
        .command_buffer_count = 1,
        .command_buffers = &command_buffers,
    }};
    result = submit_fn(queue, 1, &submits, 0);
    if (result != abi.SUCCESS) {
        self.pixelProbeFailure(real_swapchain, frame, result, "readback submit failed", synthetic_image, write_kind);
        return;
    }
    if (waits.len != 0) {
        waits_consumed.* = true;
        self.pixel_probe.readback_wait_handoffs +|= 1;
    }
    result = wait_idle(queue);
    if (result != abi.SUCCESS) {
        self.pixel_probe.readback_completion_failed = true;
        self.pixelProbeFailure(real_swapchain, frame, result, "readback completion failed", synthetic_image, write_kind);
        return;
    }
    if (!self.pixel_probe.mapped_coherent) {
        const invalidate = self.real_vulkan.fn_ptrs.invalidate_mapped_memory_ranges orelse {
            self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FEATURE_NOT_PRESENT, "noncoherent readback invalidation unavailable", synthetic_image, write_kind);
            return;
        };
        {
            var ranges = [_]abi.MappedMemoryRange{.{
                .memory = self.pixel_probe.staging_memory,
                // WHOLE_SIZE satisfies nonCoherentAtomSize alignment even
                // when width*height*4 isn't an atom multiple.
                .size = abi.WHOLE_SIZE,
            }};
            result = invalidate(self.real_vulkan.device.?, 1, &ranges);
            if (result != abi.SUCCESS) {
                self.pixelProbeFailure(real_swapchain, frame, result, "mapped readback invalidation failed", synthetic_image, write_kind);
                return;
            }
        }
    }
    const mapped = self.pixel_probe.mapped orelse {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_INITIALIZATION_FAILED, "mapped readback pointer missing", synthetic_image, write_kind);
        return;
    };
    const bytes: []const u8 = @as([*]const u8, @ptrCast(mapped))[0..@as(usize, @intCast(size))];
    const stats = frame_capture.analyze(bytes, width, height, format) catch {
        self.pixelProbeFailure(real_swapchain, frame, abi.ERROR_FORMAT_NOT_SUPPORTED, "readback analysis refused malformed frame", synthetic_image, write_kind);
        return;
    };
    self.pixel_probe.last_stats = stats;
    self.pixel_probe.last_stats_frame = frame;
    self.pixel_probe.last_stats_format = format;
    // Retain legacy readback-stat observations even when PNG/preview
    // delivery is disabled. Delivery counters remain separate evidence.
    self.pixel_probe.capture_last_frame = frame;
    self.pixel_probe.capture_last_stats = stats;
    const sample = ReadbackSample{ .frame = frame, .swapchain = real_swapchain, .image = synthetic_image, .width = width, .height = height, .format = format, .stats = stats };
    self.pixel_probe.last_sample = sample;
    const hash = stats.hash;
    const uniform_value = stats.first_pixel;
    var previous_hash: u64 = 0;
    var previous_frame: u64 = 0;
    for (self.present_chain.swapchains[0..self.present_chain.swapchain_count]) |record| {
        if (record.handle == real_swapchain) {
            previous_hash = record.pixel_hash;
            previous_frame = record.pixel_probe_frame;
            break;
        }
    }
    const evidence: rosette_gpu.PresentPixelEvidence = if (!stats.any_nonzero)
        .solid_clear
    else if (stats.uniform or stats.rgb_different_pixels == 0)
        .uniform_colour
    else if (previous_frame != 0 and previous_hash != hash)
        .changing
    else
        .nonzero_static;
    self.notePixelProbeResult(real_swapchain, evidence, hash, frame, uniform_value, synthetic_image, write_kind);
    self.pixel_probe.successes +|= 1;
    // WSI may reject this request, and the brightness ladder reuses the
    // staging area. Copy only a requested capture, with one 64 MiB budget
    // across the batch, and deliver it AFTER accepted native completion.
    const candidate_picture = if (write_kind == .content and (self.picture_sequence.frames != 0 or stats.hasRgbDetail())) self.picture_sequence.frames +| 1 else 0;
    const opening_preview = self.pixel_probe.preview_enabled and self.picture_sequence.frames == 0 and write_kind == .content and stats.hasRgbDetail();
    if (preview_due or opening_preview or (self.pixel_probe.capture_enabled and self.pixel_probe.capture_policy.wantsCapture(frame, write_kind == .content, candidate_picture, false))) {
        const owned = if (size <= frame_capture.max_bytes -| capture_bytes.*) std.heap.page_allocator.dupe(u8, bytes) catch null else null;
        if (owned) |copy| {
            capture.* = .{ .sample = sample, .bytes = copy, .write_kind = write_kind, .preview = preview_due or opening_preview };
            capture_bytes.* += size;
        } else {
            self.pixel_probe.capture_failures +|= 1;
            if (self.pixel_probe.capture_failures == 1) machoCapturePrint("macho-processor: FRAME CAPTURE: deferred copy unavailable or batch exceeds 64 MiB; pixel evidence retained, no unsafe staging pointer delivered\n", .{});
        }
    }
    if (self.pixel_probe.successes <= 4 or force_content_probe or campaign_probe or self.graphics_report_verbose) {
        machoCapturePrint(
            "macho-processor: PIXEL PROBE: frame={d} swapchain=0x{x} image_index={d} image=0x{x} write_kind={s} forced_content={} bytes={d} evidence={s} hash=0x{x} uniform_value=0x{x} shows_detail={}\n",
            .{ frame, real_swapchain, image_index, synthetic_image, write_kind.label(), force_content_probe, size, evidence.label(), hash, uniform_value, evidence.showsDetail() },
        );
        machoCapturePrint(
            "macho-processor: PIXEL CONTENT: frame={d} pixels={d} visible_rgb_gt16={d} bright_rgb_gt64={d} alpha_lt255={d} rgb_different={d} mean_rgb={d}/{d}/{d} min_rgb={d}/{d}/{d} max_rgb={d}/{d}/{d}; varying bytes alone do not prove a visible picture\n",
            .{ frame, stats.pixel_count, stats.visible_pixels, stats.bright_pixels, stats.transparent_pixels, stats.rgb_different_pixels, stats.mean(0), stats.mean(1), stats.mean(2), stats.min_rgb[0], stats.min_rgb[1], stats.min_rgb[2], stats.max_rgb[0], stats.max_rgb[1], stats.max_rgb[2] },
        );
        if (write_kind == .content and stats.visible_pixels == 0) machoCapturePrint(
            "macho-processor: FRAME CAPTURE FINDING: acquired-image RGB is entirely near-black (all channels <=16); transport and varying bytes do not establish a visible title image. Inspect saved RGB pixels and the shader/texture/source plane before blaming WSI\n",
            .{},
        );
    }
}

pub fn presentQueueFamily(self: anytype, present_queue: abi.Queue) ?u32 {
    var queue_family: u32 = abi.QUEUE_FAMILY_IGNORED;
    for (&self.real_vulkan.queue_map, 0..) |*entry, index| {
        const mapping = HandleMap.snapshot(entry) orelse continue;
        if (mapping.real == @intFromPtr(present_queue)) {
            queue_family = self.real_vulkan.queue_family_indices[index];
            break;
        }
    }
    if (queue_family == abi.QUEUE_FAMILY_IGNORED and present_queue == self.real_vulkan.graphics_queue)
        queue_family = self.real_vulkan.graphics_queue_family_index;
    if (queue_family >= self.real_vulkan.queue_family_count or
        self.real_vulkan.queue_family_properties[queue_family].queue_flags &
            (abi.QUEUE_TRANSFER_BIT | abi.QUEUE_GRAPHICS_BIT | abi.QUEUE_COMPUTE_BIT) == 0)
    {
        return null;
    }
    return queue_family;
}

pub fn syntheticImageForReal(self: anytype, real: u64) ?u64 {
    if (real == 0) return null;
    return HandleMap.findSynthetic(&self.real_vulkan.image_map, real);
}

pub fn readbackImageBytes(
    self: anytype,
    image: abi.Image,
    width: u32,
    height: u32,
    format: u32,
    layout: u32,
    queue: abi.Queue,
    queue_family: u32,
) ?[]const u8 {
    const bytes_per_pixel = pixelProbeBytesPerPixel(format) orelse return null;
    if (width == 0 or height == 0 or width > PIXEL_PROBE_MAX_BYTES / bytes_per_pixel / @as(u64, height)) return null;
    const size = @as(u64, width) * @as(u64, height) * bytes_per_pixel;
    if (!self.ensurePixelProbeResources(size, queue_family)) return null;
    const command_buffer = self.pixel_probe.command_buffer orelse return null;
    const fns = &self.real_vulkan.fn_ptrs;
    const reset = fns.reset_command_buffer orelse return null;
    const begin = fns.begin_command_buffer orelse return null;
    const end = fns.end_command_buffer orelse return null;
    const barrier_fn = fns.cmd_pipeline_barrier orelse return null;
    const copy_fn = fns.cmd_copy_image_to_buffer orelse return null;
    const submit_fn = fns.queue_submit orelse return null;
    const wait_idle = fns.queue_wait_idle orelse return null;
    if (reset(command_buffer, 0) != abi.SUCCESS) return null;
    var begin_info = abi.CommandBufferBeginInfo{ .flags = abi.COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    if (begin(command_buffer, &begin_info) != abi.SUCCESS) return null;
    var to_transfer = [_]abi.ImageMemoryBarrier{.{
        .src_access_mask = abi.ACCESS_MEMORY_READ_BIT | abi.ACCESS_MEMORY_WRITE_BIT,
        .dst_access_mask = abi.ACCESS_TRANSFER_READ_BIT,
        .old_layout = layout,
        .new_layout = abi.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .image = image,
    }};
    barrier_fn(command_buffer, abi.PIPELINE_STAGE_ALL_COMMANDS_BIT, abi.PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &to_transfer);
    var region = [_]abi.BufferImageCopy{.{
        .image_subresource = .{ .aspect_mask = abi.IMAGE_ASPECT_COLOR_BIT, .layer_count = 1 },
        .image_extent = .{ .width = width, .height = height, .depth = 1 },
    }};
    copy_fn(command_buffer, image, abi.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, self.pixel_probe.staging_buffer, 1, &region);
    var to_host = [_]abi.BufferMemoryBarrier{.{
        .src_access_mask = abi.ACCESS_TRANSFER_WRITE_BIT,
        .dst_access_mask = abi.ACCESS_HOST_READ_BIT,
        .buffer = self.pixel_probe.staging_buffer,
        .size = abi.WHOLE_SIZE,
    }};
    barrier_fn(command_buffer, abi.PIPELINE_STAGE_TRANSFER_BIT, abi.PIPELINE_STAGE_HOST_BIT, 0, 0, null, 1, &to_host, 0, null);
    var to_rest = [_]abi.ImageMemoryBarrier{.{
        .src_access_mask = abi.ACCESS_TRANSFER_READ_BIT,
        .dst_access_mask = abi.ACCESS_SHADER_READ_BIT | abi.ACCESS_MEMORY_READ_BIT,
        .old_layout = abi.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .new_layout = layout,
        .image = image,
    }};
    barrier_fn(command_buffer, abi.PIPELINE_STAGE_TRANSFER_BIT, abi.PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, null, 0, null, 1, &to_rest);
    if (end(command_buffer) != abi.SUCCESS) return null;
    var command_buffers = [_]abi.CommandBuffer{command_buffer};
    var submits = [_]abi.SubmitInfo{.{
        .command_buffer_count = 1,
        .command_buffers = &command_buffers,
    }};
    if (submit_fn(queue, 1, &submits, 0) != abi.SUCCESS) return null;
    if (wait_idle(queue) != abi.SUCCESS) return null;
    if (!self.pixel_probe.mapped_coherent) {
        const invalidate = fns.invalidate_mapped_memory_ranges orelse return null;
        var ranges = [_]abi.MappedMemoryRange{.{ .memory = self.pixel_probe.staging_memory, .size = abi.WHOLE_SIZE }};
        if (invalidate(self.real_vulkan.device.?, 1, &ranges) != abi.SUCCESS) return null;
    }
    const mapped = self.pixel_probe.mapped orelse return null;
    return @as([*]const u8, @ptrCast(mapped))[0..@as(usize, @intCast(size))];
}

pub fn readLadderStage(
    self: anytype,
    stage: *LadderStage,
    real_image: u64,
    queue: abi.Queue,
    queue_family: u32,
    decode_as_xenos_7e3: bool,
) void {
    stage.real_image = real_image;
    if (real_image == 0) {
        stage.status = "no_source_edge";
        return;
    }
    const synthetic = self.syntheticImageForReal(real_image) orelse {
        stage.status = "image_not_mapped";
        return;
    };
    stage.synthetic_image = synthetic;
    const resource = self.findResource(synthetic) orelse {
        stage.status = "no_resource_record";
        return;
    };
    stage.format = resource.format;
    stage.width = resource.width;
    stage.height = resource.height;
    if (frame_capture.layoutFor(resource.format) == null) {
        stage.status = "format_not_decodable";
        return;
    }
    if ((resource.usage & abi.IMAGE_USAGE_TRANSFER_SRC_BIT) == 0 and
        !imageReadbackAugmentable(resource.usage, resource.format, abi.IMAGE_TYPE_2D, abi.SAMPLE_COUNT_1_BIT))
    {
        stage.status = "no_transfer_src";
        return;
    }
    self.brightness_ladder.readbacks +|= 1;
    const bytes = self.readbackImageBytes(
        @intCast(real_image),
        resource.width,
        resource.height,
        resource.format,
        abi.IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        queue,
        queue_family,
    ) orelse {
        self.brightness_ladder.readback_failures +|= 1;
        stage.status = "readback_failed";
        return;
    };
    stage.stats = frame_capture.analyze(bytes, resource.width, resource.height, resource.format) catch {
        self.brightness_ladder.readback_failures +|= 1;
        stage.status = "analysis_refused";
        return;
    };
    if (decode_as_xenos_7e3) {
        stage.seven_e3 = frame_capture.analyzeSevenE3(bytes, resource.width, resource.height, resource.format);
    }
    stage.status = "read";
}

pub fn printFsiImageTransitionCandidates(self: anytype, frame: u64) void {
    const available = self.vulkan_fsi_tracker.recent_submission_count;
    const count = @min(available, 4);
    const first = available - count;
    machoCapturePrint(
        "macho-processor: VULKAN FSI IMAGE CANDIDATES: frame={d} recent_accepted={d} printed={d}; newest accepted submissions near the first measured white transition, not proof any candidate caused the pixels\n",
        .{ frame, available, count },
    );
    for (first..available) |index| {
        const submission = self.vulkan_fsi_tracker.recentSubmission(index) orelse continue;
        const draw = submission.draw;
        machoCapturePrint(
            "macho-processor: VULKAN FSI IMAGE CANDIDATE: frame={d} submit={d} batch={d} command_buffer=0x{x} command_draw={d} global_draw={d} kind={s} target=0x{x} target_source={s} pipeline=0x{x} module_id={d} shader_hash=0x{x} pipeline_hash=0x{x} draws_in_command_buffer={d} args_valid={} elements={d} instances={d} first_element={d} vertex_offset={d} first_instance={d}\n",
            .{
                frame,
                submission.queue_submit_ordinal,
                submission.batch_index,
                draw.command_buffer,
                draw.command_buffer_draw_ordinal,
                draw.draw_ordinal,
                @tagName(draw.kind),
                draw.target_image,
                @tagName(draw.target_source),
                draw.pipeline_real,
                draw.module_id,
                draw.shader_hash,
                draw.pipeline_hash,
                submission.fsi_draws_in_command_buffer,
                draw.parameters.valid,
                draw.parameters.element_count,
                draw.parameters.instance_count,
                draw.parameters.first_element,
                draw.parameters.vertex_offset,
                draw.parameters.first_instance,
            },
        );
    }
}

pub fn probeBrightnessLadder(self: anytype, real_swapchain: abi.SwapchainKHR, frame: u64, queue: abi.Queue, swapchain_stats: frame_capture.Stats, format: u32) void {
    const ladder = &self.brightness_ladder;
    const started = transport_timing.nowNs();
    // A raw modulo-60 rule could alias with timed readback forever and
    // stop observing gamma/source changes. Keep the first eight proofs,
    // then one ladder per host second per swapchain, independently of
    // raw presentation rate and batch order.
    const campaign_probe = campaignDiagnosticFrame(frame);
    if (!ladder.probe_schedule.choose(real_swapchain, started, 1_000_000_000, ladder.samples < 8 or campaign_probe)) return;
    const pending = self.present_chain.pendingFrame(real_swapchain) orelse return;
    if (pending.write_kind != .content) return;
    const queue_family = self.presentQueueFamily(queue) orelse return;
    defer self.transport_cost.finish(.readback_inclusive, started);
    ladder.samples +|= 1;
    ladder.last_frame = frame;

    var swapchain_stage = LadderStage{ .label = "swapchain", .format = format, .stats = swapchain_stats, .status = "read" };
    var output_stage = LadderStage{ .label = "guest_output" };
    var source_stage = LadderStage{ .label = "swap_texture" };
    self.readLadderStage(&output_stage, pending.sampled_image, queue, queue_family, false);
    const sources = self.present_chain.passSourcesOf(pending.sampled_image);
    self.readLadderStage(
        &source_stage,
        sources[0],
        queue,
        queue_family,
        self.guest_frontbuffer_format.uses7e3Color(),
    );

    const swapchain_peak: u16 = swapchain_stage.stats.?.peak();
    const output_peak: u16 = if (output_stage.stats) |stats| stats.peak() else 256;
    const source_peak: u16 = if (source_stage.stats) |stats| stats.peak() else 256;
    ladder.last_peaks = .{ source_peak, output_peak, swapchain_peak };
    const swapchain_near_white = swapchain_stats.nearWhite();
    const white_transition = swapchain_near_white and !ladder.last_swapchain_near_white;
    ladder.last_swapchain_near_white = swapchain_near_white;
    if (white_transition) {
        ladder.white_transitions +|= 1;
        machoCapturePrint(
            "macho-processor: FSI WHITE FRAME: transition={d} frame={d} swapchain_white={d}/{d} guest_output={s} white={d}/{d} swap_texture={s} white={d}/{d}; this locates the first sampled white image in the FSI/gamma/present chain, not the cause of its pixels\n",
            .{
                ladder.white_transitions,
                frame,
                swapchain_stats.white_pixels,
                swapchain_stats.pixel_count,
                if (output_stage.stats) |stats| (if (stats.nearWhite()) "near_white" else "not_near_white") else output_stage.status,
                if (output_stage.stats) |stats| stats.white_pixels else 0,
                if (output_stage.stats) |stats| stats.pixel_count else 0,
                if (source_stage.stats) |stats| (if (stats.nearWhite()) "near_white" else "not_near_white") else source_stage.status,
                if (source_stage.stats) |stats| stats.white_pixels else 0,
                if (source_stage.stats) |stats| stats.pixel_count else 0,
            },
        );
        if (source_stage.seven_e3) |seven| {
            machoCapturePrint(
                "macho-processor: FSI WHITE SOURCE ENCODING: frame={d} stage=pre_gamma_swap_texture encoding=xenos_7e3 max_milli={d}/{d}/{d} mean_milli={d}/{d}/{d} over_one_pixels={d}/{d}; this interpretation is intentionally not applied to normalized guest_output\n",
                .{ frame, seven.max_milli[0], seven.max_milli[1], seven.max_milli[2], seven.mean(0), seven.mean(1), seven.mean(2), seven.over_one_pixels, seven.pixel_count },
            );
        } else {
            machoCapturePrint(
                "macho-processor: FSI WHITE SOURCE ENCODING: frame={d} stage=pre_gamma_swap_texture encoding={s} guest_frontbuffer_format={s}({d}) host_vk_format={d} status={s}; normalized channel bytes are measured by the UNORM ladder above and are not reinterpreted as 7e3\n",
                .{ frame, self.guest_frontbuffer_format.encodingLabel(), self.guest_frontbuffer_format.label(), @intFromEnum(self.guest_frontbuffer_format), source_stage.format, source_stage.status },
            );
        }
        self.printFsiImageTransitionCandidates(frame);
    }
    // "Dark" is the swapchain probe's own threshold, 64/255, at every
    // stage. The 2026-09-17 run read a dim swap texture (peak 36) and
    // called it unknown because the first rule wanted 16.
    const verdict: BrightnessLoss = if (swapchain_peak > 64)
        .swapchain_signal_present
    else if (source_peak != 256 and source_peak <= 64)
        .before_gamma_pass
    else if (source_peak != 256 and source_peak > 64 and output_peak != 256 and output_peak <= 64)
        .gamma_pass
    else if (output_peak != 256 and output_peak > 64)
        .present_paint
    else if (output_peak != 256 and output_peak <= 64 and source_peak == 256)
        // Dark out of the gamma pass with no readable input: the loss is
        // at or before the pass, which still clears the presenter.
        .gamma_pass
    else
        .unknown;
    ladder.verdict_counts[@intFromEnum(verdict)] +|= 1;
    const changed = verdict != ladder.last_verdict;
    ladder.last_verdict = verdict;
    if (ladder.printed < 8 or changed or campaignDiagnosticFrame(frame)) {
        ladder.printed +|= 1;
        self.printLadderStage(frame, &source_stage);
        self.printLadderStage(frame, &output_stage);
        self.printLadderStage(frame, &swapchain_stage);
        self.printLadderSampling(frame, pending.sampled_image, &source_stage);
        self.printLadderSampling(frame, self.present_chain.pendingFrame(real_swapchain).?.acquired_image, &output_stage);
        machoCapturePrint("macho-processor: GAMMA CHANNEL CONTRACT: frame={d} ramp_format={d} full_table_channel_pairs_differ={?d}; latest observed ramp; zero means every R/G/B table value or PWL base/delta pair agrees, not only the reported landmarks\n", .{ frame, self.texel_custody_last_format, self.texel_custody_last_channel_pairs_differ });
        machoCapturePrint(
            "macho-processor: BRIGHTNESS LADDER: frame={d} peaks(swap_texture/guest_output/swapchain)={d}/{d}/{d} (256=unread) ramp_format={d} ramp_shape={s} ramp_out_rgb(max/7e3_one/mid)=({d},{d},{d})/({d},{d},{d})/({d},{d},{d}) verdict={s}: {s}\n",
            .{ frame, source_peak, output_peak, swapchain_peak, self.texel_custody_last_format, self.texel_custody_last_shape.label(), self.texel_custody_last_out_rgb[0][0], self.texel_custody_last_out_rgb[0][1], self.texel_custody_last_out_rgb[0][2], self.texel_custody_last_out_rgb[1][0], self.texel_custody_last_out_rgb[1][1], self.texel_custody_last_out_rgb[1][2], self.texel_custody_last_out_rgb[2][0], self.texel_custody_last_out_rgb[2][1], self.texel_custody_last_out_rgb[2][2], verdict.label(), verdict.meaning() },
        );
        if (verdict == .before_gamma_pass and self.texel_custody_last_shape == .xenia_default_linear and self.texel_custody_last_format == 81) {
            machoCapturePrint(
                "macho-processor: BRIGHTNESS LADDER: the ramp in use is Xenia's seeded linear PWL ramp, not one the title programmed. A title whose final pass renders 7e3 floating-point data and relies on DC_LUT programming to display it has not had that programming reach Xenia's command processor (MMIO DC_LUT writes are stored by GraphicsSystem::WriteRegister without updating the ramp; only PM4 type-0 writes do)\n",
                .{},
            );
        }
    }
}

pub fn printLadderSampling(self: anytype, frame: u64, target: u64, source: *const LadderStage) void {
    for (self.present_chain.passSourceViewsOf(target)) |view| {
        if (view.image == 0 or view.image != source.real_image) continue;
        machoCapturePrint("macho-processor: BRIGHTNESS SAMPLE VIEW: frame={d} stage={s} target=0x{x} image=0x{x} guest_view=0x{x} known={} view_format={d} storage_format={d} components={d}/{d}/{d}/{d} view_type={d} base_mip={d} base_layer={d}; latest descriptor source in this pass, not proof which binding the shader fetched; components 0=identity 1=zero 2=one 3=R 4=G 5=B 6=A; submission metadata, raw transfer bytes do not apply this mapping\n", .{ frame, source.label, target, view.image, view.view, view.known, view.format, source.format, view.components[0], view.components[1], view.components[2], view.components[3], view.view_type, view.base_mip, view.base_layer });
        if (!view.known or view.format != source.format or view.view_type != 1 or view.base_mip != 0 or view.base_layer != 0 or
            (view.format != 37 and view.format != 44 and view.format != 51 and view.format != 64)) return;
        const stats = source.stats orelse return;
        const permutation = frame_capture.sampledRgbPermutation(view.components) orelse return;
        machoCapturePrint("macho-processor: BRIGHTNESS SAMPLED RGB: frame={d} stage={s} mean_rgb={d}/{d}/{d} max_rgb={d}/{d}/{d}; RGB permutation of the raw readback for this submitted view, without another GPU readback; constants, alpha, replication, sRGB conversion, differing formats and subresources are not inferred\n", .{ frame, source.label, stats.mean(permutation[0]), stats.mean(permutation[1]), stats.mean(permutation[2]), stats.max_rgb[permutation[0]], stats.max_rgb[permutation[1]], stats.max_rgb[permutation[2]] });
        return;
    }
}

pub fn printLadderStage(self: anytype, frame: u64, stage: *const LadderStage) void {
    _ = self;
    if (stage.stats) |stats| {
        machoCapturePrint(
            "macho-processor: BRIGHTNESS LADDER:   stage={s} image=0x{x} guest=0x{x} format={d} extent={d}x{d} channels=raw_storage mean_rgb={d}/{d}/{d} max_rgb={d}/{d}/{d} visible_gt16={d} bright_gt64={d} white_rgb_ge240={d}/{d} rgb_different={d} frame={d}\n",
            .{ stage.label, stage.real_image, stage.synthetic_image, stage.format, stage.width, stage.height, stats.mean(0), stats.mean(1), stats.mean(2), stats.max_rgb[0], stats.max_rgb[1], stats.max_rgb[2], stats.visible_pixels, stats.bright_pixels, stats.white_pixels, stats.pixel_count, stats.rgb_different_pixels, frame },
        );
        if (stage.seven_e3) |seven| {
            machoCapturePrint(
                "macho-processor: BRIGHTNESS LADDER:   stage={s} encoding=xenos_7e3_pre_gamma(max_milli/mean_milli)={d}/{d}/{d} / {d}/{d}/{d} over_one_pixels={d}; 1000 is 1.0; this is the pre-gamma Xenos front-buffer interpretation, not a second interpretation of normalized guest_output\n",
                .{ stage.label, seven.max_milli[0], seven.max_milli[1], seven.max_milli[2], seven.mean(0), seven.mean(1), seven.mean(2), seven.over_one_pixels },
            );
        }
    } else {
        machoCapturePrint(
            "macho-processor: BRIGHTNESS LADDER:   stage={s} image=0x{x} guest=0x{x} format={d} extent={d}x{d} status={s} frame={d}\n",
            .{ stage.label, stage.real_image, stage.synthetic_image, stage.format, stage.width, stage.height, stage.status, frame },
        );
    }
}

pub fn pacePresent(self: anytype, state: anytype) bool {
    const now = transport_timing.nowNs();
    const deadline = self.present_ceiling.deadline(now) orelse {
        self.present_ceiling.refused +|= 1;
        return false;
    };
    if (deadline == now) return true;
    var wait: present_pacing.Wait = .{ .deadline_ns = deadline };
    if (comptime @hasDecl(@TypeOf(state.*), "tryWithWindowsRuntimeLockReleasedForVulkanQueueWait")) {
        if (!state.tryWithWindowsRuntimeLockReleasedForVulkanQueueWait(&wait, present_pacing.Wait.run)) {
            self.present_ceiling.refused +|= 1;
            return false;
        }
    } else {
        present_pacing.Wait.run(&wait);
    }
    self.present_ceiling.waits +|= 1;
    self.present_ceiling.waited_ns +|= wait.elapsed_ns;
    if (!wait.succeeded) self.present_ceiling.refused +|= 1;
    return wait.succeeded;
}

pub fn queuePresent(self: anytype, state: anytype) u64 {
    const ingress_ns = transport_timing.nowNs();
    self.transport_cost.ingress(ingress_ns);
    self.vulkan_presents +|= 1;
    self.frame_provenance.noteGuestVulkanCall();
    if (self.realDeviceLostResult()) |result| return result;
    const present_info = guest_context.registers(state).rsi;
    if (self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.queue_present != null and present_info != 0 and state.guestMemoryConst(present_info, @sizeOf(abi.PresentInfoKHR)) != null) {
        const real_queue = self.real_vulkan.realQueue(guest_context.registers(state).rdi) orelse return vkErrorInitializationFailed();
        var queue_lease = self.lockVulkanQueueApi(state) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        defer queue_lease.release();
        if (state.read64(present_info + 8) != 0) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const swapchain_count = @min(state.read32(present_info + 32), 8);
        const wait_count = @min(state.read32(present_info + 16), 16);
        const wait_address = state.read64(present_info + 24);
        const swapchain_address = state.read64(present_info + 40);
        const image_index_address = state.read64(present_info + 48);
        const result_address = state.read64(present_info + 56);
        if ((wait_count != 0 and wait_address == 0) or (swapchain_count != 0 and (swapchain_address == 0 or image_index_address == 0))) return vkErrorInitializationFailed();
        var waits: [16]abi.Semaphore = [_]abi.Semaphore{0} ** 16;
        var swapchains: [8]abi.SwapchainKHR = [_]abi.SwapchainKHR{0} ** 8;
        var synthetic_swapchains: [8]u64 = [_]u64{0} ** 8;
        var indices: [8]u32 = [_]u32{0} ** 8;
        // NOT_READY is an unwritten sentinel, not invented success. The
        // native pResults is supplied even when the guest omitted it.
        var results: [8]abi.Result = [_]abi.Result{abi.NOT_READY} ** 8;
        var captures: [8]?PendingReadbackCapture = @splat(null);
        var capture_bytes: u64 = 0;
        defer for (captures) |capture| {
            if (capture) |pending| std.heap.page_allocator.free(pending.bytes);
        };
        var samples: [8]?ReadbackSample = @splat(null);
        var acquired_images: [8]u64 = @splat(0);
        for (0..wait_count) |index| {
            const synthetic = state.read64(wait_address + @as(u64, @intCast(index)) * 8);
            waits[index] = self.real_vulkan.realSemaphore(synthetic) orelse return vkErrorInitializationFailed();
        }
        var waits_consumed = false;
        self.pixel_probe.readback_completion_failed = false;
        for (0..swapchain_count) |index| {
            const synthetic = state.read64(swapchain_address + @as(u64, @intCast(index)) * 8);
            synthetic_swapchains[index] = synthetic;
            swapchains[index] = self.real_vulkan.realSwapchain(synthetic) orelse return vkErrorInitializationFailed();
            indices[index] = state.read32(image_index_address + @as(u64, @intCast(index)) * 4);
        }
        var real_info = abi.PresentInfoKHR{
            .wait_semaphore_count = wait_count,
            .wait_semaphores = if (wait_count == 0) null else &waits,
            .swapchain_count = swapchain_count,
            .swapchains = if (swapchain_count == 0) null else &swapchains,
            .image_indices = if (swapchain_count == 0) null else &indices,
            .results = if (swapchain_count == 0) null else &results,
        };
        if (!self.pacePresent(state)) return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        // The probe is inserted after the guest's queued rendering and
        // before WSI consumes the image. Its second layout transition
        // restores PRESENT_SRC_KHR, so the guest present remains the
        // authoritative display operation. The pending ledger is read
        // before notePresent clears it; that is what lets the first
        // content-backed image bypass the sparse startup schedule.
        var content_targets: [8]bool = @splat(false);
        for (0..swapchain_count) |index| {
            const pending = self.present_chain.pendingFrame(swapchains[index]);
            if (self.real_vulkan.swapchainRecord(synthetic_swapchains[index])) |record| {
                if (indices[index] < record.image_count) acquired_images[index] = record.image_handles[indices[index]];
            }
            const real_image = self.real_vulkan.realImage(acquired_images[index]) orelse 0;
            // The command ledger uses native image IDs; the readback
            // packet uses guest IDs. Prove that the presented index is
            // precisely the acquired/written image before crediting it.
            const write_kind: WriteKind = if (pending) |frame|
                (if (frame.has_target and real_image != 0 and frame.acquired_image == real_image) frame.write_kind else .none)
            else
                .none;
            content_targets[index] = write_kind == .content;
            const force_content_probe = shouldForceContentPixelProbe(&self.pixel_probe, write_kind);
            self.probeGuestSwapchainImage(
                synthetic_swapchains[index],
                swapchains[index],
                indices[index],
                self.vulkan_presents,
                write_kind,
                force_content_probe,
                real_queue,
                waits[0..wait_count],
                &waits_consumed,
                &captures[index],
                &capture_bytes,
            );
            if (self.pixel_probe.readback_completion_failed) {
                // A submitted copy without completion cannot be displayed
                // safely or presented with its consumed binary waits.
                self.noteRealVulkanResult(self.pixel_probe.last_result, "vkQueueWaitIdle(readback-completion)");
                return @as(u32, @bitCast(self.pixel_probe.last_result));
            }
            if (self.pixel_probe.last_sample) |sample| {
                if (sample.frame == self.vulkan_presents and sample.swapchain == swapchains[index] and sample.image == acquired_images[index]) samples[index] = sample;
            }
        }
        var content_target_observed = false;
        for (content_targets) |content_target| {
            content_target_observed = content_target_observed or content_target;
        }
        if (content_target_observed and self.native_presenter.stage.isReady()) {
            // The guest now has real work attached to its acquired image.
            // Retire Rosette's bootstrap swapchain before the guest WSI
            // presents so one CAMetalLayer drawable pool is not contested.
            self.retireNativePresenterForGuestSwapchain(
                self.native_presenter.extent.width,
                self.native_presenter.extent.height,
            );
        }
        if (waits_consumed) {
            // Also clear on post-submit analysis/invalidation failure:
            // those failures do not un-consume a binary semaphore.
            real_info.wait_semaphore_count = 0;
            real_info.wait_semaphores = null;
        }
        const present_started = transport_timing.nowNs();
        const result = self.real_vulkan.fn_ptrs.queue_present.?(real_queue, &real_info);
        self.transport_cost.finish(.wsi_present, present_started);
        self.noteRealVulkanResult(result, "vkQueuePresentKHR");
        var accepted_content = false;
        for (0..swapchain_count) |index| {
            // Per-swapchain results are authoritative when the driver
            // fills them; the batch result is the fallback.
            const per_swapchain = resolvedPresentResult(result, results[index]);
            accepted_content = accepted_content or (content_targets[index] and (per_swapchain == abi.SUCCESS or per_swapchain == abi.SUBOPTIMAL_KHR));
        }
        if (accepted_content) self.transport_cost.content(ingress_ns);
        if (result_address != 0 and swapchain_count != 0) {
            if (state.guestMemory(result_address, @as(u64, swapchain_count) * 4)) |guest_results| {
                for (0..swapchain_count) |index| std.mem.writeInt(i32, guest_results[index * 4 ..][0..4], resolvedPresentResult(result, results[index]), .little);
            }
        }
        self.frame_provenance.noteNativePresentRequest();
        // A successful `vkQueuePresentKHR` only means that the WSI accepted
        // the request. The guest does not give this forwarding boundary a
        // frame fence, so use the real queue-idle edge when available to
        // prove that the queue completed its work. Keep request and
        // completion counters separate even when both are observed here.
        var hardware_completed = false;
        var completion_result: abi.Result = abi.NOT_READY;
        if (result == abi.SUCCESS or result == abi.SUBOPTIMAL_KHR) {
            // Waiting for the queue to drain after every present stalls
            // every guest thread for a whole GPU frame (51 s of a 640 s
            // run). Block only while the proof is the point: until the
            // first picture opens, and on a present the pixel probe read
            // back. Every other present is proven asynchronously by a
            // fence that is polled, never waited on.
            var probed = false;
            for (samples[0..swapchain_count]) |sample| probed = probed or sample != null;
            const prove_now = self.picture_sequence.frames == 0 or probed;
            if (prove_now) {
                if (self.real_vulkan.fn_ptrs.queue_wait_idle) |wait_idle| {
                    const completion_started = transport_timing.nowNs();
                    completion_result = wait_idle(real_queue);
                    self.transport_cost.finish(.present_completion, completion_started);
                    self.noteRealVulkanResult(completion_result, "vkQueueWaitIdle(present-completion)");
                    hardware_completed = completion_result == abi.SUCCESS;
                    self.present_completion_blocking +|= 1;
                    if (hardware_completed) self.present_completion_confirmed = self.vulkan_real_presents +| 1;
                }
            } else {
                hardware_completed = self.trackPresentCompletion(real_queue);
            }
        }
        self.gpu_runtime.observeBackendProgress(false, hardware_completed);
        self.vulkan_tiers.note(.presentation, .real);
        if (result == abi.SUCCESS or result == abi.SUBOPTIMAL_KHR) {
            self.vulkan_real_presents +|= 1;
        }
        if (hardware_completed) self.vulkan_real_present_completions +|= 1;
        const completed_ns = transport_timing.nowNs();
        // Include synchronous completion/probe delays in the pacing edge
        // so accepted timestamps cannot bunch up after a slow first call.
        // Failed attempts are also paced rather than retried in a burst.
        self.present_ceiling.attempted(completed_ns);
        if (result == abi.SUCCESS or result == abi.SUBOPTIMAL_KHR) {
            self.transport_cost.acceptedPresent(completed_ns);
        }
        for (0..swapchain_count) |index| {
            const per_swapchain = resolvedPresentResult(result, results[index]);
            const accepted = per_swapchain == abi.SUCCESS or per_swapchain == abi.SUBOPTIMAL_KHR;
            const opened = self.picture_sequence.observe(.{
                .present = self.vulkan_presents,
                .swapchain = swapchains[index],
                .image = acquired_images[index],
                .content = content_targets[index],
                .accepted = accepted,
                .completed = hardware_completed,
                .sample = if (samples[index]) |sample| sample.pictureEvidence() else null,
            }, completed_ns);
            if (opened) machoCapturePrint("macho-processor: CONTENT FRAME BEGIN: frame=1 raw_present={d} swapchain=0x{x} image=0x{x} custody=fresh_RGB_detail+native_accepted+queue_completed; first observed picture, not a game-loop or scanout claim\n", .{ self.vulkan_presents, swapchains[index], acquired_images[index] });
        }
        if (result == abi.SUCCESS or result == abi.SUBOPTIMAL_KHR) {
            self.notePresentationProgress(completed_ns);
        }
        // Independent CPU preview is still not WSI/scanout evidence. A
        // rejected or incomplete native request never receives an epoch
        // frame number or consumes the picture PNG budget.
        for (0..swapchain_count) |index| {
            const per_swapchain = resolvedPresentResult(result, results[index]);
            if (hardware_completed and (per_swapchain == abi.SUCCESS or per_swapchain == abi.SUBOPTIMAL_KHR)) {
                if (captures[index]) |capture| {
                    const picture_frame = if (content_targets[index] and self.picture_sequence.last_present == self.vulkan_presents) self.picture_sequence.frames else 0;
                    self.captureReadback(capture, picture_frame);
                }
                if (content_targets[index]) {
                    if (samples[index]) |sample| {
                        self.transport_cost.pixels(sample.stats.hash, completed_ns);
                        self.probeBrightnessLadder(swapchains[index], self.vulkan_presents, real_queue, sample.stats, sample.format);
                    }
                }
            }
            self.present_chain.notePresent(swapchains[index], per_swapchain);
        }
        // Report after updating completion counters, not one present
        // behind. An accepted request alone is not completion evidence.
        self.reportPresentChain(false);
        if (self.vulkan_real_presents <= 4) {
            machoCapturePrint(
                "macho-processor: REAL vkQueuePresentKHR: request={s} queue_completion={s} completion_result={d}\n",
                .{
                    if (result == abi.SUCCESS or result == abi.SUBOPTIMAL_KHR) "ACCEPTED" else "REJECTED",
                    if (hardware_completed) "PROVEN" else "UNPROVEN",
                    completion_result,
                },
            );
        }
        if (result != abi.SUCCESS and result != abi.SUBOPTIMAL_KHR) machoCapturePrint("macho-processor: REAL vkQueuePresentKHR FAILED: VkResult={d}\n", .{result});
        return @as(u32, @bitCast(result));
    }
    // This branch is reached only when the guest-native queue/present path
    // was not available. A guest present request is still useful as a
    // refresh trigger, but the pixels are diagnostic until a real guest
    // image or the console front buffer is discovered.
    const presented = self.presentWindowFrame(state, self.vulkan_presents, 0, 0, 3);
    if (self.vulkan_presents == 1) {
        machoCapturePrint(
            "macho-processor: Vulkan FALLBACK milestone: first_queue_present. presentation provenance=DIAGNOSTIC_ONLY source=host_clear guest_native_present=NO native_swapchain={s} native_queue_submit={s} guest_output=NO displayed={}\n",
            .{
                if (self.native_presenter.stage.isReady()) "YES" else "NO",
                if (self.native_presenter.ledger.native_submissions != 0) "YES" else "NO",
                presented,
            },
        );
    }
    return 0;
}

pub fn allocateVulkanMemory(self: anytype, state: anytype, info: u64, output: u64) u64 {
    if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
    if (self.realDeviceLostResult()) |lost| return lost;
    // VkMemoryAllocateInfo is {sType, padding, pNext, allocationSize,
    // memoryTypeIndex}. Reading +8 observes pNext (often a stack address),
    // not allocationSize, and caused the old model to reserve multi-GB
    // phantom allocations.
    if (info == 0 or state.guestMemoryConst(info + 16, 8) == null) return vkErrorInitializationFailed();
    const requested_size = state.read64(info + 16);
    const memory_type_index = state.read32(info + 24);
    if (requested_size == 0) return vkErrorInitializationFailed();

    // Xenia's macOS Vulkan implementation uses VkMemoryDedicatedAllocateInfo
    // for its large shared buffers when the host advertises the dedicated
    // allocation extension.  The guest node is in guest memory and its
    // handles are guest-visible synthetic values; passing either through
    // unchanged would make the real driver dereference an invalid pointer
    // or bind the wrong resource.  Accept exactly one bounded, terminal
    // node and translate its resource handles into the native allocation
    // info.  Unknown chains remain an explicit ABI refusal.
    var dedicated: abi.MemoryDedicatedAllocateInfo = .{};
    var has_dedicated = false;
    const guest_next = state.read64(info + 8);
    if (guest_next != 0) {
        if (state.guestMemoryConst(guest_next, @sizeOf(abi.MemoryDedicatedAllocateInfo)) == null or
            state.read32(guest_next) != abi.STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO or
            state.read64(guest_next + 8) != 0)
        {
            return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        }
        dedicated.s_type = abi.STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO;
        const guest_image = state.read64(guest_next + 16);
        const guest_buffer = state.read64(guest_next + 24);
        if (guest_image != 0) dedicated.image = self.real_vulkan.realImage(guest_image) orelse return vkErrorInitializationFailed();
        if (guest_buffer != 0) dedicated.buffer = self.real_vulkan.realBuffer(guest_buffer) orelse return vkErrorInitializationFailed();
        if (dedicated.image == 0 and dedicated.buffer == 0) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        has_dedicated = true;
    }

    const record = self.freeVulkanMemoryRecord() orelse return vkErrorOutOfHostMemory();
    if (self.real_vulkan.hasDevice() and HandleMap.freeSlots(&self.real_vulkan.memory_map) == 0) {
        self.noteVulkanMapCapacityRefusal("vkAllocateMemory", 1, 0);
        return vkErrorOutOfHostMemory();
    }
    const handle = self.nextVulkanObject();
    record.* = .{
        .handle = handle,
        .requested_size = requested_size,
        .memory_flags_known = self.real_vulkan.hasDevice() and memory_type_index < self.real_vulkan.physical_device_memory.memory_type_count,
        .memory_flags = if (memory_type_index < self.real_vulkan.physical_device_memory.memory_type_count) self.real_vulkan.physical_device_memory.memory_types[memory_type_index].property_flags else 0,
    };
    self.vulkan_memory_allocations +|= 1;

    // Phase 1: when the real device is available, allocate real GPU memory.
    if (self.real_vulkan.hasDevice()) {
        const device = self.real_vulkan.device.?;
        const alloc_fn = self.real_vulkan.fn_ptrs.allocate_memory orelse {
            record.* = .{};
            return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        };
        var alloc_info: abi.MemoryAllocateInfo = .{};
        alloc_info.allocation_size = requested_size;
        alloc_info.memory_type_index = memory_type_index;
        alloc_info.p_next = if (has_dedicated) &dedicated else null;
        var real_memory: abi.DeviceMemory = 0;
        const result = alloc_fn(device, &alloc_info, null, &real_memory);
        self.noteRealVulkanResult(result, "vkAllocateMemory");
        if (result == 0 and real_memory != 0) {
            if (!self.mapVulkanHandle(&self.real_vulkan.memory_map, handle, real_memory, "vkAllocateMemory")) {
                if (self.real_vulkan.fn_ptrs.free_memory) |free| free(device, real_memory, null);
                record.* = .{};
                return vkErrorOutOfHostMemory();
            }
            self.vulkan_tiers.note(.device_memory, .real);
            if (sparseVulkanSuccessLog(self.vulkan_memory_allocations)) machoCapturePrint(
                "macho-processor: REAL Vulkan memory sample: count={d} synthetic=0x{x} real=0x{x} size={d} type={d}\n",
                .{ self.vulkan_memory_allocations, handle, real_memory, requested_size, memory_type_index },
            );
        } else {
            machoCapturePrint(
                "macho-processor: REAL vkAllocateMemory FAILED: VkResult={d} size={d} type={d}\n",
                .{ result, requested_size, memory_type_index },
            );
            record.* = .{};
            return @as(u32, @bitCast(if (result != abi.SUCCESS) result else abi.ERROR_OUT_OF_DEVICE_MEMORY));
        }
    }

    state.write64(output, handle);
    registerOpaqueHandle(state, handle, "Vulkan device memory");
    if (sparseVulkanSuccessLog(self.vulkan_memory_allocations)) {
        machoCapturePrint(
            "macho-processor: Vulkan memory allocated: handle=0x{x} requested_size={d} output=0x{x}\n",
            .{ handle, requested_size, output },
        );
    }
    return 0;
}

pub fn mapVulkanMemory(
    self: anytype,
    state: anytype,
    memory_handle: u64,
    offset: u64,
    requested_size: u64,
    output: u64,
) u64 {
    if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
    if (self.realDeviceLostResult()) |lost| return lost;
    // The guest-visible pointer is always a Rosette-owned window. With a
    // real device that window is explicitly copied to/from the driver map
    // during flush/invalidate; without one it remains the modelled backing
    // store. Do not mark the fact modelled before the real map succeeds.
    const max_modeled_size: u64 = 64 * 1024 * 1024;
    const record = self.findVulkanMemoryRecord(memory_handle) orelse return vkErrorInitializationFailed();
    if (offset > record.requested_size) return vkErrorInitializationFailed();
    const available_size = record.requested_size - offset;
    const map_size = if (requested_size == std.math.maxInt(u64))
        available_size
    else
        requested_size;
    if (map_size == 0 or map_size > available_size or record.requested_size > max_modeled_size) {
        return vkErrorOutOfHostMemory();
    }

    const reused = record.mapped_base != 0;
    if (reused) {
        // Vulkan forbids a second native vkMapMemory while an allocation
        // is already mapped. Reuse is valid only inside the original
        // native range; otherwise the guest must unmap first.
        const range_valid = if (self.real_vulkan.hasDevice())
            record.host_mapped_ptr != null and
                rangeContains(record.mapped_offset, record.host_mapped_size, offset, map_size)
        else
            rangeContains(record.mapped_offset, record.mapped_size, offset, map_size);
        if (!range_valid) {
            machoCapturePrint(
                "macho-processor: Vulkan vkMapMemory refused: existing mapping does not cover offset={d} size={d} handle=0x{x}; vkUnmapMemory is required before remapping\n",
                .{ offset, map_size, memory_handle },
            );
            return @as(u32, @bitCast(abi.ERROR_MEMORY_MAP_FAILED));
        }
        self.vulkan_memory_map_reuses +|= 1;
    } else if (self.real_vulkan.hasDevice()) {
        if (comptime @hasDecl(@TypeOf(state.*), "borrowNativeMemory")) {
            if (abi.nativeMemoryMapAlignment(&self.real_vulkan.physical_device_properties) == null) {
                machoCapturePrint("macho-processor: NATIVE MEMORY ALIAS REFUSED: memory=0x{x}; minMemoryMapAlignment unavailable or exceeds the validated 4-GiB address-alignment contract\n", .{memory_handle});
                return @as(u32, @bitCast(abi.ERROR_MEMORY_MAP_FAILED));
            }
        }
        // Map the native allocation first. The guest shadow is committed
        // only after the driver accepts the request, so a failed native
        // map cannot leave a record that later appears reusable.
        const map_fn = self.real_vulkan.fn_ptrs.map_memory orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const real_mem = self.real_vulkan.realMemory(memory_handle) orelse return vkErrorInitializationFailed();
        var host_ptr: ?*anyopaque = null;
        const device = self.real_vulkan.device.?;
        const result = map_fn(device, real_mem, offset, map_size, 0, &host_ptr);
        if (result != abi.SUCCESS or host_ptr == null) {
            machoCapturePrint(
                "macho-processor: REAL vkMapMemory FAILED: VkResult={d} synthetic=0x{x} offset={d} size={d}\n",
                .{ result, memory_handle, offset, map_size },
            );
            return @as(u32, @bitCast(if (result != abi.SUCCESS) result else abi.ERROR_MEMORY_MAP_FAILED));
        }
        const host_bytes = @as([*]u8, @ptrCast(host_ptr.?))[0..@as(usize, @intCast(map_size))];
        if (comptime @hasDecl(@TypeOf(state.*), "borrowNativeMemory")) {
            const alias = state.borrowNativeMemory(host_bytes) orelse {
                if (self.real_vulkan.fn_ptrs.unmap_memory) |unmap| unmap(device, real_mem);
                machoCapturePrint("macho-processor: NATIVE MEMORY ALIAS REFUSED: memory=0x{x} size={d}; native map rolled back, not silently downgraded to incoherent shadow\n", .{ memory_handle, map_size });
                return vkErrorOutOfHostMemory();
            };
            record.native_alias_base = alias;
            record.mapped_base = alias - offset;
            self.vulkan_native_memory_aliases +|= 1;
        } else {
            record.mapped_base = state.guestAlloc(record.requested_size, 16) orelse {
                if (self.real_vulkan.fn_ptrs.unmap_memory) |unmap| unmap(device, real_mem);
                return vkErrorOutOfHostMemory();
            };
        }
        record.mapped_size = record.requested_size;
        record.mapped_offset = offset;
        record.host_mapped_ptr = host_ptr;
        record.host_mapped_size = map_size;
        if (record.native_alias_base == 0) {
            record.shadow_baseline = std.heap.c_allocator.dupe(u8, host_bytes) catch {
                if (self.real_vulkan.fn_ptrs.unmap_memory) |unmap| unmap(device, real_mem);
                record.mapped_base = 0;
                record.mapped_size = 0;
                record.mapped_offset = 0;
                record.host_mapped_ptr = null;
                record.host_mapped_size = 0;
                return vkErrorOutOfHostMemory();
            };
            // Mapping an existing allocation exposes its current bytes, not
            // the zero-filled guest allocator window. No completion is
            // invented: the guest still owes the usual fence/invalidate edge.
            if (!self.copyMappedBytes(state, memory_handle, offset, map_size, false)) {
                if (self.real_vulkan.fn_ptrs.unmap_memory) |unmap| unmap(device, real_mem);
                record.releaseBaseline();
                record.mapped_base = 0;
                record.mapped_size = 0;
                record.host_mapped_ptr = null;
                record.host_mapped_size = 0;
                return vkErrorInitializationFailed();
            }
        }
        self.vulkan_tiers.note(.memory_mapping, .real);
        if (sparseVulkanSuccessLog(self.vulkan_memory_maps + 1)) machoCapturePrint(
            "macho-processor: REAL Vulkan map sample: count={d} synthetic=0x{x} real=0x{x} host_ptr=0x{x} size={d}\n",
            .{ self.vulkan_memory_maps + 1, memory_handle, real_mem, @intFromPtr(host_ptr.?), map_size },
        );
    } else {
        const mapped_base = state.guestAlloc(record.requested_size, 16) orelse return vkErrorOutOfHostMemory();
        record.mapped_base = mapped_base;
        record.mapped_size = record.requested_size;
        record.mapped_offset = 0;
        self.vulkan_tiers.note(.memory_mapping, .modelled);
    }

    const mapped_address = std.math.add(u64, record.mapped_base, offset) catch {
        // The native map and the guest shadow are one transaction. If the
        // guest-visible address cannot represent the requested offset,
        // undo the native side before discarding the shadow record; a
        // half-committed mapping would make the next map appear reusable
        // while its driver range is no longer described accurately.
        if (!reused and self.real_vulkan.hasDevice() and record.host_mapped_ptr != null) {
            if (self.real_vulkan.realMemory(memory_handle)) |real_memory| {
                if (self.real_vulkan.fn_ptrs.unmap_memory) |unmap| unmap(self.real_vulkan.device.?, real_memory);
            }
        }
        if (comptime @hasDecl(@TypeOf(state.*), "releaseNativeMemory")) {
            if (record.native_alias_base != 0) state.releaseNativeMemory(record.native_alias_base);
        }
        record.native_alias_base = 0;
        record.mapped_base = 0;
        record.mapped_size = 0;
        record.mapped_offset = 0;
        record.host_mapped_ptr = null;
        record.host_mapped_size = 0;
        record.releaseBaseline();
        return vkErrorInitializationFailed();
    };
    state.write64(output, mapped_address);
    self.vulkan_memory_maps +|= 1;
    if (sparseVulkanSuccessLog(self.vulkan_memory_maps)) {
        machoCapturePrint(
            "macho-processor: Vulkan memory mapped: handle=0x{x} ptr=0x{x} allocation_size={d} offset={d} requested_size={d} map_size={d} reused={} output=0x{x}\n",
            .{
                memory_handle,
                mapped_address,
                record.requested_size,
                offset,
                requested_size,
                map_size,
                reused,
                output,
            },
        );
    }
    return 0;
}

pub fn freeVulkanMemoryRecord(self: anytype) ?*VulkanMemoryAllocation {
    for (&self.vulkan_memory_records) |*record| {
        if (record.handle == 0) return record;
    }
    return null;
}

pub fn findVulkanMemoryRecord(self: anytype, handle: u64) ?*VulkanMemoryAllocation {
    for (&self.vulkan_memory_records) |*record| {
        if (record.handle == handle) return record;
    }
    return null;
}

pub fn allocateVulkanObjects(self: anytype, state: anytype, info: u64, output: u64, count_offset: u64, name: []const u8) u64 {
    if (self.realDeviceLostResult()) |lost| return lost;
    if (info == 0 or state.guestMemoryConst(info + count_offset, 4) == null) return vkErrorInitializationFailed();
    const count = state.read32(info + count_offset);
    if (count == 0) return 0;
    if (output == 0 or state.guestMemory(output, @as(u64, count) * 8) == null) return vkErrorInitializationFailed();

    if (std.mem.eql(u8, name, "vkAllocateCommandBuffers") and self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.allocate_command_buffers != null) {
        const pool_synthetic = state.read64(info + 16);
        const pool = self.real_vulkan.realCommandPool(pool_synthetic) orelse return vkErrorInitializationFailed();
        if (count > 256) {
            return self.refuseVulkanCall(
                name,
                "native command-buffer batch exceeds the bridge's bounded output storage",
                abi.ERROR_OUT_OF_HOST_MEMORY,
                .{ count, 256, output },
            );
        }
        const real_count: u32 = @intCast(count);
        const available = HandleMap.freeSlots(&self.real_vulkan.command_buffer_map);
        if (available < @as(usize, @intCast(real_count))) {
            self.noteVulkanMapCapacityRefusal(name, @intCast(real_count), available);
            return vkErrorOutOfHostMemory();
        }
        var real_info = abi.CommandBufferAllocateInfo{
            .command_pool = pool,
            .level = state.read32(info + 24),
            .command_buffer_count = real_count,
        };
        var real_buffers: [256]abi.CommandBuffer = [_]abi.CommandBuffer{null} ** 256;
        const result = self.real_vulkan.fn_ptrs.allocate_command_buffers.?(self.real_vulkan.device.?, &real_info, &real_buffers);
        self.noteRealVulkanResult(result, "vkAllocateCommandBuffers");
        if (result != abi.SUCCESS) return @as(u32, @bitCast(result));
        var synthetic_buffers: [256]u64 = [_]u64{0} ** 256;
        var mapped_count: usize = 0;
        for (0..real_count) |index| {
            const synthetic = self.nextVulkanObject();
            const real = real_buffers[index] orelse {
                for (synthetic_buffers[0..mapped_count]) |mapped| {
                    _ = self.releaseVulkanHandle(&self.real_vulkan.command_buffer_map, mapped);
                }
                if (self.real_vulkan.fn_ptrs.free_command_buffers) |free| free(self.real_vulkan.device.?, pool, real_count, &real_buffers);
                return vkErrorInitializationFailed();
            };
            if (!self.mapVulkanHandle(&self.real_vulkan.command_buffer_map, synthetic, @intFromPtr(real), name)) {
                for (synthetic_buffers[0..mapped_count]) |mapped| {
                    _ = self.releaseVulkanHandle(&self.real_vulkan.command_buffer_map, mapped);
                }
                if (self.real_vulkan.fn_ptrs.free_command_buffers) |free| free(self.real_vulkan.device.?, pool, real_count, &real_buffers);
                return vkErrorOutOfHostMemory();
            }
            synthetic_buffers[mapped_count] = synthetic;
            mapped_count += 1;
            state.write64(output + @as(u64, @intCast(index)) * 8, synthetic);
            registerOpaqueHandle(state, synthetic, name);
        }
        self.fsiNoteCommandBuffersAllocated(synthetic_buffers[0..mapped_count], pool_synthetic, real_info.level);
        self.vulkan_tiers.note(.command_buffer, .real);
        self.vulkan_command_buffer_allocations +|= 1;
        if (sparseVulkanSuccessLog(self.vulkan_command_buffer_allocations)) {
            machoCapturePrint("macho-processor: REAL Vulkan command-buffer allocation sample: call={d} pool=0x{x} count={d}\n", .{ self.vulkan_command_buffer_allocations, pool_synthetic, real_count });
        }
        return 0;
    }

    if (std.mem.eql(u8, name, "vkAllocateDescriptorSets") and self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.allocate_descriptor_sets != null) {
        const pool_synthetic = state.read64(info + 16);
        const pool = self.real_vulkan.realDescriptorPool(pool_synthetic) orelse return vkErrorInitializationFailed();
        if (count > 256) {
            return self.refuseVulkanCall(
                name,
                "native descriptor-set batch exceeds the bridge's bounded output storage",
                abi.ERROR_OUT_OF_HOST_MEMORY,
                .{ count, 256, output },
            );
        }
        _ = self.reclaimOrphanedDescriptorSets();
        const real_count: u32 = @intCast(count);
        const available = HandleMap.freeSlots(&self.real_vulkan.descriptor_set_map);
        if (available < @as(usize, @intCast(real_count))) {
            self.noteVulkanMapCapacityRefusal(name, @intCast(real_count), available);
            return vkErrorOutOfHostMemory();
        }
        const layouts_address = state.read64(info + 32);
        if (layouts_address == 0 or state.guestMemoryConst(layouts_address, @as(u64, real_count) * 8) == null) return vkErrorInitializationFailed();
        var layouts: [256]u64 = [_]u64{0} ** 256;
        for (0..real_count) |index| {
            const synthetic = state.read64(layouts_address + @as(u64, @intCast(index)) * 8);
            layouts[index] = self.real_vulkan.realDescriptorSetLayout(synthetic) orelse return vkErrorInitializationFailed();
        }
        const real_info = abi.DescriptorSetAllocateInfo{
            .descriptor_pool = pool,
            .descriptor_set_count = real_count,
            .descriptor_set_layouts = &layouts,
        };
        var real_sets: [256]u64 = [_]u64{0} ** 256;
        const result = self.real_vulkan.fn_ptrs.allocate_descriptor_sets.?(self.real_vulkan.device.?, &real_info, &real_sets);
        self.noteRealVulkanResult(result, "vkAllocateDescriptorSets");
        if (result != abi.SUCCESS) return @as(u32, @bitCast(result));
        var synthetic_sets: [256]u64 = [_]u64{0} ** 256;
        var mapped_count: usize = 0;
        for (0..real_count) |index| {
            const synthetic = self.nextVulkanObject();
            if (!self.mapVulkanHandleOwned(&self.real_vulkan.descriptor_set_map, synthetic, real_sets[index], pool_synthetic, name)) {
                for (synthetic_sets[0..mapped_count]) |mapped| {
                    _ = self.releaseVulkanHandle(&self.real_vulkan.descriptor_set_map, mapped);
                    self.forgetDescriptorSet(mapped);
                }
                if (self.real_vulkan.fn_ptrs.free_descriptor_sets) |free| _ = free(self.real_vulkan.device.?, pool, real_count, &real_sets);
                return vkErrorOutOfHostMemory();
            }
            synthetic_sets[mapped_count] = synthetic;
            mapped_count += 1;
            state.write64(output + @as(u64, @intCast(index)) * 8, synthetic);
            registerOpaqueHandle(state, synthetic, name);
            self.noteDescriptorSetPool(synthetic, pool_synthetic);
        }
        self.vulkan_tiers.note(.descriptor_set, .real);
        self.vulkan_descriptor_set_allocations +|= 1;
        if (sparseVulkanSuccessLog(self.vulkan_descriptor_set_allocations)) {
            machoCapturePrint("macho-processor: REAL Vulkan descriptor-set allocation sample: call={d} pool=0x{x} count={d}\n", .{ self.vulkan_descriptor_set_allocations, pool_synthetic, real_count });
        }
        return 0;
    }

    for (0..count) |index| {
        const handle = self.nextVulkanObject();
        state.write64(output + @as(u64, @intCast(index)) * 8, handle);
        registerOpaqueHandle(state, handle, name);
    }
    self.vulkan_synthetic_object_batches +|= 1;
    if (sparseVulkanSuccessLog(self.vulkan_synthetic_object_batches)) {
        machoCapturePrint("macho-processor: Vulkan synthetic object batch sample: call={d} kind={s} count={d} output=0x{x}\n", .{ self.vulkan_synthetic_object_batches, name, count, output });
    }
    return 0;
}

pub fn observeFsiDescriptorSetLayout(self: anytype, state: anytype, create_info: u64) void {
    var root: marshal.DescriptorSetLayoutCreateInfo = undefined;
    if (!copyGuestValue(marshal.DescriptorSetLayoutCreateInfo, state, create_info, &root) or root.binding_count != 3) return;
    const bindings_address = if (root.bindings) |pointer| @intFromPtr(pointer) else return;
    const binding_bytes_len = 3 * @sizeOf(marshal.DescriptorSetLayoutBinding);
    const bytes = state.guestMemoryConst(bindings_address, binding_bytes_len) orelse return;
    var guest_bindings: [3]marshal.DescriptorSetLayoutBinding = undefined;
    @memcpy(std.mem.sliceAsBytes(guest_bindings[0..]), bytes);
    var bindings: [3]fsi_diagnostics.DescriptorBinding = undefined;
    for (guest_bindings, 0..) |binding, index| {
        bindings[index] = .{
            .binding = binding.binding,
            .descriptor_type = binding.descriptor_type,
            .descriptor_count = binding.descriptor_count,
            .stage_flags = binding.stage_flags,
            .immutable_samplers = if (binding.immutable_samplers) |pointer| @intFromPtr(pointer) else 0,
        };
    }
    const shared_count = fsi_diagnostics.sharedMemoryBindingCount(&bindings) orelse return;
    self.vulkan_fsi_descriptor_layouts +|= 1;
    self.vulkan_fsi_shared_memory_binding_count = shared_count;
    self.vulkan_fsi_shared_memory_binding_count_known = true;
    const limits = abi.fsiPhysicalDeviceLimits(&self.real_vulkan.physical_device_properties) orelse return;
    self.vulkan_fsi_host_storage_buffer_limit = limits.max_per_stage_storage_buffers;
    self.vulkan_fsi_host_storage_buffer_limit_known = true;
    self.vulkan_fsi_binding_limit_would_fallback = shared_count >= limits.max_per_stage_storage_buffers;
    if (limits.max_storage_buffer_range != 0) {
        self.vulkan_fsi_binding_count_matches_host_range_known = true;
        self.vulkan_fsi_binding_count_matches_host_range = shared_count ==
            fsi_diagnostics.sharedMemoryBindingCountForRange(limits.max_storage_buffer_range);
    }
    if (self.vulkan_fsi_descriptor_layouts <= 3) machoCapturePrint(
        "macho-processor: Vulkan FSI path selection: Xenia EDRAM/ZPD descriptor layout observed shared_memory_bindings={d} host_maxPerStageDescriptorStorageBuffers={d} would_fallback={s} maxStorageBufferRange={d}\n",
        .{ shared_count, limits.max_per_stage_storage_buffers, if (self.vulkan_fsi_binding_limit_would_fallback) "yes" else "no", limits.max_storage_buffer_range },
    );
}

pub fn copyGuestValue(comptime T: type, state: anytype, address: u64, value: *T) bool {
    const bytes = state.guestMemoryConst(address, @sizeOf(T)) orelse return false;
    @memcpy(std.mem.asBytes(value), bytes);
    return true;
}

pub fn guestPointerValue(comptime T: type, pointer: ?[*]const T) u64 {
    return if (pointer) |value| @intFromPtr(value) else 0;
}

pub fn copyPipelineName(state: anytype, guest_pointer: u64, destination: *[64]u8) bool {
    const text = state.guestCString(guest_pointer, 63) orelse return false;
    if (text.len >= destination.len) return false;
    @memset(destination, 0);
    @memcpy(destination[0..text.len], text);
    return true;
}

pub fn marshalGuestArray(
    comptime T: type,
    state: anytype,
    guest: ?[*]const T,
    count: u32,
    storage: []T,
    comptime unreadable: PipelineMarshalFailure,
) PipelineMarshalFailure!?[*]const T {
    const address = guestPointerValue(T, guest);
    if (address == 0 or count == 0) return null;
    if (!copyGuestStructs(T, state, address, count, storage)) return unreadable;
    return storage.ptr;
}

pub fn marshalSpecializationInfo(
    state: anytype,
    guest_address: u64,
    scratch: *SpecializationScratch,
) PipelineMarshalFailure!*const abi.SpecializationInfo {
    if (!copyGuestValue(abi.SpecializationInfo, state, guest_address, &scratch.info)) return error.SpecializationInfoUnreadable;
    if (scratch.info.map_entry_count > scratch.entries.len) return error.SpecializationMapOutOfRange;
    if (scratch.info.data_size > scratch.data.len) return error.SpecializationDataOutOfRange;
    scratch.info.map_entries = try marshalGuestArray(
        abi.SpecializationMapEntry,
        state,
        scratch.info.map_entries,
        scratch.info.map_entry_count,
        &scratch.entries,
        error.SpecializationInfoUnreadable,
    );
    const data_address = if (scratch.info.data) |pointer| @intFromPtr(pointer) else 0;
    if (data_address == 0 or scratch.info.data_size == 0) {
        scratch.info.data = null;
        scratch.info.data_size = 0;
    } else {
        if (!copyGuestBytes(state, data_address, scratch.info.data_size, &scratch.data)) return error.SpecializationInfoUnreadable;
        scratch.info.data = @ptrCast(&scratch.data);
    }
    return &scratch.info;
}

pub fn callNativeGraphicsPipeline(
    state: anytype,
    function: abi.PfnCreateGraphicsPipelines,
    device: abi.Device,
    cache: abi.PipelineCache,
    info: *const abi.GraphicsPipelineCreateInfo,
    output: *u64,
) abi.Result {
    const call = NativeGraphicsPipelineCall{
        .function = function,
        .device = device,
        .cache = cache,
        .info = info,
        .output = output,
    };
    if (comptime @hasDecl(@TypeOf(state.*), "withWindowsRuntimeLockReleased")) {
        return state.withWindowsRuntimeLockReleased(call, NativeGraphicsPipelineCall.invoke);
    }
    return NativeGraphicsPipelineCall.invoke(call);
}

pub fn callNativeComputePipeline(
    state: anytype,
    function: abi.PfnCreateComputePipelines,
    device: abi.Device,
    cache: abi.PipelineCache,
    info: *const abi.ComputePipelineCreateInfo,
    output: *u64,
) abi.Result {
    const call = NativeComputePipelineCall{
        .function = function,
        .device = device,
        .cache = cache,
        .info = info,
        .output = output,
    };
    if (comptime @hasDecl(@TypeOf(state.*), "withWindowsRuntimeLockReleased")) {
        return state.withWindowsRuntimeLockReleased(call, NativeComputePipelineCall.invoke);
    }
    return NativeComputePipelineCall.invoke(call);
}
