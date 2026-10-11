//! Small, pure observations for Xenia's Vulkan fragment-shader-interlock path.
//!
//! Vulkan device creation can negotiate fragment interlock even when Xenia
//! later falls back to host render targets. The shared-memory/EDRAM descriptor
//! layout is a stronger signal: Xenia creates its three-binding form only
//! after selecting the FSI render-target path.

const std = @import("std");
const spirv_stage = @import("../spirv_stage.zig");

pub const shader_identity_capacity: usize = 512;
pub const pipeline_identity_capacity: usize = 512;
pub const command_state_capacity: usize = 512;
pub const recent_submission_capacity: usize = 16;
const command_state_ways: usize = 4;
const command_state_sets: usize = command_state_capacity / command_state_ways;

pub const DescriptorBinding = struct {
    binding: u32,
    descriptor_type: u32,
    descriptor_count: u32,
    stage_flags: u32,
    immutable_samplers: u64 = 0,
};

pub const STORAGE_BUFFER_DESCRIPTOR_TYPE: u32 = 7;
pub const FRAGMENT_SHADER_STAGE: u32 = 0x10;

pub const ShaderIdentity = struct {
    id: u64 = 0,
    guest_handle: u64 = 0,
    spirv_hash: u64 = 0,
    code_bytes: u32 = 0,
    execution_model_mask: u8 = 0,
    capability_mask: u8 = 0,
    begin_ops: u32 = 0,
    end_ops: u32 = 0,
};

/// A stable fingerprint for a graphics pipeline's FSI shader stage(s). The
/// first module is retained for direct lookup; the combined hash still
/// distinguishes unusual pipelines containing more than one interlock stage.
pub const PipelineIdentity = struct {
    uses_fsi: bool = false,
    shader_count: u8 = 0,
    stage_flags_or: u32 = 0,
    module_id: u64 = 0,
    shader_hash: u64 = 0,
    combined_hash: u64 = 0,
    capability_mask: u8 = 0,
    begin_ops: u32 = 0,
    end_ops: u32 = 0,
    /// Host pass variant fixed to this pipeline's raster sample count.
    /// Zero when no MoltenVK adaptation is needed.
    raster_pass: u64 = 0,
    rasterization_samples: u32 = 0,

    pub fn include(self: *PipelineIdentity, stage_flags: u32, shader: ShaderIdentity) void {
        if (!self.uses_fsi) self.combined_hash = 14695981039346656037;
        self.uses_fsi = true;
        self.shader_count +|= 1;
        self.stage_flags_or |= stage_flags;
        if (self.module_id == 0) {
            self.module_id = shader.id;
            self.shader_hash = shader.spirv_hash;
        }
        self.combined_hash = mixHash(self.combined_hash, stage_flags);
        self.combined_hash = mixHash(self.combined_hash, shader.id);
        self.combined_hash = mixHash(self.combined_hash, shader.spirv_hash);
        self.capability_mask |= shader.capability_mask;
        self.begin_ops +|= shader.begin_ops;
        self.end_ops +|= shader.end_ops;
    }
};

pub const BufferBindingEvidence = struct {
    binding: u32 = 0,
    descriptor_count: u32 = 0,
    guest_buffer: u64 = 0,
    native_buffer: u64 = 0,
    guest_offset: u64 = 0,
    guest_range: u64 = 0,
    offset: u64 = 0,
    range: u64 = 0,
    repaired: bool = false,
};

pub const DescriptorUpdateEvidence = struct {
    update_call: u64 = 0,
    guest_set: u64 = 0,
    native_set: u64 = 0,
    binding_count: u8 = 0,
    binding_mask: u8 = 0,
    bindings: [3]BufferBindingEvidence = [_]BufferBindingEvidence{.{}} ** 3,
};

pub const DrawKind = enum(u8) {
    direct,
    indexed,
    indirect,
    indexed_indirect,
    indirect_count,
    indexed_indirect_count,
};

/// Bounded direct-draw arguments kept with the last submitted FSI draw. The
/// indirect forms intentionally leave these invalid because reading their
/// guest argument buffers here would add work and can race GPU writes.
pub const DrawParameters = struct {
    valid: bool = false,
    element_count: u64 = 0,
    instance_count: u64 = 0,
    first_element: u64 = 0,
    vertex_offset: i32 = 0,
    first_instance: u64 = 0,
};

