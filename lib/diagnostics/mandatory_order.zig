//! Records when each declared event first and last happened, judges every
//! ordering rule against those observations, and — when a rule is violated —
//! prints the events that led up to it.
//!
//! ## The snapshot is the point
//!
//! A violation on its own names two events and a gap. What a reader actually
//! needs is what the run was doing when the dependant ran without its
//! requirement, and that has never been recoverable: by the time a report says
//! "twenty-four draws, no render target", the ordering of the hundred events
//! around them is a hundred million steps in the past and nothing kept them.
//!
//! So a bounded ring of every observed event is retained at all times and
//! costs nothing to keep — one array slot per event, no allocation, no
//! formatting. It is silent until a rule turns actionable, and then the window
//! is printed once, in order, with steps and threads. That is the whole design:
//! **retain always, report only at a finding**, so the log gains a region of
//! detail exactly where the run went wrong and nowhere else.
//!
//! ## Why a race is reported as loudly as a violation
//!
//! An ordering that held by two hundred steps on this run holds by minus two
//! hundred on the next. Under translation nothing keeps the timing it was
//! written for, so every ordering that is close is a coin flip that happened to
//! land — and a run where it lands right proves nothing about the run where it
//! does not. Reporting only violations means the defect is invisible until the
//! day it is not reproducible.
//!
//! ## What it never does
//!
//! It does not order anything. It has no way to make an event wait for another
//! and would be wrong to have one: a harness that enforced an ordering the
//! emulator did not would hide exactly the defect it was built to find.

const std = @import("std");
const contract = @import("rosette_mandatory_order_contract");

pub const Event = contract.Event;
pub const Rule = contract.Rule;
pub const Strength = contract.Strength;
pub const Standing = contract.Standing;
pub const rules = contract.rules;
pub const rule_count = contract.rule_count;
pub const event_count = contract.event_count;

/// Events retained for the lead-up window. Sized so a violation's context
/// spans the interesting part of one subsystem's activity without the ring
/// becoming a second log: at the observed rate the graphics path produces a few
/// hundred events in a whole run, so this holds most of it.
pub const window_capacity: usize = 48;

pub const Occurrence = struct {
    event: Event = .guest_address_space_reserved,
    step: u64 = 0,
    thread: u64 = 0,
    /// Whatever the observer had to hand: an address, a handle, a count. Kept
    /// untyped because its meaning belongs to the event, not to this module.
    detail: u64 = 0,
    valid: bool = false,
};

const EventState = struct {
    count: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    first_thread: u64 = 0,
    first_detail: u64 = 0,

    fn seen(self: EventState) bool {
        return self.count != 0;
    }
};

pub const RuleReading = struct {
    rule: Rule,
    standing: Standing = .inactive,
    required_step: u64 = 0,
    dependant_step: u64 = 0,
    /// Positive when the ordering held, and the number that decides whether it
    /// held by design or by luck.
    gap_steps: u64 = 0,
    dependant_count: u64 = 0,
    required_count: u64 = 0,
};

pub const Summary = struct {
    active: u8 = 0,
    held: u8 = 0,
    raced: u8 = 0,
    violated: u8 = 0,
    /// Violations of `mandatory` rules. The ones that stop a run being
    /// meaningful rather than merely suspicious.
    mandatory_violations: u8 = 0,

    pub fn actionable(self: Summary) u8 {
        return self.raced + self.violated;
    }

    pub fn describe(self: Summary) []const u8 {
        if (self.active == 0) {
            return "no ordering rule has seen both of its events, so nothing here is judging anything yet";
        }
        if (self.mandatory_violations != 0) {
            return "an event ran before something it cannot be correct without. Whatever it produced was produced against state that did not exist, so its own counters are worse than useless — they say the work happened";
        }
        if (self.violated != 0) {
            return "an ordering the platform guarantees did not hold. That is more often an observer watching the wrong symbol than an emulator doing something impossible, and either way the reading below it cannot be trusted";
        }
        if (self.raced != 0) {
            return "every ordering held and at least one held by so little that it was luck. Under translation nothing keeps the timing it was written for, so a close ordering is a coin flip that landed — expect the opposite result on a run that is scheduled differently";
        }
        return "every ordering that has become judgeable held with room to spare";
    }
};

