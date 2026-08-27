//! Stateful Xenos command-processor facade.
//!
//! The Vulkan forwarder owns host objects; this module owns the console-side
//! work that makes a draw meaningful.  It consumes the same big-endian PM4
//! dwords that Xenia publishes in its ring, applies register packets, emits
//! completion events, and exposes the derived pipeline/EDRAM state to a
//! backend.  It deliberately does not invent a packet or advance a guest
//! pointer: the caller supplies the readable ring span and remains the owner
//! of guest memory.

const std = @import("std");
const edram = @import("edram.zig");
const interrupt = @import("interrupt_controller.zig");
const observation_contract = @import("xenia_gpu_observation_contract");
const pipeline = @import("pipeline_state.zig");
const pm4 = @import("pm4.zig");
const pm4_contract = @import("xenia_pm4_contract");
const executor_module = @import("pm4_executor.zig");
const packet_trace = @import("packet_trace.zig");
const registers = @import("xenos_registers.zig");
const formats = @import("xenos_formats.zig");
const shader = @import("xenos_shader.zig");

pub const max_ring_dwords: usize = observation_contract.max_ring_dwords;

comptime {
    if (observation_contract.max_indirect_depth != pm4_contract.max_indirect_depth or
        observation_contract.max_indirect_dwords != pm4_contract.max_indirect_dwords or
        observation_contract.max_indirect_references != pm4_contract.max_indirect_references)
    {
        @compileError("GPU observation and PM4 packages disagree on indirect-buffer bounds");
    }
}

pub const ExecuteError = error{
    InvalidRing,
    TruncatedRing,
    PacketError,
};

/// Whether command execution owns guest-visible effects or is reconstructing
/// state from a batch Xenia already consumed. Retained inspection may update
/// Rosette's register/draw evidence, but it must never publish a second
/// interrupt, satisfy a wait twice, or overwrite guest memory.
pub const ExecutionDisposition = enum(u8) {
    live,
    retained_observation,

    pub fn publishesEffects(self: ExecutionDisposition) bool {
        return self == .live;
    }

    pub fn label(self: ExecutionDisposition) []const u8 {
        return switch (self) {
            .live => "live",
            .retained_observation => "retained-observation",
        };
    }
};

pub const IndirectStatus = enum(u8) {
    not_attempted,
    complete,
    unreadable,
    truncated,
    invalid,
    depth_limit,
    budget_limit,
    cycle,

    pub fn label(self: IndirectStatus) []const u8 {
        return switch (self) {
            .not_attempted => "not-attempted",
            .complete => "complete",
            .unreadable => "unreadable",
            .truncated => "truncated",
            .invalid => "invalid",
            .depth_limit => "depth-limit",
            .budget_limit => "budget-limit",
            .cycle => "cycle",
        };
    }
};

pub const Report = struct {
    disposition: ExecutionDisposition = .live,
    dwords: u32 = 0,
    packets_before: u64 = 0,
    packets_after: u64 = 0,
    draws: u64 = 0,
    events: u64 = 0,
    swaps: u64 = 0,
    draw_completion_observations: u64 = 0,
    draw_completion_signals: u64 = 0,
    unknown_opcodes: u64 = 0,
    truncated: bool = false,
    indirect_buffers: u64 = 0,
    indirect_dwords_requested: u64 = 0,
    indirect_dwords_read: u64 = 0,
    indirect_unreadable: u64 = 0,
    indirect_truncated: u64 = 0,
    indirect_invalid: u64 = 0,
    indirect_depth_limited: u64 = 0,
    indirect_budget_limited: u64 = 0,
    indirect_cycles: u64 = 0,
    indirect_last_status: IndirectStatus = .not_attempted,
    indirect_last_address: u32 = 0,
    indirect_last_missing_address: ?u32 = null,
    packet_summary: packet_trace.Summary = .{},
};

pub const TextureBinding = struct {
    binding: u8,
    fetch_constant: u8,
    fetch: registers.TextureFetch,
};

/// Register-backed surface evidence.  `renderTargets()` always returns a
/// primary target, including immediately after reset, so callers must not use
/// that non-null result as proof that a title selected a render target.  This
/// record only reports evidence when a relevant Xenos register contains a
/// non-default value after the register file has received writes.
pub const RenderTargetEvidence = struct {
    state_observed: bool = false,
    plausible: bool = false,
    color_base_tiles: u32 = 0,
    color_format: u32 = 0,
    depth_base_tiles: u32 = 0,
    depth_format: u32 = 0,
    surface_pitch_pixels: u32 = 0,
    msaa_mode: u2 = 0,
    color_mask: u8 = 0,
    raw_color_info: u32 = 0,
    raw_depth_info: u32 = 0,
    raw_surface_info: u32 = 0,
};

const ActiveIndirectRange = struct {
    address: u32 = 0,
    size_dwords: u32 = 0,
};