/// Where the forwarder learned which guest image an FSI draw targets. This
/// stays diagnostic only: Vulkan still receives the guest's original
/// attachments and Rosette does not substitute a framebuffer.
pub const TargetSource = enum(u8) {
    unknown,
    render_pass,
    dynamic_rendering,
    inherited_secondary,
};

pub const DrawEvidence = struct {
    command_buffer: u64 = 0,
    pipeline_real: u64 = 0,
    module_id: u64 = 0,
    shader_hash: u64 = 0,
    pipeline_hash: u64 = 0,
    stage_flags: u32 = 0,
    target_image: u64 = 0,
    target_source: TargetSource = .unknown,
    kind: DrawKind = .direct,
    parameters: DrawParameters = .{},
    command_buffer_draw_ordinal: u64 = 0,
    draw_ordinal: u64 = 0,
};

pub const SubmissionEvidence = struct {
    queue_submit_ordinal: u64 = 0,
    batch_index: u32 = 0,
    draw: DrawEvidence = .{},
    fsi_draws_in_command_buffer: u64 = 0,
};

const PipelineRecord = struct {
    real_handle: u64 = 0,
    identity: PipelineIdentity = .{},
    tombstone: bool = false,
};

const CommandState = struct {
    command_buffer: u64 = 0,
    active_fsi_pipeline: bool = false,
    pipeline_real: u64 = 0,
    identity: PipelineIdentity = .{},
    target_image: u64 = 0,
    target_source: TargetSource = .unknown,
    fsi_draw_count: u64 = 0,
    last_draw: DrawEvidence = .{},
};

