//! The standards a run has to meet to be allowed to continue.
//!
//! Rosette is not a compatibility shim that gets an application on screen by
//! whatever means work. It is a framework that hosts an application and stays
//! answerable for everything that crosses the boundary between them. A run in
//! which the two are *not* interoperating correctly is worse than a run that
//! stops, because it burns hours and produces a log in which the real defect is
//! one line among eighty thousand.
//!
//! So this is a set of named invariants over the run's own ledgers, each with
//! an owner, evaluated at every checkpoint. The first one violated stops the
//! run and names what to fix.
//!
//! ## Arming is the whole design
//!
//! Every invariant here would be violated at step zero. A window has presented
//! no frames, no swap has been offered, the translation cache is empty, no
//! capability has been exercised. Reporting those as defects would make the
//! gate fire on every healthy bring-up and teach a reader to ignore it.
//!
//! Each invariant therefore states the condition under which it becomes
//! *judgeable*, and the three states are kept distinct:
//!
//!   * `not_armed`  — the run has not yet reached the point where this can be
//!                    assessed. Says nothing.
//!   * `satisfied`  — armed, assessed, and holding.
//!   * `violated`   — armed, assessed, and failing.
//!
//! A zero from an unarmed invariant and a zero from a violated one are printed
//! differently, because they send a reader to opposite places.
//!
//! ## Owners
//!
//! Every violation names whose defect it is. That is the point of the split:
//! a Rosette-owned violation means Rosette failed to substantiate something the
//! application legitimately needs, and an emulator-owned one means the
//! application is not behaving in a way Rosette can host. Both stop the run;
//! they send the reader to different code.

const std = @import("std");

pub const schema_version: u16 = 8;

/// The runtime phase that makes a missing notifier actionable.
///
/// A host worker can legitimately park before the guest has retired its first
/// instruction. At that point "no notifier observed" is an incomplete
/// observation, not proof that the worker is waiting on a lost signal. The
/// runtime still records the wait and prints it, but the strict liveness
/// invariant is not armed until the application-side execution boundary has
/// been crossed. Once guest execution or guest GPU activity is proven, the
/// same evidence is actionable and the fault policy applies normally.
pub const LivenessScope = enum(u8) {
    pre_guest_startup,
    guest_execution,
    gpu_activity,

    pub fn label(self: LivenessScope) []const u8 {
        return switch (self) {
            .pre_guest_startup => "pre-guest-startup",
            .guest_execution => "guest-execution",
            .gpu_activity => "gpu-activity",
        };
    }

    pub fn notifierChecksArmed(self: LivenessScope) bool {
        return self != .pre_guest_startup;
    }
};

pub const Owner = enum(u8) {
    /// Rosette failed to substantiate, account for, or hand over something.
    rosette_harness,
    /// The hosted emulator did something Rosette cannot host, or failed to do
    /// something it said it would.
    emulator_host,
    /// The guest title itself.
    guest_title,
    /// The host driver or operating system.
    host_driver,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .rosette_harness => "rosette:harness",
            .emulator_host => "emulator:host",
            .guest_title => "guest:title",
            .host_driver => "host:driver",
        };
    }

    /// Ordering for the tiebreak when several invariants are violated at the
    /// same checkpoint. Rosette's own defects come first: one of them may be
    /// what produced the others, and fixing a symptom whose cause is on this
    /// side of the boundary wastes a run.
    pub fn rank(self: Owner) u8 {
        return switch (self) {
            .rosette_harness => 0,
            .host_driver => 1,
            .emulator_host => 2,
            .guest_title => 3,
        };
    }
};

/// What kind of failure this is, so a reader can tell a missing handoff from a
/// broken one without reading the invariant's prose.
pub const Class = enum(u8) {
    /// Something crossed into Rosette that Rosette did not account for.
    ownership,
    /// A boundary the two sides are supposed to negotiate was never offered,
    /// or was offered and never completed.
    handoff,
    /// Rosette produced something on the application's behalf.
    substitution,
    /// A thread, a signal or a queue stopped making progress.
    liveness,
    /// A capability was exercised and did not work.
    capability,
    /// A cost that grows without bound.
    pressure,
    /// The hosted application reported its own failure.
    anomaly,

    pub fn label(self: Class) []const u8 {
        return switch (self) {
            .ownership => "ownership",
            .handoff => "handoff",
            .substitution => "substitution",
            .liveness => "liveness",
            .capability => "capability",
            .pressure => "pressure",
            .anomaly => "anomaly",
        };
    }
};

