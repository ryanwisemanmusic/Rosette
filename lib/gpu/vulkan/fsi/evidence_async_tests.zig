const std = @import("std");
const async_io = @import("evidence_async.zig");
const evidence = @import("evidence.zig");
const atom = std.atomic.Value;
const words = [_]u32{ 0x07230203, 0x10000, 0, 8, 0, 0x20011, 1 };
const Probe = struct {
    entered: atom(bool) = .init(false),
    permit: atom(bool) = .init(true),
    calls: usize = 0,
    correct: bool = true,
    delay_ns: usize = 0,
    expected: []const u32 = &words,
    fn save(context: ?*anyopaque, job: async_io.Request) evidence.Result {
        const self: *Probe = @ptrCast(@alignCast(context.?));
        self.entered.store(true, .release);
        while (!self.permit.load(.acquire)) std.Thread.yield() catch {};
        if (self.delay_ns != 0) {
            var t: std.c.timespec = .{ .sec = 0, .nsec = @intCast(self.delay_ns) };
            _ = std.c.nanosleep(&t, null);
        }
        const fingerprint = @import("tracker.zig").spirvFingerprint(job.words);
        std.mem.doNotOptimizeAway(fingerprint);
        self.correct = self.correct and fingerprint == @import("tracker.zig").spirvFingerprint(self.expected) and std.mem.eql(u32, self.expected, job.words) and std.mem.eql(u8, job.directory, "/owned-path");
        self.calls += 1;
        return if (job.guest == 999) .failed else .saved;
    }
};
fn request(guest: u64) async_io.Request {
    return .{ .directory = "/owned-path", .guest = guest, .words = &words, .version = .guest };
}
test "FSI evidence async owns source and directory preserves errors and drains explicitly" {
    var probe: Probe = .{ .permit = .init(false) };
    const writer = try async_io.Writer.create(std.testing.allocator, Probe.save, &probe);
    defer writer.destroy();
    var source = words;
    var directory = "/owned-path".*;
    try std.testing.expectEqual(.queued, writer.enqueue(.{ .directory = &directory, .guest = 1, .words = &source, .version = .native }));
    @memset(&source, 0xbaad);
    @memset(&directory, 'x');
    try std.testing.expectEqual(.queued, writer.enqueue(request(999)));
    probe.permit.store(true, .release);
    writer.flush();
    try std.testing.expect(probe.correct);
    try std.testing.expectEqual(@as(usize, 2), probe.calls);
    const s = writer.snapshot();
    try std.testing.expectEqual(@as(u64, 2), s.accepted);
    try std.testing.expectEqual(@as(u64, 1), s.saved);
    try std.testing.expectEqual(@as(u64, 1), s.failures);
    try std.testing.expectEqual(@as(usize, 0), s.pending_bytes);
}
test "FSI evidence async bounded admission and stop cancel backlog and join the active sink" {
    var probe: Probe = .{ .permit = .init(false) };
    const writer = try async_io.Writer.create(std.testing.allocator, Probe.save, &probe);
    defer writer.destroy();
    try std.testing.expectEqual(.queued, writer.enqueue(request(1)));
    while (!probe.entered.load(.acquire)) std.Thread.yield() catch {};
    for (0..async_io.capacity) |i| try std.testing.expectEqual(.queued, writer.enqueue(request(i)));
    try std.testing.expectEqual(.limited, writer.enqueue(request(1)));
    const Stop = struct {
        fn run(w: *async_io.Writer) void {
            w.stop();
        }
    };
    const thread = try std.Thread.spawn(.{}, Stop.run, .{writer});
    while (true) {
        writer.mutex.lock();
        const stopping = writer.stopping;
        writer.mutex.unlock();
        if (stopping) break;
        std.Thread.yield() catch {};
    }
    try std.testing.expectEqual(.stopped, writer.enqueue(request(1)));
    probe.permit.store(true, .release);
    thread.join();
    const s = writer.snapshot();
    try std.testing.expectEqual(@as(u64, async_io.capacity), s.cancelled);
    try std.testing.expectEqual(@as(u64, 1), s.saved);
    try std.testing.expectEqual(@as(usize, 0), s.pending_bytes);
}
test "FSI evidence async declines malformed budget and allocation failures before publication" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, async_io.Writer.create(failing.allocator(), null, null));
    var probe: Probe = .{};
    const writer = try async_io.Writer.create(std.testing.allocator, Probe.save, &probe);
    defer writer.destroy();
    var invalid = request(1);
    invalid.words = &.{};
    try std.testing.expectEqual(.invalid, writer.enqueue(invalid));
    writer.allocator = failing.allocator();
    try std.testing.expectEqual(.failed, writer.enqueue(request(1)));
    failing.fail_index = 1;
    try std.testing.expectEqual(.failed, writer.enqueue(request(1)));
    writer.allocator = std.testing.allocator;
    writer.stats.pending_bytes = async_io.maximum_pending_bytes;
    try std.testing.expectEqual(.limited, writer.enqueue(request(1)));
    writer.stats.pending_bytes = 0;
    writer.stats.accepted_bytes = evidence.maximum_run_bytes;
    try std.testing.expectEqual(.limited, writer.enqueue(request(1)));
    writer.stats.accepted_bytes = 0;
    try std.testing.expectEqual(@as(u64, 0), writer.snapshot().accepted);
}
extern "c" fn mkdtemp(template: [*:0]u8) ?[*:0]u8;
extern "c" fn rmdir(path: [*:0]const u8) c_int;
extern "c" fn unlink(path: [*:0]const u8) c_int;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fread(data: [*]u8, size: usize, count: usize, stream: *anyopaque) usize;
extern "c" fn fclose(stream: *anyopaque) c_int;
test "FSI evidence async writes byte-identical guest and native files with unchanged naming" {
    var name = "/tmp/rosette-async-evidence-XXXXXX".*;
    const dir = mkdtemp(&name) orelse return error.TestUnexpectedResult;
    defer _ = rmdir(dir);
    var path: [512]u8 = undefined;
    const child = try std.fmt.bufPrintZ(&path, "{s}/vulkan-shaders", .{dir});
    defer _ = rmdir(child);
    const writer = try async_io.Writer.create(std.testing.allocator, null, null);
    defer writer.destroy();
    for ([_]evidence.Version{ .guest, .native }) |version| try std.testing.expectEqual(.queued, writer.enqueue(.{ .directory = std.mem.span(dir), .guest = 88, .words = &words, .version = version }));
    writer.flush();
    for ([_]evidence.Version{ .guest, .native }) |version| {
        var buffer: [96]u8 = undefined;
        const basename = try evidence.filename(&buffer, 88, @import("tracker.zig").spirvFingerprint(&words), version);
        var file_buffer: [512]u8 = undefined;
        const file_path = try std.fmt.bufPrintZ(&file_buffer, "{s}/{s}", .{ child, basename });
        defer _ = unlink(file_path);
        const file = fopen(file_path, "rb") orelse return error.TestUnexpectedResult;
        defer _ = fclose(file);
        var bytes: [@sizeOf(@TypeOf(words)) + 1]u8 = undefined;
        try std.testing.expectEqual(@sizeOf(@TypeOf(words)), fread(&bytes, 1, bytes.len, file));
        try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&words), bytes[0..@sizeOf(@TypeOf(words))]);
    }
    try std.testing.expectEqual(@as(u64, 2), writer.snapshot().saved);
}
test "FSI evidence async producer latency benchmark (ROSETTE_EVIDENCE_IO_BENCH=1)" {
    if (std.c.getenv("ROSETTE_EVIDENCE_IO_BENCH") == null) return error.SkipZigTest;
    const payload = try std.testing.allocator.alloc(u32, 32768);
    defer std.testing.allocator.free(payload);
    for (payload, 0..) |*word, i| word.* = @truncate(i *% 31337);
    payload[0] = 0x07230203;
    for ([_]usize{ 0, 20 * std.time.ns_per_ms }) |delay| for (0..7) |pair| for (0..2) |arm| {
        const enabled = (pair + arm) % 2 != 0;
        var probe: Probe = .{ .delay_ns = delay, .expected = payload };
        const writer = try async_io.Writer.create(std.testing.allocator, Probe.save, &probe);
        defer writer.destroy();
        const begin = @import("shader_profile.zig").now();
        for (0..8) |i| {
            var job = request(i);
            job.words = payload;
            if (enabled) try std.testing.expectEqual(.queued, writer.enqueue(job)) else try std.testing.expectEqual(.saved, Probe.save(&probe, job));
        }
        const producer = @import("shader_profile.zig").now() - begin;
        writer.flush();
        const end = @import("shader_profile.zig").now() - begin;
        try std.testing.expectEqual(@as(usize, 8), probe.calls);
        try std.testing.expect(probe.correct);
        std.debug.print("EVIDENCE_IO pair={d} enabled={} producer_ns={d} drained_ns={d} checked={d} delay_ns={d} bytes={d}\n", .{ pair, enabled, producer, end, probe.calls, probe.delay_ns, std.mem.sliceAsBytes(payload).len });
    };
}

