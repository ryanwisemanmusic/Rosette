//! Whether a repeating wait is a problem or the system working, and everything
//! a reader needs about the ones that are problems.
//!
//! Every predictor in this runtime has the same weakness: it detects a
//! *pattern*, and patterns are what healthy systems are made of. An audio pump
//! that waits on a semaphore, signals two events and waits again, sixty times a
//! second, forever, is indistinguishable — as a pattern — from the same three
//! operations rotating because nothing downstream will ever consume them. The
//! livelock predictor fires on both. So does a reader.
//!
//! One thing separates them, and it is not in the pattern at all: **whether
//! anything else in the run moved.** A pump that cycles while the pipeline
//! advances, modules load and frames present is doing its job. The identical
//! cycle with every one of those frozen is a wait nobody will ever satisfy.
//!
//! So this module holds an independent set of progress axes, samples them when
//! a wait pattern is first seen and again as it recurs, and classifies the
//! pattern by what changed elsewhere. A pattern that is working is reported as
//! one line and never expanded; a pattern that is not gets the whole audit —
//! participants, operation mix, aliases, period, and the list of axes that have
//! not moved since it started, which is the concrete statement of what the wait
//! is holding back.
//!
//! ## Why the axes are named rather than counted
//!
//! "Nothing advanced" is a weaker claim than "the graphics pipeline and the
//! ring both froze while module loading kept going". The second one says the
//! wait is not blocking the loader and is blocking the GPU, which is the
//! difference between one subsystem to investigate and five. Naming the frozen
//! axes is the entire value of the witness.
//!
//! ## What it refuses to do
//!
//! It will not classify on a single sighting. One wait proves nothing, and a
//! predictor that fires on first sight is a predictor that cries wolf on every
//! healthy pump in the process.

const std = @import("std");

/// Independent evidence that the run as a whole is getting somewhere. Each axis
/// is driven by a different subsystem, so a wait can freeze one without
/// freezing the others — and which ones it freezes is the finding.
pub const Axis = enum(u8) {
    /// The emulator's own startup pipeline reached a new stage.
    pipeline_stage,
    /// The guest advanced the GPU ring write pointer.
    ring_publication,
    /// A graphics interrupt callback was dispatched.
    gpu_callback,
    /// A module was loaded.
    module_load,
    /// A frame reached the window.
    presented_frame,
    /// Guest instructions retired. Advances even in a livelock, which is
    /// exactly why it is separated from the others: it distinguishes a spinning
    /// run from a parked one and proves nothing about progress.
    executed_steps,

    pub fn label(self: Axis) []const u8 {
        return switch (self) {
            .pipeline_stage => "pipeline_stage",
            .ring_publication => "ring_publication",
            .gpu_callback => "gpu_callback",
            .module_load => "module_load",
            .presented_frame => "presented_frame",
            .executed_steps => "executed_steps",
        };
    }

    /// Whether movement on this axis counts as the run making progress.
    /// Retiring instructions does not: a livelock retires billions of them.
    pub fn provesProgress(self: Axis) bool {
        return self != .executed_steps;
    }
};

pub const axis_count = @typeInfo(Axis).@"enum".fields.len;

pub const Witness = struct {
    values: [axis_count]u64 = [_]u64{0} ** axis_count,

    pub fn set(self: *Witness, axis: Axis, value: u64) void {
        self.values[@intFromEnum(axis)] = value;
    }

    pub fn get(self: Witness, axis: Axis) u64 {
        return self.values[@intFromEnum(axis)];
    }

    /// Whether any axis that proves progress moved between two samples.
    pub fn advancedSince(self: Witness, earlier: Witness) bool {
        inline for (@typeInfo(Axis).@"enum".fields) |field| {
            const axis: Axis = @enumFromInt(field.value);
            if (axis.provesProgress() and self.get(axis) > earlier.get(axis)) return true;
        }
        return false;
    }
};

