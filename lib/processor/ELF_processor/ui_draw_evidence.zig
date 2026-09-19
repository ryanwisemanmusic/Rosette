//! Read-only evidence at public ImGui / Xenia UI function boundaries.
//! CPU atlas bytes and a valid clip are not GPU upload or visible-pixel proof.
const std = @import("std");

pub const font_rgba_symbol = "_ZN11ImFontAtlas18GetTexDataAsRGBA32EPPhPiS2_S2_";
pub const lists_symbol = "_ZN2xe2ui11ImGuiDrawer15RenderDrawListsEP10ImDrawDataRNS0_13UIDrawContextE";
pub const draw_symbol = "_ZN2xe2ui6vulkan21VulkanImmediateDrawer4DrawERKNS0_13ImmediateDrawE";
pub const scissor_symbol = "_ZN2xe2ui15ImmediateDrawer21ScissorToRenderTargetERKNS0_13ImmediateDrawERjS5_S5_S5_";
pub const pipelines_symbol = "_ZN2xe2ui6vulkan21VulkanImmediateDrawer42EnsurePipelinesCreatedForCurrentRenderPassEv";

pub fn floatAt(bytes: []const u8, offset: usize) f32 {
    return @bitCast(std.mem.readInt(u32, bytes[offset..][0..4], .little));
}

