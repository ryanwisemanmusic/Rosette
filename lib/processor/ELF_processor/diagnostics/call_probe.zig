//! Named-function call probes: every call to a chosen guest function, with
//! its arguments on the way in and its results on the way out, without a
//! rebuild.
//!
//! `ROSETTE_PE64_CALL_PROBE=<name>[,<name>...]` arms up to `max_probes`
//! functions, each named by its symbol exactly as a backtrace prints it
//! (`_ZNSt10filesystem7__cxx114path7_Parser4nextEv`) or by `0x<address>`.
//! `ROSETTE_PE64_CALL_PROBE_BUDGET` caps how many calls of each are logged
//! (default 32); every call is still counted. The 2026-09-25 investigation
//! of the 10.8 GB allocation needed exactly this - the arguments
//! `_Parser::next` was called with on Xenia's Emulator thread - and had to
//! reconstruct them from a disassembly instead.
//!
//! A probe observes `call` instructions only: the interpreter's call arms
//! report the entry and arm the thread's return capture, and a translated
//! call to a probed target is kept on the interpreter so it passes the same
//! arm. A tail `jmp` into the function is not seen. While a probe's return
//! is pending, translated `ret`s go through the interpreter, as they do for
//! every return capture.

const std = @import("std");

pub const max_probes = 16;
pub const default_budget: u32 = 32;
pub const name_bytes = 128;

pub const Probe = struct {
    address: u64 = 0,
    name_storage: [name_bytes]u8 = undefined,
    name_len: u8 = 0,
    calls: u64 = 0,
    returns: u64 = 0,
    logged: u32 = 0,

    pub fn name(self: *const Probe) []const u8 {
        return self.name_storage[0..self.name_len];
    }
};

pub const ProbeSet = struct {
    probes: [max_probes]Probe = @splat(.{}),
    count: u8 = 0,
    budget: u32 = default_budget,
    /// Requested names that did not resolve, for the arming report.
    unresolved: u8 = 0,

    pub fn armed(self: *const ProbeSet) bool {
        return self.count != 0;
    }

    pub fn indexOf(self: *const ProbeSet, address: u64) ?u8 {
        if (self.count == 0) return null;
        for (self.probes[0..self.count], 0..) |probe, index| {
            if (probe.address == address) return @intCast(index);
        }
        return null;
    }

    /// Arm `address` under `label`; false when the set is full or the
    /// address is already armed.
    pub fn add(self: *ProbeSet, address: u64, label: []const u8) bool {
        if (address == 0 or self.count == max_probes or self.indexOf(address) != null) return false;
        const probe = &self.probes[self.count];
        probe.* = .{ .address = address };
        const length = @min(label.len, name_bytes);
        @memcpy(probe.name_storage[0..length], label[0..length]);
        probe.name_len = @intCast(length);
        self.count += 1;
        return true;
    }

    /// Count a call; true while it is still within the logging budget.
    pub fn noteCall(self: *ProbeSet, index: u8) struct { number: u64, log: bool } {
        const probe = &self.probes[index];
        probe.calls +|= 1;
        const log = probe.logged < self.budget;
        if (log) probe.logged += 1;
        return .{ .number = probe.calls, .log = log };
    }
};

/// The requested entries of a comma- or space-separated probe list.
pub fn requests(text: []const u8) std.mem.TokenIterator(u8, .any) {
    return std.mem.tokenizeAny(u8, text, ", ;");
}

/// A request that names an address rather than a symbol.
pub fn parseAddress(request: []const u8) ?u64 {
    if (request.len < 3 or request[0] != '0' or (request[1] != 'x' and request[1] != 'X')) return null;
    return std.fmt.parseInt(u64, request[2..], 16) catch null;
}

test "a probe set arms each address once and finds it again" {
    var set: ProbeSet = .{};
    try std.testing.expect(!set.armed());
    try std.testing.expect(set.add(0x1400_1000, "first"));
    try std.testing.expect(!set.add(0x1400_1000, "again"));
    try std.testing.expect(set.add(0x1400_2000, "second"));
    try std.testing.expectEqual(@as(?u8, 1), set.indexOf(0x1400_2000));
    try std.testing.expect(set.indexOf(0x1400_3000) == null);
    try std.testing.expectEqualStrings("second", set.probes[1].name());
}

test "calls past the budget are counted but not logged" {
    var set: ProbeSet = .{ .budget = 2 };
    _ = set.add(0x10, "f");
    try std.testing.expect(set.noteCall(0).log);
    try std.testing.expect(set.noteCall(0).log);
    const third = set.noteCall(0);
    try std.testing.expect(!third.log);
    try std.testing.expectEqual(@as(u64, 3), third.number);
}

test "requests split on separators and addresses parse" {
    var it = requests("_ZN3fooEv, 0x1411bf740;bar");
    try std.testing.expectEqualStrings("_ZN3fooEv", it.next().?);
    const address = it.next().?;
    try std.testing.expectEqual(@as(?u64, 0x1411bf740), parseAddress(address));
    try std.testing.expectEqualStrings("bar", it.next().?);
    try std.testing.expect(it.next() == null);
    try std.testing.expect(parseAddress("bar") == null);
}
