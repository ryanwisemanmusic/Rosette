//! Splitting one guest command buffer's FSI work into bounded chunks.
//!
//! Xenia replays a whole frame of draws into one primary command buffer and
//! submits it in one VkSubmitInfo, which MoltenVK turns into one Metal command
//! buffer. To keep each Metal command buffer far below the GPU watchdog
//! (`budget.zig`), the bridge may close the current real command buffer
//! between two FSI draws and continue the guest's recording in a fresh one:
//!
//!   end the render pass, end the command buffer;
//!   begin a new command buffer from the bridge's own pool;
//!   begin the same render pass and framebuffer again;
//!   replay every piece of bound state the guest had set;
//!   forward the rest of the guest's commands there.
//!
//! At submission each chunk becomes its own VkSubmitInfo.
//!
//! This is only exact where nothing is lost by ending the pass:
//!   - the pass has no attachments and one subpass (Xenia's FSI pass, see
//!     `contract.zig`), so there is nothing to store or load, and its by-region
//!     external dependency orders the EDRAM writes across the break;
//!   - the pass was begun inline in this primary command buffer;
//!   - no query or conditional rendering is active;
//!   - every state command the guest recorded is one this module records and
//!     can replay. Any other command makes the recording unsplittable until
//!     the guest begins it again.
//! If a boundary cannot be replayed, the original Vulkan recording remains
//! intact; the hard chain capacity is reported and refuses submission.
const std = @import("std");
const abi = @import("../abi.zig");

// The guest submit translator accepts up to 256 command-buffer handles in a
// single VkSubmitInfo, but an FSI recording can produce more segments because
// the forwarder streams one segment per VkSubmitInfo. 255 was incorrectly
// reused as the per-recording chain limit. On Halo 3, a risk response could
// reduce the draw cap to 4, hit that limit during a 1,000+ draw recording,
// and then let the remaining FSI draws accumulate in one unbounded chunk.
// Keep a generous per-recording ceiling; the forwarder fails the recording
// closed if even this bound is reached, rather than forwarding an oversized
// Metal command buffer.
pub const max_chunks_per_command_buffer: usize = 4095;
pub const max_descriptor_binds: usize = 16;
pub const max_sets_per_bind: usize = 8;
pub const max_dynamic_offsets: usize = 16;
pub const max_push_constant_calls: usize = 16;
pub const max_push_constant_bytes: usize = 256;
pub const max_viewports: usize = 16;
pub const max_vertex_bindings: usize = 32;
const max_in_flight_segments = @import("../../metal/command_buffer_policy.zig").fsi.max_in_flight;

pub const bind_point_graphics: u32 = 0;
pub const bind_point_compute: u32 = 1;
pub const stencil_face_front: u32 = 1;
pub const stencil_face_back: u32 = 2;
pub const subpass_contents_inline: u32 = 0;

/// Why a recording is not split. `none` means it may be.
pub const Block = enum(u8) {
    none,
    secondary_command_buffer,
    unrecorded_command,
    descriptor_bind_capacity,
    descriptor_bind_shape,
    push_constant_capacity,
    viewport_shape,
    vertex_binding_shape,
    query_active,
    conditional_rendering_active,
    dynamic_rendering,
    render_pass_not_splittable,
    secondary_contents,
    continuation_unavailable,
    continuation_reset_failed,
    continuation_begin_failed,
    replay_function_missing,
    recording_failed,
    chunk_capacity,
};

pub const DescriptorBind = struct {
    bind_point: u32 = 0,
    layout: u64 = 0,
    first_set: u32 = 0,
    set_count: u32 = 0,
    sets: [max_sets_per_bind]u64 = [_]u64{0} ** max_sets_per_bind,
    dynamic_count: u32 = 0,
    dynamic_offsets: [max_dynamic_offsets]u32 = [_]u32{0} ** max_dynamic_offsets,

    fn covers(self: DescriptorBind, older: DescriptorBind) bool {
        return self.bind_point == older.bind_point and
            self.first_set <= older.first_set and
            older.first_set + older.set_count <= self.first_set + self.set_count;
    }
};

pub const PushConstants = struct {
    layout: u64 = 0,
    stages: u32 = 0,
    offset: u32 = 0,
    size: u32 = 0,
    bytes: [max_push_constant_bytes]u8 = [_]u8{0} ** max_push_constant_bytes,
};

pub const IndexBinding = struct {
    buffer: u64 = 0,
    offset: u64 = 0,
    index_type: u32 = 0,
};