pub const Invariant = enum(u8) {
    /// Every forwarding into Rosette's window was one Rosette has semantics
    /// for, from a domain that owns it.
    window_forwarding_accounted,
    /// Every frame the window put on screen has a custody record. A window
    /// that shows pixels nothing took custody of cannot say who put them
    /// there.
    presented_frames_in_custody,
    /// Every swap boundary the emulator reached was offered to the window's
    /// gate. If the emulator swaps and Rosette never gated it, the two are not
    /// interoperating — they are running past each other.
    swap_boundary_offered,
    /// Once the presenter is up and the emulator has consumed draws, some
    /// producer must have published a frame. "No producer has ever published"
    /// past that point means the output handoff is not connected.
    guest_output_handoff_connected,
    /// Nothing is parked forever on an object nothing has ever signalled.
    no_never_notified_park,
    /// A mature wait/signal pair is cycling without independent progress. A
    /// matched count is not proof of a working handshake: the pair can wake
    /// one another forever while the graphics boundary remains untouched.
    no_stalled_wait_handshake,
    /// A wait that only ever times out is not a pump. Something is supposed to
    /// signal it.
    wait_receives_signals,
    /// No capability was exercised and found not to work.
    no_unsatisfied_capability,
    /// Rosette did not stand in for the application. A substitution that
    /// actually fired means the run advanced on Rosette's output rather than
    /// the application's, and every conclusion drawn from it is about Rosette.
    no_harness_substitution,
    /// The translation cache reaches a steady state instead of evicting live
    /// entries forever.
    translation_cache_converges,
    /// The anomaly ledger is empty. Today that means the hosted emulator did
    /// not assert; the ledger also holds invalid frees, declined library calls,
    /// unresolved imports and recovered faults, and every one of those is a
    /// thing the run should stop for.
    no_recorded_anomaly,
    /// Nothing is waiting on an object that has no notifier at all.
    ///
    /// Distinct from `no_never_notified_park`, which measures how *long* a
    /// park has lasted. This one is about the object: waiters chose it, so
    /// something intended to signal it, and if no code has ever raised it the
    /// signaller is missing rather than late.
    every_waiter_has_a_notifier,
    /// Every parked thread states why it is parked. A wait Rosette cannot
    /// account for is one nobody can be asked about.
    every_park_has_a_reason,
    /// Every framework event carries exactly one master owner, with the hosted
    /// subsystem recorded beneath it. Two master owners in one process is how
    /// two accounts of the same fact drift apart while neither looks wrong.
    single_master_owner,
    /// Every boundary the run has reached has an account from at least one
    /// side, and the two agree wherever both gave one.
    every_boundary_substantiated,
    /// No guest texture format is being served by a host/loader pair that
    /// reads its bits as something else or leaves a required conversion
    /// unverified. A signed format handed to an unsigned one with the unsigned
    /// loader is not a degraded texture, it is a different image.
    no_reinterpreting_texture_format,
    /// Once the host capability ladder has stopped moving, every critical
    /// capability must have a satisfied record. Unknown is not permission:
    /// Rosette must not admit a hosted application past the evidence boundary
    /// while a critical prerequisite is still unproven.
    all_critical_capabilities_proven,
    /// A critical capability that answers calls but does not prove its job is
    /// not acceptable at the admission boundary. This is separate from the
    /// completeness rule so a native diagnostic present cannot hide behind an
    /// otherwise healthy coverage percentage.
    no_degraded_critical_capability,
    /// Live PM4 input must be structurally safe and covered by the known
    /// Xenos register vocabulary. Retained inspection is excluded: old bytes
    /// can explain state, but cannot prove that live input was safe.
    no_unverified_pm4_input,
    /// Every mandatory cross-subsystem ordering that became judgeable held.
    /// Raw counters cannot satisfy this invariant: the mandatory-order ledger
    /// must have a retained, domain-correct event for both sides of the rule.
    no_mandatory_order_violation,
    /// GPU pre-initialization never established a dependent element before its
    /// prerequisite. This is the admission firewall for synthetic and host
    /// GPU dispatch: once an interrupt has entered before the title registered
    /// its callback, continuing would make every later completion ambiguous.
    no_gpu_preinitialization_order_inversion,
    /// No fact that two of Rosette's own counters measure is being reported
    /// from the counter that is demonstrably short.
    ///
    /// A monotone quantity has a floor: the largest count any witness stated.
    /// A witness below it is undercounting, and whether that is a defect
    /// depends on its carrier. A throttled breadcrumb may be short; an armed
    /// instruction-pointer tracepoint may not. When the second kind is short,
    /// every absence it has reported is a fact about Rosette's observation and
    /// not about the mechanism — and reports built on those absences name the
    /// wrong owner with full confidence.
    no_undercounting_observer,
    /// A bounded manual-reset poll is receiving signals, or the run is still
    /// making the progress that would explain why it is not.
    ///
    /// Kept deliberately separate from `wait_receives_signals`, which excludes
    /// bounded polls. That exclusion is right on its own terms: a finite
    /// timeout is a completed guest wait, and a title that polls while doing
    /// other work is behaving normally. What the exclusion could not see is a
    /// poll that has expired a hundred and twelve times, received nothing, and
    /// sits beside a ring producer that published once and has been silent for
    /// four billion steps. That is not a poll — it is the consumer half of a
    /// handshake whose producer never ran, and every finite expiry is the same
    /// non-event counted again.
    bounded_poll_receives_signals,
    /// The native presenter did not merely lack guest pixels: its own native
    /// bring-up or device lifetime entered a terminal failure. Retryable
    /// surface backpressure and swapchain rebuilds are deliberately excluded.
    no_presenter_failure,
    /// A console-owned platform value was still unresolved, arrived after its
    /// consumer, diverged from the owner's value, or failed through an
    /// unresolved storage refusal once the consumer boundary was observed.
    /// Owner-rule refusals for title-owned or already-populated values are not
    /// this finding.
    no_actionable_provisioning_refusal,
    /// The wait-handshake policy itself classified an observed object as a
    /// fault. A refused synthetic guest wake is a protection decision and is
    /// not a fault by itself.
    no_actionable_wait_policy_fault,
    /// The application controller emitted a decision whose host authority or
    /// evidence preconditions contradicted the immutable sample it inspected.
    /// This is a Rosette safety violation: applying such a decision could make
    /// the host mutate state on behalf of the guest or hide a missing boundary.
    no_invalid_application_controller_decision,
    /// A readable, decisive execution profile still contains samples the
    /// classifier or symbol resolver could not account for. Continuing would
    /// make the dominant-region conclusion stronger than its evidence.
    no_unclassified_execution_profile,
    /// A swap-contract stage whose causal prerequisites are all met has never
    /// had a single one of its probes attempted, while other probes on the
    /// same driver have run many times. That is a wiring gap in Rosette, and
    /// every zero the contract reports at or below that stage is Rosette's
    /// silence being read as the title's absence.
    no_unprobed_reachable_stage,
    /// A reachable swap-contract stage was probed and the probe read nothing,
    /// for a reason Rosette can remove without the guest or the emulator doing
    /// anything: the probe is not wired to a route, or it reads a counter no
    /// source ever writes. The contract's own verdict already says this is
    /// "Rosette's to close today"; unlike an unprobed stage, the probe ran and
    /// reported honestly, and the gap is still Rosette's.
    no_rosette_closable_starvation,
    /// The measured guest-time rate has fallen below the rate declared for the
    /// run after the startup settling window. Continuing only moves the
    /// watchdog farther away from the stage the run was started to measure.
    no_run_budget_deficit,
    /// The host wait-for graph has a deadlock finding with enough causal
    /// evidence to stop. NEVER_NOTIFIED remains an observation until a guest
    /// obligation or a fully frozen run makes it causal; this gate is for the
    /// stronger all-notifiers-parked, producer-terminated and mature-cycle
    /// findings.
    no_proven_deadlock,
    /// An essential component was used while it was still unproven, or was
    /// exercised and failed. Continuing would make every downstream result
    /// depend on an unchecked boundary; the readiness ledger is the authority
    /// for this decision.
    no_unproven_essential_component,
    /// Every required core monotone witness has an independent agreeing
    /// observer. This is deliberately stricter than the undercount gate:
    /// explained, weak, and single-witness readings are still observation debt
    /// when Rosette is about to make a closed graphics claim.
    all_required_witnesses_corroborated,
    /// Two live observers of one claim disagree about the present, and the
    /// losing source is still repeating its value after being contradicted.
    /// A superseded claim is deliberately not this: there the losing sources
    /// went quiet, so the newest reading is current and the older ones are
    /// stale snapshots a reader must not quote. A contested one has no current
    /// reading at all, and every conclusion drawn from either side is unsound.
    no_contested_claim,
    /// A classifier declined a raw value that a conclusion downstream needed,
    /// and went on declining it. Running longer cannot produce the answer: the
    /// answer is a case statement nobody has written, so the run would reach
    /// the same frontier for the same reason however long it continued. This
    /// is the gate that turns "stuck" from a feeling into a stop with the
    /// missing value printed beside it.
    no_settled_unknown_mapping,
    /// The boundary the frontier names as the blocker is armed, was reached on
    /// none of its addresses, and no independent observer agrees that it never
    /// happened.
    ///
    /// A frontier directs everything downstream of it — which subsystem gets
    /// investigated, which owner is blamed, which week is spent. It is built on
    /// instruction-pointer tracepoints, which are exact for the address they
    /// are armed on and blind everywhere else. A boundary armed on one of six
    /// candidate addresses reports `never crossed` for a call that happened,
    /// and the frontier then points at a subsystem that is working. That is not
    /// hypothetical: on 2026-09-05 `VdQueryVideoMode` read never-crossed at
    /// step 2.1B while the emulator's own breadcrumb in the same log said
    /// `called (count=1)`.
    ///
    /// A negative this load-bearing needs two observers. Without one the run is
    /// about to spend its next week on a frontier it cannot substantiate.
    frontier_boundary_corroborated,

    pub fn label(self: Invariant) []const u8 {
        return switch (self) {
            .window_forwarding_accounted => "window-forwarding-accounted",
            .presented_frames_in_custody => "presented-frames-in-custody",
            .swap_boundary_offered => "swap-boundary-offered",
            .guest_output_handoff_connected => "guest-output-handoff-connected",
            .no_never_notified_park => "no-never-notified-park",
            .no_stalled_wait_handshake => "no-stalled-wait-handshake",
            .wait_receives_signals => "wait-receives-signals",
            .no_unsatisfied_capability => "no-unsatisfied-capability",
            .no_harness_substitution => "no-harness-substitution",
            .translation_cache_converges => "translation-cache-converges",
            .no_recorded_anomaly => "no-recorded-anomaly",
            .every_waiter_has_a_notifier => "every-waiter-has-a-notifier",
            .every_park_has_a_reason => "every-park-has-a-reason",
            .single_master_owner => "single-master-owner",
            .every_boundary_substantiated => "every-boundary-substantiated",
            .no_reinterpreting_texture_format => "no-reinterpreting-texture-format",
            .all_critical_capabilities_proven => "all-critical-capabilities-proven",
            .no_degraded_critical_capability => "no-degraded-critical-capability",
            .no_unverified_pm4_input => "no-unverified-pm4-input",
            .no_mandatory_order_violation => "no-mandatory-order-violation",
            .no_gpu_preinitialization_order_inversion => "no-gpu-preinitialization-order-inversion",
            .no_undercounting_observer => "no-undercounting-observer",
            .bounded_poll_receives_signals => "bounded-poll-receives-signals",
            .no_presenter_failure => "no-presenter-failure",
            .no_actionable_provisioning_refusal => "no-actionable-provisioning-refusal",
            .no_actionable_wait_policy_fault => "no-actionable-wait-policy-fault",
            .no_invalid_application_controller_decision => "no-invalid-application-controller-decision",
            .no_unclassified_execution_profile => "no-unclassified-execution-profile",
            .no_unprobed_reachable_stage => "no-unprobed-reachable-stage",
            .no_rosette_closable_starvation => "no-rosette-closable-starvation",
            .no_run_budget_deficit => "no-run-budget-deficit",
            .no_proven_deadlock => "no-proven-deadlock",
            .no_unproven_essential_component => "no-unproven-essential-component",
            .all_required_witnesses_corroborated => "all-required-witnesses-corroborated",
            .no_contested_claim => "no-contested-claim",
            .no_settled_unknown_mapping => "no-settled-unknown-mapping",
            .frontier_boundary_corroborated => "frontier-boundary-corroborated",
        };
    }

    pub fn owner(self: Invariant) Owner {
        return switch (self) {
            .window_forwarding_accounted,
            .presented_frames_in_custody,
            .swap_boundary_offered,
            .no_harness_substitution,
            .translation_cache_converges,
            // Both of these are Rosette's own bookkeeping. A park Rosette
            // cannot name a reason for is a hole in Rosette's model of the
            // scheduler, not a defect in the thread; and the ownership rule is
            // Rosette's to enforce on its own event stream.
            .every_park_has_a_reason,
            .single_master_owner,
            .every_boundary_substantiated,
            .all_critical_capabilities_proven,
            .no_degraded_critical_capability,
            .no_unverified_pm4_input,
            .no_mandatory_order_violation,
            .no_gpu_preinitialization_order_inversion,
            // Rosette's reading, not the emulator's mechanism. The counter the
            // emulator keeps is the one that turned out to be right.
            .no_undercounting_observer,
            .no_actionable_provisioning_refusal,
            .no_invalid_application_controller_decision,
            .no_unclassified_execution_profile,
            // The probe table and the code that drives it are both Rosette's.
            // A stage the driver never visits is a hole in Rosette's observer,
            // whoever owns the stage itself.
            .no_unprobed_reachable_stage,
            .no_rosette_closable_starvation,
            .no_run_budget_deficit,
            .no_unproven_essential_component,
            .all_required_witnesses_corroborated,
            .no_contested_claim,
            .no_settled_unknown_mapping,
            .frontier_boundary_corroborated,
            => .rosette_harness,
            .guest_output_handoff_connected,
            .no_never_notified_park,
            .no_stalled_wait_handshake,
            .wait_receives_signals,
            .no_recorded_anomaly,
            .every_waiter_has_a_notifier,
            // The emulator chose the host format. Rosette confirmed the
            // preferred one is genuinely absent and found the substitution that
            // preserves the values, so what is left is the emulator's decision.
            .no_reinterpreting_texture_format,
            // A capability that was exercised and did not work is attributed to
            // the hosted application: Rosette negotiated and stood up the host
            // side, and the ladder measures whether the application's use of it
            // works. Which capability failed decides where to look, and the
            // critical-gap list names it and its layer — a genuine host-driver
            // defect surfaces as a Vulkan or Metal failure elsewhere, not here.
            .no_unsatisfied_capability,
            // Same reasoning as `wait_receives_signals`: Rosette observed the
            // poll correctly; what is missing is the signaller.
            .bounded_poll_receives_signals,
            .no_actionable_wait_policy_fault,
            .no_proven_deadlock,
            => .emulator_host,
            .no_presenter_failure => .host_driver,
        };
    }

    pub fn class(self: Invariant) Class {
        return switch (self) {
            .window_forwarding_accounted, .presented_frames_in_custody => .ownership,
            .swap_boundary_offered, .guest_output_handoff_connected => .handoff,
            .no_harness_substitution => .substitution,
            .no_never_notified_park,
            .no_stalled_wait_handshake,
            .wait_receives_signals,
            .every_waiter_has_a_notifier,
            => .liveness,
            .every_park_has_a_reason => .liveness,
            .single_master_owner => .ownership,
            .every_boundary_substantiated => .handoff,
            .no_reinterpreting_texture_format => .capability,
            .all_critical_capabilities_proven,
            .no_degraded_critical_capability,
            .no_unverified_pm4_input,
            => .capability,
            .no_mandatory_order_violation => .handoff,
            .no_gpu_preinitialization_order_inversion => .handoff,
            .no_undercounting_observer => .ownership,
            .bounded_poll_receives_signals => .liveness,
            .no_unsatisfied_capability => .capability,
            .translation_cache_converges => .pressure,
            .no_recorded_anomaly => .anomaly,
            .no_presenter_failure => .capability,
            .no_actionable_provisioning_refusal => .ownership,
            .no_actionable_wait_policy_fault => .liveness,
            .no_invalid_application_controller_decision => .ownership,
            .no_unclassified_execution_profile => .ownership,
            .no_unprobed_reachable_stage => .ownership,
            .no_rosette_closable_starvation => .ownership,
            .no_run_budget_deficit => .pressure,
            .no_proven_deadlock => .liveness,
            .no_unproven_essential_component => .ownership,
            .all_required_witnesses_corroborated => .ownership,
            .no_contested_claim => .ownership,
            .no_settled_unknown_mapping => .ownership,
            .frontier_boundary_corroborated => .ownership,
        };
    }

    /// What a reader should do about it. Written as an instruction rather than
    /// a description, because a gate that stops a run owes the reader a next
    /// step and not a restatement of the counter that tripped it.
    pub fn remedy(self: Invariant) []const u8 {
        return switch (self) {
            .window_forwarding_accounted => "substantiate the forwarding in native_window_runtime.handleObjcMessage, or state why this domain may make it; the WINDOW ADMISSION detail lines name the selector and the actor",
            .presented_frames_in_custody => "route the presentation through the custody ledger before it reaches the drawable; a frame that skipped custody is one nobody can attribute afterwards",
            .swap_boundary_offered => "the emulator reached a swap boundary that refreshWindowSwapAdmission never offered to the gate; find why the boundary's evidence did not reach it, because the window is presenting without deciding",
            .guest_output_handoff_connected => "the presenter is up and a genuine guest output opportunity was observed, but no producer has published a frame; read the target-backed draw/resolve evidence, GUEST FRAME SOURCE and GUEST FRONT BUFFER",
            .no_never_notified_park => "a thread is parked on an object nothing has ever raised; find the code that should signal it and confirm that code ran at all, rather than assuming a late signal",
            .no_stalled_wait_handshake => "a mature wait/signal pair is cycling without independent progress; inspect the named waiter and signaller continuations and the causal boundary they are supposed to advance, and do not inject a synthetic wake",
            .wait_receives_signals => "a wait subject has only ever timed out; it is not a pump, it is a signal that never arrives — find the intended signaller",
            .no_unsatisfied_capability => "a capability was exercised and did not work; the critical-gap list names it and its layer",
            .no_harness_substitution => "the run advanced on Rosette's own output rather than the application's; every conclusion drawn past this point describes Rosette. Disable the substitution or accept that the run is measuring the harness",
            .translation_cache_converges => "the decode cache lost actionable reusable work. Read TRANSLATION ECONOMICS: compulsory first-touch fills are unavoidable, cold evictions are deferred working-set evidence, and the recurring actionable classes are reusable conflicts, stale bytes, or coarse-flush collateral. The cache-pressure page list names the addresses; the fix is capacity, a better mapping, or separating immutable image code from mutable JIT code",
            .no_recorded_anomaly => "the anomaly ledger or pause-causality ledger recorded a defect; read the exact ledger entry before continuing",
            .every_waiter_has_a_notifier => "a thread is waiting on an object no code has ever raised. Waiters chose that object, so something intended to signal it — find that code and confirm it ran at all, rather than waiting for a signal that is not late but absent",
            .every_park_has_a_reason => "a thread is parked and Rosette cannot say why. That is a hole in Rosette's model of the wait, not a defect in the thread: teach the scheduler to name this wait before drawing any conclusion from it",
            .single_master_owner => "a framework event carries an ownership pair the contract does not permit. Rosette is the only master owner of the process; a hosted subsystem substantiates its own truth beneath it, and two masters is how two accounts of one fact drift apart",
            .no_reinterpreting_texture_format => "a signed guest texture format is being served by a host/loader pair that Rosette cannot prove preserves signed values. An unsigned reinterpretation reads every negative component as a large positive one, while a substituted format without an explicit conversion loader is not admitted. The TEXTURE FORMAT SUPPORT report names the host format and loader contract",
            .every_boundary_substantiated => "a boundary has no account from either side, or has two that disagree. NEVER ENTERED on its own is not this: it becomes this only when Rosette also has nothing to say about the same question",
            .all_critical_capabilities_proven => "the capability ladder has stopped improving while one or more critical capabilities remain unproven. Keep the application outside Rosette's admitted window until every critical entry is satisfied; the HOST CONTRACT COVERAGE critical-gap lines name the exact entries",
            .no_degraded_critical_capability => "a critical capability answered calls without proving that it performed its job. Do not treat a diagnostic/native present, synthetic submission or other partial path as application graphics; the HOST CONTRACT COVERAGE entry names the degraded capability",
            .no_unverified_pm4_input => "live PM4 input contained a packet, indirect-buffer, or register condition Rosette cannot prove safe. Read the PM4 RUNTIME EVIDENCE counters and PM4 FAULT/register detail; add the missing Xenos semantics before admitting this path",
            .no_mandatory_order_violation => "the mandatory-order contract observed a required GPU or kernel event after its dependant. Read MANDATORY ORDER and its retained lead-up, then fix the producer ordering or the observer domain before admitting the run",
            .no_gpu_preinitialization_order_inversion => "GPU pre-initialization established a dependent element before its prerequisite. Read GPU PRE-INITIALIZATION ORDERING INVERSION, fix the producer or observer ordering, and do not dispatch a synthetic or host GPU interrupt before the title callback registration is proven",
            .no_undercounting_observer => "an observer that sees every occurrence is reporting fewer than another observer of the same fact, and has been for longer than the sampling window explains. Read MONOTONE WITNESS: it names the subject, the floor, who set it and who is short. Repair the short observer — a tracepoint armed on the wrong address, a parser reading the wrong line, a ledger scoped to the wrong domain — before quoting any absence it has reported",
            .bounded_poll_receives_signals => "a bounded manual-reset poll has expired repeatedly, received no signal at all, and the ring producer beside it has published nothing for the whole window. Read RUN INTEGRITY WAIT EVIDENCE for the object and handle, find the code that is supposed to set that event, and confirm it was reached — a finite timeout expiring is not the title making progress, it is the same non-event counted again. Do not synthesise the signal",
            .no_presenter_failure => "the native presenter entered a non-retryable bring-up or device failure. Read the native presenter stage, VkResult, adapter, and last frame report; surface_not_presentable and swapchain_failed remain retryable and are not this finding",
            .no_actionable_provisioning_refusal => "a console-owned platform value was not established in time, was contested, or remains blocked by an unresolved storage refusal. Read PROVISIONING CUSTODY for the resource and consumer step; raw not-harness-owned, already-present, and address-unknown refusals are diagnostic unless they leave this custody contract broken",
            .no_actionable_wait_policy_fault => "the wait-handshake policy made a fault decision for an observed synchronization object. Read WAIT HANDSHAKE POLICY and the matching wait-graph object; a refused synthetic guest wake or a caution is protection, not proof of a broken wake path",
            .no_invalid_application_controller_decision => "the application controller emitted an internally inconsistent or unauthorized action. Read the retained controller decision and sample, then repair the evidence/ownership guard before allowing host work or guest-boundary conclusions to proceed",
            .no_unclassified_execution_profile => "a readable and decisive execution profile still contains unclassified or unresolved-symbol samples. Read the retained profile witnesses, extend the region/symbol classifier, and do not treat the dominant region as a complete explanation until that observation debt is gone",
            .no_unprobed_reachable_stage => "a swap-contract stage with every causal prerequisite met has never had one of its probes attempted, while probes on the same driver have run many times. Read VD SWAP TRACE for the stage and its probe rows: every one reads attempts=0. Wire the probe at its call site. Until then the contract is reporting a hole in Rosette as an absence in the title, and no zero at or below that stage means anything",
            .no_rosette_closable_starvation => "a reachable swap-contract stage was probed and read nothing for a reason Rosette owns: the probe is unwired on this route, or the counter it reads has never been written by any source. Read VD SWAP TRACE for the stage, its deciding probe and the recorded cause. Wire the probe or connect the counter; nothing is needed from the guest or the emulator, and until it is closed the zero below that stage is Rosette's silence rather than the title's absence",
            .no_run_budget_deficit => "the settled run is below its declared guest-millisecond throughput budget. Read RUN BUDGET and the phase table, fix the dominant host-time consumer, and do not let a watchdog turn a measured reachability failure into an apparent hang",
            .no_proven_deadlock => "the deadlock predictor has a causal deadlock finding after the guest boundary. Read DEADLOCK PREDICTOR for the exact object, waiter and notifier roster; repair the producer or wait-for edge, and do not inject a synthetic wake to hide it",
            .no_unproven_essential_component => "an essential component was used before its readiness proof, or its proof failed. Read COMPONENT READINESS for the component, first-use step and proof obligation; repair that boundary before trusting any downstream GPU or scheduler result",
            .frontier_boundary_corroborated => "the boundary the frontier blames is armed, was reached on none of its armed addresses, and nothing else agrees it never happened. Read the gpu-boundary row for addresses(armed/reached): reached=0 on every armed address means either the title never called it or Rosette armed addresses the call does not pass through, and a tracepoint cannot tell those apart. Add a second observer for this boundary — the emulator's own breadcrumb is usually already in the log — before spending another day downstream of this frontier",
            .no_settled_unknown_mapping => "a classifier has repeatedly declined a raw value that something downstream needed. Read UNKNOWN INVENTORY: the blocking rows name the exact value and the table it belongs in, and the domain's remedy names the file. This is not a condition further running resolves — the run will reach this same frontier for this same reason every time until the case is added, which is what being stuck is",
            .no_contested_claim => "two live observers of the same claim disagree about the present, and the losing one is still repeating its value after being contradicted. Read CLAIM RECONCILIATION for the subject, both sources and their last steps. When the two sit on opposite sides of the host/guest boundary this is a model split rather than a race, and neither reading may be quoted until it is resolved. A superseded claim is not this: there the losing source went quiet and the newest reading is current",
            .all_required_witnesses_corroborated => "the nine required bring-up witness subjects have been observed, but one or more still lacks an independent agreeing observer. Read MONOTONE WITNESS for each subject's finding and carrier; repair or add the missing observer before quoting a closed graphics conclusion",
        };
    }

    /// These invariants cannot be stepped past. An ordering inversion or an
    /// invalid controller authorization is not merely a bad result that can be
    /// documented while the run continues: it means a callback, GPU dependency
    /// or host action was allowed to act against a state that did not exist.
    /// Warn/observe and allow-list controls remain useful for ordinary findings,
    /// but must not reopen either admission hole.
    pub fn nonBypassable(self: Invariant) bool {
        return self == .no_gpu_preinitialization_order_inversion or
            self == .no_invalid_application_controller_decision or
            self == .no_unproven_essential_component;
    }
};

pub const invariant_count: usize = @typeInfo(Invariant).@"enum".fields.len;

pub const State = enum(u8) {
    /// The run has not reached the point where this can be assessed.
    not_armed,
    satisfied,
    violated,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .not_armed => "not-armed",
            .satisfied => "satisfied",
            .violated => "violated",
        };
    }
};

