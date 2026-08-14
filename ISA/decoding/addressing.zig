//! Family: addressing — ModRM, SIB, segment selection, effective-address resolution.
//! Extracted from the universal x86-64 decoder (formerly src/x64-ASM/decoder.zig).

const std = @import("std");
const types = @import("types.zig");
const pref = @import("prefix.zig");
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

fn registerId(code: u8, extended: bool) RegId {
    const value: u4 = @as(u4, @truncate(code)) | if (extended) @as(u4, 8) else @as(u4, 0);
    return @enumFromInt(value);
}

/// Decodes the otherwise ambiguous 8-bit register codes 4...7. Without a
/// REX prefix they name AH/CH/DH/BH; with any REX prefix they name
/// SPL/BPL/SIL/DIL. The old decoder discarded this distinction.
pub fn decodeRegister(code: u8, extended: bool, byte_operand: bool, has_rex: bool) RegisterOperand {
    if (byte_operand and !has_rex and !extended and code >= 4 and code <= 7) {
        return .{ .id = registerId(code - 4, false), .high8 = true };
    }
    return .{ .id = registerId(code, extended) };
}

fn signExtendDisp32(raw: u32) u64 {
    const signed: i32 = @bitCast(raw);
    return @bitCast(@as(i64, signed));
}

pub fn defaultSegment(reference_kind: MemoryReferenceKind, base: ?RegId) Segment {
    return switch (reference_kind) {
        .instruction_fetch => .cs,
        .stack => .ss,
        .string_destination => .es,
        .string_source => .ds,
        .explicit_data => if (base == .ah_sp_esp_rsp or base == .ch_bp_ebp_rbp) .ss else .ds,
    };
}

pub fn selectSegment(reference_kind: MemoryReferenceKind, base: ?RegId, override: ?Segment) Segment {
    return switch (reference_kind) {
        .instruction_fetch, .stack, .string_destination => defaultSegment(reference_kind, base),
        .explicit_data, .string_source => override orelse defaultSegment(reference_kind, base),
    };
}

pub fn segmentBase(regs: *const Regs, segment: Segment, mode: ExecutionMode) u64 {
    if (mode == .real16) return @as(u64, regs.segments.get(segment).selector) << 4;
    if (mode == .long64 and segment != .fs and segment != .gs) return 0;
    return regs.segments.get(segment).base;
}

pub fn resolveMemoryAddress(regs: *const Regs, memory: MemoryOperand, instruction_end: u64, address_size: OperandSize, mode: ExecutionMode, apply_segment: bool) u64 {
    std.debug.assert(address_size == .bits16 or address_size == .bits32 or address_size == .bits64);
    const offset: u64 = switch (address_size) {
        .bits16 => blk: {
            var value: u16 = @truncate(memory.displacement);
            if (memory.has_index) {
                const index: u16 = @truncate(regVal(regs, memory.index_reg, .bits16));
                value +%= index << @as(u4, memory.scale);
            }
            if (memory.has_base) value +%= @truncate(regVal(regs, memory.base_reg, .bits16));
            if (memory.rip_relative) value +%= @truncate(instruction_end);
            break :blk value;
        },
        .bits32 => blk: {
            var value: u32 = @truncate(memory.displacement);
            if (memory.has_index) {
                const index: u32 = @truncate(regVal(regs, memory.index_reg, .bits32));
                value +%= index << @as(u5, memory.scale);
            }
            if (memory.has_base) value +%= @truncate(regVal(regs, memory.base_reg, .bits32));
            if (memory.rip_relative) value +%= @truncate(instruction_end);
            break :blk value;
        },
        .bits64 => blk: {
            var value = memory.displacement;
            if (memory.has_index) value +%= regVal(regs, memory.index_reg, .bits64) << @as(u6, memory.scale);
            if (memory.has_base) value +%= regVal(regs, memory.base_reg, .bits64);
            if (memory.rip_relative) value +%= instruction_end;
            break :blk value;
        },
        .bits8 => unreachable,
    };
    return offset +% if (apply_segment) segmentBase(regs, memory.segment, mode) else 0;
}

fn applyDefaultSegment(memory: *MemoryOperand, prefixes: LegacyPrefixes) void {
    const base: ?RegId = if (memory.has_base) memory.base_reg else null;
    memory.segment = selectSegment(.explicit_data, base, prefixes.segment_override);
}

