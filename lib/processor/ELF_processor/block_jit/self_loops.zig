//! A native back-edge to the executing block can keep that block's GPR
//! assignment. It still proves the source generation on every iteration;
//! the caller performs the usual scheduler/budget checks before this path.
const a64 = @import("arm64_encode");
const core = @import("core.zig");

pub fn hasEdge(insns: []const core.Insn) bool {
    for (insns) |insn| {
        const d = insn.decoded;
        if (insn.force_fallback) continue;
        const displacement = switch (d.op) {
            .jcc_rel8, .jcc_rel32 => d.addr,
            .jmp_rel8 => d.imm,
            else => continue,
        };
        if (insn.rip +% d.len +% displacement == insns[0].rip) return true;
    }
    return false;
}

/// t2 is the executing Block, t4 the requested successor; t1/t3 are dead
/// temporaries after accounting. No cache register or host flags survive
/// as an input to the next iteration. A non-self successor falls through.
pub fn emit(a: *core.Assembler, block: a64.Reg, target: a64.Reg, scratch: a64.Reg, loop: core.Label, leave: core.Label) !void {
    const other = try a.createLabel();
    try a.emit(a64.ldrImm(.doubleword, 12, block, @offsetOf(core.Block, "start_rip")).?);
    try a.emit(a64.cmp(.x64, 12, target));
    try a.branchCond(.ne, other);
    try a.emit(a64.ldrImm(.doubleword, 12, block, @offsetOf(core.Block, "chain_gen_ptr")).?);
    try a.emit(a64.ldrImm(.doubleword, 12, 12, 0).?);
    try a.emit(a64.ldrImm(.doubleword, 10, block, @offsetOf(core.Block, "chain_generation")).?);
    try a.emit(a64.cmp(.x64, 12, 10));
    try a.branchCond(.ne, leave);
    try a.emit(a64.strImm(.doubleword, block, scratch, @offsetOf(core.Scratch, "chain_previous")).?);
    try a.branch(loop);
    a.placeLabel(other);
}
