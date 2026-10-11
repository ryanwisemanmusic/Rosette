// Split implementation for Forwarder; wrappers keep the public state API stable.
const process = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = process.__ForwarderInternals;
const Forwarder = process.Forwarder;
const GuestHandleKind = process.GuestHandleKind;
const DescriptorUpdateFailureDetails = __ForwarderInternals._DescriptorUpdateFailureDetails;
const FsiGuard = __ForwarderInternals._FsiGuard;
const FsiReplayOps = __ForwarderInternals._FsiReplayOps;
const FsiSegment = __ForwarderInternals._FsiSegment;
const VK_ATTACHMENT_LOAD_OP_CLEAR = __ForwarderInternals._VK_ATTACHMENT_LOAD_OP_CLEAR;
const VK_PIPELINE_BIND_POINT_GRAPHICS = __ForwarderInternals._VK_PIPELINE_BIND_POINT_GRAPHICS;
const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST = __ForwarderInternals._VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP = __ForwarderInternals._VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
const VulkanCommandAdmission = __ForwarderInternals._VulkanCommandAdmission;
const abi = __ForwarderInternals._abi;
const async_vulkan_command = __ForwarderInternals._async_vulkan_command;
const builtin = __ForwarderInternals._builtin;
const canonicalVulkanCommand = __ForwarderInternals._canonicalVulkanCommand;
const captureRunDirectory = __ForwarderInternals._captureRunDirectory;
const forwardedVulkanCommandIndex = __ForwarderInternals._forwardedVulkanCommandIndex;
const forwarded_vulkan_commands = __ForwarderInternals._forwarded_vulkan_commands;
const fsiCanCoalesceSegments = __ForwarderInternals._fsiCanCoalesceSegments;
const fsiCommandClass = __ForwarderInternals._fsiCommandClass;
const fsiFenceNow = __ForwarderInternals._fsiFenceNow;
const fsiFenceReset = __ForwarderInternals._fsiFenceReset;
const fsiFenceWait = __ForwarderInternals._fsiFenceWait;
const fsiWatcherReport = __ForwarderInternals._fsiWatcherReport;
const fsi_chain = __ForwarderInternals._fsi_chain;
const fsi_contract = __ForwarderInternals._fsi_contract;
const fsi_diagnostics = __ForwarderInternals._fsi_diagnostics;
const fsi_segment_command_capacity = __ForwarderInternals._fsi_segment_command_capacity;
const fsi_timing = __ForwarderInternals._fsi_timing;
const gpu_vulkan = __ForwarderInternals._gpu_vulkan;
const guest_context = __ForwarderInternals._guest_context;
const machoCapturePrint = __ForwarderInternals._machoCapturePrint;
const marshal = __ForwarderInternals._marshal;
const native_texture = __ForwarderInternals._native_texture;
const rosette_gpu = __ForwarderInternals._rosette_gpu;
const sparseVulkanSuccessLog = __ForwarderInternals._sparseVulkanSuccessLog;
const std = __ForwarderInternals._std;
const transport_timing = __ForwarderInternals._transport_timing;
const vulkanNameHash = __ForwarderInternals._vulkanNameHash;
const addCommandImageView = Forwarder.addCommandImageView;
const clearCommandPassTarget = Forwarder.clearCommandPassTarget;
const commandPassTarget = Forwarder.commandPassTarget;
const copyGuestBytes = Forwarder.copyGuestBytes;
const copyGuestStructs = Forwarder.copyGuestStructs;
const copyGuestValue = Forwarder.copyGuestValue;
const deinit = Forwarder.deinit;
const faultOnUnavailableVulkanCommand = Forwarder.faultOnUnavailableVulkanCommand;
const forward = Forwarder.forward;
const forwardPushDescriptorSet = Forwarder.forwardPushDescriptorSet;
const fsiArmedGuard = Forwarder.fsiArmedGuard;
const fsiCommandTarget = Forwarder.fsiCommandTarget;
const fsiNoteBeginRenderPass = Forwarder.fsiNoteBeginRenderPass;
const fsiNoteShadowBlock = Forwarder.fsiNoteShadowBlock;
const fsiRasterBeforeCommand = Forwarder.fsiRasterBeforeCommand;
const fsiRecording = Forwarder.fsiRecording;
const fsiShadow = Forwarder.fsiShadow;
const graphicsStateTraceEnabled = Forwarder.graphicsStateTraceEnabled;
const guestFloatArgument = Forwarder.guestFloatArgument;
const guestStackArg = Forwarder.guestStackArg;
const mergeCommandTargets = Forwarder.mergeCommandTargets;
const mutableCommandTargets = Forwarder.mutableCommandTargets;
const noteCommandDescriptorSets = Forwarder.noteCommandDescriptorSets;
const noteCommandDynamicTarget = Forwarder.noteCommandDynamicTarget;
const noteCommandImageTarget = Forwarder.noteCommandImageTarget;
const noteCommandImageViewTransfer = Forwarder.noteCommandImageViewTransfer;
const noteCommandPassTarget = Forwarder.noteCommandPassTarget;
const noteCommandPipelineState = Forwarder.noteCommandPipelineState;
const noteCommandPushConstants = Forwarder.noteCommandPushConstants;
const noteCommandScissor = Forwarder.noteCommandScissor;
const noteCommandTargets = Forwarder.noteCommandTargets;
const noteCommandTransfer = Forwarder.noteCommandTransfer;
const noteCommandViewport = Forwarder.noteCommandViewport;
const noteLoadClearTarget = Forwarder.noteLoadClearTarget;
const noteRealVulkanResult = Forwarder.noteRealVulkanResult;
const printDeviceLossFsiSubmission = Forwarder.printDeviceLossFsiSubmission;
const rectExpandCommandState = Forwarder.rectExpandCommandState;
const rectangleExpandedPipeline = Forwarder.rectangleExpandedPipeline;
const rejectDescriptorBind = Forwarder.rejectDescriptorBind;
const repairGuestOutputTopology = Forwarder.repairGuestOutputTopology;
const trackFramebufferTargets = Forwarder.trackFramebufferTargets;
const trackRenderPassTransfers = Forwarder.trackRenderPassTransfers;
const trackedRenderPass = Forwarder.trackedRenderPass;
const updateDescriptorSetsNative = Forwarder.updateDescriptorSetsNative;
const vulkanTopologyLabel = Forwarder.vulkanTopologyLabel;

pub fn printFsiRasterReport(self: anytype) void {
    if (!self.fsi_raster.moltenvk or self.fsi_raster.adapted_pipelines == 0) return;
    machoCapturePrint("macho-processor: VULKAN FSI RASTERIZATION: pipelines={d} private_passes={d} sample_count_restarts={d} refusals={d}; compatible attachment-less passes preserve EDRAM and bindings while matching the bound pipeline's raster sample count; independent of ROSETTE_FSI_WATCHDOG_GUARD\n", .{ self.fsi_raster.adapted_pipelines, self.fsi_raster.variants_created, self.fsi_raster.restarts, self.fsi_raster.refusals });
}

pub fn fsiRasterShutdown(self: anytype) void {
    self.printFsiRasterReport();
    if (!self.real_vulkan.device_lost) {
        if (self.real_vulkan.fn_ptrs.destroy_render_pass) |destroy| {
            for (&self.fsi_raster.passes) |*pass| {
                for (pass.variants[1..]) |variant| if (variant != 0) destroy(self.real_vulkan.device, variant, null);
            }
        }
    }
    self.fsi_raster.deinit();
}

pub fn fsiNoteCommand(self: anytype, guest: u64, name_hash: u64, name: []const u8) void {
    const guard = self.fsiArmedGuard() orelse return;
    if (guard.monitor.context_dump_requested.swap(false, .acq_rel)) self.fsiPrintEscalationContext(guard);
    const recording = self.fsiRecording(guest) orelse return;
    if (recording.failed) return;
    switch (fsiCommandClass(name_hash, name)) {
        .draw => self.fsiBeforeDraw(guard, recording, guest),
        .blocks => recording.noteBlock(.unrecorded_command),
        .neutral => {},
        .recorded => {
            if (std.mem.eql(u8, name, "vkCmdEndRenderPass") or std.mem.startsWith(u8, name, "vkCmdEndRenderPass2")) {
                recording.endPass();
            } else if (std.mem.eql(u8, name, "vkCmdBeginQuery")) {
                recording.active_queries +|= 1;
            } else if (std.mem.eql(u8, name, "vkCmdEndQuery")) {
                recording.active_queries -|= 1;
            } else if (std.mem.eql(u8, name, "vkCmdBeginConditionalRenderingEXT")) {
                recording.conditional_rendering = true;
            } else if (std.mem.eql(u8, name, "vkCmdEndConditionalRenderingEXT")) {
                recording.conditional_rendering = false;
            }
        },
    }
}

pub fn fsiBeforeDraw(self: anytype, guard: *FsiGuard, recording: *fsi_chain.Recording, guest: u64) void {
    // The diagnostic tracker may evict identities in a long game. The
    // correctness registry still knows every pipeline on an FSI pass.
    if (!self.fsi_raster.pipelines.contains(recording.shadow.pipelines[fsi_chain.bind_point_graphics]) and
        !self.vulkan_fsi_tracker.isFsiPipelineBound(guest)) return;
    const area = recording.pass.render_area.extent;
    const pixels = if (recording.shadow.scissor_mask & 1 != 0) blk: {
        const scissor = recording.shadow.scissors[0];
        break :blk fsi_contract.scissoredPixels(scissor.offset.x, scissor.offset.y, scissor.extent.width, scissor.extent.height, area.width, area.height);
    } else blk: {
        guard.unscissored_draws +|= 1;
        break :blk @as(u64, area.width) * area.height;
    };
    const cap = guard.monitor.capValue();
    const pixel_cap = guard.monitor.sampleWorkCapValue();
    const bound_pipeline = recording.shadow.pipelines[fsi_chain.bind_point_graphics];
    const diagnostic = self.vulkan_fsi_tracker.findPipeline(bound_pipeline);
    const samples = self.fsi_raster.pipelineSampleCount(bound_pipeline) orelse
        (if (diagnostic) |identity| @max(identity.rasterization_samples, 1) else 1);
    const sample_work = pixels *| @as(u64, samples);
    const segment_pixels = recording.segment_sample_work[recording.chunk_count];
    const isolated = self.fsi_raster.isolated_pipelines.contains(bound_pipeline);
    const isolation_boundary = recording.segment_draws != 0 and
        (isolated or recording.segment_isolated[recording.chunk_count]);
    if (isolation_boundary or guard.monitor.shouldSplit(recording.segment_draws, segment_pixels, sample_work)) {
        const allowed = recording.splitAllowed();
        if (allowed == .none) {
            if (self.fsiSplitRecording(guard, recording)) {
                guard.splits +|= 1;
            } else {
                guard.split_failures +|= 1;
                if (recording.failed) {
                    guard.recording_aborts +|= 1;
                    guard.aborted_fsi_draws +|= 1;
                    machoCapturePrint(
                        "macho-processor: VULKAN FSI GUARD: poisoned recording refused guest_command_buffer=0x{x} chunks={d} draws_in_segment={d} draw_cap={d} sample_work_in_segment={d} next_draw_sample_work={d} sample_work_cap={d} pipeline=0x{x}; the old command buffer was already ended before the continuation failed, so end/submit must reject this partial chain\n",
                        .{ guest, recording.chunk_count, recording.segment_draws, cap, segment_pixels, sample_work, pixel_cap, recording.shadow.pipelines[fsi_chain.bind_point_graphics] },
                    );
                    return;
                }
                // Failures before ending the live buffer leave it intact.
                // Complete and submit it with normal Vulkan semantics;
                // the remaining tail is unsplit and may exceed budget.
                if (recording.block == .none) recording.noteBlock(.continuation_unavailable);
                guard.blocked_splits[@intFromEnum(recording.block)] +|= 1;
                recording.budget_block_reported = true;
                machoCapturePrint(
                    "macho-processor: VULKAN FSI GUARD: split deferred guest_command_buffer=0x{x} reason={s} chunks={d} draws_in_segment={d} draw_cap={d} sample_work_in_segment={d} next_draw_sample_work={d} sample_work_cap={d} pipeline=0x{x}; the live Vulkan command buffer remains intact and this tail stays whole because splitting failed before the old buffer was ended\n",
                    .{ guest, @tagName(recording.block), recording.chunk_count, recording.segment_draws, cap, segment_pixels, sample_work, pixel_cap, recording.shadow.pipelines[fsi_chain.bind_point_graphics] },
                );
            }
        } else if (allowed == .chunk_capacity) {
            // This is the hard end of the per-recording continuation
            // storage. Never forward an unbounded FSI tail to Metal.
            guard.blocked_splits[@intFromEnum(allowed)] +|= 1;
            recording.budget_block_reported = true;
            machoCapturePrint(
                "macho-processor: VULKAN FSI GUARD: hard chain limit reached guest_command_buffer=0x{x} reason={s} chunks={d} draws_in_segment={d} draw_cap={d} sample_work_in_segment={d} next_draw_sample_work={d} sample_work_cap={d} pipeline=0x{x}; recording refused before an unbounded tail could reach Metal\n",
                .{ guest, @tagName(allowed), recording.chunk_count, recording.segment_draws, cap, segment_pixels, sample_work, pixel_cap, recording.shadow.pipelines[fsi_chain.bind_point_graphics] },
            );
            recording.fail();
            guard.recording_aborts +|= 1;
            guard.aborted_fsi_draws +|= 1;
            return;
        } else if (!recording.budget_block_reported) {
            guard.blocked_splits[@intFromEnum(allowed)] +|= 1;
            recording.budget_block_reported = true;
            machoCapturePrint(
                "macho-processor: VULKAN FSI GUARD: split deferred guest_command_buffer=0x{x} reason={s} chunks={d} draws_in_segment={d} draw_cap={d} sample_work_in_segment={d} next_draw_sample_work={d} sample_work_cap={d} pipeline=0x{x}; preserving the guest's whole Vulkan recording because this boundary cannot be replayed exactly; this recording may exceed the Metal time budget\n",
                .{ guest, @tagName(allowed), recording.chunk_count, recording.segment_draws, cap, segment_pixels, sample_work, pixel_cap, recording.shadow.pipelines[fsi_chain.bind_point_graphics] },
            );
        } else {
            // Report once per recording; preserve its original command
            // stream until the hard chain limit is reached.
        }
    }
    const pipeline_hash = if (self.vulkan_fsi_tracker.findPipeline(recording.shadow.pipelines[fsi_chain.bind_point_graphics])) |identity| identity.combined_hash else 0;
    recording.noteFsiDrawSamples(pipeline_hash, pixels, samples);
    recording.segment_isolated[recording.chunk_count] = recording.segment_isolated[recording.chunk_count] or isolated;
    guard.fsi_draws +|= 1;
    guard.max_scissor_pixels = @max(guard.max_scissor_pixels, pixels);
    // Four megapixels is more than five of Halo 3's 1152x640 pictures.
    if (pixels > 4 * 1024 * 1024) guard.oversized_scissor_draws +|= 1;
}

pub fn fsiChunkCommandPool(self: anytype, guard: *FsiGuard, device: abi.Device) ?abi.CommandPool {
    if (guard.command_pool != 0) return guard.command_pool;
    if (guard.command_pool_failed) return null;
    const create = self.real_vulkan.fn_ptrs.create_command_pool orelse {
        guard.command_pool_failed = true;
        return null;
    };
    const info = abi.CommandPoolCreateInfo{
        .flags = abi.COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queue_family_index = self.real_vulkan.graphics_queue_family_index,
    };
    var pool: abi.CommandPool = 0;
    const result = create(device, &info, null, &pool);
    if (result != abi.SUCCESS or pool == 0) {
        guard.command_pool_failed = true;
        machoCapturePrint("macho-processor: VULKAN FSI GUARD: chunk command pool creation failed VkResult={d}; FSI command buffers stay whole\n", .{result});
        return null;
    }
    guard.command_pool = pool;
    return pool;
}

pub fn fsiAcquireChunk(self: anytype, guard: *FsiGuard, device: abi.Device) ?u64 {
    if (guard.chunk_pool.acquire(guard.monitor.completedSerial())) |chunk| return chunk;
    if (!guard.chunk_pool.canGrow()) return null;
    const pool = self.fsiChunkCommandPool(guard, device) orelse return null;
    const allocate = self.real_vulkan.fn_ptrs.allocate_command_buffers orelse return null;
    const info = abi.CommandBufferAllocateInfo{ .command_pool = pool, .level = abi.COMMAND_BUFFER_LEVEL_PRIMARY, .command_buffer_count = 1 };
    var buffers = [_]abi.CommandBuffer{null};
    if (allocate(device, &info, &buffers) != abi.SUCCESS) return null;
    const handle = @intFromPtr(buffers[0] orelse return null);
    if (!guard.chunk_pool.add(handle)) return null;
    return handle;
}

