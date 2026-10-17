//! Static qualification only, published at the existing report boundary.
//! Compilation counters never run inside guest instruction or chain loops.
const I = @import("../../process.zig").__ProcessInternals;
pub fn compiled(jit: *I._BlockJitState, counts: [3]u32) void {
    for (&jit.direct_operand_templates, counts) |*counter, n| {
        if (n == 0) continue;
        const old = @atomicLoad(u64, counter, .monotonic);
        @atomicStore(u64, counter, old +| n, .monotonic);
    }
}
fn row(jit: *I._BlockJitState, name: []const u8) void {
    var n: [3]u64 = undefined;
    for (&n, &jit.direct_operand_templates) |*value, *counter| value.* = @atomicLoad(u64, counter, .monotonic);
    if (n[0] | n[1] | n[2] == 0) return;
    I._log.info("PE64 DIRECT REGISTER OPERANDS: name='{s}' variable_shift={d} conversion={d} multiply={d}; independently read cumulative compiled templates, not execution counts or saved CPU", .{ name, n[0], n[1], n[2] });
}
pub fn report(state: anytype) void {
    if (state.block_jit) |jit| row(jit, "owner");
    for (state.windows_guest_threads) |thread| {
        const jit = thread.parallel_block_jit orelse continue;
        row(jit, thread.nameText());
    }
}
