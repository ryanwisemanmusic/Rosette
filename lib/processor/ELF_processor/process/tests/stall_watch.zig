const std = @import("std");
const process = @import("../../process.zig");
const impl = process.__ProcessInternals._process_impl_block_jit;
const spin = @import("../../diagnostics/guest_spin.zig");
const base = process.__ProcessInternals._MEM_BASE;

test "expired spin watch restores write admission while explicit watches still withhold it" {
    var state = process.ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.block_jit_enabled = true;
    const jit = impl.blockJitActive(&state).?;
    const address = base + 0x20010;
    const epoch = state.spin_watch.epoch.load(.acquire);
    const now = @import("../../diagnostics/monotonic_clock.zig").monotonicNanoseconds();
    _ = state.spin_watch.armForEpochAt(epoch, address, 4, 0, now);
    impl.blockJitTlbConsider(&state, address, 4, true);
    try std.testing.expectEqual(@as(u64, 1), state.block_jit_tlb_bail_traced);
    try std.testing.expectEqual(@as(u64, 0), jit.tlb_fills);
    state.write32(address, 7);
    try std.testing.expectEqual(@as(u64, 1), state.spin_watch.hits[0].load(.acquire));
    state.spin_watch.expire(now + spin.WatchSet.lease_ns);
    impl.blockJitTlbConsider(&state, address, 4, true);
    try std.testing.expect(jit.tlb_fills > 0);
    try std.testing.expectEqual(@as(u64, 1), state.block_jit_tlb_bail_traced);
    state.write32(address, 9);
    try std.testing.expectEqual(@as(u32, 9), state.read32(address));
    try std.testing.expectEqual(@as(u64, 1), state.spin_watch.hits[0].load(.acquire));
    // Only the automatic diagnostic lease expires. An explicit user watch
    // continues to withhold the same page even after that lease ended.
    state.trace_write_address = address;
    impl.blockJitTlbConsider(&state, address, 4, true);
    try std.testing.expectEqual(@as(u64, 2), state.block_jit_tlb_bail_traced);
}

test "spin watch production benchmark compares active and expired leases" {
    if (std.c.getenv("ROSETTE_STALL_WATCH_BENCH") == null) return error.SkipZigTest;
    for ([_]bool{ true, false }) |active| {
        var state = process.ElfState.initWithMemory(std.testing.allocator, 0x80000);
        defer state.deinit();
        // Every run translates the same store / decrement / branch loop.
        const bytes = [_]u8{ 0xC6, 0x43, 0x10, 7, 0x49, 0xFF, 0xCF, 0x75, 0xF7, 0xF4 };
        @memcpy(state.mem[0x1000..][0..bytes.len], &bytes);
        const address = base + 0x20010;
        const epoch = state.spin_watch.epoch.load(.acquire);
        _ = state.spin_watch.armForEpochAt(epoch, address, 1, 0, if (active) std.math.maxInt(u64) - spin.WatchSet.lease_ns else 1);
        if (!active) state.spin_watch.expire(1 + spin.WatchSet.lease_ns);
        state.regs.rbx = base + 0x20000;
        state.regs.rsp = base + 0x40000;
        state.regs.rip = base + 0x1000;
        state.regs.r15 = 2_000_000;
        state.block_jit_enabled = true;
        state.block_jit_hot_threshold = 2;
        const clock = @import("../../diagnostics/monotonic_clock.zig").monotonicNanoseconds;
        const start = clock();
        state.runWithLimit(10_000_000);
        const elapsed = clock() -| start;
        try std.testing.expect(state.terminated);
        try std.testing.expectEqual(@as(u8, 7), state.read8(address));
        try std.testing.expectEqual(@as(u64, 0), state.regs.r15);
        try std.testing.expect(state.block_jit.?.instructions_retired > 0);
        try std.testing.expectEqual(@as(u64, if (active) 2_000_000 else 0), state.spin_watch.hits[0].load(.acquire));
        std.debug.print("STALL WATCH BENCH: active={} stores=2000000 elapsed_ns={} traced_admissions={}\n", .{ active, elapsed, state.block_jit_tlb_bail_traced });
    }
}
