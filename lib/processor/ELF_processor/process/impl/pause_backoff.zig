//! After an exact PAUSE scheduling boundary, repeated identical guest state
//! can wait briefly on this worker's epoch. Raw guest writes need no notify:
//! the 100 us requested deadline bounds polling delay (OS scheduling may
//! overshoot). No guest waits, deadlines or synchronization objects change.
const std = @import("std");
const clock = @import("concurrency");
pub const wait_ns: u64 = 100_000;
pub const Counters = struct {
    yields: u64 = 0,
    excluded: u64 = 0,
    resets: u64 = 0,
    parks: u64 = 0,
    wait_ns: u64 = 0,
    max_wait_ns: u64 = 0,
    notified: u64 = 0,
    stopped: u64 = 0,
};
pub const Ledger = struct {
    enabled: bool = true,
    values: [8]std.atomic.Value(u64) = @splat(.init(0)),
    pub fn add(self: *Ledger, c: Counters) void {
        inline for (std.meta.fields(Counters), 0..) |f, i| {
            const n = @field(c, f.name);
            if (i == 5) {
                var old = self.values[i].load(.monotonic);
                while (old < n) old = self.values[i].cmpxchgWeak(old, n, .monotonic, .monotonic) orelse break;
            } else _ = self.values[i].fetchAdd(n, .monotonic);
        }
    }
    pub fn report(self: *const Ledger) void {
        if (self.values[0].load(.acquire) == 0) return;
        std.log.info("PE64 PAUSE BACKOFF: enabled={} yields={d} excluded={d} state_resets={d} parks={d} host_wait_ms={d} max_host_wait_us={d} notified={d} stopped={d} requested_max_us=100; exact PAUSE marker, all GPR/vector/x87 state plus RIP/RSP/frame unchanged for 16 yields and 2 ms; raw writes polled after deadline; not guest wait time", .{ self.enabled, self.values[0].load(.acquire), self.values[1].load(.acquire), self.values[2].load(.acquire), self.values[3].load(.acquire), self.values[4].load(.acquire) / std.time.ns_per_ms, self.values[5].load(.acquire) / 1000, self.values[6].load(.acquire), self.values[7].load(.acquire) });
    }
};
pub const Route = struct {
    site: u64 = 0,
    stack: u64 = 0,
    frame: u64 = 0,
    steps: u64 = 0,
    regs: [17]u64 = @splat(0),
    vector_state: [4096]u8 = @splat(0),
    vector_valid: bool = false,
    last_ns: u64 = 0,
    episode_ns: u64 = 0,
    stable_yields: u32 = 0,
    epoch: ?u32 = null,
    counters: Counters = .{},
    /// Exact private architectural bytes, not a hash. Productive FP/vector
    /// loops cannot qualify merely because their integer registers match.
    pub fn observeVectors(self: *Route, context: anytype) bool {
        comptime {
            var needed: usize = 0;
            for (.{ "xmm", "ymm_hi", "zmm_hi", "k", "x87_stack", "x87_tags", "x87_top", "x87_status", "x87_control" }) |name| {
                if (@hasField(@TypeOf(context.*), name)) needed += @sizeOf(@FieldType(@TypeOf(context.*), name));
            }
            if (needed > 4096) @compileError("PAUSE architectural snapshot exceeds its owned capacity");
        }
        var offset: usize = 0;
        var same = self.vector_valid;
        inline for (.{ "xmm", "ymm_hi", "zmm_hi", "k", "x87_stack", "x87_tags", "x87_top", "x87_status", "x87_control" }) |name| {
            if (@hasField(@TypeOf(context.*), name)) {
                const bytes = std.mem.asBytes(&@field(context.*, name));
                const target = self.vector_state[offset..][0..bytes.len];
                same = same and std.mem.eql(u8, bytes, target);
                @memcpy(target, bytes);
                offset += bytes.len;
            }
        }
        self.vector_valid = true;
        return same;
    }
    pub fn reset(self: *Route) void {
        self.stable_yields = 0;
        self.last_ns = 0;
        self.episode_ns = 0;
        self.epoch = null;
    }
    pub fn observe(self: *Route, site: u64, stack: u64, frame: u64, steps: u64, regs: [17]u64, now: u64) bool {
        self.counters.yields +|= 1;
        const stable = self.last_ns != 0 and now >= self.last_ns and now - self.last_ns <= 200_000 and
            site == self.site and stack == self.stack and frame == self.frame and steps >= self.steps and
            steps - self.steps <= 65_536 and std.mem.eql(u64, &regs, &self.regs);
        if (!stable) {
            if (self.last_ns != 0) self.counters.resets +|= 1;
            self.stable_yields = 0;
            self.episode_ns = now;
        }
        self.site = site;
        self.stack = stack;
        self.frame = frame;
        self.steps = steps;
        self.regs = regs;
        self.last_ns = now;
        self.stable_yields +|= 1;
        return self.stable_yields >= 16 and now -| self.episode_ns >= 2_000_000;
    }
    pub fn park(self: *Route, worker: anytype) void {
        const stamp = clock.monotonicNanoseconds();
        const result = worker.waitForHostBackoff(self.epoch orelse worker.epoch(), stamp +| wait_ns);
        const end = clock.monotonicNanoseconds();
        const elapsed = end -| stamp;
        self.counters.parks +|= 1;
        self.counters.wait_ns +|= elapsed;
        self.counters.max_wait_ns = @max(self.counters.max_wait_ns, elapsed);
        if (result == .changed) {
            self.counters.notified +|= 1;
            self.reset();
        } else if (result == .stopping) {
            self.counters.stopped +|= 1;
            self.reset();
        } else self.last_ns = end; // our own sleep cannot disqualify an episode
    }
    pub fn flush(self: *Route, ledger: *Ledger) void {
        ledger.add(self.counters);
        self.counters = .{};
    }
};

