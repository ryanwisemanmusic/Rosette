const std = @import("std");
const testing = std.testing;
const core = @import("core.zig");
const fixtures = @import("tests.zig");
const TestHarness = fixtures.TestHarness;
const TestState = fixtures.TestState;
const a64 = core._test_api._a64;
const DecodedInsn = core._test_api._DecodedInsn;
const Op = core._test_api._Op;
const RegId = core._test_api._RegId;
const Size = core._test_api._Size;
const RFL_ZF = core._test_api._RFL_ZF;

fn baseDisp(op: Op, size: Size, reg: RegId, disp: u64) DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = reg, .src_reg = reg, .addr = disp, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx };
}

test "locked compare-exchange retry hint is edge-only and guest-state neutral" {
    var h = try TestHarness.init();
    defer h.deinit();

    var cas = baseDisp(.cmpxchg_mem32_reg32, .bits32, .cl_cx_ecx_rcx, 0);
    cas.lock = true;
    try h.add(0x1000, 3, cas);
    // jnz back to the locked compare-exchange on failure.
    try h.add(0x1003, 2, .{
        .op = .jcc_rel8,
        .cond = .ne,
        .addr = @bitCast(@as(i64, -5)),
    });

    var hinted_failure = TestState{};
    hinted_failure.admitMemory(true, true);
    hinted_failure.regs.rbx = 0x100;
    hinted_failure.regs.rcx = 0x77;
    hinted_failure.regs.rax = 1;
    std.mem.writeInt(u32, hinted_failure.memory[0x100..][0..4], 5, .little);
    const hinted_result = try h.runWith(&hinted_failure, .{ .atomic_retry_yield_enabled = true });
    try testing.expect(std.mem.indexOfScalar(u32, h.block.code, a64.yieldHint()) != null);
    try testing.expectEqual(@as(u32, 2), hinted_result);
    try testing.expectEqual(@as(u64, 0x1000), hinted_failure.regs.rip);
    try testing.expectEqual(@as(u64, 5), hinted_failure.regs.rax);
    try testing.expect(hinted_failure.regs.rflags & RFL_ZF == 0);
    try testing.expectEqual(@as(u32, 5), std.mem.readInt(u32, hinted_failure.memory[0x100..][0..4], .little));

    var baseline_failure = TestState{};
    baseline_failure.admitMemory(true, true);
    baseline_failure.regs.rbx = 0x100;
    baseline_failure.regs.rcx = 0x77;
    baseline_failure.regs.rax = 1;
    std.mem.writeInt(u32, baseline_failure.memory[0x100..][0..4], 5, .little);
    const baseline_result = try h.runWith(&baseline_failure, .{ .atomic_retry_yield_enabled = false });
    try testing.expect(std.mem.indexOfScalar(u32, h.block.code, a64.yieldHint()) == null);
    try testing.expectEqual(hinted_result, baseline_result);
    try testing.expectEqual(hinted_failure.regs, baseline_failure.regs);
    try testing.expectEqualSlices(u8, hinted_failure.memory[0x100..][0..4], baseline_failure.memory[0x100..][0..4]);

    // On a successful CAS, the same translated hint is not executed. The
    // guest-visible register, flag, memory, and completion state still match
    // the differential translation with the hint disabled.
    var hinted_success = TestState{};
    hinted_success.admitMemory(true, true);
    hinted_success.regs.rbx = 0x100;
    hinted_success.regs.rcx = 0x77;
    hinted_success.regs.rax = 1;
    std.mem.writeInt(u32, hinted_success.memory[0x100..][0..4], 1, .little);
    const hinted_success_result = try h.runWith(&hinted_success, .{ .atomic_retry_yield_enabled = true });
    var baseline_success = TestState{};
    baseline_success.admitMemory(true, true);
    baseline_success.regs.rbx = 0x100;
    baseline_success.regs.rcx = 0x77;
    baseline_success.regs.rax = 1;
    std.mem.writeInt(u32, baseline_success.memory[0x100..][0..4], 1, .little);
    const baseline_success_result = try h.runWith(&baseline_success, .{ .atomic_retry_yield_enabled = false });
    try testing.expectEqual(hinted_success_result, baseline_success_result);
    try testing.expectEqual(hinted_success.regs, baseline_success.regs);
    try testing.expectEqualSlices(u8, hinted_success.memory[0x100..][0..4], baseline_success.memory[0x100..][0..4]);
}
