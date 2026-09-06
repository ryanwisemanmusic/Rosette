//! What a graphics interrupt *did*, as distinct from whether one was
//! delivered.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run registered the title's callback at `0x821951F8` and
//! entered it repeatedly. Every counter about the callback route was healthy,
//! and the producer never advanced. A callback count is not a hardware
//! interrupt: the title may be distinguishing vblank from ring completion from
//! event-write, may be reading a source or status value out of the frame, may
//! need an acknowledgement before the next one, or may require the callback to
//! run on a particular thread.
//!
//! Every dispatch in that run passed `source=0`. That is adequate for some
//! titles and wrong for others, and nothing in the run could tell which,
//! because "the callback ran" and "the callback had the effect the title was
//! waiting for" were the same number.
//!
//! So this ledger links the whole chain — PM4 event, emulator completion
//! state, interrupt source/status, callback entry and return, guest object
//! mutation, waiter result — and reports the first link that did not happen.
//! A registration and a dispatch count satisfy nothing on their own.
//!
//! What it never does
//! ------------------
//! It does not deliver an interrupt, broaden a source, or set a guest object
//! because a waiter is overdue. The differential mode below selects *which
//! cause to observe*, never which to fabricate.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;
pub const Address = bridge.contract.Address;
pub const CodeLocation = bridge.contract.CodeLocation;

/// Why an interrupt was raised. The title may branch on this, and a run that
/// only ever raises one of them cannot discover that.
pub const Cause = enum(u8) {
    vblank = 0,
    ring_write_pointer_completion = 1,
    event_write_completion = 2,
    read_pointer_writeback = 3,
    command_stream_interrupt = 4,
    unknown = 255,

    pub fn label(self: Cause) []const u8 {
        return switch (self) {
            .vblank => "vblank",
            .ring_write_pointer_completion => "ring-write-pointer-completion",
            .event_write_completion => "event-write-completion",
            .read_pointer_writeback => "read-pointer-writeback",
            .command_stream_interrupt => "command-stream-interrupt",
            .unknown => "unknown",
        };
    }

    /// This cause's slot in a dense per-cause table.
    ///
    /// Deliberately not `@intFromEnum`. `unknown` carries 255 because that is
    /// what it means as a *source code*, and a six-entry histogram indexed by
    /// the source code writes past its end — silently in a release build. The
    /// enum's numbering serves the wire and this serves the table, and
    /// conflating them is a memory-safety bug that only appears on the first
    /// unrecognised source the emulator ever raises.
    pub fn bucket(self: Cause) usize {
        return switch (self) {
            .vblank => 0,
            .command_stream_interrupt => 1,
            .ring_write_pointer_completion => 2,
            .event_write_completion => 3,
            .read_pointer_writeback => 4,
            .unknown => 5,
        };
    }

    /// The inverse of `bucket`, for walking a dense table back to causes.
    pub fn fromBucket(index: usize) Cause {
        return switch (index) {
            0 => .vblank,
            1 => .command_stream_interrupt,
            2 => .ring_write_pointer_completion,
            3 => .event_write_completion,
            4 => .read_pointer_writeback,
            else => .unknown,
        };
    }

    /// The `source` value the console would pass for this cause. Zero for
    /// vblank is what every dispatch in the observed run used.
    pub fn sourceCode(self: Cause) u32 {
        return switch (self) {
            .vblank => 0,
            .command_stream_interrupt => 1,
            .ring_write_pointer_completion => 2,
            .event_write_completion => 3,
            .read_pointer_writeback => 4,
            .unknown => 0xFFFF_FFFF,
        };
    }
};

pub const cause_count: usize = @typeInfo(Cause).@"enum".fields.len;

