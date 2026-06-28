const std = @import("std");

pub const TerminationReason = enum(u8) {
    unknown = 0,
    exit_syscall = 1,
    ret_stack_empty = 2,
    hlt = 3,
    invalid_instruction = 4,
    unimplemented_instruction = 5,
    max_steps_reached = 6,
    divide_by_zero = 7,
    decode_failed = 8,
    unresolved_import_result = 9,
    invalid_control_flow_target = 10,
    cxx_exception = 11,
};

pub const TerminalRegs = struct {
    rax: u64 = 0,
    rbx: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
    rsi: u64 = 0,
    rdi: u64 = 0,
    rbp: u64 = 0,
    rsp: u64 = 0,
    r8: u64 = 0,
    r9: u64 = 0,
    r10: u64 = 0,
    r11: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,
};

pub const TraceEntry = struct {
    rip: u64 = 0,
    op: []const u8 = "",
    len: u64 = 0,
    rsp: u64 = 0,
    rax: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
};

pub const SymbolizedAddress = struct {
    address: u64 = 0,
    symbol: []const u8 = "",
    symbol_offset: u64 = 0,
};

pub const DependencyCall = struct {
    symbol: []const u8 = "",
    image: []const u8 = "",
    stub_address: u64 = 0,
    return_address: u64 = 0,
    caller_symbol: []const u8 = "",
    caller_offset: u64 = 0,
    synthetic_result: u64 = 0,
};

pub const ExitReport = struct {
    exit_code: u64,
    reason: TerminationReason,
    faulted: bool,
    rip: u64,
    regs: TerminalRegs,
    last_instructions: []const TraceEntry = &.{},
    terminal_symbol: ?SymbolizedAddress = null,
    dependency_calls: []const DependencyCall = &.{},
    execution_authoritative: bool = true,
    detail: []const u8 = "",
};

pub fn logExitReport(report: ExitReport) void {
    std.debug.print("\n  \x1b[31m======= EXIT DIAGNOSTICS =======\x1b[0m\n", .{});
    std.debug.print("  exit_code:    {d}\n", .{report.exit_code});
    std.debug.print("  reason:       {s}\n", .{reasonLabel(report.reason)});
    std.debug.print("  faulted:      {}\n", .{report.faulted});
    std.debug.print("  rip:          0x{x}\n", .{report.rip});
    if (report.terminal_symbol) |symbol| {
        std.debug.print("  location:     {s}+0x{x} (0x{x})\n", .{ symbol.symbol, symbol.symbol_offset, symbol.address });
    }
    std.debug.print("  authoritative:{}\n", .{report.execution_authoritative});

    const r = report.regs;
    std.debug.print("  \x1b[33mregisters:\x1b[0m\n", .{});
    std.debug.print("    rax=0x{x}  rbx=0x{x}  rcx=0x{x}  rdx=0x{x}\n", .{ r.rax, r.rbx, r.rcx, r.rdx });
    std.debug.print("    rsi=0x{x}  rdi=0x{x}  rbp=0x{x}  rsp=0x{x}\n", .{ r.rsi, r.rdi, r.rbp, r.rsp });
    std.debug.print("    r8=0x{x}   r9=0x{x}   r10=0x{x}  r11=0x{x}\n", .{ r.r8, r.r9, r.r10, r.r11 });
    std.debug.print("    r12=0x{x}  r13=0x{x}  r14=0x{x}  r15=0x{x}\n", .{ r.r12, r.r13, r.r14, r.r15 });

    if (report.detail.len > 0) {
        std.debug.print("  detail:       {s}\n", .{report.detail});
    }

    if (report.dependency_calls.len > 0) {
        std.debug.print("  \x1b[33munresolved dependency calls ({d}):\x1b[0m\n", .{report.dependency_calls.len});
        for (report.dependency_calls, 0..) |call, i| {
            if (call.caller_symbol.len != 0) {
                std.debug.print(
                    "    [{d:>3}] {s} from {s}; caller={s}+0x{x} return=0x{x} stub=0x{x} synthesized_rax=0x{x}\n",
                    .{ i, call.symbol, call.image, call.caller_symbol, call.caller_offset, call.return_address, call.stub_address, call.synthetic_result },
                );
            } else {
                std.debug.print(
                    "    [{d:>3}] {s} from {s}; caller=0x{x} stub=0x{x} synthesized_rax=0x{x}\n",
                    .{ i, call.symbol, call.image, call.return_address, call.stub_address, call.synthetic_result },
                );
            }
        }
    }

    const trace = report.last_instructions;
    if (trace.len > 0) {
        std.debug.print("  \x1b[33mlast {d} instructions (oldest first):\x1b[0m\n", .{trace.len});
        for (trace, 0..) |entry, i| {
            std.debug.print("    [{d:>3}] rip=0x{x:<16} op={s:<20} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}\n", .{
                i,
                entry.rip,
                entry.op,
                entry.rsp,
                entry.rax,
                entry.rcx,
                entry.rdx,
            });
        }
    }
    std.debug.print("  \x1b[31m==================================\x1b[0m\n", .{});
}

pub fn reasonLabel(reason: TerminationReason) []const u8 {
    return switch (reason) {
        .unknown => "unknown",
        .exit_syscall => "guest called exit()",
        .ret_stack_empty => "ret popped zero (stack underflow)",
        .hlt => "HLT instruction executed",
        .invalid_instruction => "decoder returned invalid instruction",
        .unimplemented_instruction => "opcode not implemented",
        .max_steps_reached => "step budget exhausted",
        .divide_by_zero => "divide-by-zero",
        .decode_failed => "decoder returned null",
        .unresolved_import_result => "guest result depends on unresolved Mach-O imports",
        .invalid_control_flow_target => "control flow entered non-executable memory",
        .cxx_exception => "guest raised a C++ exception without an available unwinder",
    };
}

pub fn reasonFromValue(val: u8) TerminationReason {
    return @enumFromInt(val);
}
