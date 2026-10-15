//! Which Windows imports a run calls, how often, and roughly what each
//! costs: the evidence for choosing what gets a lock-free lane.
//!
//! On 2026-10-02 the worker transfer ledger counted 52.3 million imports
//! reached through the interpreter, each paying the runtime mutex, an arena
//! and the name-keyed dispatch chain, and nothing said which imports they
//! were. Every import is counted here at `windows_runtime.tryFunction`.
//!
//! Lock-free: an entry is keyed by its name's pointer, which is the import
//! stub's own storage or a literal and lives as long as the run, claimed
//! with one compare-and-swap and counted with relaxed adds. One call in
//! `sample_period` per entry is timed; the time includes whatever the
//! import waited for, so a wait import's cost is its blocking, not
//! Rosette's overhead.

const std = @import("std");

pub const slots: usize = 1024;
pub const sample_period: u64 = 64;

pub const Entry = struct {
    key: std.atomic.Value(usize) = .init(0),
    name_ptr: std.atomic.Value(usize) = .init(0),
    name_len: std.atomic.Value(usize) = .init(0),
    dll_ptr: std.atomic.Value(usize) = .init(0),
    dll_len: std.atomic.Value(usize) = .init(0),
    calls: std.atomic.Value(u64) = .init(0),
    samples: std.atomic.Value(u64) = .init(0),
    sampled_ns: std.atomic.Value(u64) = .init(0),
    sampled_max_ns: std.atomic.Value(u64) = .init(0),

    pub fn name(self: *const Entry) []const u8 {
        const ptr = self.name_ptr.load(.acquire);
        if (ptr == 0) return "<unnamed>";
        return @as([*]const u8, @ptrFromInt(ptr))[0..self.name_len.load(.monotonic)];
    }

    pub fn dll(self: *const Entry) []const u8 {
        const ptr = self.dll_ptr.load(.acquire);
        if (ptr == 0) return "";
        return @as([*]const u8, @ptrFromInt(ptr))[0..self.dll_len.load(.monotonic)];
    }

    /// The mean sampled host time of one call, in nanoseconds.
    pub fn meanNs(self: *const Entry) u64 {
        const samples = self.samples.load(.monotonic);
        return if (samples == 0) 0 else self.sampled_ns.load(.monotonic) / samples;
    }
};

pub const Histogram = struct {
    entries: [slots]Entry = [_]Entry{.{}} ** slots,
    overflow: std.atomic.Value(u64) = .init(0),

    /// Count one call; returns the entry when this call is the one in
    /// `sample_period` to time.
    pub fn note(self: *Histogram, dll: []const u8, function_name: []const u8) ?*Entry {
        const key = @intFromPtr(function_name.ptr);
        if (key == 0) return null;
        var index: usize = @intCast((key >> 3) *% 0x9E37_79B9 % slots);
        var probes: usize = 0;
        while (probes < 32) : (probes += 1) {
            const entry = &self.entries[index];
            const current = entry.key.load(.acquire);
            if (current == 0) {
                if (entry.key.cmpxchgStrong(0, key, .acq_rel, .acquire)) |_| {
                    // Another thread claimed it first; look again.
                    continue;
                }
                entry.name_len.store(function_name.len, .monotonic);
                entry.dll_len.store(dll.len, .monotonic);
                entry.dll_ptr.store(@intFromPtr(dll.ptr), .release);
                entry.name_ptr.store(key, .release);
            } else if (current != key) {
                index = (index + 1) % slots;
                continue;
            }
            const calls = entry.calls.fetchAdd(1, .monotonic);
            return if (calls % sample_period == 0) entry else null;
        }
        _ = self.overflow.fetchAdd(1, .monotonic);
        return null;
    }

    pub fn addSample(entry: *Entry, nanoseconds: u64) void {
        _ = entry.samples.fetchAdd(1, .monotonic);
        _ = entry.sampled_ns.fetchAdd(nanoseconds, .monotonic);
        _ = entry.sampled_max_ns.fetchMax(nanoseconds, .monotonic);
    }

    /// The `out.len` busiest entries, busiest first.
    pub fn top(self: *const Histogram, out: []*const Entry) []*const Entry {
        if (out.len == 0) return out[0..0];
        var count: usize = 0;
        for (&self.entries) |*entry| {
            const calls = entry.calls.load(.monotonic);
            if (calls == 0) continue;
            var position: usize = count;
            while (position > 0 and out[position - 1].calls.load(.monotonic) < calls) position -= 1;
            if (position >= out.len) continue;
            // Shift the rest down one place, dropping the last when full.
            var move: usize = @min(count, out.len - 1);
            while (move > position) : (move -= 1) out[move] = out[move - 1];
            out[position] = entry;
            if (count < out.len) count += 1;
        }
        return out[0..count];
    }

    pub fn totalCalls(self: *const Histogram) u64 {
        var total: u64 = 0;
        for (&self.entries) |*entry| total +|= entry.calls.load(.monotonic);
        return total;
    }
};

test "the histogram counts by name and ranks the busiest first" {
    const histogram = try std.testing.allocator.create(Histogram);
    defer std.testing.allocator.destroy(histogram);
    histogram.* = .{};
    const qpc = "QueryPerformanceCounter";
    const srw = "AcquireSRWLockExclusive";
    var sampled: u32 = 0;
    for (0..200) |_| {
        if (histogram.note("KERNEL32.dll", qpc)) |entry| {
            Histogram.addSample(entry, 100);
            sampled += 1;
        }
    }
    for (0..50) |_| _ = histogram.note("KERNEL32.dll", srw);
    // One call in sample_period is timed, the first among them.
    try std.testing.expectEqual(@as(u32, 4), sampled);
    var storage: [4]*const Entry = undefined;
    const ranked = histogram.top(&storage);
    try std.testing.expectEqual(@as(usize, 2), ranked.len);
    try std.testing.expectEqualStrings(qpc, ranked[0].name());
    try std.testing.expectEqualStrings("KERNEL32.dll", ranked[0].dll());
    try std.testing.expectEqual(@as(u64, 200), ranked[0].calls.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 100), ranked[0].meanNs());
    try std.testing.expectEqualStrings(srw, ranked[1].name());
    try std.testing.expectEqual(@as(u64, 250), histogram.totalCalls());
}

test "sampled timing maximum survives concurrent import reporters" {
    var entry: Entry = .{};
    const Worker = struct {
        fn run(e: *Entry, offset: u64) void {
            for (0..1000) |n| Histogram.addSample(e, offset + n);
        }
    };
    const a = try std.Thread.spawn(.{}, Worker.run, .{ &entry, @as(u64, 0) });
    const b = try std.Thread.spawn(.{}, Worker.run, .{ &entry, @as(u64, 1000) });
    a.join();
    b.join();
    try std.testing.expectEqual(@as(u64, 2000), entry.samples.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1999), entry.sampled_max_ns.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1999000), entry.sampled_ns.load(.monotonic));
}