/// What a repeating wait pattern actually is.
pub const Classification = enum(u8) {
    /// Too few sightings to say. Never a finding.
    insufficient_evidence = 0,
    /// The pattern recurs and the run advanced alongside it. A working pump.
    expected_pump = 1,
    /// The pattern ran and stopped. Bounded work, now finished.
    expected_bounded = 2,
    /// The pattern recurs and nothing that proves progress has moved since it
    /// started.
    problem_stalled = 3,
    /// Every wait on this object times out. The signal is not merely late.
    problem_never_ready = 4,

    pub fn label(self: Classification) []const u8 {
        return switch (self) {
            .insufficient_evidence => "insufficient_evidence",
            .expected_pump => "expected_pump",
            .expected_bounded => "expected_bounded",
            .problem_stalled => "PROBLEM_STALLED",
            .problem_never_ready => "PROBLEM_NEVER_READY",
        };
    }

    /// Whether the full audit is worth printing. The whole point: a healthy
    /// pump gets one line, and only a problem gets its participants, operation
    /// mix and frozen axes.
    pub fn worthAuditing(self: Classification) bool {
        return @intFromEnum(self) >= @intFromEnum(Classification.problem_stalled);
    }

    pub fn meaning(self: Classification) []const u8 {
        return switch (self) {
            .insufficient_evidence => "too few sightings to distinguish a working pump from a stalled one. One wait proves nothing",
            .expected_pump => "the pattern recurs and the run advanced alongside it, so this is a working producer/consumer pump and its detail is not worth printing",
            .expected_bounded => "the pattern ran for a while and stopped. Bounded work that finished, which is what a healthy wait looks like in hindsight",
            .problem_stalled => "the pattern recurs and nothing that proves progress has moved since it started. The operations are happening and the run is not getting anywhere, so this rotation is consuming the process rather than advancing it — the frozen axes below are what it is holding back",
            .problem_never_ready => "every wait on this object timed out. The waiter blocks correctly and the signal never comes at all, which puts the defect in whatever was supposed to signal rather than in the wait",
        };
    }
};

/// Sightings before a classification means anything.
pub const minimum_sightings: u64 = 8;

/// Steps of silence after which a pattern counts as finished rather than
/// stalled. A pattern that stopped is bounded work; one that is still going is
/// the candidate.
pub const quiescent_steps: u64 = 200_000_000;

pub const Operation = enum(u8) {
    wait,
    wait_timeout,
    signal,

    pub fn label(self: Operation) []const u8 {
        return switch (self) {
            .wait => "wait",
            .wait_timeout => "wait_timeout",
            .signal => "signal",
        };
    }
};

pub const max_subjects = 24;
pub const max_participants = 4;

pub const Subject = struct {
    /// Canonical (console) address.
    object: u64 = 0,
    /// The emulator's handle for it, when a line carried one. A handle is what
    /// the title's own code refers to, so it is the identity a reader can grep
    /// the title for.
    handle: u32 = 0,
    /// The emulator's object type code, when one was stated.
    type_code: u32 = 0,
    waits: u64 = 0,
    timeouts: u64 = 0,
    signals: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// Threads observed operating on it. The participant list is what turns
    /// "this object is stuck" into "these two threads are stuck on it".
    participants: [max_participants]u64 = [_]u64{0} ** max_participants,
    participant_count: u32 = 0,
    first_witness: Witness = .{},
    last_witness: Witness = .{},

    pub fn sightings(self: Subject) u64 {
        return self.waits + self.timeouts + self.signals;
    }

    /// Mean steps between sightings. A period says whether a rotation is a
    /// frame-rate pump or a tight spin, which are different problems.
    pub fn periodSteps(self: Subject) u64 {
        const count = self.sightings();
        if (count < 2 or self.last_step <= self.first_step) return 0;
        return (self.last_step - self.first_step) / (count - 1);
    }

    fn addParticipant(self: *Subject, thread: u64) void {
        if (thread == 0) return;
        for (self.participants[0..self.participant_count]) |existing| {
            if (existing == thread) return;
        }
        if (self.participant_count == max_participants) return;
        self.participants[self.participant_count] = thread;
        self.participant_count += 1;
    }
};

