//! Guest C++ exceptions, and whether catching one actually recovered anything.
//!
//! A caught exception looks like a handled error. The unwinder found a landing
//! pad, the handler ran, `__cxa_end_catch` retired the object, and execution
//! continued — every step reported success. That is exactly what happened in
//! the observed run, and the process died four thousand steps later.
//!
//! The gap is that "caught" describes the *unwinder*, not the *program*. A
//! handler that logs the failure and abandons the work it was doing has handled
//! the exception perfectly and left the system in a state where something
//! downstream will dereference a null. Nothing in the exception machinery can
//! see that, because from its point of view the transaction completed.
//!
//! So this tracks the one thing the ABI cannot: **what happened after**. An
//! exception followed by continued progress was recovered. An exception
//! followed by a terminal event, with nothing in between, was not — however
//! cleanly it was caught.
//!
//! ## Why the type matters more than the count
//!
//! Exception counts are meaningless in C++: a program can throw thousands of
//! times as ordinary control flow. What is not ordinary is a *specific type*
//! from a *specific throw site* appearing for the first time immediately before
//! a run stops progressing. The ledger is therefore keyed by type name, keeps
//! the throw site, and reports first-sight separately from recurrence — the
//! same shape as the livelock and near-null predictors, because the same
//! reasoning applies: a first sight is a new behaviour and a recurrence is a
//! pattern.
//!
//! ## What it will not claim
//!
//! Correlation is not causation, and this says so. An exception followed by a
//! terminal event is a *suspect*, reported with the distance between them, and
//! the report states that the distance is the whole of the evidence.

const std = @import("std");

/// Steps after an exception within which a terminal event is close enough to be
/// worth correlating. Beyond this the two are probably unrelated and saying
/// otherwise would send a reader at the wrong subsystem.
pub const correlation_window_steps: u64 = 100_000;

/// Steps after an exception within which a deferred codegen failure is worth
/// correlating. This window is deliberately wider than the terminal one: the
/// deferred failure is the *same* codegen transaction as the throw — the catch
/// cleanup (emitter reset, label destruction) runs a long tail of decoded
/// steps before the "function left undefined" line lands — so the distance is
/// transaction length, not unrelated time. The observed Xbyak case spans
/// ~200k steps; the window leaves room for a slow cleanup while still
/// excluding an exception and a failure that have nothing to do with each
/// other.
pub const deferred_failure_window_steps: u64 = 1_000_000;

pub const Outcome = enum(u8) {
    /// Thrown; no handler has been observed yet.
    thrown = 0,
    /// A handler was found and the catch transaction completed.
    caught = 1,
    /// Caught, and the run made observable progress afterwards.
    recovered = 2,
    /// Caught, and the handler abandoned the work it was protecting: a
    /// deferred failure (code generation for a guest function) was recorded
    /// shortly after. The unwinder completed and the program still dies later.
    caught_then_deferred = 3,
    /// Caught, and a terminal event followed closely with nothing in between.
    caught_then_terminal = 4,
    /// The unwinder found no handler.
    uncaught = 5,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .thrown => "thrown",
            .caught => "caught",
            .recovered => "recovered",
            .caught_then_deferred => "CAUGHT_THEN_DEFERRED",
            .caught_then_terminal => "CAUGHT_THEN_TERMINAL",
            .uncaught => "UNCAUGHT",
        };
    }

    pub fn concerning(self: Outcome) bool {
        return self == .caught_then_deferred or self == .caught_then_terminal or self == .uncaught;
    }

    pub fn meaning(self: Outcome) []const u8 {
        return switch (self) {
            .thrown => "an exception was raised and no handler outcome has been observed yet",
            .caught => "a handler was found and the catch transaction completed. This describes the unwinder, not the program: whether anything was actually recovered is a separate question answered by what happens next",
            .recovered => "caught, and the run made observable progress afterwards. The handler did its job",
            .caught_then_deferred => "caught cleanly, and the handler abandoned the work it was protecting: a deferred failure — code generation for a guest function — was recorded shortly after the catch. The exception machinery worked perfectly and the handler left the function undefined, so the next call to it is where the run dies. Look at what the handler abandoned, not at the unwinder. The distance between the two events is the whole of the evidence for this correlation",
            .caught_then_terminal => "caught cleanly, and the run hit a terminal event shortly afterwards with nothing in between. The exception machinery worked perfectly and the handler left the system in a state something downstream could not survive — look at what the handler abandoned, not at the unwinder. The distance between the two events is the whole of the evidence for this correlation",
            .uncaught => "the unwinder walked every frame and found no handler. The run cannot continue past this",
        };
    }
};

