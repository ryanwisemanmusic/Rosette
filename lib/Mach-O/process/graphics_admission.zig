// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const GUEST_FILE_BASE = __ProcessInternals._GUEST_FILE_BASE;
const GUEST_FILE_MAX = __ProcessInternals._GUEST_FILE_MAX;
const GuestFile = __ProcessInternals._GuestFile;
const GuestFileKind = __ProcessInternals._GuestFileKind;
const ImportHandlerResult = __ProcessInternals._ImportHandlerResult;
const application_framework = __ProcessInternals._application_framework;
const bootstrap_poll_join_steps = __ProcessInternals._bootstrap_poll_join_steps;
const builtin = __ProcessInternals._builtin;
const contract = __ProcessInternals._contract;
const execution_tracepoints = __ProcessInternals._execution_tracepoints;
const exit_diagnostics = __ProcessInternals._exit_diagnostics;
const gpu = __ProcessInternals._gpu;
const guest_log = __ProcessInternals._guest_log;
const host_contract_coverage = __ProcessInternals._host_contract_coverage;
const import_handler = __ProcessInternals._import_handler;
const import_resolution = __ProcessInternals._import_resolution;
const interrupt_callback_transaction = __ProcessInternals._interrupt_callback_transaction;
const lazy_import_stub = __ProcessInternals._lazy_import_stub;
const log = __ProcessInternals._log;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const macho_metadata = __ProcessInternals._macho_metadata;
const main = __ProcessInternals._main;
const mandatory_order = __ProcessInternals._mandatory_order;
const preflight_lib = __ProcessInternals._preflight_lib;
const primitive = __ProcessInternals._primitive;
const primitiveCapturePrint = __ProcessInternals._primitiveCapturePrint;
const signal_handling = __ProcessInternals._signal_handling;
const sparse_virtual_memory = __ProcessInternals._sparse_virtual_memory;
const startup_observer = __ProcessInternals._startup_observer;
const std = __ProcessInternals._std;
const swap_health = __ProcessInternals._swap_health;
const timeout_fidelity = __ProcessInternals._timeout_fidelity;
const types = __ProcessInternals._types;
const wait_audit = __ProcessInternals._wait_audit;
const xenia_gpu_causal_trace = __ProcessInternals._xenia_gpu_causal_trace;
const xenia_memory_views = __ProcessInternals._xenia_memory_views;
const addrToOffset = __ProcessInternals._addrToOffset;
const captureMemoryMutation = __ProcessInternals._captureMemoryMutation;
const commitMemoryMutation = __ProcessInternals._commitMemoryMutation;
const guestCString = __ProcessInternals._guestCString;
const guestMemory = __ProcessInternals._guestMemory;
const guestMemoryConst = __ProcessInternals._guestMemoryConst;
const pop = __ProcessInternals._pop;
const push = __ProcessInternals._push;
const read64 = __ProcessInternals._read64;
const writeGuestBytes = __ProcessInternals._writeGuestBytes;
const applyApplicationController = MachOState.applyApplicationController;
const decodeWithLiveOperands = MachOState.decodeWithLiveOperands;
const execute = MachOState.execute;
const guestOutputEvidence = MachOState.guestOutputEvidence;
const guestOutputFramesPresented = MachOState.guestOutputFramesPresented;
const handleImportImpl = MachOState.handleImportImpl;
const logAnomalyLedger = MachOState.logAnomalyLedger;
const logApplicationController = MachOState.logApplicationController;
const logApplicationFramework = MachOState.logApplicationFramework;
const logAuditContracts = MachOState.logAuditContracts;
const logBringupFailures = MachOState.logBringupFailures;
const logClaimReconciliation = MachOState.logClaimReconciliation;
const logCocoaGraphicsControl = MachOState.logCocoaGraphicsControl;
const logComponentReadiness = MachOState.logComponentReadiness;
const logDeadlockPredictor = MachOState.logDeadlockPredictor;
const logDeferredWork = MachOState.logDeferredWork;
const logDrawDispatch = MachOState.logDrawDispatch;
const logGraphicsContract = MachOState.logGraphicsContract;
const logGraphicsHealthContract = MachOState.logGraphicsHealthContract;
const logGuestExceptions = MachOState.logGuestExceptions;
const logGuestKernelStatus = MachOState.logGuestKernelStatus;
const logGuestLogChannels = MachOState.logGuestLogChannels;
const logGuestWaitLiveness = MachOState.logGuestWaitLiveness;
const logHostCoverage = MachOState.logHostCoverage;
const logImportBinding = MachOState.logImportBinding;
const logInterruptCallbackTransaction = MachOState.logInterruptCallbackTransaction;
const logKernelSurface = MachOState.logKernelSurface;
const logKernelVariables = MachOState.logKernelVariables;
const logMonotoneWitnesses = MachOState.logMonotoneWitnesses;
const logNearNullDispatchStatus = MachOState.logNearNullDispatchStatus;
const logNotifierLiveness = MachOState.logNotifierLiveness;
const logPacketCensus = MachOState.logPacketCensus;
const logPreinitialization = MachOState.logPreinitialization;
const logPresentationProvenance = MachOState.logPresentationProvenance;
const logProvisioningCustody = MachOState.logProvisioningCustody;
const logPumpLiveness = MachOState.logPumpLiveness;
const logRegisterApertureTraffic = MachOState.logRegisterApertureTraffic;
const logRegisterJournal = MachOState.logRegisterJournal;
const logRingContents = MachOState.logRingContents;
const logRunHorizon = MachOState.logRunHorizon;
const logSignalExpectation = MachOState.logSignalExpectation;
const logStallRelease = MachOState.logStallRelease;
const logSwapSubstitution = MachOState.logSwapSubstitution;
const logTranslationEconomics = MachOState.logTranslationEconomics;
const logUnknownInventory = MachOState.logUnknownInventory;
const logVdSwapContract = MachOState.logVdSwapContract;
const logVdSwapTrace = MachOState.logVdSwapTrace;
const logWaitAudit = MachOState.logWaitAudit;
const logWaitGraph = MachOState.logWaitGraph;
const logWindowAdmission = MachOState.logWindowAdmission;
const recordUnresolvedImport = MachOState.recordUnresolvedImport;
const refreshApplicationController = MachOState.refreshApplicationController;
const refreshCocoaGraphicsControl = MachOState.refreshCocoaGraphicsControl;
const refreshGraphicsContract = MachOState.refreshGraphicsContract;
const refreshGraphicsHealthContract = MachOState.refreshGraphicsHealthContract;
const refreshKernelVariables = MachOState.refreshKernelVariables;
const refreshRunIntegrity = MachOState.refreshRunIntegrity;
const refreshWindowSwapAdmission = MachOState.refreshWindowSwapAdmission;
const run = MachOState.run;
const serviceApplicationFrameworkRequests = MachOState.serviceApplicationFrameworkRequests;
const step = MachOState.step;
const syncGraphicsBoundaryGate = MachOState.syncGraphicsBoundaryGate;
const terminateForUnresolvedImport = MachOState.terminateForUnresolvedImport;

pub fn syncMandatoryOrder(self: anytype) void {
    const order = mandatory_order;
    const bringup = gpu.bringup_gate;
    const Pairing = struct {
        event: order.Event,
        boundary: bringup.Boundary,
        /// High-frequency boundaries record only their first occurrence in
        /// the lead-up window; every later one would push the events that
        /// matter out of it.
        frequent: bool = false,
    };
    const pairings = [_]Pairing{
        .{ .event = .engines_initialized, .boundary = .initialize_engines },
        .{ .event = .ring_initialized, .boundary = .initialize_ring_buffer },
        .{ .event = .read_pointer_writeback_enabled, .boundary = .enable_rptr_write_back },
        .{ .event = .command_processor_running, .boundary = .command_processor_worker_running, .frequent = true },
        .{ .event = .write_pointer_published, .boundary = .write_pointer_updated, .frequent = true },
        .{ .event = .ring_drained, .boundary = .execute_primary_buffer, .frequent = true },
        .{ .event = .register_programmed, .boundary = .write_register, .frequent = true },
        .{ .event = .render_target_programmed, .boundary = .render_target_update, .frequent = true },
        .{ .event = .draw_issued, .boundary = .issue_draw, .frequent = true },
        .{ .event = .swap_requested, .boundary = .guest_swap_requested },
        .{ .event = .swap_consumed, .boundary = .xe_swap_decoded },
        .{ .event = .guest_output_refreshed, .boundary = .refresh_guest_output },
        .{ .event = .interrupt_dispatched, .boundary = .dispatch_interrupt_callback, .frequent = true },
    };
    for (pairings) |pairing| {
        const record = self.gpu_bringup_gate.recordFor(pairing.boundary);
        if (!record.crossed()) continue;
        if (self.mandatory_order.count(pairing.event) >= record.hits) continue;
        if (pairing.frequent) {
            self.mandatory_order.observeOnce(
                pairing.event,
                record.first_step,
                record.first_thread,
                record.hits,
            );
        } else {
            self.mandatory_order.observe(
                pairing.event,
                record.first_step,
                record.first_thread,
                record.hits,
            );
        }
    }

    // The title callback is a separate execution domain from Rosette's
    // optional host callback. The generic SetInterrupt/EmulateCP trace
    // points are retained as context above, but they cannot satisfy this
    // ordering ledger because both domains travel through those symbols.
    const title_callback = &self.interrupt_callback_transaction;
    if (title_callback.registrations != 0 and
        !self.mandatory_order.seen(.interrupt_callback_registered))
    {
        self.mandatory_order.observe(
            .interrupt_callback_registered,
            if (title_callback.first_registration_step != 0)
                title_callback.first_registration_step
            else
                self.executed_steps,
            0,
            title_callback.callback_address,
        );
    } else if (title_callback.registrations == 0 and
        !self.mandatory_order.seen(.interrupt_callback_registered))
    {
        // Keep compatibility with an older Xenia binary that has not yet
        // emitted the domain-labelled transaction breadcrumbs. This is a
        // registration-only fallback; there is deliberately no analogous
        // fallback for guest entry, because the old generic entry point is
        // exactly what caused the false positive in the captured run.
        const registration = self.gpu_bringup_gate.recordFor(.set_interrupt_callback);
        if (registration.crossed() and
            self.gpu_interrupt_slot_is_guest and
            self.gpu_interrupt_slot_address != 0)
        {
            self.mandatory_order.observe(
                .interrupt_callback_registered,
                registration.first_step,
                registration.first_thread,
                self.gpu_interrupt_slot_address,
            );
        }
    }
    if (title_callback.dispatch_attempts != 0 and
        !self.mandatory_order.seen(.interrupt_entered_guest))
    {
        self.mandatory_order.observe(
            .interrupt_entered_guest,
            if (title_callback.first_dispatch_step != 0)
                title_callback.first_dispatch_step
            else
                self.executed_steps,
            0,
            title_callback.callback_address,
        );
    }
    // Host callback entry is retained in the same bounded lead-up window,
    // but it has no title-owned prerequisite and therefore cannot create a
    // guest callback ordering finding.
    const host_callback = &self.host_interrupt_callback_transaction;
    if (host_callback.dispatch_attempts != 0 and
        !self.mandatory_order.seen(.interrupt_entered_host))
    {
        self.mandatory_order.observe(
            .interrupt_entered_host,
            if (host_callback.first_dispatch_step != 0)
                host_callback.first_dispatch_step
            else
                self.executed_steps,
            0,
            host_callback.callback_address,
        );
    }

    // A raw IssueDraw boundary is useful context, but Xenia enters it for
    // no-effect draws as well. The Xenos runtime increments this separate
    // counter only after it has a live, writable target-backed output
    // witness, which is the event the mandatory target-order rule judges.
    if (self.gpu_xenos_runtime.renderable_draw_observations != 0 and
        !self.mandatory_order.seen(.renderable_draw_issued))
    {
        self.mandatory_order.observe(
            .renderable_draw_issued,
            if (self.gpu_renderable_draw_first_step != 0)
                self.gpu_renderable_draw_first_step
            else
                self.executed_steps,
            self.gpu_renderable_draw_first_thread,
            self.gpu_xenos_runtime.renderable_draw_observations,
        );
    }

    // PaintFromUIThread also paints Rosette's diagnostic surface while the
    // guest has produced no output. Preserve that fact, but do not call it
    // a guest surface paint or activate the expected guest-output rule.
    // A target-backed draw is only an opportunity; the refresh boundary is
    // the point at which pixels actually became the presenter source. If
    // any paint in the aggregate record predates that boundary, the
    // aggregate is ambiguous and remains diagnostic. Requiring the last
    // refresh to precede the first paint is intentionally conservative:
    // a first paint after a refresh is proof, but a later paint cannot
    // prove what an earlier paint displayed.
    const host_paint = self.gpu_bringup_gate.recordFor(.host_paint);
    if (host_paint.crossed()) {
        const guest_output = self.guestOutputEvidence();
        const opportunity = host_contract_coverage.guestOutputOpportunity(guest_output);
        const guest_refresh = self.gpu_bringup_gate.recordFor(.refresh_guest_output);
        const authentic = opportunity and
            guest_refresh.crossed() and
            guest_refresh.last_step <= host_paint.first_step;
        if (authentic and !self.mandatory_order.seen(.host_surface_painted)) {
            self.mandatory_order.observe(
                .host_surface_painted,
                @max(guest_refresh.first_step, host_paint.first_step),
                host_paint.first_thread,
                host_paint.hits,
            );
        } else if (!authentic and !self.mandatory_order.seen(.diagnostic_surface_painted)) {
            self.mandatory_order.observe(
                .diagnostic_surface_painted,
                host_paint.first_step,
                host_paint.first_thread,
                host_paint.hits,
            );
        }
    }
    if (self.xenia_memory_views.ready()) {
        self.mandatory_order.observeOnce(
            .guest_address_space_reserved,
            self.executed_steps,
            0,
            self.xenia_memory_views.mapping_base,
        );
    }
    if (self.gpu_completion_routes.status(.read_pointer_write_back).value_changed) {
        self.mandatory_order.observeOnce(
            .read_pointer_writeback_delivered,
            self.executed_steps,
            0,
            self.gpu_read_pointer_writeback_address,
        );
    }
}

