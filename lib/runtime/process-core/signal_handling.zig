//! Guest signal handling (sigaction/signal delivery/return).
//! Extracted from MachOState (process.zig) to reduce file size.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const exit_diagnostics = @import("exit_diagnostics");
const utils = @import("macho_core").utils;

const guestSignalIndex = utils.guestSignalIndex;
const signalFailureResult = utils.signalFailureResult;
const readDarwinSigaction = utils.readDarwinSigaction;
const writeDarwinSigaction = utils.writeDarwinSigaction;
const writeDarwinSiginfo = utils.writeDarwinSiginfo;
const writeDarwinMcontext = utils.writeDarwinMcontext;
const writeDarwinUcontext = utils.writeDarwinUcontext;
const readDarwinMcontext = utils.readDarwinMcontext;
const resolveGuestSignalReturn = utils.resolveGuestSignalReturn;

const constants = @import("macho_core").constants;
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

const GuestSignalFrame = @import("macho_core").types.GuestSignalFrame;
const GuestAccess = @import("macho_core").types.GuestAccess;
const memory_access = @import("memory_access.zig");
const recovery_ledger = @import("ownership").ledger;
const GuestAssertionContext = @import("macho_core").types.GuestAssertionContext;

fn assertionContextForFault(self: anytype, fault_rip: u64) GuestAssertionContext {
    if (self.last_guest_assertion.relevant(self.active_guest_thread, self.executed_steps, fault_rip)) {
        return self.last_guest_assertion;
    }
    return .{};
}

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
    if (self.regs.rdi == GUEST_SIGSEGV) {
        const action = self.signal_actions[signal_index];
        // Sparse write-watch pages are expected to fault and be repaired by
        // the guest's SIGSEGV handler. Keep the memory classifier synchronized
        // with the real process-wide disposition so it doesn't diagnose that
        // protocol as an unhandled permission violation.
        self.sparse_memory.guest_fault_handler_installed = action.handler > 1;
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
    fault_width: u8,
    fault_instruction: []const u8,
) bool {
    const signal_index = guestSignalIndex(signal) orelse return false;
    const action = self.signal_actions[signal_index];
    if (action.handler == 0) return false;
    if (action.handler == 1) {
        self.regs.rip +%= instruction_len;
        machoCapturePrint("macho-processor: guest ignored signal {d} at rip=0x{x}\n", .{ signal, fault_rip });
        return true;
    }
    const assertion_context = assertionContextForFault(self, fault_rip);
    if (action.flags & SA_NODEFER == 0 and self.signalIsActive(signal)) {
        if (signal != GUEST_SIGILL) return false;
        self.regs.rip = fault_rip +% instruction_len;
        machoCapturePrint(
            "macho-processor: deferred recursive guest signal {d} at rip=0x{x}; outer handler remains active\n",
            .{ signal, fault_rip },
        );
        const outer_assertion = if (self.signal_frame_count != 0)
            self.signal_frames[self.signal_frame_count - 1].assertion_context
        else
            assertion_context;
        if (outer_assertion.class == .breakpoint_untracked_thread) {
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

    if (action.flags & SA_RESETHAND != 0) {
        self.signal_actions[signal_index] = .{};
        if (signal == GUEST_SIGSEGV) self.sparse_memory.guest_fault_handler_installed = false;
    }
    frame.signal = signal;
    frame.instruction_len = instruction_len;
    frame.owner_thread = self.active_guest_thread;
    frame.fault_rip = fault_rip;
    frame.fault_address = fault_address;
    frame.fault_access = fault_access;
    frame.fault_width = fault_width;
    frame.fault_instruction = fault_instruction;
    frame.assertion_context = assertion_context;
    frame.saved_assertion_context = self.last_guest_assertion;
    // Keep a scalar snapshot in the frame as well as the Darwin mcontext.
    // The handler may edit mcontext before returning; if it fails to resolve
    // the fault, diagnostics must still describe the interrupted instruction's
    // operands rather than the handler's working registers.
    frame.saved_regs = self.regs;
    frame.saved_xmm = self.xmm;
    frame.saved_ymm_hi = self.ymm_hi;
    frame.saved_k = self.k;
    frame.saved_x87 = self.x87;
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
        "macho-processor: delivered guest signal {d} to 0x{x}; fault_rip=0x{x} fault_address=0x{x} access={s} assertion={s} assertion_thread=0x{x} siginfo=0x{x} ucontext=0x{x}\n",
        .{ signal, action.handler, fault_rip, fault_address, if (fault_access) |access| @tagName(access) else "instruction", @tagName(assertion_context.class), assertion_context.thread, frame.siginfo, frame.ucontext },
    );
    if (backend_correlated) {
        machoCapturePrint(
            "macho-processor: guest signal correlation: signal={d} fault_rip=0x{x} is linked to backend assertion kind={s} assertion_return=0x{x} step_delta={d}\n",
            .{ signal, fault_rip, @tagName(self.backend_diagnostics.last_backend_assertion_binding), self.backend_diagnostics.last_backend_assertion_rip, self.executed_steps -| self.backend_diagnostics.last_backend_assertion_step },
        );
    }
    if (assertion_context.valid) {
        const assertion_distance = if (fault_rip >= assertion_context.return_address)
            fault_rip - assertion_context.return_address
        else
            assertion_context.return_address - fault_rip;
        machoCapturePrint(
            "macho-processor: guest signal assertion provenance: signal={d} fault_rip=0x{x} assertion={s} assertion_thread=0x{x} assertion_return=0x{x} address_delta={d} step_delta={d}\n",
            .{ signal, fault_rip, @tagName(assertion_context.class), assertion_context.thread, assertion_context.return_address, assertion_distance, self.executed_steps -| assertion_context.step },
        );
    }
    return true;
}

/// Deliver a signal raised by the guest's `raise()` import rather than by an
/// instruction fault. The normal signal path saves the import thunk's current
/// context; patch the saved RIP/RSP to the import's return address so a handler
/// returning through the guest signal trampoline resumes *after* `raise()` and
/// does not re-enter the thunk or leave its return address on the stack.
pub fn deliverRaisedGuestSignal(self: anytype, signal: u8, return_address: u64) bool {
    const frame_count_before = self.signal_frame_count;
    const import_rsp = self.regs.rsp;
    if (!deliverGuestSignal(
        self,
        signal,
        self.regs.rip,
        0,
        self.regs.rip,
        null,
        0,
        "raise",
    )) return false;

    // SIG_IGN was handled without creating a frame; raise() still succeeds.
    if (self.signal_frame_count == frame_count_before) return true;
    const frame = &self.signal_frames[self.signal_frame_count - 1];
    const bytes = self.guestMemory(frame.mcontext, DARWIN_MCONTEXT_SIZE) orelse return false;
    var resume_regs = self.regs;
    if (!readDarwinMcontext(bytes, &resume_regs)) return false;
    resume_regs.rip = return_address;
    resume_regs.rsp = import_rsp +% @sizeOf(u64);
    writeDarwinMcontext(bytes, resume_regs, 6, 0, 0);
    return true;
}

pub fn signalIsActive(self: anytype, signal: u8) bool {
    for (self.signal_frames[0..self.signal_frame_count]) |frame| {
        if (frame.owner_thread == self.active_guest_thread and frame.signal == signal) return true;
    }
    return false;
}

pub fn ensureGuestSignalFrameStorage(self: anytype, frame: *GuestSignalFrame) bool {
    if (frame.siginfo == 0) frame.siginfo = self.guestAlloc(DARWIN_SIGINFO_SIZE, 16) orelse return false;
    if (frame.mcontext == 0) frame.mcontext = self.guestAlloc(DARWIN_MCONTEXT_SIZE, 16) orelse return false;
    if (frame.ucontext == 0) frame.ucontext = self.guestAlloc(DARWIN_UCONTEXT_SIZE, 16) orelse return false;
    return true;
}

/// Whether the access that raised this SIGSEGV would now be permitted.
///
/// This is the only thing that authorises retrying the faulting instruction:
/// the guest's handler must have actually changed the protection. Asking the
/// memory system directly — rather than trusting that a handler ran — means an
/// unresolved fault still terminates, and means the answer stays correct for
/// any guest that uses the write-watch pattern rather than for one we
/// recognised.
fn protectionFaultResolved(self: anytype, frame: GuestSignalFrame) bool {
    const access = frame.fault_access orelse return false;
    if (frame.fault_width == 0) return false;
    const width: u64 = frame.fault_width;
    if (self.sparse_memory.bytesConst(frame.fault_address, width) != null) {
        // Readable now; a write additionally needs the writable view.
        if (access != .write) return true;
        return self.sparse_memory.bytes(frame.fault_address, width, true) != null;
    }
    if (access == .execute) return self.sparse_memory.isExecutable(frame.fault_address, width);
    return memory_access.translateGuest(self, frame.fault_address, width, access) != null;
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
    if (frame.owner_thread != self.active_guest_thread) {
        machoCapturePrint(
            "macho-processor: guest signal return ownership violation: signal={d} frame_thread=0x{x} active_thread=0x{x}; refusing to restore another guest thread's machine context\n",
            .{ frame.signal, frame.owner_thread, self.active_guest_thread },
        );
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        return false;
    }
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
    // A handler is allowed to use the full machine state. Restore the exact
    // pre-signal vector, mask, x87, and assertion context rather than letting
    // handler work leak into the interrupted guest thread.
    self.xmm = frame.saved_xmm;
    self.ymm_hi = frame.saved_ymm_hi;
    self.k = frame.saved_k;
    self.x87 = frame.saved_x87;
    self.last_guest_assertion = frame.saved_assertion_context;
    const fault_bytes = self.guestMemoryConst(frame.fault_rip, frame.instruction_len) orelse &.{};
    // A SIGSEGV handler that returns with RIP unchanged is not necessarily
    // stuck: for a *protection* fault that is the whole protocol. The
    // write-watch pattern — protect a page read-only, catch the write,
    // un-protect it, return — deliberately leaves RIP on the faulting
    // instruction and expects it to be retried. Treating "RIP unchanged" as
    // failure terminated the run at precisely the moment the guest was handling
    // the fault correctly.
    //
    // The predicate is behavioural, not a guess about who the guest is: retry
    // only when the access that faulted would *now* succeed. If the handler
    // left the protection as it was, nothing changed and the original
    // termination stands, so this cannot spin on an unhandled fault.
    if (frame.signal == GUEST_SIGSEGV and self.regs.rip == frame.fault_rip) {
        if (protectionFaultResolved(self, frame)) {
            self.guest_protection_retries +|= 1;
            if (recovery_ledger.throttled(self.guest_protection_retries)) {
                machoCapturePrint(
                    "macho-processor: guest SIGSEGV handler resolved a protection fault #{d}: rip=0x{x} address=0x{x} bytes={d} access={s}; the handler changed the page's protection and returned without moving RIP, so the faulting instruction is retried — this is the write-watch protocol, not a stalled handler\n",
                    .{ self.guest_protection_retries, frame.fault_rip, frame.fault_address, frame.fault_width, if (frame.fault_access) |access| @tagName(access) else "unknown" },
                );
            }
            self.terminal_memory_failure = null;
            return true;
        }
    }
    const resume_rip = resolveGuestSignalReturn(frame, self.regs.rip, fault_bytes) orelse {
        if (frame.signal == GUEST_SIGSEGV) {
            machoCapturePrint(
                "macho-processor: guest SIGSEGV handler returned without resolving mapped protection fault: rip=0x{x} address=0x{x} bytes={d} access={s} instruction={s}\n",
                .{ frame.fault_rip, frame.fault_address, frame.fault_width, if (frame.fault_access) |access| @tagName(access) else "unknown", frame.fault_instruction },
            );
            self.terminal_memory_failure = .{
                .instruction_address = frame.fault_rip,
                .instruction = frame.fault_instruction,
                .address = frame.fault_address,
                .bytes = frame.fault_width,
                .access = if (frame.fault_access) |access| @tagName(access) else "unknown",
                .fault = "permission_denied",
                .mapped = true,
                .fault_regs = .{
                    .rax = frame.saved_regs.rax,
                    .rbx = frame.saved_regs.rbx,
                    .rcx = frame.saved_regs.rcx,
                    .rdx = frame.saved_regs.rdx,
                    .rsi = frame.saved_regs.rsi,
                    .rdi = frame.saved_regs.rdi,
                    .rbp = frame.saved_regs.rbp,
                    .rsp = frame.saved_regs.rsp,
                    .r8 = frame.saved_regs.r8,
                    .r9 = frame.saved_regs.r9,
                    .r10 = frame.saved_regs.r10,
                    .r11 = frame.saved_regs.r11,
                    .r12 = frame.saved_regs.r12,
                    .r13 = frame.saved_regs.r13,
                    .r14 = frame.saved_regs.r14,
                    .r15 = frame.saved_regs.r15,
                },
                .fault_regs_valid = true,
            };
        } else {
            machoCapturePrint(
                "macho-processor: guest signal {d} handler returned without resolving fault at rip=0x{x}\n",
                .{ frame.signal, frame.fault_rip },
            );
        }
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 128 + frame.signal;
        self.termination_reason = @intFromEnum(if (frame.signal == GUEST_SIGSEGV)
            exit_diagnostics.TerminationReason.memory_access_violation
        else
            exit_diagnostics.TerminationReason.unhandled_guest_signal);
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
