// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const DecodeCacheEntry = __ProcessInternals._DecodeCacheEntry;
const application_controller = __ProcessInternals._application_controller;
const application_framework = __ProcessInternals._application_framework;
const async_log = __ProcessInternals._async_log;
const claim_reconciliation = __ProcessInternals._claim_reconciliation;
const constants = __ProcessInternals._constants;
const contract = __ProcessInternals._contract;
const deadlock_predictor = __ProcessInternals._deadlock_predictor;
const decodeInsn = __ProcessInternals._decodeInsn;
const decodeInsnCompat = __ProcessInternals._decodeInsnCompat;
const diagnostics_execution_profile = __ProcessInternals._diagnostics_execution_profile;
const execution_tracepoints = __ProcessInternals._execution_tracepoints;
const gpu = __ProcessInternals._gpu;
const graphics_health_contract = __ProcessInternals._graphics_health_contract;
const guest_log = __ProcessInternals._guest_log;
const guest_wait_liveness = __ProcessInternals._guest_wait_liveness;
const host_contract_coverage = __ProcessInternals._host_contract_coverage;
const interrupt_callback_transaction = __ProcessInternals._interrupt_callback_transaction;
const log = __ProcessInternals._log;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const macho_log = __ProcessInternals._macho_log;
const main = __ProcessInternals._main;
const mandatory_order = __ProcessInternals._mandatory_order;
const monotone_witness = __ProcessInternals._monotone_witness;
const native_crash = __ProcessInternals._native_crash;
const native_window = __ProcessInternals._native_window;
const notifier_liveness = __ProcessInternals._notifier_liveness;
const ownership_contract = __ProcessInternals._ownership_contract;
const pipeline_evidence = __ProcessInternals._pipeline_evidence;
const run_budget = __ProcessInternals._run_budget;
const run_horizon = __ProcessInternals._run_horizon;
const run_integrity = __ProcessInternals._run_integrity;
const startup_observer = __ProcessInternals._startup_observer;
const std = __ProcessInternals._std;
const substantiation = __ProcessInternals._substantiation;
const translation_cache = __ProcessInternals._translation_cache;
const translation_domain = __ProcessInternals._translation_domain;
const translation_economics = __ProcessInternals._translation_economics;
const unknown_inventory_mod = __ProcessInternals._unknown_inventory_mod;
const wait_audit = __ProcessInternals._wait_audit;
const wait_graph = __ProcessInternals._wait_graph;
const xenia_gpu_causal_trace = __ProcessInternals._xenia_gpu_causal_trace;
const xenia_gpu_handoff = __ProcessInternals._xenia_gpu_handoff;
const xenia_pipeline = __ProcessInternals._xenia_pipeline;
const ms = __ProcessInternals._ms;
const decodeCacheAlternateSetBaseFor = MachOState.decodeCacheAlternateSetBaseFor;
const decodeCacheEntryOccupied = MachOState.decodeCacheEntryOccupied;
const deliverGpuInterrupt = MachOState.deliverGpuInterrupt;
const ensureRunIntegrity = MachOState.ensureRunIntegrity;
const execute = MachOState.execute;
const fileOffsetForVaddr = MachOState.fileOffsetForVaddr;
const guestOutputEvidence = MachOState.guestOutputEvidence;
const logComponentReadiness = MachOState.logComponentReadiness;
const logDeadlockPredictor = MachOState.logDeadlockPredictor;
const logGuestWaitLiveness = MachOState.logGuestWaitLiveness;
const logMandatoryOrder = MachOState.logMandatoryOrder;
const logPreinitialization = MachOState.logPreinitialization;
const logProvisioningCustody = MachOState.logProvisioningCustody;
const logRingContents = MachOState.logRingContents;
const logUnknownInventory = MachOState.logUnknownInventory;
const logWaitAudit = MachOState.logWaitAudit;
const logWaitGraph = MachOState.logWaitGraph;
const refreshDeadlockPredictor = MachOState.refreshDeadlockPredictor;
const refreshHostCoverage = MachOState.refreshHostCoverage;
const refreshKernelVariables = MachOState.refreshKernelVariables;
const refreshPreinitialization = MachOState.refreshPreinitialization;
const refreshWaitAuditWitness = MachOState.refreshWaitAuditWitness;
const run = MachOState.run;
const runBudgetGuestWindowObserved = MachOState.runBudgetGuestWindowObserved;
const runBudgetGuestWindowSummary = MachOState.runBudgetGuestWindowSummary;
const runBudgetGuestWindowVerdict = MachOState.runBudgetGuestWindowVerdict;
const runHorizonStalled = MachOState.runHorizonStalled;
const step = MachOState.step;
const syncComponentReadiness = MachOState.syncComponentReadiness;
const syncMandatoryOrder = MachOState.syncMandatoryOrder;
const syncMonotoneWitnesses = MachOState.syncMonotoneWitnesses;
const syncPacketCensus = MachOState.syncPacketCensus;
const titleInterruptCallbackRegistrationObserved = MachOState.titleInterruptCallbackRegistrationObserved;

