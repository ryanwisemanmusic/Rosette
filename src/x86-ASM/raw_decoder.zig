const std = @import("std");
const scaffold = @import("decode_scaffold.zig");
const reg_map = @import("register_mapping.zig");
const isa_registry = @import("isa_registry");
const highway = isa_registry.highway;

const ModRm = scaffold.ModRm;
const Sib = scaffold.Sib;
const Register = reg_map.Register;

pub const max_instruction_len = 15;

pub const DecodeStatus = enum {
    executable,
    recognized_unimplemented,
    invalid,
};

pub const ControlKind = enum {
    none,
    near_jump,
    near_call,
    near_return,
};

pub const RawOp = enum {
    invalid,
    recognized_unimplemented,
    nop,
    ret,
    jmp_rel,
    call_rel,
    push_reg,
    pop_reg,
    push_imm,
    mov_reg_imm,
    binary_reg_reg,
    group5_inc,
    group5_dec,
    group5_call,
    group5_jmp,
    group5_push,
};

pub const EffectiveAddress = struct {
    absolute: ?u32 = null,
    base: ?Register = null,
    index: ?Register = null,
    scale: u8 = 1,
    displacement: i32 = 0,

    pub fn resolve(self: EffectiveAddress, regs: *const reg_map.RegisterFile) ?u32 {
        var value: i64 = 0;
        if (self.absolute) |absolute| value += @as(i64, @intCast(absolute));
        if (self.base) |base| value += @as(i64, @intCast(regs.get(base)));
        if (self.index) |index| value += @as(i64, @intCast(regs.get(index))) * @as(i64, self.scale);
        value += self.displacement;
        if (value < 0 or value > std.math.maxInt(u32)) return null;
        return @intCast(value);
    }
};

pub const Rm32 = union(enum) {
    reg: Register,
    mem: EffectiveAddress,
};

const GroupInfo = struct {
    op: RawOp,
    mnemonic: []const u8,
    control: ControlKind,
    executable: bool,
    reason: []const u8,
};

pub const DecodedInstruction = struct {
    address: u32,
    len: u8,
    bytes: [max_instruction_len]u8 = [_]u8{0} ** max_instruction_len,
    opcode: u8,
    modrm: ?ModRm = null,
    sib: ?Sib = null,
    op: RawOp,
    status: DecodeStatus,
    control: ControlKind = .none,
    mnemonic: []const u8,
    isa_path: []const u8,
    operand: ?Rm32 = null,
    register: ?Register = null,
    immediate: u32 = 0,
    binary_op: ?highway.BinaryOp = null,
    width: highway.Width = .bits32,
    target: u32 = 0,
    text: [96]u8 = [_]u8{0} ** 96,
    text_len: u8 = 0,
    unsupported_reason: []const u8 = "",

    pub fn textSlice(self: *const DecodedInstruction) []const u8 {
        return self.text[0..self.text_len];
    }
};

const PrefixState = struct {
    operand_size_override: bool = false,
    address_size_override: bool = false,
    count: u8 = 0,
};

fn reg32Name(reg: Register) []const u8 {
    return switch (reg) {
        .eax => "eax",
        .ecx => "ecx",
        .edx => "edx",
        .ebx => "ebx",
        .esp => "esp",
        .ebp => "ebp",
        .esi => "esi",
        .edi => "edi",
    };
}

fn registerFromBits(bits: u3) Register {
    return @enumFromInt(@as(u4, bits));
}

fn readU8(cursor: *scaffold.DecodeCursor) !u8 {
    return cursor.readU8();
}

fn readU32(cursor: *scaffold.DecodeCursor) !u32 {
    var result: u32 = 0;
    for (0..4) |shift| {
        result |= @as(u32, try readU8(cursor)) << @intCast(shift * 8);
    }
    return result;
}

fn readI32(cursor: *scaffold.DecodeCursor) !i32 {
    return @bitCast(try readU32(cursor));
}

fn readI8(cursor: *scaffold.DecodeCursor) !i8 {
    return @bitCast(try readU8(cursor));
}

fn parsePrefixes(cursor: *scaffold.DecodeCursor) !PrefixState {
    var prefixes = PrefixState{};
    while (cursor.remaining() > 0 and cursor.offset < max_instruction_len) {
        const byte = cursor.bytes[cursor.offset];
        switch (byte) {
            0x66 => prefixes.operand_size_override = true,
            0x67 => prefixes.address_size_override = true,
            0xF0, 0xF2, 0xF3, 0x2E, 0x36, 0x3E, 0x26, 0x64, 0x65 => {},
            else => break,
        }
        _ = try readU8(cursor);
        prefixes.count +|= 1;
    }
    return prefixes;
}

