//! Perform, on this machine, every host operation the emulator's behaviour
//! rests on — once, before the guest runs — and report what actually happened.
//!
//! ## Why a probe and not a check
//!
//! Everything else in this repository observes the emulator. This does the
//! opposite: it takes the operations the emulator will rely on and *performs
//! them itself*, against the real kernel, so that "Xenia mapped a page" and
//! "a page can be mapped here" become two separate facts instead of one
//! assumption.
//!
//! That distinction is the entire value. An emulator written for another
//! platform assumes a page is 4 KiB, a one-millisecond sleep is about one
//! millisecond, and a timed wait wakes near its deadline. Under translation
//! none of those has to be true, none of them fails loudly, and every one of
//! them produces its symptom somewhere else — a write watch that fires for a
//! write that did not happen, a frame limiter pacing at a third of its
//! intended rate, a bounded poll that only ever times out. Each of those has
//! been investigated as a graphics or scheduling defect.
//!
//! ## Measured, not returned
//!
//! A capability with a magnitude is verified by its magnitude, not by a return
//! code. `mprotect` returning zero while covering four times the range it was
//! given returned success and did not do what was asked; a `nanosleep(1ms)`
//! that takes twenty returned success too. So every timing probe runs several
//! times and reports the **median**, which is what a caller experiences, rather
//! than the best case, which is what a benchmark reports.
//!
//! ## Safety
//!
//! The probes only ever touch memory this module mapped itself, spawn threads
//! it joins, and sleep for single-digit milliseconds. Nothing here writes to a
//! guest address space, and a probe that cannot run is reported as `unprobed`
//! rather than assumed.

const std = @import("std");
const contract = @import("rosette_host_capability_contract");

pub const Capability = contract.Capability;
pub const Outcome = contract.Outcome;
pub const Severity = contract.Severity;
pub const Finding = contract.Finding;
pub const Summary = contract.Summary;
pub const capability_count = contract.capability_count;
pub const allCapabilities = contract.allCapabilities;

extern "c" fn mprotect(addr: [*]align(std.heap.page_size_min) u8, len: usize, prot: c_int) c_int;

/// The same call, reachable with a deliberately under-aligned address.
///
/// The aligned declaration above states the invariant every other probe holds
/// to. The granularity probe's entire question is what the kernel does with an
/// address that does *not* meet it, so it needs a binding that will carry one:
/// an `@alignCast` there would assert the answer instead of asking for it.
const mprotectAt: *const fn (addr: [*]u8, len: usize, prot: c_int) callconv(.c) c_int =
    @extern(*const fn (addr: [*]u8, len: usize, prot: c_int) callconv(.c) c_int, .{ .name = "mprotect" });

const PROT_NONE: u32 = 0x0;
const PROT_READ: u32 = 0x1;
const PROT_WRITE: u32 = 0x2;
const PROT_EXEC: u32 = 0x4;

/// The protection bits `mmap` wants, from the raw values `mprotect` takes.
/// Kept as one conversion so a probe cannot accidentally pass one to the other.
fn mapProt(raw: u32) std.posix.PROT {
    return @bitCast(raw);
}

/// Sleep on the host clock, without going through anything the guest can see.
fn hostSleep(nanoseconds: u64) void {
    var request: std.c.timespec = .{
        .sec = @intCast(nanoseconds / std.time.ns_per_s),
        .nsec = @intCast(nanoseconds % std.time.ns_per_s),
    };
    var remaining: std.c.timespec = undefined;
    // A signal can cut the sleep short. Resuming keeps the measurement about
    // the host's granularity rather than about whatever interrupted it.
    while (std.c.nanosleep(&request, &remaining) != 0) {
        request = remaining;
    }
}

/// How many times a timing probe repeats. Odd so the median is an observation
/// rather than an average of two, and small enough that the whole report costs
/// a few tens of milliseconds once.
pub const timing_samples: usize = 7;

