//! Exact metadata and ordinary production import dispatch; CPU callbacks only.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const t = std.testing;
const life = @import("../impl/lifecycle.zig");
const stub_cache = @import("../impl/import_stub_cache.zig");
const site_cache = @import("../impl/import_callsite_cache.zig");
const metadata = @import("../impl/import_metadata.zig");
const base = I._MEM_BASE;
const code = base + 0x1000;
fn create() !*process.ElfState {
    const s = try t.allocator.create(process.ElfState);
    s.* = process.ElfState.init(t.allocator);
    s.windows_runtime_enabled = true;
    s.setParallelGuestExecution(true);
    s.windows_active_guest_thread_slot = 3;
    s.windows_guest_threads[3] = .{ .status = .running, .thread_id = 43 };
    s.trace_windows_memory = true;
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    s.guest_clock.source = .host_monotonic;
    s.image_low = base;
    s.image_high = code + 0x400;
    return s;
}
fn destroy(s: *process.ElfState) void {
    s.setParallelGuestExecution(false);
    s.deinit();
    t.allocator.destroy(s);
}
fn fill(s: *process.ElfState, count: usize) !u64 {
    for (0..count) |n| try t.expect(s.registerWindowsImportStubAt(base + 0x10000 + n * 16, "vulkan-1.dll", "vkCmdDraw"));
    return base + 0x10000 + (count - 1) * 16;
}
test "import metadata stub cache retains interiors live registry ranges and replacement identities" {
    const s = try create();
    defer destroy(s);
    const target = try fill(s, 256);
    const old = stub_cache.enabled;
    defer stub_cache.enabled = old;
    stub_cache.enabled = false;
    const expected = s.windowsImportStubAt(target).?;
    stub_cache.enabled = true;
    try t.expectEqualDeep(expected, s.windowsImportStubAt(target).?);
    try t.expectEqualDeep(expected, s.windowsImportStubAt(target).?);
    try t.expect(s.windowsImportStubAt(target + 1) == null);
    s.windows_dynamic_stub_start = s.windows_stub_count;
    try t.expect(s.windowsImportStubAt(target) == null);
    s.windows_dynamic_stub_start = 0;
    s.windows_stub_storage[255].address += 16;
    try t.expect(s.windowsImportStubAt(target) == null);
    s.windows_stub_storage[255].address = target;
    const other = try create();
    defer destroy(other);
    try t.expect(other.registerWindowsImportStubAt(target, "other.dll", "other"));
    try t.expectEqualStrings("other", other.windowsImportStubAt(target).?.function_name);
    try t.expectEqualStrings("vkCmdDraw", s.windowsImportStubAt(target).?.function_name);
}
fn put(s: *process.ElfState, bytes: []const u8) u64 {
    for (0..15) |i| s.write8(code + i, 0x90);
    for (bytes, 0..) |byte, i| s.write8(code + 15 + i, byte);
    return code + 15 + bytes.len;
}
test "import metadata callsite cache matches the original scan with aliases prefixes targets and mutation" {
    const s = try create();
    defer destroy(s);
    s.regs = .{ .rax = 0x1234, .r12 = 0x5678, .rbx = base + 0x800, .rsp = base + 0x900 };
    s.write64(s.regs.rbx, 0x1234);
    s.write64(s.regs.rsp + 8, 0x1234);
    const programs = [_][]const u8{ &.{ 0xFF, 0xD0 }, &.{ 0x41, 0xFF, 0xD4 }, &.{ 0xFF, 0x13 }, &.{ 0xFF, 0x54, 0x24, 0x08 }, &.{ 0x2E, 0x41, 0xFF, 0xD4 }, &.{ 0x90, 0x90 } };
    for (programs) |bytes| {
        const end = put(s, bytes);
        for (0..3) |_| for ([_]u64{ 0x1234, 0x5678, 0x9999 }) |target| {
            try t.expectEqualDeep(site_cache.legacy(s, end, target), site_cache.find(s, end, target));
        };
    }
    const end = put(s, &.{ 0x41, 0xFF, 0xD4 });
    _ = site_cache.find(s, end, 0x5678);
    s.regs.rax = 0x5678; // shorter overlapping CALL RSP now wins, if it resolves
    s.regs.rsp = 0x5678;
    try t.expectEqualDeep(site_cache.legacy(s, end, 0x5678), site_cache.find(s, end, 0x5678));
    s.write8(end - 1, 0xD0); // changes both the target register and cached bytes
    try t.expectEqualDeep(site_cache.legacy(s, end, 0x5678), site_cache.find(s, end, 0x5678));
    var prefixed: [15]u8 = @splat(0x2E);
    prefixed[12..15].* = .{ 0x41, 0xFF, 0xD4 };
    const long_end = put(s, &prefixed);
    s.regs.rsp = base + 0x900;
    for (0..3) |_| try t.expectEqualDeep(site_cache.legacy(s, long_end, 0x5678), site_cache.find(s, long_end, 0x5678));
    s.diagnose_abi = true;
    try t.expectEqualDeep(site_cache.legacy(s, long_end, 0x5678), site_cache.find(s, long_end, 0x5678));
}
test "import metadata follows bound worker operands and rechecks current memory targets" {
    const s = try create();
    defer destroy(s);
    const end = put(s, &.{ 0xFF, 0x13 });
    var ctx: I._WindowsGuestThreadContext = .{};
    ctx.windows_active_guest_thread_slot = 3;
    ctx.regs.rbx = base + 0x800;
    const prior = I._windows_guest_execution_binding().*;
    I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(s), .context = &ctx };
    defer I._windows_guest_execution_binding().* = prior;
    s.write64(ctx.regs.rbx, 0x1234);
    try t.expect(site_cache.find(s, end, 0x1234) != null);
    s.write64(ctx.regs.rbx, 0x5678);
    try t.expect(site_cache.find(s, end, 0x1234) == null);
    try t.expect(site_cache.find(s, end, 0x5678) != null);
    try t.expectEqualDeep(site_cache.legacy(s, end, 0x5678), site_cache.find(s, end, 0x5678));
}
test "import metadata retains short mapped CALL sites and negative returns" {
    const s = try create();
    defer destroy(s);
    s.write8(base, 0xFF);
    s.write8(base + 1, 0xD0);
    s.regs.rax = 0x1234;
    try t.expect(site_cache.find(s, base + 2, 0x1234) != null);
    try t.expectEqualDeep(site_cache.legacy(s, base + 2, 0x1234), site_cache.find(s, base + 2, 0x1234));
    try t.expect(site_cache.find(s, 1, 0x1234) == null);
    try t.expect(site_cache.find(s, std.math.maxInt(u64), 0x1234) == null);
}
test "import metadata four host readers keep bound operands and private counters" {
    const s = try create();
    defer destroy(s);
    const target = try fill(s, 256);
    const end = put(s, &.{ 0x41, 0xFF, 0xD4 });
    const Reader = struct {
        state: *process.ElfState,
        target: u64,
        end: u64,
        index: usize,
        failed: bool = false,
        counts: metadata.Counts = .{},
        fn execute(r: *@This()) void {
            var ctx: I._WindowsGuestThreadContext = .{};
            ctx.regs.rsp = base + 0x900;
            const old = I._windows_guest_execution_binding().*;
            I._windows_guest_execution_binding().* = .{ .owner = @ptrCast(r.state), .context = &ctx };
            defer I._windows_guest_execution_binding().* = old;
            metadata.reset();
            for (0..1000 + r.index) |n| {
                ctx.regs.r12 = if (n % 2 == 0) r.target else r.target - 16;
                if (r.state.windowsImportStubAt(ctx.regs.r12) == null) r.failed = true;
                const expected = site_cache.legacy(r.state, r.end, ctx.regs.r12);
                const found = site_cache.find(r.state, r.end, ctx.regs.r12);
                if (expected == null or found == null or !std.meta.eql(expected, found)) r.failed = true;
            }
            r.counts = metadata.snapshot();
        }
    };
    var readers: [4]Reader = undefined;
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    errdefer for (threads[0..started]) |thread| thread.join();
    for (&readers, 0..) |*r, i| {
        r.* = .{ .state = s, .target = target - i * 16, .end = end, .index = i };
        threads[i] = try std.Thread.spawn(.{}, Reader.execute, .{r});
        started += 1;
    }
    for (threads) |thread| thread.join();
    started = 0;
    for (readers, 0..) |r, i| {
        try t.expect(!r.failed);
        try t.expectEqual(@as(u64, 1000 + i), r.counts.stub_lookups);
        try t.expectEqual(@as(u64, 1000 + i), r.counts.callsites);
        try t.expectEqual(@as(u64, 998 + i), r.counts.stub_hits);
        try t.expectEqual(@as(u64, 999 + i), r.counts.callsite_hits);
    }
}
const Sink = struct {
    calls: u64 = 0,
    checksum: u64 = 0,
    fn dispatch(context: ?*anyopaque, state_ptr: *anyopaque, name: [*]const u8, length: usize, direct: u64, is_direct: c_int) callconv(.c) c_int {
        const sink: *Sink = @ptrCast(@alignCast(context.?));
        const s: *process.ElfState = @ptrCast(@alignCast(state_ptr));
        std.debug.assert(std.mem.eql(u8, name[0..length], "vkCmdDraw"));
        const return_rip = if (is_direct != 0) blk: {
            std.debug.assert(direct == code + 3 or direct == code + 6);
            break :blk direct;
        } else blk: {
            std.debug.assert(direct == 0);
            break :blk s.pop();
        };
        const regs = life.guestContextField(s, "regs");
        sink.calls += 1;
        sink.checksum +%= regs.rcx ^ regs.rdx ^ regs.r8 ^ regs.r9;
        regs.rip = return_rip;
        return 1;
    }
};
fn cpu() u64 {
    return @import("../impl/worker_cpu.zig").current().?;
}
fn run(s: *process.ElfState, target: u64, memory: bool, count: u64, sink: *Sink) !u64 {
    s.regs = .{ .rip = code, .rsp = base + 0x80000, .r12 = target, .rbx = count, .rcx = 17, .rdx = 19, .r8 = 23, .r9 = 29, .rflags = 0x246 };
    s.write64(base + 0x800, target);
    sink.* = .{};
    var random = std.Random.DefaultPrng.init(0x1234);
    for (&s.xmm) |*v| random.random().bytes(v);
    for (&s.ymm_hi) |*v| random.random().bytes(v);
    for (&s.zmm_hi) |*v| random.random().bytes(v);
    const xmm = s.xmm;
    const ymm = s.ymm_hi;
    const zmm = s.zmm_hi;
    const sentinel = code + @as(u64, if (memory) 11 else 8);
    const start = cpu();
    var retired: u64 = 0;
    var calls: u64 = 0;
    while (s.regs.rip != sentinel and calls < count * 10 + 100) : (calls += 1) {
        try t.expect(s.step());
        retired += s.step_retired;
    }
    const duration = cpu() - start;
    try t.expectEqual(sentinel, s.regs.rip);
    try t.expectEqual(count, sink.calls);
    try t.expectEqual((@as(u64, 17) ^ 19 ^ 23 ^ 29) * count, sink.checksum);
    try t.expectEqual(base + 0x80000, s.regs.rsp);
    try t.expectEqual(@as(u64, 0), s.regs.rbx);
    try t.expectEqual(@as(u64, 0x246), s.regs.rflags);
    // The translated Vulkan call lane completes some calls in place, so
    // those iterations do not step the synthetic import-thunk return. The
    // ordinary thunk route retires that additional step.
    const minimum_retired = 3 * count + 1;
    const maximum_retired = 4 * count + 1;
    try t.expect(retired >= minimum_retired and retired <= maximum_retired);
    try t.expectEqual(xmm, s.xmm);
    try t.expectEqual(ymm, s.ymm_hi);
    try t.expectEqual(zmm, s.zmm_hi);
    return duration;
}
test "import metadata ordinary ABI dispatch comparison (ROSETTE_FRAME_WORK_BENCH=1)" {
    const bench = std.c.getenv("ROSETTE_FRAME_WORK_BENCH") != null;
    const old_stub = stub_cache.enabled;
    const old_site = site_cache.enabled;
    defer stub_cache.enabled = old_stub;
    defer site_cache.enabled = old_site;
    if (bench) std.debug.print("frame_work retained_stub_bytes={d} retained_callsite_bytes={d}\n", .{ stub_cache.retained_bytes, site_cache.retained_bytes });
    for ([_]usize{ 64, 1024, 4096 }) |size| for ([_]bool{ false, true }) |memory| {
        const s = try create();
        defer destroy(s);
        const target = try fill(s, size);
        var sink: Sink = .{};
        s.windows_graphics.hooks.native_context = &sink;
        s.windows_graphics.hooks.native_vulkan_dispatch = Sink.dispatch;
        var program = if (memory) [_]u8{ 0xFF, 0x15, 0, 0, 0, 0, 0x48, 0xFF, 0xCB, 0x75, 0xF5, 0xEB, 0xFE } else [_]u8{ 0x41, 0xFF, 0xD4, 0x48, 0xFF, 0xCB, 0x75, 0xF8, 0xEB, 0xFE, 0x90, 0x90, 0x90 };
        if (memory) std.mem.writeInt(i32, program[2..6], @intCast(@as(i64, @intCast(base + 0x800)) - @as(i64, @intCast(code + 6))), .little);
        for (program, 0..) |byte, i| s.write8(code + i, byte);
        s.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = program.len }});
        _ = try run(s, target, memory, if (bench) 2048 else 32, &sink);
        for (0..if (bench) @as(usize, 7) else 1) |pair| {
            var expected: ?I._ElfRegs = null;
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                stub_cache.enabled = enabled;
                site_cache.enabled = enabled;
                _ = try run(s, target, memory, 32, &sink);
                const compiled = s.currentBlockJit().?.compiled;
                metadata.reset();
                const n: u64 = if (bench) 100000 else 32;
                const ns = try run(s, target, memory, n, &sink);
                try t.expectEqual(compiled, s.currentBlockJit().?.compiled);
                if (expected) |regs| try t.expectEqualDeep(regs, s.regs) else expected = s.regs;
                const stats = metadata.snapshot();
                if (bench) std.debug.print("frame_work kind=dispatch pair={d} size={d} memory={} enabled={} calls={d} cpu_ns={d} retired={d} stub_hits={d} scanned={d} site_hits={d} rebuilds={d}\n", .{ pair, size, memory, enabled, n, ns, n * 4 + 1, stats.stub_hits, stats.stub_scanned, stats.callsite_hits, stats.callsite_rebuilds });
            }
        }
    };
}
