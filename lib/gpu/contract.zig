//! GRAPHICS CONTRACT — the preconditions a frame needs, each with an owner.
//!
//! On Windows a large amount of graphics bring-up is implicit: the loader, the
//! display driver and the kernel have already established state by the time a
//! title's first `Present` runs, so nothing in the title or the emulator has to
//! ask for it. On macOS none of that happened, and the failure it produces is
//! not an error — it is an *absence*. The run reaches a rung of the pipeline
//! ladder and simply stops, and every counter above the frontier reads zero
//! because it is downstream, not because it failed.
//!
//! A ladder alone cannot say what to do about that. "guest VdSwap export
//! entered = 0" is a consequence; the question is which precondition is unmet
//! and, decisively, **who is allowed to meet it**. This module is that list.
//!
//! ## Owners, and why the distinction is the whole point
//!
//! Every clause names an owner, and the owner decides what satisfying it means:
//!
//!   * `rosette_harness` — Rosette owns the resource outright (the window
//!     surface, the presenter, capability negotiation, the host synchronisation
//!     primitives the guest's waits are built on). Rosette satisfying these is
//!     not forcing anything: it is supplying what the platform would have
//!     supplied. These are the clauses a harness exists for.
//!   * `emulator_host` — the emulator owns it, and Rosette can only observe.
//!     Rosette may report an unmet clause here in detail, and must not write
//!     the state itself; doing so would hide the defect being hunted.
//!   * `guest_title` — the title owns it. `VdSwap` is entered because the
//!     title decided to present a frame. A swap Rosette manufactures is a frame
//!     the title did not draw, and it would retire the one signal that says the
//!     title is stuck. **Never satisfiable by the harness, by construction.**
//!
//! `satisfy` enforces that: a clause owned by the guest cannot be marked
//! satisfied by harness action, and the attempt is counted rather than silently
//! ignored. That is the mechanism behind "never force behaviour" — not a
//! convention someone has to remember.
//!
//! ## What the report is for
//!
//! The frontier is the first unmet *required* clause in order. Reading its
//! owner tells the operator immediately whether the next move is to write
//! Rosette code (`rosette_harness`), to fix the emulator (`emulator_host`), or
//! to find out what the title is waiting for (`guest_title`) — three different
//! days of work that the ladder alone cannot distinguish.

const std = @import("std");

pub const Owner = enum {
    /// Rosette owns the resource; the harness may and should satisfy it.
    rosette_harness,
    /// The emulator owns it. Observe and report; never write it.
    emulator_host,
    /// The title owns it. Satisfying it from outside would be a fabricated
    /// frame, so the contract refuses.
    guest_title,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .rosette_harness => "rosette_harness",
            .emulator_host => "emulator_host",
            .guest_title => "guest_title",
        };
    }

    /// Whether the harness is permitted to satisfy a clause with this owner.
    pub fn harnessMaySatisfy(self: Owner) bool {
        return self == .rosette_harness;
    }
};

