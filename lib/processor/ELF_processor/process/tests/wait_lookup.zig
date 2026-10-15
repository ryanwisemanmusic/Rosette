//! Real wait objects, ordinary NT ABI dispatch and private metadata controls.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const t = std.testing;
const cache = @import("../impl/wait_lookup.zig");
const metadata = @import("../impl/import_metadata.zig");
const base = I._MEM_BASE;
const code = base + 0x1000;
fn create(count: usize) !*process.ElfState {
    const s = try t.allocator.create(process.ElfState);
    s.* = process.ElfState.init(t.allocator);
    s.windows_runtime_enabled = true;
    s.setParallelGuestExecution(true);
    s.windows_active_guest_thread_slot = 3;
    s.windows_guest_threads[3] = .{ .status = .running, .thread_id = 43 };
    s.guest_clock.source = .host_monotonic;
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    for (0..count) |n| s.registerWindowsEvent(0x2000 + n, true, true);
    return s;
}
fn destroy(s: *process.ElfState) void {
    s.setParallelGuestExecution(false);
    s.deinit();
    t.allocator.destroy(s);
}
test "wait lookup cache retains closure reuse owner changes and live readiness" {
    const s = try create(64);
    defer destroy(s);
    const handle = 0x2000 + 63;
    try t.expectEqual(@as(?usize, 63), s.windowsWaitObjectIndex(handle));
    try t.expect(s.windowsWaitObjectSignaled(handle));
    try t.expect(s.resetWindowsWaitObject(handle));
    try t.expect(!s.windowsWaitObjectSignaled(handle));
    try t.expect(s.closeWindowsWaitObject(handle));
    try t.expect(s.windowsWaitObjectIndex(handle) == null);
    s.registerWindowsEvent(handle + 1, false, false);
    try t.expect(s.windowsWaitObjectIndex(handle) == null);
    s.registerWindowsEvent(handle, false, false);
    try t.expectEqual(@as(?usize, 64), s.windowsWaitObjectIndex(handle));
    const other = try create(2);
    defer destroy(other);
    other.registerWindowsEvent(handle, true, false);
    try t.expectEqual(@as(?usize, 2), other.windowsWaitObjectIndex(handle));
    try t.expectEqual(@as(?usize, 64), s.windowsWaitObjectIndex(handle));
    try t.expect(s.windowsWaitObjectIndex(0) == null);
}
fn cpu() u64 {
    return @import("../impl/worker_cpu.zig").current().?;
}
test "wait lookup randomized production table matches original linear policy" {
    const s = try create(474);
    defer destroy(s);
    var prng = std.Random.DefaultPrng.init(17);
    const original = cache.enabled;
    defer cache.enabled = original;
    for (0..10000) |n| {
        const handle = 0x2000 + prng.random().uintLessThan(u64, 540);
        cache.enabled = false;
        const expected = s.windowsWaitObjectIndex(handle);
        cache.enabled = true;
        try t.expectEqual(expected, s.windowsWaitObjectIndex(handle));
        if (n % 101 == 0 and expected != null) {
            _ = s.closeWindowsWaitObject(handle);
            s.registerWindowsEvent(0x2000 + prng.random().uintLessThan(u64, 540), true, false);
        }
    }
}
test "wait lookup four bound host readers share immutable objects not private counters" {
    const s = try create(474);
    defer destroy(s);
    const Reader = struct {
        state: *process.ElfState,
        index: usize,
        failed: bool = false,
        counts: metadata.Counts = .{},
        fn run(r: *@This()) void {
            var ctx: I._WindowsGuestThreadContext = .{};
            ctx.regs.rip = 0xBEEF + r.index;
            const old = I._windows_guest_execution_binding().*;
            I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(r.state), .context = &ctx };
            defer I._windows_guest_execution_binding().* = old;
            metadata.reset();
            const handle = 0x2000 + 473 - r.index;
            for (0..1000 + r.index) |_| if (r.state.windowsWaitObjectIndex(handle) != 473 - r.index) {
                r.failed = true;
            };
            if (ctx.regs.rip != 0xBEEF + r.index) r.failed = true;
            r.counts = metadata.snapshot();
        }
    };
    var readers: [4]Reader = undefined;
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    errdefer for (threads[0..started]) |thread| thread.join();
    for (&readers, 0..) |*r, i| {
        r.* = .{ .state = s, .index = i };
        threads[i] = try std.Thread.spawn(.{}, Reader.run, .{r});
        started += 1;
    }
    for (threads) |thread| thread.join();
    started = 0;
    for (readers, 0..) |r, i| {
        try t.expect(!r.failed);
        try t.expectEqual(@as(u64, 1000 + i), r.counts.wait_lookups);
        try t.expectEqual(@as(u64, 999 + i), r.counts.wait_hits);
    }
}
test "wait lookup full ordinary NT dispatch benchmark (ROSETTE_ROUTING_BENCH=1)" {
    const bench = std.c.getenv("ROSETTE_ROUTING_BENCH") != null;
    const old = cache.enabled;
    defer cache.enabled = old;
    for ([_]usize{ 64, 474, 1800 }) |size| {
        const s = try create(size);
        defer destroy(s);
        const handle = 0x2000 + size - 1;
        for (0..if (bench) @as(usize, 7) else 1) |pair| for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
            cache.enabled = enabled;
            _ = s.windowsWaitObjectIndex(handle);
            metadata.reset();
            const n: u64 = if (bench) 100000 else 32;
            const start = cpu();
            var checksum: u64 = 0;
            for (0..n) |_| checksum +%= s.windowsWaitObjectIndex(handle).?;
            const ns = cpu() - start;
            try t.expectEqual((size - 1) * n, checksum);
            const stats = metadata.snapshot();
            if (bench) std.debug.print("routing kind=wait_lookup pair={d} size={d} enabled={} operations={d} cpu_ns={d} hits={d} scanned={d}\n", .{ pair, size, enabled, n, ns, stats.wait_hits, stats.wait_scanned });
        };
    }
    for ([_][]const u8{ "NtWaitForSingleObject", "NtSetEventBoostPriority" }) |name| {
        const s = try create(474);
        defer destroy(s);
        const handle = 0x2000 + 473;
        const target = base + 0x10000;
        try t.expect(s.registerWindowsImportStubAt(target, "ntdll.dll", name));
        const program = [_]u8{ 0x41, 0xFF, 0xD4, 0x48, 0xFF, 0xCB, 0x75, 0xF8, 0xEB, 0xFE };
        for (program, 0..) |byte, i| s.write8(code + i, byte);
        s.image_low = base;
        s.image_high = code + program.len;
        s.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = program.len }});
        _ = try dispatch(s, handle, target, 64);
        for (0..if (bench) @as(usize, 7) else 1) |pair| {
            var expected: ?I._ElfRegs = null;
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                cache.enabled = enabled;
                _ = try dispatch(s, handle, target, 32);
                metadata.reset();
                const compiled = s.currentBlockJit().?.compiled;
                const n: u64 = if (bench) 100000 else 32;
                const ns = try dispatch(s, handle, target, n);
                try t.expectEqual(compiled, s.currentBlockJit().?.compiled);
                if (expected) |regs| try t.expectEqualDeep(regs, s.regs) else expected = s.regs;
                const stats = metadata.snapshot();
                if (bench) std.debug.print("routing kind={s} pair={d} size=474 enabled={} operations={d} cpu_ns={d} retired={d} hits={d} scanned={d}\n", .{ name, pair, enabled, n, ns, n * 4 + 1, stats.wait_hits, stats.wait_scanned });
            }
        }
    }
}
fn dispatch(s: *process.ElfState, handle: u64, target: u64, n: u64) !u64 {
    s.regs = .{ .rip = code, .rsp = base + 0x80000, .r12 = target, .rbx = n, .rcx = handle, .rflags = 0x246 };
    const before = s.windows_import_calls;
    const start = cpu();
    var retired: u64 = 0;
    var steps: u64 = 0;
    while (s.regs.rip != code + 8 and steps < n * 10 + 100) : (steps += 1) {
        try t.expect(s.step());
        retired += s.step_retired;
    }
    const ns = cpu() - start;
    try t.expectEqual(code + 8, s.regs.rip);
    try t.expectEqual(n, s.windows_import_calls - before);
    try t.expectEqual(n * 4 + 1, retired);
    try t.expectEqual(@as(u64, 0), s.regs.rax);
    try t.expectEqual(@as(u64, 0), s.regs.rbx);
    try t.expectEqual(@as(u64, 0x246), s.regs.rflags);
    try t.expectEqual(base + 0x80000, s.regs.rsp);
    return ns;
}