/// Bounded identity and event tracker for FSI rendering. Its command-buffer
/// lookup is direct-mapped so ordinary draw forwarding pays one indexed read;
/// a collision is counted and replaces diagnostic state only. It never alters
/// Vulkan resources or decides whether a draw is forwarded.
pub const Tracker = struct {
    shaders: [shader_identity_capacity]ShaderIdentity = [_]ShaderIdentity{.{}} ** shader_identity_capacity,
    shader_count: usize = 0,
    shader_cursor: usize = 0,
    shader_ids_issued: u64 = 0,
    shader_identity_overflow: u64 = 0,
    pipelines: [pipeline_identity_capacity]PipelineRecord = [_]PipelineRecord{.{}} ** pipeline_identity_capacity,
    pipeline_count: usize = 0,
    pipeline_cursor: usize = 0,
    pipeline_candidates: u64 = 0,
    pipeline_native_successes: u64 = 0,
    pipeline_native_failures: u64 = 0,
    pipeline_identity_overflow: u64 = 0,
    last_pipeline_real: u64 = 0,
    last_pipeline: PipelineIdentity = .{},
    last_pipeline_native_success: bool = false,
    command_states: [command_state_capacity]CommandState = [_]CommandState{.{}} ** command_state_capacity,
    command_state_collisions: u64 = 0,
    pipeline_binds: u64 = 0,
    draws: u64 = 0,
    submitted_command_buffers: u64 = 0,
    submitted_draws: u64 = 0,
    descriptor_updates: u64 = 0,
    target_updates_before_fsi_pipeline: u64 = 0,
    target_propagations_on_bind: u64 = 0,
    dynamic_targets_resolved: u64 = 0,
    dynamic_targets_unresolved: u64 = 0,
    secondary_targets_inherited: u64 = 0,
    secondary_targets_unresolved: u64 = 0,
    last_descriptor_update: DescriptorUpdateEvidence = .{},
    last_draw: DrawEvidence = .{},
    last_submission: SubmissionEvidence = .{},
    recent_submissions: [recent_submission_capacity]SubmissionEvidence = [_]SubmissionEvidence{.{}} ** recent_submission_capacity,
    recent_submission_count: usize = 0,
    recent_submission_next: usize = 0,

    pub fn rememberShader(self: *Tracker, guest_handle: u64, spirv_hash: u64, code_bytes: u32, module: anytype) ?ShaderIdentity {
        if (guest_handle == 0 or !module.usesFragmentShaderInterlock()) return null;
        for (&self.shaders) |*record| {
            if (record.guest_handle != guest_handle) continue;
            self.shader_ids_issued +|= 1;
            record.* = shaderIdentity(self.shader_ids_issued, guest_handle, spirv_hash, code_bytes, module);
            return record.*;
        }
        for (&self.shaders) |*record| {
            if (record.guest_handle != 0) continue;
            self.shader_ids_issued +|= 1;
            record.* = shaderIdentity(self.shader_ids_issued, guest_handle, spirv_hash, code_bytes, module);
            self.shader_count += 1;
            return record.*;
        }
        self.shader_identity_overflow +|= 1;
        const slot = self.shader_cursor;
        self.shader_cursor = (self.shader_cursor + 1) % self.shaders.len;
        self.shader_ids_issued +|= 1;
        self.shaders[slot] = shaderIdentity(self.shader_ids_issued, guest_handle, spirv_hash, code_bytes, module);
        return self.shaders[slot];
    }

    pub fn forgetShader(self: *Tracker, guest_handle: u64) void {
        for (&self.shaders) |*record| {
            if (record.guest_handle != guest_handle) continue;
            record.* = .{};
            self.shader_count -|= 1;
            return;
        }
    }

    pub fn findShader(self: *const Tracker, guest_handle: u64) ?ShaderIdentity {
        if (guest_handle == 0) return null;
        for (self.shaders) |record| {
            if (record.guest_handle == guest_handle) return record;
        }
        return null;
    }

    /// Record the host outcome after the real pipeline call. Failed pipelines
    /// remain visible in totals but are not made bindable in the identity map.
    pub fn notePipelineCreated(self: *Tracker, real_handle: u64, identity: PipelineIdentity, native_success: bool) void {
        if (!identity.uses_fsi) return;
        self.pipeline_candidates +|= 1;
        self.last_pipeline_real = real_handle;
        self.last_pipeline = identity;
        self.last_pipeline_native_success = native_success;
        if (!native_success or real_handle == 0) {
            self.pipeline_native_failures +|= 1;
            return;
        }
        self.pipeline_native_successes +|= 1;
        const start = handleHash(real_handle) & (self.pipelines.len - 1);
        var tombstone: ?usize = null;
        for (0..self.pipelines.len) |probe| {
            const slot = (start + probe) & (self.pipelines.len - 1);
            const record = &self.pipelines[slot];
            if (record.real_handle == real_handle) {
                record.identity = identity;
                return;
            }
            if (record.real_handle == 0) {
                if (record.tombstone) {
                    if (tombstone == null) tombstone = slot;
                    continue;
                }
                const destination = tombstone orelse slot;
                self.pipelines[destination] = .{ .real_handle = real_handle, .identity = identity };
                self.pipeline_count += 1;
                return;
            }
        }
        self.pipeline_identity_overflow +|= 1;
        const slot = tombstone orelse self.pipeline_cursor;
        self.pipeline_cursor = (self.pipeline_cursor + 1) % self.pipelines.len;
        self.pipelines[slot] = .{ .real_handle = real_handle, .identity = identity };
    }

    pub fn forgetPipeline(self: *Tracker, real_handle: u64) void {
        const start = handleHash(real_handle) & (self.pipelines.len - 1);
        for (0..self.pipelines.len) |probe| {
            const slot = (start + probe) & (self.pipelines.len - 1);
            const record = &self.pipelines[slot];
            if (record.real_handle == real_handle) {
                record.* = .{ .tombstone = true };
                self.pipeline_count -|= 1;
                return;
            }
            if (record.real_handle == 0 and !record.tombstone) return;
        }
    }

    pub fn findPipeline(self: *const Tracker, real_handle: u64) ?PipelineIdentity {
        if (real_handle == 0) return null;
        const start = handleHash(real_handle) & (self.pipelines.len - 1);
        for (0..self.pipelines.len) |probe| {
            const record = self.pipelines[(start + probe) & (self.pipelines.len - 1)];
            if (record.real_handle == real_handle) return record.identity;
            if (record.real_handle == 0 and !record.tombstone) return null;
        }
        return null;
    }

    /// `pipeline_real` is zero or a non-FSI pipeline when an existing binding
    /// is replaced. This preserves prior draw evidence while clearing the
    /// active stage used to classify subsequent draws.
    pub fn bindPipeline(self: *Tracker, command_buffer: u64, pipeline_real: u64) void {
        if (command_buffer == 0) return;
        const identity = self.findPipeline(pipeline_real);
        var state = self.findCommandState(command_buffer);
        if (state == null and identity != null) state = self.allocateCommandState(command_buffer);
        const entry = state orelse return;
        entry.active_fsi_pipeline = identity != null;
        entry.pipeline_real = if (identity != null) pipeline_real else 0;
        entry.identity = identity orelse .{};
        if (identity != null) self.pipeline_binds +|= 1;
    }

    pub fn setTarget(self: *Tracker, command_buffer: u64, target_image: u64, source: TargetSource) void {
        if (command_buffer == 0) return;
        const state = self.findCommandState(command_buffer) orelse {
            self.target_updates_before_fsi_pipeline +|= 1;
            return;
        };
        const resolved_source: TargetSource = if (target_image == 0) .unknown else source;
        const changed = state.target_image != target_image or state.target_source != resolved_source;
        state.target_image = target_image;
        state.target_source = resolved_source;
        // Traditional render-pass state is observed before the FSI pipeline
        // is bound. Secondary buffers may also be assigned their primary's
        // target after their draws have already been recorded. Repair only
        // the latest evidence for this same command buffer; the Vulkan work
        // and the actual pipeline state remain untouched.
        if (state.last_draw.command_buffer == command_buffer and state.last_draw.target_image == 0 and target_image != 0) {
            state.last_draw.target_image = target_image;
            state.last_draw.target_source = source;
            if (self.last_draw.command_buffer == command_buffer and self.last_draw.draw_ordinal == state.last_draw.draw_ordinal) {
                self.last_draw = state.last_draw;
            }
        }
        if (changed and source == .dynamic_rendering and target_image != 0) self.dynamic_targets_resolved +|= 1;
        if (changed and source == .inherited_secondary and target_image != 0) self.secondary_targets_inherited +|= 1;
    }

    pub fn noteTargetPropagationOnBind(self: *Tracker) void {
        self.target_propagations_on_bind +|= 1;
    }

    pub fn isFsiPipelineBound(self: *const Tracker, command_buffer: u64) bool {
        const state = self.findCommandStateConst(command_buffer) orelse return false;
        return state.active_fsi_pipeline;
    }

    pub fn targetMatches(self: *const Tracker, command_buffer: u64, target_image: u64, source: TargetSource) bool {
        const state = self.findCommandStateConst(command_buffer) orelse return false;
        const resolved_source: TargetSource = if (target_image == 0) .unknown else source;
        return state.target_image == target_image and state.target_source == resolved_source;
    }

    pub fn noteDynamicTargetUnresolved(self: *Tracker) void {
        self.dynamic_targets_unresolved +|= 1;
    }

    pub fn noteSecondaryTargetUnresolved(self: *Tracker, command_buffer: u64) void {
        const state = self.findCommandState(command_buffer) orelse return;
        if (state.fsi_draw_count != 0) self.secondary_targets_unresolved +|= 1;
    }

    pub fn noteDraw(self: *Tracker, command_buffer: u64) ?DrawEvidence {
        return self.noteDrawKind(command_buffer, .direct);
    }

    pub fn noteDrawKind(self: *Tracker, command_buffer: u64, kind: DrawKind) ?DrawEvidence {
        return self.noteDrawWithParameters(command_buffer, kind, .{});
    }

    pub fn noteDrawWithParameters(self: *Tracker, command_buffer: u64, kind: DrawKind, parameters: DrawParameters) ?DrawEvidence {
        if (command_buffer == 0) return null;
        const state = self.findCommandState(command_buffer) orelse return null;
        if (!state.active_fsi_pipeline) return null;
        self.draws +|= 1;
        state.fsi_draw_count +|= 1;
        state.last_draw = .{
            .command_buffer = command_buffer,
            .pipeline_real = state.pipeline_real,
            .module_id = state.identity.module_id,
            .shader_hash = state.identity.shader_hash,
            .pipeline_hash = state.identity.combined_hash,
            .stage_flags = state.identity.stage_flags_or,
            .target_image = state.target_image,
            .target_source = state.target_source,
            .kind = kind,
            .parameters = parameters,
            .command_buffer_draw_ordinal = state.fsi_draw_count,
            .draw_ordinal = self.draws,
        };
        self.last_draw = state.last_draw;
        return state.last_draw;
    }

    pub fn resetCommandBuffer(self: *Tracker, command_buffer: u64) void {
        if (command_buffer == 0) return;
        if (self.findCommandState(command_buffer)) |state| state.* = .{ .command_buffer = command_buffer };
    }

    pub fn forgetCommandBuffer(self: *Tracker, command_buffer: u64) void {
        if (command_buffer == 0) return;
        if (self.findCommandState(command_buffer)) |state| state.* = .{};
    }

    pub fn mergeCommandBuffer(self: *Tracker, destination: u64, source: u64) void {
        if (destination == 0 or source == 0 or destination == source) return;
        const source_state = self.findCommandState(source) orelse return;
        if (source_state.fsi_draw_count == 0) return;
        const destination_state = self.findCommandState(destination) orelse self.allocateCommandState(destination) orelse return;
        destination_state.active_fsi_pipeline = false;
        destination_state.pipeline_real = 0;
        destination_state.fsi_draw_count +|= source_state.fsi_draw_count;
        destination_state.last_draw = source_state.last_draw;
        destination_state.last_draw.command_buffer = destination;
        destination_state.last_draw.command_buffer_draw_ordinal = destination_state.fsi_draw_count;
        destination_state.target_image = source_state.target_image;
        destination_state.target_source = source_state.target_source;
    }

    /// Called only after the host accepted the queue submission. A draw in a
    /// secondary command buffer is first merged into its primary, so this
    /// record identifies work that was actually handed to the device.
    pub fn noteSubmitted(self: *Tracker, command_buffer: u64, queue_submit_ordinal: u64, batch_index: u32) ?SubmissionEvidence {
        if (command_buffer == 0) return null;
        const state = self.findCommandState(command_buffer) orelse return null;
        if (state.fsi_draw_count == 0) return null;
        self.submitted_command_buffers +|= 1;
        self.submitted_draws +|= state.fsi_draw_count;
        const evidence = SubmissionEvidence{
            .queue_submit_ordinal = queue_submit_ordinal,
            .batch_index = batch_index,
            .draw = state.last_draw,
            .fsi_draws_in_command_buffer = state.fsi_draw_count,
        };
        self.last_submission = evidence;
        self.recent_submissions[self.recent_submission_next] = evidence;
        self.recent_submission_next = (self.recent_submission_next + 1) % self.recent_submissions.len;
        self.recent_submission_count = @min(self.recent_submission_count + 1, self.recent_submissions.len);
        return evidence;
    }

    /// Accepted FSI command buffers in chronological order, oldest first.
    /// A GPU fault is reported asynchronously, so the last accepted buffer
    /// alone must never be presented as the one that hung the device.
    pub fn recentSubmission(self: *const Tracker, oldest_index: usize) ?SubmissionEvidence {
        if (oldest_index >= self.recent_submission_count) return null;
        const oldest = (self.recent_submission_next + self.recent_submissions.len - self.recent_submission_count) % self.recent_submissions.len;
        return self.recent_submissions[(oldest + oldest_index) % self.recent_submissions.len];
    }

    pub fn noteDescriptorUpdate(self: *Tracker, evidence: DescriptorUpdateEvidence) void {
        self.descriptor_updates +|= 1;
        self.last_descriptor_update = evidence;
    }

    fn commandStart(command_buffer: u64) usize {
        return (handleHash(command_buffer) & (command_state_sets - 1)) * command_state_ways;
    }

    fn findCommandState(self: *Tracker, command_buffer: u64) ?*CommandState {
        if (command_buffer == 0) return null;
        const start = commandStart(command_buffer);
        for (0..command_state_ways) |way| {
            const state = &self.command_states[start + way];
            if (state.command_buffer == command_buffer) return state;
        }
        return null;
    }

    fn findCommandStateConst(self: *const Tracker, command_buffer: u64) ?*const CommandState {
        if (command_buffer == 0) return null;
        const start = commandStart(command_buffer);
        for (0..command_state_ways) |way| {
            const state = &self.command_states[start + way];
            if (state.command_buffer == command_buffer) return state;
        }
        return null;
    }

    fn allocateCommandState(self: *Tracker, command_buffer: u64) ?*CommandState {
        if (command_buffer == 0) return null;
        const start = commandStart(command_buffer);
        for (0..command_state_ways) |way| {
            const state = &self.command_states[start + way];
            if (state.command_buffer != 0) continue;
            state.* = .{ .command_buffer = command_buffer };
            return state;
        }
        self.command_state_collisions +|= 1;
        const victim_way = @as(usize, @intCast((handleHash(command_buffer) >> 32) % command_state_ways));
        const victim = &self.command_states[start + victim_way];
        victim.* = .{ .command_buffer = command_buffer };
        return victim;
    }
};

