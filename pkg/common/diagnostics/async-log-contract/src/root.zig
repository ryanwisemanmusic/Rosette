//! What a diagnostic transport may and may not do to the program it observes.
//!
//! Rosette's diagnostics are written from translated guest threads. Every line
//! costs the calling thread two syscalls and a global stderr mutex, so the act
//! of observing the guest changes the guest's timing — and the busier the
//! subsystem, the more it is slowed. A run that emits twenty thousand lines
//! from the GPU command path has had its GPU command path serialised twenty
//! thousand times against every other thread that logged.
//!
//! That is not a throughput complaint. It is a correctness one: a scheduler
//! defect, a wait/signal race or a livelock can be created, hidden, or moved by
//! the observer. An emulator whose logging perturbs its own scheduling cannot
//! be used to diagnose a scheduling problem, and that is the exact problem
//! under investigation.
//!
//! ## The rule that makes an async transport honest
//!
//! Moving writes to another thread solves the syscall cost and introduces a
//! worse hazard: a bounded queue that blocks when full has simply moved the
//! stall to a less predictable place. Xenia's own logger does exactly this —
//! a disruptor ring with a spin wait strategy — and under heavy logging its
//! producers spin.
//!
//! So the contract is: **a diagnostic transport must never block the observed
//! program, and must count everything it drops.** A transport that blocks is
//! not async, it is deferred-synchronous. A transport that drops silently
//! turns a truncated log into one that looks complete, which is worse than the
//! stall it was built to avoid.
//!
//! This package holds no state and performs no I/O. The ring is
//! `lib/diagnostics/async_log.zig`.

const std = @import("std");

/// How diagnostics reach their destination.
pub const Mode = enum(u8) {
    /// The calling thread performs the writes. Correct, ordered, and it makes
    /// the observer part of the observed program's critical path.
    synchronous,
    /// The calling thread buffers and writes in batches. Removes most of the
    /// syscall cost and the shared lock, and still writes on the caller's
    /// thread when a batch fills.
    batched,
    /// The calling thread hands the line to a ring and returns. A writer
    /// thread performs every syscall. The only mode in which the observed
    /// program never performs a diagnostic write.
    async_writer,

    pub fn label(self: Mode) []const u8 {
        return switch (self) {
            .synchronous => "synchronous",
            .batched => "batched",
            .async_writer => "async-writer",
        };
    }

    /// Whether the observed program can be stalled by a diagnostic write.
    pub fn stallsProducer(self: Mode) bool {
        return self != .async_writer;
    }

    pub fn meaning(self: Mode) []const u8 {
        return switch (self) {
            .synchronous => "the observed thread performs every diagnostic syscall and contends for the shared stderr lock; observation is part of the program's critical path",
            .batched => "the observed thread accumulates lines and writes them in batches; the syscall cost falls by orders of magnitude and the thread still writes when a batch fills",
            .async_writer => "the observed thread copies into a ring and returns; a writer thread performs every syscall, so no diagnostic write is on the observed program's critical path",
        };
    }
};

/// What a transport does when its queue is full.
///
/// This is the decision that separates an async transport from a deferred
/// synchronous one, and it is the reason a ring alone is not enough.
pub const Backpressure = enum(u8) {
    /// Block the producer until space exists. Bounded memory, unbounded
    /// latency: the stall moves from the write syscall to the queue, where it
    /// is harder to see and no less real.
    block_producer,
    /// Discard the line and count it. Bounded memory and bounded latency, at
    /// the cost of a gap that must be reported.
    drop_and_count,

    pub fn label(self: Backpressure) []const u8 {
        return switch (self) {
            .block_producer => "block-producer",
            .drop_and_count => "drop-and-count",
        };
    }

    /// The single rule of this package.
    pub fn preservesObservedTiming(self: Backpressure) bool {
        return self == .drop_and_count;
    }

    pub fn guidance(self: Backpressure) []const u8 {
        return switch (self) {
            .block_producer => "the producer waits for queue space, so a burst of diagnostics still stalls the observed program. This is deferred-synchronous rather than async, and it is what a spin-wait ring strategy gives you",
            .drop_and_count => "the producer never waits. A full queue costs a counted gap in the log rather than a pause in the program, which is the only trade that keeps the observer out of the observed program's timing",
        };
    }
};