pub fn fsiSplitRecording(self: anytype, guard: *FsiGuard, recording: *fsi_chain.Recording) bool {
    const device = self.real_vulkan.device orelse return false;
    const fns = &self.real_vulkan.fn_ptrs;
    const end_pass = fns.cmd_end_render_pass orelse return false;
    const begin_pass = fns.cmd_begin_render_pass orelse return false;
    const end_buffer = fns.end_command_buffer orelse return false;
    const begin_buffer = fns.begin_command_buffer orelse return false;
    const reset_buffer = fns.reset_command_buffer orelse return false;
    // The async worker owns admitted bind/draw calls, including calls
    // targeting this recording. Complete them before any split operation
    // touches the command pool or changes the active subpass. The drain
    // has a completion-watermark fast path, so this boundary does not
    // take a second worker stats lock when all prior commands are done.
    // In particular, no worker draw may overlap vkCmdEndRenderPass,
    // vkEndCommandBuffer, or the continuation's begin/replay sequence.
    if (self.drainAsyncVulkanCommandsIfPending()) guard.split_worker_drains +|= 1;
    guard.serialized_split_boundaries +|= 1;
    const chunk = self.fsiAcquireChunk(guard, device) orelse return false;
    const old: abi.CommandBuffer = @ptrFromInt(recording.target());
    const next: abi.CommandBuffer = @ptrFromInt(chunk);
    // Preflight the replay before touching the guest's live command
    // buffer. If the driver entry point is absent, the original remains
    // intact and we can safely forward it whole.
    var ops = FsiReplayOps{ .fns = fns, .command_buffer = next };
    if (!ops.supports(&recording.shadow)) {
        recording.noteBlock(.replay_function_missing);
        guard.chunk_pool.release(chunk);
        machoCapturePrint("macho-processor: VULKAN FSI GUARD: split refused guest=0x{x} reason=replay_function_missing; the original command buffer remains open and will be forwarded whole\n", .{recording.guest});
        return false;
    }
    const reset = reset_buffer(next, 0);
    if (reset != abi.SUCCESS) {
        recording.noteBlock(.continuation_reset_failed);
        guard.chunk_pool.discard(chunk);
        machoCapturePrint("macho-processor: VULKAN FSI GUARD: split refused guest=0x{x} chunk={d} reason=vkResetCommandBuffer VkResult={d}; original command buffer remains open and will be forwarded whole\n", .{ recording.guest, recording.chunk_count + 1, reset });
        return false;
    }
    // Beginning the continuation first means an ordinary begin failure
    // leaves the guest's original command buffer untouched and usable.
    // RENDER_PASS_CONTINUE is a secondary-buffer flag; this is primary.
    const begin_info = abi.CommandBufferBeginInfo{ .flags = recording.usage_flags & ~@as(u32, 0x2) };
    const begun = begin_buffer(next, &begin_info);
    if (begun != abi.SUCCESS) {
        recording.noteBlock(.continuation_begin_failed);
        guard.chunk_pool.discard(chunk);
        machoCapturePrint("macho-processor: VULKAN FSI GUARD: split refused guest=0x{x} chunk={d} reason=vkBeginCommandBuffer VkResult={d}; original command buffer remains open and will be forwarded whole\n", .{ recording.guest, recording.chunk_count + 1, begun });
        return false;
    }
    // Close synchronously after the drain above. MoltenVK's indexed-draw
    // encoder assumes its subpass state remains live through encoding;
    // queueing this close pair left that lifetime concurrent with FSI draw
    // recording on the worker.
    end_pass(old);
    const ended = end_buffer(old);
    if (ended != abi.SUCCESS) {
        _ = end_buffer(next);
        guard.chunk_pool.discard(chunk);
        recording.fail();
        machoCapturePrint("macho-processor: VULKAN FSI GUARD: split failed guest=0x{x} chunk={d} reason=vkEndCommandBuffer VkResult={d}; the recording is poisoned and will be rejected at end/submit\n", .{ recording.guest, recording.chunk_count + 1, ended });
        return false;
    }
    const pass_begin = abi.RenderPassBeginInfo{
        .render_pass = recording.pass.render_pass,
        .framebuffer = recording.pass.framebuffer,
        .render_area = recording.pass.render_area,
    };
    begin_pass(next, &pass_begin, fsi_chain.subpass_contents_inline);
    recording.shadow.replay(&ops);
    guard.replay_missing_functions +|= ops.missing;
    if (ops.missing != 0) {
        // supports() ran before the boundary and the Vulkan entry points
        // are device-stable. Keep this as a hard failure if that contract
        // is violated anyway; never claim a partial state replay worked.
        end_pass(next);
        _ = end_buffer(next);
        guard.chunk_pool.discard(chunk);
        recording.fail();
        machoCapturePrint("macho-processor: VULKAN FSI GUARD: split failed guest=0x{x} reason=replay_function_missing after preflight={d}; the recording is poisoned and will be rejected at end/submit\n", .{ recording.guest, ops.missing });
        return false;
    }
    recording.commitSplit(chunk);
    return true;
}

pub fn fsiSubmitNeedsExpansion(self: anytype, synthetics: *const [8][256]u64, counts: *const [8]u32, submit_count: u32) bool {
    _ = self.fsiArmedGuard() orelse return false;
    for (0..submit_count) |batch| {
        for (synthetics[batch][0..counts[batch]]) |guest| {
            const recording = self.fsiRecording(guest) orelse continue;
            if (recording.failed or recording.chunk_count != 0 or recording.fsi_draws != 0) return true;
        }
    }
    return false;
}

pub fn fsiStartMonitor(self: anytype, guard: *FsiGuard, device: abi.Device) bool {
    if (guard.monitor_started) return true;
    if (guard.monitor_start_failed or !self.fsi_guard_watcher_thread) return false;
    guard.fence_context = .{ .device = device, .wait = self.real_vulkan.fn_ptrs.wait_for_fences, .reset = self.real_vulkan.fn_ptrs.reset_fences };
    if (guard.fence_context.wait == null or guard.fence_context.reset == null or self.real_vulkan.fn_ptrs.create_fence == null) {
        guard.monitor_start_failed = true;
        return false;
    }
    guard.monitor.start(.{ .context = @ptrCast(&guard.fence_context), .wait = fsiFenceWait, .reset = fsiFenceReset, .now = fsiFenceNow }, fsiWatcherReport) catch {
        guard.monitor_start_failed = true;
        machoCapturePrint("macho-processor: VULKAN FSI GUARD: GPU timing watcher could not start; the bridge will refuse FSI queue submission rather than hand unbounded, untimed work to MoltenVK\n", .{});
        return false;
    };
    guard.monitor_started = true;
    machoCapturePrint("macho-processor: VULKAN FSI GUARD: GPU timing watcher started; every FSI chunk is now timed from its fence\n", .{});
    return true;
}

pub fn fsiTimingFence(self: anytype, guard: *FsiGuard, device: abi.Device) u64 {
    if (!self.fsiStartMonitor(guard, device)) return 0;
    if (guard.monitor.takeFence()) |fence| return fence;
    const create = self.real_vulkan.fn_ptrs.create_fence orelse return 0;
    const info = abi.FenceCreateInfo{};
    var fence: abi.Fence = 0;
    if (create(device, &info, null, &fence) != abi.SUCCESS or fence == 0) {
        guard.timing_fence_failures +|= 1;
        if (guard.timing_fence_failures <= 4 or (guard.timing_fence_failures & (guard.timing_fence_failures - 1)) == 0) machoCapturePrint(
            "macho-processor: VULKAN FSI GUARD: timing fence creation failed count={d}; this segment will not be submitted without timing/queue-depth accounting\n",
            .{guard.timing_fence_failures},
        );
        return 0;
    }
    guard.timing_fences_created +|= 1;
    guard.monitor.noteFenceCreated();
    return fence;
}

pub fn fsiWaitForRoom(state: anytype, monitor: *fsi_timing.Monitor, incoming_submit_infos: usize, isolated: bool) fsi_timing.RoomResult {
    const WaitContext = struct {
        monitor: *fsi_timing.Monitor,
        incoming_submit_infos: usize,
        isolated: bool,
        result: fsi_timing.RoomResult = .available,

        fn wait(context: *@This()) void {
            context.result = context.monitor.waitForIsolatedSubmitInfos(fsi_timing.max_in_flight_segments, context.incoming_submit_infos, context.isolated);
        }
    };
    var context = WaitContext{ .monitor = monitor, .incoming_submit_infos = incoming_submit_infos, .isolated = isolated };
    if (comptime @hasDecl(@TypeOf(state.*), "tryWithWindowsRuntimeLockReleasedForVulkanQueueWait")) {
        if (!state.tryWithWindowsRuntimeLockReleasedForVulkanQueueWait(&context, WaitContext.wait)) return .runtime_lock_pinned;
    } else {
        WaitContext.wait(&context);
    }
    return context.result;
}

pub fn fsiSubmitSegmentGroup(
    self: anytype,
    guard: *FsiGuard,
    queue: abi.Queue,
    submit_fn: abi.PfnQueueSubmit,
    device: abi.Device,
    segments: []const FsiSegment,
    segment_buffers: []const [fsi_segment_command_capacity]abi.CommandBuffer,
    last: bool,
    guest_fence: u64,
    queue_submit: u64,
    runtime_state: anytype,
) abi.Result {
    if (segments.len == 0 or segments.len > fsi_timing.max_submit_infos_per_timing_group or segments.len != segment_buffers.len) return abi.ERROR_INITIALIZATION_FAILED;
    if (!guard.monitor_started) return abi.ERROR_INITIALIZATION_FAILED;
    // Keep a stable host copy across monitor backpressure. Queue submits
    // hold the Vulkan queue gate while waiting, so no later queue call can
    // overtake this segment; the host-only monitor wait yields the guest
    // runtime mutex so CPU workers keep making progress.
    var command_buffer_snapshots: [fsi_timing.max_submit_infos_per_timing_group][fsi_segment_command_capacity]abi.CommandBuffer = undefined;
    var infos: [fsi_timing.max_submit_infos_per_timing_group]abi.SubmitInfo = undefined;
    var combined = FsiSegment{};
    for (segments, segment_buffers, 0..) |segment, buffers, index| {
        combined.isolated = combined.isolated or segment.isolated;
        command_buffer_snapshots[index] = buffers;
        infos[index] = .{
            .wait_semaphore_count = segment.wait_count,
            .wait_semaphores = segment.wait_semaphores,
            .wait_dst_stage_mask = segment.wait_stages,
            .command_buffer_count = segment.command_count,
            .command_buffers = if (segment.command_count == 0) null else &command_buffer_snapshots[index],
            .signal_semaphore_count = segment.signal_count,
            .signal_semaphores = segment.signal_semaphores,
        };
        combined.draws +|= segment.draws;
        combined.scissor_pixels +|= segment.scissor_pixels;
        combined.max_draw_scissor_pixels = @max(combined.max_draw_scissor_pixels, segment.max_draw_scissor_pixels);
        combined.sample_work +|= segment.sample_work;
        combined.max_draw_sample_work = @max(combined.max_draw_sample_work, segment.max_draw_sample_work);
        if (combined.guest_command_buffer == 0 and segment.guest_command_buffer != 0) {
            combined.guest_command_buffer = segment.guest_command_buffer;
            combined.segment_in_guest = segment.segment_in_guest;
            combined.guest_segments = segment.guest_segments;
            combined.first_pipeline = segment.first_pipeline;
        }
        if (segment.last_pipeline != 0) combined.last_pipeline = segment.last_pipeline;
    }
    switch (fsiWaitForRoom(runtime_state, &guard.monitor, segments.len, combined.isolated)) {
        .available => {},
        .slow_chunk => {
            guard.slow_chunk_submit_aborts +|= 1;
            if (guard.slow_chunk_submit_aborts == 1 or (guard.slow_chunk_submit_aborts & (guard.slow_chunk_submit_aborts - 1)) == 0) {
                const stats = guard.monitor.stats();
                machoCapturePrint("macho-processor: VULKAN FSI GUARD: software_guard_device_loss=true reason=pending_without_live_watcher; refusing FSI queue submission because the monitor cannot prove outstanding completion; aborts={d} outstanding_groups={d} outstanding_metal_command_buffers={d} worst_completed_group_ms={d} worst_group_draws={d} worst_sample_work={d}; a live watcher instead parks the submitter until successful completion, actual fence failure or shutdown\n", .{ guard.slow_chunk_submit_aborts, stats.outstanding, stats.outstanding_submit_infos, stats.budget.max_chunk_ns / 1_000_000, stats.budget.max_chunk_draws, stats.budget.max_chunk_sample_work });
            }
            // This is a monitor failure, not ordinary slow completion:
            // the wait could not continue because no watcher is live.
            // Never submit unobserved work or invite a generic retry.
            return abi.ERROR_DEVICE_LOST;
        },
        .runtime_lock_pinned => {
            machoCapturePrint("macho-processor: VULKAN FSI GUARD: room wait refused because the guest runtime lock is pinned; no monitor wait or FSI submission was issued, and this is not a Vulkan device-loss report\n", .{});
            return abi.ERROR_INITIALIZATION_FAILED;
        },
        .failed, .stopped => return abi.ERROR_DEVICE_LOST,
    }
    // Device teardown can run while the dispatch-only lock is yielded.
    // Shutdown wakes the monitor waiter; refuse to touch a stopped guard
    // after reacquiring the runtime lock.
    if (!guard.monitor_started or self.real_vulkan.device != device or self.real_vulkan.device_lost) {
        return abi.ERROR_DEVICE_LOST;
    }
    const timing_fence = self.fsiTimingFence(guard, device);
    if (timing_fence == 0) return abi.ERROR_OUT_OF_HOST_MEMORY;
    const submit_ns = transport_timing.nowNs();
    const result = submit_fn(queue, @intCast(segments.len), &infos, timing_fence);
    if (result != abi.SUCCESS) {
        guard.monitor.returnFence(timing_fence);
        machoCapturePrint(
            "macho-processor: VULKAN FSI SUBMIT FAILED: queue_submit={d} VkResult={d} submit_infos={d} guest_command_buffer=0x{x} first_segment={d}/{d} draws={d} scissor_pixel_work={d} max_draw_pixels={d} pipelines(first/last)=0x{x}/0x{x} timing_fence=0x{x} guest_fence=0x{x}; failure happened while submitting this bounded FSI segment group, before the guest submit was accepted\n",
            .{ queue_submit, result, segments.len, combined.guest_command_buffer, combined.segment_in_guest, combined.guest_segments, combined.draws, combined.scissor_pixels, combined.max_draw_scissor_pixels, combined.first_pipeline, combined.last_pipeline, timing_fence, guest_fence },
        );
        return result;
    }
    guard.driver_queue_submit_calls +|= 1;
    guard.driver_submit_infos +|= segments.len;
    if (segments.len > 1) guard.coalesced_submit_groups +|= 1;
    guard.segments_submitted +|= segments.len;
    const tracked = guard.monitor.trackSubmitted(.{
        .isolated = combined.isolated,
        .fence = timing_fence,
        .submit_ns = submit_ns,
        .draws = combined.draws,
        .scissor_pixels = combined.scissor_pixels,
        .max_draw_scissor_pixels = combined.max_draw_scissor_pixels,
        .sample_work = combined.sample_work,
        .max_draw_sample_work = combined.max_draw_sample_work,
        .guest_command_buffer = combined.guest_command_buffer,
        .segment = combined.segment_in_guest,
        .segments = combined.guest_segments,
        .queue_submit = queue_submit,
        .submit_infos = @intCast(segments.len),
        .first_pipeline_hash = combined.first_pipeline,
        .last_pipeline_hash = combined.last_pipeline,
    });
    for (segment_buffers, 0..) |buffers, segment_index| {
        for (buffers[0..segments[segment_index].command_count]) |buffer| {
            if (buffer) |handle| guard.chunk_pool.noteSubmitted(@intFromPtr(handle), tracked.serial);
        }
    }
    if (tracked.failed) return abi.ERROR_DEVICE_LOST;
    // Preserve the guest fence's completion point. The queue-order fence
    // follows the timed segment, while the timing fence already tracks
    // the actual work and therefore cannot be lost on an empty-submit
    // failure.
    if (last and guest_fence != 0) {
        const fence_result = submit_fn(queue, 0, null, guest_fence);
        if (fence_result != abi.SUCCESS) {
            machoCapturePrint("macho-processor: VULKAN FSI GUEST FENCE SUBMIT FAILED: queue_submit={d} VkResult={d} guest_fence=0x{x} after_last_segment={d}/{d}; timed FSI work was accepted, but Xenia's completion fence was not\n", .{ queue_submit, fence_result, guest_fence, combined.segment_in_guest + @as(u16, @intCast(segments.len)) - 1, combined.guest_segments });
            return fence_result;
        }
        guard.driver_queue_submit_calls +|= 1;
    }
    return abi.SUCCESS;
}

pub fn fsiAdvanceSegmentSlots(
    self: anytype,
    guard: *FsiGuard,
    queue: abi.Queue,
    submit_fn: abi.PfnQueueSubmit,
    device: abi.Device,
    segments: *[2]FsiSegment,
    segment_buffers: *[2][fsi_segment_command_capacity]abi.CommandBuffer,
    pending: *?usize,
    current: usize,
    queue_submit: u64,
    runtime_state: anytype,
) abi.Result {
    if (pending.*) |older| {
        if (fsiCanCoalesceSegments(segments[older], segments[current])) {
            const group = [_]FsiSegment{ segments[older], segments[current] };
            const buffers = [_][fsi_segment_command_capacity]abi.CommandBuffer{ segment_buffers[older], segment_buffers[current] };
            const result = self.fsiSubmitSegmentGroup(guard, queue, submit_fn, device, &group, &buffers, false, 0, queue_submit, runtime_state);
            if (result != abi.SUCCESS) return result;
            pending.* = null;
        } else {
            const group = [_]FsiSegment{segments[older]};
            const buffers = [_][fsi_segment_command_capacity]abi.CommandBuffer{segment_buffers[older]};
            const result = self.fsiSubmitSegmentGroup(guard, queue, submit_fn, device, &group, &buffers, false, 0, queue_submit, runtime_state);
            if (result != abi.SUCCESS) return result;
            pending.* = current;
        }
    } else {
        pending.* = current;
    }
    return abi.SUCCESS;
}

