// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const acceptance_gates = __ProcessInternals._acceptance_gates;
const claim_reconciliation = __ProcessInternals._claim_reconciliation;
const contract = __ProcessInternals._contract;
const deadlock_predictor = __ProcessInternals._deadlock_predictor;
const deferred_work = __ProcessInternals._deferred_work;
const environmentFlag = __ProcessInternals._environmentFlag;
const execution_tracepoints = __ProcessInternals._execution_tracepoints;
const gpu = __ProcessInternals._gpu;
const guest_log = __ProcessInternals._guest_log;
const guest_wait_liveness = __ProcessInternals._guest_wait_liveness;
const host_contract_coverage = __ProcessInternals._host_contract_coverage;
const interrupt_callback_transaction = __ProcessInternals._interrupt_callback_transaction;
const log = __ProcessInternals._log;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const main = __ProcessInternals._main;
const monotone_witness = __ProcessInternals._monotone_witness;
const native_window = __ProcessInternals._native_window;
const preflight_lib = __ProcessInternals._preflight_lib;
const run_horizon = __ProcessInternals._run_horizon;
const scheduler = __ProcessInternals._scheduler;
const signal_expectation = __ProcessInternals._signal_expectation;
const std = __ProcessInternals._std;
const sync_object_identity = __ProcessInternals._sync_object_identity;
const sync_object_registry = __ProcessInternals._sync_object_registry;
const translation_economics = __ProcessInternals._translation_economics;
const types = __ProcessInternals._types;
const wait_audit = __ProcessInternals._wait_audit;
const xenia_gpu_handoff = __ProcessInternals._xenia_gpu_handoff;
const xenia_memory_views = __ProcessInternals._xenia_memory_views;
const xenia_pipeline = __ProcessInternals._xenia_pipeline;
const captureMemoryMutation = __ProcessInternals._captureMemoryMutation;
const commitMemoryMutation = __ProcessInternals._commitMemoryMutation;
const guestMemory = __ProcessInternals._guestMemory;
const guestMemoryConst = __ProcessInternals._guestMemoryConst;
const ms = __ProcessInternals._ms;
const configureAuditContracts = MachOState.configureAuditContracts;
const elapsedHostSeconds = MachOState.elapsedHostSeconds;
const execute = MachOState.execute;
const guestOutputEvidence = MachOState.guestOutputEvidence;
const guestOutputFramesPresented = MachOState.guestOutputFramesPresented;
const preflightAddressTranslation = MachOState.preflightAddressTranslation;
const preflightOutcomeStatus = MachOState.preflightOutcomeStatus;
const readConsolePhysicalDword = MachOState.readConsolePhysicalDword;
const refreshDeadlockPredictor = MachOState.refreshDeadlockPredictor;
const refreshGraphicsContract = MachOState.refreshGraphicsContract;
const refreshVdSwapContract = MachOState.refreshVdSwapContract;
const run = MachOState.run;
const runBudgetGuestWindowSummary = MachOState.runBudgetGuestWindowSummary;
const runBudgetGuestWindowVerdict = MachOState.runBudgetGuestWindowVerdict;
const step = MachOState.step;
const syncPresentationProvenance = MachOState.syncPresentationProvenance;

pub fn seedPreWindowHostCoverage(self: anytype) void {
    const C = host_contract_coverage.Capability;
    const host = &self.host_capabilities;

    const image_mapped = self.segments.len != 0 and
        self.entry_point_vaddr != 0 and
        self.guestMemoryConst(self.entry_point_vaddr, 1) != null;
    self.host_coverage.record(
        C.guest_memory_mapping,
        if (image_mapped) .satisfied else .unsatisfied,
        if (image_mapped)
            "Mach-O segments and the entry point are mapped and readable before guest execution"
        else
            "the loaded Mach-O has no readable mapped entry point",
    );

    const host_page = host.finding(.host_page_granularity);
    const protection = host.finding(.protection_cycle);
    const overlay = host.finding(.guest_page_protection_fidelity);
    const protection_status: host_contract_coverage.Status = blk: {
        if (protection.outcome == .failed or protection.outcome == .unavailable) {
            break :blk .unsatisfied;
        }
        // On a coarse host the overlay is the proof of the effective
        // contract.  On a 4 KiB host, the direct protection-cycle probe is
        // already the exact guest-sized operation.
        if (overlay.outcome == .verified) {
            break :blk preflightOutcomeStatus(protection.outcome);
        }
        if (host_page.outcome == .verified and host_page.measured_value <= 4096) {
            break :blk preflightOutcomeStatus(protection.outcome);
        }
        if (overlay.outcome == .degraded or
            host_page.outcome == .degraded or
            protection.outcome == .degraded)
        {
            break :blk .degraded;
        }
        if (host_page.outcome == .failed or host_page.outcome == .unavailable) {
            break :blk .unsatisfied;
        }
        break :blk .untested;
    };
    self.host_coverage.record(
        C.memory_protection,
        protection_status,
        switch (protection_status) {
            .satisfied => if (overlay.outcome == .verified)
                "host protection cycle passed and Rosette's guest-page overlay restored the requested granularity"
            else
                "host protection cycle passed at the guest's 4 KiB page granularity",
            .degraded => "the host protection operation or its guest-page compensation is coarser than requested",
            .unsatisfied => "the host protection contract was exercised and failed",
            .untested => "the host protection contract has no complete granularity proof",
        },
    );

    const translation_ok = preflightAddressTranslation();
    self.host_coverage.record(
        C.address_space_translation,
        if (translation_ok) .satisfied else .unsatisfied,
        if (translation_ok)
            "virtual, physical and A/C/E alias projections passed the model self-test; the live Xenia base remains guest-deferred"
        else
            "the console virtual/physical alias model failed its pre-window self-test",
    );

    const thread_status = preflightOutcomeStatus(host.finding(.thread_creation).outcome);
    self.host_coverage.record(
        C.thread_creation,
        thread_status,
        "a host thread was spawned, executed a release-store witness and joined during preflight",
    );
    self.host_coverage.record(
        C.thread_scheduling,
        thread_status,
        "the preflight worker ran on the host scheduler and completed before the join returned",
    );

    const timed_wait_status = preflightOutcomeStatus(host.finding(.timed_wait_fidelity).outcome);
    const sync_status: host_contract_coverage.Status = if (!self.host_signal_handshake_proven)
        .unsatisfied
    else switch (timed_wait_status) {
        .satisfied => .satisfied,
        .degraded => .degraded,
        .unsatisfied => .unsatisfied,
        .untested => .untested,
    };
    self.host_coverage.record(
        C.sync_primitives,
        sync_status,
        if (self.host_signal_handshake_proven and sync_status == .satisfied)
            "libc mutex/condition primitives signalled and released a real waiter"
        else
            "the host mutex/condition contract did not provide a complete timed and signalled proof",
    );
    self.host_coverage.record(
        C.wait_signal_handshake,
        if (self.host_signal_handshake_proven) .satisfied else .unsatisfied,
        if (self.host_signal_handshake_proven)
            "a pthread condition signal crossed from the producer thread to the waiting thread"
        else
            "a pthread condition signal did not release the waiting thread",
    );

    const file_ok = self.data.len != 0 and self.segments.len != 0;
    self.host_coverage.record(
        C.file_read,
        if (file_ok) .satisfied else .unsatisfied,
        if (file_ok)
            "the Mach-O image was read into memory and indexed before admission"
        else
            "the Mach-O image read/index operation produced no usable bytes",
    );
    self.host_coverage.record(
        C.disc_image,
        if (self.audit_media_fingerprint == 0)
            .unsatisfied
        else if (self.audit_media_preflight_evaluated and !self.audit_media_preflight_passed)
            .degraded
        else if (self.audit_media_preflight_evaluated and self.audit_media_preflight_passed)
            .satisfied
        else
            .degraded,
        if (self.audit_media_fingerprint == 0)
            "no verified Xenia media content identity exists before admission"
        else if (self.audit_media_preflight_evaluated and !self.audit_media_preflight_passed)
            "the selected media hash exists, but the XISO structure preflight did not pass"
        else if (self.audit_media_preflight_evaluated and self.audit_media_preflight_passed)
            "the selected Xenia media input and content identity passed before admission"
        else
            "the selected media has a content identity but no format-level preflight proof",
    );

    if (self.graphics_preflight_enabled) {
        self.host_coverage.record(
            C.window_surface,
            if (self.graphics_path_preflight.windowGateAllows()) .satisfied else .unsatisfied,
            if (self.graphics_path_preflight.windowGateAllows())
                "native window/layer/backend host stages passed the pre-window path probe"
            else
                "the native window path probe has a blocking host-stage failure",
        );
    }

    const unwind_ok = self.unwinder.compact != null;
    self.host_coverage.record(
        C.exception_unwinding,
        if (unwind_ok) .satisfied else .unsatisfied,
        if (unwind_ok)
            "the Mach-O compact-unwind index is configured before guest execution"
        else
            "the Mach-O has no configured compact-unwind index",
    );

    const codegen_ok = self.ready.enabled() and
        self.ready.compile_check_count != 0 and
        self.ready.compile_checks_dropped == 0 and
        self.ready.failure.kind == .none;
    self.host_coverage.record(
        C.code_generation,
        if (codegen_ok)
            .satisfied
        else if (self.ready.failure.kind != .none)
            .unsatisfied
        else
            .untested,
        if (codegen_ok)
            "the required startup compile plan completed with retained passing checks"
        else if (self.ready.failure.kind != .none)
            "the startup compiler recorded a typed failure before guest execution"
        else
            "no complete startup code-generation proof was retained before guest execution",
    );

    const clock_status = preflightOutcomeStatus(host.finding(.monotonic_clock_resolution).outcome);
    const locale_status: host_contract_coverage.Status = if (!self.host_locale_query_proven)
        .unsatisfied
    else switch (clock_status) {
        .satisfied => .satisfied,
        .degraded => .degraded,
        .unsatisfied => .unsatisfied,
        .untested => .untested,
    };
    self.host_coverage.record(
        C.locale_and_time,
        locale_status,
        if (self.host_locale_query_proven and locale_status == .satisfied)
            "libc answered the current locale and the monotonic clock resolution probe passed"
        else
            "the locale/time host contract did not provide a complete pre-window proof",
    );
}

pub fn enforcePreWindowHostCoverage(self: anytype) bool {
    self.seedPreWindowHostCoverage();
    // This catches any evidence already available from the generic runtime
    // ledgers while Ledger.record's conservative `.untested` rule keeps a
    // no-evidence refresh from erasing the preflight proofs above.
    self.refreshHostCoverage();

    const coverage = self.host_coverage.preWindowCoverage();
    const bypass = environmentFlag("ROSETTE_PREWINDOW_COVERAGE_OFF");
    machoCapturePrint(
        "macho-processor: PRE-WINDOW COVERAGE: phase=final host(satisfied/untested/failing)={d}/{d}/{d} guest_deferred={d} strict={s} bypass={s}\n",
        .{
            coverage.host_satisfied,
            coverage.host_untested,
            coverage.host_failing,
            coverage.guest_deferred,
            if (self.audit_profile == .authentic) "YES" else "NO",
            if (bypass) "YES" else "NO",
        },
    );
    var capability_index: u8 = 0;
    while (capability_index < host_contract_coverage.capability_count) : (capability_index += 1) {
        const capability: host_contract_coverage.Capability = @enumFromInt(capability_index);
        if (!capability.answerableBeforeWindow()) continue;
        const entry = self.host_coverage.entry(capability);
        machoCapturePrint(
            "  pre-window capability={s} status={s} owner={s} layer={s} evidence={s}\n",
            .{
                capability.label(),
                entry.status.label(),
                capability.owner().label(),
                capability.layer().label(),
                entry.note(),
            },
        );
    }

    if (coverage.blocksWindow() and !bypass) {
        machoCapturePrint(
            "macho-processor: PRE-WINDOW COVERAGE: BLOCKED host_foundation_gaps={d} host_failures={d}; no native window or guest initializer is permitted until every Rosette-owned capability has a verdict\n",
            .{ coverage.host_untested, coverage.host_failing },
        );
        return false;
    }
    if (bypass and coverage.blocksWindow()) {
        machoCapturePrint(
            "macho-processor: PRE-WINDOW COVERAGE: explicit diagnostic bypass accepted; host gaps remain authoritative and every downstream finding is marked conditional on this bypass\n",
            .{},
        );
    }
    machoCapturePrint(
        "macho-processor: PRE-WINDOW COVERAGE: host foundation closed; guest-owned edges deferred to runtime and may now be observed without confusing an untested Rosette capability for a title failure\n",
        .{},
    );
    return true;
}

