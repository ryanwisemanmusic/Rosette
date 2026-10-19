//! The first direct successor is the common case. Its complete slot/address/
//! generation proof follows immediately; the remaining ways and jump-cache
//! search live after the successful hop. No link or proof is cached here.
const a64 = @import("arm64_encode");
const core = @import("core.zig");

/// x11=this block, x13=next guest RIP, x15=matching link on success.
/// This is the original way-zero comparison, without a branch to proof.
pub fn first(a: anytype, miss: anytype) !void {
    const offset = core.hop_offset + @offsetOf(core.Hop, "links");
    try a.emit(a64.ldrImm(.doubleword, 12, 11, offset + @offsetOf(core.Link, "rip")).?);
    try a.emit(a64.cmp(.x64, 12, 13));
    try a.branchCond(.ne, miss);
    try a.emit(a64.addImm(.x64, 15, 11, offset).?);
}

/// Branch to `prove` with x15 = the way whose address is x13 (x11 = this
/// block). Each way costs only its address compare; the way that matches is
/// proved once.
pub fn wayScan(c: anytype, first_way: usize, prove: anytype) !void {
    for (first_way..core.link_ways) |way| {
        const base: u32 = @intCast(core.hop_offset + @offsetOf(core.Hop, "links") + way * @sizeOf(core.Link));
        const next_way = try c.a.createLabel();
        try c.emitChecked(a64.ldrImm(.doubleword, 12, 11, base + @offsetOf(core.Link, "rip")));
        try c.emit(a64.cmp(.x64, 12, 13));
        try c.a.branchCond(.ne, next_way);
        try c.emitChecked(a64.addImm(.x64, 15, 11, base));
        try c.a.branch(prove);
        c.a.placeLabel(next_way);
    }
}

/// Branch to `prove` with x15 = the jump-cache entry for x13 when it names
/// x13, else to `miss`.
pub fn jumpCacheProbe(c: anytype, prove: anytype, miss: anytype) !void {
    try c.emitChecked(a64.ldrImm(.doubleword, 12, 22, @offsetOf(core.Scratch, "jump_cache")));
    try c.a.branchIfZero(.x64, 12, miss);
    try c.emit(a64.lsrImm(.x64, 14, 13, core.jump_cache_shift));
    try c.emit(a64.eorReg(.x64, 14, 14, 13));
    try c.emit(a64.logicalImmediate(.x64, .andop, 14, 14, core.jump_cache_entries - 1).?);
    try c.emit(a64.addSubShifted(.x64, .add, false, 15, 12, 14, @import("std").math.log2_int(usize, @sizeOf(core.Link))));
    try c.emitChecked(a64.ldrImm(.doubleword, 14, 15, @offsetOf(core.Link, "rip")));
    try c.emit(a64.cmp(.x64, 14, 13));
    try c.a.branchCond(.ne, miss);
    try c.a.branch(prove);
}

/// After a block whose every exit address is known missed its ways: the
/// jump cache too, unless the block can link all its targets itself
/// (`direct_links.Plan.ownsAllTargets`). A successor some other block
/// linked sits in the jump cache, and a hop found there never reaches the
/// glue, so this block's exit would never be linked or patched; leaving
/// once lets the glue do both.
pub fn staticMiss(c: anytype, prove: anytype, leave: anytype, owns_all_targets: bool) !void {
    if (owns_all_targets) return c.a.branch(leave);
    try jumpCacheProbe(c, prove, leave);
}