pub fn fsiSubmitExpanded(
    self: anytype,
    queue: abi.Queue,
    submit_fn: abi.PfnQueueSubmit,
    real_submits: *const [8]abi.SubmitInfo,
    synthetics: *const [8][256]u64,
    counts: *const [8]u32,
    submit_count: u32,
    guest_fence: u64,
    runtime_state: anytype,
) abi.Result {
    const guard = self.fsi_guard.?;
    const device = self.real_vulkan.device;
    for (0..submit_count) |batch| {
        for (synthetics[batch][0..counts[batch]]) |guest| {
            if (self.fsiRecording(guest)) |recording| {
                if (recording.failed) {
                    machoCapturePrint("macho-processor: VULKAN FSI GUARD: vkQueueSubmit refused guest_command_buffer=0x{x}; a continuation boundary failed and the recording is not executable\n", .{guest});
                    return abi.ERROR_INITIALIZATION_FAILED;
                }
            }
        }
    }
    // A one-segment frame also needs a live watcher. Do not silently fall
    // back to the unbounded Vulkan path if timing cannot be established.
    if (!self.fsiStartMonitor(guard, device)) return abi.ERROR_INITIALIZATION_FAILED;
    const queue_submit = self.vulkan_real_queue_submits + 1;
    var current: usize = 0;
    var pending: ?usize = null;
    var produced: u64 = 0;
    // Per-submit stack workspace keeps segment construction bounded and
    // prevents one guest submit from reusing another submit's scratch.
    var segments: [2]FsiSegment = .{ .{}, .{} };
    var segment_buffers: [2][fsi_segment_command_capacity]abi.CommandBuffer = [_][fsi_segment_command_capacity]abi.CommandBuffer{[_]abi.CommandBuffer{null} ** fsi_segment_command_capacity} ** 2;
    for (0..submit_count) |batch| {
        const info = real_submits[batch];
        if (batch != 0) {
            const result = self.fsiAdvanceSegmentSlots(guard, queue, submit_fn, device, &segments, &segment_buffers, &pending, current, queue_submit, runtime_state);
            if (result != abi.SUCCESS) return result;
            current = 1 - current;
            segments[current] = .{};
            produced += 1;
        }
        segments[current].wait_count = info.wait_semaphore_count;
        segments[current].wait_semaphores = info.wait_semaphores;
        segments[current].wait_stages = info.wait_dst_stage_mask;
        for (0..counts[batch]) |index| {
            const guest = synthetics[batch][index];
            const own = if (info.command_buffers) |buffers| buffers[index] else null;
            const recording = self.fsiRecording(guest);
            // Segments: the guest's own buffer, then each chunk.
            const segment_total: usize = if (recording) |entry| entry.chunk_count + 1 else 1;
            for (0..segment_total) |part| {
                if (part != 0) {
                    const result = self.fsiAdvanceSegmentSlots(guard, queue, submit_fn, device, &segments, &segment_buffers, &pending, current, queue_submit, runtime_state);
                    if (result != abi.SUCCESS) return result;
                    current = 1 - current;
                    segments[current] = .{};
                    produced += 1;
                }
                const segment = &segments[current];
                if (segment.command_count == fsi_segment_command_capacity) return abi.ERROR_OUT_OF_HOST_MEMORY;
                const buffer: abi.CommandBuffer = if (part == 0) own else @ptrFromInt(recording.?.chunks[part - 1]);
                segment_buffers[current][segment.command_count] = buffer;
                segment.command_count += 1;
                if (recording) |entry| {
                    segment.draws +|= entry.segment_fsi_draws[part];
                    segment.scissor_pixels +|= entry.segment_scissor_pixels[part];
                    segment.max_draw_scissor_pixels = @max(segment.max_draw_scissor_pixels, entry.segment_max_draw_pixels[part]);
                    segment.sample_work +|= entry.segment_sample_work[part];
                    segment.max_draw_sample_work = @max(segment.max_draw_sample_work, entry.segment_max_draw_sample_work[part]);
                    segment.isolated = segment.isolated or entry.segment_isolated[part];
                    if (entry.segment_fsi_draws[part] != 0) {
                        if (segment.guest_command_buffer == 0) {
                            segment.guest_command_buffer = guest;
                            segment.segment_in_guest = @intCast(part);
                            segment.guest_segments = @intCast(segment_total);
                            segment.first_pipeline = entry.segment_first_pipeline[part];
                        }
                        segment.last_pipeline = entry.segment_last_pipeline[part];
                    }
                }
            }
        }
        segments[current].signal_count = info.signal_semaphore_count;
        segments[current].signal_semaphores = info.signal_semaphores;
    }
    if (pending) |slot| {
        if (fsiCanCoalesceSegments(segments[slot], segments[current])) {
            const group = [_]FsiSegment{ segments[slot], segments[current] };
            const buffers = [_][fsi_segment_command_capacity]abi.CommandBuffer{ segment_buffers[slot], segment_buffers[current] };
            const result = self.fsiSubmitSegmentGroup(guard, queue, submit_fn, device, &group, &buffers, true, guest_fence, queue_submit, runtime_state);
            if (result != abi.SUCCESS) return result;
        } else {
            const group = [_]FsiSegment{segments[slot]};
            const buffers = [_][fsi_segment_command_capacity]abi.CommandBuffer{segment_buffers[slot]};
            const result = self.fsiSubmitSegmentGroup(guard, queue, submit_fn, device, &group, &buffers, false, 0, queue_submit, runtime_state);
            if (result != abi.SUCCESS) return result;
            const last_group = [_]FsiSegment{segments[current]};
            const last_buffers = [_][fsi_segment_command_capacity]abi.CommandBuffer{segment_buffers[current]};
            const last_result = self.fsiSubmitSegmentGroup(guard, queue, submit_fn, device, &last_group, &last_buffers, true, guest_fence, queue_submit, runtime_state);
            if (last_result != abi.SUCCESS) return last_result;
        }
    } else {
        const group = [_]FsiSegment{segments[current]};
        const buffers = [_][fsi_segment_command_capacity]abi.CommandBuffer{segment_buffers[current]};
        const result = self.fsiSubmitSegmentGroup(guard, queue, submit_fn, device, &group, &buffers, true, guest_fence, queue_submit, runtime_state);
        if (result != abi.SUCCESS) return result;
    }
    produced += 1;
    guard.expanded_submits +|= 1;
    guard.max_segments_per_submit = @max(guard.max_segments_per_submit, produced);
    return abi.SUCCESS;
}

pub fn fsiEvidenceEnabled(self: anytype) bool {
    if (self.fsi_evidence_enabled) |enabled| return enabled;
    const raw = std.c.getenv("ROSETTE_FSI_EVIDENCE");
    const enabled = if (raw) |value| std.mem.eql(u8, std.mem.span(value), "1") else false;
    self.fsi_evidence_enabled = enabled;
    if (enabled) machoCapturePrint("macho-processor: VULKAN FSI EVIDENCE: exact guest/native shader modules saved under {s}/vulkan-shaders (256 MiB run limit); all FSI pipeline identities are logged\n", .{captureRunDirectory()});
    return enabled;
}

pub fn fsiSaveShaderEvidence(self: anytype, guest: u64, info: *const marshal.ShaderModuleCreateInfo, version: gpu_vulkan.fsi.evidence.Version) void {
    if (!self.fsiEvidenceEnabled()) return;
    const code = info.code orelse return;
    if (info.code_size % 4 != 0 or info.code_size > gpu_vulkan.fsi.evidence.maximum_module_bytes) return;
    const words: [*]const u32 = @ptrCast(@alignCast(code));
    const result = self.fsi_evidence_writer.save(captureRunDirectory(), guest, words[0 .. info.code_size / 4], version);
    if (result != .saved and self.fsi_evidence_writer.failures + self.fsi_evidence_writer.limits <= 4) machoCapturePrint("macho-processor: VULKAN FSI EVIDENCE: shader save {s} module=0x{x} version={s} bytes={d}; capture evidence is incomplete\n", .{ @tagName(result), guest, @tagName(version), info.code_size });
}

pub fn fsiPrintEscalationContext(self: anytype, guard: *FsiGuard) void {
    guard.escalation_dumps +|= 1;
    if (guard.escalation_dumps > 8) return;
    self.printFsiGuardReport();
    machoCapturePrint(
        "macho-processor: VULKAN FSI WATCHDOG CONTEXT: recent_accepted_submissions={d}; the guest command buffers the slow chunk came from, newest last\n",
        .{self.vulkan_fsi_tracker.recent_submission_count},
    );
    for (0..self.vulkan_fsi_tracker.recent_submission_count) |index| {
        self.printDeviceLossFsiSubmission("watchdog_recent_submission", self.vulkan_fsi_tracker.recentSubmission(index).?);
    }
}

pub fn printFsiGuardReport(self: anytype) void {
    self.printFsiRasterReport();
    const guard = self.fsi_guard orelse return;
    if (!guard.armed) return;
    const stats = guard.monitor.stats();
    const budget = stats.budget;
    const queue_gate = self.vulkan_queue_api_gate.stats();
    machoCapturePrint(
        "macho-processor: VULKAN FSI GUARD: armed=true fsi_draws={d} splits={d} split_failures={d} serialized_split_boundaries={d} worker_drains={d} cap_now={d} latency_ns_per_draw={d} timing_groups_timed={d} completion_ms_per_group(mean/p50/p95/p99/max)={d}/{d}/{d}/{d}/{d} max_group_draws={d} risk_events={d} severe_events={d} emergency={} submissions_paused={} severe_recoveries={d} outstanding_groups(now/max)={d}/{d} outstanding_metal_command_buffers(now/max)={d}/{d} timing_basis=submit_to_fence_observation_upper_bound; latency includes queue wait and CPU observation delay; submit_infos remain distinct Metal command buffers\n",
        .{
            guard.fsi_draws,                   guard.splits,                       guard.split_failures,
            guard.serialized_split_boundaries, guard.split_worker_drains,          guard.monitor.capValue(),
            budget.ns_per_draw,                stats.completed,                    budget.meanChunkNs() / 1_000_000,
            budget.percentileMs(500),          budget.percentileMs(950),           budget.percentileMs(990),
            budget.max_chunk_ns / 1_000_000,   budget.max_chunk_draws,             budget.risk_events,
            budget.severe_events,              budget.emergency,                   stats.submissions_paused,
            stats.severe_recoveries,           stats.outstanding,                  stats.max_outstanding,
            stats.outstanding_submit_infos,    stats.max_outstanding_submit_infos,
        },
    );
    machoCapturePrint(
        "macho-processor: VULKAN FSI GUARD:   submission expanded_submits={d} segments={d} driver_queue_submit_calls={d} driver_submit_infos={d} coalesced_groups={d} max_submit_infos_per_group={d} max_segments_per_submit={d} untimed_segments={d} slow_chunk_submit_aborts={d} chunk_buffers(allocated/reused/exhausted/poisoned)={d}/{d}/{d}/{d} timing_fences(created/failed)={d}/{d} watcher(started/failed)={}/{} replay_missing={d} recordings_overflow={d} fsi_render_passes={d} framebuffer={d}x{d} scissor_pixels(max/over_4M_draws/unscissored_draws)={d}/{d}/{d}; adjacent chunks share the host queue call but remain separate VkSubmitInfo batches and Metal command buffers\n",
        .{
            guard.expanded_submits,     guard.segments_submitted,      guard.driver_queue_submit_calls, guard.driver_submit_infos,       guard.coalesced_submit_groups, fsi_timing.max_submit_infos_per_timing_group, guard.max_segments_per_submit, guard.untimed_segments,                     guard.slow_chunk_submit_aborts,
            guard.chunk_pool.allocated, guard.chunk_pool.reuses,       guard.chunk_pool.exhausted,      guard.chunk_pool.poisoned_count, guard.timing_fences_created,   guard.timing_fence_failures,                  guard.monitor_started,         stats.failed or guard.monitor_start_failed, guard.replay_missing_functions,
            guard.recording_overflow,   guard.xenia_fsi_render_passes, guard.framebuffer_width,         guard.framebuffer_height,        guard.max_scissor_pixels,      guard.oversized_scissor_draws,                guard.unscissored_draws,
        },
    );
    machoCapturePrint(
        "macho-processor: METAL COMMAND BUFFER POLICY: target_ms={d} risk_ms={d} severe_ms={d} hard_draw_cap={d} adaptive_sample_work_cap={d} ns_per_sample={d} max_group_sample_work={d} max_single_draw_sample_work={d} max_in_flight_metal_command_buffers={d} max_in_flight_timing_groups={d} room_waits={d} room_wait_ms={d} room_wait_max_ms={d} shader_bounds_verified={} hard_sample_work_cap={d}; room_waits counts condition-variable sleeps, not separate queue submissions\n",
        .{ budget.config.target_chunk_ns / 1_000_000, budget.config.risk_ns / 1_000_000, budget.config.severe_ns / 1_000_000, budget.config.max_draws, guard.monitor.sampleWorkCapValue(), budget.ns_per_sample, budget.max_chunk_sample_work, budget.max_draw_sample_work, fsi_timing.max_in_flight_segments, fsi_timing.max_in_flight_timing_groups, stats.room_waits, stats.room_wait_ns / 1_000_000, stats.max_room_wait_ns / 1_000_000, budget.shader_bounds_verified, budget.config.max_sample_work },
    );
    machoCapturePrint(
        "macho-processor: VULKAN QUEUE API GATE: acquisitions={d} contended={d} waits={d} wait_ms={d} wait_max_ms={d} pinned_refusals={d}; this serializes host queue calls while a blocked submit yields the guest-runtime mutex\n",
        .{ queue_gate.acquisitions, queue_gate.contended, queue_gate.waits, queue_gate.wait_ns / 1_000_000, queue_gate.max_wait_ns / 1_000_000, queue_gate.wait_refusals },
    );
    machoCapturePrint(
        "macho-processor: VULKAN FSI FENCE ROUTE: ready_checks={d} ready_completions={d}; a zero-time fence wait can retire an already completed FIFO head on the submitter; pending fences keep watcher timing and queue backpressure\n",
        .{ stats.ready_checks, stats.ready_completions },
    );
    machoCapturePrint(
        "macho-processor: VULKAN FSI CPU ROUTE: small_chunk_sync={} synchronous_commands={d} recovery_fast_groups={d} recovery_work_cap={d} recovery_growths={d}; minimum draw-cap recordings bypass worker handoffs after draining older commands; recovery work never exceeds {d}\n",
        .{ self.fsi_small_chunk_sync, self.fsi_small_chunk_sync_commands, budget.recovery_fast_groups, budget.recovery_work_cap, budget.recovery_growths, rosette_gpu.metal.command_buffer_policy.fsi.recovery_max_sample_work },
    );
    machoCapturePrint(
        "macho-processor: VULKAN FSI GUARD SAFETY: max_chain_segments={d} recording_aborts={d} withheld_over_budget_draws={d}; continuation/replay failures and the hard chain ceiling are refused; structurally unsplittable guest recordings retain whole-buffer semantics and are explicitly reported as potentially over budget\n",
        .{ fsi_chain.max_chunks_per_command_buffer + 1, guard.recording_aborts, guard.aborted_fsi_draws },
    );
    var any_blocked = false;
    for (guard.blocked_splits) |count| any_blocked = any_blocked or count != 0;
    if (!any_blocked) return;
    inline for (@typeInfo(fsi_chain.Block).@"enum".fields) |field| {
        const count = guard.blocked_splits[field.value];
        if (count != 0) machoCapturePrint(
            "macho-processor: VULKAN FSI GUARD:   split_blocked reason={s} times={d}; an unsplittable recording retains Vulkan whole-buffer semantics and may exceed the adaptive budget; chunk_capacity is the hard chain limit and is refused before submission\n",
            .{ field.name, count },
        );
    }
}

pub fn fsiGuardShutdown(self: anytype) void {
    const guard = self.fsi_guard orelse return;
    guard.monitor.stop();
    const device = self.real_vulkan.device;
    const usable = device != null and !self.real_vulkan.device_lost;
    var fences: [fsi_timing.capacity]u64 = undefined;
    const fence_count = guard.monitor.collectFences(&fences);
    if (usable) {
        if (self.real_vulkan.fn_ptrs.destroy_fence) |destroy| {
            for (fences[0..fence_count]) |fence| destroy(device, fence, null);
        }
        if (guard.command_pool != 0) {
            if (self.real_vulkan.fn_ptrs.destroy_command_pool) |destroy| destroy(device, guard.command_pool, null);
        }
    }
    self.printFsiGuardReport();
    guard.* = .{};
}

pub fn noteFsiDraw(self: anytype, command_buffer: u64, kind: fsi_diagnostics.DrawKind) void {
    self.noteFsiDrawWithParameters(command_buffer, kind, .{});
}

pub fn noteFsiDrawWithParameters(
    self: anytype,
    command_buffer: u64,
    kind: fsi_diagnostics.DrawKind,
    parameters: fsi_diagnostics.DrawParameters,
) void {
    if (self.vulkan_fsi_tracker.noteDrawWithParameters(command_buffer, kind, parameters)) |draw| {
        if (sparseVulkanSuccessLog(draw.draw_ordinal)) machoCapturePrint(
            "macho-processor: Vulkan FSI DRAW: ordinal={d} kind={s} command_buffer=0x{x} pipeline_real=0x{x} module_id={d} shader_hash=0x{x} pipeline_hash=0x{x} stage_flags=0x{x} target_image=0x{x} target_source={s} args_valid={} elements={d} instances={d} first_element={d} vertex_offset={d} first_instance={d} command_buffer_fsi_draws={d}; identifies an interlock pipeline command actually recorded, while the accepted-submit record distinguishes recorded work from work handed to MoltenVK\n",
            .{ draw.draw_ordinal, @tagName(draw.kind), draw.command_buffer, draw.pipeline_real, draw.module_id, draw.shader_hash, draw.pipeline_hash, draw.stage_flags, draw.target_image, @tagName(draw.target_source), draw.parameters.valid, draw.parameters.element_count, draw.parameters.instance_count, draw.parameters.first_element, draw.parameters.vertex_offset, draw.parameters.first_instance, draw.command_buffer_draw_ordinal },
        );
    }
}