pub fn refreshHostCoverage(self: anytype) void {
    const C = host_contract_coverage.Capability;
    const ledger = &self.host_coverage;

    if (self.xenia_memory_views.ready()) {
        ledger.record(C.address_space_translation, .satisfied, "console memory view base discovered");
    }
    if (self.executed_steps != 0) {
        ledger.record(C.guest_memory_mapping, .satisfied, "guest image mapped and executing");
    }
    ledger.record(
        C.memory_protection,
        if (self.gpu_register_aperture_reachable) .satisfied else .untested,
        "aperture handler registration is the only reachability evidence",
    );
    if (self.pthreads.created_threads != 0) {
        ledger.record(C.thread_creation, .satisfied, "guest threads created and scheduled");
        ledger.record(C.thread_scheduling, .satisfied, "cooperative rotation is running");
        ledger.record(C.sync_primitives, .satisfied, "mutexes and condvars are servicing guest waits");
    }

    // The wait handshake is scored from the audit rather than from call
    // counts: a handshake that answers every call and never releases anyone
    // is exactly the degraded state this model exists to name.
    const problems = self.wait_audit.problemCount(self.executed_steps);
    if (self.wait_audit.count != 0) {
        const wait_note: []const u8 = if (problems == 0)
            "no observed wait pattern crossed the audit threshold for a problem; signal-only and incomplete observations remain explicitly non-diagnostic"
        else if (self.wait_audit.worst(self.executed_steps)) |subject|
            self.wait_audit.classify(subject, self.executed_steps).meaning()
        else
            "wait audit recorded a problem, but no stable subject was available for a more specific explanation";
        ledger.record(
            C.wait_signal_handshake,
            if (problems == 0) .satisfied else .degraded,
            wait_note,
        );
    }

    if (self.fs_forwarder.open_count != 0) {
        ledger.record(C.file_read, .satisfied, "guest file reads are being serviced");
    }
    if (self.xenia_pipeline.hasReached(.disc_mounted)) {
        ledger.record(C.disc_image, .satisfied, "disc image mounted");
    }

    const variables = self.gpu_kernel_variables.finding();
    if (variables.imported_count != 0) {
        ledger.record(
            C.kernel_variable_surface,
            if (variables.blocking == null) .satisfied else .unsatisfied,
            "every imported kernel variable resolves through both dereferences",
        );
    }
    if (self.gpu_import_binding.count != 0) {
        ledger.record(
            C.kernel_export_binding,
            if (self.gpu_import_binding.worst().healthy()) .satisfied else .unsatisfied,
            if (self.gpu_import_binding.worst().healthy())
                "Xenia thunk-readiness/import probes show committed, translatable slots beginning with the export stub"
            else
                "an import/thunk probe found a slot or export thunk that is not safely bound",
        );
    } else {
        ledger.record(
            C.kernel_export_binding,
            .untested,
            "Rosette has no import/thunk-readiness evidence for the graphics kernel exports yet",
        );
    }

    if (self.gpu_bootstrap.seen(.initialize_engines)) {
        ledger.record(C.gpu_engine_init, .satisfied, "VdInitializeEngines ran");
    } else {
        ledger.record(C.gpu_engine_init, .untested, "Xenia has not entered VdInitializeEngines");
    }
    if (self.gpu_ring_watch_base != 0) {
        ledger.record(C.gpu_ring_buffer, .satisfied, "ring geometry established and readable");
    } else {
        ledger.record(
            C.gpu_ring_buffer,
            .untested,
            "the host observer is ready, but Xenia has not published guest ring geometry",
        );
    }
    if (self.gpu_bootstrap.seen(.graphics_interrupt_dispatch)) {
        ledger.record(C.gpu_interrupt_callback, .satisfied, "callback registered and dispatched");
    } else {
        ledger.record(C.gpu_interrupt_callback, .untested, "no guest GPU interrupt dispatch has been observed");
    }
    if (self.execution_tracepoints.roleEntered(.command_processor)) {
        ledger.record(C.gpu_command_flow, .satisfied, "the command processor drained a batch");
    } else {
        ledger.record(C.gpu_command_flow, .untested, "no guest PM4 command-processor entry has been observed");
    }

    // General bring-up and raw/no-output draws do not establish that a
    // swap was due. The 2026-09-01 run consumed 24 intentional no-effect
    // startup draws and was consequently labelled UNSATISFIED forever,
    // even though no target, resolve, front buffer or XE_SWAP existed.
    // Judge the title only after an output-bearing opportunity exists.
    const guest_output_evidence = self.guestOutputEvidence();
    const guest_output_opportunity = host_contract_coverage.guestOutputOpportunity(guest_output_evidence);
    const swap_entered = self.execution_tracepoints.roleEntered(.swap);
    const swap_status = host_contract_coverage.guestSwapStatus(guest_output_evidence, swap_entered);
    ledger.record(
        C.guest_swap_request,
        swap_status,
        if (swap_entered)
            "VdSwap entered through the guest GPU path"
        else if (guest_output_opportunity)
            "target-backed output or explicit swap evidence exists, but VdSwap was never entered"
        else
            "GPU activity so far has no output-bearing target, resolve or guest swap evidence; VdSwap remains untested",
    );

    // Score the guest Vulkan path from driver-bound work, not from the
    // existence of a proc token or a successful synthetic return. Real
    // command recording and queue submission are meaningful host
    // execution evidence; a present without either is still only a
    // request for a diagnostic refresh.
    const observed_commands = self.dynamic_forwarder.guestVulkanObservedCommands();
    const real_commands = self.dynamic_forwarder.guestVulkanCommandsForwarded();
    const real_submits = self.dynamic_forwarder.guestVulkanQueueSubmits();
    ledger.record(
        C.graphics_command_execution,
        if (real_submits != 0)
            .satisfied
        else if (real_commands != 0)
            .degraded
        else if (observed_commands != 0)
            .degraded
        else
            .untested,
        if (real_submits != 0)
            "guest command buffers reached native Vulkan and were submitted"
        else if (real_commands != 0)
            "guest command buffers reached native Vulkan but no native submission was observed"
        else if (observed_commands != 0)
            "guest Vulkan commands were observed but had no native command-buffer mapping"
        else
            "no guest Vulkan command recording has been observed",
    );
    // A native present is not, by itself, guest-output evidence. Rosette
    // emits diagnostic frames while the guest Vulkan path is being
    // brought up; treating those presents as a guest opportunity turns a
    // truthful "not reached" contract into a false failure. Keep the
    // strict source gate tied to guest render/swap evidence only.
    ledger.record(
        C.frame_source,
        if (self.dynamic_forwarder.guestFrontBufferAvailable())
            .satisfied
        else if (guest_output_opportunity)
            .unsatisfied
        else
            .untested,
        if (self.dynamic_forwarder.guestFrontBufferAvailable())
            "a guest-produced image is available to the presenter"
        else if (guest_output_opportunity)
            "guest output work was requested, but no guest-produced image has held a picture"
        else
            "no guest output opportunity has been observed yet",
    );
    if (self.native_window.layer_attachments != 0) {
        ledger.record(C.window_surface, .satisfied, "Cocoa layer attached and the presenter is bound");
    }
    const guest_source_available = self.dynamic_forwarder.guestFrontBufferAvailable() or self.gpu_frontbuffer != null;
    const authentic_guest_frames = self.guestOutputFramesPresented();
    const presentation_status = host_contract_coverage.guestPresentationStatus(
        guest_output_evidence,
        guest_source_available,
        authentic_guest_frames,
    );
    ledger.record(
        C.frame_presentation,
        presentation_status,
        if (authentic_guest_frames != 0)
            "a guest-authentic frame completed the presenter-to-window handoff"
        else if (guest_source_available)
            "a guest frame source exists, but no guest-authentic frame completed the window handoff"
        else if (guest_output_opportunity)
            "guest output became due, but no guest-authentic frame reached the window"
        else
            "no guest output opportunity exists yet; native and diagnostic presents prove only the separately scored host window surface",
    );

    if (self.guest_exceptions.total_throws != 0) {
        ledger.record(
            C.exception_unwinding,
            if (self.guest_exceptions.worst() == null) .satisfied else .degraded,
            "phase-1 walk, handler install and catch retirement all complete",
        );
    }
    ledger.record(
        C.code_generation,
        if (!self.ready.enabled())
            .untested
        else if (self.ready.compile_check_count == 0 or self.ready.compile_checks_dropped != 0)
            .untested
        else if (self.ready.failure.kind != .none or self.deferred_work.total_failures != 0)
            .degraded
        else
            .satisfied,
        if (!self.ready.enabled())
            "the startup code-generation gate was not enabled, so no readiness verdict exists"
        else if (self.ready.compile_check_count == 0 or self.ready.compile_checks_dropped != 0)
            "the readiness gate was enabled but retained no complete compile-check set"
        else if (self.ready.failure.kind != .none or self.deferred_work.total_failures != 0)
            "translation has a recorded readiness or deferred-emission failure"
        else
            "the enabled readiness path has no recorded compiler or deferred-emission failure",
    );
    if (self.dynamic_forwarder.forwarded != 0) {
        ledger.record(C.locale_and_time, .satisfied, "host library forwarding is servicing queries");
    }
}

pub fn logHostCoverage(self: anytype) void {
    self.refreshHostCoverage();
    const ledger = &self.host_coverage;
    const report = ledger.report();
    machoCapturePrint(
        "macho-processor: HOST CONTRACT COVERAGE: {d}% satisfied={d} degraded={d} unsatisfied={d} untested={d} critical(total/satisfied/degraded/unsatisfied/untested)={d}/{d}/{d}/{d}/{d} of {d} step={d}; {s}\n",
        .{
            report.percent(),
            report.satisfied,
            report.degraded,
            report.unsatisfied,
            report.untested,
            report.critical_total,
            report.critical_satisfied,
            report.critical_degraded,
            report.critical_unsatisfied,
            report.critical_untested,
            host_contract_coverage.capability_count,
            self.executed_steps,
            ledger.verdict(),
        },
    );
    const pre_window = ledger.preWindowCoverage();
    machoCapturePrint(
        "macho-processor: HOST CONTRACT PRE-WINDOW: host(satisfied/untested/failing)={d}/{d}/{d} guest_deferred={d} strict_gate={s} step={d}; host rows are Rosette-owned evidence and guest rows are intentionally deferred until the title exercises them\n",
        .{
            pre_window.host_satisfied,
            pre_window.host_untested,
            pre_window.host_failing,
            pre_window.guest_deferred,
            if (pre_window.blocksWindow()) "BLOCKED" else "CLOSED",
            self.executed_steps,
        },
    );
    inline for (@typeInfo(host_contract_coverage.Layer).@"enum".fields) |field| {
        const layer: host_contract_coverage.Layer = @enumFromInt(field.value);
        const score = ledger.layerScore(layer);
        machoCapturePrint(
            "  layer {s: <18} {d: >3}%\n",
            .{ layer.label(), score.percent() },
        );
    }
    if (ledger.weakestLayer()) |weakest| machoCapturePrint(
        "macho-processor: HOST CONTRACT COVERAGE: weakest layer is {s} at {d}% — this is where the next hour belongs, not wherever the last frontier happened to point\n",
        .{ weakest.layer.label(), weakest.percent() },
    );
    var gaps: [host_contract_coverage.capability_count]host_contract_coverage.Capability = undefined;
    for (ledger.criticalGaps(&gaps)) |capability| {
        const entry = ledger.entry(capability);
        machoCapturePrint(
            "  critical gap {s: <34} {s: <12} layer={s} — {s}\n",
            .{ capability.label(), entry.status.label(), capability.layer().label(), entry.note() },
        );
    }
}

pub fn refreshWaitAuditWitness(self: anytype) void {
    var stages: u64 = 0;
    for (self.xenia_pipeline.reached) |reached| {
        if (reached) stages += 1;
    }
    self.wait_audit.noteProgress(.pipeline_stage, stages);
    self.wait_audit.noteProgress(.ring_publication, self.gpu_ring_publication.advances);
    self.wait_audit.noteProgress(
        .gpu_callback,
        if (self.gpu_bootstrap.seen(.graphics_interrupt_dispatch)) 1 else 0,
    );
    self.wait_audit.noteProgress(.module_load, self.guest_modules.count);
    self.wait_audit.noteProgress(
        .presented_frame,
        self.dynamic_forwarder.nativePresenterFramesPresented(),
    );
    self.wait_audit.noteProgress(.executed_steps, self.executed_steps);
}

pub fn logWaitAudit(self: anytype) void {
    self.refreshWaitAuditWitness();
    const ledger = &self.wait_audit;
    const problems = ledger.problemCount(self.executed_steps);
    machoCapturePrint(
        "macho-processor: WAIT AUDIT: subjects={d} problems={d} no_finding={d} dropped={d} step={d}; {s}\n",
        .{
            ledger.count,
            problems,
            ledger.count - problems,
            ledger.dropped,
            self.executed_steps,
            ledger.verdict(self.executed_steps),
        },
    );
    // `no_finding` used to be printed as `suppressed`, which reads as
    // "eight problems were hidden" when it means "eight subjects were
    // judged and none of them was a problem *by this audit's rules*". The
    // difference matters because this audit's rules deliberately exclude
    // finite polls, and the run where that wording appeared had
    // `problems=0 suppressed=8` printed a few lines above
    // `DEADLOCK PREDICTOR: deadlocked=YES`. Both were right about their own
    // question, and read together they said nothing was wrong.
    if (problems == 0 and ledger.count != 0) {
        machoCapturePrint(
            "  WAIT AUDIT SCOPE: this audit judges repeating waits against its own rules and excludes finite manual-reset polls by design. A subject with no finding here can still be the blocker in the wait graph, the signal-expectation pairing or the deadlock predictor — `problems=0` is this audit's answer, not the run's\n",
            .{},
        );
    }
    var bounded_timeout_subjects: u64 = 0;
    var bounded_timeout_attempts: u64 = 0;
    for (ledger.subjects[0..ledger.count]) |subject| {
        if (subject.timeout_class != .bounded_poll) continue;
        bounded_timeout_subjects +|= 1;
        bounded_timeout_attempts +|= subject.timeouts;
    }
    if (bounded_timeout_subjects != 0) machoCapturePrint(
        "  WAIT TIMEOUT CONTRACT: bounded_poll_subjects={d} attempts={d} guest_synthetic_wake=REFUSED; finite manual-reset timeout returns are authoritative guest results, not proof of an indefinitely parked waiter\n",
        .{ bounded_timeout_subjects, bounded_timeout_attempts },
    );
    // One line per subject, whatever its classification: a reader needs to
    // know a pump exists and was judged healthy, or the suppression looks
    // like the subsystem missing it.
    for (ledger.subjects[0..ledger.count]) |subject| {
        const classification = ledger.classify(subject, self.executed_steps);
        machoCapturePrint(
            "  subject object=0x{x:0>8} handle=0x{x:0>8} type={d} {s: <21} waits={d} timeouts={d} signals={d} timeout_class={s} timeout_ms={d} timeout_requested_known={s} timeout_requested={s} threads={d} period_steps={d}\n",
            .{
                subject.object,
                subject.handle,
                subject.type_code,
                classification.label(),
                subject.waits,
                subject.timeouts,
                subject.signals,
                subject.timeout_class.label(),
                subject.timeout_ms,
                if (subject.timeout_requested_known) "YES" else "NO",
                if (subject.timeout_requested) "YES" else "NO",
                subject.participant_count,
                subject.periodSteps(),
            },
        );
        if (subject.timeout_class == .bounded_poll and subject.timeouts != 0) {
            machoCapturePrint(
                "    timeout contract: class=bounded_poll action=await_deadline severity=caution may_resume=YES may_synthesize_wake=NO attempts={d} signals={d} first_step={d} last_step={d}; inspect the producer/frontier, but do not convert a finite poll expiry into a guest signal\n",
                .{ subject.timeouts, subject.signals, subject.first_step, subject.last_step },
            );
        }
        if (!classification.worthAuditing()) continue;

        // The full audit, for problems only.
        machoCapturePrint(
            "    audit: first_step={d} last_step={d} sightings={d}; {s}\n",
            .{ subject.first_step, subject.last_step, subject.sightings(), classification.meaning() },
        );
        for (subject.participants[0..subject.participant_count]) |thread| {
            machoCapturePrint("    participant thread=0x{x}\n", .{thread});
        }
        var axes: [wait_audit.axis_count]wait_audit.Axis = undefined;
        const frozen = ledger.frozenAxes(subject, &axes);
        if (frozen.len == 0) continue;
        machoCapturePrint("    holding back:", .{});
        for (frozen) |axis| machoCapturePrint(" {s}", .{axis.label()});
        machoCapturePrint(
            " — these are the subsystems that have not advanced once since this pattern started. Anything not listed here kept working, so this wait is not what is blocking it\n",
            .{},
        );
    }
}

