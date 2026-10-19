//! Indirect links (`block_jit/indirect_links.zig`) through the production
//! translator and glue: a `call rax` through a table and a `ret` find their
//! successor in a link way whose own branch the glue patched, and every way a
//! successor can stop being the right code - dropped, its memory reused, its
//! guest bytes rewritten, disarmed from another thread, out of a branch's
//! reach - leaves through the glue with exact guest state.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const ElfState = P.ElfState;
const MEM_BASE = I._MEM_BASE;
const block_jit = I._block_jit;
const direct_links = block_jit.direct_links;
const indirect_links = block_jit.indirect_links;
const jit_glue = @import("../impl/block_jit.zig");
const guest_memory = @import("../impl/guest_memory.zig");

const code: usize = 0x100000;
const table: usize = 0x50000;
const a_rip = MEM_BASE + code;
const r1_rip = a_rip + 15;
const r2_rip = a_rip + 23;
const exit_rip = a_rip + 38;
const f_rip = MEM_BASE + code + 0x80;
const c_rip = MEM_BASE + code + 0xC0;
const p_rip = MEM_BASE + code + 0x100;
const p_sites = 6;
const p_exit = p_rip + 5 * p_sites + 9 + 3;

fn rel32(from: u64, to: u64) [4]u8 {
    return @bitCast(@as(i32, @intCast(@as(i64, @intCast(to)) - @as(i64, @intCast(from)))));
}

/// A: mov rbx, table ; mov rax, [rbx] ; call rax (F) ; R1: inc rcx ; call F ;
/// R2: inc rdx ; dec r8 ; jnz A ; cmp rsp,rsp ; jmp $.  F: add r9,1 ; ret.
/// C, never on a path: mov ecx,0xdead ; jmp $.  P: six `call F` in a row
/// (F returns to six sites) ; dec r8 ; jnz P ; cmp rsp,rsp ; jmp $.
fn install(state: *ElfState) void {
    const mem = state.mem;
    std.mem.writeInt(u64, mem[table..][0..8], f_rip, .little);
    var at = code;
    mem[at..][0..2].* = .{ 0x48, 0xBB };
    mem[at + 2 ..][0..8].* = @bitCast(@as(u64, MEM_BASE + table));
    mem[at + 10 ..][0..3].* = .{ 0x48, 0x8B, 0x03 };
    mem[at + 13 ..][0..2].* = .{ 0xFF, 0xD0 };
    mem[at + 15 ..][0..3].* = .{ 0x48, 0xFF, 0xC1 };
    mem[at + 18] = 0xE8;
    mem[at + 19 ..][0..4].* = rel32(a_rip + 23, f_rip);
    mem[at + 23 ..][0..3].* = .{ 0x48, 0xFF, 0xC2 };
    mem[at + 26 ..][0..3].* = .{ 0x49, 0xFF, 0xC8 };
    mem[at + 29 ..][0..2].* = .{ 0x0F, 0x85 };
    mem[at + 31 ..][0..4].* = rel32(a_rip + 35, a_rip);
    mem[at + 35 ..][0..3].* = .{ 0x48, 0x39, 0xE4 };
    mem[at + 38 ..][0..2].* = .{ 0xEB, 0xFE };
    at = code + 0x80;
    mem[at..][0..4].* = .{ 0x49, 0x83, 0xC1, 0x01 };
    mem[at + 4] = 0xC3;
    at = code + 0xC0;
    mem[at..][0..5].* = .{ 0xB9, 0xAD, 0xDE, 0x00, 0x00 };
    mem[at + 5 ..][0..2].* = .{ 0xEB, 0xFE };
    at = code + 0x100;
    for (0..p_sites) |i| {
        mem[at + 5 * i] = 0xE8;
        mem[at + 5 * i + 1 ..][0..4].* = rel32(p_rip + 5 * i + 5, f_rip);
    }
    at += 5 * p_sites;
    mem[at..][0..3].* = .{ 0x49, 0xFF, 0xC8 };
    mem[at + 3 ..][0..2].* = .{ 0x0F, 0x85 };
    mem[at + 5 ..][0..4].* = rel32(p_rip + 5 * p_sites + 9, p_rip);
    mem[at + 9 ..][0..3].* = .{ 0x48, 0x39, 0xE4 };
    mem[at + 12 ..][0..2].* = .{ 0xEB, 0xFE };
}

