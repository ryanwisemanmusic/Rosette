//! The host operations a translated emulator depends on, each named with the
//! emulator subsystem that depends on it and what its failure looks like from
//! the far end.
//!
//! ## Why this package exists
//!
//! An emulator running under translation lives in its own world twice over. It
//! virtualises a console, and it is itself virtualised — so when it asks the
//! host for something, three different layers can quietly give it something
//! other than what it asked for, and none of them reports it. A `mprotect` of
//! one 4 KiB guest page silently covers 16 KiB. A one-millisecond sleep takes
//! ten. A thread priority is accepted and ignored. Each of those is *correct*
//! at every API boundary it crosses and wrong for the code that depended on it.
//!
//! The emulator cannot detect any of them. It has no reason to: on the platform
//! it was written for they are all true, so nothing in it checks. And the
//! symptom always appears somewhere else — a frame that never arrives, a wait
//! that always times out, a producer that looks stalled — which is why weeks go
//! into the far end of a pipeline whose foundation was never verified.
//!
//! So this declares the foundation. Not as an assumption: as a set of
//! operations Rosette can **actually perform on the real machine, once, before
//! the guest runs**, and then report as verified, failed, or degraded with the
//! measured number attached.
//!
//! ## The rule that makes it worth anything
//!
//! A capability is `verified` only when Rosette did the operation and observed
//! the result. Nothing here is satisfied by a header constant, a platform
//! `#ifdef`, or a successful return code alone: a `mprotect` that returns zero
//! and covers four times the range it was given returned success and did not do
//! what was asked. Where a capability has a magnitude, the magnitude is
//! measured and reported next to what was requested, because "it worked" and
//! "it worked at the resolution the caller needed" are different answers and
//! only the second one is useful.
//!
//! ## What this package must never become
//!
//! It holds no state, performs no I/O, and never probes anything. It is the
//! vocabulary: which capability, whose dependency, what a failure means. The
//! prober that actually touches the machine lives in `lib/preflight` and is the
//! only thing allowed to say `verified`.

const std = @import("std");

/// How much a capability matters to a run.
pub const Severity = enum(u8) {
    /// The emulator cannot function correctly without it. A failure here
    /// explains any number of downstream symptoms and none of them is worth
    /// investigating first.
    foundational,
    /// The emulator functions and something measurable about it is wrong —
    /// usually timing. These are the failures that produce a run where every
    /// counter is healthy and nothing finishes.
    fidelity,
    /// Worth knowing. Never a finding on its own.
    informational,

    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .foundational => "foundational",
            .fidelity => "fidelity",
            .informational => "informational",
        };
    }
};

/// What the prober found. Deliberately four outcomes: the difference between
/// "it does not work" and "nobody checked" is the whole point of the package,
/// and a capability that works but not well enough is a third thing again.
pub const Outcome = enum(u8) {
    /// The probe never ran. Says nothing about the host.
    unprobed,
    /// Rosette performed the operation and it did what was asked.
    verified,
    /// Rosette performed the operation and it succeeded at a magnitude that
    /// will not serve the dependant. Success at the API and failure in fact.
    degraded,
    /// Rosette performed the operation and it did not work.
    failed,
    /// The operation cannot be attempted on this host at all — a platform
    /// without the facility rather than a facility that misbehaves.
    unavailable,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .unprobed => "UNPROBED",
            .verified => "verified",
            .degraded => "DEGRADED",
            .failed => "FAILED",
            .unavailable => "unavailable",
        };
    }

    /// Whether a reader may rely on the capability.
    pub fn dependable(self: Outcome) bool {
        return self == .verified;
    }
};