/// The measurements every invariant is decided from.
///
/// Deliberately a flat struct of counters rather than a pointer to the runtime:
/// a decision assembled from live ledgers cannot be replayed, and every one of
/// these has to be reproducible in a test that has no window, no guest and no
/// emulator.
pub const Observation = struct {
    step: u64 = 0,

    // Window admission.
    window_forwardings: u64 = 0,
    window_unaccountable: u64 = 0,

    // Frame custody.
    frames_presented_to_window: u64 = 0,
    frames_in_custody: u64 = 0,
    /// Presentation counters split by provenance. A diagnostic Metal clear is
    /// a real host event, but it is not guest output and must never disappear
    /// into the aggregate custody count.
    authentic_frames_presented: u64 = 0,
    host_frames_presented: u64 = 0,
    diagnostic_frames_presented: u64 = 0,
    /// Guest Vulkan present requests that the native driver accepted. This is
    /// an enqueue edge, not proof that the GPU executed the work.
    native_present_requests: u64 = 0,
    /// Guest Vulkan present requests followed by a host queue/fence completion
    /// edge. This is still not scan-out proof, but it is the minimum hardware
    /// witness Rosette accepts before promoting a request to completed work.
    native_gpu_completions: u64 = 0,

    // Swap handoff.
    swap_boundaries_reached: u64 = 0,
    swap_boundaries_offered: u64 = 0,

    // Output handoff.
    presenter_ready: bool = false,
    /// The native presenter was actually attempted. A host with no layer or
    /// loader attempt has not reached this boundary and stays unarmed.
    presenter_attempted: bool = false,
    /// Terminal native presenter failures only. Retryable surface backpressure
    /// and swapchain rebuild states are intentionally excluded.
    presenter_nonretryable_failures: u64 = 0,
    draws_consumed: u64 = 0,
    /// A draw observed in a retained PM4 batch is not enough to arm this gate.
    /// This count is restricted to live draws with an explicit, writable
    /// output target.
    renderable_draws_observed: u64 = 0,
    render_target_state_observed: bool = false,
    render_target_output_ready: bool = false,
    draw_completion_signals: u64 = 0,
    color_resolve_observations: u64 = 0,
    guest_swap_boundaries: u64 = 0,
    guest_vdswap_packets_encoded: u64 = 0,
    /// Set by the process only from the shared Xenia GPU observation contract.
    /// The granular fields above are retained so a trace can audit that input.
    guest_output_opportunity_observed: bool = false,
    frames_published_by_any_producer: u64 = 0,
    /// Steps since the producer last made progress. The handoff is only judged
    /// once the producer has been quiet long enough that "it is still coming"
    /// stops being the explanation.
    producer_quiet_steps: u64 = 0,

    // Liveness.
    longest_never_notified_park_steps: u64 = 0,
    /// A wait subject that has timed out repeatedly and never been signalled.
    unsignalled_wait_timeouts: u64 = 0,
    /// Identity of the timeout-only subject that supplied the maximum above.
    /// Zero means the aggregate has not selected one. Keeping the identity in
    /// the immutable observation prevents a later report from guessing which
    /// object the gate meant when several wait ledgers disagree.
    unsignalled_wait_object: u64 = 0,
    unsignalled_wait_handle: u32 = 0,
    unsignalled_wait_type: u32 = 0,
    unsignalled_wait_waits: u64 = 0,
    unsignalled_wait_signals: u64 = 0,
    unsignalled_wait_first_step: u64 = 0,
    unsignalled_wait_last_step: u64 = 0,
    /// Finite manual-reset polls are deliberately excluded from the
    /// unbounded-wait fault above, but they remain part of the immutable
    /// observation so a report cannot make that exclusion look like missing
    /// evidence.
    bounded_timeout_subjects: u64 = 0,
    bounded_timeout_attempts: u64 = 0,
    bounded_timeout_object: u64 = 0,
    bounded_timeout_handle: u32 = 0,
    bounded_timeout_ms: i64 = 0,
    /// Signals the selected bounded subject has received. A poll that is
    /// consuming signals is a poll; one that has received none is a consumer
    /// waiting on a producer.
    bounded_timeout_signals: u64 = 0,
    /// When the selected bounded subject first and last polled. The window
    /// between them is what the producer's silence is measured against.
    bounded_timeout_first_step: u64 = 0,
    bounded_timeout_last_step: u64 = 0,
    /// The selected poll is only actionable after the synchronization
    /// registry has named the object's role, creator and expected notifier.
    /// Repeated expiry alone cannot distinguish an idle/title-local poll from
    /// a GPU completion contract.
    bounded_timeout_notifier_proven: bool = false,
    /// Independent progress observed between the first and newest expiry of
    /// the selected poll. A finite poll returning STATUS_TIMEOUT while another
    /// pipeline axis advances is a working pump, not a stuck consumer.
    bounded_timeout_other_progress: bool = false,
    /// Whether the ring producer has published at all. `producer_quiet_steps`
    /// is measured from the last advance, so on a run where the ring has never
    /// started it equals the whole run and reads as a long silence from step
    /// one. A producer that has never published is a different finding with
    /// its own gates, and this one must not borrow its number.
    ring_producer_published: bool = false,

    // Independent wait-graph evidence. These values are deliberately copied
    // from the graph summary rather than inferred from the timeout aggregate:
    // a matched handshake that never advances is a different failure from an
    // object that is never signalled, and neither may hide the other.
    wait_graph_events: u64 = 0,
    wait_graph_objects: u64 = 0,
    wait_graph_stalled_handshakes: u64 = 0,
    wait_graph_cycles: u64 = 0,
    wait_graph_insufficient: u64 = 0,
    wait_graph_dropped_objects: u64 = 0,
    /// Immutable copy of the wait graph's selected blocker. The timeout
    /// subject above is a different ledger and must never be used as a proxy
    /// for this object or its participants.
    wait_graph_blocker_object: u64 = 0,
    wait_graph_blocker_waits: u64 = 0,
    wait_graph_blocker_signals: u64 = 0,
    wait_graph_blocker_waiter_thread: u64 = 0,
    wait_graph_blocker_waiter_pc: u64 = 0,
    wait_graph_blocker_signaller_thread: u64 = 0,
    wait_graph_blocker_signaller_pc: u64 = 0,
    wait_graph_blocker_first_step: u64 = 0,
    wait_graph_blocker_last_step: u64 = 0,
    wait_graph_blocker_participants_dropped: u64 = 0,

    // Application controller.
    /// Number of immutable process samples for which the controller emitted a
    /// decision. A zero count leaves the decision contract unarmed.
    application_controller_decisions: u64 = 0,
    /// Decisions whose host-action or state preconditions contradicted the
    /// sample that produced them. This is a safety fault, not a guest refusal.
    application_controller_contract_violations: u64 = 0,

    // Provisioning custody.
    /// The consumer boundary for tracked console variables was observed.
    /// Before that point, a missing value is incomplete evidence rather than a
    /// failed handoff.
    provisioning_armed: bool = false,
    /// Total refusal attempts, retained to distinguish valid owner-rule
    /// refusals from an actionable custody failure.
    provisioning_raw_refusals: u64 = 0,
    /// Unresolved storage refusals on console-owned resources. The state-level
    /// custody counters remain authoritative; this field makes the refusal
    /// class visible in the trace.
    provisioning_actionable_refusals: u64 = 0,
    provisioning_late: u64 = 0,
    provisioning_diverged: u64 = 0,
    provisioning_contested: u64 = 0,
    provisioning_unprovisioned: u64 = 0,

    // Wait-handshake policy.
    /// At least one observed wait object reached a classified policy decision.
    wait_policy_observed: bool = false,
    /// Decisions whose severity was `.fault`; refused synthetic wakes and
    /// cautions do not increment this count.
    wait_policy_faults: u64 = 0,

    // Capability.
    capabilities_exercised: u64 = 0,
    capabilities_unsatisfied: u64 = 0,
    /// Number of critical capabilities in the model. The status counts below
    /// are not trusted without this total: an omitted status must not look like
    /// a clean surface simply because the omitted counters are zero.
    critical_capabilities_total: u64 = 0,
    /// Critical capabilities whose records are satisfied. Kept separate from
    /// the aggregate counts because supporting capabilities must not make the
    /// critical admission surface look complete.
    critical_capabilities_satisfied: u64 = 0,
    /// Critical capabilities that were exercised but only partially work.
    critical_capabilities_degraded: u64 = 0,
    /// Critical capabilities that were exercised and failed.
    critical_capabilities_unsatisfied: u64 = 0,
    /// Critical capabilities with no proven observation yet. At the strict
    /// closure boundary this is a failure of evidence, not a passing unknown.
    critical_capabilities_untested: u64 = 0,
    /// Steps since the effective capability-progress witness last improved. A
    /// capability the ladder calls `unsatisfied` at step zero is usually one
    /// the run has not had the chance to exercise to completion yet —
    /// "VdSwap has never been entered" is a not-yet, not a defect. The runtime
    /// combines host-coverage improvement with independently accepted guest
    /// compiler/translation progress before filling this field. Once both
    /// progress axes have been quiet for a long window, the run has had its
    /// chance and the remaining failures are findings.
    capability_progress_quiet_steps: u64 = 0,
    /// Last step at which the host-coverage score improved. Kept in the
    /// observation so a terminal trace can show which side supplied the
    /// progress witness rather than exposing only the derived quiet period.
    capability_coverage_progress_step: u64 = 0,
    /// Last step at which a trusted guest/compiler progress counter advanced.
    /// This is not instruction retirement: it is successful guest translation,
    /// a new guest allocation high-water mark, or another host-serviced
    /// counter that a spin cannot manufacture.
    capability_guest_progress_step: u64 = 0,
    /// The maximum of the two progress witnesses above. This is the step from
    /// which `capability_progress_quiet_steps` is measured.
    capability_progress_witness_step: u64 = 0,

    // Substitution.
    harness_substitutions: u64 = 0,

    // Translation pressure.
    /// Runtime-selected evidence mode. The ordinary contract keeps cache
    /// pressure and never-notified parks behind their settling windows so a
    /// warm-up burst or idle worker does not stop a run. The fault-policy
    /// runtime may select this stricter mode after the relevant observer is
    /// armed: proven reusable eviction, executable-byte changes and proven
    /// liveness contradictions are then faults even when an unrelated counter
    /// is still advancing. Cold evictions remain separately observable because
    /// they do not prove reusable work was lost.
    strict_fail_fast: bool = false,
    translation_cache_entries: u64 = 0,
    translation_vacant_fills: u64 = 0,
    translation_conflict_fills: u64 = 0,
    /// A non-empty, never-reused entry displaced by the fill. This is kept
    /// separate from conflicts because a cold working-set stream is fill cost
    /// rather than evidence that reusable translations are fighting for a
    /// set.
    translation_cold_evictions: u64 = 0,
    /// Refills for which the cached source bytes changed. This is stronger
    /// evidence than ordinary pressure and must not disappear merely because
    /// the cache has not reached its steady-state occupancy yet.
    translation_stale_refills: u64 = 0,
    /// Refills caused by a coarse invalidation. Like stale bytes, this is a
    /// cache-integrity finding rather than a normal warm-up miss.
    translation_flush_refills: u64 = 0,
    /// Lookups that hit and missed. The conflict *share* of fills says the
    /// cache never converges; only the hit rate says whether that is costing
    /// the run anything. Both are needed, and the second is what decides.
    translation_hits: u64 = 0,
    translation_misses: u64 = 0,

    // Anomalies.
    recorded_anomalies: u64 = 0,
    /// Defects in the pause-causality ledger are separate from emulator
    /// anomalies. A pause report later disproved by guest progress is an
    /// observer contradiction, not a guest assertion, but it still prevents a
    /// clean run from continuing.
    pause_transaction_defects: u64 = 0,

    // Component readiness.
    /// True once the readiness ledger has observed a proof or a guest use and
    /// can therefore distinguish an unvisited component from an essential
    /// gap.
    component_readiness_armed: bool = false,
    /// Essential components currently used unproven or exercised and broken.
    essential_component_gaps: u64 = 0,

    // Execution profile.
    execution_profile_samples: u64 = 0,
    execution_profile_readable: bool = false,
    execution_profile_decisive: bool = false,
    execution_profile_unclassified: u64 = 0,
    execution_profile_unresolved: u64 = 0,

    // Swap-contract probe coverage.
    /// Stages whose causal prerequisites are all met and for which not one
    /// declared probe has ever been attempted.
    vd_swap_unprobed_reachable_stages: u64 = 0,
    /// The most attempts any single swap probe has recorded. The evidence that
    /// the driver ran at all: a cold ledger has every reachable stage unprobed
    /// and that says nothing, while a ledger where one probe has been called a
    /// hundred times and another never has a probe off the driver's path.
    vd_swap_probe_attempt_floor: u64 = 0,
    /// Reachable stages starved for a cause Rosette can remove on its own —
    /// an unwired probe, or a counter nothing feeds.
    vd_swap_rosette_closable_starvations: u64 = 0,

    // Throughput reachability.
    /// True only after the guest-main execution boundary and enough
    /// post-boundary host time have been observed for the declared rate to be
    /// useful. A process still in loader/static-initializer/Xenia startup must
    /// not fail this gate merely because no guest milliseconds have accrued
    /// yet; the runtime owns the boundary and supplies a scoped measurement.
    run_budget_observed: bool = false,
    /// The run-budget ledger's specific below-budget verdict. Observer-share
    /// and cache-thrashing defects retain their own diagnostics and gates.
    run_budget_deficit: bool = false,
    run_budget_guest_ms_per_host_second: u64 = 0,
    run_budget_required_guest_ms_per_host_second: u64 = 0,
    run_budget_host_seconds: u64 = 0,
    run_budget_guest_ms: u64 = 0,

    // Deadlock evidence.
    /// The predictor saw a deadlocked classification (including the weaker
    /// NEVER_NOTIFIED finding). This is retained for the trace even when the
    /// stronger causal gate below is not armed.
    deadlock_observed: bool = false,
    /// True only for all-notifiers-parked, notifiers-terminated, or a mature
    /// wait cycle. A never-notified idle worker is not enough by itself.
    deadlock_proven: bool = false,
    /// Numeric value of deadlock_predictor.Finding at the selected witness.
    /// Keeping the contract independent of that diagnostics module avoids a
    /// package dependency while preserving the exact finding in reports.
    deadlock_finding: u8 = 0,
    deadlock_waiters: u64 = 0,
    deadlock_park_steps: u64 = 0,

    // Liveness, ownership and substantiation.
    /// The application boundary that makes a missing notifier actionable. A
    /// pre-guest-startup wait is retained in the diagnostics but is not enough
    /// to terminate a run that has not reached the hosted application yet.
    liveness_scope: LivenessScope = .pre_guest_startup,
    /// Objects with waiters and no notifier at all, past the liveness
    /// classifier's own stall threshold.
    waiters_without_a_notifier: u64 = 0,
    /// The subset of the raw host-pthread census for which Rosetta has proved
    /// a causal obligation to notify. A parked POSIX worker by itself is not
    /// a guest deadlock: it may simply be an idle worker waiting for future
    /// work. Keep the raw count for diagnostics, but only this subset can arm
    /// a fatal liveness invariant.
    actionable_waiters_without_a_notifier: u64 = 0,
    /// True only when a guest wait, a classified synchronization object, or a
    /// genuinely frozen run proves that the raw silence is causally relevant.
    liveness_obligation_proven: bool = false,
    /// Threads parked with no reason Rosette can name.
    parks_without_a_reason: u64 = 0,
    /// Framework events whose master/subowner pair the contract refuses.
    ownership_violations: u64 = 0,
    /// Boundaries with no account from either side, and boundaries with two
    /// accounts that disagree.
    unsubstantiated_boundaries: u64 = 0,
    diverged_boundaries: u64 = 0,
    /// Boundaries whose two numeric answers use incompatible measurement
    /// domains. This is separate from a same-domain value disagreement, but it
    /// is equally fatal: the gate must never choose between unlike counters.
    measurement_drift_boundaries: u64 = 0,
    /// True once at least one boundary has been reached, so the substantiation
    /// ledger has something to say.
    substantiation_armed: bool = false,

    // Live PM4 quality. These values are copied from the Xenos runtime's
    // live-only ledger; retained/replayed observations must not arm or satisfy
    // the strict packet boundary.
    pm4_packets_observed: u64 = 0,
    pm4_packets_executed: u64 = 0,
    pm4_packet_errors: u64 = 0,
    pm4_invalid_packets: u64 = 0,
    pm4_unknown_opcodes: u64 = 0,
    pm4_truncated_rings: u64 = 0,
    pm4_indirect_unreadable: u64 = 0,
    pm4_indirect_truncated: u64 = 0,
    pm4_indirect_invalid: u64 = 0,
    pm4_indirect_depth_limited: u64 = 0,
    pm4_indirect_budget_limited: u64 = 0,
    pm4_indirect_cycles: u64 = 0,
    pm4_unclassified_register_writes: u64 = 0,
    pm4_out_of_range_register_writes: u64 = 0,
    pm4_defects: u64 = 0,

    // Mandatory-order evidence. These counters are copied from the live
    // ledger at one integrity snapshot; they are intentionally not inferred
    // from PM4 or callback totals because those aggregates can contain host,
    // diagnostic, or no-effect work.
    mandatory_order_armed: bool = false,
    mandatory_order_active: u64 = 0,
    mandatory_order_violated: u64 = 0,
    mandatory_order_mandatory_violations: u64 = 0,
    mandatory_order_raced: u64 = 0,

    // GPU pre-initialization ordering evidence. The dropped count is part of
    // the decision: a bounded inversion list cannot make an incomplete audit
    // look clean.
    gpu_preinitialization_inversions: u64 = 0,
    gpu_preinitialization_inversions_dropped: u64 = 0,

    /// Guest texture formats the emulator is serving by reinterpretation.
    reinterpreted_texture_formats: u64 = 0,
    /// True once a physical device has actually been asked what it supports.
    /// Before that every format reads absent, which is a fact about the
    /// observer.
    texture_formats_probed: bool = false,

    /// Subjects whose unexplained undercount has outlived the settling window,
    /// plus monotone counters that went backwards. Both are defects in
    /// Rosette's reading rather than in what is being read, and both make
    /// every absence the short observer reported unquotable.
    settled_observer_undercounts: u64 = 0,
    /// True once at least one subject has two witnesses, so the comparison is
    /// possible at all. A single-witness surface is uncorroborated, not
    /// passing, and must not arm this gate.
    monotone_witness_corroboration_possible: bool = false,
    /// True once all nine required bring-up subjects have spoken at least once.
    /// The optional guest-frame subject is not part of this admission boundary.
    monotone_witness_closure_ready: bool = false,
    monotone_witness_required: u64 = 0,
    monotone_witness_observed: u64 = 0,
    monotone_witness_corroborated: u64 = 0,
    monotone_witness_agreement_debt: u64 = 0,
    /// Claims whose observers actively disagree while both remain live.
    claim_reconciliation_contested: u64 = 0,
    /// Claims that have been cross-checked at all. Without one, a zero above
    /// is "nothing was compared", not "everything agreed".
    claim_reconciliation_multi_source: u64 = 0,
    /// Unmapped raw values that a conclusion needed and that have been
    /// consulted often enough to be a certain table gap rather than a
    /// bring-up transient.
    settled_unknown_mappings: u64 = 0,
    /// Whether a frontier boundary exists and is armed at all. Without one
    /// there is no negative to substantiate.
    frontier_boundary_armed: bool = false,
    /// Steps this same boundary has been the frontier.
    ///
    /// A frontier that has just appeared is a run in progress, not a wall. At
    /// step 0 every boundary is armed, reached on none, and spoken about by
    /// nobody — which is the correct state of a run that has not started and
    /// which stopped the 2026-09-06 run at its first checkpoint. The gate below
    /// judges a frontier only once the run has sat at it long enough that "not
    /// yet" has stopped being the explanation. The timer resets whenever the
    /// frontier moves, so a run making boundary progress is never judged.
    frontier_boundary_settled_steps: u64 = 0,
    /// Boundaries crossed anywhere on the watched surface.
    ///
    /// Evidence that the run reached this phase at all and that the tracepoint
    /// set demonstrably fires. With none crossed, the frontier is simply the
    /// first boundary of a phase the guest has not started: on 2026-09-06 the
    /// gate blamed `VdQueryVideoMode` at step 100M while the title was still
    /// inside `XexModule::LoadContinue`, having not finished mapping its own
    /// executable. A frontier ahead of the run is not a wall.
    frontier_boundary_crossed_elsewhere: u32 = 0,
    /// Whether an independent axis — module loads, translation progress,
    /// milestones — moved recently. A run still moving toward the frontier has
    /// not settled at it, however long the frontier has had the same name.
    external_progress_fresh: bool = false,
    /// Armed addresses for the frontier boundary that were ever reached.
    frontier_boundary_addresses_reached: u32 = 0,
    /// Whether any observer other than the tracepoint has spoken about this
    /// boundary. A breadcrumb, a claim, a guest log counter — anything that
    /// did not come from the same instruction-pointer arming.
    frontier_boundary_corroborating_observers: u32 = 0,

    /// Whether any axis that proves progress has advanced since the longest
    /// never-notified park began.
    ///
    /// A thread parked on an object nothing signals *while the rest of the run
    /// advances* is an idle worker. The same thread parked while nothing else
    /// moves is a lost wakeup. Repetition alone cannot tell those apart, which
    /// is why every predictor in this codebase is gated on an independent
    /// progress axis and why this one is too.
    progress_since_never_notified_park: bool = false,
};

