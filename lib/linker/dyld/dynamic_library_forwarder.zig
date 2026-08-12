const std = @import("std");
const builtin = @import("builtin");
const guest_sleep = @import("scheduler").guest_sleep;
const rosette_gpu = @import("gpu");
const guest_memory_geometry = @import("guest_memory_geometry.zig");
const machoCapturePrint = @import("event_log").machoCapturePrint;

const RTLD_LAZY: c_int = 0x1;
const RTLD_LOCAL: c_int = 0x4;
const MAX_LIBRARIES = 16;
const MAX_GUEST_LIBRARIES = 32;
pub const MAX_GUEST_SYMBOLS = 256;
const GUEST_LIBRARY_HANDLE_BASE: u64 = 0xFFFF_FC00_0000_0000;
pub const GUEST_SYMBOL_THUNK_BASE: u64 = 0xFFFF_FB00_0000_0000;

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
    queue_present,
    create_device_object,
    allocate_command_buffers,
    allocate_descriptor_sets,
    allocate_memory,
    map_memory,
    bind_image_memory,
    bind_buffer_memory,
    get_memory_requirements,
    create_graphics_pipelines,
    destroy_device_object,
    device_success,
    device_void,
    @"opaque",
};

const GuestSymbol = struct {
    token: u64 = 0,
    library_token: u64 = 0,
    kind: GuestSymbolKind = .@"opaque",
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
    // handles. This is sufficient for Vulkan initialization discovery, but it
    // cannot put pixels in the CAMetalLayer.
    synthetic_swapchain_ready,
    // Rosette's own native Vulkan presenter owns a real device, a real
    // swapchain and real images on the window's CAMetalLayer, and frames reach
    // the display through vkQueueSubmit and vkQueuePresentKHR. This says
    // nothing about the guest's Vulkan objects, which remain modelled: it means
    // the host half of the path is no longer synthetic.
    native_drawable_ready,
    failed,
};

const VK_SYNTHETIC_DEVICE: u64 = 0xFFFF_F600_0000_0021;
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
};

// Offsets into VkImageCreateInfo and VkBufferCreateInfo. Read from the guest's
// own structures rather than guessed, because the extent and format they carry
// are the only description of what the guest intends to draw into.
const VK_IMAGE_CREATE_INFO_FORMAT_OFFSET: u64 = 24;
const VK_IMAGE_CREATE_INFO_EXTENT_OFFSET: u64 = 28;
const VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET: u64 = 40;
const VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET: u64 = 44;
const VK_IMAGE_CREATE_INFO_TILING_OFFSET: u64 = 52;
const VK_IMAGE_CREATE_INFO_USAGE_OFFSET: u64 = 56;
const VK_IMAGE_CREATE_INFO_SIZE: u64 = 88;
const VK_BUFFER_CREATE_INFO_SIZE_OFFSET: u64 = 24;
const VK_BUFFER_CREATE_INFO_USAGE_OFFSET: u64 = 32;
const VK_BUFFER_CREATE_INFO_SIZE: u64 = 56;

