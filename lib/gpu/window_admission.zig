//! The record of what was forwarded into Rosette's window and what happened.
//!
//! The contract in `cocoa_window_admission_contract` decides; this keeps the
//! evidence. They are separate because the decision has to be a pure function
//! of stated facts — testable without a window, a run or a guest — while the
//! evidence has to survive a whole run and be readable at the end of it.
//!
//! The defect this was written against: Rosette's window presented 99 frames in
//! a 10.5-billion-step run and the frame-custody ledger recorded zero of them,
//! because custody was wired only to the guest frame source and Rosette's own
//! diagnostic presentations went straight to the drawable. A window that shows
//! pixels nothing took custody of cannot answer "who put that there", which is
//! the only question the ownership model exists to answer.
//!
//! Indexing is dense on `(facility, operation)` rather than on the request
//! triple: this is consulted at every Objective-C message into a window token,
//! and a linear scan on a per-message hook has already cost this codebase about
//! ten times its throughput once.

const std = @import("std");
const contract = @import("cocoa_window_admission_contract");

pub const Actor = contract.Actor;
pub const Facility = contract.Facility;
pub const Operation = contract.Operation;
pub const Condition = contract.Condition;
pub const ConditionMask = contract.ConditionMask;
pub const Verdict = contract.Verdict;
pub const Decision = contract.Decision;
pub const Request = contract.Request;
pub const FaultPolicy = contract.FaultPolicy;
pub const Disposition = contract.Disposition;
pub const SwapBoundary = contract.SwapBoundary;
pub const SwapProvenance = contract.SwapProvenance;
pub const SwapEvidence = contract.SwapEvidence;
pub const SwapVerdict = contract.SwapVerdict;

pub const schema_version = contract.schema_version;

pub const facility_count = contract.facility_count;
pub const operation_count = contract.operation_count;
pub const swap_boundary_count = contract.swap_boundary_count;
pub const conditionBit = contract.conditionBit;
pub const conditionsOf = contract.conditionsOf;
const verdict_count: usize = @typeInfo(Verdict).@"enum".fields.len;
const swap_verdict_count: usize = @typeInfo(SwapVerdict).@"enum".fields.len;

/// How many refusals keep their full detail. Bounded because a refused
/// forwarding can repeat at guest instruction rate; the counters stay exact and
/// only the per-occurrence detail is capped.
pub const detail_capacity: usize = 32;

pub const Entry = struct {
    verdicts: [verdict_count]u64 = [_]u64{0} ** verdict_count,
    observations: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    last_actor: Actor = .unknown,
    last_verdict: Verdict = .admitted,
    last_missing: ConditionMask = 0,
    /// Domains seen forwarding this pair, as a bitmask over `Actor`.
    actor_mask: u16 = 0,

    pub fn admitted(self: Entry) u64 {
        return self.verdicts[@intFromEnum(Verdict.admitted)];
    }

    pub fn refused(self: Entry) u64 {
        return self.observations -| self.admitted();
    }

    pub fn touched(self: Entry) bool {
        return self.observations != 0;
    }

    /// True when the pair was only ever admitted. A collapsed report prints
    /// nothing for these, which is the whole point of collapsing.
    pub fn clean(self: Entry) bool {
        return self.observations != 0 and self.refused() == 0;
    }
};

pub const Detail = struct {
    sequence: u64 = 0,
    actor: Actor = .unknown,
    facility: Facility = .window,
    operation: Operation = .query,
    verdict: Verdict = .admitted,
    disposition: Disposition = .admit,
    missing: ConditionMask = 0,
    step: u64 = 0,
    /// The boundary the forwarding arrived on, as the caller named it. Free
    /// text is deliberate: it is the selector, import or packet name, and it
    /// exists so a refusal points at a line of code rather than at a category.
    origin: [48]u8 = [_]u8{0} ** 48,
    origin_len: u8 = 0,

    pub fn originName(self: *const Detail) []const u8 {
        return self.origin[0..self.origin_len];
    }
};