pub const Runtime = struct {
    executor: executor_module.Executor = .{},
    interrupts: interrupt.Controller = .{},
    batches: u64 = 0,
    ring_dwords_consumed: u64 = 0,
    draw_count: u64 = 0,
    event_count: u64 = 0,
    swap_count: u64 = 0,
    draw_completion_signals: u64 = 0,
    draw_completion_observations: u64 = 0,
    retained_draw_observations: u64 = 0,
    retained_event_observations: u64 = 0,
    execution_disposition: ExecutionDisposition = .live,
    color_resolve_observations: u64 = 0,
    packet_errors: u64 = 0,
    truncated_rings: u64 = 0,
    indirect_depth: u8 = 0,
    indirect_buffers: u64 = 0,
    indirect_dwords_requested: u64 = 0,
    indirect_dwords_read: u64 = 0,
    indirect_unreadable: u64 = 0,
    indirect_truncated: u64 = 0,
    indirect_invalid: u64 = 0,
    indirect_depth_limited: u64 = 0,
    indirect_budget_limited: u64 = 0,
    indirect_cycles: u64 = 0,
    indirect_execution_dwords: u64 = 0,
    active_indirect_ranges: [observation_contract.max_indirect_references]ActiveIndirectRange = [_]ActiveIndirectRange{.{}} ** observation_contract.max_indirect_references,
    active_indirect_count: usize = 0,
    indirect_last_status: IndirectStatus = .not_attempted,
    indirect_last_address: u32 = 0,
    indirect_last_missing_address: ?u32 = null,
    last_swap: ?pm4.SwapDescription = null,
    last_draw: ?executor_module.Draw = null,
    shader_cache: shader.Cache = .{},
    last_shader_source_hash: u64 = 0,
    last_shader_type: shader.ShaderType = .unknown,
    shader_parse_failures: u64 = 0,
    shader_translation_observations: u64 = 0,
    packet_timeline: packet_trace.Timeline = .{},
    /// Host-owned EDRAM backing supplied by the process.  Keeping it as a
    /// slice makes the 10 MiB allocation lazy and keeps Runtime cheap to copy
    /// in tests and in the Mach-O state object.
    edram_store: ?edram.Store = null,

    pub fn init() Runtime {
        var result: Runtime = .{};
        result.executor.callback_context = @ptrCast(&result);
        result.executor.event_callback = onEvent;
        result.executor.draw_callback = onDraw;
        // The callback context is repaired below when the value is moved into
        // its owner; callers should use `activate` for a persistent instance.
        result.executor.callback_context = null;
        return result;
    }

    pub fn activate(self: *Runtime) void {
        self.executor.callback_context = @ptrCast(self);
        self.executor.event_callback = onEvent;
        self.executor.draw_callback = onDraw;
        self.executor.packet_callback_context = @ptrCast(self);
        self.executor.packet_callback = onPacket;
    }

    /// Attach the process-owned console memory view to the command processor.
    /// PM4 itself remains backend-neutral; these callbacks are the only place
    /// it is allowed to observe or mutate guest memory for WAIT/MEM_WRITE and
    /// indirect-buffer packets.
    pub fn attachMemory(
        self: *Runtime,
        read_context: *anyopaque,
        read_callback: ?executor_module.MemoryReadCallback,
        write_context: *anyopaque,
        write_callback: ?executor_module.MemoryWriteCallback,
    ) void {
        self.activate();
        self.executor.memory_read_context = read_context;
        self.executor.memory_read_callback = read_callback;
        self.executor.memory_write_context = write_context;
        self.executor.memory_write_callback = write_callback;
        self.executor.indirect_buffer_context = @ptrCast(self);
        self.executor.indirect_buffer_callback = if (read_callback != null) onIndirectBuffer else null;
    }

    pub fn attachEdram(self: *Runtime, bytes: []u8) void {
        self.edram_store = edram.Store.init(bytes);
    }

    /// Apply a register write observed through the protected Xenos aperture.
    /// PM4 type-0 packets are still the authoritative command stream, but a
    /// delivered MMIO fault is an equally real piece of console state and is
    /// needed for titles that program CP/VGT/RB directly before publishing a
    /// ring batch.
    pub fn observeRegisterWrite(self: *Runtime, register: registers.Register, value: u32) void {
        self.activate();
        self.executor.register_file.write(register, value);
    }

    /// Read the console-side register file for a direct MMIO load. PM4 waits
    /// already use the same state, but translated titles can also poll the
    /// Xenos aperture directly (notably CP_RB_RPTR and event status). Keeping
    /// this in the runtime makes those reads observe the exact state that PM4
    /// writes and avoids treating a deliberate no-access MMIO page as a guest
    /// SIGSEGV.
    pub fn readRegister(self: *Runtime, register: registers.Register) u32 {
        self.activate();
        return self.executor.register_file.read(register);
    }

    /// Complete a fence that was submitted through the real Vulkan queue.
    /// Vulkan completion is observed at the fence wait/status calls by the
    /// forwarding layer; publishing it here keeps the guest callback path
    /// identical to a PM4 EVENT_WRITE completion.
    pub fn noteNativeFenceComplete(self: *Runtime, fence: u64) void {
        self.activate();
        if (fence == 0) return;
        self.interrupts.publish(.fence, @truncate(fence), 1);
    }

    /// Recover the six-dword fetch constant the command processor last saw at
    /// the conventional front-buffer slot.  A zero constant is not useful as
    /// a presentation description, so return null until at least one dword is
    /// populated.
    pub fn frontBufferFetch(self: *const Runtime) ?pm4.FetchConstant {
        var fetch = pm4.FetchConstant{};
        var nonzero = false;
        for (0..fetch.dwords.len) |index| {
            fetch.dwords[index] = self.executor.register_file.peek(pm4.shader_constant_fetch_00_0 + @as(registers.Register, @intCast(index)));
            nonzero = nonzero or fetch.dwords[index] != 0;
        }
        return if (nonzero) fetch else null;
    }

    pub fn executeRingBytes(self: *Runtime, bytes: []const u8, read_pointer: u32, span_dwords: u32, ring_dwords: u32) ExecuteError!Report {
        if (ring_dwords == 0 or ring_dwords > max_ring_dwords or @as(u64, ring_dwords) * 4 > bytes.len) return error.InvalidRing;
        self.activate();
        const packet_before = self.packet_timeline.snapshot();
        // These are per-root-execution guards. They are reset only here, never
        // by a nested callback, so a cyclic indirect stream is bounded across
        // the entire batch rather than receiving a fresh budget at each edge.
        self.indirect_depth = 0;
        self.indirect_execution_dwords = 0;
        self.active_indirect_count = 0;
        var report = Report{
            .disposition = self.execution_disposition,
            .packets_before = self.executor.packet_count,
            .dwords = @min(span_dwords, ring_dwords),
        };
        const draws_before = self.executor.draw_count;
        const events_before = self.executor.event_count;
        const swaps_before = self.executor.swap_count;
        const draw_observations_before = self.draw_completion_observations;
        const draw_signals_before = self.draw_completion_signals;
        const indirect_buffers_before = self.indirect_buffers;
        const indirect_requested_before = self.indirect_dwords_requested;
        const indirect_read_before = self.indirect_dwords_read;
        const indirect_unreadable_before = self.indirect_unreadable;
        const indirect_truncated_before = self.indirect_truncated;
        const indirect_invalid_before = self.indirect_invalid;
        const indirect_depth_limited_before = self.indirect_depth_limited;
        const indirect_budget_limited_before = self.indirect_budget_limited;
        const indirect_cycles_before = self.indirect_cycles;
        self.indirect_last_status = .not_attempted;
        self.indirect_last_address = 0;
        self.indirect_last_missing_address = null;
        if (span_dwords > ring_dwords) report.truncated = true;
        if (span_dwords > max_ring_dwords) {
            report.dwords = max_ring_dwords;
            report.truncated = true;
        }
        var words: [max_ring_dwords]u32 = undefined;
        for (0..@as(usize, @intCast(report.dwords))) |index| {
            const ring_index = (@as(u64, read_pointer) + index) % ring_dwords;
            const offset = @as(usize, @intCast(ring_index)) * 4;
            words[index] = std.mem.readInt(u32, bytes[offset..][0..4], .big);
        }
        self.batches +|= 1;
        self.ring_dwords_consumed +|= report.dwords;
        self.draw_count = self.executor.draw_count;
        self.event_count = self.executor.event_count;
        self.swap_count = self.executor.swap_count;
        self.last_draw = self.executor.last_draw;
        self.last_swap = self.executor.last_swap;
        self.executor.execute(words[0..@as(usize, @intCast(report.dwords))]) catch |err| {
            self.packet_errors +|= 1;
            if (err == error.truncated_packet) {
                report.truncated = true;
                self.truncated_rings +|= 1;
                return error.TruncatedRing;
            }
            return error.PacketError;
        };
        self.cacheLastShader();
        report.packets_after = self.executor.packet_count;
        report.draws = self.executor.draw_count - draws_before;
        report.events = self.executor.event_count - events_before;
        report.swaps = self.executor.swap_count - swaps_before;
        report.draw_completion_observations = self.draw_completion_observations - draw_observations_before;
        report.draw_completion_signals = self.draw_completion_signals - draw_signals_before;
        report.unknown_opcodes = self.executor.unknown_opcode_count;
        report.indirect_buffers = self.indirect_buffers - indirect_buffers_before;
        report.indirect_dwords_requested = self.indirect_dwords_requested - indirect_requested_before;
        report.indirect_dwords_read = self.indirect_dwords_read - indirect_read_before;
        report.indirect_unreadable = self.indirect_unreadable - indirect_unreadable_before;
        report.indirect_truncated = self.indirect_truncated - indirect_truncated_before;
        report.indirect_invalid = self.indirect_invalid - indirect_invalid_before;
        report.indirect_depth_limited = self.indirect_depth_limited - indirect_depth_limited_before;
        report.indirect_budget_limited = self.indirect_budget_limited - indirect_budget_limited_before;
        report.indirect_cycles = self.indirect_cycles - indirect_cycles_before;
        report.indirect_last_status = self.indirect_last_status;
        report.indirect_last_address = self.indirect_last_address;
        report.indirect_last_missing_address = self.indirect_last_missing_address;
        report.packet_summary = self.packet_timeline.snapshot().delta(packet_before);
        self.draw_count = self.executor.draw_count;
        self.event_count = self.executor.event_count;
        self.swap_count = self.executor.swap_count;
        self.last_draw = self.executor.last_draw;
        self.last_swap = self.executor.last_swap;
        return report;
    }

    /// Decode a retained, already-consumed batch into Rosette-owned state
    /// without replaying any guest-visible completion or interrupt effect.
    pub fn inspectRetainedRingBytes(self: *Runtime, bytes: []const u8, read_pointer: u32, span_dwords: u32, ring_dwords: u32) ExecuteError!Report {
        const previous = self.execution_disposition;
        self.execution_disposition = .retained_observation;
        defer self.execution_disposition = previous;
        return self.executeRingBytes(bytes, read_pointer, span_dwords, ring_dwords);
    }

    fn cacheLastShader(self: *Runtime) void {
        const count = self.executor.last_shader_word_count;
        if (count < 4) return;
        const program = self.shader_cache.getOrParse(
            self.executor.last_shader_words[0..@as(usize, @intCast(count))],
        ) catch {
            self.shader_parse_failures +|= 1;
            return;
        };
        self.last_shader_source_hash = program.source_hash;
        self.last_shader_type = program.shader_type;
        self.shader_translation_observations +|= 1;
    }

    pub fn lastShaderSourceHash(self: *const Runtime) u64 {
        return self.last_shader_source_hash;
    }

    pub fn lastShaderType(self: *const Runtime) shader.ShaderType {
        return self.last_shader_type;
    }

    /// Return the exact six-dword texture resource description currently in
    /// the Xenos fetch aperture.  Keeping this API beside pipelineState makes
    /// descriptor/resource code consume typed state instead of re-decoding
    /// register words independently.
    pub fn textureFetch(self: *const Runtime, index: usize) ?registers.TextureFetch {
        return self.executor.register_file.textureFetch(index);
    }

    /// Enumerate programmed texture fetch constants in their stable Xenos
    /// slot order.  The native Vulkan path receives Xenia's descriptor writes
    /// directly; this compact mapping is the fallback/resource-invalidation
    /// contract and prevents a texture cache from guessing which register
    /// aperture entry a sampled image came from.
    pub fn textureBindings(self: *const Runtime, output: []TextureBinding) usize {
        var written: usize = 0;
        for (0..registers.shader_constant_fetch_count) |index| {
            if (written >= output.len) break;
            const fetch = self.textureFetch(index) orelse continue;
            if (fetch.type != .texture) continue;
            output[written] = .{
                .binding = @intCast(written),
                .fetch_constant = @intCast(index),
                .fetch = fetch,
            };
            written += 1;
        }
        return written;
    }

    pub fn vertexFetch(self: *const Runtime, index: usize) ?registers.VertexFetch {
        return self.executor.register_file.vertexFetch(index);
    }

    pub fn aluConstant(self: *const Runtime, index: usize) ?[4]u32 {
        return self.executor.register_file.aluConstant(index);
    }

    pub fn programControl(self: *const Runtime) registers.ProgramControl {
        return self.executor.register_file.programControl();
    }

    pub fn contextMisc(self: *const Runtime) registers.ContextMisc {
        return self.executor.register_file.contextMisc();
    }

    pub fn outputPath(self: *const Runtime) registers.OutputPathState {
        return self.executor.register_file.outputPath();
    }

    /// Return only register evidence that can identify a programmed Xenos
    /// surface.  The default `RenderTargetState` is not evidence: target 0 is
    /// structurally present even when the title never touched RB_COLOR_INFO or
    /// RB_SURFACE_INFO.
    pub fn renderTargetEvidence(self: *const Runtime) RenderTargetEvidence {
        const color_info = self.executor.register_file.peek(registers.RB_COLOR_INFO);
        const depth_info = self.executor.register_file.peek(registers.RB_DEPTH_INFO);
        const surface_info = self.executor.register_file.peek(registers.RB_SURFACE_INFO);
        const color_mask = self.executor.register_file.peek(registers.RB_COLOR_MASK);
        const target = self.executor.register_file.renderTargets();
        const state_observed = self.executor.register_file.write_count != 0 and
            (color_info != 0 or depth_info != 0 or surface_info != 0 or color_mask != 0);
        return .{
            .state_observed = state_observed,
            .plausible = state_observed and target.surface_pitch_pixels != 0,
            .color_base_tiles = target.color_base_tiles,
            .color_format = target.color_format,
            .depth_base_tiles = target.depth_base_tiles,
            .depth_format = target.depth_format,
            .surface_pitch_pixels = target.surface_pitch_pixels,
            .msaa_mode = target.msaa_mode,
            .color_mask = target.color_mask,
            .raw_color_info = color_info,
            .raw_depth_info = depth_info,
            .raw_surface_info = surface_info,
        };
    }

    /// Drain completion events through a caller-owned boundary.  The runtime
    /// keeps events queued until the Mach-O scheduler has a guest callback to
    /// receive them; this prevents a PM4 scan from calling guest code
    /// synchronously while it is still inspecting guest memory.
    pub fn drainInterrupts(self: *Runtime, callback: interrupt.Callback, context: *anyopaque, max_events: u8) u8 {
        self.interrupts.register(callback, context);
        defer self.interrupts.unregister();
        return self.interrupts.drain(max_events);
    }

    pub fn pipelineState(self: *const Runtime) pipeline.State {
        var state: pipeline.State = .{};
        const initiator = self.executor.register_file.drawInitiator();
        state.topology = pipeline.topologyFromPrimitive(initiator.primitive);
        state.index_format = initiator.index_format;
        const raster = self.executor.register_file.raster();
        state.primitive_restart = raster.primitive_restart;
        state.cull_mode = pipeline.cullModeFromRaster(raster);
        state.front_face = if (raster.front_face_clockwise) .clockwise else .counter_clockwise;
        state.polygon_mode = pipeline.polygonModeFromRaster(raster);
        state.depth_clamp = raster.depth_clamp;
        state.depth_bias_enable = raster.polygon_offset_front_enable or
            raster.polygon_offset_back_enable or raster.polygon_offset_para_enable;
        if (raster.polygon_offset_front_enable or raster.polygon_offset_para_enable) {
            state.depth_bias_constant = raster.polygon_offset_front_offset;
            state.depth_bias_slope = raster.polygon_offset_front_scale;
        } else if (raster.polygon_offset_back_enable) {
            state.depth_bias_constant = raster.polygon_offset_back_offset;
            state.depth_bias_slope = raster.polygon_offset_back_scale;
        }
        const targets = self.executor.register_file.renderTargets();
        state.samples = switch (targets.msaa_mode) {
            1 => 2,
            2 => 4,
            else => 1,
        };
        state.viewport = pipeline.dynamicViewportFromRegisters(&self.executor.register_file);
        const scissor = self.executor.register_file.scissor();
        state.scissor = .{
            .x = scissor.left,
            .y = scissor.top,
            .width = if (scissor.right > scissor.left) @intCast(scissor.right - scissor.left) else 0,
            .height = if (scissor.bottom > scissor.top) @intCast(scissor.bottom - scissor.top) else 0,
        };
        const depth = self.executor.register_file.depthStencil();
        state.depth_stencil = .{
            .depth_test = depth.depth_enable,
            .depth_write = depth.depth_write_enable,
            .depth_compare = pipeline.compareFromXenos(depth.depth_compare),
            .stencil_test = depth.stencil_enable,
            .stencil_front_compare = pipeline.compareFromXenos(depth.stencil_compare),
            .stencil_back_compare = pipeline.compareFromXenos(depth.back_stencil_compare),
            .stencil_front_reference = depth.front_reference,
            .stencil_back_reference = depth.back_reference,
            .stencil_front_compare_mask = depth.front_compare_mask,
            .stencil_back_compare_mask = depth.back_compare_mask,
            .stencil_front_write_mask = depth.front_write_mask,
            .stencil_back_write_mask = depth.back_write_mask,
        };
        var highest_target: usize = 0;
        for (0..4) |target_index| {
            const target = self.executor.register_file.renderTarget(target_index) orelse continue;
            const color_target = &state.color_targets[target_index];
            color_target.format = formats.renderTargetVulkanFormat(target.color_format) orelse 0;
            color_target.write_mask = @truncate(target.color_mask);
            const blend = self.executor.register_file.blend(target_index);
            color_target.blend_enable = blend.source_color != 1 or blend.destination_color != 0 or
                blend.source_alpha != 1 or blend.destination_alpha != 0 or
                blend.color_op != 0 or blend.alpha_op != 0;
            color_target.src_color = pipeline.blendFactorFromXenos(blend.source_color);
            color_target.dst_color = pipeline.blendFactorFromXenos(blend.destination_color);
            color_target.color_op = pipeline.blendOpFromXenos(blend.color_op);
            color_target.src_alpha = pipeline.blendFactorFromXenos(blend.source_alpha);
            color_target.dst_alpha = pipeline.blendFactorFromXenos(blend.destination_alpha);
            color_target.alpha_op = pipeline.blendOpFromXenos(blend.alpha_op);
            if (target_index == 0) state.alpha_to_coverage = blend.alpha_to_mask_enable;
            highest_target = @max(highest_target, target_index);
        }
        state.color_target_count = @intCast(highest_target + 1);
        const programs = self.executor.register_file.shaderProgramAddresses();
        state.vertex_shader = programs.vertex;
        state.fragment_shader = programs.pixel;
        var binding_count: usize = 0;
        for (0..registers.vertex_fetch_constant_count) |fetch_index| {
            const fetch = self.executor.register_file.vertexFetch(fetch_index) orelse continue;
            if (fetch.type != .vertex or binding_count >= state.vertex_bindings.len) continue;
            const stride_bytes = @min(fetch.sizeBytes(), std.math.maxInt(u16));
            state.vertex_bindings[binding_count] = .{
                .binding = @intCast(binding_count),
                .stride = @intCast(stride_bytes),
                .input_rate_instance = false,
                .fetch_constant = @intCast(fetch_index),
                .address_dwords = fetch.address_dwords,
                .size_words = fetch.size_words,
                .endian = fetch.endian,
            };
            binding_count += 1;
        }
        state.vertex_binding_count = @intCast(binding_count);
        return state;
    }

    pub fn resolveColor(self: *const Runtime, store: edram.Store, surface: edram.Surface, destination: []u8, pitch: u32) edram.Error!void {
        _ = self;
        return store.resolveColor(surface, destination, pitch);
    }

    /// Resolve the currently programmed color target through the process-owned
    /// EDRAM backing.  A caller may still pass an explicit Store to
    /// `resolveColor` when replaying a capture; this method is the live-path
    /// convenience used by the Mach-O presenter/readback boundary.
    pub fn resolveCurrentColor(self: *Runtime, width: u32, height: u32, destination: []u8, pitch: u32) edram.Error!void {
        const store = self.edram_store orelse return error.BufferTooSmall;
        const targets = self.executor.register_file.renderTargets();
        const format: edram.Format = if (targets.color_format == 5 or targets.color_format == 7 or targets.color_format == 15)
            .color64
        else
            .color32;
        const surface = edram.Surface{
            .base_tile = targets.color_base_tiles,
            .pitch_pixels = targets.surface_pitch_pixels,
            .width = width,
            .height = height,
            .msaa = switch (targets.msaa_mode) {
                1 => .x2,
                2 => .x4,
                else => .x1,
            },
            .format = format,
        };
        try store.resolveColor(surface, destination, pitch);
        self.color_resolve_observations +|= 1;
    }

    fn onDraw(context: *anyopaque, draw: executor_module.Draw) void {
        const self: *Runtime = @ptrCast(@alignCast(context));
        self.last_draw = draw;
        self.draw_completion_observations +|= 1;
        if (!self.execution_disposition.publishesEffects()) {
            self.retained_draw_observations +|= 1;
            return;
        }
        self.draw_completion_signals +|= 1;
        self.interrupts.publish(.draw_complete, registers.VGT_DRAW_INITIATOR, draw.count);
    }

    fn onPacket(context: *anyopaque, observation: packet_trace.Observation) void {
        const self: *Runtime = @ptrCast(@alignCast(context));
        self.packet_timeline.record(observation);
    }

    fn onEvent(context: *anyopaque, event: executor_module.Event) void {
        const self: *Runtime = @ptrCast(@alignCast(context));
        if (!self.execution_disposition.publishesEffects()) {
            self.retained_event_observations +|= 1;
            switch (event) {
                .swap => |value| self.last_swap = value,
                else => {},
            }
            return;
        }
        switch (event) {
            .event_write => |value| self.interrupts.publish(.fence, value.event_id, value.value),
            .event_write_shd => |value| self.interrupts.publish(.custom, value.event_id, value.value),
            .event_write_cfl => |value| self.interrupts.publish(.custom, value.event_id, 0),
            .event_write_ext => |value| self.interrupts.publish(.custom, value.event_id, value.address),
            .event_write_zpd => |value| self.interrupts.publish(.custom, value.event_id, value.sample_count_address),
            .interrupt => |value| {
                // Xenia's Mac command processor treats the payload as a CPU
                // interrupt mask and dispatches the six Xenos interrupt bits
                // independently.  Publishing the raw mask as one source can
                // strand a guest callback waiting on a specific vector.
                for (0..6) |bit| {
                    const mask = @as(u32, 1) << @as(u5, @intCast(bit));
                    if ((value & mask) != 0) self.interrupts.publish(.fence, @intCast(bit), 0);
                }
            },
            .memory_write => |value| self.interrupts.publish(.custom, value.address, value.value),
            .wait_deferred => |value| self.interrupts.publish(.custom, value.address, value.reference),
            .indirect_buffer => |value| self.interrupts.publish(.custom, value.address, value.size_dwords),
            .read_pointer_writeback => |value| self.interrupts.publish(.fence, registers.CP_RB_RPTR, value),
            .swap => |value| {
                self.last_swap = value;
                self.interrupts.publish(.swap_complete, 0, value.frontbuffer_physical_address);
            },
        }
    }

    fn onIndirectBuffer(context: *anyopaque, address: u32, size_dwords: u32) void {
        const self: *Runtime = @ptrCast(@alignCast(context));
        self.indirect_buffers +|= 1;
        self.indirect_dwords_requested +|= size_dwords;
        self.indirect_last_address = address;
        self.indirect_last_missing_address = null;
        if (size_dwords == 0) {
            self.indirect_invalid +|= 1;
            self.indirect_last_status = .invalid;
            return;
        }
        if ((address & 3) != 0) {
            self.indirect_invalid +|= 1;
            self.indirect_last_status = .invalid;
            self.indirect_last_missing_address = address;
            return;
        }
        if (size_dwords > observation_contract.max_indirect_dwords) {
            self.indirect_budget_limited +|= 1;
            self.indirect_last_status = .budget_limit;
            return;
        }
        if (self.indirect_depth >= observation_contract.max_indirect_depth) {
            self.indirect_depth_limited +|= 1;
            self.indirect_last_status = .depth_limit;
            return;
        }
        if (self.indirectRangeActive(address, size_dwords)) {
            self.indirect_cycles +|= 1;
            self.indirect_last_status = .cycle;
            self.indirect_last_missing_address = address;
            return;
        }
        const requested = @as(u64, size_dwords);
        if (self.indirect_execution_dwords > observation_contract.max_indirect_execution_dwords or
            requested > observation_contract.max_indirect_execution_dwords - self.indirect_execution_dwords)
        {
            self.indirect_budget_limited +|= 1;
            self.indirect_last_status = .budget_limit;
            return;
        }
        if (self.active_indirect_count >= self.active_indirect_ranges.len) {
            self.indirect_budget_limited +|= 1;
            self.indirect_last_status = .budget_limit;
            return;
        }
        self.indirect_execution_dwords += requested;
        self.active_indirect_ranges[self.active_indirect_count] = .{ .address = address, .size_dwords = size_dwords };
        self.active_indirect_count += 1;
        defer self.active_indirect_count -= 1;
        const read_callback = self.executor.memory_read_callback orelse {
            self.indirect_unreadable +|= 1;
            self.indirect_last_status = .unreadable;
            self.indirect_last_missing_address = address;
            return;
        };
        const read_context = self.executor.memory_read_context orelse {
            self.indirect_unreadable +|= 1;
            self.indirect_last_status = .unreadable;
            self.indirect_last_missing_address = address;
            return;
        };
        var words: [observation_contract.max_indirect_dwords]u32 = undefined;
        var words_read: u32 = 0;
        for (0..@as(usize, @intCast(size_dwords))) |index| {
            const offset = std.math.mul(u32, @intCast(index), 4) catch {
                self.indirect_truncated +|= 1;
                self.indirect_last_status = .truncated;
                self.indirect_last_missing_address = std.math.maxInt(u32);
                return;
            };
            const byte_address = std.math.add(u32, address, offset) catch {
                self.indirect_truncated +|= 1;
                self.indirect_last_status = .truncated;
                self.indirect_last_missing_address = std.math.maxInt(u32);
                return;
            };
            words[index] = read_callback(read_context, byte_address) orelse {
                if (words_read == 0) {
                    self.indirect_unreadable +|= 1;
                    self.indirect_last_status = .unreadable;
                } else {
                    self.indirect_truncated +|= 1;
                    self.indirect_last_status = .truncated;
                }
                self.indirect_last_missing_address = byte_address;
                return;
            };
            words_read += 1;
            self.indirect_dwords_read +|= 1;
        }
        self.indirect_last_status = .complete;
        self.indirect_depth += 1;
        defer self.indirect_depth -= 1;
        self.executor.executeNested(
            words[0..@as(usize, @intCast(size_dwords))],
            self.indirect_depth,
            address,
        ) catch {
            self.packet_errors +|= 1;
        };
    }

    fn indirectRangeActive(self: *const Runtime, address: u32, size_dwords: u32) bool {
        const start = @as(u64, address);
        const end = start + @as(u64, size_dwords) * 4;
        for (self.active_indirect_ranges[0..self.active_indirect_count]) |active| {
            const active_start = @as(u64, active.address);
            const active_end = active_start + @as(u64, active.size_dwords) * 4;
            if (start < active_end and active_start < end) return true;
        }
        return false;
    }
};

