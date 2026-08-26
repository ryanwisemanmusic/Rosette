//! When each piece of console platform state was provisioned, by whom, and
//! whether its owner later agreed.
//!
//! The defect this was written against: Rosette provisions `VdGpuClockInMHz`
//! and `VdHSIOCalibrationLock` correctly, and does it from
//! `refreshKernelVariables`, which is reached only from a diagnostic heartbeat.
//! The heartbeat interval is a hundred million guest steps. The title reads
//! those variables during its display bring-up, several orders of magnitude
//! earlier, gets a zero, and takes its early-return path — permanently, because
//! nothing re-reads them. By the time the first heartbeat fires, the values are
//! written, the variables report `populated`, the kernel-variable ladder reports
//! no blocker, and the title has been wedged for the whole run.
//!
//! That is invisible to every "is it populated" check, because by the time
//! anyone asks, it is. The only way to see it is to record *when* the write
//! happened and compare it against when the consumer ran, which is what this
//! does.
//!
//! Keyed by kernel-export ordinal rather than by a closed enum so the same
//! ledger covers anything else that turns out to need provisioning, without a
//! second copy of the custody logic.

const std = @import("std");
const contract = @import("xenia_provisioning_contract");

pub const Owner = contract.Owner;
pub const Custody = contract.Custody;
pub const Timing = contract.Timing;
pub const Divergence = contract.Divergence;
pub const Refusal = contract.Refusal;
pub const Finding = contract.Finding;

pub const capacity: usize = 16;

pub const Record = struct {
    ordinal: u16 = 0,
    name: []const u8 = "",
    owner: Owner = .console_kernel,

    /// The harness's write.
    harness_wrote: bool = false,
    harness_value: u32 = 0,
    harness_step: u64 = 0,
    harness_writes: u32 = 0,
    /// Whether the guest had executed any instruction when the harness wrote.
    /// A write at step zero reproduces the console's own ordering and needs no
    /// argument about scheduling.
    guest_had_started: bool = false,

    /// The owner's own write, observed by seeing the storage hold a value the
    /// harness did not put there.
    owner_wrote: bool = false,
    owner_value: u32 = 0,
    owner_step: u64 = 0,

    /// The step at which something that reads this resource was first seen
    /// running. Without it, precedence is unknown and is reported as unknown.
    consumer_step: ?u64 = null,

    last_refusal: Refusal = .none,
    refusals: u32 = 0,
    /// Provisioning attempts made before the slot address was known. A large
    /// count here is the signature of a provisioner wired to a hook that runs
    /// before the export table has been read.
    address_unknown_attempts: u32 = 0,

    pub fn custody(self: Record) Custody {
        return contract.custodyOf(self.harness_wrote, self.owner_wrote, self.valuesAgree());
    }

    pub fn divergence(self: Record) Divergence {
        return contract.divergenceOf(self.harness_wrote, self.owner_wrote, self.valuesAgree());
    }

    pub fn timing(self: Record) Timing {
        return contract.timingOf(
            self.harness_wrote,
            self.harness_step,
            self.guest_had_started,
            self.consumer_step,
        );
    }

    pub fn valuesAgree(self: Record) bool {
        return self.harness_value == self.owner_value;
    }

    /// True when this record describes state the run depends on the harness
    /// for. Not a defect; a dependency that has to be stated.
    pub fn loadBearing(self: Record) bool {
        return self.custody().loadBearing();
    }
};

pub const Summary = struct {
    tracked: usize = 0,
    provisioned: usize = 0,
    preboot: usize = 0,
    late: usize = 0,
    unknown_timing: usize = 0,
    diverged: usize = 0,
    contested: usize = 0,
    adopted: usize = 0,
    load_bearing: usize = 0,
    unprovisioned: usize = 0,
    refusals: u64 = 0,
    address_unknown_attempts: u64 = 0,

    pub fn finding(self: Summary) Finding {
        // Ordered by how badly each one misleads a reader who stops at the
        // first line. A late write is worst: every other counter reads healthy.
        if (self.late != 0) return .provisioned_late;
        if (self.diverged != 0 or self.contested != 0) return .contested_ownership;
        if (self.unprovisioned != 0) return .unprovisioned_platform_state;
        if (self.load_bearing != 0) return .harness_load_bearing;
        return .healthy;
    }
};