pub fn logMandatoryOrder(self: anytype) void {
    const order = mandatory_order;
    self.syncMandatoryOrder();
    const totals = self.mandatory_order.summary();
    const draw_entry = self.gpu_bringup_gate.recordFor(.issue_draw);
    const target = self.gpu_bringup_gate.recordFor(.render_target_update);
    const guest_refresh = self.gpu_bringup_gate.recordFor(.refresh_guest_output);
    const host_paint = self.gpu_bringup_gate.recordFor(.host_paint);
    const title_callback = &self.interrupt_callback_transaction;
    const host_callback = &self.host_interrupt_callback_transaction;
    machoCapturePrint(
        "macho-processor: MANDATORY ORDER: active={d}/{d} held={d} raced={d} violated={d} mandatory_violations={d} events={d} step={d}; {s}\n",
        .{
            totals.active,
            order.rule_count,
            totals.held,
            totals.raced,
            totals.violated,
            totals.mandatory_violations,
            self.mandatory_order.total,
            self.executed_steps,
            totals.describe(),
        },
    );
    machoCapturePrint(
        "macho-processor: MANDATORY ORDER EVIDENCE: raw_draws={d} raw_draw(first/last/thread)={d}/{d}/0x{x} renderable_draws={d} renderable_first(step/thread)={d}/0x{x} target_programmed(hits/first/last/thread)={d}/{d}/{d}/0x{x} guest_refresh(hits/first/last)={d}/{d}/{d} title_callback(registration/dispatch/return)={d}/{d}/{d} first_steps={d}/{d}/{d} host_callback(dispatch/return)={d}/{d} host_paint_events={d} classified_surface(authentic/diagnostic)={d}/{d}; raw IssueDraw entry, host callback entry, and diagnostic paint never satisfy the target/title/guest-output prerequisites; ambiguous aggregate paint stays diagnostic\n",
        .{
            draw_entry.hits,
            draw_entry.first_step,
            draw_entry.last_step,
            draw_entry.first_thread,
            self.gpu_xenos_runtime.renderable_draw_observations,
            self.gpu_renderable_draw_first_step,
            self.gpu_renderable_draw_first_thread,
            target.hits,
            target.first_step,
            target.last_step,
            target.first_thread,
            guest_refresh.hits,
            guest_refresh.first_step,
            guest_refresh.last_step,
            title_callback.registrations,
            title_callback.dispatch_attempts,
            title_callback.callback_returns,
            title_callback.first_registration_step,
            title_callback.first_dispatch_step,
            title_callback.first_return_step,
            host_callback.dispatch_attempts,
            host_callback.callback_returns,
            host_paint.hits,
            self.mandatory_order.count(.host_surface_painted),
            self.mandatory_order.count(.diagnostic_surface_painted),
        },
    );
    var index: usize = 0;
    while (index < order.rule_count) : (index += 1) {
        const found = self.mandatory_order.reading(index);
        if (!found.standing.actionable()) continue;
        machoCapturePrint(
            "  order {s: <9} {s: <9} {s} before {s} — required(step/count)={d}/{d} dependant(step/count)={d}/{d} gap={d}\n",
            .{
                found.standing.label(),
                found.rule.strength.label(),
                found.rule.required.label(),
                found.rule.dependant.label(),
                found.required_step,
                found.required_count,
                found.dependant_step,
                found.dependant_count,
                found.gap_steps,
            },
        );
        machoCapturePrint("    order consequence: {s}\n", .{found.rule.consequence});
        // Retain always, report once. The lead-up is a region of detail at
        // the point the run went wrong; printed every checkpoint it would
        // stop being a region and become the log.
        if (!self.mandatory_order.takeUnreported(index)) continue;
        var buffer: [order.window_capacity]order.Occurrence = undefined;
        const lead_up = self.mandatory_order.leadUp(&buffer);
        machoCapturePrint(
            "    order lead-up: {d} retained event(s) before this finding, oldest first\n",
            .{lead_up.len},
        );
        for (lead_up) |occurrence| {
            machoCapturePrint(
                "      order event step={d: <12} thread=0x{x: <10} {s: <14} {s} detail={d}\n",
                .{
                    occurrence.step,
                    occurrence.thread,
                    occurrence.event.subsystem(),
                    occurrence.event.label(),
                    occurrence.detail,
                },
            );
        }
    }
}

pub fn logHostCapabilities(self: anytype) void {
    const capability = preflight_lib.host_capability;
    self.host_capabilities = capability.probe();
    const report = &self.host_capabilities;

    // The one capability preflight cannot answer, answered by the module
    // that owns the mechanism. Without this the host's coarser page sits
    // at the top of every run as a permanent, unactionable accusation —
    // and the emulator has in fact been getting its own page size the
    // whole time, from an overlay nobody was measuring.
    const overlay = sparse_virtual_memory.Manager.proveProtectionOverlay(self.allocator);
    // An obstacle in the environment is not a verdict on the overlay. A
    // reservation that could not be taken says nothing about whether the
    // mechanism works, and recording it as a failure would put a red row
    // next to something that was never exercised — so the row stays
    // unprobed, the host's coarser page stays uncompensated, and both
    // facts are true.
    if (overlay.succeeded or overlay.obstacle.accusesOverlay()) {
        report.note(
            .guest_page_protection_fidelity,
            overlay.succeeded,
            overlay.granularity,
            sparse_virtual_memory.PAGE_4K,
            @intFromEnum(overlay.obstacle),
        );
    }
    machoCapturePrint(
        "macho-processor: GUEST PAGE PROTECTION OVERLAY: proven={s} enforced={d}bytes host_page={d}bytes shared_host_page={s} mappings_used={d} obstacle={s}; the granularity comes from bookkeeping over one mapping. Giving each guest page a host page of its own would buy the same number and quadruple the address space, so the mapping count is part of the result and not an aside\n",
        .{
            if (overlay.succeeded) "YES" else "NO",
            overlay.granularity,
            std.heap.page_size_min,
            if (overlay.shared_host_page) "YES" else "NO",
            overlay.mappings_used,
            overlay.obstacle.label(),
        },
    );
    if (!overlay.succeeded) {
        // Two calls rather than one with a chosen string: the format is a
        // compile-time parameter, and picking it at run time does not
        // compile.
        if (overlay.obstacle.accusesOverlay()) {
            machoCapturePrint(
                "macho-processor: GUEST PAGE PROTECTION OVERLAY: the overlay did not enforce the console's page size, so the host's granularity now reaches the guest. Every protection change the emulator makes covers neighbouring guest pages, and a write watch or a guard page is only as precise as the host page\n",
                .{},
            );
        } else {
            machoCapturePrint(
                "macho-processor: GUEST PAGE PROTECTION OVERLAY: the proof could not be carried out here, so the overlay is unproven rather than broken. The host's page granularity is reported uncompensated below because nothing has shown otherwise, not because anything failed\n",
                .{},
            );
        }
    }

    // The generic host probe measures timed waiting, but it deliberately
    // does not signal a second thread.  Exercise the actual notification
    // edge separately so the pre-window ledger can distinguish
    // "deadlines work" from "a producer can wake a consumer".  Locale is
    // likewise a supplemental libc operation rather than a memory/timing
    // probe, and is kept as its own read-only fact.
    self.host_signal_handshake_proven = capability.probeSignalHandshake();
    self.host_locale_query_proven = capability.probeLocaleQuery();
    machoCapturePrint(
        "macho-processor: HOST SUPPLEMENTAL: signal_handshake={s} locale_query={s}; both are direct libc operations exercised before guest execution\n",
        .{
            if (self.host_signal_handshake_proven) "verified" else "FAILED",
            if (self.host_locale_query_proven) "verified" else "FAILED",
        },
    );

    const totals = report.summary();
    machoCapturePrint(
        "macho-processor: HOST CAPABILITY: probed={d} verified={d} degraded={d} compensated={d} failed={d} foundational_failures={d} fidelity_failures={d} probe_ms={d}; {s}\n",
        .{
            totals.probed,
            totals.verified,
            totals.degraded,
            totals.compensated,
            totals.failed,
            totals.foundational_failures,
            totals.fidelity_failures,
            report.elapsed_ns / std.time.ns_per_ms,
            totals.describe(),
        },
    );
    for (capability.allCapabilities()) |which| {
        const found = report.finding(which);
        machoCapturePrint(
            "  host-capability {s: <10} {s: <14} {s: <34} measured={d}{s} requested={d}{s} owner={s}\n",
            .{
                found.outcome.label(),
                which.severity().label(),
                which.label(),
                found.measured_value,
                which.unit(),
                found.requested_value,
                which.unit(),
                which.dependant(),
            },
        );
        if (found.outcome == .verified or found.outcome == .unprobed) continue;
        // A degraded magnitude whose compensator is verified is a fact
        // about the machine. Printing it in the same shape as a finding is
        // how a permanent platform property becomes a standing accusation
        // against the run, so the two say different things.
        if (report.compensationHolds(which)) {
            const paired = which.compensatedBy().?;
            machoCapturePrint(
                "    host-capability {s} (compensated): the shortfall is made up by {s}, measured at {d}{s}. This row is a property of this machine and not a finding against the run\n",
                .{
                    found.outcome.label(),
                    paired.label(),
                    report.finding(paired).measured_value,
                    paired.unit(),
                },
            );
            continue;
        }
        machoCapturePrint(
            "    host-capability {s}: {s}\n",
            .{ found.outcome.label(), which.failureLooksLike() },
        );
        machoCapturePrint(
            "    host-capability {s} owner={s}\n",
            .{ found.outcome.label(), which.shortfallOwner() },
        );
    }
    // The timed-wait overshoot is the only number that can tell a slow
    // machine from a slow emulated clock, so the timeout ledger is given it
    // rather than left to guess.
    self.timeout_fidelity.noteHostOvershoot(
        report.finding(.timed_wait_fidelity).measured_value,
    );
}

pub fn logTimeoutFidelity(self: anytype) void {
    const ledger = &self.timeout_fidelity;
    if (ledger.samples == 0) return;
    const found = ledger.verdict();
    machoCapturePrint(
        "macho-processor: TIMEOUT FIDELITY: verdict={s} attribution={s} samples={d} requested_ms={d} observed_ms={d} ratio={d}% host_overshoot_us={d} worst(object/requested_ms/observed_ms)=0x{x}/{d}/{d} step={d}; {s}\n",
        .{
            found.label(),
            ledger.attribution().label(),
            ledger.samples,
            ledger.requested_ms_total,
            ledger.observed_ms_total,
            ledger.ratioPercent(),
            ledger.host_overshoot_us,
            ledger.worst_object,
            ledger.worst_requested_ms,
            ledger.worst_observed_ms,
            self.executed_steps,
            found.describe(),
        },
    );
    machoCapturePrint(
        "  timeout fidelity source: observed durations are the emulator's own measure of how long each wait took, so this ratio is only as good as the clock it measured them with. The host overshoot beside it was measured directly by the capability probe and is the one number here that is not the emulator's\n",
        .{},
    );
}