const IndirectMemoryFixture = struct {
    words: [128]u32 = [_]u32{0} ** 128,
    readable_until: u32 = std.math.maxInt(u32),

    fn read(context: *anyopaque, address: u32) ?u32 {
        const self: *IndirectMemoryFixture = @ptrCast(@alignCast(context));
        if ((address & 3) != 0 or address >= self.readable_until or address / 4 >= self.words.len) return null;
        return self.words[address / 4];
    }

    fn write(context: *anyopaque, address: u32, value: u32, endian: u2) bool {
        _ = endian;
        const self: *IndirectMemoryFixture = @ptrCast(@alignCast(context));
        if ((address & 3) != 0 or address / 4 >= self.words.len) return false;
        self.words[address / 4] = value;
        return true;
    }
};

test "Xenos runtime consumes big-endian ring words and derives pipeline state" {
    var bytes = [_]u8{0} ** 64;
    const draw = pm4.packetType3(.draw_indx_2, 1, false).?;
    std.mem.writeInt(u32, bytes[0..4], draw, .big);
    std.mem.writeInt(u32, bytes[4..8], (registers.DrawInitiator{ .primitive = .triangle_list, .source = .auto_index, .major_mode_explicit = false, .index_format = .uint16, .not_end_of_pipe = false, .index_count = 3 }).encode(), .big);
    var runtime = Runtime.init();
    const report = try runtime.executeRingBytes(&bytes, 0, 2, 16);
    try std.testing.expectEqual(@as(u64, 1), report.draws);
    try std.testing.expectEqual(@as(u32, 3), runtime.last_draw.?.count);
    try std.testing.expectEqual(@as(u64, 1), runtime.draw_completion_signals);
    try std.testing.expectEqual(pipeline.Topology.triangle_list, runtime.pipelineState().topology);
}