/// Whether what was written is the whole story.
pub const Integrity = enum(u8) {
    /// Every line reached the destination.
    complete,
    /// Lines were dropped and counted. The log has gaps of known size.
    lossy_counted,
    /// The queue was still draining when the process ended.
    unflushed_tail,
    /// Lines were dropped and the count is not trustworthy. A transport must
    /// never reach this state; it exists so that a defect in the counter is
    /// representable rather than silently reported as `complete`.
    lossy_uncounted,

    pub fn label(self: Integrity) []const u8 {
        return switch (self) {
            .complete => "complete",
            .lossy_counted => "lossy-counted",
            .unflushed_tail => "unflushed-tail",
            .lossy_uncounted => "LOSSY-UNCOUNTED",
        };
    }

    pub fn trustworthy(self: Integrity) bool {
        return self != .lossy_uncounted;
    }

    pub fn guidance(self: Integrity) []const u8 {
        return switch (self) {
            .complete => "every line the program emitted reached the log",
            .lossy_counted => "lines were dropped because the ring filled, and the count below is exact. Absence of a diagnostic in this log is not evidence that it did not fire",
            .unflushed_tail => "the process ended with lines still queued. The tail of the log is missing and its size is known; drain before exit to close this",
            .lossy_uncounted => "lines were dropped and the drop counter is not trustworthy. No conclusion may be drawn from the absence of any line, and the transport itself is the first defect to fix",
        };
    }
};

/// Diagnostics whose loss would be worse than the stall avoided by dropping
/// them.
///
/// A crash report that is dropped because a ring was full leaves nothing to
/// diagnose, which defeats the purpose of the transport entirely. These take
/// the synchronous path regardless of mode.
pub const Priority = enum(u8) {
    /// Ordinary observation. Droppable.
    routine,
    /// A finding: a contract frontier, a verdict, a blocker. Droppable, but
    /// preferred over routine lines when the ring is under pressure.
    finding,
    /// A fault, crash or terminal diagnostic. Never dropped, never deferred.
    critical,

    pub fn label(self: Priority) []const u8 {
        return switch (self) {
            .routine => "routine",
            .finding => "finding",
            .critical => "critical",
        };
    }

    /// Whether this line may be discarded when the ring is full.
    pub fn droppable(self: Priority) bool {
        return self != .critical;
    }

    /// Whether this line must be written on the calling thread even in async
    /// mode. A crash must not be queued behind a writer thread that may never
    /// run again.
    pub fn requiresSynchronousWrite(self: Priority) bool {
        return self == .critical;
    }
};

/// Ring geometry. Fixed slots rather than a byte stream: a slotted ring lets a
/// producer claim its space with one atomic increment and lets the writer
/// find record boundaries without parsing, which is what keeps the producer
/// path free of both locks and syscalls.
pub const default_slot_bytes: usize = 1024;
pub const default_slot_count: usize = 8192;

/// The largest line a single slot carries. Anything longer is truncated with a
/// marker and counted, because losing the tail of a diagnostic is recoverable
/// and losing the fact that it fired is not.
pub fn payloadCapacity(slot_bytes: usize) usize {
    return slot_bytes - slot_header_bytes;
}

/// Length plus the publication flag the writer thread reads.
pub const slot_header_bytes: usize = 8;

pub fn ringBytes(slot_bytes: usize, slot_count: usize) usize {
    return slot_bytes * slot_count;
}

pub fn integrityOf(dropped: u64, queued_at_exit: u64, counter_trustworthy: bool) Integrity {
    if (!counter_trustworthy) return .lossy_uncounted;
    if (dropped != 0) return .lossy_counted;
    if (queued_at_exit != 0) return .unflushed_tail;
    return .complete;
}

