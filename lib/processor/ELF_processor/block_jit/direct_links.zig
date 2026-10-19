//! Direct links: a block's exit to a known address jumps straight into the
//! block compiled for it, through one `b` the glue patches in when it links
//! the two (`blockJitLink`).
//!
//! Why. A chain hop through `hop.links` ends in `br`, an indirect branch
//! whose target the predictor has to remember for every block. Measured on
//! this host (M2 Max, 2026-10-19; the harness is in the pass's evidence):
//! with 2,048-16,384 blocks of about 1 KB in a ring, the production hop costs
//! 7-25 ns more per block than a direct `b` into a successor that checks its
//! own generation, and Halo 3's MAIN_THREAD pays 50-59 ns per block live.
//! A direct branch the predictor has forgotten costs a decode redirect; an
//! indirect one waits for the loads that produce its target, then refetches.
//!
//! Exit. A stub whose address is known sets x8 and x0 as every stub does and
//! calls the block's exit checks (`bl`): the register-cache write-back, the
//! chain accounting, the break flag and the step budget, exactly what the
//! shared exit path ran before the way scan. They return to the stub's
//! site: one `b` naming the block's own dispatch (the original way scan,
//! jump cache and proof) until the glue links the exit, then the
//! successor's direct entry. A block whose loop keeps its registers
//! resident publishes them only after its proof, so it keeps the shared
//! path and has no sites.
//!
//! Entry. The successor proves itself from its own code. Its header holds
//! the generation word and value it was armed at (`armChain`) and its
//! `Block`; the direct entry loads the word through the header and compares
//! it with the value, and only then becomes the executing block
//! (`scratch.block`, `scratch.chain_previous`, `r_helpers`), exactly as the
//! indirect hop does after its proof. `disarmChain` writes the header's
//! word pointer to `chain_never_word`, so a branch into code that was
//! dropped, rewritten or recycled fails there and leaves as a failed proof
//! does: x0, x8, the frame and the register file are what the
//! predecessor's exit checks left, and the glue relinks the site.
//!
//! Lifetime. Code memory is bump-allocated and reset only whole, after every
//! block was freed and so disarmed: a patched branch always lands in the code
//! it was patched for, live or disarmed. A header write first checks that
//! the header still names its block.
const std = @import("std");
const builtin = @import("builtin");
const a64 = @import("arm64_encode");
const core = @import("core.zig");
pub const far_links = @import("far_links.zig");

/// One exit whose target is known: the guest address it leaves to and the
/// byte offset of its patchable `b` from the block's code.
pub const Site = struct { rip: u64, offset: u32 };

/// A block's patchable exits: Xenia's blocks end in one or two known
/// addresses; a block with more keeps the rest on the shared exit path.
pub const max_sites = 6;

/// What a block keeps for its links: where its header and direct entry are
/// in its code (0: none), and its patchable exits.
pub const BlockLinks = struct {
    header: u32 = 0,
    entry: u32 = 0,
    count: u8 = 0,
    site_list: [max_sites]Site = undefined,
    /// Byte offsets of the patchable `b` each link way falls into when an
    /// exit known only at run time matches it (`indirect_links.zig`); 0
    /// when the block has none.
    ways: [core.link_ways]u32 = @splat(0),
    /// Where each way site branches while unlinked: the way's proof.
    way_proofs: [core.link_ways]u32 = @splat(0),

    pub fn sites(self: *const BlockLinks) []const Site {
        return self.site_list[0..self.count];
    }
};

/// The three doublewords the direct entry reads, in the block's code.
pub const Header = extern struct {
    gen_ptr: u64,
    generation: u64,
    block: u64,
};

/// Process-wide switch, read once from `ROSETTE_X64_DIRECT_LINKS` (0 turns
/// links off: sites are still emitted but never patched). Tests and the
/// benchmark set it directly.
pub var enabled: ?bool = null;

pub fn active() bool {
    if (enabled) |value| return value;
    const value = if (std.c.getenv("ROSETTE_X64_DIRECT_LINKS")) |raw| raw[0] != '0' else true;
    enabled = value;
    return value;
}

/// The registers and offsets the emitted entry uses (core's assignment).
pub const Registers = struct {
    helpers: a64.Reg,
    scratch: a64.Reg,
    t1: a64.Reg,
    t2: a64.Reg,
    t3: a64.Reg,
    t5: a64.Reg,
    helpers_offset: u32,
    block_offset: u32,
    previous_offset: u32,
};

pub const SiteLabel = struct { rip: u64, label: Label };

const Label = a64.assembler.Label;