test "Xenos runtime reports a bounded truncated ring" {
    var bytes = [_]u8{0} ** 8;
    const header = pm4.packetType3(.nop, 4, false).?;
    std.mem.writeInt(u32, bytes[0..4], header, .big);
    var runtime = Runtime.init();
    try std.testing.expectError(error.TruncatedRing, runtime.executeRingBytes(&bytes, 0, 2, 2));
    try std.testing.expectEqual(@as(u64, 1), runtime.truncated_rings);
}

test "Xenos runtime reports the indirect read boundary and executes a readable buffer" {
    var bytes = [_]u8{0} ** 64;
    const packet = pm4.packetType3(.indirect_buffer, 2, false).?;
    std.mem.writeInt(u32, bytes[0..4], packet, .big);
    std.mem.writeInt(u32, bytes[4..8], 0x100, .big);
    std.mem.writeInt(u32, bytes[8..12], 2, .big);

    var memory = IndirectMemoryFixture{};
    memory.words[0x100 / 4] = pm4.packetType3(.draw_indx_2, 1, false).?;
    memory.words[0x104 / 4] = (registers.DrawInitiator{
        .primitive = .triangle_list,
        .source = .auto_index,
        .major_mode_explicit = false,
        .index_format = .uint16,
        .not_end_of_pipe = false,
        .index_count = 3,
    }).encode();

    var runtime = Runtime.init();
    runtime.attachMemory(&memory, IndirectMemoryFixture.read, &memory, null);
    const report = try runtime.executeRingBytes(&bytes, 0, 3, 16);
    try std.testing.expectEqual(@as(u64, 1), report.indirect_buffers);
    try std.testing.expectEqual(@as(u64, 2), report.indirect_dwords_requested);
    try std.testing.expectEqual(@as(u64, 2), report.indirect_dwords_read);
    try std.testing.expectEqual(IndirectStatus.complete, report.indirect_last_status);
    try std.testing.expectEqual(@as(u64, 1), report.draws);
    try std.testing.expectEqual(@as(u64, 2), report.packet_summary.packets);
    try std.testing.expectEqual(@as(u64, 1), report.packet_summary.root_packets);
    try std.testing.expectEqual(@as(u64, 1), report.packet_summary.nested_packets);
    try std.testing.expectEqual(@as(u64, 1), report.packet_summary.classCount(.indirect));
    try std.testing.expectEqual(@as(u64, 1), report.packet_summary.classCount(.draw));
    try std.testing.expectEqual(@as(u64, 1), report.packet_summary.executedClassCount(.draw));
    try std.testing.expectEqual(packet_trace.Source.indirect, report.packet_summary.last.?.source);
    try std.testing.expectEqual(@as(u32, 0x100), report.packet_summary.last.?.stream_address);
}

