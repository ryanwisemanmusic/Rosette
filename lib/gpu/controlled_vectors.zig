//! Known-good PM4 streams that exercise the render path without a title.
//!
//! Why this exists
//! ---------------
//! The audit's recommended order puts this before relying on Halo: run a known
//! clear, a triangle and a resolve through the same command processor and
//! presenter, and see which of the six render-target verdicts they reach. That
//! separates "the emulator cannot render" from "this title has not asked it
//! to", which is a distinction the 2026-08-31 run could not make — its
//! twenty-four draws were all `no_rasterization_no_memexport`, and nothing
//! else had ever tried.
//!
//! A vector states what it expects. The point is not that a vector renders; it
//! is that a vector's *expectation* is written down in advance, so a run that
//! falls short says which stage and by how much rather than producing a number
//! for a human to judge.
//!
//! What a vector never is
//! ----------------------
//! A vector is `SourceClass.diagnostic` for its whole life. It can prove the
//! emulator's render path works end to end; it can never be counted as the
//! title rendering, and its frames never satisfy a title contract.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");
const render_target_evidence = @import("render_target_evidence.zig");
const pm4 = @import("pm4.zig");
const pm4_executor = @import("pm4_executor.zig");
const regs = @import("xenos_registers.zig");

pub const SourceClass = bridge.contract.SourceClass;
pub const Verdict = render_target_evidence.Verdict;
pub const verdict_count = render_target_evidence.verdict_count;

/// The vectors, ordered by how much of the path each one exercises. A run
/// should stop at the first one that falls short of its expectation.
pub const Vector = enum(u8) {
    /// Program a target and clear it. The shortest path to a changed EDRAM
    /// range.
    color_clear = 0,
    /// Clear depth. Separated because a depth-only target exercises different
    /// register decoding.
    depth_clear = 1,
    /// One triangle into a bound colour target.
    single_triangle = 2,
    /// A triangle with a texture fetch, which brings the sampler and format
    /// conversion paths in.
    textured_triangle = 3,
    /// Resolve a cleared target into guest-visible memory.
    resolve_to_memory = 4,
    /// Encode and consume a swap packet against a resolved frontbuffer.
    swap_packet = 5,

    pub fn label(self: Vector) []const u8 {
        return switch (self) {
            .color_clear => "color-clear",
            .depth_clear => "depth-clear",
            .single_triangle => "single-triangle",
            .textured_triangle => "textured-triangle",
            .resolve_to_memory => "resolve-to-memory",
            .swap_packet => "swap-packet",
        };
    }

    /// What this vector must reach to be called passing.
    pub fn expectation(self: Vector) Verdict {
        return switch (self) {
            .color_clear, .depth_clear => .edram_modified,
            .single_triangle, .textured_triangle => .edram_modified,
            .resolve_to_memory => .resolved_to_guest_memory,
            .swap_packet => .frame_candidate_published,
        };
    }

    /// The vector that must pass before this one is worth running. Running a
    /// resolve vector against a path that cannot clear a target produces a
    /// failure whose cause is one stage upstream.
    pub fn prerequisite(self: Vector) ?Vector {
        return switch (self) {
            .color_clear => null,
            .depth_clear => .color_clear,
            .single_triangle => .color_clear,
            .textured_triangle => .single_triangle,
            .resolve_to_memory => .color_clear,
            .swap_packet => .resolve_to_memory,
        };
    }

    pub fn describe(self: Vector) []const u8 {
        return switch (self) {
            .color_clear => "program a colour target and clear it. If this does not change an EDRAM range, no title will render either and the frontier is in the emulator",
            .depth_clear => "the same for depth, which decodes different registers and can fail on its own",
            .single_triangle => "one triangle into a bound colour target. This is where rasterization, the pipeline and the shader translator all have to work at once",
            .textured_triangle => "a triangle with a texture fetch, bringing sampler state and format conversion in",
            .resolve_to_memory => "copy a cleared target into guest-visible memory and prove the checksum changed on the guest's own route",
            .swap_packet => "encode a swap against a resolved frontbuffer and consume it. The last emulator-owned step before a title's own present",
        };
    }
};

pub const vector_count: usize = @typeInfo(Vector).@"enum".fields.len;