/// The cause a raw `source` value names.
///
/// The inverse of `sourceCode`, and it exists so a ledger fed from an observed
/// dispatch records the cause the emulator actually raised instead of the one
/// the call site assumed. Recording every delivery as `vblank` because vblank
/// is the common case makes the cause histogram a restatement of the call site
/// rather than an observation, and the histogram is the only thing that can
/// say whether the handler was ever asked a second question.
pub fn causeOfSource(source: u32) Cause {
    inline for (@typeInfo(Cause).@"enum".fields) |field| {
        const cause: Cause = @enumFromInt(field.value);
        if (cause != .unknown and cause.sourceCode() == source) return cause;
    }
    return .unknown;
}

/// The links between a GPU event and a guest thread waking up. Each is
/// observed on its own.
pub const Link = enum(u8) {
    /// A PM4 event or write-back created the completion.
    gpu_event = 0,
    /// The emulator recorded the completion in its own state.
    emulator_completion = 1,
    /// An interrupt source/status was raised.
    interrupt_raised = 2,
    /// The title's callback was entered.
    callback_entered = 3,
    /// The callback returned. A handler still inside its call is a dead pump
    /// with a healthy entry count.
    callback_returned = 4,
    /// A guest object or flag changed as a result.
    guest_state_mutated = 5,
    /// A waiter left its pending state.
    waiter_released = 6,

    pub fn label(self: Link) []const u8 {
        return switch (self) {
            .gpu_event => "GPU event/writeback",
            .emulator_completion => "emulator completion state",
            .interrupt_raised => "interrupt source/status",
            .callback_entered => "title callback entry",
            .callback_returned => "title callback return",
            .guest_state_mutated => "guest object/flag mutation",
            .waiter_released => "waiter result",
        };
    }

    pub fn owner(self: Link) []const u8 {
        return switch (self) {
            .gpu_event, .emulator_completion, .interrupt_raised => "emulator:gpu",
            .callback_entered, .callback_returned => "emulator:kernel",
            .guest_state_mutated, .waiter_released => "guest:title",
        };
    }

    pub fn gapMeans(self: Link) []const u8 {
        return switch (self) {
            .gpu_event => "no PM4 event or write-back created a completion. Nothing downstream is missing — there was nothing to deliver",
            .emulator_completion => "an event happened and the emulator recorded no completion for it. The event decoder and the completion state are disagreeing",
            .interrupt_raised => "a completion exists and no interrupt was raised for it. The title will not be told, whatever its callback does",
            .callback_entered => "an interrupt was raised and the title's callback was not entered. Check registration provenance and the dispatch gate before anything else",
            .callback_returned => "the callback was entered and has not returned. The handler is still inside its call, and the thread that made it is gone — every counter upstream still reads healthy",
            .guest_state_mutated => "the callback ran and returned and no guest object changed. The title's handler executed and did not do what the waiter is waiting for: the cause code, the status value or the payload it read is not the one it needs",
            .waiter_released => "a guest object changed and no waiter left its pending state. Either nobody is waiting on that object, or the object the handler set is not the one the waiter chose",
        };
    }
};

pub const link_count: usize = @typeInfo(Link).@"enum".fields.len;

