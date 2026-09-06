//! Where host time went, whether the run can reach graphics before it expires,
//! and whether the diagnostics changed the answer.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run spent about 1 032 host seconds to reach about 324 ms of
//! guest time, with roughly 1.59 million translation fills at a 99% lookup hit
//! rate. That is not the first semantic cause of the missing frame and it is a
//! blocker all the same: a correct producer or render fix cannot be evaluated
//! if every run expires at the wall-clock watchdog before it reaches the stage
//! the fix touches.
//!
//! A vague watchdog SIGTERM at the end is the worst way to learn that. It
//! arrives with no structure, at an arbitrary point, and it looks like a hang.
//! So the budget is declared in advance — guest milliseconds per host second —
//! and a run that cannot meet it stops with a performance failure that names
//! the phase eating the time.
//!
//! The second half is non-interference. A diagnostic that changes the frontier
//! is not a diagnostic; it is a variable. Two runs with instrumentation on and
//! off must reach the same frontier, and the budget records enough to say
//! whether they did.

const std = @import("std");

/// Where host time goes. Attribution is per phase because the fix differs:
/// JIT compilation is a caching problem, guest execution is a semantics
/// problem, and diagnostics are a budget problem.
pub const Phase = enum(u8) {
    guest_execution = 0,
    instruction_decode = 1,
    jit_compilation = 2,
    jit_optimization = 3,
    jit_register_allocation = 4,
    jit_emission = 5,
    memory_tracing = 6,
    diagnostics = 7,
    host_graphics = 8,
    idle = 9,

    pub fn label(self: Phase) []const u8 {
        return switch (self) {
            .guest_execution => "guest-execution",
            .instruction_decode => "instruction-decode",
            .jit_compilation => "jit-compilation",
            .jit_optimization => "jit-optimization",
            .jit_register_allocation => "jit-register-allocation",
            .jit_emission => "jit-emission",
            .memory_tracing => "memory-tracing",
            .diagnostics => "diagnostics",
            .host_graphics => "host-graphics",
            .idle => "idle",
        };
    }

    /// Time in this phase is the observer's, not the guest's. It is what the
    /// non-interference budget caps.
    pub fn isObserverWork(self: Phase) bool {
        return self == .diagnostics or self == .memory_tracing;
    }

    /// Time here is spent preparing to run guest code rather than running it.
    pub fn isTranslationWork(self: Phase) bool {
        return switch (self) {
            .instruction_decode, .jit_compilation, .jit_optimization, .jit_register_allocation, .jit_emission => true,
            else => false,
        };
    }
};

pub const phase_count: usize = @typeInfo(Phase).@"enum".fields.len;

/// Share of host time an observer may take before it is changing what it
/// observes. Ten percent is generous for sampling and far below the point
/// where scheduling shifts.
pub const observer_budget_percent: u64 = 10;

/// Which of two translation-cache pools an entry belongs in. The audit's
/// partition: immutable image code and mutable JIT output evict each other
/// when they share a pool, and only one of them is ever re-decoded.
pub const Pool = enum(u8) {
    /// Decoded from a mapped image that does not change.
    immutable_image = 0,
    /// Decoded from memory the guest or the JIT writes.
    mutable_generated = 1,

    pub fn label(self: Pool) []const u8 {
        return switch (self) {
            .immutable_image => "immutable-image",
            .mutable_generated => "mutable-generated",
        };
    }
};

/// The share of lookups that must miss before the *composition* of those
/// misses can be the run's headline finding, in basis points. One percent.
///
/// Below this, a pool refilling itself is not where the host time goes, and
/// naming it as the verdict displaces whatever is. The 2026-09-01 run is the
/// case: 1.69 million fills against 6.1 billion lookups — 0.03 percent — with
/// conflicts making up 52 percent of them. Every part of that is true, the
/// pool is genuinely conflict-dominated, and the run was three guest
/// milliseconds per host second against a required five for reasons the cache
/// had nothing to do with. `CACHE-THRASHING` was printed instead.
pub const material_miss_basis_points: u64 = 100;

