//! What the thread that published to the command ring did next.
//!
//! `SWAP HEALTH` has been ending with the same instruction for weeks — *"the
//! guest published once and has not advanced the write pointer since; find
//! what the submitting thread is waiting on"* — and nothing in the run ever
//! answered it. The information was all there: Rosette knows which guest
//! thread crossed the write-pointer boundary, and it observes every guest wait
//! with its object, its program counter and its disposition. Nobody joined
//! them.
//!
//! ## The distinction that decides the next hour
//!
//! A producer that stopped publishing is in exactly one of two states, and
//! they call for opposite work:
//!
//! * **Parked.** It entered a wait and has not come back. Something owed it a
//!   signal and did not send one. This is a lost wakeup, it is fixable in the
//!   emulator or in Rosette, and the object it is parked on names the fix.
//! * **Cycling.** Its waits are returning — promptly, with success — and it is
//!   going round a small closed set of program counters without publishing.
//!   Nothing is broken in the wait machinery at all. The title is running a
//!   loop that is *waiting for something else*, and the answer is upstream:
//!   what has it been told it must have before it submits again?
//!
//! Those look identical in every counter the run currently prints. Both show a
//! quiet write pointer, a drained ring and a command processor with nothing to
//! do. Only the wait disposition separates them, and separating them is this
//! module's entire job.
//!
//! ## Why a small ring of samples
//!
//! Retaining every guest wait would be a second log. What a reader needs is
//! the *shape* of the recent behaviour: how many distinct objects, how many
//! distinct call sites, whether the same pair keeps recurring, and whether any
//! of it returns. Sixteen samples is enough to recognise a cycle of two or
//! three and cheap enough to keep on the hot path.

const std = @import("std");

/// How a guest wait ended, from the emulator's own report.
pub const Disposition = enum(u8) {
    /// Not yet known — the wait is still outstanding.
    outstanding,
    /// The object was already signalled on entry, so the thread never blocked.
    /// A loop made entirely of these is a spin, not a wait.
    ready_on_entry,
    /// The thread blocked and was released.
    blocked_then_released,
    /// The thread blocked and the wait timed out.
    timed_out,
    /// The thread blocked and has not come back.
    parked,

    pub fn label(self: Disposition) []const u8 {
        return switch (self) {
            .outstanding => "outstanding",
            .ready_on_entry => "ready-on-entry",
            .blocked_then_released => "released",
            .timed_out => "timed-out",
            .parked => "parked",
        };
    }

    /// Whether the thread came back from this wait. A returning wait cannot be
    /// what is holding a producer, however long the producer has been quiet.
    pub fn returned(self: Disposition) bool {
        return self == .ready_on_entry or
            self == .blocked_then_released or
            self == .timed_out;
    }
};

pub const Sample = struct {
    /// The synchronisation object, in the guest's own address space.
    object: u64 = 0,
    handle: u32 = 0,
    /// Where in guest code the wait was issued from. The call site is what
    /// makes a cycle recognisable; the object alone is not, because a job
    /// system reuses one semaphore from many places.
    pc: u64 = 0,
    disposition: Disposition = .outstanding,
    step: u64 = 0,
    duration_ms: u32 = 0,
};

pub const capacity: usize = 16;