pub fn decodeMemoryOperand(bytes: []const u8, pos: *usize, mode: u2, rm: u3, prefixes: LegacyPrefixes) ?MemoryOperand {
    if (rm != 4) {
        var result = MemoryOperand{
            .has_base = true,
            .base_reg = registerId(rm, prefixes.rexB()),
        };
        if (mode == 0 and rm == 5) {
            if (pos.* + 4 > bytes.len) return null;
            result.displacement = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
            result.has_base = false;
            result.rip_relative = true;
            pos.* += 4;
        } else if (mode == 1) {
            if (pos.* >= bytes.len) return null;
            result.displacement = @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*]))));
            pos.* += 1;
        } else if (mode == 2) {
            if (pos.* + 4 > bytes.len) return null;
            result.displacement = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
            pos.* += 4;
        }
        applyDefaultSegment(&result, prefixes);
        return result;
    }

    if (pos.* >= bytes.len) return null;
    const sib = bytes[pos.*];
    pos.* += 1;
    const base: u3 = @truncate(sib);
    const index: u3 = @truncate(sib >> 3);
    var result = MemoryOperand{
        .has_index = index != 4 or prefixes.rexX(),
        .index_reg = registerId(index, prefixes.rexX()),
        .scale = @truncate(sib >> 6),
        .has_base = !(mode == 0 and base == 5),
        .base_reg = registerId(base, prefixes.rexB()),
    };
    if (mode == 0 and base == 5) {
        if (pos.* + 4 > bytes.len) return null;
        result.displacement = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
        pos.* += 4;
    } else if (mode == 1) {
        if (pos.* >= bytes.len) return null;
        result.displacement = @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*]))));
        pos.* += 1;
    } else if (mode == 2) {
        if (pos.* + 4 > bytes.len) return null;
        result.displacement = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
        pos.* += 4;
    }
    applyDefaultSegment(&result, prefixes);
    return result;
}

/// Universally decodes the ModR/M byte and any following SIB/displacement.
/// Instruction handlers consume this structure instead of reimplementing
/// addressing rules for every mnemonic.
pub fn decodeModRm(bytes: []const u8, pos: *usize, prefixes: LegacyPrefixes, byte_operand: bool) ?DecodedModRm {
    if (pos.* >= bytes.len) return null;
    const modrm = bytes[pos.*];
    pos.* += 1;
    const mode: u2 = @truncate(modrm >> 6);
    const reg_code: u3 = @truncate(modrm >> 3);
    const rm_code: u3 = @truncate(modrm);
    const reg = decodeRegister(reg_code, prefixes.rexR(), byte_operand, prefixes.has_rex);
    const rm: RmOperand = if (mode == 3)
        .{ .register = decodeRegister(rm_code, prefixes.rexB(), byte_operand, prefixes.has_rex) }
    else
        .{ .memory = decodeMemoryOperand(bytes, pos, mode, rm_code, prefixes) orelse return null };
    return .{ .reg = reg, .rm = rm, .group = reg_code };
}

test "default segment selection follows instruction stack data and string rules" {
    try std.testing.expectEqual(Segment.cs, defaultSegment(.instruction_fetch, null));
    try std.testing.expectEqual(Segment.ss, defaultSegment(.stack, null));
    try std.testing.expectEqual(Segment.ss, defaultSegment(.explicit_data, .ah_sp_esp_rsp));
    try std.testing.expectEqual(Segment.ss, defaultSegment(.explicit_data, .ch_bp_ebp_rbp));
    try std.testing.expectEqual(Segment.ds, defaultSegment(.explicit_data, .al_ax_eax_rax));
    try std.testing.expectEqual(Segment.ds, defaultSegment(.explicit_data, .r12b_r12w_r12d_r12));
    try std.testing.expectEqual(Segment.ds, defaultSegment(.string_source, .dh_si_esi_rsi));
    try std.testing.expectEqual(Segment.es, defaultSegment(.string_destination, .bh_di_edi_rdi));

    try std.testing.expectEqual(Segment.fs, selectSegment(.explicit_data, .ch_bp_ebp_rbp, .fs));
    try std.testing.expectEqual(Segment.gs, selectSegment(.string_source, .dh_si_esi_rsi, .gs));
    try std.testing.expectEqual(Segment.es, selectSegment(.string_destination, .bh_di_edi_rdi, .fs));
    try std.testing.expectEqual(Segment.ss, selectSegment(.stack, .ah_sp_esp_rsp, .gs));
}