pub const ProgramError = error{
    invalid_configuration,
    program_too_large,
    invalid_program,
};

/// Inputs for a diagnostic program. The addresses are supplied by the caller
/// after it has established real guest mappings; the builder never allocates a
/// surface or pretends that a title owns one. Xenos color targets live in
/// EDRAM, so `target_physical_address` is retained as caller-owned diagnostic
/// identity only — it is deliberately not written into `RB_COLOR_INFO` as if
/// that register held a byte address.
pub const ProgramConfig = struct {
    target_physical_address: u32 = 0x0100_0000,
    resolve_physical_address: u32 = 0x0200_0000,
    vertex_physical_address: u32 = 0x0300_0000,
    completion_physical_address: u32 = 0x0400_0000,
    width: u32 = 640,
    height: u32 = 480,
    clear_color: u32 = 0x1020_3040,
    completion_value: u32 = 1,
    completion_event: u32 = 3,
};

pub const program_capacity: usize = 256;

pub const Program = struct {
    vector: Vector = .color_clear,
    source: SourceClass = .diagnostic,
    target_physical_address: u32 = 0,
    resolve_physical_address: u32 = 0,
    vertex_physical_address: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    dwords: [program_capacity]u32 = [_]u32{0} ** program_capacity,
    dword_count: usize = 0,

    /// Build an actual PM4 stream for the selected diagnostic vector. This is
    /// the same packet language consumed by Xenia's command processor; it is
    /// not a direct Vulkan shortcut and it never enters the title's output
    /// accounting.
    pub fn build(vector: Vector, config: ProgramConfig) ProgramError!Program {
        if (config.target_physical_address == 0 or config.resolve_physical_address == 0 or
            config.vertex_physical_address == 0 or
            config.completion_physical_address == 0 or
            (config.target_physical_address & 0xFFF) != 0 or
            (config.resolve_physical_address & 0xFFF) != 0 or
            (config.completion_physical_address & 0x3) != 0 or
            (config.vertex_physical_address & 0x3) != 0 or
            config.width < 64 or config.height < 64 or config.width > 4096 or config.height > 4096)
        {
            return error.invalid_configuration;
        }
        var program = Program{
            .vector = vector,
            .target_physical_address = config.target_physical_address,
            .resolve_physical_address = config.resolve_physical_address,
            .vertex_physical_address = config.vertex_physical_address,
            .width = config.width,
            .height = config.height,
        };
        try program.appendTargetSetup(config);
        switch (vector) {
            .color_clear => try program.appendClear(config),
            .depth_clear => try program.appendDepthClear(),
            .single_triangle => {
                try program.appendClear(config);
                try program.appendTriangle(false);
            },
            .textured_triangle => {
                try program.appendClear(config);
                try program.appendTextureProbe(config);
                try program.appendTriangle(true);
            },
            .resolve_to_memory => {
                try program.appendClear(config);
                try program.appendResolve();
            },
            .swap_packet => {
                try program.appendClear(config);
                try program.appendResolve();
                // The completion is intentionally before XE_SWAP: this makes
                // the diagnostic's synchronization causality explicit and
                // prevents presentation from being mistaken for completion.
                try program.appendCompletion(config);
                try program.appendSwap(config);
            },
        }
        if (vector != .swap_packet) try program.appendCompletion(config);
        try program.validate();
        return program;
    }

    pub fn words(self: *const Program) []const u32 {
        return self.dwords[0..self.dword_count];
    }

    /// Run the stream through Rosette's bounded PM4 executor model. A real
    /// Xenia run uses the corresponding opt-in diagnostic handoff to feed the
    /// same stream through its command processor/backend. This model is a
    /// deterministic contract test, never title output.
    pub fn executeModel(self: *const Program, executor: *pm4_executor.Executor) !void {
        try executor.execute(self.words());
    }

    pub fn validate(self: *const Program) ProgramError!void {
        if (self.source != .diagnostic or self.dword_count == 0) return error.invalid_program;
        var index: usize = 0;
        var target_programmed = false;
        var draw_count: u32 = 0;
        var clear_draw_count: u32 = 0;
        var resolve_draw_count: u32 = 0;
        var color_clear_programmed = false;
        var depth_clear_programmed = false;
        var color_clear_enabled = false;
        var depth_clear_enabled = false;
        var resolve_destination_programmed = false;
        var copy_mode = false;
        var copy_control: u32 = 0;
        var resolve_requested = false;
        var completion_requested = false;
        var swap_requested = false;
        while (index < self.dword_count) {
            const header = pm4.decodeHeader(self.dwords[index]);
            const total: usize = @intCast(header.totalDwords());
            if (total == 0 or total > self.dword_count - index) return error.invalid_program;
            switch (header.kind) {
                .type0 => {
                    if (header.register_index == regs.RB_COLOR_INFO or
                        (header.register_index <= regs.RB_COLOR_INFO and
                            @as(u32, header.register_index) + header.count > regs.RB_COLOR_INFO))
                    {
                        target_programmed = true;
                    }
                    const payload = self.dwords[index + 1 .. index + total];
                    for (payload, 0..) |value, offset| {
                        const register = @as(u32, header.register_index) + @as(u32, @intCast(offset));
                        switch (register) {
                            regs.RB_MODECONTROL => copy_mode = (value & 0x7) == 6,
                            regs.RB_COPY_CONTROL => {
                                copy_control = value;
                                if ((value & (1 << 8)) != 0) color_clear_enabled = true;
                                if ((value & (1 << 9)) != 0) depth_clear_enabled = true;
                            },
                            regs.RB_COLOR_CLEAR, regs.RB_COLOR_CLEAR_LO => color_clear_programmed = true,
                            regs.RB_DEPTH_CLEAR => depth_clear_programmed = true,
                            regs.RB_COPY_DEST_BASE => resolve_destination_programmed = value != 0,
                            else => {},
                        }
                    }
                },
                .type3 => switch (header.opcode) {
                    .draw_indx, .draw_indx_2, .draw_indx_bin, .draw_indx_2_bin => {
                        draw_count += 1;
                        if (copy_mode) {
                            if ((copy_control & ((1 << 8) | (1 << 9))) != 0) {
                                clear_draw_count += 1;
                            } else {
                                resolve_draw_count += 1;
                                resolve_requested = true;
                            }
                        }
                    },
                    .event_write_shd => {
                        completion_requested = true;
                    },
                    .xe_swap => swap_requested = true,
                    else => {},
                },
                .type1, .type2 => {},
            }
            index += total;
        }
        const valid = switch (self.vector) {
            .color_clear => target_programmed and color_clear_programmed and color_clear_enabled and clear_draw_count != 0,
            .depth_clear => target_programmed and depth_clear_programmed and depth_clear_enabled and clear_draw_count != 0,
            .single_triangle => target_programmed and color_clear_programmed and color_clear_enabled and
                clear_draw_count != 0 and draw_count >= 2,
            .textured_triangle => target_programmed and color_clear_programmed and color_clear_enabled and
                clear_draw_count != 0 and draw_count >= 2,
            .resolve_to_memory => target_programmed and color_clear_programmed and color_clear_enabled and
                clear_draw_count != 0 and resolve_destination_programmed and resolve_draw_count != 0 and
                resolve_requested and completion_requested,
            .swap_packet => target_programmed and resolve_destination_programmed and resolve_draw_count != 0 and
                resolve_requested and completion_requested and swap_requested,
        };
        if (!valid) return error.invalid_program;
    }

    fn appendTargetSetup(self: *Program, config: ProgramConfig) ProgramError!void {
        const surface_pitch = alignPixels(config.width);
        const surface_info = surface_pitch & 0x3FFF;
        // RB_COLOR_INFO::color_base is an EDRAM tile index, not a physical
        // byte address. Base tile zero is the first legal diagnostic target;
        // the caller-owned address remains metadata on ProgramConfig.
        const color_info: u32 = 0;
        const depth_info: u32 = 0; // D24S8, depth base tile zero.
        const scissor_br = (config.width & 0x7FFF) | ((config.height & 0x7FFF) << 16);
        const copy_dest_info = @as(u32, 2) | (@as(u32, 6) << 7); // 8in32, 8_8_8_8.
        const copy_dest_pitch = surface_pitch | (config.height << 16);
        try self.appendType0(regs.RB_MODECONTROL, &.{0});
        try self.appendType0(regs.RB_SURFACE_INFO, &.{surface_info});
        try self.appendType0(regs.RB_COLOR_INFO, &.{color_info});
        try self.appendType0(regs.RB_DEPTH_INFO, &.{depth_info});
        try self.appendType0(regs.RB_COLOR_MASK, &.{0xF});
        try self.appendType0(regs.RB_COLORCONTROL, &.{0});
        try self.appendType0(regs.RB_DEPTHCONTROL, &.{0});
        try self.appendType0(regs.RB_BLENDCONTROL0, &.{0});
        try self.appendType0(regs.PA_SU_SC_MODE_CNTL, &.{0});
        try self.appendType0(regs.PA_SU_VTX_CNTL, &.{0});
        try self.appendType0(regs.PA_SC_WINDOW_OFFSET, &.{0});
        try self.appendType0(regs.PA_SC_WINDOW_SCISSOR_TL, &.{0x8000_0000});
        try self.appendType0(regs.PA_SC_WINDOW_SCISSOR_BR, &.{scissor_br});
        try self.appendType0(regs.PA_SC_SCREEN_SCISSOR_TL, &.{0});
        try self.appendType0(regs.PA_SC_SCREEN_SCISSOR_BR, &.{scissor_br});
        try self.appendType0(regs.PA_CL_VTE_CNTL, &.{0});
        try self.appendType0(regs.RB_COPY_DEST_BASE, &.{config.resolve_physical_address});
        try self.appendType0(regs.RB_COPY_DEST_PITCH, &.{copy_dest_pitch});
        try self.appendType0(regs.RB_COPY_DEST_INFO, &.{copy_dest_info});
        const vertex_fetch = [_]u32{
            @as(u32, @intFromEnum(regs.FetchConstantType.vertex)) |
                ((config.vertex_physical_address >> 2) << 2),
            @as(u32, @intFromEnum(regs.Endian.@"8in32")) | (6 << 2),
        };
        try self.appendType0(pm4.shader_constant_fetch_00_0, &vertex_fetch);
    }

    fn appendClear(self: *Program, config: ProgramConfig) ProgramError!void {
        try self.appendType0(regs.RB_MODECONTROL, &.{6});
        try self.appendType0(regs.RB_COPY_CONTROL, &.{1 << 8});
        try self.appendType0(regs.RB_COLOR_CLEAR, &.{config.clear_color});
        try self.appendType0(regs.RB_COLOR_CLEAR_LO, &.{0});
        try self.appendType0(regs.RB_COLORCONTROL, &.{0});
        try self.appendType0(regs.RB_BLENDCONTROL0, &.{0});
        try self.appendRectangleDraw();
    }

    fn appendDepthClear(self: *Program) ProgramError!void {
        try self.appendType0(regs.RB_MODECONTROL, &.{6});
        try self.appendType0(regs.RB_COPY_CONTROL, &.{4 | (1 << 9)});
        try self.appendType0(regs.RB_DEPTH_CLEAR, &.{0x00FF_FFFF});
        try self.appendRectangleDraw();
    }

    fn appendTriangle(self: *Program, textured: bool) ProgramError!void {
        if (textured) try self.appendType0(regs.SQ_CONTEXT_MISC, &.{0x1});
        try self.appendType0(regs.SQ_PROGRAM_CNTL, &.{0x0101});
        const initiator = regs.DrawInitiator{
            .primitive = .triangle_list,
            .source = .auto_index,
            .major_mode_explicit = false,
            .index_format = .uint16,
            .not_end_of_pipe = false,
            .index_count = 3,
        };
        try self.appendType3(.draw_indx_2, &.{initiator.encode()});
    }

    fn appendRectangleDraw(self: *Program) ProgramError!void {
        const initiator = regs.DrawInitiator{
            .primitive = .rectangle_list,
            .source = .auto_index,
            .major_mode_explicit = false,
            .index_format = .uint16,
            .not_end_of_pipe = false,
            .index_count = 3,
        };
        try self.appendType3(.draw_indx_2, &.{initiator.encode()});
    }

    fn appendTextureProbe(self: *Program, config: ProgramConfig) ProgramError!void {
        // Fetch constant 1 is kept separate from vertex fetch constant 0,
        // which the resolve draw consumes. It is a real Xenos descriptor for
        // the caller-owned resolve mapping; the diagnostic has no title shader
        // and therefore must not claim that a sample was actually executed.
        const fetch = textureFetchWords(config);
        try self.appendType0(pm4.shader_constant_fetch_00_0 + 6, &fetch);
    }

    fn appendResolve(self: *Program) ProgramError!void {
        try self.appendType0(regs.RB_MODECONTROL, &.{6});
        try self.appendType0(regs.RB_COPY_CONTROL, &.{0});
        try self.appendRectangleDraw();
    }

    fn appendCompletion(self: *Program, config: ProgramConfig) ProgramError!void {
        try self.appendType3(.event_write_shd, &.{
            config.completion_event,
            config.completion_physical_address,
            config.completion_value,
        });
    }

    fn appendSwap(self: *Program, config: ProgramConfig) ProgramError!void {
        const fetch = pm4.FetchConstant{ .dwords = textureFetchWords(config) };
        var swap_storage: [pm4.swap_reservation_dwords]u32 = undefined;
        const written = pm4.encodeSwapSequence(&swap_storage, fetch, .{
            .frontbuffer_physical_address = config.resolve_physical_address,
            .width = config.width,
            .height = config.height,
        }, pm4.swap_reservation_dwords) orelse return error.invalid_program;
        for (swap_storage[0..written]) |word| try self.appendWord(word);
    }

    fn appendType0(self: *Program, register: u32, values: []const u32) ProgramError!void {
        if (register > std.math.maxInt(u16) or values.len == 0 or values.len > 0x4000) return error.invalid_program;
        try self.appendWord(pm4.packetType0(@intCast(register), @intCast(values.len), false) orelse return error.invalid_program);
        for (values) |value| try self.appendWord(value);
    }

    fn appendType3(self: *Program, opcode: pm4.Type3Opcode, values: []const u32) ProgramError!void {
        if (values.len == 0 or values.len > 0x4000) return error.invalid_program;
        try self.appendWord(pm4.packetType3(opcode, @intCast(values.len), false) orelse return error.invalid_program);
        for (values) |value| try self.appendWord(value);
    }

    fn appendWord(self: *Program, word: u32) ProgramError!void {
        if (self.dword_count == self.dwords.len) return error.program_too_large;
        self.dwords[self.dword_count] = word;
        self.dword_count += 1;
    }
};

