//! Bounded x87 subset for the raw PE32 interpreter.
//!
//! The maze loader's injected DLL uses the classic x87 control-word, scalar
//! load/store, compare, and basic arithmetic instructions during startup. This
//! module keeps the architectural stack and tags in RegisterFile.FpuState;
//! values use f64 precision, so 80-bit intermediates and unlisted encodings are
//! still reported as unsupported rather than silently misdecoded.
const std = @import("std");
const reg_map = @import("register_mapping.zig");
const raw_decode = @import("raw_decoder.zig");

pub const ExecuteError = error{
    UnsupportedEncoding,
    InvalidEffectiveAddress,
    UnmappedMemory,
};

const tag_valid: u2 = 0;
const tag_zero: u2 = 1;
const tag_special: u2 = 2;
const tag_empty: u2 = 3;
const status_invalid: u16 = 1 << 0;
const status_stack_fault: u16 = 1 << 6;
const status_c0: u16 = 1 << 8;
const status_c1: u16 = 1 << 9;
const status_c2: u16 = 1 << 10;
const status_c3: u16 = 1 << 14;
const status_condition_mask: u16 = status_c0 | status_c1 | status_c2 | status_c3;
const status_top_mask: u16 = 0x3800;

fn top(fpu: *const reg_map.FpuState) u3 {
    return @truncate(fpu.x87_top);
}

fn physical(fpu: *const reg_map.FpuState, logical: u3) u3 {
    return top(fpu) +% logical;
}

fn tagAt(fpu: *const reg_map.FpuState, index: u3) u2 {
    const shift: u4 = @as(u4, index) * 2;
    return @truncate(fpu.tag >> shift);
}

fn setTag(fpu: *reg_map.FpuState, index: u3, tag: u2) void {
    const shift: u4 = @as(u4, index) * 2;
    const mask: u16 = @as(u16, 3) << shift;
    fpu.tag = (fpu.tag & ~mask) | (@as(u16, tag) << shift);
}

fn syncTop(fpu: *reg_map.FpuState) void {
    fpu.x87_top = top(fpu);
    fpu.status = (fpu.status & ~status_top_mask) | (@as(u16, fpu.x87_top) << 11);
}

fn classify(value: f64) u2 {
    if (value == 0.0) return tag_zero;
    if (std.math.isFinite(value)) return tag_valid;
    return tag_special;
}

fn stackFault(fpu: *reg_map.FpuState, overflow: bool) void {
    fpu.status |= status_invalid | status_stack_fault;
    if (overflow) fpu.status |= status_c1 else fpu.status &= ~status_c1;
}

fn push(fpu: *reg_map.FpuState, value: f64) bool {
    const next = top(fpu) -% 1;
    if (tagAt(fpu, next) != tag_empty) {
        stackFault(fpu, true);
        syncTop(fpu);
        return false;
    }
    fpu.x87_top = next;
    fpu.x87_stack[next] = value;
    setTag(fpu, next, classify(value));
    syncTop(fpu);
    return true;
}

fn get(fpu: *reg_map.FpuState, logical: u3) ?f64 {
    const index = physical(fpu, logical);
    if (tagAt(fpu, index) == tag_empty) {
        stackFault(fpu, false);
        syncTop(fpu);
        return null;
    }
    return fpu.x87_stack[index];
}

fn set(fpu: *reg_map.FpuState, logical: u3, value: f64) bool {
    const index = physical(fpu, logical);
    if (tagAt(fpu, index) == tag_empty) {
        stackFault(fpu, false);
        syncTop(fpu);
        return false;
    }
    fpu.x87_stack[index] = value;
    setTag(fpu, index, classify(value));
    syncTop(fpu);
    return true;
}

fn pop(fpu: *reg_map.FpuState) ?f64 {
    const index = top(fpu);
    if (tagAt(fpu, index) == tag_empty) {
        stackFault(fpu, false);
        syncTop(fpu);
        return null;
    }
    const value = fpu.x87_stack[index];
    setTag(fpu, index, tag_empty);
    fpu.x87_top = index +% 1;
    syncTop(fpu);
    return value;
}