test "long mode effective addresses apply only FS and GS segment bases" {
    var regs = Regs{};
    regs.rbp = 0x1000;
    regs.segments.ss.base = 0x2000;
    regs.segments.fs.base = 0x3000;

    const stack_default = MemoryOperand{
        .displacement = 8,
        .has_base = true,
        .base_reg = .ch_bp_ebp_rbp,
        .segment = .ss,
    };
    try std.testing.expectEqual(@as(u64, 0x1008), resolveMemoryAddress(&regs, stack_default, 0, .bits64, .long64, true));
    try std.testing.expectEqual(@as(u64, 0x3008), resolveMemoryAddress(&regs, .{ .displacement = 8, .segment = .fs }, 0, .bits64, .long64, true));
    try std.testing.expectEqual(@as(u64, 0x3008), resolveMemoryAddress(&regs, stack_default, 0, .bits64, .protected, true));
}

test "effective address resolver wraps address-size 32 before segmentation" {
    var regs = Regs{};
    regs.rax = 0xFFFF_FFFF;
    regs.rcx = 2;
    regs.segments.fs.base = 0x1000;
    const memory = MemoryOperand{
        .displacement = 3,
        .has_base = true,
        .base_reg = .al_ax_eax_rax,
        .has_index = true,
        .index_reg = .cl_cx_ecx_rcx,
        .scale = 1,
        .segment = .fs,
    };
    try std.testing.expectEqual(@as(u64, 0x1006), resolveMemoryAddress(&regs, memory, 0, .bits32, .long64, true));
}

test "RIP relative address resolution uses the end of the instruction" {
    const regs = Regs{};
    const memory = MemoryOperand{
        .displacement = @bitCast(@as(i64, -4)),
        .rip_relative = true,
    };
    try std.testing.expectEqual(@as(u64, 0x1003), resolveMemoryAddress(&regs, memory, 0x1007, .bits64, .long64, true));
}

test "a SIB with no base register is an absolute displacement, not RIP relative" {
    // `movbe eax, [rax*4 + 0x2000]` — 0F 38 F0 /r with SIB mod=00 base=101.
    // The base==101 escape means "no base, disp32 follows"; only a *non-SIB*
    // mod=00 rm=101 is RIP-relative. Conflating them shifted every scaled
    // table read by the address of the instruction doing the reading.
    var decoded = DecodedInsn{};
    var pos: usize = 0;
    const bytes = [_]u8{ 0x04, 0x85, 0x00, 0x20, 0x00, 0x00 };
    const rm = readModRM(&decoded, &bytes, &pos, false, false, false, .bits32);

    try std.testing.expect(!decoded.rip_relative);
    try std.testing.expect(!decoded.sib_has_base);
    try std.testing.expect(decoded.sib_has_index);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.sib_index_reg);
    try std.testing.expectEqual(@as(u2, 2), decoded.sib_scale);
    try std.testing.expectEqual(@as(u64, 0x2000), rm.addr);

    // Resolved against a register file, the address is the table entry and
    // owes nothing to the instruction pointer.
    var regs = Regs{};
    regs.rax = 3;
    const address = resolveMemoryAddress(&regs, .{
        .displacement = rm.addr,
        .has_index = decoded.sib_has_index,
        .index_reg = decoded.sib_index_reg,
        .scale = decoded.sib_scale,
        .has_base = decoded.sib_has_base,
        .base_reg = decoded.sib_base_reg,
        .rip_relative = decoded.rip_relative,
        .segment = decoded.segment,
    }, 0x40_0000, .bits64, .long64, true);
    try std.testing.expectEqual(@as(u64, 0x2000 + 3 * 4), address);
}

test "a non-SIB mod=00 rm=101 is still RIP relative" {
    // The form the fix must not disturb: `lea rax, [rip+0x10]`.
    var decoded = DecodedInsn{};
    var pos: usize = 0;
    const bytes = [_]u8{ 0x05, 0x10, 0x00, 0x00, 0x00 };
    const rm = readModRM(&decoded, &bytes, &pos, false, false, false, .bits64);

    try std.testing.expect(decoded.rip_relative);
    try std.testing.expect(!decoded.sib_has_base);
    try std.testing.expect(!decoded.sib_has_index);
    try std.testing.expectEqual(@as(u64, 0x10), rm.addr);
}

