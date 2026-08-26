//! Who owns a piece of console platform state, when they took it, and whether
//! the handoff between them held.
//!
//! On real hardware the kernel writes platform state before the title's first
//! instruction and nothing else ever touches it. Here the same state has two
//! possible providers — the harness and the emulator — with no agreed moment of
//! transfer, and a title reads it at a moment neither of them chose. That is a
//! custody problem, and it has exactly three failure modes:
//!
//!   * **Late.** The value arrives after the consumer already read the old one.
//!     Every counter afterwards reads healthy: the variable is populated, the
//!     ladder rung is met, the run still never presents, because the decision
//!     the title made against the zero is never revisited. This is the failure
//!     that looks least like a failure.
//!   * **Contested.** Both providers write, with different values. Each is
//!     individually defensible and the consumer sees whichever landed last.
//!   * **Load-bearing.** The harness writes and the emulator never does. The
//!     run works, and it works *because* of the harness — which is fine, and
//!     must be stated, because it means the emulator still cannot do this on
//!     its own and a later change that removes the harness write breaks it.
//!
//! None of the three is visible in "is the value populated". All three are
//! visible here.
//!
//! This package holds no state and reads no memory. It is the vocabulary and
//! the classifier; the ledger is `lib/gpu/custody.zig`.

const std = @import("std");

/// Who a resource belongs to once everything has settled.
pub const Owner = enum(u8) {
    /// The console kernel wrote it before the title ran. The harness may
    /// supply it: doing so reproduces hardware rather than inventing anything.
    console_kernel,
    /// The emulator establishes it as part of its own bring-up.
    emulator,
    /// The title writes it. The harness must never supply it — a value here is
    /// a decision the title did not make.
    guest_title,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .console_kernel => "console:kernel",
            .emulator => "xenia:emulator",
            .guest_title => "guest:title",
        };
    }

    /// The single rule that keeps provisioning from becoming fabrication.
    pub fn harnessMayProvision(self: Owner) bool {
        return self == .console_kernel;
    }
};

/// Where a resource's custody currently sits.
pub const Custody = enum(u8) {
    /// Nobody has written it.
    unprovisioned,
    /// The harness wrote it and nothing has since.
    harness_provisioned,
    /// Its owner wrote it without the harness having to.
    owner_established,
    /// The harness wrote it and the owner later wrote the same value. The
    /// handoff completed: the owner has taken over and agrees.
    owner_adopted,
    /// The harness wrote it and the owner later wrote something different.
    contested,

    pub fn label(self: Custody) []const u8 {
        return switch (self) {
            .unprovisioned => "unprovisioned",
            .harness_provisioned => "harness-provisioned",
            .owner_established => "owner-established",
            .owner_adopted => "owner-adopted",
            .contested => "contested",
        };
    }

    pub fn settled(self: Custody) bool {
        return self == .owner_established or self == .owner_adopted;
    }

    /// True when the run depends on the harness's write and nothing has
    /// confirmed it. Not an error — but it means the emulator still cannot
    /// reach this state alone, and removing the write would regress the run.
    pub fn loadBearing(self: Custody) bool {
        return self == .harness_provisioned;
    }
};

/// When a provisioning write landed relative to the consumer that needed it.
///
/// This is the axis that "is it populated" cannot express, and it is the one
/// that decides whether a provisioning fix changes anything at all.
pub const Timing = enum(u8) {
    /// The resource has not been provisioned, so there is no timing to judge.
    not_provisioned,
    /// Written before the guest executed a single instruction. This is the
    /// only timing that reproduces the console, and the only one that is
    /// unconditionally safe.
    before_guest_started,
    /// Written after the guest started but before the first consumer was
    /// observed reaching for it. Still in time, but only by luck of scheduling.
    before_first_consumer,
    /// Written after the consumer had already run. The value is correct and
    /// arrived too late to affect the decision that was made against the old
    /// one; the consumer does not re-read it.
    after_first_consumer,
    /// The consumer boundary was never observed, so precedence is unknown.
    /// Reported as unknown rather than assumed good.
    unknown,

    pub fn label(self: Timing) []const u8 {
        return switch (self) {
            .not_provisioned => "not-provisioned",
            .before_guest_started => "preboot",
            .before_first_consumer => "in-time",
            .after_first_consumer => "LATE",
            .unknown => "unknown",
        };
    }

    /// True when the write cannot have influenced the consumer.
    pub fn missedItsConsumer(self: Timing) bool {
        return self == .after_first_consumer;
    }

    pub fn guidance(self: Timing) []const u8 {
        return switch (self) {
            .not_provisioned => "nothing was written, so nothing arrived early or late",
            .before_guest_started => "written before the guest executed an instruction, which is what the console does and the only timing that is safe by construction",
            .before_first_consumer => "written after the guest started but before its consumer ran; correct in this run and dependent on scheduling, so it is not a guarantee",
            .after_first_consumer => "written after the consumer had already read the old value. The variable now reads healthy and the decision made against the zero was never revisited: provision this before the consumer runs or the write changes nothing",
            .unknown => "no consumer boundary was observed, so whether this arrived in time cannot be decided; do not read a populated value as proof that it was early enough",
        };
    }
};