pub const Verdict = enum(u8) {
    /// No thread has been attributed as the producer, so nothing below is
    /// about the producer.
    producer_unknown,
    /// A real publication was observed, but the publication breadcrumb did
    /// not carry the guest producer identity. Consumer activity must not be
    /// promoted into a producer attribution in this state.
    attribution_lost,
    /// The producer thread never published. There is no stall to explain.
    never_published,
    /// The write pointer is still advancing.
    publishing,
    /// The producer entered a wait and never returned. The object names the
    /// fix.
    parked,
    /// The producer's waits are returning and it is going round a closed set
    /// of call sites without publishing. The wait machinery is fine; the title
    /// is waiting on something the waits are not about.
    cycling,
    /// The producer is running and neither waiting nor publishing.
    running_without_publishing,
    /// The producer thread was last seen and has produced no observation at
    /// all since publication.
    silent,
    /// The attributed thread is silent and other guest threads are busy. The
    /// attribution is wrong, not the guest: reporting `silent` here would say
    /// the run had stopped while thousands of guest waits were being observed
    /// on threads this tracker is not watching.
    misattributed,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .producer_unknown => "producer_unknown",
            .attribution_lost => "ATTRIBUTION-LOST",
            .never_published => "never_published",
            .publishing => "publishing",
            .parked => "parked",
            .cycling => "cycling",
            .running_without_publishing => "running_without_publishing",
            .silent => "silent",
            .misattributed => "misattributed",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .producer_unknown => "no guest thread has been attributed to the ring write pointer, so nothing here is about the producer. Arm the write-pointer boundary before reading any stall verdict",
            .attribution_lost => "the ring write pointer genuinely advanced, but the publication breadcrumb did not carry a guest producer thread/PC/LR. The command-processor worker is not a valid substitute; preserve the publication and re-run with producer context enabled",
            .never_published => "the producer thread never advanced the write pointer, so there is no stall to explain. The question is what the title is doing instead of submitting, and it is upstream of every graphics counter",
            .publishing => "the producer is still advancing the write pointer. A quiet command processor is not this thread's fault",
            .parked => "the producer entered a wait and never came back. Something owed it a signal and did not send one; the object named below is the fix, and it is a lost wakeup rather than a graphics failure",
            .cycling => "the producer's waits are returning promptly and it is going round a closed set of call sites without publishing. Nothing is wrong with the wait machinery — the title is waiting for something these waits are not about, and the thing to find is what it believes it needs before submitting again. A completion route that has never delivered is the usual answer",
            .running_without_publishing => "the producer is executing and has neither waited nor published since. It is doing work that does not end in a submission",
            .silent => "the producer thread has produced no observation of any kind since it published. It may have exited",
            .misattributed => "the thread this tracker is watching has been silent since it published, and other guest threads are busy. The attribution is what is wrong: the boundary that named this thread is a command-processor entry, which runs on whichever thread performed the store rather than on the thread that owns the submission loop. Read the guest activity counts below and re-attribute before drawing any conclusion about a stalled producer",
        };
    }
};

/// A distinct call site seen in the retained window, with how often it recurred.
pub const Site = struct {
    pc: u64 = 0,
    count: u32 = 0,
};

