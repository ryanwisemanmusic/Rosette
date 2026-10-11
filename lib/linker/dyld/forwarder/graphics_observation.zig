// Split implementation for Forwarder; wrappers keep the public state API stable.
const process = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = process.__ForwarderInternals;
const Forwarder = process.Forwarder;
const DescriptorBindRejectReason = __ForwarderInternals._DescriptorBindRejectReason;
const DescriptorUpdateRefusal = __ForwarderInternals._DescriptorUpdateRefusal;
const GuestFrameEvidence = __ForwarderInternals._GuestFrameEvidence;
const HandleMap = __ForwarderInternals._HandleMap;
const HostWindowDescribeResolver = __ForwarderInternals._HostWindowDescribeResolver;
const PIXEL_PROBE_CONTENT_SAMPLES = __ForwarderInternals._PIXEL_PROBE_CONTENT_SAMPLES;
const PIXEL_PROBE_INITIAL_SAMPLES = __ForwarderInternals._PIXEL_PROBE_INITIAL_SAMPLES;
const PfnVkDestroyInstance = __ForwarderInternals._PfnVkDestroyInstance;
const SwapchainRecord = __ForwarderInternals._SwapchainRecord;
const TargetOverflowKind = __ForwarderInternals._TargetOverflowKind;
const WriteKind = __ForwarderInternals._WriteKind;
const abi = __ForwarderInternals._abi;
const capture_plan = __ForwarderInternals._capture_plan;
const device_loss_diagnostics = __ForwarderInternals._device_loss_diagnostics;
const dlsym = __ForwarderInternals._dlsym;
const exportedOrNone = __ForwarderInternals._exportedOrNone;
const fsi_diagnostics = __ForwarderInternals._fsi_diagnostics;
const gpu_vulkan = __ForwarderInternals._gpu_vulkan;
const machoCapturePrint = __ForwarderInternals._machoCapturePrint;
const native_texture = __ForwarderInternals._native_texture;
const present_pacing = __ForwarderInternals._present_pacing;
const render_diagnostic_frames = __ForwarderInternals._render_diagnostic_frames;
const rosette_gpu = __ForwarderInternals._rosette_gpu;
const std = __ForwarderInternals._std;
const transport_timing = __ForwarderInternals._transport_timing;
const vulkan_capture = __ForwarderInternals._vulkan_capture;
const deinit = Forwarder.deinit;
const describeHostWindow = Forwarder.describeHostWindow;
const destroyFsiZpdSinkResources = Forwarder.destroyFsiZpdSinkResources;
const destroyNativeSurface = Forwarder.destroyNativeSurface;
const destroyPixelProbeResources = Forwarder.destroyPixelProbeResources;
const drainAsyncVulkanCommands = Forwarder.drainAsyncVulkanCommands;
const dumpVulkanCallTrace = Forwarder.dumpVulkanCallTrace;
const dumpVulkanCreateLedger = Forwarder.dumpVulkanCreateLedger;
const dumpVulkanStateSnapshot = Forwarder.dumpVulkanStateSnapshot;
const fsiGuardShutdown = Forwarder.fsiGuardShutdown;
const fsiRasterShutdown = Forwarder.fsiRasterShutdown;
const guestLibrary = Forwarder.guestLibrary;
const materializeNativeVulkanLibrary = Forwarder.materializeNativeVulkanLibrary;
const negotiateRosetteGpuBoundary = Forwarder.negotiateRosetteGpuBoundary;
const observeScreenValidity = Forwarder.observeScreenValidity;
const persistPipelineCache = Forwarder.persistPipelineCache;
const prepareMetalDrawableForSwapchain = Forwarder.prepareMetalDrawableForSwapchain;
const printFsiGuardReport = Forwarder.printFsiGuardReport;
const printFsiPixelFrequencyReport = Forwarder.printFsiPixelFrequencyReport;
const printRobustAccessReport = Forwarder.printRobustAccessReport;
const printVulkanCommandAdmission = Forwarder.printVulkanCommandAdmission;
const registerNativePresenterInPresentChain = Forwarder.registerNativePresenterInPresentChain;
const releaseVulkanHandle = Forwarder.releaseVulkanHandle;
const screenValiditySnapshot = Forwarder.screenValiditySnapshot;
const trackedGraphicsPipeline = Forwarder.trackedGraphicsPipeline;

pub fn printScreenValidity(self: anytype) void {
    const snapshot = if (self.screen_validity.wasObserved())
        self.screen_validity.snapshot()
    else
        self.screenValiditySnapshot(describeHostWindow());
    const evaluation = if (self.screen_validity.wasObserved())
        self.screen_validity.evaluation()
    else
        rosette_gpu.screen_validity.evaluate(snapshot);
    const first_stage = if (evaluation.first_blocking) |stage| stage.label() else "none";
    const first_owner = if (evaluation.first_blocking) |stage| evaluation.record(stage).owner.label() else "none";
    machoCapturePrint(
        "macho-processor: SCREEN VALIDITY CHAIN: verdict={s} -- {s}\n",
        .{ evaluation.verdict.label(), evaluation.verdict.action() },
    );
    machoCapturePrint(
        "macho-processor: SCREEN VALIDITY CHAIN: satisfied={d}/{d} met={d} inferred={d} unmet={d} unknown={d} observations={d} transitions={d} first_blocking={s} owner={s} action={s}\n",
        .{
            evaluation.satisfiedCount(),
            rosette_gpu.screen_validity.stage_count,
            evaluation.metCount(),
            evaluation.inferredCount(),
            evaluation.unmetCount(),
            evaluation.unknownCount(),
            self.screen_validity.observations,
            self.screen_validity.transitions,
            first_stage,
            first_owner,
            evaluation.action(),
        },
    );
    for (evaluation.records) |entry| {
        machoCapturePrint(
            "macho-processor: SCREEN VALIDITY CHAIN:   stage={s} owner={s} status={s} evidence={s} action={s}\n",
            .{ entry.stage.label(), entry.owner.label(), entry.status.label(), entry.evidence, entry.action },
        );
    }
    machoCapturePrint(
        "macho-processor: SCREEN VALIDITY CHAIN:   transport guest_presents={d} acquires={d} target={d} content={d} clear_only={d} without_target={d} without_write={d} failures={d}; native_present(requests/completions)={d}/{d} queue_submits={d}\n",
        .{
            snapshot.guest_presents,
            snapshot.guest_acquires,
            snapshot.presents_with_target,
            snapshot.presents_with_content,
            snapshot.presents_clear_only,
            snapshot.presents_without_target,
            snapshot.presents_without_write,
            snapshot.guest_present_failures,
            snapshot.native_present_requests,
            snapshot.native_present_completions,
            snapshot.native_queue_submits,
        },
    );
    machoCapturePrint(
        "macho-processor: SCREEN VALIDITY CHAIN:   provenance sampled_source_presents={d} propagated_transfer_presents={d} buffer_upload_presents={d} unresolved_source_presents={d}; commands(content/draw/dispatch)={d}/{d}/{d} targets(resolved/offscreen/unknown/overflow)={d}/{d}/{d}/{d}\n",
        .{
            snapshot.presents_with_sampled_source,
            snapshot.presents_with_propagated_transfer,
            snapshot.presents_with_buffer_upload,
            snapshot.presents_with_unresolved_source,
            snapshot.content_commands,
            snapshot.draw_commands,
            snapshot.dispatch_commands,
            snapshot.target_resolved,
            snapshot.target_offscreen,
            snapshot.target_unknown,
            snapshot.target_overflow,
        },
    );
    machoCapturePrint(
        "macho-processor: SCREEN VALIDITY CHAIN:   descriptor image_infos={d} sampled_images={d} unknown_views={d} unknown_sets={d}; resource_transfers={d} buffer_to_image={d} sources_resolved={d} sources_unresolved={d} graph_overflow={d}\n",
        .{
            snapshot.descriptor_image_infos,
            snapshot.descriptor_sampled_images,
            snapshot.descriptor_unknown_image_views,
            snapshot.descriptor_sets_unknown,
            snapshot.resource_transfer_events,
            snapshot.resource_buffer_to_image,
            snapshot.resource_transfer_sources_resolved,
            snapshot.resource_transfer_sources_unresolved,
            snapshot.resource_graph_overflow,
        },
    );
    machoCapturePrint(
        "macho-processor: SCREEN VALIDITY CHAIN:   pixel probes(attempts/successes/failures)={d}/{d}/{d} selected_sample(frame/image/write)={d}/0x{x}/{s} evidence={s} uniform_value=0x{x} hash=0x{x}; extent expected={d}x{d} drawable={d}x{d} layer={d}x{d} observed={} contract_failed={} owner={s} live_swapchains={d} contested={}\n",
        .{
            snapshot.pixel_probe_attempts,
            snapshot.pixel_probe_successes,
            snapshot.pixel_probe_failures,
            snapshot.pixel_sample_frame,
            snapshot.pixel_sample_image,
            if (snapshot.pixel_sample_was_content) "content" else "non_content_or_unknown",
            snapshot.pixel_evidence.label(),
            snapshot.pixel_uniform_value,
            snapshot.pixel_hash,
            snapshot.expected_width,
            snapshot.expected_height,
            snapshot.drawable_width,
            snapshot.drawable_height,
            snapshot.layer_width,
            snapshot.layer_height,
            snapshot.extent_observed,
            snapshot.extent_contract_failed,
            snapshot.drawable_owner.label(),
            snapshot.live_swapchains,
            snapshot.contested_layer,
        },
    );
    machoCapturePrint(
        "macho-processor: SCREEN VALIDITY CHAIN:   window available={} intact={} user_visible={} visible_fraction={d}% break={s}\n",
        .{
            snapshot.window_available,
            snapshot.window_chain_intact,
            snapshot.window_user_visible,
            snapshot.window_visible_fraction_percent,
            if (snapshot.window_break_reason.len != 0) snapshot.window_break_reason else "none",
        },
    );
    if (snapshot.pixel_evidence.isUniform() and snapshot.presents_with_content != 0 and
        snapshot.presents_with_sampled_source == 0 and
        snapshot.presents_with_propagated_transfer == 0 and
        snapshot.presents_with_buffer_upload == 0)
    {
        machoCapturePrint(
            "macho-processor: SCREEN VALIDITY CHAIN:   ACTIONABLE PROVENANCE GAP: the acquired image was marked content, but no presented frame has a resolved sampled-image, image-transfer, or buffer-upload source; inspect the command's actual shader output, descriptor image view, image layout, and render-target write before changing the window\n",
            .{},
        );
    }
    if (evaluation.first_blocking) |stage| {
        machoCapturePrint(
            "macho-processor: SCREEN VALIDITY CHAIN:   FIRST BLOCKING STAGE: {s} owner={s}; {s}\n",
            .{ stage.label(), evaluation.record(stage).owner.label(), evaluation.record(stage).action },
        );
    }
}

pub fn hostWindowFactsUnavailableReason() []const u8 {
    HostWindowDescribeResolver.resolve();
    if (HostWindowDescribeResolver.describe == null) {
        return "the AppKit geometry callback is absent from this process image (the dlsym-only export was dead-stripped or the native bridge is not linked)";
    }
    return "the AppKit geometry callback is linked, but it reports no NSWindow yet";
}

pub fn presentChainVerdict(self: anytype) rosette_gpu.PresentChainVerdict {
    if (self.present_chain_window_break) |window_break| {
        if (window_break != null) return .host_window_broken;
    }
    return self.present_chain.verdict();
}

pub fn noteGuestExecutionProgress(
    self: anytype,
    steps: u64,
    rip: u64,
    thread: u64,
    operation: []const u8,
    frontier_is_bounded: bool,
) void {
    self.guest_frontier_is_bounded = frontier_is_bounded;
    self.guest_progress_steps = steps;
    self.guest_progress_rip = rip;
    self.guest_progress_thread = thread;
    @memset(&self.guest_progress_op, 0);
    self.guest_progress_op_len = @min(operation.len, self.guest_progress_op.len);
    if (self.guest_progress_op_len != 0) {
        @memcpy(self.guest_progress_op[0..self.guest_progress_op_len], operation[0..self.guest_progress_op_len]);
    }
}

pub fn guestFrameEvidence(self: anytype) GuestFrameEvidence {
    var evidence = GuestFrameEvidence{
        .native_present_requests = self.vulkan_real_presents,
        .native_present_completions = self.vulkan_real_present_completions,
        .native_queue_submits = self.vulkan_real_queue_submits,
    };
    for (self.present_chain.swapchains[0..self.present_chain.swapchain_count]) |record| {
        if (record.owner != .guest) continue;
        evidence.presents_with_target +|= record.presents_with_target;
        evidence.presents_with_content +|= record.presents_with_content;
        evidence.presents_clear_only +|= record.presents_clear_only;
        evidence.presents_without_target +|= record.presents_without_target;
        evidence.presents_without_write +|= record.presents_without_write;
    }
    return evidence;
}