pub const Evidence = struct {
    font_returns: u64 = 0,
    font_valid_returns: u64 = 0,
    font_invalid_returns: u64 = 0,
    font_unreadable_returns: u64 = 0,
    font_last_valid: bool = false,
    font_pixels: u64 = 0,
    font_width: i32 = 0,
    font_height: i32 = 0,
    lists_entries: u64 = 0,
    lists_unreadable: u64 = 0,
    lists_invalid: u64 = 0,
    lists_empty: u64 = 0,
    list_count: i32 = 0,
    vertex_count: i32 = 0,
    index_count: i32 = 0,
    draw_data_valid: bool = false,
    display_size: [2]f32 = .{ 0, 0 },
    display_pos: [2]f32 = .{ 0, 0 },
    framebuffer_scale: [2]f32 = .{ 0, 0 },
    owner_viewport: u64 = 0,
    first_list: u64 = 0,
    first_cmd: u64 = 0,
    first_vertex: u64 = 0,
    raw_cmd_clip: [4]f32 = .{ 0, 0, 0, 0 },
    raw_first_vertex: [2]f32 = .{ 0, 0 },
    raw_cmd_count: u32 = 0,
    raw_vertex_count: u32 = 0,
    raw_buffers_readable: bool = false,
    raw_list_flags: u32 = 0,
    raw_shared_data: u64 = 0,
    raw_cmd_header_clip: [4]f32 = .{ 0, 0, 0, 0 },
    raw_shared_clip: [4]f32 = .{ 0, 0, 0, 0 },
    raw_clip_stack_size: i32 = 0,
    raw_clip_stack_data: u64 = 0,
    raw_clip_stack_first: [4]f32 = .{ 0, 0, 0, 0 },
    raw_clip_stack_first_readable: bool = false,
    raw_list_internals_readable: bool = false,
    draw_entries: u64 = 0,
    draw_unreadable: u64 = 0,
    draw_empty: u64 = 0,
    draw_invalid_clip: u64 = 0,
    primitive: u32 = 0,
    draw_count: u32 = 0,
    texture: u64 = 0,
    scissor_enabled: bool = false,
    clip: [4]f32 = .{ 0, 0, 0, 0 },
    scissor_returns: u64 = 0,
    scissor_true: u64 = 0,
    scissor_false: u64 = 0,
    scissor_unreadable: u64 = 0,
    scissor_rect: [4]u32 = .{ 0, 0, 0, 0 },
    pipeline_true: u64 = 0,
    pipeline_false: u64 = 0,

    pub fn atlasByteCount(width: i32, height: i32) ?usize {
        if (width <= 0 or height <= 0) return null;
        const pixels = std.math.mul(usize, @intCast(width), @intCast(height)) catch return null;
        return std.math.mul(usize, pixels, 4) catch null;
    }

    pub fn noteFontReturn(self: *Evidence, pixels: u64, width: i32, height: i32, readable: bool) void {
        self.font_returns +|= 1;
        self.font_pixels = pixels;
        self.font_width = width;
        self.font_height = height;
        self.font_last_valid = false;
        if (pixels == 0 or atlasByteCount(width, height) == null) {
            self.font_invalid_returns +|= 1;
        } else if (!readable) {
            self.font_unreadable_returns +|= 1;
        } else {
            self.font_valid_returns +|= 1;
            self.font_last_valid = true;
        }
    }

    /// ImDrawData's Windows x64 public layout, checked by header_contract_test.cc.
    pub fn noteLists(self: *Evidence, memory: ?[]const u8) void {
        self.lists_entries +|= 1;
        const bytes = memory orelse {
            self.lists_unreadable +|= 1;
            return;
        };
        self.list_count = std.mem.readInt(i32, bytes[4..8], .little);
        self.index_count = std.mem.readInt(i32, bytes[8..12], .little);
        self.vertex_count = std.mem.readInt(i32, bytes[12..16], .little);
        self.draw_data_valid = bytes[0] != 0;
        self.display_pos = .{ floatAt(bytes, 32), floatAt(bytes, 36) };
        self.display_size = .{ floatAt(bytes, 40), floatAt(bytes, 44) };
        self.framebuffer_scale = .{ floatAt(bytes, 48), floatAt(bytes, 52) };
        self.owner_viewport = std.mem.readInt(u64, bytes[56..64], .little);
        if (!self.draw_data_valid or self.list_count < 0 or self.index_count < 0 or self.vertex_count < 0 or
            !std.math.isFinite(self.display_pos[0]) or !std.math.isFinite(self.display_pos[1]) or
            !std.math.isFinite(self.display_size[0]) or !std.math.isFinite(self.display_size[1]) or
            !std.math.isFinite(self.framebuffer_scale[0]) or !std.math.isFinite(self.framebuffer_scale[1]) or
            self.display_size[0] <= 0 or self.display_size[1] <= 0 or
            self.framebuffer_scale[0] <= 0 or self.framebuffer_scale[1] <= 0)
        {
            self.lists_invalid +|= 1;
        } else if (self.list_count == 0 or self.index_count == 0 or self.vertex_count == 0) {
            self.lists_empty +|= 1;
        }
    }

    /// Record the first public ImDrawList buffers behind ImDrawData. This is
    /// deliberately a one-list snapshot: it answers whether the bad clip is
    /// already present in ImGui's command buffer and whether the vertices are
    /// in the same coordinate space, without walking untrusted guest-owned
    /// counts or turning evidence into a second renderer.
    pub fn noteRawBuffers(
        self: *Evidence,
        first_list: u64,
        first_cmd: u64,
        first_vertex: u64,
        command_count: u32,
        vertex_count: u32,
        cmd_memory: ?[]const u8,
        vertex_memory: ?[]const u8,
    ) void {
        self.first_list = first_list;
        self.first_cmd = first_cmd;
        self.first_vertex = first_vertex;
        self.raw_cmd_count = command_count;
        self.raw_vertex_count = vertex_count;
        self.raw_buffers_readable = false;
        const cmd = cmd_memory orelse return;
        const vertex = vertex_memory orelse return;
        if (cmd.len < 16 or vertex.len < 8) return;
        for (&self.raw_cmd_clip, 0..) |*value, index| value.* = floatAt(cmd, index * 4);
        self.raw_first_vertex = .{ floatAt(vertex, 0), floatAt(vertex, 4) };
        self.raw_buffers_readable = true;
    }

    /// Snapshot the first list's private clip state without treating it as a
    /// renderer. These are the Windows x64 offsets from the read-only Xenia
    /// ImGui layout: `_Data` +56, `_CmdHeader` +96, and `_ClipRectStack`
    /// +152. The shared fullscreen rectangle begins at +48 in
    /// ImDrawListSharedData.
    pub fn noteRawListInternals(
        self: *Evidence,
        list_memory: ?[]const u8,
        shared_memory: ?[]const u8,
        stack_memory: ?[]const u8,
    ) void {
        self.raw_list_internals_readable = false;
        const list = list_memory orelse return;
        if (list.len < 168) return;

        self.raw_list_flags = std.mem.readInt(u32, list[48..52], .little);
        self.raw_shared_data = std.mem.readInt(u64, list[56..64], .little);
        for (&self.raw_cmd_header_clip, 0..) |*value, index| value.* = floatAt(list, 96 + index * 4);
        self.raw_clip_stack_size = std.mem.readInt(i32, list[152..156], .little);
        self.raw_clip_stack_data = std.mem.readInt(u64, list[160..168], .little);
        self.raw_clip_stack_first_readable = false;
        if (shared_memory) |shared| {
            if (shared.len >= 16) {
                for (&self.raw_shared_clip, 0..) |*value, index| value.* = floatAt(shared, index * 4);
            }
        }
        if (self.raw_clip_stack_size > 0 and self.raw_clip_stack_data != 0) {
            // One ImVec4 is enough to distinguish the stack's first push from
            // a later command-header mutation without walking guest counts.
            if (stack_memory) |stack| {
                if (stack.len >= 16) {
                    for (&self.raw_clip_stack_first, 0..) |*value, index| value.* = floatAt(stack, index * 4);
                    self.raw_clip_stack_first_readable = true;
                }
            }
        }
        self.raw_list_internals_readable = true;
    }

    /// ImmediateDraw's public layout; never probe private drawer/batch offsets.
    pub fn noteDraw(self: *Evidence, memory: ?[]const u8) void {
        self.draw_entries +|= 1;
        const bytes = memory orelse {
            self.draw_unreadable +|= 1;
            return;
        };
        self.primitive = std.mem.readInt(u32, bytes[0..4], .little);
        self.draw_count = std.mem.readInt(u32, bytes[4..8], .little);
        self.texture = std.mem.readInt(u64, bytes[16..24], .little);
        self.scissor_enabled = bytes[24] != 0;
        for (&self.clip, 0..) |*value, index| value.* = floatAt(bytes, 28 + index * 4);
        if (self.draw_count == 0) self.draw_empty +|= 1;
        if (self.scissor_enabled) {
            for (self.clip) |value| {
                if (!std.math.isFinite(value)) {
                    self.draw_invalid_clip +|= 1;
                    return;
                }
            }
            if (self.clip[2] <= self.clip[0] or self.clip[3] <= self.clip[1]) self.draw_invalid_clip +|= 1;
        }
    }

    pub fn noteScissorReturn(self: *Evidence, accepted: bool, rect: ?[4]u32) void {
        self.scissor_returns +|= 1;
        if (accepted) {
            self.scissor_true +|= 1;
            // A false return need not initialize the output references.
            if (rect) |value| self.scissor_rect = value else self.scissor_unreadable +|= 1;
        } else self.scissor_false +|= 1;
    }
};

