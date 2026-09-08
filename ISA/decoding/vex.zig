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

fn evexRegIndex(evex: EvexPrefix, code: u3) u8 {
    return @as(u8, code) |
        (if (evex.r) @as(u8, 8) else 0) |
        (if (evex.r_prime) @as(u8, 16) else 0);
}

fn evexRmIndex(evex: EvexPrefix, code: u3) u8 {
    // In register form EVEX.B and EVEX.X are the two high bits of ModRM.r/m.
    // In memory form they remain address-register extensions and are consumed
    // by readModRM below.
    return @as(u8, code) |
        (if (evex.b) @as(u8, 8) else 0) |
        (if (evex.x) @as(u8, 16) else 0);
}

fn evexVIndex(evex: EvexPrefix) u8 {
    return @as(u8, evex.vvvv) | (if (evex.v_prime) @as(u8, 16) else 0);
}

/// Decode the ModR/M byte following an EVEX prefix with 5-bit register
/// addressing (R' extends ModRM.reg, B/X extend a register-form ModRM.r/m,
/// and V' extends vvvv). Addressing metadata is decoded by the shared
/// readModRM routine so live-register address resolution remains identical to
/// legacy/VEX instructions. EVEX disp8 is signed and tuple-scaled.
fn decodeEvexModRm(
    bytes: []const u8,
    pos: *usize,
    evex: EvexPrefix,
    element_width_bytes: u8,
) ?struct {
    decoded: DecodedInsn,
    mod: u2,
    reg_code: u3,
    rm_code: u3,
} {
    if (pos.* >= bytes.len) return null;
    const modrm_pos = pos.*;
    const modrm = bytes[modrm_pos];
    const mod: u2 = @truncate(modrm >> 6);
    const reg_code: u3 = @truncate(modrm >> 3);
    const rm_code: u3 = @truncate(modrm);

    // Preflight the complete ModR/M/SIB/displacement footprint. readModRM is
    // intentionally a compact hot-path helper and assumes a well-formed
    // instruction; the EVEX entry point must reject truncated byte streams
    // before handing them to it.
    var after_modrm = modrm_pos + 1;
    var sib_base: u3 = 0;
    if (mod != 3 and rm_code == 4) {
        if (after_modrm >= bytes.len) return null;
        const sib = bytes[after_modrm];
        sib_base = @truncate(sib);
        after_modrm += 1;
    }
    const displacement_size: usize = switch (mod) {
        0 => if (rm_code == 5 or (rm_code == 4 and sib_base == 5)) 4 else 0,
        1 => 1,
        2 => 4,
        else => 0,
    };
    if (after_modrm + displacement_size > bytes.len) return null;

    var decoded = DecodedInsn{};
    _ = readModRM(&decoded, bytes, pos, evex.r, evex.x, evex.b, .bits64);

    if (mod != 3 and mod == 1) {
        // EVEX tuple scaling is N = vector width for ordinary packed loads,
        // or the element width for broadcast forms. All current callers pass
        // the element width in bytes; the vector-width values are the common
        // Full tuple used by the Windows Xenia instructions.
        const scale: i64 = if (evex.broadcast)
            @intCast(element_width_bytes)
        else switch (evex.vector_length) {
            0 => 16,
            1 => 32,
            2 => 64,
            else => return null,
        };
        const displacement_pos = modrm_pos + 1 + (if (rm_code == 4) @as(usize, 1) else 0);
        const signed: i64 = @as(i8, @bitCast(bytes[displacement_pos]));
        decoded.addr = @bitCast(signed * scale);
    }

    return .{
        .decoded = decoded,
        .mod = mod,
        .reg_code = reg_code,
        .rm_code = rm_code,
    };
}