/// The host operations the emulator's behaviour rests on.
pub const Capability = enum(u8) {
    /// The granularity at which the host will actually change page protection.
    host_page_granularity,
    /// The granularity at which a guest page protection change is *enforced
    /// against the guest*, after whatever Rosette does to make up the
    /// difference. Separate from `host_page_granularity` on purpose: on a host
    /// whose page is larger than the console's, those two numbers are different
    /// and only this one decides what the guest experiences.
    guest_page_protection_fidelity,
    /// Replacing part of an existing mapping in place.
    fixed_mapping_replacement,
    /// Removing and restoring access to a page, which is how a write watch is
    /// implemented.
    protection_cycle,
    /// Mapping memory that can be written and then executed.
    executable_mapping,
    /// The smallest interval the monotonic clock can distinguish.
    monotonic_clock_resolution,
    /// How long a short sleep actually takes.
    sleep_granularity,
    /// How much a timed wait overshoots its deadline.
    timed_wait_fidelity,
    /// Creating a thread, and how long it takes.
    thread_creation,
    /// Reserving a large contiguous address range.
    large_reservation,

    pub fn label(self: Capability) []const u8 {
        return switch (self) {
            .host_page_granularity => "host page granularity",
            .guest_page_protection_fidelity => "guest page protection fidelity",
            .fixed_mapping_replacement => "fixed mapping replacement",
            .protection_cycle => "protection removal and restore",
            .executable_mapping => "writable-then-executable mapping",
            .monotonic_clock_resolution => "monotonic clock resolution",
            .sleep_granularity => "short sleep granularity",
            .timed_wait_fidelity => "timed wait fidelity",
            .thread_creation => "thread creation",
            .large_reservation => "large address reservation",
        };
    }

    pub fn severity(self: Capability) Severity {
        return switch (self) {
            .fixed_mapping_replacement,
            .protection_cycle,
            .executable_mapping,
            .thread_creation,
            .large_reservation,
            => .foundational,

            .host_page_granularity,
            .guest_page_protection_fidelity,
            .sleep_granularity,
            .timed_wait_fidelity,
            => .fidelity,

            .monotonic_clock_resolution => .informational,
        };
    }

    /// The emulator subsystem whose behaviour rests on this. Named so a
    /// failure here can be joined to the symptom it will produce rather than
    /// read as an abstract platform note.
    pub fn dependant(self: Capability) []const u8 {
        return switch (self) {
            .host_page_granularity => "emulator:memory (guest page protection)",
            .guest_page_protection_fidelity => "emulator:memory (guest page protection, as the guest sees it)",
            .fixed_mapping_replacement => "emulator:memory (heap and XEX image mapping)",
            .protection_cycle => "emulator:memory (ring and texture write watches)",
            .executable_mapping => "emulator:cpu (PowerPC code generation)",
            .monotonic_clock_resolution => "emulator:clock (guest tick source)",
            .sleep_granularity => "emulator:gpu (frame limiter vblank pacing)",
            .timed_wait_fidelity => "emulator:kernel (guest timed waits and DPC delivery)",
            .thread_creation => "emulator:kernel (guest thread creation)",
            .large_reservation => "emulator:memory (console address space reservation)",
        };
    }

    /// What a failure here will look like from the far end of the run. This is
    /// the field that saves the week: every one of these symptoms has been
    /// investigated as a graphics or scheduling defect at some point.
    pub fn failureLooksLike(self: Capability) []const u8 {
        return switch (self) {
            .host_page_granularity => "the kernel will not change protection at the console's page size, so every protection change the emulator forwards to the host covers whole host pages. On its own this is a magnitude, not a defect: what it costs depends entirely on whether anything restores the missing resolution, which is what `guest page protection fidelity` measures. Read that row before attributing a fault or a missed write watch to this one",
            .guest_page_protection_fidelity => "nothing restores the resolution the host will not give, so a guest page protection change covers neighbouring guest pages. Write watches fire for writes that did not happen, and a page the guest believes is writable faults — which surfaces as spurious faults in unrelated code and as a ring the emulator believes was modified when it was not",
            .fixed_mapping_replacement => "the emulator cannot place a module or heap where it needs to, and falls back to an address the guest was never told about. Guest pointers then resolve to the wrong memory, which surfaces as corruption rather than as a mapping failure",
            .protection_cycle => "write watches cannot be armed. The emulator stops learning when the guest modifies the ring or a texture, and reuses stale contents — which surfaces as a frame that renders the previous frame's data, or as no frame at all",
            .executable_mapping => "the PowerPC code generator cannot publish translated code. This one at least fails loudly, but under a second translation layer it can fail as a silent fallback to an interpreter and surface only as a run that is inexplicably slow",
            .monotonic_clock_resolution => "the guest tick source cannot distinguish short intervals, so guest timing arithmetic quantises. Rarely fatal and it changes what a timing measurement means",
            .sleep_granularity => "the frame limiter sleeps far longer than it asked to, so vblanks are further apart than the emulator believes. Every guest wait that is paced by vblank inherits the error, and the title's frame loop runs at a rate nothing in the emulator reports",
            .timed_wait_fidelity => "a guest wait with a millisecond deadline actually blocks for much longer. Bounded polls that should retry many times retry a few, timeouts that should be rare become the common case, and a producer/consumer handshake that is correct by construction stops making progress",
            .thread_creation => "guest threads cannot be created. The symptom appears wherever the missing thread was supposed to do work, never at the creation site",
            .large_reservation => "the console address space cannot be reserved contiguously and the emulator falls back to a scattered mapping. Guest physical/virtual aliasing then breaks for the ranges that did not land where expected",
        };
    }

    /// Whether the capability has a magnitude that must be compared against a
    /// requirement, rather than a yes/no result.
    pub fn measured(self: Capability) bool {
        return switch (self) {
            .host_page_granularity,
            .guest_page_protection_fidelity,
            .monotonic_clock_resolution,
            .sleep_granularity,
            .timed_wait_fidelity,
            .thread_creation,
            => true,
            else => false,
        };
    }

    /// The unit of `measured_value` and `requirement`, for the report.
    pub fn unit(self: Capability) []const u8 {
        return switch (self) {
            .host_page_granularity, .guest_page_protection_fidelity => "bytes",
            .monotonic_clock_resolution => "ns",
            .sleep_granularity, .timed_wait_fidelity => "us",
            .thread_creation => "us",
            else => "",
        };
    }

    /// The magnitude beyond which the capability is `degraded` rather than
    /// `verified`. Zero for capabilities with no magnitude.
    ///
    /// These are deliberately loose. The point is not to hold the host to a
    /// standard: it is to make a number that is *far* outside the dependant's
    /// assumption visible at the moment it can still be attributed. A sleep
    /// that overshoots by 200 microseconds is ordinary scheduling; one that
    /// overshoots by twenty milliseconds is a different machine from the one
    /// the frame limiter was written for.
    pub fn degradedAbove(self: Capability) u64 {
        return switch (self) {
            // A host page larger than the console's 4 KiB guest page means every
            // guest-granular protection change is coarser than requested.
            .host_page_granularity => 4096,
            // The console's own page. A protection change the guest cannot
            // rely on at this resolution is the failure this row exists for.
            .guest_page_protection_fidelity => 4096,
            .monotonic_clock_resolution => 1_000,
            // The frame limiter sleeps for 90% of a vblank. Overshooting a
            // short sleep by more than four milliseconds moves a 60 Hz pump to
            // something slower than 50 Hz on its own.
            .sleep_granularity => 4_000,
            // A guest wait with a millisecond deadline overshooting by more
            // than eight milliseconds turns bounded polls into timeouts.
            .timed_wait_fidelity => 8_000,
            .thread_creation => 5_000,
            else => 0,
        };
    }

    /// The capability that measures whether the shortfall in this one has been
    /// made up, when such a capability exists.
    ///
    /// This is the difference between "the machine will not do what was asked"
    /// and "the emulator does not get what it needs". A host page four times
    /// the console's is the first; it only becomes the second when nothing
    /// restores the resolution. Naming the pair here — rather than leaving a
    /// reader to notice that two rows are about one subject — is what stops a
    /// permanent, unactionable red row from sitting at the top of every run
    /// telling the reader to distrust every timing symptom below it.
    pub fn compensatedBy(self: Capability) ?Capability {
        return switch (self) {
            .host_page_granularity => .guest_page_protection_fidelity,
            else => null,
        };
    }

    /// Who owns closing the gap when this capability is degraded. For a raw
    /// host magnitude that is nobody — the machine is the machine — so the
    /// owner is whoever owns the compensation.
    pub fn shortfallOwner(self: Capability) []const u8 {
        return switch (self) {
            .host_page_granularity,
            .guest_page_protection_fidelity,
            => "rosette:memory (guest protection overlay)",
            else => "host",
        };
    }

    /// Whether the preflight prober alone can answer this capability.
    ///
    /// A capability whose subject is Rosette's own compensation cannot be
    /// probed by a module that knows nothing about it, and pretending
    /// otherwise would put a green check next to a mechanism nobody ran. The
    /// prober records those as `unprobed` and the owner of the mechanism
    /// supplies the finding.
    pub fn probedByPreflight(self: Capability) bool {
        return self != .guest_page_protection_fidelity;
    }
};

