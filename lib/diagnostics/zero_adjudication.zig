//! Whether a value that reads zero is a finding or a fact.
//!
//! Zero is the most common value in a translated process and the least
//! informative. A slot reads zero because it was never written, because the
//! writer meant zero, because zero is the encoding for "nothing here", or
//! because whoever was supposed to fill it did not. Those are four different
//! situations with one observation, and the reason a log full of zeros teaches
//! nothing is that every one of them is reported the same way.
//!
//! Treating any of them as fatal is wrong — three of the four are correct
//! behaviour, and a runtime that aborts on them cannot boot. Treating all of
//! them as noise is also wrong, because the fourth is the defect and it is the
//! one that never gets found. What is missing is not more zero-detection but a
//! *verdict*: a decision, per observation, about which of the four this is, and
//! a notification code emitted only for the one that is a problem.
//!
//! The discriminators are cheap and are things the caller already has at the
//! moment of the read:
//!
//!   * **what the slot is for** — zero in a status word is success; zero in a
//!     pointer that a producer was contracted to fill is a hole;
//!   * **who wrote it** — the allocator, guest code, or the runtime itself;
//!   * **whether the producer ran** — a slot still zero *after* the code that
//!     fills it has been observed to execute is the strongest defect signal
//!     available, and it is invisible to anything looking only at the value;
//!   * **whether it ever held anything else** — a slot that regressed to zero
//!     was written by someone, and that someone is the finding.
//!
//! ## Zero is the common case of a wider question
//!
//! The same machinery answers the harder version, and the harder version is
//! what actually costs days: an *implausible non-zero constant* in a slot whose
//! domain is addresses. A pointer field seeded with `1` is exactly as wrong as
//! one left at `0`, and considerably more dangerous, because every null check
//! the guest performs passes and the fault surfaces later as a wild dereference
//! with no connection to the store that caused it. Small integers are not
//! addresses by construction, so the moment such a value is read *as* an
//! address the slot is already known to be poisoned — no trace, no history, no
//! second run required.
//!
//! That case is worth naming precisely because it is the one where the
//! runtime's own seeding of a host-supplied structure is the culprit. When the
//! writer is the runtime, the constant is the runtime's, and no amount of
//! investigating the guest will find it.
//!
//! Deliberately advisory. Nothing here fails, aborts, or repairs: it returns a
//! classification and, for the defect cases only, a stable code to notify on.

const std = @import("std");

/// What the slot is contracted to hold. This is the fact that decides whether
/// zero is a value or a hole, and no inspection of the bits can supply it.
pub const Domain = enum(u8) {
    /// A guest address. Zero is "no object"; a value below the address floor is
    /// not an address at all.
    address,
    /// An opaque kernel handle. Zero is the reserved invalid handle.
    handle,
    /// A byte count, extent, or capacity.
    extent,
    /// A completion code. Zero conventionally means success, so zero here is
    /// the single most-reported non-finding in the whole runtime.
    status,
    /// A monotonic counter, sequence number, or ring pointer. Zero is the
    /// legitimate starting value, which is exactly why a zero that persists
    /// past the point a producer should have advanced it is worth reporting.
    counter,
    /// A boolean or bitfield. Zero means "nothing set" and is a real value.
    flags,
    /// Nothing is known about the slot's contract.
    unconstrained,

    /// Whether a value in this domain is interpreted as a pointer, and so is
    /// subject to the plausibility floor.
    pub fn isAddressShaped(self: Domain) bool {
        return self == .address;
    }
};

/// Who last stored to the slot. Separating the runtime from the guest is the
/// whole point: a poisoned constant written by the runtime cannot be found by
/// investigating guest code, and that misdirection is where the time goes.
pub const Writer = enum(u8) {
    /// No store has been observed since the slot was created, so the zero
    /// belongs to the allocator rather than to anyone's intent.
    none,
    /// The runtime seeded it — a host-supplied kernel structure, a synthesised
    /// export, a compatibility shim.
    host_seed,
    /// Guest code stored to it.
    guest,
    unknown,
};