pub fn decodeVexInstruction(bytes: []const u8) ?DecodedInsn {
    // Check for EVEX prefix (0x62) before VEX (0xC5/0xC4). This is a real
    // decoder path, not a metadata-only placeholder: the Windows Xenia PE
    // contains AVX-512 instructions in its optimized memory/shader helpers.
    if (bytes.len > 0 and bytes[0] == 0x62) {
        const evex = decodeEvexPrefix(bytes) orelse return null;
        var pos = evex.len;
        if (pos >= bytes.len) return null;
        const opcode = bytes[pos];
        pos += 1;
        const evex_modrm = decodeEvexModRm(bytes, &pos, evex, 4) orelse return null;
        var decoded = evex_modrm.decoded;
        decoded.size = .bits64;
        decoded.len = @intCast(pos);
        decoded.vector_256 = evex.vector_length == 1;
        decoded.vector_512 = evex.vector_length == 2;
        decoded.opmask = evex.opmask;
        decoded.zero_mask = evex.z;
        decoded.evex_broadcast = evex.broadcast;
        decoded.is_evex = true;

        const dst = evexRegIndex(evex, evex_modrm.reg_code);
        const rm = evexRmIndex(evex, evex_modrm.rm_code);
        const vvvv = evexVIndex(evex);
        decoded.xmm_dst = dst;
        decoded.xmm_src = vvvv;
        decoded.xmm_src2 = if (evex_modrm.mod == 3) rm else 0;

        // The register form of the store opcode reverses the architectural
        // destination/source roles even though both forms use the same
        // ModR/M fields. Memory stores keep ModRM.reg as the source below.
        if (evex_modrm.mod == 3 and (opcode == 0x7F)) {
            decoded.xmm_dst = rm;
            decoded.xmm_src2 = dst;
        }

        // The EVEX register roles differ for a few families: VPMOVQD and
        // VEXTRACT* encode the source in ModRM.reg and the destination in
        // ModRM.r/m, while VPSLLD immediate uses vvvv as its destination.
        switch (evex.m) {
            1 => switch (opcode) {
                0x6F, 0x7F => {
                    if (evex.has_66_prefix) {
                        // VMOVDQA32/64 share this operation identity; W
                        // selects the element width used by masking.
                        decoded.evex_element_bytes = if (evex.w) 8 else 4;
                        decoded.op = if (opcode == 0x6F)
                            (if (evex_modrm.mod == 3) .vmovdqa_ymm_ymm else .vmovdqa_ymm_mem)
                        else
                            (if (evex_modrm.mod == 3) .vmovdqa_ymm_ymm else .vmovdqa_mem_ymm);
                    } else if (evex.has_f3_prefix) {
                        // VMOVDQU8 is W=0 and VMOVDQU64 is W=1.
                        decoded.evex_element_bytes = if (evex.w) 8 else 1;
                        decoded.op = if (opcode == 0x6F)
                            (if (evex_modrm.mod == 3) .vmovdqu_ymm_ymm else .vmovdqu_ymm_mem)
                        else
                            (if (evex_modrm.mod == 3) .vmovdqu_ymm_ymm else .vmovdqu_mem_ymm);
                    } else if (evex.has_f2_prefix and !evex.w) {
                        // VMOVDQU16.
                        decoded.evex_element_bytes = 2;
                        decoded.op = if (opcode == 0x6F)
                            (if (evex_modrm.mod == 3) .vmovdqu_ymm_ymm else .vmovdqu_ymm_mem)
                        else
                            (if (evex_modrm.mod == 3) .vmovdqu_ymm_ymm else .vmovdqu_mem_ymm);
                    } else if (!evex.has_66_prefix and !evex.has_f2_prefix and !evex.has_f3_prefix and !evex.w) {
                        decoded.evex_element_bytes = 4;
                        decoded.op = if (opcode == 0x6F)
                            (if (evex_modrm.mod == 3) .vmovups_ymm_ymm else .vmovups_ymm_mem)
                        else
                            (if (evex_modrm.mod == 3) .vmovups_ymm_ymm else .vmovups_mem_ymm);
                    } else return null;
                },
                0x70 => {
                    if (evex.w or (!evex.has_66_prefix and !evex.has_f2_prefix and !evex.has_f3_prefix)) return null;
                    if (pos >= bytes.len) return null;
                    decoded.op = if (evex.has_f2_prefix) .vpshuflw else if (evex.has_f3_prefix) .vpshufhw else .vpshufd;
                    decoded.evex_element_bytes = if (evex.has_66_prefix) 4 else 2;
                    decoded.xmm_src = rm;
                    decoded.xmm_src2 = 0;
                    decoded.imm = bytes[pos];
                    decoded.uses_imm = true;
                    pos += 1;
                },
                0x72 => {
                    if (!evex.has_66_prefix or evex.w or evex_modrm.reg_code != 6) return null;
                    if (pos >= bytes.len) return null;
                    decoded.op = .vpslld;
                    decoded.xmm_dst = vvvv;
                    decoded.xmm_src = rm;
                    decoded.xmm_src2 = 0;
                    decoded.imm = bytes[pos];
                    decoded.uses_imm = true;
                    pos += 1;
                },
                0xEF => {
                    if (!evex.has_66_prefix or evex.w) return null;
                    decoded.op = .vpxor;
                },
                0xF6 => {
                    if (!evex.has_66_prefix or evex.w) return null;
                    decoded.op = .vpsadbw;
                },
                0xFE => {
                    if (!evex.has_66_prefix or evex.w) return null;
                    decoded.op = .vpaddd;
                },
                0x6E => {
                    if (!evex.has_66_prefix or evex.w or evex.vector_length != 0 or evex.vvvv != 0 or evex.v_prime) return null;
                    decoded.op = if (evex_modrm.mod == 3) .vmovd_xmm_reg32 else .vmovd_xmm_mem32;
                    decoded.xmm_dst = dst;
                    decoded.src_reg = @enumFromInt(rm);
                },
                0x7E => {
                    if (!evex.has_66_prefix or evex.w or evex.vector_length != 0 or evex.vvvv != 0 or evex.v_prime) return null;
                    decoded.op = if (evex_modrm.mod == 3) .vmovd_reg32_xmm else .vmovd_mem32_xmm;
                    decoded.xmm_src = dst;
                    decoded.dst_reg = @enumFromInt(rm);
                },
                else => return null,
            },
            2 => switch (opcode) {
                0x00 => {
                    if (!evex.has_66_prefix or evex.w) return null;
                    decoded.evex_element_bytes = 1;
                    decoded.op = .vpshufb;
                },
                0x04 => {
                    if (!evex.has_66_prefix or evex.w) return null;
                    decoded.op = .vpmaddubsw;
                },
                0x35 => {
                    // VPMOVQD: ModRM.reg is the source YMM/ZMM and
                    // ModRM.r/m is the XMM/YMM destination.
                    if (evex.has_66_prefix or evex.w or evex.vvvv != 0 or evex.v_prime) return null;
                    decoded.op = .vpmovqd;
                    decoded.xmm_src = dst;
                    decoded.xmm_dst = rm;
                },
                0x50 => {
                    if (!evex.has_66_prefix or evex.w) return null;
                    decoded.evex_element_bytes = 4;
                    decoded.op = .vpdpbusd;
                },
                0xF5 => {
                    if (!evex.has_66_prefix or evex.w) return null;
                    decoded.op = .vpmaddwd;
                },
                else => return null,
            },
            3 => switch (opcode) {
                0x39 => {
                    if (!evex.has_66_prefix or evex.w) return null;
                    decoded.op = .vextracti32x4;
                    decoded.xmm_src = dst;
                    decoded.xmm_dst = rm;
                    if (pos >= bytes.len) return null;
                    decoded.imm = bytes[pos];
                    decoded.uses_imm = true;
                    pos += 1;
                },
                0x3B => {
                    if (!evex.has_66_prefix or !evex.w) return null;
                    decoded.op = .vextracti64x4;
                    decoded.xmm_src = dst;
                    decoded.xmm_dst = rm;
                    if (pos >= bytes.len) return null;
                    decoded.imm = bytes[pos];
                    decoded.uses_imm = true;
                    pos += 1;
                },
                0x3F => {
                    if (evex.w or !evex.has_66_prefix) return null;
                    if (pos >= bytes.len) return null;
                    decoded.op = .vpcmpb;
                    decoded.dst_k = evex_modrm.reg_code;
                    decoded.xmm_src = vvvv;
                    decoded.xmm_src2 = rm;
                    decoded.imm = bytes[pos];
                    decoded.uses_imm = true;
                    pos += 1;
                },
                else => return null,
            },
            else => return null,
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    const vex = decodeVexPrefix(bytes) orelse return null;
    var pos = vex.len;
    if (pos >= bytes.len) return null;

    const opcode = bytes[pos];
    pos += 1;

    // BMI1/BMI2 use the VEX prefix as a three-operand GPR encoding. They do
    // not go through the vector ModR/M helper below: doing so would discard
    // the GPR meaning of ModRM.reg/rm and, for memory operands, the SIB
    // fields. Keep this path before the SIMD table dispatch so the helper is
    // also usable by the production C4 decoder below.
    if (decodeVexGprInstruction(bytes, pos, vex, opcode)) |decoded| return decoded;
    if (decodeVexMaskMove(bytes, pos, vex, opcode)) |decoded| return decoded;

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
        0xAE => {
            // VLDMXCSR/VSTMXCSR: VEX.128.0F.WIG AE /2 and /3. Unlike most
            // VEX instructions these use the ModR/M reg field as an opcode
            // extension, not as a vector destination. Keep them in the
            // unified ISA decoder so generated Xenia code doesn't depend on
            // an external VEX-to-NEON diagnostic shim.
            const group = modrm_decoded.dst_xmm & 7;
            if (vex.l or vex.vvvv != 0 or vex.has_66_prefix or vex.has_f2_prefix or
                vex.has_f3_prefix or modrm_decoded.is_reg_form or
                (group != 2 and group != 3))
            {
                return null;
            }
            return .{
                .op = if (group == 2) .ldmxcsr_mem32 else .stmxcsr_mem32,
                .size = .bits32,
                .len = @intCast(pos),
                .addr = modrm_decoded.addr,
                .is_reg_form = false,
            };
        },
        // Packed saturating/min-max/multiply-high operations use the
        // mandatory 66 prefix and the ordinary VEX.NDS operand layout.
        0xD9, 0xDA, 0xDE, 0xE4, 0xE5, 0xE8, 0xE9, 0xEC, 0xED => {
            if (!vex.has_66_prefix) return null;
            const op: Op = switch (opcode) {
                0xD9 => .vpsubusw,
                0xDA => .vpminub,
                0xDE => .vpmaxub,
                0xE4 => .vpmulhuw,
                0xE5 => .vpmulhw,
                0xE8 => .vpsubsb,
                0xE9 => .vpsubsw,
                0xEC => .vpaddsb,
                0xED => .vpaddsw,
                else => unreachable,
            };
            return decodeVexPackedBinaryReturn(vex, pos, op, modrm_decoded);
        },
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
        0x2B => {
            // VMOVNTPS is the 256-bit VEX non-temporal store form.
            if (vex.has_66_prefix or vex.has_f2_prefix or vex.has_f3_prefix or
                !vex.l or vex.w)
            {
                return null;
            }
            return decodeVexNonTemporalStore(vex, pos, .vmovntps, modrm_decoded);
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
                .op = if (vex.has_f3_prefix) .vrsqrtss else .vrsqrtps,
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
                .op = if (vex.has_f3_prefix) .vrcpss else .vrcpps,
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
            const op_sel = arith(vex, .{ .vcvttps2dq, .vcvtdq2ps, .vcvtps2dq, .vcvtdq2ps });
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
            return decodeVexPackedBinaryReturn(vex, pos, if (vex.has_66_prefix) .vpacksswb else return null, modrm_decoded);
        },
        0x64 => {
            // VPCMPGTB (VEX.66.0F 64 /r) — packed signed greater-than, bytes
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpcmpgtb else return null, modrm_decoded);
        },
        0x65 => {
            // VPCMPGTW (VEX.66.0F 65 /r) — packed signed greater-than, words
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpcmpgtw else return null, modrm_decoded);
        },
        0x66 => {
            // VPCMPGTD (VEX.66.0F 66 /r) — packed signed greater-than, dwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpcmpgtd else return null, modrm_decoded);
        },
        0x67 => {
            // VPACKUSWB (VEX.66.0F 67 /r) — pack with unsigned saturation
            return decodeVexPackedBinaryReturn(vex, pos, if (vex.has_66_prefix) .vpackuswb else return null, modrm_decoded);
        },
        0x6B => {
            // VPACKSSDW (VEX.66.0F 6B /r) — pack signed dwords to words
            return decodeVexPackedBinaryReturn(vex, pos, if (vex.has_66_prefix) .vpackssdw else return null, modrm_decoded);
        },
        0x68 => {
            // VPUNPCKHBW (VEX.66.0F 68 /r) — unpack high bytes
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhbw else return null, modrm_decoded);
        },
        0x69 => {
            // VPUNPCKHWD (VEX.66.0F 69 /r) — unpack high words
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhwd else return null, modrm_decoded);
        },
        0x6A => {
            // VPUNPCKHDQ (VEX.66.0F 6A /r) — unpack high dwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhdq else return null, modrm_decoded);
        },
        0x6C => {
            // VPUNPCKLQDQ (VEX.66.0F 6C /r) — unpack low qwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpcklqdq else return null, modrm_decoded);
        },
        0x6D => {
            // VPUNPCKHQDQ (VEX.66.0F 6D /r) — unpack high qwords
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
            // VPSHUFD (VEX.66.0F 70 /r ib), VPSHUFLW (VEX.F2.0F 70
            // /r ib), and VPSHUFHW (VEX.F3.0F 70 /r ib). VEX.vvvv is
            // reserved for all three unary shuffle forms.
            if (vex.vvvv != 0 or (!vex.has_66_prefix and !vex.has_f2_prefix and !vex.has_f3_prefix)) return null;
            if (pos >= bytes.len) return null;
            const imm = bytes[pos];
            pos += 1;
            return .{
                .op = if (vex.has_f2_prefix) .vpshuflw else if (vex.has_f3_prefix) .vpshufhw else .vpshufd,
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
        0xC6 => {
            // VSHUFPS is the unprefixed form; VSHUFPD uses mandatory 66.
            if (pos >= bytes.len) return null;
            const imm = bytes[pos];
            pos += 1;
            if (vex.has_66_prefix) return decodeVexNdsImm(vex, pos, .vshufpd, modrm_decoded, imm);
            if (vex.has_f2_prefix or vex.has_f3_prefix) return null;
            return .{
                .op = .vshufps,
                .size = .bits64,
                .len = @intCast(pos),
                .xmm_dst = modrm_decoded.dst_xmm,
                .xmm_src = vex.vvvv,
                .xmm_src2 = modrm_decoded.src_xmm,
                .imm = imm,
                .uses_imm = true,
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
                    .xmm_dst = if (modrm_decoded.is_reg_form) modrm_decoded.src_xmm else modrm_decoded.dst_xmm,
                    .xmm_src = if (modrm_decoded.is_reg_form) modrm_decoded.dst_xmm else modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else if (vex.has_f3_prefix or vex.has_f2_prefix) {
                return .{
                    .op = if (modrm_decoded.is_reg_form) .vmovdqu_xmm_xmm else .vmovdqu_mem_xmm,
                    .size = .bits64,
                    .len = @intCast(pos),
                    .xmm_dst = if (modrm_decoded.is_reg_form) modrm_decoded.src_xmm else modrm_decoded.dst_xmm,
                    .xmm_src = if (modrm_decoded.is_reg_form) modrm_decoded.dst_xmm else modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else {
                return null;
            }
        },
        0xE6 => {
            // VCVTDQ2PD uses F3; VCVTTPD2DQ uses 66. Both are unary with the
            // source in ModRM.r/m and have no VEX.vvvv source operand.
            if (vex.vvvv != 0 or vex.has_f2_prefix or vex.has_f3_prefix == false and vex.has_66_prefix == false) return null;
            if (vex.has_f3_prefix) return decodeVexUnaryReturn(vex, pos, .vcvtdq2pd, modrm_decoded);
            if (vex.has_66_prefix) return decodeVexUnaryReturn(vex, pos, .vcvttpd2dq, modrm_decoded);
            return null;
        },
        0xE7 => {
            // VMOVNTDQ is the 256-bit VEX.66.0F E7 non-temporal store.
            if (!vex.has_66_prefix or vex.has_f2_prefix or vex.has_f3_prefix or
                !vex.l or vex.w)
            {
                return null;
            }
            return decodeVexNonTemporalStore(vex, pos, .vmovntdq, modrm_decoded);
        },
        0xEE => {
            // VPMAXSW (VEX.66.0F38 3D is VPMAXSD; the legacy map-1 EE form
            // is the signed word maximum.)
            return decodeVexPackedBinaryReturn(vex, pos, if (vex.has_66_prefix) .vpmaxsw else return null, modrm_decoded);
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
    // Most VEX arithmetic and packed-integer instructions are NDS forms:
    // VEX.vvvv is SRC1 and ModR/M.r/m is SRC2.  Loads, stores, scalar
    // conversions, and square-root/mask-extract families instead reserve
    // VEX.vvvv and use only ModR/M.r/m.  Keeping that distinction here makes
    // every caller's operand fields architecturally meaningful instead of
    // relying on the executor to guess which register was intended.
    const nds = switch (op_enum) {
        .vpshufb,
        .vphaddw,
        .vphaddd,
        .vphaddsw,
        .vphsubw,
        .vphsubd,
        .vphsubsw,
        .vpunpcklbw,
        .vpunpcklwd,
        .vpunpckldq,
        .vpunpckhbw,
        .vpunpckhwd,
        .vpunpckhdq,
        .vpunpcklqdq,
        .vpunpckhqdq,
        .vunpcklps,
        .vunpckhps,
        .vunpcklpd,
        .vunpckhpd,
        .vpcmpgtb,
        .vpcmpgtw,
        .vpcmpgtd,
        .vaddss,
        .vaddsd,
        .vaddps,
        .vaddpd,
        .vmulss,
        .vmulsd,
        .vmulps,
        .vmulpd,
        .vsubss,
        .vsubsd,
        .vsubps,
        .vsubpd,
        .vminss,
        .vminsd,
        .vminps,
        .vminpd,
        .vdivss,
        .vdivsd,
        .vdivps,
        .vdivpd,
        .vandps,
        .vandpd,
        .vandnps,
        .vandnpd,
        .vorps,
        .vorpd,
        .vxorps,
        .vxorpd,
        .vhaddps,
        .vhaddpd,
        .vhsubps,
        .vhsubpd,
        .vpsrlvw,
        .vpsravw,
        .vpsllvw,
        .vpsrlvd,
        .vpsravd,
        .vpsllvd,
        .vpermps,
        .vpblendvb,
        .vpblendw,
        .vfmaddsub132ps,
        .vfmaddsub132pd,
        .vfmsubadd132ps,
        .vfmsubadd132pd,
        .vfmadd132ps,
        .vfmadd132pd,
        .vfmsub132ps,
        .vfmsub132pd,
        .vfmaddsub213ps,
        .vfmaddsub213pd,
        .vfmsubadd213ps,
        .vfmsubadd213pd,
        .vfmadd213ps,
        .vfmadd213pd,
        .vfmsub213ps,
        .vfmsub213pd,
        .vfmaddsub231ps,
        .vfmaddsub231pd,
        .vfmsubadd231ps,
        .vfmsubadd231pd,
        .vfmadd231ps,
        .vfmadd231pd,
        .vfmsub231ps,
        .vfmsub231pd,
        => true,
        else => false,
    };
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = if (nds) vex.vvvv else modrm.src_xmm,
        .xmm_src2 = if (nds) modrm.src_xmm else 0,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
    };
}

/// Construct a normal NDS packed-integer VEX instruction. Unlike the older
/// generic return helper, this keeps VEX.vvvv as SRC1 and ModR/M.r/m as SRC2;
/// that distinction is observable for subtraction and saturating arithmetic.
fn decodeVexPackedBinaryReturn(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype) ?DecodedInsn {
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = vex.vvvv,
        .xmm_src2 = modrm.src_xmm,
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

/// Decode the scalar source of VPINSRB/VPINSRW/VPINSRD/VPINSRQ.  These are
/// NDS instructions, but their ModR/M.r/m operand is a GPR or scalar memory
/// value rather than a vector.  Keeping the scalar register in `src_reg`
/// prevents the executor from accidentally reading an XMM register with the
/// same numeric index.
fn decodeVexInsertElementReturn(
    vex: VexPrefix,
    pos: usize,
    op_enum: Op,
    modrm: anytype,
    imm: u8,
    size: Size,
) ?DecodedInsn {
    if (!vex.has_66_prefix or vex.l) return null;
    const decoded = DecodedInsn{
        .op = if (op_enum == .vpinsrb_xmm_xmm_reg32 and !modrm.is_reg_form)
            .vpinsrb_xmm_xmm_mem8
        else
            op_enum,
        .size = size,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = vex.vvvv,
        .xmm_src2 = if (modrm.is_reg_form) modrm.src_xmm else 0,
        .src_reg = if (modrm.is_reg_form) @enumFromInt(modrm.src_xmm) else .al_ax_eax_rax,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .uses_imm = true,
        .imm = imm,
    };
    return decoded;
}

/// Decode VINSERTPS.  Its first vector source is VEX.vvvv and its second
/// source is ModR/M.r/m; the latter is either an XMM register or one scalar
/// f32 in memory.
fn decodeVexInsertPsReturn(vex: VexPrefix, pos: usize, modrm: anytype, imm: u8) ?DecodedInsn {
    if (!vex.has_66_prefix or vex.l or vex.w) return null;
    return .{
        .op = .vinsertps,
        .size = .bits32,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = vex.vvvv,
        .xmm_src2 = if (modrm.is_reg_form) modrm.src_xmm else 0,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .uses_imm = true,
        .imm = imm,
    };
}

/// Decode VPEXTRB/VPEXTRW/VPEXTRD/VPEXTRQ.  These write ModR/M.r/m, which
/// may be a GPR or memory, and read the vector from ModR/M.reg.
fn decodeVexExtractElementReturn(
    vex: VexPrefix,
    pos: usize,
    op_enum: Op,
    modrm: anytype,
    imm: u8,
    size: Size,
) ?DecodedInsn {
    if (!vex.has_66_prefix or vex.l or vex.vvvv != 0) return null;
    return .{
        .op = op_enum,
        .size = size,
        .len = @intCast(pos),
        .xmm_src = modrm.dst_xmm,
        .dst_reg = @enumFromInt(modrm.src_xmm),
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .uses_imm = true,
        .imm = imm,
    };
}

/// Construct the AVX masked vector memory forms. VMASKMOV uses VEX.vvvv as
/// the per-element mask source, while the ModR/M.reg operand is the vector
/// destination for a load or the vector data source for a store. The memory
/// operand is always ModR/M.r/m; register forms are #UD.
fn decodeVexVectorMaskMove(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype) ?DecodedInsn {
    if (vex.m != 2 or !vex.has_66_prefix or vex.w or modrm.is_reg_form) return null;
    return switch (op_enum) {
        .vmaskmovps_load, .vmaskmovpd_load => .{
            .op = op_enum,
            .size = .bits64,
            .len = @intCast(pos),
            .xmm_dst = modrm.dst_xmm,
            .xmm_src = vex.vvvv,
            .is_reg_form = false,
            .addr = modrm.addr,
            .vector_256 = vex.l,
        },
        .vmaskmovps_store, .vmaskmovpd_store => .{
            .op = op_enum,
            .size = .bits64,
            .len = @intCast(pos),
            .xmm_src = modrm.dst_xmm,
            .xmm_src2 = vex.vvvv,
            .is_reg_form = false,
            .addr = modrm.addr,
            .vector_256 = vex.l,
        },
        else => null,
    };
}

/// Construct a VEX NDS instruction with an immediate control byte. The VEX
/// encoding puts the first source in vvvv and the second source in ModRM.r/m;
/// keeping that order here is important for non-commutative and lane-select
/// operations.
fn decodeVexNdsImm(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype, imm: u8) ?DecodedInsn {
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = vex.vvvv,
        .xmm_src2 = modrm.src_xmm,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
        .uses_imm = true,
        .imm = imm,
    };
}

/// Construct a VEX unary vector operation. The ModRM.r/m operand is the only
/// source; unlike the NDS helper, vvvv is reserved and must not become a live
/// source register.
fn decodeVexUnaryReturn(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype) ?DecodedInsn {
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = modrm.src_xmm,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
    };
}

fn decodeVexUnaryImmReturn(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype, imm: u8) ?DecodedInsn {
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = modrm.src_xmm,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
        .uses_imm = true,
        .imm = imm,
    };
}

fn decodeVexBroadcastReturn(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype, size: Size) ?DecodedInsn {
    if (!vex.has_66_prefix or vex.w or vex.vvvv != 0) return null;
    return .{
        .op = op_enum,
        .size = size,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = modrm.src_xmm,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
    };
}

/// EXTRACTPS has the source in ModRM.reg and writes ModRM.r/m as either a
/// GPR or a 32-bit memory destination. It is not an ordinary vector result.
fn decodeVexExtractPsReturn(vex: VexPrefix, pos: usize, modrm: anytype, imm: u8) ?DecodedInsn {
    if (vex.l or !vex.has_66_prefix or vex.w or vex.vvvv != 0) return null;
    return .{
        .op = .vextractps,
        .size = .bits32,
        .len = @intCast(pos),
        .xmm_src = modrm.dst_xmm,
        .dst_reg = @enumFromInt(modrm.src_xmm),
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .uses_imm = true,
        .imm = imm,
    };
}

/// Non-temporal stores use ModRM.reg as the vector source and require a
/// memory ModRM.r/m operand. A separate helper prevents the generic VEX return
/// shape from accidentally treating the destination address as a vector.
fn decodeVexNonTemporalStore(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype) ?DecodedInsn {
    if (modrm.is_reg_form) return null;
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_src = modrm.dst_xmm,
        .is_reg_form = false,
        .addr = modrm.addr,
        .vector_256 = vex.l,
    };
}

fn decodeVexNonTemporalLoad(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype) ?DecodedInsn {
    if (modrm.is_reg_form) return null;
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .is_reg_form = false,
        .addr = modrm.addr,
        .vector_256 = vex.l,
    };
}

