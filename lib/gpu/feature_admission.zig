//! What the run is allowed to skip, and what skipping it costs the
//! authenticity of everything downstream.
//!
//! The defect this exists for
//! --------------------------
//! The active Xenia configuration has `gpu_ignore_unimplemented_opcode = true`.
//! That keeps a diagnostic run alive and it is dangerous when the goal is to
//! prove a faithful frame: an unknown PM4 opcode can program state,
//! synchronise, resolve, or kick presentation. Skipping one can leave the
//! guest waiting forever with no crash to show for it, or produce a blank
//! frame that looks like a rendering bug.
//!
//! "Ignore" is therefore not an outcome this contract offers. Every
//! unsupported operation is classified into one of five dispositions, and two
//! of them stop the run or void the frame.
//!
//! The other half is the run profile. A dozen independent booleans make it too
//! easy for a run to look authentic while a fallback is quietly active, so the
//! profile declares one mode and enumerates every intervention that is enabled
//! — including the ones that are enabled but whose predicate never fired,
//! because "enabled and inactive" and "disabled" are different postures and
//! only one of them can change tomorrow.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;

/// What to do about an operation the emulator does not implement.
pub const Disposition = enum(u8) {
    /// Proven not to matter on the current path.
    harmless = 0,
    /// Approximated, with the approximation written down.
    modelled = 1,
    /// Not needed yet; safe to continue and revisit.
    deferred = 2,
    /// Needed on the current path. The run is blocked.
    required = 3,
    /// A fallback that keeps the run moving and voids frame authenticity.
    diagnostic_fallback = 4,
    /// Nobody has classified it. Never a pass.
    unclassified = 255,

    pub fn label(self: Disposition) []const u8 {
        return switch (self) {
            .harmless => "harmless",
            .modelled => "modelled",
            .deferred => "deferred",
            .required => "REQUIRED",
            .diagnostic_fallback => "DIAGNOSTIC-FALLBACK",
            .unclassified => "UNCLASSIFIED",
        };
    }

    pub fn describe(self: Disposition) []const u8 {
        return switch (self) {
            .harmless => "proven irrelevant to the current path. Continuing past it changes nothing the title can observe",
            .modelled => "approximated with a documented behaviour. The run continues and the approximation is part of what the frame means",
            .deferred => "not needed on the current path and not proven irrelevant either. Safe to continue and it comes back the moment the path changes",
            .required => "needed on the current path. Continuing past it means the guest asked for something that did not happen, and the run is blocked rather than degraded",
            .diagnostic_fallback => "a substitute that keeps the run moving. Every frame produced downstream is non-authentic, permanently and regardless of how it looks",
            .unclassified => "nobody has said what this is. An unclassified skip is not a pass: it is an operation whose effect on state, synchronization, resolve and presentation nobody has checked",
        };
    }

    /// Whether the run may continue past it.
    pub fn permitsContinuation(self: Disposition) bool {
        return switch (self) {
            .harmless, .modelled, .deferred, .diagnostic_fallback => true,
            .required, .unclassified => false,
        };
    }

    /// Whether a frame produced after this can still be called authentic.
    pub fn preservesAuthenticity(self: Disposition) bool {
        return switch (self) {
            .harmless, .modelled, .deferred => true,
            .required, .diagnostic_fallback, .unclassified => false,
        };
    }
};

/// The kind of thing that was unsupported.
pub const Subject = enum(u8) {
    pm4_opcode = 0,
    register = 1,
    kernel_export = 2,
    shader_instruction = 3,
    texture_format = 4,
    vulkan_feature = 5,

    pub fn label(self: Subject) []const u8 {
        return switch (self) {
            .pm4_opcode => "pm4-opcode",
            .register => "register",
            .kernel_export => "kernel-export",
            .shader_instruction => "shader-instruction",
            .texture_format => "texture-format",
            .vulkan_feature => "vulkan-feature",
        };
    }
};

