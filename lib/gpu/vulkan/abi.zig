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
pub const Event = u64;
pub const QueryPool = u64;
pub const CommandPool = u64;
pub const Buffer = u64;
pub const DeviceMemory = u64;
pub const DescriptorSet = u64;
pub const ImageView = u64;

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
pub const ERROR_FORMAT_NOT_SUPPORTED: Result = -11;
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
pub const STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO: u32 = 1_000_127_001;
pub const STRUCTURE_TYPE_MAPPED_MEMORY_RANGE: u32 = 6;
pub const STRUCTURE_TYPE_FENCE_CREATE_INFO: u32 = 8;
pub const STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO: u32 = 9;
pub const STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO: u32 = 17;
pub const STRUCTURE_TYPE_BUFFER_CREATE_INFO: u32 = 12;
pub const STRUCTURE_TYPE_IMAGE_CREATE_INFO: u32 = 14;
pub const STRUCTURE_TYPE_IMAGE_FORMAT_LIST_CREATE_INFO: u32 = 1_000_147_000;
pub const STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER: u32 = 45;
pub const STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO: u32 = 39;
pub const STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO: u32 = 40;
pub const STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO: u32 = 42;
pub const STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO: u32 = 41;
pub const STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO: u32 = 34;
pub const STRUCTURE_TYPE_DESCRIPTOR_UPDATE_TEMPLATE_CREATE_INFO: u32 = 1_000_085_000;
pub const STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR: u32 = 1_000_001_000;
pub const STRUCTURE_TYPE_PRESENT_INFO_KHR: u32 = 1_000_001_001;
pub const STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT: u32 = 1_000_217_000;
pub const STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2: u32 = 1000146003;
pub const STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2: u32 = 1000146000;
pub const STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2: u32 = 1000146001;
pub const STRUCTURE_TYPE_DEPENDENCY_INFO: u32 = 1000314003;
pub const STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO: u32 = 1000314004;
pub const STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO: u32 = 1000314005;
pub const STRUCTURE_TYPE_SUBMIT_INFO_2: u32 = 1000314006;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES: u32 = 1_000_207_000;
pub const STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO: u32 = 1_000_207_002;
pub const STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO: u32 = 1_000_207_004;
pub const STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO: u32 = 1_000_207_005;
pub const STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO: u32 = 11;
pub const STRUCTURE_TYPE_SUBPASS_BEGIN_INFO: u32 = 1_000_109_004;
pub const STRUCTURE_TYPE_SUBPASS_END_INFO: u32 = 1_000_109_005;
pub const STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO: u32 = 1_000_044_000;
pub const STRUCTURE_TYPE_RENDERING_INFO: u32 = 1_000_044_001;
pub const STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO: u32 = 1_000_044_002;
pub const STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO: u32 = 1_000_044_004;
pub const STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_DIVISOR_STATE_CREATE_INFO: u32 = 1_000_190_000;
pub const STRUCTURE_TYPE_CONDITIONAL_RENDERING_BEGIN_INFO_EXT: u32 = 1_000_081_000;
pub const STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: u32 = 1_000_138_000;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2: u32 = 1_000_059_000;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2: u32 = 1_000_059_001;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2: u32 = 1_000_059_002;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT: u32 = 1_000_237_000;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES: u32 = 51;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES: u32 = 53;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR: u32 = 1_000_163_000;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES: u32 = 1_000_196_000;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES_KHR: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES: u32 = 1_000_197_000;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES_KHR: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT: u32 = 1_000_251_000;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DEMOTE_TO_HELPER_INVOCATION_FEATURES: u32 = 1_000_276_000;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DEMOTE_TO_HELPER_INVOCATION_FEATURES_EXT: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DEMOTE_TO_HELPER_INVOCATION_FEATURES;
pub const STRUCTURE_TYPE_PHYSICAL_DEVICE_NON_SEAMLESS_CUBE_MAP_FEATURES_EXT: u32 = 1_000_422_000;

pub const SEMAPHORE_TYPE_BINARY: u32 = 0;
pub const SEMAPHORE_TYPE_TIMELINE: u32 = 1;
pub const QUERY_TYPE_OCCLUSION: u32 = 0;
pub const QUERY_TYPE_PIPELINE_STATISTICS: u32 = 1;
pub const QUERY_TYPE_TIMESTAMP: u32 = 2;
pub const QUERY_RESULT_64_BIT: u32 = 0x0000_0001;
pub const QUERY_RESULT_WAIT_BIT: u32 = 0x0000_0002;
pub const QUERY_RESULT_WITH_AVAILABILITY_BIT: u32 = 0x0000_0004;
pub const QUERY_RESULT_PARTIAL_BIT: u32 = 0x0000_0008;
pub const DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK: u32 = 1_000_138_000;
pub const DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET: u32 = 0;
pub const CONDITIONAL_RENDERING_INVERTED_BIT_EXT: u32 = 0x0000_0001;

pub const INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR: u32 = 1;

pub const QUEUE_GRAPHICS_BIT: u32 = 0x0000_0001;
pub const QUEUE_COMPUTE_BIT: u32 = 0x0000_0002;
pub const QUEUE_TRANSFER_BIT: u32 = 0x0000_0004;

pub const FORMAT_UNDEFINED: u32 = 0;
pub const FORMAT_R8_UNORM: u32 = 9;
pub const FORMAT_R8G8_UNORM: u32 = 16;
pub const FORMAT_R8G8B8A8_UNORM: u32 = 37;
pub const FORMAT_R8G8B8A8_SRGB: u32 = 43;
pub const FORMAT_B8G8R8A8_UNORM: u32 = 44;
pub const FORMAT_B8G8R8A8_SRGB: u32 = 50;
pub const FORMAT_A8B8G8R8_UNORM_PACK32: u32 = 51;
pub const FORMAT_A2B10G10R10_UNORM_PACK32: u32 = 64;
pub const FORMAT_B4G4R4A4_UNORM_PACK16: u32 = 3;
pub const FORMAT_R5G6B5_UNORM_PACK16: u32 = 4;
pub const FORMAT_A1R5G5B5_UNORM_PACK16: u32 = 8;
pub const FORMAT_G8B8G8R8_422_UNORM: u32 = 1_000_156_000;
pub const FORMAT_B8G8R8G8_422_UNORM: u32 = 1_000_156_001;
pub const FORMAT_R16_UNORM: u32 = 70;
pub const FORMAT_R16G16_UNORM: u32 = 77;
pub const FORMAT_R16G16_SNORM: u32 = 78;
pub const FORMAT_R16_SFLOAT: u32 = 76;
pub const FORMAT_R16G16_SFLOAT: u32 = 83;
pub const FORMAT_R16G16B16A16_UNORM: u32 = 91;
pub const FORMAT_R16G16B16A16_SNORM: u32 = 92;
pub const FORMAT_R16G16B16A16_SFLOAT: u32 = 97;
pub const FORMAT_R32_SFLOAT: u32 = 100;
pub const FORMAT_R32G32_SFLOAT: u32 = 103;
pub const FORMAT_R32G32B32_SFLOAT: u32 = 106;
pub const FORMAT_R32G32B32A32_SFLOAT: u32 = 109;
pub const FORMAT_BC1_RGBA_UNORM_BLOCK: u32 = 133;
pub const FORMAT_BC2_UNORM_BLOCK: u32 = 135;
pub const FORMAT_BC3_UNORM_BLOCK: u32 = 137;
pub const FORMAT_BC4_UNORM_BLOCK: u32 = 139;
pub const FORMAT_BC5_UNORM_BLOCK: u32 = 141;
pub const FORMAT_BC6H_UFLOAT_BLOCK: u32 = 143;
pub const FORMAT_BC7_UNORM_BLOCK: u32 = 145;

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

