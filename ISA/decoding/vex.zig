//! Family: vex — VEX / EVEX encoded families (VEX2/VEX3, half/duplicate moves).
//! Extracted from the universal x86-64 decoder (formerly src/x64-ASM/decoder.zig).

const std = @import("std");
const types = @import("types.zig");
const pref = @import("prefix.zig");
const addressing = @import("addressing.zig");
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
const LegacyPrefixes = pref.LegacyPrefixes;
const VexPrefix = pref.VexPrefix;
const EvexPrefix = pref.EvexPrefix;
const decodeLegacyPrefixes = pref.decodeLegacyPrefixes;
const decodeVexPrefix = pref.decodeVexPrefix;
const decodeEvexPrefix = pref.decodeEvexPrefix;
const decodeRegister = addressing.decodeRegister;
const defaultSegment = addressing.defaultSegment;
const selectSegment = addressing.selectSegment;
const segmentBase = addressing.segmentBase;
const resolveMemoryAddress = addressing.resolveMemoryAddress;
const decodeMemoryOperand = addressing.decodeMemoryOperand;
const decodeModRm = addressing.decodeModRm;
const hasModRM = addressing.hasModRM;
const mapReg = addressing.mapReg;
const mapJccCond8 = addressing.mapJccCond8;
const mapJccCond32 = addressing.mapJccCond32;
const readModRM = addressing.readModRM;

fn decodeVexModRm(
    bytes: []const u8,
    pos: *usize,
    vex: VexPrefix,
) ?struct {
    dst_xmm: u8,
    src_xmm: u8,
    mod: u2,
    rm_code: u3,
    addr: u64,
    is_reg_form: bool,
} {
    if (pos.* >= bytes.len) return null;
    const modrm = bytes[pos.*];
    pos.* += 1;

    const mod: u2 = @truncate(modrm >> 6);
    const reg_code: u3 = @truncate(modrm >> 3);
    const rm_code: u3 = @truncate(modrm);

    const dst_xmm: u8 = (if (vex.r) @as(u8, 8) else @as(u8, 0)) | reg_code;
    const src_xmm: u8 = (if (vex.b) @as(u8, 8) else @as(u8, 0)) | rm_code;

    var addr: u64 = undefined;
    const is_reg_form = (mod == 3);

    if (!is_reg_form) {
        const has_sib = (rm_code == 4) or (mod == 0 and rm_code == 5);
        if (has_sib) {
            if (pos.* >= bytes.len) return null;
            _ = bytes[pos.*];
            pos.* += 1;
        }

        const disp_size: u4 = switch (mod) {
            0 => if (rm_code == 5 or has_sib) @as(u4, 4) else 0,
            1 => 1,
            2 => 4,
            else => unreachable,
        };
        if (pos.* + disp_size > bytes.len) return null;
        if (disp_size == 1) {
            const disp: i8 = @bitCast(bytes[pos.*]);
            addr = @as(u64, @bitCast(@as(i64, disp)));
            pos.* += 1;
        } else if (disp_size == 4) {
            const disp: i32 = std.mem.readInt(i32, bytes[pos.*..][0..4], .little);
            addr = @as(u64, @bitCast(@as(i64, disp)));
            pos.* += 4;
        } else {
            addr = 0;
        }
    }

    return .{
        .dst_xmm = dst_xmm,
        .src_xmm = src_xmm,
        .mod = mod,
        .rm_code = rm_code,
        .addr = addr,
        .is_reg_form = is_reg_form,
    };
}

/// Decode the ModR/M byte following an EVEX prefix with 5-bit register
/// addressing (R' extends dst to xmm0-xmm31, V' extends vvvv). Also handles
/// compressed 8-bit displacement scaling for EVEX instructions.
fn decodeEvexModRm(
    bytes: []const u8,
    pos: *usize,
    evex: EvexPrefix,
    element_width: u6,
) ?struct {
    dst_xmm: u8,
    src_xmm: u8,
    mod: u2,
    rm_code: u3,
    addr: u64,
    is_reg_form: bool,
} {
    if (pos.* >= bytes.len) return null;
    const modrm = bytes[pos.*];
    pos.* += 1;

    const mod: u2 = @truncate(modrm >> 6);
    const reg_code: u3 = @truncate(modrm >> 3);
    const rm_code: u3 = @truncate(modrm);

    // 5-bit destination register: {R', !R, reg_code}
    const dst_xmm: u8 = ((if (evex.r_prime) @as(u8, 16) else 0) | (if (evex.r) @as(u8, 8) else 0)) | reg_code;
    const src_xmm: u8 = (if (evex.b) @as(u8, 8) else @as(u8, 0)) | rm_code;

    var addr: u64 = undefined;
    const is_reg_form = (mod == 3);

    if (!is_reg_form) {
        // Compressed displacement (DISP8) scaling for EVEX:
        // N = element_width * vector_lanes (128-bit=16, 256-bit=32, 512-bit=64)
        // Broadcast: N = element_width
        // The Intel SDM defines the EVEX DISP8 scaling factor N as:
        // - For regular memory ops: N = total vector bytes (16/32/64)
        // - For broadcast: N = element size in bytes (2/4/8)        // N values: 16 (128-bit), 32 (256-bit), 64 (512-bit) — fits in u7
        const evex_scale: u7 = if (evex.broadcast)
            @as(u7, element_width / 8)
        else switch (evex.vector_length) {
            0 => 16,
            1 => 32,
            2 => 64,
            3 => 64, // reserved, treat as 512-bit
        };

        const has_sib = (rm_code == 4) or (mod == 0 and rm_code == 5);
        if (has_sib) {
            if (pos.* >= bytes.len) return null;
            _ = bytes[pos.*];
            pos.* += 1;
        }

        const disp_size: u4 = switch (mod) {
            0 => if (rm_code == 5 or has_sib) @as(u4, 4) else 0,
            1 => 1,
            2 => 4,
            else => unreachable,
        };
        if (pos.* + disp_size > bytes.len) return null;
        if (disp_size == 1) {
            // Compressed 8-bit displacement scaled by N
            const disp: u8 = bytes[pos.*];
            addr = @as(u64, disp) * evex_scale;
            pos.* += 1;
        } else if (disp_size == 4) {
            const disp: i32 = std.mem.readInt(i32, bytes[pos.*..][0..4], .little);
            addr = @as(u64, @bitCast(@as(i64, disp)));
            pos.* += 4;
        } else {
            addr = 0;
        }
    }

    return .{
        .dst_xmm = dst_xmm,
        .src_xmm = src_xmm,
        .mod = mod,
        .rm_code = rm_code,
        .addr = addr,
        .is_reg_form = is_reg_form,
    };
}

