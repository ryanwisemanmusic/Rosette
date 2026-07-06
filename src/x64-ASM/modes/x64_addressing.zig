const std = @import("std");
const memory = @import("x64_memory.zig");

/// x64 addressing forms and their availability per operating mode
pub const AddressingForm = enum {
    /// Direct addressing: address specified directly in instruction
    direct,
    /// Register addressing: operand in register
    register,
    /// Register indirect: address in register
    indirect,
    /// Indexed: base + index
    indexed,
    /// Base + index + scale + displacement (SIB)
    base_index_scale_disp,
    /// RIP-relative addressing (64-bit mode only)
    rip_relative,
};

/// Effective address computation components (64-bit)
pub const EffectiveAddress = struct {
    base: ?u64 = null,
    index: ?u64 = null,
    scale: u2 = 0, // 0=1, 1=2, 2=4, 3=8 (SIB encoding)
    displacement: i32 = 0,

    pub fn compute(self: *const EffectiveAddress) u64 {
        var addr: u64 = 0;
        if (self.base) |b| addr += b;
        if (self.index) |i| {
            const multiplier: u64 = switch (self.scale) {
                0 => 1,
                1 => 2,
                2 => 4,
                3 => 8,
            };
            addr += i * multiplier;
        }
        addr +%= @bitCast(@as(i64, @intCast(self.displacement)));
        return addr;
    }

    pub fn isValid(self: *const EffectiveAddress) bool {
        _ = self;
        // Scale field is u2, so only values 0-3 are possible (all valid)
        // Scale values map to multipliers: 0->1, 1->2, 2->4, 3->8
        // If index is present, scale must be valid (always true for u2)
        // RSP cannot be used as index register in SIB
        return true;
    }

    /// Check if computed address is canonical
    pub fn isCanonical(self: *const EffectiveAddress) bool {
        const addr = self.compute();
        return memory.isCanonicalAddress(addr);
    }
};

/// 64-bit SIB (Scale-Index-Base) byte decoding
pub const SibByte = packed struct {
    scale: u2, // 00=1, 01=2, 10=4, 11=8
    index: u3, // Index register
    base: u3, // Base register

    pub fn scaleMultiplier(self: *const SibByte) u64 {
        return switch (self.scale) {
            0 => 1,
            1 => 2,
            2 => 4,
            3 => 8,
        };
    }
};

/// Addressing capabilities per operating mode
pub const AddressingCapabilities = struct {
    supports_32bit: bool,
    supports_64bit: bool,
    supports_sib: bool,
    supports_rip_relative: bool,
    supports_segment_override: bool,
    fs_gs_base_writable: bool,
};

/// Get addressing capabilities for operating mode
pub fn addressingCapabilitiesFor(mode: memory.OperatingMode) AddressingCapabilities {
    return switch (mode) {
        .long_mode => .{
            .supports_32bit = true, // Via address-size override
            .supports_64bit = true,
            .supports_sib = true,
            .supports_rip_relative = true,
            .supports_segment_override = false, // Limited in 64-bit mode
            .fs_gs_base_writable = true,
        },
        .compatibility => .{
            .supports_32bit = true,
            .supports_64bit = false,
            .supports_sib = true,
            .supports_rip_relative = false,
            .supports_segment_override = true,
            .fs_gs_base_writable = false,
        },
        .system_management => .{
            .supports_32bit = true,
            .supports_64bit = false,
            .supports_sib = false,
            .supports_rip_relative = false,
            .supports_segment_override = true,
            .fs_gs_base_writable = false,
        },
    };
}

/// Address size in x64 mode
pub const AddressSize = enum(u8) {
    bits32 = 32,
    bits64 = 64,
};

/// Segment override prefixes (limited in 64-bit mode)
pub const SegmentOverride = enum {
    none,
    cs,
    ds,
    es,
    fs,
    gs,
    ss,
};

/// Default segment for addressing mode in 64-bit mode
/// In 64-bit mode, only FS and GS can have non-zero bases
pub fn defaultSegmentForAddressing(form: AddressingForm, base_reg: ?u8) SegmentOverride {
    _ = base_reg;
    return switch (form) {
        .register => .none,
        .direct => .ds, // Base is 0 anyway
        .indirect, .indexed, .base_index_scale_disp => {
            // In 64-bit mode, DS base is 0, so this doesn't matter much
            // FS/GS can have non-zero bases
            return .ds;
        },
        .rip_relative => .none, // RIP-relative is always relative to CS (base = 0)
    };
}