pub fn logDeadlockPredictor(self: anytype) void {
    // The identity table decides whether any of this is about one object or
    // two, so it is reported alongside rather than buried.
    const identity = &self.sync_object_identity;
    if (identity.count != 0 or identity.rewrites != 0 or identity.handle_count != 0 or
        identity.handle_conflicts != 0 or identity.handle_rejections != 0) machoCapturePrint(
        "macho-processor: SYNC OBJECT IDENTITY: pairs={d} handles={d} rewrites={d} conflicts={d} handle_conflicts={d} dropped={d} rejected(truncated/spliced/handle)={d}/{d}/{d} mapping_base=0x{x}; {s}\n",
        .{
            identity.count,
            identity.handle_count,
            identity.rewrites,
            identity.conflicts,
            identity.handle_conflicts,
            identity.dropped,
            identity.truncated_reads,
            identity.spliced_pairs,
            identity.handle_rejections,
            identity.mapping_base,
            identity.verdict(),
        },
    );
    self.refreshDeadlockPredictor();
    const ledger = &self.deadlock_predictor;
    const worst = ledger.worst();
    machoCapturePrint(
        "macho-processor: DEADLOCK PREDICTOR: finding={s} objects={d} threads={d} parked={d} deadlocked={s} untracked(threads/objects)={d}/{d} step={d}; {s}\n",
        .{
            worst.finding.label(),
            ledger.object_count,
            ledger.thread_count,
            ledger.parkedThreadCount(),
            if (worst.finding.deadlocked()) "YES" else "NO",
            ledger.untracked_threads,
            ledger.untracked_objects,
            self.executed_steps,
            ledger.verdict(),
        },
    );
    if (worst.object) |object| {
        machoCapturePrint(
            "  blocking object=0x{x} kind={s} waiters={d} notifiers={d} notifications={d} repairs={d} longest_park_steps={d} last_notify(step={d} thread=0x{x} pc=0x{x})\n",
            .{
                object.address,
                object.kind.label(),
                object.waiters,
                object.notifier_count,
                object.notifications,
                object.repair_attempts,
                object.longest_park_steps,
                object.last_notify_step,
                object.last_notify_thread,
                object.last_notify_pc,
            },
        );
        var waiters: [deadlock_predictor.max_threads]deadlock_predictor.Thread = undefined;
        for (ledger.waitersFor(object.address, &waiters)) |waiter| {
            machoCapturePrint(
                "  blocking waiter thread=0x{x} start=0x{x} wait_rip=0x{x} mutex=0x{x} generation={d}/{d} blocked_since_step={d} age_steps={d} reason={s}\n",
                .{
                    waiter.handle,
                    waiter.start_routine,
                    waiter.blocked_rip,
                    waiter.waiting_mutex,
                    waiter.wait_generation,
                    waiter.notified_generation,
                    waiter.blocked_since_step,
                    self.executed_steps -| waiter.blocked_since_step,
                    if (waiter.blocked_reason.len != 0) waiter.blocked_reason else "unknown",
                },
            );
            if (waiter.blocked_rip != 0) {
                machoCapturePrint(
                    "    blocking waiter symbol={s} start_symbol={s}; this is the last guest/host boundary retained for the parked context\n",
                    .{ self.metadata.symbolLabel(waiter.blocked_rip), self.metadata.symbolLabel(waiter.start_routine) },
                );
            }
        }
        if (object.repair_attempts != 0) {
            machoCapturePrint(
                "  repair note: a bounded spurious wake was granted {d} time(s) and the waiter re-parked — the predicate is genuinely unsatisfied, so this is a guest-side deadlock (the creator never published the state it waits on), not a lost wakeup. Find the code that should have published it and confirm it ran; the once-per-generation guard stops further wakes\n",
                .{object.repair_attempts},
            );
        }
    }
    // Every object with waiters, not only the worst one.
    //
    // The worst object is the one to act on; the rest are what makes it
    // legible. An object with one waiter and one notifier sitting beside
    // one with a waiter and none is the comparison that says the missing
    // signaller is specific to that object rather than a property of the
    // run. Objects that have been notified are collapsed to a count: they
    // are the healthy majority and printing them buries the one that is
    // not.
    var notified_objects: usize = 0;
    for (ledger.objects[0..ledger.object_count]) |object| {
        if (object.waiters == 0) continue;
        if (object.notifier_count != 0 or object.notifications != 0) {
            notified_objects += 1;
            continue;
        }
        machoCapturePrint(
            "  notifier-census object=0x{x} kind={s} waiters={d} notifiers={d} notifications={d} longest_park_steps={d} last_notify_step={d}; nothing has ever raised this object and waiters chose it, so something intended to signal it\n",
            .{
                object.address,
                object.kind.label(),
                object.waiters,
                object.notifier_count,
                object.notifications,
                object.longest_park_steps,
                object.last_notify_step,
            },
        );
    }
    if (notified_objects != 0) machoCapturePrint(
        "  notifier-census: {d} object(s) with waiters have a notifier and are collapsed; every object listed above has none at all\n",
        .{notified_objects},
    );
    // A cycle is a stronger statement than "no live root", so it is looked
    // for explicitly rather than inferred from the classification.
    for (ledger.threads[0..ledger.thread_count]) |thread| {
        if (!thread.state.parked()) continue;
        var chain: [8]u64 = undefined;
        const cycle = ledger.findCycle(thread.handle, &chain) orelse continue;
        machoCapturePrint(
            "macho-processor: DEADLOCK PREDICTOR: WAIT_CYCLE length={d} — {s}\n",
            .{ cycle.len, deadlock_predictor.Finding.wait_cycle.meaning() },
        );
        for (cycle, 0..) |handle, index| {
            machoCapturePrint("    cycle[{d}] thread=0x{x}\n", .{ index, handle });
        }
        break;
    }
}

pub fn logGuestExceptions(self: anytype) void {
    const ledger = &self.guest_exceptions;
    // Throwing is ordinary C++ control flow; a run with no exceptions and
    // no concern does not need a line on every checkpoint.
    if (ledger.total_throws == 0) return;
    machoCapturePrint(
        "macho-processor: GUEST EXCEPTION PREDICTOR: types={d} throws={d} catches={d} concerning={s} dropped={d} step={d}; {s}\n",
        .{
            ledger.count,
            ledger.total_throws,
            ledger.total_catches,
            if (ledger.worst() != null) "YES" else "NO",
            ledger.dropped,
            self.executed_steps,
            ledger.verdict(),
        },
    );
    for (ledger.records[0..ledger.count]) |record| {
        machoCapturePrint(
            "  exception type={s} outcome={s} throws={d} catches={d} code={d} unwind_frames={d} first_step={d} last_step={d} site={s}\n",
            .{
                record.name(),
                record.outcome.label(),
                record.throws,
                record.catches,
                record.code,
                record.unwind_frames,
                record.first_step,
                record.last_step,
                record.site(),
            },
        );
    }
}

pub fn logDeferredWork(self: anytype) void {
    const ledger = &self.deferred_work;
    const finding = ledger.finding();
    // Deferral is how the system works; a quiet ledger with nothing
    // outstanding is not worth a line on every checkpoint.
    if (finding == .quiet and ledger.total_failures == 0) return;
    machoCapturePrint(
        "macho-processor: DEFERRED WORK PREDICTOR: finding={s} deferrals={d} failures={d} demands={d} latent={d} fatal={d} unrecorded_demands={d} dropped={d} step={d}; {s}\n",
        .{
            finding.label(),
            ledger.total_deferrals,
            ledger.total_failures,
            ledger.total_demands,
            ledger.latentCount(),
            ledger.fatalCount(),
            ledger.demands_without_record,
            ledger.dropped,
            self.executed_steps,
            finding.meaning(),
        },
    );
    for (ledger.items[0..ledger.count]) |item| {
        if (item.disposition != .failed) continue;
        machoCapturePrint(
            "  deferred id=0x{x} kind={s} {s} deferred_step={d} demanded_step={d} demands={d} reason='{s}' — {s}\n",
            .{
                item.id,
                item.kind.label(),
                item.disposition.label(),
                item.deferred_step,
                item.demanded_step,
                item.demands,
                item.reason(),
                item.kind.consequence(),
            },
        );
    }
}

pub fn logImportBinding(self: anytype) void {
    const ledger = &self.gpu_import_binding;
    machoCapturePrint(
        "macho-processor: IMPORT BINDING: probed={d} bound={d} worst={s} probes={d} untracked={d} step={d}; {s}\n",
        .{
            ledger.count,
            ledger.boundCount(),
            ledger.worst().label(),
            ledger.total_probes,
            ledger.untracked_probes,
            self.executed_steps,
            ledger.verdict(),
        },
    );
    for (ledger.entries[0..ledger.count]) |entry| {
        machoCapturePrint(
            "  import 0x{x:0>3} {s: <17} slot=0x{x:0>8} -> 0x{x:0>8} thunk=0x{x:0>8} words={x:0>8}/{x:0>8} export_stub={s} probes={d}\n",
            .{
                entry.ordinal,
                entry.binding.label(),
                entry.slot_address,
                entry.slot_word,
                entry.thunk_address,
                entry.thunk_word0,
                entry.thunk_word1,
                if (gpu.import_binding.isExportThunk(entry.thunk_word0, entry.thunk_word1)) "YES" else "NO",
                entry.probes,
            },
        );
    }
}

pub fn logSubmissionProvenance(self: anytype) void {
    const ledger = &self.gpu_submission_provenance;
    // Rosette's tracker is fed by parsing a line the emulator printed, so
    // it is recorded as the log-line source and never as a stronger one.
    ledger.record(.emulator_log_line, true, self.gpu_ring_publication.writes);
    ledger.record(.emulator_counter, self.gpu_xenia_wptr_counter_seen, self.gpu_xenia_wptr_updates);
    ledger.record(
        .guest_register_store,
        true,
        self.gpu_register_aperture.total_writes,
    );
    ledger.record(.ring_memory_contents, self.gpu_ring_watch_base != 0, self.gpu_ring_nonzero_dwords);
    const transport_summary = self.audit_ring_transport.summary();
    ledger.record(
        .transport_completion,
        self.audit_configured,
        if (self.audit_ring_transport.meetsPublicationGate()) transport_summary.effective else 0,
    );

    const finding = ledger.finding();
    machoCapturePrint(
        "macho-processor: SUBMISSION PROVENANCE: finding={s} strongest_pointer_evidence={s} active_observers={d} undermines_publication={s} step={d}; {s}\n",
        .{
            finding.label(),
            if (ledger.strongestPointerEvidence()) |source| source.label() else "<none>",
            ledger.activeCount(),
            if (finding.undermines_publication()) "YES" else "NO",
            self.executed_steps,
            finding.meaning(),
        },
    );
    const consumer_observed = self.gpu_ring_publication.consumerSawBatch() or
        self.gpu_xenos_runtime.batches != 0 or
        self.xenia_gpu_handoff.pm4_packets != 0;
    machoCapturePrint(
        "  consumer evidence: observed={s} stateful_batches={d} handoff_packets={d} consumed_dwords={d} root_or_nested_packets={d} root_or_nested_draws={d} swaps={d} first_step={d} last_step={d}; this is independent of pointer provenance\n",
        .{
            if (consumer_observed) "YES" else "NO",
            self.gpu_xenos_runtime.batches,
            self.xenia_gpu_handoff.pm4_packets,
            self.gpu_ring_publication.consumed_batch_dwords,
            self.gpu_ring_publication.consumed_batch_packets,
            self.gpu_ring_publication.consumed_batch_draws,
            self.gpu_ring_publication.consumed_batch_swaps,
            self.gpu_ring_publication.first_consumed_step,
            self.gpu_ring_publication.last_consumed_step,
        },
    );
    inline for (.{
        gpu.submission_provenance.Source.emulator_log_line,
        gpu.submission_provenance.Source.emulator_counter,
        gpu.submission_provenance.Source.guest_register_store,
        gpu.submission_provenance.Source.ring_memory_contents,
        gpu.submission_provenance.Source.transport_completion,
    }) |source| {
        const observation = ledger.get(source);
        machoCapturePrint(
            "  observer {s: <22} active={s: <3} events={d: <8} {s}\n",
            .{
                source.label(),
                if (observation.active) "YES" else "NO",
                observation.events,
                source.strength(),
            },
        );
    }
}

