//! MoltenVK's attachment-less raster sample count belongs to the render pass,
//! not just the bound pipeline. Xenia uses one FSI pass for all MSAA modes.
//! MoltenVK 1.2.7 and 1.4.1 set that pass's defaultRasterSampleCount when a
//! pipeline is CREATED, so the last creation silently changes other draws'
//! SampleMask input. Missing samples corrupt EDRAM colour and depth together.
//!
//! Keep compatible empty passes private to each sample count, and restart the
//! host pass when a draw changes counts. No attachments are added; EDRAM stays
//! the same buffer and the original external dependencies are retained. This
//! correctness adaptation is independent of the optional watchdog guard.
const std = @import("std");
const abi = @import("../abi.zig");
const marshal = @import("../marshal.zig");

pub const sample_counts = [_]u32{ 1, 2, 4, 8, 16, 32, 64 };
pub const pass_capacity = 16;

pub fn sampleSlot(samples: u32) ?usize {
    for (sample_counts, 0..) |count, i| if (count == samples) return i;
    return null;
}

pub const Pass = struct {
    original: u64 = 0,
    flags: u32 = 0,
    subpass: marshal.SubpassDescription = .{},
    dependencies: [2]marshal.SubpassDependency = [_]marshal.SubpassDependency{.{}} ** 2,
    /// Slot zero is the guest's original pass, used only by 1x pipelines.
    variants: [sample_counts.len]u64 = [_]u64{0} ** sample_counts.len,

    /// The pointers are already marshalled native addresses. Copy all data
    /// needed later; never keep a pointer into the marshalling scratch.
    pub fn capture(original: u64, info: *const marshal.RenderPassCreateInfo) ?Pass {
        if (original == 0 or info.p_next != null or info.attachment_count != 0 or
            info.subpass_count != 1 or info.dependency_count != 2) return null;
        const subpass_pointer = info.subpasses orelse return null;
        var subpass: marshal.SubpassDescription = undefined;
        @memcpy(std.mem.asBytes(&subpass), @as([*]const u8, @ptrCast(subpass_pointer))[0..@sizeOf(marshal.SubpassDescription)]);
        if (subpass.flags != 0 or subpass.pipeline_bind_point != 0 or subpass.input_attachment_count != 0 or
            subpass.color_attachment_count != 0 or subpass.depth_stencil_attachment != null or
            subpass.preserve_attachment_count != 0) return null;
        const dependency_pointer = info.dependencies orelse return null;
        var dependencies: [2]marshal.SubpassDependency = undefined;
        @memcpy(std.mem.asBytes(&dependencies), @as([*]const u8, @ptrCast(dependency_pointer))[0..@sizeOf(@TypeOf(dependencies))]);
        // Exact Xenia FSI dependencies, including the storage-buffer access
        // scopes, rather than merely guessing from the number of subpasses.
        for (dependencies, 0..) |dep, i| {
            if (dep.src_subpass != (if (i == 0) @as(u32, 0xffff_ffff) else 0) or
                dep.dst_subpass != (if (i == 0) @as(u32, 0) else 0xffff_ffff) or
                dep.src_stage_mask != 0x80 or dep.dst_stage_mask != 0x80 or
                dep.src_access_mask != 0x60 or dep.dst_access_mask != 0x60 or
                dep.dependency_flags != 1) return null;
        }
        var pass = Pass{ .original = original, .flags = info.flags, .dependencies = dependencies };
        // All counts are zero. Canonicalise ignored pointers so none of the
        // native scratch addresses survive the create call.
        pass.subpass = .{};
        pass.variants[0] = original;
        return pass;
    }

    pub fn createInfo(self: *const Pass) marshal.RenderPassCreateInfo {
        return .{ .s_type = 38, .flags = self.flags, .subpass_count = 1, .subpasses = &self.subpass, .dependency_count = 2, .dependencies = &self.dependencies };
    }

    pub fn owns(self: *const Pass, handle: u64) bool {
        if (handle == 0 or self.original == 0) return false;
        for (self.variants) |variant| if (variant == handle) return true;
        return false;
    }
};