test "font readiness is witnessed by valid returns, not historical frontier samples" {
    var evidence: Evidence = .{};
    try std.testing.expect(!evidence.font_last_valid);
    evidence.noteFontReturn(0x1000, 128, 64, true);
    try std.testing.expect(evidence.font_last_valid);
    evidence.noteLists(null); // ordinary text drawing cannot reopen the atlas wall
    try std.testing.expect(evidence.font_last_valid);
    evidence.noteFontReturn(0x1000, 128, 64, false);
    try std.testing.expect(!evidence.font_last_valid); // don't latch away a real regression
    evidence.noteFontReturn(0, 0, 0, true);
    try std.testing.expectEqual(@as(u64, 1), evidence.font_invalid_returns);
    try std.testing.expectEqual(@as(u64, 1), evidence.font_unreadable_returns);
    try std.testing.expectEqual(@as(?usize, null), Evidence.atlasByteCount(-1, 32));
}

test "failed scissor returns don't claim uninitialized output references" {
    var evidence: Evidence = .{};
    evidence.noteScissorReturn(false, null);
    try std.testing.expectEqual(@as(u64, 0), evidence.scissor_unreadable);
    evidence.noteScissorReturn(true, null);
    try std.testing.expectEqual(@as(u64, 1), evidence.scissor_unreadable);
    evidence.noteScissorReturn(true, .{ 10, 20, 30, 40 });
    try std.testing.expectEqual([4]u32{ 10, 20, 30, 40 }, evidence.scissor_rect);
}

test "public geometry snapshots distinguish normal drawing from empty or invalid clips" {
    var evidence: Evidence = .{};
    var lists = [_]u8{0} ** 64;
    lists[0] = 1;
    std.mem.writeInt(i32, lists[4..8], 1, .little);
    std.mem.writeInt(i32, lists[8..12], 6, .little);
    std.mem.writeInt(i32, lists[12..16], 4, .little);
    std.mem.writeInt(u32, lists[40..44], @bitCast(@as(f32, 1280)), .little);
    std.mem.writeInt(u32, lists[44..48], @bitCast(@as(f32, 720)), .little);
    std.mem.writeInt(u32, lists[48..52], @bitCast(@as(f32, 1)), .little);
    std.mem.writeInt(u32, lists[52..56], @bitCast(@as(f32, 1)), .little);
    evidence.noteLists(&lists);
    try std.testing.expectEqual(@as(u64, 0), evidence.lists_invalid);
    try std.testing.expectEqual(@as(i32, 4), evidence.vertex_count);
    try std.testing.expect(!evidence.raw_buffers_readable);
    std.mem.writeInt(i32, lists[8..12], 0, .little);
    evidence.noteLists(&lists);
    try std.testing.expectEqual(@as(u64, 1), evidence.lists_empty);

    var draw = [_]u8{0} ** 44;
    std.mem.writeInt(u32, draw[4..8], 6, .little);
    draw[24] = 1;
    std.mem.writeInt(u32, draw[36..40], @bitCast(@as(f32, 1280)), .little);
    std.mem.writeInt(u32, draw[40..44], @bitCast(@as(f32, 720)), .little);
    evidence.noteDraw(&draw);
    try std.testing.expectEqual(@as(u64, 0), evidence.draw_invalid_clip);
    std.mem.writeInt(u32, draw[36..40], @bitCast(std.math.nan(f32)), .little);
    evidence.noteDraw(&draw);
    try std.testing.expectEqual(@as(u64, 1), evidence.draw_invalid_clip);
}