/// One interrupt, from event to waiter.
pub const Delivery = struct {
    id: u64 = 0,
    cause: Cause = .unknown,
    source_code: u32 = 0,
    status_value: u32 = 0,
    callback: u32 = 0,
    user_data: u32 = 0,
    guest_thread: u64 = 0,
    /// The object the title is expected to touch, and the one it did.
    expected_object: u64 = 0,
    /// A complete watch of the expected object over this callback interval.
    effect_observed: bool = false,
    mutated_object: u64 = 0,
    /// The waiter this was supposed to release.
    waiter_object: u64 = 0,
    queued_step: u64 = 0,
    entered_step: u64 = 0,
    returned_step: u64 = 0,
    source: SourceClass = .unknown,
    reached: [link_count]bool = [_]bool{false} ** link_count,

    pub fn note(self: *Delivery, link: Link) void {
        self.reached[@intFromEnum(link)] = true;
    }

    pub fn has(self: Delivery, link: Link) bool {
        return self.reached[@intFromEnum(link)];
    }

    pub fn firstGap(self: Delivery) ?Link {
        var index: usize = 0;
        while (index < link_count) : (index += 1) {
            if (!self.reached[index]) return @enumFromInt(index);
        }
        return null;
    }

    /// The callback is still inside its call. This is the shape that kills a
    /// display pump while every entry counter reads healthy.
    pub fn stillInside(self: Delivery) bool {
        return self.has(.callback_entered) and !self.has(.callback_returned);
    }

    /// Whether the object the handler touched is the one the waiter chose. A
    /// mutation of the wrong object is a working callback and a stuck title.
    pub fn mutatedExpectedObject(self: Delivery) bool {
        if (self.mutated_object == 0) return false;
        if (self.expected_object == 0) return true;
        return self.mutated_object == self.expected_object;
    }

    /// The audit's criterion for a callback claimed to unblock a producer:
    /// entry, return, a guest mutation, and the waiter leaving pending.
    pub fn unblockedAWaiter(self: Delivery) bool {
        return self.has(.callback_entered) and
            self.has(.callback_returned) and
            self.has(.guest_state_mutated) and
            self.has(.waiter_released) and
            self.mutatedExpectedObject();
    }
};

/// What the ledger concluded overall.
pub const Verdict = enum(u8) {
    unobserved,
    /// Deliveries reach the waiter. The route works.
    effective,
    /// The callback runs and returns and nothing in the guest changes.
    entered_without_effect,
    effect_unobserved,
    /// The callback was entered and never came back.
    handler_never_returned,
    /// The chain stops before the callback.
    never_delivered,
    /// The handler changed something other than what the waiter chose.
    wrong_object_mutated,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .effective => "effective",
            .entered_without_effect => "ENTERED-WITHOUT-EFFECT",
            .effect_unobserved => "EFFECT-UNOBSERVED",
            .handler_never_returned => "CALLBACK-IN-FLIGHT",
            .never_delivered => "NEVER-DELIVERED",
            .wrong_object_mutated => "WRONG-OBJECT-MUTATED",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "no interrupt delivery has been recorded, so neither its success nor its failure is available",
            .effective => "deliveries reach a waiter and release it. Registration, dispatch and effect are all proven",
            .entered_without_effect => "a returned callback has a named expected object and complete effect observation, but did not perform the expected mutation",
            .effect_unobserved => "callbacks returned, but the expected object and a complete effect watch are not established. A sampled ring hash cannot prove that the handler changed no guest state",
            .handler_never_returned => "a callback entry has no observed return yet. This can be execution, compilation, or delayed telemetry; no deadline violation is proven by the count alone",
            .never_delivered => "the chain stops before the title's callback. Nothing the handler does can matter until this is fixed, and the first missing link names who owns it",
            .wrong_object_mutated => "the handler changed a guest object and it is not the one the waiter chose. This is the split-identity shape: a working callback and a stuck title",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return switch (self) {
            .entered_without_effect, .wrong_object_mutated => true,
            .unobserved, .effective, .effect_unobserved, .handler_never_returned, .never_delivered => false,
        };
    }
};

pub const max_deliveries: usize = 32;

/// Which causes a run is allowed to raise. The differential experiment the
/// audit asks for: deliver one cause at a time and watch the effect, rather
/// than broadening delivery until something moves.
pub const CauseFilter = struct {
    enabled: [cause_count]bool = [_]bool{true} ** cause_count,

    pub fn only(cause: Cause) CauseFilter {
        var filter = CauseFilter{ .enabled = [_]bool{false} ** cause_count };
        filter.enabled[cause.bucket()] = true;
        return filter;
    }

    pub fn allows(self: CauseFilter, cause: Cause) bool {
        return self.enabled[cause.bucket()];
    }
};

pub const Summary = struct {
    deliveries: u64 = 0,
    retained: usize = 0,
    dropped: u64 = 0,
    entered: u64 = 0,
    returned: u64 = 0,
    mutations: u64 = 0,
    releases: u64 = 0,
    wrong_object: u64 = 0,
    outstanding: u64 = 0,
    by_cause: [cause_count]u64 = [_]u64{0} ** cause_count,
    refused_by_filter: u64 = 0,
};

