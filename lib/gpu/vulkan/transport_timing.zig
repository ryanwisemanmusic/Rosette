//! Host costs, not GPU timestamps. Keep frame generation separate from delivery.
const std = @import("std");
const builtin = @import("builtin");

pub const Stage = enum { shadow_upload, queue_submit, readback_inclusive, cpu_capture, wsi_present, present_completion };

/// Reporting only: never sleeps, changes guest time, or drops GPU work.
pub const ReportKind = enum { none, progress, full };
pub const ReportCadence = struct {
    interval_ns: u64 = 5_000_000_000,
    fallback_checks: u64 = 8192,
    emitted: bool = false,
    last_ns: u64 = 0,
    checks_since_report: u64 = 0,
    coalesced_checks: u64 = 0,
    full_reports: u64 = 0,
    progress_reports: u64 = 0,

    pub fn choose(self: *ReportCadence, now: u64, semantic_changed: bool, sample_changed: bool, force: bool, verbose: bool) ReportKind {
        self.checks_since_report +|= 1;
        const kind: ReportKind = if (force or !self.emitted or semantic_changed or (verbose and sample_changed))
            .full
        else if (self.due(now))
            .progress
        else
            .none;
        if (kind == .none) {
            self.coalesced_checks +|= 1;
            return .none;
        }
        self.emitted = true;
        self.last_ns = now;
        self.checks_since_report = 0;
        switch (kind) {
            .full => self.full_reports +|= 1,
            .progress => self.progress_reports +|= 1,
            .none => unreachable,
        }
        return kind;
    }

    fn due(self: *ReportCadence, now: u64) bool {
        // If the host clock fails or moves backwards, rebase once and use a
        // bounded call-count fallback. Clock failure must not mean "dump on
        // every frame", nor silence all subsequent progress forever.
        if (now == 0) return self.checks_since_report >= self.fallback_checks;
        if (self.last_ns == 0 or now < self.last_ns) {
            self.last_ns = now;
            return self.checks_since_report >= self.fallback_checks;
        }
        return now - self.last_ns >= self.interval_ns;
    }
};

/// Discovery must be fair across a multi-swapchain present. One global
/// timer lets an always-uniform first image consume every due slot, leaving
/// the second image's first picture unobserved forever. Bound identities to
/// the forwarding map's sixteen live slots, reusing old history on overflow.
pub const ProbeCadence = struct {
    const Slot = struct { swapchain: u64 = 0, cadence: ReportCadence = .{} };
    slots: [16]Slot = @splat(.{}),
    next_replacement: usize = 0,

    pub fn choose(self: *ProbeCadence, swapchain: u64, now: u64, interval_ns: u64, force: bool) bool {
        if (swapchain == 0) return false;
        var selected: ?*Slot = null;
        var free: ?*Slot = null;
        for (&self.slots) |*slot| {
            if (slot.swapchain == swapchain) {
                selected = slot;
                break;
            }
            if (slot.swapchain == 0 and free == null) free = slot;
        }
        const slot = selected orelse free orelse blk: {
            const replacement = &self.slots[self.next_replacement];
            self.next_replacement = (self.next_replacement + 1) % self.slots.len;
            break :blk replacement;
        };
        if (slot.swapchain != swapchain) slot.* = .{ .swapchain = swapchain };
        slot.cadence.interval_ns = interval_ns;
        return slot.cadence.choose(now, force, false, false, false) != .none;
    }
};

pub fn presentModeLabel(mode: u32) []const u8 {
    return switch (mode) {
        0 => "immediate",
        1 => "mailbox",
        2 => "fifo",
        3 => "fifo_relaxed",
        std.math.maxInt(u32) => "no_live_guest_swapchain",
        else => "other",
    };
}

pub fn pacingLabel(presents: u64, content: u64, fills: u64, mode: u32) []const u8 {
    if (presents == 0) return "not_started";
    if (content != 0) return "content_seen_simulation_speed_unverified";
    if (fills != 0) return if (mode == 0) "fills_only_immediate_not_game_fps" else "fills_only_not_game_fps";
    return "present_without_attributed_write";
}
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
    pub fn activeFpsMilli(self: *const Recent, last: u64, now: u64) u64 {
        if (last == 0 or self.count == 0) return 0;
        const stale_after = @max(@as(u64, 5_000_000_000), (self.total_ns / self.count) *| 4);
        if (now >= last and now - last > stale_after) return 0;
        return self.fpsMilli();
    }
};