pub const Tracker = struct {
    producer_thread: u64 = 0,
    producer_known: bool = false,
    publication_context_missing: bool = false,
    published_at_step: u64 = 0,
    publications: u64 = 0,
    /// Observations attributed to the producer thread after its last
    /// publication. Separated from the total because a busy thread before the
    /// publication says nothing about the stall.
    waits_after_publish: u64 = 0,
    returns_after_publish: u64 = 0,
    /// The newest outstanding wait, when the thread is parked in one.
    outstanding: ?Sample = null,
    samples: [capacity]Sample = [_]Sample{.{}} ** capacity,
    filled: usize = 0,
    cursor: usize = 0,
    /// The last step at which anything at all was attributed to this thread.
    last_seen_step: u64 = 0,
    /// Guest activity on threads other than the attributed producer, and how
    /// many distinct threads it came from.
    ///
    /// Without this a silent attributed thread is indistinguishable from a dead
    /// guest, and the 2026-08-31 run reported `silent` while the causal trace
    /// counted three thousand nine hundred and sixty-eight post-draw waits on
    /// other threads. One of those two readings had to be wrong and nothing in
    /// the report said which.
    elsewhere_events: u64 = 0,
    elsewhere_threads: [4]u64 = [_]u64{0} ** 4,
    elsewhere_thread_count: u8 = 0,
    /// How long the producer may be quiet before the tracker is willing to
    /// call it stalled rather than merely between submissions.
    quiet_budget: u64 = 100_000_000,

    /// Attribute the ring producer. Called with the thread that crossed the
    /// write-pointer boundary. The first attribution wins: a later thread
    /// touching the ring is a second producer and a separate question, and
    /// silently retargeting would make the wait history belong to nobody.
    pub fn attribute(self: *Tracker, thread: u64, step: u64) void {
        if (self.producer_known or thread == 0) return;
        self.producer_known = true;
        self.producer_thread = thread;
        self.published_at_step = step;
        self.last_seen_step = step;
    }

    /// Mark an observed publication whose producer identity was unavailable.
    /// This is stronger than `producer_unknown` (a run with no submission at
    /// all) but deliberately weaker than naming the consumer as producer.
    pub fn noteAttributionLost(self: *Tracker) void {
        if (!self.producer_known) self.publication_context_missing = true;
    }

    pub fn notePublication(self: *Tracker, step: u64) void {
        self.publications +|= 1;
        self.published_at_step = step;
        self.last_seen_step = step;
        // A fresh publication retires the previous window: the waits that
        // preceded it were the ones it came back from, and keeping them would
        // report a resolved stall forever.
        self.filled = 0;
        self.cursor = 0;
        self.waits_after_publish = 0;
        self.returns_after_publish = 0;
        self.outstanding = null;
    }

    /// Record a wait attributed to some guest thread. Waits from other threads
    /// are dropped here rather than at the call site, so the caller does not
    /// have to know which thread the producer is.
    pub fn observeWait(self: *Tracker, thread: u64, sample: Sample) void {
        if (!self.producer_known or thread != self.producer_thread) return;
        self.last_seen_step = sample.step;
        if (sample.step < self.published_at_step) return;
        self.waits_after_publish +|= 1;
        if (sample.disposition.returned()) {
            self.returns_after_publish +|= 1;
            self.outstanding = null;
        } else {
            self.outstanding = sample;
        }
        self.samples[self.cursor] = sample;
        self.cursor = (self.cursor + 1) % capacity;
        if (self.filled < capacity) self.filled += 1;
    }

    /// Any other sign of life from the producer: an executed boundary, a
    /// kernel call, a translation. Distinguishes `silent` from
    /// `running_without_publishing`.
    ///
    /// Activity on a *different* thread is recorded too, separately. That is
    /// what stops a silent attributed thread being reported as a dead guest.
    pub fn noteActivity(self: *Tracker, thread: u64, step: u64) void {
        if (!self.producer_known or thread == 0) return;
        if (thread == self.producer_thread) {
            if (step > self.last_seen_step) self.last_seen_step = step;
            return;
        }
        if (step < self.published_at_step) return;
        self.elsewhere_events +|= 1;
        for (self.elsewhere_threads[0..self.elsewhere_thread_count]) |known| {
            if (known == thread) return;
        }
        if (self.elsewhere_thread_count < self.elsewhere_threads.len) {
            self.elsewhere_threads[self.elsewhere_thread_count] = thread;
            self.elsewhere_thread_count += 1;
        }
    }

    pub fn busyElsewhere(self: *const Tracker) []const u64 {
        return self.elsewhere_threads[0..self.elsewhere_thread_count];
    }

    pub fn retained(self: *const Tracker) []const Sample {
        return self.samples[0..self.filled];
    }

    /// Distinct wait objects in the retained window.
    pub fn distinctObjects(self: *const Tracker) u8 {
        var total: u8 = 0;
        for (self.retained(), 0..) |sample, index| {
            var seen = false;
            for (self.retained()[0..index]) |earlier| {
                if (earlier.object == sample.object) seen = true;
            }
            if (!seen) total += 1;
        }
        return total;
    }

    /// The call sites in the retained window, most frequent first. A producer
    /// going round two sites four times each is a cycle; sixteen different
    /// sites is a thread doing varied work.
    pub fn sites(self: *const Tracker, out: []Site) []Site {
        var length: usize = 0;
        for (self.retained()) |sample| {
            var found = false;
            for (out[0..length]) |*site| {
                if (site.pc != sample.pc) continue;
                site.count += 1;
                found = true;
                break;
            }
            if (found or length >= out.len) continue;
            out[length] = .{ .pc = sample.pc, .count = 1 };
            length += 1;
        }
        const slice = out[0..length];
        std.mem.sort(Site, slice, {}, struct {
            fn greater(_: void, a: Site, b: Site) bool {
                return a.count > b.count;
            }
        }.greater);
        return slice;
    }

    /// A closed cycle: a small set of call sites, each recurring, with every
    /// wait returning. This is the shape that looks like a deadlock in the
    /// counters and is not one.
    pub fn cycling(self: *const Tracker) bool {
        if (self.filled < 4) return false;
        if (self.outstanding != null) return false;
        if (self.returns_after_publish < self.waits_after_publish) return false;
        var buffer: [capacity]Site = undefined;
        const found = self.sites(&buffer);
        if (found.len == 0 or found.len > 4) return false;
        // Every retained site must have recurred; one site seen once among
        // three that repeat is a thread passing through, not a cycle.
        for (found) |site| {
            if (site.count < 2) return false;
        }
        return true;
    }

    pub fn quietFor(self: *const Tracker, step: u64) u64 {
        if (!self.producer_known or step <= self.published_at_step) return 0;
        return step - self.published_at_step;
    }

    pub fn verdict(self: *const Tracker, step: u64) Verdict {
        if (!self.producer_known) return if (self.publication_context_missing) .attribution_lost else .producer_unknown;
        if (self.publications == 0) return .never_published;
        if (self.quietFor(step) <= self.quiet_budget) return .publishing;
        if (self.outstanding != null) return .parked;
        if (self.cycling()) return .cycling;
        if (self.waits_after_publish != 0) return .running_without_publishing;
        if (step > self.last_seen_step and step - self.last_seen_step > self.quiet_budget) {
            // Silence on the attributed thread while other guest threads are
            // busy is a fact about the attribution, not about the guest.
            return if (self.elsewhere_events != 0) .misattributed else .silent;
        }
        return .running_without_publishing;
    }
};