pub const SwapEntry = struct {
    verdicts: [swap_verdict_count]u64 = [_]u64{0} ** swap_verdict_count,
    observations: u64 = 0,
    admissions: u64 = 0,
    harness_admissions: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    last_verdict: SwapVerdict = .refused_provenance_insufficient,
    best_provenance: SwapProvenance = .none,

    pub fn touched(self: SwapEntry) bool {
        return self.observations != 0;
    }
};

pub const Summary = struct {
    observations: u64 = 0,
    admitted: u64 = 0,
    refused: u64 = 0,
    unaccountable: u64 = 0,
    faults: u64 = 0,
    pairs_touched: usize = 0,
    pairs_clean: usize = 0,
    swap_observations: u64 = 0,
    swap_admissions: u64 = 0,
    swap_harness_admissions: u64 = 0,
    details_dropped: u64 = 0,

    /// The single sentence the report leads with.
    pub fn verdict(self: Summary) []const u8 {
        if (self.observations == 0)
            return "nothing has been forwarded into the window yet; the admission surface is armed and has had nothing to decide";
        if (self.faults != 0)
            return "an unaccountable forwarding reached the window and the policy terminated the run at it; the last detail line below is the one that did it";
        if (self.unaccountable != 0)
            return "a forwarding named a window operation Rosette has no semantics for, or came from a domain that does not own it; under ROSETTE_WINDOW_ADMISSION=fault the run would have stopped here";
        if (self.refused != 0)
            return "every refusal was an ordering refusal: a legitimate request that arrived before its preconditions were observed, and was retried";
        return "every forwarding into the window was one Rosette has semantics for, from a domain that owns it, with its preconditions observed";
    }
};

