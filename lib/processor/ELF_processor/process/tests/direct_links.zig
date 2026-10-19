//! Direct links (`block_jit/direct_links.zig`) through the production
//! translator and glue: an exit to a known address is patched to branch
//! straight into its successor, and every way a successor can stop being
//! the right code - dropped, its memory reused, its guest bytes rewritten,
//! disarmed from another thread, out of a branch's reach - leaves through
//! the glue with exact guest state.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const ElfState = P.ElfState;
const MEM_BASE = I._MEM_BASE;
const block_jit = I._block_jit;
const direct_links = block_jit.direct_links;
const jit_glue = @import("../impl/block_jit.zig");
const guest_memory = @import("../impl/guest_memory.zig");

const code: usize = 0x100000;
const a_rip = MEM_BASE + code;
const b_rip = MEM_BASE + code + 0x40;
const c_rip = MEM_BASE + code + 0x80;
const d_rip = MEM_BASE + code + 0xC0;
const exit_rip = b_rip + 3 + 3 + 6 + 3;

fn rel32(from: u64, to: u64) [4]u8 {
    return @bitCast(@as(i32, @intCast(@as(i64, @intCast(to)) - @as(i64, @intCast(from)))));
}

/// A: add eax,1 ; jmp B.  B: add ebx,1 ; dec r8 ; jnz A ; cmp rsp,rsp ;
/// jmp $.  C, never on the program's path: mov ecx,0xdead ; jmp $.
fn install(state: *ElfState) void {
    const mem = state.mem;
    const a = code;
    mem[a..][0..3].* = .{ 0x83, 0xC0, 0x01 };
    mem[a + 3] = 0xE9;
    mem[a + 4 ..][0..4].* = rel32(a_rip + 8, b_rip);
    const b = code + 0x40;
    mem[b..][0..3].* = .{ 0x83, 0xC3, 0x01 };
    mem[b + 3 ..][0..3].* = .{ 0x49, 0xFF, 0xC8 };
    mem[b + 6 ..][0..2].* = .{ 0x0F, 0x85 };
    mem[b + 8 ..][0..4].* = rel32(b_rip + 12, a_rip);
    mem[b + 12 ..][0..3].* = .{ 0x48, 0x39, 0xE4 };
    mem[b + 15 ..][0..2].* = .{ 0xEB, 0xFE };
    const c = code + 0x80;
    mem[c..][0..5].* = .{ 0xB9, 0xAD, 0xDE, 0x00, 0x00 };
    mem[c + 5 ..][0..2].* = .{ 0xEB, 0xFE };
    // D, a second way into B: add edx,1 ; jmp B.
    const d = code + 0xC0;
    mem[d..][0..3].* = .{ 0x83, 0xC2, 0x01 };
    mem[d + 3] = 0xE9;
    mem[d + 4 ..][0..4].* = rel32(d_rip + 8, b_rip);
}

fn setup(state: *ElfState) void {
    state.windows_runtime_enabled = true;
    state.image_low = MEM_BASE + code;
    state.image_high = MEM_BASE + code + 0x100;
    state.configureWindowsExecutableRanges(&[_]I._WindowsExecutableRange{.{ .guest_base = MEM_BASE + code, .length = 0x100 }});
    install(state);
    state.block_jit_enabled = true;
    state.block_jit_hot_threshold = 1;
    state.regs.rsp = MEM_BASE + 0x7f000;
    state.regs.rflags = 0x2;
}

fn runPasses(state: *ElfState, passes: u64) !void {
    state.regs.rip = a_rip;
    state.regs.r8 = passes;
    var steps: usize = 0;
    while (state.regs.rip != exit_rip and !state.terminated) : (steps += 1) {
        _ = state.step();
        try t.expect(steps < 10_000_000);
    }
    try t.expectEqual(exit_rip, state.regs.rip);
}