pub fn logGraphicsBoundaryGate(self: anytype) void {
    const bringup = gpu.bringup_gate;
    const at_step = self.executed_steps;
    self.syncGraphicsBoundaryGate();
    const verdict = self.gpu_bringup_gate.verdict(at_step);
    machoCapturePrint(
        "macho-processor: GPU BOUNDARY GATE: finding={s} boundary={s} owner={s} phase={s} crossed={d}/{d} watched={d} actionable={d} observer_holes={d} inversions={d} step={d}; {s}\n",
        .{
            verdict.finding.label(),
            if (verdict.subject) |which| which.label() else "<none>",
            if (verdict.owner()) |who| who.label() else "-",
            if (verdict.phase()) |which| which.label() else "-",
            verdict.crossed,
            verdict.total,
            verdict.watched,
            verdict.actionable,
            verdict.holes,
            verdict.inversions,
            at_step,
            verdict.describe(),
        },
    );
    if (verdict.subject) |which| {
        const record = self.gpu_bringup_gate.recordFor(which);
        if (self.gpu_bringup_gate.state(which, at_step) == .stalled_after_crossing) {
            machoCapturePrint(
                "  GPU BOUNDARY GATE SUBJECT: {s} crossed {d}x, first_step={d} last_step={d} quiet_for={d} thread=0x{x}; {s}\n",
                .{
                    which.label(),
                    record.hits,
                    record.first_step,
                    record.last_step,
                    self.gpu_bringup_gate.quietFor(which, at_step),
                    record.first_thread,
                    which.silenceMeans(),
                },
            );
            // `silenceMeans()` for the write-pointer boundary ends with
            // "find which object the publishing thread parked on". The
            // producer tracker had already decided, in the same report,
            // that the thread this line names is not the submission loop:
            // the boundary fires on whichever thread performed the store.
            // Sending a reader after that thread's parks is sending them
            // after a thread that has none. Where the tracker says the
            // attribution is wrong, the directive is withdrawn here rather
            // than left standing beside the verdict that contradicts it.
            if (which == .write_pointer_updated) {
                const producer = self.gpu_producer_stall.verdict(at_step);
                if (producer == .misattributed or producer == .producer_unknown) {
                    machoCapturePrint(
                        "  GPU BOUNDARY GATE ATTRIBUTION: producer_verdict={s} named_thread=0x{x}; the thread named above performed the store and is not known to be the submission loop, so do not go looking for its parks. {s}\n",
                        .{
                            producer.label(),
                            record.first_thread,
                            producer.describe(),
                        },
                    );
                }
            }
        } else {
            machoCapturePrint(
                "  GPU BOUNDARY GATE SUBJECT: {s} watchers={d} requirement={s}; {s}\n",
                .{
                    which.label(),
                    record.watchers,
                    which.requirement().label(),
                    which.absenceMeans(),
                },
            );
        }
    }
    inline for (@typeInfo(bringup.Phase).@"enum".fields) |field| {
        const phase: bringup.Phase = @enumFromInt(field.value);
        const progress = self.gpu_bringup_gate.phaseProgress(phase);
        machoCapturePrint(
            "  gpu-phase {s: <13} crossed={d}/{d} watched={d}{s}\n",
            .{
                phase.label(),
                progress.crossed,
                progress.total,
                progress.watched,
                if (progress.blind()) " BLIND: nothing in this phase is observed, so its zero is Rosette's" else "",
            },
        );
    }
    // The full table only when the crossed set moved. Thirty-four rows on
    // every checkpoint is a second log, and the rows that did not change
    // are the ones a reader has already read.
    const crossed_mask: u64 = self.gpu_bringup_gate.crossedMask();
    const table_changed = self.gpu_gate_detail_mask != crossed_mask;
    self.gpu_gate_detail_mask = crossed_mask;
    for (bringup.contractBoundaries()) |boundary| {
        const state = self.gpu_bringup_gate.state(boundary, at_step);
        if (!table_changed and !state.actionable()) continue;
        if (!table_changed and boundary.requirement() == .optional) continue;
        const record = self.gpu_bringup_gate.recordFor(boundary);
        // How much of the armed surface was actually reached.
        //
        // `hits=0` reads as "the title never did this" and can equally mean
        // "armed on addresses the call never passes through". A boundary
        // armed on six addresses and reached on none is an observer hole
        // wearing the costume of a silent guest, and that mistake put the
        // 2026-09-05 frontier on VdQueryVideoMode while the guest log said
        // it had been called. The pair is what separates them.
        const coverage = self.execution_tracepoints.boundaryAddressCoverage(
            @intFromEnum(boundary),
        );
        machoCapturePrint(
            "  gpu-boundary {s: <16} {s: <10} {s: <45} owner={s: <28} watchers={d} entries={d} addresses(armed/reached)={d}/{d} crossings={d} first={d} last={d}\n",
            .{
                boundary.phase().label(),
                state.label(),
                boundary.label(),
                boundary.owner().label(),
                record.watchers,
                record.hits,
                coverage.armed,
                coverage.reached,
                self.execution_tracepoints.boundaryCrossings(@intFromEnum(boundary)),
                record.first_step,
                record.last_step,
            },
        );
    }
    self.logDrawAttrition();
    self.logCompletionRoutes();
    self.logProducerStall();
    self.logGraphicsEvidence();
}

pub fn logDrawAttrition(self: anytype) void {
    const issued = self.gpu_bringup_gate.recordFor(.issue_draw);
    const bound = self.gpu_bringup_gate.recordFor(.render_target_update);
    if (!issued.crossed() and self.gpu_draws_entered == 0) return;
    const lost = issued.hits -| bound.hits;
    machoCapturePrint(
        "macho-processor: GPU DRAW ATTRITION: entered={d} reached_render_target={d} lost={d} emulator_ledger(draws/reached/early/defects)={d}/{d}/{d}/{d} named_exits={d} first_exit={s} first_exit_step={d} step={d}; {s}\n",
        .{
            issued.hits,
            bound.hits,
            lost,
            self.gpu_draws_entered,
            self.gpu_draws_reached_render_target,
            self.gpu_draw_early_exits,
            self.gpu_draw_defect_exits,
            self.gpu_draw_exits_named,
            if (self.gpu_draw_first_exit_length != 0)
                self.gpu_draw_first_exit[0..self.gpu_draw_first_exit_length]
            else
                "<none>",
            self.gpu_draw_first_exit_step,
            self.executed_steps,
            if (issued.hits == 0)
                "no draw has entered the command processor, so there is no attrition to explain"
            else if (lost == 0)
                "every draw that entered reached a render target"
            else if (self.gpu_draw_defect_exits != 0)
                "draws are being dropped and the emulator classifies at least one of the reasons as its own failure. That reason is the graphics frontier, and the draw counter climbing is what makes it look like rendering is happening"
            else if (self.gpu_draw_exits_named != 0)
                "draws are being dropped for reasons the emulator classifies as the title's — a draw with rasterization disabled and no memory export legitimately has no effect. A whole batch of those is a title programming state, not a title failing to render, and the next question is what it is waiting for before it submits one that does"
            else
                "draws entered and did not reach a render target, and the emulator has not said why. Its per-exit ledger is not in this log, so this gap is unattributed rather than explained",
        },
    );
    if (issued.hits == 0) return;
    // Whether the render-target component is being counted as something the
    // guest depends on, and why. Printed because withholding a dependency
    // is a decision, and a decision that changes which owner a readiness
    // report names has to be auditable rather than inferred from its
    // absence.
    const exits_are_title_owned =
        self.gpu_draw_exits_named != 0 and self.gpu_draw_defect_exits == 0;
    const reached = bound.crossed() or self.gpu_draws_reached_render_target != 0;
    machoCapturePrint(
        "  DRAW ATTRITION DEPENDENCY: render_target_binding counted_as_used={s} named_exits={d} defect_exits={d} reached={s}; {s}\n",
        .{
            if (reached or !exits_are_title_owned) "YES" else "NO",
            self.gpu_draw_exits_named,
            self.gpu_draw_defect_exits,
            if (reached) "YES" else "NO",
            if (reached)
                "a draw reached the render target cache, so the component is genuinely on the path"
            else if (exits_are_title_owned)
                "every exit the emulator has named is one it classifies as the title's own, and those draws leave before the render target cache is consulted. The component is not on this batch's path, so it is not reported as a dependency the guest is running on unproven — the frontier is what the title is waiting for before it submits a draw that renders"
            else
                "no exit reason has been named, so the gap is unattributed. An unattributed gap does not excuse the dependency: the component stays counted as used and unproven until the emulator says why the draws stopped short",
        },
    );
}