pub fn offerGuestFrontBuffer(
    self: anytype,
    swap: gpu.Pm4SwapDescription,
    fetch: ?gpu.Pm4FetchConstant,
    harness_supplied: bool,
) void {
    const host = self.xenia_memory_views.physicalHostAddress(swap.frontbuffer_physical_address) orelse {
        machoCapturePrint(
            "macho-processor: GUEST FRONT BUFFER: console physical 0x{x:0>8} could not be translated; the emulator's memory view base has not been discovered, so its framebuffer is unreadable from here\n",
            .{swap.frontbuffer_physical_address},
        );
        return;
    };
    const resolved = self.tryResolveXenosColorToFrontBuffer(swap, host);
    const tiled = if (resolved) false else if (fetch) |constant| constant.tiled() else true;
    const endian: gpu.xenos_texture.Endian = if (resolved)
        .none
    else if (fetch) |constant|
        @enumFromInt(constant.endianness())
    else
        .@"8in32";
    const format: gpu.xenos_texture.Format = if (resolved)
        .k_8_8_8_8
    else if (fetch) |constant|
        @enumFromInt(constant.format())
    else
        .k_8_8_8_8;
    self.dynamic_forwarder.noteGuestFrontBuffer(host, swap.width, swap.height, tiled, endian, format, harness_supplied);
    if (!self.gpu_frontbuffer_offered) {
        self.gpu_frontbuffer_offered = true;
        machoCapturePrint(
            "macho-processor: GUEST FRONT BUFFER: console physical 0x{x:0>8} -> 0x{x} extent={d}x{d} format={s}(raw={d}) tiled={s} endian={s} fetch={s}; the presenter will convert and show these pixels ahead of any emulator Vulkan image, because they are the console's own framebuffer\n",
            .{
                swap.frontbuffer_physical_address,                                                                                                                                                                                 host,
                swap.width,                                                                                                                                                                                                        swap.height,
                format.label(),                                                                                                                                                                                                    @intFromEnum(format),
                if (tiled) "YES" else "NO",                                                                                                                                                                                        endian.label(),
                if (resolved) "EDRAM RESOLVE (linear RGBA8)" else if (fetch != null) "observed" else "ABSENT (tiling and byte order assumed; a wrong assumption here produces a sheared or colour-swapped picture, not an error)",
            },
        );
    }
}

pub fn tryResolveXenosColorToFrontBuffer(self: anytype, swap: gpu.Pm4SwapDescription, host: u64) bool {
    if (self.gpu_xenos_runtime.last_draw == null) return false;
    if (swap.width == 0 or swap.height == 0 or swap.width > 4096 or swap.height > 4096) return false;
    const pitch_u64 = std.math.mul(u64, swap.width, 4) catch return false;
    const bytes_u64 = std.math.mul(u64, pitch_u64, swap.height) catch return false;
    if (bytes_u64 > std.math.maxInt(usize)) return false;
    const bytes_len: usize = @intCast(bytes_u64);
    if (self.gpu_xenos_resolve_scratch.len < bytes_len) {
        const replacement = self.allocator.alloc(u8, bytes_len) catch return false;
        if (self.gpu_xenos_resolve_scratch.len != 0) self.allocator.free(self.gpu_xenos_resolve_scratch);
        self.gpu_xenos_resolve_scratch = replacement;
    }
    const scratch = self.gpu_xenos_resolve_scratch[0..bytes_len];
    @memset(scratch, 0);
    self.gpu_xenos_runtime.resolveCurrentColor(swap.width, swap.height, scratch, @intCast(pitch_u64)) catch return false;

    var any_nonzero = false;
    for (scratch) |byte| {
        if (byte != 0) {
            any_nonzero = true;
            break;
        }
    }
    if (!any_nonzero) return false;
    const destination = self.guestMemory(host, bytes_u64) orelse return false;
    const mutation = self.captureMemoryMutation(host, bytes_u64);
    @memcpy(destination, scratch);
    self.commitMemoryMutation(mutation, .bulk_copy);
    machoCapturePrint(
        "macho-processor: XENOS EDRAM resolve: target=0x{x} extent={d}x{d} bytes={d} source=stateful_color_target destination=guest_front_buffer\n",
        .{ host, swap.width, swap.height, bytes_len },
    );
    return true;
}

pub fn logSwapSubstitution(self: anytype) void {
    self.refreshVdSwapContract();
    const publication = &self.gpu_ring_publication;
    const stalled = publication.last_advance_step != 0 and
        self.executed_steps > publication.last_advance_step;
    const evidence = gpu.SubstitutionEvidence{
        .ring_published = publication.advances != 0,
        // The tracepoint is useful when Xenia's own command-processor
        // symbol is reached, but the stateful Rosette consumer can prove
        // the same boundary by draining the retained ring before that
        // symbol is visible. Keep both sources: substitution must not
        // call a consumed batch "unconsumed" merely because the generic
        // tracepoint missed an indirect-buffer route.
        .pm4_consumed = self.execution_tracepoints.roleEntered(.command_processor) or
            publication.consumerSawBatch() or
            self.gpu_xenos_runtime.batches != 0 or
            self.xenia_gpu_handoff.pm4_packets != 0,
        .draws_issued = self.gpu_ring_draws_seen,
        .authentic_swap_seen = self.gpu_vd_swap_contract.authentic_consumptions != 0,
        .steps_since_publish = if (stalled) self.executed_steps - publication.last_advance_step else 0,
        .ring_geometry_known = self.gpu_ring_watch_base != 0,
        .ring_drained = publication.drained_observations != 0,
        .frontbuffer_known = self.gpu_vd_swap_contract.frontbufferKnown(),
        .discovered_output_available = self.dynamic_forwarder.guestFrontBufferAvailable(),
        // The channel is open when the ring's host projections are writable
        // from here: the packet, and the write-pointer value it implies,
        // can be delivered into the ring memory the emulator reads. What a
        // memory write cannot reach is the emulator's own memory-mapped
        // register store — its stores are executed by guest code — and that
        // boundary is stated out loud in the SYNTHETIC QUEUE line rather
        // than hidden.
        .write_pointer_channel_available = self.gpu_ring_watch_host_physical != 0 or
            self.gpu_ring_watch_host_virtual != 0,
    };
    const decision = gpu.swap_substitution.decide(evidence, gpu.swap_substitution.default_quiet_steps);
    const triggers_before = self.gpu_swap_substitution.triggers;
    self.gpu_swap_substitution.record(decision, self.executed_steps);
    // Execute the tier the decision authorised, once per substitution
    // episode. The decision stays `substituting` for every heartbeat while
    // the producer is quiet, so gating on the trigger count is what stops
    // the queue from re-injecting the same packet on a loop — a livelock
    // of the harness's own making. Only tiers that fabricate guest
    // behaviour write a packet: presenting the guest's own discovered
    // pixels invents nothing and has no packet.
    if (decision.tier.fabricatesGuestBehaviour() and
        self.gpu_swap_substitution.triggers > triggers_before)
    {
        self.runSyntheticQueue();
    }

    machoCapturePrint(
        "macho-processor: SWAP SUBSTITUTION: tier={s} blocked_by={s} step={d} triggers={d} presented={d} packets={d} pointers={d} fabricated={s}; {s}\n",
        .{
            decision.tier.label(),
            if (decision.blocked_by) |reason| @tagName(reason) else "-",
            self.executed_steps,
            self.gpu_swap_substitution.triggers,
            self.gpu_swap_substitution.presented_discovered,
            self.gpu_swap_substitution.packets_published,
            self.gpu_swap_substitution.pointers_advanced,
            if (self.gpu_swap_substitution.fabricatedAnything()) "YES" else "NO",
            self.gpu_swap_substitution.verdict(),
        },
    );
    machoCapturePrint(
        "  evidence: published={s} consumed={s} drew={s} authentic_swap={s} quiet_steps={d} geometry={s} drained={s} frontbuffer={s} wptr_channel={s}\n",
        .{
            if (evidence.ring_published) "YES" else "NO",
            if (evidence.pm4_consumed) "YES" else "NO",
            if (evidence.draws_issued) "YES" else "NO",
            if (evidence.authentic_swap_seen) "YES" else "NO",
            evidence.steps_since_publish,
            if (evidence.ring_geometry_known) "YES" else "NO",
            if (evidence.ring_drained) "YES" else "NO",
            if (evidence.frontbuffer_known) "YES" else "NO",
            if (evidence.write_pointer_channel_available) "YES" else "NO",
        },
    );
    if (decision.blocked_by) |reason| {
        if (reason != .not_triggered) machoCapturePrint(
            "macho-processor: SWAP SUBSTITUTION: blocked — {s}\n",
            .{reason.label()},
        );
    }
    if (decision.tier.fabricatesGuestBehaviour()) {
        _ = self.graphics_contract.substitute(.guest_swap_entered, self.executed_steps);
    }
    const vd_frontier = self.gpu_vd_swap_contract.frontier();
    machoCapturePrint(
        "macho-processor: SWAP SUBSTITUTION CONTRACT: frontier={s} owner={s} blocker={s} frontbuffer={s} packet_seen={s} authentic_consumed={s}; {s}\n",
        .{
            if (vd_frontier.stage) |stage| stage.label() else "<complete>",
            vd_frontier.owner.label(),
            vd_frontier.blocker.label(),
            if (self.gpu_vd_swap_contract.frontbufferKnown()) "YES" else "NO",
            if (self.gpu_vd_swap_contract.packetSeen()) "YES" else "NO",
            if (self.gpu_vd_swap_contract.authentic_consumptions != 0) "YES" else "NO",
            vd_frontier.blocker.guidance(),
        },
    );
}

pub fn runSyntheticQueue(self: anytype) void {
    const ledger = &self.gpu_ring_injection;
    const publication = &self.gpu_ring_publication;

    // The write pointer the packet goes at. The geometry carries the
    // emulator's own pointer pair when it reports one; the tracker's last
    // observed value is the fallback. Either way the refusal is named, not
    // swallowed.
    const write_pointer = blk: {
        if (publication.geometry) |geometry| {
            if (geometry.write_pointer != 0) break :blk geometry.write_pointer;
        }
        if (publication.last_value) |value| break :blk value;
        ledger.recordBlocked(.no_write_pointer);
        if (ledger.last_blocked_by == .no_write_pointer) machoCapturePrint(
            "macho-processor: SYNTHETIC QUEUE: blocked — {s}\n",
            .{gpu.ring_injection.Blocked.no_write_pointer.label()},
        );
        return;
    };

    const swap = self.gpu_frontbuffer orelse {
        ledger.recordBlocked(.frontbuffer_implausible);
        return;
    };
    if (!swap.plausible()) {
        ledger.recordBlocked(.frontbuffer_implausible);
        return;
    }

    // A coherent fetch constant describing the front buffer the swap
    // names. The command processor only checks the XE_SWAP payload; the
    // fetch dwords carry the surface's format and tiling for presentation,
    // and defaults here are the same ones a packet without a fetch decodes
    // to.
    var fetch = gpu.pm4.FetchConstant{};
    fetch.setBaseAddress(swap.frontbuffer_physical_address);
    fetch.setSize2d(swap.width, swap.height);
    fetch.setTiled(true);

    var packet: [gpu.ring_injection.swap_reservation_dwords]u32 = undefined;
    const used = gpu.pm4.encodeSwapSequence(
        &packet,
        fetch,
        swap,
        gpu.ring_injection.swap_reservation_dwords,
    ) orelse return;
    const dwords = packet[0..used];
    if (self.gpu_ring_watch_size == 0) {
        ledger.recordBlocked(.no_geometry);
        return;
    }
    const ring_dwords: u32 = @intCast(@min(self.gpu_ring_watch_size / 4, std.math.maxInt(u32)));

    // Write every projection the ring is readable through. The emulator
    // may read the ring through any of them and the three aliases can
    // disagree, so a single-address write is how a harness delivers a
    // packet somewhere nobody looks.
    var written_aliases: u32 = 0;
    var first_inject: ?gpu.RingInject = null;
    const aliases = [_]struct { name: []const u8, host: u64 }{
        .{ .name = "physical", .host = self.gpu_ring_watch_host_physical },
        .{ .name = "virtual", .host = self.gpu_ring_watch_host_virtual },
    };
    for (aliases) |alias| {
        if (alias.host == 0) continue;
        const ring = self.guestMemory(alias.host, @as(u64, ring_dwords) * 4) orelse continue;
        const inject = gpu.ring_injection.injectSequence(ring, ring_dwords, write_pointer, dwords) orelse continue;
        written_aliases += 1;
        if (first_inject == null) first_inject = inject;
        machoCapturePrint(
            "  synthetic queue wrote projection={s} host=0x{x} dwords={d} wptr=0x{x}->0x{x} wrap={s}\n",
            .{
                alias.name,                 alias.host,
                inject.dwords_written,      inject.write_pointer_before,
                inject.write_pointer_after, if (inject.wrapped) "YES" else "NO",
            },
        );
    }
    const inject = first_inject orelse {
        ledger.recordBlocked(.not_writable);
        machoCapturePrint(
            "macho-processor: SYNTHETIC QUEUE: blocked — {s}\n",
            .{gpu.ring_injection.Blocked.not_writable.label()},
        );
        return;
    };
    ledger.record(inject, self.executed_steps);
    ledger.channel_open = true;
    machoCapturePrint(
        "macho-processor: SYNTHETIC QUEUE: injected swap packet dwords={d} ring_base=0x{x} wptr=0x{x}->0x{x} wrap={s} aliases={d}/2 frontbuffer=0x{x:0>8} {d}x{d} step={d}; the packet is in ring memory the emulator reads. The write pointer value is what the guest must publish — its register store is memory-mapped and only guest code can execute that store, so until the emulator's ring-change watch acts on this, nothing downstream may count it as an authentic submission\n",
        .{
            inject.dwords_written,
            self.gpu_ring_watch_base,
            inject.write_pointer_before,
            inject.write_pointer_after,
            if (inject.wrapped) "YES" else "NO",
            written_aliases,
            swap.frontbuffer_physical_address,
            swap.width,
            swap.height,
            self.executed_steps,
        },
    );
}

pub fn logGraphicsContract(self: anytype) void {
    self.refreshGraphicsContract();
    const ledger = &self.graphics_contract;
    const frontier = ledger.frontier();
    machoCapturePrint(
        "macho-processor: GRAPHICS CONTRACT: met={d}/{d} frontier={s} owner={s} step={d} harness_refusals={d}; {s}\n",
        .{
            frontier.met_required,
            frontier.required_total,
            if (frontier.clause) |clause| clause.label() else "<complete>",
            if (frontier.clause) |clause| clause.owner().label() else "-",
            self.executed_steps,
            ledger.refused_harness_satisfactions,
            if (frontier.clause) |clause| clause.guidance() else "every required clause is met",
        },
    );
    inline for (@typeInfo(gpu.ContractClause).@"enum".fields) |field| {
        const clause: gpu.ContractClause = @enumFromInt(field.value);
        machoCapturePrint(
            "  clause {s: <8} {s: <12} {s}{s}\n",
            .{
                ledger.state(clause).label(),
                clause.owner().label(),
                clause.label(),
                if (clause.required()) "" else " (optional)",
            },
        );
    }
    var pending: [gpu.contract.clause_count]gpu.ContractClause = undefined;
    const outstanding = ledger.unmetHarnessClauses(&pending);
    if (outstanding.len == 0) {
        machoCapturePrint(
            "macho-processor: GRAPHICS CONTRACT: no harness clause is outstanding — every precondition Rosette owns has been supplied, so the frontier above is not Rosette's to move\n",
            .{},
        );
        return;
    }
    for (outstanding) |clause| {
        machoCapturePrint(
            "macho-processor: GRAPHICS CONTRACT: harness work outstanding: {s} — {s}\n",
            .{ clause.label(), clause.guidance() },
        );
    }
}

