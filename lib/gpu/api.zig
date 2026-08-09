const std = @import("std");

/// Stable, backend-neutral Rosette GPU handshake ABI.
///
/// The ABI deliberately describes capabilities and Rosette-owned concepts. A
/// backend name is a negotiated result, never something a consumer must know in
/// order to request a device, resource, queue, or presentation path.
pub const abi_magic: u32 = 0x5247_5055; // "RGPU"
pub const api_version: u32 = 1;
pub const no_capability: u32 = std.math.maxInt(u32);

pub const BackendKind = enum(u32) {
    none = 0,
    vulkan = 1,
    metal = 2,
    mesa = 3,
    other = 0xFFFF_FFFF,
};

pub const ConsumerKind = enum(u32) {
    generic = 0,
    xenia = 1,
};

pub const Status = enum(u32) {
    success = 0,
    degraded = 1,
    invalid_request = 2,
    incompatible_version = 3,
    missing_capability = 4,
    resource_exhausted = 5,
};

pub const Capability = enum(u8) {
    backend_instance,
    physical_adapter,
    logical_device,
    queue_graphics,
    queue_compute,
    queue_transfer,
    queue_sparse,
    surface,
    presentation,
    swapchain,
    memory_host_visible,
    memory_host_coherent,
    memory_device_local,
    memory_import,
    guest_memory_mapping,
    sparse_buffer,
    sparse_image,
    buffer,
    image_1d,
    image_2d,
    image_3d,
    image_cube,
    sampler,
    render_target,
    depth_stencil_target,
    format_rgba8_unorm,
    format_bgra8_unorm,
    format_rgba16_float,
    format_r32_uint,
    format_d24_unorm_s8,
    format_d32_float,
    shader_vertex,
    shader_fragment,
    shader_compute,
    shader_spirv,
    shader_msl,
    command_buffer,
    secondary_command_buffer,
    resource_barrier,
    buffer_image_copy,
    fence,
    semaphore_binary,
    semaphore_timeline,
    timeline_host_wait,
    timeline_host_signal,
    timestamp_query,
    occlusion_query,
    descriptor_binding,
    push_constants,
    pipeline_cache,
    dynamic_rendering,
    backend_escape,
};

pub const capability_count: usize = @typeInfo(Capability).@"enum".fields.len;

pub const CapabilitySet = extern struct {
    low: u64 = 0,
    high: u64 = 0,

    pub fn from(items: []const Capability) CapabilitySet {
        var result = CapabilitySet{};
        for (items) |item| result.insert(item);
        return result;
    }

    pub fn insert(self: *CapabilitySet, capability: Capability) void {
        const index: u8 = @intFromEnum(capability);
        if (index < 64) {
            self.low |= @as(u64, 1) << @as(u6, @intCast(index));
        } else {
            self.high |= @as(u64, 1) << @as(u6, @intCast(index - 64));
        }
    }

    pub fn remove(self: *CapabilitySet, capability: Capability) void {
        const index: u8 = @intFromEnum(capability);
        if (index < 64) {
            self.low &= ~(@as(u64, 1) << @as(u6, @intCast(index)));
        } else {
            self.high &= ~(@as(u64, 1) << @as(u6, @intCast(index - 64)));
        }
    }

    pub fn contains(self: CapabilitySet, capability: Capability) bool {
        const index: u8 = @intFromEnum(capability);
        return if (index < 64)
            (self.low & (@as(u64, 1) << @as(u6, @intCast(index)))) != 0
        else
            (self.high & (@as(u64, 1) << @as(u6, @intCast(index - 64)))) != 0;
    }

    pub fn unionWith(self: CapabilitySet, other: CapabilitySet) CapabilitySet {
        return .{ .low = self.low | other.low, .high = self.high | other.high };
    }

    pub fn intersect(self: CapabilitySet, other: CapabilitySet) CapabilitySet {
        return .{ .low = self.low & other.low, .high = self.high & other.high };
    }

    pub fn difference(self: CapabilitySet, other: CapabilitySet) CapabilitySet {
        return .{ .low = self.low & ~other.low, .high = self.high & ~other.high };
    }

    pub fn isEmpty(self: CapabilitySet) bool {
        return self.low == 0 and self.high == 0;
    }

    pub fn first(self: CapabilitySet) ?Capability {
        for (0..capability_count) |index| {
            const capability: Capability = @enumFromInt(index);
            if (self.contains(capability)) return capability;
        }
        return null;
    }
};

pub const QueueMask = struct {
    pub const graphics: u32 = 1 << 0;
    pub const compute: u32 = 1 << 1;
    pub const transfer: u32 = 1 << 2;
    pub const sparse: u32 = 1 << 3;
};

