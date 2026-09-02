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

pub const schema_version: u16 = 4;

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
            => .emulator_host,
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
            .translation_cache_converges => "live byte-valid decodes are being evicted faster than vacant ways fill; the cache-pressure page list names the hot pages, and the fix is capacity or separating immutable image code from mutable JIT code",
            .no_recorded_anomaly => "the anomaly ledger recorded something; it names the kind, and for an emulator assertion the file, line and function it came from",
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
        };
    }

    /// This invariant cannot be stepped past. An ordering inversion here is not
    /// merely a bad result that can be documented while the run continues: it
    /// means a callback or another GPU dependency was allowed to act against a
    /// state that did not exist. Warn/observe and allow-list controls remain
    /// useful for ordinary findings, but must not reopen this admission hole.
    pub fn nonBypassable(self: Invariant) bool {
        return self == .no_gpu_preinitialization_order_inversion;
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

    // Liveness, ownership and substantiation.
    /// The application boundary that makes a missing notifier actionable. A
    /// pre-guest-startup wait is retained in the diagnostics but is not enough
    /// to terminate a run that has not reached the hosted application yet.
    liveness_scope: LivenessScope = .pre_guest_startup,
    /// Objects with waiters and no notifier at all, past the liveness
    /// classifier's own stall threshold.
    waiters_without_a_notifier: u64 = 0,
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

/// How many timeouts a wait may accumulate with no signal at all before it
/// stops being a poll and becomes a signal that never arrives.
pub const unsignalled_timeout_limit: u64 = 32;

/// How long the producer must be quiet before "no frame yet" becomes "no
/// handoff".
pub const output_handoff_quiet_steps: u64 = 1_000_000_000;

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
            break :blk .{
                .state = if (observation.recorded_anomalies == 0) .satisfied else .violated,
                .detail = observation.recorded_anomalies,
            };
        },
        .every_waiter_has_a_notifier => blk: {
            if (!observation.liveness_scope.notifierChecksArmed()) break :blk .{};
            if (observation.waiters_without_a_notifier == 0) break :blk .{ .state = .satisfied };
            // Gated on an independent progress axis, like every other predictor
            // here. Three condvars parked from startup in a run that is
            // otherwise advancing are idle workers; the same three in a run
            // that has stopped moving are the finding.
            if (observation.progress_since_never_notified_park) break :blk .{
                .state = .satisfied,
                .detail = observation.waiters_without_a_notifier,
            };
            break :blk .{
                .state = .violated,
                .detail = observation.waiters_without_a_notifier,
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
        }).state,
    );
    try std.testing.expect(judge(.no_never_notified_park, .{
        .liveness_scope = scope,
        .longest_never_notified_park_steps = never_notified_park_steps,
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
test "the observed run violates five invariants and stops at Rosette's" {
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
    try std.testing.expectEqual(@as(usize, 5), violations);
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
    try std.testing.expectEqual(Invariant.no_never_notified_park, firstToStopAt(judgements).?);
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
    };
    try std.testing.expectEqual(@as(u64, 3), judge(.every_waiter_has_a_notifier, advancing).detail);
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