/// One unsupported operation the run met.
pub const Encounter = struct {
    subject: Subject = .pm4_opcode,
    /// Opcode, register index, ordinal — interpreted by `subject`.
    identifier: u32 = 0,
    disposition: Disposition = .unclassified,
    occurrences: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// Where in the stream it was found, so a reader can go and look.
    address: u32 = 0,
    /// Whether skipping it could plausibly touch each of these paths. Stated
    /// by whoever classified it, and the reason `harmless` has to be earned.
    could_affect_state: bool = false,
    could_affect_synchronization: bool = false,
    could_affect_resolve: bool = false,
    could_affect_presentation: bool = false,

    /// A `harmless` claim with any of the effect flags set is a contradiction:
    /// something proven irrelevant cannot also be able to touch the path.
    pub fn classificationConsistent(self: Encounter) bool {
        if (self.disposition != .harmless) return true;
        return !(self.could_affect_state or
            self.could_affect_synchronization or
            self.could_affect_resolve or
            self.could_affect_presentation);
    }
};

/// The mode a run declares about itself.
pub const Profile = enum(u8) {
    /// No intervention may fabricate guest progress, completion, publication,
    /// target content or a swap.
    authentic = 0,
    /// Interventions are allowed and the output is permanently labelled
    /// non-authentic.
    diagnostic = 1,
    /// The harness is deliberately standing in for the guest.
    synthetic = 2,
    /// A retained batch is being replayed. Never a live guest run.
    replay = 3,

    pub fn label(self: Profile) []const u8 {
        return switch (self) {
            .authentic => "authentic",
            .diagnostic => "diagnostic",
            .synthetic => "synthetic",
            .replay => "replay",
        };
    }

    pub fn allowsFabrication(self: Profile) bool {
        return self != .authentic;
    }
};

/// The interventions a run can have enabled. Each is a thing that can produce
/// guest-shaped work the guest did not do.
pub const Intervention = enum(u8) {
    host_callback_forcing = 0,
    host_signal_forcing = 1,
    ring_write_pointer_kick = 2,
    host_swap_injection = 3,
    presenter_nudge = 4,
    unknown_opcode_continuation = 5,
    edram_stub_substitution = 6,
    guest_memory_repair = 7,
    wait_timeout_override = 8,
    shader_fallback = 9,
    texture_fallback = 10,

    pub fn label(self: Intervention) []const u8 {
        return switch (self) {
            .host_callback_forcing => "host-callback-forcing",
            .host_signal_forcing => "host-signal-forcing",
            .ring_write_pointer_kick => "ring-write-pointer-kick",
            .host_swap_injection => "host-swap-injection",
            .presenter_nudge => "presenter-nudge",
            .unknown_opcode_continuation => "unknown-opcode-continuation",
            .edram_stub_substitution => "edram-stub-substitution",
            .guest_memory_repair => "guest-memory-repair",
            .wait_timeout_override => "wait-timeout-override",
            .shader_fallback => "shader-fallback",
            .texture_fallback => "texture-fallback",
        };
    }

    /// Whether enabling this can manufacture guest progress. These are the
    /// ones an authentic run may not have on.
    pub fn fabricatesGuestProgress(self: Intervention) bool {
        return switch (self) {
            .host_callback_forcing,
            .host_signal_forcing,
            .ring_write_pointer_kick,
            .host_swap_injection,
            .guest_memory_repair,
            .wait_timeout_override,
            => true,
            .presenter_nudge,
            .unknown_opcode_continuation,
            .edram_stub_substitution,
            .shader_fallback,
            .texture_fallback,
            => false,
        };
    }
};

pub const intervention_count: usize = @typeInfo(Intervention).@"enum".fields.len;

/// One intervention's posture. "Enabled but inactive" is recorded separately
/// from "disabled" because only the first can fire tomorrow.
pub const Posture = struct {
    enabled: bool = false,
    /// How many times its activation predicate was true.
    fired: u64 = 0,
    /// A short description of when it would fire. Kept so a reader does not
    /// have to reconstruct the predicate from source.
    predicate: []const u8 = "",

    pub fn armedButQuiet(self: Posture) bool {
        return self.enabled and self.fired == 0;
    }
};

pub const max_encounters: usize = 32;

