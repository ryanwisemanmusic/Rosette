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
};

const Library = struct {
    path: []const u8 = "",
    handle: ?*anyopaque = null,
};

const GuestLibrary = struct {
    token: u64 = 0,
    handle: ?*anyopaque = null,
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
    create_metal_surface,
    destroy_surface,
    get_surface_capabilities,
    get_surface_formats,
    get_surface_present_modes,
    get_surface_support,
    destroy_device,
    create_device_object,
    allocate_command_buffers,
    allocate_descriptor_sets,
    destroy_device_object,
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
    considered: u64 = 0,
    forwarded: u64 = 0,
    rejected_not_allowlisted: u64 = 0,
    rejected_library: u64 = 0,
    rejected_symbol: u64 = 0,
    rejected_guest_memory: u64 = 0,

    pub fn deinit(self: *Forwarder) void {
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
        const library = self.guestLibrary(library_token) orelse return 0;
        var symbol_buffer: [512]u8 = undefined;
        const symbol_z = nulTerminate(&symbol_buffer, symbol) orelse return 0;
        _ = dlsym(library, symbol_z) orelse return 0;
        return self.allocateGuestSymbol(library_token, symbol);
    }

    fn lookupVulkanProcGuest(self: *Forwarder, library_token: u64, symbol: []const u8) u64 {
        if (self.guestLibrary(library_token) == null) return 0;
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
            if (self.guestLibrary(entry.library_token) == null) return false;
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
                .create_device => state.regs.rax = createHandle(state, state.regs.rcx, 0xFFFF_F600_0000_0021),
                .get_device_queue => {
                    if (state.guestMemory(state.regs.rcx, 8) != null) state.write64(state.regs.rcx, 0xFFFF_F600_0000_0031);
                    state.regs.rax = 0;
                },
                .create_metal_surface => state.regs.rax = createHandle(state, state.regs.rcx, 0xFFFF_F600_0000_0041),
                .get_surface_capabilities => state.regs.rax = writeSurfaceCapabilities(state, state.regs.rdx),
                .get_surface_formats => state.regs.rax = enumerateSurfaceFormats(state),
                .get_surface_present_modes => state.regs.rax = enumerateSurfacePresentModes(state),
                .get_surface_support => state.regs.rax = writeBoolResult(state, state.regs.rcx, true),
                .destroy_instance, .destroy_surface, .destroy_device => state.regs.rax = 0,
                .create_device_object => state.regs.rax = self.createVulkanObject(state, state.regs.rcx, entry.name[0..entry.name_length]),
                .allocate_command_buffers => state.regs.rax = self.allocateVulkanObjects(state, state.regs.rsi, state.regs.rdx, 28, entry.name[0..entry.name_length]),
                .allocate_descriptor_sets => state.regs.rax = self.allocateVulkanObjects(state, state.regs.rsi, state.regs.rdx, 24, entry.name[0..entry.name_length]),
                .destroy_device_object => state.regs.rax = 0,
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

    fn allocateVulkanObjects(self: *Forwarder, state: anytype, info: u64, output: u64, count_offset: u64, name: []const u8) u64 {
        if (info == 0 or state.guestMemoryConst(info + count_offset, 4) == null) return vkErrorInitializationFailed();
        const count = state.read32(info + count_offset);
        if (count == 0) return 0;
        if (output == 0 or state.guestMemory(output, @as(u64, count) * 8) == null) return vkErrorInitializationFailed();
        for (0..count) |index| state.write64(output + @as(u64, @intCast(index)) * 8, self.nextVulkanObject());
        std.debug.print("macho-processor: Vulkan objects allocated: {s} count={d} output=0x{x}\n", .{ name, count, output });
        return 0;
    }

    pub fn openGuest(self: *Forwarder, path: []const u8, mode: u64) u64 {
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
            const result = if (entry.handle) |handle| dlclose(handle) else -1;
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

    fn guestLibrary(self: *Forwarder, token: u64) ?*anyopaque {
        for (&self.guest_libraries) |*entry| {
            if (entry.token == token) return entry.handle;
        }
        return null;
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
    if (std.mem.eql(u8, symbol, "vkCreateMetalSurfaceEXT")) return .create_metal_surface;
    if (std.mem.eql(u8, symbol, "vkDestroySurfaceKHR")) return .destroy_surface;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR")) return .get_surface_capabilities;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceSurfaceFormatsKHR")) return .get_surface_formats;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceSurfacePresentModesKHR")) return .get_surface_present_modes;
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceSurfaceSupportKHR")) return .get_surface_support;
    if (std.mem.eql(u8, symbol, "vkDestroyDevice")) return .destroy_device;
    const create_objects = [_][]const u8{
        "vkCreateDescriptorSetLayout",
        "vkCreatePipelineLayout",
        "vkCreateShaderModule",
        "vkCreateRenderPass",
        "vkCreateSemaphore",
        "vkCreateCommandPool",
        "vkCreateDescriptorPool",
    };
    for (create_objects) |name| if (std.mem.eql(u8, symbol, name)) return .create_device_object;
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
        "vkFreeCommandBuffers",
        "vkFreeDescriptorSets",
    };
    for (destroy_objects) |name| if (std.mem.eql(u8, symbol, name)) return .destroy_device_object;
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

fn writePhysicalDeviceProperties(state: anytype, output: u64) void {
    // Populate the fixed identity prefix through pipelineCacheUUID. Limits
    // and sparse properties remain guest-initialized instead of writing past
    // the fields Rosette substantively models.
    const bytes = state.guestMemory(output, 292) orelse return;
    @memset(bytes, 0);
    std.mem.writeInt(u32, bytes[0..4], 0x0040_2000, .little);
    std.mem.writeInt(u32, bytes[4..8], 1, .little);
    std.mem.writeInt(u32, bytes[8..12], 0x106B, .little); // Apple
    std.mem.writeInt(u32, bytes[12..16], 1, .little);
    std.mem.writeInt(u32, bytes[16..20], 2, .little); // discrete GPU profile
    const name = "Rosette Vulkan Metal Adapter";
    @memcpy(bytes[20..][0..name.len], name);
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
    std.mem.writeInt(u32, bytes[0..4], 0x7, .little); // graphics, compute, transfer
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

fn writePhysicalDeviceProperties2(state: anytype, output: u64) void {
    writePhysicalDeviceProperties(state, output + 16);
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

test "Vulkan guest symbol classification covers surface bootstrap" {
    try std.testing.expectEqual(GuestSymbolKind.enumerate_instance_extensions, guestSymbolKind("vkEnumerateInstanceExtensionProperties"));
    try std.testing.expectEqual(GuestSymbolKind.create_metal_surface, guestSymbolKind("vkCreateMetalSurfaceEXT"));
    try std.testing.expectEqual(GuestSymbolKind.create_device, guestSymbolKind("vkCreateDevice"));
    try std.testing.expectEqual(GuestSymbolKind.get_physical_device_features2, guestSymbolKind("vkGetPhysicalDeviceFeatures2"));
    try std.testing.expectEqual(GuestSymbolKind.get_physical_device_features2, guestSymbolKind("vkGetPhysicalDeviceFeatures2KHR"));
    try std.testing.expectEqual(GuestSymbolKind.get_physical_device_properties2, guestSymbolKind("vkGetPhysicalDeviceProperties2"));
    try std.testing.expectEqual(GuestSymbolKind.get_physical_device_memory_properties2, guestSymbolKind("vkGetPhysicalDeviceMemoryProperties2"));
    try std.testing.expectEqual(GuestSymbolKind.create_device_object, guestSymbolKind("vkCreateDescriptorSetLayout"));
    try std.testing.expectEqual(GuestSymbolKind.allocate_command_buffers, guestSymbolKind("vkAllocateCommandBuffers"));
    try std.testing.expectEqual(GuestSymbolKind.destroy_device_object, guestSymbolKind("vkDestroyShaderModule"));
}

fn normalizeMachOSymbol(symbol: []const u8) []const u8 {
    if (symbol.len != 0 and symbol[0] == '_') return symbol[1..];
    return symbol;
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
    mem: [32]u8 = [_]u8{0} ** 32,
    regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0 } = .{},

    pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }

    fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }
};

test "forwarding registry only admits typed libSystem functions" {
    try std.testing.expectEqual(Signature.no_args_i32, specFor("getpid").?.signature);
    try std.testing.expect(specFor("objc_msgSend") == null);
    try std.testing.expect(specFor("_ZNSt3__16localeD1Ev") == null);
    try std.testing.expectEqual(LibraryClass.libcxx, specFor("_ZNSt3__18ios_base6xallocEv").?.library);
    try std.testing.expect(libraryMatches(.libsystem, "/usr/lib/libSystem.B.dylib"));
    try std.testing.expect(!libraryMatches(.libsystem, "/usr/lib/libc++.1.dylib"));
    try std.testing.expect(libraryMatches(.libcxx, "/usr/lib/libc++.1.dylib"));
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
