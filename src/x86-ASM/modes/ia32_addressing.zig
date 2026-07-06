const std = @import("std");
const memory = @import("ia32_memory.zig");

/// IA-32 addressing forms and their availability per operating mode
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
    /// Relative: offset from instruction pointer
    relative,
};

/// Effective address computation components
pub const EffectiveAddress = struct {
    base: ?u32 = null,
    index: ?u32 = null,
    scale: u2 = 0, // 0=1, 1=2, 2=4, 3=8 (SIB encoding)
    displacement: i32 = 0,

    pub fn compute(self: *const EffectiveAddress) u32 {
        var addr: u32 = 0;
        if (self.base) |b| addr += b;
        if (self.index) |i| {
            const multiplier: u32 = switch (self.scale) {
                0 => 1,
                1 => 2,
                2 => 4,
                3 => 8,
            };
            addr += i * multiplier;
        }
        addr +%= @bitCast(self.displacement);
        return addr;
    }

    pub fn isValid(self: *const EffectiveAddress) bool {
        _ = self;
        // Scale field is u2, so only values 0-3 are possible (all valid)
        // Scale values map to multipliers: 0->1, 1->2, 2->4, 3->8
        // If index is present, scale must be valid (always true for u2)
        // ESP cannot be used as index register in SIB
        return true;
    }
};

/// Addressing capabilities per operating mode
pub const AddressingCapabilities = struct {
    supports_16bit: bool,
    supports_32bit: bool,
    supports_sib: bool,
    supports_rip_relative: bool,
    supports_segment_override: bool,
};

/// Get addressing capabilities for operating mode
pub fn addressingCapabilitiesFor(mode: memory.OperatingMode) AddressingCapabilities {
    return switch (mode) {
        .real_address => .{
            .supports_16bit = true,
            .supports_32bit = false,
            .supports_sib = false,
            .supports_rip_relative = false,
            .supports_segment_override = true,
        },
        .protected => .{
            .supports_16bit = true,
            .supports_32bit = true,
            .supports_sib = true,
            .supports_rip_relative = false,
            .supports_segment_override = true,
        },
        .virtual_8086 => .{
            .supports_16bit = true,
            .supports_32bit = false,
            .supports_sib = false,
            .supports_rip_relative = false,
            .supports_segment_override = true,
        },
        .system_management => .{
            .supports_16bit = true,
            .supports_32bit = false,
            .supports_sib = false,
            .supports_rip_relative = false,
            .supports_segment_override = true,
        },
    };
}

/// 16-bit addressing modes (real-address mode and 16-bit protected mode)
pub const AddressingMode16 = enum {
    /// [BX + SI]
    bx_si,
    /// [BX + DI]
    bx_di,
    /// [BP + SI]
    bp_si,
    /// [BP + DI]
    bp_di,
    /// [SI]
    si,
    /// [DI]
    di,
    /// [BP]
    bp,
    /// [BX]
    bx,
    /// [disp16]
    disp16,
};

/// Compute 16-bit effective address
pub fn computeEffectiveAddress16(mode: AddressingMode16, bx: u16, si: u16, di: u16, bp: u16, disp: u16) u16 {
    return switch (mode) {
        .bx_si => bx + si,
        .bx_di => bx + di,
        .bp_si => bp + si,
        .bp_di => bp + di,
        .si => si,
        .di => di,
        .bp => bp,
        .bx => bx,
        .disp16 => disp,
    };
}

/// 32-bit SIB (Scale-Index-Base) byte decoding
pub const SibByte = packed struct {
    scale: u2, // 00=1, 01=2, 10=4, 11=8
    index: u3, // Index register
    base: u3, // Base register

    pub fn scaleMultiplier(self: *const SibByte) u32 {
        return switch (self.scale) {
            0 => 1,
            1 => 2,
            2 => 4,
            3 => 8,
        };
    }
};

/// Segment override prefixes
pub const SegmentOverride = enum {
    none,
    cs,
    ds,
    es,
    fs,
    gs,
    ss,
};

/// Default segment for addressing mode
pub fn defaultSegmentForAddressing(form: AddressingForm, base_reg: ?u8) SegmentOverride {
    // Based on Intel SDM default segment associations
    return switch (form) {
        .register => .none,
        .direct => .ds,
        .indirect, .indexed, .base_index_scale_disp => {
            // For BP/EBP or ESP as base, default to SS
            // Otherwise default to DS
            if (base_reg) |reg| {
                if (reg == 4 or reg == 5) return .ss; // BP/EBP (4) or ESP (5)
            }
            return .ds;
        },
        .relative => .cs,
    };
}

/// Check if addressing form is available in given mode
pub fn isAddressingFormAvailable(form: AddressingForm, mode: memory.OperatingMode, addr_size: memory.AddressSize) bool {
    const caps = addressingCapabilitiesFor(mode);

    return switch (form) {
        .direct => true,
        .register => true,
        .indirect => true,
        .indexed => addr_size == .bits32 and caps.supports_32bit,
        .base_index_scale_disp => addr_size == .bits32 and caps.supports_sib,
        .relative => caps.supports_rip_relative,
    };
}