fn inRange(memory: *const reg_map.Memory, address: u32, size: usize) bool {
    if (address < memory.base) return false;
    const offset: usize = @intCast(address - memory.base);
    return offset <= memory.data.len and size <= memory.data.len - offset;
}

fn resolveAddress(regs: *const reg_map.RegisterFile, decoded: raw_decode.DecodedInstruction) ?u32 {
    const operand = decoded.operand orelse return null;
    const offset = switch (operand) {
        .mem => |effective| effective.resolve(regs) orelse return null,
        .reg => return null,
    };
    const segment_base: u32 = switch (decoded.segment_override orelse return offset) {
        .cs => regs.cs_desc.base,
        .ds => regs.ds_desc.base,
        .es => regs.es_desc.base,
        .fs => regs.fs_desc.base,
        .gs => regs.gs_desc.base,
        .ss => regs.ss_desc.base,
    };
    return std.math.add(u32, segment_base, offset) catch null;
}

fn read64(memory: *const reg_map.Memory, address: u32) ExecuteError!u64 {
    if (!inRange(memory, address, 8)) return error.UnmappedMemory;
    const high_address = std.math.add(u32, address, 4) catch return error.UnmappedMemory;
    return @as(u64, memory.read32(address)) | (@as(u64, memory.read32(high_address)) << 32);
}

fn readFloat32(memory: *const reg_map.Memory, address: u32) ExecuteError!f64 {
    if (!inRange(memory, address, 4)) return error.UnmappedMemory;
    return @floatCast(@as(f32, @bitCast(memory.read32(address))));
}

fn readSignedInt32(memory: *const reg_map.Memory, address: u32) ExecuteError!f64 {
    if (!inRange(memory, address, 4)) return error.UnmappedMemory;
    return @floatFromInt(@as(i32, @bitCast(memory.read32(address))));
}

fn readSignedInt16(memory: *const reg_map.Memory, address: u32) ExecuteError!f64 {
    if (!inRange(memory, address, 2)) return error.UnmappedMemory;
    return @floatFromInt(@as(i16, @bitCast(memory.read16(address))));
}

fn roundFistpValue(value: f64, control: u16) ?i64 {
    if (!std.math.isFinite(value)) return null;

    const rounded = switch ((control >> 10) & 3) {
        0 => blk: {
            const lower = @floor(value);
            const fraction = value - lower;
            if (fraction < 0.5) break :blk lower;
            if (fraction > 0.5) break :blk lower + 1.0;
            // Round-to-nearest-even, including negative half-way values.
            break :blk if (@rem(lower, 2.0) == 0.0) lower else lower + 1.0;
        },
        1 => @floor(value),
        2 => @ceil(value),
        3 => @trunc(value),
        else => unreachable,
    };

    // f64 represents the signed 64-bit boundary exactly, but not INT64_MAX.
    // Reject 2^63 while permitting -2^63 before the checked conversion.
    const signed_limit: f64 = 9223372036854775808.0;
    if (rounded < -signed_limit or rounded >= signed_limit) return null;
    return @intFromFloat(rounded);
}

fn writeFloat32(memory: *reg_map.Memory, address: u32, value: f64) ExecuteError!void {
    if (!inRange(memory, address, 4)) return error.UnmappedMemory;
    memory.write32(address, @bitCast(@as(f32, @floatCast(value))));
}

fn write64(memory: *reg_map.Memory, address: u32, value: u64) ExecuteError!void {
    if (!inRange(memory, address, 8)) return error.UnmappedMemory;
    const high_address = std.math.add(u32, address, 4) catch return error.UnmappedMemory;
    memory.write32(address, @truncate(value));
    memory.write32(high_address, @truncate(value >> 32));
}

fn write16(memory: *reg_map.Memory, address: u32, value: u16) ExecuteError!void {
    if (!inRange(memory, address, 2)) return error.UnmappedMemory;
    memory.write16(address, value);
}

