//! The events that must happen before other events, across every subsystem —
//! declared, so that a run can be told when something got ahead of what it
//! depended on instead of being left to infer it from a symptom.
//!
//! ## The problem this is for
//!
//! Under translation, nothing runs at the speed it was written for. The
//! emulator's threads keep their logical order and lose their timing, and the
//! places where correctness quietly depended on timing rather than on a lock
//! stop holding. That failure never announces itself: the dependant runs, gets
//! a zero or a stale pointer instead of the thing it needed, and carries on.
//! The symptom appears later, in a different subsystem, as an absence.
//!
//! A concrete one from 2026-08-30 exposed an observer mistake: twenty-four
//! calls entered the command processor, but all were classified by Xenia as
//! no-effect draws. Treating those calls as target-backed work produced a
//! false ordering violation. The contract therefore keeps raw draw entry for
//! context and judges only the post-classification `renderable_draw_issued`
//! event.
//!
//! ## Three outcomes, not two
//!
//! * **held** — the required event happened first, with room to spare.
//! * **raced** — the required event happened first, and by so little that the
//!   ordering was luck. This is the one worth having. An ordering that holds by
//!   two hundred steps on one run holds by minus two hundred on the next, and
//!   the run where it holds tells you nothing about the run where it does not.
//! * **violated** — the dependant happened and the requirement had not. On the
//!   platform the emulator was written for this could not occur, so it is
//!   always either a real inversion or an observer that is watching the wrong
//!   thing, and both are worth stopping for.
//!
//! ## What this package must never become
//!
//! It holds no state and observes nothing. It is the rule set: which event,
//! which dependant, how much slack counts as a race, and what a violation
//! means. The ledger that records occurrences lives in lib and is the only
//! thing allowed to say `violated`.

const std = @import("std");

/// Events that other events depend on. Deliberately spans subsystems: the
/// orderings that break under translation are mostly the ones that cross from
/// memory to threading to the GPU, and a per-subsystem rule set cannot see them.
pub const Event = enum(u8) {
    // ---- memory ------------------------------------------------------------
    guest_address_space_reserved,
    guest_page_protection_changed,
    write_watch_armed,
    write_watch_fired,

    // ---- threading ---------------------------------------------------------
    guest_thread_created,
    guest_wait_entered,
    guest_wait_returned,
    guest_object_signalled,

    // ---- kernel ------------------------------------------------------------
    kernel_export_resolved,
    kernel_export_called,
    interrupt_callback_registered,
    interrupt_dispatched,
    interrupt_entered_guest,
    interrupt_entered_host,

    // ---- gpu ---------------------------------------------------------------
    engines_initialized,
    ring_initialized,
    read_pointer_writeback_enabled,
    read_pointer_writeback_delivered,
    command_processor_running,
    write_pointer_published,
    ring_drained,
    register_programmed,
    render_target_programmed,
    draw_issued,
    renderable_draw_issued,
    swap_requested,
    swap_consumed,
    guest_output_refreshed,
    host_surface_painted,
    diagnostic_surface_painted,

    pub fn label(self: Event) []const u8 {
        return switch (self) {
            .guest_address_space_reserved => "guest address space reserved",
            .guest_page_protection_changed => "guest page protection changed",
            .write_watch_armed => "write watch armed",
            .write_watch_fired => "write watch fired",
            .guest_thread_created => "guest thread created",
            .guest_wait_entered => "guest wait entered",
            .guest_wait_returned => "guest wait returned",
            .guest_object_signalled => "guest object signalled",
            .kernel_export_resolved => "kernel export resolved",
            .kernel_export_called => "kernel export called",
            .interrupt_callback_registered => "title interrupt callback registered",
            .interrupt_dispatched => "graphics interrupt dispatched",
            .interrupt_entered_guest => "graphics interrupt entered guest code",
            .interrupt_entered_host => "graphics interrupt entered host callback",
            .engines_initialized => "GPU engines initialised",
            .ring_initialized => "command ring initialised",
            .read_pointer_writeback_enabled => "read-pointer write-back enabled",
            .read_pointer_writeback_delivered => "read-pointer write-back delivered",
            .command_processor_running => "command processor running",
            .write_pointer_published => "ring write pointer published",
            .ring_drained => "ring drained",
            .register_programmed => "GPU register programmed",
            .render_target_programmed => "render target programmed",
            .draw_issued => "draw issued",
            .renderable_draw_issued => "renderable draw issued",
            .swap_requested => "swap requested",
            .swap_consumed => "swap consumed",
            .guest_output_refreshed => "guest output refreshed",
            .host_surface_painted => "host surface painted",
            .diagnostic_surface_painted => "diagnostic surface painted",
        };
    }

    pub fn subsystem(self: Event) []const u8 {
        return switch (self) {
            .guest_address_space_reserved,
            .guest_page_protection_changed,
            .write_watch_armed,
            .write_watch_fired,
            => "memory",

            .guest_thread_created,
            .guest_wait_entered,
            .guest_wait_returned,
            .guest_object_signalled,
            => "threading",

            .kernel_export_resolved,
            .kernel_export_called,
            .interrupt_callback_registered,
            .interrupt_dispatched,
            .interrupt_entered_guest,
            .interrupt_entered_host,
            => "kernel",

            else => "gpu",
        };
    }
};