pub const Ledger = struct {
    policy: FaultPolicy = .refuse,
    entries: [facility_count][operation_count]Entry = [_][operation_count]Entry{[_]Entry{.{}} ** operation_count} ** facility_count,
    swaps: [swap_boundary_count]SwapEntry = [_]SwapEntry{.{}} ** swap_boundary_count,
    details: [detail_capacity]Detail = [_]Detail{.{}} ** detail_capacity,
    detail_count: usize = 0,
    detail_next: usize = 0,
    details_dropped: u64 = 0,
    sequence: u64 = 0,
    observations: u64 = 0,
    admitted: u64 = 0,
    refused: u64 = 0,
    unaccountable: u64 = 0,
    faults: u64 = 0,
    swap_observations: u64 = 0,
    swap_admissions: u64 = 0,
    swap_harness_admissions: u64 = 0,
    /// Set once a fault disposition has been produced, so a caller that keeps
    /// running (a test, or `observe` policy) cannot report two first faults.
    fault_latched: bool = false,
    fault_detail: Detail = .{},

    pub fn configure(self: *Ledger, policy: FaultPolicy) void {
        self.policy = policy;
    }

    pub fn entry(self: *const Ledger, facility: Facility, operation: Operation) Entry {
        return self.entries[@intFromEnum(facility)][@intFromEnum(operation)];
    }

    pub fn swapEntry(self: *const Ledger, boundary: SwapBoundary) SwapEntry {
        return self.swaps[@intFromEnum(boundary)];
    }

    /// Decide and record one forwarding.
    ///
    /// `origin` names the boundary it arrived on — a selector, an import, a
    /// packet opcode — and is retained only on a refusal, where it is the
    /// difference between a category and a line of code.
    pub fn admit(self: *Ledger, request: Request, origin: []const u8, step: u64) Outcome {
        const decision = contract.decide(request);
        const disposition = contract.disposition(decision.verdict, self.policy);

        const record = &self.entries[@intFromEnum(request.facility)][@intFromEnum(request.operation)];
        if (record.observations == 0) record.first_step = step;
        record.observations +|= 1;
        record.last_step = step;
        record.last_actor = request.actor;
        record.last_verdict = decision.verdict;
        record.last_missing = decision.missing;
        record.actor_mask |= actorBit(request.actor);
        record.verdicts[@intFromEnum(decision.verdict)] +|= 1;

        self.observations +|= 1;
        if (decision.verdict.admittedOk()) {
            self.admitted +|= 1;
        } else {
            self.refused +|= 1;
            if (decision.verdict.isUnaccountable()) self.unaccountable +|= 1;
        }

        self.sequence +|= 1;
        var detail = Detail{
            .sequence = self.sequence,
            .actor = request.actor,
            .facility = request.facility,
            .operation = request.operation,
            .verdict = decision.verdict,
            .disposition = disposition,
            .missing = decision.missing,
            .step = step,
        };
        const copied = @min(origin.len, detail.origin.len);
        @memcpy(detail.origin[0..copied], origin[0..copied]);
        detail.origin_len = @intCast(copied);

        if (!decision.verdict.admittedOk()) self.storeDetail(detail);

        if (disposition == .fault and !self.fault_latched) {
            self.fault_latched = true;
            self.fault_detail = detail;
            self.faults +|= 1;
        }

        return .{ .decision = decision, .disposition = disposition, .detail = detail };
    }

    /// Decide and record one swap handoff.
    pub fn admitSwap(
        self: *Ledger,
        boundary: SwapBoundary,
        evidence: SwapEvidence,
        step: u64,
    ) SwapVerdict {
        const verdict = contract.admitSwap(boundary, evidence);
        const record = &self.swaps[@intFromEnum(boundary)];
        if (record.observations == 0) record.first_step = step;
        record.observations +|= 1;
        record.last_step = step;
        record.last_verdict = verdict;
        record.verdicts[@intFromEnum(verdict)] +|= 1;
        if (evidence.provenance.rank() > record.best_provenance.rank())
            record.best_provenance = evidence.provenance;
        self.swap_observations +|= 1;
        switch (verdict) {
            .admitted => {
                record.admissions +|= 1;
                self.swap_admissions +|= 1;
            },
            .admitted_harness_surface => {
                record.harness_admissions +|= 1;
                self.swap_harness_admissions +|= 1;
            },
            else => {},
        }
        return verdict;
    }

    /// The frontier of the swap ladder: the first boundary that has never been
    /// admitted, and why. Null once every boundary has been admitted at least
    /// once.
    pub fn swapFrontier(self: *const Ledger) ?struct { boundary: SwapBoundary, verdict: SwapVerdict, observations: u64 } {
        var index: u8 = 0;
        while (index < swap_boundary_count) : (index += 1) {
            const boundary: SwapBoundary = @enumFromInt(index);
            const record = self.swaps[index];
            if (record.admissions != 0 or record.harness_admissions != 0) continue;
            return .{
                .boundary = boundary,
                .verdict = if (record.observations == 0) .refused_provenance_insufficient else record.last_verdict,
                .observations = record.observations,
            };
        }
        return null;
    }

    pub fn summary(self: *const Ledger) Summary {
        var result = Summary{
            .observations = self.observations,
            .admitted = self.admitted,
            .refused = self.refused,
            .unaccountable = self.unaccountable,
            .faults = self.faults,
            .swap_observations = self.swap_observations,
            .swap_admissions = self.swap_admissions,
            .swap_harness_admissions = self.swap_harness_admissions,
            .details_dropped = self.details_dropped,
        };
        for (self.entries) |row| {
            for (row) |record| {
                if (!record.touched()) continue;
                result.pairs_touched += 1;
                if (record.clean()) result.pairs_clean += 1;
            }
        }
        return result;
    }

    /// A fingerprint over the facts a reader would act on. Used to collapse the
    /// report when nothing has changed since the previous checkpoint.
    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = 0x9E37_79B9_7F4A_7C15;
        hash = mix(hash, self.observations);
        hash = mix(hash, self.refused);
        hash = mix(hash, self.unaccountable);
        hash = mix(hash, self.faults);
        hash = mix(hash, self.swap_observations);
        hash = mix(hash, self.swap_admissions);
        hash = mix(hash, self.swap_harness_admissions);
        for (self.entries) |row| {
            for (row) |record| {
                if (!record.touched()) continue;
                hash = mix(hash, record.refused());
                hash = mix(hash, @intFromEnum(record.last_verdict));
                hash = mix(hash, record.actor_mask);
            }
        }
        for (self.swaps) |record| {
            hash = mix(hash, record.observations);
            hash = mix(hash, @intFromEnum(record.last_verdict));
        }
        return hash;
    }

    fn storeDetail(self: *Ledger, detail: Detail) void {
        if (self.detail_count == detail_capacity) self.details_dropped +|= 1;
        self.details[self.detail_next] = detail;
        self.detail_next = (self.detail_next + 1) % detail_capacity;
        if (self.detail_count < detail_capacity) self.detail_count += 1;
    }
};

