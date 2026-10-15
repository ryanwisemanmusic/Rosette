//! Production process reproducer for a PAUSE refusal outliving startup policy.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const f = @import("pause_jit.zig");
const impl = @import("../impl/block_jit.zig");
const std = I._std;
const t = std.testing;
const code = I._MEM_BASE + 0x1000;
fn seed(s: *process.ElfState, bundle: usize, loops: u64) void {
    f.seed(s, loops, 0);
    if (bundle == 8) s.regs.rcx = loops * 8;
}
fn prepare(enabled: bool, bundle: usize) !*process.ElfState {
    const s = try f.create(true, bundle);
    errdefer f.destroy(s);
    if (bundle == 8) {
        // Exact TimerQueue loop tail captured at 0x140130080 in the supplied
        // run: eight F390 hints; ADD ECX,-8; JNZ to the first hint.
        for ([_]u8{ 0x83, 0xC1, 0xF8, 0x75, 0xEB }, 0..) |byte, offset| s.write8(code + 16 + offset, byte);
    }
    // A bounded memory trace may close automatically; ABI diagnosis keeps
    // admission excluded until this fixture's explicit transition.
    s.windows_memory_trace_step_closed.store(false, .monotonic);
    s.diagnose_abi = true;
    seed(s, bundle, 65536);
    _ = try f.run(s, bundle, 65536, false);
    const jit = s.currentBlockJit().?;
    const hot = impl.blockJitHotness(jit, code);
    try t.expect(hot.refused and hot.pause_policy_refused);
    try t.expectEqual(I._block_jit_refusal_retry_limit, hot.retries);
    s.diagnose_abi = false;
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    jit.recheck_pause_policy = enabled;
    return s;
}
test "PAUSE policy recheck revives exhausted startup refusals at the unchanged admission boundary" {
    for ([_]usize{ 1, 8 }) |bundle| {
        const old = try prepare(false, bundle);
        defer f.destroy(old);
        const new = try prepare(true, bundle);
        defer f.destroy(new);
        seed(old, bundle, 2000);
        seed(new, bundle, 2000);
        const a = try f.run(old, bundle, 2000, false);
        const b = try f.run(new, bundle, 2000, false);
        try t.expectEqual(a.retired, b.retired);
        try t.expectEqual(a.yields, b.yields);
        try t.expectEqual(old.regs, new.regs);
        try t.expectEqual(old.windows_guest_threads[3].pause_hints, new.windows_guest_threads[3].pause_hints);
        try t.expectEqual(@as(u64, 0), old.currentBlockJit().?.pause_policy_revived);
        try t.expect(new.currentBlockJit().?.pause_policy_revived > 0);
        try t.expect(new.currentBlockJit().?.pause_helper_calls > 0);
    }
}
test "PAUSE policy recheck refuses cross-check failures other NOPs tracing and clock policy" {
    const s = try prepare(true, 1);
    defer f.destroy(s);
    const jit = s.currentBlockJit().?;
    const hot = impl.blockJitHotness(jit, code);
    const saved = hot.*;
    const retry = @import("../impl/pause_recheck.zig");
    hot.pause_policy_refused = false; // permanent cross-check refusal
    retry.revive(s, jit, hot, code);
    try t.expect(hot.refused);
    hot.* = saved;
    s.diagnose_abi = true;
    retry.revive(s, jit, hot, code);
    try t.expect(hot.refused);
    s.diagnose_abi = false;
    s.windows_memory_trace_step_closed.store(false, .monotonic);
    retry.revive(s, jit, hot, code);
    try t.expect(hot.refused);
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    s.block_jit_verify_memory = true;
    retry.revive(s, jit, hot, code);
    try t.expect(hot.refused);
    s.block_jit_verify_memory = false;
    s.windows_idle_yield.pause_translated_enabled = false;
    retry.revive(s, jit, hot, code);
    try t.expect(hot.refused);
    s.windows_idle_yield.pause_translated_enabled = true;
    s.guest_clock.source = .retired_instructions;
    retry.revive(s, jit, hot, code);
    try t.expect(hot.refused);
    s.guest_clock.source = .host_monotonic;
    s.write8(code, 0x66); // two-byte XCHG/NOP is not PAUSE
    try t.expect(!retry.deferred(s, jit, code));
    retry.revive(s, jit, hot, code);
    try t.expect(hot.refused);
    s.write8(code, 0xF3);
    retry.revive(s, jit, hot, code);
    try t.expect(!hot.refused and !hot.pause_policy_refused);
    try t.expectEqual(@as(u64, 1), jit.pause_policy_revived);
    retry.revive(s, jit, hot, code);
    try t.expectEqual(@as(u64, 1), jit.pause_policy_revived);
}
test "PAUSE policy recheck alternating CPU comparison (ROSETTE_CRITICAL_CPU_BENCH=1)" {
    if (std.c.getenv("ROSETTE_CRITICAL_CPU_BENCH") == null) return error.SkipZigTest;
    for ([_]usize{ 1, 8 }) |bundle| {
        const old = try prepare(false, bundle);
        defer f.destroy(old);
        const new = try prepare(true, bundle);
        defer f.destroy(new);
        // Warm code admitted by the new policy; neither timed side compiles.
        seed(new, bundle, 2000);
        _ = try f.run(new, bundle, 2000, false);
        for (0..7) |pair| {
            var results: [2]@TypeOf(try f.run(old, bundle, 0, false)) = undefined;
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                const s = if (enabled) new else old;
                seed(s, bundle, 100000);
                const start = @import("../impl/worker_cpu.zig").current().?;
                const r = try f.run(s, bundle, 100000, false);
                const cpu = @import("../impl/worker_cpu.zig").current().? - start;
                results[@intFromBool(enabled)] = r;
                std.debug.print("critical_cpu kind=pause pair={d} bundle={d} enabled={} operations={d} retired={d} yields={d} cpu_ns={d} elapsed_ns={d} dispatches={d}\n", .{ pair, bundle, enabled, 100000 * bundle, r.retired, r.yields, cpu, r.elapsed_ns, r.steps });
            }
            try t.expectEqual(results[0].retired, results[1].retired);
            try t.expectEqual(results[0].yields, results[1].yields);
            try t.expectEqual(old.regs, new.regs);
        }
    }
}