pub fn syncGraphicsBoundaryGate(self: anytype) void {
    const bringup = gpu.bringup_gate;
    const tracepoints = &self.execution_tracepoints;
    const at_step = self.executed_steps;
    for (bringup.contractBoundaries()) |boundary| {
        const index: u8 = @intFromEnum(boundary);
        const hits = tracepoints.boundaryHits(index);
        if (hits == 0) continue;
        const first = tracepoints.boundaryFirst(index) orelse continue;
        self.gpu_bringup_gate.observe(
            boundary,
            hits,
            first.first_step,
            tracepoints.boundaryLastStep(index),
            first.first_thread,
            first.first_caller,
        );
    }
    self.syncBootstrapProvenanceTracepoints();
    self.syncMonotoneWitnesses(at_step);
    // Completion-route sampling supplies the guest-visible write-back
    // edge consumed by the transport audit below. Sample first so one
    // checkpoint describes one coherent transport state.
    self.syncCompletionRoutes(at_step);
    self.syncAuditContracts(at_step);
    self.syncGraphicsEvidence();
    self.syncProducerAttribution();
    self.syncPresentationProvenance();
}

pub fn syncAuditContracts(self: anytype, at_step: u64) void {
    const bringup = gpu.bringup_gate;
    const gate = &self.gpu_bringup_gate;

    self.configureAuditContracts(at_step);

    // ---- producer epochs ------------------------------------------------
    // Each epoch is credited only from the boundary that proves it, and a
    // guest-owned epoch only from a guest-authentic source. The ledger
    // refuses the rest and counts the refusal.
    const Epoch = gpu.producer_liveness.Epoch;
    const EpochPair = struct { epoch: Epoch, boundary: bringup.Boundary, guest: bool };
    const epochs = [_]EpochPair{
        .{ .epoch = .video_initialized, .boundary = .initialize_engines, .guest = true },
        .{ .epoch = .callback_registered, .boundary = .set_interrupt_callback, .guest = true },
        .{ .epoch = .ring_initialized, .boundary = .initialize_ring_buffer, .guest = true },
        .{ .epoch = .payload_published, .boundary = .write_pointer_updated, .guest = true },
        .{ .epoch = .payload_consumed, .boundary = .execute_packet_type3, .guest = false },
        .{ .epoch = .draw_activity, .boundary = .issue_draw, .guest = false },
        .{ .epoch = .swap_requested, .boundary = .guest_swap_requested, .guest = true },
        .{ .epoch = .frame_consumed, .boundary = .refresh_guest_output, .guest = false },
    };
    for (epochs) |pair| {
        if (self.audit_producer.has(pair.epoch)) continue;
        const record = gate.recordFor(pair.boundary);
        if (!record.crossed()) continue;
        _ = self.audit_producer.observe(.{
            .epoch = pair.epoch,
            .guest_step = record.first_step,
            .guest_thread = record.first_thread,
            .source = if (pair.guest) .guest_authentic else .host_forwarded,
            .wait_object = self.audit_producer.currentWaitObject(),
        });
    }
    // The object the producer is waiting on, taken from the bounded-poll
    // subject the wait audit selected. Attribution, not inference: the
    // ledger reports `quiet_without_a_reason` when nothing supplies one.
    for (self.wait_audit.subjects[0..self.wait_audit.count]) |subject| {
        if (subject.timeout_class != .bounded_poll) continue;
        if (subject.signals != 0 or subject.timeouts == 0) continue;
        if (self.audit_producer.transition_count == 0) break;
        const newest = &self.audit_producer.transitions[self.audit_producer.transition_count - 1];
        var same_thread = false;
        for (subject.participants[0..subject.participant_count]) |thread| {
            if (thread == newest.guest_thread and thread != 0) {
                same_thread = true;
                break;
            }
        }
        if (!same_thread) continue;
        if (newest.wait_object == 0) newest.wait_object = subject.object;
        break;
    }
    // Offer the pause ledger the axes a stopped guest cannot move.
    //
    // A pause report is a claim, and until this existed the only way out
    // of `unreconciled` was finding a transaction that had never been
    // written — so one unmatched line early in a run disqualified every
    // wait finding for the rest of it. These readings let the run answer
    // the claim with what the guest actually did after it.
    self.audit_pause.observeGuestProgress(
        .guest_code_translated,
        self.ready.translationProgressGeneration(),
        at_step,
    );
    self.audit_pause.observeGuestProgress(
        .guest_wait_released,
        self.guest_wait_liveness.total_blocked_signalled,
        at_step,
    );
    self.audit_pause.observeGuestProgress(
        .guest_export_entered,
        self.gpu_bringup_gate.crossedCount(),
        at_step,
    );
    self.audit_pause.observeGuestProgress(
        .guest_symbol_reached,
        self.ready.external_progress_advances,
        at_step,
    );
    if (self.audit_pause.standing() == .open_with_cause) {
        self.audit_producer.notePause(at_step);
    } else {
        self.audit_producer.noteResume();
    }

    // ---- ring transport --------------------------------------------------
    const publication = &self.gpu_ring_publication;
    if (publication.geometry) |geometry| {
        _ = self.audit_ring_transport.declare(.{
            .base = .{ .guest_physical = geometry.base },
            .size_bytes = geometry.size_bytes,
        });
    }
    const writeback_route = self.gpu_completion_routes.status(.read_pointer_write_back);
    if (writeback_route.value_changed and writeback_route.deliveries != 0) {
        _ = publication.observeGuestWriteback(
            writeback_route.last_value,
            writeback_route.last_delivery_step,
        );
    }
    const advances = publication.retainedAdvances();
    var advance_index: usize = @intCast(@min(self.audit_ring_transport.total, advances.len));
    while (advance_index < advances.len) : (advance_index += 1) {
        const record = advances[advance_index];
        const transition = self.audit_ring_transport.begin(.guest_mmio, record.value);
        transition.read_index_before = record.previous_value;
        transition.normalised_index = record.value;
        transition.applied_index = record.value;
        transition.note(.source_write, record.step);
        transition.note(.validated, record.step);
        transition.note(.normalised, record.step);
        transition.note(.range_checked, record.step);
        if (record.applied) transition.note(.applied, record.applied_step);
        if (record.worker_woken) transition.note(.worker_woken, record.worker_woken_step);
        if (record.consumed) {
            transition.read_index_before = record.read_before;
            transition.read_index_after = record.read_after;
            transition.note(.read_pointer_moved, record.consumed_step);
            self.audit_ring_transport.noteConsumed(record.consumed_dwords);
        }
        if (record.guest_writeback) transition.note(.guest_writeback, record.guest_writeback_step);
    }

    // ---- render target and draw classification ---------------------------
    const draws = gate.recordFor(.issue_draw);
    const target = gate.recordFor(.render_target_update);
    while (self.audit_render_target.total < draws.hits) {
        const candidate = self.audit_render_target.begin(draws.first_step, .guest_authentic) orelse break;
        if (target.crossed()) {
            candidate.note(.state_programmed);
            candidate.note(.target_memory_bound);
            candidate.classification = .target_backed;
        } else if (self.gpu_draw_exits_named != 0 and self.gpu_draw_defect_exits == 0) {
            // The emulator named every exit it saw and classified none of
            // them as its own failure. Those draws legitimately produce
            // nothing, and that is the title's program rather than a
            // rendering failure.
            candidate.classification = .intentional_no_output;
        } else if (self.gpu_draw_defect_exits != 0) {
            candidate.classification = .emulator_dropped;
        }
    }

    // ---- Xenos register state -------------------------------------------
    const journal = &self.gpu_xenos_runtime.executor.register_file.journal;
    const register_totals = journal.summary();
    if (self.audit_registers.writes < register_totals.writes) {
        var pending = register_totals.writes - self.audit_registers.writes;
        while (pending > 0) : (pending -= 1) {
            self.audit_registers.write(0x2080, 1, .raster_setup, .pm4_stream, true, at_step);
        }
    }
    // The three registers that decide whether a draw has anywhere to go.
    // Mirrored individually rather than as a block count, because "the
    // render backend was touched" and "a colour target was named" are
    // different claims and the second is the one a frame depends on.
    for (gpu.register_journal.target_registers) |register| {
        const record = journal.target(register) orelse continue;
        if (record.writes == 0) continue;
        if (self.audit_registers.recordFor(register)) |seen| {
            if (seen.writes >= record.writes) continue;
        }
        self.audit_registers.write(
            register,
            record.last_value,
            .render_backend,
            .pm4_stream,
            true,
            at_step,
        );
    }

    // Interrupt delivery records are captured at executor log receipt.
    // Checkpoint totals cannot reconstruct missing per-delivery history.

    // ---- frame custody ----------------------------------------------------
    self.audit_frames.syncHandoffs(&self.cocoa_graphics.frames);

    // ---- synchronization identity -----------------------------------------
    for (self.wait_audit.subjects[0..self.wait_audit.count]) |subject| {
        const entry = self.audit_sync.intern(.{
            .address = .{ .guest_virtual = @truncate(subject.object) },
            .handle = subject.handle,
            .generation = 1,
            .kind = @intFromEnum(if (subject.timeout_class == .bounded_poll)
                sync_object_registry.ObjectKind.manual_reset_event
            else
                sync_object_registry.ObjectKind.unknown),
        }) orelse continue;
        entry.activity = .{
            .waits = subject.waits,
            .timeouts = subject.timeouts,
            .signals = subject.signals,
            .first_step = subject.first_step,
            .last_step = subject.last_step,
            .shape = if (subject.timeout_class == .bounded_poll) .bounded_poll else .unknown,
            .timeout_ms = subject.timeout_ms,
        };
    }

    // ---- translation and throughput budget ---------------------------------
    const economics = self.translation_economics.summary();
    if (self.audit_budget.required_guest_ms_per_host_second == 0) {
        self.audit_budget.declare(5, 2400);
    }
    self.audit_budget.observeTotals(
        self.elapsedHostSeconds() *| std.time.ns_per_s,
        self.run_horizon.latest.emulated_ms,
    );
    // Do not start the throughput clock on Rosette's instruction counter.
    // The latest run spent its first measured window in Xenia's own
    // CommitExecutableRange/import path, before the title's guest main
    // thread had retired an instruction. The pipeline boundary is the
    // authoritative handoff from host startup to guest execution.
    if (!self.audit_budget_guest_window.started and
        self.xenia_pipeline.hasReached(.guest_main_ready))
    {
        self.audit_budget_guest_window.begin(self.audit_budget.summary());
    }
    const mutable = self.audit_budget.pool(.mutable_generated);
    mutable.hits = self.decode_cache_hits;
    mutable.fills = economics.vacant_fills +| economics.conflict_fills +| economics.cold_evictions;
    mutable.conflict_evictions = economics.conflict_fills;
    mutable.stale_refills = economics.stale_refills;

    // ---- imports ------------------------------------------------------------
    // Every probed ordinal is on the graphics chain and has a guest side
    // effect: these are the video exports, and each writes a flag, returns
    // a handle or installs a callback. That makes an ABI probe a
    // prerequisite for resting a graphics conclusion on any of them.
    for (self.gpu_import_binding.entries[0..self.gpu_import_binding.count]) |entry| {
        const bound = entry.binding == .bound;
        _ = self.audit_imports.record(.{
            .module_id = 1,
            .ordinal = entry.ordinal,
            .target = entry.thunk_address,
            .thunk = entry.thunk_address,
            .binding = if (bound) .bound else .unresolved,
            // Binding probes inspect addresses and thunk bytes only.
            .abi = .unchecked,
            .on_graphics_chain = true,
            .has_guest_side_effect = true,
        });
    }

    self.syncAcceptanceGates(at_step);
}