fn readExtended80(memory: *const reg_map.Memory, address: u32) ExecuteError!f64 {
    if (!inRange(memory, address, 10)) return error.UnmappedMemory;
    const significand = try read64(memory, address);
    const sign_exp_address = std.math.add(u32, address, 8) catch return error.UnmappedMemory;
    const sign_exp = memory.read16(sign_exp_address);
    const negative = (sign_exp & 0x8000) != 0;
    const exponent: i32 = @intCast(sign_exp & 0x7FFF);
    if (exponent == 0x7FFF) {
        if (significand == 0x8000_0000_0000_0000) {
            const sign_bit: u64 = if (negative) @as(u64, 1) << 63 else 0;
            return @bitCast(sign_bit | 0x7FF0_0000_0000_0000);
        }
        return std.math.nan(f64);
    }
    if (significand == 0) return if (negative) -0.0 else 0.0;
    const unbiased: i32 = (if (exponent == 0) 1 else exponent) - 16383;
    const scale: f64 = @floatFromInt(unbiased - 63);
    const magnitude = @as(f64, @floatFromInt(significand)) * std.math.exp2(scale);
    return if (negative) -magnitude else magnitude;
}

fn compare(fpu: *reg_map.FpuState, lhs: f64, rhs: f64, pop_after: bool) void {
    fpu.status &= ~status_condition_mask;
    if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
        fpu.status |= status_c0 | status_c2 | status_c3;
    } else if (lhs < rhs) {
        fpu.status |= status_c0;
    } else if (lhs == rhs) {
        fpu.status |= status_c3;
    }
    if (pop_after) _ = pop(fpu);
    syncTop(fpu);
}

fn arithmetic(fpu: *reg_map.FpuState, extension: u3, rhs: f64) void {
    const lhs = get(fpu, 0) orelse return;
    const value: f64 = switch (extension) {
        0 => lhs + rhs, // FADD
        1 => lhs * rhs, // FMUL
        4 => lhs - rhs, // FSUB
        5 => rhs - lhs, // FSUBR
        6 => lhs / rhs, // FDIV
        7 => rhs / lhs, // FDIVR
        else => unreachable,
    };
    _ = set(fpu, 0, value);
}

fn compareToIntegerFlags(regs: *reg_map.RegisterFile, lhs: f64, rhs: f64) void {
    const cf: u32 = 1 << 0;
    const pf: u32 = 1 << 2;
    const af: u32 = 1 << 4;
    const zf: u32 = 1 << 6;
    const sf: u32 = 1 << 7;
    const of: u32 = 1 << 11;
    const updated = cf | pf | af | zf | sf | of;
    var flags = regs.flags.raw() & ~updated;
    if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
        flags |= cf | pf | zf;
    } else if (lhs < rhs) {
        flags |= cf;
    } else if (lhs == rhs) {
        flags |= zf;
    }
    regs.flags = reg_map.Flags.fromRaw(flags);
}

