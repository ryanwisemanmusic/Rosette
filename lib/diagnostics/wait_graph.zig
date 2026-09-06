//! Who waits on what, who signals it, and whether the handshake is going
//! anywhere.
//!
//! The livelock predictor already reports the shape:
//!
//! ```text
//! op=wait              object=0x333dec14 thread=0x7fff2160 count=1212
//! op=release_semaphore object=0x333dec14 thread=0x7fff2150 count=1218
//! op=set_event         object=0x333dec28 thread=0x7fff2150 count=1217
//! ```
//!
//! What it cannot say is who is on which end. Twelve hundred matched waits and
//! releases with nothing parked and nothing unsignalled passes every deadlock
//! check in the process, because by their question it is healthy. The pair is
//! alive, both threads are running, and the run is not moving.
//!
//! This builds the other half: a per-object waiter/signaller set, so a stalled
//! handshake names *which thread waits* and *which thread feeds it*, and a
//! bounded cycle check that finds two threads each waiting on an object only
//! the other signals.
//!
//! ## The progress gate is not optional
//!
//! Two threads passing a semaphore is what a working producer/consumer pair
//! looks like. The counters are identical to a livelocked one. Every verdict
//! here is therefore gated on an independent progress axis the caller supplies,
//! because a predictor that reports healthy worker loops as livelocks trains a
//! reader to skip the line that eventually matters.
//!
//! ## Identity is the hazard
//!
//! The same object appears as `0x333dec14`, `0x827CEC14` and `0xD1BBEC14` in
//! three different reports. Waits recorded under one name and signals under
//! another produce a phantom orphan wait next to a phantom orphan signal, which
//! is exactly the pair of findings that sends an investigation in two wrong
//! directions at once. The ledger folds addresses through a caller-supplied
//! canonical form and counts how often it had to.

const std = @import("std");
const contract = @import("xenia_wait_graph_contract");
const wait_policy = @import("xenia_wait_handshake_policy");

pub const Role = contract.Role;
pub const PairState = contract.PairState;
pub const Verdict = contract.Verdict;
pub const WaitTiming = contract.WaitTiming;
pub const minimum_handshake_sample = contract.minimum_handshake_sample;
pub const WaitHandshakePolicy = wait_policy;
pub const HandoffOrder = wait_policy.HandoffOrder;
pub const PcDomain = wait_policy.PcDomain;
pub const PcQuality = wait_policy.PcQuality;
pub const PcEvidence = wait_policy.PcEvidence;

/// Bounded, because this is fed from the guest wait path. A run with more
/// distinct sync objects than this reports the overflow rather than evicting:
/// a table that follows the most recent object makes the verdict follow it too.
pub const max_objects: usize = 64;
pub const max_participants: usize = 8;
/// Continuation evidence is bounded independently from object identities. A
/// guest can complete several waits before the next log line arrives, and
/// retaining a small set per process lets us report that loss rather than
/// overwriting the evidence for an older waiter.
pub const max_continuations: usize = 32;

/// The state vocabulary is owned by the build-time wait policy package. The
/// runtime graph only records which state the observed evidence reached.
pub const ContinuationState = wait_policy.ContinuationState;

pub const ActivityKind = enum(u8) {
    unknown,
    guest_log,
    wait_entry,
    wait_result,
    signal,

    pub fn label(self: ActivityKind) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .guest_log => "guest_log",
            .wait_entry => "wait_entry",
            .wait_result => "wait_result",
            .signal => "signal",
        };
    }
};

pub const Continuation = struct {
    active: bool = false,
    thread: u64 = 0,
    object: u64 = 0,
    wait_pc: u64 = 0,
    wait_pc_domain: PcDomain = .unknown,
    wait_pc_quality: PcQuality = .unavailable,
    wait_step: u64 = 0,
    timing: WaitTiming = .unknown,
    state: ContinuationState = .unobserved,
    next_kind: ActivityKind = .unknown,
    next_pc: u64 = 0,
    next_pc_domain: PcDomain = .unknown,
    next_pc_quality: PcQuality = .unavailable,
    next_step: u64 = 0,

    pub fn age(self: Continuation, current_step: u64) u64 {
        if (!self.active or current_step < self.wait_step) return 0;
        return current_step - self.wait_step;
    }

    pub fn waitPcEvidence(self: Continuation) PcEvidence {
        return .{
            .address = self.wait_pc,
            .domain = self.wait_pc_domain,
            .quality = self.wait_pc_quality,
        };
    }

    pub fn nextPcEvidence(self: Continuation) PcEvidence {
        return .{
            .address = self.next_pc,
            .domain = self.next_pc_domain,
            .quality = self.next_pc_quality,
        };
    }
};

pub const ContinuationSummary = struct {
    pending: usize = 0,
    observed: u64 = 0,
    same_site: u64 = 0,
    transitions: u64 = 0,
    observed_without_pc: u64 = 0,
    observed_untrusted_pc: u64 = 0,
    incomparable_pc: u64 = 0,
    unobserved: u64 = 0,
    dropped: u64 = 0,
    out_of_order: u64 = 0,
    unattributed: u64 = 0,
    max_pending_age: u64 = 0,
};

pub const Participant = struct {
    thread: u64 = 0,
    /// Execution address of the most recent operation. The domain and quality
    /// below are mandatory context: a Rosette RIP or seeded Xenia value is a
    /// useful breadcrumb, but neither is automatically a guest call site.
    pc: u64 = 0,
    pc_domain: PcDomain = .unknown,
    pc_quality: PcQuality = .unavailable,
    events: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// Same-site returns are not a proof of a bug by themselves, but they are
    /// the concrete evidence needed to distinguish "the wait returned and the
    /// caller continued" from "the same wait site was entered again".
    same_site_reentries: u64 = 0,
    /// A different observed site on the same thread is weaker than an
    /// instruction-level continuation trace, but it is still useful evidence
    /// that control flow did not immediately return to the same wait call.
    site_transitions: u64 = 0,
    /// A value was present, but at least one side was seeded/unavailable and
    /// therefore could not be promoted to same-site or transition evidence.
    pc_untrusted_events: u64 = 0,
    /// Both values were usable but came from different address spaces (for
    /// example Xenia PPC versus Rosette translated x86).
    pc_incomparable_events: u64 = 0,
};

