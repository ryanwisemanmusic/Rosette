//! Compilation-only evidence at existing progress/exit boundaries. These
//! counters never run on native block hops or individual guest operations.
const I = @import("../../process.zig").__ProcessInternals;
pub fn compiled(jit: *I._BlockJitState, direct_chain: bool, scalar_ops: u32) void {
    if (direct_chain) {
        const old = @atomicLoad(u64, &jit.direct_chain_templates_compiled, .monotonic);
        @atomicStore(u64, &jit.direct_chain_templates_compiled, old +| 1, .monotonic);
    }
    if (scalar_ops != 0) {
        const old = @atomicLoad(u64, &jit.direct_scalar_ops_compiled, .monotonic);
        @atomicStore(u64, &jit.direct_scalar_ops_compiled, old +| scalar_ops, .monotonic);
    }
}
fn row(jit: *I._BlockJitState, name: []const u8) void {
    const chain = @atomicLoad(u64, &jit.direct_chain_templates_compiled, .monotonic);
    const scalar = @atomicLoad(u64, &jit.direct_scalar_ops_compiled, .monotonic);
    if (chain == 0 and scalar == 0) return;
    I._log.info("PE64 NATIVE PATH TEMPLATES: name='{s}' direct_chain_blocks={d} direct_scalar_ops={d}; cumulative compiled templates, not execution counts, compatible-hit share or saved CPU", .{ name, chain, scalar });
}
pub fn report(self: anytype) void {
    if (self.block_jit) |jit| row(jit, "owner");
    for (self.windows_guest_threads) |thread| {
        const jit = thread.parallel_block_jit orelse continue;
        row(jit, thread.nameText());
    }
}