/// What the caller can see at the moment of the read. Every field has a
/// defensible default so a caller that knows only the value still gets an
/// answer, and one that knows more gets a sharper one.
pub const Observation = struct {
    value: u64 = 0,
    width_bytes: u8 = 4,
    domain: Domain = .unconstrained,
    writer: Writer = .unknown,
    /// The contract admits zero as a meaningful value here, independent of
    /// domain. Set this when the caller knows the specific slot — a success
    /// status, a deliberately null optional — and wants the question closed.
    zero_is_meaningful: bool = false,
    /// Something was contracted to fill this slot before this read.
    producer_expected: bool = false,
    /// That producer was actually observed to run. Only meaningful alongside
    /// `producer_expected`, and together they are the strongest signal here.
    producer_observed: bool = false,
    /// The slot has been seen holding a non-zero value at some earlier point.
    held_nonzero_before: bool = false,
    /// Whether the runtime has a mapping covering `value` read as an address.
    /// `null` when the caller could not check — the verdict degrades to the
    /// floor test rather than guessing.
    value_is_mapped: ?bool = null,
    /// The same question for the byte-swapped reading of `value`. When the
    /// swapped form maps and the original does not, byte order is a live
    /// hypothesis; when neither maps, it is not, and saying so stops a search
    /// that would otherwise be conducted for nothing.
    byte_swapped_is_mapped: ?bool = null,
    /// Values at or below this are not addresses by construction. The default
    /// matches the runtime's own near-null threshold.
    address_floor: u64 = 0x10000,
};

pub const Finding = enum(u8) {
    // ---- Correct behaviour. No code is emitted for any of these. ----

    /// Zero is what this slot means when there is nothing to point at.
    absent_by_contract,
    /// Nothing has written it yet and nothing was supposed to have.
    not_yet_written,
    /// Zero is a value in this domain and the writer meant it.
    meaningful_zero,
    /// A non-zero value with nothing implausible about it.
    plausible_value,

    // ---- Defects. Each carries a stable notification code. ----

    /// The producer ran and the slot is still zero. The producer is the defect;
    /// nothing downstream of it is worth investigating.
    zero_after_producer_ran,
    /// A producer was contracted to fill this and has not been observed to run.
    /// The frontier is upstream: find why the producer never executed.
    zero_without_producer,
    /// It held a value and now holds zero, with no guest store to account for
    /// it. Something cleared it.
    regressed_to_zero,
    /// A constant too small to be an address sits in a slot being read as one.
    /// The slot is poisoned; the store that seeded it is the defect.
    non_address_constant,
    /// The value does not name mapped memory but its byte-swapped form does.
    /// A guest address was converted the wrong number of times.
    byte_order_mismatch,

    pub fn isDefect(self: Finding) bool {
        return switch (self) {
            .absent_by_contract, .not_yet_written, .meaningful_zero, .plausible_value => false,
            else => true,
        };
    }

    /// A stable code for the caller to notify on, and `null` for every
    /// observation that is not a problem. Callers are expected to branch on
    /// null rather than on severity: the point of the split is that a benign
    /// zero should cost nothing at all, not that it should be logged quietly.
    pub fn notificationCode(self: Finding) ?u16 {
        return switch (self) {
            .absent_by_contract, .not_yet_written, .meaningful_zero, .plausible_value => null,
            .zero_after_producer_ran => 0x5A01,
            .zero_without_producer => 0x5A02,
            .regressed_to_zero => 0x5A03,
            .non_address_constant => 0x5A04,
            .byte_order_mismatch => 0x5A05,
        };
    }
};