pub const Command = struct {
    pool: u64 = 0,
    primary: bool = false,
    has_inheritance: bool = false,
    original_pass: u64 = 0,
    active_pass: u64 = 0,
    bound_pass: u64 = 0,
    framebuffer: u64 = 0,
    area: abi.Rect2D = .{},
    inline_contents: bool = false,
    active_queries: u32 = 0,
    conditional: bool = false,
    failed: bool = false,

    pub fn reset(self: *Command, inheritance: bool) void {
        self.* = .{ .pool = self.pool, .primary = self.primary, .has_inheritance = inheritance };
    }

    pub fn beginPass(self: *Command, original: u64, begin: *const abi.RenderPassBeginInfo, contents: u32) void {
        self.original_pass = original;
        self.active_pass = begin.render_pass;
        self.framebuffer = begin.framebuffer;
        self.area = begin.render_area;
        self.inline_contents = contents == 0 and begin.clear_value_count == 0 and begin.p_next == null;
    }

    pub fn endPass(self: *Command) void {
        self.original_pass = 0;
        self.active_pass = 0;
        self.inline_contents = false;
    }

    pub fn needsRestart(self: *const Command) bool {
        return self.original_pass != 0 and self.bound_pass != 0 and self.active_pass != self.bound_pass;
    }

    pub fn canRestart(self: *const Command) bool {
        return self.primary and !self.has_inheritance and self.inline_contents and
            self.active_queries == 0 and !self.conditional and !self.failed;
    }
};

pub const Registry = struct {
    /// Set from native driver identity. Other Vulkan implementations preserve
    /// the guest's pass/pipeline semantics without this adaptation.
    moltenvk: bool = false,
    passes: [pass_capacity]Pass = [_]Pass{.{}} ** pass_capacity,
    commands: std.AutoHashMapUnmanaged(u64, Command) = .{},
    /// Correctness state must not live in the bounded diagnostic tracker:
    /// a long game may create more than its 512 remembered pipelines.
    pipelines: std.AutoHashMapUnmanaged(u64, u64) = .{},
    /// Tessellation plus FSI needs independent submission observation. This
    /// registry must survive diagnostic identity eviction, just like samples.
    isolated_pipelines: std.AutoHashMapUnmanaged(u64, void) = .{},
    allocation_failed: bool = false,
    variants_created: u64 = 0,
    restarts: u64 = 0,
    adapted_pipelines: u64 = 0,
    refusals: u64 = 0,

    pub fn findPass(self: *Registry, handle: u64) ?*Pass {
        for (&self.passes) |*pass| if (pass.owns(handle)) return pass;
        return null;
    }

    pub fn capturePass(self: *Registry, original: u64, info: *const marshal.RenderPassCreateInfo) bool {
        if (!self.moltenvk) return true;
        const pass = Pass.capture(original, info) orelse return true;
        for (&self.passes) |*slot| {
            if (slot.original == 0) {
                slot.* = pass;
                return true;
            }
        }
        self.refusals +|= 1;
        return false;
    }

    pub fn allocated(self: *Registry, guests: []const u64, pool: u64, primary: bool) void {
        if (!self.moltenvk) return;
        for (guests) |guest| {
            self.commands.put(std.heap.c_allocator, guest, .{ .pool = pool, .primary = primary }) catch {
                self.allocation_failed = true;
            };
        }
    }

    pub fn command(self: *Registry, guest: u64) ?*Command {
        return self.commands.getPtr(guest);
    }

    pub fn pipelineCreated(self: *Registry, native: u64, pass: u64) !void {
        if (native == 0 or pass == 0) return;
        try self.pipelines.put(std.heap.c_allocator, native, pass);
        self.adapted_pipelines +|= 1;
    }

    pub fn isolatePipeline(self: *Registry, native: u64) !void {
        try self.isolated_pipelines.put(std.heap.c_allocator, native, {});
    }

    pub fn bindPipeline(self: *Registry, guest: u64, native: u64) void {
        if (self.command(guest)) |cmd| cmd.bound_pass = self.pipelines.get(native) orelse 0;
    }

    /// Use correctness state, which survives diagnostic identity eviction.
    pub fn pipelineSampleCount(self: *const Registry, native: u64) ?u32 {
        const handle = self.pipelines.get(native) orelse return null;
        for (&self.passes) |*pass| {
            if (!pass.owns(handle)) continue;
            for (pass.variants, sample_counts) |variant, samples| {
                if (variant == handle) return samples;
            }
        }
        return null;
    }

    pub fn forgetPool(self: *Registry, pool: u64, destroyed: bool) void {
        // Remove one entry at a time because removing invalidates iterators.
        if (destroyed) {
            while (true) {
                var key: ?u64 = null;
                var iterator = self.commands.iterator();
                while (iterator.next()) |entry| {
                    if (entry.value_ptr.pool == pool) {
                        key = entry.key_ptr.*;
                        break;
                    }
                }
                _ = self.commands.remove(key orelse break);
            }
        } else {
            var iterator = self.commands.valueIterator();
            while (iterator.next()) |cmd| if (cmd.pool == pool) cmd.reset(false);
        }
    }

    pub fn deinit(self: *Registry) void {
        self.isolated_pipelines.deinit(std.heap.c_allocator);
        const moltenvk = self.moltenvk;
        self.commands.deinit(std.heap.c_allocator);
        self.pipelines.deinit(std.heap.c_allocator);
        self.* = .{ .moltenvk = moltenvk };
    }
};

