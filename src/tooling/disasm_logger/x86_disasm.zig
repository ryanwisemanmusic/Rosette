const std = @import("std");
const x86_asm = @import("x86_asm");
const scaffold = x86_asm.decode_scaffold;
const core = x86_asm.family_core;

const ModRm = scaffold.ModRm;
const Sib = scaffold.Sib;
const DecodeCursor = scaffold.DecodeCursor;
const LegacyPrefixes = scaffold.LegacyPrefixes;

pub const DisasmLine = struct {
    address: u32,
    bytes: [15]u8,
    byte_len: u8,
    text: [80]u8,
    text_len: u8,
};

fn reg32Name(reg: u3) []const u8 {
    return switch (reg) {
        0 => "eax",
        1 => "ecx",
        2 => "edx",
        3 => "ebx",
        4 => "esp",
        5 => "ebp",
        6 => "esi",
        7 => "edi",
    };
}

fn reg8Name(reg: u3) []const u8 {
    return switch (reg) {
        0 => "al",
        1 => "cl",
        2 => "dl",
        3 => "bl",
        4 => "ah",
        5 => "ch",
        6 => "dh",
        7 => "bh",
    };
}

fn reg16Name(reg: u3) []const u8 {
    return switch (reg) {
        0 => "ax",
        1 => "cx",
        2 => "dx",
        3 => "bx",
        4 => "sp",
        5 => "bp",
        6 => "si",
        7 => "di",
    };
}

fn segRegName(reg: u3) []const u8 {
    return switch (reg) {
        0 => "es",
        1 => "cs",
        2 => "ss",
        3 => "ds",
        4 => "fs",
        5 => "gs",
        else => "?",
    };
}

fn formatModRm(buf: []u8, cursor: *DecodeCursor, modrm: ModRm, opsize_32: bool) ![]const u8 {
    _ = opsize_32;

    if (modrm.mod == 3) {
        return std.fmt.bufPrint(buf, "{s}", .{reg32Name(modrm.rm)});
    }

    if (modrm.mod == 0 and modrm.rm == 5) {
        const disp = try cursor.readDisplacement(.dword);
        return std.fmt.bufPrint(buf, "[0x{X:0>8}]", .{@as(u32, @bitCast(disp.value))});
    }

    if (modrm.rm == 4) {
        const sib = try cursor.readSib();
        const scale: u32 = switch (sib.scale) {
            0 => 1,
            1 => 2,
            2 => 4,
            3 => 8,
        };
        const index_str = reg32Name(sib.index);
        const base_str = reg32Name(sib.base);

        if (modrm.mod == 0 and sib.base == 5) {
            const disp = try cursor.readDisplacement(.dword);
            return std.fmt.bufPrint(buf, "[{s}*{d}+0x{X:0>8}]", .{ index_str, scale, @as(u32, @bitCast(disp.value)) });
        }

        const disp = try cursor.readDisplacement(switch (modrm.mod) {
            1 => .byte,
            2 => .dword,
            else => .byte,
        });

        if (modrm.mod == 0) {
            return std.fmt.bufPrint(buf, "[{s}*{d}+{s}]", .{ index_str, scale, base_str });
        }
        if (disp.value == 0) {
            return std.fmt.bufPrint(buf, "[{s}*{d}+{s}]", .{ index_str, scale, base_str });
        }
        if (@as(i32, @bitCast(disp.value)) < 0) {
            return std.fmt.bufPrint(buf, "[{s}*{d}+{s}-0x{X}]", .{ index_str, scale, base_str, @as(u32, @bitCast(-disp.value)) });
        }
        return std.fmt.bufPrint(buf, "[{s}*{d}+{s}+0x{X}]", .{ index_str, scale, base_str, @as(u32, @bitCast(disp.value)) });
    }

    const rm_str = reg32Name(modrm.rm);
    const disp = try cursor.readDisplacement(switch (modrm.mod) {
        1 => .byte,
        2 => .dword,
        else => .byte,
    });

    switch (modrm.mod) {
        0 => return std.fmt.bufPrint(buf, "[{s}]", .{rm_str}),
        1 => {
            if (disp.value == 0) return std.fmt.bufPrint(buf, "[{s}]", .{rm_str});
            if (@as(i32, @bitCast(disp.value)) < 0)
                return std.fmt.bufPrint(buf, "[{s}-0x{X}]", .{ rm_str, @as(u32, @bitCast(-disp.value)) })
            else
                return std.fmt.bufPrint(buf, "[{s}+0x{X}]", .{ rm_str, @as(u32, @bitCast(disp.value)) });
        },
        2 => {
            if (@as(i32, @bitCast(disp.value)) < 0)
                return std.fmt.bufPrint(buf, "[{s}-0x{X}]", .{ rm_str, @as(u32, @bitCast(-disp.value)) })
            else
                return std.fmt.bufPrint(buf, "[{s}+0x{X}]", .{ rm_str, @as(u32, @bitCast(disp.value)) });
        },
        else => unreachable,
    }
}