pub const ObjectRecord = struct {
    address: u64 = 0,
    occupied: bool = false,

    waits: u64 = 0,
    signals: u64 = 0,
    /// Successful wait return status observed directly on the result line.
    /// This is deliberately separate from `successful_waits`: that counter
    /// means timing-proven ready/blocked evidence, while this counter answers
    /// the narrower question "did the kernel return STATUS_SUCCESS?". A
    /// duration-derived `wait_disposition=blocked` can be unknown timing and
    /// still carry a real success result.
    completed_successes: u64 = 0,
    successful_waits: u64 = 0,
    timed_out_waits: u64 = 0,
    blocked_successes: u64 = 0,
    ready_on_entry: u64 = 0,
    unknown_timing: u64 = 0,
    /// Timeout and object-family metadata come from the same Xenia result
    /// record. Without carrying them into the graph, a finite manual-reset
    /// poll is downgraded to an unknown object and the policy can only choose
    /// the conservative indefinite-wait action.
    object_kind: wait_policy.ObjectKind = .unknown,
    object_kind_conflicts: u64 = 0,
    timeout_class: wait_policy.TimeoutClass = .none,
    timeout_ms: i64 = 0,
    /// `timeout_ms` may come from an elapsed result duration. Preserve whether
    /// the guest request itself was actually observed so reports cannot call
    /// host timing a guest polling contract.
    timeout_requested_known: bool = false,
    timeout_requested: bool = false,
    waiters: [max_participants]Participant = [_]Participant{.{}} ** max_participants,
    waiter_count: usize = 0,
    signallers: [max_participants]Participant = [_]Participant{.{}} ** max_participants,
    signaller_count: usize = 0,
    /// Participants that did not fit. Counted so a crowded object is not
    /// mistaken for a simple one.
    participants_dropped: u64 = 0,

    first_step: u64 = 0,
    last_step: u64 = 0,
    /// Value of the caller's progress axis when this object was first seen, so
    /// the classifier can ask whether anything moved *while it cycled* rather
    /// than whether anything ever moved.
    progress_at_first: u64 = 0,
    progress_at_last: u64 = 0,
    /// Temporal witnesses for blocked waits. These are intentionally weaker
    /// than a one-to-one signal token: a manual-reset event can release more
    /// than one waiter, and a sampled log can omit an edge. The graph records
    /// the ordering it can prove and leaves the rest visible.
    has_signal: bool = false,
    last_signal_step: u64 = 0,
    blocked_after_signal: u64 = 0,
    blocked_without_prior_signal: u64 = 0,

    pub fn state(self: ObjectRecord) PairState {
        return contract.classifyPairWithTiming(
            self.waits,
            self.signals,
            self.timed_out_waits,
            self.blocked_successes,
            self.progress_at_last > self.progress_at_first,
        );
    }

    /// Apply the shared wait-handshake policy to this immutable ledger
    /// snapshot. The graph owns the object counters and progress witness; the
    /// package owns the safety decision. Unknown timing remains unknown, while
    /// explicit blocked/ready evidence is allowed to establish a handoff.
    pub fn policyDecision(self: ObjectRecord) wait_policy.Decision {
        var same_site_reentries: u64 = 0;
        var site_transitions: u64 = 0;
        for (self.waiters[0..self.waiter_count]) |participant| {
            same_site_reentries +|= participant.same_site_reentries;
            site_transitions +|= participant.site_transitions;
        }
        for (self.signallers[0..self.signaller_count]) |participant| {
            same_site_reentries +|= participant.same_site_reentries;
            site_transitions +|= participant.site_transitions;
        }
        return wait_policy.decide(.{
            .waits = self.waits,
            .signals = self.signals,
            .successful_waits = self.successful_waits,
            .timed_out_waits = self.timed_out_waits,
            .blocked_successes = self.blocked_successes,
            .ready_on_entry = self.ready_on_entry,
            .unknown_timing = self.unknown_timing,
            .waiter_count = self.waiter_count,
            .notifier_count = self.signaller_count,
            .notifications = self.signals,
            .progress = if (self.progress_at_last > self.progress_at_first) .advanced else .flat,
            .same_site_reentries = same_site_reentries,
            .site_transitions = site_transitions,
            .object_kind = self.object_kind,
            .timeout_class = self.timeout_class,
            .identity_conflict = self.object_kind_conflicts != 0,
        }, .{});
    }

    /// Whether the observed wait results include a real blocked-to-signalled
    /// handoff. This is intentionally a witness, not a claim that every wait
    /// consumed a signal: ready-on-entry, legacy result-only lines and timeout
    /// lines cannot establish that.
    pub fn blockedHandoffProven(self: ObjectRecord) bool {
        return self.blocked_successes != 0 and self.signals >= self.blocked_successes;
    }

    pub fn handoffOrder(self: ObjectRecord) HandoffOrder {
        if (self.blocked_after_signal != 0 and self.blocked_without_prior_signal != 0)
            return .mixed;
        if (self.blocked_after_signal != 0) return .signal_before_return;
        if (self.blocked_without_prior_signal != 0) return .return_without_prior_signal;
        return .unknown;
    }

    /// The thread doing the waiting, when exactly one does. A stalled handshake
    /// with a single waiter names the thread to look at; one with several is a
    /// different and harder shape, and saying so is better than picking one.
    pub fn soleWaiter(self: ObjectRecord) ?Participant {
        if (self.waiter_count != 1) return null;
        return self.waiters[0];
    }

    pub fn soleSignaller(self: ObjectRecord) ?Participant {
        if (self.signaller_count != 1) return null;
        return self.signallers[0];
    }
};

pub const Cycle = struct {
    first_thread: u64 = 0,
    second_thread: u64 = 0,
    first_object: u64 = 0,
    second_object: u64 = 0,
};

pub const Summary = struct {
    objects: usize = 0,
    dropped_objects: u64 = 0,
    orphan_waits: usize = 0,
    orphan_signals: usize = 0,
    stalled_handshakes: usize = 0,
    progressing_handshakes: usize = 0,
    insufficient: usize = 0,
    timeout_only: usize = 0,
    cycles: usize = 0,
    events: u64 = 0,
    canonical_folds: u64 = 0,
    cycle: ?Cycle = null,

    pub fn verdict(self: Summary) Verdict {
        return contract.verdictOfWithTimeouts(
            self.objects,
            self.orphan_waits,
            self.orphan_signals,
            self.stalled_handshakes,
            self.cycles,
            self.timeout_only,
        );
    }
};

/// Folds an observed address to the identity the ledger keys on. Supplied by
/// the caller because only the process knows the host/guest projections; the
/// ledger only knows that it must not key on two names for one object.
pub const CanonicalFn = *const fn (address: u64) u64;

