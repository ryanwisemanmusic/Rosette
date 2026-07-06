const runtime_abi = @import("runtime_abi_handshake");
const bridge = @import("bridge_exceptions");

var sequence: u64 = 0;

// Catch all the various issues by monitoring if we run into terminal ASM errors.
pub fn logSignalMapping(scope: []const u8, signal_number: u32, mapped_code: u32, address: u64, instruction: u64, flags: u64) void {
    sequence += 1;
    const signal_kind: runtime_abi.arm64.HostSignalKind = switch (signal_number) {
        1 => .sighup,
        2 => .sigint,
        3 => .sigquit,
        4 => .sigill,
        5 => .sigtrap,
        6 => .sigabort,
        7 => .sigemt,
        8 => .sigfpe,
        9 => .sigkill,
        10 => .sigbus,
        11 => .sigsegv,
        12 => .sigsys,
        13 => .sigpipe,
        14 => .sigalrm,
        15 => .sigterm,
        16 => .sigurg,
        17 => .sigstop,
        18 => .sigtstp,
        19 => .sigcont,
        20 => .sigchld,
        21 => .sigttin,
        22 => .sigttou,
        23 => .sigio,
        24 => .sigxcpu,
        25 => .sigxfsz,
        26 => .sigvtalrm,
        27 => .sigprof,
        28 => .sigwinch,
        29 => .siginfo,
        30 => .sigusr1,
        31 => .sigusr2,
        else => .none,
    };
    // We then want to also get the Assembly data related to this error.
    // Because if something like a sigabort happens, we need as much data behind the point of failure
    runtime_abi.arm64.validateSignalDelivery(scope, signal_kind, mapped_code);
    runtime_abi.common.writeLine(
        "[exception-trace][arm64] scope={s} seq={d} kind=macos_signal_exception signal={d} mapped=0x{x} addr=0x{x} instr=0x{x} flags=0x{x}\n",
        .{ scope, sequence, signal_number, mapped_code, address, instruction, flags },
    );
    var target = bridge.makeExceptionEvent(.arm64, sequence, scope, .macos_signal_exception);
    target.vector = @intCast(signal_number);
    target.code = mapped_code;
    target.address = address;
    target.instruction = instruction;
    target.flags = flags;
    bridge.reportExceptionEvent(target, noopContext); // Finally, report we've hit an exception
}

fn noopContext(_: []const u8) void {}
