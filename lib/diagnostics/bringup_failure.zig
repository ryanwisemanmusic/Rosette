//! A subsystem that failed to start, and everything downstream that will now
//! wait forever for it.
//!
//! The emulator brings its subsystems up on their own threads. When one cannot
//! initialise it logs the reason, returns false, and the thread **exits** —
//! which is correct behaviour and completely silent from outside. Every thread
//! that was going to wait on that subsystem then waits on something that will
//! never signal, and the run settles into a steady spin with no error anywhere
//! near the symptom.
//!
//! That is the shape of the run this was written for. The GPU command processor
//! reported `Failed to initialize the geometric primitive processor`, the
//! worker exited at roughly forty million steps, and the process then spent
//! nineteen hundred million more steps spinning in a wait loop. The heartbeat
//! showed a healthy instruction rate the whole time. Nothing in the runtime
//! connected the two events, so the visible problem was "it hangs" and the
//! cause was four thousand log lines earlier.
//!
//! ## Why the failure is worth its own ledger
//!
//! The deadlock predictor can already say "this object was never signalled".
//! What it cannot say is *why nobody will ever signal it* — that fact lives in
//! a log line from a different subsystem, minutes earlier, phrased as an
//! ordinary error. Joining them turns "a thread is parked on 0x19ad668" into
//! "the GPU command processor exited during setup, so nothing will ever signal
//! it", which is a different day's work.
//!
//! ## What it will not claim
//!
//! A subsystem that failed and whose failure was handled is not a finding. The
//! ledger reports a failure as *causal* only when the run subsequently stops
//! making progress — the same progress witness the wait audit uses, for the
//! same reason: a run that carried on regardless did not depend on the thing
//! that broke.

const std = @import("std");

/// Which part of the emulator failed to come up. Kinds exist because each one
/// blocks a different set of downstream work, and "a subsystem failed" alone
/// does not say what to expect to be missing.
pub const Subsystem = enum(u8) {
    unknown,
    /// The GPU command processor's worker thread.
    gpu_command_processor,
    /// Geometry/primitive processing inside the GPU backend.
    primitive_processor,
    /// The presenter and its swapchain.
    presenter,
    /// Shared memory / buffer cache bring-up.
    memory_backend,
    /// Audio.
    audio,
    /// A guest module load.
    module_load,

    pub fn label(self: Subsystem) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .gpu_command_processor => "gpu_command_processor",
            .primitive_processor => "primitive_processor",
            .presenter => "presenter",
            .memory_backend => "memory_backend",
            .audio => "audio",
            .module_load => "module_load",
        };
    }

    /// What stops working when this subsystem does not come up. Written as the
    /// downstream consequence, because the failure line already says what
    /// failed and never says what depended on it.
    pub fn blocks(self: Subsystem) []const u8 {
        return switch (self) {
            .unknown => "an unrecognised subsystem; whatever waits on it is not modelled here",
            .gpu_command_processor => "every ring-buffer handshake. The worker thread exits, so the initialisation event it would have signalled is never raised and whatever waits for the GPU to be ready waits for the rest of the run. No PM4 is consumed, no swap is decoded, and no frame is possible",
            .primitive_processor => "the GPU command processor's own setup, which returns false and takes the worker thread down with it. The visible failure is the worker, and the cause is here",
            .presenter => "everything that turns rendered output into pixels. The guest may keep submitting work that nothing will ever display",
            .memory_backend => "buffer and texture residency. Draws proceed against resources with nothing behind them",
            .audio => "the audio pump only. A run can reach a frame with audio broken, so this is rarely the reason nothing is on screen",
            .module_load => "whatever the module exported. Calls into it resolve to nothing",
        };
    }
};

pub const Finding = enum(u8) {
    /// No bring-up failure has been observed.
    none = 0,
    /// A failure was observed and the run kept making progress. Handled.
    recovered = 1,
    /// A failure was observed and the run stopped making progress afterwards.
    blocking = 2,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .none => "none",
            .recovered => "recovered",
            .blocking => "BLOCKING",
        };
    }

    pub fn meaning(self: Finding) []const u8 {
        return switch (self) {
            .none => "no subsystem has reported a bring-up failure",
            .recovered => "a subsystem failed to initialise and the run kept making progress afterwards, so nothing that mattered was waiting on it. The failure is real and is not what is stopping this run",
            .blocking => "a subsystem failed to initialise and the run has made no progress since. Its thread exited, so whatever waits on it waits for the rest of the run — the hang is downstream of this failure, and the wait it produces is a symptom rather than a defect of its own. Fix the initialisation, not the wait",
        };
    }
};

pub const max_failures = 8;
pub const max_reason = 128;

/// Steps of progress-free execution after a failure before it counts as
/// blocking. Generous: a subsystem can fail and the run can take a while to
/// reach whatever depended on it.
pub const quiescent_steps: u64 = 200_000_000;