pub const Ledger = struct {
    objects: [max_objects]ObjectRecord = [_]ObjectRecord{.{}} ** max_objects,
    occupied: usize = 0,
    dropped_objects: u64 = 0,
    events: u64 = 0,
    canonical_folds: u64 = 0,
    canonical: ?CanonicalFn = null,

    /// A completion arms one slot until the first later observable activity
    /// from that same guest thread. Completed slots are retained until reused
    /// so a blocker report can show the most recent observed continuation.
    continuations: [max_continuations]Continuation =
        [_]Continuation{.{}} ** max_continuations,
    continuation_pending_count: usize = 0,
    continuation_observed: u64 = 0,
    continuation_same_site: u64 = 0,
    continuation_transitions: u64 = 0,
    continuation_observed_without_pc: u64 = 0,
    continuation_observed_untrusted_pc: u64 = 0,
    continuation_incomparable_pc: u64 = 0,
    continuation_unobserved: u64 = 0,
    continuation_dropped: u64 = 0,
    continuation_out_of_order: u64 = 0,
    continuation_unattributed: u64 = 0,

    /// The independent progress axis. Any counter that a spin cannot advance:
    /// milestones reached, ring publications, guest output frames. Compared
    /// against itself over time, never interpreted.
    progress: u64 = 0,

    pub fn setCanonical(self: *Ledger, canonical: CanonicalFn) void {
        self.canonical = canonical;
    }

    /// Update the axis the classifier gates on. Callers push rather than the
    /// ledger pulling, so the ledger has no opinion about what progress means.
    pub fn noteProgress(self: *Ledger, value: u64) void {
        if (value > self.progress) self.progress = value;
    }

    fn activityKind(message: []const u8) ActivityKind {
        if (std.mem.indexOf(u8, message, "KeWaitForSingleObject result=") != null or
            std.mem.indexOf(u8, message, "NtWaitForSingleObjectEx result=") != null)
            return .wait_result;
        if (std.mem.indexOf(u8, message, "KeWaitForSingleObject tid=") != null or
            std.mem.indexOf(u8, message, "NtWaitForSingleObjectEx tid=") != null)
            return .wait_entry;
        if (std.mem.indexOf(u8, message, "DEBUG: xeKeSetEvent: ptr=") != null or
            std.mem.indexOf(u8, message, "KeReleaseSemaphore(") != null)
            return .signal;
        if (message.len != 0) return .guest_log;
        return .unknown;
    }

    fn finishUnobserved(self: *Ledger, entry: *Continuation) void {
        if (!entry.active) return;
        entry.active = false;
        self.continuation_pending_count -|= 1;
        self.continuation_unobserved +|= 1;
        entry.state = .unobserved;
    }

    /// Record the first guest-visible activity after a completed wait. This is
    /// intentionally separate from `observe`: a signal or another wait is an
    /// operation on an object, while this records the control-flow edge out of
    /// the prior wait. A generic log line is retained as weak evidence rather
    /// than being promoted to a proven instruction-level continuation.
    /// Compatibility entry point for legacy callers that only have an integer
    /// address. The address is retained, but without provenance it cannot prove
    /// a control-flow edge.
    pub fn observeGuestActivity(
        self: *Ledger,
        thread: u64,
        pc: u64,
        step: u64,
        message: []const u8,
    ) void {
        self.observeGuestActivityWithEvidence(thread, .{ .address = pc }, step, message);
    }

    /// Record the first activity after a wait with its address-space
    /// provenance. This is the strict path used by the Rosette/Xenia bridge.
    pub fn observeGuestActivityWithEvidence(
        self: *Ledger,
        thread: u64,
        pc: PcEvidence,
        step: u64,
        message: []const u8,
    ) void {
        if (thread == 0 or self.continuation_pending_count == 0) return;
        const kind = activityKind(message);
        for (&self.continuations) |*entry| {
            if (!entry.active or entry.thread != thread) continue;
            // A stale or same-step line from a reordered/duplicated mirror
            // must not close a live continuation. Keep the pending wait so a
            // strictly later ordered line can still provide the evidence.
            if (step <= entry.wait_step) {
                self.continuation_out_of_order +|= 1;
                continue;
            }

            entry.active = false;
            self.continuation_pending_count -|= 1;
            self.continuation_observed +|= 1;
            entry.next_kind = kind;
            entry.next_pc = pc.address;
            entry.next_pc_domain = pc.domain;
            entry.next_pc_quality = pc.quality;
            entry.next_step = step;
            const wait_pc = entry.waitPcEvidence();
            if (wait_pc.comparableWith(pc)) {
                if (wait_pc.address == pc.address) {
                    entry.state = .same_site;
                    self.continuation_same_site +|= 1;
                } else {
                    entry.state = .transitioned;
                    self.continuation_transitions +|= 1;
                }
            } else if (!wait_pc.usable() or !pc.usable()) {
                if (entry.wait_pc == 0 and pc.address == 0) {
                    entry.state = .observed_without_pc;
                    self.continuation_observed_without_pc +|= 1;
                } else {
                    entry.state = .observed_untrusted_pc;
                    self.continuation_observed_untrusted_pc +|= 1;
                }
            } else {
                entry.state = .incomparable_pc;
                self.continuation_incomparable_pc +|= 1;
            }
            return;
        }
    }

    /// Arm a continuation witness for one wait result, including a timeout.
    /// Timeouts are useful because a caller that immediately re-polls is a
    /// different shape from a caller that resumed after a real signal. They
    /// remain evidence only and never authorize a wake.
    /// Compatibility entry point for raw/legacy records. The address is
    /// retained for diagnostics, but it cannot prove a domain-local
    /// continuation without provenance.
    pub fn noteWaitCompletion(
        self: *Ledger,
        object: u64,
        thread: u64,
        pc: u64,
        step: u64,
        timing: WaitTiming,
    ) void {
        self.noteWaitCompletionWithEvidence(
            object,
            thread,
            .{ .address = pc },
            step,
            timing,
        );
    }

    pub fn noteWaitCompletionWithEvidence(
        self: *Ledger,
        object: u64,
        thread: u64,
        pc: PcEvidence,
        step: u64,
        timing: WaitTiming,
    ) void {
        if (object == 0 or thread == 0) {
            self.continuation_unattributed +|= 1;
            return;
        }
        const key = self.canonicalKey(object);

        var slot_to_use: ?*Continuation = null;
        for (&self.continuations) |*entry| {
            if (entry.active and entry.thread == thread) {
                // Two completions with no intervening activity are themselves
                // evidence that the prior continuation was not observed. Do
                // not silently overwrite it.
                self.finishUnobserved(entry);
                slot_to_use = entry;
                break;
            }
            if (!entry.active and slot_to_use == null) slot_to_use = entry;
        }
        const entry = slot_to_use orelse {
            self.continuation_dropped +|= 1;
            return;
        };
        entry.* = .{
            .active = true,
            .thread = thread,
            .object = key,
            .wait_pc = pc.address,
            .wait_pc_domain = pc.domain,
            .wait_pc_quality = pc.quality,
            .wait_step = step,
            .timing = timing,
            .state = .pending,
        };
        self.continuation_pending_count += 1;
    }

    /// Return the most recent continuation for a waiter/object pair. Copies
    /// are returned because the guest log path may receive another line while
    /// the caller is formatting a report.
    pub fn continuationFor(
        self: *const Ledger,
        object: u64,
        thread: u64,
    ) ?Continuation {
        const key = self.canonicalKey(object);
        var result: ?Continuation = null;
        for (self.continuations) |entry| {
            if (entry.thread != thread or entry.object != key) continue;
            if (result == null or entry.wait_step >= result.?.wait_step)
                result = entry;
        }
        return result;
    }

    pub fn continuationSummary(self: *const Ledger, current_step: u64) ContinuationSummary {
        var result = ContinuationSummary{
            .observed = self.continuation_observed,
            .same_site = self.continuation_same_site,
            .transitions = self.continuation_transitions,
            .observed_without_pc = self.continuation_observed_without_pc,
            .observed_untrusted_pc = self.continuation_observed_untrusted_pc,
            .incomparable_pc = self.continuation_incomparable_pc,
            .unobserved = self.continuation_unobserved,
            .dropped = self.continuation_dropped,
            .out_of_order = self.continuation_out_of_order,
            .unattributed = self.continuation_unattributed,
        };
        for (self.continuations) |entry| {
            if (!entry.active) continue;
            result.pending += 1;
            result.max_pending_age = @max(result.max_pending_age, entry.age(current_step));
        }
        return result;
    }

    fn canonicalKey(self: *const Ledger, address: u64) u64 {
        const fold = self.canonical orelse return address;
        return fold(address);
    }

    fn canonicalise(self: *Ledger, address: u64) u64 {
        const folded = self.canonicalKey(address);
        if (folded != address) self.canonical_folds +|= 1;
        return folded;
    }

    fn slot(self: *Ledger, address: u64) ?*ObjectRecord {
        const mask = max_objects - 1;
        var index: usize = @intCast(address % max_objects);
        var probes: usize = 0;
        while (probes < max_objects) : (probes += 1) {
            const entry = &self.objects[index];
            if (!entry.occupied) return entry;
            if (entry.address == address) return entry;
            index = (index + 1) & mask;
        }
        return null;
    }

    fn recordParticipant(
        list: *[max_participants]Participant,
        count: *usize,
        dropped: *u64,
        thread: u64,
        pc: PcEvidence,
        step: u64,
    ) void {
        for (list[0..count.*]) |*existing| {
            if (existing.thread != thread) continue;
            existing.events +|= 1;
            const existing_pc = PcEvidence{
                .address = existing.pc,
                .domain = existing.pc_domain,
                .quality = existing.pc_quality,
            };
            if (existing_pc.comparableWith(pc)) {
                if (existing_pc.address == pc.address) {
                    existing.same_site_reentries +|= 1;
                } else {
                    existing.site_transitions +|= 1;
                }
            } else if (existing_pc.usable() and pc.usable()) {
                existing.pc_incomparable_events +|= 1;
            } else if (existing.pc != 0 or pc.address != 0) {
                existing.pc_untrusted_events +|= 1;
            }
            existing.last_step = step;
            if (pc.address != 0) {
                existing.pc = pc.address;
                existing.pc_domain = pc.domain;
                existing.pc_quality = pc.quality;
            }
            return;
        }
        if (count.* == max_participants) {
            dropped.* +|= 1;
            return;
        }
        list[count.*] = .{
            .thread = thread,
            .pc = pc.address,
            .pc_domain = pc.domain,
            .pc_quality = pc.quality,
            .events = 1,
            .first_step = step,
            .last_step = step,
        };
        count.* += 1;
    }

    pub fn observe(
        self: *Ledger,
        role: Role,
        address: u64,
        thread: u64,
        pc: u64,
        step: u64,
    ) void {
        self.observeWithEvidence(role, address, thread, .{ .address = pc }, step);
    }

    pub fn observeWithEvidence(
        self: *Ledger,
        role: Role,
        address: u64,
        thread: u64,
        pc: PcEvidence,
        step: u64,
    ) void {
        self.observeWithTimingEvidence(role, address, thread, pc, step, .unknown, .{});
    }

    /// Record a wait with the timing breadcrumb that accompanied its result.
    /// Signal edges do not carry timing evidence and should continue to use
    /// `observe`; keeping the two entry points prevents a signal line from
    /// accidentally being counted as a successful wait.
    pub fn observeWait(
        self: *Ledger,
        address: u64,
        thread: u64,
        pc: u64,
        step: u64,
        timing: WaitTiming,
    ) void {
        self.observeWaitWithEvidence(address, thread, .{ .address = pc }, step, timing);
    }

    pub fn observeWaitWithEvidence(
        self: *Ledger,
        address: u64,
        thread: u64,
        pc: PcEvidence,
        step: u64,
        timing: WaitTiming,
    ) void {
        self.observeWithTimingEvidence(.waiter, address, thread, pc, step, timing, .{});
    }

    /// Record a wait with the timeout/object-family facts emitted by Xenia.
    /// The ordinary entry point remains for legacy callers whose lines do not
    /// carry enough metadata to classify the timeout.
    pub fn observeWaitWithTimeoutEvidence(
        self: *Ledger,
        address: u64,
        thread: u64,
        pc: PcEvidence,
        step: u64,
        timing: WaitTiming,
        timeout: wait_policy.TimeoutEvidence,
    ) void {
        self.observeWithTimingEvidence(.waiter, address, thread, pc, step, timing, timeout);
    }

    /// Reconcile a raw successful wait result with the wait edge already
    /// recorded for the same result line. This must not increment `waits` or
    /// emit another participant event: it is a second fact about one wait,
    /// not a second wait.
    pub fn noteSuccessfulWaitResult(self: *Ledger, address: u64) void {
        if (address == 0) return;
        const key = self.canonicalKey(address);
        const entry = self.slot(key) orelse {
            self.dropped_objects +|= 1;
            return;
        };
        // A well-formed result has already gone through observeWait*. Keep a
        // defensive initialization for callers that feed a result-only line
        // into the reconciliation API directly.
        if (!entry.occupied) {
            entry.* = .{ .address = key, .occupied = true };
            self.occupied += 1;
        }
        entry.completed_successes +|= 1;
    }

    fn observeWithTimingEvidence(
        self: *Ledger,
        role: Role,
        address: u64,
        thread: u64,
        pc: PcEvidence,
        step: u64,
        timing: WaitTiming,
        timeout: wait_policy.TimeoutEvidence,
    ) void {
        if (address == 0) return;
        self.events +|= 1;
        const key = self.canonicalise(address);
        const entry = self.slot(key) orelse {
            self.dropped_objects +|= 1;
            return;
        };
        if (!entry.occupied) {
            entry.* = .{
                .address = key,
                .occupied = true,
                .first_step = step,
                .progress_at_first = self.progress,
            };
            self.occupied += 1;
        }
        entry.last_step = step;
        entry.progress_at_last = self.progress;
        if (timeout.object_kind != .unknown) {
            if (entry.object_kind == .unknown) {
                entry.object_kind = timeout.object_kind;
            } else if (entry.object_kind != timeout.object_kind) {
                entry.object_kind_conflicts +|= 1;
                entry.object_kind = .unknown;
            }
        }
        switch (role) {
            .waiter => {
                entry.waits +|= 1;
                switch (timing) {
                    .unknown => entry.unknown_timing +|= 1,
                    .ready_on_entry => {
                        entry.successful_waits +|= 1;
                        entry.ready_on_entry +|= 1;
                    },
                    .blocked => {
                        entry.successful_waits +|= 1;
                        entry.blocked_successes +|= 1;
                        if (entry.has_signal and entry.last_signal_step <= step) {
                            entry.blocked_after_signal +|= 1;
                        } else {
                            entry.blocked_without_prior_signal +|= 1;
                        }
                    },
                    .timed_out => {
                        entry.timed_out_waits +|= 1;
                        const timeout_class = wait_policy.classifyTimeout(timeout);
                        if (entry.timeout_class == .none or entry.timeout_class == .unknown) {
                            entry.timeout_class = timeout_class;
                            if (timeout.timeout_known) entry.timeout_ms = timeout.timeout_ms;
                        } else if (entry.timeout_class != timeout_class or
                            (timeout.requested_known and entry.timeout_requested_known and
                                timeout.requested != entry.timeout_requested))
                        {
                            entry.timeout_class = .mixed;
                        }
                        if (timeout.requested_known) {
                            entry.timeout_requested_known = true;
                            entry.timeout_requested = timeout.requested;
                        }
                    },
                }
                recordParticipant(
                    &entry.waiters,
                    &entry.waiter_count,
                    &entry.participants_dropped,
                    thread,
                    pc,
                    step,
                );
            },
            .signaller => {
                entry.signals +|= 1;
                entry.has_signal = true;
                entry.last_signal_step = step;
                recordParticipant(
                    &entry.signallers,
                    &entry.signaller_count,
                    &entry.participants_dropped,
                    thread,
                    pc,
                    step,
                );
            },
        }
    }

    pub fn record(self: *const Ledger, address: u64) ?ObjectRecord {
        const key = self.canonicalKey(address);
        for (self.objects) |entry| {
            if (entry.occupied and entry.address == key) return entry;
        }
        return null;
    }

    /// Two threads each waiting on an object only the other signals.
    ///
    /// Bounded to pairs on purpose. A longer chain is possible in principle and
    /// has never appeared in this system, and an unbounded search over a table
    /// written from the guest wait path is a cost with no demonstrated payoff.
    /// A pair is the shape that actually occurs, and reporting it precisely
    /// beats reporting a general cycle vaguely.
    pub fn findCycle(self: *const Ledger) ?Cycle {
        for (self.objects) |first| {
            if (!first.occupied) continue;
            // A reciprocal shape below the handshake maturity threshold is
            // only a coincidence. The summary already reports those objects as
            // insufficient; allowing them into the cycle detector would turn
            // that same evidence into a stronger, contradictory finding.
            if (first.state() != .handshake_stalled) continue;
            const first_waiter = first.soleWaiter() orelse continue;
            const first_signaller = first.soleSignaller() orelse continue;
            if (first_waiter.thread == first_signaller.thread) continue;

            for (self.objects) |second| {
                if (!second.occupied or second.address == first.address) continue;
                if (second.state() != .handshake_stalled) continue;
                const second_waiter = second.soleWaiter() orelse continue;
                const second_signaller = second.soleSignaller() orelse continue;
                // A waits on X that only B signals; B waits on Y that only A
                // signals.
                if (second_waiter.thread == first_signaller.thread and
                    second_signaller.thread == first_waiter.thread)
                {
                    return .{
                        .first_thread = first_waiter.thread,
                        .second_thread = second_waiter.thread,
                        .first_object = first.address,
                        .second_object = second.address,
                    };
                }
            }
        }
        return null;
    }

    pub fn summary(self: *const Ledger) Summary {
        var totals = Summary{
            .objects = self.occupied,
            .dropped_objects = self.dropped_objects,
            .events = self.events,
            .canonical_folds = self.canonical_folds,
        };
        for (self.objects) |entry| {
            if (!entry.occupied) continue;
            switch (entry.state()) {
                .wait_never_signalled => totals.orphan_waits += 1,
                .signal_never_waited => totals.orphan_signals += 1,
                .handshake_stalled => totals.stalled_handshakes += 1,
                .handshake_progressing => totals.progressing_handshakes += 1,
                .insufficient_sample => totals.insufficient += 1,
                .timeout_only => totals.timeout_only += 1,
                .unobserved => {},
            }
        }
        if (self.findCycle()) |cycle| {
            totals.cycles = 1;
            totals.cycle = cycle;
        }
        return totals;
    }

    /// The object a reader should look at first: a cycle member, then a stalled
    /// handshake, then an orphan wait, ordered by how little a longer run can
    /// do about it.
    pub fn blocking(self: *const Ledger) ?ObjectRecord {
        var best: ?ObjectRecord = null;
        var best_rank: u8 = 0;
        for (self.objects) |entry| {
            if (!entry.occupied) continue;
            const rank: u8 = switch (entry.state()) {
                .handshake_stalled => 3,
                .wait_never_signalled => 2,
                .signal_never_waited => 1,
                else => 0,
            };
            if (rank == 0) continue;
            // Among equals prefer the busiest: a pair that has gone round a
            // thousand times is a stronger finding than one that has gone
            // round nine.
            const better = rank > best_rank or
                (rank == best_rank and best != null and
                    entry.waits + entry.signals > best.?.waits + best.?.signals);
            if (best == null or better) {
                best = entry;
                best_rank = rank;
            }
        }
        return best;
    }
};