pub const event_count: usize = @typeInfo(Event).@"enum".fields.len;

/// How much the ordering matters, and therefore what to do about a violation.
pub const Strength = enum(u8) {
    /// The dependant cannot be correct without it. A violation means the work
    /// the dependant did was against state that did not exist yet.
    mandatory,
    /// The ordering is how the platform behaves and a violation is a strong
    /// signal that something is being observed wrongly rather than that the
    /// emulator is broken.
    expected,

    pub fn label(self: Strength) []const u8 {
        return switch (self) {
            .mandatory => "mandatory",
            .expected => "expected",
        };
    }
};

pub const Rule = struct {
    /// The event that must come first.
    required: Event,
    /// The event that depends on it.
    dependant: Event,
    strength: Strength,
    /// How close the two may be before the ordering is called luck rather than
    /// causality. Zero means any positive gap is fine — used where the two are
    /// genuinely adjacent in one call path.
    race_window_steps: u64,
    /// What a violation means, for the person reading it.
    consequence: []const u8,
};

/// The rule set.
///
/// Kept small and specific on purpose. Every rule here is one that has either
/// been violated in an observed run or is the direct precondition of one that
/// was. Raw observations that are useful for a retained lead-up but are not
/// safe prerequisites are events without a rule (for example `draw_issued`,
/// `interrupt_entered_host`, and `diagnostic_surface_painted`).
pub const rules = [_]Rule{
    .{
        .required = .render_target_programmed,
        .dependant = .renderable_draw_issued,
        .strength = .mandatory,
        .race_window_steps = 0,
        .consequence = "a target-backed draw was observed and no render target had been programmed, so the draw had nowhere to land. Raw IssueDraw entry is retained for diagnosis but cannot satisfy this rule because Xenia legitimately enters IssueDraw for no-effect draws",
    },
    .{
        .required = .interrupt_callback_registered,
        .dependant = .interrupt_entered_guest,
        .strength = .mandatory,
        .race_window_steps = 0,
        .consequence = "a graphics interrupt entered guest code before the title registered a callback, so it entered an address the title never named. The dispatch counters climb, the emulator reports success, and the title's own callback is still unreached",
    },
    .{
        .required = .ring_initialized,
        .dependant = .write_pointer_published,
        .strength = .mandatory,
        .race_window_steps = 0,
        .consequence = "a write pointer was published against a ring whose geometry had not been established, so the command processor was pointed at memory whose base and size it does not know",
    },
    .{
        .required = .command_processor_running,
        .dependant = .ring_drained,
        .strength = .mandatory,
        .race_window_steps = 0,
        .consequence = "the ring was drained by something other than a running command processor worker. Either the worker is not the drainer or the drain is being attributed to the wrong actor",
    },
    .{
        .required = .engines_initialized,
        .dependant = .ring_initialized,
        .strength = .expected,
        .race_window_steps = 1_000_000,
        .consequence = "a ring was initialised before the title turned the GPU on. On hardware the title always does these in order, so this is more likely an observer watching the wrong symbol than a title doing something unusual",
    },
    .{
        .required = .read_pointer_writeback_enabled,
        .dependant = .read_pointer_writeback_delivered,
        .strength = .mandatory,
        .race_window_steps = 0,
        .consequence = "a read-pointer write-back was delivered before the title asked for one, so the value landed at an address the title had not yet named",
    },
    .{
        .required = .guest_address_space_reserved,
        .dependant = .guest_page_protection_changed,
        .strength = .mandatory,
        .race_window_steps = 0,
        .consequence = "a guest page protection changed before the address space it belongs to was reserved, so the change applied to a mapping the guest does not own",
    },
    .{
        .required = .write_watch_armed,
        .dependant = .write_watch_fired,
        .strength = .mandatory,
        .race_window_steps = 0,
        .consequence = "a write watch fired without having been armed, so something is faulting on a page for a reason the watch layer did not cause and is now taking credit for",
    },
    .{
        .required = .kernel_export_resolved,
        .dependant = .kernel_export_called,
        .strength = .mandatory,
        .race_window_steps = 0,
        .consequence = "a kernel export was called before its address was resolved, so the call went to whatever the import slot held — which is the shape of a silent jump into unrelated code rather than of a missing export",
    },
    .{
        .required = .swap_requested,
        .dependant = .swap_consumed,
        .strength = .expected,
        .race_window_steps = 0,
        .consequence = "a swap was consumed that the title never requested, so a harness or a diagnostic produced it. A frame from that path proves the presentation stack and says nothing about the title",
    },
    .{
        .required = .guest_output_refreshed,
        .dependant = .host_surface_painted,
        .strength = .expected,
        .race_window_steps = 0,
        .consequence = "the host surface was painted without any guest output behind it. This is normal for a diagnostic frame and is only a finding when the run is claiming to display guest rendering",
    },
    .{
        .required = .guest_wait_entered,
        .dependant = .guest_wait_returned,
        .strength = .mandatory,
        .race_window_steps = 0,
        .consequence = "a wait returned that was never observed to be entered, so the wait ledger is missing entries and any conclusion about parked consumers drawn from it is unsupported",
    },
};