/// Every piece of command-buffer state that survives a render pass boundary
/// and that Xenia's FSI recording sets, in host (real) handles.
pub const Shadow = struct {
    pipelines: [2]u64 = .{ 0, 0 },
    descriptor_binds: [max_descriptor_binds]DescriptorBind = [_]DescriptorBind{.{}} ** max_descriptor_binds,
    descriptor_bind_count: usize = 0,
    push_constants: [max_push_constant_calls]PushConstants = [_]PushConstants{.{}} ** max_push_constant_calls,
    push_constant_count: usize = 0,
    viewports: [max_viewports]abi.Viewport = [_]abi.Viewport{.{}} ** max_viewports,
    viewport_mask: u16 = 0,
    scissors: [max_viewports]abi.Rect2D = [_]abi.Rect2D{.{}} ** max_viewports,
    scissor_mask: u16 = 0,
    blend_constants: ?[4]f32 = null,
    depth_bias: ?[3]f32 = null,
    depth_bounds: ?[2]f32 = null,
    stencil_compare_mask: [2]?u32 = .{ null, null },
    stencil_write_mask: [2]?u32 = .{ null, null },
    stencil_reference: [2]?u32 = .{ null, null },
    index: ?IndexBinding = null,
    vertex_buffers: [max_vertex_bindings]u64 = [_]u64{0} ** max_vertex_bindings,
    vertex_offsets: [max_vertex_bindings]u64 = [_]u64{0} ** max_vertex_bindings,
    vertex_mask: u32 = 0,

    pub fn bindPipeline(self: *Shadow, bind_point: u32, pipeline: u64) bool {
        if (bind_point > bind_point_compute) return false;
        self.pipelines[bind_point] = pipeline;
        return true;
    }

    /// Record a descriptor-set bind. Earlier binds whose sets this one fully
    /// rebinds are dropped, so the list stays as short as the set indices in
    /// use; replaying the survivors in order reproduces every valid state.
    pub fn bindDescriptorSets(self: *Shadow, bind_point: u32, layout: u64, first_set: u32, sets: []const u64, dynamic_offsets: []const u32) Block {
        if (bind_point > bind_point_compute or sets.len == 0 or sets.len > max_sets_per_bind or dynamic_offsets.len > max_dynamic_offsets) return .descriptor_bind_shape;
        var bind = DescriptorBind{
            .bind_point = bind_point,
            .layout = layout,
            .first_set = first_set,
            .set_count = @intCast(sets.len),
            .dynamic_count = @intCast(dynamic_offsets.len),
        };
        @memcpy(bind.sets[0..sets.len], sets);
        @memcpy(bind.dynamic_offsets[0..dynamic_offsets.len], dynamic_offsets);
        var kept: usize = 0;
        for (self.descriptor_binds[0..self.descriptor_bind_count]) |older| {
            if (bind.covers(older)) continue;
            self.descriptor_binds[kept] = older;
            kept += 1;
        }
        if (kept == max_descriptor_binds) {
            self.descriptor_bind_count = kept;
            return .descriptor_bind_capacity;
        }
        self.descriptor_binds[kept] = bind;
        self.descriptor_bind_count = kept + 1;
        return .none;
    }

    /// Record a push-constant write; an identical range replaces its older
    /// copy, and the writes replay in their original order.
    pub fn pushConstants(self: *Shadow, layout: u64, stages: u32, offset: u32, bytes: []const u8) Block {
        if (bytes.len > max_push_constant_bytes) return .push_constant_capacity;
        var write = PushConstants{ .layout = layout, .stages = stages, .offset = offset, .size = @intCast(bytes.len) };
        @memcpy(write.bytes[0..bytes.len], bytes);
        var kept: usize = 0;
        for (self.push_constants[0..self.push_constant_count]) |older| {
            if (older.layout == layout and older.stages == stages and older.offset == offset and older.size == write.size) continue;
            self.push_constants[kept] = older;
            kept += 1;
        }
        if (kept == max_push_constant_calls) {
            self.push_constant_count = kept;
            return .push_constant_capacity;
        }
        self.push_constants[kept] = write;
        self.push_constant_count = kept + 1;
        return .none;
    }

    pub fn setViewports(self: *Shadow, first: u32, viewports: []const abi.Viewport) Block {
        if (first + viewports.len > max_viewports) return .viewport_shape;
        for (viewports, 0..) |viewport, index| {
            self.viewports[first + index] = viewport;
            self.viewport_mask |= @as(u16, 1) << @intCast(first + index);
        }
        return .none;
    }

    pub fn setScissors(self: *Shadow, first: u32, scissors: []const abi.Rect2D) Block {
        if (first + scissors.len > max_viewports) return .viewport_shape;
        for (scissors, 0..) |scissor, index| {
            self.scissors[first + index] = scissor;
            self.scissor_mask |= @as(u16, 1) << @intCast(first + index);
        }
        return .none;
    }

    pub fn setStencil(field: *[2]?u32, face_mask: u32, value: u32) void {
        if (face_mask & stencil_face_front != 0) field[0] = value;
        if (face_mask & stencil_face_back != 0) field[1] = value;
    }

    pub fn bindVertexBuffers(self: *Shadow, first: u32, buffers: []const u64, offsets: []const u64) Block {
        if (buffers.len != offsets.len or first + buffers.len > max_vertex_bindings) return .vertex_binding_shape;
        for (buffers, offsets, 0..) |buffer, offset, index| {
            self.vertex_buffers[first + index] = buffer;
            self.vertex_offsets[first + index] = offset;
            self.vertex_mask |= @as(u32, 1) << @intCast(first + index);
        }
        return .none;
    }

    /// Re-issue every recorded state command through `ops`, in an order that
    /// leaves the same bound state the guest had: pipelines, descriptor sets
    /// and push constants in their recorded order, then dynamic state and
    /// buffers. `ops` provides one method per command; see the test below.
    pub fn replay(self: *const Shadow, ops: anytype) void {
        for (self.pipelines, 0..) |pipeline, bind_point| {
            if (pipeline != 0) ops.bindPipeline(@intCast(bind_point), pipeline);
        }
        for (self.descriptor_binds[0..self.descriptor_bind_count]) |*bind| ops.bindDescriptorSets(bind);
        for (self.push_constants[0..self.push_constant_count]) |*write| ops.pushConstants(write);
        replayRuns(abi.Viewport, ops, self.viewport_mask, &self.viewports, "setViewports");
        replayRuns(abi.Rect2D, ops, self.scissor_mask, &self.scissors, "setScissors");
        if (self.blend_constants) |*constants| ops.setBlendConstants(constants);
        if (self.depth_bias) |bias| ops.setDepthBias(bias[0], bias[1], bias[2]);
        if (self.depth_bounds) |bounds| ops.setDepthBounds(bounds[0], bounds[1]);
        replayStencil(ops, self.stencil_compare_mask, "setStencilCompareMask");
        replayStencil(ops, self.stencil_write_mask, "setStencilWriteMask");
        replayStencil(ops, self.stencil_reference, "setStencilReference");
        if (self.index) |index| ops.bindIndexBuffer(index.buffer, index.offset, index.index_type);
        var start: u32 = 0;
        while (start < max_vertex_bindings) {
            if (self.vertex_mask & (@as(u32, 1) << @intCast(start)) == 0) {
                start += 1;
                continue;
            }
            var end = start;
            while (end < max_vertex_bindings and self.vertex_mask & (@as(u32, 1) << @intCast(end)) != 0) end += 1;
            ops.bindVertexBuffers(start, self.vertex_buffers[start..end], self.vertex_offsets[start..end]);
            start = end;
        }
    }
};