pub const Ledger = struct {
    deliveries: [max_deliveries]Delivery = [_]Delivery{.{}} ** max_deliveries,
    count: usize = 0,
    dropped: u64 = 0,
    total: u64 = 0,
    next_id: u64 = 1,
    filter: CauseFilter = .{},
    refused_by_filter: u64 = 0,
    by_cause: [cause_count]u64 = [_]u64{0} ** cause_count,

    reported_entries: u64 = 0,
    reported_returns: u64 = 0,
    reported_step: u64 = 0,

    /// Cumulative statements remain totals. They never create individual
    /// deliveries, causes, timestamps, GPU writes or guest mutations.
    pub fn observeTotals(self: *Ledger, entered: u64, returned: u64, step: u64) void {
        self.reported_entries = @max(self.reported_entries, entered);
        self.reported_returns = @max(self.reported_returns, returned);
        self.reported_step = step;
    }

    fn findObserved(self: *Ledger, id: u64, callback: u32) ?*Delivery {
        for (self.deliveries[0..self.count]) |*delivery| {
            if (delivery.id == id and delivery.callback == callback) return delivery;
        }
        return null;
    }

    pub fn observeEntry(self: *Ledger, id: u64, callback: u32, source: u32, cpu: u32, step: u64) void {
        if (self.findObserved(id, callback) != null) return;
        const delivery = self.begin(causeOfSource(source), step) orelse return;
        delivery.id = id;
        delivery.callback = callback;
        delivery.source_code = source;
        // cpu is a processor index, not a guest thread identity.
        _ = cpu;
        delivery.entered_step = step;
        delivery.source = .host_forwarded;
        delivery.note(.interrupt_raised);
        delivery.note(.callback_entered);
    }

    pub fn observeReturn(self: *Ledger, id: u64, callback: u32, step: u64) void {
        // A return without a retained entry still raises the total; it cannot
        // reconstruct the source, event, or time of that missing entry.
        const delivery = self.findObserved(id, callback) orelse return;
        delivery.returned_step = step;
        delivery.note(.callback_returned);
    }

    /// Begin a delivery. A cause the filter excludes is refused and counted;
    /// it is never delivered silently.
    pub fn begin(self: *Ledger, cause: Cause, at_step: u64) ?*Delivery {
        if (!self.filter.allows(cause)) {
            self.refused_by_filter +|= 1;
            return null;
        }
        self.total +|= 1;
        self.by_cause[cause.bucket()] +|= 1;
        if (self.count >= max_deliveries) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.deliveries[self.count];
        self.count += 1;
        slot.* = .{ .id = self.next_id, .cause = cause, .source_code = cause.sourceCode(), .queued_step = at_step };
        self.next_id += 1;
        return slot;
    }

    pub fn retained(self: *const Ledger) []const Delivery {
        return self.deliveries[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{
            .deliveries = self.total,
            .retained = self.count,
            .dropped = self.dropped,
            .by_cause = self.by_cause,
            .refused_by_filter = self.refused_by_filter,
        };
        for (self.retained()) |delivery| {
            if (delivery.has(.callback_entered)) out.entered +|= 1;
            if (delivery.has(.callback_returned)) out.returned +|= 1;
            if (delivery.has(.guest_state_mutated)) out.mutations +|= 1;
            if (delivery.has(.waiter_released)) out.releases +|= 1;
            if (delivery.has(.guest_state_mutated) and !delivery.mutatedExpectedObject()) {
                out.wrong_object +|= 1;
            }
            if (delivery.stillInside()) out.outstanding +|= 1;
        }
        out.deliveries = @max(out.deliveries, self.reported_entries);
        out.entered = @max(out.entered, self.reported_entries);
        out.returned = @max(out.returned, self.reported_returns);
        out.outstanding = out.entered -| out.returned;
        return out;
    }

    /// How many distinct causes this run has ever raised.
    ///
    /// A handler that branches on the cause and only ever sees one of them is
    /// indistinguishable, from every counter in the run, from a handler that
    /// ignores the cause and is broken. The console raises several; a run that
    /// raises one has not tested the handler, it has tested one path through
    /// it — and `entered-without-effect` is exactly what that looks like.
    pub fn causesRaised(self: *const Ledger) usize {
        var count: usize = 0;
        for (self.by_cause) |raised| {
            if (raised != 0) count += 1;
        }
        return count;
    }

    /// The only cause this run has raised, when there is exactly one. Named
    /// rather than counted because the next question is always which one.
    pub fn soleCause(self: *const Ledger) ?Cause {
        if (self.causesRaised() != 1) return null;
        for (self.by_cause, 0..) |raised, index| {
            if (raised != 0) return Cause.fromBucket(index);
        }
        return null;
    }

    /// Whether the run's evidence permits the conclusion that the title's
    /// handler is at fault.
    ///
    /// It does not when every delivery carried one cause: the handler has been
    /// entered many times and asked one question, and "the handler does not do
    /// what the waiter needs" is then a statement about the experiment rather
    /// than about the handler. This is the suppression the audit's own
    /// differential mode exists to serve, made explicit so a reader does not
    /// have to notice the histogram.
    pub fn permitsHandlerConclusion(self: *const Ledger) bool {
        for (self.retained()) |delivery| {
            if (delivery.has(.callback_returned) and delivery.expected_object != 0 and
                delivery.effect_observed and !delivery.has(.guest_state_mutated)) return true;
        }
        return false;
    }

    /// The first link no delivery has ever crossed.
    pub fn frontier(self: *const Ledger) ?Link {
        if (self.count == 0) return .gpu_event;
        var index: usize = 0;
        while (index < link_count) : (index += 1) {
            var any = false;
            for (self.retained()) |delivery| {
                if (delivery.reached[index]) any = true;
            }
            if (!any) return @enumFromInt(index);
        }
        return null;
    }

    pub fn verdict(self: *const Ledger) Verdict {
        const totals = self.summary();
        if (totals.deliveries == 0 and totals.returned == 0) return .unobserved;
        for (self.retained()) |delivery| {
            if (delivery.unblockedAWaiter()) return .effective;
        }
        if (totals.outstanding != 0) return .handler_never_returned;
        if (totals.wrong_object != 0) return .wrong_object_mutated;
        if (totals.returned != 0) return if (self.permitsHandlerConclusion()) .entered_without_effect else .effect_unobserved;
        return .never_delivered;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.deliveries;
        hash = hash *% 31 +% totals.entered;
        hash = hash *% 31 +% totals.returned;
        hash = hash *% 31 +% totals.releases;
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

test "an entered callback that changes nothing is not a delivered completion" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 8) : (index += 1) {
        const delivery = ledger.begin(.vblank, 1000 + index).?;
        delivery.callback = 0x8219_51F8;
        delivery.note(.gpu_event);
        delivery.note(.emulator_completion);
        delivery.note(.interrupt_raised);
        delivery.note(.callback_entered);
        delivery.note(.callback_returned);
    }
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.effect_unobserved, verdict);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expectEqual(Link.guest_state_mutated, ledger.frontier().?);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "expected object") != null);
}