pub fn syncAcceptanceGates(self: anytype, at_step: u64) void {
    const board = &self.audit_gates;
    const gate = &self.gpu_bringup_gate;

    const storage = self.audit_storage.summary();
    const journal_completeness = self.audit_journal.completeness();
    const journal_intact = self.audit_journal.criticalChannelIntact();
    const durable_ready = self.audit_durable_journal.started and
        !self.audit_durable_open_failed;
    const manifest_reason: acceptance_gates.Reason = if (!self.audit_manifest.sealed)
        .manifest_unsealed
    else if (!self.audit_manifest.sealIntact())
        .manifest_tampered
    else if (!durable_ready)
        .durable_journal_unavailable
    else if (journal_completeness == .empty)
        .journal_empty
    else if (!storage.baselineClean())
        .storage_short_read_on_chain
    else if (!journal_intact)
        .journal_channel_lost
    else
        .satisfied;
    _ = board.judge(
        .reproducible_manifest,
        if (!self.audit_manifest.sealed or journal_completeness == .empty)
            .unevaluable
        else if (self.audit_manifest.sealIntact() and durable_ready and
            storage.baselineClean() and journal_intact)
            .passed
        else
            .failed,
        manifest_reason,
        storage.short_reads_on_chain,
        at_step,
    );

    self.syncComponentReadiness();
    const substrate = self.component_readiness.substrateSummary();
    const budget_totals = self.runBudgetGuestWindowSummary();
    const budget = self.runBudgetGuestWindowVerdict(budget_totals);
    // A substrate component that nothing has exercised is not a broken
    // one. Most of the substrate can only be proven by the guest's own
    // first use, so before the title reaches it the honest verdict is that
    // the gate cannot yet be judged — and the owner of the remaining work
    // is the title, not the harness. Judging it `FAILED
    // owner=rosette:harness` put the frontier on Rosette for the first
    // 3.3 billion steps of the 2026-09-01 run, with nothing wrong.
    // An unprovable component is not an unproven one. The first is waiting
    // for the guest and the second cannot be answered here at all, and
    // only the first justifies withholding the verdict.
    const substrate_broken = substrate.failed != 0 or substrate.unprovable != 0;
    const substrate_reason: acceptance_gates.Reason = if (substrate_broken)
        .substrate_component_broken
    else if (budget == .observer_over_budget)
        .observers_over_budget
    else if (substrate.awaitingFirstUse())
        .substrate_awaiting_first_use
    else
        .satisfied;
    _ = board.judge(
        .substrate,
        if (substrate.total == 0)
            .unevaluable
        else if (substrate_broken or budget == .observer_over_budget)
            .failed
        else if (substrate.ready())
            .passed
        else
            .unevaluable,
        substrate_reason,
        @as(u64, substrate.failed) +| substrate.unproven,
        at_step,
    );

    const ring_crossed = gate.recordFor(.initialize_ring_buffer).crossed();
    const ring_published = self.audit_ring_transport.meetsPublicationGate();
    _ = board.judge(
        .gpu_bootstrap,
        if (ring_crossed and ring_published) .passed else .failed,
        if (!ring_crossed)
            .ring_never_initialized
        else if (ring_published)
            .satisfied
        else
            .ring_publication_incomplete,
        self.audit_ring_transport.summary().effective,
        at_step,
    );

    const pm4 = self.audit_pm4.verdict();
    _ = board.judge(
        .authoritative_pm4,
        switch (pm4) {
            .corroborated => if (self.audit_pm4.provesLiveExecution()) .passed else .unevaluable,
            .unobserved, .single_account, .uncomparable_accounts => .unevaluable,
            .decoder_disagreement, .semantic_defect => .failed,
        },
        switch (pm4) {
            .corroborated => if (self.audit_pm4.provesLiveExecution()) .satisfied else .pm4_live_execution_unobserved,
            .unobserved => .pm4_unobserved,
            .single_account => .pm4_single_account,
            .uncomparable_accounts => .pm4_accounts_uncomparable,
            .decoder_disagreement => .pm4_decoders_disagree,
            .semantic_defect => .pm4_semantic_defect,
        },
        @intFromEnum(pm4),
        at_step,
    );

    const target = self.audit_render_target.summary();
    _ = board.judge(
        .target_activity,
        if (!target.outputGateJudgeable())
            .unevaluable
        else if (target.first_pixel_candidates != 0)
            .passed
        else
            .failed,
        if (!target.outputGateJudgeable())
            .target_output_unjudgeable
        else if (target.first_pixel_candidates != 0)
            .satisfied
        else
            .target_no_output_bearing_draw,
        target.outputBearing(),
        at_step,
    );

    const producer = self.audit_producer.verdict(
        at_step,
        self.wait_audit.witness.advancedSince(self.never_notified_witness),
        false,
    );
    _ = board.judge(
        .guest_progress,
        switch (producer) {
            .advancing, .quiet_with_progress => .passed,
            .unobserved => .unevaluable,
            .waiting_on_missing_notifier, .quiet_without_a_reason, .suspended_by_pause => .failed,
        },
        switch (producer) {
            .advancing, .quiet_with_progress => .satisfied,
            .unobserved => .producer_unobserved,
            .waiting_on_missing_notifier => .producer_waiting_on_missing_notifier,
            .quiet_without_a_reason => .producer_quiet_without_a_reason,
            .suspended_by_pause => .producer_suspended_by_pause,
        },
        @intFromEnum(producer),
        at_step,
    );

    const swap_requested = gate.recordFor(.guest_swap_requested).crossed();
    _ = board.judge(
        .authentic_swap,
        if (swap_requested) .passed else .failed,
        if (swap_requested) .satisfied else .swap_never_requested,
        gate.recordFor(.guest_swap_requested).hits,
        at_step,
    );

    const custody = self.audit_frames.verdict();
    _ = board.judge(
        .frame_custody,
        switch (custody) {
            .authentic_presented => .passed,
            .no_candidate => .unevaluable,
            .diagnostic_only, .authentic_blocked, .authentic_lost => .failed,
        },
        switch (custody) {
            .authentic_presented => .satisfied,
            .no_candidate => .custody_no_candidate,
            .diagnostic_only => .custody_diagnostic_only,
            .authentic_blocked => .custody_blocked,
            .authentic_lost => .custody_lost,
        },
        self.audit_frames.tally.authenticFrames(),
        at_step,
    );

    const stable = self.audit_frames.stableOutput();
    _ = board.judge(
        .stable_output,
        if (stable) .passed else .failed,
        if (stable) .satisfied else .output_not_stable,
        self.audit_frames.tally.authenticFrames(),
        at_step,
    );
}

pub fn syncMonotoneWitnesses(self: anytype, at_step: u64) void {
    const bringup = gpu.bringup_gate;
    const Pair = struct { subject: monotone_witness.Subject, boundary: bringup.Boundary };
    const pairs = [_]Pair{
        .{ .subject = .draws_issued, .boundary = .issue_draw },
        .{ .subject = .render_target_updates, .boundary = .render_target_update },
        .{ .subject = .pm4_packets_consumed, .boundary = .execute_packet_type3 },
        .{ .subject = .vblank_marks, .boundary = .mark_vblank },
        .{ .subject = .graphics_interrupt_dispatches, .boundary = .dispatch_interrupt_callback },
        .{ .subject = .register_writes, .boundary = .write_register },
        .{ .subject = .ring_write_pointer_advances, .boundary = .write_pointer_updated },
    };
    for (pairs) |pair| {
        // An unarmed tracepoint has not looked, and a witness that has not
        // looked must not state a zero: that zero would become the short
        // reading in a comparison it was never part of.
        if (!self.execution_tracepoints.boundaryArmed(@intFromEnum(pair.boundary))) continue;
        const record = self.gpu_bringup_gate.recordFor(pair.boundary);
        // The bring-up gate already knows whether this boundary is
        // downstream of a missing prerequisite. Do not turn a blocked
        // zero into an observation: doing so closes the monotone set before
        // the guest has reached the corresponding phase and was the cause
        // of the false all-required-witnesses-corroborated stop in the
        // 2026-09-04 run. A zero is only meaningful for an eligible,
        // never-crossed boundary; a positive crossing is always retained.
        if (!bringup.tracepointWitnessMayState(
            record,
            self.gpu_bringup_gate.state(pair.boundary, at_step),
        )) continue;
        self.monotone_witness.state(
            pair.subject,
            .rosette_tracepoint,
            record.hits,
            at_step,
        );
    }
    // Emulator counters are stated at log receipt, under their own event
    // definitions and source timestamps (guest_log.zig). Re-reading a
    // cached total here must never manufacture a fresh witness statement.
    // Rosette's own reading of the title-callback transaction, so the
    // report shows whether the repaired ledger has actually caught up with
    // the executor rather than only that the executor said so.
    const title_callback = &self.interrupt_callback_transaction;
    // Registration is not a zero dispatch/return observation. Until the
    // title callback executor has actually attempted a dispatch, neither
    // counter has reached an eligible observation boundary. Treating the
    // registration-only state as two zeroes manufactured closure in runs
    // that had merely installed the callback and were still booting.
    if (title_callback.dispatch_attempts != 0) {
        self.monotone_witness.state(
            .title_interrupt_callback_entries,
            .rosette_derived_ledger,
            title_callback.dispatch_attempts,
            title_callback.last_step,
        );
        self.monotone_witness.state(
            .title_interrupt_callback_returns,
            .rosette_derived_ledger,
            title_callback.callback_returns,
            title_callback.last_step,
        );
    } else if (title_callback.callback_returns != 0) {
        // A malformed or partially retained completion can expose a
        // return total without its entry total. Preserve that evidence as
        // a hole rather than manufacturing an entry zero.
        self.monotone_witness.state(
            .title_interrupt_callback_returns,
            .rosette_derived_ledger,
            title_callback.callback_returns,
            title_callback.last_step,
        );
    }
    self.monotone_witness.settle(at_step);
}

pub fn syncBootstrapProvenanceTracepoints(self: anytype) void {
    const bringup = gpu.bringup_gate;
    const Pair = struct { step: gpu.Step, boundary: bringup.Boundary };
    const pairs = [_]Pair{
        .{ .step = .initialize_engines, .boundary = .initialize_engines },
        .{ .step = .graphics_interrupt_callback, .boundary = .set_interrupt_callback },
        .{ .step = .ring_buffer, .boundary = .initialize_ring_buffer },
        .{ .step = .rptr_writeback, .boundary = .enable_rptr_write_back },
    };
    for (pairs) |pair| {
        const record = self.gpu_bringup_gate.recordFor(pair.boundary);
        if (!record.crossed()) continue;
        self.gpu_bootstrap_provenance.observeTrace(
            pair.step,
            record.hits,
            record.first_step,
            record.last_step,
        );
    }
}

pub fn syncGraphicsEvidence(self: anytype) void {
    const evidence = gpu.evidence_grade;
    const bringup = gpu.bringup_gate;
    const tracepoints = &self.execution_tracepoints;
    const at_step = self.executed_steps;

    const Pairing = struct {
        subject: evidence.Subject,
        boundary: bringup.Boundary,
        observer: []const u8,
    };
    // Instruction-pointer evidence first, because it is the only kind
    // nothing in the system can forge.
    const traced = [_]Pairing{
        .{ .subject = .gpu_engines_initialized, .boundary = .initialize_engines, .observer = "tracepoint:VdInitializeEngines_entry" },
        .{ .subject = .interrupt_callback_registered, .boundary = .set_interrupt_callback, .observer = "tracepoint:VdSetGraphicsInterruptCallback_entry" },
        .{ .subject = .vblank_pump_live, .boundary = .mark_vblank, .observer = "tracepoint:MarkVblank" },
        .{ .subject = .ring_initialized, .boundary = .initialize_ring_buffer, .observer = "tracepoint:VdInitializeRingBuffer_entry" },
        .{ .subject = .ring_write_pointer_published, .boundary = .write_pointer_updated, .observer = "tracepoint:UpdateWritePointer" },
        .{ .subject = .command_processor_running, .boundary = .execute_primary_buffer, .observer = "tracepoint:ExecutePrimaryBuffer" },
        .{ .subject = .pm4_packets_consumed, .boundary = .execute_packet_type3, .observer = "tracepoint:ExecutePacketType3" },
        .{ .subject = .render_target_programmed, .boundary = .render_target_update, .observer = "tracepoint:RenderTargetCache::Update" },
        .{ .subject = .draws_issued, .boundary = .issue_draw, .observer = "tracepoint:IssueDraw" },
        .{ .subject = .swap_requested_by_title, .boundary = .guest_swap_requested, .observer = "tracepoint:VdSwap_entry" },
        .{ .subject = .swap_packet_decoded, .boundary = .xe_swap_decoded, .observer = "tracepoint:ExecutePacketType3_XE_SWAP" },
        .{ .subject = .guest_frame_presented, .boundary = .refresh_guest_output, .observer = "tracepoint:RefreshGuestOutput" },
    };
    for (traced) |pairing| {
        const index: u8 = @intFromEnum(pairing.boundary);
        if (!tracepoints.boundaryArmed(index)) continue;
        const record = self.gpu_bringup_gate.recordFor(pairing.boundary);
        self.gpu_evidence.observe(pairing.subject, .{
            .tier = .instruction_pointer,
            .observer = pairing.observer,
            .step = if (record.crossed()) record.first_step else at_step,
            .magnitude = record.hits,
            .present = record.crossed(),
        });
    }

    // EmulateCPInterruptDPC is shared by Rosette's host fallback and the
    // title's PowerPC callback. The tracepoint alone therefore cannot
    // answer "entered guest code". The transaction ledger is fed by
    // domain-labelled Xenia breadcrumbs and is the only log-level source
    // admitted for this subject.
    const title_callback = &self.interrupt_callback_transaction;
    const title_callback_ordered =
        title_callback.registrationPrecedesDispatch() and
        title_callback.callback_address >= 0x8000_0000 and
        title_callback.callback_address < 0xC000_0000;
    if (title_callback_ordered) {
        self.gpu_evidence.observe(.interrupt_callback_entered_guest, .{
            .tier = .emulator_log_claim,
            .observer = "xenia-guest-callback-transaction",
            .step = if (title_callback.first_dispatch_step != 0)
                title_callback.first_dispatch_step
            else
                at_step,
            .magnitude = title_callback.dispatch_attempts,
            .present = true,
        });
    } else if (title_callback.dispatch_attempts != 0) {
        machoCapturePrint(
            "macho-processor: GPU CALLBACK ORDERING: title dispatch evidence was withheld because no ordered title registration precedes it (registrations={d} dispatches={d} first_registration_step={d} first_dispatch_step={d} callback=0x{x:0>8}); the dispatch remains a strict violation candidate and cannot substantiate guest interrupt entry\n",
            .{
                title_callback.registrations,
                title_callback.dispatch_attempts,
                title_callback.first_registration_step,
                title_callback.first_dispatch_step,
                title_callback.callback_address,
            },
        );
    }

    // The emulator's own log claims, at the tier that says what they are
    // worth. These are the source of the disagreements this ledger exists
    // to adjudicate: a bootstrap gate that reported `ring_init=NO` at
    // 2303 ms is not wrong, it is early, and the ledger's staleness rule is
    // what turns that from a live contradiction into a footnote.
    const ClaimPairing = struct {
        subject: gpu.evidence_grade.Subject,
        claim: claim_reconciliation.Claim,
        observer: []const u8,
    };
    const logged = [_]ClaimPairing{
        .{ .subject = .ring_initialized, .claim = .ring_initialised, .observer = "xenia-bootstrap-claim" },
        .{ .subject = .interrupt_callback_registered, .claim = .interrupt_callback_set, .observer = "xenia-bootstrap-claim" },
    };
    for (logged) |pairing| {
        const reading = self.claim_reconciliation.reconcile(pairing.claim);
        if (reading.observers == 0) continue;
        self.gpu_evidence.observe(pairing.subject, .{
            .tier = .emulator_log_claim,
            .observer = pairing.observer,
            .step = reading.current_step,
            .magnitude = reading.current_value,
            .present = reading.current_value != 0,
        });
    }

    // Rosette's own scans of guest memory. Uninitialised memory matches a
    // great many patterns, so these are offered at the tier that says so.
    const publication = &self.gpu_ring_publication;
    if (publication.writes != 0) {
        self.gpu_evidence.observe(.ring_write_pointer_published, .{
            .tier = .emulator_counter,
            .observer = "ring-publication-ledger",
            .step = publication.last_advance_step,
            .magnitude = publication.advances,
            .present = publication.published(),
        });
    }
    const consumed = self.gpu_vd_swap_contract;
    if (consumed.authentic_consumptions != 0) {
        self.gpu_evidence.observe(.swap_packet_decoded, .{
            .tier = .memory_scan,
            .observer = "ring-memory-scan",
            .step = at_step,
            .magnitude = consumed.authentic_consumptions,
            .present = true,
        });
    }
}

