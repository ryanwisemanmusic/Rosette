const std = @import("std");
const x64_decoder = @import("x64_decoder");
const cleo_routing = @import("cleo_routing");
const exit_diagnostics = @import("exit_diagnostics");
const macho_log = @import("dyld").event_log;
const atomic_compare_exchange = @import("memory").atomic_compare_exchange;
const memory_mod = @import("memory");
const proc_diag = @import("diagnostics.zig");
const execution_helpers = @import("../execution_helpers.zig");
const packed_ops = @import("../packed_ops.zig");
const decoder = @import("../decoder.zig");
const utils = @import("../utils.zig");
const types = @import("../types.zig");
const constants = @import("../constants.zig");
const compat_runtime = @import("macho_compat_runtime");
const tlv_runtime = @import("guest_abi").tlv_runtime;
const guest_assertion_recovery = @import("guest_abi").guest_assertion_recovery;
const lazy_import_stub = @import("dyld").lazy_import_stub;

const machoCapturePrint = macho_log.machoCapturePrint;
const Op = x64_decoder.Op;
const Size = x64_decoder.OperandSize;
const RegId = x64_decoder.RegId;
const DecodedInsn = x64_decoder.DecodedInsn;
const populationCount = x64_decoder.populationCount;
const crc32cAccumulator = x64_decoder.crc32cAccumulator;
const RFL_CF = x64_decoder.RFL_CF;
const RFL_PF: u32 = 1 << 2;
const RFL_AF: u32 = 1 << 4;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;
const RFL_DF: u32 = 1 << 10;
const GuestAccess = types.GuestAccess;
const ControlTransferContext = types.ControlTransferContext;
const GUEST_SIGILL = constants.GUEST_SIGILL;
const readExtendedFloat80 = memory_mod.readExtendedFloat80;
const writeExtendedFloat80 = memory_mod.writeExtendedFloat80;
const VexArithmetic = decoder.VexArithmetic;
const VexBitwise = decoder.VexBitwise;
const applyVexArithmetic = decoder.applyVexArithmetic;
const applyVexBitwise = decoder.applyVexBitwise;
const applyVexCompare = decoder.applyVexCompare;
const vexArithmeticForOp = decoder.vexArithmeticForOp;
const vexBitwiseForOp = decoder.vexBitwiseForOp;
const shuffleBytes = decoder.shuffleBytes;
const unpackLowDwords = decoder.unpackLowDwords;
const bitwiseAndAllZero = decoder.bitwiseAndAllZero;
const bitwiseAndNotAllZero = decoder.bitwiseAndNotAllZero;
const roundVexFloat = decoder.roundVexFloat;
const roundVexPackedF32 = decoder.roundVexPackedF32;
const roundVexPackedF64 = decoder.roundVexPackedF64;
const convertVexFloatToSigned = decoder.convertVexFloatToSigned;
const duplicateVectorElements = decoder.duplicateVectorElements;
const permutePackedDoubles = decoder.permutePackedDoubles;
const PackedIntegerOperation = packed_ops.PackedIntegerOperation;
const packedIntegerBinary = packed_ops.packedIntegerBinary;
const multiplyUnsignedEvenDwords = packed_ops.multiplyUnsignedEvenDwords;
const shufflePackedDwords = packed_ops.shufflePackedDwords;
const unpackLowQwords = packed_ops.unpackLowQwords;
const blendPackedWords = packed_ops.blendPackedWords;
const shiftPackedBytes = packed_ops.shiftPackedBytes;
const shiftPackedElements = packed_ops.shiftPackedElements;
const threeOperandImulResult = utils.threeOperandImulResult;
const maskForSize = execution_helpers.maskForSize;

const log = std.log.scoped(.macho);

fn releaseBarrier() void {
    proc_diag.releaseBarrier();
}

fn arithmeticShiftRight(value: u64, size: Size, count: u6) u64 {
    const signed: i64 = switch (size) {
        .bits8 => @as(i8, @bitCast(@as(u8, @truncate(value)))),
        .bits16 => @as(i16, @bitCast(@as(u16, @truncate(value)))),
        .bits32 => @as(i32, @bitCast(@as(u32, @truncate(value)))),
        .bits64 => @bitCast(value),
    };
    return @as(u64, @bitCast(signed >> count)) & maskForSize(size);
}

fn packedIntegerOperation(op: Op) PackedIntegerOperation {
    return switch (op) {
        .vpaddb, .vpaddw, .vpaddd, .vpaddq => .add,
        .vpsubb, .vpsubw, .vpsubd, .vpsubq => .sub,
        .vpmullw => .mul_low,
        else => unreachable,
    };
}

fn packedIntegerLaneBits(op: Op) u8 {
    return switch (op) {
        .vpaddb, .vpsubb => 8,
        .vpaddw, .vpsubw, .vpmullw => 16,
        .vpaddd, .vpsubd => 32,
        .vpaddq, .vpsubq => 64,
        else => unreachable,
    };
}

fn packedShiftLaneBits(op: Op) u8 {
    return switch (op) {
        .vpsllw, .vpsrlw => 16,
        .vpslld, .vpsrld => 32,
        .vpsllq, .vpsrlq => 64,
        else => unreachable,
    };
}

fn isCooperativeYieldImport(name: []const u8) bool {
    return std.mem.eql(u8, name, "_pthread_yield_np") or std.mem.eql(u8, name, "_sched_yield");
}

