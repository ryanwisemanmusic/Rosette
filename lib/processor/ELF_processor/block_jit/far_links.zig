//! A bounded local island for targets outside B's +/-128 MiB reach.
//! ADRP/ADD/BR forms the address without a data load. Existing successor
//! generation proof, write-back and budgets remain unchanged. Patch only
//! on the owner, outside native execution. Pool/range failure keeps the
//! original shared route. No extra words are emitted in individual blocks.
const a64 = @import("arm64_encode");
pub var enabled: bool = true; // internal compile comparison only
pub var link_enabled: bool = true; // internal same-code comparison only
pub const Patch = struct { word: u32, code: []u32, instructions: [4]u32 };
pub fn instructions(pc: u64, target: u64) ?[4]u32 {
    const pages = @as(i64, @intCast(target >> 12)) - @as(i64, @intCast(pc >> 12));
    if (pages < -(1 << 20) or pages >= (1 << 20)) return null;
    const imm: u21 = @bitCast(@as(i21, @intCast(pages)));
    const adrp = @as(u32, 0x90000010) | (@as(u32, imm & 3) << 29) | (@as(u32, imm >> 2) << 5);
    return .{ adrp, a64.addImm(.x64, 16, 16, @intCast(target & 4095)).?, a64.br(16), a64.nop() };
}
fn branch(at: usize, destination: usize) ?u32 {
    const delta = @as(i64, @intCast(destination)) - @as(i64, @intCast(at));
    if (@mod(delta, 4) != 0 or delta < -(128 << 20) or delta >= 128 << 20) return null;
    return a64.b(@intCast(@divExact(delta, 4)));
}
pub fn current(memory: anytype, at: usize) ?[]u32 {
    const base = @intFromPtr(memory.memory.ptr);
    if (memory.memory.len < 4 or at < base or at - base > memory.memory.len - 4 or at % 4 != 0) return null;
    const word = @atomicLoad(u32, @as(*const u32, @ptrFromInt(at)), .acquire);
    if (word >> 26 != 0b000101) return null;
    const imm: i26 = @bitCast(@as(u26, @truncate(word)));
    const target = @as(i64, @intCast(at)) + @as(i64, imm) * 4;
    if (target < 0) return null;
    return memory.branch_islands.existing(memory.memory, @intCast(target));
}
pub fn plan(memory: anytype, at: usize, target: u64) ?Patch {
    const prior = current(memory, at);
    const code = prior orelse memory.branch_islands.peek(memory.memory, at) orelse return null;
    const words = instructions(@intFromPtr(code.ptr), target) orelse return null;
    const word = branch(at, @intFromPtr(code.ptr)) orelse return null;
    if (prior == null) _ = memory.branch_islands.take(memory.memory, at) orelse return null;
    return .{ .word = word, .code = code, .instructions = words };
}
pub fn pointsTo(memory: anytype, at: usize, target: u64) bool {
    const code = current(memory, at) orelse return false;
    const expected = instructions(@intFromPtr(code.ptr), target) orelse return false;
    for (code, expected) |*word, value| if (@atomicLoad(u32, word, .acquire) != value) return false;
    return true;
}