fn parseRm32(cursor: *scaffold.DecodeCursor, modrm: ModRm, out_sib: *?Sib) !Rm32 {
    if (modrm.mod == 3) {
        return .{ .reg = registerFromBits(modrm.rm) };
    }

    var mem = EffectiveAddress{};
    if (modrm.mod == 0 and modrm.rm == 5) {
        mem.absolute = try readU32(cursor);
        return .{ .mem = mem };
    }

    if (modrm.rm == 4) {
        const sib = try cursor.readSib();
        out_sib.* = sib;
        mem.scale = switch (sib.scale) {
            0 => 1,
            1 => 2,
            2 => 4,
            3 => 8,
        };
        if (sib.index != 4) mem.index = registerFromBits(sib.index);
        if (modrm.mod == 0 and sib.base == 5) {
            mem.absolute = try readU32(cursor);
        } else {
            mem.base = registerFromBits(sib.base);
        }
    } else {
        mem.base = registerFromBits(modrm.rm);
    }

    mem.displacement = switch (modrm.mod) {
        0 => 0,
        1 => @as(i32, try readI8(cursor)),
        2 => try readI32(cursor),
        else => unreachable,
    };
    return .{ .mem = mem };
}

fn appendText(result: *DecodedInstruction, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.bufPrint(&result.text, fmt, args);
    result.text_len = @intCast(text.len);
}

fn formatRm32(buf: []u8, rm: Rm32) ![]const u8 {
    return switch (rm) {
        .reg => |reg| std.fmt.bufPrint(buf, "{s}", .{reg32Name(reg)}),
        .mem => |mem| blk: {
            if (mem.absolute) |absolute| {
                if (mem.base == null and mem.index == null and mem.displacement == 0) {
                    break :blk try std.fmt.bufPrint(buf, "[0x{X:0>8}]", .{absolute});
                }
            }
            if (mem.base) |base| {
                if (mem.index) |index| {
                    if (mem.displacement == 0) {
                        break :blk try std.fmt.bufPrint(buf, "[{s}+{s}*{d}]", .{ reg32Name(base), reg32Name(index), mem.scale });
                    }
                    if (mem.displacement < 0) {
                        break :blk try std.fmt.bufPrint(buf, "[{s}+{s}*{d}-0x{X}]", .{ reg32Name(base), reg32Name(index), mem.scale, @as(u32, @intCast(-mem.displacement)) });
                    }
                    break :blk try std.fmt.bufPrint(buf, "[{s}+{s}*{d}+0x{X}]", .{ reg32Name(base), reg32Name(index), mem.scale, @as(u32, @intCast(mem.displacement)) });
                }
                if (mem.displacement == 0) {
                    break :blk try std.fmt.bufPrint(buf, "[{s}]", .{reg32Name(base)});
                }
                if (mem.displacement < 0) {
                    break :blk try std.fmt.bufPrint(buf, "[{s}-0x{X}]", .{ reg32Name(base), @as(u32, @intCast(-mem.displacement)) });
                }
                break :blk try std.fmt.bufPrint(buf, "[{s}+0x{X}]", .{ reg32Name(base), @as(u32, @intCast(mem.displacement)) });
            }
            if (mem.index) |index| {
                if (mem.displacement == 0) {
                    break :blk try std.fmt.bufPrint(buf, "[{s}*{d}]", .{ reg32Name(index), mem.scale });
                }
                if (mem.displacement < 0) {
                    break :blk try std.fmt.bufPrint(buf, "[{s}*{d}-0x{X}]", .{ reg32Name(index), mem.scale, @as(u32, @intCast(-mem.displacement)) });
                }
                break :blk try std.fmt.bufPrint(buf, "[{s}*{d}+0x{X}]", .{ reg32Name(index), mem.scale, @as(u32, @intCast(mem.displacement)) });
            }
            break :blk try std.fmt.bufPrint(buf, "[0x{X:0>8}]", .{mem.absolute orelse 0});
        },
    };
}

fn relTarget(address: u32, len: usize, rel: i32) u32 {
    const next = address +% @as(u32, @intCast(len));
    return next +% @as(u32, @bitCast(rel));
}