pub const Report = struct {
    findings: [capability_count]Finding = blk: {
        var out: [capability_count]Finding = undefined;
        for (&out, 0..) |*slot, index| {
            slot.* = .{ .capability = @enumFromInt(index) };
        }
        break :blk out;
    },
    /// Wall-clock nanoseconds the whole probe took. Reported because a probe
    /// that itself took a second is a finding about the host.
    elapsed_ns: u64 = 0,

    pub fn finding(self: *const Report, capability: Capability) Finding {
        return self.findings[@intFromEnum(capability)];
    }

    fn record(
        self: *Report,
        capability: Capability,
        succeeded: bool,
        measured_value: u64,
        requested_value: u64,
        error_code: i32,
    ) void {
        self.findings[@intFromEnum(capability)] = .{
            .capability = capability,
            .outcome = contract.classify(capability, succeeded, measured_value),
            .measured_value = measured_value,
            .requested_value = requested_value,
            .error_code = error_code,
        };
    }

    /// Record a finding the prober itself cannot produce.
    ///
    /// The one capability in this shape is `guest_page_protection_fidelity`:
    /// its subject is Rosette's own protection overlay, and a module that
    /// knows nothing about the overlay must not put a verdict next to it. The
    /// owner of the mechanism exercises it and reports here, through the same
    /// classification every other row goes through, so an externally supplied
    /// finding cannot be graded on a different scale from a probed one.
    pub fn note(
        self: *Report,
        capability: Capability,
        succeeded: bool,
        measured_value: u64,
        requested_value: u64,
        error_code: i32,
    ) void {
        std.debug.assert(!capability.probedByPreflight());
        self.record(capability, succeeded, measured_value, requested_value, error_code);
    }

    /// Whether a degraded capability's shortfall has been made up. A degraded
    /// row whose compensating capability is verified is a fact about the
    /// machine; one whose compensator is missing, degraded or unprobed is a
    /// finding against the run.
    pub fn compensationHolds(self: *const Report, capability: Capability) bool {
        const paired = capability.compensatedBy() orelse return false;
        return self.finding(paired).outcome == .verified;
    }

    pub fn summary(self: *const Report) Summary {
        var out = Summary{};
        for (self.findings) |item| {
            switch (item.outcome) {
                .unprobed => continue,
                .verified => out.verified += 1,
                .degraded => {
                    out.degraded += 1;
                    if (self.compensationHolds(item.capability)) {
                        out.compensated += 1;
                    } else switch (item.capability.severity()) {
                        .foundational => out.foundational_failures += 1,
                        .fidelity => out.fidelity_failures += 1,
                        .informational => {},
                    }
                },
                .failed => {
                    out.failed += 1;
                    switch (item.capability.severity()) {
                        .foundational => out.foundational_failures += 1,
                        .fidelity => out.fidelity_failures += 1,
                        .informational => {},
                    }
                },
                .unavailable => out.unavailable += 1,
            }
            out.probed += 1;
        }
        return out;
    }

    /// The capability a reader should act on: the most severe failure, earliest
    /// in declaration order. One row, not nine.
    pub fn firstFinding(self: *const Report) ?Finding {
        var best: ?Finding = null;
        for (self.findings) |item| {
            if (item.outcome == .verified or item.outcome == .unprobed) continue;
            const held = best orelse {
                best = item;
                continue;
            };
            const item_rank = @intFromEnum(item.capability.severity());
            const held_rank = @intFromEnum(held.capability.severity());
            if (item_rank < held_rank) best = item;
        }
        return best;
    }
};

fn monotonicNanoseconds() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}

/// The middle of a small sample. What a caller experiences, as opposed to the
/// best case a benchmark would report and the worst case one scheduling hiccup
/// would produce.
fn median(samples: []u64) u64 {
    if (samples.len == 0) return 0;
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    return samples[samples.len / 2];
}

