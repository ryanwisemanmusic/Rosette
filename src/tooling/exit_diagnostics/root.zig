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

pub const StopOwner = enum {
    guest_application,
    rosette_runtime,
    indeterminate,
};

pub const ResultAuthority = enum {
    authoritative,
    diagnostic_only,
};

pub const Attribution = struct {
    owner: StopOwner,
    authority: ResultAuthority,
    evidence: []const u8,
    next_action: []const u8,
};

pub const AttributionInput = struct {
    reason: TerminationReason,
    faulted: bool,
    unresolved_import_calls: u64 = 0,
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

pub const CxxExceptionReport = struct {
    object_address: u64,
    allocation_size: u64 = 0,
    allocation_matched: bool = false,
    allocation_site: ?SymbolizedAddress = null,
    type_info_address: u64,
    type_name: []const u8 = "",
    type_symbol: ?SymbolizedAddress = null,
    destructor_address: u64 = 0,
    destructor_symbol: ?SymbolizedAddress = null,
    throw_site: ?SymbolizedAddress = null,
    message: []const u8 = "",
    unwinder_available: bool = false,
    unwind_frames: usize = 0,
    handler_found: bool = false,
    handler_address: u64 = 0,
    phase_two_supported: bool = false,
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
    unresolved_import_calls: u64 = 0,
    attribution: ?Attribution = null,
    cxx_exception: ?CxxExceptionReport = null,
    execution_authoritative: bool = true,
    detail: []const u8 = "",
};

pub fn logExitReport(report: ExitReport) void {
    const attribution = report.attribution orelse attribute(.{
        .reason = report.reason,
        .faulted = report.faulted,
        .unresolved_import_calls = report.unresolved_import_calls,
    });
    std.debug.print("\n  \x1b[31m======= EXIT DIAGNOSTICS =======\x1b[0m\n", .{});
    std.debug.print("  exit_code:    {d}\n", .{report.exit_code});
    std.debug.print("  reason:       {s}\n", .{reasonLabel(report.reason)});
    std.debug.print("  faulted:      {}\n", .{report.faulted});
    std.debug.print("  rip:          0x{x}\n", .{report.rip});
    if (report.terminal_symbol) |symbol| {
        std.debug.print("  location:     {s}+0x{x} (0x{x})\n", .{ symbol.symbol, symbol.symbol_offset, symbol.address });
    }
    std.debug.print("  authoritative:{}\n", .{attribution.authority == .authoritative});
    std.debug.print("  stop owner:   {s}\n", .{ownerLabel(attribution.owner)});
    std.debug.print("  verdict:      {s}\n", .{authorityLabel(attribution.authority)});
    std.debug.print("  evidence:     {s}\n", .{attribution.evidence});
    std.debug.print("  next check:   {s}\n", .{attribution.next_action});

    const r = report.regs;
    std.debug.print("  \x1b[33mregisters:\x1b[0m\n", .{});
    std.debug.print("    rax=0x{x}  rbx=0x{x}  rcx=0x{x}  rdx=0x{x}\n", .{ r.rax, r.rbx, r.rcx, r.rdx });
    std.debug.print("    rsi=0x{x}  rdi=0x{x}  rbp=0x{x}  rsp=0x{x}\n", .{ r.rsi, r.rdi, r.rbp, r.rsp });
    std.debug.print("    r8=0x{x}   r9=0x{x}   r10=0x{x}  r11=0x{x}\n", .{ r.r8, r.r9, r.r10, r.r11 });
    std.debug.print("    r12=0x{x}  r13=0x{x}  r14=0x{x}  r15=0x{x}\n", .{ r.r12, r.r13, r.r14, r.r15 });

    if (report.detail.len > 0) {
        std.debug.print("  detail:       {s}\n", .{report.detail});
    }

    if (report.cxx_exception) |exception| {
        std.debug.print("  \x1b[33mC++ exception:\x1b[0m\n", .{});
        std.debug.print("    object=0x{x} allocation_matched={} allocation_size={d}\n", .{
            exception.object_address,
            exception.allocation_matched,
            exception.allocation_size,
        });
        if (exception.type_name.len != 0) {
            std.debug.print("    type={s} type_info=0x{x}\n", .{ exception.type_name, exception.type_info_address });
        } else {
            std.debug.print("    type_info=0x{x}\n", .{exception.type_info_address});
        }
        if (exception.type_symbol) |symbol| {
            std.debug.print("    type symbol={s}+0x{x}\n", .{ symbol.symbol, symbol.symbol_offset });
        }
        if (exception.destructor_symbol) |symbol| {
            std.debug.print("    destructor={s}+0x{x} (0x{x})\n", .{ symbol.symbol, symbol.symbol_offset, exception.destructor_address });
        } else if (exception.destructor_address != 0) {
            std.debug.print("    destructor=0x{x}\n", .{exception.destructor_address});
        }
        if (exception.throw_site) |symbol| {
            std.debug.print("    throw site={s}+0x{x} (0x{x})\n", .{ symbol.symbol, symbol.symbol_offset, symbol.address });
        }
        if (exception.allocation_site) |symbol| {
            std.debug.print("    allocation site={s}+0x{x} (0x{x})\n", .{ symbol.symbol, symbol.symbol_offset, symbol.address });
        }
        if (exception.message.len != 0) {
            std.debug.print("    message={s}\n", .{exception.message});
        }
        std.debug.print("    unwinder_available={}\n", .{exception.unwinder_available});
        std.debug.print(
            "    unwind_frames={d} handler_found={} handler=0x{x} phase_two_supported={}\n",
            .{ exception.unwind_frames, exception.handler_found, exception.handler_address, exception.phase_two_supported },
        );
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
        .cxx_exception => "guest raised a C++ exception requiring incomplete phase-two unwinding",
    };
}

pub fn attribute(input: AttributionInput) Attribution {
    if (input.unresolved_import_calls != 0) {
        return .{
            .owner = .rosette_runtime,
            .authority = .diagnostic_only,
            .evidence = "One or more guest dependency calls were not executed.",
            .next_action = "Resolve the recorded imports before interpreting the guest exit status.",
        };
    }

    const result: Attribution = switch (input.reason) {
        .exit_syscall => .{
            .owner = .guest_application,
            .authority = .authoritative,
            .evidence = "The guest explicitly called exit().",
            .next_action = "Inspect the guest caller and its application-level error path.",
        },
        .ret_stack_empty => .{
            .owner = .guest_application,
            .authority = .authoritative,
            .evidence = "The guest returned from its outermost frame.",
            .next_action = "Interpret the return register as the guest program result.",
        },
        .hlt => .{
            .owner = .guest_application,
            .authority = .authoritative,
            .evidence = "The guest executed HLT.",
            .next_action = "Inspect the guest control-flow path leading to HLT.",
        },
        .divide_by_zero => .{
            .owner = .guest_application,
            .authority = .diagnostic_only,
            .evidence = "Guest arithmetic raised a divide error.",
            .next_action = "Inspect the faulting guest instruction and exception policy.",
        },
        .cxx_exception => .{
            .owner = .rosette_runtime,
            .authority = .diagnostic_only,
            .evidence = "The guest called __cxa_throw; Rosette can inspect compact-unwind and LSDA metadata, but cannot safely install a landing-pad register context yet.",
            .next_action = "Use the phase-one handler report to implement verified phase-two register restoration before treating this result as a guest exit.",
        },
        .invalid_instruction, .unimplemented_instruction, .decode_failed => .{
            .owner = .rosette_runtime,
            .authority = .diagnostic_only,
            .evidence = "Rosette could not decode or execute a guest instruction.",
            .next_action = "Implement the recorded instruction and rerun from the same trace boundary.",
        },
        .max_steps_reached => .{
            .owner = .rosette_runtime,
            .authority = .diagnostic_only,
            .evidence = "Rosette exhausted its instruction budget before the guest terminated.",
            .next_action = "Check for a guest loop, then raise the step budget if progress is legitimate.",
        },
        .unresolved_import_result => .{
            .owner = .rosette_runtime,
            .authority = .diagnostic_only,
            .evidence = "Rosette synthesized a result for an unresolved guest dependency.",
            .next_action = "Resolve the dependency and discard the current guest exit status.",
        },
        .invalid_control_flow_target => .{
            .owner = .rosette_runtime,
            .authority = .diagnostic_only,
            .evidence = "Guest control flow reached an address Rosette could not execute.",
            .next_action = "Inspect the last branch, imported thunk, and mapped executable ranges.",
        },
        .unknown => .{
            .owner = .indeterminate,
            .authority = .diagnostic_only,
            .evidence = "No terminal event was classified.",
            .next_action = "Inspect the terminal registers and recent instruction trace.",
        },
    };

    if (input.faulted and result.authority == .authoritative) {
        return .{
            .owner = .indeterminate,
            .authority = .diagnostic_only,
            .evidence = "The terminal event looked guest-driven, but Rosette also marked the run faulted.",
            .next_action = "Resolve the Rosette fault before trusting the guest result.",
        };
    }
    return result;
}

pub fn ownerLabel(owner: StopOwner) []const u8 {
    return switch (owner) {
        .guest_application => "guest application",
        .rosette_runtime => "Rosette runtime",
        .indeterminate => "indeterminate",
    };
}

pub fn authorityLabel(authority: ResultAuthority) []const u8 {
    return switch (authority) {
        .authoritative => "authoritative guest result",
        .diagnostic_only => "diagnostic only",
    };
}

pub fn reasonFromValue(val: u8) TerminationReason {
    return @enumFromInt(val);
}

test "C++ exception stop is attributed to missing Rosette unwinding" {
    const result = attribute(.{ .reason = .cxx_exception, .faulted = false });
    try std.testing.expectEqual(StopOwner.rosette_runtime, result.owner);
    try std.testing.expectEqual(ResultAuthority.diagnostic_only, result.authority);
}

test "clean guest exit is authoritative" {
    const result = attribute(.{ .reason = .exit_syscall, .faulted = false });
    try std.testing.expectEqual(StopOwner.guest_application, result.owner);
    try std.testing.expectEqual(ResultAuthority.authoritative, result.authority);
}

test "unresolved dependency overrides an apparent guest exit" {
    const result = attribute(.{
        .reason = .exit_syscall,
        .faulted = false,
        .unresolved_import_calls = 1,
    });
    try std.testing.expectEqual(StopOwner.rosette_runtime, result.owner);
    try std.testing.expectEqual(ResultAuthority.diagnostic_only, result.authority);
}