pub fn runIntegrityObservation(self: anytype) run_integrity.Observation {
    // Both of these are refreshed from the log paths on a coarser cadence
    // than this gate runs at, and a judgement made against a ledger that is
    // sixteen checkpoints stale is the stale-snapshot defect this codebase
    // has hit repeatedly. Refreshing here costs a walk over the capability
    // table and the thread list, which at checkpoint cadence is nothing.
    self.refreshHostCoverage();
    self.refreshDeadlockPredictor();
    // The progress witness the never-notified gate compares against is
    // otherwise sampled only inside `logWaitAudit`, which runs on a
    // sixteen-checkpoint cadence. Judging a park against a witness that
    // stale is the same stale-snapshot defect the rest of this gate exists
    // to catch.
    self.refreshWaitAuditWitness();
    // The wait graph has the same stale-snapshot hazard. Its summary is
    // part of the integrity decision, so update the independent progress
    // axis before taking the snapshot that the contract will judge.
    self.refreshWaitGraphProgress();
    // Ordering is itself an integrity input. Synchronise it in the same
    // snapshot that judges waits, capabilities, and PM4 so a newly
    // observed dependant cannot sit in the ledger until a later graphics
    // report while the run-integrity gate still sees the old answer.
    self.syncMandatoryOrder();
    // The witness ledger is another integrity input. It is normally
    // synchronised with the graphics report, but run-integrity can fire
    // before that report on the same checkpoint. Refresh it here so the
    // closure gate never judges a stale observer set.
    self.syncPacketCensus();
    self.syncMonotoneWitnesses(self.executed_steps);
    // Readiness is an admission input, not merely a verbose report. Keep
    // this snapshot beside the other ledgers so a component cannot be
    // proven or used between the readiness report and the integrity judge.
    self.syncComponentReadiness();
    const component_readiness = self.component_readiness.summary();
    const component_readiness_armed = component_readiness.proven != 0 or
        component_readiness.used_unproven != 0 or
        component_readiness.broken != 0;
    const admission = self.window_admission.summary();
    const frames = self.cocoa_graphics.frames.summary();
    const ownership = self.dynamic_forwarder.graphicsOwnershipSnapshot();
    const coverage = self.host_coverage.report();
    const economics = self.translation_economics.summary();
    const target = self.gpu_xenos_runtime.renderTargetEvidence();
    const pm4_evidence = self.gpu_xenos_runtime.runtimeEvidence();
    const guest_output = self.guestOutputEvidence();
    const mandatory_order_summary = self.mandatory_order.summary();
    // Which of Rosette's own counters can be trusted. Judged from the same
    // snapshot as everything else so a gate cannot stop the run on a
    // disagreement that the settling window had already resolved.
    const witnesses = self.monotone_witness.summary();
    // Read beside the witnesses so both halves of the corroboration story
    // come from one instant: how many claims have two observers, and how
    // many of those pairs are actively disagreeing.
    const claims = self.claim_reconciliation.summary();

    // The boundary the frontier blames, and whether anything but the
    // tracepoint has spoken about it. A negative that steers the whole
    // investigation has to be substantiated by more than the arming.
    var frontier_armed: u32 = 0;
    var frontier_reached: u32 = 0;
    var frontier_observers: u32 = 0;
    var frontier_settled: u64 = 0;
    // How much of the watched surface has ever fired. Zero means the guest
    // has not started this phase and the tracepoints have never
    // demonstrated they work, so the frontier is the first boundary of
    // something that has not begun rather than a wall the run is at.
    var frontier_crossed_elsewhere: u32 = 0;
    for (gpu.bringup_gate.contractBoundaries()) |boundary| {
        if (self.gpu_bringup_gate.recordFor(boundary).crossed()) {
            frontier_crossed_elsewhere += 1;
        }
    }
    if (self.gpu_bringup_gate.frontier(self.executed_steps)) |frontier| {
        // Restart the dwell timer whenever the frontier moves. A run that
        // is still crossing boundaries is progressing, and judging its
        // newest frontier would stop it for having arrived.
        const which: u8 = @intFromEnum(frontier);
        if (self.frontier_boundary_last != which) {
            self.frontier_boundary_last = which;
            self.frontier_boundary_since_step = self.executed_steps;
        }
        frontier_settled = self.executed_steps -| self.frontier_boundary_since_step;
        const frontier_addresses = self.execution_tracepoints.boundaryAddressCoverage(
            @intFromEnum(frontier),
        );
        frontier_armed = frontier_addresses.armed;
        frontier_reached = frontier_addresses.reached;
        frontier_observers = self.claim_reconciliation.observersForBoundary(frontier);
    } else {
        self.frontier_boundary_last = 0xFF;
    }
    const worst_park = self.deadlock_predictor.worst();
    const budget_totals = self.runBudgetGuestWindowSummary();
    const budget_observed = self.runBudgetGuestWindowObserved(budget_totals);
    const budget_verdict = self.runBudgetGuestWindowVerdict(budget_totals);
    // Do not turn the process-creation/static-initializer/Xenia-loader
    // prefix into a throughput fault: zero guest milliseconds are expected
    // there. Once the guest-main boundary is proven and ten host seconds
    // are represented in the same post-boundary window, a BELOW-BUDGET
    // verdict is a reachability defect, not an early startup sample.

    // The predictor's NEVER_NOTIFIED result is intentionally retained as
    // evidence but is not enough to stop an otherwise advancing run: an
    // idle worker and a lost producer have the same host-side shape. Find
    // the strongest object-level finding separately because a weaker
    // NEVER_NOTIFIED object may outrank a proven lower-numbered finding in
    // the predictor's severity ordering. Explicit mature cycles are even
    // stronger and are folded into the same immutable snapshot.
    var deadlock_observed = worst_park.object != null and worst_park.finding.deadlocked();
    var deadlock_proven = false;
    var deadlock_finding = @intFromEnum(worst_park.finding);
    var deadlock_waiters: u64 = if (worst_park.object) |object| object.waiters else 0;
    var deadlock_park_steps: u64 = if (worst_park.object) |object| object.longest_park_steps else 0;
    var proven_finding: ?deadlock_predictor.Finding = null;
    var proven_object: ?deadlock_predictor.Object = null;
    for (self.deadlock_predictor.objects[0..self.deadlock_predictor.object_count]) |object| {
        const finding = self.deadlock_predictor.classify(object);
        if (!finding.provenDeadlock()) continue;
        if (proven_finding == null or
            @intFromEnum(finding) > @intFromEnum(proven_finding.?))
        {
            proven_finding = finding;
            proven_object = object;
        }
    }
    if (proven_finding) |finding| {
        deadlock_observed = true;
        deadlock_proven = true;
        deadlock_finding = @intFromEnum(finding);
        if (proven_object) |object| {
            deadlock_waiters = object.waiters;
            deadlock_park_steps = object.longest_park_steps;
        }
    }

    // `findCycle` is a separate walk because `classify` cannot infer a
    // cycle from one object. Require every member of the cycle to have
    // crossed the predictor's mature park window, so a short lock-order
    // transition during startup cannot become a fatal run-integrity stop.
    for (self.deadlock_predictor.threads[0..self.deadlock_predictor.thread_count]) |thread| {
        if (!thread.state.parked()) continue;
        var chain: [8]u64 = undefined;
        const cycle = self.deadlock_predictor.findCycle(thread.handle, &chain) orelse continue;
        if (cycle.len < 2) continue;
        var mature = true;
        var oldest_park: u64 = 0;
        for (cycle) |handle| {
            var found_thread = false;
            for (self.deadlock_predictor.threads[0..self.deadlock_predictor.thread_count]) |candidate| {
                if (candidate.handle != handle) continue;
                found_thread = true;
                const parked_steps = self.executed_steps -| candidate.blocked_since_step;
                if (parked_steps < deadlock_predictor.minimum_park_steps) mature = false;
                oldest_park = @max(oldest_park, parked_steps);
                break;
            }
            if (!found_thread) mature = false;
        }
        if (!mature) continue;

        deadlock_observed = true;
        deadlock_proven = true;
        deadlock_finding = @intFromEnum(deadlock_predictor.Finding.wait_cycle);
        deadlock_park_steps = oldest_park;
        for (self.deadlock_predictor.objects[0..self.deadlock_predictor.object_count]) |object| {
            if (object.address != thread.waiting_on) continue;
            deadlock_waiters = object.waiters;
            break;
        }
        break;
    }

    // Native presenter health is judged from its own dependency-ordered
    // stage, not from the absence of guest pixels. A diagnostic clear can
    // prove that the Cocoa sink is alive while the title has not reached a
    // source yet; that is not a presenter failure. Conversely, a terminal
    // bring-up failure or device loss must stop a run once the presenter
    // was genuinely attempted. Surface backpressure and swapchain rebuilds
    // remain retryable by the presenter contract.
    const native_presenter_stage = self.dynamic_forwarder.nativePresenterStage();
    const presenter_attempted = self.dynamic_forwarder.native_presenter_attempts != 0;
    const presenter_nonretryable_failures: u64 = if (presenter_attempted and
        native_presenter_stage != .unstarted and
        native_presenter_stage != .ready and
        !native_presenter_stage.retryable())
        1
    else
        0;

    // Provisioning is only judgeable once its consumer boundary was seen.
    // The raw refusal total is intentionally retained: not-harness-owned,
    // already-present, and early address-unknown refusals are valid custody
    // decisions. An unresolved storage refusal is actionable only while its
    // console-owned resource is still unprovisioned.
    const provisioning = self.gpu_provisioning_custody.summary();
    const provisioning_armed = self.gpu_bootstrap.observations[
        @intFromEnum(gpu.Step.initialize_engines)
    ].seen;
    var provisioning_actionable_refusals: u64 = 0;
    for (self.gpu_provisioning_custody.records[0..self.gpu_provisioning_custody.count]) |record| {
        if (record.actionableRefusal()) provisioning_actionable_refusals +|= 1;
    }

    // The policy's `requires_fault` bit is the authority here. In
    // particular, `guest_synthetic_wake=REFUSED` is expected protection:
    // the policy refuses Rosette permission to invent a guest signal, but
    // that refusal is not itself evidence that the real signal was lost.
    var wait_policy_observed = false;
    var wait_policy_faults: u64 = 0;
    for (self.wait_graph.objects) |record| {
        if (!record.occupied) continue;
        const policy_decision = record.policyDecision();
        if (policy_decision.classification == .unobserved) continue;
        wait_policy_observed = true;
        if (policy_decision.requires_fault) wait_policy_faults +|= 1;
    }

    // Profile debt is only actionable after the profile itself says its
    // dominant region is decisive. Startup's two-sample snapshot remains a
    // useful breadcrumb, not a reason to terminate the process.
    const execution_profile = self.startup.profile.summary();
    const execution_profile_unclassified = execution_profile.by_region[
        @intFromEnum(diagnostics_execution_profile.Region.unclassified)
    ];
    const execution_profile_unresolved = execution_profile.by_region[
        @intFromEnum(diagnostics_execution_profile.Region.unresolved_symbol)
    ];

    // Swap-contract stages whose prerequisites hold and whose probes have
    // never once been attempted. The contract's own verdict already calls
    // this Rosette's hole rather than the title's absence; reading it here
    // is what makes the run stop instead of printing it twenty times.
    //
    // Refreshed first so the summary and the attempt floor come from the
    // same reading. The gate compares them against each other, and a stale
    // pair is still self-consistent, but a stale one beside a fresh one
    // would not be.
    self.refreshVdSwapContract();
    const vd_swap_probes = self.gpu_vd_swap_contract.diagnosisSummary();

    // The longest park on an object nothing has ever raised. A park on an
    // object that *has* been signalled is a late signal, which is a
    // different and much weaker finding.
    var never_notified_park: u64 = 0;
    if (worst_park.object) |object| {
        if (object.notifier_count == 0 and object.notifications == 0)
            never_notified_park = object.longest_park_steps;
    }

    // Objects with waiters and no notifier at all, past the liveness
    // classifier's own stall threshold. Distinct from the park *duration*
    // above: this is about the object rather than the wait, and waiters
    // chose that object, so something intended to signal it.
    var waiters_without_notifier: u64 = 0;
    for (self.deadlock_predictor.objects[0..self.deadlock_predictor.object_count]) |object| {
        if (object.waiters == 0) continue;
        if (object.notifier_count != 0 or object.notifications != 0) continue;
        if (object.longest_park_steps < notifier_liveness.default_stall_steps) continue;
        waiters_without_notifier += 1;
    }

    // Whether the run advanced alongside those parks. Captured once when a
    // never-notified park is first seen and re-based whenever an axis
    // moves, so the comparison is always against the start of the current
    // quiet window rather than against the start of the run. This witness
    // intentionally excludes raw instruction retirement: long JIT/compiler
    // loops can execute guest instructions without moving a subsystem axis.
    var progress_since_park = false;
    if (waiters_without_notifier != 0) {
        if (!self.never_notified_witness_valid) {
            self.never_notified_witness = self.wait_audit.witness;
            self.never_notified_witness_valid = true;
        } else if (self.wait_audit.witness.advancedSince(self.never_notified_witness)) {
            progress_since_park = true;
            self.never_notified_witness = self.wait_audit.witness;
        }
    } else {
        self.never_notified_witness_valid = false;
    }

    // A flat non-step witness is not the same thing as a frozen guest. Use
    // the step counter only for the stronger question: did this checkpoint
    // observe exactly the same guest execution position as the previous
    // integrity checkpoint? This keeps idle host workers diagnostic while
    // preserving the fail-fast path for a genuinely stopped run.
    const run_execution_frozen = self.run_integrity.evaluations != 0 and
        self.executed_steps == self.run_integrity.last_observation.step;

    // A wait subject that has timed out repeatedly and been signalled zero
    // times. A finite manual-reset poll is a completed guest timeout, not
    // an unbounded wait; retain it in the observation but do not promote it
    // into the wait-receives-signals fault. Its producer evidence is
    // printed by logWaitAudit as a separate timeout contract.
    var unsignalled_timeouts: u64 = 0;
    var timeout_subject: ?wait_audit.Subject = null;
    var bounded_timeout_subjects: u64 = 0;
    var bounded_timeout_attempts: u64 = 0;
    var bounded_timeout_subject: ?wait_audit.Subject = null;
    for (self.wait_audit.subjects[0..self.wait_audit.count]) |subject| {
        if (subject.timeout_class == .bounded_poll) {
            bounded_timeout_subjects +|= 1;
            bounded_timeout_attempts +|= subject.timeouts;
            const better_bounded = bounded_timeout_subject == null or
                subject.timeouts > bounded_timeout_subject.?.timeouts or
                (subject.timeouts == bounded_timeout_subject.?.timeouts and
                    (subject.first_step < bounded_timeout_subject.?.first_step or
                        (subject.first_step == bounded_timeout_subject.?.first_step and
                            subject.object < bounded_timeout_subject.?.object)));
            if (better_bounded) bounded_timeout_subject = subject;
            continue;
        }
        if (subject.signals != 0 or subject.timeouts == 0) continue;
        const better = timeout_subject == null or
            subject.timeouts > timeout_subject.?.timeouts or
            (subject.timeouts == timeout_subject.?.timeouts and
                (subject.first_step < timeout_subject.?.first_step or
                    (subject.first_step == timeout_subject.?.first_step and
                        subject.object < timeout_subject.?.object)));
        if (!better) continue;
        unsignalled_timeouts = subject.timeouts;
        timeout_subject = subject;
    }
    const selected_timeout_subject = timeout_subject orelse wait_audit.Subject{};
    const selected_bounded_timeout = bounded_timeout_subject orelse wait_audit.Subject{};
    const bounded_timeout_other_progress = bounded_timeout_subject != null and
        selected_bounded_timeout.last_witness.advancedSince(selected_bounded_timeout.first_witness);
    var bounded_timeout_notifier_proven = false;
    if (bounded_timeout_subject != null) {
        for (self.audit_sync.retained()) |entry| {
            const address_matches = selected_bounded_timeout.object != 0 and
                entry.identity.address.guest_virtual == @as(u32, @truncate(selected_bounded_timeout.object));
            const handle_matches = selected_bounded_timeout.handle != 0 and
                entry.identity.handle == selected_bounded_timeout.handle;
            if (!address_matches and !handle_matches) continue;
            bounded_timeout_notifier_proven = entry.fullyAttributed() and
                entry.standing().promotableToCause();
            break;
        }
    }
    const wait_graph_summary = self.wait_graph.summary();
    const wait_graph_blocker = self.wait_graph.blocking() orelse wait_graph.ObjectRecord{};
    const blocker_waiter = wait_graph_blocker.soleWaiter();
    const blocker_signaller = wait_graph_blocker.soleSignaller();

    // The deadlock predictor observes Rosette's host pthread condvars,
    // while the wait graph observes explicit guest synchronization. A
    // host worker that has never been notified is therefore not, by
    // itself, proof that a guest producer was lost. Promote the raw census
    // only when there is a causal witness: an actual guest wait with no
    // signal, a classified sync-registry object whose waiter obligation is
    // promotable, or a run whose guest execution position is unchanged
    // between integrity checkpoints. A flat non-step progress witness is
    // not enough, because translation/JIT work can still be executing.
    const guest_wait_obligation = wait_graph_blocker.address != 0 and
        wait_graph_blocker.waits != 0 and
        wait_graph_blocker.signals == 0;
    var registry_wait_obligation = false;
    for (self.audit_sync.retained()) |entry| {
        if (entry.waiter_count != 0 and entry.standing().promotableToCause()) {
            registry_wait_obligation = true;
            break;
        }
    }
    const liveness_obligation_proven = run_integrity.proveLivenessObligation(
        waiters_without_notifier,
        guest_wait_obligation,
        registry_wait_obligation,
        run_execution_frozen,
        progress_since_park,
    );
    const actionable_waiters_without_notifier = if (liveness_obligation_proven)
        waiters_without_notifier
    else
        0;

    // Anything Rosette produced on the emulator's behalf. The draw
    // dispatcher's deliveries and the substitution layer's fabrications are
    // both counted: either one means the run advanced on Rosette's output.
    const substitutions = self.gpu_swap_substitution.packets_published +|
        self.gpu_swap_substitution.pointers_advanced +|
        self.gpu_draw_dispatch.delivered;

    const producer_quiet = self.executed_steps -| self.gpu_ring_publication.last_advance_step;
    const liveness_scope = self.runIntegrityLivenessScope();
    const pause_transaction_defects = self.audit_pause.defectCount();

    const coverage_percent: u32 = @intCast(coverage.percent());
    if (coverage_percent > self.host_coverage_best_percent) {
        self.host_coverage_best_percent = coverage_percent;
        self.host_coverage_progress_step = self.executed_steps;
    }
    const capability_guest_progress_step = self.capabilityGuestProgressStep();
    const capability_progress_witness_step = run_integrity.capabilityProgressWitnessStep(
        self.host_coverage_progress_step,
        capability_guest_progress_step,
    );

    return .{
        .step = self.executed_steps,
        .liveness_scope = liveness_scope,
        .window_forwardings = admission.observations,
        .window_unaccountable = admission.unaccountable,
        .frames_presented_to_window = self.window_presentations,
        .frames_in_custody = frames.presentations_covered,
        .authentic_frames_presented = frames.authentic_guest,
        .host_frames_presented = frames.guest_pixels_host_cadence,
        .diagnostic_frames_presented = frames.diagnostic,
        .native_present_requests = ownership.xenia_presents,
        .native_gpu_completions = ownership.xenia_present_completions,
        .swap_boundaries_reached = self.swap_boundaries_reached,
        .swap_boundaries_offered = self.window_admission.touchedBoundaries(),
        .presenter_ready = self.dynamic_forwarder.nativePresenterStage().isReady(),
        .presenter_attempted = presenter_attempted,
        .presenter_nonretryable_failures = presenter_nonretryable_failures,
        .draws_consumed = guest_output.raw_draws_consumed,
        .renderable_draws_observed = guest_output.renderable_draws_observed,
        .render_target_state_observed = target.state_observed,
        .render_target_output_ready = target.outputReady(),
        .draw_completion_signals = self.gpu_xenos_runtime.draw_completion_signals,
        .color_resolve_observations = guest_output.color_resolve_observations,
        .guest_swap_boundaries = guest_output.guest_swap_boundaries,
        .guest_vdswap_packets_encoded = guest_output.guest_vdswap_packets_encoded,
        .guest_output_opportunity_observed = host_contract_coverage.guestOutputOpportunity(guest_output),
        .frames_published_by_any_producer = self.dynamic_forwarder.publishedFrameGenerations(),
        .producer_quiet_steps = producer_quiet,
        .longest_never_notified_park_steps = never_notified_park,
        .deadlock_observed = deadlock_observed,
        .deadlock_proven = deadlock_proven,
        .deadlock_finding = deadlock_finding,
        .deadlock_waiters = deadlock_waiters,
        .deadlock_park_steps = deadlock_park_steps,
        .unsignalled_wait_timeouts = unsignalled_timeouts,
        .unsignalled_wait_object = selected_timeout_subject.object,
        .unsignalled_wait_handle = selected_timeout_subject.handle,
        .unsignalled_wait_type = selected_timeout_subject.type_code,
        .unsignalled_wait_waits = selected_timeout_subject.waits,
        .unsignalled_wait_signals = selected_timeout_subject.signals,
        .unsignalled_wait_first_step = selected_timeout_subject.first_step,
        .unsignalled_wait_last_step = selected_timeout_subject.last_step,
        .bounded_timeout_subjects = bounded_timeout_subjects,
        .bounded_timeout_attempts = bounded_timeout_attempts,
        .bounded_timeout_object = selected_bounded_timeout.object,
        .bounded_timeout_handle = selected_bounded_timeout.handle,
        .bounded_timeout_ms = selected_bounded_timeout.timeout_ms,
        .ring_producer_published = self.gpu_ring_publication.published(),
        .bounded_timeout_signals = selected_bounded_timeout.signals,
        .bounded_timeout_first_step = selected_bounded_timeout.first_step,
        .bounded_timeout_last_step = selected_bounded_timeout.last_step,
        .bounded_timeout_notifier_proven = bounded_timeout_notifier_proven,
        .bounded_timeout_other_progress = bounded_timeout_other_progress,
        .wait_graph_events = wait_graph_summary.events,
        .wait_graph_objects = wait_graph_summary.objects,
        .wait_graph_stalled_handshakes = wait_graph_summary.stalled_handshakes,
        .wait_graph_cycles = wait_graph_summary.cycles,
        .wait_graph_insufficient = wait_graph_summary.insufficient,
        .wait_graph_dropped_objects = wait_graph_summary.dropped_objects,
        .wait_graph_blocker_object = wait_graph_blocker.address,
        .wait_graph_blocker_waits = wait_graph_blocker.waits,
        .wait_graph_blocker_signals = wait_graph_blocker.signals,
        .wait_graph_blocker_waiter_thread = if (blocker_waiter) |participant| participant.thread else 0,
        .wait_graph_blocker_waiter_pc = if (blocker_waiter) |participant| participant.pc else 0,
        .wait_graph_blocker_signaller_thread = if (blocker_signaller) |participant| participant.thread else 0,
        .wait_graph_blocker_signaller_pc = if (blocker_signaller) |participant| participant.pc else 0,
        .wait_graph_blocker_first_step = wait_graph_blocker.first_step,
        .wait_graph_blocker_last_step = wait_graph_blocker.last_step,
        .wait_graph_blocker_participants_dropped = wait_graph_blocker.participants_dropped,
        .application_controller_decisions = self.application_controller.observations,
        .application_controller_contract_violations = self.application_controller.contract_violations,
        .provisioning_armed = provisioning_armed,
        .provisioning_raw_refusals = provisioning.refusals,
        .provisioning_actionable_refusals = provisioning_actionable_refusals,
        .provisioning_late = @intCast(provisioning.late),
        .provisioning_diverged = @intCast(provisioning.diverged),
        .provisioning_contested = @intCast(provisioning.contested),
        .provisioning_unprovisioned = @intCast(provisioning.unprovisioned),
        .wait_policy_observed = wait_policy_observed,
        .wait_policy_faults = wait_policy_faults,
        .capabilities_exercised = coverage.satisfied + coverage.degraded + coverage.unsatisfied,
        .capabilities_unsatisfied = coverage.unsatisfied,
        .critical_capabilities_total = coverage.critical_total,
        .critical_capabilities_satisfied = coverage.critical_satisfied,
        .critical_capabilities_degraded = coverage.critical_degraded,
        .critical_capabilities_unsatisfied = coverage.critical_unsatisfied,
        .critical_capabilities_untested = coverage.critical_untested,
        .capability_progress_quiet_steps = run_integrity.capabilityProgressQuietSteps(
            self.executed_steps,
            self.host_coverage_progress_step,
            capability_guest_progress_step,
        ),
        .capability_coverage_progress_step = self.host_coverage_progress_step,
        .capability_guest_progress_step = capability_guest_progress_step,
        .capability_progress_witness_step = capability_progress_witness_step,
        .harness_substitutions = substitutions,
        .strict_fail_fast = self.run_integrity_strict,
        .translation_cache_entries = self.decode_cache.len,
        .translation_vacant_fills = economics.vacant_fills,
        .translation_conflict_fills = economics.conflict_fills,
        .translation_cold_evictions = economics.cold_evictions,
        .translation_stale_refills = economics.stale_refills,
        .translation_flush_refills = economics.flush_refills,
        .translation_hits = self.decode_cache_hits,
        .translation_misses = self.decode_cache_misses,
        .recorded_anomalies = self.anomalies.count,
        .pause_transaction_defects = pause_transaction_defects,
        .component_readiness_armed = component_readiness_armed,
        .essential_component_gaps = component_readiness.essential_gaps,
        .execution_profile_samples = execution_profile.samples,
        .execution_profile_readable = execution_profile.readable(),
        .execution_profile_decisive = execution_profile.dominantIsDecisive(),
        .execution_profile_unclassified = execution_profile_unclassified,
        .execution_profile_unresolved = execution_profile_unresolved,
        .vd_swap_unprobed_reachable_stages = vd_swap_probes.unprobed,
        .vd_swap_rosette_closable_starvations = vd_swap_probes.starved_closable_by_rosette,
        .vd_swap_probe_attempt_floor = self.gpu_vd_swap_contract.probes.maxAttempts(),
        .run_budget_observed = budget_observed,
        .run_budget_deficit = budget_observed and budget_verdict == .below_budget,
        .run_budget_guest_ms_per_host_second = budget_totals.guestMsPerHostSecond(),
        .run_budget_required_guest_ms_per_host_second = self.audit_budget.required_guest_ms_per_host_second,
        .run_budget_host_seconds = budget_totals.host_ns / std.time.ns_per_s,
        .run_budget_guest_ms = budget_totals.guest_ms,
        .waiters_without_a_notifier = waiters_without_notifier,
        .actionable_waiters_without_a_notifier = actionable_waiters_without_notifier,
        .liveness_obligation_proven = liveness_obligation_proven,
        .run_execution_frozen = run_execution_frozen,
        // The horizon's own verdict, computed from the producer's
        // publication axis rather than from instruction retirement. This
        // is the one progress reading here that a spinning main loop
        // cannot forge, which is why it is the one that can end a run.
        .run_horizon_stalled = self.runHorizonStalled(),
        .run_horizon_milestones = self.run_horizon.milestones_reached,
        .progress_since_never_notified_park = progress_since_park,
        .reinterpreted_texture_formats = self.texture_format_summary.reinterpreted,
        .texture_formats_probed = self.texture_format_summary.probed != 0,
        .parks_without_a_reason = self.pthreads.parksWithoutAReason(),
        .ownership_violations = self.application_framework.ownershipViolations(),
        // Only the ones Rosette was allowed to answer. A boundary the title
        // alone can give is reported by the substantiation report and owned
        // by the frontier that tracks the title, not by this gate.
        .unsubstantiated_boundaries = self.substantiation_summary.unsubstantiated_answerable,
        .diverged_boundaries = self.substantiation_summary.diverged,
        .measurement_drift_boundaries = self.substantiation_summary.measurement_drifts,
        .substantiation_armed = self.substantiation_summary.answered != 0 or
            self.substantiation_summary.unsubstantiated != 0 or
            self.substantiation_summary.diverged != 0 or
            self.substantiation_summary.measurement_drifts != 0,
        .pm4_packets_observed = pm4_evidence.packets_observed,
        .pm4_packets_executed = pm4_evidence.packets_executed,
        .pm4_packet_errors = pm4_evidence.packet_errors,
        .pm4_invalid_packets = pm4_evidence.invalid_packets,
        .pm4_unknown_opcodes = pm4_evidence.unknown_opcodes,
        .pm4_truncated_rings = pm4_evidence.truncated_rings,
        .pm4_indirect_unreadable = pm4_evidence.indirect_unreadable,
        .pm4_indirect_truncated = pm4_evidence.indirect_truncated,
        .pm4_indirect_invalid = pm4_evidence.indirect_invalid,
        .pm4_indirect_depth_limited = pm4_evidence.indirect_depth_limited,
        .pm4_indirect_budget_limited = pm4_evidence.indirect_budget_limited,
        .pm4_indirect_cycles = pm4_evidence.indirect_cycles,
        .pm4_unclassified_register_writes = pm4_evidence.unclassified_register_writes,
        .pm4_out_of_range_register_writes = pm4_evidence.out_of_range_register_writes,
        .pm4_defects = pm4_evidence.defectCount(),
        .mandatory_order_armed = mandatory_order_summary.active != 0 or
            mandatory_order_summary.mandatory_violations != 0,
        .mandatory_order_active = mandatory_order_summary.active,
        .mandatory_order_violated = mandatory_order_summary.violated,
        .mandatory_order_mandatory_violations = mandatory_order_summary.mandatory_violations,
        .mandatory_order_raced = mandatory_order_summary.raced,
        .gpu_preinitialization_inversions = @intCast(self.gpu_preinitialization.inversion_count),
        .gpu_preinitialization_inversions_dropped = self.gpu_preinitialization.inversions_dropped,
        .settled_observer_undercounts = witnesses.judgeableDefects(),
        // Corroboration is only possible where a fact has two witnesses.
        // A surface where nothing is corroborated is uncorroborated, not
        // clean, and arming the gate on it would report a passing grade
        // for an observation nothing has checked.
        .monotone_witness_corroboration_possible = witnesses.observed > witnesses.uncorroborated,
        // Closure means every required subject has an actual claim. A
        // subject whose witnesses all still read zero is counted as
        // unclaimed rather than observed, so arming this gate now needs
        // nine statements rather than nine armed tracepoints.
        .monotone_witness_closure_ready = witnesses.required_observed == monotone_witness.required_subject_count,
        .frontier_boundary_armed = frontier_armed != 0,
        .frontier_boundary_settled_steps = frontier_settled,
        .frontier_boundary_crossed_elsewhere = frontier_crossed_elsewhere,
        .external_progress_fresh = self.ready.hasRecentExternalProgress(self.executed_steps),
        .frontier_boundary_addresses_reached = frontier_reached,
        .frontier_boundary_corroborating_observers = frontier_observers,
        .settled_unknown_mappings = self.unknown_inventory.settledBlockers(
            unknown_inventory_mod.settled_blocker_threshold,
        ),
        .claim_reconciliation_contested = claims.contested,
        .claim_reconciliation_multi_source = claims.multi_source,
        .monotone_witness_required = @intCast(monotone_witness.required_subject_count),
        .monotone_witness_observed = @intCast(witnesses.required_observed),
        .monotone_witness_corroborated = @intCast(witnesses.required_corroborated),
        .monotone_witness_agreement_debt = @intCast(witnesses.required_agreement_debt),
    };
}

pub fn refreshWaitGraphProgress(self: anytype) void {
    self.wait_graph.noteProgress(
        @as(u64, gpu.vd_swap_contract.observedCount(self.gpu_vd_swap_contract.observed_mask)) +|
            self.gpu_ring_publication.advances +|
            self.run_horizon.milestones_reached +|
            // Translation generations belong on this axis for the same
            // reason they belong on the capability one below: a title can
            // spend a long prefix reaching new guest code while the
            // graphics ladder quite correctly does not move, and a spinning
            // thread cannot advance this counter — reaching a function
            // nothing has translated yet is exactly what a spin does not do.
            //
            // Without it the 2026-08-30 20:08 run raised SIGSEGV on
            // `no-stalled-wait-handshake` at step 4_200_000_000 while the
            // Ready Compiler had accepted generation 1344 three million
            // steps earlier. The handshake really was cycling; the claim
            // that nothing outside it was moving was false, and it stopped
            // the run before the question it was started to answer could
            // be reached.
            self.ready.translationProgressGeneration(),
    );
}

pub fn runIntegrityGpuActivity(self: anytype) bool {
    return self.gpu_bootstrap.seen(.initialize_engines) or
        self.gpu_bootstrap.seen(.graphics_interrupt_callback) or
        self.gpu_bootstrap.seen(.ring_buffer) or
        self.gpu_bootstrap.seen(.ring_write_pointer) or
        self.gpu_bootstrap.seen(.pm4_packet_consumed) or
        self.gpu_bootstrap.seen(.swap) or
        self.gpu_ring_publication.advances != 0 or
        self.gpu_xenos_runtime.batches != 0 or
        self.xenia_gpu_handoff.pm4_packets != 0 or
        self.swap_boundaries_reached != 0 or
        self.guest_vdswap_packet_encoded or
        self.guest_vdswap_entry_completed;
}

pub fn capabilityGuestProgressStep(self: anytype) u64 {
    var progress_step: u64 = 0;
    if (self.ready.work_unit_count != 0) {
        progress_step = @max(progress_step, self.ready.lastNamedProgressStep());
    }
    if (self.ready.external_progress_advances != 0) {
        progress_step = @max(progress_step, self.ready.externalProgressStep());
    }
    return progress_step;
}

pub fn substantiationGpuActivity(self: anytype) bool {
    return self.gpu_bootstrap.seen(.ring_buffer) or
        self.gpu_bootstrap.seen(.ring_write_pointer) or
        self.gpu_bootstrap.seen(.pm4_packet_consumed) or
        self.gpu_bootstrap.seen(.swap) or
        self.gpu_ring_publication.advances != 0 or
        self.gpu_xenos_runtime.batches != 0 or
        self.gpu_xenos_runtime.executor.packet_count != 0 or
        self.xenia_gpu_handoff.pm4_packets != 0 or
        self.swap_boundaries_reached != 0 or
        self.guest_vdswap_packet_encoded or
        self.guest_vdswap_entry_completed;
}

pub fn runIntegrityLivenessScope(self: anytype) run_integrity.LivenessScope {
    return run_integrity.livenessScope(
        self.xenia_pipeline.hasReached(.guest_main_ready),
        self.runIntegrityGpuActivity(),
    );
}

pub fn refreshWindowPresentations(self: anytype) void {
    const ownership = self.dynamic_forwarder.graphicsOwnershipSnapshot();
    self.window_presentations = ownership.rosette_diagnostic_frames +|
        ownership.rosette_host_frames +|
        ownership.rosette_guest_output_frames +|
        self.native_window.diagnostic_frames_presented +|
        self.native_window.guest_frames_presented;
}

