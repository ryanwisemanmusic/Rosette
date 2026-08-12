//! The Vulkan ABI, only as far as presentation needs it.
//!
//! Rosette does not link against a Vulkan SDK: the host implementation is
//! resolved at runtime with `dlopen`, because whether MoltenVK is present is a
//! property of the machine and not of the build. That leaves the structure
//! layouts as Rosette's own responsibility — a mistyped field offset here is
//! not a compile error, it is a driver reading a swapchain extent out of a
//! usage mask and returning a plausible failure code.
//!
//! So every structure below is `extern` and laid out to match the C header
//! exactly, and the sizes are asserted at compile time against the values the
//! specification fixes. The assertions exist because the failure they catch is
//! otherwise indistinguishable from a driver bug.
//!
//! Deliberately partial. Only the entry points and structures on the path from
//! a `CAMetalLayer` to a presented swapchain image appear here; adding a type
//! because it exists in Vulkan would create the impression that Rosette
//! forwards more than it does.

const std = @import("std");

// Dispatchable handles are pointers to driver-owned dispatch tables.
pub const Instance = ?*anyopaque;
pub const PhysicalDevice = ?*anyopaque;
pub const Device = ?*anyopaque;
pub const Queue = ?*anyopaque;
pub const CommandBuffer = ?*anyopaque;

// Non-dispatchable handles are 64-bit on every platform Rosette targets.
pub const SurfaceKHR = u64;
pub const SwapchainKHR = u64;
pub const Image = u64;
pub const Semaphore = u64;
pub const Fence = u64;
pub const CommandPool = u64;
pub const Buffer = u64;
pub const DeviceMemory = u64;

pub const null_handle: u64 = 0;

pub const Result = i32;

pub const SUCCESS: Result = 0;
pub const NOT_READY: Result = 1;
pub const TIMEOUT: Result = 2;
pub const INCOMPLETE: Result = 5;
pub const ERROR_OUT_OF_HOST_MEMORY: Result = -1;
pub const ERROR_OUT_OF_DEVICE_MEMORY: Result = -2;
pub const ERROR_INITIALIZATION_FAILED: Result = -3;
pub const ERROR_DEVICE_LOST: Result = -4;
pub const ERROR_MEMORY_MAP_FAILED: Result = -5;
pub const ERROR_EXTENSION_NOT_PRESENT: Result = -7;
pub const ERROR_FEATURE_NOT_PRESENT: Result = -8;
pub const ERROR_INCOMPATIBLE_DRIVER: Result = -9;
pub const ERROR_SURFACE_LOST_KHR: Result = -1_000_000_000;
pub const ERROR_NATIVE_WINDOW_IN_USE_KHR: Result = -1_000_000_001;
pub const SUBOPTIMAL_KHR: Result = 1_000_001_003;
pub const ERROR_OUT_OF_DATE_KHR: Result = -1_000_001_004;

pub const STRUCTURE_TYPE_APPLICATION_INFO: u32 = 0;
pub const STRUCTURE_TYPE_INSTANCE_CREATE_INFO: u32 = 1;
pub const STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO: u32 = 2;
pub const STRUCTURE_TYPE_DEVICE_CREATE_INFO: u32 = 3;
pub const STRUCTURE_TYPE_SUBMIT_INFO: u32 = 4;
pub const STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO: u32 = 5;
pub const STRUCTURE_TYPE_MAPPED_MEMORY_RANGE: u32 = 6;
pub const STRUCTURE_TYPE_FENCE_CREATE_INFO: u32 = 8;
pub const STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO: u32 = 9;
pub const STRUCTURE_TYPE_BUFFER_CREATE_INFO: u32 = 12;
pub const STRUCTURE_TYPE_IMAGE_CREATE_INFO: u32 = 14;
pub const STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER: u32 = 45;
pub const STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO: u32 = 39;
pub const STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO: u32 = 40;
pub const STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO: u32 = 42;
pub const STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR: u32 = 1_000_001_000;
pub const STRUCTURE_TYPE_PRESENT_INFO_KHR: u32 = 1_000_001_001;
pub const STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT: u32 = 1_000_217_000;