fn handleHash(handle: u64) usize {
    var mixed = handle ^ (handle >> 33);
    mixed *%= 0xff51_afd7_ed55_8ccd;
    mixed ^= mixed >> 33;
    return @intCast(mixed);
}

fn shaderIdentity(id: u64, guest_handle: u64, spirv_hash: u64, code_bytes: u32, module: anytype) ShaderIdentity {
    return .{
        .id = id,
        .guest_handle = guest_handle,
        .spirv_hash = spirv_hash,
        .code_bytes = code_bytes,
        .execution_model_mask = module.execution_model_mask,
        .capability_mask = module.fragment_interlock_capabilities,
        .begin_ops = module.begin_interlock_ops,
        .end_ops = module.end_interlock_ops,
    };
}

fn mixHash(hash: u64, value: u64) u64 {
    var mixed = hash;
    inline for (0..8) |byte_index| {
        const byte: u8 = @truncate(value >> (byte_index * 8));
        mixed = (mixed ^ byte) *% 1099511628211;
    }
    return mixed;
}

pub fn spirvFingerprint(words: []const u32) u64 {
    var hash: u64 = 14695981039346656037;
    for (words) |word| hash = mixHash(hash, word);
    return hash;
}

/// Return Xenia's shared-memory SSBO count if these are its FSI EDRAM layout
/// bindings (0 = shared memory, 1 = EDRAM, 2 = ZPD counter). Other Vulkan
/// layouts are deliberately ignored.
pub fn sharedMemoryBindingCount(bindings: []const DescriptorBinding) ?u32 {
    if (bindings.len != 3) return null;

    var shared_memory_count: ?u32 = null;
    var edram_seen = false;
    var zpd_counter_seen = false;
    for (bindings) |binding| {
        if (binding.descriptor_type != STORAGE_BUFFER_DESCRIPTOR_TYPE or
            binding.descriptor_count == 0 or binding.immutable_samplers != 0)
        {
            return null;
        }
        switch (binding.binding) {
            0 => {
                if (shared_memory_count != null or binding.stage_flags & FRAGMENT_SHADER_STAGE == 0) return null;
                shared_memory_count = binding.descriptor_count;
            },
            1 => {
                if (edram_seen or binding.descriptor_count != 1 or binding.stage_flags != FRAGMENT_SHADER_STAGE) return null;
                edram_seen = true;
            },
            2 => {
                if (zpd_counter_seen or binding.descriptor_count != 1 or binding.stage_flags != FRAGMENT_SHADER_STAGE) return null;
                zpd_counter_seen = true;
            },
            else => return null,
        }
    }
    if (!edram_seen or !zpd_counter_seen) return null;
    return shared_memory_count;
}

