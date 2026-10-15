//! Production CPU paths only; no emulator, native driver or GPU work.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const protection = @import("../../guest_page_protection.zig");
const words = @import("../../protection_words.zig");
const wait = @import("../../wait_cost.zig");
const signals = @import("../../wait_signal_index.zig");
fn cpu() u64 {
    var stamp: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &stamp) == 0);
    return @as(u64, @intCast(stamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(stamp.nsec));
}
fn bench() bool {
    return std.c.getenv("ROSETTE_THROUGHPUT_BENCH") != null;
}
fn pairs() usize {
    return if (bench()) 7 else 1;
}
fn order(pair: usize) [2]bool {
    return if (pair % 2 == 0) .{ false, true } else .{ true, false };
}

test "CPU throughput packed page updates match original pagewise table and counters" {
    const saved = words.enabled;
    defer words.enabled = saved;
    var a: protection.Table = .{};
    defer a.deinit(t.allocator);
    var b: protection.Table = .{};
    defer b.deinit(t.allocator);
    var random = std.Random.DefaultPrng.init(0xC0212026);
    for (0..700) |n| {
        const chunk: u64 = if (n % 17 == 0) 0x10000000 - 0x10000 else 0;
        const start = chunk + random.random().uintLessThan(u64, 128) * 4096 + n % 4096;
        const size = 1 + random.random().uintLessThan(u64, 96 * 4096);
        const value: protection.Protection = @enumFromInt(random.random().uintLessThan(u2, 3));
        words.enabled = false;
        const old = a.set(t.allocator, start, size, value);
        words.enabled = true;
        const new = b.set(t.allocator, start, size, value);
        try t.expectEqualDeep(old, new);
        try t.expectEqualDeep(a.stats(), b.stats());
        for (0..256) |i| try t.expectEqual(a.get(chunk + i * 4096), b.get(chunk + i * 4096));
        try t.expectEqualDeep(a.restricted_in_chunk, b.restricted_in_chunk);
    }
    for ([_]u64{ 0, 1, 31, 32, 33, 65535, 65536, (protection.window_end >> 12) - 1, protection.window_end >> 12 }) |page| {
        words.enabled = false;
        const old = a.set(t.allocator, page * 4096, 33 * 4096, .no_access);
        words.enabled = true;
        const new = b.set(t.allocator, page * 4096, 33 * 4096, .no_access);
        try t.expectEqualDeep(old, new);
        try t.expectEqualDeep(a.stats(), b.stats());
    }
}
test "CPU throughput same-page and crossing protection decisions remain exact" {
    var table: protection.Table = .{};
    defer table.deinit(t.allocator);
    _ = table.set(t.allocator, 0x1000, 4096, .read_only);
    _ = table.set(t.allocator, 0x2000, 4096, .no_access);
    const saved = words.same_page;
    defer words.same_page = saved;
    for ([_]u64{ 0, 0xFF0, 0xFFF, 0x1000, 0x1FF0, 0x1FFF, 0x2000, 0x2FFF, 0x3000, std.math.maxInt(u64) - 4 }) |address| {
        for ([_]u8{ 1, 2, 4, 8, 16, 64, 255 }) |width| for ([_]bool{ false, true }) |write| {
            words.same_page = false;
            const old = table.faults(address, width, write);
            words.same_page = true;
            try t.expectEqual(old, table.faults(address, width, write));
        };
    }
}
fn checkLedgers(a: *const wait.Ledger, b: *const wait.Ledger) !void {
    try t.expectEqualDeep(a.sites, b.sites);
    try t.expectEqual(a.count, b.count);
    try t.expectEqual(a.dropped_sites, b.dropped_sites);
    try t.expectEqual(a.dropped_events, b.dropped_events);
    try t.expectEqual(a.unmatched_signals, b.unmatched_signals);
}
test "CPU throughput signal index preserves first-key duplicate kinds append reset and evidence" {
    const saved = signals.enabled;
    defer signals.enabled = saved;
    var a: wait.Ledger = .{};
    var b: wait.Ledger = .{};
    var random = std.Random.DefaultPrng.init(0x517A1);
    for (0..10000) |n| {
        const key = random.random().uintLessThan(u64, 100);
        if (n % 409 == 0) {
            a = .{};
            b = .{};
        }
        if (n % 11 == 0) {
            const kind: wait.WaitKind = if (n % 2 == 0) .finite_handle else .condition;
            try t.expectEqual(a.begin(key, kind, n, n * 10, 5), b.begin(key, kind, n, n * 10, 5));
        }
        signals.enabled = false;
        a.signal(key, n, n * 10, .{ .thread_handle = n + 1, .rip = n * 4 });
        signals.enabled = true;
        b.signal(key, n, n * 10, .{ .thread_handle = n + 1, .rip = n * 4 });
        try checkLedgers(&a, &b);
    }
    a = .{};
    b = .{};
    for (0..96) |i| {
        _ = a.begin(i, .condition, i, i, 0);
        _ = b.begin(i, .condition, i, i, 0);
    }
    try t.expectEqual(a.begin(97, .condition, 0, 0, 0), b.begin(97, .condition, 0, 0, 0));
    try checkLedgers(&a, &b);
}
test "CPU throughput table and ledger alternating CPU comparisons" {
    const old_words = words.enabled;
    const old_same = words.same_page;
    const old_signal = signals.enabled;
    defer {
        words.enabled = old_words;
        words.same_page = old_same;
        signals.enabled = old_signal;
    }
    for ([_]usize{ 64, 4096 }) |pages| {
        var table: protection.Table = .{};
        defer table.deinit(t.allocator);
        _ = table.set(t.allocator, 0, pages * 4096, .read_only);
        for (0..pairs()) |pair| for (order(pair)) |enabled| {
            words.enabled = enabled;
            const n: usize = if (bench()) 2048 else 4;
            const start = cpu();
            var changed: u64 = 0;
            for (0..n) |i| changed += table.set(t.allocator, 0, pages * 4096, if (i % 2 == 0) .no_access else .read_only).pages_changed;
            const elapsed = cpu() - start;
            try t.expectEqual(@as(u64, pages * n), changed);
            try t.expectEqual(@as(u64, pages), table.stats().read_only_pages);
            try t.expectEqual(@as(u64, 0), table.stats().no_access_pages);
            if (bench()) std.debug.print("throughput kind=protection pages={d} pair={d} enabled={} operations={d} cpu_ns={d}\n", .{ pages, pair, enabled, n, elapsed });
        };
    }
    var table: protection.Table = .{};
    defer table.deinit(t.allocator);
    _ = table.set(t.allocator, 0x1000, 4096, .read_only);
    for (0..pairs()) |pair| for (order(pair)) |enabled| {
        words.same_page = enabled;
        const n: usize = if (bench()) 1000000 else 32;
        const start = cpu();
        var faults: u64 = 0;
        for (0..n) |i| faults += @intFromBool(table.faults(0x1000 + (i & 1023), 16, true));
        const elapsed = cpu() - start;
        try t.expectEqual(@as(u64, n), faults);
        if (bench()) std.debug.print("throughput kind=same_page pair={d} enabled={} operations={d} cpu_ns={d}\n", .{ pair, enabled, n, elapsed });
    };
    for (0..pairs()) |pair| for (order(pair)) |enabled| {
        signals.enabled = enabled;
        var ledger: wait.Ledger = .{};
        for (0..96) |i| _ = ledger.begin(i, .condition, i, i, 0);
        const n: usize = if (bench()) 100000 else 32;
        const start = cpu();
        for (0..n) |i| ledger.signal(if (i % 5 == 0) 999 else 80 + i % 16, i, i, .{ .rip = i + 1, .thread_handle = 3 });
        const elapsed = cpu() - start;
        try t.expectEqual(@as(u64, (n + 4) / 5), ledger.unmatched_signals);
        var sum: u64 = ledger.unmatched_signals;
        for (ledger.sites) |site| sum += site.signals;
        try t.expectEqual(@as(u64, n), sum);
        if (bench()) std.debug.print("throughput kind=signal_index pair={d} enabled={} operations={d} cpu_ns={d} hits={d} scanned={d}\n", .{ pair, enabled, n, elapsed, ledger.signal_index.hits, ledger.signal_index.scanned });
    };
}