/// Check if segment override is effective in given mode
pub fn isSegmentOverrideEffective(mode: memory.OperatingMode, override: SegmentOverride) bool {
    return switch (mode) {
        .long_mode => {
            // In 64-bit mode, only FS and GS overrides are effective
            // CS, DS, ES, SS bases are forced to 0
            return override == .fs or override == .gs;
        },
        .compatibility => {
            // In compatibility mode, all segment overrides work
            return override != .none;
        },
        .system_management => {
            // In SMM, segment overrides work
            return override != .none;
        },
    };
}

/// Check if addressing form is available in given mode
pub fn isAddressingFormAvailable(form: AddressingForm, mode: memory.OperatingMode, addr_size: AddressSize) bool {
    const caps = addressingCapabilitiesFor(mode);

    return switch (form) {
        .direct => true,
        .register => true,
        .indirect => true,
        .indexed => addr_size == .bits64 and caps.supports_64bit,
        .base_index_scale_disp => (addr_size == .bits64 and caps.supports_sib) or (addr_size == .bits32 and caps.supports_32bit),
        .rip_relative => addr_size == .bits64 and caps.supports_rip_relative,
    };
}

/// Compute effective address with segment override (64-bit mode)
pub fn computeAddressWithSegment(
    config: *const memory.MemoryModelConfig,
    form: AddressingForm,
    ea: EffectiveAddress,
    override: SegmentOverride,
) !u64 {
    _ = form;
    const effective_addr = ea.compute();

    // Check canonicality
    if (!memory.isCanonicalAddress(effective_addr)) {
        return error.NonCanonicalAddress;
    }

    // Apply segment base if relevant
    // In 64-bit mode, only FS and GS can have non-zero bases
    const seg_override = if (isSegmentOverrideEffective(config.operating_mode, override))
        override
    else
        .none;

    const seg_base = switch (seg_override) {
        .none => 0,
        .fs => config.fs.base,
        .gs => config.gs.base,
        .cs, .ds, .es, .ss => 0, // Forced to 0 in 64-bit mode
    };

    const linear_addr = seg_base + effective_addr;

    // Check canonicality of result
    if (!memory.isCanonicalAddress(linear_addr)) {
        return error.NonCanonicalAddress;
    }

    return linear_addr;
}

/// RIP-relative addressing computation
pub fn computeRipRelative(rip: u64, displacement: i32) u64 {
    const sign_extended: i64 = @intCast(displacement);
    return @intCast(@as(i64, @intCast(rip)) + sign_extended);
}

/// Register encoding for 64-bit addressing
pub const Register64 = enum(u3) {
    rax = 0,
    rcx = 1,
    rdx = 2,
    rbx = 3,
    rsp = 4,
    rbp = 5,
    rsi = 6,
    rdi = 7,
};

/// Extended registers (R8-R15) in REX prefix
pub const Register64Extended = enum(u4) {
    r8 = 8,
    r9 = 9,
    r10 = 10,
    r11 = 11,
    r12 = 12,
    r13 = 13,
    r14 = 14,
    r15 = 15,
};

/// Check if register can be used as base in SIB
pub fn isValidBaseReg(reg: u4, mode: memory.OperatingMode) bool {
    // RSP cannot be used as index, but can be used as base
    // R12 (extended RSP) has same restriction
    return switch (mode) {
        .long_mode => true, // All registers valid as base
        .compatibility => reg < 8, // Only legacy registers in compatibility mode
        .system_management => reg < 8,
    };
}

/// Check if register can be used as index in SIB
pub fn isValidIndexReg(reg: u4, mode: memory.OperatingMode) bool {
    // RSP and R12 cannot be used as index
    const is_rsp = reg == 4 or reg == 12;
    if (is_rsp) return false;

    return switch (mode) {
        .long_mode => true,
        .compatibility => reg < 8,
        .system_management => reg < 8,
    };
}

test "addressing capabilities per mode" {
    const long_caps = addressingCapabilitiesFor(.long_mode);
    try std.testing.expect(long_caps.supports_64bit);
    try std.testing.expect(long_caps.supports_rip_relative);
    try std.testing.expect(long_caps.fs_gs_base_writable);
    try std.testing.expect(!long_caps.supports_segment_override);

    const compat_caps = addressingCapabilitiesFor(.compatibility);
    try std.testing.expect(compat_caps.supports_32bit);
    try std.testing.expect(!compat_caps.supports_64bit);
    try std.testing.expect(!compat_caps.supports_rip_relative);
    try std.testing.expect(compat_caps.supports_segment_override);
}

