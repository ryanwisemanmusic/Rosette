const std = @import("std");
const isa = @import("instruction_set.zig");
const Register = isa.Register;
const Executor = @import("instruction_operations.zig").Executor;

extern "C" fn rosette_debug_x86_disasm_enabled() c_int;
extern "C" fn rosette_debug_log_path() [*:0]const u8;

var trace_file: ?*std.c.FILE = null;
var trace_enabled: bool = false;
var instruction_trace_enabled: bool = true;

fn instructionsEnabledFromEnvironment() bool {
    const value_ptr = std.c.getenv("ROSETTE_TRACE_INSTRUCTIONS") orelse return true;
    const value = std.mem.sliceTo(value_ptr, 0);
    return !std.mem.eql(u8, value, "0") and !std.ascii.eqlIgnoreCase(value, "false");
}

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

fn formatArm64Shadow(buf: []u8, inst: isa.InstructionDef) ![]const u8 {
    switch (inst.opcode) {
        .nop => return std.fmt.bufPrint(buf, "nop", .{}),
        .exit => return std.fmt.bufPrint(buf, "ret", .{}),
        .mov_reg_imm => return std.fmt.bufPrint(buf, "mov w0, #{d}", .{inst.op2}),
        .mov_reg_reg => return std.fmt.bufPrint(buf, "mov w0, w1", .{}),
        .mov_mem_imm => return std.fmt.bufPrint(buf, "mov w9, #{d}; str w9, [mem+0x{X:0>8}]", .{ inst.op2, @as(u32, @bitCast(inst.op1)) }),
        .mov_mem_reg, .mov_mem_reg8 => return std.fmt.bufPrint(buf, "str w0, [mem+0x{X:0>8}]", .{@as(u32, @bitCast(inst.op1))}),
        .mov_reg_mem, .movzx_reg_mem => return std.fmt.bufPrint(buf, "ldr w0, [mem+0x{X:0>8}]", .{@as(u32, @bitCast(inst.op2))}),
        .lea_reg_mem => return std.fmt.bufPrint(buf, "adr x0, mem+0x{X:0>8}", .{@as(u32, @bitCast(inst.op2))}),
        .add_reg_imm => return std.fmt.bufPrint(buf, "add w0, w0, #{d}", .{inst.op2}),
        .add_reg_reg => return std.fmt.bufPrint(buf, "add w0, w0, w1", .{}),
        .sub_reg_imm => return std.fmt.bufPrint(buf, "sub w0, w0, #{d}", .{inst.op2}),
        .sub_reg_reg => return std.fmt.bufPrint(buf, "sub w0, w0, w1", .{}),
        .cmp_reg_imm => return std.fmt.bufPrint(buf, "cmp w0, #{d}", .{inst.op2}),
        .cmp_reg_reg => return std.fmt.bufPrint(buf, "cmp w0, w1", .{}),
        .test_reg_reg => return std.fmt.bufPrint(buf, "tst w0, w1", .{}),
        .xor_reg_reg => return std.fmt.bufPrint(buf, "eor w0, w0, w1", .{}),
        .and_reg_reg => return std.fmt.bufPrint(buf, "and w0, w0, w1", .{}),
        .or_reg_reg => return std.fmt.bufPrint(buf, "orr w0, w0, w1", .{}),
        .inc_reg => return std.fmt.bufPrint(buf, "add w0, w0, #1", .{}),
        .dec_reg => return std.fmt.bufPrint(buf, "sub w0, w0, #1", .{}),
        .not_reg => return std.fmt.bufPrint(buf, "mvn w0, w0", .{}),
        .neg_reg => return std.fmt.bufPrint(buf, "neg w0, w0", .{}),
        .shl_reg_cl => return std.fmt.bufPrint(buf, "lsl w0, w0, w1", .{}),
        .shr_reg_cl => return std.fmt.bufPrint(buf, "lsr w0, w0, w1", .{}),
        .mul_reg, .imul_reg => return std.fmt.bufPrint(buf, "mul w0, w0, w1", .{}),
        .div_reg => return std.fmt.bufPrint(buf, "udiv w0, w0, w1", .{}),
        .jmp => return std.fmt.bufPrint(buf, "b 0x{X:0>8}", .{@as(u32, @bitCast(inst.op1))}),
        .je => return std.fmt.bufPrint(buf, "b.eq 0x{X:0>8}", .{@as(u32, @bitCast(inst.op1))}),
        .jne => return std.fmt.bufPrint(buf, "b.ne 0x{X:0>8}", .{@as(u32, @bitCast(inst.op1))}),
        .jl => return std.fmt.bufPrint(buf, "b.lt 0x{X:0>8}", .{@as(u32, @bitCast(inst.op1))}),
        .jge => return std.fmt.bufPrint(buf, "b.ge 0x{X:0>8}", .{@as(u32, @bitCast(inst.op1))}),
        .jg => return std.fmt.bufPrint(buf, "b.gt 0x{X:0>8}", .{@as(u32, @bitCast(inst.op1))}),
        .jle => return std.fmt.bufPrint(buf, "b.le 0x{X:0>8}", .{@as(u32, @bitCast(inst.op1))}),
        .call => return std.fmt.bufPrint(buf, "bl 0x{X:0>8}", .{@as(u32, @bitCast(inst.op1))}),
        .ret => return std.fmt.bufPrint(buf, "ret", .{}),
        .ret_imm => return std.fmt.bufPrint(buf, "add sp, sp, #{d}; ret", .{inst.op1}),
        .push_reg => return std.fmt.bufPrint(buf, "str x0, [sp,#-16]!", .{}),
        .pop_reg => return std.fmt.bufPrint(buf, "ldr x0, [sp],#16", .{}),
        .call_thunk => return std.fmt.bufPrint(buf, "bl thunk_{d}", .{@as(u32, @bitCast(inst.op1))}),
    }
}