pub fn refreshSubstantiation(self: anytype) substantiation.Summary {
    const tracepoints = &self.execution_tracepoints;
    const vd = &self.gpu_vd_swap_contract;
    const at = self.executed_steps;
    const ownership = self.dynamic_forwarder.graphicsOwnershipSnapshot();
    const ledger = &self.substantiation;

    // Do not start the unanswered-boundary clock at process creation. A
    // long translation/startup prefix can legitimately precede every GPU
    // event; holding future ring/swap/presenter boundaries accountable in
    // that phase turns an expected ordering gap into a Rosette-owned stop.
    const scope = substantiation.scopeFor(
        self.xenia_pipeline.hasReached(.guest_main_ready),
        self.substantiationGpuActivity(),
    );
    ledger.setScope(scope, at);

    const executed = substantiation.Evidence.executed;
    const entered = substantiation.Evidence.entered;
    const observed = substantiation.Evidence.observed;

    // Ring publication. Xenia's publisher is an address; Rosette watches
    // the write pointer itself. A setup tracepoint is not publication, and
    // a publication entry is not completion until the pointer/span proves
    // that a command span actually existed.
    const ring_entry = tracepoints.roleEntered(.ring_publication);
    const ring_published = self.gpu_ring_publication.published();
    if (ring_published) {
        if (ring_entry)
            ledger.answer(.ring_publication, .application, executed, 0, false, at);
        if (self.gpu_ring_publication.advances != 0) {
            ledger.answerWithDomain(.ring_publication, .harness, observed, self.gpu_ring_publication.advances, true, .ring_advances, at);
        } else {
            // A sampled non-empty span proves publication but has no
            // pointer-advance count that can be compared as a value.
            ledger.answer(.ring_publication, .harness, observed, 0, false, at);
        }
    } else if (ring_entry) {
        ledger.answer(.ring_publication, .application, entered, 0, false, at);
    }

    // PM4 consumption. Rosette's stateful executor counts the packets it
    // walked; Xenia's command processor is an address. `packet_count`
    // includes a header that may be rejected as truncated, so only the
    // successful portion is allowed to substantiate consumption.
    const command_entry = tracepoints.roleEntered(.command_processor);
    const packet_count = self.gpu_xenos_runtime.executor.packet_count;
    const valid_packet_count = packet_count -| self.gpu_xenos_runtime.executor.invalid_packet_count;
    if (valid_packet_count != 0) {
        if (command_entry)
            ledger.answer(.command_processor, .application, executed, 0, false, at);
        ledger.answerWithDomain(.command_processor, .harness, observed, valid_packet_count, true, .pm4_packets, at);
    } else if (command_entry) {
        ledger.answer(.command_processor, .application, entered, 0, false, at);
    }

    // The swap request is the title's alone. Rosette can observe one and
    // never originate one, so it is left with nothing to say here by
    // design rather than by omission. An encoded packet is a later stream
    // fact, not proof that the VdSwap request boundary was entered.
    if (vd.vdswap_calls != 0) {
        ledger.answerWithDomain(.swap_request, .application, executed, vd.vdswap_calls, true, .swap_requests, at);
    } else if (tracepoints.roleEntered(.swap)) {
        ledger.noteApplicationEntry(.swap_request, at);
    }

    if (vd.decoded_packet_observations != 0) {
        if (tracepoints.roleEntered(.xe_swap_decode))
            ledger.answer(.swap_decode, .application, executed, 0, false, at);
        ledger.answerWithDomain(.swap_decode, .harness, observed, vd.decoded_packet_observations, true, .xe_swap_packets, at);
    } else if (tracepoints.roleEntered(.xe_swap_decode)) {
        ledger.noteApplicationEntry(.swap_decode, at);
    }

    const presenter_entry = tracepoints.roleEntered(.command_swap) or tracepoints.roleEntered(.presenter);
    if (ownership.xenia_presents != 0) {
        ledger.answerWithDomain(.presenter_entry, .application, executed, ownership.xenia_presents, true, .presenter_requests, at);
    } else if (presenter_entry) {
        ledger.noteApplicationEntry(.presenter_entry, at);
    }
    // Presenter entry is a request boundary, not a completed-frame
    // boundary. Xenia's successful real present count is the application
    // account above; the independent Rosette account is the number of
    // guest requests that actually reached the host Vulkan driver. The
    // native-presenter frame ledger is intentionally not used here: a
    // request can reach the driver before a drawable completes, which is
    // exactly the state this run reached.
    const guest_present_requests = self.dynamic_forwarder.guestVulkanPresentRequests();
    if (guest_present_requests != 0) {
        ledger.answerWithDomain(.presenter_entry, .harness, observed, guest_present_requests, true, .presenter_requests, at);
    }

    // These are two valid but independent executor domains. Xenia's
    // PowerPC callback is dispatched by Xenia's CPU engine; Rosette's
    // optional completion route is dispatched by the modelled x86 runtime.
    // Comparing one domain's count with the other domain's zero creates a
    // false result drift, which is exactly what the 2026-08-31 capture
    // reported: Xenia returned three title callbacks while the Rosette
    // model had delivered none. Pick the active route as the account for
    // this boundary and keep the other route in its own ledger.
    // Registration opens the question; it does not answer the question
    // "did a dispatch occur?". The old predicate merged those two states,
    // so a valid VdSet followed by zero dispatches blocked Rosette from
    // recording the strict, bounded negative that the run had actually
    // established.
    const xenia_interrupt_dispatch_observed =
        self.interrupt_callback_transaction.dispatch_attempts != 0;
    const model_interrupt_dispatch_observed =
        self.gpu_draw_completion_dispatch_attempts != 0 or
        self.gpu_draw_completion_dispatches != 0;
    // An explicit title callback registration opens the interrupt
    // boundary even when neither executor has attempted a dispatch yet.
    // The registration is evidence that Rosette can inspect the route;
    // it is not evidence that a callback ran and it never authorizes one.
    // Without this third source, a valid VdSetGraphicsInterruptCallback
    // followed by a quiet vblank interval remained `unsubstantiated`.
    const title_interrupt_route_registered =
        self.titleInterruptCallbackRegistrationObserved();
    const interrupt_dispatch_observed =
        xenia_interrupt_dispatch_observed or model_interrupt_dispatch_observed;
    if (xenia_interrupt_dispatch_observed) {
        const dispatches = self.interrupt_callback_transaction.dispatch_attempts;
        if (dispatches != 0) {
            ledger.answerWithDomain(.interrupt_dispatch, .application, observed, dispatches, true, .interrupt_dispatches, at);
        }
    } else if (model_interrupt_dispatch_observed) {
        const dispatches = if (self.gpu_draw_completion_dispatches != 0)
            self.gpu_draw_completion_dispatches
        else
            self.gpu_draw_completion_dispatch_attempts;
        ledger.answerWithDomain(.interrupt_dispatch, .harness, observed, dispatches, true, .interrupt_dispatches, at);
    }

    const target = self.gpu_xenos_runtime.renderTargetEvidence();
    if (target.state_observed)
        ledger.answerWithDomain(.render_target, .application, observed, target.raw_color_info, true, .render_target_state, at);

    // A successful Xenia `vkQueuePresentKHR` is a presenter-entry/request
    // fact, not proof that a drawable reached Rosette's window. The
    // request is recorded above under `presenter_entry`. The frame
    // boundary is owned by the window ledger and therefore only receives
    // the independently measured window-presentation count. This keeps a
    // request count from being compared with diagnostic/host/guest window
    // frames.
    if (self.window_presentations != 0)
        ledger.answerWithDomain(.frame_presented, .harness, executed, self.window_presentations, true, .window_presentations, at);

    // Prerequisites are established before bounded-absence answers are
    // emitted. The old order answered future boundaries first and only
    // then recorded that their producers had not become reachable,
    // turning an ordinary ordering gap into a false harness claim.
    const swap_requested = ledger.record(.swap_request).answered();
    const pm4_consumed = ledger.record(.command_processor).answered();
    ledger.notePrerequisites(.swap_decode, swap_requested);
    ledger.notePrerequisites(.presenter_entry, swap_requested);
    ledger.notePrerequisites(.render_target, pm4_consumed);
    // A vblank callback does not require a PM4 packet. It becomes an
    // answerable route only after Xenia registered/attempted it or the
    // Rosette model actually queued a completion.
    ledger.notePrerequisites(
        .interrupt_dispatch,
        interrupt_dispatch_observed or title_interrupt_route_registered,
    );

    // Once guest execution or GPU activity has established a causal
    // frontier, Rosette can answer every boundary with an explicit
    // bounded absence when neither side supplied a positive answer. This
    // is not a fabricated ring write, PM4 packet, swap, callback, target,
    // or frame: it is the host's observation that the event count is zero
    // through this checkpoint. Keeping the negative claim explicit is what
    // distinguishes a known zero from the old `not-reached` hole.
    if (scope.checksArmed()) {
        var boundary_index: u8 = 0;
        while (boundary_index < substantiation.boundary_count) : (boundary_index += 1) {
            const boundary: substantiation.Boundary = @enumFromInt(boundary_index);
            const record = ledger.record(boundary);
            if (boundary.rosetteMayCloseAsAbsent(scope) and
                record.prerequisites_met and
                !record.harness.substantiates() and
                // Once either interrupt executor has actually observed a
                // dispatch, do not manufacture a negative answer. A mere
                // registration is intentionally not this guard: it is the
                // prerequisite that makes a bounded "not dispatched"
                // answer meaningful.
                !(boundary == .interrupt_dispatch and
                    interrupt_dispatch_observed))
            {
                ledger.answerAbsent(boundary, .harness, boundary.observationDomain(), at);
            }
        }
    }

    return ledger.evaluate(at);
}

pub fn logSubstantiation(self: anytype, summary: substantiation.Summary, force: bool) void {
    const fingerprint = self.substantiation.fingerprint();
    if (!force and fingerprint == self.substantiation_last_fingerprint and summary.clean()) return;
    self.substantiation_last_fingerprint = fingerprint;
    machoCapturePrint(
        "macho-processor: SUBSTANTIATION: schema={d} scope={s} armed={} elapsed={d} boundaries={d} answered={d} (application={d} harness={d} corroborated={d} bounded_negative={d} superseded_negative={d}) diverged={d} measurement_drift={d} unsubstantiated={d} (rosette_answerable={d}) not_reached={d} step={d}; {s}\n",
        .{
            substantiation.schema_version,
            summary.scope.label(),
            summary.scope_armed,
            summary.scope_elapsed_steps,
            substantiation.boundary_count,
            summary.answered,
            summary.by_application,
            summary.by_harness,
            summary.corroborated,
            summary.bounded_negative,
            summary.superseded_negative,
            summary.diverged,
            summary.measurement_drifts,
            summary.unsubstantiated,
            summary.unsubstantiated_answerable,
            summary.not_reached,
            self.executed_steps,
            summary.verdict(),
        },
    );
    var index: u8 = 0;
    while (index < substantiation.boundary_count) : (index += 1) {
        const boundary: substantiation.Boundary = @enumFromInt(index);
        const entry = self.substantiation.record(boundary);
        // A boundary somebody answered and nothing disagreed with is a
        // success and prints nothing.
        if (entry.settled() and summary.clean() and
            entry.application.substantiates() and
            entry.harness.substantiates() and
            entry.application.claim == .positive and
            entry.harness.claim == .positive)
            continue;
        machoCapturePrint(
            "  substantiation {s: <20} {s: <22} application={s: <9}({s: <8}) harness={s: <9}({s: <8}) first_answer_step={d} divergences={d} superseded_negatives={d}; {s}\n",
            .{
                boundary.label(),
                entry.finding.label(),
                entry.application.evidence.label(),
                entry.application.claim.label(),
                entry.harness.evidence.label(),
                entry.harness.claim.label(),
                entry.first_answer_step,
                entry.divergences,
                entry.superseded_negative_answers,
                boundary.question(),
            },
        );
    }
    if (summary.problem) |boundary| {
        const entry = self.substantiation.record(boundary);
        machoCapturePrint(
            "macho-processor: SUBSTANTIATION PROBLEM: boundary={s} finding={s} application={s}({s}) harness={s}({s}) application_value={d}({s}) harness_value={d}({s}) step={d}; {s}\n",
            .{
                boundary.label(),
                entry.finding.label(),
                entry.application.evidence.label(),
                entry.application.claim.label(),
                entry.harness.evidence.label(),
                entry.harness.claim.label(),
                entry.application.value,
                entry.application.value_domain.label(),
                entry.harness.value,
                entry.harness.value_domain.label(),
                self.executed_steps,
                entry.finding.meaning(),
            },
        );
    }
}

pub fn refreshTextureFormatSupport(self: anytype) void {
    if (!self.texture_formats.resolved) {
        var probed_any = false;
        for (gpu.texture_format_support.probed_formats) |format| {
            // All three fields, not just the tiling half. A format can be
            // unusable as an image and native as a vertex attribute, and
            // on this host exactly one of the probed formats is.
            const properties = self.dynamic_forwarder.presenterFormatProperties(format) orelse continue;
            self.texture_formats.noteSupportProperties(
                format,
                properties.linear_tiling_features,
                properties.optimal_tiling_features,
                properties.buffer_features,
            );
            probed_any = true;
        }
        if (!probed_any) return;
    }
    self.texture_format_summary = self.texture_formats.resolveAll(self.executed_steps);
    const fingerprint = self.texture_formats.fingerprint();
    if (fingerprint == self.texture_format_last_fingerprint) return;
    self.texture_format_last_fingerprint = fingerprint;
    self.logTextureFormatSupport();
}

pub fn logTextureFormatSupport(self: anytype) void {
    const T = gpu.texture_format_support;
    const summary = self.texture_format_summary;
    machoCapturePrint(
        "macho-processor: TEXTURE FORMAT SUPPORT: schema={d} probed={d}/{d} preferred={d} substituted={d} refused={d} reinterpreted={d} available_but_unused={d} step={d}; {s}\n",
        .{
            T.schema_version,
            summary.probed,
            T.probed_formats.len,
            summary.preferred,
            summary.substituted,
            summary.refused,
            summary.reinterpreted,
            summary.available_but_unused,
            self.executed_steps,
            summary.verdict(),
        },
    );
    for (self.texture_formats.support) |entry| {
        // An unprobed format is not an absent one, so it says which it is.
        machoCapturePrint(
            "  host-format {d: >4} usage={s: <12} sampled={s} probed={s} features(linear/optimal/buffer)=0x{x:0>8}/0x{x:0>8}/0x{x:0>8}; {s}\n",
            .{
                entry.format,
                entry.usage(),
                if (entry.sampled) "YES" else "NO",
                if (entry.probed) "YES" else "NO",
                entry.linear_features,
                entry.features,
                entry.buffer_features,
                entry.unavailability(),
            },
        );
    }
    var format_index: u8 = 0;
    while (format_index < T.format_count) : (format_index += 1) {
        const format: T.TextureFormat = @enumFromInt(format_index);
        for ([_]T.Signedness{ .unsigned, .signed }) |signedness| {
            const entry = self.texture_formats.record(format, signedness);
            // A guest format served by the host format it maps to directly
            // is a success and prints nothing.
            if (entry.plan.outcome == .preferred and !entry.emulator_reinterpreting) continue;
            machoCapturePrint(
                "  texture-format {s: <28} {s: <9} outcome={s: <12} host={d} preferred={d} fidelity={s: <18} loader_change={s} emulator_chose={d} loader={s} loader_verified={s} reinterpreting={s}; {s}\n",
                .{
                    format.label(),
                    signedness.label(),
                    entry.plan.outcome.label(),
                    entry.plan.host_format,
                    entry.plan.preferred_format,
                    entry.plan.fidelity.label(),
                    if (entry.plan.requiresLoaderChange()) "YES" else "NO",
                    entry.emulator_chose,
                    entry.emulator_loader.label(),
                    if (entry.emulator_loader_verified) "YES" else "NO",
                    if (entry.emulator_reinterpreting) "YES" else "NO",
                    entry.plan.note,
                },
            );
        }
    }
}

pub fn ringInspectionNeedsPreIntegrityScan(self: anytype) bool {
    if (self.gpu_ring_watch_base == 0 or self.gpu_ring_watch_size == 0) {
        return !self.gpu_ring_inspection_attempted;
    }
    return self.gpu_ring_last_inspected_base != self.gpu_ring_watch_base or
        self.gpu_ring_last_inspected_size != self.gpu_ring_watch_size;
}

pub fn refreshRunIntegrity(self: anytype) void {
    self.ensureRunIntegrity();
    // Ring projection is one of the integrity gate's reachable inputs. A
    // newly observed geometry must therefore be inspected before the gate
    // evaluates, rather than waiting for the later graphics-report
    // cadence. Otherwise the gate can truthfully see reachable ring work
    // with all of its probes still at zero and stop before the observer has
    // had a chance to run.
    if (self.ringInspectionNeedsPreIntegrityScan() and
        self.gpu_ring_last_inspection_step != self.executed_steps)
    {
        self.logRingContents();
    }
    // Pre-initialization ordering is a live integrity input, not a report
    // produced after the decision. Refresh the kernel-variable surface and
    // the cross-domain ledger before taking the immutable observation so a
    // callback dispatched at this checkpoint cannot hide behind the older
    // graphics report cadence.
    self.refreshKernelVariables();
    self.refreshPreinitialization();
    self.refreshWindowPresentations();
    // The handshake is judged before the gate reads it, so an integrity
    // violation and the boundary detail behind it describe the same
    // instant rather than adjacent checkpoints.
    self.substantiation_summary = self.refreshSubstantiation();
    self.logSubstantiation(self.substantiation_summary, false);
    self.refreshTextureFormatSupport();
    const observation = self.runIntegrityObservation();
    const summary = self.run_integrity.evaluate(observation);
    self.captureRunIntegrityContexts();
    const fingerprint = self.run_integrity.fingerprint();
    const changed = fingerprint != self.run_integrity_last_fingerprint;
    self.run_integrity_last_fingerprint = fingerprint;
    if (changed or !summary.clean()) self.logRunIntegrity(summary);
    if (self.run_integrity.shouldStop(summary)) self.faultOnRunIntegrity(summary);
}

pub fn captureRunIntegrityContexts(self: anytype) void {
    var index: u8 = 0;
    while (index < run_integrity.invariant_count) : (index += 1) {
        const invariant: run_integrity.Invariant = @enumFromInt(index);
        const record = self.run_integrity.record(invariant);
        if (record.has_armed_observation and
            !self.run_integrity_first_armed_context[index].valid)
        {
            self.run_integrity_first_armed_context[index] = .{
                .valid = true,
                .rip = self.regs.rip,
                .thread = self.active_guest_thread,
            };
        }
        if (record.has_first_violation_observation and
            !self.run_integrity_first_violation_context[index].valid)
        {
            self.run_integrity_first_violation_context[index] = .{
                .valid = true,
                .rip = self.regs.rip,
                .thread = self.active_guest_thread,
            };
        }
    }
}