pub fn reportPresentChain(self: anytype, full: bool) void {
    const chain = &self.present_chain;
    if (chain.isEmpty() and !full) return;
    // A guest that has not made a single Vulkan call has not failed to
    // present; it has not started. Reporting `no_surface -- nothing can
    // present` at step zero, which is where the first checkpoint lands,
    // puts a verdict at the top of every run log that is true, useless,
    // and indistinguishable in shape from the one that matters.
    if (chain.isEmpty() and self.vulkan_loader_lookup_unique == 0) return;
    if (full) {
        const surface = &self.vulkan_surface_path;
        machoCapturePrint(
            "macho-processor: Vulkan surface path: proc_queries(available/missing)={d}/{d}/{d} surface_dispatches(attempts/successes/failures)={d}/{d}/{d} last(instance/layer/result/surface)=0x{x}/0x{x}/{d}/0x{x}; proc lookup is distinct from the guest's create-surface call\n",
            .{ surface.proc_queries, surface.proc_available, surface.proc_missing, surface.dispatch_attempts, surface.dispatch_successes, surface.dispatch_failures, surface.last_guest_instance, surface.last_layer_token, surface.last_result, surface.last_surface_handle },
        );
    }
    self.configureGraphicsReports();
    const now = transport_timing.nowNs();
    // describeHostWindow dispatches to AppKit's main thread. Previously
    // the unconditional screen observation below bypassed the intended
    // sparse window refresh and paid that rendezvous on every present.
    // Poll once per host second, and immediately at topology/full-report
    // boundaries, while continuing to observe GPU counters every time.
    const topology_changed = self.present_chain_verdict_logged != self.presentChainVerdict();
    if (self.present_chain_window_poll.choose(now, topology_changed, false, full, false) != .none) {
        self.refreshPresentChainWindow();
    }
    // SCREEN VALIDITY is a separate contract from PRESENT CHAIN. It must
    // observe the same report boundary after the window refresh, but it
    // is allowed to keep a uniform-pixel finding even when Vulkan's
    // transport verdict remains healthy.
    _ = self.observeScreenValidity(self.present_chain_window_facts);
    const verdict = self.presentChainVerdict();
    self.notePresentChainVerdict(verdict);
    const report_kind = self.chooseGraphicsReport(now, verdict, full);
    if (report_kind == .none) return;
    self.present_chain_reports +|= 1;
    if (report_kind == .progress) {
        self.printGraphicsProgress(now, verdict);
        self.screen_validity.markReported();
        return;
    }
    machoCapturePrint("macho-processor: GRAPHICS REPORT: kind={s} full_reports={d} progress_reports={d} checks_coalesced={d} interval_ms={d} verbose={}; all forwarding/evidence counters are retained; verbosity never gates failures or GPU work\n", .{
        if (full) "final_or_explicit" else if (self.graphics_report_verbose) "transition_or_verbose_sample" else "state_transition",
        self.graphics_report_cadence.full_reports,
        self.graphics_report_cadence.progress_reports,
        self.graphics_report_cadence.coalesced_checks,
        self.graphics_report_cadence.interval_ns / 1_000_000,
        self.graphics_report_verbose,
    });
    self.drainAsyncVulkanCommands();
    self.printPresentChainBody(verdict);
    // Include successful creates too in the terminal snapshot: a guest
    // shader warning with no bridge failure needs positive publication
    // counts, not the absence of an anomaly-only log, to locate the gap.
    if (full and self.vulkan_create_ledger_count != 0) self.dumpVulkanCreateLedger();
    if (full or self.pixel_probe.successes != 0) {
        const probe = &self.pixel_probe;
        const stats = probe.capture_last_stats;
        machoCapturePrint(
            "macho-processor: FRAME CAPTURE SUMMARY: enabled={} preview={} calls={d} saved={d} previewed={d} failed={d} missing_callback={d} semaphore_handoffs={d} last_frame={d} pixels={d} visible_rgb_gt16={d} bright_rgb_gt64={d} alpha_lt255={d} rgb_different={d} mean_rgb={d}/{d}/{d}; capture is independent evidence, not a Vulkan present or recognizable-title proof\n",
            .{ probe.capture_enabled, probe.preview_enabled, probe.capture_calls, probe.capture_saved, probe.capture_previewed, probe.capture_failures, probe.capture_missing, probe.readback_wait_handoffs, probe.capture_last_frame, stats.pixel_count, stats.visible_pixels, stats.bright_pixels, stats.transparent_pixels, stats.rgb_different_pixels, stats.mean(0), stats.mean(1), stats.mean(2) },
        );
        self.printTransportCosts();
        const ladder = &self.brightness_ladder;
        machoCapturePrint("macho-processor: IMAGE SIGNAL VERDICT: near_black={} raw_pixel_variation={} recognizable_title=unverified exposure_comparison={} preview_interval_ms={d} brightness_loss_stage={s}; healthy transport does not prove image brightness or shader correctness\n", .{ stats.pixel_count != 0 and stats.visible_pixels == 0, stats.rgb_different_pixels != 0, probe.exposure_enabled, probe.preview_interval_ns / 1_000_000, ladder.last_verdict.label() });
        if (ladder.samples != 0 or self.vulkan_image_usage_augmented != 0) {
            machoCapturePrint("macho-processor: BRIGHTNESS LADDER SUMMARY: samples={d} readbacks={d} readback_failures={d} verdicts(unknown/before_gamma_pass/gamma_pass/present_paint/swapchain_signal_present)={d}/{d}/{d}/{d}/{d} white_transitions={d} last_frame={d} last_peaks(swap_texture/guest_output/swapchain)={d}/{d}/{d} pass_source_edges={d} host_images_given_transfer_src={d}; {s}\n", .{ ladder.samples, ladder.readbacks, ladder.readback_failures, ladder.verdict_counts[0], ladder.verdict_counts[1], ladder.verdict_counts[2], ladder.verdict_counts[3], ladder.verdict_counts[4], ladder.white_transitions, ladder.last_frame, ladder.last_peaks[0], ladder.last_peaks[1], ladder.last_peaks[2], self.vulkan_pass_source_edges, self.vulkan_image_usage_augmented, ladder.last_verdict.meaning() });
        }
    }
    self.printScreenValidity();
    self.screen_validity.markReported();
}

pub fn chooseGraphicsReport(self: anytype, now: u64, verdict: rosette_gpu.PresentChainVerdict, full: bool) transport_timing.ReportKind {
    const anomalies = self.graphicsReportAnomalyMask();
    const semantic_changed = self.present_chain_verdict_logged != verdict or
        self.screen_validity.semanticChangedSinceReport() or
        self.graphics_report_anomalies != anomalies or
        self.graphics_report_brightness != self.brightness_ladder.last_verdict or
        self.graphics_report_picture_started != (self.picture_sequence.frames != 0);
    const report_kind = self.graphics_report_cadence.choose(now, semantic_changed, self.screen_validity.changedSinceReport(), full, self.graphics_report_verbose);
    if (report_kind == .none) return .none;
    self.present_chain_verdict_logged = verdict;
    self.graphics_report_anomalies = anomalies;
    self.graphics_report_brightness = self.brightness_ladder.last_verdict;
    self.graphics_report_picture_started = self.picture_sequence.frames != 0;
    return report_kind;
}

pub fn configureGraphicsReports(self: anytype) void {
    if (self.graphics_report_configured) return;
    self.graphics_report_configured = true;
    if (std.c.getenv("ROSETTE_VULKAN_REPORT_VERBOSE")) |raw| {
        const value = std.mem.span(raw);
        self.graphics_report_verbose = std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true");
    }
    if (std.c.getenv("ROSETTE_VULKAN_REPORT_INTERVAL_MS")) |raw| {
        const milliseconds = std.fmt.parseInt(u64, std.mem.span(raw), 10) catch 5000;
        self.graphics_report_cadence.interval_ns = std.math.clamp(milliseconds, 250, 60_000) * 1_000_000;
    }
}

pub fn graphicsReportAnomalyMask(self: anytype) u64 {
    const snapshot = self.screen_validity.snapshot();
    const flags = [_]bool{
        self.native_vulkan_failures != 0,
        snapshot.guest_present_failures != 0,
        self.pixel_probe.failures != 0,
        self.pixel_probe.capture_failures != 0,
        self.vulkan_descriptor_bind_admission.rejected != 0,
        self.vulkan_shadow_upload_failures != 0,
        self.brightness_ladder.readback_failures != 0,
        snapshot.target_unknown != 0,
        snapshot.target_overflow != 0,
        snapshot.resource_graph_overflow != 0,
        self.graphics_extent_contract_failed,
    };
    var mask: u64 = 0;
    for (flags, 0..) |flag, bit| {
        if (flag) mask |= @as(u64, 1) << @intCast(bit);
    }
    return mask;
}

pub fn guestPresentMode(self: anytype) ?u32 {
    var mode: ?u32 = null;
    var most_presents: u64 = 0;
    for (self.present_chain.swapchains[0..self.present_chain.swapchain_count]) |record| {
        if (record.owner != .guest or record.retired or record.presents < most_presents) continue;
        most_presents = record.presents;
        mode = record.present_mode;
    }
    return mode;
}

pub fn provenanceGapLabel(self: anytype) []const u8 {
    return if (self.vulkan_command_draw_calls != 0 or self.vulkan_command_dispatch_calls != 0 or self.present_chain.totalPresentsWithContent() != 0)
        "ACTIONABLE PROVENANCE GAP"
    else
        "STARTUP RESOURCE INVENTORY (no picture work observed)";
}

pub fn printGraphicsProgress(self: anytype, now: u64, verdict: rosette_gpu.PresentChainVerdict) void {
    const snapshot = self.screen_validity.snapshot();
    const evaluation = self.screen_validity.evaluation();
    const first = if (evaluation.first_blocking) |stage| stage.label() else "none";
    machoCapturePrint("macho-processor: GRAPHICS PROGRESS: transport={s} screen={s} first_blocking={s} presents={d} content={d} fills={d} missing(target/write)={d}/{d} native(requests/completions/failures)={d}/{d}/{d} checks_coalesced={d}; complete stage inventory on transitions and exit\n", .{
        @tagName(verdict),                evaluation.verdict.label(),          first,                            snapshot.guest_presents,
        snapshot.presents_with_content,   snapshot.presents_clear_only,        snapshot.presents_without_target, snapshot.presents_without_write,
        snapshot.native_present_requests, snapshot.native_present_completions, self.native_vulkan_failures,      self.graphics_report_cadence.coalesced_checks,
    });
    self.printFrameRates(now);
    self.printGraphicsPacing(now);
    machoCapturePrint("macho-processor: GRAPHICS ROUTE: descriptors(updates/native_writes/binds_forwarded/binds_rejected)={d}/{d}/{d}/{d} presented_sources(sampled/transfer/upload/unresolved)={d}/{d}/{d}/{d} pixels={s} brightness_loss={s} peaks(source/output/swapchain)={d}/{d}/{d}; offscreen targets are intermediate work, not automatically lost pixels\n", .{
        self.vulkan_descriptor_update_calls,             self.vulkan_descriptor_native_writes,
        self.vulkan_descriptor_bind_admission.forwarded, self.vulkan_descriptor_bind_admission.rejected,
        snapshot.presents_with_sampled_source,           snapshot.presents_with_propagated_transfer,
        snapshot.presents_with_buffer_upload,            snapshot.presents_with_unresolved_source,
        snapshot.pixel_evidence.label(),                 self.brightness_ladder.last_verdict.label(),
        self.brightness_ladder.last_peaks[0],            self.brightness_ladder.last_peaks[1],
        self.brightness_ladder.last_peaks[2],
    });
}

pub fn printGraphicsPacing(self: anytype, now: u64) void {
    const snapshot = self.screen_validity.snapshot();
    const observed_mode = self.guestPresentMode();
    const mode = observed_mode orelse std.math.maxInt(u32);
    const completion = self.transport_cost.costs[@intFromEnum(transport_timing.Stage.present_completion)];
    machoCapturePrint("macho-processor: GRAPHICS PACING: classification={s} guest_present_mode={d}/{s} live_guest_mode_observed={} last_content_age_ms={d} completion_wait(calls/mean_us/max_us)={d}/{d}/{d}; immediate mode has no vblank wait; presentation rate is not title/simulation FPS; guest mode and clocks unchanged\n", .{
        transport_timing.pacingLabel(snapshot.guest_presents, snapshot.presents_with_content, snapshot.presents_clear_only, mode),
        mode,
        transport_timing.presentModeLabel(mode),
        observed_mode != null,
        if (self.transport_cost.last_content_ns == 0) 0 else (now -| self.transport_cost.last_content_ns) / 1_000_000,
        completion.calls,
        if (completion.calls == 0) 0 else completion.total_ns / completion.calls / 1_000,
        completion.max_ns / 1_000,
    });
}

