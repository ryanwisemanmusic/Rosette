//! Real translated byte-code spin workers plus the production yield route.
//! Raw guest-memory publication and epoch notification are checked separately.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const t = std.testing;
const clock = @import("concurrency");
const workers = @import("parallelism").worker;
const scheduling = @import("../impl/worker_yield.zig");
const pause = @import("../impl/pause_backoff.zig");
const base = I._MEM_BASE;
const code = base + 0x1000;
const data = base + 0x20000;
const atomic = std.atomic.Value;
fn cpuNs() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
fn sleep(ns: u64) void {
    var time: std.c.timespec = .{ .sec = @intCast(ns / std.time.ns_per_s), .nsec = @intCast(ns % std.time.ns_per_s) };
    _ = std.c.nanosleep(&time, null);
}
const Poller = struct {
    state: *process.ElfState,
    worker: workers.Worker = .{},
    route: scheduling.Route = .{},
    ready: atomic(bool) = .init(false),
    go: *atomic(bool),
    received: atomic(u64) = .init(0),
    checksum: u64 = 0,
    retired: u64 = 0,
    cpu_ns: u64 = 0,
    productive: bool = false,
    failed: bool = false,
    fn run(raw: *anyopaque, worker: *workers.Worker) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        const s = self.state;
        const labels = [_][]const u8{ "RENDER (F800010C)", "MAIN_THREAD (F8000014)", "XThread0022", "xe::threading::TimerQueue" };
        self.route.setLabel(labels[worker.slot]);
        for (0..100) |_| {
            s.windows_guest_slice_yield_requested = false;
            s.windows_slice_pause_yield = false;
            if (!s.step()) {
                self.failed = true;
                return;
            }
        }
        self.ready.store(true, .release);
        while (!self.go.load(.acquire)) std.Thread.yield() catch {};
        const stamp = cpuNs();
        while (!worker.shouldStop()) {
            s.windows_guest_slice_yield_requested = false;
            s.windows_slice_pause_yield = false;
            if (!s.step()) {
                self.failed = true;
                break;
            }
            self.retired += s.step_retired;
            const got = s.regs.rbx;
            if (got != self.received.load(.monotonic)) {
                self.checksum +%= got *% 0x9e3779b97f4a7c15;
                self.received.store(got, .release);
            }
            if (self.productive) s.regs.r15 +%= 1;
            if (s.windows_guest_slice_yield_requested) scheduling.handle(s, &s.windows_guest_threads[3], s, worker, &self.route, self.retired, @import("../impl/pause_jit.zig").canBackoff(s, false));
        }
        self.cpu_ns = cpuNs() - stamp;
        self.route.flush(&s.windows_idle_yield);
    }
    fn create(enabled: bool, productive: bool, vector: bool, go: *atomic(bool)) !@This() {
        const s = try t.allocator.create(process.ElfState);
        s.* = process.ElfState.init(t.allocator);
        errdefer {
            s.deinit();
            t.allocator.destroy(s);
        }
        s.parallel_guest_execution = true;
        s.trace_windows_memory = true;
        s.windows_memory_trace_step_closed.store(true, .monotonic);
        s.guest_clock.source = .host_monotonic;
        s.windows_active_guest_thread_slot = 3;
        s.windows_guest_threads[3] = .{ .status = .running, .thread_id = 43 };
        s.windows_idle_yield.pause.enabled = enabled;
        s.image_low = base;
        s.image_high = base + s.mem.len;
        // mov rbx,[rdi]; eight PAUSE hints; jmp loop.
        const program = [_]u8{ 0x48, 0x8B, 0x1F, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xEB, 0xEB };
        const vector_program = [_]u8{ 0x48, 0x8B, 0x1F, 0x66, 0x0F, 0xD4, 0xC1, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0xEB, 0xE7 }; // also PADDQ xmm0,xmm1
        const bytes: []const u8 = if (vector) &vector_program else &program;
        s.xmm[1][0] = 1;
        @memcpy(s.guestMemory(code, bytes.len).?, bytes);
        s.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = bytes.len }});
        s.regs = .{ .rip = code, .rsp = base + 0x40000, .rdi = data, .rflags = 0x246 };
        return .{ .state = s, .productive = productive, .go = go };
    }
    fn destroy(self: *@This()) void {
        self.state.setParallelGuestExecution(false);
        self.state.deinit();
        t.allocator.destroy(self.state);
    }
    fn send(self: *@This(), value: u64) void {
        const pointer: *u64 = @ptrCast(@alignCast(self.state.guestMemory(data, 8).?.ptr));
        @atomicStore(u64, pointer, value, .seq_cst);
    }
};
const Mode = enum { idle, raw, notified, short, productive, vector };
fn sample(mode: Mode, enabled: bool, pair: usize, bench: bool) !void {
    var pollers: [4]Poller = undefined;
    var allocated: usize = 0;
    defer for (pollers[0..allocated]) |*p| p.destroy();
    var started: usize = 0;
    defer for (pollers[0..started]) |*p| {
        p.worker.requestStop();
        p.worker.join();
    };
    var hub: workers.WakeHub = .{};
    var go: atomic(bool) = .init(false);
    defer go.store(true, .release); // release ready workers on setup failure
    for (&pollers, 0..) |*p, n| {
        p.* = try Poller.create(enabled, mode == .productive, mode == .vector, &go);
        allocated += 1;
        try p.worker.start(p, n, &hub, Poller.run);
        started += 1;
    }
    const ready_deadline = clock.monotonicNanoseconds() + 10_000_000_000;
    for (&pollers) |*p| while (!p.ready.load(.acquire)) {
        if (clock.monotonicNanoseconds() > ready_deadline) return error.WarmupStalled;
        std.Thread.yield() catch {};
    };
    const stamp = clock.monotonicNanoseconds();
    go.store(true, .release);
    var latencies: [80]u64 = @splat(0);
    var count: usize = 0;
    if (mode == .idle or mode == .productive or mode == .vector) sleep(if (bench) 120_000_000 else 20_000_000) else {
        for (1..21) |sequence| {
            sleep(if (mode == .short) 200_000 else 5_000_000);
            var stamps: [4]u64 = undefined;
            for (&pollers, 0..) |*p, n| {
                stamps[n] = clock.monotonicNanoseconds();
                p.send(sequence);
                if (mode == .notified) p.worker.notify();
            }
            for (&pollers, 0..) |*p, n| {
                while (p.received.load(.acquire) != sequence) {
                    if (clock.monotonicNanoseconds() - stamps[n] > 2_000_000_000) return error.HandoffStalled;
                    std.Thread.yield() catch {};
                }
                latencies[count] = clock.monotonicNanoseconds() - stamps[n];
                count += 1;
            }
        }
    }
    for (&pollers) |*p| p.worker.requestStop();
    for (&pollers) |*p| p.worker.join();
    started = 0;
    const elapsed = clock.monotonicNanoseconds() - stamp;
    var cpu: u64 = 0;
    var parks: u64 = 0;
    var hints: u64 = 0;
    var max_wait: u64 = 0;
    for (&pollers) |*p| {
        try t.expect(!p.failed);
        try t.expect(p.state.windows_guest_threads[3].parallel_block_jit.?.pause_helper_calls > 0);
        try t.expectEqual(@as(u64, 0x246), p.state.regs.rflags);
        cpu += p.cpu_ns;
        parks += p.state.windows_idle_yield.pause.values[3].load(.acquire);
        hints += p.state.windows_guest_threads[3].pause_hints;
        max_wait = @max(max_wait, p.state.windows_idle_yield.pause.values[5].load(.acquire));
        var checksum: u64 = 0;
        if (count != 0) for (1..21) |n| {
            checksum +%= @as(u64, n) *% 0x9e3779b97f4a7c15;
        };
        try t.expectEqual(checksum, p.checksum);
        if (!enabled or mode == .productive or mode == .vector) try t.expectEqual(@as(u64, 0), p.state.windows_idle_yield.pause.values[3].load(.acquire));
        if (mode == .vector) try t.expect(std.mem.readInt(u64, p.state.xmm[0][0..8], .little) != 0);
    }
    try t.expectEqual(@as(u64, 0), hub.deadline_expiries.load(.acquire));
    try t.expectEqual(@as(u64, 0), hub.timeouts.load(.acquire));
    try t.expect(cpu <= elapsed * 4 + 5_000_000); // all CPU stamps start after the common barrier
    std.mem.sort(u64, latencies[0..count], {}, std.sort.asc(u64));
    if (bench) std.debug.print("pause_workers pair={d} mode={s} enabled={} cpu_ns={d} elapsed_ns={d} parks={d} hints={d} handoffs={d} p95_ns={d} max_ns={d} max_wait_ns={d}\n", .{ pair, @tagName(mode), enabled, cpu, elapsed, parks, hints, count, if (count == 0) 0 else latencies[(count - 1) * 95 / 100], if (count == 0) 0 else latencies[count - 1], max_wait });
}

