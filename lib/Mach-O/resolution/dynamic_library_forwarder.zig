const std = @import("std");
const builtin = @import("builtin");

const RTLD_LAZY: c_int = 0x1;
const RTLD_LOCAL: c_int = 0x4;
const MAX_LIBRARIES = 16;
const MAX_GUEST_LIBRARIES = 32;
const MAX_GUEST_SYMBOLS = 256;
const GUEST_LIBRARY_HANDLE_BASE: u64 = 0xFFFF_FC00_0000_0000;
const GUEST_SYMBOL_THUNK_BASE: u64 = 0xFFFF_FB00_0000_0000;

extern fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern fn dlclose(handle: *anyopaque) c_int;

pub const Signature = enum {
    no_args_i32,
    no_args_u32,
    buffer_length_usize,
    two_buffers_length_i32,
    buffer_byte_length_pointer,
    guest_memory_copy,
    libcxx_getloc,
    libcxx_istream_sentry_constructor,
    void_with_pointer_arg,
    socket_three_args,
    setsockopt_five_args,
    snprintf_three_args,
    connect_three_args,
    send_four_args,
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
    .{ .symbol = "getpagesize", .library = .libsystem, .signature = .no_args_i32 },
    .{ .symbol = "arc4random", .library = .libsystem, .signature = .no_args_u32 },
    .{ .symbol = "strnlen", .library = .libsystem, .signature = .buffer_length_usize },
    .{ .symbol = "strncmp", .library = .libsystem, .signature = .two_buffers_length_i32 },
    .{ .symbol = "memcmp", .library = .libsystem, .signature = .two_buffers_length_i32 },
    .{ .symbol = "memchr", .library = .libsystem, .signature = .buffer_byte_length_pointer },
    .{ .symbol = "memcpy", .library = .libsystem, .signature = .guest_memory_copy },
    .{ .symbol = "_ZNSt3__18ios_base6xallocEv", .library = .libcxx, .signature = .no_args_i32 },
    .{ .symbol = "_ZNKSt3__18ios_base6getlocEv", .library = .libcxx, .signature = .libcxx_getloc },
    .{ .symbol = "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE6sentryC1ERS3_b", .library = .libcxx, .signature = .libcxx_istream_sentry_constructor },
    .{ .symbol = "_ZNSt3__111this_thread9sleep_forERKNS_6chrono8durationIxNS_5ratioILl1ELl1000000000EEEEE", .library = .libcxx, .signature = .void_with_pointer_arg },
    .{ .symbol = "socket", .library = .libsystem, .signature = .socket_three_args },
    .{ .symbol = "setsockopt", .library = .libsystem, .signature = .setsockopt_five_args },
    .{ .symbol = "snprintf", .library = .libsystem, .signature = .snprintf_three_args },
    .{ .symbol = "connect", .library = .libsystem, .signature = .connect_three_args },
    .{ .symbol = "send", .library = .libsystem, .signature = .send_four_args },
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
    ready,
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
    vulkan_memory_allocations: u64 = 0,
    vulkan_memory_maps: u64 = 0,
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
    vulkan_swapchain_image_handles: [4]u64 = [_]u64{0} ** 4,
    vulkan_swapchain_image_count: u32 = 0,
    considered: u64 = 0,
    forwarded: u64 = 0,
    rejected_not_allowlisted: u64 = 0,
    rejected_library: u64 = 0,
    rejected_symbol: u64 = 0,
    rejected_guest_memory: u64 = 0,

    pub fn deinit(self: *Forwarder) void {
        self.destroyNativeVulkanObjects();
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
            std.debug.print(
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
        std.debug.print(
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
        for (&self.guest_symbols) |*entry| {
            if (entry.token != token) continue;
            if (self.guestLibraryEntry(entry.library_token) == null) return false;
            self.guest_thunk_calls +|= 1;
            entry.calls +|= 1;
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
                .create_instance => state.regs.rax = createHandle(state, state.regs.rdx, 0xFFFF_F600_0000_0001),
                .enumerate_physical_devices => state.regs.rax = enumerateHandle(state, state.regs.rsi, state.regs.rdx, 0xFFFF_F600_0000_0011),
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
                .get_surface_capabilities => state.regs.rax = writeSurfaceCapabilities(state, state.regs.rdx),
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
                .queue_present => state.regs.rax = self.queuePresent(),
                .create_device_object => state.regs.rax = self.createVulkanObject(state, state.regs.rcx, entry.name[0..entry.name_length]),
                .allocate_command_buffers => state.regs.rax = self.allocateVulkanObjects(state, state.regs.rsi, state.regs.rdx, 28, entry.name[0..entry.name_length]),
                .allocate_descriptor_sets => state.regs.rax = self.allocateVulkanObjects(state, state.regs.rsi, state.regs.rdx, 24, entry.name[0..entry.name_length]),
                .allocate_memory => state.regs.rax = self.allocateVulkanMemory(state, state.regs.rsi, state.regs.rcx),
                .map_memory => state.regs.rax = self.mapVulkanMemory(state, state.regs.rcx, state.regs.r9),
                .get_memory_requirements => state.regs.rax = writeMemoryRequirements(state, state.regs.rdx),
                .create_graphics_pipelines => state.regs.rax = self.createMultipleVulkanObjects(state, state.regs.rdx, state.regs.r9, entry.name[0..entry.name_length]),
                .destroy_device_object => state.regs.rax = 0,
                .device_success => state.regs.rax = 0,
                .device_void => state.regs.rax = 0,
                // A non-null lookup remains useful for capability discovery,
                // but calling an untyped ARM64 function through x86 registers
                // is unsafe. Keep it contained until its Vulkan ABI signature
                // has an explicit bridge.
                .@"opaque" => {
                    self.guest_opaque_calls +|= 1;
                    std.debug.print(
                        "macho-processor: Vulkan ABI gap: called unmodeled proc {s} (token=0x{x}, call={d}); returning zero\n",
                        .{ entry.name[0..entry.name_length], entry.token, entry.calls },
                    );
                    state.regs.rax = 0;
                },
            }
            return true;
        }
        return false;
    }

    fn nextVulkanObject(self: *Forwarder) u64 {
        const result = self.next_vulkan_object;
        self.next_vulkan_object +%= 0x10;
        return result;
    }

    fn createVulkanObject(self: *Forwarder, state: anytype, output: u64, name: []const u8) u64 {
        if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
        const handle = self.nextVulkanObject();
        state.write64(output, handle);
        std.debug.print("macho-processor: Vulkan object created: {s} handle=0x{x} output=0x{x}\n", .{ name, handle, output });
        return 0;
    }

    fn createLogicalDevice(self: *Forwarder, state: anytype, output: u64) u64 {
        const result = createHandle(state, output, VK_SYNTHETIC_DEVICE);
        if (result == 0) {
            self.vulkan_logical_devices_created +|= 1;
            if (self.vulkan_logical_devices_created == 1) {
                std.debug.print(
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
        self.vulkan_queues_acquired +|= 1;
        if (self.vulkan_queues_acquired == 1) {
            std.debug.print(
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
            std.debug.print(
                "macho-processor: native Vulkan instance creation failed: attempt={d} VkResult={d} library_token=0x{x}\n",
                .{ self.native_vulkan_instance_attempts, result, library_token },
            );
            return if (result != 0) result else vkErrorInitializationFailedSigned();
        }
        self.native_vulkan_instance = instance;
        self.native_vulkan_library_token = library_token;
        std.debug.print(
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
            std.debug.print(
                "macho-processor: native vkCreateMetalSurfaceEXT failed: attempt={d} VkResult={d} CAMetalLayer=0x{x} surface=0x{x}\n",
                .{ self.native_vulkan_surface_attempts, result, host_layer, surface },
            );
            return .{ .enforced = true, .result = if (result != 0) result else vkErrorInitializationFailedSigned(), .surface = 0 };
        }
        self.native_vulkan_surface = surface;
        std.debug.print(
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

    fn createMetalSurface(self: *Forwarder, state: anytype, library_token: u64, instance: u64, create_info: u64, output: u64) u64 {
        self.vulkan_presenter_stage = .metal_surface_requested;
        const info = state.guestMemoryConst(create_info, 32);
        const s_type = if (info != null) state.read32(create_info) else 0;
        const layer = if (info != null) state.read64(create_info + 24) else 0;
        if (state.active_gtk_idle_source == 0) self.vulkan_presenter_off_ui_calls +|= 1;
        std.debug.print(
            "macho-processor: Vulkan presenter bind: stage=metal_surface_requested step={d} thread=0x{x} gtk_idle_source={d} instance=0x{x} create_info=0x{x} s_type={d} layer=0x{x} output=0x{x}\n",
            .{ state.executed_steps, state.active_guest_thread, state.active_gtk_idle_source, instance, create_info, s_type, layer, output },
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
            std.debug.print(
                "macho-processor: Vulkan presenter bind failed: stage=metal_surface reason={s} create_info=0x{x} s_type={d} expected={d}\n",
                .{ if (info == null) "unmapped_create_info" else if (s_type != VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT) "unexpected_s_type" else if (layer == 0) "null_metal_layer" else "unbound_native_metal_layer", create_info, s_type, VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT },
            );
            return vkErrorInitializationFailed();
        }
        const native_surface = self.createNativeMetalSurface(state, library_token);
        if (native_surface.enforced and native_surface.result != 0) {
            self.vulkan_presenter_stage = .failed;
            self.vulkan_presenter_bind_failures +|= 1;
            std.debug.print(
                "macho-processor: Vulkan presenter bind failed: stage=metal_surface reason=host_vkCreateMetalSurfaceEXT_failed VkResult={d} layer=0x{x}\n",
                .{ native_surface.result, layer },
            );
            return @as(u32, @bitCast(native_surface.result));
        }
        const result = createHandle(state, output, VK_SYNTHETIC_SURFACE);
        if (result == 0) {
            self.vulkan_metal_surfaces_created +|= 1;
            self.vulkan_presenter_stage = .metal_surface_created;
            if (@hasDecl(State, "noteNativeVulkanSurfaceBound")) {
                state.noteNativeVulkanSurfaceBound(layer, VK_SYNTHETIC_SURFACE, native_surface.surface);
            }
            if (self.vulkan_metal_surfaces_created == 1) {
                std.debug.print(
                    "macho-processor: Vulkan milestone: metal_surface_created surface=0x{x} layer=0x{x} output=0x{x} gtk_idle_source={d}\n",
                    .{ VK_SYNTHETIC_SURFACE, layer, output, state.active_gtk_idle_source },
                );
            }
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
        if (state.active_gtk_idle_source == 0) self.vulkan_presenter_off_ui_calls +|= 1;
        std.debug.print(
            "macho-processor: Vulkan presenter bind: stage=swapchain_requested attempt={d} step={d} thread=0x{x} gtk_idle_source={d} device=0x{x} create_info=0x{x} s_type={d} surface=0x{x} output=0x{x}\n",
            .{ self.vulkan_presenter_bind_attempts, state.executed_steps, state.active_guest_thread, state.active_gtk_idle_source, device, create_info, s_type, surface, output },
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
            std.debug.print(
                "macho-processor: Vulkan presenter bind failed: stage=swapchain attempt={d} reason={s} device=0x{x} surface=0x{x} s_type={d} output=0x{x}\n",
                .{ self.vulkan_presenter_bind_attempts, reason, device, surface, s_type, output },
            );
            return vkErrorInitializationFailed();
        }
        const handle = self.nextVulkanObject();
        state.write64(output, handle);
        self.vulkan_swapchains_created +|= 1;
        self.vulkan_swapchain_image_count = 3;
        for (self.vulkan_swapchain_image_handles[0..self.vulkan_swapchain_image_count]) |*image| {
            if (image.* == 0) image.* = self.nextVulkanObject();
        }
        if (self.vulkan_swapchains_created == 1) {
            std.debug.print(
                "macho-processor: Vulkan milestone: swapchain_created handle=0x{x} output=0x{x} images={d}\n",
                .{ handle, output, self.vulkan_swapchain_image_count },
            );
        }
        self.vulkan_presenter_stage = .ready;
        std.debug.print(
            "macho-processor: Vulkan presenter bind complete: stage=ready attempt={d} surface=0x{x} swapchain=0x{x} gtk_idle_source={d}\n",
            .{ self.vulkan_presenter_bind_attempts, surface, handle, state.active_gtk_idle_source },
        );
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
            }
            state.write64(state.regs.rcx + @as(u64, @intCast(index)) * 8, handle);
        }
        state.write32(count_address, written);
        self.vulkan_swapchain_images_enumerated +|= written;
        if (self.vulkan_swapchain_images_enumerated == written) {
            std.debug.print(
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
            std.debug.print(
                "macho-processor: Vulkan milestone: first_image_acquired index=0 output=0x{x}\n",
                .{output},
            );
        }
        return 0;
    }

    fn queueSubmit(self: *Forwarder) u64 {
        self.vulkan_queue_submits +|= 1;
        if (self.vulkan_queue_submits == 1) {
            std.debug.print("macho-processor: Vulkan milestone: first_queue_submit\n", .{});
        }
        return 0;
    }

    fn queuePresent(self: *Forwarder) u64 {
        self.vulkan_presents +|= 1;
        if (self.vulkan_presents == 1) {
            std.debug.print("macho-processor: Vulkan milestone: first_present_reached\n", .{});
        }
        return 0;
    }

    fn allocateVulkanMemory(self: *Forwarder, state: anytype, info: u64, output: u64) u64 {
        if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
        const handle = self.nextVulkanObject();
        state.write64(output, handle);
        self.vulkan_memory_allocations +|= 1;
        const size = if (info != 0 and state.guestMemoryConst(info + 8, 8) != null) state.read64(info + 8) else 0;
        if (self.vulkan_memory_allocations <= 8 or self.vulkan_memory_allocations % 64 == 0) {
            std.debug.print(
                "macho-processor: Vulkan memory allocated: handle=0x{x} requested_size={d} output=0x{x}\n",
                .{ handle, size, output },
            );
        }
        return 0;
    }

    fn mapVulkanMemory(self: *Forwarder, state: anytype, requested_size: u64, output: u64) u64 {
        if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
        const fallback_size: u64 = 16 * 1024 * 1024;
        const max_modeled_size: u64 = 64 * 1024 * 1024;
        const allocation_size = if (requested_size == 0 or requested_size == std.math.maxInt(u64))
            fallback_size
        else
            @min(requested_size, max_modeled_size);
        const mapped = state.guestAlloc(allocation_size, 16) orelse return vkErrorOutOfHostMemory();
        state.write64(output, mapped);
        self.vulkan_memory_maps +|= 1;
        std.debug.print(
            "macho-processor: Vulkan memory mapped: ptr=0x{x} modeled_size={d} requested_size={d} output=0x{x}\n",
            .{ mapped, allocation_size, requested_size, output },
        );
        return 0;
    }

    fn allocateVulkanObjects(self: *Forwarder, state: anytype, info: u64, output: u64, count_offset: u64, name: []const u8) u64 {
        if (info == 0 or state.guestMemoryConst(info + count_offset, 4) == null) return vkErrorInitializationFailed();
        const count = state.read32(info + count_offset);
        if (count == 0) return 0;
        if (output == 0 or state.guestMemory(output, @as(u64, count) * 8) == null) return vkErrorInitializationFailed();
        for (0..count) |index| state.write64(output + @as(u64, @intCast(index)) * 8, self.nextVulkanObject());
        std.debug.print("macho-processor: Vulkan objects allocated: {s} count={d} output=0x{x}\n", .{ name, count, output });
        return 0;
    }

    fn createMultipleVulkanObjects(self: *Forwarder, state: anytype, count: u64, output: u64, name: []const u8) u64 {
        if (count == 0) return 0;
        if (output == 0 or state.guestMemory(output, count * 8) == null) return vkErrorInitializationFailed();
        for (0..count) |index| state.write64(output + index * 8, self.nextVulkanObject());
        std.debug.print("macho-processor: Vulkan objects created: {s} count={d} output=0x{x}\n", .{ name, count, output });
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
                std.debug.print(
                    "macho-processor: Vulkan guest loader virtualized: path={s} mode=0x{x} token=0x{x}; native dyld load deferred until Metal surface bind\n",
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
        _ = self;
        return switch (signature) {
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

    pub fn logSummary(self: *const Forwarder) void {
        std.debug.print(
            "macho-processor: dynamic library forwarding: considered={d} forwarded={d} guest_open={d} guest_close={d} guest_lookup={d} proc_queries={d} guest_thunk_calls={d} opaque_calls={d} not_allowlisted={d} library_rejected={d} symbol_missing={d} guest_memory_rejected={d}\n",
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
            },
        );
        if (self.guest_proc_queries != 0) {
            std.debug.print(
                "macho-processor: Vulkan lifecycle: device={d} queue={d} metal_surface={d} swapchain={d} swapchain_images={d} acquired={d} submits={d} presents={d} memory(alloc/maps)={d}/{d} opaque={d} presenter(stage/attempts/failures/off_ui_calls)={s}/{d}/{d}/{d}\n",
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
                    self.guest_opaque_calls,
                    @tagName(self.vulkan_presenter_stage),
                    self.vulkan_presenter_bind_attempts,
                    self.vulkan_presenter_bind_failures,
                    self.vulkan_presenter_off_ui_calls,
                },
            );
            std.debug.print(
                "macho-processor: native Vulkan presenter backing: loader(attempts/failures)={d}/{d} instance_attempts={d} surface_attempts={d} failures={d} instance=0x{x} host_surface=0x{x} library_token=0x{x}\n",
                .{ self.native_vulkan_loader_attempts, self.native_vulkan_loader_failures, self.native_vulkan_instance_attempts, self.native_vulkan_surface_attempts, self.native_vulkan_failures, if (self.native_vulkan_instance) |instance| @intFromPtr(instance) else 0, self.native_vulkan_surface, self.native_vulkan_library_token },
            );
            std.debug.print("macho-processor: Vulkan proc inventory:\n", .{});
            for (&self.guest_symbols) |*entry| {
                if (entry.token == 0) continue;
                std.debug.print(
                    "  token=0x{x} kind={s} calls={d} name={s}\n",
                    .{ entry.token, @tagName(entry.kind), entry.calls, entry.name[0..entry.name_length] },
                );
            }
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
        std.debug.print(
            "macho-processor: native Vulkan loader begin: attempt={d} path={s}; entering host dlopen/dyld initializers\n",
            .{ self.native_vulkan_loader_attempts, path },
        );
        const handle = dlopen(path_z, RTLD_LAZY | RTLD_LOCAL) orelse {
            self.native_vulkan_loader_failures +|= 1;
            std.debug.print(
                "macho-processor: native Vulkan loader failed: attempt={d} path={s}\n",
                .{ self.native_vulkan_loader_attempts, path },
            );
            return null;
        };
        entry.handle = handle;
        std.debug.print(
            "macho-processor: native Vulkan loader ready: attempt={d} path={s} host_handle=0x{x}\n",
            .{ self.native_vulkan_loader_attempts, path, @intFromPtr(handle) },
        );
        return handle;
    }

    fn invoke(self: *Forwarder, state: anytype, signature: Signature, address: *anyopaque) ?Outcome {
        _ = self;
        return switch (signature) {
            .no_args_i32 => blk: {
                const function: *const fn () callconv(.c) c_int = @ptrCast(@alignCast(address));
                break :blk .{ .handled = @bitCast(@as(i64, function())) };
            },
            .no_args_u32 => blk: {
                const function: *const fn () callconv(.c) c_uint = @ptrCast(@alignCast(address));
                break :blk .{ .handled = function() };
            },
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
            .void_with_pointer_arg => blk: {
                // void function with a single pointer argument in rdi
                // Used for std::this_thread::sleep_for which takes a reference to duration
                // The duration is a 64-bit nanosecond count
                // Implement sleep directly in Zig to avoid memory layout issues
                const guest_duration = state.guestMemoryConst(state.regs.rdi, 8) orelse return null;
                const nanoseconds = std.mem.readInt(i64, guest_duration[0..8], .little);
                if (nanoseconds > 0) {
                    const ns = @as(u64, @intCast(nanoseconds));
                    // Use std.c.nanosleep directly (available on macOS/Linux)
                    const seconds = ns / 1_000_000_000;
                    const remainder = ns % 1_000_000_000;
                    const ts = std.c.timespec{
                        .sec = @intCast(seconds),
                        .nsec = @intCast(remainder),
                    };
                    _ = std.c.nanosleep(&ts, null);
                }
                break :blk .handled_void;
            },
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
        "vkBindBufferMemory",
        "vkBindImageMemory",
        "vkFlushMappedMemoryRanges",
        "vkGetFenceStatus",
        "vkInvalidateMappedMemoryRanges",
        "vkResetCommandPool",
        "vkResetDescriptorPool",
        "vkResetFences",
        "vkWaitForFences",
    };
    for (success_calls) |name| if (std.mem.eql(u8, symbol, name)) return .device_success;
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
    @memset(bytes, 0);
    std.mem.writeInt(u32, bytes[0..4], 2, .little);
    std.mem.writeInt(u32, bytes[4..8], 3, .little);
    std.mem.writeInt(u32, bytes[16..20], 1, .little);
    std.mem.writeInt(u32, bytes[20..24], 16384, .little);
    std.mem.writeInt(u32, bytes[24..28], 16384, .little);
    std.mem.writeInt(u32, bytes[28..32], 1, .little);
    std.mem.writeInt(u32, bytes[32..36], 1, .little);
    std.mem.writeInt(u32, bytes[36..40], 1, .little);
    std.mem.writeInt(u32, bytes[40..44], 1, .little);
    std.mem.writeInt(u32, bytes[44..48], 0x1F, .little);
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

fn writeMemoryRequirements(state: anytype, output: u64) u64 {
    const bytes = state.guestMemory(output, 24) orelse return vkErrorInitializationFailed();
    @memset(bytes, 0);
    std.mem.writeInt(u64, bytes[0..8], 4096, .little);
    std.mem.writeInt(u64, bytes[8..16], 256, .little);
    std.mem.writeInt(u32, bytes[16..20], 1, .little);
    return 0;
}

fn createHandle(state: anytype, output: u64, handle: u64) u64 {
    if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
    state.write64(output, handle);
    return 0;
}

fn enumerateHandle(state: anytype, count_address: u64, output: u64, handle: u64) u64 {
    if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
    if (output == 0) {
        state.write32(count_address, 1);
        return 0;
    }
    if (state.read32(count_address) == 0 or state.guestMemory(output, 8) == null) return 5;
    state.write64(output, handle);
    state.write32(count_address, 1);
    return 0;
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
    mem: [256]u8 = [_]u8{0} ** 256,
    regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0, r9: u64 = 0, rax: u64 = 0 } = .{},
    executed_steps: u64 = 10,
    active_guest_thread: u64 = 0x7FFF_2020,
    active_gtk_idle_source: u64 = 1,

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

    fn validateNativeMetalLayerToken(_: *@This(), token: u64) bool {
        return token == 0xCAFE_BABE;
    }
};

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
    try std.testing.expectEqual(VulkanPresenterStage.ready, forwarder.vulkan_presenter_stage);
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