pub const Verdict = struct {
    finding: Finding = .plausible_value,
    /// Repeated from the observation so a report can be rendered from the
    /// verdict alone.
    domain: Domain = .unconstrained,
    writer: Writer = .unknown,
    value: u64 = 0,
    /// The byte-swapped reading, when the value was width-narrowed to a guest
    /// pointer. Zero when swapping was not applicable.
    byte_swapped_value: u64 = 0,

    pub fn isDefect(self: Verdict) bool {
        return self.finding.isDefect();
    }

    pub fn notificationCode(self: Verdict) ?u16 {
        return self.finding.notificationCode();
    }

    /// One sentence naming what was decided and where to look next. Written to
    /// be the whole report: a caller that prints only this should not need to
    /// consult anything else to know whether to act.
    pub fn describe(self: Verdict) []const u8 {
        return switch (self.finding) {
            .absent_by_contract => "zero is this slot's encoding for 'nothing here' and someone stored it deliberately; there is no missing value to find",
            .not_yet_written => "nothing has stored to this slot and nothing was contracted to have done so yet, so the zero is the allocator's and not a value at all",
            .meaningful_zero => "zero is a value in this domain and the writer meant it; reporting it as missing data would be reporting a success as a failure",
            .plausible_value => "the value is present and nothing about it is implausible for this slot",
            .zero_after_producer_ran => "the producer contracted to fill this slot has been observed to run and the slot is still zero. The producer is the defect — it executed and did not write, so nothing downstream of it is worth investigating",
            .zero_without_producer => "a producer was contracted to fill this slot and has not been observed to run. The frontier is upstream: the question is why the producer never executed, not why the value is zero",
            .regressed_to_zero => "this slot held a non-zero value earlier and now reads zero with no guest store to account for it. Something cleared it, and that store is the finding",
            .non_address_constant => "a constant far too small to be an address is being read as one. The slot is poisoned rather than stale, so no amount of tracing the fault will help — the store that seeded this constant is the defect",
            .byte_order_mismatch => "the value names no mapped memory but its byte-swapped form does. A guest address was byte-order converted the wrong number of times, and the conversion must happen exactly once, at the guest-memory boundary",
        };
    }

    /// The extra sentence that only applies when the runtime seeded the slot
    /// itself. Kept separate because it redirects the entire investigation, and
    /// burying it inside `describe` would make it easy to skip.
    pub fn attribution(self: Verdict) []const u8 {
        if (!self.isDefect()) return "";
        return switch (self.writer) {
            .host_seed => "The runtime wrote this slot, not the guest: the constant is the runtime's own seeding of a host-supplied structure, and investigating guest code will not find it",
            .guest => "Guest code wrote this slot, so the value is the guest's own and the runtime reproduced it faithfully",
            .none => "No store to this slot has been observed at all, so whatever it holds predates the runtime's recording of it",
            .unknown => "The writer is unrecorded, so attribution between guest and runtime is still open",
        };
    }
};

pub fn adjudicate(observation: Observation) Verdict {
    var verdict = Verdict{
        .domain = observation.domain,
        .writer = observation.writer,
        .value = observation.value,
    };

    if (observation.value != 0) {
        verdict.byte_swapped_value = swapNarrow(observation.value, observation.width_bytes);
        verdict.finding = adjudicateNonZero(observation);
        return verdict;
    }

    verdict.finding = adjudicateZero(observation);
    return verdict;
}

fn adjudicateZero(observation: Observation) Finding {
    // An explicit contract closes the question before anything else looks at
    // it. This is what keeps a success status out of the findings, and it has
    // to come first: a status word can perfectly well have a producer.
    if (observation.zero_is_meaningful) return .meaningful_zero;

    // A slot that held something and now holds zero was written by someone. The
    // guest clearing its own field is ordinary; anyone else doing it is not.
    if (observation.held_nonzero_before and observation.writer != .guest) {
        return .regressed_to_zero;
    }

    // The producer questions outrank the domain, because "zero is a legal
    // starting value" and "the thing that advances it ran and did not" are both
    // true of a stalled ring pointer, and only the second is worth anyone's
    // time.
    if (observation.producer_expected) {
        return if (observation.producer_observed)
            .zero_after_producer_ran
        else
            .zero_without_producer;
    }

    if (observation.writer == .none) return .not_yet_written;

    return switch (observation.domain) {
        .status, .flags, .counter, .unconstrained => .meaningful_zero,
        .address, .handle, .extent => .absent_by_contract,
    };
}

fn adjudicateNonZero(observation: Observation) Finding {
    if (!observation.domain.isAddressShaped()) return .plausible_value;

    // Below the floor there is nothing to check against mappings: the value is
    // not an address, whatever the mapping table says.
    if (observation.value <= observation.address_floor) return .non_address_constant;

    const mapped = observation.value_is_mapped orelse return .plausible_value;
    if (mapped) return .plausible_value;

    // The original names nothing. Byte order is only a hypothesis if the
    // swapped form names something; when neither does, saying "check the byte
    // order" sends the reader after a conversion bug that is not there.
    if (observation.byte_swapped_is_mapped orelse false) return .byte_order_mismatch;

    return .plausible_value;
}

/// Byte-swap a value at the width it was actually read, so a 32-bit guest
/// pointer loaded into a 64-bit register does not swap into its high half.
fn swapNarrow(value: u64, width_bytes: u8) u64 {
    return switch (width_bytes) {
        2 => @byteSwap(@as(u16, @truncate(value))),
        4 => @byteSwap(@as(u32, @truncate(value))),
        8 => @byteSwap(value),
        else => 0,
    };
}

