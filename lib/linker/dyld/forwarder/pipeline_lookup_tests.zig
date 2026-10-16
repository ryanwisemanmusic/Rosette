//! The tracked-pipeline memo through the forwarder's own writers.
const std = @import("std");
const root = @import("../dynamic_library_forwarder.zig");
const internal = root.__ForwarderInternals;
const abi = internal._abi;
const loader = @import("loader_symbols.zig");
const pipeline_lookup = @import("pipeline_lookup.zig");

fn lookup(forwarder: *root.Forwarder, real: u64) ?u32 {
    const record = loader.trackedGraphicsPipeline(forwarder, real) orelse return null;
    return record.stage_count;
}

test "pipeline memo follows remember, forget and the table reset exactly" {
    const saved = pipeline_lookup.enabled;
    defer pipeline_lookup.enabled = saved;
    pipeline_lookup.enabled = true;
    const forwarder = try std.testing.allocator.create(root.Forwarder);
    defer std.testing.allocator.destroy(forwarder);
    forwarder.* = .{};
    const create = abi.GraphicsPipelineCreateInfo{ .stage_count = 2 };
    const other = abi.GraphicsPipelineCreateInfo{ .stage_count = 3 };

    try std.testing.expectEqual(@as(?u32, null), lookup(forwarder, 0x7000));
    forwarder.rememberGraphicsPipeline(0x7000, &create, 0, false, .{});
    try std.testing.expectEqual(@as(?u32, 2), lookup(forwarder, 0x7000));
    // A cached hit, then a write to the same handle must be visible at once.
    try std.testing.expectEqual(@as(?u32, 2), lookup(forwarder, 0x7000));
    forwarder.rememberGraphicsPipeline(0x7000, &other, 0, false, .{});
    try std.testing.expectEqual(@as(?u32, 3), lookup(forwarder, 0x7000));
    // A cached miss turns into a hit when the handle is remembered.
    try std.testing.expectEqual(@as(?u32, null), lookup(forwarder, 0x8000));
    forwarder.rememberGraphicsPipeline(0x8000, &create, 0, false, .{});
    try std.testing.expectEqual(@as(?u32, 2), lookup(forwarder, 0x8000));
    forwarder.forgetGraphicsPipeline(0x7000);
    try std.testing.expectEqual(@as(?u32, null), lookup(forwarder, 0x7000));
    try std.testing.expectEqual(@as(?u32, 2), lookup(forwarder, 0x8000));
    // A freed slot is reused by the next handle; the old handle stays absent.
    forwarder.rememberGraphicsPipeline(0x9000, &other, 0, false, .{});
    try std.testing.expectEqual(@as(?u32, 3), lookup(forwarder, 0x9000));
    try std.testing.expectEqual(@as(?u32, null), lookup(forwarder, 0x7000));
    forwarder.clearRealVulkanObjectMaps();
    try std.testing.expectEqual(@as(?u32, null), lookup(forwarder, 0x8000));
    try std.testing.expectEqual(@as(?u32, null), lookup(forwarder, 0x9000));
    try std.testing.expect(forwarder.tracked_pipeline_lookup.hits != 0);
}

test "pipeline memo agrees with the scan over a randomized forwarder history" {
    const saved = pipeline_lookup.enabled;
    defer pipeline_lookup.enabled = saved;
    const forwarder = try std.testing.allocator.create(root.Forwarder);
    defer std.testing.allocator.destroy(forwarder);
    forwarder.* = .{};
    var random = std.Random.DefaultPrng.init(0x91be);
    const infos = [_]abi.GraphicsPipelineCreateInfo{ .{ .stage_count = 1 }, .{ .stage_count = 2 }, .{ .stage_count = 4 } };
    for (0..30_000) |_| {
        const r = random.random();
        const real = 0x10_0000 + @as(u64, r.uintLessThan(u16, 600)) * 0x40;
        switch (r.uintLessThan(u8, 8)) {
            0 => forwarder.rememberGraphicsPipeline(real, &infos[r.uintLessThan(usize, infos.len)], 0, false, .{}),
            1 => forwarder.forgetGraphicsPipeline(real),
            else => {
                pipeline_lookup.enabled = false;
                const expected = lookup(forwarder, real);
                pipeline_lookup.enabled = true;
                try std.testing.expectEqual(expected, lookup(forwarder, real));
            },
        }
    }
}