/// Execute only x87 forms that the decoder has positively admitted. Other
/// escapes stop through the ordinary unsupported-instruction path.
pub fn execute(regs: *reg_map.RegisterFile, memory: *reg_map.Memory, decoded: raw_decode.DecodedInstruction) ExecuteError!void {
    const modrm = decoded.modrm orelse return error.UnsupportedEncoding;
    const fpu = &regs.fpu;
    if (modrm.mod == 3) {
        if (decoded.opcode == 0xD8) {
            const lhs = get(fpu, 0) orelse return;
            const rhs = get(fpu, modrm.rm) orelse return;
            switch (modrm.reg) {
                2 => compare(fpu, lhs, rhs, false), // FCOM ST(i)
                3 => compare(fpu, lhs, rhs, true), // FCOMP ST(i)
                else => arithmetic(fpu, modrm.reg, rhs),
            }
            return;
        }
        if (decoded.opcode == 0xD9 and modrm.reg == 0) {
            const value = get(fpu, modrm.rm) orelse return; // FLD ST(i)
            _ = push(fpu, value);
            return;
        }
        if (decoded.opcode == 0xD9 and modrm.reg == 1) {
            if (modrm.rm != 0) {
                const st0 = get(fpu, 0) orelse return;
                const sti = get(fpu, modrm.rm) orelse return;
                _ = set(fpu, 0, sti);
                _ = set(fpu, modrm.rm, st0);
            }
            return;
        }
        if (decoded.opcode == 0xD9 and modrm.reg == 4 and (modrm.rm == 0 or modrm.rm == 1)) {
            const value = get(fpu, 0) orelse return;
            _ = set(fpu, 0, if (modrm.rm == 0) -value else @abs(value));
            return;
        }
        if (decoded.opcode == 0xD9 and modrm.reg == 5) {
            const value: ?f64 = switch (modrm.rm) {
                0 => 1.0, // FLD1
                1 => 3.32192809488736234787, // FLDL2T
                2 => 1.44269504088896340736, // FLDL2E
                3 => 3.14159265358979323846, // FLDPI
                4 => 0.30102999566398119521, // FLDLG2
                5 => 0.69314718055994530942, // FLDLN2
                6 => 0.0, // FLDZ
                else => null,
            };
            if (value) |constant| {
                _ = push(fpu, constant);
                return;
            }
        }
        if (decoded.opcode == 0xD9 and modrm.reg == 7) {
            const value = get(fpu, 0) orelse return;
            switch (modrm.rm) {
                2 => {
                    if (value < 0.0) {
                        fpu.status |= status_invalid;
                        _ = set(fpu, 0, std.math.nan(f64));
                    } else {
                        _ = set(fpu, 0, @sqrt(value));
                    }
                },
                6, 7 => {
                    if (!std.math.isFinite(value) or @abs(value) >= 9_223_372_036_854_775_808.0) {
                        fpu.status |= status_c2;
                    } else {
                        fpu.status &= ~status_c2;
                        _ = set(fpu, 0, if (modrm.rm == 6) @sin(value) else @cos(value));
                    }
                },
                else => return error.UnsupportedEncoding,
            }
            syncTop(fpu);
            return;
        }
        if (decoded.opcode == 0xD9 and modrm.reg == 6 and modrm.rm == 1) {
            const x = get(fpu, 0) orelse return; // ST(0)
            const y = get(fpu, 1) orelse return; // ST(1)
            _ = set(fpu, 1, y * @log2(x)); // FYL2X: ST(1) = ST(1) * log2(ST(0))
            _ = pop(fpu);
            return;
        }
        if (decoded.opcode == 0xDE and (modrm.reg == 0 or modrm.reg == 5) and modrm.rm != 0) {
            const destination = get(fpu, modrm.rm) orelse return;
            const source = get(fpu, 0) orelse return;
            _ = set(fpu, modrm.rm, if (modrm.reg == 0) destination + source else destination - source);
            _ = pop(fpu);
            return;
        }
        if (decoded.opcode == 0xDF and modrm.reg == 5) {
            const lhs = get(fpu, 0) orelse return;
            const rhs = get(fpu, modrm.rm) orelse return;
            compareToIntegerFlags(regs, lhs, rhs);
            _ = pop(fpu);
            return;
        }
        if (decoded.opcode == 0xDD and (modrm.reg == 2 or modrm.reg == 3)) {
            const value = get(fpu, 0) orelse return;
            _ = set(fpu, modrm.rm, value); // FST/FSTP ST(i)
            if (modrm.reg == 3) _ = pop(fpu);
            return;
        }
        if (decoded.opcode == 0xDB and modrm.reg == 4 and modrm.rm == 2) {
            fpu.status &= ~@as(u16, 0x80FF); // FNCLEX
            syncTop(fpu);
            return;
        }
        if (decoded.opcode == 0xDF and modrm.reg == 4 and modrm.rm == 0) {
            regs.set16(.eax, fpu.status); // FNSTSW AX
            return;
        }
        return error.UnsupportedEncoding;
    }

    const address = resolveAddress(regs, decoded) orelse return error.InvalidEffectiveAddress;
    switch (decoded.opcode) {
        0xD8 => {
            const rhs = try readFloat32(memory, address);
            switch (modrm.reg) {
                2 => {
                    const lhs = get(fpu, 0) orelse return;
                    compare(fpu, lhs, rhs, false); // FCOM m32real
                },
                3 => {
                    const lhs = get(fpu, 0) orelse return;
                    compare(fpu, lhs, rhs, true); // FCOMP m32real
                },
                else => arithmetic(fpu, modrm.reg, rhs),
            }
        },
        0xD9 => {
            switch (modrm.reg) {
                0 => _ = push(fpu, try readFloat32(memory, address)), // FLD m32real
                2, 3 => {
                    const value = get(fpu, 0) orelse return;
                    try writeFloat32(memory, address, value); // FST/FSTP m32real
                    if (modrm.reg == 3) _ = pop(fpu);
                },
                5 => {
                    if (!inRange(memory, address, 2)) return error.UnmappedMemory;
                    fpu.control = memory.read16(address); // FLDCW m16
                },
                7 => try write16(memory, address, fpu.control), // FNSTCW m16
                else => return error.UnsupportedEncoding,
            }
        },
        0xDA => {
            const rhs = try readSignedInt32(memory, address);
            switch (modrm.reg) {
                2 => {
                    const lhs = get(fpu, 0) orelse return;
                    compare(fpu, lhs, rhs, false); // FICOM m32int
                },
                3 => {
                    const lhs = get(fpu, 0) orelse return;
                    compare(fpu, lhs, rhs, true); // FICOMP m32int
                },
                else => arithmetic(fpu, modrm.reg, rhs),
            }
        },
        0xDB => switch (modrm.reg) {
            0 => {
                if (!inRange(memory, address, 4)) return error.UnmappedMemory;
                const signed = @as(i32, @bitCast(memory.read32(address)));
                _ = push(fpu, @floatFromInt(signed)); // FILD m32
            },
            5 => _ = push(fpu, try readExtended80(memory, address)), // FLD m80
            else => return error.UnsupportedEncoding,
        },
        0xDC => {
            const rhs: f64 = @bitCast(try read64(memory, address));
            switch (modrm.reg) {
                2, 3 => {
                    const lhs = get(fpu, 0) orelse return;
                    compare(fpu, lhs, rhs, modrm.reg == 3); // FCOM/FCOMP m64real
                },
                else => arithmetic(fpu, modrm.reg, rhs),
            }
        },
        0xDE => {
            const rhs = try readSignedInt16(memory, address);
            switch (modrm.reg) {
                2 => {
                    const lhs = get(fpu, 0) orelse return;
                    compare(fpu, lhs, rhs, false); // FICOM m16int
                },
                3 => {
                    const lhs = get(fpu, 0) orelse return;
                    compare(fpu, lhs, rhs, true); // FICOMP m16int
                },
                else => arithmetic(fpu, modrm.reg, rhs),
            }
        },
        0xDF => switch (modrm.reg) {
            0 => _ = push(fpu, try readSignedInt16(memory, address)), // FILD m16int
            7 => {
                const value = get(fpu, 0) orelse return;
                const integer = roundFistpValue(value, fpu.control) orelse blk: {
                    fpu.status |= status_invalid;
                    break :blk std.math.minInt(i64);
                };
                try write64(memory, address, @bitCast(integer)); // FISTP m64int
                _ = pop(fpu);
            },
            else => return error.UnsupportedEncoding,
        },
        0xDD => switch (modrm.reg) {
            0 => _ = push(fpu, @as(f64, @bitCast(try read64(memory, address)))), // FLD m64
            2, 3 => {
                const value = get(fpu, 0) orelse return;
                try write64(memory, address, @bitCast(value)); // FST/FSTP m64real
                if (modrm.reg == 3) _ = pop(fpu);
            },
            else => return error.UnsupportedEncoding,
        },
        else => return error.UnsupportedEncoding,
    }
}

