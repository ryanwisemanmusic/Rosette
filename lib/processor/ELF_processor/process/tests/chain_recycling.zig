//! Chain links name the block they hop to (`block_jit.Link`), so a block's
//! memory must only ever hold a block (`block_jit/block_recycler.zig`). These
//! tests run real translated chains through the production glue and check
//! the two cases that matter: a dropped successor is never entered through
//! a stale link, and memory reused for another address is never entered for
//! the old one.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const ElfState = P.ElfState;
const MEM_BASE = I._MEM_BASE;
const jit_glue = @import("../impl/block_jit.zig");

const code: usize = 0x100000;
const a_rip = MEM_BASE + code;
const b_rip = MEM_BASE + code + 0x40;
const c_rip = MEM_BASE + code + 0x80;
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
        try t.expect(steps < 1_000_000);
    }
    try t.expectEqual(exit_rip, state.regs.rip);
}

fn linkTo(block: *const I._block_jit.Block, rip: u64) ?usize {
    for (block.hop.links) |link| if (link.rip == rip) return link.block;
    return null;
}

test "chain recycling: a dropped successor is never entered through a stale link" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.init(t.allocator);
    defer state.deinit();
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    setup(&state);
    try runPasses(&state, 64);
    try t.expectEqual(@as(u64, 64), state.regs.rax);
    try t.expectEqual(@as(u64, 64), state.regs.rbx);
    const jit = state.block_jit.?;
    try t.expect(jit.native_chain_hops > 0);
    const a = state.blockJitFindValidSlot(jit, a_rip).?.block;
    const found_b = state.blockJitFindValidSlot(jit, b_rip).?;
    // A's link names B's block itself, not a table slot.
    try t.expectEqual(@intFromPtr(found_b.block), linkTo(a, b_rip).?);

    jit_glue.dropBlockJitSlot(&state, jit, found_b.slot);
    const dropped = found_b.block;
    try t.expectEqual(@as(u64, 1), jit.recycler.recycled);
    try t.expectEqual(@as(u64, 0), dropped.hop.rip);
    // A hop into it loads a generation word no generation equals.
    try t.expectEqual(I._block_jit.chain_never_word, dropped.hop.gen_ptr.*);
    try t.expect(dropped.hop.gen_ptr.* != dropped.hop.generation);

    // C takes the dropped block's memory; A still names that memory for B.
    const c = state.compileBlockJit(jit, c_rip).?;
    try t.expectEqual(@intFromPtr(dropped), @intFromPtr(c));
    try t.expectEqual(@as(u64, 1), jit.recycler.reused);
    try t.expectEqual(c_rip, c.hop.rip);
    try t.expectEqual(@intFromPtr(c), linkTo(a, b_rip).?);

    // The program runs on: A's hop to B fails C's address comparison, the
    // glue compiles B again and relinks, and C's `mov ecx` never runs.
    state.regs.rcx = 0;
    try runPasses(&state, 64);
    try t.expectEqual(@as(u64, 128), state.regs.rax);
    try t.expectEqual(@as(u64, 128), state.regs.rbx);
    try t.expectEqual(@as(u64, 0), state.regs.rcx);
    const b_again = state.blockJitFindValidSlot(jit, b_rip).?.block;
    try t.expect(b_again != c);
    try t.expectEqual(@intFromPtr(b_again), linkTo(a, b_rip).?);
    I._freeTranslatedBlock(state.allocator, c);
    try t.expectEqual(@as(u64, 0), jit.recycler.leaked);
}

test "chain recycling: memory reused for the same address is the block a hop enters" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.init(t.allocator);
    defer state.deinit();
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    setup(&state);
    try runPasses(&state, 16);
    const jit = state.block_jit.?;
    const found_b = state.blockJitFindValidSlot(jit, b_rip).?;
    jit_glue.dropBlockJitSlot(&state, jit, found_b.slot);
    // The glue compiles B again into the recycled memory: A's link names it
    // again without being rewritten, and the hop enters it.
    try runPasses(&state, 16);
    const b_again = state.blockJitFindValidSlot(jit, b_rip).?.block;
    try t.expectEqual(@intFromPtr(found_b.block), @intFromPtr(b_again));
    const hops_before = jit.native_chain_hops;
    try runPasses(&state, 64);
    try t.expectEqual(@as(u64, 96), state.regs.rax);
    try t.expectEqual(@as(u64, 96), state.regs.rbx);
    try t.expect(jit.native_chain_hops >= hops_before + 64);
    try t.expectEqual(@as(u64, 0), jit.recycler.leaked);
}
