//! Why guest store buffers drained, and whether an execution tier ever saw a
//! stale view of its own stores.
//!
//! The hybrid memory model has two tiers that write guest memory in two
//! different ways. The interpreter queues each store in its executor's
//! buffer and forwards it to that executor's own loads; translated blocks and
//! Rosette's runtime shims write memory directly. Both are x86-TSO as long as
//! the buffer is empty at every point where the other tier takes over. When
//! it is not, the direct tier reads memory without the queued bytes and its
//! own later stores are overwritten when the queue drains - a stale load and
//! a lost update, both inside one guest thread. The 2026-09-24 Halo 3 run did
//! exactly that on every interpreted fallback inside a translated block: fmt
//! read a string_view the fallback had just stored, Xenia's log file was
//! created as `0H;C\x01.log` and its config was written full of NULs.
//!
//! Every drain at a tier boundary is counted here under the boundary that
//! caused it, and the one check that must never fire - translated code
//! entered while its executor still held buffered stores - is counted with
//! the first place it fired. The exit report prints both.

const std = @import("std");

pub const Boundary = enum(u8) {
    /// An interpreted instruction inside a translated block finished.
    jit_fallback,
    /// Translated code was about to run (block entry, chain, verification).
    jit_entry,
    /// A translated block's memory helper crossed into the interpreter's
    /// memory model.
    jit_helper,
    /// A Rosette runtime call (import, shim, hook) began or ended.
    runtime_call,
    /// A guest thread's slice began or ended on the one host thread.
    context_switch,
    /// A guest thread finished; its stack may be released.
    thread_exit,
    /// A host slice of guest memory was handed to Rosette code.
    raw_view,
    /// MFENCE, SFENCE or a LOCK-prefixed read-modify-write.
    fence,
    /// A store touched executable bytes; decode caches are invalidated next.
    code_write,
    /// Parallel/serial execution changed, or mappings are being torn down.
    mode_change,
    /// The run ended.
    shutdown,
    /// A caller that has not named its boundary.
    unattributed,
};

pub const boundary_count = @typeInfo(Boundary).@"enum".fields.len;

const Counter = std.atomic.Value(u64);

const Ledger = struct {
    /// Flushes that found at least one buffered store, per boundary.
    flushes: [boundary_count]Counter = @splat(Counter.init(0)),
    /// Stores those flushes made visible, per boundary.
    entries: [boundary_count]Counter = @splat(Counter.init(0)),
    /// Translated code entered while its executor still held buffered
    /// stores. Always a Rosette defect: the block would have read memory
    /// without them.
    translated_entry_violations: Counter = Counter.init(0),
    translated_entry_violation_entries: Counter = Counter.init(0),
    first_violation_rip: Counter = Counter.init(0),
    first_violation_boundary: std.atomic.Value(u8) = std.atomic.Value(u8).init(0xFF),
};

var ledger: Ledger = .{};

/// Count one flush that made `drained` stores visible at `boundary`.
pub fn noteFlush(boundary: Boundary, drained: usize) void {
    if (drained == 0) return;
    const index = @intFromEnum(boundary);
    _ = ledger.flushes[index].fetchAdd(1, .monotonic);
    _ = ledger.entries[index].fetchAdd(drained, .monotonic);
}

/// Count a translated-code entry that found `pending` buffered stores.
/// Returns true for the first violation of the run, so the caller can log
/// it with everything it knows about the site.
pub fn noteTranslatedEntryViolation(boundary: Boundary, pending: usize, rip: u64) bool {
    const previous = ledger.translated_entry_violations.fetchAdd(1, .monotonic);
    _ = ledger.translated_entry_violation_entries.fetchAdd(pending, .monotonic);
    if (previous != 0) return false;
    ledger.first_violation_rip.store(rip, .monotonic);
    ledger.first_violation_boundary.store(@intFromEnum(boundary), .monotonic);
    return true;
}