test "Xenos runtime stops a cyclic indirect stream and records its provenance" {
    var bytes = [_]u8{0} ** 64;
    const packet = pm4.packetType3(.indirect_buffer, 2, false).?;
    std.mem.writeInt(u32, bytes[0..4], packet, .big);
    std.mem.writeInt(u32, bytes[4..8], 0x100, .big);
    std.mem.writeInt(u32, bytes[8..12], 3, .big);

    var memory = IndirectMemoryFixture{};
    memory.words[0x100 / 4] = packet;
    memory.words[0x104 / 4] = 0x100;
    memory.words[0x108 / 4] = 3;

    var runtime = Runtime.init();
    runtime.attachMemory(&memory, IndirectMemoryFixture.read, &memory, null);
    const report = try runtime.executeRingBytes(&bytes, 0, 3, 16);

    try std.testing.expectEqual(@as(u64, 2), report.indirect_buffers);
    try std.testing.expectEqual(@as(u64, 1), report.indirect_cycles);
    try std.testing.expectEqual(IndirectStatus.cycle, report.indirect_last_status);
    try std.testing.expectEqual(@as(?u32, 0x100), report.indirect_last_missing_address);
    try std.testing.expectEqual(@as(u64, 2), report.packet_summary.packets);
    try std.testing.expectEqual(@as(u64, 2), report.packet_summary.executedClassCount(.indirect));
    try std.testing.expectEqual(@as(u8, 1), report.packet_summary.max_depth);
}