fn replayRuns(comptime T: type, ops: anytype, mask: u16, values: *const [max_viewports]T, comptime method: []const u8) void {
    var start: u32 = 0;
    while (start < max_viewports) {
        if (mask & (@as(u16, 1) << @intCast(start)) == 0) {
            start += 1;
            continue;
        }
        var end = start;
        while (end < max_viewports and mask & (@as(u16, 1) << @intCast(end)) != 0) end += 1;
        @field(@TypeOf(ops.*), method)(ops, start, values[start..end]);
        start = end;
    }
}

fn replayStencil(ops: anytype, field: [2]?u32, comptime method: []const u8) void {
    const front = field[0];
    const back = field[1];
    if (front != null and back != null and front.? == back.?) {
        @field(@TypeOf(ops.*), method)(ops, stencil_face_front | stencil_face_back, front.?);
        return;
    }
    if (front) |value| @field(@TypeOf(ops.*), method)(ops, stencil_face_front, value);
    if (back) |value| @field(@TypeOf(ops.*), method)(ops, stencil_face_back, value);
}

/// The render pass instance a split must begin again, in host handles.
pub const PassBegin = struct {
    render_pass: u64 = 0,
    framebuffer: u64 = 0,
    render_area: abi.Rect2D = .{},
};

/// One guest command buffer between vkBeginCommandBuffer and its reset.
pub const Recording = struct {
    guest: u64 = 0,
    /// The guest's own real command buffer: the first segment.
    own: u64 = 0,
    guest_pool: u64 = 0,
    usage_flags: u32 = 0,
    primary: bool = true,
    block: Block = .none,
    budget_block_reported: bool = false,
    failed: bool = false,
    failure_reported: bool = false,
    in_pass: bool = false,
    pass_splittable: bool = false,
    pass: PassBegin = .{},
    active_queries: u32 = 0,
    conditional_rendering: bool = false,
    /// FSI draws in the segment now being recorded.
    segment_draws: u32 = 0,
    fsi_draws: u64 = 0,
    chunks: [max_chunks_per_command_buffer]u64 = [_]u64{0} ** max_chunks_per_command_buffer,
    chunk_count: usize = 0,
    /// FSI draws per segment: [0] is `own`, [i + 1] is `chunks[i]`.
    segment_fsi_draws: [max_chunks_per_command_buffer + 1]u32 = [_]u32{0} ** (max_chunks_per_command_buffer + 1),
    /// Sum of clipped scissor area for FSI draws in each segment. This work
    /// estimate prevents one command buffer from collecting many full-screen
    /// interlocked draws just because their count is low.
    segment_scissor_pixels: [max_chunks_per_command_buffer + 1]u64 = [_]u64{0} ** (max_chunks_per_command_buffer + 1),
    segment_max_draw_pixels: [max_chunks_per_command_buffer + 1]u64 = [_]u64{0} ** (max_chunks_per_command_buffer + 1),
    segment_sample_work: [max_chunks_per_command_buffer + 1]u64 = [_]u64{0} ** (max_chunks_per_command_buffer + 1),
    segment_max_draw_sample_work: [max_chunks_per_command_buffer + 1]u64 = [_]u64{0} ** (max_chunks_per_command_buffer + 1),
    /// The FSI pipeline (tracker fingerprint) of each segment's first and
    /// last draw, so a slow Metal command buffer names what it was running.
    segment_first_pipeline: [max_chunks_per_command_buffer + 1]u64 = [_]u64{0} ** (max_chunks_per_command_buffer + 1),
    segment_last_pipeline: [max_chunks_per_command_buffer + 1]u64 = [_]u64{0} ** (max_chunks_per_command_buffer + 1),
    segment_isolated: [max_chunks_per_command_buffer + 1]bool = [_]bool{false} ** (max_chunks_per_command_buffer + 1),
    shadow: Shadow = .{},

    pub fn begin(self: *Recording, guest: u64, own: u64, guest_pool: u64, usage_flags: u32, primary: bool) void {
        self.* = .{
            .guest = guest,
            .own = own,
            .guest_pool = guest_pool,
            .usage_flags = usage_flags,
            .primary = primary,
            .block = if (primary) .none else .secondary_command_buffer,
        };
    }

    /// The real command buffer the guest's next command must go to.
    pub fn target(self: *const Recording) u64 {
        return if (self.chunk_count == 0) self.own else self.chunks[self.chunk_count - 1];
    }

    pub fn noteBlock(self: *Recording, reason: Block) void {
        if (reason != .none and self.block == .none) self.block = reason;
    }

    pub fn beginPass(self: *Recording, pass: PassBegin, splittable_shape: bool, contents: u32) void {
        self.in_pass = true;
        self.pass = pass;
        self.pass_splittable = splittable_shape and contents == subpass_contents_inline;
    }

    pub fn endPass(self: *Recording) void {
        self.in_pass = false;
        self.pass_splittable = false;
    }

    /// Whether a split is allowed before the next draw.
    pub fn splitAllowed(self: *const Recording) Block {
        if (self.failed) return .recording_failed;
        if (self.block != .none) return self.block;
        if (!self.in_pass or !self.pass_splittable) return .render_pass_not_splittable;
        if (self.active_queries != 0) return .query_active;
        if (self.conditional_rendering) return .conditional_rendering_active;
        if (self.chunk_count == max_chunks_per_command_buffer) return .chunk_capacity;
        return .none;
    }

    /// A failed native boundary operation makes the recorded sequence unsafe
    /// to submit. The forwarder then suppresses later vkCmd calls and rejects
    /// end/submit with a deterministic initialization error.
    pub fn fail(self: *Recording) void {
        self.failed = true;
    }

    /// Account one FSI draw in the current segment.
    pub fn noteFsiDraw(self: *Recording, pipeline_hash: u64, scissor_pixels: u64) void {
        self.noteFsiDrawSamples(pipeline_hash, scissor_pixels, 1);
    }

    pub fn noteFsiDrawSamples(self: *Recording, pipeline_hash: u64, scissor_pixels: u64, raster_samples: u32) void {
        const sample_work = scissor_pixels *| @max(@as(u64, raster_samples), 1);
        self.segment_draws +|= 1;
        self.fsi_draws +|= 1;
        self.segment_fsi_draws[self.chunk_count] +|= 1;
        self.segment_scissor_pixels[self.chunk_count] +|= scissor_pixels;
        self.segment_max_draw_pixels[self.chunk_count] = @max(self.segment_max_draw_pixels[self.chunk_count], scissor_pixels);
        self.segment_sample_work[self.chunk_count] +|= sample_work;
        self.segment_max_draw_sample_work[self.chunk_count] = @max(self.segment_max_draw_sample_work[self.chunk_count], sample_work);
        if (self.segment_first_pipeline[self.chunk_count] == 0) self.segment_first_pipeline[self.chunk_count] = pipeline_hash;
        self.segment_last_pipeline[self.chunk_count] = pipeline_hash;
    }

    /// Make `chunk` the new recording target, after the caller has closed
    /// the old one and prepared the new one.
    pub fn commitSplit(self: *Recording, chunk: u64) void {
        self.chunks[self.chunk_count] = chunk;
        self.chunk_count += 1;
        self.segment_draws = 0;
        self.budget_block_reported = false;
    }

    /// The real command buffers that carry this recording, in order.
    pub fn segments(self: *const Recording, out: []u64) usize {
        if (out.len == 0) return 0;
        out[0] = self.own;
        const count = @min(self.chunk_count, out.len - 1);
        @memcpy(out[1 .. count + 1], self.chunks[0..count]);
        return count + 1;
    }
};

