//! Keeps Rosette's own log from filling the host disk.
//!
//! Every `std.log` call in the runner writes a line to stderr, which the
//! Xenia launcher tees into the run log on the host disk. Most call sites are
//! checkpoints or once-per-run reports. A few sit on paths whose frequency is
//! the guest's to choose - an import refusal, a wait decision, an audio event
//! - and are throttled by hand. A call site nobody throttled, reached in a
//! loop, writes until the disk is full.
//!
//! The rule is per call site: the first `default_site_budget` lines of any one
//! `log.*` call are written, and after that only occurrences whose count is a
//! power of two, each followed by a line saying how many that site has
//! produced. A call site is its format string, level and scope, so two
//! different messages never share a budget.
//!
//! `ROSETTE_LOG_SITE_BUDGET` overrides the budget; `unlimited` disables the
//! governor for a deep trace that is meant to be exhaustive.

const std = @import("std");

pub const default_site_budget: u64 = 20_000;

pub const Admission = enum {
    emit,
    /// Emit, and say that this site is now being thinned.
    emit_with_notice,
    suppress,
};

/// Whether the `occurrence`-th line of one call site is written.
pub fn admit(occurrence: u64, budget: u64) Admission {
    if (occurrence <= budget) return .emit;
    if (occurrence != 0 and (occurrence & (occurrence - 1)) == 0) return .emit_with_notice;
    return .suppress;
}

pub fn parseBudget(text: ?[]const u8) u64 {
    const value = text orelse return default_site_budget;
    if (std.ascii.eqlIgnoreCase(value, "unlimited")) return std.math.maxInt(u64);
    const parsed = std.fmt.parseInt(u64, value, 10) catch return default_site_budget;
    return if (parsed == 0) std.math.maxInt(u64) else parsed;
}

var cached_budget = std.atomic.Value(u64).init(0);

/// Lines withheld across every call site, for anything that wants to report
/// that the log is incomplete.
pub var suppressed_lines = std.atomic.Value(u64).init(0);

pub fn siteBudget() u64 {
    const cached = cached_budget.load(.monotonic);
    if (cached != 0) return cached;
    const raw = std.c.getenv("ROSETTE_LOG_SITE_BUDGET");
    const budget = parseBudget(if (raw) |pointer| std.mem.span(pointer) else null);
    cached_budget.store(budget, .monotonic);
    return budget;
}

/// A `std.Options.logFn` that applies the per-site budget, then writes
/// through the standard logger.
pub fn governedLog(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const Site = struct {
        // Referencing the call site's comptime parameters is what makes this
        // a distinct type, and therefore a distinct counter, per call site.
        // A container that captures nothing is shared by every instantiation.
        const site_format = format;
        const site_level = level;
        const site_scope = scope;
        var occurrences = std.atomic.Value(u64).init(0);
    };
    const occurrence = Site.occurrences.fetchAdd(1, .monotonic) +% 1;
    switch (admit(occurrence, siteBudget())) {
        .emit => std.log.defaultLog(level, scope, format, args),
        .emit_with_notice => {
            std.log.defaultLog(level, scope, format, args);
            std.log.defaultLog(.warn, .log_governor, "the call site above has written {d} lines; past {d} per call site only power-of-two occurrences reach this log (ROSETTE_LOG_SITE_BUDGET=unlimited disables this)", .{
                occurrence,
                siteBudget(),
            });
        },
        .suppress => _ = suppressed_lines.fetchAdd(1, .monotonic),
    }
}

fn countingSite(comptime tag: []const u8) u64 {
    const Site = struct {
        const site_tag = tag;
        var hits: u64 = 0;
    };
    Site.hits += 1;
    return Site.hits;
}

test "a counter declared in a generic function is one per call site" {
    _ = countingSite("first message");
    _ = countingSite("first message");
    try std.testing.expectEqual(@as(u64, 1), countingSite("second message"));
    try std.testing.expectEqual(@as(u64, 3), countingSite("first message"));
}

test "a site writes its budget, then only at powers of two" {
    try std.testing.expectEqual(Admission.emit, admit(1, 4));
    try std.testing.expectEqual(Admission.emit, admit(4, 4));
    try std.testing.expectEqual(Admission.suppress, admit(5, 4));
    try std.testing.expectEqual(Admission.emit_with_notice, admit(8, 4));
    try std.testing.expectEqual(Admission.suppress, admit(9, 4));
    var written: u64 = 0;
    var occurrence: u64 = 1;
    while (occurrence <= 1_000_000) : (occurrence += 1) {
        if (admit(occurrence, 16) != .suppress) written += 1;
    }
    // Sixteen, then 32 through 524288: fifteen more.
    try std.testing.expectEqual(@as(u64, 31), written);
}

test "the budget override is parsed conservatively" {
    try std.testing.expectEqual(default_site_budget, parseBudget(null));
    try std.testing.expectEqual(default_site_budget, parseBudget("not a number"));
    try std.testing.expectEqual(@as(u64, 500), parseBudget("500"));
    try std.testing.expectEqual(std.math.maxInt(u64), parseBudget("unlimited"));
    try std.testing.expectEqual(std.math.maxInt(u64), parseBudget("0"));
}
