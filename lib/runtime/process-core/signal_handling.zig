//! Guest signal handling (sigaction/signal delivery/return).
//! Extracted from MachOState (process.zig) to reduce file size.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const exit_diagnostics = @import("exit_diagnostics");
const utils = @import("../../Mach-O/utils.zig");

const guestSignalIndex = utils.guestSignalIndex;
const signalFailureResult = utils.signalFailureResult;
const readDarwinSigaction = utils.readDarwinSigaction;
const writeDarwinSigaction = utils.writeDarwinSigaction;
const writeDarwinSiginfo = utils.writeDarwinSiginfo;
const writeDarwinMcontext = utils.writeDarwinMcontext;
const writeDarwinUcontext = utils.writeDarwinUcontext;
const readDarwinMcontext = utils.readDarwinMcontext;
const resolveGuestSignalReturn = utils.resolveGuestSignalReturn;

const constants = @import("../../Mach-O/constants.zig");
const DARWIN_SIGACTION_SIZE = constants.DARWIN_SIGACTION_SIZE;
const DARWIN_SIGINFO_SIZE = constants.DARWIN_SIGINFO_SIZE;
const DARWIN_MCONTEXT_SIZE = constants.DARWIN_MCONTEXT_SIZE;
const DARWIN_UCONTEXT_SIZE = constants.DARWIN_UCONTEXT_SIZE;
const GUEST_SIGNAL_RETURN_SENTINEL = constants.GUEST_SIGNAL_RETURN_SENTINEL;
const GUEST_SIGILL = constants.GUEST_SIGILL;
const GUEST_SIGSEGV = constants.GUEST_SIGSEGV;
const SA_NODEFER = constants.SA_NODEFER;
const SA_RESETHAND = constants.SA_RESETHAND;
const SA_SIGINFO = constants.SA_SIGINFO;

const GuestSignalFrame = @import("../../Mach-O/types.zig").GuestSignalFrame;
const GuestAccess = @import("../../Mach-O/types.zig").GuestAccess;

pub fn handleSigaction(self: anytype) u64 {
    const signal_index = guestSignalIndex(self.regs.rdi) orelse return signalFailureResult();
    const previous = self.signal_actions[signal_index];

    if (self.regs.rdx != 0) {
        const output = self.guestMemory(self.regs.rdx, DARWIN_SIGACTION_SIZE) orelse return signalFailureResult();
        writeDarwinSigaction(output, previous);
    }
    if (self.regs.rsi != 0) {
        const input = self.guestMemoryConst(self.regs.rsi, DARWIN_SIGACTION_SIZE) orelse return signalFailureResult();
        self.signal_actions[signal_index] = readDarwinSigaction(input) orelse return signalFailureResult();
    }
    if (self.verbose_trace) {
        const action = self.signal_actions[signal_index];
        machoCapturePrint(
            "    [signal] sigaction signal={d} handler=0x{x} flags=0x{x} mask=0x{x}\n",
            .{ self.regs.rdi, action.handler, action.flags, action.mask },
        );
    }
    return 0;
}

