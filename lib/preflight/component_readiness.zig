//! Which components have been shown to work, when, and whether the guest was
//! already depending on them by then.
//!
//! ## What this is for
//!
//! Everything else observes the emulator and reports what happened. This
//! reports something different and, in a translated run, more decisive:
//! **what the run is trusting without having checked.**
//!
//! A title's bring-up depends on sixteen or so distinct things working. Each of
//! them either works, or returns something plausible and does not — and the
//! second case produces its symptom thirty calls later, in a subsystem that is
//! itself fine. On 2026-08-31 the title initialised engines, initialised the
//! ring, enabled write-back, registered its interrupt callback, issued
//! twenty-four draws, and then waited on a manual-reset event that nothing ever
//! signalled, for ten and a half billion steps. Guest event signalling had
//! never been shown to work end to end. Nobody had ever asked.
//!
//! ## The two halves
//!
//! `noteProven` is the only way a component leaves `unproven`, and it takes a
//! step number. `noteUsed` records when the guest first depended on it, and it
//! takes a step number too. The interesting output is the relationship between
//! them, which is why both are recorded rather than a single boolean:
//!
//! * proven, then used — the ordering somebody arranged.
//! * used, then proven — the run worked on trust and happened to be right.
//! * used, never proven — the finding.
//!
//! ## What it never does
//!
//! The ledger itself does not stop the guest. A readiness ledger that refused
//! to let the guest proceed would be enforcing an ordering the emulator does
//! not have, and the first thing it would hide is the defect it was built to
//! find. It records. The run-integrity contract consumes its summary at the
//! admission boundary and may stop on an essential component used unproven or
//! marked broken; that decision stays outside this data structure so the
//! component rows remain inspectable.

const std = @import("std");
const contract = @import("rosette_component_readiness_contract");

pub const Component = contract.Component;
pub const Proof = contract.Proof;
pub const State = contract.State;
pub const Standing = contract.Standing;
pub const component_count = contract.component_count;
pub const allComponents = contract.allComponents;

pub const Record = struct {
    state: State = .unproven,
    proven_step: u64 = 0,
    /// What actually established it, borrowed. String literals owned by the
    /// reporting code, which outlives the run.
    prover: []const u8 = "",
    used: bool = false,
    first_use_step: u64 = 0,
    uses: u64 = 0,
    /// Why a proof could not be carried out, when it could not.
    obstacle: []const u8 = "",

    pub fn proven(self: Record) bool {
        return self.state == .proven;
    }
};

pub const Summary = struct {
    proven: u8 = 0,
    unproven: u8 = 0,
    broken: u8 = 0,
    unprovable: u8 = 0,
    used_unproven: u8 = 0,
    proven_after_use: u8 = 0,
    /// Components that could have been proven before the guest ran and were
    /// not. Unlike `used_unproven` this is a statement about Rosette's own
    /// preparation rather than about the emulator, and it is the part that is
    /// actually fixable ahead of time.
    provable_early_but_unproven: u8 = 0,
    essential_gaps: u8 = 0,

    pub fn readyPercent(self: Summary) u8 {
        const total: u16 = component_count;
        return @intCast((@as(u16, self.proven) * 100) / total);
    }

    pub fn describe(self: Summary) []const u8 {
        if (self.broken != 0) {
            return "a component was exercised and does not work. Everything that depends on it is a consequence, and none of the consequences is worth investigating first";
        }
        if (self.used_unproven != 0) {
            return "the guest is depending on components that nothing has ever shown to work. A symptom downstream of any of them cannot be attributed, because the thing it rests on was never checked — this list is the shortest one worth shortening";
        }
        if (self.provable_early_but_unproven != 0) {
            return "every component the guest has used was proven, and some that could have been exercised before the guest ran were not. Those are Rosette's to close and they cost nothing to close";
        }
        if (self.proven != 0 and self.unproven == 0) {
            return "every component has been shown to work, and each was shown before anything depended on it. A failure after this point is not a readiness problem";
        }
        return "components remain unproven and unused; the run has not reached them yet";
    }
};

pub const substrate_components = [_]Component{
    .guest_memory_aliasing,
    .register_aperture_dispatch,
    .host_graphics_device,
    .host_surface_presentation,
    .guest_code_translation,
    .kernel_export_table,
    .guest_thread_scheduling,
    .guest_event_signalling,
    .guest_critical_sections,
    .guest_timer_source,
};

/// Whether a component is one of the ten the substrate acceptance gate rests
/// on. A reader looking at a failing or unevaluable `G1` needs the rows that
/// hold it there, and those rows are exactly this set.
pub fn isSubstrate(component: Component) bool {
    for (substrate_components) |member| {
        if (member == component) return true;
    }
    return false;
}