/// The compiler's view of one block's links while it emits.
pub const Plan = struct {
    /// Emit the header and direct entry.
    entry_enabled: bool = false,
    /// Route exits with a known address through patchable sites.
    sites_enabled: bool = false,
    header: Label = undefined,
    generation: Label = undefined,
    block: Label = undefined,
    entry: Label = undefined,
    /// The leave path past a resident loop's write-back: a failed direct
    /// entry has not loaded this block's register cache.
    unloaded: Label = undefined,
    checks: Label = undefined,
    dispatch: Label = undefined,
    count: u8 = 0,
    sites: [max_sites]SiteLabel = undefined,
    /// Some exit's address is known only at run time, or did not get a site.
    unlinkable: bool = false,
    /// The way sites `indirect_links.emitDispatch` placed (0 or link_ways).
    way_count: u8 = 0,
    way_sites: [core.link_ways]Label = undefined,
    way_proofs: [core.link_ways]Label = undefined,

    pub fn init(a: anytype, entry_enabled: bool, sites_enabled: bool) !Plan {
        var plan: Plan = .{ .entry_enabled = entry_enabled, .sites_enabled = entry_enabled and sites_enabled };
        if (!entry_enabled) return plan;
        inline for (.{ "header", "generation", "block", "entry", "unloaded", "checks", "dispatch" }) |name| @field(plan, name) = try a.createLabel();
        return plan;
    }

    /// Right after the prologue: the glue's entry branches over the header
    /// and the direct entry, which falls into the chain entry.
    pub fn emitEntry(self: *Plan, a: anytype, r: Registers) !void {
        if (!self.entry_enabled) return;
        const chain_entry = try a.createLabel();
        try a.branch(chain_entry);
        if (a.len() % 2 != 0) try a.emit(a64.nop());
        // Not armed yet: the word pointer names a word no generation equals.
        const never: u64 = @intFromPtr(&core.chain_never_word);
        a.placeLabel(self.header);
        try a.emit(@truncate(never));
        try a.emit(@truncate(never >> 32));
        a.placeLabel(self.generation);
        try a.emit(0);
        try a.emit(0);
        a.placeLabel(self.block);
        try a.emit(0);
        try a.emit(0);
        a.placeLabel(self.entry);
        try a.loadLiteral(r.t3, self.header);
        try a.loadLiteral(r.t1, self.generation);
        try a.emit(a64.ldrImm(.doubleword, r.t3, r.t3, 0).?);
        try a.emit(a64.cmp(.x64, r.t3, r.t1));
        try a.branchCond(.ne, self.unloaded);
        try a.loadLiteral(r.t5, self.block);
        try a.emit(a64.subImm(.x64, r.t2, r.helpers, r.helpers_offset).?);
        try a.emit(a64.strImm(.doubleword, r.t2, r.scratch, r.previous_offset).?);
        try a.emit(a64.strImm(.doubleword, r.t5, r.scratch, r.block_offset).?);
        try a.emit(a64.addImm(.x64, r.helpers, r.t5, r.helpers_offset).?);
        a.placeLabel(chain_entry);
    }

    /// An exit stub's transfer once x8 and x0 are set: through a site when
    /// its address is known, else to the shared exit path.
    pub fn emitTransfer(self: *Plan, a: anytype, rip: ?u64, exit_path: Label) !void {
        const target = rip orelse {
            self.unlinkable = true;
            return a.branch(exit_path);
        };
        if (!self.sites_enabled or a.section == .cold or self.count == max_sites) {
            if (a.section != .cold) self.unlinkable = true;
            return a.branch(exit_path);
        }
        try a.call(self.checks);
        const site = try a.createLabel();
        a.placeLabel(site);
        self.sites[self.count] = .{ .rip = target, .label = site };
        self.count += 1;
        try a.branch(self.dispatch);
    }

    /// Every exit of the block has a site and their addresses fit in the
    /// block's link ways: a way miss means a target not linked yet.
    pub fn ownsAllTargets(self: *const Plan) bool {
        if (!self.sites_enabled or self.count == 0 or self.unlinkable) return false;
        var distinct: usize = 0;
        for (self.sites[0..self.count], 0..) |site, i| {
            for (self.sites[0..i]) |earlier| {
                if (earlier.rip == site.rip) break;
            } else distinct += 1;
        }
        return distinct <= core.link_ways;
    }

    /// The finished block's offsets.
    pub fn finish(self: *const Plan, a: anytype) BlockLinks {
        if (!self.entry_enabled) return .{};
        var links: BlockLinks = .{ .header = @intCast(a.hotWord(self.header).? * 4), .entry = @intCast(a.hotWord(self.entry).? * 4), .count = self.count };
        for (self.sites[0..self.count], links.site_list[0..self.count]) |site, *out| out.* = .{ .rip = site.rip, .offset = @intCast(a.hotWord(site.label).? * 4) };
        for (self.way_sites[0..self.way_count], links.ways[0..self.way_count]) |site, *out| out.* = @intCast(a.hotWord(site).? * 4);
        for (self.way_proofs[0..self.way_count], links.way_proofs[0..self.way_count]) |proof, *out| out.* = @intCast(a.hotWord(proof).? * 4);
        return links;
    }
};

// -- run time -----------------------------------------------------------------

const jit_host = builtin.os.tag.isDarwin() and builtin.cpu.arch == .aarch64;
extern "c" fn pthread_jit_write_protect_np(enabled: c_int) void;
extern "c" fn sys_icache_invalidate(start: ?*anyopaque, len: usize) void;