pub const max_types = 16;
pub const max_name = 64;
pub const max_site = 96;

pub const Record = struct {
    name_storage: [max_name]u8 = [_]u8{0} ** max_name,
    name_length: u8 = 0,
    site_storage: [max_site]u8 = [_]u8{0} ** max_site,
    site_length: u8 = 0,
    /// Emulator-specific error code carried by the exception object, when the
    /// type is one that has one. Zero means none was reported.
    code: u32 = 0,
    throws: u64 = 0,
    catches: u64 = 0,
    outcome: Outcome = .thrown,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// Frames the phase-1 walk covered. A short walk on a deep stack is its own
    /// finding: the unwinder lost the frame chain rather than finding no
    /// handler.
    unwind_frames: u32 = 0,

    pub fn name(self: *const Record) []const u8 {
        return self.name_storage[0..self.name_length];
    }

    pub fn site(self: *const Record) []const u8 {
        return self.site_storage[0..self.site_length];
    }
};

fn store(destination: []u8, length: *u8, value: []const u8) void {
    const count = @min(value.len, destination.len);
    @memcpy(destination[0..count], value[0..count]);
    length.* = @intCast(count);
}

pub const Ledger = struct {
    records: [max_types]Record = [_]Record{.{}} ** max_types,
    count: usize = 0,
    /// Types past capacity.
    dropped: u64 = 0,
    total_throws: u64 = 0,
    total_catches: u64 = 0,
    /// The most recent exception, used to correlate a terminal event that
    /// follows it.
    last_throw_step: u64 = 0,
    last_index: ?usize = null,
    /// Steps at which the run last made observable progress. A progress mark
    /// after a catch is what promotes it to `recovered`.
    last_progress_step: u64 = 0,

    fn find(self: *Ledger, type_name: []const u8) ?*Record {
        for (self.records[0..self.count]) |*record| {
            if (std.mem.eql(u8, record.name(), type_name)) return record;
        }
        if (self.count == max_types) {
            self.dropped +|= 1;
            return null;
        }
        const record = &self.records[self.count];
        record.* = .{};
        store(&record.name_storage, &record.name_length, type_name);
        self.count += 1;
        return record;
    }

    /// Returns whether this is the first sight of the type, which is the shape
    /// worth reporting immediately.
    pub fn noteThrow(
        self: *Ledger,
        type_name: []const u8,
        throw_site: []const u8,
        code: u32,
        unwind_frames: u32,
        step: u64,
    ) bool {
        self.total_throws +|= 1;
        self.last_throw_step = step;
        const record = self.find(type_name) orelse return false;
        const first = record.throws == 0;
        record.throws +|= 1;
        record.last_step = step;
        if (first) {
            record.first_step = step;
            store(&record.site_storage, &record.site_length, throw_site);
            record.code = code;
            record.unwind_frames = unwind_frames;
        }
        record.outcome = .thrown;
        for (self.records[0..self.count], 0..) |*candidate, index| {
            if (candidate == record) self.last_index = index;
        }
        return first;
    }

    pub fn noteCaught(self: *Ledger, step: u64) void {
        self.total_catches +|= 1;
        const index = self.last_index orelse return;
        const record = &self.records[index];
        record.catches +|= 1;
        record.last_step = step;
        if (record.outcome == .thrown) record.outcome = .caught;
    }

    pub fn noteUncaught(self: *Ledger, step: u64) void {
        const index = self.last_index orelse return;
        const record = &self.records[index];
        record.outcome = .uncaught;
        record.last_step = step;
    }

    /// The run made observable progress. Promotes a recent catch to recovered,
    /// which is the only evidence that a handler did more than log.
    pub fn noteProgress(self: *Ledger, step: u64) void {
        self.last_progress_step = step;
        const index = self.last_index orelse return;
        const record = &self.records[index];
        if (record.outcome == .caught and step > record.last_step) record.outcome = .recovered;
    }

    /// A terminal event happened. Correlates it with a recent exception when
    /// one is close enough, and does nothing when it is not.
    pub fn noteTerminal(self: *Ledger, step: u64) ?Record {
        const index = self.last_index orelse return null;
        if (step < self.last_throw_step) return null;
        if (step - self.last_throw_step > correlation_window_steps) return null;
        const record = &self.records[index];
        // Progress after the catch clears the suspicion: the handler did work.
        if (record.outcome == .recovered) return null;
        record.outcome = .caught_then_terminal;
        return record.*;
    }

    /// A deferred failure was recorded: the handler abandoned the work it was
    /// protecting (e.g. code generation for a guest function failed and the
    /// function was left undefined). This is the ledger's original scenario —
    /// the unwinder completed and the program still dies at the next demand —
    /// so it correlates with a recent exception the same way a terminal event
    /// does, but at the failure site where the exception context still exists.
    /// The terminal event itself is often far outside the window, because the
    /// crash happens at the *call* to the undefined function, not at the
    /// failure that produced it.
    pub fn noteDeferredFailure(self: *Ledger, step: u64) ?Record {
        const index = self.last_index orelse return null;
        if (step < self.last_throw_step) return null;
        if (step - self.last_throw_step > deferred_failure_window_steps) return null;
        const record = &self.records[index];
        // Progress after the catch clears the suspicion: the handler did work.
        if (record.outcome == .recovered) return null;
        record.outcome = .caught_then_deferred;
        return record.*;
    }

    pub fn worst(self: *const Ledger) ?Record {
        var chosen: ?Record = null;
        for (self.records[0..self.count]) |record| {
            if (!record.outcome.concerning()) continue;
            if (chosen == null or @intFromEnum(record.outcome) > @intFromEnum(chosen.?.outcome)) {
                chosen = record;
            }
        }
        return chosen;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.total_throws == 0)
            return "no guest C++ exception has been raised, so the exception path is not part of this run's behaviour";
        if (self.worst()) |record| return record.outcome.meaning();
        return "every guest exception was caught and the run made progress afterwards. Throwing is ordinary C++ control flow and this run's exceptions are behaving as such";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "a first sight is distinguished from a recurrence" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.noteThrow("N5Xbyak5ErrorE", "Xbyak::CodeGenerator::ready", 11, 30, 100));
    try std.testing.expect(!ledger.noteThrow("N5Xbyak5ErrorE", "Xbyak::CodeGenerator::ready", 11, 30, 200));
    try std.testing.expectEqual(@as(u64, 2), ledger.records[0].throws);
    try std.testing.expectEqual(@as(u64, 100), ledger.records[0].first_step);
    try std.testing.expectEqual(@as(u32, 11), ledger.records[0].code);
}