/// The clauses, in dependency order. The order is the ladder: the first unmet
/// required clause is the frontier and everything after it is a consequence.
pub const Clause = enum(u8) {
    // ---- Host platform surface. Rosette's own, and the reason a harness
    // exists: on Windows the equivalent state is established before the title
    // runs, so nothing asks for it.
    native_window_surface,
    native_presenter_bound,
    backend_instance_negotiated,
    physical_adapter_negotiated,
    presentation_capability_negotiated,
    host_visible_memory_negotiated,
    /// A guest wait must consume the signal it waits on. Rosette hosts the
    /// primitives the emulator's events are built from, so when a set always
    /// finds its event already signalled the waiter never blocks and every
    /// producer/consumer handshake above this line free-runs.
    wait_primitives_consume_signals,

    // ---- Emulator bring-up. Observed, never written.
    gpu_engines_initialised,
    interrupt_callback_registered,
    interrupt_callback_dispatched,
    ring_buffer_initialised,

    // ---- Title behaviour. Never satisfiable from outside.
    guest_ring_payload_published,
    guest_write_pointer_advanced,
    guest_pm4_consumed,
    guest_swap_entered,
    swap_packet_encoded,
    swap_consumed_by_command_processor,
    presenter_output_refreshed,

    pub fn owner(self: Clause) Owner {
        return switch (self) {
            .native_window_surface,
            .native_presenter_bound,
            .backend_instance_negotiated,
            .physical_adapter_negotiated,
            .presentation_capability_negotiated,
            .host_visible_memory_negotiated,
            .wait_primitives_consume_signals,
            => .rosette_harness,

            .gpu_engines_initialised,
            .interrupt_callback_registered,
            .interrupt_callback_dispatched,
            .ring_buffer_initialised,
            .swap_consumed_by_command_processor,
            .presenter_output_refreshed,
            => .emulator_host,

            .guest_ring_payload_published,
            .guest_write_pointer_advanced,
            .guest_pm4_consumed,
            .guest_swap_entered,
            .swap_packet_encoded,
            => .guest_title,
        };
    }

    /// Optional clauses do not block the frontier. A title that never uses a
    /// system command buffer is not stuck; treating an unused capability as a
    /// missing precondition is how a ladder points at the wrong rung.
    pub fn required(self: Clause) bool {
        return switch (self) {
            .host_visible_memory_negotiated => false,
            else => true,
        };
    }

    pub fn label(self: Clause) []const u8 {
        return switch (self) {
            .native_window_surface => "native window surface exists",
            .native_presenter_bound => "presenter bound to the surface",
            .backend_instance_negotiated => "graphics backend instance negotiated",
            .physical_adapter_negotiated => "physical adapter negotiated",
            .presentation_capability_negotiated => "presentation capability negotiated",
            .host_visible_memory_negotiated => "host-visible memory negotiated (optional)",
            .wait_primitives_consume_signals => "guest waits consume the signals they wait on",
            .gpu_engines_initialised => "VdInitializeEngines",
            .interrupt_callback_registered => "VdSetGraphicsInterruptCallback",
            .interrupt_callback_dispatched => "graphics interrupt callback dispatched",
            .ring_buffer_initialised => "VdInitializeRingBuffer",
            .guest_ring_payload_published => "guest ring payload published",
            .guest_write_pointer_advanced => "guest advanced CP_RB_WPTR",
            .guest_pm4_consumed => "PM4 packets consumed",
            .guest_swap_entered => "guest VdSwap export entered",
            .swap_packet_encoded => "guest XE_SWAP packet encoded",
            .swap_consumed_by_command_processor => "XE_SWAP consumed by the command processor",
            .presenter_output_refreshed => "presenter output refreshed",
        };
    }

    /// What to do when this clause is the frontier. Written as the next action,
    /// not as a restatement of the clause, because a frontier that only repeats
    /// itself is what the ladder already did.
    pub fn guidance(self: Clause) []const u8 {
        return switch (self) {
            .native_window_surface => "Rosette owns this: create the window surface before the emulator asks for one. Nothing above this rung can run",
            .native_presenter_bound => "Rosette owns this: bind the presenter to the surface. A presenter with no surface silently accepts frames and drops them",
            .backend_instance_negotiated => "Rosette owns this: the backend instance is the first capability the emulator asks for and the one it cannot proceed without",
            .physical_adapter_negotiated => "Rosette owns this: without an adapter the emulator's device creation degrades and every later capability is negotiated against nothing",
            .presentation_capability_negotiated => "Rosette owns this: presentation is what turns a rendered image into a frame on screen",
            .host_visible_memory_negotiated => "optional: absence costs a copy, not a frame",
            .wait_primitives_consume_signals => "Rosette owns this. If every set finds its event already signalled, waits are not consuming signals: the waiter never blocks, so a producer/consumer loop spins without progress and no rung above this one can advance. This looks like a GPU stall and is not one",
            .gpu_engines_initialised => "emulator: the title called nothing yet, or the export is unbound. Check import binding before anything graphical",
            .interrupt_callback_registered => "emulator: the title registers this before it will submit. Its absence means the title has not reached its graphics init",
            .interrupt_callback_dispatched => "emulator: registered but never fired. The vblank source is not reaching the callback",
            .ring_buffer_initialised => "emulator: the ring geometry was never established, so there is nowhere to submit",
            .guest_ring_payload_published => "title: the ring is configured and empty. The title has not produced a command batch — look at what it is doing instead",
            .guest_write_pointer_advanced => "title: a batch was written but never published. Look at the submitting thread",
            .guest_pm4_consumed => "emulator/title boundary: the guest published and the command processor has not drained it",
            .guest_swap_entered => "title: the title has not decided to present. A swap synthesised here would be a frame it did not draw, so the contract refuses to satisfy this. Find what the title is waiting for",
            .swap_packet_encoded => "title: VdSwap ran without encoding a packet",
            .swap_consumed_by_command_processor => "emulator: the packet was encoded and the command processor did not decode it",
            .presenter_output_refreshed => "emulator: everything upstream happened and the presenter did not refresh",
        };
    }
};

