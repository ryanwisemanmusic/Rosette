//! A real Vulkan presenter: `CAMetalLayer` to a presented swapchain image, with
//! every stage forwarded to the host driver.
//!
//! What this replaces is a path that reached a genuine `VkSurfaceKHR` and then
//! answered everything after it itself — synthetic device, synthetic swapchain,
//! synthetic images, a `vkQueueSubmit` that incremented a counter, and a
//! "present" that was a Metal clear on a drawable the guest never touched. That
//! arrangement can only ever display Rosette's own colour, because no object in
//! it has a parent the driver recognises. Vulkan object parentage is not
//! cosmetic: a swapchain belongs to a device, an image belongs to a swapchain,
//! and a queue may only present to a surface its family was proven to support.
//!
//! So this owns the whole chain and owns it natively. It enumerates rather than
//! assumes — extensions, physical devices, queue families, surface formats,
//! present modes, memory types — and refuses instead of guessing when the host
//! does not report what the path needs. The refusal is the useful outcome:
//! `Stage` names the first thing that was unavailable, which is the next thing
//! to fix, and no later stage reports itself ready on top of it.
//!
//! Two things it deliberately does not do. It does not open the Vulkan library:
//! resolving the host loader is dyld's business, so a symbol resolver is passed
//! in and this stays free of `dlopen` policy and of libc. And it does not
//! print: it accumulates a `Report` its caller logs, so the whole module stays
//! testable without a driver, a window, or a runloop.
//!
//! The frame loop is the textbook one, deliberately — acquire on a semaphore,
//! record, submit waiting on that semaphore and signalling another, present
//! waiting on the second, one fence per frame slot — because every shortcut
//! available here trades a real synchronisation edge for a counter that looks
//! identical in a log.

const std = @import("std");
const abi = @import("abi.zig");
const selection = @import("selection.zig");
const frame = @import("frame.zig");
const provenance = @import("../provenance.zig");
const frame_source = @import("../frame_source.zig");
const forwarding = @import("../forwarding.zig");
const backend = @import("../backend.zig");

const max_physical_devices: usize = 8;
const max_queue_families: usize = 16;
const max_surface_formats: usize = 32;
const max_present_modes: usize = 8;
const max_extensions: usize = 512;
/// A CPU source larger than this is a mistake upstream, not a frame.
const max_staging_bytes: u64 = 64 * 1024 * 1024;
/// Long enough to ride out a compositor hitch, short enough that an occluded
/// window reports back instead of parking the caller indefinitely.
const acquire_timeout_nanoseconds: u64 = 1_000_000_000;
const fence_timeout_nanoseconds: u64 = 2_000_000_000;

pub const instance_extension_surface = "VK_KHR_surface";
pub const instance_extension_metal_surface = "VK_EXT_metal_surface";
pub const instance_extension_portability_enumeration = "VK_KHR_portability_enumeration";
pub const device_extension_swapchain = "VK_KHR_swapchain";
/// Must be enabled whenever the physical device advertises it. MoltenVK does,
/// and omitting it makes `vkCreateDevice` fail with a code that says nothing
/// about which extension was missing.
pub const device_extension_portability_subset = "VK_KHR_portability_subset";

/// How far the native path got. Ordered, so the first stage not reached is both
/// the reason there are no guest pixels and the next thing to build.
pub const Stage = enum(u8) {
    unstarted,
    loader_unavailable,
    instance_extensions_missing,
    instance_failed,
    surface_failed,
    no_supported_physical_device,
    device_failed,
    frame_resources_failed,
    swapchain_failed,
    /// The surface currently has no area — minimised, occluded, or mid-resize.
    /// Deliberately not a failure: the window will come back, and treating this
    /// as terminal leaves a permanently dead presenter behind a window that
    /// looks fine.
    surface_not_presentable,
    /// Every stage is native and a frame can be presented.
    ready,
    /// Terminal. The device is gone and none of its objects may be used again.
    device_lost,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .unstarted => "the native presenter has not been started",
            .loader_unavailable => "the host Vulkan loader did not resolve vkGetInstanceProcAddr",
            .instance_extensions_missing => "the host instance does not offer VK_KHR_surface and VK_EXT_metal_surface",
            .instance_failed => "vkCreateInstance failed or an instance entry point did not resolve",
            .surface_failed => "vkCreateMetalSurfaceEXT failed against the window's CAMetalLayer",
            .no_supported_physical_device => "no physical device can both render and present to this surface",
            .device_failed => "vkCreateDevice failed or a device entry point did not resolve",
            .frame_resources_failed => "per-frame command buffers, semaphores or fences could not be created",
            .swapchain_failed => "the swapchain could not be created from the surface's reported capabilities",
            .surface_not_presentable => "the surface has no area right now (minimised, occluded or mid-resize); this is backpressure and the presenter will retry",
            .ready => "native instance, surface, physical device, logical device, queue and swapchain are live",
            .device_lost => "the device was lost; this presenter session is over",
        };
    }

    pub fn isReady(self: Stage) bool {
        return self == .ready;
    }

    /// Whether another attempt could succeed without anything else changing.
    /// A swapchain that failed against a surface which has since been resized,
    /// and a surface that had no area a moment ago, are both worth retrying;
    /// a missing loader or a lost device are not.
    pub fn retryable(self: Stage) bool {
        return self == .surface_not_presentable or self == .swapchain_failed;
    }
};

/// What one frame attempt did. Every field is an observation, not an intent.
pub const FrameReport = struct {
    attempted: bool = false,
    generation: u32 = 0,
    frame_slot: u32 = 0,
    image_index: u32 = 0,
    acquire_result: abi.Result = abi.SUCCESS,
    acquire_outcome: selection.AcquireOutcome = .retry,
    submit_result: abi.Result = abi.SUCCESS,
    submitted: bool = false,
    present_result: abi.Result = abi.SUCCESS,
    present_outcome: selection.PresentOutcome = .failed,
    presented: bool = false,
    /// Set when the image was written by a copy from a real source rather than
    /// by a clear.
    source_copied: bool = false,
    composite: Composite = .none,
    /// Where the source landed in the acquired image. Bars around it mean the
    /// aspect ratio was preserved rather than the frame being cropped.
    destination: frame_source.Rect = .{},
    health: frame.Health = .ready,
    classification: provenance.Classification = .rejected,
};

/// Accumulated session facts for the caller to log. The presenter does not
/// print: printing from here would make it untestable and would put driver
/// strings on a per-frame path.
pub const Report = struct {
    stage: Stage = .unstarted,
    last_result: abi.Result = abi.SUCCESS,
    rejection: ?selection.Rejection = null,
    adapter_name: [abi.MAX_PHYSICAL_DEVICE_NAME_SIZE]u8 = [_]u8{0} ** abi.MAX_PHYSICAL_DEVICE_NAME_SIZE,
    adapter_name_length: u16 = 0,
    api_version: u32 = 0,
    physical_device_count: u32 = 0,
    graphics_family: u32 = 0,
    present_family: u32 = 0,
    unified_queue: bool = false,
    portability_enumeration: bool = false,
    portability_subset: bool = false,
    surface_format: u32 = abi.FORMAT_UNDEFINED,
    surface_color_space: u32 = 0,
    present_mode: u32 = 0,
    image_usage: u32 = 0,
    swapchain_image_count: u32 = 0,
    extent_width: u32 = 0,
    extent_height: u32 = 0,
    swapchain_generations: u32 = 0,
    surface_recreations: u32 = 0,
    blit_supported: bool = false,
    blit_filter: u32 = 0,
    instance_extensions_seen: u32 = 0,

    pub fn adapterName(self: *const Report) []const u8 {
        return self.adapter_name[0..self.adapter_name_length];
    }

    pub fn rejectionLabel(self: *const Report) []const u8 {
        const rejection = self.rejection orelse return "none";
        return selection.rejectionLabel(rejection);
    }

    fn setAdapterName(self: *Report, name: []const u8) void {
        @memset(&self.adapter_name, 0);
        const length = @min(name.len, self.adapter_name.len);
        @memcpy(self.adapter_name[0..length], name[0..length]);
        self.adapter_name_length = @intCast(length);
    }
};