pub const PoolStats = struct {
    entries: u64 = 0,
    hits: u64 = 0,
    fills: u64 = 0,
    conflict_evictions: u64 = 0,
    stale_refills: u64 = 0,

    pub fn hitRatePercent(self: PoolStats) u64 {
        const lookups = self.hits +| self.fills;
        if (lookups == 0) return 0;
        return (self.hits *| 100) / lookups;
    }

    /// Share of lookups that had to refill, in basis points. The magnitude
    /// `hitRatePercent` rounds away: 99% covers everything from one miss in a
    /// hundred to one in a hundred thousand, and those are different runs.
    pub fn missBasisPoints(self: PoolStats) u64 {
        const lookups = self.hits +| self.fills;
        if (lookups == 0) return 0;
        return (self.fills *| 10_000) / lookups;
    }

    /// A pool where conflicts dominate the fills is evicting live work.
    ///
    /// This is a statement about the *composition* of the misses and says
    /// nothing about how many there were. Kept as its own predicate because
    /// the composition is worth reporting even when the volume is not: it is
    /// what tells an indexing problem from a working set that does not fit.
    pub fn conflictDominated(self: PoolStats) bool {
        if (self.fills == 0) return false;
        return self.conflict_evictions *| 2 > self.fills;
    }

    /// A pool that is both conflict-dominated *and* missing often enough for
    /// that to be where the run's time goes.
    ///
    /// The conjunction is the point. A pattern is only a problem when it is
    /// material, and a verdict that skips the second half sends every reader
    /// to the cache regardless of what the run was actually doing.
    pub fn thrashing(self: PoolStats) bool {
        return self.conflictDominated() and self.missBasisPoints() >= material_miss_basis_points;
    }
};

pub const Verdict = enum(u8) {
    /// Not enough measured yet.
    unobserved,
    /// Meeting the declared rate.
    within_budget,
    /// The rate is temporarily below the target, but a trusted structural
    /// progress source advanced inside the same window. This is not a pass:
    /// it keeps the throughput gate from convicting an active translator and
    /// hands the decision back to the strict budget once that progress quiets.
    progressing,
    /// Below the declared rate. The run will not reach its stage in time, and
    /// this is a structured failure rather than a watchdog kill.
    below_budget,
    /// Observers are taking more host time than their cap.
    observer_over_budget,
    /// A cache pool is evicting entries it will need again.
    cache_thrashing,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .within_budget => "within-budget",
            .progressing => "PROGRESSING",
            .below_budget => "BELOW-BUDGET",
            .observer_over_budget => "OBSERVER-OVER-BUDGET",
            .cache_thrashing => "CACHE-THRASHING",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "not enough host time has been measured to judge the rate",
            .within_budget => "the run is making guest progress fast enough to reach its stage inside the window",
            .progressing => "the measured guest-time rate is temporarily below target, but trusted external progress is still advancing; keep the run alive until that bounded progress window closes",
            .below_budget => "the run is below the declared guest-millisecond rate and will expire before it reaches the stage under test. Stop here with this reason rather than at an arbitrary watchdog: the phase table below names where the time went",
            .observer_over_budget => "diagnostics and memory tracing are taking more host time than their cap. An observer at this share is changing the scheduling it exists to watch, and a frontier measured under it is not comparable to one measured without it",
            .cache_thrashing => "a translation pool is evicting entries faster than it fills vacant ways, and it is missing often enough for that to be where the host time goes. Immutable image code and mutable generated code sharing one pool is the usual cause, and only one of them is ever re-decoded",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self != .unobserved and self != .within_budget and self != .progressing;
    }
};