pub fn logRunIntegrityTraceSnapshot(
    self: anytype,
    label: []const u8,
    observation: run_integrity.Observation,
) void {
    _ = self;
    machoCapturePrint(
        "    integrity-trace snapshot={s} step={d} liveness_scope={s} liveness_armed={} progress_since_park={} execution_frozen={} window(forwardings/unaccountable)={d}/{d} frames(presented/custody)={d}/{d} swap(reached/offered)={d}/{d}\n",
        .{
            label,
            observation.step,
            observation.liveness_scope.label(),
            observation.liveness_scope.notifierChecksArmed(),
            observation.progress_since_never_notified_park,
            observation.run_execution_frozen,
            observation.window_forwardings,
            observation.window_unaccountable,
            observation.frames_presented_to_window,
            observation.frames_in_custody,
            observation.swap_boundaries_reached,
            observation.swap_boundaries_offered,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} monotone-witness(closure/required/observed/corroborated/agreement-debt)={s}/{d}/{d}/{d}/{d}\n",
        .{
            label,
            if (observation.monotone_witness_closure_ready) "YES" else "NO",
            observation.monotone_witness_required,
            observation.monotone_witness_observed,
            observation.monotone_witness_corroborated,
            observation.monotone_witness_agreement_debt,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} output(presenter_ready/raw_draws/renderable_draws/target_state/target_output_ready/completion_signals/color_resolves/swap_boundaries/vdswap_encoded/opportunity/published/producer_quiet)={}/{}/{}/{}/{}/{}/{}/{}/{}/{}/{}/{} liveness(park_steps/wait_timeouts/waiters_without_notifier/actionable_without_notifier/obligation_proven/execution_frozen/progress_since_park/parks_without_reason)={}/{}/{}/{}/{}/{}/{}/{}\n",
        .{
            label,
            observation.presenter_ready,
            observation.draws_consumed,
            observation.renderable_draws_observed,
            observation.render_target_state_observed,
            observation.render_target_output_ready,
            observation.draw_completion_signals,
            observation.color_resolve_observations,
            observation.guest_swap_boundaries,
            observation.guest_vdswap_packets_encoded,
            observation.guest_output_opportunity_observed,
            observation.frames_published_by_any_producer,
            observation.producer_quiet_steps,
            observation.longest_never_notified_park_steps,
            observation.unsignalled_wait_timeouts,
            observation.waiters_without_a_notifier,
            observation.actionable_waiters_without_a_notifier,
            observation.liveness_obligation_proven,
            observation.run_execution_frozen,
            observation.progress_since_never_notified_park,
            observation.parks_without_a_reason,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} wait-evidence timeout-subject(object/handle/type/waits/signals/first_step/last_step)=0x{x}/0x{x}/{d}/{d}/{d}/{d}/{d} bounded-timeout(subjects/attempts/object/handle/ms/signals/first_step/last_step/notifier_proven/other_progress)={d}/{d}/0x{x}/0x{x}/{d}/{d}/{d}/{d}/{s}/{s} wait-graph(events/objects/stalled/cycles/insufficient/dropped)={d}/{d}/{d}/{d}/{d}/{d}\n",
        .{
            label,
            observation.unsignalled_wait_object,
            observation.unsignalled_wait_handle,
            observation.unsignalled_wait_type,
            observation.unsignalled_wait_waits,
            observation.unsignalled_wait_signals,
            observation.unsignalled_wait_first_step,
            observation.unsignalled_wait_last_step,
            observation.bounded_timeout_subjects,
            observation.bounded_timeout_attempts,
            observation.bounded_timeout_object,
            observation.bounded_timeout_handle,
            observation.bounded_timeout_ms,
            observation.bounded_timeout_signals,
            observation.bounded_timeout_first_step,
            observation.bounded_timeout_last_step,
            if (observation.bounded_timeout_notifier_proven) "YES" else "NO",
            if (observation.bounded_timeout_other_progress) "YES" else "NO",
            observation.wait_graph_events,
            observation.wait_graph_objects,
            observation.wait_graph_stalled_handshakes,
            observation.wait_graph_cycles,
            observation.wait_graph_insufficient,
            observation.wait_graph_dropped_objects,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} wait-blocker(object/waits/signals/waiter-thread/waiter-pc/signaller-thread/signaller-pc/first_step/last_step/participants-dropped)=0x{x}/{d}/{d}/0x{x}/0x{x}/0x{x}/0x{x}/{d}/{d}/{d}\n",
        .{
            label,
            observation.wait_graph_blocker_object,
            observation.wait_graph_blocker_waits,
            observation.wait_graph_blocker_signals,
            observation.wait_graph_blocker_waiter_thread,
            observation.wait_graph_blocker_waiter_pc,
            observation.wait_graph_blocker_signaller_thread,
            observation.wait_graph_blocker_signaller_pc,
            observation.wait_graph_blocker_first_step,
            observation.wait_graph_blocker_last_step,
            observation.wait_graph_blocker_participants_dropped,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} capabilities(exercised/unsatisfied/quiet_steps)={}/{}/{} progress(coverage/guest/witness)={}/{}/{} critical(total/satisfied/degraded/unsatisfied/untested)={}/{}/{}/{}/{} substitutions={d} anomalies={d} pause_transaction_defects={d} readiness(armed/essential_gaps)={}/{d}\n",
        .{
            label,
            observation.capabilities_exercised,
            observation.capabilities_unsatisfied,
            observation.capability_progress_quiet_steps,
            observation.capability_coverage_progress_step,
            observation.capability_guest_progress_step,
            observation.capability_progress_witness_step,
            observation.critical_capabilities_total,
            observation.critical_capabilities_satisfied,
            observation.critical_capabilities_degraded,
            observation.critical_capabilities_unsatisfied,
            observation.critical_capabilities_untested,
            observation.harness_substitutions,
            observation.recorded_anomalies,
            observation.pause_transaction_defects,
            observation.component_readiness_armed,
            observation.essential_component_gaps,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} translation(strict/cache_entries/vacant/conflict/cold/stale/flush)={s}/{d}/{d}/{d}/{d}/{d}/{d} lookups(hits/misses)={d}/{d}\n",
        .{
            label,
            if (observation.strict_fail_fast) "YES" else "NO",
            observation.translation_cache_entries,
            observation.translation_vacant_fills,
            observation.translation_conflict_fills,
            observation.translation_cold_evictions,
            observation.translation_stale_refills,
            observation.translation_flush_refills,
            observation.translation_hits,
            observation.translation_misses,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} budget(observed/deficit/guest_ms_per_host_s/required/host_s/guest_ms)={s}/{s}/{d}/{d}/{d}/{d} deadlock(observed/proven/finding/waiters/park_steps)={s}/{s}/{d}/{d}/{d}\n",
        .{
            label,
            if (observation.run_budget_observed) "YES" else "NO",
            if (observation.run_budget_deficit) "YES" else "NO",
            observation.run_budget_guest_ms_per_host_second,
            observation.run_budget_required_guest_ms_per_host_second,
            observation.run_budget_host_seconds,
            observation.run_budget_guest_ms,
            if (observation.deadlock_observed) "YES" else "NO",
            if (observation.deadlock_proven) "YES" else "NO",
            observation.deadlock_finding,
            observation.deadlock_waiters,
            observation.deadlock_park_steps,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} ownership={d} substantiation(armed/unsubstantiated/diverged/measurement_drift)={}/{}/{}/{} texture(probed/reinterpreted)={}/{}\n",
        .{
            label,
            observation.ownership_violations,
            observation.substantiation_armed,
            observation.unsubstantiated_boundaries,
            observation.diverged_boundaries,
            observation.measurement_drift_boundaries,
            observation.texture_formats_probed,
            observation.reinterpreted_texture_formats,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} frame-provenance(authentic/host/diagnostic/guest-forwarded-present-requests/native-gpu-completions/custody)={d}/{d}/{d}/{d}/{d}/{d}\n",
        .{
            label,
            observation.authentic_frames_presented,
            observation.host_frames_presented,
            observation.diagnostic_frames_presented,
            observation.native_present_requests,
            observation.native_gpu_completions,
            observation.frames_in_custody,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} presenter(attempted/nonretryable-failures)={s}/{d} provisioning(armed/raw-refusals/actionable/late/diverged/contested/unprovisioned)={s}/{d}/{d}/{d}/{d}/{d}/{d} wait-policy(observed/faults)={s}/{d} profile(samples/readable/decisive/unclassified/unresolved)={d}/{s}/{s}/{d}/{d}\n",
        .{
            label,
            if (observation.presenter_attempted) "YES" else "NO",
            observation.presenter_nonretryable_failures,
            if (observation.provisioning_armed) "YES" else "NO",
            observation.provisioning_raw_refusals,
            observation.provisioning_actionable_refusals,
            observation.provisioning_late,
            observation.provisioning_diverged,
            observation.provisioning_contested,
            observation.provisioning_unprovisioned,
            if (observation.wait_policy_observed) "YES" else "NO",
            observation.wait_policy_faults,
            observation.execution_profile_samples,
            if (observation.execution_profile_readable) "YES" else "NO",
            if (observation.execution_profile_decisive) "YES" else "NO",
            observation.execution_profile_unclassified,
            observation.execution_profile_unresolved,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} mandatory-order(armed/active/held/raced/violated/mandatory-violations)={s}/{d}/{d}/{d}/{d}/{d}\n",
        .{
            label,
            if (observation.mandatory_order_armed) "YES" else "NO",
            observation.mandatory_order_active,
            observation.mandatory_order_active -|
                observation.mandatory_order_violated -|
                observation.mandatory_order_raced,
            observation.mandatory_order_raced,
            observation.mandatory_order_violated,
            observation.mandatory_order_mandatory_violations,
        },
    );
    machoCapturePrint(
        "    integrity-trace snapshot={s} pm4-live(packets-observed/executed/defects)={d}/{d}/{d} packet(errors/invalid/unknown/truncated)={d}/{d}/{d}/{d} indirect(unreadable/truncated/invalid/depth/budget/cycles)={d}/{d}/{d}/{d}/{d}/{d} registers(unclassified/out-of-range)={d}/{d}\n",
        .{
            label,
            observation.pm4_packets_observed,
            observation.pm4_packets_executed,
            observation.pm4_defects,
            observation.pm4_packet_errors,
            observation.pm4_invalid_packets,
            observation.pm4_unknown_opcodes,
            observation.pm4_truncated_rings,
            observation.pm4_indirect_unreadable,
            observation.pm4_indirect_truncated,
            observation.pm4_indirect_invalid,
            observation.pm4_indirect_depth_limited,
            observation.pm4_indirect_budget_limited,
            observation.pm4_indirect_cycles,
            observation.pm4_unclassified_register_writes,
            observation.pm4_out_of_range_register_writes,
        },
    );
}

pub fn logRunIntegrityPm4Evidence(self: anytype) void {
    const evidence = self.gpu_xenos_runtime.runtimeEvidence();
    const first_defect = if (evidence.firstDefect()) |defect| defect.label() else "<none>";
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY PM4: source=live-xenos-runtime retained-excluded=YES verdict={s} first_defect={s} packets(observed/executed)={d}/{d} defects={d} packet(errors/invalid/unknown/truncated)={d}/{d}/{d}/{d} indirect(unreadable/truncated/invalid/depth/budget/cycles)={d}/{d}/{d}/{d}/{d}/{d} registers(unclassified/out_of_range)={d}/{d}; live execution is the only input to no-unverified-pm4-input\n",
        .{
            evidence.verdict().label(),
            first_defect,
            evidence.packets_observed,
            evidence.packets_executed,
            evidence.defectCount(),
            evidence.packet_errors,
            evidence.invalid_packets,
            evidence.unknown_opcodes,
            evidence.truncated_rings,
            evidence.indirect_unreadable,
            evidence.indirect_truncated,
            evidence.indirect_invalid,
            evidence.indirect_depth_limited,
            evidence.indirect_budget_limited,
            evidence.indirect_cycles,
            evidence.unclassified_register_writes,
            evidence.out_of_range_register_writes,
        },
    );
}

pub fn logRunIntegrityCapabilityCauses(self: anytype, invariant: run_integrity.Invariant) void {
    const ledger = &self.host_coverage;
    inline for (@typeInfo(host_contract_coverage.Capability).@"enum".fields) |field| {
        const capability: host_contract_coverage.Capability = @enumFromInt(field.value);
        const status = ledger.status(capability);
        const relevant = switch (invariant) {
            .no_unsatisfied_capability => status == .unsatisfied,
            .all_critical_capabilities_proven => capability.weight() == .critical and status != .satisfied,
            .no_degraded_critical_capability => capability.weight() == .critical and status == .degraded,
            else => false,
        };
        if (relevant) {
            const entry = ledger.entry(capability);
            machoCapturePrint(
                "    integrity-trace capability={s} status={s} layer={s} weight={s} note={s}\n",
                .{
                    capability.label(),
                    status.label(),
                    capability.layer().label(),
                    capability.weight().label(),
                    entry.note(),
                },
            );
        }
    }
}

pub fn logRunIntegrityPresenterCause(self: anytype) void {
    const presenter = &self.dynamic_forwarder.native_presenter;
    const report = &presenter.report;
    const frame = &presenter.last_frame;
    machoCapturePrint(
        "    integrity-trace presenter stage={s} retryable={} VkResult={d} rejection={s} adapter={s} api=0x{x} attempts={d} swapchain_generations={d} surface_recreations={d}\n",
        .{
            @tagName(presenter.stage),
            presenter.stage.retryable(),
            report.last_result,
            report.rejectionLabel(),
            if (report.adapter_name_length != 0) report.adapterName() else "<unselected>",
            report.api_version,
            self.dynamic_forwarder.native_presenter_attempts,
            report.swapchain_generations,
            report.surface_recreations,
        },
    );
    machoCapturePrint(
        "    integrity-trace presenter last-frame(attempted/slot/image/acquire/submit/present/request-accepted/gpu-completed/completion/health/provenance)={s}/{d}/{d}/{d}/{d}/{d}/{s}/{s}/{d}/{s}/{s}; retryable surface backpressure is not a terminal presenter failure\n",
        .{
            if (frame.attempted) "YES" else "NO",
            frame.frame_slot,
            frame.image_index,
            frame.acquire_result,
            frame.submit_result,
            frame.present_result,
            if (frame.present_request_accepted) "YES" else "NO",
            if (frame.hardware_completed) "YES" else "NO",
            frame.hardware_completion_result,
            @tagName(frame.health),
            frame.classification.label(),
        },
    );
}

pub fn logRunIntegrityProfileGaps(self: anytype) void {
    const profile = &self.startup.profile;
    const totals = profile.summary();
    machoCapturePrint(
        "    integrity-trace profile gaps samples={d} readable={} decisive={} unclassified={d} unresolved={d}\n",
        .{
            totals.samples,
            totals.readable(),
            totals.dominantIsDecisive(),
            totals.by_region[@intFromEnum(diagnostics_execution_profile.Region.unclassified)],
            totals.by_region[@intFromEnum(diagnostics_execution_profile.Region.unresolved_symbol)],
        },
    );
    var shown: usize = 0;
    for (profile.retained()) |entry| {
        if (entry.region != .unclassified and entry.region != .unresolved_symbol) continue;
        machoCapturePrint(
            "    integrity-trace profile gap region={s} samples={d} witness_rip=0x{x} first_step={d} last_step={d} symbol={s}\n",
            .{
                entry.region.label(),
                entry.samples,
                entry.witness_rip,
                entry.first_step,
                entry.last_step,
                entry.name,
            },
        );
        shown += 1;
        if (shown == 8) break;
    }
}

pub fn logRunIntegrityWitnessCorroboration(self: anytype) void {
    const ledger = &self.monotone_witness;
    const totals = ledger.summary();
    machoCapturePrint(
        "    integrity-trace monotone-witness closure=NO required/observed/corroborated/agreement-debt={d}/{d}/{d}/{d}; every required subject must be exactly corroborated before a closed graphics conclusion\n",
        .{
            monotone_witness.required_subject_count,
            totals.required_observed,
            totals.required_corroborated,
            totals.required_agreement_debt,
        },
    );

    const subjects = [_]monotone_witness.Subject{
        .title_interrupt_callback_entries,
        .title_interrupt_callback_returns,
        .graphics_interrupt_dispatches,
        .vblank_marks,
        .pm4_packets_consumed,
        .draws_issued,
        .render_target_updates,
        .register_writes,
        .ring_write_pointer_advances,
    };
    for (subjects) |subject| {
        const result = ledger.reconcile(subject);
        machoCapturePrint(
            "      integrity-trace witness subject={s} finding={s} witnesses={d} floor={d} floor_by={s} floor_step={d} short={s} short_count={d} short_step={d} quiet={d}; {s}\n",
            .{
                subject.label(),
                result.finding.label(),
                result.witnesses,
                result.floor,
                if (result.floor_witness) |which| which.label() else "-",
                result.floor_step,
                if (result.short_witness) |which| which.label() else "-",
                result.short_count,
                result.short_step,
                result.short_quiet_steps,
                result.finding.guidance(),
            },
        );
    }
}

pub fn logRunIntegrityUnprobedStages(self: anytype) void {
    const ledger = &self.gpu_vd_swap_contract;
    const mask = ledger.observed_mask;
    machoCapturePrint(
        "    integrity-trace unprobed stages attempt_floor={d} required_floor={d}\n",
        .{ ledger.probes.maxAttempts(), run_integrity.vd_swap_probe_floor },
    );
    var shown: usize = 0;
    inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
        const stage: gpu.VdSwapStage = @enumFromInt(field.value);
        const diagnosis = ledger.probes.diagnose(stage, mask);
        if (diagnosis.attribution == .unprobed and shown < 6) {
            machoCapturePrint(
                "    integrity-trace unprobed stage={s} chain={s} owner={s} probes={d}/{d} prerequisites=met\n",
                .{
                    stage.label(),
                    diagnosis.chain.label(),
                    stage.owner().label(),
                    diagnosis.probes_attempted,
                    diagnosis.probes_total,
                },
            );
            for (gpu.vd_swap_contract.probesFor(stage)) |probe| {
                const cell = ledger.probes.cell(stage, probe);
                machoCapturePrint(
                    "      integrity-trace unprobed probe={s} attempts={d} outcome={s} first_step={d} last_step={d}\n",
                    .{ probe.label(), cell.attempts, @tagName(cell.outcome), cell.first_step, cell.last_step },
                );
            }
            shown += 1;
        }
    }
}

pub fn logRunIntegrityClosableStarvations(self: anytype) void {
    const ledger = &self.gpu_vd_swap_contract;
    var shown: usize = 0;
    inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
        const stage: gpu.VdSwapStage = @enumFromInt(field.value);
        const diagnosis = ledger.diagnose(stage);
        if (diagnosis.attribution == .starved and
            diagnosis.starvation_cause.closableByRosette() and
            shown < 6)
        {
            machoCapturePrint(
                "    integrity-trace closable-starvation stage={s} chain={s} owner={s} cause={s} decided_by={s} probes(attempted/total/starved)={d}/{d}/{d}; {s}\n",
                .{
                    stage.label(),
                    diagnosis.chain.label(),
                    stage.owner().label(),
                    diagnosis.starvation_cause.label(),
                    if (diagnosis.decided_by) |which| which.label() else "<none>",
                    diagnosis.probes_attempted,
                    diagnosis.probes_total,
                    diagnosis.probes_starved,
                    diagnosis.starvation_cause.remedy(),
                },
            );
            shown += 1;
        }
    }
}

pub fn logRunIntegrityContestedClaims(self: anytype) void {
    const ledger = &self.claim_reconciliation;
    var shown: usize = 0;
    inline for (@typeInfo(claim_reconciliation.Claim).@"enum".fields) |field| {
        const claim: claim_reconciliation.Claim = @enumFromInt(field.value);
        const result = ledger.reconcile(claim);
        if (result.agreement == .contested and shown < 8) {
            machoCapturePrint(
                "    integrity-trace contested-claim {s} observers={d} current={s}=0x{x} (step {d}) losing={s}=0x{x} (step {d}) crosses_sides={s}; {s}\n",
                .{
                    claim.label(),
                    result.observers,
                    if (result.current_source) |which| which.label() else "<none>",
                    result.current_value,
                    result.current_step,
                    if (result.losing_source) |which| which.label() else "<none>",
                    result.losing_value,
                    result.losing_step,
                    if (result.crosses_sides) "YES" else "NO",
                    result.agreement.guidance(),
                },
            );
            shown += 1;
        }
    }
}

pub fn logRunIntegrityBudgetCause(self: anytype) void {
    const totals = self.runBudgetGuestWindowSummary();
    const verdict = self.runBudgetGuestWindowVerdict(totals);
    machoCapturePrint(
        "    integrity-trace budget verdict={s} observed_host_seconds={d} observed_guest_ms={d} guest_ms_per_host_s={d} required={d} observer_percent={d} dominant_phase={s}; {s}\n",
        .{
            verdict.label(),
            totals.host_ns / std.time.ns_per_s,
            totals.guest_ms,
            totals.guestMsPerHostSecond(),
            self.audit_budget.required_guest_ms_per_host_second,
            totals.observerPercent(),
            if (totals.dominantPhase()) |phase| phase.label() else "-",
            verdict.describe(),
        },
    );
    var phase_index: usize = 0;
    while (phase_index < run_budget.phase_count) : (phase_index += 1) {
        const phase: run_budget.Phase = @enumFromInt(phase_index);
        const host_ns = totals.by_phase[phase_index];
        if (host_ns != 0) {
            machoCapturePrint(
                "    integrity-trace budget phase={s} host_seconds={d} host_ns={d}\n",
                .{ phase.label(), host_ns / std.time.ns_per_s, host_ns },
            );
        }
    }
}