pub const INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR: u32 = 1;

pub const QUEUE_GRAPHICS_BIT: u32 = 0x0000_0001;
pub const QUEUE_COMPUTE_BIT: u32 = 0x0000_0002;
pub const QUEUE_TRANSFER_BIT: u32 = 0x0000_0004;

pub const FORMAT_UNDEFINED: u32 = 0;
pub const FORMAT_R8G8B8A8_UNORM: u32 = 37;
pub const FORMAT_R8G8B8A8_SRGB: u32 = 43;
pub const FORMAT_B8G8R8A8_UNORM: u32 = 44;
pub const FORMAT_B8G8R8A8_SRGB: u32 = 50;
pub const FORMAT_A2B10G10R10_UNORM_PACK32: u32 = 64;

pub const COLOR_SPACE_SRGB_NONLINEAR_KHR: u32 = 0;

pub const PRESENT_MODE_IMMEDIATE_KHR: u32 = 0;
pub const PRESENT_MODE_MAILBOX_KHR: u32 = 1;
pub const PRESENT_MODE_FIFO_KHR: u32 = 2;
pub const PRESENT_MODE_FIFO_RELAXED_KHR: u32 = 3;

pub const IMAGE_USAGE_TRANSFER_SRC_BIT: u32 = 0x0000_0001;
pub const IMAGE_USAGE_TRANSFER_DST_BIT: u32 = 0x0000_0002;
pub const IMAGE_USAGE_SAMPLED_BIT: u32 = 0x0000_0004;
pub const IMAGE_USAGE_COLOR_ATTACHMENT_BIT: u32 = 0x0000_0010;

pub const IMAGE_TYPE_2D: u32 = 1;
pub const IMAGE_TILING_OPTIMAL: u32 = 0;
pub const IMAGE_TILING_LINEAR: u32 = 1;
pub const SAMPLE_COUNT_1_BIT: u32 = 1;
pub const IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL: u32 = 6;

pub const FILTER_NEAREST: u32 = 0;
pub const FILTER_LINEAR: u32 = 1;

pub const ACCESS_TRANSFER_READ_BIT: u32 = 0x0000_0800;

/// Blitting is not universally supported for every format and tiling, and a
/// blit the driver cannot do is a validation error rather than a soft failure.
pub const FORMAT_FEATURE_BLIT_SRC_BIT: u32 = 0x0000_0400;
pub const FORMAT_FEATURE_BLIT_DST_BIT: u32 = 0x0000_0800;
pub const FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT: u32 = 0x0000_1000;
pub const FORMAT_FEATURE_TRANSFER_DST_BIT: u32 = 0x0000_8000;

pub const BUFFER_USAGE_TRANSFER_SRC_BIT: u32 = 0x0000_0001;

pub const SHARING_MODE_EXCLUSIVE: u32 = 0;

pub const SURFACE_TRANSFORM_IDENTITY_BIT_KHR: u32 = 0x0000_0001;
pub const COMPOSITE_ALPHA_OPAQUE_BIT_KHR: u32 = 0x0000_0001;
pub const COMPOSITE_ALPHA_INHERIT_BIT_KHR: u32 = 0x0000_0008;

pub const IMAGE_LAYOUT_UNDEFINED: u32 = 0;
pub const IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL: u32 = 7;
pub const IMAGE_LAYOUT_PRESENT_SRC_KHR: u32 = 1_000_001_002;

pub const IMAGE_ASPECT_COLOR_BIT: u32 = 0x0000_0001;

pub const ACCESS_TRANSFER_WRITE_BIT: u32 = 0x0000_1000;
pub const ACCESS_MEMORY_READ_BIT: u32 = 0x0000_8000;

pub const PIPELINE_STAGE_TOP_OF_PIPE_BIT: u32 = 0x0000_0001;
pub const PIPELINE_STAGE_TRANSFER_BIT: u32 = 0x0000_1000;
pub const PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT: u32 = 0x0000_2000;
pub const PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT: u32 = 0x0000_0400;

pub const COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT: u32 = 0x0000_0002;
pub const COMMAND_BUFFER_LEVEL_PRIMARY: u32 = 0;
pub const COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT: u32 = 0x0000_0001;

