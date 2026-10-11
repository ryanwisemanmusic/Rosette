//! Narrow, version-pinned native MSL texture pipelines in the Vulkan stream.
//! The original hardened pipeline remains available for every declined call.
//! No separate Metal queue, CPU pixel copies, or additional GPU submissions.
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("../vulkan/abi.zig");
const marshal = @import("../vulkan/marshal.zig");
const source = @import("rosette_live_metal_source").source;
const allocator = std.heap.c_allocator;
const compute = 0x20;
const capacity = 4096;

pub const Format = enum(u8) {
    ctx1 = 0,
    dxt1 = 1,
    dxt3 = 3,
    dxt5 = 5,
    pub fn entry(self: Format) [*:0]const u8 {
        return switch (self) {
            .ctx1 => "rosette_live_ctx1",
            .dxt1 => "rosette_live_dxt1",
            .dxt3 => "rosette_live_dxt3",
            .dxt5 => "rosette_live_dxt5",
        };
    }
};

// Exact shipped loader bytes from the user's clean Xenia Windows bundle's
// headers, also verified present in its PE image by the standalone gate.
// A changed compiler or loader simply stays on the hardened SPIR-V route.
pub fn identify(bytes: []const u8) ?Format {
    if (bytes.len < 20 or bytes.len % 4 != 0) return null;
    const entries = .{
        .{ Format.ctx1, 19236, "62d6655844c00aa27c41bb525e762bc875ab41e6040268f80a9b22831d0e34d1" },
        .{ Format.dxt1, 15864, "bcdfce86372ebccd56fb9c1fd7e969ababa5298f0561d90101ffd91c9b4e0366" },
        .{ Format.dxt3, 14348, "141670e9f738bb7cf528fdc8dbc577c5fe94c65f9f2d6bfcc0bf13cf7d2321d3" },
        .{ Format.dxt5, 35460, "e078a76d45fd8bcced7de3e69ac9cac3ded81058f1783ec58cb09633b64805f9" },
    };
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    inline for (entries) |entry| {
        const expected = comptime blk: {
            var digest: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&digest, entry[2]) catch unreachable;
            break :blk digest;
        };
        if (bytes.len == entry[1] and std.mem.eql(u8, &hash, &expected)) return entry[0];
    }
    return null;
}

pub const SetWorkgroup = *const fn (u64, u32, u32, u32) callconv(.c) void;
extern "c" fn _dyld_image_count() u32;
extern "c" fn _dyld_get_image_name(u32) ?[*:0]const u8;

/// Resolve controls ONLY from an already loaded, unambiguous MoltenVK image.
/// The API is deprecated, absent from getProcAddr, and not portable Vulkan.
/// Do not load a second driver or assume another version has this binding ABI.
pub fn resolveControl(instance: abi.Instance, driver_id: u32, driver_version: u32, uniform_alignment: u64) ?SetWorkgroup {
    if (builtin.os.tag != .macos or driver_id != 14 or driver_version != 10207 or
        uniform_alignment == 0 or uniform_alignment > 4096 or 4096 % uniform_alignment != 0) return null;
    if (std.c.getenv("ROSETTE_NATIVE_METAL_TEXTURES")) |value| {
        if (std.mem.eql(u8, std.mem.sliceTo(value, 0), "0")) return null;
    }
    var selected: ?[*:0]const u8 = null;
    for (0.._dyld_image_count()) |index| {
        const path = _dyld_get_image_name(@intCast(index)) orelse continue;
        const basename = std.fs.path.basename(std.mem.sliceTo(path, 0));
        if (!std.mem.eql(u8, basename, "libMoltenVK.dylib") and !std.mem.eql(u8, basename, "MoltenVK")) continue;
        if (selected != null) return null;
        selected = path;
    }
    // Darwin RTLD_NOLOAD: this acquires the existing image, never a new driver.
    const library = std.c.dlopen(selected orelse return null, @bitCast(@as(u32, 0x10 | 0x1))) orelse return null;
    defer _ = std.c.dlclose(library);
    const getter_address = std.c.dlsym(library, "vkGetMoltenVKConfigurationMVK") orelse return null;
    const getter: *const fn (?*anyopaque, ?*anyopaque, *usize) callconv(.c) i32 = @ptrCast(@alignCast(getter_address));
    var configuration: [160]u8 align(8) = @splat(0);
    var size: usize = configuration.len;
    if (getter(instance, &configuration, &size) != abi.SUCCESS or size != 160 or
        std.mem.readInt(u32, configuration[144..148], .little) != 0) return null;
    return @ptrCast(@alignCast(std.c.dlsym(library, "vkSetWorkgroupSizeMVK") orelse return null));
}