/// How long a park has to last before it is a defect rather than an idle
/// worker. One second of emulated time at this run's step rate is far past the
/// point where a signal that was coming would have arrived.
pub const never_notified_park_steps: u64 = 1_000_000_000;

/// The deadlock predictor has already classified a never-notified object as a
/// stalled wait by the time it reaches its own 100M-step window. Strict mode
/// uses that evidence boundary instead of waiting another billion steps while
/// unrelated guest work advances.
pub const strict_never_notified_park_steps: u64 = 100_000_000;

/// How many timeouts a wait may accumulate with no signal at all before it
/// stops being a poll and becomes a signal that never arrives.
pub const unsignalled_timeout_limit: u64 = 32;

/// How long the producer must be quiet before "no frame yet" becomes "no
/// handoff".
pub const output_handoff_quiet_steps: u64 = 1_000_000_000;

/// How many times one swap probe must have been attempted before a *different*
/// stage's total absence of attempts stops being a cold ledger and becomes an
/// unwired probe.
///
/// The refresh that drives every probe runs on the same checkpoint, so a probe
/// on its path accumulates attempts at the same rate as every other. Eight
/// rounds is well past any ordering or first-checkpoint effect and far short of
/// the hundreds a real run accumulates, so the gate arms early enough to be
/// worth having and late enough that a run cannot trip it on the way up.
pub const vd_swap_probe_floor: u64 = 8;

/// Steps a boundary must remain the frontier before its negative is judged.
///
/// Long enough that a run still crossing boundaries is never stopped — the
/// timer resets on every frontier move — and short enough that a genuine wall
/// is named within the first minute rather than after the whole run. Matches
/// the checkpoint cadence, so the gate arms on evidence a reader has already
/// seen printed.
pub const frontier_settle_steps: u64 = 100_000_000;

/// Host seconds that must elapse after the proven guest-main boundary before a
/// measured below-budget rate becomes a reachability failure. Process
/// creation, static initializers and Xenia loader work are outside that
/// boundary, where zero guest milliseconds is expected.
pub const budget_observation_host_seconds: u64 = 10;

/// How long host-capability coverage must stop improving before its remaining
/// failures are findings rather than work still in progress.
pub const capability_progress_quiet_steps: u64 = 1_000_000_000;

/// The conflict share above which the cache is evicting live work rather than
/// filling. Only assessed once every way has been filled at least once.
pub const conflict_pressure_percent: u64 = 50;

/// The hit rate below which conflict-driven eviction is actually costing the
/// run time.
///
/// The conflict share alone is not the finding, and this is the correction the
/// observed run forced. That run reported `conflict=85% converges=NO`, which
/// reads alarming, alongside a 99% hit rate — 1.6 million re-decodes across 6.8
/// billion steps, about two hundredths of one percent of the work. A gate that
/// stopped there would be stopping on a number that is true and costs nothing,
/// and the first thing a reader would do is allow-list it, which devalues every
/// other invariant in this file. Conflicts are the *cause*; the hit rate is the
/// *cost*, and only a cost is worth stopping a run for.
pub const translation_hit_rate_floor: u64 = 95;

/// A stale-byte or flush cause is actionable only when it is a material part
/// of the fill stream. One legitimate JIT publication should be recorded and
/// investigated, but should not make a large healthy image fail the same gate
/// that catches rewrite/flush thrashing.
pub const translation_integrity_dominance_percent: u64 = 25;

fn percentage(part: u64, whole: u64) u64 {
    if (whole == 0) return 0;
    return @intCast((@as(u128, part) * 100) / whole);
}

pub const Judgement = struct {
    state: State = .not_armed,
    /// The measured quantity that decided it, for the report line.
    detail: u64 = 0,

    pub fn violated(self: Judgement) bool {
        return self.state == .violated;
    }
};