fn decodeVexStringCompare(vex: VexPrefix, pos: usize, modrm: anytype, imm: u8) ?DecodedInsn {
    if (vex.l or !vex.has_66_prefix or vex.w or vex.vvvv != 0) return null;
    return .{
        .op = .vpcmpistri,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_src = modrm.dst_xmm,
        .xmm_src2 = modrm.src_xmm,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .uses_imm = true,
        .imm = imm,
    };
}

fn decodeVex3Nds(bytes: []const u8, start_pos: usize, vex: VexPrefix, op: Op, with_imm: bool) ?DecodedInsn {
    if (start_pos + 4 > bytes.len) return null;
    var decoded = DecodedInsn{ .op = op, .vector_256 = vex.l };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, .bits64);
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.xmm_src = vex.vvvv;
    if (decoded.is_reg_form) {
        decoded.xmm_src2 = @intCast(rm.addr);
    } else {
        decoded.addr = rm.addr;
    }
    if (with_imm) {
        if (pos >= bytes.len) return null;
        decoded.imm = bytes[pos];
        decoded.uses_imm = true;
        pos += 1;
    }
    decoded.len = @intCast(pos);
    return decoded;
}

/// Decode the production three-byte VEX form of VMASKMOV. The generic map-38
/// decoder already has a parsed ModR/M shape, but decodeVex3 has its own
/// hot-path tables, so keep this small form-specific constructor beside the
/// other production helpers.
fn decodeVex3MaskMove(bytes: []const u8, start_pos: usize, vex: VexPrefix, op: Op) ?DecodedInsn {
    if (start_pos + 4 > bytes.len or vex.m != 2 or !vex.has_66_prefix or vex.w) return null;
    var decoded = DecodedInsn{ .op = op, .vector_256 = vex.l, .is_reg_form = false };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, .bits64);
    if (decoded.is_reg_form) return null;
    decoded.addr = rm.addr;
    switch (op) {
        .vmaskmovps_load, .vmaskmovpd_load => {
            decoded.xmm_dst = @intFromEnum(rm.reg);
            decoded.xmm_src = vex.vvvv;
        },
        .vmaskmovps_store, .vmaskmovpd_store => {
            decoded.xmm_src = @intFromEnum(rm.reg);
            decoded.xmm_src2 = vex.vvvv;
        },
        else => return null,
    }
    decoded.len = @intCast(pos);
    return decoded;
}

fn decodeVex3Unary(bytes: []const u8, start_pos: usize, vex: VexPrefix, op: Op, with_imm: bool) ?DecodedInsn {
    if (start_pos + 4 > bytes.len) return null;
    var decoded = DecodedInsn{ .op = op, .vector_256 = vex.l };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, .bits64);
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.xmm_src = if (decoded.is_reg_form) @intCast(rm.addr) else 0;
    decoded.addr = rm.addr;
    if (with_imm) {
        if (pos >= bytes.len) return null;
        decoded.imm = bytes[pos];
        decoded.uses_imm = true;
        pos += 1;
    }
    decoded.len = @intCast(pos);
    return decoded;
}

fn decodeVex3Broadcast(bytes: []const u8, start_pos: usize, vex: VexPrefix, op: Op, size: Size) ?DecodedInsn {
    if (start_pos + 4 > bytes.len) return null;
    var decoded = DecodedInsn{ .op = op, .size = size, .vector_256 = vex.l };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, .bits64);
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.xmm_src = if (decoded.is_reg_form) @intCast(rm.addr) else 0;
    decoded.addr = rm.addr;
    decoded.len = @intCast(pos);
    return decoded;
}

fn decodeVex3Store(bytes: []const u8, start_pos: usize, vex: VexPrefix, op: Op) ?DecodedInsn {
    if (start_pos + 4 > bytes.len) return null;
    var decoded = DecodedInsn{ .op = op, .vector_256 = vex.l };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, .bits64);
    if (decoded.is_reg_form) return null;
    decoded.xmm_src = @intFromEnum(rm.reg);
    decoded.addr = rm.addr;
    decoded.len = @intCast(pos);
    return decoded;
}

fn decodeVex3Load(bytes: []const u8, start_pos: usize, vex: VexPrefix, op: Op) ?DecodedInsn {
    if (start_pos + 4 > bytes.len) return null;
    var decoded = DecodedInsn{ .op = op, .vector_256 = vex.l };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, .bits64);
    if (decoded.is_reg_form) return null;
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.addr = rm.addr;
    decoded.len = @intCast(pos);
    return decoded;
}

fn decodeVex3ExtractPs(bytes: []const u8, start_pos: usize, vex: VexPrefix) ?DecodedInsn {
    if (start_pos + 4 > bytes.len or vex.l or vex.w or !vex.has_66_prefix or vex.vvvv != 0) return null;
    var decoded = DecodedInsn{ .op = .vextractps, .size = .bits32 };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, .bits32);
    decoded.xmm_src = @intFromEnum(rm.reg);
    decoded.dst_reg = @enumFromInt(@as(u8, @truncate(rm.addr)));
    decoded.addr = rm.addr;
    if (pos >= bytes.len) return null;
    decoded.imm = bytes[pos];
    decoded.uses_imm = true;
    pos += 1;
    decoded.len = @intCast(pos);
    return decoded;
}

