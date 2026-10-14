//! CPU-only timing of the production shader rewrite stages, with no driver.
const std = @import("std");
const rect = @import("rect");
const robust = @import("robust");
const sampling = @import("sampling");
const hdr = @import("hdr");
fn fingerprint(words: []const u32) u64 {
    var value: u64 = 14695981039346656037;
    for (words) |word| inline for (0..8) |byte| {
        value = (value ^ @as(u8, @truncate(@as(u64, word) >> @intCast(byte * 8)))) *% 1099511628211;
    };
    return value;
}
fn now() u64 {
    var t: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &t);
    return @as(u64, @intCast(t.sec)) * std.time.ns_per_s + @as(u64, @intCast(t.nsec));
}
pub fn main(init: std.process.Init) !void {
    const a = std.heap.c_allocator;
    const args = try init.minimal.args.toSlice(a);
    var dir = try std.Io.Dir.cwd().openDir(init.io, args[1], .{ .iterate = true });
    defer dir.close(init.io);
    var it = dir.iterate();
    var total: [4]u64 = @splat(0);
    var count: usize = 0;
    while (try it.next(init.io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".guest.spv")) continue;
        const bytes = try dir.readFileAllocOptions(init.io, entry.name, a, .limited(32 << 20), .of(u32), null);
        defer a.free(bytes);
        const words = std.mem.bytesAsSlice(u32, bytes);
        const t0 = now();
        const h = try hdr.rewrite(a, words);
        defer a.free(h.words);
        const t1 = now();
        const r = try rect.expand(a, if (h.words.len != 0) h.words else words);
        defer a.free(r.words);
        const t2 = now();
        const p = try sampling.centerCoordinates(a, if (r.refusal == .none) r.words else if (h.words.len != 0) h.words else words);
        defer a.free(p.words);
        const t3 = now();
        const b = try robust.harden(a, if (p.words.len != 0) p.words else if (r.refusal == .none) r.words else if (h.words.len != 0) h.words else words);
        defer a.free(b.words);
        const t4 = now();
        const times = [_]u64{ t1 - t0, t2 - t1, t3 - t2, t4 - t3 };
        for (&total, times) |*sum, v| sum.* += v;
        count += 1;
        std.debug.print("STAGE file={s} hash={x} bytes={d} hdr_ns={d} rect_ns={d} pixel_ns={d} robust_ns={d} refusal={s}\n", .{ entry.name, fingerprint(words), bytes.len, times[0], times[1], times[2], times[3], b.refusal.label() });
    }
    std.debug.print("TOTAL modules={d} hdr_ns={d} rect_ns={d} pixel_ns={d} robust_ns={d}\n", .{ count, total[0], total[1], total[2], total[3] });
}