pub const FENCE_CREATE_SIGNALED_BIT: u32 = 0x0000_0001;

pub const MEMORY_PROPERTY_DEVICE_LOCAL_BIT: u32 = 0x0000_0001;
pub const MEMORY_PROPERTY_HOST_VISIBLE_BIT: u32 = 0x0000_0002;
pub const MEMORY_PROPERTY_HOST_COHERENT_BIT: u32 = 0x0000_0004;

pub const QUEUE_FAMILY_IGNORED: u32 = 0xFFFF_FFFF;
pub const WHOLE_SIZE: u64 = 0xFFFF_FFFF_FFFF_FFFF;
/// `VkSurfaceCapabilitiesKHR.currentExtent` uses this in both dimensions to say
/// the surface has no fixed size and the application chooses.
pub const extent_undefined: u32 = 0xFFFF_FFFF;
/// `VkSurfaceCapabilitiesKHR.maxImageCount` uses zero to mean unbounded, which
/// is the opposite of what clamping code assumes if it is read literally.
pub const image_count_unbounded: u32 = 0;

pub const MAX_EXTENSION_NAME_SIZE: usize = 256;
pub const MAX_PHYSICAL_DEVICE_NAME_SIZE: usize = 256;
pub const MAX_MEMORY_TYPES: usize = 32;
pub const MAX_MEMORY_HEAPS: usize = 16;

pub fn makeApiVersion(major: u32, minor: u32, patch: u32) u32 {
    return (major << 22) | (minor << 12) | patch;
}

pub const Extent2D = extern struct {
    width: u32 = 0,
    height: u32 = 0,
};

pub const Extent3D = extern struct {
    width: u32 = 0,
    height: u32 = 0,
    depth: u32 = 0,
};

pub const Offset3D = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,
};

pub const ExtensionProperties = extern struct {
    extension_name: [MAX_EXTENSION_NAME_SIZE]u8,
    spec_version: u32,

    pub fn name(self: *const ExtensionProperties) []const u8 {
        return std.mem.sliceTo(&self.extension_name, 0);
    }
};

pub const ApplicationInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_APPLICATION_INFO,
    p_next: ?*const anyopaque = null,
    application_name: ?[*:0]const u8 = null,
    application_version: u32 = 0,
    engine_name: ?[*:0]const u8 = null,
    engine_version: u32 = 0,
    api_version: u32 = 0,
};

pub const InstanceCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    application_info: ?*const ApplicationInfo = null,
    enabled_layer_count: u32 = 0,
    enabled_layer_names: ?[*]const [*:0]const u8 = null,
    enabled_extension_count: u32 = 0,
    enabled_extension_names: ?[*]const [*:0]const u8 = null,
};

pub const MetalSurfaceCreateInfoEXT = extern struct {
    s_type: u32 = STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    layer: ?*const anyopaque = null,
};

/// The prefix of `VkPhysicalDeviceProperties` up to (but excluding) `limits`.
/// Callers pass a larger, over-aligned buffer to the driver and read this view
/// of it: `VkPhysicalDeviceLimits` contains `VkDeviceSize` members, so its
/// alignment inserts padding that is easy to get wrong and that Rosette does
/// not need to model to name an adapter.
pub const PhysicalDeviceIdentity = extern struct {
    api_version: u32,
    driver_version: u32,
    vendor_id: u32,
    device_id: u32,
    device_type: u32,
    device_name: [MAX_PHYSICAL_DEVICE_NAME_SIZE]u8,
    pipeline_cache_uuid: [16]u8,

    pub fn name(self: *const PhysicalDeviceIdentity) []const u8 {
        return std.mem.sliceTo(&self.device_name, 0);
    }
};

/// Room for the whole of `VkPhysicalDeviceProperties` (about 824 bytes) so the
/// driver never writes past the buffer Rosette hands it.
pub const physical_device_properties_bytes: usize = 1024;

pub const QueueFamilyProperties = extern struct {
    queue_flags: u32 = 0,
    queue_count: u32 = 0,
    timestamp_valid_bits: u32 = 0,
    min_image_transfer_granularity: Extent3D = .{},
};