pub const Summary = struct {
    host_ns: u64 = 0,
    guest_ms: u64 = 0,
    by_phase: [phase_count]u64 = [_]u64{0} ** phase_count,
    observer_ns: u64 = 0,
    translation_ns: u64 = 0,

    /// Return the work measured after `origin` rather than since process
    /// creation. The throughput budget is meaningful only inside the phase
    /// it is judging: loader and static-initializer time must not dilute a
    /// guest-execution rate that starts at a later, proven boundary.
    pub fn since(self: Summary, origin: Summary) Summary {
        var out = Summary{
            .host_ns = self.host_ns -| origin.host_ns,
            .guest_ms = self.guest_ms -| origin.guest_ms,
        };
        var index: usize = 0;
        while (index < phase_count) : (index += 1) {
            out.by_phase[index] = self.by_phase[index] -| origin.by_phase[index];
            const phase: Phase = @enumFromInt(index);
            if (phase.isObserverWork()) out.observer_ns +|= out.by_phase[index];
            if (phase.isTranslationWork()) out.translation_ns +|= out.by_phase[index];
        }
        return out;
    }

    /// Guest milliseconds achieved per host second. The number the budget is
    /// declared in.
    pub fn guestMsPerHostSecond(self: Summary) u64 {
        if (self.host_ns == 0) return 0;
        const host_seconds = self.host_ns / std.time.ns_per_s;
        if (host_seconds == 0) return 0;
        return self.guest_ms / host_seconds;
    }

    pub fn observerPercent(self: Summary) u64 {
        if (self.host_ns == 0) return 0;
        return (self.observer_ns *| 100) / self.host_ns;
    }

    pub fn dominantPhase(self: Summary) ?Phase {
        var best: ?Phase = null;
        var best_ns: u64 = 0;
        var index: usize = 0;
        while (index < phase_count) : (index += 1) {
            if (self.by_phase[index] <= best_ns) continue;
            best_ns = self.by_phase[index];
            best = @enumFromInt(index);
        }
        return best;
    }

    /// Host seconds needed to reach a guest deadline at the achieved rate.
    /// This is what turns "run longer" from advice into a decision.
    pub fn hostSecondsToReach(self: Summary, guest_ms_target: u64) ?u64 {
        const rate = self.guestMsPerHostSecond();
        if (rate == 0) return null;
        if (guest_ms_target <= self.guest_ms) return 0;
        return (guest_ms_target - self.guest_ms) / rate;
    }
};

/// A monotonic measurement window anchored at a proven runtime boundary.
/// Keeping the origin as a complete summary preserves phase attribution while
/// making it impossible for pre-boundary startup work to contaminate the rate.
pub const Window = struct {
    started: bool = false,
    origin: Summary = .{},

    pub fn begin(self: *Window, current: Summary) void {
        if (self.started) return;
        self.origin = current;
        self.started = true;
    }

    pub fn summary(self: *const Window, current: Summary) Summary {
        if (!self.started) return .{};
        return current.since(self.origin);
    }
};