pub const Summary = struct {
    encounters: usize = 0,
    dropped: u64 = 0,
    required: usize = 0,
    unclassified: usize = 0,
    diagnostic_fallbacks: usize = 0,
    inconsistent: usize = 0,
    interventions_enabled: usize = 0,
    interventions_fired: usize = 0,
    fabricating_enabled: usize = 0,

    pub fn blocking(self: Summary) usize {
        return self.required + self.unclassified;
    }
};

/// Whether a run may call itself authentic.
pub const Admission = enum(u8) {
    /// Nothing blocks it and no intervention could fabricate progress.
    authentic,
    /// The declared profile permits interventions, so the output is labelled
    /// and the run continues.
    degraded,
    /// An intervention that fabricates guest progress is enabled in a run that
    /// declared itself authentic.
    profile_violation,
    /// An operation the current path needs is unimplemented, or nobody
    /// classified one.
    blocked,

    pub fn label(self: Admission) []const u8 {
        return switch (self) {
            .authentic => "authentic",
            .degraded => "degraded",
            .profile_violation => "PROFILE-VIOLATION",
            .blocked => "BLOCKED",
        };
    }

    pub fn describe(self: Admission) []const u8 {
        return switch (self) {
            .authentic => "no unsupported operation blocks the current path and nothing enabled can fabricate guest progress. A frame from this run may be called the title's",
            .degraded => "the run continues with a documented fallback active. Whatever it produces is labelled non-authentic, and no gate downstream may treat it as the title's output",
            .profile_violation => "the run declared itself authentic and has an intervention enabled that can manufacture guest progress. Either the profile is wrong or the intervention is; the run's own claim about itself cannot be trusted until one of them changes",
            .blocked => "an operation the current path needs is unimplemented, or one was met and nobody classified it. Continuing means the guest asked for something that did not happen",
        };
    }

    pub fn permitsAuthenticFrame(self: Admission) bool {
        return self == .authentic;
    }
};

pub const Ledger = struct {
    profile: Profile = .authentic,
    postures: [intervention_count]Posture = [_]Posture{.{}} ** intervention_count,
    encounters: [max_encounters]Encounter = [_]Encounter{.{}} ** max_encounters,
    count: usize = 0,
    dropped: u64 = 0,
    /// Configuration is frozen once guest execution begins. Runtime
    /// encounters remain appendable; changing the profile or enabling a new
    /// intervention after that point would make two intervals of one run
    /// incomparable.
    configuration_sealed: bool = false,
    configuration_mutation_attempts: u64 = 0,

    pub fn declare(self: *Ledger, profile: Profile) bool {
        if (self.configuration_sealed) {
            self.configuration_mutation_attempts +|= 1;
            return false;
        }
        self.profile = profile;
        return true;
    }

    pub fn enable(self: *Ledger, which: Intervention, predicate: []const u8) bool {
        if (self.configuration_sealed) {
            self.configuration_mutation_attempts +|= 1;
            return false;
        }
        self.postures[@intFromEnum(which)] = .{ .enabled = true, .predicate = predicate };
        return true;
    }

    pub fn sealConfiguration(self: *Ledger) void {
        self.configuration_sealed = true;
    }

    pub fn configurationMutable(self: *const Ledger) bool {
        return !self.configuration_sealed;
    }

    pub fn noteFired(self: *Ledger, which: Intervention) void {
        self.postures[@intFromEnum(which)].fired +|= 1;
    }

    pub fn posture(self: *const Ledger, which: Intervention) Posture {
        return self.postures[@intFromEnum(which)];
    }

    fn find(self: *Ledger, subject: Subject, identifier: u32) ?*Encounter {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const entry = &self.encounters[index];
            if (entry.subject == subject and entry.identifier == identifier) return entry;
        }
        return null;
    }

    /// Record meeting an unsupported operation. New ones arrive
    /// `unclassified`, which blocks the run until somebody says what they are.
    pub fn encounter(self: *Ledger, subject: Subject, identifier: u32, step: u64) ?*Encounter {
        if (self.find(subject, identifier)) |existing| {
            existing.occurrences +|= 1;
            existing.last_step = step;
            return existing;
        }
        if (self.count >= max_encounters) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.encounters[self.count];
        self.count += 1;
        slot.* = .{
            .subject = subject,
            .identifier = identifier,
            .occurrences = 1,
            .first_step = step,
            .last_step = step,
        };
        return slot;
    }

    pub fn retained(self: *const Ledger) []const Encounter {
        return self.encounters[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{ .encounters = self.count, .dropped = self.dropped };
        for (self.retained()) |entry| {
            switch (entry.disposition) {
                .required => out.required += 1,
                .unclassified => out.unclassified += 1,
                .diagnostic_fallback => out.diagnostic_fallbacks += 1,
                else => {},
            }
            if (!entry.classificationConsistent()) out.inconsistent += 1;
        }
        var index: usize = 0;
        while (index < intervention_count) : (index += 1) {
            const item = self.postures[index];
            if (!item.enabled) continue;
            out.interventions_enabled += 1;
            if (item.fired != 0) out.interventions_fired += 1;
            const which: Intervention = @enumFromInt(index);
            if (which.fabricatesGuestProgress()) out.fabricating_enabled += 1;
        }
        return out;
    }

    pub fn admission(self: *const Ledger) Admission {
        const totals = self.summary();
        if (totals.blocking() != 0) return .blocked;
        if (self.profile == .authentic and totals.fabricating_enabled != 0) return .profile_violation;
        if (self.profile != .authentic) return .degraded;
        if (totals.diagnostic_fallbacks != 0) return .degraded;
        return .authentic;
    }

    /// The authenticity a frame from this run may claim.
    pub fn effectiveSourceClass(self: *const Ledger) SourceClass {
        return switch (self.admission()) {
            .authentic => .guest_authentic,
            .degraded => .diagnostic,
            .profile_violation, .blocked => .synthetic,
        };
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = @intFromEnum(self.profile);
        hash = hash *% 31 +% totals.encounters;
        hash = hash *% 31 +% totals.blocking();
        hash = hash *% 31 +% @intFromEnum(self.admission());
        hash = hash *% 31 +% @intFromBool(self.configuration_sealed);
        hash = hash *% 31 +% self.configuration_mutation_attempts;
        for (self.postures) |configured| {
            hash = hash *% 31 +% @intFromBool(configured.enabled);
            hash = hash *% 31 +% configured.fired;
        }
        return hash;
    }
};