/// The smallest offset inside a mapping at which this kernel will accept a
/// protection change, which is its protection granularity.
///
/// Measured rather than derived from `std.heap.page_size_min`, because the
/// question is not what the compiler was told: it is what the kernel does with
/// a request the console's page size would produce. Darwin rejects an
/// `mprotect` whose address is not aligned to the VM map's page with `EINVAL`
/// before it changes anything, so walking the candidate alignments upward and
/// taking the first the kernel accepts is an exact reading with no fault, no
/// signal handler and no page left in a different state than it started in.
///
/// The alternative — protect one guest page and read the next one to see
/// whether it faults — measures the same number and needs a `SIGSEGV` handler
/// installed under a process that has its own. This does not.
fn probePageGranularity(report: *Report) void {
    const guest_page: usize = 4096;
    const span = std.heap.page_size_min * 4;
    const region = std.posix.mmap(
        null,
        span,
        mapProt(PROT_READ | PROT_WRITE),
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch |err| {
        report.record(.host_page_granularity, false, 0, guest_page, errorCode(err));
        return;
    };
    defer std.posix.munmap(region);

    // Candidates ascend from the console's page to the largest the mapping can
    // demonstrate. The first alignment the kernel accepts is the granularity:
    // an accepted offset of 4096 proves it will split there, and a rejection
    // proves it will not.
    var candidate: usize = guest_page;
    while (candidate <= std.heap.page_size_min) : (candidate *= 2) {
        if (candidate >= span) break;
        const at = region.ptr + candidate;
        // A no-op protection: the region is already read/write, so an accepted
        // call changes nothing and a rejected one changed nothing either.
        const result = mprotectAt(at, guest_page, @intCast(PROT_READ | PROT_WRITE));
        if (result == 0) {
            report.record(.host_page_granularity, true, candidate, guest_page, 0);
            return;
        }
    }
    // Every candidate below the host page was refused, so the host page is the
    // granularity. Reported as a measurement because the refusals are the
    // observation, not because the constant says so.
    report.record(.host_page_granularity, true, std.heap.page_size_min, guest_page, 0);
}

fn probeFixedMappingReplacement(report: *Report) void {
    const span = std.heap.page_size_min * 4;
    const region = std.posix.mmap(
        null,
        span,
        mapProt(PROT_READ | PROT_WRITE),
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch |err| {
        report.record(.fixed_mapping_replacement, false, 0, 0, errorCode(err));
        return;
    };
    defer std.posix.munmap(region);

    region[0] = 0x5A;
    const inner = region.ptr + std.heap.page_size_min;
    const replaced = std.posix.mmap(
        @alignCast(inner),
        std.heap.page_size_min,
        mapProt(PROT_READ | PROT_WRITE),
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .FIXED = true },
        -1,
        0,
    ) catch |err| {
        report.record(.fixed_mapping_replacement, false, 0, 0, errorCode(err));
        return;
    };
    // The replacement must be usable and must not have disturbed the byte
    // written outside it. A `MAP_FIXED` that succeeds and unmaps its
    // neighbours is the failure mode that surfaces as corruption.
    replaced[0] = 0xA5;
    const intact = region[0] == 0x5A and replaced[0] == 0xA5;
    report.record(.fixed_mapping_replacement, intact, 0, 0, 0);
}

fn probeProtectionCycle(report: *Report) void {
    const span = std.heap.page_size_min;
    const region = std.posix.mmap(
        null,
        span,
        mapProt(PROT_READ | PROT_WRITE),
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch |err| {
        report.record(.protection_cycle, false, 0, 0, errorCode(err));
        return;
    };
    defer std.posix.munmap(region);

    region[0] = 0x11;
    if (mprotect(region.ptr, span, @intCast(PROT_NONE)) != 0) {
        report.record(.protection_cycle, false, 0, 0, 1);
        return;
    }
    if (mprotect(region.ptr, span, @intCast(PROT_READ | PROT_WRITE)) != 0) {
        report.record(.protection_cycle, false, 0, 0, 2);
        return;
    }
    // The contents must survive the round trip. A protection cycle that
    // discards the page is how a write watch loses the ring's contents.
    report.record(.protection_cycle, region[0] == 0x11, 0, 0, 0);
}

fn probeExecutableMapping(report: *Report) void {
    const span = std.heap.page_size_min;
    const region = std.posix.mmap(
        null,
        span,
        mapProt(PROT_READ | PROT_WRITE),
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch |err| {
        report.record(.executable_mapping, false, 0, 0, errorCode(err));
        return;
    };
    defer std.posix.munmap(region);

    region[0] = 0xC3;
    // Write first, then execute. Nothing here jumps to the page: proving the
    // transition is allowed is the question, and running generated bytes in the
    // observer would make the observer a code generator.
    const promoted = mprotect(region.ptr, span, @intCast(PROT_READ | PROT_EXEC));
    report.record(.executable_mapping, promoted == 0, 0, 0, promoted);
    _ = mprotect(region.ptr, span, @intCast(PROT_READ | PROT_WRITE));
}

fn probeClockResolution(report: *Report) void {
    var samples: [timing_samples]u64 = undefined;
    for (&samples) |*slot| {
        const first = monotonicNanoseconds();
        var second = first;
        // The smallest interval the clock can distinguish is the first
        // difference it will report at all.
        var spins: u32 = 0;
        while (second == first and spins < 100_000) : (spins += 1) {
            second = monotonicNanoseconds();
        }
        slot.* = if (second > first) second - first else 0;
    }
    const measured = median(&samples);
    report.record(.monotonic_clock_resolution, measured != 0, measured, 0, 0);
}

/// How long a short sleep actually takes.
///
/// The emulator's frame limiter sleeps for 90% of a vblank interval and
/// assumes it wakes near the end of it. If a one-millisecond request routinely
/// takes twenty, the vblank pump runs at a rate nothing in the emulator
/// reports, and every guest wait paced by vblank inherits the error.
fn probeSleepGranularity(report: *Report) void {
    const requested_ns: u64 = std.time.ns_per_ms;
    var samples: [timing_samples]u64 = undefined;
    for (&samples) |*slot| {
        const before = monotonicNanoseconds();
        hostSleep(requested_ns);
        const after = monotonicNanoseconds();
        const elapsed = if (after > before) after - before else 0;
        slot.* = if (elapsed > requested_ns) (elapsed - requested_ns) / 1000 else 0;
    }
    const overshoot_us = median(&samples);
    report.record(
        .sleep_granularity,
        true,
        overshoot_us,
        requested_ns / 1000,
        0,
    );
}

/// A one-shot timed wait on the real pthread primitives.
///
/// Deliberately not Zig's own condition variable. The emulator's waits go
/// through libc++, which goes through `pthread_cond_timedwait` with an absolute
/// deadline on the realtime clock, and a probe that measured a different
/// primitive would answer a question nobody asked. Nothing ever signals this
/// condition, so every wait reaches its deadline and the deadline is the
/// measurement.
const TimedWaitProbe = struct {
    mutex: std.c.pthread_mutex_t = .{},
    condition: std.c.pthread_cond_t = .{},

    fn overshootMicroseconds(self: *TimedWaitProbe, deadline_ns: u64) u64 {
        var realtime: std.c.timespec = undefined;
        if (std.c.clock_gettime(@as(std.c.clockid_t, .REALTIME), &realtime) != 0) return 0;
        var deadline = realtime;
        const total_ns = @as(u64, @intCast(deadline.nsec)) + deadline_ns;
        deadline.sec += @intCast(total_ns / std.time.ns_per_s);
        deadline.nsec = @intCast(total_ns % std.time.ns_per_s);

        if (std.c.pthread_mutex_lock(&self.mutex) != .SUCCESS) return 0;
        const before = monotonicNanoseconds();
        _ = std.c.pthread_cond_timedwait(&self.condition, &self.mutex, &deadline);
        const after = monotonicNanoseconds();
        _ = std.c.pthread_mutex_unlock(&self.mutex);

        const elapsed = if (after > before) after - before else 0;
        return if (elapsed > deadline_ns) (elapsed - deadline_ns) / 1000 else 0;
    }
};

/// How far past its deadline a timed wait actually wakes.
///
/// This is the probe the whole module was written for. A guest wait with a
/// millisecond deadline is the emulator's most common synchronisation
/// primitive, and if it routinely blocks for much longer than it asked, a
/// producer/consumer handshake that is correct by construction stops making
/// progress — which is the exact shape of `handshake_without_progress` in the
/// wait graph, and it is not a defect in either participant.
fn probeTimedWaitFidelity(report: *Report) void {
    var waiter = TimedWaitProbe{};
    const deadline_ns: u64 = std.time.ns_per_ms;
    var samples: [timing_samples]u64 = undefined;
    for (&samples) |*slot| slot.* = waiter.overshootMicroseconds(deadline_ns);
    const overshoot_us = median(&samples);
    report.record(
        .timed_wait_fidelity,
        true,
        overshoot_us,
        deadline_ns / 1000,
        0,
    );
}

fn threadProbeBody(flag: *std.atomic.Value(u32)) void {
    flag.store(1, .release);
}

fn probeThreadCreation(report: *Report) void {
    var samples: [timing_samples]u64 = undefined;
    var length: usize = 0;
    for (&samples) |*slot| {
        var flag = std.atomic.Value(u32).init(0);
        const before = monotonicNanoseconds();
        const thread = std.Thread.spawn(.{}, threadProbeBody, .{&flag}) catch |err| {
            report.record(.thread_creation, false, 0, 0, errorCode(err));
            return;
        };
        thread.join();
        const after = monotonicNanoseconds();
        if (flag.load(.acquire) != 1) {
            report.record(.thread_creation, false, 0, 0, 0);
            return;
        }
        slot.* = if (after > before) (after - before) / 1000 else 0;
        length += 1;
    }
    report.record(.thread_creation, true, median(samples[0..length]), 0, 0);
}

/// Reserving a large contiguous range without committing it.
///
/// The emulator reserves the console's address space in one piece and relies on
/// physical/virtual aliasing across it. A host that will not give a contiguous
/// reservation forces a scattered fallback, and the aliasing then holds only
/// for the ranges that happened to land where expected.
fn probeLargeReservation(report: *Report) void {
    const span: usize = 256 * 1024 * 1024;
    const region = std.posix.mmap(
        null,
        span,
        mapProt(PROT_NONE),
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch |err| {
        report.record(.large_reservation, false, 0, span, errorCode(err));
        return;
    };
    std.posix.munmap(region);
    report.record(.large_reservation, true, 0, span, 0);
}

fn errorCode(err: anyerror) i32 {
    // The numeric value is not portable and is not meant to be: it is a
    // discriminator so two different failures of the same probe can be told
    // apart in a log.
    return @intCast(@intFromError(err));
}

/// Run every probe. Called once, before the guest runs.
pub fn probe() Report {
    var report = Report{};
    const started = monotonicNanoseconds();
    probePageGranularity(&report);
    probeFixedMappingReplacement(&report);
    probeProtectionCycle(&report);
    probeExecutableMapping(&report);
    probeClockResolution(&report);
    probeSleepGranularity(&report);
    probeTimedWaitFidelity(&report);
    probeThreadCreation(&report);
    probeLargeReservation(&report);
    const finished = monotonicNanoseconds();
    report.elapsed_ns = if (finished > started) finished - started else 0;
    return report;
}

test "an unprobed report says nothing about the host" {
    const report = Report{};
    const totals = report.summary();
    try std.testing.expectEqual(@as(u8, 0), totals.probed);
    try std.testing.expect(report.firstFinding() == null);
    try std.testing.expect(totals.foundationHolds());
}

// Every capability this module can answer, it answers. The contract names the
// exception rather than this test carrying a hand-maintained list, so a new
// capability added there is either probed here or has to declare why not.
test "every capability preflight can answer is probed and none is left unprobed" {
    const report = probe();
    var expected: u8 = 0;
    for (allCapabilities()) |capability| {
        if (!capability.probedByPreflight()) {
            try std.testing.expectEqual(Outcome.unprobed, report.finding(capability).outcome);
            continue;
        }
        expected += 1;
        try std.testing.expect(report.finding(capability).outcome != .unprobed);
    }
    const totals = report.summary();
    try std.testing.expectEqual(expected, totals.probed);
    try std.testing.expect(expected < capability_count);
}

// An overlay finding supplied by its owner is graded on exactly the scale a
// probed one would be, and it is what decides whether the host's coarser page
// is a fact or a finding.
test "an externally supplied overlay finding decides whether the host page is a finding" {
    var report = probe();
    const host_page = report.finding(.host_page_granularity);
    if (host_page.measured_value <= 4096) return; // 4 KiB host: nothing to compensate.

    try std.testing.expectEqual(Outcome.degraded, host_page.outcome);
    try std.testing.expectEqual(@as(u8, 1), report.summary().fidelity_failures);
    try std.testing.expect(!report.compensationHolds(.host_page_granularity));

    report.note(.guest_page_protection_fidelity, true, 4096, 4096, 0);
    try std.testing.expect(report.compensationHolds(.host_page_granularity));
    const compensated = report.summary();
    try std.testing.expectEqual(@as(u8, 0), compensated.fidelity_failures);
    try std.testing.expectEqual(@as(u8, 1), compensated.compensated);

    // An overlay that is itself coarse restores nothing, and both rows are
    // then degraded with the second one owning the gap.
    report.note(.guest_page_protection_fidelity, true, host_page.measured_value, 4096, 0);
    try std.testing.expect(!report.compensationHolds(.host_page_granularity));
    try std.testing.expectEqual(@as(u8, 2), report.summary().fidelity_failures);
}

// The foundational operations must actually work on any machine this can be
// built on; if one of them does not, the run has no business starting.
test "the foundational memory and thread operations work on this host" {
    const report = probe();
    try std.testing.expectEqual(
        Outcome.verified,
        report.finding(.fixed_mapping_replacement).outcome,
    );
    try std.testing.expectEqual(
        Outcome.verified,
        report.finding(.protection_cycle).outcome,
    );
    try std.testing.expectEqual(
        Outcome.verified,
        report.finding(.large_reservation).outcome,
    );
    try std.testing.expect(report.finding(.thread_creation).outcome != .failed);
}

// The magnitude is the answer, not the return code. A timing probe that
// reported success without a number would be exactly the kind of green check
// this module exists to replace.
test "timing probes carry a magnitude and what was asked for" {
    const report = probe();
    const sleep = report.finding(.sleep_granularity);
    try std.testing.expectEqual(@as(u64, 1000), sleep.requested_value);
    const wait = report.finding(.timed_wait_fidelity);
    try std.testing.expectEqual(@as(u64, 1000), wait.requested_value);
    try std.testing.expect(report.elapsed_ns != 0);
}

test "the page granularity probe reports what the kernel accepted, not a constant" {
    const report = probe();
    const page = report.finding(.host_page_granularity);
    try std.testing.expectEqual(@as(u64, 4096), page.requested_value);
    try std.testing.expect(page.measured_value >= 4096);
    // A granularity is a page size: a power of two, and never finer than the
    // console page the emulator asks for or coarser than the host's own.
    try std.testing.expect(std.math.isPowerOfTwo(page.measured_value));
    try std.testing.expect(page.measured_value <= std.heap.page_size_min);
    // The reading is a measurement, so it must be reproducible: two probes of
    // the same kernel cannot disagree.
    try std.testing.expectEqual(
        page.measured_value,
        probe().finding(.host_page_granularity).measured_value,
    );
}

test "the median is the middle observation rather than the best" {
    var samples = [_]u64{ 9, 1, 5, 3, 7 };
    try std.testing.expectEqual(@as(u64, 5), median(&samples));
}

test "the most severe failure is the one reported first" {
    var report = Report{};
    report.record(.sleep_granularity, true, 50_000, 1000, 0);
    report.record(.protection_cycle, false, 0, 0, 0);
    const first = report.firstFinding().?;
    try std.testing.expectEqual(Capability.protection_cycle, first.capability);
    try std.testing.expect(!report.summary().foundationHolds());
}