test "Xenos runtime distinguishes a framed predicated draw from submitted work" {
    var bytes = [_]u8{0} ** 64;
    const packet = pm4.packetType3(.draw_indx_2, 1, true).?;
    std.mem.writeInt(u32, bytes[0..4], packet, .big);
    std.mem.writeInt(u32, bytes[4..8], (registers.DrawInitiator{
        .primitive = .triangle_list,
        .source = .auto_index,
        .major_mode_explicit = false,
        .index_format = .uint16,
        .not_end_of_pipe = false,
        .index_count = 3,
    }).encode(), .big);

    var runtime = Runtime.init();
    const report = try runtime.executeRingBytes(&bytes, 0, 2, 16);
    try std.testing.expectEqual(@as(u64, 0), report.draws);
    try std.testing.expectEqual(@as(u64, 1), report.packet_summary.classCount(.draw));
    try std.testing.expectEqual(@as(u64, 0), report.packet_summary.executedClassCount(.draw));
    try std.testing.expectEqual(@as(u64, 1), runtime.executor.predicated_skip_count);
}

test "Xenos runtime distinguishes an unreadable indirect buffer from a zero-filled one" {
    var bytes = [_]u8{0} ** 64;
    const packet = pm4.packetType3(.indirect_buffer, 2, false).?;
    std.mem.writeInt(u32, bytes[0..4], packet, .big);
    std.mem.writeInt(u32, bytes[4..8], 0x200, .big);
    std.mem.writeInt(u32, bytes[8..12], 1, .big);

    var memory = IndirectMemoryFixture{ .readable_until = 0x200 };
    var runtime = Runtime.init();
    runtime.attachMemory(&memory, IndirectMemoryFixture.read, &memory, null);
    const report = try runtime.executeRingBytes(&bytes, 0, 3, 16);
    try std.testing.expectEqual(IndirectStatus.unreadable, report.indirect_last_status);
    try std.testing.expectEqual(@as(u64, 1), report.indirect_unreadable);
    try std.testing.expectEqual(@as(u64, 0), report.indirect_dwords_read);
    try std.testing.expectEqual(@as(?u32, 0x200), report.indirect_last_missing_address);
    try std.testing.expectEqual(@as(u64, 0), report.draws);
}