test "PAUSE worker backoff compares actual translated raw and notified handoffs (ROSETTE_PAUSE_WORKERS_BENCH=1)" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const bench = std.c.getenv("ROSETTE_PAUSE_WORKERS_BENCH") != null;
    for (0..if (bench) @as(usize, 7) else 1) |pair| for (std.enums.values(Mode)) |mode| for (0..2) |order| {
        try sample(mode, (pair + order) % 2 != 0, pair, bench);
    };
}

test "PAUSE worker backoff catches notifications before park and excludes diagnostics" {
    var hub: workers.WakeHub = .{};
    var worker: workers.Worker = .{ .wake_hub = &hub, .slot = 2 };
    var route: pause.Route = .{};
    route.epoch = worker.epoch();
    worker.notify();
    route.park(&worker);
    try t.expectEqual(@as(u64, 1), route.counters.notified);
    try t.expectEqual(@as(u32, 0), route.stable_yields);
    worker.requestStop();
    route.park(&worker);
    try t.expectEqual(@as(u64, 1), route.counters.stopped);
    var go: atomic(bool) = .init(false);
    const s = try Poller.create(true, false, false, &go);
    var p = s;
    defer p.destroy();
    var generic: scheduling.Route = .{};
    p.state.windows_slice_pause_yield = true;
    scheduling.handle(p.state, &p.state.windows_guest_threads[3], p.state, &worker, &generic, 1, false);
    try t.expectEqual(@as(u64, 1), generic.pause_route.counters.excluded);
    try t.expectEqual(@as(u64, 0), generic.pause_route.counters.parks);
}