pub const capability_count: usize = @typeInfo(Capability).@"enum".fields.len;

pub fn allCapabilities() [capability_count]Capability {
    var out: [capability_count]Capability = undefined;
    for (&out, 0..) |*slot, index| slot.* = @enumFromInt(index);
    return out;
}

/// Decide an outcome from a measurement. Kept here rather than in the prober so
/// the threshold and the sentence that explains it live in one place.
pub fn classify(capability: Capability, succeeded: bool, measured_value: u64) Outcome {
    if (!succeeded) return .failed;
    if (!capability.measured()) return .verified;
    const limit = capability.degradedAbove();
    if (limit == 0) return .verified;
    return if (measured_value > limit) .degraded else .verified;
}

/// One capability's result, as the prober fills it in.
pub const Finding = struct {
    capability: Capability,
    outcome: Outcome = .unprobed,
    /// What was measured, in `capability.unit()`.
    measured_value: u64 = 0,
    /// What was asked for, where that differs from the threshold.
    requested_value: u64 = 0,
    /// An errno or platform code, when the operation failed.
    error_code: i32 = 0,
};

/// The whole reading, summarised.
pub const Summary = struct {
    probed: u8 = 0,
    verified: u8 = 0,
    degraded: u8 = 0,
    failed: u8 = 0,
    unavailable: u8 = 0,
    foundational_failures: u8 = 0,
    fidelity_failures: u8 = 0,
    /// Degraded host magnitudes whose compensating capability is verified.
    /// Counted apart from `fidelity_failures` because the dependant is getting
    /// what it needs and a reader sent to investigate one of these would be
    /// investigating the machine rather than the run.
    compensated: u8 = 0,

    /// Whether the host is one the emulator can run correctly on at all.
    pub fn foundationHolds(self: Summary) bool {
        return self.foundational_failures == 0;
    }

    /// The one sentence a reader needs.
    pub fn describe(self: Summary) []const u8 {
        if (self.probed == 0) {
            return "nothing was probed, so every emulator behaviour below rests on an assumption about this machine that nobody checked";
        }
        if (self.foundational_failures != 0) {
            return "an operation the emulator cannot function without does not work on this host. Every downstream symptom is a consequence and none of them is worth investigating first";
        }
        if (self.fidelity_failures != 0) {
            return "every operation works and at least one of them works at a magnitude the emulator was not written for, with nothing making up the difference. This is the state that produces healthy counters and a run that never finishes: read the degraded rows below before attributing any timing symptom to the guest";
        }
        if (self.compensated != 0) {
            return "every operation works. One or more of them works at a magnitude the emulator was not written for and the shortfall is made up before the emulator sees it, so those rows are a property of the machine and not a finding against the run";
        }
        return "every probed host operation did what was asked, at a magnitude the dependant can use. A timing or memory symptom later in the run is not this layer's";
    }
};