/// Whether the owner's own write agreed with the harness's.
pub const Divergence = enum(u8) {
    /// The owner never wrote, so there is nothing to compare.
    uncontested,
    /// The owner wrote the same value. The harness write was redundant and
    /// harmless, and the two agree about the platform.
    confirmed,
    /// The owner wrote a different value. The harness's value was wrong, and
    /// anything the consumer decided against it in the meantime was decided
    /// against a value the platform does not hold.
    diverged,

    pub fn label(self: Divergence) []const u8 {
        return switch (self) {
            .uncontested => "uncontested",
            .confirmed => "confirmed",
            .diverged => "DIVERGED",
        };
    }

    pub fn guidance(self: Divergence) []const u8 {
        return switch (self) {
            .uncontested => "the owner never wrote this, so the harness value stands unchallenged and unverified",
            .confirmed => "the owner independently wrote the same value: the harness reproduced the platform correctly and the handoff is complete",
            .diverged => "the owner wrote a different value than the harness supplied. The harness value was wrong; find what the consumer decided against it before the correction landed",
        };
    }
};

/// The classifier. Pure, so the ledger and any offline analysis agree.
pub fn custodyOf(
    harness_wrote: bool,
    owner_wrote: bool,
    values_agree: bool,
) Custody {
    if (!harness_wrote and !owner_wrote) return .unprovisioned;
    if (!harness_wrote) return .owner_established;
    if (!owner_wrote) return .harness_provisioned;
    return if (values_agree) .owner_adopted else .contested;
}

pub fn divergenceOf(harness_wrote: bool, owner_wrote: bool, values_agree: bool) Divergence {
    if (!harness_wrote or !owner_wrote) return .uncontested;
    return if (values_agree) .confirmed else .diverged;
}

/// Decide precedence from three step numbers.
///
/// `consumer_step` is the step at which something that reads this resource was
/// first observed running. It is deliberately a *step* and not a flag: an
/// ordering question can only be answered by comparing two moments, and a
/// boolean "the consumer ran" loses exactly the half that matters.
pub fn timingOf(
    provisioned: bool,
    provisioned_step: u64,
    guest_started: bool,
    consumer_step: ?u64,
) Timing {
    if (!provisioned) return .not_provisioned;
    if (!guest_started or provisioned_step == 0) return .before_guest_started;
    const consumer = consumer_step orelse return .unknown;
    return if (provisioned_step <= consumer) .before_first_consumer else .after_first_consumer;
}

/// A provisioning attempt the contract refuses, and why.
pub const Refusal = enum(u8) {
    none,
    /// The resource belongs to the title. Writing it fabricates a decision.
    not_harness_owned,
    /// A usable value is already there; overwriting it would destroy evidence
    /// about who established it.
    already_present,
    /// The storage the slot names cannot be written from here.
    storage_unwritable,
    /// The slot's address is not known yet, so there is nowhere to write.
    address_unknown,

    pub fn label(self: Refusal) []const u8 {
        return switch (self) {
            .none => "none",
            .not_harness_owned => "not-harness-owned",
            .already_present => "already-present",
            .storage_unwritable => "storage-unwritable",
            .address_unknown => "address-unknown",
        };
    }

    pub fn guidance(self: Refusal) []const u8 {
        return switch (self) {
            .none => "the write was permitted",
            .not_harness_owned => "this belongs to the title; supplying it would fabricate a decision the title never made",
            .already_present => "a usable value is already there. Overwriting it would erase which provider established it, and the custody question is the one being asked",
            .storage_unwritable => "the storage the slot points at is not writable from here, so the platform state stays unsupplied and the title reads whatever is present",
            .address_unknown => "the slot's address has not been discovered yet. This is the state a provisioner is in before the export table is read, and the only fix is to provision again once it is",
        };
    }
};

/// The reading a whole ledger produces.
pub const Finding = enum(u8) {
    /// Everything the harness owns is provisioned before the guest ran, and
    /// nothing diverged.
    healthy,
    /// At least one resource was provisioned after its consumer had run.
    provisioned_late,
    /// At least one resource has two providers that disagree.
    contested_ownership,
    /// At least one harness-owned resource was never provisioned at all.
    unprovisioned_platform_state,
    /// Provisioning is complete and correct, and the emulator has not taken
    /// over any of it.
    harness_load_bearing,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .healthy => "healthy",
            .provisioned_late => "provisioned_late",
            .contested_ownership => "contested_ownership",
            .unprovisioned_platform_state => "unprovisioned_platform_state",
            .harness_load_bearing => "harness_load_bearing",
        };
    }

    pub fn guidance(self: Finding) []const u8 {
        return switch (self) {
            .healthy => "every resource the harness owns was provisioned before the guest ran and its owner either agreed or never needed to write",
            .provisioned_late => "platform state was written after the consumer that needed it had already run. The value now reads correct and the decision made against the old one was never revisited — this is the failure mode that leaves every counter healthy and the run stuck",
            .contested_ownership => "the harness and the resource's owner wrote different values. Stop and decide which is the platform's, because the consumer saw whichever landed last",
            .unprovisioned_platform_state => "state the console kernel establishes before a title runs has not been established here. A title reading it sees whatever the fault path left behind, and takes its early-return branch permanently",
            .harness_load_bearing => "provisioning is complete and the emulator has adopted none of it. The run depends on the harness write; removing it would regress the run, and the emulator still cannot reach this state alone",
        };
    }
};