/// The pre-GPU substrate only. Downstream graphics components such as render
/// target binding and frame handoff must not make the substrate gate circular.
pub const SubstrateSummary = struct {
    total: u8 = substrate_components.len,
    proven: u8 = 0,
    failed: u8 = 0,
    unproven: u8 = 0,
    /// The proof was attempted here and could not be carried out. Counted
    /// apart from `unproven`, because the two lead to opposite verdicts: an
    /// unproven component is waiting for the guest to reach it and an
    /// unprovable one will never be reached by waiting.
    unprovable: u8 = 0,

    pub fn ready(self: SubstrateSummary) bool {
        return self.total != 0 and self.proven == self.total and self.failed == 0;
    }

    /// Whether the substrate is merely un-exercised. True while every gap is
    /// something the guest has yet to do; false as soon as one of them is
    /// something that cannot be done here.
    pub fn awaitingFirstUse(self: SubstrateSummary) bool {
        return self.failed == 0 and self.unprovable == 0 and self.unproven != 0;
    }
};

pub const Ledger = struct {
    records: [component_count]Record = [_]Record{.{}} ** component_count,

    pub fn recordFor(self: *const Ledger, component: Component) Record {
        return self.records[@intFromEnum(component)];
    }

    /// Something exercised the component and it worked. The only way out of
    /// `unproven`, and it deliberately takes the step so the ordering against
    /// first use is a fact rather than an impression.
    ///
    /// The first proof wins. A component proven at startup and proven again
    /// mid-run was proven at startup, and letting a later proof overwrite the
    /// step would erase the ordering the ledger exists to report.
    pub fn noteProven(self: *Ledger, component: Component, step: u64, prover: []const u8) void {
        const slot = &self.records[@intFromEnum(component)];
        if (slot.state == .proven) return;
        slot.state = .proven;
        slot.proven_step = step;
        slot.prover = prover;
    }

    /// Something exercised the component and it did not work.
    pub fn noteFailed(self: *Ledger, component: Component, step: u64, prover: []const u8) void {
        const slot = &self.records[@intFromEnum(component)];
        slot.state = .failed;
        slot.proven_step = step;
        slot.prover = prover;
    }

    /// The proof could not be carried out here. Deliberately distinct from
    /// failure: an unattempted check is a hole in Rosette, and reporting it as
    /// a defect would send the next hour at the emulator.
    pub fn noteUnprovable(self: *Ledger, component: Component, obstacle: []const u8) void {
        const slot = &self.records[@intFromEnum(component)];
        if (slot.state == .proven or slot.state == .failed) return;
        slot.state = .unprovable;
        slot.obstacle = obstacle;
    }

    /// The guest depended on the component. Only the first use carries a step;
    /// the rest advance the count, because the question is when the run started
    /// trusting it and not how often.
    pub fn noteUsed(self: *Ledger, component: Component, step: u64) void {
        const slot = &self.records[@intFromEnum(component)];
        if (!slot.used) {
            slot.used = true;
            slot.first_use_step = step;
        }
        slot.uses +|= 1;
    }

    pub fn standing(self: *const Ledger, component: Component) Standing {
        const slot = self.records[@intFromEnum(component)];
        return contract.standingOf(
            slot.state == .proven,
            slot.state == .failed,
            slot.proven_step,
            slot.used,
            slot.first_use_step,
        );
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{};
        for (allComponents()) |component| {
            const slot = self.records[@intFromEnum(component)];
            switch (slot.state) {
                .proven => out.proven += 1,
                .failed => out.broken += 1,
                .unprovable => out.unprovable += 1,
                .unproven => {
                    out.unproven += 1;
                    if (component.proof().availableBeforeFirstUse()) {
                        out.provable_early_but_unproven += 1;
                    }
                },
            }
            const found = self.standing(component);
            if (found == .used_unproven) {
                out.used_unproven += 1;
                if (component.essential()) out.essential_gaps += 1;
            }
            if (found == .proven_after_use) out.proven_after_use += 1;
            if (found == .broken and component.essential()) out.essential_gaps += 1;
        }
        return out;
    }

    pub fn substrateSummary(self: *const Ledger) SubstrateSummary {
        var out = SubstrateSummary{};
        for (substrate_components) |component| {
            switch (self.recordFor(component).state) {
                .proven => out.proven += 1,
                .failed => out.failed += 1,
                .unproven => out.unproven += 1,
                .unprovable => {
                    out.unprovable += 1;
                    out.unproven += 1;
                },
            }
        }
        return out;
    }

    /// The first substrate component still holding the substrate gate closed,
    /// in declaration order. `G1` reporting a count of unproven components and
    /// not naming one of them is the difference between a reader knowing where
    /// to look and a reader knowing only that something is missing.
    pub fn firstUnprovenSubstrate(self: *const Ledger) ?Component {
        for (substrate_components) |component| {
            if (!self.recordFor(component).proven()) return component;
        }
        return null;
    }

    /// The one component to act on: broken first, then an essential component
    /// being used unproven, then any component being used unproven, then one
    /// that could have been proven early and was not.
    pub fn firstFinding(self: *const Ledger) ?Component {
        var best: ?Component = null;
        var best_rank: u8 = 255;
        for (allComponents()) |component| {
            const rank = rankOf(self.standing(component), component);
            if (rank >= best_rank) continue;
            best_rank = rank;
            best = component;
        }
        return if (best_rank == 255) null else best;
    }
};

