//! Delivering a queued GPU completion to a guest callback, and knowing exactly
//! how much was assumed to do it.
//!
//! The run this exists for reports, in the same checkpoint:
//!
//! ```text
//! vd-swap stage=draw completion signaled  state=YES count=169
//! XENOS COMPLETION EVIDENCE: draw_signals=24 draw_dispatch(attempts/success/failures)=0/0/0
//! XENIA INTERRUPT CALLBACK: registered=0 callback=0x821951f8
//! ```
//!
//! Work was completed, nothing was delivered, and **not one delivery was
//! attempted** — because the dispatcher holds no callback, while the callback's
//! address is sitting in the line below it. The address is known and unusable
//! at the same time, and the reason is provenance: it was read out of the
//! emulator's log text, not captured at a call Rosette intercepted.
//!
//! ## Provenance is the whole contract
//!
//! Those two ways of knowing an address are not interchangeable. An address
//! captured at an intercepted registration is a **binding**: Rosette saw the
//! guest hand it over. An address parsed from a diagnostic line is a **claim**:
//! it is as good as the sentence that carried it, which may be a stale
//! bring-up snapshot, a different object's field, or a value the emitter
//! reformatted. Calling into a claimed address is a real act with real
//! consequences — it transfers control to guest code at a location nothing
//! verified — so the two must never be counted together.
//!
//! ## Why dispatch at all
//!
//! Because a completion nobody delivers is indistinguishable from a completion
//! nobody generated, and the two have opposite causes. Delivering one and
//! watching what changes is the only way to tell a consumer that is missing its
//! signal from a consumer that is not there. That is diagnosis, not repair: the
//! result is recorded as a substitution and can never close the authentic
//! stage, so a run that only progressed because Rosette dispatched still reads
//! as a run whose title never received its own interrupt.
//!
//! This package holds no state and calls nothing. It is the vocabulary and the
//! admission rules; the ledger is `lib/gpu/draw_dispatch.zig`.

const std = @import("std");

/// How Rosette came to know a callback address. The ordering is the amount
/// assumed, lowest first, and every admission rule below reads it.
pub const Provenance = enum(u8) {
    /// No address is known.
    none = 0,
    /// Parsed out of an emulator diagnostic line. The weakest form: it is
    /// exactly as trustworthy as the sentence that carried it, and diagnostic
    /// lines in this system are routinely stale snapshots nobody retracted.
    emulator_log_claim = 1,
    /// Read from a guest structure Rosette can address — a kernel variable
    /// slot, an export table entry. Stronger than text because the value came
    /// from memory the guest owns, and weaker than a binding because nothing
    /// observed the guest *using* it as a callback.
    guest_memory_read = 2,
    /// Captured at a registration call Rosette intercepted. The guest handed
    /// this address over and Rosette watched it happen.
    intercepted_binding = 3,

    pub fn label(self: Provenance) []const u8 {
        return switch (self) {
            .none => "none",
            .emulator_log_claim => "emulator-log-claim",
            .guest_memory_read => "guest-memory-read",
            .intercepted_binding => "intercepted-binding",
        };
    }

    /// Whether the address was observed being used as a callback, rather than
    /// merely being seen somewhere.
    pub fn isBinding(self: Provenance) bool {
        return self == .intercepted_binding;
    }

    pub fn meaning(self: Provenance) []const u8 {
        return switch (self) {
            .none => "no callback address is known from any source",
            .emulator_log_claim => "the address was parsed from an emulator diagnostic line. It is as trustworthy as that sentence, and diagnostic lines here are routinely bring-up snapshots that were never retracted — so entering it transfers control to guest code at a location nothing has verified",
            .guest_memory_read => "the address was read from guest-owned memory. Better than text, and still not proof that the guest intends it as a callback entry point",
            .intercepted_binding => "the guest passed this address to a registration Rosette intercepted. The guest itself named it as the callback",
        };
    }
};