test "a handler still inside its call is found even with a healthy entry count" {
    var ledger = Ledger{};
    const finished = ledger.begin(.vblank, 100).?;
    finished.note(.callback_entered);
    finished.note(.callback_returned);
    const stuck = ledger.begin(.vblank, 200).?;
    stuck.note(.callback_entered);

    try std.testing.expect(stuck.stillInside());
    try std.testing.expect(!finished.stillInside());
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().outstanding);
    try std.testing.expectEqual(Verdict.handler_never_returned, ledger.verdict());
}

test "a mutation of the wrong object is a working callback and a stuck title" {
    var ledger = Ledger{};
    const delivery = ledger.begin(.event_write_completion, 100).?;
    delivery.expected_object = 0x4000_4BF4;
    delivery.mutated_object = 0x827C_EC28;
    delivery.note(.gpu_event);
    delivery.note(.emulator_completion);
    delivery.note(.interrupt_raised);
    delivery.note(.callback_entered);
    delivery.note(.callback_returned);
    delivery.note(.guest_state_mutated);

    try std.testing.expect(!delivery.mutatedExpectedObject());
    try std.testing.expect(!delivery.unblockedAWaiter());
    try std.testing.expectEqual(Verdict.wrong_object_mutated, ledger.verdict());
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().wrong_object);
}