pub const Ledger = struct {
    events: [event_count]EventState = [_]EventState{.{}} ** event_count,
    window: [window_capacity]Occurrence = [_]Occurrence{.{}} ** window_capacity,
    cursor: usize = 0,
    filled: usize = 0,
    /// Total occurrences offered, so a reader knows how much of the run the
    /// retained window covers.
    total: u64 = 0,
    /// Rules already reported, so a standing violation is printed at the
    /// checkpoint it becomes true and not at every checkpoint afterwards.
    reported: [rule_count]bool = [_]bool{false} ** rule_count,

    pub fn observe(self: *Ledger, event: Event, step: u64, thread: u64, detail: u64) void {
        const slot = &self.events[@intFromEnum(event)];
        if (slot.count == 0) {
            slot.first_step = step;
            slot.first_thread = thread;
            slot.first_detail = detail;
        }
        slot.count +|= 1;
        if (step > slot.last_step) slot.last_step = step;

        self.total +|= 1;
        self.window[self.cursor] = .{
            .event = event,
            .step = step,
            .thread = thread,
            .detail = detail,
            .valid = true,
        };
        self.cursor = (self.cursor + 1) % window_capacity;
        if (self.filled < window_capacity) self.filled += 1;
    }

    /// Record an event only the first time it happens.
    ///
    /// Some of these fire constantly — a page protection change, a register
    /// write — and every occurrence after the first tells the ordering rules
    /// nothing while pushing the events that matter out of the lead-up window.
    /// The count still advances, so "how many" stays answerable.
    pub fn observeOnce(self: *Ledger, event: Event, step: u64, thread: u64, detail: u64) void {
        if (self.events[@intFromEnum(event)].count != 0) {
            self.events[@intFromEnum(event)].count +|= 1;
            if (step > self.events[@intFromEnum(event)].last_step) {
                self.events[@intFromEnum(event)].last_step = step;
            }
            return;
        }
        self.observe(event, step, thread, detail);
    }

    pub fn seen(self: *const Ledger, event: Event) bool {
        return self.events[@intFromEnum(event)].seen();
    }

    pub fn firstStep(self: *const Ledger, event: Event) u64 {
        return self.events[@intFromEnum(event)].first_step;
    }

    pub fn count(self: *const Ledger, event: Event) u64 {
        return self.events[@intFromEnum(event)].count;
    }

    pub fn reading(self: *const Ledger, index: usize) RuleReading {
        const rule = rules[index];
        const required = self.events[@intFromEnum(rule.required)];
        const dependant = self.events[@intFromEnum(rule.dependant)];
        var out = RuleReading{
            .rule = rule,
            .required_step = required.first_step,
            .dependant_step = dependant.first_step,
            .required_count = required.count,
            .dependant_count = dependant.count,
        };
        out.standing = contract.standingOf(
            rule,
            required.seen(),
            required.first_step,
            dependant.seen(),
            dependant.first_step,
        );
        if (dependant.seen() and required.seen() and dependant.first_step >= required.first_step) {
            out.gap_steps = dependant.first_step - required.first_step;
        }
        return out;
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{};
        var index: usize = 0;
        while (index < rule_count) : (index += 1) {
            const found = self.reading(index);
            switch (found.standing) {
                .inactive, .awaiting_dependant => continue,
                .held => out.held += 1,
                .raced => out.raced += 1,
                .violated => {
                    out.violated += 1;
                    if (found.rule.strength == .mandatory) out.mandatory_violations += 1;
                },
            }
            out.active += 1;
        }
        return out;
    }

    /// The rule a reader should act on: a mandatory violation first, then any
    /// violation, then a race. One row, not twelve.
    pub fn firstFinding(self: *const Ledger) ?RuleReading {
        var best: ?RuleReading = null;
        var index: usize = 0;
        while (index < rule_count) : (index += 1) {
            const found = self.reading(index);
            if (!found.standing.actionable()) continue;
            const held = best orelse {
                best = found;
                continue;
            };
            if (rank(found) < rank(held)) best = found;
        }
        return best;
    }

    /// Whether this rule's finding is new since the last time it was reported.
    /// The lead-up window is worth printing once; printing it at every
    /// checkpoint would make the snapshot the log rather than a region of it.
    pub fn takeUnreported(self: *Ledger, index: usize) bool {
        const found = self.reading(index);
        if (!found.standing.actionable()) return false;
        if (self.reported[index]) return false;
        self.reported[index] = true;
        return true;
    }

    /// The retained events in the order they happened.
    ///
    /// The ring is written in place, so the oldest retained entry is the one
    /// after the cursor once the ring has wrapped. Copying into the caller's
    /// buffer keeps this allocation-free and keeps the ring available for the
    /// events that arrive while the report is being written.
    pub fn leadUp(self: *const Ledger, out: []Occurrence) []Occurrence {
        const length = @min(self.filled, out.len);
        if (length == 0) return out[0..0];
        var source = if (self.filled < window_capacity)
            self.filled - length
        else
            (self.cursor + (window_capacity - length)) % window_capacity;
        var written: usize = 0;
        while (written < length) : (written += 1) {
            out[written] = self.window[source];
            source = (source + 1) % window_capacity;
        }
        return out[0..length];
    }
};