fn alignPixels(value: u32) u32 {
    return (value + 31) & ~@as(u32, 31);
}

fn textureFetchWords(config: ProgramConfig) [6]u32 {
    const base_page = config.resolve_physical_address >> 12;
    const pitch = (alignPixels(config.width) >> 5) & 0x1FF;
    const width = (config.width - 1) & 0x1FFF;
    const height = (config.height - 1) & 0x1FFF;
    const clamp_to_edge: u32 = 2;
    // Xenos encodes R,G,B,A as 0,1,2,3 in three-bit lanes.
    const swizzle_rgba: u32 = 0x688;
    return .{
        @as(u32, @intFromEnum(regs.FetchConstantType.texture)) |
            (clamp_to_edge << 10) | (clamp_to_edge << 13) | (clamp_to_edge << 16) |
            (pitch << 22) | 0x8000_0000,
        @as(u32, 6) | (@as(u32, @intFromEnum(regs.Endian.@"8in32")) << 6) |
            ((base_page & 0xFFFFF) << 12),
        width | (height << 13),
        swizzle_rgba << 1,
        0,
        (@as(u32, 1) << 9) | ((base_page & 0xFFFFF) << 12),
    };
}

fn hasRegisterValue(program: *const Program, register: u32, expected: u32) bool {
    var index: usize = 0;
    while (index < program.dword_count) {
        const header = pm4.decodeHeader(program.dwords[index]);
        const total: usize = @intCast(header.totalDwords());
        if (total == 0 or total > program.dword_count - index) return false;
        if (header.kind == .type0) {
            const payload = program.dwords[index + 1 .. index + total];
            for (payload, 0..) |value, offset| {
                const addressed = @as(u32, header.register_index) + @as(u32, @intCast(offset));
                if (addressed == register and value == expected) return true;
            }
        }
        index += total;
    }
    return false;
}

