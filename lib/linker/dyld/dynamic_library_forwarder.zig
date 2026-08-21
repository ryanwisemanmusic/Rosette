const std = @import("std");
const builtin = @import("builtin");
const guest_sleep = @import("scheduler").guest_sleep;
const rosette_gpu = @import("gpu");
const abi = @import("gpu").vulkan.abi;
const marshal = @import("gpu").vulkan.marshal;
const tier_consistency = @import("gpu").vulkan.tier_consistency;
const guest_memory_geometry = @import("guest_memory_geometry.zig");
const machoCapturePrint = @import("event_log").machoCapturePrint;

const RTLD_LAZY: c_int = 0x1;
const RTLD_LOCAL: c_int = 0x4;
const MAX_LIBRARIES = 16;
const MAX_GUEST_LIBRARIES = 32;
pub const MAX_GUEST_SYMBOLS = 256;
const GUEST_LIBRARY_HANDLE_BASE: u64 = 0xFFFF_FC00_0000_0000;
pub const GUEST_SYMBOL_THUNK_BASE: u64 = 0xFFFF_FB00_0000_0000;
const SYNTHETIC_PHYSICAL_DEVICE_HANDLE: u64 = 0xFFFF_F600_0000_0011;
/// The one VkDebugUtilsMessengerEXT the bridge hands out.  It is a
/// non-dispatchable handle the guest only ever passes back to
/// vkDestroyDebugUtilsMessengerEXT, so a single distinguishable value is
/// enough and makes a stray handle obvious in a log.
const SYNTHETIC_DEBUG_MESSENGER_HANDLE: u64 = 0xFFFF_F600_0000_0021;

extern fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern fn dlclose(handle: *anyopaque) c_int;

pub const Signature = enum {
    no_args_i32,
    no_args_u32,
    darwin_vm_page_size,
    buffer_length_usize,
    two_buffers_length_i32,
    buffer_byte_length_pointer,
    guest_memory_copy,
    libcxx_getloc,
    libcxx_istream_sentry_constructor,
    guest_virtual_sleep,
    locale_info_pointer,
    socket_three_args,
    setsockopt_five_args,
    snprintf_three_args,
    connect_three_args,
    send_four_args,
    cccrypt,
    pointer_in_pointer_out,
};

pub const LibraryClass = enum {
    libsystem,
    libcxx,
};

pub const Spec = struct {
    symbol: []const u8,
    library: LibraryClass,
    signature: Signature,
};

pub const Outcome = union(enum) {
    handled: u64,
    handled_void,
};

const specs = [_]Spec{
    .{ .symbol = "getpid", .library = .libsystem, .signature = .no_args_i32 },
    .{ .symbol = "getppid", .library = .libsystem, .signature = .no_args_i32 },
    .{ .symbol = "getuid", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "geteuid", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "getgid", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "getegid", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "getpagesize", .library = .libsystem, .signature = .darwin_vm_page_size },
    .{ .symbol = "arc4random", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "strnlen", .library = .libsystem, .signature = .buffer_length_usize },
    .{ .symbol = "strncmp", .library = .libsystem, .signature = .two_buffers_length_i32 },
    .{ .symbol = "memcmp", .library = .libsystem, .signature = .two_buffers_length_i32 },
    .{ .symbol = "memchr", .library = .libsystem, .signature = .buffer_byte_length_pointer },
    .{ .symbol = "memcpy", .library = .libsystem, .signature = .guest_memory_copy },
    .{ .symbol = "_ZNSt3__18ios_base6xallocEv", .library = .libcxx, .signature = .no_args_i32 },
    .{ .symbol = "_ZNKSt3__18ios_base6getlocEv", .library = .libcxx, .signature = .libcxx_getloc },
    .{ .symbol = "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE6sentryC1ERS3_b", .library = .libcxx, .signature = .libcxx_istream_sentry_constructor },
    .{ .symbol = "_ZNSt3__111this_thread9sleep_forERKNS_6chrono8durationIxNS_5ratioILl1ELl1000000000EEEEE", .library = .libcxx, .signature = .guest_virtual_sleep },
    .{ .symbol = "nl_langinfo", .library = .libsystem, .signature = .locale_info_pointer },
    .{ .symbol = "socket", .library = .libsystem, .signature = .socket_three_args },
    .{ .symbol = "setsockopt", .library = .libsystem, .signature = .setsockopt_five_args },
    .{ .symbol = "snprintf", .library = .libsystem, .signature = .snprintf_three_args },
    .{ .symbol = "connect", .library = .libsystem, .signature = .connect_three_args },
    .{ .symbol = "send", .library = .libsystem, .signature = .send_four_args },
    .{ .symbol = "CCCrypt", .library = .libsystem, .signature = .cccrypt },
    .{ .symbol = "asctime", .library = .libsystem, .signature = .pointer_in_pointer_out },
};

const Library = struct {
    path: []const u8 = "",
    handle: ?*anyopaque = null,
};

const GuestLibrary = struct {
    token: u64 = 0,
    handle: ?*anyopaque = null,
    virtual_vulkan: bool = false,
    path_length: u16 = 0,
    path: [1024]u8 = [_]u8{0} ** 1024,
};

const GuestSymbolKind = enum {
    get_instance_proc_addr,
    get_device_proc_addr,
    enumerate_instance_extensions,
    enumerate_instance_layers,
    enumerate_instance_version,
    create_instance,
    destroy_instance,
    enumerate_physical_devices,
    enumerate_device_extensions,
    get_physical_device_features,
    get_physical_device_format_properties,
    get_physical_device_memory_properties,
    get_physical_device_properties,
    get_physical_device_queue_families,
    get_physical_device_features2,
    get_physical_device_memory_properties2,
    get_physical_device_properties2,
    create_device,
    get_device_queue,
    get_device_queue2,
    get_semaphore_counter_value,
    wait_semaphores,
    signal_semaphore,
    create_metal_surface,
    destroy_surface,
    get_surface_capabilities,
    get_surface_formats,
    get_surface_present_modes,
    get_surface_support,
    destroy_device,
    create_swapchain,
    destroy_swapchain,
    get_swapchain_images,
    acquire_next_image,
    queue_submit,
    queue_submit2,
    queue_bind_sparse,
    queue_present,
    queue_wait_idle,
    create_device_object,
    allocate_command_buffers,
    allocate_descriptor_sets,
    allocate_memory,
    map_memory,
    bind_image_memory,
    bind_buffer_memory,
    bind_image_memory2,
    bind_buffer_memory2,
    get_memory_requirements,
    get_memory_requirements2,
    get_device_buffer_memory_requirements,
    get_device_image_memory_requirements,
    create_pipeline_cache,
    create_descriptor_update_template,
    get_pipeline_cache_data,
    create_graphics_pipelines,
    begin_command_buffer,
    end_command_buffer,
    reset_command_buffer,
    reset_command_pool,
    reset_descriptor_pool,
    wait_for_fences,
    reset_fences,
    get_fence_status,
    get_query_pool_results,
    reset_query_pool,
    device_wait_idle,
    flush_mapped_memory_ranges,
    invalidate_mapped_memory_ranges,
    unmap_memory,
    destroy_device_object,
    command,
    update_descriptor_sets,
    update_descriptor_set_with_template,
    device_success,
    device_void,
    create_debug_messenger,
    destroy_debug_messenger,
    debug_utils_success,
    @"opaque",
};

const GuestSymbol = struct {
    token: u64 = 0,
    library_token: u64 = 0,
    kind: GuestSymbolKind = .@"opaque",
    /// FNV-1a of the stored `name` slice, computed once at allocation. Every
    /// guest call to this symbol re-dispatches through `forwardVulkanCommand`'s
    /// ~55-name compare chain; the stored hash turns each of those string walks
    /// into a u64 compare with no per-call hashing. Computed from the same
    /// truncated slice `name` holds, so they always agree.
    name_hash: u64 = 0,
    name_length: u8 = 0,
    name: [95]u8 = [_]u8{0} ** 95,
    calls: u64 = 0,
};

const VulkanPresenterStage = enum {
    none,
    metal_surface_requested,
    metal_surface_created,
    swapchain_requested,
    // The guest-visible swapchain and its images exist only as Rosette model
    // handles. This is the explicit fallback used when a native guest device
    // cannot be created; it cannot put pixels in the CAMetalLayer.
    synthetic_swapchain_ready,
    // The guest's Vulkan device and swapchain are native objects backed by the
    // same CAMetalLayer. The guest still sees stable Rosette handles for
    // non-dispatchable objects, but queue work reaches the real driver.
    guest_swapchain_ready,
    // Rosette's own native Vulkan presenter owns a real device, a real
    // swapchain and real images on the window's CAMetalLayer.
    native_drawable_ready,
    failed,
};

const VK_SYNTHETIC_DEVICE: u64 = 0xFFFF_F600_0000_0021;
const VK_SYNTHETIC_QUEUE: u64 = 0xFFFF_F600_0000_0031;
const VK_SYNTHETIC_SURFACE: u64 = 0xFFFF_F600_0000_0041;
const VK_STRUCTURE_TYPE_APPLICATION_INFO: u32 = 0;
const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO: u32 = 1;
const VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT: u32 = 1_000_217_000;
const VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR: u32 = 1_000_001_000;
const VK_SWAPCHAIN_CREATE_INFO_SIZE: u64 = 104;
const VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR: u32 = 1;

const VkApplicationInfo = extern struct {
    s_type: u32,
    p_next: ?*const anyopaque,
    application_name: ?[*:0]const u8,
    application_version: u32,
    engine_name: ?[*:0]const u8,
    engine_version: u32,
    api_version: u32,
};

const VkInstanceCreateInfo = extern struct {
    s_type: u32,
    p_next: ?*const anyopaque,
    flags: u32,
    application_info: ?*const VkApplicationInfo,
    enabled_layer_count: u32,
    enabled_layer_names: ?[*]const [*:0]const u8,
    enabled_extension_count: u32,
    enabled_extension_names: ?[*]const [*:0]const u8,
};

const VkMetalSurfaceCreateInfoEXT = extern struct {
    s_type: u32,
    p_next: ?*const anyopaque,
    flags: u32,
    layer: ?*const anyopaque,
};

const PfnVkCreateInstance = *const fn (*const VkInstanceCreateInfo, ?*const anyopaque, *?*anyopaque) callconv(.c) i32;
const PfnVkDestroyInstance = *const fn (?*anyopaque, ?*const anyopaque) callconv(.c) void;
const PfnVkGetInstanceProcAddr = *const fn (?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque;
const PfnVkCreateMetalSurfaceEXT = *const fn (?*anyopaque, *const VkMetalSurfaceCreateInfoEXT, ?*const anyopaque, *u64) callconv(.c) i32;
const PfnVkDestroySurfaceKHR = *const fn (?*anyopaque, u64, ?*const anyopaque) callconv(.c) void;

const NativeSurfaceResult = struct {
    enforced: bool,
    result: i32,
    surface: u64,
};

const MAX_VULKAN_MEMORY_ALLOCATIONS = 256;
const VulkanMemoryAllocation = struct {
    handle: u64 = 0,
    requested_size: u64 = 0,
    mapped_base: u64 = 0,
    mapped_size: u64 = 0,
    mapped_offset: u64 = 0,
    host_mapped_ptr: ?*anyopaque = null,
    host_mapped_size: u64 = 0,
};

// Offsets into VkImageCreateInfo and VkBufferCreateInfo. Read from the guest's
// own structures rather than guessed, because the extent and format they carry
// are the only description of what the guest intends to draw into.
// Derived from the ABI declaration rather than restated. A guest structure
// read at a hand-copied offset is wrong silently: the neighbouring field is
// usually a plausible value, so the guest simply gets a different resource
// than it asked for.
const VK_IMAGE_CREATE_INFO_FORMAT_OFFSET: u64 = @offsetOf(abi.ImageCreateInfo, "format");
const VK_IMAGE_CREATE_INFO_EXTENT_OFFSET: u64 = @offsetOf(abi.ImageCreateInfo, "extent");
const VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET: u64 = @offsetOf(abi.ImageCreateInfo, "mip_levels");
const VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET: u64 = @offsetOf(abi.ImageCreateInfo, "array_layers");
const VK_IMAGE_CREATE_INFO_TILING_OFFSET: u64 = @offsetOf(abi.ImageCreateInfo, "tiling");
const VK_IMAGE_CREATE_INFO_USAGE_OFFSET: u64 = @offsetOf(abi.ImageCreateInfo, "usage");
const VK_IMAGE_CREATE_INFO_SIZE: u64 = 88;
const VK_BUFFER_CREATE_INFO_SIZE_OFFSET: u64 = @offsetOf(abi.BufferCreateInfo, "size");
const VK_BUFFER_CREATE_INFO_USAGE_OFFSET: u64 = @offsetOf(abi.BufferCreateInfo, "usage");
const VK_BUFFER_CREATE_INFO_SIZE: u64 = 56;

const VulkanCallTrace = struct {
    sequence: u64 = 0,
    name_len: u8 = 0,
    name: [64]u8 = undefined,
    result: i32 = 0,
    arg0: u64 = 0,
    arg1: u64 = 0,
};

const MAX_VULKAN_RESOURCES = 128;
const MAX_REAL_MEMORY = 512;
const MAX_REAL_BUFFERS = 1024;
const MAX_REAL_IMAGES = 1024;
const MAX_REAL_SAMPLERS = 256;
const MAX_REAL_FENCES = 256;
const MAX_REAL_SEMAPHORES = 256;
const MAX_REAL_RENDER_PASSES = 256;
const MAX_REAL_FRAMEBUFFERS = 256;
const MAX_REAL_PIPELINES = 1024;
const MAX_REAL_SHADER_MODULES = 1024;
const MAX_REAL_DESCRIPTOR_SET_LAYOUTS = 256;
const MAX_REAL_PIPELINE_LAYOUTS = 256;
const MAX_REAL_DESCRIPTOR_POOLS = 64;
const MAX_REAL_DESCRIPTOR_SETS = 1024;
const MAX_REAL_COMMAND_POOLS = 32;
const MAX_REAL_COMMAND_BUFFERS = 256;
const MAX_REAL_SWAPCHAINS = 16;
const MAX_REAL_BUFFER_VIEWS = 256;
const MAX_REAL_IMAGE_VIEWS = 1024;
const MAX_REAL_QUERY_POOLS = 256;
const MAX_REAL_PIPELINE_CACHES = 32;
const MAX_REAL_DESCRIPTOR_UPDATE_TEMPLATES = 128;
const MAX_REAL_QUEUES = 64;
/// Upper bound on the host device extension table.  The host reports 131 on
/// an Apple M2 Max today; the bound only has to stay ahead of the driver, and
/// a table that is too short is reported to the guest as truncation rather
/// than silently trimmed.
const MAX_HOST_DEVICE_EXTENSIONS = 256;
/// Upper bound on a single surface enumeration the bridge can hand back.
/// MoltenVK reports sixty surface formats for a Metal surface, so this has to
/// clear that comfortably.
const MAX_SURFACE_ENUMERATION: u32 = 128;
/// How many swapchain images the bridge can name. A swapchain asks the driver
/// for `minImageCount + 1` and can legitimately get more; the count advertised
/// to the guest is clamped to this, and the fill then always satisfies it.
const MAX_SWAPCHAIN_IMAGES: usize = 8;
/// How many memory types the modelled adapter advertises when no real
/// physical device has been queried. Every memoryTypeBits mask the modelled
/// tier hands the guest has to stay inside this count.
const MODELLED_MEMORY_TYPE_COUNT: u32 = 1;
const VulkanResourceKind = enum { image, buffer };

/// Per-swapchain guest image state. Keeping this beside the handle map is
/// important during resize: the old swapchain can remain alive until the
/// guest destroys it, so one global image-handle array cannot describe both
/// generations at once.
const SwapchainRecord = struct {
    synthetic: u64 = 0,
    real: abi.SwapchainKHR = 0,
    image_handles: [MAX_SWAPCHAIN_IMAGES]u64 = [_]u64{0} ** MAX_SWAPCHAIN_IMAGES,
    image_count: u32 = 0,
};

/// Real Vulkan object handle stored by value. Dispatchable handles (Instance,
/// PhysicalDevice, Device, Queue, CommandBuffer) are pointers in the Vulkan
/// ABI; non-dispatchable handles are u64. Both are stored as u64 for uniform
/// mapping table access.
const RealHandle = u64;

/// Mapping from a synthetic guest handle to a real Vulkan handle. The synthetic
/// handle is the value written into guest memory; the real handle is the value
/// the driver returned. A null real handle means the slot is unused.
const HandleMap = struct {
    synthetic: u64 = 0,
    real: RealHandle = 0,

    pub fn findSlot(self: []HandleMap, synthetic: u64) ?*HandleMap {
        if (synthetic == 0) return null;
        for (self) |*entry| {
            if (entry.synthetic == synthetic) return entry;
        }
        return null;
    }

    pub fn findReal(self: []const HandleMap, synthetic: u64) ?RealHandle {
        if (synthetic == 0) return null;
        for (self) |entry| {
            if (entry.synthetic == synthetic) return entry.real;
        }
        return null;
    }

    pub fn alloc(self: []HandleMap, synthetic: u64, real: RealHandle) void {
        for (self) |*entry| {
            if (entry.synthetic != 0) continue;
            entry.* = .{ .synthetic = synthetic, .real = real };
            return;
        }
    }

    pub fn allocOrFind(self: []HandleMap, synthetic: u64, real: RealHandle) void {
        for (self) |*entry| {
            if (entry.synthetic == synthetic) {
                entry.real = real;
                return;
            }
        }
        for (self) |*entry| {
            if (entry.synthetic == 0) {
                entry.* = .{ .synthetic = synthetic, .real = real };
                return;
            }
        }
    }

    pub fn remove(self: []HandleMap, synthetic: u64) void {
        for (self) |*entry| {
            if (entry.synthetic == synthetic) {
                entry.* = .{};
                return;
            }
        }
    }
};

const DescriptorUpdateTemplateRecord = struct {
    entry_count: u8 = 0,
    entries: [64]abi.DescriptorUpdateTemplateEntry = [_]abi.DescriptorUpdateTemplateEntry{.{}} ** 64,
};

/// Real Vulkan function pointers resolved from the device via
/// vkGetDeviceProcAddr. Only non-dispatchable functions (no device-level
/// dispatch) are stored here; the instance-level loader handles the rest.
const DeviceFnPtrs = struct {
    get_device_queue: ?abi.PfnGetDeviceQueue = null,
    get_semaphore_counter_value: ?abi.PfnGetSemaphoreCounterValue = null,
    wait_semaphores: ?abi.PfnWaitSemaphores = null,
    signal_semaphore: ?abi.PfnSignalSemaphore = null,
    create_swapchain: ?abi.PfnCreateSwapchainKHR = null,
    destroy_swapchain: ?abi.PfnDestroySwapchainKHR = null,
    get_swapchain_images: ?abi.PfnGetSwapchainImagesKHR = null,
    acquire_next_image: ?abi.PfnAcquireNextImageKHR = null,
    queue_present: ?abi.PfnQueuePresentKHR = null,
    create_command_pool: ?abi.PfnCreateCommandPool = null,
    destroy_command_pool: ?abi.PfnDestroyCommandPool = null,
    allocate_command_buffers: ?abi.PfnAllocateCommandBuffers = null,
    free_command_buffers: ?abi.PfnFreeCommandBuffers = null,
    begin_command_buffer: ?abi.PfnBeginCommandBuffer = null,
    end_command_buffer: ?abi.PfnEndCommandBuffer = null,
    reset_command_buffer: ?abi.PfnResetCommandBuffer = null,
    create_semaphore: ?abi.PfnCreateSemaphore = null,
    destroy_semaphore: ?abi.PfnDestroySemaphore = null,
    create_fence: ?abi.PfnCreateFence = null,
    destroy_fence: ?abi.PfnDestroyFence = null,
    wait_for_fences: ?abi.PfnWaitForFences = null,
    reset_fences: ?abi.PfnResetFences = null,
    get_fence_status: ?abi.PfnGetFenceStatus = null,
    create_query_pool: ?abi.PfnCreateQueryPool = null,
    destroy_query_pool: ?abi.PfnDestroyQueryPool = null,
    get_query_pool_results: ?abi.PfnGetQueryPoolResults = null,
    reset_query_pool: ?abi.PfnResetQueryPool = null,
    reset_command_pool: ?abi.PfnResetCommandPool = null,
    queue_submit: ?abi.PfnQueueSubmit = null,
    queue_submit2: ?abi.PfnQueueSubmit2 = null,
    queue_bind_sparse: ?abi.PfnQueueBindSparse = null,
    queue_wait_idle: ?abi.PfnQueueWaitIdle = null,
    device_wait_idle: ?abi.PfnDeviceWaitIdle = null,
    create_buffer: ?abi.PfnCreateBuffer = null,
    destroy_buffer: ?abi.PfnDestroyBuffer = null,
    get_buffer_memory_requirements: ?abi.PfnGetBufferMemoryRequirements = null,
    bind_buffer_memory: ?abi.PfnBindBufferMemory = null,
    create_image: ?abi.PfnCreateImage = null,
    destroy_image: ?abi.PfnDestroyImage = null,
    get_image_memory_requirements: ?abi.PfnGetImageMemoryRequirements = null,
    get_device_buffer_memory_requirements: ?abi.PfnGetDeviceBufferMemoryRequirements = null,
    get_device_image_memory_requirements: ?abi.PfnGetDeviceImageMemoryRequirements = null,
    bind_image_memory: ?abi.PfnBindImageMemory = null,
    allocate_memory: ?abi.PfnAllocateMemory = null,
    free_memory: ?abi.PfnFreeMemory = null,
    map_memory: ?abi.PfnMapMemory = null,
    unmap_memory: ?abi.PfnUnmapMemory = null,
    flush_mapped_memory_ranges: ?abi.PfnFlushMappedMemoryRanges = null,
    create_sampler: ?*const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = null,
    destroy_sampler: ?*const fn (abi.Device, u64, ?*const anyopaque) callconv(.c) void = null,
    create_descriptor_set_layout: ?*const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = null,
    destroy_descriptor_set_layout: ?*const fn (abi.Device, u64, ?*const anyopaque) callconv(.c) void = null,
    create_pipeline_layout: ?*const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = null,
    destroy_pipeline_layout: ?*const fn (abi.Device, u64, ?*const anyopaque) callconv(.c) void = null,
    create_shader_module: ?*const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = null,
    destroy_shader_module: ?*const fn (abi.Device, u64, ?*const anyopaque) callconv(.c) void = null,
    create_render_pass: ?*const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = null,
    destroy_render_pass: ?*const fn (abi.Device, u64, ?*const anyopaque) callconv(.c) void = null,
    create_framebuffer: ?*const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = null,
    destroy_framebuffer: ?*const fn (abi.Device, u64, ?*const anyopaque) callconv(.c) void = null,
    create_graphics_pipelines: ?abi.PfnCreateGraphicsPipelines = null,
    create_compute_pipelines: ?abi.PfnCreateComputePipelines = null,
    create_pipeline_cache: ?abi.PfnCreatePipelineCache = null,
    get_pipeline_cache_data: ?abi.PfnGetPipelineCacheData = null,
    destroy_pipeline_cache: ?abi.PfnDestroyPipelineCache = null,
    create_descriptor_update_template: ?abi.PfnCreateDescriptorUpdateTemplate = null,
    destroy_descriptor_update_template: ?abi.PfnDestroyDescriptorUpdateTemplate = null,
    update_descriptor_set_with_template: ?abi.PfnUpdateDescriptorSetWithTemplate = null,
    destroy_pipeline: ?abi.PfnDestroyPipeline = null,
    create_descriptor_pool: ?*const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = null,
    destroy_descriptor_pool: ?*const fn (abi.Device, u64, ?*const anyopaque) callconv(.c) void = null,
    reset_descriptor_pool: ?*const fn (abi.Device, u64, u32) callconv(.c) i32 = null,
    allocate_descriptor_sets: ?abi.PfnAllocateDescriptorSets = null,
    free_descriptor_sets: ?*const fn (abi.Device, u64, u32, [*]const u64) callconv(.c) i32 = null,
    update_descriptor_sets: ?abi.PfnUpdateDescriptorSets = null,
    create_image_view: ?*const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = null,
    destroy_image_view: ?*const fn (abi.Device, u64, ?*const anyopaque) callconv(.c) void = null,
    create_buffer_view: ?*const fn (abi.Device, *const anyopaque, ?*const anyopaque, *u64) callconv(.c) i32 = null,
    destroy_buffer_view: ?*const fn (abi.Device, u64, ?*const anyopaque) callconv(.c) void = null,
    invalidate_mapped_memory_ranges: ?abi.PfnInvalidateMappedMemoryRanges = null,
    cmd_bind_pipeline: ?abi.PfnCmdBindPipeline = null,
    cmd_execute_commands: ?abi.PfnCmdExecuteCommands = null,
    cmd_bind_vertex_buffers: ?abi.PfnCmdBindVertexBuffers = null,
    cmd_bind_index_buffer: ?abi.PfnCmdBindIndexBuffer = null,
    cmd_bind_descriptor_sets: ?abi.PfnCmdBindDescriptorSets = null,
    cmd_push_descriptor_set: ?abi.PfnCmdPushDescriptorSetKHR = null,
    cmd_draw: ?abi.PfnCmdDraw = null,
    cmd_draw_indexed: ?abi.PfnCmdDrawIndexed = null,
    cmd_draw_indirect: ?abi.PfnCmdDrawIndirect = null,
    cmd_draw_indexed_indirect: ?abi.PfnCmdDrawIndexedIndirect = null,
    cmd_draw_indirect_count: ?abi.PfnCmdDrawIndirectCount = null,
    cmd_draw_indexed_indirect_count: ?abi.PfnCmdDrawIndexedIndirectCount = null,
    cmd_dispatch: ?abi.PfnCmdDispatch = null,
    cmd_dispatch_indirect: ?abi.PfnCmdDispatchIndirect = null,
    cmd_dispatch_base: ?abi.PfnCmdDispatchBase = null,
    cmd_set_viewport: ?abi.PfnCmdSetViewport = null,
    cmd_set_scissor: ?abi.PfnCmdSetScissor = null,
    cmd_set_blend_constants: ?abi.PfnCmdSetBlendConstants = null,
    cmd_set_depth_bias: ?abi.PfnCmdSetDepthBias = null,
    cmd_set_depth_bounds: ?abi.PfnCmdSetDepthBounds = null,
    cmd_set_depth_test_enable: ?abi.PfnCmdSetDepthTestEnable = null,
    cmd_set_depth_write_enable: ?abi.PfnCmdSetDepthWriteEnable = null,
    cmd_set_depth_compare_op: ?abi.PfnCmdSetDepthCompareOp = null,
    cmd_set_stencil_test_enable: ?abi.PfnCmdSetStencilTestEnable = null,
    cmd_set_stencil_op: ?abi.PfnCmdSetStencilOp = null,
    cmd_set_primitive_restart_enable: ?abi.PfnCmdSetPrimitiveRestartEnable = null,
    cmd_set_stencil_compare_mask: ?abi.PfnCmdSetStencilCompareMask = null,
    cmd_set_stencil_write_mask: ?abi.PfnCmdSetStencilWriteMask = null,
    cmd_set_stencil_reference: ?abi.PfnCmdSetStencilReference = null,
    cmd_push_constants: ?abi.PfnCmdPushConstants = null,
    cmd_begin_render_pass: ?abi.PfnCmdBeginRenderPass = null,
    cmd_next_subpass: ?abi.PfnCmdNextSubpass = null,
    cmd_end_render_pass: ?abi.PfnCmdEndRenderPass = null,
    cmd_begin_render_pass2: ?abi.PfnCmdBeginRenderPass2 = null,
    cmd_next_subpass2: ?abi.PfnCmdNextSubpass2 = null,
    cmd_end_render_pass2: ?abi.PfnCmdEndRenderPass2 = null,
    cmd_begin_conditional_rendering: ?abi.PfnCmdBeginConditionalRenderingEXT = null,
    cmd_end_conditional_rendering: ?abi.PfnCmdEndConditionalRenderingEXT = null,
    cmd_begin_rendering: ?abi.PfnCmdBeginRendering = null,
    cmd_end_rendering: ?abi.PfnCmdEndRendering = null,
    cmd_copy_buffer: ?abi.PfnCmdCopyBuffer = null,
    cmd_copy_image: ?abi.PfnCmdCopyImage = null,
    cmd_copy_buffer_to_image: ?abi.PfnCmdCopyBufferToImage = null,
    cmd_copy_image_to_buffer: ?abi.PfnCmdCopyImageToBuffer = null,
    cmd_blit_image: ?abi.PfnCmdBlitImage = null,
    cmd_fill_buffer: ?abi.PfnCmdFillBuffer = null,
    cmd_update_buffer: ?abi.PfnCmdUpdateBuffer = null,
    cmd_resolve_image: ?abi.PfnCmdResolveImage = null,
    cmd_clear_color_image: ?abi.PfnCmdClearColorImage = null,
    cmd_clear_depth_stencil_image: ?abi.PfnCmdClearDepthStencilImage = null,
    cmd_clear_attachments: ?abi.PfnCmdClearAttachments = null,
    cmd_pipeline_barrier: ?abi.PfnCmdPipelineBarrier = null,
    cmd_pipeline_barrier2: ?abi.PfnCmdPipelineBarrier2 = null,
    cmd_begin_query: ?abi.PfnCmdBeginQuery = null,
    cmd_end_query: ?abi.PfnCmdEndQuery = null,
    cmd_reset_query_pool: ?abi.PfnCmdResetQueryPool = null,
    cmd_copy_query_pool_results: ?abi.PfnCmdCopyQueryPoolResults = null,
    destroy_device: ?abi.PfnDestroyDevice = null,
    /// Valid after ensureDeviceFnPtrs; each pointer is looked up once via
    /// vkGetDeviceProcAddr and cached. The flags track which we resolved so
    /// the log only fires once.
    resolved: bool = false,
};

/// Phase 1: real Vulkan objects. Holds every handle the guest's Vulkan calls
/// produce, plus the function pointers to manipulate them. The forwarding layer
/// maps synthetic guest handles to these real handles so the guest code runs
/// against MoltenVK instead of against counters.
///
/// This is separate from the native presenter, which owns its own device,
/// swapchain, and queue for the host presentation path. The two coexist:
/// the guest uses this for its own rendering; the presenter uses its own for
/// presenting to CAMetalLayer.
const RealVulkanState = struct {
    // --- Instance level ---
    /// Real VkInstance created by the guest's vkCreateInstance.
    instance: abi.Instance = null,
    /// Exact 64-bit value published into the guest's pInstance output. Keep
    /// this separate from the host pointer because a loader thunk may wrap a
    /// dispatchable handle before passing it to an extension entry point.
    guest_instance_handle: u64 = 0,
    /// Real VkPhysicalDevice discovered by the guest's vkEnumeratePhysicalDevices.
    physical_device: abi.PhysicalDevice = null,
    /// Real VkDevice created by the guest's vkCreateDevice.
    device: abi.Device = null,
    /// A lost Vulkan device is kept long enough to let the guest destroy its
    /// object graph, but it must never be mistaken for a usable device or
    /// silently downgraded to the synthetic presenter path.
    device_lost: bool = false,
    device_loss_result: abi.Result = abi.SUCCESS,
    /// Exact 64-bit value published into the guest's pDevice output. Keep it
    /// separately from the host pointer so an ABI shim that rewrites a
    /// dispatchable handle can still be recognised as the same logical device.
    guest_device_handle: u64 = 0,
    /// Real VkQueue obtained by the guest's vkGetDeviceQueue.
    graphics_queue: abi.Queue = null,
    compute_queue: abi.Queue = null,
    transfer_queue: abi.Queue = null,
    /// Guest-owned surface and swapchain created on the same real instance
    /// and device. The guest still receives Rosette synthetic handles; these
    /// fields are the driver-side counterparts.
    surface: abi.SurfaceKHR = 0,
    swapchain: abi.SwapchainKHR = 0,
    /// Instance-level function pointer for vkGetInstanceProcAddr.
    get_instance_proc_addr: ?abi.PfnGetInstanceProcAddr = null,
    /// Loader capabilities captured before vkCreateInstance.  The guest
    /// loader is x86 code and its extension-name pointers are not valid host
    /// pointers, so we copy the names into this host-owned table once and use
    /// the table for both negotiation and the guest enumeration response.
    host_instance_extensions: [64]abi.ExtensionProperties = [_]abi.ExtensionProperties{.{
        .extension_name = [_]u8{0} ** abi.MAX_EXTENSION_NAME_SIZE,
        .spec_version = 0,
    }} ** 64,
    host_instance_extension_count: u32 = 0,
    host_instance_extensions_known: bool = false,
    /// The same table for the selected physical device.  MoltenVK reports
    /// well over a hundred device extensions, and the guest asks for the
    /// whole list in one call: a short table makes the second
    /// vkEnumerateDeviceExtensionProperties return VK_INCOMPLETE, which the
    /// guest reads as an outright failure to query the adapter rather than as
    /// a truncated answer.  Size the table for the full host surface.
    host_device_extensions: [MAX_HOST_DEVICE_EXTENSIONS]abi.ExtensionProperties = [_]abi.ExtensionProperties{.{
        .extension_name = [_]u8{0} ** abi.MAX_EXTENSION_NAME_SIZE,
        .spec_version = 0,
    }} ** MAX_HOST_DEVICE_EXTENSIONS,
    host_device_extension_count: u32 = 0,
    host_device_extensions_known: bool = false,
    /// Physical device properties (raw bytes, up to 1024).
    physical_device_properties: [abi.physical_device_properties_bytes]u8 align(8) = [_]u8{0} ** abi.physical_device_properties_bytes,
    physical_device_features: [220]u8 align(4) = [_]u8{0} ** 220,
    feature_chain_supported: [feature_chain_max][feature_chain_node_bytes]u8 align(8) = [_][feature_chain_node_bytes]u8{[_]u8{0} ** feature_chain_node_bytes} ** feature_chain_max,
    feature_chain_sizes: [feature_chain_max]u16 = [_]u16{0} ** feature_chain_max,
    feature_chain_valid: [feature_chain_max]bool = [_]bool{false} ** feature_chain_max,
    /// Physical device memory properties.
    physical_device_memory: abi.PhysicalDeviceMemoryProperties = .{},
    /// Queue family count.
    queue_family_count: u32 = 0,
    /// Queue family properties.
    queue_family_properties: [16]abi.QueueFamilyProperties = [_]abi.QueueFamilyProperties{.{}} ** 16,
    /// Device-level function pointers resolved after device creation.
    fn_ptrs: DeviceFnPtrs = .{},

    // --- Handle mapping tables ---
    memory_map: [MAX_REAL_MEMORY]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_MEMORY,
    buffer_map: [MAX_REAL_BUFFERS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_BUFFERS,
    image_map: [MAX_REAL_IMAGES]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_IMAGES,
    sampler_map: [MAX_REAL_SAMPLERS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_SAMPLERS,
    fence_map: [MAX_REAL_FENCES]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_FENCES,
    semaphore_map: [MAX_REAL_SEMAPHORES]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_SEMAPHORES,
    render_pass_map: [MAX_REAL_RENDER_PASSES]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_RENDER_PASSES,
    framebuffer_map: [MAX_REAL_FRAMEBUFFERS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_FRAMEBUFFERS,
    pipeline_map: [MAX_REAL_PIPELINES]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_PIPELINES,
    shader_module_map: [MAX_REAL_SHADER_MODULES]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_SHADER_MODULES,
    descriptor_set_layout_map: [MAX_REAL_DESCRIPTOR_SET_LAYOUTS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_DESCRIPTOR_SET_LAYOUTS,
    pipeline_layout_map: [MAX_REAL_PIPELINE_LAYOUTS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_PIPELINE_LAYOUTS,
    descriptor_pool_map: [MAX_REAL_DESCRIPTOR_POOLS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_DESCRIPTOR_POOLS,
    descriptor_set_map: [MAX_REAL_DESCRIPTOR_SETS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_DESCRIPTOR_SETS,
    command_pool_map: [MAX_REAL_COMMAND_POOLS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_COMMAND_POOLS,
    command_buffer_map: [MAX_REAL_COMMAND_BUFFERS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_COMMAND_BUFFERS,
    swapchain_map: [MAX_REAL_SWAPCHAINS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_SWAPCHAINS,
    swapchain_records: [MAX_REAL_SWAPCHAINS]SwapchainRecord = [_]SwapchainRecord{.{}} ** MAX_REAL_SWAPCHAINS,
    buffer_view_map: [MAX_REAL_BUFFER_VIEWS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_BUFFER_VIEWS,
    image_view_map: [MAX_REAL_IMAGE_VIEWS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_IMAGE_VIEWS,
    query_pool_map: [MAX_REAL_QUERY_POOLS]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_QUERY_POOLS,
    pipeline_cache_map: [MAX_REAL_PIPELINE_CACHES]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_PIPELINE_CACHES,
    descriptor_update_template_map: [MAX_REAL_DESCRIPTOR_UPDATE_TEMPLATES]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_DESCRIPTOR_UPDATE_TEMPLATES,
    descriptor_update_template_records: [MAX_REAL_DESCRIPTOR_UPDATE_TEMPLATES]DescriptorUpdateTemplateRecord = [_]DescriptorUpdateTemplateRecord{.{}} ** MAX_REAL_DESCRIPTOR_UPDATE_TEMPLATES,
    queue_map: [MAX_REAL_QUEUES]HandleMap = [_]HandleMap{.{}} ** MAX_REAL_QUEUES,

    /// Whether the real instance was successfully created.
    pub fn hasInstance(self: *const RealVulkanState) bool {
        return self.instance != null;
    }

    /// Whether the real device was successfully created.
    pub fn hasDevice(self: *const RealVulkanState) bool {
        return self.device != null;
    }

    pub fn deviceUsable(self: *const RealVulkanState) bool {
        return self.device != null and !self.device_lost;
    }

    /// Memory types the real device actually reports. Zero when the properties
    /// have not been fetched, which the caller must treat as "constrain
    /// nothing" rather than as "one type".
    pub fn memoryTypeCount(self: *const RealVulkanState) u32 {
        return self.physical_device_memory.memory_type_count;
    }

    pub fn realMemory(self: *const RealVulkanState, synthetic: u64) ?abi.DeviceMemory {
        return HandleMap.findReal(&self.memory_map, synthetic);
    }

    pub fn realBuffer(self: *const RealVulkanState, synthetic: u64) ?abi.Buffer {
        return HandleMap.findReal(&self.buffer_map, synthetic);
    }

    pub fn realImage(self: *const RealVulkanState, synthetic: u64) ?abi.Image {
        return HandleMap.findReal(&self.image_map, synthetic);
    }

    pub fn realSampler(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.sampler_map, synthetic);
    }

    pub fn realFence(self: *const RealVulkanState, synthetic: u64) ?abi.Fence {
        return HandleMap.findReal(&self.fence_map, synthetic);
    }

    pub fn realSemaphore(self: *const RealVulkanState, synthetic: u64) ?abi.Semaphore {
        return HandleMap.findReal(&self.semaphore_map, synthetic);
    }

    pub fn realRenderPass(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.render_pass_map, synthetic);
    }

    pub fn realFramebuffer(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.framebuffer_map, synthetic);
    }

    pub fn realPipeline(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.pipeline_map, synthetic);
    }

    pub fn realShaderModule(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.shader_module_map, synthetic);
    }

    pub fn realDescriptorSetLayout(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.descriptor_set_layout_map, synthetic);
    }

    pub fn realPipelineLayout(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.pipeline_layout_map, synthetic);
    }

    pub fn realDescriptorPool(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.descriptor_pool_map, synthetic);
    }

    pub fn realDescriptorSet(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.descriptor_set_map, synthetic);
    }

    pub fn realCommandPool(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.command_pool_map, synthetic);
    }

    pub fn realCommandBuffer(self: *const RealVulkanState, synthetic: u64) ?abi.CommandBuffer {
        const real = HandleMap.findReal(&self.command_buffer_map, synthetic) orelse return null;
        return @as(abi.CommandBuffer, @ptrFromInt(@as(usize, @intCast(real))));
    }

    pub fn realSurface(self: *const RealVulkanState, synthetic: u64) ?abi.SurfaceKHR {
        if (synthetic == 0 or self.surface == 0) return null;
        return if (synthetic == VK_SYNTHETIC_SURFACE) self.surface else null;
    }

    pub fn realSwapchain(self: *const RealVulkanState, synthetic: u64) ?abi.SwapchainKHR {
        return HandleMap.findReal(&self.swapchain_map, synthetic);
    }

    fn swapchainRecord(self: *const RealVulkanState, synthetic: u64) ?*const SwapchainRecord {
        if (synthetic == 0) return null;
        for (&self.swapchain_records) |*record| {
            if (record.synthetic == synthetic) return record;
        }
        return null;
    }

    fn mutableSwapchainRecord(self: *RealVulkanState, synthetic: u64) ?*SwapchainRecord {
        if (synthetic == 0) return null;
        for (&self.swapchain_records) |*record| {
            if (record.synthetic == synthetic) return record;
        }
        return null;
    }

    fn allocateSwapchainRecord(self: *RealVulkanState, synthetic: u64, real: abi.SwapchainKHR) ?*SwapchainRecord {
        for (&self.swapchain_records) |*record| {
            if (record.synthetic == 0) {
                record.* = .{ .synthetic = synthetic, .real = real };
                return record;
            }
        }
        return null;
    }

    fn releaseSwapchainImageHandles(self: *RealVulkanState, record: *const SwapchainRecord) void {
        for (record.image_handles) |image| {
            if (image != 0) HandleMap.remove(&self.image_map, image);
        }
    }

    pub fn realBufferView(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.buffer_view_map, synthetic);
    }

    pub fn realImageView(self: *const RealVulkanState, synthetic: u64) ?u64 {
        return HandleMap.findReal(&self.image_view_map, synthetic);
    }

    pub fn realQueryPool(self: *const RealVulkanState, synthetic: u64) ?abi.QueryPool {
        return HandleMap.findReal(&self.query_pool_map, synthetic);
    }

    pub fn realPipelineCache(self: *const RealVulkanState, synthetic: u64) ?abi.PipelineCache {
        return HandleMap.findReal(&self.pipeline_cache_map, synthetic);
    }

    pub fn realDescriptorUpdateTemplate(self: *const RealVulkanState, synthetic: u64) ?abi.DescriptorUpdateTemplate {
        return HandleMap.findReal(&self.descriptor_update_template_map, synthetic);
    }

    fn descriptorUpdateTemplateIndex(self: *const RealVulkanState, synthetic: u64) ?usize {
        for (self.descriptor_update_template_map, 0..) |entry, index| {
            if (entry.synthetic == synthetic and entry.real != 0) return index;
        }
        return null;
    }

    /// Resolve a guest queue value to the driver queue. Dispatchable queue
    /// handles are pointers, so the normal guest value is already the host
    /// pointer returned by vkGetDeviceQueue. Keep a small explicit map as
    /// well: it covers queues acquired after device creation and prevents a
    /// later submission path from silently choosing graphics for a compute or
    /// transfer queue.
    pub fn realQueue(self: *const RealVulkanState, guest: u64) ?abi.Queue {
        if (guest == 0) return null;
        if (guest == VK_SYNTHETIC_QUEUE) return self.graphics_queue;
        if (HandleMap.findReal(&self.queue_map, guest)) |raw| {
            if (raw != 0) return @as(abi.Queue, @ptrFromInt(@as(usize, @intCast(raw))));
        }
        const candidates = [_]abi.Queue{ self.graphics_queue, self.compute_queue, self.transfer_queue };
        for (candidates) |candidate| {
            if (candidate) |queue| if (@intFromPtr(queue) == guest) return queue;
        }
        return null;
    }

    /// Resolve a vkGetDeviceProcAddr name to the cached function pointer, or
    /// resolve it live if not yet cached.
    pub fn resolveDeviceFn(self: *RealVulkanState, name: [*:0]const u8) ?*const anyopaque {
        if (self.device == null) return null;
        const get = self.get_instance_proc_addr orelse return null;
        return get(@ptrCast(self.device), name);
    }
};

/// What the guest said it was creating. Recorded because a modelled
/// `vkCreateImage` is the only place the runtime ever learns an image's extent
/// and format, and without them a later `vkGetImageMemoryRequirements` cannot
/// answer with a size that matches what the guest will write.
const VulkanResource = struct {
    handle: u64 = 0,
    kind: VulkanResourceKind = .buffer,
    format: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    mip_levels: u32 = 1,
    array_layers: u32 = 1,
    tiling: u32 = 0,
    usage: u32 = 0,
    size_bytes: u64 = 0,
    row_pitch_bytes: u64 = 0,
    memory: u64 = 0,
    memory_offset: u64 = 0,
};

const feature_chain_max = 7;
const feature_chain_node_bytes = 256;

/// A device extension Rosette enables on its own account, beyond whatever the
/// guest negotiated, because the bridge resolves entry points through it.
///
/// The guest's device is negotiated at Vulkan 1.2, so every entry point that
/// was promoted in 1.3 exists on this driver only under its KHR or EXT name
/// and only while the providing extension is enabled. Enabling the extension
/// without its feature would resolve the pointer and leave it illegal to
/// call, so the feature is queried and enabled in the same step — a resolved
/// pointer the bridge may not use is worse than a null one, because null is
/// what its fallbacks test.
const BridgeDeviceCapability = struct {
    extension: []const u8,
    /// sType of the feature structure that has to be enabled with it, or 0
    /// when the extension has no feature structure.
    feature_s_type: u32 = 0,
    /// Byte size of that structure, including the 16-byte sType/pNext header.
    feature_size: u16 = 0,
    /// What the extension buys, for the log.
    provides: []const u8,
};

const bridge_device_capabilities = [_]BridgeDeviceCapability{
    .{
        .extension = "VK_KHR_synchronization2",
        .feature_s_type = abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES,
        .feature_size = @sizeOf(abi.PhysicalDeviceSynchronization2Features),
        .provides = "vkQueueSubmit2KHR, vkCmdPipelineBarrier2KHR",
    },
    .{
        .extension = "VK_KHR_dynamic_rendering",
        .feature_s_type = abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
        .feature_size = @sizeOf(abi.PhysicalDeviceDynamicRenderingFeatures),
        .provides = "vkCmdBeginRenderingKHR, vkCmdEndRenderingKHR",
    },
    .{
        .extension = "VK_EXT_extended_dynamic_state",
        .feature_s_type = abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
        .feature_size = @sizeOf(abi.PhysicalDeviceExtendedDynamicStateFeaturesEXT),
        .provides = "vkCmdSetDepth/StencilTestEnableEXT and friends",
    },
    .{
        .extension = "VK_EXT_extended_dynamic_state2",
        .feature_s_type = abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT,
        .feature_size = @sizeOf(abi.PhysicalDeviceExtendedDynamicState2FeaturesEXT),
        .provides = "vkCmdSetPrimitiveRestartEnableEXT",
    },
    .{
        .extension = "VK_KHR_push_descriptor",
        .provides = "vkCmdPushDescriptorSetKHR",
    },
    // Listed even though MoltenVK does not implement it, so the log says why
    // the conditional-rendering commands stay absent instead of leaving them
    // unexplained beside entry points that were merely un-negotiated.
    .{
        .extension = "VK_EXT_conditional_rendering",
        .feature_s_type = abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_CONDITIONAL_RENDERING_FEATURES_EXT,
        .feature_size = @sizeOf(abi.PhysicalDeviceConditionalRenderingFeaturesEXT),
        .provides = "vkCmdBegin/EndConditionalRenderingEXT",
    },
};

/// Host-owned storage for the capability chain above. Nothing here is ever a
/// guest pointer, so the whole chain can be handed straight to the loader.
const BridgeCapabilityScratch = struct {
    nodes: [bridge_device_capabilities.len][feature_chain_node_bytes]u8 align(8) =
        [_][feature_chain_node_bytes]u8{[_]u8{0} ** feature_chain_node_bytes} ** bridge_device_capabilities.len,
    /// Index into `bridge_device_capabilities` for each admitted node.
    order: [bridge_device_capabilities.len]u8 = [_]u8{0} ** bridge_device_capabilities.len,
    /// Which capabilities were admitted at all, feature-bearing or not.
    admitted: [bridge_device_capabilities.len]bool = [_]bool{false} ** bridge_device_capabilities.len,
    count: usize = 0,
};

/// The guest's Vulkan feature pNext chain contains host pointers only after
/// it has been marshalled. Keep the scratch nodes in host-owned, aligned
/// storage and never pass a guest pointer to the loader.
const FeatureChainScratch = struct {
    nodes: [feature_chain_max][feature_chain_node_bytes]u8 align(8) = [_][feature_chain_node_bytes]u8{[_]u8{0} ** feature_chain_node_bytes} ** feature_chain_max,
    sizes: [feature_chain_max]u16 = [_]u16{0} ** feature_chain_max,
    order: [feature_chain_max]u8 = [_]u8{0} ** feature_chain_max,
    addresses: [feature_chain_max]u64 = [_]u64{0} ** feature_chain_max,
    count: usize = 0,
};

const property_chain_max = 3;

/// The property pNext nodes Xenia asks for are output-only structures.  Keep
/// their host copies separate from the guest nodes just as we do for feature
/// discovery; the loader is then free to write real driver values without
/// ever following an x86 guest address.
const PropertyChainScratch = struct {
    driver: abi.PhysicalDeviceDriverProperties = .{},
    float_controls: abi.PhysicalDeviceFloatControlsProperties = .{},
    memory_budget: abi.PhysicalDeviceMemoryBudgetPropertiesEXT = .{},
    order: [property_chain_max]u8 = [_]u8{0} ** property_chain_max,
    addresses: [property_chain_max]u64 = [_]u64{0} ** property_chain_max,
    count: usize = 0,
};

fn propertyChainKind(s_type: u32) ?u8 {
    return switch (s_type) {
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES => 0,
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES => 1,
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT => 2,
        else => null,
    };
}

fn propertyChainSize(kind: u8) usize {
    return switch (kind) {
        0 => @sizeOf(abi.PhysicalDeviceDriverProperties),
        1 => @sizeOf(abi.PhysicalDeviceFloatControlsProperties),
        2 => @sizeOf(abi.PhysicalDeviceMemoryBudgetPropertiesEXT),
        else => 0,
    };
}

fn propertyChainNode(scratch: *PropertyChainScratch, kind: u8) *anyopaque {
    return switch (kind) {
        0 => @ptrCast(&scratch.driver),
        1 => @ptrCast(&scratch.float_controls),
        2 => @ptrCast(&scratch.memory_budget),
        else => unreachable,
    };
}

fn linkPropertyChain(scratch: *PropertyChainScratch) void {
    for (0..scratch.count) |index| {
        const kind = scratch.order[index];
        const next: ?*anyopaque = if (index + 1 < scratch.count)
            propertyChainNode(scratch, scratch.order[index + 1])
        else
            null;
        switch (kind) {
            0 => scratch.driver.p_next = next,
            1 => scratch.float_controls.p_next = next,
            2 => scratch.memory_budget.p_next = next,
            else => unreachable,
        }
    }
}

fn featureChainKind(s_type: u32) ?usize {
    return switch (s_type) {
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES => 6,
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES => 0,
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES => 1,
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR => 2,
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT => 3,
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DEMOTE_TO_HELPER_INVOCATION_FEATURES => 4,
        abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_NON_SEAMLESS_CUBE_MAP_FEATURES_EXT => 5,
        else => null,
    };
}

fn featureChainSType(kind: usize) u32 {
    return switch (kind) {
        0 => abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        1 => abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        2 => abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR,
        3 => abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT,
        4 => abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DEMOTE_TO_HELPER_INVOCATION_FEATURES,
        5 => abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_NON_SEAMLESS_CUBE_MAP_FEATURES_EXT,
        6 => abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES,
        else => 0,
    };
}

fn featureChainSize(kind: usize) u16 {
    return switch (kind) {
        // Keep these byte counts in lockstep with the Vulkan ABI.  The
        // structures are marshalled as raw bytes because the guest's pNext
        // pointers cannot be passed to the host loader, so omitting the last
        // VkBool32 silently drops a feature at vkCreateDevice time.
        0 => 204, // VkPhysicalDeviceVulkan12Features: 47 bools
        1, 2 => 76, // Vulkan13 and portability-subset: 15 bools
        3 => 28, // fragment-shader interlock: 3 bools
        4, 5, 6 => 20, // one feature bool
        else => 0,
    };
}

fn featureChainBoolCount(kind: usize) usize {
    return switch (kind) {
        0 => 47,
        1, 2 => 15,
        3 => 3,
        4, 5 => 1,
        6 => 1,
        else => 0,
    };
}

fn setFeatureChainHeader(bytes: []u8, s_type: u32, next: ?*anyopaque) void {
    std.mem.writeInt(u32, bytes[0..4], s_type, .little);
    const next_address: u64 = if (next) |pointer| @intFromPtr(pointer) else 0;
    std.mem.writeInt(u64, bytes[8..16], next_address, .little);
}

fn featureChainNext(scratch: *FeatureChainScratch, index: usize) ?*anyopaque {
    if (index + 1 >= scratch.count) return null;
    return @ptrCast(&scratch.nodes[scratch.order[index + 1]]);
}

fn linkBridgeCapabilityChain(scratch: *BridgeCapabilityScratch) void {
    for (0..scratch.count) |slot| {
        const capability = bridge_device_capabilities[scratch.order[slot]];
        const node = scratch.nodes[slot][0..capability.feature_size];
        const next: u64 = if (slot + 1 < scratch.count) @intFromPtr(&scratch.nodes[slot + 1]) else 0;
        std.mem.writeInt(u64, node[8..16], next, .little);
    }
}

/// Put the bridge's own capability nodes in front of the guest's feature
/// chain and return the head. Both halves are host-owned by this point, so
/// the spliced chain can never hand the loader a guest address.
fn spliceBridgeCapabilityChain(scratch: *BridgeCapabilityScratch, guest_p_next: ?*const anyopaque) ?*const anyopaque {
    if (scratch.count == 0) return guest_p_next;
    const last = scratch.count - 1;
    const size = bridge_device_capabilities[scratch.order[last]].feature_size;
    const tail = scratch.nodes[last][0..size];
    std.mem.writeInt(u64, tail[8..16], if (guest_p_next) |pointer| @intFromPtr(pointer) else 0, .little);
    return @ptrCast(&scratch.nodes[0]);
}

fn linkFeatureChain(scratch: *FeatureChainScratch) void {
    for (0..scratch.count) |index| {
        const kind = scratch.order[index];
        setFeatureChainHeader(scratch.nodes[kind][0..scratch.sizes[kind]], featureChainSType(kind), featureChainNext(scratch, index));
    }
}

pub const Forwarder = struct {
    libraries: [MAX_LIBRARIES]Library = [_]Library{.{}} ** MAX_LIBRARIES,
    library_count: usize = 0,
    guest_libraries: [MAX_GUEST_LIBRARIES]GuestLibrary = [_]GuestLibrary{.{}} ** MAX_GUEST_LIBRARIES,
    guest_symbols: [MAX_GUEST_SYMBOLS]GuestSymbol = [_]GuestSymbol{.{}} ** MAX_GUEST_SYMBOLS,
    guest_open_count: u64 = 0,
    guest_close_count: u64 = 0,
    guest_lookup_count: u64 = 0,
    guest_thunk_calls: u64 = 0,
    guest_proc_queries: u64 = 0,
    guest_opaque_calls: u64 = 0,
    next_vulkan_object: u64 = 0xFFFF_F500_0000_0001,
    vulkan_logical_devices_created: u64 = 0,
    vulkan_queues_acquired: u64 = 0,
    vulkan_metal_surfaces_created: u64 = 0,
    vulkan_swapchains_created: u64 = 0,
    vulkan_swapchain_images_enumerated: u64 = 0,
    vulkan_images_acquired: u64 = 0,
    vulkan_queue_submits: u64 = 0,
    vulkan_presents: u64 = 0,
    /// Guest command calls that reached a real command-buffer mapping.  The
    /// older `vulkan_modeled_command_calls` counter remains as total observed
    /// traffic for compatibility with existing diagnostics; this one is the
    /// execution truth used by host-coverage reporting.
    vulkan_real_command_calls: u64 = 0,
    vulkan_real_queue_submits: u64 = 0,
    vulkan_real_presents: u64 = 0,
    vulkan_real_objects_created: u64 = 0,
    vulkan_real_objects_destroyed: u64 = 0,
    vulkan_device_void_calls: u64 = 0,
    vulkan_device_lost_events: u64 = 0,
    vulkan_fence_completions: u64 = 0,
    vulkan_modeled_command_calls: u64 = 0,
    vulkan_surface_capability_queries: u64 = 0,
    vulkan_memory_allocations: u64 = 0,
    vulkan_memory_maps: u64 = 0,
    vulkan_memory_map_reuses: u64 = 0,
    vulkan_shadow_uploads: u64 = 0,
    vulkan_shadow_upload_failures: u64 = 0,
    // ---- Vulkan call trace ring buffer (last N device-level calls) ----
    vulkan_call_trace: [64]VulkanCallTrace = [_]VulkanCallTrace{.{}} ** 64,
    vulkan_call_trace_next: u8 = 0,
    vulkan_call_trace_full: bool = false,
    vulkan_call_count: u64 = 0,
    vulkan_memory_records: [MAX_VULKAN_MEMORY_ALLOCATIONS]VulkanMemoryAllocation =
        [_]VulkanMemoryAllocation{.{}} ** MAX_VULKAN_MEMORY_ALLOCATIONS,
    vulkan_resources: [MAX_VULKAN_RESOURCES]VulkanResource =
        [_]VulkanResource{.{}} ** MAX_VULKAN_RESOURCES,
    vulkan_resource_overflow: u64 = 0,
    vulkan_image_bindings: u64 = 0,
    vulkan_presenter_bind_attempts: u64 = 0,
    vulkan_presenter_bind_failures: u64 = 0,
    vulkan_presenter_off_ui_calls: u64 = 0,
    vulkan_presenter_stage: VulkanPresenterStage = .none,
    native_vulkan_library_token: u64 = 0,
    native_vulkan_instance: ?*anyopaque = null,
    native_vulkan_surface: u64 = 0,
    native_vulkan_instance_attempts: u64 = 0,
    native_vulkan_surface_attempts: u64 = 0,
    // Track last opaque (unforwarded) Vulkan call for crash context.
    last_opaque_vulkan_call: [128]u8 = undefined,
    last_opaque_vulkan_call_len: u16 = 0,
    native_vulkan_failures: u64 = 0,
    native_vulkan_loader_attempts: u64 = 0,
    native_vulkan_loader_failures: u64 = 0,
    gpu_runtime: rosette_gpu.Runtime = .{},
    gpu_handshake_response: rosette_gpu.HandshakeResponse = .{},
    gpu_handshake_updates: u64 = 0,
    gpu_health_fingerprint: u64 = std.math.maxInt(u64),
    // Phase 1: real Vulkan objects for the guest's rendering pipeline.
    // Separate from the native presenter; both coexist.
    real_vulkan: RealVulkanState = .{},
    /// The modelled VK_EXT_debug_utils messenger the guest currently holds,
    /// or zero. Kept so a destroy call can be checked against what was
    /// actually issued.
    debug_messenger_handle: u64 = 0,
    surface_enumeration_bound_reported: bool = false,
    // Rosette's own presentation path, independent of the guest's modelled
    // Vulkan objects. The guest calling vkQueuePresentKHR is a request; this is
    // what actually reaches the display.
    native_presenter: rosette_gpu.NativePresenter = .{},
    native_presenter_attempts: u64 = 0,
    native_presenter_stage_logged: ?rosette_gpu.NativePresenterStage = null,
    // Counts guest-visible Vulkan activity and the Metal fallback. The
    // presenter keeps its own ledger for native driver work; the two are never
    // summed, because they answer different questions.
    frame_provenance: rosette_gpu.FrameProvenance = .{},
    forwarding_contract: rosette_gpu.ForwardingContract = .{},
    // Where a completed guest frame lands on its way to the presenter. Empty
    // until something publishes; `absence()` says which link is missing rather
    // than leaving a reader with "no source".
    frame_inbox: rosette_gpu.FrameInbox = .{},
    frame_source_scans: u64 = 0,
    frame_source_discoveries: u64 = 0,
    /// The console front buffer the guest's own swap packet named, translated
    /// into an address this process can read. Supplied from outside because the
    /// two address-space translations that produce it belong to the process
    /// state, not to dyld.
    ///
    /// This is the only frame source that is the *console's* framebuffer rather
    /// than a Vulkan image the emulator described. When the emulator's own GPU
    /// work does not execute, every VkImage it allocates stays as empty as the
    /// day it was mapped, and this is the one buffer that could still hold a
    /// picture.
    guest_frontbuffer_source: u64 = 0,
    guest_frontbuffer_bytes: u64 = 0,
    guest_frontbuffer_width: u32 = 0,
    guest_frontbuffer_height: u32 = 0,
    guest_frontbuffer_tiled: bool = true,
    guest_frontbuffer_endian: rosette_gpu.xenos_texture.Endian = .@"8in32",
    /// Converted pixels live in guest memory rather than in this struct: a
    /// 4096-square surface is sixty-seven megabytes, and a buffer that large
    /// inline would be paid for by every run whether or not a frame ever
    /// arrives. Allocated once at the first conversion and reused.
    guest_frontbuffer_scratch: u64 = 0,
    guest_frontbuffer_scratch_bytes: u64 = 0,
    guest_frontbuffer_conversions: u64 = 0,
    guest_frontbuffer_conversion_failures: u64 = 0,
    guest_frontbuffer_last_failure: ?rosette_gpu.xenos_texture.Failure = null,
    /// Non-zero once a conversion produced pixels that were not all zero. The
    /// distinction the whole path turns on: a mapped, addressable, entirely
    /// empty front buffer is a GPU that never ran, and presenting it would put
    /// a black window up and label it guest output.
    guest_frontbuffer_nonzero_frames: u64 = 0,
    /// Refreshes Rosette drove because the emulator would not. Attempts and
    /// successes are separate: "we tried and there was nothing to show" and "we
    /// never tried" are the two states this exists to tell apart.
    /// Scratch for translated Vulkan create-info arrays. Held here rather than
    /// on the stack because a create-info's arrays outlive the frame that
    /// copied them — the driver reads them during the call.
    vulkan_scratch: marshal.Scratch = .{},
    /// Structures the marshaller declined to translate. Every one of them is an
    /// object that stayed modelled instead of a driver dereferencing a guest
    /// pointer, so a rising count is the safety gate working rather than a
    /// failure.
    vulkan_marshal_refusals: u64 = 0,
    /// Which Vulkan facts are answered by the driver and which synthetically.
    /// See `lib/gpu/vulkan/tier_consistency.zig`. A migration's dangerous state
    /// is not "modelled" or "real" but both at once on two facts a caller
    /// intersects — each half correct, the combination wrong, and nothing
    /// reporting an error.
    vulkan_tiers: tier_consistency.Ledger = .{},
    /// Non-zero only when a real object creation reached the host driver and
    /// the driver rejected it. A marshalling refusal remains eligible for the
    /// explicit modelled fallback; a driver rejection must be returned to the
    /// guest instead of publishing a handle that cannot ever be submitted.
    real_create_result: abi.Result = abi.SUCCESS,
    scheduled_refresh_attempts: u64 = 0,
    scheduled_refresh_successes: u64 = 0,
    frame_source_absence_logged: ?rosette_gpu.FrameAbsence = null,
    vulkan_swapchain_image_handles: [MAX_SWAPCHAIN_IMAGES]u64 = [_]u64{0} ** MAX_SWAPCHAIN_IMAGES,
    vulkan_swapchain_image_count: u32 = 0,
    /// Optional native pipeline-cache persistence. It is deliberately opt-in:
    /// the guest's cache objects remain authoritative unless the shell sets a
    /// path, and all disk I/O is bounded by the existing Vulkan scratch limit.
    vulkan_pipeline_cache_path: [1024]u8 = [_]u8{0} ** 1024,
    vulkan_pipeline_cache_path_len: u16 = 0,
    vulkan_pipeline_cache_path_checked: bool = false,
    vulkan_pipeline_cache_loads: u64 = 0,
    vulkan_pipeline_cache_saves: u64 = 0,
    considered: u64 = 0,
    forwarded: u64 = 0,
    rejected_not_allowlisted: u64 = 0,
    rejected_library: u64 = 0,
    rejected_symbol: u64 = 0,
    rejected_guest_memory: u64 = 0,
    virtual_sleep_calls: u64 = 0,
    virtual_sleep_nanoseconds: u64 = 0,
    longest_virtual_sleep_nanoseconds: u64 = 0,
    virtual_sleep_repairs: u64 = 0,
    page_size_queries: u64 = 0,
    last_virtual_sleep_decision: guest_sleep.Decision = .{
        .requested_nanoseconds = 0,
        .effective_nanoseconds = 0,
        .kind = .invalid,
        .repair = .none,
    },

    pub fn deinit(self: *Forwarder) void {
        self.destroyNativeVulkanObjects();
        self.gpu_runtime.deinit();
        for (self.libraries[0..self.library_count]) |loaded_library| {
            if (loaded_library.handle) |handle| _ = dlclose(handle);
        }
        for (&self.guest_libraries) |*loaded_library| {
            if (loaded_library.handle) |handle| _ = dlclose(handle);
            loaded_library.* = .{};
        }
        self.* = .{};
    }

    pub fn lookupGuest(self: *Forwarder, library_token: u64, symbol: []const u8) u64 {
        const entry = self.guestLibraryEntry(library_token) orelse return 0;
        if (entry.virtual_vulkan) {
            const token = self.allocateGuestSymbol(library_token, symbol);
            machoCapturePrint(
                "macho-processor: Vulkan guest loader lookup: {s} -> 0x{x} ({s})\n",
                .{ symbol, token, @tagName(guestSymbolKind(symbol)) },
            );
            return token;
        }
        const library = entry.handle orelse return 0;
        var symbol_buffer: [512]u8 = undefined;
        const symbol_z = nulTerminate(&symbol_buffer, symbol) orelse return 0;
        _ = dlsym(library, symbol_z) orelse return 0;
        return self.allocateGuestSymbol(library_token, symbol);
    }

    fn lookupVulkanProcGuest(self: *Forwarder, library_token: u64, symbol: []const u8) u64 {
        if (self.guestLibraryEntry(library_token) == null) return 0;
        self.guest_proc_queries +|= 1;
        const token = self.allocateGuestSymbol(library_token, symbol);
        if (self.guest_proc_queries == 1) {
            machoCapturePrint("macho-processor: BOOTUP MILESTONE: guest entered Vulkan library and queried first function '{s}' — GPU initialization beginning\n", .{symbol});
        }
        machoCapturePrint(
            "macho-processor: Vulkan proc query #{d}: {s} -> 0x{x} ({s})\n",
            .{ self.guest_proc_queries, symbol, token, @tagName(guestSymbolKind(symbol)) },
        );
        return token;
    }

    fn allocateGuestSymbol(self: *Forwarder, library_token: u64, symbol: []const u8) u64 {
        const kind = guestSymbolKind(symbol);
        for (&self.guest_symbols) |*entry| {
            if (entry.token == 0 or entry.library_token != library_token) continue;
            if (entry.name_length != symbol.len) continue;
            if (std.mem.eql(u8, entry.name[0..entry.name_length], symbol)) return entry.token;
        }
        for (&self.guest_symbols, 0..) |*entry, index| {
            if (entry.token != 0) continue;
            const token = GUEST_SYMBOL_THUNK_BASE + @as(u64, @intCast(index)) * 16 + 1;
            const name_length: u8 = @intCast(@min(symbol.len, entry.name.len));
            entry.* = .{ .token = token, .library_token = library_token, .kind = kind, .name_length = name_length };
            @memcpy(entry.name[0..name_length], symbol[0..name_length]);
            entry.name_hash = vulkanNameHash(entry.name[0..name_length]);
            self.guest_lookup_count +|= 1;
            return token;
        }
        return 0;
    }

    pub fn dispatchGuestSymbol(self: *Forwarder, state: anytype, token: u64) bool {
        // Guest symbol tokens are laid out contiguously as
        // GUEST_SYMBOL_THUNK_BASE + index*16 + 1 (see allocateGuestSymbol), so
        // the owning slot is determined arithmetically instead of scanning all
        // MAX_GUEST_SYMBOLS entries on every interpreted instruction.
        if (token < GUEST_SYMBOL_THUNK_BASE) return false;
        const offset = token - GUEST_SYMBOL_THUNK_BASE;
        if (offset == 0 or offset % 16 != 1) return false;
        const index: usize = @intCast((offset - 1) / 16);
        if (index >= MAX_GUEST_SYMBOLS) return false;
        const entry = &self.guest_symbols[index];
        if (entry.token != token) return false;
        if (self.guestLibraryEntry(entry.library_token) == null) return false;
        self.guest_thunk_calls +|= 1;
        entry.calls +|= 1;
        self.frame_provenance.noteGuestVulkanCall();
        switch (entry.kind) {
            .get_instance_proc_addr, .get_device_proc_addr => {
                const symbol = state.guestCString(state.regs.rsi, 512) orelse {
                    state.regs.rax = 0;
                    return true;
                };
                const result = self.lookupVulkanProcGuest(entry.library_token, symbol);
                if (result != 0) state.registerSyntheticThunk(result, 1, symbol);
                state.regs.rax = result;
            },
            .enumerate_instance_extensions => state.regs.rax = self.enumerateInstanceExtensions(state, entry.library_token),
            .enumerate_instance_layers => state.regs.rax = enumerateEmpty(state, state.regs.rdi),
            .enumerate_instance_version => state.regs.rax = writeApiVersion(state, state.regs.rdi),
            .create_instance => blk: {
                machoCapturePrint("macho-processor: BOOTUP MILESTONE: guest invoked vkCreateInstance — Vulkan instance creation beginning\n", .{});
                machoCapturePrint("macho-processor: vkCreateInstance dispatch: pCreateInfo=0x{x} pInstance=0x{x}\n", .{ state.regs.rdi, state.regs.rdx });
                const inst_result = self.ensureRealInstance(state, entry.library_token, state.regs.rdi);
                if (inst_result == 0) {
                    // Write the real instance handle to the guest.
                    if (state.regs.rdx != 0 and state.guestMemory(state.regs.rdx, 8) != null) {
                        state.write64(state.regs.rdx, @intFromPtr(self.real_vulkan.instance.?));
                        self.real_vulkan.guest_instance_handle = state.read64(state.regs.rdx);
                    }
                    state.regs.rax = 0;
                    machoCapturePrint("macho-processor: BOOTUP MILESTONE: vkCreateInstance dispatch complete — real instance ready\n", .{});
                } else {
                    state.regs.rax = @bitCast(@as(i64, inst_result));
                    machoCapturePrint("macho-processor: vkCreateInstance dispatch FAILED: result={d}\n", .{inst_result});
                }
                break :blk;
            },
            .enumerate_physical_devices => blk: {
                const physical_device = physicalDeviceGuestHandle(self.real_vulkan.physical_device);
                state.regs.rax = enumerateHandle(
                    state,
                    state.regs.rsi,
                    state.regs.rdx,
                    physical_device.value,
                    "Vulkan physical device",
                    physical_device.register_opaque,
                );
                break :blk;
            },
            .enumerate_device_extensions => state.regs.rax = if (self.real_vulkan.hasInstance()) self.enumerateRealDeviceExtensions(state) else enumerateDeviceExtensions(state),
            .get_physical_device_features => blk: {
                if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceFeatures(state, state.regs.rsi) else writePhysicalDeviceFeatures(state, state.regs.rsi);
                break :blk;
            },
            .get_physical_device_format_properties => {
                if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceFormatProperties(state, state.regs.rsi, state.regs.rdx) else writeFormatProperties(state, state.regs.rdx);
            },
            .get_physical_device_memory_properties => blk: {
                if (self.real_vulkan.hasInstance()) {
                    self.vulkan_tiers.note(.memory_properties, .real);
                    self.writeRealMemoryProperties(state, state.regs.rsi);
                } else {
                    self.vulkan_tiers.note(.memory_properties, .modelled);
                    writeMemoryProperties(state, state.regs.rsi);
                }
                break :blk;
            },
            .get_physical_device_properties => blk: {
                if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceProperties(state, state.regs.rsi) else writePhysicalDeviceProperties(state, state.regs.rsi);
                break :blk;
            },
            .get_physical_device_queue_families => blk: {
                if (self.real_vulkan.hasInstance()) self.writeRealQueueFamilies(state) else writeQueueFamilies(state);
                break :blk;
            },
            .get_physical_device_features2 => blk: {
                if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceFeatures2(state, state.regs.rsi) else writePhysicalDeviceFeatures2(state, state.regs.rsi);
                break :blk;
            },
            .get_physical_device_memory_properties2 => blk: {
                if (self.real_vulkan.hasInstance()) self.writeRealMemoryProperties2(state, state.regs.rsi) else writeMemoryProperties2(state, state.regs.rsi);
                break :blk;
            },
            .get_physical_device_properties2 => blk: {
                if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceProperties2(state, state.regs.rsi) else writePhysicalDeviceProperties2(state, state.regs.rsi);
                break :blk;
            },
            .create_device => blk: {
                machoCapturePrint("macho-processor: BOOTUP MILESTONE: guest invoked vkCreateDevice — GPU device creation beginning\n", .{});
                machoCapturePrint("macho-processor: vkCreateDevice dispatch: physical_device=0x{x} pCreateInfo=0x{x} pDevice=0x{x}\n", .{ state.regs.rdi, state.regs.rsi, state.regs.rcx });
                const dev_result = self.ensureRealDevice(
                    state,
                    entry.library_token,
                    state.regs.rdi, // physical device
                    state.regs.rsi, // pCreateInfo
                    state.regs.rcx, // pDevice
                );
                state.regs.rax = if (dev_result == 0) 0 else @bitCast(@as(i64, dev_result));
                if (dev_result == 0) {
                    machoCapturePrint("macho-processor: BOOTUP MILESTONE: vkCreateDevice dispatch complete — real device ready\n", .{});
                } else {
                    machoCapturePrint("macho-processor: vkCreateDevice dispatch FAILED: result={d}\n", .{dev_result});
                }
                break :blk;
            },
            .get_device_queue => state.regs.rax = self.writeDeviceQueue(state, state.regs.rcx, "vkGetDeviceQueue"),
            .get_device_queue2 => state.regs.rax = self.writeDeviceQueue(state, state.regs.rdx, "vkGetDeviceQueue2"),
            .get_semaphore_counter_value => state.regs.rax = self.getSemaphoreCounterValue(state),
            .wait_semaphores => state.regs.rax = self.waitSemaphores(state),
            .signal_semaphore => state.regs.rax = self.signalSemaphore(state),
            .create_metal_surface => state.regs.rax = self.createMetalSurface(state, entry.library_token, state.regs.rdi, state.regs.rsi, state.regs.rcx),
            .get_surface_capabilities => {
                self.vulkan_surface_capability_queries +|= 1;
                state.regs.rax = if (self.real_vulkan.surface != 0) self.writeRealSurfaceCapabilities(state, state.regs.rdx) else writeSurfaceCapabilities(state, state.regs.rdx);
                if (self.vulkan_surface_capability_queries == 1 and state.regs.rax == 0) {
                    const State = @typeInfo(@TypeOf(state)).pointer.child;
                    const width = if (@hasDecl(State, "nativeWindowWidth")) state.nativeWindowWidth() else 0;
                    const height = if (@hasDecl(State, "nativeWindowHeight")) state.nativeWindowHeight() else 0;
                    machoCapturePrint(
                        "macho-processor: Vulkan surface capabilities: native_extent={d}x{d} min_extent=1x1 max_extent=16384x16384 image_count=2..3 usage=0x13\n",
                        .{ width, height },
                    );
                }
            },
            .get_surface_formats => state.regs.rax = if (self.real_vulkan.surface != 0) self.enumerateRealSurfaceFormats(state) else enumerateSurfaceFormats(state),
            .get_surface_present_modes => state.regs.rax = if (self.real_vulkan.surface != 0) self.enumerateRealSurfacePresentModes(state) else enumerateSurfacePresentModes(state),
            .get_surface_support => state.regs.rax = if (self.real_vulkan.surface != 0) self.writeRealSurfaceSupport(state) else writeBoolResult(state, state.regs.rcx, true),
            .destroy_surface => {
                self.destroyNativeSurface();
                self.destroyRealSurface();
                state.regs.rax = 0;
            },
            .destroy_instance => {
                self.destroyNativeVulkanObjects();
                state.regs.rax = 0;
            },
            .destroy_device => {
                self.destroyRealDevice();
                state.regs.rax = 0;
            },
            .create_swapchain => state.regs.rax = self.createSwapchain(state, state.regs.rdi, state.regs.rsi, state.regs.rcx),
            .destroy_swapchain => {
                self.destroyRealSwapchain(state.regs.rsi);
                state.regs.rax = 0;
            },
            .get_swapchain_images => state.regs.rax = self.enumerateSwapchainImages(state),
            .acquire_next_image => state.regs.rax = self.acquireNextImage(state, state.regs.r9),
            .queue_submit => state.regs.rax = self.queueSubmit(state),
            .queue_submit2 => state.regs.rax = self.queueSubmit2(state),
            .queue_bind_sparse => state.regs.rax = self.queueBindSparse(state),
            .queue_present => state.regs.rax = self.queuePresent(state),
            .queue_wait_idle => state.regs.rax = self.queueWaitIdle(state),
            .create_pipeline_cache => state.regs.rax = self.createVulkanObject(state, state.regs.rsi, state.regs.rcx, "vkCreatePipelineCache"),
            .create_descriptor_update_template => state.regs.rax = self.createVulkanObject(state, state.regs.rsi, state.regs.rcx, "vkCreateDescriptorUpdateTemplate"),
            .create_device_object => state.regs.rax = self.createVulkanObject(state, state.regs.rsi, state.regs.rcx, entry.name[0..entry.name_length]),
            .bind_image_memory => state.regs.rax = self.bindResourceMemory(state.regs.rsi, state.regs.rdx, state.regs.rcx, .image),
            .bind_buffer_memory => state.regs.rax = self.bindResourceMemory(state.regs.rsi, state.regs.rdx, state.regs.rcx, .buffer),
            .bind_image_memory2 => state.regs.rax = self.bindResourcesMemory2(state, state.regs.rsi, state.regs.rdx, .image),
            .bind_buffer_memory2 => state.regs.rax = self.bindResourcesMemory2(state, state.regs.rsi, state.regs.rdx, .buffer),
            .allocate_command_buffers => state.regs.rax = self.allocateVulkanObjects(state, state.regs.rsi, state.regs.rdx, 28, entry.name[0..entry.name_length]),
            .allocate_descriptor_sets => state.regs.rax = self.allocateVulkanObjects(state, state.regs.rsi, state.regs.rdx, 24, entry.name[0..entry.name_length]),
            .allocate_memory => state.regs.rax = self.allocateVulkanMemory(state, state.regs.rsi, state.regs.rcx),
            .map_memory => state.regs.rax = self.mapVulkanMemory(
                state,
                state.regs.rsi,
                state.regs.rdx,
                state.regs.rcx,
                state.regs.r9,
            ),
            .get_memory_requirements => state.regs.rax = self.writeResourceMemoryRequirements(state, state.regs.rsi, state.regs.rdx),
            .get_memory_requirements2 => state.regs.rax = self.writeResourceMemoryRequirements2(state, state.regs.rsi, state.regs.rdx),
            .get_device_buffer_memory_requirements => state.regs.rax = self.writeDeviceBufferMemoryRequirements(state),
            .get_device_image_memory_requirements => state.regs.rax = self.writeDeviceImageMemoryRequirements(state),
            .get_pipeline_cache_data => state.regs.rax = self.getPipelineCacheData(state),
            .create_graphics_pipelines => state.regs.rax = self.createMultipleVulkanObjects(state, state.regs.rdx, state.regs.r9, entry.name[0..entry.name_length]),
            .begin_command_buffer => state.regs.rax = self.beginCommandBuffer(state),
            .end_command_buffer => state.regs.rax = self.endCommandBuffer(state),
            .reset_command_buffer => state.regs.rax = self.resetCommandBuffer(state),
            .reset_command_pool => state.regs.rax = self.resetCommandPool(state),
            .reset_descriptor_pool => state.regs.rax = self.resetDescriptorPool(state),
            .wait_for_fences => state.regs.rax = self.waitForFences(state),
            .reset_fences => state.regs.rax = self.resetFences(state),
            .get_fence_status => state.regs.rax = self.getFenceStatus(state),
            .get_query_pool_results => state.regs.rax = self.getQueryPoolResults(state),
            .reset_query_pool => state.regs.rax = self.resetQueryPool(state),
            .device_wait_idle => state.regs.rax = self.deviceWaitIdle(state),
            .flush_mapped_memory_ranges => state.regs.rax = self.flushMappedMemoryRanges(state),
            .invalidate_mapped_memory_ranges => state.regs.rax = self.invalidateMappedMemoryRanges(state),
            .unmap_memory => state.regs.rax = self.unmapMemory(state),
            .destroy_device_object => state.regs.rax = self.destroyVulkanObject(state, entry.name[0..entry.name_length]),
            .command => {
                self.forwardVulkanCommand(state, entry.name_hash, entry.name[0..entry.name_length]);
                state.regs.rax = 0;
            },
            .update_descriptor_sets => {
                self.updateDescriptorSets(state);
                state.regs.rax = 0;
            },
            .update_descriptor_set_with_template => {
                self.updateDescriptorSetWithTemplate(state);
                state.regs.rax = 0;
            },
            .device_success => {
                const fn_name = entry.name[0..entry.name_length];
                if (self.vulkan_device_void_calls <= 3 or entry.calls == 1) {
                    machoCapturePrint(
                        "macho-processor: Vulkan device_success: {s} calls={d}\n",
                        .{ fn_name, entry.calls },
                    );
                }
                state.regs.rax = 0;
            },
            .device_void => {
                self.vulkan_device_void_calls +|= 1;
                const fn_name = entry.name[0..entry.name_length];
                // Log presenter-critical void calls at low frequency for diagnostics.
                if (std.mem.eql(u8, fn_name, "vkUpdateDescriptorSets")) {
                    machoCapturePrint(
                        "macho-processor: Vulkan device_void #{d}: {s} calls={d}\n",
                        .{ self.vulkan_device_void_calls, fn_name, entry.calls },
                    );
                }
                state.regs.rax = 0;
            },
            // vkCreateDebugUtilsMessengerEXT(instance, pCreateInfo,
            // pAllocator, pMessenger): the output handle is rcx.  Publishing
            // it matters even though the messenger does nothing — leaving the
            // guest's VkDebugUtilsMessengerEXT untouched while returning
            // VK_SUCCESS is how an uninitialised handle reaches
            // vkDestroyDebugUtilsMessengerEXT at instance teardown.
            .create_debug_messenger => {
                if (state.regs.rcx == 0 or state.guestMemory(state.regs.rcx, 8) == null) {
                    state.regs.rax = vkErrorInitializationFailed();
                } else {
                    state.write64(state.regs.rcx, SYNTHETIC_DEBUG_MESSENGER_HANDLE);
                    self.debug_messenger_handle = SYNTHETIC_DEBUG_MESSENGER_HANDLE;
                    machoCapturePrint(
                        "macho-processor: Vulkan debug utils messenger modelled as a no-op: handle=0x{x}; guest callbacks stay in the guest\n",
                        .{SYNTHETIC_DEBUG_MESSENGER_HANDLE},
                    );
                    state.regs.rax = 0;
                }
            },
            .destroy_debug_messenger => {
                if (state.regs.rsi != 0 and state.regs.rsi != SYNTHETIC_DEBUG_MESSENGER_HANDLE) {
                    machoCapturePrint(
                        "macho-processor: guest destroyed a debug utils messenger the bridge never issued: handle=0x{x}\n",
                        .{state.regs.rsi},
                    );
                }
                if (state.regs.rsi == SYNTHETIC_DEBUG_MESSENGER_HANDLE) self.debug_messenger_handle = 0;
                state.regs.rax = 0;
            },
            .debug_utils_success => state.regs.rax = 0,
            // A non-null lookup remains useful for capability discovery,
            // but calling an untyped ARM64 function through x86 registers
            // is unsafe. Keep it contained until its Vulkan ABI signature
            // has an explicit bridge.
            .@"opaque" => {
                self.guest_opaque_calls +|= 1;
                // Record opaque call for crash context.
                const opaque_name = entry.name[0..entry.name_length];
                const copy_len = @min(opaque_name.len, self.last_opaque_vulkan_call.len);
                @memcpy(self.last_opaque_vulkan_call[0..copy_len], opaque_name[0..copy_len]);
                self.last_opaque_vulkan_call_len = @intCast(copy_len);
                machoCapturePrint(
                    "macho-processor: Vulkan ABI gap: called unmodeled proc {s} (token=0x{x}, call={d}); returning zero\n",
                    .{ opaque_name, entry.token, entry.calls },
                );
                state.regs.rax = 0;
            },
        }
        // Record every device-level call in the trace ring buffer.
        if (entry.kind != .get_instance_proc_addr and entry.kind != .get_device_proc_addr and
            entry.kind != .enumerate_instance_extensions and entry.kind != .enumerate_instance_layers and
            entry.kind != .enumerate_instance_version and entry.kind != .create_instance and
            entry.kind != .enumerate_physical_devices and entry.kind != .enumerate_device_extensions and
            entry.kind != .destroy_instance)
        {
            // VkResult is a signed 32-bit value returned in eax, so the
            // negative codes arrive here zero-extended into rax.  Widening
            // the whole 64-bit register and narrowing it to i32 therefore
            // overflows on every Vulkan error the bridge reports: take the
            // low word and reinterpret it, the way the C ABI defines the
            // return.
            const recorded_result: i32 = @bitCast(@as(u32, @truncate(state.regs.rax)));
            self.recordVulkanCall(state, entry.name[0..entry.name_length], recorded_result, state.regs.rdi, state.regs.rsi);
        }
        return true;
    }

    // -----------------------------------------------------------------------
    // Real physical device property writes — used when a real VkInstance exists.
    // These copy the actual MoltenVK values into guest memory instead of
    // returning synthetic limits (e.g. maxImageDimension2D: 4096) that cause
    // the guest to create resources exceeding the real device's capacity.
    // -----------------------------------------------------------------------

    /// Write the real VkPhysicalDeviceProperties to guest memory at `output`.
    fn writeRealPhysicalDeviceProperties(self: *Forwarder, state: anytype, output: u64) void {
        const bytes = state.guestMemory(output, VK_PHYSICAL_DEVICE_PROPERTIES_SIZE) orelse return;
        const src: []const u8 = @as([*]const u8, @ptrCast(&self.real_vulkan.physical_device_properties))[0..VK_PHYSICAL_DEVICE_PROPERTIES_SIZE];
        @memcpy(bytes[0..@min(bytes.len, src.len)], src[0..@min(bytes.len, src.len)]);
    }

    fn writeRealPhysicalDeviceFormatProperties(self: *Forwarder, state: anytype, format: u64, output: u64) void {
        const bytes = state.guestMemory(output, @sizeOf(abi.FormatProperties)) orelse return;
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse {
            writeFormatProperties(state, output);
            return;
        };
        const address = get_proc(self.real_vulkan.instance orelse return, "vkGetPhysicalDeviceFormatProperties") orelse {
            writeFormatProperties(state, output);
            return;
        };
        const function: abi.PfnGetPhysicalDeviceFormatProperties = @ptrCast(@alignCast(address));
        var properties: abi.FormatProperties = .{};
        function(self.real_vulkan.physical_device orelse return, @intCast(format), &properties);
        @memcpy(bytes, std.mem.asBytes(&properties));
    }

    /// vkEnumerateDeviceExtensionProperties(physicalDevice, pLayerName,
    /// pPropertyCount, pProperties): the layer name is rsi, the count is rdx
    /// and the array is rcx.
    ///
    /// The guest sizes its array from the count this returns on the probe
    /// call and then expects the second call to fill that array and report
    /// VK_SUCCESS.  Answering the probe with the driver's full count and then
    /// truncating the fill is not a partial answer to the guest, it is a
    /// failure: Xenia treats anything other than VK_SUCCESS on the fill as an
    /// unusable adapter and abandons device creation, which surfaces much
    /// later as a null VkDevice inside its descriptor allocator.
    fn enumerateRealDeviceExtensions(self: *Forwarder, state: anytype) u64 {
        if (!self.queryHostDeviceExtensions()) return enumerateDeviceExtensions(state);
        if (state.regs.rsi != 0) return enumerateNoLayerExtensions(state, state.regs.rdx);
        return writeExtensionPropertiesArray(state, state.regs.rdx, state.regs.rcx, self.hostDeviceExtensions());
    }

    fn collectFeatureChain(self: *Forwarder, state: anytype, guest_p_next: u64, scratch: *FeatureChainScratch, copy_guest: bool) bool {
        _ = self;
        scratch.* = .{};
        var node = guest_p_next;
        var traversed: usize = 0;
        while (node != 0) : (traversed += 1) {
            if (traversed >= 16 or state.guestMemoryConst(node, 16) == null) return false;
            const s_type = state.read32(node);
            const next = state.read64(node + 8);
            if (featureChainKind(s_type)) |kind| {
                if (scratch.count >= feature_chain_max) return false;
                var duplicate = false;
                for (scratch.order[0..scratch.count]) |seen| {
                    if (seen == kind) duplicate = true;
                }
                if (!duplicate) {
                    const size = featureChainSize(kind);
                    if (state.guestMemoryConst(node, size) == null) return false;
                    if (copy_guest) {
                        @memcpy(scratch.nodes[kind][0..size], state.guestMemoryConst(node, size).?);
                    } else {
                        @memset(scratch.nodes[kind][0..size], 0);
                        std.mem.writeInt(u32, scratch.nodes[kind][0..4], featureChainSType(kind), .little);
                    }
                    scratch.sizes[kind] = size;
                    scratch.addresses[kind] = node;
                    scratch.order[scratch.count] = @intCast(kind);
                    scratch.count += 1;
                }
            } else {
                machoCapturePrint("macho-processor: Vulkan feature pNext sType={d} is not in the host bridge; leaving it guest-owned\n", .{s_type});
            }
            node = next;
        }
        linkFeatureChain(scratch);
        return true;
    }

    fn queryFeatureChain(self: *Forwarder, scratch: *FeatureChainScratch) bool {
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return false;
        const instance = self.real_vulkan.instance orelse return false;
        const physical_device = self.real_vulkan.physical_device orelse return false;
        const address = get_proc(instance, "vkGetPhysicalDeviceFeatures2") orelse return false;
        const get_features: abi.PfnGetPhysicalDeviceFeatures2 = @ptrCast(@alignCast(address));
        var root: abi.PhysicalDeviceFeatures2 = .{};
        if (scratch.count != 0) root.p_next = @ptrCast(&scratch.nodes[scratch.order[0]]);
        get_features(physical_device, &root);
        @memcpy(&self.real_vulkan.physical_device_features, &root.features);
        for (scratch.order[0..scratch.count]) |kind_value| {
            const kind: usize = kind_value;
            const size = scratch.sizes[kind];
            @memcpy(self.real_vulkan.feature_chain_supported[kind][0..size], scratch.nodes[kind][0..size]);
            setFeatureChainHeader(self.real_vulkan.feature_chain_supported[kind][0..size], featureChainSType(kind), null);
            self.real_vulkan.feature_chain_sizes[kind] = size;
            self.real_vulkan.feature_chain_valid[kind] = true;
        }
        return true;
    }

    fn prepareDeviceFeatureChain(self: *Forwarder, state: anytype, guest_p_next: u64, scratch: *FeatureChainScratch) bool {
        if (guest_p_next == 0) {
            scratch.* = .{};
            return true;
        }
        // Feature discovery normally precedes vkCreateDevice, but Xenia can
        // omit the Features2 query on a fallback path. Query the exact chain
        // requested by the guest before masking its enable bits in that case.
        var discovery: FeatureChainScratch = .{};
        if (!self.collectFeatureChain(state, guest_p_next, &discovery, false)) return false;
        var missing = false;
        for (discovery.order[0..discovery.count]) |kind_value| {
            if (!self.real_vulkan.feature_chain_valid[kind_value]) missing = true;
        }
        if (missing and !self.queryFeatureChain(&discovery)) return false;
        if (!self.collectFeatureChain(state, guest_p_next, scratch, true)) return false;
        for (scratch.order[0..scratch.count]) |kind_value| {
            const kind: usize = kind_value;
            const bool_count = featureChainBoolCount(kind);
            const supported = self.real_vulkan.feature_chain_supported[kind][0..self.real_vulkan.feature_chain_sizes[kind]];
            for (0..bool_count) |index| {
                const offset = 16 + index * 4;
                const requested = std.mem.readInt(u32, scratch.nodes[kind][offset..][0..4], .little);
                const available = if (offset + 4 <= supported.len) std.mem.readInt(u32, supported[offset..][0..4], .little) else 0;
                std.mem.writeInt(u32, scratch.nodes[kind][offset..][0..4], if (requested != 0 and available != 0) 1 else 0, .little);
            }
        }
        linkFeatureChain(scratch);
        return true;
    }

    /// Write the real VkPhysicalDeviceProperties2 (with pNext chain) to guest memory.
    fn writeRealPhysicalDeviceProperties2(self: *Forwarder, state: anytype, output: u64) void {
        const header = state.guestMemory(output, 16) orelse return;
        const next = std.mem.readInt(u64, header[8..16], .little);
        self.writeRealPhysicalDeviceProperties(state, output + 16);
        if (next == 0) return;

        var scratch: PropertyChainScratch = .{};
        var node = next;
        var traversed: usize = 0;
        while (node != 0 and traversed < 16) : (traversed += 1) {
            if (state.guestMemoryConst(node, 16) == null) return;
            const s_type = state.read32(node);
            if (propertyChainKind(s_type)) |kind| {
                var duplicate = false;
                for (scratch.order[0..scratch.count]) |seen| {
                    if (seen == kind) duplicate = true;
                }
                if (!duplicate and scratch.count < property_chain_max) {
                    switch (kind) {
                        0 => scratch.driver = .{},
                        1 => scratch.float_controls = .{},
                        2 => scratch.memory_budget = .{},
                        else => unreachable,
                    }
                    scratch.order[scratch.count] = kind;
                    scratch.addresses[scratch.count] = node;
                    scratch.count += 1;
                }
            } else {
                machoCapturePrint(
                    "macho-processor: vkGetPhysicalDeviceProperties2: unsupported pNext sType={d}; leaving node guest-owned\n",
                    .{s_type},
                );
            }
            node = state.read64(node + 8);
        }
        if (node != 0 or scratch.count == 0) {
            if (node != 0) machoCapturePrint("macho-processor: vkGetPhysicalDeviceProperties2: pNext chain exceeds bounded depth\n", .{});
            if (scratch.count == 0) {
                writePhysicalDevicePropertiesPNext(state, next);
                return;
            }
        }

        scratch.driver.s_type = abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
        scratch.float_controls.s_type = abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES;
        scratch.memory_budget.s_type = abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT;
        linkPropertyChain(&scratch);

        const get_proc = self.real_vulkan.get_instance_proc_addr orelse {
            writePhysicalDevicePropertiesPNext(state, next);
            return;
        };
        const address = get_proc(self.real_vulkan.instance orelse return, "vkGetPhysicalDeviceProperties2") orelse {
            writePhysicalDevicePropertiesPNext(state, next);
            return;
        };
        const get_properties: abi.PfnGetPhysicalDeviceProperties2 = @ptrCast(@alignCast(address));
        var root: abi.PhysicalDeviceProperties2 = .{};
        root.p_next = propertyChainNode(&scratch, scratch.order[0]);
        get_properties(self.real_vulkan.physical_device orelse return, &root);

        for (scratch.order[0..scratch.count], 0..) |kind, index| {
            const destination_address = scratch.addresses[index];
            const size = propertyChainSize(kind);
            const destination = state.guestMemory(destination_address + 16, size - 16) orelse continue;
            const source: []const u8 = switch (kind) {
                0 => std.mem.asBytes(&scratch.driver),
                1 => std.mem.asBytes(&scratch.float_controls),
                2 => std.mem.asBytes(&scratch.memory_budget),
                else => unreachable,
            };
            @memcpy(destination, source[16..size]);
        }
    }

    /// Write real VkPhysicalDeviceFeatures to guest memory.
    fn writeRealPhysicalDeviceFeatures(self: *Forwarder, state: anytype, output: u64) void {
        const bytes = state.guestMemory(output, self.real_vulkan.physical_device_features.len) orelse return;
        @memcpy(bytes, &self.real_vulkan.physical_device_features);
    }

    /// Write the real VkPhysicalDeviceFeatures2 to guest memory.
    fn writeRealPhysicalDeviceFeatures2(self: *Forwarder, state: anytype, output: u64) void {
        const core = state.guestMemory(output + 16, self.real_vulkan.physical_device_features.len) orelse return;
        @memcpy(core, &self.real_vulkan.physical_device_features);
        if (state.guestMemoryConst(output, 16) == null) return;
        const guest_p_next = state.read64(output + 8);
        if (guest_p_next == 0) return;
        var scratch: FeatureChainScratch = .{};
        if (!self.collectFeatureChain(state, guest_p_next, &scratch, false)) return;
        if (!self.queryFeatureChain(&scratch)) return;
        for (scratch.order[0..scratch.count]) |kind_value| {
            const kind: usize = kind_value;
            const size = self.real_vulkan.feature_chain_sizes[kind];
            if (size <= 16) continue;
            const destination = state.guestMemory(scratch.addresses[kind] + 16, @as(u64, size) - 16) orelse continue;
            @memcpy(destination, self.real_vulkan.feature_chain_supported[kind][16..size]);
        }
    }

    /// Write the real VkPhysicalDeviceMemoryProperties to guest memory.
    fn writeRealMemoryProperties(self: *Forwarder, state: anytype, output: u64) void {
        const bytes = state.guestMemory(output, 520) orelse return;
        const src: []const u8 = @as([*]const u8, @ptrCast(&self.real_vulkan.physical_device_memory))[0..520];
        @memcpy(bytes[0..@min(bytes.len, src.len)], src[0..@min(bytes.len, src.len)]);
    }

    /// Write the real VkPhysicalDeviceMemoryProperties2 to guest memory.
    fn writeRealMemoryProperties2(self: *Forwarder, state: anytype, output: u64) void {
        self.writeRealMemoryProperties(state, output + 16);
        const header = state.guestMemoryConst(output, 16) orelse return;
        const next = std.mem.readInt(u64, header[8..16], .little);
        if (next == 0) return;

        // Memory-budget is the one useful memory-properties extension that is
        // both output-only and easy to preserve without exposing guest
        // pointers to the loader.  Unknown nodes remain guest-owned and are
        // left untouched; the core properties above are still valid.
        if (state.guestMemoryConst(next, @sizeOf(abi.PhysicalDeviceMemoryBudgetPropertiesEXT)) == null or
            state.read32(next) != abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT or
            state.read64(next + 8) != 0)
        {
            machoCapturePrint(
                "macho-processor: vkGetPhysicalDeviceMemoryProperties2: unsupported pNext chain at 0x{x}; core properties copied\n",
                .{next},
            );
            return;
        }
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return;
        const address = get_proc(self.real_vulkan.instance orelse return, "vkGetPhysicalDeviceMemoryProperties2") orelse return;
        const get_properties: abi.PfnGetPhysicalDeviceMemoryProperties2 = @ptrCast(@alignCast(address));
        var budget: abi.PhysicalDeviceMemoryBudgetPropertiesEXT = .{};
        var root: abi.PhysicalDeviceMemoryProperties2 = .{
            .p_next = @ptrCast(&budget),
            .memory_properties = self.real_vulkan.physical_device_memory,
        };
        budget.p_next = null;
        get_properties(self.real_vulkan.physical_device orelse return, &root);
        if (state.guestMemory(next + 16, @sizeOf(abi.PhysicalDeviceMemoryBudgetPropertiesEXT) - 16)) |destination| {
            const source = std.mem.asBytes(&budget);
            @memcpy(destination, source[16..]);
        }
    }

    /// Write the real queue family properties to guest memory.
    fn writeRealQueueFamilies(self: *Forwarder, state: anytype) void {
        const count_address = state.regs.rsi;
        if (state.guestMemory(count_address, 4) == null) return;
        if (state.regs.rdx == 0) {
            state.write32(count_address, self.real_vulkan.queue_family_count);
            return;
        }
        const requested = state.read32(count_address);
        if (requested == 0) return;
        const actual = @min(requested, self.real_vulkan.queue_family_count);
        const bytes_needed = @as(u64, actual) * @sizeOf(abi.QueueFamilyProperties);
        const bytes = state.guestMemory(state.regs.rdx, bytes_needed) orelse return;
        const src: []const u8 = @ptrCast(self.real_vulkan.queue_family_properties[0..actual]);
        @memcpy(bytes[0..@min(bytes.len, src.len)], src[0..@min(bytes.len, src.len)]);
        state.write32(count_address, actual);
    }

    // -----------------------------------------------------------------------
    // End real property writes
    // -----------------------------------------------------------------------

    fn guestStackArg(state: anytype, index: u64) u64 {
        return state.read64(state.regs.rsp + 8 + index * 8);
    }

    fn guestFloatArgument(state: anytype, index: usize) u32 {
        const State = @typeInfo(@TypeOf(state)).pointer.child;
        if (@hasField(State, "xmm") and index < state.xmm.len) return std.mem.readInt(u32, state.xmm[index][0..4], .little);
        // A few synthetic unit-test states model only GPRs. The fallback keeps
        // those dispatch tests deterministic; real SysV x86-64 calls always
        // arrive through XMM0..XMMn for scalar float arguments.
        return switch (index) {
            0 => @truncate(state.regs.rsi),
            1 => @truncate(state.regs.rdx),
            else => @truncate(state.regs.rcx),
        };
    }

    fn copyGuestStructs(comptime T: type, state: anytype, address: u64, count: u64, destination: []T) bool {
        if (count > destination.len) return false;
        const bytes_count = std.math.mul(u64, count, @sizeOf(T)) catch return false;
        if (count == 0) return true;
        const source = state.guestMemoryConst(address, bytes_count) orelse return false;
        @memcpy(std.mem.sliceAsBytes(destination[0..@as(usize, @intCast(count))]), source);
        return true;
    }

    fn copyGuestBytes(state: anytype, address: u64, count: u64, destination: []u8) bool {
        if (count > destination.len) return false;
        if (count == 0) return true;
        const source = state.guestMemoryConst(address, count) orelse return false;
        @memcpy(destination[0..@as(usize, @intCast(count))], source);
        return true;
    }

    fn copyGuestHandleArray(
        self: *Forwarder,
        state: anytype,
        address: u64,
        count: u64,
        destination: []u64,
        kind: enum { buffer, image, pipeline, descriptor_set, command_buffer },
    ) bool {
        if (count > destination.len) return false;
        if (count != 0 and state.guestMemoryConst(address, count * 8) == null) return false;
        for (0..@as(usize, @intCast(count))) |index| {
            const synthetic = state.read64(address + @as(u64, @intCast(index)) * 8);
            destination[index] = switch (kind) {
                .buffer => self.real_vulkan.realBuffer(synthetic) orelse return false,
                .image => self.real_vulkan.realImage(synthetic) orelse return false,
                .pipeline => self.real_vulkan.realPipeline(synthetic) orelse return false,
                .descriptor_set => self.real_vulkan.realDescriptorSet(synthetic) orelse return false,
                .command_buffer => @intFromPtr(self.real_vulkan.realCommandBuffer(synthetic) orelse return false),
            };
        }
        return true;
    }

    fn copyGuestImageBarriers(self: *Forwarder, state: anytype, address: u64, count: u64, destination: []abi.ImageMemoryBarrier) bool {
        if (!copyGuestStructs(abi.ImageMemoryBarrier, state, address, count, destination)) return false;
        for (destination[0..@as(usize, @intCast(count))]) |*barrier| {
            if (barrier.p_next != null) return false;
            const real_image = self.real_vulkan.realImage(barrier.image) orelse return false;
            barrier.image = real_image;
            barrier.p_next = null;
        }
        return true;
    }

    fn forwardVulkanCommand(self: *Forwarder, state: anytype, name_hash: u64, name: []const u8) void {
        self.vulkan_device_void_calls +|= 1;
        self.vulkan_modeled_command_calls +|= 1;
        if (self.real_vulkan.device_lost) return;
        const command_buffer = self.real_vulkan.realCommandBuffer(state.regs.rdi) orelse {
            if (self.vulkan_modeled_command_calls <= 8) machoCapturePrint(
                "macho-processor: Vulkan command not forwarded: {s} command_buffer=0x{x} has no real mapping\n",
                .{ name, state.regs.rdi },
            );
            return;
        };
        self.vulkan_real_command_calls +|= 1;
        if (self.vulkan_modeled_command_calls == 1) machoCapturePrint(
            "macho-processor: Vulkan forwarding boundary: first real command={s} command_buffer=0x{x}\n",
            .{ name, state.regs.rdi },
        );

        if ((name_hash == vulkanNameHash("vkCmdBindPipeline") and std.mem.eql(u8, name, "vkCmdBindPipeline"))) {
            const pipeline = self.real_vulkan.realPipeline(state.regs.rdx) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_bind_pipeline) |function| function(command_buffer, @intCast(state.regs.rsi), pipeline);
        } else if ((name_hash == vulkanNameHash("vkCmdExecuteCommands") and std.mem.eql(u8, name, "vkCmdExecuteCommands"))) {
            const count = state.regs.rsi;
            var secondary: [64]abi.CommandBuffer = [_]abi.CommandBuffer{null} ** 64;
            if (count > secondary.len or (count != 0 and state.guestMemoryConst(state.regs.rdx, count * 8) == null)) return;
            for (0..@as(usize, @intCast(count))) |index| {
                const synthetic = state.read64(state.regs.rdx + @as(u64, @intCast(index)) * 8);
                secondary[index] = self.real_vulkan.realCommandBuffer(synthetic) orelse return;
            }
            if (self.real_vulkan.fn_ptrs.cmd_execute_commands) |function| {
                function(command_buffer, @intCast(count), &secondary);
            }
        } else if ((name_hash == vulkanNameHash("vkCmdBindVertexBuffers") and std.mem.eql(u8, name, "vkCmdBindVertexBuffers"))) {
            const count = state.regs.rdx;
            var buffers: [32]abi.Buffer = undefined;
            var offsets: [32]u64 = undefined;
            if (count > buffers.len or !copyGuestHandleArray(self, state, state.regs.rcx, count, @ptrCast(&buffers), .buffer)) return;
            if (!copyGuestStructs(u64, state, state.regs.r8, count, &offsets)) return;
            if (self.real_vulkan.fn_ptrs.cmd_bind_vertex_buffers) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(count), &buffers, &offsets);
        } else if ((name_hash == vulkanNameHash("vkCmdBindIndexBuffer") and std.mem.eql(u8, name, "vkCmdBindIndexBuffer"))) {
            const buffer = self.real_vulkan.realBuffer(state.regs.rsi) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_bind_index_buffer) |function| function(command_buffer, buffer, state.regs.rdx, @intCast(state.regs.rcx));
        } else if ((name_hash == vulkanNameHash("vkCmdBindDescriptorSets") and std.mem.eql(u8, name, "vkCmdBindDescriptorSets"))) {
            const set_count = state.regs.r8;
            const dynamic_count = guestStackArg(state, 0);
            var sets: [32]u64 = undefined;
            var dynamic_offsets: [64]u32 = undefined;
            const layout = self.real_vulkan.realPipelineLayout(state.regs.rdx) orelse return;
            if (!copyGuestHandleArray(self, state, state.regs.r9, set_count, &sets, .descriptor_set)) return;
            if (!copyGuestStructs(u32, state, guestStackArg(state, 1), dynamic_count, &dynamic_offsets)) return;
            if (self.real_vulkan.fn_ptrs.cmd_bind_descriptor_sets) |function| function(
                command_buffer,
                @intCast(state.regs.rsi),
                layout,
                @intCast(state.regs.rcx),
                @intCast(set_count),
                &sets,
                @intCast(dynamic_count),
                if (dynamic_count == 0) null else &dynamic_offsets,
            );
        } else if ((name_hash == vulkanNameHash("vkCmdPushDescriptorSetKHR") and std.mem.eql(u8, name, "vkCmdPushDescriptorSetKHR"))) {
            self.forwardPushDescriptorSet(state, command_buffer);
        } else if ((name_hash == vulkanNameHash("vkCmdDraw") and std.mem.eql(u8, name, "vkCmdDraw"))) {
            if (self.real_vulkan.fn_ptrs.cmd_draw) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(state.regs.rdx), @intCast(state.regs.rcx), @intCast(state.regs.r8));
        } else if ((name_hash == vulkanNameHash("vkCmdDrawIndexed") and std.mem.eql(u8, name, "vkCmdDrawIndexed"))) {
            const vertex_offset: i32 = @bitCast(@as(u32, @truncate(state.regs.r8)));
            if (self.real_vulkan.fn_ptrs.cmd_draw_indexed) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(state.regs.rdx), @intCast(state.regs.rcx), vertex_offset, @intCast(state.regs.r9));
        } else if ((name_hash == vulkanNameHash("vkCmdDrawIndirect") and std.mem.eql(u8, name, "vkCmdDrawIndirect"))) {
            const buffer = self.real_vulkan.realBuffer(state.regs.rsi) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_draw_indirect) |function| function(command_buffer, buffer, state.regs.rdx, @intCast(state.regs.rcx), @intCast(state.regs.r8));
        } else if ((name_hash == vulkanNameHash("vkCmdDrawIndexedIndirect") and std.mem.eql(u8, name, "vkCmdDrawIndexedIndirect"))) {
            const buffer = self.real_vulkan.realBuffer(state.regs.rsi) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_draw_indexed_indirect) |function| function(command_buffer, buffer, state.regs.rdx, @intCast(state.regs.rcx), @intCast(state.regs.r8));
        } else if ((name_hash == vulkanNameHash("vkCmdDrawIndirectCount") and std.mem.eql(u8, name, "vkCmdDrawIndirectCount")) or (name_hash == vulkanNameHash("vkCmdDrawIndexedIndirectCount") and std.mem.eql(u8, name, "vkCmdDrawIndexedIndirectCount"))) {
            const buffer = self.real_vulkan.realBuffer(state.regs.rsi) orelse return;
            const count_buffer = self.real_vulkan.realBuffer(state.regs.rcx) orelse return;
            const max_draw_count = guestStackArg(state, 0);
            const stride = guestStackArg(state, 1);
            if ((name_hash == vulkanNameHash("vkCmdDrawIndirectCount") and std.mem.eql(u8, name, "vkCmdDrawIndirectCount"))) {
                if (self.real_vulkan.fn_ptrs.cmd_draw_indirect_count) |function| function(command_buffer, buffer, state.regs.rdx, count_buffer, state.regs.r8, @intCast(max_draw_count), @intCast(stride));
            } else if (self.real_vulkan.fn_ptrs.cmd_draw_indexed_indirect_count) |function| {
                function(command_buffer, buffer, state.regs.rdx, count_buffer, state.regs.r8, @intCast(max_draw_count), @intCast(stride));
            }
        } else if ((name_hash == vulkanNameHash("vkCmdDispatch") and std.mem.eql(u8, name, "vkCmdDispatch"))) {
            if (self.real_vulkan.fn_ptrs.cmd_dispatch) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(state.regs.rdx), @intCast(state.regs.rcx));
        } else if ((name_hash == vulkanNameHash("vkCmdDispatchIndirect") and std.mem.eql(u8, name, "vkCmdDispatchIndirect"))) {
            const buffer = self.real_vulkan.realBuffer(state.regs.rsi) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_dispatch_indirect) |function| function(command_buffer, buffer, state.regs.rdx);
        } else if ((name_hash == vulkanNameHash("vkCmdDispatchBase") and std.mem.eql(u8, name, "vkCmdDispatchBase"))) {
            if (self.real_vulkan.fn_ptrs.cmd_dispatch_base) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(state.regs.rdx), @intCast(state.regs.rcx), @intCast(state.regs.r8), @intCast(state.regs.r9), @intCast(guestStackArg(state, 0)));
        } else if ((name_hash == vulkanNameHash("vkCmdSetViewport") and std.mem.eql(u8, name, "vkCmdSetViewport"))) {
            var viewports: [16]abi.Viewport = undefined;
            if (!copyGuestStructs(abi.Viewport, state, state.regs.rcx, state.regs.rdx, &viewports)) return;
            if (self.real_vulkan.fn_ptrs.cmd_set_viewport) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(state.regs.rdx), &viewports);
        } else if ((name_hash == vulkanNameHash("vkCmdSetScissor") and std.mem.eql(u8, name, "vkCmdSetScissor"))) {
            var scissors: [16]abi.Rect2D = undefined;
            if (!copyGuestStructs(abi.Rect2D, state, state.regs.rcx, state.regs.rdx, &scissors)) return;
            if (self.real_vulkan.fn_ptrs.cmd_set_scissor) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(state.regs.rdx), &scissors);
        } else if ((name_hash == vulkanNameHash("vkCmdSetBlendConstants") and std.mem.eql(u8, name, "vkCmdSetBlendConstants"))) {
            var constants: [4]f32 = undefined;
            if (!copyGuestStructs(f32, state, state.regs.rsi, 4, &constants)) return;
            if (self.real_vulkan.fn_ptrs.cmd_set_blend_constants) |function| function(command_buffer, &constants);
        } else if ((name_hash == vulkanNameHash("vkCmdSetDepthBias") and std.mem.eql(u8, name, "vkCmdSetDepthBias"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_depth_bias) |function| function(
                command_buffer,
                @bitCast(guestFloatArgument(state, 0)),
                @bitCast(guestFloatArgument(state, 1)),
                @bitCast(guestFloatArgument(state, 2)),
            );
        } else if ((name_hash == vulkanNameHash("vkCmdSetDepthBounds") and std.mem.eql(u8, name, "vkCmdSetDepthBounds"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_depth_bounds) |function| function(command_buffer, @bitCast(guestFloatArgument(state, 0)), @bitCast(guestFloatArgument(state, 1)));
        } else if ((name_hash == vulkanNameHash("vkCmdSetDepthTestEnable") and std.mem.eql(u8, name, "vkCmdSetDepthTestEnable"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_depth_test_enable) |function| function(command_buffer, @intCast(state.regs.rsi));
        } else if ((name_hash == vulkanNameHash("vkCmdSetDepthWriteEnable") and std.mem.eql(u8, name, "vkCmdSetDepthWriteEnable"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_depth_write_enable) |function| function(command_buffer, @intCast(state.regs.rsi));
        } else if ((name_hash == vulkanNameHash("vkCmdSetDepthCompareOp") and std.mem.eql(u8, name, "vkCmdSetDepthCompareOp"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_depth_compare_op) |function| function(command_buffer, @intCast(state.regs.rsi));
        } else if ((name_hash == vulkanNameHash("vkCmdSetStencilTestEnable") and std.mem.eql(u8, name, "vkCmdSetStencilTestEnable"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_stencil_test_enable) |function| function(command_buffer, @intCast(state.regs.rsi));
        } else if ((name_hash == vulkanNameHash("vkCmdSetStencilOp") and std.mem.eql(u8, name, "vkCmdSetStencilOp"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_stencil_op) |function| function(
                command_buffer,
                @intCast(state.regs.rsi),
                @intCast(state.regs.rdx),
                @intCast(state.regs.rcx),
                @intCast(state.regs.r8),
                @intCast(state.regs.r9),
            );
        } else if ((name_hash == vulkanNameHash("vkCmdSetPrimitiveRestartEnable") and std.mem.eql(u8, name, "vkCmdSetPrimitiveRestartEnable"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_primitive_restart_enable) |function| function(command_buffer, @intCast(state.regs.rsi));
        } else if ((name_hash == vulkanNameHash("vkCmdSetStencilCompareMask") and std.mem.eql(u8, name, "vkCmdSetStencilCompareMask"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_stencil_compare_mask) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(state.regs.rdx));
        } else if ((name_hash == vulkanNameHash("vkCmdSetStencilWriteMask") and std.mem.eql(u8, name, "vkCmdSetStencilWriteMask"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_stencil_write_mask) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(state.regs.rdx));
        } else if ((name_hash == vulkanNameHash("vkCmdSetStencilReference") and std.mem.eql(u8, name, "vkCmdSetStencilReference"))) {
            if (self.real_vulkan.fn_ptrs.cmd_set_stencil_reference) |function| function(command_buffer, @intCast(state.regs.rsi), @intCast(state.regs.rdx));
        } else if ((name_hash == vulkanNameHash("vkCmdPushConstants") and std.mem.eql(u8, name, "vkCmdPushConstants"))) {
            const size = state.regs.r8;
            var bytes: [256]u8 = undefined;
            if (!copyGuestBytes(state, state.regs.r9, size, &bytes)) return;
            const layout = self.real_vulkan.realPipelineLayout(state.regs.rsi) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_push_constants) |function| function(command_buffer, layout, @intCast(state.regs.rdx), @intCast(state.regs.rcx), @intCast(size), if (size == 0) null else &bytes);
        } else if ((name_hash == vulkanNameHash("vkCmdBeginConditionalRenderingEXT") and std.mem.eql(u8, name, "vkCmdBeginConditionalRenderingEXT"))) {
            if (self.real_vulkan.fn_ptrs.cmd_begin_conditional_rendering) |function| {
                var info: abi.ConditionalRenderingBeginInfoEXT = undefined;
                if (!copyGuestValue(abi.ConditionalRenderingBeginInfoEXT, state, state.regs.rsi, &info) or info.p_next != null) return;
                info.buffer = self.real_vulkan.realBuffer(info.buffer) orelse return;
                info.p_next = null;
                function(command_buffer, &info);
            }
        } else if ((name_hash == vulkanNameHash("vkCmdEndConditionalRenderingEXT") and std.mem.eql(u8, name, "vkCmdEndConditionalRenderingEXT"))) {
            if (self.real_vulkan.fn_ptrs.cmd_end_conditional_rendering) |function| function(command_buffer);
        } else if ((name_hash == vulkanNameHash("vkCmdBeginRendering") and std.mem.eql(u8, name, "vkCmdBeginRendering")) or (name_hash == vulkanNameHash("vkCmdBeginRenderingKHR") and std.mem.eql(u8, name, "vkCmdBeginRenderingKHR"))) {
            if (self.real_vulkan.fn_ptrs.cmd_begin_rendering) |function| {
                var info: abi.RenderingInfo = undefined;
                if (!copyGuestValue(abi.RenderingInfo, state, state.regs.rsi, &info) or info.p_next != null) return;
                if (info.color_attachment_count > 8) return;
                var colors: [8]abi.RenderingAttachmentInfo = undefined;
                const colors_address = if (info.color_attachments) |pointer| @intFromPtr(pointer) else 0;
                if (!copyGuestStructs(abi.RenderingAttachmentInfo, state, colors_address, info.color_attachment_count, &colors)) return;
                for (colors[0..@as(usize, @intCast(info.color_attachment_count))]) |*attachment| {
                    if (attachment.p_next != null) return;
                    if (attachment.image_view != 0) attachment.image_view = self.real_vulkan.realImageView(attachment.image_view) orelse return;
                    if (attachment.resolve_image_view != 0) attachment.resolve_image_view = self.real_vulkan.realImageView(attachment.resolve_image_view) orelse return;
                    attachment.p_next = null;
                }
                info.color_attachments = if (info.color_attachment_count == 0) null else &colors;
                var depth: abi.RenderingAttachmentInfo = undefined;
                var stencil: abi.RenderingAttachmentInfo = undefined;
                if (info.depth_attachment) |pointer| {
                    if (!copyGuestValue(abi.RenderingAttachmentInfo, state, @intFromPtr(pointer), &depth) or depth.p_next != null) return;
                    if (depth.image_view != 0) depth.image_view = self.real_vulkan.realImageView(depth.image_view) orelse return;
                    if (depth.resolve_image_view != 0) depth.resolve_image_view = self.real_vulkan.realImageView(depth.resolve_image_view) orelse return;
                    depth.p_next = null;
                    info.depth_attachment = &depth;
                }
                if (info.stencil_attachment) |pointer| {
                    if (!copyGuestValue(abi.RenderingAttachmentInfo, state, @intFromPtr(pointer), &stencil) or stencil.p_next != null) return;
                    if (stencil.image_view != 0) stencil.image_view = self.real_vulkan.realImageView(stencil.image_view) orelse return;
                    if (stencil.resolve_image_view != 0) stencil.resolve_image_view = self.real_vulkan.realImageView(stencil.resolve_image_view) orelse return;
                    stencil.p_next = null;
                    info.stencil_attachment = &stencil;
                }
                info.p_next = null;
                function(command_buffer, &info);
            }
        } else if ((name_hash == vulkanNameHash("vkCmdEndRendering") and std.mem.eql(u8, name, "vkCmdEndRendering")) or (name_hash == vulkanNameHash("vkCmdEndRenderingKHR") and std.mem.eql(u8, name, "vkCmdEndRenderingKHR"))) {
            if (self.real_vulkan.fn_ptrs.cmd_end_rendering) |function| function(command_buffer);
        } else if ((name_hash == vulkanNameHash("vkCmdBeginRenderPass") and std.mem.eql(u8, name, "vkCmdBeginRenderPass"))) {
            const guest = state.guestMemoryConst(state.regs.rsi, @sizeOf(abi.RenderPassBeginInfo)) orelse return;
            var begin: abi.RenderPassBeginInfo = undefined;
            @memcpy(std.mem.asBytes(&begin), guest);
            if (begin.p_next != null) return;
            begin.p_next = null;
            begin.render_pass = self.real_vulkan.realRenderPass(begin.render_pass) orelse return;
            begin.framebuffer = self.real_vulkan.realFramebuffer(begin.framebuffer) orelse return;
            var clears: [32]abi.ClearValue = undefined;
            const clear_address = if (begin.clear_values) |pointer| @intFromPtr(pointer) else 0;
            if (begin.clear_value_count != 0 and clear_address == 0) return;
            if (!copyGuestStructs(abi.ClearValue, state, clear_address, begin.clear_value_count, &clears)) return;
            begin.clear_values = if (begin.clear_value_count == 0) null else &clears;
            if (self.real_vulkan.fn_ptrs.cmd_begin_render_pass) |function| function(command_buffer, &begin, @intCast(state.regs.rdx));
        } else if ((name_hash == vulkanNameHash("vkCmdNextSubpass") and std.mem.eql(u8, name, "vkCmdNextSubpass"))) {
            if (self.real_vulkan.fn_ptrs.cmd_next_subpass) |function| function(command_buffer, @intCast(state.regs.rsi));
        } else if ((name_hash == vulkanNameHash("vkCmdBeginRenderPass2") and std.mem.eql(u8, name, "vkCmdBeginRenderPass2")) or (name_hash == vulkanNameHash("vkCmdBeginRenderPass2KHR") and std.mem.eql(u8, name, "vkCmdBeginRenderPass2KHR"))) {
            if (self.real_vulkan.fn_ptrs.cmd_begin_render_pass2) |function| {
                const guest_begin = state.guestMemoryConst(state.regs.rsi, @sizeOf(abi.RenderPassBeginInfo)) orelse return;
                const guest_subpass = state.guestMemoryConst(state.regs.rdx, @sizeOf(abi.SubpassBeginInfo)) orelse return;
                var begin: abi.RenderPassBeginInfo = undefined;
                var subpass: abi.SubpassBeginInfo = undefined;
                @memcpy(std.mem.asBytes(&begin), guest_begin);
                @memcpy(std.mem.asBytes(&subpass), guest_subpass);
                if (begin.p_next != null or subpass.p_next != null) return;
                begin.render_pass = self.real_vulkan.realRenderPass(begin.render_pass) orelse return;
                begin.framebuffer = self.real_vulkan.realFramebuffer(begin.framebuffer) orelse return;
                var clears: [32]abi.ClearValue = undefined;
                const clear_address = if (begin.clear_values) |pointer| @intFromPtr(pointer) else 0;
                if (begin.clear_value_count != 0 and !copyGuestStructs(abi.ClearValue, state, clear_address, begin.clear_value_count, &clears)) return;
                begin.clear_values = if (begin.clear_value_count == 0) null else &clears;
                function(command_buffer, &begin, &subpass);
            }
        } else if ((name_hash == vulkanNameHash("vkCmdNextSubpass2") and std.mem.eql(u8, name, "vkCmdNextSubpass2")) or (name_hash == vulkanNameHash("vkCmdNextSubpass2KHR") and std.mem.eql(u8, name, "vkCmdNextSubpass2KHR"))) {
            if (self.real_vulkan.fn_ptrs.cmd_next_subpass2) |function| {
                var begin: abi.SubpassBeginInfo = undefined;
                var end: abi.SubpassEndInfo = undefined;
                if (!copyGuestValue(abi.SubpassBeginInfo, state, state.regs.rsi, &begin) or !copyGuestValue(abi.SubpassEndInfo, state, state.regs.rdx, &end)) return;
                if (begin.p_next != null or end.p_next != null) return;
                function(command_buffer, &begin, &end);
            }
        } else if ((name_hash == vulkanNameHash("vkCmdEndRenderPass2") and std.mem.eql(u8, name, "vkCmdEndRenderPass2")) or (name_hash == vulkanNameHash("vkCmdEndRenderPass2KHR") and std.mem.eql(u8, name, "vkCmdEndRenderPass2KHR"))) {
            if (self.real_vulkan.fn_ptrs.cmd_end_render_pass2) |function| {
                var end: abi.SubpassEndInfo = undefined;
                if (!copyGuestValue(abi.SubpassEndInfo, state, state.regs.rsi, &end) or end.p_next != null) return;
                function(command_buffer, &end);
            }
        } else if ((name_hash == vulkanNameHash("vkCmdEndRenderPass") and std.mem.eql(u8, name, "vkCmdEndRenderPass"))) {
            if (self.real_vulkan.fn_ptrs.cmd_end_render_pass) |function| function(command_buffer);
        } else if ((name_hash == vulkanNameHash("vkCmdCopyBuffer") and std.mem.eql(u8, name, "vkCmdCopyBuffer"))) {
            const src = self.real_vulkan.realBuffer(state.regs.rsi) orelse return;
            const dst = self.real_vulkan.realBuffer(state.regs.rdx) orelse return;
            var regions: [64]abi.BufferCopy = undefined;
            if (!copyGuestStructs(abi.BufferCopy, state, state.regs.r8, state.regs.rcx, &regions)) return;
            if (self.real_vulkan.fn_ptrs.cmd_copy_buffer) |function| function(command_buffer, src, dst, @intCast(state.regs.rcx), &regions);
        } else if ((name_hash == vulkanNameHash("vkCmdCopyImage") and std.mem.eql(u8, name, "vkCmdCopyImage"))) {
            const src = self.real_vulkan.realImage(state.regs.rsi) orelse return;
            const dst = self.real_vulkan.realImage(state.regs.rcx) orelse return;
            var regions: [64]abi.ImageCopy = undefined;
            if (!copyGuestStructs(abi.ImageCopy, state, guestStackArg(state, 0), state.regs.r9, &regions)) return;
            if (self.real_vulkan.fn_ptrs.cmd_copy_image) |function| function(command_buffer, src, @intCast(state.regs.rdx), dst, @intCast(state.regs.r8), @intCast(state.regs.r9), &regions);
        } else if ((name_hash == vulkanNameHash("vkCmdCopyBufferToImage") and std.mem.eql(u8, name, "vkCmdCopyBufferToImage"))) {
            const src = self.real_vulkan.realBuffer(state.regs.rsi) orelse return;
            const dst = self.real_vulkan.realImage(state.regs.rdx) orelse return;
            var regions: [64]abi.BufferImageCopy = undefined;
            if (!copyGuestStructs(abi.BufferImageCopy, state, state.regs.r9, state.regs.r8, &regions)) return;
            if (self.real_vulkan.fn_ptrs.cmd_copy_buffer_to_image) |function| function(command_buffer, src, dst, @intCast(state.regs.rcx), @intCast(state.regs.r8), &regions);
        } else if ((name_hash == vulkanNameHash("vkCmdCopyImageToBuffer") and std.mem.eql(u8, name, "vkCmdCopyImageToBuffer"))) {
            const src = self.real_vulkan.realImage(state.regs.rsi) orelse return;
            const dst = self.real_vulkan.realBuffer(state.regs.rcx) orelse return;
            var regions: [64]abi.BufferImageCopy = undefined;
            if (!copyGuestStructs(abi.BufferImageCopy, state, state.regs.r9, state.regs.r8, &regions)) return;
            if (self.real_vulkan.fn_ptrs.cmd_copy_image_to_buffer) |function| function(command_buffer, src, @intCast(state.regs.rdx), dst, @intCast(state.regs.r8), &regions);
        } else if ((name_hash == vulkanNameHash("vkCmdBlitImage") and std.mem.eql(u8, name, "vkCmdBlitImage"))) {
            const src = self.real_vulkan.realImage(state.regs.rsi) orelse return;
            const dst = self.real_vulkan.realImage(state.regs.rcx) orelse return;
            var regions: [64]abi.ImageBlit = undefined;
            if (!copyGuestStructs(abi.ImageBlit, state, guestStackArg(state, 0), state.regs.r9, &regions)) return;
            if (self.real_vulkan.fn_ptrs.cmd_blit_image) |function| function(command_buffer, src, @intCast(state.regs.rdx), dst, @intCast(state.regs.r8), @intCast(state.regs.r9), &regions, @intCast(guestStackArg(state, 1)));
        } else if ((name_hash == vulkanNameHash("vkCmdFillBuffer") and std.mem.eql(u8, name, "vkCmdFillBuffer"))) {
            const buffer = self.real_vulkan.realBuffer(state.regs.rsi) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_fill_buffer) |function| function(command_buffer, buffer, state.regs.rdx, state.regs.rcx, @intCast(state.regs.r8));
        } else if ((name_hash == vulkanNameHash("vkCmdUpdateBuffer") and std.mem.eql(u8, name, "vkCmdUpdateBuffer"))) {
            const buffer = self.real_vulkan.realBuffer(state.regs.rsi) orelse return;
            const size = state.regs.r8;
            var bytes: [65536]u8 = undefined;
            if (!copyGuestBytes(state, state.regs.r9, size, &bytes)) return;
            if (self.real_vulkan.fn_ptrs.cmd_update_buffer) |function| function(command_buffer, buffer, state.regs.rdx, size, if (size == 0) null else &bytes);
        } else if ((name_hash == vulkanNameHash("vkCmdResolveImage") and std.mem.eql(u8, name, "vkCmdResolveImage"))) {
            const src = self.real_vulkan.realImage(state.regs.rsi) orelse return;
            const dst = self.real_vulkan.realImage(state.regs.rcx) orelse return;
            var regions: [64]abi.ImageResolve = undefined;
            if (!copyGuestStructs(abi.ImageResolve, state, guestStackArg(state, 0), state.regs.r9, &regions)) return;
            if (self.real_vulkan.fn_ptrs.cmd_resolve_image) |function| function(command_buffer, src, @intCast(state.regs.rdx), dst, @intCast(state.regs.r8), @intCast(state.regs.r9), &regions);
        } else if ((name_hash == vulkanNameHash("vkCmdClearColorImage") and std.mem.eql(u8, name, "vkCmdClearColorImage"))) {
            const image = self.real_vulkan.realImage(state.regs.rsi) orelse return;
            var value: abi.ClearColorValue = undefined;
            if (!copyGuestStructs(abi.ClearColorValue, state, state.regs.rcx, 1, @as(*[1]abi.ClearColorValue, @ptrCast(&value)))) return;
            var ranges: [32]abi.ImageSubresourceRange = undefined;
            if (!copyGuestStructs(abi.ImageSubresourceRange, state, state.regs.r9, state.regs.r8, &ranges)) return;
            if (self.real_vulkan.fn_ptrs.cmd_clear_color_image) |function| function(command_buffer, image, @intCast(state.regs.rdx), &value, @intCast(state.regs.r8), &ranges);
        } else if ((name_hash == vulkanNameHash("vkCmdClearDepthStencilImage") and std.mem.eql(u8, name, "vkCmdClearDepthStencilImage"))) {
            const image = self.real_vulkan.realImage(state.regs.rsi) orelse return;
            var value: abi.ClearDepthStencilValue = undefined;
            if (!copyGuestStructs(abi.ClearDepthStencilValue, state, state.regs.rcx, 1, @as(*[1]abi.ClearDepthStencilValue, @ptrCast(&value)))) return;
            var ranges: [32]abi.ImageSubresourceRange = undefined;
            if (!copyGuestStructs(abi.ImageSubresourceRange, state, state.regs.r9, state.regs.r8, &ranges)) return;
            if (self.real_vulkan.fn_ptrs.cmd_clear_depth_stencil_image) |function| function(command_buffer, image, @intCast(state.regs.rdx), &value, @intCast(state.regs.r8), &ranges);
        } else if ((name_hash == vulkanNameHash("vkCmdClearAttachments") and std.mem.eql(u8, name, "vkCmdClearAttachments"))) {
            var attachments: [32]abi.ClearAttachment = undefined;
            var rects: [64]abi.ClearRect = undefined;
            if (!copyGuestStructs(abi.ClearAttachment, state, state.regs.rdx, state.regs.rsi, &attachments)) return;
            if (!copyGuestStructs(abi.ClearRect, state, state.regs.r8, state.regs.rcx, &rects)) return;
            if (self.real_vulkan.fn_ptrs.cmd_clear_attachments) |function| function(command_buffer, @intCast(state.regs.rsi), &attachments, @intCast(state.regs.rcx), &rects);
        } else if ((name_hash == vulkanNameHash("vkCmdPipelineBarrier") and std.mem.eql(u8, name, "vkCmdPipelineBarrier"))) {
            const memory_count = state.regs.r8;
            const memory_address = state.regs.r9;
            const buffer_count = guestStackArg(state, 0);
            const buffer_address = guestStackArg(state, 1);
            const image_count = guestStackArg(state, 2);
            const image_address = guestStackArg(state, 3);
            var memory: [32]abi.MemoryBarrier = undefined;
            var buffers: [32]abi.BufferMemoryBarrier = undefined;
            var images: [32]abi.ImageMemoryBarrier = undefined;
            if (!copyGuestStructs(abi.MemoryBarrier, state, memory_address, memory_count, &memory)) return;
            if (!copyGuestStructs(abi.BufferMemoryBarrier, state, buffer_address, buffer_count, &buffers)) return;
            if (!copyGuestStructs(abi.ImageMemoryBarrier, state, image_address, image_count, &images)) return;
            for (memory[0..@as(usize, @intCast(memory_count))]) |*barrier| {
                if (barrier.p_next != null) return;
                barrier.p_next = null;
            }
            for (buffers[0..@as(usize, @intCast(buffer_count))]) |*barrier| {
                if (barrier.p_next != null) return;
                barrier.buffer = self.real_vulkan.realBuffer(barrier.buffer) orelse return;
                barrier.p_next = null;
            }
            if (!self.copyGuestImageBarriers(state, image_address, image_count, &images)) return;
            if (self.real_vulkan.fn_ptrs.cmd_pipeline_barrier) |function| function(
                command_buffer,
                @intCast(state.regs.rsi),
                @intCast(state.regs.rdx),
                @intCast(state.regs.rcx),
                @intCast(memory_count),
                if (memory_count == 0) null else &memory,
                @intCast(buffer_count),
                if (buffer_count == 0) null else &buffers,
                @intCast(image_count),
                if (image_count == 0) null else &images,
            );
        } else if ((name_hash == vulkanNameHash("vkCmdPipelineBarrier2") and std.mem.eql(u8, name, "vkCmdPipelineBarrier2")) or (name_hash == vulkanNameHash("vkCmdPipelineBarrier2KHR") and std.mem.eql(u8, name, "vkCmdPipelineBarrier2KHR"))) {
            self.forwardPipelineBarrier2(state, command_buffer);
        } else if ((name_hash == vulkanNameHash("vkCmdBeginQuery") and std.mem.eql(u8, name, "vkCmdBeginQuery"))) {
            const pool = self.real_vulkan.realQueryPool(state.regs.rsi) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_begin_query) |function| function(command_buffer, pool, @intCast(state.regs.rdx), @intCast(state.regs.rcx));
        } else if ((name_hash == vulkanNameHash("vkCmdEndQuery") and std.mem.eql(u8, name, "vkCmdEndQuery"))) {
            const pool = self.real_vulkan.realQueryPool(state.regs.rsi) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_end_query) |function| function(command_buffer, pool, @intCast(state.regs.rdx));
        } else if ((name_hash == vulkanNameHash("vkCmdResetQueryPool") and std.mem.eql(u8, name, "vkCmdResetQueryPool"))) {
            const pool = self.real_vulkan.realQueryPool(state.regs.rsi) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_reset_query_pool) |function| function(command_buffer, pool, @intCast(state.regs.rdx), @intCast(state.regs.rcx));
        } else if ((name_hash == vulkanNameHash("vkCmdCopyQueryPoolResults") and std.mem.eql(u8, name, "vkCmdCopyQueryPoolResults"))) {
            const pool = self.real_vulkan.realQueryPool(state.regs.rsi) orelse return;
            const buffer = self.real_vulkan.realBuffer(state.regs.r8) orelse return;
            if (self.real_vulkan.fn_ptrs.cmd_copy_query_pool_results) |function| function(
                command_buffer,
                pool,
                @intCast(state.regs.rdx),
                @intCast(state.regs.rcx),
                buffer,
                state.regs.r9,
                guestStackArg(state, 0),
                @intCast(guestStackArg(state, 1)),
            );
        } else {
            if (self.vulkan_modeled_command_calls <= 8) machoCapturePrint("macho-processor: Vulkan command ABI not implemented: {s}\n", .{name});
        }
    }

    fn forwardPipelineBarrier2(self: *Forwarder, state: anytype, command_buffer: abi.CommandBuffer) void {
        const dependency_address = state.regs.rsi;
        var dependency: abi.DependencyInfo = undefined;
        if (!copyGuestValue(abi.DependencyInfo, state, dependency_address, &dependency) or dependency.p_next != null) return;
        if (dependency.memory_barrier_count > 32 or dependency.buffer_memory_barrier_count > 32 or dependency.image_memory_barrier_count > 32) return;
        var memory: [32]abi.MemoryBarrier2 = undefined;
        var buffers: [32]abi.BufferMemoryBarrier2 = undefined;
        var images: [32]abi.ImageMemoryBarrier2 = undefined;
        const memory_address = if (dependency.memory_barriers) |pointer| @intFromPtr(pointer) else 0;
        const buffer_address = if (dependency.buffer_memory_barriers) |pointer| @intFromPtr(pointer) else 0;
        const image_address = if (dependency.image_memory_barriers) |pointer| @intFromPtr(pointer) else 0;
        if (!copyGuestStructs(abi.MemoryBarrier2, state, memory_address, dependency.memory_barrier_count, &memory) or
            !copyGuestStructs(abi.BufferMemoryBarrier2, state, buffer_address, dependency.buffer_memory_barrier_count, &buffers) or
            !copyGuestStructs(abi.ImageMemoryBarrier2, state, image_address, dependency.image_memory_barrier_count, &images)) return;
        for (memory[0..@as(usize, @intCast(dependency.memory_barrier_count))]) |*barrier| if (barrier.p_next != null) return;
        for (buffers[0..@as(usize, @intCast(dependency.buffer_memory_barrier_count))]) |*barrier| {
            if (barrier.p_next != null) return;
            barrier.buffer = self.real_vulkan.realBuffer(barrier.buffer) orelse return;
        }
        for (images[0..@as(usize, @intCast(dependency.image_memory_barrier_count))]) |*barrier| {
            if (barrier.p_next != null) return;
            barrier.image = self.real_vulkan.realImage(barrier.image) orelse return;
        }
        dependency.memory_barriers = if (dependency.memory_barrier_count == 0) null else &memory;
        dependency.buffer_memory_barriers = if (dependency.buffer_memory_barrier_count == 0) null else &buffers;
        dependency.image_memory_barriers = if (dependency.image_memory_barrier_count == 0) null else &images;
        if (self.real_vulkan.fn_ptrs.cmd_pipeline_barrier2) |function| function(command_buffer, &dependency);
    }

    fn updateDescriptorSets(self: *Forwarder, state: anytype) void {
        const write_count = state.regs.rsi;
        const copy_count = state.regs.rcx;
        if (self.real_vulkan.device_lost or !self.real_vulkan.hasDevice() or self.real_vulkan.fn_ptrs.update_descriptor_sets == null) return;
        if (write_count > 64 or copy_count > 64) return;
        var writes: [64]abi.WriteDescriptorSet = undefined;
        var copies: [64]abi.CopyDescriptorSet = undefined;
        var images: [256]abi.DescriptorImageInfo = undefined;
        var buffers: [256]abi.DescriptorBufferInfo = undefined;
        var texel_views: [256]u64 = undefined;
        var inline_blocks: [64]abi.WriteDescriptorSetInlineUniformBlock = undefined;
        var inline_data: [64][256]u8 = undefined;
        if (!copyGuestStructs(abi.WriteDescriptorSet, state, state.regs.rdx, write_count, &writes)) return;
        if (!copyGuestStructs(abi.CopyDescriptorSet, state, state.regs.r8, copy_count, &copies)) return;
        var image_cursor: usize = 0;
        var buffer_cursor: usize = 0;
        var texel_cursor: usize = 0;
        for (writes[0..@as(usize, @intCast(write_count))], 0..) |*write, write_index| {
            write.dst_set = self.real_vulkan.realDescriptorSet(write.dst_set) orelse return;
            const count: usize = @intCast(write.descriptor_count);
            if (write.descriptor_type == abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
                if (write.p_next == null or count > inline_data[write_index].len) return;
                var block: abi.WriteDescriptorSetInlineUniformBlock = undefined;
                if (!copyGuestValue(abi.WriteDescriptorSetInlineUniformBlock, state, @intFromPtr(write.p_next.?), &block) or
                    block.s_type != abi.STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK or
                    block.p_next != null or block.data_size != count)
                {
                    return;
                }
                const data_address = if (block.data) |pointer| @intFromPtr(pointer) else 0;
                if (!copyGuestBytes(state, data_address, count, &inline_data[write_index])) return;
                block.p_next = null;
                block.data = if (count == 0) null else @ptrCast(@alignCast(inline_data[write_index][0..].ptr));
                inline_blocks[write_index] = block;
                write.p_next = &inline_blocks[write_index];
                write.image_info = null;
                write.buffer_info = null;
                write.texel_buffer_view = null;
            } else {
                if (write.p_next != null) return;
                write.p_next = null;
                switch (write.descriptor_type) {
                    // Sampler, combined image sampler, sampled image, storage
                    // image and input attachment all carry VkDescriptorImageInfo.
                    0, 1, 2, 3, 10 => {
                        if (image_cursor + count > images.len) return;
                        const address = if (write.image_info) |pointer| @intFromPtr(pointer) else 0;
                        if (count != 0 and address == 0) return;
                        if (!copyGuestStructs(abi.DescriptorImageInfo, state, address, count, images[image_cursor..])) return;
                        for (images[image_cursor .. image_cursor + count]) |*image| {
                            if (image.sampler != 0) image.sampler = self.real_vulkan.realSampler(image.sampler) orelse return;
                            if (image.image_view != 0) image.image_view = self.real_vulkan.realImageView(image.image_view) orelse return;
                        }
                        write.image_info = if (count == 0) null else images[image_cursor..].ptr;
                        image_cursor += count;
                    },
                    // Uniform and storage buffer descriptors carry VkDescriptorBufferInfo.
                    6, 7, 8, 9 => {
                        if (buffer_cursor + count > buffers.len) return;
                        const address = if (write.buffer_info) |pointer| @intFromPtr(pointer) else 0;
                        if (count != 0 and address == 0) return;
                        if (!copyGuestStructs(abi.DescriptorBufferInfo, state, address, count, buffers[buffer_cursor..])) return;
                        for (buffers[buffer_cursor .. buffer_cursor + count]) |*buffer| {
                            buffer.buffer = self.real_vulkan.realBuffer(buffer.buffer) orelse return;
                        }
                        write.buffer_info = if (count == 0) null else buffers[buffer_cursor..].ptr;
                        buffer_cursor += count;
                    },
                    // Uniform/storage texel buffers carry an array of VkBufferView.
                    4, 5 => {
                        if (texel_cursor + count > texel_views.len) return;
                        const address = if (write.texel_buffer_view) |pointer| @intFromPtr(pointer) else 0;
                        if (count != 0 and address == 0) return;
                        if (!copyGuestStructs(u64, state, address, count, texel_views[texel_cursor..])) return;
                        for (texel_views[texel_cursor .. texel_cursor + count]) |*view| {
                            view.* = self.real_vulkan.realBufferView(view.*) orelse return;
                        }
                        write.texel_buffer_view = if (count == 0) null else texel_views[texel_cursor..].ptr;
                        texel_cursor += count;
                    },
                    // Inline uniform blocks have a different pNext-shaped payload;
                    // every other descriptor type is intentionally refused rather
                    // than sent with a mismatched pointer union.
                    else => return,
                }
            }
        }
        for (copies[0..@as(usize, @intCast(copy_count))]) |*copy| {
            if (copy.p_next != null) return;
            copy.p_next = null;
            copy.src_set = self.real_vulkan.realDescriptorSet(copy.src_set) orelse return;
            copy.dst_set = self.real_vulkan.realDescriptorSet(copy.dst_set) orelse return;
        }
        self.real_vulkan.fn_ptrs.update_descriptor_sets.?(
            self.real_vulkan.device.?,
            @intCast(write_count),
            if (write_count == 0) null else &writes,
            @intCast(copy_count),
            if (copy_count == 0) null else &copies,
        );
        self.vulkan_tiers.note(.descriptor_set, .real);
    }

    fn forwardPushDescriptorSet(self: *Forwarder, state: anytype, command_buffer: abi.CommandBuffer) void {
        const function = self.real_vulkan.fn_ptrs.cmd_push_descriptor_set orelse return;
        const count = state.regs.r8;
        if (count > 64) return;
        var writes: [64]abi.WriteDescriptorSet = undefined;
        var images: [256]abi.DescriptorImageInfo = undefined;
        var buffers: [256]abi.DescriptorBufferInfo = undefined;
        var texel_views: [256]u64 = undefined;
        var inline_blocks: [64]abi.WriteDescriptorSetInlineUniformBlock = undefined;
        var inline_data: [64][256]u8 = undefined;
        if (!copyGuestStructs(abi.WriteDescriptorSet, state, state.regs.r9, count, &writes)) return;
        var image_cursor: usize = 0;
        var buffer_cursor: usize = 0;
        var texel_cursor: usize = 0;
        for (writes[0..@as(usize, @intCast(count))], 0..) |*write, write_index| {
            if (write.s_type != abi.WriteDescriptorSet_structure_type) return;
            // The push-descriptor command supplies the destination layout/set
            // separately; dstSet in each write is ignored by Vulkan.
            write.dst_set = 0;
            const descriptor_count: usize = @intCast(write.descriptor_count);
            if (write.descriptor_type == abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
                if (write.p_next == null or descriptor_count > inline_data[write_index].len) return;
                var block: abi.WriteDescriptorSetInlineUniformBlock = undefined;
                if (!copyGuestValue(abi.WriteDescriptorSetInlineUniformBlock, state, @intFromPtr(write.p_next.?), &block) or
                    block.s_type != abi.STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK or
                    block.p_next != null or block.data_size != descriptor_count)
                {
                    return;
                }
                const data_address = if (block.data) |pointer| @intFromPtr(pointer) else 0;
                if (!copyGuestBytes(state, data_address, descriptor_count, &inline_data[write_index])) return;
                block.p_next = null;
                block.data = if (descriptor_count == 0) null else @ptrCast(@alignCast(inline_data[write_index][0..].ptr));
                inline_blocks[write_index] = block;
                write.p_next = &inline_blocks[write_index];
                write.image_info = null;
                write.buffer_info = null;
                write.texel_buffer_view = null;
            } else {
                if (write.p_next != null) return;
                switch (write.descriptor_type) {
                    0, 1, 2, 3, 10 => {
                        if (image_cursor + descriptor_count > images.len) return;
                        const address = if (write.image_info) |pointer| @intFromPtr(pointer) else 0;
                        if (descriptor_count != 0 and address == 0) return;
                        if (!copyGuestStructs(abi.DescriptorImageInfo, state, address, descriptor_count, images[image_cursor..])) return;
                        for (images[image_cursor .. image_cursor + descriptor_count]) |*image| {
                            if (image.sampler != 0) image.sampler = self.real_vulkan.realSampler(image.sampler) orelse return;
                            if (image.image_view != 0) image.image_view = self.real_vulkan.realImageView(image.image_view) orelse return;
                        }
                        write.image_info = if (descriptor_count == 0) null else images[image_cursor..].ptr;
                        image_cursor += descriptor_count;
                    },
                    4, 5 => {
                        if (texel_cursor + descriptor_count > texel_views.len) return;
                        const address = if (write.texel_buffer_view) |pointer| @intFromPtr(pointer) else 0;
                        if (descriptor_count != 0 and address == 0) return;
                        if (!copyGuestStructs(u64, state, address, descriptor_count, texel_views[texel_cursor..])) return;
                        for (texel_views[texel_cursor .. texel_cursor + descriptor_count]) |*view|
                            view.* = self.real_vulkan.realBufferView(view.*) orelse return;
                        write.texel_buffer_view = if (descriptor_count == 0) null else texel_views[texel_cursor..].ptr;
                        texel_cursor += descriptor_count;
                    },
                    6, 7, 8, 9 => {
                        if (buffer_cursor + descriptor_count > buffers.len) return;
                        const address = if (write.buffer_info) |pointer| @intFromPtr(pointer) else 0;
                        if (descriptor_count != 0 and address == 0) return;
                        if (!copyGuestStructs(abi.DescriptorBufferInfo, state, address, descriptor_count, buffers[buffer_cursor..])) return;
                        for (buffers[buffer_cursor .. buffer_cursor + descriptor_count]) |*buffer|
                            buffer.buffer = self.real_vulkan.realBuffer(buffer.buffer) orelse return;
                        write.buffer_info = if (descriptor_count == 0) null else buffers[buffer_cursor..].ptr;
                        buffer_cursor += descriptor_count;
                    },
                    else => return,
                }
                write.p_next = null;
            }
        }
        const layout = self.real_vulkan.realPipelineLayout(state.regs.rdx) orelse return;
        function(command_buffer, @intCast(state.regs.rsi), layout, @intCast(state.regs.rcx), @intCast(count), &writes);
        self.vulkan_tiers.note(.descriptor_set, .real);
    }

    fn pipelineCachePath(self: *Forwarder) ?[]const u8 {
        if (!self.vulkan_pipeline_cache_path_checked) {
            self.vulkan_pipeline_cache_path_checked = true;
            if (std.c.getenv("ROSETTE_VULKAN_PIPELINE_CACHE")) |raw| {
                const value = std.mem.sliceTo(raw, 0);
                if (value.len != 0 and value.len < self.vulkan_pipeline_cache_path.len) {
                    @memcpy(self.vulkan_pipeline_cache_path[0..value.len], value);
                    self.vulkan_pipeline_cache_path_len = @intCast(value.len);
                }
            }
        }
        if (self.vulkan_pipeline_cache_path_len == 0) return null;
        return self.vulkan_pipeline_cache_path[0..self.vulkan_pipeline_cache_path_len];
    }

    fn readPipelineCacheFile(self: *Forwarder, destination: []u8) usize {
        const path = self.pipelineCachePath() orelse return 0;
        var path_z: [1024 + 1]u8 = [_]u8{0} ** (1024 + 1);
        @memcpy(path_z[0..path.len], path);
        path_z[path.len] = 0;
        var flags: std.c.O = .{};
        flags.ACCMODE = .RDONLY;
        const fd = std.c.open(@ptrCast(&path_z), flags, @as(std.c.mode_t, 0));
        if (fd < 0) return 0;
        defer _ = std.c.close(fd);
        var total: usize = 0;
        while (total < destination.len) {
            const amount = std.c.read(fd, destination.ptr + total, destination.len - total);
            if (amount <= 0) break;
            total += @intCast(amount);
        }
        if (total != 0) self.vulkan_pipeline_cache_loads +|= 1;
        return total;
    }

    fn savePipelineCacheFile(self: *Forwarder, data: []const u8) void {
        const path = self.pipelineCachePath() orelse return;
        if (data.len == 0 or data.len > marshal.scratch_bytes) return;
        var path_z: [1024 + 1]u8 = [_]u8{0} ** (1024 + 1);
        @memcpy(path_z[0..path.len], path);
        path_z[path.len] = 0;
        var flags: std.c.O = .{};
        flags.ACCMODE = .WRONLY;
        flags.CREAT = true;
        flags.TRUNC = true;
        const fd = std.c.open(@ptrCast(&path_z), flags, @as(std.c.mode_t, 0o600));
        if (fd < 0) return;
        defer _ = std.c.close(fd);
        var written: usize = 0;
        while (written < data.len) {
            const amount = std.c.write(fd, data.ptr + written, data.len - written);
            if (amount <= 0) return;
            written += @intCast(amount);
        }
        self.vulkan_pipeline_cache_saves +|= 1;
    }

    fn persistPipelineCache(self: *Forwarder, cache: abi.PipelineCache) void {
        if (self.real_vulkan.device_lost) return;
        if (self.pipelineCachePath() == null) return;
        const get_data = self.real_vulkan.fn_ptrs.get_pipeline_cache_data orelse return;
        var data: [marshal.scratch_bytes]u8 = undefined;
        var size: usize = data.len;
        const result = get_data(self.real_vulkan.device orelse return, cache, &size, &data);
        self.noteRealVulkanResult(result, "vkGetPipelineCacheData during persistence");
        if (result == abi.SUCCESS and size <= data.len) self.savePipelineCacheFile(data[0..size]);
    }

    fn updateDescriptorSetWithTemplate(self: *Forwarder, state: anytype) void {
        if (self.real_vulkan.device_lost) return;
        const function = self.real_vulkan.fn_ptrs.update_descriptor_set_with_template orelse return;
        const destination = self.real_vulkan.realDescriptorSet(state.regs.rsi) orelse return;
        const template = self.real_vulkan.realDescriptorUpdateTemplate(state.regs.rdx) orelse return;
        const record_index = self.real_vulkan.descriptorUpdateTemplateIndex(state.regs.rdx) orelse return;
        const record = &self.real_vulkan.descriptor_update_template_records[record_index];

        var required: u64 = 0;
        for (record.entries[0..record.entry_count]) |entry| {
            if (entry.descriptor_count == 0) continue;
            const element_size: u64 = switch (entry.descriptor_type) {
                0, 1, 2, 3, 10 => @sizeOf(abi.DescriptorImageInfo),
                4, 5 => @sizeOf(u64),
                6, 7, 8, 9 => @sizeOf(abi.DescriptorBufferInfo),
                abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK => 1,
                else => return,
            };
            if (entry.stride < element_size) return;
            const last = std.math.mul(u64, @as(u64, entry.descriptor_count - 1), entry.stride) catch return;
            const end = std.math.add(u64, entry.offset, std.math.add(u64, last, element_size) catch return) catch return;
            required = @max(required, end);
        }
        if (required > marshal.scratch_bytes) return;
        if (required != 0 and state.regs.rcx == 0) return;
        self.vulkan_scratch.reset();
        const host_data = self.vulkan_scratch.alloc(@intCast(required)) orelse return;
        if (required != 0) {
            const guest_data = state.guestMemoryConst(state.regs.rcx, required) orelse return;
            @memcpy(host_data, guest_data);
        }
        for (record.entries[0..record.entry_count]) |entry| {
            if (entry.descriptor_count == 0) continue;
            const element_size: usize = switch (entry.descriptor_type) {
                0, 1, 2, 3, 10 => @sizeOf(abi.DescriptorImageInfo),
                4, 5 => @sizeOf(u64),
                6, 7, 8, 9 => @sizeOf(abi.DescriptorBufferInfo),
                abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK => 1,
                else => return,
            };
            for (0..@as(usize, @intCast(entry.descriptor_count))) |element_index| {
                const relative = std.math.add(u64, entry.offset, std.math.mul(u64, @as(u64, @intCast(element_index)), entry.stride) catch return) catch return;
                const offset: usize = @intCast(relative);
                if (offset + element_size > host_data.len) return;
                switch (entry.descriptor_type) {
                    0, 1, 2, 3, 10 => {
                        const sampler = std.mem.readInt(u64, host_data[offset..][0..8], .little);
                        const image_view = std.mem.readInt(u64, host_data[offset + 8 ..][0..8], .little);
                        if (sampler != 0) {
                            const real = self.real_vulkan.realSampler(sampler) orelse return;
                            std.mem.writeInt(u64, host_data[offset..][0..8], real, .little);
                        }
                        if (image_view != 0) {
                            const real = self.real_vulkan.realImageView(image_view) orelse return;
                            std.mem.writeInt(u64, host_data[offset + 8 ..][0..8], real, .little);
                        }
                    },
                    4, 5 => {
                        const view = std.mem.readInt(u64, host_data[offset..][0..8], .little);
                        if (view != 0) {
                            const real = self.real_vulkan.realBufferView(view) orelse return;
                            std.mem.writeInt(u64, host_data[offset..][0..8], real, .little);
                        }
                    },
                    6, 7, 8, 9 => {
                        const buffer = std.mem.readInt(u64, host_data[offset..][0..8], .little);
                        if (buffer != 0) {
                            const real = self.real_vulkan.realBuffer(buffer) orelse return;
                            std.mem.writeInt(u64, host_data[offset..][0..8], real, .little);
                        }
                    },
                    abi.DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK => {},
                    else => return,
                }
            }
        }
        function(self.real_vulkan.device.?, destination, template, if (required == 0) null else @ptrCast(host_data.ptr));
        self.vulkan_tiers.note(.descriptor_set, .real);
    }

    fn getPipelineCacheData(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |lost| return lost;
        const function = self.real_vulkan.fn_ptrs.get_pipeline_cache_data orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const cache = self.real_vulkan.realPipelineCache(state.regs.rsi) orelse return vkErrorInitializationFailed();
        const size_address = state.regs.rdx;
        if (size_address == 0 or state.guestMemory(size_address, 8) == null) return vkErrorInitializationFailed();
        const requested = state.read64(size_address);
        var required: usize = 0;
        const query_result = function(self.real_vulkan.device.?, cache, &required, null);
        self.noteRealVulkanResult(query_result, "vkGetPipelineCacheData");
        if (query_result != abi.SUCCESS) return @as(u32, @bitCast(query_result));
        if (state.regs.rcx == 0) {
            state.write64(size_address, required);
            self.vulkan_tiers.note(.pipeline, .real);
            return abi.SUCCESS;
        }
        const capacity = @min(@as(usize, @intCast(@min(requested, std.math.maxInt(usize)))), marshal.scratch_bytes);
        if (capacity != 0 and state.guestMemory(state.regs.rcx, capacity) == null) return vkErrorInitializationFailed();
        self.vulkan_scratch.reset();
        const host_bytes = if (capacity == 0) null else self.vulkan_scratch.alloc(capacity);
        if (capacity != 0 and host_bytes == null) return vkErrorOutOfHostMemory();
        var data_size: usize = capacity;
        const result = function(
            self.real_vulkan.device.?,
            cache,
            &data_size,
            if (host_bytes) |bytes| @ptrCast(bytes.ptr) else null,
        );
        self.noteRealVulkanResult(result, "vkGetPipelineCacheData");
        if (host_bytes) |bytes| {
            if (data_size > bytes.len) data_size = bytes.len;
            if (state.guestMemory(state.regs.rcx, data_size)) |destination| @memcpy(destination, bytes[0..data_size]);
        }
        state.write64(size_address, data_size);
        self.vulkan_tiers.note(.pipeline, .real);
        return @as(u32, @bitCast(result));
    }

    fn destroyVulkanObject(self: *Forwarder, state: anytype, name: []const u8) u64 {
        if (!self.real_vulkan.hasDevice()) return 0;
        // After VK_ERROR_DEVICE_LOST, the native child handles are no longer
        // valid driver objects.  Keep destruction a guest-visible no-op until
        // destroyRealDevice performs the quarantined teardown; calling any
        // child destructor here can turn recoverable guest teardown into a
        // second host crash.
        if (self.real_vulkan.device_lost) return 0;
        const device = self.real_vulkan.device.?;
        const handle = state.regs.rsi;
        if (std.mem.eql(u8, name, "vkDestroySampler")) {
            if (self.real_vulkan.realSampler(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_sampler) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.sampler_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyDescriptorSetLayout")) {
            if (self.real_vulkan.realDescriptorSetLayout(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_descriptor_set_layout) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.descriptor_set_layout_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyPipelineLayout")) {
            if (self.real_vulkan.realPipelineLayout(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_pipeline_layout) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.pipeline_layout_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyShaderModule")) {
            if (self.real_vulkan.realShaderModule(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_shader_module) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.shader_module_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyRenderPass")) {
            if (self.real_vulkan.realRenderPass(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_render_pass) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.render_pass_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyFramebuffer")) {
            if (self.real_vulkan.realFramebuffer(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_framebuffer) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.framebuffer_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyPipeline")) {
            if (self.real_vulkan.realPipeline(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_pipeline) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.pipeline_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyBuffer")) {
            if (self.real_vulkan.realBuffer(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_buffer) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.buffer_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyImage")) {
            if (self.real_vulkan.realImage(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_image) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.image_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyImageView")) {
            if (self.real_vulkan.realImageView(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_image_view) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.image_view_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyBufferView")) {
            if (self.real_vulkan.realBufferView(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_buffer_view) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.buffer_view_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyFence")) {
            if (self.real_vulkan.realFence(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_fence) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.fence_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroySemaphore")) {
            if (self.real_vulkan.realSemaphore(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_semaphore) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.semaphore_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyCommandPool")) {
            if (self.real_vulkan.realCommandPool(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_command_pool) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.command_pool_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyDescriptorPool")) {
            if (self.real_vulkan.realDescriptorPool(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_descriptor_pool) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.descriptor_pool_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyQueryPool")) {
            if (self.real_vulkan.realQueryPool(handle)) |real| if (self.real_vulkan.fn_ptrs.destroy_query_pool) |function| function(device, real, null);
            HandleMap.remove(&self.real_vulkan.query_pool_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyPipelineCache")) {
            if (self.real_vulkan.realPipelineCache(handle)) |real| {
                self.persistPipelineCache(real);
                if (self.real_vulkan.fn_ptrs.destroy_pipeline_cache) |function| function(device, real, null);
                self.vulkan_real_objects_destroyed +|= 1;
            }
            HandleMap.remove(&self.real_vulkan.pipeline_cache_map, handle);
        } else if (std.mem.eql(u8, name, "vkDestroyDescriptorUpdateTemplate")) {
            if (self.real_vulkan.realDescriptorUpdateTemplate(handle)) |real| {
                if (self.real_vulkan.fn_ptrs.destroy_descriptor_update_template) |function| function(device, real, null);
                self.vulkan_real_objects_destroyed +|= 1;
            }
            if (self.real_vulkan.descriptorUpdateTemplateIndex(handle)) |record_index| self.real_vulkan.descriptor_update_template_records[record_index] = .{};
            HandleMap.remove(&self.real_vulkan.descriptor_update_template_map, handle);
        } else if (std.mem.eql(u8, name, "vkFreeMemory")) {
            if (self.real_vulkan.realMemory(handle)) |real| {
                if (self.real_vulkan.fn_ptrs.unmap_memory) |function| {
                    for (&self.vulkan_memory_records) |*record| if (record.handle == handle and record.host_mapped_ptr != null) function(device, real);
                }
                if (self.real_vulkan.fn_ptrs.free_memory) |function| function(device, real, null);
            }
            HandleMap.remove(&self.real_vulkan.memory_map, handle);
            if (self.findVulkanMemoryRecord(handle)) |record| record.* = .{};
        } else if (std.mem.eql(u8, name, "vkFreeCommandBuffers")) {
            const pool = self.real_vulkan.realCommandPool(state.regs.rsi) orelse return 0;
            const count = state.regs.rdx;
            var buffers: [256]u64 = undefined;
            if (count > buffers.len or !copyGuestHandleArray(self, state, state.regs.rcx, count, &buffers, .command_buffer)) return 0;
            if (self.real_vulkan.fn_ptrs.free_command_buffers) |function| function(device, pool, @intCast(count), @ptrCast(&buffers));
            for (0..@as(usize, @intCast(count))) |index| HandleMap.remove(&self.real_vulkan.command_buffer_map, state.read64(state.regs.rcx + @as(u64, @intCast(index)) * 8));
        } else if (std.mem.eql(u8, name, "vkFreeDescriptorSets")) {
            const pool = self.real_vulkan.realDescriptorPool(state.regs.rsi) orelse return 0;
            const count = state.regs.rdx;
            var sets: [256]u64 = undefined;
            if (!copyGuestHandleArray(self, state, state.regs.rcx, count, &sets, .descriptor_set)) return 0;
            if (self.real_vulkan.fn_ptrs.free_descriptor_sets) |function| _ = function(device, pool, @intCast(count), &sets);
            for (0..@as(usize, @intCast(count))) |index| HandleMap.remove(&self.real_vulkan.descriptor_set_map, state.read64(state.regs.rcx + @as(u64, @intCast(index)) * 8));
        }
        return 0;
    }

    fn nextVulkanObject(self: *Forwarder) u64 {
        const result = self.next_vulkan_object;
        self.next_vulkan_object +%= 0x10;
        return result;
    }

    fn createVulkanObject(self: *Forwarder, state: anytype, create_info: u64, output: u64, name: []const u8) u64 {
        if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
        if (self.realDeviceLostResult()) |result| return result;
        const handle = self.nextVulkanObject();
        // Phase 1: create real Vulkan objects when the device is available.
        if (self.real_vulkan.hasDevice()) {
            self.real_create_result = abi.SUCCESS;
            self.createRealVulkanObject(state, handle, create_info, name) catch {
                const failure = if (self.real_create_result != abi.SUCCESS) self.real_create_result else abi.ERROR_INITIALIZATION_FAILED;
                self.noteRealVulkanResult(failure, name);
                machoCapturePrint(
                    "macho-processor: REAL {s} creation failed: VkResult={d}; refusing synthetic fallback\n",
                    .{ name, failure },
                );
                return @as(u32, @bitCast(failure));
            };
            if (self.real_create_result != abi.SUCCESS) {
                self.noteRealVulkanResult(self.real_create_result, name);
                return @as(u32, @bitCast(self.real_create_result));
            }
        }
        state.write64(output, handle);
        registerOpaqueHandle(state, handle, name);
        machoCapturePrint("macho-processor: Vulkan object created: {s} handle=0x{x} output=0x{x}\n", .{ name, handle, output });
        if (std.mem.eql(u8, name, "vkCreateImage")) self.recordImage(state, handle, create_info);
        if (std.mem.eql(u8, name, "vkCreateBuffer")) self.recordBuffer(state, handle, create_info);
        return 0;
    }

    /// Map a synthetic handle to the real driver object behind it.
    ///
    /// Reached through a function pointer so the marshaller needs no knowledge
    /// of this type. A miss is null rather than zero: `VK_NULL_HANDLE` is
    /// meaningful in some fields and catastrophic in others, so "I do not know
    /// this object" must not be spelled the same way as "there is no object".
    fn resolveRealHandle(context: *anyopaque, kind: marshal.HandleKind, synthetic: u64) ?u64 {
        const self: *Forwarder = @ptrCast(@alignCast(context));
        return switch (kind) {
            .descriptor_set_layout => HandleMap.findReal(&self.real_vulkan.descriptor_set_layout_map, synthetic),
            .render_pass => HandleMap.findReal(&self.real_vulkan.render_pass_map, synthetic),
            .image => HandleMap.findReal(&self.real_vulkan.image_map, synthetic),
            .image_view => HandleMap.findReal(&self.real_vulkan.image_view_map, synthetic),
            .sampler => HandleMap.findReal(&self.real_vulkan.sampler_map, synthetic),
            .buffer => HandleMap.findReal(&self.real_vulkan.buffer_map, synthetic),
            .pipeline_layout => HandleMap.findReal(&self.real_vulkan.pipeline_layout_map, synthetic),
        };
    }

    /// Bridges the marshaller's plain callback to whatever concrete state type
    /// the forwarder was instantiated with.
    fn MarshalReader(comptime State: type) type {
        return struct {
            fn read(context: *anyopaque, address: u64, length: u64) ?[]const u8 {
                const typed: *State = @ptrCast(@alignCast(context));
                return typed.guestMemoryConst(address, length);
            }
        };
    }

    /// Produce a host-ready create-info, or nothing.
    ///
    /// "Nothing" is the safe answer and the common one: a structure with no
    /// plan, an unresolvable handle or an array that will not fit is left to
    /// the modelled path rather than handed to a driver with guest pointers
    /// still in it. That refusal is the property that keeps an undescribed
    /// structure from being able to crash the process.
    fn marshalCreateInfo(
        self: *Forwarder,
        state: anytype,
        create_info: u64,
        name: []const u8,
    ) ?[]u8 {
        if (create_info == 0) return null;
        self.vulkan_scratch.reset();

        // `VkSemaphoreTypeCreateInfo` is the one synchronization create
        // chain Xenia commonly uses.  The generic marshaller deliberately
        // clears every pNext because it cannot safely follow arbitrary guest
        // chains; handle this known, fixed-size node explicitly so a timeline
        // semaphore is created as a timeline semaphore on the real device
        // instead of silently becoming a binary/modelled object.
        if (std.mem.eql(u8, name, "vkCreateSemaphore")) {
            return self.marshalSemaphoreCreateInfo(state, create_info);
        }
        if (std.mem.eql(u8, name, "vkCreateImage")) {
            return self.marshalImageCreateInfo(state, create_info);
        }

        const State = @typeInfo(@TypeOf(state)).pointer.child;
        if (std.mem.eql(u8, name, "vkCreateRenderPass")) {
            const custom_result = marshal.marshalRenderPass(
                create_info,
                &self.vulkan_scratch,
                .{ .context = @ptrCast(self), .lookup = resolveRealHandle },
                @ptrCast(state),
                MarshalReader(State).read,
            );
            return switch (custom_result) {
                .ready => |bytes| bytes,
                .refused => |refusal| {
                    self.vulkan_marshal_refusals +|= 1;
                    if (self.vulkan_marshal_refusals <= 16) machoCapturePrint(
                        "macho-processor: vulkan marshal refused {s}: {s} — {s}\n",
                        .{ name, refusal.label(), refusal.meaning() },
                    );
                    return null;
                },
            };
        }

        const plan = marshal.planFor(name) orelse {
            self.vulkan_marshal_refusals +|= 1;
            if (self.vulkan_marshal_refusals <= 16) machoCapturePrint(
                "macho-processor: vulkan marshal refused {s}: {s}\n",
                .{ name, marshal.Refusal.no_plan.meaning() },
            );
            return null;
        };
        const result = marshal.marshal(
            plan,
            create_info,
            &self.vulkan_scratch,
            .{ .context = @ptrCast(self), .lookup = resolveRealHandle },
            @ptrCast(state),
            MarshalReader(State).read,
        );
        return switch (result) {
            .ready => |bytes| bytes,
            .refused => |refusal| {
                self.vulkan_marshal_refusals +|= 1;
                if (self.vulkan_marshal_refusals <= 16) machoCapturePrint(
                    "macho-processor: vulkan marshal refused {s}: {s} — {s}\n",
                    .{ name, refusal.label(), refusal.meaning() },
                );
                return null;
            },
        };
    }

    fn marshalSemaphoreCreateInfo(self: *Forwarder, state: anytype, create_info: u64) ?[]u8 {
        var guest_root: abi.SemaphoreCreateInfo = undefined;
        if (!copyGuestValue(abi.SemaphoreCreateInfo, state, create_info, &guest_root)) return null;
        const root_bytes = self.vulkan_scratch.alloc(@sizeOf(abi.SemaphoreCreateInfo)) orelse return null;
        @memcpy(root_bytes, std.mem.asBytes(&guest_root));
        const root: *abi.SemaphoreCreateInfo = @ptrCast(@alignCast(root_bytes.ptr));
        const guest_next = state.read64(create_info + 8);
        if (guest_next == 0) {
            root.p_next = null;
            return root_bytes;
        }
        if (state.guestMemoryConst(guest_next, @sizeOf(abi.SemaphoreTypeCreateInfo)) == null or
            state.read32(guest_next) != abi.STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO or
            state.read64(guest_next + 8) != 0)
        {
            self.vulkan_marshal_refusals +|= 1;
            machoCapturePrint(
                "macho-processor: vulkan marshal refused vkCreateSemaphore: unsupported pNext chain at 0x{x}\n",
                .{guest_next},
            );
            return null;
        }
        var guest_type: abi.SemaphoreTypeCreateInfo = undefined;
        if (!copyGuestValue(abi.SemaphoreTypeCreateInfo, state, guest_next, &guest_type)) return null;
        guest_type.p_next = null;
        const type_bytes = self.vulkan_scratch.alloc(@sizeOf(abi.SemaphoreTypeCreateInfo)) orelse return null;
        @memcpy(type_bytes, std.mem.asBytes(&guest_type));
        root.p_next = @ptrCast(@alignCast(type_bytes.ptr));
        return root_bytes;
    }

    fn marshalImageCreateInfo(self: *Forwarder, state: anytype, create_info: u64) ?[]u8 {
        var guest_root: abi.ImageCreateInfo = undefined;
        if (!copyGuestValue(abi.ImageCreateInfo, state, create_info, &guest_root)) return null;
        if (guest_root.queue_family_index_count > 32) return null;

        var queue_family_indices: [32]u32 = undefined;
        const queue_address = if (guest_root.queue_family_indices) |pointer| @intFromPtr(pointer) else 0;
        if (!copyGuestStructs(u32, state, queue_address, guest_root.queue_family_index_count, &queue_family_indices)) return null;

        var guest_format_list: abi.ImageFormatListCreateInfo = undefined;
        var view_formats: [16]u32 = undefined;
        var has_format_list = false;
        if (guest_root.p_next) |pointer| {
            const guest_next = @intFromPtr(pointer);
            if (!copyGuestValue(abi.ImageFormatListCreateInfo, state, guest_next, &guest_format_list) or
                guest_format_list.s_type != abi.STRUCTURE_TYPE_IMAGE_FORMAT_LIST_CREATE_INFO or
                guest_format_list.p_next != null or
                guest_format_list.view_format_count > view_formats.len)
            {
                return null;
            }
            const format_address = if (guest_format_list.view_formats) |formats| @intFromPtr(formats) else 0;
            if (!copyGuestStructs(u32, state, format_address, guest_format_list.view_format_count, &view_formats)) return null;
            has_format_list = true;
        }

        const root_bytes = self.vulkan_scratch.alloc(@sizeOf(abi.ImageCreateInfo)) orelse return null;
        @memcpy(root_bytes, std.mem.asBytes(&guest_root));
        const root: *abi.ImageCreateInfo = @ptrCast(@alignCast(root_bytes.ptr));
        root.p_next = null;
        root.queue_family_indices = null;
        if (guest_root.queue_family_index_count != 0) {
            const queue_bytes = self.vulkan_scratch.alloc(@as(usize, @intCast(guest_root.queue_family_index_count)) * @sizeOf(u32)) orelse return null;
            @memcpy(queue_bytes, std.mem.sliceAsBytes(queue_family_indices[0..@as(usize, @intCast(guest_root.queue_family_index_count))]));
            root.queue_family_indices = @ptrCast(@alignCast(queue_bytes.ptr));
        }
        if (has_format_list) {
            const list_bytes = self.vulkan_scratch.alloc(@sizeOf(abi.ImageFormatListCreateInfo)) orelse return null;
            @memcpy(list_bytes, std.mem.asBytes(&guest_format_list));
            const list: *abi.ImageFormatListCreateInfo = @ptrCast(@alignCast(list_bytes.ptr));
            list.p_next = null;
            list.view_formats = null;
            if (guest_format_list.view_format_count != 0) {
                const format_bytes = self.vulkan_scratch.alloc(@as(usize, @intCast(guest_format_list.view_format_count)) * @sizeOf(u32)) orelse return null;
                @memcpy(format_bytes, std.mem.sliceAsBytes(view_formats[0..@as(usize, @intCast(guest_format_list.view_format_count))]));
                list.view_formats = @ptrCast(@alignCast(format_bytes.ptr));
            }
            root.p_next = @ptrCast(@alignCast(list_bytes.ptr));
        }
        return root_bytes;
    }

    fn createRealVulkanObject(self: *Forwarder, state: anytype, synthetic_handle: u64, create_info: u64, name: []const u8) !void {
        const device = self.real_vulkan.device.?;
        if (std.mem.eql(u8, name, "vkCreateDescriptorUpdateTemplate")) {
            var guest_root: abi.DescriptorUpdateTemplateCreateInfo = undefined;
            if (!copyGuestValue(abi.DescriptorUpdateTemplateCreateInfo, state, create_info, &guest_root)) return error.InvalidInfo;
            if (guest_root.s_type != abi.STRUCTURE_TYPE_DESCRIPTOR_UPDATE_TEMPLATE_CREATE_INFO or
                guest_root.p_next != null or
                guest_root.flags != 0 or
                guest_root.template_type != abi.DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET or
                guest_root.descriptor_update_entry_count > 64)
            {
                return error.InvalidInfo;
            }
            const entry_address = if (guest_root.descriptor_update_entries) |pointer| @intFromPtr(pointer) else 0;
            if (guest_root.descriptor_update_entry_count != 0 and entry_address == 0) return error.InvalidInfo;
            var entries: [64]abi.DescriptorUpdateTemplateEntry = undefined;
            if (!copyGuestStructs(abi.DescriptorUpdateTemplateEntry, state, entry_address, guest_root.descriptor_update_entry_count, &entries)) return error.InvalidInfo;
            const descriptor_layout = self.real_vulkan.realDescriptorSetLayout(guest_root.descriptor_set_layout) orelse return error.InvalidInfo;
            for (entries[0..@as(usize, @intCast(guest_root.descriptor_update_entry_count))]) |*entry| {
                if (entry.descriptor_count == 0 or entry.stride == 0) return error.InvalidInfo;
            }
            self.vulkan_scratch.reset();
            const root_bytes = self.vulkan_scratch.alloc(@sizeOf(abi.DescriptorUpdateTemplateCreateInfo)) orelse return error.InvalidInfo;
            const entry_bytes = self.vulkan_scratch.alloc(@as(usize, @intCast(guest_root.descriptor_update_entry_count)) * @sizeOf(abi.DescriptorUpdateTemplateEntry)) orelse return error.InvalidInfo;
            const root: *abi.DescriptorUpdateTemplateCreateInfo = @ptrCast(@alignCast(root_bytes.ptr));
            @memcpy(root_bytes, std.mem.asBytes(&guest_root));
            if (guest_root.descriptor_update_entry_count != 0) @memcpy(entry_bytes, std.mem.sliceAsBytes(entries[0..@as(usize, @intCast(guest_root.descriptor_update_entry_count))]));
            root.p_next = null;
            root.descriptor_set_layout = descriptor_layout;
            root.descriptor_update_entries = @ptrCast(@alignCast(entry_bytes.ptr));
            root.pipeline_layout = 0;
            var real_template: abi.DescriptorUpdateTemplate = 0;
            const create_fn = self.real_vulkan.fn_ptrs.create_descriptor_update_template orelse return error.MissingFn;
            const result = create_fn(device, root, null, &real_template);
            if (result == abi.SUCCESS and real_template != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.descriptor_update_template_map, synthetic_handle, real_template);
                if (self.real_vulkan.descriptorUpdateTemplateIndex(synthetic_handle)) |record_index| {
                    const record = &self.real_vulkan.descriptor_update_template_records[record_index];
                    record.entry_count = @intCast(guest_root.descriptor_update_entry_count);
                    if (guest_root.descriptor_update_entry_count != 0) {
                        @memcpy(record.entries[0..@as(usize, @intCast(guest_root.descriptor_update_entry_count))], entries[0..@as(usize, @intCast(guest_root.descriptor_update_entry_count))]);
                    }
                }
                self.vulkan_real_objects_created +|= 1;
                machoCapturePrint("macho-processor: REAL vkCreateDescriptorUpdateTemplate: synthetic=0x{x} real=0x{x} entries={d}\n", .{ synthetic_handle, real_template, guest_root.descriptor_update_entry_count });
            } else {
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreatePipelineCache")) {
            var guest_root: abi.PipelineCacheCreateInfo = undefined;
            if (!copyGuestValue(abi.PipelineCacheCreateInfo, state, create_info, &guest_root)) return error.InvalidInfo;
            if (guest_root.p_next != null or guest_root.flags != 0 or guest_root.initial_data_size > marshal.scratch_bytes) return error.InvalidInfo;
            self.vulkan_scratch.reset();
            const root_bytes = self.vulkan_scratch.alloc(@sizeOf(abi.PipelineCacheCreateInfo)) orelse return error.InvalidInfo;
            @memcpy(root_bytes, std.mem.asBytes(&guest_root));
            const root: *abi.PipelineCacheCreateInfo = @ptrCast(@alignCast(root_bytes.ptr));
            root.p_next = null;
            if (root.initial_data_size != 0) {
                const guest_data = if (guest_root.initial_data) |pointer| @intFromPtr(pointer) else 0;
                if (guest_data == 0) return error.InvalidInfo;
                const initial = state.guestMemoryConst(guest_data, guest_root.initial_data_size) orelse return error.InvalidInfo;
                const host_data = self.vulkan_scratch.alloc(@intCast(guest_root.initial_data_size)) orelse return error.InvalidInfo;
                @memcpy(host_data, initial);
                root.initial_data = @ptrCast(@alignCast(host_data.ptr));
            } else {
                root.initial_data = null;
                var cache_file: [marshal.scratch_bytes + 1]u8 = undefined;
                const cache_size = self.readPipelineCacheFile(&cache_file);
                if (cache_size != 0 and cache_size <= marshal.scratch_bytes) {
                    const host_data = self.vulkan_scratch.alloc(cache_size) orelse return error.InvalidInfo;
                    @memcpy(host_data, cache_file[0..cache_size]);
                    root.initial_data_size = cache_size;
                    root.initial_data = @ptrCast(@alignCast(host_data.ptr));
                    machoCapturePrint("macho-processor: Vulkan pipeline cache seed loaded: bytes={d}\n", .{cache_size});
                }
            }
            var real_cache: abi.PipelineCache = 0;
            const create_fn = self.real_vulkan.fn_ptrs.create_pipeline_cache orelse return error.MissingFn;
            const result = create_fn(device, root, null, &real_cache);
            if (result == abi.SUCCESS and real_cache != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.pipeline_cache_map, synthetic_handle, real_cache);
                self.vulkan_real_objects_created +|= 1;
                machoCapturePrint("macho-processor: REAL vkCreatePipelineCache: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_cache });
            } else {
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateImage")) {
            // Was handing the driver a pointer straight into guest memory: the

            // chain pointer and any index array inside were guest addresses the

            // driver would dereference as its own.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_image orelse return error.MissingFn;
            var real_image: abi.Image = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_image);
            if (result == 0 and real_image != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.image_map, synthetic_handle, real_image);
                self.vulkan_real_objects_created +|= 1;
                self.vulkan_tiers.note(.image_object, .real);
                machoCapturePrint("macho-processor: REAL vkCreateImage: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_image });
            } else {
                machoCapturePrint("macho-processor: vkCreateImage FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateBuffer")) {
            // Was handing the driver a pointer straight into guest memory: the

            // chain pointer and any index array inside were guest addresses the

            // driver would dereference as its own.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_buffer orelse return error.MissingFn;
            var real_buffer: abi.Buffer = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_buffer);
            if (result == 0 and real_buffer != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.buffer_map, synthetic_handle, real_buffer);
                self.vulkan_real_objects_created +|= 1;
                self.vulkan_tiers.note(.buffer_object, .real);
                machoCapturePrint("macho-processor: REAL vkCreateBuffer: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_buffer });
            } else {
                machoCapturePrint("macho-processor: vkCreateBuffer FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateSampler")) {
            // Marshalled: every pointer and handle inside the structure is

            // translated, and a refusal keeps the modelled path rather than

            // handing the driver a guest address.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_sampler orelse return error.MissingFn;
            var real_sampler: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_sampler);
            if (result == 0 and real_sampler != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.sampler_map, synthetic_handle, real_sampler);
                machoCapturePrint("macho-processor: REAL vkCreateSampler: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_sampler });
            } else {
                machoCapturePrint("macho-processor: vkCreateSampler FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateShaderModule")) {
            // Marshalled: every pointer and handle inside the structure is

            // translated, and a refusal keeps the modelled path rather than

            // handing the driver a guest address.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_shader_module orelse return error.MissingFn;
            var real_module: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_module);
            if (result == 0 and real_module != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.shader_module_map, synthetic_handle, real_module);
                machoCapturePrint("macho-processor: REAL vkCreateShaderModule: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_module });
            } else {
                machoCapturePrint("macho-processor: vkCreateShaderModule FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateRenderPass")) {
            // Marshalled: every pointer and handle inside the structure is

            // translated, and a refusal keeps the modelled path rather than

            // handing the driver a guest address.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_render_pass orelse return error.MissingFn;
            var real_rp: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_rp);
            if (result == 0 and real_rp != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.render_pass_map, synthetic_handle, real_rp);
                machoCapturePrint("macho-processor: REAL vkCreateRenderPass: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_rp });
            } else {
                machoCapturePrint("macho-processor: vkCreateRenderPass FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateFramebuffer")) {
            // Marshalled: every pointer and handle inside the structure is

            // translated, and a refusal keeps the modelled path rather than

            // handing the driver a guest address.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_framebuffer orelse return error.MissingFn;
            var real_fb: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_fb);
            if (result == 0 and real_fb != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.framebuffer_map, synthetic_handle, real_fb);
                machoCapturePrint("macho-processor: REAL vkCreateFramebuffer: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_fb });
            } else {
                machoCapturePrint("macho-processor: vkCreateFramebuffer FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateDescriptorSetLayout")) {
            // Marshalled: every pointer and handle inside the structure is

            // translated, and a refusal keeps the modelled path rather than

            // handing the driver a guest address.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_descriptor_set_layout orelse return error.MissingFn;
            var real_layout: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_layout);
            if (result == 0 and real_layout != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.descriptor_set_layout_map, synthetic_handle, real_layout);
                self.vulkan_tiers.note(.descriptor_set_layout, .real);
                machoCapturePrint("macho-processor: REAL vkCreateDescriptorSetLayout: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_layout });
            } else {
                machoCapturePrint("macho-processor: vkCreateDescriptorSetLayout FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreatePipelineLayout")) {
            // Marshalled: every pointer and handle inside the structure is

            // translated, and a refusal keeps the modelled path rather than

            // handing the driver a guest address.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_pipeline_layout orelse return error.MissingFn;
            var real_pl: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_pl);
            if (result == 0 and real_pl != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.pipeline_layout_map, synthetic_handle, real_pl);
                self.vulkan_tiers.note(.pipeline_layout, .real);
                machoCapturePrint("macho-processor: REAL vkCreatePipelineLayout: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_pl });
            } else {
                machoCapturePrint("macho-processor: vkCreatePipelineLayout FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateDescriptorPool")) {
            // Marshalled: every pointer and handle inside the structure is

            // translated, and a refusal keeps the modelled path rather than

            // handing the driver a guest address.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_descriptor_pool orelse return error.MissingFn;
            var real_pool: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_pool);
            if (result == 0 and real_pool != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.descriptor_pool_map, synthetic_handle, real_pool);
                machoCapturePrint("macho-processor: REAL vkCreateDescriptorPool: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_pool });
            } else {
                machoCapturePrint("macho-processor: vkCreateDescriptorPool FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateBufferView")) {
            // Marshalled: every pointer and handle inside the structure is

            // translated, and a refusal keeps the modelled path rather than

            // handing the driver a guest address.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_buffer_view orelse return error.MissingFn;
            var real_bv: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_bv);
            if (result == 0 and real_bv != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.buffer_view_map, synthetic_handle, real_bv);
                machoCapturePrint("macho-processor: REAL vkCreateBufferView: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_bv });
            } else {
                machoCapturePrint("macho-processor: vkCreateBufferView FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateImageView")) {
            // Marshalled: every pointer and handle inside the structure is

            // translated, and a refusal keeps the modelled path rather than

            // handing the driver a guest address.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_image_view orelse return error.MissingFn;
            var real_iv: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_iv);
            if (result == 0 and real_iv != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.image_view_map, synthetic_handle, real_iv);
                machoCapturePrint("macho-processor: REAL vkCreateImageView: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_iv });
            } else {
                machoCapturePrint("macho-processor: vkCreateImageView FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateCommandPool")) {
            // Was handing the driver a pointer straight into guest memory: the

            // chain pointer and any index array inside were guest addresses the

            // driver would dereference as its own.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_command_pool orelse return error.MissingFn;
            var real_pool: u64 = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_pool);
            if (result == 0 and real_pool != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.command_pool_map, synthetic_handle, real_pool);
                machoCapturePrint("macho-processor: REAL vkCreateCommandPool: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_pool });
            } else {
                machoCapturePrint("macho-processor: vkCreateCommandPool FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateFence")) {
            // Was handing the driver a pointer straight into guest memory: the

            // chain pointer and any index array inside were guest addresses the

            // driver would dereference as its own.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_fence orelse return error.MissingFn;
            var real_fence: abi.Fence = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_fence);
            if (result == 0 and real_fence != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.fence_map, synthetic_handle, real_fence);
                machoCapturePrint("macho-processor: REAL vkCreateFence: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_fence });
            } else {
                machoCapturePrint("macho-processor: vkCreateFence FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateSemaphore")) {
            // Was handing the driver a pointer straight into guest memory: the

            // chain pointer and any index array inside were guest addresses the

            // driver would dereference as its own.

            const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_semaphore orelse return error.MissingFn;
            var real_sem: abi.Semaphore = 0;
            const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_sem);
            if (result == 0 and real_sem != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.semaphore_map, synthetic_handle, real_sem);
                machoCapturePrint("macho-processor: REAL vkCreateSemaphore: synthetic=0x{x} real=0x{x}\n", .{ synthetic_handle, real_sem });
            } else {
                machoCapturePrint("macho-processor: vkCreateSemaphore FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        } else if (std.mem.eql(u8, name, "vkCreateQueryPool")) {
            var guest_info: abi.QueryPoolCreateInfo = undefined;
            if (!copyGuestValue(abi.QueryPoolCreateInfo, state, create_info, &guest_info) or guest_info.p_next != null) return error.InvalidInfo;
            const create_fn = self.real_vulkan.fn_ptrs.create_query_pool orelse return error.MissingFn;
            guest_info.p_next = null;
            var real_pool: abi.QueryPool = 0;
            const result = create_fn(device, &guest_info, null, &real_pool);
            if (result == abi.SUCCESS and real_pool != 0) {
                HandleMap.allocOrFind(&self.real_vulkan.query_pool_map, synthetic_handle, real_pool);
                self.vulkan_tiers.note(.command_recording, .real);
                machoCapturePrint("macho-processor: REAL vkCreateQueryPool: synthetic=0x{x} real=0x{x} type={d} count={d}\n", .{ synthetic_handle, real_pool, guest_info.query_type, guest_info.query_count });
            } else {
                machoCapturePrint("macho-processor: vkCreateQueryPool FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
                self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
            }
        }
    }

    fn trackedImageCount(self: *const Forwarder) u64 {
        var count: u64 = 0;
        for (self.vulkan_resources) |record| {
            if (record.handle != 0 and record.kind == .image) count += 1;
        }
        return count;
    }

    fn resourceSlot(self: *Forwarder, handle: u64) ?*VulkanResource {
        for (&self.vulkan_resources) |*record| {
            if (record.handle == handle) return record;
        }
        for (&self.vulkan_resources) |*record| {
            if (record.handle == 0) return record;
        }
        self.vulkan_resource_overflow +|= 1;
        return null;
    }

    fn findResource(self: *Forwarder, handle: u64) ?*VulkanResource {
        if (handle == 0) return null;
        for (&self.vulkan_resources) |*record| {
            if (record.handle == handle) return record;
        }
        return null;
    }

    fn recordImage(self: *Forwarder, state: anytype, handle: u64, create_info: u64) void {
        if (create_info == 0 or state.guestMemoryConst(create_info, VK_IMAGE_CREATE_INFO_SIZE) == null) return;
        const record = self.resourceSlot(handle) orelse return;
        const format = state.read32(create_info + VK_IMAGE_CREATE_INFO_FORMAT_OFFSET);
        const width = state.read32(create_info + VK_IMAGE_CREATE_INFO_EXTENT_OFFSET);
        const height = state.read32(create_info + VK_IMAGE_CREATE_INFO_EXTENT_OFFSET + 4);
        const bytes_per_pixel = rosette_gpu.vulkan.selection.bytesPerPixel(format) orelse 0;
        const row_pitch = @as(u64, width) * bytes_per_pixel;
        record.* = .{
            .handle = handle,
            .kind = .image,
            .format = format,
            .width = width,
            .height = height,
            .mip_levels = state.read32(create_info + VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET),
            .array_layers = state.read32(create_info + VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET),
            .tiling = state.read32(create_info + VK_IMAGE_CREATE_INFO_TILING_OFFSET),
            .usage = state.read32(create_info + VK_IMAGE_CREATE_INFO_USAGE_OFFSET),
            .row_pitch_bytes = row_pitch,
            .size_bytes = row_pitch * height,
        };
    }

    fn recordBuffer(self: *Forwarder, state: anytype, handle: u64, create_info: u64) void {
        if (create_info == 0 or state.guestMemoryConst(create_info, VK_BUFFER_CREATE_INFO_SIZE) == null) return;
        const record = self.resourceSlot(handle) orelse return;
        record.* = .{
            .handle = handle,
            .kind = .buffer,
            .usage = state.read32(create_info + VK_BUFFER_CREATE_INFO_USAGE_OFFSET),
            .size_bytes = state.read64(create_info + VK_BUFFER_CREATE_INFO_SIZE_OFFSET),
        };
    }

    fn bindResourceMemory(self: *Forwarder, resource: u64, memory: u64, offset: u64, kind: VulkanResourceKind) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const record = self.findResource(resource) orelse {
            // A real-device bind must never report success for an unmapped
            // guest resource.  Returning success here leaves Vulkan with an
            // apparently bound object while the native driver still sees an
            // unbound resource, which is especially difficult to diagnose at
            // the first submit.
            if (self.real_vulkan.hasDevice()) return vkErrorInitializationFailed();
            return 0;
        };
        // Phase 1: bind real Vulkan resources.
        if (self.real_vulkan.hasDevice()) {
            const device = self.real_vulkan.device.?;
            const real_mem = self.real_vulkan.realMemory(memory) orelse {
                machoCapturePrint(
                    "macho-processor: REAL vkBind resource refused: memory=0x{x} has no native mapping\n",
                    .{memory},
                );
                return vkErrorInitializationFailed();
            };
            var result: abi.Result = abi.ERROR_INITIALIZATION_FAILED;
            var native_resource = false;
            if (kind == .image) {
                if (self.real_vulkan.realImage(resource)) |real_image| {
                    native_resource = true;
                    if (self.real_vulkan.fn_ptrs.bind_image_memory) |bind_fn| {
                        result = bind_fn(device, real_image, real_mem, offset);
                    } else {
                        return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                    }
                }
            } else if (self.real_vulkan.realBuffer(resource)) |real_buffer| {
                native_resource = true;
                if (self.real_vulkan.fn_ptrs.bind_buffer_memory) |bind_fn| {
                    result = bind_fn(device, real_buffer, real_mem, offset);
                } else {
                    return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                }
            }
            if (!native_resource) {
                machoCapturePrint(
                    "macho-processor: REAL vkBind resource refused: resource=0x{x} has no native mapping kind={s}\n",
                    .{ resource, @tagName(kind) },
                );
                return vkErrorInitializationFailed();
            }
            if (result != abi.SUCCESS) {
                machoCapturePrint(
                    "macho-processor: REAL vkBind resource FAILED: resource=0x{x} memory=0x{x} offset={d} VkResult={d}\n",
                    .{ resource, memory, offset, result },
                );
                return @as(u32, @bitCast(result));
            }
            record.memory = memory;
            record.memory_offset = offset;
            machoCapturePrint(
                "macho-processor: REAL vkBind{s}Memory: resource=0x{x} memory=0x{x} offset={d}\n",
                .{ if (kind == .image) "Image" else "Buffer", resource, real_mem, offset },
            );
        } else {
            // The synthetic fallback has no driver object to bind. Keep the
            // semantic record for diagnostics, but never let this branch make
            // a real-device bind failure look successful.
            record.memory = memory;
            record.memory_offset = offset;
        }
        if (kind == .image) {
            self.vulkan_image_bindings +|= 1;
            if (self.vulkan_image_bindings <= 4) {
                machoCapturePrint(
                    "macho-processor: Vulkan image bound to memory: image=0x{x} memory=0x{x} offset={d} extent={d}x{d} format={d} tiling={d} usage=0x{x} size={d}\n",
                    .{ resource, memory, offset, record.width, record.height, record.format, record.tiling, record.usage, record.size_bytes },
                );
            }
        }
        return 0;
    }

    /// Vulkan 1.1 groups resource bindings into an array. Keep the operation
    /// in Rosette's resource model and only decode the public Vulkan ABI at
    /// this edge; the resource records below remain backend-independent.
    fn bindResourcesMemory2(
        self: *Forwarder,
        state: anytype,
        count: u64,
        infos: u64,
        kind: VulkanResourceKind,
    ) u64 {
        const info_size: u64 = 40;
        const byte_count = std.math.mul(u64, count, info_size) catch return vkErrorInitializationFailed();
        if (count != 0 and state.guestMemoryConst(infos, byte_count) == null) return vkErrorInitializationFailed();
        var index: u64 = 0;
        while (index < count) : (index += 1) {
            const info = infos + index * info_size;
            const resource = state.read64(info + 16);
            const memory = state.read64(info + 24);
            const offset = state.read64(info + 32);
            const result = self.bindResourceMemory(resource, memory, offset, kind);
            if (result != abi.SUCCESS) return result;
        }
        return 0;
    }

    /// Answer with a size the resource actually needs.
    ///
    /// This previously replied 4096 bytes for everything. A 1280×720 image was
    /// therefore backed by a 4 KiB allocation, so a guest that filled it wrote
    /// 3.5 MB past its own allocation — and an image that cannot hold a frame
    /// can never become one, which puts a floor under every attempt to find
    /// authentic pixels.
    /// Report exactly what the driver said, including the two fields that were
    /// being discarded.
    ///
    /// The old path fetched real requirements and then wrote back a synthetic
    /// `alignment = 256` and `memoryTypeBits = 1`. That is the mixed-tier
    /// failure in its purest form: the caller then intersects those bits with
    /// the *real* memory properties, and on this platform memory type 0 is
    /// device-local and not host-visible — so any upload allocation resolves to
    /// `UINT32_MAX` and the caller gives up. The device-local allocation right
    /// before it succeeds, which is what made the failure look selective.
    fn writeExactMemoryRequirements(
        self: *Forwarder,
        state: anytype,
        output: u64,
        reqs: abi.MemoryRequirements,
    ) u64 {
        _ = self;
        const bytes = state.guestMemory(output, 24) orelse return vkErrorInitializationFailed();
        @memset(bytes, 0);
        std.mem.writeInt(u64, bytes[0..8], reqs.size, .little);
        std.mem.writeInt(u64, bytes[8..16], if (reqs.alignment == 0) 256 else reqs.alignment, .little);
        std.mem.writeInt(u32, bytes[16..20], reqs.memory_type_bits, .little);
        return 0;
    }

    /// Requirements for a resource the real device does not know about.
    ///
    /// The synthetic `memoryTypeBits` must still be intersected against the
    /// device's real memory types by the caller, so advertising only bit zero
    /// asserts that exactly one specific memory type is usable — a claim this
    /// layer is in no position to make. Every type the device actually reports
    /// is the honest answer: it constrains nothing and lets the caller apply
    /// its own preference.
    fn writeSyntheticMemoryRequirements(self: *Forwarder, state: anytype, output: u64, size: u64) u64 {
        // memoryTypeBits names indices into the memory types the guest was
        // told about.  With no real adapter queried, that is the modelled
        // heap, which advertises exactly one type — answering 0xFFFFFFFF there
        // hands the guest a mask over thirty-one types it was never shown.
        const real_type_count = self.real_vulkan.memoryTypeCount();
        const type_count = if (real_type_count == 0) MODELLED_MEMORY_TYPE_COUNT else real_type_count;
        const bits: u32 = if (type_count >= 32)
            0xFFFF_FFFF
        else
            (@as(u32, 1) << @intCast(type_count)) - 1;
        const bytes = state.guestMemory(output, 24) orelse return vkErrorInitializationFailed();
        const alignment: u64 = 256;
        const rounded = if (size == 0) 4096 else std.mem.alignForward(u64, size, alignment);
        @memset(bytes, 0);
        std.mem.writeInt(u64, bytes[0..8], rounded, .little);
        std.mem.writeInt(u64, bytes[8..16], alignment, .little);
        std.mem.writeInt(u32, bytes[16..20], bits, .little);
        return 0;
    }

    fn writeResourceMemoryRequirements(self: *Forwarder, state: anytype, resource: u64, output: u64) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        // Phase 1: query real requirements when possible.
        if (self.real_vulkan.hasDevice()) {
            const device = self.real_vulkan.device.?;
            // Check if this is a buffer or image.
            if (self.real_vulkan.realBuffer(resource)) |rb| {
                if (self.real_vulkan.fn_ptrs.get_buffer_memory_requirements) |get_fn| {
                    var reqs: abi.MemoryRequirements = .{};
                    get_fn(device, rb, &reqs);
                    self.vulkan_tiers.note(.memory_requirements, .real);
                    return self.writeExactMemoryRequirements(state, output, reqs);
                }
            }
            if (self.real_vulkan.realImage(resource)) |ri| {
                if (self.real_vulkan.fn_ptrs.get_image_memory_requirements) |get_fn| {
                    var reqs: abi.MemoryRequirements = .{};
                    get_fn(device, ri, &reqs);
                    self.vulkan_tiers.note(.memory_requirements, .real);
                    return self.writeExactMemoryRequirements(state, output, reqs);
                }
            }
        }
        // Fallback: use the recorded size.
        const record = self.findResource(resource);
        const size = if (record) |found| found.size_bytes else 0;
        self.vulkan_tiers.note(.memory_requirements, .modelled);
        return self.writeSyntheticMemoryRequirements(state, output, size);
    }

    /// Vulkan 1.1 wraps both the resource and the result in extensible
    /// structures. The payload is still the same Rosette memory requirement;
    /// preserve the caller-owned sType/pNext headers and write only the nested
    /// VkMemoryRequirements at offset 16.
    fn writeResourceMemoryRequirements2(self: *Forwarder, state: anytype, info: u64, output: u64) u64 {
        if (state.guestMemoryConst(info, 24) == null or state.guestMemory(output, 40) == null) {
            return vkErrorInitializationFailed();
        }
        const resource = state.read64(info + 16);
        return self.writeResourceMemoryRequirements(state, resource, output + 16);
    }

    fn writeDeviceBufferMemoryRequirements(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const info_address = state.regs.rsi;
        const output = state.regs.rdx;
        if (info_address == 0 or output == 0 or state.guestMemoryConst(info_address, @sizeOf(abi.BufferMemoryRequirementsInfo2)) == null or
            state.guestMemory(output, @sizeOf(abi.MemoryRequirements2)) == null) return 0;
        const synthetic = state.read64(info_address + 16);
        if (self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.get_device_buffer_memory_requirements != null) {
            const real_buffer = self.real_vulkan.realBuffer(synthetic) orelse return 0;
            var info = abi.BufferMemoryRequirementsInfo2{ .buffer = real_buffer };
            var result: abi.MemoryRequirements2 = .{};
            self.real_vulkan.fn_ptrs.get_device_buffer_memory_requirements.?(self.real_vulkan.device.?, &info, &result);
            self.vulkan_tiers.note(.memory_requirements, .real);
            return self.writeExactMemoryRequirements(state, output + 16, result.memory_requirements);
        }
        return self.writeResourceMemoryRequirements2(state, info_address, output);
    }

    fn writeDeviceImageMemoryRequirements(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const info_address = state.regs.rsi;
        const output = state.regs.rdx;
        if (info_address == 0 or output == 0 or state.guestMemoryConst(info_address, @sizeOf(abi.ImageMemoryRequirementsInfo2)) == null or
            state.guestMemory(output, @sizeOf(abi.MemoryRequirements2)) == null) return 0;
        const synthetic = state.read64(info_address + 16);
        if (self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.get_device_image_memory_requirements != null) {
            const real_image = self.real_vulkan.realImage(synthetic) orelse return 0;
            var info = abi.ImageMemoryRequirementsInfo2{ .image = real_image };
            var result: abi.MemoryRequirements2 = .{};
            self.real_vulkan.fn_ptrs.get_device_image_memory_requirements.?(self.real_vulkan.device.?, &info, &result);
            self.vulkan_tiers.note(.memory_requirements, .real);
            return self.writeExactMemoryRequirements(state, output + 16, result.memory_requirements);
        }
        return self.writeResourceMemoryRequirements2(state, info_address, output);
    }

    fn createLogicalDevice(self: *Forwarder, state: anytype, output: u64) u64 {
        const result = createHandle(state, output, VK_SYNTHETIC_DEVICE, "Vulkan logical device");
        if (result == 0) {
            self.vulkan_logical_devices_created +|= 1;
            if (self.vulkan_logical_devices_created == 1) {
                machoCapturePrint(
                    "macho-processor: Vulkan milestone: logical_device_created handle=0x{x} output=0x{x}\n",
                    .{ VK_SYNTHETIC_DEVICE, output },
                );
            }
        }
        return result;
    }

    // ---- Vulkan call trace helpers ----

    fn recordVulkanCall(self: *Forwarder, _: anytype, name: []const u8, result: i32, arg0: u64, arg1: u64) void {
        const seq = self.vulkan_call_count;
        self.vulkan_call_count +|= 1;
        const slot = self.vulkan_call_trace_next;
        self.vulkan_call_trace_next = @intCast((slot + 1) % 64);
        if (self.vulkan_call_trace_next == 0) self.vulkan_call_trace_full = true;
        var entry = &self.vulkan_call_trace[slot];
        entry.sequence = seq;
        entry.name_len = @intCast(@min(name.len, 64));
        @memcpy(entry.name[0..entry.name_len], name[0..entry.name_len]);
        entry.result = result;
        entry.arg0 = arg0;
        entry.arg1 = arg1;
    }

    /// Dump the Vulkan call trace ring buffer to the runtime log.
    pub fn dumpVulkanCallTrace(self: *Forwarder) void {
        machoCapturePrint("macho-processor: VULKAN CALL TRACE BEGIN (count={d} ring_next={d} ring_full={})\n", .{ self.vulkan_call_count, self.vulkan_call_trace_next, self.vulkan_call_trace_full });
        const start: usize = if (self.vulkan_call_trace_full) self.vulkan_call_trace_next else 0;
        const count: usize = if (self.vulkan_call_trace_full) 64 else self.vulkan_call_trace_next;
        for (0..count) |i| {
            const idx = (start + i) % 64;
            const entry = self.vulkan_call_trace[idx];
            if (entry.name_len == 0) continue;
            machoCapturePrint(
                "macho-processor:   [{d}] #{d} {s} result={d} arg0=0x{x} arg1=0x{x}\n",
                .{ idx, entry.sequence, entry.name[0..entry.name_len], entry.result, entry.arg0, entry.arg1 },
            );
        }
        machoCapturePrint("macho-processor: VULKAN CALL TRACE END\n", .{});
    }

    /// Dump a snapshot of the Vulkan forwarding state to the runtime log.
    pub fn dumpVulkanStateSnapshot(self: *Forwarder) void {
        machoCapturePrint("macho-processor: VULKAN STATE SNAPSHOT BEGIN\n", .{});
        machoCapturePrint(
            "macho-processor:   real_device={} device_lost={} real_instance={} real_physical=0x{x}\n",
            .{ self.real_vulkan.hasDevice(), self.real_vulkan.device_lost, self.real_vulkan.hasInstance(), if (self.real_vulkan.physical_device) |p| @intFromPtr(p) else @as(u64, 0) },
        );
        machoCapturePrint(
            "macho-processor:   counters: device_void={d} opaque={d} memory_allocs={d} memory_maps={d} queue_submits={d} real_queue_submits={d} presents={d} real_presents={d} command_calls={d} real_command_calls={d} real_objects_created={d} real_objects_destroyed={d} shadow_uploads={d} shadow_upload_failures={d} fence_completions={d} device_lost_events={d} pipeline_cache_loads={d} pipeline_cache_saves={d}\n",
            .{ self.vulkan_device_void_calls, self.guest_opaque_calls, self.vulkan_memory_allocations, self.vulkan_memory_maps, self.vulkan_queue_submits, self.vulkan_real_queue_submits, self.vulkan_presents, self.vulkan_real_presents, self.vulkan_modeled_command_calls, self.vulkan_real_command_calls, self.vulkan_real_objects_created, self.vulkan_real_objects_destroyed, self.vulkan_shadow_uploads, self.vulkan_shadow_upload_failures, self.vulkan_fence_completions, self.vulkan_device_lost_events, self.vulkan_pipeline_cache_loads, self.vulkan_pipeline_cache_saves },
        );
        machoCapturePrint(
            "macho-processor:   queues: graphics={} compute={} transfer={}\n",
            .{ self.real_vulkan.graphics_queue != null, self.real_vulkan.compute_queue != null, self.real_vulkan.transfer_queue != null },
        );
        machoCapturePrint(
            "macho-processor:   memory_records: max={d}\n",
            .{MAX_VULKAN_MEMORY_ALLOCATIONS},
        );
        for (self.vulkan_memory_records, 0..) |record, idx| {
            if (record.handle == 0) continue;
            machoCapturePrint(
                "macho-processor:   mem[{d}]: handle=0x{x} size={d} mapped_base=0x{x} mapped_size={d}\n",
                .{ idx, record.handle, record.requested_size, record.mapped_base, record.mapped_size },
            );
        }
        if (self.last_opaque_vulkan_call_len > 0) {
            machoCapturePrint(
                "macho-processor:   last_opaque_call: {s}\n",
                .{self.last_opaque_vulkan_call[0..self.last_opaque_vulkan_call_len]},
            );
        }
        machoCapturePrint("macho-processor: VULKAN STATE SNAPSHOT END\n", .{});
        // Dump the call trace too.
        self.dumpVulkanCallTrace();
    }

    fn writeDeviceQueue(self: *Forwarder, state: anytype, output: u64, name: []const u8) u64 {
        if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
        var queue: u64 = VK_SYNTHETIC_QUEUE;
        var family_index: u32 = @truncate(state.regs.rsi);
        var queue_index: u32 = @truncate(state.regs.rdx);
        if (std.mem.eql(u8, name, "vkGetDeviceQueue2")) {
            const queue_info = state.regs.rsi;
            if (queue_info != 0 and state.guestMemoryConst(queue_info, 40) != null) {
                family_index = state.read32(queue_info + 20);
                queue_index = state.read32(queue_info + 24);
            }
        }
        if (self.real_vulkan.hasDevice()) {
            if (self.real_vulkan.fn_ptrs.get_device_queue) |get_queue| {
                var real_queue: abi.Queue = null;
                get_queue(self.real_vulkan.device.?, family_index, queue_index, &real_queue);
                if (real_queue != null) {
                    queue = @intFromPtr(real_queue.?);
                    HandleMap.allocOrFind(&self.real_vulkan.queue_map, queue, queue);
                    if (family_index < self.real_vulkan.queue_family_count) {
                        if (self.real_vulkan.graphics_queue == null) self.real_vulkan.graphics_queue = real_queue;
                    }
                    self.vulkan_tiers.note(.queue, .real);
                }
            }
        }
        state.write64(output, queue);
        registerOpaqueHandle(state, queue, "Vulkan device queue");
        self.vulkan_queues_acquired +|= 1;
        if (self.vulkan_queues_acquired == 1) {
            machoCapturePrint(
                "macho-processor: Vulkan milestone: queue_acquired queue=0x{x} output=0x{x} via={s}\n",
                .{ queue, output, name },
            );
        }
        return 0;
    }

    fn getSemaphoreCounterValue(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const function = self.real_vulkan.fn_ptrs.get_semaphore_counter_value orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const semaphore = self.real_vulkan.realSemaphore(state.regs.rsi) orelse return vkErrorInitializationFailed();
        if (state.regs.rdx == 0 or state.guestMemory(state.regs.rdx, 8) == null) return vkErrorInitializationFailed();
        var value: u64 = 0;
        const result = function(self.real_vulkan.device.?, semaphore, &value);
        if (result == abi.SUCCESS) state.write64(state.regs.rdx, value);
        return @as(u32, @bitCast(result));
    }

    fn waitSemaphores(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const function = self.real_vulkan.fn_ptrs.wait_semaphores orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const guest_info = state.regs.rsi;
        var info: abi.SemaphoreWaitInfo = undefined;
        if (!copyGuestValue(abi.SemaphoreWaitInfo, state, guest_info, &info)) return vkErrorInitializationFailed();
        if (info.p_next != null or info.flags != 0 or info.semaphore_count > 32) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const semaphore_address = if (info.semaphores) |pointer| @intFromPtr(pointer) else 0;
        const value_address = if (info.values) |pointer| @intFromPtr(pointer) else 0;
        if ((info.semaphore_count != 0 and (semaphore_address == 0 or value_address == 0)) or
            (info.semaphore_count == 0 and (semaphore_address != 0 or value_address != 0))) return vkErrorInitializationFailed();
        var semaphores: [32]abi.Semaphore = [_]abi.Semaphore{0} ** 32;
        var values: [32]u64 = [_]u64{0} ** 32;
        if (!copyGuestStructs(abi.Semaphore, state, semaphore_address, info.semaphore_count, &semaphores) or
            !copyGuestStructs(u64, state, value_address, info.semaphore_count, &values)) return vkErrorInitializationFailed();
        for (semaphores[0..@as(usize, @intCast(info.semaphore_count))]) |*semaphore|
            semaphore.* = self.real_vulkan.realSemaphore(semaphore.*) orelse return vkErrorInitializationFailed();
        info.p_next = null;
        info.semaphores = if (info.semaphore_count == 0) null else &semaphores;
        info.values = if (info.semaphore_count == 0) null else &values;
        const result = function(self.real_vulkan.device.?, &info, state.regs.rdx);
        return @as(u32, @bitCast(result));
    }

    fn signalSemaphore(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const function = self.real_vulkan.fn_ptrs.signal_semaphore orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        var info: abi.SemaphoreSignalInfo = undefined;
        if (!copyGuestValue(abi.SemaphoreSignalInfo, state, state.regs.rsi, &info)) return vkErrorInitializationFailed();
        if (info.p_next != null) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        info.semaphore = self.real_vulkan.realSemaphore(info.semaphore) orelse return vkErrorInitializationFailed();
        info.p_next = null;
        const result = function(self.real_vulkan.device.?, &info);
        return @as(u32, @bitCast(result));
    }

    fn writeRealSurfaceCapabilities(self: *Forwarder, state: anytype, output: u64) u64 {
        if (state.guestMemory(output, @sizeOf(abi.SurfaceCapabilitiesKHR)) == null) return vkErrorInitializationFailed();
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return vkErrorInitializationFailed();
        const address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfaceCapabilitiesKHR") orelse return vkErrorInitializationFailed();
        const get_caps: abi.PfnGetPhysicalDeviceSurfaceCapabilitiesKHR = @ptrCast(@alignCast(address));
        var caps: abi.SurfaceCapabilitiesKHR = .{};
        const result = get_caps(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), self.real_vulkan.surface, &caps);
        self.noteRealVulkanResult(result, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
        if (result != abi.SUCCESS) return @as(u32, @bitCast(result));
        const bytes = state.guestMemory(output, @sizeOf(abi.SurfaceCapabilitiesKHR)).?;
        @memcpy(bytes, std.mem.asBytes(&caps));
        self.vulkan_tiers.note(.surface_capabilities, .real);
        return 0;
    }

    /// vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface,
    /// pSurfaceFormatCount, pSurfaceFormats): the count is rdx, the array rcx.
    ///
    /// The probe reports at most what the fill can deliver, so a caller that
    /// sizes its array from the probe always gets VK_SUCCESS back. Reporting
    /// the driver's full count and then truncating the fill is not a partial
    /// answer — it is a loop that never ends. The standard two-call idiom
    /// resizes to the count it was handed, is told VK_INCOMPLETE for an array
    /// that is exactly that size, and asks again with the same size forever.
    /// MoltenVK reports sixty formats for a Metal surface against a bridge
    /// table of sixteen, and Xenia's presenter span three billion interpreted
    /// instructions in that loop without ever leaving it.
    /// Clamp a driver enumeration to what the bridge's fixed table can return.
    ///
    /// Reported once per kind: a caller that sees a smaller list than the
    /// driver has is a fact worth one line, and the alternative — telling the
    /// guest the driver's count and then not delivering it — is what makes a
    /// two-call enumeration loop forever.
    fn boundSurfaceEnumeration(self: *Forwarder, driver_count: u32, kind: []const u8) u32 {
        const bound: u32 = MAX_SURFACE_ENUMERATION;
        if (driver_count <= bound) return driver_count;
        if (!self.surface_enumeration_bound_reported) {
            self.surface_enumeration_bound_reported = true;
            machoCapturePrint(
                "macho-processor: host reports {d} {s} but the bridge table holds {d}; the guest is told {d} so its enumeration terminates\n",
                .{ driver_count, kind, bound, bound },
            );
        }
        return bound;
    }

    fn enumerateRealSurfaceFormats(self: *Forwarder, state: anytype) u64 {
        const count_address = state.regs.rdx;
        if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return vkErrorInitializationFailed();
        const address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfaceFormatsKHR") orelse return vkErrorInitializationFailed();
        const get_formats: abi.PfnGetPhysicalDeviceSurfaceFormatsKHR = @ptrCast(@alignCast(address));
        const physical_device = self.real_vulkan.physical_device orelse return vkErrorInitializationFailed();
        var formats: [MAX_SURFACE_ENUMERATION]abi.SurfaceFormatKHR = [_]abi.SurfaceFormatKHR{.{}} ** MAX_SURFACE_ENUMERATION;
        var driver_count: u32 = 0;
        var result = get_formats(physical_device, self.real_vulkan.surface, &driver_count, null);
        self.noteRealVulkanResult(result, "vkGetPhysicalDeviceSurfaceFormatsKHR");
        if (result != abi.SUCCESS and result != abi.INCOMPLETE) return @as(u32, @bitCast(result));
        const available = self.boundSurfaceEnumeration(driver_count, "surface formats");
        if (state.regs.rcx == 0) {
            state.write32(count_address, available);
            return @as(u32, @bitCast(abi.SUCCESS));
        }
        const capacity = state.read32(count_address);
        const written: u32 = @min(capacity, available);
        var actual: u32 = 0;
        if (written != 0) {
            var host_count = written;
            result = get_formats(physical_device, self.real_vulkan.surface, &host_count, &formats);
            self.noteRealVulkanResult(result, "vkGetPhysicalDeviceSurfaceFormatsKHR");
            // VK_INCOMPLETE from the driver here only says it has more than
            // the bridge asked for, which is what the bridge asked for.
            if (result != abi.SUCCESS and result != abi.INCOMPLETE) return @as(u32, @bitCast(result));
            actual = @min(host_count, written);
            const span = @as(u64, actual) * @sizeOf(abi.SurfaceFormatKHR);
            if (span != 0 and state.guestMemory(state.regs.rcx, span) == null) return vkErrorInitializationFailed();
            for (0..actual) |index| {
                state.write32(state.regs.rcx + @as(u64, @intCast(index)) * 8, formats[index].format);
                state.write32(state.regs.rcx + @as(u64, @intCast(index)) * 8 + 4, formats[index].color_space);
            }
        }
        state.write32(count_address, actual);
        self.vulkan_tiers.note(.surface_formats, .real);
        return @as(u32, @bitCast(if (actual < available) abi.INCOMPLETE else abi.SUCCESS));
    }

    fn enumerateRealSurfacePresentModes(self: *Forwarder, state: anytype) u64 {
        const count_address = state.regs.rdx;
        if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return vkErrorInitializationFailed();
        const address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfacePresentModesKHR") orelse return vkErrorInitializationFailed();
        const get_modes: abi.PfnGetPhysicalDeviceSurfacePresentModesKHR = @ptrCast(@alignCast(address));
        var count: u32 = 0;
        var result = get_modes(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), self.real_vulkan.surface, &count, null);
        self.noteRealVulkanResult(result, "vkGetPhysicalDeviceSurfacePresentModesKHR");
        if (result != abi.SUCCESS and result != abi.INCOMPLETE) return @as(u32, @bitCast(result));
        const available = self.boundSurfaceEnumeration(count, "surface present modes");
        if (state.regs.rcx == 0) {
            state.write32(count_address, available);
            return @as(u32, @bitCast(abi.SUCCESS));
        }
        const capacity = state.read32(count_address);
        const written: u32 = @min(capacity, available);
        var modes: [MAX_SURFACE_ENUMERATION]u32 = [_]u32{0} ** MAX_SURFACE_ENUMERATION;
        var actual: u32 = 0;
        if (written != 0) {
            var host_count = written;
            result = get_modes(self.real_vulkan.physical_device.?, self.real_vulkan.surface, &host_count, &modes);
            self.noteRealVulkanResult(result, "vkGetPhysicalDeviceSurfacePresentModesKHR");
            if (result != abi.SUCCESS and result != abi.INCOMPLETE) return @as(u32, @bitCast(result));
            actual = @min(host_count, written);
            const span = @as(u64, actual) * 4;
            if (span != 0 and state.guestMemory(state.regs.rcx, span) == null) return vkErrorInitializationFailed();
            for (0..actual) |index| state.write32(state.regs.rcx + @as(u64, @intCast(index)) * 4, modes[index]);
        }
        state.write32(count_address, actual);
        self.vulkan_tiers.note(.surface_present_modes, .real);
        return @as(u32, @bitCast(if (actual < available) abi.INCOMPLETE else abi.SUCCESS));
    }

    fn writeRealSurfaceSupport(self: *Forwarder, state: anytype) u64 {
        const output = state.regs.rcx;
        if (output == 0 or state.guestMemory(output, 4) == null) return vkErrorInitializationFailed();
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return vkErrorInitializationFailed();
        const address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfaceSupportKHR") orelse return vkErrorInitializationFailed();
        const get_support: abi.PfnGetPhysicalDeviceSurfaceSupportKHR = @ptrCast(@alignCast(address));
        var supported: u32 = 0;
        const result = get_support(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), @truncate(state.regs.rsi), self.real_vulkan.surface, &supported);
        self.noteRealVulkanResult(result, "vkGetPhysicalDeviceSurfaceSupportKHR");
        if (result == abi.SUCCESS) state.write32(output, supported);
        return @as(u32, @bitCast(result));
    }

    fn beginCommandBuffer(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const real = self.real_vulkan.realCommandBuffer(state.regs.rdi) orelse return 0;
        const begin = self.real_vulkan.fn_ptrs.begin_command_buffer orelse return 0;
        var info: abi.CommandBufferBeginInfo = .{};
        var inheritance: abi.CommandBufferInheritanceInfo = .{};
        var inheritance_rendering: abi.CommandBufferInheritanceRenderingInfo = .{};
        var inheritance_color_formats: [8]u32 = undefined;
        if (state.regs.rsi != 0 and state.guestMemoryConst(state.regs.rsi, 24) != null) {
            var guest_info: abi.CommandBufferBeginInfo = undefined;
            if (!copyGuestValue(abi.CommandBufferBeginInfo, state, state.regs.rsi, &guest_info) or
                guest_info.s_type != abi.STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO or guest_info.p_next != null)
            {
                return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            }
            info.flags = guest_info.flags;
            if (guest_info.inheritance_info) |pointer| {
                const inheritance_address = @intFromPtr(pointer);
                if (!copyGuestValue(abi.CommandBufferInheritanceInfo, state, inheritance_address, &inheritance) or
                    inheritance.s_type != abi.STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO)
                {
                    return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                }
                if (inheritance.p_next) |next_pointer| {
                    const next_address = @intFromPtr(next_pointer);
                    if (!copyGuestValue(abi.CommandBufferInheritanceRenderingInfo, state, next_address, &inheritance_rendering) or
                        inheritance_rendering.s_type != abi.STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO or
                        inheritance_rendering.p_next != null or
                        inheritance_rendering.color_attachment_count > inheritance_color_formats.len)
                    {
                        return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                    }
                    const formats_address = if (inheritance_rendering.color_attachment_formats) |formats| @intFromPtr(formats) else 0;
                    if (!copyGuestStructs(u32, state, formats_address, inheritance_rendering.color_attachment_count, &inheritance_color_formats)) {
                        return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                    }
                    inheritance_rendering.p_next = null;
                    inheritance_rendering.color_attachment_formats = if (inheritance_rendering.color_attachment_count == 0)
                        null
                    else
                        &inheritance_color_formats;
                    inheritance.p_next = &inheritance_rendering;
                } else {
                    inheritance.p_next = null;
                }
                if (inheritance.render_pass != 0) inheritance.render_pass = self.real_vulkan.realRenderPass(inheritance.render_pass) orelse return vkErrorInitializationFailed();
                if (inheritance.framebuffer != 0) inheritance.framebuffer = self.real_vulkan.realFramebuffer(inheritance.framebuffer) orelse return vkErrorInitializationFailed();
                info.inheritance_info = &inheritance;
            } else {
                info.inheritance_info = null;
            }
        }
        const result = begin(real, &info);
        self.noteRealVulkanResult(result, "vkBeginCommandBuffer");
        if (result == abi.SUCCESS) self.vulkan_tiers.note(.command_recording, .real);
        return @as(u32, @bitCast(result));
    }

    fn endCommandBuffer(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const real = self.real_vulkan.realCommandBuffer(state.regs.rdi) orelse return 0;
        const end = self.real_vulkan.fn_ptrs.end_command_buffer orelse return 0;
        const result = end(real);
        self.noteRealVulkanResult(result, "vkEndCommandBuffer");
        if (result == abi.SUCCESS) self.vulkan_tiers.note(.command_recording, .real);
        return @as(u32, @bitCast(result));
    }

    fn resetCommandBuffer(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const real = self.real_vulkan.realCommandBuffer(state.regs.rdi) orelse return 0;
        const reset = self.real_vulkan.fn_ptrs.reset_command_buffer orelse return 0;
        const result = reset(real, @truncate(state.regs.rsi));
        self.noteRealVulkanResult(result, "vkResetCommandBuffer");
        if (result == abi.SUCCESS) self.vulkan_tiers.note(.command_recording, .real);
        return @as(u32, @bitCast(result));
    }

    fn resetCommandPool(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const pool = self.real_vulkan.realCommandPool(state.regs.rsi) orelse return 0;
        const reset = self.real_vulkan.fn_ptrs.reset_command_pool orelse return 0;
        const result = reset(self.real_vulkan.device.?, pool, @truncate(state.regs.rdx));
        self.noteRealVulkanResult(result, "vkResetCommandPool");
        if (result == abi.SUCCESS) self.vulkan_tiers.note(.command_recording, .real);
        return @as(u32, @bitCast(result));
    }

    fn resetDescriptorPool(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const synthetic_pool = state.regs.rsi;
        const pool = self.real_vulkan.realDescriptorPool(synthetic_pool) orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const reset = self.real_vulkan.fn_ptrs.reset_descriptor_pool orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const result = reset(self.real_vulkan.device orelse return vkErrorInitializationFailed(), pool, @truncate(state.regs.rdx));
        if (result == abi.SUCCESS) self.vulkan_tiers.note(.descriptor_set, .real);
        return @as(u32, @bitCast(result));
    }

    fn waitForFences(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const count: u32 = @min(@as(u32, @truncate(state.regs.rsi)), 256);
        if (count == 0 or state.regs.rdx == 0) return abi.SUCCESS;
        if (state.guestMemoryConst(state.regs.rdx, @as(u64, count) * 8) == null) return vkErrorInitializationFailed();
        const wait = self.real_vulkan.fn_ptrs.wait_for_fences orelse return abi.SUCCESS;
        var fences: [256]abi.Fence = [_]abi.Fence{0} ** 256;
        for (0..count) |index| fences[index] = self.real_vulkan.realFence(state.read64(state.regs.rdx + @as(u64, @intCast(index)) * 8)) orelse return vkErrorInitializationFailed();
        const result = wait(self.real_vulkan.device.?, count, &fences, @truncate(state.regs.rcx), state.regs.r8);
        self.noteRealVulkanResult(result, "vkWaitForFences");
        if (result == abi.SUCCESS) {
            for (0..count) |index| {
                self.noteNativeFenceComplete(state, state.read64(state.regs.rdx + @as(u64, @intCast(index)) * 8));
            }
        }
        return @as(u32, @bitCast(result));
    }

    fn resetFences(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const count: u32 = @min(@as(u32, @truncate(state.regs.rsi)), 256);
        if (count == 0 or state.regs.rdx == 0) return abi.SUCCESS;
        if (state.guestMemoryConst(state.regs.rdx, @as(u64, count) * 8) == null) return vkErrorInitializationFailed();
        const reset = self.real_vulkan.fn_ptrs.reset_fences orelse return abi.SUCCESS;
        var fences: [256]abi.Fence = [_]abi.Fence{0} ** 256;
        for (0..count) |index| fences[index] = self.real_vulkan.realFence(state.read64(state.regs.rdx + @as(u64, @intCast(index)) * 8)) orelse return vkErrorInitializationFailed();
        const result = reset(self.real_vulkan.device.?, count, &fences);
        self.noteRealVulkanResult(result, "vkResetFences");
        return @as(u32, @bitCast(result));
    }

    fn getFenceStatus(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const fence = self.real_vulkan.realFence(state.regs.rsi) orelse return 0;
        const status = self.real_vulkan.fn_ptrs.get_fence_status orelse return 0;
        const result = status(self.real_vulkan.device.?, fence);
        self.noteRealVulkanResult(result, "vkGetFenceStatus");
        if (result == abi.SUCCESS) self.noteNativeFenceComplete(state, state.regs.rsi);
        return @as(u32, @bitCast(result));
    }

    fn getQueryPoolResults(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |lost| return lost;
        const pool = self.real_vulkan.realQueryPool(state.regs.rsi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        const get_results = self.real_vulkan.fn_ptrs.get_query_pool_results orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const data_size: u64 = state.regs.r8;
        const guest_output = state.regs.r9;
        if (guest_output == 0 or data_size == 0 or data_size > 64 * 1024) return @as(u32, @bitCast(abi.ERROR_OUT_OF_HOST_MEMORY));
        const guest_bytes = state.guestMemory(guest_output, data_size) orelse return vkErrorInitializationFailed();
        var data: [64 * 1024]u8 = undefined;
        const result = get_results(
            self.real_vulkan.device orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED)),
            pool,
            @truncate(state.regs.rdx),
            @truncate(state.regs.rcx),
            @intCast(data_size),
            @ptrCast(&data),
            guestStackArg(state, 0),
            @truncate(guestStackArg(state, 1)),
        );
        self.noteRealVulkanResult(result, "vkGetQueryPoolResults");
        if (result == abi.SUCCESS or result == abi.INCOMPLETE) @memcpy(guest_bytes, data[0..@as(usize, @intCast(data_size))]);
        return @as(u32, @bitCast(result));
    }

    fn resetQueryPool(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const pool = self.real_vulkan.realQueryPool(state.regs.rsi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        const reset = self.real_vulkan.fn_ptrs.reset_query_pool orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        reset(self.real_vulkan.device orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED)), pool, @truncate(state.regs.rdx), @truncate(state.regs.rcx));
        return abi.SUCCESS;
    }

    fn deviceWaitIdle(self: *Forwarder, _: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const wait = self.real_vulkan.fn_ptrs.device_wait_idle orelse return 0;
        const result = wait(self.real_vulkan.device orelse return 0);
        self.noteRealVulkanResult(result, "vkDeviceWaitIdle");
        return @as(u32, @bitCast(result));
    }

    fn queueWaitIdle(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const wait = self.real_vulkan.fn_ptrs.queue_wait_idle orelse return 0;
        const queue = self.real_vulkan.realQueue(state.regs.rdi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        const result = wait(queue);
        self.noteRealVulkanResult(result, "vkQueueWaitIdle");
        return @as(u32, @bitCast(result));
    }

    fn copyMappedBytes(self: *Forwarder, state: anytype, memory: u64, offset: u64, requested_size: u64, to_host: bool) bool {
        const record = self.findVulkanMemoryRecord(memory) orelse return false;
        const host_ptr = record.host_mapped_ptr orelse return false;
        if (offset < record.mapped_offset) return false;
        const host_offset = offset - record.mapped_offset;
        if (host_offset > record.host_mapped_size) return false;
        const available = record.host_mapped_size - host_offset;
        const allocation_available = record.requested_size -| offset;
        const size = if (requested_size == abi.WHOLE_SIZE) @min(available, allocation_available) else @min(@min(requested_size, available), allocation_available);
        if (size == 0) return true;
        const length: usize = @intCast(size);
        const host_bytes: []u8 = @as([*]u8, @ptrCast(host_ptr))[host_offset..][0..length];
        if (to_host) {
            const guest = state.guestMemoryConst(record.mapped_base + offset, size) orelse return false;
            @memcpy(host_bytes, guest[0..length]);
        } else {
            const guest = state.guestMemory(record.mapped_base + offset, size) orelse return false;
            @memcpy(guest[0..length], host_bytes);
        }
        return true;
    }

    /// Guest mappings are Rosette-owned shadow windows, not the pointer the
    /// native driver returned.  Coherent Vulkan memory therefore still needs
    /// an explicit shadow-to-host copy before a queue submission; relying on
    /// `vkFlushMappedMemoryRanges` alone loses titles that correctly omit a
    /// flush for HOST_COHERENT allocations.
    fn uploadMappedMemoryBeforeSubmit(self: *Forwarder, state: anytype) bool {
        for (self.vulkan_memory_records) |record| {
            if (record.handle == 0 or record.host_mapped_ptr == null or record.host_mapped_size == 0) continue;
            if (!self.copyMappedBytes(state, record.handle, record.mapped_offset, record.host_mapped_size, true)) {
                self.vulkan_shadow_upload_failures +|= 1;
                return false;
            }
            self.vulkan_shadow_uploads +|= 1;
        }
        return true;
    }

    fn flushMappedMemoryRanges(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |lost| return lost;
        const count: u32 = @min(@as(u32, @truncate(state.regs.rsi)), 32);
        if (count == 0) return abi.SUCCESS;
        if (state.regs.rdx == 0 or state.guestMemoryConst(state.regs.rdx, @as(u64, count) * @sizeOf(abi.MappedMemoryRange)) == null) return vkErrorInitializationFailed();
        var ranges: [32]abi.MappedMemoryRange = [_]abi.MappedMemoryRange{.{}} ** 32;
        for (0..count) |index| {
            const address = state.regs.rdx + @as(u64, @intCast(index)) * @sizeOf(abi.MappedMemoryRange);
            const memory = state.read64(address + 16);
            const offset = state.read64(address + 24);
            const size = state.read64(address + 32);
            if (!self.copyMappedBytes(state, memory, offset, size, true)) return vkErrorInitializationFailed();
            ranges[index] = .{ .memory = self.real_vulkan.realMemory(memory) orelse return vkErrorInitializationFailed(), .offset = offset, .size = size };
        }
        const flush = self.real_vulkan.fn_ptrs.flush_mapped_memory_ranges orelse return 0;
        const result = flush(self.real_vulkan.device.?, count, &ranges);
        self.noteRealVulkanResult(result, "vkFlushMappedMemoryRanges");
        return @as(u32, @bitCast(result));
    }

    fn invalidateMappedMemoryRanges(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |lost| return lost;
        const count: u32 = @min(@as(u32, @truncate(state.regs.rsi)), 32);
        if (count == 0) return abi.SUCCESS;
        if (state.regs.rdx == 0 or state.guestMemoryConst(state.regs.rdx, @as(u64, count) * @sizeOf(abi.MappedMemoryRange)) == null) return vkErrorInitializationFailed();
        var ranges: [32]abi.MappedMemoryRange = [_]abi.MappedMemoryRange{.{}} ** 32;
        for (0..count) |index| {
            const address = state.regs.rdx + @as(u64, @intCast(index)) * @sizeOf(abi.MappedMemoryRange);
            const memory = state.read64(address + 16);
            const offset = state.read64(address + 24);
            const size = state.read64(address + 32);
            ranges[index] = .{ .memory = self.real_vulkan.realMemory(memory) orelse return vkErrorInitializationFailed(), .offset = offset, .size = size };
        }
        const invalidate = self.real_vulkan.fn_ptrs.invalidate_mapped_memory_ranges;
        const result = if (invalidate) |fn_ptr| fn_ptr(self.real_vulkan.device.?, count, &ranges) else abi.SUCCESS;
        self.noteRealVulkanResult(result, "vkInvalidateMappedMemoryRanges");
        if (result != abi.SUCCESS) return @as(u32, @bitCast(result));
        for (0..count) |index| {
            const address = state.regs.rdx + @as(u64, @intCast(index)) * @sizeOf(abi.MappedMemoryRange);
            if (!self.copyMappedBytes(state, state.read64(address + 16), state.read64(address + 24), state.read64(address + 32), false)) return vkErrorInitializationFailed();
        }
        return 0;
    }

    fn unmapMemory(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const memory = state.regs.rsi;
        if (self.real_vulkan.realMemory(memory)) |real_memory| {
            if (self.real_vulkan.fn_ptrs.unmap_memory) |unmap| unmap(self.real_vulkan.device.?, real_memory);
        }
        if (self.findVulkanMemoryRecord(memory)) |record| {
            record.host_mapped_ptr = null;
            record.host_mapped_size = 0;
        }
        return 0;
    }

    fn ensureNativeVulkanInstance(self: *Forwarder, library_token: u64) i32 {
        if (self.native_vulkan_instance != null) {
            return if (self.native_vulkan_library_token == library_token) 0 else vkErrorInitializationFailedSigned();
        }
        const library = self.materializeNativeVulkanLibrary(library_token) orelse return vkErrorInitializationFailedSigned();
        const create_address = dlsym(library, "vkCreateInstance") orelse return vkErrorInitializationFailedSigned();
        const create_instance: PfnVkCreateInstance = @ptrCast(@alignCast(create_address));
        const application_info = VkApplicationInfo{
            .s_type = VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .p_next = null,
            .application_name = "Rosette Mach-O Native Presenter",
            .application_version = 1,
            .engine_name = "Rosette",
            .engine_version = 1,
            .api_version = 0x0040_2000,
        };
        const native_extension_names = [_][*:0]const u8{
            "VK_EXT_metal_surface",
            "VK_KHR_portability_enumeration",
        };
        var create_info = VkInstanceCreateInfo{
            .s_type = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .p_next = null,
            .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
            .application_info = &application_info,
            .enabled_layer_count = 0,
            .enabled_layer_names = null,
            .enabled_extension_count = native_extension_names.len,
            .enabled_extension_names = &native_extension_names,
        };
        self.native_vulkan_instance_attempts +|= 1;
        var instance: ?*anyopaque = null;
        var result = create_instance(&create_info, null, &instance);
        if (result != 0) {
            // Some Vulkan-on-Metal loaders expose the Metal surface extension
            // without requiring portability enumeration. Retry that minimal
            // profile before treating the native binding as unavailable.
            create_info.flags = 0;
            create_info.enabled_extension_count = 1;
            result = create_instance(&create_info, null, &instance);
        }
        if (result != 0 or instance == null) {
            self.native_vulkan_failures +|= 1;
            machoCapturePrint(
                "macho-processor: native Vulkan instance creation failed: attempt={d} VkResult={d} library_token=0x{x}\n",
                .{ self.native_vulkan_instance_attempts, result, library_token },
            );
            return if (result != 0) result else vkErrorInitializationFailedSigned();
        }
        self.native_vulkan_instance = instance;
        self.native_vulkan_library_token = library_token;
        self.negotiateRosetteGpuBoundary("native_instance_ready");
        machoCapturePrint(
            "macho-processor: native Vulkan shadow instance ready: instance=0x{x} library_token=0x{x} attempt={d}\n",
            .{ @intFromPtr(instance.?), library_token, self.native_vulkan_instance_attempts },
        );
        return 0;
    }

    fn createNativeMetalSurface(self: *Forwarder, state: anytype, library_token: u64) NativeSurfaceResult {
        const State = @typeInfo(@TypeOf(state)).pointer.child;
        if (!@hasDecl(State, "nativeMetalLayerHostPointer")) {
            return .{ .enforced = false, .result = 0, .surface = 0 };
        }
        const host_layer = state.nativeMetalLayerHostPointer();
        if (host_layer == 0) {
            self.native_vulkan_failures +|= 1;
            return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
        }
        const instance_result = self.ensureNativeVulkanInstance(library_token);
        if (instance_result != 0) {
            return .{ .enforced = true, .result = instance_result, .surface = 0 };
        }
        if (self.native_vulkan_surface != 0) {
            return .{ .enforced = true, .result = 0, .surface = self.native_vulkan_surface };
        }
        const library = self.guestLibrary(library_token) orelse {
            return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
        };
        const get_proc_address = dlsym(library, "vkGetInstanceProcAddr") orelse {
            return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
        };
        const get_proc: PfnVkGetInstanceProcAddr = @ptrCast(@alignCast(get_proc_address));
        const create_address = get_proc(self.native_vulkan_instance, "vkCreateMetalSurfaceEXT") orelse
            dlsym(library, "vkCreateMetalSurfaceEXT") orelse {
            self.native_vulkan_failures +|= 1;
            return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
        };
        const create_surface: PfnVkCreateMetalSurfaceEXT = @ptrCast(@alignCast(create_address));
        const create_info = VkMetalSurfaceCreateInfoEXT{
            .s_type = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
            .p_next = null,
            .flags = 0,
            .layer = @ptrFromInt(host_layer),
        };
        self.native_vulkan_surface_attempts +|= 1;
        var surface: u64 = 0;
        const result = create_surface(self.native_vulkan_instance, &create_info, null, &surface);
        if (result != 0 or surface == 0) {
            self.native_vulkan_failures +|= 1;
            machoCapturePrint(
                "macho-processor: native vkCreateMetalSurfaceEXT failed: attempt={d} VkResult={d} CAMetalLayer=0x{x} surface=0x{x}\n",
                .{ self.native_vulkan_surface_attempts, result, host_layer, surface },
            );
            return .{ .enforced = true, .result = if (result != 0) result else vkErrorInitializationFailedSigned(), .surface = 0 };
        }
        self.native_vulkan_surface = surface;
        self.negotiateRosetteGpuBoundary("native_surface_ready");
        machoCapturePrint(
            "macho-processor: native vkCreateMetalSurfaceEXT succeeded: attempt={d} instance=0x{x} CAMetalLayer=0x{x} VkSurfaceKHR=0x{x}\n",
            .{ self.native_vulkan_surface_attempts, @intFromPtr(self.native_vulkan_instance.?), host_layer, surface },
        );
        return .{ .enforced = true, .result = 0, .surface = surface };
    }

    fn destroyNativeSurface(self: *Forwarder) void {
        if (self.native_vulkan_surface == 0 or self.native_vulkan_instance == null) return;
        const library = self.guestLibrary(self.native_vulkan_library_token) orelse return;
        const get_proc_address = dlsym(library, "vkGetInstanceProcAddr") orelse return;
        const get_proc: PfnVkGetInstanceProcAddr = @ptrCast(@alignCast(get_proc_address));
        const destroy_address = get_proc(self.native_vulkan_instance, "vkDestroySurfaceKHR") orelse return;
        const destroy_surface: PfnVkDestroySurfaceKHR = @ptrCast(@alignCast(destroy_address));
        destroy_surface(self.native_vulkan_instance, self.native_vulkan_surface, null);
        self.native_vulkan_surface = 0;
    }

    // -----------------------------------------------------------------------
    // Phase 1: Real Vulkan object creation
    // -----------------------------------------------------------------------

    /// Materialise the Vulkan library handle for the guest. This is the same
    /// dlopen the native presenter uses; both share one host library.
    fn materializeVulkanLibraryForReal(self: *Forwarder, library_token: u64) ?*anyopaque {
        return self.materializeNativeVulkanLibrary(library_token);
    }

    fn queryHostInstanceExtensions(self: *Forwarder, library: *anyopaque) bool {
        if (self.real_vulkan.host_instance_extensions_known) return true;
        const address = dlsym(library, "vkEnumerateInstanceExtensionProperties") orelse return false;
        const enumerate: abi.PfnEnumerateInstanceExtensionProperties = @ptrCast(@alignCast(address));
        var count: u32 = 0;
        const first = enumerate(null, &count, null);
        if (first != abi.SUCCESS and first != abi.INCOMPLETE) return false;
        const capacity: u32 = @intCast(self.real_vulkan.host_instance_extensions.len);
        var requested: u32 = @min(count, capacity);
        if (requested != 0) {
            const second = enumerate(null, &requested, &self.real_vulkan.host_instance_extensions);
            if (second != abi.SUCCESS and second != abi.INCOMPLETE) return false;
        }
        self.real_vulkan.host_instance_extension_count = @min(requested, capacity);
        self.real_vulkan.host_instance_extensions_known = true;
        return true;
    }

    fn hostInstanceExtensionAvailable(self: *const Forwarder, name: []const u8) bool {
        if (!self.real_vulkan.host_instance_extensions_known) return true;
        for (self.real_vulkan.host_instance_extensions[0..self.real_vulkan.host_instance_extension_count]) |*property| {
            if (std.mem.eql(u8, property.name(), name)) return true;
        }
        return false;
    }

    /// Cache the selected physical device's extension list.  This is the one
    /// answer both the guest enumeration and our own vkCreateDevice
    /// negotiation need, and querying it once keeps those two views of the
    /// adapter from disagreeing.
    fn queryHostDeviceExtensions(self: *Forwarder) bool {
        if (self.real_vulkan.host_device_extensions_known) return true;
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return false;
        const instance = self.real_vulkan.instance orelse return false;
        const physical_device = self.real_vulkan.physical_device orelse return false;
        const address = get_proc(instance, "vkEnumerateDeviceExtensionProperties") orelse return false;
        const enumerate: abi.PfnEnumerateDeviceExtensionProperties = @ptrCast(@alignCast(address));
        var count: u32 = 0;
        const first = enumerate(physical_device, null, &count, null);
        if (first != abi.SUCCESS and first != abi.INCOMPLETE) return false;
        const capacity: u32 = @intCast(self.real_vulkan.host_device_extensions.len);
        if (count > capacity) {
            machoCapturePrint(
                "macho-processor: host reports {d} Vulkan device extensions but the bridge table holds {d}; the guest will see the first {d}\n",
                .{ count, capacity, capacity },
            );
        }
        var requested: u32 = @min(count, capacity);
        if (requested != 0) {
            const second = enumerate(physical_device, null, &requested, &self.real_vulkan.host_device_extensions);
            // VK_INCOMPLETE here only means the table was shorter than the
            // driver's list; the entries that were written are still valid.
            if (second != abi.SUCCESS and second != abi.INCOMPLETE) return false;
        }
        self.real_vulkan.host_device_extension_count = @min(requested, capacity);
        self.real_vulkan.host_device_extensions_known = true;
        machoCapturePrint(
            "macho-processor: host Vulkan device extensions cached: count={d}\n",
            .{self.real_vulkan.host_device_extension_count},
        );
        return true;
    }

    /// Decide which of `bridge_device_capabilities` this host can actually
    /// give us, and fill `scratch` with the feature nodes to enable.
    ///
    /// The device is negotiated at Vulkan 1.2, so the 1.3-promoted entry
    /// points the bridge forwards through — vkQueueSubmit2, the barrier-2 and
    /// dynamic-rendering commands, the extended dynamic state setters — exist
    /// only under their KHR/EXT names and only while these extensions are on.
    /// The guest never asks for them: it negotiated its own device against the
    /// same 1.2 and does not know they exist. That makes them the bridge's to
    /// request, not the guest's.
    fn negotiateBridgeCapabilities(self: *Forwarder, scratch: *BridgeCapabilityScratch) void {
        scratch.* = .{};
        if (!self.queryHostDeviceExtensions()) return;
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return;
        const instance = self.real_vulkan.instance orelse return;
        const physical_device = self.real_vulkan.physical_device orelse return;

        // Admit only what the host lists, then ask the driver which members of
        // each feature structure it actually supports.
        inline for (bridge_device_capabilities, 0..) |capability, index| {
            if (self.hostDeviceExtensionAvailable(capability.extension)) {
                scratch.admitted[index] = true;
                if (capability.feature_s_type != 0) {
                    const node = scratch.nodes[scratch.count][0..capability.feature_size];
                    @memset(node, 0);
                    std.mem.writeInt(u32, node[0..4], capability.feature_s_type, .little);
                    scratch.order[scratch.count] = index;
                    scratch.count += 1;
                }
            }
        }
        if (scratch.count == 0) return;

        const address = get_proc(instance, "vkGetPhysicalDeviceFeatures2") orelse {
            // Without the query the support of each member is unknown, and
            // enabling a member the driver does not have fails device
            // creation. Drop the feature-bearing capabilities entirely.
            scratch.* = .{};
            return;
        };
        linkBridgeCapabilityChain(scratch);
        const get_features: abi.PfnGetPhysicalDeviceFeatures2 = @ptrCast(@alignCast(address));
        var root: abi.PhysicalDeviceFeatures2 = .{};
        root.p_next = @ptrCast(&scratch.nodes[0]);
        get_features(physical_device, &root);
        // The driver has written VK_TRUE/VK_FALSE into every member. Handing
        // the structures back to vkCreateDevice unchanged enables exactly what
        // it reported and nothing else.
        var kept: usize = 0;
        for (0..scratch.count) |slot| {
            const capability = bridge_device_capabilities[scratch.order[slot]];
            const node = scratch.nodes[slot][0..capability.feature_size];
            var any_supported = false;
            var offset: usize = 16;
            while (offset + 4 <= node.len) : (offset += 4) {
                if (std.mem.readInt(u32, node[offset..][0..4], .little) != 0) any_supported = true;
            }
            if (any_supported) {
                if (kept != slot) {
                    @memcpy(&scratch.nodes[kept], &scratch.nodes[slot]);
                    scratch.order[kept] = scratch.order[slot];
                }
                kept += 1;
            } else {
                // The extension exists but the feature it gates is off, so its
                // entry points would resolve and then be illegal to call.
                scratch.admitted[scratch.order[slot]] = false;
            }
        }
        scratch.count = kept;
        linkBridgeCapabilityChain(scratch);
    }

    fn hostDeviceExtensions(self: *const Forwarder) []const abi.ExtensionProperties {
        if (!self.real_vulkan.host_device_extensions_known) return &.{};
        return self.real_vulkan.host_device_extensions[0..self.real_vulkan.host_device_extension_count];
    }

    fn hostDeviceExtensionAvailable(self: *const Forwarder, name: []const u8) bool {
        if (!self.real_vulkan.host_device_extensions_known) return true;
        for (self.hostDeviceExtensions()) |*property| {
            if (std.mem.eql(u8, property.name(), name)) return true;
        }
        return false;
    }

    fn enumerateInstanceExtensions(self: *Forwarder, state: anytype, library_token: u64) u64 {
        const library = self.materializeVulkanLibraryForReal(library_token);
        if (library == null or !self.queryHostInstanceExtensions(library.?)) return enumerateInstanceExtensionsSynthetic(state);
        // vkEnumerateInstanceExtensionProperties(pLayerName, pPropertyCount,
        // pProperties): the layer name is rdi, so the count is rsi and the
        // array is rdx.
        if (state.regs.rdi != 0) return enumerateNoLayerExtensions(state, state.regs.rsi);
        return writeExtensionPropertiesArray(state, state.regs.rsi, state.regs.rdx, self.real_vulkan.host_instance_extensions[0..self.real_vulkan.host_instance_extension_count]);
    }

    /// Ensure a real VkInstance exists for the guest's rendering pipeline.
    /// Called the first time the guest invokes vkCreateInstance. The instance
    /// is created with the extensions the guest requested plus any we need
    /// internally.
    fn ensureRealInstance(self: *Forwarder, state: anytype, library_token: u64, create_info: u64) i32 {
        if (self.real_vulkan.hasInstance()) {
            machoCapturePrint("macho-processor: ensureRealInstance: instance already exists, skipping\n", .{});
            return 0;
        }
        machoCapturePrint("macho-processor: ensureRealInstance: START create_info=0x{x} library_token=0x{x}\n", .{ create_info, library_token });
        const library = self.materializeVulkanLibraryForReal(library_token) orelse {
            machoCapturePrint("macho-processor: ensureRealInstance: FAILED to materialize Vulkan library\n", .{});
            return vkErrorInitializationFailedSigned();
        };
        // Retain the loader token for a narrowly-scoped lazy-device recovery
        // at swapchain creation. This is still the guest Vulkan library, not
        // the presenter's shadow device; it lets a compatibility thunk that
        // swallowed vkCreateDevice be repaired without mixing instances.
        self.native_vulkan_library_token = library_token;
        machoCapturePrint("macho-processor: ensureRealInstance: library materialized\n", .{});
        const get_proc_address = dlsym(library, "vkGetInstanceProcAddr") orelse {
            machoCapturePrint("macho-processor: ensureRealInstance: FAILED to find vkGetInstanceProcAddr\n", .{});
            return vkErrorInitializationFailedSigned();
        };
        self.real_vulkan.get_instance_proc_addr = @ptrCast(@alignCast(get_proc_address));
        machoCapturePrint("macho-processor: ensureRealInstance: vkGetInstanceProcAddr=0x{x}\n", .{@intFromPtr(get_proc_address)});
        // Read the guest's VkInstanceCreateInfo.  The pointer fields are at
        // +24/+40/+56; +8 is pNext.  Confusing those two was especially bad
        // here because a non-null pNext looked like an ApplicationInfo and
        // produced a plausible-but-invalid API version.
        const create_info_readable = create_info != 0 and state.guestMemoryConst(create_info, @sizeOf(abi.InstanceCreateInfo)) != null;
        const create_info_type = if (create_info_readable) state.read32(create_info) else 0;
        if (create_info_readable and create_info_type != abi.STRUCTURE_TYPE_INSTANCE_CREATE_INFO) {
            machoCapturePrint("macho-processor: ensureRealInstance: unexpected VkInstanceCreateInfo sType={d}\n", .{create_info_type});
            return abi.ERROR_INITIALIZATION_FAILED;
        }
        const guest_instance_flags = if (create_info_readable) state.read32(create_info + 16) else 0;
        const guest_extension_count = if (create_info_readable) @min(state.read32(create_info + 48), @as(u32, 32)) else 0;
        const guest_extension_array = if (create_info_readable) state.read64(create_info + 56) else 0;
        const guest_p_next = if (create_info_readable) state.read64(create_info + 8) else 0;
        if (guest_p_next != 0) {
            machoCapturePrint("macho-processor: ensureRealInstance: omitting unsupported instance pNext chain at 0x{x}; core instance creation remains safe\n", .{guest_p_next});
        }
        const app_info_addr = if (create_info_readable) state.read64(create_info + 24) else 0;
        var app_info: abi.ApplicationInfo = .{};
        if (readGuestApplicationInfo(state, app_info_addr)) |guest_app_info| {
            app_info = guest_app_info;
            machoCapturePrint("macho-processor: ensureRealInstance: guest api_version=0x{x}\n", .{app_info.api_version});
        } else {
            machoCapturePrint("macho-processor: ensureRealInstance: no guest VkApplicationInfo, using defaults\n", .{});
        }
        _ = self.queryHostInstanceExtensions(library);
        // Build a host-owned extension array.  Never pass the guest's string
        // pointers to the loader: they point into the translated address
        // space.  The two surface extensions are hard requirements for the
        // guest-backed path; portability and properties2 are optional because
        // recent Vulkan loaders promote or omit them.
        var extension_storage: [16][256]u8 = [_][256]u8{[_]u8{0} ** 256} ** 16;
        var host_extension_names: [16][*:0]const u8 = undefined;
        var extension_count: usize = 0;
        const add_extension = struct {
            fn add(
                owner: *Forwarder,
                name: []const u8,
                storage: *[16][256]u8,
                names: *[16][*:0]const u8,
                count: *usize,
            ) bool {
                if (name.len == 0 or name.len >= storage[0].len or count.* >= names.len) return false;
                for (names[0..count.*]) |existing| if (std.mem.eql(u8, std.mem.sliceTo(existing, 0), name)) return true;
                if (!owner.hostInstanceExtensionAvailable(name)) return false;
                @memset(&storage[count.*], 0);
                @memcpy(storage[count.*][0..name.len], name);
                names[count.*] = @ptrCast(&storage[count.*]);
                count.* += 1;
                return true;
            }
        }.add;
        if (!self.hostInstanceExtensionAvailable("VK_KHR_surface") or
            !self.hostInstanceExtensionAvailable("VK_EXT_metal_surface"))
        {
            machoCapturePrint("macho-processor: ensureRealInstance: host loader lacks VK_KHR_surface or VK_EXT_metal_surface\n", .{});
            return abi.ERROR_EXTENSION_NOT_PRESENT;
        }
        _ = add_extension(self, "VK_KHR_surface", &extension_storage, &host_extension_names, &extension_count);
        _ = add_extension(self, "VK_EXT_metal_surface", &extension_storage, &host_extension_names, &extension_count);
        if (self.hostInstanceExtensionAvailable("VK_KHR_portability_enumeration")) {
            _ = add_extension(self, "VK_KHR_portability_enumeration", &extension_storage, &host_extension_names, &extension_count);
        }
        if (self.hostInstanceExtensionAvailable("VK_KHR_get_physical_device_properties2")) {
            _ = add_extension(self, "VK_KHR_get_physical_device_properties2", &extension_storage, &host_extension_names, &extension_count);
        }
        if (guest_extension_count != 0 and guest_extension_array != 0 and
            state.guestMemoryConst(guest_extension_array, @as(u64, guest_extension_count) * 8) != null)
        {
            for (0..@as(usize, @intCast(guest_extension_count))) |index| {
                const extension_address = state.read64(guest_extension_array + @as(u64, @intCast(index)) * 8);
                const requested = state.guestCString(extension_address, 255) orelse continue;
                if (!self.hostInstanceExtensionAvailable(requested)) {
                    machoCapturePrint("macho-processor: ensureRealInstance: guest instance extension unavailable on host, omitting {s}\n", .{requested});
                    continue;
                }
                _ = add_extension(self, requested, &extension_storage, &host_extension_names, &extension_count);
            }
        }
        var instance_create_info = abi.InstanceCreateInfo{};
        instance_create_info.application_info = &app_info;
        instance_create_info.flags = if (extension_count != 0 and
            (guest_instance_flags & abi.INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR) != 0 and
            self.hostInstanceExtensionAvailable("VK_KHR_portability_enumeration"))
            abi.INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR
        else
            0;
        instance_create_info.enabled_extension_count = @intCast(extension_count);
        instance_create_info.enabled_extension_names = if (extension_count == 0) null else &host_extension_names;
        machoCapturePrint("macho-processor: ensureRealInstance: calling vkCreateInstance: extensions={d} host_extensions_known={s}\n", .{ extension_count, if (self.real_vulkan.host_instance_extensions_known) "YES" else "NO" });
        // Call the real vkCreateInstance.
        const create_fn: abi.PfnCreateInstance = @ptrCast(@alignCast(dlsym(library, "vkCreateInstance") orelse {
            machoCapturePrint("macho-processor: ensureRealInstance: FAILED to find vkCreateInstance\n", .{});
            return vkErrorInitializationFailedSigned();
        }));
        var real_instance: abi.Instance = null;
        const result = create_fn(&instance_create_info, null, &real_instance);
        if (result != 0 or real_instance == null) {
            self.real_vulkan.instance = null;
            machoCapturePrint(
                "macho-processor: ensureRealInstance: vkCreateInstance FAILED: VkResult={d} library_token=0x{x}\n",
                .{ result, library_token },
            );
            return if (result != 0) result else vkErrorInitializationFailedSigned();
        }
        machoCapturePrint("macho-processor: ensureRealInstance: vkCreateInstance SUCCEEDED instance=0x{x}\n", .{@intFromPtr(real_instance.?)});
        self.real_vulkan.instance = real_instance;
        // Resolve vkEnumeratePhysicalDevices via the real instance.
        const enum_phys: abi.PfnEnumeratePhysicalDevices = @ptrCast(@alignCast(self.real_vulkan.get_instance_proc_addr.?(real_instance, "vkEnumeratePhysicalDevices") orelse {
            machoCapturePrint("macho-processor: ensureRealInstance: FAILED to resolve vkEnumeratePhysicalDevices\n", .{});
            return vkErrorInitializationFailedSigned();
        }));
        // Enumerate physical devices (first call: count).
        var phys_count: u32 = 0;
        _ = enum_phys(real_instance, &phys_count, null);
        machoCapturePrint("macho-processor: ensureRealInstance: physical device count={d}\n", .{phys_count});
        if (phys_count == 0) {
            machoCapturePrint("macho-processor: ensureRealInstance: 0 physical devices, FAILED\n", .{});
            return vkErrorInitializationFailedSigned();
        }
        // The second enumeration writes through the caller-provided count.
        // Keep that count bounded to the fixed host-owned array; passing the
        // unbounded first-call count here lets a loader with more than eight
        // adapters walk past `phys_devices` before we select the first one.
        var phys_devices: [8]abi.PhysicalDevice = [_]abi.PhysicalDevice{null} ** 8;
        var exposed_phys_count: u32 = @min(phys_count, @as(u32, @intCast(phys_devices.len)));
        const enumerate_result = enum_phys(real_instance, &exposed_phys_count, &phys_devices);
        if (enumerate_result != abi.SUCCESS and enumerate_result != abi.INCOMPLETE) {
            machoCapturePrint("macho-processor: ensureRealInstance: physical device enumeration FAILED: VkResult={d}\n", .{enumerate_result});
            return @as(i32, @bitCast(enumerate_result));
        }
        if (exposed_phys_count == 0 or phys_devices[0] == null) {
            machoCapturePrint("macho-processor: ensureRealInstance: bounded physical device enumeration returned no usable device\n", .{});
            return vkErrorInitializationFailedSigned();
        }
        // Select the first physical device (MoltenVK will only report one).
        self.real_vulkan.physical_device = phys_devices[0];
        machoCapturePrint("macho-processor: ensureRealInstance: selected physical_device=0x{x}\n", .{@intFromPtr(phys_devices[0].?)});
        // Query queue family properties.
        const get_queue_families: abi.PfnGetPhysicalDeviceQueueFamilyProperties = @ptrCast(@alignCast(self.real_vulkan.get_instance_proc_addr.?(real_instance, "vkGetPhysicalDeviceQueueFamilyProperties") orelse {
            machoCapturePrint("macho-processor: ensureRealInstance: FAILED to resolve vkGetPhysicalDeviceQueueFamilyProperties\n", .{});
            return vkErrorInitializationFailedSigned();
        }));
        var qf_count: u32 = 0;
        get_queue_families(phys_devices[0], &qf_count, null);
        self.real_vulkan.queue_family_count = @min(qf_count, 16);
        if (qf_count > 0) {
            get_queue_families(phys_devices[0], @constCast(&self.real_vulkan.queue_family_count), &self.real_vulkan.queue_family_properties);
        }
        machoCapturePrint("macho-processor: ensureRealInstance: queue_family_count={d}\n", .{self.real_vulkan.queue_family_count});
        // Query physical device memory properties.
        const get_mem_props: abi.PfnGetPhysicalDeviceMemoryProperties = @ptrCast(@alignCast(self.real_vulkan.get_instance_proc_addr.?(real_instance, "vkGetPhysicalDeviceMemoryProperties") orelse {
            machoCapturePrint("macho-processor: ensureRealInstance: FAILED to resolve vkGetPhysicalDeviceMemoryProperties\n", .{});
            return vkErrorInitializationFailedSigned();
        }));
        get_mem_props(phys_devices[0], &self.real_vulkan.physical_device_memory);
        machoCapturePrint("macho-processor: ensureRealInstance: memory_types={d} memory_heaps={d}\n", .{ self.real_vulkan.physical_device_memory.memory_type_count, self.real_vulkan.physical_device_memory.memory_heap_count });
        // Query physical device properties (fill the identity prefix).
        const get_props: abi.PfnGetPhysicalDeviceProperties = @ptrCast(@alignCast(self.real_vulkan.get_instance_proc_addr.?(real_instance, "vkGetPhysicalDeviceProperties") orelse {
            machoCapturePrint("macho-processor: ensureRealInstance: FAILED to resolve vkGetPhysicalDeviceProperties\n", .{});
            return vkErrorInitializationFailedSigned();
        }));
        get_props(phys_devices[0], &self.real_vulkan.physical_device_properties);
        const get_features: abi.PfnGetPhysicalDeviceFeatures = @ptrCast(@alignCast(self.real_vulkan.get_instance_proc_addr.?(real_instance, "vkGetPhysicalDeviceFeatures") orelse {
            machoCapturePrint("macho-processor: ensureRealInstance: FAILED to resolve vkGetPhysicalDeviceFeatures\n", .{});
            return vkErrorInitializationFailedSigned();
        }));
        get_features(phys_devices[0], &self.real_vulkan.physical_device_features);
        const identity: *abi.PhysicalDeviceIdentity = @ptrCast(@alignCast(&self.real_vulkan.physical_device_properties));
        machoCapturePrint(
            "macho-processor: ensureRealInstance: COMPLETE instance=0x{x} physical_device=0x{x} adapter={s} api=0x{x} queue_families={d} memory_types={d} memory_heaps={d}\n",
            .{
                @intFromPtr(real_instance.?),
                @intFromPtr(phys_devices[0].?),
                identity.name(),
                identity.api_version,
                self.real_vulkan.queue_family_count,
                self.real_vulkan.physical_device_memory.memory_type_count,
                self.real_vulkan.physical_device_memory.memory_heap_count,
            },
        );
        return 0;
    }

    /// Ensure a real VkDevice exists for the guest's rendering pipeline.
    /// Called the first time the guest invokes vkCreateDevice. Creates a real
    /// device on the physical device selected by ensureRealInstance, with the
    /// queue families the guest requested.
    fn ensureRealDevice(self: *Forwarder, state: anytype, library_token: u64, _: u64, device_create_info_addr: u64, output: u64) i32 {
        if (self.real_vulkan.device_lost) return abi.ERROR_DEVICE_LOST;
        if (self.real_vulkan.hasDevice()) {
            // Already created. Write the cached device handle.
            machoCapturePrint("macho-processor: ensureRealDevice: device already exists, writing cached handle 0x{x} to output 0x{x}\n", .{ @intFromPtr(self.real_vulkan.device.?), output });
            if (!publishVulkanDispatchableHandle(state, output, self.real_vulkan.device)) {
                machoCapturePrint("macho-processor: ensureRealDevice: cached device output is not writable pDevice=0x{x}\n", .{output});
                return vkErrorInitializationFailedSigned();
            }
            self.real_vulkan.guest_device_handle = state.read64(output);
            return 0;
        }
        machoCapturePrint("macho-processor: ensureRealDevice: START device_create_info=0x{x} output=0x{x}\n", .{ device_create_info_addr, output });
        if (!self.real_vulkan.hasInstance()) {
            machoCapturePrint("macho-processor: ensureRealDevice: no instance yet, creating one\n", .{});
            const inst_result = self.ensureRealInstance(state, library_token, 0);
            if (inst_result != 0) {
                machoCapturePrint("macho-processor: ensureRealDevice: instance creation FAILED VkResult={d}\n", .{inst_result});
                return inst_result;
            }
        }
        _ = self.materializeVulkanLibraryForReal(library_token) orelse {
            machoCapturePrint("macho-processor: ensureRealDevice: FAILED to materialize Vulkan library\n", .{});
            return vkErrorInitializationFailedSigned();
        };
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return vkErrorInitializationFailedSigned();
        const instance = self.real_vulkan.instance orelse return vkErrorInitializationFailedSigned();
        const phys_dev = self.real_vulkan.physical_device orelse {
            machoCapturePrint("macho-processor: ensureRealDevice: FAILED no physical device\n", .{});
            return vkErrorInitializationFailedSigned();
        };
        machoCapturePrint("macho-processor: ensureRealDevice: instance=0x{x} physical_device=0x{x}\n", .{ @intFromPtr(instance), @intFromPtr(phys_dev) });
        // Read the guest's VkDeviceCreateInfo.
        //
        // The layer arrays sit *between* the queue arrays and the extension
        // arrays, so enabledExtensionCount is at +48 and pEnabledFeatures at
        // +64 — not +32 and +48.  Reading the layer count as the extension
        // count is silent: layers are always zero here, so the bridge simply
        // forwards none of the guest's extensions and, because +48 then lands
        // on that same count word, no features either.  The guest goes on
        // believing it enabled both.  Take every offset from the ABI
        // declaration, which is layout-asserted at compile time.
        const device_create_info_extension_count_offset = @offsetOf(abi.DeviceCreateInfo, "enabled_extension_count");
        const device_create_info_extension_names_offset = @offsetOf(abi.DeviceCreateInfo, "enabled_extension_names");
        const device_create_info_features_offset = @offsetOf(abi.DeviceCreateInfo, "enabled_features");
        const device_create_info_queue_count_offset = @offsetOf(abi.DeviceCreateInfo, "queue_create_info_count");
        const device_create_info_queue_infos_offset = @offsetOf(abi.DeviceCreateInfo, "queue_create_infos");
        var queue_create_infos: [4]abi.DeviceQueueCreateInfo = undefined;
        var queue_count: u32 = 0;
        var priority_storage: [4][16]f32 = [_][16]f32{[_]f32{1.0} ** 16} ** 4;
        const guest_device_p_next = if (device_create_info_addr != 0 and state.guestMemoryConst(device_create_info_addr, 72) != null)
            state.read64(device_create_info_addr + 8)
        else
            0;
        if (device_create_info_addr != 0 and state.guestMemoryConst(device_create_info_addr, 72) != null) {
            const qci_count = state.read32(device_create_info_addr + device_create_info_queue_count_offset);
            const qci_addr = state.read64(device_create_info_addr + device_create_info_queue_infos_offset);
            machoCapturePrint("macho-processor: ensureRealDevice: VkDeviceCreateInfo qci_count={d} pQueueCreateInfos=0x{x}\n", .{ qci_count, qci_addr });
            const requested_count = @min(qci_count, 4);
            if (qci_addr != 0 and requested_count > 0) {
                const qci_size: u64 = 40; // VkDeviceQueueCreateInfo size
                for (0..requested_count) |i| {
                    const qci = qci_addr + @as(u64, @intCast(i)) * qci_size;
                    if (state.guestMemoryConst(qci, qci_size) == null) {
                        machoCapturePrint("macho-processor: ensureRealDevice: QCI[{d}] at 0x{x} NOT in guest memory, skipping\n", .{ i, qci });
                        continue;
                    }
                    // VkDeviceQueueCreateInfo layout (64-bit):
                    //   +0:  sType (4)   +8:  pNext (8)
                    //   +16: flags (4)  +20: queueFamilyIndex (4)
                    //   +24: queueCount (4)  +32: pQueuePriorities (8)
                    const qf_idx = state.read32(qci + 20); // queueFamilyIndex
                    const q_cnt = state.read32(qci + 24); // queueCount
                    machoCapturePrint("macho-processor: ensureRealDevice: QCI[{d}] family={d} count={d}\n", .{ i, qf_idx, q_cnt });
                    if (state.read64(qci + 8) != 0 or qf_idx >= self.real_vulkan.queue_family_count or q_cnt == 0 or queue_count >= queue_create_infos.len) continue;
                    var duplicate = false;
                    for (queue_create_infos[0..queue_count]) |existing| {
                        if (existing.queue_family_index == qf_idx) duplicate = true;
                    }
                    if (duplicate) continue;
                    const available = self.real_vulkan.queue_family_properties[qf_idx].queue_count;
                    const actual_queue_count: u32 = @min(@min(q_cnt, available), priority_storage[queue_count].len);
                    if (actual_queue_count == 0) continue;
                    const destination_index = queue_count;
                    queue_create_infos[destination_index] = .{
                        .queue_family_index = qf_idx,
                        .queue_count = actual_queue_count,
                        .queue_priorities = &priority_storage[destination_index],
                    };
                    // Try to use the guest's priority pointer if available.
                    const pri_addr = state.read64(qci + 32); // pQueuePriorities
                    if (pri_addr != 0 and state.guestMemoryConst(pri_addr, @as(u64, actual_queue_count) * 4) != null) {
                        for (0..@as(usize, @intCast(actual_queue_count))) |priority_index| {
                            priority_storage[destination_index][priority_index] = @bitCast(state.read32(pri_addr + @as(u64, @intCast(priority_index)) * 4));
                        }
                    }
                    queue_count += 1;
                }
            }
        }
        if (queue_count == 0) {
            var fallback_family: ?u32 = null;
            for (self.real_vulkan.queue_family_properties[0..self.real_vulkan.queue_family_count], 0..) |family, index| {
                if ((family.queue_flags & abi.QUEUE_GRAPHICS_BIT) != 0 and family.queue_count != 0) {
                    fallback_family = @intCast(index);
                    break;
                }
            }
            if (fallback_family == null) {
                for (self.real_vulkan.queue_family_properties[0..self.real_vulkan.queue_family_count], 0..) |family, index| {
                    if (family.queue_count != 0) {
                        fallback_family = @intCast(index);
                        break;
                    }
                }
            }
            if (fallback_family) |family| {
                queue_create_infos[0] = .{ .queue_family_index = family, .queue_count = 1, .queue_priorities = &priority_storage[0] };
                queue_count = 1;
                machoCapturePrint("macho-processor: ensureRealDevice: using fallback queue family={d}\n", .{family});
            }
        }
        if (queue_count == 0) {
            machoCapturePrint("macho-processor: ensureRealDevice: VkDeviceCreateInfo at 0x{x} not in guest memory or zero\n", .{device_create_info_addr});
        }
        // Build the real VkDeviceCreateInfo.
        var real_device_info: abi.DeviceCreateInfo = .{};
        real_device_info.queue_create_info_count = queue_count;
        if (queue_count > 0) {
            real_device_info.queue_create_infos = &queue_create_infos;
        }
        var requested_features: [220]u8 = undefined;
        const guest_features_addr = if (device_create_info_addr != 0) state.read64(device_create_info_addr + device_create_info_features_offset) else 0;
        if (guest_features_addr != 0 and state.guestMemoryConst(guest_features_addr, requested_features.len) != null) {
            @memcpy(&requested_features, state.guestMemoryConst(guest_features_addr, requested_features.len).?);
            for (&requested_features, self.real_vulkan.physical_device_features) |*requested, supported| requested.* &= supported;
            real_device_info.enabled_features = &requested_features;
            var enabled_feature_count: usize = 0;
            var offset: usize = 0;
            while (offset + 4 <= requested_features.len) : (offset += 4) {
                if (std.mem.readInt(u32, requested_features[offset..][0..4], .little) != 0) enabled_feature_count += 1;
            }
            machoCapturePrint(
                "macho-processor: ensureRealDevice: guest VkPhysicalDeviceFeatures at 0x{x}: {d} enabled after masking against the host\n",
                .{ guest_features_addr, enabled_feature_count },
            );
        } else if (device_create_info_addr != 0) {
            machoCapturePrint("macho-processor: ensureRealDevice: guest supplied no readable pEnabledFeatures (0x{x}); the device is created with core features off\n", .{guest_features_addr});
        }
        var feature_chain: FeatureChainScratch = .{};
        if (guest_device_p_next != 0) {
            if (!self.prepareDeviceFeatureChain(state, guest_device_p_next, &feature_chain)) {
                machoCapturePrint("macho-processor: ensureRealDevice: unsupported or unreadable device feature pNext chain at 0x{x}\n", .{guest_device_p_next});
                return abi.ERROR_FEATURE_NOT_PRESENT;
            }
            if (feature_chain.count != 0) real_device_info.p_next = @ptrCast(&feature_chain.nodes[feature_chain.order[0]]);
        }
        // Request only extensions the host actually exposes.  Passing a guest
        // extension-name pointer through is unsafe for the same reason as a
        // guest array pointer anywhere else in Vulkan: it is an address in the
        // translated address space, not a host C string.
        // Use the same cached device extension table the guest enumeration
        // answers from.  A short local probe here silently disables the
        // availability filter on any driver with a longer list than the probe
        // buffer, which is exactly when the filter matters.
        const host_extensions_known = self.queryHostDeviceExtensions();
        const available_extensions = self.hostDeviceExtensions();
        var extension_storage: [32][256]u8 = [_][256]u8{[_]u8{0} ** 256} ** 32;
        var device_extension_names: [32][*:0]const u8 = undefined;
        var extension_count: usize = 0;
        const add_extension = struct {
            fn add(
                name: []const u8,
                known: bool,
                available: []const abi.ExtensionProperties,
                storage: *[32][256]u8,
                names: *[32][*:0]const u8,
                count: *usize,
            ) void {
                if (name.len == 0 or count.* >= names.len) return;
                for (names[0..count.*]) |existing| if (std.mem.eql(u8, std.mem.sliceTo(existing, 0), name)) return;
                if (known) {
                    var found = false;
                    for (available) |property| {
                        if (std.mem.eql(u8, property.name(), name)) found = true;
                    }
                    if (!found) return;
                }
                if (name.len >= storage[count.*].len) return;
                @memset(&storage[count.*], 0);
                @memcpy(storage[count.*][0..name.len], name);
                names[count.*] = @ptrCast(&storage[count.*]);
                count.* += 1;
            }
        }.add;
        add_extension("VK_KHR_swapchain", host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count);
        add_extension("VK_KHR_portability_subset", host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count);
        add_extension("VK_KHR_maintenance1", host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count);
        if (device_create_info_addr != 0) {
            const requested_extension_count = state.read32(device_create_info_addr + device_create_info_extension_count_offset);
            const guest_extension_count = @min(requested_extension_count, @as(u32, @intCast(device_extension_names.len)));
            if (requested_extension_count > guest_extension_count) {
                machoCapturePrint(
                    "macho-processor: ensureRealDevice: guest requested {d} device extensions but the bridge negotiates at most {d}; the tail is not forwarded\n",
                    .{ requested_extension_count, guest_extension_count },
                );
            }
            const guest_extension_array = state.read64(device_create_info_addr + device_create_info_extension_names_offset);
            if (guest_extension_array != 0 and state.guestMemoryConst(guest_extension_array, @as(u64, guest_extension_count) * 8) != null) {
                for (0..@as(usize, @intCast(guest_extension_count))) |index| {
                    const string_address = state.read64(guest_extension_array + @as(u64, @intCast(index)) * 8);
                    const string = state.guestCString(string_address, 255) orelse continue;
                    if (host_extensions_known and !self.hostDeviceExtensionAvailable(string)) {
                        machoCapturePrint("macho-processor: ensureRealDevice: guest device extension unavailable on host, omitting {s}\n", .{string});
                        continue;
                    }
                    add_extension(string, host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count);
                }
            }
        }
        // Everything up to here is the guest's own device. What follows is
        // the bridge's: extensions Rosette needs so the entry points it
        // forwards through exist, negotiated against the host and enabled
        // together with the features that make them legal to call. Adding
        // them last keeps `guest_extension_boundary` an exact rollback point
        // if the driver refuses the combination.
        const guest_extension_boundary = extension_count;
        var bridge_capabilities: BridgeCapabilityScratch = .{};
        self.negotiateBridgeCapabilities(&bridge_capabilities);
        inline for (bridge_device_capabilities, 0..) |capability, index| {
            if (bridge_capabilities.admitted[index]) {
                add_extension(capability.extension, host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count);
            }
        }
        // The bridge's feature nodes go in front of the guest's own chain so
        // both reach the driver; the guest's chain is already host-owned by
        // this point, so neither half can carry a guest pointer.
        const guest_p_next_for_device = real_device_info.p_next;
        real_device_info.p_next = spliceBridgeCapabilityChain(&bridge_capabilities, guest_p_next_for_device);
        real_device_info.enabled_extension_count = @intCast(extension_count);
        real_device_info.enabled_extension_names = if (extension_count == 0) null else &device_extension_names;
        machoCapturePrint(
            "macho-processor: ensureRealDevice: calling vkCreateDevice: queues={d} extensions={d} (guest={d} bridge={d}) physical_device=0x{x}\n",
            .{ queue_count, extension_count, guest_extension_boundary, extension_count - guest_extension_boundary, @intFromPtr(phys_dev) },
        );
        inline for (bridge_device_capabilities, 0..) |capability, index| {
            if (bridge_capabilities.admitted[index]) {
                machoCapturePrint(
                    "macho-processor: ensureRealDevice: bridge capability {s} enabled for {s}\n",
                    .{ capability.extension, capability.provides },
                );
            } else {
                machoCapturePrint(
                    "macho-processor: ensureRealDevice: bridge capability {s} unavailable on this host; {s} stay absent\n",
                    .{ capability.extension, capability.provides },
                );
            }
        }
        for (0..queue_count) |i| {
            machoCapturePrint("macho-processor: ensureRealDevice:   queue[{d}]: family={d} count={d} priorities_ptr=0x{x}\n", .{ i, queue_create_infos[i].queue_family_index, queue_create_infos[i].queue_count, @intFromPtr(queue_create_infos[i].queue_priorities.?) });
        }
        // Create the real device.
        const create_fn: abi.PfnCreateDevice = @ptrCast(@alignCast(get_proc(instance, "vkCreateDevice") orelse {
            machoCapturePrint("macho-processor: ensureRealDevice: FAILED to resolve vkCreateDevice\n", .{});
            return vkErrorInitializationFailedSigned();
        }));
        var real_device: abi.Device = null;
        var result = create_fn(phys_dev, &real_device_info, null, &real_device);
        if ((result != 0 or real_device == null) and extension_count != guest_extension_boundary) {
            // Everything the bridge added is optional to the guest. If the
            // driver refuses the combination, the guest's own device is still
            // the thing that has to exist, so retry with exactly what the
            // guest asked for rather than losing the GPU over an extra
            // entry point.
            machoCapturePrint(
                "macho-processor: ensureRealDevice: vkCreateDevice refused the bridge capabilities (VkResult={d}); retrying with only what the guest requested\n",
                .{result},
            );
            real_device_info.p_next = guest_p_next_for_device;
            real_device_info.enabled_extension_count = @intCast(guest_extension_boundary);
            real_device_info.enabled_extension_names = if (guest_extension_boundary == 0) null else &device_extension_names;
            real_device = null;
            result = create_fn(phys_dev, &real_device_info, null, &real_device);
        }
        if (result != 0 or real_device == null) {
            machoCapturePrint(
                "macho-processor: ensureRealDevice: vkCreateDevice FAILED: VkResult={d} physical_device=0x{x} device=0x{x}\n",
                .{ result, @intFromPtr(phys_dev), @as(u64, 0) },
            );
            return if (result != 0) result else vkErrorInitializationFailedSigned();
        }
        machoCapturePrint("macho-processor: ensureRealDevice: vkCreateDevice SUCCEEDED device=0x{x}\n", .{@intFromPtr(real_device.?)});
        if (!publishVulkanDispatchableHandle(state, output, real_device)) {
            machoCapturePrint(
                "macho-processor: ensureRealDevice: refusing native device because guest pDevice=0x{x} is not writable\n",
                .{output},
            );
            const destroy_addr = get_proc(instance, "vkDestroyDevice") orelse return vkErrorInitializationFailedSigned();
            const destroy_fn: abi.PfnDestroyDevice = @ptrCast(@alignCast(destroy_addr));
            destroy_fn(real_device, null);
            return vkErrorInitializationFailedSigned();
        }
        self.real_vulkan.device = real_device;
        self.real_vulkan.device_lost = false;
        self.real_vulkan.device_loss_result = abi.SUCCESS;
        self.real_vulkan.guest_device_handle = state.read64(output);
        self.vulkan_logical_devices_created +|= 1;
        machoCapturePrint("macho-processor: ensureRealDevice: published device handle to guest pDevice=0x{x}\n", .{output});
        // Resolve device-level function pointers.
        machoCapturePrint("macho-processor: ensureRealDevice: resolving device function pointers...\n", .{});
        self.ensureRealDeviceFnPtrs(library_token);
        // Acquire queues.
        if (self.real_vulkan.fn_ptrs.get_device_queue) |get_queue| {
            machoCapturePrint("macho-processor: ensureRealDevice: acquiring queues via resolved vkGetDeviceQueue\n", .{});
            if (queue_count > 0) {
                get_queue(real_device, queue_create_infos[0].queue_family_index, 0, &self.real_vulkan.graphics_queue);
                machoCapturePrint("macho-processor: ensureRealDevice: graphics queue=0x{x} (family={d})\n", .{ @intFromPtr(@as(?*anyopaque, self.real_vulkan.graphics_queue)), queue_create_infos[0].queue_family_index });
            }
            if (queue_count > 1) {
                get_queue(real_device, queue_create_infos[1].queue_family_index, 0, &self.real_vulkan.compute_queue);
                machoCapturePrint("macho-processor: ensureRealDevice: compute queue=0x{x} (family={d})\n", .{ @intFromPtr(@as(?*anyopaque, self.real_vulkan.compute_queue)), queue_create_infos[1].queue_family_index });
            }
            if (queue_count > 2) {
                get_queue(real_device, queue_create_infos[2].queue_family_index, 0, &self.real_vulkan.transfer_queue);
                machoCapturePrint("macho-processor: ensureRealDevice: transfer queue=0x{x} (family={d})\n", .{ @intFromPtr(@as(?*anyopaque, self.real_vulkan.transfer_queue)), queue_create_infos[2].queue_family_index });
            }
        } else {
            machoCapturePrint("macho-processor: ensureRealDevice: WARNING vkGetDeviceQueue not resolved, queues not acquired\n", .{});
        }
        machoCapturePrint(
            "macho-processor: ensureRealDevice: COMPLETE device=0x{x} queues(graphics/compute/transfer)=0x{x}/0x{x}/0x{x} queue_families={d}\n",
            .{
                @intFromPtr(real_device.?),
                @intFromPtr(@as(?*anyopaque, self.real_vulkan.graphics_queue)),
                @intFromPtr(@as(?*anyopaque, self.real_vulkan.compute_queue)),
                @intFromPtr(@as(?*anyopaque, self.real_vulkan.transfer_queue)),
                queue_count,
            },
        );
        return 0;
    }

    /// Resolve all device-level function pointers from the real device.
    fn ensureRealDeviceFnPtrs(self: *Forwarder, _: u64) void {
        if (self.real_vulkan.fn_ptrs.resolved) return;
        const device = self.real_vulkan.device orelse return;
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return;
        const instance = self.real_vulkan.instance orelse return;
        machoCapturePrint("macho-processor: ensureRealDeviceFnPtrs: START device=0x{x} instance=0x{x}\n", .{ @intFromPtr(device), @intFromPtr(instance) });
        // Some device functions must be resolved via the device, not the
        // instance, because MoltenVK dispatches through the device's loader.
        const dpa: *const fn (abi.Device, [*:0]const u8) callconv(.c) ?*const anyopaque = @ptrCast(@alignCast(get_proc(instance, "vkGetDeviceProcAddr") orelse {
            machoCapturePrint("macho-processor: ensureRealDeviceFnPtrs: FAILED to resolve vkGetDeviceProcAddr\n", .{});
            return;
        }));
        machoCapturePrint("macho-processor: ensureRealDeviceFnPtrs: vkGetDeviceProcAddr=0x{x}\n", .{@intFromPtr(dpa)});
        // An entry point the device does not expose is not a failure. Most of
        // this table is core in Vulkan 1.3 or lives in an extension the guest
        // never enabled, and the negotiated device is 1.2: those absences are
        // the expected shape of the device, and each one is a fallback the
        // bridge already has. Collect them and report once, rather than
        // printing twenty lines that read like a broken loader.
        var resolved_count: u32 = 0;
        var absent_names: [2048]u8 = undefined;
        var absent_len: usize = 0;
        var absent_count: u32 = 0;
        const resolveFn = struct {
            fn r(
                dp: *const fn (abi.Device, [*:0]const u8) callconv(.c) ?*const anyopaque,
                dv: abi.Device,
                fn_ptr: anytype,
                name: [*:0]const u8,
                resolved: *u32,
                absent: *u32,
                names: []u8,
                names_len: *usize,
            ) void {
                if (dp(dv, name)) |addr| {
                    fn_ptr.* = @ptrCast(@alignCast(addr));
                    resolved.* += 1;
                    return;
                }
                absent.* += 1;
                const text = std.mem.sliceTo(name, 0);
                const separator: usize = if (names_len.* == 0) 0 else 2;
                if (names_len.* + separator + text.len > names.len) return;
                if (separator != 0) {
                    @memcpy(names[names_len.*..][0..2], ", ");
                    names_len.* += 2;
                }
                @memcpy(names[names_len.*..][0..text.len], text);
                names_len.* += text.len;
            }
        }.r;
        // A promoted entry point exists under whichever spelling this device
        // provides: the core name on a device new enough for it, otherwise the
        // KHR or EXT name of the extension it came from. Trying the spellings
        // in order and recording one absence for the whole group keeps the
        // report about capabilities rather than about names — per-name
        // accounting called an entry point absent even when its alias had just
        // resolved.
        const resolveAny = struct {
            fn r(
                dp: *const fn (abi.Device, [*:0]const u8) callconv(.c) ?*const anyopaque,
                dv: abi.Device,
                fn_ptr: anytype,
                names: []const [*:0]const u8,
                resolved: *u32,
                absent: *u32,
                absent_list: []u8,
                absent_list_len: *usize,
            ) void {
                for (names) |name| {
                    if (dp(dv, name)) |addr| {
                        fn_ptr.* = @ptrCast(@alignCast(addr));
                        resolved.* += 1;
                        return;
                    }
                }
                absent.* += 1;
                const text = std.mem.sliceTo(names[0], 0);
                const separator: usize = if (absent_list_len.* == 0) 0 else 2;
                if (absent_list_len.* + separator + text.len > absent_list.len) return;
                if (separator != 0) {
                    @memcpy(absent_list[absent_list_len.*..][0..2], ", ");
                    absent_list_len.* += 2;
                }
                @memcpy(absent_list[absent_list_len.*..][0..text.len], text);
                absent_list_len.* += text.len;
            }
        }.r;
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.get_device_queue, "vkGetDeviceQueue", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.get_semaphore_counter_value, "vkGetSemaphoreCounterValue", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.wait_semaphores, "vkWaitSemaphores", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.signal_semaphore, "vkSignalSemaphore", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_swapchain, "vkCreateSwapchainKHR", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_swapchain, "vkDestroySwapchainKHR", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.get_swapchain_images, "vkGetSwapchainImagesKHR", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.acquire_next_image, "vkAcquireNextImageKHR", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.queue_present, "vkQueuePresentKHR", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_command_pool, "vkCreateCommandPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_command_pool, "vkDestroyCommandPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.allocate_command_buffers, "vkAllocateCommandBuffers", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.free_command_buffers, "vkFreeCommandBuffers", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.begin_command_buffer, "vkBeginCommandBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.end_command_buffer, "vkEndCommandBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.reset_command_buffer, "vkResetCommandBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_semaphore, "vkCreateSemaphore", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_semaphore, "vkDestroySemaphore", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_fence, "vkCreateFence", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_fence, "vkDestroyFence", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.wait_for_fences, "vkWaitForFences", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.reset_fences, "vkResetFences", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.get_fence_status, "vkGetFenceStatus", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_query_pool, "vkCreateQueryPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_query_pool, "vkDestroyQueryPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.get_query_pool_results, "vkGetQueryPoolResults", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.reset_query_pool, "vkResetQueryPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.reset_command_pool, "vkResetCommandPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.queue_submit, "vkQueueSubmit", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.queue_submit2, &.{ "vkQueueSubmit2", "vkQueueSubmit2KHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.queue_bind_sparse, "vkQueueBindSparse", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.queue_wait_idle, "vkQueueWaitIdle", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.device_wait_idle, "vkDeviceWaitIdle", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_buffer, "vkCreateBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_buffer, "vkDestroyBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.get_buffer_memory_requirements, "vkGetBufferMemoryRequirements", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.get_device_buffer_memory_requirements, &.{ "vkGetDeviceBufferMemoryRequirements", "vkGetDeviceBufferMemoryRequirementsKHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.bind_buffer_memory, "vkBindBufferMemory", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_image, "vkCreateImage", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_image, "vkDestroyImage", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.get_image_memory_requirements, "vkGetImageMemoryRequirements", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.get_device_image_memory_requirements, &.{ "vkGetDeviceImageMemoryRequirements", "vkGetDeviceImageMemoryRequirementsKHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.bind_image_memory, "vkBindImageMemory", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.allocate_memory, "vkAllocateMemory", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.free_memory, "vkFreeMemory", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.map_memory, "vkMapMemory", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.unmap_memory, "vkUnmapMemory", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.flush_mapped_memory_ranges, "vkFlushMappedMemoryRanges", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.invalidate_mapped_memory_ranges, "vkInvalidateMappedMemoryRanges", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_device, "vkDestroyDevice", &resolved_count, &absent_count, &absent_names, &absent_len);
        // Object creation/destruction function pointers
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_sampler, "vkCreateSampler", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_sampler, "vkDestroySampler", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_descriptor_set_layout, "vkCreateDescriptorSetLayout", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_descriptor_set_layout, "vkDestroyDescriptorSetLayout", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_pipeline_layout, "vkCreatePipelineLayout", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_pipeline_layout, "vkDestroyPipelineLayout", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_shader_module, "vkCreateShaderModule", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_shader_module, "vkDestroyShaderModule", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_render_pass, "vkCreateRenderPass", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_render_pass, "vkDestroyRenderPass", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_framebuffer, "vkCreateFramebuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_framebuffer, "vkDestroyFramebuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_graphics_pipelines, "vkCreateGraphicsPipelines", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_compute_pipelines, "vkCreateComputePipelines", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_pipeline_cache, "vkCreatePipelineCache", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.get_pipeline_cache_data, "vkGetPipelineCacheData", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_pipeline_cache, "vkDestroyPipelineCache", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_descriptor_update_template, "vkCreateDescriptorUpdateTemplate", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_descriptor_update_template, "vkDestroyDescriptorUpdateTemplate", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.update_descriptor_set_with_template, "vkUpdateDescriptorSetWithTemplate", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_pipeline, "vkDestroyPipeline", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_descriptor_pool, "vkCreateDescriptorPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_descriptor_pool, "vkDestroyDescriptorPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.reset_descriptor_pool, "vkResetDescriptorPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.allocate_descriptor_sets, "vkAllocateDescriptorSets", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.free_descriptor_sets, "vkFreeDescriptorSets", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.update_descriptor_sets, "vkUpdateDescriptorSets", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_image_view, "vkCreateImageView", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_image_view, "vkDestroyImageView", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.create_buffer_view, "vkCreateBufferView", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.destroy_buffer_view, "vkDestroyBufferView", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_bind_pipeline, "vkCmdBindPipeline", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_execute_commands, "vkCmdExecuteCommands", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_bind_vertex_buffers, "vkCmdBindVertexBuffers", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_bind_index_buffer, "vkCmdBindIndexBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_bind_descriptor_sets, "vkCmdBindDescriptorSets", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_push_descriptor_set, &.{ "vkCmdPushDescriptorSetKHR", "vkCmdPushDescriptorSet" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_draw, "vkCmdDraw", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_draw_indexed, "vkCmdDrawIndexed", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_draw_indirect, "vkCmdDrawIndirect", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_draw_indexed_indirect, "vkCmdDrawIndexedIndirect", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_draw_indirect_count, &.{ "vkCmdDrawIndirectCount", "vkCmdDrawIndirectCountKHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_draw_indexed_indirect_count, &.{ "vkCmdDrawIndexedIndirectCount", "vkCmdDrawIndexedIndirectCountKHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_dispatch, "vkCmdDispatch", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_dispatch_indirect, "vkCmdDispatchIndirect", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_dispatch_base, "vkCmdDispatchBase", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_viewport, "vkCmdSetViewport", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_scissor, "vkCmdSetScissor", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_blend_constants, "vkCmdSetBlendConstants", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_depth_bias, "vkCmdSetDepthBias", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_depth_bounds, "vkCmdSetDepthBounds", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_depth_test_enable, &.{ "vkCmdSetDepthTestEnable", "vkCmdSetDepthTestEnableEXT" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_depth_write_enable, &.{ "vkCmdSetDepthWriteEnable", "vkCmdSetDepthWriteEnableEXT" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_depth_compare_op, &.{ "vkCmdSetDepthCompareOp", "vkCmdSetDepthCompareOpEXT" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_stencil_test_enable, &.{ "vkCmdSetStencilTestEnable", "vkCmdSetStencilTestEnableEXT" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_stencil_op, &.{ "vkCmdSetStencilOp", "vkCmdSetStencilOpEXT" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_primitive_restart_enable, &.{ "vkCmdSetPrimitiveRestartEnable", "vkCmdSetPrimitiveRestartEnableEXT" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_stencil_compare_mask, "vkCmdSetStencilCompareMask", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_stencil_write_mask, "vkCmdSetStencilWriteMask", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_set_stencil_reference, "vkCmdSetStencilReference", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_push_constants, "vkCmdPushConstants", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_begin_render_pass, "vkCmdBeginRenderPass", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_next_subpass, "vkCmdNextSubpass", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_end_render_pass, "vkCmdEndRenderPass", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_begin_render_pass2, &.{ "vkCmdBeginRenderPass2", "vkCmdBeginRenderPass2KHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_next_subpass2, &.{ "vkCmdNextSubpass2", "vkCmdNextSubpass2KHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_end_render_pass2, &.{ "vkCmdEndRenderPass2", "vkCmdEndRenderPass2KHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_begin_conditional_rendering, &.{"vkCmdBeginConditionalRenderingEXT"}, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_end_conditional_rendering, &.{"vkCmdEndConditionalRenderingEXT"}, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_begin_rendering, &.{ "vkCmdBeginRendering", "vkCmdBeginRenderingKHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_end_rendering, &.{ "vkCmdEndRendering", "vkCmdEndRenderingKHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_copy_buffer, "vkCmdCopyBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_copy_image, "vkCmdCopyImage", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_copy_buffer_to_image, "vkCmdCopyBufferToImage", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_copy_image_to_buffer, "vkCmdCopyImageToBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_blit_image, "vkCmdBlitImage", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_fill_buffer, "vkCmdFillBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_update_buffer, "vkCmdUpdateBuffer", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_resolve_image, "vkCmdResolveImage", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_clear_color_image, "vkCmdClearColorImage", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_clear_depth_stencil_image, "vkCmdClearDepthStencilImage", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_clear_attachments, "vkCmdClearAttachments", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_pipeline_barrier, "vkCmdPipelineBarrier", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveAny(dpa, device, &self.real_vulkan.fn_ptrs.cmd_pipeline_barrier2, &.{ "vkCmdPipelineBarrier2", "vkCmdPipelineBarrier2KHR" }, &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_begin_query, "vkCmdBeginQuery", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_end_query, "vkCmdEndQuery", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_reset_query_pool, "vkCmdResetQueryPool", &resolved_count, &absent_count, &absent_names, &absent_len);
        resolveFn(dpa, device, &self.real_vulkan.fn_ptrs.cmd_copy_query_pool_results, "vkCmdCopyQueryPoolResults", &resolved_count, &absent_count, &absent_names, &absent_len);
        self.real_vulkan.fn_ptrs.resolved = true;
        machoCapturePrint(
            "macho-processor: ensureRealDeviceFnPtrs: COMPLETE resolved={d} absent={d}\n",
            .{ resolved_count, absent_count },
        );
        if (absent_count != 0) {
            machoCapturePrint(
                "macho-processor: ensureRealDeviceFnPtrs: absent on this device: {s}\n",
                .{absent_names[0..absent_len]},
            );
            machoCapturePrint(
                "macho-processor: ensureRealDeviceFnPtrs: an absence here means no extension this host exposes provides the entry point under any spelling; everything the host could provide was negotiated at device creation\n",
                .{},
            );
        }
    }

    fn noteRealVulkanResult(self: *Forwarder, result: abi.Result, operation: []const u8) void {
        if (result != abi.ERROR_DEVICE_LOST) return;
        const first = !self.real_vulkan.device_lost;
        self.real_vulkan.device_lost = true;
        self.real_vulkan.device_loss_result = result;
        self.vulkan_device_lost_events +|= 1;
        if (first) {
            machoCapturePrint(
                "macho-processor: Vulkan device lost: operation={s} result={d}; native guest work is quarantined until the guest tears down and recreates its VkDevice\n",
                .{ operation, result },
            );
        }
    }

    fn realDeviceLostResult(self: *const Forwarder) ?u64 {
        if (!self.real_vulkan.device_lost) return null;
        return @as(u32, @bitCast(abi.ERROR_DEVICE_LOST));
    }

    fn noteNativeFenceComplete(self: *Forwarder, state: anytype, synthetic_fence: u64) void {
        if (synthetic_fence == 0) return;
        if (comptime @hasField(@TypeOf(state.*), "gpu_xenos_runtime")) {
            state.gpu_xenos_runtime.noteNativeFenceComplete(synthetic_fence);
        }
        self.vulkan_fence_completions +|= 1;
    }

    fn clearRealVulkanObjectMaps(self: *Forwarder) void {
        @memset(&self.real_vulkan.memory_map, .{});
        @memset(&self.real_vulkan.buffer_map, .{});
        @memset(&self.real_vulkan.image_map, .{});
        @memset(&self.real_vulkan.sampler_map, .{});
        @memset(&self.real_vulkan.fence_map, .{});
        @memset(&self.real_vulkan.semaphore_map, .{});
        @memset(&self.real_vulkan.render_pass_map, .{});
        @memset(&self.real_vulkan.framebuffer_map, .{});
        @memset(&self.real_vulkan.pipeline_map, .{});
        @memset(&self.real_vulkan.shader_module_map, .{});
        @memset(&self.real_vulkan.descriptor_set_layout_map, .{});
        @memset(&self.real_vulkan.pipeline_layout_map, .{});
        @memset(&self.real_vulkan.descriptor_pool_map, .{});
        @memset(&self.real_vulkan.descriptor_set_map, .{});
        @memset(&self.real_vulkan.command_pool_map, .{});
        @memset(&self.real_vulkan.command_buffer_map, .{});
        @memset(&self.real_vulkan.swapchain_map, .{});
        @memset(&self.real_vulkan.swapchain_records, .{});
        @memset(&self.real_vulkan.buffer_view_map, .{});
        @memset(&self.real_vulkan.image_view_map, .{});
        @memset(&self.real_vulkan.query_pool_map, .{});
        @memset(&self.real_vulkan.pipeline_cache_map, .{});
        @memset(&self.real_vulkan.descriptor_update_template_map, .{});
        @memset(&self.real_vulkan.descriptor_update_template_records, .{});
        @memset(&self.real_vulkan.queue_map, .{});
    }

    /// Destroy the guest's real Vulkan device and all its children.
    fn destroyRealDevice(self: *Forwarder) void {
        if (!self.real_vulkan.hasDevice()) return;
        const device = self.real_vulkan.device.?;
        if (self.real_vulkan.device_lost) {
            // Once the driver has reported VK_ERROR_DEVICE_LOST, child
            // destruction and idle waits are not a reliable recovery path.
            // Drop the bridge's mappings, then perform the one Vulkan teardown
            // operation that remains meaningful so a later guest recreation
            // starts from a clean provenance ledger.
            self.clearRealVulkanObjectMaps();
            self.real_vulkan.swapchain = 0;
            self.vulkan_swapchain_image_count = 0;
            @memset(&self.vulkan_swapchain_image_handles, 0);
            if (self.real_vulkan.fn_ptrs.destroy_device) |destroy| destroy(device, null);
            self.real_vulkan.device = null;
            self.real_vulkan.guest_device_handle = 0;
            self.real_vulkan.graphics_queue = null;
            self.real_vulkan.compute_queue = null;
            self.real_vulkan.transfer_queue = null;
            self.real_vulkan.fn_ptrs = .{};
            self.real_vulkan.device_lost = false;
            self.real_vulkan.device_loss_result = abi.SUCCESS;
            machoCapturePrint("macho-processor: REAL VkDevice destroyed after device loss; mappings quarantined\n", .{});
            return;
        }
        self.destroyRealSwapchain(0);
        // Wait for all work to finish before destroying.
        if (self.real_vulkan.fn_ptrs.device_wait_idle) |wait_fn| {
            const result = wait_fn(device);
            self.noteRealVulkanResult(result, "vkDeviceWaitIdle during teardown");
            if (self.real_vulkan.device_lost) {
                // Re-enter through the quarantined path so no child
                // destructor is called after the driver has invalidated the
                // device.
                self.destroyRealDevice();
                return;
            }
        }
        // Destroy tracked objects in reverse dependency order.
        for (self.real_vulkan.image_view_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_image_view) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.query_pool_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_query_pool) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.pipeline_cache_map) |entry| {
            if (entry.real == 0) continue;
            self.persistPipelineCache(entry.real);
            if (self.real_vulkan.fn_ptrs.destroy_pipeline_cache) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.descriptor_update_template_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_descriptor_update_template) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.buffer_view_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_buffer_view) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.framebuffer_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_framebuffer) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.pipeline_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_pipeline) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.render_pass_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_render_pass) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.descriptor_set_layout_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_descriptor_set_layout) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.pipeline_layout_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_pipeline_layout) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.shader_module_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_shader_module) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.sampler_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_sampler) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.descriptor_pool_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_descriptor_pool) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.image_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_image) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.buffer_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_buffer) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.fence_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_fence) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.semaphore_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_semaphore) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.memory_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.free_memory) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        for (self.real_vulkan.command_pool_map) |entry| {
            if (entry.real == 0) continue;
            if (self.real_vulkan.fn_ptrs.destroy_command_pool) |fn_ptr| {
                fn_ptr(device, entry.real, null);
            }
        }
        // Clear all maps.
        @memset(&self.real_vulkan.memory_map, .{});
        @memset(&self.real_vulkan.buffer_map, .{});
        @memset(&self.real_vulkan.image_map, .{});
        @memset(&self.real_vulkan.sampler_map, .{});
        @memset(&self.real_vulkan.fence_map, .{});
        @memset(&self.real_vulkan.semaphore_map, .{});
        @memset(&self.real_vulkan.render_pass_map, .{});
        @memset(&self.real_vulkan.framebuffer_map, .{});
        @memset(&self.real_vulkan.pipeline_map, .{});
        @memset(&self.real_vulkan.shader_module_map, .{});
        @memset(&self.real_vulkan.descriptor_set_layout_map, .{});
        @memset(&self.real_vulkan.pipeline_layout_map, .{});
        @memset(&self.real_vulkan.descriptor_pool_map, .{});
        @memset(&self.real_vulkan.descriptor_set_map, .{});
        @memset(&self.real_vulkan.command_pool_map, .{});
        @memset(&self.real_vulkan.command_buffer_map, .{});
        @memset(&self.real_vulkan.buffer_view_map, .{});
        @memset(&self.real_vulkan.image_view_map, .{});
        @memset(&self.real_vulkan.query_pool_map, .{});
        @memset(&self.real_vulkan.pipeline_cache_map, .{});
        @memset(&self.real_vulkan.descriptor_update_template_map, .{});
        @memset(&self.real_vulkan.descriptor_update_template_records, .{});
        @memset(&self.real_vulkan.queue_map, .{});
        // Destroy the device.
        if (self.real_vulkan.fn_ptrs.destroy_device) |destroy| {
            destroy(device, null);
        }
        self.real_vulkan.device = null;
        self.real_vulkan.guest_device_handle = 0;
        self.real_vulkan.graphics_queue = null;
        self.real_vulkan.compute_queue = null;
        self.real_vulkan.transfer_queue = null;
        self.real_vulkan.fn_ptrs = .{};
        self.real_vulkan.device_lost = false;
        self.real_vulkan.device_loss_result = abi.SUCCESS;
        machoCapturePrint("macho-processor: REAL VkDevice destroyed\n", .{});
    }

    fn destroyRealSwapchain(self: *Forwarder, synthetic: u64) void {
        if (!self.real_vulkan.device_lost) {
            if (self.real_vulkan.device) |device| {
                if (self.real_vulkan.fn_ptrs.destroy_swapchain) |destroy| {
                    if (synthetic != 0) {
                        if (self.real_vulkan.realSwapchain(synthetic)) |swapchain| destroy(device, swapchain, null);
                    } else {
                        for (self.real_vulkan.swapchain_records) |record| {
                            if (record.real != 0) destroy(device, record.real, null);
                        }
                    }
                }
            }
        }
        if (synthetic != 0) {
            if (self.real_vulkan.mutableSwapchainRecord(synthetic)) |record| {
                self.real_vulkan.releaseSwapchainImageHandles(record);
                record.* = .{};
            }
            HandleMap.remove(&self.real_vulkan.swapchain_map, synthetic);
        } else {
            for (self.real_vulkan.swapchain_records) |record| {
                self.real_vulkan.releaseSwapchainImageHandles(&record);
            }
            @memset(&self.real_vulkan.swapchain_map, .{});
            @memset(&self.real_vulkan.swapchain_records, .{});
        }
        self.real_vulkan.swapchain = 0;
        self.vulkan_swapchain_image_count = 0;
        @memset(&self.vulkan_swapchain_image_handles, 0);
    }

    fn destroyRealSurface(self: *Forwarder) void {
        if (self.real_vulkan.surface == 0) return;
        const instance = self.real_vulkan.instance orelse return;
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return;
        const address = get_proc(instance, "vkDestroySurfaceKHR") orelse return;
        const destroy: abi.PfnDestroySurfaceKHR = @ptrCast(@alignCast(address));
        destroy(instance, self.real_vulkan.surface, null);
        self.real_vulkan.surface = 0;
        machoCapturePrint("macho-processor: REAL VkSurfaceKHR destroyed\n", .{});
    }

    /// Destroy the guest's real Vulkan instance.
    fn destroyRealInstance(self: *Forwarder) void {
        if (!self.real_vulkan.hasInstance()) return;
        const instance = self.real_vulkan.instance.?;
        const library = self.guestLibrary(self.native_vulkan_library_token) orelse return;
        const destroy_addr = dlsym(library, "vkDestroyInstance") orelse return;
        const destroy_fn: PfnVkDestroyInstance = @ptrCast(@alignCast(destroy_addr));
        destroy_fn(instance, null);
        self.real_vulkan.instance = null;
        self.real_vulkan.guest_instance_handle = 0;
        self.real_vulkan.physical_device = null;
        self.real_vulkan.get_instance_proc_addr = undefined;
        @memset(&self.real_vulkan.physical_device_properties, 0);
        self.real_vulkan.physical_device_memory = .{};
        self.real_vulkan.queue_family_count = 0;
        machoCapturePrint("macho-processor: REAL VkInstance destroyed\n", .{});
    }

    fn destroyNativeVulkanObjects(self: *Forwarder) void {
        // Destroy the guest's real Vulkan objects first (device before instance).
        self.destroyRealDevice();
        // A guest may destroy its instance without first destroying the surface.
        // Keep the Vulkan parent/child teardown order valid in that case too.
        self.destroyRealSurface();
        // The presenter owns a device, a swapchain and a surface of its own,
        // all parented by an instance in this same library. It has to go first,
        // and in its own dependency order.
        self.native_presenter.shutdown();
        self.destroyNativeSurface();
        if (self.native_vulkan_instance) |instance| {
            if (self.guestLibrary(self.native_vulkan_library_token)) |library| {
                if (dlsym(library, "vkDestroyInstance")) |destroy_address| {
                    const destroy_instance: PfnVkDestroyInstance = @ptrCast(@alignCast(destroy_address));
                    destroy_instance(instance, null);
                }
            }
            self.native_vulkan_instance = null;
        }
        self.native_vulkan_surface = 0;
        // Clean up the guest's real instance if it differs from the presenter's.
        self.destroyRealInstance();
        self.native_vulkan_library_token = 0;
    }

    /// Hands the presenter the host loader without teaching the GPU library
    /// anything about `dlopen`: resolving symbols is dyld's job, and this is
    /// dyld.
    fn resolveNativeVulkanSymbol(context: ?*anyopaque, name: [*:0]const u8) callconv(.c) ?*anyopaque {
        const handle = context orelse return null;
        return dlsym(handle, name);
    }

    /// Bring Rosette's own native presenter up against the window's
    /// `CAMetalLayer`. Independent of the guest's Vulkan objects: the guest's
    /// device and swapchain stay modelled, while this owns a real device, a
    /// real swapchain and real images, so something other than a host clear can
    /// reach the display.
    fn bringUpNativePresenter(self: *Forwarder, state: anytype, library_token: u64) rosette_gpu.NativePresenterStage {
        const State = @typeInfo(@TypeOf(state)).pointer.child;
        if (self.native_presenter.stage.isReady()) return .ready;
        if (self.native_presenter.stage == .device_lost) return .device_lost;
        if (!@hasDecl(State, "nativeMetalLayerHostPointer")) return self.native_presenter.stage;
        const layer = state.nativeMetalLayerHostPointer();
        if (layer == 0) return self.native_presenter.stage;
        const library = self.materializeNativeVulkanLibrary(library_token) orelse return self.native_presenter.stage;

        const width = if (@hasDecl(State, "nativeWindowWidth")) state.nativeWindowWidth() else 1280;
        const height = if (@hasDecl(State, "nativeWindowHeight")) state.nativeWindowHeight() else 720;
        self.native_presenter_attempts +|= 1;
        const stage = self.native_presenter.bringUp(
            .{ .context = library, .lookup = resolveNativeVulkanSymbol },
            layer,
            @max(width, 1),
            @max(height, 1),
        );
        if (self.native_presenter_stage_logged != stage) {
            self.native_presenter_stage_logged = stage;
            const report = &self.native_presenter.report;
            machoCapturePrint(
                "macho-processor: native Vulkan presenter: attempt={d} stage={s} ({s}) VkResult={d} rejection={s} adapter={s} api=0x{x} physical_devices={d} queues(graphics/present/unified)={d}/{d}/{} portability(enumeration/subset)={}/{} swapchain(images/extent/format/colorspace/present_mode/usage)={d}/{d}x{d}/{d}/{d}/{d}/0x{x} CAMetalLayer=0x{x}\n",
                .{
                    self.native_presenter_attempts,
                    @tagName(stage),
                    stage.label(),
                    report.last_result,
                    report.rejectionLabel(),
                    if (report.adapter_name_length != 0) report.adapterName() else "unselected",
                    report.api_version,
                    report.physical_device_count,
                    report.graphics_family,
                    report.present_family,
                    report.unified_queue,
                    report.portability_enumeration,
                    report.portability_subset,
                    report.swapchain_image_count,
                    report.extent_width,
                    report.extent_height,
                    report.surface_format,
                    report.surface_color_space,
                    report.present_mode,
                    report.image_usage,
                    layer,
                },
            );
        }
        if (stage.isReady()) {
            self.vulkan_presenter_stage = .native_drawable_ready;
            self.negotiateRosetteGpuBoundary("native_presenter_ready");
        }
        return stage;
    }

    /// Look for a guest image that could be this frame.
    ///
    /// Deliberately generic: no address, title, or symbol name appears here.
    /// The question asked is structural — is there an image the guest described
    /// with a presentable format and extent, bound to memory the guest can
    /// write, that the guest has actually written? An image satisfying all four
    /// is the guest's frame whatever produced it, and an image failing any of
    /// them is named by which one it failed, so the next run says what to fix
    /// rather than that nothing was found.
    ///
    /// It does not synthesise. If the guest wrote nothing, this publishes
    /// nothing, and the window keeps showing a frame labelled diagnostic.
    fn discoverGuestFrameSource(self: *Forwarder, state: anytype) void {
        self.frame_source_scans +|= 1;
        // The console's own framebuffer outranks any Vulkan image the emulator
        // described. When the emulator's GPU work does not execute, its images
        // stay exactly as empty as they were mapped, and this is the only
        // buffer that can hold a picture at all.
        if (self.publishGuestFrontBuffer(state)) return;
        var best: ?*VulkanResource = null;
        var best_pixels: u64 = 0;
        var saw_image = false;
        var saw_bound = false;
        var saw_mapped = false;
        var saw_format = false;
        for (&self.vulkan_resources) |*record| {
            if (record.handle == 0 or record.kind != .image) continue;
            saw_image = true;
            if (record.width == 0 or record.height == 0) continue;
            if (rosette_gpu.vulkan.selection.bytesPerPixel(record.format) == null) continue;
            saw_format = true;
            if (record.memory == 0) continue;
            saw_bound = true;
            const allocation = self.findVulkanMemoryRecord(record.memory) orelse continue;
            if (allocation.mapped_base == 0) continue;
            saw_mapped = true;
            const pixels = @as(u64, record.width) * record.height;
            if (pixels <= best_pixels) continue;
            best_pixels = pixels;
            best = record;
        }
        const chosen = best orelse {
            // Each of these is a different missing link, and "no source" alone
            // would send a reader nowhere.
            self.frame_inbox.noteUnusable(if (!saw_image)
                .never_published
            else if (!saw_format)
                .format_unsupported
            else if (!saw_bound or !saw_mapped)
                .source_unmapped
            else
                .never_published);
            return;
        };
        const allocation = self.findVulkanMemoryRecord(chosen.memory) orelse return;
        const address = allocation.mapped_base + chosen.memory_offset;
        const required = chosen.size_bytes;
        const readable = state.guestMemoryConst(address, required);
        if (readable == null) {
            self.frame_inbox.noteUnusable(.source_truncated);
            return;
        }
        // An allocated, mapped, never-written image is zero throughout.
        // Presenting it would put a black frame on the window and label it
        // guest output, which is worse than showing nothing.
        var written = false;
        for (readable.?) |byte| {
            if (byte != 0) {
                written = true;
                break;
            }
        }
        if (!written) {
            self.frame_inbox.noteUnusable(.never_published);
            return;
        }
        const serial = self.frame_inbox.publish(.{
            .source_address = address,
            .source_length = required,
            .width = chosen.width,
            .height = chosen.height,
            .format = chosen.format,
            .row_pitch_bytes = chosen.row_pitch_bytes,
            .orientation = .top_down,
            .fit = .letterbox,
            .producer = .xenia_host,
            // Only the bootstrap's own swap observation may set this, and it is
            // supplied by the caller rather than inferred from a frame arriving.
            .guest_swap_observed = false,
        });
        if (serial == 0) return;
        self.frame_source_discoveries +|= 1;
        if (self.frame_source_discoveries == 1) {
            machoCapturePrint(
                "macho-processor: GUEST FRAME SOURCE FOUND: image=0x{x} extent={d}x{d} format={d} pitch={d} bytes={d} guest_address=0x{x} serial={d}; a written, mapped, presentable guest image now feeds the native presenter\n",
                .{ chosen.handle, chosen.width, chosen.height, chosen.format, chosen.row_pitch_bytes, required, address, serial },
            );
        }
    }

    /// Put a frame on the window. Prefers a completed guest image, falls back to
    /// Rosette's native Vulkan presenter showing a diagnostic clear, and falls
    /// back again to the host Metal clear only when that presenter could not be
    /// brought up. Every one of those is labelled with what it actually is.
    fn presentWindowFrame(self: *Forwarder, state: anytype, serial: u64, width: u32, height: u32, stage_hint: u32) bool {
        if (self.native_presenter.stage.isReady()) {
            self.discoverGuestFrameSource(state);
            if (self.frame_inbox.acquire()) |descriptor| {
                const pixels = state.guestMemoryConst(descriptor.source_address, descriptor.source_length);
                if (pixels) |bytes| {
                    const report = self.native_presenter.present(.{ .cpu_image = .{
                        .pixels = bytes,
                        .width = descriptor.width,
                        .height = descriptor.height,
                        .format = self.native_presenter.surface_format.format,
                        .row_pitch_bytes = descriptor.row_pitch_bytes,
                        .orientation = descriptor.orientation,
                        .fit = descriptor.fit,
                        .producer = descriptor.producer,
                        .guest_swap_observed = descriptor.guest_swap_observed,
                    } });
                    self.observeNativePresenterReport(report);
                    self.frame_inbox.release(report.presented and report.source_copied);
                    if (report.presented and report.source_copied) {
                        const frames = self.native_presenter.ledger.host_frames_presented +
                            self.native_presenter.ledger.guest_output_frames_presented;
                        if (frames <= 8 or frames % 120 == 0) {
                            machoCapturePrint(
                                "macho-processor: guest-sourced frame presented: serial={d} extent={d}x{d} composite={s} destination={d},{d} {d}x{d} class={s} guest_swap_observed={s}\n",
                                .{
                                    descriptor.serial,
                                    descriptor.width,
                                    descriptor.height,
                                    @tagName(report.composite),
                                    report.destination.x,
                                    report.destination.y,
                                    report.destination.width,
                                    report.destination.height,
                                    report.classification.label(),
                                    if (descriptor.guest_swap_observed) "YES" else "NO",
                                },
                            );
                        }
                        return true;
                    }
                    // The presenter could not use it. Say so rather than
                    // falling through silently to a clear that looks the same.
                    machoCapturePrint(
                        "macho-processor: guest-sourced frame rejected by the presenter: serial={d} extent={d}x{d} swapchain={d}x{d} source_format={d} swapchain_format={d} composite={s}; falling back to a diagnostic clear\n",
                        .{
                            descriptor.serial,
                            descriptor.width,
                            descriptor.height,
                            self.native_presenter.extent.width,
                            self.native_presenter.extent.height,
                            descriptor.format,
                            self.native_presenter.surface_format.format,
                            @tagName(report.composite),
                        },
                    );
                } else {
                    self.frame_inbox.release(false);
                    self.frame_inbox.noteUnusable(.source_unmapped);
                }
            } else if (self.frame_source_absence_logged != self.frame_inbox.absence()) {
                self.frame_source_absence_logged = self.frame_inbox.absence();
                machoCapturePrint(
                    "macho-processor: no guest frame source: {s} (scans={d} discoveries={d} images_tracked={d} image_bindings={d})\n",
                    .{
                        self.frame_inbox.absence().label(),
                        self.frame_source_scans,
                        self.frame_source_discoveries,
                        self.trackedImageCount(),
                        self.vulkan_image_bindings,
                    },
                );
            }
            // Cycled so a stalled presenter is visibly distinguishable from a
            // running one that has nothing new to show.
            const phase: f32 = @as(f32, @floatFromInt(serial % 120)) / 120.0;
            const report = self.native_presenter.present(.{
                .clear = .{ 0.05, 0.08 + phase * 0.3, 0.16 + (1.0 - phase) * 0.4, 1.0 },
            });
            self.observeNativePresenterReport(report);
            const frames = self.native_presenter.ledger.diagnostic_frames_presented;
            if (frames <= 8 or frames % 120 == 0 or !report.presented) {
                machoCapturePrint(
                    "macho-processor: native Vulkan frame: serial={d} attempted={} generation={d} slot={d} image={d} acquire={d}({s}) submit={d} present={d}({s}) health={s} provenance={s} source=host_clear native_swapchain=YES native_queue_submit={s} guest_output=NO\n",
                    .{
                        serial,
                        report.attempted,
                        report.generation,
                        report.frame_slot,
                        report.image_index,
                        report.acquire_result,
                        @tagName(report.acquire_outcome),
                        report.submit_result,
                        report.present_result,
                        @tagName(report.present_outcome),
                        @tagName(report.health),
                        report.classification.label(),
                        if (report.submitted) "YES" else "NO",
                    },
                );
            }
            return report.presented;
        }
        const presented = presentDiagnosticMetalFrame(state, serial, width, height, stage_hint);
        _ = self.frame_provenance.record(.{
            .producer = .diagnostic,
            .source_ready = true,
            // A Metal clear reaches the drawable without any of these.
            .native_command_recording = false,
            .native_submission = false,
            .native_presentation = false,
            .present_accepted = presented,
        });
        return presented;
    }

    /// Fold real native presenter progress back into the backend-neutral
    /// handshake. `ready` is established before the first queue submission, so
    /// the initial handshake correctly lacks presentation. Once the driver has
    /// actually accepted a present request, leaving that early snapshot in
    /// place makes later diagnostics claim the proven path is still missing.
    /// This updates host-boundary facts only; it never marks a guest swap,
    /// publishes a ring pointer, or changes frame provenance.
    fn observeNativePresenterReport(self: *Forwarder, report: anytype) void {
        self.gpu_runtime.observeBackendProgress(report.submitted, report.presented);
        const live_boundary = self.native_presenter.boundary();
        const advertised = self.gpu_runtime.adapter.description.provided;
        if (live_boundary.presentation_native and !advertised.contains(.presentation)) {
            self.negotiateRosetteGpuBoundary("native_presentation_observed");
        }
    }

    fn negotiateRosetteGpuBoundary(self: *Forwarder, reason: []const u8) void {
        // The presenter is authoritative once it exists: it is the only thing
        // that has actually created a device, a queue and a swapchain.
        if (self.native_presenter.stage != .unstarted) {
            self.gpu_runtime.installVulkanBoundary(self.native_presenter.boundary());
            self.forwarding_contract = .{};
            self.native_presenter.declareInto(&self.forwarding_contract);
        } else {
            self.gpu_runtime.installVulkanBoundary(.{
                .instance_native = self.native_vulkan_instance != null,
                .surface_native = self.native_vulkan_surface != 0,
            });
        }
        self.gpu_handshake_response = self.gpu_runtime.negotiate(rosette_gpu.HandshakeRequest.xeniaObservation());
        self.gpu_handshake_updates +|= 1;
        const response = &self.gpu_handshake_response;
        machoCapturePrint(
            "macho-processor: Rosette GPU handshake #{d}: reason={s} api={d} backend={s} status={s} session=0x{x} negotiated=0x{x}:0x{x} missing_required=0x{x}:0x{x} missing_desired=0x{x}:0x{x} first_missing={s} detail={s}\n",
            .{
                self.gpu_handshake_updates,
                reason,
                response.version,
                @tagName(response.backendValue()),
                @tagName(response.statusValue()),
                response.session,
                response.negotiated.high,
                response.negotiated.low,
                response.missing_required.high,
                response.missing_required.low,
                response.missing_desired.high,
                response.missing_desired.low,
                if (response.first_missing_capability == rosette_gpu.api.no_capability)
                    "none"
                else
                    rosette_gpu.api.capabilityName(@enumFromInt(response.first_missing_capability)),
                response.reasonSlice(),
            },
        );
        const health = self.gpu_runtime.bridgeHealth();
        const health_fingerprint = health.fingerprint();
        if (health_fingerprint != self.gpu_health_fingerprint) {
            self.gpu_health_fingerprint = health_fingerprint;
            machoCapturePrint(
                "macho-processor: Rosette GPU bridge health: stage={s} advisory_only=YES host_execution_ready={s} first_missing={s} authentic_submit={s} authentic_present={s}; this report is non-fatal and does not alter guest GPU bootstrap\n",
                .{
                    @tagName(health.stage),
                    if (health.readyForHostExecution()) "YES" else "NO",
                    if (health.first_missing_execution_capability) |missing|
                        rosette_gpu.api.capabilityName(missing)
                    else
                        "none",
                    if (health.authentic_submission_seen) "YES" else "NO",
                    if (health.authentic_presentation_seen) "YES" else "NO",
                },
            );
        }
    }

    fn createMetalSurface(self: *Forwarder, state: anytype, library_token: u64, instance: u64, create_info: u64, output: u64) u64 {
        self.vulkan_presenter_stage = .metal_surface_requested;
        const info = state.guestMemoryConst(create_info, 32);
        const s_type = if (info != null) state.read32(create_info) else 0;
        const layer = if (info != null) state.read64(create_info + 24) else 0;
        if (state.active_idle_source == 0) self.vulkan_presenter_off_ui_calls +|= 1;
        machoCapturePrint(
            "macho-processor: Vulkan presenter bind: stage=metal_surface_requested step={d} thread=0x{x} gtk_idle_source={d} instance=0x{x} create_info=0x{x} s_type={d} layer=0x{x} output=0x{x}\n",
            .{ state.executed_steps, state.active_guest_thread, state.active_idle_source, instance, create_info, s_type, layer, output },
        );
        const State = @typeInfo(@TypeOf(state)).pointer.child;
        const layer_valid = if (info == null or layer == 0)
            false
        else if (@hasDecl(State, "validateNativeMetalLayerToken"))
            state.validateNativeMetalLayerToken(layer)
        else
            true;
        if (info == null or s_type != VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT or !layer_valid) {
            self.vulkan_presenter_stage = .failed;
            self.vulkan_presenter_bind_failures +|= 1;
            machoCapturePrint(
                "macho-processor: Vulkan presenter bind failed: stage=metal_surface reason={s} create_info=0x{x} s_type={d} expected={d}\n",
                .{ if (info == null) "unmapped_create_info" else if (s_type != VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT) "unexpected_s_type" else if (layer == 0) "null_metal_layer" else "unbound_native_metal_layer", create_info, s_type, VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT },
            );
            return vkErrorInitializationFailed();
        }
        // Prefer a surface created from the guest's real VkInstance. A
        // VkSurfaceKHR is instance-owned; using the native presenter's shadow
        // instance here makes a later real vkCreateSwapchainKHR invalid even
        // though the surface-creation call itself succeeds.
        const real_surface = self.createRealGuestMetalSurface(state, instance, layer);
        if (real_surface.enforced and real_surface.result != 0) {
            self.vulkan_presenter_stage = .failed;
            self.vulkan_presenter_bind_failures +|= 1;
            machoCapturePrint(
                "macho-processor: Vulkan presenter bind failed: stage=metal_surface reason=guest_instance_vkCreateMetalSurfaceEXT_failed VkResult={d} layer=0x{x}\n",
                .{ real_surface.result, layer },
            );
            return @as(u32, @bitCast(real_surface.result));
        }
        const native_surface = if (real_surface.enforced)
            NativeSurfaceResult{ .enforced = false, .result = 0, .surface = 0 }
        else
            self.createNativeMetalSurface(state, library_token);
        if (native_surface.enforced and native_surface.result != 0) {
            self.vulkan_presenter_stage = .failed;
            self.vulkan_presenter_bind_failures +|= 1;
            machoCapturePrint(
                "macho-processor: Vulkan presenter bind failed: stage=metal_surface reason=host_vkCreateMetalSurfaceEXT_failed VkResult={d} layer=0x{x}\n",
                .{ native_surface.result, layer },
            );
            return @as(u32, @bitCast(native_surface.result));
        }
        const result = createHandle(state, output, VK_SYNTHETIC_SURFACE, "Vulkan Metal surface");
        if (result == 0) {
            self.vulkan_metal_surfaces_created +|= 1;
            self.vulkan_presenter_stage = .metal_surface_created;
            if (@hasDecl(State, "noteNativeVulkanSurfaceBound")) {
                const host_surface = if (real_surface.enforced) real_surface.surface else native_surface.surface;
                state.noteNativeVulkanSurfaceBound(layer, VK_SYNTHETIC_SURFACE, host_surface);
            }
            if (self.vulkan_metal_surfaces_created == 1) {
                machoCapturePrint(
                    "macho-processor: Vulkan milestone: metal_surface_created guest_surface=0x{x} backing={s} layer=0x{x} output=0x{x} gtk_idle_source={d}\n",
                    .{ VK_SYNTHETIC_SURFACE, if (real_surface.enforced) "real_guest_instance" else "native_presenter_shadow", layer, output, state.active_idle_source },
                );
            }
            // The layer is live and the host loader is open, which is the
            // earliest point Rosette's own presenter can exist. Bringing it up
            // here rather than at first present means a failure is reported
            // while there is still context for it.
            _ = self.bringUpNativePresenter(state, library_token);
        } else {
            self.vulkan_presenter_stage = .failed;
            self.vulkan_presenter_bind_failures +|= 1;
        }
        return result;
    }

    fn createRealGuestMetalSurface(self: *Forwarder, state: anytype, guest_instance: u64, layer_token: u64) NativeSurfaceResult {
        const instance = self.real_vulkan.instance orelse return .{ .enforced = false, .result = 0, .surface = 0 };
        const known_guest_instance = if (self.real_vulkan.guest_instance_handle != 0)
            self.real_vulkan.guest_instance_handle
        else
            @intFromPtr(instance);
        if (guest_instance == 0 or (guest_instance != known_guest_instance and guest_instance != @intFromPtr(instance))) {
            return .{ .enforced = false, .result = 0, .surface = 0 };
        }
        const State = @typeInfo(@TypeOf(state)).pointer.child;
        if (!@hasDecl(State, "nativeMetalLayerHostPointer")) {
            return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
        }
        const host_layer = state.nativeMetalLayerHostPointer();
        if (host_layer == 0) {
            return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
        }
        if (self.real_vulkan.surface != 0) {
            return .{ .enforced = true, .result = 0, .surface = self.real_vulkan.surface };
        }
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse {
            return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
        };
        const address = get_proc(instance, "vkCreateMetalSurfaceEXT") orelse {
            return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
        };
        const create_surface: abi.PfnCreateMetalSurfaceEXT = @ptrCast(@alignCast(address));
        const create_info = abi.MetalSurfaceCreateInfoEXT{ .layer = @ptrFromInt(host_layer) };
        var surface: abi.SurfaceKHR = 0;
        const result = create_surface(instance, &create_info, null, &surface);
        if (result != abi.SUCCESS or surface == 0) {
            machoCapturePrint(
                "macho-processor: REAL guest vkCreateMetalSurfaceEXT failed: VkResult={d} instance=0x{x} CAMetalLayer=0x{x} layer_token=0x{x}\n",
                .{ result, guest_instance, host_layer, layer_token },
            );
            return .{ .enforced = true, .result = if (result != 0) result else vkErrorInitializationFailedSigned(), .surface = 0 };
        }
        self.real_vulkan.surface = surface;
        machoCapturePrint(
            "macho-processor: REAL guest vkCreateMetalSurfaceEXT succeeded: instance=0x{x} CAMetalLayer=0x{x} VkSurfaceKHR=0x{x}\n",
            .{ guest_instance, host_layer, surface },
        );
        return .{ .enforced = true, .result = 0, .surface = surface };
    }

    fn guestDeviceMatches(self: *const Forwarder, guest_device: u64) bool {
        if (guest_device == 0) return false;
        if (self.real_vulkan.device_lost) return false;
        // The synthetic presenter path intentionally has no native VkDevice;
        // it still needs a provenance check so a stale/foreign handle cannot
        // create a swapchain.  Native handles continue through the real-device
        // checks below.
        if (guest_device == VK_SYNTHETIC_DEVICE) return self.vulkan_logical_devices_created != 0;
        if (!self.real_vulkan.hasDevice()) return false;
        if (guest_device == self.real_vulkan.guest_device_handle) return true;
        const real_device = self.real_vulkan.device orelse return false;
        if (guest_device == @intFromPtr(real_device)) return true;
        // There is one guest logical device in the current Xenia Vulkan path.
        // A compatibility thunk may rewrite the dispatchable value after
        // vkCreateDevice; keep the native object graph alive instead of
        // reporting the misleading logical_device_not_created failure.
        return self.vulkan_logical_devices_created != 0;
    }

    fn createSwapchain(self: *Forwarder, state: anytype, device: u64, create_info: u64, output: u64) u64 {
        self.vulkan_presenter_bind_attempts +|= 1;
        self.vulkan_presenter_stage = .swapchain_requested;
        const info = state.guestMemoryConst(create_info, VK_SWAPCHAIN_CREATE_INFO_SIZE);
        const s_type = if (info != null) state.read32(create_info) else 0;
        const surface = if (info != null) state.read64(create_info + 24) else 0;
        const image_width = if (info != null) state.read32(create_info + 44) else 0;
        const image_height = if (info != null) state.read32(create_info + 48) else 0;
        const image_usage = if (info != null) state.read32(create_info + 56) else 0;
        if (state.active_idle_source == 0) self.vulkan_presenter_off_ui_calls +|= 1;
        machoCapturePrint(
            "macho-processor: Vulkan presenter bind: stage=swapchain_requested attempt={d} step={d} thread=0x{x} gtk_idle_source={d} device=0x{x} create_info=0x{x} s_type={d} surface=0x{x} output=0x{x}\n",
            .{ self.vulkan_presenter_bind_attempts, state.executed_steps, state.active_guest_thread, state.active_idle_source, device, create_info, s_type, surface, output },
        );
        if (!self.real_vulkan.hasDevice() and self.real_vulkan.hasInstance() and
            self.native_vulkan_library_token != 0)
        {
            // The normal path creates the device at the guest's
            // vkCreateDevice call. A few translated loader paths have been
            // observed to lose that dispatch but still reach swapchain
            // creation. Build the minimum real device against the already
            // created guest instance, using a temporary guest output slot;
            // all subsequent objects remain children of that real device.
            if (state.guestAlloc(8, 8)) |temporary_output| {
                const recovery = self.ensureRealDevice(state, self.native_vulkan_library_token, 0, 0, temporary_output);
                if (recovery == 0) {
                    machoCapturePrint(
                        "macho-processor: Vulkan lazy device recovery: created real logical device before swapchain device=0x{x} guest_device=0x{x}\n",
                        .{ @intFromPtr(self.real_vulkan.device.?), state.read64(temporary_output) },
                    );
                } else {
                    machoCapturePrint(
                        "macho-processor: Vulkan lazy device recovery failed: VkResult={d}\n",
                        .{recovery},
                    );
                }
            }
        }
        const failure_reason: ?[]const u8 = if (self.real_vulkan.device_lost)
            "device_lost"
        else if (!self.guestDeviceMatches(device))
            "logical_device_not_created"
        else if (self.vulkan_metal_surfaces_created == 0)
            "metal_surface_not_created"
        else if (info == null)
            "unmapped_create_info"
        else if (s_type != VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR)
            "unexpected_s_type"
        else if (state.read64(create_info + 8) != 0)
            "unsupported_pnext"
        else if (surface != VK_SYNTHETIC_SURFACE)
            "unknown_surface"
        else if (output == 0 or state.guestMemory(output, 8) == null)
            "unmapped_output"
        else
            null;
        if (failure_reason) |reason| {
            self.vulkan_presenter_stage = .failed;
            self.vulkan_presenter_bind_failures +|= 1;
            machoCapturePrint(
                "macho-processor: Vulkan presenter bind failed: stage=swapchain attempt={d} reason={s} device=0x{x} surface=0x{x} s_type={d} output=0x{x}\n",
                .{ self.vulkan_presenter_bind_attempts, reason, device, surface, s_type, output },
            );
            return vkErrorInitializationFailed();
        }

        // When the guest's device and Metal surface were both created on the
        // real instance, create the swapchain on that same driver object. The
        // guest still receives a stable Rosette handle, while every later
        // acquire/submit/present call can resolve it through this map.
        if (self.real_vulkan.hasDevice() and self.real_vulkan.surface != 0 and self.real_vulkan.fn_ptrs.create_swapchain != null) {
            const real_device = self.real_vulkan.device.?;
            const real_surface = self.real_vulkan.surface;
            var real_info: abi.SwapchainCreateInfoKHR = .{};
            real_info.flags = state.read32(create_info + 16);
            real_info.surface = real_surface;
            real_info.min_image_count = state.read32(create_info + 32);
            real_info.image_format = state.read32(create_info + 36);
            real_info.image_color_space = state.read32(create_info + 40);
            real_info.image_extent = .{ .width = image_width, .height = image_height };
            real_info.image_array_layers = state.read32(create_info + 52);
            real_info.image_usage = image_usage;
            real_info.image_sharing_mode = state.read32(create_info + 60);
            real_info.pre_transform = state.read32(create_info + 80);
            real_info.composite_alpha = state.read32(create_info + 84);
            real_info.present_mode = state.read32(create_info + 88);
            real_info.clipped = state.read32(create_info + 92);
            const old_synthetic = state.read64(create_info + 96);
            real_info.old_swapchain = self.real_vulkan.realSwapchain(old_synthetic) orelse 0;

            // The guest's capability query and the host's surface query can
            // differ slightly (especially after a resize).  Validate the
            // request against the real surface immediately before creating
            // the swapchain and choose the nearest legal value.  Passing the
            // synthetic capability answer through unchanged is exactly how a
            // real device still ends up returning VK_ERROR_* at this seam.
            const get_proc = self.real_vulkan.get_instance_proc_addr orelse return vkErrorInitializationFailed();
            const get_caps_address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfaceCapabilitiesKHR") orelse return vkErrorInitializationFailed();
            const get_caps: abi.PfnGetPhysicalDeviceSurfaceCapabilitiesKHR = @ptrCast(@alignCast(get_caps_address));
            var caps: abi.SurfaceCapabilitiesKHR = .{};
            const caps_result = get_caps(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), real_surface, &caps);
            self.noteRealVulkanResult(caps_result, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
            if (caps_result != abi.SUCCESS) return @as(u32, @bitCast(caps_result));
            if (caps.current_extent.width != abi.extent_undefined and caps.current_extent.height != abi.extent_undefined) {
                real_info.image_extent = caps.current_extent;
            } else {
                real_info.image_extent.width = @max(caps.min_image_extent.width, @min(real_info.image_extent.width, caps.max_image_extent.width));
                real_info.image_extent.height = @max(caps.min_image_extent.height, @min(real_info.image_extent.height, caps.max_image_extent.height));
            }
            real_info.min_image_count = @max(real_info.min_image_count, caps.min_image_count);
            if (caps.max_image_count != abi.image_count_unbounded) real_info.min_image_count = @min(real_info.min_image_count, caps.max_image_count);
            real_info.image_array_layers = @max(real_info.image_array_layers, 1);
            if (caps.max_image_array_layers != 0) real_info.image_array_layers = @min(real_info.image_array_layers, caps.max_image_array_layers);
            const requested_usage = real_info.image_usage;
            real_info.image_usage &= caps.supported_usage_flags;
            if (real_info.image_usage == 0) {
                machoCapturePrint("macho-processor: REAL vkCreateSwapchainKHR refused: no supported usage bits requested=0x{x} supported=0x{x}\n", .{ requested_usage, caps.supported_usage_flags });
                return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            }
            const requested_transform = real_info.pre_transform;
            if ((caps.supported_transforms & requested_transform) == 0) real_info.pre_transform = caps.current_transform;
            const requested_composite = real_info.composite_alpha;
            if ((caps.supported_composite_alpha & requested_composite) == 0) real_info.composite_alpha = caps.supported_composite_alpha & (~caps.supported_composite_alpha +% 1);

            var host_formats: [32]abi.SurfaceFormatKHR = [_]abi.SurfaceFormatKHR{.{}} ** 32;
            var host_format_count: u32 = @intCast(host_formats.len);
            const get_formats_address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfaceFormatsKHR") orelse return vkErrorInitializationFailed();
            const get_formats: abi.PfnGetPhysicalDeviceSurfaceFormatsKHR = @ptrCast(@alignCast(get_formats_address));
            const formats_result = get_formats(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), real_surface, &host_format_count, &host_formats);
            self.noteRealVulkanResult(formats_result, "vkGetPhysicalDeviceSurfaceFormatsKHR");
            if (formats_result != abi.SUCCESS and formats_result != abi.INCOMPLETE) return @as(u32, @bitCast(formats_result));
            const format_count = @min(host_format_count, @as(u32, @intCast(host_formats.len)));
            var matching_format = false;
            for (host_formats[0..format_count]) |format| {
                if (format.format == real_info.image_format and format.color_space == real_info.image_color_space) {
                    matching_format = true;
                    break;
                }
            }
            if (!matching_format) {
                if (format_count == 0) return @as(u32, @bitCast(abi.ERROR_FORMAT_NOT_SUPPORTED));
                real_info.image_format = host_formats[0].format;
                real_info.image_color_space = host_formats[0].color_space;
            }

            var host_modes: [16]u32 = [_]u32{0} ** 16;
            var host_mode_count: u32 = @intCast(host_modes.len);
            const get_modes_address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfacePresentModesKHR") orelse return vkErrorInitializationFailed();
            const get_modes: abi.PfnGetPhysicalDeviceSurfacePresentModesKHR = @ptrCast(@alignCast(get_modes_address));
            const modes_result = get_modes(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), real_surface, &host_mode_count, &host_modes);
            self.noteRealVulkanResult(modes_result, "vkGetPhysicalDeviceSurfacePresentModesKHR");
            if (modes_result != abi.SUCCESS and modes_result != abi.INCOMPLETE) return @as(u32, @bitCast(modes_result));
            const mode_count = @min(host_mode_count, @as(u32, @intCast(host_modes.len)));
            var matching_mode = false;
            var fifo_mode = false;
            for (host_modes[0..mode_count]) |mode| {
                if (mode == real_info.present_mode) matching_mode = true;
                if (mode == abi.PRESENT_MODE_FIFO_KHR) fifo_mode = true;
            }
            if (!matching_mode) {
                if (fifo_mode) {
                    real_info.present_mode = abi.PRESENT_MODE_FIFO_KHR;
                } else if (mode_count != 0) {
                    real_info.present_mode = host_modes[0];
                } else {
                    return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                }
            }

            // Concurrent sharing carries a guest pointer. Copy the indices to
            // host-owned storage instead of allowing the driver to dereference
            // an x86 guest address after this call returns.
            var queue_indices: [16]u32 = [_]u32{0} ** 16;
            const guest_queue_count = state.read32(create_info + 64);
            const guest_queue_address = state.read64(create_info + 72);
            const queue_count = @min(guest_queue_count, queue_indices.len);
            if (real_info.image_sharing_mode != abi.SHARING_MODE_EXCLUSIVE and queue_count != 0 and guest_queue_address != 0) {
                if (state.guestMemoryConst(guest_queue_address, @as(u64, queue_count) * 4)) |queue_bytes| {
                    var valid_indices = true;
                    for (0..queue_count) |index| {
                        queue_indices[index] = std.mem.readInt(u32, queue_bytes[index * 4 ..][0..4], .little);
                        if (queue_indices[index] >= self.real_vulkan.queue_family_count) valid_indices = false;
                    }
                    if (valid_indices) {
                        real_info.queue_family_index_count = queue_count;
                        real_info.queue_family_indices = &queue_indices;
                    } else {
                        real_info.image_sharing_mode = abi.SHARING_MODE_EXCLUSIVE;
                        real_info.queue_family_index_count = 0;
                    }
                } else {
                    real_info.image_sharing_mode = abi.SHARING_MODE_EXCLUSIVE;
                    real_info.queue_family_index_count = 0;
                }
            } else {
                real_info.image_sharing_mode = abi.SHARING_MODE_EXCLUSIVE;
                real_info.queue_family_index_count = 0;
            }

            var real_swapchain: abi.SwapchainKHR = 0;
            const real_result = self.real_vulkan.fn_ptrs.create_swapchain.?(real_device, &real_info, null, &real_swapchain);
            self.noteRealVulkanResult(real_result, "vkCreateSwapchainKHR");
            if (real_result != abi.SUCCESS or real_swapchain == 0) {
                machoCapturePrint(
                    "macho-processor: REAL vkCreateSwapchainKHR failed: VkResult={d} device=0x{x} surface=0x{x} extent={d}x{d} format={d} usage=0x{x}\n",
                    .{ real_result, device, surface, image_width, image_height, real_info.image_format, image_usage },
                );
                return @as(u32, @bitCast(real_result));
            }
            const synthetic_swapchain = self.nextVulkanObject();
            if (self.real_vulkan.allocateSwapchainRecord(synthetic_swapchain, real_swapchain) == null) {
                if (self.real_vulkan.fn_ptrs.destroy_swapchain) |destroy| destroy(real_device, real_swapchain, null);
                return @as(u32, @bitCast(abi.ERROR_OUT_OF_HOST_MEMORY));
            }
            state.write64(output, synthetic_swapchain);
            registerOpaqueHandle(state, synthetic_swapchain, "Vulkan swapchain");
            HandleMap.allocOrFind(&self.real_vulkan.swapchain_map, synthetic_swapchain, real_swapchain);
            self.real_vulkan.swapchain = real_swapchain;
            self.vulkan_swapchains_created +|= 1;
            self.vulkan_swapchain_image_count = 0;
            self.vulkan_tiers.note(.swapchain, .real);
            self.vulkan_presenter_stage = .guest_swapchain_ready;
            machoCapturePrint(
                "macho-processor: REAL vkCreateSwapchainKHR succeeded: synthetic=0x{x} real=0x{x} extent={d}x{d} format={d} usage=0x{x}\n",
                .{ synthetic_swapchain, real_swapchain, image_width, image_height, real_info.image_format, image_usage },
            );
            return 0;
        }

        const handle = self.nextVulkanObject();
        state.write64(output, handle);
        registerOpaqueHandle(state, handle, "Vulkan swapchain");
        self.vulkan_swapchains_created +|= 1;
        self.vulkan_swapchain_image_count = 3;
        for (self.vulkan_swapchain_image_handles[0..self.vulkan_swapchain_image_count]) |*image| {
            if (image.* == 0) {
                image.* = self.nextVulkanObject();
                registerOpaqueHandle(state, image.*, "Vulkan swapchain image");
            }
        }
        if (self.vulkan_swapchains_created == 1) {
            machoCapturePrint(
                "macho-processor: Vulkan milestone: swapchain_created handle=0x{x} output=0x{x} images={d} extent={d}x{d} usage=0x{x} backing=synthetic\n",
                .{ handle, output, self.vulkan_swapchain_image_count, image_width, image_height, image_usage },
            );
        }
        self.vulkan_presenter_stage = .synthetic_swapchain_ready;
        machoCapturePrint(
            "macho-processor: Vulkan presenter bind complete: stage=synthetic_swapchain_ready attempt={d} surface=0x{x} swapchain=0x{x} gtk_idle_source={d} native_drawable=false\n",
            .{ self.vulkan_presenter_bind_attempts, surface, handle, state.active_idle_source },
        );
        if (self.vulkan_swapchains_created == 1) {
            machoCapturePrint(
                "macho-processor: GRAPHICS FORWARDING BOUNDARY: native Vulkan device creation was unavailable, so the guest's VkDevice, VkSwapchainKHR, swapchain images, commands, queue submissions and presents are using the diagnostic synthetic fallback (stage={s}); no guest command reaches a driver. Guest pixels require the native Vulkan path or a title-owned framebuffer handoff.\n",
                .{@tagName(self.native_presenter.stage)},
            );
        }
        _ = self.presentWindowFrame(state, handle, image_width, image_height, 1);
        return 0;
    }

    fn enumerateSwapchainImages(self: *Forwarder, state: anytype) u64 {
        const count_address = state.regs.rdx;
        if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();

        if (self.real_vulkan.hasDevice() and self.real_vulkan.realSwapchain(state.regs.rsi) != null and self.real_vulkan.fn_ptrs.get_swapchain_images != null) {
            const real_swapchain = self.real_vulkan.realSwapchain(state.regs.rsi).?;
            const record = self.real_vulkan.mutableSwapchainRecord(state.regs.rsi) orelse
                return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
            var real_count: u32 = 0;
            var result = self.real_vulkan.fn_ptrs.get_swapchain_images.?(self.real_vulkan.device.?, real_swapchain, &real_count, null);
            self.noteRealVulkanResult(result, "vkGetSwapchainImagesKHR");
            if (result != abi.SUCCESS and result != abi.INCOMPLETE) return @as(u32, @bitCast(result));
            const exposed_count: u32 = @min(real_count, record.image_handles.len);
            record.image_count = exposed_count;
            self.vulkan_swapchain_image_count = exposed_count;
            if (state.regs.rcx == 0) {
                state.write32(count_address, exposed_count);
                self.vulkan_tiers.note(.swapchain, .real);
                return 0;
            }
            const capacity = state.read32(count_address);
            const written: u32 = @min(@min(capacity, exposed_count), record.image_handles.len);
            if (written != 0 and state.guestMemory(state.regs.rcx, @as(u64, written) * 8) == null) return vkErrorInitializationFailed();
            var real_images: [MAX_SWAPCHAIN_IMAGES]abi.Image = [_]abi.Image{0} ** MAX_SWAPCHAIN_IMAGES;
            var driver_count = written;
            result = self.real_vulkan.fn_ptrs.get_swapchain_images.?(self.real_vulkan.device.?, real_swapchain, &driver_count, &real_images);
            self.noteRealVulkanResult(result, "vkGetSwapchainImagesKHR");
            if (result != abi.SUCCESS and result != abi.INCOMPLETE) return @as(u32, @bitCast(result));
            const actual: u32 = @min(@min(driver_count, written), exposed_count);
            for (0..actual) |index| {
                var synthetic = record.image_handles[index];
                if (synthetic == 0) {
                    synthetic = self.nextVulkanObject();
                    record.image_handles[index] = synthetic;
                    registerOpaqueHandle(state, synthetic, "Vulkan swapchain image");
                }
                HandleMap.allocOrFind(&self.real_vulkan.image_map, synthetic, real_images[index]);
                state.write64(state.regs.rcx + @as(u64, @intCast(index)) * 8, synthetic);
            }
            state.write32(count_address, actual);
            self.vulkan_swapchain_images_enumerated +|= actual;
            self.vulkan_tiers.note(.swapchain, .real);
            // The driver's VK_INCOMPLETE only says it has more images than the
            // bridge can name, and the probe already told the guest the smaller
            // number. Reporting it here would tell a caller its correctly sized
            // array was too small, and the standard two-call loop would ask
            // again with the same size for the rest of the run.
            return @as(u32, @bitCast(if (actual < exposed_count) abi.INCOMPLETE else abi.SUCCESS));
        }

        const count = if (self.vulkan_swapchain_image_count == 0) 3 else self.vulkan_swapchain_image_count;
        if (state.regs.rcx == 0) {
            state.write32(count_address, count);
            return 0;
        }
        const requested = state.read32(count_address);
        const written: u32 = @min(requested, count);
        if (state.guestMemory(state.regs.rcx, @as(u64, written) * 8) == null) return vkErrorInitializationFailed();
        for (0..written) |index| {
            var handle = self.vulkan_swapchain_image_handles[index];
            if (handle == 0) {
                handle = self.nextVulkanObject();
                self.vulkan_swapchain_image_handles[index] = handle;
                registerOpaqueHandle(state, handle, "Vulkan swapchain image");
            }
            state.write64(state.regs.rcx + @as(u64, @intCast(index)) * 8, handle);
        }
        state.write32(count_address, written);
        self.vulkan_swapchain_images_enumerated +|= written;
        if (self.vulkan_swapchain_images_enumerated == written) {
            machoCapturePrint(
                "macho-processor: Vulkan milestone: swapchain_images count={d} output=0x{x}\n",
                .{ written, state.regs.rcx },
            );
        }
        return if (written < count) 5 else 0;
    }

    fn acquireNextImage(self: *Forwarder, state: anytype, output: u64) u64 {
        if (output == 0 or state.guestMemory(output, 4) == null) return vkErrorInitializationFailed();
        if (self.realDeviceLostResult()) |result| return result;

        if (self.real_vulkan.hasDevice() and self.real_vulkan.realSwapchain(state.regs.rsi) != null and self.real_vulkan.fn_ptrs.acquire_next_image != null) {
            const semaphore = if (state.regs.rcx == 0)
                0
            else
                self.real_vulkan.realSemaphore(state.regs.rcx) orelse return vkErrorInitializationFailed();
            const fence = if (state.regs.r8 == 0)
                0
            else
                self.real_vulkan.realFence(state.regs.r8) orelse return vkErrorInitializationFailed();
            var image_index: u32 = 0;
            const result = self.real_vulkan.fn_ptrs.acquire_next_image.?(
                self.real_vulkan.device.?,
                self.real_vulkan.realSwapchain(state.regs.rsi).?,
                state.regs.rdx,
                semaphore,
                fence,
                &image_index,
            );
            self.noteRealVulkanResult(result, "vkAcquireNextImageKHR");
            if (result != abi.SUCCESS and result != abi.SUBOPTIMAL_KHR) return @as(u32, @bitCast(result));
            state.write32(output, image_index);
            self.vulkan_images_acquired +|= 1;
            self.vulkan_tiers.note(.swapchain, .real);
            return @as(u32, @bitCast(result));
        }

        state.write32(output, 0);
        self.vulkan_images_acquired +|= 1;
        if (self.vulkan_images_acquired == 1) {
            machoCapturePrint(
                "macho-processor: Vulkan milestone: first_image_acquired index=0 output=0x{x}\n",
                .{output},
            );
        }
        return 0;
    }

    fn queueSubmit(self: *Forwarder, state: anytype) u64 {
        self.vulkan_queue_submits +|= 1;
        self.frame_provenance.noteGuestVulkanCall();
        if (self.realDeviceLostResult()) |result| return result;
        // Phase 1: forward real queue submissions when the device and queue exist.
        // The guest's vkQueueSubmit arguments:
        //   rdi = queue handle (synthetic)
        //   rsi = submit count
        //   rdx = pSubmits (guest pointer to VkSubmitInfo array)
        //   rcx = fence handle (synthetic, may be 0)
        if (self.real_vulkan.hasDevice()) {
            const real_queue = self.real_vulkan.realQueue(state.regs.rdi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
            if (self.real_vulkan.fn_ptrs.queue_submit) |submit_fn| {
                const submit_count: u32 = @min(@as(u32, @truncate(state.regs.rsi)), 8);
                const submits_addr = state.regs.rdx;
                const fence_synthetic = state.regs.rcx;
                if (submit_count == 0 or submits_addr == 0) return vkErrorInitializationFailed();
                if (state.guestMemoryConst(submits_addr, @as(u64, submit_count) * @sizeOf(abi.SubmitInfo)) == null) return vkErrorInitializationFailed();
                if (!self.uploadMappedMemoryBeforeSubmit(state)) return vkErrorInitializationFailed();
                var real_submits: [8]abi.SubmitInfo = [_]abi.SubmitInfo{.{}} ** 8;
                var wait_semaphores: [8][16]abi.Semaphore = [_][16]abi.Semaphore{[_]abi.Semaphore{0} ** 16} ** 8;
                var wait_stages: [8][16]u32 = [_][16]u32{[_]u32{0} ** 16} ** 8;
                var command_buffers: [8][256]abi.CommandBuffer = [_][256]abi.CommandBuffer{[_]abi.CommandBuffer{null} ** 256} ** 8;
                var signal_semaphores: [8][16]abi.Semaphore = [_][16]abi.Semaphore{[_]abi.Semaphore{0} ** 16} ** 8;
                var i: u32 = 0;
                while (i < submit_count) : (i += 1) {
                    const info = submits_addr + @as(u64, i) * @sizeOf(abi.SubmitInfo);
                    if (state.read64(info + 8) != 0) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                    const wait_count = @min(state.read32(info + 16), 16);
                    const wait_address = state.read64(info + 24);
                    const stage_address = state.read64(info + 32);
                    const command_count = @min(state.read32(info + 40), 256);
                    const command_address = state.read64(info + 48);
                    const signal_count = @min(state.read32(info + 56), 16);
                    const signal_address = state.read64(info + 64);
                    if ((wait_count != 0 and (wait_address == 0 or stage_address == 0)) or (command_count != 0 and command_address == 0) or (signal_count != 0 and signal_address == 0)) return vkErrorInitializationFailed();
                    for (0..wait_count) |index| {
                        const synthetic = state.read64(wait_address + @as(u64, @intCast(index)) * 8);
                        wait_semaphores[i][index] = self.real_vulkan.realSemaphore(synthetic) orelse return vkErrorInitializationFailed();
                        wait_stages[i][index] = state.read32(stage_address + @as(u64, @intCast(index)) * 4);
                    }
                    for (0..command_count) |index| {
                        const synthetic = state.read64(command_address + @as(u64, @intCast(index)) * 8);
                        command_buffers[i][index] = self.real_vulkan.realCommandBuffer(synthetic) orelse return vkErrorInitializationFailed();
                    }
                    for (0..signal_count) |index| {
                        const synthetic = state.read64(signal_address + @as(u64, @intCast(index)) * 8);
                        signal_semaphores[i][index] = self.real_vulkan.realSemaphore(synthetic) orelse return vkErrorInitializationFailed();
                    }
                    real_submits[i] = .{
                        .wait_semaphore_count = wait_count,
                        .wait_semaphores = if (wait_count == 0) null else &wait_semaphores[i],
                        .wait_dst_stage_mask = if (wait_count == 0) null else &wait_stages[i],
                        .command_buffer_count = command_count,
                        .command_buffers = if (command_count == 0) null else &command_buffers[i],
                        .signal_semaphore_count = signal_count,
                        .signal_semaphores = if (signal_count == 0) null else &signal_semaphores[i],
                    };
                }
                const fence_real = if (fence_synthetic == 0) 0 else self.real_vulkan.realFence(fence_synthetic) orelse return vkErrorInitializationFailed();
                const result = submit_fn(real_queue, submit_count, &real_submits, fence_real);
                self.noteRealVulkanResult(result, "vkQueueSubmit");
                if (result != abi.SUCCESS) {
                    machoCapturePrint("macho-processor: REAL vkQueueSubmit FAILED: VkResult={d} count={d}\n", .{ result, submit_count });
                    return @as(u32, @bitCast(result));
                }
                self.frame_provenance.noteNativeSubmission();
                self.gpu_runtime.observeBackendProgress(true, false);
                self.vulkan_tiers.note(.queue_submission, .real);
                self.vulkan_real_queue_submits +|= 1;
                if (self.vulkan_queue_submits <= 4) machoCapturePrint("macho-processor: REAL vkQueueSubmit: count={d} fence=0x{x} result=SUCCESS\n", .{ submit_count, fence_synthetic });
                return 0;
            }
        }
        if (self.vulkan_queue_submits == 1) {
            machoCapturePrint(
                "macho-processor: Vulkan milestone: first_queue_submit. real_device={} real_queue={s}\n",
                .{ self.real_vulkan.hasDevice(), if (self.real_vulkan.graphics_queue != null) "YES" else "NO" },
            );
        }
        return 0;
    }

    fn queueSubmit2(self: *Forwarder, state: anytype) u64 {
        self.vulkan_queue_submits +|= 1;
        self.frame_provenance.noteGuestVulkanCall();
        if (self.realDeviceLostResult()) |result| return result;
        const submit = self.real_vulkan.fn_ptrs.queue_submit2 orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const queue = self.real_vulkan.realQueue(state.regs.rdi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        const count: u32 = @min(@as(u32, @truncate(state.regs.rsi)), 8);
        if (count == 0) return abi.SUCCESS;
        const address = state.regs.rdx;
        if (address == 0 or state.guestMemoryConst(address, @as(u64, count) * @sizeOf(abi.SubmitInfo2)) == null) return vkErrorInitializationFailed();
        if (!self.uploadMappedMemoryBeforeSubmit(state)) return vkErrorInitializationFailed();
        var submits: [8]abi.SubmitInfo2 = [_]abi.SubmitInfo2{.{}} ** 8;
        var waits: [8][32]abi.SemaphoreSubmitInfo = [_][32]abi.SemaphoreSubmitInfo{[_]abi.SemaphoreSubmitInfo{.{}} ** 32} ** 8;
        var commands: [8][64]abi.CommandBufferSubmitInfo = [_][64]abi.CommandBufferSubmitInfo{[_]abi.CommandBufferSubmitInfo{.{}} ** 64} ** 8;
        var signals: [8][32]abi.SemaphoreSubmitInfo = [_][32]abi.SemaphoreSubmitInfo{[_]abi.SemaphoreSubmitInfo{.{}} ** 32} ** 8;
        for (0..count) |index| {
            if (!copyGuestValue(abi.SubmitInfo2, state, address + @as(u64, @intCast(index)) * @sizeOf(abi.SubmitInfo2), &submits[index])) return vkErrorInitializationFailed();
            if (submits[index].p_next != null or submits[index].flags != 0) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            if (submits[index].wait_semaphore_info_count > waits[index].len or
                submits[index].command_buffer_info_count > commands[index].len or
                submits[index].signal_semaphore_info_count > signals[index].len) return vkErrorInitializationFailed();
            const wait_address = if (submits[index].wait_semaphore_infos) |pointer| @intFromPtr(pointer) else 0;
            const command_address = if (submits[index].command_buffer_infos) |pointer| @intFromPtr(pointer) else 0;
            const signal_address = if (submits[index].signal_semaphore_infos) |pointer| @intFromPtr(pointer) else 0;
            if ((submits[index].wait_semaphore_info_count != 0 and wait_address == 0) or
                (submits[index].command_buffer_info_count != 0 and command_address == 0) or
                (submits[index].signal_semaphore_info_count != 0 and signal_address == 0)) return vkErrorInitializationFailed();
            if (!copyGuestStructs(abi.SemaphoreSubmitInfo, state, wait_address, submits[index].wait_semaphore_info_count, &waits[index])) return vkErrorInitializationFailed();
            if (!copyGuestStructs(abi.CommandBufferSubmitInfo, state, command_address, submits[index].command_buffer_info_count, &commands[index])) return vkErrorInitializationFailed();
            if (!copyGuestStructs(abi.SemaphoreSubmitInfo, state, signal_address, submits[index].signal_semaphore_info_count, &signals[index])) return vkErrorInitializationFailed();
            for (waits[index][0..@as(usize, @intCast(submits[index].wait_semaphore_info_count))]) |*info| {
                if (info.p_next != null) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                info.semaphore = self.real_vulkan.realSemaphore(info.semaphore) orelse return vkErrorInitializationFailed();
            }
            for (commands[index][0..@as(usize, @intCast(submits[index].command_buffer_info_count))]) |*info| {
                if (info.p_next != null) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                info.command_buffer = self.real_vulkan.realCommandBuffer(@intFromPtr(info.command_buffer)) orelse return vkErrorInitializationFailed();
            }
            for (signals[index][0..@as(usize, @intCast(submits[index].signal_semaphore_info_count))]) |*info| {
                if (info.p_next != null) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                info.semaphore = self.real_vulkan.realSemaphore(info.semaphore) orelse return vkErrorInitializationFailed();
            }
            submits[index].wait_semaphore_infos = if (submits[index].wait_semaphore_info_count == 0) null else &waits[index];
            submits[index].command_buffer_infos = if (submits[index].command_buffer_info_count == 0) null else &commands[index];
            submits[index].signal_semaphore_infos = if (submits[index].signal_semaphore_info_count == 0) null else &signals[index];
        }
        const fence = if (state.regs.rcx == 0) 0 else self.real_vulkan.realFence(state.regs.rcx) orelse return vkErrorInitializationFailed();
        const result = submit(queue, count, &submits, fence);
        self.noteRealVulkanResult(result, "vkQueueSubmit2");
        if (result == abi.SUCCESS) {
            self.frame_provenance.noteNativeSubmission();
            self.gpu_runtime.observeBackendProgress(true, false);
            self.vulkan_tiers.note(.queue_submission, .real);
            self.vulkan_real_queue_submits +|= 1;
        }
        return @as(u32, @bitCast(result));
    }

    fn queueBindSparse(self: *Forwarder, state: anytype) u64 {
        if (self.realDeviceLostResult()) |result| return result;
        const bind_sparse = self.real_vulkan.fn_ptrs.queue_bind_sparse orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const queue = self.real_vulkan.realQueue(state.regs.rdi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        const count: u32 = @min(@as(u32, @truncate(state.regs.rsi)), 4);
        if (count == 0) return abi.SUCCESS;
        const address = state.regs.rdx;
        if (address == 0 or state.guestMemoryConst(address, @as(u64, count) * @sizeOf(abi.BindSparseInfo)) == null) return vkErrorInitializationFailed();
        var infos: [4]abi.BindSparseInfo = [_]abi.BindSparseInfo{.{}} ** 4;
        var waits: [4][16]abi.Semaphore = [_][16]abi.Semaphore{[_]abi.Semaphore{0} ** 16} ** 4;
        var signals: [4][16]abi.Semaphore = [_][16]abi.Semaphore{[_]abi.Semaphore{0} ** 16} ** 4;
        var buffer_infos: [4][16]abi.SparseBufferMemoryBindInfo = [_][16]abi.SparseBufferMemoryBindInfo{[_]abi.SparseBufferMemoryBindInfo{.{}} ** 16} ** 4;
        var opaque_infos: [4][16]abi.SparseImageOpaqueMemoryBindInfo = [_][16]abi.SparseImageOpaqueMemoryBindInfo{[_]abi.SparseImageOpaqueMemoryBindInfo{.{}} ** 16} ** 4;
        var image_infos: [4][16]abi.SparseImageMemoryBindInfo = [_][16]abi.SparseImageMemoryBindInfo{[_]abi.SparseImageMemoryBindInfo{.{}} ** 16} ** 4;
        var buffer_binds: [4][16][16]abi.SparseMemoryBind = [_][16][16]abi.SparseMemoryBind{[_][16]abi.SparseMemoryBind{[_]abi.SparseMemoryBind{.{}} ** 16} ** 16} ** 4;
        var opaque_binds: [4][16][16]abi.SparseMemoryBind = [_][16][16]abi.SparseMemoryBind{[_][16]abi.SparseMemoryBind{[_]abi.SparseMemoryBind{.{}} ** 16} ** 16} ** 4;
        var image_binds: [4][16][16]abi.SparseImageMemoryBind = [_][16][16]abi.SparseImageMemoryBind{[_][16]abi.SparseImageMemoryBind{[_]abi.SparseImageMemoryBind{.{}} ** 16} ** 16} ** 4;
        for (0..count) |index| {
            if (!copyGuestValue(abi.BindSparseInfo, state, address + @as(u64, @intCast(index)) * @sizeOf(abi.BindSparseInfo), &infos[index])) return vkErrorInitializationFailed();
            if (infos[index].p_next != null or infos[index].wait_semaphore_count > waits[index].len or infos[index].signal_semaphore_count > signals[index].len or
                infos[index].buffer_bind_count > buffer_infos[index].len or infos[index].image_opaque_bind_count > opaque_infos[index].len or
                infos[index].image_bind_count > image_infos[index].len) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            const wait_address = if (infos[index].wait_semaphores) |pointer| @intFromPtr(pointer) else 0;
            const signal_address = if (infos[index].signal_semaphores) |pointer| @intFromPtr(pointer) else 0;
            if (!copyGuestStructs(abi.Semaphore, state, wait_address, infos[index].wait_semaphore_count, &waits[index])) return vkErrorInitializationFailed();
            if (!copyGuestStructs(abi.Semaphore, state, signal_address, infos[index].signal_semaphore_count, &signals[index])) return vkErrorInitializationFailed();
            for (waits[index][0..@as(usize, @intCast(infos[index].wait_semaphore_count))]) |*semaphore| semaphore.* = self.real_vulkan.realSemaphore(semaphore.*) orelse return vkErrorInitializationFailed();
            for (signals[index][0..@as(usize, @intCast(infos[index].signal_semaphore_count))]) |*semaphore| semaphore.* = self.real_vulkan.realSemaphore(semaphore.*) orelse return vkErrorInitializationFailed();
            const buffer_info_address = if (infos[index].buffer_binds) |pointer| @intFromPtr(pointer) else 0;
            const opaque_info_address = if (infos[index].image_opaque_binds) |pointer| @intFromPtr(pointer) else 0;
            const image_info_address = if (infos[index].image_binds) |pointer| @intFromPtr(pointer) else 0;
            if (!copyGuestStructs(abi.SparseBufferMemoryBindInfo, state, buffer_info_address, infos[index].buffer_bind_count, &buffer_infos[index])) return vkErrorInitializationFailed();
            if (!copyGuestStructs(abi.SparseImageOpaqueMemoryBindInfo, state, opaque_info_address, infos[index].image_opaque_bind_count, &opaque_infos[index])) return vkErrorInitializationFailed();
            if (!copyGuestStructs(abi.SparseImageMemoryBindInfo, state, image_info_address, infos[index].image_bind_count, &image_infos[index])) return vkErrorInitializationFailed();
            for (buffer_infos[index][0..@as(usize, @intCast(infos[index].buffer_bind_count))], 0..) |*bind_info, bind_index| {
                if (bind_info.bind_count > buffer_binds[index][bind_index].len) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                const bind_address = if (bind_info.binds) |pointer| @intFromPtr(pointer) else 0;
                if (!copyGuestStructs(abi.SparseMemoryBind, state, bind_address, bind_info.bind_count, &buffer_binds[index][bind_index])) return vkErrorInitializationFailed();
                bind_info.buffer = self.real_vulkan.realBuffer(bind_info.buffer) orelse return vkErrorInitializationFailed();
                for (buffer_binds[index][bind_index][0..@as(usize, @intCast(bind_info.bind_count))]) |*bind| {
                    if (bind.memory != 0) bind.memory = self.real_vulkan.realMemory(bind.memory) orelse return vkErrorInitializationFailed();
                }
                bind_info.binds = if (bind_info.bind_count == 0) null else &buffer_binds[index][bind_index];
            }
            for (opaque_infos[index][0..@as(usize, @intCast(infos[index].image_opaque_bind_count))], 0..) |*bind_info, bind_index| {
                if (bind_info.bind_count > opaque_binds[index][bind_index].len) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                const bind_address = if (bind_info.binds) |pointer| @intFromPtr(pointer) else 0;
                if (!copyGuestStructs(abi.SparseMemoryBind, state, bind_address, bind_info.bind_count, &opaque_binds[index][bind_index])) return vkErrorInitializationFailed();
                bind_info.image = self.real_vulkan.realImage(bind_info.image) orelse return vkErrorInitializationFailed();
                for (opaque_binds[index][bind_index][0..@as(usize, @intCast(bind_info.bind_count))]) |*bind| {
                    if (bind.memory != 0) bind.memory = self.real_vulkan.realMemory(bind.memory) orelse return vkErrorInitializationFailed();
                }
                bind_info.binds = if (bind_info.bind_count == 0) null else &opaque_binds[index][bind_index];
            }
            for (image_infos[index][0..@as(usize, @intCast(infos[index].image_bind_count))], 0..) |*bind_info, bind_index| {
                if (bind_info.bind_count > image_binds[index][bind_index].len) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                const bind_address = if (bind_info.binds) |pointer| @intFromPtr(pointer) else 0;
                if (!copyGuestStructs(abi.SparseImageMemoryBind, state, bind_address, bind_info.bind_count, &image_binds[index][bind_index])) return vkErrorInitializationFailed();
                bind_info.image = self.real_vulkan.realImage(bind_info.image) orelse return vkErrorInitializationFailed();
                for (image_binds[index][bind_index][0..@as(usize, @intCast(bind_info.bind_count))]) |*bind| {
                    if (bind.memory != 0) bind.memory = self.real_vulkan.realMemory(bind.memory) orelse return vkErrorInitializationFailed();
                }
                bind_info.binds = if (bind_info.bind_count == 0) null else &image_binds[index][bind_index];
            }
            infos[index].wait_semaphores = if (infos[index].wait_semaphore_count == 0) null else &waits[index];
            infos[index].signal_semaphores = if (infos[index].signal_semaphore_count == 0) null else &signals[index];
            infos[index].buffer_binds = if (infos[index].buffer_bind_count == 0) null else &buffer_infos[index];
            infos[index].image_opaque_binds = if (infos[index].image_opaque_bind_count == 0) null else &opaque_infos[index];
            infos[index].image_binds = if (infos[index].image_bind_count == 0) null else &image_infos[index];
        }
        const fence = if (state.regs.rcx == 0) 0 else self.real_vulkan.realFence(state.regs.rcx) orelse return vkErrorInitializationFailed();
        const result = bind_sparse(queue, count, &infos, fence);
        self.noteRealVulkanResult(result, "vkQueueBindSparse");
        return @as(u32, @bitCast(result));
    }

    fn queuePresent(self: *Forwarder, state: anytype) u64 {
        self.vulkan_presents +|= 1;
        self.frame_provenance.noteGuestVulkanCall();
        if (self.realDeviceLostResult()) |result| return result;
        const present_info = state.regs.rsi;
        if (self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.queue_present != null and present_info != 0 and state.guestMemoryConst(present_info, @sizeOf(abi.PresentInfoKHR)) != null) {
            if (state.read64(present_info + 8) != 0) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            const swapchain_count = @min(state.read32(present_info + 32), 8);
            const wait_count = @min(state.read32(present_info + 16), 16);
            const wait_address = state.read64(present_info + 24);
            const swapchain_address = state.read64(present_info + 40);
            const image_index_address = state.read64(present_info + 48);
            const result_address = state.read64(present_info + 56);
            if ((wait_count != 0 and wait_address == 0) or (swapchain_count != 0 and (swapchain_address == 0 or image_index_address == 0))) return vkErrorInitializationFailed();
            var waits: [16]abi.Semaphore = [_]abi.Semaphore{0} ** 16;
            var swapchains: [8]abi.SwapchainKHR = [_]abi.SwapchainKHR{0} ** 8;
            var indices: [8]u32 = [_]u32{0} ** 8;
            var results: [8]abi.Result = [_]abi.Result{abi.SUCCESS} ** 8;
            for (0..wait_count) |index| {
                const synthetic = state.read64(wait_address + @as(u64, @intCast(index)) * 8);
                waits[index] = self.real_vulkan.realSemaphore(synthetic) orelse return vkErrorInitializationFailed();
            }
            for (0..swapchain_count) |index| {
                const synthetic = state.read64(swapchain_address + @as(u64, @intCast(index)) * 8);
                swapchains[index] = self.real_vulkan.realSwapchain(synthetic) orelse return vkErrorInitializationFailed();
                indices[index] = state.read32(image_index_address + @as(u64, @intCast(index)) * 4);
            }
            var real_info = abi.PresentInfoKHR{
                .wait_semaphore_count = wait_count,
                .wait_semaphores = if (wait_count == 0) null else &waits,
                .swapchain_count = swapchain_count,
                .swapchains = if (swapchain_count == 0) null else &swapchains,
                .image_indices = if (swapchain_count == 0) null else &indices,
                .results = if (swapchain_count == 0) null else &results,
            };
            const real_queue = self.real_vulkan.realQueue(state.regs.rdi) orelse return vkErrorInitializationFailed();
            const result = self.real_vulkan.fn_ptrs.queue_present.?(real_queue, &real_info);
            self.noteRealVulkanResult(result, "vkQueuePresentKHR");
            if (result_address != 0 and swapchain_count != 0) {
                if (state.guestMemory(result_address, @as(u64, swapchain_count) * 4)) |guest_results| {
                    for (0..swapchain_count) |index| std.mem.writeInt(i32, guest_results[index * 4 ..][0..4], results[index], .little);
                }
            }
            self.frame_provenance.noteNativePresentRequest();
            self.gpu_runtime.observeBackendProgress(false, result == abi.SUCCESS or result == abi.SUBOPTIMAL_KHR);
            self.vulkan_tiers.note(.presentation, .real);
            if (result == abi.SUCCESS or result == abi.SUBOPTIMAL_KHR) self.vulkan_real_presents +|= 1;
            if (result != abi.SUCCESS and result != abi.SUBOPTIMAL_KHR) machoCapturePrint("macho-processor: REAL vkQueuePresentKHR FAILED: VkResult={d}\n", .{result});
            return @as(u32, @bitCast(result));
        }
        // This branch is reached only when the guest-native queue/present path
        // was not available. A guest present request is still useful as a
        // refresh trigger, but the pixels are diagnostic until a real guest
        // image or the console front buffer is discovered.
        const presented = self.presentWindowFrame(state, self.vulkan_presents, 0, 0, 3);
        if (self.vulkan_presents == 1) {
            machoCapturePrint(
                "macho-processor: Vulkan FALLBACK milestone: first_queue_present. presentation provenance=DIAGNOSTIC_ONLY source=host_clear guest_native_present=NO native_swapchain={s} native_queue_submit={s} guest_output=NO displayed={}\n",
                .{
                    if (self.native_presenter.stage.isReady()) "YES" else "NO",
                    if (self.native_presenter.ledger.native_submissions != 0) "YES" else "NO",
                    presented,
                },
            );
        }
        return 0;
    }

    fn allocateVulkanMemory(self: *Forwarder, state: anytype, info: u64, output: u64) u64 {
        if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
        if (self.realDeviceLostResult()) |lost| return lost;
        // VkMemoryAllocateInfo is {sType, padding, pNext, allocationSize,
        // memoryTypeIndex}. Reading +8 observes pNext (often a stack address),
        // not allocationSize, and caused the old model to reserve multi-GB
        // phantom allocations.
        if (info == 0 or state.guestMemoryConst(info + 16, 8) == null) return vkErrorInitializationFailed();
        const requested_size = state.read64(info + 16);
        const memory_type_index = state.read32(info + 24);
        if (requested_size == 0) return vkErrorInitializationFailed();

        // Xenia's macOS Vulkan implementation uses VkMemoryDedicatedAllocateInfo
        // for its large shared buffers when the host advertises the dedicated
        // allocation extension.  The guest node is in guest memory and its
        // handles are guest-visible synthetic values; passing either through
        // unchanged would make the real driver dereference an invalid pointer
        // or bind the wrong resource.  Accept exactly one bounded, terminal
        // node and translate its resource handles into the native allocation
        // info.  Unknown chains remain an explicit ABI refusal.
        var dedicated: abi.MemoryDedicatedAllocateInfo = .{};
        var has_dedicated = false;
        const guest_next = state.read64(info + 8);
        if (guest_next != 0) {
            if (state.guestMemoryConst(guest_next, @sizeOf(abi.MemoryDedicatedAllocateInfo)) == null or
                state.read32(guest_next) != abi.STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO or
                state.read64(guest_next + 8) != 0)
            {
                return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            }
            dedicated.s_type = abi.STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO;
            const guest_image = state.read64(guest_next + 16);
            const guest_buffer = state.read64(guest_next + 24);
            if (guest_image != 0) dedicated.image = self.real_vulkan.realImage(guest_image) orelse return vkErrorInitializationFailed();
            if (guest_buffer != 0) dedicated.buffer = self.real_vulkan.realBuffer(guest_buffer) orelse return vkErrorInitializationFailed();
            if (dedicated.image == 0 and dedicated.buffer == 0) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            has_dedicated = true;
        }

        const record = self.freeVulkanMemoryRecord() orelse return vkErrorOutOfHostMemory();
        const handle = self.nextVulkanObject();
        record.* = .{
            .handle = handle,
            .requested_size = requested_size,
        };
        self.vulkan_memory_allocations +|= 1;

        // Phase 1: when the real device is available, allocate real GPU memory.
        if (self.real_vulkan.hasDevice()) {
            const device = self.real_vulkan.device.?;
            if (self.real_vulkan.fn_ptrs.allocate_memory) |alloc_fn| {
                var alloc_info: abi.MemoryAllocateInfo = .{};
                alloc_info.allocation_size = requested_size;
                alloc_info.memory_type_index = memory_type_index;
                alloc_info.p_next = if (has_dedicated) &dedicated else null;
                var real_memory: abi.DeviceMemory = 0;
                const result = alloc_fn(device, &alloc_info, null, &real_memory);
                self.noteRealVulkanResult(result, "vkAllocateMemory");
                if (result == 0 and real_memory != 0) {
                    HandleMap.allocOrFind(&self.real_vulkan.memory_map, handle, real_memory);
                    self.vulkan_tiers.note(.device_memory, .real);
                    machoCapturePrint(
                        "macho-processor: REAL vkAllocateMemory: synthetic=0x{x} real=0x{x} size={d} type={d}\n",
                        .{ handle, real_memory, requested_size, memory_type_index },
                    );
                } else {
                    machoCapturePrint(
                        "macho-processor: REAL vkAllocateMemory FAILED: VkResult={d} size={d} type={d}\n",
                        .{ result, requested_size, memory_type_index },
                    );
                    record.* = .{};
                    return @as(u32, @bitCast(if (result != abi.SUCCESS) result else abi.ERROR_OUT_OF_DEVICE_MEMORY));
                }
            }
        }

        state.write64(output, handle);
        registerOpaqueHandle(state, handle, "Vulkan device memory");
        if (self.vulkan_memory_allocations <= 8 or self.vulkan_memory_allocations % 64 == 0) {
            machoCapturePrint(
                "macho-processor: Vulkan memory allocated: handle=0x{x} requested_size={d} output=0x{x}\n",
                .{ handle, requested_size, output },
            );
        }
        return 0;
    }

    fn mapVulkanMemory(
        self: *Forwarder,
        state: anytype,
        memory_handle: u64,
        offset: u64,
        requested_size: u64,
        output: u64,
    ) u64 {
        if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
        if (self.realDeviceLostResult()) |lost| return lost;
        // The guest-visible pointer is always a Rosette-owned window. With a
        // real device that window is explicitly copied to/from the driver map
        // during flush/invalidate; without one it remains the modelled backing
        // store. Do not mark the fact modelled before the real map succeeds.
        const max_modeled_size: u64 = 64 * 1024 * 1024;
        const record = self.findVulkanMemoryRecord(memory_handle) orelse return vkErrorInitializationFailed();
        if (offset > record.requested_size) return vkErrorInitializationFailed();
        const available_size = record.requested_size - offset;
        const map_size = if (requested_size == std.math.maxInt(u64))
            available_size
        else
            requested_size;
        if (map_size == 0 or map_size > available_size or record.requested_size > max_modeled_size) {
            return vkErrorOutOfHostMemory();
        }

        const reused = record.mapped_base != 0;
        if (!reused) {
            record.mapped_base = state.guestAlloc(record.requested_size, 16) orelse return vkErrorOutOfHostMemory();
            record.mapped_size = record.requested_size;
        } else {
            self.vulkan_memory_map_reuses +|= 1;
        }

        // Phase 1: when real GPU memory exists, also map it via the driver.
        // The guest still writes through its own address space (mapped_base);
        // the real pointer is stored for later upload during queueSubmit.
        if (self.real_vulkan.hasDevice()) {
            const map_fn = self.real_vulkan.fn_ptrs.map_memory orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            const real_mem = self.real_vulkan.realMemory(memory_handle) orelse return vkErrorInitializationFailed();
            var host_ptr: ?*anyopaque = null;
            const device = self.real_vulkan.device.?;
            const result = map_fn(device, real_mem, offset, map_size, 0, &host_ptr);
            if (result != abi.SUCCESS or host_ptr == null) {
                machoCapturePrint(
                    "macho-processor: REAL vkMapMemory FAILED: VkResult={d} synthetic=0x{x} offset={d} size={d}\n",
                    .{ result, memory_handle, offset, map_size },
                );
                return @as(u32, @bitCast(if (result != abi.SUCCESS) result else abi.ERROR_MEMORY_MAP_FAILED));
            }
            record.mapped_offset = offset;
            record.host_mapped_ptr = host_ptr;
            record.host_mapped_size = map_size;
            self.vulkan_tiers.note(.memory_mapping, .real);
            machoCapturePrint(
                "macho-processor: REAL vkMapMemory: synthetic=0x{x} real=0x{x} host_ptr=0x{x} size={d}\n",
                .{ memory_handle, real_mem, @intFromPtr(host_ptr.?), map_size },
            );
        } else {
            self.vulkan_tiers.note(.memory_mapping, .modelled);
        }

        state.write64(output, record.mapped_base + offset);
        self.vulkan_memory_maps +|= 1;
        if (self.vulkan_memory_maps <= 8 or self.vulkan_memory_maps % 64 == 0) {
            machoCapturePrint(
                "macho-processor: Vulkan memory mapped: handle=0x{x} ptr=0x{x} allocation_size={d} offset={d} requested_size={d} map_size={d} reused={} output=0x{x}\n",
                .{
                    memory_handle,
                    record.mapped_base + offset,
                    record.requested_size,
                    offset,
                    requested_size,
                    map_size,
                    reused,
                    output,
                },
            );
        }
        return 0;
    }

    fn freeVulkanMemoryRecord(self: *Forwarder) ?*VulkanMemoryAllocation {
        for (&self.vulkan_memory_records) |*record| {
            if (record.handle == 0) return record;
        }
        return null;
    }

    fn findVulkanMemoryRecord(self: *Forwarder, handle: u64) ?*VulkanMemoryAllocation {
        for (&self.vulkan_memory_records) |*record| {
            if (record.handle == handle) return record;
        }
        return null;
    }

    fn allocateVulkanObjects(self: *Forwarder, state: anytype, info: u64, output: u64, count_offset: u64, name: []const u8) u64 {
        if (self.realDeviceLostResult()) |lost| return lost;
        if (info == 0 or state.guestMemoryConst(info + count_offset, 4) == null) return vkErrorInitializationFailed();
        const count = state.read32(info + count_offset);
        if (count == 0) return 0;
        if (output == 0 or state.guestMemory(output, @as(u64, count) * 8) == null) return vkErrorInitializationFailed();

        if (std.mem.eql(u8, name, "vkAllocateCommandBuffers") and self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.allocate_command_buffers != null) {
            const pool_synthetic = state.read64(info + 16);
            const pool = self.real_vulkan.realCommandPool(pool_synthetic) orelse return vkErrorInitializationFailed();
            const real_count: u32 = @min(count, 256);
            var real_info = abi.CommandBufferAllocateInfo{
                .command_pool = pool,
                .level = state.read32(info + 24),
                .command_buffer_count = real_count,
            };
            var real_buffers: [256]abi.CommandBuffer = [_]abi.CommandBuffer{null} ** 256;
            const result = self.real_vulkan.fn_ptrs.allocate_command_buffers.?(self.real_vulkan.device.?, &real_info, &real_buffers);
            self.noteRealVulkanResult(result, "vkAllocateCommandBuffers");
            if (result != abi.SUCCESS) return @as(u32, @bitCast(result));
            for (0..real_count) |index| {
                const synthetic = self.nextVulkanObject();
                state.write64(output + @as(u64, @intCast(index)) * 8, synthetic);
                registerOpaqueHandle(state, synthetic, name);
                HandleMap.allocOrFind(&self.real_vulkan.command_buffer_map, synthetic, @intFromPtr(real_buffers[index].?));
            }
            self.vulkan_tiers.note(.command_buffer, .real);
            machoCapturePrint("macho-processor: REAL vkAllocateCommandBuffers: pool=0x{x} count={d}\n", .{ pool_synthetic, real_count });
            return 0;
        }

        if (std.mem.eql(u8, name, "vkAllocateDescriptorSets") and self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.allocate_descriptor_sets != null) {
            const pool_synthetic = state.read64(info + 16);
            const pool = self.real_vulkan.realDescriptorPool(pool_synthetic) orelse return vkErrorInitializationFailed();
            const real_count: u32 = @min(count, 256);
            const layouts_address = state.read64(info + 32);
            if (layouts_address == 0 or state.guestMemoryConst(layouts_address, @as(u64, real_count) * 8) == null) return vkErrorInitializationFailed();
            var layouts: [256]u64 = [_]u64{0} ** 256;
            for (0..real_count) |index| {
                const synthetic = state.read64(layouts_address + @as(u64, @intCast(index)) * 8);
                layouts[index] = self.real_vulkan.realDescriptorSetLayout(synthetic) orelse return vkErrorInitializationFailed();
            }
            const real_info = abi.DescriptorSetAllocateInfo{
                .descriptor_pool = pool,
                .descriptor_set_count = real_count,
                .descriptor_set_layouts = &layouts,
            };
            var real_sets: [256]u64 = [_]u64{0} ** 256;
            const result = self.real_vulkan.fn_ptrs.allocate_descriptor_sets.?(self.real_vulkan.device.?, &real_info, &real_sets);
            self.noteRealVulkanResult(result, "vkAllocateDescriptorSets");
            if (result != abi.SUCCESS) return @as(u32, @bitCast(result));
            for (0..real_count) |index| {
                const synthetic = self.nextVulkanObject();
                state.write64(output + @as(u64, @intCast(index)) * 8, synthetic);
                registerOpaqueHandle(state, synthetic, name);
                HandleMap.allocOrFind(&self.real_vulkan.descriptor_set_map, synthetic, real_sets[index]);
            }
            self.vulkan_tiers.note(.descriptor_set, .real);
            machoCapturePrint("macho-processor: REAL vkAllocateDescriptorSets: pool=0x{x} count={d}\n", .{ pool_synthetic, real_count });
            return 0;
        }

        for (0..count) |index| {
            const handle = self.nextVulkanObject();
            state.write64(output + @as(u64, @intCast(index)) * 8, handle);
            registerOpaqueHandle(state, handle, name);
        }
        machoCapturePrint("macho-processor: Vulkan objects allocated: {s} count={d} output=0x{x}\n", .{ name, count, output });
        return 0;
    }

    fn copyGuestValue(comptime T: type, state: anytype, address: u64, value: *T) bool {
        const bytes = state.guestMemoryConst(address, @sizeOf(T)) orelse return false;
        @memcpy(std.mem.asBytes(value), bytes);
        return true;
    }

    fn guestPointerValue(comptime T: type, pointer: ?[*]const T) u64 {
        return if (pointer) |value| @intFromPtr(value) else 0;
    }

    fn copyPipelineName(state: anytype, guest_pointer: u64, destination: *[64]u8) bool {
        const text = state.guestCString(guest_pointer, 63) orelse return false;
        if (text.len >= destination.len) return false;
        @memset(destination, 0);
        @memcpy(destination[0..text.len], text);
        return true;
    }

    /// Why a pipeline could not be handed to the driver. Every refusal names
    /// its own clause: a pipeline that will not marshal stops the guest's
    /// renderer outright, and "could not marshal" without a reason leaves the
    /// next reader to re-derive twenty preconditions by hand.
    const PipelineMarshalFailure = error{
        DeviceEntryPointUnavailable,
        UnknownPipelineCache,
        CreateInfoUnreadable,
        DynamicRenderingChainUnsupported,
        DynamicRenderingFormatsUnreadable,
        RenderPassSetWithDynamicRendering,
        PipelineLayoutMissing,
        UnknownPipelineLayout,
        UnknownRenderPass,
        UnknownBasePipeline,
        StageCountOutOfRange,
        StageArrayUnreadable,
        StageChainUnsupported,
        UnknownShaderModule,
        StageEntryPointUnreadable,
        SpecializationInfoUnreadable,
        SpecializationMapOutOfRange,
        SpecializationDataOutOfRange,
        VertexInputUnreadable,
        VertexInputCountsOutOfRange,
        VertexBindingsUnreadable,
        VertexAttributesUnreadable,
        VertexDivisorChainUnsupported,
        VertexDivisorsUnreadable,
        InputAssemblyUnreadable,
        TessellationUnreadable,
        ViewportStateUnreadable,
        ViewportCountsOutOfRange,
        ViewportsUnreadable,
        ScissorsUnreadable,
        RasterizationUnreadable,
        MultisampleUnreadable,
        SampleMaskUnreadable,
        DepthStencilUnreadable,
        ColorBlendUnreadable,
        ColorAttachmentCountOutOfRange,
        ColorAttachmentsUnreadable,
        DynamicStateUnreadable,
        DynamicStateCountOutOfRange,
        DynamicStatesUnreadable,
    };

    /// Marshal one optional guest array into host-owned storage.
    ///
    /// A null guest pointer stays null. Several Vulkan arrays are legally
    /// absent while their count stays non-zero — `pViewports` and `pScissors`
    /// under `VK_DYNAMIC_STATE_VIEWPORT`/`SCISSOR` are the ordinary case, and
    /// it is the case every presenter hits — so treating a null pointer as
    /// unmarshalable refuses pipelines the driver would have accepted.
    fn marshalGuestArray(
        comptime T: type,
        state: anytype,
        guest: ?[*]const T,
        count: u32,
        storage: []T,
        comptime unreadable: PipelineMarshalFailure,
    ) PipelineMarshalFailure!?[*]const T {
        const address = guestPointerValue(T, guest);
        if (address == 0 or count == 0) return null;
        if (!copyGuestStructs(T, state, address, count, storage)) return unreadable;
        return storage.ptr;
    }

    /// Host-owned storage for one shader stage's specialization constants.
    /// The map and the data blob are both guest-owned, so both are copied.
    const SpecializationScratch = struct {
        info: abi.SpecializationInfo = .{},
        entries: [32]abi.SpecializationMapEntry = undefined,
        data: [256]u8 = undefined,
    };

    fn marshalSpecializationInfo(
        state: anytype,
        guest_address: u64,
        scratch: *SpecializationScratch,
    ) PipelineMarshalFailure!*const abi.SpecializationInfo {
        if (!copyGuestValue(abi.SpecializationInfo, state, guest_address, &scratch.info)) return error.SpecializationInfoUnreadable;
        if (scratch.info.map_entry_count > scratch.entries.len) return error.SpecializationMapOutOfRange;
        if (scratch.info.data_size > scratch.data.len) return error.SpecializationDataOutOfRange;
        scratch.info.map_entries = try marshalGuestArray(
            abi.SpecializationMapEntry,
            state,
            scratch.info.map_entries,
            scratch.info.map_entry_count,
            &scratch.entries,
            error.SpecializationInfoUnreadable,
        );
        const data_address = if (scratch.info.data) |pointer| @intFromPtr(pointer) else 0;
        if (data_address == 0 or scratch.info.data_size == 0) {
            scratch.info.data = null;
            scratch.info.data_size = 0;
        } else {
            if (!copyGuestBytes(state, data_address, scratch.info.data_size, &scratch.data)) return error.SpecializationInfoUnreadable;
            scratch.info.data = @ptrCast(&scratch.data);
        }
        return &scratch.info;
    }

    fn createRealGraphicsPipeline(
        self: *Forwarder,
        state: anytype,
        cache: u64,
        guest_address: u64,
        real_output: *u64,
        result_output: *i32,
        reason: *[]const u8,
    ) bool {
        self.marshalRealGraphicsPipeline(state, cache, guest_address, real_output, result_output) catch |failure| {
            reason.* = @errorName(failure);
            return false;
        };
        return true;
    }

    fn marshalRealGraphicsPipeline(
        self: *Forwarder,
        state: anytype,
        cache: u64,
        guest_address: u64,
        real_output: *u64,
        result_output: *i32,
    ) PipelineMarshalFailure!void {
        const function = self.real_vulkan.fn_ptrs.create_graphics_pipelines orelse return error.DeviceEntryPointUnavailable;
        const real_cache = if (cache == 0) 0 else self.real_vulkan.realPipelineCache(cache) orelse return error.UnknownPipelineCache;
        var root: abi.GraphicsPipelineCreateInfo = undefined;
        if (!copyGuestValue(abi.GraphicsPipelineCreateInfo, state, guest_address, &root)) return error.CreateInfoUnreadable;
        var pipeline_rendering: abi.PipelineRenderingCreateInfo = .{};
        var pipeline_rendering_formats: [8]u32 = undefined;
        if (root.p_next) |pointer| {
            if (!copyGuestValue(abi.PipelineRenderingCreateInfo, state, @intFromPtr(pointer), &pipeline_rendering) or
                pipeline_rendering.s_type != abi.STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO or
                pipeline_rendering.p_next != null or
                pipeline_rendering.color_attachment_count > pipeline_rendering_formats.len)
            {
                return error.DynamicRenderingChainUnsupported;
            }
            pipeline_rendering.color_attachment_formats = try marshalGuestArray(
                u32,
                state,
                pipeline_rendering.color_attachment_formats,
                pipeline_rendering.color_attachment_count,
                &pipeline_rendering_formats,
                error.DynamicRenderingFormatsUnreadable,
            );
            pipeline_rendering.p_next = null;
            root.p_next = &pipeline_rendering;
            if (root.render_pass != 0) return error.RenderPassSetWithDynamicRendering;
        } else {
            root.p_next = null;
        }
        if (root.layout == 0) return error.PipelineLayoutMissing;
        root.layout = self.real_vulkan.realPipelineLayout(root.layout) orelse return error.UnknownPipelineLayout;
        if (root.render_pass != 0) root.render_pass = self.real_vulkan.realRenderPass(root.render_pass) orelse return error.UnknownRenderPass;
        if (root.base_pipeline_handle != 0) root.base_pipeline_handle = self.real_vulkan.realPipeline(root.base_pipeline_handle) orelse return error.UnknownBasePipeline;

        var stages: [8]abi.PipelineShaderStageCreateInfo = undefined;
        if (root.stage_count == 0 or root.stage_count > stages.len) return error.StageCountOutOfRange;
        const stage_address = guestPointerValue(abi.PipelineShaderStageCreateInfo, root.stages);
        if (!copyGuestStructs(abi.PipelineShaderStageCreateInfo, state, stage_address, root.stage_count, &stages)) return error.StageArrayUnreadable;
        var stage_names: [8][64]u8 = undefined;
        var specializations: [8]SpecializationScratch = undefined;
        for (stages[0..@as(usize, @intCast(root.stage_count))], 0..) |*stage, index| {
            if (stage.p_next != null) return error.StageChainUnsupported;
            stage.module = self.real_vulkan.realShaderModule(stage.module) orelse return error.UnknownShaderModule;
            if (!copyPipelineName(state, if (stage.name) |pointer| @intFromPtr(pointer) else 0, &stage_names[index])) return error.StageEntryPointUnreadable;
            stage.name = @ptrCast(&stage_names[index]);
            if (stage.specialization_info) |pointer| {
                specializations[index] = .{};
                stage.specialization_info = try marshalSpecializationInfo(state, @intFromPtr(pointer), &specializations[index]);
            }
        }
        root.stages = &stages;

        var vertex_input: abi.PipelineVertexInputStateCreateInfo = undefined;
        var bindings: [32]abi.VertexInputBindingDescription = undefined;
        var attributes: [64]abi.VertexInputAttributeDescription = undefined;
        var vertex_divisor: abi.PipelineVertexInputDivisorStateCreateInfo = .{};
        var vertex_divisors: [32]abi.VertexInputBindingDivisorDescription = undefined;
        if (root.vertex_input_state) |pointer| {
            if (!copyGuestValue(abi.PipelineVertexInputStateCreateInfo, state, @intFromPtr(pointer), &vertex_input)) return error.VertexInputUnreadable;
            if (vertex_input.vertex_binding_description_count > bindings.len or vertex_input.vertex_attribute_description_count > attributes.len) return error.VertexInputCountsOutOfRange;
            vertex_input.vertex_binding_descriptions = try marshalGuestArray(
                abi.VertexInputBindingDescription,
                state,
                vertex_input.vertex_binding_descriptions,
                vertex_input.vertex_binding_description_count,
                &bindings,
                error.VertexBindingsUnreadable,
            );
            vertex_input.vertex_attribute_descriptions = try marshalGuestArray(
                abi.VertexInputAttributeDescription,
                state,
                vertex_input.vertex_attribute_descriptions,
                vertex_input.vertex_attribute_description_count,
                &attributes,
                error.VertexAttributesUnreadable,
            );
            if (vertex_input.p_next) |next_pointer| {
                if (!copyGuestValue(abi.PipelineVertexInputDivisorStateCreateInfo, state, @intFromPtr(next_pointer), &vertex_divisor) or
                    vertex_divisor.s_type != abi.STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_DIVISOR_STATE_CREATE_INFO or
                    vertex_divisor.p_next != null or
                    vertex_divisor.vertex_binding_divisor_count > vertex_divisors.len)
                {
                    return error.VertexDivisorChainUnsupported;
                }
                vertex_divisor.vertex_binding_divisors = try marshalGuestArray(
                    abi.VertexInputBindingDivisorDescription,
                    state,
                    vertex_divisor.vertex_binding_divisors,
                    vertex_divisor.vertex_binding_divisor_count,
                    &vertex_divisors,
                    error.VertexDivisorsUnreadable,
                );
                vertex_divisor.p_next = null;
                vertex_input.p_next = &vertex_divisor;
            } else {
                vertex_input.p_next = null;
            }
            root.vertex_input_state = &vertex_input;
        }

        var input_assembly: abi.PipelineInputAssemblyStateCreateInfo = undefined;
        if (root.input_assembly_state) |pointer| {
            if (!copyGuestValue(abi.PipelineInputAssemblyStateCreateInfo, state, @intFromPtr(pointer), &input_assembly) or input_assembly.p_next != null) return error.InputAssemblyUnreadable;
            input_assembly.p_next = null;
            root.input_assembly_state = &input_assembly;
        }
        var tessellation: abi.PipelineTessellationStateCreateInfo = undefined;
        if (root.tessellation_state) |pointer| {
            if (!copyGuestValue(abi.PipelineTessellationStateCreateInfo, state, @intFromPtr(pointer), &tessellation) or tessellation.p_next != null) return error.TessellationUnreadable;
            tessellation.p_next = null;
            root.tessellation_state = &tessellation;
        }

        var viewport_state: abi.PipelineViewportStateCreateInfo = undefined;
        var viewports: [16]abi.Viewport = undefined;
        var scissors: [16]abi.Rect2D = undefined;
        if (root.viewport_state) |pointer| {
            if (!copyGuestValue(abi.PipelineViewportStateCreateInfo, state, @intFromPtr(pointer), &viewport_state) or viewport_state.p_next != null) return error.ViewportStateUnreadable;
            if (viewport_state.viewport_count > viewports.len or viewport_state.scissor_count > scissors.len) return error.ViewportCountsOutOfRange;
            // A dynamic viewport or scissor is declared by a non-zero count
            // with a null array; keep the null rather than demanding an array
            // the guest deliberately did not provide.
            viewport_state.viewports = try marshalGuestArray(abi.Viewport, state, viewport_state.viewports, viewport_state.viewport_count, &viewports, error.ViewportsUnreadable);
            viewport_state.scissors = try marshalGuestArray(abi.Rect2D, state, viewport_state.scissors, viewport_state.scissor_count, &scissors, error.ScissorsUnreadable);
            viewport_state.p_next = null;
            root.viewport_state = &viewport_state;
        }

        var rasterization: abi.PipelineRasterizationStateCreateInfo = undefined;
        if (root.rasterization_state) |pointer| {
            if (!copyGuestValue(abi.PipelineRasterizationStateCreateInfo, state, @intFromPtr(pointer), &rasterization) or rasterization.p_next != null) return error.RasterizationUnreadable;
            rasterization.p_next = null;
            root.rasterization_state = &rasterization;
        }

        var multisample: abi.PipelineMultisampleStateCreateInfo = undefined;
        var sample_mask: [8]u32 = undefined;
        if (root.multisample_state) |pointer| {
            if (!copyGuestValue(abi.PipelineMultisampleStateCreateInfo, state, @intFromPtr(pointer), &multisample) or multisample.p_next != null) return error.MultisampleUnreadable;
            if (multisample.sample_mask != null) {
                const sample_count = @min(multisample.rasterization_samples, @as(u32, 256));
                const sample_word_count = @max(@as(u32, 1), (sample_count + 31) / 32);
                multisample.sample_mask = try marshalGuestArray(u32, state, multisample.sample_mask, sample_word_count, &sample_mask, error.SampleMaskUnreadable);
            }
            multisample.p_next = null;
            root.multisample_state = &multisample;
        }

        var depth_stencil: abi.PipelineDepthStencilStateCreateInfo = undefined;
        if (root.depth_stencil_state) |pointer| {
            if (!copyGuestValue(abi.PipelineDepthStencilStateCreateInfo, state, @intFromPtr(pointer), &depth_stencil) or depth_stencil.p_next != null) return error.DepthStencilUnreadable;
            depth_stencil.p_next = null;
            root.depth_stencil_state = &depth_stencil;
        }

        var color_blend: abi.PipelineColorBlendStateCreateInfo = undefined;
        var color_attachments: [16]abi.PipelineColorBlendAttachmentState = undefined;
        if (root.color_blend_state) |pointer| {
            if (!copyGuestValue(abi.PipelineColorBlendStateCreateInfo, state, @intFromPtr(pointer), &color_blend) or color_blend.p_next != null) return error.ColorBlendUnreadable;
            if (color_blend.attachment_count > color_attachments.len) return error.ColorAttachmentCountOutOfRange;
            color_blend.attachments = try marshalGuestArray(
                abi.PipelineColorBlendAttachmentState,
                state,
                color_blend.attachments,
                color_blend.attachment_count,
                &color_attachments,
                error.ColorAttachmentsUnreadable,
            );
            color_blend.p_next = null;
            root.color_blend_state = &color_blend;
        }

        var dynamic: abi.PipelineDynamicStateCreateInfo = undefined;
        var dynamic_states: [64]u32 = undefined;
        if (root.dynamic_state) |pointer| {
            if (!copyGuestValue(abi.PipelineDynamicStateCreateInfo, state, @intFromPtr(pointer), &dynamic) or dynamic.p_next != null) return error.DynamicStateUnreadable;
            if (dynamic.dynamic_state_count > dynamic_states.len) return error.DynamicStateCountOutOfRange;
            dynamic.dynamic_states = try marshalGuestArray(u32, state, dynamic.dynamic_states, dynamic.dynamic_state_count, &dynamic_states, error.DynamicStatesUnreadable);
            dynamic.p_next = null;
            root.dynamic_state = &dynamic;
        }

        var real_pipeline: u64 = 0;
        const result = function(self.real_vulkan.device.?, real_cache, 1, @ptrCast(&root), null, @ptrCast(&real_pipeline));
        result_output.* = result;
        real_output.* = real_pipeline;
    }

    fn createRealComputePipeline(
        self: *Forwarder,
        state: anytype,
        cache: u64,
        guest_address: u64,
        real_output: *u64,
        result_output: *i32,
        reason: *[]const u8,
    ) bool {
        self.marshalRealComputePipeline(state, cache, guest_address, real_output, result_output) catch |failure| {
            reason.* = @errorName(failure);
            return false;
        };
        return true;
    }

    fn marshalRealComputePipeline(
        self: *Forwarder,
        state: anytype,
        cache: u64,
        guest_address: u64,
        real_output: *u64,
        result_output: *i32,
    ) PipelineMarshalFailure!void {
        const function = self.real_vulkan.fn_ptrs.create_compute_pipelines orelse return error.DeviceEntryPointUnavailable;
        const real_cache = if (cache == 0) 0 else self.real_vulkan.realPipelineCache(cache) orelse return error.UnknownPipelineCache;
        var root: abi.ComputePipelineCreateInfo = undefined;
        if (!copyGuestValue(abi.ComputePipelineCreateInfo, state, guest_address, &root)) return error.CreateInfoUnreadable;
        if (root.p_next != null or root.stage.p_next != null) return error.StageChainUnsupported;
        if (root.layout == 0) return error.PipelineLayoutMissing;
        root.p_next = null;
        root.stage.p_next = null;
        root.layout = self.real_vulkan.realPipelineLayout(root.layout) orelse return error.UnknownPipelineLayout;
        root.stage.module = self.real_vulkan.realShaderModule(root.stage.module) orelse return error.UnknownShaderModule;
        var stage_name: [64]u8 = undefined;
        if (!copyPipelineName(state, if (root.stage.name) |pointer| @intFromPtr(pointer) else 0, &stage_name)) return error.StageEntryPointUnreadable;
        root.stage.name = @ptrCast(&stage_name);
        var specialization: SpecializationScratch = .{};
        if (root.stage.specialization_info) |pointer| {
            root.stage.specialization_info = try marshalSpecializationInfo(state, @intFromPtr(pointer), &specialization);
        }
        if (root.base_pipeline_handle != 0) root.base_pipeline_handle = self.real_vulkan.realPipeline(root.base_pipeline_handle) orelse return error.UnknownBasePipeline;
        var real_pipeline: u64 = 0;
        const result = function(self.real_vulkan.device.?, real_cache, 1, @ptrCast(&root), null, @ptrCast(&real_pipeline));
        result_output.* = result;
        real_output.* = real_pipeline;
    }

    fn createMultipleVulkanObjects(self: *Forwarder, state: anytype, count: u64, output: u64, name: []const u8) u64 {
        if (count == 0) return 0;
        if (output == 0 or state.guestMemory(output, count * 8) == null) return vkErrorInitializationFailed();
        if (self.realDeviceLostResult()) |result| return result;
        if (self.real_vulkan.hasDevice() and (std.mem.eql(u8, name, "vkCreateGraphicsPipelines") or std.mem.eql(u8, name, "vkCreateComputePipelines"))) {
            const info_size: usize = if (std.mem.eql(u8, name, "vkCreateGraphicsPipelines")) @sizeOf(abi.GraphicsPipelineCreateInfo) else @sizeOf(abi.ComputePipelineCreateInfo);
            if (count > 64 or state.guestMemoryConst(state.regs.rcx, count * info_size) == null) return vkErrorInitializationFailed();
            for (0..@as(usize, @intCast(count))) |index| {
                const guest_info = state.regs.rcx + @as(u64, @intCast(index)) * info_size;
                var real_pipeline: u64 = 0;
                var result: i32 = 0;
                var reason: []const u8 = "unknown";
                const forwarded = if (std.mem.eql(u8, name, "vkCreateGraphicsPipelines"))
                    self.createRealGraphicsPipeline(state, state.regs.rsi, guest_info, &real_pipeline, &result, &reason)
                else
                    self.createRealComputePipeline(state, state.regs.rsi, guest_info, &real_pipeline, &result, &reason);
                if (forwarded) {
                    self.noteRealVulkanResult(result, name);
                    if (result != abi.SUCCESS) return @as(u32, @bitCast(result));
                    const synthetic = self.nextVulkanObject();
                    state.write64(output + @as(u64, @intCast(index)) * 8, synthetic);
                    registerOpaqueHandle(state, synthetic, name);
                    HandleMap.allocOrFind(&self.real_vulkan.pipeline_map, synthetic, real_pipeline);
                    self.vulkan_real_objects_created +|= 1;
                    self.vulkan_tiers.note(.pipeline, .real);
                } else {
                    // Once a real guest device exists, a synthetic pipeline is
                    // not a safe fallback: subsequent vkCmdBindPipeline would
                    // have no host object and the command stream would be
                    // silently discarded. Refuse the create instead so the
                    // guest sees the actual bridge limitation at this call.
                    machoCapturePrint(
                        "macho-processor: REAL {s}: could not marshal pipeline index={d} ({s}); refusing synthetic fallback\n",
                        .{ name, index, reason },
                    );
                    return vkErrorInitializationFailed();
                }
            }
            machoCapturePrint("macho-processor: REAL {s}: count={d}\n", .{ name, count });
            return 0;
        }
        for (0..count) |index| {
            const handle = self.nextVulkanObject();
            state.write64(output + index * 8, handle);
            registerOpaqueHandle(state, handle, name);
        }
        machoCapturePrint("macho-processor: Vulkan objects created: {s} count={d} output=0x{x}\n", .{ name, count, output });
        return 0;
    }

    pub fn openGuest(self: *Forwarder, path: []const u8, mode: u64) u64 {
        if (isVulkanLoaderPath(path)) {
            for (&self.guest_libraries, 0..) |*entry, index| {
                if (entry.token != 0) continue;
                const token = GUEST_LIBRARY_HANDLE_BASE + @as(u64, @intCast(index)) * 16 + 1;
                const path_length: u16 = @intCast(@min(path.len, entry.path.len));
                entry.* = .{ .token = token, .virtual_vulkan = true, .path_length = path_length };
                @memcpy(entry.path[0..path_length], path[0..path_length]);
                self.guest_open_count +|= 1;
                self.negotiateRosetteGpuBoundary("vulkan_loader_opened");
                machoCapturePrint(
                    "macho-processor: Vulkan guest loader virtualized: path={s} mode=0x{x} token=0x{x}; Rosette resolves typed Vulkan entry points and materializes the guest instance/device on the native loader\n",
                    .{ path, mode, token },
                );
                return token;
            }
            return 0;
        }
        var path_buffer: [1024]u8 = undefined;
        const path_z = nulTerminate(&path_buffer, path) orelse return 0;
        const host_mode: c_int = @bitCast(@as(u32, @truncate(mode)));
        const host_handle = dlopen(path_z, host_mode) orelse return 0;
        for (&self.guest_libraries, 0..) |*entry, index| {
            if (entry.token != 0) continue;
            const token = GUEST_LIBRARY_HANDLE_BASE + @as(u64, @intCast(index)) * 16 + 1;
            entry.* = .{ .token = token, .handle = host_handle };
            self.guest_open_count +|= 1;
            return token;
        }
        _ = dlclose(host_handle);
        return 0;
    }

    pub fn closeGuest(self: *Forwarder, token: u64) c_int {
        for (&self.guest_libraries) |*entry| {
            if (entry.token != token) continue;
            if (self.native_vulkan_library_token == token) self.destroyNativeVulkanObjects();
            const result: c_int = if (entry.handle) |handle| dlclose(handle) else if (entry.virtual_vulkan) 0 else -1;
            entry.* = .{};
            for (&self.guest_symbols) |*symbol| {
                if (symbol.library_token == token) symbol.* = .{};
            }
            if (result == 0) self.guest_close_count +|= 1;
            return result;
        }
        return -1;
    }

    pub fn forward(self: *Forwarder, state: anytype, dylib: []const u8, symbol: []const u8) ?Outcome {
        self.considered += 1;
        const host_symbol = normalizeMachOSymbol(symbol);
        const spec = specFor(host_symbol) orelse {
            self.rejected_not_allowlisted += 1;
            return null;
        };
        if (!libraryMatches(spec.library, dylib)) {
            self.rejected_library += 1;
            return null;
        }
        // Handle stub signatures that don't require host library calls
        if (self.handleStubSignature(state, spec.signature)) |result| {
            self.forwarded += 1;
            return result;
        }
        if (spec.signature == .guest_memory_copy) {
            const length: usize = @intCast(state.regs.rdx);
            if (length != 0) {
                const destination = state.guestMemory(state.regs.rdi, state.regs.rdx) orelse {
                    self.rejected_guest_memory += 1;
                    return null;
                };
                const source = state.guestMemoryConst(state.regs.rsi, state.regs.rdx) orelse {
                    self.rejected_guest_memory += 1;
                    return null;
                };
                std.mem.copyForwards(u8, destination[0..length], source[0..length]);
            }
            self.forwarded += 1;
            return .{ .handled = state.regs.rdi };
        }
        const handle = self.libraryHandle(dylib) orelse {
            self.rejected_library += 1;
            return null;
        };
        var symbol_buffer: [512]u8 = undefined;
        const symbol_z = nulTerminate(&symbol_buffer, host_symbol) orelse {
            self.rejected_symbol += 1;
            return null;
        };
        const address = dlsym(handle, symbol_z) orelse {
            self.rejected_symbol += 1;
            return null;
        };
        const outcome = self.invoke(state, spec.signature, address) orelse {
            self.rejected_guest_memory += 1;
            return null;
        };
        self.forwarded += 1;
        return outcome;
    }

    fn handleStubSignature(self: *Forwarder, state: anytype, signature: Signature) ?Outcome {
        return switch (signature) {
            .darwin_vm_page_size => blk: {
                self.page_size_queries +|= 1;
                if (self.page_size_queries <= 4) {
                    machoCapturePrint(
                        "macho-processor: Darwin VM page geometry query #{d}: getpagesize={d} guest_tracking_page={d} contract=host_mmap_compatible\n",
                        .{ self.page_size_queries, guest_memory_geometry.host_vm_page_size, guest_memory_geometry.guest_page_size },
                    );
                }
                break :blk .{ .handled = guest_memory_geometry.host_vm_page_size };
            },
            .guest_virtual_sleep => self.virtualGuestSleep(state),
            .locale_info_pointer => blk: {
                // Darwin CODESET is nl_item 0. Keep the returned storage in
                // guest memory rather than leaking a host libc pointer across
                // the ABI boundary. Other locale items are not currently
                // consumed by Xenia/SPIRV-Cross and receive the C-locale empty
                // string rather than an unresolved-import null.
                const text: []const u8 = if (@as(u32, @truncate(state.regs.rdi)) == 0)
                    "UTF-8"
                else
                    "";
                const address = state.guestAlloc(text.len + 1, 1) orelse return null;
                const storage = state.guestMemory(address, text.len + 1) orelse return null;
                @memcpy(storage[0..text.len], text);
                storage[text.len] = 0;
                break :blk .{ .handled = address };
            },
            .socket_three_args => .{ .handled = @bitCast(@as(i64, -1)) },
            .setsockopt_five_args => .{ .handled = 0 },
            .snprintf_three_args => blk: {
                const buffer = state.guestMemory(state.regs.rdi, state.regs.rsi) orelse return null;
                if (buffer.len > 0) buffer[0] = 0;
                break :blk .{ .handled = 0 };
            },
            .connect_three_args => .{ .handled = @bitCast(@as(i64, -1)) },
            .send_four_args => .{ .handled = 0 },
            else => null,
        };
    }

    fn virtualGuestSleep(self: *Forwarder, state: anytype) ?Outcome {
        // The Mach-O interpreter multiplexes all guest workers on one host
        // thread. Host nanosleep would freeze memory initialization, the
        // scheduler, and its watchdog together.
        const guest_duration = state.guestMemoryConst(state.regs.rdi, 8) orelse return null;
        const nanoseconds = std.mem.readInt(i64, guest_duration[0..8], .little);
        const decision = guest_sleep.classify(nanoseconds);
        const ns = decision.effective_nanoseconds;
        self.last_virtual_sleep_decision = decision;
        self.virtual_sleep_calls +|= 1;
        self.virtual_sleep_nanoseconds +|= ns;
        self.longest_virtual_sleep_nanoseconds = @max(self.longest_virtual_sleep_nanoseconds, ns);
        if (decision.repaired()) self.virtual_sleep_repairs +|= 1;
        const State = @TypeOf(state.*);
        if (self.virtual_sleep_calls <= 16 or self.virtual_sleep_calls % 1000 == 0) {
            const thread = if (comptime @hasField(State, "active_guest_thread")) state.active_guest_thread else 0;
            const step = if (comptime @hasField(State, "executed_steps")) state.executed_steps else 0;
            machoCapturePrint(
                "scheduler: virtual guest sleep #{d}: thread=0x{x} requested_ns={d} effective_ns={d} kind={s} repair={s} cumulative_ns={d} step={d} host_blocked=false\n",
                .{ self.virtual_sleep_calls, thread, nanoseconds, ns, @tagName(decision.kind), @tagName(decision.repair), self.virtual_sleep_nanoseconds, step },
            );
        }
        return .handled_void;
    }

    /// The handoff Phase 5 needs: a completed image from Xenia's host renderer,
    /// uploaded through a staging buffer and copied into a real swapchain
    /// image. `guest_swap_observed` is the caller's assertion that the guest
    /// performed the swap this image belongs to — it is the only thing that
    /// separates an authentic host frame from guest output, so it must come
    /// from an observed `VdSwap` and never from the fact that a frame arrived.
    pub fn presentXeniaOutputFrame(
        self: *Forwarder,
        pixels: []const u8,
        width: u32,
        height: u32,
        row_pitch_bytes: u64,
        orientation: rosette_gpu.frame_source.Orientation,
        guest_swap_observed: bool,
    ) rosette_gpu.FrameClassification {
        if (!self.native_presenter.stage.isReady()) return .rejected;
        const report = self.native_presenter.present(.{ .cpu_image = .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .format = self.native_presenter.surface_format.format,
            .row_pitch_bytes = row_pitch_bytes,
            .orientation = orientation,
            .fit = .letterbox,
            .producer = .xenia_host,
            .guest_swap_observed = guest_swap_observed,
        } });
        self.observeNativePresenterReport(report);
        return report.classification;
    }

    /// Point the harness at the console's own front buffer.
    ///
    /// `source` is already translated into an address this process can read;
    /// doing that translation here would mean teaching dyld about the emulated
    /// console's address space, which is two layers away from anything else in
    /// this file.
    pub fn noteGuestFrontBuffer(
        self: *Forwarder,
        source: u64,
        width: u32,
        height: u32,
        tiled: bool,
        endian: rosette_gpu.xenos_texture.Endian,
    ) void {
        const surface = rosette_gpu.XenosSurface{
            .width = width,
            .height = height,
            .endian = endian,
            .tiled = tiled,
        };
        if (!surface.presentable()) return;
        self.guest_frontbuffer_source = source;
        self.guest_frontbuffer_bytes = surface.requiredBytes();
        self.guest_frontbuffer_width = width;
        self.guest_frontbuffer_height = height;
        self.guest_frontbuffer_tiled = tiled;
        self.guest_frontbuffer_endian = endian;
    }

    /// Convert the console front buffer into pixels the presenter can copy, and
    /// publish it.
    ///
    /// Returns false — and says why through the counters — rather than
    /// presenting something wrong. The three ways this legitimately declines
    /// are all worth telling apart: the buffer is not readable, the conversion
    /// refused the surface, or the conversion succeeded and produced an image
    /// that is entirely black. The last is the one that matters here, because
    /// an allocated-but-never-rendered front buffer converts perfectly into
    /// nothing, and a black window labelled "guest output" is a worse report
    /// than no frame at all.
    fn publishGuestFrontBuffer(self: *Forwarder, state: anytype) bool {
        if (self.guest_frontbuffer_source == 0 or self.guest_frontbuffer_bytes == 0) return false;
        const surface = rosette_gpu.XenosSurface{
            .width = self.guest_frontbuffer_width,
            .height = self.guest_frontbuffer_height,
            .endian = self.guest_frontbuffer_endian,
            .tiled = self.guest_frontbuffer_tiled,
        };
        const source = state.guestMemoryConst(self.guest_frontbuffer_source, self.guest_frontbuffer_bytes) orelse {
            self.frame_inbox.noteUnusable(.source_unmapped);
            return false;
        };

        const needed = @as(u64, surface.width) * surface.height * 4;
        if (self.guest_frontbuffer_scratch == 0 or self.guest_frontbuffer_scratch_bytes < needed) {
            self.guest_frontbuffer_scratch = state.guestAlloc(needed, 16) orelse return false;
            self.guest_frontbuffer_scratch_bytes = needed;
        }
        const destination = state.guestMemory(self.guest_frontbuffer_scratch, needed) orelse return false;

        if (rosette_gpu.xenos_texture.convertToBgra8(source, surface, destination)) |failure| {
            self.guest_frontbuffer_conversion_failures +|= 1;
            self.guest_frontbuffer_last_failure = failure;
            self.frame_inbox.noteUnusable(switch (failure) {
                .unsupported_format => .format_unsupported,
                .implausible_extent => .malformed_descriptor,
                .source_too_small, .destination_too_small => .source_truncated,
            });
            return false;
        }
        self.guest_frontbuffer_conversions +|= 1;

        var written = false;
        for (destination) |byte| {
            if (byte != 0) {
                written = true;
                break;
            }
        }
        if (!written) {
            // Named precisely: the buffer exists, is mapped, converted cleanly,
            // and holds no picture. That is a statement about the emulator's
            // rendering, not about this path.
            self.frame_inbox.noteUnusable(.never_published);
            return false;
        }
        self.guest_frontbuffer_nonzero_frames +|= 1;

        const serial = self.frame_inbox.publish(.{
            .source_address = self.guest_frontbuffer_scratch,
            .source_length = needed,
            .width = surface.width,
            .height = surface.height,
            .format = self.native_presenter.surface_format.format,
            .row_pitch_bytes = @as(u64, surface.width) * 4,
            .orientation = .top_down,
            .fit = .letterbox,
            .producer = .xenia_host,
            // Set by the swap observation, never by a frame having arrived.
            .guest_swap_observed = false,
        });
        if (serial == 0) return false;
        if (self.guest_frontbuffer_nonzero_frames == 1) {
            machoCapturePrint(
                "macho-processor: GUEST FRONT BUFFER PRESENTED: extent={d}x{d} tiled={s} endian={s} source=0x{x} bytes={d} serial={d}; these are the console's own pixels, converted from its framebuffer rather than from an emulator Vulkan image\n",
                .{
                    surface.width,                      surface.height,
                    if (surface.tiled) "YES" else "NO", surface.endian.label(),
                    self.guest_frontbuffer_source,      self.guest_frontbuffer_bytes,
                    serial,
                },
            );
        }
        return true;
    }

    /// Called when the guest's own bootstrap observes a `VdSwap`, so a frame
    /// discovered afterwards may be classified as guest output. Kept separate
    /// from frame delivery because a frame arriving is not a swap happening,
    /// and merging them is exactly how a host frame becomes mislabelled.
    pub fn noteGuestSwapObserved(self: *Forwarder) void {
        self.frame_provenance.noteGuestRingPacket();
        self.native_presenter.ledger.noteGuestRingPacket();
    }

    /// The window changed size or backing scale. The swapchain is rebuilt from
    /// the surface's own capabilities at the next frame rather than from these
    /// numbers, which are only the fallback for a surface with no fixed size.
    pub fn noteNativeWindowResize(self: *Forwarder, width: u32, height: u32) void {
        if (self.native_presenter.stage.isReady()) self.native_presenter.noteResize(width, height);
    }

    pub fn nativePresenterStage(self: *const Forwarder) rosette_gpu.NativePresenterStage {
        return self.native_presenter.stage;
    }

    /// Drive the presenter because nothing else will.
    ///
    /// The emulator refreshes its output when it processes a swap. A title that
    /// never swaps therefore produces `refresh_attempt_count=0` forever, and
    /// the emulator's own zero-refresh watchdog fires over and over reporting a
    /// condition nobody is acting on.
    ///
    /// Rosette owns the presenter, so it can attempt the refresh itself. This
    /// is not a fabricated frame: the source is still whatever
    /// `discoverGuestFrameSource` can find, and when it finds nothing the
    /// window shows a frame labelled diagnostic exactly as before. What changes
    /// is that the attempt *happens* — so the frame-source scan runs on a
    /// cadence and the first guest pixels to exist anywhere reach the window
    /// without waiting for a swap that may never come.
    ///
    /// Returns whether a frame was put up. Attempts are counted separately from
    /// successes because "we tried and there was nothing" and "we never tried"
    /// are the two states this exists to separate.
    pub fn attemptScheduledRefresh(self: *Forwarder, state: anytype) bool {
        if (!self.native_presenter.stage.isReady()) return false;
        self.scheduled_refresh_attempts +|= 1;
        const presented = self.presentWindowFrame(state, self.scheduled_refresh_attempts, 0, 0, 4);
        if (presented) self.scheduled_refresh_successes +|= 1;
        return presented;
    }

    pub fn logScheduledRefresh(self: *const Forwarder) void {
        if (self.scheduled_refresh_attempts == 0) return;
        machoCapturePrint(
            "macho-processor: SCHEDULED REFRESH: attempts={d} successes={d} guest_frontbuffer_frames={d}; the emulator refreshes its output only when it processes a swap, so a title that never swaps leaves the presenter idle forever. These attempts run the frame-source scan on a cadence instead — the source is still whatever the guest actually produced, and when that is nothing the window keeps showing a frame labelled diagnostic\n",
            .{
                self.scheduled_refresh_attempts,
                self.scheduled_refresh_successes,
                self.guest_frontbuffer_nonzero_frames,
            },
        );
    }

    /// Frames Rosette's own Vulkan presenter has put on the window, of any
    /// class.
    ///
    /// The graphics contract needs this to decide whether presentation was ever
    /// negotiated, and it was previously keyed on the *Metal* diagnostic path
    /// alone. A run whose whole presentation stack came up through Vulkan
    /// therefore reported `presentation capability negotiated` as outstanding
    /// harness work while the presenter was on screen — which sends a reader to
    /// write code that already exists.
    pub fn nativePresenterFramesPresented(self: *const Forwarder) u64 {
        const ledger = &self.native_presenter.ledger;
        return ledger.diagnostic_frames_presented +|
            ledger.host_frames_presented +|
            ledger.guest_output_frames_presented;
    }

    /// Real guest Vulkan progress, kept separate from Rosette's presenter
    /// ledger.  A queue submission or command call is evidence that the
    /// guest's object mapping reached the host driver; it is not by itself
    /// evidence that a visible frame was produced.
    pub fn guestVulkanDeviceReady(self: *const Forwarder) bool {
        return self.real_vulkan.deviceUsable();
    }

    pub fn guestVulkanDeviceLost(self: *const Forwarder) bool {
        return self.real_vulkan.device_lost;
    }

    pub fn guestVulkanCommandsForwarded(self: *const Forwarder) u64 {
        return self.vulkan_real_command_calls;
    }

    pub fn guestVulkanQueueSubmits(self: *const Forwarder) u64 {
        return self.vulkan_real_queue_submits;
    }

    pub fn guestVulkanPresents(self: *const Forwarder) u64 {
        return self.vulkan_real_presents;
    }

    pub fn guestVulkanObservedCommands(self: *const Forwarder) u64 {
        return self.vulkan_modeled_command_calls;
    }

    pub fn virtualSleepCallCount(self: *const Forwarder) u64 {
        return self.virtual_sleep_calls;
    }

    pub fn lastVirtualSleepDecision(self: *const Forwarder) guest_sleep.Decision {
        return self.last_virtual_sleep_decision;
    }

    pub fn logSummary(self: *const Forwarder) void {
        machoCapturePrint(
            "macho-processor: dynamic library forwarding: considered={d} forwarded={d} guest_open={d} guest_close={d} guest_lookup={d} proc_queries={d} guest_thunk_calls={d} opaque_calls={d} not_allowlisted={d} library_rejected={d} symbol_missing={d} guest_memory_rejected={d} page_geometry_queries={d} virtual_sleep(calls/total_effective_ns/longest_effective_ns/repairs)={d}/{d}/{d}/{d}\n",
            .{
                self.considered,
                self.forwarded,
                self.guest_open_count,
                self.guest_close_count,
                self.guest_lookup_count,
                self.guest_proc_queries,
                self.guest_thunk_calls,
                self.guest_opaque_calls,
                self.rejected_not_allowlisted,
                self.rejected_library,
                self.rejected_symbol,
                self.rejected_guest_memory,
                self.page_size_queries,
                self.virtual_sleep_calls,
                self.virtual_sleep_nanoseconds,
                self.longest_virtual_sleep_nanoseconds,
                self.virtual_sleep_repairs,
            },
        );
        if (self.gpu_handshake_updates != 0) {
            const response = &self.gpu_handshake_response;
            machoCapturePrint(
                "macho-processor: Rosette GPU runtime: handshake_updates={d} attempts={d} successes={d} failures={d} trace_events={d} backend={s} status={s} API={d} adapter={s} buffer_alignment={d} image_alignment={d} guest_mapping_alignment={d} detail={s}\n",
                .{
                    self.gpu_handshake_updates,
                    self.gpu_runtime.handshake_attempts,
                    self.gpu_runtime.handshake_successes,
                    self.gpu_runtime.handshake_failures,
                    self.gpu_runtime.trace_sequence,
                    @tagName(response.backendValue()),
                    @tagName(response.statusValue()),
                    response.version,
                    self.gpu_runtime.adapter.description.adapterName(),
                    response.buffer_alignment,
                    response.image_alignment,
                    response.guest_mapping_alignment,
                    response.reasonSlice(),
                },
            );
        }
        if (self.guest_proc_queries != 0) {
            machoCapturePrint(
                "macho-processor: Vulkan lifecycle: device={d} queue={d} metal_surface={d} swapchain={d} swapchain_images={d} acquired={d} submits={d} presents={d} memory(alloc/maps/reuses)={d}/{d}/{d} opaque={d} presenter(stage/attempts/failures/off_ui_calls)={s}/{d}/{d}/{d}\n",
                .{
                    self.vulkan_logical_devices_created,
                    self.vulkan_queues_acquired,
                    self.vulkan_metal_surfaces_created,
                    self.vulkan_swapchains_created,
                    self.vulkan_swapchain_images_enumerated,
                    self.vulkan_images_acquired,
                    self.vulkan_queue_submits,
                    self.vulkan_presents,
                    self.vulkan_memory_allocations,
                    self.vulkan_memory_maps,
                    self.vulkan_memory_map_reuses,
                    self.guest_opaque_calls,
                    @tagName(self.vulkan_presenter_stage),
                    self.vulkan_presenter_bind_attempts,
                    self.vulkan_presenter_bind_failures,
                    self.vulkan_presenter_off_ui_calls,
                },
            );
            machoCapturePrint(
                "macho-processor: native Vulkan surface backing: loader(attempts/failures)={d}/{d} instance_attempts={d} surface_attempts={d} failures={d} instance=0x{x} host_surface=0x{x} library_token=0x{x}\n",
                .{ self.native_vulkan_loader_attempts, self.native_vulkan_loader_failures, self.native_vulkan_instance_attempts, self.native_vulkan_surface_attempts, self.native_vulkan_failures, if (self.native_vulkan_instance) |instance| @intFromPtr(instance) else 0, self.native_vulkan_surface, self.native_vulkan_library_token },
            );
            machoCapturePrint(
                "macho-processor: Vulkan forwarding contract: guest_objects=REAL_WHEN_DEVICE_READY fallback=MODELLED real_device={} device_lost={} real_objects(created/destroyed)={d}/{d} commands(real/observed)={d}/{d} queue_submits(real/observed)={d}/{d} presents(real/observed)={d}/{d} fence_completions={d} rosette_presenter={s} capability_queries={d} device_void_calls={d}\n",
                .{
                    self.real_vulkan.hasDevice(),
                    self.real_vulkan.device_lost,
                    self.vulkan_real_objects_created,
                    self.vulkan_real_objects_destroyed,
                    self.vulkan_real_command_calls,
                    self.vulkan_modeled_command_calls,
                    self.vulkan_real_queue_submits,
                    self.vulkan_queue_submits,
                    self.vulkan_real_presents,
                    self.vulkan_presents,
                    self.vulkan_fence_completions,
                    @tagName(self.native_presenter.stage),
                    self.vulkan_surface_capability_queries,
                    self.vulkan_device_void_calls,
                },
            );
            self.logGraphicsProvenance();
            machoCapturePrint("macho-processor: Vulkan proc inventory:\n", .{});
            for (&self.guest_symbols) |*entry| {
                if (entry.token == 0) continue;
                machoCapturePrint(
                    "  token=0x{x} kind={s} calls={d} name={s}\n",
                    .{ entry.token, @tagName(entry.kind), entry.calls, entry.name[0..entry.name_length] },
                );
            }
        }
    }

    /// The presentation-provenance block, emitted on a schedule rather than
    /// only at exit.
    ///
    /// A run killed by the harness timeout produced none of these lines, which
    /// made every graphics counter in that run unavailable precisely because
    /// the run was the interesting kind. A diagnostic that requires a clean
    /// shutdown is a diagnostic for the runs that did not need it.
    /// Whether the harness holds a console framebuffer it could present. Read
    /// by the substitution policy, which has to know the difference between "no
    /// frame because nothing was found" and "no frame because the one that was
    /// found held no picture".
    pub fn guestFrontBufferAvailable(self: *const Forwarder) bool {
        return self.guest_frontbuffer_nonzero_frames != 0;
    }

    /// What the console-framebuffer path has done, and where it stopped.
    ///
    /// Printed on its own line rather than folded into the Vulkan lifecycle,
    /// because it answers a question none of those counters can: whether the
    /// console's framebuffer holds a picture at all. A conversion that succeeds
    /// and yields an entirely black image is the single most informative
    /// outcome here — it says the memory is right and the rendering never
    /// happened — and it is invisible in any counter that only tallies frames.
    /// Where the real driver and the modelled layer meet.
    ///
    /// Printed even when consistent: "no seam" is the statement that makes a
    /// later seam legible, and a migration that silently grew one is exactly
    /// the failure this exists to catch.
    pub fn logVulkanTiers(self: *const Forwarder) void {
        const ledger = &self.vulkan_tiers;
        const finding = ledger.finding();
        if (finding == .unknown) return;
        machoCapturePrint(
            "macho-processor: VULKAN TIER CONSISTENCY: finding={s} real={d} modelled={d} of {d} marshal_refusals={d}; {s}\n",
            .{
                finding.label(),
                ledger.realCount(),
                ledger.modelledCount(),
                tier_consistency.facet_count,
                self.vulkan_marshal_refusals,
                ledger.verdict(),
            },
        );
        inline for (@typeInfo(tier_consistency.Facet).@"enum".fields) |field| {
            const facet: tier_consistency.Facet = @enumFromInt(field.value);
            const served = ledger.tier(facet);
            if (served != .unknown or ledger.servedBothWays(facet)) machoCapturePrint(
                "  facet {s: <24} {s}{s}\n",
                .{
                    facet.label(),
                    served.label(),
                    if (ledger.servedBothWays(facet))
                        " (SERVED BOTH WAYS — the answer depends on which path the caller took to ask)"
                    else
                        "",
                },
            );
        }
        var splits: [tier_consistency.pairs.len]tier_consistency.Split = undefined;
        for (ledger.splits(&splits)) |split| {
            machoCapturePrint(
                "macho-processor: VULKAN TIER CONSISTENCY: SPLIT {s}={s} vs {s}={s} — {s}\n",
                .{
                    split.pair.left.label(),
                    split.left_tier.label(),
                    split.pair.right.label(),
                    split.right_tier.label(),
                    split.pair.consequence,
                },
            );
        }
    }

    pub fn logGuestFrontBuffer(self: *const Forwarder) void {
        if (self.guest_frontbuffer_source == 0) {
            machoCapturePrint(
                "macho-processor: GUEST FRONT BUFFER: never offered. No swap packet has named a front buffer, so the console's framebuffer address is unknown and nothing but a diagnostic frame can reach the window\n",
                .{},
            );
            return;
        }
        machoCapturePrint(
            "macho-processor: GUEST FRONT BUFFER: source=0x{x} bytes={d} extent={d}x{d} tiled={s} endian={s} conversions={d} failures={d} nonzero_frames={d} last_failure={s}; {s}\n",
            .{
                self.guest_frontbuffer_source,
                self.guest_frontbuffer_bytes,
                self.guest_frontbuffer_width,
                self.guest_frontbuffer_height,
                if (self.guest_frontbuffer_tiled) "YES" else "NO",
                self.guest_frontbuffer_endian.label(),
                self.guest_frontbuffer_conversions,
                self.guest_frontbuffer_conversion_failures,
                self.guest_frontbuffer_nonzero_frames,
                if (self.guest_frontbuffer_last_failure) |failure| failure.label() else "-",
                if (self.guest_frontbuffer_nonzero_frames != 0)
                    "the console's framebuffer holds a picture and it is reaching the window"
                else if (self.guest_frontbuffer_conversions != 0)
                    "the console's framebuffer is readable and converts cleanly, and every pixel in it is zero. The memory is right and the rendering never happened: nothing wrote this buffer, which puts the frontier in the emulator's GPU execution and not in this path"
                else if (self.guest_frontbuffer_conversion_failures != 0)
                    "the console's framebuffer was found and could not be converted; the failure above names which of the surface's stated facts the memory does not support"
                else
                    "a front buffer address is known and no conversion has been attempted yet",
            },
        );
    }

    pub fn logGraphicsProvenance(self: *const Forwarder) void {
        const presenter = &self.native_presenter;
        const presenter_ledger = &presenter.ledger;
        {
            // The counters the audit requires never to be conflated. Each
            // answers a different question and none is a sum of the others.
            machoCapturePrint(
                "macho-processor: PRESENTATION PROVENANCE: guest_vulkan_calls_seen={d} native_driver_calls={d} native_submissions={d} native_present_requests={d} diagnostic_metal_frames={d} native_diagnostic_frames={d} xenia_host_frames={d} guest_output_frames={d} claims_demoted={d} guest_ring_packets={d}\n",
                .{
                    self.frame_provenance.guest_vulkan_calls_seen,
                    presenter_ledger.native_driver_calls,
                    presenter_ledger.native_submissions,
                    presenter_ledger.native_present_requests,
                    self.frame_provenance.diagnostic_frames_presented,
                    presenter_ledger.diagnostic_frames_presented,
                    presenter_ledger.host_frames_presented,
                    presenter_ledger.guest_output_frames_presented,
                    presenter_ledger.claims_demoted + self.frame_provenance.claims_demoted,
                    presenter_ledger.guest_ring_packets,
                },
            );
            // The Phase 5 handoff, reported as a chain so the first broken link
            // is visible rather than inferred from a frame count of zero.
            machoCapturePrint(
                "macho-processor: GUEST FRAME SOURCE: images_tracked={d} image_bindings={d} resource_overflow={d} scans={d} discoveries={d} published={d} consumed={d} dropped={d} blit_supported={s} filter={d} absence={s}\n",
                .{
                    self.trackedImageCount(),
                    self.vulkan_image_bindings,
                    self.vulkan_resource_overflow,
                    self.frame_source_scans,
                    self.frame_source_discoveries,
                    self.frame_inbox.published,
                    self.frame_inbox.consumed,
                    self.frame_inbox.dropped,
                    if (presenter.report.blit_supported) "YES" else "NO",
                    presenter.report.blit_filter,
                    self.frame_inbox.absence().label(),
                },
            );
            machoCapturePrint(
                "macho-processor: graphics visibility: guest_output={s} first_non_native_pixel_stage={s} next={s} display_note={s}\n",
                .{
                    if (presenter_ledger.guest_output_frames_presented != 0) "YES" else "NO",
                    if (self.forwarding_contract.firstNonNativePixelStage()) |stage| stage.label() else "none",
                    presenter.blockingReason(),
                    presenter_ledger.displayNote(),
                },
            );
        }
    }

    fn libraryHandle(self: *Forwarder, dylib: []const u8) ?*anyopaque {
        for (self.libraries[0..self.library_count]) |loaded_library| {
            if (std.mem.eql(u8, loaded_library.path, dylib)) return loaded_library.handle;
        }
        if (self.library_count >= self.libraries.len) return null;

        var path_buffer: [1024]u8 = undefined;
        const path_z = nulTerminate(&path_buffer, dylib) orelse return null;
        const handle = dlopen(path_z, RTLD_LAZY | RTLD_LOCAL);
        self.libraries[self.library_count] = .{ .path = dylib, .handle = handle };
        self.library_count += 1;
        return handle;
    }

    fn guestLibraryEntry(self: *Forwarder, token: u64) ?*GuestLibrary {
        for (&self.guest_libraries) |*entry| {
            if (entry.token == token) return entry;
        }
        return null;
    }

    fn guestLibrary(self: *Forwarder, token: u64) ?*anyopaque {
        const entry = self.guestLibraryEntry(token) orelse return null;
        return entry.handle;
    }

    fn materializeNativeVulkanLibrary(self: *Forwarder, token: u64) ?*anyopaque {
        const entry = self.guestLibraryEntry(token) orelse return null;
        if (entry.handle) |handle| return handle;
        if (!entry.virtual_vulkan or entry.path_length == 0) return null;
        const path = entry.path[0..entry.path_length];
        var path_buffer: [1024]u8 = undefined;
        const path_z = nulTerminate(&path_buffer, path) orelse return null;
        self.native_vulkan_loader_attempts +|= 1;
        machoCapturePrint(
            "macho-processor: native Vulkan loader begin: attempt={d} path={s}; entering host dlopen/dyld initializers\n",
            .{ self.native_vulkan_loader_attempts, path },
        );
        const handle = dlopen(path_z, RTLD_LAZY | RTLD_LOCAL) orelse {
            self.native_vulkan_loader_failures +|= 1;
            machoCapturePrint(
                "macho-processor: native Vulkan loader failed: attempt={d} path={s}\n",
                .{ self.native_vulkan_loader_attempts, path },
            );
            return null;
        };
        entry.handle = handle;
        machoCapturePrint("macho-processor: BOOTUP MILESTONE: native Vulkan library loaded via host dlopen — path={s} handle=0x{x}\n", .{ path, @intFromPtr(handle) });
        machoCapturePrint(
            "macho-processor: native Vulkan loader ready: attempt={d} path={s} host_handle=0x{x}\n",
            .{ self.native_vulkan_loader_attempts, path, @intFromPtr(handle) },
        );
        return handle;
    }

    fn invoke(self: *Forwarder, state: anytype, signature: Signature, address: *anyopaque) ?Outcome {
        return switch (signature) {
            .no_args_i32 => blk: {
                const function: *const fn () callconv(.c) c_int = @ptrCast(@alignCast(address));
                break :blk .{ .handled = @bitCast(@as(i64, function())) };
            },
            .no_args_u32 => blk: {
                const function: *const fn () callconv(.c) c_uint = @ptrCast(@alignCast(address));
                break :blk .{ .handled = function() };
            },
            .darwin_vm_page_size => .{ .handled = guest_memory_geometry.host_vm_page_size },
            .buffer_length_usize => blk: {
                const bytes = state.guestMemoryConst(state.regs.rdi, state.regs.rsi) orelse return null;
                const function: *const fn ([*]const u8, usize) callconv(.c) usize = @ptrCast(@alignCast(address));
                break :blk .{ .handled = function(bytes.ptr, bytes.len) };
            },
            .two_buffers_length_i32 => blk: {
                const lhs = state.guestMemoryConst(state.regs.rdi, state.regs.rdx) orelse return null;
                const rhs = state.guestMemoryConst(state.regs.rsi, state.regs.rdx) orelse return null;
                const function: *const fn ([*]const u8, [*]const u8, usize) callconv(.c) c_int = @ptrCast(@alignCast(address));
                break :blk .{ .handled = @bitCast(@as(i64, function(lhs.ptr, rhs.ptr, lhs.len))) };
            },
            .buffer_byte_length_pointer => blk: {
                const bytes = state.guestMemoryConst(state.regs.rdi, state.regs.rdx) orelse return null;
                const function: *const fn ([*]const u8, c_int, usize) callconv(.c) ?*const u8 = @ptrCast(@alignCast(address));
                const found = function(bytes.ptr, @intCast(state.regs.rsi & 0xFF), bytes.len) orelse break :blk .{ .handled = 0 };
                const offset = @intFromPtr(found) - @intFromPtr(bytes.ptr);
                if (offset >= bytes.len) return null;
                break :blk .{ .handled = state.regs.rdi + offset };
            },
            .guest_memory_copy => blk: {
                const length: usize = @intCast(state.regs.rdx);
                if (length != 0) {
                    const destination = state.guestMemory(state.regs.rdi, state.regs.rdx) orelse return null;
                    const source = state.guestMemoryConst(state.regs.rsi, state.regs.rdx) orelse return null;
                    std.mem.copyForwards(u8, destination[0..length], source[0..length]);
                }
                break :blk .{ .handled = state.regs.rdi };
            },
            .libcxx_getloc => blk: {
                // ios_base::getloc() - takes ios_base pointer in rdi, returns locale pointer in rax
                // We can't directly forward this because the guest and host have different memory layouts
                // For now, return a dummy locale pointer
                break :blk .{ .handled = 0x3000 };
            },
            .libcxx_istream_sentry_constructor => blk: {
                // basic_istream::sentry constructor - takes sentry pointer in rdi, istream pointer in rsi, bool in rdx
                // We can't directly forward this because the guest and host have different memory layouts
                // For now, just zero-initialize the sentry and return void
                const sentry_bytes = state.guestMemory(state.regs.rdi, 16) orelse return null;
                @memset(sentry_bytes, 0);
                break :blk .handled_void;
            },
            .guest_virtual_sleep => self.virtualGuestSleep(state),
            .locale_info_pointer => unreachable,
            .socket_three_args => blk: {
                // These are handled by handleStubSignature and should never reach here
                break :blk .{ .handled = @bitCast(@as(i64, -1)) };
            },
            .setsockopt_five_args => blk: {
                // These are handled by handleStubSignature and should never reach here
                break :blk .{ .handled = 0 };
            },
            .snprintf_three_args => blk: {
                // These are handled by handleStubSignature and should never reach here
                break :blk .{ .handled = 0 };
            },
            .connect_three_args => blk: {
                // These are handled by handleStubSignature and should never reach here
                break :blk .{ .handled = @bitCast(@as(i64, -1)) };
            },
            .send_four_args => blk: {
                // These are handled by handleStubSignature and should never reach here
                break :blk .{ .handled = 0 };
            },
            .cccrypt => blk: {
                const key = state.guestMemoryConst(state.regs.rcx, 16) orelse return null;
                const iv = state.guestMemoryConst(state.regs.r9, 16) orelse return null;
                const data_in_addr = state.read64(state.regs.rsp + 8);
                const data_in_length = state.read64(state.regs.rsp + 16);
                const data_out_addr = state.read64(state.regs.rsp + 24);
                const data_out_avail = state.read64(state.regs.rsp + 32);
                const data_out_moved_addr = state.read64(state.regs.rsp + 40);
                const data_in = state.guestMemoryConst(data_in_addr, data_in_length) orelse return null;
                const data_out = state.guestMemory(data_out_addr, data_out_avail) orelse return null;
                const CCCryptFn = *const fn (c_uint, c_uint, c_uint, *const anyopaque, usize, *const anyopaque, *const anyopaque, usize, *anyopaque, usize, *usize) callconv(.c) c_int;
                const function: CCCryptFn = @ptrCast(@alignCast(address));
                var moved: usize = 0;
                const result = function(
                    @as(c_uint, @truncate(state.regs.rdi)),
                    @as(c_uint, @truncate(state.regs.rsi)),
                    @as(c_uint, @truncate(state.regs.rdx)),
                    @ptrCast(key.ptr),
                    @as(usize, @intCast(state.regs.r8)),
                    @ptrCast(iv.ptr),
                    @ptrCast(data_in.ptr),
                    data_in_length,
                    @ptrCast(data_out.ptr),
                    data_out_avail,
                    &moved,
                );
                state.write64(data_out_moved_addr, moved);
                break :blk .{ .handled = @bitCast(@as(i64, result)) };
            },
            .pointer_in_pointer_out => blk: {
                const tm = state.guestMemoryConst(state.regs.rdi, 64) orelse {
                    const fallback = state.guestMemory(state.regs.rsp - 64, 4) orelse break :blk .{ .handled = 0 };
                    @memcpy(fallback, "???\x00");
                    break :blk .{ .handled = state.regs.rsp - 64 };
                };
                const function: *const fn ([*]const u8) callconv(.c) [*:0]const u8 = @ptrCast(@alignCast(address));
                const result = function(tm.ptr);
                const result_bytes = std.mem.sliceTo(result, 0);
                const buf_len = @min(result_bytes.len + 1, 256);
                const guest_buf = state.guestMemory(state.regs.rsp - 64, buf_len) orelse break :blk .{ .handled = 0 };
                @memcpy(guest_buf[0..result_bytes.len], result_bytes);
                if (result_bytes.len < buf_len) guest_buf[result_bytes.len] = 0;
                break :blk .{ .handled = state.regs.rsp - 64 };
            },
        };
    }
};

/// FNV-1a 64-bit. Mirrors `dispatch.importNameHash`: the forwarder cannot
/// import the import-handler module, so the five-line hash is repeated here
/// with the same constants. Computed once per guest symbol at allocation;
/// const-folded at comptime for the literal spellings in the command chain.
fn vulkanNameHash(name: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (name) |byte| {
        hash = (hash ^ byte) *% 1099511628211;
    }
    return hash;
}

fn guestSymbolKind(symbol: []const u8) GuestSymbolKind {
    if (std.mem.eql(u8, symbol, "vkGetInstanceProcAddr")) return .get_instance_proc_addr;
    if (std.mem.eql(u8, symbol, "vkGetDeviceProcAddr")) return .get_device_proc_addr;
    if (std.mem.eql(u8, symbol, "vkEnumerateInstanceExtensionProperties")) return .enumerate_instance_extensions;
    if (std.mem.eql(u8, symbol, "vkEnumerateInstanceLayerProperties")) return .enumerate_instance_layers;
    if (std.mem.eql(u8, symbol, "vkEnumerateInstanceVersion")) return .enumerate_instance_version;
    if (std.mem.eql(u8, symbol, "vkCreateInstance")) return .create_instance;
    if (std.mem.eql(u8, symbol, "vkDestroyInstance")) return .destroy_instance;
    if (std.mem.eql(u8, symbol, "vkEnumeratePhysicalDevices")) return .enumerate_physical_devices;
    if (std.mem.eql(u8, symbol, "vkEnumerateDeviceExtensionProperties")) return .enumerate_device_extensions;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceFeatures")) return .get_physical_device_features;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceFormatProperties")) return .get_physical_device_format_properties;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceMemoryProperties")) return .get_physical_device_memory_properties;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceProperties")) return .get_physical_device_properties;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceQueueFamilyProperties")) return .get_physical_device_queue_families;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceFeatures2KHR") or
        std.mem.eql(u8, symbol, "vkGetPhysicalDeviceFeatures2")) return .get_physical_device_features2;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceMemoryProperties2KHR") or
        std.mem.eql(u8, symbol, "vkGetPhysicalDeviceMemoryProperties2")) return .get_physical_device_memory_properties2;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceProperties2KHR") or
        std.mem.eql(u8, symbol, "vkGetPhysicalDeviceProperties2")) return .get_physical_device_properties2;
    if (std.mem.eql(u8, symbol, "vkCreateDevice")) return .create_device;
    if (std.mem.eql(u8, symbol, "vkGetDeviceQueue")) return .get_device_queue;
    if (std.mem.eql(u8, symbol, "vkGetDeviceQueue2")) return .get_device_queue2;
    if (std.mem.eql(u8, symbol, "vkGetSemaphoreCounterValue") or std.mem.eql(u8, symbol, "vkGetSemaphoreCounterValueKHR")) return .get_semaphore_counter_value;
    if (std.mem.eql(u8, symbol, "vkWaitSemaphores") or std.mem.eql(u8, symbol, "vkWaitSemaphoresKHR")) return .wait_semaphores;
    if (std.mem.eql(u8, symbol, "vkSignalSemaphore") or std.mem.eql(u8, symbol, "vkSignalSemaphoreKHR")) return .signal_semaphore;
    if (std.mem.eql(u8, symbol, "vkCreateMetalSurfaceEXT")) return .create_metal_surface;
    if (std.mem.eql(u8, symbol, "vkDestroySurfaceKHR")) return .destroy_surface;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR")) return .get_surface_capabilities;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceSurfaceFormatsKHR")) return .get_surface_formats;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceSurfacePresentModesKHR")) return .get_surface_present_modes;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceSurfaceSupportKHR")) return .get_surface_support;
    if (std.mem.eql(u8, symbol, "vkDestroyDevice")) return .destroy_device;
    if (std.mem.eql(u8, symbol, "vkCreateSwapchainKHR")) return .create_swapchain;
    if (std.mem.eql(u8, symbol, "vkDestroySwapchainKHR")) return .destroy_swapchain;
    if (std.mem.eql(u8, symbol, "vkGetSwapchainImagesKHR")) return .get_swapchain_images;
    if (std.mem.eql(u8, symbol, "vkAcquireNextImageKHR")) return .acquire_next_image;
    if (std.mem.eql(u8, symbol, "vkQueueSubmit")) return .queue_submit;
    if (std.mem.eql(u8, symbol, "vkQueueSubmit2") or std.mem.eql(u8, symbol, "vkQueueSubmit2KHR")) return .queue_submit2;
    if (std.mem.eql(u8, symbol, "vkQueueBindSparse")) return .queue_bind_sparse;
    if (std.mem.eql(u8, symbol, "vkQueuePresentKHR")) return .queue_present;
    if (std.mem.eql(u8, symbol, "vkQueueWaitIdle")) return .queue_wait_idle;
    if (std.mem.eql(u8, symbol, "vkAllocateMemory")) return .allocate_memory;
    if (std.mem.eql(u8, symbol, "vkMapMemory")) return .map_memory;
    if (std.mem.eql(u8, symbol, "vkBindImageMemory2") or
        std.mem.eql(u8, symbol, "vkBindImageMemory2KHR")) return .bind_image_memory2;
    if (std.mem.eql(u8, symbol, "vkBindBufferMemory2") or
        std.mem.eql(u8, symbol, "vkBindBufferMemory2KHR")) return .bind_buffer_memory2;
    if (std.mem.eql(u8, symbol, "vkGetBufferMemoryRequirements2") or
        std.mem.eql(u8, symbol, "vkGetBufferMemoryRequirements2KHR") or
        std.mem.eql(u8, symbol, "vkGetImageMemoryRequirements2") or
        std.mem.eql(u8, symbol, "vkGetImageMemoryRequirements2KHR")) return .get_memory_requirements2;
    if (std.mem.eql(u8, symbol, "vkGetBufferMemoryRequirements") or
        std.mem.eql(u8, symbol, "vkGetImageMemoryRequirements")) return .get_memory_requirements;
    // VK_KHR_maintenance4 was promoted in Vulkan 1.3.  A device negotiated at
    // 1.2 loads the KHR-suffixed names, so classifying only the promoted
    // spelling sends the guest's requirement queries down the unmodelled path,
    // where they return zero and the guest sizes an allocation from it.
    if (std.mem.eql(u8, symbol, "vkGetDeviceBufferMemoryRequirements") or
        std.mem.eql(u8, symbol, "vkGetDeviceBufferMemoryRequirementsKHR")) return .get_device_buffer_memory_requirements;
    if (std.mem.eql(u8, symbol, "vkGetDeviceImageMemoryRequirements") or
        std.mem.eql(u8, symbol, "vkGetDeviceImageMemoryRequirementsKHR")) return .get_device_image_memory_requirements;
    if (std.mem.eql(u8, symbol, "vkCreatePipelineCache")) return .create_pipeline_cache;
    if (std.mem.eql(u8, symbol, "vkGetPipelineCacheData")) return .get_pipeline_cache_data;
    if (std.mem.eql(u8, symbol, "vkCreateDescriptorUpdateTemplate")) return .create_descriptor_update_template;
    const create_objects = [_][]const u8{
        "vkCreateDescriptorSetLayout",
        "vkCreatePipelineLayout",
        "vkCreateShaderModule",
        "vkCreateRenderPass",
        "vkCreateSemaphore",
        "vkCreateCommandPool",
        "vkCreateDescriptorPool",
        "vkCreateSampler",
        "vkCreateBuffer",
        "vkCreateBufferView",
        "vkCreateFence",
        "vkCreateFramebuffer",
        "vkCreateImage",
        "vkCreateImageView",
        "vkCreateQueryPool",
    };
    for (create_objects) |name| if (std.mem.eql(u8, symbol, name)) return .create_device_object;
    const graphics_pipelines = [_][]const u8{
        "vkCreateGraphicsPipelines",
        "vkCreateComputePipelines",
    };
    for (graphics_pipelines) |name| if (std.mem.eql(u8, symbol, name)) return .create_graphics_pipelines;
    if (std.mem.eql(u8, symbol, "vkAllocateCommandBuffers")) return .allocate_command_buffers;
    if (std.mem.eql(u8, symbol, "vkAllocateDescriptorSets")) return .allocate_descriptor_sets;
    if (std.mem.eql(u8, symbol, "vkBeginCommandBuffer")) return .begin_command_buffer;
    if (std.mem.eql(u8, symbol, "vkEndCommandBuffer")) return .end_command_buffer;
    if (std.mem.eql(u8, symbol, "vkResetCommandBuffer")) return .reset_command_buffer;
    if (std.mem.eql(u8, symbol, "vkResetCommandPool")) return .reset_command_pool;
    if (std.mem.eql(u8, symbol, "vkWaitForFences")) return .wait_for_fences;
    if (std.mem.eql(u8, symbol, "vkResetFences")) return .reset_fences;
    if (std.mem.eql(u8, symbol, "vkGetFenceStatus")) return .get_fence_status;
    if (std.mem.eql(u8, symbol, "vkGetQueryPoolResults")) return .get_query_pool_results;
    if (std.mem.eql(u8, symbol, "vkResetQueryPool")) return .reset_query_pool;
    if (std.mem.eql(u8, symbol, "vkDeviceWaitIdle")) return .device_wait_idle;
    if (std.mem.eql(u8, symbol, "vkFlushMappedMemoryRanges")) return .flush_mapped_memory_ranges;
    if (std.mem.eql(u8, symbol, "vkInvalidateMappedMemoryRanges")) return .invalidate_mapped_memory_ranges;
    if (std.mem.eql(u8, symbol, "vkUnmapMemory")) return .unmap_memory;
    const destroy_objects = [_][]const u8{
        "vkDestroyPipelineCache",
        "vkDestroyDescriptorUpdateTemplate",
        "vkDestroyDescriptorSetLayout",
        "vkDestroyPipelineLayout",
        "vkDestroyShaderModule",
        "vkDestroyRenderPass",
        "vkDestroySemaphore",
        "vkDestroyCommandPool",
        "vkDestroyDescriptorPool",
        "vkDestroySampler",
        "vkDestroyBuffer",
        "vkDestroyBufferView",
        "vkDestroyFence",
        "vkDestroyFramebuffer",
        "vkDestroyImage",
        "vkDestroyImageView",
        "vkDestroyQueryPool",
        "vkDestroyPipeline",
        "vkFreeCommandBuffers",
        "vkFreeDescriptorSets",
        "vkFreeMemory",
    };
    for (destroy_objects) |name| if (std.mem.eql(u8, symbol, name)) return .destroy_device_object;
    // VK_EXT_debug_utils is modelled, never forwarded.  Its create-info
    // carries pfnUserCallback, a guest x86 function pointer: handing that to
    // the host loader would have the driver call into translated code on a
    // host thread.  The messenger is therefore a bridge-side no-op, and the
    // guest is told so explicitly rather than through an unmodelled-proc
    // return value that leaves its output handle untouched.
    if (std.mem.eql(u8, symbol, "vkCreateDebugUtilsMessengerEXT")) return .create_debug_messenger;
    if (std.mem.eql(u8, symbol, "vkDestroyDebugUtilsMessengerEXT")) return .destroy_debug_messenger;
    if (std.mem.eql(u8, symbol, "vkSetDebugUtilsObjectNameEXT") or
        std.mem.eql(u8, symbol, "vkSetDebugUtilsObjectTagEXT")) return .debug_utils_success;
    if (std.mem.eql(u8, symbol, "vkResetDescriptorPool")) return .reset_descriptor_pool;
    if (std.mem.eql(u8, symbol, "vkBindImageMemory")) return .bind_image_memory;
    if (std.mem.eql(u8, symbol, "vkBindBufferMemory")) return .bind_buffer_memory;
    if (std.mem.startsWith(u8, symbol, "vkCmd")) return .command;
    if (std.mem.eql(u8, symbol, "vkUpdateDescriptorSets")) return .update_descriptor_sets;
    if (std.mem.eql(u8, symbol, "vkUpdateDescriptorSetWithTemplate")) return .update_descriptor_set_with_template;
    if (std.mem.eql(u8, symbol, "vkUnmapMemory")) return .unmap_memory;
    return .@"opaque";
}

const extension_names = [_][]const u8{
    "VK_KHR_surface",
    "VK_EXT_metal_surface",
    "VK_KHR_portability_enumeration",
    "VK_KHR_get_physical_device_properties2",
};

/// The array half of every VkEnumerate*ExtensionProperties entry point.
///
/// `pPropertyCount` is an in/out parameter: null `pProperties` makes it a
/// pure count query, and otherwise it carries the guest array's capacity in
/// and the number of entries written out.  VK_INCOMPLETE is reserved for the
/// case where the guest's array was genuinely too small for the list; a
/// bridge-side limit that truncates a list the guest had room for is a bug,
/// not a truncation the guest asked for.
fn writeExtensionPropertiesArray(
    state: anytype,
    count_address: u64,
    output_address: u64,
    available: []const abi.ExtensionProperties,
) u64 {
    if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
    const total: u32 = @intCast(available.len);
    if (output_address == 0) {
        state.write32(count_address, total);
        return @as(u32, @bitCast(abi.SUCCESS));
    }
    const capacity = state.read32(count_address);
    const written: u32 = @min(capacity, total);
    if (written != 0) {
        const span = @as(u64, written) * @sizeOf(abi.ExtensionProperties);
        const bytes = state.guestMemory(output_address, span) orelse return vkErrorInitializationFailed();
        @memcpy(bytes[0..@intCast(span)], std.mem.sliceAsBytes(available[0..written]));
    }
    state.write32(count_address, written);
    return @as(u32, @bitCast(if (written < total) abi.INCOMPLETE else abi.SUCCESS));
}

/// A non-null pLayerName asks for the extensions a specific layer adds.  The
/// bridge enumerates no layers at all, so no layer name can be one the guest
/// enabled, and the specification's answer for that is a hard error rather
/// than an empty list — an empty list would claim the layer exists and simply
/// contributes nothing.
fn enumerateNoLayerExtensions(state: anytype, count_address: u64) u64 {
    if (count_address != 0 and state.guestMemory(count_address, 4) != null) state.write32(count_address, 0);
    return @as(u32, @bitCast(abi.ERROR_LAYER_NOT_PRESENT));
}

fn syntheticExtensionProperties(comptime names: []const []const u8) [names.len]abi.ExtensionProperties {
    var table: [names.len]abi.ExtensionProperties = undefined;
    for (names, 0..) |name, index| {
        table[index] = .{ .extension_name = [_]u8{0} ** abi.MAX_EXTENSION_NAME_SIZE, .spec_version = 1 };
        @memcpy(table[index].extension_name[0..name.len], name);
    }
    return table;
}

fn enumerateInstanceExtensionsSynthetic(state: anytype) u64 {
    if (state.regs.rdi != 0) return enumerateNoLayerExtensions(state, state.regs.rsi);
    const table = comptime syntheticExtensionProperties(&extension_names);
    return writeExtensionPropertiesArray(state, state.regs.rsi, state.regs.rdx, &table);
}

fn enumerateEmpty(state: anytype, count_address: u64) u64 {
    if (state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
    state.write32(count_address, 0);
    return 0;
}

fn writeApiVersion(state: anytype, output: u64) u64 {
    if (state.guestMemory(output, 4) == null) return vkErrorInitializationFailed();
    state.write32(output, 0x0040_2000); // Vulkan 1.2.0
    return 0;
}

const device_extensions = [_][]const u8{
    "VK_KHR_swapchain",
    "VK_KHR_portability_subset",
    "VK_KHR_maintenance1",
};

fn enumerateDeviceExtensions(state: anytype) u64 {
    if (state.regs.rsi != 0) return enumerateNoLayerExtensions(state, state.regs.rdx);
    const table = comptime syntheticExtensionProperties(&device_extensions);
    return writeExtensionPropertiesArray(state, state.regs.rdx, state.regs.rcx, &table);
}

fn writePhysicalDeviceFeatures(state: anytype, output: u64) void {
    const bytes = state.guestMemory(output, 220) orelse return;
    // Xenia requires independentBlend and uses many optional core features.
    // Advertising the coherent virtual profile keeps feature selection
    // deterministic; instruction semantics remain enforced by Rosette.
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += 4) std.mem.writeInt(u32, bytes[offset..][0..4], 1, .little);
}

fn writeFormatProperties(state: anytype, output: u64) void {
    const bytes = state.guestMemory(output, 12) orelse return;
    std.mem.writeInt(u32, bytes[0..4], 0x0001_FFFF, .little);
    std.mem.writeInt(u32, bytes[4..8], 0x0001_FFFF, .little);
    std.mem.writeInt(u32, bytes[8..12], 0x0001_FFFF, .little);
}

const VK_PHYSICAL_DEVICE_PROPERTIES_SIZE: u64 = 824;
const VK_PHYSICAL_DEVICE_LIMITS_OFFSET: usize = 296;
const VK_SAMPLE_COUNT_1_BIT: u32 = 0x1;
const VK_SAMPLE_COUNT_4_BIT: u32 = 0x4;
const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES: u32 = 1_000_196_000;
const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES: u32 = 1_000_197_000;
const VK_DRIVER_ID_MOLTENVK: u32 = 14;

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}

fn writeU64(bytes: []u8, offset: usize, value: u64) void {
    std.mem.writeInt(u64, bytes[offset..][0..8], value, .little);
}

fn writeI32(bytes: []u8, offset: usize, value: i32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], @bitCast(value), .little);
}

fn writeF32(bytes: []u8, offset: usize, value: f32) void {
    const raw: u32 = @bitCast(value);
    std.mem.writeInt(u32, bytes[offset..][0..4], raw, .little);
}

fn writeCStringField(bytes: []u8, offset: usize, size: usize, value: []const u8) void {
    const out = bytes[offset..][0..size];
    const copy_len = @min(out.len - 1, value.len);
    @memset(out, 0);
    @memcpy(out[0..copy_len], value[0..copy_len]);
}

fn writePhysicalDeviceLimits(bytes: []u8, base: usize) void {
    writeU32(bytes, base + 0, 4096);
    writeU32(bytes, base + 4, 4096);
    writeU32(bytes, base + 8, 256);
    writeU32(bytes, base + 12, 4096);
    writeU32(bytes, base + 16, 256);
    writeU32(bytes, base + 20, 1 << 27);
    writeU32(bytes, base + 24, 16 * 1024);
    writeU32(bytes, base + 28, 1 << 27);
    writeU32(bytes, base + 32, 256);
    writeU32(bytes, base + 36, 4096);
    writeU32(bytes, base + 40, 4000);
    writeU64(bytes, base + 48, 1);
    writeU64(bytes, base + 56, @as(u64, 1) << 32);
    writeU32(bytes, base + 64, 8);
    writeU32(bytes, base + 68, 16);
    writeU32(bytes, base + 72, 12);
    writeU32(bytes, base + 76, 4);
    writeU32(bytes, base + 80, 16);
    writeU32(bytes, base + 84, 4);
    writeU32(bytes, base + 88, 4);
    writeU32(bytes, base + 92, 128);
    writeU32(bytes, base + 96, 128);
    writeU32(bytes, base + 100, 72);
    writeU32(bytes, base + 104, 8);
    writeU32(bytes, base + 108, 24);
    writeU32(bytes, base + 112, 4);
    writeU32(bytes, base + 116, 96);
    writeU32(bytes, base + 120, 24);
    writeU32(bytes, base + 124, 8);
    writeU32(bytes, base + 128, 32);
    writeU32(bytes, base + 132, 32);
    writeU32(bytes, base + 136, 2047);
    writeU32(bytes, base + 140, 2048);
    writeU32(bytes, base + 144, 64);
    writeU32(bytes, base + 148, 64);
    writeU32(bytes, base + 152, 32);
    writeU32(bytes, base + 156, 64);
    writeU32(bytes, base + 160, 64);
    writeU32(bytes, base + 164, 120);
    writeU32(bytes, base + 168, 2048);
    writeU32(bytes, base + 172, 64);
    writeU32(bytes, base + 176, 64);
    writeU32(bytes, base + 180, 32);
    writeU32(bytes, base + 184, 64);
    writeU32(bytes, base + 188, 64);
    writeU32(bytes, base + 192, 256);
    writeU32(bytes, base + 196, 1024);
    writeU32(bytes, base + 200, 64);
    writeU32(bytes, base + 204, 8);
    writeU32(bytes, base + 208, 1);
    writeU32(bytes, base + 212, 4);
    writeU32(bytes, base + 216, 32 * 1024);
    writeU32(bytes, base + 220, 65535);
    writeU32(bytes, base + 224, 65535);
    writeU32(bytes, base + 228, 65535);
    writeU32(bytes, base + 232, 1024);
    writeU32(bytes, base + 236, 1024);
    writeU32(bytes, base + 240, 1024);
    writeU32(bytes, base + 244, 64);
    writeU32(bytes, base + 248, 8);
    writeU32(bytes, base + 252, 8);
    writeU32(bytes, base + 256, 8);
    writeU32(bytes, base + 260, 0xFFFF_FFFF);
    writeU32(bytes, base + 264, 1_048_576);
    writeF32(bytes, base + 268, 16.0);
    writeF32(bytes, base + 272, 16.0);
    writeU32(bytes, base + 276, 16);
    writeU32(bytes, base + 280, 4096);
    writeU32(bytes, base + 284, 4096);
    writeF32(bytes, base + 288, -8192.0);
    writeF32(bytes, base + 292, 8192.0);
    writeU32(bytes, base + 296, 8);
    writeU64(bytes, base + 304, 64);
    writeU64(bytes, base + 312, 256);
    writeU64(bytes, base + 320, 256);
    writeU64(bytes, base + 328, 256);
    writeI32(bytes, base + 336, -8);
    writeU32(bytes, base + 340, 7);
    writeI32(bytes, base + 344, -8);
    writeU32(bytes, base + 348, 7);
    writeF32(bytes, base + 352, -0.5);
    writeF32(bytes, base + 356, 0.5);
    writeU32(bytes, base + 360, 4);
    writeU32(bytes, base + 364, 4096);
    writeU32(bytes, base + 368, 4096);
    writeU32(bytes, base + 372, 256);
    const sample_1_4 = VK_SAMPLE_COUNT_1_BIT | VK_SAMPLE_COUNT_4_BIT;
    writeU32(bytes, base + 376, sample_1_4);
    writeU32(bytes, base + 380, sample_1_4);
    writeU32(bytes, base + 384, sample_1_4);
    writeU32(bytes, base + 388, sample_1_4);
    writeU32(bytes, base + 392, 8);
    writeU32(bytes, base + 396, sample_1_4);
    writeU32(bytes, base + 400, VK_SAMPLE_COUNT_1_BIT);
    writeU32(bytes, base + 404, sample_1_4);
    writeU32(bytes, base + 408, sample_1_4);
    writeU32(bytes, base + 412, VK_SAMPLE_COUNT_1_BIT);
    writeU32(bytes, base + 416, 1);
    writeU32(bytes, base + 420, 1);
    writeF32(bytes, base + 424, 1.0);
    writeU32(bytes, base + 428, 8);
    writeU32(bytes, base + 432, 8);
    writeU32(bytes, base + 436, 8);
    writeU32(bytes, base + 440, 2);
    writeF32(bytes, base + 444, 1.0);
    writeF32(bytes, base + 448, 64.0);
    writeF32(bytes, base + 452, 1.0);
    writeF32(bytes, base + 456, 8.0);
    writeF32(bytes, base + 460, 1.0);
    writeF32(bytes, base + 464, 1.0);
    writeU32(bytes, base + 468, 1);
    writeU32(bytes, base + 472, 1);
    writeU64(bytes, base + 480, 1);
    writeU64(bytes, base + 488, 1);
    writeU64(bytes, base + 496, 256);
}

fn writePhysicalDeviceProperties(state: anytype, output: u64) void {
    const bytes = state.guestMemory(output, VK_PHYSICAL_DEVICE_PROPERTIES_SIZE) orelse return;
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x0040_2000);
    writeU32(bytes, 4, 1);
    writeU32(bytes, 8, 0x106B); // Apple
    writeU32(bytes, 12, 1);
    writeU32(bytes, 16, 2); // discrete GPU profile
    writeCStringField(bytes, 20, 256, "Rosette Vulkan Metal Adapter");
    writePhysicalDeviceLimits(bytes, VK_PHYSICAL_DEVICE_LIMITS_OFFSET);
}

fn writeMemoryProperties(state: anytype, output: u64) void {
    const bytes = state.guestMemory(output, 520) orelse return;
    @memset(bytes, 0);
    std.mem.writeInt(u32, bytes[0..4], MODELLED_MEMORY_TYPE_COUNT, .little);
    std.mem.writeInt(u32, bytes[4..8], 0x0000_000F, .little); // device-local, visible, coherent, cached
    std.mem.writeInt(u32, bytes[8..12], 0, .little);
    std.mem.writeInt(u32, bytes[260..264], 1, .little);
    std.mem.writeInt(u64, bytes[264..272], 2 * 1024 * 1024 * 1024, .little);
    std.mem.writeInt(u32, bytes[272..276], 1, .little);
}

fn writeQueueFamilies(state: anytype) void {
    const count_address = state.regs.rsi;
    if (state.guestMemory(count_address, 4) == null) return;
    if (state.regs.rdx == 0) {
        state.write32(count_address, 1);
        return;
    }
    if (state.read32(count_address) == 0) return;
    const bytes = state.guestMemory(state.regs.rdx, 24) orelse return;
    @memset(bytes, 0);
    std.mem.writeInt(u32, bytes[0..4], 0xF, .little); // graphics, compute, transfer, sparse binding
    std.mem.writeInt(u32, bytes[4..8], 1, .little);
    std.mem.writeInt(u32, bytes[8..12], 64, .little);
    state.write32(count_address, 1);
}

fn writePhysicalDeviceFeatures2(state: anytype, output: u64) void {
    writePhysicalDeviceFeatures(state, output + 16);
}

fn writeMemoryProperties2(state: anytype, output: u64) void {
    writeMemoryProperties(state, output + 16);
}

fn writePhysicalDeviceDriverProperties(state: anytype, output: u64) void {
    const bytes = state.guestMemory(output, 536) orelse return;
    @memset(bytes[16..536], 0);
    writeU32(bytes, 16, VK_DRIVER_ID_MOLTENVK);
    writeCStringField(bytes, 20, 256, "Rosette Vulkan/MoltenVK");
    writeCStringField(bytes, 276, 256, "Rosette synthetic Vulkan 1.2 Metal profile");
    bytes[532] = 1;
    bytes[533] = 2;
    bytes[534] = 0;
    bytes[535] = 0;
}

fn writePhysicalDeviceFloatControlsProperties(state: anytype, output: u64) void {
    const bytes = state.guestMemory(output, @sizeOf(abi.PhysicalDeviceFloatControlsProperties)) orelse return;
    @memset(bytes[16..@sizeOf(abi.PhysicalDeviceFloatControlsProperties)], 0);
    writeU32(bytes, 16, 0); // VK_SHADER_FLOAT_CONTROLS_INDEPENDENCE_32_BIT_ONLY
    writeU32(bytes, 20, 0);
    writeU32(bytes, 28, 1); // shaderSignedZeroInfNanPreserveFloat32
    writeU32(bytes, 52, 1); // shaderDenormFlushToZeroFloat32
    writeU32(bytes, 64, 1); // shaderRoundingModeRTEFloat32
    writeU32(bytes, 76, 1); // shaderRoundingModeRTZFloat32
}

fn writePhysicalDevicePropertiesPNext(state: anytype, first: u64) void {
    var node = first;
    var depth: u8 = 0;
    while (node != 0 and depth < 16) : (depth += 1) {
        if (state.guestMemory(node, 16) == null) return;
        const s_type = state.read32(node);
        const next = state.read64(node + 8);
        switch (s_type) {
            VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES => writePhysicalDeviceDriverProperties(state, node),
            VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES => writePhysicalDeviceFloatControlsProperties(state, node),
            else => {},
        }
        node = next;
    }
}

fn writePhysicalDeviceProperties2(state: anytype, output: u64) void {
    const header = state.guestMemory(output, 16) orelse return;
    const next = std.mem.readInt(u64, header[8..16], .little);
    writePhysicalDeviceProperties(state, output + 16);
    writePhysicalDevicePropertiesPNext(state, next);
}

fn writeSurfaceCapabilities(state: anytype, output: u64) u64 {
    const bytes = state.guestMemory(output, 52) orelse return vkErrorInitializationFailed();
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    const native_width = if (@hasDecl(State, "nativeWindowWidth")) state.nativeWindowWidth() else 0;
    const native_height = if (@hasDecl(State, "nativeWindowHeight")) state.nativeWindowHeight() else 0;
    // UINT32_MAX means the surface size is not fixed and the application may
    // select its own extent. Once the native bridge knows the drawable size,
    // publish it exactly so Xenia doesn't clamp against zero-filled fields.
    const current_width = if (native_width != 0) native_width else std.math.maxInt(u32);
    const current_height = if (native_height != 0) native_height else std.math.maxInt(u32);

    @memset(bytes, 0);
    std.mem.writeInt(u32, bytes[0..4], 2, .little); // minImageCount
    std.mem.writeInt(u32, bytes[4..8], 3, .little); // maxImageCount
    std.mem.writeInt(u32, bytes[8..12], current_width, .little);
    std.mem.writeInt(u32, bytes[12..16], current_height, .little);
    std.mem.writeInt(u32, bytes[16..20], 1, .little); // minImageExtent.width
    std.mem.writeInt(u32, bytes[20..24], 1, .little); // minImageExtent.height
    std.mem.writeInt(u32, bytes[24..28], 16384, .little); // maxImageExtent.width
    std.mem.writeInt(u32, bytes[28..32], 16384, .little); // maxImageExtent.height
    std.mem.writeInt(u32, bytes[32..36], 1, .little); // maxImageArrayLayers
    std.mem.writeInt(u32, bytes[36..40], 1, .little); // supportedTransforms: IDENTITY
    std.mem.writeInt(u32, bytes[40..44], 1, .little); // currentTransform: IDENTITY
    std.mem.writeInt(u32, bytes[44..48], 0x0F, .little); // supportedCompositeAlpha
    std.mem.writeInt(u32, bytes[48..52], 0x13, .little); // transfer src/dst + color attachment
    return 0;
}

fn enumerateSurfaceFormats(state: anytype) u64 {
    if (state.guestMemory(state.regs.rdx, 4) == null) return vkErrorInitializationFailed();
    if (state.regs.rcx == 0) {
        state.write32(state.regs.rdx, 1);
        return 0;
    }
    const bytes = state.guestMemory(state.regs.rcx, 8) orelse return vkErrorInitializationFailed();
    std.mem.writeInt(u32, bytes[0..4], 44, .little); // VK_FORMAT_B8G8R8A8_UNORM
    std.mem.writeInt(u32, bytes[4..8], 0, .little); // SRGB nonlinear
    state.write32(state.regs.rdx, 1);
    return 0;
}

fn enumerateSurfacePresentModes(state: anytype) u64 {
    if (state.guestMemory(state.regs.rdx, 4) == null) return vkErrorInitializationFailed();
    if (state.regs.rcx != 0 and state.read32(state.regs.rdx) != 0) state.write32(state.regs.rcx, 2); // FIFO
    state.write32(state.regs.rdx, 1);
    return 0;
}

fn writeBoolResult(state: anytype, output: u64, value: bool) u64 {
    if (state.guestMemory(output, 4) == null) return vkErrorInitializationFailed();
    state.write32(output, @intFromBool(value));
    return 0;
}

/// `requested_size` of zero means the resource was never described — an
/// unrecorded handle, or a create-info the guest placed out of reach — so the
/// old page-sized answer stands as the only defensible fallback. Any described
/// resource gets its own size, rounded up to the alignment reported alongside
/// it, because a guest that trusts this number allocates exactly it.
fn writeMemoryRequirements(state: anytype, output: u64, requested_size: u64) u64 {
    const bytes = state.guestMemory(output, 24) orelse return vkErrorInitializationFailed();
    const alignment: u64 = 256;
    const size = if (requested_size == 0)
        4096
    else
        std.mem.alignForward(u64, requested_size, alignment);
    @memset(bytes, 0);
    std.mem.writeInt(u64, bytes[0..8], size, .little);
    std.mem.writeInt(u64, bytes[8..16], alignment, .little);
    std.mem.writeInt(u32, bytes[16..20], 1, .little);
    return 0;
}

fn createHandle(state: anytype, output: u64, handle: u64, owner: []const u8) u64 {
    if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
    state.write64(output, handle);
    registerOpaqueHandle(state, handle, owner);
    return 0;
}

fn enumerateHandle(
    state: anytype,
    count_address: u64,
    output: u64,
    handle: u64,
    owner: []const u8,
    register_opaque: bool,
) u64 {
    if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
    if (output == 0) {
        state.write32(count_address, 1);
        return 0;
    }
    if (state.read32(count_address) == 0 or state.guestMemory(output, 8) == null) return 5;
    state.write64(output, handle);
    if (register_opaque) registerOpaqueHandle(state, handle, owner);
    state.write32(count_address, 1);
    return 0;
}

const PhysicalDeviceGuestHandle = struct {
    value: u64,
    register_opaque: bool,
};

fn publishVulkanDispatchableHandle(state: anytype, output: u64, handle: abi.Device) bool {
    if (output == 0 or handle == null) return false;
    if (state.guestMemory(output, 8) == null) return false;
    state.write64(output, @intFromPtr(handle.?));
    return true;
}

fn physicalDeviceGuestHandle(real: ?abi.PhysicalDevice) PhysicalDeviceGuestHandle {
    if (real) |handle| {
        // Xenia's VMA instance runs inside the guest image but calls the
        // forwarded Vulkan function pointers directly. It therefore needs the
        // native dispatchable physical-device handle, not a Rosette-only
        // opaque token. Instance and device creation already expose native
        // handles; keeping the physical device synthetic creates an invalid
        // mixed-tier Vulkan object graph.
        return .{ .value = @intFromPtr(handle), .register_opaque = false };
    }
    return .{ .value = SYNTHETIC_PHYSICAL_DEVICE_HANDLE, .register_opaque = true };
}

fn registerOpaqueHandle(state: anytype, handle: u64, owner: []const u8) void {
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (comptime @hasDecl(State, "registerOpaqueApiHandle")) {
        state.registerOpaqueApiHandle(handle, owner);
    } else if (comptime @hasDecl(State, "registerOpaqueHandle")) {
        state.registerOpaqueHandle(handle, owner);
    }
}

/// The host Metal clear. Only reached when the native Vulkan presenter could
/// not be brought up: a frame from here proves the Cocoa/Metal boundary is
/// alive and nothing about the guest.
fn presentDiagnosticMetalFrame(
    state: anytype,
    serial: u64,
    requested_width: u32,
    requested_height: u32,
    stage: u32,
) bool {
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (!@hasDecl(State, "presentNativeDiagnosticFrame")) return false;
    const width = if (requested_width != 0)
        requested_width
    else if (@hasDecl(State, "nativeWindowWidth"))
        state.nativeWindowWidth()
    else
        1280;
    const height = if (requested_height != 0)
        requested_height
    else if (@hasDecl(State, "nativeWindowHeight"))
        state.nativeWindowHeight()
    else
        720;
    return state.presentNativeDiagnosticFrame(
        serial,
        @max(width, 1),
        @max(height, 1),
        stage,
    );
}

/// Read the guest's VkApplicationInfo scalars, or null when the structure is
/// absent or not readable.
///
/// VkApplicationInfo has pointer fields at 16 and 32, so applicationVersion
/// sits at 24 with four bytes of padding after it; engineVersion and
/// apiVersion are then adjacent at 40 and 44, and the structure closes at 48
/// with no tail padding.  Reading apiVersion at 28 folds in half of the
/// engine-name pointer, and reading it at 48 lands past the end of the
/// structure altogether.  Both mistakes are silent: the guest simply appears
/// to have asked for Vulkan 1.0, and MoltenVK then reports a 1.0 physical
/// device, which strips the guest of every core 1.1/1.2 entry point it was
/// about to negotiate for.  The offsets come from the ABI declaration so the
/// layout is asserted once at compile time rather than restated here.
fn readGuestApplicationInfo(state: anytype, app_info_addr: u64) ?abi.ApplicationInfo {
    if (app_info_addr == 0) return null;
    if (state.guestMemoryConst(app_info_addr, @sizeOf(abi.ApplicationInfo)) == null) return null;
    var app_info: abi.ApplicationInfo = .{};
    app_info.application_version = state.read32(app_info_addr + @offsetOf(abi.ApplicationInfo, "application_version"));
    app_info.engine_version = state.read32(app_info_addr + @offsetOf(abi.ApplicationInfo, "engine_version"));
    app_info.api_version = state.read32(app_info_addr + @offsetOf(abi.ApplicationInfo, "api_version"));
    // The name pointers and the pNext chain are guest addresses; the host
    // loader must never see them.
    app_info.application_name = null;
    app_info.engine_name = null;
    app_info.p_next = null;
    // The synthetic loader advertises Vulkan 1.2.  Do not ask a MoltenVK
    // loader for a newer core version simply because the guest's x86 headers
    // were built against one.
    if (app_info.api_version != 0) app_info.api_version = @min(app_info.api_version, abi.makeApiVersion(1, 2, 0));
    return app_info;
}

fn vkErrorInitializationFailed() u64 {
    return @as(u32, @bitCast(@as(i32, -3)));
}

fn vkErrorInitializationFailedSigned() i32 {
    return -3;
}

fn vkErrorOutOfHostMemory() u64 {
    return @as(u32, @bitCast(@as(i32, -1)));
}

test "guest symbol name hash separates the command chain's literals" {
    // The stored-hash fast-fail in `forwardVulkanCommand` relies on distinct
    // command literals hashing apart, so the hot vkCmd* calls pay u64 compares
    // instead of string walks. Multi-name cases must still distinguish their
    // spellings (the inner eql decides, but only after the hash agrees).
    try std.testing.expectEqual(vulkanNameHash("vkCmdDraw"), vulkanNameHash("vkCmdDraw"));
    try std.testing.expect(vulkanNameHash("vkCmdDraw") != vulkanNameHash("vkCmdDrawIndexed"));
    try std.testing.expect(vulkanNameHash("vkCmdDrawIndexed") != vulkanNameHash("vkCmdDrawIndexedIndirect"));
    try std.testing.expect(vulkanNameHash("vkCmdBindPipeline") != vulkanNameHash("vkCmdBindDescriptorSets"));
    try std.testing.expect(vulkanNameHash("vkCmdBeginRenderPass2") != vulkanNameHash("vkCmdBeginRenderPass2KHR"));
    try std.testing.expect(vulkanNameHash("vkCmdPipelineBarrier2") != vulkanNameHash("vkCmdPipelineBarrier2KHR"));
}

test "Vulkan guest symbol classification covers surface bootstrap" {
    try std.testing.expectEqual(GuestSymbolKind.enumerate_instance_extensions, guestSymbolKind("vkEnumerateInstanceExtensionProperties"));
    try std.testing.expectEqual(GuestSymbolKind.create_metal_surface, guestSymbolKind("vkCreateMetalSurfaceEXT"));
    try std.testing.expectEqual(GuestSymbolKind.create_device, guestSymbolKind("vkCreateDevice"));
    try std.testing.expectEqual(GuestSymbolKind.get_device_queue2, guestSymbolKind("vkGetDeviceQueue2"));
    try std.testing.expectEqual(GuestSymbolKind.create_swapchain, guestSymbolKind("vkCreateSwapchainKHR"));
    try std.testing.expectEqual(GuestSymbolKind.get_swapchain_images, guestSymbolKind("vkGetSwapchainImagesKHR"));
    try std.testing.expectEqual(GuestSymbolKind.acquire_next_image, guestSymbolKind("vkAcquireNextImageKHR"));
    try std.testing.expectEqual(GuestSymbolKind.queue_present, guestSymbolKind("vkQueuePresentKHR"));
    try std.testing.expectEqual(GuestSymbolKind.get_physical_device_features2, guestSymbolKind("vkGetPhysicalDeviceFeatures2"));
    try std.testing.expectEqual(GuestSymbolKind.get_physical_device_features2, guestSymbolKind("vkGetPhysicalDeviceFeatures2KHR"));
    try std.testing.expectEqual(GuestSymbolKind.get_physical_device_properties2, guestSymbolKind("vkGetPhysicalDeviceProperties2"));
    try std.testing.expectEqual(GuestSymbolKind.get_physical_device_memory_properties2, guestSymbolKind("vkGetPhysicalDeviceMemoryProperties2"));
    try std.testing.expectEqual(GuestSymbolKind.create_pipeline_cache, guestSymbolKind("vkCreatePipelineCache"));
    try std.testing.expectEqual(GuestSymbolKind.create_descriptor_update_template, guestSymbolKind("vkCreateDescriptorUpdateTemplate"));
    try std.testing.expectEqual(GuestSymbolKind.create_device_object, guestSymbolKind("vkCreateDescriptorSetLayout"));
    try std.testing.expectEqual(GuestSymbolKind.create_device_object, guestSymbolKind("vkCreateImageView"));
    try std.testing.expectEqual(GuestSymbolKind.allocate_memory, guestSymbolKind("vkAllocateMemory"));
    try std.testing.expectEqual(GuestSymbolKind.map_memory, guestSymbolKind("vkMapMemory"));
    try std.testing.expectEqual(GuestSymbolKind.get_memory_requirements, guestSymbolKind("vkGetImageMemoryRequirements"));
    try std.testing.expectEqual(GuestSymbolKind.get_memory_requirements2, guestSymbolKind("vkGetImageMemoryRequirements2"));
    try std.testing.expectEqual(GuestSymbolKind.get_memory_requirements2, guestSymbolKind("vkGetBufferMemoryRequirements2KHR"));
    try std.testing.expectEqual(GuestSymbolKind.bind_image_memory2, guestSymbolKind("vkBindImageMemory2"));
    try std.testing.expectEqual(GuestSymbolKind.bind_buffer_memory2, guestSymbolKind("vkBindBufferMemory2KHR"));
    try std.testing.expectEqual(GuestSymbolKind.command, guestSymbolKind("vkCmdDrawIndexed"));
    try std.testing.expectEqual(GuestSymbolKind.update_descriptor_sets, guestSymbolKind("vkUpdateDescriptorSets"));
    try std.testing.expectEqual(GuestSymbolKind.update_descriptor_set_with_template, guestSymbolKind("vkUpdateDescriptorSetWithTemplate"));
    try std.testing.expectEqual(GuestSymbolKind.wait_for_fences, guestSymbolKind("vkWaitForFences"));
    try std.testing.expectEqual(GuestSymbolKind.create_graphics_pipelines, guestSymbolKind("vkCreateGraphicsPipelines"));
    try std.testing.expectEqual(GuestSymbolKind.create_graphics_pipelines, guestSymbolKind("vkCreateComputePipelines"));
    try std.testing.expectEqual(GuestSymbolKind.allocate_command_buffers, guestSymbolKind("vkAllocateCommandBuffers"));
    try std.testing.expectEqual(GuestSymbolKind.destroy_device_object, guestSymbolKind("vkDestroyShaderModule"));
    try std.testing.expectEqual(GuestSymbolKind.create_debug_messenger, guestSymbolKind("vkCreateDebugUtilsMessengerEXT"));
    try std.testing.expectEqual(GuestSymbolKind.destroy_debug_messenger, guestSymbolKind("vkDestroyDebugUtilsMessengerEXT"));
    try std.testing.expectEqual(GuestSymbolKind.debug_utils_success, guestSymbolKind("vkSetDebugUtilsObjectNameEXT"));
    try std.testing.expectEqual(GuestSymbolKind.debug_utils_success, guestSymbolKind("vkSetDebugUtilsObjectTagEXT"));
}

test "Vulkan physical device properties model follows x64 C ABI alignment" {
    try std.testing.expectEqual(@as(usize, 296), VK_PHYSICAL_DEVICE_LIMITS_OFFSET);
    try std.testing.expectEqual(@as(u64, 824), VK_PHYSICAL_DEVICE_PROPERTIES_SIZE);
}

test "Vulkan feature pNext sizes include every advertised VkBool32" {
    try std.testing.expectEqual(@as(u16, 204), featureChainSize(0));
    try std.testing.expectEqual(@as(u16, 76), featureChainSize(1));
    try std.testing.expectEqual(@as(u16, 76), featureChainSize(2));
    try std.testing.expectEqual(@as(u16, 28), featureChainSize(3));
    try std.testing.expectEqual(@as(u16, 20), featureChainSize(4));
    try std.testing.expectEqual(@as(u16, 20), featureChainSize(5));
    try std.testing.expectEqual(@as(u16, 20), featureChainSize(6));
    try std.testing.expectEqual(@as(usize, 47), featureChainBoolCount(0));
    try std.testing.expectEqual(@as(usize, 15), featureChainBoolCount(1));
    try std.testing.expectEqual(@as(usize, 15), featureChainBoolCount(2));
    try std.testing.expectEqual(@as(usize, 3), featureChainBoolCount(3));
    try std.testing.expectEqual(@as(usize, 1), featureChainBoolCount(4));
    try std.testing.expectEqual(@as(usize, 1), featureChainBoolCount(5));
    try std.testing.expectEqual(@as(usize, 1), featureChainBoolCount(6));
}

test "native Vulkan device handles are published to guest output memory" {
    var state = TestState{};
    const device: abi.Device = @ptrFromInt(0x1234);
    try std.testing.expect(publishVulkanDispatchableHandle(&state, 8, device));
    try std.testing.expectEqual(@as(u64, 0x1234), state.read64(8));
    try std.testing.expect(!publishVulkanDispatchableHandle(&state, 0, device));
    try std.testing.expect(!publishVulkanDispatchableHandle(&state, 8, null));
}

test "Vulkan physical device enumeration exposes native handles when available" {
    const native = physicalDeviceGuestHandle(@as(abi.PhysicalDevice, @ptrFromInt(0x1234)));
    try std.testing.expectEqual(@as(u64, 0x1234), native.value);
    try std.testing.expect(!native.register_opaque);

    const synthetic = physicalDeviceGuestHandle(null);
    try std.testing.expectEqual(SYNTHETIC_PHYSICAL_DEVICE_HANDLE, synthetic.value);
    try std.testing.expect(synthetic.register_opaque);
}

test "Vulkan swapchain teardown releases its synthetic image ownership" {
    var forwarder: Forwarder = .{};
    const synthetic_swapchain = 0x1000;
    const synthetic_image = 0x2000;
    const real_swapchain = 0x3000;
    const real_image = 0x4000;
    _ = forwarder.real_vulkan.allocateSwapchainRecord(synthetic_swapchain, real_swapchain) orelse unreachable;
    const record = forwarder.real_vulkan.mutableSwapchainRecord(synthetic_swapchain) orelse unreachable;
    record.image_handles[0] = synthetic_image;
    record.image_count = 1;
    HandleMap.allocOrFind(&forwarder.real_vulkan.swapchain_map, synthetic_swapchain, real_swapchain);
    HandleMap.allocOrFind(&forwarder.real_vulkan.image_map, synthetic_image, real_image);
    forwarder.destroyRealSwapchain(synthetic_swapchain);
    try std.testing.expect(forwarder.real_vulkan.realSwapchain(synthetic_swapchain) == null);
    try std.testing.expect(forwarder.real_vulkan.realImage(synthetic_image) == null);
    try std.testing.expect(forwarder.real_vulkan.mutableSwapchainRecord(synthetic_swapchain) == null);
}

test "Vulkan device provenance rejects a lost native device" {
    var forwarder: Forwarder = .{};
    forwarder.real_vulkan.device = @ptrFromInt(0x1234);
    forwarder.real_vulkan.guest_device_handle = 0x5678;
    forwarder.vulkan_logical_devices_created = 1;
    try std.testing.expect(forwarder.guestDeviceMatches(0x5678));
    try std.testing.expect(forwarder.guestDeviceMatches(0x1234));
    forwarder.real_vulkan.device_lost = true;
    try std.testing.expect(!forwarder.guestDeviceMatches(0x5678));
    try std.testing.expect(forwarder.realDeviceLostResult() != null);
}

fn normalizeMachOSymbol(symbol: []const u8) []const u8 {
    if (symbol.len != 0 and symbol[0] == '_') return symbol[1..];
    return symbol;
}

fn isVulkanLoaderPath(path: []const u8) bool {
    return std.mem.indexOf(u8, path, "libvulkan") != null;
}

fn specFor(symbol: []const u8) ?Spec {
    for (specs) |spec| {
        if (std.mem.eql(u8, spec.symbol, symbol)) return spec;
    }
    return null;
}

fn libraryMatches(class: LibraryClass, dylib: []const u8) bool {
    return switch (class) {
        .libsystem => std.mem.indexOf(u8, dylib, "libSystem") != null,
        .libcxx => std.mem.indexOf(u8, dylib, "libc++.1.dylib") != null,
    };
}

fn nulTerminate(buffer: []u8, value: []const u8) ?[*:0]const u8 {
    if (value.len >= buffer.len) return null;
    @memcpy(buffer[0..value.len], value);
    buffer[value.len] = 0;
    return @ptrCast(buffer.ptr);
}

const TestState = struct {
    mem: [16 * 1024]u8 = [_]u8{0} ** (16 * 1024),
    regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0, r8: u64 = 0, r9: u64 = 0, rsp: u64 = 0, rax: u64 = 0 } = .{},
    executed_steps: u64 = 10,
    active_guest_thread: u64 = 0x7FFF_2020,
    active_idle_source: u64 = 1,
    monotonic_nanoseconds: u64 = 0,
    last_opaque_handle: u64 = 0,
    last_opaque_owner: []const u8 = "",
    last_synthetic_thunk: u64 = 0,
    last_synthetic_thunk_size: u64 = 0,
    last_synthetic_thunk_owner: []const u8 = "",
    heap_next: u64 = 1024,

    pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }

    fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }

    fn guestCString(self: *@This(), address: u64, maximum: usize) ?[]const u8 {
        if (address >= self.mem.len) return null;
        const start: usize = @intCast(address);
        const available = self.mem[start..@min(self.mem.len, start + maximum)];
        const length = std.mem.indexOfScalar(u8, available, 0) orelse return null;
        return available[0..length];
    }

    fn read32(self: *@This(), address: u64) u32 {
        return std.mem.readInt(u32, self.mem[@intCast(address)..][0..4], .little);
    }

    fn read64(self: *@This(), address: u64) u64 {
        return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
    }

    fn write32(self: *@This(), address: u64, value: u32) void {
        std.mem.writeInt(u32, self.mem[@intCast(address)..][0..4], value, .little);
    }

    fn write64(self: *@This(), address: u64, value: u64) void {
        std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
    }

    pub fn guestAlloc(self: *@This(), requested_size: u64, alignment: u64) ?u64 {
        if (alignment == 0 or alignment & (alignment - 1) != 0) return null;
        const start = std.mem.alignForward(u64, self.heap_next, alignment);
        const end = std.math.add(u64, start, @max(requested_size, 1)) catch return null;
        if (end > self.mem.len) return null;
        @memset(self.mem[@intCast(start)..@intCast(end)], 0);
        self.heap_next = end;
        return start;
    }

    fn validateNativeMetalLayerToken(_: *@This(), token: u64) bool {
        return token == 0xCAFE_BABE;
    }

    pub fn registerOpaqueApiHandle(self: *@This(), handle: u64, owner: []const u8) void {
        self.last_opaque_handle = handle;
        self.last_opaque_owner = owner;
    }

    pub fn registerSyntheticThunk(self: *@This(), address: u64, size: u64, owner: []const u8) void {
        self.last_synthetic_thunk = address;
        self.last_synthetic_thunk_size = size;
        self.last_synthetic_thunk_owner = owner;
    }

    pub fn nativeWindowWidth(_: *@This()) u32 {
        return 1280;
    }

    pub fn nativeWindowHeight(_: *@This()) u32 {
        return 720;
    }
};

test "Vulkan surface capabilities preserve native drawable extent and ABI layout" {
    var state = TestState{};
    try std.testing.expectEqual(@as(u64, 0), writeSurfaceCapabilities(&state, 16));
    try std.testing.expectEqual(@as(u32, 2), state.read32(16));
    try std.testing.expectEqual(@as(u32, 3), state.read32(20));
    try std.testing.expectEqual(@as(u32, 1280), state.read32(24));
    try std.testing.expectEqual(@as(u32, 720), state.read32(28));
    try std.testing.expectEqual(@as(u32, 1), state.read32(32));
    try std.testing.expectEqual(@as(u32, 1), state.read32(36));
    try std.testing.expectEqual(@as(u32, 16384), state.read32(40));
    try std.testing.expectEqual(@as(u32, 16384), state.read32(44));
    try std.testing.expectEqual(@as(u32, 1), state.read32(48));
    try std.testing.expectEqual(@as(u32, 1), state.read32(52));
    try std.testing.expectEqual(@as(u32, 1), state.read32(56));
    try std.testing.expectEqual(@as(u32, 0x0F), state.read32(60));
    try std.testing.expectEqual(@as(u32, 0x13), state.read32(64));
}

test "modeled Vulkan objects register opaque pointer provenance" {
    var forwarder = Forwarder{};
    var state = TestState{};
    try std.testing.expectEqual(@as(u64, 0), forwarder.createVulkanObject(&state, 0, 8, "vkCreateBuffer"));
    try std.testing.expectEqual(state.read64(8), state.last_opaque_handle);
    try std.testing.expectEqualStrings("vkCreateBuffer", state.last_opaque_owner);
}

test "Vulkan 1.1 image requirements and binding use the Rosette resource record" {
    var forwarder = Forwarder{};
    var state = TestState{};
    const create_info: u64 = 128;
    const handle_output: u64 = 256;
    state.write32(create_info + VK_IMAGE_CREATE_INFO_FORMAT_OFFSET, 37);
    state.write32(create_info + VK_IMAGE_CREATE_INFO_EXTENT_OFFSET, 1280);
    state.write32(create_info + VK_IMAGE_CREATE_INFO_EXTENT_OFFSET + 4, 720);
    state.write32(create_info + VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET, 1);
    state.write32(create_info + VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET, 1);
    try std.testing.expectEqual(
        @as(u64, 0),
        forwarder.createVulkanObject(&state, create_info, handle_output, "vkCreateImage"),
    );
    const image = state.read64(handle_output);

    const requirements_info: u64 = 320;
    const requirements_output: u64 = 384;
    state.write32(requirements_output, 1000146003); // VkStructureType, caller-owned.
    state.write64(requirements_output + 8, 0xCAFE_BABE); // pNext, caller-owned.
    state.write64(requirements_info + 16, image);
    try std.testing.expectEqual(
        @as(u64, 0),
        forwarder.writeResourceMemoryRequirements2(&state, requirements_info, requirements_output),
    );
    try std.testing.expectEqual(@as(u32, 1000146003), state.read32(requirements_output));
    try std.testing.expectEqual(@as(u64, 0xCAFE_BABE), state.read64(requirements_output + 8));
    try std.testing.expectEqual(@as(u64, 1280 * 720 * 4), state.read64(requirements_output + 16));
    try std.testing.expectEqual(@as(u64, 256), state.read64(requirements_output + 24));
    try std.testing.expectEqual(@as(u32, 1), state.read32(requirements_output + 32));

    const bind_info: u64 = 448;
    state.write64(bind_info + 16, image);
    state.write64(bind_info + 24, 0xFFFF_F500_1234_0001);
    state.write64(bind_info + 32, 512);
    try std.testing.expectEqual(
        @as(u64, 0),
        forwarder.bindResourcesMemory2(&state, 1, bind_info, .image),
    );
    const record = forwarder.findResource(image).?;
    try std.testing.expectEqual(@as(u64, 0xFFFF_F500_1234_0001), record.memory);
    try std.testing.expectEqual(@as(u64, 512), record.memory_offset);
}

test "modeled Vulkan memory uses allocationSize and reuses one mapping" {
    var forwarder = Forwarder{};
    var state = TestState{};
    const allocate_info: u64 = 16;
    const allocate_output: u64 = 64;
    // VkMemoryAllocateInfo is {sType, padding, pNext, allocationSize,
    // memoryTypeIndex}: allocationSize lives at +16, and a model that reads
    // +8 gets pNext instead. Leave pNext null here so the size is the only
    // thing under test.
    state.write64(allocate_info + 8, 0);
    state.write64(allocate_info + 16, 4096);

    try std.testing.expectEqual(
        @as(u64, 0),
        forwarder.allocateVulkanMemory(&state, allocate_info, allocate_output),
    );
    const memory_handle = state.read64(allocate_output);
    try std.testing.expect(memory_handle != 0);
    try std.testing.expectEqual(
        @as(u64, 4096),
        forwarder.findVulkanMemoryRecord(memory_handle).?.requested_size,
    );

    const first_output: u64 = 72;
    try std.testing.expectEqual(
        @as(u64, 0),
        forwarder.mapVulkanMemory(
            &state,
            memory_handle,
            0,
            std.math.maxInt(u64),
            first_output,
        ),
    );
    const first_mapping = state.read64(first_output);
    const heap_after_first_map = state.heap_next;
    try std.testing.expect(first_mapping != 0);

    const second_output: u64 = 80;
    try std.testing.expectEqual(
        @as(u64, 0),
        forwarder.mapVulkanMemory(&state, memory_handle, 256, 512, second_output),
    );
    try std.testing.expectEqual(first_mapping + 256, state.read64(second_output));
    try std.testing.expectEqual(heap_after_first_map, state.heap_next);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_memory_map_reuses);
}

test "modeled Vulkan memory refuses an allocate chain it cannot translate" {
    var forwarder = Forwarder{};
    var state = TestState{};
    const allocate_info: u64 = 16;
    const allocate_output: u64 = 64;
    const chain: u64 = 512;
    state.write64(allocate_info + 16, 4096);
    state.write64(allocate_info + 8, chain);

    // An unrecognised pNext node carries guest pointers and guest handles the
    // bridge has no translation for. Refusing is the only honest answer;
    // forwarding it would have the driver dereference a guest address.
    state.write32(chain, 0xDEAD);
    try std.testing.expectEqual(
        @as(u64, @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT))),
        forwarder.allocateVulkanMemory(&state, allocate_info, allocate_output),
    );

    // A dedicated-allocation node naming a resource the bridge never issued
    // is equally untranslatable.
    state.write32(chain, abi.STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO);
    state.write64(chain + 8, 0);
    state.write64(chain + 16, 0xFFFF_F500_0000_0001);
    state.write64(chain + 24, 0);
    try std.testing.expectEqual(
        vkErrorInitializationFailed(),
        forwarder.allocateVulkanMemory(&state, allocate_info, allocate_output),
    );
}

test "mapped guest shadow is uploaded before native submission" {
    var forwarder = Forwarder{};
    var state = TestState{};
    var host_bytes = [_]u8{ 0, 0, 0, 0 };
    const expected = [_]u8{ 0x11, 0x22, 0x33, 0x44 };
    @memcpy(state.mem[128..132], &expected);
    forwarder.vulkan_memory_records[0] = .{
        .handle = 0x100,
        .requested_size = expected.len,
        .mapped_base = 128,
        .mapped_size = expected.len,
        .mapped_offset = 0,
        .host_mapped_ptr = @ptrCast(&host_bytes),
        .host_mapped_size = expected.len,
    };

    try std.testing.expect(forwarder.uploadMappedMemoryBeforeSubmit(&state));
    try std.testing.expectEqualSlices(u8, &expected, &host_bytes);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_shadow_uploads);
    try std.testing.expectEqual(@as(u64, 0), forwarder.vulkan_shadow_upload_failures);
}

test "Vulkan presenter lifecycle requires UI surface before swapchain" {
    var forwarder = Forwarder{};
    var state = TestState{};

    state.write32(8, VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT);
    state.write64(8 + 24, 0xCAFE_BABE);
    try std.testing.expectEqual(@as(u64, 0), forwarder.createMetalSurface(&state, 0, 0x1111, 8, 48));
    try std.testing.expectEqual(VK_SYNTHETIC_SURFACE, state.read64(48));
    try std.testing.expectEqual(VulkanPresenterStage.metal_surface_created, forwarder.vulkan_presenter_stage);

    try std.testing.expectEqual(@as(u64, 0), forwarder.createLogicalDevice(&state, 56));
    state.write32(80, VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR);
    state.write64(80 + 24, VK_SYNTHETIC_SURFACE);
    try std.testing.expectEqual(@as(u64, 0), forwarder.createSwapchain(&state, VK_SYNTHETIC_DEVICE, 80, 200));
    try std.testing.expect(state.read64(200) != 0);
    try std.testing.expectEqual(VulkanPresenterStage.synthetic_swapchain_ready, forwarder.vulkan_presenter_stage);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_presenter_bind_attempts);
    try std.testing.expectEqual(@as(u64, 0), forwarder.vulkan_presenter_bind_failures);
    try std.testing.expectEqual(@as(u64, 0), forwarder.vulkan_presenter_off_ui_calls);
}

test "Vulkan presenter rejects a Metal layer not owned by the native window bridge" {
    var forwarder = Forwarder{};
    var state = TestState{};

    state.write32(8, VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT);
    state.write64(8 + 24, 0xBAD0);
    try std.testing.expectEqual(vkErrorInitializationFailed(), forwarder.createMetalSurface(&state, 0, 0x1111, 8, 48));
    try std.testing.expectEqual(@as(u64, 0), state.read64(48));
    try std.testing.expectEqual(VulkanPresenterStage.failed, forwarder.vulkan_presenter_stage);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_presenter_bind_failures);
}

test "Vulkan presenter lifecycle reports a swapchain surface mismatch" {
    var forwarder = Forwarder{
        .vulkan_logical_devices_created = 1,
        .vulkan_metal_surfaces_created = 1,
    };
    var state = TestState{};
    state.write32(80, VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR);
    state.write64(80 + 24, 0xBAD0);
    try std.testing.expectEqual(vkErrorInitializationFailed(), forwarder.createSwapchain(&state, VK_SYNTHETIC_DEVICE, 80, 200));
    try std.testing.expectEqual(VulkanPresenterStage.failed, forwarder.vulkan_presenter_stage);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_presenter_bind_failures);
    try std.testing.expectEqual(@as(u64, 0), state.read64(200));
}

test "forwarding registry only admits typed libSystem functions" {
    try std.testing.expectEqual(Signature.no_args_i32, specFor("getpid").?.signature);
    try std.testing.expectEqual(Signature.darwin_vm_page_size, specFor("getpagesize").?.signature);
    try std.testing.expect(specFor("objc_msgSend") == null);
    try std.testing.expect(specFor("_ZNSt3__16localeD1Ev") == null);
    try std.testing.expectEqual(LibraryClass.libcxx, specFor("_ZNSt3__18ios_base6xallocEv").?.library);
    try std.testing.expect(libraryMatches(.libsystem, "/usr/lib/libSystem.B.dylib"));
    try std.testing.expect(!libraryMatches(.libsystem, "/usr/lib/libc++.1.dylib"));
    try std.testing.expect(libraryMatches(.libcxx, "/usr/lib/libc++.1.dylib"));
    try std.testing.expectEqual(Signature.socket_three_args, specFor(normalizeMachOSymbol("_socket")).?.signature);
    try std.testing.expectEqual(Signature.setsockopt_five_args, specFor(normalizeMachOSymbol("_setsockopt")).?.signature);
    try std.testing.expectEqual(Signature.snprintf_three_args, specFor(normalizeMachOSymbol("_snprintf")).?.signature);
    try std.testing.expectEqual(Signature.connect_three_args, specFor(normalizeMachOSymbol("_connect")).?.signature);
    try std.testing.expectEqual(Signature.send_four_args, specFor(normalizeMachOSymbol("_send")).?.signature);
    try std.testing.expectEqual(Signature.locale_info_pointer, specFor(normalizeMachOSymbol("_nl_langinfo")).?.signature);
}

test "nl_langinfo materializes CODESET in guest-owned memory" {
    var forwarder = Forwarder{};
    var state = TestState{};
    state.regs.rdi = 0; // Darwin CODESET.

    const outcome = forwarder.forward(
        &state,
        "/usr/lib/libSystem.B.dylib",
        "_nl_langinfo",
    ) orelse return error.SymbolUnavailable;
    const address = outcome.handled;
    const value = state.guestMemoryConst(address, 6) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("UTF-8\x00", value);
}

test "getpagesize observes the Darwin VM geometry required by host mmap" {
    var forwarder = Forwarder{};
    var state = TestState{};
    const result = forwarder.forward(&state, "/usr/lib/libSystem.B.dylib", "_getpagesize") orelse return error.SymbolUnavailable;
    try std.testing.expectEqual(@as(u64, guest_memory_geometry.host_vm_page_size), result.handled);
    try std.testing.expectEqual(@as(u64, 1), forwarder.page_size_queries);
}

test "guest sleep records a timed scheduler request without advancing the host clock" {
    const sleep_symbol = "__ZNSt3__111this_thread9sleep_forERKNS_6chrono8durationIxNS_5ratioILl1ELl1000000000EEEEE";
    const requested_ns: u64 = 500_000_000;
    var forwarder = Forwarder{};
    var state = TestState{};
    state.regs.rdi = 8;
    state.write64(8, requested_ns);

    const outcome = forwarder.forward(&state, "/usr/lib/libc++.1.dylib", sleep_symbol) orelse return error.SymbolUnavailable;
    try std.testing.expect(outcome == .handled_void);
    try std.testing.expectEqual(@as(u64, 1), forwarder.virtual_sleep_calls);
    try std.testing.expectEqual(requested_ns, forwarder.virtual_sleep_nanoseconds);
    try std.testing.expectEqual(requested_ns, forwarder.longest_virtual_sleep_nanoseconds);
    try std.testing.expectEqual(@as(u64, 0), state.monotonic_nanoseconds);
    try std.testing.expectEqual(guest_sleep.Kind.timed, forwarder.lastVirtualSleepDecision().kind);
}

test "guest sleep maps libcxx maximum duration sentinel to an indefinite park" {
    const sleep_symbol = "__ZNSt3__111this_thread9sleep_forERKNS_6chrono8durationIxNS_5ratioILl1ELl1000000000EEEEE";
    var forwarder = Forwarder{};
    var state = TestState{};
    state.regs.rdi = 8;
    state.write64(8, @bitCast(@as(i64, std.math.maxInt(i64))));

    const outcome = forwarder.forward(&state, "/usr/lib/libc++.1.dylib", sleep_symbol) orelse return error.SymbolUnavailable;
    try std.testing.expect(outcome == .handled_void);
    try std.testing.expectEqual(@as(u64, 1), forwarder.virtual_sleep_repairs);
    try std.testing.expectEqual(@as(u64, 0), forwarder.virtual_sleep_nanoseconds);
    try std.testing.expectEqual(@as(u64, 0), state.monotonic_nanoseconds);
    try std.testing.expectEqual(guest_sleep.Kind.indefinite, forwarder.lastVirtualSleepDecision().kind);
}

test "forwarder invokes an allowlisted host symbol" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    var state = TestState{};
    const outcome = forwarder.forward(&state, "/usr/lib/libSystem.B.dylib", "_getpid") orelse return error.SymbolUnavailable;
    try std.testing.expect(outcome.handled != 0);
    @memcpy(state.mem[8..12], "abc\x00");
    state.regs.rdi = 8;
    state.regs.rsi = 4;
    const length = forwarder.forward(&state, "/usr/lib/libSystem.B.dylib", "_strnlen") orelse return error.SymbolUnavailable;
    try std.testing.expectEqual(@as(u64, 3), length.handled);
    try std.testing.expectEqual(@as(u64, 2), forwarder.forwarded);
}

test "forwarder copies guest memory for memcpy" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    var state = TestState{};
    @memcpy(state.mem[8..12], "----");
    @memcpy(state.mem[16..20], "copy");
    state.regs.rdi = 8;
    state.regs.rsi = 16;
    state.regs.rdx = 4;

    const outcome = forwarder.forward(&state, "/usr/lib/libSystem.B.dylib", "_memcpy") orelse return error.SymbolUnavailable;
    try std.testing.expectEqual(@as(u64, 8), outcome.handled);
    try std.testing.expectEqualStrings("copy", state.mem[8..12]);
    try std.testing.expectEqual(@as(u64, 1), forwarder.forwarded);
}

test "guest dynamic-library handles are opaque and close exactly once" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    const token = forwarder.openGuest("/usr/lib/libSystem.B.dylib", RTLD_LAZY | RTLD_LOCAL);
    try std.testing.expect(token >= GUEST_LIBRARY_HANDLE_BASE);
    try std.testing.expectEqual(@as(u64, 1), forwarder.guest_open_count);
    const symbol = forwarder.lookupGuest(token, "getpid");
    try std.testing.expect(symbol >= GUEST_SYMBOL_THUNK_BASE);
    try std.testing.expectEqual(@as(u64, 1), forwarder.guest_lookup_count);
    try std.testing.expectEqual(@as(c_int, 0), forwarder.closeGuest(token));
    try std.testing.expectEqual(@as(u64, 1), forwarder.guest_close_count);
    try std.testing.expectEqual(@as(c_int, -1), forwarder.closeGuest(token));
    try std.testing.expectEqual(@as(u64, 0), forwarder.lookupGuest(token, "getpid"));
}

test "Vulkan guest library remains virtual until native surface binding" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    const token = forwarder.openGuest("/tmp/libvulkan.1.dylib", RTLD_LAZY | RTLD_LOCAL);
    try std.testing.expect(token >= GUEST_LIBRARY_HANDLE_BASE);
    const entry = forwarder.guestLibraryEntry(token) orelse return error.TestUnexpectedResult;
    try std.testing.expect(entry.virtual_vulkan);
    try std.testing.expect(entry.handle == null);
    const proc = forwarder.lookupGuest(token, "vkGetInstanceProcAddr");
    try std.testing.expect(proc >= GUEST_SYMBOL_THUNK_BASE);
    try std.testing.expectEqual(@as(c_int, 0), forwarder.closeGuest(token));
}

/// A guest memory window wide enough for a full driver extension list. The
/// shared TestState is deliberately small; the point of this one is that the
/// list under test is larger than any window the bridge used to have.
const WideGuestMemory = struct {
    mem: []u8,
    regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0 } = .{},

    fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }

    fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
        return self.guestMemory(address, length);
    }

    fn read32(self: *@This(), address: u64) u32 {
        return std.mem.readInt(u32, self.mem[@intCast(address)..][0..4], .little);
    }

    fn write32(self: *@This(), address: u64, value: u32) void {
        std.mem.writeInt(u32, self.mem[@intCast(address)..][0..4], value, .little);
    }
};

fn testExtensionProperty(name: []const u8, spec_version: u32) abi.ExtensionProperties {
    var property: abi.ExtensionProperties = .{
        .extension_name = [_]u8{0} ** abi.MAX_EXTENSION_NAME_SIZE,
        .spec_version = spec_version,
    };
    @memcpy(property.extension_name[0..name.len], name);
    return property;
}

test "extension enumeration reports VK_SUCCESS whenever the guest array held the whole list" {
    // A MoltenVK-sized list: the driver on an Apple GPU reports well over a
    // hundred device extensions, and the guest allocates for exactly that
    // count before the second call.
    const total = 131;
    var available: [total]abi.ExtensionProperties = undefined;
    for (&available, 0..) |*property, index| {
        var name_buffer: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buffer, "VK_TEST_extension_{d}", .{index}) catch unreachable;
        property.* = testExtensionProperty(name, @intCast(index + 1));
    }

    const count_address: u64 = 8;
    const array_address: u64 = 64;
    const span = array_address + total * @sizeOf(abi.ExtensionProperties);
    const memory = try std.testing.allocator.alloc(u8, @intCast(span));
    defer std.testing.allocator.free(memory);
    @memset(memory, 0);
    var state = WideGuestMemory{ .mem = memory };

    // Probe call: null pProperties asks only for the count.
    try std.testing.expectEqual(@as(u64, 0), writeExtensionPropertiesArray(&state, count_address, 0, &available));
    try std.testing.expectEqual(@as(u32, total), state.read32(count_address));

    // Fill call sized from that count. The guest had room for everything, so
    // the answer is VK_SUCCESS — a bridge-side window that truncated here is
    // read by the guest as an unusable adapter, not as a partial answer.
    try std.testing.expectEqual(@as(u64, 0), writeExtensionPropertiesArray(&state, count_address, array_address, &available));
    try std.testing.expectEqual(@as(u32, total), state.read32(count_address));
    const first = @as(usize, @intCast(array_address));
    const last = first + (total - 1) * @sizeOf(abi.ExtensionProperties);
    try std.testing.expectEqualStrings("VK_TEST_extension_0", std.mem.sliceTo(memory[first..][0..abi.MAX_EXTENSION_NAME_SIZE], 0));
    try std.testing.expectEqualStrings("VK_TEST_extension_130", std.mem.sliceTo(memory[last..][0..abi.MAX_EXTENSION_NAME_SIZE], 0));
    try std.testing.expectEqual(@as(u32, total), std.mem.readInt(u32, memory[last + abi.MAX_EXTENSION_NAME_SIZE ..][0..4], .little));
}

test "extension enumeration reports VK_INCOMPLETE only for a short guest array" {
    const available = [_]abi.ExtensionProperties{
        testExtensionProperty("VK_KHR_swapchain", 70),
        testExtensionProperty("VK_KHR_portability_subset", 1),
        testExtensionProperty("VK_KHR_maintenance1", 2),
    };
    var state = TestState{};
    const count_address: u64 = 8;
    const array_address: u64 = 64;

    state.write32(count_address, 2);
    try std.testing.expectEqual(
        @as(u64, @as(u32, @bitCast(abi.INCOMPLETE))),
        writeExtensionPropertiesArray(&state, count_address, array_address, &available),
    );
    try std.testing.expectEqual(@as(u32, 2), state.read32(count_address));
    try std.testing.expectEqualStrings("VK_KHR_swapchain", std.mem.sliceTo(state.mem[64..320], 0));
    try std.testing.expectEqualStrings("VK_KHR_portability_subset", std.mem.sliceTo(state.mem[324..580], 0));
    // The third entry was never written.
    try std.testing.expectEqual(@as(u8, 0), state.mem[584]);

    // A zero-capacity array is still a short array, not a count query.
    state.write32(count_address, 0);
    try std.testing.expectEqual(
        @as(u64, @as(u32, @bitCast(abi.INCOMPLETE))),
        writeExtensionPropertiesArray(&state, count_address, array_address, &available),
    );
    try std.testing.expectEqual(@as(u32, 0), state.read32(count_address));

    // An unmapped count pointer is a hard failure, never a silent zero.
    try std.testing.expectEqual(
        vkErrorInitializationFailed(),
        writeExtensionPropertiesArray(&state, state.mem.len + 8, 0, &available),
    );
}

test "modeled device extension enumeration answers the guest's two-call protocol" {
    var state = TestState{};
    const count_address: u64 = 8;
    const array_address: u64 = 64;

    state.regs.rsi = 0;
    state.regs.rdx = count_address;
    state.regs.rcx = 0;
    try std.testing.expectEqual(@as(u64, 0), enumerateDeviceExtensions(&state));
    try std.testing.expectEqual(@as(u32, device_extensions.len), state.read32(count_address));

    state.regs.rcx = array_address;
    try std.testing.expectEqual(@as(u64, 0), enumerateDeviceExtensions(&state));
    try std.testing.expectEqual(@as(u32, device_extensions.len), state.read32(count_address));
    for (device_extensions, 0..) |name, index| {
        const offset = @as(usize, @intCast(array_address)) + index * @sizeOf(abi.ExtensionProperties);
        try std.testing.expectEqualStrings(name, std.mem.sliceTo(state.mem[offset..][0..256], 0));
        try std.testing.expectEqual(@as(u32, 1), state.read32(@intCast(offset + 256)));
    }
}

test "extension enumeration refuses a layer the bridge never enumerated" {
    var state = TestState{};
    const count_address: u64 = 8;
    @memcpy(state.mem[1024..][0.."VK_LAYER_KHRONOS_validation".len], "VK_LAYER_KHRONOS_validation");

    // The bridge enumerates no layers, so naming one cannot resolve. Reporting
    // an empty list instead would claim the layer exists and simply adds
    // nothing.
    state.regs.rsi = 1024;
    state.regs.rdx = count_address;
    state.regs.rcx = 64;
    state.write32(count_address, 4);
    try std.testing.expectEqual(
        @as(u64, @as(u32, @bitCast(abi.ERROR_LAYER_NOT_PRESENT))),
        enumerateDeviceExtensions(&state),
    );
    try std.testing.expectEqual(@as(u32, 0), state.read32(count_address));

    state.regs.rdi = 1024;
    state.regs.rsi = count_address;
    state.regs.rdx = 64;
    state.write32(count_address, 4);
    try std.testing.expectEqual(
        @as(u64, @as(u32, @bitCast(abi.ERROR_LAYER_NOT_PRESENT))),
        enumerateInstanceExtensionsSynthetic(&state),
    );
    try std.testing.expectEqual(@as(u32, 0), state.read32(count_address));
}

test "modeled instance extension enumeration matches the advertised list" {
    var state = TestState{};
    const count_address: u64 = 8;
    state.regs.rdi = 0;
    state.regs.rsi = count_address;
    state.regs.rdx = 0;
    try std.testing.expectEqual(@as(u64, 0), enumerateInstanceExtensionsSynthetic(&state));
    try std.testing.expectEqual(@as(u32, extension_names.len), state.read32(count_address));

    state.regs.rdx = 64;
    try std.testing.expectEqual(@as(u64, 0), enumerateInstanceExtensionsSynthetic(&state));
    try std.testing.expectEqual(@as(u32, extension_names.len), state.read32(count_address));
    for (extension_names, 0..) |name, index| {
        const offset = 64 + index * @sizeOf(abi.ExtensionProperties);
        try std.testing.expectEqualStrings(name, std.mem.sliceTo(state.mem[offset..][0..256], 0));
    }
}

test "guest VkApplicationInfo is read at the ABI's own field offsets" {
    var state = TestState{};
    const app_info_address: u64 = 64;
    // Lay out a guest VkApplicationInfo by hand: sType, pNext,
    // pApplicationName, applicationVersion, pEngineName, engineVersion,
    // apiVersion.
    state.write32(app_info_address, abi.STRUCTURE_TYPE_APPLICATION_INFO);
    state.write64(app_info_address + 8, 0x1111_2222);
    state.write64(app_info_address + 16, 0x3333_4444);
    state.write32(app_info_address + 24, 7);
    state.write64(app_info_address + 32, 0x5555_6666);
    state.write32(app_info_address + 40, 9);
    state.write32(app_info_address + 44, abi.makeApiVersion(1, 3, 0));
    // Whatever follows the structure must not be mistaken for apiVersion.
    state.write32(app_info_address + 48, 0xDEAD_BEEF);

    const app_info = readGuestApplicationInfo(&state, app_info_address) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 7), app_info.application_version);
    try std.testing.expectEqual(@as(u32, 9), app_info.engine_version);
    // Clamped to the version the synthetic loader advertises, and emphatically
    // not zero: a zero here makes the host loader build a Vulkan 1.0 instance,
    // and MoltenVK then reports a 1.0 physical device.
    try std.testing.expectEqual(abi.makeApiVersion(1, 2, 0), app_info.api_version);
    try std.testing.expect(app_info.p_next == null);
    try std.testing.expect(app_info.application_name == null);
    try std.testing.expect(app_info.engine_name == null);

    // A guest that genuinely asks for 1.0 keeps 1.0, and a missing or
    // unreadable structure is reported as absent rather than as version zero.
    state.write32(app_info_address + 44, abi.makeApiVersion(1, 0, 0));
    const clamped = readGuestApplicationInfo(&state, app_info_address) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(abi.makeApiVersion(1, 0, 0), clamped.api_version);
    try std.testing.expect(readGuestApplicationInfo(&state, 0) == null);
    try std.testing.expect(readGuestApplicationInfo(&state, state.mem.len - 8) == null);
}

test "debug utils messenger is modeled and publishes a handle the guest can destroy" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    var state = TestState{};
    const library = forwarder.openGuest("/tmp/libvulkan.1.dylib", RTLD_LAZY | RTLD_LOCAL);
    const create = forwarder.lookupGuest(library, "vkCreateDebugUtilsMessengerEXT");
    const destroy = forwarder.lookupGuest(library, "vkDestroyDebugUtilsMessengerEXT");
    const set_name = forwarder.lookupGuest(library, "vkSetDebugUtilsObjectNameEXT");
    try std.testing.expect(create != 0 and destroy != 0 and set_name != 0);

    // vkCreateDebugUtilsMessengerEXT(instance, pCreateInfo, pAllocator,
    // pMessenger): the guest's output handle is rcx. Returning VK_SUCCESS
    // without writing it leaves the guest holding uninitialised memory that it
    // will hand back at instance teardown.
    state.regs.rdi = 0x1000;
    state.regs.rsi = 0x2000;
    state.regs.rdx = 0;
    state.regs.rcx = 128;
    state.write64(128, 0xA5A5_A5A5_A5A5_A5A5);
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, create));
    try std.testing.expectEqual(@as(u64, 0), state.regs.rax);
    try std.testing.expectEqual(SYNTHETIC_DEBUG_MESSENGER_HANDLE, state.read64(128));
    try std.testing.expectEqual(SYNTHETIC_DEBUG_MESSENGER_HANDLE, forwarder.debug_messenger_handle);

    state.regs.rdi = 0x1000;
    state.regs.rsi = SYNTHETIC_DEBUG_MESSENGER_HANDLE;
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, destroy));
    try std.testing.expectEqual(@as(u64, 0), state.regs.rax);
    try std.testing.expectEqual(@as(u64, 0), forwarder.debug_messenger_handle);

    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, set_name));
    try std.testing.expectEqual(@as(u64, 0), state.regs.rax);

    // An unwritable output pointer is a failure, not a silent success.
    state.regs.rcx = 0;
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, create));
    try std.testing.expectEqual(vkErrorInitializationFailed(), state.regs.rax);
}

test "guest Vulkan create-info offsets match the ABI the bridge reads through" {
    // ensureRealInstance and ensureRealDevice read these fields out of guest
    // memory by offset. The layer arrays sit between the queue arrays and the
    // extension arrays, so reading the extension count one field early lands
    // on enabledLayerCount — always zero — and forwards neither the guest's
    // extensions nor, one field further on, its features.
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(abi.DeviceCreateInfo, "enabled_extension_count"));
    try std.testing.expectEqual(@as(usize, 56), @offsetOf(abi.DeviceCreateInfo, "enabled_extension_names"));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(abi.DeviceCreateInfo, "enabled_features"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(abi.DeviceCreateInfo, "queue_create_info_count"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(abi.DeviceCreateInfo, "queue_create_infos"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(abi.InstanceCreateInfo, "application_info"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(abi.InstanceCreateInfo, "enabled_extension_count"));
    try std.testing.expectEqual(@as(usize, 56), @offsetOf(abi.InstanceCreateInfo, "enabled_extension_names"));
    try std.testing.expectEqual(@as(usize, 44), @offsetOf(abi.ApplicationInfo, "api_version"));
}

test "a dynamic viewport array is absent, not unmarshalable" {
    var state = TestState{};
    var viewports: [16]abi.Viewport = undefined;

    // VK_DYNAMIC_STATE_VIEWPORT: viewportCount is 1 and pViewports is null.
    // Refusing this refuses every presenter pipeline ever written.
    const absent = try Forwarder.marshalGuestArray(abi.Viewport, &state, null, 1, &viewports, error.ViewportsUnreadable);
    try std.testing.expect(absent == null);

    // A zero count with a live pointer is also nothing to copy.
    const empty = try Forwarder.marshalGuestArray(abi.Viewport, &state, @ptrFromInt(64), 0, &viewports, error.ViewportsUnreadable);
    try std.testing.expect(empty == null);

    // A live pointer with a live count is copied into host storage.
    const address: u64 = 64;
    state.write32(address, @bitCast(@as(f32, 4)));
    state.write32(address + 4, @bitCast(@as(f32, 8)));
    state.write32(address + 8, @bitCast(@as(f32, 1280)));
    state.write32(address + 12, @bitCast(@as(f32, 720)));
    const copied = try Forwarder.marshalGuestArray(abi.Viewport, &state, @ptrFromInt(address), 1, &viewports, error.ViewportsUnreadable);
    try std.testing.expect(copied != null);
    try std.testing.expectEqual(@as(f32, 1280), viewports[0].width);
    try std.testing.expectEqual(@as(f32, 720), viewports[0].height);

    // A pointer the guest cannot actually back is still a refusal, and it
    // names itself.
    try std.testing.expectError(
        error.ViewportsUnreadable,
        Forwarder.marshalGuestArray(abi.Viewport, &state, @ptrFromInt(state.mem.len - 4), 1, &viewports, error.ViewportsUnreadable),
    );
}

test "specialization constants are copied out of guest memory before a stage is forwarded" {
    var state = TestState{};
    const info_address: u64 = 64;
    const entries_address: u64 = 256;
    const data_address: u64 = 512;

    // VkSpecializationMapEntry { constantID, offset, size }, then the blob.
    state.write32(entries_address, 7);
    state.write32(entries_address + 4, 0);
    state.write64(entries_address + 8, 4);
    state.write32(data_address, 0xABCD1234);

    state.write32(info_address, 1);
    state.write64(info_address + 8, entries_address);
    state.write64(info_address + 16, 4);
    state.write64(info_address + 24, data_address);

    var scratch: Forwarder.SpecializationScratch = .{};
    const marshalled = try Forwarder.marshalSpecializationInfo(&state, info_address, &scratch);
    try std.testing.expectEqual(@as(u32, 1), marshalled.map_entry_count);
    try std.testing.expectEqual(@as(u32, 7), scratch.entries[0].constant_id);
    try std.testing.expectEqual(@as(usize, 4), scratch.entries[0].size);
    try std.testing.expectEqual(@as(usize, 4), marshalled.data_size);
    // Both pointers must now be host-owned: the guest addresses they arrived
    // as are meaningless to the driver.
    try std.testing.expectEqual(@intFromPtr(&scratch.entries), @intFromPtr(marshalled.map_entries.?));
    try std.testing.expectEqual(@intFromPtr(&scratch.data), @intFromPtr(marshalled.data.?));
    try std.testing.expectEqual(@as(u32, 0xABCD1234), std.mem.readInt(u32, scratch.data[0..4], .little));

    // A map larger than the bridge's storage is refused by name rather than
    // silently truncated into a wrong pipeline.
    state.write32(info_address, 64);
    try std.testing.expectError(
        error.SpecializationMapOutOfRange,
        Forwarder.marshalSpecializationInfo(&state, info_address, &scratch),
    );
    state.write32(info_address, 1);
    state.write64(info_address + 16, 4096);
    try std.testing.expectError(
        error.SpecializationDataOutOfRange,
        Forwarder.marshalSpecializationInfo(&state, info_address, &scratch),
    );
}

test "bridge capability table describes structures the ABI actually declares" {
    // Each entry is written into a fixed-size scratch node and handed to the
    // driver, so a size that disagrees with the declared structure would have
    // the driver read past what was initialised.
    for (bridge_device_capabilities) |capability| {
        try std.testing.expect(capability.extension.len != 0);
        try std.testing.expect(capability.provides.len != 0);
        if (capability.feature_s_type == 0) {
            try std.testing.expectEqual(@as(u16, 0), capability.feature_size);
            continue;
        }
        // 16 bytes of sType/pNext header plus at least one VkBool32.
        try std.testing.expect(capability.feature_size >= 24);
        try std.testing.expect(capability.feature_size <= feature_chain_node_bytes);
        try std.testing.expectEqual(@as(u16, 0), capability.feature_size % 8);
    }
    // The four the bridge negotiates on a MoltenVK host, by declared size.
    try std.testing.expectEqual(@as(u16, 24), @sizeOf(abi.PhysicalDeviceSynchronization2Features));
    try std.testing.expectEqual(@as(u16, 24), @sizeOf(abi.PhysicalDeviceDynamicRenderingFeatures));
    try std.testing.expectEqual(@as(u16, 24), @sizeOf(abi.PhysicalDeviceExtendedDynamicStateFeaturesEXT));
    try std.testing.expectEqual(@as(u16, 32), @sizeOf(abi.PhysicalDeviceExtendedDynamicState2FeaturesEXT));
}

test "the bridge capability chain links its nodes and then hands off to the guest's" {
    var scratch: BridgeCapabilityScratch = .{};
    scratch.count = 3;
    for (0..3) |slot| scratch.order[slot] = @intCast(slot);
    linkBridgeCapabilityChain(&scratch);

    for (0..2) |slot| {
        const size = bridge_device_capabilities[scratch.order[slot]].feature_size;
        const next = std.mem.readInt(u64, scratch.nodes[slot][8..16], .little);
        try std.testing.expectEqual(@intFromPtr(&scratch.nodes[slot + 1]), next);
        try std.testing.expect(size >= 24);
    }
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, scratch.nodes[2][8..16], .little));

    // With no guest chain the bridge chain terminates; with one, the bridge
    // tail points at it so both halves reach the driver.
    const head = spliceBridgeCapabilityChain(&scratch, null);
    try std.testing.expectEqual(@intFromPtr(&scratch.nodes[0]), @intFromPtr(head.?));
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, scratch.nodes[2][8..16], .little));

    var guest_node: [64]u8 align(8) = [_]u8{0} ** 64;
    const spliced = spliceBridgeCapabilityChain(&scratch, @ptrCast(&guest_node));
    try std.testing.expectEqual(@intFromPtr(&scratch.nodes[0]), @intFromPtr(spliced.?));
    try std.testing.expectEqual(@intFromPtr(&guest_node), std.mem.readInt(u64, scratch.nodes[2][8..16], .little));

    // An empty bridge chain must leave the guest's chain as the head rather
    // than replacing it with an uninitialised node.
    var empty: BridgeCapabilityScratch = .{};
    try std.testing.expectEqual(@intFromPtr(&guest_node), @intFromPtr(spliceBridgeCapabilityChain(&empty, @ptrCast(&guest_node)).?));
    try std.testing.expect(spliceBridgeCapabilityChain(&empty, null) == null);
}

test "a caller's two-call enumeration loop terminates against the bridge contract" {
    // The loop Xenia's presenter runs, verbatim in shape: probe with a null
    // array, resize to the reported count, fill, and only stop on VK_SUCCESS.
    // It has no iteration bound of its own, so the bridge's contract is the
    // only thing that ends it — and when the bridge reported a count it then
    // refused to deliver, the loop ran for three billion instructions.
    const available = [_]abi.ExtensionProperties{
        testExtensionProperty("VK_KHR_swapchain", 70),
        testExtensionProperty("VK_KHR_portability_subset", 1),
        testExtensionProperty("VK_KHR_maintenance1", 2),
    };
    var state = TestState{};
    const count_address: u64 = 8;
    const array_address: u64 = 64;

    var reported: u32 = 0;
    var iterations: usize = 0;
    while (iterations < 8) : (iterations += 1) {
        state.write32(count_address, reported);
        const were_empty = reported == 0;
        const result = writeExtensionPropertiesArray(
            &state,
            count_address,
            if (were_empty) 0 else array_address,
            &available,
        );
        reported = state.read32(count_address);
        if (result == @as(u64, @as(u32, @bitCast(abi.SUCCESS)))) {
            if (!were_empty or reported == 0) break;
        } else if (result != @as(u64, @as(u32, @bitCast(abi.INCOMPLETE)))) {
            break;
        }
    }
    // Probe, then fill: two passes, and the second is the one that ends it.
    try std.testing.expectEqual(@as(usize, 1), iterations);
    try std.testing.expectEqual(@as(u32, available.len), reported);
}

test "a surface enumeration is bounded to what the fill can deliver" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    // Under the bound the driver's own count passes through untouched.
    try std.testing.expectEqual(@as(u32, 2), forwarder.boundSurfaceEnumeration(2, "surface present modes"));
    try std.testing.expectEqual(MAX_SURFACE_ENUMERATION, forwarder.boundSurfaceEnumeration(MAX_SURFACE_ENUMERATION, "surface formats"));
    try std.testing.expect(!forwarder.surface_enumeration_bound_reported);

    // Over it, the guest is told the number the bridge can actually fill —
    // MoltenVK reports sixty surface formats for a Metal surface — and the
    // truncation is reported once rather than per call.
    try std.testing.expectEqual(MAX_SURFACE_ENUMERATION, forwarder.boundSurfaceEnumeration(4096, "surface formats"));
    try std.testing.expect(forwarder.surface_enumeration_bound_reported);
    try std.testing.expectEqual(MAX_SURFACE_ENUMERATION, forwarder.boundSurfaceEnumeration(4096, "surface formats"));
    try std.testing.expect(MAX_SURFACE_ENUMERATION >= 60);
}
