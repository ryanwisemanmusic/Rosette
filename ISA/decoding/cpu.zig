//! Family: cpu — bit scan, popcount, byte swap, CRC32C, emulated CPUID/XCR0.
//! Extracted from the universal x86-64 decoder (formerly src/x64-ASM/decoder.zig).

const std = @import("std");
const types = @import("types.zig");
const flags = @import("flags");
const capabilities = @import("capabilities");
const highway = types.highway;
const isa_decode = types.isa_decode;
const OperandSize = types.OperandSize;
const Condition = types.Condition;
const Size = types.Size;
const Cond = types.Cond;
const RegId = types.RegId;
const Regs = types.Regs;
const Segment = types.Segment;
const SegmentState = types.SegmentState;
const ExecutionMode = types.ExecutionMode;
const MemoryReferenceKind = types.MemoryReferenceKind;
const RFL_CF = types.RFL_CF;
const RFL_PF = types.RFL_PF;
const RFL_AF = types.RFL_AF;
const RFL_ZF = types.RFL_ZF;
const RFL_SF = types.RFL_SF;
const RFL_OF = types.RFL_OF;
const statusByteForLahf = types.statusByteForLahf;
const applySahf = types.applySahf;
const BitTestOperation = types.BitTestOperation;
const bitTestRegister = types.bitTestRegister;
const bitTestAndResetRegister = types.bitTestAndResetRegister;
const bitTestMemoryOperand = types.bitTestMemoryOperand;
const bitTestMemoryOperandImmediate = types.bitTestMemoryOperandImmediate;
const RegisterOperand = types.RegisterOperand;
const MemoryOperand = types.MemoryOperand;
const RmOperand = types.RmOperand;
const DecodedModRm = types.DecodedModRm;
const applySub = types.applySub;
const applySbb = types.applySbb;
const applyAdd = types.applyAdd;
const applyIncDec = types.applyIncDec;
const applyLogic = types.applyLogic;
const evalCond = types.evalCond;
const regVal = types.regVal;
const setReg = types.setReg;
const BitScanKind = types.BitScanKind;
const BitScanResult = types.BitScanResult;
const PopulationCountResult = types.PopulationCountResult;
const Op = types.Op;
const DecodedInsn = types.DecodedInsn;

pub fn populationCount(size: OperandSize, raw_source: u64, initial_rflags: u32) PopulationCountResult {
    const mask: u64 = switch (size) {
        .bits8 => 0xFF,
        .bits16 => 0xFFFF,
        .bits32 => 0xFFFF_FFFF,
        .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
    };
    const source = raw_source & mask;
    const status_mask = flags.RFL_CF | flags.RFL_PF | flags.RFL_AF | flags.RFL_ZF | flags.RFL_SF | flags.RFL_OF;
    var rflags = initial_rflags & ~status_mask;
    if (source == 0) rflags |= flags.RFL_ZF;
    return .{ .value = @popCount(source), .rflags = rflags };
}

pub fn bitScan(size: OperandSize, kind: BitScanKind, raw_source: u64) BitScanResult {
    const width: u7 = switch (size) {
        .bits8 => 8,
        .bits16 => 16,
        .bits32 => 32,
        .bits64 => 64,
    };
    const mask: u64 = switch (size) {
        .bits8 => 0xFF,
        .bits16 => 0xFFFF,
        .bits32 => 0xFFFF_FFFF,
        .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
    };
    const source = raw_source & mask;

    return switch (kind) {
        .bsf => if (source == 0)
            .{ .value = 0, .write_destination = false, .zero_flag = true, .carry_flag = null }
        else
            .{ .value = @ctz(source), .write_destination = true, .zero_flag = false, .carry_flag = null },
        .bsr => if (source == 0)
            .{ .value = 0, .write_destination = false, .zero_flag = true, .carry_flag = null }
        else
            .{ .value = 63 - @clz(source), .write_destination = true, .zero_flag = false, .carry_flag = null },
        .tzcnt => blk: {
            const value: u64 = if (source == 0) width else @ctz(source);
            break :blk .{
                .value = value,
                .write_destination = true,
                .zero_flag = value == 0,
                .carry_flag = source == 0,
            };
        },
        .lzcnt => blk: {
            const value: u64 = if (source == 0) width else width - 1 - (63 - @clz(source));
            break :blk .{
                .value = value,
                .write_destination = true,
                .zero_flag = value == 0,
                .carry_flag = source == 0,
            };
        },
    };
}

pub fn byteSwap(size: OperandSize, value: u64) u64 {
    return switch (size) {
        .bits8 => @as(u8, @truncate(value)),
        .bits16 => @byteSwap(@as(u16, @truncate(value))),
        .bits32 => @byteSwap(@as(u32, @truncate(value))),
        .bits64 => @byteSwap(value),
    };
}

pub fn crc32cAccumulator(initial: u32, source: u64, size: OperandSize) u32 {
    var crc = initial;
    var value = source;
    const byte_count: u8 = switch (size) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32 => 4,
        .bits64 => 8,
    };
    var byte_index: u8 = 0;
    while (byte_index < byte_count) : (byte_index += 1) {
        crc ^= @as(u8, @truncate(value));
        value >>= 8;
        var bit_index: u4 = 0;
        while (bit_index < 8) : (bit_index += 1) {
            crc = (crc >> 1) ^ (0x82F6_3B78 & (0 -% (crc & 1)));
        }
    }
    return crc;
}

pub const CpuidResult = capabilities.CpuidResult;

pub fn emulatedCpuid(leaf: u32, subleaf: u32) CpuidResult {
    return capabilities.cpuid(.xenia, leaf, subleaf);
}

pub fn emulatedXcr0() u64 {
    return capabilities.xcr0(.xenia);
}

test "emulated CPUID exposes a coherent AVX baseline" {
    const leaf0 = emulatedCpuid(0, 0);
    // The capabilities model advertises every modeled basic leaf; AVX profiles
    // expose XSAVE, so leaf 0xD must be available (see capabilities.cpuid).
    try std.testing.expectEqual(@as(u32, 0xD), leaf0.eax);
    try std.testing.expectEqual(@as(u32, 0x756E_6547), leaf0.ebx);

    const leaf1 = emulatedCpuid(1, 0);
    try std.testing.expect(leaf1.ecx & (@as(u32, 1) << 27) != 0);
    try std.testing.expect(leaf1.ecx & (@as(u32, 1) << 28) != 0);
    try std.testing.expectEqual(@as(u64, 0x7), emulatedXcr0());
}

test "shared byte swap preserves operand width" {
    try std.testing.expectEqual(@as(u64, 0x12), byteSwap(.bits8, 0x12));
    try std.testing.expectEqual(@as(u64, 0x3412), byteSwap(.bits16, 0x1234));
    try std.testing.expectEqual(@as(u64, 0x7856_3412), byteSwap(.bits32, 0x1234_5678));
    try std.testing.expectEqual(@as(u64, 0xEFCD_AB89_6745_2301), byteSwap(.bits64, 0x0123_4567_89AB_CDEF));
}

test "shared CRC32C accumulator follows x86 byte order" {
    try std.testing.expectEqual(@as(u32, 0x93AD_1061), crc32cAccumulator(0, 'a', .bits8));
}