/// The bridge-owned command buffers chunks are recorded into. A chunk goes
/// back to the free list only after the submission that carried it has
/// completed (`release_after` against the completed serial), so a guest that
/// resets early can never make the bridge re-record a buffer the GPU is
/// still executing.
pub const ChunkPool = struct {
    // Retain enough continuation buffers for the bounded in-flight queue,
    // even if every outstanding guest recording reaches its full chain size.
    pub const capacity = max_chunks_per_command_buffer * max_in_flight_segments;
    pub const Entry = struct {
        handle: u64 = 0,
        in_use: bool = false,
        /// A driver operation left this command buffer's recording state
        /// uncertain. Keep its handle for command-pool destruction, but never
        /// hand it to another recording.
        poisoned: bool = false,
        /// Submission serial that must complete before reuse; 0 = none.
        release_after: u64 = 0,
        last_submit: u64 = 0,
    };

    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,
    allocated: u64 = 0,
    reuses: u64 = 0,
    exhausted: u64 = 0,
    poisoned_count: u64 = 0,

    /// A free chunk whose last submission is complete, or null when the
    /// caller must allocate (or give up when the pool is full).
    pub fn acquire(self: *ChunkPool, completed_serial: u64) ?u64 {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.poisoned or entry.in_use or entry.release_after > completed_serial) continue;
            entry.in_use = true;
            entry.release_after = 0;
            entry.last_submit = 0;
            self.reuses +|= 1;
            return entry.handle;
        }
        return null;
    }

    pub fn canGrow(self: *const ChunkPool) bool {
        return self.count < capacity;
    }

    pub fn add(self: *ChunkPool, handle: u64) bool {
        if (self.count == capacity) {
            self.exhausted +|= 1;
            return false;
        }
        self.entries[self.count] = .{ .handle = handle, .in_use = true };
        self.count += 1;
        self.allocated +|= 1;
        return true;
    }

    pub fn noteSubmitted(self: *ChunkPool, handle: u64, serial: u64) void {
        if (self.find(handle)) |entry| entry.last_submit = serial;
    }

    pub fn release(self: *ChunkPool, handle: u64) void {
        const entry = self.find(handle) orelse return;
        if (entry.poisoned) return;
        entry.in_use = false;
        entry.release_after = entry.last_submit;
    }

    /// Quarantine a handle whose driver-side recording state is uncertain.
    /// Keeping it in the pool lets vkDestroyCommandPool reclaim it at teardown
    /// without risking a reset/re-record on a potentially invalid buffer.
    pub fn discard(self: *ChunkPool, handle: u64) void {
        const entry = self.find(handle) orelse return;
        if (entry.poisoned) return;
        entry.poisoned = true;
        entry.in_use = false;
        self.poisoned_count +|= 1;
    }

    fn find(self: *ChunkPool, handle: u64) ?*Entry {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.handle == handle) return entry;
        }
        return null;
    }
};