pub const Snapshot = struct {
    flushes: [boundary_count]u64 = @splat(0),
    entries: [boundary_count]u64 = @splat(0),
    translated_entry_violations: u64 = 0,
    translated_entry_violation_entries: u64 = 0,
    first_violation_rip: u64 = 0,
    first_violation_boundary: ?Boundary = null,

    pub fn totalFlushes(self: Snapshot) u64 {
        var total: u64 = 0;
        for (self.flushes) |value| total +|= value;
        return total;
    }

    /// `jit_fallback=12/40 runtime_call=3/9 ...` for every boundary that
    /// drained anything, as flushes/entries.
    pub fn formatBoundaries(self: Snapshot, buffer: []u8) []const u8 {
        var used: usize = 0;
        for (0..boundary_count) |index| {
            if (self.flushes[index] == 0) continue;
            const boundary: Boundary = @enumFromInt(index);
            const written = std.fmt.bufPrint(buffer[used..], "{s}{s}={d}/{d}", .{
                if (used == 0) "" else " ",
                @tagName(boundary),
                self.flushes[index],
                self.entries[index],
            }) catch return buffer[0..used];
            used += written.len;
        }
        if (used == 0) {
            const none = "none";
            if (buffer.len < none.len) return buffer[0..0];
            @memcpy(buffer[0..none.len], none);
            return buffer[0..none.len];
        }
        return buffer[0..used];
    }
};

pub fn snapshot() Snapshot {
    var result: Snapshot = .{};
    for (0..boundary_count) |index| {
        result.flushes[index] = ledger.flushes[index].load(.monotonic);
        result.entries[index] = ledger.entries[index].load(.monotonic);
    }
    result.translated_entry_violations = ledger.translated_entry_violations.load(.monotonic);
    result.translated_entry_violation_entries = ledger.translated_entry_violation_entries.load(.monotonic);
    result.first_violation_rip = ledger.first_violation_rip.load(.monotonic);
    const boundary = ledger.first_violation_boundary.load(.monotonic);
    result.first_violation_boundary = if (boundary < boundary_count) @enumFromInt(boundary) else null;
    return result;
}

/// Tests only: the ledger is process-wide.
pub fn resetForTest() void {
    ledger = .{};
}

test "flushes are counted per boundary and empty flushes are not" {
    resetForTest();
    defer resetForTest();
    noteFlush(.jit_fallback, 3);
    noteFlush(.jit_fallback, 1);
    noteFlush(.runtime_call, 0);
    noteFlush(.context_switch, 2);
    const result = snapshot();
    try std.testing.expectEqual(@as(u64, 2), result.flushes[@intFromEnum(Boundary.jit_fallback)]);
    try std.testing.expectEqual(@as(u64, 4), result.entries[@intFromEnum(Boundary.jit_fallback)]);
    try std.testing.expectEqual(@as(u64, 0), result.flushes[@intFromEnum(Boundary.runtime_call)]);
    try std.testing.expectEqual(@as(u64, 3), result.totalFlushes());
    var text: [256]u8 = undefined;
    try std.testing.expectEqualStrings("jit_fallback=2/4 context_switch=1/2", result.formatBoundaries(&text));
}

test "only the first translated-entry violation asks to be logged" {
    resetForTest();
    defer resetForTest();
    try std.testing.expect(noteTranslatedEntryViolation(.jit_entry, 2, 0x1400_1000));
    try std.testing.expect(!noteTranslatedEntryViolation(.jit_fallback, 5, 0x1400_2000));
    const result = snapshot();
    try std.testing.expectEqual(@as(u64, 2), result.translated_entry_violations);
    try std.testing.expectEqual(@as(u64, 7), result.translated_entry_violation_entries);
    try std.testing.expectEqual(@as(u64, 0x1400_1000), result.first_violation_rip);
    try std.testing.expectEqual(Boundary.jit_entry, result.first_violation_boundary.?);
}

test "an empty ledger formats as none" {
    resetForTest();
    defer resetForTest();
    var text: [16]u8 = undefined;
    try std.testing.expectEqualStrings("none", snapshot().formatBoundaries(&text));
}
