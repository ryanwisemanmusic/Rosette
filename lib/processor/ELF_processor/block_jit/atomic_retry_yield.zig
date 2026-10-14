//! Optional host scheduling hint for a narrowly proven atomic retry edge.
//!
//! This module owns the eligibility rule and the emitted branch sequence so
//! the block compiler only supplies facts from its decoded instruction pair.
//! The hint has no architectural effect; the caller must keep it on the
//! already-taken retry edge and preserve the original condition value.

pub fn eligible(
    enabled: bool,
    is_not_equal: bool,
    is_backward: bool,
    follows_locked_compare_exchange: bool,
) bool {
    return enabled and is_not_equal and is_backward and follows_locked_compare_exchange;
}

/// Emit the original taken edge with one host `YIELD` hint before retrying.
/// `compiler` supplies its assembler as `a` and an `emit(u32)` method.
pub fn emitTakenRetryHint(compiler: anytype, condition: anytype, target: anytype, hint: u32) !void {
    const fallthrough = try compiler.a.createLabel();
    try compiler.a.branchIfZero(.w32, condition, fallthrough);
    try compiler.emit(hint);
    try compiler.a.branch(target);
    compiler.a.placeLabel(fallthrough);
}

test "atomic retry hint requires the complete narrow predicate" {
    const std = @import("std");
    const testing = std.testing;

    try testing.expect(eligible(true, true, true, true));
    try testing.expect(!eligible(false, true, true, true));
    try testing.expect(!eligible(true, false, true, true));
    try testing.expect(!eligible(true, true, false, true));
    try testing.expect(!eligible(true, true, true, false));
}