fn foldLowBits(address: u64) u64 {
    // Test double for the real projection fold: three names for one object
    // share their low bits.
    return address & 0xFFFF;
}

fn trackedGuestPc(address: u64) PcEvidence {
    return .{
        .address = address,
        .domain = .xenia_guest_ppc,
        .quality = .tracked,
    };
}

test "the live shape: a matched handshake with nothing else moving" {
    // 1212 waits from one thread, 1218 releases from another, progress flat.
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 40) : (round += 1) {
        ledger.observe(.signaller, 0x333d_ec14, 0x7fff_2150, 0x1bd9d0, round * 10);
        ledger.observeWait(0x333d_ec14, 0x7fff_2160, 0x1bd7c0, round * 10 + 1, .blocked);
    }

    const record = ledger.record(0x333d_ec14).?;
    try std.testing.expectEqual(PairState.handshake_stalled, record.state());
    try std.testing.expectEqual(@as(u64, 0x7fff_2160), record.soleWaiter().?.thread);
    try std.testing.expectEqual(@as(u64, 0x7fff_2150), record.soleSignaller().?.thread);
    // The call sites, so a reader goes straight there.
    try std.testing.expectEqual(@as(u64, 0x1bd7c0), record.soleWaiter().?.pc);
    try std.testing.expectEqual(@as(u64, 0x1bd9d0), record.soleSignaller().?.pc);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.stalled_handshakes);
    try std.testing.expectEqual(Verdict.handshake_without_progress, totals.verdict());
    try std.testing.expect(!totals.verdict().selfResolving());
}