// The audit's acceptance criterion for a callback claimed to unblock a
// producer: entry, return, the mutation, and the waiter leaving pending.
test "unblocking a waiter needs all four links and the right object" {
    var delivery = Delivery{ .expected_object = 0x4000_4BF4, .mutated_object = 0x4000_4BF4 };
    delivery.note(.callback_entered);
    delivery.note(.callback_returned);
    delivery.note(.guest_state_mutated);
    try std.testing.expect(!delivery.unblockedAWaiter());
    delivery.note(.waiter_released);
    try std.testing.expect(delivery.unblockedAWaiter());
}

// The audit's Experiment B: one cause at a time, observed rather than forced.
test "the cause filter selects what to observe and counts what it excluded" {
    var ledger = Ledger{ .filter = CauseFilter.only(.event_write_completion) };
    try std.testing.expect(ledger.begin(.vblank, 100) == null);
    try std.testing.expectEqual(@as(u64, 1), ledger.refused_by_filter);
    try std.testing.expectEqual(@as(u64, 0), ledger.total);

    const allowed = ledger.begin(.event_write_completion, 200).?;
    try std.testing.expectEqual(@as(u32, 3), allowed.source_code);
    try std.testing.expectEqual(@as(u64, 1), ledger.total);
    try std.testing.expectEqual(@as(u64, 1), ledger.by_cause[Cause.event_write_completion.bucket()]);
}

test "a chain that stops before the callback names the link and its owner" {
    var ledger = Ledger{};
    const delivery = ledger.begin(.ring_write_pointer_completion, 100).?;
    delivery.note(.gpu_event);
    delivery.note(.emulator_completion);
    try std.testing.expectEqual(Link.interrupt_raised, delivery.firstGap().?);
    try std.testing.expectEqual(Verdict.never_delivered, ledger.verdict());
    try std.testing.expectEqualStrings("emulator:gpu", Link.interrupt_raised.owner());
}

test "a released waiter makes the route effective" {
    var ledger = Ledger{};
    const delivery = ledger.begin(.vblank, 100).?;
    delivery.expected_object = 7;
    delivery.mutated_object = 7;
    inline for (@typeInfo(Link).@"enum".fields) |field| {
        delivery.note(@enumFromInt(field.value));
    }
    try std.testing.expect(delivery.firstGap() == null);
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.effective, verdict);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expect(ledger.frontier() == null);
}

test "nothing delivered is unobserved rather than a failure" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Verdict.unobserved, ledger.verdict());
    try std.testing.expect(!ledger.verdict().isDefect());
    try std.testing.expectEqual(Link.gpu_event, ledger.frontier().?);
}

test "every cause and link states its own vocabulary" {
    inline for (@typeInfo(Cause).@"enum".fields) |field| {
        const cause: Cause = @enumFromInt(field.value);
        try std.testing.expect(cause.label().len != 0);
    }
    inline for (@typeInfo(Link).@"enum".fields) |field| {
        const link: Link = @enumFromInt(field.value);
        try std.testing.expect(link.label().len != 0);
        try std.testing.expect(link.owner().len != 0);
        try std.testing.expect(link.gapMeans().len != 0);
    }
    // Every dispatch in the observed run used source 0, which is vblank.
    try std.testing.expectEqual(@as(u32, 0), Cause.vblank.sourceCode());
}

