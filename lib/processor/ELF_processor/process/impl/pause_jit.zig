//! PAUSE remains an exact scheduling/forensics boundary, but a parallel
//! executor need not leave its translated trace for each idle hint.
const process = @import("../../process.zig");
const life = @import("lifecycle.zig");
const jit = @import("block_jit.zig");
const ElfState = process.ElfState;
const I = process.__ProcessInternals;

pub fn canCompile(self: *ElfState, d: I._block_jit.DecodedInsn, bytes: []const u8) bool {
    return self.parallel_guest_execution and self.windows_idle_yield.pause_translated_enabled and
        self.guest_clock.source == .host_monotonic and !self.block_jit_verify_memory and !self.diagnose_abi and !self.windowsMemoryTraceLive() and !jit.blockJitTracingActive(self) and
        jit.parallelWorkerSlot(self) != null and
        d.op == .nop and d.len == 2 and bytes.len >= 2 and bytes[0] == 0xF3 and bytes[1] == 0x90;
}

pub fn canBackoff(self: *ElfState, capturing: bool) bool {
    if (capturing or self.block_jit_verify_memory or self.guest_clock.source != .host_monotonic or self.diagnose_abi or
        self.windowsMemoryTraceLive() or jit.blockJitTracingActive(self)) return false;
    // Yielding used to keep interpreted stores aging between instructions.
    // Never extend their unpublished lifetime with a new timed host wait.
    if (jit.activeGuestTsoStoreBuffer(self)) |buffer| if (!buffer.isEmpty()) return false;
    return true;
}

pub fn execute(self: *ElfState, block: *const I._block_jit.Block, index: u32) u32 {
    const insn = &block.insns[index];
    const ctx = life.guestContextRef(self);
    // emitInterpretCall has published the GPR/vector caches. The spin
    // detector must also see precise flags and the PAUSE's original RIP.
    I._blockJitFlags(self);
    ctx.field("regs").*.rip = insn.rip;
    ctx.field("last_instruction_rip").* = insn.rip;
    ctx.field("last_decoded_op").* = insn.decoded.op;
    ctx.field("last_decoded_len").* = insn.len;
    life.noteWindowsGuestPause(self);
    ctx.field("regs").*.rip +%= insn.len;
    // A stall assist can reach guest-memory helpers. Publish any stores it
    // queued before the rest of the trace resumes with direct native loads.
    I._tso_memory.flushActiveStoreBufferFor(.jit_fallback);
    if (self.currentBlockJit()) |active| {
        // One executor owns this counter. Publish on the exact same cadence
        // as the PAUSE scheduler snapshot; worker progress/exit publishes any
        // non-boundary tail before diagnostics consume the final totals.
        if (self.pause_options.counter_batches_enabled) {
            active.pause_helper_calls_local +%= 1;
            if (ctx.field("windows_slice_pause_yield").*) {
                @atomicStore(u64, &active.pause_helper_calls, active.pause_helper_calls_local, .monotonic);
            }
        } else {
            const calls = @atomicLoad(u64, &active.pause_helper_calls, .monotonic) +| 1;
            active.pause_helper_calls_local = calls;
            @atomicStore(u64, &active.pause_helper_calls, calls, .monotonic);
        }
    }
    const capturing = if (ctx.field("windows_active_guest_thread_slot").*) |slot|
        self.windows_guest_threads[slot].spin.capture_remaining != 0 or self.windows_guest_threads[slot].status != .running
    else
        true;
    if (ctx.field("windows_guest_slice_yield_requested").* or ctx.field("windows_guest_handoff_requested").* or
        capturing or life.isTerminated(self) or ctx.field("guest_access_violation_pending").*)
    {
        ctx.field("block_jit_scratch").chain_break = 1;
        return 1;
    }
    return 0;
}
