//! Policy for keeping expected optional IPC probes out of the run log.
//!
//! The file-failure ledger remains authoritative and keeps counting Discord's
//! absent Windows named-pipe probes. This module only decides when an
//! all-expected-IPC ledger is too noisy to report as a failure summary.

pub fn suppressOnlyUnavailableIpc(ledger: anytype) bool {
    if (ledger.count == 0) return false;
    for (ledger.entries[0..ledger.count]) |entry| {
        if (!std.mem.eql(u8, @tagName(entry.class), "named_pipe_without_server")) return false;
    }
    return true;
}

const std = @import("std");

test "only absent named-pipe IPC ledgers are suppressed" {
    const Class = enum { named_pipe_without_server, missing_path_open };
    const Entry = struct { class: Class };
    const Ledger = struct {
        entries: [2]Entry,
        count: usize,
    };

    var ipc_only = Ledger{
        .entries = .{ .{ .class = .named_pipe_without_server }, .{ .class = .named_pipe_without_server } },
        .count = 2,
    };
    try std.testing.expect(suppressOnlyUnavailableIpc(&ipc_only));
    ipc_only.count = 0;
    try std.testing.expect(!suppressOnlyUnavailableIpc(&ipc_only));
    ipc_only.count = 2;
    ipc_only.entries[1].class = .missing_path_open;
    try std.testing.expect(!suppressOnlyUnavailableIpc(&ipc_only));
}