fn rankOf(found: Standing, component: Component) u8 {
    return switch (found) {
        .broken => if (component.essential()) 0 else 1,
        .used_unproven => if (component.essential()) 2 else 3,
        .proven_after_use => 4,
        else => 255,
    };
}

test "an empty ledger has nothing to act on" {
    const ledger = Ledger{};
    try std.testing.expect(ledger.firstFinding() == null);
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u8, 0), totals.proven);
    try std.testing.expectEqual(@as(u8, 0), totals.used_unproven);
    const substrate = ledger.substrateSummary();
    try std.testing.expectEqual(@as(u8, 10), substrate.total);
    try std.testing.expectEqual(@as(u8, 10), substrate.unproven);
    try std.testing.expect(!substrate.ready());
}

test "the substrate excludes downstream graphics readiness" {
    var ledger = Ledger{};
    for (substrate_components) |component| ledger.noteProven(component, 1, "test");
    try std.testing.expect(ledger.substrateSummary().ready());

    // The first-pixel and handoff components are judged by later acceptance
    // gates. Leaving them unproven must not reopen G1.
    try std.testing.expectEqual(State.unproven, ledger.recordFor(.render_target_binding).state);
    try std.testing.expectEqual(State.unproven, ledger.recordFor(.frame_handoff_to_window).state);
}

// The 2026-08-31 shape: the title depended on guest event signalling and
// nothing had ever shown that an event set on one thread wakes a waiter on
// another.
test "a component the guest depends on with no proof is the finding" {
    var ledger = Ledger{};
    ledger.noteProven(.host_graphics_device, 10, "rosette:self-exercise");
    ledger.noteUsed(.guest_event_signalling, 3_402_556_936);
    ledger.noteUsed(.guest_event_signalling, 3_500_000_000);

    try std.testing.expectEqual(
        Standing.used_unproven,
        ledger.standing(.guest_event_signalling),
    );
    try std.testing.expectEqual(
        Component.guest_event_signalling,
        ledger.firstFinding().?,
    );
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u8, 1), totals.used_unproven);
    try std.testing.expectEqual(@as(u8, 1), totals.essential_gaps);
    try std.testing.expectEqual(@as(u64, 3_402_556_936), ledger.recordFor(.guest_event_signalling).first_use_step);
    try std.testing.expectEqual(@as(u64, 2), ledger.recordFor(.guest_event_signalling).uses);
}

test "the ordering against first use is what is reported" {
    var ledger = Ledger{};
    ledger.noteProven(.guest_memory_aliasing, 50, "rosette:self-exercise");
    ledger.noteUsed(.guest_memory_aliasing, 100);
    try std.testing.expectEqual(
        Standing.proven_before_use,
        ledger.standing(.guest_memory_aliasing),
    );

    ledger.noteUsed(.command_processor_drain, 100);
    ledger.noteProven(.command_processor_drain, 150, "tracepoint:ExecutePacketType3");
    try std.testing.expectEqual(
        Standing.proven_after_use,
        ledger.standing(.command_processor_drain),
    );
    try std.testing.expectEqual(@as(u8, 1), ledger.summary().proven_after_use);
}

// A component proven at startup and proven again later was proven at startup.
// Letting the later proof win would erase the ordering the ledger exists for.
test "the first proof wins" {
    var ledger = Ledger{};
    ledger.noteProven(.host_surface_presentation, 10, "first");
    ledger.noteProven(.host_surface_presentation, 900, "second");
    const slot = ledger.recordFor(.host_surface_presentation);
    try std.testing.expectEqual(@as(u64, 10), slot.proven_step);
    try std.testing.expectEqualStrings("first", slot.prover);
}