pub fn printTransportCosts(self: anytype) void {
    const timing = &self.transport_cost;
    const now = transport_timing.nowNs();
    self.printFrameRates(now);
    self.printGraphicsPacing(now);
    machoCapturePrint("macho-processor: PRESENT CEILING: max_fps={d} interval_ns={d} waits={d} waited_ms={d} refused={d}; host sleeps release the runtime mutex; slow frames receive no additional delay or catch-up credit\n", .{ present_pacing.Ceiling.fps, present_pacing.Ceiling.interval_ns, self.present_ceiling.waits, self.present_ceiling.waited_ns / 1_000_000, self.present_ceiling.refused });
    machoCapturePrint("macho-processor: FRAME HOST COST: present_intervals={d} total_ms={d} mean_ms={d} max_ms={d}; ingress-to-ingress includes guest execution, waits, and delivery, not just Vulkan\n", .{ timing.intervals.calls, timing.intervals.total_ns / 1_000_000, if (timing.intervals.calls == 0) 0 else timing.intervals.total_ns / timing.intervals.calls / 1_000_000, timing.intervals.max_ns / 1_000_000 });
    inline for (std.enums.values(transport_timing.Stage)) |stage| {
        const cost = timing.costs[@intFromEnum(stage)];
        machoCapturePrint("macho-processor: FRAME HOST COST: stage={s} calls={d} total_us={d} max_us={d}; readback and deferred cpu_capture are separately timed; ladder readbacks are included in readback_inclusive\n", .{ @tagName(stage), cost.calls, cost.total_ns / 1_000, cost.max_ns / 1_000 });
    }
    machoCapturePrint("macho-processor: PRESENT COMPLETION: blocking_waits={d} async={d} fence_signals={d} confirmed={d} requests={d} fence_pending={} failures={d}; a present is waited on only until the first picture opens and when the pixel probe reads it back, then proven by a polled fence so the guest never idles for a GPU frame\n", .{ self.present_completion_blocking, self.present_completion_async, self.present_completion_fence_signals, self.present_completion_confirmed, self.vulkan_real_presents, self.present_completion_fence_pending, self.present_completion_failures });
    machoCapturePrint("macho-processor: SHADOW MEMORY CUSTODY: uploads={d} bytes={d} unchanged_skips={d} unmap_publications={d} failures={d}; coherent CPU changes are published without erasing unchanged GPU bytes; noncoherent ranges still require explicit flush\n", .{ self.vulkan_shadow_uploads, self.vulkan_shadow_upload_bytes, self.vulkan_shadow_unchanged, self.vulkan_shadow_unmap_uploads, self.vulkan_shadow_upload_failures });
    machoCapturePrint("macho-processor: NATIVE MEMORY IDENTITY: mappings={d}; PE driver-owned aliases retain exact CPU/GPU byte identity, including same-value stores; flush/invalidate and synchronization remain native Vulkan obligations\n", .{self.vulkan_native_memory_aliases});
    if (vulkan_capture.active) {
        machoCapturePrint("macho-processor: VULKAN CAPTURE: active mode={s} flush_calls={d} flush_failures={d} file={s}; GFXReconstruct writes only the triggered frames, its own log says when\n", .{ @tagName(vulkan_capture.plan.mode), vulkan_capture.flush_calls, vulkan_capture.flush_failures, exportedOrNone("GFXRECON_CAPTURE_FILE") });
    }
    const capture_layer_directory: []const u8 = if (vulkan_capture.layer_directory[0] == 0)
        "<none>"
    else
        std.mem.sliceTo(vulkan_capture.layer_directory[0..], 0);
    machoCapturePrint(
        "macho-processor: VULKAN CAPTURE STATUS: requested={} raw_setting={s} mode={s} state={s} prepared={} active={} layer_directory={s} loader_layer_listed={} loader_paths(VK_LAYER_PATH/VK_ADD_LAYER_PATH)={s}/{s} instance_layer_requested={} instance_create_failures={d} assisted_flush(calls/failures)={d}/{d} capture_file={s} capture_log={s}; FRAME CAPTURE SUMMARY is only a swap-image probe and is not a GFXReconstruct render-pass capture, so fog/exposure attribution remains unverified unless the .gfxr artifact exists\n",
        .{ vulkan_capture.requested, exportedOrNone(capture_plan.environment), @tagName(vulkan_capture.plan.mode), @tagName(vulkan_capture.state), vulkan_capture.prepared, vulkan_capture.active, capture_layer_directory, vulkan_capture.loader_layer_listed, exportedOrNone("VK_LAYER_PATH"), exportedOrNone("VK_ADD_LAYER_PATH"), vulkan_capture.instance_layer_requested, vulkan_capture.instance_create_failures, vulkan_capture.flush_calls, vulkan_capture.flush_failures, exportedOrNone("GFXRECON_CAPTURE_FILE"), exportedOrNone("GFXRECON_LOG_FILE") },
    );
    machoCapturePrint("macho-processor: TEXEL CUSTODY SUMMARY: samples={d} zero_tables={d} unreadable_native_ranges={d} printed={d} xenia_default_ramps={d} programmed_ramps={d} last(format/shape/out_max_rgb/out_7e3_one_rgb/out_mid_rgb)={d}/{s}/({d},{d},{d})/({d},{d},{d})/({d},{d},{d}); RGB tuples are red/green/blue; lookup bytes are checked only for bounded mapped A2B10G10R10 and R16G16_UINT uniform texel views, and a default shape means no title DC_LUT programming reached the ramp\n", .{ self.texel_custody_samples, self.texel_custody_zero, self.texel_custody_missing, self.texel_custody_printed, self.texel_custody_default_samples, self.texel_custody_programmed_samples, self.texel_custody_last_format, self.texel_custody_last_shape.label(), self.texel_custody_last_out_rgb[0][0], self.texel_custody_last_out_rgb[0][1], self.texel_custody_last_out_rgb[0][2], self.texel_custody_last_out_rgb[1][0], self.texel_custody_last_out_rgb[1][1], self.texel_custody_last_out_rgb[1][2], self.texel_custody_last_out_rgb[2][0], self.texel_custody_last_out_rgb[2][1], self.texel_custody_last_out_rgb[2][2] });
}

pub fn printFrameRates(self: anytype, now: u64) void {
    const timing = &self.transport_cost;
    const picture = &self.picture_sequence;
    const recent_fps = timing.recent.activeFpsMilli(timing.last_present_ns, now);
    const accepted_fps = timing.accepted_present_recent.activeFpsMilli(timing.last_accepted_present_ns, now);
    machoCapturePrint("macho-processor: RAW PRESENT TRAFFIC: presents={d} ingress_per_second={d}.{d:0>3} accepted_content_presents={d}; transport counters, NOT picture frames or game FPS\n", .{
        self.vulkan_presents, recent_fps / 1000, recent_fps % 1000, timing.content_frames,
    });
    machoCapturePrint("macho-processor: FRAME HUD RATE: bridge={s} accepted_presents={d} presented_fps={d}.{d:0>3}; successful native WSI cadence, not Xbox simulation FPS\n", .{
        if (self.frame_hud_callback_resolved) "resolved" else "unresolved",
        timing.accepted_presents,
        accepted_fps / 1000,
        accepted_fps % 1000,
    });
    if (picture.frames == 0) {
        machoCapturePrint("macho-processor: CONTENT FRAME: frame=0 state=waiting_for_picture completed_content_without_fresh_detail={d}; frame 1 requires fresh acquired-image RGB detail, accepted native present and queue completion; offscreen writes/clears do not open the epoch\n", .{picture.waiting_content});
        return;
    }
    const picture_fps = picture.recent.activeFpsMilli(picture.last_ns, now);
    machoCapturePrint("macho-processor: FRAME GENERATION RATE: picture_frame={d} picture_fps={d}.{d:0>3} first_observed_picture_raw_present={d} first_observed_image=0x{x} initial_to_picture_ms={d}; counts completed content presents since first OBSERVED RGB detail, not distinct scenes or Xbox simulation FPS; UI fills excluded, black content fades retained\n", .{
        picture.frames,                                                                              picture_fps / 1000, picture_fps % 1000, picture.first_present, picture.first_image,
        if (picture.first_ns == 0) 0 else (picture.first_ns -| timing.first_present_ns) / 1_000_000,
    });
    const cadence = &picture.recent;
    const mean_interval_ns = if (cadence.count == 0) 0 else cadence.total_ns / cadence.count;
    const p95_interval_ns = cadence.p95Ns();
    const max_interval_ns = cadence.maxSampleNs();
    machoCapturePrint("macho-processor: FRAME CADENCE JITTER: completed_content_intervals={d} mean_ms={d}.{d:0>3} p95_ms={d}.{d:0>3} max_ms={d}.{d:0>3}; recent accepted/completed picture gaps; this snapshot does not identify camera-motion timing\n", .{
        cadence.count,
        mean_interval_ns / 1_000_000,
        (mean_interval_ns / 1_000) % 1_000,
        p95_interval_ns / 1_000_000,
        (p95_interval_ns / 1_000) % 1_000,
        max_interval_ns / 1_000_000,
        (max_interval_ns / 1_000) % 1_000,
    });
    machoCapturePrint("macho-processor: FRAME PIXEL PROGRESS: samples={d} byte_hash_changes={d} consecutive_unchanged_samples={d} last_change_age_ms={d}; repeated presents are not proof of scene advancement; sparse readback can miss changes\n", .{
        timing.pixel_samples,                                                                          timing.pixel_changes, timing.pixel_unchanged_run,
        if (timing.last_pixel_change_ns == 0) 0 else (now -| timing.last_pixel_change_ns) / 1_000_000,
    });
}

pub fn notePresentChainVerdict(self: anytype, verdict: rosette_gpu.PresentChainVerdict) void {
    if (verdict == .no_presents and self.guest_frontier_is_bounded) {
        // Not a failure point yet. The guest is inside work that
        // terminates - a module translation, a font atlas, a pipeline
        // build - and cannot be producing frames while it is there.
        // Opening a failure episode against the presentation chain for
        // that names the wrong subsystem, and the episode then stays
        // "still active" for the rest of the run.
        if (!self.present_chain_deferred_reported) {
            self.present_chain_deferred_reported = true;
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN: verdict=no_presents held -- the guest frontier is in bounded work and cannot present from there. No failure episode is opened until it leaves. guest_progress(step={d} rip=0x{x} thread=0x{x} op={s})\n",
                .{
                    self.guest_progress_steps,
                    self.guest_progress_rip,
                    self.guest_progress_thread,
                    self.guest_progress_op[0..self.guest_progress_op_len],
                },
            );
        }
        // Deliberately not falling through to the resolve path: an
        // episode that was open before the guest entered bounded work is
        // not resolved by it, it is paused.
        return;
    } else if (verdict == .no_presents) {
        self.present_chain_deferred_reported = false;
        self.present_chain_no_present_reports +|= 1;
        const report = self.present_chain_no_present_reports;
        if (!self.present_chain_no_present_active) {
            self.present_chain_no_present_active = true;
            self.present_chain_no_present_episode +|= 1;
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN FAILURE POINT BEGIN: episode={d} verdict=no_presents stage={s} devices={d} queues={d} surfaces={d} swapchains={d} images={d} acquires={d} presents={d} queue_submits={d} real_queue_submits={d} command_calls={d} target_submissions={d} native_loader_failures={d} native_vulkan_failures={d} last_opaque={s} guest_progress(step={d} rip=0x{x} thread=0x{x} op={s})\n",
                .{
                    self.present_chain_no_present_episode,
                    @tagName(self.vulkan_presenter_stage),
                    self.vulkan_logical_devices_created,
                    self.vulkan_queues_acquired,
                    self.vulkan_metal_surfaces_created,
                    self.vulkan_swapchains_created,
                    self.vulkan_swapchain_images_enumerated,
                    self.vulkan_images_acquired,
                    self.vulkan_presents,
                    self.vulkan_queue_submits,
                    self.vulkan_real_queue_submits,
                    self.vulkan_modeled_command_calls,
                    self.vulkan_target_submission_events,
                    self.native_vulkan_loader_failures,
                    self.native_vulkan_failures,
                    if (self.last_opaque_vulkan_call_len != 0)
                        self.last_opaque_vulkan_call[0..self.last_opaque_vulkan_call_len]
                    else
                        "<none>",
                    self.guest_progress_steps,
                    self.guest_progress_rip,
                    self.guest_progress_thread,
                    self.guest_progress_op[0..self.guest_progress_op_len],
                },
            );
            // This is intentionally one full snapshot per episode. It
            // includes the bounded Vulkan call ring and the command-shape
            // counters needed to tell "not started" from "not writing".
            self.dumpVulkanStateSnapshot();
        } else if (report == 4 or (report > 4 and (report & (report - 1)) == 0)) {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN FAILURE POINT still active: episode={d} report={d} stage={s} acquires={d} presents={d} submits={d} command_calls={d} target_submissions={d} last_opaque={s} guest_progress(step={d} rip=0x{x} thread=0x{x} op={s})\n",
                .{
                    self.present_chain_no_present_episode,
                    report,
                    @tagName(self.vulkan_presenter_stage),
                    self.vulkan_images_acquired,
                    self.vulkan_presents,
                    self.vulkan_queue_submits,
                    self.vulkan_modeled_command_calls,
                    self.vulkan_target_submission_events,
                    if (self.last_opaque_vulkan_call_len != 0)
                        self.last_opaque_vulkan_call[0..self.last_opaque_vulkan_call_len]
                    else
                        "<none>",
                    self.guest_progress_steps,
                    self.guest_progress_rip,
                    self.guest_progress_thread,
                    self.guest_progress_op[0..self.guest_progress_op_len],
                },
            );
        }
        return;
    }

    if (self.present_chain_no_present_active) {
        self.present_chain_no_present_active = false;
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN FAILURE POINT RESOLVED: episode={d} no_presents_reports={d} resulting_verdict={s} acquires={d} presents={d} with_content={d}\n",
            .{
                self.present_chain_no_present_episode,
                self.present_chain_no_present_reports,
                @tagName(verdict),
                self.present_chain.totalAcquires(),
                self.present_chain.totalPresents(),
                self.present_chain.totalPresentsWithContent(),
            },
        );
    }
}

pub fn refreshPresentChainWindow(self: anytype) void {
    if (self.present_chain.isEmpty()) return;
    self.present_chain_window_facts = describeHostWindow();
    const window = self.present_chain_window_facts orelse return;
    const break_now = window.firstBrokenLink();
    const changed = blk: {
        const previous = self.present_chain_window_break orelse break :blk true;
        if (previous) |previous_text| {
            const current = break_now orelse break :blk true;
            break :blk !std.mem.eql(u8, previous_text, current);
        }
        break :blk break_now != null;
    };
    if (!changed) return;
    self.present_chain_window_break = break_now;
    self.present_chain_verdict_logged = null;
    if (break_now) |broken| {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN: the host window changed and can no longer carry a frame: {s}. Presents keep succeeding regardless; drawable={d}x{d} visible={d} occlusion_visible={} layer_is_view_layer={d}\n",
            .{
                broken,
                @as(i64, @intFromFloat(window.drawable_width)),
                @as(i64, @intFromFloat(window.drawable_height)),
                window.window_visible,
                window.occlusionVisible(),
                window.layer_is_view_layer,
            },
        );
    } else {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN: the host window can carry a frame again: drawable={d}x{d} visible={d} occlusion_visible={}\n",
            .{
                @as(i64, @intFromFloat(window.drawable_width)),
                @as(i64, @intFromFloat(window.drawable_height)),
                window.window_visible,
                window.occlusionVisible(),
            },
        );
    }
}

pub fn printPresentChain(self: anytype) void {
    if (self.present_chain.isEmpty()) return;
    const verdict: rosette_gpu.PresentChainVerdict = blk: {
        if (describeHostWindow()) |window| {
            if (window.firstBrokenLink() != null) break :blk .host_window_broken;
        }
        break :blk self.present_chain.verdict();
    };
    self.drainAsyncVulkanCommands();
    self.printPresentChainBody(verdict);
    self.printScreenValidity();
}