const Fixture = struct {
    state: *ElfState,

    fn init() !Fixture {
        const state = try t.allocator.create(ElfState);
        state.* = ElfState.init(t.allocator);
        state.setParallelGuestExecution(true);
        setup(state);
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
};

fn headerOf(code_ptr: [*]const u32, offset: u32) *const direct_links.Header {
    return @ptrFromInt(@intFromPtr(code_ptr) + offset);
}

/// The word a header's pointer names (`chain_never_word` once disarmed;
/// copies of that constant can sit at different addresses).
fn headerWord(code_ptr: [*]const u32, offset: u32) u64 {
    return @as(*const u64, @ptrFromInt(headerOf(code_ptr, offset).gen_ptr)).*;
}

test "direct links: a two-block loop runs through patched branches with exact results" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    direct_links.enabled = true;
    defer direct_links.enabled = null;
    const f = try Fixture.init();
    defer f.deinit();
    try runPasses(f.state, 64);
    try t.expectEqual(@as(u64, 64), f.state.regs.rax);
    try t.expectEqual(@as(u64, 64), f.state.regs.rbx);
    const jit = f.state.block_jit.?;
    const a = f.block(a_rip);
    const b = f.block(b_rip);
    // A's jmp and B's taken jnz both branch straight into their successor.
    try t.expect(jit.direct_patches >= 2);
    try t.expect(direct_links.linked(a, b_rip, b));
    try t.expect(direct_links.linked(b, a_rip, a));
    try t.expect(a.links.count >= 1 and b.links.count >= 2);
    // Armed headers name their blocks and the generation they were proven at.
    const hb = headerOf(b.code.ptr, b.links.header);
    try t.expectEqual(@intFromPtr(b), hb.block);
    try t.expectEqual(@intFromPtr(b.hop.gen_ptr), hb.gen_ptr);
    try t.expectEqual(b.hop.generation, hb.generation);
    // From here on the loop never comes back to the glue for a link.
    const relinks = jit.dispatch_relinks;
    const hops = jit.native_chain_hops;
    try runPasses(f.state, 1000);
    try t.expectEqual(@as(u64, 1064), f.state.regs.rax);
    try t.expectEqual(@as(u64, 1064), f.state.regs.rbx);
    try t.expect(jit.native_chain_hops >= hops + 1990);
    try t.expect(jit.dispatch_relinks <= relinks + 2);
    try t.expectEqual(@as(u64, 0), jit.direct_far);
}

test "direct links: switched off, exits stay on the shared path with the same results" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    direct_links.enabled = false;
    defer direct_links.enabled = null;
    const f = try Fixture.init();
    defer f.deinit();
    try runPasses(f.state, 300);
    try t.expectEqual(@as(u64, 300), f.state.regs.rax);
    try t.expectEqual(@as(u64, 300), f.state.regs.rbx);
    const jit = f.state.block_jit.?;
    try t.expectEqual(@as(u64, 0), jit.direct_patches);
    try t.expect(!direct_links.linked(f.block(a_rip), b_rip, f.block(b_rip)));
    try t.expect(jit.native_chain_hops > 500);
}

test "direct links: a dropped successor's code is never entered through a patched branch" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    direct_links.enabled = true;
    defer direct_links.enabled = null;
    const f = try Fixture.init();
    defer f.deinit();
    try runPasses(f.state, 64);
    const jit = f.state.block_jit.?;
    const a = f.block(a_rip);
    const found_b = f.state.blockJitFindValidSlot(jit, b_rip).?;
    try t.expect(direct_links.linked(a, b_rip, found_b.block));
    const old_code = found_b.block.code.ptr;
    const old_header = found_b.block.links.header;
    jit_glue.dropBlockJitSlot(f.state, jit, found_b.slot);
    // The dropped code's header is disarmed in place; the struct is
    // scrubbed for its next life.
    try t.expectEqual(block_jit.chain_never_word, headerWord(old_code, old_header));
    try t.expectEqual(@as(u32, 0), found_b.block.links.header);
    // C takes the dropped block's memory; A's patched branch still names
    // B's old code.
    const c = f.state.compileBlockJit(jit, c_rip).?;
    try t.expectEqual(@intFromPtr(found_b.block), @intFromPtr(c));
    // The program runs on: the old code's direct entry fails, the glue
    // compiles B again and repatches, and C's `mov ecx` never runs.
    f.state.regs.rcx = 0;
    try runPasses(f.state, 64);
    try t.expectEqual(@as(u64, 128), f.state.regs.rax);
    try t.expectEqual(@as(u64, 128), f.state.regs.rbx);
    try t.expectEqual(@as(u64, 0), f.state.regs.rcx);
    const b_again = f.block(b_rip);
    try t.expect(b_again != c);
    try t.expect(direct_links.linked(a, b_rip, b_again));
    I._freeTranslatedBlock(f.state.allocator, c);
}

