const std = @import("std");

/// Canonical execution/assembly mode for instruction decode.
///
/// This is the central hub type in the ISA layer for ASM-flavor
/// awareness: every decoder (16-bit DOS real mode, 32-bit x86, 64-bit
/// Mach-O/ELF) reports which flavor it is decoding through this enum.
/// Mode drives the real behavioral differences between flavors:
/// REX consumption, inc/dec vs REX bytes (0x40-0x4F), default operand
/// and address sizes, and real-mode segment addressing.
pub const ExecutionMode = enum(u8) {
    /// 16-bit real-address mode (DOS, segmented addressing).
    real16,
    /// 32-bit protected mode (native 32-bit PE/raw binaries).
    protected,
    /// 32-bit compatibility mode running under a 64-bit OS.
    compatibility,
    /// 64-bit long mode (Mach-O / ELF).
    long64,

    /// Native bit width of the mode.
    pub fn bits(self: ExecutionMode) u8 {
        return switch (self) {
            .real16 => 16,
            .protected, .compatibility => 32,
            .long64 => 64,
        };
    }

    pub fn is16(self: ExecutionMode) bool {
        return self == .real16;
    }

    pub fn is32(self: ExecutionMode) bool {
        return self == .protected or self == .compatibility;
    }

    pub fn is64(self: ExecutionMode) bool {
        return self == .long64;
    }

    /// REX prefixes only exist in 64-bit long mode.
    pub fn rexAllowed(self: ExecutionMode) bool {
        return self == .long64;
    }

    /// Default address size before any 0x67 override.
    pub fn defaultAddressBits(self: ExecutionMode) u8 {
        return switch (self) {
            .real16 => 16,
            .protected, .compatibility => 32,
            .long64 => 64,
        };
    }

    /// Default operand size before any 0x66 / REX.W override.
    pub fn defaultOperandBits(self: ExecutionMode) u8 {
        return switch (self) {
            .real16 => 16,
            .protected, .compatibility => 32,
            .long64 => 32,
        };
    }

    pub fn fromBits(width_bits: u16) ?ExecutionMode {
        return switch (width_bits) {
            16 => .real16,
            32 => .protected,
            64 => .long64,
            else => null,
        };
    }
};

test "execution mode reports correct widths" {
    try std.testing.expectEqual(@as(u8, 16), ExecutionMode.real16.bits());
    try std.testing.expectEqual(@as(u8, 32), ExecutionMode.protected.bits());
    try std.testing.expectEqual(@as(u8, 32), ExecutionMode.compatibility.bits());
    try std.testing.expectEqual(@as(u8, 64), ExecutionMode.long64.bits());
}

test "execution mode flavor predicates" {
    try std.testing.expect(ExecutionMode.real16.is16());
    try std.testing.expect(!ExecutionMode.real16.is32());
    try std.testing.expect(ExecutionMode.protected.is32());
    try std.testing.expect(ExecutionMode.compatibility.is32());
    try std.testing.expect(ExecutionMode.long64.is64());
    try std.testing.expect(!ExecutionMode.long64.is32());
}

test "rex and default sizes follow mode semantics" {
    try std.testing.expect(!ExecutionMode.real16.rexAllowed());
    try std.testing.expect(!ExecutionMode.protected.rexAllowed());
    try std.testing.expect(ExecutionMode.long64.rexAllowed());

    try std.testing.expectEqual(@as(u8, 16), ExecutionMode.real16.defaultAddressBits());
    try std.testing.expectEqual(@as(u8, 32), ExecutionMode.protected.defaultAddressBits());
    try std.testing.expectEqual(@as(u8, 64), ExecutionMode.long64.defaultAddressBits());

    // 64-bit long mode defaults to 32-bit operands (REX.W widens).
    try std.testing.expectEqual(@as(u8, 16), ExecutionMode.real16.defaultOperandBits());
    try std.testing.expectEqual(@as(u8, 32), ExecutionMode.long64.defaultOperandBits());
}

test "fromBits round-trips every mode" {
    try std.testing.expectEqual(ExecutionMode.real16, ExecutionMode.fromBits(16).?);
    try std.testing.expectEqual(ExecutionMode.protected, ExecutionMode.fromBits(32).?);
    try std.testing.expectEqual(ExecutionMode.long64, ExecutionMode.fromBits(64).?);
    try std.testing.expect(ExecutionMode.fromBits(0) == null);
    try std.testing.expect(ExecutionMode.fromBits(128) == null);
}