pub fn boundedRange(size: u64, offset: u64, range: u64) u32 {
    if (offset >= size) return 0;
    return @intCast(@min(@min(size - offset, range), std.math.maxInt(u32)));
}

pub const Push = extern struct {
    flags: u32,
    guest_offset: u32,
    guest_pitch: u32,
    guest_z_rows: u32,
    blocks_x: u32,
    blocks_y: u32,
    blocks_z: u32,
    host_offset: u32,
    host_pitch: u32,
    height: u32,

    pub fn admitted(self: Push, format: Format, groups: [3]u32) bool {
        return self.reason(format, groups) == null;
    }

    pub fn reason(self: Push, format: Format, groups: [3]u32) ?Decline {
        const bpp: u64 = if (format == .ctx1) 2 else 4;
        // Xenia always packs scale X/Y, including 1x (bits 4 and 7).
        // Legacy zero-scale synthetic fixtures use the same unscaled kernel.
        const scale = self.flags & ~@as(u32, 15);
        if ((scale != 0 and scale != 0x90) or self.flags & 2 != 0 or self.blocks_z != 1) return .scaled_or_3d;
        if (self.blocks_x == 0 or self.blocks_x > 1024 or self.blocks_y == 0 or self.blocks_y > 1024 or
            self.height == 0 or self.height > self.blocks_y * 4) return .extent;
        if (self.guest_pitch < self.blocks_x or self.host_pitch < @as(u64, self.blocks_x) * 4 * bpp) return .pitch;
        if (self.guest_offset & 15 != 0 or self.host_offset & 15 != 0 or self.host_pitch & 15 != 0 or self.guest_pitch & 31 != 0) return .alignment;
        if (groups[0] != (self.blocks_x + 15) / 16 or groups[1] != (self.blocks_y + 31) / 32 or groups[2] != 1) return .groups;
        return null;
    }
};

pub const Decline = enum { terminal, command, pipeline, layout, constants, descriptors, scaled_or_3d, extent, pitch, alignment, groups };

test "native Metal live texture refusal reasons preserve admission" {
    const good = Push{ .flags = 1, .guest_offset = 32, .guest_pitch = 32, .guest_z_rows = 32, .blocks_x = 5, .blocks_y = 3, .blocks_z = 1, .host_offset = 16, .host_pitch = 128, .height = 11 };
    try std.testing.expectEqual(@as(?Decline, null), good.reason(.ctx1, .{ 1, 1, 1 }));
    var changed = good;
    changed.flags = 2;
    try std.testing.expectEqual(Decline.scaled_or_3d, changed.reason(.ctx1, .{ 1, 1, 1 }).?);
    changed.flags = good.flags | 0x90;
    try std.testing.expect(changed.admitted(.ctx1, .{ 1, 1, 1 }));
    changed.flags = good.flags | 0xa0;
    try std.testing.expectEqual(Decline.scaled_or_3d, changed.reason(.ctx1, .{ 1, 1, 1 }).?);
    changed = good;
    changed.host_pitch = 16;
    try std.testing.expectEqual(Decline.pitch, changed.reason(.ctx1, .{ 1, 1, 1 }).?);
    changed = good;
    changed.guest_offset = 4;
    try std.testing.expectEqual(Decline.alignment, changed.reason(.ctx1, .{ 1, 1, 1 }).?);
    try std.testing.expectEqual(Decline.groups, good.reason(.ctx1, .{ 2, 1, 1 }).?);
}

