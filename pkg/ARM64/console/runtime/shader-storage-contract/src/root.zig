//! ARM64-route source-backed facts for Xenia's shader-storage handoff.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_codegen = "arm64-native-bridge";
pub const blocking_timeout_ms: u32 = 5_000;
pub const request_owner = "xenia:graphics";
pub const completion_owner = "xenia:command_processor";

pub const Stage = enum(u2) {
    user_module_ready,
    shader_storage_requested,
    shader_storage_ready,
    guest_main_ready,
};

pub const CompletionMode = enum {
    blocking,
    asynchronous,
};

pub const Verdict = enum {
    incomplete,
    waiting,
    completed,
    explicit_timeout_continuation,
    ordering_violation,
};

pub const all_stages_mask: u8 = (@as(u8, 1) << (@as(u3, @intCast(@intFromEnum(Stage.guest_main_ready))) + 1)) - 1;

pub fn stageBit(stage: Stage) u8 {
    return @as(u8, 1) << @as(u3, @intFromEnum(stage));
}

pub fn orderValid(observed: u8) bool {
    const edges = [_]struct { from: Stage, to: Stage }{
        .{ .from = .user_module_ready, .to = .shader_storage_requested },
        .{ .from = .shader_storage_requested, .to = .shader_storage_ready },
        .{ .from = .shader_storage_ready, .to = .guest_main_ready },
    };
    for (edges) |edge| {
        if (observed & stageBit(edge.to) != 0 and observed & stageBit(edge.from) == 0) return false;
    }
    return true;
}

pub fn classify(observed: u8, mode: CompletionMode, timeout_continuation: bool) Verdict {
    if (!orderValid(observed)) return .ordering_violation;
    if (observed & stageBit(.user_module_ready) == 0 or
        observed & stageBit(.shader_storage_requested) == 0)
    {
        return .incomplete;
    }
    if (observed & stageBit(.shader_storage_ready) != 0) return .completed;
    if (timeout_continuation) {
        return if (mode == .blocking) .explicit_timeout_continuation else .ordering_violation;
    }
    return .waiting;
}

pub fn matchesReadyCompilerNames(names: []const []const u8) bool {
    const expected = [_][]const u8{
        "user_module_ready",
        "shader_storage_requested",
        "shader_storage_ready",
        "guest_main_ready",
    };
    if (names.len != expected.len) return false;
    for (expected, 0..) |name, index| {
        if (!std.mem.eql(u8, name, names[index])) return false;
    }
    return true;
}

pub fn contractIsWellFormed() bool {
    return blocking_timeout_ms == 5_000 and request_owner.len != 0 and completion_owner.len != 0 and
        orderValid(all_stages_mask) and classify(all_stages_mask, .blocking, false) == .completed;
}

test "completion requires an explicit ready edge" {
    const requested = stageBit(.user_module_ready) | stageBit(.shader_storage_requested);
    try std.testing.expectEqual(Verdict.waiting, classify(requested, .blocking, false));
    try std.testing.expectEqual(Verdict.explicit_timeout_continuation, classify(requested, .blocking, true));
    try std.testing.expectEqual(Verdict.completed, classify(requested | stageBit(.shader_storage_ready), .blocking, false));
    try std.testing.expectEqual(Verdict.ordering_violation, classify(stageBit(.guest_main_ready), .blocking, false));
    try std.testing.expectEqual(Verdict.ordering_violation, classify(requested, .asynchronous, true));
}

test "package matches the Ready Compiler stage spellings" {
    const names = [_][]const u8{
        "user_module_ready",
        "shader_storage_requested",
        "shader_storage_ready",
        "guest_main_ready",
    };
    try std.testing.expect(matchesReadyCompilerNames(names[0..]));
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expectEqual(@as(u32, 5_000), blocking_timeout_ms);
    try std.testing.expectEqualStrings("arm64", host_architecture);
}