test "Xenos runtime exposes native Vulkan fence completion as a guest event" {
    var runtime = Runtime.init();
    runtime.noteNativeFenceComplete(0x1234);
    try std.testing.expect(runtime.interrupts.last_event != null);
    try std.testing.expectEqual(@as(u32, 0x1234), runtime.interrupts.last_event.?.id);
    try std.testing.expectEqual(@as(u32, 1), runtime.interrupts.last_event.?.value);
}

test "Xenos runtime preserves programmed MRT color targets" {
    var runtime = Runtime.init();
    runtime.executor.register_file.write(registers.RB_COLOR_INFO, 0x101 | (6 << 16));
    runtime.executor.register_file.write(registers.RB_COLOR_INFO + 1, 0x202 | (7 << 16));
    const state = runtime.pipelineState();
    try std.testing.expectEqual(@as(u8, 2), state.color_target_count);
    try std.testing.expect(state.color_targets[0].format != 0);
    try std.testing.expect(state.color_targets[1].format != 0);
}

test "Xenos runtime distinguishes default target structure from programmed target evidence" {
    var runtime = Runtime.init();
    try std.testing.expect(!runtime.renderTargetEvidence().state_observed);
    runtime.executor.register_file.write(registers.RB_SURFACE_INFO, 1280);
    runtime.executor.register_file.write(registers.RB_COLOR_INFO, 0x101 | (6 << 16));
    const evidence = runtime.renderTargetEvidence();
    try std.testing.expect(evidence.state_observed);
    try std.testing.expect(evidence.plausible);
    try std.testing.expectEqual(@as(u32, 1280), evidence.surface_pitch_pixels);
    try std.testing.expectEqual(@as(u32, 6), evidence.color_format);
}

test "Xenos runtime exposes typed resource and pipeline state" {
    var runtime = Runtime.init();
    runtime.executor.register_file.write(registers.shader_constant_fetch_base + 0, 2);
    runtime.executor.register_file.write(registers.shader_constant_fetch_base + 1, 3 | (1 << 6) | (2 << 9) | (0x12 << 12));
    runtime.executor.register_file.write(registers.shader_constant_fetch_base + 2, 31 | (63 << 13));
    runtime.executor.register_file.write(registers.shader_constant_fetch_base + 3, 1 | (0xA55 << 1));
    runtime.executor.register_file.write(registers.shader_constant_fetch_base + 4, 1 << 12);
    runtime.executor.register_file.write(registers.shader_constant_fetch_base + 5, 1 << 9);
    runtime.executor.register_file.write(registers.shader_constant_alu_base, 11);
    runtime.executor.register_file.write(registers.shader_constant_alu_base + 1, 22);
    runtime.executor.register_file.write(registers.shader_constant_alu_base + 2, 33);
    runtime.executor.register_file.write(registers.shader_constant_alu_base + 3, 44);
    runtime.executor.register_file.write(registers.RB_COLOR_INFO, 0x101 | (6 << 16));
    runtime.executor.register_file.write(registers.RB_COLORCONTROL, 1 << 4);
    runtime.executor.register_file.write(registers.PA_SU_SC_MODE_CNTL, 1 << 11);
    runtime.executor.register_file.write(registers.PA_SU_POLY_OFFSET_FRONT_SCALE, @bitCast(@as(f32, 2)));
    runtime.executor.register_file.write(registers.PA_SU_POLY_OFFSET_FRONT_OFFSET, @bitCast(@as(f32, 3)));
    const fetch = runtime.textureFetch(0).?;
    var bindings: [2]TextureBinding = undefined;
    const binding_count = runtime.textureBindings(&bindings);
    const constant = runtime.aluConstant(0).?;
    const state = runtime.pipelineState();
    try std.testing.expectEqual(registers.FetchConstantType.texture, fetch.type);
    try std.testing.expectEqual(@as(u32, 32), fetch.width);
    try std.testing.expectEqual(@as(usize, 1), binding_count);
    try std.testing.expectEqual(@as(u8, 0), bindings[0].fetch_constant);
    try std.testing.expectEqual(@as(u32, 11), constant[0]);
    try std.testing.expectEqual(@as(u32, 44), constant[3]);
    try std.testing.expect(state.depth_bias_enable);
    try std.testing.expectEqual(@as(f32, 2), state.depth_bias_slope);
    try std.testing.expectEqual(@as(f32, 3), state.depth_bias_constant);
    try std.testing.expect(state.alpha_to_coverage);
}