test "an unattributed tracker says nothing about a producer" {
    const tracker = Tracker{};
    try std.testing.expectEqual(Verdict.producer_unknown, tracker.verdict(5_000_000_000));
}

test "waits from other threads are dropped" {
    var tracker = Tracker{};
    tracker.attribute(0x7fff20f0, 100);
    tracker.notePublication(100);
    tracker.observeWait(0x7fff2040, .{ .object = 1, .pc = 2, .step = 200 });
    try std.testing.expectEqual(@as(usize, 0), tracker.retained().len);
    tracker.observeWait(0x7fff20f0, .{ .object = 1, .pc = 2, .step = 200 });
    try std.testing.expectEqual(@as(usize, 1), tracker.retained().len);
}

// The parked case: something owed a signal and did not send one.
test "an outstanding wait is a park and names its object" {
    var tracker = Tracker{};
    tracker.attribute(0x7fff20f0, 3_407_441_654);
    tracker.notePublication(3_407_441_654);
    tracker.observeWait(0x7fff20f0, .{
        .object = 0x827c_ec14,
        .handle = 0xf800_015c,
        .pc = 0x826c_72f0,
        .disposition = .parked,
        .step = 3_410_000_000,
    });
    try std.testing.expectEqual(Verdict.parked, tracker.verdict(5_000_000_000));
    try std.testing.expectEqual(@as(u64, 0x827c_ec14), tracker.outstanding.?.object);
}

// The cycling case, and the shape the observed run actually had: a producer
// alternating between two call sites, every wait returning, publishing nothing.
test "a closed set of returning waits is cycling, not a deadlock" {
    var tracker = Tracker{};
    tracker.attribute(0x7fff20f0, 3_407_441_654);
    tracker.notePublication(3_407_441_654);
    var step: u64 = 3_500_000_000;
    var index: usize = 0;
    while (index < 8) : (index += 1) {
        tracker.observeWait(0x7fff20f0, .{
            .object = if (index % 2 == 0) 0x827c_ec14 else 0x827c_ec38,
            .pc = if (index % 2 == 0) 0x826c_72f0 else 0x826c_7228,
            .disposition = .blocked_then_released,
            .step = step,
            .duration_ms = 5,
        });
        step += 10_000_000;
    }
    try std.testing.expect(tracker.cycling());
    try std.testing.expectEqual(Verdict.cycling, tracker.verdict(5_000_000_000));
    try std.testing.expectEqual(@as(u8, 2), tracker.distinctObjects());
    var buffer: [capacity]Site = undefined;
    const found = tracker.sites(&buffer);
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expectEqual(@as(u32, 4), found[0].count);
}