/// The callback integer is meaningful only inside one executor. Equal numeric
/// addresses in these domains are not interchangeable entry points.
pub const AddressSpace = enum(u8) {
    none,
    translated_x86,
    xenia_powerpc,

    pub fn label(self: AddressSpace) []const u8 {
        return switch (self) {
            .none => "none",
            .translated_x86 => "translated-x86",
            .xenia_powerpc => "xenia-powerpc",
        };
    }
};

/// What a dispatch attempt did.
pub const Outcome = enum(u8) {
    /// The callback ran and returned.
    delivered,
    /// No address is known from any source.
    refused_no_callback,
    /// An address is known but its provenance is below the admission floor for
    /// the current policy.
    refused_unverified,
    /// The callback belongs to a different instruction-set executor. No policy
    /// may override this refusal: provenance can prove an address exists, but
    /// cannot make a PowerPC entry point callable by the x86 interpreter.
    refused_cross_domain,
    /// Policy forbids Rosette originating this dispatch at all.
    refused_by_policy,
    /// There was nothing queued to deliver.
    nothing_queued,
    /// The call was made and did not return normally.
    failed,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .delivered => "delivered",
            .refused_no_callback => "refused-no-callback",
            .refused_unverified => "refused-unverified",
            .refused_cross_domain => "refused-cross-domain",
            .refused_by_policy => "refused-by-policy",
            .nothing_queued => "nothing-queued",
            .failed => "FAILED",
        };
    }

    pub fn attempted(self: Outcome) bool {
        return self == .delivered or self == .failed;
    }
};

/// What changed as a result. A delivery that changes nothing is a finding, not
/// a success: it means the consumer received its signal and still did not act,
/// which points somewhere entirely different from a consumer that never got one.
pub const Effect = enum(u8) {
    /// Not yet sampled.
    unmeasured,
    /// Nothing observable changed. The consumer got the signal and did nothing.
    no_observable_change,
    /// The guest advanced a counter the dispatcher was watching.
    guest_progressed,
    /// The producer published new ring work after the dispatch.
    producer_published,
    /// The title entered its present path.
    present_reached,

    pub fn label(self: Effect) []const u8 {
        return switch (self) {
            .unmeasured => "unmeasured",
            .no_observable_change => "no-observable-change",
            .guest_progressed => "guest-progressed",
            .producer_published => "producer-published",
            .present_reached => "present-reached",
        };
    }

    /// Whether the dispatch moved the run forward.
    pub fn advanced(self: Effect) bool {
        return switch (self) {
            .guest_progressed, .producer_published, .present_reached => true,
            .unmeasured, .no_observable_change => false,
        };
    }

    pub fn guidance(self: Effect) []const u8 {
        return switch (self) {
            .unmeasured => "the dispatch has not been followed by a sample, so its effect is unknown rather than absent",
            .no_observable_change => "the callback ran and nothing the dispatcher watches changed. The consumer is reachable and unmoved: whatever it is waiting for, this was not it — which rules out a missing interrupt and points at the wait itself",
            .guest_progressed => "a guest progress counter advanced after the dispatch. The signal was what the consumer needed, and the run was blocked on delivery rather than on the guest",
            .producer_published => "the producer published new ring work after the dispatch. The completion was gating the producer's next batch",
            .present_reached => "the title entered its present path after the dispatch. The missing completion was the whole wall",
        };
    }
};