test "every capability names a dependant and a failure symptom" {
    for (allCapabilities()) |capability| {
        try std.testing.expect(capability.label().len != 0);
        try std.testing.expect(capability.dependant().len != 0);
        try std.testing.expect(capability.failureLooksLike().len != 0);
    }
}

test "a measured capability declares a unit and a threshold" {
    for (allCapabilities()) |capability| {
        if (!capability.measured()) continue;
        try std.testing.expect(capability.unit().len != 0);
        try std.testing.expect(capability.degradedAbove() != 0);
    }
}

// Success at the API and failure in fact are different answers, and only the
// second one explains a run where every counter is healthy.
test "a succeeding operation at the wrong magnitude is degraded, not verified" {
    try std.testing.expectEqual(
        Outcome.verified,
        classify(.sleep_granularity, true, 900),
    );
    try std.testing.expectEqual(
        Outcome.degraded,
        classify(.sleep_granularity, true, 15_000),
    );
    try std.testing.expectEqual(
        Outcome.failed,
        classify(.sleep_granularity, false, 0),
    );
    try std.testing.expect(!Outcome.degraded.dependable());
}

test "an unmeasured capability that succeeded is verified" {
    try std.testing.expectEqual(
        Outcome.verified,
        classify(.executable_mapping, true, 0),
    );
}