test "varied call sites are not a cycle" {
    var tracker = Tracker{};
    tracker.attribute(1, 0);
    tracker.notePublication(0);
    var index: u64 = 0;
    while (index < 8) : (index += 1) {
        tracker.observeWait(1, .{
            .object = index,
            .pc = 0x1000 + index,
            .disposition = .blocked_then_released,
            .step = 1_000 + index,
        });
    }
    try std.testing.expect(!tracker.cycling());
}

test "a fresh publication retires the previous window" {
    var tracker = Tracker{};
    tracker.attribute(1, 0);
    tracker.notePublication(0);
    tracker.observeWait(1, .{ .object = 1, .pc = 1, .disposition = .parked, .step = 10 });
    try std.testing.expect(tracker.outstanding != null);
    tracker.notePublication(20);
    try std.testing.expect(tracker.outstanding == null);
    try std.testing.expectEqual(@as(usize, 0), tracker.retained().len);
    try std.testing.expectEqual(Verdict.publishing, tracker.verdict(30));
}

test "a producer inside its quiet budget is still publishing" {
    var tracker = Tracker{};
    tracker.attribute(1, 1_000);
    tracker.notePublication(1_000);
    try std.testing.expectEqual(Verdict.publishing, tracker.verdict(50_000_000));
    try std.testing.expectEqual(Verdict.silent, tracker.verdict(500_000_000));
}

test "a producer that never published has no stall to explain" {
    var tracker = Tracker{};
    tracker.attribute(1, 1_000);
    try std.testing.expectEqual(Verdict.never_published, tracker.verdict(5_000_000_000));
}

test "every verdict explains itself" {
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        const value: Verdict = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.describe().len != 0);
    }
}

// The 2026-08-31 contradiction: the tracker reported `silent` while the causal
// trace counted 3968 post-draw waits on threads it was not watching.
test "silence on the attributed thread beside busy guest threads is misattribution" {
    var tracker = Tracker{};
    tracker.attribute(0x7fff20f0, 3_411_673_406);
    tracker.notePublication(3_411_673_406);
    try std.testing.expectEqual(Verdict.silent, tracker.verdict(13_900_000_000));

    tracker.noteActivity(0x7fff2140, 4_000_000_000);
    tracker.noteActivity(0x7fff2160, 4_100_000_000);
    tracker.noteActivity(0x7fff2140, 4_200_000_000);
    try std.testing.expectEqual(Verdict.misattributed, tracker.verdict(13_900_000_000));
    try std.testing.expectEqual(@as(u64, 3), tracker.elsewhere_events);
    try std.testing.expectEqual(@as(usize, 2), tracker.busyElsewhere().len);
}

// Activity on the attributed thread itself still keeps it alive rather than
// counting as somebody else's.
test "activity on the producer thread is not counted as elsewhere" {
    var tracker = Tracker{};
    tracker.attribute(1, 100);
    tracker.notePublication(100);
    tracker.noteActivity(1, 5_000_000);
    try std.testing.expectEqual(@as(u64, 0), tracker.elsewhere_events);
    try std.testing.expectEqual(@as(u64, 5_000_000), tracker.last_seen_step);
}

// Activity from before the publication says nothing about what happened after.
test "pre-publication activity elsewhere is ignored" {
    var tracker = Tracker{};
    tracker.attribute(1, 1_000);
    tracker.notePublication(1_000);
    tracker.noteActivity(2, 500);
    try std.testing.expectEqual(@as(u64, 0), tracker.elsewhere_events);
}