pub fn noteGraphicsDrawState(
    self: anytype,
    command_buffer: u64,
    kind: []const u8,
    vertex_count: u64,
    instance_count: u64,
    first_vertex_or_index: u64,
    auxiliary: u64,
    first_instance: u64,
) void {
    const direct = std.mem.eql(u8, kind, "draw");
    const parameters = fsi_diagnostics.DrawParameters{
        .valid = true,
        .element_count = vertex_count,
        .instance_count = instance_count,
        .first_element = first_vertex_or_index,
        .vertex_offset = if (direct) 0 else @bitCast(@as(u32, @truncate(auxiliary))),
        .first_instance = first_instance,
    };
    self.noteFsiDrawWithParameters(command_buffer, if (direct) .direct else .indexed, parameters);
    if (!self.graphicsStateTraceEnabled()) return;
    self.graphics_state_trace_draws +|= 1;
    const ordinal = self.graphics_state_trace_draws;
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    const trace = &record.graphics_state;
    const needs_viewport = trace.pipeline_bound and trace.pipeline_dynamic_viewport;
    const needs_scissor = trace.pipeline_bound and trace.pipeline_dynamic_scissor;
    const missing_viewport = needs_viewport and !trace.viewport_valid;
    const missing_scissor = needs_scissor and !trace.scissor_valid;
    if (missing_viewport) self.graphics_state_trace_missing_viewport +|= 1;
    if (missing_scissor) self.graphics_state_trace_missing_scissor +|= 1;
    const viewport_bad = trace.viewport_valid and
        (!std.math.isFinite(trace.viewport.x) or !std.math.isFinite(trace.viewport.y) or
            !std.math.isFinite(trace.viewport.width) or !std.math.isFinite(trace.viewport.height) or
            trace.viewport.width <= 0 or trace.viewport.height == 0 or
            @abs(trace.viewport.width) > 65536 or @abs(trace.viewport.height) > 65536);
    const scissor_bad = trace.scissor_valid and
        (trace.scissor.extent.width == 0 or trace.scissor.extent.height == 0 or
            trace.scissor.offset.x < -65536 or trace.scissor.offset.y < -65536);
    if (viewport_bad) self.graphics_state_trace_bad_viewport +|= 1;
    if (scissor_bad) self.graphics_state_trace_bad_scissor +|= 1;
    const rect_words = trace.rect_push_words;
    const rect_x: f32 = @bitCast(rect_words[0]);
    const rect_y: f32 = @bitCast(rect_words[1]);
    const rect_width: f32 = @bitCast(rect_words[2]);
    const rect_height: f32 = @bitCast(rect_words[3]);
    // A push at offset zero is common for ordinary shader constants.  It
    // is not enough evidence to call those four words a presenter
    // rectangle.  Require either the pipeline contract or the exact
    // four-vertex presenter draw shape before classifying the values.
    const rect_candidate = trace.rect_push_valid and
        (trace.pipeline_guest_output_candidate or
            (vertex_count == 4 and instance_count == 1 and first_vertex_or_index == 0 and first_instance == 0));
    if (rect_candidate)
        self.graphics_state_trace_rect_candidates +|= 1
    else if (trace.rect_push_valid)
        self.graphics_state_trace_rect_non_candidates +|= 1;
    const rect_bad = rect_candidate and
        (!std.math.isFinite(rect_x) or !std.math.isFinite(rect_y) or
            !std.math.isFinite(rect_width) or !std.math.isFinite(rect_height) or
            rect_width <= 0 or rect_height <= 0 or @abs(rect_x) > 8 or @abs(rect_y) > 8 or
            @abs(rect_width) > 8 or @abs(rect_height) > 8);
    if (rect_bad) self.graphics_state_trace_bad_rect +|= 1;
    const topology_mismatch = trace.pipeline_topology_known and rect_candidate and
        ((vertex_count == 4 and trace.pipeline_topology != VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP) or
            (vertex_count == 3 and trace.pipeline_topology != VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST));
    if (topology_mismatch) self.graphics_state_trace_topology_mismatch +|= 1;
    const interesting = vertex_count == 3 or vertex_count == 4 or missing_viewport or missing_scissor or
        viewport_bad or scissor_bad or rect_bad or topology_mismatch;
    if (!interesting) return;
    const sparse = ordinal <= 128 or (ordinal & (ordinal - 1)) == 0;
    if (!sparse) return;
    const descriptor_count = @as(usize, @intCast(record.bound_descriptor_set_count));
    const first_descriptor = if (descriptor_count == 0) 0 else record.bound_descriptor_sets[0].synthetic;
    const topology_name = if (trace.pipeline_topology_known) vulkanTopologyLabel(trace.pipeline_topology) else "unknown";
    self.graphics_state_trace_printed +|= 1;
    machoCapturePrint(
        "macho-processor: Vulkan GRAPHICS STATE DRAW: ordinal={d} kind={s} command_buffer=0x{x} pipeline_guest=0x{x} pipeline_real=0x{x} bind_point={d} topology={d}/{s} stages={d} dynamic_viewport={} dynamic_scissor={} draw={d}/{d}/{d}/{d}/{d} viewport(valid/first/count)={}/{d}/{d} viewport_xywh={d:.3}/{d:.3}/{d:.3}/{d:.3} scissor(valid/first/count)={}/{d}/{d} scissor_xywh={d}/{d}/{d}/{d}\n",
        .{
            ordinal,
            kind,
            command_buffer,
            trace.pipeline_guest,
            trace.pipeline_real,
            trace.pipeline_bind_point,
            trace.pipeline_topology,
            topology_name,
            trace.pipeline_stage_count,
            trace.pipeline_dynamic_viewport,
            trace.pipeline_dynamic_scissor,
            vertex_count,
            instance_count,
            first_vertex_or_index,
            auxiliary,
            first_instance,
            trace.viewport_valid,
            trace.viewport_first,
            trace.viewport_count,
            trace.viewport.x,
            trace.viewport.y,
            trace.viewport.width,
            trace.viewport.height,
            trace.scissor_valid,
            trace.scissor_first,
            trace.scissor_count,
            trace.scissor.offset.x,
            trace.scissor.offset.y,
            trace.scissor.extent.width,
            trace.scissor.extent.height,
        },
    );
    machoCapturePrint(
        "macho-processor: Vulkan GRAPHICS STATE DRAW DETAIL: ordinal={d} command_buffer=0x{x} descriptor_sets={d} first_descriptor=0x{x} push(valid/layout_guest/layout_real/stages/offset/size/hash)={}/0x{x}/0x{x}/0x{x}/{d}/{d}/0x{x} rect(valid/xywh/hash)={}/{d:.3}/{d:.3}/{d:.3}/{d:.3}/0x{x} anomalies(missing_viewport/missing_scissor/bad_viewport/bad_scissor/bad_rect/topology)={}/{}/{}/{}/{}/{}\n",
        .{
            ordinal,
            command_buffer,
            descriptor_count,
            first_descriptor,
            trace.push_constants_valid,
            trace.push_layout_guest,
            trace.push_layout_real,
            trace.push_stage_flags,
            trace.push_offset,
            trace.push_size,
            trace.push_hash,
            trace.rect_push_valid,
            rect_x,
            rect_y,
            rect_width,
            rect_height,
            trace.rect_push_hash,
            missing_viewport,
            missing_scissor,
            viewport_bad,
            scissor_bad,
            rect_bad,
            topology_mismatch,
        },
    );
}

pub fn copyGuestHandleArray(
    self: anytype,
    state: anytype,
    address: u64,
    count: u64,
    destination: []u64,
    kind: GuestHandleKind,
) bool {
    if (count > destination.len) return false;
    if (count != 0 and state.guestMemoryConst(address, count * 8) == null) return false;
    for (0..@as(usize, @intCast(count))) |index| {
        const synthetic = state.read64(address + @as(u64, @intCast(index)) * 8);
        destination[index] = switch (kind) {
            .buffer => self.real_vulkan.realBuffer(synthetic) orelse return false,
            .image => self.real_vulkan.realImage(synthetic) orelse return false,
            .pipeline => self.real_vulkan.realPipeline(synthetic) orelse return false,
            .descriptor_set => self.real_vulkan.realDescriptorSet(synthetic) orelse return false,
            .command_buffer => @intFromPtr(self.real_vulkan.realCommandBuffer(synthetic) orelse return false),
        };
    }
    return true;
}

pub fn copyGuestImageBarriers(self: anytype, state: anytype, address: u64, count: u64, destination: []abi.ImageMemoryBarrier) bool {
    if (!copyGuestStructs(abi.ImageMemoryBarrier, state, address, count, destination)) return false;
    for (destination[0..@as(usize, @intCast(count))]) |*barrier| {
        if (barrier.p_next != null) return false;
        const real_image = self.real_vulkan.realImage(barrier.image) orelse return false;
        barrier.image = real_image;
        barrier.p_next = null;
    }
    return true;
}

pub fn noteVulkanCommandShape(self: anytype, name: []const u8, command_buffer: u64) void {
    var category: []const u8 = "other";
    var counter: *u64 = &self.vulkan_command_other_calls;
    if (std.mem.startsWith(u8, name, "vkCmdBeginRenderPass") or
        std.mem.startsWith(u8, name, "vkCmdBeginRendering"))
    {
        category = "render_begin";
        counter = &self.vulkan_command_render_begin_calls;
    } else if (std.mem.startsWith(u8, name, "vkCmdEndRenderPass") or
        std.mem.startsWith(u8, name, "vkCmdEndRendering"))
    {
        category = "render_end";
        counter = &self.vulkan_command_render_end_calls;
    } else if (std.mem.startsWith(u8, name, "vkCmdDraw")) {
        category = "draw";
        counter = &self.vulkan_command_draw_calls;
    } else if (std.mem.startsWith(u8, name, "vkCmdDispatch")) {
        category = "dispatch";
        counter = &self.vulkan_command_dispatch_calls;
    } else if (std.mem.startsWith(u8, name, "vkCmdClear")) {
        category = "clear";
        counter = &self.vulkan_command_clear_calls;
    } else if (std.mem.startsWith(u8, name, "vkCmdCopy") or
        std.mem.startsWith(u8, name, "vkCmdBlit") or
        std.mem.startsWith(u8, name, "vkCmdResolve"))
    {
        category = "copy_or_resolve";
        counter = &self.vulkan_command_copy_calls;
    }
    counter.* +|= 1;
    if (counter.* == 1) {
        machoCapturePrint(
            "macho-processor: Vulkan command category first seen: category={s} name={s} command_buffer=0x{x}\n",
            .{ category, name, command_buffer },
        );
    }
}

pub fn callNativeVulkanCommand(self: anytype, function: anytype, arguments: std.meta.ArgsTuple(@typeInfo(@TypeOf(function)).pointer.child)) void {
    // All other Vulkan entry points share the same ordering domain as the
    // commands submitted to the worker. Finish earlier queued commands
    // before making a synchronous driver call.
    self.drainAsyncVulkanCommands();
    @call(.auto, function, arguments);
    self.vulkan_real_command_calls +|= 1;
}

pub fn asyncVulkanWorker(self: anytype) ?*async_vulkan_command.Worker {
    if (!self.vulkan_async_command_worker_decided) {
        self.vulkan_async_command_worker_decided = true;
        var enabled = builtin.os.tag == .macos and !builtin.is_test;
        if (std.c.getenv("ROSETTE_VULKAN_COMMAND_WORKER")) |raw| {
            const value = std.mem.span(raw);
            if (std.mem.eql(u8, value, "0") or std.ascii.eqlIgnoreCase(value, "off") or std.ascii.eqlIgnoreCase(value, "false")) {
                enabled = false;
            } else if (std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "on") or std.ascii.eqlIgnoreCase(value, "true")) {
                enabled = builtin.os.tag == .macos and !builtin.is_test;
            }
        }
        self.vulkan_async_command_worker_enabled = enabled;
        machoCapturePrint(
            "macho-processor: Vulkan hybrid command worker: enabled={} default=macOS production only; set ROSETTE_VULKAN_COMMAND_WORKER=0 to disable; FIFO pointer-free commands only, barriers drain before all other Vulkan calls\n",
            .{enabled},
        );
    }
    if (!self.vulkan_async_command_worker_enabled) return null;
    if (self.vulkan_async_command_worker) |worker| return worker;

    const worker = std.heap.page_allocator.create(async_vulkan_command.Worker) catch {
        self.vulkan_async_command_worker_enabled = false;
        machoCapturePrint("macho-processor: Vulkan hybrid command worker unavailable: host allocation failed; continuing synchronously\n", .{});
        return null;
    };
    worker.* = .{};
    worker.start() catch |err| {
        std.heap.page_allocator.destroy(worker);
        self.vulkan_async_command_worker_enabled = false;
        machoCapturePrint(
            "macho-processor: Vulkan hybrid command worker unavailable: host thread start failed ({s}); continuing synchronously\n",
            .{@errorName(err)},
        );
        return null;
    };
    self.vulkan_async_command_worker = worker;
    return worker;
}

pub fn queueAsyncVulkanCommand(self: anytype, job: async_vulkan_command.Job) bool {
    if (self.fsi_small_chunk_sync) {
        if (self.fsiArmedGuard()) |guard| {
            if (guard.monitor.capValue() <= rosette_gpu.metal.command_buffer_policy.fsi.min_draws) {
                // The ordinary synchronous call site drains all older
                // jobs first. Avoid a wake/drain round trip for the tiny
                // post-risk recordings without changing command order.
                self.fsi_small_chunk_sync_commands +|= 1;
                return false;
            }
        }
    }
    const worker = self.asyncVulkanWorker() orelse return false;
    return switch (worker.trySubmit(job)) {
        .queued => blk: {
            // This is an admission count: the worker owns a copy of every
            // scalar argument and executes it before the next barrier.
            self.vulkan_real_command_calls +|= 1;
            break :blk true;
        },
        .full => blk: {
            // The call site executes synchronously after
            // callNativeVulkanCommand drains the earlier sequence range.
            self.vulkan_async_queue_saturated_fallbacks +|= 1;
            break :blk false;
        },
        .stopped => blk: {
            self.vulkan_async_worker_stopped_fallbacks +|= 1;
            break :blk false;
        },
    };
}

pub fn drainAsyncVulkanCommands(self: anytype) void {
    _ = self.drainAsyncVulkanCommandsIfPending();
}

pub fn drainAsyncVulkanCommandsIfPending(self: anytype) bool {
    if (self.vulkan_async_command_worker) |worker| {
        const watermark = worker.checkpoint();
        if (worker.completedThrough(watermark)) return false;
        self.vulkan_async_command_barriers +|= 1;
        worker.drainThrough(watermark);
        return true;
    }
    return false;
}

pub fn stopAsyncVulkanCommandWorker(self: anytype) void {
    const worker = self.vulkan_async_command_worker orelse return;
    worker.deinit();
    std.heap.page_allocator.destroy(worker);
    self.vulkan_async_command_worker = null;
}

pub fn noteVulkanCommandRefusal(self: anytype, source_line: u32) void {
    self.vulkan_command_refusal_line = source_line;
}

pub fn nativeVulkanCommandFunctionAvailable(self: anytype, name: []const u8) bool {
    @setEvalBranchQuota(5000);
    const fields = [_]struct { name: []const u8, field: []const u8 }{
        .{ .name = "vkCmdBeginConditionalRenderingEXT", .field = "cmd_begin_conditional_rendering" },
        .{ .name = "vkCmdBeginQuery", .field = "cmd_begin_query" },
        .{ .name = "vkCmdBeginRendering", .field = "cmd_begin_rendering" },
        .{ .name = "vkCmdBeginRenderingKHR", .field = "cmd_begin_rendering" },
        .{ .name = "vkCmdBeginRenderPass", .field = "cmd_begin_render_pass" },
        .{ .name = "vkCmdBeginRenderPass2", .field = "cmd_begin_render_pass2" },
        .{ .name = "vkCmdBeginRenderPass2KHR", .field = "cmd_begin_render_pass2" },
        .{ .name = "vkCmdBindDescriptorSets", .field = "cmd_bind_descriptor_sets" },
        .{ .name = "vkCmdBindIndexBuffer", .field = "cmd_bind_index_buffer" },
        .{ .name = "vkCmdBindPipeline", .field = "cmd_bind_pipeline" },
        .{ .name = "vkCmdBindVertexBuffers", .field = "cmd_bind_vertex_buffers" },
        .{ .name = "vkCmdBlitImage", .field = "cmd_blit_image" },
        .{ .name = "vkCmdClearAttachments", .field = "cmd_clear_attachments" },
        .{ .name = "vkCmdClearColorImage", .field = "cmd_clear_color_image" },
        .{ .name = "vkCmdClearDepthStencilImage", .field = "cmd_clear_depth_stencil_image" },
        .{ .name = "vkCmdCopyBuffer", .field = "cmd_copy_buffer" },
        .{ .name = "vkCmdCopyBufferToImage", .field = "cmd_copy_buffer_to_image" },
        .{ .name = "vkCmdCopyImage", .field = "cmd_copy_image" },
        .{ .name = "vkCmdCopyImageToBuffer", .field = "cmd_copy_image_to_buffer" },
        .{ .name = "vkCmdCopyQueryPoolResults", .field = "cmd_copy_query_pool_results" },
        .{ .name = "vkCmdDispatch", .field = "cmd_dispatch" },
        .{ .name = "vkCmdDispatchBase", .field = "cmd_dispatch_base" },
        .{ .name = "vkCmdDispatchIndirect", .field = "cmd_dispatch_indirect" },
        .{ .name = "vkCmdDraw", .field = "cmd_draw" },
        .{ .name = "vkCmdDrawIndexed", .field = "cmd_draw_indexed" },
        .{ .name = "vkCmdDrawIndexedIndirect", .field = "cmd_draw_indexed_indirect" },
        .{ .name = "vkCmdDrawIndexedIndirectCount", .field = "cmd_draw_indexed_indirect_count" },
        .{ .name = "vkCmdDrawIndirect", .field = "cmd_draw_indirect" },
        .{ .name = "vkCmdDrawIndirectCount", .field = "cmd_draw_indirect_count" },
        .{ .name = "vkCmdEndConditionalRenderingEXT", .field = "cmd_end_conditional_rendering" },
        .{ .name = "vkCmdEndQuery", .field = "cmd_end_query" },
        .{ .name = "vkCmdEndRendering", .field = "cmd_end_rendering" },
        .{ .name = "vkCmdEndRenderingKHR", .field = "cmd_end_rendering" },
        .{ .name = "vkCmdEndRenderPass", .field = "cmd_end_render_pass" },
        .{ .name = "vkCmdEndRenderPass2", .field = "cmd_end_render_pass2" },
        .{ .name = "vkCmdEndRenderPass2KHR", .field = "cmd_end_render_pass2" },
        .{ .name = "vkCmdExecuteCommands", .field = "cmd_execute_commands" },
        .{ .name = "vkCmdFillBuffer", .field = "cmd_fill_buffer" },
        .{ .name = "vkCmdNextSubpass", .field = "cmd_next_subpass" },
        .{ .name = "vkCmdNextSubpass2", .field = "cmd_next_subpass2" },
        .{ .name = "vkCmdNextSubpass2KHR", .field = "cmd_next_subpass2" },
        .{ .name = "vkCmdPipelineBarrier", .field = "cmd_pipeline_barrier" },
        .{ .name = "vkCmdPipelineBarrier2", .field = "cmd_pipeline_barrier2" },
        .{ .name = "vkCmdPipelineBarrier2KHR", .field = "cmd_pipeline_barrier2" },
        .{ .name = "vkCmdPushConstants", .field = "cmd_push_constants" },
        .{ .name = "vkCmdPushDescriptorSetKHR", .field = "cmd_push_descriptor_set" },
        .{ .name = "vkCmdResetQueryPool", .field = "cmd_reset_query_pool" },
        .{ .name = "vkCmdResolveImage", .field = "cmd_resolve_image" },
        .{ .name = "vkCmdSetBlendConstants", .field = "cmd_set_blend_constants" },
        .{ .name = "vkCmdSetDepthBias", .field = "cmd_set_depth_bias" },
        .{ .name = "vkCmdSetDepthBounds", .field = "cmd_set_depth_bounds" },
        .{ .name = "vkCmdSetDepthCompareOp", .field = "cmd_set_depth_compare_op" },
        .{ .name = "vkCmdSetDepthTestEnable", .field = "cmd_set_depth_test_enable" },
        .{ .name = "vkCmdSetDepthWriteEnable", .field = "cmd_set_depth_write_enable" },
        .{ .name = "vkCmdSetPrimitiveRestartEnable", .field = "cmd_set_primitive_restart_enable" },
        .{ .name = "vkCmdSetScissor", .field = "cmd_set_scissor" },
        .{ .name = "vkCmdSetStencilCompareMask", .field = "cmd_set_stencil_compare_mask" },
        .{ .name = "vkCmdSetStencilOp", .field = "cmd_set_stencil_op" },
        .{ .name = "vkCmdSetStencilReference", .field = "cmd_set_stencil_reference" },
        .{ .name = "vkCmdSetStencilTestEnable", .field = "cmd_set_stencil_test_enable" },
        .{ .name = "vkCmdSetStencilWriteMask", .field = "cmd_set_stencil_write_mask" },
        .{ .name = "vkCmdSetViewport", .field = "cmd_set_viewport" },
        .{ .name = "vkCmdUpdateBuffer", .field = "cmd_update_buffer" },
    };
    const hash = vulkanNameHash(name);
    inline for (fields) |entry| {
        const expected_hash = comptime vulkanNameHash(entry.name);
        if (hash == expected_hash and std.mem.eql(u8, name, entry.name)) {
            return @field(self.real_vulkan.fn_ptrs, entry.field) != null;
        }
    }
    return false;
}

