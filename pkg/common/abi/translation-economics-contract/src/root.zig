//! Stable vocabulary for decode-cache cost.
//!
//! A repeated cache miss is not proof that code was rewritten. The cache fill
//! path knows whether it found a vacant way, evicted a live decode, rejected
//! stale bytes, or refilled after a wholesale flush; the contract requires
//! that cause to travel with the event rather than being inferred later from
//! "this page was seen before".

const std = @import("std");
// The fill-cause vocabulary belongs to the standalone cache boundary. This
// package retains the public alias so existing economics ledgers keep their
// API while fail-fast policy, cache mapping, and diagnostics all name the same
// enum type.
pub const Cause = @import("rosette_translation_cache_contract").Cause;

pub const Verdict = enum(u8) {
    idle,
    warming,
    cache_pressure,
    executable_rewrite,
    flush_thrashing,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .idle => "idle",
            .warming => "warming",
            .cache_pressure => "CACHE-PRESSURE",
            .executable_rewrite => "EXECUTABLE-REWRITE",
            .flush_thrashing => "FLUSH-THRASHING",
        };
    }

    pub fn converges(self: Verdict) bool {
        return self == .idle or self == .warming;
    }

    pub fn guidance(self: Verdict) []const u8 {
        return switch (self) {
            .idle => "no decode miss has been observed, so translation economics has no conclusion",
            .warming => "vacant or cold-stream fills dominate; the cache is primarily paying cold or precisely-invalidated fill cost rather than evicting reused work",
            .cache_pressure => "live byte-valid decodes are being evicted faster than vacant ways are filled. Increase effective cache capacity or isolate immutable image code from mutable JIT code",
            .executable_rewrite => "byte comparison proved that cached instruction bytes changed. Attribute the executable writer and generation before changing cache policy",
            .flush_thrashing => "coarse invalidation is discarding unrelated live decodes. Make the invalidation range precise before increasing cache size",
        };
    }
};

pub fn percentage(part: u64, whole: u64) u64 {
    if (whole == 0) return 0;
    return @intCast((@as(u128, part) * 100) / whole);
}

pub const dominant_percent: u64 = 25;

pub fn verdictOf(vacant: u64, conflict: u64, cold: u64, stale: u64, flush: u64) Verdict {
    const total = vacant +| conflict +| cold +| stale +| flush;
    if (total == 0) return .idle;
    const cold_fills = vacant +| cold;
    if (flush >= cold_fills and percentage(flush, total) >= dominant_percent) return .flush_thrashing;
    if (stale >= cold_fills and percentage(stale, total) >= dominant_percent) return .executable_rewrite;
    if (conflict > cold_fills and percentage(conflict, total) >= dominant_percent) return .cache_pressure;
    return .warming;
}

pub fn contractIsWellFormed() bool {
    if (Cause.vacant_fill.recurring()) return false;
    if (!Cause.capacity_conflict.recurring()) return false;
    if (Cause.cold_eviction.recurring()) return false;
    if (!Cause.stale_bytes.recurring()) return false;
    if (!Cause.flush_collateral.recurring()) return false;
    if (verdictOf(0, 0, 0, 0, 0) != .idle) return false;
    if (verdictOf(100, 10, 0, 0, 0) != .warming) return false;
    if (verdictOf(10, 100, 0, 0, 0) != .cache_pressure) return false;
    if (verdictOf(10, 0, 0, 100, 0) != .executable_rewrite) return false;
    if (verdictOf(10, 0, 0, 0, 100) != .flush_thrashing) return false;
    return true;
}

test "verdicts preserve the miss cause" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expectEqual(@as(u64, 94), percentage(94, 100));
    try std.testing.expect(!Verdict.cache_pressure.converges());
    try std.testing.expect(std.mem.indexOf(u8, Verdict.cache_pressure.guidance(), "immutable") != null);
}

test "every cause has a non-empty explanation" {
    inline for (@typeInfo(Cause).@"enum".fields) |field| {
        const value: Cause = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.meaning().len > 40);
    }
}