pub const clause_count = @typeInfo(Clause).@"enum".fields.len;

pub const State = enum {
    unmet,
    /// Satisfied by the guest or emulator doing the real thing.
    satisfied_authentically,
    /// Satisfied by Rosette supplying a resource it owns.
    satisfied_by_harness,
    /// Supplied by the harness for a clause it does *not* own, deliberately and
    /// under the substitution policy. Never reachable through `satisfy`: the
    /// caller has to ask for it by name, and it can never be counted as met by
    /// anything that asks whether the pipeline works.
    substituted_by_harness,

    pub fn met(self: State) bool {
        return self != .unmet;
    }

    /// Whether the thing that owns this clause actually did it. The question
    /// every downstream counter is implicitly asking, and the reason
    /// substitution is a third state rather than a flag on the second.
    pub fn authentic(self: State) bool {
        return self == .satisfied_authentically;
    }

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .unmet => "UNMET",
            .satisfied_authentically => "authentic",
            .satisfied_by_harness => "harness",
            .substituted_by_harness => "SUBSTITUTED",
        };
    }
};

const Entry = struct {
    state: State = .unmet,
    step: u64 = 0,
    observations: u32 = 0,
};

pub const Frontier = struct {
    clause: ?Clause,
    met_required: u32,
    required_total: u32,
};