fn formatRegOrMem(buf: []u8, cursor: *DecodeCursor, modrm: ModRm, w: u1) ![]const u8 {
    if (modrm.mod == 3) {
        return std.fmt.bufPrint(buf, "{s}", .{if (w == 1) reg32Name(modrm.rm) else reg8Name(modrm.rm)});
    }
    return formatModRm(buf, cursor, modrm, true);
}

fn groupName(reg: u3) []const u8 {
    return switch (reg) {
        0 => "ADD",
        1 => "OR",
        2 => "ADC",
        3 => "SBB",
        4 => "AND",
        5 => "SUB",
        6 => "XOR",
        7 => "CMP",
    };
}

pub fn decodeInstruction(address: u32, bytes: []const u8) !DisasmLine {
    var result = DisasmLine{
        .address = address,
        .bytes = [_]u8{0} ** 15,
        .byte_len = 0,
        .text = [_]u8{0} ** 80,
        .text_len = 0,
    };

    var cursor = DecodeCursor{ .bytes = bytes, .offset = 0 };
    var prefixes = LegacyPrefixes{};
    var opsize_32 = true;
    var addr_size_32 = true;
    var start_offset: usize = 0;

    while (cursor.remaining() > 0) {
        const b = try cursor.readU8();
        start_offset = cursor.offset - 1;
        if (b == 0x66) {
            opsize_32 = false;
            prefixes.operand_size_override = true;
            continue;
        }
        if (b == 0x67) {
            addr_size_32 = false;
            prefixes.address_size_override = true;
            continue;
        }
        if (b == 0xF0) {
            prefixes.lock = true;
            continue;
        }
        if (b == 0xF2) {
            prefixes.repne = true;
            continue;
        }
        if (b == 0xF3) {
            prefixes.rep = true;
            continue;
        }
        if (b == 0x2E) {
            prefixes.segment_override = .cs;
            continue;
        }
        if (b == 0x36) {
            prefixes.segment_override = .ss;
            continue;
        }
        if (b == 0x3E) {
            prefixes.segment_override = .ds;
            continue;
        }
        if (b == 0x26) {
            prefixes.segment_override = .es;
            continue;
        }
        if (b == 0x64) {
            prefixes.segment_override = .fs;
            continue;
        }
        if (b == 0x65) {
            prefixes.segment_override = .gs;
            continue;
        }
        break;
    }

    cursor.offset = start_offset;
    const total_prefixes = start_offset;
    _ = total_prefixes;

    const op1 = try cursor.readU8();

    var mnemonic: []const u8 = "db";
    var has_modrm = false;
    var imm_size: u8 = 0;
    const imm2_size: u8 = 0;
    var is_group = false;
    var group_op: u3 = 0;
    var w: u1 = 1;
    var d: u1 = 1;
    var s: u1 = 0;
    var is_jmp_call = false;
    var rel_size: u8 = 0;
    const is_two_byte = false;
    const two_byte_op: u8 = 0;

    switch (op1) {
        0x00...0x03 => {
            mnemonic = "add";
            has_modrm = true;
            w = @truncate(op1 & 1);
            d = @as(u1, @truncate((op1 >> 1) & 1));
        },
        0x08...0x0B => {
            mnemonic = "or";
            has_modrm = true;
            w = @truncate(op1 & 1);
            d = @as(u1, @truncate((op1 >> 1) & 1));
        },
        0x10...0x13 => {
            mnemonic = "adc";
            has_modrm = true;
            w = @truncate(op1 & 1);
            d = @as(u1, @truncate((op1 >> 1) & 1));
        },
        0x18...0x1B => {
            mnemonic = "sbb";
            has_modrm = true;
            w = @truncate(op1 & 1);
            d = @as(u1, @truncate((op1 >> 1) & 1));
        },
        0x20...0x23 => {
            mnemonic = "and";
            has_modrm = true;
            w = @truncate(op1 & 1);
            d = @as(u1, @truncate((op1 >> 1) & 1));
        },
        0x28...0x2B => {
            mnemonic = "sub";
            has_modrm = true;
            w = @truncate(op1 & 1);
            d = @as(u1, @truncate((op1 >> 1) & 1));
        },
        0x30...0x33 => {
            mnemonic = "xor";
            has_modrm = true;
            w = @truncate(op1 & 1);
            d = @as(u1, @truncate((op1 >> 1) & 1));
        },
        0x38...0x3B => {
            mnemonic = "cmp";
            has_modrm = true;
            w = @truncate(op1 & 1);
            d = @as(u1, @truncate((op1 >> 1) & 1));
        },

        0x50...0x57 => {
            const reg: u3 = @truncate(op1 - 0x50);
            mnemonic = "push";
            var tmp: [16]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "push {s}", .{reg32Name(reg)});
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0x58...0x5F => {
            const reg: u3 = @truncate(op1 - 0x58);
            mnemonic = "pop";
            var tmp: [16]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "pop {s}", .{reg32Name(reg)});
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },

        0x68 => {
            mnemonic = "push";
            imm_size = 4;
        },
        0x6A => {
            mnemonic = "push";
            imm_size = 1;
            s = 1;
        },

        0x70 => {
            mnemonic = "jo";
            rel_size = 1;
        },
        0x71 => {
            mnemonic = "jno";
            rel_size = 1;
        },
        0x72 => {
            mnemonic = "jb";
            rel_size = 1;
        },
        0x73 => {
            mnemonic = "jnb";
            rel_size = 1;
        },
        0x74 => {
            mnemonic = "jz";
            rel_size = 1;
        },
        0x75 => {
            mnemonic = "jnz";
            rel_size = 1;
        },
        0x76 => {
            mnemonic = "jbe";
            rel_size = 1;
        },
        0x77 => {
            mnemonic = "ja";
            rel_size = 1;
        },
        0x78 => {
            mnemonic = "js";
            rel_size = 1;
        },
        0x79 => {
            mnemonic = "jns";
            rel_size = 1;
        },
        0x7A => {
            mnemonic = "jp";
            rel_size = 1;
        },
        0x7B => {
            mnemonic = "jnp";
            rel_size = 1;
        },
        0x7C => {
            mnemonic = "jl";
            rel_size = 1;
        },
        0x7D => {
            mnemonic = "jnl";
            rel_size = 1;
        },
        0x7E => {
            mnemonic = "jle";
            rel_size = 1;
        },
        0x7F => {
            mnemonic = "jg";
            rel_size = 1;
        },

        0x80, 0x82 => {
            mnemonic = "group1";
            is_group = true;
            has_modrm = true;
            w = 0;
            imm_size = 1;
        },
        0x81 => {
            mnemonic = "group1";
            is_group = true;
            has_modrm = true;
            w = 1;
            imm_size = if (opsize_32) @as(u8, 4) else 2;
        },
        0x83 => {
            mnemonic = "group1";
            is_group = true;
            has_modrm = true;
            w = 1;
            imm_size = 1;
            s = 1;
        },

        0x84 => {
            mnemonic = "test";
            has_modrm = true;
            w = 0;
        },
        0x85 => {
            mnemonic = "test";
            has_modrm = true;
            w = 1;
        },
        0x86, 0x87 => {
            mnemonic = "xchg";
            has_modrm = true;
            w = @truncate(op1 & 1);
        },
        0x88 => {
            mnemonic = "mov";
            has_modrm = true;
            w = 0;
            d = 0;
        },
        0x89 => {
            mnemonic = "mov";
            has_modrm = true;
            w = 1;
            d = 0;
        },
        0x8A => {
            mnemonic = "mov";
            has_modrm = true;
            w = 0;
            d = 1;
        },
        0x8B => {
            mnemonic = "mov";
            has_modrm = true;
            w = 1;
            d = 1;
        },
        0x8D => {
            mnemonic = "lea";
            has_modrm = true;
        },

        0x8F => {
            mnemonic = "pop";
            has_modrm = true;
        },

        0x90 => {
            const txt = "nop";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0x91...0x97 => {
            const reg: u3 = @truncate(op1 - 0x90);
            var tmp: [32]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "xchg {s}, eax", .{reg32Name(reg)});
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0x98 => {
            const txt = "cwde";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 4;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0x99 => {
            const txt = "cdq";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 3;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0x9C => {
            const txt = "pushf";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0x9D => {
            const txt = "popf";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 4;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },

        0xA0 => {
            mnemonic = "mov";
            w = 0;
            d = 1;
            imm_size = 4;
        },
        0xA1 => {
            mnemonic = "mov";
            w = 1;
            d = 1;
            imm_size = 4;
        },
        0xA2 => {
            mnemonic = "mov";
            w = 0;
            d = 0;
            imm_size = 4;
        },
        0xA3 => {
            mnemonic = "mov";
            w = 1;
            d = 0;
            imm_size = 4;
        },

        0xA4 => {
            const txt = "movsb";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xA5 => {
            const txt = "movsd";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xAA => {
            const txt = "stosb";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xAB => {
            const txt = "stosd";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xAC => {
            const txt = "lodsb";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xAD => {
            const txt = "lodsd";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xAE => {
            const txt = "scasb";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xAF => {
            const txt = "scasd";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },

        0xB0...0xB7 => {
            const reg: u3 = @truncate(op1 - 0xB0);
            const imm = try cursor.readImmediate(.byte);
            var tmp: [32]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "mov {s}, 0x{X:0>2}", .{ reg8Name(reg), imm.value });
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xB8...0xBF => {
            const reg: u3 = @truncate(op1 - 0xB8);
            const imm = try cursor.readImmediate(.dword);
            var tmp: [32]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "mov {s}, 0x{X:0>8}", .{ reg32Name(reg), imm.value });
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },

        0xC0, 0xC1 => {
            mnemonic = "group2";
            is_group = true;
            has_modrm = true;
            w = @truncate(op1 & 1);
            imm_size = 1;
        },
        0xC2 => {
            mnemonic = "ret";
            imm_size = 2;
        },
        0xC3 => {
            const txt = "ret";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 3;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xC6 => {
            mnemonic = "mov";
            has_modrm = true;
            w = 0;
            imm_size = 1;
        },
        0xC7 => {
            mnemonic = "mov";
            has_modrm = true;
            w = 1;
            imm_size = if (opsize_32) @as(u8, 4) else 2;
        },
        0xC9 => {
            const txt = "leave";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 5;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xCC => {
            const txt = "int3";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 4;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xCD => {
            const imm = try cursor.readImmediate(.byte);
            var tmp: [32]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "int 0x{X:0>2}", .{imm.value});
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },

        0xD0, 0xD2 => {
            mnemonic = "group2";
            is_group = true;
            has_modrm = true;
            w = 0;
        },
        0xD1, 0xD3 => {
            mnemonic = "group2";
            is_group = true;
            has_modrm = true;
            w = 1;
        },

        0xE0 => {
            rel_size = 1;
            mnemonic = "loopne";
        },
        0xE1 => {
            rel_size = 1;
            mnemonic = "loope";
        },
        0xE2 => {
            rel_size = 1;
            mnemonic = "loop";
        },
        0xE3 => {
            rel_size = 1;
            mnemonic = "jecxz";
        },
        0xE8 => {
            rel_size = if (opsize_32) @as(u8, 4) else 2;
            mnemonic = "call";
            is_jmp_call = true;
        },
        0xE9 => {
            rel_size = if (opsize_32) @as(u8, 4) else 2;
            mnemonic = "jmp";
            is_jmp_call = true;
        },
        0xEB => {
            rel_size = 1;
            mnemonic = "jmp";
            is_jmp_call = true;
        },

        0xF4 => {
            const txt = "hlt";
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = 3;
            result.byte_len = @intCast(cursor.offset);
            const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
            @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
            return result;
        },
        0xF6 => {
            mnemonic = "group3";
            is_group = true;
            has_modrm = true;
            w = 0;
        },
        0xF7 => {
            mnemonic = "group3";
            is_group = true;
            has_modrm = true;
            w = 1;
        },
        0xFE => {
            mnemonic = "group4";
            is_group = true;
            has_modrm = true;
            w = 0;
        },
        0xFF => {
            mnemonic = "group5";
            is_group = true;
            has_modrm = true;
        },

        else => {
            mnemonic = "db";
            has_modrm = false;
        },
    }

    if (is_two_byte) {
        _ = two_byte_op;
    }

    var modrm: ?ModRm = null;
    if (has_modrm) {
        if (cursor.remaining() == 0) return error.EndOfStream;
        modrm = try cursor.readModRm();
    }

    if (is_group and modrm != null) {
        group_op = modrm.?.reg;
        if (std.mem.eql(u8, mnemonic, "group1")) mnemonic = groupName(group_op);
        if (std.mem.eql(u8, mnemonic, "group2")) {
            mnemonic = switch (group_op) {
                0 => "rol",
                1 => "ror",
                2 => "rcl",
                3 => "rcr",
                4 => "shl",
                5 => "shr",
                else => "group2",
            };
        }
        if (std.mem.eql(u8, mnemonic, "group3")) {
            mnemonic = switch (group_op) {
                0 => "test",
                1 => "test",
                2 => "not",
                3 => "neg",
                4 => "mul",
                5 => "imul",
                6 => "div",
                7 => "idiv",
            };
        }
        if (std.mem.eql(u8, mnemonic, "group4")) {
            mnemonic = if (group_op == 0) "inc" else "dec";
        }
        if (std.mem.eql(u8, mnemonic, "group5")) {
            mnemonic = switch (group_op) {
                0 => "inc",
                1 => "dec",
                2 => "call",
                4 => "jmp",
                6 => "push",
                else => "group5",
            };
        }
    }

    var modrm_buf: [80]u8 = undefined;
    const modrm_str = if (has_modrm and modrm != null) try formatRegOrMem(&modrm_buf, &cursor, modrm.?, w) else "";

    if (is_jmp_call and rel_size > 0) {
        const next_addr = address + @as(u32, @intCast(cursor.offset));
        const rel = if (rel_size == 1) blk: {
            const val = try cursor.readImmediate(.byte);
            const v: u32 = @truncate(val.value);
            break :blk @as(i32, @bitCast(v));
        } else blk: {
            const val = try cursor.readImmediate(.dword);
            const v: u32 = @truncate(val.value);
            break :blk @as(i32, @bitCast(v));
        };
        const target = @as(u32, @bitCast(@as(i32, @bitCast(next_addr)) + rel));
        var tmp: [48]u8 = undefined;
        const txt = try std.fmt.bufPrint(&tmp, "{s} 0x{X:0>8}", .{ mnemonic, target });
        @memcpy(result.text[0..txt.len], txt);
        result.text_len = @intCast(txt.len);
        result.byte_len = @intCast(cursor.offset);
        const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
        @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
        return result;
    }

    if (imm_size > 0 and imm2_size == 0) {
        const imm_width: core.OperandWidth = switch (imm_size) {
            1 => .byte,
            2 => .word,
            4 => .dword,
            else => .byte,
        };
        const imm = try cursor.readImmediate(imm_width);

        if (has_modrm and modrm != null) {
            if (std.mem.eql(u8, mnemonic, "test") or std.mem.eql(u8, mnemonic, "mov")) {
                var tmp: [80]u8 = undefined;
                const txt = try std.fmt.bufPrint(&tmp, "{s} {s}, 0x{X}", .{ mnemonic, modrm_str, imm.value });
                @memcpy(result.text[0..txt.len], txt);
                result.text_len = @intCast(txt.len);
            } else if (std.mem.eql(u8, mnemonic, "push")) {
                var tmp: [32]u8 = undefined;
                const txt = try std.fmt.bufPrint(&tmp, "push 0x{X}", .{imm.value});
                @memcpy(result.text[0..txt.len], txt);
                result.text_len = @intCast(txt.len);
            } else if (s == 1) {
                const signed_val = @as(i8, @bitCast(@as(u8, @truncate(imm.value))));
                var tmp: [80]u8 = undefined;
                const txt = try std.fmt.bufPrint(&tmp, "{s} {s}, {d}", .{ mnemonic, modrm_str, signed_val });
                @memcpy(result.text[0..txt.len], txt);
                result.text_len = @intCast(txt.len);
            } else {
                var tmp: [80]u8 = undefined;
                const txt = try std.fmt.bufPrint(&tmp, "{s} {s}, 0x{X}", .{ mnemonic, modrm_str, imm.value });
                @memcpy(result.text[0..txt.len], txt);
                result.text_len = @intCast(txt.len);
            }
        } else if (std.mem.eql(u8, mnemonic, "ret")) {
            var tmp: [32]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "ret 0x{X}", .{imm.value});
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
        } else {
            var tmp: [32]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "{s} 0x{X}", .{ mnemonic, imm.value });
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
        }
    } else if (has_modrm and modrm != null) {
        if (std.mem.eql(u8, mnemonic, "lea")) {
            var tmp: [80]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "lea {s}, {s}", .{ reg32Name(modrm.?.reg), modrm_str });
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
        } else if (std.mem.eql(u8, mnemonic, "mov") or std.mem.eql(u8, mnemonic, "xchg") or
            std.mem.eql(u8, mnemonic, "add") or std.mem.eql(u8, mnemonic, "sub") or
            std.mem.eql(u8, mnemonic, "cmp") or std.mem.eql(u8, mnemonic, "and") or
            std.mem.eql(u8, mnemonic, "or") or std.mem.eql(u8, mnemonic, "xor") or
            std.mem.eql(u8, mnemonic, "adc") or std.mem.eql(u8, mnemonic, "sbb") or
            std.mem.eql(u8, mnemonic, "test"))
        {
            if (d == 1) {
                var tmp: [80]u8 = undefined;
                const txt = try std.fmt.bufPrint(&tmp, "{s} {s}, {s}", .{ mnemonic, reg32Name(modrm.?.reg), modrm_str });
                @memcpy(result.text[0..txt.len], txt);
                result.text_len = @intCast(txt.len);
            } else {
                var tmp: [80]u8 = undefined;
                const txt = try std.fmt.bufPrint(&tmp, "{s} {s}, {s}", .{ mnemonic, modrm_str, reg32Name(modrm.?.reg) });
                @memcpy(result.text[0..txt.len], txt);
                result.text_len = @intCast(txt.len);
            }
        } else if (std.mem.eql(u8, mnemonic, "pop") or std.mem.eql(u8, mnemonic, "not") or
            std.mem.eql(u8, mnemonic, "neg") or std.mem.eql(u8, mnemonic, "mul") or
            std.mem.eql(u8, mnemonic, "imul") or std.mem.eql(u8, mnemonic, "div") or
            std.mem.eql(u8, mnemonic, "idiv") or std.mem.eql(u8, mnemonic, "inc") or
            std.mem.eql(u8, mnemonic, "dec"))
        {
            var tmp: [80]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "{s} {s}", .{ mnemonic, modrm_str });
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
        } else if (std.mem.eql(u8, mnemonic, "call") or std.mem.eql(u8, mnemonic, "jmp")) {
            var tmp: [80]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "{s} {s}", .{ mnemonic, modrm_str });
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
        } else if (std.mem.eql(u8, mnemonic, "push")) {
            var tmp: [80]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "push {s}", .{modrm_str});
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
        } else {
            var tmp: [80]u8 = undefined;
            const txt = try std.fmt.bufPrint(&tmp, "{s} {s}", .{ mnemonic, modrm_str });
            @memcpy(result.text[0..txt.len], txt);
            result.text_len = @intCast(txt.len);
        }
    } else {
        var tmp: [32]u8 = undefined;
        const txt = try std.fmt.bufPrint(&tmp, "{s}", .{mnemonic});
        @memcpy(result.text[0..txt.len], txt);
        result.text_len = @intCast(txt.len);
    }

    result.byte_len = @intCast(cursor.offset);
    const copy_len = @min(@as(usize, cursor.offset), result.bytes.len);
    @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
    return result;
}