pub const MemoryType = extern struct {
    property_flags: u32 = 0,
    heap_index: u32 = 0,
};

pub const MemoryHeap = extern struct {
    size: u64 = 0,
    flags: u32 = 0,
};

pub const PhysicalDeviceMemoryProperties = extern struct {
    memory_type_count: u32 = 0,
    memory_types: [MAX_MEMORY_TYPES]MemoryType = [_]MemoryType{.{}} ** MAX_MEMORY_TYPES,
    memory_heap_count: u32 = 0,
    memory_heaps: [MAX_MEMORY_HEAPS]MemoryHeap = [_]MemoryHeap{.{}} ** MAX_MEMORY_HEAPS,
};

pub const SurfaceCapabilitiesKHR = extern struct {
    min_image_count: u32 = 0,
    max_image_count: u32 = 0,
    current_extent: Extent2D = .{},
    min_image_extent: Extent2D = .{},
    max_image_extent: Extent2D = .{},
    max_image_array_layers: u32 = 0,
    supported_transforms: u32 = 0,
    current_transform: u32 = 0,
    supported_composite_alpha: u32 = 0,
    supported_usage_flags: u32 = 0,
};

pub const SurfaceFormatKHR = extern struct {
    format: u32 = FORMAT_UNDEFINED,
    color_space: u32 = COLOR_SPACE_SRGB_NONLINEAR_KHR,
};

pub const DeviceQueueCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    queue_family_index: u32 = 0,
    queue_count: u32 = 0,
    queue_priorities: ?[*]const f32 = null,
};

pub const DeviceCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    queue_create_info_count: u32 = 0,
    queue_create_infos: ?[*]const DeviceQueueCreateInfo = null,
    enabled_layer_count: u32 = 0,
    enabled_layer_names: ?[*]const [*:0]const u8 = null,
    enabled_extension_count: u32 = 0,
    enabled_extension_names: ?[*]const [*:0]const u8 = null,
    enabled_features: ?*const anyopaque = null,
};

pub const SwapchainCreateInfoKHR = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    surface: SurfaceKHR = null_handle,
    min_image_count: u32 = 0,
    image_format: u32 = FORMAT_UNDEFINED,
    image_color_space: u32 = COLOR_SPACE_SRGB_NONLINEAR_KHR,
    image_extent: Extent2D = .{},
    image_array_layers: u32 = 1,
    image_usage: u32 = 0,
    image_sharing_mode: u32 = SHARING_MODE_EXCLUSIVE,
    queue_family_index_count: u32 = 0,
    queue_family_indices: ?[*]const u32 = null,
    pre_transform: u32 = 0,
    composite_alpha: u32 = 0,
    present_mode: u32 = PRESENT_MODE_FIFO_KHR,
    clipped: u32 = 1,
    old_swapchain: SwapchainKHR = null_handle,
};

pub const CommandPoolCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    queue_family_index: u32 = 0,
};

pub const CommandBufferAllocateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    p_next: ?*const anyopaque = null,
    command_pool: CommandPool = null_handle,
    level: u32 = COMMAND_BUFFER_LEVEL_PRIMARY,
    command_buffer_count: u32 = 0,
};

pub const CommandBufferBeginInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    inheritance_info: ?*const anyopaque = null,
};

pub const SemaphoreCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
};

pub const FenceCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_FENCE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
};

pub const ImageSubresourceRange = extern struct {
    aspect_mask: u32 = IMAGE_ASPECT_COLOR_BIT,
    base_mip_level: u32 = 0,
    level_count: u32 = 1,
    base_array_layer: u32 = 0,
    layer_count: u32 = 1,
};

pub const ImageSubresourceLayers = extern struct {
    aspect_mask: u32 = IMAGE_ASPECT_COLOR_BIT,
    mip_level: u32 = 0,
    base_array_layer: u32 = 0,
    layer_count: u32 = 1,
};