// The single most-repeated line in a stalled run: a kernel call returning
// success. Nothing about it is a finding, and the adjudicator has to say so
// without the caller having to special-case the function by name.
test "a success status reading zero is not a finding" {
    const verdict = adjudicate(.{
        .value = 0,
        .domain = .status,
        .writer = .guest,
        .zero_is_meaningful = true,
    });
    try std.testing.expectEqual(Finding.meaningful_zero, verdict.finding);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expectEqual(@as(?u16, null), verdict.notificationCode());
}

// A status domain alone is enough even without the explicit contract flag,
// because a caller that knows only "this is a completion code" should not have
// to also assert that zero means success.
test "the status domain treats zero as a value on its own" {
    const verdict = adjudicate(.{ .value = 0, .domain = .status, .writer = .guest });
    try std.testing.expectEqual(Finding.meaningful_zero, verdict.finding);
    try std.testing.expectEqual(@as(?u16, null), verdict.notificationCode());
}

// A ring write pointer at zero before the guest has submitted anything is the
// legitimate starting value, and reporting it every time the pointer is sampled
// is how a real stall gets buried.
test "a counter at its starting value with no producer due is not a finding" {
    const verdict = adjudicate(.{ .value = 0, .domain = .counter, .writer = .none });
    try std.testing.expectEqual(Finding.not_yet_written, verdict.finding);
    try std.testing.expect(!verdict.isDefect());
}

// The same pointer, once the producer has been observed to run, is the defect —
// and this is the transition the value itself cannot show, because the value
// did not change.
test "a counter still zero after its producer ran names the producer" {
    const verdict = adjudicate(.{
        .value = 0,
        .domain = .counter,
        .writer = .none,
        .producer_expected = true,
        .producer_observed = true,
    });
    try std.testing.expectEqual(Finding.zero_after_producer_ran, verdict.finding);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expect(verdict.notificationCode() != null);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "executed and did not write") != null);
}

// Producer contracted but never observed is a different verdict with a
// different next step: look upstream, not at this slot.
test "a producer that never ran points upstream rather than at the slot" {
    const verdict = adjudicate(.{
        .value = 0,
        .domain = .counter,
        .producer_expected = true,
        .producer_observed = false,
    });
    try std.testing.expectEqual(Finding.zero_without_producer, verdict.finding);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "upstream") != null);
}

// The case that costs the most time: a pointer field seeded with a small
// integer. Every null check the guest makes passes, and the fault lands
// somewhere with no connection to the store.
test "a small constant read as an address is a poisoned slot, not a stale one" {
    const verdict = adjudicate(.{
        .value = 1,
        .width_bytes = 4,
        .domain = .address,
        .writer = .host_seed,
    });
    try std.testing.expectEqual(Finding.non_address_constant, verdict.finding);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "poisoned") != null);
}

