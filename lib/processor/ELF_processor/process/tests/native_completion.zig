//! Real decoder, process, interpreter and emitted ARM64 completion comparisons.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const t = std.testing;
const base = I._MEM_BASE;
const code = base + 0x1000;
const data = base + 0x10000;
const Case = enum { cwde, div32, movaps_load, movaps_store, madd };
const cases = [_]Case{ .cwde, .div32, .movaps_load, .movaps_store, .madd };
fn bytes(c: Case) []const u8 {
    return switch (c) {
        .cwde => &.{0x98},
        .div32 => &.{ 0xB8, 0xAB, 0xCD, 0xEF, 0x01, 0x31, 0xD2, 0xF7, 0x33 }, // mov eax; xor edx; div [rbx]
        .movaps_load => &.{ 0x0F, 0x28, 0x03 },
        .movaps_store => &.{ 0x0F, 0x29, 0x03 },
        .madd => &.{ 0xC5, 0xF1, 0xF5, 0xC2 }, // vpmaddwd xmm0,xmm1,xmm2
    };
}
fn op(c: Case) I._Op {
    return switch (c) {
        .cwde => .cwde,
        .div32 => .div_mem32,
        .movaps_load => .movaps_xmm_mem,
        .movaps_store => .movaps_mem_xmm,
        .madd => .vpmaddwd,
    };
}
fn create(c: Case, enabled: bool) !*process.ElfState {
    const s = try t.allocator.create(process.ElfState);
    s.* = process.ElfState.initWithMemory(t.allocator, 0x80000);
    s.image_low = base;
    s.image_high = base + s.mem.len;
    const body = bytes(c);
    const memory = s.guestMemory(code, body.len + 7).?;
    @memcpy(memory[0..body.len], body);
    @memcpy(memory[body.len..][0..3], &[_]u8{ 0x49, 0xFF, 0xCC }); // dec r12
    memory[body.len + 3] = 0x75;
    memory[body.len + 4] = @bitCast(-@as(i8, @intCast(body.len + 5)));
    @memcpy(memory[body.len + 5 ..], &[_]u8{ 0xEB, 0xFE });
    s.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = memory.len }});
    seed(s, 64, 0);
    // Establish the JIT before selecting the differential old policy.
    _ = try run(s, 64);
    const active = s.currentBlockJit().?;
    if (!enabled) {
        @import("../impl/block_jit.zig").resetBlockJit(s, active);
        active.native_completions = false;
        seed(s, 64, 0);
        _ = try run(s, 64);
    }
    return s;
}
fn destroy(s: *process.ElfState) void {
    s.deinit();
    t.allocator.destroy(s);
}
fn seed(s: *process.ElfState, count: u64, salt: u64) void {
    s.regs = .{ .rip = code, .rbx = data, .r12 = count, .rax = 0xABCD_8001 + salt, .rsp = base + 0x40000, .rflags = 0xA57 };
    var random = std.Random.DefaultPrng.init(salt + 117);
    random.random().bytes(s.guestMemory(data, 32).?);
    s.write32(data, 7);
    for (&s.xmm) |*v| random.random().bytes(v);
    for (&s.ymm_hi) |*v| random.random().bytes(v);
    for (&s.zmm_hi) |*v| random.random().bytes(v);
    // Include the only PMADDWD sum overflow: 2 * (-32768 * -32768).
    if (salt == 0) {
        for (0..8) |lane| {
            std.mem.writeInt(u16, s.xmm[1][lane * 2 ..][0..2], 0x8000, .little);
            std.mem.writeInt(u16, s.xmm[2][lane * 2 ..][0..2], 0x8000, .little);
        }
    }
}
const Result = struct { cpu: u64, wall: u64, retired: u64, dispatch: u64 };
fn run(s: *process.ElfState, n: u64) !Result {
    const cpu = @import("../impl/worker_cpu.zig").current().?;
    const wall = I._monotonicNanoseconds();
    var retired: u64 = 0;
    var dispatch: u64 = 0;
    while (s.regs.r12 != 0 and dispatch < n * 8 + 200) : (dispatch += 1) {
        try t.expect(s.step());
        retired += s.step_retired;
    }
    const cpu_elapsed = @import("../impl/worker_cpu.zig").current().? - cpu;
    const elapsed = I._monotonicNanoseconds() - wall;
    try t.expectEqual(@as(u64, 0), s.regs.r12);
    return .{ .cpu = cpu_elapsed, .wall = elapsed, .retired = retired, .dispatch = dispatch };
}
fn equal(a: *process.ElfState, b: *process.ElfState) !void {
    try t.expectEqual(a.regs, b.regs);
    try t.expectEqual(a.xmm, b.xmm);
    try t.expectEqual(a.ymm_hi, b.ymm_hi);
    try t.expectEqual(a.zmm_hi, b.zmm_hi);
    try t.expectEqualSlices(u8, a.guestMemory(data, 32).?, b.guestMemory(data, 32).?);
}
test "native completion five paths match the real interpreter and preserve upper state" {
    for (cases) |c| {
        const native = try create(c, true);
        defer destroy(native);
        const ordinary = try create(c, false);
        defer destroy(ordinary);
        for (0..32) |salt| {
            seed(native, 73, salt);
            seed(ordinary, 73, salt);
            const fall_before = ordinary.currentBlockJit().?.fallback_ops[@intFromEnum(op(c))];
            const a = try run(native, 73);
            const b = try run(ordinary, 73);
            equal(native, ordinary) catch |err| {
                std.debug.print("completion mismatch case={s} salt={d}\n", .{ @tagName(c), salt });
                return err;
            };
            if (c == .madd and salt == 0) for (0..4) |lane| {
                try t.expectEqual(@as(u32, 0x80000000), std.mem.readInt(u32, native.xmm[0][lane * 4 ..][0..4], .little));
            };
            try t.expectEqual(a.retired, b.retired);
            try t.expectEqual(@as(u64, 73), ordinary.currentBlockJit().?.fallback_ops[@intFromEnum(op(c))] - fall_before);
        }
    }
}
test "native completion benchmark equivalent CPU work seven alternating pairs" {
    if (std.c.getenv("ROSETTE_COMPLETION_BENCH") == null) return error.SkipZigTest;
    const count: u64 = 100000;
    for (cases) |c| {
        const before = try create(c, false);
        defer destroy(before);
        const after = try create(c, true);
        defer destroy(after);
        for (0..7) |pair| {
            const order = if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false };
            var results: [2]Result = undefined;
            for (order) |enabled| {
                const s = if (enabled) after else before;
                seed(s, count, pair);
                const falls = s.currentBlockJit().?.fallback_ops[@intFromEnum(op(c))];
                const r = try run(s, count);
                const fallbacks = s.currentBlockJit().?.fallback_ops[@intFromEnum(op(c))] - falls;
                try t.expectEqual(if (enabled) @as(u64, 0) else count, fallbacks);
                results[@intFromBool(enabled)] = r;
                std.debug.print("native_completion case={s} pair={d} enabled={} operations={d} retired={d} fallbacks={d} cpu_ns={d} elapsed_ns={d} dispatches={d}\n", .{ @tagName(c), pair, enabled, count, r.retired, fallbacks, r.cpu, r.wall, r.dispatch });
            }
            try equal(before, after);
            try t.expectEqual(results[0].retired, results[1].retired);
        }
    }
}