const TestOps = struct {
    log: [64][]const u8 = undefined,
    count: usize = 0,
    detail: [64]u64 = [_]u64{0} ** 64,

    fn note(self: *TestOps, name: []const u8, value: u64) void {
        self.log[self.count] = name;
        self.detail[self.count] = value;
        self.count += 1;
    }
    fn bindPipeline(self: *TestOps, bind_point: u32, pipeline: u64) void {
        self.note(if (bind_point == bind_point_graphics) "pipeline.graphics" else "pipeline.compute", pipeline);
    }
    fn bindDescriptorSets(self: *TestOps, bind: *const DescriptorBind) void {
        self.note("descriptors", @as(u64, bind.first_set) * 100 + bind.set_count);
    }
    fn pushConstants(self: *TestOps, write: *const PushConstants) void {
        self.note("push", write.bytes[0]);
    }
    fn setViewports(self: *TestOps, first: u32, viewports: []const abi.Viewport) void {
        self.note("viewports", @as(u64, first) * 100 + viewports.len);
    }
    fn setScissors(self: *TestOps, first: u32, scissors: []const abi.Rect2D) void {
        self.note("scissors", @as(u64, first) * 100 + scissors.len);
    }
    fn setBlendConstants(self: *TestOps, constants: *const [4]f32) void {
        self.note("blend", @intFromFloat(constants[0]));
    }
    fn setDepthBias(self: *TestOps, constant: f32, clamp: f32, slope: f32) void {
        _ = clamp;
        _ = slope;
        self.note("depth_bias", @intFromFloat(constant));
    }
    fn setDepthBounds(self: *TestOps, min: f32, max: f32) void {
        _ = min;
        self.note("depth_bounds", @intFromFloat(max));
    }
    fn setStencilCompareMask(self: *TestOps, face: u32, value: u32) void {
        self.note("stencil_compare", @as(u64, face) * 1000 + value);
    }
    fn setStencilWriteMask(self: *TestOps, face: u32, value: u32) void {
        self.note("stencil_write", @as(u64, face) * 1000 + value);
    }
    fn setStencilReference(self: *TestOps, face: u32, value: u32) void {
        self.note("stencil_reference", @as(u64, face) * 1000 + value);
    }
    fn bindIndexBuffer(self: *TestOps, buffer: u64, offset: u64, index_type: u32) void {
        _ = offset;
        _ = index_type;
        self.note("index", buffer);
    }
    fn bindVertexBuffers(self: *TestOps, first: u32, buffers: []const u64, offsets: []const u64) void {
        _ = offsets;
        self.note("vertex", @as(u64, first) * 100 + buffers.len);
    }
};