pub fn printPresentChainBody(self: anytype, verdict: rosette_gpu.PresentChainVerdict) void {
    const chain = &self.present_chain;

    machoCapturePrint(
        "macho-processor: PRESENT CHAIN: verdict={s} -- {s}\n",
        .{ @tagName(verdict), verdict.label() },
    );
    if (verdict == .no_presents) {
        // `machoCapturePrint` takes a comptime format, so the two wordings
        // are two calls rather than one selected string.
        if (self.guest_frontier_is_bounded) {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   HELD: no_presents is not yet a finding - the guest frontier is in bounded work and cannot present from there; state follows (episode={d} report={d})\n",
                .{ self.present_chain_no_present_episode, self.present_chain_no_present_reports },
            );
        } else {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   FAILURE POINT: no_presents is a live presentation failure until the first acquired image is submitted; failure evidence follows (episode={d} report={d})\n",
                .{ self.present_chain_no_present_episode, self.present_chain_no_present_reports },
            );
        }
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   guest_progress: step={d} rip=0x{x} thread=0x{x} op={s} (this is the guest frontier after the last Vulkan call)\n",
            .{
                self.guest_progress_steps,
                self.guest_progress_rip,
                self.guest_progress_thread,
                self.guest_progress_op[0..self.guest_progress_op_len],
            },
        );
    }

    if (describeHostWindow()) |window| {
        const user_visible = window.window_visible != 0 and window.window_on_screen != 0 and
            window.window_miniaturized == 0 and window.view_hidden_or_ancestor == 0 and
            window.layer_hidden == 0 and window.drawable_width > 0 and window.drawable_height > 0;
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   window=0x{x} frame={d}x{d}@{d},{d} visible={d} user_visible={} on_screen={d} miniaturized={d} occlusion_visible={} key={d} alpha={d:.2} backing_scale={d:.2}\n",
            .{
                window.window,
                @as(i64, @intFromFloat(window.window_width)),
                @as(i64, @intFromFloat(window.window_height)),
                @as(i64, @intFromFloat(window.window_x)),
                @as(i64, @intFromFloat(window.window_y)),
                window.window_visible,
                user_visible,
                window.window_on_screen,
                window.window_miniaturized,
                window.occlusionVisible(),
                window.window_key,
                window.window_alpha,
                window.backing_scale,
            },
        );
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   view=0x{x} size={d}x{d} wants_layer={d} hidden={d} hidden_or_ancestor={d} view_layer=0x{x}\n",
            .{
                window.view,
                @as(i64, @intFromFloat(window.view_width)),
                @as(i64, @intFromFloat(window.view_height)),
                window.view_wants_layer,
                window.view_hidden,
                window.view_hidden_or_ancestor,
                window.view_layer,
            },
        );
        const logical_view_width: i64 = @intFromFloat(window.view_width);
        const logical_view_height: i64 = @intFromFloat(window.view_height);
        const logical_layer_width: i64 = @intFromFloat(window.layer_width);
        const logical_layer_height: i64 = @intFromFloat(window.layer_height);
        const logical_window_locked = logical_view_width == 1280 and
            logical_view_height == 720 and logical_layer_width == 1280 and
            logical_layer_height == 720;
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   window contract: mode=EXACT_LOGICAL_CONTENT_POINTS required=1280x720 view={d}x{d} layer_bounds={d}x{d} status={s} drawable_pixels_are_independent=true backing_scale={d:.2} action={s}\n",
            .{
                logical_view_width,
                logical_view_height,
                logical_layer_width,
                logical_layer_height,
                if (logical_window_locked) "met" else "unmet",
                window.backing_scale,
                if (logical_window_locked)
                    "keep the fixed content contract and inspect drawable pixels separately"
                else
                    "repair the AppKit content/view bounds to 1280x720; do not derive them from backing scale or drawable pixels",
            },
        );
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   layer=0x{x} bounds={d}x{d} drawable={d}x{d} scale={d:.2} is_view_layer={d} hidden={d} opaque={d} device=0x{x} max_drawables={d} pixel_format={d} drawable_owner={s}\n",
            .{
                window.metal_layer,
                @as(i64, @intFromFloat(window.layer_width)),
                @as(i64, @intFromFloat(window.layer_height)),
                @as(i64, @intFromFloat(window.drawable_width)),
                @as(i64, @intFromFloat(window.drawable_height)),
                window.contents_scale,
                window.layer_is_view_layer,
                window.layer_hidden,
                window.layer_opaque,
                window.layer_device,
                window.maximum_drawable_count,
                window.layer_pixel_format,
                if (self.metal_drawable_yielded) "vulkan_swapchain" else "rosette_window_bridge",
            },
        );
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   drawable contract: mode=EXACT default=1280x720 pixels preflight=before_vkCreateSwapchainKHR attempts/successes/failures={d}/{d}/{d} last_prepared={d}x{d} owner={s} contract_failed={} contract_failures={d}; contentsScale={d:.2} is pinned to 1.0 during strict 720p admission (backing_scale={d:.2})\n",
            .{ self.metal_drawable_prepare_attempts, self.metal_drawable_prepare_successes, self.metal_drawable_prepare_failures, self.metal_drawable_prepared_width, self.metal_drawable_prepared_height, @tagName(self.drawable_owner), self.graphics_extent_contract_failed, self.graphics_extent_contract_failures, window.contents_scale, window.backing_scale },
        );
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   screen=0x{x} count={d} visible_frame={d}x{d}@{d},{d} window_inside_it={d}%\n",
            .{
                window.screen,
                window.screen_count,
                @as(i64, @intFromFloat(window.screen_visible_width)),
                @as(i64, @intFromFloat(window.screen_visible_height)),
                @as(i64, @intFromFloat(window.screen_visible_x)),
                @as(i64, @intFromFloat(window.screen_visible_y)),
                window.visibleFractionPercent(),
            },
        );
        // The layer, the swapchain and the view have to agree on one
        // size or the compositor is scaling something. MoltenVK derives
        // a swapchain's extent from the layer's drawableSize at create
        // time, so a later change to the drawable leaves the two saying
        // different things and nothing reports an error.
        for (chain.swapchains[0..chain.swapchain_count]) |swapchain| {
            if (swapchain.retired or swapchain.layer != window.metal_layer) continue;
            if (swapchain.width == 0 or swapchain.height == 0) continue;
            const drawable_width: u32 = @intFromFloat(@max(window.drawable_width, 0));
            const drawable_height: u32 = @intFromFloat(@max(window.drawable_height, 0));
            if (swapchain.width == drawable_width and swapchain.height == drawable_height) continue;
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   GEOMETRY DISAGREEMENT: swapchain 0x{x} ({s}) is {d}x{d} and its CAMetalLayer's drawableSize is {d}x{d}. The layer vends drawables at its own size; a swapchain image of a different size is scaled or rejected, and the driver reports success either way\n",
                .{
                    swapchain.handle,
                    swapchain.owner.label(),
                    swapchain.width,
                    swapchain.height,
                    drawable_width,
                    drawable_height,
                },
            );
        }
        if (window.placementAdvisory()) |advisory| {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   WINDOW PLACEMENT: {s}. Frame {d}x{d} at {d},{d}; the screen's visible area is {d}x{d} at {d},{d}\n",
                .{
                    advisory,
                    @as(i64, @intFromFloat(window.window_width)),
                    @as(i64, @intFromFloat(window.window_height)),
                    @as(i64, @intFromFloat(window.window_x)),
                    @as(i64, @intFromFloat(window.window_y)),
                    @as(i64, @intFromFloat(window.screen_visible_width)),
                    @as(i64, @intFromFloat(window.screen_visible_height)),
                    @as(i64, @intFromFloat(window.screen_visible_x)),
                    @as(i64, @intFromFloat(window.screen_visible_y)),
                },
            );
        }
        if (window.firstBrokenLink()) |broken| {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   HOST WINDOW BREAK: {s}. Vulkan reports success for this; nothing downstream can compensate for it\n",
                .{broken},
            );
        }
    } else {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   host window geometry unavailable: {s}\n",
            .{hostWindowFactsUnavailableReason()},
        );
    }

    for (chain.surfaces[0..chain.surface_count]) |surface| {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   surface=0x{x} layer=0x{x} owner={s}{s}\n",
            .{ surface.handle, surface.layer, surface.owner.label(), if (surface.retired) " retired" else "" },
        );
    }
    for (chain.swapchains[0..chain.swapchain_count]) |swapchain| {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   swapchain=0x{x} surface=0x{x} layer=0x{x} owner={s}{s} extent={d}x{d} format={d} present_mode={d} images={d}/{d} requested_usage=0x{x} actual_usage=0x{x} acquires={d} presents={d} with_target={d} with_content={d} clear_only={d} buffer_uploads={d} without_target={d} without_write={d} failures={d} last_result={d} last_image={d} last_target=0x{x}\n",
            .{
                swapchain.handle,
                swapchain.surface,
                swapchain.layer,
                swapchain.owner.label(),
                if (swapchain.retired) " retired" else "",
                swapchain.width,
                swapchain.height,
                swapchain.format,
                swapchain.present_mode,
                swapchain.image_count,
                swapchain.actual_image_count,
                swapchain.requested_image_usage,
                swapchain.image_usage,
                swapchain.acquires,
                swapchain.presents,
                swapchain.presents_with_target,
                swapchain.presents_with_content,
                swapchain.presents_clear_only,
                swapchain.presents_with_buffer_upload,
                swapchain.presents_without_target,
                swapchain.presents_without_write,
                swapchain.present_failures,
                swapchain.last_present_result,
                swapchain.last_image_index,
                swapchain.last_target_image,
            },
        );
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   swapchain=0x{x} last_write={s} pixel={s} pixel_uniform=0x{x} pixel_sample(frame/image/write)={d}/0x{x}/{s} content_sample(frame/image/evidence)={d}/0x{x}/{s} shows_detail={}\n",
            .{
                swapchain.handle,
                swapchain.last_write_kind.label(),
                swapchain.pixel_evidence.label(),
                swapchain.pixel_uniform_value,
                swapchain.pixel_probe_frame,
                swapchain.pixel_probe_image,
                swapchain.pixel_probe_write_kind.label(),
                swapchain.pixel_content_probe_frame,
                swapchain.pixel_content_probe_image,
                swapchain.pixel_content_probe_evidence.label(),
                swapchain.pixel_evidence.showsDetail(),
            },
        );
    }
    const guest_presents = chain.totalPresents();
    const guest_presents_with_content = chain.totalPresentsWithContent();
    if (guest_presents != 0 or self.vulkan_real_presents != 0 or self.pixel_probe.successes != 0) {
        var latest_pixel = rosette_gpu.PresentPixelEvidence.unprobed;
        var latest_pixel_frame: u64 = 0;
        var latest_pixel_image: u64 = 0;
        var latest_pixel_write_kind: WriteKind = .none;
        var latest_content_pixel = rosette_gpu.PresentPixelEvidence.unprobed;
        var latest_content_pixel_frame: u64 = 0;
        var latest_content_pixel_image: u64 = 0;
        for (chain.swapchains[0..chain.swapchain_count]) |swapchain| {
            if (swapchain.pixel_probe_frame >= latest_pixel_frame and swapchain.pixel_probe_frame != 0) {
                latest_pixel = swapchain.pixel_evidence;
                latest_pixel_frame = swapchain.pixel_probe_frame;
                latest_pixel_image = swapchain.pixel_probe_image;
                latest_pixel_write_kind = swapchain.pixel_probe_write_kind;
            }
            if (swapchain.pixel_content_probe_frame >= latest_content_pixel_frame and swapchain.pixel_content_probe_frame != 0) {
                latest_content_pixel = swapchain.pixel_content_probe_evidence;
                latest_content_pixel_frame = swapchain.pixel_content_probe_frame;
                latest_content_pixel_image = swapchain.pixel_content_probe_image;
            }
        }
        if (guest_presents_with_content != 0 and latest_content_pixel_frame != 0) {
            latest_pixel = latest_content_pixel;
            latest_pixel_frame = latest_content_pixel_frame;
            latest_pixel_image = latest_content_pixel_image;
            latest_pixel_write_kind = .content;
        }
        const guest_presents_clear_only = chain.totalPresentsClearOnly();
        // `transport_observed` used to cover two states that send a
        // reader to opposite places: a frame whose content nothing has
        // read back yet, and a frame that provably had no content in it.
        // The 2026-09-12 run was the second and was reported as the
        // first.
        const frame_status = if (guest_presents_with_content != 0 and
            latest_content_pixel_frame != 0 and self.vulkan_real_present_completions != 0)
            if (latest_pixel.showsDetail())
                "proven_guest_content"
            else if (latest_pixel == .unavailable)
                "content_probe_unavailable"
            else
                "proven_transport_uniform_pixels"
        else if (guest_presents_with_content != 0)
            "transport_observed_content_not_yet_proven"
        else if (guest_presents_clear_only != 0)
            "transport_proven_frames_are_fills_only"
        else if (guest_presents != 0 or self.vulkan_real_presents != 0)
            "transport_observed_content_not_yet_proven"
        else
            "probe_only";
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   FRAME EVIDENCE: status={s} guest_presents={d} acquired_image_writes={d} acquired_image_fills={d} pixel_probe_successes={d} latest_pixel={s} sample_frame={d} sample_image=0x{x} sample_write={s} native_present_requests={d} native_present_completions={d} native_queue_submits={d}\n",
            .{
                frame_status,
                guest_presents,
                guest_presents_with_content,
                guest_presents_clear_only,
                self.pixel_probe.successes,
                latest_pixel.label(),
                latest_pixel_frame,
                latest_pixel_image,
                latest_pixel_write_kind.label(),
                self.vulkan_real_presents,
                self.vulkan_real_present_completions,
                self.vulkan_real_queue_submits,
            },
        );
        if (guest_presents_clear_only != 0 and guest_presents_with_content == 0) {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   FRAME EVIDENCE: every presented frame's only write was a fill ({d} of them, {d} draw/dispatch/copy marks recorded against any command buffer). The window is showing exactly what the guest put in it, which is one colour. This is the guest's progress, not a break in the bridge: look for whether the title reached a swap, not for a lost frame\n",
                .{ guest_presents_clear_only, self.vulkan_command_content_marks },
            );
        }
        if (guest_presents_with_content != 0 and self.pixel_probe.successes != 0 and !latest_pixel.showsDetail()) {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   FRAME EVIDENCE: native completion and acquired-image content are proven, but readback is {s}; this is transport proof without visible detail, so inspect descriptor/transfer provenance below before blaming the window\n",
                .{latest_pixel.label()},
            );
        }
    }
    if (self.target_attribution_events != 0 or self.target_offscreen_events != 0 or self.target_unknown_events != 0 or self.target_overflow_events != 0) {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   target_attribution=resolved={d} offscreen={d} unknown={d} overflow={d} (a draw is content only when it names the acquired swapchain image)\n",
            .{ self.target_attribution_events, self.target_offscreen_events, self.target_unknown_events, self.target_overflow_events },
        );
        for (std.enums.values(TargetOverflowKind), 0..) |kind, index| {
            const count = self.target_overflow_by_kind[index];
            if (count == 0) continue;
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   target_overflow_kind={s} count={d}; this is provenance-ledger pressure, not a rejected Vulkan command\n",
                .{ kind.label(), count },
            );
        }
    }
    if (self.graphics_state_trace_configured or self.graphics_state_trace_draws != 0 or self.graphics_state_trace_push_constants != 0) {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   graphics_state_trace=enabled:{} draws={d} push_constants={d} printed={d} missing_viewport={d} missing_scissor={d} bad_viewport={d} bad_scissor={d} rect_candidates={d} rect_non_candidates={d} bad_rect={d} topology_mismatch={d} unknown_pipeline={d} pipeline_overflow={d}; bad_rect/topology only use the strict presenter-shape candidate, while rect_non_candidates are ordinary offset-zero pushes; topology 3=triangle_list 4=triangle_strip\n",
            .{
                self.graphics_state_trace_enabled,
                self.graphics_state_trace_draws,
                self.graphics_state_trace_push_constants,
                self.graphics_state_trace_printed,
                self.graphics_state_trace_missing_viewport,
                self.graphics_state_trace_missing_scissor,
                self.graphics_state_trace_bad_viewport,
                self.graphics_state_trace_bad_scissor,
                self.graphics_state_trace_rect_candidates,
                self.graphics_state_trace_rect_non_candidates,
                self.graphics_state_trace_bad_rect,
                self.graphics_state_trace_topology_mismatch,
                self.graphics_state_trace_unknown_pipeline,
                self.graphics_state_trace_pipeline_overflow,
            },
        );
    }
    if (self.guest_output_topology_repair_configured or self.graphics_topology_repair_candidates != 0 or
        self.graphics_topology_repairs != 0 or self.graphics_topology_repair_create_failures != 0)
    {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   guest_output_topology_repair=enabled:{} candidates={d} pipeline_twins={d} twin_failures={d} draws_repaired={d} bind_failures={d}; a repair means a strict four-vertex/16-byte-rectangle draw was rebound from triangle_list to triangle_strip\n",
            .{ self.guest_output_topology_repair_enabled, self.graphics_topology_repair_candidates, self.graphics_topology_repair_pipeline_creations, self.graphics_topology_repair_create_failures, self.graphics_topology_repairs, self.graphics_topology_repair_bind_failures },
        );
    }
    self.printFsiGuardReport();
    self.printRobustAccessReport();
    self.printFsiPixelFrequencyReport();
    self.printNativeTextureReport();
    if (self.rect_expand_configured or self.rect_expand_shaders_rewritten != 0) {
        machoCapturePrint(
            "macho-processor: RECT EXPAND: enabled={} shaders(rewritten/unused_cull_distance_removed/transform_refused/non_vertex_skipped/already_expanded_skipped)={d}/{d}/{d}/{d}/{d} last_transform_refusal={s} pipelines(marked/unmarked)={d}/{d} draws_tagged={d} declined_foreign_index={d} builtin_index_buffer=0x{x} overflow(modules/pipelines)={d}/{d} driver_rejections={d}; a Xenos rectangle list is three vertices with the fourth corner derived, and Xenia's Vulkan backend selects a vertex-shader fallback its SPIR-V translator never implemented. draws_tagged counts the draws whose fourth corner this bridge shaded, and declined_foreign_index the rectangle-shaped draws on a rewritten pipeline whose indices were a guest strip's, not the built-in expansion buffer's; zero tagged with rewritten shaders means the rectangle pipelines were never recognised, not that the title drew no rectangles\n",
            .{
                self.rect_expand_enabled,
                self.rect_expand_shaders_rewritten,
                self.rect_expand_shaders_cull_distance_stripped,
                self.rect_expand_shaders_refused,
                self.rect_expand_shaders_skipped_non_vertex,
                self.rect_expand_shaders_skipped_already_expanded,
                self.rect_expand_last_refusal.label(),
                self.rect_expand_pipelines_marked,
                self.rect_expand_pipelines_unmarked,
                self.rect_expand_draws_tagged,
                self.rect_expand_draws_declined_foreign_index,
                self.rect_expand_builtin_index_buffer,
                self.rect_expand_module_overflow,
                self.rect_expand_pipeline_overflow,
                self.rect_expand_module_rejections,
            },
        );
        if (self.rect_expand_first_foreign_index_sample) |sample| {
            machoCapturePrint(
                "macho-processor: RECT EXPAND FOREIGN INDEX SAMPLE: command_buffer=0x{x} pipeline=0x{x} index_buffer=0x{x} offset={d} index_type={d} index_count={d} first_index={d} vertex_offset={d} instances={d}; one rectangle-shaped draw declined because its index binding was not Xenia's built-in expansion buffer at offset zero with UINT32 indices\n",
                .{
                    sample.command_buffer,
                    sample.pipeline,
                    sample.index_buffer,
                    sample.index_offset,
                    sample.index_type,
                    sample.index_count,
                    sample.first_index,
                    sample.vertex_offset,
                    sample.instance_count,
                },
            );
        }
        if (self.rect_expand_shaders_refused != 0) {
            const cull_site = self.rect_expand_last_cull_distance_site orelse gpu_vulkan.rect_list_expand.CullDistanceSite{};
            machoCapturePrint(
                "macho-processor: RECT EXPAND REFUSAL DETAIL: last_reason={s} module=0x{x} spirv_hash=0x{x} source_bytes={d} allocation_failures={d} cull_site_present={} output_variable=0x{x} interface_type=0x{x} member_index={d}; member_index=4294967295 means BuiltIn was attached directly to the output variable; refusals preserve the guest shader unchanged\n",
                .{
                    self.rect_expand_last_refusal.label(),
                    self.rect_expand_last_refusal_module,
                    self.rect_expand_last_refusal_hash,
                    self.rect_expand_last_refusal_bytes,
                    self.rect_expand_allocation_failures,
                    self.rect_expand_last_cull_distance_site != null,
                    cull_site.variable,
                    cull_site.interface_type,
                    cull_site.member_index orelse std.math.maxInt(u32),
                },
            );
            for (std.enums.values(gpu_vulkan.rect_list_expand.Refusal), 0..) |reason, index| {
                const count = self.rect_expand_refusal_counts[index];
                if (count == 0) continue;
                machoCapturePrint(
                    "macho-processor: RECT EXPAND REFUSAL REASON: reason={s} count={d}\n",
                    .{ reason.label(), count },
                );
            }
        }
        if (self.rect_expand_allocation_failures != 0) {
            machoCapturePrint(
                "macho-processor: RECT EXPAND ALLOCATION FAILURE: count={d}; last module=0x{x} spirv_hash=0x{x} bytes={d}\n",
                .{ self.rect_expand_allocation_failures, self.rect_expand_last_refusal_module, self.rect_expand_last_refusal_hash, self.rect_expand_last_refusal_bytes },
            );
        }
        if (self.rect_expand_module_rejections != 0) {
            machoCapturePrint(
                "macho-processor: RECT EXPAND DRIVER REJECTION: result={d} module=0x{x} spirv_hash=0x{x} source_bytes={d}; the unchanged guest module was retried\n",
                .{ self.rect_expand_last_driver_rejection_result, self.rect_expand_last_driver_rejection_module, self.rect_expand_last_driver_rejection_hash, self.rect_expand_last_driver_rejection_bytes },
            );
        }
    }
    self.printVulkanCommandAdmission();
    if (self.vulkan_descriptor_update_calls != 0 or
        self.vulkan_descriptor_template_update_calls != 0 or
        self.vulkan_descriptor_push_calls != 0 or
        self.vulkan_descriptor_bind_admission.entries != 0 or
        self.vulkan_descriptor_bind_calls != 0 or
        self.vulkan_descriptor_image_infos_observed != 0)
    {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   descriptor_route=updates={d} template_updates={d} push_calls={d} image_infos={d} unknown_image_views={d} bind_forwarded={d} sets_bound={d} sets_resolved={d} sets_unknown={d} late_set_resolutions={d} sampled_images_recorded={d} sampled_unknown_commands={d}; descriptor sets are resolved again at queue submission\n",
            .{
                self.vulkan_descriptor_update_calls,
                self.vulkan_descriptor_template_update_calls,
                self.vulkan_descriptor_push_calls,
                self.vulkan_descriptor_image_infos_observed,
                self.vulkan_descriptor_unknown_image_views,
                self.vulkan_descriptor_bind_calls,
                self.vulkan_descriptor_sets_bound,
                self.vulkan_descriptor_sets_resolved,
                self.vulkan_descriptor_sets_unknown,
                self.vulkan_descriptor_late_resolutions,
                self.vulkan_descriptor_sampled_images_recorded,
                self.vulkan_descriptor_sampled_unknown,
            },
        );
        var refused_total: u64 = 0;
        for (self.vulkan_descriptor_update_refusals) |count| refused_total +|= count;
        machoCapturePrint("macho-processor: PRESENT CHAIN:   descriptor_update_refusals={d}", .{refused_total});
        for (self.vulkan_descriptor_update_refusals, 0..) |count, index| {
            if (count != 0) machoCapturePrint(" {s}={d}", .{ @tagName(@as(DescriptorUpdateRefusal, @enumFromInt(index))), count });
        }
        machoCapturePrint("; a refused update leaves its sets holding their previous resources, which is a uniform or stale picture with every command forwarded\n", .{});
        machoCapturePrint("macho-processor: PRESENT CHAIN:   descriptor_update_admission=entries:{d},forwarded:{d},refused:{d},native_writes:{d},native_copies:{d}; vkUpdateDescriptorSets returns void: native invocation is not driver-validation proof\n", .{ self.vulkan_descriptor_update_calls, self.vulkan_descriptor_update_forwarded, refused_total, self.vulkan_descriptor_native_writes, self.vulkan_descriptor_native_copies });
        const bind_admission = &self.vulkan_descriptor_bind_admission;
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   descriptor_bind_admission=entries:{d},forwarded:{d},rejected:{d} rejects(device_lost/command_buffer/layout/set_count/set_array/set_handle/dynamic_count/dynamic_array/native_fn)={d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}/{d} last(reason/command_buffer/layout/set_count/sets/dynamic_count/dynamic_offsets/unmapped_handle)={s}/0x{x}/0x{x}/{d}/0x{x}/{d}/0x{x}/0x{x}; only forwarded binds reached MoltenVK\n",
            .{
                bind_admission.entries,
                bind_admission.forwarded,
                bind_admission.rejected,
                bind_admission.rejected_by_reason[@intFromEnum(DescriptorBindRejectReason.device_lost)],
                bind_admission.rejected_by_reason[@intFromEnum(DescriptorBindRejectReason.command_buffer_unmapped)],
                bind_admission.rejected_by_reason[@intFromEnum(DescriptorBindRejectReason.pipeline_layout_unmapped)],
                bind_admission.rejected_by_reason[@intFromEnum(DescriptorBindRejectReason.set_count_exceeds_limit)],
                bind_admission.rejected_by_reason[@intFromEnum(DescriptorBindRejectReason.descriptor_set_array_unreadable)],
                bind_admission.rejected_by_reason[@intFromEnum(DescriptorBindRejectReason.descriptor_set_unmapped)],
                bind_admission.rejected_by_reason[@intFromEnum(DescriptorBindRejectReason.dynamic_offset_count_exceeds_limit)],
                bind_admission.rejected_by_reason[@intFromEnum(DescriptorBindRejectReason.dynamic_offset_array_unreadable)],
                bind_admission.rejected_by_reason[@intFromEnum(DescriptorBindRejectReason.native_entry_point_missing)],
                @tagName(bind_admission.last_reason),
                bind_admission.last_command_buffer,
                bind_admission.last_layout,
                bind_admission.last_set_count,
                bind_admission.last_sets,
                bind_admission.last_dynamic_count,
                bind_admission.last_dynamic_offsets,
                bind_admission.last_unmapped_handle,
            },
        );
        if (self.vulkan_descriptor_image_infos_observed != 0 and
            bind_admission.entries == 0 and
            self.vulkan_descriptor_push_calls == 0 and
            self.vulkan_descriptor_sampled_images_recorded == 0)
        {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   {s}: {d} image-descriptor write(s), but no vkCmdBindDescriptorSets/push-descriptor command or submitted sampled image. Unused startup resources alone are not a forwarding failure; with draw/dispatch/content work, follow the missing command edge before blaming shader output\n",
                .{ self.provenanceGapLabel(), self.vulkan_descriptor_image_infos_observed },
            );
        } else if (bind_admission.entries != 0 and
            bind_admission.forwarded == 0 and
            self.vulkan_descriptor_push_calls == 0)
        {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   ACTIONABLE DESCRIPTOR BIND WALL: {d} vkCmdBindDescriptorSets call(s) reached Rosette and all were refused before MoltenVK; last_reason={s} last_unmapped_handle=0x{x}. Repair that exact handle/pointer admission edge before investigating shader output\n",
                .{ bind_admission.entries, @tagName(bind_admission.last_reason), bind_admission.last_unmapped_handle },
            );
        } else if (bind_admission.forwarded != 0 and
            self.vulkan_descriptor_sampled_images_recorded == 0 and
            self.vulkan_descriptor_image_infos_observed != 0)
        {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   ACTIONABLE DESCRIPTOR PROVENANCE WALL: {d} descriptor bind(s) reached MoltenVK, but none resolved a sampled image for submitted work; inspect descriptor-set tracking and the late submission-time resolution edge\n",
                .{bind_admission.forwarded},
            );
        }
    }
    if (chain.resource_submission_events != 0 or chain.resource_transfer_events != 0 or chain.totalPresentsWithSampledSource() != 0 or chain.totalPresentsWithPropagatedTransfer() != 0 or chain.totalPresentsWithUnresolvedSource() != 0 or chain.totalPresentsWithBufferUpload() != 0) {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   resource_route=submissions={d} images={d} image_transfers={d} transfer_sources_resolved={d} transfer_sources_unresolved={d} graph_overflow={d} kinds=image_copy:{d},buffer_to_image:{d},image_blit:{d},image_resolve:{d},render_pass_resolve:{d} sampled_source_presents={d} propagated_transfer_presents={d} buffer_upload_presents={d} unresolved_source_presents={d}; descriptor identities are observed at bind/update time and committed at queue submission\n",
            .{
                chain.resource_submission_events,
                chain.resource_image_count,
                chain.resource_transfer_events,
                chain.resource_transfer_resolved,
                chain.resource_transfer_unresolved,
                chain.resource_image_overflow,
                chain.resource_transfer_kind_counts[@intFromEnum(rosette_gpu.PresentTransferKind.image_copy)],
                chain.resource_transfer_kind_counts[@intFromEnum(rosette_gpu.PresentTransferKind.buffer_to_image)],
                chain.resource_transfer_kind_counts[@intFromEnum(rosette_gpu.PresentTransferKind.image_blit)],
                chain.resource_transfer_kind_counts[@intFromEnum(rosette_gpu.PresentTransferKind.image_resolve)],
                chain.resource_transfer_kind_counts[@intFromEnum(rosette_gpu.PresentTransferKind.render_pass_resolve)],
                chain.totalPresentsWithSampledSource(),
                chain.totalPresentsWithPropagatedTransfer(),
                chain.totalPresentsWithBufferUpload(),
                chain.totalPresentsWithUnresolvedSource(),
            },
        );
        const buffer_to_image_count = chain.resource_transfer_kind_counts[@intFromEnum(rosette_gpu.PresentTransferKind.buffer_to_image)];
        if (buffer_to_image_count != 0 and
            chain.totalPresentsWithPropagatedTransfer() == 0 and
            chain.totalPresentsWithBufferUpload() == 0 and
            chain.totalPresentsWithSampledSource() == 0 and
            self.target_offscreen_events != 0)
        {
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:   {s}: buffer_to_image transfers={d}, none reached the acquired presented image; offscreen target events={d}. Offscreen uploads are legitimate intermediate/startup work, not lost pixels; if picture work exists, follow its offscreen-to-acquired edge or descriptor route\n",
                .{ self.provenanceGapLabel(), buffer_to_image_count, self.target_offscreen_events },
            );
        }
        if (buffer_to_image_count != 0 and chain.totalPresentsWithSampledSource() != 0) machoCapturePrint("macho-processor: PRESENT CHAIN:   INDIRECT IMAGE ROUTE: offscreen buffer uploads={d} sampled_source_presents={d}; shader sampling, not a direct copy into the swapchain, connects this path. No direct acquired-image upload is required; inspect source pixels, lookup tables, and shader state\n", .{ buffer_to_image_count, chain.totalPresentsWithSampledSource() });
        for (chain.swapchains[0..chain.swapchain_count]) |swapchain| {
            if (swapchain.presents_with_sampled_source == 0 and
                swapchain.presents_with_propagated_transfer == 0 and
                swapchain.presents_with_buffer_upload == 0 and
                swapchain.presents_with_unresolved_source == 0 and
                swapchain.last_sampled_image == 0 and
                swapchain.last_transfer_source == 0) continue;
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:     route swapchain=0x{x} sampled_source_presents={d} propagated_transfer_presents={d} buffer_upload_presents={d} unresolved_source_presents={d} last_sampled=0x{x} last_transfer_source=0x{x} last_transfer_kind={s}\n",
                .{
                    swapchain.handle,
                    swapchain.presents_with_sampled_source,
                    swapchain.presents_with_propagated_transfer,
                    swapchain.presents_with_buffer_upload,
                    swapchain.presents_with_unresolved_source,
                    swapchain.last_sampled_image,
                    swapchain.last_transfer_source,
                    swapchain.last_transfer_kind.label(),
                },
            );
        }
    }
    if (self.pixel_probe.attempts != 0 or self.pixel_probe.failures != 0) {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   pixel_probe=attempts={d} successes={d} failures={d} content_attempts={d} detail_observed={} last_result={d} sample_policy=first_{d}+up_to_{d}_pre_detail_content_retries+first_8_picture_frames+{d}_render_checkpoints; steady_fills=1Hz steady_content=4Hz preview_interval_ms={d} clock_failure_fallback=8192_checks; readback discovery never waits for the picture epoch\n",
            .{ self.pixel_probe.attempts, self.pixel_probe.successes, self.pixel_probe.failures, self.pixel_probe.content_probe_attempts, self.pixel_probe.detail_observed, self.pixel_probe.last_result, PIXEL_PROBE_INITIAL_SAMPLES, PIXEL_PROBE_CONTENT_SAMPLES, render_diagnostic_frames.len, self.pixel_probe.preview_interval_ns / 1_000_000 },
        );
    }
    if (chain.contestedLayer()) |layer| {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   CONTESTED LAYER 0x{x}: {d} live swapchains share it. A CAMetalLayer vends one drawable pool; two swapchains take turns from it and the one nobody is driving wins those turns, so a correct frame is followed by an empty one\n",
            .{ layer, chain.liveSwapchains() },
        );
        // Name them. Which side owns each swapchain decides who yields,
        // and Rosette's own presenter is a legitimate answer: it brings
        // one up against the window's layer before the guest exists, and
        // nothing retires it when the guest builds its own.
        for (chain.swapchains[0..chain.swapchain_count]) |swapchain| {
            if (swapchain.retired or swapchain.layer != layer) continue;
            machoCapturePrint(
                "macho-processor: PRESENT CHAIN:     contender: swapchain=0x{x} owner={s} extent={d}x{d} images={d} acquires={d} presents={d}\n",
                .{
                    swapchain.handle,
                    swapchain.owner.label(),
                    swapchain.width,
                    swapchain.height,
                    swapchain.image_count,
                    swapchain.acquires,
                    swapchain.presents,
                },
            );
        }
    }
    if (chain.surface_overflow != 0 or chain.swapchain_overflow != 0) {
        machoCapturePrint(
            "macho-processor: PRESENT CHAIN:   {d} surfaces and {d} swapchains did not fit the bounded tables\n",
            .{ chain.surface_overflow, chain.swapchain_overflow },
        );
    }
}