pub const ImageMemoryBarrier = extern struct {
    s_type: u32 = STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    p_next: ?*const anyopaque = null,
    src_access_mask: u32 = 0,
    dst_access_mask: u32 = 0,
    old_layout: u32 = IMAGE_LAYOUT_UNDEFINED,
    new_layout: u32 = IMAGE_LAYOUT_UNDEFINED,
    src_queue_family_index: u32 = QUEUE_FAMILY_IGNORED,
    dst_queue_family_index: u32 = QUEUE_FAMILY_IGNORED,
    image: Image = null_handle,
    subresource_range: ImageSubresourceRange = .{},
};

pub const ClearColorValue = extern union {
    float32: [4]f32,
    int32: [4]i32,
    uint32: [4]u32,
};

pub const BufferCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    size: u64 = 0,
    usage: u32 = 0,
    sharing_mode: u32 = SHARING_MODE_EXCLUSIVE,
    queue_family_index_count: u32 = 0,
    queue_family_indices: ?[*]const u32 = null,
};

pub const ImageCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_IMAGE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    image_type: u32 = IMAGE_TYPE_2D,
    format: u32 = FORMAT_UNDEFINED,
    extent: Extent3D = .{ .width = 1, .height = 1, .depth = 1 },
    mip_levels: u32 = 1,
    array_layers: u32 = 1,
    samples: u32 = SAMPLE_COUNT_1_BIT,
    tiling: u32 = IMAGE_TILING_OPTIMAL,
    usage: u32 = 0,
    sharing_mode: u32 = SHARING_MODE_EXCLUSIVE,
    queue_family_index_count: u32 = 0,
    queue_family_indices: ?[*]const u32 = null,
    initial_layout: u32 = IMAGE_LAYOUT_UNDEFINED,
};

pub const ImageBlit = extern struct {
    src_subresource: ImageSubresourceLayers = .{},
    /// Two corners. Giving the source corners in descending order on an axis is
    /// how a blit mirrors on that axis, which is the whole vertical-flip
    /// mechanism.
    src_offsets: [2]Offset3D = [_]Offset3D{.{}} ** 2,
    dst_subresource: ImageSubresourceLayers = .{},
    dst_offsets: [2]Offset3D = [_]Offset3D{.{}} ** 2,
};

pub const FormatProperties = extern struct {
    linear_tiling_features: u32 = 0,
    optimal_tiling_features: u32 = 0,
    buffer_features: u32 = 0,
};

pub const MemoryRequirements = extern struct {
    size: u64 = 0,
    alignment: u64 = 0,
    memory_type_bits: u32 = 0,
};

pub const MemoryAllocateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    p_next: ?*const anyopaque = null,
    allocation_size: u64 = 0,
    memory_type_index: u32 = 0,
};

pub const MappedMemoryRange = extern struct {
    s_type: u32 = STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
    p_next: ?*const anyopaque = null,
    memory: DeviceMemory = null_handle,
    offset: u64 = 0,
    size: u64 = 0,
};

pub const BufferImageCopy = extern struct {
    buffer_offset: u64 = 0,
    buffer_row_length: u32 = 0,
    buffer_image_height: u32 = 0,
    image_subresource: ImageSubresourceLayers = .{},
    image_offset: Offset3D = .{},
    image_extent: Extent3D = .{},
};

pub const SubmitInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SUBMIT_INFO,
    p_next: ?*const anyopaque = null,
    wait_semaphore_count: u32 = 0,
    wait_semaphores: ?[*]const Semaphore = null,
    wait_dst_stage_mask: ?[*]const u32 = null,
    command_buffer_count: u32 = 0,
    command_buffers: ?[*]const CommandBuffer = null,
    signal_semaphore_count: u32 = 0,
    signal_semaphores: ?[*]const Semaphore = null,
};

pub const PresentInfoKHR = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PRESENT_INFO_KHR,
    p_next: ?*const anyopaque = null,
    wait_semaphore_count: u32 = 0,
    wait_semaphores: ?[*]const Semaphore = null,
    swapchain_count: u32 = 0,
    swapchains: ?[*]const SwapchainKHR = null,
    image_indices: ?[*]const u32 = null,
    results: ?[*]Result = null,
};

pub const PfnVoidFunction = *const anyopaque;