test "FSI evidence async concurrent producers publish complete owned snapshots" {
    const Sink = struct {
        count: usize = 0,
        correct: bool = true,
        fn save(raw: ?*anyopaque, job: async_io.Request) evidence.Result {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.correct = self.correct and job.words.len == 64 and job.words[0] == 0x07230203;
            for (job.words[1..]) |word| self.correct = self.correct and word == job.guest;
            self.count += 1;
            return .saved;
        }
    };
    const Producer = struct {
        fn run(writer: *async_io.Writer, id: usize) void {
            for (0..100) |i| {
                const value: u32 = @intCast(id * 100 + i);
                var source: [64]u32 = @splat(value);
                source[0] = 0x07230203;
                const result = writer.enqueue(.{ .directory = "/owned-path", .guest = value, .words = &source, .version = .guest });
                std.debug.assert(result == .queued);
                @memset(&source, 0xbaad);
            }
        }
    };
    var sink: Sink = .{};
    const writer = try async_io.Writer.create(std.testing.allocator, Sink.save, &sink);
    defer writer.destroy();
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, i| thread.* = try std.Thread.spawn(.{}, Producer.run, .{ writer, i });
    for (threads) |thread| thread.join();
    writer.flush();
    try std.testing.expect(sink.correct);
    try std.testing.expectEqual(@as(usize, 400), sink.count);
    try std.testing.expectEqual(@as(u64, 400), writer.snapshot().saved);
}