fn sourcePathForMnemonic(mnemonic: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(mnemonic, "add")) return "ADD/ADD.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "bit_and")) return "AND/AND.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "bit_or")) return "OR/OR.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "bit_xor")) return "XOR/XOR.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "call")) return "CALL-RET/CALL.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "cmp")) return "CMP/CMP.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "dec")) return "INC-DEC/DEC.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "inc")) return "INC-DEC/INC.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "jmp")) return "JMP/JMP.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "mov")) return "MOV/MOV.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "nop")) return "INTERNAL/NOP";
    if (std.ascii.eqlIgnoreCase(mnemonic, "pop")) return "POP/POP.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "push")) return "PUSH/PUSH.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "ret")) return "CALL-RET/RET.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "sbb")) return "ADC-SBB/SBB.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "sub")) return "SUB/SUB.inc";
    return "UNKNOWN";
}

fn finish(result: *DecodedInstruction, bytes: []const u8, len: usize) !DecodedInstruction {
    result.len = @intCast(len);
    const copy_len = @min(bytes.len, @min(len, result.bytes.len));
    @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
    return result.*;
}

fn makeBase(address: u32, opcode: u8, op: RawOp, status: DecodeStatus, mnemonic: []const u8) DecodedInstruction {
    return .{
        .address = address,
        .len = 0,
        .opcode = opcode,
        .op = op,
        .status = status,
        .mnemonic = mnemonic,
        .isa_path = sourcePathForMnemonic(mnemonic),
    };
}