pub const PIPELINE_BIND_POINT_GRAPHICS: u32 = 0;
pub const PIPELINE_BIND_POINT_COMPUTE: u32 = 1;
pub const INDEX_TYPE_UINT16: u32 = 0;
pub const INDEX_TYPE_UINT32: u32 = 1;
pub const SUBPASS_CONTENTS_INLINE: u32 = 0;
pub const DEPENDENCY_BY_REGION_BIT: u32 = 0x0000_0001;

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

pub const PhysicalDeviceFeatures2 = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
    p_next: ?*anyopaque = null,
    features: [220]u8 = [_]u8{0} ** 220,
};

pub const PhysicalDeviceProperties2 = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
    p_next: ?*anyopaque = null,
    properties: [physical_device_properties_bytes]u8 = [_]u8{0} ** physical_device_properties_bytes,
};

pub const ConformanceVersion = extern struct {
    major: u8 = 0,
    minor: u8 = 0,
    subminor: u8 = 0,
    patch: u8 = 0,
};

/// Property-chain nodes used by Xenia's adapter probing.  These are kept as
/// real ABI structs instead of raw byte arrays so the real properties2 path
/// can chain host-owned nodes without ever handing a guest pointer to the
/// Vulkan loader.
pub const PhysicalDeviceDriverProperties = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES,
    p_next: ?*anyopaque = null,
    driver_id: u32 = 0,
    driver_name: [256]u8 = [_]u8{0} ** 256,
    driver_info: [256]u8 = [_]u8{0} ** 256,
    conformance_version: ConformanceVersion = .{},
};

pub const PhysicalDeviceFloatControlsProperties = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES,
    p_next: ?*anyopaque = null,
    denorm_behavior_independence: u32 = 0,
    rounding_mode_independence: u32 = 0,
    shader_signed_zero_inf_nan_preserve_float16: u32 = 0,
    shader_signed_zero_inf_nan_preserve_float32: u32 = 0,
    shader_signed_zero_inf_nan_preserve_float64: u32 = 0,
    shader_denorm_preserve_float16: u32 = 0,
    shader_denorm_preserve_float32: u32 = 0,
    shader_denorm_preserve_float64: u32 = 0,
    shader_denorm_flush_to_zero_float16: u32 = 0,
    shader_denorm_flush_to_zero_float32: u32 = 0,
    shader_denorm_flush_to_zero_float64: u32 = 0,
    shader_rounding_mode_rte_float16: u32 = 0,
    shader_rounding_mode_rte_float32: u32 = 0,
    shader_rounding_mode_rte_float64: u32 = 0,
    shader_rounding_mode_rtz_float16: u32 = 0,
    shader_rounding_mode_rtz_float32: u32 = 0,
    shader_rounding_mode_rtz_float64: u32 = 0,
};

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

pub const PhysicalDeviceMemoryProperties2 = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2,
    p_next: ?*anyopaque = null,
    memory_properties: PhysicalDeviceMemoryProperties = .{},
};

pub const PhysicalDeviceMemoryBudgetPropertiesEXT = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT,
    p_next: ?*anyopaque = null,
    heap_budget: [MAX_MEMORY_HEAPS]u64 = [_]u64{0} ** MAX_MEMORY_HEAPS,
    heap_usage: [MAX_MEMORY_HEAPS]u64 = [_]u64{0} ** MAX_MEMORY_HEAPS,
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

pub const CommandBufferInheritanceInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
    p_next: ?*const anyopaque = null,
    render_pass: u64 = null_handle,
    subpass: u32 = 0,
    _padding: u32 = 0,
    framebuffer: u64 = null_handle,
    occlusion_query_enable: u32 = 0,
    query_flags: u32 = 0,
    pipeline_statistics: u32 = 0,
};

pub const CommandBufferInheritanceRenderingInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    view_mask: u32 = 0,
    color_attachment_count: u32 = 0,
    color_attachment_formats: ?[*]const u32 = null,
    depth_attachment_format: u32 = FORMAT_UNDEFINED,
    stencil_attachment_format: u32 = FORMAT_UNDEFINED,
    rasterization_samples: u32 = SAMPLE_COUNT_1_BIT,
};

pub const DescriptorSetAllocateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    p_next: ?*const anyopaque = null,
    descriptor_pool: u64 = null_handle,
    descriptor_set_count: u32 = 0,
    descriptor_set_layouts: ?[*]const u64 = null,
};

pub const DescriptorImageInfo = extern struct {
    sampler: u64 = null_handle,
    image_view: u64 = null_handle,
    image_layout: u32 = IMAGE_LAYOUT_UNDEFINED,
    _padding: u32 = 0,
};

pub const DescriptorBufferInfo = extern struct {
    buffer: Buffer = null_handle,
    offset: u64 = 0,
    range: u64 = 0,
};

pub const WriteDescriptorSet = extern struct {
    s_type: u32 = WriteDescriptorSet_structure_type,
    p_next: ?*const anyopaque = null,
    dst_set: u64 = null_handle,
    dst_binding: u32 = 0,
    dst_array_element: u32 = 0,
    descriptor_count: u32 = 0,
    descriptor_type: u32 = 0,
    image_info: ?[*]const DescriptorImageInfo = null,
    buffer_info: ?[*]const DescriptorBufferInfo = null,
    texel_buffer_view: ?[*]const u64 = null,
};

pub const WriteDescriptorSet_structure_type: u32 = 35;

pub const WriteDescriptorSetInlineUniformBlock = extern struct {
    s_type: u32 = STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK,
    p_next: ?*const anyopaque = null,
    data_size: u32 = 0,
    _padding: u32 = 0,
    data: ?*const anyopaque = null,
};

pub const ConditionalRenderingBeginInfoEXT = extern struct {
    s_type: u32 = STRUCTURE_TYPE_CONDITIONAL_RENDERING_BEGIN_INFO_EXT,
    p_next: ?*const anyopaque = null,
    buffer: Buffer = null_handle,
    offset: u64 = 0,
    flags: u32 = 0,
    _padding: u32 = 0,
};

pub const CopyDescriptorSet = extern struct {
    s_type: u32 = CopyDescriptorSet_structure_type,
    p_next: ?*const anyopaque = null,
    src_set: u64 = null_handle,
    src_binding: u32 = 0,
    src_array_element: u32 = 0,
    dst_set: u64 = null_handle,
    dst_binding: u32 = 0,
    dst_array_element: u32 = 0,
    descriptor_count: u32 = 0,
};

pub const CopyDescriptorSet_structure_type: u32 = 36;

pub const PipelineCache = u64;

pub const DescriptorUpdateTemplate = u64;

pub const DescriptorUpdateTemplateEntry = extern struct {
    dst_binding: u32 = 0,
    dst_array_element: u32 = 0,
    descriptor_count: u32 = 0,
    descriptor_type: u32 = 0,
    offset: u64 = 0,
    stride: u64 = 0,
};

pub const DescriptorUpdateTemplateCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_DESCRIPTOR_UPDATE_TEMPLATE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    descriptor_update_entry_count: u32 = 0,
    descriptor_update_entries: ?[*]const DescriptorUpdateTemplateEntry = null,
    template_type: u32 = DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET,
    descriptor_set_layout: u64 = null_handle,
    pipeline_bind_point: u32 = PIPELINE_BIND_POINT_GRAPHICS,
    pipeline_layout: u64 = null_handle,
    set: u32 = 0,
    _padding: u32 = 0,
};

pub const PipelineCacheCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    _padding: u32 = 0,
    initial_data_size: u64 = 0,
    initial_data: ?*const anyopaque = null,
};

pub const PipelineShaderStageCreateInfo = extern struct {
    s_type: u32 = 18,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    stage: u32 = 0,
    module: u64 = null_handle,
    name: ?[*:0]const u8 = null,
    specialization_info: ?*const anyopaque = null,
};

pub const VertexInputBindingDescription = extern struct {
    binding: u32 = 0,
    stride: u32 = 0,
    input_rate: u32 = 0,
};

pub const VertexInputAttributeDescription = extern struct {
    location: u32 = 0,
    binding: u32 = 0,
    format: u32 = FORMAT_UNDEFINED,
    offset: u32 = 0,
};

pub const PipelineVertexInputStateCreateInfo = extern struct {
    s_type: u32 = 19,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    vertex_binding_description_count: u32 = 0,
    vertex_binding_descriptions: ?[*]const VertexInputBindingDescription = null,
    vertex_attribute_description_count: u32 = 0,
    vertex_attribute_descriptions: ?[*]const VertexInputAttributeDescription = null,
};

pub const VertexInputBindingDivisorDescription = extern struct {
    binding: u32 = 0,
    divisor: u32 = 1,
};

pub const PipelineVertexInputDivisorStateCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_DIVISOR_STATE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    vertex_binding_divisor_count: u32 = 0,
    _padding: u32 = 0,
    vertex_binding_divisors: ?[*]const VertexInputBindingDivisorDescription = null,
};

pub const PipelineInputAssemblyStateCreateInfo = extern struct {
    s_type: u32 = 20,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    topology: u32 = 0,
    primitive_restart_enable: u32 = 0,
};

pub const PipelineTessellationStateCreateInfo = extern struct {
    s_type: u32 = 21,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    patch_control_points: u32 = 0,
};

pub const PipelineViewportStateCreateInfo = extern struct {
    s_type: u32 = 22,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    viewport_count: u32 = 0,
    viewports: ?[*]const Viewport = null,
    scissor_count: u32 = 0,
    scissors: ?[*]const Rect2D = null,
};

pub const PipelineRasterizationStateCreateInfo = extern struct {
    s_type: u32 = 23,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    depth_clamp_enable: u32 = 0,
    rasterizer_discard_enable: u32 = 0,
    polygon_mode: u32 = 0,
    cull_mode: u32 = 0,
    front_face: u32 = 0,
    depth_bias_enable: u32 = 0,
    depth_bias_constant_factor: f32 = 0,
    depth_bias_clamp: f32 = 0,
    depth_bias_slope_factor: f32 = 0,
    line_width: f32 = 1,
};

pub const PipelineMultisampleStateCreateInfo = extern struct {
    s_type: u32 = 24,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    rasterization_samples: u32 = SAMPLE_COUNT_1_BIT,
    sample_shading_enable: u32 = 0,
    min_sample_shading: f32 = 0,
    sample_mask: ?[*]const u32 = null,
    alpha_to_coverage_enable: u32 = 0,
    alpha_to_one_enable: u32 = 0,
};

pub const StencilOpState = extern struct {
    fail_op: u32 = 0,
    pass_op: u32 = 0,
    depth_fail_op: u32 = 0,
    compare_op: u32 = 7,
    compare_mask: u32 = 0xFFFF_FFFF,
    write_mask: u32 = 0xFFFF_FFFF,
    reference: u32 = 0,
};

pub const PipelineDepthStencilStateCreateInfo = extern struct {
    s_type: u32 = 25,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    depth_test_enable: u32 = 0,
    depth_write_enable: u32 = 0,
    depth_compare_op: u32 = 7,
    depth_bounds_test_enable: u32 = 0,
    stencil_test_enable: u32 = 0,
    front: StencilOpState = .{},
    back: StencilOpState = .{},
    min_depth_bounds: f32 = 0,
    max_depth_bounds: f32 = 1,
};

pub const PipelineColorBlendAttachmentState = extern struct {
    blend_enable: u32 = 0,
    src_color_blend_factor: u32 = 1,
    dst_color_blend_factor: u32 = 0,
    color_blend_op: u32 = 0,
    src_alpha_blend_factor: u32 = 1,
    dst_alpha_blend_factor: u32 = 0,
    alpha_blend_op: u32 = 0,
    color_write_mask: u32 = 0xF,
};

pub const PipelineColorBlendStateCreateInfo = extern struct {
    s_type: u32 = 26,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    logic_op_enable: u32 = 0,
    logic_op: u32 = 0,
    attachment_count: u32 = 0,
    attachments: ?[*]const PipelineColorBlendAttachmentState = null,
    blend_constants: [4]f32 = .{ 0, 0, 0, 0 },
};

pub const PipelineDynamicStateCreateInfo = extern struct {
    s_type: u32 = 27,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    dynamic_state_count: u32 = 0,
    dynamic_states: ?[*]const u32 = null,
};

pub const GraphicsPipelineCreateInfo = extern struct {
    s_type: u32 = 28,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    stage_count: u32 = 0,
    stages: ?[*]const PipelineShaderStageCreateInfo = null,
    vertex_input_state: ?*const PipelineVertexInputStateCreateInfo = null,
    input_assembly_state: ?*const PipelineInputAssemblyStateCreateInfo = null,
    tessellation_state: ?*const PipelineTessellationStateCreateInfo = null,
    viewport_state: ?*const PipelineViewportStateCreateInfo = null,
    rasterization_state: ?*const PipelineRasterizationStateCreateInfo = null,
    multisample_state: ?*const PipelineMultisampleStateCreateInfo = null,
    depth_stencil_state: ?*const PipelineDepthStencilStateCreateInfo = null,
    color_blend_state: ?*const PipelineColorBlendStateCreateInfo = null,
    dynamic_state: ?*const PipelineDynamicStateCreateInfo = null,
    layout: u64 = null_handle,
    render_pass: u64 = null_handle,
    subpass: u32 = 0,
    _padding: u32 = 0,
    base_pipeline_handle: u64 = null_handle,
    base_pipeline_index: i32 = -1,
};

pub const PipelineRenderingCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    view_mask: u32 = 0,
    color_attachment_count: u32 = 0,
    color_attachment_formats: ?[*]const u32 = null,
    depth_attachment_format: u32 = FORMAT_UNDEFINED,
    stencil_attachment_format: u32 = FORMAT_UNDEFINED,
};