pub fn logRunIntegrityViolationTrace(self: anytype, summary: run_integrity.Summary) void {
    var changed_count: usize = 0;
    var index: u8 = 0;
    while (index < run_integrity.invariant_count) : (index += 1) {
        const entry = self.run_integrity.record(@enumFromInt(index));
        if (entry.state == .violated and entry.last_transition.tracesViolation())
            changed_count += 1;
    }
    if (changed_count == 0) return;

    machoCapturePrint(
        "macho-processor: RUN INTEGRITY VIOLATION TRACE: schema={d} step={d} newly_changed={d} current_violations={d} selected_stop={s}; first predicate inputs, causal capability status and execution context follow\n",
        .{
            run_integrity.schema_version,
            self.executed_steps,
            changed_count,
            summary.violated,
            if (summary.stop_at) |invariant| invariant.label() else "<none>",
        },
    );

    index = 0;
    var wait_graph_logged = false;
    while (index < run_integrity.invariant_count) : (index += 1) {
        const invariant: run_integrity.Invariant = @enumFromInt(index);
        const entry = self.run_integrity.record(invariant);
        if (entry.state != .violated or !entry.last_transition.tracesViolation()) continue;

        if (!wait_graph_logged and
            (invariant == .no_stalled_wait_handshake or
                invariant == .wait_receives_signals or
                invariant == .no_actionable_wait_policy_fault))
        {
            // The integrity checkpoint runs before the normal graphics
            // report. Emit the graph here as part of the causal fault block
            // so a strict stop cannot lose the waiter/signaller PCs that
            // explain the aggregate liveness counter.
            self.logWaitAudit();
            self.logWaitGraph();
            wait_graph_logged = true;
        }

        const first_observation = if (entry.has_first_violation_observation)
            entry.first_violation_observation
        else
            self.run_integrity.last_observation;
        const first_armed_observation = if (entry.has_armed_observation)
            entry.first_armed_observation
        else
            first_observation;
        const armed_context = self.run_integrity_first_armed_context[index];
        const violation_context = self.run_integrity_first_violation_context[index];
        machoCapturePrint(
            "  integrity-trace invariant={s} transition={s} state={s} owner={s} subowner={s} class={s} allowed={} gate={s}\n",
            .{
                invariant.label(),
                entry.last_transition.label(),
                entry.state.label(),
                ownership_contract.root_owner,
                invariant.owner().label(),
                invariant.class().label(),
                entry.allowlistApplies(invariant),
                run_integrity.traceGate(invariant),
            },
        );
        machoCapturePrint(
            "    integrity-trace cause(first/current)={s} / {s} detail(first/current)={d}/{d} armed_step={d} first_violation_step={d} first_detail={d} violations={d} context(armed_rip/armed_thread/violation_rip/violation_thread/current_rip/current_thread)=0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}; remedy={s}\n",
            .{
                run_integrity.traceCause(invariant, first_observation),
                run_integrity.traceCause(invariant, self.run_integrity.last_observation),
                entry.first_violation_detail,
                entry.detail,
                entry.armed_step,
                entry.first_violation_step,
                entry.first_violation_detail,
                entry.violations,
                armed_context.rip,
                armed_context.thread,
                violation_context.rip,
                violation_context.thread,
                self.regs.rip,
                self.active_guest_thread,
                invariant.remedy(),
            },
        );
        if (invariant == .no_gpu_preinitialization_order_inversion) {
            // The pre-initialization ledger retains the exact dependent,
            // prerequisite and first step. Emit it inside the causal block
            // so the hard stop cannot leave the ordering inversion buried
            // in a later checkpoint's general graphics report.
            self.logPreinitialization();
        }
        if (invariant == .no_actionable_provisioning_refusal) {
            // Custody owns the per-resource refusal, owner and consumer
            // details. Emit it in the causal block so a strict stop does
            // not leave the raw refusal total detached from its resource.
            self.logProvisioningCustody();
        }
        if (invariant == .no_presenter_failure) {
            self.logRunIntegrityPresenterCause();
        }
        if (invariant == .no_unclassified_execution_profile) {
            self.logRunIntegrityProfileGaps();
        }
        if (invariant == .all_required_witnesses_corroborated) {
            self.logRunIntegrityWitnessCorroboration();
        }
        if (invariant == .no_unprobed_reachable_stage) {
            self.logRunIntegrityUnprobedStages();
        }
        if (invariant == .no_rosette_closable_starvation) {
            self.logRunIntegrityClosableStarvations();
        }
        if (invariant == .no_contested_claim) {
            self.logRunIntegrityContestedClaims();
        }
        if (invariant == .no_settled_unknown_mapping) {
            // Reprint the inventory unconditionally on the stop: the
            // collapse-on-unchanged-total rule that keeps it quiet during a
            // run is exactly what would hide it at the moment it matters.
            self.unknown_inventory_last_total = 0;
            self.logUnknownInventory();
        }
        if (invariant == .no_run_budget_deficit) {
            self.logRunIntegrityBudgetCause();
        }
        if (invariant == .no_proven_deadlock) {
            self.logDeadlockPredictor();
        }
        if (invariant == .no_invalid_application_controller_decision) {
            self.logApplicationControllerContractViolation();
        }
        if (invariant == .no_unproven_essential_component) {
            // Readiness owns the component, first-use step and proof
            // obligation. Emit it in the causal block so the fatal stop
            // cannot leave an essential gap as an unexplained percentage.
            self.logComponentReadiness();
        }
        self.logRunIntegrityTraceSnapshot("first-armed", first_armed_observation);
        self.logRunIntegrityTraceSnapshot("first-violation", first_observation);
        if (entry.last_transition == .changed or
            first_observation.step != self.run_integrity.last_observation.step)
        {
            self.logRunIntegrityTraceSnapshot("current", self.run_integrity.last_observation);
        }
        self.logRunIntegrityCapabilityCauses(invariant);
    }
}

pub fn logApplicationControllerContractViolation(self: anytype) void {
    const violation = self.application_controller.last_contract_violation orelse return;
    const decision = self.application_controller.last_contract_violation_decision;
    const sample = self.application_controller.last_contract_violation_sample;
    machoCapturePrint(
        "    integrity-trace application-controller violation={s} decision(phase/action/blocker/secondary/domain/authorized/step)={s}/{s}/{s}/{s}/{s}/{}/{d} sample(guest-vdswap/guest-output/authentic-swap/presenter-ready/interrupt-callback/powerpc-callback/target-state/target-memory/pending/signaled/dispatched)={}/{}/{}/{}/{}/{}/{}/{}/{d}/{d}/{d}\n",
        .{
            violation.label(),
            decision.phase.label(),
            decision.action.label(),
            decision.blocker.label(),
            decision.secondary_blocker.label(),
            decision.domain.label(),
            decision.host_action_authorized,
            decision.step,
            sample.guest_vdswap_entered,
            sample.guest_output_available,
            sample.authentic_swap_consumed,
            sample.presenter_ready,
            sample.interrupt_callback_registered,
            sample.powerpc_callback_registered,
            sample.render_target_state_observed,
            sample.render_target_memory_observed,
            sample.pending_gpu_interrupts,
            sample.draw_completion_signaled,
            sample.draw_completion_dispatched,
        },
    );
}