pub fn decodeInstruction(address: u32, bytes: []const u8) !DecodedInstruction {
    if (bytes.len == 0) return error.EndOfStream;

    var cursor = scaffold.DecodeCursor{ .bytes = bytes[0..@min(bytes.len, max_instruction_len)] };
    const prefixes = try parsePrefixes(&cursor);
    const opcode = try readU8(&cursor);

    if (prefixes.address_size_override) {
        var result = makeBase(address, opcode, .recognized_unimplemented, .recognized_unimplemented, "address-size-override");
        result.isa_path = "UNKNOWN";
        result.unsupported_reason = "16-bit addressing forms are not executable in the PE raw bridge yet";
        try appendText(&result, "db 0x{X:0>2}", .{opcode});
        return finish(&result, bytes, cursor.offset);
    }

    switch (opcode) {
        0x90 => {
            var result = makeBase(address, opcode, .nop, .executable, "nop");
            try appendText(&result, "nop", .{});
            return finish(&result, bytes, cursor.offset);
        },
        0xC3 => {
            var result = makeBase(address, opcode, .ret, .executable, "ret");
            result.control = .near_return;
            try appendText(&result, "ret", .{});
            return finish(&result, bytes, cursor.offset);
        },
        0x50...0x57 => {
            const reg: Register = @enumFromInt(@as(u4, @truncate(opcode - 0x50)));
            var result = makeBase(address, opcode, .push_reg, .executable, "push");
            result.register = reg;
            try appendText(&result, "push {s}", .{reg32Name(reg)});
            return finish(&result, bytes, cursor.offset);
        },
        0x58...0x5F => {
            const reg: Register = @enumFromInt(@as(u4, @truncate(opcode - 0x58)));
            var result = makeBase(address, opcode, .pop_reg, .executable, "pop");
            result.register = reg;
            try appendText(&result, "pop {s}", .{reg32Name(reg)});
            return finish(&result, bytes, cursor.offset);
        },
        0x68 => {
            const imm = try readU32(&cursor);
            var result = makeBase(address, opcode, .push_imm, .executable, "push");
            result.immediate = imm;
            try appendText(&result, "push 0x{X:0>8}", .{imm});
            return finish(&result, bytes, cursor.offset);
        },
        0x6A => {
            const imm8 = try readI8(&cursor);
            var result = makeBase(address, opcode, .push_imm, .executable, "push");
            result.immediate = @as(u32, @bitCast(@as(i32, imm8)));
            try appendText(&result, "push {d}", .{imm8});
            return finish(&result, bytes, cursor.offset);
        },
        0xB8...0xBF => {
            const reg: Register = @enumFromInt(@as(u4, @truncate(opcode - 0xB8)));
            const imm = try readU32(&cursor);
            var result = makeBase(address, opcode, .mov_reg_imm, .executable, "mov");
            result.register = reg;
            result.immediate = imm;
            try appendText(&result, "mov {s}, 0x{X:0>8}", .{ reg32Name(reg), imm });
            return finish(&result, bytes, cursor.offset);
        },
        0xE8 => {
            const rel = try readI32(&cursor);
            var result = makeBase(address, opcode, .call_rel, .executable, "call");
            result.control = .near_call;
            result.target = relTarget(address, cursor.offset, rel);
            try appendText(&result, "call 0x{X:0>8}", .{result.target});
            return finish(&result, bytes, cursor.offset);
        },
        0xE9 => {
            const rel = try readI32(&cursor);
            var result = makeBase(address, opcode, .jmp_rel, .executable, "jmp");
            result.control = .near_jump;
            result.target = relTarget(address, cursor.offset, rel);
            try appendText(&result, "jmp 0x{X:0>8}", .{result.target});
            return finish(&result, bytes, cursor.offset);
        },
        0xEB => {
            const rel = @as(i32, try readI8(&cursor));
            var result = makeBase(address, opcode, .jmp_rel, .executable, "jmp");
            result.control = .near_jump;
            result.target = relTarget(address, cursor.offset, rel);
            try appendText(&result, "jmp 0x{X:0>8}", .{result.target});
            return finish(&result, bytes, cursor.offset);
        },
        0x00...0x03, 0x08...0x0B, 0x18...0x1B, 0x20...0x23, 0x28...0x2B, 0x30...0x33, 0x38...0x3B => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            const binary_op: highway.BinaryOp = switch (opcode >> 3) {
                0 => .add,
                1 => .bit_or,
                3 => .sbb,
                4 => .bit_and,
                5 => .sub,
                6 => .bit_xor,
                7 => .cmp,
                else => unreachable,
            };
            const mnemonic = @tagName(binary_op);
            const width: highway.Width = if ((opcode & 1) == 0)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            const executable = modrm.mod == 3 and width != .bits8;
            var result = makeBase(address, opcode, if (executable) .binary_reg_reg else .recognized_unimplemented, if (executable) .executable else .recognized_unimplemented, mnemonic);
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.register = registerFromBits(modrm.reg);
            result.binary_op = binary_op;
            result.width = width;
            result.unsupported_reason = if (width == .bits8)
                "8-bit high-register aliases require the byte-register adapter"
            else
                "memory arithmetic requires the shared memory transaction adapter";
            const d = (opcode >> 1) & 1;
            if (d == 1) {
                try appendText(&result, "{s} {s}, {s}", .{ mnemonic, reg32Name(registerFromBits(modrm.reg)), rm_text });
            } else {
                try appendText(&result, "{s} {s}, {s}", .{ mnemonic, rm_text, reg32Name(registerFromBits(modrm.reg)) });
            }
            return finish(&result, bytes, cursor.offset);
        },
        0x88...0x8B => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            var result = makeBase(address, opcode, .recognized_unimplemented, .recognized_unimplemented, "mov");
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.unsupported_reason = "MOV r/m raw PE execution is decoded but not executable in the raw bridge yet";
            const d = (opcode >> 1) & 1;
            if (d == 1) {
                try appendText(&result, "mov {s}, {s}", .{ reg32Name(registerFromBits(modrm.reg)), rm_text });
            } else {
                try appendText(&result, "mov {s}, {s}", .{ rm_text, reg32Name(registerFromBits(modrm.reg)) });
            }
            return finish(&result, bytes, cursor.offset);
        },
        0xFF => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            const group_op = modrm.reg;
            const rm_is_reg = switch (rm) {
                .reg => true,
                .mem => false,
            };
            const info: GroupInfo = switch (group_op) {
                0 => .{ .op = RawOp.group5_inc, .mnemonic = "inc", .control = ControlKind.none, .executable = rm_is_reg, .reason = if (rm_is_reg) "" else "INC r/m32 memory form is decoded but not executable in the raw bridge yet" },
                1 => .{ .op = RawOp.group5_dec, .mnemonic = "dec", .control = ControlKind.none, .executable = rm_is_reg, .reason = if (rm_is_reg) "" else "DEC r/m32 memory form is decoded but not executable in the raw bridge yet" },
                2 => .{ .op = RawOp.group5_call, .mnemonic = "call", .control = ControlKind.near_call, .executable = true, .reason = "" },
                4 => .{ .op = RawOp.group5_jmp, .mnemonic = "jmp", .control = ControlKind.near_jump, .executable = true, .reason = "" },
                6 => .{ .op = RawOp.group5_push, .mnemonic = "push", .control = ControlKind.none, .executable = true, .reason = "" },
                3 => .{ .op = RawOp.recognized_unimplemented, .mnemonic = "call", .control = ControlKind.near_call, .executable = false, .reason = "far CALL is decoded but not executable in the raw bridge yet" },
                5 => .{ .op = RawOp.recognized_unimplemented, .mnemonic = "jmp", .control = ControlKind.near_jump, .executable = false, .reason = "far JMP is decoded but not executable in the raw bridge yet" },
                else => .{ .op = RawOp.recognized_unimplemented, .mnemonic = "group5", .control = ControlKind.none, .executable = false, .reason = "undefined Group5 extension" },
            };
            var result = makeBase(address, opcode, info.op, if (info.executable) .executable else .recognized_unimplemented, info.mnemonic);
            result.control = info.control;
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.unsupported_reason = info.reason;
            try appendText(&result, "{s} {s}", .{ info.mnemonic, rm_text });
            return finish(&result, bytes, cursor.offset);
        },
        else => {
            var result = makeBase(address, opcode, .recognized_unimplemented, .recognized_unimplemented, "db");
            result.isa_path = "UNKNOWN";
            result.unsupported_reason = "opcode is not decoded by the PE raw bridge yet";
            try appendText(&result, "db 0x{X:0>2}", .{opcode});
            return finish(&result, bytes, cursor.offset);
        },
    }
}

