//! Indirect links: a block whose exit address is known only at run time - a
//! `ret`, a `call rax` through Xenia's indirection table, a jump through a
//! table - looks for its successor in its own four link ways first, and each
//! way falls into a `b` of its own that the glue points at the successor's
//! direct entry when it links that way (`blockJitLink`), as it patches a
//! direct link's site (`direct_links.zig`).
//!
//! Why. Halo 3's MAIN_THREAD runs Xenia's x64 output, which calls a guest
//! function not yet compiled when its caller was through the indirection
//! table and returns with `ret`; both used to leave through the thread's
//! jump cache (a hash, a load from a 256 KiB table), the successor's hop
//! line and generation word, and an indirect `br` the predictor has to hold
//! for every such exit. A call site through the table names one function, and
//! most functions return to a few call sites, so most of these exits find
//! their successor in a way: one load from the block's own hop line, a
//! compare, and a direct branch.
//!
//! Dispatch. Way i: compare the exit's address with the way's; on a match,
//! fall into way site i. Unlinked, the site branches to the way's original
//! proof (the successor's hop line, generation, `br`). When no way matches
//! and the last one is still empty, the exit leaves for the glue, which
//! links a way and patches its site; when all four are in use, the jump
//! cache and its proof follow as before.
//!
//! Correctness. A way and its site change together, in the glue, while none
//! of this translator's code runs: way i names (address, block) and site i
//! branches into that block's direct entry, or back to the way's proof when
//! it cannot (no direct entry, a target out of reach with no veneer). A hop
//! takes site i only after comparing its address with way i's, and the
//! successor's direct entry proves its own generation, so a dropped,
//! rewritten, recycled or remotely disarmed successor leaves as a failed
//! proof does and the glue relinks the way.
const std = @import("std");
const a64 = @import("arm64_encode");
const core = @import("core.zig");
const chain_layout = @import("chain_layout.zig");
const direct_links = @import("direct_links.zig");

/// Process-wide switch, read once from `ROSETTE_X64_INDIRECT_LINKS` (0 keeps
/// the jump-cache-first dispatch for blocks compiled from then on). Tests and
/// the benchmark set it directly.
pub var enabled: ?bool = null;

pub fn active() bool {
    if (enabled) |value| return value;
    const value = if (std.c.getenv("ROSETTE_X64_INDIRECT_LINKS")) |raw| raw[0] != '0' else true;
    enabled = value;
    return value;
}

fn wayOffset(way: usize) u32 {
    return @intCast(core.hop_offset + @offsetOf(core.Hop, "links") + way * @sizeOf(core.Link));
}

/// The dispatch of a block whose exit address is known only at run time,
/// with x11 = this block and x13 = the successor's guest address (the
/// registers of `chain_layout`); `prove` expects x15 = the matching link.
/// Returns false, emitting nothing, when the block cannot have way sites.
pub fn emitDispatch(c: anytype, prove: anytype, leave: anytype) !bool {
    if (!active() or !c.links.sites_enabled or c.a.section == .cold) return false;
    const Label = @TypeOf(prove);
    var proofs: [core.link_ways]Label = undefined;
    const miss = try c.a.createLabel();
    for (0..core.link_ways) |way| {
        const next = if (way + 1 < core.link_ways) try c.a.createLabel() else miss;
        try c.emitChecked(a64.ldrImm(.doubleword, 12, 11, wayOffset(way) + @offsetOf(core.Link, "rip")));
        try c.emit(a64.cmp(.x64, 12, 13));
        try c.a.branchCond(.ne, next);
        const site = try c.a.createLabel();
        c.a.placeLabel(site);
        c.links.way_sites[way] = site;
        proofs[way] = try c.a.createLabel();
        try c.a.branch(proofs[way]);
        if (way + 1 < core.link_ways) c.a.placeLabel(next);
    }
    c.links.way_count = core.link_ways;
    c.links.way_proofs = proofs;
    c.a.placeLabel(miss);
    // x12 is the last way's address: zero while a way is free.
    try c.a.branchIfZero(.x64, 12, leave);
    try chain_layout.jumpCacheProbe(c, prove, leave);
    for (proofs, 0..) |label, way| {
        c.a.placeLabel(label);
        try c.emitChecked(a64.addImm(.x64, 15, 11, wayOffset(way)));
        try c.a.branch(prove);
    }
    return true;
}

/// The way `blockJitLink` arms for `rip`: the one that already names it,
/// else the round-robin victim. Null when `from` has way sites and all four
/// name other addresses: a successor past the fourth stays in the jump cache,
/// where replacing a way would re-patch its branch on every such visit.
pub fn chooseWay(from: anytype, rip: u64) ?usize {
    for (from.hop.links, 0..) |existing, index| {
        if (existing.rip == rip) return index;
    }
    const way: usize = from.link_victim;
    if (from.links.ways[0] != 0 and from.hop.links[way].rip != 0) return null;
    from.link_victim = @intCast((way + 1) % core.link_ways);
    return way;
}

/// After the glue made way `way` of `from` name `to`: point the way's site
/// at `to`'s direct entry, or back at the way's proof when it cannot. Owner
/// thread, no translated code running.
pub fn linkWay(from: anytype, way: usize, to: anytype, memory: anytype) direct_links.LinkResult {
    var result: direct_links.LinkResult = .{};
    const offset = from.links.ways[way];
    if (offset == 0 or from.code.len == 0) return result;
    const at = @intFromPtr(from.code.ptr) + offset;
    if (direct_links.active() and to.links.entry != 0 and to.code.len != 0) {
        const target: i64 = @intCast(@intFromPtr(to.code.ptr) + to.links.entry);
        direct_links.patchAt(&result, at, target, memory);
        if (direct_links.branchesTo(at, target, memory)) return result;
    }
    // Back to the proof, which reads the way: never a branch into a block
    // linked for another address.
    var restored: direct_links.LinkResult = .{};
    direct_links.patchAt(&restored, at, @intCast(@intFromPtr(from.code.ptr) + from.links.way_proofs[way]), memory);
    return result;
}

/// Whether way `way` of `from` currently branches into `to`.
pub fn wayLinked(from: anytype, way: usize, to: anytype, memory: anytype) bool {
    const offset = from.links.ways[way];
    if (offset == 0 or to.links.entry == 0) return false;
    return direct_links.branchesTo(@intFromPtr(from.code.ptr) + offset, @intCast(@intFromPtr(to.code.ptr) + to.links.entry), memory);
}