test "FSI raster passes retain dependencies and own one stable sample count each" {
    const subpass = marshal.SubpassDescription{};
    const deps = [_]marshal.SubpassDependency{
        .{ .src_subpass = 0xffff_ffff, .src_stage_mask = 0x80, .dst_stage_mask = 0x80, .src_access_mask = 0x60, .dst_access_mask = 0x60, .dependency_flags = 1 },
        .{ .dst_subpass = 0xffff_ffff, .src_stage_mask = 0x80, .dst_stage_mask = 0x80, .src_access_mask = 0x60, .dst_access_mask = 0x60, .dependency_flags = 1 },
    };
    var info = marshal.RenderPassCreateInfo{ .s_type = 38, .subpass_count = 1, .subpasses = &subpass, .dependency_count = 2, .dependencies = &deps };
    var pass = Pass.capture(0x10, &info).?;
    try std.testing.expectEqualDeep(deps, pass.dependencies);
    pass.variants[sampleSlot(4).?] = 0x40;
    try std.testing.expect(pass.owns(0x10) and pass.owns(0x40));
    try std.testing.expect(!pass.owns(0));
    try std.testing.expectEqual(@as(u32, 0), pass.createInfo().attachment_count);
    info.attachment_count = 1;
    try std.testing.expect(Pass.capture(0x10, &info) == null);
    try std.testing.expect(sampleSlot(3) == null);
}

test "mixed FSI sampling restarts only when needed and retains the binding across pass ends" {
    var cmd = Command{ .pool = 2, .primary = true, .bound_pass = 0x40 };
    const begin = abi.RenderPassBeginInfo{ .render_pass = 0x10, .framebuffer = 9 };
    cmd.beginPass(0x10, &begin, 0);
    try std.testing.expect(cmd.needsRestart() and cmd.canRestart());
    cmd.active_pass = 0x40;
    try std.testing.expect(!cmd.needsRestart());
    cmd.bound_pass = 0x10;
    cmd.active_queries = 1;
    try std.testing.expect(cmd.needsRestart() and !cmd.canRestart());
    cmd.active_queries = 0;
    cmd.has_inheritance = true;
    try std.testing.expect(!cmd.canRestart());
    cmd.endPass();
    try std.testing.expect(!cmd.needsRestart());
    try std.testing.expectEqual(@as(u64, 0x10), cmd.bound_pass);
    cmd.reset(false);
    try std.testing.expectEqual(@as(u64, 0), cmd.bound_pass);
    try std.testing.expectEqual(@as(u64, 2), cmd.pool);
}

test "FSI raster recording follows command pool reset and destruction" {
    var registry = Registry{ .moltenvk = true };
    defer registry.deinit();
    registry.allocated(&.{ 1, 2 }, 9, true);
    registry.command(1).?.bound_pass = 0x40;
    registry.forgetPool(9, false);
    try std.testing.expectEqual(@as(u64, 0), registry.command(1).?.bound_pass);
    registry.forgetPool(9, true);
    try std.testing.expect(registry.command(1) == null and registry.command(2) == null);
}

test "FSI raster pipeline selection survives diagnostic capacity and clears ordinary binds" {
    var registry = Registry{ .moltenvk = true };
    defer registry.deinit();
    registry.allocated(&.{1}, 9, true);
    for (1..1025) |pipeline| try registry.pipelineCreated(pipeline, 0x40);
    registry.bindPipeline(1, 1024);
    try std.testing.expectEqual(@as(u64, 0x40), registry.command(1).?.bound_pass);
    registry.bindPipeline(1, 2048);
    try std.testing.expectEqual(@as(u64, 0), registry.command(1).?.bound_pass);
}