pub fn judge(invariant: Invariant, observation: Observation) Judgement {
    return switch (invariant) {
        .window_forwarding_accounted => blk: {
            if (observation.window_forwardings == 0) break :blk .{};
            break :blk .{
                .state = if (observation.window_unaccountable == 0) .satisfied else .violated,
                .detail = observation.window_unaccountable,
            };
        },
        .presented_frames_in_custody => blk: {
            if (observation.frames_presented_to_window == 0) break :blk .{};
            // Custody may legitimately run ahead — a frame is offered before it
            // is presented — but it can never run behind.
            const uncounted = observation.frames_presented_to_window -| observation.frames_in_custody;
            break :blk .{
                .state = if (uncounted == 0) .satisfied else .violated,
                .detail = uncounted,
            };
        },
        .swap_boundary_offered => blk: {
            if (observation.swap_boundaries_reached == 0) break :blk .{};
            const ungated = observation.swap_boundaries_reached -| observation.swap_boundaries_offered;
            break :blk .{
                .state = if (ungated == 0) .satisfied else .violated,
                .detail = ungated,
            };
        },
        .guest_output_handoff_connected => blk: {
            // Three things have to be true before absence means anything: the
            // presenter can accept a frame, the guest has created a genuine
            // output opportunity, and enough time has passed that "it is still
            // coming" is no longer the explanation. A raw draw count is not an
            // output opportunity: retained PM4 inspection and draw packets with
            // no target both produce that count without producing pixels.
            const granular_evidence = observation.renderable_draws_observed != 0 or
                observation.color_resolve_observations != 0 or
                observation.guest_swap_boundaries != 0 or
                observation.guest_vdswap_packets_encoded != 0;
            if (!observation.presenter_ready or
                !observation.guest_output_opportunity_observed or
                !granular_evidence)
                break :blk .{};
            if (observation.producer_quiet_steps < output_handoff_quiet_steps) break :blk .{};
            break :blk .{
                .state = if (observation.frames_published_by_any_producer != 0) .satisfied else .violated,
                .detail = observation.producer_quiet_steps,
            };
        },
        .no_never_notified_park => blk: {
            if (!observation.liveness_scope.notifierChecksArmed()) break :blk .{};
            if (observation.longest_never_notified_park_steps == 0) break :blk .{};
            // The deadlock predictor observes host condvars, so silence alone
            // is deliberately not causal evidence. Require the runtime to
            // prove an obligation before this invariant can arm.
            if (!observation.liveness_obligation_proven or
                observation.actionable_waiters_without_a_notifier == 0)
                break :blk .{};
            if (observation.strict_fail_fast) break :blk .{
                .state = if (observation.longest_never_notified_park_steps < strict_never_notified_park_steps)
                    .satisfied
                else
                    .violated,
                .detail = observation.longest_never_notified_park_steps,
            };
            // Same gate as `every_waiter_has_a_notifier`: a long park beside a
            // run that keeps advancing is a worker that has nothing to do.
            if (observation.progress_since_never_notified_park) break :blk .{
                .state = .satisfied,
                .detail = observation.longest_never_notified_park_steps,
            };
            break :blk .{
                .state = if (observation.longest_never_notified_park_steps < never_notified_park_steps)
                    .satisfied
                else
                    .violated,
                .detail = observation.longest_never_notified_park_steps,
            };
        },
        .no_stalled_wait_handshake => blk: {
            if (!observation.liveness_scope.notifierChecksArmed() or
                observation.wait_graph_events == 0)
                break :blk .{};
            // Dropping an object is itself a failure of evidence. A graph with
            // lost identities cannot certify that no cycle exists.
            if (observation.wait_graph_dropped_objects != 0) break :blk .{
                .state = .violated,
                .detail = observation.wait_graph_dropped_objects,
            };
            if (observation.wait_graph_objects == 0) break :blk .{};
            const mature_objects = observation.wait_graph_objects -|
                observation.wait_graph_insufficient;
            if (mature_objects == 0) break :blk .{};
            if (observation.wait_graph_cycles != 0) break :blk .{
                .state = .violated,
                .detail = observation.wait_graph_cycles,
            };
            if (observation.wait_graph_stalled_handshakes != 0) break :blk .{
                .state = .violated,
                .detail = observation.wait_graph_stalled_handshakes,
            };
            break :blk .{ .state = .satisfied };
        },
        .wait_receives_signals => blk: {
            if (!observation.liveness_scope.notifierChecksArmed() or
                observation.unsignalled_wait_timeouts == 0)
                break :blk .{};
            break :blk .{
                .state = if (observation.unsignalled_wait_timeouts < unsignalled_timeout_limit)
                    .satisfied
                else
                    .violated,
                .detail = observation.unsignalled_wait_timeouts,
            };
        },
        .no_unsatisfied_capability => blk: {
            if (observation.capabilities_exercised == 0) break :blk .{};
            // A capability that is failing while the score is still climbing is
            // work in progress. Judged only once the ladder has stopped moving.
            if (observation.capability_progress_quiet_steps < capability_progress_quiet_steps) break :blk .{};
            break :blk .{
                .state = if (observation.capabilities_unsatisfied == 0) .satisfied else .violated,
                .detail = observation.capabilities_unsatisfied,
            };
        },
        .all_critical_capabilities_proven => blk: {
            if (observation.capabilities_exercised == 0) break :blk .{};
            // Use the same quiet period as the existing capability gate. The
            // two invariants must agree on when the ladder stopped moving, or
            // the report would create an ordering-dependent result drift.
            if (observation.capability_progress_quiet_steps < capability_progress_quiet_steps) break :blk .{};
            if (observation.critical_capabilities_total == 0) break :blk .{};
            const accounted = observation.critical_capabilities_satisfied +|
                observation.critical_capabilities_degraded +|
                observation.critical_capabilities_unsatisfied +|
                observation.critical_capabilities_untested;
            if (accounted != observation.critical_capabilities_total) break :blk .{
                .state = .violated,
                .detail = if (accounted > observation.critical_capabilities_total)
                    accounted - observation.critical_capabilities_total
                else
                    observation.critical_capabilities_total - accounted,
            };
            const unproven = observation.critical_capabilities_degraded +|
                observation.critical_capabilities_unsatisfied +|
                observation.critical_capabilities_untested;
            break :blk .{
                .state = if (unproven == 0) .satisfied else .violated,
                .detail = unproven,
            };
        },
        .no_degraded_critical_capability => blk: {
            if (observation.capabilities_exercised == 0) break :blk .{};
            if (observation.capability_progress_quiet_steps < capability_progress_quiet_steps) break :blk .{};
            if (observation.critical_capabilities_total == 0) break :blk .{};
            break :blk .{
                .state = if (observation.critical_capabilities_degraded == 0) .satisfied else .violated,
                .detail = observation.critical_capabilities_degraded,
            };
        },
        .no_harness_substitution => blk: {
            // Armed from the first step: a substitution that fired is a fact
            // about the run whenever it happens, and there is no window in
            // which it would be acceptable.
            break :blk .{
                .state = if (observation.harness_substitutions == 0) .satisfied else .violated,
                .detail = observation.harness_substitutions,
            };
        },
        .translation_cache_converges => blk: {
            const fills = observation.translation_vacant_fills +|
                observation.translation_conflict_fills +|
                observation.translation_cold_evictions +|
                observation.translation_stale_refills +|
                observation.translation_flush_refills;
            if (fills == 0) break :blk .{};

            // A strict diagnostic run is explicitly trying to catch the
            // first reusable eviction, not decide whether the aggregate hit
            // rate made it expensive. `capacity_conflict` is already proved
            // at the cache fill site: a non-empty entry with a non-zero reuse
            // count was displaced. Stale-byte and coarse-flush refills are
            // equally strong integrity evidence. Do not let nominal cache
            // occupancy or a 99% hit rate turn those facts back into a
            // “warming” report.
            //
            // Cold evictions deliberately do not enter this branch. Their
            // victim had never been reused, and the active victim/static-L2
            // tiers may recover it without another decode. A cold stream is
            // valuable evidence for cache sizing, but this event alone does
            // not prove that reusable work was lost.
            if (observation.strict_fail_fast) {
                if (observation.translation_conflict_fills != 0) break :blk .{
                    .state = .violated,
                    .detail = observation.translation_conflict_fills,
                };
                if (observation.translation_stale_refills != 0) break :blk .{
                    .state = .violated,
                    .detail = observation.translation_stale_refills,
                };
                if (observation.translation_flush_refills != 0) break :blk .{
                    .state = .violated,
                    .detail = observation.translation_flush_refills,
                };
            }

            // Do not let the warm-up occupancy gate hide a proven integrity
            // failure. These are the two causes that the economics contract
            // deliberately keeps distinct from ordinary cache pressure.
            const cold_fills = observation.translation_vacant_fills +|
                observation.translation_cold_evictions;
            const flush_dominant = observation.translation_flush_refills >= cold_fills and
                percentage(observation.translation_flush_refills, fills) >= translation_integrity_dominance_percent;
            const rewrite_dominant = observation.translation_stale_refills >= cold_fills and
                percentage(observation.translation_stale_refills, fills) >= translation_integrity_dominance_percent;
            if (flush_dominant or rewrite_dominant) break :blk .{
                .state = .violated,
                .detail = if (flush_dominant)
                    observation.translation_flush_refills
                else
                    observation.translation_stale_refills,
            };

            // Only judge ordinary pressure once every way has been filled at
            // least once. Before that, conflict counts are a cold cache
            // warming up and the share means nothing by itself.
            if (observation.translation_cache_entries == 0) break :blk .{};
            if (observation.translation_vacant_fills < observation.translation_cache_entries) break :blk .{};
            const lookups = observation.translation_hits + observation.translation_misses;
            if (lookups == 0) break :blk .{};
            const conflict_share = percentage(observation.translation_conflict_fills, fills);
            const hit_rate = (observation.translation_hits * 100) / lookups;
            // Both have to hold. Conflicts name the cause and the hit rate
            // measures whether that cause is costing anything.
            const failing = conflict_share >= conflict_pressure_percent and
                hit_rate < translation_hit_rate_floor;
            break :blk .{
                .state = if (failing) .violated else .satisfied,
                .detail = hit_rate,
            };
        },
        .no_recorded_anomaly => blk: {
            const defects = observation.recorded_anomalies +| observation.pause_transaction_defects;
            break :blk .{
                .state = if (defects == 0) .satisfied else .violated,
                .detail = defects,
            };
        },
        .every_waiter_has_a_notifier => blk: {
            if (!observation.liveness_scope.notifierChecksArmed()) break :blk .{};
            if (observation.waiters_without_a_notifier == 0) break :blk .{ .state = .satisfied };
            // Preserve the raw host wait census for the report, but do not
            // treat an idle/unclassified worker as a required guest producer.
            if (!observation.liveness_obligation_proven or
                observation.actionable_waiters_without_a_notifier == 0)
                break :blk .{};
            if (observation.strict_fail_fast) break :blk .{
                .state = if (observation.longest_never_notified_park_steps < strict_never_notified_park_steps)
                    .satisfied
                else
                    .violated,
                .detail = observation.actionable_waiters_without_a_notifier,
            };
            // Gated on an independent progress axis, like every other predictor
            // here. Three condvars parked from startup in a run that is
            // otherwise advancing are idle workers; the same three in a run
            // that has stopped moving are the finding.
            if (observation.progress_since_never_notified_park) break :blk .{
                .state = .satisfied,
                .detail = observation.actionable_waiters_without_a_notifier,
            };
            break :blk .{
                .state = .violated,
                .detail = observation.actionable_waiters_without_a_notifier,
            };
        },
        .no_reinterpreting_texture_format => blk: {
            if (!observation.texture_formats_probed) break :blk .{};
            break :blk .{
                .state = if (observation.reinterpreted_texture_formats == 0) .satisfied else .violated,
                .detail = observation.reinterpreted_texture_formats,
            };
        },
        .every_park_has_a_reason => blk: {
            break :blk .{
                .state = if (observation.parks_without_a_reason == 0) .satisfied else .violated,
                .detail = observation.parks_without_a_reason,
            };
        },
        .single_master_owner => blk: {
            break :blk .{
                .state = if (observation.ownership_violations == 0) .satisfied else .violated,
                .detail = observation.ownership_violations,
            };
        },
        .every_boundary_substantiated => blk: {
            // The substantiation ledger applies its own grace before it will
            // call a boundary unsubstantiated, so an unarmed reading here means
            // no boundary has been reached at all.
            if (!observation.substantiation_armed) break :blk .{};
            const problems = observation.unsubstantiated_boundaries +|
                observation.diverged_boundaries +|
                observation.measurement_drift_boundaries;
            break :blk .{
                .state = if (problems == 0) .satisfied else .violated,
                // A numeric-domain drift is the most specific account of a
                // result mismatch, followed by a same-domain divergence.
                .detail = if (observation.measurement_drift_boundaries != 0)
                    observation.measurement_drift_boundaries
                else if (observation.diverged_boundaries != 0)
                    observation.diverged_boundaries
                else
                    observation.unsubstantiated_boundaries,
            };
        },
        .no_unverified_pm4_input => blk: {
            // A truncated root header can fail before the packet timeline sees
            // a packet, so defects themselves also arm this invariant.
            if (observation.pm4_packets_observed == 0 and
                observation.pm4_packets_executed == 0 and
                observation.pm4_defects == 0)
                break :blk .{};
            break :blk .{
                .state = if (observation.pm4_defects == 0) .satisfied else .violated,
                .detail = observation.pm4_defects,
            };
        },
        .no_mandatory_order_violation => blk: {
            if (!observation.mandatory_order_armed and
                observation.mandatory_order_mandatory_violations == 0)
                break :blk .{};
            break :blk .{
                .state = if (observation.mandatory_order_mandatory_violations == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.mandatory_order_mandatory_violations,
            };
        },
        .no_gpu_preinitialization_order_inversion => blk: {
            const inversions = observation.gpu_preinitialization_inversions +|
                observation.gpu_preinitialization_inversions_dropped;
            if (inversions == 0) break :blk .{};
            break :blk .{
                .state = .violated,
                .detail = inversions,
            };
        },
        // Only armed once some fact actually has two witnesses. A run whose
        // whole observation surface is single-carrier has nothing to
        // corroborate, and reporting that as satisfied would be the same
        // mistake in the other direction.
        // Three conditions, and all three are needed. The poll has to have
        // expired often enough that a late signal is no longer the
        // explanation; it has to have received nothing at all, because a poll
        // that consumes signals is doing its job; and the producer has to have
        // been quiet across the window, because a poll beside a producer that
        // is still publishing is a consumer keeping up, not a stuck one.
        .bounded_poll_receives_signals => blk: {
            if (!observation.liveness_scope.notifierChecksArmed()) break :blk .{};
            if (observation.bounded_timeout_subjects == 0) break :blk .{};
            if (observation.bounded_timeout_attempts < unsignalled_timeout_limit) break :blk .{};
            // An unclassified object is observation debt, not proof that the
            // emulator owes a signal. This invariant becomes non-bypassable
            // only after the registry has proved that notifier contract.
            if (!observation.bounded_timeout_notifier_proven) break :blk .{};
            if (observation.bounded_timeout_other_progress) break :blk .{
                .state = .satisfied,
                .detail = observation.bounded_timeout_attempts,
            };
            if (observation.bounded_timeout_signals != 0) break :blk .{
                .state = .satisfied,
                .detail = observation.bounded_timeout_signals,
            };
            if (!observation.ring_producer_published) break :blk .{};
            if (observation.producer_quiet_steps < output_handoff_quiet_steps) break :blk .{
                .state = .satisfied,
                .detail = observation.bounded_timeout_attempts,
            };
            break :blk .{
                .state = .violated,
                .detail = observation.bounded_timeout_attempts,
            };
        },
        .no_undercounting_observer => blk: {
            if (!observation.monotone_witness_corroboration_possible) break :blk .{};
            break :blk .{
                .state = if (observation.settled_observer_undercounts == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.settled_observer_undercounts,
            };
        },
        .no_presenter_failure => blk: {
            if (!observation.presenter_attempted) break :blk .{};
            break :blk .{
                .state = if (observation.presenter_nonretryable_failures == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.presenter_nonretryable_failures,
            };
        },
        .no_actionable_provisioning_refusal => blk: {
            if (!observation.provisioning_armed) break :blk .{};
            const custody_failures = observation.provisioning_late +|
                observation.provisioning_diverged +|
                observation.provisioning_contested +|
                observation.provisioning_unprovisioned;
            // An unresolved storage refusal normally leaves the resource
            // unprovisioned and is therefore already represented above. Keep
            // the maximum so a hand-built observation can still expose a
            // refusal without double-counting one resource in the detail.
            const failures = @max(custody_failures, observation.provisioning_actionable_refusals);
            break :blk .{
                .state = if (failures == 0) .satisfied else .violated,
                .detail = failures,
            };
        },
        .no_actionable_wait_policy_fault => blk: {
            if (!observation.wait_policy_observed) break :blk .{};
            break :blk .{
                .state = if (observation.wait_policy_faults == 0) .satisfied else .violated,
                .detail = observation.wait_policy_faults,
            };
        },
        .no_invalid_application_controller_decision => blk: {
            if (observation.application_controller_decisions == 0) break :blk .{};
            break :blk .{
                .state = if (observation.application_controller_contract_violations == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.application_controller_contract_violations,
            };
        },
        .no_unclassified_execution_profile => blk: {
            if (!observation.execution_profile_readable or
                !observation.execution_profile_decisive)
                break :blk .{};
            const debt = observation.execution_profile_unclassified +|
                observation.execution_profile_unresolved;
            break :blk .{
                .state = if (debt == 0) .satisfied else .violated,
                .detail = debt,
            };
        },
        // Unarmed until the probe driver has demonstrably run. Before that,
        // "never probed" is the whole ledger being cold and stopping on it
        // would stop every run at its first checkpoint. Once one probe has
        // been called this many times, a reachable stage with no attempts at
        // all is not waiting its turn — nothing calls it.
        .no_unprobed_reachable_stage => blk: {
            if (observation.vd_swap_probe_attempt_floor < vd_swap_probe_floor)
                break :blk .{};
            break :blk .{
                .state = if (observation.vd_swap_unprobed_reachable_stages == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.vd_swap_unprobed_reachable_stages,
            };
        },
        // Armed on the same evidence as the unprobed gate, and for the same
        // reason: before the driver has run, every stage is starved and that
        // says nothing about the wiring.
        .no_rosette_closable_starvation => blk: {
            if (observation.vd_swap_probe_attempt_floor < vd_swap_probe_floor)
                break :blk .{};
            break :blk .{
                .state = if (observation.vd_swap_rosette_closable_starvations == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.vd_swap_rosette_closable_starvations,
            };
        },
        .no_run_budget_deficit => blk: {
            if (!observation.run_budget_observed) break :blk .{};
            break :blk .{
                .state = if (observation.run_budget_deficit) .violated else .satisfied,
                .detail = if (observation.run_budget_deficit)
                    observation.run_budget_required_guest_ms_per_host_second -|
                        observation.run_budget_guest_ms_per_host_second
                else
                    observation.run_budget_guest_ms_per_host_second,
            };
        },
        .no_proven_deadlock => blk: {
            if (!observation.liveness_scope.notifierChecksArmed() or
                !observation.deadlock_observed or
                !observation.deadlock_proven)
                break :blk .{};
            break :blk .{
                .state = .violated,
                .detail = if (observation.deadlock_park_steps != 0)
                    observation.deadlock_park_steps
                else
                    observation.deadlock_waiters,
            };
        },
        .no_unproven_essential_component => blk: {
            if (!observation.component_readiness_armed) break :blk .{};
            break :blk .{
                .state = if (observation.essential_component_gaps == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.essential_component_gaps,
            };
        },
        // Armed only once some claim actually has two observers. A run whose
        // whole surface is single-source has nothing to disagree about, and
        // reporting that as satisfied would be the same mistake as reporting
        // it as violated.
        // Armed by its own evidence: the threshold that makes a gap settled is
        // applied where the inventory is read, so a first sighting during
        // bring-up cannot stop a run that was about to map the value anyway.
        // Armed only once a frontier boundary exists and is watched. Before
        // that there is no negative being asserted, and a gate that fired on a
        // run which had not yet armed its tracepoints would say nothing about
        // the observers.
        .frontier_boundary_corroborated => blk: {
            if (!observation.frontier_boundary_armed) break :blk .{};
            // Nothing on this surface has ever been crossed: the phase has not
            // begun and the tracepoints have never demonstrated they fire.
            // There is no negative here to substantiate.
            if (observation.frontier_boundary_crossed_elsewhere == 0) break :blk .{};
            if (observation.frontier_boundary_settled_steps < frontier_settle_steps)
                break :blk .{};
            // The run is still moving. A frontier the guest has not arrived at
            // is ahead of the run, not blocking it — the discriminator every
            // predictor in this codebase is required to consult.
            if (observation.external_progress_fresh) break :blk .{};
            // Reached on at least one address: the tracepoint is demonstrably
            // on the path, so its silence about later calls is evidence.
            if (observation.frontier_boundary_addresses_reached != 0) break :blk .{
                .state = .satisfied,
                .detail = observation.frontier_boundary_addresses_reached,
            };
            if (observation.frontier_boundary_corroborating_observers != 0) break :blk .{
                .state = .satisfied,
                .detail = observation.frontier_boundary_corroborating_observers,
            };
            break :blk .{ .state = .violated, .detail = 0 };
        },
        .no_settled_unknown_mapping => blk: {
            break :blk .{
                .state = if (observation.settled_unknown_mappings == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.settled_unknown_mappings,
            };
        },
        .no_contested_claim => blk: {
            if (observation.claim_reconciliation_multi_source == 0) break :blk .{};
            break :blk .{
                .state = if (observation.claim_reconciliation_contested == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.claim_reconciliation_contested,
            };
        },
        .all_required_witnesses_corroborated => blk: {
            // Do not turn an early, still-cold observer set into a failure.
            // Once all required subjects have spoken, however, every one of
            // them must be exactly corroborated; explained and weak findings
            // remain unsafe for a closed graphics conclusion.
            if (!observation.monotone_witness_closure_ready) break :blk .{};
            break :blk .{
                .state = if (observation.monotone_witness_agreement_debt == 0)
                    .satisfied
                else
                    .violated,
                .detail = observation.monotone_witness_agreement_debt,
            };
        },
    };
}

/// Combine the two independent capability-progress axes without allowing a
/// stale coverage score to hide work the guest compiler is still completing.
/// A larger step is the more recent witness; neither axis is allowed to lower
/// the other or to invent progress when it has no evidence.
pub fn capabilityProgressWitnessStep(
    coverage_progress_step: u64,
    guest_progress_step: u64,
) u64 {
    return @max(coverage_progress_step, guest_progress_step);
}

/// Return the quiet period used by the capability closure invariants.
/// Keeping this arithmetic in the package makes the runtime policy testable
/// independently from Mach-O and prevents different callers from silently
/// choosing different stale-snapshot rules.
pub fn capabilityProgressQuietSteps(
    step: u64,
    coverage_progress_step: u64,
    guest_progress_step: u64,
) u64 {
    return step -| capabilityProgressWitnessStep(
        coverage_progress_step,
        guest_progress_step,
    );
}

pub const Policy = enum(u8) {
    /// Judge and record; never stop the run.
    observe,
    /// Judge, record and report a violation loudly, but keep running.
    warn,
    /// Stop the run at the first violation.
    fault,

    pub fn label(self: Policy) []const u8 {
        return switch (self) {
            .observe => "observe",
            .warn => "warn",
            .fault => "fault",
        };
    }
};

/// The invariant a run should stop at, given everything judged this checkpoint.
///
/// Ordered by owner rather than by declaration: a Rosette-owned violation may
/// be what produced an emulator-owned one, and stopping at the symptom sends
/// the reader to the wrong side of the boundary. Within an owner, declaration
/// order decides, so the choice is stable across runs.
pub fn firstToStopAt(judgements: [invariant_count]Judgement) ?Invariant {
    var selected: ?Invariant = null;
    var selected_rank: u8 = 255;
    var index: u8 = 0;
    while (index < invariant_count) : (index += 1) {
        const invariant: Invariant = @enumFromInt(index);
        if (!judgements[index].violated()) continue;
        const rank = invariant.owner().rank();
        if (rank < selected_rank) {
            selected = invariant;
            selected_rank = rank;
        }
    }
    return selected;
}

/// Whether a name appears in a comma-separated allow list.
///
/// The list exists so a reader who has triaged one violation can step past it
/// and reach the next, without disarming the whole gate. Matching is exact on
/// the invariant's label; an unrecognised name allows nothing, so a typo in the
/// list cannot silently widen it.
pub fn allowedByList(list: []const u8, invariant: Invariant) bool {
    const name = invariant.label();
    var remaining = list;
    while (remaining.len != 0) {
        const end = std.mem.indexOfScalar(u8, remaining, ',') orelse remaining.len;
        const entry = std.mem.trim(u8, remaining[0..end], " \t");
        if (std.mem.eql(u8, entry, name)) return true;
        if (end == remaining.len) break;
        remaining = remaining[end + 1 ..];
    }
    return false;
}

/// Every invariant names an owner, a class and a remedy, and no two share a
/// label. Checked rather than assumed: the report is only useful if each line
/// sends a reader somewhere specific.
pub fn contractIsWellFormed() bool {
    var index: u8 = 0;
    while (index < invariant_count) : (index += 1) {
        const invariant: Invariant = @enumFromInt(index);
        if (invariant.label().len == 0) return false;
        if (invariant.remedy().len == 0) return false;
        var other: u8 = 0;
        while (other < invariant_count) : (other += 1) {
            if (other == index) continue;
            const compared: Invariant = @enumFromInt(other);
            if (std.mem.eql(u8, invariant.label(), compared.label())) return false;
        }
    }
    return true;
}

test "the contract is well formed" {
    try std.testing.expect(contractIsWellFormed());
}

test "an empty run violates nothing" {
    const observation = Observation{};
    var index: u8 = 0;
    while (index < invariant_count) : (index += 1) {
        const invariant: Invariant = @enumFromInt(index);
        const judgement = judge(invariant, observation);
        try std.testing.expect(!judgement.violated());
    }
}

test "an unarmed invariant is not satisfied either" {
    // The distinction is the point: a reader must be able to tell "assessed and
    // holding" from "nothing has looked".
    try std.testing.expectEqual(State.not_armed, judge(.presented_frames_in_custody, .{}).state);
    try std.testing.expectEqual(State.not_armed, judge(.swap_boundary_offered, .{}).state);
    try std.testing.expectEqual(State.not_armed, judge(.translation_cache_converges, .{}).state);
}

test "a frame that skipped custody is a Rosette-owned violation" {
    const judgement = judge(.presented_frames_in_custody, .{
        .frames_presented_to_window = 99,
        .frames_in_custody = 0,
    });
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 99), judgement.detail);
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.presented_frames_in_custody.owner());
}

test "custody running ahead of presentation is not a violation" {
    // A frame is offered before it is presented, so custody legitimately leads.
    try std.testing.expectEqual(
        State.satisfied,
        judge(.presented_frames_in_custody, .{ .frames_presented_to_window = 60, .frames_in_custody = 61 }).state,
    );
}

test "a swap the gate never saw means the two sides ran past each other" {
    try std.testing.expectEqual(
        State.satisfied,
        judge(.swap_boundary_offered, .{ .swap_boundaries_reached = 3, .swap_boundaries_offered = 3 }).state,
    );
    const judgement = judge(.swap_boundary_offered, .{ .swap_boundaries_reached = 3, .swap_boundaries_offered = 1 });
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 2), judgement.detail);
}

test "raw draws do not arm the output handoff" {
    var observation = Observation{ .draws_consumed = 24, .producer_quiet_steps = output_handoff_quiet_steps };
    // Presenter down: nothing to say.
    try std.testing.expectEqual(State.not_armed, judge(.guest_output_handoff_connected, observation).state);
    observation.presenter_ready = true;
    try std.testing.expectEqual(State.not_armed, judge(.guest_output_handoff_connected, observation).state);
    observation.renderable_draws_observed = 24;
    observation.guest_output_opportunity_observed = true;
    try std.testing.expect(judge(.guest_output_handoff_connected, observation).violated());
    // No draws: the emulator was never asked to produce anything.
    observation.draws_consumed = 0;
    observation.renderable_draws_observed = 0;
    observation.guest_output_opportunity_observed = false;
    try std.testing.expectEqual(State.not_armed, judge(.guest_output_handoff_connected, observation).state);
    // Draws, but the producer has not been quiet long enough yet.
    observation.draws_consumed = 24;
    observation.producer_quiet_steps = output_handoff_quiet_steps - 1;
    try std.testing.expectEqual(State.not_armed, judge(.guest_output_handoff_connected, observation).state);
    // A published frame satisfies it however quiet the producer went.
    observation.producer_quiet_steps = output_handoff_quiet_steps * 4;
    observation.frames_published_by_any_producer = 1;
    observation.renderable_draws_observed = 24;
    observation.guest_output_opportunity_observed = true;
    try std.testing.expectEqual(State.satisfied, judge(.guest_output_handoff_connected, observation).state);
}

test "a handoff cannot arm on an inconsistent opportunity claim" {
    const observation = Observation{
        .presenter_ready = true,
        .draws_consumed = 24,
        .guest_output_opportunity_observed = true,
        .producer_quiet_steps = output_handoff_quiet_steps,
    };
    try std.testing.expectEqual(State.not_armed, judge(.guest_output_handoff_connected, observation).state);
}

test "a short park is a worker and a long one is a lost wakeup" {
    const scope = LivenessScope.guest_execution;
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_never_notified_park, .{
            .liveness_scope = scope,
            .longest_never_notified_park_steps = 1000,
            .actionable_waiters_without_a_notifier = 1,
            .liveness_obligation_proven = true,
        }).state,
    );
    try std.testing.expect(judge(.no_never_notified_park, .{
        .liveness_scope = scope,
        .longest_never_notified_park_steps = never_notified_park_steps,
        .actionable_waiters_without_a_notifier = 1,
        .liveness_obligation_proven = true,
    }).violated());
}

test "a few timeouts are a poll and many with no signal are a missing signaller" {
    try std.testing.expectEqual(
        State.satisfied,
        judge(.wait_receives_signals, .{
            .liveness_scope = .guest_execution,
            .unsignalled_wait_timeouts = 4,
        }).state,
    );
    try std.testing.expect(judge(.wait_receives_signals, .{
        .liveness_scope = .guest_execution,
        .unsignalled_wait_timeouts = unsignalled_timeout_limit,
    }).violated());
}

test "wait graph findings require mature, lossless evidence" {
    // Before guest execution, even a recorded graph is diagnostic only.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_stalled_wait_handshake, .{
            .wait_graph_events = 16,
            .wait_graph_objects = 2,
            .wait_graph_stalled_handshakes = 1,
            .wait_graph_insufficient = 1,
        }).state,
    );

    // A reciprocal shape below the graph's maturity threshold cannot prove a
    // cycle or a stalled handshake.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_stalled_wait_handshake, .{
            .liveness_scope = .guest_execution,
            .wait_graph_events = 12,
            .wait_graph_objects = 2,
            .wait_graph_insufficient = 2,
        }).state,
    );

    const progressing = judge(.no_stalled_wait_handshake, .{
        .liveness_scope = .gpu_activity,
        .wait_graph_events = 80,
        .wait_graph_objects = 3,
        .wait_graph_insufficient = 1,
    });
    try std.testing.expectEqual(State.satisfied, progressing.state);

    const stalled = judge(.no_stalled_wait_handshake, .{
        .liveness_scope = .gpu_activity,
        .wait_graph_events = 872,
        .wait_graph_objects = 5,
        .wait_graph_stalled_handshakes = 2,
        .wait_graph_insufficient = 2,
    });
    try std.testing.expectEqual(State.violated, stalled.state);
    try std.testing.expectEqual(@as(u64, 2), stalled.detail);

    const cycle = judge(.no_stalled_wait_handshake, .{
        .liveness_scope = .gpu_activity,
        .wait_graph_events = 872,
        .wait_graph_objects = 5,
        .wait_graph_stalled_handshakes = 2,
        .wait_graph_cycles = 1,
        .wait_graph_insufficient = 2,
    });
    try std.testing.expectEqual(State.violated, cycle.state);
    try std.testing.expectEqual(@as(u64, 1), cycle.detail);

    // An overflowed graph is never allowed to pass by claiming that its
    // retained objects were healthy; dropped identity is missing evidence.
    try std.testing.expect(judge(.no_stalled_wait_handshake, .{
        .liveness_scope = .guest_execution,
        .wait_graph_events = 1,
        .wait_graph_objects = 1,
        .wait_graph_dropped_objects = 1,
    }).violated());
}