test "x87 stack tags, status top, load/store, and compare pop" {
    var regs = reg_map.RegisterFile{};
    var memory = reg_map.Memory.fromSlice(try std.testing.allocator.alloc(u8, 0x2000));
    defer std.testing.allocator.free(memory.data);
    memory.base = 0x0040_0000;
    @memset(memory.data, 0);
    const value_address = memory.base + 0x100;
    const value_bits: u64 = @bitCast(@as(f64, 2.0));
    memory.write32(value_address, @truncate(value_bits));
    memory.write32(value_address + 4, @truncate(value_bits >> 32));

    const fld = try raw_decode.decodeInstruction(0x1000, &.{ 0xDD, 0x05, 0x00, 0x01, 0x40, 0x00 });
    try execute(&regs, &memory, fld);
    try std.testing.expectEqual(@as(u8, 7), regs.fpu.x87_top);
    try std.testing.expectEqual(@as(u2, tag_valid), tagAt(&regs.fpu, 7));

    const fld1 = try raw_decode.decodeInstruction(0x1006, &.{ 0xD9, 0xE8 });
    try execute(&regs, &memory, fld1);
    const fcomp = try raw_decode.decodeInstruction(0x1008, &.{ 0xDC, 0x1D, 0x00, 0x01, 0x40, 0x00 });
    try execute(&regs, &memory, fcomp);
    try std.testing.expect((regs.fpu.status & status_c0) != 0);
    try std.testing.expectEqual(@as(u8, 7), regs.fpu.x87_top);
    try std.testing.expectEqual(@as(u2, tag_empty), tagAt(&regs.fpu, 6));
}