pub fn logCompletionRoutes(self: anytype) void {
    const completion = gpu.completion_route;
    const routes = &self.gpu_completion_routes;
    const at_step = self.executed_steps;
    const verdict = routes.verdict(at_step);
    machoCapturePrint(
        "macho-processor: GPU COMPLETION ROUTE: verdict={s} requested={d}/{d} established={d}/{d} live={d}/{d} deliveries={d} step={d}; {s}\n",
        .{
            verdict.label(),
            routes.requestedCount(),
            completion.route_count,
            routes.establishedCount(),
            routes.requestedCount(),
            routes.liveCount(),
            routes.requestedCount(),
            routes.totalDeliveries(),
            at_step,
            verdict.describe(),
        },
    );
    const all_routes = comptime blk: {
        var out: [completion.route_count]completion.Route = undefined;
        for (&out, 0..) |*slot, index| slot.* = @enumFromInt(index);
        break :blk out;
    };
    for (all_routes) |route| {
        const status = routes.status(route);
        if (!status.requested) {
            machoCapturePrint(
                "  gpu-route {s: <28} requested=NO established=NO live=NO; the title did not select this optional completion route, so it is not a missing capability\n",
                .{route.label()},
            );
            continue;
        }
        machoCapturePrint(
            "  gpu-route {s: <28} requested=YES established={s} live={s} address=0x{x:0>8} attempts={d} deliveries={d} value(first/last/changed)=0x{x}/0x{x}/{s} observation={s} polled={s} owner={s}\n",
            .{
                route.label(),
                if (status.established) "YES" else "NO",
                if (status.liveFor(route)) "YES" else "NO",
                status.address,
                status.attempts,
                status.deliveries,
                status.first_value,
                status.last_value,
                if (!status.value_seen) "UNSAMPLED" else if (status.value_changed) "YES" else "NO",
                route.valueObservation(),
                if (route.deliversByValueChange()) "YES" else "NO",
                route.deliveryOwner(),
            },
        );
        // `value(first/last/changed)=0x0/0x0/NO` reads identically for a
        // value that was sampled and never moved and one that was never
        // sampled at all, and those are opposite conclusions. Only the
        // first is a finding about the emulator; the second is a hole in
        // Rosette.
        if (route.deliversByValueChange() and !status.value_seen and route.hasGuestAddress()) {
            machoCapturePrint(
                "    gpu-route VALUE UNSAMPLED: this route reaches the title by a value it polls and Rosette has never read that value. Its `changed=NO` above describes the observer, not the route, and nothing below may be concluded from it\n",
                .{},
            );
        } else if (route.deliversByValueChange() and !status.value_seen) {
            machoCapturePrint(
                "    gpu-route VALUE OBSERVATION: this route has no guest-visible address in the contract; delivery is established from its named boundary and no guest counter value is being fabricated\n",
                .{},
            );
        }
        if (status.inert()) {
            machoCapturePrint("    gpu-route INERT: {s}\n", .{route.inertMeans()});
        }
        if (status.deliveredWithoutChange(route)) {
            machoCapturePrint(
                "    gpu-route DELIVERED-WITHOUT-CHANGE: this route reaches the title by a value it polls, the emulator has written it {d} time(s), and the value has been 0x{x} every time. A title polling this saw nothing happen. Find what computes the value, not what delivers it\n",
                .{ status.deliveries, status.last_value },
            );
        }
    }
    const registration = self.gpu_bringup_gate.recordFor(.set_interrupt_callback);
    if (registration.crossed() and
        self.gpu_interrupt_slot_writes == 0 and
        self.interrupt_callback_transaction.callback_address == 0)
    {
        machoCapturePrint(
            "macho-processor: GPU COMPLETION ROUTE ADDRESS UNKNOWN: the title entered VdSetGraphicsInterruptCallback at step {d} and Rosette never observed the address it passed, so this route reads established=NO for a registration that did happen. That zero is the observer's, not the title's — wire the argument capture before concluding anything about the callback\n",
            .{registration.first_step},
        );
    }
    // The interrupt callback slot holds one address, and two different
    // parties can put one there. The emulator's macOS fork installs a
    // Xenia-owned host callback when the title has not registered one, and
    // from that moment the two are indistinguishable in every counter: the
    // null check inside the interrupt dispatch stops firing, dispatches
    // begin "succeeding", and "the title registered a callback" becomes
    // unanswerable. Say which one is in there.
    const title_callback = self.interrupt_callback_transaction.callback_address;
    const host_callback = self.host_interrupt_callback_transaction.callback_address;
    const occupancy = self.gpu_completion_routes.status(.interrupt_callback);
    if (self.gpu_interrupt_slot_writes != 0) {
        machoCapturePrint(
            "macho-processor: GPU INTERRUPT SLOT: address=0x{x:0>8} user_data=0x{x:0>8} owner={s} writes={d} last_write_step={d}; the slot holds one address and this is the newest statement of it. Every earlier reading in this log is a snapshot of a slot that has since changed hands\n",
            .{
                self.gpu_interrupt_slot_address,
                self.gpu_interrupt_slot_user_data,
                if (self.gpu_interrupt_slot_is_guest) "guest:title" else "emulator:host-builtin",
                self.gpu_interrupt_slot_writes,
                self.gpu_interrupt_slot_step,
            },
        );
        machoCapturePrint(
            "macho-processor: GPU INTERRUPT SLOT HISTORY: transitions={d} guest_writes={d} host_writes={d} current(address/owner/step)=0x{x:0>8}/{s}/{d} previous(address/owner/step)=0x{x:0>8}/{s}/{d}; current occupancy is authoritative for dispatch, while previous occupancy explains stale checkpoint lines and cannot satisfy the title callback boundary\n",
            .{
                self.gpu_interrupt_slot_transitions,
                self.gpu_interrupt_slot_guest_writes,
                self.gpu_interrupt_slot_host_writes,
                self.gpu_interrupt_slot_address,
                if (self.gpu_interrupt_slot_is_guest) "guest:title" else "emulator:host-builtin",
                self.gpu_interrupt_slot_step,
                self.gpu_interrupt_slot_previous_address,
                if (self.gpu_interrupt_slot_previous_is_guest) "guest:title" else "emulator:host-builtin",
                self.gpu_interrupt_slot_previous_step,
            },
        );
    }
    if (host_callback != 0 and !self.gpu_interrupt_slot_is_guest) {
        machoCapturePrint(
            "macho-processor: GPU COMPLETION ROUTE OCCUPANCY: the graphics interrupt slot holds a Xenia-owned host callback 0x{x:0>8} (host registrations={d}, attempts={d}, returns={d}); the title's own registration is 0x{x:0>8} (registrations={d}). A host callback in this slot disables the null guard in the emulator's interrupt dispatch and makes 'the title registered a callback' unanswerable from any counter — read the boundary gate's {s} row instead\n",
            .{
                host_callback,
                self.host_interrupt_callback_transaction.registrations,
                self.host_interrupt_callback_transaction.dispatch_attempts,
                self.host_interrupt_callback_transaction.callback_returns,
                title_callback,
                self.interrupt_callback_transaction.registrations,
                gpu.bringup_gate.Boundary.set_interrupt_callback.label(),
            },
        );
        machoCapturePrint(
            "  gpu-route occupancy: foreign_deliveries={d} title_deliveries={d} title_boundary_crossed={s} title_boundary_step={d}; a dispatch into the occupant is a real event and it is not the title's completion, so it is counted apart from the deliveries that would make this route live\n",
            .{
                occupancy.foreign_deliveries,
                occupancy.deliveries,
                if (registration.crossed()) "YES" else "NO",
                registration.first_step,
            },
        );
    }
}

pub fn logProducerStall(self: anytype) void {
    const tracker = &self.gpu_producer_stall;
    const at_step = self.executed_steps;
    const verdict = tracker.verdict(at_step);
    machoCapturePrint(
        "macho-processor: GPU PRODUCER: verdict={s} thread=0x{x} publications={d} published_at={d} quiet_for={d} waits_after_publish={d} returns={d} distinct_objects={d} step={d}; {s}\n",
        .{
            verdict.label(),
            tracker.producer_thread,
            tracker.publications,
            tracker.published_at_step,
            tracker.quietFor(at_step),
            tracker.waits_after_publish,
            tracker.returns_after_publish,
            tracker.distinctObjects(),
            at_step,
            verdict.describe(),
        },
    );
    if (tracker.elsewhere_events != 0) {
        machoCapturePrint(
            "  gpu-producer ELSEWHERE: {d} guest observation(s) on {d} other thread(s) since publication",
            .{ tracker.elsewhere_events, tracker.busyElsewhere().len },
        );
        for (tracker.busyElsewhere()) |thread| {
            machoCapturePrint(" 0x{x}", .{thread});
        }
        machoCapturePrint(
            "; the guest is running. A silent attributed thread beside these is a statement about the attribution and not about the run\n",
            .{},
        );
    }
    if (tracker.outstanding) |sample| {
        machoCapturePrint(
            "  gpu-producer OUTSTANDING WAIT: object=0x{x} handle=0x{x} pc=0x{x} since_step={d}; this is the wait to break, and whatever should have signalled that object is the thing to find\n",
            .{ sample.object, sample.handle, sample.pc, sample.step },
        );
    }
    var sites: [gpu.producer_stall.capacity]gpu.producer_stall.Site = undefined;
    for (tracker.sites(&sites)) |site| {
        machoCapturePrint(
            "  gpu-producer site pc=0x{x} waits={d}\n",
            .{ site.pc, site.count },
        );
    }
}

pub fn logGraphicsEvidence(self: anytype) void {
    const evidence = gpu.evidence_grade;
    const ledger = &self.gpu_evidence;
    machoCapturePrint(
        "macho-processor: GRAPHICS EVIDENCE: claims={d} established={d} unsafe={d} live_conflicts={d} stale_negatives={d}; a subject below the established count is one a reader may build on. The rest are either a weak claim a stronger observer denies, or an absence only a weak observer noticed — and neither supports a conclusion\n",
        .{
            ledger.claims,
            ledger.establishedSubjects(),
            ledger.unsafeSubjects(),
            ledger.conflicts(),
            ledger.staleClaims(),
        },
    );
    const all_subjects = comptime blk: {
        var out: [evidence.subject_count]evidence.Subject = undefined;
        for (&out, 0..) |*slot, index| slot.* = @enumFromInt(index);
        break :blk out;
    };
    // Every subject, every round.
    //
    // This used to skip the unobserved ones and the clean established
    // ones, so a run with three hundred and ninety-two claims printed
    // twelve rows and a reader could not tell an unmet subject from one
    // the roster does not contain. Which subjects are satisfied, which are
    // refuted and which nothing has looked at are three different answers,
    // and the ones that print nothing are exactly the ones a reader cannot
    // reconstruct. The roster is a fixed, bounded list, so printing all of
    // it costs a line each and removes the guessing.
    for (all_subjects) |subject| {
        const finding = ledger.finding(subject);
        machoCapturePrint(
            "  evidence {s: <20} {s: <40} believable={s} authority={s}/{s} step={d} magnitude={d} stale_negatives={d}; {s}\n",
            .{
                finding.standing.label(),
                subject.label(),
                if (finding.standing.believable()) "YES" else "NO",
                finding.authority.tier.label(),
                if (finding.authority.observer.len != 0) finding.authority.observer else "<none>",
                finding.authority.step,
                finding.authority.magnitude,
                finding.stale_negatives,
                finding.standing.describe(),
            },
        );
        if (finding.standing == .contested) {
            machoCapturePrint(
                "    GRAPHICS EVIDENCE CONFLICT: {s} — {s} ({s}, step {d}) claims it and {s} ({s}, step {d}) looked later and did not see it. {s}\n",
                .{
                    subject.label(),
                    finding.authority.observer,
                    finding.authority.tier.label(),
                    finding.authority.step,
                    finding.challenger.observer,
                    finding.challenger.tier.label(),
                    finding.challenger.step,
                    finding.standing.describe(),
                },
            );
        }
    }
}

pub fn logSwapHealth(self: anytype) void {
    const publication = &self.gpu_ring_publication;
    const swap_seen = self.gpu_vd_swap_contract.authentic_consumptions != 0;
    const livelocked = if (comptime @hasField(MachOState, "guest_log_cycles"))
        self.guest_log_cycles.active()
    else
        false;
    const livelock_seen = if (comptime @hasField(MachOState, "guest_log_cycles"))
        self.guest_log_cycles.hasHistory()
    else
        false;
    const producer_verdict = self.gpu_producer_stall.verdict(self.executed_steps);
    const attribution: swap_health.Attribution = switch (producer_verdict) {
        .attribution_lost, .producer_unknown, .misattributed => .lost,
        else => .known,
    };
    const assessment = swap_health.assessWithAttribution(
        publication.writes,
        publication.advances,
        publication.published(),
        publication.stalledSteps(self.executed_steps),
        livelocked,
        swap_seen,
        attribution,
    );
    machoCapturePrint(
        "macho-processor: SWAP HEALTH: blocker={s} producer={s} attribution={s} producer_verdict={s} step={d} wptr(writes/advances/repeats)={d}/{d}/{d} published={s} last_advance_step={d} quiet_for={d} largest_span_dwords={d} consumed_batch(dwords/packets/draws/swaps)={d}/{d}/{d}/{d} consumed_steps={d}/{d} guest_livelocked={s} guest_livelock_seen={s} swap_seen={s}; {s}\n",
        .{
            assessment.blocker.label(),
            @tagName(assessment.producer),
            assessment.producer_attribution.label(),
            producer_verdict.label(),
            self.executed_steps,
            publication.writes,
            publication.advances,
            publication.repeats,
            if (assessment.published) "YES" else "NO",
            publication.last_advance_step,
            assessment.stalled_steps orelse 0,
            publication.largest_span_dwords,
            publication.consumed_batch_dwords,
            publication.consumed_batch_packets,
            publication.consumed_batch_draws,
            publication.consumed_batch_swaps,
            publication.first_consumed_step,
            publication.last_consumed_step,
            if (assessment.guest_livelocked) "YES" else "NO",
            if (livelock_seen) "YES" else "NO",
            if (assessment.swap_seen) "YES" else "NO",
            assessment.blocker.guidance(),
        },
    );
}

pub fn logXeniaGpuCausalTrace(self: anytype, force: bool) void {
    self.xenia_gpu_causal_trace.logSummary(self.executed_steps, force);
}

pub fn logGpuEarlyFrontier(self: anytype, force: bool) void {
    const fingerprint = self.gpu_early_frontier.fingerprint();
    if (!force and fingerprint == self.gpu_early_frontier_last_fingerprint) return;
    self.gpu_early_frontier_last_fingerprint = fingerprint;
    const next_label = if (self.gpu_early_frontier.firstActionable()) |next| next.label() else "none";
    const first_unmet = if (self.gpu_early_frontier.firstUnmet()) |unmet| unmet.label() else "none";
    machoCapturePrint(
        "macho-processor: GPU EARLY FRONTIER: step={d} fingerprint=0x{x} observed=0x{x:0>8} actionable=0x{x:0>8} next={s} first_unmet={s} quiet={d}\n",
        .{
            self.executed_steps,
            fingerprint,
            self.gpu_early_frontier.observed_mask,
            self.gpu_early_frontier.actionableMask(),
            next_label,
            first_unmet,
            self.gpu_early_frontier.quietSteps(self.executed_steps) orelse 0,
        },
    );
    inline for (@typeInfo(gpu.GpuEarlyBoundary).@"enum".fields) |field| {
        const boundary: gpu.GpuEarlyBoundary = @enumFromInt(field.value);
        const edge = self.gpu_early_frontier.edge(boundary);
        machoCapturePrint(
            "  gpu-edge boundary={s} owner={s} state={s} count={d} first_step={d} last_step={d} first_value=0x{x} last_value=0x{x} source_mask=0x{x:0>4}\n",
            .{
                boundary.label(),
                boundary.owner().label(),
                if (edge.seen) "YES" else "NO",
                edge.count,
                edge.first_step,
                edge.last_step,
                edge.first_value,
                edge.last_value,
                edge.source_mask,
            },
        );
    }
}