pub const PfnGetInstanceProcAddr = *const fn (Instance, [*:0]const u8) callconv(.c) ?PfnVoidFunction;
pub const PfnGetDeviceProcAddr = *const fn (Device, [*:0]const u8) callconv(.c) ?PfnVoidFunction;
pub const PfnEnumerateInstanceExtensionProperties = *const fn (?[*:0]const u8, *u32, ?[*]ExtensionProperties) callconv(.c) Result;
pub const PfnCreateInstance = *const fn (*const InstanceCreateInfo, ?*const anyopaque, *Instance) callconv(.c) Result;
pub const PfnDestroyInstance = *const fn (Instance, ?*const anyopaque) callconv(.c) void;
pub const PfnEnumeratePhysicalDevices = *const fn (Instance, *u32, ?[*]PhysicalDevice) callconv(.c) Result;
pub const PfnGetPhysicalDeviceProperties = *const fn (PhysicalDevice, *anyopaque) callconv(.c) void;
pub const PfnGetPhysicalDeviceQueueFamilyProperties = *const fn (PhysicalDevice, *u32, ?[*]QueueFamilyProperties) callconv(.c) void;
pub const PfnGetPhysicalDeviceMemoryProperties = *const fn (PhysicalDevice, *PhysicalDeviceMemoryProperties) callconv(.c) void;
pub const PfnEnumerateDeviceExtensionProperties = *const fn (PhysicalDevice, ?[*:0]const u8, *u32, ?[*]ExtensionProperties) callconv(.c) Result;
pub const PfnCreateMetalSurfaceEXT = *const fn (Instance, *const MetalSurfaceCreateInfoEXT, ?*const anyopaque, *SurfaceKHR) callconv(.c) Result;
pub const PfnDestroySurfaceKHR = *const fn (Instance, SurfaceKHR, ?*const anyopaque) callconv(.c) void;
pub const PfnGetPhysicalDeviceSurfaceSupportKHR = *const fn (PhysicalDevice, u32, SurfaceKHR, *u32) callconv(.c) Result;
pub const PfnGetPhysicalDeviceSurfaceCapabilitiesKHR = *const fn (PhysicalDevice, SurfaceKHR, *SurfaceCapabilitiesKHR) callconv(.c) Result;
pub const PfnGetPhysicalDeviceSurfaceFormatsKHR = *const fn (PhysicalDevice, SurfaceKHR, *u32, ?[*]SurfaceFormatKHR) callconv(.c) Result;
pub const PfnGetPhysicalDeviceSurfacePresentModesKHR = *const fn (PhysicalDevice, SurfaceKHR, *u32, ?[*]u32) callconv(.c) Result;
pub const PfnCreateDevice = *const fn (PhysicalDevice, *const DeviceCreateInfo, ?*const anyopaque, *Device) callconv(.c) Result;
pub const PfnDestroyDevice = *const fn (Device, ?*const anyopaque) callconv(.c) void;
pub const PfnDeviceWaitIdle = *const fn (Device) callconv(.c) Result;
pub const PfnGetDeviceQueue = *const fn (Device, u32, u32, *Queue) callconv(.c) void;
pub const PfnCreateSwapchainKHR = *const fn (Device, *const SwapchainCreateInfoKHR, ?*const anyopaque, *SwapchainKHR) callconv(.c) Result;
pub const PfnDestroySwapchainKHR = *const fn (Device, SwapchainKHR, ?*const anyopaque) callconv(.c) void;
pub const PfnGetSwapchainImagesKHR = *const fn (Device, SwapchainKHR, *u32, ?[*]Image) callconv(.c) Result;
pub const PfnAcquireNextImageKHR = *const fn (Device, SwapchainKHR, u64, Semaphore, Fence, *u32) callconv(.c) Result;
pub const PfnQueuePresentKHR = *const fn (Queue, *const PresentInfoKHR) callconv(.c) Result;
pub const PfnCreateCommandPool = *const fn (Device, *const CommandPoolCreateInfo, ?*const anyopaque, *CommandPool) callconv(.c) Result;
pub const PfnDestroyCommandPool = *const fn (Device, CommandPool, ?*const anyopaque) callconv(.c) void;
pub const PfnAllocateCommandBuffers = *const fn (Device, *const CommandBufferAllocateInfo, [*]CommandBuffer) callconv(.c) Result;
pub const PfnBeginCommandBuffer = *const fn (CommandBuffer, *const CommandBufferBeginInfo) callconv(.c) Result;
pub const PfnEndCommandBuffer = *const fn (CommandBuffer) callconv(.c) Result;
pub const PfnResetCommandBuffer = *const fn (CommandBuffer, u32) callconv(.c) Result;
pub const PfnCreateSemaphore = *const fn (Device, *const SemaphoreCreateInfo, ?*const anyopaque, *Semaphore) callconv(.c) Result;
pub const PfnDestroySemaphore = *const fn (Device, Semaphore, ?*const anyopaque) callconv(.c) void;
pub const PfnCreateFence = *const fn (Device, *const FenceCreateInfo, ?*const anyopaque, *Fence) callconv(.c) Result;
pub const PfnDestroyFence = *const fn (Device, Fence, ?*const anyopaque) callconv(.c) void;
pub const PfnWaitForFences = *const fn (Device, u32, [*]const Fence, u32, u64) callconv(.c) Result;
pub const PfnResetFences = *const fn (Device, u32, [*]const Fence) callconv(.c) Result;
pub const PfnQueueSubmit = *const fn (Queue, u32, ?[*]const SubmitInfo, Fence) callconv(.c) Result;
pub const PfnQueueWaitIdle = *const fn (Queue) callconv(.c) Result;
pub const PfnCmdPipelineBarrier = *const fn (CommandBuffer, u32, u32, u32, u32, ?*const anyopaque, u32, ?*const anyopaque, u32, ?[*]const ImageMemoryBarrier) callconv(.c) void;
pub const PfnCmdClearColorImage = *const fn (CommandBuffer, Image, u32, *const ClearColorValue, u32, [*]const ImageSubresourceRange) callconv(.c) void;
pub const PfnCmdCopyBufferToImage = *const fn (CommandBuffer, Buffer, Image, u32, u32, [*]const BufferImageCopy) callconv(.c) void;
pub const PfnGetPhysicalDeviceFormatProperties = *const fn (PhysicalDevice, u32, *FormatProperties) callconv(.c) void;
pub const PfnCmdBlitImage = *const fn (CommandBuffer, Image, u32, Image, u32, u32, [*]const ImageBlit, u32) callconv(.c) void;
pub const PfnCreateImage = *const fn (Device, *const ImageCreateInfo, ?*const anyopaque, *Image) callconv(.c) Result;
pub const PfnDestroyImage = *const fn (Device, Image, ?*const anyopaque) callconv(.c) void;
pub const PfnGetImageMemoryRequirements = *const fn (Device, Image, *MemoryRequirements) callconv(.c) void;
pub const PfnBindImageMemory = *const fn (Device, Image, DeviceMemory, u64) callconv(.c) Result;
pub const PfnCreateBuffer = *const fn (Device, *const BufferCreateInfo, ?*const anyopaque, *Buffer) callconv(.c) Result;
pub const PfnDestroyBuffer = *const fn (Device, Buffer, ?*const anyopaque) callconv(.c) void;
pub const PfnGetBufferMemoryRequirements = *const fn (Device, Buffer, *MemoryRequirements) callconv(.c) void;
pub const PfnAllocateMemory = *const fn (Device, *const MemoryAllocateInfo, ?*const anyopaque, *DeviceMemory) callconv(.c) Result;
pub const PfnFreeMemory = *const fn (Device, DeviceMemory, ?*const anyopaque) callconv(.c) void;
pub const PfnBindBufferMemory = *const fn (Device, Buffer, DeviceMemory, u64) callconv(.c) Result;
pub const PfnMapMemory = *const fn (Device, DeviceMemory, u64, u64, u32, *?*anyopaque) callconv(.c) Result;
pub const PfnUnmapMemory = *const fn (Device, DeviceMemory) callconv(.c) void;
pub const PfnFlushMappedMemoryRanges = *const fn (Device, u32, [*]const MappedMemoryRange) callconv(.c) Result;

