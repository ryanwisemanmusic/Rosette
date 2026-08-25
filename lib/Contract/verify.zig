const std = @import("std");
const contract = @import("contract.zig");
const runtime = @import("runtime.zig");

const MatchPattern = contract.MatchPattern;
const Contract = contract.Contract;
const DispatchOutcome = runtime.DispatchOutcome;

pub const VerificationEntry = struct {
    symbol: []const u8,
    expected: DispatchOutcome,
};

pub const VerificationTable = struct {
    entries: []const VerificationEntry,

    pub fn lookup(self: *const VerificationTable, symbol: []const u8) ?VerificationEntry {
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.symbol, symbol)) return entry;
        }
        return null;
    }
};

pub fn allEntries() []const VerificationEntry {
    return &.{
        // .terminate contracts
        .{ .symbol = "_exit", .expected = .{ .terminated = 0 } },
        .{ .symbol = "exit", .expected = .{ .terminated = 0 } },
        // .stub contracts (all return 0)
        .{ .symbol = "_pthread_attr_setstacksize", .expected = .{ .handled = 0 } },
        .{ .symbol = "_pthread_attr_destroy", .expected = .{ .handled = 0 } },
        .{ .symbol = "_objc_autoreleasePoolPop", .expected = .{ .handled = 0 } },
        .{ .symbol = "__shared_weak_count14__release_weakEv", .expected = .{ .handled = 0 } },
        .{ .symbol = "__ZNSt3__15mutex4lockEv", .expected = .{ .handled = 0 } },
        .{ .symbol = "__ZNSt3__15mutex6unlockEv", .expected = .{ .handled = 0 } },
        .{ .symbol = "__ZNSt3__15mutexD1Ev", .expected = .{ .handled = 0 } },
        .{ .symbol = "__ZNSt3__15mutexD2Ev", .expected = .{ .handled = 0 } },
        .{ .symbol = "__ZNSt3__16threadD1Ev", .expected = .{ .handled = 0 } },
        .{ .symbol = "__ZNSt3__16threadD2Ev", .expected = .{ .handled = 0 } },
        .{ .symbol = "__ZdlPv", .expected = .{ .handled = 0 } },
        .{ .symbol = "__ZdaPv", .expected = .{ .handled = 0 } },
        .{ .symbol = "_readdir$INODE64", .expected = .{ .handled = 0 } },
        .{ .symbol = "_readdir", .expected = .{ .handled = 0 } },
        .{ .symbol = "_pthread_join", .expected = .{ .handled = 0 } },
        .{ .symbol = "_pthread_detach", .expected = .{ .handled = 0 } },
        .{ .symbol = "_gtk_dialog_run", .expected = .{ .handled = 0 } },
        .{ .symbol = "_gtk_widget_destroy", .expected = .{ .handled = 0 } },
        .{ .symbol = "_gtk_box_pack_start", .expected = .{ .handled = 0 } },
        .{ .symbol = "_gtk_label_set_xalign", .expected = .{ .handled = 0 } },
        .{ .symbol = "_gtk_widget_set_margin_start", .expected = .{ .handled = 0 } },
        .{ .symbol = "_g_object_ref_sink", .expected = .{ .handled = 0 } },
        .{ .symbol = "__ZNSt3__18ios_base5clearEj", .expected = .{ .handled = 0 } },
        .{ .symbol = "_localtime", .expected = .{ .handled = 0 } },
        .{ .symbol = "_strftime", .expected = .{ .handled = 0 } },
        // .synthesize contracts with fixed values
        .{ .symbol = "_pthread_main_np", .expected = .{ .handled = 1 } },
        .{ .symbol = "_getuid", .expected = .{ .handled = 501 } },
        .{ .symbol = "_gtk_message_dialog_new", .expected = .{ .handled = 1 } },
        .{ .symbol = "_gtk_dialog_get_type", .expected = .{ .handled = 1 } },
        .{ .symbol = "_gtk_menu_bar_new", .expected = .{ .handled = 1 } },
        .{ .symbol = "_gtk_menu_item_new_with_mnemonic", .expected = .{ .handled = 1 } },
        .{ .symbol = "_gtk_box_new", .expected = .{ .handled = 1 } },
        .{ .symbol = "_gtk_box_get_type", .expected = .{ .handled = 1 } },
        .{ .symbol = "_gtk_label_new_with_mnemonic", .expected = .{ .handled = 1 } },
        .{ .symbol = "_gtk_label_get_type", .expected = .{ .handled = 1 } },
        .{ .symbol = "_gtk_label_new", .expected = .{ .handled = 1 } },
        .{ .symbol = "_gtk_menu_item_get_type", .expected = .{ .handled = 1 } },
    };
}

pub fn verifyDispatch(symbol: []const u8, outcome: DispatchOutcome, rdi: u64) bool {
    const table = VerificationTable{ .entries = allEntries() };
    const entry = table.lookup(symbol) orelse return true;
    return outcomesMatch(outcome, entry.expected, rdi);
}