fn create() !*P.ElfState {
    const s = try t.allocator.create(P.ElfState);
    s.* = P.ElfState.init(t.allocator);
    s.windows_runtime_enabled = true;
    s.setParallelGuestExecution(true);
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    return s;
}
fn destroy(s: *P.ElfState) void {
    s.setParallelGuestExecution(false);
    s.deinit();
    t.allocator.destroy(s);
}
fn run(s: *P.ElfState, n: u64) !u64 {
    const base = I._MEM_BASE;
    s.regs = .{ .rip = base + 0x1000, .rsp = base + 0x80000, .rax = @bitCast(@as(f64, 100)), .r12 = base + 0x10000, .rbx = n, .rflags = 0x246 };
    const start = cpu();
    var retired: u64 = 0;
    var steps: u64 = 0;
    while (s.regs.rip != base + 0x100D and steps < n * 12 + 100) : (steps += 1) {
        try t.expect(s.step());
        retired += s.step_retired;
    }
    const elapsed = cpu() - start;
    try t.expectEqual(n * 5 + 1, retired);
    try t.expectEqual(@as(u64, 0), s.regs.rbx);
    try t.expectEqual(base + 0x80000, s.regs.rsp);
    try t.expectEqual(@as(f64, 2), @as(f64, @bitCast(std.mem.readInt(u64, s.xmm[0][0..8], .little))));
    return elapsed;
}
test "CPU throughput full translated log10 call preserves ABI with no timed compilation" {
    const s = try create();
    defer destroy(s);
    const base = I._MEM_BASE;
    try t.expect(s.registerWindowsImportStubAt(base + 0x10000, "api-ms-win-crt-math-l1-1-0.dll", "log10"));
    const program = [_]u8{ 0xC4, 0xE1, 0xF9, 0x6E, 0xC0, 0x41, 0xFF, 0xD4, 0x48, 0xFF, 0xCB, 0x75, 0xF3, 0xEB, 0xFE };
    for (program, 0..) |byte, i| s.write8(base + 0x1000 + i, byte);
    s.configureWindowsExecutableRanges(&.{.{ .guest_base = base + 0x1000, .length = program.len }});
    _ = try run(s, 64);
    for (0..pairs()) |pair| {
        var expected: ?I._ElfRegs = null;
        var vectors: ?@TypeOf(s.xmm) = null;
        for (order(pair)) |enabled| {
            s.windows_fast_math.enabled = enabled;
            _ = try run(s, 32);
            const compiled = s.currentBlockJit().?.compiled;
            const n: u64 = if (bench()) 100000 else 32;
            const elapsed = try run(s, n);
            try t.expectEqual(compiled, s.currentBlockJit().?.compiled);
            if (expected) |regs| try t.expectEqualDeep(regs, s.regs) else expected = s.regs;
            if (vectors) |v| try t.expectEqualDeep(v, s.xmm) else vectors = s.xmm;
            if (bench()) std.debug.print("throughput kind=log10 pair={d} enabled={} operations={d} retired={d} cpu_ns={d}\n", .{ pair, enabled, n, n * 5 + 1, elapsed });
        }
    }
}