test "a split replays exactly the state an FSI draw was recorded with" {
    var shadow: Shadow = .{};
    try std.testing.expect(shadow.bindPipeline(bind_point_graphics, 0xA1));
    try std.testing.expect(shadow.bindPipeline(bind_point_compute, 0xC1));
    try std.testing.expectEqual(Block.none, shadow.bindDescriptorSets(bind_point_graphics, 0x10, 0, &.{ 0x100, 0x101, 0x102 }, &.{}));
    // Xenia rebinds single sets per draw: set 1 alone does not supersede the
    // three-set bind, a later bind of sets 0-2 does.
    try std.testing.expectEqual(Block.none, shadow.bindDescriptorSets(bind_point_graphics, 0x10, 1, &.{0x111}, &.{}));
    try std.testing.expectEqual(@as(usize, 2), shadow.descriptor_bind_count);
    try std.testing.expectEqual(Block.none, shadow.bindDescriptorSets(bind_point_graphics, 0x10, 2, &.{0x122}, &.{ 7, 8 }));
    try std.testing.expectEqual(Block.none, shadow.bindDescriptorSets(bind_point_graphics, 0x10, 2, &.{0x123}, &.{}));
    try std.testing.expectEqual(@as(usize, 3), shadow.descriptor_bind_count);
    try std.testing.expectEqual(Block.none, shadow.pushConstants(0x10, 0x10, 0, &.{ 5, 6, 7, 8 }));
    try std.testing.expectEqual(Block.none, shadow.pushConstants(0x10, 0x10, 0, &.{ 9, 6, 7, 8 }));
    try std.testing.expectEqual(@as(usize, 1), shadow.push_constant_count);
    try std.testing.expectEqual(Block.none, shadow.setViewports(0, &.{.{ .width = 1152, .height = 640 }}));
    try std.testing.expectEqual(Block.none, shadow.setScissors(0, &.{.{ .extent = .{ .width = 1152, .height = 640 } }}));
    Shadow.setStencil(&shadow.stencil_reference, stencil_face_front | stencil_face_back, 0x80);
    Shadow.setStencil(&shadow.stencil_write_mask, stencil_face_front, 0xff);
    shadow.index = .{ .buffer = 0x301, .offset = 0, .index_type = 1 };
    try std.testing.expectEqual(Block.none, shadow.bindVertexBuffers(2, &.{ 0x401, 0x402 }, &.{ 0, 16 }));

    var ops: TestOps = .{};
    shadow.replay(&ops);
    const expected = [_][]const u8{ "pipeline.graphics", "pipeline.compute", "descriptors", "descriptors", "descriptors", "push", "viewports", "scissors", "stencil_write", "stencil_reference", "index", "vertex" };
    try std.testing.expectEqual(expected.len, ops.count);
    for (expected, 0..) |name, index| try std.testing.expectEqualStrings(name, ops.log[index]);
    // The three-set bind, then set 1, then the latest set 2.
    try std.testing.expectEqual(@as(u64, 3), ops.detail[2]);
    try std.testing.expectEqual(@as(u64, 101), ops.detail[3]);
    try std.testing.expectEqual(@as(u64, 201), ops.detail[4]);
    try std.testing.expectEqual(@as(u64, 9), ops.detail[5]);
    try std.testing.expectEqual(@as(u64, 1000 + 0xff), ops.detail[8]);
    try std.testing.expectEqual(@as(u64, 3000 + 0x80), ops.detail[9]);
    try std.testing.expectEqual(@as(u64, 202), ops.detail[11]);
}