test "x87 logarithm constants and FYL2X execute the loader's natural-log sequence" {
    var regs = reg_map.RegisterFile{};
    const data = try std.testing.allocator.alloc(u8, 0x2000);
    defer std.testing.allocator.free(data);
    @memset(data, 0);
    var memory = reg_map.Memory.fromSlice(data);
    memory.base = 0x0040_0000;
    const input_address = memory.base + 0x100;
    try write64(&memory, input_address, @bitCast(@as(f64, 8.0)));

    const fldln2 = try raw_decode.decodeInstruction(0x1000, &.{ 0xD9, 0xED });
    try std.testing.expectEqual(raw_decode.RawOp.x87, fldln2.op);
    try std.testing.expectEqual(raw_decode.DecodeStatus.executable, fldln2.status);
    try execute(&regs, &memory, fldln2);

    const fld_x = try raw_decode.decodeInstruction(0x1002, &.{ 0xDD, 0x05, 0x00, 0x01, 0x40, 0x00 });
    try execute(&regs, &memory, fld_x);
    const fyl2x = try raw_decode.decodeInstruction(0x1008, &.{ 0xD9, 0xF1 });
    try std.testing.expectEqual(raw_decode.RawOp.x87, fyl2x.op);
    try std.testing.expectEqual(raw_decode.DecodeStatus.executable, fyl2x.status);
    try execute(&regs, &memory, fyl2x);

    try std.testing.expectEqual(@as(u3, 7), regs.fpu.x87_top);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0 * 0.69314718055994530942), get(&regs.fpu, 0).?, 1e-12);
}

