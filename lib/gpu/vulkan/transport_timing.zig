//! Host costs, not GPU timestamps. Keep frame generation separate from delivery.
const std = @import("std");
const builtin = @import("builtin");

pub const Stage = enum { shadow_upload, queue_submit, readback_inclusive, cpu_capture, wsi_present };
pub const Cost = struct {
    calls: u64 = 0,
    total_ns: u64 = 0,
    max_ns: u64 = 0,
    pub fn note(self: *Cost, elapsed: u64) void {
        self.calls +|= 1;
        self.total_ns +|= elapsed;
        self.max_ns = @max(self.max_ns, elapsed);
    }
};
pub const Recent = struct {
    samples: [32]u64 = @splat(0),
    next: usize = 0,
    count: usize = 0,
    total_ns: u64 = 0,
    pub fn note(self: *Recent, duration: u64) void {
        self.total_ns -= self.samples[self.next];
        self.samples[self.next] = duration;
        self.total_ns +|= duration;
        self.next = (self.next + 1) % self.samples.len;
        self.count = @min(self.count + 1, self.samples.len);
    }
    pub fn fpsMilli(self: *const Recent) u64 {
        if (self.total_ns == 0) return 0;
        return @intCast(@min(@as(u128, std.math.maxInt(u64)), @as(u128, self.count) * 1_000_000_000_000 / self.total_ns));
    }
};
pub const Ledger = struct {
    costs: [5]Cost = @splat(.{}),
    first_present_ns: u64 = 0,
    last_present_ns: u64 = 0,
    intervals: Cost = .{},
    recent: Recent = .{},
    first_content_ns: u64 = 0,
    last_content_ns: u64 = 0,
    content_frames: u64 = 0,
    content_recent: Recent = .{},
    pixel_samples: u64 = 0,
    pixel_changes: u64 = 0,
    pixel_unchanged_run: u64 = 0,
    previous_pixel_hash: u64 = 0,
    last_pixel_change_ns: u64 = 0,
    pub fn ingress(self: *Ledger, now: u64) void {
        if (now == 0) return;
        if (self.first_present_ns == 0) self.first_present_ns = now;
        if (self.last_present_ns != 0 and now >= self.last_present_ns) {
            self.intervals.note(now - self.last_present_ns);
            self.recent.note(now - self.last_present_ns);
        }
        self.last_present_ns = now;
    }
    pub fn content(self: *Ledger, now: u64) void {
        if (now == 0) return;
        if (self.first_content_ns == 0) self.first_content_ns = now;
        if (self.last_content_ns != 0 and now >= self.last_content_ns) self.content_recent.note(now - self.last_content_ns);
        self.last_content_ns = now;
        self.content_frames +|= 1;
    }
    pub fn pixels(self: *Ledger, hash: u64, now: u64) void {
        if (self.pixel_samples != 0 and hash != self.previous_pixel_hash) {
            self.pixel_changes +|= 1;
            self.pixel_unchanged_run = 0;
            self.last_pixel_change_ns = now;
        } else if (self.pixel_samples != 0) self.pixel_unchanged_run +|= 1;
        if (self.pixel_samples == 0) self.last_pixel_change_ns = now;
        self.previous_pixel_hash = hash;
        self.pixel_samples +|= 1;
    }
    pub fn finish(self: *Ledger, stage: Stage, started: u64) void {
        const now = nowNs();
        if (started != 0 and now >= started) self.costs[@intFromEnum(stage)].note(now - started);
    }
};
pub fn nowNs() u64 {
    if (builtin.os.tag != .macos and builtin.os.tag != .linux) return 0;
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0 or timestamp.sec < 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) *| 1_000_000_000 +| @as(u64, @intCast(timestamp.nsec));
}
pub fn previewDue(last: u64, now: u64, interval_ns: u64) bool {
    return last == 0 or now == 0 or now < last or now - last >= interval_ns;
}
test "present ingress measures generation gaps independently of driver costs" {
    var ledger = Ledger{};
    ledger.ingress(1_000);
    ledger.ingress(2_000);
    ledger.ingress(12_000);
    ledger.ingress(0);
    try std.testing.expectEqual(@as(u64, 2), ledger.intervals.calls);
    try std.testing.expectEqual(@as(u64, 11_000), ledger.intervals.total_ns);
    try std.testing.expectEqual(@as(u64, 10_000), ledger.intervals.max_ns);
    try std.testing.expectEqual(@as(u64, 0), ledger.costs[@intFromEnum(Stage.wsi_present)].calls);
}
test "preview sampling is wall-clock bounded without dropping guest presents" {
    try std.testing.expect(previewDue(0, 1, 250_000_000));
    try std.testing.expect(!previewDue(1, 10_000_000, 250_000_000));
    try std.testing.expect(previewDue(1, 250_000_001, 250_000_000));
    try std.testing.expect(previewDue(1, 2, 0));
    try std.testing.expect(previewDue(2, 1, 250_000_000));
}
test "recent FPS excludes boot history and content ticks exclude UI clear frames" {
    var ledger = Ledger{};
    ledger.ingress(1);
    ledger.ingress(480_000_000_001);
    ledger.content(480_000_000_001);
    for (1..34) |frame| {
        const now = 480_000_000_001 + @as(u64, @intCast(frame)) * 200_000_000;
        ledger.ingress(now);
        ledger.content(now);
    }
    try std.testing.expectEqual(@as(u64, 5000), ledger.recent.fpsMilli());
    try std.testing.expectEqual(@as(u64, 5000), ledger.content_recent.fpsMilli());
    try std.testing.expectEqual(@as(usize, 32), ledger.recent.count);
    ledger.pixels(0, 1);
    ledger.pixels(0, 2);
    ledger.pixels(10, 3);
    ledger.pixels(10, 4);
    try std.testing.expectEqual(@as(u64, 4), ledger.pixel_samples);
    try std.testing.expectEqual(@as(u64, 1), ledger.pixel_changes);
    try std.testing.expectEqual(@as(u64, 1), ledger.pixel_unchanged_run);
    try std.testing.expectEqual(@as(u64, 3), ledger.last_pixel_change_ns);
}
