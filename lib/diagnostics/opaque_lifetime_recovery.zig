const std = @import("std");

/// Cleanup may receive an opaque API identity after guest ownership metadata
/// has been corrupted. Recovery is intentionally narrower than a token-range
/// check: only a compiler-emitted Itanium destructor may discard that cleanup
/// frame, and only after the caller return address has been validated.
pub fn isItaniumDestructor(symbol: []const u8) bool {
    return std.mem.endsWith(u8, symbol, "D0Ev") or
        std.mem.endsWith(u8, symbol, "D1Ev") or
        std.mem.endsWith(u8, symbol, "D2Ev");
}

pub fn shouldQuarantine(symbol: []const u8, pointer_is_registered_opaque: bool, address_is_this: bool) bool {
    return pointer_is_registered_opaque and address_is_this and isItaniumDestructor(symbol);
}

test "only Itanium destructors may quarantine registered opaque this pointers" {
    try std.testing.expect(shouldQuarantine(
        "__ZN2xe9threading18MacConditionHandleINS0_6ThreadEED2Ev",
        true,
        true,
    ));
    try std.testing.expect(!shouldQuarantine("__ZN2xe9threading18MacConditionHandleINS0_6ThreadEE4WaitEv", true, true));
    try std.testing.expect(!shouldQuarantine("__ZN2xe9threading18MacConditionHandleINS0_6ThreadEED2Ev", false, true));
    try std.testing.expect(!shouldQuarantine("__ZN2xe9threading18MacConditionHandleINS0_6ThreadEED2Ev", true, false));
}