pub fn finishVulkanCommandAdmission(self: anytype, state: anytype, name: []const u8, command_index: ?usize, forwarded: bool) void {
    if (forwarded) {
        if (command_index) |index| self.vulkan_command_admission[index].forwarded +|= 1;
        self.noteVulkanCommandShape(name, guest_context.registers(state).rdi);
        if (self.vulkan_real_command_calls == 1) machoCapturePrint(
            "macho-processor: Vulkan forwarding boundary: first real command={s} command_buffer=0x{x}\n",
            .{ name, guest_context.registers(state).rdi },
        );
        return;
    }
    self.vulkan_command_admission_rejected +|= 1;
    const index = command_index orelse return;
    const record = &self.vulkan_command_admission[index];
    record.rejected +|= 1;
    record.last_reason = if (self.real_vulkan.device_lost)
        .device_lost
    else if (self.real_vulkan.realCommandBuffer(guest_context.registers(state).rdi) == null)
        .command_buffer_unmapped
    else if (!self.nativeVulkanCommandFunctionAvailable(name))
        .native_entry_point_missing
    else
        .argument_marshalling_refused;
    // Native-entry-point absence has no marshalling guard to name. Point
    // to this classification site rather than emitting an unusable :0.
    record.last_refusal_line = if (self.vulkan_command_refusal_line != 0)
        self.vulkan_command_refusal_line
    else
        @src().line;
    record.last_arguments = .{
        guest_context.registers(state).rdi, guest_context.registers(state).rsi, guest_context.registers(state).rdx,
        guest_context.registers(state).rcx, guest_context.registers(state).r8,  guest_context.registers(state).r9,
        guestStackArg(state, 0),            guestStackArg(state, 1),            guestStackArg(state, 2),
        guestStackArg(state, 3),            guestStackArg(state, 4),            guestStackArg(state, 5),
    };
    if (record.rejected <= 4 or (record.rejected & (record.rejected - 1)) == 0) {
        self.printVulkanCommandRefusal(name, record);
    }
}

pub fn printVulkanCommandRefusal(_: *const Forwarder, name: []const u8, record: *const VulkanCommandAdmission) void {
    const args = record.last_arguments;
    machoCapturePrint(
        "macho-processor: Vulkan command refused before native call: name={s} entries={d} forwarded={d} rejected={d} reason={s} refusal_site=dynamic_library_forwarder.zig:{d} args[0..11]=0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}; handled does not mean native work\n",
        .{ name, record.entries, record.forwarded, record.rejected, @tagName(record.last_reason), record.last_refusal_line, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11] },
    );
}

pub fn printVulkanCommandAdmission(self: anytype) void {
    if (self.vulkan_command_admission_entries == 0) return;
    machoCapturePrint(
        "macho-processor: PRESENT CHAIN:   command_admission=entries:{d},forwarded:{d},rejected:{d},untracked:{d}; forwarded means the native entry point was called synchronously or admitted to the ordered worker; this report drains queued calls first\n",
        .{ self.vulkan_command_admission_entries, self.vulkan_real_command_calls, self.vulkan_command_admission_rejected, self.vulkan_command_admission_untracked },
    );
    if (self.vulkan_async_command_worker_decided) {
        if (self.vulkan_async_command_worker) |worker| {
            const stats = worker.stats();
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   hybrid_command_worker=enabled:{} submitted={d} completed={d} sequence(queued/completed)={d}/{d} batches={d} max_batch={d} max_queue_depth={d} work_signals={d} drain_broadcasts={d} queue_full_fallbacks={d} worker_stopped_fallbacks={d} ordering_barriers_with_work={d}; FSI continuation boundaries drain this worker before synchronous pass close/replay\n",
                .{ self.vulkan_async_command_worker_enabled, stats.submitted, stats.completed, stats.last_submitted_sequence, stats.completed_sequence, stats.batches, stats.max_batch_size, stats.max_depth, stats.work_signals, stats.drain_broadcasts, self.vulkan_async_queue_saturated_fallbacks, self.vulkan_async_worker_stopped_fallbacks, self.vulkan_async_command_barriers },
            );
        } else {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   hybrid_command_worker=enabled:{} submitted=0 completed=0 sequence(queued/completed)=0/0 batches=0 max_batch=0 max_queue_depth=0 queue_full_fallbacks={d} worker_stopped_fallbacks={d} ordering_barriers_with_work={d}\n",
                .{ self.vulkan_async_command_worker_enabled, self.vulkan_async_queue_saturated_fallbacks, self.vulkan_async_worker_stopped_fallbacks, self.vulkan_async_command_barriers },
            );
        }
    }
    for (self.vulkan_command_admission, forwarded_vulkan_commands) |record, name| {
        if (record.entries == 0) continue;
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   command_admission name={s} entries={d} forwarded={d} rejected={d}\n",
            .{ name, record.entries, record.forwarded, record.rejected },
        );
        if (record.rejected != 0) self.printVulkanCommandRefusal(name, &record);
    }
}

