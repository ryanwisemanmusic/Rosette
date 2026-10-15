//! Startup diagnostics can temporarily exclude PAUSE from translation.
//! Only an ends-before:NOP refusal may revisit that policy after it closes.
//! Cross-check refusals, allocation failures and other opcodes stay refused.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const admission = @import("pause_jit.zig");
const jit_impl = @import("block_jit.zig");
pub fn deferred(self: *process.ElfState, jit: *I._BlockJitState, rip: u64) bool {
    if (jit.last_refusal != .ends_before or jit.last_refusal_op != .nop) return false;
    const source = jit_impl.fetchInstructionSource(self, rip) orelse return false;
    const bytes = source.contents();
    return bytes.len >= 2 and bytes[0] == 0xF3 and bytes[1] == 0x90;
}
pub fn revive(self: *process.ElfState, jit: *I._BlockJitState, hot: *I._BlockHotness, rip: u64) void {
    if (!jit.recheck_pause_policy or !hot.pause_policy_refused or !hot.refused or !admission.policyReady(self)) return;
    // canCompile preserves every existing tracing, clock, ABI and worker gate.
    // Fetch remains under the same source/mapping lease as block collection.
    const source = jit_impl.fetchInstructionSource(self, rip) orelse return;
    const bytes = source.contents();
    if (bytes.len < 2 or bytes[0] != 0xF3 or bytes[1] != 0x90) return;
    const decoded = I._decodeInsn(bytes);
    if (!admission.canCompile(self, decoded, bytes)) return;
    // Consume this one policy revival before collection: an OOM/compile
    // refusal cannot repeatedly bypass the original retry backoff.
    hot.pause_policy_refused = false;
    hot.refused = false;
    hot.refused_runs = 0;
    hot.count = jit.hot_threshold -| 1;
    const revived = @atomicLoad(u64, &jit.pause_policy_revived, .monotonic);
    @atomicStore(u64, &jit.pause_policy_revived, revived +| 1, .monotonic);
}
pub fn report(self: anytype) void {
    const log = I._log;
    if (self.block_jit) |jit| if (@atomicLoad(u64, &jit.pause_policy_revived, .monotonic) != 0)
        log.info("PE64 PAUSE POLICY RECHECK: name='owner' revived={d}; only startup-deferred exact PAUSE sites; original admission and scheduling retained", .{@atomicLoad(u64, &jit.pause_policy_revived, .monotonic)});
    for (self.windows_guest_threads, 0..) |thread, slot| {
        const jit = thread.parallel_block_jit orelse continue;
        if (@atomicLoad(u64, &jit.pause_policy_revived, .monotonic) == 0) continue;
        log.info("PE64 PAUSE POLICY RECHECK: slot={d} name='{s}' revived={d}; only startup-deferred exact PAUSE sites; original admission and scheduling retained", .{ slot, thread.nameText(), @atomicLoad(u64, &jit.pause_policy_revived, .monotonic) });
    }
}