// A wrong offset here is silent at runtime, so the sizes the specification
// fixes are checked at compile time instead.
comptime {
    std.debug.assert(@sizeOf(Extent2D) == 8);
    std.debug.assert(@sizeOf(Extent3D) == 12);
    std.debug.assert(@sizeOf(QueueFamilyProperties) == 24);
    std.debug.assert(@sizeOf(SurfaceCapabilitiesKHR) == 52);
    std.debug.assert(@sizeOf(SurfaceFormatKHR) == 8);
    std.debug.assert(@sizeOf(ExtensionProperties) == 260);
    std.debug.assert(@sizeOf(PhysicalDeviceIdentity) == 292);
    std.debug.assert(@sizeOf(PhysicalDeviceIdentity) <= physical_device_properties_bytes);
    std.debug.assert(@sizeOf(PhysicalDeviceMemoryProperties) == 520);
    std.debug.assert(@sizeOf(DeviceQueueCreateInfo) == 40);
    std.debug.assert(@sizeOf(DeviceCreateInfo) == 72);
    std.debug.assert(@sizeOf(SwapchainCreateInfoKHR) == 104);
    std.debug.assert(@sizeOf(SubmitInfo) == 72);
    std.debug.assert(@sizeOf(PresentInfoKHR) == 64);
    std.debug.assert(@sizeOf(CommandPoolCreateInfo) == 24);
    std.debug.assert(@sizeOf(CommandBufferAllocateInfo) == 32);
    std.debug.assert(@sizeOf(CommandBufferBeginInfo) == 32);
    std.debug.assert(@sizeOf(SemaphoreCreateInfo) == 24);
    std.debug.assert(@sizeOf(FenceCreateInfo) == 24);
    std.debug.assert(@sizeOf(ImageSubresourceRange) == 20);
    std.debug.assert(@sizeOf(ImageMemoryBarrier) == 72);
    std.debug.assert(@sizeOf(ClearColorValue) == 16);
    std.debug.assert(@sizeOf(BufferCreateInfo) == 56);
    std.debug.assert(@sizeOf(MemoryRequirements) == 24);
    std.debug.assert(@sizeOf(MemoryAllocateInfo) == 32);
    std.debug.assert(@sizeOf(MappedMemoryRange) == 40);
    std.debug.assert(@sizeOf(BufferImageCopy) == 56);
    std.debug.assert(@sizeOf(ImageCreateInfo) == 88);
    std.debug.assert(@sizeOf(ImageBlit) == 80);
    std.debug.assert(@sizeOf(FormatProperties) == 12);
    std.debug.assert(@sizeOf(ImageSubresourceLayers) == 16);
    std.debug.assert(@sizeOf(Offset3D) == 12);
    std.debug.assert(@sizeOf(MetalSurfaceCreateInfoEXT) == 32);
    std.debug.assert(@sizeOf(InstanceCreateInfo) == 64);
}

