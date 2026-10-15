//! Compilation-only evidence: these are templates, not executed operations.
//! One owning compiler writes; existing progress/exit readers use atomics.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
pub fn compiled(jit: *I._BlockJitState, operations: u32) void {
    if (operations == 0) return;
    const old = @atomicLoad(u64, &jit.scalar_resident_ops_compiled, .monotonic);
    @atomicStore(u64, &jit.scalar_resident_ops_compiled, old +| operations, .monotonic);
}
fn count(jit: *I._BlockJitState) u64 {
    return @atomicLoad(u64, &jit.scalar_resident_ops_compiled, .monotonic);
}
pub fn report(self: anytype) void {
    if (self.block_jit) |jit| if (count(jit) != 0)
        I._log.info("PE64 SCALAR XMM RESIDENCY: name='owner' compiled_ops={d}; cumulative register scalar templates, not execution counts or saved CPU time", .{count(jit)});
    for (self.windows_guest_threads, 0..) |thread, slot| {
        const jit = thread.parallel_block_jit orelse continue;
        if (count(jit) == 0) continue;
        I._log.info("PE64 SCALAR XMM RESIDENCY: slot={d} name='{s}' compiled_ops={d}; cumulative register scalar templates, not execution counts or saved CPU time", .{ slot, thread.nameText(), count(jit) });
    }
}