pub fn contractIsWellFormed() bool {
    // The whole point: only the async writer keeps the observed program off the
    // write path, and only dropping keeps it off the queue.
    if (Mode.synchronous.stallsProducer() != true) return false;
    if (Mode.batched.stallsProducer() != true) return false;
    if (Mode.async_writer.stallsProducer() != false) return false;
    if (Backpressure.block_producer.preservesObservedTiming()) return false;
    if (!Backpressure.drop_and_count.preservesObservedTiming()) return false;

    // A crash diagnostic must never be queued or discarded.
    if (Priority.critical.droppable()) return false;
    if (!Priority.critical.requiresSynchronousWrite()) return false;
    if (!Priority.routine.droppable()) return false;
    if (Priority.finding.requiresSynchronousWrite()) return false;

    if (integrityOf(0, 0, true) != .complete) return false;
    if (integrityOf(5, 0, true) != .lossy_counted) return false;
    if (integrityOf(0, 5, true) != .unflushed_tail) return false;
    if (integrityOf(0, 0, false) != .lossy_uncounted) return false;
    if (!Integrity.lossy_counted.trustworthy()) return false;
    if (Integrity.lossy_uncounted.trustworthy()) return false;

    if (payloadCapacity(default_slot_bytes) + slot_header_bytes != default_slot_bytes) return false;
    if (ringBytes(default_slot_bytes, default_slot_count) != 8 * 1024 * 1024) return false;
    // A power-of-two slot count is what lets the producer mask instead of
    // dividing on the hot path.
    if (default_slot_count & (default_slot_count - 1) != 0) return false;
    return true;
}

test "only the async writer keeps the observed program off the write path" {
    try std.testing.expect(Mode.synchronous.stallsProducer());
    try std.testing.expect(Mode.batched.stallsProducer());
    try std.testing.expect(!Mode.async_writer.stallsProducer());
    try std.testing.expect(std.mem.indexOf(u8, Mode.synchronous.meaning(), "critical path") != null);
}

test "a blocking ring is deferred-synchronous, not async" {
    // The hazard this package exists to name: a bounded queue with a spin wait
    // moves the stall somewhere harder to see and no less real.
    try std.testing.expect(!Backpressure.block_producer.preservesObservedTiming());
    try std.testing.expect(Backpressure.drop_and_count.preservesObservedTiming());
    try std.testing.expect(std.mem.indexOf(u8, Backpressure.block_producer.guidance(), "deferred-synchronous") != null);
}

test "a crash diagnostic is never queued and never dropped" {
    try std.testing.expect(!Priority.critical.droppable());
    try std.testing.expect(Priority.critical.requiresSynchronousWrite());
    // A finding is droppable but must not be forced onto the caller's thread:
    // that would put the report path back into the program's timing.
    try std.testing.expect(Priority.finding.droppable());
    try std.testing.expect(!Priority.finding.requiresSynchronousWrite());
}

test "a dropped line makes the log lossy and says so" {
    try std.testing.expectEqual(Integrity.complete, integrityOf(0, 0, true));
    try std.testing.expectEqual(Integrity.lossy_counted, integrityOf(1, 0, true));
    try std.testing.expect(std.mem.indexOf(u8, Integrity.lossy_counted.guidance(), "not evidence") != null);

    // Dropping outranks an unflushed tail: a gap in the middle misleads more
    // than a missing end.
    try std.testing.expectEqual(Integrity.lossy_counted, integrityOf(1, 5, true));
}

test "an untrustworthy counter is representable rather than reported as complete" {
    try std.testing.expectEqual(Integrity.lossy_uncounted, integrityOf(0, 0, false));
    try std.testing.expect(!Integrity.lossy_uncounted.trustworthy());
    try std.testing.expect(std.mem.indexOf(u8, Integrity.lossy_uncounted.guidance(), "No conclusion") != null);
}

test "the ring geometry masks instead of dividing" {
    try std.testing.expectEqual(@as(usize, 8 * 1024 * 1024), ringBytes(default_slot_bytes, default_slot_count));
    try std.testing.expectEqual(@as(usize, 0), default_slot_count & (default_slot_count - 1));
    try std.testing.expectEqual(default_slot_bytes - slot_header_bytes, payloadCapacity(default_slot_bytes));
    try std.testing.expect(contractIsWellFormed());
}

test "every vocabulary member carries a label and guidance" {
    inline for (@typeInfo(Mode).@"enum".fields) |field| {
        const value: Mode = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.meaning().len > 40);
    }
    inline for (@typeInfo(Backpressure).@"enum".fields) |field| {
        const value: Backpressure = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 40);
    }
    inline for (@typeInfo(Integrity).@"enum".fields) |field| {
        const value: Integrity = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 25);
    }
    inline for (@typeInfo(Priority).@"enum".fields) |field| {
        const value: Priority = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
}