const MAX_VULKAN_RESOURCES = 128;
const VulkanResourceKind = enum { image, buffer };

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
    vulkan_device_void_calls: u64 = 0,
    vulkan_modeled_command_calls: u64 = 0,
    vulkan_surface_capability_queries: u64 = 0,
    vulkan_memory_allocations: u64 = 0,
    vulkan_memory_maps: u64 = 0,
    vulkan_memory_map_reuses: u64 = 0,
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
    native_vulkan_failures: u64 = 0,
    native_vulkan_loader_attempts: u64 = 0,
    native_vulkan_loader_failures: u64 = 0,
    gpu_runtime: rosette_gpu.Runtime = .{},
    gpu_handshake_response: rosette_gpu.HandshakeResponse = .{},
    gpu_handshake_updates: u64 = 0,
    gpu_health_fingerprint: u64 = std.math.maxInt(u64),
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
    frame_source_absence_logged: ?rosette_gpu.FrameAbsence = null,
    vulkan_swapchain_image_handles: [4]u64 = [_]u64{0} ** 4,
    vulkan_swapchain_image_count: u32 = 0,
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
            .enumerate_instance_extensions => state.regs.rax = enumerateInstanceExtensions(state),
            .enumerate_instance_layers => state.regs.rax = enumerateEmpty(state, state.regs.rdi),
            .enumerate_instance_version => state.regs.rax = writeApiVersion(state, state.regs.rdi),
            .create_instance => state.regs.rax = createHandle(state, state.regs.rdx, 0xFFFF_F600_0000_0001, "Vulkan instance"),
            .enumerate_physical_devices => state.regs.rax = enumerateHandle(state, state.regs.rsi, state.regs.rdx, 0xFFFF_F600_0000_0011, "Vulkan physical device"),
            .enumerate_device_extensions => state.regs.rax = enumerateDeviceExtensions(state),
            .get_physical_device_features => writePhysicalDeviceFeatures(state, state.regs.rsi),
            .get_physical_device_format_properties => writeFormatProperties(state, state.regs.rdx),
            .get_physical_device_memory_properties => writeMemoryProperties(state, state.regs.rsi),
            .get_physical_device_properties => writePhysicalDeviceProperties(state, state.regs.rsi),
            .get_physical_device_queue_families => writeQueueFamilies(state),
            .get_physical_device_features2 => writePhysicalDeviceFeatures2(state, state.regs.rsi),
            .get_physical_device_memory_properties2 => writeMemoryProperties2(state, state.regs.rsi),
            .get_physical_device_properties2 => writePhysicalDeviceProperties2(state, state.regs.rsi),
            .create_device => state.regs.rax = self.createLogicalDevice(state, state.regs.rcx),
            .get_device_queue => state.regs.rax = self.writeDeviceQueue(state, state.regs.rcx, "vkGetDeviceQueue"),
            .get_device_queue2 => state.regs.rax = self.writeDeviceQueue(state, state.regs.rdx, "vkGetDeviceQueue2"),
            .create_metal_surface => state.regs.rax = self.createMetalSurface(state, entry.library_token, state.regs.rdi, state.regs.rsi, state.regs.rcx),
            .get_surface_capabilities => {
                self.vulkan_surface_capability_queries +|= 1;
                state.regs.rax = writeSurfaceCapabilities(state, state.regs.rdx);
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
            .get_surface_formats => state.regs.rax = enumerateSurfaceFormats(state),
            .get_surface_present_modes => state.regs.rax = enumerateSurfacePresentModes(state),
            .get_surface_support => state.regs.rax = writeBoolResult(state, state.regs.rcx, true),
            .destroy_surface => {
                self.destroyNativeSurface();
                state.regs.rax = 0;
            },
            .destroy_instance => {
                self.destroyNativeVulkanObjects();
                state.regs.rax = 0;
            },
            .destroy_device => state.regs.rax = 0,
            .create_swapchain => state.regs.rax = self.createSwapchain(state, state.regs.rdi, state.regs.rsi, state.regs.rcx),
            .destroy_swapchain => state.regs.rax = 0,
            .get_swapchain_images => state.regs.rax = self.enumerateSwapchainImages(state),
            .acquire_next_image => state.regs.rax = self.acquireNextImage(state, state.regs.r9),
            .queue_submit => state.regs.rax = self.queueSubmit(),
            .queue_present => state.regs.rax = self.queuePresent(state),
            .create_device_object => state.regs.rax = self.createVulkanObject(state, state.regs.rsi, state.regs.rcx, entry.name[0..entry.name_length]),
            .bind_image_memory => state.regs.rax = self.bindResourceMemory(state.regs.rsi, state.regs.rdx, state.regs.rcx, .image),
            .bind_buffer_memory => state.regs.rax = self.bindResourceMemory(state.regs.rsi, state.regs.rdx, state.regs.rcx, .buffer),
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
            .create_graphics_pipelines => state.regs.rax = self.createMultipleVulkanObjects(state, state.regs.rdx, state.regs.r9, entry.name[0..entry.name_length]),
            .destroy_device_object => state.regs.rax = 0,
            .device_success => state.regs.rax = 0,
            .device_void => {
                self.vulkan_device_void_calls +|= 1;
                if (std.mem.startsWith(u8, entry.name[0..entry.name_length], "vkCmd")) {
                    self.vulkan_modeled_command_calls +|= 1;
                    if (self.vulkan_modeled_command_calls == 1) {
                        machoCapturePrint(
                            "macho-processor: Vulkan forwarding boundary: first modeled command={s}; Metal surface is native, but device/command/swapchain submission remains synthetic\n",
                            .{entry.name[0..entry.name_length]},
                        );
                    }
                }
                state.regs.rax = 0;
            },
            // A non-null lookup remains useful for capability discovery,
            // but calling an untyped ARM64 function through x86 registers
            // is unsafe. Keep it contained until its Vulkan ABI signature
            // has an explicit bridge.
            .@"opaque" => {
                self.guest_opaque_calls +|= 1;
                machoCapturePrint(
                    "macho-processor: Vulkan ABI gap: called unmodeled proc {s} (token=0x{x}, call={d}); returning zero\n",
                    .{ entry.name[0..entry.name_length], entry.token, entry.calls },
                );
                state.regs.rax = 0;
            },
        }
        return true;
    }

    fn nextVulkanObject(self: *Forwarder) u64 {
        const result = self.next_vulkan_object;
        self.next_vulkan_object +%= 0x10;
        return result;
    }

    fn createVulkanObject(self: *Forwarder, state: anytype, create_info: u64, output: u64, name: []const u8) u64 {
        if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
        const handle = self.nextVulkanObject();
        state.write64(output, handle);
        registerOpaqueHandle(state, handle, name);
        machoCapturePrint("macho-processor: Vulkan object created: {s} handle=0x{x} output=0x{x}\n", .{ name, handle, output });
        // Deliberately no frame here. An ordinary vkCreateImage is a resource
        // event: the image may be a texture, a depth buffer, a staging image or
        // a render target, it need not have presentation usage, it does not
        // belong to a swapchain, it may not be bound to memory, and it may hold
        // no pixels. Treating it as a presentation trigger produced a frame
        // whose only relationship to the guest was that the guest had allocated
        // something.
        //
        // The description is worth keeping even so. An image the guest later
        // fills and presents is the only route to authentic pixels, and its
        // extent and format exist nowhere but in this structure.
        if (std.mem.eql(u8, name, "vkCreateImage")) self.recordImage(state, handle, create_info);
        if (std.mem.eql(u8, name, "vkCreateBuffer")) self.recordBuffer(state, handle, create_info);
        return 0;
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
        const record = self.findResource(resource) orelse return 0;
        record.memory = memory;
        record.memory_offset = offset;
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

    /// Answer with a size the resource actually needs.
    ///
    /// This previously replied 4096 bytes for everything. A 1280×720 image was
    /// therefore backed by a 4 KiB allocation, so a guest that filled it wrote
    /// 3.5 MB past its own allocation — and an image that cannot hold a frame
    /// can never become one, which puts a floor under every attempt to find
    /// authentic pixels.
    fn writeResourceMemoryRequirements(self: *Forwarder, state: anytype, resource: u64, output: u64) u64 {
        const record = self.findResource(resource);
        const size = if (record) |found| found.size_bytes else 0;
        return writeMemoryRequirements(state, output, size);
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

    fn writeDeviceQueue(self: *Forwarder, state: anytype, output: u64, name: []const u8) u64 {
        if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
        const queue = 0xFFFF_F600_0000_0031;
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

    fn destroyNativeVulkanObjects(self: *Forwarder) void {
        // The presenter owns a device, a swapchain and a surface of its own,
        // all parented by an instance in this same library. It has to go first,
        // and in its own dependency order.
        self.native_presenter.shutdown();
        self.destroyNativeSurface();
        const instance = self.native_vulkan_instance orelse return;
        if (self.guestLibrary(self.native_vulkan_library_token)) |library| {
            if (dlsym(library, "vkDestroyInstance")) |destroy_address| {
                const destroy_instance: PfnVkDestroyInstance = @ptrCast(@alignCast(destroy_address));
                destroy_instance(instance, null);
            }
        }
        self.native_vulkan_instance = null;
        self.native_vulkan_library_token = 0;
        self.native_vulkan_surface = 0;
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
        const native_surface = self.createNativeMetalSurface(state, library_token);
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
                state.noteNativeVulkanSurfaceBound(layer, VK_SYNTHETIC_SURFACE, native_surface.surface);
            }
            if (self.vulkan_metal_surfaces_created == 1) {
                machoCapturePrint(
                    "macho-processor: Vulkan milestone: metal_surface_created guest_surface=0x{x} (MODELLED) layer=0x{x} output=0x{x} gtk_idle_source={d}\n",
                    .{ VK_SYNTHETIC_SURFACE, layer, output, state.active_idle_source },
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
        const failure_reason: ?[]const u8 = if (self.vulkan_logical_devices_created == 0)
            "logical_device_not_created"
        else if (device != VK_SYNTHETIC_DEVICE)
            "unknown_device"
        else if (self.vulkan_metal_surfaces_created == 0)
            "metal_surface_not_created"
        else if (info == null)
            "unmapped_create_info"
        else if (s_type != VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR)
            "unexpected_s_type"
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
                "macho-processor: GRAPHICS FORWARDING BOUNDARY: the guest's VkDevice, VkSwapchainKHR, swapchain images, commands, queue submissions and presents are MODELLED by Rosette and reach no driver. Rosette's own native presenter (stage={s}) owns the host half of the path. Guest pixels require Xenia to hand the presenter a completed image; until then every frame on the window is diagnostic.\n",
                .{@tagName(self.native_presenter.stage)},
            );
        }
        _ = self.presentWindowFrame(state, handle, image_width, image_height, 1);
        return 0;
    }

    fn enumerateSwapchainImages(self: *Forwarder, state: anytype) u64 {
        const count_address = state.regs.rdx;
        if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
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

    fn queueSubmit(self: *Forwarder) u64 {
        self.vulkan_queue_submits +|= 1;
        self.frame_provenance.noteGuestVulkanCall();
        if (self.vulkan_queue_submits == 1) {
            machoCapturePrint(
                "macho-processor: Vulkan MODELLED milestone: first_queue_submit. Rosette answered the call; no native VkQueue saw it and no command executed. This counts guest intent, not host work.\n",
                .{},
            );
        }
        return 0;
    }

    fn queuePresent(self: *Forwarder, state: anytype) u64 {
        self.vulkan_presents +|= 1;
        self.frame_provenance.noteGuestVulkanCall();
        // The guest asking to present is a reason to put a frame up, not a
        // frame. What reaches the display is Rosette's own presenter, and its
        // source is still a host clear because the guest's modelled command
        // stream produced no image to carry.
        const presented = self.presentWindowFrame(state, self.vulkan_presents, 0, 0, 3);
        if (self.vulkan_presents == 1) {
            machoCapturePrint(
                "macho-processor: Vulkan MODELLED milestone: first_queue_present. presentation provenance=DIAGNOSTIC_ONLY source=host_clear native_swapchain={s} native_queue_submit={s} guest_output=NO displayed={}\n",
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
        // VkMemoryAllocateInfo is {sType, padding, pNext, allocationSize,
        // memoryTypeIndex}. Reading +8 observes pNext (often a stack address),
        // not allocationSize, and caused the old model to reserve multi-GB
        // phantom allocations.
        if (info == 0 or state.guestMemoryConst(info + 16, 8) == null) return vkErrorInitializationFailed();
        const requested_size = state.read64(info + 16);
        if (requested_size == 0) return vkErrorInitializationFailed();

        const record = self.freeVulkanMemoryRecord() orelse return vkErrorOutOfHostMemory();
        const handle = self.nextVulkanObject();
        state.write64(output, handle);
        registerOpaqueHandle(state, handle, "Vulkan device memory");
        record.* = .{
            .handle = handle,
            .requested_size = requested_size,
        };
        self.vulkan_memory_allocations +|= 1;
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
        if (info == 0 or state.guestMemoryConst(info + count_offset, 4) == null) return vkErrorInitializationFailed();
        const count = state.read32(info + count_offset);
        if (count == 0) return 0;
        if (output == 0 or state.guestMemory(output, @as(u64, count) * 8) == null) return vkErrorInitializationFailed();
        for (0..count) |index| {
            const handle = self.nextVulkanObject();
            state.write64(output + @as(u64, @intCast(index)) * 8, handle);
            registerOpaqueHandle(state, handle, name);
        }
        machoCapturePrint("macho-processor: Vulkan objects allocated: {s} count={d} output=0x{x}\n", .{ name, count, output });
        return 0;
    }

    fn createMultipleVulkanObjects(self: *Forwarder, state: anytype, count: u64, output: u64, name: []const u8) u64 {
        if (count == 0) return 0;
        if (output == 0 or state.guestMemory(output, count * 8) == null) return vkErrorInitializationFailed();
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
                    "macho-processor: Vulkan guest loader virtualized: path={s} mode=0x{x} token=0x{x}; native dyld load deferred until Metal surface bind and is currently limited to the shadow instance + surface bridge\n",
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
        return report.classification;
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
                "macho-processor: Vulkan forwarding contract: guest_objects=MODELLED (physical_device+logical_device+swapchain+images+commands+submit+present) rosette_presenter={s} capability_queries={d} device_void_calls={d} modelled_commands={d}\n",
                .{ @tagName(self.native_presenter.stage), self.vulkan_surface_capability_queries, self.vulkan_device_void_calls, self.vulkan_modeled_command_calls },
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
    if (std.mem.eql(u8, symbol, "vkQueueSubmit") or std.mem.eql(u8, symbol, "vkQueueBindSparse")) return .queue_submit;
    if (std.mem.eql(u8, symbol, "vkQueuePresentKHR")) return .queue_present;
    if (std.mem.eql(u8, symbol, "vkAllocateMemory")) return .allocate_memory;
    if (std.mem.eql(u8, symbol, "vkMapMemory")) return .map_memory;
    if (std.mem.eql(u8, symbol, "vkGetBufferMemoryRequirements") or
        std.mem.eql(u8, symbol, "vkGetImageMemoryRequirements")) return .get_memory_requirements;
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
    };
    for (create_objects) |name| if (std.mem.eql(u8, symbol, name)) return .create_device_object;
    const graphics_pipelines = [_][]const u8{
        "vkCreateGraphicsPipelines",
        "vkCreateComputePipelines",
    };
    for (graphics_pipelines) |name| if (std.mem.eql(u8, symbol, name)) return .create_graphics_pipelines;
    if (std.mem.eql(u8, symbol, "vkAllocateCommandBuffers")) return .allocate_command_buffers;
    if (std.mem.eql(u8, symbol, "vkAllocateDescriptorSets")) return .allocate_descriptor_sets;
    const destroy_objects = [_][]const u8{
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
        "vkDestroyPipeline",
        "vkFreeCommandBuffers",
        "vkFreeDescriptorSets",
        "vkFreeMemory",
    };
    for (destroy_objects) |name| if (std.mem.eql(u8, symbol, name)) return .destroy_device_object;
    const success_calls = [_][]const u8{
        "vkBeginCommandBuffer",
        "vkEndCommandBuffer",
        "vkFlushMappedMemoryRanges",
        "vkGetFenceStatus",
        "vkInvalidateMappedMemoryRanges",
        "vkResetCommandPool",
        "vkResetDescriptorPool",
        "vkResetFences",
        "vkWaitForFences",
    };
    for (success_calls) |name| if (std.mem.eql(u8, symbol, name)) return .device_success;
    if (std.mem.eql(u8, symbol, "vkBindImageMemory")) return .bind_image_memory;
    if (std.mem.eql(u8, symbol, "vkBindBufferMemory")) return .bind_buffer_memory;
    if (std.mem.startsWith(u8, symbol, "vkCmd") or
        std.mem.eql(u8, symbol, "vkUpdateDescriptorSets") or
        std.mem.eql(u8, symbol, "vkUnmapMemory")) return .device_void;
    return .@"opaque";
}

const extension_names = [_][]const u8{
    "VK_KHR_surface",
    "VK_EXT_metal_surface",
    "VK_KHR_portability_enumeration",
    "VK_KHR_get_physical_device_properties2",
};

fn enumerateInstanceExtensions(state: anytype) u64 {
    const count_address = state.regs.rsi;
    if (state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
    if (state.regs.rdx == 0) {
        state.write32(count_address, extension_names.len);
        return 0;
    }
    const requested = state.read32(count_address);
    const written: u32 = @min(requested, extension_names.len);
    const properties_size: u64 = 260;
    const bytes = state.guestMemory(state.regs.rdx, @as(u64, written) * properties_size) orelse return vkErrorInitializationFailed();
    @memset(bytes, 0);
    for (extension_names[0..written], 0..) |name, index| {
        const offset = index * @as(usize, @intCast(properties_size));
        @memcpy(bytes[offset..][0..name.len], name);
        std.mem.writeInt(u32, bytes[offset + 256 ..][0..4], 1, .little);
    }
    state.write32(count_address, written);
    return if (written < extension_names.len) 5 else 0; // VK_INCOMPLETE / VK_SUCCESS
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
    const count_address = state.regs.rdx;
    if (state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
    if (state.regs.rcx == 0) {
        state.write32(count_address, device_extensions.len);
        return 0;
    }
    const requested = state.read32(count_address);
    const written: u32 = @min(requested, device_extensions.len);
    const bytes = state.guestMemory(state.regs.rcx, @as(u64, written) * 260) orelse return vkErrorInitializationFailed();
    @memset(bytes, 0);
    for (device_extensions[0..written], 0..) |name, index| {
        const offset = index * 260;
        @memcpy(bytes[offset..][0..name.len], name);
        std.mem.writeInt(u32, bytes[offset + 256 ..][0..4], 1, .little);
    }
    state.write32(count_address, written);
    return if (written < device_extensions.len) 5 else 0;
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
    std.mem.writeInt(u32, bytes[0..4], 1, .little);
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
    const bytes = state.guestMemory(output, 84) orelse return;
    @memset(bytes[16..84], 0);
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

fn enumerateHandle(state: anytype, count_address: u64, output: u64, handle: u64, owner: []const u8) u64 {
    if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
    if (output == 0) {
        state.write32(count_address, 1);
        return 0;
    }
    if (state.read32(count_address) == 0 or state.guestMemory(output, 8) == null) return 5;
    state.write64(output, handle);
    registerOpaqueHandle(state, handle, owner);
    state.write32(count_address, 1);
    return 0;
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

fn vkErrorInitializationFailed() u64 {
    return @as(u32, @bitCast(@as(i32, -3)));
}

fn vkErrorInitializationFailedSigned() i32 {
    return -3;
}

fn vkErrorOutOfHostMemory() u64 {
    return @as(u32, @bitCast(@as(i32, -1)));
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
    try std.testing.expectEqual(GuestSymbolKind.create_device_object, guestSymbolKind("vkCreateDescriptorSetLayout"));
    try std.testing.expectEqual(GuestSymbolKind.create_device_object, guestSymbolKind("vkCreateImageView"));
    try std.testing.expectEqual(GuestSymbolKind.allocate_memory, guestSymbolKind("vkAllocateMemory"));
    try std.testing.expectEqual(GuestSymbolKind.map_memory, guestSymbolKind("vkMapMemory"));
    try std.testing.expectEqual(GuestSymbolKind.get_memory_requirements, guestSymbolKind("vkGetImageMemoryRequirements"));
    try std.testing.expectEqual(GuestSymbolKind.device_void, guestSymbolKind("vkCmdDrawIndexed"));
    try std.testing.expectEqual(GuestSymbolKind.device_success, guestSymbolKind("vkWaitForFences"));
    try std.testing.expectEqual(GuestSymbolKind.create_graphics_pipelines, guestSymbolKind("vkCreateGraphicsPipelines"));
    try std.testing.expectEqual(GuestSymbolKind.create_graphics_pipelines, guestSymbolKind("vkCreateComputePipelines"));
    try std.testing.expectEqual(GuestSymbolKind.allocate_command_buffers, guestSymbolKind("vkAllocateCommandBuffers"));
    try std.testing.expectEqual(GuestSymbolKind.destroy_device_object, guestSymbolKind("vkDestroyShaderModule"));
}

test "Vulkan physical device properties model follows x64 C ABI alignment" {
    try std.testing.expectEqual(@as(usize, 296), VK_PHYSICAL_DEVICE_LIMITS_OFFSET);
    try std.testing.expectEqual(@as(u64, 824), VK_PHYSICAL_DEVICE_PROPERTIES_SIZE);
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
    heap_next: u64 = 1024,

    pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }

    fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
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
    try std.testing.expectEqual(@as(u64, 0), forwarder.createVulkanObject(&state, 8, "vkCreateBuffer"));
    try std.testing.expectEqual(state.read64(8), state.last_opaque_handle);
    try std.testing.expectEqualStrings("vkCreateBuffer", state.last_opaque_owner);
}

test "modeled Vulkan memory uses allocationSize and reuses one mapping" {
    var forwarder = Forwarder{};
    var state = TestState{};
    const allocate_info: u64 = 16;
    const allocate_output: u64 = 64;
    state.write64(allocate_info + 8, 0x7FFF_FFFF); // pNext, never a size.
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