const Fixture = struct {
    state: *ElfState,

    fn init() !Fixture {
        const state = try t.allocator.create(ElfState);
        state.* = ElfState.init(t.allocator);
        state.setParallelGuestExecution(true);
        state.windows_runtime_enabled = true;
        state.image_low = MEM_BASE + code;
        state.image_high = MEM_BASE + code + 0x200;
        state.configureWindowsExecutableRanges(&[_]I._WindowsExecutableRange{.{ .guest_base = MEM_BASE + code, .length = 0x200 }});
        install(state);
        state.block_jit_enabled = true;
        state.block_jit_hot_threshold = 1;
        state.regs.rsp = MEM_BASE + 0x7f000;
        state.regs.rflags = 0x2;
        return .{ .state = state };
    }

    fn deinit(self: Fixture) void {
        self.state.setParallelGuestExecution(false);
        self.state.deinit();
        t.allocator.destroy(self.state);
    }

    fn block(self: Fixture, rip: u64) *block_jit.Block {
        return self.state.blockJitFindValidSlot(self.state.block_jit.?, rip).?.block;
    }

    fn run(self: Fixture, start: u64, stop: u64, passes: u64) !void {
        self.state.regs.rip = start;
        self.state.regs.r8 = passes;
        var steps: usize = 0;
        while (self.state.regs.rip != stop and !self.state.terminated) : (steps += 1) {
            _ = self.state.step();
            try t.expect(steps < 10_000_000);
        }
        try t.expectEqual(stop, self.state.regs.rip);
        try t.expectEqual(@as(u64, MEM_BASE + 0x7f000), self.state.regs.rsp);
    }

    /// Whether `from` has a way naming `rip` whose branch enters `to`.
    fn wayLinked(self: Fixture, from: *block_jit.Block, rip: u64, to: *block_jit.Block) bool {
        for (from.hop.links, 0..) |link, way| {
            if (link.rip == rip) return indirect_links.wayLinked(from, way, to, &self.state.block_jit.?.memory);
        }
        return false;
    }
};

fn useLinks() void {
    direct_links.enabled = true;
    indirect_links.enabled = true;
}

fn resetLinks() void {
    direct_links.enabled = null;
    indirect_links.enabled = null;
}

test "indirect links: a call through a table and returns to two sites run through patched way branches" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    useLinks();
    defer resetLinks();
    const f = try Fixture.init();
    defer f.deinit();
    try f.run(a_rip, exit_rip, 64);
    try t.expectEqual(@as(u64, 64), f.state.regs.rcx);
    try t.expectEqual(@as(u64, 64), f.state.regs.rdx);
    try t.expectEqual(@as(u64, 128), f.state.regs.r9);
    const a = f.block(a_rip);
    const fb = f.block(f_rip);
    // A's `call rax` and F's `ret`, both known only at run time.
    try t.expect(a.links.ways[0] != 0 and fb.links.ways[0] != 0);
    try t.expect(f.wayLinked(a, f_rip, fb));
    try t.expect(f.wayLinked(fb, r1_rip, f.block(r1_rip)));
    try t.expect(f.wayLinked(fb, r2_rip, f.block(r2_rip)));
    const jit = f.state.block_jit.?;
    try t.expect(jit.indirect_patches >= 3);
    // From here on the loop never comes back to the glue for a link.
    const relinks = jit.dispatch_relinks;
    const misses = jit.chain_exits_miss;
    try f.run(a_rip, exit_rip, 1000);
    try t.expectEqual(@as(u64, 1064), f.state.regs.rcx);
    try t.expectEqual(@as(u64, 1064), f.state.regs.rdx);
    try t.expectEqual(@as(u64, 2128), f.state.regs.r9);
    try t.expect(jit.dispatch_relinks <= relinks + 2);
    try t.expect(jit.chain_exits_miss <= misses + 2);
}

test "indirect links: switched off, run-time exits keep the jump-cache-first dispatch with the same results" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    direct_links.enabled = true;
    indirect_links.enabled = false;
    defer resetLinks();
    const f = try Fixture.init();
    defer f.deinit();
    try f.run(a_rip, exit_rip, 300);
    try t.expectEqual(@as(u64, 300), f.state.regs.rcx);
    try t.expectEqual(@as(u64, 600), f.state.regs.r9);
    try t.expectEqual(@as(u32, 0), f.block(f_rip).links.ways[0]);
    try t.expectEqual(@as(u32, 0), f.block(a_rip).links.ways[0]);
    try t.expectEqual(@as(u64, 0), f.state.block_jit.?.indirect_patches);
}

test "indirect links: a dropped return site is never entered through its way branch" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    useLinks();
    defer resetLinks();
    const f = try Fixture.init();
    defer f.deinit();
    try f.run(a_rip, exit_rip, 64);
    const jit = f.state.block_jit.?;
    const fb = f.block(f_rip);
    const found = f.state.blockJitFindValidSlot(jit, r1_rip).?;
    try t.expect(f.wayLinked(fb, r1_rip, found.block));
    jit_glue.dropBlockJitSlot(f.state, jit, found.slot);
    // C takes the dropped block's memory; F's way branch still names R1's
    // old code, whose direct entry is disarmed.
    const c = f.state.compileBlockJit(jit, c_rip).?;
    try t.expectEqual(@intFromPtr(found.block), @intFromPtr(c));
    f.state.regs.rcx = 64;
    try f.run(a_rip, exit_rip, 64);
    // C's `mov ecx, 0xdead` never ran; R1 was compiled again and relinked.
    try t.expectEqual(@as(u64, 128), f.state.regs.rcx);
    try t.expectEqual(@as(u64, 128), f.state.regs.rdx);
    try t.expectEqual(@as(u64, 256), f.state.regs.r9);
    const r1 = f.block(r1_rip);
    try t.expect(r1 != c);
    try t.expect(f.wayLinked(fb, r1_rip, r1));
    I._freeTranslatedBlock(f.state.allocator, c);
}