pub fn validateGlobalIsaCoverage() void {
    const required = [_][]const u8{
        "ADD",
        "AND",
        "CALL",
        "CMP",
        "DEC",
        "INC",
        "JMP",
        "MOV",
        "POP",
        "PUSH",
        "RET",
        "SUB",
        "XOR",
    };
    for (required) |name| {
        std.debug.assert(isa_registry.x86.findByName(name) != null);
    }
}

test "portable register arithmetic decodes through the ISA highway" {
    const add = try decodeInstruction(0x00401000, &.{ 0x01, 0xC8 });
    try std.testing.expectEqual(RawOp.binary_reg_reg, add.op);
    try std.testing.expectEqual(DecodeStatus.executable, add.status);
    try std.testing.expectEqual(highway.BinaryOp.add, add.binary_op.?);
    try std.testing.expectEqual(highway.Width.bits32, add.width);

    const sbb = try decodeInstruction(0x00401002, &.{ 0x19, 0xC9 });
    try std.testing.expectEqual(RawOp.binary_reg_reg, sbb.op);
    try std.testing.expectEqual(highway.BinaryOp.sbb, sbb.binary_op.?);
    try std.testing.expectEqualStrings("ADC-SBB/SBB.inc", sbb.isa_path);

    const memory = try decodeInstruction(0x00401004, &.{ 0x29, 0x08 });
    try std.testing.expectEqual(DecodeStatus.recognized_unimplemented, memory.status);
    try std.testing.expectEqual(highway.BinaryOp.sub, memory.binary_op.?);
}

test "decodes Group5 absolute indirect JMP through global ISA table" {
    validateGlobalIsaCoverage();
    const bytes = [_]u8{ 0xFF, 0x25, 0x00, 0x20, 0x40, 0x00 };
    const inst = try decodeInstruction(0x0041F7A2, &bytes);
    try std.testing.expectEqual(RawOp.group5_jmp, inst.op);
    try std.testing.expectEqual(@as(u8, 6), inst.len);
    try std.testing.expectEqualStrings("jmp", inst.mnemonic);
    try std.testing.expectEqualStrings("JMP/JMP.inc", inst.isa_path);
    try std.testing.expectEqualStrings("jmp [0x00402000]", inst.textSlice());
    switch (inst.operand.?) {
        .mem => |mem| try std.testing.expectEqual(@as(u32, 0x00402000), mem.absolute.?),
        .reg => return error.ExpectedMemoryOperand,
    }
}

test "decodes Group5 absolute indirect CALL and PUSH" {
    const call_bytes = [_]u8{ 0xFF, 0x15, 0x08, 0x20, 0x40, 0x00 };
    const call = try decodeInstruction(0x00401000, &call_bytes);
    try std.testing.expectEqual(RawOp.group5_call, call.op);
    try std.testing.expectEqualStrings("CALL-RET/CALL.inc", call.isa_path);

    const push_bytes = [_]u8{ 0xFF, 0x35, 0x0C, 0x20, 0x40, 0x00 };
    const push = try decodeInstruction(0x00401006, &push_bytes);
    try std.testing.expectEqual(RawOp.group5_push, push.op);
    try std.testing.expectEqualStrings("PUSH/PUSH.inc", push.isa_path);
}