pub fn refreshXeniaGpuCausalTrace(self: anytype) void {
    const at = self.executed_steps;
    if (self.execution_tracepoints.roleEntered(.swap)) {
        self.xenia_gpu_causal_trace.observeStage(.guest_vdswap_entered, at);
    }
    if (self.guest_vdswap_packet_encoded) {
        self.xenia_gpu_causal_trace.observeStage(.swap_packet_encoded, at);
    }
    if (self.guest_vdswap_entry_completed) {
        self.xenia_gpu_causal_trace.observeStage(.guest_vdswap_completed, at);
    }
    if (self.gpu_bootstrap.seen(.pm4_packet_consumed)) {
        self.xenia_gpu_causal_trace.observeEvidence(.pm4_packet_consumed, at);
    }
    if (self.gpu_vd_swap_contract.observed(.authentic_xe_swap_consumed)) {
        self.xenia_gpu_causal_trace.observeEvidence(.authentic_swap_consumed, at);
    }
}

pub fn logGpuBootstrapProvenance(self: anytype, force: bool) void {
    const ledger = &self.gpu_bootstrap_provenance;
    const fingerprint = ledger.stableFingerprint();
    if (!force and fingerprint == self.gpu_bootstrap_provenance_last_fingerprint) return;
    self.gpu_bootstrap_provenance_last_fingerprint = fingerprint;
    const summary = ledger.summary();
    machoCapturePrint(
        "macho-processor: GPU BOOTSTRAP PROVENANCE: sources(guest/trace/corroborated/guest-only/guest-only-callsite-blind/trace-only/callsite-blind/configured)={d}/{d}/{d}/{d}/{d}/{d}/{d}/{d} fingerprint=0x{x} step={d}; guest breadcrumbs and IP tracepoints remain separate authorities; a callsite probe miss never retracts a concrete guest event\n",
        .{
            summary.guest_observed,
            summary.trace_observed,
            summary.corroborated,
            summary.guest_only,
            summary.guest_only_callsite_blind,
            summary.trace_only,
            summary.callsite_blind,
            summary.configured,
            fingerprint,
            self.executed_steps,
        },
    );
    var bootstrap_index: usize = 0;
    while (bootstrap_index < gpu.bootstrap.step_count) : (bootstrap_index += 1) {
        const bootstrap_step: gpu.Step = @enumFromInt(bootstrap_index);
        const item = ledger.record(bootstrap_step);
        // A callsite-only miss is an observation hole of its own. Keep its
        // row even when no guest breadcrumb or tracepoint exists, so the
        // summary's callsite-blind count always has concrete witnesses.
        if (item.finding() == .unobserved and
            !item.configured() and
            !item.callsiteObserved())
            continue;
        machoCapturePrint(
            "  bootstrap-provenance step={s} finding={s} guest(count/first/last)={d}/{d}/{d} trace(count/first/last)={d}/{d}/{d} callsite(probes/first/last/pc/lr/ctr/branch/near-bl/entry-bctrl/near-refs/entry-refs)={d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}/{d} configured(count/first/last/mapped)={d}/{d}/{d}/{d}; {s}\n",
            .{
                bootstrap_step.label(),
                item.finding().label(),
                item.guest_count,
                item.guest_first_step,
                item.guest_last_step,
                item.trace_count,
                item.trace_first_step,
                item.trace_last_step,
                item.callsite_probe_count,
                item.callsite_first_step,
                item.callsite_last_step,
                item.callsite_pc_hits,
                item.callsite_lr_hits,
                item.callsite_ctr_hits,
                item.callsite_branch_probe_hits,
                item.callsite_near_direct_bl_hits,
                item.callsite_entry_bctrl_hits,
                item.callsite_near_value_ref_hits,
                item.callsite_entry_value_ref_hits,
                item.configuration_count,
                item.configuration_first_step,
                item.configuration_last_step,
                item.configuration_mapped_count,
                item.guidance(),
            },
        );
    }
}