/// How much Rosette is permitted to originate. A run picks one and the ledger
/// enforces it; nothing escalates on its own.
pub const Policy = enum(u8) {
    /// Never dispatch. Record what would have been possible.
    observe_only,
    /// Dispatch only to an address the guest was seen handing over.
    bound_callbacks_only,
    /// Dispatch to any address from guest-owned memory or better.
    guest_addressed,
    /// Dispatch to anything known, including an address parsed from log text.
    /// A diagnostic mode: it transfers control to an unverified location, and
    /// it exists because a completion nobody delivers cannot be told apart
    /// from one nobody generated.
    any_known_address,

    pub fn label(self: Policy) []const u8 {
        return switch (self) {
            .observe_only => "observe-only",
            .bound_callbacks_only => "bound-callbacks-only",
            .guest_addressed => "guest-addressed",
            .any_known_address => "any-known-address",
        };
    }

    /// The weakest provenance this policy will enter. `null` means none.
    pub fn admissionFloor(self: Policy) ?Provenance {
        return switch (self) {
            .observe_only => null,
            .bound_callbacks_only => .intercepted_binding,
            .guest_addressed => .guest_memory_read,
            .any_known_address => .emulator_log_claim,
        };
    }

    pub fn admits(self: Policy, provenance: Provenance) bool {
        if (provenance == .none) return false;
        const floor = self.admissionFloor() orelse return false;
        return @intFromEnum(provenance) >= @intFromEnum(floor);
    }
};

/// The rule. Separated from the ledger so the decision is made the same way
/// every time and can be tested without a guest.
pub fn decide(
    policy: Policy,
    provenance: Provenance,
    callback_space: AddressSpace,
    executor_space: AddressSpace,
    queued: u64,
) Outcome {
    if (queued == 0) return .nothing_queued;
    if (policy == .observe_only) return .refused_by_policy;
    if (provenance == .none) return .refused_no_callback;
    if (callback_space == .none or callback_space != executor_space) return .refused_cross_domain;
    if (!policy.admits(provenance)) return .refused_unverified;
    return .delivered;
}

/// Whether a delivery performed under this provenance may close the contract's
/// authentic dispatch stage.
///
/// It may not, ever, and the function exists to make that a rule rather than a
/// convention. Only the emulator delivering its own interrupt is authentic; a
/// dispatch Rosette originated is a substitution however well-founded its
/// address was, and a run that progressed because of one has still not shown
/// that the title receives its own completions.
pub fn closesAuthenticStage(provenance: Provenance) bool {
    _ = provenance;
    return false;
}

pub fn contractIsWellFormed() bool {
    // Provenance ordering is the admission ordering.
    if (@intFromEnum(Provenance.none) >= @intFromEnum(Provenance.emulator_log_claim)) return false;
    if (@intFromEnum(Provenance.emulator_log_claim) >= @intFromEnum(Provenance.guest_memory_read)) return false;
    if (@intFromEnum(Provenance.guest_memory_read) >= @intFromEnum(Provenance.intercepted_binding)) return false;
    if (!Provenance.intercepted_binding.isBinding()) return false;
    if (Provenance.emulator_log_claim.isBinding()) return false;

    // Observe-only admits nothing; the widest policy admits everything known.
    if (Policy.observe_only.admits(.intercepted_binding)) return false;
    if (!Policy.any_known_address.admits(.emulator_log_claim)) return false;
    if (Policy.bound_callbacks_only.admits(.emulator_log_claim)) return false;
    if (Policy.bound_callbacks_only.admits(.guest_memory_read)) return false;
    if (!Policy.guest_addressed.admits(.guest_memory_read)) return false;
    if (Policy.guest_addressed.admits(.emulator_log_claim)) return false;
    if (Policy.any_known_address.admits(.none)) return false;

    if (decide(.any_known_address, .emulator_log_claim, .xenia_powerpc, .translated_x86, 0) != .nothing_queued) return false;
    if (decide(.any_known_address, .none, .none, .translated_x86, 5) != .refused_no_callback) return false;
    if (decide(.observe_only, .intercepted_binding, .translated_x86, .translated_x86, 5) != .refused_by_policy) return false;
    if (decide(.bound_callbacks_only, .emulator_log_claim, .translated_x86, .translated_x86, 5) != .refused_unverified) return false;
    if (decide(.bound_callbacks_only, .intercepted_binding, .translated_x86, .translated_x86, 5) != .delivered) return false;
    if (decide(.any_known_address, .intercepted_binding, .xenia_powerpc, .translated_x86, 5) != .refused_cross_domain) return false;

    // No provenance whatsoever makes a Rosette-originated dispatch authentic.
    inline for (@typeInfo(Provenance).@"enum".fields) |field| {
        if (closesAuthenticStage(@enumFromInt(field.value))) return false;
    }

    if (!Effect.present_reached.advanced()) return false;
    if (Effect.no_observable_change.advanced()) return false;
    if (Effect.unmeasured.advanced()) return false;
    if (!Outcome.delivered.attempted()) return false;
    if (Outcome.refused_no_callback.attempted()) return false;
    return true;
}