pub fn snapshot(r: anytype) [17]u64 {
    return .{ r.rax, r.rcx, r.rdx, r.rbx, r.rbp, r.rsi, r.rdi, r.r8, r.r9, r.r10, r.r11, r.r12, r.r13, r.r14, r.r15, r.rflags, r.mxcsr };
}

test "PAUSE backoff exact vectors and x87 snapshots see productive floating state" {
    const Context = struct {
        xmm: [32][16]u8 = @splat(@splat(0)),
        ymm_hi: [32][16]u8 = @splat(@splat(0)),
        zmm_hi: [32][32]u8 = @splat(@splat(0)),
        k: [8]u64 = @splat(0),
        x87_stack: [8]f80 = @splat(0),
        x87_tags: [8]bool = @splat(false),
        x87_top: u8 = 0,
        x87_status: u16 = 0,
        x87_control: u16 = 0,
    };
    var context: Context = .{};
    var route: Route = .{};
    try std.testing.expect(!route.observeVectors(&context));
    try std.testing.expect(route.observeVectors(&context));
    inline for (.{ "xmm", "ymm_hi", "zmm_hi", "k", "x87_stack", "x87_tags", "x87_top", "x87_status", "x87_control" }) |name| {
        const bytes = std.mem.asBytes(&@field(context, name));
        bytes[bytes.len - 1] ^= 1;
        try std.testing.expect(!route.observeVectors(&context));
        try std.testing.expect(route.observeVectors(&context));
    }
}

test "PAUSE backoff requires exact quiet state and preserves counters on reset" {
    var route: Route = .{};
    var regs: [17]u64 = @splat(42);
    var now: u64 = 1;
    for (0..16) |n| {
        try std.testing.expect(!route.observe(1, 2, 3, n * 256, regs, now));
        now += 100_000;
    }
    for (16..21) |n| {
        const expected = n == 20;
        try std.testing.expectEqual(expected, route.observe(1, 2, 3, n * 256, regs, now));
        now += 100_000;
    }
    for (0..17) |n| {
        regs[n] += 1;
        try std.testing.expect(!route.observe(1, 2, 3, 6000, regs, now));
        now += 1000;
    }
    const cases = .{ .{ 2, 2, 3, 6000, now }, .{ 2, 3, 3, 6000, now + 1 }, .{ 2, 3, 4, 6000, now + 2 }, .{ 2, 3, 4, 6000 + 65537, now + 3 }, .{ 2, 3, 4, 6000, now + 4 }, .{ 2, 3, 4, 6000, now + 200005 } };
    inline for (cases) |c| try std.testing.expect(!route.observe(c[0], c[1], c[2], c[3], regs, c[4]));
    try std.testing.expect(route.counters.resets >= 23);
    route.reset();
    try std.testing.expectEqual(@as(u64, 44), route.counters.yields);
}