fn rank(found: RuleReading) u8 {
    return switch (found.standing) {
        .violated => if (found.rule.strength == .mandatory) 0 else 1,
        .raced => 2,
        else => 3,
    };
}

test "an empty ledger judges nothing" {
    const ledger = Ledger{};
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u8, 0), totals.active);
    try std.testing.expect(ledger.firstFinding() == null);
}

// The 2026-08-30 reading, replayed: twenty-four raw IssueDraw calls entered
// the command processor, but Xenia classified them as no-effect draws. Raw
// entry must remain diagnostic context, not proof that a target-backed draw
// occurred. A classified renderable draw is the event that can be judged.
test "raw no-effect draws do not create a false target-order finding" {
    var ledger = Ledger{};
    ledger.observe(.engines_initialized, 3_004_649_644, 0x7fff20f0, 0);
    ledger.observe(.ring_initialized, 3_039_275_846, 0x7fff20f0, 0);
    ledger.observe(.write_pointer_published, 3_390_634_999, 0x7fff20f0, 0);
    ledger.observe(.command_processor_running, 41_448_786, 0x7fff2040, 0);
    ledger.observe(.ring_drained, 3_390_703_080, 0x7fff2040, 0);
    var draw: u64 = 0;
    while (draw < 24) : (draw += 1) {
        ledger.observe(.draw_issued, 3_399_870_297 + draw, 0x7fff2040, draw);
    }

    try std.testing.expectEqual(@as(u8, 0), ledger.summary().mandatory_violations);
    try std.testing.expect(ledger.firstFinding() == null);

    ledger.observe(.renderable_draw_issued, 3_399_870_321, 0x7fff2040, 1);

    const found = ledger.firstFinding().?;
    try std.testing.expectEqual(Standing.violated, found.standing);
    try std.testing.expectEqual(Event.render_target_programmed, found.rule.required);
    try std.testing.expectEqual(Event.renderable_draw_issued, found.rule.dependant);
    try std.testing.expectEqual(@as(u64, 1), found.dependant_count);
    try std.testing.expectEqual(@as(u8, 1), ledger.summary().mandatory_violations);
}

// The other half of the same run: the interrupt entered guest code and the
// title's own registration was never observed.
test "an interrupt entering the guest without a registration is a violation" {
    var ledger = Ledger{};
    ledger.observe(.interrupt_dispatched, 731_864_641, 0x7fff2050, 0);
    ledger.observe(.interrupt_entered_guest, 731_865_818, 0x7fff2050, 0xffff0010);
    var index: usize = 0;
    var found: ?RuleReading = null;
    while (index < rule_count) : (index += 1) {
        const reading = ledger.reading(index);
        if (reading.rule.dependant == .interrupt_entered_guest) found = reading;
    }
    try std.testing.expectEqual(Standing.violated, found.?.standing);
}