pub const Ledger = struct {
    entries: [clause_count]Entry = [_]Entry{.{}} ** clause_count,
    /// Attempts to satisfy a clause the harness does not own. Counted rather
    /// than ignored: a harness quietly declining to do something is how a
    /// missing capability becomes invisible.
    refused_harness_satisfactions: u64 = 0,
    last_refused: ?Clause = null,
    /// Clauses the harness deliberately stood in for. Kept apart from the
    /// refusals above: a refusal is the rule working, a substitution is the
    /// rule being consciously overridden, and a run needs to be able to report
    /// which of the two happened.
    substitutions: u64 = 0,
    last_substituted: ?Clause = null,

    /// Record that a clause is genuinely met, by whoever legitimately met it.
    pub fn observe(self: *Ledger, clause: Clause, step: u64) void {
        const entry = &self.entries[@intFromEnum(clause)];
        entry.observations +|= 1;
        if (entry.state.met()) return;
        entry.state = .satisfied_authentically;
        entry.step = step;
    }

    /// Rosette supplying a resource it owns. Refuses — and counts the refusal —
    /// for any clause it does not own, which is the mechanical guarantee that
    /// the harness never fabricates guest behaviour.
    pub fn satisfy(self: *Ledger, clause: Clause, step: u64) bool {
        if (!clause.owner().harnessMaySatisfy()) {
            self.refused_harness_satisfactions +|= 1;
            self.last_refused = clause;
            return false;
        }
        const entry = &self.entries[@intFromEnum(clause)];
        entry.observations +|= 1;
        if (entry.state.met()) return true;
        entry.state = .satisfied_by_harness;
        entry.step = step;
        return true;
    }

    /// Supply a clause the harness does not own, deliberately.
    ///
    /// This is the escape hatch `satisfy` refuses to be, and the difference is
    /// entirely in what it records. The danger of a fabricated swap was never
    /// the fabrication — it was that the resulting counter looked exactly like
    /// a real one, so every subsystem downstream reported progress nobody made.
    /// A clause marked `substituted_by_harness` can never answer yes to
    /// `authenticFrontier`, so that confusion is unavailable by construction
    /// rather than by anyone remembering.
    ///
    /// Refuses the clauses the harness *does* own: routing those through here
    /// would tar ordinary harness work with a substitution label and make the
    /// report claim the run was faked when it was not.
    pub fn substitute(self: *Ledger, clause: Clause, step: u64) bool {
        if (clause.owner().harnessMaySatisfy()) return false;
        const entry = &self.entries[@intFromEnum(clause)];
        entry.observations +|= 1;
        self.substitutions +|= 1;
        self.last_substituted = clause;
        // An authentic observation is never downgraded. If the title really did
        // present, that fact outranks anything the harness did earlier.
        if (entry.state.authentic()) return true;
        entry.state = .substituted_by_harness;
        if (entry.step == 0) entry.step = step;
        return true;
    }

    pub fn state(self: *const Ledger, clause: Clause) State {
        return self.entries[@intFromEnum(clause)].state;
    }

    /// The frontier counting only clauses their own owner satisfied. The
    /// honest ladder: substituted clauses do not advance it, so a run driven by
    /// the harness still reports the rung the title never reached.
    pub fn authenticFrontier(self: *const Ledger) Frontier {
        var first: ?Clause = null;
        var met_required: u32 = 0;
        var required_total: u32 = 0;
        inline for (@typeInfo(Clause).@"enum".fields) |field| {
            const clause: Clause = @enumFromInt(field.value);
            if (clause.required()) {
                required_total += 1;
                // Harness-owned clauses are authentic when the harness supplies
                // them: supplying a window surface is the harness doing its own
                // job, not standing in for anyone.
                const honest = switch (self.state(clause)) {
                    .satisfied_authentically => true,
                    .satisfied_by_harness => clause.owner().harnessMaySatisfy(),
                    else => false,
                };
                if (honest) {
                    met_required += 1;
                } else if (first == null) {
                    first = clause;
                }
            }
        }
        return .{ .clause = first, .met_required = met_required, .required_total = required_total };
    }

    pub fn met(self: *const Ledger, clause: Clause) bool {
        return self.state(clause).met();
    }

    /// First unmet required clause in dependency order, plus the tally. Optional
    /// clauses are counted separately and never become the frontier.
    pub fn frontier(self: *const Ledger) Frontier {
        var first: ?Clause = null;
        var met_required: u32 = 0;
        var required_total: u32 = 0;
        inline for (@typeInfo(Clause).@"enum".fields) |field| {
            const clause: Clause = @enumFromInt(field.value);
            if (clause.required()) {
                required_total += 1;
                if (self.met(clause)) {
                    met_required += 1;
                } else if (first == null) {
                    first = clause;
                }
            }
        }
        return .{ .clause = first, .met_required = met_required, .required_total = required_total };
    }

    /// Clauses the harness owns and has not supplied. This is the actionable
    /// list: everything here is work Rosette can legitimately do, and nothing
    /// here requires the title or the emulator to change.
    pub fn unmetHarnessClauses(self: *const Ledger, out: []Clause) []Clause {
        var count: usize = 0;
        inline for (@typeInfo(Clause).@"enum".fields) |field| {
            const clause: Clause = @enumFromInt(field.value);
            if (count < out.len and clause.owner() == .rosette_harness and !self.met(clause)) {
                out[count] = clause;
                count += 1;
            }
        }
        return out[0..count];
    }
};

test "the frontier is the first unmet required clause, and optional ones never block" {
    var ledger = Ledger{};
    // Nothing met yet: the very first clause is the frontier.
    try std.testing.expectEqual(Clause.native_window_surface, ledger.frontier().clause.?);

    // Satisfy every harness clause except the optional one.
    inline for (@typeInfo(Clause).@"enum".fields) |field| {
        const clause: Clause = @enumFromInt(field.value);
        if (clause.owner() == .rosette_harness and clause != .host_visible_memory_negotiated) {
            try std.testing.expect(ledger.satisfy(clause, 10));
        }
    }
    // The optional clause is still unmet and must not be the frontier.
    try std.testing.expect(!ledger.met(.host_visible_memory_negotiated));
    try std.testing.expectEqual(Clause.gpu_engines_initialised, ledger.frontier().clause.?);
}