pub fn decodeVexInstruction(bytes: []const u8) ?DecodedInsn {
    // Check for EVEX prefix (0x62) before VEX (0xC5/0xC4)
    if (bytes.len > 0 and bytes[0] == 0x62) {
        const evex = decodeEvexPrefix(bytes) orelse return null;
        var pos = evex.len;
        if (pos >= bytes.len) return null;
        const opcode = bytes[pos];
        pos += 1;
        _ = opcode; // Reserved for EVEX Phase 2 opcode dispatch
        // Use 5-bit register decode for EVEX (r_prime + v_prime extensions)
        // with compressed displacement scaling. Default element_width=32;
        // opcode-specific handlers will override with correct element size.
        const evex_modrm = decodeEvexModRm(bytes, &pos, evex, 32) orelse return null;
        // Build a DecodedInsn with EVEX metadata; actual opcode dispatch
        // will be added in EVEX Phase 2
        return .{
            .op = .invalid,
            .size = .bits64,
            .len = @intCast(pos),
            .xmm_dst = evex_modrm.dst_xmm,
            .xmm_src = evex_modrm.src_xmm,
            .xmm_src2 = (if (evex.v_prime) @as(u8, 16) else 0) | evex.vvvv,
            .is_reg_form = evex_modrm.is_reg_form,
            .addr = evex_modrm.addr,
            .vector_256 = (evex.vector_length == 1),
            .vector_512 = (evex.vector_length == 2),
            .opmask = evex.opmask,
            .zero_mask = evex.z,
            .evex_broadcast = evex.broadcast,
        };
    }

    const vex = decodeVexPrefix(bytes) orelse return null;
    var pos = vex.len;
    if (pos >= bytes.len) return null;

    const opcode = bytes[pos];
    pos += 1;

    // Parse ModR/M (all VEX instructions have ModR/M)
    const modrm_decoded = decodeVexModRm(bytes, &pos, vex) orelse return null;

    // Determine opcode variant based on VEX prefix type (PS/PD/SS/SD)
    // The pattern: vex.has_66_prefix → PD, vex.has_f2_prefix → SD,
    // vex.has_f3_prefix → SS, none → PS
    const arith = struct {
        fn pick(v: VexPrefix, comptime ops: [4]Op) Op {
            if (v.has_f3_prefix) return ops[0];
            if (v.has_f2_prefix) return ops[1];
            if (v.has_66_prefix) return ops[2];
            return ops[3];
        }
    }.pick;

    // Dispatch by opcode, using VEX map field to select the correct
    // opcode map (1=0x0F, 2=0x0F38, 3=0x0F3A)
    switch (vex.m) {
        2 => return decodeVexMap38(vex, pos, opcode, modrm_decoded),
        3 => {
            // All VEX.0x0F3A instructions have a mandatory 8-bit immediate
            if (pos >= bytes.len) return null;
            const imm = bytes[pos];
            pos += 1;
            return decodeVexMap3A(vex, pos, opcode, modrm_decoded, imm);
        },
        1 => {}, // 0x0F map — handled below
        else => return null,
    }

    // Original 0x0F map (vex.m == 1)
    switch (opcode) {
        0x10 => {
            // VMOVUPS (VEX.0F 10), VMOVUPD (VEX.66.0F 10)
            // VMOVSS (VEX.F3.0F 10), VMOVSD (VEX.F2.0F 10) — load forms
            const op = arith(vex, .{ .vmovss_xmm_mem, .vmovsd_xmm_mem, .vmovupd_xmm_mem, .vmovups_xmm_mem });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x11 => {
            // VMOVUPS (VEX.0F 11), VMOVUPD (VEX.66.0F 11)
            // VMOVSS (VEX.F3.0F 11), VMOVSD (VEX.F2.0F 11) — store forms
            const op = arith(vex, .{ .vmovss_mem_xmm, .vmovsd_mem_xmm, .vmovupd_mem_xmm, .vmovups_mem_xmm });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x12 => {
            // VMOVHLPS (VEX.0F 12, reg) / VMOVLPS (VEX.0F 12 /r) — load low
            // VMOVLPD (VEX.66.0F 12 /r) — load low double
            const op: Op = if (vex.has_66_prefix)
                (if (modrm_decoded.is_reg_form) .vmovlhps else .vmovlpd_xmm_xmm_mem64)
            else
                (if (modrm_decoded.is_reg_form) .vmovhlps else .vmovlps_xmm_xmm_mem64);
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x13 => {
            // VMOVLPS (VEX.0F 13 /r) — store low packed single
            // With 0x66 prefix: VMOVLPD (VEX.66.0F 13 /r)
            const op = arith(vex, .{ .vmovlps_mem64_xmm, .vmovlps_mem64_xmm, .vmovlpd_mem64_xmm, .vmovlps_mem64_xmm });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x14 => {
            // VUNPCKLPS (VEX.0F 14) / VUNPCKLPD (VEX.66.0F 14)
            const op: Op = if (vex.has_66_prefix) .vunpcklpd else .vunpcklps;
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x15 => {
            // VUNPCKHPS (VEX.0F 15) / VUNPCKHPD (VEX.66.0F 15)
            const op: Op = if (vex.has_66_prefix) .vunpckhpd else .vunpckhps;
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x16 => {
            // VMOVLHPS (VEX.0F 16, reg) / VMOVHPS (VEX.0F 16 /r) — load high
            // VMOVHPD (VEX.66.0F 16 /r) — load high double
            const op: Op = if (vex.has_66_prefix)
                (if (modrm_decoded.is_reg_form) .vmovlhps else .vmovhpd_xmm_xmm_mem64)
            else
                (if (modrm_decoded.is_reg_form) .vmovlhps else .vmovhps_xmm_xmm_mem64);
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x17 => {
            // VMOVHPS (VEX.0F 17 /r) — store high packed single
            // With 0x66 prefix: VMOVHPD (VEX.66.0F 17 /r)
            const op = arith(vex, .{ .vmovhps_mem64_xmm, .vmovhps_mem64_xmm, .vmovhpd_mem64_xmm, .vmovhps_mem64_xmm });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x28 => {
            // VMOVAPS (VEX.0F 28), VMOVAPD (VEX.66.0F 28) — load forms
            const op = arith(vex, .{ .vmovaps_xmm_mem, .vmovaps_xmm_mem, .vmovapd_xmm_mem, .vmovaps_xmm_mem });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x29 => {
            // VMOVAPS (VEX.0F 29), VMOVAPD (VEX.66.0F 29) — store forms
            const op = arith(vex, .{ .vmovaps_mem_xmm, .vmovaps_mem_xmm, .vmovapd_mem_xmm, .vmovaps_mem_xmm });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x2A => {
            // VCVTSI2SS (VEX.0F 2A), VCVTSI2SD (VEX.66.0F 2A)
            // VEX.F3.0F 2A and VEX.F2.0F 2A are also CVTSI2SS/SD
            const op = arith(vex, .{ .vcvtsi2ss_xmm_reg, .vcvtsi2sd_xmm_reg, .vcvtsi2sd_xmm_reg, .vcvtsi2ss_xmm_reg });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x2E => {
            // VUCOMISS (VEX.66.0F 2E) — unordered compare scalar single
            if (vex.has_66_prefix or !vex.has_f3_prefix) return decodeVexReturn(vex, pos, .vucomiss, modrm_decoded);
            return null;
        },
        0x2F => {
            // VUCOMISD (VEX.66.0F 2F) — unordered compare scalar double
            if (vex.has_66_prefix or !vex.has_f3_prefix) return decodeVexReturn(vex, pos, .vucomisd, modrm_decoded);
            return null;
        },
        0x50 => {
            // VMOVMSKPS (VEX.0F 50) / VMOVMSKPD (VEX.66.0F 50)
            const op: Op = if (vex.has_66_prefix) .vmovmskpd else .vmovmskps;
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x51 => {
            // VSQRTPS (VEX.0F 51) / VSQRTPD (VEX.66.0F 51)
            // VSQRTSS (VEX.F3.0F 51) / VSQRTSD (VEX.F2.0F 51)
            const op = arith(vex, .{ .vsqrtss, .vsqrtsd, .vsqrtpd, .vsqrtps });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x52 => {
            // VRSQRTPS (VEX.0F 52 /r) — no 0x66/PD form
            return .{
                .op = .vrsqrtps,
                .size = .bits64,
                .len = @intCast(pos),
                .xmm_dst = modrm_decoded.dst_xmm,
                .xmm_src = modrm_decoded.src_xmm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
                .vector_256 = vex.l,
            };
        },
        0x53 => {
            // VRCPPS (VEX.0F 53 /r) — no 0x66/PD form
            return .{
                .op = .vrcpps,
                .size = .bits64,
                .len = @intCast(pos),
                .xmm_dst = modrm_decoded.dst_xmm,
                .xmm_src = modrm_decoded.src_xmm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
                .vector_256 = vex.l,
            };
        },
        0x54 => {
            // VANDPS (VEX.0F 54) / VANDPD (VEX.66.0F 54)
            const op_sel = arith(vex, .{ .vandps, .vandps, .vandpd, .vandps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x55 => {
            // VANDNPS (VEX.0F 55) / VANDNPD (VEX.66.0F 55)
            const op_sel = arith(vex, .{ .vandnps, .vandnps, .vandnpd, .vandnps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x56 => {
            // VORPS (VEX.0F 56) / VORPD (VEX.66.0F 56)
            const op_sel = arith(vex, .{ .vorps, .vorps, .vorpd, .vorps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x57 => {
            // VXORPS (VEX.0F 57) / VXORPD (VEX.66.0F 57)
            const op_sel = arith(vex, .{ .vxorps, .vxorps, .vxorpd, .vxorps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x58 => {
            // VADDPS (VEX.0F 58) / VADDPD (VEX.66.0F 58)
            // VADDSS (VEX.F3.0F 58) / VADDSD (VEX.F2.0F 58)
            const op_sel = arith(vex, .{ .vaddss, .vaddsd, .vaddpd, .vaddps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x59 => {
            // VMULPS (VEX.0F 59) / VMULPD (VEX.66.0F 59)
            // VMULSS (VEX.F3.0F 59) / VMULSD (VEX.F2.0F 59)
            const op_sel = arith(vex, .{ .vmulss, .vmulsd, .vmulpd, .vmulps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5A => {
            // VCVTPS2PD (VEX.0F 5A) / VCVTPD2PS (VEX.66.0F 5A)
            // VCVTSS2SD (VEX.F3.0F 5A) / VCVTSD2SS (VEX.F2.0F 5A)
            const op = arith(vex, .{ .vcvtss2sd, .vcvtsd2ss, .vcvtpd2ps, .vcvtps2pd });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x5B => {
            // VCVTDQ2PS (VEX.0F 5B) / VCVTPS2DQ (VEX.66.0F 5B)
            // VCVTQQ2PS (VEX.F3.0F 5B)
            const op_sel = arith(vex, .{ .vcvtdq2ps, .vcvtdq2ps, .vcvtps2dq, .vcvtdq2ps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5C => {
            // VSUBPS (VEX.0F 5C) / VSUBPD (VEX.66.0F 5C)
            // VSUBSS (VEX.F3.0F 5C) / VSUBSD (VEX.F2.0F 5C)
            const op_sel = arith(vex, .{ .vsubss, .vsubsd, .vsubpd, .vsubps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5D => {
            // VMINPS (VEX.0F 5D) / VMINPD (VEX.66.0F 5D)
            // VMINSS (VEX.F3.0F 5D) / VMINSD (VEX.F2.0F 5D)
            const op_sel = arith(vex, .{ .vminss, .vminsd, .vminpd, .vminps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5E => {
            // VDIVPS (VEX.0F 5E) / VDIVPD (VEX.66.0F 5E)
            // VDIVSS (VEX.F3.0F 5E) / VDIVSD (VEX.F2.0F 5E)
            const op_sel = arith(vex, .{ .vdivss, .vdivsd, .vdivpd, .vdivps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5F => {
            // VMAXPS (VEX.0F 5F) / VMAXPD (VEX.66.0F 5F)
            // VMAXSS (VEX.F3.0F 5F) / VMAXSD (VEX.F2.0F 5F)
            const op_sel = arith(vex, .{ .vmaxss, .vmaxsd, .vmaxpd, .vmaxps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x60 => {
            // VPUNPCKLBW (VEX.66.0F 60 /r) — unpack low bytes
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpcklbw else return null, modrm_decoded);
        },
        0x61 => {
            // VPUNPCKLWD (VEX.66.0F 61 /r) — unpack low words
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpcklwd else return null, modrm_decoded);
        },
        0x62 => {
            // VPUNPCKLDQ (VEX.66.0F 62 /r) — unpack low dwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckldq else return null, modrm_decoded);
        },
        0x63 => {
            // VPACKSSWB (VEX.66.0F 63 /r) — pack with signed saturation
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpacksswb else return null, modrm_decoded);
        },
        0x64 => {
            // VPUNPCKHBW (VEX.66.0F 64 /r) — unpack high bytes
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhbw else return null, modrm_decoded);
        },
        0x65 => {
            // VPUNPCKHWD (VEX.66.0F 65 /r) — unpack high words
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhwd else return null, modrm_decoded);
        },
        0x66 => {
            // VPUNPCKHDQ (VEX.66.0F 66 /r) — unpack high dwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhdq else return null, modrm_decoded);
        },
        0x67 => {
            // VPACKUSWB (VEX.66.0F 67 /r) — pack with unsigned saturation
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpackuswb else return null, modrm_decoded);
        },
        0x68 => {
            // VPUNPCKLQDQ (VEX.66.0F 68 /r) — unpack low qwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpcklqdq else return null, modrm_decoded);
        },
        0x69 => {
            // VPUNPCKHQDQ (VEX.66.0F 69 /r) — unpack high qwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhqdq else return null, modrm_decoded);
        },
        0x6E => {
            // VMOVD (VEX.66.0F 6E) / VMOVQ (VEX.66.REX.W 0F 6E)
            if (!vex.has_66_prefix or vex.l or vex.vvvv != 0) return null;
            return .{
                .op = if (vex.w)
                    (if (modrm_decoded.is_reg_form) .vmovq_xmm_reg64 else .vmovq_xmm_mem64)
                else
                    (if (modrm_decoded.is_reg_form) .vmovd_xmm_reg32 else .vmovd_xmm_mem32),
                .size = if (vex.w) .bits64 else .bits32,
                .len = @intCast(pos),
                .src_reg = @enumFromInt(modrm_decoded.src_xmm),
                .xmm_dst = modrm_decoded.dst_xmm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
            };
        },
        0x6F => {
            // VMOVDQA (VEX.66.0F 6F) / VMOVDQU (VEX.F3.0F 6F)
            // With F2 prefix: VMOVDQU (VEX.F2.0F 6F is also VMOVDQU)
            if (vex.has_66_prefix) {
                return .{
                    .op = if (modrm_decoded.is_reg_form) .vmovdqa_xmm_xmm else .vmovdqa_xmm_mem,
                    .size = .bits64,
                    .len = @intCast(pos),
                    .xmm_dst = modrm_decoded.dst_xmm,
                    .xmm_src = modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else if (vex.has_f3_prefix or vex.has_f2_prefix) {
                return .{
                    .op = if (modrm_decoded.is_reg_form) .vmovdqu_xmm_xmm else .vmovdqu_xmm_mem,
                    .size = .bits64,
                    .len = @intCast(pos),
                    .xmm_dst = modrm_decoded.dst_xmm,
                    .xmm_src = modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else {
                // VMOVAPS/VMOVAPD with no prefix: F30F6F = MOVDQU
                // VEX.0F 6F is undefined — fall through
                return null;
            }
        },
        0x70 => {
            // VPSHUFD (VEX.66.0F 70 /r ib)
            if (pos >= bytes.len) return null;
            const imm = bytes[pos];
            pos += 1;
            return .{
                .op = .vpshufd,
                .size = .bits64,
                .len = @intCast(pos),
                .xmm_dst = modrm_decoded.dst_xmm,
                .xmm_src = modrm_decoded.src_xmm,
                .imm = imm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
                .vector_256 = vex.l,
            };
        },
        0x7C => {
            // VHADDPS (VEX.0F 7C) / VHADDPD (VEX.66.0F 7C)
            const op_sel = arith(vex, .{ .vhaddps, .vhaddps, .vhaddpd, .vhaddps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x7D => {
            // VHSUBPS (VEX.0F 7D) / VHSUBPD (VEX.66.0F 7D)
            const op_sel = arith(vex, .{ .vhsubps, .vhsubps, .vhsubpd, .vhsubps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x7E => {
            // VMOVD (VEX.128.66.0F 7E) / VMOVQ (VEX.128.66.W1.0F 7E).
            // ModRM.reg is the XMM source; ModRM.r/m is the GPR or memory
            // destination, the reverse operand direction from opcode 6E.
            if (!vex.has_66_prefix or vex.l or vex.vvvv != 0) return null;
            return .{
                .op = if (vex.w)
                    (if (modrm_decoded.is_reg_form) .vmovq_reg64_xmm else .vmovq_mem64_xmm)
                else
                    (if (modrm_decoded.is_reg_form) .vmovd_reg32_xmm else .vmovd_mem32_xmm),
                .size = if (vex.w) .bits64 else .bits32,
                .len = @intCast(pos),
                .dst_reg = @enumFromInt(modrm_decoded.src_xmm),
                .xmm_src = modrm_decoded.dst_xmm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
            };
        },
        0x7F => {
            // VMOVDQA (VEX.66.0F 7F) / VMOVDQU (VEX.F3.0F 7F) — store forms
            if (vex.has_66_prefix) {
                return .{
                    .op = if (modrm_decoded.is_reg_form) .vmovdqa_xmm_xmm else .vmovdqa_mem_xmm,
                    .size = .bits64,
                    .len = @intCast(pos),
                    .xmm_dst = modrm_decoded.dst_xmm,
                    .xmm_src = modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else if (vex.has_f3_prefix or vex.has_f2_prefix) {
                return .{
                    .op = if (modrm_decoded.is_reg_form) .vmovdqu_xmm_xmm else .vmovdqu_mem_xmm,
                    .size = .bits64,
                    .len = @intCast(pos),
                    .xmm_dst = modrm_decoded.dst_xmm,
                    .xmm_src = modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else {
                return null;
            }
        },
        0xC2 => {
            // VCMPPS (VEX.0F C2) / VCMPPD (VEX.66.0F C2)
            // VCMPSS (VEX.F3.0F C2) / VCMPSD (VEX.F2.0F C2)
            // Has an immediate comparison predicate byte
            if (pos >= bytes.len) return null;
            const imm = bytes[pos];
            pos += 1;
            const op_sel = arith(vex, .{ .vcmpss, .vcmpsd, .vcmppd, .vcmpps });
            return .{
                .op = op_sel,
                .size = .bits64,
                .len = @intCast(pos),
                .xmm_dst = modrm_decoded.dst_xmm,
                .xmm_src = modrm_decoded.src_xmm,
                .imm = imm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
                .vector_256 = vex.l,
            };
        },
        else => return null,
    }
}

/// Helper to construct a DecodedInsn from the decoded VEX operands.
fn decodeVexReturn(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype) ?DecodedInsn {
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = modrm.src_xmm,
        .xmm_src2 = vex.vvvv,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
    };
}

/// Helper to construct a DecodedInsn with an immediate byte.
/// Used by VEX.0F3A instructions that encode an immediate operand.
fn decodeVexReturnImm(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype, imm: u8) ?DecodedInsn {
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = modrm.src_xmm,
        .xmm_src2 = vex.vvvv,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
        .uses_imm = true,
        .imm = imm,
    };
}

/// Decode VEX opcode map 0x38 (VEX.0F38).
/// Handles SSSE3/AVX2 3-operand integer SIMD instructions.
fn decodeVexMap38(vex: VexPrefix, pos: usize, opcode: u8, modrm: anytype) ?DecodedInsn {
    // VEX opcode map 0x38 uses the 0F 38 two-byte opcode prefix.
    // Dispatch by the third opcode byte:
    return switch (opcode) {
        0x00...0x06 => {
            // VPSHUFB (0x00), VPHADDW/D/SW (0x01-0x03), VPHSUBW/D/SW (0x04-0x06)
            return switch (opcode) {
                0x00 => decodeVexReturn(vex, pos, .vpshufb, modrm),
                0x01 => decodeVexReturn(vex, pos, .vphaddw, modrm),
                0x02 => decodeVexReturn(vex, pos, .vphaddd, modrm),
                0x03 => decodeVexReturn(vex, pos, .vphaddsw, modrm),
                0x04 => decodeVexReturn(vex, pos, .vphsubw, modrm),
                0x05 => decodeVexReturn(vex, pos, .vphsubd, modrm),
                0x06 => decodeVexReturn(vex, pos, .vphsubsw, modrm),
                else => null,
            };
        },
        0x08...0x0A => {
            // VPSIGNB/W/D (VEX.0F38 08/09/0A)
            return switch (opcode) {
                0x08 => decodeVexReturn(vex, pos, .vpsignb, modrm),
                0x09 => decodeVexReturn(vex, pos, .vpsignw, modrm),
                0x0A => decodeVexReturn(vex, pos, .vpsignd, modrm),
                else => null,
            };
        },
        0x10...0x12 => {
            // VPSRLVW (0x10), VPSRAVW (0x11), VPSLLVW (0x12)
            return switch (opcode) {
                0x10 => decodeVexReturn(vex, pos, .vpsrlvw, modrm),
                0x11 => decodeVexReturn(vex, pos, .vpsravw, modrm),
                0x12 => decodeVexReturn(vex, pos, .vpsllvw, modrm),
                else => null,
            };
        },
        0x1C...0x1E => {
            // VPABSB/W/D (VEX.0F38 1C/1D/1E)
            return switch (opcode) {
                0x1C => decodeVexReturn(vex, pos, .vpabsb, modrm),
                0x1D => decodeVexReturn(vex, pos, .vpabsw, modrm),
                0x1E => decodeVexReturn(vex, pos, .vpabsd, modrm),
                else => null,
            };
        },
        0x20...0x25 => {
            // PMOVSX variants: VEX.0F38 20-25
            return switch (opcode) {
                0x20 => decodeVexReturn(vex, pos, .vpmovsxbw, modrm),
                0x21 => decodeVexReturn(vex, pos, .vpmovsxbd, modrm),
                0x22 => decodeVexReturn(vex, pos, .vpmovsxbq, modrm),
                0x23 => decodeVexReturn(vex, pos, .vpmovsxwd, modrm),
                0x24 => decodeVexReturn(vex, pos, .vpmovsxwq, modrm),
                0x25 => decodeVexReturn(vex, pos, .vpmovsxdq, modrm),
                else => null,
            };
        },
        0x28 => decodeVexReturn(vex, pos, .vpmuldq, modrm),
        0x29 => decodeVexReturn(vex, pos, .vpcmpeqq, modrm),
        0x2A => decodeVexReturn(vex, pos, .vpmovzxbd, modrm), // VMOVNTDQA with 66
        0x2B => decodeVexReturn(vex, pos, .vpackusdw, modrm),
        0x36 => decodeVexReturn(vex, pos, .vpermd, modrm),
        0x37 => decodeVexReturn(vex, pos, .vpcmpgtq, modrm),
        0x38 => decodeVexReturn(vex, pos, .vpminsb, modrm),
        0x39 => decodeVexReturn(vex, pos, .vpminsd, modrm),
        0x3A => decodeVexReturn(vex, pos, .vpminuw, modrm),
        0x3B => decodeVexReturn(vex, pos, .vpminud, modrm),
        0x3C => decodeVexReturn(vex, pos, .vpmaxsb, modrm),
        0x3D => decodeVexReturn(vex, pos, .vpmaxsd, modrm),
        0x3E => decodeVexReturn(vex, pos, .vpmaxuw, modrm),
        0x3F => decodeVexReturn(vex, pos, .vpmaxud, modrm),
        0x40 => decodeVexReturn(vex, pos, .vpmulld_38, modrm),
        0x41 => decodeVexReturn(vex, pos, .vphminposuw, modrm),
        0x45 => decodeVexReturn(vex, pos, .vpsrlvd, modrm),
        0x46 => decodeVexReturn(vex, pos, .vpsravd, modrm),
        0x47 => decodeVexReturn(vex, pos, .vpsllvd, modrm),
        0x4C => decodeVexReturn(vex, pos, .vpblendvb, modrm),
        0x4D => decodeVexReturn(vex, pos, .vpblendw, modrm), // VEX.0F3A 0E fallback
        // VEX.0F38 FMA — PS/PD variants selected by VEX.W bit
        0x96 => decodeVexReturn(vex, pos, if (vex.w) .vfmaddsub132pd else .vfmaddsub132ps, modrm),
        0x97 => decodeVexReturn(vex, pos, if (vex.w) .vfmsubadd132pd else .vfmsubadd132ps, modrm),
        0x98 => decodeVexReturn(vex, pos, if (vex.w) .vfmadd132pd else .vfmadd132ps, modrm),
        0x9A => decodeVexReturn(vex, pos, if (vex.w) .vfmsub132pd else .vfmsub132ps, modrm),
        0xA6 => decodeVexReturn(vex, pos, if (vex.w) .vfmaddsub213pd else .vfmaddsub213ps, modrm),
        0xA7 => decodeVexReturn(vex, pos, if (vex.w) .vfmsubadd213pd else .vfmsubadd213ps, modrm),
        0xA8 => decodeVexReturn(vex, pos, if (vex.w) .vfmadd213pd else .vfmadd213ps, modrm),
        0xAA => decodeVexReturn(vex, pos, if (vex.w) .vfmsub213pd else .vfmsub213ps, modrm),
        0xB6 => decodeVexReturn(vex, pos, if (vex.w) .vfmaddsub231pd else .vfmaddsub231ps, modrm),
        0xB7 => decodeVexReturn(vex, pos, if (vex.w) .vfmsubadd231pd else .vfmsubadd231ps, modrm),
        0xB8 => decodeVexReturn(vex, pos, if (vex.w) .vfmadd231pd else .vfmadd231ps, modrm),
        0xBA => decodeVexReturn(vex, pos, if (vex.w) .vfmsub231pd else .vfmsub231ps, modrm),
        else => null,
    };
}

/// Decode VEX opcode map 0x3A (VEX.0F3A).
/// Handles VEX-encoded immediate byte instructions.
fn decodeVexMap3A(vex: VexPrefix, pos: usize, opcode: u8, modrm: anytype, imm: u8) ?DecodedInsn {
    // VEX opcode map 0x3A uses the 0F 3A two-byte opcode prefix.
    // All 0x3A instructions have an 8-bit immediate byte (already consumed
    // by the caller). The immediate controls operation selection, element
    // insertion/sign extension, or broadcast behavior.
    return switch (opcode) {
        0x0A => decodeVexReturnImm(vex, pos, .vpextrb, modrm, imm), // VPEXTRB
        0x0B => decodeVexReturnImm(vex, pos, .vpextrw, modrm, imm), // VPEXTRW
        0x0C => decodeVexReturnImm(vex, pos, .vpextrd, modrm, imm), // VPEXTRD / VEXTRACTPS
        0x0D => decodeVexReturnImm(vex, pos, .vpextrq, modrm, imm), // VPEXTRQ
        0x0E => decodeVexReturnImm(vex, pos, .vpblendw, modrm, imm), // VPBLENDW
        0x0F => decodeVexReturnImm(vex, pos, .vpalignr, modrm, imm), // VPALIGNR
        0x16 => decodeVexReturnImm(vex, pos, .vpermps, modrm, imm), // VPERMPS
        0x17 => decodeVexReturnImm(vex, pos, .vextractf128, modrm, imm), // VEXTRACTF128 (VEX.L=1)
        0x18 => decodeVexReturnImm(vex, pos, .vbroadcastss, modrm, imm), // VBROADCASTSS
        0x19 => decodeVexReturnImm(vex, pos, .vbroadcastsd, modrm, imm), // VBROADCASTSD (YMM only)
        0x1A => decodeVexReturnImm(vex, pos, .vbroadcastf128, modrm, imm), // VBROADCASTF128
        0x1B => decodeVexReturnImm(vex, pos, .vbroadcasti128, modrm, imm), // VBROADCASTI128
        0x20 => decodeVexReturnImm(vex, pos, .vpinsrb_xmm_xmm_reg32, modrm, imm), // VPINSRB
        0x21 => decodeVexReturnImm(vex, pos, .vinsertps, modrm, imm), // VEX.0F3A 21 = VINSERTPS
        0x25 => decodeVexReturnImm(vex, pos, .vpternlogd, modrm, imm), // VPTERNLOGD
        0x26 => decodeVexReturnImm(vex, pos, .vpternlogq, modrm, imm), // VPTERNLOGQ
        0x4A => decodeVexReturnImm(vex, pos, .valignd, modrm, imm), // VALIGND
        0x4B => decodeVexReturnImm(vex, pos, .valignq, modrm, imm), // VALIGNQ
        else => null,
    };
}

/// Decodes every legacy general-purpose MOV encoding that is valid in long
/// mode: ModR/M register/memory forms, opcode-embedded immediates, Group 11
/// immediates, and moffs accumulator forms. All forms share the same prefix,
/// register, SIB, and displacement machinery above.
pub fn decodeVex2(bytes: []const u8, start_pos: usize) DecodedInsn {
    if (start_pos + 3 > bytes.len) return .{};

    const vex = bytes[start_pos + 1];
    const opcode = bytes[start_pos + 2];
    const rex_r = (vex & 0x80) == 0;
    const vector_256 = (vex & 0x04) != 0;
    const prefix = vex & 0x03;

    if (opcode == 0x77 and (vex & 0x78) == 0x78 and !vector_256 and prefix == 0) {
        return .{ .op = .vzeroupper, .len = @intCast(start_pos + 3) };
    }
    if (start_pos + 3 >= bytes.len) return .{};

    if (opcode == 0x6E and (vex & 0x78) == 0x78 and !vector_256 and prefix == 1) {
        var decoded = DecodedInsn{ .size = .bits32 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            decoded.op = .vmovd_xmm_mem32;
            decoded.addr = rm.addr;
        } else {
            decoded.op = .vmovd_xmm_reg32;
            decoded.src_reg = @enumFromInt(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x7E and (vex & 0x78) == 0x78 and !vector_256 and prefix == 1) {
        var decoded = DecodedInsn{ .size = .bits32 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            decoded.op = .vmovd_mem32_xmm;
            decoded.addr = rm.addr;
        } else {
            decoded.op = .vmovd_reg32_xmm;
            decoded.dst_reg = @enumFromInt(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x7E and (vex & 0x78) == 0x78 and !vector_256 and prefix == 2) {
        var decoded = DecodedInsn{ .size = .bits64 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (is_memory) {
            decoded.op = .vmovq_xmm_mem64;
            decoded.addr = rm.addr;
        } else {
            return .{};
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if ((opcode == 0x64 or opcode == 0x65 or opcode == 0x66 or opcode == 0x74 or opcode == 0x75 or opcode == 0x76) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x64 => .vpcmpgtb,
            0x65 => .vpcmpgtw,
            0x66 => .vpcmpgtd,
            0x74 => .vpcmpeqb,
            0x75 => .vpcmpeqw,
            0x76 => .vpcmpeqd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x62 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpunpckldq, .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x6C and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpunpcklqdq, .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPSHUFD: VEX.NDS.LIG.66.0F.WIG 70 /r ib
    if (opcode == 0x70 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpshufd, .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @intCast(rm.addr);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        }
        // Immediate byte for shuffle control
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if ((opcode == 0x12 or opcode == 0x13 or opcode == 0x16 or opcode == 0x17) and
        !vector_256 and (prefix == 0 or prefix == 1))
    {
        return decodeVexHalfMove(bytes, start_pos + 3, opcode, prefix, vex, rex_r, false, false);
    }

    if ((opcode == 0x16 and prefix == 2) or (opcode == 0x12 and (prefix == 2 or prefix == 3))) {
        return decodeVexDuplicateMove(bytes, start_pos + 3, opcode, prefix, vex, rex_r, false, false, vector_256);
    }

    if (opcode == 0x2A and !vector_256 and (prefix == 2 or prefix == 3)) {
        var decoded = DecodedInsn{ .size = .bits32 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_mem else .vcvtsi2sd_xmm_mem;
        } else {
            decoded.src_reg = @enumFromInt(rm.addr);
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_reg else .vcvtsi2sd_xmm_reg;
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x5A and !vector_256 and prefix == 2) {
        var decoded = DecodedInsn{ .op = .vcvtss2sd, .size = .bits32 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VCVTSD2SS: VEX.LIG.F2.0F.WIG 5A /r
    if (opcode == 0x5A and prefix == 3) {
        var decoded = DecodedInsn{ .op = .vcvtsd2ss, .size = .bits64 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VSQRTPS/PD and VSQRTSS/SD: VEX.128/256.[66/F3/F2].0F.WIG 51 /r.
    // Scalar forms merge the upper 96/64 bits from VEX.vvvv. Packed forms
    // have a single r/m source, but retaining vvvv here keeps the decoded
    // shape uniform and makes malformed/reserved encodings diagnosable.
    if (opcode == 0x51) {
        if (vector_256 and (prefix == 2 or prefix == 3)) return .{};

        var decoded = DecodedInsn{
            .size = if (prefix == 1 or prefix == 3) .bits64 else .bits32,
            .vector_256 = vector_256,
        };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, decoded.size);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (prefix) {
            0 => .vsqrtps,
            1 => .vsqrtpd,
            2 => .vsqrtss,
            3 => .vsqrtsd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPINSRW: VEX.128.66.0F.W0 C4 /r ib — Insert Word
    // Encoding: ModRM.r/m = destination XMM, ModRM.reg = GPR, VEX.vvvv = merge source
    if (opcode == 0xC4 and !vector_256 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpinsrw, .size = .bits16 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F); // VEX.vvvv = merge source XMM
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.xmm_dst = decoded.xmm_src; // merge source is implicit destination
            decoded.addr = rm.addr; // memory address
        } else {
            decoded.xmm_dst = @intCast(rm.addr); // ModRM.r/m = destination XMM
            decoded.xmm_src2 = @intFromEnum(rm.reg); // ModRM.reg = GPR source
        }
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if ((opcode == 0x2C or opcode == 0x2D) and !vector_256 and (prefix == 2 or prefix == 3) and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .size = .bits32 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.dst_reg = rm.reg;
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        decoded.op = if (opcode == 0x2C)
            if (prefix == 2) .vcvttss2si else .vcvttsd2si
        else if (prefix == 2)
            .vcvtss2si
        else
            .vcvtsd2si;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x58 or opcode == 0x59 or opcode == 0x5C or opcode == 0x5E) {
        if (vector_256 and (prefix == 2 or prefix == 3)) return .{};

        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var arithmetic_pos = start_pos + 3;
        const is_mem = bytes[arithmetic_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &arithmetic_pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x58 => switch (prefix) {
                0 => .vaddps,
                1 => .vaddpd,
                2 => .vaddss,
                3 => .vaddsd,
                else => unreachable,
            },
            0x59 => switch (prefix) {
                0 => .vmulps,
                1 => .vmulpd,
                2 => .vmulss,
                3 => .vmulsd,
                else => unreachable,
            },
            0x5C => switch (prefix) {
                0 => .vsubps,
                1 => .vsubpd,
                2 => .vsubss,
                3 => .vsubsd,
                else => unreachable,
            },
            0x5E => switch (prefix) {
                0 => .vdivps,
                1 => .vdivpd,
                2 => .vdivss,
                3 => .vdivsd,
                else => unreachable,
            },
            else => unreachable,
        };
        decoded.len = @intCast(arithmetic_pos);
        return decoded;
    }

    if (opcode >= 0x54 and opcode <= 0x57 and (prefix == 0 or prefix == 1)) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var bitwise_pos = start_pos + 3;
        const is_mem = bytes[bitwise_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &bitwise_pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x54 => if (prefix == 0) .vandps else .vandpd,
            0x55 => if (prefix == 0) .vandnps else .vandnpd,
            0x56 => if (prefix == 0) .vorps else .vorpd,
            0x57 => if (prefix == 0) .vxorps else .vxorpd,
            else => unreachable,
        };
        decoded.len = @intCast(bitwise_pos);
        return decoded;
    }

    if ((opcode == 0xDB or opcode == 0xDF or opcode == 0xEB or opcode == 0xEF) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pp_pos = start_pos + 3;
        const is_mem = bytes[pp_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pp_pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xDB => .vpand,
            0xDF => .vpandn,
            0xEB => .vpor,
            0xEF => .vpxor,
            else => unreachable,
        };
        decoded.len = @intCast(pp_pos);
        return decoded;
    }

    if ((opcode == 0x2E or opcode == 0x2F) and (vex & 0x78) == 0x78 and !vector_256 and (prefix == 0 or prefix == 1)) {
        var decoded = DecodedInsn{};
        var compare_pos = start_pos + 3;
        const is_mem = bytes[compare_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &compare_pos, rex_r, false, false, .bits64);
        decoded.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = if (prefix == 0) .vucomiss else .vucomisd;
        decoded.len = @intCast(compare_pos);
        return decoded;
    }

    if (opcode == 0xD7 and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.dst_reg = rm.reg;
        decoded.xmm_src = @intCast(rm.addr);
        decoded.op = if (vector_256) .vpmovmskb_ymm else .vpmovmskb;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPMULUDQ: VEX.NDS.128.66.0F.WIG F4 /r
    if (opcode == 0xF4 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = .vpmuludq;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // Variable-count packed logical shifts. The count is the low 64 bits of
    // the third XMM/m128 operand and applies to every element.
    if ((opcode == 0xD1 or opcode == 0xD2 or opcode == 0xD3 or
        opcode == 0xF1 or opcode == 0xF2 or opcode == 0xF3) and prefix == 1)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xD1 => .vpsrlw,
            0xD2 => .vpsrld,
            0xD3 => .vpsrlq,
            0xF1 => .vpsllw,
            0xF2 => .vpslld,
            0xF3 => .vpsllq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPUNPCKHBW/HDQ/HWD: VEX.NDS.128.66.0F.WIG 68/69/6A /r
    if ((opcode == 0x68 or opcode == 0x69 or opcode == 0x6A) and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x68 => .vpunpckhbw,
            0x69 => .vpunpckhwd,
            0x6A => .vpunpckhdq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPUNPCKLBW/LWD/LQD: VEX.NDS.128.66.0F.WIG 60/61/62 /r
    if ((opcode == 0x60 or opcode == 0x61) and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x60 => .vpunpcklbw,
            0x61 => .vpunpcklwd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPSHUFB: VEX.NDS.128.66.0F.WIG 00 /r ib
    if (opcode == 0x00 and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        // Immediate byte for shuffle control
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = .vpshufb;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPSHUFD: VEX.NDS.LIG.66.0F.WIG 70 /r ib (already handled above, keeping for reference)

    // Immediate-count packed shifts: /2 and /3 shift right, /6 and /7
    // shift left. VEX.vvvv is the destination and ModRM.r/m is the source.
    if ((opcode == 0x71 or opcode == 0x72 or opcode == 0x73) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        const group = (@intFromEnum(rm.reg) & 0x07);
        if (group != 2 and group != 3 and group != 6 and group != 7) return .{};
        decoded.xmm_dst = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        decoded.uses_imm = true;
        pos += 1;
        decoded.op = switch (opcode) {
            0x71 => if (group == 2) .vpsrlw else .vpsllw,
            0x72 => if (group == 2) .vpsrld else .vpslld,
            0x73 => switch (group) {
                2 => .vpsrlq,
                3 => .vpsrldq,
                6 => .vpsllq,
                7 => .vpslldq,
                else => unreachable,
            },
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPSUBB/PSUBD/PSUBQ/PSUBW: VEX.NDS.128.66.0F.WIG F8/FA/FB/F9 /r
    if ((opcode == 0xF8 or opcode == 0xFA or opcode == 0xFB or opcode == 0xF9) and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xF8 => .vpsubb,
            0xFA => .vpsubd,
            0xFB => .vpsubq,
            0xF9 => .vpsubw,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPADDB/PADDW/PADDD/PADDQ: VEX.NDS.128/256.66.0F.WIG FC/FD/FE/D4 /r
    if ((opcode == 0xFC or opcode == 0xFD or opcode == 0xFE or opcode == 0xD4) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xFC => .vpaddb,
            0xFD => .vpaddw,
            0xFE => .vpaddd,
            0xD4 => .vpaddq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPMULLW: VEX.NDS.128.66.0F.WIG D5 /r
    if (opcode == 0xD5 and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = .vpmullw;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if ((vex & 0x78) != 0x78) return .{};

    var d = DecodedInsn{ .vector_256 = vector_256 };
    var pos = start_pos + 3;
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, false, false, .bits64);

    const is_load = switch (opcode) {
        0x6F, 0x10, 0x28 => true,
        0x7F, 0x11, 0x29 => false,
        else => return .{},
    };

    const family: enum { dqu, dqa, ups, aps, upd, apd, ss, sd } = switch (opcode) {
        0x6F, 0x7F => switch (prefix) {
            1 => .dqa,
            2 => .dqu,
            else => return .{},
        },
        0x10, 0x11 => switch (prefix) {
            0 => .ups,
            1 => .upd,
            2 => .ss,
            3 => .sd,
            else => unreachable,
        },
        0x28, 0x29 => switch (prefix) {
            0 => .aps,
            1 => .apd,
            else => return .{},
        },
        else => unreachable,
    };

    if ((family == .ss or family == .sd) and !is_mem) return .{};
    if ((family == .ss or family == .sd) and vector_256) return .{};

    if (is_load) {
        d.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            d.addr = rm.addr;
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_ymm_mem,
                .dqa => .vmovdqa_ymm_mem,
                .ups => .vmovups_ymm_mem,
                .aps => .vmovaps_ymm_mem,
                .upd => .vmovupd_ymm_mem,
                .apd => .vmovapd_ymm_mem,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_xmm_mem,
                .dqa => .vmovdqa_xmm_mem,
                .ups => .vmovups_xmm_mem,
                .aps => .vmovaps_xmm_mem,
                .upd => .vmovupd_xmm_mem,
                .apd => .vmovapd_xmm_mem,
                .ss => .vmovss_xmm_mem,
                .sd => .vmovsd_xmm_mem,
            };
        } else {
            d.xmm_src = @intCast(rm.addr);
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_ymm_ymm,
                .dqa => .vmovdqa_ymm_ymm,
                .ups => .vmovups_ymm_ymm,
                .aps => .vmovaps_ymm_ymm,
                .upd => .vmovupd_ymm_ymm,
                .apd => .vmovapd_ymm_ymm,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_xmm_xmm,
                .dqa => .vmovdqa_xmm_xmm,
                .ups => .vmovups_xmm_xmm,
                .aps => .vmovaps_xmm_xmm,
                .upd => .vmovupd_xmm_xmm,
                .apd => .vmovapd_xmm_xmm,
                .ss, .sd => unreachable,
            };
        }
    } else {
        d.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            d.addr = rm.addr;
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_mem_ymm,
                .dqa => .vmovdqa_mem_ymm,
                .ups => .vmovups_mem_ymm,
                .aps => .vmovaps_mem_ymm,
                .upd => .vmovupd_mem_ymm,
                .apd => .vmovapd_mem_ymm,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_mem_xmm,
                .dqa => .vmovdqa_mem_xmm,
                .ups => .vmovups_mem_xmm,
                .aps => .vmovaps_mem_xmm,
                .upd => .vmovupd_mem_xmm,
                .apd => .vmovapd_mem_xmm,
                .ss => .vmovss_mem_xmm,
                .sd => .vmovsd_mem_xmm,
            };
        } else {
            d.xmm_dst = @intCast(rm.addr);
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_ymm_ymm,
                .dqa => .vmovdqa_ymm_ymm,
                .ups => .vmovups_ymm_ymm,
                .aps => .vmovaps_ymm_ymm,
                .upd => .vmovupd_ymm_ymm,
                .apd => .vmovapd_ymm_ymm,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_xmm_xmm,
                .dqa => .vmovdqa_xmm_xmm,
                .ups => .vmovups_xmm_xmm,
                .aps => .vmovaps_xmm_xmm,
                .upd => .vmovupd_xmm_xmm,
                .apd => .vmovapd_xmm_xmm,
                .ss, .sd => unreachable,
            };
        }
    }

    d.len = @intCast(pos);
    return d;
}

pub fn decodeVex3(bytes: []const u8, start_pos: usize) DecodedInsn {
    if (start_pos + 5 > bytes.len) return .{};
    const vex_map = bytes[start_pos + 1];
    const vex_control = bytes[start_pos + 2];
    const opcode = bytes[start_pos + 3];
    const opcode_map = vex_map & 0x1F;
    const rex_r = (vex_map & 0x80) == 0;
    const rex_x = (vex_map & 0x40) == 0;
    const rex_b = (vex_map & 0x20) == 0;
    const rex_w = (vex_control & 0x80) != 0;
    const vector_256 = (vex_control & 0x04) != 0;
    const prefix = vex_control & 0x03;

    if (opcode_map == 1 and opcode == 0x51) {
        if (vector_256 and (prefix == 2 or prefix == 3)) return .{};

        var decoded = DecodedInsn{
            .size = if (prefix == 1 or prefix == 3) .bits64 else .bits32,
            .vector_256 = vector_256,
        };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, decoded.size);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (prefix) {
            0 => .vsqrtps,
            1 => .vsqrtpd,
            2 => .vsqrtss,
            3 => .vsqrtsd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VEX.0F arithmetic: VADD (58), VMUL (59), VSUB (5C), VDIV (5E)
    // Prefix: 0=PS, 1=PD, 2=SS, 3=SD
    if (opcode_map == 1 and
        (opcode == 0x58 or opcode == 0x59 or opcode == 0x5C or opcode == 0x5E))
    {
        if (vector_256 and (prefix == 2 or prefix == 3)) return .{};

        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x58 => switch (prefix) {
                0 => .vaddps,
                1 => .vaddpd,
                2 => .vaddss,
                3 => .vaddsd,
                else => unreachable,
            },
            0x59 => switch (prefix) {
                0 => .vmulps,
                1 => .vmulpd,
                2 => .vmulss,
                3 => .vmulsd,
                else => unreachable,
            },
            0x5C => switch (prefix) {
                0 => .vsubps,
                1 => .vsubpd,
                2 => .vsubss,
                3 => .vsubsd,
                else => unreachable,
            },
            0x5E => switch (prefix) {
                0 => .vdivps,
                1 => .vdivpd,
                2 => .vdivss,
                3 => .vdivsd,
                else => unreachable,
            },
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VEX.0F bitwise ops: VAND (54/55), VOR (56), VXOR (57)
    // Prefix: 0=PS, 1=PD only
    if (opcode_map == 1 and opcode >= 0x54 and opcode <= 0x57 and (prefix == 0 or prefix == 1)) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x54 => if (prefix == 0) .vandps else .vandpd,
            0x55 => if (prefix == 0) .vandnps else .vandnpd,
            0x56 => if (prefix == 0) .vorps else .vorpd,
            0x57 => if (prefix == 0) .vxorps else .vxorpd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and
        (opcode == 0x12 or opcode == 0x13 or opcode == 0x16 or opcode == 0x17) and
        !vector_256 and (prefix == 0 or prefix == 1))
    {
        return decodeVexHalfMove(bytes, start_pos + 4, opcode, prefix, vex_control, rex_r, rex_x, rex_b);
    }

    if (opcode_map == 1 and
        ((opcode == 0x16 and prefix == 2) or (opcode == 0x12 and (prefix == 2 or prefix == 3))))
    {
        return decodeVexDuplicateMove(bytes, start_pos + 4, opcode, prefix, vex_control, rex_r, rex_x, rex_b, vector_256);
    }

    if (opcode_map == 1 and opcode == 0x76 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vpcmpeqd;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x62 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpunpckldq, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x6C and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpunpcklqdq, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPMULUDQ: VEX.NDS.128/256.66.0F.WIG F4 /r
    if (opcode_map == 1 and opcode == 0xF4 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpmuludq, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and
        (opcode == 0xD1 or opcode == 0xD2 or opcode == 0xD3 or
            opcode == 0xF1 or opcode == 0xF2 or opcode == 0xF3) and prefix == 1)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xD1 => .vpsrlw,
            0xD2 => .vpsrld,
            0xD3 => .vpsrlq,
            0xF1 => .vpsllw,
            0xF2 => .vpslld,
            0xF3 => .vpsllq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and
        (opcode == 0xF8 or opcode == 0xF9 or opcode == 0xFA or opcode == 0xFB or
            opcode == 0xFC or opcode == 0xFD or opcode == 0xFE or opcode == 0xD4 or opcode == 0xD5) and prefix == 1)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xF8 => .vpsubb,
            0xF9 => .vpsubw,
            0xFA => .vpsubd,
            0xFB => .vpsubq,
            0xFC => .vpaddb,
            0xFD => .vpaddw,
            0xFE => .vpaddd,
            0xD4 => .vpaddq,
            0xD5 => .vpmullw,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode == 0x0E and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpblendw, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.imm = bytes[pos];
        decoded.uses_imm = true;
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode == 0x05 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpermilpd, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and (opcode == 0x6E or opcode == 0x7E)) {
        if (vector_256 or prefix != 1 or (vex_control & 0x78) != 0x78) return .{};

        var decoded = DecodedInsn{ .size = if (rex_w) .bits64 else .bits32 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, decoded.size);
        if (opcode == 0x6E) {
            decoded.xmm_dst = @intFromEnum(rm.reg);
            if (is_mem) {
                decoded.op = if (rex_w) .vmovq_xmm_mem64 else .vmovd_xmm_mem32;
                decoded.addr = rm.addr;
            } else {
                decoded.op = if (rex_w) .vmovq_xmm_reg64 else .vmovd_xmm_reg32;
                decoded.src_reg = @enumFromInt(rm.addr);
            }
        } else {
            decoded.xmm_src = @intFromEnum(rm.reg);
            if (is_mem) {
                decoded.op = if (rex_w) .vmovq_mem64_xmm else .vmovd_mem32_xmm;
                decoded.addr = rm.addr;
            } else {
                decoded.op = if (rex_w) .vmovq_reg64_xmm else .vmovd_reg32_xmm;
                decoded.dst_reg = @enumFromInt(rm.addr);
            }
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x2A) {
        if (vector_256 or (prefix != 2 and prefix != 3)) return .{};

        var decoded = DecodedInsn{ .size = if (rex_w) .bits64 else .bits32 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, decoded.size);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @as(u8, @truncate((~vex_control >> 3) & 0x0F));
        if (is_mem) {
            decoded.addr = rm.addr;
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_mem else .vcvtsi2sd_xmm_mem;
        } else {
            decoded.src_reg = @enumFromInt(rm.addr);
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_reg else .vcvtsi2sd_xmm_reg;
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x5A) {
        if (rex_w) return .{};
        if (prefix == 2 and !vector_256) {
            var decoded = DecodedInsn{ .op = .vcvtss2sd, .size = .bits32 };
            var pos = start_pos + 4;
            const is_memory = bytes[pos] < 0xC0;
            const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits32);
            decoded.xmm_dst = @intFromEnum(rm.reg);
            decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
            decoded.is_reg_form = !is_memory;
            if (is_memory) {
                decoded.addr = rm.addr;
            } else {
                decoded.xmm_src2 = @intCast(rm.addr);
            }
            decoded.len = @intCast(pos);
            return decoded;
        }
        if (prefix == 3) {
            var decoded = DecodedInsn{ .op = .vcvtsd2ss, .size = .bits64 };
            var pos = start_pos + 4;
            const is_memory = bytes[pos] < 0xC0;
            const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
            decoded.xmm_dst = @intFromEnum(rm.reg);
            decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
            decoded.is_reg_form = !is_memory;
            if (is_memory) {
                decoded.addr = rm.addr;
            } else {
                decoded.xmm_src2 = @intCast(rm.addr);
            }
            decoded.len = @intCast(pos);
            return decoded;
        }
    }

    if (opcode_map == 1 and (opcode == 0x2C or opcode == 0x2D)) {
        if (vector_256 or (prefix != 2 and prefix != 3) or (vex_control & 0x78) != 0x78) return .{};

        var decoded = DecodedInsn{ .size = if (rex_w) .bits64 else .bits32 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, decoded.size);
        decoded.dst_reg = rm.reg;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        decoded.op = if (opcode == 0x2C)
            if (prefix == 2) .vcvttss2si else .vcvttsd2si
        else if (prefix == 2)
            .vcvtss2si
        else
            .vcvtsd2si;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 2 and opcode == 0x00 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vpshufb;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 2 and opcode == 0x17 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vptest;
        decoded.xmm_src = @intFromEnum(rm.reg);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 2 and (opcode == 0x29 or opcode == 0x37) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x29 => .vpcmpeqq,
            0x37 => .vpcmpgtq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode >= 0x08 and opcode <= 0x0B and prefix == 1) {
        const is_scalar = opcode == 0x0A or opcode == 0x0B;
        if (is_scalar and vector_256) return .{};
        if (!is_scalar and (vex_control & 0x78) != 0x78) return .{};

        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = switch (opcode) {
            0x08 => .vroundps,
            0x09 => .vroundpd,
            0x0A => .vroundss,
            0x0B => .vroundsd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPINSRD/VPINSRQ/VPINSRW: VEX.NDS.LIG.66.0F38.WIG 22/23/2A /r ib
    if (opcode_map == 3 and (opcode == 0x22 or opcode == 0x23 or opcode == 0x2A) and prefix == 1 and !vector_256) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        // Immediate byte for index
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = switch (opcode) {
            0x22 => .vpinsrd,
            0x23 => .vpinsrq,
            0x2A => .vpinsrw,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode == 0x20 and prefix == 1 and !vector_256) {
        var decoded = DecodedInsn{ .size = .bits8 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits8);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.op = .vpinsrb_xmm_xmm_mem8;
            decoded.addr = rm.addr;
        } else {
            decoded.op = .vpinsrb_xmm_xmm_reg32;
            decoded.src_reg = @enumFromInt(rm.addr);
        }
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and (opcode == 0x64 or opcode == 0x65 or opcode == 0x66 or opcode == 0x74 or opcode == 0x75 or opcode == 0x76) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x64 => .vpcmpgtb,
            0x65 => .vpcmpgtw,
            0x66 => .vpcmpgtd,
            0x74 => .vpcmpeqb,
            0x75 => .vpcmpeqw,
            0x76 => .vpcmpeqd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and (opcode == 0xDB or opcode == 0xDF or opcode == 0xEB or opcode == 0xEF) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pp_pos = start_pos + 4;
        const is_mem = bytes[pp_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pp_pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xDB => .vpand,
            0xDF => .vpandn,
            0xEB => .vpor,
            0xEF => .vpxor,
            else => unreachable,
        };
        decoded.len = @intCast(pp_pos);
        return decoded;
    }

    // Three-byte VEX is required when X/B extension bits address r8-r15 even
    // for ordinary 0F-map moves. Xbyak emits this form for VMOVDQU [r9],xmm0.
    if (opcode_map == 1 and (opcode == 0x6F or opcode == 0x7F) and
        (prefix == 1 or prefix == 2) and (vex_control & 0x78) == 0x78)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        const unaligned = prefix == 2;
        if (opcode == 0x6F) {
            decoded.xmm_dst = @intFromEnum(rm.reg);
            if (is_memory) {
                decoded.addr = rm.addr;
                decoded.op = if (vector_256)
                    if (unaligned) .vmovdqu_ymm_mem else .vmovdqa_ymm_mem
                else if (unaligned)
                    .vmovdqu_xmm_mem
                else
                    .vmovdqa_xmm_mem;
            } else {
                decoded.xmm_src = @intCast(rm.addr);
                decoded.op = if (vector_256)
                    if (unaligned) .vmovdqu_ymm_ymm else .vmovdqa_ymm_ymm
                else if (unaligned)
                    .vmovdqu_xmm_xmm
                else
                    .vmovdqa_xmm_xmm;
            }
        } else {
            decoded.xmm_src = @intFromEnum(rm.reg);
            if (is_memory) {
                decoded.addr = rm.addr;
                decoded.op = if (vector_256)
                    if (unaligned) .vmovdqu_mem_ymm else .vmovdqa_mem_ymm
                else if (unaligned)
                    .vmovdqu_mem_xmm
                else
                    .vmovdqa_mem_xmm;
            } else {
                decoded.xmm_dst = @intCast(rm.addr);
                decoded.op = if (vector_256)
                    if (unaligned) .vmovdqu_ymm_ymm else .vmovdqa_ymm_ymm
                else if (unaligned)
                    .vmovdqu_xmm_xmm
                else
                    .vmovdqa_xmm_xmm;
            }
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    return .{};
}

pub fn decodeVexHalfMove(
    bytes: []const u8,
    modrm_pos: usize,
    opcode: u8,
    prefix: u8,
    vex_control: u8,
    rex_r: bool,
    rex_x: bool,
    rex_b: bool,
) DecodedInsn {
    if (modrm_pos >= bytes.len or bytes[modrm_pos] >= 0xC0) return .{};

    const is_load = opcode == 0x12 or opcode == 0x16;
    if (!is_load and (vex_control & 0x78) != 0x78) return .{};

    var decoded = DecodedInsn{};
    var pos = modrm_pos;
    const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
    decoded.addr = rm.addr;
    if (is_load) {
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
    } else {
        decoded.xmm_src = @intFromEnum(rm.reg);
    }
    decoded.op = switch (opcode) {
        0x12 => if (prefix == 0) .vmovlps_xmm_xmm_mem64 else .vmovlpd_xmm_xmm_mem64,
        0x13 => if (prefix == 0) .vmovlps_mem64_xmm else .vmovlpd_mem64_xmm,
        0x16 => if (prefix == 0) .vmovhps_xmm_xmm_mem64 else .vmovhpd_xmm_xmm_mem64,
        0x17 => if (prefix == 0) .vmovhps_mem64_xmm else .vmovhpd_mem64_xmm,
        else => unreachable,
    };
    decoded.len = @intCast(pos);
    return decoded;
}

pub fn decodeVexDuplicateMove(
    bytes: []const u8,
    modrm_pos: usize,
    opcode: u8,
    prefix: u8,
    vex_control: u8,
    rex_r: bool,
    rex_x: bool,
    rex_b: bool,
    vector_256: bool,
) DecodedInsn {
    if (modrm_pos >= bytes.len or (vex_control & 0x78) != 0x78) return .{};

    var decoded = DecodedInsn{ .vector_256 = vector_256 };
    var pos = modrm_pos;
    const is_mem = bytes[pos] < 0xC0;
    const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.is_reg_form = !is_mem;
    if (is_mem) {
        decoded.addr = rm.addr;
    } else {
        decoded.xmm_src = @intCast(rm.addr);
    }
    decoded.op = if (opcode == 0x16) .vmovshdup else if (prefix == 2) .vmovsldup else .vmovddup;
    decoded.len = @intCast(pos);
    return decoded;
}