// A 16 KiB host page is the ordinary case on Apple silicon and it is exactly
// the condition that makes a guest-granular protection change cover its
// neighbours.
test "a host page larger than the console's is degraded" {
    try std.testing.expectEqual(
        Outcome.degraded,
        classify(.host_page_granularity, true, 16384),
    );
    try std.testing.expectEqual(
        Outcome.verified,
        classify(.host_page_granularity, true, 4096),
    );
}

test "the summary separates a broken host from a slow one" {
    const nothing = Summary{};
    try std.testing.expect(nothing.foundationHolds());
    const broken = Summary{ .probed = 9, .foundational_failures = 1 };
    try std.testing.expect(!broken.foundationHolds());
    const slow = Summary{ .probed = 9, .fidelity_failures = 2 };
    try std.testing.expect(slow.foundationHolds());
    try std.testing.expect(!std.mem.eql(u8, broken.describe(), slow.describe()));
}

// The pairing is the point of the two rows: a raw host magnitude and the
// mechanism that makes it survivable are different subjects, and reporting the
// first without the second is how a permanent platform fact becomes a standing
// accusation against the run.
test "the host page magnitude names the capability that makes it survivable" {
    try std.testing.expectEqual(
        @as(?Capability, .guest_page_protection_fidelity),
        Capability.host_page_granularity.compensatedBy(),
    );
    // A compensating capability is not itself compensated: the chain has to
    // end somewhere, and that end is the row a reader must act on.
    try std.testing.expectEqual(
        @as(?Capability, null),
        Capability.guest_page_protection_fidelity.compensatedBy(),
    );
    try std.testing.expectEqual(
        @as(?Capability, null),
        Capability.sleep_granularity.compensatedBy(),
    );
    // Both rows are about the same subsystem and neither blames the machine
    // for a gap somebody owns.
    try std.testing.expectEqualStrings(
        Capability.host_page_granularity.shortfallOwner(),
        Capability.guest_page_protection_fidelity.shortfallOwner(),
    );
    try std.testing.expectEqualStrings("host", Capability.thread_creation.shortfallOwner());
}

// The 16 KiB Apple silicon page with a working overlay, which is the ordinary
// case: the host row is degraded, the fidelity row is verified, and the run
// has no fidelity failure.
test "a compensated host magnitude is not a fidelity failure" {
    try std.testing.expectEqual(
        Outcome.degraded,
        classify(.host_page_granularity, true, 16384),
    );
    try std.testing.expectEqual(
        Outcome.verified,
        classify(.guest_page_protection_fidelity, true, 4096),
    );
    // The same host with no overlay: the fidelity row degrades too, and *that*
    // is the row worth acting on.
    try std.testing.expectEqual(
        Outcome.degraded,
        classify(.guest_page_protection_fidelity, true, 16384),
    );

    const compensated = Summary{ .probed = 10, .degraded = 1, .compensated = 1 };
    try std.testing.expect(compensated.foundationHolds());
    try std.testing.expect(std.mem.indexOf(u8, compensated.describe(), "not a finding against the run") != null);

    const uncompensated = Summary{ .probed = 10, .degraded = 2, .fidelity_failures = 1 };
    try std.testing.expect(std.mem.indexOf(u8, uncompensated.describe(), "nothing making up the difference") != null);
    try std.testing.expect(!std.mem.eql(u8, compensated.describe(), uncompensated.describe()));
}

// A capability the prober cannot answer must say so rather than be given a
// default. The overlay is Rosette's, and a module that knows nothing about it
// has no business reporting on it.
test "the capability whose subject is Rosette's own compensation is not preflight's to answer" {
    try std.testing.expect(!Capability.guest_page_protection_fidelity.probedByPreflight());
    for (allCapabilities()) |capability| {
        if (capability == .guest_page_protection_fidelity) continue;
        try std.testing.expect(capability.probedByPreflight());
    }
}