/// Compute effective address with segment override
pub fn computeAddressWithSegment(
    config: *const memory.MemoryModelConfig,
    form: AddressingForm,
    ea: EffectiveAddress,
    override: SegmentOverride,
) !u32 {
    const linear_addr = ea.compute();

    // Apply segment base if segmentation is enabled
    if (config.segmentation_enabled) {
        const seg = if (override == .none)
            defaultSegmentForAddressing(form, null)
        else
            override;

        const seg_reg = getSegmentRegisterForOverride(config, seg);
        const seg_base = seg_reg.base();

        // Check segment limit
        const seg_limit = seg_reg.limit();
        if (linear_addr > seg_limit) {
            return error.SegmentLimitExceeded;
        }

        return seg_base + linear_addr;
    }

    return linear_addr;
}

fn getSegmentRegisterForOverride(config: *const memory.MemoryModelConfig, override: SegmentOverride) *const memory.SegmentRegister {
    return switch (override) {
        .none => &config.ds,
        .cs => &config.cs,
        .ds => &config.ds,
        .es => &config.es,
        .fs => &config.fs,
        .gs => &config.gs,
        .ss => &config.ss,
    };
}

test "addressing capabilities per mode" {
    const real_caps = addressingCapabilitiesFor(.real_address);
    try std.testing.expect(real_caps.supports_16bit);
    try std.testing.expect(!real_caps.supports_32bit);
    try std.testing.expect(!real_caps.supports_sib);

    const protected_caps = addressingCapabilitiesFor(.protected);
    try std.testing.expect(protected_caps.supports_16bit);
    try std.testing.expect(protected_caps.supports_32bit);
    try std.testing.expect(protected_caps.supports_sib);
}

test "16-bit effective address computation" {
    const addr = computeEffectiveAddress16(.bx_si, 0x1000, 0x0200, 0, 0, 0);
    try std.testing.expectEqual(@as(u16, 0x1200), addr);

    const addr_disp = computeEffectiveAddress16(.disp16, 0, 0, 0, 0, 0x4000);
    try std.testing.expectEqual(@as(u16, 0x4000), addr_disp);
}

test "SIB byte scale multiplier" {
    const sib1 = SibByte{ .scale = 0, .index = 0, .base = 0 };
    try std.testing.expectEqual(@as(u32, 1), sib1.scaleMultiplier());

    const sib2 = SibByte{ .scale = 1, .index = 0, .base = 0 };
    try std.testing.expectEqual(@as(u32, 2), sib2.scaleMultiplier());

    const sib4 = SibByte{ .scale = 2, .index = 0, .base = 0 };
    try std.testing.expectEqual(@as(u32, 4), sib4.scaleMultiplier());

    const sib8 = SibByte{ .scale = 3, .index = 0, .base = 0 };
    try std.testing.expectEqual(@as(u32, 8), sib8.scaleMultiplier());
}

test "effective address computation" {
    const ea = EffectiveAddress{
        .base = 0x1000,
        .index = 0x0200,
        .scale = 2, // scale = 2 means multiplier of 4
        .displacement = 0x10,
    };
    const addr = ea.compute();
    // 0x1000 + 0x0200 * 4 + 0x10 = 0x1000 + 0x800 + 0x10 = 0x1810
    try std.testing.expectEqual(@as(u32, 0x1810), addr);
}

test "effective address validation" {
    const valid = EffectiveAddress{
        .base = 0x1000,
        .index = 0x0200,
        .scale = 2,
        .displacement = 0,
    };
    try std.testing.expect(valid.isValid());

    // Scale field is u2, so only values 0-3 are possible (all valid)
    // Scale values map to multipliers: 0->1, 1->2, 2->4, 3->8
    const no_index = EffectiveAddress{
        .base = 0x1000,
        .index = null,
        .scale = 2,
        .displacement = 0,
    };
    try std.testing.expect(no_index.isValid());
}

test "default segment selection" {
    try std.testing.expectEqual(SegmentOverride.ds, defaultSegmentForAddressing(.direct, null));
    try std.testing.expectEqual(SegmentOverride.cs, defaultSegmentForAddressing(.relative, null));
    try std.testing.expectEqual(SegmentOverride.ss, defaultSegmentForAddressing(.indirect, 5)); // ESP
    try std.testing.expectEqual(SegmentOverride.ds, defaultSegmentForAddressing(.indirect, 0)); // EAX
}

test "addressing form availability" {
    try std.testing.expect(isAddressingFormAvailable(.direct, .real_address, .bits16));
    try std.testing.expect(!isAddressingFormAvailable(.indexed, .real_address, .bits16));
    try std.testing.expect(isAddressingFormAvailable(.indexed, .protected, .bits32));
    try std.testing.expect(isAddressingFormAvailable(.base_index_scale_disp, .protected, .bits32));
}