pub fn syncCompletionRoutes(self: anytype, at_step: u64) void {
    const bringup = gpu.bringup_gate;
    const routes = &self.gpu_completion_routes;

    const registration = self.gpu_bringup_gate.recordFor(.set_interrupt_callback);
    const registration_provenance =
        self.gpu_bootstrap_provenance.record(.graphics_interrupt_callback);
    const registration_observed = registration.crossed() or
        registration_provenance.guestObserved();
    const registration_step = if (registration.crossed())
        registration.first_step
    else
        registration_provenance.guest_first_step;
    // The slot line is the emulator saying what it will dispatch into, and
    // it supersedes the registration ledger — which reported zero for a
    // registration that plainly happened because nothing parsed it.
    const registration_address = if (self.gpu_interrupt_slot_is_guest and
        self.gpu_interrupt_slot_address != 0)
        self.gpu_interrupt_slot_address
    else if (self.interrupt_callback_transaction.callback_address != 0)
        self.interrupt_callback_transaction.callback_address
    else
        self.gpu_interrupt_slot_address;
    if (registration_observed) {
        routes.noteRequested(.interrupt_callback, registration_step);
        // The registered address is the title's own callback. Rosette does
        // not invent one: an address the harness supplies here would make
        // an inert route read established, which is the failure mode this
        // ledger exists to catch.
        if (registration_address != 0) {
            routes.noteEstablished(
                .interrupt_callback,
                registration_address,
                registration_step,
            );
        }
    }
    // Something other than the title in the slot is recorded before any
    // delivery is counted, so a dispatch into a Xenia-owned host callback
    // is never mistaken for the title receiving its completion. The first
    // pass counted thirty-four of those as deliveries and called the route
    // live while the title's own callback was still unreached.
    // Only while a non-guest address is actually in the slot. The emulator's
    // host callback being installed once and then superseded by the title
    // is not an occupied slot, and reporting it as one made a resolved
    // situation look like a live defect for the rest of the run.
    if (self.gpu_interrupt_slot_writes != 0 and !self.gpu_interrupt_slot_is_guest) {
        routes.noteForeignOccupant(.interrupt_callback, self.gpu_interrupt_slot_address);
    } else if (self.gpu_interrupt_slot_is_guest) {
        // Occupancy is current state, not history. The host callback is
        // installed during bring-up and the title's registration displaces
        // it; a latched occupant made every later delivery foreign and
        // printed `INERT ... an emulator defect and not a title one` about
        // a callback the emulator was entering. The release keeps the
        // displaced address, so nothing about the handover is lost.
        routes.clearForeignOccupant(.interrupt_callback);
    }
    // The generic dispatch and EmulateCPInterruptDPC tracepoints are
    // shared by the Rosette host callback and the title callback. They are
    // therefore not valid route evidence on their own. Use the title's
    // domain-labelled transaction, and count each transition once so a
    // repeated graphics checkpoint cannot manufacture deliveries.
    const title_callback = &self.interrupt_callback_transaction;
    var callback_route = routes.status(.interrupt_callback);
    if (title_callback.dispatch_attempts != 0 and callback_route.attempts == 0) {
        routes.noteAttempt(
            .interrupt_callback,
            if (title_callback.first_dispatch_step != 0)
                title_callback.first_dispatch_step
            else
                at_step,
        );
        callback_route = routes.status(.interrupt_callback);
    }
    if (title_callback.callback_returns != 0 and
        callback_route.deliveries == 0 and
        callback_route.foreign_deliveries == 0)
    {
        routes.noteDelivery(
            .interrupt_callback,
            if (title_callback.first_return_step != 0)
                title_callback.first_return_step
            else
                at_step,
        );
    }

    const writeback = self.gpu_bringup_gate.recordFor(.enable_rptr_write_back);
    const writeback_provenance =
        self.gpu_bootstrap_provenance.record(.rptr_writeback);
    const writeback_observed = writeback.crossed() or
        writeback_provenance.guestObserved();
    const writeback_step = if (writeback.crossed())
        writeback.first_step
    else
        writeback_provenance.guest_first_step;
    if (writeback_observed) {
        routes.noteRequested(.read_pointer_write_back, writeback_step);
        if (self.gpu_read_pointer_writeback_address != 0) {
            routes.noteEstablished(
                .read_pointer_write_back,
                self.gpu_read_pointer_writeback_address,
                writeback_step,
            );
            // The word changing is the delivery. The emulator reporting
            // that it wrote one is not: a word written with the same value
            // forever is inert to the poller reading it.
            if (self.readConsolePhysicalDword(self.gpu_read_pointer_writeback_address)) |value| {
                routes.sampleValue(.read_pointer_write_back, value, at_step);
            }
        }
    }
    const vblank = self.gpu_bringup_gate.recordFor(.mark_vblank);
    if (vblank.crossed()) {
        routes.noteRequested(.vblank_counter, vblank.first_step);
        // The vblank counter is a register the title polls, not a word the
        // emulator writes, so it is established by the pump running. Passing
        // a placeholder address printed `address=0x00000001`, which is a
        // number in the report that means nothing.
        routes.noteEstablished(.vblank_counter, 0, vblank.first_step);
        routes.noteDelivery(.vblank_counter, vblank.last_step);
    }
    _ = bringup;
}

pub fn syncProducerAttribution(self: anytype) void {
    const publications = self.gpu_ring_publication.retainedAdvances();
    if (publications.len == 0) return;
    var observed = false;
    for (publications) |record| {
        if (!record.producer.valid or record.producer.guest_thread == 0) continue;
        observed = true;
        self.gpu_producer_stall.attribute(record.producer.guest_thread, record.step);
        if (record.step > self.gpu_producer_stall.published_at_step) {
            self.gpu_producer_stall.notePublication(record.step);
        } else if (self.gpu_producer_stall.publications == 0) {
            self.gpu_producer_stall.notePublication(record.step);
        }
    }
    if (!observed and !self.gpu_producer_stall.producer_known) {
        self.gpu_producer_stall.noteAttributionLost();
    }
}

pub fn syncComponentReadiness(self: anytype) void {
    const readiness = &self.component_readiness;
    const at_step = self.executed_steps;
    const gate = &self.gpu_bringup_gate;

    // ---- what Rosette exercises itself ---------------------------------
    if (self.xenia_memory_views.ready()) {
        readiness.noteProven(.guest_memory_aliasing, at_step, "rosette:memory-view-model");
    }
    const clock = self.host_capabilities.finding(.monotonic_clock_resolution);
    if (clock.outcome == .verified) {
        readiness.noteProven(.guest_timer_source, clock.measured_value, "rosette:host-capability-probe");
    }
    if (self.dynamic_forwarder.nativePresenterFramesPresented() != 0) {
        readiness.noteProven(.host_graphics_device, at_step, "rosette:native-presenter-device");
        readiness.noteProven(.host_surface_presentation, at_step, "rosette:native-presenter-frame");
    }

    // ---- what only the guest's own use can prove ------------------------
    const Pairing = struct {
        component: preflight_lib.component_readiness.Component,
        boundary: gpu.bringup_gate.Boundary,
        prover: []const u8,
    };
    const traced = [_]Pairing{
        .{ .component = .kernel_export_table, .boundary = .initialize_engines, .prover = "tracepoint:VdInitializeEngines_entry" },
        .{ .component = .register_aperture_dispatch, .boundary = .write_register, .prover = "tracepoint:CommandProcessor::WriteRegister" },
        .{ .component = .ring_memory_visibility, .boundary = .execute_primary_buffer, .prover = "tracepoint:ExecutePrimaryBuffer" },
        .{ .component = .command_processor_drain, .boundary = .execute_packet_type3, .prover = "tracepoint:ExecutePacketType3" },
        .{ .component = .render_target_binding, .boundary = .render_target_update, .prover = "tracepoint:RenderTargetCache::Update" },
        .{ .component = .frame_handoff_to_window, .boundary = .refresh_guest_output, .prover = "tracepoint:RefreshGuestOutput" },
    };
    for (traced) |pairing| {
        const record = gate.recordFor(pairing.boundary);
        if (record.crossed()) {
            readiness.noteProven(pairing.component, record.first_step, pairing.prover);
        }
    }

    // The interrupt is only proven to reach the *title* when the callback
    // transaction has an ordered title registration and a returned
    // dispatch at a guest address. The generic DPC tracepoint can enter a
    // harness callback too, and the live slot can be replaced before a
    // later checkpoint, so the transaction ledger is the authority here.
    const entered = gate.recordFor(.emulate_cp_interrupt_dpc);
    if (entered.crossed() and self.gpu_interrupt_slot_is_guest) {
        readiness.noteProven(
            .interrupt_delivery_into_guest,
            entered.first_step,
            "tracepoint:EmulateCPInterruptDPC + guest-owned slot",
        );
    }
    if (self.interrupt_callback_transaction.guestTitleRoundTripProven()) {
        readiness.noteProven(
            .interrupt_delivery_into_guest,
            self.interrupt_callback_transaction.first_return_step,
            "xenia:guest-callback transaction round-trip",
        );
    }

    // Event signalling is proven by a waiter *waking because of* a signal,
    // not by a set call returning. `blocked_released` is the only counter
    // that means the handoff completed.
    if (comptime @hasField(MachOState, "guest_wait_liveness")) {
        // `provesSignalConsumption` is the only predicate that means a
        // waiter actually blocked and was released by a signal. A set call
        // returning, or a wait returning because it was already signalled,
        // proves nothing about the handoff.
        if (self.guest_wait_liveness.provesSignalConsumption()) {
            readiness.noteProven(
                .guest_event_signalling,
                at_step,
                "guest-wait-liveness:blocked-then-released",
            );
        }
        if (self.guest_wait_liveness.total_waits != 0) {
            readiness.noteUsed(.guest_event_signalling, at_step);
        }
    }
    if (self.ready.translationProgressGeneration() != 0) {
        readiness.noteProven(.guest_code_translation, at_step, "ready-compiler:translation-generation");
    }
    if (self.pthreads.created_threads != 0) {
        readiness.noteProven(.guest_thread_scheduling, at_step, "pthread-runtime:created-and-scheduled");
        readiness.noteUsed(.guest_thread_scheduling, at_step);
    }
    if (self.critical_section_initial_valid) {
        readiness.noteProven(.guest_critical_sections, at_step, "guest-critical-section:baseline-observed");
    }
    if (self.xenia_gpu_handoff.shader_completion_commits != 0) {
        readiness.noteProven(.shader_translation, at_step, "xenia-gpu-handoff:shader-commit");
    }

    // ---- what the guest has depended on --------------------------------
    const uses = [_]Pairing{
        .{ .component = .kernel_export_table, .boundary = .query_video_mode, .prover = "" },
        .{ .component = .guest_memory_aliasing, .boundary = .initialize_ring_buffer, .prover = "" },
        .{ .component = .ring_memory_visibility, .boundary = .write_pointer_updated, .prover = "" },
        .{ .component = .register_aperture_dispatch, .boundary = .write_pointer_updated, .prover = "" },
        .{ .component = .command_processor_drain, .boundary = .write_pointer_updated, .prover = "" },
        .{ .component = .interrupt_delivery_into_guest, .boundary = .set_interrupt_callback, .prover = "" },
        .{ .component = .shader_translation, .boundary = .issue_draw, .prover = "" },
        .{ .component = .frame_handoff_to_window, .boundary = .guest_swap_requested, .prover = "" },
        .{ .component = .guest_timer_source, .boundary = .mark_vblank, .prover = "" },
        .{ .component = .host_graphics_device, .boundary = .execute_primary_buffer, .prover = "" },
        .{ .component = .host_surface_presentation, .boundary = .host_paint, .prover = "" },
        .{ .component = .guest_critical_sections, .boundary = .initialize_engines, .prover = "" },
        .{ .component = .guest_code_translation, .boundary = .query_video_mode, .prover = "" },
    };
    for (uses) |pairing| {
        const record = gate.recordFor(pairing.boundary);
        if (record.crossed()) readiness.noteUsed(pairing.component, record.first_step);
    }

    // Entering IssueDraw is not the same as depending on a render target.
    //
    // A draw with rasterization disabled and no memory export leaves the
    // command processor before the render target cache is consulted, and
    // it does so because of what the title programmed. Counting it as a
    // use put `render target binding USED-UNPROVEN owner=emulator:gpu` at
    // the top of the readiness report — with `draws are issued with
    // nowhere to land ... which looks exactly like rendering that produced
    // a black frame` — for a batch of twenty-four draws that the emulator
    // had already classified, by name, as legitimately having no effect.
    // Two Rosette reports, two owners, one fact.
    //
    // So the dependency is recorded when a draw actually reached the
    // target, when the emulator classified an exit as its own failure, or
    // when no exit has been named at all — because an unattributed gap
    // must not be excused by the absence of the very evidence that would
    // excuse it.
    const draws = gate.recordFor(.issue_draw);
    if (draws.crossed()) {
        const exits_are_title_owned =
            self.gpu_draw_exits_named != 0 and self.gpu_draw_defect_exits == 0;
        const reached = gate.recordFor(.render_target_update).crossed() or
            self.gpu_draws_reached_render_target != 0;
        if (reached or !exits_are_title_owned) {
            readiness.noteUsed(.render_target_binding, draws.first_step);
        }
    }
}