pub const Ledger = struct {
    /// The rate a graphics bring-up run has to hold.
    required_guest_ms_per_host_second: u64 = 0,
    /// The wall-clock window before the run is killed.
    window_host_seconds: u64 = 0,
    host_ns: u64 = 0,
    guest_ms: u64 = 0,
    by_phase: [phase_count]u64 = [_]u64{0} ** phase_count,
    pools: [2]PoolStats = [_]PoolStats{.{}} ** 2,
    /// The frontier this run reached, so two runs can be compared.
    frontier_id: u64 = 0,

    pub fn declare(self: *Ledger, guest_ms_per_host_second: u64, window_host_seconds: u64) void {
        self.required_guest_ms_per_host_second = guest_ms_per_host_second;
        self.window_host_seconds = window_host_seconds;
    }

    pub fn spend(self: *Ledger, phase: Phase, host_ns: u64) void {
        self.by_phase[@intFromEnum(phase)] +|= host_ns;
        self.host_ns +|= host_ns;
    }

    pub fn advanceGuest(self: *Ledger, guest_ms: u64) void {
        self.guest_ms +|= guest_ms;
    }

    /// Reconcile monotonic run-horizon totals without double-counting a
    /// checkpoint. Time not attributed by a narrower phase observer is kept
    /// as guest execution so the budget is judgeable rather than `unobserved`.
    pub fn observeTotals(self: *Ledger, host_ns: u64, guest_ms: u64) void {
        if (host_ns > self.host_ns) {
            self.by_phase[@intFromEnum(Phase.guest_execution)] +|= host_ns - self.host_ns;
            self.host_ns = host_ns;
        }
        if (guest_ms > self.guest_ms) self.guest_ms = guest_ms;
    }

    pub fn pool(self: *Ledger, which: Pool) *PoolStats {
        return &self.pools[@intFromEnum(which)];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{
            .host_ns = self.host_ns,
            .guest_ms = self.guest_ms,
            .by_phase = self.by_phase,
        };
        var index: usize = 0;
        while (index < phase_count) : (index += 1) {
            const phase: Phase = @enumFromInt(index);
            if (phase.isObserverWork()) out.observer_ns +|= self.by_phase[index];
            if (phase.isTranslationWork()) out.translation_ns +|= self.by_phase[index];
        }
        return out;
    }

    /// The phase that took the most host time. Where the next hour goes.
    pub fn dominantPhase(self: *const Ledger) ?Phase {
        var best: ?Phase = null;
        var best_ns: u64 = 0;
        var index: usize = 0;
        while (index < phase_count) : (index += 1) {
            if (self.by_phase[index] <= best_ns) continue;
            best_ns = self.by_phase[index];
            best = @enumFromInt(index);
        }
        return best;
    }

    /// Judge a supplied measurement window while retaining the ledger's pool
    /// evidence. This lets a caller exclude a known startup prefix without
    /// discarding the cache and observer accounting attached to the run.
    pub fn verdictFor(self: *const Ledger, totals: Summary) Verdict {
        if (totals.host_ns < std.time.ns_per_s) return .unobserved;
        if (totals.observerPercent() > observer_budget_percent) return .observer_over_budget;
        for (self.pools) |stats| {
            if (stats.thrashing()) return .cache_thrashing;
        }
        if (self.required_guest_ms_per_host_second == 0) return .unobserved;
        if (totals.guestMsPerHostSecond() < self.required_guest_ms_per_host_second) return .below_budget;
        return .within_budget;
    }

    /// Defer only the throughput verdict while a trusted structural-progress
    /// witness is fresh. The raw `verdictFor` remains strict and is used for
    /// all other causes, so observer over-budget and cache thrashing cannot be
    /// hidden by unrelated guest progress.
    pub fn verdictForWithProgress(
        self: *const Ledger,
        totals: Summary,
        structural_progress_fresh: bool,
    ) Verdict {
        const base_verdict = self.verdictFor(totals);
        if (base_verdict == .below_budget and structural_progress_fresh) return .progressing;
        return base_verdict;
    }

    pub fn verdict(self: *const Ledger) Verdict {
        return self.verdictFor(self.summary());
    }

    /// Whether the run can reach a guest deadline inside its window.
    pub fn canReach(self: *const Ledger, guest_ms_target: u64) bool {
        const needed = self.summary().hostSecondsToReach(guest_ms_target) orelse return false;
        if (self.window_host_seconds == 0) return true;
        const spent = self.host_ns / std.time.ns_per_s;
        return spent +| needed <= self.window_host_seconds;
    }

    /// Two runs are comparable when they reached the same frontier. A
    /// diagnostic that moves the frontier is a variable rather than an
    /// observer.
    pub fn observerNonInterfering(self: *const Ledger, other: *const Ledger) bool {
        return self.frontier_id != 0 and self.frontier_id == other.frontier_id;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.guestMsPerHostSecond();
        hash = hash *% 31 +% totals.observerPercent();
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

// The 2026-08-31 throughput: 324 guest ms in 1032 host seconds, which is well
// under one guest millisecond per host second.
test "a run below its declared rate fails with a reason instead of a watchdog" {
    var ledger = Ledger{};
    ledger.declare(5, 2400);
    ledger.spend(.guest_execution, 400 * std.time.ns_per_s);
    ledger.spend(.jit_register_allocation, 632 * std.time.ns_per_s);
    ledger.advanceGuest(324);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 0), totals.guestMsPerHostSecond());
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.below_budget, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expectEqual(Phase.jit_register_allocation, ledger.dominantPhase().?);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "arbitrary watchdog") != null);
}

test "a run meeting its rate is within budget and its projection is usable" {
    var ledger = Ledger{};
    ledger.declare(5, 2400);
    ledger.spend(.guest_execution, 100 * std.time.ns_per_s);
    ledger.advanceGuest(1000);
    try std.testing.expectEqual(@as(u64, 10), ledger.summary().guestMsPerHostSecond());
    try std.testing.expectEqual(Verdict.within_budget, ledger.verdict());
    // Reaching 10 000 guest ms needs 900 more host seconds at 10 ms/s.
    try std.testing.expectEqual(@as(u64, 900), ledger.summary().hostSecondsToReach(10_000).?);
    try std.testing.expect(ledger.canReach(10_000));
    try std.testing.expect(!ledger.canReach(60_000));
}