fn hasOpcode(program: *const Program, opcode: pm4.Type3Opcode) bool {
    var index: usize = 0;
    while (index < program.dword_count) {
        const header = pm4.decodeHeader(program.dwords[index]);
        const total: usize = @intCast(header.totalDwords());
        if (total == 0 or total > program.dword_count - index) return false;
        if (header.kind == .type3 and header.opcode == opcode) return true;
        index += total;
    }
    return false;
}

fn hasDrawPrimitive(program: *const Program, primitive: regs.PrimitiveType) bool {
    var index: usize = 0;
    while (index < program.dword_count) {
        const header = pm4.decodeHeader(program.dwords[index]);
        const total: usize = @intCast(header.totalDwords());
        if (total == 0 or total > program.dword_count - index) return false;
        if (header.kind == .type3 and header.opcode == .draw_indx_2 and header.count >= 1) {
            const initiator = regs.DrawInitiator.decode(program.dwords[index + 1]);
            if (initiator.primitive == primitive) return true;
        }
        index += total;
    }
    return false;
}

test "controlled programs encode the real Xenos clear, resolve, and swap stages" {
    const config = ProgramConfig{};
    const clear = try Program.build(.color_clear, config);
    try std.testing.expect(hasRegisterValue(&clear, regs.RB_MODECONTROL, 6));
    try std.testing.expect(hasRegisterValue(&clear, regs.RB_COPY_CONTROL, 1 << 8));
    try std.testing.expect(hasRegisterValue(&clear, regs.RB_COLOR_CLEAR, config.clear_color));
    try std.testing.expect(hasDrawPrimitive(&clear, .rectangle_list));
    try std.testing.expect(hasOpcode(&clear, .event_write_shd));
    try std.testing.expect(!hasOpcode(&clear, .event_write));

    const depth = try Program.build(.depth_clear, config);
    try std.testing.expect(hasRegisterValue(&depth, regs.RB_COPY_CONTROL, 4 | (1 << 9)));
    try std.testing.expect(hasRegisterValue(&depth, regs.RB_DEPTH_CLEAR, 0x00FF_FFFF));
    try std.testing.expect(hasDrawPrimitive(&depth, .rectangle_list));

    const resolve = try Program.build(.resolve_to_memory, config);
    try std.testing.expect(hasRegisterValue(&resolve, regs.RB_COLOR_INFO, 0));
    try std.testing.expect(!hasRegisterValue(&resolve, regs.RB_COLOR_INFO, (config.target_physical_address >> 12) | (6 << 16)));
    try std.testing.expect(hasRegisterValue(&resolve, regs.RB_COPY_DEST_BASE, config.resolve_physical_address));
    try std.testing.expect(hasRegisterValue(&resolve, regs.RB_COPY_CONTROL, 0));
    try std.testing.expect(hasRegisterValue(&resolve, regs.RB_COPY_DEST_INFO, 2 | (6 << 7)));
    try std.testing.expect(hasRegisterValue(&resolve, regs.RB_MODECONTROL, 6));
    try std.testing.expect(hasOpcode(&resolve, .event_write_shd));

    const swap = try Program.build(.swap_packet, config);
    try std.testing.expect(hasOpcode(&swap, .xe_swap));
    try std.testing.expect(hasOpcode(&swap, .event_write_shd));
    try std.testing.expect(hasDrawPrimitive(&swap, .rectangle_list));

    var executor = pm4_executor.Executor{};
    try swap.executeModel(&executor);
    const fetch = executor.register_file.textureFetch(0).?;
    try std.testing.expectEqual(regs.FetchConstantType.texture, fetch.type);
    try std.testing.expect(fetch.tiled);
    try std.testing.expectEqual(@as(u64, config.resolve_physical_address), fetch.base_address_bytes);
    try std.testing.expectEqual(config.width, fetch.width);
    try std.testing.expectEqual(config.height, fetch.height);
    try std.testing.expectEqual(@as(u64, 1), executor.swap_count);
}

