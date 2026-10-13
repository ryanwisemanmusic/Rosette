//! Argument snapshots for FIFO recording. No guest or marshal-scratch pointers
//! survive admission; native handles remain valid until the ordinary drain at
//! update/free/reset/destroy/submit and FSI continuation boundaries.
const std = @import("std");
const abi = @import("abi.zig");

pub const DescriptorSets = struct {
    function: abi.PfnCmdBindDescriptorSets,
    command_buffer: abi.CommandBuffer,
    bind_point: u32,
    layout: u64,
    first_set: u32,
    set_count: u32,
    dynamic_count: u32,
    sets: [32]u64 = undefined,
    offsets: [64]u32 = undefined,

    pub fn init(function: abi.PfnCmdBindDescriptorSets, command_buffer: abi.CommandBuffer, bind_point: u32, layout: u64, first_set: u32, sets: []const u64, offsets: []const u32) ?DescriptorSets {
        if (sets.len > 32 or offsets.len > 64) return null;
        var result = DescriptorSets{ .function = function, .command_buffer = command_buffer, .bind_point = bind_point, .layout = layout, .first_set = first_set, .set_count = @intCast(sets.len), .dynamic_count = @intCast(offsets.len) };
        @memcpy(result.sets[0..sets.len], sets);
        @memcpy(result.offsets[0..offsets.len], offsets);
        return result;
    }

    pub fn execute(self: *const DescriptorSets) void {
        self.function(self.command_buffer, self.bind_point, self.layout, self.first_set, self.set_count, &self.sets, self.dynamic_count, if (self.dynamic_count == 0) null else &self.offsets);
    }
};

pub const PushConstants = struct {
    function: abi.PfnCmdPushConstants,
    command_buffer: abi.CommandBuffer,
    layout: u64,
    stages: u32,
    offset: u32,
    size: u32,
    // Keep the native pointer aligned as it was in the original marshal.
    bytes: [256]u8 align(4) = undefined,

    pub fn init(function: abi.PfnCmdPushConstants, command_buffer: abi.CommandBuffer, layout: u64, stages: u32, offset: u32, bytes: []const u8) ?PushConstants {
        if (bytes.len > 256) return null;
        var result = PushConstants{ .function = function, .command_buffer = command_buffer, .layout = layout, .stages = stages, .offset = offset, .size = @intCast(bytes.len) };
        @memcpy(result.bytes[0..bytes.len], bytes);
        return result;
    }

    pub fn execute(self: *const PushConstants) void {
        self.function(self.command_buffer, self.layout, self.stages, self.offset, self.size, if (self.size == 0) null else &self.bytes);
    }
};

test "owned Vulkan payload limits refuse oversized arguments without truncation" {
    const Calls = struct {
        fn sets(_: abi.CommandBuffer, _: u32, _: u64, _: u32, _: u32, _: [*]const u64, _: u32, _: ?[*]const u32) callconv(.c) void {}
        fn push(_: abi.CommandBuffer, _: u64, _: u32, _: u32, _: u32, _: ?*const anyopaque) callconv(.c) void {}
    };
    const sets: [33]u64 = @splat(0);
    const offsets: [65]u32 = @splat(0);
    const bytes: [257]u8 = @splat(0);
    try std.testing.expect(DescriptorSets.init(Calls.sets, null, 0, 0, 0, &sets, &.{}) == null);
    try std.testing.expect(DescriptorSets.init(Calls.sets, null, 0, 0, 0, &.{}, &offsets) == null);
    try std.testing.expect(DescriptorSets.init(Calls.sets, null, 0, 0, 0, sets[0..32], offsets[0..64]) != null);
    try std.testing.expect(PushConstants.init(Calls.push, null, 0, 0, 0, &bytes) == null);
    try std.testing.expect(PushConstants.init(Calls.push, null, 0, 0, 0, bytes[0..256]) != null);
}