pub fn forwardVulkanCommand(self: anytype, state: anytype, requested_hash: u64, requested_name: []const u8) void {
    const name = canonicalVulkanCommand(requested_name);
    const name_hash = if (name.ptr == requested_name.ptr) requested_hash else vulkanNameHash(name);
    const command_index = forwardedVulkanCommandIndex(name);
    self.vulkan_command_admission_entries +|= 1;
    if (command_index) |index| {
        self.vulkan_command_admission[index].entries +|= 1;
    } else {
        self.vulkan_command_admission_untracked +|= 1;
    }
    self.vulkan_command_refusal_line = 0;
    const native_calls_before = self.vulkan_real_command_calls;
    defer self.finishVulkanCommandAdmission(state, name, command_index, self.vulkan_real_command_calls != native_calls_before);
    const is_descriptor_bind = name_hash == vulkanNameHash("vkCmdBindDescriptorSets") and
        std.mem.eql(u8, name, "vkCmdBindDescriptorSets");
    if (is_descriptor_bind) self.vulkan_descriptor_bind_admission.entries +|= 1;
    self.vulkan_device_void_calls +|= 1;
    self.vulkan_modeled_command_calls +|= 1;
    if (self.real_vulkan.device_lost) {
        if (is_descriptor_bind) self.rejectDescriptorBind(
            .device_lost,
            guest_context.registers(state).rdi,
            guest_context.registers(state).rdx,
            guest_context.registers(state).r8,
            guest_context.registers(state).r9,
            guestStackArg(state, 0),
            guestStackArg(state, 1),
            0,
        );
        return self.noteVulkanCommandRefusal(@src().line);
    }
    if (!self.fsiRasterBeforeCommand(guest_context.registers(state).rdi, name_hash, name)) return self.noteVulkanCommandRefusal(@src().line);
    self.fsiNoteCommand(guest_context.registers(state).rdi, name_hash, name);
    if (self.fsiRecording(guest_context.registers(state).rdi)) |recording| {
        if (recording.failed) return self.noteVulkanCommandRefusal(@src().line);
    }
    const own_command_buffer = self.real_vulkan.realCommandBuffer(guest_context.registers(state).rdi) orelse {
        if (is_descriptor_bind) self.rejectDescriptorBind(
            .command_buffer_unmapped,
            guest_context.registers(state).rdi,
            guest_context.registers(state).rdx,
            guest_context.registers(state).r8,
            guest_context.registers(state).r9,
            guestStackArg(state, 0),
            guestStackArg(state, 1),
            guest_context.registers(state).rdi,
        );
        if (self.vulkan_modeled_command_calls <= 8) machoCapturePrint(
            "macho-processor: Vulkan command not forwarded: {s} command_buffer=0x{x} has no real mapping\n",
            .{ name, guest_context.registers(state).rdi },
        );
        return self.noteVulkanCommandRefusal(@src().line);
    };
    if (std.mem.eql(u8, name, "vkCmdExecuteCommands") or std.mem.startsWith(u8, name, "vkCmdPushDescriptor")) {
        if (self.native_texture_state) |native| native.resetCommand(guest_context.registers(state).rdi);
    }
    // Once an FSI recording has been split its commands go to the newest chunk.
    const command_buffer = self.fsiCommandTarget(guest_context.registers(state).rdi, own_command_buffer);
    if ((name_hash == vulkanNameHash("vkCmdBindPipeline") and std.mem.eql(u8, name, "vkCmdBindPipeline"))) {
        const pipeline = self.real_vulkan.realPipeline(guest_context.registers(state).rdx) orelse return self.noteVulkanCommandRefusal(@src().line);
        self.noteCommandPipelineState(guest_context.registers(state).rdi, guest_context.registers(state).rdx, pipeline, guest_context.registers(state).rsi);
        if (guest_context.registers(state).rsi == 1) if (self.native_texture_state) |native| {
            if (native.command(guest_context.registers(state).rdi)) |command| command.pipeline = pipeline;
        };
        // Compute and graphics are separate bind points: a compute bind
        // (Xenia's resolves and texture loads) leaves the graphics
        // pipeline its next draw uses in place.
        if (@as(u32, @truncate(guest_context.registers(state).rsi)) == VK_PIPELINE_BIND_POINT_GRAPHICS) {
            self.fsi_raster.bindPipeline(guest_context.registers(state).rdi, pipeline);
            self.rect_expand_bound_pipeline = if (self.rectangleExpandedPipeline(pipeline)) pipeline else 0;
            const recording = self.rectExpandCommandState(guest_context.registers(state).rdi);
            recording.pipeline = pipeline;
            recording.marked_pipeline = self.rect_expand_bound_pipeline != 0;
        }
        if (self.real_vulkan.fn_ptrs.cmd_bind_pipeline) |function| {
            const bind_point: u32 = @intCast(guest_context.registers(state).rsi);
            if (!self.queueAsyncVulkanCommand(.{ .bind_pipeline = .{
                .function = function,
                .command_buffer = command_buffer,
                .bind_point = bind_point,
                .pipeline = pipeline,
            } })) self.callNativeVulkanCommand(function, .{ command_buffer, bind_point, pipeline });
            if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| {
                if (!shadow.bindPipeline(bind_point, pipeline)) self.fsiNoteShadowBlock(guest_context.registers(state).rdi, .unrecorded_command);
            }
        }
    } else if ((name_hash == vulkanNameHash("vkCmdExecuteCommands") and std.mem.eql(u8, name, "vkCmdExecuteCommands"))) {
        const count = guest_context.registers(state).rsi;
        var secondary: [64]abi.CommandBuffer = [_]abi.CommandBuffer{null} ** 64;
        if (count > secondary.len or (count != 0 and state.guestMemoryConst(guest_context.registers(state).rdx, count * 8) == null)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_execute_commands) |function| {
            const primary_target = self.commandPassTarget(guest_context.registers(state).rdi);
            for (0..@as(usize, @intCast(count))) |index| {
                const synthetic = state.read64(guest_context.registers(state).rdx + @as(u64, @intCast(index)) * 8);
                secondary[index] = self.real_vulkan.realCommandBuffer(synthetic) orelse return self.noteVulkanCommandRefusal(@src().line);
                if (primary_target) |target| {
                    if (target.image != 0) {
                        self.vulkan_fsi_tracker.setTarget(synthetic, target.image, .inherited_secondary);
                    } else {
                        self.vulkan_fsi_tracker.noteSecondaryTargetUnresolved(synthetic);
                    }
                } else {
                    self.vulkan_fsi_tracker.noteSecondaryTargetUnresolved(synthetic);
                }
                self.mergeCommandTargets(guest_context.registers(state).rdi, synthetic);
            }
            self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(count), &secondary });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdBindVertexBuffers") and std.mem.eql(u8, name, "vkCmdBindVertexBuffers"))) {
        const count = guest_context.registers(state).rdx;
        var buffers: [32]abi.Buffer = undefined;
        var offsets: [32]u64 = undefined;
        if (count > buffers.len or !copyGuestHandleArray(self, state, guest_context.registers(state).rcx, count, @ptrCast(&buffers), .buffer)) return self.noteVulkanCommandRefusal(@src().line);
        if (!copyGuestStructs(u64, state, guest_context.registers(state).r8, count, &offsets)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_bind_vertex_buffers) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), @intCast(count), &buffers, &offsets });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| self.fsiNoteShadowBlock(guest_context.registers(state).rdi, shadow.bindVertexBuffers(@intCast(guest_context.registers(state).rsi), buffers[0..@intCast(count)], offsets[0..@intCast(count)]));
    } else if ((name_hash == vulkanNameHash("vkCmdBindIndexBuffer") and std.mem.eql(u8, name, "vkCmdBindIndexBuffer"))) {
        const buffer = self.real_vulkan.realBuffer(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        // The two-triangle strips are the built-in buffer's first
        // section, 32-bit, so an expansion binds it at offset 0.
        const recording = self.rectExpandCommandState(guest_context.registers(state).rdi);
        recording.index_buffer = buffer;
        recording.index_offset = guest_context.registers(state).rdx;
        recording.index_type = @truncate(guest_context.registers(state).rcx);
        recording.builtin_indices = self.rect_expand_builtin_index_buffer != 0 and
            buffer == self.rect_expand_builtin_index_buffer and
            guest_context.registers(state).rdx == 0 and @as(u32, @truncate(guest_context.registers(state).rcx)) == abi.INDEX_TYPE_UINT32;
        if (self.real_vulkan.fn_ptrs.cmd_bind_index_buffer) |function| {
            const index_type: u32 = @intCast(guest_context.registers(state).rcx);
            if (!self.queueAsyncVulkanCommand(.{ .bind_index_buffer = .{
                .function = function,
                .command_buffer = command_buffer,
                .buffer = buffer,
                .offset = guest_context.registers(state).rdx,
                .index_type = index_type,
            } })) self.callNativeVulkanCommand(function, .{ command_buffer, buffer, guest_context.registers(state).rdx, index_type });
            if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| shadow.index = .{ .buffer = buffer, .offset = guest_context.registers(state).rdx, .index_type = index_type };
        }
    } else if (is_descriptor_bind) {
        const set_count = guest_context.registers(state).r8;
        const guest_sets = guest_context.registers(state).r9;
        const dynamic_count = guestStackArg(state, 0);
        const guest_dynamic_offsets = guestStackArg(state, 1);
        var sets: [32]u64 = undefined;
        var dynamic_offsets: [64]u32 = undefined;
        const layout = self.real_vulkan.realPipelineLayout(guest_context.registers(state).rdx) orelse {
            self.rejectDescriptorBind(.pipeline_layout_unmapped, guest_context.registers(state).rdi, guest_context.registers(state).rdx, set_count, guest_sets, dynamic_count, guest_dynamic_offsets, guest_context.registers(state).rdx);
            return self.noteVulkanCommandRefusal(@src().line);
        };
        if (set_count > sets.len) {
            self.rejectDescriptorBind(.set_count_exceeds_limit, guest_context.registers(state).rdi, guest_context.registers(state).rdx, set_count, guest_sets, dynamic_count, guest_dynamic_offsets, 0);
            return self.noteVulkanCommandRefusal(@src().line);
        }
        if (set_count != 0 and state.guestMemoryConst(guest_sets, set_count * 8) == null) {
            self.rejectDescriptorBind(.descriptor_set_array_unreadable, guest_context.registers(state).rdi, guest_context.registers(state).rdx, set_count, guest_sets, dynamic_count, guest_dynamic_offsets, 0);
            return self.noteVulkanCommandRefusal(@src().line);
        }
        for (0..@as(usize, @intCast(set_count))) |index| {
            const synthetic = state.read64(guest_sets + @as(u64, @intCast(index)) * 8);
            sets[index] = self.real_vulkan.realDescriptorSet(synthetic) orelse {
                self.rejectDescriptorBind(.descriptor_set_unmapped, guest_context.registers(state).rdi, guest_context.registers(state).rdx, set_count, guest_sets, dynamic_count, guest_dynamic_offsets, synthetic);
                return self.noteVulkanCommandRefusal(@src().line);
            };
        }
        if (dynamic_count > dynamic_offsets.len) {
            self.rejectDescriptorBind(.dynamic_offset_count_exceeds_limit, guest_context.registers(state).rdi, guest_context.registers(state).rdx, set_count, guest_sets, dynamic_count, guest_dynamic_offsets, 0);
            return self.noteVulkanCommandRefusal(@src().line);
        }
        if (!copyGuestStructs(u32, state, guest_dynamic_offsets, dynamic_count, &dynamic_offsets)) {
            self.rejectDescriptorBind(.dynamic_offset_array_unreadable, guest_context.registers(state).rdi, guest_context.registers(state).rdx, set_count, guest_sets, dynamic_count, guest_dynamic_offsets, 0);
            return self.noteVulkanCommandRefusal(@src().line);
        }
        const function = self.real_vulkan.fn_ptrs.cmd_bind_descriptor_sets orelse {
            self.rejectDescriptorBind(.native_entry_point_missing, guest_context.registers(state).rdi, guest_context.registers(state).rdx, set_count, guest_sets, dynamic_count, guest_dynamic_offsets, 0);
            return self.noteVulkanCommandRefusal(@src().line);
        };
        self.callNativeVulkanCommand(function, .{
            command_buffer,
            @intCast(guest_context.registers(state).rsi),
            layout,
            @intCast(guest_context.registers(state).rcx),
            @intCast(set_count),
            &sets,
            @intCast(dynamic_count),
            if (dynamic_count == 0) null else &dynamic_offsets,
        });
        self.vulkan_descriptor_bind_admission.forwarded +|= 1;
        if (guest_context.registers(state).rsi == 1) if (self.native_texture_state) |native| {
            if (native.command(guest_context.registers(state).rdi)) |command| command.bind(layout, @intCast(guest_context.registers(state).rcx), sets[0..@intCast(set_count)], @intCast(dynamic_count));
        };
        self.vulkan_descriptor_bind_calls +|= 1;
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| self.fsiNoteShadowBlock(guest_context.registers(state).rdi, shadow.bindDescriptorSets(@intCast(guest_context.registers(state).rsi), layout, @intCast(guest_context.registers(state).rcx), sets[0..@intCast(set_count)], dynamic_offsets[0..@intCast(dynamic_count)]));
        // Keep the descriptor-set identities with the command. The image
        // contents of a set are persistent guest state and may be updated
        // after recording but before queue submission; resolve them at
        // the submission boundary instead of freezing a bind-time view.
        self.noteCommandDescriptorSets(state, guest_context.registers(state).rdi, guest_context.registers(state).rcx, guest_sets, set_count);
    } else if ((name_hash == vulkanNameHash("vkCmdPushDescriptorSetKHR") and std.mem.eql(u8, name, "vkCmdPushDescriptorSetKHR"))) {
        self.forwardPushDescriptorSet(state, command_buffer);
    } else if ((name_hash == vulkanNameHash("vkCmdDraw") and std.mem.eql(u8, name, "vkCmdDraw"))) {
        if (self.real_vulkan.fn_ptrs.cmd_draw) |function| {
            self.noteCommandTargets(guest_context.registers(state).rdi, .content);
            self.noteGraphicsDrawState(guest_context.registers(state).rdi, "draw", guest_context.registers(state).rsi, guest_context.registers(state).rdx, guest_context.registers(state).rcx, 0, guest_context.registers(state).r8);
            self.repairGuestOutputTopology(guest_context.registers(state).rdi, command_buffer, guest_context.registers(state).rsi, guest_context.registers(state).rdx, guest_context.registers(state).rcx, guest_context.registers(state).r8);
            const vertex_count: u32 = @intCast(guest_context.registers(state).rsi);
            const instance_count: u32 = @intCast(guest_context.registers(state).rdx);
            const first_vertex: u32 = @intCast(guest_context.registers(state).rcx);
            const first_instance: u32 = @intCast(guest_context.registers(state).r8);
            if (!self.queueAsyncVulkanCommand(.{ .draw = .{
                .function = function,
                .command_buffer = command_buffer,
                .vertex_count = vertex_count,
                .instance_count = instance_count,
                .first_vertex = first_vertex,
                .first_instance = first_instance,
            } })) self.callNativeVulkanCommand(function, .{ command_buffer, vertex_count, instance_count, first_vertex, first_instance });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdDrawIndexed") and std.mem.eql(u8, name, "vkCmdDrawIndexed"))) {
        // Vulkan defines an indexed draw's `gl_VertexIndex` as
        // `indexBuffer[i] + vertexOffset`, so the rectangle tag rides in
        // the offset. Xenia's builtin index buffer is untouched, which
        // matters because its point-list fallback shares it - and that
        // fallback's shader is one this bridge deliberately refuses to
        // rewrite, so its draws are never tagged.
        var vertex_offset: i32 = @bitCast(@as(u32, @truncate(guest_context.registers(state).r8)));
        // Xenia draws `4 * rectangles + (rectangles - 1)` indices for the
        // fallback: four strip vertices per rectangle and a primitive
        // restart between them. An index count that is not one short of a
        // multiple of five is some other draw that happens to share this
        // pipeline, and it is left alone.
        const index_count = guest_context.registers(state).rsi;
        const rectangle_shaped = index_count >= 4 and (index_count + 1) % 5 == 0;
        const recording = self.rectExpandCommandState(guest_context.registers(state).rdi);
        if (recording.marked_pipeline and rectangle_shaped) {
            // The rewritten module is shared with guest triangle strips
            // that use primitive restart, and 1 in 5 of those has a
            // rectangle-shaped count. Decoding a guest index as
            // `(rectangle << 2) | corner` shades three unrelated
            // vertices per corner - giant triangles, and enough overdraw
            // to trip the GPU watchdog. Only the built-in buffer holds
            // expansion indices, and Xenia draws it from index 0.
            const builtin_indices = recording.builtin_indices and
                @as(u32, @truncate(guest_context.registers(state).rcx)) == 0;
            if (builtin_indices) {
                vertex_offset = @bitCast(@as(u32, @bitCast(vertex_offset)) | gpu_vulkan.rect_list_expand.rect_tag);
                self.rect_expand_draws_tagged +|= 1;
            } else {
                self.rect_expand_draws_declined_foreign_index +|= 1;
                if (self.rect_expand_first_foreign_index_sample == null) {
                    self.rect_expand_first_foreign_index_sample = .{
                        .command_buffer = recording.command_buffer,
                        .pipeline = recording.pipeline,
                        .index_buffer = recording.index_buffer,
                        .index_offset = recording.index_offset,
                        .index_type = recording.index_type,
                        .index_count = @truncate(index_count),
                        .first_index = @truncate(guest_context.registers(state).rcx),
                        .vertex_offset = vertex_offset,
                        .instance_count = @truncate(guest_context.registers(state).rdx),
                    };
                }
            }
        }
        if (self.real_vulkan.fn_ptrs.cmd_draw_indexed) |function| {
            self.noteCommandTargets(guest_context.registers(state).rdi, .content);
            self.noteGraphicsDrawState(guest_context.registers(state).rdi, "draw_indexed", guest_context.registers(state).rsi, guest_context.registers(state).rdx, guest_context.registers(state).rcx, guest_context.registers(state).r8, guest_context.registers(state).r9);
            const native_index_count: u32 = @intCast(guest_context.registers(state).rsi);
            const instance_count: u32 = @intCast(guest_context.registers(state).rdx);
            const first_index: u32 = @intCast(guest_context.registers(state).rcx);
            const first_instance: u32 = @intCast(guest_context.registers(state).r9);
            if (!self.queueAsyncVulkanCommand(.{ .draw_indexed = .{
                .function = function,
                .command_buffer = command_buffer,
                .index_count = native_index_count,
                .instance_count = instance_count,
                .first_index = first_index,
                .vertex_offset = vertex_offset,
                .first_instance = first_instance,
            } })) self.callNativeVulkanCommand(function, .{ command_buffer, native_index_count, instance_count, first_index, vertex_offset, first_instance });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdDrawIndirect") and std.mem.eql(u8, name, "vkCmdDrawIndirect"))) {
        const buffer = self.real_vulkan.realBuffer(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_draw_indirect) |function| {
            self.noteCommandTargets(guest_context.registers(state).rdi, .content);
            self.noteFsiDraw(guest_context.registers(state).rdi, .indirect);
            self.callNativeVulkanCommand(function, .{ command_buffer, buffer, guest_context.registers(state).rdx, @intCast(guest_context.registers(state).rcx), @intCast(guest_context.registers(state).r8) });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdDrawIndexedIndirect") and std.mem.eql(u8, name, "vkCmdDrawIndexedIndirect"))) {
        const buffer = self.real_vulkan.realBuffer(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_draw_indexed_indirect) |function| {
            self.noteCommandTargets(guest_context.registers(state).rdi, .content);
            self.noteFsiDraw(guest_context.registers(state).rdi, .indexed_indirect);
            self.callNativeVulkanCommand(function, .{ command_buffer, buffer, guest_context.registers(state).rdx, @intCast(guest_context.registers(state).rcx), @intCast(guest_context.registers(state).r8) });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdDrawIndirectCount") and std.mem.eql(u8, name, "vkCmdDrawIndirectCount")) or (name_hash == vulkanNameHash("vkCmdDrawIndexedIndirectCount") and std.mem.eql(u8, name, "vkCmdDrawIndexedIndirectCount"))) {
        const buffer = self.real_vulkan.realBuffer(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        const count_buffer = self.real_vulkan.realBuffer(guest_context.registers(state).rcx) orelse return self.noteVulkanCommandRefusal(@src().line);
        const max_draw_count = guestStackArg(state, 0);
        const stride = guestStackArg(state, 1);
        if ((name_hash == vulkanNameHash("vkCmdDrawIndirectCount") and std.mem.eql(u8, name, "vkCmdDrawIndirectCount"))) {
            if (self.real_vulkan.fn_ptrs.cmd_draw_indirect_count) |function| {
                self.noteCommandTargets(guest_context.registers(state).rdi, .content);
                self.noteFsiDraw(guest_context.registers(state).rdi, .indirect_count);
                self.callNativeVulkanCommand(function, .{ command_buffer, buffer, guest_context.registers(state).rdx, count_buffer, guest_context.registers(state).r8, @intCast(max_draw_count), @intCast(stride) });
            }
        } else if (self.real_vulkan.fn_ptrs.cmd_draw_indexed_indirect_count) |function| {
            self.noteCommandTargets(guest_context.registers(state).rdi, .content);
            self.noteFsiDraw(guest_context.registers(state).rdi, .indexed_indirect_count);
            self.callNativeVulkanCommand(function, .{ command_buffer, buffer, guest_context.registers(state).rdx, count_buffer, guest_context.registers(state).r8, @intCast(max_draw_count), @intCast(stride) });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdDispatch") and std.mem.eql(u8, name, "vkCmdDispatch"))) {
        if (self.real_vulkan.fn_ptrs.cmd_dispatch) |function| {
            self.noteCommandTargets(guest_context.registers(state).rdi, .content);
            const groups = [3]u32{ @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx), @intCast(guest_context.registers(state).rcx) };
            var routed = false;
            if (self.native_texture_state) |native| {
                if (native.canDispatch(guest_context.registers(state).rdi, groups)) {
                    _ = self.drainAsyncVulkanCommandsIfPending();
                    routed = native.dispatch(&self.real_vulkan, guest_context.registers(state).rdi, command_buffer, groups);
                } else if (native.commands.get(guest_context.registers(state).rdi)) |command_state| {
                    if (native.pipelines.contains(command_state.pipeline)) {
                        const reason = native.dispatchReason(guest_context.registers(state).rdi, groups).?;
                        native.noteDecline(reason);
                        if (native.declines <= 8) {
                            var push: native_texture.Push = undefined;
                            @memcpy(std.mem.asBytes(&push), &command_state.push);
                            machoCapturePrint("macho-processor: NATIVE METAL TEXTURE DECLINE: reason={s} pipeline=0x{x} descriptor_layout=0x{x} push_layout=0x{x} push_mask=0x{x} flags={d} blocks={d}/{d}/{d} guest_pitch={d} host_pitch={d} height={d} offsets={d}/{d} groups={d}/{d}/{d}; original hardened dispatch retained\n", .{ @tagName(reason), command_state.pipeline, command_state.layout, command_state.push_layout, command_state.push_mask, push.flags, push.blocks_x, push.blocks_y, push.blocks_z, push.guest_pitch, push.host_pitch, push.height, push.guest_offset, push.host_offset, groups[0], groups[1], groups[2] });
                        }
                    }
                }
            }
            if (self.native_texture_state) |native| {
                if (native.terminal_result != abi.SUCCESS) {
                    self.noteRealVulkanResult(native.terminal_result, "native Metal texture metadata");
                    return self.noteVulkanCommandRefusal(@src().line);
                }
            }
            if (routed) self.vulkan_real_command_calls +|= 4 else self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx), @intCast(guest_context.registers(state).rcx) });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdDispatchIndirect") and std.mem.eql(u8, name, "vkCmdDispatchIndirect"))) {
        const buffer = self.real_vulkan.realBuffer(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_dispatch_indirect) |function| {
            self.noteCommandTargets(guest_context.registers(state).rdi, .content);
            self.callNativeVulkanCommand(function, .{ command_buffer, buffer, guest_context.registers(state).rdx });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdDispatchBase") and std.mem.eql(u8, name, "vkCmdDispatchBase"))) {
        if (self.real_vulkan.fn_ptrs.cmd_dispatch_base) |function| {
            self.noteCommandTargets(guest_context.registers(state).rdi, .content);
            self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx), @intCast(guest_context.registers(state).rcx), @intCast(guest_context.registers(state).r8), @intCast(guest_context.registers(state).r9), @intCast(guestStackArg(state, 0)) });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdSetViewport") and std.mem.eql(u8, name, "vkCmdSetViewport"))) {
        var viewports: [16]abi.Viewport = undefined;
        if (!copyGuestStructs(abi.Viewport, state, guest_context.registers(state).rcx, guest_context.registers(state).rdx, &viewports)) return self.noteVulkanCommandRefusal(@src().line);
        self.noteCommandViewport(guest_context.registers(state).rdi, guest_context.registers(state).rsi, guest_context.registers(state).rdx, viewports[0..@as(usize, @intCast(guest_context.registers(state).rdx))]);
        if (self.real_vulkan.fn_ptrs.cmd_set_viewport) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx), &viewports });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| self.fsiNoteShadowBlock(guest_context.registers(state).rdi, shadow.setViewports(@intCast(guest_context.registers(state).rsi), viewports[0..@intCast(guest_context.registers(state).rdx)]));
    } else if ((name_hash == vulkanNameHash("vkCmdSetScissor") and std.mem.eql(u8, name, "vkCmdSetScissor"))) {
        var scissors: [16]abi.Rect2D = undefined;
        if (!copyGuestStructs(abi.Rect2D, state, guest_context.registers(state).rcx, guest_context.registers(state).rdx, &scissors)) return self.noteVulkanCommandRefusal(@src().line);
        self.noteCommandScissor(guest_context.registers(state).rdi, guest_context.registers(state).rsi, guest_context.registers(state).rdx, scissors[0..@as(usize, @intCast(guest_context.registers(state).rdx))]);
        if (self.real_vulkan.fn_ptrs.cmd_set_scissor) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx), &scissors });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| self.fsiNoteShadowBlock(guest_context.registers(state).rdi, shadow.setScissors(@intCast(guest_context.registers(state).rsi), scissors[0..@intCast(guest_context.registers(state).rdx)]));
    } else if ((name_hash == vulkanNameHash("vkCmdSetBlendConstants") and std.mem.eql(u8, name, "vkCmdSetBlendConstants"))) {
        var constants: [4]f32 = undefined;
        if (!copyGuestStructs(f32, state, guest_context.registers(state).rsi, 4, &constants)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_set_blend_constants) |function| self.callNativeVulkanCommand(function, .{ command_buffer, &constants });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| shadow.blend_constants = constants;
    } else if ((name_hash == vulkanNameHash("vkCmdSetDepthBias") and std.mem.eql(u8, name, "vkCmdSetDepthBias"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_depth_bias) |function| self.callNativeVulkanCommand(function, .{
            command_buffer,
            @bitCast(guestFloatArgument(state, 0)),
            @bitCast(guestFloatArgument(state, 1)),
            @bitCast(guestFloatArgument(state, 2)),
        });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| shadow.depth_bias = .{ @bitCast(guestFloatArgument(state, 0)), @bitCast(guestFloatArgument(state, 1)), @bitCast(guestFloatArgument(state, 2)) };
    } else if ((name_hash == vulkanNameHash("vkCmdSetDepthBounds") and std.mem.eql(u8, name, "vkCmdSetDepthBounds"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_depth_bounds) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @bitCast(guestFloatArgument(state, 0)), @bitCast(guestFloatArgument(state, 1)) });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| shadow.depth_bounds = .{ @bitCast(guestFloatArgument(state, 0)), @bitCast(guestFloatArgument(state, 1)) };
    } else if ((name_hash == vulkanNameHash("vkCmdSetDepthTestEnable") and std.mem.eql(u8, name, "vkCmdSetDepthTestEnable"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_depth_test_enable) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi) });
    } else if ((name_hash == vulkanNameHash("vkCmdSetDepthWriteEnable") and std.mem.eql(u8, name, "vkCmdSetDepthWriteEnable"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_depth_write_enable) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi) });
    } else if ((name_hash == vulkanNameHash("vkCmdSetDepthCompareOp") and std.mem.eql(u8, name, "vkCmdSetDepthCompareOp"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_depth_compare_op) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi) });
    } else if ((name_hash == vulkanNameHash("vkCmdSetStencilTestEnable") and std.mem.eql(u8, name, "vkCmdSetStencilTestEnable"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_stencil_test_enable) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi) });
    } else if ((name_hash == vulkanNameHash("vkCmdSetStencilOp") and std.mem.eql(u8, name, "vkCmdSetStencilOp"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_stencil_op) |function| self.callNativeVulkanCommand(function, .{
            command_buffer,
            @intCast(guest_context.registers(state).rsi),
            @intCast(guest_context.registers(state).rdx),
            @intCast(guest_context.registers(state).rcx),
            @intCast(guest_context.registers(state).r8),
            @intCast(guest_context.registers(state).r9),
        });
    } else if ((name_hash == vulkanNameHash("vkCmdSetPrimitiveRestartEnable") and std.mem.eql(u8, name, "vkCmdSetPrimitiveRestartEnable"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_primitive_restart_enable) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi) });
    } else if ((name_hash == vulkanNameHash("vkCmdSetStencilCompareMask") and std.mem.eql(u8, name, "vkCmdSetStencilCompareMask"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_stencil_compare_mask) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx) });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| fsi_chain.Shadow.setStencil(&shadow.stencil_compare_mask, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx));
    } else if ((name_hash == vulkanNameHash("vkCmdSetStencilWriteMask") and std.mem.eql(u8, name, "vkCmdSetStencilWriteMask"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_stencil_write_mask) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx) });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| fsi_chain.Shadow.setStencil(&shadow.stencil_write_mask, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx));
    } else if ((name_hash == vulkanNameHash("vkCmdSetStencilReference") and std.mem.eql(u8, name, "vkCmdSetStencilReference"))) {
        if (self.real_vulkan.fn_ptrs.cmd_set_stencil_reference) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx) });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| fsi_chain.Shadow.setStencil(&shadow.stencil_reference, @intCast(guest_context.registers(state).rsi), @intCast(guest_context.registers(state).rdx));
    } else if ((name_hash == vulkanNameHash("vkCmdPushConstants") and std.mem.eql(u8, name, "vkCmdPushConstants"))) {
        const size = guest_context.registers(state).r8;
        var bytes: [256]u8 = undefined;
        if (!copyGuestBytes(state, guest_context.registers(state).r9, size, &bytes)) return self.noteVulkanCommandRefusal(@src().line);
        const layout = self.real_vulkan.realPipelineLayout(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        self.noteCommandPushConstants(guest_context.registers(state).rdi, guest_context.registers(state).rsi, layout, guest_context.registers(state).rdx, guest_context.registers(state).rcx, size, bytes[0..@as(usize, @intCast(size))]);
        if (guest_context.registers(state).rdx & 0x20 != 0) if (self.native_texture_state) |native| {
            if (native.command(guest_context.registers(state).rdi)) |command| command.constants(layout, @intCast(guest_context.registers(state).rcx), bytes[0..@intCast(size)]);
        };
        if (self.real_vulkan.fn_ptrs.cmd_push_constants) |function| self.callNativeVulkanCommand(function, .{ command_buffer, layout, @intCast(guest_context.registers(state).rdx), @intCast(guest_context.registers(state).rcx), @intCast(size), if (size == 0) null else &bytes });
        if (self.fsiShadow(guest_context.registers(state).rdi)) |shadow| self.fsiNoteShadowBlock(guest_context.registers(state).rdi, shadow.pushConstants(layout, @intCast(guest_context.registers(state).rdx), @intCast(guest_context.registers(state).rcx), bytes[0..@intCast(size)]));
    } else if ((name_hash == vulkanNameHash("vkCmdBeginConditionalRenderingEXT") and std.mem.eql(u8, name, "vkCmdBeginConditionalRenderingEXT"))) {
        if (self.real_vulkan.fn_ptrs.cmd_begin_conditional_rendering) |function| {
            var info: abi.ConditionalRenderingBeginInfoEXT = undefined;
            if (!copyGuestValue(abi.ConditionalRenderingBeginInfoEXT, state, guest_context.registers(state).rsi, &info) or info.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
            info.buffer = self.real_vulkan.realBuffer(info.buffer) orelse return self.noteVulkanCommandRefusal(@src().line);
            info.p_next = null;
            self.callNativeVulkanCommand(function, .{ command_buffer, &info });
        } else self.faultOnUnavailableVulkanCommand(name);
    } else if ((name_hash == vulkanNameHash("vkCmdEndConditionalRenderingEXT") and std.mem.eql(u8, name, "vkCmdEndConditionalRenderingEXT"))) {
        if (self.real_vulkan.fn_ptrs.cmd_end_conditional_rendering) |function| self.callNativeVulkanCommand(function, .{command_buffer}) else self.faultOnUnavailableVulkanCommand(name);
    } else if ((name_hash == vulkanNameHash("vkCmdBeginRendering") and std.mem.eql(u8, name, "vkCmdBeginRendering")) or (name_hash == vulkanNameHash("vkCmdBeginRenderingKHR") and std.mem.eql(u8, name, "vkCmdBeginRenderingKHR"))) {
        if (self.real_vulkan.fn_ptrs.cmd_begin_rendering) |function| {
            var info: abi.RenderingInfo = undefined;
            if (!copyGuestValue(abi.RenderingInfo, state, guest_context.registers(state).rsi, &info) or info.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
            if (info.color_attachment_count > 8) return self.noteVulkanCommandRefusal(@src().line);
            var colors: [8]abi.RenderingAttachmentInfo = undefined;
            var guest_color_target_view: u64 = 0;
            const colors_address = if (info.color_attachments) |pointer| @intFromPtr(pointer) else 0;
            if (!copyGuestStructs(abi.RenderingAttachmentInfo, state, colors_address, info.color_attachment_count, &colors)) return self.noteVulkanCommandRefusal(@src().line);
            var color_load_clear = false;
            for (colors[0..@as(usize, @intCast(info.color_attachment_count))]) |*attachment| {
                if (attachment.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
                if (attachment.load_op == VK_ATTACHMENT_LOAD_OP_CLEAR) color_load_clear = true;
                const guest_image_view = attachment.image_view;
                if (guest_color_target_view == 0 and guest_image_view != 0) guest_color_target_view = guest_image_view;
                const guest_resolve_image_view = attachment.resolve_image_view;
                if (guest_image_view != 0) self.addCommandImageView(guest_context.registers(state).rdi, guest_image_view);
                if (guest_resolve_image_view != 0) self.addCommandImageView(guest_context.registers(state).rdi, guest_resolve_image_view);
                self.noteCommandImageViewTransfer(guest_context.registers(state).rdi, guest_image_view, guest_resolve_image_view, .render_pass_resolve);
                if (guest_image_view != 0) attachment.image_view = self.real_vulkan.realImageView(guest_image_view) orelse return self.noteVulkanCommandRefusal(@src().line);
                if (guest_resolve_image_view != 0) attachment.resolve_image_view = self.real_vulkan.realImageView(guest_resolve_image_view) orelse return self.noteVulkanCommandRefusal(@src().line);
                attachment.p_next = null;
            }
            info.color_attachments = if (info.color_attachment_count == 0) null else &colors;
            var depth: abi.RenderingAttachmentInfo = undefined;
            var stencil: abi.RenderingAttachmentInfo = undefined;
            if (info.depth_attachment) |pointer| {
                if (!copyGuestValue(abi.RenderingAttachmentInfo, state, @intFromPtr(pointer), &depth) or depth.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
                const guest_depth_image_view = depth.image_view;
                const guest_depth_resolve_image_view = depth.resolve_image_view;
                if (guest_depth_image_view != 0) self.addCommandImageView(guest_context.registers(state).rdi, guest_depth_image_view);
                if (guest_depth_resolve_image_view != 0) self.addCommandImageView(guest_context.registers(state).rdi, guest_depth_resolve_image_view);
                self.noteCommandImageViewTransfer(guest_context.registers(state).rdi, guest_depth_image_view, guest_depth_resolve_image_view, .render_pass_resolve);
                if (guest_depth_image_view != 0) depth.image_view = self.real_vulkan.realImageView(guest_depth_image_view) orelse return self.noteVulkanCommandRefusal(@src().line);
                if (guest_depth_resolve_image_view != 0) depth.resolve_image_view = self.real_vulkan.realImageView(guest_depth_resolve_image_view) orelse return self.noteVulkanCommandRefusal(@src().line);
                depth.p_next = null;
                info.depth_attachment = &depth;
            }
            if (info.stencil_attachment) |pointer| {
                if (!copyGuestValue(abi.RenderingAttachmentInfo, state, @intFromPtr(pointer), &stencil) or stencil.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
                const guest_stencil_image_view = stencil.image_view;
                const guest_stencil_resolve_image_view = stencil.resolve_image_view;
                if (guest_stencil_image_view != 0) self.addCommandImageView(guest_context.registers(state).rdi, guest_stencil_image_view);
                if (guest_stencil_resolve_image_view != 0) self.addCommandImageView(guest_context.registers(state).rdi, guest_stencil_resolve_image_view);
                self.noteCommandImageViewTransfer(guest_context.registers(state).rdi, guest_stencil_image_view, guest_stencil_resolve_image_view, .render_pass_resolve);
                if (guest_stencil_image_view != 0) stencil.image_view = self.real_vulkan.realImageView(guest_stencil_image_view) orelse return self.noteVulkanCommandRefusal(@src().line);
                if (guest_stencil_resolve_image_view != 0) stencil.resolve_image_view = self.real_vulkan.realImageView(guest_stencil_resolve_image_view) orelse return self.noteVulkanCommandRefusal(@src().line);
                stencil.p_next = null;
                info.stencil_attachment = &stencil;
            }
            info.p_next = null;
            self.noteCommandDynamicTarget(guest_context.registers(state).rdi, guest_color_target_view);
            if (color_load_clear) self.noteLoadClearTarget(guest_context.registers(state).rdi, "vkCmdBeginRendering") else self.noteCommandTargets(guest_context.registers(state).rdi, .none);
            self.callNativeVulkanCommand(function, .{ command_buffer, &info });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdEndRendering") and std.mem.eql(u8, name, "vkCmdEndRendering")) or (name_hash == vulkanNameHash("vkCmdEndRenderingKHR") and std.mem.eql(u8, name, "vkCmdEndRenderingKHR"))) {
        if (self.real_vulkan.fn_ptrs.cmd_end_rendering) |function| {
            self.callNativeVulkanCommand(function, .{command_buffer});
            self.clearCommandPassTarget(guest_context.registers(state).rdi);
        }
    } else if ((name_hash == vulkanNameHash("vkCmdBeginRenderPass") and std.mem.eql(u8, name, "vkCmdBeginRenderPass"))) {
        const guest = state.guestMemoryConst(guest_context.registers(state).rsi, @sizeOf(abi.RenderPassBeginInfo)) orelse return self.noteVulkanCommandRefusal(@src().line);
        var begin: abi.RenderPassBeginInfo = undefined;
        @memcpy(std.mem.asBytes(&begin), guest);
        const guest_render_pass = begin.render_pass;
        const guest_framebuffer = begin.framebuffer;
        if (begin.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
        begin.p_next = null;
        begin.render_pass = self.real_vulkan.realRenderPass(begin.render_pass) orelse return self.noteVulkanCommandRefusal(@src().line);
        begin.framebuffer = self.real_vulkan.realFramebuffer(begin.framebuffer) orelse return self.noteVulkanCommandRefusal(@src().line);
        var clears: [32]abi.ClearValue = undefined;
        const clear_address = if (begin.clear_values) |pointer| @intFromPtr(pointer) else 0;
        if (begin.clear_value_count != 0 and clear_address == 0) return self.noteVulkanCommandRefusal(@src().line);
        if (!copyGuestStructs(abi.ClearValue, state, clear_address, begin.clear_value_count, &clears)) return self.noteVulkanCommandRefusal(@src().line);
        begin.clear_values = if (begin.clear_value_count == 0) null else &clears;
        if (self.real_vulkan.fn_ptrs.cmd_begin_render_pass) |function| {
            self.trackFramebufferTargets(guest_context.registers(state).rdi, guest_framebuffer);
            self.noteCommandPassTarget(guest_context.registers(state).rdi, guest_framebuffer);
            self.trackRenderPassTransfers(guest_context.registers(state).rdi, guest_render_pass, guest_framebuffer);
            if (self.trackedRenderPass(guest_render_pass)) |render_pass| {
                if (render_pass.color_load_clear) {
                    self.noteLoadClearTarget(guest_context.registers(state).rdi, "vkCmdBeginRenderPass");
                } else {
                    self.noteCommandTargets(guest_context.registers(state).rdi, .none);
                }
            } else {
                self.noteCommandTargets(guest_context.registers(state).rdi, .none);
            }
            self.callNativeVulkanCommand(function, .{ command_buffer, &begin, @intCast(guest_context.registers(state).rdx) });
            self.fsiNoteBeginRenderPass(guest_context.registers(state).rdi, &begin, @intCast(guest_context.registers(state).rdx));
        }
    } else if ((name_hash == vulkanNameHash("vkCmdNextSubpass") and std.mem.eql(u8, name, "vkCmdNextSubpass"))) {
        if (self.real_vulkan.fn_ptrs.cmd_next_subpass) |function| self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi) });
    } else if ((name_hash == vulkanNameHash("vkCmdBeginRenderPass2") and std.mem.eql(u8, name, "vkCmdBeginRenderPass2")) or (name_hash == vulkanNameHash("vkCmdBeginRenderPass2KHR") and std.mem.eql(u8, name, "vkCmdBeginRenderPass2KHR"))) {
        if (self.real_vulkan.fn_ptrs.cmd_begin_render_pass2) |function| {
            const guest_begin = state.guestMemoryConst(guest_context.registers(state).rsi, @sizeOf(abi.RenderPassBeginInfo)) orelse return self.noteVulkanCommandRefusal(@src().line);
            const guest_subpass = state.guestMemoryConst(guest_context.registers(state).rdx, @sizeOf(abi.SubpassBeginInfo)) orelse return self.noteVulkanCommandRefusal(@src().line);
            var begin: abi.RenderPassBeginInfo = undefined;
            var subpass: abi.SubpassBeginInfo = undefined;
            @memcpy(std.mem.asBytes(&begin), guest_begin);
            @memcpy(std.mem.asBytes(&subpass), guest_subpass);
            const guest_render_pass = begin.render_pass;
            const guest_framebuffer = begin.framebuffer;
            if (begin.p_next != null or subpass.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
            begin.render_pass = self.real_vulkan.realRenderPass(begin.render_pass) orelse return self.noteVulkanCommandRefusal(@src().line);
            begin.framebuffer = self.real_vulkan.realFramebuffer(begin.framebuffer) orelse return self.noteVulkanCommandRefusal(@src().line);
            var clears: [32]abi.ClearValue = undefined;
            const clear_address = if (begin.clear_values) |pointer| @intFromPtr(pointer) else 0;
            if (begin.clear_value_count != 0 and !copyGuestStructs(abi.ClearValue, state, clear_address, begin.clear_value_count, &clears)) return self.noteVulkanCommandRefusal(@src().line);
            begin.clear_values = if (begin.clear_value_count == 0) null else &clears;
            self.trackFramebufferTargets(guest_context.registers(state).rdi, guest_framebuffer);
            self.noteCommandPassTarget(guest_context.registers(state).rdi, guest_framebuffer);
            self.trackRenderPassTransfers(guest_context.registers(state).rdi, guest_render_pass, guest_framebuffer);
            if (self.trackedRenderPass(guest_render_pass)) |render_pass| {
                if (render_pass.color_load_clear) {
                    self.noteLoadClearTarget(guest_context.registers(state).rdi, "vkCmdBeginRenderPass2");
                } else {
                    self.noteCommandTargets(guest_context.registers(state).rdi, .none);
                }
            } else {
                self.noteCommandTargets(guest_context.registers(state).rdi, .none);
            }
            self.callNativeVulkanCommand(function, .{ command_buffer, &begin, &subpass });
            self.fsiNoteBeginRenderPass(guest_context.registers(state).rdi, &begin, subpass.contents);
        }
    } else if ((name_hash == vulkanNameHash("vkCmdNextSubpass2") and std.mem.eql(u8, name, "vkCmdNextSubpass2")) or (name_hash == vulkanNameHash("vkCmdNextSubpass2KHR") and std.mem.eql(u8, name, "vkCmdNextSubpass2KHR"))) {
        if (self.real_vulkan.fn_ptrs.cmd_next_subpass2) |function| {
            var begin: abi.SubpassBeginInfo = undefined;
            var end: abi.SubpassEndInfo = undefined;
            if (!copyGuestValue(abi.SubpassBeginInfo, state, guest_context.registers(state).rsi, &begin) or !copyGuestValue(abi.SubpassEndInfo, state, guest_context.registers(state).rdx, &end)) return self.noteVulkanCommandRefusal(@src().line);
            if (begin.p_next != null or end.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
            self.callNativeVulkanCommand(function, .{ command_buffer, &begin, &end });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdEndRenderPass2") and std.mem.eql(u8, name, "vkCmdEndRenderPass2")) or (name_hash == vulkanNameHash("vkCmdEndRenderPass2KHR") and std.mem.eql(u8, name, "vkCmdEndRenderPass2KHR"))) {
        self.clearCommandPassTarget(guest_context.registers(state).rdi);
        if (self.real_vulkan.fn_ptrs.cmd_end_render_pass2) |function| {
            var end: abi.SubpassEndInfo = undefined;
            if (!copyGuestValue(abi.SubpassEndInfo, state, guest_context.registers(state).rsi, &end) or end.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
            self.callNativeVulkanCommand(function, .{ command_buffer, &end });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdEndRenderPass") and std.mem.eql(u8, name, "vkCmdEndRenderPass"))) {
        self.clearCommandPassTarget(guest_context.registers(state).rdi);
        if (self.real_vulkan.fn_ptrs.cmd_end_render_pass) |function| self.callNativeVulkanCommand(function, .{command_buffer});
    } else if ((name_hash == vulkanNameHash("vkCmdCopyBuffer") and std.mem.eql(u8, name, "vkCmdCopyBuffer"))) {
        const src = self.real_vulkan.realBuffer(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        const dst = self.real_vulkan.realBuffer(guest_context.registers(state).rdx) orelse return self.noteVulkanCommandRefusal(@src().line);
        var regions: [64]abi.BufferCopy = undefined;
        if (!copyGuestStructs(abi.BufferCopy, state, guest_context.registers(state).r8, guest_context.registers(state).rcx, &regions)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_copy_buffer) |function| self.callNativeVulkanCommand(function, .{ command_buffer, src, dst, @intCast(guest_context.registers(state).rcx), &regions });
    } else if ((name_hash == vulkanNameHash("vkCmdCopyImage") and std.mem.eql(u8, name, "vkCmdCopyImage"))) {
        const src = self.real_vulkan.realImage(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        const dst = self.real_vulkan.realImage(guest_context.registers(state).rcx) orelse return self.noteVulkanCommandRefusal(@src().line);
        var regions: [64]abi.ImageCopy = undefined;
        if (!copyGuestStructs(abi.ImageCopy, state, guestStackArg(state, 0), guest_context.registers(state).r9, &regions)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_copy_image) |function| {
            self.noteCommandTransfer(guest_context.registers(state).rdi, guest_context.registers(state).rsi, guest_context.registers(state).rcx, .image_copy);
            self.callNativeVulkanCommand(function, .{ command_buffer, src, @intCast(guest_context.registers(state).rdx), dst, @intCast(guest_context.registers(state).r8), @intCast(guest_context.registers(state).r9), &regions });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdCopyBufferToImage") and std.mem.eql(u8, name, "vkCmdCopyBufferToImage"))) {
        const src = self.real_vulkan.realBuffer(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        const dst = self.real_vulkan.realImage(guest_context.registers(state).rdx) orelse return self.noteVulkanCommandRefusal(@src().line);
        var regions: [64]abi.BufferImageCopy = undefined;
        if (!copyGuestStructs(abi.BufferImageCopy, state, guest_context.registers(state).r9, guest_context.registers(state).r8, &regions)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_copy_buffer_to_image) |function| {
            self.noteCommandTransfer(guest_context.registers(state).rdi, 0, guest_context.registers(state).rdx, .buffer_to_image);
            self.callNativeVulkanCommand(function, .{ command_buffer, src, dst, @intCast(guest_context.registers(state).rcx), @intCast(guest_context.registers(state).r8), &regions });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdCopyImageToBuffer") and std.mem.eql(u8, name, "vkCmdCopyImageToBuffer"))) {
        const src = self.real_vulkan.realImage(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        const dst = self.real_vulkan.realBuffer(guest_context.registers(state).rcx) orelse return self.noteVulkanCommandRefusal(@src().line);
        var regions: [64]abi.BufferImageCopy = undefined;
        if (!copyGuestStructs(abi.BufferImageCopy, state, guest_context.registers(state).r9, guest_context.registers(state).r8, &regions)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_copy_image_to_buffer) |function| self.callNativeVulkanCommand(function, .{ command_buffer, src, @intCast(guest_context.registers(state).rdx), dst, @intCast(guest_context.registers(state).r8), &regions });
    } else if ((name_hash == vulkanNameHash("vkCmdBlitImage") and std.mem.eql(u8, name, "vkCmdBlitImage"))) {
        const src = self.real_vulkan.realImage(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        const dst = self.real_vulkan.realImage(guest_context.registers(state).rcx) orelse return self.noteVulkanCommandRefusal(@src().line);
        var regions: [64]abi.ImageBlit = undefined;
        if (!copyGuestStructs(abi.ImageBlit, state, guestStackArg(state, 0), guest_context.registers(state).r9, &regions)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_blit_image) |function| {
            self.noteCommandTransfer(guest_context.registers(state).rdi, guest_context.registers(state).rsi, guest_context.registers(state).rcx, .image_blit);
            self.callNativeVulkanCommand(function, .{ command_buffer, src, @intCast(guest_context.registers(state).rdx), dst, @intCast(guest_context.registers(state).r8), @intCast(guest_context.registers(state).r9), &regions, @intCast(guestStackArg(state, 1)) });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdFillBuffer") and std.mem.eql(u8, name, "vkCmdFillBuffer"))) {
        const buffer = self.real_vulkan.realBuffer(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_fill_buffer) |function| self.callNativeVulkanCommand(function, .{ command_buffer, buffer, guest_context.registers(state).rdx, guest_context.registers(state).rcx, @intCast(guest_context.registers(state).r8) });
    } else if ((name_hash == vulkanNameHash("vkCmdUpdateBuffer") and std.mem.eql(u8, name, "vkCmdUpdateBuffer"))) {
        const buffer = self.real_vulkan.realBuffer(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        const size = guest_context.registers(state).r8;
        var bytes: [65536]u8 = undefined;
        if (!copyGuestBytes(state, guest_context.registers(state).r9, size, &bytes)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_update_buffer) |function| self.callNativeVulkanCommand(function, .{ command_buffer, buffer, guest_context.registers(state).rdx, size, if (size == 0) null else &bytes });
    } else if ((name_hash == vulkanNameHash("vkCmdResolveImage") and std.mem.eql(u8, name, "vkCmdResolveImage"))) {
        const src = self.real_vulkan.realImage(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        const dst = self.real_vulkan.realImage(guest_context.registers(state).rcx) orelse return self.noteVulkanCommandRefusal(@src().line);
        var regions: [64]abi.ImageResolve = undefined;
        if (!copyGuestStructs(abi.ImageResolve, state, guestStackArg(state, 0), guest_context.registers(state).r9, &regions)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_resolve_image) |function| {
            self.noteCommandTransfer(guest_context.registers(state).rdi, guest_context.registers(state).rsi, guest_context.registers(state).rcx, .image_resolve);
            self.callNativeVulkanCommand(function, .{ command_buffer, src, @intCast(guest_context.registers(state).rdx), dst, @intCast(guest_context.registers(state).r8), @intCast(guest_context.registers(state).r9), &regions });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdClearColorImage") and std.mem.eql(u8, name, "vkCmdClearColorImage"))) {
        const image = self.real_vulkan.realImage(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        var value: abi.ClearColorValue = undefined;
        if (!copyGuestStructs(abi.ClearColorValue, state, guest_context.registers(state).rcx, 1, @as(*[1]abi.ClearColorValue, @ptrCast(&value)))) return self.noteVulkanCommandRefusal(@src().line);
        var ranges: [32]abi.ImageSubresourceRange = undefined;
        if (!copyGuestStructs(abi.ImageSubresourceRange, state, guest_context.registers(state).r9, guest_context.registers(state).r8, &ranges)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_clear_color_image) |function| {
            self.noteCommandImageTarget(guest_context.registers(state).rdi, guest_context.registers(state).rsi, .uniform_fill);
            self.callNativeVulkanCommand(function, .{ command_buffer, image, @intCast(guest_context.registers(state).rdx), &value, @intCast(guest_context.registers(state).r8), &ranges });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdClearDepthStencilImage") and std.mem.eql(u8, name, "vkCmdClearDepthStencilImage"))) {
        const image = self.real_vulkan.realImage(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        var value: abi.ClearDepthStencilValue = undefined;
        if (!copyGuestStructs(abi.ClearDepthStencilValue, state, guest_context.registers(state).rcx, 1, @as(*[1]abi.ClearDepthStencilValue, @ptrCast(&value)))) return self.noteVulkanCommandRefusal(@src().line);
        var ranges: [32]abi.ImageSubresourceRange = undefined;
        if (!copyGuestStructs(abi.ImageSubresourceRange, state, guest_context.registers(state).r9, guest_context.registers(state).r8, &ranges)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_clear_depth_stencil_image) |function| {
            self.noteCommandImageTarget(guest_context.registers(state).rdi, guest_context.registers(state).rsi, .uniform_fill);
            self.callNativeVulkanCommand(function, .{ command_buffer, image, @intCast(guest_context.registers(state).rdx), &value, @intCast(guest_context.registers(state).r8), &ranges });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdClearAttachments") and std.mem.eql(u8, name, "vkCmdClearAttachments"))) {
        var attachments: [32]abi.ClearAttachment = undefined;
        var rects: [64]abi.ClearRect = undefined;
        if (!copyGuestStructs(abi.ClearAttachment, state, guest_context.registers(state).rdx, guest_context.registers(state).rsi, &attachments)) return self.noteVulkanCommandRefusal(@src().line);
        if (!copyGuestStructs(abi.ClearRect, state, guest_context.registers(state).r8, guest_context.registers(state).rcx, &rects)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_clear_attachments) |function| {
            self.noteCommandTargets(guest_context.registers(state).rdi, .uniform_fill);
            self.callNativeVulkanCommand(function, .{ command_buffer, @intCast(guest_context.registers(state).rsi), &attachments, @intCast(guest_context.registers(state).rcx), &rects });
        }
    } else if ((name_hash == vulkanNameHash("vkCmdPipelineBarrier") and std.mem.eql(u8, name, "vkCmdPipelineBarrier"))) {
        const memory_count = guest_context.registers(state).r8;
        const memory_address = guest_context.registers(state).r9;
        const buffer_count = guestStackArg(state, 0);
        const buffer_address = guestStackArg(state, 1);
        const image_count = guestStackArg(state, 2);
        const image_address = guestStackArg(state, 3);
        var memory: [32]abi.MemoryBarrier = undefined;
        var buffers: [32]abi.BufferMemoryBarrier = undefined;
        var images: [32]abi.ImageMemoryBarrier = undefined;
        if (!copyGuestStructs(abi.MemoryBarrier, state, memory_address, memory_count, &memory)) return self.noteVulkanCommandRefusal(@src().line);
        if (!copyGuestStructs(abi.BufferMemoryBarrier, state, buffer_address, buffer_count, &buffers)) return self.noteVulkanCommandRefusal(@src().line);
        if (!copyGuestStructs(abi.ImageMemoryBarrier, state, image_address, image_count, &images)) return self.noteVulkanCommandRefusal(@src().line);
        for (memory[0..@as(usize, @intCast(memory_count))]) |*barrier| {
            if (barrier.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
            barrier.p_next = null;
        }
        for (buffers[0..@as(usize, @intCast(buffer_count))]) |*barrier| {
            if (barrier.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
            barrier.buffer = self.real_vulkan.realBuffer(barrier.buffer) orelse return self.noteVulkanCommandRefusal(@src().line);
            barrier.p_next = null;
        }
        if (!self.copyGuestImageBarriers(state, image_address, image_count, &images)) return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_pipeline_barrier) |function| self.callNativeVulkanCommand(function, .{
            command_buffer,
            @intCast(guest_context.registers(state).rsi),
            @intCast(guest_context.registers(state).rdx),
            @intCast(guest_context.registers(state).rcx),
            @intCast(memory_count),
            if (memory_count == 0) null else &memory,
            @intCast(buffer_count),
            if (buffer_count == 0) null else &buffers,
            @intCast(image_count),
            if (image_count == 0) null else &images,
        });
    } else if ((name_hash == vulkanNameHash("vkCmdPipelineBarrier2") and std.mem.eql(u8, name, "vkCmdPipelineBarrier2")) or (name_hash == vulkanNameHash("vkCmdPipelineBarrier2KHR") and std.mem.eql(u8, name, "vkCmdPipelineBarrier2KHR"))) {
        self.forwardPipelineBarrier2(state, command_buffer);
    } else if ((name_hash == vulkanNameHash("vkCmdBeginQuery") and std.mem.eql(u8, name, "vkCmdBeginQuery"))) {
        const pool = self.real_vulkan.realQueryPool(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_begin_query) |function| self.callNativeVulkanCommand(function, .{ command_buffer, pool, @intCast(guest_context.registers(state).rdx), @intCast(guest_context.registers(state).rcx) });
    } else if ((name_hash == vulkanNameHash("vkCmdEndQuery") and std.mem.eql(u8, name, "vkCmdEndQuery"))) {
        const pool = self.real_vulkan.realQueryPool(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_end_query) |function| self.callNativeVulkanCommand(function, .{ command_buffer, pool, @intCast(guest_context.registers(state).rdx) });
    } else if ((name_hash == vulkanNameHash("vkCmdResetQueryPool") and std.mem.eql(u8, name, "vkCmdResetQueryPool"))) {
        const pool = self.real_vulkan.realQueryPool(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_reset_query_pool) |function| self.callNativeVulkanCommand(function, .{ command_buffer, pool, @intCast(guest_context.registers(state).rdx), @intCast(guest_context.registers(state).rcx) });
    } else if ((name_hash == vulkanNameHash("vkCmdCopyQueryPoolResults") and std.mem.eql(u8, name, "vkCmdCopyQueryPoolResults"))) {
        const pool = self.real_vulkan.realQueryPool(guest_context.registers(state).rsi) orelse return self.noteVulkanCommandRefusal(@src().line);
        const buffer = self.real_vulkan.realBuffer(guest_context.registers(state).r8) orelse return self.noteVulkanCommandRefusal(@src().line);
        if (self.real_vulkan.fn_ptrs.cmd_copy_query_pool_results) |function| self.callNativeVulkanCommand(function, .{
            command_buffer,
            pool,
            @intCast(guest_context.registers(state).rdx),
            @intCast(guest_context.registers(state).rcx),
            buffer,
            guest_context.registers(state).r9,
            guestStackArg(state, 0),
            @intCast(guestStackArg(state, 1)),
        });
    } else {
        if (self.vulkan_modeled_command_calls <= 8) machoCapturePrint("macho-processor: Vulkan command ABI not implemented: {s}\n", .{name});
    }
}

pub fn forwardPipelineBarrier2(self: anytype, state: anytype, command_buffer: abi.CommandBuffer) void {
    const dependency_address = guest_context.registers(state).rsi;
    var dependency: abi.DependencyInfo = undefined;
    if (!copyGuestValue(abi.DependencyInfo, state, dependency_address, &dependency) or dependency.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
    if (dependency.memory_barrier_count > 32 or dependency.buffer_memory_barrier_count > 32 or dependency.image_memory_barrier_count > 32) return self.noteVulkanCommandRefusal(@src().line);
    var memory: [32]abi.MemoryBarrier2 = undefined;
    var buffers: [32]abi.BufferMemoryBarrier2 = undefined;
    var images: [32]abi.ImageMemoryBarrier2 = undefined;
    const memory_address = if (dependency.memory_barriers) |pointer| @intFromPtr(pointer) else 0;
    const buffer_address = if (dependency.buffer_memory_barriers) |pointer| @intFromPtr(pointer) else 0;
    const image_address = if (dependency.image_memory_barriers) |pointer| @intFromPtr(pointer) else 0;
    if (!copyGuestStructs(abi.MemoryBarrier2, state, memory_address, dependency.memory_barrier_count, &memory) or
        !copyGuestStructs(abi.BufferMemoryBarrier2, state, buffer_address, dependency.buffer_memory_barrier_count, &buffers) or
        !copyGuestStructs(abi.ImageMemoryBarrier2, state, image_address, dependency.image_memory_barrier_count, &images)) return self.noteVulkanCommandRefusal(@src().line);
    for (memory[0..@as(usize, @intCast(dependency.memory_barrier_count))]) |*barrier| if (barrier.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
    for (buffers[0..@as(usize, @intCast(dependency.buffer_memory_barrier_count))]) |*barrier| {
        if (barrier.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
        barrier.buffer = self.real_vulkan.realBuffer(barrier.buffer) orelse return self.noteVulkanCommandRefusal(@src().line);
    }
    for (images[0..@as(usize, @intCast(dependency.image_memory_barrier_count))]) |*barrier| {
        if (barrier.p_next != null) return self.noteVulkanCommandRefusal(@src().line);
        barrier.image = self.real_vulkan.realImage(barrier.image) orelse return self.noteVulkanCommandRefusal(@src().line);
    }
    dependency.memory_barriers = if (dependency.memory_barrier_count == 0) null else &memory;
    dependency.buffer_memory_barriers = if (dependency.buffer_memory_barrier_count == 0) null else &buffers;
    dependency.image_memory_barriers = if (dependency.image_memory_barrier_count == 0) null else &images;
    if (self.real_vulkan.fn_ptrs.cmd_pipeline_barrier2) |function| self.callNativeVulkanCommand(function, .{ command_buffer, &dependency });
}

pub fn updateDescriptorSets(self: anytype, state: anytype) void {
    self.vulkan_descriptor_update_calls +|= 1;
    var failure: DescriptorUpdateFailureDetails = .{};
    const refusal = self.updateDescriptorSetsNative(state, &failure) orelse return;
    const index = @intFromEnum(refusal);
    self.vulkan_descriptor_update_refusals[index] +|= 1;
    if (self.vulkan_descriptor_update_refusals[index] == 1) {
        // VkWriteDescriptorSet: dstBinding at 24, descriptorType at 36.
        const readable = guest_context.registers(state).rsi != 0 and state.guestMemoryConst(guest_context.registers(state).rdx, 64) != null;
        const first_binding: u64 = if (readable) @as(u32, @truncate(state.read64(guest_context.registers(state).rdx + 24))) else 0;
        const first_type: u64 = if (readable) @as(u32, @truncate(state.read64(guest_context.registers(state).rdx + 32) >> 32)) else 0;
        const guest_thread = if (comptime @hasField(@TypeOf(state.*), "active_guest_thread"))
            guest_context.field(state, "active_guest_thread").*
        else
            0;
        const registers = guest_context.registers(state);
        const guest_rip = if (comptime @hasField(@TypeOf(registers.*), "rip")) registers.rip else 0;
        machoCapturePrint(
            "macho-processor: DESCRIPTOR UPDATE REFUSED: reason={s} writes={d} copies={d} failing_write(index/type/binding/set/resource/element)={d}/{d}/{d}/0x{x}/0x{x}/{d} first_write(type={d} binding={d}) update_call={d} guest_thread=0x{x} rip=0x{x}; the whole vkUpdateDescriptorSets was dropped, so every set it named keeps its previous contents and a shader bound to one reads stale or null resources\n",
            .{ @tagName(refusal), guest_context.registers(state).rsi, guest_context.registers(state).rcx, failure.write_index, failure.descriptor_type, failure.binding, failure.descriptor_set, failure.resource, failure.element_index, first_type, first_binding, self.vulkan_descriptor_update_calls, guest_thread, guest_rip },
        );
    }
}