pub const Ledger = struct {
    subjects: [max_subjects]Subject = [_]Subject{.{}} ** max_subjects,
    count: usize = 0,
    dropped: u64 = 0,
    witness: Witness = .{},
    /// Subjects classified as expected. Counted so a report can say how many
    /// patterns it deliberately did not print.
    suppressed: u64 = 0,

    pub fn noteProgress(self: *Ledger, axis: Axis, value: u64) void {
        if (value > self.witness.get(axis)) self.witness.set(axis, value);
    }

    fn slot(self: *Ledger, object: u64) ?*Subject {
        for (self.subjects[0..self.count]) |*subject| {
            if (subject.object == object) return subject;
        }
        if (self.count == max_subjects) {
            self.dropped +|= 1;
            return null;
        }
        const subject = &self.subjects[self.count];
        subject.* = .{ .object = object };
        self.count += 1;
        return subject;
    }

    pub fn observe(
        self: *Ledger,
        object: u64,
        operation: Operation,
        thread: u64,
        handle: u32,
        type_code: u32,
        step: u64,
    ) void {
        if (object == 0) return;
        const subject = self.slot(object) orelse return;
        if (subject.sightings() == 0) {
            subject.first_step = step;
            subject.first_witness = self.witness;
        }
        switch (operation) {
            .wait => subject.waits +|= 1,
            .wait_timeout => subject.timeouts +|= 1,
            .signal => subject.signals +|= 1,
        }
        subject.last_step = step;
        subject.last_witness = self.witness;
        if (handle != 0) subject.handle = handle;
        if (type_code != 0) subject.type_code = type_code;
        subject.addParticipant(thread);
    }

    pub fn classify(self: *const Ledger, subject: Subject, current_step: u64) Classification {
        _ = self;
        if (subject.sightings() < minimum_sightings) return .insufficient_evidence;
        // A pattern that stopped is bounded work that finished. Checked before
        // the progress test so a pump that ran early and went quiet is not
        // accused of stalling the run it is no longer part of.
        if (current_step > subject.last_step and
            current_step - subject.last_step >= quiescent_steps) return .expected_bounded;
        if (subject.last_witness.advancedSince(subject.first_witness)) return .expected_pump;
        // Timeouts prove the waiter really blocked, which is a different defect
        // from a rotation that never blocks at all.
        if (subject.waits == 0 and subject.timeouts != 0) return .problem_never_ready;
        return .problem_stalled;
    }

    /// The axes that have not moved since this pattern started. The concrete
    /// statement of what the wait is holding back, and the reason the witness
    /// is a set of named axes rather than a single counter.
    pub fn frozenAxes(self: *const Ledger, subject: Subject, out: []Axis) []Axis {
        _ = self;
        var length: usize = 0;
        inline for (@typeInfo(Axis).@"enum".fields) |field| {
            const axis: Axis = @enumFromInt(field.value);
            if (axis.provesProgress() and length < out.len and
                subject.last_witness.get(axis) == subject.first_witness.get(axis))
            {
                out[length] = axis;
                length += 1;
            }
        }
        return out[0..length];
    }

    /// The subject a reader should look at first: the worst classification,
    /// broken by which one carries the most traffic.
    pub fn worst(self: *const Ledger, current_step: u64) ?Subject {
        var chosen: ?Subject = null;
        var chosen_class: Classification = .insufficient_evidence;
        for (self.subjects[0..self.count]) |subject| {
            const classification = self.classify(subject, current_step);
            if (!classification.worthAuditing()) continue;
            const better = chosen == null or
                @intFromEnum(classification) > @intFromEnum(chosen_class) or
                (classification == chosen_class and subject.sightings() > chosen.?.sightings());
            if (better) {
                chosen = subject;
                chosen_class = classification;
            }
        }
        return chosen;
    }

    pub fn problemCount(self: *const Ledger, current_step: u64) u32 {
        var count: u32 = 0;
        for (self.subjects[0..self.count]) |subject| {
            if (self.classify(subject, current_step).worthAuditing()) count += 1;
        }
        return count;
    }

    pub fn verdict(self: *const Ledger, current_step: u64) []const u8 {
        if (self.count == 0)
            return "no wait pattern has been observed, so nothing here can be called a problem or expected";
        if (self.worst(current_step)) |subject| return self.classify(subject, current_step).meaning();
        return "every observed wait pattern either advanced the run alongside it or ran and finished. None of them is holding anything back, so none of their detail is printed";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Drive a pattern the shape the observed run has: wait on a semaphore, signal
/// two events, release the semaphore, repeat.
fn rotate(ledger: *Ledger, base_step: u64, iterations: u64) void {
    var index: u64 = 0;
    while (index < iterations) : (index += 1) {
        const step = base_step + index * 1000;
        ledger.observe(0x827CEC14, .wait, 0x7fff2080, 0xF800015C, 8, step);
        ledger.observe(0x827CEC28, .signal, 0x7fff2080, 0xF800016C, 2, step + 10);
        ledger.observe(0x827CEC38, .signal, 0x7fff2080, 0xF8000168, 2, step + 20);
    }
}

test "one sighting is never a classification" {
    var ledger = Ledger{};
    ledger.observe(0x827CEC14, .wait, 1, 0xF800015C, 8, 100);
    try std.testing.expectEqual(Classification.insufficient_evidence, ledger.classify(ledger.subjects[0], 200));
    try std.testing.expect(!Classification.insufficient_evidence.worthAuditing());
    try std.testing.expect(ledger.worst(200) == null);
    try std.testing.expect(std.mem.indexOf(u8, Classification.insufficient_evidence.meaning(), "One wait proves nothing") != null);
}

// The distinction the whole module exists for: the identical pattern is a
// working pump or a stalled rotation depending only on what happened elsewhere.
test "the same rotation is a pump or a stall depending on the witness" {
    var healthy = Ledger{};
    rotate(&healthy, 1000, 10);
    // Something independent advanced while it rotated.
    healthy.noteProgress(.pipeline_stage, 5);
    rotate(&healthy, 20000, 10);
    try std.testing.expectEqual(Classification.expected_pump, healthy.classify(healthy.subjects[0], 40000));
    try std.testing.expect(healthy.worst(40000) == null);
    try std.testing.expect(std.mem.indexOf(u8, healthy.verdict(40000), "None of them is holding anything back") != null);

    var stalled = Ledger{};
    rotate(&stalled, 1000, 20);
    try std.testing.expectEqual(Classification.problem_stalled, stalled.classify(stalled.subjects[0], 40000));
    try std.testing.expect(stalled.worst(40000) != null);
    try std.testing.expect(std.mem.indexOf(u8, stalled.verdict(40000), "holding back") != null);
}

// Retiring instructions is what a livelock does best, so it must never count as
// the run getting somewhere.
test "executed steps advancing does not make a stall look healthy" {
    var ledger = Ledger{};
    rotate(&ledger, 1000, 20);
    ledger.noteProgress(.executed_steps, 9_000_000_000);
    rotate(&ledger, 40000, 20);
    try std.testing.expectEqual(Classification.problem_stalled, ledger.classify(ledger.subjects[0], 80000));
    try std.testing.expect(!Axis.executed_steps.provesProgress());
}

// "Nothing advanced" is a weaker claim than naming which subsystems froze.
test "the frozen axes name what the wait is holding back" {
    var ledger = Ledger{};
    rotate(&ledger, 1000, 10);
    // The loader kept working; the GPU did not.
    ledger.noteProgress(.module_load, 7);
    rotate(&ledger, 20000, 10);

    var buffer: [axis_count]Axis = undefined;
    const frozen = ledger.frozenAxes(ledger.subjects[0], &buffer);
    try std.testing.expect(frozen.len >= 3);
    for (frozen) |axis| {
        try std.testing.expect(axis != .module_load);
        try std.testing.expect(axis.provesProgress());
    }
    // And because something advanced, the pattern is not accused.
    try std.testing.expectEqual(Classification.expected_pump, ledger.classify(ledger.subjects[0], 40000));
}

test "a pattern that ran and stopped is bounded work rather than a stall" {
    var ledger = Ledger{};
    rotate(&ledger, 1000, 20);
    const much_later = 1000 + quiescent_steps * 2;
    try std.testing.expectEqual(Classification.expected_bounded, ledger.classify(ledger.subjects[0], much_later));
    try std.testing.expect(!Classification.expected_bounded.worthAuditing());
}

// A waiter that blocks and times out is a different defect from a rotation that
// never blocks, and the remedies are in different subsystems.
test "waits that always time out accuse the signaller rather than the waiter" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 20) : (index += 1) {
        ledger.observe(0x827206E4, .wait_timeout, 0x7fff2090, 0xF8000058, 2, 1000 + index * 100);
    }
    try std.testing.expectEqual(Classification.problem_never_ready, ledger.classify(ledger.subjects[0], 5000));
    try std.testing.expect(std.mem.indexOf(u8, Classification.problem_never_ready.meaning(), "supposed to signal") != null);
}

