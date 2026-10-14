//! Fuse exact registered NT-yield / CRT-math tail thunks with their existing
//! fast stub adapter. Ordinary calls and unclaimed targets keep their path.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const life = @import("lifecycle.zig");
const jit = @import("block_jit.zig");
pub const Ledger = struct { enabled: bool = true };
pub fn configure(state: anytype, envFalse: anytype) void {
    state.windows_idle_yield.configure(envFalse);
    state.windows_register_imports.enabled = !envFalse("ROSETTE_PE64_REGISTER_IMPORT_TAIL");
}
pub fn total(state: *process.ElfState) u64 {
    var count: u64 = 0;
    for (state.windows_guest_threads) |thread| if (thread.parallel_block_jit) |active| {
        count +|= @atomicLoad(u64, &active.register_import_tail_calls, .monotonic);
    };
    return count;
}
pub fn report(state: *process.ElfState) void {
    for (state.windows_guest_threads, 0..) |thread, slot| if (thread.parallel_block_jit) |active| {
        const count = @atomicLoad(u64, &active.register_import_tail_calls, .monotonic);
        if (count != 0) std.log.info("PE64 REGISTER IMPORT TAIL: slot={d} name='{s}' calls={d}; exact registered NT-yield/math target and live IAT binding; existing fast adapter, stack pop, ABI, TSO and yield retained; ordinary calls unchanged", .{ slot, thread.nameText(), count });
    };
}
// The original fast-stub adapter, shared by step dispatch and fused thunks.
// Only the transfer is fused; handler admission and calling convention agree.
pub fn tryStub(self: *process.ElfState, address: u64) bool {
    if (!life.windowsFastCrtImportMayBypassRuntimeLock(self)) return false;
    const stub = self.windowsImportStubAt(address) orelse return false;
    return tryRegistered(self, stub, false);
}
fn tryRegistered(self: *process.ElfState, stub: anytype, comptime narrow: bool) bool {
    if (stub.is_dynamic) {
        if (stub.iat_address != 0) return false;
    } else if (stub.iat_address == 0 or self.read64(stub.iat_address) != stub.address) return false;
    const regs = life.guestContextField(self, "regs");
    const return_rip = self.read64(regs.rsp);
    if (return_rip == 0) return false;
    const claimed = if (narrow)
        I._x64_linux_runtime.tryWindowsFastRegisteredTail(self, stub.dll_name, stub.function_name, return_rip)
    else
        I._x64_linux_runtime.tryWindowsFastFunction(self, stub.dll_name, stub.function_name, return_rip);
    if (!claimed) return false;
    regs.rsp +%= 8;
    return true;
}
pub fn tryExecute(self: *process.ElfState, insn: *const I._block_jit.Insn) bool {
    if (!insn.registered_import_tail or insn.decoded.op != .jmp_reg64 or self.block_jit_verify_memory or !self.windows_register_imports.enabled or
        self.guest_clock.source != .host_monotonic or
        insn.force_fallback or !life.windowsFastCrtImportMayBypassRuntimeLock(self)) return false;
    const ctx = life.guestContextRef(self);
    if (ctx.field("block_jit_scratch").jmp_guard != 0 or self.trace_calls or
        self.diagnose_abi or self.trace_write_address != null or self.windowsMemoryTraceLive() or
        jit.blockJitTracingActive(self)) return false;
    const target = self.regVal(insn.decoded.dst_reg, .bits64);
    if (!self.windows_stub_box.contains(target) or self.call_probes.indexOf(target) != null or
        self.windows_compat_hook_points.contains(target)) return false;
    const stub = self.windowsImportStubAt(target) orelse return false;
    // Avoid a second speculative handler traversal for unclaimed imports.
    // Shared-table handlers (including SRW) are outside this fused surface.
    const name = stub.function_name;
    if (!std.mem.eql(u8, name, "NtDelayExecution") and !std.mem.eql(u8, name, "NtYieldExecution") and
        !std.mem.eql(u8, name, "exp2") and !std.mem.eql(u8, name, "exp2f")) return false;
    I._blockJitFlags(self);
    if (!tryRegistered(self, stub, true)) return false;
    ctx.field("last_instruction_rip").* = insn.rip;
    ctx.field("last_decoded_op").* = insn.decoded.op;
    ctx.field("last_decoded_len").* = insn.len;
    I._tso_memory.flushActiveStoreBufferFor(.jit_fallback);
    if (self.currentBlockJit()) |active| {
        const count = @atomicLoad(u64, &active.register_import_tail_calls, .monotonic);
        @atomicStore(u64, &active.register_import_tail_calls, count +| 1, .monotonic);
    }
    ctx.field("block_jit_scratch").chain_break = 1;
    return true;
}