pub const Ledger = struct {
    records: [capacity]Record = [_]Record{.{}} ** capacity,
    count: usize = 0,
    /// Resources that did not fit. Counted so the report never presents a
    /// bounded list as the whole picture.
    dropped: u64 = 0,

    fn find(self: *Ledger, ordinal: u16) ?*Record {
        for (self.records[0..self.count]) |*record| {
            if (record.ordinal == ordinal) return record;
        }
        return null;
    }

    pub fn entry(self: *const Ledger, ordinal: u16) ?Record {
        for (self.records[0..self.count]) |record| {
            if (record.ordinal == ordinal) return record;
        }
        return null;
    }

    /// Begin tracking a resource. Idempotent: calling it again updates the
    /// descriptive fields and never disturbs recorded history.
    pub fn track(self: *Ledger, ordinal: u16, name: []const u8, owner: Owner) ?*Record {
        if (ordinal == 0) return null;
        if (self.find(ordinal)) |existing| {
            existing.name = name;
            existing.owner = owner;
            return existing;
        }
        if (self.count == capacity) {
            self.dropped +|= 1;
            return null;
        }
        const record = &self.records[self.count];
        record.* = .{ .ordinal = ordinal, .name = name, .owner = owner };
        self.count += 1;
        return record;
    }

    /// Record a harness write that succeeded.
    ///
    /// `guest_steps` is the guest's instruction count at the moment of the
    /// write — zero means the guest has not run, which is the console's own
    /// ordering and the only timing that is safe without an argument.
    pub fn noteHarnessWrite(
        self: *Ledger,
        ordinal: u16,
        value: u32,
        guest_steps: u64,
    ) void {
        const record = self.find(ordinal) orelse return;
        record.harness_writes +|= 1;
        // The first write is the one that decides timing. A later rewrite of
        // the same value cannot make an early write late or a late one early.
        if (!record.harness_wrote) {
            record.harness_wrote = true;
            record.harness_step = guest_steps;
            record.guest_had_started = guest_steps != 0;
        }
        record.harness_value = value;
        record.last_refusal = .none;
    }

    pub fn noteRefusal(self: *Ledger, ordinal: u16, refusal: Refusal) void {
        const record = self.find(ordinal) orelse return;
        record.last_refusal = refusal;
        record.refusals +|= 1;
        if (refusal == .address_unknown) record.address_unknown_attempts +|= 1;
    }

    /// Record what the storage currently holds.
    ///
    /// A value the harness did not write is the owner's. This is how adoption
    /// and divergence are detected without a write hook on the address: the
    /// harness knows what it wrote, so anything else in there came from
    /// somewhere else.
    pub fn observeStorage(self: *Ledger, ordinal: u16, value: u32, guest_steps: u64) void {
        const record = self.find(ordinal) orelse return;
        if (value == 0) return;
        if (record.harness_wrote and value == record.harness_value) {
            // Indistinguishable from the harness's own write, so it proves
            // nothing about adoption and must not be recorded as the owner's.
            return;
        }
        if (!record.owner_wrote) {
            record.owner_wrote = true;
            record.owner_step = guest_steps;
        }
        record.owner_value = value;
    }

    /// Record the step at which a consumer of this resource was first seen.
    /// Only the earliest is kept: precedence is decided against the first
    /// reader, not the most recent one.
    pub fn noteConsumer(self: *Ledger, ordinal: u16, guest_steps: u64) void {
        const record = self.find(ordinal) orelse return;
        if (record.consumer_step) |existing| {
            if (guest_steps >= existing) return;
        }
        record.consumer_step = guest_steps;
    }

    /// Record one consumer boundary against every tracked resource. Used when
    /// the observed boundary — display bring-up entering its first `Vd` export
    /// — reads all of them and there is no finer attribution available.
    pub fn noteConsumerForAll(self: *Ledger, guest_steps: u64) void {
        for (self.records[0..self.count]) |*record| {
            if (record.consumer_step) |existing| {
                if (guest_steps >= existing) continue;
            }
            record.consumer_step = guest_steps;
        }
    }

    pub fn summary(self: *const Ledger) Summary {
        var totals = Summary{ .tracked = self.count };
        for (self.records[0..self.count]) |record| {
            totals.refusals +|= record.refusals;
            totals.address_unknown_attempts +|= record.address_unknown_attempts;
            if (record.harness_wrote) totals.provisioned += 1;
            switch (record.timing()) {
                .before_guest_started => totals.preboot += 1,
                .after_first_consumer => totals.late += 1,
                .unknown => totals.unknown_timing += 1,
                .before_first_consumer, .not_provisioned => {},
            }
            switch (record.custody()) {
                // Only state the harness may provision can be *missing*. A
                // title-owned zero is the title not having got there yet, and
                // counting it here reported the title's own progress as absent
                // platform state — the exact error the owner model exists to
                // prevent.
                .unprovisioned => if (record.owner.harnessMayProvision()) {
                    totals.unprovisioned += 1;
                },
                .harness_provisioned => totals.load_bearing += 1,
                .owner_adopted => totals.adopted += 1,
                .contested => totals.contested += 1,
                .owner_established => {},
            }
            if (record.divergence() == .diverged) totals.diverged += 1;
        }
        return totals;
    }

    /// The record a reader should look at first: a late write before a
    /// divergence before an unprovisioned resource. A late write outranks the
    /// others because it is the only one whose symptoms all read healthy.
    pub fn blocking(self: *const Ledger) ?Record {
        var best: ?Record = null;
        for (self.records[0..self.count]) |record| {
            const rank = severity(record);
            if (rank == 0) continue;
            const current = best orelse {
                best = record;
                continue;
            };
            if (rank > severity(current)) best = record;
        }
        return best;
    }
};