pub fn execute(self: anytype, initial_d: DecodedInsn) void {
    // Check if CLEO can route this instruction for wide execution
    {
        const result = cleo_routing.CleoRouter.route(
            @tagName(initial_d.op),
            cleo_routing.types.FeatureSet.cleoEmulated(),
            0, // skip width check; decoder determines width
        );
        if (result.can_route) {
            self.cleo_dispatch_hits +|= 1;
            if (result.meta) |meta| {
                const result_wide: ?cleo_routing.wide.Wide(128) = ternary: {
                    const is_fma = switch (meta.operation) {
                        .fma_ps, .fma_pd, .fms_ps, .fms_pd, .fnma_ps, .fnma_pd, .fnms_ps, .fnms_pd, .fma_addsub_ps, .fma_addsub_pd, .fma_subadd_ps => true,
                        else => false,
                    };
                    const mask_active = initial_d.opmask != 0;
                    const mask_val: u64 = if (mask_active) self.k[initial_d.opmask] else 0xFFFF_FFFF_FFFF_FFFF;
                    const mask_mode: cleo_routing.wide.MaskMode = if (initial_d.zero_mask) .zero else .merge;
                    if (!is_fma) {
                        _ = initial_d.evex_broadcast; // Reserved for EVEX broadcast semantics
                        if (mask_active) {
                            break :ternary cleo_routing.ops.executeBinaryMasked(
                                128,
                                meta,
                                cleo_routing.wide.Wide(128).fromBytes(self.xmm[initial_d.xmm_dst]),
                                cleo_routing.wide.Wide(128).fromBytes(self.xmm[initial_d.xmm_dst]),
                                cleo_routing.wide.Wide(128).fromBytes(self.xmm[initial_d.xmm_src]),
                                mask_val,
                                mask_mode,
                                result.features,
                            ) catch null;
                        }
                        break :ternary cleo_routing.ops.executeBinary(
                            128,
                            meta,
                            cleo_routing.wide.Wide(128).fromBytes(self.xmm[initial_d.xmm_dst]),
                            cleo_routing.wide.Wide(128).fromBytes(self.xmm[initial_d.xmm_src]),
                            result.features,
                        ) catch null;
                    }
                    const op_name = @tagName(initial_d.op);
                    const has_132 = std.mem.indexOf(u8, op_name, "132") != null;
                    const has_213 = std.mem.indexOf(u8, op_name, "213") != null;
                    const accum = if (has_132) initial_d.xmm_src2 else if (has_213) initial_d.xmm_src else initial_d.xmm_dst;
                    const lhs = if (has_132) initial_d.xmm_dst else if (has_213) initial_d.xmm_src2 else initial_d.xmm_src2;
                    const rhs = if (has_132) initial_d.xmm_src else if (has_213) initial_d.xmm_dst else initial_d.xmm_src;
                    if (mask_active) {
                        break :ternary cleo_routing.ops.executeAccumulateMasked(
                            128,
                            meta,
                            cleo_routing.wide.Wide(128).fromBytes(self.xmm[initial_d.xmm_dst]),
                            cleo_routing.wide.Wide(128).fromBytes(self.xmm[accum]),
                            cleo_routing.wide.Wide(128).fromBytes(self.xmm[lhs]),
                            cleo_routing.wide.Wide(128).fromBytes(self.xmm[rhs]),
                            mask_val,
                            mask_mode,
                            result.features,
                        ) catch null;
                    }
                    break :ternary cleo_routing.ops.executeAccumulate(
                        128,
                        meta,
                        cleo_routing.wide.Wide(128).fromBytes(self.xmm[accum]),
                        cleo_routing.wide.Wide(128).fromBytes(self.xmm[lhs]),
                        cleo_routing.wide.Wide(128).fromBytes(self.xmm[rhs]),
                        result.features,
                    ) catch null;
                };
                if (result_wide) |rw| {
                    self.xmm[initial_d.xmm_dst] = rw.bytes;
                    return;
                }
            }
            // Fall through to interpreter for unsupported operations
        }
    }
    var d = initial_d;
    // Detect LOCK prefix (0xF0) from raw instruction bytes at RIP.
    if (self.guestMemoryConst(self.regs.rip, 1)) |bytes| {
        if (bytes[0] == 0xF0) d.lock = true;
    }
    if (d.lock) {
        // Acquire barrier: all prior loads/stores complete before the
        // LOCK-prefixed RMW executes (x86 LOCK# acquire semantic).
        releaseBarrier();
    }
    switch (d.op) {
        .invalid => {
            machoCapturePrint("macho-processor: undecoded instruction at rip=0x{x} opcode_prefix=0x{x}\n", .{ self.regs.rip, self.readMemVal(self.regs.rip, .bits8) });
            self.faulted = true;
            self.exit_code = 1;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_instruction);
            self.terminated = true;
            return;
        },
        .nop => {},
        .cmc => self.regs.rflags ^= RFL_CF,
        .clc => self.regs.rflags &= ~RFL_CF,
        .stc => self.regs.rflags |= RFL_CF,

        .fild_mem16 => _ = self.x87.push(@floatFromInt(@as(i16, @bitCast(@as(u16, @truncate(self.readMemVal(d.addr, .bits16))))))),
        .fild_mem32 => _ = self.x87.push(@floatFromInt(@as(i32, @bitCast(@as(u32, @truncate(self.readMemVal(d.addr, .bits32))))))),
        .fild_mem64 => _ = self.x87.push(@floatFromInt(@as(i64, @bitCast(self.readMemVal(d.addr, .bits64))))),
        .fld_mem32 => _ = self.x87.push(@as(f64, @floatCast(@as(f32, @bitCast(@as(u32, @truncate(self.readMemVal(d.addr, .bits32)))))))),
        .fld_mem64 => _ = self.x87.push(@bitCast(self.readMemVal(d.addr, .bits64))),
        .fld_mem80 => {
            const input = self.guestMemoryConst(d.addr, 10) orelse {
                self.terminateForGuestAccess(d.addr, 10, .read, "fld_mem80");
                return;
            };
            _ = self.x87.push(readExtendedFloat80(input));
        },
        .fstp_mem80 => {
            const output = self.guestMemory(d.addr, 10) orelse {
                self.terminateForGuestAccess(d.addr, 10, .write, "fstp_mem80");
                return;
            };
            if (self.x87.pop()) |value| writeExtendedFloat80(output, value) else @memset(output[0..10], 0);
        },
        .fstp_mem32 => {
            if (self.x87.pop()) |value| {
                self.writeMemVal(d.addr, .bits32, @as(u64, @as(u32, @bitCast(@as(f32, @floatCast(value))))));
            }
        },
        .fstp_mem64 => {
            if (self.x87.pop()) |value| self.writeMemVal(d.addr, .bits64, @as(u64, @bitCast(value)));
        },
        .fld_st => {
            if (self.x87.get(@truncate(d.imm))) |value| _ = self.x87.push(value);
        },
        .fstp_st => {
            if (self.x87.get(0)) |value| {
                _ = self.x87.set(@truncate(d.imm), value);
                _ = self.x87.pop();
            }
        },
        .fxch_st => _ = self.x87.exchange(@truncate(d.imm)),
        .ffree_st => self.x87.free(@truncate(d.imm)),
        .fninit => self.x87.reset(),
        .fnstsw_ax => self.setReg(.al_ax_eax_rax, .bits16, self.x87.statusWord()),
        .fnstcw_mem16 => self.writeMemVal(d.addr, .bits16, self.x87.control),
        .fldcw_mem16 => self.x87.control = @truncate(self.readMemVal(d.addr, .bits16)),
        .x87_binary => self.x87.binary(
            @truncate((d.imm >> 3) & 7),
            @truncate((d.imm >> 6) & 7),
            @truncate(d.imm),
            (d.imm & (1 << 9)) != 0,
        ),
        .fucomip_st => self.executeFucomip(@truncate(d.imm)),

        .mov_reg8_mem8 => {
            self.setReg(d.dst_reg, .bits8, self.readMemVal(d.addr, .bits8));
        },
        .mov_reg16_mem16 => {
            self.setReg(d.dst_reg, .bits16, self.readMemVal(d.addr, .bits16));
        },
        .mov_reg32_mem32 => {
            self.setReg(d.dst_reg, .bits32, self.readMemVal(d.addr, .bits32));
        },
        .mov_reg64_mem64 => {
            _ = self.recoverNearNullBaseRegister(&d);
            self.setReg(d.dst_reg, .bits64, self.readMemVal(d.addr, .bits64));
        },

        .mov_mem8_reg8 => {
            self.writeMemVal(d.addr, .bits8, self.regVal(d.src_reg, .bits8));
        },
        .mov_mem16_reg16 => {
            self.writeMemVal(d.addr, .bits16, self.regVal(d.src_reg, .bits16));
        },
        .mov_mem32_reg32 => {
            self.writeMemVal(d.addr, .bits32, self.regVal(d.src_reg, .bits32));
        },
        .mov_mem64_reg64 => {
            self.writeMemVal(d.addr, .bits64, self.regVal(d.src_reg, .bits64));
        },

        .mov_reg_imm => {
            self.setReg(d.dst_reg, d.size, d.imm);
        },

        .mov_mem8_imm8 => {
            self.writeMemVal(d.addr, .bits8, d.imm);
        },
        .mov_mem16_imm16 => {
            self.writeMemVal(d.addr, .bits16, d.imm);
        },
        .mov_mem32_imm32 => {
            self.writeMemVal(d.addr, .bits32, d.imm);
        },
        .mov_mem64_imm32 => {
            self.writeMemVal(d.addr, .bits64, d.imm);
        },

        .mov_reg8_reg8 => {
            self.setReg(d.dst_reg, .bits8, self.regVal(d.src_reg, .bits8));
        },
        .mov_reg16_reg16 => {
            self.setReg(d.dst_reg, .bits16, self.regVal(d.src_reg, .bits16));
        },
        .mov_reg32_reg32 => {
            self.setReg(d.dst_reg, .bits32, self.regVal(d.src_reg, .bits32));
        },
        .mov_reg64_reg64 => {
            self.setReg(d.dst_reg, .bits64, self.regVal(d.src_reg, .bits64));
        },

        .add_accum_imm => self.executeAddRegImm(d, d.size),
        .or_accum_imm => {
            const result = self.regVal(.al_ax_eax_rax, d.size) | d.imm;
            self.setReg(.al_ax_eax_rax, d.size, result);
            self.setFlagsLogic(result, d.size);
        },
        .adc_accum_imm => {
            const input = self.regVal(.al_ax_eax_rax, d.size);
            const carry: u64 = @intFromBool((self.regs.rflags & RFL_CF) != 0);
            const addend = d.imm +% carry;
            const result = input +% addend;
            self.setReg(.al_ax_eax_rax, d.size, result);
            self.setFlagsAdd(input, addend, result, d.size);
        },
        .sbb_accum_imm => {
            const input = self.regVal(.al_ax_eax_rax, d.size);
            const carry: u64 = @intFromBool((self.regs.rflags & RFL_CF) != 0);
            const subtrahend = d.imm +% carry;
            const result = input -% subtrahend;
            self.setReg(.al_ax_eax_rax, d.size, result);
            self.setFlagsSub(input, subtrahend, result, d.size);
        },
        .and_accum_imm => {
            const result = self.regVal(.al_ax_eax_rax, d.size) & d.imm;
            self.setReg(.al_ax_eax_rax, d.size, result);
            self.setFlagsLogic(result, d.size);
        },
        .sub_accum_imm => self.executeSubRegImm(d, d.size),
        .xor_accum_imm => {
            const result = self.regVal(.al_ax_eax_rax, d.size) ^ d.imm;
            self.setReg(.al_ax_eax_rax, d.size, result);
            self.setFlagsLogic(result, d.size);
        },
        .cmp_accum_imm => {
            const input = self.regVal(.al_ax_eax_rax, d.size);
            self.setFlagsSub(input, d.imm, input -% d.imm, d.size);
        },

        .add_reg8_reg8, .add_reg16_reg16, .add_reg32_reg32, .add_reg64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_reg8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayRegisterBinary(d, .add, sz);
        },
        .add_reg8_mem8, .add_reg16_mem16, .add_reg32_mem32, .add_reg64_mem64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_reg8_mem8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .add, sz, .memory_to_register);
        },
        .add_mem8_reg8, .add_mem16_reg16, .add_mem32_reg32, .add_mem64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_mem8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .add, sz, .register_to_memory);
        },

        .add_reg8_imm8 => self.executeAddRegImm(d, .bits8),
        .add_reg16_imm8 => self.executeAddRegImm(d, .bits16),
        .add_reg32_imm8 => self.executeAddRegImm(d, .bits32),
        .add_reg64_imm8 => self.executeAddRegImm(d, .bits64),
        .add_reg16_imm32 => self.executeAddRegImm(d, .bits16),
        .add_reg32_imm32 => self.executeAddRegImm(d, .bits32),
        .add_reg64_imm32 => self.executeAddRegImm(d, .bits64),

        .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayRegisterBinary(d, .sub, sz);
        },
        .sub_reg8_mem8, .sub_reg16_mem16, .sub_reg32_mem32, .sub_reg64_mem64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_mem8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .sub, sz, .memory_to_register);
        },
        .sub_mem8_reg8, .sub_mem16_reg16, .sub_mem32_reg32, .sub_mem64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_mem8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .sub, sz, .register_to_memory);
        },
        .sbb_reg8_reg8, .sbb_reg16_reg16, .sbb_reg32_reg32, .sbb_reg64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sbb_reg8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayRegisterBinary(d, .sbb, sz);
        },
        .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_imm8) + @intFromEnum(Size.bits8));
            self.executeSubRegImm(d, sz);
        },
        .sbb_reg8_imm8 => {
            const a = self.regVal(d.dst_reg, .bits8);
            const b = d.imm;
            const cf = (self.regs.rflags & RFL_CF) != 0;
            const r = a -% b -% @as(u8, @intFromBool(cf));
            self.setReg(d.dst_reg, .bits8, r);
            self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
        },
        .adc_reg8_imm8 => {
            const a = self.regVal(d.dst_reg, .bits8);
            const b = d.imm;
            const cf = (self.regs.rflags & RFL_CF) != 0;
            const r = a +% b +% @as(u8, @intFromBool(cf));
            self.setReg(d.dst_reg, .bits8, r);
            self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
        },
        .adc_reg8_mem8 => {
            const a = self.regVal(d.dst_reg, .bits8);
            const b = self.readMemVal(d.addr, .bits8);
            const cf = (self.regs.rflags & RFL_CF) != 0;
            const r = a +% b +% @as(u8, @intFromBool(cf));
            self.setReg(d.dst_reg, .bits8, r);
            self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
        },
        .sbb_reg8_mem8 => {
            const a = self.regVal(d.dst_reg, .bits8);
            const b = self.readMemVal(d.addr, .bits8);
            const cf = (self.regs.rflags & RFL_CF) != 0;
            const r = a -% b -% @as(u8, @intFromBool(cf));
            self.setReg(d.dst_reg, .bits8, r);
            self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
        },

        .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_reg8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayRegisterBinary(d, .bit_and, sz);
        },
        .and_reg8_mem8, .and_reg16_mem16, .and_reg32_mem32, .and_reg64_mem64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_reg8_mem8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .bit_and, sz, .memory_to_register);
        },
        .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_mem8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .bit_and, sz, .register_to_memory);
        },
        .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8 => self.executeAndRegImm(d),
        .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32 => self.executeAndRegImm(d),

        .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayRegisterBinary(d, .bit_or, sz);
        },
        .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_mem8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .bit_or, sz, .memory_to_register);
        },
        .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_mem8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .bit_or, sz, .register_to_memory);
        },
        .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_imm8) + @intFromEnum(Size.bits8));
            self.executeHighwayImmediate(d, .bit_or, sz, false);
        },
        .or_mem8_imm8,
        .or_mem16_imm8,
        .or_mem32_imm8,
        .or_mem64_imm8,
        .or_mem16_imm32,
        .or_mem32_imm32,
        .or_mem64_imm32,
        => {
            self.executeHighwayImmediate(d, .bit_or, d.size, true);
        },

        .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayRegisterBinary(d, .bit_xor, sz);
        },
        .xor_reg8_mem8, .xor_reg16_mem16, .xor_reg32_mem32, .xor_reg64_mem64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_mem8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .bit_xor, sz, .memory_to_register);
        },
        .xor_mem8_reg8, .xor_mem16_reg16, .xor_mem32_reg32, .xor_mem64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_mem8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .bit_xor, sz, .register_to_memory);
        },
        .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_imm8) + @intFromEnum(Size.bits8));
            self.executeHighwayImmediate(d, .bit_xor, sz, false);
        },

        .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayRegisterBinary(d, .cmp, sz);
        },
        .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_mem8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .cmp, sz, .memory_to_register);
        },
        .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_mem8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .cmp, sz, .register_to_memory);
        },
        .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_imm8) + @intFromEnum(Size.bits8));
            self.executeHighwayImmediate(d, .cmp, sz, false);
        },
        .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_mem8_imm8) + @intFromEnum(Size.bits8));
            self.executeHighwayImmediate(d, .cmp, sz, true);
        },

        .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.test_reg8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayRegisterBinary(d, .test_bits, sz);
        },
        .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.test_mem8_reg8) + @intFromEnum(Size.bits8));
            self.executeHighwayMemoryBinary(d, .test_bits, sz, .register_to_memory);
        },
        .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => self.executeHighwayImmediate(d, .test_bits, d.size, false),
        .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => self.executeHighwayImmediate(d, .test_bits, d.size, true),

        .inc_mem8, .inc_mem16, .inc_mem32, .inc_mem64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.inc_mem8) + @intFromEnum(Size.bits8));
            const a = self.readMemVal(d.addr, sz);
            const r = a +% 1;
            self.writeMemVal(d.addr, sz, r);
            self.setFlagsIncDec(a, r, sz, true);
        },
        .inc_reg8, .inc_reg16, .inc_reg32, .inc_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.inc_reg8) + @intFromEnum(Size.bits8));
            const a = self.regVal(d.dst_reg, sz);
            const r = a +% 1;
            self.setReg(d.dst_reg, sz, r);
            self.setFlagsIncDec(a, r, sz, true);
        },
        .dec_mem8, .dec_mem16, .dec_mem32, .dec_mem64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.dec_mem8) + @intFromEnum(Size.bits8));
            const a = self.readMemVal(d.addr, sz);
            const r = a -% 1;
            self.writeMemVal(d.addr, sz, r);
            self.setFlagsIncDec(a, r, sz, false);
        },
        .dec_reg8, .dec_reg16, .dec_reg32, .dec_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.dec_reg8) + @intFromEnum(Size.bits8));
            const a = self.regVal(d.dst_reg, sz);
            const r = a -% 1;
            self.setReg(d.dst_reg, sz, r);
            self.setFlagsIncDec(a, r, sz, false);
        },

        .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.neg_reg8) + @intFromEnum(Size.bits8));
            const a = self.regVal(d.dst_reg, sz);
            const r = (~a +% 1) & maskForSize(sz);
            self.setReg(d.dst_reg, sz, r);
            self.setFlagsSub(0, a, r, sz);
        },
        .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => {
            const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.neg_mem8) + @intFromEnum(Size.bits8));
            const a = self.readMemVal(d.addr, sz);
            const r = (~a +% 1) & maskForSize(sz);
            self.writeMemVal(d.addr, sz, r);
            self.setFlagsSub(0, a, r, sz);
        },
        .not_reg8, .not_reg16, .not_reg32, .not_reg64 => {
            self.setReg(d.dst_reg, d.size, ~self.regVal(d.dst_reg, d.size));
        },
        .not_mem8, .not_mem16, .not_mem32, .not_mem64 => {
            self.writeMemVal(d.addr, d.size, ~self.readMemVal(d.addr, d.size));
        },

        .btr_reg_reg => self.executeBtrRegister(d),
        .btr_mem_reg => self.executeBtrMemory(d),

        .push_reg => {
            self.push(self.regVal(d.dst_reg, .bits64));
        },
        .push_mem64 => {
            self.push(self.readMemVal(d.addr, .bits64));
        },
        .push_imm => {
            self.push(d.imm);
        },

        .pop_reg => {
            self.setReg(d.dst_reg, .bits64, self.pop());
        },
        .pop_mem64 => {
            self.writeMemVal(d.addr, .bits64, self.pop());
        },

        .lods => {
            const src_addr = self.regs.rsi;
            switch (d.size) {
                .bits8 => self.setReg(.al_ax_eax_rax, .bits8, self.readMemVal(src_addr, .bits8)),
                .bits16 => self.setReg(.al_ax_eax_rax, .bits16, self.readMemVal(src_addr, .bits16)),
                .bits32 => self.setReg(.al_ax_eax_rax, .bits32, self.readMemVal(src_addr, .bits32)),
                .bits64 => self.setReg(.al_ax_eax_rax, .bits64, self.readMemVal(src_addr, .bits64)),
            }
            const stride: u64 = switch (d.size) {
                .bits8 => 1,
                .bits16 => 2,
                .bits32 => 4,
                .bits64 => 8,
            };
            if ((self.regs.rflags & RFL_DF) != 0) {
                self.regs.rsi -|= stride;
            } else {
                self.regs.rsi +|= stride;
            }
        },

        .call_rel32 => {
            const from_rip = self.regs.rip;
            const transfer = x64_decoder.highway.directControl(.call, from_rip, d.len, d.addr, true);
            const target = transfer.target;
            const return_addr = transfer.return_address.?;
            self.pending_control_transfer = .{
                .kind = "call_rel32",
                .instruction_address = from_rip,
                .target_address = target,
                .return_address = return_addr,
            };
            self.push(return_addr);
            self.regs.rip = target;
            self.logControlFlow("call_rel32", from_rip, target, d.len, return_addr);
            if (self.sha1_tracer.enabled and self.sha1_tracer.depth < 4) {
                const stk = self.sha1_tracer.depth;
                self.sha1_tracer.saved_entry[stk] = self.sha1_tracer.entry_rip;
                self.sha1_tracer.saved_count[stk] = self.sha1_tracer.instruction_count;
                self.sha1_tracer.saved_call_site[stk] = self.sha1_tracer.call_site;
                self.sha1_tracer.depth += 1;
                self.sha1_tracer.entry_rip = target;
                self.sha1_tracer.call_site = from_rip;
                self.sha1_tracer.instruction_count = 0;
            }
        },
        .call_reg64 => {
            const from_rip = self.regs.rip;
            const target = self.regVal(d.dst_reg, .bits64);
            const return_addr = self.regs.rip + d.len;
            if (target == 0) {
                self.logControlFlow("call_reg64_null", from_rip, target, d.len, return_addr);
                self.terminateForInvalidControlTransfer(.{
                    .kind = "call_reg64_null",
                    .instruction_address = from_rip,
                    .target_address = target,
                    .return_address = return_addr,
                });
            } else {
                self.pending_control_transfer = .{
                    .kind = "call_reg64",
                    .instruction_address = from_rip,
                    .target_address = target,
                    .return_address = return_addr,
                };
                self.push(return_addr);
                self.regs.rip = target;
                self.logControlFlow("call_reg64", from_rip, target, d.len, return_addr);
                if (self.sha1_tracer.enabled and self.sha1_tracer.depth < 4) {
                    const stk = self.sha1_tracer.depth;
                    self.sha1_tracer.saved_entry[stk] = self.sha1_tracer.entry_rip;
                    self.sha1_tracer.saved_count[stk] = self.sha1_tracer.instruction_count;
                    self.sha1_tracer.saved_call_site[stk] = self.sha1_tracer.call_site;
                    self.sha1_tracer.depth += 1;
                    self.sha1_tracer.entry_rip = target;
                    self.sha1_tracer.call_site = from_rip;
                    self.sha1_tracer.instruction_count = 0;
                }
            }
        },
        .call_mem64 => {
            const from_rip = self.regs.rip;
            const return_addr = self.regs.rip + d.len;
            // Do not record a terminal page-zero read before a narrowly
            // verified virtual-dispatch recovery has inspected the real
            // C++ object. readMemVal() is intentionally terminal on an
            // unmapped operand, so recovery must precede that side effect.
            const operand_mapped = self.guestMemoryConst(d.addr, @sizeOf(u64)) != null;
            var target: u64 = if (operand_mapped) self.readMemVal(d.addr, .bits64) else 0;
            if (target == 0) {
                target = self.recoverLibcppSharedControlBlockCall(from_rip, d.addr) orelse 0;
            }
            if ((target == 0 or (target != 0 and !self.isExecutableAddress(target))) and operand_mapped) {
                target = self.recoverNullVtableSlot(from_rip, d.addr) orelse target;
            }
            if (target == 0) {
                if (!operand_mapped) {
                    self.terminateForGuestAccess(d.addr, @sizeOf(u64), .read, "call_mem64");
                    return;
                }
                self.logControlFlow("call_mem64_null", from_rip, target, d.len, return_addr);
                self.terminateForInvalidControlTransfer(.{
                    .kind = "call_mem64_null",
                    .instruction_address = from_rip,
                    .operand_address = d.addr,
                    .target_address = target,
                    .return_address = return_addr,
                });
            } else if (!self.isExecutableAddress(target) and compat_runtime.syntheticThunk(target) == null and !tlv_runtime.Runtime.handles(target)) {
                self.logControlFlow("call_mem64", from_rip, target, d.len, return_addr);
                self.terminateForInvalidControlTransfer(.{
                    .kind = "call_mem64",
                    .instruction_address = from_rip,
                    .operand_address = d.addr,
                    .target_address = target,
                    .return_address = return_addr,
                });
            } else {
                self.pending_control_transfer = .{
                    .kind = "call_mem64",
                    .instruction_address = from_rip,
                    .operand_address = d.addr,
                    .target_address = target,
                    .return_address = return_addr,
                };
                self.push(return_addr);
                self.regs.rip = target;
                self.logControlFlow("call_mem64", from_rip, target, d.len, return_addr);
                if (self.sha1_tracer.enabled and self.sha1_tracer.depth < 4) {
                    const stk = self.sha1_tracer.depth;
                    self.sha1_tracer.saved_entry[stk] = self.sha1_tracer.entry_rip;
                    self.sha1_tracer.saved_count[stk] = self.sha1_tracer.instruction_count;
                    self.sha1_tracer.saved_call_site[stk] = self.sha1_tracer.call_site;
                    self.sha1_tracer.depth += 1;
                    self.sha1_tracer.entry_rip = target;
                    self.sha1_tracer.call_site = from_rip;
                    self.sha1_tracer.instruction_count = 0;
                }
            }
        },
        .ret => {
            if (d.imm > 0) {
                self.regs.rsp +|= d.imm;
            }
            const ret_addr = self.pop();
            if (ret_addr == 0) {
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.ret_stack_empty);
                self.terminated = true;
                self.exit_code = self.regs.rax;
                return;
            }
            self.logControlFlow("ret", self.regs.rip, ret_addr, d.len, null);
            self.regs.rip = ret_addr;
            if (self.sha1_tracer.enabled and self.sha1_tracer.depth > 0) {
                self.sha1_tracer.depth -= 1;
                const stk = self.sha1_tracer.depth;
                self.sha1_tracer.entry_rip = self.sha1_tracer.saved_entry[stk];
                self.sha1_tracer.instruction_count = self.sha1_tracer.saved_count[stk];
                self.sha1_tracer.call_site = self.sha1_tracer.saved_call_site[stk];
            }
        },

        .jmp_rel8 => {
            const transfer = x64_decoder.highway.directControl(.jump, self.regs.rip, d.len, d.addr, true);
            self.pending_control_transfer = .{
                .kind = "jmp_rel8",
                .instruction_address = self.regs.rip,
                .target_address = transfer.target,
            };
            self.logControlFlow("jmp", self.regs.rip, transfer.target, d.len, null);
            self.regs.rip = transfer.target;
        },
        .jmp_reg64 => {
            const target = self.regVal(d.dst_reg, .bits64);
            if (target == 0) {
                self.logControlFlow("jmp_reg64_null", self.regs.rip, target, d.len, null);
                self.terminateForInvalidControlTransfer(.{
                    .kind = "jmp_reg64_null",
                    .instruction_address = self.regs.rip,
                    .target_address = target,
                });
            } else {
                self.pending_control_transfer = .{
                    .kind = "jmp_reg64",
                    .instruction_address = self.regs.rip,
                    .target_address = target,
                };
                self.logControlFlow("jmp_reg64", self.regs.rip, target, d.len, null);
                self.regs.rip = target;
            }
        },
        .jmp_mem64 => {
            const stub_rip = self.regs.rip;
            const target = self.readMemVal(d.addr, .bits64);
            const imported = self.metadata.importAtStub(stub_rip);
            if (imported != null and isCooperativeYieldImport(imported.?.name)) {
                self.pending_import_stub_rip = null;
                self.lazy_import_direct_dispatches +|= 1;
                const import = imported.?;
                self.handleDirectImportCall(import);
                return;
            }
            const target_is_lazy_helper = target >= self.stub_helper_start and target < self.stub_helper_end;
            switch (lazy_import_stub.chooseDispatch(imported != null, target, target_is_lazy_helper)) {
                .typed_import => {
                    self.pending_import_stub_rip = null;
                    self.lazy_import_direct_dispatches +|= 1;
                    const import = imported.?;
                    self.handleDirectImportCall(import);
                },
                .invalid_null_target => {
                    self.logControlFlow("jmp_mem64_null", stub_rip, target, d.len, null);
                    self.terminateForInvalidControlTransfer(.{
                        .kind = "jmp_mem64_null",
                        .instruction_address = stub_rip,
                        .operand_address = d.addr,
                        .target_address = target,
                    });
                },
                .follow_target => {
                    self.pending_import_stub_rip = null;
                    self.pending_control_transfer = .{
                        .kind = "jmp_mem64",
                        .instruction_address = stub_rip,
                        .operand_address = d.addr,
                        .target_address = target,
                    };
                    self.logControlFlow("jmp_mem64", stub_rip, target, d.len, null);
                    self.regs.rip = target;
                },
            }
        },

        .jcc_rel8, .jcc_rel32 => {
            const condMet = x64_decoder.evalCond(self.regs.rflags, d.cond);
            const transfer = x64_decoder.highway.directControl(.conditional_jump, self.regs.rip, d.len, d.addr, condMet);
            if (condMet) {
                self.logControlFlow("jcc_taken", self.regs.rip, transfer.target, d.len, null);
                self.regs.rip = transfer.target;
            }
        },

        .bsf_reg_reg,
        .bsf_reg_mem,
        .bsr_reg_reg,
        .bsr_reg_mem,
        .tzcnt_reg_reg,
        .tzcnt_reg_mem,
        .lzcnt_reg_reg,
        .lzcnt_reg_mem,
        => self.executeBitScan(d),

        .popcnt_reg_reg, .popcnt_reg_mem => {
            const source = if (d.op == .popcnt_reg_mem)
                self.readMemVal(d.addr, d.size)
            else
                self.regVal(d.src_reg, d.size);
            const result = populationCount(d.size, source, self.regs.rflags);
            self.setReg(d.dst_reg, d.size, result.value);
            self.regs.rflags = result.rflags;
        },

        .bswap_reg => self.setReg(d.dst_reg, d.size, x64_decoder.byteSwap(d.size, self.regVal(d.dst_reg, d.size))),

        .crc32_reg_reg, .crc32_reg_mem => {
            const source = if (d.op == .crc32_reg_mem)
                self.readMemVal(d.addr, d.size)
            else
                self.regVal(d.src_reg, d.size);
            const crc = crc32cAccumulator(@truncate(self.regVal(d.dst_reg, .bits32)), source, d.size);
            self.setReg(d.dst_reg, d.dst_size, crc);
        },

        .rol_reg_cl,
        .rol_mem_cl,
        .ror_reg_cl,
        .ror_mem_cl,
        .rol_reg_imm,
        .rol_mem_imm,
        .ror_reg_imm,
        .ror_mem_imm,
        => self.executeRotate(d),

        .shl_reg_cl, .shl_mem_cl => {
            const sz = d.size;
            const is_mem = d.op == .shl_mem_cl;
            const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
            const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
            const r = (a & maskForSize(sz)) << @as(u6, @intCast(count));
            if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
        },
        .shr_reg_cl, .shr_mem_cl => {
            const sz = d.size;
            const is_mem = d.op == .shr_mem_cl;
            const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
            const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
            const r = (a & maskForSize(sz)) >> @as(u6, @intCast(count));
            if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
        },
        .sar_reg_cl, .sar_mem_cl => {
            const sz = d.size;
            const is_mem = d.op == .sar_mem_cl;
            const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
            const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
            const r = arithmeticShiftRight(a, sz, @intCast(count));
            if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
        },
        .shr_reg_imm, .shr_mem_imm => {
            const sz = d.size;
            const is_mem = d.op == .shr_mem_imm;
            const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
            const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
            const r = (a & maskForSize(sz)) >> @as(u6, @intCast(count));
            if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
        },
        .shl_reg_imm, .shl_mem_imm => {
            const sz = d.size;
            const is_mem = d.op == .shl_mem_imm;
            const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
            const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
            const r = (a & maskForSize(sz)) << @as(u6, @intCast(count));
            if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
        },
        .sar_reg_imm, .sar_mem_imm => {
            const sz = d.size;
            const is_mem = d.op == .sar_mem_imm;
            const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
            const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
            const r = arithmeticShiftRight(a, sz, @intCast(count));
            if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
        },

        .mul_reg8 => {
            const a = self.regVal(.al_ax_eax_rax, .bits8);
            const b = self.regVal(d.dst_reg, .bits8);
            const r = a * b;
            self.setReg(.al_ax_eax_rax, .bits16, r);
            self.setFlag(RFL_CF, r >> 8 != 0);
            self.setFlag(RFL_OF, r >> 8 != 0);
        },
        .mul_reg16 => {
            const a = self.regVal(.al_ax_eax_rax, .bits16);
            const b = self.regVal(d.dst_reg, .bits16);
            const r: u32 = @as(u32, @truncate(a)) * @as(u32, @truncate(b));
            self.setReg(.al_ax_eax_rax, .bits16, @truncate(r));
            self.setReg(.dl_dx_edx_rdx, .bits16, @truncate(r >> 16));
            self.setFlag(RFL_CF, r >> 16 != 0);
            self.setFlag(RFL_OF, r >> 16 != 0);
        },
        .mul_reg32 => {
            const a = self.regVal(.al_ax_eax_rax, .bits32);
            const b = self.regVal(d.dst_reg, .bits32);
            const r: u64 = @as(u64, a) * @as(u64, b);
            self.setReg(.al_ax_eax_rax, .bits32, @truncate(r));
            self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(r >> 32));
            self.setFlag(RFL_CF, r >> 32 != 0);
            self.setFlag(RFL_OF, r >> 32 != 0);
        },
        .mul_reg64 => {
            const a = self.regs.rax;
            const b = self.regVal(d.dst_reg, .bits64);
            @setRuntimeSafety(false);
            const r = @as(u128, a) * @as(u128, b);
            self.regs.rax = @truncate(r);
            self.regs.rdx = @truncate(r >> 64);
            self.setFlag(RFL_CF, self.regs.rdx != 0);
            self.setFlag(RFL_OF, self.regs.rdx != 0);
        },

        .div_mem16, .div_reg16 => {
            const divisor: u16 = @truncate(if (d.op == .div_mem16) self.readMemVal(d.addr, .bits16) else self.regVal(d.dst_reg, .bits16));
            if (divisor == 0) return self.raiseDivideError();
            const dividend = (@as(u32, @truncate(self.regs.rdx)) << 16) | @as(u16, @truncate(self.regs.rax));
            const quotient = dividend / divisor;
            if (quotient > std.math.maxInt(u16)) return self.raiseDivideError();
            self.setReg(.al_ax_eax_rax, .bits16, quotient);
            self.setReg(.dl_dx_edx_rdx, .bits16, dividend % divisor);
        },
        .div_mem32, .div_reg32 => {
            const divisor: u32 = @truncate(if (d.op == .div_mem32) self.readMemVal(d.addr, .bits32) else self.regVal(d.dst_reg, .bits32));
            if (divisor == 0) return self.raiseDivideError();
            const dividend = (@as(u64, @truncate(self.regs.rdx)) << 32) | @as(u32, @truncate(self.regs.rax));
            const quotient = dividend / divisor;
            if (quotient > std.math.maxInt(u32)) return self.raiseDivideError();
            self.setReg(.al_ax_eax_rax, .bits32, quotient);
            self.setReg(.dl_dx_edx_rdx, .bits32, dividend % divisor);
        },
        .div_mem64, .div_reg64 => {
            const divisor = if (d.op == .div_mem64) self.readMemVal(d.addr, .bits64) else self.regVal(d.dst_reg, .bits64);
            if (divisor == 0) return self.raiseDivideError();
            const dividend = (@as(u128, self.regs.rdx) << 64) | self.regs.rax;
            const quotient = dividend / divisor;
            if (quotient > std.math.maxInt(u64)) return self.raiseDivideError();
            self.regs.rax = @truncate(quotient);
            self.regs.rdx = @truncate(dividend % divisor);
        },
        .idiv_mem16, .idiv_reg16 => {
            const raw_divisor = if (d.op == .idiv_mem16) self.readMemVal(d.addr, .bits16) else self.regVal(d.dst_reg, .bits16);
            const divisor: i16 = @bitCast(@as(u16, @truncate(raw_divisor)));
            if (divisor == 0) return self.raiseDivideError();
            const dividend_bits = (@as(u32, @truncate(self.regs.rdx)) << 16) | @as(u16, @truncate(self.regs.rax));
            const dividend: i32 = @bitCast(dividend_bits);
            const quotient = @divTrunc(dividend, @as(i32, divisor));
            if (quotient < std.math.minInt(i16) or quotient > std.math.maxInt(i16)) return self.raiseDivideError();
            const remainder = @rem(dividend, @as(i32, divisor));
            self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @intCast(quotient)))));
            self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(@as(i16, @intCast(remainder)))));
        },
        .idiv_mem32, .idiv_reg32 => {
            const raw_divisor = if (d.op == .idiv_mem32) self.readMemVal(d.addr, .bits32) else self.regVal(d.dst_reg, .bits32);
            const divisor: i32 = @bitCast(@as(u32, @truncate(raw_divisor)));
            if (divisor == 0) return self.raiseDivideError();
            const dividend_bits = (@as(u64, @truncate(self.regs.rdx)) << 32) | @as(u32, @truncate(self.regs.rax));
            const dividend: i64 = @bitCast(dividend_bits);
            const quotient = @divTrunc(dividend, @as(i64, divisor));
            if (quotient < std.math.minInt(i32) or quotient > std.math.maxInt(i32)) return self.raiseDivideError();
            const remainder = @rem(dividend, @as(i64, divisor));
            self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, @intCast(quotient)))));
            self.setReg(.dl_dx_edx_rdx, .bits32, @as(u32, @bitCast(@as(i32, @intCast(remainder)))));
        },
        .idiv_mem64, .idiv_reg64 => {
            const raw_divisor = if (d.op == .idiv_mem64) self.readMemVal(d.addr, .bits64) else self.regVal(d.dst_reg, .bits64);
            const divisor: i64 = @bitCast(raw_divisor);
            if (divisor == 0) return self.raiseDivideError();
            const dividend_bits = (@as(u128, self.regs.rdx) << 64) | self.regs.rax;
            const dividend: i128 = @bitCast(dividend_bits);
            const quotient = @divTrunc(dividend, @as(i128, divisor));
            if (quotient < std.math.minInt(i64) or quotient > std.math.maxInt(i64)) return self.raiseDivideError();
            const remainder = @rem(dividend, @as(i128, divisor));
            self.regs.rax = @bitCast(@as(i64, @intCast(quotient)));
            self.regs.rdx = @bitCast(@as(i64, @intCast(remainder)));
        },
        .imul_reg64_reg64, .imul_reg32_reg32 => {
            const sz = if (d.op == .imul_reg64_reg64) Size.bits64 else Size.bits32;
            const a = self.regVal(d.dst_reg, sz);
            const b = self.regVal(d.src_reg, sz);
            const r = a *% b;
            self.setReg(d.dst_reg, sz, r);
        },
        .imul_reg64_mem64, .imul_reg32_mem32 => {
            const sz = if (d.op == .imul_reg64_mem64) Size.bits64 else Size.bits32;
            const a = self.regVal(d.dst_reg, sz);
            const b = self.readMemVal(d.addr, sz);
            const r = a *% b;
            self.setReg(d.dst_reg, sz, r);
        },
        .imul_reg64_reg64_imm8, .imul_reg32_reg32_imm8 => {
            const sz = if (d.op == .imul_reg64_reg64_imm8) Size.bits64 else Size.bits32;
            // Three-operand IMUL reads r/m as its source and does not use
            // the old destination value. Using dst here corrupts pointer
            // and index scaling whenever source and destination differ.
            const r = threeOperandImulResult(&self.regs, d, sz);
            self.setReg(d.dst_reg, sz, r);
        },
        .imul_reg64_mem64_imm8, .imul_reg32_mem32_imm8 => {
            const sz = if (d.op == .imul_reg64_mem64_imm8) Size.bits64 else Size.bits32;
            const a = self.readMemVal(d.addr, sz);
            const r = a *% d.imm;
            self.setReg(d.dst_reg, sz, r);
        },

        .lea_reg_mem => {
            self.setReg(d.dst_reg, d.size, d.addr);
        },

        .movzx_reg32_mem8 => {
            const val = if (d.is_reg_form)
                self.regVal(d.src_reg, .bits8)
            else
                self.readMemVal(d.addr, .bits8);
            self.setReg(d.dst_reg, d.size, val);
        },
        .movzx_reg32_mem16 => {
            const val = if (d.is_reg_form)
                self.regVal(d.src_reg, .bits16)
            else
                self.readMemVal(d.addr, .bits16);
            self.setReg(d.dst_reg, d.size, val);
        },
        .movsx_reg32_mem8 => {
            const val = if (d.is_reg_form)
                self.regVal(d.src_reg, .bits8)
            else
                self.readMemVal(d.addr, .bits8);
            const signed_val = @as(u32, @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(val)))))));
            self.setReg(d.dst_reg, d.size, signed_val);
        },
        .movsx_reg32_mem16 => {
            const val = if (d.is_reg_form)
                self.regVal(d.src_reg, .bits16)
            else
                self.readMemVal(d.addr, .bits16);
            const signed_val = @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(val)))))));
            self.setReg(d.dst_reg, d.size, signed_val);
        },
        .movsxd_reg64_reg32 => {
            const val = self.regVal(d.src_reg, .bits32);
            const signed_val = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(val)))))));
            self.setReg(d.dst_reg, .bits64, signed_val);
        },
        .movsxd_reg64_mem32 => {
            const val = self.readMemVal(d.addr, .bits32);
            const signed_val = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(val)))))));
            self.setReg(d.dst_reg, .bits64, signed_val);
        },

        .cbw => {
            self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(@as(u8, @truncate(self.regs.rax))))))));
        },
        .cwde => {
            self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(self.regs.rax))))))));
        },
        .cdqe => {
            self.regs.rax = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regs.rax)))))));
        },
        .cwd => {
            const val = self.regVal(.al_ax_eax_rax, .bits16);
            const sign = @as(u16, @bitCast(@as(i16, @intCast(val)))) >> 15;
            self.setReg(.dl_dx_edx_rdx, .bits16, if (sign != 0) 0xFFFF else 0);
        },
        .cdq => {
            const val = self.regVal(.al_ax_eax_rax, .bits32);
            const sign = @as(u32, @bitCast(@as(i32, @intCast(val)))) >> 31;
            self.setReg(.dl_dx_edx_rdx, .bits32, if (sign != 0) 0xFFFF_FFFF else 0);
        },
        .cqo => {
            const val = self.regs.rax;
            const sign = (val & 0x8000_0000_0000_0000) != 0;
            self.regs.rdx = if (sign) 0xFFFF_FFFF_FFFF_FFFF else 0;
        },

        .cmovcc_reg_reg => {
            if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                self.setReg(d.dst_reg, d.size, self.regVal(d.src_reg, d.size));
            }
        },
        .cmovcc_reg_mem => {
            if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                self.setReg(d.dst_reg, d.size, self.readMemVal(d.addr, d.size));
            }
        },

        .setcc_reg8 => {
            if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                self.setReg(d.dst_reg, .bits8, 1);
            } else {
                self.setReg(d.dst_reg, .bits8, 0);
            }
        },
        .setcc_mem8 => {
            if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                self.writeMemVal(d.addr, .bits8, 1);
            } else {
                self.writeMemVal(d.addr, .bits8, 0);
            }
        },

        .cmpxchg_mem8_reg8,
        .cmpxchg_mem16_reg16,
        .cmpxchg_mem32_reg32,
        .cmpxchg_mem64_reg64,
        .cmpxchg_reg8_reg8,
        .cmpxchg_reg16_reg16,
        .cmpxchg_reg32_reg32,
        .cmpxchg_reg64_reg64,
        => {
            const size = d.size;
            const expected = self.regVal(.al_ax_eax_rax, size);
            const actual = if (d.is_reg_form)
                self.regVal(d.dst_reg, size)
            else
                self.readMemVal(d.addr, size);
            const replacement = self.regVal(d.src_reg, size);
            const rax_before = self.regs.rax;
            const rflags_before = self.regs.rflags;
            const outcome = atomic_compare_exchange.evaluate(expected, actual, replacement);
            const matched = outcome.matched;
            // x86 CMPXCHG: flags reflect AL − DEST (= expected − actual)
            const subtract_result = expected -% actual;
            self.setFlagsSub(expected, actual, subtract_result, size);
            if (matched) {
                if (d.is_reg_form) {
                    self.setReg(d.dst_reg, size, outcome.destination);
                } else {
                    self.writeMemVal(d.addr, size, outcome.destination);
                }
            } else {
                self.setReg(.al_ax_eax_rax, size, outcome.accumulator);
            }
            self.atomic_cmpxchg.record(matched);
            if (!matched and self.timer_queue_watch.active and d.addr == self.timer_queue_watch.state_addr) {
                const expected_name = guest_assertion_recovery.timerQueueStateName(@as(u8, @truncate(expected)));
                const actual_name = guest_assertion_recovery.timerQueueStateName(@as(u8, @truncate(actual)));
                machoCapturePrint(
                    "  timer queue CMPXCHG mismatch on watched state: expected={s}({d}) actual={s}({d}) addr=0x{x} rip=0x{x} thread=0x{x}\n",
                    .{ expected_name, @as(u8, @truncate(expected)), actual_name, @as(u8, @truncate(actual)), d.addr, self.regs.rip, self.active_guest_thread },
                );
            }
            self.logAtomicDiagnostic(matched, size, d.addr, expected, actual, replacement, d.lock, rax_before, rflags_before);
            if (d.lock) releaseBarrier();
        },

        .cmpxchg8b_mem, .cmpxchg16b_mem => {
            const is_16b = d.op == .cmpxchg16b_mem;
            const expected_lo = self.regVal(.al_ax_eax_rax, .bits32);
            const expected_hi = self.regVal(.dl_dx_edx_rdx, if (is_16b) .bits64 else .bits32);
            const replacement_lo = self.regVal(.cl_cx_ecx_rcx, if (is_16b) .bits64 else .bits32);
            const replacement_hi = self.regVal(.bl_bx_ebx_rbx, if (is_16b) .bits64 else .bits32);
            const rax_before = self.regs.rax;
            const rflags_before = self.regs.rflags;

            const actual_lo = self.readMemVal(d.addr, if (is_16b) .bits64 else .bits32);
            const actual_hi = if (is_16b) self.readMemVal(d.addr + 8, .bits64) else 0;

            const matched = expected_lo == actual_lo and expected_hi == actual_hi;

            if (matched) {
                self.writeMemVal(d.addr, if (is_16b) .bits64 else .bits32, replacement_lo);
                if (is_16b) self.writeMemVal(d.addr + 8, .bits64, replacement_hi);
            } else {
                self.setReg(.al_ax_eax_rax, if (is_16b) .bits64 else .bits32, actual_lo);
                self.setReg(.dl_dx_edx_rdx, if (is_16b) .bits64 else .bits32, actual_hi);
            }

            self.regs.rflags &= ~RFL_ZF;
            self.regs.rflags |= if (matched) RFL_ZF else 0;

            self.atomic_cmpxchg.record(matched);
            if (is_16b) {
                self.logAtomicDiagnostic(matched, .bits64, d.addr, expected_lo, actual_lo, replacement_lo, d.lock, rax_before, rflags_before);
            } else {
                self.logAtomicDiagnostic(matched, .bits32, d.addr, expected_lo, actual_lo, replacement_lo, d.lock, rax_before, rflags_before);
            }
            if (d.lock) releaseBarrier();
        },

        .xchg_mem32_reg32 => {
            // XCHG with memory is architecturally always atomic (implicit LOCK#)
            // Acquire+release semantics via full barrier (XCHG implies LOCK)
            releaseBarrier();
            const a = self.readMemVal(d.addr, .bits32);
            const b = self.regVal(d.src_reg, .bits32);
            self.writeMemVal(d.addr, .bits32, b);
            self.setReg(d.src_reg, .bits32, a);
            releaseBarrier();
        },
        .xchg_mem64_reg64 => {
            releaseBarrier();
            const a = self.readMemVal(d.addr, .bits64);
            const b = self.regVal(d.src_reg, .bits64);
            self.writeMemVal(d.addr, .bits64, b);
            self.setReg(d.src_reg, .bits64, a);
            releaseBarrier();
        },
        .xchg_reg32_reg32 => {
            const a = self.regVal(d.dst_reg, .bits32);
            const b = self.regVal(d.src_reg, .bits32);
            self.setReg(d.dst_reg, .bits32, b);
            self.setReg(d.src_reg, .bits32, a);
        },
        .xchg_reg64_reg64 => {
            const a = self.regVal(d.dst_reg, .bits64);
            const b = self.regVal(d.src_reg, .bits64);
            self.setReg(d.dst_reg, .bits64, b);
            self.setReg(d.src_reg, .bits64, a);
        },
        .xadd_mem8_reg8, .xadd_mem32_reg32, .xadd_mem64_reg64 => {
            const sz: Size = if (d.op == .xadd_mem64_reg64) .bits64 else if (d.op == .xadd_mem8_reg8) .bits8 else .bits32;
            const old_mem = self.readMemVal(d.addr, sz);
            const old_reg = self.regVal(d.src_reg, sz);
            const result = old_mem +% old_reg;
            self.writeMemVal(d.addr, sz, result);
            self.setReg(d.src_reg, sz, old_mem);
            self.setFlagsAdd(old_mem, old_reg, result, sz);
            if (d.lock) releaseBarrier();
        },

        .xorps_xmm_xmm => {
            const dst = d.xmm_dst;
            const src = d.xmm_src;
            for (&self.xmm[dst], self.xmm[src]) |*d8, s8| d8.* = d8.* ^ s8;
        },
        .movups_xmm_xmm, .movaps_xmm_xmm => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
        },
        .movups_xmm_mem, .movaps_xmm_mem => {
            self.xmm[d.xmm_dst] = self.readMem128(d.addr);
        },
        .movups_mem_xmm, .movaps_mem_xmm => {
            self.writeMem128(d.addr, self.xmm[d.xmm_src]);
        },
        .vmovd_xmm_reg32, .vmovd_xmm_mem32 => {
            const value: u32 = @truncate(if (d.op == .vmovd_xmm_reg32)
                self.regVal(d.src_reg, .bits32)
            else
                self.readMemVal(d.addr, .bits32));
            @memset(&self.xmm[d.xmm_dst], 0);
            @memset(&self.ymm_hi[d.xmm_dst], 0);
            std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], value, .little);
        },
        .vmovq_xmm_reg64, .vmovq_xmm_mem64 => {
            const value = if (d.op == .vmovq_xmm_reg64)
                self.regVal(d.src_reg, .bits64)
            else
                self.readMemVal(d.addr, .bits64);
            @memset(&self.xmm[d.xmm_dst], 0);
            @memset(&self.ymm_hi[d.xmm_dst], 0);
            std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], value, .little);
        },
        .vmovq_reg64_xmm, .vmovq_mem64_xmm => {
            const value = std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little);
            if (d.op == .vmovq_reg64_xmm) {
                self.setReg(d.dst_reg, .bits64, value);
            } else {
                self.writeMemVal(d.addr, .bits64, value);
            }
        },
        .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8 => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            const value: u8 = @truncate(if (d.op == .vpinsrb_xmm_xmm_reg32)
                self.regVal(d.src_reg, .bits32)
            else
                self.readMemVal(d.addr, .bits8));
            self.xmm[d.xmm_dst][@intCast(d.imm & 0x0F)] = value;
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        },
        .vpshufb => {
            const source_low = self.xmm[d.xmm_src];
            const mask_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = shuffleBytes(source_low, mask_low);
            if (d.vector_256) {
                const source_high = self.ymm_hi[d.xmm_src];
                const mask_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = shuffleBytes(source_high, mask_high);
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vpcmpeqb, .vpcmpeqw, .vpcmpeqd, .vpcmpeqq, .vpcmpgtb, .vpcmpgtw, .vpcmpgtd, .vpcmpgtq => {
            const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = applyVexCompare(self.xmm[d.xmm_src], rhs_low, d.op);
            if (d.vector_256) {
                const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = applyVexCompare(self.ymm_hi[d.xmm_src], rhs_high, d.op);
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vptest => {
            const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            const low_zf = bitwiseAndAllZero(self.xmm[d.xmm_src], rhs_low);
            const low_cf = bitwiseAndNotAllZero(self.xmm[d.xmm_src], rhs_low);
            if (d.vector_256) {
                const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.regs.rflags &= ~(RFL_OF | RFL_SF | RFL_ZF | RFL_AF | RFL_PF | RFL_CF);
                if (low_zf and bitwiseAndAllZero(self.ymm_hi[d.xmm_src], rhs_high)) self.regs.rflags |= RFL_ZF;
                if (low_cf and bitwiseAndNotAllZero(self.ymm_hi[d.xmm_src], rhs_high)) self.regs.rflags |= RFL_CF;
            } else {
                self.regs.rflags &= ~(RFL_OF | RFL_SF | RFL_ZF | RFL_AF | RFL_PF | RFL_CF);
                if (low_zf) self.regs.rflags |= RFL_ZF;
                if (low_cf) self.regs.rflags |= RFL_CF;
            }
        },
        .vpunpckldq => {
            const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = unpackLowDwords(self.xmm[d.xmm_src], rhs_low);
            if (d.vector_256) {
                const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = unpackLowDwords(self.ymm_hi[d.xmm_src], rhs_high);
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vpunpcklqdq => {
            const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = unpackLowQwords(self.xmm[d.xmm_src], rhs_low);
            if (d.vector_256) {
                const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = unpackLowQwords(self.ymm_hi[d.xmm_src], rhs_high);
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vpermilpd => {
            const source_low = if (d.is_reg_form) self.xmm[d.xmm_src] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = permutePackedDoubles(source_low, @truncate(d.imm));
            if (d.vector_256) {
                const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = permutePackedDoubles(source_high, @truncate(d.imm >> 2));
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vmovdqu_xmm_xmm, .vmovdqa_xmm_xmm, .vmovups_xmm_xmm, .vmovaps_xmm_xmm, .vmovupd_xmm_xmm, .vmovapd_xmm_xmm => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        },
        .vmovdqu_xmm_mem, .vmovdqa_xmm_mem, .vmovups_xmm_mem, .vmovaps_xmm_mem, .vmovupd_xmm_mem, .vmovapd_xmm_mem => {
            self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        },
        .vmovdqu_mem_xmm, .vmovdqa_mem_xmm, .vmovups_mem_xmm, .vmovaps_mem_xmm, .vmovupd_mem_xmm, .vmovapd_mem_xmm => {
            self.writeMem128(d.addr, self.xmm[d.xmm_src]);
        },
        .vmovdqu_ymm_ymm, .vmovdqa_ymm_ymm, .vmovups_ymm_ymm, .vmovaps_ymm_ymm, .vmovupd_ymm_ymm, .vmovapd_ymm_ymm => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            self.ymm_hi[d.xmm_dst] = self.ymm_hi[d.xmm_src];
        },
        .vmovdqu_ymm_mem, .vmovdqa_ymm_mem, .vmovups_ymm_mem, .vmovaps_ymm_mem, .vmovupd_ymm_mem, .vmovapd_ymm_mem => {
            self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            self.ymm_hi[d.xmm_dst] = self.readMem128(d.addr + 16);
        },
        .vmovdqu_mem_ymm, .vmovdqa_mem_ymm, .vmovups_mem_ymm, .vmovaps_mem_ymm, .vmovupd_mem_ymm, .vmovapd_mem_ymm => {
            self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            self.writeMem128(d.addr + 16, self.ymm_hi[d.xmm_src]);
        },
        .vmovss_xmm_mem => {
            @memset(&self.xmm[d.xmm_dst], 0);
            @memset(&self.ymm_hi[d.xmm_dst], 0);
            std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @truncate(self.readMemVal(d.addr, .bits32)), .little);
        },
        .vmovss_mem_xmm => {
            self.writeMemVal(d.addr, .bits32, std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little));
        },
        .vmovsd_xmm_mem => {
            @memset(&self.xmm[d.xmm_dst], 0);
            @memset(&self.ymm_hi[d.xmm_dst], 0);
            std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], self.readMemVal(d.addr, .bits64), .little);
        },
        .vmovsd_mem_xmm => {
            self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
        },
        .vmovlps_xmm_xmm_mem64, .vmovlpd_xmm_xmm_mem64 => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], self.readMemVal(d.addr, .bits64), .little);
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        },
        .vmovlps_mem64_xmm, .vmovlpd_mem64_xmm => {
            self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
        },
        .vmovhps_xmm_xmm_mem64, .vmovhpd_xmm_xmm_mem64 => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            std.mem.writeInt(u64, self.xmm[d.xmm_dst][8..16], self.readMemVal(d.addr, .bits64), .little);
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        },
        .vmovhps_mem64_xmm, .vmovhpd_mem64_xmm => {
            self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][8..16], .little));
        },
        .vmovshdup, .vmovsldup, .vmovddup => {
            const source_low = if (d.is_reg_form) self.xmm[d.xmm_src] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = duplicateVectorElements(d.op, source_low);
            if (d.vector_256) {
                const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = duplicateVectorElements(d.op, source_high);
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vzeroupper => {
            for (&self.ymm_hi) |*upper| @memset(upper, 0);
        },
        .vcvtsi2ss_xmm_reg, .vcvtsi2ss_xmm_mem => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            @memset(&self.ymm_hi[d.xmm_dst], 0);
            const integer: i64 = if (d.size == .bits64)
                @bitCast(if (d.op == .vcvtsi2ss_xmm_reg) self.regVal(d.src_reg, .bits64) else self.readMemVal(d.addr, .bits64))
            else
                @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2ss_xmm_reg) self.regVal(d.src_reg, .bits32) else self.readMemVal(d.addr, .bits32)))));
            const converted: f32 = @floatFromInt(integer);
            std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(converted), .little);
        },
        .vcvtsi2sd_xmm_reg, .vcvtsi2sd_xmm_mem => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            @memset(&self.ymm_hi[d.xmm_dst], 0);
            const integer: i64 = if (d.size == .bits64)
                @bitCast(if (d.op == .vcvtsi2sd_xmm_reg) self.regVal(d.src_reg, .bits64) else self.readMemVal(d.addr, .bits64))
            else
                @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2sd_xmm_reg) self.regVal(d.src_reg, .bits32) else self.readMemVal(d.addr, .bits32)))));
            const converted: f64 = @floatFromInt(integer);
            std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(converted), .little);
        },
        .vcvtss2sd => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            @memset(&self.ymm_hi[d.xmm_dst], 0);
            const source_bits = if (d.is_reg_form)
                std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
            else
                @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
            const converted: f64 = @floatCast(@as(f32, @bitCast(source_bits)));
            std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(converted), .little);
        },
        .vcvtsd2ss => {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            @memset(&self.ymm_hi[d.xmm_dst], 0);
            const source_bits = if (d.is_reg_form)
                std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
            else
                self.readMemVal(d.addr, .bits64);
            const converted: f32 = @floatCast(@as(f64, @bitCast(source_bits)));
            std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(converted), .little);
        },
        .vaddss, .vmulss, .vsubss, .vdivss => {
            self.executeVexScalarF32(d, vexArithmeticForOp(d.op));
        },
        .vaddsd, .vmulsd, .vsubsd, .vdivsd => {
            self.executeVexScalarF64(d, vexArithmeticForOp(d.op));
        },
        .vaddps, .vmulps, .vsubps, .vdivps => {
            self.executeVexPackedF32(d, vexArithmeticForOp(d.op));
        },
        .vaddpd, .vmulpd, .vsubpd, .vdivpd => {
            self.executeVexPackedF64(d, vexArithmeticForOp(d.op));
        },
        .vucomiss => {
            const lhs: f32 = @bitCast(std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little));
            const rhs_bits = if (d.is_reg_form)
                std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
            else
                @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
            self.setVexComparisonFlags(lhs, @as(f32, @bitCast(rhs_bits)));
        },
        .vucomisd => {
            const lhs: f64 = @bitCast(std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
            const rhs_bits = if (d.is_reg_form)
                std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
            else
                self.readMemVal(d.addr, .bits64);
            self.setVexComparisonFlags(lhs, @as(f64, @bitCast(rhs_bits)));
        },
        .vroundss => {
            const source1 = self.xmm[d.xmm_src];
            const source2_bits = if (d.is_reg_form)
                std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
            else
                @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
            self.xmm[d.xmm_dst] = source1;
            std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(roundVexFloat(f32, @bitCast(source2_bits), @truncate(d.imm))), .little);
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        },
        .vroundsd => {
            const source1 = self.xmm[d.xmm_src];
            const source2_bits = if (d.is_reg_form)
                std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
            else
                self.readMemVal(d.addr, .bits64);
            self.xmm[d.xmm_dst] = source1;
            std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(roundVexFloat(f64, @bitCast(source2_bits), @truncate(d.imm))), .little);
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        },
        .vroundps => {
            const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = roundVexPackedF32(source_low, @truncate(d.imm));
            if (d.vector_256) {
                const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = roundVexPackedF32(source_high, @truncate(d.imm));
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vroundpd => {
            const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = roundVexPackedF64(source_low, @truncate(d.imm));
            if (d.vector_256) {
                const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = roundVexPackedF64(source_high, @truncate(d.imm));
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vcvttss2si, .vcvtss2si => {
            const source_bits = if (d.is_reg_form)
                std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little)
            else
                @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
            const source: f32 = @bitCast(source_bits);
            self.setReg(d.dst_reg, d.size, convertVexFloatToSigned(f32, source, d.size, d.op == .vcvttss2si));
        },
        .vcvttsd2si, .vcvtsd2si => {
            const source_bits = if (d.is_reg_form)
                std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little)
            else
                self.readMemVal(d.addr, .bits64);
            const source: f64 = @bitCast(source_bits);
            self.setReg(d.dst_reg, d.size, convertVexFloatToSigned(f64, source, d.size, d.op == .vcvttsd2si));
        },
        .pmovmskb, .vpmovmskb => {
            var mask: u32 = 0;
            for (self.xmm[d.xmm_src], 0..) |byte, i| {
                if (byte & 0x80 != 0) mask |= @as(u32, 1) << @intCast(i);
            }
            self.setReg(d.dst_reg, .bits32, mask);
        },
        .vpmovmskb_ymm => {
            var mask: u32 = 0;
            for (self.xmm[d.xmm_src], 0..) |byte, i| {
                if (byte & 0x80 != 0) mask |= @as(u32, 1) << @intCast(i);
            }
            for (self.ymm_hi[d.xmm_src], 0..) |byte, i| {
                if (byte & 0x80 != 0) mask |= @as(u32, 1) << @intCast(i + 16);
            }
            self.setReg(d.dst_reg, .bits32, mask);
        },
        .vandps, .vandpd, .vandnps, .vandnpd, .vorps, .vorpd, .vxorps, .vxorpd, .vpor, .vpand, .vpandn, .vpxor => {
            self.executeVexBitwise(d, vexBitwiseForOp(d.op));
        },
        .vpshufd => {
            const control: u8 = @truncate(d.imm);
            const source_low = if (d.is_reg_form) self.xmm[d.xmm_src] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = shufflePackedDwords(source_low, control);
            if (d.vector_256) {
                const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = shufflePackedDwords(source_high, control);
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vpmuludq => {
            const source1_low = self.xmm[d.xmm_src];
            const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = multiplyUnsignedEvenDwords(source1_low, source2_low);
            if (d.vector_256) {
                const source1_high = self.ymm_hi[d.xmm_src];
                const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = multiplyUnsignedEvenDwords(source1_high, source2_high);
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vpblendw => {
            const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = blendPackedWords(self.xmm[d.xmm_src], rhs_low, @truncate(d.imm));
            if (d.vector_256) {
                const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = blendPackedWords(self.ymm_hi[d.xmm_src], rhs_high, @truncate(d.imm));
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vpinsrd, .vpinsrq, .vpinsrw => {
            const index: u8 = @truncate(d.imm);
            const lane_count: u8 = if (d.op == .vpinsrd) 4 else if (d.op == .vpinsrq) 2 else 8;
            const element_size: u8 = if (d.op == .vpinsrd) 4 else if (d.op == .vpinsrq) 8 else 2;
            const clamped_index = index % lane_count;
            const offset = clamped_index * element_size;

            // Copy source XMM to destination
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];

            // Insert the element
            if (d.is_reg_form) {
                // From GPR register (low dword/qword/word)
                const gpr_val = self.regVal(@as(RegId, @enumFromInt(d.xmm_src2)), switch (d.op) {
                    .vpinsrd => .bits32,
                    .vpinsrq => .bits64,
                    .vpinsrw => .bits16,
                    else => .bits32,
                });
                if (d.op == .vpinsrd) {
                    std.mem.writeInt(u32, self.xmm[d.xmm_dst][offset..][0..4], @truncate(gpr_val), .little);
                } else if (d.op == .vpinsrq) {
                    std.mem.writeInt(u64, self.xmm[d.xmm_dst][offset..][0..8], gpr_val, .little);
                } else {
                    std.mem.writeInt(u16, self.xmm[d.xmm_dst][offset..][0..2], @truncate(gpr_val), .little);
                }
            } else {
                // From memory (read 32/64/16 bits)
                const mem_value = if (d.op == .vpinsrd)
                    self.readMemVal(d.addr, .bits32)
                else if (d.op == .vpinsrq)
                    self.readMemVal(d.addr, .bits64)
                else
                    self.readMemVal(d.addr, .bits16);

                if (d.op == .vpinsrd) {
                    std.mem.writeInt(u32, self.xmm[d.xmm_dst][offset..][0..4], @intCast(mem_value), .little);
                } else if (d.op == .vpinsrq) {
                    std.mem.writeInt(u64, self.xmm[d.xmm_dst][offset..][0..8], mem_value, .little);
                } else {
                    std.mem.writeInt(u16, self.xmm[d.xmm_dst][offset..][0..2], @intCast(mem_value), .little);
                }
            }

            if (d.vector_256) {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vpunpckhbw, .vpunpckhwd, .vpunpckhdq, .vpunpcklbw, .vpunpcklwd => {
            // VPUNPCK unpack operations - no-op for now
            // TODO: Implement actual unpack semantics
            if (d.is_reg_form) {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            } else {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            }
            if (d.vector_256) {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vpslld, .vpsllq, .vpsllw, .vpslldq, .vpsrld, .vpsrlq, .vpsrlw, .vpsrldq => {
            const source_low = if (d.uses_imm and !d.is_reg_form) self.readMem128(d.addr) else self.xmm[d.xmm_src];
            const count = if (d.uses_imm)
                d.imm
            else blk: {
                const count_source = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                break :blk std.mem.readInt(u64, count_source[0..8], .little);
            };
            const left = d.op == .vpsllw or d.op == .vpslld or d.op == .vpsllq or d.op == .vpslldq;
            if (d.op == .vpslldq or d.op == .vpsrldq) {
                self.xmm[d.xmm_dst] = shiftPackedBytes(source_low, count, left);
            } else {
                self.xmm[d.xmm_dst] = shiftPackedElements(source_low, packedShiftLaneBits(d.op), count, left);
            }
            if (d.vector_256) {
                const source_high = if (d.uses_imm and !d.is_reg_form) self.readMem128(d.addr + 16) else self.ymm_hi[d.xmm_src];
                if (d.op == .vpslldq or d.op == .vpsrldq) {
                    self.ymm_hi[d.xmm_dst] = shiftPackedBytes(source_high, count, left);
                } else {
                    self.ymm_hi[d.xmm_dst] = shiftPackedElements(source_high, packedShiftLaneBits(d.op), count, left);
                }
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
        .vpsubb, .vpsubd, .vpsubq, .vpsubw, .vpaddb, .vpaddd, .vpaddq, .vpaddw, .vpmullw => {
            const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            self.xmm[d.xmm_dst] = packedIntegerBinary(
                self.xmm[d.xmm_src],
                rhs_low,
                packedIntegerLaneBits(d.op),
                packedIntegerOperation(d.op),
            );
            if (d.vector_256) {
                const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                self.ymm_hi[d.xmm_dst] = packedIntegerBinary(
                    self.ymm_hi[d.xmm_src],
                    rhs_high,
                    packedIntegerLaneBits(d.op),
                    packedIntegerOperation(d.op),
                );
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },

        .syscall => {
            const boundary = x64_decoder.highway.systemBoundary(.macho64, .syscall, self.regs.rax, "");
            if (boundary.disposition != .forward) {
                self.faulted = true;
                self.terminated = true;
                self.exit_code = 126;
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.system_policy_rejected);
                return;
            }
            self.dispatchMacOSSyscall(
                self.regs.rdi,
                self.regs.rsi,
                self.regs.rdx,
                self.regs.r10,
                self.regs.r8,
                self.regs.r9,
            );
        },

        .ud2 => {
            const symbol = self.metadata.nearestSymbol(self.regs.rip);
            const assertion_age = self.executed_steps -| self.last_guest_assertion_step;
            machoCapturePrint(
                "macho-processor: UD2 encounter: rip=0x{x} {s}+0x{x} active=0x{x} signal_depth={d} assertion={s} assertion_age={d} assertion_return=0x{x} bytes=0f0b\n",
                .{ self.regs.rip, if (symbol) |entry| entry.name else "<unknown>", if (symbol) |entry| entry.offset else 0, self.active_guest_thread, self.signal_frame_count, @tagName(self.last_guest_assertion_class), assertion_age, self.last_guest_assertion_return },
            );
            if (self.deliverGuestSignal(GUEST_SIGILL, self.regs.rip, d.len, self.regs.rip, null)) return;
            machoCapturePrint("macho-processor: UD2 instruction at rip=0x{x} — unhandled guest SIGILL\n", .{self.regs.rip});
            self.faulted = true;
            self.terminated = true;
            self.exit_code = 128 + GUEST_SIGILL;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unhandled_guest_signal);
            return;
        },

        .cpuid => {
            const leaf: u32 = @truncate(self.regs.rax);
            const subleaf: u32 = @truncate(self.regs.rcx);
            const result = x64_decoder.capabilities.cpuid(self.cpu_profile, leaf, subleaf);
            log.info(
                "cpuid: leaf=0x{x} subleaf=0x{x} -> eax=0x{x} ebx=0x{x} ecx=0x{x} edx=0x{x}",
                .{ leaf, subleaf, result.eax, result.ebx, result.ecx, result.edx },
            );
            self.setReg(.al_ax_eax_rax, .bits32, result.eax);
            self.setReg(.bl_bx_ebx_rbx, .bits32, result.ebx);
            self.setReg(.cl_cx_ecx_rcx, .bits32, result.ecx);
            self.setReg(.dl_dx_edx_rdx, .bits32, result.edx);
        },

        .xgetbv => {
            const xcr0 = if (@as(u32, @truncate(self.regs.rcx)) == 0)
                x64_decoder.capabilities.xcr0(self.cpu_profile)
            else
                0;
            log.info("xgetbv: xcr=0x{x} -> xcr0=0x{x} profile={s}", .{ self.regs.rcx, xcr0, self.cpu_profile.label() });
            self.setReg(.al_ax_eax_rax, .bits32, @truncate(xcr0));
            self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(xcr0 >> 32));
        },

        .hlt => {
            const boundary = x64_decoder.highway.systemBoundary(.macho64, .process_exit, self.regs.rax, "HLT");
            if (boundary.disposition != .emulate) unreachable;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.hlt);
            self.terminated = true;
            self.exit_code = self.regs.rax;
        },

        else => {
            log.warn("unimplemented instruction: {s} at rip=0x{x}", .{ @tagName(d.op), self.regs.rip });
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unimplemented_instruction);
            self.terminated = true;
        },
    }
}