test "timeout liveness is not armed before guest execution" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.wait_receives_signals, .{ .unsignalled_wait_timeouts = unsignalled_timeout_limit }).state,
    );
}

test "a cold translation cache is never judged for conflicts" {
    // Every conflict, but the cache has not filled once: this is warm-up.
    const cold = Observation{
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 100,
        .translation_conflict_fills = 900,
        .translation_hits = 10,
        .translation_misses = 1000,
    };
    try std.testing.expectEqual(State.not_armed, judge(.translation_cache_converges, cold).state);
}

// The correction the observed run forced: 85% conflicts alongside a 99% hit
// rate is a true statement about the cache that costs the run nothing.
test "conflicts that cost nothing do not stop the run" {
    const observed = Observation{
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 262_144,
        .translation_conflict_fills = 1_610_194,
        .translation_hits = 6_805_578_866,
        .translation_misses = 1_872_338,
    };
    const judgement = judge(.translation_cache_converges, observed);
    try std.testing.expectEqual(State.satisfied, judgement.state);
    try std.testing.expectEqual(@as(u64, 99), judgement.detail);
}

test "conflicts that do cost the run stop it" {
    const thrashing = Observation{
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 262_144,
        .translation_conflict_fills = 9_000_000,
        .translation_hits = 900_000,
        .translation_misses = 900_000,
    };
    const judgement = judge(.translation_cache_converges, thrashing);
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 50), judgement.detail);
}

test "strict translation mode stops on the first proven reusable eviction" {
    const strict = Observation{
        .strict_fail_fast = true,
        // The primary cache is intentionally below its nominal occupancy
        // gate here. Strict mode must not wait for that gate to reach an
        // accounting number that the active bank layout may never produce.
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 131_072,
        .translation_conflict_fills = 1,
        .translation_hits = 9_999,
        .translation_misses = 1,
    };
    const judgement = judge(.translation_cache_converges, strict);
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
}

test "strict liveness mode does not dismiss a classified park with progress" {
    const strict = Observation{
        .strict_fail_fast = true,
        .liveness_scope = .gpu_activity,
        .waiters_without_a_notifier = 1,
        .longest_never_notified_park_steps = strict_never_notified_park_steps,
        .progress_since_never_notified_park = true,
        .actionable_waiters_without_a_notifier = 1,
        .liveness_obligation_proven = true,
    };
    try std.testing.expect(judge(.no_never_notified_park, strict).violated());
    try std.testing.expect(judge(.every_waiter_has_a_notifier, strict).violated());
}

test "pause transaction defects block the anomaly invariant" {
    const judgement = judge(.no_recorded_anomaly, .{
        .pause_transaction_defects = 1,
    });
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
}

test "a low hit rate from vacant fills alone is not conflict pressure" {
    // A cold-ish working set missing constantly with no eviction is a capacity
    // question, not the eviction defect this invariant names.
    const vacant_heavy = Observation{
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 900_000,
        .translation_conflict_fills = 1000,
        .translation_hits = 100,
        .translation_misses = 900_000,
    };
    try std.testing.expectEqual(State.satisfied, judge(.translation_cache_converges, vacant_heavy).state);
}

test "cold fills stay in the conflict denominator" {
    // The old judge divided only by vacant+conflict fills. That could call a
    // stream a pressure violation even when cold evictions were the majority
    // of the actual fill work. The denominator must include every fill cause.
    const cold_stream = Observation{
        .translation_cache_entries = 1,
        .translation_vacant_fills = 100,
        .translation_conflict_fills = 110,
        .translation_cold_evictions = 200,
        .translation_hits = 1,
        .translation_misses = 100,
    };
    try std.testing.expectEqual(State.satisfied, judge(.translation_cache_converges, cold_stream).state);
}

test "dominant stale refills are a translation integrity violation" {
    // A byte mismatch is stronger than an ordinary warm-up miss and remains
    // actionable even before the whole cache has been occupied once.
    const rewrite = Observation{
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 10,
        .translation_stale_refills = 10,
        .translation_hits = 100,
        .translation_misses = 20,
    };
    try std.testing.expect(judge(.translation_cache_converges, rewrite).violated());
}

test "dominant flush refills are a translation integrity violation" {
    const coarse_flush = Observation{
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 20,
        .translation_flush_refills = 20,
        .translation_hits = 100,
        .translation_misses = 40,
    };
    try std.testing.expect(judge(.translation_cache_converges, coarse_flush).violated());
}

test "a substitution that fired is never acceptable" {
    try std.testing.expectEqual(State.satisfied, judge(.no_harness_substitution, .{}).state);
    try std.testing.expect(judge(.no_harness_substitution, .{ .harness_substitutions = 1 }).violated());
}

test "a capability is only judged once it has been exercised and the ladder has stopped moving" {
    // Never exercised: nothing to say.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_unsatisfied_capability, .{ .capabilities_unsatisfied = 3 }).state,
    );
    // Exercised and failing, but the score is still climbing — this is the
    // step-zero reading, where "VdSwap has never been entered" is a not-yet.
    try std.testing.expectEqual(State.not_armed, judge(.no_unsatisfied_capability, .{
        .capabilities_exercised = 9,
        .capabilities_unsatisfied = 3,
        .capability_progress_quiet_steps = 10,
    }).state);
    // The ladder has stopped moving and the failures remain.
    try std.testing.expect(judge(.no_unsatisfied_capability, .{
        .capabilities_exercised = 9,
        .capabilities_unsatisfied = 3,
        .capability_progress_quiet_steps = capability_progress_quiet_steps,
    }).violated());
    // Stopped moving with nothing failing is the healthy end state.
    try std.testing.expectEqual(State.satisfied, judge(.no_unsatisfied_capability, .{
        .capabilities_exercised = 23,
        .capabilities_unsatisfied = 0,
        .capability_progress_quiet_steps = capability_progress_quiet_steps * 4,
    }).state);
}

test "guest compiler progress keeps capability closure in its grace window" {
    const coverage_step: u64 = 700_000_000;
    const guest_step: u64 = 1_696_197_173;
    const current_step: u64 = 1_700_000_000;
    try std.testing.expectEqual(guest_step, capabilityProgressWitnessStep(coverage_step, guest_step));
    try std.testing.expectEqual(
        current_step - guest_step,
        capabilityProgressQuietSteps(current_step, coverage_step, guest_step),
    );
    try std.testing.expect(
        capabilityProgressQuietSteps(current_step, coverage_step, guest_step) <
            capability_progress_quiet_steps,
    );

    // Once the guest/compiler witness is old as well, strict closure resumes;
    // a recent witness never certifies any capability by itself.
    const quiet_step = guest_step + capability_progress_quiet_steps;
    try std.testing.expectEqual(
        capability_progress_quiet_steps,
        capabilityProgressQuietSteps(quiet_step, coverage_step, guest_step),
    );
    try std.testing.expect(
        judge(.all_critical_capabilities_proven, .{
            .capabilities_exercised = 16,
            .critical_capabilities_total = 11,
            .critical_capabilities_satisfied = 8,
            .critical_capabilities_degraded = 1,
            .critical_capabilities_untested = 2,
            .capability_progress_quiet_steps = capability_progress_quiet_steps,
        }).violated(),
    );
}

test "critical capability closure rejects degraded and unknown entries" {
    const warming = Observation{
        .capabilities_exercised = 17,
        .critical_capabilities_degraded = 1,
        .critical_capabilities_untested = 2,
        .capability_progress_quiet_steps = capability_progress_quiet_steps - 1,
    };
    try std.testing.expectEqual(
        State.not_armed,
        judge(.all_critical_capabilities_proven, warming).state,
    );

    const closed = Observation{
        .capabilities_exercised = 17,
        .critical_capabilities_total = 10,
        .critical_capabilities_satisfied = 6,
        .critical_capabilities_degraded = 1,
        .critical_capabilities_unsatisfied = 1,
        .critical_capabilities_untested = 2,
        .capability_progress_quiet_steps = capability_progress_quiet_steps,
    };
    const closure = judge(.all_critical_capabilities_proven, closed);
    try std.testing.expect(closure.violated());
    try std.testing.expectEqual(@as(u64, 4), closure.detail);
    try std.testing.expectEqual(
        State.violated,
        judge(.no_degraded_critical_capability, closed).state,
    );

    const complete = Observation{
        .capabilities_exercised = 23,
        .critical_capabilities_total = 11,
        .critical_capabilities_satisfied = 11,
        .capability_progress_quiet_steps = capability_progress_quiet_steps,
    };
    try std.testing.expectEqual(
        State.satisfied,
        judge(.all_critical_capabilities_proven, complete).state,
    );
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_degraded_critical_capability, complete).state,
    );
}

test "critical capability closure rejects an incomplete status census" {
    const incomplete = Observation{
        .capabilities_exercised = 17,
        .critical_capabilities_total = 11,
        .critical_capabilities_satisfied = 10,
        .capability_progress_quiet_steps = capability_progress_quiet_steps,
    };
    const judgement = judge(.all_critical_capabilities_proven, incomplete);
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
}

test "the run stops at the owner nearest to Rosette" {
    var judgements = [_]Judgement{.{}} ** invariant_count;
    // An emulator-owned violation alone.
    judgements[@intFromEnum(Invariant.no_never_notified_park)] = .{ .state = .violated };
    try std.testing.expectEqual(Invariant.no_never_notified_park, firstToStopAt(judgements).?);
    // A Rosette-owned one alongside it wins: it may be what produced the other.
    judgements[@intFromEnum(Invariant.presented_frames_in_custody)] = .{ .state = .violated };
    try std.testing.expectEqual(Invariant.presented_frames_in_custody, firstToStopAt(judgements).?);
}

test "nothing violated stops nothing" {
    const judgements = [_]Judgement{.{}} ** invariant_count;
    try std.testing.expect(firstToStopAt(judgements) == null);
}

test "the allow list matches exactly and a typo widens nothing" {
    try std.testing.expect(allowedByList("no-recorded-anomaly", .no_recorded_anomaly));
    try std.testing.expect(allowedByList("a, no-recorded-anomaly ,b", .no_recorded_anomaly));
    try std.testing.expect(!allowedByList("no-recorded-anomalys", .no_recorded_anomaly));
    try std.testing.expect(!allowedByList("no-emulator", .no_recorded_anomaly));
    try std.testing.expect(!allowedByList("", .no_recorded_anomaly));
    try std.testing.expect(!allowedByList("no-recorded-anomaly", .no_harness_substitution));
}