test "a SIB that does have a base register keeps it" {
    // `[rbx + rcx*8 + 0x20]`, mod=01 — the ordinary case, unchanged.
    var decoded = DecodedInsn{};
    var pos: usize = 0;
    const bytes = [_]u8{ 0x44, 0xCB, 0x20 };
    const rm = readModRM(&decoded, &bytes, &pos, false, false, false, .bits64);

    try std.testing.expect(!decoded.rip_relative);
    try std.testing.expect(decoded.sib_has_base);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, decoded.sib_base_reg);
    try std.testing.expect(decoded.sib_has_index);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.sib_index_reg);
    try std.testing.expectEqual(@as(u2, 3), decoded.sib_scale);
    try std.testing.expectEqual(@as(u64, 0x20), rm.addr);
}

pub fn hasModRM(byte: u8) bool {
    _ = byte;
    return true;
}

pub fn mapReg(reg_num: u8, rex_b: bool) RegId {
    const r = reg_num + @as(u8, if (rex_b) 8 else 0);
    return @enumFromInt(r);
}

pub fn mapJccCond8(opcode: u8) Cond {
    const conditions: [16]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np, .l, .ge, .le, .g,
    };
    return conditions[opcode & 0x0F];
}

pub fn mapJccCond32(opcode: u8) Cond {
    const conditions: [12]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np,
    };
    const idx = opcode & 0x0F;
    if (idx < 12) return conditions[idx];
    if (idx == 12) return .l;
    if (idx == 13) return .ge;
    if (idx == 14) return .le;
    return .g;
}

pub fn readModRM(d: *DecodedInsn, bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, _: Size) struct { reg: RegId, addr: u64 } {
    const modrm = bytes[pos.*];
    pos.* += 1;
    const mod = (modrm >> 6) & 3;
    const reg_num = (modrm >> 3) & 7;
    const rm_num = modrm & 7;

    const reg = mapReg(reg_num, rex_r);

    d.sib_has_base = false;
    d.sib_has_index = false;
    d.rip_relative = false;
    d.is_reg_form = false;

    if (mod == 3) {
        d.is_reg_form = true;
        return .{ .reg = reg, .addr = @as(u64, @intFromEnum(mapReg(rm_num, rex_b))) };
    }

    var disp: u64 = 0;

    if (rm_num == 4) {
        const sib = bytes[pos.*];
        pos.* += 1;
        const scale = (sib >> 6) & 3;
        const index_num = (sib >> 3) & 7;
        const base_num = sib & 7;

        if (index_num != 4) {
            d.sib_has_index = true;
            d.sib_index_reg = mapReg(index_num, rex_x);
            d.sib_scale = @as(u2, @intCast(scale));
        }

        // SIB with mod==0 and base==101 encodes "no base register, disp32
        // follows". It is **not** RIP-relative: RIP-relative addressing is
        // only ever `mod==0, rm==101` with no SIB byte at all, which the
        // non-SIB path below handles. Setting `rip_relative` here made every
        // `[index*scale + disp32]` and `[disp32]` form resolve to
        // `next_instruction + disp + index*scale`, so a vectorised table read
        // through a two-byte opcode landed a whole instruction pointer away
        // from its table.
        if (!(mod == 0 and base_num == 5)) {
            d.sib_has_base = true;
            d.sib_base_reg = mapReg(base_num, rex_b);
        }

        if (mod == 0 and base_num == 5) {
            if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
            disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
            pos.* += 4;
        } else if (mod == 1) {
            disp = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*])))));
            pos.* += 1;
        } else if (mod == 2) {
            if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
            disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
            pos.* += 4;
        }
        return .{ .reg = reg, .addr = disp };
    }

    if (mod == 0 and rm_num == 5) {
        if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
        d.rip_relative = true;
        disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
    } else if (mod == 1) {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
        disp = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*])))));
        pos.* += 1;
    } else if (mod == 2) {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
        if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
        disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
    } else {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
    }

    return .{ .reg = reg, .addr = disp };
}