pub fn contractIsWellFormed() bool {
    if (!Owner.console_kernel.harnessMayProvision()) return false;
    if (Owner.guest_title.harnessMayProvision()) return false;
    if (Owner.emulator.harnessMayProvision()) return false;

    if (custodyOf(false, false, false) != .unprovisioned) return false;
    if (custodyOf(true, false, false) != .harness_provisioned) return false;
    if (custodyOf(false, true, false) != .owner_established) return false;
    if (custodyOf(true, true, true) != .owner_adopted) return false;
    if (custodyOf(true, true, false) != .contested) return false;

    if (divergenceOf(true, true, false) != .diverged) return false;
    if (divergenceOf(true, true, true) != .confirmed) return false;
    if (divergenceOf(true, false, false) != .uncontested) return false;

    // The property the whole model exists for: a write that lands after its
    // consumer is late even though the value is correct.
    if (timingOf(true, 100, true, 10) != .after_first_consumer) return false;
    if (timingOf(true, 10, true, 100) != .before_first_consumer) return false;
    if (timingOf(true, 0, true, 100) != .before_guest_started) return false;
    if (timingOf(true, 100, true, null) != .unknown) return false;
    if (timingOf(false, 0, true, 100) != .not_provisioned) return false;
    return true;
}

test "custody separates a completed handoff from a load-bearing harness write" {
    // The harness wrote and nobody challenged it: correct, and the run now
    // depends on it.
    const alone = custodyOf(true, false, false);
    try std.testing.expectEqual(Custody.harness_provisioned, alone);
    try std.testing.expect(alone.loadBearing());
    try std.testing.expect(!alone.settled());

    // The owner independently wrote the same value: the handoff completed.
    const adopted = custodyOf(true, true, true);
    try std.testing.expectEqual(Custody.owner_adopted, adopted);
    try std.testing.expect(adopted.settled());
    try std.testing.expect(!adopted.loadBearing());

    // The owner wrote something else: the harness value was wrong.
    const contested = custodyOf(true, true, false);
    try std.testing.expectEqual(Custody.contested, contested);
    try std.testing.expect(!contested.settled());
    try std.testing.expectEqual(Divergence.diverged, divergenceOf(true, true, false));
}

test "a correct value written after its consumer is still a failure" {
    // This is the case the model exists for. The value is right, the variable
    // reads populated, every ladder rung is met, and the title decided against
    // the zero long ago.
    const late = timingOf(true, 100_000_000, true, 4_000_000);
    try std.testing.expectEqual(Timing.after_first_consumer, late);
    try std.testing.expect(late.missedItsConsumer());
    try std.testing.expect(std.mem.indexOf(u8, late.guidance(), "never revisited") != null);

    // The same value written before the guest ran at all is the console's own
    // ordering and needs no argument about scheduling.
    const preboot = timingOf(true, 0, false, null);
    try std.testing.expectEqual(Timing.before_guest_started, preboot);
    try std.testing.expect(!preboot.missedItsConsumer());
}

test "an unobserved consumer is unknown rather than assumed early" {
    const timing = timingOf(true, 5_000, true, null);
    try std.testing.expectEqual(Timing.unknown, timing);
    try std.testing.expect(!timing.missedItsConsumer());
    try std.testing.expect(std.mem.indexOf(u8, timing.guidance(), "cannot be decided") != null);
}

test "only console-kernel state may be provisioned" {
    try std.testing.expect(Owner.console_kernel.harnessMayProvision());
    try std.testing.expect(!Owner.guest_title.harnessMayProvision());
    try std.testing.expect(!Owner.emulator.harnessMayProvision());
    try std.testing.expect(std.mem.indexOf(u8, Refusal.not_harness_owned.guidance(), "fabricate") != null);
}

test "every vocabulary member carries a label and actionable guidance" {
    inline for (@typeInfo(Timing).@"enum".fields) |field| {
        const value: Timing = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 20);
    }
    inline for (@typeInfo(Divergence).@"enum".fields) |field| {
        const value: Divergence = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 20);
    }
    inline for (@typeInfo(Refusal).@"enum".fields) |field| {
        const value: Refusal = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 10);
    }
    inline for (@typeInfo(Finding).@"enum".fields) |field| {
        const value: Finding = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 20);
    }
    inline for (@typeInfo(Custody).@"enum".fields) |field| {
        const value: Custody = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
    try std.testing.expect(contractIsWellFormed());
}