test "x87 register compare exchange and pop forms execute" {
    var regs = reg_map.RegisterFile{};
    var empty_memory: [0]u8 = .{};
    var memory = reg_map.Memory.fromSlice(&empty_memory);
    _ = push(&regs.fpu, 2.0);
    _ = push(&regs.fpu, 1.0);

    const fcom = try raw_decode.decodeInstruction(0x1000, &.{ 0xD8, 0xD1 });
    try std.testing.expectEqual(raw_decode.DecodeStatus.executable, fcom.status);
    try execute(&regs, &memory, fcom);
    try std.testing.expect((regs.fpu.status & status_c0) != 0);

    const fxch = try raw_decode.decodeInstruction(0x1002, &.{ 0xD9, 0xC9 });
    try execute(&regs, &memory, fxch);
    try std.testing.expectEqual(@as(f64, 2.0), get(&regs.fpu, 0).?);
    try std.testing.expectEqual(@as(f64, 1.0), get(&regs.fpu, 1).?);

    const fstp_st0 = try raw_decode.decodeInstruction(0x1004, &.{ 0xDD, 0xD8 });
    try execute(&regs, &memory, fstp_st0);
    try std.testing.expectEqual(@as(u3, 7), regs.fpu.x87_top);
    try std.testing.expectEqual(@as(f64, 1.0), get(&regs.fpu, 0).?);
}

test "x87 extended load and control-word access preserve boundaries" {
    var regs = reg_map.RegisterFile{};
    const data = try std.testing.allocator.alloc(u8, 0x2000);
    defer std.testing.allocator.free(data);
    @memset(data, 0);
    var memory = reg_map.Memory.fromSlice(data);
    memory.base = 0x0040_0000;
    const address = memory.base + 0x100;
    // 1.5 as extended80: exponent 16383 and significand 1.5 * 2^63.
    memory.write32(address, 0x0000_0000);
    memory.write32(address + 4, 0xC000_0000);
    memory.write16(address + 8, 0x3FFF);
    const fld80 = try raw_decode.decodeInstruction(0x1000, &.{ 0xDB, 0x2D, 0x00, 0x01, 0x40, 0x00 });
    try execute(&regs, &memory, fld80);
    try std.testing.expectEqual(@as(f64, 1.5), get(&regs.fpu, 0).?);

    memory.write16(address + 0x20, 0x027F);
    regs.ebp = address;
    const fldcw = try raw_decode.decodeInstruction(0x1006, &.{ 0xD9, 0x6D, 0x20 });
    try execute(&regs, &memory, fldcw);
    try std.testing.expectEqual(@as(u16, 0x027F), regs.fpu.control);

    memory.write16(address + 0x22, 0);
    const fnstcw = try raw_decode.decodeInstruction(0x1009, &.{ 0xD9, 0x7D, 0x22 });
    try execute(&regs, &memory, fnstcw);
    try std.testing.expectEqual(@as(u16, 0x027F), memory.read16(address + 0x22));
}

test "x87 m32 arithmetic and comparisons preserve stack behavior" {
    const data = try std.testing.allocator.alloc(u8, 0x2000);
    defer std.testing.allocator.free(data);
    @memset(data, 0);
    var memory = reg_map.Memory.fromSlice(data);
    memory.base = 0x0040_0000;
    const operand_address = memory.base + 0x100;
    memory.write32(operand_address, @bitCast(@as(f32, 2.0)));

    var regs = reg_map.RegisterFile{};
    _ = push(&regs.fpu, 3.0);
    const fmul = try raw_decode.decodeInstruction(0x1000, &.{ 0xD8, 0x0D, 0x00, 0x01, 0x40, 0x00 });
    try std.testing.expectEqual(raw_decode.DecodeStatus.executable, fmul.status);
    try std.testing.expectEqual(raw_decode.RawOp.x87, fmul.op);
    try std.testing.expectEqual(@as(u8, 32), @intFromEnum(fmul.width));
    try execute(&regs, &memory, fmul);
    try std.testing.expectEqual(@as(f64, 6.0), get(&regs.fpu, 0).?);

    memory.write32(operand_address, @bitCast(@as(f32, 10.0)));
    const fcom = try raw_decode.decodeInstruction(0x1006, &.{ 0xD8, 0x15, 0x00, 0x01, 0x40, 0x00 });
    try execute(&regs, &memory, fcom);
    try std.testing.expect((regs.fpu.status & status_c0) != 0);
    try std.testing.expectEqual(@as(f64, 6.0), get(&regs.fpu, 0).?);

    const fcomp = try raw_decode.decodeInstruction(0x100C, &.{ 0xD8, 0x1D, 0x00, 0x01, 0x40, 0x00 });
    try execute(&regs, &memory, fcomp);
    try std.testing.expectEqual(@as(u8, 0), regs.fpu.x87_top);
    try std.testing.expectEqual(@as(u2, tag_empty), tagAt(&regs.fpu, 7));
}