/// Xenia derives this count from VkPhysicalDeviceLimits::maxStorageBufferRange.
pub fn sharedMemoryBindingCountForRange(max_storage_buffer_range: u32) u32 {
    if (max_storage_buffer_range >= 512 * 1024 * 1024) return 1;
    if (max_storage_buffer_range >= 256 * 1024 * 1024) return 2;
    return 4;
}

test "Xenia's three-binding EDRAM layout proves FSI path selection" {
    const bindings = [_]DescriptorBinding{
        .{ .binding = 0, .descriptor_type = STORAGE_BUFFER_DESCRIPTOR_TYPE, .descriptor_count = 2, .stage_flags = 0x3f },
        .{ .binding = 1, .descriptor_type = STORAGE_BUFFER_DESCRIPTOR_TYPE, .descriptor_count = 1, .stage_flags = FRAGMENT_SHADER_STAGE },
        .{ .binding = 2, .descriptor_type = STORAGE_BUFFER_DESCRIPTOR_TYPE, .descriptor_count = 1, .stage_flags = FRAGMENT_SHADER_STAGE },
    };
    try std.testing.expectEqual(@as(?u32, 2), sharedMemoryBindingCount(&bindings));
}

test "ordinary render-target layouts do not count as FSI selection" {
    const bindings = [_]DescriptorBinding{
        .{ .binding = 0, .descriptor_type = STORAGE_BUFFER_DESCRIPTOR_TYPE, .descriptor_count = 2, .stage_flags = 0x3f },
    };
    try std.testing.expect(sharedMemoryBindingCount(&bindings) == null);
}

