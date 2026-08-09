const api = @import("api.zig");

pub const Error = error{
    Unsupported,
    OutOfMemory,
    DeviceLost,
    InvalidResource,
    SubmissionFailed,
    PresentationFailed,
};

/// Backend-owned facts exposed to the generic runtime. `provided` is the
/// authoritative capability set; the named fields preserve enough topology
/// and alignment information for a consumer to make a useful decision without
/// learning Vulkan, Metal, or Mesa types.
pub const Description = struct {
    kind: api.BackendKind = .none,
    provided: api.CapabilitySet = .{},
    adapter_name: [96]u8 = [_]u8{0} ** 96,
    adapter_name_length: u8 = 0,
    graphics_queue_count: u8 = 0,
    compute_queue_count: u8 = 0,
    transfer_queue_count: u8 = 0,
    sparse_queue_count: u8 = 0,
    buffer_alignment: u64 = 1,
    image_alignment: u64 = 1,
    guest_mapping_alignment: u64 = 1,
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
    surface: api.SurfaceCapabilities = .{},

    pub fn setAdapterName(self: *Description, name: []const u8) void {
        @memset(&self.adapter_name, 0);
        const length = @min(name.len, self.adapter_name.len);
        @memcpy(self.adapter_name[0..length], name[0..length]);
        self.adapter_name_length = @intCast(length);
    }

    pub fn adapterName(self: *const Description) []const u8 {
        return self.adapter_name[0..self.adapter_name_length];
    }
};

pub const Operations = struct {
    shutdown: ?*const fn (?*anyopaque) void = null,
    create_buffer: ?*const fn (?*anyopaque, *const api.BufferDesc, *u64) Error!void = null,
    create_image: ?*const fn (?*anyopaque, *const api.ImageDesc, *u64) Error!void = null,
    create_sampler: ?*const fn (?*anyopaque, *const api.SamplerDesc, *u64) Error!void = null,
    create_sync: ?*const fn (?*anyopaque, *const api.SyncDesc, *u64) Error!void = null,
    create_surface: ?*const fn (?*anyopaque, *const api.SurfaceDesc, *u64) Error!void = null,
    create_swapchain: ?*const fn (?*anyopaque, *const api.SwapchainDesc, *u64) Error!void = null,
    destroy_resource: ?*const fn (?*anyopaque, u64) void = null,
    create_command_buffer: ?*const fn (?*anyopaque, api.QueueClass, *u64) Error!void = null,
    submit: ?*const fn (?*anyopaque, u64, u64, u64, u64) Error!void = null,
    wait_fence: ?*const fn (?*anyopaque, u64, u64) Error!void = null,
    present: ?*const fn (?*anyopaque, u64, u32, u64) Error!void = null,
    escape: ?*const fn (?*anyopaque, *const api.EscapeRequest) Error!void = null,
};

/// Adapter interface implemented once per host API. Backend objects returned
/// by these callbacks remain private tokens stored behind Rosette handles.
pub const Adapter = struct {
    context: ?*anyopaque = null,
    description: Description = .{},
    operations: Operations = .{},
    adapter_token: u64 = 0,
    device_token: u64 = 0,
    queue_tokens: [4]u64 = [_]u64{0} ** 4,

    pub fn none() Adapter {
        return .{};
    }
};