pub const ComputePipelineCreateInfo = extern struct {
    s_type: u32 = 29,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    stage: PipelineShaderStageCreateInfo = .{},
    layout: u64 = null_handle,
    base_pipeline_handle: u64 = null_handle,
    base_pipeline_index: i32 = -1,
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

pub const ImageFormatListCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_IMAGE_FORMAT_LIST_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    view_format_count: u32 = 0,
    view_formats: ?*const u32 = null,
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

pub const MemoryRequirements2 = extern struct {
    s_type: u32 = STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2,
    p_next: ?*anyopaque = null,
    memory_requirements: MemoryRequirements = .{},
};

pub const BufferMemoryRequirementsInfo2 = extern struct {
    s_type: u32 = STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2,
    p_next: ?*const anyopaque = null,
    buffer: Buffer = null_handle,
};

pub const ImageMemoryRequirementsInfo2 = extern struct {
    s_type: u32 = STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2,
    p_next: ?*const anyopaque = null,
    image: Image = null_handle,
};

pub const MemoryAllocateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    p_next: ?*const anyopaque = null,
    allocation_size: u64 = 0,
    memory_type_index: u32 = 0,
};

/// `VkMemoryDedicatedAllocateInfo` is used by the active Xenia Vulkan path
/// for its large shared and gamma-ramp buffers.  It is a pNext node, so it
/// must be copied and its resource handles translated before reaching the
/// host driver just like the root allocation structure.
pub const MemoryDedicatedAllocateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO,
    p_next: ?*const anyopaque = null,
    image: Image = null_handle,
    buffer: Buffer = null_handle,
};

pub const MappedMemoryRange = extern struct {
    s_type: u32 = STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
    p_next: ?*const anyopaque = null,
    memory: DeviceMemory = null_handle,
    offset: u64 = 0,
    size: u64 = 0,
};

pub const SemaphoreTypeCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    semaphore_type: u32 = SEMAPHORE_TYPE_BINARY,
    _padding: u32 = 0,
    initial_value: u64 = 0,
};

pub const PhysicalDeviceTimelineSemaphoreFeatures = extern struct {
    s_type: u32 = STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES,
    p_next: ?*anyopaque = null,
    timeline_semaphore: u32 = 0,
};

pub const SemaphoreWaitInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    _padding: u32 = 0,
    semaphore_count: u32 = 0,
    _padding_2: u32 = 0,
    semaphores: ?[*]const Semaphore = null,
    values: ?[*]const u64 = null,
};

pub const SemaphoreSignalInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO,
    p_next: ?*const anyopaque = null,
    semaphore: Semaphore = null_handle,
    value: u64 = 0,
};

pub const BufferImageCopy = extern struct {
    buffer_offset: u64 = 0,
    buffer_row_length: u32 = 0,
    buffer_image_height: u32 = 0,
    image_subresource: ImageSubresourceLayers = .{},
    image_offset: Offset3D = .{},
    image_extent: Extent3D = .{},
};

pub const Offset2D = extern struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const Rect2D = extern struct {
    offset: Offset2D = .{},
    extent: Extent2D = .{},
};

pub const Viewport = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    min_depth: f32 = 0,
    max_depth: f32 = 1,
};

pub const ClearDepthStencilValue = extern struct {
    depth: f32 = 1,
    stencil: u32 = 0,
};

pub const ClearValue = extern union {
    color: ClearColorValue,
    depth_stencil: ClearDepthStencilValue,
};

pub const RenderPassBeginInfo = extern struct {
    s_type: u32 = 43,
    p_next: ?*const anyopaque = null,
    render_pass: u64 = null_handle,
    framebuffer: u64 = null_handle,
    render_area: Rect2D = .{},
    clear_value_count: u32 = 0,
    clear_values: ?[*]const ClearValue = null,
};

pub const BufferCopy = extern struct {
    src_offset: u64 = 0,
    dst_offset: u64 = 0,
    size: u64 = 0,
};

pub const ImageCopy = extern struct {
    src_subresource: ImageSubresourceLayers = .{},
    src_offset: Offset3D = .{},
    dst_subresource: ImageSubresourceLayers = .{},
    dst_offset: Offset3D = .{},
    extent: Extent3D = .{},
};

pub const ImageResolve = extern struct {
    src_subresource: ImageSubresourceLayers = .{},
    src_offset: Offset3D = .{},
    dst_subresource: ImageSubresourceLayers = .{},
    dst_offset: Offset3D = .{},
    extent: Extent3D = .{},
};

pub const MemoryBarrier = extern struct {
    s_type: u32 = 46,
    p_next: ?*const anyopaque = null,
    src_access_mask: u32 = 0,
    dst_access_mask: u32 = 0,
};

pub const BufferMemoryBarrier = extern struct {
    s_type: u32 = buffer_memory_barrier_structure_type,
    p_next: ?*const anyopaque = null,
    src_access_mask: u32 = 0,
    dst_access_mask: u32 = 0,
    src_queue_family_index: u32 = QUEUE_FAMILY_IGNORED,
    dst_queue_family_index: u32 = QUEUE_FAMILY_IGNORED,
    buffer: Buffer = null_handle,
    offset: u64 = 0,
    size: u64 = 0,
};

pub const buffer_memory_barrier_structure_type: u32 = 44;

pub const MemoryBarrier2 = extern struct {
    s_type: u32 = 1000314000,
    p_next: ?*const anyopaque = null,
    src_stage_mask: u64 = 0,
    src_access_mask: u64 = 0,
    dst_stage_mask: u64 = 0,
    dst_access_mask: u64 = 0,
};

pub const BufferMemoryBarrier2 = extern struct {
    s_type: u32 = 1000314001,
    p_next: ?*const anyopaque = null,
    src_stage_mask: u64 = 0,
    src_access_mask: u64 = 0,
    dst_stage_mask: u64 = 0,
    dst_access_mask: u64 = 0,
    src_queue_family_index: u32 = QUEUE_FAMILY_IGNORED,
    dst_queue_family_index: u32 = QUEUE_FAMILY_IGNORED,
    buffer: Buffer = null_handle,
    offset: u64 = 0,
    size: u64 = 0,
};

pub const ImageMemoryBarrier2 = extern struct {
    s_type: u32 = 1000314002,
    p_next: ?*const anyopaque = null,
    src_stage_mask: u64 = 0,
    src_access_mask: u64 = 0,
    dst_stage_mask: u64 = 0,
    dst_access_mask: u64 = 0,
    old_layout: u32 = IMAGE_LAYOUT_UNDEFINED,
    new_layout: u32 = IMAGE_LAYOUT_UNDEFINED,
    src_queue_family_index: u32 = QUEUE_FAMILY_IGNORED,
    dst_queue_family_index: u32 = QUEUE_FAMILY_IGNORED,
    image: Image = null_handle,
    subresource_range: ImageSubresourceRange = .{},
};

pub const DependencyInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_DEPENDENCY_INFO,
    p_next: ?*const anyopaque = null,
    dependency_flags: u32 = 0,
    memory_barrier_count: u32 = 0,
    memory_barriers: ?[*]const MemoryBarrier2 = null,
    buffer_memory_barrier_count: u32 = 0,
    buffer_memory_barriers: ?[*]const BufferMemoryBarrier2 = null,
    image_memory_barrier_count: u32 = 0,
    image_memory_barriers: ?[*]const ImageMemoryBarrier2 = null,
};

pub const ClearAttachment = extern struct {
    aspect_mask: u32 = IMAGE_ASPECT_COLOR_BIT,
    color_attachment: u32 = 0,
    clear_value: ClearValue = .{ .color = .{ .float32 = .{ 0, 0, 0, 0 } } },
};

pub const ClearRect = extern struct {
    rect: Rect2D = .{},
    base_array_layer: u32 = 0,
    layer_count: u32 = 1,
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

pub const SemaphoreSubmitInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
    p_next: ?*const anyopaque = null,
    semaphore: Semaphore = null_handle,
    value: u64 = 0,
    stage_mask: u64 = 0,
    device_index: u32 = 0,
    _padding: u32 = 0,
};