test "a broken component outranks a merely unproven one" {
    var ledger = Ledger{};
    ledger.noteUsed(.guest_event_signalling, 100);
    ledger.noteFailed(.register_aperture_dispatch, 50, "rosette:aperture-probe");
    try std.testing.expectEqual(
        Component.register_aperture_dispatch,
        ledger.firstFinding().?,
    );
    try std.testing.expectEqual(@as(u8, 1), ledger.summary().broken);
}

// An unattempted proof is a hole in Rosette. Reporting it as a defect would
// send the next hour at the emulator.
test "an unprovable component is not a failure" {
    var ledger = Ledger{};
    ledger.noteUnprovable(.host_graphics_device, "no host device was created for this run");
    const slot = ledger.recordFor(.host_graphics_device);
    try std.testing.expectEqual(State.unprovable, slot.state);
    try std.testing.expectEqual(@as(u8, 0), ledger.summary().broken);
    try std.testing.expectEqualStrings(
        "no host device was created for this run",
        slot.obstacle,
    );
}

// The part that is actually fixable ahead of time: components Rosette could
// have exercised before the guest ran and did not.
test "components provable early but unproven are counted separately" {
    const ledger = Ledger{};
    const totals = ledger.summary();
    try std.testing.expect(totals.provable_early_but_unproven != 0);
    try std.testing.expect(totals.provable_early_but_unproven < component_count);
}

test "a fully proven ledger says so" {
    var ledger = Ledger{};
    for (allComponents()) |component| {
        ledger.noteProven(component, 10, "test");
        ledger.noteUsed(component, 20);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u8, component_count), totals.proven);
    try std.testing.expectEqual(@as(u8, 0), totals.used_unproven);
    try std.testing.expectEqual(@as(u8, 100), totals.readyPercent());
    try std.testing.expect(ledger.firstFinding() == null);
}

// `G1` reporting `detail=8` and naming nothing was the whole problem: the
// count was right and useless. The ledger has to be able to name the row.
test "the substrate gate's first blocker is named, in gate order" {
    var ledger = Ledger{};
    try std.testing.expectEqual(
        substrate_components[0],
        ledger.firstUnprovenSubstrate().?,
    );

    // Proving them in order walks the blocker forward.
    for (substrate_components[0..3]) |component| ledger.noteProven(component, 1, "test");
    try std.testing.expectEqual(
        substrate_components[3],
        ledger.firstUnprovenSubstrate().?,
    );

    for (substrate_components) |component| ledger.noteProven(component, 1, "test");
    try std.testing.expect(ledger.firstUnprovenSubstrate() == null);
    try std.testing.expect(ledger.substrateSummary().ready());
}

// The substrate set has to be answerable as a predicate, so a reader looking
// at a held gate is shown its own rows and not the whole ledger.
test "substrate membership matches the set the gate is judged against" {
    var counted: usize = 0;
    for (allComponents()) |component| {
        if (isSubstrate(component)) counted += 1;
    }
    try std.testing.expectEqual(substrate_components.len, counted);
    try std.testing.expect(isSubstrate(.guest_event_signalling));
    // Downstream graphics readiness is judged by later gates and must not be
    // reported as something holding the substrate closed.
    try std.testing.expect(!isSubstrate(.render_target_binding));
    try std.testing.expect(!isSubstrate(.frame_handoff_to_window));
}

// "The guest has not got there yet" and "this cannot be answered here" produce
// the same unproven count and opposite verdicts: waiting closes the first and
// never closes the second.
test "an unprovable substrate component is not an unproven one" {
    var ledger = Ledger{};
    for (substrate_components) |component| ledger.noteProven(component, 1, "test");
    try std.testing.expect(ledger.substrateSummary().ready());
    try std.testing.expect(!ledger.substrateSummary().awaitingFirstUse());

    var waiting = Ledger{};
    for (substrate_components[0 .. substrate_components.len - 1]) |component| {
        waiting.noteProven(component, 1, "test");
    }
    const pending = waiting.substrateSummary();
    try std.testing.expect(pending.awaitingFirstUse());
    try std.testing.expectEqual(@as(u8, 0), pending.unprovable);
    try std.testing.expectEqual(@as(u8, 1), pending.unproven);

    // The same shape with the last component declared unprovable is no longer
    // something waiting can close.
    waiting.noteUnprovable(substrate_components[substrate_components.len - 1], "no device here");
    const blocked = waiting.substrateSummary();
    try std.testing.expect(!blocked.awaitingFirstUse());
    try std.testing.expectEqual(@as(u8, 1), blocked.unprovable);
    try std.testing.expect(!blocked.ready());
}