test "direct links: rewritten successor bytes are what the next hop runs" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    direct_links.enabled = true;
    defer direct_links.enabled = null;
    const f = try Fixture.init();
    defer f.deinit();
    try runPasses(f.state, 64);
    try t.expect(direct_links.linked(f.block(a_rip), b_rip, f.block(b_rip)));
    // B's `add ebx,1` becomes `add ebx,2`, through the same generation bump
    // a guest store to executable image code makes.
    f.state.mem[code + 0x40 + 2] = 0x02;
    guest_memory.bumpWindowsImageCodeGeneration(f.state, b_rip, 3);
    try runPasses(f.state, 64);
    try t.expectEqual(@as(u64, 128), f.state.regs.rax);
    try t.expectEqual(@as(u64, 64 + 128), f.state.regs.rbx);
    // And again directly linked to the new translation.
    const a = f.block(a_rip);
    const b = f.block(b_rip);
    try t.expect(direct_links.linked(a, b_rip, b));
    try runPasses(f.state, 10);
    try t.expectEqual(@as(u64, 64 + 128 + 20), f.state.regs.rbx);
}

test "direct links: the step budget still returns a directly linked loop to the glue" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    direct_links.enabled = true;
    defer direct_links.enabled = null;
    const f = try Fixture.init();
    defer f.deinit();
    try runPasses(f.state, 100_000);
    try t.expectEqual(@as(u64, 100_000), f.state.regs.rax);
    try t.expectEqual(@as(u64, 100_000), f.state.regs.rbx);
    const jit = f.state.block_jit.?;
    try t.expect(direct_links.linked(f.block(a_rip), b_rip, f.block(b_rip)));
    // 600,000 instructions against a per-step budget of a few thousand.
    try t.expect(jit.chain_exits_budget >= 10);
}

test "direct links: a disarm from another thread stops the direct entry" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    direct_links.enabled = true;
    defer direct_links.enabled = null;
    const f = try Fixture.init();
    defer f.deinit();
    try runPasses(f.state, 64);
    const b = f.block(b_rip);
    try t.expect(direct_links.linked(f.block(a_rip), b_rip, b));
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(block: *block_jit.Block) void {
            block.disarmChain();
        }
    }.run, .{b});
    thread.join();
    try t.expectEqual(block_jit.chain_never_word, headerWord(b.code.ptr, b.links.header));
    // Every hop into B now leaves through the glue, which runs B itself.
    const jit = f.state.block_jit.?;
    const relinks = jit.dispatch_relinks;
    try runPasses(f.state, 50);
    try t.expectEqual(@as(u64, 114), f.state.regs.rax);
    try t.expectEqual(@as(u64, 114), f.state.regs.rbx);
    try t.expect(jit.dispatch_relinks >= relinks + 50);
}

test "direct links: a successor beyond a branch's reach keeps the shared path" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    direct_links.enabled = true;
    defer direct_links.enabled = null;
    const f = try Fixture.init();
    defer f.deinit();
    try runPasses(f.state, 8);
    const a = f.block(a_rip);
    const site = a.links.sites()[0];
    const slot: *const u32 = @ptrFromInt(@intFromPtr(a.code.ptr) + site.offset);
    const before = slot.*;
    // A stand-in successor 512 MiB away: `link` reads only its code
    // address and entry offset.
    const far_code: [*]const u32 = @ptrFromInt(@intFromPtr(a.code.ptr) + (512 << 20));
    const far = .{ .links = direct_links.BlockLinks{ .header = 8, .entry = 64 }, .code = far_code[0..32] };
    for (a.links.sites()) |each| {
        const result = direct_links.link(a, each.rip, far);
        try t.expectEqual(@as(u32, 0), result.patched);
        try t.expect(result.far >= 1);
    }
    try t.expectEqual(before, slot.*);
}

test "direct links: a second predecessor of a linked block gets its own patched branch" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    direct_links.enabled = true;
    defer direct_links.enabled = null;
    const f = try Fixture.init();
    defer f.deinit();
    try runPasses(f.state, 64);
    const b = f.block(b_rip);
    // B is in the thread's jump cache now, linked by A. D's exit finds no
    // way of its own and leaves once for the glue instead of hopping through
    // the jump cache, so it is linked and patched too.
    for (0..4) |_| {
        f.state.regs.rip = d_rip;
        f.state.regs.r8 = 8;
        var steps: usize = 0;
        while (f.state.regs.rip != exit_rip and !f.state.terminated) : (steps += 1) {
            _ = f.state.step();
            try t.expect(steps < 1_000_000);
        }
    }
    try t.expectEqual(@as(u64, 4), f.state.regs.rdx);
    try t.expectEqual(@as(u64, 64 + 32), f.state.regs.rbx);
    const d = f.block(d_rip);
    try t.expect(direct_links.linked(d, b_rip, b));
}