/// Truthful description of the Vulkan adapter as it is progressively brought
/// online. This is intentionally stage-based: a native instance and surface do
/// not imply a physical device, queue, native resources, submission, or pixels.
pub const VulkanBoundary = struct {
    instance_native: bool = false,
    surface_native: bool = false,
    physical_adapter_native: bool = false,
    logical_device_native: bool = false,
    graphics_queue_native: bool = false,
    compute_queue_native: bool = false,
    transfer_queue_native: bool = false,
    host_visible_memory_native: bool = false,
    device_local_memory_native: bool = false,
    guest_mapping_native: bool = false,
    buffer_native: bool = false,
    image_native: bool = false,
    sampler_native: bool = false,
    shader_native: bool = false,
    command_buffer_native: bool = false,
    barriers_native: bool = false,
    synchronization_native: bool = false,
    swapchain_native: bool = false,
    presentation_native: bool = false,
    adapter_name: []const u8 = "Vulkan backend (discovery pending)",
    buffer_alignment: u64 = 1,
    image_alignment: u64 = 1,
    guest_mapping_alignment: u64 = 1,
    adapter_token: u64 = 0,
    device_token: u64 = 0,
    graphics_queue_token: u64 = 0,
    compute_queue_token: u64 = 0,
    transfer_queue_token: u64 = 0,

    pub fn describe(self: VulkanBoundary) Description {
        var result = Description{
            .kind = .vulkan,
            .buffer_alignment = self.buffer_alignment,
            .image_alignment = self.image_alignment,
            .guest_mapping_alignment = self.guest_mapping_alignment,
            .graphics_queue_count = @intFromBool(self.graphics_queue_native),
            .compute_queue_count = @intFromBool(self.compute_queue_native),
            .transfer_queue_count = @intFromBool(self.transfer_queue_native),
        };
        result.setAdapterName(self.adapter_name);
        if (self.instance_native) result.provided.insert(.backend_instance);
        if (self.surface_native) result.provided.insert(.surface);
        if (self.physical_adapter_native) result.provided.insert(.physical_adapter);
        if (self.logical_device_native) result.provided.insert(.logical_device);
        if (self.graphics_queue_native) result.provided.insert(.queue_graphics);
        if (self.compute_queue_native) result.provided.insert(.queue_compute);
        if (self.transfer_queue_native) result.provided.insert(.queue_transfer);
        if (self.host_visible_memory_native) {
            result.provided.insert(.memory_host_visible);
            result.provided.insert(.memory_host_coherent);
        }
        if (self.device_local_memory_native) result.provided.insert(.memory_device_local);
        if (self.guest_mapping_native) result.provided.insert(.guest_memory_mapping);
        if (self.buffer_native) result.provided.insert(.buffer);
        if (self.image_native) {
            result.provided.insert(.image_2d);
            result.provided.insert(.render_target);
            result.provided.insert(.depth_stencil_target);
            result.provided.insert(.format_rgba8_unorm);
            result.provided.insert(.format_bgra8_unorm);
            result.provided.insert(.format_d24_unorm_s8);
        }
        if (self.sampler_native) result.provided.insert(.sampler);
        if (self.shader_native) {
            result.provided.insert(.shader_vertex);
            result.provided.insert(.shader_fragment);
            result.provided.insert(.shader_compute);
            result.provided.insert(.shader_spirv);
        }
        if (self.command_buffer_native) result.provided.insert(.command_buffer);
        if (self.barriers_native) {
            result.provided.insert(.resource_barrier);
            result.provided.insert(.buffer_image_copy);
        }
        if (self.synchronization_native) {
            result.provided.insert(.fence);
            result.provided.insert(.semaphore_binary);
        }
        if (self.swapchain_native) result.provided.insert(.swapchain);
        if (self.presentation_native) result.provided.insert(.presentation);
        return result;
    }

    pub fn adapter(self: VulkanBoundary, operations: Operations, context: ?*anyopaque) Adapter {
        return .{
            .context = context,
            .description = self.describe(),
            .operations = operations,
            .adapter_token = self.adapter_token,
            .device_token = self.device_token,
            .queue_tokens = .{
                self.graphics_queue_token,
                self.compute_queue_token,
                self.transfer_queue_token,
                0,
            },
        };
    }
};

test "Vulkan instance and surface do not imply a device or presentation" {
    const description = (VulkanBoundary{
        .instance_native = true,
        .surface_native = true,
    }).describe();
    try @import("std").testing.expect(description.provided.contains(.backend_instance));
    try @import("std").testing.expect(description.provided.contains(.surface));
    try @import("std").testing.expect(!description.provided.contains(.physical_adapter));
    try @import("std").testing.expect(!description.provided.contains(.logical_device));
    try @import("std").testing.expect(!description.provided.contains(.presentation));
}