test "wait timing records only the evidence the line actually carries" {
    var ledger = Ledger{};
    const object: u64 = 0x333d_ec14;

    ledger.observeWait(object, 0xAAAA, 0x10, 1, .blocked);
    ledger.observeWait(object, 0xAAAA, 0x10, 2, .ready_on_entry);
    ledger.observeWait(object, 0xAAAA, 0x10, 3, .unknown);
    ledger.observeWait(object, 0xAAAA, 0x10, 4, .timed_out);
    ledger.observe(.signaller, object, 0xBBBB, 0x20, 5);

    const record = ledger.record(object).?;
    try std.testing.expectEqual(@as(u64, 4), record.waits);
    try std.testing.expectEqual(@as(u64, 2), record.successful_waits);
    try std.testing.expectEqual(@as(u64, 1), record.blocked_successes);
    try std.testing.expectEqual(@as(u64, 1), record.ready_on_entry);
    try std.testing.expectEqual(@as(u64, 1), record.unknown_timing);
    try std.testing.expectEqual(@as(u64, 1), record.timed_out_waits);
    try std.testing.expect(record.blockedHandoffProven());
}

test "blocked handoff ordering is recorded without claiming one-to-one tokens" {
    var ordered = Ledger{};
    ordered.observe(.signaller, 0x9100, 0xBBBB, 0x20, 10);
    ordered.observeWait(0x9100, 0xAAAA, 0x10, 11, .blocked);
    const ordered_record = ordered.record(0x9100).?;
    try std.testing.expectEqual(HandoffOrder.signal_before_return, ordered_record.handoffOrder());
    try std.testing.expectEqual(@as(u64, 1), ordered_record.blocked_after_signal);
    try std.testing.expectEqual(@as(u64, 0), ordered_record.blocked_without_prior_signal);
    try std.testing.expectEqual(@as(u64, 10), ordered_record.last_signal_step);

    var ambiguous = Ledger{};
    ambiguous.observeWait(0x9200, 0xAAAA, 0x10, 20, .blocked);
    ambiguous.observe(.signaller, 0x9200, 0xBBBB, 0x20, 21);
    const ambiguous_record = ambiguous.record(0x9200).?;
    try std.testing.expectEqual(HandoffOrder.return_without_prior_signal, ambiguous_record.handoffOrder());
    try std.testing.expectEqual(@as(u64, 1), ambiguous_record.blocked_without_prior_signal);
    try std.testing.expectEqual(@as(u64, 0), ambiguous_record.blocked_after_signal);
}

