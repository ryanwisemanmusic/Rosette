//! Incremental collection of preflight facts from Rosette's own boundaries.
//!
//! The facts do not arrive at once. Rosette services the configuration file's
//! open early, the guest prints what it believes about that configuration some
//! seconds later, and the graphics handles appear later still. A collector that
//! demanded them together would have to be called at a moment that does not
//! exist.
//!
//! So this accepts lines as they cross, keeps only what it was asked to watch,
//! and answers when asked. Bounded storage and no allocation, because it runs on
//! the guest logging path: a collector that can fail to record is not a
//! collector, and one that allocates on a hot path is a tax on every line the
//! guest prints.
//!
//! ## What it is watching for
//!
//! `key = value`, from two sources that must agree. Both sides use that shape —
//! TOML declares it and the guest's own configuration dump prints it — so one
//! parser serves both, and the only thing that distinguishes them is which side
//! deposited the reading. That symmetry is the whole mechanism: no interpretation
//! happens, two strings are compared, and a disagreement is a fact rather than
//! an inference.
//!
//! Deliberately watches a fixed list rather than everything. A collector that
//! kept every key would need the allocator it must not use, and the interesting
//! keys are the ones something depends on — which is a judgement, not a sweep.

const std = @import("std");
const check = @import("check.zig");
const observation = @import("observation.zig");

/// Longest key and value retained. Anything longer is truncated for comparison
/// rather than dropped: a truncated mismatch is still a mismatch, and dropping
/// would silently narrow what the gate can see.
pub const max_text: usize = 64;
pub const max_watched: usize = 32;

const Slot = struct {
    key: [max_text]u8 = undefined,
    key_len: usize = 0,
    file: [max_text]u8 = undefined,
    file_len: usize = 0,
    file_present: bool = false,
    guest: [max_text]u8 = undefined,
    guest_len: usize = 0,
    guest_present: bool = false,
    severity: check.Severity = .degraded,

    fn keyText(self: *const Slot) []const u8 {
        return self.key[0..self.key_len];
    }
};

pub const Collector = struct {
    slots: [max_watched]Slot = [_]Slot{.{}} ** max_watched,
    count: usize = 0,
    /// Watch requests beyond capacity. Tracked because a silently truncated
    /// watch list produces a report that is clean for the wrong reason.
    dropped_watches: usize = 0,
    config_file_read: bool = false,
    guest_dump_captured: bool = false,

    /// Register a key whose two readings must agree.
    pub fn watch(self: *Collector, key: []const u8, severity: check.Severity) void {
        if (self.find(key) != null) return;
        if (self.count >= self.slots.len) {
            self.dropped_watches +|= 1;
            return;
        }
        const slot = &self.slots[self.count];
        slot.* = .{};
        slot.key_len = copyInto(&slot.key, key);
        slot.severity = severity;
        self.count += 1;
    }

    /// Feed a line from the configuration file Rosette serviced the open for.
    pub fn observeFileLine(self: *Collector, line: []const u8) void {
        self.config_file_read = true;
        const pair = parseAssignment(line) orelse return;
        const slot = self.find(pair.key) orelse return;
        slot.file_len = copyInto(&slot.file, pair.value);
        slot.file_present = true;
    }

    /// Feed a line the guest printed. Only lines inside its configuration dump
    /// carry its beliefs; ordinary log lines happen to contain '=' constantly,
    /// and treating those as configuration would manufacture disagreements out
    /// of prose.
    pub fn observeGuestLine(self: *Collector, line: []const u8) void {
        if (isConfigDumpBoundary(line)) {
            self.guest_dump_captured = true;
            return;
        }
        if (!self.guest_dump_captured) return;
        const pair = parseAssignment(line) orelse return;
        const slot = self.find(pair.key) orelse return;
        slot.guest_len = copyInto(&slot.guest, pair.value);
        slot.guest_present = true;
    }

    /// Render what has been collected into the readings `observation` compares.
    /// Writes into caller storage so nothing here allocates.
    pub fn readings(self: *const Collector, out: []observation.ConfigReading) []const observation.ConfigReading {
        const limit = @min(out.len, self.count);
        var index: usize = 0;
        while (index < limit) : (index += 1) {
            const slot = &self.slots[index];
            out[index] = .{
                .key = slot.keyText(),
                .file_value = slot.file[0..slot.file_len],
                .file_present = slot.file_present,
                .guest_value = slot.guest[0..slot.guest_len],
                .guest_present = slot.guest_present,
                .severity = slot.severity,
            };
        }
        return out[0..limit];
    }

    fn find(self: *Collector, key: []const u8) ?*Slot {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (std.mem.eql(u8, self.slots[index].keyText(), key)) return &self.slots[index];
        }
        return null;
    }
};

const Assignment = struct { key: []const u8, value: []const u8 };

/// `key = value`, tolerating the alignment padding both TOML and the guest's
/// dump use, and rejecting anything that is not an assignment at the start of
/// a line. Comments are stripped because TOML carries them inline and the value
/// before the '#' is the one that binds.
fn parseAssignment(raw: []const u8) ?Assignment {
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (line.len == 0 or line[0] == '#' or line[0] == '[') return null;
    const equals = std.mem.indexOfScalar(u8, line, '=') orelse return null;
    const key = std.mem.trim(u8, line[0..equals], " \t");
    if (key.len == 0) return null;
    for (key) |byte| {
        // A key is an identifier. Anything else means this line is prose that
        // happens to contain '=', which every log is full of.
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return null;
    }
    var value = std.mem.trim(u8, line[equals + 1 ..], " \t");
    if (std.mem.indexOfScalar(u8, value, '#')) |comment| {
        value = std.mem.trim(u8, value[0..comment], " \t");
    }
    value = std.mem.trim(u8, value, "\"");
    return .{ .key = key, .value = value };
}