pub const rule_count: usize = rules.len;

/// What one rule's observations add up to.
pub const Standing = enum(u8) {
    /// Neither event has been seen. The rule says nothing yet.
    inactive,
    /// The required event happened and the dependant has not. Nothing to judge.
    awaiting_dependant,
    /// The dependant happened and the required event never has.
    violated,
    /// Both happened in order, and closely enough that the ordering was luck.
    raced,
    /// Both happened in order, with room to spare.
    held,

    pub fn label(self: Standing) []const u8 {
        return switch (self) {
            .inactive => "inactive",
            .awaiting_dependant => "awaiting",
            .violated => "VIOLATED",
            .raced => "RACED",
            .held => "held",
        };
    }

    pub fn actionable(self: Standing) bool {
        return self == .violated or self == .raced;
    }

    pub fn describe(self: Standing) []const u8 {
        return switch (self) {
            .inactive => "neither event has been observed, so this rule is not yet saying anything",
            .awaiting_dependant => "the required event happened and nothing has depended on it yet",
            .violated => "the dependant ran and its requirement had not. On the platform this emulator was written for that cannot happen, so it is either a real inversion or an observer watching the wrong thing — and both are worth stopping for",
            .raced => "the ordering held, and by so little that it was luck. The run where it holds says nothing about the run where it does not, and this is the class of defect that reproduces once in twenty",
            .held => "the requirement was established well before anything depended on it",
        };
    }
};

/// Decide a standing from two observations. Kept here so the race threshold and
/// the sentence that explains it stay in one place.
pub fn standingOf(
    rule: Rule,
    required_seen: bool,
    required_step: u64,
    dependant_seen: bool,
    dependant_step: u64,
) Standing {
    if (!dependant_seen) {
        if (!required_seen) return .inactive;
        return .awaiting_dependant;
    }
    if (!required_seen) return .violated;
    if (dependant_step < required_step) return .violated;
    const gap = dependant_step - required_step;
    if (gap <= rule.race_window_steps) return .raced;
    return .held;
}

test "every rule names a consequence and orders two different events" {
    for (rules) |rule| {
        try std.testing.expect(rule.consequence.len != 0);
        try std.testing.expect(rule.required != rule.dependant);
    }
}

test "a dependant without its requirement is a violation" {
    const rule = rules[0];
    try std.testing.expectEqual(
        Standing.violated,
        standingOf(rule, false, 0, true, 3_399_870_297),
    );
}

// The 2026-08-30 reading: twenty-four raw IssueDraw calls entered the command
// processor and the render target cache was never updated. Raw IssueDraw is
// retained as context, but Xenia also uses it for no-effect draws. Only a
// classified renderable draw is allowed to make the target-order rule fire.
test "only a classified renderable draw can trigger the target-order rule" {
    const rule = rules[0];
    try std.testing.expectEqual(Event.render_target_programmed, rule.required);
    try std.testing.expectEqual(Event.renderable_draw_issued, rule.dependant);
    try std.testing.expectEqual(Strength.mandatory, rule.strength);
    try std.testing.expect(
        standingOf(rule, false, 0, true, 1).actionable(),
    );
}

test "an ordering that held by less than the race window is luck" {
    const rule = Rule{
        .required = .engines_initialized,
        .dependant = .ring_initialized,
        .strength = .expected,
        .race_window_steps = 1_000,
        .consequence = "",
    };
    try std.testing.expectEqual(Standing.raced, standingOf(rule, true, 100, true, 600));
    try std.testing.expectEqual(Standing.held, standingOf(rule, true, 100, true, 5_000));
}

test "a rule with nothing observed says nothing" {
    const rule = rules[0];
    try std.testing.expectEqual(Standing.inactive, standingOf(rule, false, 0, false, 0));
    try std.testing.expectEqual(Standing.awaiting_dependant, standingOf(rule, true, 10, false, 0));
    try std.testing.expect(!Standing.inactive.actionable());
}

test "a dependant observed before its requirement is a violation even when both happened" {
    const rule = rules[2];
    try std.testing.expectEqual(
        Standing.violated,
        standingOf(rule, true, 500, true, 100),
    );
}

test "every event names a subsystem" {
    inline for (@typeInfo(Event).@"enum".fields) |field| {
        const event: Event = @enumFromInt(field.value);
        try std.testing.expect(event.label().len != 0);
        try std.testing.expect(event.subsystem().len != 0);
    }
}