fn outcomesMatch(actual: DispatchOutcome, expected: DispatchOutcome, rdi: u64) bool {
    return switch (actual) {
        .handled => |val| switch (expected) {
            .handled => |exp_val| val == exp_val,
            .terminated => false,
        },
        .terminated => |code| switch (expected) {
            .handled => false,
            .terminated => code == rdi & 0xFF,
        },
    };
}

pub fn resolveExpected(symbol: []const u8, rdi: u64) ?DispatchOutcome {
    const table = VerificationTable{ .entries = allEntries() };
    const entry = table.lookup(symbol) orelse return null;
    var result = entry.expected;
    switch (result) {
        .terminated => result = .{ .terminated = rdi & 0xFF },
        else => {},
    }
    return result;
}

test "all verification entries have registered symbols" {
    const rt = runtime;
    for (allEntries()) |entry| {
        const resolved = rt.resolveFromAllFamilies(entry.symbol);
        try std.testing.expect(resolved != null);
    }
}

test "verification matches contract dispatch for stub symbols" {
    const stubs = [_][]const u8{
        "_pthread_attr_destroy",
        "_pthread_join",
        "_objc_autoreleasePoolPop",
        "__shared_weak_count14__release_weakEv",
        "__ZNSt3__16threadD1Ev",
        "_gtk_dialog_run",
        "_gtk_widget_destroy",
        "_gtk_box_pack_start",
        "_gtk_label_set_xalign",
        "_gtk_widget_set_margin_start",
        "_g_object_ref_sink",
        "__ZNSt3__18ios_base5clearEj",
        "_localtime",
    };
    for (stubs) |sym| {
        // Assert the strategy, not just the outcome. A symbol that is not a
        // stub has no modelled outcome at all, so listing one here used to
        // fail on a null dispatch with nothing to say which entry was wrong.
        const resolved = runtime.resolveFromAllFamilies(sym) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(contract.ResolutionStrategy.stub, resolved.strategy);
        const outcome = runtime.dispatchFromAllFamilies(sym, 0);
        try std.testing.expect(outcome != null);
        try std.testing.expectEqual(@as(u64, 0), outcome.?.handled);
        try std.testing.expect(verifyDispatch(sym, outcome.?, 0));
    }
}

test "host-forwarded symbols resolve but have no modelled outcome" {
    // readdir fills a caller buffer and operator delete releases memory: a
    // stub returning zero for either would be a silent wrong answer, so both
    // forward to the host and dispatch deliberately produces nothing.
    const forwarded = [_][]const u8{ "_readdir", "__ZdlPv" };
    for (forwarded) |sym| {
        const resolved = runtime.resolveFromAllFamilies(sym) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(contract.ResolutionStrategy.forward_to_host, resolved.strategy);
        try std.testing.expect(runtime.dispatchFromAllFamilies(sym, 0) == null);
    }
}

test "verification matches contract dispatch for synthesize symbols" {
    const synths = [_]struct { sym: []const u8, val: u64 }{
        .{ .sym = "_pthread_main_np", .val = 1 },
        .{ .sym = "_getuid", .val = 501 },
        .{ .sym = "_gtk_message_dialog_new", .val = 1 },
        .{ .sym = "_gtk_dialog_get_type", .val = 1 },
        .{ .sym = "_gtk_menu_bar_new", .val = 1 },
        .{ .sym = "_gtk_menu_item_new_with_mnemonic", .val = 1 },
        .{ .sym = "_gtk_box_new", .val = 1 },
        .{ .sym = "_gtk_box_get_type", .val = 1 },
        .{ .sym = "_gtk_label_new_with_mnemonic", .val = 1 },
        .{ .sym = "_gtk_label_get_type", .val = 1 },
        .{ .sym = "_gtk_label_new", .val = 1 },
        .{ .sym = "_gtk_menu_item_get_type", .val = 1 },
    };
    for (synths) |s| {
        const outcome = runtime.dispatchFromAllFamilies(s.sym, 0);
        try std.testing.expect(outcome != null);
        try std.testing.expectEqual(s.val, outcome.?.handled);
        try std.testing.expect(verifyDispatch(s.sym, outcome.?, 0));
    }
}

test "verification matches contract dispatch for terminate symbols" {
    const outcome = runtime.dispatchFromAllFamilies("_exit", 42);
    try std.testing.expect(outcome != null);
    try std.testing.expectEqual(@as(u64, 42), outcome.?.terminated);
    try std.testing.expect(verifyDispatch("_exit", outcome.?, 42));
}

test "resolveExpected returns correct values" {
    const val = resolveExpected("_getuid", 0);
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(u64, 501), val.?.handled);

    const term = resolveExpected("_exit", 42);
    try std.testing.expect(term != null);
    try std.testing.expectEqual(@as(u64, 42), term.?.terminated);
}

test "resolveExpected returns null for unknown symbols" {
    try std.testing.expect(resolveExpected("_nonexistent_foo", 0) == null);
}

test "verifyDispatch returns true for unknown symbols" {
    try std.testing.expect(verifyDispatch("_unknown_sym", .{ .handled = 0 }, 0));
}