test "effective address computation" {
    const ea = EffectiveAddress{
        .base = 0x1000,
        .index = 0x0200,
        .scale = 2, // scale = 2 means multiplier of 4
        .displacement = 0x10,
    };
    const addr = ea.compute();
    try std.testing.expectEqual(@as(u64, 0x1000 + 0x0200 * 4 + 0x10), addr);
}

test "effective address canonicality check" {
    const canonical_ea = EffectiveAddress{
        .base = 0x0000_1000,
        .displacement = 0,
    };
    try std.testing.expect(canonical_ea.isCanonical());

    const non_canonical_ea = EffectiveAddress{
        .base = 0x0000_8000_0000_0000,
        .displacement = 0,
    };
    try std.testing.expect(!non_canonical_ea.isCanonical());
}

test "SIB byte scale multiplier" {
    const sib1 = SibByte{ .scale = 0, .index = 0, .base = 0 };
    try std.testing.expectEqual(@as(u64, 1), sib1.scaleMultiplier());

    const sib2 = SibByte{ .scale = 1, .index = 0, .base = 0 };
    try std.testing.expectEqual(@as(u64, 2), sib2.scaleMultiplier());

    const sib4 = SibByte{ .scale = 2, .index = 0, .base = 0 };
    try std.testing.expectEqual(@as(u64, 4), sib4.scaleMultiplier());

    const sib8 = SibByte{ .scale = 3, .index = 0, .base = 0 };
    try std.testing.expectEqual(@as(u64, 8), sib8.scaleMultiplier());
}

test "segment override effectiveness" {
    try std.testing.expect(isSegmentOverrideEffective(.long_mode, .fs));
    try std.testing.expect(isSegmentOverrideEffective(.long_mode, .gs));
    try std.testing.expect(!isSegmentOverrideEffective(.long_mode, .ds));
    try std.testing.expect(!isSegmentOverrideEffective(.long_mode, .cs));

    try std.testing.expect(isSegmentOverrideEffective(.compatibility, .ds));
    try std.testing.expect(isSegmentOverrideEffective(.compatibility, .fs));
}

test "addressing form availability" {
    try std.testing.expect(isAddressingFormAvailable(.direct, .long_mode, .bits64));
    try std.testing.expect(isAddressingFormAvailable(.indexed, .long_mode, .bits64));
    try std.testing.expect(isAddressingFormAvailable(.base_index_scale_disp, .long_mode, .bits64));
    try std.testing.expect(isAddressingFormAvailable(.rip_relative, .long_mode, .bits64));
    try std.testing.expect(!isAddressingFormAvailable(.rip_relative, .compatibility, .bits32));

    try std.testing.expect(isAddressingFormAvailable(.base_index_scale_disp, .compatibility, .bits32));
    try std.testing.expect(!isAddressingFormAvailable(.indexed, .compatibility, .bits64));
}

test "compute address with segment override" {
    var config = memory.longModeDefaults();
    config.fs.base = 0x1000;

    const ea = EffectiveAddress{
        .base = 0x0200,
        .displacement = 0x10,
    };

    const addr = try computeAddressWithSegment(&config, .indirect, ea, .fs);
    try std.testing.expectEqual(@as(u64, 0x1000 + 0x0200 + 0x10), addr);
}

test "compute address with non-canonical error" {
    const config = memory.longModeDefaults();

    const ea = EffectiveAddress{
        .base = 0x0000_8000_0000_0000,
        .displacement = 0,
    };

    const result = computeAddressWithSegment(&config, .indirect, ea, .none);
    try std.testing.expectError(error.NonCanonicalAddress, result);
}

test "RIP-relative addressing" {
    const rip: u64 = 0x1_0000_4000;
    const displacement: i32 = 0x100;
    const addr = computeRipRelative(rip, displacement);
    try std.testing.expectEqual(@as(u64, 0x1_0000_4100), addr);

    const neg_disp: i32 = -0x100;
    const addr_neg = computeRipRelative(rip, neg_disp);
    try std.testing.expectEqual(@as(u64, 0x1_0000_3F00), addr_neg);
}

test "valid base and index registers" {
    try std.testing.expect(isValidBaseReg(0, .long_mode)); // RAX
    try std.testing.expect(isValidBaseReg(4, .long_mode)); // RSP (valid as base)
    try std.testing.expect(!isValidIndexReg(4, .long_mode)); // RSP (invalid as index)
    try std.testing.expect(!isValidIndexReg(12, .long_mode)); // R12 (invalid as index)

    try std.testing.expect(isValidBaseReg(0, .compatibility));
    try std.testing.expect(!isValidBaseReg(8, .compatibility)); // R8 (not in compatibility mode)
}