// The whole reason the owner field exists. A harness that can satisfy
// `guest_swap_entered` is a harness that manufactures frames the title never
// drew, and the run would then report success while the actual defect — the
// title never deciding to present — went unlogged forever.
test "the harness cannot satisfy a clause the title owns" {
    var ledger = Ledger{};
    try std.testing.expect(!ledger.satisfy(.guest_swap_entered, 10));
    try std.testing.expect(!ledger.met(.guest_swap_entered));
    try std.testing.expectEqual(@as(u64, 1), ledger.refused_harness_satisfactions);
    try std.testing.expectEqual(Clause.guest_swap_entered, ledger.last_refused.?);

    // Nor one the emulator owns: writing that state would hide the defect.
    try std.testing.expect(!ledger.satisfy(.ring_buffer_initialised, 11));
    try std.testing.expectEqual(@as(u64, 2), ledger.refused_harness_satisfactions);

    // Observation is always allowed — the title really doing it is the point.
    ledger.observe(.guest_swap_entered, 12);
    try std.testing.expectEqual(State.satisfied_authentically, ledger.state(.guest_swap_entered));
}

test "harness and authentic satisfaction stay distinguishable" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.satisfy(.native_window_surface, 5));
    try std.testing.expectEqual(State.satisfied_by_harness, ledger.state(.native_window_surface));

    ledger.observe(.gpu_engines_initialised, 6);
    try std.testing.expectEqual(State.satisfied_authentically, ledger.state(.gpu_engines_initialised));

    // A later authentic observation does not downgrade a harness-supplied
    // clause to unmet, and a harness supply does not overwrite an authentic
    // one: the first true statement wins and the run can still tell them apart.
    ledger.observe(.native_window_surface, 7);
    try std.testing.expectEqual(State.satisfied_by_harness, ledger.state(.native_window_surface));
    try std.testing.expectEqual(@as(u64, 5), ledger.entries[@intFromEnum(Clause.native_window_surface)].step);
}

// The run this was written for: every rung through PM4 consumption reached,
// `guest VdSwap export entered` at zero, and the operator with no way to tell
// whether that was Rosette's job. The owner answers it in one word.
test "the observed run resolves to a guest-owned frontier with no harness work left" {
    var ledger = Ledger{};
    const reached = [_]Clause{
        .native_window_surface,        .native_presenter_bound,
        .backend_instance_negotiated,  .physical_adapter_negotiated,
        .presentation_capability_negotiated, .wait_primitives_consume_signals,
        .gpu_engines_initialised,      .interrupt_callback_registered,
        .interrupt_callback_dispatched, .ring_buffer_initialised,
        .guest_ring_payload_published, .guest_write_pointer_advanced,
        .guest_pm4_consumed,
    };
    for (reached) |clause| ledger.observe(clause, 100);

    const frontier = ledger.frontier();
    try std.testing.expectEqual(Clause.guest_swap_entered, frontier.clause.?);
    try std.testing.expectEqual(Owner.guest_title, frontier.clause.?.owner());
    try std.testing.expect(std.mem.indexOf(u8, frontier.clause.?.guidance(), "contract refuses") != null);

    // And nothing *required* is left on Rosette's side, which is the fact that
    // stops the operator writing harness code that cannot help. The observed
    // run really was missing host-visible memory, and that clause is optional
    // precisely so a missing copy optimisation cannot masquerade as the reason
    // there is no frame.
    var buffer: [clause_count]Clause = undefined;
    const outstanding = ledger.unmetHarnessClauses(&buffer);
    try std.testing.expectEqual(@as(usize, 1), outstanding.len);
    try std.testing.expectEqual(Clause.host_visible_memory_negotiated, outstanding[0]);
    try std.testing.expect(!outstanding[0].required());
    for (outstanding) |clause| try std.testing.expect(!clause.required());
}