test "CPU throughput producer evidence omits only unused locked clock snapshot" {
    const notify = @import("../impl/wait_signal.zig");
    const saved = notify.legacy_clock;
    defer notify.legacy_clock = saved;
    const s = try create();
    defer destroy(s);
    s.windows_active_guest_thread_slot = 3;
    s.windows_guest_threads[3] = .{ .thread_id = 43, .handle = 0x123, .status = .running };
    s.last_instruction_rip = 0xBEEF;
    _ = s.windows_wait_cost.begin(0x44, .condition, 0, 0, 0);
    var old_evidence: ?wait.Site = null;
    for (0..pairs()) |pair| for (order(pair)) |enabled| {
        notify.legacy_clock = !enabled;
        s.windows_wait_cost.sites[0].signals = 0;
        const clock_before = s.guest_clock;
        const n: usize = if (bench()) 100000 else 32;
        const start = cpu();
        for (0..n) |_| @import("../impl/windows_sync.zig").noteWindowsWaitSignal(s, 0x44);
        const elapsed = cpu() - start;
        try t.expectEqualDeep(clock_before, s.guest_clock);
        try t.expectEqual(@as(u64, n), s.windows_wait_cost.sites[0].signals);
        try t.expectEqual(@as(u64, 0x123), s.windows_wait_cost.sites[0].last_signal_thread_handle);
        try t.expectEqual(@as(u64, 0xBEEF), s.windows_wait_cost.sites[0].last_signal_rip);
        if (old_evidence) |expected| try t.expectEqualDeep(expected, s.windows_wait_cost.sites[0]) else old_evidence = s.windows_wait_cost.sites[0];
        if (bench()) std.debug.print("throughput kind=signal_clock pair={d} enabled={} operations={d} cpu_ns={d}\n", .{ pair, enabled, n, elapsed });
    };
}