pub const CommandBufferSubmitInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
    p_next: ?*const anyopaque = null,
    command_buffer: CommandBuffer = null,
    device_mask: u32 = 0,
    _padding: u32 = 0,
};

pub const SubmitInfo2 = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SUBMIT_INFO_2,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    wait_semaphore_info_count: u32 = 0,
    wait_semaphore_infos: ?[*]const SemaphoreSubmitInfo = null,
    command_buffer_info_count: u32 = 0,
    command_buffer_infos: ?[*]const CommandBufferSubmitInfo = null,
    signal_semaphore_info_count: u32 = 0,
    signal_semaphore_infos: ?[*]const SemaphoreSubmitInfo = null,
};

pub const SparseMemoryBind = extern struct {
    resource_offset: u64 = 0,
    size: u64 = 0,
    memory: DeviceMemory = null_handle,
    memory_offset: u64 = 0,
    flags: u32 = 0,
    _padding: u32 = 0,
};

pub const SparseBufferMemoryBindInfo = extern struct {
    buffer: Buffer = null_handle,
    bind_count: u32 = 0,
    binds: ?[*]const SparseMemoryBind = null,
};

pub const ImageSubresource = extern struct {
    aspect_mask: u32 = IMAGE_ASPECT_COLOR_BIT,
    mip_level: u32 = 0,
    array_layer: u32 = 0,
};

pub const SparseImageMemoryBind = extern struct {
    subresource: ImageSubresource = .{},
    offset: Offset3D = .{},
    extent: Extent3D = .{},
    memory: DeviceMemory = null_handle,
    memory_offset: u64 = 0,
    flags: u32 = 0,
    _padding: u32 = 0,
};

pub const SparseImageOpaqueMemoryBindInfo = extern struct {
    image: Image = null_handle,
    bind_count: u32 = 0,
    binds: ?[*]const SparseMemoryBind = null,
};

pub const SparseImageMemoryBindInfo = extern struct {
    image: Image = null_handle,
    bind_count: u32 = 0,
    binds: ?[*]const SparseImageMemoryBind = null,
};

pub const BindSparseInfo = extern struct {
    s_type: u32 = 7,
    p_next: ?*const anyopaque = null,
    wait_semaphore_count: u32 = 0,
    wait_semaphores: ?[*]const Semaphore = null,
    buffer_bind_count: u32 = 0,
    buffer_binds: ?[*]const SparseBufferMemoryBindInfo = null,
    image_opaque_bind_count: u32 = 0,
    image_opaque_binds: ?[*]const SparseImageOpaqueMemoryBindInfo = null,
    image_bind_count: u32 = 0,
    image_binds: ?[*]const SparseImageMemoryBindInfo = null,
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

pub const SubpassBeginInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SUBPASS_BEGIN_INFO,
    p_next: ?*const anyopaque = null,
    contents: u32 = SUBPASS_CONTENTS_INLINE,
};

pub const SubpassEndInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SUBPASS_END_INFO,
    p_next: ?*const anyopaque = null,
};

pub const RenderingAttachmentInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
    p_next: ?*const anyopaque = null,
    image_view: ImageView = null_handle,
    image_layout: u32 = IMAGE_LAYOUT_UNDEFINED,
    resolve_mode: u32 = 0,
    resolve_image_view: ImageView = null_handle,
    resolve_image_layout: u32 = IMAGE_LAYOUT_UNDEFINED,
    load_op: u32 = 0,
    store_op: u32 = 0,
    clear_value: ClearValue = .{ .color = .{ .float32 = .{ 0, 0, 0, 0 } } },
};

pub const RenderingInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_RENDERING_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    render_area: Rect2D = .{},
    layer_count: u32 = 1,
    view_mask: u32 = 0,
    color_attachment_count: u32 = 0,
    color_attachments: ?[*]const RenderingAttachmentInfo = null,
    depth_attachment: ?*const RenderingAttachmentInfo = null,
    stencil_attachment: ?*const RenderingAttachmentInfo = null,
};

pub const QueryPoolCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    query_type: u32 = QUERY_TYPE_OCCLUSION,
    query_count: u32 = 0,
    pipeline_statistics: u32 = 0,
};

pub const PfnVoidFunction = *const anyopaque;