pub fn logRunIntegrity(self: anytype, summary: run_integrity.Summary) void {
    const observation = self.run_integrity.last_observation;
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY: owner={s} subowner={s} policy={s} armed={d} satisfied={d} violated={d} unarmed={d} allowed={d} regressions={d} of {d} step={d} capability_progress(coverage/guest/witness/quiet)={d}/{d}/{d}/{d} critical(total/satisfied/degraded/unsatisfied/untested)={d}/{d}/{d}/{d}/{d} order(active/held/raced/violated/mandatory)={d}/{d}/{d}/{d}/{d} preinit(inversions/dropped)={d}/{d} readiness(armed/essential_gaps)={}/{d}\n",
        .{
            ownership_contract.root_owner,
            "rosette:harness",
            self.run_integrity.policy.label(),
            summary.armed,
            summary.satisfied,
            summary.violated,
            summary.unarmed,
            summary.allowed,
            summary.regressions,
            run_integrity.invariant_count,
            self.executed_steps,
            observation.capability_coverage_progress_step,
            observation.capability_guest_progress_step,
            observation.capability_progress_witness_step,
            observation.capability_progress_quiet_steps,
            observation.critical_capabilities_total,
            observation.critical_capabilities_satisfied,
            observation.critical_capabilities_degraded,
            observation.critical_capabilities_unsatisfied,
            observation.critical_capabilities_untested,
            observation.mandatory_order_active,
            observation.mandatory_order_active -|
                observation.mandatory_order_violated -|
                observation.mandatory_order_raced,
            observation.mandatory_order_raced,
            observation.mandatory_order_violated,
            observation.mandatory_order_mandatory_violations,
            observation.gpu_preinitialization_inversions,
            observation.gpu_preinitialization_inversions_dropped,
            observation.component_readiness_armed,
            observation.essential_component_gaps,
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY LIVENESS: scope={s} armed={} waiters_without_notifier={d} actionable={d} obligation_proven={} execution_frozen={}; verdict={s}\n",
        .{
            observation.liveness_scope.label(),
            observation.liveness_scope.notifierChecksArmed(),
            observation.waiters_without_a_notifier,
            observation.actionable_waiters_without_a_notifier,
            observation.liveness_obligation_proven,
            observation.run_execution_frozen,
            summary.verdict(),
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY PRESENTER: attempted={} stage={s} retryable={} nonretryable_failures={d}; diagnostic-only frames prove the Cocoa sink, not guest output, and do not degrade native_present_completed\n",
        .{
            observation.presenter_attempted,
            @tagName(self.dynamic_forwarder.nativePresenterStage()),
            self.dynamic_forwarder.nativePresenterStage().retryable(),
            observation.presenter_nonretryable_failures,
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY PROVISIONING: armed={} raw_refusals={d} actionable_storage_refusals={d} custody_failures(late/diverged/contested/unprovisioned)={d}/{d}/{d}/{d}; owner-rule refusals remain diagnostic until they leave an actionable custody state\n",
        .{
            observation.provisioning_armed,
            observation.provisioning_raw_refusals,
            observation.provisioning_actionable_refusals,
            observation.provisioning_late,
            observation.provisioning_diverged,
            observation.provisioning_contested,
            observation.provisioning_unprovisioned,
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY APPLICATION CONTROLLER: decisions={d} contract_violations={d}; guest-boundary observations are not refusals, and an invalid host authorization/evidence pairing is non-bypassable\n",
        .{
            observation.application_controller_decisions,
            observation.application_controller_contract_violations,
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY WAIT POLICY: observed={} faults={d}; guest_synthetic_wake=REFUSED is a protection decision, while only requires_fault is fatal\n",
        .{ observation.wait_policy_observed, observation.wait_policy_faults },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY PROFILE: samples={d} readable={} decisive={} classifier_debt(unclassified/unresolved)={d}/{d}; startup profiles below the evidence threshold remain unarmed\n",
        .{
            observation.execution_profile_samples,
            observation.execution_profile_readable,
            observation.execution_profile_decisive,
            observation.execution_profile_unclassified,
            observation.execution_profile_unresolved,
        },
    );
    const deadlock_finding: deadlock_predictor.Finding = @enumFromInt(observation.deadlock_finding);
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY BUDGET: observed={} deficit={} guest_ms_per_host_s={d} required={d} host_seconds={d} guest_ms={d}; the deficit gate excludes the startup settling window and stops only a measured BELOW-BUDGET reachability failure\n",
        .{
            observation.run_budget_observed,
            observation.run_budget_deficit,
            observation.run_budget_guest_ms_per_host_second,
            observation.run_budget_required_guest_ms_per_host_second,
            observation.run_budget_host_seconds,
            observation.run_budget_guest_ms,
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY DEADLOCK: observed={} proven={} finding={s} waiters={d} longest_park_steps={d}; NEVER_NOTIFIED remains diagnostic until a causal obligation or fully frozen run exists, while all-notifiers-parked, producer-terminated and mature WAIT_CYCLE findings are fatal\n",
        .{
            observation.deadlock_observed,
            observation.deadlock_proven,
            deadlock_finding.label(),
            observation.deadlock_waiters,
            observation.deadlock_park_steps,
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY POLICY: strict_fail_fast={} anomaly_ledger_records={d} pause_transaction_defects={d}; fault mode stops on the first avoidable cache miss or other proven defect, warn exposes it without stopping, and observe retains the settling-window policy\n",
        .{
            self.run_integrity_strict,
            observation.recorded_anomalies,
            observation.pause_transaction_defects,
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY READINESS: armed={} essential_gaps={d}; an essential component used before proof or marked broken is non-bypassable, while unused unproven components remain diagnostic\n",
        .{ observation.component_readiness_armed, observation.essential_component_gaps },
    );
    if (observation.mandatory_order_armed) {
        machoCapturePrint(
            "macho-processor: RUN INTEGRITY ORDER: armed={s} active={d} violated={d} mandatory_violations={d} raced={d}; raw draw/callback/diagnostic counters are context only, and the order ledger is the authority for cross-domain prerequisites\n",
            .{
                if (observation.mandatory_order_armed) "YES" else "NO",
                observation.mandatory_order_active,
                observation.mandatory_order_violated,
                observation.mandatory_order_mandatory_violations,
                observation.mandatory_order_raced,
            },
        );
    }
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY WAIT EVIDENCE: graph(events/objects/stalled/cycles/insufficient/dropped)={d}/{d}/{d}/{d}/{d}/{d} timeout-subject(object/handle/type/waits/timeouts/signals/first_step/last_step)=0x{x}/0x{x}/{d}/{d}/{d}/{d}/{d}/{d} bounded-timeout(subjects/attempts/object/handle/ms/signals/first_step/last_step/notifier_proven/other_progress)={d}/{d}/0x{x}/0x{x}/{d}/{d}/{d}/{d}/{s}/{s}; a finite poll can arm the fatal notifier invariant only when the exact sync object has a classified causal notifier and no independent progress advanced during the interval\n",
        .{
            observation.wait_graph_events,
            observation.wait_graph_objects,
            observation.wait_graph_stalled_handshakes,
            observation.wait_graph_cycles,
            observation.wait_graph_insufficient,
            observation.wait_graph_dropped_objects,
            observation.unsignalled_wait_object,
            observation.unsignalled_wait_handle,
            observation.unsignalled_wait_type,
            observation.unsignalled_wait_waits,
            observation.unsignalled_wait_timeouts,
            observation.unsignalled_wait_signals,
            observation.unsignalled_wait_first_step,
            observation.unsignalled_wait_last_step,
            observation.bounded_timeout_subjects,
            observation.bounded_timeout_attempts,
            observation.bounded_timeout_object,
            observation.bounded_timeout_handle,
            observation.bounded_timeout_ms,
            observation.bounded_timeout_signals,
            observation.bounded_timeout_first_step,
            observation.bounded_timeout_last_step,
            if (observation.bounded_timeout_notifier_proven) "YES" else "NO",
            if (observation.bounded_timeout_other_progress) "YES" else "NO",
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY WAIT BLOCKER: object=0x{x} waits={d} signals={d} waiter(thread/pc)=0x{x}/0x{x} signaller(thread/pc)=0x{x}/0x{x} interval(first/last)={d}/{d} participants_dropped={d}; selected from the wait graph and intentionally kept separate from the timeout subject\n",
        .{
            observation.wait_graph_blocker_object,
            observation.wait_graph_blocker_waits,
            observation.wait_graph_blocker_signals,
            observation.wait_graph_blocker_waiter_thread,
            observation.wait_graph_blocker_waiter_pc,
            observation.wait_graph_blocker_signaller_thread,
            observation.wait_graph_blocker_signaller_pc,
            observation.wait_graph_blocker_first_step,
            observation.wait_graph_blocker_last_step,
            observation.wait_graph_blocker_participants_dropped,
        },
    );
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY FRAME EVIDENCE: completed(authentic/host/diagnostic)={d}/{d}/{d} guest-forwarded-present-requests={d} native-gpu-completions={d} custody={d}; a Vulkan present request is not a completed guest frame and a diagnostic Metal clear is not guest output. This counts only presents the *guest* asked for and Rosette forwarded to the real driver; PRESENTATION PROVENANCE counts every native present request from any producer, so the two differ by Rosette's own diagnostic presents and neither is undercounting\n",
        .{
            observation.authentic_frames_presented,
            observation.host_frames_presented,
            observation.diagnostic_frames_presented,
            observation.native_present_requests,
            observation.native_gpu_completions,
            observation.frames_in_custody,
        },
    );
    self.logRunIntegrityPm4Evidence();
    if (observation.waiters_without_a_notifier != 0 and
        observation.actionable_waiters_without_a_notifier == 0)
    {
        machoCapturePrint(
            "macho-processor: RUN INTEGRITY LIVENESS: raw host waiters_without_notifier={d} retained diagnostically, but no causal notifier obligation was proven; execution_frozen={} progress_since_park={}; the fatal notifier invariants remain unarmed. Guest wait graph/classified sync evidence or a fully frozen run is required\n",
            .{
                observation.waiters_without_a_notifier,
                observation.run_execution_frozen,
                observation.progress_since_never_notified_park,
            },
        );
    }
    // Keep the translation evidence beside the terminal integrity report.
    // A run can stop on an emulator anomaly after the last full graphics
    // frontier report, and without this compact snapshot a reader could
    // mistake the last visible economics line for the cause of the stop.
    const translation_totals = self.translation_economics.summary();
    const translation_lookups = self.decode_cache_hits +| self.decode_cache_misses;
    const translation_hit_rate: u64 = if (translation_lookups == 0)
        0
    else
        @intCast((@as(u128, self.decode_cache_hits) * 100) / translation_lookups);
    const translation_record = self.run_integrity.record(.translation_cache_converges);
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY TRANSLATION: gate={s} verdict={s} fills={d} causes(vacant/conflict/cold/stale/flush)={d}/{d}/{d}/{d}/{d} hit_rate={d}% static_l2(hits/fills)={d}/{d} sampled_pages={d} unsampled_events={d} sample_complete={s}; {s}\n",
        .{
            translation_record.state.label(),
            translation_totals.verdict().label(),
            translation_totals.decodes,
            translation_totals.vacant_fills,
            translation_totals.conflict_fills,
            translation_totals.cold_evictions,
            translation_totals.stale_refills,
            translation_totals.flush_refills,
            translation_hit_rate,
            self.static_decode_l2_hits,
            self.static_decode_l2_fills,
            translation_totals.sampled_pages,
            translation_totals.unsampled_events,
            if (translation_totals.sampleComplete()) "YES" else "NO",
            translation_totals.verdict().guidance(),
        },
    );
    if (observation.mandatory_order_mandatory_violations != 0) {
        // The order ledger owns the bounded lead-up and domain-specific
        // event identities. Emit it before the generic integrity trace so
        // a strict SIGSEGV always leaves the exact ordering evidence in
        // the retained runtime log.
        self.logMandatoryOrder();
    }
    self.logRunIntegrityViolationTrace(summary);
    var index: u8 = 0;
    while (index < run_integrity.invariant_count) : (index += 1) {
        const invariant: run_integrity.Invariant = @enumFromInt(index);
        const entry = self.run_integrity.record(invariant);
        // A satisfied invariant is a success and prints nothing. An unarmed
        // one prints only while something is wrong, because "nothing has
        // looked at this yet" is context for a violation and noise without
        // one.
        if (entry.state == .satisfied) continue;
        if (entry.state == .not_armed and summary.violated == 0) continue;
        machoCapturePrint(
            "  integrity {s: <32} {s: <10} owner={s} subowner={s: <16} invariant_owner={s: <16} class={s: <13} detail={d} armed_step={d} first_violation_step={d} violations={d}{s}\n",
            .{
                invariant.label(),
                entry.state.label(),
                ownership_contract.root_owner,
                invariant.owner().label(),
                invariant.owner().label(),
                invariant.class().label(),
                entry.detail,
                entry.armed_step,
                entry.first_violation_step,
                entry.violations,
                if (entry.allowlistApplies(invariant))
                    " ALLOWED"
                else if (entry.allowed and invariant.nonBypassable())
                    " NON_BYPASSABLE"
                else
                    "",
            },
        );
    }
    if (summary.stop_at) |invariant| {
        machoCapturePrint(
            "macho-processor: RUN INTEGRITY STOP: invariant={s} owner={s} subowner={s} invariant_owner={s} class={s} detail={d} step={d}; {s}\n",
            .{
                invariant.label(),
                ownership_contract.root_owner,
                invariant.owner().label(),
                invariant.owner().label(),
                invariant.class().label(),
                self.run_integrity.record(invariant).detail,
                self.executed_steps,
                invariant.remedy(),
            },
        );
    }
}

pub noinline fn failFastOnTranslationCause(
    self: anytype,
    address: u64,
    domain: translation_domain.Domain,
    cause: translation_economics.Cause,
    set_base: usize,
    cache_way: usize,
    victim: *const DecodeCacheEntry,
    victim_is_empty: bool,
    victim_was_reused: bool,
    stale_rejected: bool,
    bytes: []const u8,
) void {
    const invariant = run_integrity.Invariant.translation_cache_converges;
    const integrity_record = self.run_integrity.record(invariant);
    if (!translation_cache.shouldFailFast(cause, .{
        .strict = self.run_integrity_strict,
        .fault_policy = self.run_integrity.policy == .fault,
        .allowlisted = integrity_record.allowlistApplies(invariant),
    })) return;

    const global_set: usize = set_base / constants.DECODE_CACHE_WAYS;
    // Banks are unequal, so the bank-local coordinate is the offset from
    // this domain's first set. A modulo by "the" bank size would name a
    // set in the wrong domain the moment the banks stopped matching.
    const bank_set: usize = global_set - translation_cache.primary_layout.bankFirstSet(domain);
    const alternate_set_base = self.decodeCacheAlternateSetBaseFor(address, domain);
    const alternate_global_set: usize = alternate_set_base / constants.DECODE_CACHE_WAYS;
    const source_symbol = self.metadata.nearestSymbol(address);
    var source_decode = decodeInsn(bytes);
    if (source_decode.op == .invalid and self.sparse_memory.containsMapped(address, 1)) {
        source_decode = decodeInsnCompat(bytes);
    }
    const initializer = self.initializer_resolver.current();
    const initializer_index: u64 = if (initializer) |record|
        @intCast(record.index + 1)
    else
        0;
    const initializer_address = if (initializer) |record| record.address else 0;
    const initializer_symbol = if (initializer) |record| record.symbol else "<none>";
    const initializer_symbol_match = if (initializer) |record|
        self.metadata.nearestSymbol(record.address)
    else
        null;
    const source_byte_count = @min(bytes.len, @as(usize, 15));
    const victim_byte_count: usize = if (victim_is_empty)
        0
    else
        @min(@as(usize, victim.instruction_byte_count), victim.instruction_bytes.len);
    const file_offset = self.fileOffsetForVaddr(address) orelse 0;
    const source_name = if (source_symbol) |symbol| symbol.name else self.metadata.addressKind(address).label();
    const source_offset = if (source_symbol) |symbol| symbol.offset else 0;
    const initializer_offset = if (initializer_symbol_match) |symbol| symbol.offset else 0;
    machoCapturePrint(
        "macho-processor: TRANSLATION FAIL-FAST CONTEXT: startup_phase={s} phase_start_step={d} guest_rip=0x{x} guest_thread=0x{x} initializer={d}/{d} initializer_address=0x{x} initializer_symbol={s}+0x{x}\n",
        .{
            @tagName(self.startup.phase),
            self.startup.phase_start_step,
            self.regs.rip,
            self.active_guest_thread,
            initializer_index,
            self.metadata.initializer_addresses.len,
            initializer_address,
            initializer_symbol,
            initializer_offset,
        },
    );
    machoCapturePrint(
        "macho-processor: TRANSLATION FAIL-FAST INSTRUCTION: address=0x{x} symbol={s}+0x{x} op={s} len={d} bytes={any} file_offset=0x{x} file_offset_valid={}\n",
        .{
            address,
            source_name,
            source_offset,
            @tagName(source_decode.op),
            source_decode.len,
            bytes[0..source_byte_count],
            file_offset,
            self.fileOffsetForVaddr(address) != null,
        },
    );
    machoCapturePrint(
        "macho-processor: TRANSLATION FAIL-FAST CACHE: set(global/bank/alternate)={d}/{d}/{d} set_base/alternate={d}/{d} way={d}/{d} generation={d} cause={s} stale_rejected={}\n",
        .{
            global_set,
            bank_set,
            alternate_global_set,
            set_base,
            alternate_set_base,
            cache_way,
            constants.DECODE_CACHE_WAYS,
            self.code_generation,
            cause.label(),
            stale_rejected,
        },
    );
    machoCapturePrint(
        "macho-processor: TRANSLATION FAIL-FAST VICTIM: present={} reused={} rip=0x{x} domain={s} generation={d} reuse_count={d} recently_used={} fast_plain={} host_image={} op={s} len={d} bytes={any}\n",
        .{
            !victim_is_empty,
            victim_was_reused,
            if (victim_is_empty) 0 else victim.rip,
            if (victim_is_empty) "<empty>" else victim.domain.label(),
            if (victim_is_empty) 0 else victim.code_generation,
            if (victim_is_empty) 0 else victim.reuse_count,
            if (victim_is_empty) false else victim.recently_used,
            if (victim_is_empty) false else victim.fast_plain,
            if (victim_is_empty) false else victim.host_image,
            if (victim_is_empty) "<empty>" else @tagName(victim.decoded.op),
            if (victim_is_empty) 0 else victim.decoded.len,
            victim.instruction_bytes[0..victim_byte_count],
        },
    );
    // The decision above is made from one selected way, but a useful
    // failure report must show the complete resident set. Without this,
    // a repeated victim can look like an indexing failure even when the
    // set was genuinely over capacity, and a replacement-policy mistake
    // cannot be distinguished from a working-set overflow on the next
    // run. This path is already terminal, so the bounded way walk has no
    // hot-path cost.
    const resident_sets = translation_domain.primarySetBases(address, domain);
    for (resident_sets, 0..) |resident_set_base, resident_choice| {
        if (resident_choice != 0 and resident_set_base == resident_sets[0]) continue;
        const resident_ways = self.decode_cache[resident_set_base..][0..constants.DECODE_CACHE_WAYS];
        for (resident_ways, 0..) |*resident, resident_way| {
            if (!decodeCacheEntryOccupied(resident)) continue;
            machoCapturePrint(
                "macho-processor: TRANSLATION FAIL-FAST RESIDENT: choice={d} way={d} rip=0x{x} domain={s} generation={d} reuse_count={d} recently_used={} fast_plain={} host_image={} op={s} len={d}\n",
                .{
                    resident_choice,
                    resident_way,
                    resident.rip,
                    resident.domain.label(),
                    resident.code_generation,
                    resident.reuse_count,
                    resident.recently_used,
                    resident.fast_plain,
                    resident.host_image,
                    @tagName(resident.decoded.op),
                    resident.decoded.len,
                },
            );
        }
    }
    const totals = self.translation_economics.summary();
    machoCapturePrint(
        "macho-processor: TRANSLATION FAIL-FAST: invariant={s} cause={s} address=0x{x} domain={s} step={d} totals(fills/vacant/conflict/cold/stale/flush)={d}/{d}/{d}/{d}/{d}/{d}; a discarded decode or executable-byte integrity event cannot continue under the fault policy\n",
        .{
            invariant.label(),
            cause.label(),
            address,
            domain.label(),
            self.executed_steps,
            totals.decodes,
            totals.vacant_fills,
            totals.conflict_fills,
            totals.cold_evictions,
            totals.stale_refills,
            totals.flush_refills,
        },
    );
    native_crash.recordTranslationFault(.{
        .address = address,
        .step = self.executed_steps,
        .guest_rip = self.regs.rip,
        .guest_thread = self.active_guest_thread,
        .startup_phase = @tagName(self.startup.phase),
        .startup_phase_start_step = self.startup.phase_start_step,
        .cause = cause.label(),
        .domain = domain.label(),
        .source_symbol = source_name,
        .source_symbol_offset = source_offset,
        .source_op = @tagName(source_decode.op),
        .source_len = source_decode.len,
        .source_bytes = bytes[0..source_byte_count],
        .file_offset = file_offset,
        .file_offset_valid = self.fileOffsetForVaddr(address) != null,
        .initializer_index = initializer_index,
        .initializer_count = @intCast(self.metadata.initializer_addresses.len),
        .initializer_address = initializer_address,
        .initializer_symbol = initializer_symbol,
        .initializer_symbol_offset = initializer_offset,
        .cache_set = @intCast(global_set),
        .cache_bank_set = @intCast(bank_set),
        .cache_set_base = @intCast(set_base),
        .cache_way = @intCast(cache_way),
        .cache_ways = constants.DECODE_CACHE_WAYS,
        .code_generation = self.code_generation,
        .victim_present = !victim_is_empty,
        .victim_reused = victim_was_reused,
        .stale_rejected = stale_rejected,
        .victim_rip = if (victim_is_empty) 0 else victim.rip,
        .victim_domain = if (victim_is_empty) "<empty>" else victim.domain.label(),
        .victim_code_generation = if (victim_is_empty) 0 else victim.code_generation,
        .victim_reuse_count = if (victim_is_empty) 0 else victim.reuse_count,
        .victim_recently_used = if (victim_is_empty) false else victim.recently_used,
        .victim_fast_plain = if (victim_is_empty) false else victim.fast_plain,
        .victim_host_image = if (victim_is_empty) false else victim.host_image,
        .victim_op = if (victim_is_empty) "<empty>" else @tagName(victim.decoded.op),
        .victim_len = if (victim_is_empty) 0 else victim.decoded.len,
        .victim_bytes = victim.instruction_bytes[0..victim_byte_count],
    });
    self.audit_pause.noteTermination(.diagnostic_termination, self.executed_steps);
    machoCapturePrint(
        "macho-processor: TRANSLATION FAIL-FAST: termination=diagnostic-termination raising SIGSEGV; set ROSETTE_RUN_INTEGRITY_ALLOW=translation-cache-converges only to step past this evidence\n",
        .{},
    );
    macho_log.flushAsyncTransport();
    self.macho_log.flush();
    native_crash.recordPhase("translation-cache-fault");
    _ = std.c.raise(std.c.SIG.SEGV);
    unreachable;
}

pub fn faultOnRunIntegrity(self: anytype, summary: run_integrity.Summary) void {
    const invariant = summary.stop_at orelse return;
    const entry = self.run_integrity.record(invariant);
    // The integrity gate is evaluated before the rest of the graphics
    // checkpoint is emitted. A guest log line can therefore open a wait
    // after the previous checkpoint but immediately before this fault.
    // Flush the retained entry here so a strict stop never loses the exact
    // guest handle, PC/LR, and completion status that caused the frontier
    // to remain unreachable. This is evidence only; it does not close or
    // satisfy the wait.
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY FAULT CONTEXT: flushing guest wait ledger before signal; open entries remain unresolved and do not satisfy liveness\n",
        .{},
    );
    self.logGuestWaitLiveness();
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY FAULT: invariant={s} owner={s} subowner={s} invariant_owner={s} class={s} detail={d} first_violation_step={d} violations={d} regressed={s} step={d} rip=0x{x} thread=0x{x}\n",
        .{
            invariant.label(),
            ownership_contract.root_owner,
            invariant.owner().label(),
            invariant.owner().label(),
            invariant.class().label(),
            entry.detail,
            entry.first_violation_step,
            entry.violations,
            if (entry.regressed()) "YES" else "NO",
            self.executed_steps,
            self.regs.rip,
            self.active_guest_thread,
        },
    );
    machoCapturePrint("macho-processor: RUN INTEGRITY FAULT: {s}\n", .{invariant.remedy()});
    // How much of this log actually reached the file.
    //
    // The ring drops rather than blocking, and its totals were printed only
    // by the normal shutdown path — which a gate that raises SIGSEGV never
    // reaches. So on exactly the runs where a reader is about to conclude
    // "X never happened", the one number that says whether X could have
    // been dropped was missing. On 2026-09-06 a 3-billion-step run carried
    // two checkpoints and no heartbeats, and nothing in it said why.
    const transport = async_log.transportStats();
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY FAULT: log integrity={s} accepted={d} dropped={d} truncated={d} written={d} queued={d}; {s}\n",
        .{
            transport.integrity().label(),
            transport.accepted,
            transport.dropped,
            transport.truncated,
            transport.written,
            transport.queued,
            transport.integrity().guidance(),
        },
    );
    // The run ended because a gate decided to end it. Recording that as a
    // deliberate termination is what keeps the next reader from filing the
    // signal below as a guest crash: on 2026-08-31 the final SIGSEGV was
    // this gate, and the crash report named a JIT symbol that had nothing
    // to do with the invariant that tripped.
    self.audit_pause.noteTermination(.diagnostic_termination, self.executed_steps);
    machoCapturePrint(
        "macho-processor: RUN INTEGRITY FAULT: termination={s}; {s}\n",
        .{
            self.audit_pause.termination.label(),
            self.audit_pause.termination.describe(),
        },
    );
    if (invariant.nonBypassable()) {
        machoCapturePrint(
            "macho-processor: RUN INTEGRITY FAULT: raising SIGSEGV so the crash report names this standard. This invariant is non-bypassable: ROSETTE_RUN_INTEGRITY_ALLOW, warn, and observe cannot permit an ordering inversion to continue\n",
            .{},
        );
    } else {
        machoCapturePrint(
            "macho-processor: RUN INTEGRITY FAULT: raising SIGSEGV so the crash report names this standard. Set ROSETTE_RUN_INTEGRITY_ALLOW={s} to step past this one and reach the next, ROSETTE_RUN_INTEGRITY=warn to record every violation without stopping, or observe to disarm the gate\n",
            .{invariant.label()},
        );
    }
    macho_log.flushAsyncTransport();
    // Preserve the complete causal report before SIGSEGV.  Without this
    // fsync the final fault can be visible while the preceding live
    // counters are still only in the filesystem cache.
    self.macho_log.flush();
    native_crash.recordPhase("run-integrity-fault");
    _ = std.c.raise(std.c.SIG.SEGV);
}

pub fn logWindowAdmission(self: anytype, force: bool) void {
    const W = gpu.window_admission;
    const ledger = &self.window_admission;
    const fingerprint = ledger.fingerprint();
    if (!force and fingerprint == self.window_admission_last_fingerprint) return;
    self.window_admission_last_fingerprint = fingerprint;
    const summary = ledger.summary();
    machoCapturePrint(
        "macho-processor: WINDOW ADMISSION: owner={s} subowner={s} policy={s} observations={d} admitted={d} refused={d} unaccountable={d} faults={d} pairs(touched/clean)={d}/{d} swap(observed/admitted/harness)={d}/{d}/{d} detail_dropped={d} step={d}; {s}\n",
        .{
            ownership_contract.root_owner,
            "rosette:window-admission",
            ledger.policy.label(),
            summary.observations,
            summary.admitted,
            summary.refused,
            summary.unaccountable,
            summary.faults,
            summary.pairs_touched,
            summary.pairs_clean,
            summary.swap_observations,
            summary.swap_admissions,
            summary.swap_harness_admissions,
            summary.details_dropped,
            self.executed_steps,
            summary.verdict(),
        },
    );
    // Collapsed by construction: a pair that was only ever admitted is a
    // success and prints nothing. Eighty thousand lines of log are what
    // happens when every established fact reprints on every checkpoint.
    var facility_index: u8 = 0;
    while (facility_index < W.facility_count) : (facility_index += 1) {
        const facility: gpu.WindowFacility = @enumFromInt(facility_index);
        var operation_index: u8 = 0;
        while (operation_index < W.operation_count) : (operation_index += 1) {
            const operation: gpu.WindowOperation = @enumFromInt(operation_index);
            const record = ledger.entry(facility, operation);
            if (!record.touched() or record.clean()) continue;
            machoCapturePrint(
                "  window-admission owner={s} subowner={s} facility={s: <20} operation={s: <8} observations={d} admitted={d} refused={d} last={s} last_actor={s} first_step={d} last_step={d}\n",
                .{
                    ownership_contract.root_owner,
                    record.last_actor.label(),
                    facility.label(),
                    operation.label(),
                    record.observations,
                    record.admitted(),
                    record.refused(),
                    record.last_verdict.label(),
                    record.last_actor.label(),
                    record.first_step,
                    record.last_step,
                },
            );
            if (record.last_missing != 0) {
                const decision = gpu.window_admission.Decision{ .missing = record.last_missing };
                if (decision.firstMissing()) |missing| {
                    machoCapturePrint(
                        "    window-admission first_unmet_condition={s}\n",
                        .{missing.label()},
                    );
                }
            }
        }
    }
    var detail_index: usize = 0;
    while (detail_index < ledger.detail_count) : (detail_index += 1) {
        const detail = ledger.details[detail_index];
        if (detail.sequence == 0) continue;
        machoCapturePrint(
            "  window-refusal seq={d} actor={s} facility={s} operation={s} verdict={s} disposition={s} origin={s} step={d}\n",
            .{
                detail.sequence,
                detail.actor.label(),
                detail.facility.label(),
                detail.operation.label(),
                detail.verdict.label(),
                detail.disposition.label(),
                detail.originName(),
                detail.step,
            },
        );
    }
    self.logWindowSwapAdmission();
}

pub fn logWindowSwapAdmission(self: anytype) void {
    const ledger = &self.window_admission;
    if (ledger.swap_observations == 0) {
        machoCapturePrint(
            "macho-processor: WINDOW SWAP ADMISSION: no swap boundary has been offered to the window. Xenia has not reached VdSwap or encoded an XE_SWAP, so the handoff Rosette gates has had nothing to gate — this says nothing about whether the gate would admit one\n",
            .{},
        );
        return;
    }
    if (ledger.swapFrontier()) |frontier| {
        machoCapturePrint(
            "macho-processor: WINDOW SWAP ADMISSION: frontier={s} owner={s} verdict={s} observations={d} admitted={d} harness={d}; the first boundary the window has never taken custody of, and the reason it did not\n",
            .{
                frontier.boundary.label(),
                frontier.boundary.owner().label(),
                frontier.verdict.label(),
                frontier.observations,
                ledger.swap_admissions,
                ledger.swap_harness_admissions,
            },
        );
    } else {
        machoCapturePrint(
            "macho-processor: WINDOW SWAP ADMISSION: every swap boundary has been admitted at least once (admitted={d} harness={d}); the handoff from Xenia to the window is complete end to end\n",
            .{ ledger.swap_admissions, ledger.swap_harness_admissions },
        );
    }
    var index: u8 = 0;
    while (index < gpu.window_admission.swap_boundary_count) : (index += 1) {
        const boundary: gpu.WindowSwapBoundary = @enumFromInt(index);
        const record = ledger.swapEntry(boundary);
        if (!record.touched()) continue;
        // A boundary that has only ever been admitted needs no detail.
        if (record.admissions + record.harness_admissions == record.observations) continue;
        machoCapturePrint(
            "  window-swap boundary={s: <20} owner={s: <16} observations={d} admitted={d} harness={d} last={s} best_provenance={s} first_step={d} last_step={d}\n",
            .{
                boundary.label(),
                boundary.owner().label(),
                record.observations,
                record.admissions,
                record.harness_admissions,
                record.last_verdict.label(),
                record.best_provenance.label(),
                record.first_step,
                record.last_step,
            },
        );
    }
}

pub fn cocoaGraphicsPolicyFromEnvironment() gpu.cocoa_runtime.RoutePolicy {
    // A verified frame copy is the useful default for this compatibility
    // layer: it acts only after a complete, non-zero, content-digested
    // frame exists and the native Vulkan presenter is unavailable. It
    // never fabricates VdSwap/XE_SWAP and yields as soon as Xenia presents.
    const raw = std.c.getenv("ROSETTE_COCOA_GRAPHICS_CONTROL") orelse return .verified_guest_fallback;
    const value = std.mem.span(raw);
    if (std.mem.eql(u8, value, "observe") or
        std.mem.eql(u8, value, "audit") or
        std.mem.eql(u8, value, "off") or
        std.mem.eql(u8, value, "0")) return .observe_only;
    if (std.mem.eql(u8, value, "diagnostic")) return .diagnostic_only;
    if (std.mem.eql(u8, value, "fallback") or
        std.mem.eql(u8, value, "verified") or
        std.mem.eql(u8, value, "guest")) return .verified_guest_fallback;
    return .observe_only;
}

pub fn logCocoaGraphicsControl(self: anytype, force: bool) void {
    const runtime = &self.cocoa_graphics;
    const fingerprint = runtime.fingerprint();
    if (!force and fingerprint == self.cocoa_graphics_last_fingerprint) return;
    self.cocoa_graphics_last_fingerprint = fingerprint;
    const control = &runtime.control;
    // The ownership map is what fills this report: twenty-eight resources
    // and thirty-two stages. Once every one of them is ready and stays
    // ready, reprinting the map on each checkpoint says nothing the header
    // line does not, so the detail collapses to a count and returns in full
    // the moment the map changes. Gated on the control plane's own
    // fingerprint rather than the runtime's, so a frame taking custody does
    // not drag sixty settled lines back into the log with it.
    const control_fingerprint = control.fingerprint();
    const map_established = self.cocoa_control_detail_fingerprint == control_fingerprint;
    self.cocoa_control_detail_fingerprint = control_fingerprint;
    const summary = control.summary();
    const frames = runtime.frames.summary();
    const intents = runtime.intents.summary();
    const work = runtime.credits.summary();
    const outcome = self.cocoa_graphics_last_outcome;
    const frame_offer_label = if (outcome.frame_observed) @tagName(outcome.frame_offer) else "none";

    machoCapturePrint(
        "macho-processor: COCOA GRAPHICS CONTROL: schema={d} run=0x{x} step={d} fingerprint=0x{x} owner={s} subowner={s} policy={s} route={s} resources_ready={d}/{d} contested={d} stages_ready={d}/{d} failed={d} ownership_conflicts={d} presenter_lease={s}@{d} handoffs(offered/completed/refused)={d}/{d}/{d} frame_offer={s} frame_class={s} frame_delivery_pending={} semantic_intents(observed/admitted/rejected/duplicates/conflicts)={d}/{d}/{d}/{d}/{d}; raw_machine_code_to_cocoa=REFUSED semantic_boundaries_only=YES\n",
        .{
            gpu.cocoa_runtime.schema_version,
            runtime.run,
            self.executed_steps,
            fingerprint,
            ownership_contract.root_owner,
            "rosette:graphics-control",
            control.policy.label(),
            summary.route.label(),
            summary.ready_resources,
            control.resources.len,
            summary.contested_resources,
            summary.ready_stages,
            control.stages.len,
            summary.failed_stages,
            summary.ownership_conflicts,
            summary.lease_holder.label(),
            control.presenter.generation,
            summary.handoffs_offered,
            summary.handoffs_completed,
            summary.handoffs_refused,
            frame_offer_label,
            outcome.frame_class.label(),
            outcome.frame_delivery_pending,
            intents.observations,
            intents.admitted,
            intents.rejected,
            intents.duplicates,
            intents.conflicts,
        },
    );
    for (intents.operations, 0..) |unique, index| {
        if (unique == 0) continue;
        const operation: gpu.graphics_intent.Operation = @enumFromInt(index);
        machoCapturePrint(
            "  cocoa-intent operation={s} unique={d}\n",
            .{ operation.label(), unique },
        );
    }
    for (intents.rejections, 0..) |unique, index| {
        if (unique == 0) continue;
        const rejection: gpu.graphics_intent.Rejection = @enumFromInt(index);
        machoCapturePrint(
            "  cocoa-intent-rejection reason={s} unique={d}\n",
            .{ rejection.label(), unique },
        );
    }
    var settled_resources: usize = 0;
    for (control.resources) |resource| {
        if (map_established and resource.state == .ready and resource.conflicts == 0) {
            settled_resources += 1;
            continue;
        }
        machoCapturePrint(
            "  cocoa-resource owner={s} subowner={s} custodian_subowner={s} name={s} state={s} identity=0x{x} generation={d} canonical_owner={s} custodian={s} evidence={s} providers=0x{x:0>4} borrowers=0x{x:0>4} observers=0x{x:0>4} observations={d} conflicts={d}\n",
            .{
                ownership_contract.root_owner,
                resource.canonical_owner.label(),
                resource.custodian.label(),
                resource.resource.label(),
                resource.state.label(),
                resource.identity,
                resource.generation,
                resource.canonical_owner.label(),
                resource.custodian.label(),
                resource.evidence.label(),
                resource.providers,
                resource.borrowers,
                resource.observers,
                resource.observations,
                resource.conflicts,
            },
        );
    }
    var settled_stages: usize = 0;
    inline for (@typeInfo(gpu.cocoa_runtime.Stage).@"enum".fields) |field| {
        const stage: gpu.cocoa_runtime.Stage = @enumFromInt(field.value);
        const record = control.stages[field.value];
        if (map_established and record.state == .ready and record.owner_conflicts == 0) {
            settled_stages += 1;
        } else machoCapturePrint(
            "  cocoa-stage owner={s} subowner={s: <16} expected_subowner={s: <16} stage_owner={s: <16} state={s: <8} stage={s} identity=0x{x} generation={d} evidence={s} observations={d} owner_conflicts={d}\n",
            .{
                ownership_contract.root_owner,
                record.owner.label(),
                stage.expectedOwner().label(),
                record.owner.label(),
                record.state.label(),
                stage.label(),
                record.identity,
                record.generation,
                record.evidence.label(),
                record.observations,
                record.owner_conflicts,
            },
        );
    }
    if (settled_resources + settled_stages != 0) machoCapturePrint(
        "  cocoa collapsed: resources={d} stages={d} ready, unconflicted and unchanged since the previous checkpoint, where they printed in full. Everything not ready is still listed above\n",
        .{ settled_resources, settled_stages },
    );
    for (control.conflicts[0..control.conflict_count]) |conflict| {
        machoCapturePrint(
            "  cocoa-conflict owner={s} subowner={s} sequence={d} kind={s} resource={s} expected_owner={s} actor={s} expected_identity=0x{x} observed_identity=0x{x} generation={d} step={d}\n",
            .{
                ownership_contract.root_owner,
                conflict.actor.label(),
                conflict.sequence,
                conflict.kind.label(),
                conflict.resource.label(),
                conflict.expected_owner.label(),
                conflict.actor.label(),
                conflict.expected_identity,
                conflict.observed_identity,
                conflict.generation,
                conflict.step,
            },
        );
    }
    for (control.handoffs[0..control.handoff_count]) |handoff| {
        machoCapturePrint(
            "  cocoa-handoff owner={s} subowner={s} from_subowner={s} to_subowner={s} token={d} state={s} resource={s} identity=0x{x} generation={d} from={s} to={s} offered={d} accepted={d} completed={d}\n",
            .{
                ownership_contract.root_owner,
                "rosette:handoff",
                handoff.from.label(),
                handoff.to.label(),
                handoff.token,
                handoff.state.label(),
                handoff.resource.label(),
                handoff.identity,
                handoff.generation,
                handoff.from.label(),
                handoff.to.label(),
                handoff.offered_step,
                handoff.accepted_step,
                handoff.completed_step,
            },
        );
    }
    machoCapturePrint(
        "macho-processor: COCOA FRAME CUSTODY: offered={d} duplicates={d} rejected={d} conflicts={d} acquired={d} submitted={d} presented={d} classes(authentic/host_cadence/diagnostic/synthetic)={d}/{d}/{d}/{d} last={s}\n",
        .{
            frames.offered,
            frames.duplicates,
            frames.rejected,
            frames.conflicts,
            frames.acquired,
            frames.submitted,
            frames.presented,
            frames.authentic_guest,
            frames.guest_pixels_host_cadence,
            frames.diagnostic,
            frames.synthetic_guest_control,
            frames.last_class.label(),
        },
    );
    var latest: ?*const gpu.frame_handoff.Record = null;
    for (runtime.frames.records[0..runtime.frames.count]) |*record| {
        if (latest == null or record.descriptor.identity.serial > latest.?.descriptor.identity.serial)
            latest = record;
    }
    if (latest) |record| {
        const frame = record.descriptor;
        machoCapturePrint(
            "  cocoa-frame owner={s} subowner={s} custodian_subowner={s} run=0x{x} serial={d} generation={d} source=0x{x}+0x{x} extent={d}x{d} pitch={d} format={s} orientation={s} producer={s} guest_pixels={s} guest_swap={s} state={s} custodian={s} class={s} rejection={s}\n",
            .{
                ownership_contract.root_owner,
                frame.producer.label(),
                record.custodian.label(),
                frame.identity.run,
                frame.identity.serial,
                frame.identity.generation,
                frame.source_address,
                frame.source_length,
                frame.width,
                frame.height,
                frame.row_pitch,
                frame.format.label(),
                frame.orientation.label(),
                frame.producer.label(),
                if (frame.guest_pixels) "YES" else "NO",
                if (frame.guest_requested_present) "YES" else "NO",
                record.state.label(),
                record.custodian.label(),
                record.frame_class.label(),
                record.rejection.label(),
            },
        );
    }
    machoCapturePrint(
        "macho-processor: GPU WORK CREDIT: observations={d} unique_claims={d} duplicates={d} conflicts={d} malformed={d} credited_units={d}; repeated logs and heartbeats never add units\n",
        .{ work.observations, work.unique_claims, work.duplicates, work.conflicts, work.malformed, work.credited_units },
    );
    inline for (@typeInfo(gpu.work_credit.Kind).@"enum".fields) |field| {
        const kind: gpu.work_credit.Kind = @enumFromInt(field.value);
        machoCapturePrint("  gpu-work kind={s: <20} unique_units={d}\n", .{ kind.label(), work.units(kind) });
    }
}

pub fn serviceApplicationFrameworkRequests(self: anytype) void {
    const ServiceResult = struct {
        status: application_framework.contract.RequestStatus,
        reason: u64,
    };
    var request: application_framework.contract.Request = .{};
    var serviced: usize = 0;
    while (serviced < 8 and self.application_framework.takePending(&request)) : (serviced += 1) {
        const command = if (request.command <= @intFromEnum(application_framework.contract.Command.write_host_state))
            @as(application_framework.contract.Command, @enumFromInt(request.command))
        else
            null;
        const result = if (command) |resolved| blk: {
            switch (resolved) {
                .snapshot => break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.applied, .reason = 0 },
                .enable_trace => {
                    self.application_framework.enableTraceMask(request.argument0);
                    break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.applied, .reason = 0 };
                },
                .disable_trace => {
                    self.application_framework.clearTraceFlags();
                    break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.applied, .reason = 0 };
                },
                .drain_gpu_interrupts => {
                    if (self.gpu_interrupt_callback == 0 or self.gpu_xenos_runtime.interrupts.pending_count == 0)
                        break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.not_ready, .reason = 0x4750_5549_4e54_0001 };
                    const delivered = self.gpu_xenos_runtime.drainInterrupts(deliverGpuInterrupt, self, 32);
                    break :blk ServiceResult{
                        .status = if (delivered != 0) application_framework.contract.RequestStatus.applied else application_framework.contract.RequestStatus.not_ready,
                        .reason = delivered,
                    };
                },
                .refresh_output => {
                    if (!self.dynamic_forwarder.guestFrontBufferAvailable())
                        break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.not_ready, .reason = 0x4652_4f4e_5400_0001 };
                    break :blk ServiceResult{
                        .status = if (self.dynamic_forwarder.attemptScheduledRefresh(self)) application_framework.contract.RequestStatus.applied else application_framework.contract.RequestStatus.not_ready,
                        .reason = 0,
                    };
                },
                .pause_guest, .resume_guest, .set_breakpoint, .inspect_guest_memory => break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.unsupported, .reason = 0x4652_414d_455f_0001 },
                .invoke_guest_api, .write_guest_memory, .write_host_state => break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.denied, .reason = 0x4755_4553_545f_0002 },
            }
        } else ServiceResult{ .status = application_framework.contract.RequestStatus.invalid, .reason = 0 };
        _ = self.application_framework.complete(request.request_id, result.status, result.reason);
    }
}