test "a recording splits only inside an inline attachment-less pass with no query open" {
    var recording: Recording = .{};
    recording.begin(0x50, 0x5000, 0x60, 1, true);
    try std.testing.expectEqual(Block.render_pass_not_splittable, recording.splitAllowed());
    recording.beginPass(.{ .render_pass = 0x70, .framebuffer = 0x71, .render_area = .{ .extent = .{ .width = 8192, .height = 8192 } } }, true, subpass_contents_inline);
    try std.testing.expectEqual(Block.none, recording.splitAllowed());
    recording.active_queries = 1;
    try std.testing.expectEqual(Block.query_active, recording.splitAllowed());
    recording.active_queries = 0;
    recording.endPass();
    // A host render target pass (attachments) is never split.
    recording.beginPass(.{ .render_pass = 0x72 }, false, subpass_contents_inline);
    try std.testing.expectEqual(Block.render_pass_not_splittable, recording.splitAllowed());
    recording.endPass();
    // Secondary-buffer contents cannot continue in a new primary.
    recording.beginPass(.{ .render_pass = 0x70 }, true, 1);
    try std.testing.expectEqual(Block.render_pass_not_splittable, recording.splitAllowed());
    recording.endPass();
    recording.noteBlock(.unrecorded_command);
    recording.beginPass(.{ .render_pass = 0x70 }, true, subpass_contents_inline);
    try std.testing.expectEqual(Block.unrecorded_command, recording.splitAllowed());

    var secondary: Recording = .{};
    secondary.begin(0x51, 0x5100, 0x60, 0, false);
    secondary.beginPass(.{ .render_pass = 0x70 }, true, subpass_contents_inline);
    try std.testing.expectEqual(Block.secondary_command_buffer, secondary.splitAllowed());
}

test "segments list the guest's own buffer, then each chunk, with their FSI draws" {
    var recording: Recording = .{};
    recording.begin(0x50, 0x5000, 0x60, 1, true);
    recording.beginPass(.{ .render_pass = 0x70 }, true, subpass_contents_inline);
    for (0..3) |_| recording.noteFsiDraw(0xAAA, 256);
    recording.commitSplit(0x9001);
    try std.testing.expectEqual(@as(u64, 0x9001), recording.target());
    try std.testing.expectEqual(@as(u32, 0), recording.segment_draws);
    recording.noteFsiDraw(0xBBB, 512);
    recording.noteFsiDraw(0xCCC, 1024);
    recording.commitSplit(0x9002);
    recording.noteFsiDraw(0xDDD, 2048);
    var out: [8]u64 = undefined;
    const count = recording.segments(&out);
    try std.testing.expectEqualSlices(u64, &.{ 0x5000, 0x9001, 0x9002 }, out[0..count]);
    try std.testing.expectEqualSlices(u32, &.{ 3, 2, 1 }, recording.segment_fsi_draws[0..3]);
    try std.testing.expectEqualSlices(u64, &.{ 768, 1536, 2048 }, recording.segment_scissor_pixels[0..3]);
    try std.testing.expectEqualSlices(u64, &.{ 256, 1024, 2048 }, recording.segment_max_draw_pixels[0..3]);
    try std.testing.expectEqualSlices(u64, &.{ 0xAAA, 0xBBB, 0xDDD }, recording.segment_first_pipeline[0..3]);
    try std.testing.expectEqualSlices(u64, &.{ 0xAAA, 0xCCC, 0xDDD }, recording.segment_last_pipeline[0..3]);
    try std.testing.expectEqual(@as(u64, 6), recording.fsi_draws);
}