// Throwing is ordinary C++ control flow. A ledger that reported every throw
// would be unreadable and would bury the one that matters.
test "exceptions that are caught and followed by progress are not a finding" {
    var ledger = Ledger{};
    _ = ledger.noteThrow("NSt3__112system_errorE", "some::site", 0, 12, 100);
    ledger.noteCaught(110);
    ledger.noteProgress(200);
    try std.testing.expectEqual(Outcome.recovered, ledger.records[0].outcome);
    try std.testing.expect(ledger.worst() == null);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "behaving as such") != null);
}

// The observed run: the unwinder did everything right and the process died
// anyway, because the handler abandoned the work rather than completing it.
test "a clean catch followed by a terminal event is the finding" {
    var ledger = Ledger{};
    _ = ledger.noteThrow("N5Xbyak5ErrorE", "Xbyak::CodeGenerator::ready", 11, 30, 4548004449);
    ledger.noteCaught(4548004500);
    const suspect = ledger.noteTerminal(4548008897).?;

    try std.testing.expectEqual(Outcome.caught_then_terminal, suspect.outcome);
    try std.testing.expect(suspect.outcome.concerning());
    try std.testing.expectEqualStrings("N5Xbyak5ErrorE", suspect.name());
    try std.testing.expectEqualStrings("Xbyak::CodeGenerator::ready", suspect.site());
    try std.testing.expect(std.mem.indexOf(u8, Outcome.caught_then_terminal.meaning(), "what the handler abandoned") != null);
    try std.testing.expect(std.mem.indexOf(u8, Outcome.caught_then_terminal.meaning(), "whole of the evidence") != null);
}

// Correlation is not causation, and a terminal event a long way from an
// exception is probably unrelated.
test "a terminal event outside the window is not correlated" {
    var ledger = Ledger{};
    _ = ledger.noteThrow("N5Xbyak5ErrorE", "site", 11, 30, 1000);
    ledger.noteCaught(1010);
    try std.testing.expect(ledger.noteTerminal(1000 + correlation_window_steps + 1) == null);
    try std.testing.expectEqual(Outcome.caught, ledger.records[0].outcome);
    try std.testing.expect(ledger.worst() == null);
}

test "progress after a catch clears a later terminal correlation" {
    var ledger = Ledger{};
    _ = ledger.noteThrow("N5Xbyak5ErrorE", "site", 11, 30, 1000);
    ledger.noteCaught(1010);
    ledger.noteProgress(1020);
    try std.testing.expect(ledger.noteTerminal(1030) == null);
    try std.testing.expectEqual(Outcome.recovered, ledger.records[0].outcome);
}