pub fn logGraphicsHealthContract(self: anytype) void {
    const H = graphics_health_contract;
    const ledger = &self.graphics_health;
    // Reachable from two paths in one checkpoint. Printing forty-two stage
    // lines twice says nothing the first copy did not.
    if (self.graphics_health_report_epoch == self.report_epoch) return;
    self.graphics_health_report_epoch = self.report_epoch;
    const report = ledger.report();
    // A stage that is satisfied and has stayed satisfied is a success, and
    // reprinting it on every checkpoint is what turns a diagnostic into
    // eighty thousand lines. The detail comes back in full the moment the
    // fingerprint moves, so a regression is never collapsed away.
    const fingerprint = ledger.fingerprint();
    const detail_established = self.graphics_health_detail_fingerprint == fingerprint;
    self.graphics_health_detail_fingerprint = fingerprint;
    machoCapturePrint(
        "macho-processor: GRAPHICS HEALTH CONTRACT: schema={d} satisfied={d} degraded={d} blocked={d} untested={d} observed={d}/{d} step={d} fingerprint=0x{x}; {s}\n",
        .{
            @as(u16, graphics_health_contract.schema_version),
            report.satisfied,
            report.degraded,
            report.blocked,
            report.untested,
            report.satisfied + report.degraded + report.blocked,
            report.total,
            self.executed_steps,
            ledger.fingerprint(),
            ledger.verdict(),
        },
    );
    var complete_paths: usize = 0;
    inline for (@typeInfo(H.Path).@"enum".fields) |field| {
        const path: H.Path = @enumFromInt(field.value);
        const path_report = ledger.pathReport(path);
        if (path_report.complete() and detail_established) {
            complete_paths += 1;
        } else machoCapturePrint(
            "  health path={s: <16} complete={s} progress={d}/{d} percent={d} satisfied={d} degraded={d} blocked={d} untested={d} first_missing={s}\n",
            .{
                path.label(),
                if (path_report.complete()) "YES" else "NO",
                path_report.satisfied,
                path_report.total,
                path_report.percent(),
                path_report.satisfied,
                path_report.degraded,
                path_report.blocked,
                path_report.untested,
                if (path_report.first_missing) |missing| missing.label() else "<none>",
            },
        );
    }
    var complete_layers: usize = 0;
    inline for (@typeInfo(H.Layer).@"enum".fields) |field| {
        const layer: H.Layer = @enumFromInt(field.value);
        const layer_report = ledger.layerReport(layer);
        if (layer_report.percent() == 100 and detail_established) {
            complete_layers += 1;
        } else machoCapturePrint(
            "  health layer={s: <16} progress={d}% satisfied={d} degraded={d} blocked={d} untested={d}\n",
            .{ layer.label(), layer_report.percent(), layer_report.satisfied, layer_report.degraded, layer_report.blocked, layer_report.untested },
        );
    }
    var satisfied_stages: usize = 0;
    inline for (@typeInfo(H.Stage).@"enum".fields) |field| {
        const stage: H.Stage = @enumFromInt(field.value);
        const entry = ledger.entry(stage);
        if (entry.state == .satisfied and detail_established) {
            satisfied_stages += 1;
        } else machoCapturePrint(
            "  health stage={s: <38} state={s: <9} owner={s: <16} layer={s: <14} count={d} first={d} last={d} source_mask=0x{x} note={s}\n",
            .{ stage.label(), entry.state.label(), stage.owner().label(), stage.layer().label(), entry.count, entry.first_step, entry.last_step, entry.source_mask, entry.note() },
        );
    }
    if (complete_paths + complete_layers + satisfied_stages != 0) machoCapturePrint(
        "  health collapsed: paths={d} layers={d} stages={d} unchanged since the previous checkpoint and printed in full there; every one of them is satisfied. This block reprints entirely the moment the fingerprint moves\n",
        .{ complete_paths, complete_layers, satisfied_stages },
    );
}

pub fn logApplicationController(self: anytype, decision: application_controller.Decision) void {
    machoCapturePrint(
        "macho-processor: APPLICATION CONTROLLER: epoch={d} observations={d} transitions={d} phase={s} action={s} blocker={s} secondary={s} domain={s} step={d} quiet(guest/ring/pm4/presenter)={d}/{d}/{d}/{d} host_action_authorized={s} host_drains={d} host_refreshes={d} guest_boundary_observations={d} contract_violations={d}; guest-owned decisions remain observational and never authorize host mutation\n",
        .{
            self.application_controller.run_epoch,
            self.application_controller.observations,
            self.application_controller.transitions,
            decision.phase.label(),
            decision.action.label(),
            decision.blocker.label(),
            decision.secondary_blocker.label(),
            decision.domain.label(),
            decision.step,
            decision.guest_quiet_steps,
            decision.ring_quiet_steps,
            decision.pm4_quiet_steps,
            decision.presenter_quiet_steps,
            if (decision.host_action_authorized) "YES" else "NO",
            self.application_controller_host_drains,
            self.application_controller_host_refreshes,
            self.application_controller.guest_boundary_observations,
            self.application_controller.contract_violations,
        },
    );
}

pub fn logApplicationFramework(self: anytype) void {
    const snapshot = self.application_framework.snapshot();
    const mode: application_framework.contract.Mode = @enumFromInt(snapshot.mode);
    machoCapturePrint(
        "macho-processor: APPLICATION FRAMEWORK: mode={s} sequence={d} events(retained/total/dropped)={d}/{d}/{d} requests(total/queued/applied/denied)={d}/{d}/{d}/{d} equivalence(checks/matches/mismatches)={d}/{d}/{d} last_guest(step/rip)=({d},0x{x}) application_id=0x{x}\n",
        .{
            mode.label(),
            snapshot.sequence,
            snapshot.events_retained,
            snapshot.events_total,
            snapshot.events_dropped,
            snapshot.requests_total,
            snapshot.requests_queued,
            snapshot.requests_applied,
            snapshot.requests_denied,
            snapshot.equivalence_checks,
            snapshot.equivalence_matches,
            snapshot.equivalence_mismatches,
            snapshot.last_guest_step,
            snapshot.last_guest_rip,
            snapshot.application_id,
        },
    );
    const retained: usize = @intCast(@min(snapshot.events_retained, 8));
    if (retained == 0) return;
    const first = snapshot.events_retained - retained;
    var ordinal: usize = @intCast(first);
    while (ordinal < @as(usize, @intCast(snapshot.events_retained))) : (ordinal += 1) {
        var event: application_framework.contract.Event = .{};
        if (!self.application_framework.readEvent(ordinal, &event)) continue;
        const name = std.mem.sliceTo(event.name[0..], 0);
        const detail = std.mem.sliceTo(event.detail[0..], 0);
        machoCapturePrint(
            "  app-event seq={d} kind={d} truth={d} owner={d} domain={d} step={d} rip=0x{x} subject=0x{x} expected=0x{x} actual=0x{x} eq={d} name={s} detail={s}\n",
            .{ event.sequence, event.kind, event.truth, event.owner, event.domain, event.guest_step, event.guest_rip, event.subject, event.expected, event.actual, event.equivalence, name, detail },
        );
    }
}