fn severity(record: Record) u8 {
    if (record.timing().missedItsConsumer()) return 4;
    if (record.divergence() == .diverged) return 3;
    if (record.custody() == .unprovisioned and record.owner.harnessMayProvision()) return 2;
    if (record.custody().loadBearing()) return 1;
    return 0;
}

test "a correct write on a diagnostic heartbeat is reported late" {
    // The live defect, reconstructed: the write is correct, the value is right,
    // and it landed a hundred million steps after the title read the zero.
    var ledger = Ledger{};
    _ = ledger.track(0x1C6, "VdGpuClockInMHz", .console_kernel);
    ledger.noteConsumer(0x1C6, 4_000_000);
    ledger.noteHarnessWrite(0x1C6, 500, 100_000_000);

    const record = ledger.entry(0x1C6).?;
    try std.testing.expectEqual(Timing.after_first_consumer, record.timing());
    try std.testing.expect(record.timing().missedItsConsumer());
    try std.testing.expectEqual(Custody.harness_provisioned, record.custody());

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.late);
    try std.testing.expectEqual(@as(usize, 1), totals.provisioned);
    try std.testing.expectEqual(Finding.provisioned_late, totals.finding());
    try std.testing.expectEqual(@as(u16, 0x1C6), ledger.blocking().?.ordinal);
}

test "the same write moved before the guest started is healthy" {
    var ledger = Ledger{};
    _ = ledger.track(0x1C6, "VdGpuClockInMHz", .console_kernel);
    ledger.noteHarnessWrite(0x1C6, 500, 0);
    ledger.noteConsumer(0x1C6, 4_000_000);

    const record = ledger.entry(0x1C6).?;
    try std.testing.expectEqual(Timing.before_guest_started, record.timing());
    try std.testing.expect(!record.timing().missedItsConsumer());

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 0), totals.late);
    try std.testing.expectEqual(@as(usize, 1), totals.preboot);
    // Nothing has adopted it, so the run depends on the harness write. That is
    // the honest reading, not "healthy".
    try std.testing.expectEqual(@as(usize, 1), totals.load_bearing);
    try std.testing.expectEqual(Finding.harness_load_bearing, totals.finding());
}

test "the owner writing the same value completes the handoff" {
    var ledger = Ledger{};
    _ = ledger.track(0x1C6, "VdGpuClockInMHz", .console_kernel);
    ledger.noteHarnessWrite(0x1C6, 500, 0);
    ledger.observeStorage(0x1C6, 500, 10_000);

    // Storage holding exactly what the harness wrote proves nothing: it is
    // indistinguishable from the harness's own write.
    try std.testing.expectEqual(Custody.harness_provisioned, ledger.entry(0x1C6).?.custody());

    // A different value is unambiguously somebody else's.
    ledger.observeStorage(0x1C6, 550, 20_000);
    const record = ledger.entry(0x1C6).?;
    try std.testing.expectEqual(Custody.contested, record.custody());
    try std.testing.expectEqual(Divergence.diverged, record.divergence());
    try std.testing.expectEqual(@as(u64, 20_000), record.owner_step);
    try std.testing.expectEqual(Finding.contested_ownership, ledger.summary().finding());
}

test "state the owner established alone is neither provisioned nor load bearing" {
    var ledger = Ledger{};
    _ = ledger.track(0x1BE, "VdGlobalDevice", .guest_title);
    ledger.observeStorage(0x1BE, 0x8200_0000, 5_000);

    const record = ledger.entry(0x1BE).?;
    try std.testing.expectEqual(Custody.owner_established, record.custody());
    try std.testing.expect(!record.loadBearing());
    try std.testing.expectEqual(Timing.not_provisioned, record.timing());
    try std.testing.expectEqual(Divergence.uncontested, record.divergence());

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 0), totals.unprovisioned);
    try std.testing.expectEqual(@as(usize, 0), totals.load_bearing);
    try std.testing.expectEqual(Finding.healthy, totals.finding());
    // A title-owned resource is never the blocker: the harness may not write it.
    try std.testing.expect(ledger.blocking() == null);
}