test "an ordering that held by less than its window is reported as a race" {
    var ledger = Ledger{};
    // `engines_initialized -> ring_initialized` carries a one-million-step
    // window, so a ring initialised immediately afterwards held by luck.
    ledger.observe(.engines_initialized, 1_000_000, 0, 0);
    ledger.observe(.ring_initialized, 1_000_500, 0, 0);
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u8, 1), totals.raced);
    try std.testing.expectEqual(@as(u8, 0), totals.violated);
    try std.testing.expect(totals.actionable() != 0);
}

test "a wide ordering is held rather than raced" {
    var ledger = Ledger{};
    ledger.observe(.engines_initialized, 3_004_649_644, 0, 0);
    ledger.observe(.ring_initialized, 3_039_275_846, 0, 0);
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u8, 1), totals.held);
    try std.testing.expectEqual(@as(u8, 0), totals.raced);
}

test "the lead-up window returns events oldest first" {
    var ledger = Ledger{};
    var step: u64 = 1;
    while (step <= 5) : (step += 1) {
        ledger.observe(.draw_issued, step, 0, step);
    }
    var buffer: [window_capacity]Occurrence = undefined;
    const window = ledger.leadUp(&buffer);
    try std.testing.expectEqual(@as(usize, 5), window.len);
    try std.testing.expectEqual(@as(u64, 1), window[0].step);
    try std.testing.expectEqual(@as(u64, 5), window[4].step);
}

// The ring must stay ordered after it wraps, or the snapshot at a violation
// shows the run's history in the wrong sequence — which is worse than no
// snapshot at all.
test "the lead-up window stays ordered after the ring wraps" {
    var ledger = Ledger{};
    var step: u64 = 1;
    while (step <= window_capacity * 2 + 3) : (step += 1) {
        ledger.observe(.register_programmed, step, 0, step);
    }
    var buffer: [window_capacity]Occurrence = undefined;
    const window = ledger.leadUp(&buffer);
    try std.testing.expectEqual(window_capacity, window.len);
    try std.testing.expectEqual(step - 1, window[window.len - 1].step);
    var index: usize = 1;
    while (index < window.len) : (index += 1) {
        try std.testing.expect(window[index].step > window[index - 1].step);
    }
}

// Retain always, report once. A snapshot printed at every checkpoint stops
// being a region of detail and becomes the log.
test "a finding is offered for reporting exactly once" {
    var ledger = Ledger{};
    ledger.observe(.renderable_draw_issued, 100, 0, 0);
    var index: usize = 0;
    var draw_rule: usize = rule_count;
    while (index < rule_count) : (index += 1) {
        if (rules[index].dependant == .renderable_draw_issued) draw_rule = index;
    }
    try std.testing.expect(draw_rule != rule_count);
    try std.testing.expect(ledger.takeUnreported(draw_rule));
    try std.testing.expect(!ledger.takeUnreported(draw_rule));
}

test "a rule whose events never both occur is never actionable" {
    var ledger = Ledger{};
    ledger.observe(.render_target_programmed, 100, 0, 0);
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u8, 0), totals.actionable());
    try std.testing.expect(ledger.firstFinding() == null);
}

// A high-frequency event must not push the events that matter out of the
// lead-up window, and its count must still be answerable.
test "observeOnce keeps the count and the window's first entry" {
    var ledger = Ledger{};
    var step: u64 = 1;
    while (step <= 200) : (step += 1) {
        ledger.observeOnce(.register_programmed, step, 0, 0);
    }
    ledger.observe(.renderable_draw_issued, 500, 0, 0);
    try std.testing.expectEqual(@as(u64, 200), ledger.count(.register_programmed));
    try std.testing.expectEqual(@as(u64, 1), ledger.firstStep(.register_programmed));
    var buffer: [window_capacity]Occurrence = undefined;
    const window = ledger.leadUp(&buffer);
    try std.testing.expectEqual(@as(usize, 2), window.len);
    try std.testing.expectEqual(Event.register_programmed, window[0].event);
    try std.testing.expectEqual(Event.renderable_draw_issued, window[1].event);
}
