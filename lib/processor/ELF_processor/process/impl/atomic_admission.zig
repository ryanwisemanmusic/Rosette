//! A failed comparison still reached an address that may be eligible for
//! native atomic access. Admission re-proves writable backing, protections,
//! tracing, executable pages and the invalidation epoch; success is not a
//! substitute for those proofs, and failure need not prevent them.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const jit = @import("block_jit.zig");
pub fn consider(self: *process.ElfState, op: I._Op, address: u64, width: u8, wrote: bool) void {
    const compare = switch (op) {
        .cmpxchg_mem8_reg8, .cmpxchg_mem16_reg16, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64 => true,
        else => false,
    };
    const active = self.currentBlockJit() orelse return;
    if (!wrote and !(compare and active.admit_failed_compare)) return;
    self.blockJitTlbConsider(address, width, true);
    if (compare and !wrote) {
        const admitted = jit.activeBlockJitTlb(self).lookup(true, address) != null;
        const counter = if (admitted) &active.failed_compare_admitted else &active.failed_compare_refused;
        const count = @atomicLoad(u64, counter, .monotonic);
        @atomicStore(u64, counter, count +| 1, .monotonic);
    }
}
pub fn report(self: *process.ElfState) void {
    if (self.block_jit) |active| row(active, "owner");
    for (self.windows_guest_threads) |thread| if (thread.parallel_block_jit) |active| row(active, thread.nameText());
}
fn row(active: anytype, name: []const u8) void {
    const admitted = @atomicLoad(u64, &active.failed_compare_admitted, .monotonic);
    const refused = @atomicLoad(u64, &active.failed_compare_refused, .monotonic);
    if (admitted +| refused != 0) std.log.info("PE64 ATOMIC COMPARE ADMISSION: name='{s}' admitted={d} refused={d}; failed compare-exchange misses use the unchanged writable-page and epoch proof; faulting, protected, watched and code pages keep interpreter guards", .{ name, admitted, refused });
}