// Substitution exists so the harness can drive the rest of the pipeline while
// the real defect stays open. The whole safety argument is that it cannot be
// mistaken for the title having done the thing.
test "a substituted clause advances the ladder and never the authentic one" {
    var ledger = Ledger{};
    const reached = [_]Clause{
        .native_window_surface,              .native_presenter_bound,
        .backend_instance_negotiated,        .physical_adapter_negotiated,
        .presentation_capability_negotiated, .wait_primitives_consume_signals,
        .gpu_engines_initialised,            .interrupt_callback_registered,
        .interrupt_callback_dispatched,      .ring_buffer_initialised,
        .guest_ring_payload_published,       .guest_write_pointer_advanced,
        .guest_pm4_consumed,
    };
    for (reached) |clause| ledger.observe(clause, 100);
    try std.testing.expectEqual(Clause.guest_swap_entered, ledger.frontier().clause.?);

    try std.testing.expect(ledger.substitute(.guest_swap_entered, 200));
    try std.testing.expectEqual(State.substituted_by_harness, ledger.state(.guest_swap_entered));
    try std.testing.expect(ledger.met(.guest_swap_entered));
    try std.testing.expect(!ledger.state(.guest_swap_entered).authentic());

    // The plain frontier moves on, so downstream work can proceed...
    try std.testing.expectEqual(Clause.swap_packet_encoded, ledger.frontier().clause.?);
    // ...and the honest one does not, so the report still names the rung the
    // title never reached.
    try std.testing.expectEqual(Clause.guest_swap_entered, ledger.authenticFrontier().clause.?);
    try std.testing.expectEqual(@as(u64, 1), ledger.substitutions);
    try std.testing.expectEqual(Clause.guest_swap_entered, ledger.last_substituted.?);
}

// `satisfy` still refuses, and routing a harness-owned clause through
// `substitute` would libel ordinary harness work as fabrication.
test "substitution neither replaces the refusal rule nor absorbs harness work" {
    var ledger = Ledger{};
    try std.testing.expect(!ledger.satisfy(.guest_swap_entered, 1));
    try std.testing.expectEqual(@as(u64, 1), ledger.refused_harness_satisfactions);
    try std.testing.expectEqual(@as(u64, 0), ledger.substitutions);

    try std.testing.expect(!ledger.substitute(.native_window_surface, 2));
    try std.testing.expectEqual(@as(u64, 0), ledger.substitutions);
    try std.testing.expectEqual(State.unmet, ledger.state(.native_window_surface));

    // A harness-supplied window surface is the harness doing its own job, and
    // the authentic ladder counts it.
    try std.testing.expect(ledger.satisfy(.native_window_surface, 3));
    try std.testing.expect(ledger.authenticFrontier().met_required >= 1);
}

// If the title recovers, its own behaviour outranks anything supplied earlier —
// otherwise a single early substitution would mislabel the rest of the run.
test "an authentic observation is never downgraded by a later substitution" {
    var ledger = Ledger{};
    ledger.observe(.guest_swap_entered, 10);
    try std.testing.expect(ledger.substitute(.guest_swap_entered, 20));
    try std.testing.expectEqual(State.satisfied_authentically, ledger.state(.guest_swap_entered));
    try std.testing.expect(ledger.state(.guest_swap_entered).authentic());
    // The attempt is still counted: the run needs to know it happened.
    try std.testing.expectEqual(@as(u64, 1), ledger.substitutions);
}

test "an unmet harness clause is listed so the actionable work is explicit" {
    var ledger = Ledger{};
    ledger.observe(.gpu_engines_initialised, 1);
    var buffer: [clause_count]Clause = undefined;
    const pending = ledger.unmetHarnessClauses(&buffer);
    // Every harness clause is outstanding, in dependency order.
    try std.testing.expectEqual(Clause.native_window_surface, pending[0]);
    try std.testing.expect(pending.len >= 6);
    for (pending) |clause| try std.testing.expectEqual(Owner.rosette_harness, clause.owner());
}