test "the specification's fixed sizes hold for every forwarded structure" {
    // The comptime block above is the real assertion; this makes its failure
    // appear as a named test rather than a build error with no context.
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(SwapchainCreateInfoKHR));
    try std.testing.expectEqual(@as(usize, 52), @sizeOf(SurfaceCapabilitiesKHR));
    try std.testing.expectEqual(@as(usize, 520), @sizeOf(PhysicalDeviceMemoryProperties));
}

test "device name is read from the identity prefix of a larger driver buffer" {
    var storage: [physical_device_properties_bytes]u8 align(8) = [_]u8{0} ** physical_device_properties_bytes;
    const identity: *PhysicalDeviceIdentity = @ptrCast(&storage);
    identity.api_version = makeApiVersion(1, 2, 0);
    const written = "Apple M-series (MoltenVK)";
    @memcpy(identity.device_name[0..written.len], written);
    try std.testing.expectEqualStrings(written, identity.name());
    try std.testing.expectEqual(makeApiVersion(1, 2, 0), identity.api_version);
}

test "sentinel values that read backwards are named rather than inlined" {
    // maxImageCount == 0 means unbounded, not "no images allowed", and a
    // currentExtent of all-ones means the surface has no fixed size.
    try std.testing.expectEqual(@as(u32, 0), image_count_unbounded);
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), extent_undefined);
}