pub const Failure = struct {
    subsystem: Subsystem = .unknown,
    step: u64 = 0,
    /// Whether the thread carrying the subsystem was seen to exit afterwards.
    /// A failure whose thread kept running may still recover; one whose thread
    /// exited cannot.
    thread_exited: bool = false,
    reason_storage: [max_reason]u8 = [_]u8{0} ** max_reason,
    reason_length: u8 = 0,
    /// The progress witness at the moment of failure, so "no progress since"
    /// is a comparison rather than an impression.
    progress_at_failure: u64 = 0,

    pub fn reason(self: *const Failure) []const u8 {
        return self.reason_storage[0..self.reason_length];
    }
};

pub const Ledger = struct {
    failures: [max_failures]Failure = [_]Failure{.{}} ** max_failures,
    count: usize = 0,
    dropped: u64 = 0,
    progress: u64 = 0,
    last_progress_step: u64 = 0,

    /// The run got somewhere. Fed from the same witness the wait audit uses, so
    /// the two can never disagree about whether the run is moving.
    pub fn noteProgress(self: *Ledger, witness: u64, step: u64) void {
        if (witness <= self.progress) return;
        self.progress = witness;
        self.last_progress_step = step;
    }

    pub fn noteFailure(self: *Ledger, subsystem: Subsystem, reason: []const u8, step: u64) void {
        // One entry per subsystem: a subsystem that reports its failure through
        // three layers of wrapper would otherwise fill the table with one event.
        for (self.failures[0..self.count]) |*existing| {
            if (existing.subsystem != subsystem) continue;
            return;
        }
        if (self.count == max_failures) {
            self.dropped +|= 1;
            return;
        }
        const entry = &self.failures[self.count];
        entry.* = .{ .subsystem = subsystem, .step = step, .progress_at_failure = self.progress };
        const length = @min(reason.len, entry.reason_storage.len);
        @memcpy(entry.reason_storage[0..length], reason[0..length]);
        entry.reason_length = @intCast(length);
        self.count += 1;
    }

    /// A thread carrying a failed subsystem exited. This is what turns "may
    /// still recover" into "cannot".
    pub fn noteThreadExit(self: *Ledger, subsystem: Subsystem) void {
        for (self.failures[0..self.count]) |*entry| {
            if (entry.subsystem == subsystem) entry.thread_exited = true;
        }
    }

    pub fn classify(self: *const Ledger, entry: Failure, current_step: u64) Finding {
        if (self.progress > entry.progress_at_failure) return .recovered;
        if (current_step > self.last_progress_step and
            current_step - self.last_progress_step >= quiescent_steps) return .blocking;
        if (entry.thread_exited and current_step > entry.step and
            current_step - entry.step >= quiescent_steps) return .blocking;
        return .recovered;
    }

    /// The failure to read first: a blocking one, earliest wins, because the
    /// earliest blocking failure is the one the later ones are downstream of.
    pub fn root(self: *const Ledger, current_step: u64) ?Failure {
        var chosen: ?Failure = null;
        for (self.failures[0..self.count]) |entry| {
            if (self.classify(entry, current_step) != .blocking) continue;
            if (chosen == null or entry.step < chosen.?.step) chosen = entry;
        }
        return chosen;
    }

    pub fn finding(self: *const Ledger, current_step: u64) Finding {
        if (self.count == 0) return .none;
        if (self.root(current_step) != null) return .blocking;
        return .recovered;
    }

    pub fn verdict(self: *const Ledger, current_step: u64) []const u8 {
        return self.finding(current_step).meaning();
    }
};