test "the Xenia shared-memory count follows maxStorageBufferRange thresholds" {
    try std.testing.expectEqual(@as(u32, 4), sharedMemoryBindingCountForRange(256 * 1024 * 1024 - 1));
    try std.testing.expectEqual(@as(u32, 2), sharedMemoryBindingCountForRange(256 * 1024 * 1024));
    try std.testing.expectEqual(@as(u32, 1), sharedMemoryBindingCountForRange(512 * 1024 * 1024));
}

test "FSI shader fingerprints follow modules through pipeline bind, draw, and accepted submit" {
    var tracker: Tracker = .{};
    const stages = spirv_stage.ModuleStages{
        .valid = true,
        .has_entry_point = true,
        .execution_model_mask = 1 << 4,
        .fragment_interlock_capabilities = 1,
        .begin_interlock_ops = 1,
        .end_interlock_ops = 1,
    };
    const shader = tracker.rememberShader(0x100, spirvFingerprint(&.{ 1, 2, 3, 4 }), 16, stages).?;
    try std.testing.expectEqual(@as(u64, 1), shader.id);
    try std.testing.expectEqual(@as(?u64, shader.spirv_hash), tracker.findShader(0x100).?.spirv_hash);

    var identity: PipelineIdentity = .{};
    identity.include(FRAGMENT_SHADER_STAGE, shader);
    tracker.notePipelineCreated(0x200, identity, true);
    tracker.bindPipeline(0x300, 0x200);
    tracker.setTarget(0x300, 0x400, .render_pass);
    const draw = tracker.noteDraw(0x300).?;
    try std.testing.expectEqual(@as(u64, 1), draw.draw_ordinal);
    try std.testing.expectEqual(@as(u64, 0x400), draw.target_image);
    try std.testing.expectEqual(TargetSource.render_pass, draw.target_source);
    const submit = tracker.noteSubmitted(0x300, 8, 1).?;
    try std.testing.expectEqual(@as(u64, 8), submit.queue_submit_ordinal);
    try std.testing.expectEqual(@as(u64, 1), submit.fsi_draws_in_command_buffer);
    try std.testing.expectEqual(@as(u64, 1), tracker.submitted_draws);

    tracker.bindPipeline(0x300, 0x201);
    try std.testing.expect(tracker.noteDraw(0x300) == null);
}