// `ENTERED-WITHOUT-EFFECT` reads as a finding against the title's handler. It
// is only that if the handler was asked more than one question, and the run it
// was written against raised `source=0` every single time.
test "one cause raised repeatedly does not license a conclusion about the handler" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_deliveries - 1) : (index += 1) {
        const delivery = ledger.begin(.vblank, 1000 + index).?;
        delivery.callback = 0x8219_51F8;
        delivery.note(.gpu_event);
        delivery.note(.emulator_completion);
        delivery.note(.interrupt_raised);
        delivery.note(.callback_entered);
        delivery.note(.callback_returned);
    }

    try std.testing.expectEqual(Verdict.effect_unobserved, ledger.verdict());
    try std.testing.expectEqual(@as(usize, 1), ledger.causesRaised());
    try std.testing.expectEqual(Cause.vblank, ledger.soleCause().?);
    // Many entries, one question. The verdict stands and the conclusion it
    // invites does not.
    try std.testing.expect(!ledger.permitsHandlerConclusion());

    // A second cause makes the same verdict mean what it says.
    const completion = ledger.begin(.event_write_completion, 2000).?;
    completion.note(.callback_entered);
    completion.note(.callback_returned);
    try std.testing.expectEqual(@as(usize, 2), ledger.causesRaised());
    try std.testing.expect(ledger.soleCause() == null);
    try std.testing.expect(!ledger.permitsHandlerConclusion());
}

// The observed run delivered forty-three and retained thirty-two. The
// histogram has to survive that: a cause raised only after the retention
// window filled is still a cause this run raised, and losing it would make the
// diversity reading a function of when the interesting delivery happened.
test "the cause histogram counts deliveries the retention window dropped" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_deliveries) : (index += 1) {
        _ = ledger.begin(.vblank, 1000 + index);
    }
    try std.testing.expectEqual(max_deliveries, ledger.count);
    try std.testing.expectEqual(@as(usize, 1), ledger.causesRaised());

    // Past the window: no slot, still counted.
    try std.testing.expect(ledger.begin(.event_write_completion, 9000) == null);
    try std.testing.expectEqual(@as(u64, 1), ledger.dropped);
    try std.testing.expectEqual(@as(usize, 2), ledger.causesRaised());
    try std.testing.expect(!ledger.permitsHandlerConclusion());
}

// A run that has delivered nothing cannot license any conclusion either, and
// for a different reason: there is no experiment at all.
test "no delivery licenses nothing, and the cause histogram says so" {
    const ledger = Ledger{};
    try std.testing.expectEqual(@as(usize, 0), ledger.causesRaised());
    try std.testing.expect(ledger.soleCause() == null);
    try std.testing.expect(!ledger.permitsHandlerConclusion());
    try std.testing.expectEqual(Verdict.unobserved, ledger.verdict());
}

// Every cause the console can raise has to carry a distinct source code, or
// the differential experiment cannot tell the paths apart.
test "each cause carries its own source code" {
    var seen: [cause_count]u32 = undefined;
    inline for (@typeInfo(Cause).@"enum".fields, 0..) |field, index| {
        const cause: Cause = @enumFromInt(field.value);
        try std.testing.expect(cause.label().len != 0);
        seen[index] = cause.sourceCode();
    }
    for (seen, 0..) |left, i| {
        for (seen[i + 1 ..]) |right| {
            try std.testing.expect(left != right);
        }
    }
    try std.testing.expectEqual(@as(u32, 0), Cause.vblank.sourceCode());
}

