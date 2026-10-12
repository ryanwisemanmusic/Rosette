//! Offline microbenchmarks for the hot paths changed after run 20261012T054107Z.
//! These measure algorithm throughput only; they do not predict game FPS.

const std = @import("std");
const crt_scan = @import("crt_scan");
const heap_index = @import("heap_index");

var timebase: ?std.c.mach_timebase_info_data = null;
var checksum: u64 = 0;

fn initTimebase() std.c.mach_timebase_info_data {
    var result: std.c.mach_timebase_info_data = undefined;
    if (std.c.mach_timebase_info(&result) != 0 or result.denom == 0) @panic("mach_timebase_info failed");
    return result;
}

fn nowNs() u64 {
    if (timebase == null) timebase = initTimebase();
    const scale = timebase.?;
    const ticks = std.c.mach_absolute_time();
    return @intCast((@as(u128, ticks) * scale.numer) / scale.denom);
}

fn elapsedNs(start: u64) u64 {
    return nowNs() - start;
}

fn printRate(name: []const u8, operations: u64, ns: u64) void {
    const ns_per_op = @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(operations));
    const ops_per_second = @as(f64, @floatFromInt(operations)) * 1_000_000_000.0 / @as(f64, @floatFromInt(ns));
    std.debug.print("{s}: operations={d} elapsed_ms={d:.3} ns_per_op={d:.2} ops_per_second={d:.0}\n", .{
        name,
        operations,
        @as(f64, @floatFromInt(ns)) / 1_000_000.0,
        ns_per_op,
        ops_per_second,
    });
}

fn scalarDifference(left: []const u8, right: []const u8) ?usize {
    for (left, right, 0..) |a, b, index| if (a != b) return index;
    return null;
}

fn scalarZero(bytes: []const u8) ?usize {
    // This is the standard-library vectorized scan used by the old import
    // path, rather than an artificially slow byte-at-a-time baseline.
    return std.mem.indexOfScalar(u8, bytes, 0);
}

fn scalarCString(left: []const u8, right: []const u8) i32 {
    const left_zero = scalarZero(left) orelse return 0;
    const right_zero = scalarZero(right) orelse return 0;
    const shared = @min(left_zero, right_zero);
    if (scalarDifference(left[0..shared], right[0..shared])) |index| {
        return @as(i32, left[index]) - @as(i32, right[index]);
    }
    if (left_zero == right_zero) return 0;
    return if (left_zero < right_zero) -1 else 1;
}

fn indexedCString(left: []const u8, right: []const u8) i32 {
    var offset: usize = 0;
    while (offset < left.len and offset < right.len) {
        const amount = @min(512, @min(left.len - offset, right.len - offset));
        switch (crt_scan.compareStringChunk(left[offset..][0..amount], right[offset..][0..amount])) {
            .continue_scan => offset += amount,
            .result => |result| return result,
        }
    }
    return 0;
}

const SnapshotStats = struct {
    length: usize,
    calls: usize,
    bytes: usize,
};

fn legacyStrxfrmStage(source: []const u8, staged: []u8, snapshot: []u8) ?SnapshotStats {
    var offset: usize = 0;
    var calls: usize = 0;
    var bytes: usize = 0;
    while (offset < source.len) {
        const amount = @min(512, source.len - offset);
        @memcpy(snapshot[0..amount], source[offset..][0..amount]);
        calls += 1;
        bytes += amount;
        if (crt_scan.firstZero(snapshot[0..amount])) |terminator| {
            const length = offset + terminator;
            @memcpy(staged[0..length], source[0..length]);
            calls += 1;
            bytes += length;
            return .{ .length = length, .calls = calls, .bytes = bytes };
        }
        offset += amount;
    }
    return null;
}

fn singleReadStrxfrmStage(source: []const u8, staged: []u8) ?SnapshotStats {
    var offset: usize = 0;
    var calls: usize = 0;
    var bytes: usize = 0;
    while (offset < source.len) {
        const amount = @min(512, source.len - offset);
        @memcpy(staged[offset..][0..amount], source[offset..][0..amount]);
        calls += 1;
        bytes += amount;
        if (crt_scan.firstZero(staged[offset..][0..amount])) |terminator| {
            return .{ .length = offset + terminator, .calls = calls, .bytes = bytes };
        }
        offset += amount;
    }
    return null;
}

fn scalarHeapLookup(records: anytype, address: u64) ?usize {
    var lower: usize = 0;
    var upper = records.len;
    while (lower < upper) {
        const middle = lower + (upper - lower) / 2;
        if (records[middle].guest_base < address) {
            lower = middle + 1;
        } else {
            upper = middle;
        }
    }
    if (lower < records.len and records[lower].guest_base == address) return lower;
    return null;
}

fn runHeapBench(records: anytype, slots: []const u32, iterations: usize) void {
    const mask = records.len - 1;
    var start = nowNs();
    for (0..iterations) |iteration| {
        const index = (iteration *% 40503) & mask;
        checksum +%= @intCast(scalarHeapLookup(records, records[index].guest_base) orelse 0);
    }
    const binary_ns = elapsedNs(start);
    printRate("heap_bounded_binary_search", iterations, binary_ns);

    start = nowNs();
    var probes: u64 = 0;
    for (0..iterations) |iteration| {
        const index = (iteration *% 40503) & mask;
        const found = heap_index.lookup(slots, records, records[index].guest_base);
        checksum +%= @intCast(found.index orelse 0);
        probes += @intCast(found.probes);
    }
    const index_ns = elapsedNs(start);
    printRate("heap_open_address_index", iterations, index_ns);
    std.debug.print("heap_open_address_index: mean_probes={d:.3}\n", .{@as(f64, @floatFromInt(probes)) / @as(f64, @floatFromInt(iterations))});
    std.debug.print("heap_speedup={d:.2}x\n", .{@as(f64, @floatFromInt(binary_ns)) / @as(f64, @floatFromInt(index_ns))});
}