// The `gpu_ignore_unimplemented_opcode = true` hazard: an unknown opcode met
// and nobody having said what it is.
test "an unclassified skip blocks the run rather than passing" {
    var ledger = Ledger{};
    const met = ledger.encounter(.pm4_opcode, 0x5A, 3_250_000_000).?;
    try std.testing.expectEqual(Disposition.unclassified, met.disposition);
    try std.testing.expect(!Disposition.unclassified.permitsContinuation());
    const admission = ledger.admission();
    try std.testing.expectEqual(Admission.blocked, admission);
    try std.testing.expect(!admission.permitsAuthenticFrame());
    try std.testing.expect(std.mem.indexOf(u8, Disposition.unclassified.describe(), "not a pass") != null);
}

test "a required operation blocks and a harmless one does not" {
    var ledger = Ledger{};
    const met = ledger.encounter(.pm4_opcode, 0x5A, 100).?;
    met.disposition = .required;
    met.could_affect_synchronization = true;
    try std.testing.expectEqual(Admission.blocked, ledger.admission());

    met.disposition = .harmless;
    met.could_affect_synchronization = false;
    try std.testing.expectEqual(Admission.authentic, ledger.admission());
    try std.testing.expectEqual(SourceClass.guest_authentic, ledger.effectiveSourceClass());
}

test "a harmless claim that admits it could touch the path is inconsistent" {
    var ledger = Ledger{};
    const met = ledger.encounter(.pm4_opcode, 0x5A, 100).?;
    met.disposition = .harmless;
    met.could_affect_presentation = true;
    try std.testing.expect(!met.classificationConsistent());
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().inconsistent);
}

