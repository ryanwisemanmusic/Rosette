//! Keep scalar FIFO entries small. Larger owned arrays live in a separate
//! bounded slab; the worker relocates them into its batch before freeing slots.
const fifo = @import("async_command_worker.zig");
const owned = @import("owned_command_payloads.zig");

pub const Payload = union {
    barriers: fifo.barriers.Snapshot,
    descriptors: owned.DescriptorSets,
    constants: owned.PushConstants,
};

pub const Command = union(enum) {
    bind_pipeline: fifo.BindPipeline,
    bind_index_buffer: fifo.BindIndexBuffer,
    draw: fifo.Draw,
    draw_indexed: fifo.DrawIndexed,
    bind_descriptor_sets: *const owned.DescriptorSets,
    push_constants: *const owned.PushConstants,
    pipeline_barrier: *const fifo.barriers.Snapshot,

    pub fn pack(job: *const fifo.Job, storage: *Payload) Command {
        return switch (job.*) {
            .pipeline_barrier => |call| blk: {
                storage.* = .{ .barriers = call };
                break :blk .{ .pipeline_barrier = &storage.barriers };
            },
            .bind_pipeline => |call| .{ .bind_pipeline = call },
            .bind_index_buffer => |call| .{ .bind_index_buffer = call },
            .draw => |call| .{ .draw = call },
            .draw_indexed => |call| .{ .draw_indexed = call },
            .bind_descriptor_sets => |call| blk: {
                storage.* = .{ .descriptors = call };
                break :blk .{ .bind_descriptor_sets = &storage.descriptors };
            },
            .push_constants => |call| blk: {
                storage.* = .{ .constants = call };
                break :blk .{ .push_constants = &storage.constants };
            },
        };
    }

    /// Called under the FIFO mutex, before the producer can reuse the slot.
    pub fn relocate(self: *Command, storage: *Payload) void {
        if (@intFromEnum(std.meta.activeTag(self.*)) <= @intFromEnum(std.meta.Tag(Command).draw_indexed)) return;
        switch (self.*) {
            .pipeline_barrier => |call| {
                storage.* = .{ .barriers = call.* };
                self.* = .{ .pipeline_barrier = &storage.barriers };
            },
            .bind_descriptor_sets => |call| {
                storage.* = .{ .descriptors = call.* };
                self.* = .{ .bind_descriptor_sets = &storage.descriptors };
            },
            .push_constants => |call| {
                storage.* = .{ .constants = call.* };
                self.* = .{ .push_constants = &storage.constants };
            },
            else => {},
        }
    }

    pub fn execute(self: *const Command) void {
        // Draws dominate Xenia's recording stream. Keep their dispatch out
        // of the growing owned-payload switch, including scalar controls.
        if (self.* == .draw) {
            const call = self.draw;
            return call.function(call.command_buffer, call.vertex_count, call.instance_count, call.first_vertex, call.first_instance);
        }
        if (self.* == .draw_indexed) {
            const call = self.draw_indexed;
            return call.function(call.command_buffer, call.index_count, call.instance_count, call.first_index, call.vertex_offset, call.first_instance);
        }
        switch (self.*) {
            .pipeline_barrier => |call| call.execute(),
            .bind_pipeline => |call| call.function(call.command_buffer, call.bind_point, call.pipeline),
            .bind_index_buffer => |call| call.function(call.command_buffer, call.buffer, call.offset, call.index_type),
            .draw => |call| call.function(call.command_buffer, call.vertex_count, call.instance_count, call.first_vertex, call.first_instance),
            .draw_indexed => |call| call.function(call.command_buffer, call.index_count, call.instance_count, call.first_index, call.vertex_offset, call.first_instance),
            .bind_descriptor_sets => |call| call.execute(),
            .push_constants => |call| call.execute(),
        }
    }
};

const std = @import("std");