pub const Command = struct {
    pipeline: u64 = 0,
    layout: u64 = 0,
    sets: [2]u64 = .{ 0, 0 },
    push_layout: u64 = 0,
    push_mask: u64 = 0,
    push: [40]u8 = @splat(0),

    pub fn bind(self: *Command, layout: u64, first: u32, sets: []const u64, dynamic: usize) void {
        if (self.layout != layout or dynamic != 0) self.sets = .{ 0, 0 };
        self.layout = layout;
        if (dynamic != 0) return;
        for (sets, 0..) |set, index| {
            const slot = @as(u64, first) + index;
            if (slot < 2) self.sets[@intCast(slot)] = set;
        }
    }
    pub fn constants(self: *Command, layout: u64, offset: u32, bytes: []const u8) void {
        if (layout != self.push_layout) self.push_mask = 0;
        self.push_layout = layout;
        for (bytes, 0..) |byte, index| {
            const slot = @as(u64, offset) + index;
            if (slot >= 40) continue;
            self.push[@intCast(slot)] = byte;
            self.push_mask |= @as(u64, 1) << @intCast(slot);
        }
    }
};

const Layout = struct { sets: [2]u64, native: u64 = 0 };
const Pipeline = struct { native: u64, layout: u64, native_layout: u64, format: Format };
const Bound = struct { buffer: u64 = 0, bytes: u32 = 0, meta: u64 = 0, slot: ?u16 = null };