pub fn logComponentReadiness(self: anytype) void {
    const module = preflight_lib.component_readiness;
    self.syncComponentReadiness();
    const readiness = &self.component_readiness;
    const totals = readiness.summary();
    machoCapturePrint(
        "macho-processor: COMPONENT READINESS: ready={d}% proven={d}/{d} unproven={d} broken={d} used_unproven={d} proven_after_use={d} provable_early_but_unproven={d} essential_gaps={d} step={d}; {s}\n",
        .{
            totals.readyPercent(),
            totals.proven,
            module.component_count,
            totals.unproven,
            totals.broken,
            totals.used_unproven,
            totals.proven_after_use,
            totals.provable_early_but_unproven,
            totals.essential_gaps,
            self.executed_steps,
            totals.describe(),
        },
    );
    if (readiness.firstFinding()) |first| {
        machoCapturePrint(
            "  COMPONENT READINESS SUBJECT: {s} owner={s} proof={s}; {s}\n",
            .{ first.label(), first.owner(), first.proof().label(), first.blindRisk() },
        );
        machoCapturePrint(
            "    obligation: {s}\n",
            .{first.obligation()},
        );
    }
    // The substrate gate's own blockers, named. An idle row is skipped
    // below because most idle components say nothing; an idle *substrate*
    // component is the reason `G1` cannot be judged, and leaving it out
    // left the gate reporting a count with nothing behind it.
    if (readiness.firstUnprovenSubstrate()) |blocker| {
        machoCapturePrint(
            "  COMPONENT READINESS SUBSTRATE: G1 is held by {s} owner={s} proof={s} used={s}; {s}\n",
            .{
                blocker.label(),
                blocker.owner(),
                blocker.proof().label(),
                if (readiness.recordFor(blocker).used) "YES" else "NO",
                if (blocker.proof().availableBeforeFirstUse())
                    "this one could be exercised before the guest runs, so it is Rosette's to close and costs nothing to close"
                else
                    "this one can only be proven by the guest's own use completing, so it is the title's to reach and not a defect until it does",
            },
        );
    }
    for (module.allComponents()) |component| {
        const standing = readiness.standing(component);
        const record = readiness.recordFor(component);
        if (standing == .idle) {
            if (!module.isSubstrate(component) or record.proven()) continue;
            machoCapturePrint(
                "  component {s: <18} {s: <12} {s: <30} owner={s: <16} proven_step={d} first_use_step={d} uses={d} by={s}\n",
                .{
                    "awaiting-use",
                    record.state.label(),
                    component.label(),
                    component.owner(),
                    record.proven_step,
                    record.first_use_step,
                    record.uses,
                    "<nothing yet>",
                },
            );
            continue;
        }
        machoCapturePrint(
            "  component {s: <18} {s: <12} {s: <30} owner={s: <16} proven_step={d} first_use_step={d} uses={d} by={s}\n",
            .{
                standing.label(),
                record.state.label(),
                component.label(),
                component.owner(),
                record.proven_step,
                record.first_use_step,
                record.uses,
                if (record.prover.len != 0) record.prover else "<nothing>",
            },
        );
    }
}

pub fn syncPacketCensus(self: anytype) void {
    const histogram = self.gpu_xenos_runtime.executor.opcode_histogram;
    for (histogram, 0..) |seen, opcode| {
        if (seen == 0) continue;
        if (self.gpu_packet_census.countOf(@enumFromInt(opcode)) >= seen) continue;
        var pending = seen - @as(u32, @intCast(@min(
            seen,
            self.gpu_packet_census.countOf(@enumFromInt(opcode)),
        )));
        while (pending > 0) : (pending -= 1) {
            self.gpu_packet_census.observePacket(@intCast(opcode), self.executed_steps);
        }
    }
}

pub fn logPumpLiveness(self: anytype) void {
    const bringup = gpu.bringup_gate;
    const at_step = self.executed_steps;
    var live: u8 = 0;
    var stalled: u8 = 0;
    var never: u8 = 0;
    var not_eligible: u8 = 0;
    for (bringup.contractBoundaries()) |boundary| {
        if (boundary.cadence() != .repeating) continue;
        const record = self.gpu_bringup_gate.recordFor(boundary);
        if (!record.crossed()) {
            never += 1;
            continue;
        }
        switch (self.gpu_bringup_gate.state(boundary, at_step)) {
            .stalled_after_crossing => stalled += 1,
            .not_eligible => not_eligible += 1,
            else => live += 1,
        }
    }
    if (live == 0 and stalled == 0 and not_eligible == 0) return;
    machoCapturePrint(
        "macho-processor: GPU PUMP LIVENESS: live={d} stalled={d} not_eligible={d} never_started={d} step={d}; only autonomous pumps appear below. Ring publication, command decode, register writes, draws, notification routines, swaps, refresh and Cocoa paint are event-driven and cannot become stalled merely because the last batch drained; not_eligible means source provenance disqualified an otherwise repeating heartbeat\n",
        .{ live, stalled, not_eligible, never, at_step },
    );
    for (bringup.contractBoundaries()) |boundary| {
        if (boundary.cadence() != .repeating) continue;
        const record = self.gpu_bringup_gate.recordFor(boundary);
        if (!record.crossed()) continue;
        machoCapturePrint(
            "  gpu-pump {s: <9} {s: <45} hits={d} first_step={d} last_step={d} quiet_for={d}\n",
            .{
                self.gpu_bringup_gate.state(boundary, at_step).label(),
                boundary.label(),
                record.hits,
                record.first_step,
                record.last_step,
                self.gpu_bringup_gate.quietFor(boundary, at_step),
            },
        );
    }
}

pub fn logPacketCensus(self: anytype) void {
    self.syncPacketCensus();
    const ledger = &self.gpu_packet_census;
    const totals = ledger.summary();
    if (totals.packets == 0 and ledger.emulator_packets == 0) return;
    const verdict = ledger.verdict();
    machoCapturePrint(
        "macho-processor: GPU PACKET CENSUS: verdict={s} distinct={d} rosette_packets={d} emulator_packets={d} draws={d} blocking={d} completion_requests(rosette/emulator_interrupt/emulator_event)={d}/{d}/{d} interrupt_requests={d} interrupts_delivered(vblank/command_stream)={d}/{d} memory_completions(delivered/alias_mismatch)={d}/{d} interrupt_dispatch(entered/returned/outstanding)={d}/{d}/{d} vblank_floor_raises={d} emulator_extensions={d} unnamed={d} dropped={d} step={d}; {s}\n",
        .{
            verdict.label(),
            totals.distinct,
            totals.packets,
            ledger.emulator_packets,
            totals.draws,
            totals.blocking,
            totals.completion_requests,
            ledger.emulator_interrupt_requests,
            ledger.emulator_event_write_requests,
            totals.interrupt_requests,
            ledger.interrupts_by_source[0],
            ledger.commandStreamInterrupts(),
            ledger.memory_completions_delivered,
            ledger.memory_completion_alias_mismatches,
            ledger.interrupt_dispatch_entered,
            ledger.interrupt_dispatch_returned,
            ledger.outstandingInterruptDispatches(),
            ledger.vblank_floor_raises,
            totals.emulator_extensions,
            totals.unnamed,
            totals.dropped,
            self.executed_steps,
            verdict.describe(),
        },
    );
    if (ledger.outstandingInterruptDispatches() != 0) {
        machoCapturePrint(
            "  GPU PACKET CENSUS INTERRUPT STUCK: {d} graphics interrupt dispatch(es) entered guest code and have not returned. The dispatch runs the title's handler on the calling thread, so the thread that made it — the frame limiter — is inside guest code and is not coming back. Every pump that thread drives is dead from that moment, and its last recorded event was a successful entry\n",
            .{ledger.outstandingInterruptDispatches()},
        );
    }
    if (ledger.vblank_floor_raises != 0) {
        machoCapturePrint(
            "  GPU PACKET CENSUS VBLANK FLOOR: {d} vblank(s) were raised by the emulator's wall-clock floor rather than by the guest clock. The guest clock is not pacing the display, so every deadline the title computes from it is stretched by the same factor — read TIMEOUT FIDELITY next\n",
            .{ledger.vblank_floor_raises},
        );
    }
    for (ledger.observed()) |entry| {
        const typed = entry.typed();
        machoCapturePrint(
            "  packet opcode=0x{x:0>2} {s: <22} count={d} first_step={d} last_step={d}{s}{s}{s}\n",
            .{
                entry.opcode,
                entry.name(),
                entry.count,
                entry.first_step,
                entry.last_step,
                if (typed.isDraw()) " draw" else "",
                if (typed.isBlocking()) " blocking" else "",
                if (typed.requestsCompletion()) " COMPLETION-REQUEST" else "",
            },
        );
    }
}

pub fn logSignalExpectation(self: anytype) void {
    const ledger = &self.signal_expectation;
    const verdict = ledger.verdict();
    const totals = ledger.summary();
    if (verdict == .quiet) return;
    machoCapturePrint(
        "macho-processor: SIGNAL EXPECTATION: verdict={s} tracked={d} matched={d} orphan_waits(total/blocking/polling)={d}/{d}/{d} orphan_signals={d} dropped={d} split_identity_suspected={s} attributed={d}/{d} creation_facts_dropped={d} step={d}; {s}\n",
        .{
            verdict.label(),
            totals.tracked,
            totals.matched,
            totals.orphan_waits,
            totals.blocking_orphan_waits,
            totals.polling_orphans,
            totals.orphan_signals,
            totals.dropped,
            if (ledger.looksLikeSplitIdentity()) "YES" else "NO",
            // How many tracked objects Rosette can say were created. The
            // provenance field exists so a "nothing signals it" finding can
            // name an owner; a count of how often it cannot is the honest
            // companion to that claim rather than a silent `unknown` per row.
            totals.tracked -| ledger.unattributed(),
            totals.tracked,
            ledger.pending_dropped,
            self.executed_steps,
            verdict.describe(),
        },
    );
    if (ledger.unattributed() != 0) {
        machoCapturePrint(
            "  SIGNAL EXPECTATION ATTRIBUTION: {d} tracked object(s) have no observed creation, so a finding against them names no owner. An object created through a kernel export and one that only ever appeared as a handle registration carry different weight when nothing signals them, and an object with neither was never seen entering the emulator at all\n",
            .{ledger.unattributed()},
        );
    }
    // Which pair, and how far apart. A `YES` with no addresses beside it
    // leaves the reader to find the pair by eye across a table, which is
    // the work the exhaustive comparison was added to do.
    if (ledger.findSplitIdentity()) |split| {
        machoCapturePrint(
            "  signal-expectation SPLIT IDENTITY: waited=0x{x} signalled=0x{x} bias=0x{x} same_address={s}; the two rows agree on their low half, so they are very likely one console object seen through two address views. Compare their handles and creation provenance before treating either half as a finding\n",
            .{
                split.waited,
                split.signalled,
                split.bias,
                if (split.sameAddress()) "YES" else "NO",
            },
        );
    }
    if (ledger.worstOrphanWait()) |waited| {
        const symbol = self.metadata.nearestSymbol(waited.guest_pc);
        machoCapturePrint(
            "  signal-expectation ORPHAN WAIT: object=0x{x} handle=0x{x:0>8} waits={d} timeouts={d} signals=0 timeout_ms={d} mode={s} waiter_thread=0x{x} guest_pc=0x{x} guest_lr=0x{x} pc_trusted={s} provenance={s} first_step={d} last_step={d}{s}{s}\n",
            .{
                waited.object,
                waited.handle,
                waited.waits,
                waited.timeouts,
                waited.timeout_ms,
                if (waited.polling()) "polling" else "parked",
                waited.waiter_thread,
                waited.guest_pc,
                waited.guest_lr,
                if (waited.guest_pc_trusted) "YES" else "NO",
                waited.provenance.label(),
                waited.first_step,
                waited.last_step,
                if (symbol != null) " nearest_symbol=" else "",
                if (symbol) |resolved| resolved.name else "",
            },
        );
        if (waited.guest_pc_trusted) {
            machoCapturePrint(
                "    signal-expectation: the guest program counter above is the title's own instruction, not the emulator's slot. That address and its link register are what a disassembly of the title can be looked up against; the object address cannot\n",
                .{},
            );
        } else {
            // The link register is written by the call instruction itself,
            // so it names the caller even when the program counter has been
            // seeded from a processor entry. Dropping both because one is
            // untrusted threw away the only address a disassembly of the
            // title could be looked up against.
            if (waited.guest_lr != 0) {
                machoCapturePrint(
                    "    signal-expectation: the guest program counter is seeded and cannot be trusted, but the link register 0x{x} is written by the call instruction itself and still names the title's caller. Look that up in the title before treating this waiter as unlocatable\n",
                    .{waited.guest_lr},
                );
            } else {
                machoCapturePrint(
                    "    signal-expectation: no trusted guest program counter and no link register were captured for this waiter, so the title's own call site is unknown. The object address names a slot in the emulator and cannot be looked up in the title — this is a hole in the observer, not a fact about the guest\n",
                    .{},
                );
            }
        }
    }
    if (ledger.worstPollingOrphan()) |polled| {
        const symbol = self.metadata.nearestSymbol(polled.guest_pc);
        machoCapturePrint(
            "  signal-expectation BOUNDED POLL: object=0x{x} handle=0x{x:0>8} waits={d} timeouts={d} signals=0 timeout_ms={d} waiter_thread=0x{x} guest_pc=0x{x} guest_lr=0x{x} pc_trusted={s} provenance={s} first_step={d} last_step={d}{s}{s}; this waiter returned through a finite deadline and is reported as polling context, never as the parked half of an unmatched handshake\n",
            .{
                polled.object,
                polled.handle,
                polled.waits,
                polled.timeouts,
                polled.timeout_ms,
                polled.waiter_thread,
                polled.guest_pc,
                polled.guest_lr,
                if (polled.guest_pc_trusted) "YES" else "NO",
                polled.provenance.label(),
                polled.first_step,
                polled.last_step,
                if (symbol != null) " nearest_symbol=" else "",
                if (symbol) |resolved| resolved.name else "",
            },
        );
    }
    if (ledger.worstOrphanSignal()) |signalled| {
        machoCapturePrint(
            "  signal-expectation ORPHAN SIGNAL: object=0x{x} handle=0x{x:0>8} signals={d} waits=0 signaller_thread=0x{x} signaller_pc=0x{x} provenance={s} first_step={d} last_step={d}\n",
            .{
                signalled.object,
                signalled.handle,
                signalled.signals,
                signalled.signaller_thread,
                signalled.signaller_pc,
                signalled.provenance.label(),
                signalled.first_step,
                signalled.last_step,
            },
        );
    }
}