test "Xenos runtime caches a shader loaded by IM_LOAD_IMMEDIATE" {
    var bytes = [_]u8{0} ** 64;
    const packet = pm4.packetType3(.im_load_immediate, 10, false).?;
    const add = @as(u32, @intFromEnum(shader.AluOp.add));
    const payload = [_]u32{ 0, 8, 0, 4, 1, 16, add, 1, 2, 3 };
    std.mem.writeInt(u32, bytes[0..4], packet, .big);
    for (payload, 0..) |word, index| {
        std.mem.writeInt(u32, bytes[(index + 1) * 4 ..][0..4], word, .big);
    }
    var runtime = Runtime.init();
    _ = try runtime.executeRingBytes(&bytes, 0, payload.len + 1, 16);
    try std.testing.expect(runtime.last_shader_source_hash != 0);
    try std.testing.expectEqual(shader.ShaderType.vertex, runtime.last_shader_type);
    try std.testing.expectEqual(@as(u64, 1), runtime.shader_cache.misses);
}

test "retained inspection programs state without publishing duplicate effects" {
    // The retained-batch path replays a batch the emulator's command processor
    // has already drained, so its MEM_WRITE packets have already landed in
    // guest memory.  Re-applying them would make Rosette overwrite fence and
    // progress values the guest has since advanced.  Attaching a null write
    // callback is what prevents that, and this proves the price is only the
    // writes: register state, draw observation and target evidence all survive,
    // while completion publication remains owned by the original execution.
    var bytes = [_]u8{0} ** 128;
    var offset: usize = 0;

    // Program the colour target through a type-0 register write.
    const reg_header = pm4.packetType0(registers.RB_COLOR_INFO, 1, false).?;
    std.mem.writeInt(u32, bytes[offset..][0..4], reg_header, .big);
    std.mem.writeInt(u32, bytes[offset + 4 ..][0..4], 0x101 | (6 << 16), .big);
    offset += 8;

    // A memory write the drained batch already performed.
    const mem_header = pm4.packetType3(.mem_write, 2, false).?;
    std.mem.writeInt(u32, bytes[offset..][0..4], mem_header, .big);
    std.mem.writeInt(u32, bytes[offset + 4 ..][0..4], 0x100, .big);
    std.mem.writeInt(u32, bytes[offset + 8 ..][0..4], 0xDEAD_BEEF, .big);
    offset += 12;

    // A draw, so completion evidence exists.
    const draw_header = pm4.packetType3(.draw_indx_2, 1, false).?;
    std.mem.writeInt(u32, bytes[offset..][0..4], draw_header, .big);
    std.mem.writeInt(u32, bytes[offset + 4 ..][0..4], (registers.DrawInitiator{
        .primitive = .triangle_list,
        .source = .auto_index,
        .major_mode_explicit = false,
        .index_format = .uint16,
        .not_end_of_pipe = false,
        .index_count = 3,
    }).encode(), .big);
    offset += 8;

    var memory = IndirectMemoryFixture{};
    var runtime = Runtime.init();
    runtime.attachMemory(&memory, IndirectMemoryFixture.read, &memory, null);
    const report = try runtime.inspectRetainedRingBytes(&bytes, 0, @intCast(offset / 4), 32);

    try std.testing.expectEqual(@as(u64, 1), report.draws);
    try std.testing.expectEqual(ExecutionDisposition.retained_observation, report.disposition);
    try std.testing.expectEqual(@as(u64, 1), report.draw_completion_observations);
    try std.testing.expectEqual(@as(u64, 0), report.draw_completion_signals);
    try std.testing.expectEqual(@as(u64, 1), runtime.retained_draw_observations);
    try std.testing.expectEqual(@as(u64, 0), runtime.draw_completion_signals);
    try std.testing.expectEqual(@as(u8, 0), runtime.interrupts.pending_count);

    // The register file carries the programmed target, which is the whole
    // reason the retained batch is replayed at all.
    const evidence = runtime.renderTargetEvidence();
    try std.testing.expect(evidence.state_observed);
    try std.testing.expect(evidence.raw_color_info != 0);

    // The guest write was counted, not applied.
    try std.testing.expectEqual(@as(u64, 1), runtime.executor.deferred_memory_count);
}

test "the same batch with a write callback attached does apply its guest writes" {
    // The counterpart to the read-only replay: the outstanding-span path
    // executes a batch whose writes have *not* happened yet, and there the
    // callback must fire.  Keeping both tests side by side makes the choice a
    // decision rather than an oversight.
    var bytes = [_]u8{0} ** 64;
    const mem_header = pm4.packetType3(.mem_write, 2, false).?;
    std.mem.writeInt(u32, bytes[0..4], mem_header, .big);
    std.mem.writeInt(u32, bytes[4..8], 0x100, .big);
    std.mem.writeInt(u32, bytes[8..12], 0xDEAD_BEEF, .big);

    var memory = IndirectMemoryFixture{};
    var runtime = Runtime.init();
    runtime.attachMemory(&memory, IndirectMemoryFixture.read, &memory, IndirectMemoryFixture.write);
    _ = try runtime.executeRingBytes(&bytes, 0, 3, 16);
    try std.testing.expectEqual(@as(u64, 0), runtime.executor.deferred_memory_count);
    try std.testing.expectEqual(@as(u32, 0xDEAD_BEEF), memory.words[0x100 / 4]);
}