pub fn reportStarvedFence(self: anytype) void {
    const entry = self.vulkan_fence_watch.starvedFence() orelse return;
    machoCapturePrint(
        "macho-processor: VULKAN FENCE STARVED: fence=0x{x} polled {d}x and no submission Rosetta forwarded ever carried it; the guest is waiting for work that was never handed to the driver. Refusals so far: {d} distinct, {d} calls -- the VULKAN REFUSAL lines name which call was rejected and why\n",
        .{ entry.handle, entry.polls, self.vulkan_refusals.count, self.vulkan_refusals.total },
    );
    self.reportVulkanRefusals(false);
}

pub fn reportVulkanRefusals(self: anytype, full: bool) void {
    if (!full and self.vulkan_refusals.unreported_count == 0) return;
    self.printVulkanRefusals(full);
    self.vulkan_refusals.markReported();
}

pub fn printVulkanRefusals(self: anytype, full: bool) void {
    if (self.vulkan_refusals.isEmpty()) return;
    machoCapturePrint(
        "macho-processor: VULKAN REFUSALS: distinct={d} calls={d} new={d}; these calls were rejected by Rosetta's translation layer, not by the driver -- each one is either a bridge limitation to implement or a guest call that is genuinely invalid\n",
        .{ self.vulkan_refusals.count, self.vulkan_refusals.total, self.vulkan_refusals.unreported_count },
    );
    for (self.vulkan_refusals.entries[0..self.vulkan_refusals.count]) |entry| {
        if (!full and !entry.unreported) continue;
        machoCapturePrint(
            "macho-processor: VULKAN REFUSAL:   {s} x{d} reason={s} result={d} first_args=0x{x},0x{x},0x{x}\n",
            .{
                entry.name(),
                entry.calls,
                entry.reason(),
                entry.result,
                entry.first_args[0],
                entry.first_args[1],
                entry.first_args[2],
            },
        );
    }
    if (self.vulkan_refusals.overflow != 0) {
        machoCapturePrint(
            "macho-processor: VULKAN REFUSALS:   {d} further refusals did not fit the bounded ledger\n",
            .{self.vulkan_refusals.overflow},
        );
    }
}

