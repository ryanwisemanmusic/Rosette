//! Small, pointer-free pipeline-barrier snapshots. Larger arrays keep the
//! original synchronous route. Native resource handles are already validated;
//! update/free/reset/destroy/submit boundaries still drain the recording FIFO.
const std = @import("std");
const abi = @import("abi.zig");

pub const Snapshot = struct {
    function: abi.PfnCmdPipelineBarrier,
    command_buffer: abi.CommandBuffer,
    source_stages: u32,
    destination_stages: u32,
    dependencies: u32,
    memory_count: u32,
    buffer_count: u32,
    image_count: u32,
    memory: [2]abi.MemoryBarrier = undefined,
    buffers: [4]abi.BufferMemoryBarrier = undefined,
    images: [2]abi.ImageMemoryBarrier = undefined,

    pub fn init(function: abi.PfnCmdPipelineBarrier, command: abi.CommandBuffer, source: u32, destination: u32, dependencies: u32, memory: []const abi.MemoryBarrier, buffers: []const abi.BufferMemoryBarrier, images: []const abi.ImageMemoryBarrier) ?Snapshot {
        if (memory.len > 2 or buffers.len > 4 or images.len > 2) return null;
        for (memory) |barrier| if (barrier.p_next != null) return null;
        for (buffers) |barrier| if (barrier.p_next != null) return null;
        for (images) |barrier| if (barrier.p_next != null) return null;
        var result = Snapshot{ .function = function, .command_buffer = command, .source_stages = source, .destination_stages = destination, .dependencies = dependencies, .memory_count = @intCast(memory.len), .buffer_count = @intCast(buffers.len), .image_count = @intCast(images.len) };
        @memcpy(result.memory[0..memory.len], memory);
        @memcpy(result.buffers[0..buffers.len], buffers);
        @memcpy(result.images[0..images.len], images);
        return result;
    }

    pub fn execute(self: *const Snapshot) void {
        self.function(self.command_buffer, self.source_stages, self.destination_stages, self.dependencies, self.memory_count, if (self.memory_count == 0) null else &self.memory, self.buffer_count, if (self.buffer_count == 0) null else &self.buffers, self.image_count, if (self.image_count == 0) null else &self.images);
    }
};

test "FSI owned Vulkan barriers refuse overflow and any unsnapshotted extension pointer" {
    const Calls = struct {
        fn barrier(_: abi.CommandBuffer, _: u32, _: u32, _: u32, _: u32, _: ?*const anyopaque, _: u32, _: ?*const anyopaque, _: u32, _: ?[*]const abi.ImageMemoryBarrier) callconv(.c) void {}
    };
    var memory: [3]abi.MemoryBarrier = @splat(.{});
    const buffers: [5]abi.BufferMemoryBarrier = @splat(.{});
    const images: [3]abi.ImageMemoryBarrier = @splat(.{});
    try std.testing.expect(Snapshot.init(Calls.barrier, null, 1, 2, 3, &memory, &.{}, &.{}) == null);
    try std.testing.expect(Snapshot.init(Calls.barrier, null, 1, 2, 3, &.{}, &buffers, &.{}) == null);
    try std.testing.expect(Snapshot.init(Calls.barrier, null, 1, 2, 3, &.{}, &.{}, &images) == null);
    try std.testing.expect(Snapshot.init(Calls.barrier, null, 1, 2, 3, memory[0..2], buffers[0..4], images[0..2]) != null);
    memory[0].p_next = @ptrFromInt(1);
    try std.testing.expect(Snapshot.init(Calls.barrier, null, 1, 2, 3, memory[0..1], &.{}, &.{}) == null);
    // Keep compact scalar entries and the existing payload slab unchanged.
    try std.testing.expect(@sizeOf(Snapshot) <= @sizeOf(@import("owned_command_payloads.zig").DescriptorSets));
}