test "every controlled PM4 vector is diagnostic and executable by the bounded model" {
    inline for (@typeInfo(Vector).@"enum".fields) |field| {
        const vector: Vector = @enumFromInt(field.value);
        const program = try Program.build(vector, .{});
        try std.testing.expectEqual(SourceClass.diagnostic, program.source);
        try program.validate();
        var executor = pm4_executor.Executor{};
        try program.executeModel(&executor);
    }
}

test "controlled PM4 configuration rejects unaligned or empty mappings" {
    try std.testing.expectError(
        error.invalid_configuration,
        Program.build(.color_clear, .{ .resolve_physical_address = 0 }),
    );
    try std.testing.expectError(
        error.invalid_configuration,
        Program.build(.color_clear, .{ .vertex_physical_address = 1 }),
    );
    try std.testing.expectError(
        error.invalid_configuration,
        Program.build(.color_clear, .{ .completion_physical_address = 2 }),
    );
    try std.testing.expectError(
        error.invalid_configuration,
        Program.build(.color_clear, .{ .width = 32 }),
    );
}

pub const Outcome = enum(u8) {
    /// Not run.
    not_run,
    /// Reached its expectation.
    passed,
    /// Ran and stopped short.
    fell_short,
    /// Not run because its prerequisite had not passed.
    skipped_prerequisite,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .not_run => "not-run",
            .passed => "passed",
            .fell_short => "FELL-SHORT",
            .skipped_prerequisite => "skipped-prerequisite",
        };
    }
};

