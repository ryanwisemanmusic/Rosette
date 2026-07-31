//! Family: prefix — legacy / VEX / EVEX prefix decoding.
//! Extracted from the universal x86-64 decoder (formerly src/x64-ASM/decoder.zig).

const std = @import("std");
const types = @import("types.zig");
const highway = types.highway;
const isa_decode = types.isa_decode;
const capabilities = types.capabilities;
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

pub const LegacyPrefixes = struct {
    len: usize = 0,
    rex: u8 = 0,
    has_rex: bool = false,
    operand_size_override: bool = false,
    address_size_override: bool = false,
    lock: bool = false,
    repeat: enum { none, repne, rep } = .none,
    segment_override: ?Segment = null,

    pub fn rexW(self: LegacyPrefixes) bool {
        return self.rex & 0x08 != 0;
    }

    pub fn rexR(self: LegacyPrefixes) bool {
        return self.rex & 0x04 != 0;
    }

    pub fn rexX(self: LegacyPrefixes) bool {
        return self.rex & 0x02 != 0;
    }

    pub fn rexB(self: LegacyPrefixes) bool {
        return self.rex & 0x01 != 0;
    }
};

pub const VexPrefix = struct {
    len: usize = 0,
    is_2byte: bool = false,
    has_66_prefix: bool = false,
    has_f2_prefix: bool = false,
    has_f3_prefix: bool = false,
    w: bool = false,
    r: bool = false,
    // Two-byte VEX has no X/B fields, so both implicit extension bits are
    // clear. Three-byte VEX decoding overwrites them from the inverted prefix
    // fields below.
    x: bool = false,
    b: bool = false,
    l: bool = false,
    vvvv: u4 = 0,
    m: u5 = 1,
};

/// EVEX prefix state (4-byte 62 [P0] [P1] [P2]) for AVX-512 instructions.
/// The EVEX prefix extends VEX with opmask registers (k0-k7), zero/merge
/// masking, broadcast/embedded rounding, and 5-bit register addressing.
pub const EvexPrefix = struct {
    len: usize = 4,
    has_66_prefix: bool = false,
    has_f2_prefix: bool = false,
    has_f3_prefix: bool = false,
    w: bool = false,
    r: bool = true,
    x: bool = true,
    b: bool = true,
    r_prime: bool = true, // R' from P0 bit 4 (high bit of ModRM.reg)
    v_prime: bool = true, // V' from P2 bit 3 (high bit of vvvv)
    vvvv: u4 = 0,
    z: bool = false, // zero-masking (P2 bit 7)
    vector_length: u2 = 0, // L'L: 0=128, 1=256, 2=512, 3=reserved
    broadcast: bool = false, // b flag (P2 bit 4)
    opmask: u3 = 0, // aaa field (P2 bits 2-0)
    m: u2 = 0, // opcode map (P0 bits 1-0): 0=0F, 1=0F38, 2=0F3A
};

pub fn decodeLegacyPrefixes(bytes: []const u8) LegacyPrefixes {
    var result = LegacyPrefixes{};
    while (result.len < bytes.len and result.len < 15) {
        const byte = bytes[result.len];
        switch (byte) {
            0x66 => result.operand_size_override = true,
            0x67 => result.address_size_override = true,
            0xF0 => result.lock = true,
            0xF2 => result.repeat = .repne,
            0xF3 => result.repeat = .rep,
            0x26 => result.segment_override = .es,
            0x2E => result.segment_override = .cs,
            0x36 => result.segment_override = .ss,
            0x3E => result.segment_override = .ds,
            0x64 => result.segment_override = .fs,
            0x65 => result.segment_override = .gs,
            0x40...0x4F => {
                result.rex = byte;
                result.has_rex = true;
            },
            else => break,
        }
        result.len += 1;
    }
    return result;
}

pub fn decodeVexPrefix(bytes: []const u8) ?VexPrefix {
    if (bytes.len == 0) return null;
    var result = VexPrefix{};
    var pos: usize = 0;

    // Check for 2-byte VEX (C5)
    if (bytes[pos] == 0xC5) {
        result.is_2byte = true;
        pos += 1;
        if (pos >= bytes.len) return null;
        const byte = bytes[pos];
        result.r = (byte & 0x80) == 0;
        result.l = (byte & 0x04) != 0;
        result.vvvv = ~@as(u4, @truncate((byte >> 3) & 0xF));
        result.m = 1; // 2-byte VEX implies m-mmmm = 1
        result.has_66_prefix = (byte & 0x03) == 1;
        result.has_f3_prefix = (byte & 0x03) == 2;
        result.has_f2_prefix = (byte & 0x03) == 3;
        result.len = 2;
        return result;
    }

    // Check for 3-byte VEX (C4)
    if (bytes[pos] == 0xC4) {
        pos += 1;
        if (pos + 1 >= bytes.len) return null;
        const byte1 = bytes[pos];
        const byte2 = bytes[pos + 1];
        result.r = (byte1 & 0x80) == 0;
        result.x = (byte1 & 0x40) == 0;
        result.b = (byte1 & 0x20) == 0;
        result.m = @as(u5, @truncate(byte1 & 0x1F));
        result.w = (byte2 & 0x80) != 0;
        result.vvvv = ~@as(u4, @truncate((byte2 >> 3) & 0xF));
        result.l = (byte2 & 0x04) != 0;
        result.has_66_prefix = (byte2 & 0x03) == 1;
        result.has_f3_prefix = (byte2 & 0x03) == 2;
        result.has_f2_prefix = (byte2 & 0x03) == 3;
        result.len = 3;
        return result;
    }

    return null;
}

/// Decode the 4-byte EVEX prefix (starting with 0x62). Returns null if the
/// bytes do not begin with a valid EVEX prefix. The returned EvexPrefix
/// carries mask/rounding/broadcast state for AVX-512 execution.
pub fn decodeEvexPrefix(bytes: []const u8) ?EvexPrefix {
    if (bytes.len < 4) return null;
    if (bytes[0] != 0x62) return null;

    var result = EvexPrefix{};

    // P0 (byte 1): R, X, B, R', 0, 0, m, m
    const p0 = bytes[1];
    result.r = (p0 & 0x80) == 0;
    result.x = (p0 & 0x40) == 0;
    result.b = (p0 & 0x20) == 0;
    result.r_prime = (p0 & 0x10) != 0;
    // bits 3-2 are reserved (must be 0)
    result.m = @truncate(p0 & 0x03);

    // P1 (byte 2): W, v, v, v, v, 1, pp, pp
    const p1 = bytes[2];
    result.w = (p1 & 0x80) != 0;
    result.vvvv = ~@as(u4, @truncate((p1 >> 3) & 0x0F));
    // bit 2 is always 1 in valid EVEX
    const pp = p1 & 0x03;
    result.has_66_prefix = pp == 1;
    result.has_f3_prefix = pp == 2;
    result.has_f2_prefix = pp == 3;

    // P2 (byte 3): z, L', L, b, V', a, a, a
    const p2 = bytes[3];
    result.z = (p2 & 0x80) != 0;
    result.vector_length = @truncate((p2 >> 5) & 0x03);
    result.broadcast = (p2 & 0x10) != 0;
    result.v_prime = (p2 & 0x08) != 0;
    result.opmask = @truncate(p2 & 0x07);

    result.len = 4;
    return result;
}