pub fn logGraphicsFrontier(self: anytype, force: bool) void {
    self.graphics_summary_emissions +|= 1;
    self.report_epoch +|= 1;
    self.refreshXeniaGpuCausalTrace();
    // Refresh the cross-layer ledgers before deciding whether this
    // checkpoint is interesting.  The controller is deliberately sampled
    // at the same boundary as the reports: this makes its quiet windows
    // and host-only directives correlate with the exact PM4/VdSwap state
    // printed below instead of with a neighboring heartbeat.
    self.refreshGraphicsContract();
    self.refreshGraphicsHealthContract();
    const controller_decision = self.refreshApplicationController();
    self.applyApplicationController(controller_decision);
    self.serviceApplicationFrameworkRequests();
    // Interrupt delivery is a host-owned action and may make a queued
    // completion visible immediately.  Re-join the health ledger so the
    // same report cannot say both "completion dispatched=0" and "drain
    // authorized" after the controller has acted.
    self.refreshGraphicsHealthContract();
    const cocoa_outcome = self.refreshCocoaGraphicsControl();
    if (cocoa_outcome.route == .cocoa_metal_guest_copy and cocoa_outcome.frame_delivery_pending) {
        if (self.dynamic_forwarder.attemptCocoaFrameFallback(self)) {
            _ = self.cocoa_graphics.observeIntent(.{
                .run = cocoa_outcome.frame_identity.run,
                .boundary = .{ .native_event = .guest_frame_presented },
                .producer = .rosette_runtime,
                .evidence = .completed_call,
                .source_identity = cocoa_outcome.frame_identity.source,
                .generation = cocoa_outcome.frame_identity.generation,
                .sequence = cocoa_outcome.frame_identity.serial,
            });
            // Reconcile the completed native command in the same checkpoint
            // so the log never advertises a route without its result.
            _ = self.refreshCocoaGraphicsControl();
        }
    }
    const cocoa_fingerprint = self.cocoa_graphics.fingerprint();
    const cocoa_changed = cocoa_fingerprint != self.cocoa_graphics_last_fingerprint;
    const early_frontier_fingerprint = self.gpu_early_frontier.fingerprint();
    const early_frontier_changed = early_frontier_fingerprint != self.gpu_early_frontier_last_fingerprint;
    self.logGpuEarlyFrontier(force);
    // Publish the same seam through the callable framework. These are
    // deliberately paired observations: entering VdSwap, consuming an
    // authentic XE_SWAP, reaching IssueSwap, and refreshing guest output
    // are separate facts. The equivalence records make a successful call
    // with an absent downstream effect visible as a mismatch.
    self.application_framework.observeController(
        @intFromEnum(controller_decision.phase),
        @intFromEnum(controller_decision.action),
        @intFromEnum(controller_decision.blocker),
        self.executed_steps,
        "controller decision sampled at graphics frontier",
    );
    const guest_vdswap_entered = @intFromBool(self.execution_tracepoints.roleEntered(.swap));
    const authentic_swap_consumed = @intFromBool(self.gpu_vd_swap_contract.authentic_consumptions != 0);
    const issue_swap_entered = @intFromBool(self.gpu_vd_swap_contract.observed(.issue_swap_entered));
    const guest_output_refreshed = @intFromBool(self.guestOutputFramesPresented() != 0);
    self.application_framework.observeValue(.xenia_kernel, .vd_swap, 1, guest_vdswap_entered, self.executed_steps, self.regs.rip, "guest-vdswap-entered", "guest execution boundary");
    self.application_framework.observeValue(.xenia_gpu, .vd_swap, 2, authentic_swap_consumed, self.executed_steps, self.regs.rip, "authentic-xe-swap-consumed", "command processor boundary");
    self.application_framework.observeValue(.xenia_presenter, .presenter, 3, issue_swap_entered, self.executed_steps, self.regs.rip, "issue-swap-entered", "native presenter boundary");
    self.application_framework.observeValue(.xenia_presenter, .presenter, 4, guest_output_refreshed, self.executed_steps, self.regs.rip, "guest-output-refreshed", "guest-produced frame evidence");
    if (self.application_framework.isEnabled()) {
        _ = self.application_framework.compareValue(.xenia_gpu, .vd_swap, 2, guest_vdswap_entered, authentic_swap_consumed, 1, self.executed_steps, self.regs.rip, "vdswap-to-authentic-xe-swap");
        _ = self.application_framework.compareValue(.xenia_presenter, .presenter, 3, authentic_swap_consumed, issue_swap_entered, 1, self.executed_steps, self.regs.rip, "xe-swap-to-issue-swap");
        _ = self.application_framework.compareValue(.rosette, .presenter, 4, issue_swap_entered, guest_output_refreshed, 1, self.executed_steps, self.regs.rip, "issue-swap-to-guest-output");
    }
    const health_fingerprint = self.graphics_health.fingerprint();
    const controller_fingerprint = controller_decision.fingerprint();
    const framework_sequence = self.application_framework.currentSequence();
    const tracepoints = &self.execution_tracepoints;
    const frontier = self.gpu_bootstrap.frontier();
    const frontier_tag = if (frontier.step) |frontier_step|
        @intFromEnum(frontier_step)
    else
        std.math.maxInt(u8);
    var role_mask: u16 = 0;
    inline for (@typeInfo(execution_tracepoints.Role).@"enum".fields) |field| {
        const role: execution_tracepoints.Role = @enumFromInt(field.value);
        if (tracepoints.roleEntered(role)) {
            role_mask |= @as(u16, 1) << @intCast(field.value);
        }
    }
    const ring_published = self.gpu_ring_publication.published();
    const causal_changed =
        self.xenia_gpu_causal_trace.total_events != self.graphics_last_causal_events or
        self.xenia_gpu_causal_trace.observed_mask != self.graphics_last_causal_mask;
    const state_changed =
        frontier_tag != self.graphics_last_frontier_tag or
        frontier.reached != self.graphics_last_frontier_reached or
        role_mask != self.graphics_last_role_mask or
        ring_published != self.graphics_last_ring_published or
        self.anomalies.count != self.graphics_last_anomaly_count or
        causal_changed or
        health_fingerprint != self.graphics_health_last_fingerprint or
        controller_fingerprint != self.application_controller_last_fingerprint or
        framework_sequence != self.application_framework_last_sequence or
        cocoa_changed or
        early_frontier_changed;
    self.graphics_last_frontier_tag = frontier_tag;
    self.graphics_last_frontier_reached = frontier.reached;
    self.graphics_last_role_mask = role_mask;
    self.graphics_last_ring_published = ring_published;
    self.graphics_last_anomaly_count = self.anomalies.count;
    self.graphics_last_causal_events = self.xenia_gpu_causal_trace.total_events;
    self.graphics_last_causal_mask = self.xenia_gpu_causal_trace.observed_mask;
    self.graphics_health_last_fingerprint = health_fingerprint;
    self.application_controller_last_fingerprint = controller_fingerprint;
    self.application_framework_last_sequence = framework_sequence;
    if (force or state_changed) self.logApplicationFramework();
    self.logCocoaGraphicsControl(force or cocoa_changed);
    // The swap gate is evaluated here rather than at each boundary: whether
    // a boundary may hand presentation to the window depends on the front
    // buffer, the ring epoch and the presenter lease as they stand now, and
    // those are exactly the facts the checkpoint has just refreshed.
    self.refreshWindowSwapAdmission();
    // The handoff report is the Rosette side of the ownership picture and
    // is three lines when clean, so it prints on the full-report cadence
    // rather than only when it changes. A reader looking for "are the two
    // sides interoperating" should not have to find the last checkpoint
    // where something moved.
    self.logWindowAdmission(force or state_changed);
    // Judged after every ledger this checkpoint refreshed, and before the
    // reports below, so a run that is not meeting its standards stops here
    // rather than after producing another checkpoint's worth of log.
    self.refreshRunIntegrity();

    // The ring is read whether or not the frontier moved.
    //
    // Everything else in this report is derived from state that only
    // changes when the frontier does, so gating it on a transition costs
    // nothing. The ring is the opposite: it is memory the guest writes at
    // its own pace, and a run whose frontier has stopped moving is exactly
    // the run where its contents are the only thing left that can change.
    // The observed stall took its last transition at step 3.5B and then ran
    // for another 2.8B steps; gated on transitions, nothing would have
    // looked at the ring across the whole second half of the run and the
    // front buffer a swap names would never have been found.
    //
    // Rate-limited rather than free-running: the scan walks the ring, and a
    // diagnostic that runs on every checkpoint becomes the dominant cost
    // and the dominant source of log traffic at the same time.
    if (force or state_changed or self.graphics_summary_emissions % 16 == 0) {
        if (self.gpu_ring_last_inspection_step != self.executed_steps)
            self.logRingContents();
        // The preinitialization ledger reads kernel-variable state. Refresh
        // that state before sampling the ledger so this report cannot lag
        // behind the variable report emitted later in the full summary.
        // Provisioning remains owner-gated: title-owned pointers are never
        // fabricated, and structured HSIO state is not synthesized here.
        self.refreshKernelVariables();
        self.logProvisioningCustody();
        self.logPreinitialization();
        self.logGuestWaitLiveness();
        self.logInterruptCallbackTransaction();
        self.logImportBinding();
        self.logHostCoverage();
        self.logBringupFailures();
        self.logStallRelease();
        // Drive a refresh because the emulator will not: it refreshes on a
        // swap, and this title has never swapped. The frame source is
        // unchanged, so this cannot invent a picture — it only ensures the
        // scan runs, which is the difference between "we tried and the
        // guest had nothing" and "nobody ever looked".
        // The controller owns the discovered-guest-output refresh when it
        // has proven that a guest source exists.  Keep the historical
        // diagnostic cadence for all other states, including a completely
        // empty source, so "no source" remains an observed result rather
        // than an unattempted path.
        if (controller_decision.action != .refresh_discovered_output)
            _ = self.dynamic_forwarder.attemptScheduledRefresh(self);
        self.dynamic_forwarder.logScheduledRefresh();
        self.logWaitAudit();
        self.logDeadlockPredictor();
        self.logDeferredWork();
        self.logGuestExceptions();
        self.logSwapSubstitution();
        self.refreshGraphicsHealthContract();
        self.logGraphicsHealthContract();
        self.logApplicationController(controller_decision);
    }

    // Heartbeats already say that execution is alive. The complete report
    // includes every tracepoint and the full thread census, so emit it only
    // on an actual state transition or at shutdown. A compact unchanged
    // checkpoint every 64 calls preserves liveness without making the
    // observer itself the dominant source of log traffic.
    if (!force and !state_changed) {
        if (self.graphics_summary_emissions % 64 != 0) return;
        machoCapturePrint(
            "macho-processor: GRAPHICS FRONTIER unchanged: run=0x{x} step={d} checkpoint={d} bootstrap={d}/{d} frontier={s} guest_vdswap_call_seen={s} guest_vdswap_entry_completed={s} guest_swap_command_buffer_write_seen={s} guest_swap_publication_proven={s} guest_pm4_xe_swap_seen={s} cp_xe_swap_decode_seen={s} host_issue_swap_seen={s} diagnostic_injection_seen={s} presenter_refresh_seen={s} ring_published={s}\n",
            .{
                self.event_stream.run_id,
                self.executed_steps,
                self.graphics_summary_emissions,
                frontier.reached,
                gpu.bootstrap.required_step_count,
                if (frontier.step) |pending| pending.label() else "<complete>",
                if (tracepoints.roleEntered(.swap)) "YES" else "NO",
                if (self.guest_vdswap_entry_completed) "YES" else "NO",
                if (self.guest_vdswap_packet_encoded) "YES" else "NO",
                if (self.gpu_vd_swap_contract.observed(.ring_write_pointer_published)) "YES" else "NO",
                if (self.gpu_vd_swap_contract.observed(.authentic_xe_swap_consumed)) "YES" else "NO",
                if (tracepoints.roleEntered(.xe_swap_decode)) "YES" else "NO",
                if (tracepoints.roleEntered(.command_swap)) "YES" else "NO",
                if (tracepoints.roleEntered(.diagnostic_swap)) "YES" else "NO",
                if (tracepoints.roleEntered(.presenter)) "YES" else "NO",
                if (ring_published) "YES" else "NO",
            },
        );
        self.logGraphicsBoundaryGate();
        self.logGpuBootstrapProvenance(false);
        self.logMandatoryOrder();
        self.logComponentReadiness();
        self.logPresentationProvenance(false);
        self.logNearNullDispatchStatus(false);
        self.logPacketCensus();
        self.logSignalExpectation();
        self.logSwapHealth();
        self.logXeniaGpuCausalTrace(false);
        self.logVdSwapContract();
        self.logVdSwapTrace();
        self.refreshGraphicsHealthContract();
        self.logGraphicsHealthContract();
        self.logApplicationController(controller_decision);
        return;
    }
    machoCapturePrint(
        "macho-processor: GRAPHICS FRONTIER #{d}: run=0x{x} step={d} events={d} guest_vdswap_call={s}\n",
        .{
            self.graphics_summary_emissions,
            self.event_stream.run_id,
            self.executed_steps,
            self.event_stream.sequence,
            tracepoints.verdict(.swap),
        },
    );
    // The boundary gate leads. Every report under it is detail about a
    // pipeline whose first unmet boundary this names, and a reader who
    // starts anywhere else spends the hour downstream of it — which is
    // what the last three passes of this investigation did.
    self.logGraphicsBoundaryGate();
    self.logGpuBootstrapProvenance(force);
    // Then what got ahead of what. A boundary that was crossed is only
    // half the fact; whether it was crossed before the thing it depended on
    // is the other half, and it is the half that explains twenty-four draws
    // reaching a command processor that had no render target.
    self.logMandatoryOrder();
    // Readiness answers a question none of the others do: what is the run
    // trusting that nothing has checked. It sits directly under the gate
    // because an unproven component makes every reading below it
    // unattributable rather than merely negative.
    self.logComponentReadiness();
    self.logPumpLiveness();
    self.logPresentationProvenance(force);
    self.logNearNullDispatchStatus(force);
    self.logPacketCensus();
    self.logSignalExpectation();
    self.logTimeoutFidelity();
    self.logRunHorizon();
    self.logWaitGraph();
    self.logDrawDispatch();
    self.logTranslationEconomics();
    self.logGuestLogChannels();
    self.logClaimReconciliation();
    self.logMonotoneWitnesses();
    self.logGuestKernelStatus();
    self.logUnknownInventory();
    self.logAuditContracts();
    self.logInterruptCallbackTransaction();
    self.logRegisterJournal();
    self.logSwapHealth();
    self.logXeniaGpuCausalTrace(force);
    self.logGraphicsContract();
    self.refreshGraphicsHealthContract();
    self.logGraphicsHealthContract();
    self.logApplicationController(controller_decision);
    self.logVdSwapContract();
    self.logVdSwapTrace();
    self.logKernelSurface();
    self.logKernelVariables();
    // Twenty-two armed addresses. What a reader needs from the table is
    // which of them the instruction pointer has reached; that set changes a
    // handful of times in a whole run, and printing the table on every
    // checkpoint costs more lines than every graphics contract combined.
    var entered_mask: [4]u64 = [_]u64{0} ** 4;
    for (tracepoints.entries[0..tracepoints.count], 0..) |entry, index| {
        if (entry.hits == 0 or index >= 256) continue;
        entered_mask[index / 64] |= @as(u64, 1) << @intCast(index % 64);
    }
    const tracepoints_established = std.mem.eql(u64, self.tracepoint_detail_mask[0..], entered_mask[0..]);
    self.tracepoint_detail_mask = entered_mask;
    var settled_tracepoints: usize = 0;
    for (tracepoints.entries[0..tracepoints.count]) |entry| {
        // A tracepoint that has been entered is a fact worth repeating
        // while the set is still moving, and settled once it is not.
        if (tracepoints_established) {
            settled_tracepoints += 1;
            continue;
        }
        machoCapturePrint(
            "  tracepoint role={s} hits={d} first_step={d} first_thread=0x{x} first_caller=0x{x} last_step={d} address=0x{x} symbol={s}\n",
            .{ @tagName(entry.role), entry.hits, entry.first_step, entry.first_thread, entry.first_caller, entry.last_step, entry.address, entry.name },
        );
    }
    if (settled_tracepoints != 0) machoCapturePrint(
        "  tracepoint collapsed: {d} armed address(es), entered=0x{x:0>16}{x:0>16}{x:0>16}{x:0>16}, unchanged since the previous checkpoint where the table printed in full. The per-role verdicts below are current on every checkpoint\n",
        .{ settled_tracepoints, entered_mask[3], entered_mask[2], entered_mask[1], entered_mask[0] },
    );
    inline for (@typeInfo(execution_tracepoints.Role).@"enum".fields) |field| {
        const role: execution_tracepoints.Role = @enumFromInt(field.value);
        if (tracepoints.roleArmed(role) or role == .swap) {
            machoCapturePrint(
                "  role={s}: {s}\n",
                .{ @tagName(role), tracepoints.verdict(role) },
            );
        }
    }
    self.logRegisterApertureTraffic();
    const publication = &self.gpu_ring_publication;
    machoCapturePrint(
        "  ring writes={d} advances={d} repeats={d} span={s} published={s}; {s}\n",
        .{
            publication.writes,
            publication.advances,
            publication.repeats,
            @tagName(publication.span()),
            if (publication.published()) "YES" else "NO",
            publication.verdict(),
        },
    );
    machoCapturePrint(
        "  bootstrap reached={d}/{d} frontier={s} precondition_met={} blocked_by={s}\n",
        .{
            frontier.reached,
            gpu.bootstrap.required_step_count,
            if (frontier.step) |pending| pending.label() else "<complete>",
            frontier.precondition_met,
            if (frontier.blocked_by) |blocked| blocked.label() else "none",
        },
    );
    self.logBootstrapFrontierOccupation(frontier);
    self.dynamic_forwarder.logGraphicsProvenance();
    self.dynamic_forwarder.logGuestFrontBuffer();
    self.dynamic_forwarder.logVulkanTiers();
    // A blocked count is an aggregate; the frontier needs to know which
    // resource the producer is parked on and for how long.
    self.pthreads.logThreadCensus(self.executed_steps, self.active_guest_thread);
    self.logNotifierLiveness();
    self.logAnomalyLedger();
    if (self.event_stream.anySuppressed()) {
        machoCapturePrint(
            "  NOTE: some event kinds hit their budget and were suppressed; a flat count is a budget, not a cessation\n",
            .{},
        );
    }
}

pub fn logBootstrapFrontierOccupation(
    self: anytype,
    frontier: gpu.bootstrap.Frontier,
) void {
    if (frontier.step == null) return;
    var subject: ?wait_audit.Subject = null;
    for (self.wait_audit.subjects[0..self.wait_audit.count]) |candidate| {
        if (candidate.timeout_class != .bounded_poll) continue;
        if (candidate.signals != 0 or candidate.timeouts == 0) continue;
        if (subject == null or candidate.timeouts > subject.?.timeouts) {
            subject = candidate;
        }
    }
    const poll = subject orelse return;
    const last_advance = self.gpu_ring_publication.last_advance_step;
    machoCapturePrint(
        "  BOOTSTRAP FRONTIER OCCUPATION: object=0x{x} handle=0x{x} type={d} timeout_ms={d} expiries={d} signals=0 first_poll_step={d} last_poll_step={d} producer_last_advance={d} started_with_batch={s}; {s}\n",
        .{
            poll.object,
            poll.handle,
            poll.type_code,
            poll.timeout_ms,
            poll.timeouts,
            poll.first_step,
            poll.last_step,
            last_advance,
            if (last_advance != 0 and poll.first_step >= last_advance -| bootstrap_poll_join_steps)
                "YES"
            else
                "NO",
            if (last_advance != 0 and poll.first_step >= last_advance -| bootstrap_poll_join_steps)
                "the title began polling this event around the same submission the frontier is waiting for a successor to, and has received nothing since. This is what it is doing instead of reaching the frontier: find the code that sets this event and confirm it was reached, rather than reading the frontier as a graphics-stack gap"
            else
                "this poll predates the producer's last advance, so it is not obviously the title waiting for that batch. It is still an event nothing has signalled, and the frontier above is unexplained by it",
        },
    );
}

pub fn standardStreamPointer(self: anytype, symbol_name: []const u8) ?u64 {
    return guest_log.standardStreamPointer(self, symbol_name);
}

pub fn configureGuestLogMirror(self: anytype, args: []const []const u8) void {
    return guest_log.configureGuestLogMirror(self, args);
}

pub fn hostWriteFdAll(fd: i32, bytes: []const u8) bool {
    return guest_log.hostWriteFdAll(fd, bytes);
}

pub fn shouldSummarizeGuestLog(level: u8, message: []const u8) bool {
    return guest_log.shouldSummarizeGuestLog(level, message);
}

pub fn shouldSuppressRuntimeGuestLog(message: []const u8) bool {
    return guest_log.shouldSuppressRuntimeGuestLog(message);
}