pub const HandshakeRequest = extern struct {
    magic: u32 = abi_magic,
    struct_size: u32 = @sizeOf(HandshakeRequest),
    minimum_version: u32 = api_version,
    maximum_version: u32 = api_version,
    consumer: u32 = @intFromEnum(ConsumerKind.generic),
    flags: u32 = 0,
    required: CapabilitySet = .{},
    desired: CapabilitySet = .{},
    required_queue_mask: u32 = 0,
    desired_queue_mask: u32 = 0,
    minimum_buffer_alignment: u64 = 1,
    minimum_image_alignment: u64 = 1,
    minimum_guest_mapping_alignment: u64 = 1,
    reserved: [5]u64 = [_]u64{0} ** 5,

    /// Non-disruptive discovery request used while the existing Vulkan
    /// forwarding path is still synthetic. It reports the truthful boundary
    /// without making guest startup depend on capabilities Rosette does not yet
    /// own.
    pub fn xeniaObservation() HandshakeRequest {
        return .{
            .consumer = @intFromEnum(ConsumerKind.xenia),
            .desired = CapabilitySet.from(&.{
                .backend_instance,
                .physical_adapter,
                .logical_device,
                .queue_graphics,
                .surface,
                .presentation,
                .memory_host_visible,
                .memory_device_local,
                .guest_memory_mapping,
                .buffer,
                .image_2d,
                .sampler,
                .render_target,
                .shader_vertex,
                .shader_fragment,
                .command_buffer,
                .resource_barrier,
                .fence,
                .semaphore_binary,
            }),
            .desired_queue_mask = QueueMask.graphics | QueueMask.transfer,
            .minimum_buffer_alignment = 256,
            .minimum_image_alignment = 256,
            .minimum_guest_mapping_alignment = 4096,
        };
    }

    /// The first real Xenia host-execution profile. This must fail until
    /// Rosette owns a native adapter, logical device, queue, resources, command
    /// buffers and synchronization. It never requests Xenos or PM4 semantics.
    pub fn xeniaHostExecution() HandshakeRequest {
        var result = xeniaObservation();
        result.required = CapabilitySet.from(&.{
            .physical_adapter,
            .logical_device,
            .queue_graphics,
            .memory_host_visible,
            .memory_device_local,
            .guest_memory_mapping,
            .buffer,
            .image_2d,
            .sampler,
            .render_target,
            .shader_vertex,
            .shader_fragment,
            .command_buffer,
            .resource_barrier,
            .fence,
            .semaphore_binary,
        });
        result.required_queue_mask = QueueMask.graphics;
        return result;
    }
};

pub const HandshakeResponse = extern struct {
    magic: u32 = abi_magic,
    struct_size: u32 = @sizeOf(HandshakeResponse),
    version: u32 = 0,
    status: u32 = @intFromEnum(Status.invalid_request),
    backend: u32 = @intFromEnum(BackendKind.none),
    first_missing_capability: u32 = no_capability,
    negotiated: CapabilitySet = .{},
    missing_required: CapabilitySet = .{},
    missing_desired: CapabilitySet = .{},
    session: u64 = 0,
    adapter: u64 = 0,
    device: u64 = 0,
    graphics_queue: u64 = 0,
    compute_queue: u64 = 0,
    transfer_queue: u64 = 0,
    sparse_queue: u64 = 0,
    buffer_alignment: u64 = 1,
    image_alignment: u64 = 1,
    guest_mapping_alignment: u64 = 1,
    limits: DeviceLimits = .{},
    surface: SurfaceCapabilities = .{},
    reason_length: u32 = 0,
    reserved: u32 = 0,
    reason: [192]u8 = [_]u8{0} ** 192,

    pub fn statusValue(self: HandshakeResponse) Status {
        return @enumFromInt(self.status);
    }

    pub fn backendValue(self: HandshakeResponse) BackendKind {
        return @enumFromInt(self.backend);
    }

    pub fn reasonSlice(self: *const HandshakeResponse) []const u8 {
        return self.reason[0..@min(self.reason_length, self.reason.len)];
    }

    pub fn setReason(self: *HandshakeResponse, message: []const u8) void {
        @memset(&self.reason, 0);
        const length = @min(message.len, self.reason.len);
        @memcpy(self.reason[0..length], message[0..length]);
        self.reason_length = @intCast(length);
    }
};

pub const DeviceLimits = extern struct {
    graphics_queue_count: u32 = 0,
    compute_queue_count: u32 = 0,
    transfer_queue_count: u32 = 0,
    sparse_queue_count: u32 = 0,
    host_visible_heap_bytes: u64 = 0,
    device_local_heap_bytes: u64 = 0,
    maximum_buffer_bytes: u64 = 0,
    maximum_image_dimension_2d: u32 = 0,
    maximum_image_array_layers: u32 = 0,
    maximum_push_constant_bytes: u32 = 0,
    timestamp_period_picoseconds: u32 = 0,
    sparse_buffer_block_bytes: u64 = 0,
    sparse_image_block_bytes: u64 = 0,
    maximum_timeline_value_difference: u64 = 0,
};