// The audit's profile rule: an authentic run cannot have an intervention that
// fabricates guest progress.
test "an authentic profile with a fabricating intervention is a violation" {
    var ledger = Ledger{};
    _ = ledger.declare(.authentic);
    _ = ledger.enable(.ring_write_pointer_kick, "fires when the ring base changes and no write pointer follows");
    const admission = ledger.admission();
    try std.testing.expectEqual(Admission.profile_violation, admission);
    try std.testing.expect(!admission.permitsAuthenticFrame());
    try std.testing.expectEqual(SourceClass.synthetic, ledger.effectiveSourceClass());
    try std.testing.expect(std.mem.indexOf(u8, admission.describe(), "cannot be trusted") != null);

    // Declaring the run diagnostic makes the same configuration legitimate and
    // permanently labels the output.
    _ = ledger.declare(.diagnostic);
    try std.testing.expectEqual(Admission.degraded, ledger.admission());
    try std.testing.expectEqual(SourceClass.diagnostic, ledger.effectiveSourceClass());
}

// The `gpu_debug_force_swap_once = true` with `gpu_debug_force_swap_after_ms = 0`
// case: harmless today because its predicate is disabled, and the posture has
// to be reported rather than inferred.
test "enabled but never fired is recorded apart from disabled" {
    var ledger = Ledger{};
    _ = ledger.enable(.presenter_nudge, "fires when a swap has not arrived within the configured delay");
    const quiet = ledger.posture(.presenter_nudge);
    try std.testing.expect(quiet.armedButQuiet());
    try std.testing.expect(quiet.predicate.len != 0);
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().interventions_enabled);
    try std.testing.expectEqual(@as(usize, 0), ledger.summary().interventions_fired);
    // The presenter nudge does not fabricate guest progress, so an authentic
    // run may have it on.
    try std.testing.expectEqual(Admission.authentic, ledger.admission());

    ledger.noteFired(.presenter_nudge);
    try std.testing.expect(!ledger.posture(.presenter_nudge).armedButQuiet());
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().interventions_fired);
}

test "a diagnostic fallback degrades a run that is otherwise clean" {
    var ledger = Ledger{};
    const met = ledger.encounter(.texture_format, 6, 100).?;
    met.disposition = .diagnostic_fallback;
    try std.testing.expectEqual(Admission.degraded, ledger.admission());
    try std.testing.expect(!Disposition.diagnostic_fallback.preservesAuthenticity());
    try std.testing.expect(Disposition.diagnostic_fallback.permitsContinuation());
    try std.testing.expectEqual(SourceClass.diagnostic, ledger.effectiveSourceClass());
}

test "repeated encounters of one operation are counted once as a subject" {
    var ledger = Ledger{};
    _ = ledger.encounter(.pm4_opcode, 0x5A, 100).?;
    _ = ledger.encounter(.pm4_opcode, 0x5A, 200).?;
    _ = ledger.encounter(.pm4_opcode, 0x5B, 300).?;
    try std.testing.expectEqual(@as(usize, 2), ledger.summary().encounters);
    try std.testing.expectEqual(@as(u64, 2), ledger.retained()[0].occurrences);
    try std.testing.expectEqual(@as(u64, 200), ledger.retained()[0].last_step);
}

test "a clean run with nothing enabled is authentic" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Admission.authentic, ledger.admission());
    try std.testing.expect(ledger.admission().permitsAuthenticFrame());
    try std.testing.expectEqual(@as(usize, 0), ledger.summary().interventions_enabled);
}

test "profile configuration is immutable after the run starts" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.declare(.authentic));
    try std.testing.expect(ledger.enable(.presenter_nudge, "bounded diagnostic nudge"));
    ledger.sealConfiguration();
    try std.testing.expect(!ledger.configurationMutable());
    try std.testing.expect(!ledger.declare(.diagnostic));
    try std.testing.expect(!ledger.enable(.host_swap_injection, "late"));
    try std.testing.expectEqual(@as(u64, 2), ledger.configuration_mutation_attempts);
}

test "every disposition, subject and intervention states its vocabulary" {
    inline for (@typeInfo(Disposition).@"enum".fields) |field| {
        const which: Disposition = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
    inline for (@typeInfo(Subject).@"enum".fields) |field| {
        const which: Subject = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(Intervention).@"enum".fields) |field| {
        const which: Intervention = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    // "Ignore" is deliberately not offered as an outcome.
    try std.testing.expect(!Disposition.unclassified.permitsContinuation());
}