// The 2026-08-27 run, replayed. The raw PM4 draw count is retained as
// diagnostic context, but this replay has no target-backed draw, resolve, swap
// boundary, or VdSwap packet, so it must not manufacture an output opportunity.
test "the observed run violates four proven invariants and stops at Rosette's" {
    const observed = Observation{
        .step = 6_800_000_000,
        .liveness_scope = .gpu_activity,
        .window_forwardings = 6,
        .window_unaccountable = 0,
        .frames_presented_to_window = 62,
        .frames_in_custody = 61,
        .swap_boundaries_reached = 0,
        .swap_boundaries_offered = 0,
        .presenter_ready = true,
        .draws_consumed = 24,
        .frames_published_by_any_producer = 0,
        .producer_quiet_steps = 3_549_168_487,
        .longest_never_notified_park_steps = 6_734_887_829,
        .unsignalled_wait_timeouts = 90,
        .capabilities_exercised = 23,
        .capabilities_unsatisfied = 2,
        .capability_progress_quiet_steps = 1_800_000_000,
        .harness_substitutions = 0,
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 262_144,
        .translation_conflict_fills = 1_610_194,
        .translation_hits = 6_805_578_866,
        .translation_misses = 1_872_338,
        .recorded_anomalies = 6,
    };
    var judgements = [_]Judgement{.{}} ** invariant_count;
    var violations: usize = 0;
    var index: u8 = 0;
    while (index < invariant_count) : (index += 1) {
        const invariant: Invariant = @enumFromInt(index);
        judgements[index] = judge(invariant, observed);
        if (judgements[index].violated()) violations += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), violations);
    // Exactly one of them is Rosette's — one frame reached the window that
    // custody never recorded — and that is where the run stops. The translation
    // cache is *not* among them: 85% conflicts at a 99% hit rate is a true
    // statement that costs the run nothing. The output handoff is also not
    // among them: raw/retained draws without a target do not prove pixels.
    try std.testing.expectEqual(Invariant.presented_frames_in_custody, firstToStopAt(judgements).?);
    try std.testing.expect(!judgements[@intFromEnum(Invariant.translation_cache_converges)].violated());
    // With custody closed, the gate hands the reader over to the emulator side
    // rather than pretending the run is clean. The output handoff is not the
    // next stop because raw/retained draws never armed it.
    judgements[@intFromEnum(Invariant.presented_frames_in_custody)] = .{ .state = .satisfied };
    try std.testing.expectEqual(Owner.emulator_host, firstToStopAt(judgements).?.owner());
    // Once unproven host-worker silence is removed, the remaining proven
    // emulator-side finding is the un-signalled wait-timeout contract.
    try std.testing.expectEqual(Invariant.wait_receives_signals, firstToStopAt(judgements).?);
}

// The one-frame custody gap in that run was not a lost frame: the presenter
// puts frames up between checkpoints and custody was crediting one identity per
// checkpoint, so the coverage a single identity accounts for has to be stated
// rather than assumed to be one.
test "custody that states its coverage closes the checkpoint skew" {
    try std.testing.expect(judge(.presented_frames_in_custody, .{
        .frames_presented_to_window = 62,
        .frames_in_custody = 61,
    }).violated());
    try std.testing.expectEqual(State.satisfied, judge(.presented_frames_in_custody, .{
        .frames_presented_to_window = 62,
        .frames_in_custody = 62,
    }).state);
}

test "pre-guest notifier silence is retained but not yet actionable" {
    const observation = Observation{
        .waiters_without_a_notifier = 3,
        .longest_never_notified_park_steps = never_notified_park_steps * 2,
    };
    try std.testing.expectEqual(
        State.not_armed,
        judge(.every_waiter_has_a_notifier, observation).state,
    );
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_never_notified_park, observation).state,
    );
}

test "liveness scope labels the boundary that arms notifier checks" {
    try std.testing.expectEqualStrings("pre-guest-startup", LivenessScope.pre_guest_startup.label());
    try std.testing.expectEqualStrings("guest-execution", LivenessScope.guest_execution.label());
    try std.testing.expectEqualStrings("gpu-activity", LivenessScope.gpu_activity.label());
    try std.testing.expect(!LivenessScope.pre_guest_startup.notifierChecksArmed());
    try std.testing.expect(LivenessScope.guest_execution.notifierChecksArmed());
    try std.testing.expect(LivenessScope.gpu_activity.notifierChecksArmed());
}

test "a waiter with no notifier is strict after guest execution starts" {
    try std.testing.expectEqual(State.satisfied, judge(.every_waiter_has_a_notifier, .{
        .liveness_scope = .guest_execution,
    }).state);
    const judgement = judge(.every_waiter_has_a_notifier, .{
        .liveness_scope = .guest_execution,
        .waiters_without_a_notifier = 1,
        .actionable_waiters_without_a_notifier = 1,
        .liveness_obligation_proven = true,
    });
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(Owner.emulator_host, Invariant.every_waiter_has_a_notifier.owner());
}

test "a park Rosette cannot name is Rosette's hole, not the thread's defect" {
    try std.testing.expectEqual(State.satisfied, judge(.every_park_has_a_reason, .{}).state);
    try std.testing.expect(judge(.every_park_has_a_reason, .{ .parks_without_a_reason = 1 }).violated());
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.every_park_has_a_reason.owner());
}

test "two master owners in one process stops the run" {
    try std.testing.expectEqual(State.satisfied, judge(.single_master_owner, .{}).state);
    try std.testing.expect(judge(.single_master_owner, .{ .ownership_violations = 1 }).violated());
    try std.testing.expectEqual(Class.ownership, Invariant.single_master_owner.class());
}

test "substantiation is unarmed until a boundary is reached" {
    try std.testing.expectEqual(State.not_armed, judge(.every_boundary_substantiated, .{
        .unsubstantiated_boundaries = 4,
    }).state);
    try std.testing.expectEqual(State.satisfied, judge(.every_boundary_substantiated, .{
        .substantiation_armed = true,
    }).state);
}

test "a divergence is what the substantiation detail reports" {
    const judgement = judge(.every_boundary_substantiated, .{
        .substantiation_armed = true,
        .unsubstantiated_boundaries = 3,
        .diverged_boundaries = 1,
    });
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
}

test "measurement-domain drift is a strict substantiation violation" {
    const judgement = judge(.every_boundary_substantiated, .{
        .substantiation_armed = true,
        .measurement_drift_boundaries = 1,
    });
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
}

test "live PM4 with unclassified register writes is not admitted" {
    const observation = Observation{
        .pm4_packets_observed = 72,
        .pm4_packets_executed = 72,
        .pm4_unclassified_register_writes = 22,
        .pm4_defects = 22,
    };
    const judgement = judge(.no_unverified_pm4_input, observation);
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 22), judgement.detail);
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_unverified_pm4_input.owner());
}

test "clean live PM4 is admitted while an unobserved path is not declared clean" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_unverified_pm4_input, .{}).state,
    );
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_unverified_pm4_input, .{
            .pm4_packets_observed = 72,
            .pm4_packets_executed = 72,
        }).state,
    );
}

test "mandatory order is unarmed until it has a judgeable rule and is strict when violated" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_mandatory_order_violation, .{}).state,
    );
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_mandatory_order_violation, .{
            .mandatory_order_armed = true,
            .mandatory_order_active = 1,
        }).state,
    );
    const judgement = judge(.no_mandatory_order_violation, .{
        .mandatory_order_armed = true,
        .mandatory_order_active = 7,
        .mandatory_order_violated = 3,
        .mandatory_order_mandatory_violations = 2,
        .mandatory_order_raced = 0,
    });
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 2), judgement.detail);
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_mandatory_order_violation.owner());
    try std.testing.expectEqual(Class.handoff, Invariant.no_mandatory_order_violation.class());
}

test "GPU preinitialization ordering inversion is always a hard violation" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_gpu_preinitialization_order_inversion, .{}).state,
    );
    const judgement = judge(.no_gpu_preinitialization_order_inversion, .{
        .gpu_preinitialization_inversions = 1,
        .gpu_preinitialization_inversions_dropped = 2,
    });
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 3), judgement.detail);
    try std.testing.expect(Invariant.no_gpu_preinitialization_order_inversion.nonBypassable());
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_gpu_preinitialization_order_inversion.owner());
    try std.testing.expectEqual(Class.handoff, Invariant.no_gpu_preinitialization_order_inversion.class());
}

test "a park beside a run that keeps advancing is an idle worker" {
    // The false positive the 2026-08-27 run produced: three condvars parked
    // from startup, in a run whose own deadlock predictor said the window was
    // too short to conclude anything.
    const advancing = Observation{
        .liveness_scope = .gpu_activity,
        .waiters_without_a_notifier = 3,
        .longest_never_notified_park_steps = never_notified_park_steps * 4,
        .progress_since_never_notified_park = true,
        .actionable_waiters_without_a_notifier = 3,
        .liveness_obligation_proven = true,
    };
    try std.testing.expectEqual(State.satisfied, judge(.every_waiter_has_a_notifier, advancing).state);
    try std.testing.expectEqual(State.satisfied, judge(.no_never_notified_park, advancing).state);

    // The same parks with nothing else moving are the finding.
    var frozen = advancing;
    frozen.progress_since_never_notified_park = false;
    try std.testing.expect(judge(.every_waiter_has_a_notifier, frozen).violated());
    try std.testing.expect(judge(.no_never_notified_park, frozen).violated());
}

test "the detail survives the progress gate so the count is still readable" {
    const advancing = Observation{
        .liveness_scope = .guest_execution,
        .waiters_without_a_notifier = 3,
        .progress_since_never_notified_park = true,
        .actionable_waiters_without_a_notifier = 3,
        .liveness_obligation_proven = true,
    };
    try std.testing.expectEqual(@as(u64, 3), judge(.every_waiter_has_a_notifier, advancing).detail);
}

test "raw host wait silence without a proven obligation stays diagnostic" {
    const observation = Observation{
        .strict_fail_fast = true,
        .liveness_scope = .gpu_activity,
        .waiters_without_a_notifier = 2,
        .longest_never_notified_park_steps = strict_never_notified_park_steps * 4,
        .progress_since_never_notified_park = true,
    };
    try std.testing.expectEqual(State.not_armed, judge(.no_never_notified_park, observation).state);
    try std.testing.expectEqual(State.not_armed, judge(.every_waiter_has_a_notifier, observation).state);
}

test "a texture format is only judged once a device has been asked" {
    try std.testing.expectEqual(State.not_armed, judge(.no_reinterpreting_texture_format, .{
        .reinterpreted_texture_formats = 2,
    }).state);
    try std.testing.expectEqual(State.satisfied, judge(.no_reinterpreting_texture_format, .{
        .texture_formats_probed = true,
    }).state);
    const judgement = judge(.no_reinterpreting_texture_format, .{
        .texture_formats_probed = true,
        .reinterpreted_texture_formats = 2,
    });
    try std.testing.expect(judgement.violated());
    try std.testing.expectEqual(@as(u64, 2), judgement.detail);
    try std.testing.expectEqual(Owner.emulator_host, Invariant.no_reinterpreting_texture_format.owner());
}

// The 2026-08-31 shape, and why this gate exists. Xenia's callback executor
// had entered the title's handler two hundred and forty times; the throttled
// breadcrumb Rosette was reading said four. That disagreement is *not* this
// invariant — a throttled line is allowed to be short — so the gate must stay
// satisfied on it while still stopping for an observer that has no excuse.
test "an undercounting observer arms only once corroboration is possible" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_undercounting_observer, .{ .settled_observer_undercounts = 3 }).state,
    );

    const explained = judge(.no_undercounting_observer, .{
        .monotone_witness_corroboration_possible = true,
        .settled_observer_undercounts = 0,
    });
    try std.testing.expectEqual(State.satisfied, explained.state);

    const unexplained = judge(.no_undercounting_observer, .{
        .monotone_witness_corroboration_possible = true,
        .settled_observer_undercounts = 1,
    });
    try std.testing.expectEqual(State.violated, unexplained.state);
    try std.testing.expectEqual(@as(u64, 1), unexplained.detail);

    // Rosette's own reading is what is wrong, so Rosette owns it, and it is an
    // ownership finding rather than a liveness one: the mechanism was running.
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_undercounting_observer.owner());
    try std.testing.expectEqual(Class.ownership, Invariant.no_undercounting_observer.class());
    try std.testing.expect(!Invariant.no_undercounting_observer.nonBypassable());
    try std.testing.expect(
        std.mem.indexOf(u8, Invariant.no_undercounting_observer.remedy(), "MONOTONE WITNESS") != null,
    );
}

test "required monotone witness closure rejects uncorroborated subjects" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.all_required_witnesses_corroborated, .{
            .monotone_witness_closure_ready = false,
            .monotone_witness_required = 9,
            .monotone_witness_observed = 8,
            .monotone_witness_corroborated = 4,
            .monotone_witness_agreement_debt = 4,
        }).state,
    );

    const incomplete = judge(.all_required_witnesses_corroborated, .{
        .monotone_witness_closure_ready = true,
        .monotone_witness_required = 9,
        .monotone_witness_observed = 9,
        .monotone_witness_corroborated = 4,
        .monotone_witness_agreement_debt = 5,
    });
    try std.testing.expectEqual(State.violated, incomplete.state);
    try std.testing.expectEqual(@as(u64, 5), incomplete.detail);
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.all_required_witnesses_corroborated.owner());
    try std.testing.expectEqual(Class.ownership, Invariant.all_required_witnesses_corroborated.class());
    try std.testing.expect(!Invariant.all_required_witnesses_corroborated.nonBypassable());

    const complete = judge(.all_required_witnesses_corroborated, .{
        .monotone_witness_closure_ready = true,
        .monotone_witness_required = 9,
        .monotone_witness_observed = 9,
        .monotone_witness_corroborated = 9,
        .monotone_witness_agreement_debt = 0,
    });
    try std.testing.expectEqual(State.satisfied, complete.state);
}

// The 2026-08-31 live blocker. A guest thread polled a manual-reset event with
// a thirty-millisecond timeout a hundred and twelve times, received nothing,
// and the ring producer beside it had published once at step 3 259 565 717 and
// gone silent. `wait_receives_signals` excludes bounded polls by design, so
// nothing in the gate stopped for it and the run spent four billion steps
// counting the same non-event.
test "an attributed bounded poll that never receives a signal beside a silent producer is a stuck consumer" {
    const polling = Observation{
        .liveness_scope = .gpu_activity,
        .bounded_timeout_subjects = 1,
        .bounded_timeout_attempts = 112,
        .bounded_timeout_signals = 0,
        .bounded_timeout_object = 0x4000_4BF4,
        .bounded_timeout_handle = 0xF800_0154,
        .bounded_timeout_ms = 30,
        .bounded_timeout_notifier_proven = true,
        .ring_producer_published = true,
        .producer_quiet_steps = 4_240_434_283,
    };
    const judgement = judge(.bounded_poll_receives_signals, polling);
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 112), judgement.detail);

    // A poll beside a producer that is still publishing is a consumer keeping
    // up. Same counters, different neighbour, and it must not stop the run.
    var keeping_up = polling;
    keeping_up.producer_quiet_steps = 1_000;
    try std.testing.expectEqual(State.satisfied, judge(.bounded_poll_receives_signals, keeping_up).state);

    // A poll that consumes signals is a poll.
    var consuming = polling;
    consuming.bounded_timeout_signals = 4;
    try std.testing.expectEqual(State.satisfied, judge(.bounded_poll_receives_signals, consuming).state);

    // The same timeouts while another independent axis advances are a working
    // pump. Retiring guest instructions alone is excluded by the witness.
    var progressing = polling;
    progressing.bounded_timeout_other_progress = true;
    try std.testing.expectEqual(State.satisfied, judge(.bounded_poll_receives_signals, progressing).state);

    // Without a classified object and a stated notifier, the missing signal
    // has no owner. Refuse to turn that observation gap into a fatal finding.
    var unclassified = polling;
    unclassified.bounded_timeout_notifier_proven = false;
    try std.testing.expectEqual(State.not_armed, judge(.bounded_poll_receives_signals, unclassified).state);

    // Too few expiries to rule out a late signal, and no guest yet, both stay
    // unarmed rather than passing.
    var early = polling;
    early.bounded_timeout_attempts = unsignalled_timeout_limit - 1;
    try std.testing.expectEqual(State.not_armed, judge(.bounded_poll_receives_signals, early).state);
    var pre_guest = polling;
    pre_guest.liveness_scope = .pre_guest_startup;
    try std.testing.expectEqual(State.not_armed, judge(.bounded_poll_receives_signals, pre_guest).state);

    // A ring that never started borrows the whole run as its quiet window, so
    // a poll beside it would read as stuck from step one. That is a different
    // finding with its own gates and this one declines to make it.
    var never_started = polling;
    never_started.ring_producer_published = false;
    try std.testing.expectEqual(State.not_armed, judge(.bounded_poll_receives_signals, never_started).state);

    try std.testing.expectEqual(Class.liveness, Invariant.bounded_poll_receives_signals.class());
    try std.testing.expectEqual(Owner.emulator_host, Invariant.bounded_poll_receives_signals.owner());
    try std.testing.expect(
        std.mem.indexOf(u8, Invariant.bounded_poll_receives_signals.remedy(), "Do not synthesise") != null,
    );
}

test "presenter failure is armed only after a native attempt and ignores retryable states" {
    try std.testing.expectEqual(State.not_armed, judge(.no_presenter_failure, .{}).state);
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_presenter_failure, .{ .presenter_attempted = true }).state,
    );
    try std.testing.expectEqual(
        State.violated,
        judge(.no_presenter_failure, .{
            .presenter_attempted = true,
            .presenter_nonretryable_failures = 1,
        }).state,
    );
    try std.testing.expectEqual(Class.capability, Invariant.no_presenter_failure.class());
    try std.testing.expectEqual(Owner.host_driver, Invariant.no_presenter_failure.owner());
}