pub const Result = struct {
    vector: Vector = .color_clear,
    outcome: Outcome = .not_run,
    /// The furthest verdict reached, whether or not it met the expectation.
    reached: ?Verdict = null,
    step: u64 = 0,
    /// Always diagnostic. Carried on the record so the class cannot be lost
    /// between the harness and the report.
    source: SourceClass = .diagnostic,
};

pub const Summary = struct {
    run: usize = 0,
    passed: usize = 0,
    fell_short: usize = 0,
    skipped: usize = 0,
    /// The first vector that fell short. Everything after it is downstream.
    first_failure: ?Vector = null,
    first_failure_reached: ?Verdict = null,

    /// The emulator's render path is proven as far as this vector.
    pub fn provenDepth(self: Summary) usize {
        return self.passed;
    }
};

pub const Suite = struct {
    results: [vector_count]Result = blk: {
        var table: [vector_count]Result = undefined;
        for (&table, 0..) |*entry, index| {
            entry.* = .{ .vector = @enumFromInt(index) };
        }
        break :blk table;
    },

    pub fn passed(self: *const Suite, vector: Vector) bool {
        return self.results[@intFromEnum(vector)].outcome == .passed;
    }

    /// Whether a vector may be run: its prerequisite has passed, or it has
    /// none. Running past a failed prerequisite produces a failure whose cause
    /// is somewhere else.
    pub fn eligible(self: *const Suite, vector: Vector) bool {
        const required = vector.prerequisite() orelse return true;
        return self.passed(required);
    }

    /// Record what a vector reached. The expectation decides the outcome; the
    /// harness does not get to say it passed.
    pub fn record(self: *Suite, vector: Vector, reached: ?Verdict, step: u64) Outcome {
        const slot = &self.results[@intFromEnum(vector)];
        slot.step = step;
        slot.reached = reached;
        if (!self.eligible(vector)) {
            slot.outcome = .skipped_prerequisite;
            return slot.outcome;
        }
        const wanted = vector.expectation();
        const met = reached != null and @intFromEnum(reached.?) >= @intFromEnum(wanted);
        slot.outcome = if (met) .passed else .fell_short;
        return slot.outcome;
    }

    pub fn summary(self: *const Suite) Summary {
        var out = Summary{};
        for (self.results) |result| {
            switch (result.outcome) {
                .not_run => continue,
                .passed => {
                    out.run += 1;
                    out.passed += 1;
                },
                .fell_short => {
                    out.run += 1;
                    out.fell_short += 1;
                    if (out.first_failure == null) {
                        out.first_failure = result.vector;
                        out.first_failure_reached = result.reached;
                    }
                },
                .skipped_prerequisite => out.skipped += 1,
            }
        }
        return out;
    }

    /// The audit's G4 gate: the render path proven as far as a resolve whose
    /// guest-visible content changed.
    pub fn meetsTargetGate(self: *const Suite) bool {
        return self.passed(.color_clear) and self.passed(.resolve_to_memory);
    }

    pub fn fingerprint(self: *const Suite) u64 {
        var hash: u64 = 0;
        for (self.results) |result| {
            hash = hash *% 31 +% @intFromEnum(result.outcome);
        }
        return hash;
    }
};