/// A picture epoch, not the Vulkan transport counter or an Xbox game clock.
/// Open only on fresh RGB detail from the very image whose native present
/// was accepted and completed. Sampling can miss an earlier picture, so the
/// first ID is explicitly the first OBSERVED picture, never backdated.
pub const PictureSequence = struct {
    pub const Sample = struct { present: u64, swapchain: u64, image: u64, rgb_detail: bool };
    pub const Observation = struct {
        present: u64,
        swapchain: u64,
        image: u64,
        content: bool,
        accepted: bool,
        completed: bool,
        sample: ?Sample = null,
    };
    frames: u64 = 0,
    first_present: u64 = 0,
    first_swapchain: u64 = 0,
    first_image: u64 = 0,
    first_ns: u64 = 0,
    last_ns: u64 = 0,
    last_present: u64 = 0,
    waiting_content: u64 = 0,
    recent: Recent = .{},

    pub fn observe(self: *PictureSequence, observation: Observation, now: u64) bool {
        if (!observation.content or !observation.accepted or !observation.completed or
            observation.present == 0 or observation.swapchain == 0 or observation.image == 0 or
            observation.present <= self.last_present) return false;
        const opening = self.frames == 0;
        if (opening) {
            const sample = observation.sample orelse {
                self.waiting_content +|= 1;
                return false;
            };
            if (!sample.rgb_detail or sample.present != observation.present or
                sample.swapchain != observation.swapchain or sample.image != observation.image)
            {
                self.waiting_content +|= 1;
                return false;
            }
            self.first_present = observation.present;
            self.first_swapchain = observation.swapchain;
            self.first_image = observation.image;
            self.first_ns = now;
        }
        self.frames +|= 1;
        self.last_present = observation.present;
        // Missing clocks cannot prevent numbering; a clock reset must not
        // manufacture an interval spanning unrelated time domains.
        if (now == 0 or (self.last_ns != 0 and now < self.last_ns)) self.recent = .{};
        if (now != 0 and self.last_ns != 0 and now >= self.last_ns) self.recent.note(now - self.last_ns);
        self.last_ns = now;
        return opening;
    }
};
pub const Ledger = struct {
    costs: [std.enums.values(Stage).len]Cost = @splat(.{}),
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

test "fast clear traffic produces bounded progress, not a full report per readback" {
    var cadence = ReportCadence{};
    for (0..17641) |frame| {
        const kind = cadence.choose(1 + @as(u64, @intCast(frame)) * 4_550_000, false, frame % 34 == 0, false, false);
        if (frame == 0) try std.testing.expectEqual(ReportKind.full, kind);
    }
    try std.testing.expectEqual(@as(u64, 1), cadence.full_reports);
    try std.testing.expectEqual(@as(u64, 16), cadence.progress_reports);
    try std.testing.expectEqual(@as(u64, 17624), cadence.coalesced_checks);
    // First content, an actual failure, and exit bypass the periodic budget.
    try std.testing.expectEqual(ReportKind.full, cadence.choose(80_300_000_000, true, false, false, false));
    try std.testing.expectEqual(ReportKind.full, cadence.choose(80_300_000_001, true, false, false, false));
    try std.testing.expectEqual(ReportKind.full, cadence.choose(80_300_000_002, false, false, true, false));
}

test "verbose reports retain pixel transitions without changing normal cadence" {
    var cadence = ReportCadence{};
    _ = cadence.choose(1, false, false, false, false);
    try std.testing.expectEqual(ReportKind.none, cadence.choose(2, false, true, false, false));
    try std.testing.expectEqual(ReportKind.full, cadence.choose(3, false, true, false, true));
}

test "missing or regressing host timestamps cannot create a report storm" {
    var cadence = ReportCadence{ .fallback_checks = 4, .interval_ns = 10 };
    try std.testing.expectEqual(ReportKind.full, cadence.choose(100, false, false, false, false));
    try std.testing.expectEqual(ReportKind.none, cadence.choose(50, false, false, false, false));
    try std.testing.expectEqual(ReportKind.none, cadence.choose(0, false, false, false, false));
    try std.testing.expectEqual(ReportKind.none, cadence.choose(0, false, false, false, false));
    try std.testing.expectEqual(ReportKind.progress, cadence.choose(0, false, false, false, false));
    try std.testing.expectEqual(ReportKind.none, cadence.choose(1000, false, false, false, false));
    try std.testing.expectEqual(ReportKind.progress, cadence.choose(1010, false, false, false, false));
}

test "pacing distinguishes immediate fills from content and expired content FPS" {
    try std.testing.expectEqualStrings("fills_only_immediate_not_game_fps", pacingLabel(17641, 0, 17641, 0));
    try std.testing.expectEqualStrings("content_seen_simulation_speed_unverified", pacingLabel(17642, 1, 17641, 0));
    try std.testing.expectEqualStrings("fifo", presentModeLabel(2));
    var recent = Recent{};
    recent.note(33_333_333);
    try std.testing.expect(recent.activeFpsMilli(1_000_000_000, 1_100_000_000) > 29999);
    try std.testing.expectEqual(@as(u64, 0), recent.activeFpsMilli(1_000_000_000, 7_000_000_000));
    try std.testing.expectEqual(@as(u64, 0), recent.activeFpsMilli(0, 1));
}

test "two hundred thousand startup fills do not start picture frame one" {
    var sequence = PictureSequence{};
    for (1..200001) |present| {
        try std.testing.expect(!sequence.observe(.{ .present = present, .swapchain = 10, .image = 20, .content = false, .accepted = true, .completed = true }, present));
    }
    try std.testing.expectEqual(@as(u64, 0), sequence.frames);
    try std.testing.expect(sequence.observe(.{ .present = 200001, .swapchain = 10, .image = 20, .content = true, .accepted = true, .completed = true, .sample = .{ .present = 200001, .swapchain = 10, .image = 20, .rgb_detail = true } }, 600_000_000_000));
    try std.testing.expectEqual(@as(u64, 1), sequence.frames);
    try std.testing.expectEqual(@as(u64, 200001), sequence.first_present);
    try std.testing.expectEqual(@as(usize, 0), sequence.recent.count);
}

test "picture opening requires exact image custody and accepted native completion" {
    var sequence = PictureSequence{};
    var observation = PictureSequence.Observation{ .present = 17, .swapchain = 10, .image = 20, .content = true, .accepted = true, .completed = true };
    try std.testing.expect(!sequence.observe(observation, 1));
    observation.sample = .{ .present = 16, .swapchain = 10, .image = 20, .rgb_detail = true };
    try std.testing.expect(!sequence.observe(observation, 2));
    observation.sample.?.present = 17;
    observation.sample.?.image = 21;
    try std.testing.expect(!sequence.observe(observation, 3));
    observation.sample.?.image = 20;
    observation.sample.?.swapchain = 11;
    try std.testing.expect(!sequence.observe(observation, 4));
    observation.sample.?.swapchain = 10;
    observation.sample.?.rgb_detail = false;
    try std.testing.expect(!sequence.observe(observation, 5));
    observation.sample.?.rgb_detail = true;
    observation.accepted = false;
    try std.testing.expect(!sequence.observe(observation, 6));
    observation.accepted = true;
    observation.completed = false;
    try std.testing.expect(!sequence.observe(observation, 7));
    observation.completed = true;
    try std.testing.expect(sequence.observe(observation, 8));
    // A multi-swapchain batch is one presentation tick, not two frames.
    observation.swapchain = 11;
    observation.image = 21;
    try std.testing.expect(!sequence.observe(observation, 9));
    try std.testing.expectEqual(@as(u64, 1), sequence.frames);
}

test "picture epoch keeps black content fades but excludes later UI fills and failures" {
    var sequence = PictureSequence{};
    var observation = PictureSequence.Observation{ .present = 1, .swapchain = 10, .image = 20, .content = true, .accepted = true, .completed = true, .sample = .{ .present = 1, .swapchain = 10, .image = 20, .rgb_detail = true } };
    try std.testing.expect(sequence.observe(observation, 0));
    observation.present = 2;
    observation.sample = null; // unsampled/black frames are legal after opening
    try std.testing.expect(!sequence.observe(observation, 1_000_000_000));
    try std.testing.expectEqual(@as(u64, 2), sequence.frames);
    observation.present = 3;
    _ = sequence.observe(observation, 1_033_333_333);
    try std.testing.expect(sequence.recent.fpsMilli() >= 30000);
    observation.present = 4;
    observation.content = false;
    _ = sequence.observe(observation, 2_000_000_000);
    observation.present = 5;
    observation.content = true;
    observation.accepted = false;
    _ = sequence.observe(observation, 2_000_000_001);
    try std.testing.expectEqual(@as(u64, 3), sequence.frames);
    observation.present = 6;
    observation.accepted = true;
    _ = sequence.observe(observation, 1); // clock regression does not stop IDs
    try std.testing.expectEqual(@as(u64, 4), sequence.frames);
    try std.testing.expectEqual(@as(usize, 0), sequence.recent.count);
}

test "startup pixel discovery remains bounded and first content bypasses the timer" {
    var cadence = ReportCadence{ .interval_ns = 1_000_000_000 };
    for (1..200001) |present| {
        _ = cadence.choose(1 + present * 5_000_000, present <= 4, false, false, false);
    }
    try std.testing.expectEqual(@as(u64, 4), cadence.full_reports);
    try std.testing.expect(cadence.progress_reports <= 1000);
    // First content must be observable even immediately after a clear probe.
    try std.testing.expectEqual(ReportKind.full, cadence.choose(1_000_000_000_002, true, false, false, false));
}

test "multi-swapchain discovery cannot starve the later content image" {
    var cadence = ProbeCadence{};
    var samples: [2]u64 = .{ 0, 0 };
    for (0..200000) |present| {
        const now = 1 + present * 5_000_000;
        for (0..2) |index| {
            if (cadence.choose(index + 1, now, 250_000_000, false)) samples[index] += 1;
        }
    }
    try std.testing.expectEqual(@as(u64, 4000), samples[0]);
    try std.testing.expectEqual(samples[0], samples[1]);
    try std.testing.expect(!cadence.choose(0, 1_000_000_000_001, 250_000_000, true));
    try std.testing.expect(cadence.choose(2, 1_000_000_000_001, 250_000_000, true));
    // Retired history cannot prevent a newly-created swapchain's first proof.
    for (3..34) |swapchain| try std.testing.expect(cadence.choose(swapchain, 1, 250_000_000, false));
}