pub const SurfaceCapabilities = extern struct {
    minimum_image_count: u32 = 0,
    maximum_image_count: u32 = 0,
    minimum_width: u32 = 0,
    minimum_height: u32 = 0,
    maximum_width: u32 = 0,
    maximum_height: u32 = 0,
    present_mode_mask: u32 = 0,
    reserved: u32 = 0,
    supported_usage: u64 = 0,
    supported_formats: CapabilitySet = .{},
};

pub const QueueClass = enum(u32) {
    graphics = 0,
    compute = 1,
    transfer = 2,
    sparse = 3,
};

pub const MemoryClass = enum(u32) {
    host_visible = 0,
    device_local = 1,
    imported_guest = 2,
};

pub const Format = enum(u32) {
    undefined = 0,
    rgba8_unorm = 1,
    bgra8_unorm = 2,
    rgba16_float = 3,
    r32_uint = 4,
    d24_unorm_s8 = 5,
    d32_float = 6,
};

pub const BufferUsage = struct {
    pub const transfer_source: u64 = 1 << 0;
    pub const transfer_destination: u64 = 1 << 1;
    pub const vertex: u64 = 1 << 2;
    pub const index: u64 = 1 << 3;
    pub const uniform: u64 = 1 << 4;
    pub const storage: u64 = 1 << 5;
    pub const indirect: u64 = 1 << 6;
};

pub const ImageUsage = struct {
    pub const transfer_source: u64 = 1 << 0;
    pub const transfer_destination: u64 = 1 << 1;
    pub const sampled: u64 = 1 << 2;
    pub const storage: u64 = 1 << 3;
    pub const color_target: u64 = 1 << 4;
    pub const depth_stencil_target: u64 = 1 << 5;
    pub const presentation: u64 = 1 << 6;
};

pub const BufferDesc = extern struct {
    size: u64,
    usage: u64,
    memory_class: u32,
    flags: u32 = 0,
    alignment: u64 = 1,
};

pub const ImageDesc = extern struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
    mip_levels: u32 = 1,
    array_layers: u32 = 1,
    format: u32,
    usage: u64,
    flags: u64 = 0,
    alignment: u64 = 1,
};

pub const GuestMemoryMappingDesc = extern struct {
    guest_physical_address: u64,
    length: u64,
    resource: u64,
    resource_offset: u64 = 0,
    flags: u64 = 0,
};

pub const SamplerDesc = extern struct {
    minimum_filter: u32 = 0,
    maximum_filter: u32 = 0,
    mip_filter: u32 = 0,
    address_u: u32 = 0,
    address_v: u32 = 0,
    address_w: u32 = 0,
    maximum_anisotropy: f32 = 1,
    minimum_lod: f32 = 0,
    maximum_lod: f32 = 1000,
    lod_bias: f32 = 0,
};

pub const SyncKind = enum(u32) {
    fence = 0,
    binary_semaphore = 1,
    timeline_semaphore = 2,
};

pub const SyncDesc = extern struct {
    kind: u32,
    flags: u32 = 0,
    initial_value: u64 = 0,
};

pub const SurfaceSource = enum(u32) {
    application_window = 0,
    headless = 1,
    external_rosette_surface = 2,
};

pub const SurfaceDesc = extern struct {
    source: u32 = @intFromEnum(SurfaceSource.application_window),
    flags: u32 = 0,
    source_id: u64 = 0,
    preferred_width: u32 = 0,
    preferred_height: u32 = 0,
};

pub const SwapchainDesc = extern struct {
    surface: u64,
    width: u32,
    height: u32,
    format: u32,
    image_count: u32,
    usage: u64,
    flags: u64 = 0,
};

/// Namespaced opt-in for features a generic Rosette concept cannot express.
/// Support is advertised by `backend_escape`; use is never required for core
/// device/resource/command/presentation operation.
pub const EscapeRequest = extern struct {
    namespace: [16]u8,
    operation: u32,
    version: u32,
    input_address: u64,
    input_length: u64,
    output_address: u64,
    output_length: u64,
};

pub fn capabilityName(capability: Capability) []const u8 {
    return @tagName(capability);
}

test "capability set crosses the 64-bit word boundary" {
    var set = CapabilitySet{};
    set.insert(.backend_instance);
    set.insert(.backend_escape);
    try std.testing.expect(set.contains(.backend_instance));
    try std.testing.expect(set.contains(.backend_escape));
    set.remove(.backend_instance);
    try std.testing.expect(!set.contains(.backend_instance));
    try std.testing.expectEqual(Capability.backend_escape, set.first().?);
}

test "Xenia execution profile is stricter than observation" {
    const observation = HandshakeRequest.xeniaObservation();
    const execution = HandshakeRequest.xeniaHostExecution();
    try std.testing.expect(observation.required.isEmpty());
    try std.testing.expect(execution.required.contains(.logical_device));
    try std.testing.expect(execution.required.contains(.guest_memory_mapping));
    try std.testing.expect(!execution.required.contains(.backend_escape));
}
