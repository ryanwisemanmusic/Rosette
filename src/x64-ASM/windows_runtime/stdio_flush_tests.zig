const std = @import("std");
const flush = @import("stdio_flush.zig");
const t = std.testing;
fn State(comptime File: type) type {
    return struct {
        const Regs = struct { rax: u64 = 0, rcx: u64 = 0x42, rdx: u64 = 0, r8: u64 = 0, r9: u64 = 0, rsp: u64 = 0x2000, rip: u64 = 0 };
        const Slot = struct { guest_handle: u64 = 0, file: ?File = null, standard_stream: ?u8 = null, stdio_commit_on_flush: bool = false };
        regs: Regs = .{},
        worker_regs: Regs = .{},
        worker_error: u32 = 0,
        bound: bool = false,
        windows_files: [4]Slot = @splat(.{}),
        windows_host_io: ?std.Io = std.testing.io,
        windows_last_error: u32 = 0,
        windows_file_failures: u64 = 0,
        windows_stdio_flush_requests: u64 = 0,
        windows_stdio_flush_commits: u64 = 0,
        windows_stdio_flush_elided: u64 = 0,
        windows_commode_storage: u64 = 0,
        diagnose_abi: bool = false,
        word: u32 = 0,
        allocations: u32 = 0,
        pops: u32 = 0,
        pub fn windowsGuestContextField(self: *@This(), comptime field: []const u8) *@FieldType(@This(), field) {
            if (comptime std.mem.eql(u8, field, "regs")) return if (self.bound) &self.worker_regs else &self.regs; // guest_context: owner -- fixture context selector
            if (comptime std.mem.eql(u8, field, "windows_last_error")) return if (self.bound) &self.worker_error else &self.windows_last_error; // guest_context: owner -- fixture context selector
            return &@field(self.*, field);
        }
        pub fn pop(self: *@This()) u64 {
            self.windowsGuestContextField("regs").rsp += 8;
            self.pops += 1;
            return 0xABCD;
        }
        pub fn read64(_: *@This(), _: u64) u64 {
            return 0xABCD;
        }
        pub fn read32(self: *@This(), _: u64) u32 {
            return self.word;
        }
        pub fn write32(self: *@This(), _: u64, value: u32) void {
            self.word = value;
        }
        pub fn guestAlloc(self: *@This(), _: u64, _: u64) ?u64 {
            self.allocations += 1;
            return 0x1000;
        }
    };
}
const SpyFile = struct {
    calls: *u64,
    fail: bool = false,
    pub fn sync(self: @This(), _: std.Io) !void {
        self.calls.* += 1;
        if (self.fail) return error.ForcedSyncFailure;
    }
};
fn clock(thread: bool) u64 {
    var stamp: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(if (thread) .THREAD_CPUTIME_ID else .MONOTONIC, &stamp) == 0);
    return @as(u64, @intCast(stamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(stamp.nsec));
}
pub fn Tests(comptime api: type) type {
    return struct {
        test "stdio flush ordinary streams avoid sync while commits failures all-streams and ABI stay explicit" {
            flush.write_through_flush = true;
            defer flush.write_through_flush = true;
            var syncs: u64 = 0;
            var s: State(SpyFile) = .{};
            for (&s.windows_files, 0..) |*slot, i| slot.* = .{ .guest_handle = 0x42 + i, .file = .{ .calls = &syncs } };
            try t.expect(api._flushWindowsStdio(&s, 0x1234));
            try t.expectEqual(@as(u64, 0), syncs);
            try t.expectEqual(@as(u64, 0), s.regs.rax);
            try t.expectEqual(@as(u64, 0x1234), s.regs.rip);
            s.windows_files[0].stdio_commit_on_flush = true;
            try t.expect(api._flushWindowsStdio(&s, null));
            try t.expectEqual(@as(u64, 1), syncs);
            try t.expectEqual(@as(u64, 0xABCD), s.regs.rip);
            try t.expectEqual(@as(u64, 0x2008), s.regs.rsp);
            try t.expectEqual(@as(u32, 1), s.pops);
            s.windows_files[0].file.?.fail = true;
            s.regs.rcx = 0; // Continue flushing the other streams after failure.
            s.windows_files[1].stdio_commit_on_flush = true;
            s.windows_files[2].standard_stream = 1;
            try t.expect(api._flushWindowsStdio(&s, 0x1234));
            try t.expectEqual(@as(u64, 3), syncs);
            try t.expectEqual(@as(u64, 0xFFFFFFFF), s.regs.rax);
            try t.expectEqual(@as(u32, 1117), s.windows_last_error);
            s.regs.rcx = 0xDEAD;
            try t.expect(api._flushWindowsStdio(&s, null));
            try t.expectEqual(@as(u64, 0xFFFFFFFF), s.regs.rax);
            try t.expectEqual(@as(u32, 2), s.pops);
            try t.expectEqual(@as(u64, 2), s.windows_file_failures);
        }
        test "stdio flush keeps return registers errors and stack in the bound caller" {
            var calls: u64 = 0;
            var s: State(SpyFile) = .{ .bound = true };
            s.regs.rcx = 0xDEAD;
            s.regs.rax = 0x1122;
            s.worker_regs.rsp = 0x3000;
            s.windows_files[0] = .{ .guest_handle = 0x42, .file = .{ .calls = &calls } };
            const owner = s.regs;
            try t.expect(api._flushWindowsStdio(&s, null));
            try t.expectEqual(@as(u64, 0), s.worker_regs.rax);
            try t.expectEqual(@as(u64, 0x3008), s.worker_regs.rsp);
            try t.expectEqual(@as(u64, 0xABCD), s.worker_regs.rip);
            s.worker_regs.rcx = 0xBAD;
            try t.expect(api._flushWindowsStdio(&s, 0x1234));
            try t.expectEqual(@as(u64, 0xFFFFFFFF), s.worker_regs.rax);
            try t.expectEqual(@as(u64, 0x1234), s.worker_regs.rip);
            try t.expectEqual(@as(u32, 1117), s.worker_error);
            try t.expectEqual(@as(u32, 0), s.windows_last_error);
            try t.expectEqualDeep(owner, s.regs);
        }
        test "stdio flush commit modes preserve guest defaults and ignore encoding options" {
            var s: State(SpyFile) = .{};
            flush.initStorage(&s, &s.windows_commode_storage);
            try t.expectEqual(@as(u32, 1), s.allocations);
            s.word = 1;
            flush.initStorage(&s, &s.windows_commode_storage);
            try t.expectEqual(@as(u32, 1), s.allocations);
            try t.expectEqual(@as(u32, 1), s.word);
            flush.applyMode(&s, &s.windows_files[0], "wb");
            try t.expect(s.windows_files[0].stdio_commit_on_flush);
            flush.applyMode(&s, &s.windows_files[0], "wbn,ccs=UTF-8");
            try t.expect(!s.windows_files[0].stdio_commit_on_flush);
            s.word = 0;
            flush.applyMode(&s, &s.windows_files[0], "a+bc");
            try t.expect(s.windows_files[0].stdio_commit_on_flush);
            flush.applyMode(&s, &s.windows_files[0], "ab,ccs=UNICODE");
            try t.expect(!s.windows_files[0].stdio_commit_on_flush);
        }
        test "stdio flush paired real-file write and complete handler CPU elapsed comparison" {
            const bench = std.c.getenv("ROSETTE_STDIO_FLUSH_BENCH") != null;
            defer flush.write_through_flush = true;
            const io = std.testing.io;
            var tmp = std.testing.tmpDir(.{});
            defer tmp.cleanup();
            var files: [4]std.Io.File = undefined;
            for (&files, 0..) |*file, i| {
                var name: [20]u8 = undefined;
                file.* = try tmp.dir.createFile(io, try std.fmt.bufPrint(&name, "stream{d}", .{i}), .{ .read = true });
            }
            defer for (files) |file| file.close(io);
            for (0..4) |profile| {
                const bytes: usize = if (profile == 0) 4096 else 64;
                const file_count: usize = if (profile == 3) 4 else 1;
                const count: usize = if (bench) 80 else 2;
                for (0..if (bench) @as(usize, 7) else 1) |pair| {
                    for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                        flush.write_through_flush = enabled;
                        var s: State(std.Io.File) = .{};
                        for (0..file_count) |i| {
                            s.windows_files[i] = .{ .guest_handle = 0x42 + i, .file = files[i], .stdio_commit_on_flush = profile == 2 or (profile == 3 and i == 0) };
                            try files[i].setLength(io, 0);
                        }
                        if (profile == 3) s.regs.rcx = 0;
                        var payload: [4096]u8 = undefined;
                        const c0 = clock(true);
                        const w0 = clock(false);
                        for (0..count) |i| {
                            @memset(payload[0..bytes], @truncate(i));
                            for (0..file_count) |j| try t.expectEqual(bytes, try files[j].writePositional(io, &.{payload[0..bytes]}, i * bytes));
                            try t.expect(api._flushWindowsStdio(&s, 0x1234));
                            try t.expectEqual(@as(u64, 0), s.regs.rax);
                        }
                        const wall = clock(false) - w0;
                        const cpu = clock(true) - c0;
                        for (0..file_count) |j| {
                            var actual: [4096]u8 = undefined;
                            try t.expectEqual(bytes, try files[j].readPositional(io, &.{actual[0..bytes]}, (count - 1) * bytes));
                            try t.expectEqualSlices(u8, payload[0..bytes], actual[0..bytes]);
                            try t.expectEqual(@as(u64, count * bytes), (try files[j].stat(io)).size);
                        }
                        const expected_commits: u64 = if (!enabled) count * file_count else if (profile == 2 or profile == 3) count else 0;
                        try t.expectEqual(expected_commits, s.windows_stdio_flush_commits);
                        try t.expectEqual(@as(u64, count), s.windows_stdio_flush_requests);
                        try t.expectEqual(@as(u64, 0), s.windows_file_failures);
                        if (bench) std.debug.print("stdio_flush profile={d} pair={d} enabled={} requests={d} bytes={d} streams={d} cpu_ns={d} elapsed_ns={d} syncs={d} elided={d}\n", .{ profile, pair, enabled, count, bytes, file_count, cpu, wall, s.windows_stdio_flush_commits, s.windows_stdio_flush_elided });
                    }
                }
            }
        }
    };
}