pub fn main() !void {
    const iterations: usize = 2_000_000;
    var left: [512]u8 = @splat('q');
    var right: [512]u8 = left;
    left[511] = 0;
    right[511] = 0;
    var started = nowNs();
    for (0..iterations) |_| checksum +%= @intCast(scalarDifference(&left, &right) orelse 0);
    const scalar_memcmp_ns = elapsedNs(started);
    started = nowNs();
    for (0..iterations) |_| checksum +%= @intCast(crt_scan.firstDifference(&left, &right) orelse 0);
    const vector_memcmp_ns = elapsedNs(started);
    printRate("memcmp_scalar_512_equal", iterations, scalar_memcmp_ns);
    printRate("memcmp_vector_512_equal", iterations, vector_memcmp_ns);
    std.debug.print("memcmp_vector_speedup={d:.2}x\n", .{@as(f64, @floatFromInt(scalar_memcmp_ns)) / @as(f64, @floatFromInt(vector_memcmp_ns))});

    started = nowNs();
    for (0..iterations) |_| checksum +%= @intCast(scalarZero(&left) orelse 0);
    const scalar_strlen_ns = elapsedNs(started);
    started = nowNs();
    for (0..iterations) |_| checksum +%= @intCast(crt_scan.firstZero(&left) orelse 0);
    const vector_strlen_ns = elapsedNs(started);
    printRate("strlen_scalar_512", iterations, scalar_strlen_ns);
    printRate("strlen_vector_512", iterations, vector_strlen_ns);
    std.debug.print("strlen_vector_speedup={d:.2}x\n", .{@as(f64, @floatFromInt(scalar_strlen_ns)) / @as(f64, @floatFromInt(vector_strlen_ns))});

    started = nowNs();
    for (0..iterations) |_| checksum +%= @intCast(scalarCString(&left, &right));
    const scalar_strcmp_ns = elapsedNs(started);
    started = nowNs();
    for (0..iterations) |_| checksum +%= @intCast(indexedCString(&left, &right));
    const vector_strcmp_ns = elapsedNs(started);
    printRate("strcmp_legacy_three_pass_512", iterations, scalar_strcmp_ns);
    printRate("strcmp_single_pass_vector_512", iterations, vector_strcmp_ns);
    std.debug.print("strcmp_vector_speedup={d:.2}x\n", .{@as(f64, @floatFromInt(scalar_strcmp_ns)) / @as(f64, @floatFromInt(vector_strcmp_ns))});

    var transform_source: [512]u8 = @splat('z');
    transform_source[400] = 0;
    var transform_staged: [513]u8 = undefined;
    var transform_snapshot: [512]u8 = undefined;
    started = nowNs();
    var legacy_stats: SnapshotStats = undefined;
    for (0..iterations) |_| {
        legacy_stats = legacyStrxfrmStage(&transform_source, &transform_staged, &transform_snapshot) orelse return error.UnterminatedString;
        checksum +%= @intCast(legacy_stats.length + legacy_stats.calls + legacy_stats.bytes);
    }
    const legacy_strxfrm_ns = elapsedNs(started);
    started = nowNs();
    var staged_stats: SnapshotStats = undefined;
    for (0..iterations) |_| {
        staged_stats = singleReadStrxfrmStage(&transform_source, &transform_staged) orelse return error.UnterminatedString;
        checksum +%= @intCast(staged_stats.length + staged_stats.calls + staged_stats.bytes);
    }
    const single_read_strxfrm_ns = elapsedNs(started);
    printRate("strxfrm_legacy_scan_then_stage_400", iterations, legacy_strxfrm_ns);
    printRate("strxfrm_single_read_stage_400", iterations, single_read_strxfrm_ns);
    std.debug.print("strxfrm_snapshot_reduction: calls={d}->{d} bytes={d}->{d} reduction={d:.1}%\n", .{
        legacy_stats.calls,
        staged_stats.calls,
        legacy_stats.bytes,
        staged_stats.bytes,
        (1.0 - @as(f64, @floatFromInt(staged_stats.bytes)) / @as(f64, @floatFromInt(legacy_stats.bytes))) * 100.0,
    });
    std.debug.print("strxfrm_stage_speedup={d:.2}x\n", .{@as(f64, @floatFromInt(legacy_strxfrm_ns)) / @as(f64, @floatFromInt(single_read_strxfrm_ns))});

    const Record = struct {
        guest_base: u64,
        padding: [120]u8 = @splat(0),
    };
    const record_count: usize = 1 << 17;
    const records = try std.heap.page_allocator.alloc(Record, record_count);
    defer std.heap.page_allocator.free(records);
    for (records, 0..) |*record, index| record.guest_base = 0x1400_0000 + @as(u64, @intCast(index)) * 0x30;
    const slot_count = heap_index.requiredSlots(record_count) orelse return error.IndexSizeOverflow;
    const slots = try std.heap.page_allocator.alloc(u32, slot_count);
    defer std.heap.page_allocator.free(slots);
    @memset(slots, 0);
    if (!heap_index.rebuild(slots, records)) return error.IndexBuildFailed;
    runHeapBench(records, slots, iterations);

    std.mem.doNotOptimizeAway(checksum);
    std.debug.print("checksum={d}\n", .{checksum});
}