pub const State = struct {
    control: SetWorkgroup,
    bounds_stride: u32 = 16,
    module: u64 = 0,
    module_failed: bool = false,
    terminal_result: abi.Result = abi.SUCCESS,
    owned_layouts: std.ArrayList(u64) = .empty,
    bounds_layout: u64 = 0,
    bounds_pool: u64 = 0,
    bounds_buffer: u64 = 0,
    bounds_memory: u64 = 0,
    mapped: ?[*]u8 = null,
    slots: [capacity]bool = @splat(false),
    set_layouts: std.AutoHashMapUnmanaged(u64, bool) = .{},
    layouts: std.AutoHashMapUnmanaged(u64, Layout) = .{},
    shaders: std.AutoHashMapUnmanaged(u64, Format) = .{},
    pipelines: std.AutoHashMapUnmanaged(u64, Pipeline) = .{},
    buffers: std.AutoHashMapUnmanaged(u64, u64) = .{},
    bounds: std.AutoHashMapUnmanaged(u64, Bound) = .{},
    commands: std.AutoHashMapUnmanaged(u64, Command) = .{},
    dispatches: [4]u64 = @splat(0),
    declines: u64 = 0,
    decline_reasons: [std.meta.fields(Decline).len]u64 = @splat(0),
    pipeline_failures: u64 = 0,
    metadata_failures: u64 = 0,

    pub fn noteSetLayout(self: *State, real: u64, info: *const marshal.DescriptorSetLayoutCreateInfo) void {
        var eligible = info.p_next == null and info.flags == 0 and info.binding_count == 1 and info.bindings != null;
        if (eligible) {
            const b: *const marshal.DescriptorSetLayoutBinding = @ptrCast(@alignCast(info.bindings.?));
            eligible = b.binding == 0 and b.descriptor_type == 7 and b.descriptor_count == 1 and
                b.stage_flags & compute != 0 and b.immutable_samplers == null;
        }
        self.set_layouts.put(allocator, real, eligible) catch {};
    }
    pub fn noteLayout(self: *State, real: u64, info: *const marshal.PipelineLayoutCreateInfo) void {
        if (info.p_next != null or info.flags != 0 or info.set_layout_count != 2 or info.set_layouts == null or
            info.push_constant_range_count != 1 or info.push_constant_ranges == null) return;
        const range: *const marshal.PushConstantRange = @ptrCast(@alignCast(info.push_constant_ranges.?));
        if (range.stage_flags != compute or range.offset != 0 or range.size != 40) return;
        const sets: *const [2]u64 = @ptrCast(@alignCast(info.set_layouts.?));
        if (!(self.set_layouts.get(sets[0]) orelse false) or !(self.set_layouts.get(sets[1]) orelse false)) return;
        self.layouts.put(allocator, real, .{ .sets = sets.* }) catch {};
    }
    pub fn command(self: *State, guest: u64) ?*Command {
        const result = self.commands.getOrPut(allocator, guest) catch return null;
        if (!result.found_existing) result.value_ptr.* = .{};
        return result.value_ptr;
    }
    pub fn resetCommand(self: *State, guest: u64) void {
        _ = self.commands.remove(guest);
    }
    pub fn noteBuffer(self: *State, handle: u64, size: u64) void {
        self.buffers.put(allocator, handle, size) catch {};
    }
    pub fn noteShader(self: *State, handle: u64, format: Format) void {
        self.shaders.put(allocator, handle, format) catch {};
    }

    /// Explicit descriptor range is authoritative, never the whole allocation.
    /// These cells also follow legal descriptor updates AFTER command recording.
    pub fn noteWrite(self: *State, write: abi.WriteDescriptorSet) void {
        if (write.dst_binding != 0 or write.dst_array_element != 0) return;
        const record = self.bounds.getOrPut(allocator, write.dst_set) catch return;
        if (!record.found_existing) record.value_ptr.* = .{};
        const b = record.value_ptr;
        b.buffer = 0;
        b.bytes = 0;
        if (write.descriptor_type == 7 and write.descriptor_count == 1 and write.buffer_info != null) {
            const info = write.buffer_info.?[0];
            b.buffer = info.buffer;
            b.bytes = boundedRange(self.buffers.get(info.buffer) orelse 0, info.offset, info.range);
        }
        self.publish(b.*);
    }
    pub fn noteCopy(self: *State, copy: abi.CopyDescriptorSet) void {
        if (copy.dst_binding != 0 or copy.dst_array_element != 0) return;
        const original = if (copy.src_binding == 0 and copy.src_array_element == 0 and copy.descriptor_count == 1)
            self.bounds.get(copy.src_set) orelse Bound{}
        else
            Bound{};
        const record = self.bounds.getOrPut(allocator, copy.dst_set) catch return;
        if (!record.found_existing) record.value_ptr.* = .{};
        record.value_ptr.buffer = original.buffer;
        record.value_ptr.bytes = original.bytes;
        self.publish(record.value_ptr.*);
    }
    fn publish(self: *State, bound: Bound) void {
        const slot = bound.slot orelse return;
        const mapped = self.mapped orelse return;
        std.mem.writeInt(u32, mapped[@as(usize, slot) * self.bounds_stride ..][0..4], bound.bytes, .little);
    }

    fn accepted(self: *State, result: abi.Result) bool {
        if (result == abi.ERROR_DEVICE_LOST) self.terminal_result = result;
        return result == abi.SUCCESS;
    }

    fn ensureResources(self: *State, host: anytype) bool {
        if (self.mapped != null) return true;
        const f = host.fn_ptrs;
        const device = host.device orelse return false;
        const create_layout = f.create_descriptor_set_layout orelse return false;
        const create_pool = f.create_descriptor_pool orelse return false;
        const create_buffer = f.create_buffer orelse return false;
        const requirements = f.get_buffer_memory_requirements orelse return false;
        const allocate = f.allocate_memory orelse return false;
        const bind = f.bind_buffer_memory orelse return false;
        const map = f.map_memory orelse return false;
        if (f.destroy_descriptor_pool == null or f.destroy_descriptor_set_layout == null or f.destroy_buffer == null or
            f.free_memory == null or f.unmap_memory == null or f.free_descriptor_sets == null or
            f.allocate_descriptor_sets == null or f.update_descriptor_sets == null) return false;
        // No non-coherent publication shortcut. If coherent memory is absent,
        // the original pipeline remains active for this device.
        const binding = marshal.DescriptorSetLayoutBinding{ .descriptor_type = 6, .descriptor_count = 1, .stage_flags = compute };
        const layout_info = marshal.DescriptorSetLayoutCreateInfo{ .s_type = 32, .binding_count = 1, .bindings = &binding };
        if (!self.accepted(create_layout(device, &layout_info, null, &self.bounds_layout))) {
            self.bounds_layout = 0;
            return false;
        }
        if (self.bounds_layout == 0) return false;
        const size = marshal.DescriptorPoolSize{ .descriptor_type = 6, .descriptor_count = capacity };
        const pool_info = marshal.DescriptorPoolCreateInfo{ .s_type = 33, .flags = 1, .max_sets = capacity, .pool_size_count = 1, .pool_sizes = &size };
        if (!self.accepted(create_pool(device, &pool_info, null, &self.bounds_pool))) {
            self.bounds_pool = 0;
            return false;
        }
        if (self.bounds_pool == 0) return false;
        const buffer_info = abi.BufferCreateInfo{ .size = capacity * self.bounds_stride, .usage = abi.BUFFER_USAGE_UNIFORM_BUFFER_BIT };
        if (!self.accepted(create_buffer(device, &buffer_info, null, &self.bounds_buffer))) {
            self.bounds_buffer = 0;
            return false;
        }
        if (self.bounds_buffer == 0) return false;
        var req: abi.MemoryRequirements = .{};
        requirements(device, self.bounds_buffer, &req);
        if (req.size < buffer_info.size) return false;
        var memory_type: ?u32 = null;
        for (host.physical_device_memory.memory_types[0..@min(host.physical_device_memory.memory_type_count, abi.MAX_MEMORY_TYPES)], 0..) |typ, index| {
            if (req.memory_type_bits & (@as(u32, 1) << @intCast(index)) != 0 and
                typ.property_flags & 6 == 6)
            {
                memory_type = @intCast(index);
                break;
            }
        }
        const allocation = abi.MemoryAllocateInfo{ .allocation_size = req.size, .memory_type_index = memory_type orelse return false };
        if (!self.accepted(allocate(device, &allocation, null, &self.bounds_memory))) {
            self.bounds_memory = 0;
            return false;
        }
        if (self.bounds_memory == 0 or !self.accepted(bind(device, self.bounds_buffer, self.bounds_memory, 0))) return false;
        var pointer: ?*anyopaque = null;
        if (!self.accepted(map(device, self.bounds_memory, 0, abi.WHOLE_SIZE, 0, &pointer)) or pointer == null) return false;
        self.mapped = @ptrCast(pointer.?);
        @memset(self.mapped.?[0 .. capacity * self.bounds_stride], 0);
        return true;
    }

    pub fn addPipeline(self: *State, host: anytype, original: u64, info: abi.ComputePipelineCreateInfo) void {
        const format = self.shaders.get(info.stage.module) orelse return;
        if (info.p_next != null or info.stage.p_next != null or info.flags != 0 or info.stage.flags != 0 or
            info.stage.specialization_info != null or info.base_pipeline_handle != 0 or info.stage.name == null or
            !std.mem.eql(u8, std.mem.sliceTo(info.stage.name.?, 0), "main")) return;
        const layout = self.layouts.getPtr(info.layout) orelse return;
        const f = host.fn_ptrs;
        const device = host.device orelse return;
        const create_module = f.create_shader_module orelse return;
        const create_layout = f.create_pipeline_layout orelse return;
        const create_pipeline = f.create_compute_pipelines orelse return;
        if (f.destroy_shader_module == null or f.destroy_pipeline_layout == null or f.destroy_pipeline == null) return;
        if (self.module_failed or self.terminal_result != abi.SUCCESS) return;
        if (!self.ensureResources(host)) {
            self.module_failed = true;
            self.pipeline_failures +|= 1;
            return;
        }
        if (self.module == 0) {
            const blob = allocator.alignedAlloc(u8, .@"4", source.len + 5) catch return;
            defer allocator.free(blob);
            std.mem.writeInt(u32, blob[0..4], 0x19960412, .little);
            @memcpy(blob[4..][0..source.len], source);
            blob[blob.len - 1] = 0;
            const module_info = marshal.ShaderModuleCreateInfo{ .s_type = 16, .code_size = blob.len, .code = blob.ptr };
            if (!self.accepted(create_module(device, &module_info, null, &self.module)) or self.module == 0) {
                self.module = 0;
                self.module_failed = true;
                self.pipeline_failures +|= 1;
                return;
            }
            self.control(self.module, 4, 32, 1);
        }
        if (layout.native == 0) {
            const sets = [4]u64{ layout.sets[0], layout.sets[1], self.bounds_layout, self.bounds_layout };
            const push = marshal.PushConstantRange{ .stage_flags = compute, .size = 40 };
            const layout_info = marshal.PipelineLayoutCreateInfo{ .s_type = 30, .set_layout_count = 4, .set_layouts = &sets, .push_constant_range_count = 1, .push_constant_ranges = &push };
            if (!self.accepted(create_layout(device, &layout_info, null, &layout.native)) or layout.native == 0) {
                layout.native = 0;
                self.pipeline_failures +|= 1;
                return;
            }
        }
        // Keep ownership independent of a destroyed/reused guest layout handle.
        if (std.mem.indexOfScalar(u64, self.owned_layouts.items, layout.native) == null) {
            self.owned_layouts.append(allocator, layout.native) catch {
                f.destroy_pipeline_layout.?(device, layout.native, null);
                layout.native = 0;
                return;
            };
        }
        var native = info;
        native.layout = layout.native;
        native.stage.module = self.module;
        native.stage.name = format.entry();
        var pipeline: u64 = 0;
        if (!self.accepted(create_pipeline(device, 0, 1, @ptrCast(&native), null, @ptrCast(&pipeline))) or pipeline == 0) {
            if (pipeline != 0 and self.terminal_result == abi.SUCCESS) f.destroy_pipeline.?(device, pipeline, null);
            self.pipeline_failures +|= 1;
            return;
        }
        self.pipelines.put(allocator, original, .{ .native = pipeline, .layout = info.layout, .native_layout = layout.native, .format = format }) catch {
            f.destroy_pipeline.?(device, pipeline, null);
        };
    }

    fn meta(self: *State, host: anytype, real_set: u64) ?u64 {
        const bound = self.bounds.getPtr(real_set) orelse return null;
        if (bound.bytes == 0) return null;
        if (bound.meta != 0) return bound.meta;
        const slot = std.mem.indexOfScalar(bool, &self.slots, false) orelse return null;
        const info = abi.DescriptorSetAllocateInfo{ .descriptor_pool = self.bounds_pool, .descriptor_set_count = 1, .descriptor_set_layouts = @ptrCast(&self.bounds_layout) };
        var new_set: u64 = 0;
        if (!self.accepted(host.fn_ptrs.allocate_descriptor_sets.?(host.device, &info, @ptrCast(&new_set))) or new_set == 0) return null;
        bound.meta = new_set;
        self.slots[slot] = true;
        bound.slot = @intCast(slot);
        self.publish(bound.*);
        const buffer = abi.DescriptorBufferInfo{ .buffer = self.bounds_buffer, .offset = slot * self.bounds_stride, .range = 16 };
        const write = abi.WriteDescriptorSet{ .dst_set = bound.meta, .descriptor_count = 1, .descriptor_type = 6, .buffer_info = @ptrCast(&buffer) };
        host.fn_ptrs.update_descriptor_sets.?(host.device, 1, @ptrCast(&write), 0, null);
        return bound.meta;
    }

    pub fn canDispatch(self: *const State, guest: u64, groups: [3]u32) bool {
        return self.dispatchReason(guest, groups) == null;
    }

    pub fn dispatchReason(self: *const State, guest: u64, groups: [3]u32) ?Decline {
        if (self.terminal_result != abi.SUCCESS) return .terminal;
        const c = self.commands.get(guest) orelse return .command;
        const p = self.pipelines.get(c.pipeline) orelse return .pipeline;
        if (c.layout != p.layout or c.push_layout != p.layout) return .layout;
        if (c.push_mask != (1 << 40) - 1) return .constants;
        if (c.sets[0] == 0 or c.sets[1] == 0) return .descriptors;
        var push: Push = undefined;
        @memcpy(std.mem.asBytes(&push), &c.push);
        return push.reason(p.format, groups);
    }

    pub fn noteDecline(self: *State, reason: Decline) void {
        self.declines +|= 1;
        self.decline_reasons[@intFromEnum(reason)] +|= 1;
    }

    /// Choose only complete, compatible direct dispatches. Restore the guest
    /// pipeline immediately after encoding so later indirect/base dispatches,
    /// watchdog replay and unrelated compute work keep their original state.
    pub fn dispatch(self: *State, host: anytype, guest: u64, target: abi.CommandBuffer, groups: [3]u32) bool {
        if (self.terminal_result != abi.SUCCESS) return false;
        const command_state = self.commands.get(guest) orelse return false;
        const pipeline = self.pipelines.get(command_state.pipeline) orelse return false;
        self.declines +|= 1;
        if (!self.canDispatch(guest, groups)) return false;
        const f = host.fn_ptrs;
        const bind_pipeline = f.cmd_bind_pipeline orelse return false;
        const bind_sets = f.cmd_bind_descriptor_sets orelse return false;
        const dispatch_fn = f.cmd_dispatch orelse return false;
        const destination = self.meta(host, command_state.sets[0]) orelse {
            self.metadata_failures +|= 1;
            return false;
        };
        const source_set = self.meta(host, command_state.sets[1]) orelse {
            self.metadata_failures +|= 1;
            return false;
        };
        const sets = [2]u64{ destination, source_set };
        bind_pipeline(target, 1, pipeline.native);
        bind_sets(target, 1, pipeline.native_layout, 2, 2, &sets, 0, null);
        dispatch_fn(target, groups[0], groups[1], groups[2]);
        bind_pipeline(target, 1, command_state.pipeline);
        const index: usize = switch (pipeline.format) {
            .ctx1 => 0,
            .dxt1 => 1,
            .dxt3 => 2,
            .dxt5 => 3,
        };
        self.dispatches[index] +|= 1;
        self.declines -|= 1;
        return true;
    }

    pub fn forgetSet(self: *State, host: anytype, set: u64) void {
        const record = self.bounds.fetchRemove(set) orelse return;
        if (record.value.meta != 0 and self.terminal_result == abi.SUCCESS) {
            var meta_set = record.value.meta;
            // Original descriptor-set lifetime governs this private cell too.
            // On free failure quarantine it; never reuse a possibly live cell.
            if (host.fn_ptrs.free_descriptor_sets) |free| {
                if (self.accepted(free(host.device, self.bounds_pool, 1, @ptrCast(&meta_set))))
                    self.slots[record.value.slot.?] = false;
            }
        }
    }
    pub fn forgetPipeline(self: *State, host: anytype, original: u64) void {
        if (self.pipelines.fetchRemove(original)) |record| {
            if (self.terminal_result == abi.SUCCESS) if (host.fn_ptrs.destroy_pipeline) |destroy| destroy(host.device, record.value.native, null);
        }
    }
    pub fn forgetLayout(self: *State, host: anytype, original: u64) void {
        // Vulkan permits destroying a layout after pipeline creation. Keep its
        // private counterpart until device teardown; recorded binds still use it.
        _ = host;
        _ = self.layouts.remove(original);
    }
    pub fn forgetBuffer(self: *State, original: u64) void {
        _ = self.buffers.remove(original);
        var iterator = self.bounds.valueIterator();
        while (iterator.next()) |bound| if (bound.buffer == original) {
            bound.bytes = 0;
            self.publish(bound.*);
        };
    }
    pub fn deinit(self: *State, host: anytype) void {
        // Caller has already stopped/drained GPU work. No post-fault submissions.
        const f = host.fn_ptrs;
        var pipelines = self.pipelines.valueIterator();
        while (pipelines.next()) |p| if (f.destroy_pipeline) |destroy| destroy(host.device, p.native, null);
        for (self.owned_layouts.items) |layout| if (f.destroy_pipeline_layout) |destroy| destroy(host.device, layout, null);
        if (self.module != 0) {
            if (f.destroy_shader_module) |destroy| destroy(host.device, self.module, null);
        }
        if (self.bounds_pool != 0) {
            if (f.destroy_descriptor_pool) |destroy| destroy(host.device, self.bounds_pool, null);
        }
        if (self.bounds_layout != 0) {
            if (f.destroy_descriptor_set_layout) |destroy| destroy(host.device, self.bounds_layout, null);
        }
        if (self.mapped != null) {
            if (f.unmap_memory) |unmap| unmap(host.device, self.bounds_memory);
        }
        if (self.bounds_buffer != 0) {
            if (f.destroy_buffer) |destroy| destroy(host.device, self.bounds_buffer, null);
        }
        if (self.bounds_memory != 0) {
            if (f.free_memory) |free| free(host.device, self.bounds_memory, null);
        }
        self.releaseCpu();
    }
    pub fn releaseCpu(self: *State) void {
        self.owned_layouts.deinit(allocator);
        self.set_layouts.deinit(allocator);
        self.layouts.deinit(allocator);
        self.shaders.deinit(allocator);
        self.pipelines.deinit(allocator);
        self.buffers.deinit(allocator);
        self.bounds.deinit(allocator);
        self.commands.deinit(allocator);
    }
};