test "attempts made before the address is known are counted, not lost" {
    var ledger = Ledger{};
    _ = ledger.track(0x1C6, "VdGpuClockInMHz", .console_kernel);
    var attempt: u32 = 0;
    while (attempt < 5) : (attempt += 1) ledger.noteRefusal(0x1C6, .address_unknown);

    const record = ledger.entry(0x1C6).?;
    try std.testing.expectEqual(@as(u32, 5), record.address_unknown_attempts);
    try std.testing.expectEqual(Refusal.address_unknown, record.last_refusal);
    try std.testing.expectEqual(Custody.unprovisioned, record.custody());
    try std.testing.expectEqual(@as(u64, 5), ledger.summary().address_unknown_attempts);
    try std.testing.expectEqual(Finding.unprovisioned_platform_state, ledger.summary().finding());
}

test "only the first harness write decides timing" {
    var ledger = Ledger{};
    _ = ledger.track(0x1C6, "VdGpuClockInMHz", .console_kernel);
    ledger.noteHarnessWrite(0x1C6, 500, 0);
    ledger.noteConsumer(0x1C6, 4_000_000);
    // A later rewrite on a heartbeat must not make an early write look late.
    ledger.noteHarnessWrite(0x1C6, 500, 100_000_000);

    const record = ledger.entry(0x1C6).?;
    try std.testing.expectEqual(@as(u64, 0), record.harness_step);
    try std.testing.expectEqual(@as(u32, 2), record.harness_writes);
    try std.testing.expectEqual(Timing.before_guest_started, record.timing());
}

test "the earliest consumer wins and a missing one stays unknown" {
    var ledger = Ledger{};
    _ = ledger.track(0x1C6, "VdGpuClockInMHz", .console_kernel);
    ledger.noteHarnessWrite(0x1C6, 500, 50_000);
    try std.testing.expectEqual(Timing.unknown, ledger.entry(0x1C6).?.timing());

    ledger.noteConsumer(0x1C6, 90_000);
    try std.testing.expectEqual(Timing.before_first_consumer, ledger.entry(0x1C6).?.timing());
    // A later sighting must not move the boundary forwards.
    ledger.noteConsumer(0x1C6, 200_000);
    try std.testing.expectEqual(@as(u64, 90_000), ledger.entry(0x1C6).?.consumer_step.?);
    // An earlier one must.
    ledger.noteConsumer(0x1C6, 10_000);
    try std.testing.expectEqual(Timing.after_first_consumer, ledger.entry(0x1C6).?.timing());
}

test "the ledger is bounded and says so" {
    var ledger = Ledger{};
    var index: u16 = 1;
    while (index <= capacity + 4) : (index += 1) {
        _ = ledger.track(index, "resource", .console_kernel);
    }
    try std.testing.expectEqual(capacity, ledger.count);
    try std.testing.expectEqual(@as(u64, 4), ledger.dropped);
    // Re-tracking an existing ordinal must not consume another slot.
    _ = ledger.track(1, "resource", .console_kernel);
    try std.testing.expectEqual(capacity, ledger.count);
    try std.testing.expectEqual(@as(u64, 4), ledger.dropped);
}

test "a late write outranks a divergence and a divergence outranks an absence" {
    var ledger = Ledger{};
    _ = ledger.track(1, "absent", .console_kernel);
    _ = ledger.track(2, "diverged", .console_kernel);
    ledger.noteHarnessWrite(2, 500, 0);
    ledger.observeStorage(2, 999, 10);
    try std.testing.expectEqual(@as(u16, 2), ledger.blocking().?.ordinal);

    _ = ledger.track(3, "late", .console_kernel);
    ledger.noteConsumer(3, 10);
    ledger.noteHarnessWrite(3, 500, 1_000);
    try std.testing.expectEqual(@as(u16, 3), ledger.blocking().?.ordinal);
    try std.testing.expectEqual(Finding.provisioned_late, ledger.summary().finding());
}

test "a title-owned zero is not missing platform state" {
    // The live reading: VdGlobalXamDevice is title-owned and still zero, which
    // is the title not having got there yet. Reporting it as unprovisioned
    // platform state sends a reader to write a value the title owns.
    var ledger = Ledger{};
    _ = ledger.track(0x1BF, "VdGlobalXamDevice", .guest_title);
    ledger.noteRefusal(0x1BF, .not_harness_owned);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 0), totals.unprovisioned);
    try std.testing.expectEqual(Finding.healthy, totals.finding());
    try std.testing.expect(ledger.blocking() == null);

    // The same state under console-kernel ownership is a real absence.
    _ = ledger.track(0x1C6, "VdGpuClockInMHz", .console_kernel);
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().unprovisioned);
    try std.testing.expectEqual(Finding.unprovisioned_platform_state, ledger.summary().finding());
}