pub fn reportVulkanAbsentEntryPoints(self: anytype) void {
    if (self.vulkan_absent_count == 0) return;
    machoCapturePrint(
        "macho-processor: VULKAN ABSENT ENTRY POINTS: absent={d} reached_by_guest={d}; an absence nothing reached is the expected shape of this device, not a gap\n",
        .{ self.vulkan_absent_count, self.vulkan_absent_reached.count },
    );
    for (self.vulkan_absent_reached.entries[0..self.vulkan_absent_reached.count]) |entry| {
        machoCapturePrint(
            "macho-processor: VULKAN ABSENT:   {s} reached {d}x, served by {s}\n",
            .{ entry.name(), entry.reached, entry.servedBy() },
        );
    }
    if (self.vulkan_absent_reached.isEmpty()) {
        machoCapturePrint(
            "macho-processor: VULKAN ABSENT:   none of them were reached: {s}\n",
            .{self.vulkan_absent_names[0..self.vulkan_absent_names_len]},
        );
    }
}

pub fn noteRealVulkanResult(self: anytype, result: abi.Result, operation: []const u8) void {
    const last_fsi_submit = self.vulkan_fsi_tracker.last_submission;
    const observation: device_loss_diagnostics.Evidence.Snapshot = .{
        .operation = operation,
        .result = result,
        .guest_queue_submit_calls = self.vulkan_queue_submits,
        .native_queue_submits_accepted = self.vulkan_real_queue_submits,
        .native_presents_accepted = self.vulkan_real_presents,
        .native_present_completions = self.vulkan_real_present_completions,
        .fence_completions = self.vulkan_fence_completions,
        .fsi_recorded_draws = self.vulkan_fsi_tracker.draws,
        .fsi_submitted_draws = self.vulkan_fsi_tracker.submitted_draws,
        .last_fsi_queue_submit = last_fsi_submit.queue_submit_ordinal,
        .last_fsi_target_image = last_fsi_submit.draw.target_image,
        .last_fsi_submission = last_fsi_submit,
    };
    if (device_loss_diagnostics.isUnexpectedApiError(result)) {
        const first_unexpected_error = self.vulkan_device_loss_evidence.first_unexpected_error.observe(observation);
        if (first_unexpected_error) {
            machoCapturePrint(
                "macho-processor: Vulkan first unexpected API error: operation={s} result={d} guest_submits={d} native_submits_accepted={d} native_presents_accepted={d} present_completions={d} fence_completions={d} fsi_draws(recorded/submitted)={d}/{d} last_fsi_submit(queue/target)={d}/0x{x}; swapchain OUT_OF_DATE is excluded, and this earliest API error is diagnostic evidence rather than a claimed root cause\n",
                .{ operation, result, observation.guest_queue_submit_calls, observation.native_queue_submits_accepted, observation.native_presents_accepted, observation.native_present_completions, observation.fence_completions, observation.fsi_recorded_draws, observation.fsi_submitted_draws, observation.last_fsi_queue_submit, observation.last_fsi_target_image },
            );
        }
    }
    if (result != abi.ERROR_DEVICE_LOST) return;
    self.real_vulkan.device_lost = true;
    self.real_vulkan.device_loss_result = result;
    self.vulkan_device_lost_events +|= 1;
    const first_run_observation = self.vulkan_device_loss_evidence.observe(observation);
    if (first_run_observation) {
        machoCapturePrint(
            "macho-processor: Vulkan device lost: observation=first_api_detection operation={s} result={d} guest_submits={d} native_submits_accepted={d} native_presents_accepted={d} present_completions={d} fence_completions={d} fsi_draws(recorded/submitted)={d}/{d} fsi_last_submit(queue/target)={d}/0x{x}; Metal/MoltenVK may have reported the underlying GPU fault earlier, so this API return is the detection point, not proof of fault origin\n",
            .{ operation, result, self.vulkan_device_loss_evidence.guest_queue_submit_calls, self.vulkan_device_loss_evidence.native_queue_submits_accepted, self.vulkan_device_loss_evidence.native_presents_accepted, self.vulkan_device_loss_evidence.native_present_completions, self.vulkan_device_loss_evidence.fence_completions, self.vulkan_device_loss_evidence.fsi_recorded_draws, self.vulkan_device_loss_evidence.fsi_submitted_draws, self.vulkan_device_loss_evidence.last_fsi_queue_submit, self.vulkan_device_loss_evidence.last_fsi_target_image },
        );
        self.printDeviceLossFsiSubmission("device_loss_last_fsi_submission", self.vulkan_device_loss_evidence.last_fsi_submission);
        machoCapturePrint(
            "macho-processor: VULKAN FSI RECENT ACCEPTED SUBMISSIONS: count={d}; chronological candidates preceding asynchronous Metal fault, not individually proven faulty\n",
            .{self.vulkan_fsi_tracker.recent_submission_count},
        );
        for (0..self.vulkan_fsi_tracker.recent_submission_count) |index| {
            self.printDeviceLossFsiSubmission("recent_accepted_candidate", self.vulkan_fsi_tracker.recentSubmission(index).?);
        }
        self.printFsiGuardReport();
        self.dumpVulkanCallTrace();
    }
}