test "the split chain supports thousands of continuations beyond one Vulkan submit width" {
    var recording: Recording = .{};
    recording.begin(0x50, 0x5000, 0x60, 1, true);
    recording.beginPass(.{ .render_pass = 0x70 }, true, subpass_contents_inline);
    for (0..max_chunks_per_command_buffer) |index| recording.commitSplit(@intCast(index + 1));
    try std.testing.expectEqual(max_chunks_per_command_buffer, recording.chunk_count);
    try std.testing.expectEqual(Block.chunk_capacity, recording.splitAllowed());
    var out: [max_chunks_per_command_buffer + 1]u64 = undefined;
    try std.testing.expectEqual(max_chunks_per_command_buffer + 1, recording.segments(&out));
    try std.testing.expectEqual(@as(u64, 1), out[1]);
    try std.testing.expectEqual(@as(u64, max_chunks_per_command_buffer), out[max_chunks_per_command_buffer]);
}

test "a chunk is reused only after the submission that carried it has completed" {
    var pool: ChunkPool = .{};
    try std.testing.expect(pool.acquire(0) == null);
    try std.testing.expect(pool.add(0xA));
    pool.noteSubmitted(0xA, 7);
    pool.release(0xA);
    try std.testing.expect(pool.acquire(6) == null);
    try std.testing.expectEqual(@as(?u64, 0xA), pool.acquire(7));
    // Released without ever being submitted: immediately reusable.
    pool.release(0xA);
    try std.testing.expectEqual(@as(?u64, 0xA), pool.acquire(0));
}

test "a chunk with an uncertain driver recording state is quarantined" {
    var pool: ChunkPool = .{};
    try std.testing.expect(pool.add(0xA));
    pool.discard(0xA);
    pool.release(0xA);
    try std.testing.expectEqual(@as(u64, 1), pool.poisoned_count);
    try std.testing.expect(pool.acquire(0) == null);
    try std.testing.expect(pool.canGrow());
}

test "descriptor and push-constant capacity limits block a split instead of losing state" {
    var shadow: Shadow = .{};
    // Two-set binds at successive first sets overlap without covering each
    // other, so all of them stay live on both bind points.
    for (0..7) |first| {
        try std.testing.expectEqual(Block.none, shadow.bindDescriptorSets(bind_point_graphics, 0x10, @intCast(first), &.{ 1, 2 }, &.{}));
        try std.testing.expectEqual(Block.none, shadow.bindDescriptorSets(bind_point_compute, 0x11, @intCast(first), &.{ 1, 2 }, &.{}));
    }
    try std.testing.expectEqual(Block.none, shadow.bindDescriptorSets(bind_point_graphics, 0x10, 0, &.{1}, &.{}));
    try std.testing.expectEqual(Block.none, shadow.bindDescriptorSets(bind_point_compute, 0x11, 0, &.{1}, &.{}));
    try std.testing.expectEqual(max_descriptor_binds, shadow.descriptor_bind_count);
    try std.testing.expectEqual(Block.descriptor_bind_capacity, shadow.bindDescriptorSets(bind_point_graphics, 0x10, 1, &.{1}, &.{}));
    // A bind of all eight graphics sets supersedes the eight graphics binds;
    // the eight compute binds stay.
    try std.testing.expectEqual(Block.none, shadow.bindDescriptorSets(bind_point_graphics, 0x10, 0, &.{ 1, 2, 3, 4, 5, 6, 7, 8 }, &.{}));
    try std.testing.expectEqual(@as(usize, 9), shadow.descriptor_bind_count);
    var push: Shadow = .{};
    for (0..max_push_constant_calls) |index| {
        try std.testing.expectEqual(Block.none, push.pushConstants(0x10, 0x10, @intCast(index * 4), &.{1}));
    }
    try std.testing.expectEqual(Block.push_constant_capacity, push.pushConstants(0x10, 0x10, 200, &.{1}));
    try std.testing.expectEqual(Block.descriptor_bind_shape, shadow.bindDescriptorSets(bind_point_graphics, 0x10, 0, &.{}, &.{}));
}