pub fn emitRuntimeSummaryHeartbeat(self: anytype, snapshot: startup_observer.Snapshot) void {
    return guest_log.emitRuntimeSummaryHeartbeat(self, snapshot);
}

pub fn emitGuestLog(self: anytype, prefix_char_raw: u64, address: u64, length_raw: u64) bool {
    return guest_log.emitGuestLog(self, prefix_char_raw, address, length_raw);
}

pub fn logProfileHostPreflight(self: anytype, profile_id: []const u8) void {
    return guest_log.logProfileHostPreflight(self, profile_id);
}

pub fn observeProfileAccountFlow(self: anytype) void {
    return guest_log.observeProfileAccountFlow(self);
}

pub fn noteProfileAccountOpen(self: anytype, path: []const u8, guest_fd: u64) void {
    return guest_log.noteProfileAccountOpen(self, path, guest_fd);
}

pub fn noteProfileAccountRead(self: anytype, guest_fd: u64, requested: u64, result: i64, offset: u64) void {
    return guest_log.noteProfileAccountRead(self, guest_fd, requested, result, offset);
}

pub fn observeBackendGuestLog(self: anytype, message: []const u8) void {
    return guest_log.observeBackendGuestLog(self, message);
}

pub fn backendMemoryDiagnosticsActive(self: anytype) bool {
    return guest_log.backendMemoryDiagnosticsActive(self);
}

pub fn noteBackendMmapAttempt(self: anytype, route: []const u8, address: u64, length: u64, prot: u64, flags: u64, fixed: bool, anonymous: bool) void {
    return guest_log.noteBackendMmapAttempt(self, route, address, length, prot, flags, fixed, anonymous);
}

pub fn noteBackendMmapResult(self: anytype, succeeded: bool, result: u64, stage: []const u8) void {
    return guest_log.noteBackendMmapResult(self, succeeded, result, stage);
}

pub fn observeXeniaFixedMemoryView(self: anytype, address: u64, length: u64, offset: u64, anonymous: bool) void {
    const discovery = self.xenia_memory_views.observeFixedFileView(address, length, offset, anonymous);
    switch (discovery) {
        .ignored, .confirmed => {},
        .discovered => machoCapturePrint(
            "macho-processor: Xenia memory-view model discovered: mapping_base=0x{x} source=fixed_file_view length=0x{x}; Xbox virtual and physical log addresses can now be resolved to translated host aliases\n",
            .{ address, length },
        ),
        .conflicting => machoCapturePrint(
            "macho-processor: Xenia memory-view model CONFLICT: retained_base=0x{x} observed_base=0x{x}; translated provenance is disabled rather than attributing writes to the wrong process view\n",
            .{ self.xenia_memory_views.mapping_base, address },
        ),
    }
}

pub fn noteBackendMprotect(self: anytype, route: []const u8, address: u64, length: u64, prot: u64, succeeded: bool) void {
    return guest_log.noteBackendMprotect(self, route, address, length, prot, succeeded);
}

pub fn allocGuestFile(self: anytype, fd: i32, kind: GuestFileKind) ?u64 {
    for (&self.guest_files, 0..) |*file, idx| {
        if (!file.active) {
            file.* = .{
                .active = true,
                .fd = fd,
                .position = 0,
                .error_flag = false,
                .kind = kind,
            };
            return GUEST_FILE_BASE + idx;
        }
    }
    return null;
}

pub fn guestFileFromHandle(self: anytype, handle: u64) ?*GuestFile {
    if (handle < GUEST_FILE_BASE) return null;
    const idx_u64 = handle - GUEST_FILE_BASE;
    if (idx_u64 >= GUEST_FILE_MAX) return null;
    const idx: usize = @intCast(idx_u64);
    const file = &self.guest_files[idx];
    if (!file.active) return null;
    return file;
}

pub fn closeGuestFiles(self: anytype) void {
    for (&self.guest_files) |*file| {
        if (!file.active) continue;
        if (file.descriptor_alias != std.math.maxInt(u64)) {
            const alias_is_primary = file.descriptor_alias_is_primary;
            _ = self.fs_forwarder.fd_manager.closeGeneration(
                file.descriptor_alias,
                file.descriptor_generation,
            );
            if (alias_is_primary) file.fd = -1;
        }
        if (file.kind == .regular and file.fd >= 0) {
            _ = std.c.close(file.fd);
        }
        file.* = .{};
    }
}

pub fn fileOffsetForVaddr(self: anytype, vaddr: u64) ?u64 {
    for (self.segments) |seg| {
        if (vaddr < seg.vmaddr) continue;
        const delta = vaddr - seg.vmaddr;
        if (delta < seg.filesize) {
            return seg.fileoff + delta;
        }
    }
    return null;
}

pub inline fn logControlFlow(self: anytype, kind: []const u8, from_rip: u64, to_rip: u64, decoded_len: u64, return_addr: ?u64) void {
    if (!self.verbose_trace) return;
    if (return_addr) |ret_addr| {
        log.info("cf({s}): rip=0x{x} -> 0x{x} len={d} ret=0x{x} rsp=0x{x}", .{ kind, from_rip, to_rip, decoded_len, ret_addr, self.regs.rsp });
    } else {
        log.info("cf({s}): rip=0x{x} -> 0x{x} len={d} rsp=0x{x}", .{ kind, from_rip, to_rip, decoded_len, self.regs.rsp });
    }
}

pub fn inHelperCluster(self: anytype, rip: u64) bool {
    if (self.helper_cluster_start) |start| {
        const end = self.helper_cluster_end orelse start;
        return rip >= start and rip < end;
    }
    return false;
}

pub const HelperCluster = struct { start: u64, end: u64 };

pub fn findSharedHelperCluster(self: anytype, helper_rip: u64) ?HelperCluster {
    const helper_bytes = self.guestMemoryConst(helper_rip, 16) orelse return null;
    if (helper_bytes.len < 16) return null;
    var scan = helper_rip;
    var found_start: ?u64 = null;
    var count: usize = 0;
    while (count < 4096) : (count += 1) {
        if (scan < lazy_import_stub.entry_size) break;
        scan -= lazy_import_stub.entry_size;
        const bytes = self.guestMemoryConst(scan, lazy_import_stub.entry_size) orelse break;
        if (lazy_import_stub.decodeEntry(scan, bytes)) |stub| {
            if (stub.shared_helper == helper_rip) {
                found_start = scan;
                continue;
            }
        }
        break;
    }
    const start = found_start orelse return null;
    var end = start;
    count = 0;
    while (count < 4096) : (count += 1) {
        const bytes = self.guestMemoryConst(end, lazy_import_stub.entry_size) orelse break;
        if (lazy_import_stub.decodeEntry(end, bytes)) |stub| {
            if (stub.shared_helper == helper_rip) {
                end += lazy_import_stub.entry_size;
                continue;
            }
        }
        break;
    }
    return .{ .start = start, .end = end };
}

pub fn dumpGuestStack(self: anytype) void {
    const count: usize = 12;
    machoCapturePrint("    [stack backtrace (rsp=0x{x}):\n", .{self.regs.rsp});
    var addr = self.regs.rsp;
    for (0..count) |i| {
        const val = self.read64(addr);
        if (val == 0) {
            machoCapturePrint("      [{d}] 0x{x}: 0x0\n", .{ i, addr });
        } else if (self.metadata.nearestSymbol(val)) |sym| {
            machoCapturePrint("      [{d}] 0x{x}: 0x{x} → {s}+0x{x}\n", .{ i, addr, val, sym.name, sym.offset });
        } else {
            machoCapturePrint("      [{d}] 0x{x}: 0x{x}\n", .{ i, addr, val });
        }
        addr +%= 8;
    }
}

pub noinline fn handleStubHelperTransition(self: anytype) bool {
    // Lazy helper decoding used to touch guest memory for every interpreted
    // instruction. All classic helper entries live in __stub_helper, so the
    // overwhelmingly common path can reject them without translation or
    // byte decoding.
    if (self.regs.rip < self.stub_helper_start or self.regs.rip >= self.stub_helper_end) {
        return false;
    }
    const entry_bytes = self.guestMemoryConst(self.regs.rip, lazy_import_stub.entry_size);
    if (if (entry_bytes) |bytes| lazy_import_stub.decodeEntry(self.regs.rip, bytes) else null) |stub| {
        self.pending_stub_slot = stub.bind_slot;
        self.pending_stub_entry_rip = self.regs.rip;
        if (self.verbose_trace) log.info("stub-entry: rip=0x{x} slot=0x{x} shared_helper=0x{x}", .{ self.regs.rip, stub.bind_slot, stub.shared_helper });
        self.regs.rip = stub.shared_helper;
        return true;
    }

    const helper_bytes = self.guestMemoryConst(self.regs.rip, 16);
    if (self.pending_stub_slot != null and (if (helper_bytes) |bytes| lazy_import_stub.isSharedHelper(bytes) else false)) {
        const slot = self.pending_stub_slot.?;
        const entry_rip = self.pending_stub_entry_rip orelse self.regs.rip;
        const synthetic_return = self.read64(self.regs.rsp);
        if (self.findSharedHelperCluster(self.regs.rip)) |cluster| {
            self.helper_cluster_start = cluster.start;
            self.helper_cluster_end = cluster.end;
            if (self.verbose_trace) log.info("stub-helper cluster: helper_rip=0x{x} cluster=[0x{x}, 0x{x})", .{ self.regs.rip, cluster.start, cluster.end });
        }
        self.pending_stub_slot = null;
        self.pending_stub_entry_rip = null;
        if (self.pending_import_stub_rip) |import_stub_rip| {
            if (self.metadata.importAtStub(import_stub_rip)) |imported| {
                switch (self.handleImport(imported)) {
                    .handled => |result| {
                        self.regs.rax = result;
                        if (self.verbose_trace) {
                            machoCapturePrint("  [handled import] {s} from {s}; stub=0x{x} return=0x{x} → rax=0x{x}\n", .{
                                imported.name,
                                imported.dylib,
                                imported.stub_address,
                                synthetic_return,
                                result,
                            });
                        }
                    },
                    .handled_void => {
                        if (self.verbose_trace) {
                            machoCapturePrint(
                                "  [handled void import] {s} from {s}; stub=0x{x} return=0x{x}\n",
                                .{ imported.name, imported.dylib, imported.stub_address, synthetic_return },
                            );
                        }
                    },
                    .control_transferred => {
                        self.pending_import_stub_rip = null;
                        if (self.verbose_trace) {
                            machoCapturePrint(
                                "  [handled control transfer] {s} from {s}; landing_pad=0x{x}\n",
                                .{ imported.name, imported.dylib, self.regs.rip },
                            );
                        }
                        return true;
                    },
                    .unsupported => |result| {
                        self.regs.rax = result;
                        self.recordUnresolvedImport(imported, synthetic_return, self.regs.rax);
                        if (self.metadata.nearestSymbol(synthetic_return)) |caller_sym| {
                            machoCapturePrint(
                                "  [unresolved import #{d}] {s} from {s}; stub=0x{x} caller={s}+0x{x} return=0x{x} → rax=0x{x}\n",
                                .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, caller_sym.name, caller_sym.offset, synthetic_return, self.regs.rax },
                            );
                        } else {
                            machoCapturePrint(
                                "  [unresolved import #{d}] {s} from {s}; stub=0x{x} caller=0x{x} → rax=0x{x}\n",
                                .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, synthetic_return, self.regs.rax },
                            );
                        }
                        self.dumpGuestStack();
                        if (self.strict_imports) self.terminateForUnresolvedImport();
                    },
                    .terminated => |exit_code| {
                        self.exit_code = exit_code;
                        if (exit_diagnostics.reasonFromValue(self.termination_reason) == .unknown) {
                            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
                        }
                        self.terminated = true;
                        machoCapturePrint("  [terminal import] {s} exit_code={d}\n", .{ imported.name, exit_code });
                    },
                }
            }
        }
        self.pending_import_stub_rip = null;
        if (self.terminated) return true;
        if (synthetic_return != 0 and self.addrToOffset(synthetic_return) != null) {
            if (self.verbose_trace) log.warn("stub-helper aggressive fallback: helper_rip=0x{x} slot=0x{x} entry_rip=0x{x} synthetic_return=0x{x}; simulating resolved helper return", .{ self.regs.rip, slot, entry_rip, synthetic_return });
            _ = self.pop();
            self.regs.rip = synthetic_return;
        } else {
            log.warn("stub-helper conservative fallback: helper_rip=0x{x} slot=0x{x} entry_rip=0x{x}; synthetic_return invalid (0x{x}), skipping helper entry", .{ self.regs.rip, slot, entry_rip, synthetic_return });
            self.regs.rip = entry_rip + lazy_import_stub.entry_size;
        }
        return true;
    }

    if (self.inHelperCluster(self.regs.rip)) {
        const cluster_end = self.helper_cluster_end orelse self.regs.rip;
        log.warn("helper-cluster escape: rip=0x{x} cluster_end=0x{x}; forcing exit from packed stub region", .{ self.regs.rip, cluster_end });
        self.regs.rax = 0;
        self.regs.rip = cluster_end;
        self.helper_cluster_start = null;
        self.helper_cluster_end = null;
        return true;
    }

    return false;
}