fn beginWrite() void {
    if (jit_host) pthread_jit_write_protect_np(0);
}

fn endWrite() void {
    if (jit_host) pthread_jit_write_protect_np(1);
}

fn header(block: anytype) ?*Header {
    if (block.links.header == 0 or block.code.len == 0) return null;
    return @ptrFromInt(@intFromPtr(block.code.ptr) + block.links.header);
}

/// Let the direct entry pass while `word` holds `generation`. Owner thread,
/// outside any code write.
pub fn arm(block: anytype, word: *const u64, generation: u64) void {
    const h = header(block) orelse return;
    const self_address = @intFromPtr(block);
    const named = @atomicLoad(u64, &h.block, .monotonic);
    if (named != 0 and named != self_address) return;
    const never = @intFromPtr(&core.chain_never_word);
    beginWrite();
    defer endWrite();
    // Disarmed while the value changes, so no reader pairs a live word
    // pointer with a value it was not armed at.
    @atomicStore(u64, &h.gen_ptr, never, .release);
    @atomicStore(u64, &h.generation, generation, .release);
    @atomicStore(u64, &h.block, self_address, .release);
    @atomicStore(u64, &h.gen_ptr, @intFromPtr(word), .release);
}

/// No direct entry passes from now on. Any thread.
pub fn disarm(block: anytype) void {
    const h = header(block) orelse return;
    if (@atomicLoad(u64, &h.block, .monotonic) != @intFromPtr(block)) return;
    const never = @intFromPtr(&core.chain_never_word);
    if (@atomicLoad(u64, &h.gen_ptr, .acquire) == never) return;
    beginWrite();
    defer endWrite();
    @atomicStore(u64, &h.gen_ptr, never, .release);
}

pub const LinkResult = struct { patched: u32 = 0, far: u32 = 0, veneers: u32 = 0 };

/// Point every site of `from` that leaves to `rip` at `to`'s direct entry,
/// when the branch reaches. Owner thread, no translated code running.
pub fn link(from: anytype, rip: u64, to: anytype, memory: anytype) LinkResult {
    var result: LinkResult = .{};
    if (!active() or to.links.entry == 0 or to.code.len == 0) return result;
    const target: i64 = @intCast(@intFromPtr(to.code.ptr) + to.links.entry);
    for (from.links.sites()) |site| {
        if (site.rip != rip) continue;
        patchAt(&result, @intFromPtr(from.code.ptr) + site.offset, target, memory);
    }
    return result;
}

/// Point the `b` at `at` at `target`, through a far veneer when it does not
/// reach. Owner thread, no translated code running.
pub fn patchAt(result: *LinkResult, at: usize, target: i64, memory: anytype) void {
    const delta = @divExact(target - @as(i64, @intCast(at)), 4);
    if (delta < -(1 << 25) or delta >= (1 << 25)) {
        result.far += 1;
        if (!far_links.link_enabled) return;
        if (far_links.pointsTo(memory, at, @intCast(target))) return;
        const p = far_links.plan(memory, at, @intCast(target)) orelse return;
        const slot: *u32 = @ptrFromInt(at);
        beginWrite();
        for (p.code, p.instructions) |*word, value| @atomicStore(u32, word, value, .release);
        @atomicStore(u32, slot, p.word, .release);
        endWrite();
        if (jit_host) {
            sys_icache_invalidate(@ptrCast(p.code), 16);
            sys_icache_invalidate(@ptrCast(slot), 4);
        }
        result.patched += 1;
        result.veneers += 1;
        return;
    }
    const word = a64.b(@intCast(delta));
    const slot: *u32 = @ptrFromInt(at);
    if (@atomicLoad(u32, slot, .monotonic) == word) return;
    beginWrite();
    @atomicStore(u32, slot, word, .release);
    endWrite();
    if (jit_host) sys_icache_invalidate(@ptrCast(slot), 4);
    result.patched += 1;
}

/// Whether the `b` at `at`, directly or through its far veneer, lands at
/// `target`.
pub fn branchesTo(at: usize, target: i64, memory: anytype) bool {
    if (far_links.pointsTo(memory, at, @intCast(target))) return true;
    const word = @as(*const u32, @ptrFromInt(at)).*;
    if (word >> 26 != 0b000101) return false;
    const imm: i32 = @bitCast(word << 6);
    return @as(i64, @intCast(at)) + @as(i64, imm >> 6) * 4 == target;
}

/// Whether `from`'s site for `rip` currently branches into `to`.
pub fn linked(from: anytype, rip: u64, to: anytype, memory: anytype) bool {
    if (to.links.entry == 0) return false;
    const target: i64 = @intCast(@intFromPtr(to.code.ptr) + to.links.entry);
    for (from.links.sites()) |site| {
        if (site.rip != rip) continue;
        if (branchesTo(@intFromPtr(from.code.ptr) + site.offset, target, memory)) return true;
    }
    return false;
}