// The observed run: Xbyak throws while finalizing a guest function, Emplace
// catches and leaves the function undefined, and the deferred-work ledger
// records the abandonment. The terminal event (the call to the undefined
// function) is far outside the correlation window, so the deferred failure is
// the correlation that actually fires.
test "a caught exception followed by a deferred codegen failure is the finding" {
    var ledger = Ledger{};
    _ = ledger.noteThrow("N5Xbyak5ErrorE", "Xbyak::CodeArray::rewrite", 13, 32, 4547634301);
    ledger.noteCaught(4547634312);
    const suspect = ledger.noteDeferredFailure(4547833124).?;

    try std.testing.expectEqual(Outcome.caught_then_deferred, suspect.outcome);
    try std.testing.expect(suspect.outcome.concerning());
    try std.testing.expectEqualStrings("N5Xbyak5ErrorE", suspect.name());
    try std.testing.expectEqual(@as(u32, 13), suspect.code);
    try std.testing.expect(std.mem.indexOf(u8, Outcome.caught_then_deferred.meaning(), "abandoned") != null);
    try std.testing.expect(std.mem.indexOf(u8, Outcome.caught_then_deferred.meaning(), "whole of the evidence") != null);
}

test "a deferred failure outside the window is not correlated" {
    var ledger = Ledger{};
    _ = ledger.noteThrow("N5Xbyak5ErrorE", "site", 13, 30, 1000);
    ledger.noteCaught(1010);
    try std.testing.expect(ledger.noteDeferredFailure(1000 + deferred_failure_window_steps + 1) == null);
    try std.testing.expectEqual(Outcome.caught, ledger.records[0].outcome);
    try std.testing.expect(ledger.worst() == null);
}

test "progress after a catch also clears a later deferred-failure correlation" {
    var ledger = Ledger{};
    _ = ledger.noteThrow("N5Xbyak5ErrorE", "site", 13, 30, 1000);
    ledger.noteCaught(1010);
    ledger.noteProgress(1020);
    try std.testing.expect(ledger.noteDeferredFailure(1030) == null);
    try std.testing.expectEqual(Outcome.recovered, ledger.records[0].outcome);
}

test "an uncaught exception outranks every other outcome" {
    var ledger = Ledger{};
    _ = ledger.noteThrow("A", "site_a", 0, 10, 100);
    ledger.noteCaught(110);
    _ = ledger.noteTerminal(120);

    _ = ledger.noteThrow("B", "site_b", 0, 2, 200);
    ledger.noteUncaught(210);

    const worst = ledger.worst().?;
    try std.testing.expectEqualStrings("B", worst.name());
    try std.testing.expectEqual(Outcome.uncaught, worst.outcome);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "found no handler") != null);
}

// A short walk on a deep stack is the unwinder losing the frame chain, which is
// a different defect from finding no handler.
test "the unwind depth is retained so a lost frame chain is visible" {
    var ledger = Ledger{};
    _ = ledger.noteThrow("N5Xbyak5ErrorE", "site", 11, 30, 100);
    try std.testing.expectEqual(@as(u32, 30), ledger.records[0].unwind_frames);
}

test "a name or site longer than its storage is truncated rather than refused" {
    var ledger = Ledger{};
    const long_name = "N" ** 200;
    const long_site = "S" ** 300;
    try std.testing.expect(ledger.noteThrow(long_name, long_site, 0, 1, 1));
    try std.testing.expectEqual(@as(usize, max_name), ledger.records[0].name().len);
    try std.testing.expectEqual(@as(usize, max_site), ledger.records[0].site().len);
}

test "types past capacity are counted rather than dropped silently" {
    var ledger = Ledger{};
    var buffer: [8]u8 = undefined;
    var index: usize = 0;
    while (index < max_types) : (index += 1) {
        const name = std.fmt.bufPrint(&buffer, "T{d}", .{index}) catch unreachable;
        _ = ledger.noteThrow(name, "site", 0, 1, index);
    }
    try std.testing.expectEqual(@as(usize, max_types), ledger.count);
    _ = ledger.noteThrow("overflow", "site", 0, 1, 999);
    try std.testing.expectEqual(@as(u64, 1), ledger.dropped);
}

test "an empty ledger says the exception path is not part of the run" {
    const ledger = Ledger{};
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "not part of this run") != null);
    inline for (.{
        Outcome.thrown, Outcome.caught, Outcome.recovered,
        Outcome.caught_then_deferred, Outcome.caught_then_terminal, Outcome.uncaught,
    }) |outcome| {
        try std.testing.expect(outcome.label().len > 0);
        try std.testing.expect(outcome.meaning().len > 40);
    }
    try std.testing.expect(!Outcome.caught.concerning());
    try std.testing.expect(Outcome.uncaught.concerning());
}