pub fn refreshVdSwapContract(self: anytype) void {
    const at = self.executed_steps;
    const ledger = &self.gpu_vd_swap_contract;
    defer self.noteVdSwapMilestones();
    const tracepoints = &self.execution_tracepoints;

    // The producer probes.  Each is recorded on every refresh, found or
    // not, because "the tracepoint watched this export for four billion
    // steps and it never fired" and "nobody was watching" are the two
    // readings the report has to be able to tell apart — and they send a
    // reader to opposite ends of the system.
    const swap_watched = tracepoints.roleEntered(.swap);
    ledger.observeProbe(.guest_vdswap_entered, .guest_export_tracepoint, swap_watched, ledger.vdswap_calls, at);
    ledger.observeProbe(.guest_vdswap_entered, .guest_log_breadcrumb, ledger.vdswap_calls != 0, ledger.vdswap_calls, at);
    ledger.observeProbe(.vdswap_arguments_captured, .vdswap_argument_capture, ledger.arguments_observed != 0, ledger.arguments_observed, at);
    ledger.observeProbe(.guest_xe_swap_encoded, .guest_log_breadcrumb, self.guest_vdswap_packet_encoded, ledger.guest_packet_encodes, at);
    ledger.observeProbe(.vdswap_completed, .guest_log_breadcrumb, self.guest_vdswap_entry_completed, ledger.vdswap_completions, at);
    ledger.observeProbe(.fetch_constant_encoded, .guest_log_breadcrumb, ledger.fetch_observations != 0, ledger.fetch_observations, at);
    ledger.observeProbe(.ring_write_pointer_published, .ring_geometry_capture, self.gpu_ring_publication.advances != 0, self.gpu_ring_publication.advances, at);
    ledger.observeProbe(.ring_geometry_observed, .ring_geometry_capture, self.gpu_ring_publication.geometry != null, self.gpu_ring_watch_size, at);

    // `frontbuffer_validated` declares no prerequisite on purpose: a ring
    // scan can name a valid surface without the title ever entering
    // VdSwap. That made it permanently reachable and, until now,
    // permanently unprobed — every one of its four probes was recorded
    // only from inside a branch this run never took, so the contract
    // reported Rosette's silence as the title's absence. Each probe now
    // reports on every refresh, from its own evidence path.
    if (ledger.arguments_observed == 0) {
        // No argument capture has happened, so there are no captured
        // arguments to read a front buffer out of.
        ledger.recordStarvation(
            .frontbuffer_validated,
            .vdswap_argument_capture,
            .input_unavailable,
            .upstream_producer_idle,
            0,
            at,
        );
    } else {
        ledger.observeProbe(
            .frontbuffer_validated,
            .vdswap_argument_capture,
            ledger.frontbufferSeenFrom(.vdswap_argument_capture),
            ledger.arguments_observed,
            at,
        );
    }
    if (ledger.log_lines_seen == 0) {
        // The breadcrumb channel has never carried a line here. That is a
        // question about Rosette's log plumbing, not about the title.
        ledger.recordStarvation(
            .frontbuffer_validated,
            .guest_log_breadcrumb,
            .input_unavailable,
            .source_never_fed,
            0,
            at,
        );
    } else {
        ledger.observeProbe(
            .frontbuffer_validated,
            .guest_log_breadcrumb,
            ledger.frontbufferSeenFrom(.guest_log),
            ledger.log_lines_seen,
            at,
        );
    }

    if (swap_watched) {
        ledger.observeVdSwapEntered(at, .guest_tracepoint);
    }
    if (self.guest_vdswap_packet_encoded) {
        ledger.observeGuestPacketEncoded(at, .guest_log);
    }
    if (self.guest_vdswap_entry_completed) {
        ledger.observeVdSwapCompleted(at, .guest_log);
    }
    if (self.gpu_ring_publication.advances != 0) {
        ledger.observePublication(at, .guest_publication);
    }
    if (self.gpu_ring_watch_base != 0 and self.gpu_ring_watch_size != 0 and
        self.gpu_ring_publication.geometry != null)
    {
        ledger.observeRingGeometry(at, .memory_mapping);
    }

    // The PM4/indirect walk now has an explicit post-consumption section.
    // These observations are deliberately sourced from the causal ledger
    // and the stateful Xenos runtime independently: seeing 24 draw
    // packets in retained memory is not the same thing as observing a
    // programmed target, a completion signal, or a guest continuation.
    const causal = &self.xenia_gpu_causal_trace;
    ledger.observeIntermediary(.{
        .pm4_state_programmed = causal.observed(.pm4_state_programmed),
        .draw_submitted = causal.observed(.first_draw_submitted),
        .draw_consumed = causal.observed(.first_draw_consumed),
        .guest_wait_observed_after_draw = causal.postDrawWaitObserved(),
    }, at, .causal_trace);
    ledger.observeProbe(.pm4_state_programmed, .causal_event_ledger, causal.observed(.pm4_state_programmed), 0, at);
    ledger.observeProbe(.draw_submitted, .causal_event_ledger, causal.observed(.first_draw_submitted), 0, at);
    ledger.observeProbe(.draw_consumed, .causal_event_ledger, causal.observed(.first_draw_consumed), 0, at);
    ledger.observeProbe(.guest_wait_observed_after_draw, .causal_event_ledger, causal.postDrawWaitObserved(), causal.wait_events_after_draw, at);

    const target = self.gpu_xenos_runtime.renderTargetEvidence();
    ledger.observeIntermediary(.{
        .render_target_state_observed = target.state_observed,
        .render_target_memory_observed = self.gpu_xenos_runtime.color_resolve_observations != 0,
        .draw_completion_signaled = self.gpu_xenos_runtime.draw_completion_signals != 0,
    }, at, .xenos_runtime);
    ledger.observeIntermediary(.{
        .draw_completion_dispatched = self.gpu_draw_completion_dispatches != 0,
    }, at, .interrupt_dispatch);
    if (causal.firstDrawConsumedStep()) |draw_step| {
        const progressed = self.gpu_ring_publication.advances > 1 and
            self.gpu_ring_publication.last_advance_step > draw_step;
        if (progressed) {
            ledger.observeIntermediary(.{
                .guest_producer_progressed_after_draw = true,
            }, at, .guest_progress);
        }
        // The counter is live and the producer has not moved: a finding
        // about the title, not a missing observer.
        ledger.observeProbe(
            .guest_producer_progressed_after_draw,
            .guest_progress_counter,
            progressed,
            self.gpu_ring_publication.advances,
            at,
        );
    } else {
        // Nothing has consumed a draw yet, so there is no "after" to
        // measure progress against.
        ledger.recordStarvation(
            .guest_producer_progressed_after_draw,
            .guest_progress_counter,
            .input_unavailable,
            .upstream_producer_idle,
            0,
            at,
        );
    }

    // The tracepoint says the decoder ran, not that the packet came from
    // VdSwap.  It closes only the packet readability/shape observations;
    // the authentic-consumption stage remains closed until a provenance-
    // bearing milestone or the stateful executor proves the source.
    if (tracepoints.roleEntered(.xe_swap_decode)) {
        ledger.observePacket(.{
            .candidate_seen = true,
            .decoded = true,
            .stream_observed = true,
            .stream_validated = true,
        }, at, .command_processor_tracepoint);
    }

    if (ledger.authentic_consumptions != 0 and tracepoints.roleEntered(.command_swap)) {
        ledger.observeIssueSwap(at, .issue_swap_tracepoint);
    }
    if (ledger.authentic_consumptions != 0 and tracepoints.roleEntered(.presenter)) {
        ledger.observeOutputRefresh(at, .output_refresh_tracepoint);
    }
    // The presenter probes are gated on an authentic consumption by owner
    // rule: entering IssueSwap for a swap the command processor never
    // consumed would present a frame the title did not draw.  That is a
    // refusal, and it is recorded as one — a policy decision a reader can
    // act on, not a capability Rosette lacks.
    if (ledger.authentic_consumptions == 0) {
        for ([_]gpu.VdSwapStage{ .issue_swap_entered, .output_refresh_succeeded }) |stage| {
            ledger.recordProbe(stage, .presenter_tracepoint, .refused_by_owner, 0, at);
        }
        ledger.recordProbe(.native_presented, .native_presenter_counter, .refused_by_owner, 0, at);
    } else {
        ledger.observeProbe(.issue_swap_entered, .presenter_tracepoint, tracepoints.roleEntered(.command_swap), 0, at);
        ledger.observeProbe(.output_refresh_succeeded, .presenter_tracepoint, tracepoints.roleEntered(.presenter), 0, at);
        ledger.observeProbe(
            .native_presented,
            .native_presenter_counter,
            self.dynamic_forwarder.nativePresenterFramesPresented() != 0,
            self.dynamic_forwarder.nativePresenterFramesPresented(),
            at,
        );
    }
    ledger.observeProbe(
        .authentic_xe_swap_consumed,
        .command_processor_tracepoint,
        ledger.authentic_consumptions != 0,
        ledger.authentic_consumptions,
        at,
    );
    if (ledger.authentic_consumptions != 0 and
        self.dynamic_forwarder.nativePresenterFramesPresented() != 0 and
        self.gpu_ring_injection.injections == 0)
    {
        ledger.observeNativePresent(at, .native_present_tracepoint);
    }
    if (self.gpu_xenos_runtime.last_swap) |swap| {
        if (self.gpu_xenos_runtime.swap_count != 0 and
            self.gpu_ring_injection.injections == 0 and
            self.gpu_ring_publication.published())
        {
            ledger.observeAuthenticConsumption(
                swap,
                self.gpu_xenos_runtime.frontBufferFetch(),
                at,
                .stateful_pm4_executor,
            );
        }
    }
}

pub fn noteVdSwapMilestones(self: anytype) void {
    const mask = self.gpu_vd_swap_contract.observed_mask;
    const fresh = mask & ~self.run_horizon_vdswap_mask;
    if (fresh == 0) return;
    self.run_horizon_vdswap_mask = mask;
    self.run_horizon.observe(.{
        .step = self.executed_steps,
        .emulated_ms = self.run_horizon.latest.emulated_ms,
        .vblanks = self.run_horizon.latest.vblanks,
        .host_seconds = self.elapsedHostSeconds(),
    });
    inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
        const stage: gpu.VdSwapStage = @enumFromInt(field.value);
        if (fresh & gpu.vd_swap_contract.stageBit(stage) != 0) {
            self.run_horizon.noteMilestone(stage.label());
        }
    }
}

pub fn elapsedHostSeconds(self: anytype) u64 {
    // The same monotonic source the heartbeat throughput uses, so the two
    // rates in the report cannot disagree about how long the run has been
    // going.
    const now = startup_observer.monotonicNanoseconds();
    if (self.run_started_at_ns == 0 or now <= self.run_started_at_ns) return 0;
    return (now - self.run_started_at_ns) / std.time.ns_per_s;
}

pub fn stateHarnessClaims(self: anytype) void {
    const at = self.executed_steps;
    const ledger = &self.claim_reconciliation;
    const publication = &self.gpu_ring_publication;

    // The tracepoint's own count for each boundary the emulator also
    // reports a breadcrumb for.
    //
    // Only stated once the tracepoint is armed: an unarmed tracepoint has
    // not looked, and a zero from it would be a claim it never made. Once
    // armed, its count is exact for the address it watches — and that is
    // the whole hazard. An export with several candidate addresses can be
    // entered through one the tracepoint is not on, and the gate then
    // reports `boundary_never_crossed` for a boundary the title crossed.
    // Stating it as a claim is what puts the two numbers side by side.
    const boundary_pairs = [_]struct {
        claim: claim_reconciliation.Claim,
        boundary: gpu.bringup_gate.Boundary,
    }{
        .{ .claim = .vd_query_video_mode_entries, .boundary = .query_video_mode },
        .{ .claim = .vd_initialize_engines_entries, .boundary = .initialize_engines },
        .{ .claim = .vd_initialize_ring_buffer_entries, .boundary = .initialize_ring_buffer },
        .{ .claim = .vd_set_graphics_interrupt_callback_entries, .boundary = .set_interrupt_callback },
        .{ .claim = .vd_swap_entries, .boundary = .issue_swap },
    };
    for (boundary_pairs) |pair| {
        if (!self.execution_tracepoints.boundaryArmed(@intFromEnum(pair.boundary))) continue;
        ledger.state(
            pair.claim,
            .rosette_boundary_tracepoint,
            self.gpu_bringup_gate.recordFor(pair.boundary).hits,
            at,
        );
    }

    if (self.gpu_ring_watch_base != 0) {
        ledger.state(.ring_base_address, .rosette_ring_publication, self.gpu_ring_watch_base, at);
        ledger.state(.ring_size_bytes, .rosette_ring_publication, self.gpu_ring_watch_size, at);
        ledger.stateBool(.ring_initialised, .rosette_ring_publication, true, at);
    }
    if (publication.geometry) |geometry| {
        ledger.state(.ring_read_pointer, .rosette_ring_publication, geometry.read_pointer, at);
        ledger.state(.ring_write_pointer, .rosette_ring_publication, geometry.write_pointer, at);
    }
    // Xenia's interrupt callback is a PowerPC title callback registered and
    // executed inside Xenia's CPU engine. `gpu_interrupt_callback` is a
    // separate Rosette-model callback used by the fallback Xenos runtime.
    // They are different objects and execution domains, so they must not be
    // entered under the same callback claims. The Xenia claims are fed only
    // by Xenia's self-contained log records; this claim names only the
    // modelled-runtime stage.
    ledger.state(
        .draw_completion_dispatches,
        .rosette_interrupt_dispatch,
        self.gpu_draw_completion_dispatches,
        at,
    );
    ledger.state(
        .swap_packets_consumed,
        .rosette_xenos_runtime,
        self.gpu_xenos_runtime.swap_count,
        at,
    );
}

pub fn logClaimReconciliation(self: anytype) void {
    self.stateHarnessClaims();
    const ledger = &self.claim_reconciliation;
    const totals = ledger.summary();
    const finding = totals.finding();

    machoCapturePrint(
        "macho-processor: CLAIM RECONCILIATION: finding={s} observed={d}/{d} multi_source={d} single_source={d} corroborated={d} agreed={d} superseded={d} contested={d} crosses_sides={s} statements={d} step={d}; {s}\n",
        .{
            finding.label(),
            totals.observed,
            claim_reconciliation.claim_count,
            totals.multi_source,
            totals.single_source,
            totals.corroborated,
            totals.agreed,
            totals.superseded,
            totals.contested,
            if (totals.crosses_sides) "YES" else "NO",
            totals.statements,
            self.executed_steps,
            finding.guidance(),
        },
    );

    if (ledger.blocking()) |result| {
        machoCapturePrint(
            "  CLAIM BLOCKER: {s} agreement={s} current={s}=0x{x} (step {d}) losing={s}=0x{x} (step {d}) crosses_sides={s}; {s}\n",
            .{
                result.claim.label(),
                result.agreement.label(),
                if (result.current_source) |which| which.label() else "<none>",
                result.current_value,
                result.current_step,
                if (result.losing_source) |which| which.label() else "<none>",
                result.losing_value,
                result.losing_step,
                if (result.crosses_sides) "YES" else "NO",
                result.agreement.guidance(),
            },
        );
    }

    inline for (@typeInfo(claim_reconciliation.Claim).@"enum".fields) |field| {
        const claim: claim_reconciliation.Claim = @enumFromInt(field.value);
        const result = ledger.reconcile(claim);
        if (result.agreement != .unobserved) {
            machoCapturePrint(
                "  claim {s: <34} {s: <14} observers={d} current={s: <28}=0x{x:0>8} losing={s: <28}=0x{x:0>8} crosses={s} counter={s}\n",
                .{
                    claim.label(),
                    result.agreement.label(),
                    result.observers,
                    if (result.current_source) |which| which.label() else "-",
                    result.current_value,
                    if (result.losing_source) |which| which.label() else "-",
                    result.losing_value,
                    if (result.crosses_sides) "YES" else "NO",
                    if (claim.isCounter()) "YES" else "NO",
                },
            );
        }
    }
}

pub fn pipelineEvidence(self: anytype) pipeline_evidence.Report {
    var report = pipeline_evidence.Report{};
    const Pair = struct { stage: pipeline_evidence.Stage, boundary: gpu.bringup_gate.Boundary };
    const pairs = [_]Pair{
        .{ .stage = .ring_setup, .boundary = .initialize_ring_buffer },
        .{ .stage = .packet_consumption, .boundary = .execute_packet_type3 },
        .{ .stage = .draw, .boundary = .issue_draw },
        .{ .stage = .target, .boundary = .render_target_update },
        .{ .stage = .swap_request, .boundary = .guest_swap_requested },
        .{ .stage = .swap_decode, .boundary = .xe_swap_decoded },
        .{ .stage = .swap_issue, .boundary = .issue_swap },
    };
    for (pairs) |pair| {
        const record = self.gpu_bringup_gate.recordFor(pair.boundary);
        report.put(pair.stage, .{
            .count = record.hits,
            .origin = if (record.watched()) .x86_tracepoint else .unobserved,
            .meaning = .entry,
            .first_step = record.first_step,
            .last_step = record.last_step,
            // No producer registration proves all paths were covered from
            // run start. A currently armed symbol alone cannot do that.
            .coverage = .{ .through_step = self.executed_steps },
        });
    }
    report.put(.guest_execution, .{
        .count = @intFromBool(self.xenia_pipeline.hasReached(.guest_main_ready)),
        .origin = .emulator_counter,
        .meaning = .entry,
    });
    var guest_publications: u64 = 0;
    for (self.audit_ring_transport.retained()) |transition| {
        if (transition.guestAuthentic() and transition.effective()) guest_publications +|= 1;
    }
    report.put(.ring_publication, .{
        .count = guest_publications,
        .origin = .emulator_counter,
        .meaning = .effect,
    });
    // No live Xenia resolve completion carrier currently feeds this
    // report. Rosette's retained/model PM4 execution cannot fill that hole.
    report.put(.resolve, .{});
    const frames = self.cocoa_graphics.frames.summary();
    var authentic_offers: u64 = 0;
    for (self.cocoa_graphics.frames.records[0..self.cocoa_graphics.frames.count]) |record| {
        if (record.descriptor.guest_pixels and record.descriptor.guest_requested_present and
            !record.descriptor.synthetic_guest_control) authentic_offers +|= 1;
    }
    report.put(.frame_offer, .{
        .count = authentic_offers,
        .origin = .canonical_custody,
        .meaning = .effect,
    });
    report.put(.frame_completion, .{
        .count = frames.authentic_guest,
        .origin = .canonical_custody,
        .meaning = .effect,
    });
    return report;
}

pub fn logPipelineEvidence(self: anytype) void {
    const report = self.pipelineEvidence();
    const fingerprint = report.fingerprint(self.executed_steps);
    const changed = fingerprint != self.pipeline_evidence_last_fingerprint;
    self.pipeline_evidence_last_fingerprint = fingerprint;
    const frames = self.cocoa_graphics.frames.summary();
    machoCapturePrint(
        "macho-processor: X86 PIPELINE EVIDENCE: first_unobserved={s} completed(authentic/host_cadence/diagnostic)={d}/{d}/{d} open_guest_waits={d} step={d}; entries prove entry only; every row is evaluated independently, and an observation gap is not a broken GPU stage\n",
        .{ if (report.firstUnobserved(self.executed_steps)) |stage| stage.label() else "<none>", frames.authentic_guest, frames.guest_pixels_host_cadence, frames.diagnostic, self.guest_wait_liveness.open_wait_count, self.executed_steps },
    );
    if (changed) {
        inline for (@typeInfo(pipeline_evidence.Stage).@"enum".fields) |field| {
            const stage: pipeline_evidence.Stage = @enumFromInt(field.value);
            const row = report.row(stage);
            machoCapturePrint("  pipeline-evidence stage={s} state={s} count={d} source={s} first={d} last={d} whole_run_negative={s}\n", .{ stage.label(), @tagName(row.verdict(0, self.executed_steps)), row.count, @tagName(row.origin), row.first_step, row.last_step, @tagName(row.coverage.negative(0, self.executed_steps)) });
        }
    }
    for (self.guest_wait_liveness.open_waits[0..self.guest_wait_liveness.open_wait_count]) |wait| {
        if (!wait.main_thread and !wait.bootstrap_thread) continue;
        machoCapturePrint("  pipeline-dependency class={s} handle=0x{x} object=0x{x} type={d} thread={d} pc=0x{x} lr=0x{x} age_steps={d}; a GPU callback return cannot satisfy this wait without a matching object and completion\n", .{ wait.classLabel(), wait.handle, wait.guest_object, wait.object_type, wait.thread_id, wait.pc, wait.lr, self.executed_steps -| wait.entered_step });
    }
}