/// Resolving the host Vulkan library is dyld's job, not the GPU library's, so
/// the one symbol the presenter needs is handed in.
pub const SymbolResolver = struct {
    context: ?*anyopaque = null,
    lookup: ?*const fn (?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque = null,

    pub fn resolve(self: SymbolResolver, name: [*:0]const u8) ?*anyopaque {
        const lookup = self.lookup orelse return null;
        return lookup(self.context, name);
    }
};

const InstanceEntries = struct {
    get_instance_proc_addr: abi.PfnGetInstanceProcAddr,
    enumerate_instance_extensions: ?abi.PfnEnumerateInstanceExtensionProperties = null,
    destroy_instance: ?abi.PfnDestroyInstance = null,
    destroy_surface: ?abi.PfnDestroySurfaceKHR = null,
    enumerate_physical_devices: abi.PfnEnumeratePhysicalDevices = undefined,
    get_physical_device_properties: abi.PfnGetPhysicalDeviceProperties = undefined,
    get_queue_family_properties: abi.PfnGetPhysicalDeviceQueueFamilyProperties = undefined,
    get_memory_properties: abi.PfnGetPhysicalDeviceMemoryProperties = undefined,
    enumerate_device_extensions: abi.PfnEnumerateDeviceExtensionProperties = undefined,
    create_metal_surface: abi.PfnCreateMetalSurfaceEXT = undefined,
    get_surface_support: abi.PfnGetPhysicalDeviceSurfaceSupportKHR = undefined,
    get_surface_capabilities: abi.PfnGetPhysicalDeviceSurfaceCapabilitiesKHR = undefined,
    get_surface_formats: abi.PfnGetPhysicalDeviceSurfaceFormatsKHR = undefined,
    get_surface_present_modes: abi.PfnGetPhysicalDeviceSurfacePresentModesKHR = undefined,
    get_format_properties: abi.PfnGetPhysicalDeviceFormatProperties = undefined,
    create_device: abi.PfnCreateDevice = undefined,
    get_device_proc_addr: abi.PfnGetDeviceProcAddr = undefined,
};

/// Resolved by name, one line each. A generated name is a silent runtime
/// failure when it is wrong, and the ones Vulkan spells irregularly — the WSI
/// `KHR` suffixes — are exactly the ones on the presentation path.
const DeviceEntries = struct {
    destroy_device: abi.PfnDestroyDevice = undefined,
    device_wait_idle: abi.PfnDeviceWaitIdle = undefined,
    get_device_queue: abi.PfnGetDeviceQueue = undefined,
    create_swapchain: abi.PfnCreateSwapchainKHR = undefined,
    destroy_swapchain: abi.PfnDestroySwapchainKHR = undefined,
    get_swapchain_images: abi.PfnGetSwapchainImagesKHR = undefined,
    acquire_next_image: abi.PfnAcquireNextImageKHR = undefined,
    queue_present: abi.PfnQueuePresentKHR = undefined,
    create_command_pool: abi.PfnCreateCommandPool = undefined,
    destroy_command_pool: abi.PfnDestroyCommandPool = undefined,
    allocate_command_buffers: abi.PfnAllocateCommandBuffers = undefined,
    begin_command_buffer: abi.PfnBeginCommandBuffer = undefined,
    end_command_buffer: abi.PfnEndCommandBuffer = undefined,
    reset_command_buffer: abi.PfnResetCommandBuffer = undefined,
    create_semaphore: abi.PfnCreateSemaphore = undefined,
    destroy_semaphore: abi.PfnDestroySemaphore = undefined,
    create_fence: abi.PfnCreateFence = undefined,
    destroy_fence: abi.PfnDestroyFence = undefined,
    wait_for_fences: abi.PfnWaitForFences = undefined,
    reset_fences: abi.PfnResetFences = undefined,
    queue_submit: abi.PfnQueueSubmit = undefined,
    queue_wait_idle: abi.PfnQueueWaitIdle = undefined,
    cmd_pipeline_barrier: abi.PfnCmdPipelineBarrier = undefined,
    cmd_clear_color_image: abi.PfnCmdClearColorImage = undefined,
    cmd_copy_buffer_to_image: abi.PfnCmdCopyBufferToImage = undefined,
    cmd_blit_image: abi.PfnCmdBlitImage = undefined,
    create_image: abi.PfnCreateImage = undefined,
    destroy_image: abi.PfnDestroyImage = undefined,
    get_image_memory_requirements: abi.PfnGetImageMemoryRequirements = undefined,
    bind_image_memory: abi.PfnBindImageMemory = undefined,
    create_buffer: abi.PfnCreateBuffer = undefined,
    destroy_buffer: abi.PfnDestroyBuffer = undefined,
    get_buffer_memory_requirements: abi.PfnGetBufferMemoryRequirements = undefined,
    allocate_memory: abi.PfnAllocateMemory = undefined,
    free_memory: abi.PfnFreeMemory = undefined,
    bind_buffer_memory: abi.PfnBindBufferMemory = undefined,
    map_memory: abi.PfnMapMemory = undefined,
    unmap_memory: abi.PfnUnmapMemory = undefined,
    flush_mapped_memory_ranges: abi.PfnFlushMappedMemoryRanges = undefined,
};

const FrameContext = struct {
    command_buffer: abi.CommandBuffer = null,
    acquire_semaphore: abi.Semaphore = abi.null_handle,
    render_finished_semaphore: abi.Semaphore = abi.null_handle,
    in_flight_fence: abi.Fence = abi.null_handle,
    /// Whether a submission using this slot's fence is outstanding. A fence
    /// created signalled but never submitted must not be waited on as though it
    /// guarded work.
    submitted: bool = false,
};

const Staging = struct {
    buffer: abi.Buffer = abi.null_handle,
    memory: abi.DeviceMemory = abi.null_handle,
    mapped: ?[*]u8 = null,
    capacity: u64 = 0,
    coherent: bool = false,
};

/// The intermediate a scaled or flipped frame passes through. `vkCmdBlitImage`
/// reads an image, not a buffer, so a source that does not match the swapchain
/// exactly has to land somewhere first.
const StagingImage = struct {
    image: abi.Image = abi.null_handle,
    memory: abi.DeviceMemory = abi.null_handle,
    width: u32 = 0,
    height: u32 = 0,
    format: u32 = abi.FORMAT_UNDEFINED,
};

/// Where a frame's pixels come from. A clear is a liveness probe and is
/// labelled as one; a CPU image carries the provenance of whoever produced it.
pub const Source = union(enum) {
    /// Host-generated colour. Proves the native path works end to end, and
    /// nothing else.
    clear: [4]f32,
    /// A completed CPU framebuffer to upload and copy into the acquired image.
    cpu_image: CpuImage,
};

pub const CpuImage = struct {
    pixels: []const u8,
    width: u32,
    height: u32,
    format: u32,
    /// Bytes per row as the producer laid them out. Zero means tightly packed.
    row_pitch_bytes: u64 = 0,
    /// Which row is the top of the picture. Stated by the producer because
    /// guessing yields an upside-down frame, not an error.
    orientation: frame_source.Orientation = .top_down,
    /// How a source that does not match the window is fitted into it.
    fit: frame_source.Fit = .letterbox,
    producer: provenance.Producer = .xenia_host,
    /// Whether the guest performed the swap this image belongs to.
    guest_swap_observed: bool = false,
};

/// How the presenter got the source onto the acquired image. Recorded because
/// "the frame was presented" does not distinguish a correctly scaled picture
/// from a correctly scaled picture the driver could not scale.
pub const Composite = enum(u8) {
    none,
    /// Host-generated colour.
    clear,
    /// Source extent equalled the swapchain extent: a straight copy.
    direct_copy,
    /// Scaled, letterboxed and/or flipped through a staging image.
    blit,
};

pub const Presenter = struct {
    stage: Stage = .unstarted,
    report: Report = .{},
    ledger: provenance.Ledger = .{},
    ring: frame.Ring = .{},

    resolver: SymbolResolver = .{},
    instance_entries: ?InstanceEntries = null,
    device_entries: DeviceEntries = .{},

    metal_layer: usize = 0,
    instance: abi.Instance = null,
    surface: abi.SurfaceKHR = abi.null_handle,
    physical_device: abi.PhysicalDevice = null,
    device: abi.Device = null,
    graphics_queue: abi.Queue = null,
    present_queue: abi.Queue = null,
    queues: selection.QueueSelection = .{ .graphics_family = 0, .present_family = 0 },
    memory_properties: abi.PhysicalDeviceMemoryProperties = .{},

    swapchain: abi.SwapchainKHR = abi.null_handle,
    swapchain_images: [frame.max_swapchain_images]abi.Image = [_]abi.Image{abi.null_handle} ** frame.max_swapchain_images,
    swapchain_image_count: u32 = 0,
    surface_format: abi.SurfaceFormatKHR = .{},
    extent: abi.Extent2D = .{},
    present_mode: u32 = abi.PRESENT_MODE_FIFO_KHR,
    image_usage: u32 = 0,

    command_pool: abi.CommandPool = abi.null_handle,
    frames: [frame.max_frames_in_flight]FrameContext = [_]FrameContext{.{}} ** frame.max_frames_in_flight,
    staging: Staging = .{},
    staging_image: StagingImage = .{},
    /// Whether the driver will blit this swapchain format, learned from
    /// `vkGetPhysicalDeviceFormatProperties` rather than assumed. A blit the
    /// driver cannot do is a validation error, not a soft failure.
    blit_supported: bool = false,
    blit_filter: u32 = abi.FILTER_NEAREST,

    last_frame: FrameReport = .{},

    // -- bring-up ---------------------------------------------------------

    /// Bring every stage up in dependency order, stopping at the first thing
    /// the host does not provide. Safe to call repeatedly: each stage returns
    /// immediately once it exists, so a caller may retry after the window
    /// becomes available without rebuilding what already works.
    pub fn bringUp(
        self: *Presenter,
        resolver: SymbolResolver,
        metal_layer: usize,
        fallback_width: u32,
        fallback_height: u32,
    ) Stage {
        if (self.stage == .device_lost or self.stage == .ready) return self.stage;
        self.resolver = resolver;
        self.metal_layer = metal_layer;

        if (!self.createInstance()) return self.stage;
        if (!self.createSurface()) return self.stage;
        if (!self.selectPhysicalDevice()) return self.stage;
        if (!self.createDevice()) return self.stage;
        if (!self.createFrameResources()) return self.stage;
        if (!self.createSwapchain(fallback_width, fallback_height)) return self.stage;

        self.stage = .ready;
        self.report.stage = .ready;
        self.report.last_result = abi.SUCCESS;
        return self.stage;
    }

    fn instanceProc(self: *Presenter, comptime T: type, name: [*:0]const u8) ?T {
        const entries = if (self.instance_entries) |*value| value else return null;
        const address = entries.get_instance_proc_addr(self.instance, name) orelse return null;
        self.ledger.noteNativeDriverCall();
        return @ptrCast(@alignCast(address));
    }

    fn deviceProc(self: *Presenter, comptime T: type, name: [*:0]const u8) ?T {
        const entries = if (self.instance_entries) |*value| value else return null;
        const address = entries.get_device_proc_addr(self.device, name) orelse return null;
        self.ledger.noteNativeDriverCall();
        return @ptrCast(@alignCast(address));
    }

    fn createInstance(self: *Presenter) bool {
        if (self.instance != null) return true;
        const address = self.resolver.resolve("vkGetInstanceProcAddr") orelse {
            self.fail(.loader_unavailable, abi.ERROR_INITIALIZATION_FAILED);
            return false;
        };
        self.instance_entries = .{ .get_instance_proc_addr = @ptrCast(@alignCast(address)) };

        // Instance-level entry points resolve against a null instance before
        // one exists; that is the one case the loader permits it.
        self.instance_entries.?.enumerate_instance_extensions =
            self.instanceProc(abi.PfnEnumerateInstanceExtensionProperties, "vkEnumerateInstanceExtensionProperties");

        var have_surface = false;
        var have_metal_surface = false;
        var have_portability = false;
        if (self.instance_entries.?.enumerate_instance_extensions) |enumerate| {
            var storage: [max_extensions]abi.ExtensionProperties = undefined;
            var count: u32 = max_extensions;
            const result = enumerate(null, &count, &storage);
            if (result == abi.SUCCESS or result == abi.INCOMPLETE) {
                const seen = @min(count, @as(u32, max_extensions));
                self.report.instance_extensions_seen = seen;
                for (storage[0..seen]) |*extension| {
                    const name = extension.name();
                    if (std.mem.eql(u8, name, instance_extension_surface)) have_surface = true;
                    if (std.mem.eql(u8, name, instance_extension_metal_surface)) have_metal_surface = true;
                    if (std.mem.eql(u8, name, instance_extension_portability_enumeration)) have_portability = true;
                }
            }
        }
        if (!have_surface or !have_metal_surface) {
            self.fail(.instance_extensions_missing, abi.ERROR_EXTENSION_NOT_PRESENT);
            return false;
        }
        self.report.portability_enumeration = have_portability;

        const create_instance = self.instanceProc(abi.PfnCreateInstance, "vkCreateInstance") orelse {
            self.fail(.loader_unavailable, abi.ERROR_INITIALIZATION_FAILED);
            return false;
        };

        const application_info = abi.ApplicationInfo{
            .application_name = "Rosette native presenter",
            .application_version = 1,
            .engine_name = "Rosette",
            .engine_version = 1,
            .api_version = abi.makeApiVersion(1, 2, 0),
        };
        const with_portability = [_][*:0]const u8{
            instance_extension_surface,
            instance_extension_metal_surface,
            instance_extension_portability_enumeration,
        };
        const without_portability = [_][*:0]const u8{
            instance_extension_surface,
            instance_extension_metal_surface,
        };
        var create_info = abi.InstanceCreateInfo{
            .flags = if (have_portability) abi.INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR else 0,
            .application_info = &application_info,
            .enabled_extension_count = if (have_portability) with_portability.len else without_portability.len,
            .enabled_extension_names = if (have_portability) &with_portability else &without_portability,
        };
        var instance: abi.Instance = null;
        var result = create_instance(&create_info, null, &instance);
        self.ledger.noteNativeDriverCall();
        if (result != abi.SUCCESS and have_portability) {
            // A loader that lists portability enumeration but rejects the flag
            // is still usable without it. Try the minimal profile before
            // declaring the host unable to present.
            create_info.flags = 0;
            create_info.enabled_extension_count = without_portability.len;
            create_info.enabled_extension_names = &without_portability;
            result = create_instance(&create_info, null, &instance);
            self.ledger.noteNativeDriverCall();
            if (result == abi.SUCCESS) self.report.portability_enumeration = false;
        }
        if (result != abi.SUCCESS or instance == null) {
            self.fail(.instance_failed, if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }
        self.instance = instance;
        return self.resolveInstanceEntries();
    }

    fn resolveInstanceEntries(self: *Presenter) bool {
        const entries = &self.instance_entries.?;
        entries.destroy_instance = self.instanceProc(abi.PfnDestroyInstance, "vkDestroyInstance");
        entries.destroy_surface = self.instanceProc(abi.PfnDestroySurfaceKHR, "vkDestroySurfaceKHR");
        entries.enumerate_physical_devices =
            self.instanceProc(abi.PfnEnumeratePhysicalDevices, "vkEnumeratePhysicalDevices") orelse return self.missingEntry();
        entries.get_physical_device_properties =
            self.instanceProc(abi.PfnGetPhysicalDeviceProperties, "vkGetPhysicalDeviceProperties") orelse return self.missingEntry();
        entries.get_queue_family_properties =
            self.instanceProc(abi.PfnGetPhysicalDeviceQueueFamilyProperties, "vkGetPhysicalDeviceQueueFamilyProperties") orelse return self.missingEntry();
        entries.get_memory_properties =
            self.instanceProc(abi.PfnGetPhysicalDeviceMemoryProperties, "vkGetPhysicalDeviceMemoryProperties") orelse return self.missingEntry();
        entries.enumerate_device_extensions =
            self.instanceProc(abi.PfnEnumerateDeviceExtensionProperties, "vkEnumerateDeviceExtensionProperties") orelse return self.missingEntry();
        entries.create_metal_surface =
            self.instanceProc(abi.PfnCreateMetalSurfaceEXT, "vkCreateMetalSurfaceEXT") orelse return self.missingEntry();
        entries.get_surface_support =
            self.instanceProc(abi.PfnGetPhysicalDeviceSurfaceSupportKHR, "vkGetPhysicalDeviceSurfaceSupportKHR") orelse return self.missingEntry();
        entries.get_surface_capabilities =
            self.instanceProc(abi.PfnGetPhysicalDeviceSurfaceCapabilitiesKHR, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR") orelse return self.missingEntry();
        entries.get_surface_formats =
            self.instanceProc(abi.PfnGetPhysicalDeviceSurfaceFormatsKHR, "vkGetPhysicalDeviceSurfaceFormatsKHR") orelse return self.missingEntry();
        entries.get_surface_present_modes =
            self.instanceProc(abi.PfnGetPhysicalDeviceSurfacePresentModesKHR, "vkGetPhysicalDeviceSurfacePresentModesKHR") orelse return self.missingEntry();
        entries.get_format_properties =
            self.instanceProc(abi.PfnGetPhysicalDeviceFormatProperties, "vkGetPhysicalDeviceFormatProperties") orelse return self.missingEntry();
        entries.create_device =
            self.instanceProc(abi.PfnCreateDevice, "vkCreateDevice") orelse return self.missingEntry();
        entries.get_device_proc_addr =
            self.instanceProc(abi.PfnGetDeviceProcAddr, "vkGetDeviceProcAddr") orelse return self.missingEntry();
        return true;
    }

    fn missingEntry(self: *Presenter) bool {
        self.fail(.instance_failed, abi.ERROR_EXTENSION_NOT_PRESENT);
        return false;
    }

    fn createSurface(self: *Presenter) bool {
        if (self.surface != abi.null_handle) return true;
        if (self.metal_layer == 0) {
            self.fail(.surface_failed, abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }
        const entries = &self.instance_entries.?;
        const create_info = abi.MetalSurfaceCreateInfoEXT{ .layer = @ptrFromInt(self.metal_layer) };
        var surface: abi.SurfaceKHR = abi.null_handle;
        const result = entries.create_metal_surface(self.instance, &create_info, null, &surface);
        self.ledger.noteNativeDriverCall();
        if (result != abi.SUCCESS or surface == abi.null_handle) {
            self.fail(.surface_failed, if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }
        self.surface = surface;
        return true;
    }

    fn selectPhysicalDevice(self: *Presenter) bool {
        if (self.physical_device != null) return true;
        const entries = &self.instance_entries.?;
        var devices: [max_physical_devices]abi.PhysicalDevice = [_]abi.PhysicalDevice{null} ** max_physical_devices;
        var count: u32 = max_physical_devices;
        const result = entries.enumerate_physical_devices(self.instance, &count, &devices);
        self.ledger.noteNativeDriverCall();
        if (result != abi.SUCCESS and result != abi.INCOMPLETE) {
            self.fail(.no_supported_physical_device, result);
            return false;
        }
        const found = @min(count, @as(u32, max_physical_devices));
        self.report.physical_device_count = found;
        if (found == 0) {
            self.fail(.no_supported_physical_device, abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }

        for (devices[0..found]) |candidate| {
            const device = candidate orelse continue;
            var families: [max_queue_families]abi.QueueFamilyProperties =
                [_]abi.QueueFamilyProperties{.{}} ** max_queue_families;
            var family_count: u32 = max_queue_families;
            entries.get_queue_family_properties(device, &family_count, &families);
            self.ledger.noteNativeDriverCall();
            const family_total = @min(family_count, @as(u32, max_queue_families));
            if (family_total == 0) continue;

            // Presentation support is a property of the (device, family,
            // surface) triple, not of the device. Asking per family is the
            // only way to learn it.
            var present_support: [max_queue_families]bool = [_]bool{false} ** max_queue_families;
            for (0..family_total) |index| {
                var supported: u32 = 0;
                const support_result = entries.get_surface_support(device, @intCast(index), self.surface, &supported);
                self.ledger.noteNativeDriverCall();
                present_support[index] = support_result == abi.SUCCESS and supported != 0;
            }

            const queues = selection.selectQueueFamilies(
                families[0..family_total],
                present_support[0..family_total],
            ) catch |rejection| {
                self.report.rejection = rejection;
                continue;
            };
            if (!self.deviceSupportsSwapchain(device)) continue;

            self.physical_device = device;
            self.queues = queues;
            self.report.rejection = null;
            self.report.graphics_family = queues.graphics_family;
            self.report.present_family = queues.present_family;
            self.report.unified_queue = queues.unified();

            var storage: [abi.physical_device_properties_bytes]u8 align(8) =
                [_]u8{0} ** abi.physical_device_properties_bytes;
            entries.get_physical_device_properties(device, @ptrCast(&storage));
            self.ledger.noteNativeDriverCall();
            const identity: *const abi.PhysicalDeviceIdentity = @ptrCast(&storage);
            self.report.setAdapterName(identity.name());
            self.report.api_version = identity.api_version;

            entries.get_memory_properties(device, &self.memory_properties);
            self.ledger.noteNativeDriverCall();
            return true;
        }
        self.fail(.no_supported_physical_device, abi.ERROR_INITIALIZATION_FAILED);
        return false;
    }

    fn deviceSupportsSwapchain(self: *Presenter, device: abi.PhysicalDevice) bool {
        const entries = &self.instance_entries.?;
        var storage: [max_extensions]abi.ExtensionProperties = undefined;
        var count: u32 = max_extensions;
        const result = entries.enumerate_device_extensions(device, null, &count, &storage);
        self.ledger.noteNativeDriverCall();
        if (result != abi.SUCCESS and result != abi.INCOMPLETE) return false;
        const seen = @min(count, @as(u32, max_extensions));
        var swapchain = false;
        for (storage[0..seen]) |*extension| {
            const name = extension.name();
            if (std.mem.eql(u8, name, device_extension_swapchain)) swapchain = true;
            if (std.mem.eql(u8, name, device_extension_portability_subset)) self.report.portability_subset = true;
        }
        return swapchain;
    }

    fn createDevice(self: *Presenter) bool {
        if (self.device != null) return true;
        const entries = &self.instance_entries.?;
        const priority = [_]f32{1.0};
        var queue_infos: [2]abi.DeviceQueueCreateInfo = undefined;
        queue_infos[0] = .{
            .queue_family_index = self.queues.graphics_family,
            .queue_count = 1,
            .queue_priorities = &priority,
        };
        var queue_info_count: u32 = 1;
        if (!self.queues.unified()) {
            queue_infos[1] = .{
                .queue_family_index = self.queues.present_family,
                .queue_count = 1,
                .queue_priorities = &priority,
            };
            queue_info_count = 2;
        }

        const with_subset = [_][*:0]const u8{ device_extension_swapchain, device_extension_portability_subset };
        const without_subset = [_][*:0]const u8{device_extension_swapchain};
        const create_info = abi.DeviceCreateInfo{
            .queue_create_info_count = queue_info_count,
            .queue_create_infos = &queue_infos,
            .enabled_extension_count = if (self.report.portability_subset) with_subset.len else without_subset.len,
            .enabled_extension_names = if (self.report.portability_subset) &with_subset else &without_subset,
        };
        var device: abi.Device = null;
        const result = entries.create_device(self.physical_device, &create_info, null, &device);
        self.ledger.noteNativeDriverCall();
        if (result != abi.SUCCESS or device == null) {
            self.fail(.device_failed, if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }
        self.device = device;
        if (!self.resolveDeviceEntries()) return false;

        self.device_entries.get_device_queue(device, self.queues.graphics_family, 0, &self.graphics_queue);
        self.device_entries.get_device_queue(device, self.queues.present_family, 0, &self.present_queue);
        self.ledger.noteNativeDriverCall();
        if (self.graphics_queue == null or self.present_queue == null) {
            self.fail(.device_failed, abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }
        return true;
    }

    fn resolveDeviceEntries(self: *Presenter) bool {
        const e = &self.device_entries;
        e.destroy_device = self.deviceProc(abi.PfnDestroyDevice, "vkDestroyDevice") orelse return self.missingDeviceEntry();
        e.device_wait_idle = self.deviceProc(abi.PfnDeviceWaitIdle, "vkDeviceWaitIdle") orelse return self.missingDeviceEntry();
        e.get_device_queue = self.deviceProc(abi.PfnGetDeviceQueue, "vkGetDeviceQueue") orelse return self.missingDeviceEntry();
        e.create_swapchain = self.deviceProc(abi.PfnCreateSwapchainKHR, "vkCreateSwapchainKHR") orelse return self.missingDeviceEntry();
        e.destroy_swapchain = self.deviceProc(abi.PfnDestroySwapchainKHR, "vkDestroySwapchainKHR") orelse return self.missingDeviceEntry();
        e.get_swapchain_images = self.deviceProc(abi.PfnGetSwapchainImagesKHR, "vkGetSwapchainImagesKHR") orelse return self.missingDeviceEntry();
        e.acquire_next_image = self.deviceProc(abi.PfnAcquireNextImageKHR, "vkAcquireNextImageKHR") orelse return self.missingDeviceEntry();
        e.queue_present = self.deviceProc(abi.PfnQueuePresentKHR, "vkQueuePresentKHR") orelse return self.missingDeviceEntry();
        e.create_command_pool = self.deviceProc(abi.PfnCreateCommandPool, "vkCreateCommandPool") orelse return self.missingDeviceEntry();
        e.destroy_command_pool = self.deviceProc(abi.PfnDestroyCommandPool, "vkDestroyCommandPool") orelse return self.missingDeviceEntry();
        e.allocate_command_buffers = self.deviceProc(abi.PfnAllocateCommandBuffers, "vkAllocateCommandBuffers") orelse return self.missingDeviceEntry();
        e.begin_command_buffer = self.deviceProc(abi.PfnBeginCommandBuffer, "vkBeginCommandBuffer") orelse return self.missingDeviceEntry();
        e.end_command_buffer = self.deviceProc(abi.PfnEndCommandBuffer, "vkEndCommandBuffer") orelse return self.missingDeviceEntry();
        e.reset_command_buffer = self.deviceProc(abi.PfnResetCommandBuffer, "vkResetCommandBuffer") orelse return self.missingDeviceEntry();
        e.create_semaphore = self.deviceProc(abi.PfnCreateSemaphore, "vkCreateSemaphore") orelse return self.missingDeviceEntry();
        e.destroy_semaphore = self.deviceProc(abi.PfnDestroySemaphore, "vkDestroySemaphore") orelse return self.missingDeviceEntry();
        e.create_fence = self.deviceProc(abi.PfnCreateFence, "vkCreateFence") orelse return self.missingDeviceEntry();
        e.destroy_fence = self.deviceProc(abi.PfnDestroyFence, "vkDestroyFence") orelse return self.missingDeviceEntry();
        e.wait_for_fences = self.deviceProc(abi.PfnWaitForFences, "vkWaitForFences") orelse return self.missingDeviceEntry();
        e.reset_fences = self.deviceProc(abi.PfnResetFences, "vkResetFences") orelse return self.missingDeviceEntry();
        e.queue_submit = self.deviceProc(abi.PfnQueueSubmit, "vkQueueSubmit") orelse return self.missingDeviceEntry();
        e.queue_wait_idle = self.deviceProc(abi.PfnQueueWaitIdle, "vkQueueWaitIdle") orelse return self.missingDeviceEntry();
        e.cmd_pipeline_barrier = self.deviceProc(abi.PfnCmdPipelineBarrier, "vkCmdPipelineBarrier") orelse return self.missingDeviceEntry();
        e.cmd_clear_color_image = self.deviceProc(abi.PfnCmdClearColorImage, "vkCmdClearColorImage") orelse return self.missingDeviceEntry();
        e.cmd_copy_buffer_to_image = self.deviceProc(abi.PfnCmdCopyBufferToImage, "vkCmdCopyBufferToImage") orelse return self.missingDeviceEntry();
        e.cmd_blit_image = self.deviceProc(abi.PfnCmdBlitImage, "vkCmdBlitImage") orelse return self.missingDeviceEntry();
        e.create_image = self.deviceProc(abi.PfnCreateImage, "vkCreateImage") orelse return self.missingDeviceEntry();
        e.destroy_image = self.deviceProc(abi.PfnDestroyImage, "vkDestroyImage") orelse return self.missingDeviceEntry();
        e.get_image_memory_requirements = self.deviceProc(abi.PfnGetImageMemoryRequirements, "vkGetImageMemoryRequirements") orelse return self.missingDeviceEntry();
        e.bind_image_memory = self.deviceProc(abi.PfnBindImageMemory, "vkBindImageMemory") orelse return self.missingDeviceEntry();
        e.create_buffer = self.deviceProc(abi.PfnCreateBuffer, "vkCreateBuffer") orelse return self.missingDeviceEntry();
        e.destroy_buffer = self.deviceProc(abi.PfnDestroyBuffer, "vkDestroyBuffer") orelse return self.missingDeviceEntry();
        e.get_buffer_memory_requirements = self.deviceProc(abi.PfnGetBufferMemoryRequirements, "vkGetBufferMemoryRequirements") orelse return self.missingDeviceEntry();
        e.allocate_memory = self.deviceProc(abi.PfnAllocateMemory, "vkAllocateMemory") orelse return self.missingDeviceEntry();
        e.free_memory = self.deviceProc(abi.PfnFreeMemory, "vkFreeMemory") orelse return self.missingDeviceEntry();
        e.bind_buffer_memory = self.deviceProc(abi.PfnBindBufferMemory, "vkBindBufferMemory") orelse return self.missingDeviceEntry();
        e.map_memory = self.deviceProc(abi.PfnMapMemory, "vkMapMemory") orelse return self.missingDeviceEntry();
        e.unmap_memory = self.deviceProc(abi.PfnUnmapMemory, "vkUnmapMemory") orelse return self.missingDeviceEntry();
        e.flush_mapped_memory_ranges = self.deviceProc(abi.PfnFlushMappedMemoryRanges, "vkFlushMappedMemoryRanges") orelse return self.missingDeviceEntry();
        return true;
    }

    fn missingDeviceEntry(self: *Presenter) bool {
        self.fail(.device_failed, abi.ERROR_EXTENSION_NOT_PRESENT);
        return false;
    }

    fn createFrameResources(self: *Presenter) bool {
        if (self.command_pool != abi.null_handle) return true;
        const entries = &self.device_entries;
        const pool_info = abi.CommandPoolCreateInfo{
            .flags = abi.COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queue_family_index = self.queues.graphics_family,
        };
        var pool: abi.CommandPool = abi.null_handle;
        if (entries.create_command_pool(self.device, &pool_info, null, &pool) != abi.SUCCESS) {
            self.fail(.frame_resources_failed, abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }
        self.command_pool = pool;

        var buffers: [frame.max_frames_in_flight]abi.CommandBuffer =
            [_]abi.CommandBuffer{null} ** frame.max_frames_in_flight;
        const allocate_info = abi.CommandBufferAllocateInfo{
            .command_pool = pool,
            .command_buffer_count = frame.max_frames_in_flight,
        };
        if (entries.allocate_command_buffers(self.device, &allocate_info, &buffers) != abi.SUCCESS) {
            self.fail(.frame_resources_failed, abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }
        for (&self.frames, 0..) |*context, index| context.command_buffer = buffers[index];
        return self.createFrameSync();
    }

    fn createFrameSync(self: *Presenter) bool {
        const entries = &self.device_entries;
        const semaphore_info = abi.SemaphoreCreateInfo{};
        // Created signalled so the first use of every slot can wait on the
        // fence unconditionally instead of special-casing the first frame.
        const fence_info = abi.FenceCreateInfo{ .flags = abi.FENCE_CREATE_SIGNALED_BIT };
        for (&self.frames) |*context| {
            if (entries.create_semaphore(self.device, &semaphore_info, null, &context.acquire_semaphore) != abi.SUCCESS or
                entries.create_semaphore(self.device, &semaphore_info, null, &context.render_finished_semaphore) != abi.SUCCESS or
                entries.create_fence(self.device, &fence_info, null, &context.in_flight_fence) != abi.SUCCESS)
            {
                self.fail(.frame_resources_failed, abi.ERROR_INITIALIZATION_FAILED);
                return false;
            }
            context.submitted = false;
        }
        return true;
    }

    /// Binary semaphores carry state across frames, and a swapchain rebuild is
    /// exactly when that state may be inconsistent — an acquire that signalled
    /// a semaphore whose wait was never submitted leaves it signalled forever,
    /// and the next wait on it hangs. Destroying and recreating them after the
    /// device is idle is the only way to know they start unsignalled.
    fn recreateFrameSync(self: *Presenter) bool {
        const entries = &self.device_entries;
        for (&self.frames) |*context| {
            if (context.acquire_semaphore != abi.null_handle) {
                entries.destroy_semaphore(self.device, context.acquire_semaphore, null);
                context.acquire_semaphore = abi.null_handle;
            }
            if (context.render_finished_semaphore != abi.null_handle) {
                entries.destroy_semaphore(self.device, context.render_finished_semaphore, null);
                context.render_finished_semaphore = abi.null_handle;
            }
            if (context.in_flight_fence != abi.null_handle) {
                entries.destroy_fence(self.device, context.in_flight_fence, null);
                context.in_flight_fence = abi.null_handle;
            }
        }
        return self.createFrameSync();
    }

    // -- swapchain --------------------------------------------------------

    pub fn createSwapchain(self: *Presenter, fallback_width: u32, fallback_height: u32) bool {
        const instance_entries = &self.instance_entries.?;
        var capabilities = abi.SurfaceCapabilitiesKHR{};
        const capability_result = instance_entries.get_surface_capabilities(
            self.physical_device,
            self.surface,
            &capabilities,
        );
        self.ledger.noteNativeDriverCall();
        if (capability_result != abi.SUCCESS) {
            self.fail(.swapchain_failed, capability_result);
            return false;
        }

        var formats: [max_surface_formats]abi.SurfaceFormatKHR =
            [_]abi.SurfaceFormatKHR{.{}} ** max_surface_formats;
        var format_count: u32 = max_surface_formats;
        _ = instance_entries.get_surface_formats(self.physical_device, self.surface, &format_count, &formats);
        self.ledger.noteNativeDriverCall();
        const format_total = @min(format_count, @as(u32, max_surface_formats));

        var modes: [max_present_modes]u32 = [_]u32{0} ** max_present_modes;
        var mode_count: u32 = max_present_modes;
        _ = instance_entries.get_surface_present_modes(self.physical_device, self.surface, &mode_count, &modes);
        self.ledger.noteNativeDriverCall();
        const mode_total = @min(mode_count, @as(u32, max_present_modes));

        const format = selection.chooseSurfaceFormat(formats[0..format_total]) orelse
            return self.rejectSwapchain(error.NoSurfaceFormat);
        const present_mode = selection.choosePresentMode(modes[0..mode_total], false) orelse
            return self.rejectSwapchain(error.NoPresentMode);
        const usage = selection.chooseImageUsage(capabilities) orelse
            return self.rejectSwapchain(error.UsageUnsupported);
        const composite_alpha = selection.chooseCompositeAlpha(capabilities) orelse
            return self.rejectSwapchain(error.NoCompositeAlpha);
        const extent = switch (selection.chooseExtent(capabilities, fallback_width, fallback_height)) {
            .not_presentable => {
                // Not a failure. The window is minimised, occluded or being
                // resized; the swapchain it had is simply unusable meanwhile.
                self.report.rejection = error.SurfaceNotPresentable;
                self.fail(.surface_not_presentable, abi.SUCCESS);
                return false;
            },
            .extent => |value| value,
        };

        const previous = self.swapchain;
        const create_info = abi.SwapchainCreateInfoKHR{
            .surface = self.surface,
            .min_image_count = selection.chooseImageCount(capabilities),
            .image_format = format.format,
            .image_color_space = format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = usage,
            .image_sharing_mode = abi.SHARING_MODE_EXCLUSIVE,
            .pre_transform = selection.choosePreTransform(capabilities),
            .composite_alpha = composite_alpha,
            .present_mode = present_mode,
            .clipped = 1,
            .old_swapchain = previous,
        };
        var swapchain: abi.SwapchainKHR = abi.null_handle;
        const result = self.device_entries.create_swapchain(self.device, &create_info, null, &swapchain);
        self.ledger.noteNativeDriverCall();
        if (result != abi.SUCCESS or swapchain == abi.null_handle) {
            self.fail(.swapchain_failed, if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }
        if (previous != abi.null_handle) {
            self.device_entries.destroy_swapchain(self.device, previous, null);
        }
        self.swapchain = swapchain;
        self.surface_format = format;
        self.extent = extent;
        self.present_mode = present_mode;
        self.image_usage = usage;

        // Called with a count first and handles second, because the driver owns
        // both the number of images and the images themselves.
        var image_count: u32 = frame.max_swapchain_images;
        const image_result = self.device_entries.get_swapchain_images(
            self.device,
            swapchain,
            &image_count,
            &self.swapchain_images,
        );
        self.ledger.noteNativeDriverCall();
        if (image_result != abi.SUCCESS and image_result != abi.INCOMPLETE) {
            self.fail(.swapchain_failed, image_result);
            return false;
        }
        self.swapchain_image_count = @min(image_count, frame.max_swapchain_images);
        if (self.swapchain_image_count == 0) {
            self.fail(.swapchain_failed, abi.ERROR_INITIALIZATION_FAILED);
            return false;
        }

        self.learnBlitSupport(format.format);
        self.ring.recreated(self.swapchain_image_count);
        self.report.swapchain_generations +|= 1;
        self.report.surface_format = format.format;
        self.report.surface_color_space = format.color_space;
        self.report.present_mode = present_mode;
        self.report.image_usage = usage;
        self.report.swapchain_image_count = self.swapchain_image_count;
        self.report.extent_width = extent.width;
        self.report.extent_height = extent.height;
        self.report.rejection = null;
        if (self.stage.retryable()) {
            self.stage = .ready;
            self.report.stage = .ready;
            self.report.last_result = abi.SUCCESS;
        }
        return true;
    }

    /// Whether the surface has any area at all, asked before any teardown.
    /// Without this an occluded window recreates its semaphores, fences and
    /// staging image once per frame for as long as it stays occluded, all to
    /// fail at the same place.
    fn surfacePresentable(self: *Presenter) bool {
        const entries = &self.instance_entries.?;
        var capabilities = abi.SurfaceCapabilitiesKHR{};
        if (entries.get_surface_capabilities(self.physical_device, self.surface, &capabilities) != abi.SUCCESS) {
            return true; // Let the real creation path report the error.
        }
        self.ledger.noteNativeDriverCall();
        return switch (selection.chooseExtent(capabilities, self.extent.width, self.extent.height)) {
            .not_presentable => false,
            .extent => true,
        };
    }

    /// What the driver advertises for a format with optimal tiling, or null
    /// when there is no physical device to ask.
    ///
    /// Rosette owns a real `VkPhysicalDevice`, so it can answer "does this host
    /// have `A2B10G10R10_SNORM_PACK32`" itself instead of taking the emulator's
    /// word for it. The null is load-bearing: an unasked format and an absent
    /// one are different facts, and a zero for both would collapse them.
    pub fn formatFeatures(self: *Presenter, format: u32) ?u32 {
        if (self.physical_device == null) return null;
        const entries = &(self.instance_entries orelse return null);
        var properties = abi.FormatProperties{};
        entries.get_format_properties(self.physical_device, format, &properties);
        self.ledger.noteNativeDriverCall();
        return properties.optimal_tiling_features;
    }

    /// Whether this format can be blitted, asked rather than assumed. A blit
    /// the driver has not advertised is a validation error, and the fallback —
    /// an exact-extent copy — is correct but cannot rescale, so which one is
    /// available has to be known before a frame arrives rather than after one
    /// fails.
    fn learnBlitSupport(self: *Presenter, format: u32) void {
        self.blit_supported = false;
        self.blit_filter = abi.FILTER_NEAREST;
        const entries = &self.instance_entries.?;
        var properties = abi.FormatProperties{};
        entries.get_format_properties(self.physical_device, format, &properties);
        self.ledger.noteNativeDriverCall();
        const optimal = properties.optimal_tiling_features;
        const source_ok = optimal & abi.FORMAT_FEATURE_BLIT_SRC_BIT != 0;
        const destination_ok = optimal & abi.FORMAT_FEATURE_BLIT_DST_BIT != 0;
        self.blit_supported = source_ok and destination_ok;
        if (self.blit_supported and optimal & abi.FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT != 0) {
            self.blit_filter = abi.FILTER_LINEAR;
        }
        self.report.blit_supported = self.blit_supported;
        self.report.blit_filter = self.blit_filter;
    }

    fn rejectSwapchain(self: *Presenter, rejection: selection.Rejection) bool {
        self.report.rejection = rejection;
        self.fail(.swapchain_failed, abi.ERROR_INITIALIZATION_FAILED);
        return false;
    }

    /// Rebuild against the surface's current state. Every outstanding
    /// submission must finish first: destroying a swapchain whose images are
    /// still referenced by in-flight work is undefined behaviour that usually
    /// surfaces as a driver crash somewhere unrelated.
    pub fn rebuild(self: *Presenter) bool {
        if (self.stage == .device_lost or self.device == null) return false;
        if (!self.surfacePresentable()) {
            self.report.rejection = error.SurfaceNotPresentable;
            self.fail(.surface_not_presentable, abi.SUCCESS);
            return false;
        }
        _ = self.device_entries.device_wait_idle(self.device);
        self.ledger.noteNativeDriverCall();
        if (!self.recreateFrameSync()) return false;
        // Sized and formatted for the previous swapchain; a rebuild may change
        // either, and a mismatched blit source is a validation error.
        self.destroyStagingImage();

        if (self.ring.health == .surface_lost) {
            // A lost surface cannot be rebuilt around: the swapchain, then the
            // surface, then a fresh surface from the same layer.
            if (self.swapchain != abi.null_handle) {
                self.device_entries.destroy_swapchain(self.device, self.swapchain, null);
                self.swapchain = abi.null_handle;
                self.swapchain_image_count = 0;
            }
            if (self.instance_entries.?.destroy_surface) |destroy| {
                destroy(self.instance, self.surface, null);
            }
            self.surface = abi.null_handle;
            if (!self.createSurface()) return false;
            self.report.surface_recreations +|= 1;
        }
        return self.createSwapchain(self.extent.width, self.extent.height);
    }

    /// Called when the window changes size or backing scale. The extent is
    /// re-read from the surface at rebuild time; these values are only the
    /// fallback for a surface that reports no fixed size.
    pub fn noteResize(self: *Presenter, width: u32, height: u32) void {
        if (width != 0) self.extent.width = width;
        if (height != 0) self.extent.height = height;
        self.ring.note(.out_of_date);
    }

    // -- frames -----------------------------------------------------------

    /// Acquire, record, submit and present one frame. Returns what happened,
    /// including the provenance class the evidence actually supported — which
    /// is not necessarily the one the source claimed.
    pub fn present(self: *Presenter, source: Source) FrameReport {
        var report = FrameReport{ .generation = self.ring.generation, .health = self.ring.health };
        if (self.stage.retryable()) {
            // The surface may have come back since the last attempt. Retrying
            // here is what turns an occlusion into a pause rather than the end
            // of the session.
            _ = self.rebuild();
        }
        if (self.stage != .ready) {
            self.last_frame = report;
            return report;
        }
        if (self.ring.health.wantsSwapchainRebuild()) {
            if (!self.rebuild()) {
                report.health = self.ring.health;
                self.last_frame = report;
                return report;
            }
            report.generation = self.ring.generation;
            report.health = self.ring.health;
        }
        if (!self.ring.health.canAcquire()) {
            report.health = self.ring.health;
            self.last_frame = report;
            return report;
        }

        const entries = &self.device_entries;
        const slot = self.ring.beginFrame();
        report.attempted = true;
        report.frame_slot = slot;
        const context = &self.frames[slot];

        if (context.submitted) {
            const fences = [_]abi.Fence{context.in_flight_fence};
            const wait = entries.wait_for_fences(self.device, 1, &fences, 1, fence_timeout_nanoseconds);
            self.ledger.noteNativeDriverCall();
            if (wait == abi.ERROR_DEVICE_LOST) return self.reportDeviceLost(report, slot);
            if (wait != abi.SUCCESS) {
                // The slot is still busy. Give the frame back rather than
                // recording work that never happened.
                self.ring.completeFrame(slot);
                report.health = self.ring.health;
                self.last_frame = report;
                return report;
            }
            context.submitted = false;
        }
        self.ring.completeFrame(slot);

        var image_index: u32 = 0;
        const acquire_result = entries.acquire_next_image(
            self.device,
            self.swapchain,
            acquire_timeout_nanoseconds,
            context.acquire_semaphore,
            abi.null_handle,
            &image_index,
        );
        self.ledger.noteNativeDriverCall();
        report.acquire_result = acquire_result;
        report.acquire_outcome = selection.classifyAcquire(acquire_result);
        self.ring.note(frame.healthAfterAcquire(report.acquire_outcome));
        if (!report.acquire_outcome.yieldsImage()) {
            if (report.acquire_outcome == .device_lost) return self.reportDeviceLost(report, slot);
            report.health = self.ring.health;
            self.last_frame = report;
            return report;
        }
        report.image_index = image_index;

        // Another frame may still be writing this image. Waiting on the frame
        // that owns it is the difference between a stable picture and one that
        // tears under load.
        if (self.ring.claimImage(image_index)) |previous_slot| {
            if (previous_slot != slot and self.frames[previous_slot].submitted) {
                const fences = [_]abi.Fence{self.frames[previous_slot].in_flight_fence};
                const wait = entries.wait_for_fences(self.device, 1, &fences, 1, fence_timeout_nanoseconds);
                self.ledger.noteNativeDriverCall();
                if (wait == abi.ERROR_DEVICE_LOST) return self.reportDeviceLost(report, slot);
            }
        }

        const reset_fences = [_]abi.Fence{context.in_flight_fence};
        _ = entries.reset_fences(self.device, 1, &reset_fences);
        self.ledger.noteNativeDriverCall();

        const wait_semaphores = [_]abi.Semaphore{context.acquire_semaphore};
        const wait_stages = [_]u32{abi.PIPELINE_STAGE_TRANSFER_BIT};
        const signal_semaphores = [_]abi.Semaphore{context.render_finished_semaphore};

        if (!self.recordFrame(context.command_buffer, self.swapchain_images[image_index], source, &report)) {
            // The acquire semaphore has been signalled. Leaving it that way
            // makes the next wait on this slot hang forever, so it is consumed
            // by an empty submission rather than abandoned.
            const drain = [_]abi.SubmitInfo{.{
                .wait_semaphore_count = 1,
                .wait_semaphores = &wait_semaphores,
                .wait_dst_stage_mask = &wait_stages,
            }};
            if (entries.queue_submit(self.graphics_queue, 1, &drain, context.in_flight_fence) == abi.SUCCESS) {
                context.submitted = true;
            } else {
                self.ring.note(.out_of_date);
            }
            report.health = self.ring.health;
            self.ring.advance();
            self.last_frame = report;
            return report;
        }

        const command_buffers = [_]abi.CommandBuffer{context.command_buffer};
        const submit_info = [_]abi.SubmitInfo{.{
            .wait_semaphore_count = 1,
            .wait_semaphores = &wait_semaphores,
            .wait_dst_stage_mask = &wait_stages,
            .command_buffer_count = 1,
            .command_buffers = &command_buffers,
            .signal_semaphore_count = 1,
            .signal_semaphores = &signal_semaphores,
        }};
        const submit_result = entries.queue_submit(self.graphics_queue, 1, &submit_info, context.in_flight_fence);
        self.ledger.noteNativeSubmission();
        report.submit_result = submit_result;
        if (submit_result != abi.SUCCESS) {
            if (submit_result == abi.ERROR_DEVICE_LOST) return self.reportDeviceLost(report, slot);
            // The semaphores are in an unknown state; a rebuild recreates them.
            self.ring.note(.out_of_date);
            report.health = self.ring.health;
            self.ring.advance();
            self.last_frame = report;
            return report;
        }
        report.submitted = true;
        context.submitted = true;

        const swapchains = [_]abi.SwapchainKHR{self.swapchain};
        const indices = [_]u32{image_index};
        const present_info = abi.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .wait_semaphores = &signal_semaphores,
            .swapchain_count = 1,
            .swapchains = &swapchains,
            .image_indices = &indices,
        };
        const present_result = entries.queue_present(self.present_queue, &present_info);
        self.ledger.noteNativePresentRequest();
        report.present_result = present_result;
        report.present_outcome = selection.classifyPresent(present_result);
        self.ring.note(frame.healthAfterPresent(report.present_outcome));
        report.presented = report.present_outcome.requestAccepted();
        if (report.present_outcome == .device_lost) return self.reportDeviceLost(report, slot);

        report.classification = self.ledger.record(.{
            .producer = switch (source) {
                .clear => .diagnostic,
                .cpu_image => |image| image.producer,
            },
            .source_ready = true,
            .native_command_recording = true,
            .native_submission = true,
            .native_presentation = true,
            .present_accepted = report.presented,
            .guest_swap_observed = switch (source) {
                .clear => false,
                .cpu_image => |image| image.guest_swap_observed,
            },
        });
        report.health = self.ring.health;
        self.ring.advance();
        self.last_frame = report;
        return report;
    }

    fn reportDeviceLost(self: *Presenter, partial: FrameReport, slot: u32) FrameReport {
        self.ring.note(.device_lost);
        self.stage = .device_lost;
        self.report.stage = .device_lost;
        self.report.last_result = abi.ERROR_DEVICE_LOST;
        self.ring.completeFrame(slot);
        var report = partial;
        report.health = .device_lost;
        self.last_frame = report;
        return report;
    }

    /// Record the transitions and the write. The acquired image arrives in an
    /// undefined layout every frame — its previous contents are not preserved —
    /// so the first barrier discards rather than reads, and the image leaves in
    /// `PRESENT_SRC_KHR` because presenting it in any other layout is invalid.
    fn recordFrame(
        self: *Presenter,
        command_buffer: abi.CommandBuffer,
        image: abi.Image,
        source: Source,
        report: *FrameReport,
    ) bool {
        const entries = &self.device_entries;
        _ = entries.reset_command_buffer(command_buffer, 0);
        const begin_info = abi.CommandBufferBeginInfo{ .flags = abi.COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
        if (entries.begin_command_buffer(command_buffer, &begin_info) != abi.SUCCESS) return false;

        const range = abi.ImageSubresourceRange{};
        const to_transfer = [_]abi.ImageMemoryBarrier{.{
            .src_access_mask = 0,
            .dst_access_mask = abi.ACCESS_TRANSFER_WRITE_BIT,
            .old_layout = abi.IMAGE_LAYOUT_UNDEFINED,
            .new_layout = abi.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .image = image,
            .subresource_range = range,
        }};
        entries.cmd_pipeline_barrier(
            command_buffer,
            abi.PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            abi.PIPELINE_STAGE_TRANSFER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &to_transfer,
        );

        switch (source) {
            .clear => |colour| {
                const clear_value = abi.ClearColorValue{ .float32 = colour };
                const ranges = [_]abi.ImageSubresourceRange{range};
                entries.cmd_clear_color_image(
                    command_buffer,
                    image,
                    abi.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    &clear_value,
                    1,
                    &ranges,
                );
                report.composite = .clear;
                report.destination = .{ .width = self.extent.width, .height = self.extent.height };
            },
            .cpu_image => |cpu| {
                if (!self.uploadCpuImage(command_buffer, image, cpu, report)) {
                    _ = entries.end_command_buffer(command_buffer);
                    return false;
                }
                report.source_copied = true;
            },
        }

        const to_present = [_]abi.ImageMemoryBarrier{.{
            .src_access_mask = abi.ACCESS_TRANSFER_WRITE_BIT,
            .dst_access_mask = abi.ACCESS_MEMORY_READ_BIT,
            .old_layout = abi.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .new_layout = abi.IMAGE_LAYOUT_PRESENT_SRC_KHR,
            .image = image,
            .subresource_range = range,
        }};
        entries.cmd_pipeline_barrier(
            command_buffer,
            abi.PIPELINE_STAGE_TRANSFER_BIT,
            abi.PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &to_present,
        );
        return entries.end_command_buffer(command_buffer) == abi.SUCCESS;
    }

    /// Put a CPU frame onto the acquired image, scaling, letterboxing and
    /// flipping as the descriptor requires.
    ///
    /// Two routes. When the source already matches the swapchain exactly and is
    /// the right way up, the buffer is copied straight into the acquired image.
    /// Otherwise it goes through a staging image and `vkCmdBlitImage`, which is
    /// the only transfer operation that can rescale — and, by giving the source
    /// corners in descending order, mirror. A blit the driver has not said it
    /// supports for this format is not attempted.
    fn uploadCpuImage(
        self: *Presenter,
        command_buffer: abi.CommandBuffer,
        image: abi.Image,
        cpu: CpuImage,
        report: *FrameReport,
    ) bool {
        const layout = selection.stagingLayout(cpu.format, cpu.width, cpu.height) orelse return false;
        if (!selection.channelOrderMatches(cpu.format, self.surface_format.format)) return false;
        const source_pitch = if (cpu.row_pitch_bytes == 0) layout.row_pitch_bytes else cpu.row_pitch_bytes;
        if (source_pitch < layout.row_pitch_bytes) return false;
        if (cpu.pixels.len < source_pitch * cpu.height) return false;
        if (layout.total_bytes > max_staging_bytes) return false;
        if (!self.ensureStaging(layout.total_bytes)) return false;

        const mapped = self.staging.mapped orelse return false;
        // Row by row: the producer's pitch need not equal the tightly packed
        // pitch the copy region describes, and reading a padded buffer as
        // packed skews the picture diagonally rather than failing.
        const width_bytes: usize = @intCast(layout.row_pitch_bytes);
        var row: u32 = 0;
        while (row < cpu.height) : (row += 1) {
            const source_offset: usize = @intCast(@as(u64, row) * source_pitch);
            const destination_offset: usize = @intCast(@as(u64, row) * layout.row_pitch_bytes);
            @memcpy(
                mapped[destination_offset .. destination_offset + width_bytes],
                cpu.pixels[source_offset .. source_offset + width_bytes],
            );
        }
        if (!self.staging.coherent) {
            const ranges = [_]abi.MappedMemoryRange{.{
                .memory = self.staging.memory,
                .offset = 0,
                .size = abi.WHOLE_SIZE,
            }};
            _ = self.device_entries.flush_mapped_memory_ranges(self.device, 1, &ranges);
            self.ledger.noteNativeDriverCall();
        }

        const exact = cpu.width == self.extent.width and cpu.height == self.extent.height;
        if (exact and cpu.orientation == .top_down) {
            self.copyBufferToImage(command_buffer, image, cpu.width, cpu.height, layout.buffer_row_length_texels);
            report.composite = .direct_copy;
            report.destination = .{ .width = cpu.width, .height = cpu.height };
            return true;
        }
        if (!self.blit_supported) return false;

        const fitted = frame_source.computeFit(
            cpu.width,
            cpu.height,
            self.extent.width,
            self.extent.height,
            cpu.fit,
        ) orelse return false;
        if (!self.ensureStagingImage(cpu.width, cpu.height)) return false;

        const entries = &self.device_entries;
        const range = abi.ImageSubresourceRange{};

        // The bars a letterboxed frame leaves would otherwise hold whatever the
        // presentation engine last put in this image.
        if (!fitted.covers(self.extent.width, self.extent.height)) {
            const black = abi.ClearColorValue{ .float32 = .{ 0, 0, 0, 1 } };
            const ranges = [_]abi.ImageSubresourceRange{range};
            entries.cmd_clear_color_image(
                command_buffer,
                image,
                abi.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                &black,
                1,
                &ranges,
            );
        }

        const staging_to_dst = [_]abi.ImageMemoryBarrier{.{
            .src_access_mask = 0,
            .dst_access_mask = abi.ACCESS_TRANSFER_WRITE_BIT,
            .old_layout = abi.IMAGE_LAYOUT_UNDEFINED,
            .new_layout = abi.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .image = self.staging_image.image,
            .subresource_range = range,
        }};
        entries.cmd_pipeline_barrier(
            command_buffer,
            abi.PIPELINE_STAGE_TRANSFER_BIT,
            abi.PIPELINE_STAGE_TRANSFER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &staging_to_dst,
        );
        self.copyBufferToImage(
            command_buffer,
            self.staging_image.image,
            cpu.width,
            cpu.height,
            layout.buffer_row_length_texels,
        );
        const staging_to_src = [_]abi.ImageMemoryBarrier{.{
            .src_access_mask = abi.ACCESS_TRANSFER_WRITE_BIT,
            .dst_access_mask = abi.ACCESS_TRANSFER_READ_BIT,
            .old_layout = abi.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .new_layout = abi.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .image = self.staging_image.image,
            .subresource_range = range,
        }};
        entries.cmd_pipeline_barrier(
            command_buffer,
            abi.PIPELINE_STAGE_TRANSFER_BIT,
            abi.PIPELINE_STAGE_TRANSFER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &staging_to_src,
        );

        // A bottom-up source is mirrored by naming the source corners in
        // descending order on the y axis, which costs nothing and needs no
        // second pass.
        const top: i32 = if (cpu.orientation == .bottom_up) @intCast(cpu.height) else 0;
        const bottom: i32 = if (cpu.orientation == .bottom_up) 0 else @intCast(cpu.height);
        const regions = [_]abi.ImageBlit{.{
            .src_subresource = .{},
            .src_offsets = .{
                .{ .x = 0, .y = top, .z = 0 },
                .{ .x = @intCast(cpu.width), .y = bottom, .z = 1 },
            },
            .dst_subresource = .{},
            .dst_offsets = .{
                .{ .x = fitted.x, .y = fitted.y, .z = 0 },
                .{ .x = fitted.right(), .y = fitted.bottom(), .z = 1 },
            },
        }};
        entries.cmd_blit_image(
            command_buffer,
            self.staging_image.image,
            abi.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            image,
            abi.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &regions,
            self.blit_filter,
        );
        report.composite = .blit;
        report.destination = fitted;
        return true;
    }

    fn copyBufferToImage(
        self: *Presenter,
        command_buffer: abi.CommandBuffer,
        image: abi.Image,
        width: u32,
        height: u32,
        row_length_texels: u32,
    ) void {
        const regions = [_]abi.BufferImageCopy{.{
            .buffer_offset = 0,
            // Counted in texels: a byte count here reads four times too far.
            .buffer_row_length = row_length_texels,
            .buffer_image_height = height,
            .image_subresource = .{},
            .image_extent = .{ .width = width, .height = height, .depth = 1 },
        }};
        self.device_entries.cmd_copy_buffer_to_image(
            command_buffer,
            self.staging.buffer,
            image,
            abi.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &regions,
        );
    }

    fn ensureStagingImage(self: *Presenter, width: u32, height: u32) bool {
        if (self.staging_image.image != abi.null_handle and
            self.staging_image.width == width and
            self.staging_image.height == height and
            self.staging_image.format == self.surface_format.format) return true;
        self.destroyStagingImage();

        const entries = &self.device_entries;
        const create_info = abi.ImageCreateInfo{
            .image_type = abi.IMAGE_TYPE_2D,
            .format = self.surface_format.format,
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = abi.SAMPLE_COUNT_1_BIT,
            .tiling = abi.IMAGE_TILING_OPTIMAL,
            .usage = abi.IMAGE_USAGE_TRANSFER_DST_BIT | abi.IMAGE_USAGE_TRANSFER_SRC_BIT,
            .initial_layout = abi.IMAGE_LAYOUT_UNDEFINED,
        };
        var created: abi.Image = abi.null_handle;
        if (entries.create_image(self.device, &create_info, null, &created) != abi.SUCCESS) return false;

        var requirements = abi.MemoryRequirements{};
        entries.get_image_memory_requirements(self.device, created, &requirements);
        const type_index = selection.selectMemoryType(
            self.memory_properties,
            requirements.memory_type_bits,
            abi.MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        ) orelse selection.selectMemoryType(self.memory_properties, requirements.memory_type_bits, 0) orelse {
            entries.destroy_image(self.device, created, null);
            self.report.rejection = error.NoMemoryType;
            return false;
        };
        const allocate_info = abi.MemoryAllocateInfo{
            .allocation_size = requirements.size,
            .memory_type_index = type_index,
        };
        var memory: abi.DeviceMemory = abi.null_handle;
        if (entries.allocate_memory(self.device, &allocate_info, null, &memory) != abi.SUCCESS) {
            entries.destroy_image(self.device, created, null);
            return false;
        }
        if (entries.bind_image_memory(self.device, created, memory, 0) != abi.SUCCESS) {
            entries.free_memory(self.device, memory, null);
            entries.destroy_image(self.device, created, null);
            return false;
        }
        self.staging_image = .{
            .image = created,
            .memory = memory,
            .width = width,
            .height = height,
            .format = self.surface_format.format,
        };
        self.ledger.noteNativeDriverCall();
        return true;
    }

    fn destroyStagingImage(self: *Presenter) void {
        if (self.device == null) return;
        const entries = &self.device_entries;
        if (self.staging_image.image != abi.null_handle) entries.destroy_image(self.device, self.staging_image.image, null);
        if (self.staging_image.memory != abi.null_handle) entries.free_memory(self.device, self.staging_image.memory, null);
        self.staging_image = .{};
    }

    fn ensureStaging(self: *Presenter, bytes: u64) bool {
        if (self.staging.capacity >= bytes and self.staging.mapped != null) return true;
        self.destroyStaging();

        const entries = &self.device_entries;
        const buffer_info = abi.BufferCreateInfo{
            .size = bytes,
            .usage = abi.BUFFER_USAGE_TRANSFER_SRC_BIT,
        };
        var buffer: abi.Buffer = abi.null_handle;
        if (entries.create_buffer(self.device, &buffer_info, null, &buffer) != abi.SUCCESS) return false;

        var requirements = abi.MemoryRequirements{};
        entries.get_buffer_memory_requirements(self.device, buffer, &requirements);
        const coherent_flags = abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT | abi.MEMORY_PROPERTY_HOST_COHERENT_BIT;
        var coherent = true;
        var type_index = selection.selectMemoryType(self.memory_properties, requirements.memory_type_bits, coherent_flags);
        if (type_index == null) {
            // Without coherency every upload needs an explicit flush, which is
            // why the distinction is kept rather than assumed.
            coherent = false;
            type_index = selection.selectMemoryType(
                self.memory_properties,
                requirements.memory_type_bits,
                abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT,
            );
        }
        const chosen = type_index orelse {
            entries.destroy_buffer(self.device, buffer, null);
            self.report.rejection = error.NoMemoryType;
            return false;
        };

        const allocate_info = abi.MemoryAllocateInfo{
            .allocation_size = requirements.size,
            .memory_type_index = chosen,
        };
        var memory: abi.DeviceMemory = abi.null_handle;
        if (entries.allocate_memory(self.device, &allocate_info, null, &memory) != abi.SUCCESS) {
            entries.destroy_buffer(self.device, buffer, null);
            return false;
        }
        if (entries.bind_buffer_memory(self.device, buffer, memory, 0) != abi.SUCCESS) {
            entries.free_memory(self.device, memory, null);
            entries.destroy_buffer(self.device, buffer, null);
            return false;
        }
        var mapped: ?*anyopaque = null;
        if (entries.map_memory(self.device, memory, 0, abi.WHOLE_SIZE, 0, &mapped) != abi.SUCCESS or mapped == null) {
            entries.free_memory(self.device, memory, null);
            entries.destroy_buffer(self.device, buffer, null);
            return false;
        }
        self.staging = .{
            .buffer = buffer,
            .memory = memory,
            .mapped = @ptrCast(mapped),
            .capacity = requirements.size,
            .coherent = coherent,
        };
        self.ledger.noteNativeDriverCall();
        return true;
    }

    fn destroyStaging(self: *Presenter) void {
        if (self.device == null) return;
        const entries = &self.device_entries;
        if (self.staging.mapped != null) entries.unmap_memory(self.device, self.staging.memory);
        if (self.staging.buffer != abi.null_handle) entries.destroy_buffer(self.device, self.staging.buffer, null);
        if (self.staging.memory != abi.null_handle) entries.free_memory(self.device, self.staging.memory, null);
        self.staging = .{};
    }

    /// Torn down in dependency order: frame resources, then the swapchain, then
    /// the device, then the surface, then the instance. The surface must not
    /// outlive the instance that parents it, and neither may outlive the
    /// `CAMetalLayer` they point at — which is why the caller releases the
    /// window only after this returns.
    pub fn shutdown(self: *Presenter) void {
        const entries = &self.device_entries;
        if (self.device != null and self.stage != .device_lost) {
            _ = entries.device_wait_idle(self.device);
            self.destroyStaging();
            self.destroyStagingImage();
            for (&self.frames) |*context| {
                if (context.acquire_semaphore != abi.null_handle) {
                    entries.destroy_semaphore(self.device, context.acquire_semaphore, null);
                }
                if (context.render_finished_semaphore != abi.null_handle) {
                    entries.destroy_semaphore(self.device, context.render_finished_semaphore, null);
                }
                if (context.in_flight_fence != abi.null_handle) {
                    entries.destroy_fence(self.device, context.in_flight_fence, null);
                }
                context.* = .{};
            }
            if (self.command_pool != abi.null_handle) {
                entries.destroy_command_pool(self.device, self.command_pool, null);
            }
            if (self.swapchain != abi.null_handle) {
                entries.destroy_swapchain(self.device, self.swapchain, null);
            }
            entries.destroy_device(self.device, null);
        }
        self.device = null;
        self.command_pool = abi.null_handle;
        self.swapchain = abi.null_handle;
        self.swapchain_image_count = 0;
        self.staging = .{};
        self.staging_image = .{};

        if (self.instance_entries) |instance_entries| {
            if (self.surface != abi.null_handle) {
                if (instance_entries.destroy_surface) |destroy| destroy(self.instance, self.surface, null);
            }
            if (self.instance != null) {
                if (instance_entries.destroy_instance) |destroy| destroy(self.instance, null);
            }
        }
        self.surface = abi.null_handle;
        self.instance = null;
        self.physical_device = null;
        self.graphics_queue = null;
        self.present_queue = null;
        self.instance_entries = null;
        if (self.stage != .device_lost) self.stage = .unstarted;
        self.report.stage = self.stage;
    }

    fn fail(self: *Presenter, stage: Stage, result: abi.Result) void {
        self.stage = stage;
        self.report.stage = stage;
        self.report.last_result = result;
    }

    // -- what the rest of the runtime is allowed to believe ------------------

    /// The per-stage fidelity actually achieved. A stage that was never reached
    /// is `unreached` rather than `modelled`: not getting there says nothing
    /// about what the runtime would have done in its place.
    pub fn declareInto(self: *const Presenter, contract: *forwarding.Contract) void {
        if (self.instance != null) contract.declare(.instance, .native);
        if (self.surface != abi.null_handle) contract.declare(.surface, .native);
        if (self.physical_device != null) contract.declare(.physical_device, .native);
        if (self.device != null) {
            contract.declare(.logical_device, .native);
            if (self.graphics_queue != null) contract.declare(.queue, .native);
        }
        if (self.swapchain != abi.null_handle) {
            contract.declare(.swapchain, .native);
            if (self.swapchain_image_count != 0) contract.declare(.swapchain_images, .native);
        }
        if (self.command_pool != abi.null_handle) contract.declare(.command_recording, .native);
        if (self.ledger.native_submissions != 0) contract.declare(.queue_submission, .native);
        if (self.ledger.native_present_requests != 0) contract.declare(.presentation, .native);
    }

    /// The truthful boundary description for the backend-neutral handshake.
    pub fn boundary(self: *const Presenter) backend.VulkanBoundary {
        return .{
            .instance_native = self.instance != null,
            .surface_native = self.surface != abi.null_handle,
            .physical_adapter_native = self.physical_device != null,
            .logical_device_native = self.device != null,
            .graphics_queue_native = self.graphics_queue != null,
            .transfer_queue_native = self.graphics_queue != null,
            .host_visible_memory_native = self.staging.memory != abi.null_handle,
            .buffer_native = self.staging.buffer != abi.null_handle,
            .image_native = self.swapchain_image_count != 0,
            .command_buffer_native = self.command_pool != abi.null_handle,
            .barriers_native = self.command_pool != abi.null_handle,
            .synchronization_native = self.frames[0].in_flight_fence != abi.null_handle,
            .swapchain_native = self.swapchain != abi.null_handle,
            .presentation_native = self.ledger.native_present_requests != 0,
            .adapter_name = if (self.report.adapter_name_length != 0)
                self.report.adapterName()
            else
                "Vulkan backend (discovery pending)",
        };
    }

    /// Why the window is not showing guest pixels, in the order a reader should
    /// investigate. Never answers "unknown".
    pub fn blockingReason(self: *const Presenter) []const u8 {
        if (self.stage != .ready) return self.stage.label();
        if (self.ledger.guest_output_frames_presented != 0) {
            return "guest-derived frames are reaching the display";
        }
        if (self.ledger.native_present_requests == 0) {
            return "the native path is ready but no frame has been presented through it yet";
        }
        return self.ledger.displayNote();
    }
};

test "an unstarted presenter claims nothing and says why" {
    var presenter = Presenter{};
    var contract = forwarding.Contract{};
    presenter.declareInto(&contract);
    try std.testing.expect(!contract.pixelsAreGuestOutput());
    try std.testing.expectEqual(forwarding.Stage.logical_device, contract.firstNonNativePixelStage().?);
    try std.testing.expect(!presenter.boundary().presentation_native);
    try std.testing.expectEqualStrings(Stage.unstarted.label(), presenter.blockingReason());
}

// The point of the rewrite: with a native chain the contract reports guest
// output, and without one it names the first stage that is missing.
test "a fully native chain is the only way the contract reports guest output" {
    var presenter = Presenter{};
    var placeholder: u8 = 0;
    presenter.instance = &placeholder;
    presenter.surface = 1;
    presenter.physical_device = &placeholder;
    presenter.device = &placeholder;
    presenter.graphics_queue = &placeholder;
    presenter.swapchain = 2;
    presenter.swapchain_image_count = 3;
    presenter.command_pool = 3;

    var partial = forwarding.Contract{};
    presenter.declareInto(&partial);
    try std.testing.expectEqual(forwarding.Stage.queue_submission, partial.firstNonNativePixelStage().?);

    presenter.ledger.noteNativeSubmission();
    presenter.ledger.noteNativePresentRequest();
    var complete = forwarding.Contract{};
    presenter.declareInto(&complete);
    try std.testing.expect(complete.pixelsAreGuestOutput());
}

// A native surface over a synthetic device was the old configuration, and it
// must not report a device, a queue or a swapchain.
test "the boundary reports only the stages that actually exist" {
    var presenter = Presenter{};
    var placeholder: u8 = 0;
    presenter.instance = &placeholder;
    presenter.surface = 1;
    const early = presenter.boundary();
    try std.testing.expect(early.instance_native);
    try std.testing.expect(early.surface_native);
    try std.testing.expect(!early.physical_adapter_native);
    try std.testing.expect(!early.logical_device_native);
    try std.testing.expect(!early.swapchain_native);
    try std.testing.expect(!early.presentation_native);
    try std.testing.expect(!early.describe().provided.contains(.presentation));
}

test "a presenter that is not ready refuses to record a frame" {
    var presenter = Presenter{};
    const report = presenter.present(.{ .clear = .{ 0, 0, 0, 1 } });
    try std.testing.expect(!report.attempted);
    try std.testing.expect(!report.presented);
    try std.testing.expectEqual(provenance.Classification.rejected, report.classification);
    try std.testing.expectEqual(@as(u64, 0), presenter.ledger.diagnostic_frames_presented);
}

test "a resolver with no lookup yields no instance" {
    var presenter = Presenter{};
    const stage = presenter.bringUp(.{}, 0, 1280, 720);
    try std.testing.expectEqual(Stage.loader_unavailable, stage);
    try std.testing.expectEqual(abi.ERROR_INITIALIZATION_FAILED, presenter.report.last_result);
    try std.testing.expect(std.mem.indexOf(u8, presenter.blockingReason(), "vkGetInstanceProcAddr") != null);
}

test "a lost device is terminal and bring-up will not restart it" {
    var presenter = Presenter{};
    presenter.stage = .device_lost;
    try std.testing.expectEqual(Stage.device_lost, presenter.bringUp(.{}, 0, 1280, 720));
    try std.testing.expect(!presenter.rebuild());
}

// A window that is minimised comes back. Treating a zero-area surface as a
// failed swapchain left the presenter permanently dead behind a window that
// looked fine — which is the "permanent OUT_OF_DATE loop" the validation plan
// exists to catch.
test "an occluded surface is retryable and a lost device is not" {
    try std.testing.expect(Stage.surface_not_presentable.retryable());
    try std.testing.expect(Stage.swapchain_failed.retryable());
    try std.testing.expect(!Stage.device_lost.retryable());
    try std.testing.expect(!Stage.loader_unavailable.retryable());
    try std.testing.expect(!Stage.ready.retryable());
    try std.testing.expect(std.mem.indexOf(u8, Stage.surface_not_presentable.label(), "backpressure") != null);
}

test "every stage explains what it means" {
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        try std.testing.expect(stage.label().len > 0);
    }
}
