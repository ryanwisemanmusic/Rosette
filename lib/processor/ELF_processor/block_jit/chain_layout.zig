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
