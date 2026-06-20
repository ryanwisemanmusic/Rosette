const std = @import("std");
const x86_asm = @import("x86_asm");
const isa = x86_asm.instruction_set;
const raw_decode = x86_asm.raw_decoder;
const Register = isa.Register;
const Executor = x86_asm.instruction_operations.Executor;

extern "C" fn rosette_debug_x86_disasm_enabled() c_int;
extern "C" fn rosette_debug_log_path() [*:0]const u8;

var trace_file: ?*std.c.FILE = null;
var trace_enabled: bool = false;

fn decodeRegister(encoded: i32) Register {
    return @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(encoded)))));
}

fn formatInstruction(buf: []u8, inst: isa.InstructionDef) ![]const u8 {
    switch (inst.opcode) {
        .nop, .exit => return std.fmt.bufPrint(buf, "{s}", .{@tagName(inst.opcode)}),
        .mov_reg_imm, .add_reg_imm, .sub_reg_imm, .cmp_reg_imm => {
            var tmp: [32]u8 = undefined;
            const reg = std.fmt.bufPrint(&tmp, "{s}", .{@tagName(decodeRegister(inst.op1))}) catch unreachable;
            return std.fmt.bufPrint(buf, "{s} {s}, {d}", .{ @tagName(inst.opcode), reg, inst.op2 });
        },
        .mov_reg_reg, .add_reg_reg, .sub_reg_reg, .cmp_reg_reg, .test_reg_reg, .xor_reg_reg, .and_reg_reg, .or_reg_reg => {
            var lhs_buf: [32]u8 = undefined;
            var rhs_buf: [32]u8 = undefined;
            const lhs = std.fmt.bufPrint(&lhs_buf, "{s}", .{@tagName(decodeRegister(inst.op1))}) catch unreachable;
            const rhs = std.fmt.bufPrint(&rhs_buf, "{s}", .{@tagName(decodeRegister(inst.op2))}) catch unreachable;
            return std.fmt.bufPrint(buf, "{s} {s}, {s}", .{ @tagName(inst.opcode), lhs, rhs });
        },
        .mov_mem_imm => return std.fmt.bufPrint(buf, "mov_mem_imm [0x{X:0>8}], {d}", .{ @as(u32, @bitCast(inst.op1)), inst.op2 }),
        .mov_mem_reg, .mov_mem_reg8 => {
            var rhs_buf: [32]u8 = undefined;
            const rhs = std.fmt.bufPrint(&rhs_buf, "{s}", .{@tagName(decodeRegister(inst.op2))}) catch unreachable;
            return std.fmt.bufPrint(buf, "{s} [0x{X:0>8}], {s}", .{ @tagName(inst.opcode), @as(u32, @bitCast(inst.op1)), rhs });
        },
        .mov_reg_mem, .movzx_reg_mem, .lea_reg_mem => {
            var lhs_buf: [32]u8 = undefined;
            const lhs = std.fmt.bufPrint(&lhs_buf, "{s}", .{@tagName(decodeRegister(inst.op1))}) catch unreachable;
            return std.fmt.bufPrint(buf, "{s} {s}, [0x{X:0>8}]", .{ @tagName(inst.opcode), lhs, @as(u32, @bitCast(inst.op2)) });
        },
        .inc_reg, .dec_reg, .mul_reg, .imul_reg, .div_reg, .not_reg, .neg_reg, .shl_reg_cl, .shr_reg_cl => {
            var reg_buf: [32]u8 = undefined;
            const reg = std.fmt.bufPrint(&reg_buf, "{s}", .{@tagName(decodeRegister(inst.op1))}) catch unreachable;
            return std.fmt.bufPrint(buf, "{s} {s}", .{ @tagName(inst.opcode), reg });
        },
        .jmp, .je, .jne, .jl, .jge, .jg, .jle, .call => {
            return std.fmt.bufPrint(buf, "{s} 0x{X:0>8}", .{ @tagName(inst.opcode), @as(u32, @bitCast(inst.op1)) });
        },
        .ret => return std.fmt.bufPrint(buf, "ret", .{}),
        .ret_imm => return std.fmt.bufPrint(buf, "ret {d}", .{inst.op1}),
        .push_reg, .pop_reg => {
            var reg_buf: [32]u8 = undefined;
            const reg = std.fmt.bufPrint(&reg_buf, "{s}", .{@tagName(decodeRegister(inst.op1))}) catch unreachable;
            return std.fmt.bufPrint(buf, "{s} {s}", .{ @tagName(inst.opcode), reg });
        },
        .call_thunk => return std.fmt.bufPrint(buf, "call_thunk {d}", .{@as(u32, @bitCast(inst.op1))}),
    }
}

pub fn initFromHostConfig() void {
    if (rosette_debug_x86_disasm_enabled() == 0) return;

    const path_z = rosette_debug_log_path();
    const path = std.mem.span(path_z);
    if (path.len == 0) return;

    trace_file = std.c.fopen(path_z, "w");
    if (trace_file == null) return;

    trace_enabled = true;
    if (trace_file) |file| {
        _ = std.c.fwrite("# Rosette x86 instruction trace\n", 1, "# Rosette x86 instruction trace\n".len, file);
    }
}