pub const Outcome = struct {
    decision: Decision,
    disposition: Disposition,
    detail: Detail,

    pub fn admitted(self: Outcome) bool {
        return self.disposition == .admit;
    }
};

pub fn actorBit(actor: Actor) u16 {
    return @as(u16, 1) << @as(u4, @intCast(@intFromEnum(actor)));
}

/// Parse `ROSETTE_WINDOW_ADMISSION`. Anything unrecognised keeps the default so
/// a typo cannot silently disarm the surface.
pub fn policyFromText(value: ?[]const u8, default: FaultPolicy) FaultPolicy {
    const text = value orelse return default;
    if (std.mem.eql(u8, text, "fault")) return .fault;
    if (std.mem.eql(u8, text, "refuse")) return .refuse;
    if (std.mem.eql(u8, text, "observe")) return .observe;
    return default;
}

fn mix(hash: u64, value: u64) u64 {
    var next = hash ^ (value +% 0x9E37_79B9_7F4A_7C15 +% (hash << 6) +% (hash >> 2));
    next ^= next >> 33;
    next = next *% 0xFF51_AFD7_ED55_8CCD;
    next ^= next >> 29;
    return next;
}

// ---------------------------------------------------------------------------

const all_conditions: ConditionMask = std.math.maxInt(ConditionMask);

test "an admitted forwarding leaves the pair clean" {
    var ledger = Ledger{};
    const outcome = ledger.admit(.{
        .actor = .xenia_host,
        .facility = .window,
        .operation = .query,
        .observed = all_conditions,
    }, "objc:contentView", 100);
    try std.testing.expect(outcome.admitted());
    try std.testing.expect(ledger.entry(.window, .query).clean());
    try std.testing.expectEqual(@as(u64, 0), ledger.refused);
    try std.testing.expectEqual(@as(usize, 0), ledger.detail_count);
}

test "an unsupported forwarding is counted, detailed and latched as the fault" {
    var ledger = Ledger{};
    ledger.configure(.fault);
    const outcome = ledger.admit(.{
        .actor = .xenia_host,
        .facility = .device,
        .operation = .mutate,
        .observed = all_conditions,
    }, "objc:setDevice:", 4200);
    try std.testing.expectEqual(Disposition.fault, outcome.disposition);
    try std.testing.expectEqual(@as(u64, 1), ledger.unaccountable);
    try std.testing.expectEqual(@as(u64, 1), ledger.faults);
    try std.testing.expect(ledger.fault_latched);
    try std.testing.expectEqualStrings("objc:setDevice:", ledger.fault_detail.originName());
    try std.testing.expectEqual(@as(u64, 4200), ledger.fault_detail.step);
}

test "only the first fault is latched" {
    var ledger = Ledger{};
    ledger.configure(.fault);
    _ = ledger.admit(.{ .actor = .xenia_host, .facility = .device, .operation = .mutate }, "first", 1);
    _ = ledger.admit(.{ .actor = .xenia_host, .facility = .device, .operation = .mutate }, "second", 2);
    try std.testing.expectEqual(@as(u64, 1), ledger.faults);
    try std.testing.expectEqualStrings("first", ledger.fault_detail.originName());
    try std.testing.expectEqual(@as(u64, 2), ledger.unaccountable);
}