test "FSI secondary command-buffer draws are attributed to the submitted primary" {
    var tracker: Tracker = .{};
    const identity = PipelineIdentity{
        .uses_fsi = true,
        .shader_count = 1,
        .stage_flags_or = FRAGMENT_SHADER_STAGE,
        .module_id = 7,
        .shader_hash = 0xabc,
        .combined_hash = 0xdef,
    };
    tracker.notePipelineCreated(0x20, identity, true);
    tracker.bindPipeline(0x30, 0x20);
    _ = tracker.noteDraw(0x30).?;
    tracker.setTarget(0x30, 0x90, .inherited_secondary);
    tracker.mergeCommandBuffer(0x40, 0x30);
    const submitted = tracker.noteSubmitted(0x40, 9, 0).?;
    try std.testing.expectEqual(@as(u64, 1), submitted.fsi_draws_in_command_buffer);
    try std.testing.expectEqual(@as(u64, 0xdef), submitted.draw.pipeline_hash);
    try std.testing.expectEqual(@as(u64, 0x90), submitted.draw.target_image);
    try std.testing.expectEqual(TargetSource.inherited_secondary, submitted.draw.target_source);
}

test "FSI target observed before pipeline binding is retained when bind creates command state" {
    var tracker: Tracker = .{};
    const identity = PipelineIdentity{ .uses_fsi = true, .module_id = 7, .combined_hash = 0xdef };
    tracker.notePipelineCreated(0x20, identity, true);

    // Vulkan records the render-pass begin before the guest binds its FSI
    // pipeline. The first observation cannot allocate command state; the
    // command tracker must propagate it after bindPipeline creates that state.
    tracker.setTarget(0x30, 0x90, .render_pass);
    tracker.bindPipeline(0x30, 0x20);
    tracker.setTarget(0x30, 0x90, .render_pass);
    const draw = tracker.noteDraw(0x30).?;
    try std.testing.expectEqual(@as(u64, 0x90), draw.target_image);
    try std.testing.expectEqual(TargetSource.render_pass, draw.target_source);
    try std.testing.expectEqual(@as(u64, 1), tracker.target_updates_before_fsi_pipeline);
}

test "FSI dynamic attachment routing counts a resolved target once" {
    var tracker: Tracker = .{};
    const identity = PipelineIdentity{ .uses_fsi = true, .module_id = 8, .combined_hash = 0xeee };
    tracker.notePipelineCreated(0x21, identity, true);
    tracker.bindPipeline(0x31, 0x21);
    tracker.setTarget(0x31, 0x91, .dynamic_rendering);
    tracker.setTarget(0x31, 0x91, .dynamic_rendering);
    try std.testing.expect(tracker.targetMatches(0x31, 0x91, .dynamic_rendering));
    try std.testing.expectEqual(@as(u64, 1), tracker.dynamic_targets_resolved);
}