test "a vector passes only by reaching the verdict it declared in advance" {
    var suite = Suite{};
    try std.testing.expectEqual(Outcome.fell_short, suite.record(.color_clear, .target_memory_bound, 100));
    try std.testing.expect(!suite.passed(.color_clear));
    try std.testing.expectEqual(Outcome.passed, suite.record(.color_clear, .edram_modified, 200));
    try std.testing.expect(suite.passed(.color_clear));
    // Reaching further than the expectation still passes.
    try std.testing.expectEqual(Outcome.passed, suite.record(.color_clear, .frame_candidate_published, 300));
}

test "a vector whose prerequisite failed is skipped rather than failed" {
    var suite = Suite{};
    _ = suite.record(.color_clear, .state_programmed, 100);
    try std.testing.expect(!suite.eligible(.resolve_to_memory));
    try std.testing.expectEqual(
        Outcome.skipped_prerequisite,
        suite.record(.resolve_to_memory, null, 200),
    );
    const totals = suite.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.skipped);
    // The first failure is the upstream vector, not the skipped one.
    try std.testing.expectEqual(Vector.color_clear, totals.first_failure.?);
    try std.testing.expectEqual(Verdict.state_programmed, totals.first_failure_reached.?);
}

test "the target gate needs a clear and a resolve, both passing" {
    var suite = Suite{};
    _ = suite.record(.color_clear, .edram_modified, 100);
    try std.testing.expect(!suite.meetsTargetGate());
    _ = suite.record(.resolve_to_memory, .resolved_to_guest_memory, 200);
    try std.testing.expect(suite.meetsTargetGate());
    try std.testing.expectEqual(@as(usize, 2), suite.summary().provenDepth());
}