pub fn initMandatory(log_path_z: [*:0]const u8) void {
    const path = std.mem.span(log_path_z);
    if (path.len == 0) return;

    if (trace_file) |file| _ = std.c.fclose(file);
    trace_file = std.c.fopen(log_path_z, "w");
    if (trace_file == null) {
        trace_enabled = false;
        return;
    }

    trace_enabled = true;
    if (trace_file) |file| {
        _ = std.c.fwrite("# Rosette mandatory x86 instruction trace\n", 1, "# Rosette mandatory x86 instruction trace\n".len, file);
    }
}

pub fn deinit() void {
    if (trace_file) |file| {
        _ = std.c.fclose(file);
    }
    trace_file = null;
    trace_enabled = false;
}

pub fn isEnabled() bool {
    return trace_enabled;
}

pub fn logText(text: []const u8) void {
    if (!trace_enabled) return;
    if (trace_file) |file| {
        _ = std.c.fwrite(text.ptr, 1, text.len, file);
    }
}

pub fn logBadOpcode(eip: u32, raw: []const u8) void {
    if (!trace_enabled) return;
    var hex_buf: [128]u8 = undefined;
    var hex_len: usize = 0;
    for (raw, 0..) |b, i| {
        if (i >= 12) break;
        if (i > 0) {
            hex_buf[hex_len] = ' ';
            hex_len += 1;
        }
        _ = std.fmt.bufPrint(hex_buf[hex_len..], "{X:0>2}", .{b}) catch return;
        hex_len += 2;
    }
    var line_buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buf, "0x{X:0>8}: <bad opcode {d}> [{s}]\n", .{ eip, raw[0], hex_buf[0..hex_len] }) catch return;
    if (trace_file) |file| {
        _ = std.c.fwrite(line.ptr, 1, line.len, file);
    }
}

pub fn logRawInstruction(eip: u32, decoded: raw_decode.DecodedInstruction, ex: *const Executor) void {
    if (!trace_enabled) return;
    var hex_buf: [128]u8 = undefined;
    var hex_len: usize = 0;
    const visible = @min(@as(usize, decoded.len), decoded.bytes.len);
    for (decoded.bytes[0..visible], 0..) |b, i| {
        if (i > 0) {
            hex_buf[hex_len] = ' ';
            hex_len += 1;
        }
        _ = std.fmt.bufPrint(hex_buf[hex_len..], "{X:0>2}", .{b}) catch return;
        hex_len += 2;
    }

    var line_buf: [512]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "0x{X:0>8}: {s} [{s}] ; isa={s} status={s} eax=0x{X:0>8} ebx=0x{X:0>8} ecx=0x{X:0>8} edx=0x{X:0>8} esp=0x{X:0>8} eip=0x{X:0>8}\n",
        .{
            eip,
            decoded.textSlice(),
            hex_buf[0..hex_len],
            decoded.isa_path,
            @tagName(decoded.status),
            ex.regs.eax,
            ex.regs.ebx,
            ex.regs.ecx,
            ex.regs.edx,
            ex.regs.esp,
            ex.regs.eip,
        },
    ) catch return;
    if (trace_file) |file| {
        _ = std.c.fwrite(line.ptr, 1, line.len, file);
    }
}

pub fn logRawStop(eip: u32, decoded: raw_decode.DecodedInstruction, reason: []const u8) void {
    if (!trace_enabled) return;
    var hex_buf: [128]u8 = undefined;
    var hex_len: usize = 0;
    const visible = @min(@as(usize, decoded.len), decoded.bytes.len);
    for (decoded.bytes[0..visible], 0..) |b, i| {
        if (i > 0) {
            hex_buf[hex_len] = ' ';
            hex_len += 1;
        }
        _ = std.fmt.bufPrint(hex_buf[hex_len..], "{X:0>2}", .{b}) catch return;
        hex_len += 2;
    }

    var line_buf: [512]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "0x{X:0>8}: <unsupported raw x86> {s} [{s}] ; isa={s} reason={s}\n",
        .{ eip, decoded.textSlice(), hex_buf[0..hex_len], decoded.isa_path, reason },
    ) catch return;
    if (trace_file) |file| {
        _ = std.c.fwrite(line.ptr, 1, line.len, file);
    }
}

pub fn logInstruction(eip: u32, inst: isa.InstructionDef, ex: *const Executor) void {
    if (!trace_enabled) return;

    var inst_buf: [128]u8 = undefined;
    const inst_text = formatInstruction(&inst_buf, inst) catch return;

    var line_buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buf, "0x{X:0>8}: {s} ; eax=0x{X:0>8} ebx=0x{X:0>8} ecx=0x{X:0>8} edx=0x{X:0>8} esp=0x{X:0>8} eip=0x{X:0>8}\n", .{
        eip,
        inst_text,
        ex.regs.eax,
        ex.regs.ebx,
        ex.regs.ecx,
        ex.regs.edx,
        ex.regs.esp,
        ex.regs.eip,
    }) catch return;

    if (trace_file) |file| {
        _ = std.c.fwrite(line.ptr, 1, line.len, file);
    }
}

test "formats call_thunk instruction" {
    var buf: [128]u8 = undefined;
    const text = try formatInstruction(&buf, .{
        .opcode = .call_thunk,
        .op1 = @as(i32, @bitCast(@as(u32, 5))),
        .op2 = 0,
    });
    try std.testing.expectEqualStrings("call_thunk 5", text);
}