pub fn initFromHostConfig() void {
    instruction_trace_enabled = instructionsEnabledFromEnvironment();
    if (rosette_debug_x86_disasm_enabled() == 0) return;

    const path_z = rosette_debug_log_path();
    const path = std.mem.span(path_z);
    if (path.len == 0) return;

    trace_file = std.c.fopen(path_z, "w");
    if (trace_file == null) return;

    trace_enabled = true;
    if (trace_file) |file| {
        _ = std.c.fwrite("# Rosette x86/arm64 instruction trace\n", 1, "# Rosette x86/arm64 instruction trace\n".len, file);
    }
}

pub fn initMandatory(log_path_z: [*:0]const u8) void {
    instruction_trace_enabled = instructionsEnabledFromEnvironment();
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
        _ = std.c.fwrite("# Rosette mandatory x86/arm64 instruction trace\n", 1, "# Rosette mandatory x86/arm64 instruction trace\n".len, file);
    }
}

pub fn deinit() void {
    if (trace_file) |file| {
        _ = std.c.fclose(file);
    }
    trace_file = null;
    trace_enabled = false;
    instruction_trace_enabled = true;
}

pub fn isEnabled() bool {
    return trace_enabled;
}

pub fn logInstruction(eip: u32, inst: isa.InstructionDef, ex: *const Executor) void {
    if (!trace_enabled or !instruction_trace_enabled) return;

    var inst_buf: [128]u8 = undefined;
    const inst_text = formatInstruction(&inst_buf, inst) catch return;

    var x86_line_buf: [320]u8 = undefined;
    const x86_line = std.fmt.bufPrint(&x86_line_buf, "[x86][instruction] eip=0x{X:0>8} {s} ; eax=0x{X:0>8} ebx=0x{X:0>8} ecx=0x{X:0>8} edx=0x{X:0>8} esp=0x{X:0>8} ebp=0x{X:0>8} esi=0x{X:0>8} edi=0x{X:0>8} eflags=0x{X:0>8}\n", .{
        eip,
        inst_text,
        ex.regs.eax,
        ex.regs.ebx,
        ex.regs.ecx,
        ex.regs.edx,
        ex.regs.esp,
        ex.regs.ebp,
        ex.regs.esi,
        ex.regs.edi,
        ex.regs.flags.raw(),
    }) catch return;

    var arm64_line_buf: [384]u8 = undefined;
    var arm64_inst_buf: [160]u8 = undefined;
    const arm64_inst = formatArm64Shadow(&arm64_inst_buf, inst) catch "shadow-unavailable";
    const arm64_line = std.fmt.bufPrint(&arm64_line_buf, "[ARM64][shadow] pc=0x{X:0>8} {s} ; x0=0x{X:0>8} x1=0x{X:0>8} x2=0x{X:0>8} x3=0x{X:0>8} sp=0x{X:0>8} x29=0x{X:0>8} x20=0x{X:0>8} x21=0x{X:0>8} nzcv=0x{X:0>8}\n", .{
        ex.regs.eip,
        arm64_inst,
        ex.regs.eax,
        ex.regs.ecx,
        ex.regs.edx,
        ex.regs.ebx,
        ex.regs.esp,
        ex.regs.ebp,
        ex.regs.esi,
        ex.regs.edi,
        ex.regs.flags.raw(),
    }) catch return;

    if (trace_file) |file| {
        _ = std.c.fwrite(x86_line.ptr, 1, x86_line.len, file);
        _ = std.c.fwrite(arm64_line.ptr, 1, arm64_line.len, file);
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