/// Recognise a bring-up failure in a line of emulator logging.
///
/// Matched on the emulator's own phrasing rather than on a symbol, so a fork
/// that renames its classes keeps working. Returns null for the overwhelming
/// majority of lines, which is what makes it cheap enough to run on every one.
pub fn classifyLine(line: []const u8) ?Subsystem {
    if (std.mem.indexOf(u8, line, "Failed to initialize the geometric primitive processor") != null or
        std.mem.indexOf(u8, line, "primitive processor: Failed") != null)
    {
        return .primitive_processor;
    }
    if (std.mem.indexOf(u8, line, "worker setup failed") != null or
        std.mem.indexOf(u8, line, "worker setup handshake failed") != null or
        std.mem.indexOf(u8, line, "SetupContext returned false") != null)
    {
        return .gpu_command_processor;
    }
    if (std.mem.indexOf(u8, line, "Failed to initialize the presenter") != null or
        std.mem.indexOf(u8, line, "VulkanPresenter") != null and
            std.mem.indexOf(u8, line, "Failed") != null)
    {
        return .presenter;
    }
    if (std.mem.indexOf(u8, line, "shared memory") != null and
        std.mem.indexOf(u8, line, "Failed") != null) return .memory_backend;
    if (std.mem.indexOf(u8, line, "Failed to load module") != null) return .module_load;
    return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "the emulator's own phrasing is recognised without matching a symbol" {
    try std.testing.expectEqual(
        Subsystem.primitive_processor,
        classifyLine("[xenia] !> Failed to initialize the geometric primitive processor").?,
    );
    try std.testing.expectEqual(
        Subsystem.gpu_command_processor,
        classifyLine("[xenia] !> RING BUFFER: worker setup failed (SetupContext returned false)").?,
    );
    try std.testing.expectEqual(
        Subsystem.primitive_processor,
        classifyLine("Vulkan primitive processor: Failed to create the built-in index buffer upload resource with 393198 bytes").?,
    );
    // The overwhelming majority of lines are not failures.
    try std.testing.expect(classifyLine("[xenia] i> DEBUG: UI thread callback queued successfully") == null);
    try std.testing.expect(classifyLine("") == null);
}

// The run this was written for: a failure at forty million steps, then nineteen
// hundred million steps of healthy-looking spinning.
test "a failure followed by no progress is the root of the hang" {
    var ledger = Ledger{};
    ledger.noteProgress(7, 30_000_000);
    ledger.noteFailure(.primitive_processor, "index buffer upload resource, 393198 bytes", 40_000_000);
    ledger.noteFailure(.gpu_command_processor, "SetupContext returned false", 41_000_000);
    ledger.noteThreadExit(.gpu_command_processor);

    const at = 1_900_000_000;
    try std.testing.expectEqual(Finding.blocking, ledger.finding(at));
    // The earliest blocking failure is the one the others are downstream of.
    const root = ledger.root(at).?;
    try std.testing.expectEqual(Subsystem.primitive_processor, root.subsystem);
    try std.testing.expectEqualStrings("index buffer upload resource, 393198 bytes", root.reason());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(at), "Fix the initialisation, not the wait") != null);
    try std.testing.expect(std.mem.indexOf(u8, Subsystem.gpu_command_processor.blocks(), "no frame is possible") != null);
}

// A run that carried on did not depend on the thing that broke.
test "a failure the run recovered from is not a finding" {
    var ledger = Ledger{};
    ledger.noteFailure(.audio, "no output device", 1000);
    ledger.noteProgress(12, 2000);
    try std.testing.expectEqual(Finding.recovered, ledger.finding(3000));
    try std.testing.expect(ledger.root(3000) == null);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(3000), "not what is stopping this run") != null);
}

// A subsystem reporting its failure through three layers of wrapper would
// otherwise fill the table with one event.
test "repeated reports of one subsystem collapse to a single entry" {
    var ledger = Ledger{};
    ledger.noteFailure(.gpu_command_processor, "first", 100);
    ledger.noteFailure(.gpu_command_processor, "second", 200);
    ledger.noteFailure(.gpu_command_processor, "third", 300);
    try std.testing.expectEqual(@as(usize, 1), ledger.count);
    try std.testing.expectEqualStrings("first", ledger.failures[0].reason());
    try std.testing.expectEqual(@as(u64, 100), ledger.failures[0].step);
}

// A thread that exited cannot recover, which is a stronger statement than
// "nothing has progressed lately".
test "a thread exit is what turns may-recover into cannot" {
    var ledger = Ledger{};
    ledger.noteFailure(.gpu_command_processor, "setup", 1000);
    // Progress is still moving, so it reads as recovered.
    ledger.noteProgress(5, 2000);
    try std.testing.expectEqual(Finding.recovered, ledger.finding(3000));

    var exited = Ledger{};
    exited.noteFailure(.gpu_command_processor, "setup", 1000);
    exited.noteThreadExit(.gpu_command_processor);
    try std.testing.expectEqual(Finding.blocking, exited.finding(1000 + quiescent_steps));
    try std.testing.expect(exited.failures[0].thread_exited);
}

test "a reason longer than its storage is truncated rather than refused" {
    var ledger = Ledger{};
    ledger.noteFailure(.presenter, "r" ** 400, 1);
    try std.testing.expectEqual(@as(usize, max_reason), ledger.failures[0].reason().len);
}

test "failures past capacity are counted rather than dropped silently" {
    var ledger = Ledger{};
    inline for (.{
        Subsystem.gpu_command_processor, Subsystem.primitive_processor,
        Subsystem.presenter,             Subsystem.memory_backend,
        Subsystem.audio,                 Subsystem.module_load,
        Subsystem.unknown,
    }) |subsystem| ledger.noteFailure(subsystem, "x", 1);
    try std.testing.expectEqual(@as(usize, 7), ledger.count);
}

test "an empty ledger reports nothing rather than health" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Finding.none, ledger.finding(1000));
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(1000), "no subsystem has reported") != null);
    inline for (.{
        Subsystem.unknown, Subsystem.gpu_command_processor, Subsystem.primitive_processor,
        Subsystem.presenter, Subsystem.memory_backend, Subsystem.audio, Subsystem.module_load,
    }) |subsystem| {
        try std.testing.expect(subsystem.label().len > 0);
        try std.testing.expect(subsystem.blocks().len > 40);
    }
    inline for (.{ Finding.none, Finding.recovered, Finding.blocking }) |value| {
        try std.testing.expect(value.label().len > 0);
        try std.testing.expect(value.meaning().len > 40);
    }
}