// A ledger fed from an observed dispatch has to record the cause the emulator
// raised. Recording every delivery as vblank because vblank is the common case
// makes the histogram a restatement of the call site.
test "a raw source value resolves to the cause it names" {
    try std.testing.expectEqual(Cause.vblank, causeOfSource(0));
    try std.testing.expectEqual(Cause.command_stream_interrupt, causeOfSource(1));
    try std.testing.expectEqual(Cause.ring_write_pointer_completion, causeOfSource(2));
    try std.testing.expectEqual(Cause.event_write_completion, causeOfSource(3));
    try std.testing.expectEqual(Cause.read_pointer_writeback, causeOfSource(4));
    // A value the console does not define is `unknown` rather than silently
    // folded into vblank: a source nobody recognises is a fact worth seeing.
    try std.testing.expectEqual(Cause.unknown, causeOfSource(0x1234));
    // Round trip for every defined cause.
    inline for (@typeInfo(Cause).@"enum".fields) |field| {
        const cause: Cause = @enumFromInt(field.value);
        if (cause == .unknown) continue;
        try std.testing.expectEqual(cause, causeOfSource(cause.sourceCode()));
    }
}

// `unknown` carries 255 because that is what it means as a source code, and a
// six-entry table indexed by the source code writes past its end. The bug is
// invisible until the emulator raises the first source this build does not
// recognise, and then it is a silent out-of-bounds write in a release build.
test "the cause histogram is indexed by a dense bucket, not by the source code" {
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), Cause.unknown.sourceCode());
    try std.testing.expect(@intFromEnum(Cause.unknown) >= cause_count);
    try std.testing.expect(Cause.unknown.bucket() < cause_count);

    // Every cause has its own slot, and every slot maps back.
    var seen = [_]bool{false} ** cause_count;
    inline for (@typeInfo(Cause).@"enum".fields) |field| {
        const cause: Cause = @enumFromInt(field.value);
        try std.testing.expect(cause.bucket() < cause_count);
        try std.testing.expect(!seen[cause.bucket()]);
        seen[cause.bucket()] = true;
        try std.testing.expectEqual(cause, Cause.fromBucket(cause.bucket()));
    }
    for (seen) |slot| try std.testing.expect(slot);

    // An unrecognised source reaches the ledger without leaving the table.
    var ledger = Ledger{};
    const delivery = ledger.begin(causeOfSource(0x1234), 10).?;
    delivery.note(.callback_entered);
    try std.testing.expectEqual(@as(u64, 1), ledger.by_cause[Cause.unknown.bucket()]);
    try std.testing.expectEqual(Cause.unknown, ledger.soleCause().?);
    try std.testing.expect(ledger.filter.allows(.unknown));
}

test "sampled callback totals never invent delivery history or GPU events" {
    var ledger = Ledger{};
    ledger.observeEntry(1, 0x821951F8, 0, 2, 100);
    ledger.observeEntry(1, 0x821951F8, 0, 2, 100);
    ledger.observeReturn(1, 0x821951F8, 150);
    ledger.observeTotals(240, 240, 900);
    try std.testing.expectEqual(@as(usize, 1), ledger.count);
    try std.testing.expectEqual(@as(u64, 240), ledger.summary().returned);
    try std.testing.expectEqual(@as(u64, 1), ledger.by_cause[Cause.vblank.bucket()]);
    const delivery = ledger.retained()[0];
    try std.testing.expectEqual(@as(u64, 100), delivery.entered_step);
    try std.testing.expectEqual(@as(u64, 150), delivery.returned_step);
    try std.testing.expect(!delivery.has(.gpu_event));
    try std.testing.expect(!delivery.has(.emulator_completion));
    try std.testing.expectEqual(Verdict.effect_unobserved, ledger.verdict());
}

test "negative callback effect requires a named object and complete watch" {
    var ledger = Ledger{};
    const delivery = ledger.begin(.vblank, 100).?;
    delivery.note(.callback_entered);
    delivery.note(.callback_returned);
    delivery.expected_object = 0x40004bf4;
    try std.testing.expectEqual(Verdict.effect_unobserved, ledger.verdict());
    delivery.effect_observed = true;
    try std.testing.expectEqual(Verdict.entered_without_effect, ledger.verdict());
    try std.testing.expect(ledger.permitsHandlerConclusion());
}