test "an address from log text is admitted only by the widest policy" {
    // The live case: callback=0x821951f8 is known, and it is known because a
    // diagnostic line said so. That is a claim, not a binding.
    try std.testing.expect(!Policy.bound_callbacks_only.admits(.emulator_log_claim));
    try std.testing.expect(!Policy.guest_addressed.admits(.emulator_log_claim));
    try std.testing.expect(Policy.any_known_address.admits(.emulator_log_claim));
    try std.testing.expect(std.mem.indexOf(u8, Provenance.emulator_log_claim.meaning(), "never retracted") != null);
}

test "no dispatch Rosette originates is ever authentic" {
    // The rule that makes the whole scaffold safe to build: a run that only
    // progressed because Rosette delivered a completion has still not shown
    // that the title receives its own.
    inline for (@typeInfo(Provenance).@"enum".fields) |field| {
        const provenance: Provenance = @enumFromInt(field.value);
        try std.testing.expect(!closesAuthenticStage(provenance));
    }
}

test "nothing queued outranks every refusal" {
    // A run with no completions to deliver must not report a policy refusal:
    // that would read as Rosette declining work that never existed.
    try std.testing.expectEqual(Outcome.nothing_queued, decide(.observe_only, .none, .none, .translated_x86, 0));
    try std.testing.expectEqual(Outcome.nothing_queued, decide(.any_known_address, .intercepted_binding, .translated_x86, .translated_x86, 0));
}

test "the widest policy cannot cross an instruction-set execution domain" {
    try std.testing.expectEqual(
        Outcome.refused_cross_domain,
        decide(.any_known_address, .intercepted_binding, .xenia_powerpc, .translated_x86, 24),
    );
}

test "a delivery that changes nothing is a finding, not a failure" {
    // It rules out a missing interrupt, which is a different and more useful
    // conclusion than a delivery that worked.
    try std.testing.expect(!Effect.no_observable_change.advanced());
    try std.testing.expect(std.mem.indexOf(u8, Effect.no_observable_change.guidance(), "rules out a missing interrupt") != null);
    try std.testing.expect(Effect.present_reached.advanced());
    try std.testing.expect(std.mem.indexOf(u8, Effect.present_reached.guidance(), "the whole wall") != null);
}

test "an unmeasured effect is not an absent one" {
    try std.testing.expect(!Effect.unmeasured.advanced());
    try std.testing.expect(std.mem.indexOf(u8, Effect.unmeasured.guidance(), "unknown rather than absent") != null);
}

test "the admission floor is exactly the policy ordering" {
    try std.testing.expect(Policy.observe_only.admissionFloor() == null);
    try std.testing.expectEqual(Provenance.intercepted_binding, Policy.bound_callbacks_only.admissionFloor().?);
    try std.testing.expectEqual(Provenance.guest_memory_read, Policy.guest_addressed.admissionFloor().?);
    try std.testing.expectEqual(Provenance.emulator_log_claim, Policy.any_known_address.admissionFloor().?);
    try std.testing.expect(contractIsWellFormed());
}

test "every vocabulary member carries a label and the risky ones explain themselves" {
    inline for (@typeInfo(Provenance).@"enum".fields) |field| {
        const value: Provenance = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.meaning().len > 30);
    }
    inline for (@typeInfo(Effect).@"enum".fields) |field| {
        const value: Effect = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 40);
    }
    inline for (@typeInfo(Outcome).@"enum".fields) |field| {
        const value: Outcome = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
    inline for (@typeInfo(Policy).@"enum".fields) |field| {
        const value: Policy = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
}