test "the audit records participants, handle, type and period" {
    var ledger = Ledger{};
    rotate(&ledger, 1000, 10);
    // A second thread joins the rotation on the semaphore.
    ledger.observe(0x827CEC14, .signal, 0x7fff2090, 0xF800015C, 8, 20000);

    const subject = ledger.subjects[0];
    try std.testing.expectEqual(@as(u64, 0x827CEC14), subject.object);
    try std.testing.expectEqual(@as(u32, 0xF800015C), subject.handle);
    try std.testing.expectEqual(@as(u32, 8), subject.type_code);
    try std.testing.expectEqual(@as(u32, 2), subject.participant_count);
    try std.testing.expectEqual(@as(u64, 0x7fff2080), subject.participants[0]);
    try std.testing.expectEqual(@as(u64, 0x7fff2090), subject.participants[1]);
    try std.testing.expect(subject.periodSteps() > 0);
    try std.testing.expectEqual(@as(u64, 11), subject.sightings());
}

test "the worst subject prefers a harder classification then more traffic" {
    var ledger = Ledger{};
    // A stalled rotation with a lot of traffic.
    rotate(&ledger, 1000, 30);
    // A never-ready object with less.
    var index: u64 = 0;
    while (index < 10) : (index += 1) {
        ledger.observe(0x827206E4, .wait_timeout, 0x7fff2090, 0xF8000058, 2, 1000 + index * 100);
    }
    // never_ready outranks stalled even with less traffic.
    try std.testing.expectEqual(@as(u64, 0x827206E4), ledger.worst(90000).?.object);
    try std.testing.expectEqual(@as(u32, 4), ledger.problemCount(90000));
}