test "native Metal live texture range is the bound descriptor range" {
    try std.testing.expectEqual(@as(u32, 16), boundedRange(1024, 512, 16));
    try std.testing.expectEqual(@as(u32, 512), boundedRange(1024, 512, abi.WHOLE_SIZE));
    try std.testing.expectEqual(@as(u32, 0), boundedRange(1024, std.math.maxInt(u64), 16));
}
test "native Metal live texture partial constants and descriptor compatibility" {
    var c = Command{};
    c.bind(5, 0, &.{ 6, 7 }, 0);
    c.constants(5, 0, &(@as([40]u8, @splat(0))));
    try std.testing.expectEqual(@as(u64, (1 << 40) - 1), c.push_mask);
    c.constants(9, 4, &.{ 1, 2, 3, 4 });
    try std.testing.expectEqual(@as(u64, 0xf0), c.push_mask);
    c.bind(9, 1, &.{8}, 0);
    try std.testing.expectEqual(@as(u64, 0), c.sets[0]);
    c.bind(9, 0, &.{6}, 1);
    try std.testing.expectEqual(@as(u64, 0), c.sets[1]);
}
test "native Metal live texture dispatch admits only the measured unscaled 2D contract" {
    var p = Push{ .flags = 1, .guest_offset = 32, .guest_pitch = 32, .guest_z_rows = 32, .blocks_x = 5, .blocks_y = 3, .blocks_z = 1, .host_offset = 16, .host_pitch = 80, .height = 11 };
    try std.testing.expect(p.admitted(.dxt5, .{ 1, 1, 1 }));
    p.flags = 3;
    try std.testing.expect(!p.admitted(.dxt5, .{ 1, 1, 1 }));
    p.flags = 1;
    try std.testing.expect(!p.admitted(.dxt5, .{ 2, 1, 1 }));
    p.host_pitch = 79;
    try std.testing.expect(!p.admitted(.dxt5, .{ 1, 1, 1 }));
}