test "an ordering refusal never faults even under the fault policy" {
    var ledger = Ledger{};
    ledger.configure(.fault);
    const outcome = ledger.admit(.{
        .actor = .rosette_runtime,
        .facility = .verified_present,
        .operation = .present,
        .observed = 0,
    }, "presenter", 7);
    try std.testing.expectEqual(Disposition.refuse, outcome.disposition);
    try std.testing.expectEqual(@as(u64, 0), ledger.faults);
    try std.testing.expectEqual(@as(u64, 0), ledger.unaccountable);
    try std.testing.expectEqual(@as(u64, 1), ledger.refused);
    try std.testing.expect(outcome.decision.firstMissing() != null);
}

test "observe policy records the refusal and still admits" {
    var ledger = Ledger{};
    ledger.configure(.observe);
    const outcome = ledger.admit(.{ .actor = .guest_title, .facility = .geometry, .operation = .mutate }, "resize", 9);
    try std.testing.expect(outcome.admitted());
    try std.testing.expectEqual(Verdict.refused_actor_not_permitted, outcome.decision.verdict);
    try std.testing.expectEqual(@as(u64, 1), ledger.unaccountable);
    try std.testing.expectEqual(@as(u64, 0), ledger.faults);
}

test "refusal detail is bounded and the overflow is counted, not hidden" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < detail_capacity + 5) : (index += 1) {
        _ = ledger.admit(.{ .actor = .guest_title, .facility = .geometry, .operation = .mutate }, "resize", index);
    }
    try std.testing.expectEqual(detail_capacity, ledger.detail_count);
    try std.testing.expectEqual(@as(u64, 5), ledger.details_dropped);
    try std.testing.expectEqual(@as(u64, detail_capacity + 5), ledger.entry(.geometry, .mutate).refused());
}

test "the swap frontier names the first boundary never admitted" {
    var ledger = Ledger{};
    var evidence = SwapEvidence{
        .provenance = .intercepted_execution,
        .facility_admitted = true,
        .frontbuffer_named = true,
        .frontbuffer_readable = true,
        .extent_valid = true,
        .format_supported = true,
        .epoch_matched = true,
        .custody_available = true,
        .lease_compatible = true,
    };
    try std.testing.expectEqual(SwapVerdict.admitted, ledger.admitSwap(.vd_swap_entry, evidence, 10));
    try std.testing.expectEqual(SwapVerdict.admitted, ledger.admitSwap(.vd_swap_arguments, evidence, 11));
    evidence.frontbuffer_readable = false;
    _ = ledger.admitSwap(.xe_swap_encoded, evidence, 12);
    const frontier = ledger.swapFrontier().?;
    try std.testing.expectEqual(SwapBoundary.xe_swap_encoded, frontier.boundary);
    try std.testing.expectEqual(SwapVerdict.refused_frontbuffer_unreadable, frontier.verdict);
    try std.testing.expectEqual(@as(u64, 1), frontier.observations);
}

test "a boundary nothing ever probed reads as insufficient provenance, not as a finding" {
    var ledger = Ledger{};
    const frontier = ledger.swapFrontier().?;
    try std.testing.expectEqual(SwapBoundary.vd_swap_entry, frontier.boundary);
    try std.testing.expectEqual(@as(u64, 0), frontier.observations);
    try std.testing.expectEqual(SwapVerdict.refused_provenance_insufficient, frontier.verdict);
}

test "a harness-surface admission is separated from an authentic one" {
    var ledger = Ledger{};
    const evidence = SwapEvidence{
        .provenance = .guest_memory_read,
        .facility_admitted = true,
        .frontbuffer_harness_supplied = true,
        .frontbuffer_readable = true,
        .extent_valid = true,
        .format_supported = true,
        .epoch_matched = true,
        .custody_available = true,
        .lease_compatible = true,
    };
    try std.testing.expectEqual(
        SwapVerdict.admitted_harness_surface,
        ledger.admitSwap(.xe_swap_consumed, evidence, 3),
    );
    try std.testing.expectEqual(@as(u64, 0), ledger.swap_admissions);
    try std.testing.expectEqual(@as(u64, 1), ledger.swap_harness_admissions);
    try std.testing.expect(ledger.swapFrontier() != null);
}