test "indirect links: rewritten callee bytes and a remote disarm leave through the glue" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    useLinks();
    defer resetLinks();
    const f = try Fixture.init();
    defer f.deinit();
    try f.run(a_rip, exit_rip, 64);
    try t.expect(f.wayLinked(f.block(a_rip), f_rip, f.block(f_rip)));
    // F's `add r9,1` becomes `add r9,2`, through the generation bump a guest
    // store to executable code makes.
    f.state.mem[code + 0x80 + 3] = 0x02;
    guest_memory.bumpWindowsImageCodeGeneration(f.state, f_rip, 4);
    try f.run(a_rip, exit_rip, 64);
    try t.expectEqual(@as(u64, 128 + 256), f.state.regs.r9);
    const fb = f.block(f_rip);
    try t.expect(f.wayLinked(f.block(a_rip), f_rip, fb));
    // Disarmed from another thread: every hop into F leaves for the glue.
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(block: *block_jit.Block) void {
            block.disarmChain();
        }
    }.run, .{fb});
    thread.join();
    const jit = f.state.block_jit.?;
    const relinks = jit.dispatch_relinks;
    try f.run(a_rip, exit_rip, 50);
    try t.expectEqual(@as(u64, 128 + 256 + 200), f.state.regs.r9);
    try t.expectEqual(@as(u64, 178), f.state.regs.rcx);
    try t.expect(jit.dispatch_relinks >= relinks + 50);
}

test "indirect links: a return to more sites than ways keeps four linked and finds the rest in the jump cache" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    useLinks();
    defer resetLinks();
    const f = try Fixture.init();
    defer f.deinit();
    try f.run(p_rip, p_exit, 64);
    try t.expectEqual(@as(u64, 64 * p_sites), f.state.regs.r9);
    const fb = f.block(f_rip);
    var linked: usize = 0;
    for (0..p_sites) |i| {
        const site = p_rip + 5 * (i + 1);
        if (f.wayLinked(fb, site, f.block(site))) linked += 1;
    }
    try t.expectEqual(block_jit.link_ways, linked);
    // Four ways in use: the glue leaves them as they are.
    try t.expectEqual(@as(?usize, null), indirect_links.chooseWay(fb, p_rip + 5 * p_sites));
    const jit = f.state.block_jit.?;
    const patches = jit.indirect_patches;
    const relinks = jit.dispatch_relinks;
    try f.run(p_rip, p_exit, 500);
    try t.expectEqual(@as(u64, 564 * p_sites), f.state.regs.r9);
    try t.expectEqual(patches, jit.indirect_patches);
    try t.expect(jit.dispatch_relinks <= relinks + 2);
}

test "indirect links: a way whose successor has no direct entry goes back to the way's proof" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    useLinks();
    defer resetLinks();
    const f = try Fixture.init();
    defer f.deinit();
    try f.run(a_rip, exit_rip, 8);
    const fb = f.block(f_rip);
    const r1 = f.block(r1_rip);
    var way: usize = 0;
    while (fb.hop.links[way].rip != r1_rip) way += 1;
    try t.expect(indirect_links.wayLinked(fb, way, r1, &f.state.block_jit.?.memory));
    const site: *const u32 = @ptrFromInt(@intFromPtr(fb.code.ptr) + fb.links.ways[way]);
    // A stand-in successor without a direct entry: the branch returns to
    // the way's proof, which reads the way, never into another block.
    const stand_in = .{ .links = direct_links.BlockLinks{}, .code = r1.code };
    _ = indirect_links.linkWay(fb, way, stand_in, &f.state.block_jit.?.memory);
    try t.expect(!indirect_links.wayLinked(fb, way, r1, &f.state.block_jit.?.memory));
    const proof: i64 = @intCast(@intFromPtr(fb.code.ptr) + fb.links.way_proofs[way]);
    try t.expect(direct_links.branchesTo(@intFromPtr(site), proof, &f.state.block_jit.?.memory));
    // A stand-in 512 MiB away with far veneers unavailable: the same.
    direct_links.far_links.link_enabled = false;
    defer direct_links.far_links.link_enabled = true;
    const far_code: [*]const u32 = @ptrFromInt(@intFromPtr(fb.code.ptr) + (512 << 20));
    const far = .{ .links = direct_links.BlockLinks{ .header = 8, .entry = 64 }, .code = far_code[0..32] };
    _ = indirect_links.linkWay(fb, way, far, &f.state.block_jit.?.memory);
    try t.expect(direct_links.branchesTo(@intFromPtr(site), proof, &f.state.block_jit.?.memory));
    try f.run(a_rip, exit_rip, 64);
    try t.expectEqual(@as(u64, 72), f.state.regs.rcx);
    try t.expectEqual(@as(u64, 144), f.state.regs.r9);
}