// The audit's non-interference requirement.
test "an observer over its share is changing what it observes" {
    var ledger = Ledger{};
    ledger.declare(1, 2400);
    ledger.spend(.guest_execution, 80 * std.time.ns_per_s);
    ledger.spend(.diagnostics, 15 * std.time.ns_per_s);
    ledger.spend(.memory_tracing, 5 * std.time.ns_per_s);
    ledger.advanceGuest(1000);
    try std.testing.expectEqual(@as(u64, 20), ledger.summary().observerPercent());
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.observer_over_budget, verdict);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "not comparable") != null);
}

test "two runs are comparable only when they reached the same frontier" {
    var instrumented = Ledger{ .frontier_id = 7 };
    var quiet = Ledger{ .frontier_id = 7 };
    try std.testing.expect(instrumented.observerNonInterfering(&quiet));
    quiet.frontier_id = 8;
    try std.testing.expect(!instrumented.observerNonInterfering(&quiet));
    // An unknown frontier is never evidence of non-interference.
    instrumented.frontier_id = 0;
    quiet.frontier_id = 0;
    try std.testing.expect(!instrumented.observerNonInterfering(&quiet));
}

// The audit's cache partition: immutable image code and mutable JIT output in
// separate pools, because only one of them is ever re-decoded.
test "a conflict-dominated pool is thrashing whatever its hit rate says" {
    var ledger = Ledger{};
    ledger.declare(1, 2400);
    ledger.spend(.guest_execution, 100 * std.time.ns_per_s);
    ledger.advanceGuest(1000);

    const mutable = ledger.pool(.mutable_generated);
    mutable.hits = 100_000_000;
    mutable.fills = 1_816_815;
    mutable.conflict_evictions = 980_465;
    // A 98% hit rate and conflicts dominating the fills at the same time. The
    // misses are ~1.8% of lookups, which is where the time actually goes.
    try std.testing.expectEqual(@as(u64, 98), mutable.hitRatePercent());
    try std.testing.expect(mutable.conflictDominated());
    try std.testing.expect(mutable.thrashing());
    try std.testing.expectEqual(Verdict.cache_thrashing, ledger.verdict());

    // The immutable pool is untouched by the mutable one's churn, which is the
    // whole point of separating them.
    try std.testing.expect(!ledger.pool(.immutable_image).conflictDominated());
}

// The 2026-09-01 run: 1.69 million fills against 6.1 billion lookups, 52% of
// them conflicts, at three guest milliseconds per host second against a
// required five. Every one of those numbers is correct and the headline read
// `CACHE-THRASHING`, which sent the reader to a pool the run barely touches
// and hid the finding that was actually there.
test "a conflict-dominated pool the run barely touches is not the run's verdict" {
    var ledger = Ledger{};
    ledger.declare(5, 2400);
    ledger.spend(.guest_execution, 1302 * std.time.ns_per_s);
    ledger.advanceGuest(4469);

    const mutable = ledger.pool(.mutable_generated);
    mutable.hits = 6_098_305_557;
    mutable.fills = 1_694_443;
    mutable.conflict_evictions = 886_743;

    // The composition is real and stays reportable: this is still the number
    // that tells an indexing problem from a working set that does not fit.
    try std.testing.expect(mutable.conflictDominated());
    // It is not material: three misses in ten thousand lookups.
    try std.testing.expectEqual(@as(u64, 2), mutable.missBasisPoints());
    try std.testing.expect(!mutable.thrashing());

    // So the verdict is the one the run actually earned.
    try std.testing.expectEqual(@as(u64, 3), ledger.summary().guestMsPerHostSecond());
    try std.testing.expectEqual(Verdict.below_budget, ledger.verdict());
    try std.testing.expectEqual(Phase.guest_execution, ledger.dominantPhase().?);
}

// The threshold has to bite in both directions or it is decoration.
test "materiality is measured in basis points rather than rounded percent" {
    var barely = PoolStats{ .hits = 9_900, .fills = 100, .conflict_evictions = 60 };
    // One percent exactly: the first miss rate that counts.
    try std.testing.expectEqual(@as(u64, 100), barely.missBasisPoints());
    try std.testing.expect(barely.thrashing());

    barely.hits = 99_900;
    barely.fills = 100;
    try std.testing.expectEqual(@as(u64, 10), barely.missBasisPoints());
    try std.testing.expect(barely.conflictDominated());
    try std.testing.expect(!barely.thrashing());

    // Both rates round to a 99% hit rate, and only one of them is a finding.
    try std.testing.expectEqual(@as(u64, 99), (PoolStats{ .hits = 9_900, .fills = 100 }).hitRatePercent());
    try std.testing.expectEqual(@as(u64, 99), (PoolStats{ .hits = 99_900, .fills = 100 }).hitRatePercent());

    // A pool with no misses at all is neither.
    const cold = PoolStats{};
    try std.testing.expectEqual(@as(u64, 0), cold.missBasisPoints());
    try std.testing.expect(!cold.thrashing());
}