fn decodeVex3InsertElement(
    bytes: []const u8,
    start_pos: usize,
    vex: VexPrefix,
    op: Op,
    size: Size,
) ?DecodedInsn {
    if (start_pos + 4 > bytes.len or vex.l or !vex.has_66_prefix) return null;
    var decoded = DecodedInsn{ .op = op, .size = size };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, size);
    if (op == .vpinsrb_xmm_xmm_reg32 and !decoded.is_reg_form) decoded.op = .vpinsrb_xmm_xmm_mem8;
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.xmm_src = vex.vvvv;
    if (decoded.is_reg_form) {
        decoded.src_reg = @enumFromInt(rm.addr);
    } else {
        decoded.addr = rm.addr;
    }
    if (pos >= bytes.len) return null;
    decoded.imm = bytes[pos];
    decoded.uses_imm = true;
    pos += 1;
    decoded.len = @intCast(pos);
    return decoded;
}

fn decodeVex3ExtractElement(
    bytes: []const u8,
    start_pos: usize,
    vex: VexPrefix,
    op: Op,
    size: Size,
) ?DecodedInsn {
    if (start_pos + 4 > bytes.len or vex.l or !vex.has_66_prefix or vex.vvvv != 0) return null;
    var decoded = DecodedInsn{ .op = op, .size = size };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, size);
    decoded.xmm_src = @intFromEnum(rm.reg);
    if (decoded.is_reg_form) decoded.dst_reg = @enumFromInt(rm.addr);
    decoded.addr = rm.addr;
    if (pos >= bytes.len) return null;
    decoded.imm = bytes[pos];
    decoded.uses_imm = true;
    pos += 1;
    decoded.len = @intCast(pos);
    return decoded;
}

fn decodeVex3InsertPs(bytes: []const u8, start_pos: usize, vex: VexPrefix) ?DecodedInsn {
    if (start_pos + 4 > bytes.len or vex.l or !vex.has_66_prefix or vex.w) return null;
    var decoded = DecodedInsn{ .op = .vinsertps, .size = .bits32 };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, .bits32);
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.xmm_src = vex.vvvv;
    if (decoded.is_reg_form) {
        decoded.xmm_src2 = @intCast(rm.addr);
    } else {
        decoded.addr = rm.addr;
    }
    if (pos >= bytes.len) return null;
    decoded.imm = bytes[pos];
    decoded.uses_imm = true;
    pos += 1;
    decoded.len = @intCast(pos);
    return decoded;
}

fn decodeVex3String(bytes: []const u8, start_pos: usize, vex: VexPrefix) ?DecodedInsn {
    if (start_pos + 4 > bytes.len or vex.l or vex.w or !vex.has_66_prefix or vex.vvvv != 0) return null;
    var decoded = DecodedInsn{ .op = .vpcmpistri, .size = .bits64 };
    var pos = start_pos + 4;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, .bits64);
    decoded.xmm_src = @intFromEnum(rm.reg);
    decoded.xmm_src2 = if (decoded.is_reg_form) @intCast(rm.addr) else 0;
    decoded.addr = rm.addr;
    if (pos >= bytes.len) return null;
    decoded.imm = bytes[pos];
    decoded.uses_imm = true;
    pos += 1;
    decoded.len = @intCast(pos);
    return decoded;
}

/// Decode the AVX 128-bit lane insertion/extraction pair. These instructions
/// use the ModR/M fields in the opposite direction from the generic
/// three-operand helper: VEXTRACT* takes its source from ModRM.reg and writes
/// ModRM.r/m, while VINSERT* writes ModRM.reg and reads ModRM.r/m plus
/// VEX.vvvv. Keeping this explicit prevents a valid instruction from being
/// decoded with swapped source and destination vectors.
fn decodeVexLane128(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype, imm: u8) ?DecodedInsn {
    if (!vex.l or !vex.has_66_prefix or vex.w) return null;
    return switch (op_enum) {
        .vextractf128 => .{
            .op = op_enum,
            .size = .bits64,
            .len = @intCast(pos),
            .xmm_src = modrm.dst_xmm,
            .xmm_dst = if (modrm.is_reg_form) modrm.src_xmm else 0,
            .is_reg_form = modrm.is_reg_form,
            .addr = modrm.addr,
            .vector_256 = true,
            .uses_imm = true,
            .imm = imm,
        },
        .vinsertf128, .vinserti128 => .{
            .op = op_enum,
            .size = .bits64,
            .len = @intCast(pos),
            .xmm_dst = modrm.dst_xmm,
            .xmm_src = vex.vvvv,
            .xmm_src2 = if (modrm.is_reg_form) modrm.src_xmm else 0,
            .is_reg_form = modrm.is_reg_form,
            .addr = modrm.addr,
            .vector_256 = true,
            .uses_imm = true,
            .imm = imm,
        },
        else => null,
    };
}

/// Decode VPHMINPOSUW, whose VEX.vvvv field is reserved and whose source is
/// the ModR/M.r/m operand. It is not an NDS instruction, so the generic VEX
/// return helper would incorrectly use VEX.vvvv as SRC2.
fn decodeVexMinPositionReturn(vex: VexPrefix, pos: usize, modrm: anytype) ?DecodedInsn {
    if (vex.l or !vex.has_66_prefix or vex.vvvv != 0) return null;
    return .{
        .op = .vphminposuw,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = modrm.src_xmm,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = false,
    };
}

/// Decode VPERM2F128's two 256-bit source operands and immediate. The
/// instruction is four-operand at the architectural level: ModR/M.reg is the
/// destination, VEX.vvvv is SRC1, and ModR/M.r/m is SRC2.
fn decodeVexPermute2x128(vex: VexPrefix, pos: usize, modrm: anytype, imm: u8) ?DecodedInsn {
    if (!vex.l or !vex.has_66_prefix or vex.w) return null;
    return .{
        .op = .vperm2f128,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = vex.vvvv,
        .xmm_src2 = if (modrm.is_reg_form) modrm.src_xmm else 0,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = true,
        .uses_imm = true,
        .imm = imm,
    };
}

fn decodeVexVectorTestReturn(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype) ?DecodedInsn {
    // VTESTPS/VTESTPD are two-source instructions. Their VEX.vvvv field is
    // reserved and therefore decodes to zero (the encoded field is 1111b).
    if (!vex.has_66_prefix or vex.w or vex.vvvv != 0) return null;
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_src = modrm.dst_xmm,
        .xmm_src2 = modrm.src_xmm,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
    };
}

fn decodeVexDotProductReturn(vex: VexPrefix, pos: usize, modrm: anytype) ?DecodedInsn {
    if (!vex.has_66_prefix or vex.w) return null;
    return .{
        .op = .vpdpbusd,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = vex.vvvv,
        .xmm_src2 = modrm.src_xmm,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
    };
}

/// Decode VEX-encoded transfers between GPR/memory and the opmask register
/// file. These use legacy VEX encodings (C5/C4) even though they operate on
/// AVX-512 k registers.
fn decodeVexMaskMove(
    bytes: []const u8,
    modrm_pos: usize,
    vex: VexPrefix,
    opcode: u8,
) ?DecodedInsn {
    if (vex.m != 1 or vex.l or vex.vvvv != 0) return null;
    if (opcode != 0x90 and opcode != 0x91 and opcode != 0x92 and opcode != 0x93) return null;

    if (modrm_pos >= bytes.len) return null;
    const modrm = bytes[modrm_pos];
    const mod: u2 = @truncate(modrm >> 6);

    // 90/91 are the memory forms. The mandatory-prefix/W combinations are
    // intentionally different from the GPR forms: KMOVW uses pp=00/W0,
    // KMOVD uses pp=66/W1, and KMOVQ uses pp=00/W1.
    const is_memory_form = opcode == 0x90 or opcode == 0x91;
    const op: Op = if (is_memory_form) blk: {
        if (mod == 3) return null;
        if (vex.has_f2_prefix or vex.has_f3_prefix) return null;
        if (vex.has_66_prefix) {
            if (!vex.w) return null;
            break :blk .kmovd;
        }
        break :blk if (vex.w) .kmovq else .kmovw;
    } else blk: {
        // 92/93 are the GPR forms and require a register ModR/M operand.
        if (mod != 3) return null;
        if (vex.has_66_prefix or vex.has_f3_prefix) return null;
        if (vex.has_f2_prefix) break :blk if (vex.w) .kmovq else .kmovd;
        if (!vex.w) break :blk .kmovw;
        return null;
    };
    const size: OperandSize = switch (op) {
        // The KMOVW GPR operand is architecturally a 32-bit register with
        // only its low 16 bits transferred to/from the k register.
        .kmovw, .kmovd => .bits32,
        .kmovq => .bits64,
        else => unreachable,
    };
    var decoded = DecodedInsn{ .op = op, .size = size };
    var pos = modrm_pos;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, size);
    const reg_code: u3 = @truncate(modrm >> 3);
    const rm_mask: u3 = @truncate(modrm);
    if (opcode == 0x90 or opcode == 0x92) {
        // KMOV{k} k1, r/m{16,32,64}.
        decoded.dst_k = reg_code;
        if (decoded.is_reg_form) {
            decoded.src_reg = if (opcode == 0x92) @enumFromInt(rm.addr) else unreachable;
        } else {
            decoded.addr = rm.addr;
        }
    } else if (opcode == 0x91) {
        // KMOV{k} m{16,32,64}, k1.
        decoded.src_k = reg_code;
        decoded.mask_to_gpr = true;
        decoded.addr = rm.addr;
    } else {
        // KMOV{k} r32/r64, k1. In this form the k register is ModR/M.r/m,
        // while the GPR destination is ModR/M.reg.
        decoded.src_k = rm_mask;
        decoded.mask_to_gpr = true;
        decoded.dst_reg = rm.reg;
    }
    decoded.len = @intCast(pos);
    return decoded;
}

/// Decode the VEX-encoded BMI1/BMI2 GPR family. VEX.R/X/B are inverted in
/// the encoding but are already represented in `VexPrefix` as the effective
/// extension bits. VEX.vvvv is likewise already complemented back to the
/// architectural register number.
fn decodeVexGprInstruction(
    bytes: []const u8,
    modrm_pos: usize,
    vex: VexPrefix,
    opcode: u8,
) ?DecodedInsn {
    if (vex.l) return null; // All of these instructions require VEX.L=0.

    const op: Op = switch (vex.m) {
        2 => switch (opcode) {
            // ANDN's mandatory F2 byte is the opcode itself (0F 38 F2), not
            // the legacy F2 prefix carried by the VEX.pp field.
            0xF2 => if (!vex.has_f2_prefix and !vex.has_66_prefix and !vex.has_f3_prefix) .andn else return null,
            0xF5 => if (!vex.has_f2_prefix and !vex.has_f3_prefix and !vex.has_66_prefix) .bzhi else return null,
            0xF6 => if (vex.has_f2_prefix and !vex.has_66_prefix and !vex.has_f3_prefix) .mulx else return null,
            0xF7 => if (vex.has_66_prefix)
                .shlx
            else if (vex.has_f2_prefix)
                .shrx
            else if (vex.has_f3_prefix)
                .sarx
            else
                return null,
            else => return null,
        },
        3 => if (opcode == 0xF0 and vex.has_f2_prefix and !vex.has_66_prefix and !vex.has_f3_prefix)
            .rorx
        else
            return null,
        else => return null,
    };

    // RORX is the only member whose VEX.vvvv field is reserved. A decoded
    // value of zero means the encoded field was 1111b.
    if (op == .rorx and vex.vvvv != 0) return null;
    if (op != .rorx and vex.vvvv == 0xF) return null;
    if (modrm_pos >= bytes.len) return null;

    const size: OperandSize = if (vex.w) .bits64 else .bits32;
    var decoded = DecodedInsn{
        .op = op,
        .size = size,
        .dst_size = size,
    };
    var pos = modrm_pos;
    const rm = readModRM(&decoded, bytes, &pos, vex.r, vex.x, vex.b, size);
    decoded.dst_reg = rm.reg;

    if (decoded.is_reg_form) {
        decoded.src_reg = @enumFromInt(@as(u4, @truncate(rm.addr)));
    } else {
        decoded.addr = rm.addr;
    }

    switch (op) {
        .andn, .bzhi, .shlx, .shrx, .sarx => {
            decoded.src_reg2 = @enumFromInt(vex.vvvv);
        },
        .mulx => {
            decoded.dst_reg2 = @enumFromInt(vex.vvvv);
        },
        .rorx => {
            if (pos >= bytes.len) return null;
            decoded.uses_imm = true;
            decoded.imm = bytes[pos];
            pos += 1;
        },
        else => unreachable,
    }

    decoded.len = @intCast(pos);
    return decoded;
}