test "the fingerprint moves only when a reader would act differently" {
    var ledger = Ledger{};
    _ = ledger.admit(.{ .actor = .xenia_host, .facility = .window, .operation = .query, .observed = all_conditions }, "q", 1);
    const first = ledger.fingerprint();
    _ = ledger.admit(.{ .actor = .xenia_host, .facility = .window, .operation = .query, .observed = all_conditions }, "q", 2);
    try std.testing.expect(ledger.fingerprint() != first);
    const second = ledger.fingerprint();
    try std.testing.expectEqual(second, ledger.fingerprint());
}

test "the summary verdict distinguishes ordering from unaccountability" {
    var ledger = Ledger{};
    try std.testing.expect(std.mem.indexOf(u8, ledger.summary().verdict(), "nothing has been forwarded") != null);
    _ = ledger.admit(.{ .actor = .xenia_host, .facility = .window, .operation = .query, .observed = all_conditions }, "q", 1);
    try std.testing.expect(std.mem.indexOf(u8, ledger.summary().verdict(), "every forwarding") != null);
    _ = ledger.admit(.{ .actor = .rosette_runtime, .facility = .swapchain, .operation = .create }, "vk", 2);
    try std.testing.expect(std.mem.indexOf(u8, ledger.summary().verdict(), "ordering refusal") != null);
    _ = ledger.admit(.{ .actor = .guest_title, .facility = .geometry, .operation = .mutate }, "resize", 3);
    try std.testing.expect(std.mem.indexOf(u8, ledger.summary().verdict(), "does not own it") != null);
}

test "policy parsing keeps the default on anything unrecognised" {
    try std.testing.expectEqual(FaultPolicy.fault, policyFromText("fault", .refuse));
    try std.testing.expectEqual(FaultPolicy.observe, policyFromText("observe", .refuse));
    try std.testing.expectEqual(FaultPolicy.refuse, policyFromText("REFUSE", .refuse));
    try std.testing.expectEqual(FaultPolicy.refuse, policyFromText(null, .refuse));
    try std.testing.expectEqual(FaultPolicy.fault, policyFromText("nonsense", .fault));
}

test "actor bits are disjoint and fit the mask" {
    var seen: u16 = 0;
    var index: u8 = 0;
    while (index < contract.actor_count) : (index += 1) {
        const actor: Actor = @enumFromInt(index);
        const bit = actorBit(actor);
        try std.testing.expectEqual(@as(u16, 0), seen & bit);
        seen |= bit;
    }
}

test "the contract the ledger records is self-consistent" {
    try std.testing.expect(contract.contractIsWellFormed());
    try std.testing.expect(contract.everySwapOwnerMayPresent());
}

test "the whole swap ladder is admitted end to end when every fact holds" {
    var ledger = Ledger{};
    ledger.configure(.fault);
    const evidence = SwapEvidence{
        .provenance = .intercepted_execution,
        .facility_admitted = true,
        .frontbuffer_named = true,
        .frontbuffer_readable = true,
        .extent_valid = true,
        .format_supported = true,
        .epoch_matched = true,
        .custody_available = true,
        .lease_compatible = true,
    };
    var index: u8 = 0;
    while (index < swap_boundary_count) : (index += 1) {
        const boundary: SwapBoundary = @enumFromInt(index);
        // The window's own admission first, exactly as the runtime asks it.
        const outcome = ledger.admit(.{
            .actor = boundary.owner(),
            .facility = boundary.facility(),
            .operation = .present,
            .observed = std.math.maxInt(ConditionMask),
        }, boundary.label(), 1000 + @as(u64, index));
        try std.testing.expectEqual(Disposition.admit, outcome.disposition);
        try std.testing.expectEqual(SwapVerdict.admitted, ledger.admitSwap(boundary, evidence, 1000 + @as(u64, index)));
    }
    try std.testing.expect(ledger.swapFrontier() == null);
    try std.testing.expectEqual(@as(u64, 0), ledger.faults);
    try std.testing.expectEqual(@as(u64, swap_boundary_count), ledger.swap_admissions);
}