pub fn primitiveMatches(self: anytype, name: []const u8) bool {
    _ = self;
    return primitive.builtin().matchSymbol(name) != null;
}

pub fn handleImport(self: anytype, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
    const name = imported.name;
    const return_address = self.read64(self.regs.rsp);
    const caller = if (self.metadata.nearestSymbol(return_address)) |symbol| symbol.name else "<unknown>";
    const active_initializer = self.initializer_resolver.current();
    const phase: import_resolution.Phase = if (active_initializer != null) .initializer else .execution;
    const owner = if (active_initializer) |initializer| initializer.symbol else "<main>";
    self.import_provider_override = null;
    self.import_confidence_override = null;
    const result = self.handleImportImpl(imported);

    const exact_contract = import_resolution.contractFor(name);
    const declared_contract = contract.resolveFromAllFamilies(name);
    const outcome: import_resolution.Outcome = switch (result) {
        .handled, .handled_void, .control_transferred => .resolved,
        .unsupported => .unresolved,
        .terminated => .terminated,
    };
    const inferred_provider: import_resolution.Provider = if (exact_contract != null)
        .contract
    else switch (result) {
        .unsupported => .none,
        else => if (declared_contract) |declared|
            switch (declared.strategy) {
                .stub, .synthesize, .terminate => .contract,
                else => .legacy_shim,
            }
        else
            .legacy_shim,
    };
    const inferred_confidence: import_resolution.Confidence = if (exact_contract != null)
        .verified
    else if (outcome == .unresolved)
        .unknown
    else
        .modeled;
    const provider = self.import_provider_override orelse inferred_provider;
    const confidence = self.import_confidence_override orelse inferred_confidence;
    self.import_resolver.record(name, caller, owner, phase, outcome, provider, confidence);
    return result;
}

pub fn callGuestFunction(self: anytype, fn_address: u64, args: [6]u64) u64 {
    const saved_regs = self.regs;
    const sentinel: u64 = 0xCA11_CA11_CA11_CA11;
    var result: u64 = 0;

    self.regs.rdi = args[0];
    self.regs.rsi = args[1];
    self.regs.rdx = args[2];
    self.regs.rcx = args[3];
    self.regs.r8 = args[4];
    self.regs.r9 = args[5];
    self.regs.rsp -%= 8;
    if (self.guestMemory(self.regs.rsp, 8)) |destination| {
        std.mem.writeInt(u64, destination[0..8], sentinel, .little);
        self.regs.rip = fn_address;

        var iterations: u32 = 0;
        while (iterations < 100_000 and !self.terminated and !self.faulted) : (iterations += 1) {
            if (self.regs.rip == sentinel) break;
            if (!self.step()) break;
        }
        result = self.regs.rax;
    }
    self.regs = saved_regs;
    return result;
}

pub fn tryPrimitiveDispatch(self: anytype, imported: macho_metadata.ImportedSymbol) ?ImportHandlerResult {
    const dispatch_cb = import_handler.PrimitiveDispatchCallbacks{
        .ctx = self,
        .matchSymbol = struct {
            fn match(_: *anyopaque, name: []const u8) ?*const anyopaque {
                // Use primitive.builtin().matchSymbol — doesn't need MachOState
                const h = primitive.builtin().matchSymbol(name);
                return if (h) |handler| @ptrCast(handler) else null;
            }
        }.match,
        .callHandler = struct {
            fn call(ctx: *anyopaque, slot: u32, handler_ptr: *const anyopaque) u8 {
                const typed_handler: primitive.types.Handler = @ptrCast(@alignCast(handler_ptr));
                var prim_ctx = primitive.types.PrimitiveContext{
                    .ptr = ctx,
                    .readArgFn = struct {
                        fn read(ptr: *anyopaque, index: u8) u64 {
                            const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                            return switch (index) {
                                0 => inner_st.regs.rdi,
                                1 => inner_st.regs.rsi,
                                2 => inner_st.regs.rdx,
                                3 => inner_st.regs.rcx,
                                4 => inner_st.regs.r8,
                                5 => inner_st.regs.r9,
                                else => 0,
                            };
                        }
                    }.read,
                    .setResultFn = struct {
                        fn set(ptr: *anyopaque, value: u64) void {
                            const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                            inner_st.regs.rax = value;
                        }
                    }.set,
                    .readGuestFn = struct {
                        fn read(ptr: *const anyopaque, address: u64, size: usize) ?[]const u8 {
                            const inner_st: *const MachOState = @ptrCast(@alignCast(ptr));
                            return inner_st.guestMemoryConst(address, @intCast(size));
                        }
                    }.read,
                    .writeGuestFn = struct {
                        fn write(ptr: *anyopaque, address: u64, data: []const u8) ?void {
                            const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                            return if (inner_st.writeGuestBytes(address, data)) {} else null;
                        }
                    }.write,
                    .readCStringFn = struct {
                        fn read(ptr: *const anyopaque, address: u64) ?[]const u8 {
                            const inner_st: *const MachOState = @ptrCast(@alignCast(ptr));
                            // Match the slow-path import handlers (strlen,
                            // strcmp, strcpy use a 1 MiB cap) so the
                            // primitive layer services the same inputs the
                            // slow path would instead of falling through
                            // to it with a shorter 4096-byte window.
                            return inner_st.guestCString(address, 1 << 20);
                        }
                    }.read,
                    .moveGuestFn = struct {
                        fn move(ptr: *anyopaque, destination_address: u64, source_address: u64, count: usize) bool {
                            const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                            if (count == 0 or destination_address == source_address) return true;
                            const count_u64: u64 = @intCast(count);
                            const source = inner_st.guestMemoryConst(source_address, count_u64) orelse return false;
                            const destination = inner_st.guestMemory(destination_address, count_u64) orelse return false;
                            const mutation = inner_st.captureMemoryMutation(destination_address, count_u64);
                            if (destination_address > source_address and destination_address - source_address < count_u64) {
                                std.mem.copyBackwards(u8, destination, source);
                            } else {
                                std.mem.copyForwards(u8, destination, source);
                            }
                            inner_st.commitMemoryMutation(mutation, .bulk_copy);
                            return true;
                        }
                    }.move,
                    .callGuestFn = struct {
                        fn call(ptr: *anyopaque, fn_address: u64, args: [6]u64) u64 {
                            const st: *MachOState = @ptrCast(@alignCast(ptr));

                            // Save the complete register state for restoration after the call.
                            const saved_regs = st.regs;

                            // Set up System V AMD64 ABI arguments for the guest function.
                            st.regs.rdi = args[0];
                            st.regs.rsi = args[1];
                            st.regs.rdx = args[2];
                            st.regs.rcx = args[3];
                            st.regs.r8 = args[4];
                            st.regs.r9 = args[5];

                            // Push a distinctive sentinel return address onto the guest
                            // stack so we can detect when the callee returns.
                            const sentinel: u64 = 0xCA11CA11CA11CA11;
                            st.regs.rsp -%= 8;
                            if (st.guestMemory(st.regs.rsp, 8)) |dest| {
                                std.mem.writeInt(u64, dest[0..8], sentinel, .little);
                            }

                            st.regs.rip = fn_address;

                            // Inline decode + execute loop.  We avoid calling
                            // self.step() because that would re-enter import
                            // dispatch and sentinel checks.  Instead we manually
                            // decode and execute each instruction until the
                            // callee rets back to our sentinel.
                            const max_iters: u32 = 200;
                            var iter: u32 = 0;
                            while (iter < max_iters) : (iter += 1) {
                                if (st.terminated or st.faulted) break;

                                // No gate chain ran before this decode (this
                                // loop deliberately skips it), so the fill must
                                // not mark the entry fast_plain.
                                const d = st.decodeWithLiveOperands(false) orelse break;
                                if (d.op == .invalid) break;

                                if (d.op == .ret) {
                                    // Pop return address from guest stack.
                                    if (st.guestMemory(st.regs.rsp, 8)) |src| {
                                        st.regs.rip = std.mem.readInt(u64, src[0..8], .little);
                                        st.regs.rsp +%= 8;
                                    }
                                    if (st.regs.rip == sentinel) break;
                                    continue;
                                }

                                const old_rip = st.regs.rip;
                                st.execute(d);
                                if (!st.terminated and st.regs.rip == old_rip) {
                                    st.regs.rip +%= d.len;
                                }
                            }

                            const result = st.regs.rax;
                            st.regs = saved_regs;
                            return result;
                        }
                    }.call,
                    .raiseSignalFn = struct {
                        fn raise(ptr: *anyopaque, signal: u8) primitive.types.RaiseResult {
                            const st: *MachOState = @ptrCast(@alignCast(ptr));
                            if (signal == 0 or signal >= st.signal_actions.len) return .failed;

                            const action = st.signal_actions[signal];
                            if (action.handler == 1) return .delivered; // SIG_IGN
                            if (action.handler > 1) {
                                const return_address = st.read64(st.regs.rsp);
                                if (signal_handling.deliverRaisedGuestSignal(st, signal, return_address)) return .delivered;
                            }

                            // The default action, or an invalid installed
                            // handler that could not be entered, terminates
                            // the guest only. Never call the host raise API.
                            st.exit_code = 128 + signal;
                            st.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unhandled_guest_signal);
                            st.terminated = true;
                            machoCapturePrint(
                                "macho-processor: guest raise({d}) applied default termination action; Rosette kept the host process alive\n",
                                .{signal},
                            );
                            return .terminated;
                        }
                    }.raise,
                    .pthreadMachThreadIdFn = struct {
                        fn lookup(ptr: *anyopaque, handle: u64) u64 {
                            const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                            return inner_st.pthreads.numericThreadId(handle);
                        }
                    }.lookup,
                    .dladdrResolveFn = struct {
                        fn resolve(ptr: *anyopaque, address: u64) primitive.types.DladdrInfo {
                            const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                            const match = inner_st.metadata.nearestSymbol(address) orelse return .{};
                            const file_offset = @as(u64, @intFromPtr(match.name.ptr)) - @as(u64, @intFromPtr(inner_st.data.ptr));
                            var name_vaddr: u64 = 0;
                            for (inner_st.segments) |seg| {
                                if (file_offset >= seg.fileoff and file_offset < seg.fileoff + seg.filesize) {
                                    name_vaddr = seg.vmaddr + (file_offset - seg.fileoff);
                                    break;
                                }
                            }
                            return .{
                                .found = true,
                                .dli_fbase = inner_st.mem_base,
                                .dli_sname = name_vaddr,
                                .dli_saddr = match.address,
                            };
                        }
                    }.resolve,
                };
                const result = typed_handler(slot, &prim_ctx);
                return @intFromEnum(result);
            }
        }.call,
        .readRegister = struct {
            fn read(ptr: *anyopaque, index: u8) u64 {
                const st: *MachOState = @ptrCast(@alignCast(ptr));
                return switch (index) {
                    0 => st.regs.rdi,
                    1 => st.regs.rsi,
                    2 => st.regs.rdx,
                    3 => st.regs.rcx,
                    4 => st.regs.r8,
                    5 => st.regs.r9,
                    else => 0,
                };
            }
        }.read,
        .readResult = struct {
            fn read(ptr: *const anyopaque) u64 {
                const st: *const MachOState = @ptrCast(@alignCast(ptr));
                return st.regs.rax;
            }
        }.read,
    };
    const log_cb = import_handler.PrimitiveLogCallbacks{
        .ctx = self,
        .logLine = struct {
            fn log(_: *anyopaque, text: []const u8) void {
                primitiveCapturePrint("{s}", .{text});
            }
        }.log,
    };
    const outcome = self.import_handler.tryPrimitiveDispatch(
        imported.name,
        dispatch_cb,
        log_cb,
    );
    return switch (outcome) {
        .handled => |value| ImportHandlerResult{ .handled = value },
        .handled_void => .handled_void,
        .control_transferred => .control_transferred,
        .unhandled => null,
    };
}