test "subjects past capacity are counted rather than dropped silently" {
    var ledger = Ledger{};
    const object: u64 = 0x8200_0000;
    var index: u32 = 0;
    while (index < max_subjects) : (index += 1) {
        ledger.observe(object + index * 0x10, .wait, 1, 0, 0, 100);
    }
    try std.testing.expectEqual(@as(usize, max_subjects), ledger.count);
    ledger.observe(0x9000_0000, .wait, 1, 0, 0, 100);
    try std.testing.expectEqual(@as(u64, 1), ledger.dropped);
}

test "a progress axis never moves backwards" {
    var ledger = Ledger{};
    ledger.noteProgress(.pipeline_stage, 9);
    ledger.noteProgress(.pipeline_stage, 3);
    try std.testing.expectEqual(@as(u64, 9), ledger.witness.get(.pipeline_stage));
}

test "an empty ledger calls nothing a problem" {
    const ledger = Ledger{};
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(100), "nothing here can be called") != null);
    inline for (@typeInfo(Axis).@"enum".fields) |field| {
        const axis: Axis = @enumFromInt(field.value);
        try std.testing.expect(axis.label().len > 0);
    }
    inline for (.{
        Classification.insufficient_evidence, Classification.expected_pump,
        Classification.expected_bounded, Classification.problem_stalled,
        Classification.problem_never_ready,
    }) |classification| {
        try std.testing.expect(classification.label().len > 0);
        try std.testing.expect(classification.meaning().len > 40);
    }
    inline for (.{ Operation.wait, Operation.wait_timeout, Operation.signal }) |operation| {
        try std.testing.expect(operation.label().len > 0);
    }
}