test "provisioning owner refusals stay diagnostic until custody is actionable" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_actionable_provisioning_refusal, .{
            .provisioning_raw_refusals = 99,
        }).state,
    );
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_actionable_provisioning_refusal, .{
            .provisioning_armed = true,
            .provisioning_raw_refusals = 99,
        }).state,
    );
    const judgement = judge(.no_actionable_provisioning_refusal, .{
        .provisioning_armed = true,
        .provisioning_actionable_refusals = 1,
    });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
    try std.testing.expectEqual(Class.ownership, Invariant.no_actionable_provisioning_refusal.class());
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_actionable_provisioning_refusal.owner());
}

test "only a wait policy fault is fatal, not a refused synthetic wake" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_actionable_wait_policy_fault, .{}).state,
    );
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_actionable_wait_policy_fault, .{
            .wait_policy_observed = true,
        }).state,
    );
    const judgement = judge(.no_actionable_wait_policy_fault, .{
        .wait_policy_observed = true,
        .wait_policy_faults = 2,
    });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 2), judgement.detail);
    try std.testing.expectEqual(Class.liveness, Invariant.no_actionable_wait_policy_fault.class());
    try std.testing.expectEqual(Owner.emulator_host, Invariant.no_actionable_wait_policy_fault.owner());
}

test "an invalid application-controller decision is a non-bypassable safety fault" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_invalid_application_controller_decision, .{}).state,
    );
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_invalid_application_controller_decision, .{
            .application_controller_decisions = 4,
        }).state,
    );
    const judgement = judge(.no_invalid_application_controller_decision, .{
        .application_controller_decisions = 4,
        .application_controller_contract_violations = 1,
    });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
    try std.testing.expect(Invariant.no_invalid_application_controller_decision.nonBypassable());
    try std.testing.expectEqual(Class.ownership, Invariant.no_invalid_application_controller_decision.class());
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_invalid_application_controller_decision.owner());
}

// The 2026-09-03 run: `VD SWAP TRACE ... unprobed=1` on every one of twenty
// checkpoints, with `front buffer validated` at `probes=0/4` while the probes
// beside it recorded a hundred attempts each. The report already said "the
// zero is Rosette's, not the title's" and nothing stopped on it, so the whole
// front-buffer branch of the producer chain read as an absence in the title.
test "an unprobed reachable stage is fatal only once the probe driver has run" {
    // A cold ledger has every reachable stage unprobed and means nothing.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_unprobed_reachable_stage, .{
            .vd_swap_unprobed_reachable_stages = 6,
        }).state,
    );
    // Still cold one round short of the floor.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_unprobed_reachable_stage, .{
            .vd_swap_unprobed_reachable_stages = 1,
            .vd_swap_probe_attempt_floor = vd_swap_probe_floor - 1,
        }).state,
    );
    // A driver that has run, with every reachable stage probed.
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_unprobed_reachable_stage, .{
            .vd_swap_probe_attempt_floor = 100,
        }).state,
    );
    // A driver that has run a hundred rounds and a stage it never visits.
    const judgement = judge(.no_unprobed_reachable_stage, .{
        .vd_swap_unprobed_reachable_stages = 1,
        .vd_swap_probe_attempt_floor = 100,
    });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
    try std.testing.expectEqual(Class.ownership, Invariant.no_unprobed_reachable_stage.class());
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_unprobed_reachable_stage.owner());
    // It is Rosette's own blind spot, so it can be stepped past like the other
    // observation debts while the wiring is repaired.
    try std.testing.expect(!Invariant.no_unprobed_reachable_stage.nonBypassable());
}

// A 99% hit rate is not a cache diagnosis by itself. The fill-site distinction
// matters: compulsory fills are unavoidable, cold evictions are non-empty but
// never-reused working-set evidence, and conflicts/stale/flush are actionable
// recurring loss. The observed `miss(vacant/conflict/cold)=908548/0/2602`
// stream therefore remains visible without being mistaken for hot conflict.
test "reusable translation loss is fatal and compulsory or cold work is not" {
    // Compulsory fills alone never arm the gate: an instruction must be
    // decoded once and no cache policy makes a first touch free.
    try std.testing.expectEqual(
        State.satisfied,
        judge(.translation_cache_converges, .{
            .strict_fail_fast = true,
            .translation_cache_entries = 262_144,
            .translation_vacant_fills = 908_548,
            .translation_hits = 2_807_391_687,
            .translation_misses = 908_548,
        }).state,
    );
    // Cold evictions stay observable but are not enough to prove reusable loss.
    const cold = judge(.translation_cache_converges, .{
        .translation_cache_entries = 262_144,
        .strict_fail_fast = true,
        .translation_vacant_fills = 908_548,
        .translation_cold_evictions = 2_602,
        .translation_hits = 2_807_391_687,
        .translation_misses = 911_150,
    });
    try std.testing.expectEqual(State.satisfied, cold.state);
    try std.testing.expectEqual(@as(u64, 99), cold.detail);
    // The three that were already fatal stay fatal, and each names its own count.
    try std.testing.expectEqual(
        State.violated,
        judge(.translation_cache_converges, .{
            .strict_fail_fast = true,
            .translation_vacant_fills = 10,
            .translation_conflict_fills = 3,
        }).state,
    );
    // Nothing decoded yet is not a pass.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.translation_cache_converges, .{ .strict_fail_fast = true }).state,
    );
}

// The contract already called this "Rosette's to close today" on every
// checkpoint and nothing stopped on it.
test "a Rosette-closable starvation is fatal once the probe driver has run" {
    // Cold ledger: every stage is starved and that says nothing.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_rosette_closable_starvation, .{
            .vd_swap_rosette_closable_starvations = 3,
        }).state,
    );
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_rosette_closable_starvation, .{
            .vd_swap_probe_attempt_floor = 178,
        }).state,
    );
    const judgement = judge(.no_rosette_closable_starvation, .{
        .vd_swap_probe_attempt_floor = 178,
        .vd_swap_rosette_closable_starvations = 1,
    });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_rosette_closable_starvation.owner());
    try std.testing.expectEqual(Class.ownership, Invariant.no_rosette_closable_starvation.class());
}

// 2026-09-04: a run whose tracepoints were merely armed reported all nine
// required subjects observed, every one of them in agreement debt, and stopped
// demanding that a second observer corroborate nine statements nobody had made.
// Closure now means nine *claims*, so this gate can only fire on real ones.
// The anti-stuck condition. A classifier that keeps declining a value a
// conclusion needs will produce the same frontier every run, forever, and no
// amount of further running changes that.
// The frontier is the single most consequential sentence Rosette emits: it
// decides which subsystem gets the next week. On 2026-09-05 it named
// VdQueryVideoMode while the emulator's own breadcrumb said that export had
// been called. A negative that directs work must be corroborated.
test "an uncorroborated frontier negative stops the run" {
    // No frontier armed yet: nothing is being asserted.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.frontier_boundary_corroborated, .{}).state,
    );
    // A frontier that has only just appeared is a run in progress. This is the
    // step-0 state that stopped the 2026-09-06 run at its first checkpoint:
    // armed, reached on nothing, spoken about by nobody, because nothing had
    // happened yet.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.frontier_boundary_corroborated, .{
            .frontier_boundary_armed = true,
            .frontier_boundary_crossed_elsewhere = 4,
            .frontier_boundary_settled_steps = 0,
        }).state,
    );
    try std.testing.expectEqual(
        State.not_armed,
        judge(.frontier_boundary_corroborated, .{
            .frontier_boundary_armed = true,
            .frontier_boundary_crossed_elsewhere = 4,
            .frontier_boundary_settled_steps = frontier_settle_steps - 1,
        }).state,
    );
    // Nothing crossed anywhere: the guest has not begun this phase. This is the
    // second false positive — the title was still mapping its own executable
    // while the gate blamed the first GPU export for never being called.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.frontier_boundary_corroborated, .{
            .frontier_boundary_armed = true,
            .frontier_boundary_crossed_elsewhere = 0,
            .frontier_boundary_settled_steps = frontier_settle_steps * 10,
        }).state,
    );
    // Settled, phase begun, but the run is still moving toward the frontier.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.frontier_boundary_corroborated, .{
            .frontier_boundary_armed = true,
            .frontier_boundary_crossed_elsewhere = 4,
            .frontier_boundary_settled_steps = frontier_settle_steps,
            .external_progress_fresh = true,
        }).state,
    );
    // The tracepoint is demonstrably on the path, so its reading stands.
    try std.testing.expectEqual(
        State.satisfied,
        judge(.frontier_boundary_corroborated, .{
            .frontier_boundary_armed = true,
            .frontier_boundary_crossed_elsewhere = 4,
            .frontier_boundary_settled_steps = frontier_settle_steps,
            .frontier_boundary_addresses_reached = 2,
        }).state,
    );
    // Never reached, but a second observer agrees it never happened.
    try std.testing.expectEqual(
        State.satisfied,
        judge(.frontier_boundary_corroborated, .{
            .frontier_boundary_armed = true,
            .frontier_boundary_crossed_elsewhere = 4,
            .frontier_boundary_settled_steps = frontier_settle_steps,
            .frontier_boundary_corroborating_observers = 1,
        }).state,
    );
    // Armed, never reached, nobody else looked: the frontier is unsubstantiated.
    const judgement = judge(.frontier_boundary_corroborated, .{
        .frontier_boundary_armed = true,
        .frontier_boundary_crossed_elsewhere = 10,
        .frontier_boundary_settled_steps = frontier_settle_steps,
    });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.frontier_boundary_corroborated.owner());
    // The remedy has to name the armed/reached pair, because that row is the
    // only place the two explanations are distinguishable.
    try std.testing.expect(std.mem.indexOf(
        u8,
        Invariant.frontier_boundary_corroborated.remedy(),
        "addresses(armed/reached)",
    ) != null);
}

test "a settled unmapped value stops the run and a fresh one does not" {
    // Satisfied rather than not-armed: the inventory always has an answer, and
    // "nothing is blocked" is a real reading rather than an absence.
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_settled_unknown_mapping, .{}).state,
    );
    const judgement = judge(.no_settled_unknown_mapping, .{ .settled_unknown_mappings = 2 });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 2), judgement.detail);
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_settled_unknown_mapping.owner());
    // The remedy has to say that running longer is not the fix, because that is
    // the thing a reader keeps trying.
    try std.testing.expect(std.mem.indexOf(
        u8,
        Invariant.no_settled_unknown_mapping.remedy(),
        "not a condition further running resolves",
    ) != null);
}

test "a contested claim is fatal and a single-source surface is not judged" {
    // Nothing has two observers: there is nothing to disagree about, and
    // reporting that as clean would be the same error as reporting it as bad.
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_contested_claim, .{ .claim_reconciliation_contested = 2 }).state,
    );
    try std.testing.expectEqual(
        State.satisfied,
        judge(.no_contested_claim, .{ .claim_reconciliation_multi_source = 6 }).state,
    );
    const judgement = judge(.no_contested_claim, .{
        .claim_reconciliation_multi_source = 6,
        .claim_reconciliation_contested = 1,
    });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_contested_claim.owner());
    try std.testing.expectEqual(Class.ownership, Invariant.no_contested_claim.class());
    // It is Rosette's own reading, so it can be stepped past while repaired.
    try std.testing.expect(!Invariant.no_contested_claim.nonBypassable());
    // The remedy has to separate contested from superseded, because only one
    // of them is a defect and the two look identical in a count.
    try std.testing.expect(std.mem.indexOf(
        u8,
        Invariant.no_contested_claim.remedy(),
        "superseded",
    ) != null);
}

test "execution profile classifier debt is fatal only after a decisive profile" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_unclassified_execution_profile, .{
            .execution_profile_samples = 2,
            .execution_profile_unclassified = 2,
        }).state,
    );
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_unclassified_execution_profile, .{
            .execution_profile_readable = true,
            .execution_profile_decisive = false,
            .execution_profile_unclassified = 2,
        }).state,
    );
    const judgement = judge(.no_unclassified_execution_profile, .{
        .execution_profile_samples = 21,
        .execution_profile_readable = true,
        .execution_profile_decisive = true,
        .execution_profile_unclassified = 2,
        .execution_profile_unresolved = 1,
    });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 3), judgement.detail);
    try std.testing.expectEqual(Class.ownership, Invariant.no_unclassified_execution_profile.class());
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_unclassified_execution_profile.owner());
}

test "a settled below-budget run is a reachability failure" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_run_budget_deficit, .{ .run_budget_deficit = true }).state,
    );
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_run_budget_deficit, .{
            .run_budget_observed = false,
            .run_budget_deficit = true,
            .run_budget_required_guest_ms_per_host_second = 5,
        }).state,
    );

    const deficit = judge(.no_run_budget_deficit, .{
        .run_budget_observed = true,
        .run_budget_deficit = true,
        .run_budget_guest_ms_per_host_second = 0,
        .run_budget_required_guest_ms_per_host_second = 5,
        .run_budget_host_seconds = budget_observation_host_seconds,
    });
    try std.testing.expectEqual(State.violated, deficit.state);
    try std.testing.expectEqual(@as(u64, 5), deficit.detail);

    const healthy = judge(.no_run_budget_deficit, .{
        .run_budget_observed = true,
        .run_budget_deficit = false,
        .run_budget_guest_ms_per_host_second = 6,
        .run_budget_required_guest_ms_per_host_second = 5,
        .run_budget_host_seconds = budget_observation_host_seconds,
    });
    try std.testing.expectEqual(State.satisfied, healthy.state);
    try std.testing.expectEqual(@as(u64, 6), healthy.detail);
    try std.testing.expectEqual(Class.pressure, Invariant.no_run_budget_deficit.class());
    try std.testing.expectEqual(Owner.rosette_harness, Invariant.no_run_budget_deficit.owner());
}

test "only a causally proven deadlock is fatal" {
    const ambiguous = judge(.no_proven_deadlock, .{
        .liveness_scope = .guest_execution,
        .deadlock_observed = true,
        .deadlock_proven = false,
        .deadlock_finding = 5,
        .deadlock_waiters = 1,
        .deadlock_park_steps = 2_000_000_000,
    });
    try std.testing.expectEqual(State.not_armed, ambiguous.state);

    const pre_guest = judge(.no_proven_deadlock, .{
        .liveness_scope = .pre_guest_startup,
        .deadlock_observed = true,
        .deadlock_proven = true,
        .deadlock_finding = 4,
        .deadlock_waiters = 1,
        .deadlock_park_steps = 2_000_000_000,
    });
    try std.testing.expectEqual(State.not_armed, pre_guest.state);

    const proven = judge(.no_proven_deadlock, .{
        .liveness_scope = .guest_execution,
        .deadlock_observed = true,
        .deadlock_proven = true,
        .deadlock_finding = 4,
        .deadlock_waiters = 1,
        .deadlock_park_steps = 2_000_000_000,
    });
    try std.testing.expectEqual(State.violated, proven.state);
    try std.testing.expectEqual(@as(u64, 2_000_000_000), proven.detail);
    try std.testing.expectEqual(Class.liveness, Invariant.no_proven_deadlock.class());
    try std.testing.expectEqual(Owner.emulator_host, Invariant.no_proven_deadlock.owner());
}

test "an essential readiness gap is fatal once readiness is armed" {
    const judgement = judge(.no_unproven_essential_component, .{
        .component_readiness_armed = true,
        .essential_component_gaps = 1,
    });
    try std.testing.expectEqual(State.violated, judgement.state);
    try std.testing.expectEqual(@as(u64, 1), judgement.detail);
    try std.testing.expect(Invariant.no_unproven_essential_component.nonBypassable());
}

test "readiness is not judged before a component is observed" {
    try std.testing.expectEqual(
        State.not_armed,
        judge(.no_unproven_essential_component, .{}).state,
    );
}

test "every invariant states a label, a remedy and a class" {
    var index: u8 = 0;
    while (index < invariant_count) : (index += 1) {
        const invariant: Invariant = @enumFromInt(index);
        try std.testing.expect(invariant.label().len != 0);
        try std.testing.expect(invariant.remedy().len != 0);
        try std.testing.expect(invariant.class().label().len != 0);
        try std.testing.expect(invariant.owner().label().len != 0);
    }
    // An unmeasured run must not violate anything. This is what catches an
    // invariant added with a judgement that fires before it has an input.
    index = 0;
    while (index < invariant_count) : (index += 1) {
        const invariant: Invariant = @enumFromInt(index);
        // The empty observation is the strongest form of this check: nothing
        // has been measured, so nothing may be a violation.
        const judgement = judge(invariant, .{});
        try std.testing.expect(!judgement.violated());
    }
}