test "a rate of zero makes a projection unavailable rather than infinite" {
    var ledger = Ledger{};
    ledger.spend(.idle, 10 * std.time.ns_per_s);
    try std.testing.expect(ledger.summary().hostSecondsToReach(1000) == null);
    try std.testing.expect(!ledger.canReach(1000));
    try std.testing.expectEqual(Verdict.unobserved, ledger.verdict());
}

test "run horizon totals are monotonic and checkpoint idempotent" {
    var ledger = Ledger{};
    ledger.declare(5, 2400);
    ledger.observeTotals(100 * std.time.ns_per_s, 1000);
    ledger.observeTotals(100 * std.time.ns_per_s, 1000);
    try std.testing.expectEqual(@as(u64, 100 * std.time.ns_per_s), ledger.host_ns);
    try std.testing.expectEqual(@as(u64, 1000), ledger.guest_ms);
    try std.testing.expectEqual(@as(u64, 10), ledger.summary().guestMsPerHostSecond());
}

test "a budget window excludes the startup prefix from its rate" {
    var ledger = Ledger{};
    ledger.declare(5, 2400);
    ledger.spend(.jit_emission, 100 * std.time.ns_per_s);
    const startup = ledger.summary();

    var window = Window{};
    window.begin(startup);

    ledger.spend(.guest_execution, 10 * std.time.ns_per_s);
    ledger.advanceGuest(100);
    const scoped = window.summary(ledger.summary());

    try std.testing.expectEqual(@as(u64, 10 * std.time.ns_per_s), scoped.host_ns);
    try std.testing.expectEqual(@as(u64, 100), scoped.guest_ms);
    try std.testing.expectEqual(@as(u64, 10), scoped.guestMsPerHostSecond());
    try std.testing.expectEqual(Verdict.within_budget, ledger.verdictFor(scoped));
    // The whole-run rate would be zero here, which is precisely the
    // contamination the window prevents.
    try std.testing.expectEqual(Verdict.below_budget, ledger.verdict());
}

test "fresh structural progress defers only a below-budget verdict" {
    var ledger = Ledger{};
    ledger.declare(5, 2400);
    ledger.spend(.guest_execution, 69 * std.time.ns_per_s);
    ledger.advanceGuest(324);
    const totals = ledger.summary();

    try std.testing.expectEqual(Verdict.below_budget, ledger.verdictFor(totals));
    try std.testing.expectEqual(Verdict.progressing, ledger.verdictForWithProgress(totals, true));
    try std.testing.expect(!ledger.verdictForWithProgress(totals, true).isDefect());
    try std.testing.expectEqual(Verdict.below_budget, ledger.verdictForWithProgress(totals, false));

    var observer_heavy = Ledger{};
    observer_heavy.declare(5, 2400);
    observer_heavy.spend(.guest_execution, 69 * std.time.ns_per_s);
    observer_heavy.spend(.diagnostics, 10 * std.time.ns_per_s);
    observer_heavy.advanceGuest(324);
    try std.testing.expectEqual(
        Verdict.observer_over_budget,
        observer_heavy.verdictForWithProgress(observer_heavy.summary(), true),
    );
}

test "a target already reached needs no more host time" {
    var ledger = Ledger{};
    ledger.spend(.guest_execution, 10 * std.time.ns_per_s);
    ledger.advanceGuest(500);
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().hostSecondsToReach(400).?);
}

test "every phase and pool states its own vocabulary" {
    inline for (@typeInfo(Phase).@"enum".fields) |field| {
        const which: Phase = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(Pool).@"enum".fields) |field| {
        const which: Pool = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    try std.testing.expect(Phase.diagnostics.isObserverWork());
    try std.testing.expect(!Phase.guest_execution.isObserverWork());
    try std.testing.expect(Phase.jit_emission.isTranslationWork());
}