pub fn printDeviceLossFsiSubmission(self: anytype, label: []const u8, submission: fsi_diagnostics.SubmissionEvidence) void {
    _ = self;
    const draw = submission.draw;
    machoCapturePrint(
        "macho-processor: VULKAN FSI FAILURE CONTEXT: {s} submit={d} batch={d} command_buffer=0x{x} draw={d} command_draw={d} kind={s} target=0x{x} target_source={s} pipeline=0x{x} module_id={d} shader_hash=0x{x} pipeline_hash=0x{x} draws_in_command_buffer={d}\n",
        .{
            label,
            submission.queue_submit_ordinal,
            submission.batch_index,
            draw.command_buffer,
            draw.draw_ordinal,
            draw.command_buffer_draw_ordinal,
            @tagName(draw.kind),
            draw.target_image,
            @tagName(draw.target_source),
            draw.pipeline_real,
            draw.module_id,
            draw.shader_hash,
            draw.pipeline_hash,
            submission.fsi_draws_in_command_buffer,
        },
    );
}

pub fn realDeviceLostResult(self: anytype) ?u64 {
    if (!self.real_vulkan.device_lost) return null;
    return @as(u32, @bitCast(abi.ERROR_DEVICE_LOST));
}

pub fn noteNativeFenceComplete(self: anytype, state: anytype, synthetic_fence: u64) void {
    if (synthetic_fence == 0) return;
    // A single fence does not prove completion for every allocation (or
    // even every fence in a waitAny call). PE aliases already share bytes.
    if (comptime @hasField(@TypeOf(state.*), "gpu_xenos_runtime")) {
        state.gpu_xenos_runtime.noteNativeFenceComplete(synthetic_fence);
    }
    self.vulkan_fence_completions +|= 1;
}

pub fn clearRealVulkanObjectMaps(self: anytype) void {
    for (&self.vulkan_memory_records) |*record| record.releaseBaseline();
    HandleMap.clear(&self.real_vulkan.memory_map);
    HandleMap.clear(&self.real_vulkan.buffer_map);
    HandleMap.clear(&self.real_vulkan.image_map);
    HandleMap.clear(&self.real_vulkan.sampler_map);
    HandleMap.clear(&self.real_vulkan.fence_map);
    HandleMap.clear(&self.real_vulkan.semaphore_map);
    HandleMap.clear(&self.real_vulkan.render_pass_map);
    HandleMap.clear(&self.real_vulkan.framebuffer_map);
    HandleMap.clear(&self.real_vulkan.pipeline_map);
    HandleMap.clear(&self.real_vulkan.shader_module_map);
    HandleMap.clear(&self.real_vulkan.descriptor_set_layout_map);
    HandleMap.clear(&self.real_vulkan.pipeline_layout_map);
    HandleMap.clear(&self.real_vulkan.descriptor_pool_map);
    HandleMap.clear(&self.real_vulkan.descriptor_set_map);
    HandleMap.clear(&self.real_vulkan.command_pool_map);
    HandleMap.clear(&self.real_vulkan.command_buffer_map);
    HandleMap.clear(&self.real_vulkan.swapchain_map);
    @memset(&self.real_vulkan.swapchain_records, .{});
    HandleMap.clear(&self.real_vulkan.buffer_view_map);
    HandleMap.clear(&self.real_vulkan.image_view_map);
    HandleMap.clear(&self.real_vulkan.query_pool_map);
    HandleMap.clear(&self.real_vulkan.pipeline_cache_map);
    HandleMap.clear(&self.real_vulkan.descriptor_update_template_map);
    @memset(&self.real_vulkan.descriptor_update_template_records, .{});
    HandleMap.clear(&self.real_vulkan.queue_map);
    @memset(&self.real_vulkan.queue_family_indices, abi.QUEUE_FAMILY_IGNORED);
    @memset(&self.vulkan_memory_records, .{});
    @memset(&self.vulkan_resources, .{});
    @memset(&self.tracked_buffer_views, .{});
    @memset(&self.tracked_image_views, .{});
    self.tracked_image_view_index.reset();
    @memset(&self.tracked_descriptor_sets, .{});
    self.tracked_descriptor_set_index.reset();
    @memset(&self.tracked_render_passes, .{});
    @memset(&self.tracked_framebuffers, .{});
    @memset(&self.tracked_command_targets, .{});
    @memset(&self.tracked_graphics_pipelines, .{});
    @memset(&self.tracked_pipeline_layouts, .{});
}

pub fn releaseNativeMemoryAliases(self: anytype, state: anytype) void {
    if (comptime @hasDecl(@TypeOf(state.*), "releaseNativeMemory")) {
        for (&self.vulkan_memory_records) |*record| {
            if (record.native_alias_base != 0) state.releaseNativeMemory(record.native_alias_base);
            record.native_alias_base = 0;
        }
    }
}

pub fn destroyRealDevice(self: anytype) void {
    if (self.native_texture_state) |native| {
        if (native.terminal_result != abi.SUCCESS) self.noteRealVulkanResult(native.terminal_result, "native Metal texture resources during teardown");
    }
    if (!self.real_vulkan.hasDevice()) return;
    for (&self.vulkan_memory_records) |*record| record.releaseBaseline();
    // The FSI timing watcher waits on this device's fences: stop it first.
    self.fsiGuardShutdown();
    const device = self.real_vulkan.device.?;
    // The pixel probe owns host Vulkan children outside the guest handle
    // maps.  Release them while the device function table is still live.
    self.destroyPixelProbeResources();
    if (self.present_completion_fence != 0 and !self.real_vulkan.device_lost) {
        // Only a submitted fence can signal: one whose reset succeeded
        // and whose submit failed would be waited on forever.
        if (self.present_completion_fence_pending) {
            if (self.real_vulkan.fn_ptrs.wait_for_fences) |wait| _ = wait(device, 1, @ptrCast(&self.present_completion_fence), 1, std.math.maxInt(u64));
        }
        if (self.real_vulkan.fn_ptrs.destroy_fence) |destroy| destroy(device, self.present_completion_fence, null);
    }
    self.present_completion_fence = 0;
    self.present_completion_fence_pending = false;
    self.rect_expand_builtin_index_buffer = 0;
    self.rect_expand_command_states = @splat(.{});
    if (self.real_vulkan.device_lost) {
        // Once the driver has reported VK_ERROR_DEVICE_LOST, child
        // destruction and idle waits are not a reliable recovery path.
        // Drop the bridge's mappings, then perform the one Vulkan teardown
        // operation that remains meaningful so a later guest recreation
        // starts from a clean provenance ledger.
        self.fsiRasterShutdown();
        self.destroyFsiZpdSinkResources();
        self.shutdownNativeTextures(false);
        self.clearRealVulkanObjectMaps();
        self.real_vulkan.swapchain = 0;
        self.vulkan_swapchain_image_count = 0;
        @memset(&self.vulkan_swapchain_image_handles, 0);
        if (self.real_vulkan.fn_ptrs.destroy_device) |destroy| destroy(device, null);
        self.real_vulkan.device = null;
        self.real_vulkan.guest_device_handle = 0;
        self.real_vulkan.graphics_queue = null;
        self.real_vulkan.compute_queue = null;
        self.real_vulkan.transfer_queue = null;
        self.real_vulkan.fn_ptrs = .{};
        self.real_vulkan.sync2_enabled = false;
        self.real_vulkan.dynamic_rendering_enabled = false;
        self.real_vulkan.extended_dynamic_state_enabled = false;
        self.real_vulkan.extended_dynamic_state2_enabled = false;
        self.real_vulkan.push_descriptor_enabled = false;
        self.real_vulkan.conditional_rendering_enabled = false;
        self.real_vulkan.device_lost = false;
        self.real_vulkan.device_loss_result = abi.SUCCESS;
        machoCapturePrint("macho-processor: REAL VkDevice destroyed after device loss; mappings quarantined\n", .{});
        return;
    }
    self.destroyRealSwapchain(0);
    // Wait for all work to finish before destroying.
    if (self.real_vulkan.fn_ptrs.device_wait_idle) |wait_fn| {
        const result = wait_fn(device);
        self.noteRealVulkanResult(result, "vkDeviceWaitIdle during teardown");
        if (self.real_vulkan.device_lost) {
            // Re-enter through the quarantined path so no child
            // destructor is called after the driver has invalidated the
            // device.
            self.destroyRealDevice();
            return;
        }
    }
    self.fsiRasterShutdown();
    self.destroyFsiZpdSinkResources();
    self.shutdownNativeTextures(true);
    // Destroy tracked objects in reverse dependency order.
    for (&self.real_vulkan.image_view_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_image_view) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.query_pool_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_query_pool) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.pipeline_cache_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        self.persistPipelineCache(mapped.real);
        if (self.real_vulkan.fn_ptrs.destroy_pipeline_cache) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.descriptor_update_template_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_descriptor_update_template) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.buffer_view_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_buffer_view) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.framebuffer_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_framebuffer) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.pipeline_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.trackedGraphicsPipeline(mapped.real)) |metadata| {
            if (metadata.repair_real != 0 and metadata.repair_real != mapped.real) {
                if (self.real_vulkan.fn_ptrs.destroy_pipeline) |fn_ptr| {
                    fn_ptr(device, metadata.repair_real, null);
                }
            }
        }
        if (self.real_vulkan.fn_ptrs.destroy_pipeline) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.render_pass_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_render_pass) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.descriptor_set_layout_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_descriptor_set_layout) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.pipeline_layout_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_pipeline_layout) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.shader_module_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_shader_module) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.sampler_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_sampler) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.descriptor_pool_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_descriptor_pool) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.image_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_image) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.buffer_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_buffer) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.fence_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_fence) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.semaphore_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_semaphore) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.memory_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.free_memory) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    for (&self.real_vulkan.command_pool_map) |*entry| {
        const mapped = HandleMap.snapshot(entry) orelse continue;
        if (mapped.real == 0) continue;
        if (self.real_vulkan.fn_ptrs.destroy_command_pool) |fn_ptr| {
            fn_ptr(device, mapped.real, null);
        }
    }
    // Clear all maps.
    HandleMap.clear(&self.real_vulkan.memory_map);
    HandleMap.clear(&self.real_vulkan.buffer_map);
    HandleMap.clear(&self.real_vulkan.image_map);
    HandleMap.clear(&self.real_vulkan.sampler_map);
    HandleMap.clear(&self.real_vulkan.fence_map);
    HandleMap.clear(&self.real_vulkan.semaphore_map);
    HandleMap.clear(&self.real_vulkan.render_pass_map);
    HandleMap.clear(&self.real_vulkan.framebuffer_map);
    HandleMap.clear(&self.real_vulkan.pipeline_map);
    HandleMap.clear(&self.real_vulkan.shader_module_map);
    HandleMap.clear(&self.real_vulkan.descriptor_set_layout_map);
    HandleMap.clear(&self.real_vulkan.pipeline_layout_map);
    HandleMap.clear(&self.real_vulkan.descriptor_pool_map);
    HandleMap.clear(&self.real_vulkan.descriptor_set_map);
    HandleMap.clear(&self.real_vulkan.command_pool_map);
    HandleMap.clear(&self.real_vulkan.command_buffer_map);
    HandleMap.clear(&self.real_vulkan.buffer_view_map);
    HandleMap.clear(&self.real_vulkan.image_view_map);
    HandleMap.clear(&self.real_vulkan.query_pool_map);
    HandleMap.clear(&self.real_vulkan.pipeline_cache_map);
    HandleMap.clear(&self.real_vulkan.descriptor_update_template_map);
    @memset(&self.real_vulkan.descriptor_update_template_records, .{});
    HandleMap.clear(&self.real_vulkan.queue_map);
    @memset(&self.real_vulkan.queue_family_indices, abi.QUEUE_FAMILY_IGNORED);
    @memset(&self.vulkan_memory_records, .{});
    @memset(&self.vulkan_resources, .{});
    @memset(&self.tracked_buffer_views, .{});
    @memset(&self.tracked_image_views, .{});
    self.tracked_image_view_index.reset();
    @memset(&self.tracked_descriptor_sets, .{});
    self.tracked_descriptor_set_index.reset();
    @memset(&self.tracked_render_passes, .{});
    @memset(&self.tracked_framebuffers, .{});
    @memset(&self.tracked_command_targets, .{});
    @memset(&self.tracked_graphics_pipelines, .{});
    @memset(&self.tracked_pipeline_layouts, .{});
    // Destroy the device.
    if (self.real_vulkan.fn_ptrs.destroy_device) |destroy| {
        destroy(device, null);
    }
    self.real_vulkan.device = null;
    self.real_vulkan.guest_device_handle = 0;
    self.real_vulkan.graphics_queue = null;
    self.real_vulkan.compute_queue = null;
    self.real_vulkan.transfer_queue = null;
    self.real_vulkan.fn_ptrs = .{};
    self.real_vulkan.sync2_enabled = false;
    self.real_vulkan.dynamic_rendering_enabled = false;
    self.real_vulkan.extended_dynamic_state_enabled = false;
    self.real_vulkan.extended_dynamic_state2_enabled = false;
    self.real_vulkan.push_descriptor_enabled = false;
    self.real_vulkan.conditional_rendering_enabled = false;
    self.real_vulkan.device_lost = false;
    self.real_vulkan.device_loss_result = abi.SUCCESS;
    machoCapturePrint("macho-processor: REAL VkDevice destroyed\n", .{});
}