test "FSI descriptor evidence retains all three native buffer bindings" {
    var tracker: Tracker = .{};
    tracker.noteDescriptorUpdate(.{
        .update_call = 3,
        .guest_set = 0x123,
        .native_set = 0x223,
        .binding_count = 3,
        .binding_mask = 0x07,
        .bindings = .{
            .{ .binding = 0, .guest_buffer = 0x10, .native_buffer = 0x110, .guest_range = 4096, .range = 4096 },
            .{ .binding = 1, .guest_buffer = 0x20, .native_buffer = 0x120, .guest_range = 16 * 1024 * 1024, .range = 16 * 1024 * 1024 },
            .{ .binding = 2, .guest_buffer = 0, .native_buffer = 0x130, .range = 32768, .repaired = true },
        },
    });
    try std.testing.expectEqual(@as(u64, 1), tracker.descriptor_updates);
    try std.testing.expect(tracker.last_descriptor_update.bindings[2].repaired);
    try std.testing.expectEqual(@as(u64, 0x130), tracker.last_descriptor_update.bindings[2].native_buffer);
    try std.testing.expectEqual(@as(u64, 0x223), tracker.last_descriptor_update.native_set);
    try std.testing.expectEqual(@as(u8, 0x07), tracker.last_descriptor_update.binding_mask);
}

test "FSI draw evidence distinguishes indirect command recording from direct draws" {
    var tracker: Tracker = .{};
    tracker.notePipelineCreated(0x20, .{ .uses_fsi = true, .module_id = 7, .combined_hash = 0xdef }, true);
    tracker.bindPipeline(0x30, 0x20);
    const draw = tracker.noteDrawKind(0x30, .indexed_indirect).?;
    try std.testing.expectEqual(DrawKind.indexed_indirect, draw.kind);
    try std.testing.expectEqual(@as(u64, 1), draw.draw_ordinal);
}

test "FSI indexed draw arguments survive accepted submission attribution" {
    var tracker: Tracker = .{};
    tracker.notePipelineCreated(0x20, .{ .uses_fsi = true, .module_id = 7 }, true);
    tracker.bindPipeline(0x30, 0x20);
    const parameters = DrawParameters{
        .valid = true,
        .element_count = 539,
        .instance_count = 1,
        .first_element = 0,
        .vertex_offset = -8,
        .first_instance = 3,
    };
    _ = tracker.noteDrawWithParameters(0x30, .indexed, parameters).?;
    const submitted = tracker.noteSubmitted(0x30, 12, 0).?;
    try std.testing.expect(submitted.draw.parameters.valid);
    try std.testing.expectEqual(@as(u64, 539), submitted.draw.parameters.element_count);
    try std.testing.expectEqual(@as(u64, 1), submitted.draw.parameters.instance_count);
    try std.testing.expectEqual(@as(u64, 0), submitted.draw.parameters.first_element);
    try std.testing.expectEqual(@as(i32, -8), submitted.draw.parameters.vertex_offset);
    try std.testing.expectEqual(@as(u64, 3), submitted.draw.parameters.first_instance);
}

test "FSI submission history keeps the accepted work before an asynchronous GPU fault" {
    var tracker: Tracker = .{};
    tracker.notePipelineCreated(0x20, .{ .uses_fsi = true, .module_id = 7 }, true);
    tracker.bindPipeline(0x30, 0x20);
    try std.testing.expect(tracker.recentSubmission(0) == null);
    for (1..recent_submission_capacity + 4) |ordinal| {
        tracker.resetCommandBuffer(0x30);
        tracker.bindPipeline(0x30, 0x20);
        _ = tracker.noteDraw(0x30).?;
        _ = tracker.noteSubmitted(0x30, ordinal, 0).?;
    }
    try std.testing.expectEqual(recent_submission_capacity, tracker.recent_submission_count);
    try std.testing.expectEqual(@as(u64, 4), tracker.recentSubmission(0).?.queue_submit_ordinal);
    try std.testing.expectEqual(@as(u64, recent_submission_capacity + 3), tracker.recentSubmission(recent_submission_capacity - 1).?.queue_submit_ordinal);
    try std.testing.expect(tracker.recentSubmission(recent_submission_capacity) == null);
}