test "timeout-only waits stay out of orphan and blocker accounting" {
    var ledger = Ledger{};
    var attempt: u64 = 0;
    while (attempt < 4) : (attempt += 1) {
        ledger.observeWait(0x4000_4bf4, 0x7fff_2000, 0x1be680, attempt, .timed_out);
    }

    const record = ledger.record(0x4000_4bf4).?;
    try std.testing.expectEqual(PairState.timeout_only, record.state());
    try std.testing.expectEqual(@as(usize, 0), ledger.summary().orphan_waits);
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().timeout_only);
    try std.testing.expectEqual(Verdict.timeout_without_signal, ledger.summary().verdict());
    try std.testing.expect(ledger.blocking() == null);
    try std.testing.expectEqual(
        wait_policy.Classification.timeout_only,
        record.policyDecision().classification,
    );
}

test "unknown and ready waits cannot manufacture an orphan consumer" {
    var unknown = Ledger{};
    var attempt: u64 = 0;
    while (attempt < 25) : (attempt += 1) {
        unknown.observeWait(0x3004_0018, 0x7fff_2170, 0x1be680, attempt, .unknown);
    }
    const unknown_record = unknown.record(0x3004_0018).?;
    try std.testing.expectEqual(PairState.insufficient_sample, unknown_record.state());
    try std.testing.expectEqual(@as(usize, 0), unknown.summary().orphan_waits);
    try std.testing.expect(unknown.blocking() == null);
    try std.testing.expectEqual(
        wait_policy.Classification.insufficient_evidence,
        unknown_record.policyDecision().classification,
    );

    var ready = Ledger{};
    attempt = 0;
    while (attempt < 25) : (attempt += 1) {
        ready.observeWait(0x3004_0018, 0x7fff_2170, 0x1be680, attempt, .ready_on_entry);
    }
    const ready_record = ready.record(0x3004_0018).?;
    try std.testing.expectEqual(PairState.insufficient_sample, ready_record.state());
    try std.testing.expectEqual(@as(usize, 0), ready.summary().orphan_waits);
    try std.testing.expect(ready.blocking() == null);
    try std.testing.expectEqual(
        wait_policy.Classification.ready_without_park,
        ready_record.policyDecision().classification,
    );
}

test "a causally proven blocked wait without a signal remains an orphan" {
    var ledger = Ledger{};
    ledger.observeWait(0x3004_0018, 0x7fff_2170, 0x1be680, 1, .blocked);

    const record = ledger.record(0x3004_0018).?;
    try std.testing.expectEqual(PairState.wait_never_signalled, record.state());
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().orphan_waits);
    try std.testing.expectEqual(@as(u64, 0x3004_0018), ledger.blocking().?.address);
}

test "policy sees a proven flat guest handshake as a non-resumable fault" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 8) : (round += 1) {
        ledger.observeWait(0x333d_ec14, 0x7fff_2160, 0x1be680, round, .blocked);
        ledger.observe(.signaller, 0x333d_ec14, 0x7fff_2160, 0x1be890, round);
    }
    const policy_decision = ledger.record(0x333d_ec14).?.policyDecision();
    try std.testing.expectEqual(wait_policy.Classification.handshake_stalled, policy_decision.classification);
    try std.testing.expectEqual(wait_policy.Action.fault_before_resume, policy_decision.action);
    try std.testing.expect(!policy_decision.may_resume);
}

test "participant records same-site reentries separately from site transitions" {
    var ledger = Ledger{};
    const object: u64 = 0x9100;

    ledger.observeWaitWithEvidence(object, 0xAAAA, trackedGuestPc(0x10), 1, .blocked);
    ledger.observeWaitWithEvidence(object, 0xAAAA, trackedGuestPc(0x10), 2, .blocked);
    ledger.observeWaitWithEvidence(object, 0xAAAA, trackedGuestPc(0x11), 3, .blocked);

    const participant = ledger.record(object).?.soleWaiter().?;
    try std.testing.expectEqual(@as(u64, 3), participant.events);
    try std.testing.expectEqual(@as(u64, 1), participant.same_site_reentries);
    try std.testing.expectEqual(@as(u64, 1), participant.site_transitions);
    try std.testing.expectEqual(@as(u64, 0x11), participant.pc);
}