pub fn deliverGuestSignal(
    self: anytype,
    signal: u8,
    fault_rip: u64,
    instruction_len: u8,
    fault_address: u64,
    fault_access: ?GuestAccess,
) bool {
    const signal_index = guestSignalIndex(signal) orelse return false;
    const action = self.signal_actions[signal_index];
    if (action.handler == 0) return false;
    if (action.handler == 1) {
        self.regs.rip +%= instruction_len;
        machoCapturePrint("macho-processor: guest ignored signal {d} at rip=0x{x}\n", .{ signal, fault_rip });
        return true;
    }
    if (action.flags & SA_NODEFER == 0 and self.signalIsActive(signal)) {
        if (signal != GUEST_SIGILL) return false;
        self.regs.rip = fault_rip +% instruction_len;
        machoCapturePrint(
            "macho-processor: deferred recursive guest signal {d} at rip=0x{x}; outer handler remains active\n",
            .{ signal, fault_rip },
        );
        if (self.last_guest_assertion_class == .breakpoint_untracked_thread) {
            machoCapturePrint(
                "macho-processor: recursive signal provenance: Processor::OnThreadBreakpointHit asserted because the active modeled thread was absent from Xenia's debugger registry; this nested UD2 is handler fallout, not a second independent backend failure\n",
                .{},
            );
        }
        return true;
    }
    if (!self.isExecutableAddress(action.handler) or self.signal_frame_count >= self.signal_frames.len) return false;

    const frame = &self.signal_frames[self.signal_frame_count];
    if (!self.ensureGuestSignalFrameStorage(frame)) return false;
    const siginfo_bytes = self.guestMemory(frame.siginfo, DARWIN_SIGINFO_SIZE) orelse return false;
    const mcontext_bytes = self.guestMemory(frame.mcontext, DARWIN_MCONTEXT_SIZE) orelse return false;
    const ucontext_bytes = self.guestMemory(frame.ucontext, DARWIN_UCONTEXT_SIZE) orelse return false;

    const protection_fault = signal == GUEST_SIGSEGV;
    const signal_code: i32 = if (protection_fault) 2 else 1;
    const trap_number: u16 = if (protection_fault) 14 else 6;
    const error_code: u32 = if (protection_fault)
        1 | (if (fault_access == .write) @as(u32, 2) else 0)
    else
        0;
    writeDarwinSiginfo(siginfo_bytes, signal, signal_code, fault_address);
    writeDarwinMcontext(mcontext_bytes, self.regs, trap_number, error_code, fault_address);
    writeDarwinUcontext(ucontext_bytes, frame.mcontext);

    if (action.flags & SA_RESETHAND != 0) self.signal_actions[signal_index] = .{};
    frame.signal = signal;
    frame.instruction_len = instruction_len;
    frame.fault_rip = fault_rip;
    frame.assertion_class = self.last_guest_assertion_class;
    self.signal_frame_count += 1;
    self.push(GUEST_SIGNAL_RETURN_SENTINEL);
    if (self.terminated) {
        self.signal_frame_count -= 1;
        return false;
    }
    self.regs.rdi = signal;
    if (action.flags & SA_SIGINFO != 0) {
        self.regs.rsi = frame.siginfo;
        self.regs.rdx = frame.ucontext;
    } else {
        self.regs.rsi = 0;
        self.regs.rdx = 0;
    }
    self.regs.rip = action.handler;
    self.guest_signal_deliveries +|= 1;
    const backend_correlated = self.backend_diagnostics.signalCorrelates(self.executed_steps, fault_rip);
    if (backend_correlated) self.backend_diagnostics.noteSignalDelivery();
    machoCapturePrint(
        "macho-processor: delivered guest signal {d} to 0x{x}; fault_rip=0x{x} fault_address=0x{x} access={s} siginfo=0x{x} ucontext=0x{x}\n",
        .{ signal, action.handler, fault_rip, fault_address, if (fault_access) |access| @tagName(access) else "instruction", frame.siginfo, frame.ucontext },
    );
    if (backend_correlated) {
        machoCapturePrint(
            "macho-processor: guest signal correlation: signal={d} fault_rip=0x{x} is linked to backend assertion kind={s} assertion_return=0x{x} step_delta={d}\n",
            .{ signal, fault_rip, @tagName(self.backend_diagnostics.last_backend_assertion_binding), self.backend_diagnostics.last_backend_assertion_rip, self.executed_steps -| self.backend_diagnostics.last_backend_assertion_step },
        );
    }
    const assertion_distance = if (fault_rip >= self.last_guest_assertion_return)
        fault_rip - self.last_guest_assertion_return
    else
        self.last_guest_assertion_return - fault_rip;
    if (self.last_guest_assertion_class != .none and
        self.executed_steps -| self.last_guest_assertion_step <= 4096 and
        assertion_distance <= 16)
    {
        machoCapturePrint(
            "macho-processor: guest signal assertion provenance: signal={d} fault_rip=0x{x} assertion={s} assertion_return=0x{x} address_delta={d} step_delta={d}\n",
            .{ signal, fault_rip, @tagName(self.last_guest_assertion_class), self.last_guest_assertion_return, assertion_distance, self.executed_steps -| self.last_guest_assertion_step },
        );
    }
    return true;
}

pub fn signalIsActive(self: anytype, signal: u8) bool {
    for (self.signal_frames[0..self.signal_frame_count]) |frame| {
        if (frame.signal == signal) return true;
    }
    return false;
}

pub fn ensureGuestSignalFrameStorage(self: anytype, frame: *GuestSignalFrame) bool {
    if (frame.siginfo == 0) frame.siginfo = self.guestAlloc(DARWIN_SIGINFO_SIZE, 16) orelse return false;
    if (frame.mcontext == 0) frame.mcontext = self.guestAlloc(DARWIN_MCONTEXT_SIZE, 16) orelse return false;
    if (frame.ucontext == 0) frame.ucontext = self.guestAlloc(DARWIN_UCONTEXT_SIZE, 16) orelse return false;
    return true;
}

pub fn finishGuestSignalReturn(self: anytype) bool {
    if (self.signal_frame_count == 0) {
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        return false;
    }
    self.signal_frame_count -= 1;
    const frame = self.signal_frames[self.signal_frame_count];
    const bytes = self.guestMemoryConst(frame.mcontext, DARWIN_MCONTEXT_SIZE) orelse {
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        return false;
    };
    if (!readDarwinMcontext(bytes, &self.regs)) {
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        return false;
    }
    const fault_bytes = self.guestMemoryConst(frame.fault_rip, frame.instruction_len) orelse &.{};
    const resume_rip = resolveGuestSignalReturn(frame, self.regs.rip, fault_bytes) orelse {
        machoCapturePrint(
            "macho-processor: guest signal {d} handler returned without resolving fault at rip=0x{x}\n",
            .{ frame.signal, frame.fault_rip },
        );
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 128 + frame.signal;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unhandled_guest_signal);
        return false;
    };
    if (resume_rip != self.regs.rip) {
        machoCapturePrint(
            "macho-processor: guest signal {d} handler returned with unchanged UD2 at rip=0x{x}; resuming at 0x{x}\n",
            .{ frame.signal, frame.fault_rip, resume_rip },
        );
        self.regs.rip = resume_rip;
    }
    if (self.backend_diagnostics.signalReturnCorrelates(frame.fault_rip)) {
        self.backend_diagnostics.noteSignalReturn();
        machoCapturePrint(
            "macho-processor: guest signal correlation resolved: signal={d} backend_assertion={s} fault_rip=0x{x} resume_rip=0x{x}; execution continued\n",
            .{ frame.signal, @tagName(self.backend_diagnostics.last_backend_assertion_binding), frame.fault_rip, self.regs.rip },
        );
    }
    if (self.verbose_trace) {
        machoCapturePrint(
            "macho-processor: guest signal {d} returned; fault_rip=0x{x} resume_rip=0x{x}\n",
            .{ frame.signal, frame.fault_rip, self.regs.rip },
        );
    }
    return true;
}