pub const PfnGetInstanceProcAddr = *const fn (Instance, [*:0]const u8) callconv(.c) ?PfnVoidFunction;
pub const PfnGetDeviceProcAddr = *const fn (Device, [*:0]const u8) callconv(.c) ?PfnVoidFunction;
pub const PfnEnumerateInstanceExtensionProperties = *const fn (?[*:0]const u8, *u32, ?[*]ExtensionProperties) callconv(.c) Result;
pub const PfnCreateInstance = *const fn (*const InstanceCreateInfo, ?*const anyopaque, *Instance) callconv(.c) Result;
pub const PfnDestroyInstance = *const fn (Instance, ?*const anyopaque) callconv(.c) void;
pub const PfnEnumeratePhysicalDevices = *const fn (Instance, *u32, ?[*]PhysicalDevice) callconv(.c) Result;
pub const PfnGetPhysicalDeviceProperties = *const fn (PhysicalDevice, *anyopaque) callconv(.c) void;
pub const PfnGetPhysicalDeviceFeatures = *const fn (PhysicalDevice, *anyopaque) callconv(.c) void;
pub const PfnGetPhysicalDeviceFeatures2 = *const fn (PhysicalDevice, *PhysicalDeviceFeatures2) callconv(.c) void;
pub const PfnGetPhysicalDeviceProperties2 = *const fn (PhysicalDevice, *PhysicalDeviceProperties2) callconv(.c) void;
pub const PfnGetPhysicalDeviceQueueFamilyProperties = *const fn (PhysicalDevice, *u32, ?[*]QueueFamilyProperties) callconv(.c) void;
pub const PfnGetPhysicalDeviceMemoryProperties = *const fn (PhysicalDevice, *PhysicalDeviceMemoryProperties) callconv(.c) void;
pub const PfnGetPhysicalDeviceMemoryProperties2 = *const fn (PhysicalDevice, *PhysicalDeviceMemoryProperties2) callconv(.c) void;
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
pub const PfnGetSemaphoreCounterValue = *const fn (Device, Semaphore, *u64) callconv(.c) Result;
pub const PfnWaitSemaphores = *const fn (Device, *const SemaphoreWaitInfo, u64) callconv(.c) Result;
pub const PfnSignalSemaphore = *const fn (Device, *const SemaphoreSignalInfo) callconv(.c) Result;
pub const PfnCreateSwapchainKHR = *const fn (Device, *const SwapchainCreateInfoKHR, ?*const anyopaque, *SwapchainKHR) callconv(.c) Result;
pub const PfnDestroySwapchainKHR = *const fn (Device, SwapchainKHR, ?*const anyopaque) callconv(.c) void;
pub const PfnGetSwapchainImagesKHR = *const fn (Device, SwapchainKHR, *u32, ?[*]Image) callconv(.c) Result;
pub const PfnAcquireNextImageKHR = *const fn (Device, SwapchainKHR, u64, Semaphore, Fence, *u32) callconv(.c) Result;
pub const PfnQueuePresentKHR = *const fn (Queue, *const PresentInfoKHR) callconv(.c) Result;
pub const PfnCreateCommandPool = *const fn (Device, *const CommandPoolCreateInfo, ?*const anyopaque, *CommandPool) callconv(.c) Result;
pub const PfnDestroyCommandPool = *const fn (Device, CommandPool, ?*const anyopaque) callconv(.c) void;
pub const PfnAllocateCommandBuffers = *const fn (Device, *const CommandBufferAllocateInfo, [*]CommandBuffer) callconv(.c) Result;
pub const PfnFreeCommandBuffers = *const fn (Device, CommandPool, u32, [*]const CommandBuffer) callconv(.c) void;
pub const PfnBeginCommandBuffer = *const fn (CommandBuffer, *const CommandBufferBeginInfo) callconv(.c) Result;
pub const PfnEndCommandBuffer = *const fn (CommandBuffer) callconv(.c) Result;
pub const PfnResetCommandBuffer = *const fn (CommandBuffer, u32) callconv(.c) Result;
pub const PfnCreateSemaphore = *const fn (Device, *const SemaphoreCreateInfo, ?*const anyopaque, *Semaphore) callconv(.c) Result;
pub const PfnDestroySemaphore = *const fn (Device, Semaphore, ?*const anyopaque) callconv(.c) void;
pub const PfnCreateFence = *const fn (Device, *const FenceCreateInfo, ?*const anyopaque, *Fence) callconv(.c) Result;
pub const PfnDestroyFence = *const fn (Device, Fence, ?*const anyopaque) callconv(.c) void;
pub const PfnWaitForFences = *const fn (Device, u32, [*]const Fence, u32, u64) callconv(.c) Result;
pub const PfnResetFences = *const fn (Device, u32, [*]const Fence) callconv(.c) Result;
pub const PfnGetFenceStatus = *const fn (Device, Fence) callconv(.c) Result;
pub const PfnResetCommandPool = *const fn (Device, CommandPool, u32) callconv(.c) Result;
pub const PfnQueueSubmit = *const fn (Queue, u32, ?[*]const SubmitInfo, Fence) callconv(.c) Result;
pub const PfnQueueSubmit2 = *const fn (Queue, u32, ?[*]const SubmitInfo2, Fence) callconv(.c) Result;
pub const PfnQueueBindSparse = *const fn (Queue, u32, ?[*]const BindSparseInfo, Fence) callconv(.c) Result;
pub const PfnQueueWaitIdle = *const fn (Queue) callconv(.c) Result;
pub const PfnCmdBindPipeline = *const fn (CommandBuffer, u32, u64) callconv(.c) void;
pub const PfnCmdExecuteCommands = *const fn (CommandBuffer, u32, [*]const CommandBuffer) callconv(.c) void;
pub const PfnCmdBindVertexBuffers = *const fn (CommandBuffer, u32, u32, [*]const Buffer, [*]const u64) callconv(.c) void;
pub const PfnCmdBindIndexBuffer = *const fn (CommandBuffer, Buffer, u64, u32) callconv(.c) void;
pub const PfnCmdBindDescriptorSets = *const fn (CommandBuffer, u32, u64, u32, u32, [*]const u64, u32, ?[*]const u32) callconv(.c) void;
pub const PfnCmdPushDescriptorSetKHR = *const fn (CommandBuffer, u32, u64, u32, u32, [*]const WriteDescriptorSet) callconv(.c) void;
pub const PfnCmdDraw = *const fn (CommandBuffer, u32, u32, u32, u32) callconv(.c) void;
pub const PfnCmdDrawIndexed = *const fn (CommandBuffer, u32, u32, u32, i32, u32) callconv(.c) void;
pub const PfnCmdDrawIndirect = *const fn (CommandBuffer, Buffer, u64, u32, u32) callconv(.c) void;
pub const PfnCmdDrawIndexedIndirect = *const fn (CommandBuffer, Buffer, u64, u32, u32) callconv(.c) void;
pub const PfnCmdDrawIndirectCount = *const fn (CommandBuffer, Buffer, u64, Buffer, u64, u32, u32) callconv(.c) void;
pub const PfnCmdDrawIndexedIndirectCount = *const fn (CommandBuffer, Buffer, u64, Buffer, u64, u32, u32) callconv(.c) void;
pub const PfnCmdDispatch = *const fn (CommandBuffer, u32, u32, u32) callconv(.c) void;
pub const PfnCmdDispatchIndirect = *const fn (CommandBuffer, Buffer, u64) callconv(.c) void;
pub const PfnCmdDispatchBase = *const fn (CommandBuffer, u32, u32, u32, u32, u32, u32) callconv(.c) void;
pub const PfnCmdSetViewport = *const fn (CommandBuffer, u32, u32, [*]const Viewport) callconv(.c) void;
pub const PfnCmdSetScissor = *const fn (CommandBuffer, u32, u32, [*]const Rect2D) callconv(.c) void;
pub const PfnCmdSetBlendConstants = *const fn (CommandBuffer, [*]const f32) callconv(.c) void;
pub const PfnCmdSetDepthBias = *const fn (CommandBuffer, f32, f32, f32) callconv(.c) void;
pub const PfnCmdSetDepthBounds = *const fn (CommandBuffer, f32, f32) callconv(.c) void;
pub const PfnCmdSetDepthTestEnable = *const fn (CommandBuffer, u32) callconv(.c) void;
pub const PfnCmdSetDepthWriteEnable = *const fn (CommandBuffer, u32) callconv(.c) void;
pub const PfnCmdSetDepthCompareOp = *const fn (CommandBuffer, u32) callconv(.c) void;
pub const PfnCmdSetStencilTestEnable = *const fn (CommandBuffer, u32) callconv(.c) void;
pub const PfnCmdSetStencilOp = *const fn (CommandBuffer, u32, u32, u32, u32, u32) callconv(.c) void;
pub const PfnCmdSetPrimitiveRestartEnable = *const fn (CommandBuffer, u32) callconv(.c) void;
pub const PfnCmdSetStencilCompareMask = *const fn (CommandBuffer, u32, u32) callconv(.c) void;
pub const PfnCmdSetStencilWriteMask = *const fn (CommandBuffer, u32, u32) callconv(.c) void;
pub const PfnCmdSetStencilReference = *const fn (CommandBuffer, u32, u32) callconv(.c) void;
pub const PfnCmdPushConstants = *const fn (CommandBuffer, u64, u32, u32, u32, ?*const anyopaque) callconv(.c) void;
pub const PfnCmdBeginRenderPass = *const fn (CommandBuffer, *const RenderPassBeginInfo, u32) callconv(.c) void;
pub const PfnCmdNextSubpass = *const fn (CommandBuffer, u32) callconv(.c) void;
pub const PfnCmdEndRenderPass = *const fn (CommandBuffer) callconv(.c) void;
pub const PfnCmdBeginRenderPass2 = *const fn (CommandBuffer, *const RenderPassBeginInfo, *const SubpassBeginInfo) callconv(.c) void;
pub const PfnCmdNextSubpass2 = *const fn (CommandBuffer, *const SubpassBeginInfo, *const SubpassEndInfo) callconv(.c) void;
pub const PfnCmdEndRenderPass2 = *const fn (CommandBuffer, *const SubpassEndInfo) callconv(.c) void;
pub const PfnCmdBeginConditionalRenderingEXT = *const fn (CommandBuffer, *const ConditionalRenderingBeginInfoEXT) callconv(.c) void;
pub const PfnCmdEndConditionalRenderingEXT = *const fn (CommandBuffer) callconv(.c) void;
pub const PfnCmdBeginRendering = *const fn (CommandBuffer, *const RenderingInfo) callconv(.c) void;
pub const PfnCmdEndRendering = *const fn (CommandBuffer) callconv(.c) void;
pub const PfnCmdCopyBuffer = *const fn (CommandBuffer, Buffer, Buffer, u32, [*]const BufferCopy) callconv(.c) void;
pub const PfnCmdCopyImage = *const fn (CommandBuffer, Image, u32, Image, u32, u32, [*]const ImageCopy) callconv(.c) void;
pub const PfnCmdCopyImageToBuffer = *const fn (CommandBuffer, Image, u32, Buffer, u32, [*]const BufferImageCopy) callconv(.c) void;
pub const PfnCmdFillBuffer = *const fn (CommandBuffer, Buffer, u64, u64, u32) callconv(.c) void;
pub const PfnCmdUpdateBuffer = *const fn (CommandBuffer, Buffer, u64, u64, ?*const anyopaque) callconv(.c) void;
pub const PfnCmdResolveImage = *const fn (CommandBuffer, Image, u32, Image, u32, u32, [*]const ImageResolve) callconv(.c) void;
pub const PfnCmdClearDepthStencilImage = *const fn (CommandBuffer, Image, u32, *const ClearDepthStencilValue, u32, [*]const ImageSubresourceRange) callconv(.c) void;
pub const PfnCmdClearAttachments = *const fn (CommandBuffer, u32, [*]const ClearAttachment, u32, [*]const ClearRect) callconv(.c) void;
pub const PfnCmdPipelineBarrier = *const fn (CommandBuffer, u32, u32, u32, u32, ?*const anyopaque, u32, ?*const anyopaque, u32, ?[*]const ImageMemoryBarrier) callconv(.c) void;
pub const PfnCmdPipelineBarrier2 = *const fn (CommandBuffer, *const DependencyInfo) callconv(.c) void;
pub const PfnCmdClearColorImage = *const fn (CommandBuffer, Image, u32, *const ClearColorValue, u32, [*]const ImageSubresourceRange) callconv(.c) void;
pub const PfnCmdCopyBufferToImage = *const fn (CommandBuffer, Buffer, Image, u32, u32, [*]const BufferImageCopy) callconv(.c) void;
pub const PfnGetPhysicalDeviceFormatProperties = *const fn (PhysicalDevice, u32, *FormatProperties) callconv(.c) void;
pub const PfnCmdBlitImage = *const fn (CommandBuffer, Image, u32, Image, u32, u32, [*]const ImageBlit, u32) callconv(.c) void;
pub const PfnCreateImage = *const fn (Device, *const ImageCreateInfo, ?*const anyopaque, *Image) callconv(.c) Result;
pub const PfnDestroyImage = *const fn (Device, Image, ?*const anyopaque) callconv(.c) void;
pub const PfnGetImageMemoryRequirements = *const fn (Device, Image, *MemoryRequirements) callconv(.c) void;
pub const PfnGetDeviceBufferMemoryRequirements = *const fn (Device, *const BufferMemoryRequirementsInfo2, *MemoryRequirements2) callconv(.c) void;
pub const PfnGetDeviceImageMemoryRequirements = *const fn (Device, *const ImageMemoryRequirementsInfo2, *MemoryRequirements2) callconv(.c) void;
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
pub const PfnInvalidateMappedMemoryRanges = *const fn (Device, u32, [*]const MappedMemoryRange) callconv(.c) Result;
pub const PfnAllocateDescriptorSets = *const fn (Device, *const DescriptorSetAllocateInfo, [*]u64) callconv(.c) Result;
pub const PfnUpdateDescriptorSets = *const fn (Device, u32, ?[*]const WriteDescriptorSet, u32, ?[*]const CopyDescriptorSet) callconv(.c) void;
pub const PfnCreateDescriptorUpdateTemplate = *const fn (Device, *const DescriptorUpdateTemplateCreateInfo, ?*const anyopaque, *DescriptorUpdateTemplate) callconv(.c) Result;
pub const PfnDestroyDescriptorUpdateTemplate = *const fn (Device, DescriptorUpdateTemplate, ?*const anyopaque) callconv(.c) void;
pub const PfnUpdateDescriptorSetWithTemplate = *const fn (Device, DescriptorSet, DescriptorUpdateTemplate, ?*const anyopaque) callconv(.c) void;
pub const PfnCreateGraphicsPipelines = *const fn (Device, PipelineCache, u32, [*]const GraphicsPipelineCreateInfo, ?*const anyopaque, [*]u64) callconv(.c) Result;
pub const PfnCreateComputePipelines = *const fn (Device, PipelineCache, u32, [*]const ComputePipelineCreateInfo, ?*const anyopaque, [*]u64) callconv(.c) Result;
pub const PfnCreatePipelineCache = *const fn (Device, *const PipelineCacheCreateInfo, ?*const anyopaque, *PipelineCache) callconv(.c) Result;
pub const PfnGetPipelineCacheData = *const fn (Device, PipelineCache, *usize, ?*anyopaque) callconv(.c) Result;
pub const PfnDestroyPipelineCache = *const fn (Device, PipelineCache, ?*const anyopaque) callconv(.c) void;
pub const PfnDestroyPipeline = *const fn (Device, u64, ?*const anyopaque) callconv(.c) void;
pub const PfnCreateQueryPool = *const fn (Device, *const QueryPoolCreateInfo, ?*const anyopaque, *QueryPool) callconv(.c) Result;
pub const PfnDestroyQueryPool = *const fn (Device, QueryPool, ?*const anyopaque) callconv(.c) void;
pub const PfnGetQueryPoolResults = *const fn (Device, QueryPool, u32, u32, usize, *anyopaque, u64, u32) callconv(.c) Result;
pub const PfnResetQueryPool = *const fn (Device, QueryPool, u32, u32) callconv(.c) void;
pub const PfnCmdBeginQuery = *const fn (CommandBuffer, QueryPool, u32, u32) callconv(.c) void;
pub const PfnCmdEndQuery = *const fn (CommandBuffer, QueryPool, u32) callconv(.c) void;
pub const PfnCmdResetQueryPool = *const fn (CommandBuffer, QueryPool, u32, u32) callconv(.c) void;
pub const PfnCmdCopyQueryPoolResults = *const fn (CommandBuffer, QueryPool, u32, u32, Buffer, u64, u64, u32) callconv(.c) void;

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
    std.debug.assert(@sizeOf(CommandBufferInheritanceInfo) == 56);
    std.debug.assert(@sizeOf(CommandBufferInheritanceRenderingInfo) == 56);
    std.debug.assert(@sizeOf(VertexInputBindingDivisorDescription) == 8);
    std.debug.assert(@sizeOf(PipelineVertexInputDivisorStateCreateInfo) == 32);
    std.debug.assert(@sizeOf(PipelineRenderingCreateInfo) == 40);
    std.debug.assert(@sizeOf(SemaphoreCreateInfo) == 24);
    std.debug.assert(@sizeOf(PipelineCacheCreateInfo) == 40);
    std.debug.assert(@sizeOf(DescriptorUpdateTemplateEntry) == 32);
    std.debug.assert(@sizeOf(DescriptorUpdateTemplateCreateInfo) == 72);
    std.debug.assert(@sizeOf(FenceCreateInfo) == 24);
    std.debug.assert(@sizeOf(ImageSubresourceRange) == 20);
    std.debug.assert(@sizeOf(ImageMemoryBarrier) == 72);
    std.debug.assert(@sizeOf(ClearColorValue) == 16);
    std.debug.assert(@sizeOf(BufferCreateInfo) == 56);
    std.debug.assert(@sizeOf(MemoryRequirements) == 24);
    std.debug.assert(@sizeOf(MemoryAllocateInfo) == 32);
    std.debug.assert(@sizeOf(MemoryDedicatedAllocateInfo) == 32);
    std.debug.assert(@sizeOf(MappedMemoryRange) == 40);
    std.debug.assert(@sizeOf(BufferImageCopy) == 56);
    std.debug.assert(@sizeOf(ImageCreateInfo) == 88);
    std.debug.assert(@sizeOf(ImageFormatListCreateInfo) == 32);
    std.debug.assert(@sizeOf(ImageBlit) == 80);
    std.debug.assert(@sizeOf(FormatProperties) == 12);
    std.debug.assert(@sizeOf(ImageSubresourceLayers) == 16);
    std.debug.assert(@sizeOf(Offset3D) == 12);
    std.debug.assert(@sizeOf(MetalSurfaceCreateInfoEXT) == 32);
    std.debug.assert(@sizeOf(InstanceCreateInfo) == 64);
    std.debug.assert(@sizeOf(Offset2D) == 8);
    std.debug.assert(@sizeOf(Rect2D) == 16);
    std.debug.assert(@sizeOf(Viewport) == 24);
    std.debug.assert(@sizeOf(RenderPassBeginInfo) == 64);
    std.debug.assert(@sizeOf(BufferCopy) == 24);
    std.debug.assert(@sizeOf(ImageCopy) == 68);
    std.debug.assert(@sizeOf(ImageResolve) == 68);
    std.debug.assert(@sizeOf(MemoryBarrier) == 24);
    std.debug.assert(@sizeOf(BufferMemoryBarrier) == 56);
    std.debug.assert(@sizeOf(ClearAttachment) == 24);
    std.debug.assert(@sizeOf(ClearRect) == 24);
    std.debug.assert(@sizeOf(DescriptorImageInfo) == 24);
    std.debug.assert(@sizeOf(DescriptorBufferInfo) == 24);
    std.debug.assert(@sizeOf(WriteDescriptorSet) == 64);
    std.debug.assert(@sizeOf(CopyDescriptorSet) == 56);
    std.debug.assert(@sizeOf(PipelineShaderStageCreateInfo) == 48);
    std.debug.assert(@sizeOf(VertexInputBindingDescription) == 12);
    std.debug.assert(@sizeOf(VertexInputAttributeDescription) == 16);
    std.debug.assert(@sizeOf(PipelineVertexInputStateCreateInfo) == 48);
    std.debug.assert(@sizeOf(PipelineInputAssemblyStateCreateInfo) == 32);
    std.debug.assert(@sizeOf(PipelineTessellationStateCreateInfo) == 24);
    std.debug.assert(@sizeOf(PipelineViewportStateCreateInfo) == 48);
    std.debug.assert(@sizeOf(PipelineRasterizationStateCreateInfo) == 64);
    std.debug.assert(@sizeOf(PipelineMultisampleStateCreateInfo) == 48);
    std.debug.assert(@sizeOf(StencilOpState) == 28);
    std.debug.assert(@sizeOf(PipelineDepthStencilStateCreateInfo) == 104);
    std.debug.assert(@sizeOf(PipelineColorBlendAttachmentState) == 32);
    std.debug.assert(@sizeOf(PipelineColorBlendStateCreateInfo) == 56);
    std.debug.assert(@sizeOf(PipelineDynamicStateCreateInfo) == 32);
    std.debug.assert(@sizeOf(GraphicsPipelineCreateInfo) == 144);
    std.debug.assert(@sizeOf(ComputePipelineCreateInfo) == 96);
    // Synchronisation 2, sparse binding, and query structures are forwarded
    // through the same guest-pointer marshalling boundary.  Keep their ABI
    // sizes checked here too; a single missing padding word would make the
    // driver read a guest address as a count or a handle.
    std.debug.assert(@sizeOf(MemoryRequirements2) == 40);
    std.debug.assert(@sizeOf(BufferMemoryRequirementsInfo2) == 24);
    std.debug.assert(@sizeOf(ImageMemoryRequirementsInfo2) == 24);
    std.debug.assert(@sizeOf(SemaphoreTypeCreateInfo) == 32);
    std.debug.assert(@sizeOf(PhysicalDeviceTimelineSemaphoreFeatures) == 24);
    std.debug.assert(@sizeOf(SemaphoreWaitInfo) == 48);
    std.debug.assert(@sizeOf(SemaphoreSignalInfo) == 32);
    std.debug.assert(@sizeOf(PhysicalDeviceDriverProperties) == 536);
    std.debug.assert(@sizeOf(PhysicalDeviceFloatControlsProperties) == 88);
    std.debug.assert(@sizeOf(PhysicalDeviceMemoryProperties2) == 536);
    std.debug.assert(@sizeOf(PhysicalDeviceMemoryBudgetPropertiesEXT) == 272);
    std.debug.assert(@sizeOf(MemoryBarrier2) == 48);
    std.debug.assert(@sizeOf(BufferMemoryBarrier2) == 80);
    std.debug.assert(@sizeOf(ImageMemoryBarrier2) == 96);
    std.debug.assert(@sizeOf(DependencyInfo) == 64);
    std.debug.assert(@sizeOf(SemaphoreSubmitInfo) == 48);
    std.debug.assert(@sizeOf(CommandBufferSubmitInfo) == 32);
    std.debug.assert(@sizeOf(SubmitInfo2) == 64);
    std.debug.assert(@sizeOf(SparseMemoryBind) == 40);
    std.debug.assert(@sizeOf(SparseBufferMemoryBindInfo) == 24);
    std.debug.assert(@sizeOf(ImageSubresource) == 12);
    std.debug.assert(@sizeOf(SparseImageMemoryBind) == 64);
    std.debug.assert(@sizeOf(SparseImageOpaqueMemoryBindInfo) == 24);
    std.debug.assert(@sizeOf(SparseImageMemoryBindInfo) == 24);
    std.debug.assert(@sizeOf(BindSparseInfo) == 96);
    std.debug.assert(@sizeOf(SubpassBeginInfo) == 24);
    std.debug.assert(@sizeOf(SubpassEndInfo) == 16);
    std.debug.assert(@sizeOf(QueryPoolCreateInfo) == 32);
    std.debug.assert(@sizeOf(WriteDescriptorSetInlineUniformBlock) == 32);
    std.debug.assert(@sizeOf(ConditionalRenderingBeginInfoEXT) == 40);
    std.debug.assert(@sizeOf(RenderingAttachmentInfo) == 72);
    std.debug.assert(@sizeOf(RenderingInfo) == 72);
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

// Size constants for reading create info structs from guest memory. These
// match the Vulkan specification's fixed struct sizes.
pub const ImageCreateInfo_size: u64 = @sizeOf(ImageCreateInfo);
pub const BufferCreateInfo_size: u64 = @sizeOf(BufferCreateInfo);
pub const CommandPoolCreateInfo_size: u64 = @sizeOf(CommandPoolCreateInfo);
pub const FenceCreateInfo_size: u64 = @sizeOf(FenceCreateInfo);
pub const SemaphoreCreateInfo_size: u64 = @sizeOf(SemaphoreCreateInfo);