test "the same handshake stops being a finding when progress advances" {
    // The gate. Without it every healthy worker loop reads as a livelock.
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 40) : (round += 1) {
        ledger.noteProgress(round);
        ledger.observe(.signaller, 0x333d_ec14, 0x7fff_2150, 0x1bd9d0, round * 10);
        ledger.observeWait(0x333d_ec14, 0x7fff_2160, 0x1bd7c0, round * 10 + 1, .blocked);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 0), totals.stalled_handshakes);
    try std.testing.expectEqual(@as(usize, 1), totals.progressing_handshakes);
    try std.testing.expectEqual(Verdict.healthy, totals.verdict());
}

test "two threads each waiting on the other's object is a cycle" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        // Thread A waits on X, thread B signals X.
        ledger.observeWait(0x1000, 0xAAAA, 0x10, round, .blocked);
        ledger.observe(.signaller, 0x1000, 0xBBBB, 0x20, round);
        // Thread B waits on Y, thread A signals Y.
        ledger.observeWait(0x2000, 0xBBBB, 0x30, round, .blocked);
        ledger.observe(.signaller, 0x2000, 0xAAAA, 0x40, round);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.cycles);
    try std.testing.expectEqual(Verdict.wait_cycle, totals.verdict());
    const cycle = totals.cycle.?;
    try std.testing.expect(cycle.first_thread != cycle.second_thread);
    try std.testing.expect(cycle.first_object != cycle.second_object);
}

test "an immature reciprocal shape is not a cycle" {
    // The final round is deliberately removed from the threshold by using one
    // fewer complete observations: reciprocal ownership is not enough to name
    // a deadlock cycle.
    var immature = Ledger{};
    var round: u64 = 0;
    while (round < minimum_handshake_sample - 1) : (round += 1) {
        immature.observeWait(0x1100, 0xAAAA, 0x10, round, .blocked);
        immature.observe(.signaller, 0x1100, 0xBBBB, 0x20, round);
        immature.observeWait(0x2200, 0xBBBB, 0x30, round, .blocked);
        immature.observe(.signaller, 0x2200, 0xAAAA, 0x40, round);
    }
    const totals = immature.summary();
    try std.testing.expectEqual(@as(usize, 2), totals.insufficient);
    try std.testing.expectEqual(@as(usize, 0), totals.cycles);
    try std.testing.expectEqual(Verdict.healthy, totals.verdict());
}

test "progressing reciprocal handshakes are not a deadlock cycle" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < minimum_handshake_sample + 4) : (round += 1) {
        ledger.noteProgress(round + 1);
        ledger.observeWait(0x3300, 0xAAAA, 0x10, round, .blocked);
        ledger.observe(.signaller, 0x3300, 0xBBBB, 0x20, round);
        ledger.observeWait(0x4400, 0xBBBB, 0x30, round, .blocked);
        ledger.observe(.signaller, 0x4400, 0xAAAA, 0x40, round);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 2), totals.progressing_handshakes);
    try std.testing.expectEqual(@as(usize, 0), totals.cycles);
    try std.testing.expectEqual(Verdict.healthy, totals.verdict());
}

test "an orphan wait and an orphan signal are kept apart" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        ledger.observeWait(0x3000, 0xAAAA, 0x10, round, .blocked);
        ledger.observe(.signaller, 0x4000, 0xBBBB, 0x20, round);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.orphan_waits);
    try std.testing.expectEqual(@as(usize, 1), totals.orphan_signals);
    // The orphan wait is the stall; the orphan signal says the consumer is
    // elsewhere. The verdict reports the one a longer run cannot fix.
    try std.testing.expectEqual(Verdict.orphan_wait, totals.verdict());
    try std.testing.expectEqual(@as(u64, 0x3000), ledger.blocking().?.address);
}

test "one object under three names is folded into one identity" {
    // Waits under one address and signals under another manufacture a phantom
    // orphan wait beside a phantom orphan signal — two wrong findings at once.
    var ledger = Ledger{};
    ledger.setCanonical(foldLowBits);
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        ledger.observeWait(0x333d_ec14, 0xAAAA, 0x10, round, .blocked);
        ledger.observe(.signaller, 0x827c_ec14, 0xBBBB, 0x20, round);
        ledger.observe(.signaller, 0xd1bb_ec14, 0xBBBB, 0x20, round);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.objects);
    try std.testing.expectEqual(@as(usize, 0), totals.orphan_waits);
    try std.testing.expectEqual(@as(usize, 0), totals.orphan_signals);
    try std.testing.expectEqual(@as(usize, 1), totals.stalled_handshakes);
    try std.testing.expect(totals.canonical_folds != 0);
}

test "without a fold the same three names look like three broken objects" {
    // The counterpart: this is what the report says when identity is wrong,
    // and it is why the fold is worth its cost.
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        ledger.observeWait(0x333d_ec14, 0xAAAA, 0x10, round, .blocked);
        ledger.observe(.signaller, 0x827c_ec14, 0xBBBB, 0x20, round);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 2), totals.objects);
    try std.testing.expectEqual(@as(usize, 1), totals.orphan_waits);
    try std.testing.expectEqual(@as(usize, 1), totals.orphan_signals);
    try std.testing.expectEqual(@as(u64, 0), totals.canonical_folds);
}

test "several waiters on one object is reported rather than guessed at" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        ledger.observeWait(0x5000, 0xAAAA, 0x10, round, .blocked);
        ledger.observeWait(0x5000, 0xCCCC, 0x11, round, .blocked);
        ledger.observe(.signaller, 0x5000, 0xBBBB, 0x20, round);
    }
    const record = ledger.record(0x5000).?;
    try std.testing.expectEqual(@as(usize, 2), record.waiter_count);
    // Naming one of two waiters would send a reader to a coin flip.
    try std.testing.expect(record.soleWaiter() == null);
    try std.testing.expectEqual(@as(u64, 0xBBBB), record.soleSignaller().?.thread);
    // A crowd is not a cycle.
    try std.testing.expect(ledger.findCycle() == null);
}

test "the busiest stalled handshake is the one reported" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 10) : (round += 1) {
        ledger.observeWait(0x6000, 0xAAAA, 0x10, round, .blocked);
        ledger.observe(.signaller, 0x6000, 0xBBBB, 0x20, round);
    }
    round = 0;
    while (round < 400) : (round += 1) {
        ledger.observeWait(0x7000, 0xCCCC, 0x30, round, .blocked);
        ledger.observe(.signaller, 0x7000, 0xDDDD, 0x40, round);
    }
    try std.testing.expectEqual(@as(u64, 0x7000), ledger.blocking().?.address);
}