/// Decode VEX opcode map 0x38 (VEX.0F38).
/// Handles SSSE3/AVX2 3-operand integer SIMD instructions.
fn decodeVexMap38(vex: VexPrefix, pos: usize, opcode: u8, modrm: anytype) ?DecodedInsn {
    // VEX opcode map 0x38 uses the 0F 38 two-byte opcode prefix.
    // Dispatch by the third opcode byte:
    return switch (opcode) {
        0x00...0x07 => {
            // VPSHUFB (0x00), VPHADDW/D/SW (0x01-0x03),
            // VPMADDUBSW (0x04), VPHSUBW/D/SW (0x05-0x07).
            return switch (opcode) {
                0x00 => decodeVexReturn(vex, pos, .vpshufb, modrm),
                0x01 => decodeVexReturn(vex, pos, .vphaddw, modrm),
                0x02 => decodeVexReturn(vex, pos, .vphaddd, modrm),
                0x03 => decodeVexReturn(vex, pos, .vphaddsw, modrm),
                0x04 => decodeVexPackedBinaryReturn(vex, pos, .vpmaddubsw, modrm),
                0x05 => decodeVexReturn(vex, pos, .vphsubw, modrm),
                0x06 => decodeVexReturn(vex, pos, .vphsubd, modrm),
                0x07 => decodeVexReturn(vex, pos, .vphsubsw, modrm),
                else => null,
            };
        },
        0x0C => decodeVexPackedBinaryReturn(vex, pos, .vpermilps, modrm),
        0x08...0x0A => {
            // VPSIGNB/W/D (VEX.0F38 08/09/0A)
            return switch (opcode) {
                0x08 => decodeVexPackedBinaryReturn(vex, pos, .vpsignb, modrm),
                0x09 => decodeVexPackedBinaryReturn(vex, pos, .vpsignw, modrm),
                0x0A => decodeVexPackedBinaryReturn(vex, pos, .vpsignd, modrm),
                else => null,
            };
        },
        0x0E => decodeVexVectorTestReturn(vex, pos, .vtestps, modrm),
        0x0F => decodeVexVectorTestReturn(vex, pos, .vtestpd, modrm),
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
                0x1C => decodeVexUnaryReturn(vex, pos, .vpabsb, modrm),
                0x1D => decodeVexUnaryReturn(vex, pos, .vpabsw, modrm),
                0x1E => decodeVexUnaryReturn(vex, pos, .vpabsd, modrm),
                else => null,
            };
        },
        0x20...0x25 => {
            // PMOVSX variants: VEX.0F38 20-25
            return switch (opcode) {
                0x20 => decodeVexUnaryReturn(vex, pos, .vpmovsxbw, modrm),
                0x21 => decodeVexUnaryReturn(vex, pos, .vpmovsxbd, modrm),
                0x22 => decodeVexUnaryReturn(vex, pos, .vpmovsxbq, modrm),
                0x23 => decodeVexUnaryReturn(vex, pos, .vpmovsxwd, modrm),
                0x24 => decodeVexUnaryReturn(vex, pos, .vpmovsxwq, modrm),
                0x25 => decodeVexUnaryReturn(vex, pos, .vpmovsxdq, modrm),
                else => null,
            };
        },
        0x28 => decodeVexPackedBinaryReturn(vex, pos, .vpmuldq, modrm),
        0x29 => decodeVexPackedBinaryReturn(vex, pos, .vpcmpeqq, modrm),
        0x2A => decodeVexNonTemporalLoad(vex, pos, .vmovntdqa, modrm), // VMOVNTDQA
        0x2C => decodeVexVectorMaskMove(vex, pos, .vmaskmovps_load, modrm),
        0x2D => decodeVexVectorMaskMove(vex, pos, .vmaskmovpd_load, modrm),
        0x2E => decodeVexVectorMaskMove(vex, pos, .vmaskmovps_store, modrm),
        0x2F => decodeVexVectorMaskMove(vex, pos, .vmaskmovpd_store, modrm),
        0x2B => decodeVexPackedBinaryReturn(vex, pos, .vpackusdw, modrm),
        0x30 => decodeVexUnaryReturn(vex, pos, .vpmovzxbw, modrm),
        0x31 => decodeVexUnaryReturn(vex, pos, .vpmovzxbd, modrm),
        0x32 => decodeVexUnaryReturn(vex, pos, .vpmovzxbq, modrm),
        0x33 => decodeVexUnaryReturn(vex, pos, .vpmovzxwd, modrm),
        0x34 => decodeVexUnaryReturn(vex, pos, .vpmovzxwq, modrm),
        0x35 => decodeVexUnaryReturn(vex, pos, .vpmovzxdq, modrm),
        0x36 => decodeVexPackedBinaryReturn(vex, pos, .vpermd, modrm),
        0x16 => decodeVexReturn(vex, pos, .vpermps, modrm), // VPERMPS (VEX.256.66.0F38.W0 16)
        0x37 => decodeVexPackedBinaryReturn(vex, pos, .vpcmpgtq, modrm),
        0x38 => decodeVexPackedBinaryReturn(vex, pos, .vpminsb, modrm),
        0x39 => decodeVexPackedBinaryReturn(vex, pos, .vpminsd, modrm),
        0x3A => decodeVexPackedBinaryReturn(vex, pos, .vpminuw, modrm),
        0x3B => decodeVexPackedBinaryReturn(vex, pos, .vpminud, modrm),
        0x3C => decodeVexPackedBinaryReturn(vex, pos, .vpmaxsb, modrm),
        0x3D => decodeVexPackedBinaryReturn(vex, pos, .vpmaxsd, modrm),
        0x3E => decodeVexPackedBinaryReturn(vex, pos, .vpmaxuw, modrm),
        0x3F => decodeVexPackedBinaryReturn(vex, pos, .vpmaxud, modrm),
        0x40 => decodeVexPackedBinaryReturn(vex, pos, .vpmulld_38, modrm),
        0x41 => decodeVexMinPositionReturn(vex, pos, modrm),
        0x42 => decodeVexPackedBinaryReturn(vex, pos, .vpsadbw, modrm),
        0x45 => decodeVexReturn(vex, pos, .vpsrlvd, modrm),
        0x46 => decodeVexReturn(vex, pos, .vpsravd, modrm),
        0x47 => decodeVexReturn(vex, pos, .vpsllvd, modrm),
        0x4C => decodeVexReturn(vex, pos, .vpblendvb, modrm),
        0x4D => decodeVexReturn(vex, pos, .vpblendw, modrm), // VEX.0F3A 0E fallback
        0x50 => decodeVexDotProductReturn(vex, pos, modrm),
        0x58 => decodeVexBroadcastReturn(vex, pos, .vpbroadcastd, modrm, .bits32),
        0x59 => decodeVexBroadcastReturn(vex, pos, .vpbroadcastq, modrm, .bits64),
        0x79 => decodeVexBroadcastReturn(vex, pos, .vpbroadcastw, modrm, .bits16),
        0xF5 => decodeVexPackedBinaryReturn(vex, pos, .vpmaddwd, modrm),
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
        0x04 => if (vex.has_66_prefix and !vex.w and vex.vvvv == 0)
            decodeVexUnaryImmReturn(vex, pos, .vpermilps, modrm, imm)
        else
            null, // VPERMILPS immediate form
        0x08 => if (vex.has_66_prefix and !vex.w and vex.vvvv == 0)
            decodeVexUnaryImmReturn(vex, pos, .vroundps, modrm, imm)
        else
            null, // VROUNDPS
        0x09 => if (vex.has_66_prefix and !vex.w and vex.vvvv == 0)
            decodeVexUnaryImmReturn(vex, pos, .vroundpd, modrm, imm)
        else
            null, // VROUNDPD
        0x0A => decodeVexNdsImm(vex, pos, .vroundss, modrm, imm), // VROUNDSS (VEX.128.66.0F3A.W0 0A)
        0x0B => decodeVexNdsImm(vex, pos, .vroundsd, modrm, imm), // VROUNDSD (VEX.128.66.0F3A.W0 0B)
        0x0C => if (vex.has_66_prefix and !vex.w) decodeVexNdsImm(vex, pos, .vblendps, modrm, imm) else null, // VBLENDPS
        0x0E => decodeVexNdsImm(vex, pos, .vpblendw, modrm, imm), // VPBLENDW
        // VPALIGNR is NDS: VEX.vvvv is the first source and ModR/M.r/m is
        // the second. Using decodeVexReturnImm here would silently swap them.
        0x0F => decodeVexNdsImm(vex, pos, .vpalignr, modrm, imm), // VPALIGNR
        0x14 => decodeVexExtractElementReturn(vex, pos, .vpextrb, modrm, imm, .bits8), // VPEXTRB
        0x15 => decodeVexExtractElementReturn(vex, pos, .vpextrw, modrm, imm, .bits16), // VPEXTRW
        0x16 => decodeVexExtractElementReturn(vex, pos, .vpextrd, modrm, imm, .bits32), // VPEXTRD
        0x17 => if (vex.w)
            decodeVexExtractElementReturn(vex, pos, .vpextrq, modrm, imm, .bits64)
        else
            decodeVexExtractPsReturn(vex, pos, modrm, imm), // VPEXTRQ / EXTRACTPS
        0x06 => decodeVexPermute2x128(vex, pos, modrm, imm), // VPERM2F128
        0x18 => decodeVexLane128(vex, pos, .vinsertf128, modrm, imm), // VINSERTF128
        0x19 => decodeVexLane128(vex, pos, .vextractf128, modrm, imm), // VEXTRACTF128
        0x1A => decodeVexReturnImm(vex, pos, .vbroadcastf128, modrm, imm), // VBROADCASTF128
        0x1B => decodeVexReturnImm(vex, pos, .vbroadcasti128, modrm, imm), // VBROADCASTI128
        0x20 => decodeVexInsertElementReturn(vex, pos, .vpinsrb_xmm_xmm_reg32, modrm, imm, .bits8), // VPINSRB
        0x21 => decodeVexInsertPsReturn(vex, pos, modrm, imm), // VEX.0F3A 21 = VINSERTPS
        0x38 => decodeVexLane128(vex, pos, .vinserti128, modrm, imm), // VINSERTI128
        // VEXTRACTI128 has the same bit-level lane operation as
        // VEXTRACTF128. Normalize it to the shared executor operation.
        0x39 => decodeVexLane128(vex, pos, .vextractf128, modrm, imm), // VEXTRACTI128
        0x25 => decodeVexReturnImm(vex, pos, .vpternlogd, modrm, imm), // VPTERNLOGD
        0x26 => decodeVexReturnImm(vex, pos, .vpternlogq, modrm, imm), // VPTERNLOGQ
        0x4A => decodeVexReturnImm(vex, pos, .valignd, modrm, imm), // VALIGND
        0x4B => decodeVexReturnImm(vex, pos, .valignq, modrm, imm), // VALIGNQ
        0x63 => decodeVexStringCompare(vex, pos, modrm, imm), // VPCMPISTRI
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
    const mask_vex = VexPrefix{
        .len = 2,
        .is_2byte = true,
        .has_66_prefix = prefix == 1,
        .has_f2_prefix = prefix == 3,
        .has_f3_prefix = prefix == 2,
        .l = vector_256,
        .vvvv = ~@as(u4, @truncate((vex >> 3) & 0x0F)),
        .m = 1,
    };

    if (decodeVexMaskMove(bytes, start_pos + 3, mask_vex, opcode)) |decoded| return decoded;

    if (opcode == 0x77 and (vex & 0x78) == 0x78 and !vector_256 and prefix == 0) {
        return .{ .op = .vzeroupper, .len = @intCast(start_pos + 3) };
    }
    if (start_pos + 3 >= bytes.len) return .{};

    // VLDMXCSR/VSTMXCSR: VEX.128.0F.WIG AE /2 and /3. Xenia emits the
    // load form before entering generated floating-point code. This belongs
    // to Rosette's ISA state model; no Xenia-side VEX-to-NEON helper is
    // involved.
    if (opcode == 0xAE and (vex & 0x78) == 0x78 and !vector_256 and prefix == 0) {
        var decoded = DecodedInsn{ .size = .bits32 };
        var pos = start_pos + 3;
        const modrm = bytes[pos];
        const group = (modrm >> 3) & 7;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        if (decoded.is_reg_form or (group != 2 and group != 3)) return .{};
        decoded.op = if (group == 2) .ldmxcsr_mem32 else .stmxcsr_mem32;
        decoded.addr = rm.addr;
        decoded.len = @intCast(pos);
        return decoded;
    }

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

    // VPSHUFD/VPSHUFLW/VPSHUFHW: VEX.NDS.LIG.{66/F2/F3}.0F.WIG 70 /r ib.
    // VEX.vvvv is reserved and must contain the encoded all-ones value.
    if (opcode == 0x70 and (prefix == 1 or prefix == 2 or prefix == 3) and mask_vex.vvvv == 0) {
        var decoded = DecodedInsn{ .op = switch (prefix) {
            1 => .vpshufd,
            2 => .vpshufhw,
            3 => .vpshuflw,
            else => unreachable,
        }, .vector_256 = vector_256 };
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

    // VSHUFPS: VEX.NDS.128/256.0F.WIG C6 /r ib. Unlike VPSHUFD, this is a
    // true three-source encoding: VEX.vvvv supplies SRC1 and ModR/M.r/m
    // supplies SRC2. No mandatory prefix is permitted.
    if (opcode == 0xC6 and prefix == 0) {
        var decoded = DecodedInsn{ .op = .vshufps, .vector_256 = vector_256 };
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
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        decoded.uses_imm = true;
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
    // VCMPPS/VCMPPD/VCMPSS/VCMPSD: VEX.0F C2 /r ib. Three operands plus a
    // comparison predicate in the immediate. Xenia's backend emits these for
    // every float comparison that produces a mask rather than flags, so a
    // missing arm here is a SIGILL in the middle of generated code — and that
    // SIGILL cascades: the emulator's own exception handler looks up a guest
    // function for a host PC inside its JIT cache, finds none, and dereferences
    // the null, so the crash it reports is nowhere near the cause.
    // VCVTDQ2PS / VCVTPS2DQ / VCVTTPS2DQ: VEX.0F 5B /r. Two operands; the
    // prefix chooses the direction and, for F3, truncation instead of the
    // current rounding mode. Xenia emits the truncating form for float-to-int
    // conversion, which is the one that was missing.
    // VRCPPS/VRCPSS (0F 53) and VRSQRTPS/VRSQRTSS (0F 52): approximate
    // reciprocal and reciprocal square root. No prefix is the packed form
    // (two operands); F3 is the scalar form, which is three-operand — the
    // upper lanes of the destination come from VEX.vvvv, not from the source.
    if ((opcode == 0x52 or opcode == 0x53) and (prefix == 0 or prefix == 2)) {
        const scalar = prefix == 2;
        if (scalar and vector_256) return .{};
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (scalar) decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = if (opcode == 0x53)
            (if (scalar) .vrcpss else .vrcpps)
        else
            (if (scalar) .vrsqrtss else .vrsqrtps);
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x5B and prefix != 3) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (prefix) {
            0 => .vcvtdq2ps,
            1 => .vcvtps2dq,
            2 => .vcvttps2dq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0xC2) {
        if (vector_256 and (prefix == 2 or prefix == 3)) return .{};

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
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = switch (prefix) {
            0 => .vcmpps,
            1 => .vcmppd,
            2 => .vcmpss,
            3 => .vcmpsd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

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

    // VPINSRW: VEX.128.66.0F.W0 C4 /r ib — Insert Word. ModRM.reg is the
    // destination XMM, VEX.vvvv is the merge source, and ModRM.r/m is the
    // scalar GPR or memory source.
    if (opcode == 0xC4 and !vector_256 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpinsrw, .size = .bits16 };
        var pos = start_pos + 3;
        if (pos >= bytes.len) return .{};
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F); // VEX.vvvv = merge source XMM
        decoded.is_reg_form = !is_memory;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (is_memory) {
            decoded.addr = rm.addr; // memory address
        } else {
            decoded.src_reg = @enumFromInt(rm.addr); // ModRM.r/m = GPR source
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

    if (opcode == 0x58 or opcode == 0x59 or opcode == 0x5C or
        opcode == 0x5D or opcode == 0x5E or opcode == 0x5F)
    {
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
            0x5D => switch (prefix) {
                0 => .vminps,
                1 => .vminpd,
                2 => .vminss,
                3 => .vminsd,
                else => unreachable,
            },
            0x5E => switch (prefix) {
                0 => .vdivps,
                1 => .vdivpd,
                2 => .vdivss,
                3 => .vdivsd,
                else => unreachable,
            },
            0x5F => switch (prefix) {
                0 => .vmaxps,
                1 => .vmaxpd,
                2 => .vmaxss,
                3 => .vmaxsd,
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

    // AVX packed saturating/min-max/multiply-high forms in the two-byte VEX
    // encoding. These are the C5 forms used when all vector registers fit in
    // the low eight architectural registers.
    if ((opcode == 0xD9 or opcode == 0xDA or opcode == 0xDE or
        opcode == 0xE4 or opcode == 0xE5 or opcode == 0xE8 or
        opcode == 0xE9 or opcode == 0xEC or opcode == 0xED) and prefix == 1)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var packed_pos = start_pos + 3;
        const is_mem = bytes[packed_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &packed_pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xD9 => .vpsubusw,
            0xDA => .vpminub,
            0xDE => .vpmaxub,
            0xE4 => .vpmulhuw,
            0xE5 => .vpmulhw,
            0xE8 => .vpsubsb,
            0xE9 => .vpsubsw,
            0xEC => .vpaddsb,
            0xED => .vpaddsw,
            else => unreachable,
        };
        decoded.len = @intCast(packed_pos);
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
        opcode == 0xE1 or opcode == 0xE2 or
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
            0xE1 => .vpsraw,
            0xE2 => .vpsrad,
            0xF1 => .vpsllw,
            0xF2 => .vpslld,
            0xF3 => .vpsllq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPUNPCKHBW/HDQ/HWD/HQDQ: VEX.NDS.128.66.0F.WIG 68/69/6A/6D /r
    if ((opcode == 0x68 or opcode == 0x69 or opcode == 0x6A or opcode == 0x6D) and prefix == 1) {
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
            0x6D => .vpunpckhqdq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPUNPCKLBW/LWD/LQD: VEX.NDS.128.66.0F.WIG 60/61/62 /r
    if ((opcode == 0x60 or opcode == 0x61) and prefix == 1) {
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

    // VPSHUFB is VEX.128.66.0F38.WIG 00 /r, and the *0F38* map is the whole
    // point: a two-byte VEX prefix has no map field, so it can only ever
    // encode the 0F map and cannot express this instruction at all. Decoding
    // `C5 <c> 00` as VPSHUFB claimed an encoding that does not exist, turning
    // a byte sequence that is not an instruction into a vector shuffle — and
    // it consumed an immediate the real instruction does not have, so it also
    // reported the wrong length. The three-byte path decodes the genuine
    // encoding; nothing belongs here.

    // VPSHUFD: VEX.NDS.LIG.66.0F.WIG 70 /r ib (already handled above, keeping for reference)

    // Immediate-count packed shifts: /2 and /3 shift right, /6 and /7
    // shift left. VEX.vvvv is the destination and ModRM.r/m is the source.
    if ((opcode == 0x71 or opcode == 0x72 or opcode == 0x73) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        const group = (@intFromEnum(rm.reg) & 0x07);
        // Group 4 is PSRAW/PSRAD. It was not merely rejected here: the opcode
        // table below mapped everything that was not group 2 to the *left*
        // shift, so admitting group 4 without fixing that would have decoded an
        // arithmetic right shift as a logical left shift. Both halves move
        // together. 0x73 (quadword) has no arithmetic form in AVX/AVX2.
        if (group != 2 and group != 3 and group != 4 and group != 6 and group != 7) return .{};
        if (group == 4 and opcode == 0x73) return .{};
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
            0x71 => switch (group) {
                2 => .vpsrlw,
                4 => .vpsraw,
                else => .vpsllw,
            },
            0x72 => switch (group) {
                2 => .vpsrld,
                4 => .vpsrad,
                else => .vpslld,
            },
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
    if ((opcode == 0xF8 or opcode == 0xFA or opcode == 0xFB or opcode == 0xF9) and prefix == 1) {
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
    if (opcode == 0xD5 and prefix == 1) {
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
    // The opcode-only VZEROUPPER form is four bytes; requiring a fifth byte
    // made a valid instruction at the end of a code page decode as invalid.
    if (start_pos + 4 > bytes.len) return .{};
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

    // Keep the production C4 path on the same BMI decoder as the standalone
    // VEX entry point. `decodeVex3` is what legacy.zig uses for real guest
    // execution, so table-only support here would still terminate Xenia on
    // its BMI-optimized zlib and hashing paths.
    const vex = VexPrefix{
        .len = 3,
        .is_2byte = false,
        .has_66_prefix = prefix == 1,
        .has_f2_prefix = prefix == 3,
        .has_f3_prefix = prefix == 2,
        .w = rex_w,
        .r = rex_r,
        .x = rex_x,
        .b = rex_b,
        .l = vector_256,
        .vvvv = ~@as(u4, @truncate((vex_control >> 3) & 0x0F)),
        .m = @intCast(opcode_map),
    };
    if (decodeVexGprInstruction(bytes, start_pos + 4, vex, opcode)) |decoded| return decoded;
    if (decodeVexMaskMove(bytes, start_pos + 4, vex, opcode)) |decoded| return decoded;

    // AVX/AVX2 vector forms that have their own architectural operand order
    // or were previously absent from this production C4 path. Keeping these
    // before the older fallback tables ensures the instruction reaches a real
    // executor instead of being reported as an invalid decode.
    if (opcode_map == 1 and prefix == 1 and !rex_w and
        (opcode == 0x63 or opcode == 0x67 or opcode == 0x6B or opcode == 0xEE))
    {
        const op: Op = switch (opcode) {
            0x63 => .vpacksswb,
            0x67 => .vpackuswb,
            0x6B => .vpackssdw,
            0xEE => .vpmaxsw,
            else => unreachable,
        };
        return decodeVex3Nds(bytes, start_pos, vex, op, false) orelse .{};
    }
    if (opcode_map == 1 and prefix == 0 and !rex_w and vector_256 and opcode == 0x2B) {
        return decodeVex3Store(bytes, start_pos, vex, .vmovntps) orelse .{};
    }
    if (opcode_map == 1 and prefix == 1 and !rex_w and vector_256 and opcode == 0xE7) {
        return decodeVex3Store(bytes, start_pos, vex, .vmovntdq) orelse .{};
    }
    if (opcode_map == 2 and prefix == 1 and !rex_w and vector_256 and opcode == 0x2A) {
        return decodeVex3Load(bytes, start_pos, vex, .vmovntdqa) orelse .{};
    }
    if (opcode_map == 1 and !rex_w and opcode == 0xE6 and (prefix == 1 or prefix == 2) and vex.vvvv == 0) {
        return decodeVex3Unary(bytes, start_pos, vex, if (prefix == 2) .vcvtdq2pd else .vcvttpd2dq, false) orelse .{};
    }
    if (opcode_map == 2 and prefix == 1 and !rex_w) {
        switch (opcode) {
            0x2C => return decodeVex3MaskMove(bytes, start_pos, vex, .vmaskmovps_load) orelse .{},
            0x2D => return decodeVex3MaskMove(bytes, start_pos, vex, .vmaskmovpd_load) orelse .{},
            0x2E => return decodeVex3MaskMove(bytes, start_pos, vex, .vmaskmovps_store) orelse .{},
            0x2F => return decodeVex3MaskMove(bytes, start_pos, vex, .vmaskmovpd_store) orelse .{},
            0x08 => return decodeVex3Nds(bytes, start_pos, vex, .vpsignb, false) orelse .{},
            0x09 => return decodeVex3Nds(bytes, start_pos, vex, .vpsignw, false) orelse .{},
            0x0A => return decodeVex3Nds(bytes, start_pos, vex, .vpsignd, false) orelse .{},
            0x04 => return decodeVex3Nds(bytes, start_pos, vex, .vpmaddubsw, false) orelse .{},
            0x2A => if (vector_256) return decodeVex3Load(bytes, start_pos, vex, .vmovntdqa) orelse .{},
            0x0C => return decodeVex3Nds(bytes, start_pos, vex, .vpermilps, false) orelse .{},
            0x1C => return decodeVex3Unary(bytes, start_pos, vex, .vpabsb, false) orelse .{},
            0x1D => return decodeVex3Unary(bytes, start_pos, vex, .vpabsw, false) orelse .{},
            0x1E => return decodeVex3Unary(bytes, start_pos, vex, .vpabsd, false) orelse .{},
            0x20 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovsxbw, false) orelse .{},
            0x21 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovsxbd, false) orelse .{},
            0x22 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovsxbq, false) orelse .{},
            0x23 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovsxwd, false) orelse .{},
            0x24 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovsxwq, false) orelse .{},
            0x25 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovsxdq, false) orelse .{},
            0x28 => return decodeVex3Nds(bytes, start_pos, vex, .vpmuldq, false) orelse .{},
            0x29 => return decodeVex3Nds(bytes, start_pos, vex, .vpcmpeqq, false) orelse .{},
            0x2B => return decodeVex3Nds(bytes, start_pos, vex, .vpackusdw, false) orelse .{},
            0x30 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovzxbw, false) orelse .{},
            0x31 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovzxbd, false) orelse .{},
            0x32 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovzxbq, false) orelse .{},
            0x33 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovzxwd, false) orelse .{},
            0x34 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovzxwq, false) orelse .{},
            0x35 => return decodeVex3Unary(bytes, start_pos, vex, .vpmovzxdq, false) orelse .{},
            0x36 => return decodeVex3Nds(bytes, start_pos, vex, .vpermd, false) orelse .{},
            0x37 => return decodeVex3Nds(bytes, start_pos, vex, .vpcmpgtq, false) orelse .{},
            0x42 => return decodeVex3Nds(bytes, start_pos, vex, .vpsadbw, false) orelse .{},
            0x58 => if (vex.vvvv == 0) return decodeVex3Broadcast(bytes, start_pos, vex, .vpbroadcastd, .bits32) orelse .{},
            0x59 => if (vex.vvvv == 0) return decodeVex3Broadcast(bytes, start_pos, vex, .vpbroadcastq, .bits64) orelse .{},
            0x79 => if (vex.vvvv == 0) return decodeVex3Broadcast(bytes, start_pos, vex, .vpbroadcastw, .bits16) orelse .{},
            0xF5 => return decodeVex3Nds(bytes, start_pos, vex, .vpmaddwd, false) orelse .{},
            else => {},
        }
    }
    if (opcode_map == 3 and prefix == 1 and !rex_w) {
        switch (opcode) {
            0x0F => return decodeVex3Nds(bytes, start_pos, vex, .vpalignr, true) orelse .{},
            0x08 => if (vex.vvvv == 0) return decodeVex3Unary(bytes, start_pos, vex, .vroundps, true) orelse .{},
            0x09 => if (vex.vvvv == 0) return decodeVex3Unary(bytes, start_pos, vex, .vroundpd, true) orelse .{},
            0x0A => if (!vector_256) return decodeVex3Nds(bytes, start_pos, vex, .vroundss, true) orelse .{},
            0x0B => if (!vector_256) return decodeVex3Nds(bytes, start_pos, vex, .vroundsd, true) orelse .{},
            0x04 => if (vex.vvvv == 0) return decodeVex3Unary(bytes, start_pos, vex, .vpermilps, true) orelse .{},
            0x0C => return decodeVex3Nds(bytes, start_pos, vex, .vblendps, true) orelse .{},
            0x0E => return decodeVex3Nds(bytes, start_pos, vex, .vpblendw, true) orelse .{},
            0x14 => return decodeVex3ExtractElement(bytes, start_pos, vex, .vpextrb, .bits8) orelse .{},
            0x15 => return decodeVex3ExtractElement(bytes, start_pos, vex, .vpextrw, .bits16) orelse .{},
            0x16 => return decodeVex3ExtractElement(bytes, start_pos, vex, .vpextrd, .bits32) orelse .{},
            0x17 => if (vex.vvvv == 0) return decodeVex3ExtractPs(bytes, start_pos, vex) orelse .{},
            0x20 => return decodeVex3InsertElement(bytes, start_pos, vex, .vpinsrb_xmm_xmm_reg32, .bits8) orelse .{},
            0x21 => return decodeVex3InsertPs(bytes, start_pos, vex) orelse .{},
            0x63 => if (vex.vvvv == 0) return decodeVex3String(bytes, start_pos, vex) orelse .{},
            else => {},
        }
    }

    if (opcode_map == 3 and prefix == 1 and rex_w and !vector_256 and opcode == 0x17) {
        return decodeVex3ExtractElement(bytes, start_pos, vex, .vpextrq, .bits64) orelse .{};
    }

    // VTESTPS/VTESTPD are VEX.0F38 two-source bit tests. They look similar
    // to the three-operand AVX family but have a reserved VEX.vvvv field;
    // keep their ModRM.reg/rm roles explicit for the executor.
    if (opcode_map == 2 and (opcode == 0x0E or opcode == 0x0F) and
        prefix == 1 and !rex_w and (vex_control & 0x78) == 0x78)
    {
        if (start_pos + 4 >= bytes.len) return .{};
        var decoded = DecodedInsn{};
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = if (opcode == 0x0E) .vtestps else .vtestpd;
        decoded.xmm_src = @intFromEnum(rm.reg);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.vector_256 = vector_256;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPDPBUSD is the AVX-VNNI byte dot-product form. Its EVEX siblings are
    // handled by the EVEX workstream; retaining the VEX.128/256 forms here
    // covers the code generated when Xenia selects AVX-VNNI.
    if (opcode_map == 2 and opcode == 0x50 and prefix == 1 and !rex_w) {
        if (start_pos + 4 >= bytes.len) return .{};
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vpdpbusd;
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

    // VUCOMISS/VUCOMISD (VEX.LIG.0F.WIG 2E) and VCOMISS/VCOMISD (…2F).
    //
    // The two-byte VEX form of these was already decoded; the three-byte form
    // was not, and the three-byte form is exactly the one a register above
    // xmm7 forces. Xenia's backend emits `vucomisd xmm8, xmm8; setp bl; test
    // bl, bl; jne …` as its NaN check, which encodes as `C4 41 79 2E C0` — a
    // three-byte VEX purely because REX.B is needed — so every float
    // comparison the JIT allocated into a high register decoded as invalid.
    //
    // Which of the four this is comes from the prefix, not the opcode: no
    // prefix is the single-precision form, 66 the double. Opcode 2F is the
    // ordered compare, which differs from 2E only in raising an invalid-
    // operation exception on a quiet NaN. Rosette does not raise guest FP
    // exceptions and both set the same flags from the same comparison, so 2F
    // is decoded as its unordered counterpart rather than given a distinct
    // opcode that would behave identically.
    if (opcode_map == 1 and (opcode == 0x2E or opcode == 0x2F) and
        (prefix == 0 or prefix == 1) and (vex_control & 0x78) == 0x78)
    {
        var decoded = DecodedInsn{};
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = if (prefix == 0) .vucomiss else .vucomisd;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VZEROUPPER: VEX.128.0F.WIG 77. No operands, so the whole instruction is
    // the prefix and the opcode.
    if (opcode_map == 1 and opcode == 0x77 and prefix == 0 and
        !vector_256 and (vex_control & 0x78) == 0x78)
    {
        return .{ .op = .vzeroupper, .len = @intCast(start_pos + 4) };
    }

    // The three-operand integer forms: VEX.NDS.128.66.0F <op> /r, destination
    // in ModRM.reg, first source in VEX.vvvv, second in ModRM.r/m.
    if (opcode_map == 1 and prefix == 1 and switch (opcode) {
        0x60, 0x61, 0x68, 0x69, 0x6A, 0x6D => true,
        else => false,
    }) {
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
            0x60 => .vpunpcklbw,
            0x61 => .vpunpcklwd,
            0x68 => .vpunpckhbw,
            0x69 => .vpunpckhwd,
            0x6A => .vpunpckhdq,
            0x6D => .vpunpckhqdq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPSHUFD/VPSHUFLW/VPSHUFHW: VEX.128/256.{66/F2/F3}.0F.WIG 70 /r ib.
    // VEX.vvvv is reserved and must contain the encoded all-ones value.
    if (opcode_map == 1 and opcode == 0x70 and
        (prefix == 1 or prefix == 2 or prefix == 3) and
        (vex_control & 0x78) == 0x78)
    {
        var decoded = DecodedInsn{ .op = switch (prefix) {
            1 => .vpshufd,
            2 => .vpshufhw,
            3 => .vpshuflw,
            else => unreachable,
        }, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @intCast(rm.addr);
        decoded.is_reg_form = !is_memory;
        if (is_memory) decoded.addr = rm.addr;
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VSHUFPS: VEX.NDS.128/256.0F.WIG C6 /r ib. The three-byte form is
    // semantically identical to the two-byte form; it is selected when X/B/W
    // extension bits or an explicit 0F map are required.
    if (opcode_map == 1 and opcode == 0xC6 and prefix == 0) {
        var decoded = DecodedInsn{ .op = .vshufps, .vector_256 = vector_256 };
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
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        decoded.uses_imm = true;
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPINSRW: VEX.128.66.0F.W0 C4 /r ib. ModRM.r/m is the destination XMM,
    // ModRM.reg the general-purpose source, VEX.vvvv the merge source.
    if (opcode_map == 1 and opcode == 0xC4 and prefix == 1 and !vector_256) {
        var decoded = DecodedInsn{ .op = .vpinsrw, .size = .bits16 };
        var pos = start_pos + 4;
        if (pos >= bytes.len) return .{};
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits32);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.src_reg = @enumFromInt(rm.addr);
        }
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPMOVMSKB: VEX.128.66.0F.WIG D7 /r. Destination is a general-purpose
    // register, so `dst_reg` rather than `xmm_dst` carries it.
    if (opcode_map == 1 and opcode == 0xD7 and prefix == 1 and (vex_control & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.dst_reg = rm.reg;
        decoded.xmm_src = @intCast(rm.addr);
        decoded.op = if (vector_256) .vpmovmskb_ymm else .vpmovmskb;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VCMPPS/VCMPPD/VCMPSS/VCMPSD, three-byte form. Same instruction, the
    // encoding a register above xmm7 forces.
    // Immediate-count packed shifts, three-byte form: VEX.128.66.0F 71/72/73
    // /2 /3 /6 /7 ib. These are *group* opcodes — ModRM.reg selects the
    // instruction rather than naming a register — and VEX.vvvv is the
    // destination with ModRM.r/m the source, which is why a source above xmm7
    // needs REX.B and therefore this encoding.
    if (opcode_map == 1 and prefix == 1 and
        (opcode == 0x71 or opcode == 0x72 or opcode == 0x73))
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        const group = @intFromEnum(rm.reg) & 0x07;
        // Group 4 is PSRAW/PSRAD. It was not merely rejected here: the opcode
        // table below mapped everything that was not group 2 to the *left*
        // shift, so admitting group 4 without fixing that would have decoded an
        // arithmetic right shift as a logical left shift. Both halves move
        // together. 0x73 (quadword) has no arithmetic form in AVX/AVX2.
        if (group != 2 and group != 3 and group != 4 and group != 6 and group != 7) return .{};
        if (group == 4 and opcode == 0x73) return .{};
        decoded.xmm_dst = @truncate((~vex_control >> 3) & 0x0F);
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
            0x71 => switch (group) {
                2 => .vpsrlw,
                4 => .vpsraw,
                else => .vpsllw,
            },
            0x72 => switch (group) {
                2 => .vpsrld,
                4 => .vpsrad,
                else => .vpslld,
            },
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

    // VCVTDQ2PS / VCVTPS2DQ / VCVTTPS2DQ, three-byte form — the encoding a
    // source register above xmm7 forces.
    // VRCPPS/VRCPSS and VRSQRTPS/VRSQRTSS, three-byte form.
    if (opcode_map == 1 and (opcode == 0x52 or opcode == 0x53) and
        (prefix == 0 or prefix == 2))
    {
        const scalar = prefix == 2;
        if (scalar and vector_256) return .{};
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (scalar) decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = if (opcode == 0x53)
            (if (scalar) .vrcpss else .vrcpps)
        else
            (if (scalar) .vrsqrtss else .vrsqrtps);
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x5B and prefix != 3) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (prefix) {
            0 => .vcvtdq2ps,
            1 => .vcvtps2dq,
            2 => .vcvttps2dq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0xC2) {
        if (vector_256 and (prefix == 2 or prefix == 3)) return .{};

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
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = switch (prefix) {
            0 => .vcmpps,
            1 => .vcmppd,
            2 => .vcmpss,
            3 => .vcmpsd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

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

    // VEX.0F arithmetic/extrema: VADD (58), VMUL (59), VSUB (5C),
    // VMIN (5D), VDIV (5E), VMAX (5F).
    // Prefix: 0=PS, 1=PD, 2=SS, 3=SD
    if (opcode_map == 1 and
        (opcode == 0x58 or opcode == 0x59 or opcode == 0x5C or
            opcode == 0x5D or opcode == 0x5E or opcode == 0x5F))
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
            0x5D => switch (prefix) {
                0 => .vminps,
                1 => .vminpd,
                2 => .vminss,
                3 => .vminsd,
                else => unreachable,
            },
            0x5E => switch (prefix) {
                0 => .vdivps,
                1 => .vdivpd,
                2 => .vdivss,
                3 => .vdivsd,
                else => unreachable,
            },
            0x5F => switch (prefix) {
                0 => .vmaxps,
                1 => .vmaxpd,
                2 => .vmaxss,
                3 => .vmaxsd,
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

    // VPHMINPOSUW is a two-operand, 128-bit-only instruction. Its encoded
    // VEX.vvvv field is reserved (1111b), so it must not use the ordinary NDS
    // three-operand layout used by the neighbouring 0F38 operations.
    if (opcode_map == 2 and opcode == 0x41 and prefix == 1 and
        !vector_256 and (vex_control & 0x78) == 0x78)
    {
        if (start_pos + 4 >= bytes.len) return .{};
        var decoded = DecodedInsn{};
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vphminposuw;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and
        (opcode == 0xD1 or opcode == 0xD2 or opcode == 0xD3 or
            opcode == 0xE1 or opcode == 0xE2 or
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
            0xE1 => .vpsraw,
            0xE2 => .vpsrad,
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

    // AVX packed saturating/min-max/multiply-high forms in the three-byte
    // VEX path. Xenia reaches this path whenever X/B extension bits are
    // needed, so keeping only the C5 forms above would still make the same
    // opcode family disappear for high vector registers.
    if (opcode_map == 1 and
        (opcode == 0xD9 or opcode == 0xDA or opcode == 0xDE or
            opcode == 0xE4 or opcode == 0xE5 or opcode == 0xE8 or
            opcode == 0xE9 or opcode == 0xEC or opcode == 0xED) and prefix == 1)
    {
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
            0xD9 => .vpsubusw,
            0xDA => .vpminub,
            0xDE => .vpmaxub,
            0xE4 => .vpmulhuw,
            0xE5 => .vpmulhw,
            0xE8 => .vpsubsb,
            0xE9 => .vpsubsw,
            0xEC => .vpaddsb,
            0xED => .vpaddsw,
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

    // VPERM2F128, VINSERTF128/VEXTRACTF128/VINSERTI128, and VEXTRACTI128 are
    // the 0F3A lane forms. Their
    // ModR/M operand direction is not the generic NDS direction, so use the
    // shared lane decoder rather than duplicating a subtly different layout.
    if (opcode_map == 3 and opcode == 0x06 and prefix == 1) {
        if (start_pos + 4 >= bytes.len) return .{};
        var pos = start_pos + 4;
        var decoded = DecodedInsn{};
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (pos >= bytes.len) return .{};
        const modrm = .{
            .dst_xmm = @intFromEnum(rm.reg),
            .src_xmm = if (decoded.is_reg_form) @as(u8, @intCast(rm.addr)) else 0,
            .is_reg_form = decoded.is_reg_form,
            .addr = rm.addr,
        };
        return decodeVexPermute2x128(vex, pos + 1, modrm, bytes[pos]) orelse .{};
    }

    if (opcode_map == 3 and (opcode == 0x18 or opcode == 0x19 or opcode == 0x38 or opcode == 0x39) and prefix == 1) {
        if (start_pos + 4 >= bytes.len) return .{};
        var pos = start_pos + 4;
        var decoded = DecodedInsn{};
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (pos >= bytes.len) return .{};
        const op: Op = switch (opcode) {
            0x18 => .vinsertf128,
            0x19 => .vextractf128,
            0x38 => .vinserti128,
            0x39 => .vextractf128, // VEXTRACTI128, bitwise alias
            else => unreachable,
        };
        const src_xmm: u8 = if (decoded.is_reg_form) @intCast(rm.addr) else 0;
        const modrm = .{
            .dst_xmm = @intFromEnum(rm.reg),
            .src_xmm = src_xmm,
            .is_reg_form = decoded.is_reg_form,
            .addr = rm.addr,
        };
        return decodeVexLane128(vex, pos + 1, op, modrm, bytes[pos]) orelse .{};
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

    // VPMAXSD: VEX.NDS.128/256.66.0F38.W0 3D /r. This is the AVX/AVX2
    // instruction emitted by Xenia at the reported fault address. The generic
    // VEX decoder knows the 0F38 opcode, but the legacy dispatch path reaches
    // this low-level decoder directly, so it must be covered here as well.
    // Packed integer min/max and VPMULLD, VEX.128/256.66.0F38.WIG 38..40 /r.
    //
    // Only 0x3D (VPMAXSD) was decoded here. The other seven had `Op` members and
    // a complete table in `decodeVexMap38` — which `decodeVex3` never calls, so
    // production never saw it. That is the same shape as the earlier C5/C4 gap:
    // a second opcode table that looks like coverage and is not reachable.
    // `VPMINSD` (0x39) is what Xenia's shader translator raised SIGILL on.
    if (opcode_map == 2 and opcode >= 0x38 and opcode <= 0x40 and prefix == 1 and !rex_w) {
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
            0x38 => .vpminsb,
            0x39 => .vpminsd,
            0x3A => .vpminuw,
            0x3B => .vpminud,
            0x3C => .vpmaxsb,
            0x3D => .vpmaxsd,
            0x3E => .vpmaxuw,
            0x3F => .vpmaxud,
            0x40 => .vpmulld_38,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPEXTRB/W/D/Q: VEX.NDD.LIG.66.0F3A.W0 14/15/16, W1 17 /r ib
    // ModRM.reg is the source XMM (VEX.R extends); ModRM.r/m is the
    // destination GPR or memory (VEX.B extends). VEX.L must be 0 and
    // VEX.vvvv reserved (1111b). VPEXTRQ is the W1 form; B/W/D are W0.
    // Xbyak emits these for byte/word/dword/qword lane extraction in
    // JIT-generated code.
    if (opcode_map == 3 and (opcode == 0x14 or opcode == 0x15 or opcode == 0x16 or opcode == 0x17) and prefix == 1) {
        if (vector_256 or (vex_control & 0x78) != 0x78) return .{};
        const w_ok = if (opcode == 0x17) rex_w else !rex_w;
        if (!w_ok) return .{};
        const extract_size: Size = switch (opcode) {
            0x14 => .bits8,
            0x15 => .bits16,
            0x16 => .bits32,
            0x17 => .bits64,
            else => unreachable,
        };
        var decoded = DecodedInsn{ .size = extract_size };
        var pos = start_pos + 4;
        if (pos >= bytes.len) return .{};
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.dst_reg = @enumFromInt(rm.addr);
        }
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = switch (opcode) {
            0x14 => .vpextrb,
            0x15 => .vpextrw,
            0x16 => .vpextrd,
            0x17 => .vpextrq,
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

    // VBLENDVPS/VBLENDVPD/VPBLENDVB: VEX.NDS.128/256.66.0F3A.W0 4A/4B/4C /r ib
    // RVMR encoding: ModRM.reg = DEST, VEX.vvvv = SRC1, ModRM.r/m = SRC2,
    // and the MASK register is encoded in bits[7:4] of the imm8 (imm8[3:0]
    // ignored). VEX.W must be 0 (otherwise #UD). Xbyak emits these for
    // HIR select/blend operations in JIT-generated code.
    if (opcode_map == 3 and (opcode == 0x4A or opcode == 0x4B or opcode == 0x4C) and prefix == 1) {
        if (rex_w) return .{};

        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        if (pos >= bytes.len) return .{};
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        decoded.uses_imm = true;
        decoded.xmm_mask = @intCast((bytes[pos] >> 4) & 0x0F);
        pos += 1;
        decoded.op = switch (opcode) {
            0x4A => .vblendvps,
            0x4B => .vblendvpd,
            0x4C => .vpblendvb,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPINSRD/VPINSRQ/VPINSRW: VEX.NDS.LIG.66.0F38.WIG 22/23/2A /r ib
    if (opcode_map == 3 and (opcode == 0x22 or opcode == 0x23 or opcode == 0x2A) and prefix == 1 and !vector_256) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        if (pos >= bytes.len) return .{};
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        decoded.size = switch (opcode) {
            0x22 => .bits32,
            0x23 => .bits64,
            0x2A => .bits16,
            else => unreachable,
        };
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
            decoded.src_reg = @enumFromInt(rm.addr);
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
        if (pos >= bytes.len) return .{};
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits8);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
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
    // for ordinary 0F-map moves. Clang and Xbyak use these forms throughout
    // Xenia, including VMOVUPS xmm0,[r12] in pre-main libc++ constructors.
    // Keep the full aligned/unaligned integer and floating-point move families
    // on the same ModR/M + SIB path so VEX.B and VEX.X reach readModRM.
    if (opcode_map == 1 and
        (opcode == 0x6F or opcode == 0x7F or
            opcode == 0x10 or opcode == 0x11 or
            opcode == 0x28 or opcode == 0x29) and
        (vex_control & 0x78) == 0x78)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        const Family = enum { dqu, dqa, ups, aps, upd, apd, ss, sd };
        const family: Family = switch (opcode) {
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
        if ((family == .ss or family == .sd) and (!is_memory or vector_256)) return .{};

        const is_load = opcode == 0x6F or opcode == 0x10 or opcode == 0x28;
        if (is_load) {
            decoded.xmm_dst = @intFromEnum(rm.reg);
            if (is_memory) {
                decoded.addr = rm.addr;
                decoded.op = if (vector_256) switch (family) {
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
                decoded.xmm_src = @intCast(rm.addr);
                decoded.op = if (vector_256) switch (family) {
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
            decoded.xmm_src = @intFromEnum(rm.reg);
            if (is_memory) {
                decoded.addr = rm.addr;
                decoded.op = if (vector_256) switch (family) {
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
                decoded.xmm_dst = @intCast(rm.addr);
                decoded.op = if (vector_256) switch (family) {
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