// And the attribution is the sentence that redirects the search, so it has to
// survive independently of the description.
test "a runtime-seeded poisoned slot is attributed to the runtime" {
    const verdict = adjudicate(.{ .value = 1, .domain = .address, .writer = .host_seed });
    try std.testing.expect(std.mem.indexOf(u8, verdict.attribution(), "runtime wrote this slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, verdict.attribution(), "will not find it") != null);
}

// Byte order is only a hypothesis when the swapped form actually names
// something. A small constant swaps into a large number that names nothing, and
// calling that a conversion bug sends the reader after a defect that is not
// there.
test "byte order is not blamed when neither reading names mapped memory" {
    const verdict = adjudicate(.{
        .value = 1,
        .domain = .address,
        .value_is_mapped = false,
        .byte_swapped_is_mapped = false,
    });
    try std.testing.expectEqual(Finding.non_address_constant, verdict.finding);
}

test "byte order is blamed when only the swapped reading names mapped memory" {
    const verdict = adjudicate(.{
        .value = 0x0000_0082,
        .width_bytes = 4,
        .domain = .address,
        .writer = .guest,
        .address_floor = 0x10,
        .value_is_mapped = false,
        .byte_swapped_is_mapped = true,
    });
    try std.testing.expectEqual(Finding.byte_order_mismatch, verdict.finding);
    try std.testing.expectEqual(@as(u64, 0x8200_0000), verdict.byte_swapped_value);
}

// A 32-bit guest pointer sitting in a 64-bit register must swap at the width it
// was read, or the swapped form lands in the high half and names nothing.
test "swapping happens at the width the value was read" {
    const verdict = adjudicate(.{ .value = 0x0000_00A0, .width_bytes = 4, .domain = .address, .value_is_mapped = true });
    try std.testing.expectEqual(@as(u64, 0xA000_0000), verdict.byte_swapped_value);
}

// A guest deliberately storing null is ordinary and must not become a finding
// just because the domain is a pointer.
test "a guest-stored null pointer is absent by contract" {
    const verdict = adjudicate(.{ .value = 0, .domain = .address, .writer = .guest });
    try std.testing.expectEqual(Finding.absent_by_contract, verdict.finding);
    try std.testing.expect(!verdict.isDefect());
}

// A slot that held a value and was cleared by someone other than the guest is
// the one zero that history, not contract, exposes.
test "a slot cleared by someone other than the guest is a finding" {
    const verdict = adjudicate(.{
        .value = 0,
        .domain = .address,
        .writer = .host_seed,
        .held_nonzero_before = true,
    });
    try std.testing.expectEqual(Finding.regressed_to_zero, verdict.finding);
    try std.testing.expect(verdict.isDefect());
}

// The guest clearing its own field is not a regression, however many times it
// happens.
test "the guest clearing its own field is not a regression" {
    const verdict = adjudicate(.{
        .value = 0,
        .domain = .address,
        .writer = .guest,
        .held_nonzero_before = true,
    });
    try std.testing.expectEqual(Finding.absent_by_contract, verdict.finding);
}

// A large address the runtime cannot check is left alone. An adjudicator that
// guessed here would produce findings proportional to its own ignorance.
test "an unverifiable address is not made into a finding" {
    const verdict = adjudicate(.{ .value = 0x8200_0000, .domain = .address });
    try std.testing.expectEqual(Finding.plausible_value, verdict.finding);
    try std.testing.expectEqual(@as(?u16, null), verdict.notificationCode());
}

// Only address-shaped slots get the floor test: `1` is a perfectly good flag
// word, extent, or status.
test "a small constant outside an address slot is not a finding" {
    for ([_]Domain{ .flags, .extent, .status, .counter, .handle, .unconstrained }) |domain| {
        const verdict = adjudicate(.{ .value = 1, .domain = domain });
        try std.testing.expectEqual(Finding.plausible_value, verdict.finding);
    }
}

/// Running counts, so a session can state how many of its zeros were facts and
/// how many were findings — the number that says whether a log full of zeros
/// deserved attention.
pub const Census = struct {
    facts: u64 = 0,
    findings: u64 = 0,
    poisoned_slots: u64 = 0,
    producer_holes: u64 = 0,

    pub fn note(self: *Census, finding: Finding) void {
        if (finding.isDefect()) {
            self.findings +|= 1;
        } else {
            self.facts +|= 1;
        }
        switch (finding) {
            .non_address_constant => self.poisoned_slots +|= 1,
            .zero_after_producer_ran, .zero_without_producer => self.producer_holes +|= 1,
            else => {},
        }
    }

    pub fn total(self: Census) u64 {
        return self.facts + self.findings;
    }

    /// Whether anything in this session is worth acting on. The intended use is
    /// a single check at exit, so a clean run reports nothing at all.
    pub fn hasFindings(self: Census) bool {
        return self.findings != 0;
    }
};

test "the census separates zeros that were facts from zeros that were findings" {
    var census = Census{};
    census.note(.meaningful_zero);
    census.note(.not_yet_written);
    census.note(.non_address_constant);
    census.note(.zero_after_producer_ran);
    try std.testing.expectEqual(@as(u64, 4), census.total());
    try std.testing.expectEqual(@as(u64, 2), census.facts);
    try std.testing.expectEqual(@as(u64, 2), census.findings);
    try std.testing.expectEqual(@as(u64, 1), census.poisoned_slots);
    try std.testing.expectEqual(@as(u64, 1), census.producer_holes);
    try std.testing.expect(census.hasFindings());
}

test "a run with only legitimate zeros reports nothing" {
    var census = Census{};
    census.note(.meaningful_zero);
    census.note(.absent_by_contract);
    census.note(.plausible_value);
    try std.testing.expect(!census.hasFindings());
}