test "a vector that was never run is not a failure" {
    const suite = Suite{};
    const totals = suite.summary();
    try std.testing.expectEqual(@as(usize, 0), totals.run);
    try std.testing.expectEqual(@as(usize, 0), totals.fell_short);
    try std.testing.expect(totals.first_failure == null);
    try std.testing.expect(!suite.meetsTargetGate());
}

test "a vector is diagnostic and can never satisfy a title contract" {
    var suite = Suite{};
    _ = suite.record(.swap_packet, .frame_candidate_published, 100);
    const result = suite.results[@intFromEnum(Vector.swap_packet)];
    try std.testing.expectEqual(SourceClass.diagnostic, result.source);
    try std.testing.expect(!result.source.satisfiesTitleContract());
}

test "the dependency order runs from a clear to a swap" {
    try std.testing.expect(Vector.color_clear.prerequisite() == null);
    try std.testing.expectEqual(Vector.color_clear, Vector.single_triangle.prerequisite().?);
    try std.testing.expectEqual(Vector.single_triangle, Vector.textured_triangle.prerequisite().?);
    try std.testing.expectEqual(Vector.resolve_to_memory, Vector.swap_packet.prerequisite().?);

    inline for (@typeInfo(Vector).@"enum".fields) |field| {
        const vector: Vector = @enumFromInt(field.value);
        try std.testing.expect(vector.label().len != 0);
        try std.testing.expect(vector.describe().len != 0);
    }
    try std.testing.expectEqual(@as(usize, 6), vector_count);
}

test "the whole suite passing proves the emulator's path without a title" {
    var suite = Suite{};
    _ = suite.record(.color_clear, .edram_modified, 100);
    _ = suite.record(.depth_clear, .edram_modified, 110);
    _ = suite.record(.single_triangle, .edram_modified, 120);
    _ = suite.record(.textured_triangle, .edram_modified, 130);
    _ = suite.record(.resolve_to_memory, .resolved_to_guest_memory, 140);
    _ = suite.record(.swap_packet, .frame_candidate_published, 150);

    const totals = suite.summary();
    try std.testing.expectEqual(@as(usize, 6), totals.passed);
    try std.testing.expectEqual(@as(usize, 0), totals.fell_short);
    try std.testing.expect(totals.first_failure == null);
    try std.testing.expect(suite.meetsTargetGate());
}