fn isConfigDumpBoundary(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "CONFIG DUMP") != null;
}

fn copyInto(destination: []u8, source: []const u8) usize {
    const length = @min(destination.len, source.len);
    @memcpy(destination[0..length], source[0..length]);
    return length;
}

test "an assignment is parsed from both TOML and dump shapes" {
    try std.testing.expectEqualStrings("7500", parseAssignment("gpu_debug_force_swap_after_ms = 7500").?.value);
    try std.testing.expectEqualStrings("7500", parseAssignment("gpu_debug_force_swap_after_ms = 7500              \t# comment").?.value);
    try std.testing.expectEqualStrings("any", parseAssignment("cpu = \"any\"").?.value);
    try std.testing.expectEqualStrings("gpu_debug_force_swap_once", parseAssignment("gpu_debug_force_swap_once = true").?.key);
}

// Log lines contain '=' constantly. Treating them as configuration would
// manufacture disagreements out of prose, which is the fastest way to make a
// gate untrustworthy.
test "prose containing an equals sign is not an assignment" {
    try std.testing.expect(parseAssignment("[xenia] w> DEBUG: read_ptr=00000019 write_ptr=00000019") == null);
    try std.testing.expect(parseAssignment("# gpu_debug_force_swap_after_ms = 7500") == null);
    try std.testing.expect(parseAssignment("[GPU]") == null);
    try std.testing.expect(parseAssignment("no equals here") == null);
}

// The bug this exists for, end to end, with no guest cooperation: the file says
// 7500, the guest's own dump says 0.
test "a file and guest disagreement is collected and reported" {
    var collector = Collector{};
    collector.watch("gpu_debug_force_swap_after_ms", .degraded);
    collector.watch("gpu_log_no_swap_after_ms", .degraded);

    collector.observeFileLine("gpu_debug_force_swap_after_ms = 7500   # inject one probe");
    collector.observeFileLine("gpu_log_no_swap_after_ms = 5000");

    collector.observeGuestLine("[xenia] i> ----------- CONFIG DUMP -----------");
    collector.observeGuestLine("gpu_debug_force_swap_after_ms = 0");
    collector.observeGuestLine("gpu_log_no_swap_after_ms = 5000");

    var storage: [max_watched]observation.ConfigReading = undefined;
    const items = collector.readings(&storage);
    try std.testing.expectEqual(@as(usize, 2), items.len);

    var report = check.Report{};
    for (items) |reading| {
        report.record(observation.checkConfigAgreement(
            reading,
            collector.guest_dump_captured,
            collector.config_file_read,
        ));
    }
    try std.testing.expectEqual(@as(usize, 1), report.tally(.violated));
    try std.testing.expectEqual(@as(usize, 1), report.tally(.satisfied));
    try std.testing.expectEqualStrings("gpu_debug_force_swap_after_ms", report.items()[0].evidence.source);
    try std.testing.expectEqualStrings("7500", report.items()[0].evidence.expected);
    try std.testing.expectEqualStrings("0", report.items()[0].evidence.observed);
}

// Assignments before the dump header are the guest's ordinary output, not its
// configuration. Accepting them would let any log line overwrite a reading.
test "guest assignments before the dump header are ignored" {
    var collector = Collector{};
    collector.watch("k", .degraded);
    collector.observeGuestLine("k = 1");
    try std.testing.expect(!collector.guest_dump_captured);

    var storage: [max_watched]observation.ConfigReading = undefined;
    try std.testing.expect(!collector.readings(&storage)[0].guest_present);
}

test "only watched keys are retained" {
    var collector = Collector{};
    collector.watch("watched", .fatal);
    collector.observeFileLine("watched = 1");
    collector.observeFileLine("ignored = 2");
    var storage: [max_watched]observation.ConfigReading = undefined;
    const items = collector.readings(&storage);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("1", items[0].file_value);
    try std.testing.expectEqual(check.Severity.fatal, items[0].severity);
}

test "duplicate watches do not consume slots" {
    var collector = Collector{};
    collector.watch("k", .degraded);
    collector.watch("k", .fatal);
    try std.testing.expectEqual(@as(usize, 1), collector.count);
    // The first registration wins, so a later call cannot quietly escalate a
    // key's severity out from under whoever registered it.
    try std.testing.expectEqual(check.Severity.degraded, collector.slots[0].severity);
}

test "watches beyond capacity are counted rather than dropped silently" {
    var collector = Collector{};
    var index: usize = 0;
    var buffer: [8]u8 = undefined;
    while (index < max_watched + 2) : (index += 1) {
        const key = std.fmt.bufPrint(&buffer, "k{d}", .{index}) catch unreachable;
        collector.watch(key, .degraded);
    }
    try std.testing.expectEqual(max_watched, collector.count);
    try std.testing.expectEqual(@as(usize, 2), collector.dropped_watches);
}

// Until both sides have been seen, the honest answer is unknown. A collector
// that has only read the file must not report the guest as agreeing.
test "readings are unknown until both sides arrive" {
    var collector = Collector{};
    collector.watch("k", .fatal);
    collector.observeFileLine("k = 7500");

    var storage: [max_watched]observation.ConfigReading = undefined;
    const items = collector.readings(&storage);
    const result = observation.checkConfigAgreement(
        items[0],
        collector.guest_dump_captured,
        collector.config_file_read,
    );
    try std.testing.expectEqual(check.Outcome.indeterminate, result.outcome);
    // Fatal severity means an unknown load-bearing precondition stops the run.
    try std.testing.expect(result.blocksLaunch());
}