test "x87 m32 store rounds and optional pop is exact" {
    const data = try std.testing.allocator.alloc(u8, 0x2000);
    defer std.testing.allocator.free(data);
    @memset(data, 0);
    var memory = reg_map.Memory.fromSlice(data);
    memory.base = 0x0040_0000;
    const destination = memory.base + 0x100;
    var regs = reg_map.RegisterFile{};
    _ = push(&regs.fpu, 1.0 / 3.0);

    const fst = try raw_decode.decodeInstruction(0x1000, &.{ 0xD9, 0x15, 0x00, 0x01, 0x40, 0x00 });
    try execute(&regs, &memory, fst);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, @floatCast(1.0 / 3.0)))), memory.read32(destination));
    try std.testing.expectEqual(@as(u3, 7), regs.fpu.x87_top);

    const fstp = try raw_decode.decodeInstruction(0x1006, &.{ 0xD9, 0x1D, 0x00, 0x01, 0x40, 0x00 });
    try execute(&regs, &memory, fstp);
    try std.testing.expectEqual(@as(u3, 0), regs.fpu.x87_top);
}

test "x87 integer arithmetic sign-extends m32 and m16 operands" {
    const data = try std.testing.allocator.alloc(u8, 0x2000);
    defer std.testing.allocator.free(data);
    @memset(data, 0);
    var memory = reg_map.Memory.fromSlice(data);
    memory.base = 0x0040_0000;
    const operand_address = memory.base + 0x100;
    memory.write32(operand_address, @bitCast(@as(i32, -4)));
    memory.write16(operand_address + 4, @bitCast(@as(i16, 2)));

    var regs = reg_map.RegisterFile{};
    _ = push(&regs.fpu, 3.0);
    const fimul = try raw_decode.decodeInstruction(0x1000, &.{ 0xDA, 0x0D, 0x00, 0x01, 0x40, 0x00 });
    try std.testing.expectEqual(raw_decode.DecodeStatus.executable, fimul.status);
    try execute(&regs, &memory, fimul);
    try std.testing.expectEqual(@as(f64, -12.0), get(&regs.fpu, 0).?);

    const fisubr = try raw_decode.decodeInstruction(0x1006, &.{ 0xDE, 0x2D, 0x04, 0x01, 0x40, 0x00 });
    try execute(&regs, &memory, fisubr);
    try std.testing.expectEqual(@as(f64, 14.0), get(&regs.fpu, 0).?);
}

test "x87 FNSTSW memory stores the full status word without popping" {
    const data = try std.testing.allocator.alloc(u8, 0x2000);
    defer std.testing.allocator.free(data);
    @memset(data, 0);
    var memory = reg_map.Memory.fromSlice(data);
    memory.base = 0x0040_0000;
    const destination = memory.base + 0x100;
    var regs = reg_map.RegisterFile{};
    regs.fpu.status = 0x7D81;
    _ = push(&regs.fpu, 9.0);
    const top_before = regs.fpu.x87_top;
    const fnstsw = try raw_decode.decodeInstruction(0x1000, &.{ 0xDF, 0x3D, 0x00, 0x01, 0x40, 0x00 });
    try std.testing.expectEqual(raw_decode.DecodeStatus.executable, fnstsw.status);
    try execute(&regs, &memory, fnstsw);
    try std.testing.expectEqual(@as(u16, 0x7D81), memory.read16(destination));
    try std.testing.expectEqual(top_before, regs.fpu.x87_top);
}