test "a full table counts the overflow rather than evicting" {
    var ledger = Ledger{};
    var index: u64 = 1;
    while (index <= max_objects + 6) : (index += 1) {
        ledger.observe(.waiter, index * 0x1000, 0xAAAA, 0x10, index);
    }
    try std.testing.expectEqual(max_objects, ledger.summary().objects);
    try std.testing.expect(ledger.summary().dropped_objects != 0);
}

test "an empty graph concludes nothing" {
    const ledger = Ledger{};
    const totals = ledger.summary();
    try std.testing.expectEqual(Verdict.idle, totals.verdict());
    try std.testing.expect(ledger.blocking() == null);
    try std.testing.expect(ledger.findCycle() == null);
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict().guidance(), "nothing can be said") != null);
}

test "participants beyond the retained set are counted" {
    var ledger = Ledger{};
    var thread: u64 = 1;
    while (thread <= max_participants + 3) : (thread += 1) {
        ledger.observe(.waiter, 0x8000, thread, 0x10, thread);
    }
    const record = ledger.record(0x8000).?;
    try std.testing.expectEqual(max_participants, record.waiter_count);
    try std.testing.expectEqual(@as(u64, 3), record.participants_dropped);
}

test "wait continuations distinguish same-site reentry from a site transition" {
    var ledger = Ledger{};
    const object: u64 = 0x3337_ec14;
    const thread: u64 = 0x7fff_2170;

    ledger.noteWaitCompletionWithEvidence(object, thread, trackedGuestPc(0x1be680), 100, .blocked);
    const pending = ledger.continuationSummary(104);
    try std.testing.expectEqual(@as(usize, 1), pending.pending);
    try std.testing.expectEqual(@as(u64, 4), pending.max_pending_age);

    ledger.observeGuestActivityWithEvidence(thread, trackedGuestPc(0x1be680), 105, "guest continuation");
    var summary = ledger.continuationSummary(105);
    try std.testing.expectEqual(@as(usize, 0), summary.pending);
    try std.testing.expectEqual(@as(u64, 1), summary.observed);
    try std.testing.expectEqual(@as(u64, 1), summary.same_site);
    try std.testing.expectEqual(@as(u64, 0), summary.transitions);
    try std.testing.expectEqual(
        ContinuationState.same_site,
        ledger.continuationFor(object, thread).?.state,
    );

    ledger.noteWaitCompletionWithEvidence(object, thread, trackedGuestPc(0x1be680), 200, .blocked);
    ledger.observeGuestActivityWithEvidence(
        thread,
        trackedGuestPc(0x1be890),
        201,
        "KeReleaseSemaphore(3337ec14, 00000001, 00000000, 00000000)",
    );
    summary = ledger.continuationSummary(201);
    try std.testing.expectEqual(@as(u64, 2), summary.observed);
    try std.testing.expectEqual(@as(u64, 1), summary.same_site);
    try std.testing.expectEqual(@as(u64, 1), summary.transitions);
    try std.testing.expect(
        ledger.continuationFor(object, thread).?.state.provesControlFlowTransition(),
    );
}

test "wait continuation loss is reported instead of overwritten" {
    var ledger = Ledger{};
    const object: u64 = 0x3337_ec14;
    const thread: u64 = 0x7fff_2170;

    ledger.noteWaitCompletion(object, thread, 0, 10, .blocked);
    // A second result with no intervening activity cannot be treated as the
    // continuation of the first. The first record is explicitly unobserved.
    ledger.noteWaitCompletion(object, thread, 0, 20, .blocked);
    var summary = ledger.continuationSummary(20);
    try std.testing.expectEqual(@as(u64, 1), summary.unobserved);
    try std.testing.expectEqual(@as(usize, 1), summary.pending);

    ledger.observeGuestActivity(thread, 0, 21, "next guest line");
    summary = ledger.continuationSummary(21);
    try std.testing.expectEqual(@as(u64, 1), summary.observed_without_pc);
    try std.testing.expectEqual(
        ContinuationState.observed_without_pc,
        ledger.continuationFor(object, thread).?.state,
    );
}

test "continuation refuses to promote seeded or cross-domain PCs" {
    var seeded = Ledger{};
    const object: u64 = 0x9100;
    const thread: u64 = 0xAAAA;
    seeded.noteWaitCompletionWithEvidence(object, thread, .{
        .address = 0x1be680,
        .domain = .xenia_guest_ppc,
        .quality = .seeded,
    }, 10, .blocked);
    seeded.observeGuestActivityWithEvidence(thread, .{
        .address = 0x1be690,
        .domain = .xenia_guest_ppc,
        .quality = .tracked,
    }, 11, "seeded guest continuation");
    try std.testing.expectEqual(
        ContinuationState.observed_untrusted_pc,
        seeded.continuationFor(object, thread).?.state,
    );
    try std.testing.expectEqual(@as(u64, 1), seeded.continuationSummary(11).observed_untrusted_pc);

    var split = Ledger{};
    split.noteWaitCompletionWithEvidence(object, thread, trackedGuestPc(0x1be680), 20, .blocked);
    split.observeGuestActivityWithEvidence(thread, .{
        .address = 0x2ef558,
        .domain = .rosette_translated_x86,
        .quality = .direct,
    }, 21, "translated host continuation");
    try std.testing.expectEqual(
        ContinuationState.incomparable_pc,
        split.continuationFor(object, thread).?.state,
    );
    try std.testing.expectEqual(@as(u64, 1), split.continuationSummary(21).incomparable_pc);
}

test "out-of-order guest activity does not close a wait continuation" {
    var ledger = Ledger{};
    const object: u64 = 0x9100;
    const thread: u64 = 0xAAAA;

    ledger.noteWaitCompletionWithEvidence(object, thread, trackedGuestPc(0x10), 100, .timed_out);
    ledger.observeGuestActivityWithEvidence(thread, trackedGuestPc(0x20), 99, "old mirrored line");
    ledger.observeGuestActivityWithEvidence(thread, trackedGuestPc(0x20), 100, "duplicate-step mirrored line");
    var summary = ledger.continuationSummary(100);
    try std.testing.expectEqual(@as(usize, 1), summary.pending);
    try std.testing.expectEqual(@as(u64, 2), summary.out_of_order);

    ledger.observeGuestActivityWithEvidence(thread, trackedGuestPc(0x20), 101, "new mirrored line");
    summary = ledger.continuationSummary(101);
    try std.testing.expectEqual(@as(usize, 0), summary.pending);
    try std.testing.expectEqual(@as(u64, 1), summary.transitions);
}