pub fn destroyRealSwapchain(self: anytype, synthetic: u64) void {
    if (!self.real_vulkan.device_lost) {
        if (self.real_vulkan.device) |device| {
            if (self.real_vulkan.fn_ptrs.destroy_swapchain) |destroy| {
                if (synthetic != 0) {
                    if (self.real_vulkan.realSwapchain(synthetic)) |swapchain| destroy(device, swapchain, null);
                } else {
                    for (self.real_vulkan.swapchain_records) |record| {
                        if (record.real != 0) destroy(device, record.real, null);
                    }
                }
            }
        }
    }
    if (synthetic != 0) {
        if (self.real_vulkan.mutableSwapchainRecord(synthetic)) |record| {
            self.forgetSwapchainResourceImages(record);
            self.real_vulkan.releaseSwapchainImageHandles(record);
            record.* = .{};
        }
        _ = self.releaseVulkanHandle(&self.real_vulkan.swapchain_map, synthetic);
    } else {
        for (self.real_vulkan.swapchain_records) |record| {
            self.forgetSwapchainResourceImages(&record);
            self.real_vulkan.releaseSwapchainImageHandles(&record);
        }
        HandleMap.clear(&self.real_vulkan.swapchain_map);
        @memset(&self.real_vulkan.swapchain_records, .{});
    }
    self.real_vulkan.swapchain = 0;
    self.vulkan_swapchain_image_count = 0;
    @memset(&self.vulkan_swapchain_image_handles, 0);
}

pub fn forgetSwapchainResourceImages(self: anytype, record: *const SwapchainRecord) void {
    const count = @min(@as(usize, @intCast(record.image_count)), record.image_handles.len);
    for (record.image_handles[0..count]) |synthetic_image| {
        if (self.real_vulkan.realImage(synthetic_image)) |real_image| {
            self.present_chain.forgetResourceImage(real_image);
        }
    }
}

pub fn destroyRealSurface(self: anytype) void {
    if (self.real_vulkan.surface == 0) return;
    const instance = self.real_vulkan.instance orelse return;
    const get_proc = self.real_vulkan.get_instance_proc_addr orelse return;
    const address = get_proc(instance, "vkDestroySurfaceKHR") orelse return;
    const destroy: abi.PfnDestroySurfaceKHR = @ptrCast(@alignCast(address));
    destroy(instance, self.real_vulkan.surface, null);
    self.real_vulkan.surface = 0;
    machoCapturePrint("macho-processor: REAL VkSurfaceKHR destroyed\n", .{});
}

pub fn destroyRealInstance(self: anytype) void {
    if (!self.real_vulkan.hasInstance()) return;
    const instance = self.real_vulkan.instance.?;
    const library = self.guestLibrary(self.native_vulkan_library_token) orelse return;
    const destroy_addr = dlsym(library, "vkDestroyInstance") orelse return;
    const destroy_fn: PfnVkDestroyInstance = @ptrCast(@alignCast(destroy_addr));
    destroy_fn(instance, null);
    self.real_vulkan.instance = null;
    self.real_vulkan.guest_instance_handle = 0;
    self.real_vulkan.physical_device = null;
    self.real_vulkan.get_instance_proc_addr = undefined;
    @memset(&self.real_vulkan.physical_device_properties, 0);
    self.real_vulkan.physical_device_memory = .{};
    self.real_vulkan.queue_family_count = 0;
    machoCapturePrint("macho-processor: REAL VkInstance destroyed\n", .{});
}

pub fn printNativeTextureReport(self: anytype) void {
    const native = self.native_texture_state orelse return;
    machoCapturePrint("macho-processor: NATIVE METAL TEXTURES: pipelines={d} modules_matched={d} dispatches(ctx1/dxt1/dxt3/dxt5)={d}/{d}/{d}/{d} declined={d} pipeline_failures={d} metadata_failures={d}; no separate submissions or CPU texture readbacks; runtime visual correctness unverified\n", .{ native.pipelines.count(), native.shaders.count(), native.dispatches[0], native.dispatches[1], native.dispatches[2], native.dispatches[3], native.declines, native.pipeline_failures, native.metadata_failures });
    inline for (std.meta.fields(native_texture.Decline)) |field| {
        const count = native.decline_reasons[field.value];
        if (count != 0) machoCapturePrint("macho-processor: NATIVE METAL TEXTURE DECLINE TOTAL: reason={s} count={d}; admission refusals are not texture decoding failures\n", .{ field.name, count });
    }
}

pub fn shutdownNativeTextures(self: anytype, destroy_native: bool) void {
    const native = self.native_texture_state orelse return;
    self.printNativeTextureReport();
    if (destroy_native) native.deinit(&self.real_vulkan) else native.releaseCpu();
    std.heap.c_allocator.destroy(native);
    self.native_texture_state = null;
}

pub fn destroyNativeVulkanObjects(self: anytype) void {
    self.drainAsyncVulkanCommands();
    // Destroy the guest's real Vulkan objects first (device before instance).
    self.destroyRealDevice();
    // A guest may destroy its instance without first destroying the surface.
    // Keep the Vulkan parent/child teardown order valid in that case too.
    self.destroyRealSurface();
    // The presenter owns a device, a swapchain and a surface of its own,
    // all parented by an instance in this same library. It has to go first,
    // and in its own dependency order.
    self.native_presenter.shutdown();
    self.destroyNativeSurface();
    if (self.native_vulkan_instance) |instance| {
        if (self.guestLibrary(self.native_vulkan_library_token)) |library| {
            if (dlsym(library, "vkDestroyInstance")) |destroy_address| {
                const destroy_instance: PfnVkDestroyInstance = @ptrCast(@alignCast(destroy_address));
                destroy_instance(instance, null);
            }
        }
        self.native_vulkan_instance = null;
    }
    self.native_vulkan_surface = 0;
    // Clean up the guest's real instance if it differs from the presenter's.
    self.destroyRealInstance();
    self.native_vulkan_library_token = 0;
}

pub fn resolveNativeVulkanSymbol(context: ?*anyopaque, name: [*:0]const u8) callconv(.c) ?*anyopaque {
    const handle = context orelse return null;
    return dlsym(handle, name);
}

pub fn nativeVulkanLoaderPath(self: anytype) []const u8 {
    return self.native_vulkan_loader_path[0..self.native_vulkan_loader_path_len];
}

pub fn noteNativeVulkanLoaderResolved(self: anytype, path: []const u8) void {
    self.native_vulkan_loader_successes +|= 1;
    if (path.len > self.native_vulkan_loader_path.len) return;
    @memset(&self.native_vulkan_loader_path, 0);
    @memcpy(self.native_vulkan_loader_path[0..path.len], path);
    self.native_vulkan_loader_path_len = @intCast(path.len);
}

pub fn currentHostDrawableExtent() abi.Extent2D {
    const window = describeHostWindow() orelse return .{};
    return .{
        .width = if (window.drawable_width > 0) @intFromFloat(window.drawable_width) else 0,
        .height = if (window.drawable_height > 0) @intFromFloat(window.drawable_height) else 0,
    };
}

pub fn noteGraphicsExtentContractFailure(
    self: anytype,
    state: anytype,
    requested_width: u32,
    requested_height: u32,
    observed_width: u32,
    observed_height: u32,
    reason: []const u8,
) void {
    self.graphics_extent_contract_failures +|= 1;
    if (self.graphics_extent_contract_failed) return;
    self.graphics_extent_contract_failed = true;
    self.graphics_extent_requested_width = requested_width;
    self.graphics_extent_requested_height = requested_height;
    const host_extent = currentHostDrawableExtent();
    const effective_observed_width = if (observed_width != 0) observed_width else host_extent.width;
    const effective_observed_height = if (observed_height != 0) observed_height else host_extent.height;
    self.graphics_extent_observed_width = effective_observed_width;
    self.graphics_extent_observed_height = effective_observed_height;
    machoCapturePrint(
        "macho-processor: GRAPHICS EXTENT CONTRACT FATAL: reason={s} required={d}x{d} observed={d}x{d} host_drawable={d}x{d} preflight={d}x{d} owner={s} attempts/successes/failures={d}/{d}/{d}; no Vulkan swapchain may continue past this mismatch\n",
        .{
            reason,
            requested_width,
            requested_height,
            effective_observed_width,
            effective_observed_height,
            host_extent.width,
            host_extent.height,
            self.metal_drawable_prepared_width,
            self.metal_drawable_prepared_height,
            @tagName(self.drawable_owner),
            self.metal_drawable_prepare_attempts,
            self.metal_drawable_prepare_successes,
            self.metal_drawable_prepare_failures,
        },
    );
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (@hasDecl(State, "faultOnGraphicsExtentContract")) {
        state.faultOnGraphicsExtentContract(
            requested_width,
            requested_height,
            effective_observed_width,
            effective_observed_height,
            reason,
        );
    }
}

pub fn bringUpNativePresenter(self: anytype, state: anytype, library_token: u64) rosette_gpu.NativePresenterStage {
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (!@hasDecl(State, "nativeMetalLayerHostPointer")) return self.native_presenter.stage;
    const layer = state.nativeMetalLayerHostPointer();
    if (layer == 0) return self.native_presenter.stage;
    const width = if (@hasDecl(State, "nativeWindowWidth")) state.nativeWindowWidth() else 1280;
    const height = if (@hasDecl(State, "nativeWindowHeight")) state.nativeWindowHeight() else 720;
    const requested_width = @max(width, 1);
    const requested_height = @max(height, 1);
    if (self.native_presenter.stage.isReady()) {
        // A layer can change underneath a live presenter when AppKit moves
        // the window between backing stores. Re-run the owner-aware check
        // before handing the already-ready stage to another caller; a
        // stale ready bit is not permission to present through a changed
        // drawable.
        if (!self.prepareMetalDrawableForSwapchain(state, requested_width, requested_height)) {
            return .ready;
        }
        const report = &self.native_presenter.report;
        if (!rosette_gpu.vulkan.selection.extentMatches(
            .{ .width = report.extent_width, .height = report.extent_height },
            .{ .width = requested_width, .height = requested_height },
        )) {
            self.noteGraphicsExtentContractFailure(
                state,
                requested_width,
                requested_height,
                report.extent_width,
                report.extent_height,
                "native_presenter_ready_extent_changed",
            );
        }
        return .ready;
    }
    if (self.native_presenter.stage == .device_lost) return .device_lost;
    // The native presenter is a real Vulkan swapchain too. It must not
    // be the first owner to observe a Retina-sized CAMetalLayer and then
    // make the guest's later 1280x720 preflight impossible. Establish
    // the fixed default extent before creating the native surface/device
    // graph; if the host cannot prove it, leave the presenter unstarted
    // so the guest path can make the authoritative attempt instead.
    if (!self.prepareMetalDrawableForSwapchain(state, requested_width, requested_height)) {
        machoCapturePrint(
            "macho-processor: native Vulkan presenter deferred: CAMetalLayer drawable extent is not proven at the default {d}x{d}; no native presenter swapchain will claim the layer at another geometry\n",
            .{ requested_width, requested_height },
        );
        return self.native_presenter.stage;
    }
    const library = self.materializeNativeVulkanLibrary(library_token) orelse return self.native_presenter.stage;

    self.native_presenter_attempts +|= 1;
    const stage = self.native_presenter.bringUp(
        .{ .context = library, .lookup = resolveNativeVulkanSymbol },
        layer,
        requested_width,
        requested_height,
    );
    if (self.native_presenter_stage_logged != stage) {
        self.native_presenter_stage_logged = stage;
        const report = &self.native_presenter.report;
        machoCapturePrint(
            "macho-processor: native Vulkan presenter: attempt={d} stage={s} ({s}) VkResult={d} rejection={s} adapter={s} api=0x{x} physical_devices={d} queues(graphics/present/unified)={d}/{d}/{} portability(enumeration/subset)={}/{} swapchain(images/extent/requested/format/colorspace/present_mode/usage)={d}/{d}x{d}/{d}x{d}/{d}/{d}/{d}/0x{x} CAMetalLayer=0x{x}\n",
            .{
                self.native_presenter_attempts,
                @tagName(stage),
                stage.label(),
                report.last_result,
                report.rejectionLabel(),
                if (report.adapter_name_length != 0) report.adapterName() else "unselected",
                report.api_version,
                report.physical_device_count,
                report.graphics_family,
                report.present_family,
                report.unified_queue,
                report.portability_enumeration,
                report.portability_subset,
                report.swapchain_image_count,
                report.extent_width,
                report.extent_height,
                report.requested_extent_width,
                report.requested_extent_height,
                report.surface_format,
                report.surface_color_space,
                report.present_mode,
                report.image_usage,
                layer,
            },
        );
    }
    if (self.native_presenter.extentContractFailed()) {
        const report = &self.native_presenter.report;
        self.noteGraphicsExtentContractFailure(
            state,
            requested_width,
            requested_height,
            report.extent_width,
            report.extent_height,
            "native_presenter_surface_capability_extent_mismatch",
        );
    }
    if (stage.isReady()) {
        self.vulkan_presenter_stage = .native_drawable_ready;
        if (@hasDecl(State, "setNativeMetalDrawableOwner")) {
            _ = state.setNativeMetalDrawableOwner(true);
            self.drawable_owner = .native_presenter;
            machoCapturePrint(
                "macho-processor: CAMetalLayer drawable owner: native_presenter extent={d}x{d}; the native smoke swapchain is now protected from AppKit/layout writes until the guest handoff retires it\n",
                .{ requested_width, requested_height },
            );
        }
        // The driver may update CAMetalLayer.drawableSize as part of
        // vkCreateSwapchainKHR even after its capability query matched.
        // Verify the post-create owner state before publishing Rosette's
        // native objects to the present chain; a successful Vulkan result
        // is not permission to retain a wrong-sized drawable.
        if (!self.prepareMetalDrawableForSwapchain(state, requested_width, requested_height)) {
            return stage;
        }
        self.registerNativePresenterInPresentChain(state);
        self.negotiateRosetteGpuBoundary("native_presenter_ready");
    }
    return stage;
}