test "FSI evidence async libc exit joins active IO before library unload" {
    const Driver = struct {
        extern fn atexit(callback: *const fn () callconv(.c) void) c_int;
        extern fn exit(code: c_int) noreturn;
        extern fn _exit(code: c_int) noreturn;
        var writer: ?*async_io.Writer = null;
        fn unload() callconv(.c) void {
            if (writer.?.thread != null) {
                std.debug.print("EVIDENCE_EXIT FAIL: worker still live at unload\n", .{});
                _exit(2);
            }
            std.debug.print("EVIDENCE_EXIT PASS: active IO joined before unload\n", .{});
        }
    };
    const mode = if (std.c.getenv("ROSETTE_EVIDENCE_EXIT_PROBE")) |value| std.mem.span(value) else "";
    var probe: Probe = .{ .delay_ns = 20 * std.time.ns_per_ms };
    if (mode.len != 0 and !std.mem.eql(u8, mode, "wrong-order")) try std.testing.expectEqual(@as(c_int, 0), Driver.atexit(Driver.unload));
    const writer = try async_io.Writer.create(std.testing.allocator, Probe.save, &probe);
    defer writer.destroy();
    Driver.writer = writer;
    try std.testing.expectEqual(.queued, writer.enqueue(request(1)));
    while (!probe.entered.load(.acquire)) std.Thread.yield() catch {};
    if (mode.len != 0) {
        if (std.mem.eql(u8, mode, "wrong-order")) try std.testing.expectEqual(@as(c_int, 0), Driver.atexit(Driver.unload));
        Driver.exit(0);
    }
    writer.stop();
    try std.testing.expect(writer.thread == null);
    try std.testing.expect(probe.correct);
}
