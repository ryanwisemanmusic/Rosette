const std = @import("std");
const builtin = @import("builtin");
// Every guest register and execution-local field this file touches is the
// calling guest thread's, through `guest_context`: a Windows worker runs this
// forwarder on its own host thread while the process owner - whose registers
// `state.regs` are - keeps running on another. See lib/guest_context/README.md.
const guest_context = @import("guest_context");
const guest_sleep = @import("scheduler").guest_sleep;
const rosette_gpu = @import("gpu");
const abi = @import("gpu").vulkan.abi;
const native_texture = @import("gpu").metal.live_texture;
const marshal = @import("gpu").vulkan.marshal;
const fsi_diagnostics = @import("gpu").vulkan.fsi_diagnostics;
const fsi_rasterization = @import("gpu").vulkan.fsi.rasterization;
const device_loss_diagnostics = @import("gpu").vulkan.device_loss_diagnostics;
const gpu_vulkan = @import("gpu").vulkan;
const async_vulkan_command = gpu_vulkan.async_command_worker;
const frame_capture = @import("gpu").vulkan.frame_capture;
const transport_timing = @import("gpu").vulkan.transport_timing;
const present_pacing = @import("gpu").vulkan.present_pacing;
const tier_consistency = @import("gpu").vulkan.tier_consistency;
const capture_plan = @import("gpu").vulkan.capture_plan;
const driver_identity = @import("gpu").vulkan.driver_identity;
const queue_api_gate = @import("gpu").vulkan.queue_api_gate;
const instance_extensions = @import("vulkan/instance_extensions.zig");
const surface_path_ledger = @import("vulkan/surface_path_ledger.zig");
const guest_memory_geometry = @import("guest_memory_geometry.zig");
const SlotIndex = @import("slot_index.zig").SlotIndex;
const machoCapturePrint = @import("event_log").machoCapturePrint;
const xenia_heap_range = @import("xenia_heap_range");
const ppc_runtime = @import("ppc_runtime");
const ppc_host_symbols = @import("rosette_ppc_host_abi");
const application_framework = @import("application_framework");
const xenia_launch_assist_contract = @import("xenia_launch_assist_contract");
const xenia_host_gpu_callback_contract = @import("xenia_host_gpu_callback_contract");
const macos_host_contract = @import("rosette_macos_host_contract");

const RTLD_LAZY: c_int = 0x1;
const RTLD_LOCAL: c_int = 0x4;
const MAX_LIBRARIES = 16;
const MAX_GUEST_LIBRARIES = 32;
const MAX_VULKAN_LOADER_CANDIDATES = 32;
const MAX_VULKAN_LOOKUP_MISSES = 128;
const VULKAN_LOADER_PATH_CAPACITY = 1024;

fn sparseVulkanSuccessLog(count: u64) bool {
    return count <= 4 or (count & (count - 1)) == 0;
}

pub const MAX_GUEST_SYMBOLS = 256;
const GUEST_SYMBOL_LOOKUP_CACHE_SIZE = 256;
const GUEST_LIBRARY_HANDLE_BASE: u64 = 0xFFFF_FC00_0000_0000;
pub const GUEST_SYMBOL_THUNK_BASE: u64 = 0xFFFF_FB00_0000_0000;
// Darwin's RTLD_DEFAULT is (void *)-2. A translated Xenia call to dlsym uses
// this handle when it asks Rosetta for an optional host ABI, so it must not be
// mistaken for one of the guest dlopen tokens above.
const RTLD_DEFAULT_HANDLE: u64 = 0xFFFF_FFFF_FFFF_FFFE;
const SYNTHETIC_PHYSICAL_DEVICE_HANDLE: u64 = 0xFFFF_F600_0000_0011;
/// The one VkDebugUtilsMessengerEXT the bridge hands out.  It is a
/// non-dispatchable handle the guest only ever passes back to
/// vkDestroyDebugUtilsMessengerEXT, so a single distinguishable value is
/// enough and makes a stray handle obvious in a log.
const SYNTHETIC_DEBUG_MESSENGER_HANDLE: u64 = 0xFFFF_F600_0000_0021;

extern fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern fn dlclose(handle: *anyopaque) c_int;
extern fn dlerror() ?[*:0]const u8;
extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

const HostWindowDescribeFn = *const fn (*rosette_gpu.WindowGeometry) callconv(.c) c_int;
pub const GuestHandleKind = enum { buffer, image, pipeline, descriptor_set, command_buffer };

const HostWindowDescribeResolver = struct {
    pub var describe: ?HostWindowDescribeFn = null;
    pub var resolved: bool = false;

    pub fn resolve() void {
        if (resolved) return;
        resolved = true;
        // RTLD_DEFAULT searches every image already loaded in this process,
        // which is where the AppKit bridge lives when it is linked.
        const rtld_default: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));
        if (dlsym(rtld_default, "rosette_macho_native_window_describe")) |address| {
            describe = @ptrCast(@alignCast(address));
        }
    }
};

const HostFrameCaptureFn = *const fn (*const frame_capture.Frame) callconv(.c) u32;
/// `rosette_macho_native_window_set_frame_counter`, resolved at run time so a
/// test build that links no window bridge still links.
const HostFrameCounterResolver = struct {
    const Fn = *const fn (u64, u64) callconv(.c) void;
    var callback: ?Fn = null;
    pub var resolved: bool = false;

    pub fn resolve() ?Fn {
        if (resolved) return callback;
        resolved = true;
        if (builtin.os.tag != .macos) return null;
        const rtld_default: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));
        if (dlsym(rtld_default, "rosette_macho_native_window_set_frame_counter")) |address| {
            callback = @ptrCast(@alignCast(address));
        }
        return callback;
    }
};

const HostFrameCaptureResolver = struct {
    pub var callback: ?HostFrameCaptureFn = null;
    pub var resolved: bool = false;

    pub fn resolve() ?HostFrameCaptureFn {
        if (resolved) return callback;
        resolved = true;
        if (builtin.os.tag != .macos) return null;
        const rtld_default: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));
        if (dlsym(rtld_default, "rosette_macho_native_window_capture_frame")) |address| {
            callback = @ptrCast(@alignCast(address));
        }
        return callback;
    }
};

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
    path: [VULKAN_LOADER_PATH_CAPACITY]u8 = [_]u8{0} ** VULKAN_LOADER_PATH_CAPACITY,
    path_length: u16 = 0,
    handle: ?*anyopaque = null,
};

const GuestLibrary = struct {
    token: u64 = 0,
    handle: ?*anyopaque = null,
    virtual_vulkan: bool = false,
    path_length: u16 = 0,
    path: [1024]u8 = [_]u8{0} ** 1024,
};

/// Native Vulkan is a host dependency, even when the guest requested a
/// loader by its Windows/Linux-style soname. macOS does not reliably search
/// `/usr/local/lib` for a bare `dlopen("libvulkan.1.dylib")`, so keep the
/// candidate policy in Rosette and make every attempted location visible in
/// the detailed run log.
const VulkanLoaderCandidates = struct {
    storage: [MAX_VULKAN_LOADER_CANDIDATES][VULKAN_LOADER_PATH_CAPACITY]u8 =
        [_][VULKAN_LOADER_PATH_CAPACITY]u8{[_]u8{0} ** VULKAN_LOADER_PATH_CAPACITY} ** MAX_VULKAN_LOADER_CANDIDATES,
    paths: [MAX_VULKAN_LOADER_CANDIDATES][]const u8 = undefined,
    count: usize = 0,

    fn add(self: *VulkanLoaderCandidates, path: []const u8) void {
        const trimmed = std.mem.trim(u8, path, " \t\r\n");
        if (trimmed.len == 0 or trimmed.len > VULKAN_LOADER_PATH_CAPACITY) return;
        for (self.paths[0..self.count]) |existing| {
            if (std.mem.eql(u8, existing, trimmed)) return;
        }
        if (self.count == self.paths.len) return;
        @memcpy(self.storage[self.count][0..trimmed.len], trimmed);
        self.paths[self.count] = self.storage[self.count][0..trimmed.len];
        self.count += 1;
    }

    fn addRoot(self: *VulkanLoaderCandidates, root: []const u8) void {
        for (macos_host_contract.native_vulkan_loader_suffixes) |suffix| {
            var joined_buffer: [VULKAN_LOADER_PATH_CAPACITY]u8 = undefined;
            if (macos_host_contract.joinPath(root, suffix, &joined_buffer)) |joined| self.add(joined);
        }
        // Also accept a caller that points directly at a `lib` directory (or
        // at a directory containing the loader), which is common for
        // VULKAN_SDK and explicit Rosette host prefixes.
        self.addSearchDirectory(root);
    }

    fn addSearchDirectory(self: *VulkanLoaderCandidates, directory: []const u8) void {
        for ([_][]const u8{ "libvulkan.1.dylib", "libvulkan.dylib" }) |basename| {
            var joined_buffer: [VULKAN_LOADER_PATH_CAPACITY]u8 = undefined;
            if (macos_host_contract.joinPath(directory, basename, &joined_buffer)) |joined| self.add(joined);
        }
    }

    fn addSearchPath(self: *VulkanLoaderCandidates, raw: []const u8) void {
        var start: usize = 0;
        while (start < raw.len) {
            const end = std.mem.indexOfScalarPos(u8, raw, start, ':') orelse raw.len;
            self.addSearchDirectory(raw[start..end]);
            if (end == raw.len) break;
            start = end + 1;
        }
    }
};

/// Whether a `vkCreateBuffer` is Xenia's built-in index buffer: the
/// primitive processor creates it device-local with exactly
/// TRANSFER_DST | INDEX_BUFFER usage (its upload twin is TRANSFER_SRC only,
/// the per-frame converted-index pool is INDEX_BUFFER only), and it holds at
/// least `GetTwoTriangleStripIndexCount(UINT16_MAX / 3)` 32-bit indices.
pub fn rectExpansionBuiltinIndexBuffer(size: u64, usage: u32) bool {
    const transfer_dst: u32 = 0x2;
    const index_buffer: u32 = 0x40;
    const rectangles: u64 = 0xFFFF / 3;
    const min_bytes: u64 = 4 * (4 * rectangles + (rectangles - 1));
    return usage == (transfer_dst | index_buffer) and size >= min_bytes;
}

/// MoltenVK settings an emulator needs, applied before the loader is opened
/// because MoltenVK reads its environment once, at its first instance.
/// A value the user already exported wins; `ROSETTE_MOLTENVK_DEFAULTS=0`
/// applies none of them.
///
/// - `MVK_CONFIG_RESUME_LOST_DEVICE=0`: report the first failed GPU command
///   buffer as device loss. Continuing after discarded EDRAM writes makes
///   Xenia consume invalid results and can repeatedly reset the system GPU.
/// - `MVK_CONFIG_FAST_MATH_ENABLED=0`: Xenia's shaders declare
///   SignedZeroInfNanPreserve and emulate Xenos NaN, infinity and signed-zero
///   rules explicitly. Metal fast math may assume none of those values exist
///   and compile the emulation away; the MoltenVK this runs on predates the
///   on-demand mode that honours the declaration.
pub const moltenvk_runtime_defaults = [_]struct { name: [*:0]const u8, value: [*:0]const u8 }{
    .{ .name = "MVK_CONFIG_RESUME_LOST_DEVICE", .value = "0" },
    .{ .name = "MVK_CONFIG_FAST_MATH_ENABLED", .value = "0" },
};

var moltenvk_runtime_defaults_applied = false;

fn applyMoltenVKRuntimeDefaults() void {
    if (moltenvk_runtime_defaults_applied) return;
    moltenvk_runtime_defaults_applied = true;
    if (std.c.getenv("ROSETTE_MOLTENVK_DEFAULTS")) |raw| {
        if (std.mem.eql(u8, std.mem.span(raw), "0")) {
            machoCapturePrint("macho-processor: MoltenVK runtime defaults: disabled by ROSETTE_MOLTENVK_DEFAULTS=0\n", .{});
            return;
        }
    }
    for (moltenvk_runtime_defaults) |setting| {
        const existing = std.c.getenv(setting.name);
        if (existing == null) _ = setenv(setting.name, setting.value, 0);
        machoCapturePrint("macho-processor: MoltenVK runtime default: {s}={s} ({s})\n", .{
            std.mem.span(setting.name),
            if (existing) |value| std.mem.span(value) else std.mem.span(setting.value),
            if (existing == null) "applied" else "kept the exported value",
        });
    }
}

/// GFXReconstruct capture of the real Vulkan stream (`gpu/vulkan/capture_plan.zig`).
/// Prepared once, before the loader opens: the loader reads its layer search
/// path, and the layer its settings, at vkCreateInstance.
const VulkanCaptureState = enum {
    not_requested,
    invalid_plan,
    layer_missing,
    output_path_invalid,
    prepared,
    loader_layer_missing,
    instance_create_failed,
    active,
};

const VulkanCapture = struct {
    plan: capture_plan.Plan = .{},
    state: VulkanCaptureState = .not_requested,
    /// Preserve the user's request when parsing or layer discovery fails.
    requested: bool = false,
    /// The layer was found and its settings exported; ensureRealInstance
    /// still has to find it in the loader's list before enabling it.
    prepared: bool = false,
    /// The real instance has the layer: every mapping is flushed before each
    /// submit, which is what assisted memory tracking records.
    active: bool = false,
    loader_layer_listed: bool = false,
    instance_layer_requested: bool = false,
    instance_create_failures: u64 = 0,
    flush_calls: u64 = 0,
    flush_failures: u64 = 0,
    layer_directory: [1024:0]u8 = [_:0]u8{0} ** 1024,
};

var vulkan_capture: VulkanCapture = .{};
var vulkan_capture_checked = false;

fn copyTerminated(buffer: *[1024:0]u8, text: []const u8) ?[]const u8 {
    if (text.len >= buffer.len) return null;
    @memcpy(buffer[0..text.len], text);
    buffer[text.len] = 0;
    return buffer[0..text.len];
}

fn captureLayerManifestIn(directory: []const u8) bool {
    var path: [1200:0]u8 = undefined;
    const joined = std.fmt.bufPrintZ(&path, "{s}/{s}", .{ directory, capture_plan.layer_manifest }) catch return false;
    return std.c.access(joined, 0) == 0;
}

/// The newest GFXReconstruct layer on this Mac: an explicit
/// ROSETTE_VULKAN_GFXR_LAYER_PATH, then the newest ~/VulkanSDK/<version>,
/// then VULKAN_SDK, then /usr/local. The newest SDK goes before VULKAN_SDK
/// because that variable commonly still names an old SDK (on 2026-10-04 it
/// named the January 2024 one) and a newer layer records more extensions.
fn findCaptureLayerDirectory(buffer: *[1024:0]u8) ?[]const u8 {
    if (std.c.getenv(capture_plan.layer_path_environment)) |raw| {
        const directory = std.mem.span(raw);
        if (captureLayerManifestIn(directory)) return copyTerminated(buffer, directory);
    }
    if (std.c.getenv("HOME")) |home| {
        var root_buffer: [1024:0]u8 = undefined;
        if (std.fmt.bufPrintZ(&root_buffer, "{s}/VulkanSDK", .{std.mem.span(home)})) |root| {
            if (std.c.opendir(root)) |directory| {
                defer _ = std.c.closedir(directory);
                var best: [256]u8 = undefined;
                var best_len: usize = 0;
                while (std.c.readdir(directory)) |entry| {
                    const name = entry.name[0..entry.namlen];
                    if (name.len > best.len or !capture_plan.versionNewer(name, best[0..best_len])) continue;
                    var candidate: [1024]u8 = undefined;
                    const layer_directory = std.fmt.bufPrint(&candidate, "{s}/{s}/macOS/share/vulkan/explicit_layer.d", .{ root, name }) catch continue;
                    if (!captureLayerManifestIn(layer_directory)) continue;
                    @memcpy(best[0..name.len], name);
                    best_len = name.len;
                }
                if (best_len != 0) {
                    var candidate: [1024]u8 = undefined;
                    if (std.fmt.bufPrint(&candidate, "{s}/{s}/macOS/share/vulkan/explicit_layer.d", .{ root, best[0..best_len] })) |found| {
                        return copyTerminated(buffer, found);
                    } else |_| {}
                }
            }
        } else |_| {}
    }
    if (std.c.getenv("VULKAN_SDK")) |raw| {
        var candidate: [1024]u8 = undefined;
        if (std.fmt.bufPrint(&candidate, "{s}/share/vulkan/explicit_layer.d", .{std.mem.span(raw)})) |directory| {
            if (captureLayerManifestIn(directory)) return copyTerminated(buffer, directory);
        } else |_| {}
    }
    const system = "/usr/local/share/vulkan/explicit_layer.d";
    if (captureLayerManifestIn(system)) return copyTerminated(buffer, system);
    return null;
}

/// Export one GFXReconstruct setting unless the user already exported it.
fn setCaptureDefault(name: [*:0]const u8, value: []const u8) void {
    if (std.c.getenv(name) != null) return;
    var buffer: [1200:0]u8 = undefined;
    const terminated = std.fmt.bufPrintZ(&buffer, "{s}", .{value}) catch return;
    _ = setenv(name, terminated, 0);
}

/// Append a capture-layer directory without hiding the user's Vulkan layer
/// paths. Older Vulkan loaders use VK_LAYER_PATH and ignore VK_ADD_LAYER_PATH;
/// newer loaders may honor both, so publish the directory to each variable.
fn appendVulkanLayerPath(name: [*:0]const u8, directory: []const u8) void {
    const existing_raw = std.c.getenv(name) orelse {
        setCaptureDefault(name, directory);
        return;
    };
    const existing = std.mem.span(existing_raw);
    var entries = std.mem.splitScalar(u8, existing, ':');
    while (entries.next()) |entry| {
        if (std.mem.eql(u8, entry, directory)) return;
    }
    var buffer: [4096:0]u8 = undefined;
    const terminated = std.fmt.bufPrintZ(&buffer, "{s}:{s}", .{ existing, directory }) catch {
        machoCapturePrint("macho-processor: VULKAN CAPTURE: could not append {s} to {s}; current_length={d} addition_length={d}\n", .{ directory, std.mem.span(name), existing.len, directory.len });
        return;
    };
    _ = setenv(name, terminated, 1);
}

fn captureRunDirectory() []const u8 {
    if (std.c.getenv("ROSETTE_RUN_DIR")) |directory| return std.mem.span(directory);
    if (std.c.getenv("ROSETTE_TRACE_PATH")) |path| return capture_plan.runDirectory(std.mem.span(path));
    if (std.c.getenv("ROSETTE_XENIA_TRACE_LOG")) |path| return capture_plan.runDirectory(std.mem.span(path));
    if (std.c.getenv("ROSETTE_XENIA_RUN_LOG")) |path| return capture_plan.runDirectory(std.mem.span(path));
    return ".";
}

fn exportedOrNone(name: [*:0]const u8) []const u8 {
    return if (std.c.getenv(name)) |value| std.mem.span(value) else "<unset>";
}

fn prepareVulkanCapture() void {
    if (vulkan_capture_checked) return;
    vulkan_capture_checked = true;
    const raw = std.c.getenv(capture_plan.environment);
    const plan = capture_plan.parse(if (raw) |value| std.mem.span(value) else null);
    vulkan_capture.plan = plan;
    vulkan_capture.requested = plan.armed() or plan.rejected;
    if (plan.rejected) {
        vulkan_capture.state = .invalid_plan;
        machoCapturePrint("macho-processor: VULKAN CAPTURE: refused {s}={s}; use 1, hotkey, hotkey:<F1-F12|TAB|CONTROL> or frames:<ascending 1-based list such as 3000,4600-4601>\n", .{ capture_plan.environment, std.mem.span(raw.?) });
        return;
    }
    if (!plan.armed()) {
        vulkan_capture.state = .not_requested;
        return;
    }
    const directory = findCaptureLayerDirectory(&vulkan_capture.layer_directory) orelse {
        vulkan_capture.state = .layer_missing;
        machoCapturePrint("macho-processor: VULKAN CAPTURE: no {s} under {s}, ~/VulkanSDK/<version>/macOS/share/vulkan/explicit_layer.d, VULKAN_SDK or /usr/local/share/vulkan/explicit_layer.d; capture disabled\n", .{ capture_plan.layer_manifest, capture_plan.layer_path_environment });
        return;
    };
    // Keep VK_LAYER_PATH for the loader used by the current MoltenVK SDK;
    // VK_ADD_LAYER_PATH is an additive hint for loaders that support it.
    appendVulkanLayerPath("VK_LAYER_PATH", directory);
    appendVulkanLayerPath("VK_ADD_LAYER_PATH", directory);

    const run_directory = captureRunDirectory();
    var file_buffer: [1100]u8 = undefined;
    var log_buffer: [1100]u8 = undefined;
    const file = std.fmt.bufPrint(&file_buffer, "{s}/rosette-vulkan.gfxr", .{run_directory}) catch {
        vulkan_capture.state = .output_path_invalid;
        machoCapturePrint("macho-processor: VULKAN CAPTURE: output path exceeds the bridge limit; run_directory={s} max_path_bytes={d}; capture disabled\n", .{ run_directory, file_buffer.len });
        return;
    };
    const log_file = std.fmt.bufPrint(&log_buffer, "{s}/gfxrecon.log", .{run_directory}) catch {
        vulkan_capture.state = .output_path_invalid;
        machoCapturePrint("macho-processor: VULKAN CAPTURE: log path exceeds the bridge limit; run_directory={s} max_path_bytes={d}; capture disabled\n", .{ run_directory, log_buffer.len });
        return;
    };
    setCaptureDefault("GFXRECON_CAPTURE_FILE", file);
    setCaptureDefault("GFXRECON_LOG_FILE", log_file);
    setCaptureDefault("GFXRECON_MEMORY_TRACKING_MODE", "assisted");
    setCaptureDefault("GFXRECON_CAPTURE_COMPRESSION_TYPE", "LZ4");
    switch (plan.mode) {
        .hotkey => {
            setCaptureDefault("GFXRECON_CAPTURE_TRIGGER", plan.key);
            setCaptureDefault("GFXRECON_CAPTURE_TRIGGER_FRAMES", "1");
        },
        .frames => setCaptureDefault("GFXRECON_CAPTURE_FRAMES", plan.frames),
        .off => unreachable,
    }
    vulkan_capture.prepared = true;
    vulkan_capture.state = .prepared;
    machoCapturePrint(
        "macho-processor: VULKAN CAPTURE: prepared mode={s} trigger={s} frames={s} layer_directory={s} file={s} log={s} memory_tracking={s}; the GFXReconstruct layer is enabled on the real instance at vkCreateInstance if the loader lists it\n",
        .{
            @tagName(plan.mode),
            exportedOrNone("GFXRECON_CAPTURE_TRIGGER"),
            exportedOrNone("GFXRECON_CAPTURE_FRAMES"),
            directory,
            exportedOrNone("GFXRECON_CAPTURE_FILE"),
            exportedOrNone("GFXRECON_LOG_FILE"),
            exportedOrNone("GFXRECON_MEMORY_TRACKING_MODE"),
        },
    );
}

const VkLayerProperties = extern struct {
    layer_name: [256]u8 = [_]u8{0} ** 256,
    spec_version: u32 = 0,
    implementation_version: u32 = 0,
    description: [256]u8 = [_]u8{0} ** 256,
};
const PfnVkEnumerateInstanceLayerProperties = *const fn (*u32, ?[*]VkLayerProperties) callconv(.c) i32;

/// Whether the native loader lists the capture layer.
fn hostLoaderListsCaptureLayer(library: *anyopaque) bool {
    const address = dlsym(library, "vkEnumerateInstanceLayerProperties") orelse return false;
    const enumerate: PfnVkEnumerateInstanceLayerProperties = @ptrCast(@alignCast(address));
    var layers: [64]VkLayerProperties = [_]VkLayerProperties{.{}} ** 64;
    var count: u32 = layers.len;
    const result = enumerate(&count, &layers);
    if (result != abi.SUCCESS and result != abi.INCOMPLETE) return false;
    for (layers[0..@min(count, layers.len)]) |*layer| {
        if (std.mem.eql(u8, driver_identity.cString(&layer.layer_name), capture_plan.layer_name)) return true;
    }
    return false;
}

fn vulkanLoaderCandidates(requested_path: []const u8) VulkanLoaderCandidates {
    applyMoltenVKRuntimeDefaults();
    prepareVulkanCapture();
    var candidates = VulkanLoaderCandidates{};
    if (std.c.getenv("ROSETTE_VULKAN_LIBRARY")) |raw| candidates.add(std.mem.span(raw));
    if (requested_path.len != 0) candidates.add(requested_path);
    if (std.c.getenv("VULKAN_SDK")) |raw| candidates.addRoot(std.mem.span(raw));
    if (std.c.getenv(macos_host_contract.host_root_environment)) |raw| candidates.addRoot(std.mem.span(raw));
    if (std.c.getenv(macos_host_contract.host_prefix_environment)) |raw| candidates.addRoot(std.mem.span(raw));
    if (std.c.getenv("DYLD_LIBRARY_PATH")) |raw| candidates.addSearchPath(std.mem.span(raw));
    for (macos_host_contract.vulkan_loader_default_paths) |path| candidates.add(path);
    return candidates;
}

fn lastDlError() []const u8 {
    const raw = dlerror() orelse return "none";
    return std.mem.span(raw);
}

/// Keep the early Vulkan negotiation trace opt-in and bounded.  Proc-address
/// results are Microsoft-ABI import stubs, so the Windows-runtime boundary
/// cannot see the subsequent native dispatch by itself.  This hook records
/// the shared forwarder's call sequence without turning normal command
/// traffic into a log stream.
/// Read once: this runs on every Vulkan dispatch, and `getenv` walks the
/// environment under libc's lock (4% of a replayed draw stream's CPU).
var vulkan_dispatch_trace_setting = std.atomic.Value(u8).init(0);
pub var vulkan_dispatch_trace_cached = true; // internal control for offline comparison
fn vulkanDispatchTraceEnabled() bool {
    const known = if (vulkan_dispatch_trace_cached) vulkan_dispatch_trace_setting.load(.monotonic) else 0;
    if (known != 0) return known == 2;
    const raw = std.c.getenv("ROSETTE_ELF_GRAPHICS_TRACE");
    const value = if (raw) |pointer| std.mem.span(pointer) else "";
    const enabled = std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "yes");
    vulkan_dispatch_trace_setting.store(if (enabled) 2 else 1, .monotonic);
    return enabled;
}

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
    get_physical_device_win32_presentation_support,
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
    rosette_heap_allocator_abi_version,
    rosette_heap_select,
    rosette_ppc_host_available,
    rosette_ppc_host_identity,
    rosette_ppc_bind_context,
    rosette_ppc_release_context,
    rosette_ppc_set_recompiler_enabled,
    rosette_ppc_recompiler_stats,
    rosette_ppc_invalidate_range,
    rosette_ppc_execute,
    rosette_xenia_launch_assist_abi_version,
    rosette_xenia_launch_assist_schema_version,
    rosette_xenia_launch_assist_query,
    rosette_xenia_launch_assist_report,
    rosette_xenia_host_gpu_callback_abi_version,
    rosette_xenia_host_gpu_callback_schema_version,
    rosette_xenia_host_gpu_callback_query,
    rosette_xenia_host_gpu_callback_report,
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
    /// Loader lookup logging is keyed by the stable guest thunk rather than
    /// by call count. The loader asks for the same function on every frame;
    /// keeping that traffic out of the detailed log prevents healthy command
    /// loops from looking like a hang.
    loader_lookup_logged: bool = false,
    loader_lookup_repeats: u64 = 0,
};

const GuestSymbolLookupCacheEntry = struct {
    library_token: u64 = 0,
    name_hash: u64 = 0,
    symbol_index: u16 = 0,
    name_length: u8 = 0,
};

fn guestSymbolLookupCacheIndex(library_token: u64, name_hash: u64) usize {
    const mixed = name_hash ^ (library_token *% 0x9E37_79B9_7F4A_7C15);
    return @intCast(mixed % GUEST_SYMBOL_LOOKUP_CACHE_SIZE);
}

const VulkanLookupMiss = struct {
    library_token: u64 = 0,
    name_hash: u64 = 0,
    name_length: u8 = 0,
    name: [95]u8 = [_]u8{0} ** 95,
    repeats: u64 = 0,
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
    memory_flags: u32 = 0,
    memory_flags_known: bool = false,
    native_alias_base: u64 = 0,
    // Last CPU-visible contents. Changed-byte publication never overwrites
    // unrelated GPU writes with an unchanged guest shadow.
    shadow_baseline: ?[]u8 = null,

    pub fn releaseBaseline(self: *VulkanMemoryAllocation) void {
        if (self.shadow_baseline) |bytes| std.heap.c_allocator.free(bytes);
        self.shadow_baseline = null;
    }
};

/// Overflow-safe half-open range containment used at every synthetic/native
/// memory boundary. Subtraction after the lower-bound check avoids accepting a
/// wrapped end address as a valid Vulkan allocation or mapped range.
fn rangeContains(base: u64, length: u64, offset: u64, size: u64) bool {
    if (offset < base) return false;
    const relative = offset - base;
    if (relative > length) return false;
    return size <= length - relative;
}

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

const DescriptorBindRejectReason = enum(u8) {
    none,
    device_lost,
    command_buffer_unmapped,
    pipeline_layout_unmapped,
    set_count_exceeds_limit,
    descriptor_set_array_unreadable,
    descriptor_set_unmapped,
    dynamic_offset_count_exceeds_limit,
    dynamic_offset_array_unreadable,
    native_entry_point_missing,
    count,
};

const DescriptorBindAdmission = struct {
    entries: u64 = 0,
    forwarded: u64 = 0,
    rejected: u64 = 0,
    rejected_by_reason: [@intFromEnum(DescriptorBindRejectReason.count)]u64 =
        [_]u64{0} ** @intFromEnum(DescriptorBindRejectReason.count),
    last_reason: DescriptorBindRejectReason = .none,
    last_command_buffer: u64 = 0,
    last_layout: u64 = 0,
    last_set_count: u64 = 0,
    last_sets: u64 = 0,
    last_dynamic_count: u64 = 0,
    last_dynamic_offsets: u64 = 0,
    last_unmapped_handle: u64 = 0,
};

const VulkanCommandRejectReason = enum {
    none,
    device_lost,
    command_buffer_unmapped,
    native_entry_point_missing,
    argument_marshalling_refused,
    unimplemented_abi,
};

const VulkanCommandAdmission = struct {
    entries: u64 = 0,
    forwarded: u64 = 0,
    rejected: u64 = 0,
    last_reason: VulkanCommandRejectReason = .none,
    last_refusal_line: u32 = 0,
    /// Six SysV registers followed by the first six stack arguments. These
    /// are the typed, normalized guest values, never real driver pointers.
    last_arguments: [12]u64 = @splat(0),
};

/// Live image/buffer provenance records. This is a live-object budget, not a
/// lifetime allocation count: vkDestroyImage/vkDestroyBuffer return slots to
/// the table. The old 128-entry table was exhausted by Halo 3 while the real
/// Vulkan driver was still accepting image creation, so Rosette started
/// returning unwritten guest handles and the first later draw could not be
/// trusted. Keep the bound finite for diagnosability, but make it large enough
/// for a long-lived title's scene and staging-resource churn.
const MAX_VULKAN_RESOURCES = 4096;
const MAX_REAL_MEMORY = 512;
// These maps must not become the next lower ceiling than the provenance
// table. A successful native create is only useful while both the native
// reverse map and the detailed resource record can be retained.
const MAX_REAL_BUFFERS = MAX_VULKAN_RESOURCES;
const MAX_REAL_IMAGES = MAX_VULKAN_RESOURCES;
const MAX_REAL_SAMPLERS = 256;
const MAX_REAL_FENCES = 256;
const MAX_REAL_SEMAPHORES = 256;
const MAX_REAL_RENDER_PASSES = 256;
const MAX_REAL_FRAMEBUFFERS = 256;
// Halo 3 has already produced more than 2,000 graphics-pipeline objects in a
// single run.  Keep the native reverse map and the detailed pipeline records
// above that observed live/cumulative working set so a valid pipeline does not
// become an "unknown_pipeline" draw merely because the old 1,024-row table
// was the first bounded structure to fill.  This remains bounded and is much
// smaller than the resource provenance budget.
const MAX_REAL_PIPELINES = 4096;
const MAX_REAL_SHADER_MODULES = 1024;
const MAX_RECT_EXPAND_MODULES = 256;
const MAX_RECT_EXPAND_PIPELINES = 2048;
/// One row per distinct `vkCreate*`/`vkAllocate*` entry point the guest
/// reaches. Bounded because the set is bounded by the API, not by the run.
const MAX_VULKAN_CREATE_LEDGER = 48;
const VULKAN_CREATE_NAME_BYTES = 40;

const VulkanCreateLedgerEntry = struct {
    name: [VULKAN_CREATE_NAME_BYTES]u8 = [_]u8{0} ** VULKAN_CREATE_NAME_BYTES,
    name_len: u8 = 0,
    attempts: u64 = 0,
    published: u64 = 0,
    /// Refused before the driver was called: a bad output pointer, an
    /// exhausted provenance table, a create-info Rosette would not marshal.
    /// These leave no VkResult of their own, so without this column they are
    /// invisible in every counter the run prints.
    refused_before_driver: u64 = 0,
    /// The driver was called and returned a non-success VkResult.
    driver_failures: u64 = 0,
    last_result: i32 = 0,

    pub fn nameText(self: *const VulkanCreateLedgerEntry) []const u8 {
        return self.name[0..self.name_len];
    }
};

const MAX_REAL_DESCRIPTOR_SET_LAYOUTS = 256;
const MAX_REAL_PIPELINE_LAYOUTS = 256;
const MAX_REAL_DESCRIPTOR_POOLS = 64;
// Descriptor sets are the one object family a long-running title can create
// continuously without creating a new pool every frame.  The old 1024-entry
// ceiling was reached by the overnight run even though the native driver was
// still accepting allocations.  Keep the reverse map bounded, but give the
// guest enough room for a realistic long-lived pool; exhaustion is still
// converted to VK_ERROR_OUT_OF_HOST_MEMORY and reported rather than panicking.
const MAX_REAL_DESCRIPTOR_SETS = 16_384;
const MAX_REAL_COMMAND_POOLS = 32;
const MAX_REAL_COMMAND_BUFFERS = 256;
const MAX_REAL_SWAPCHAINS = 16;
const MAX_REAL_BUFFER_VIEWS = 4096;
const MAX_REAL_IMAGE_VIEWS = 4096;
const MAX_REAL_QUERY_POOLS = 256;
const MAX_REAL_PIPELINE_CACHES = 32;
const MAX_REAL_DESCRIPTOR_UPDATE_TEMPLATES = 128;
const MAX_REAL_QUEUES = 64;
/// Bounds for guest-provided VkDeviceCreateInfo arrays. These are bridge
/// storage limits, not values to silently clamp: dropping a queue or extension
/// changes the device the guest believes it created.
const MAX_DEVICE_QUEUE_INFOS = 16;
const MAX_QUEUES_PER_CREATE_INFO = 64;
const MAX_DEVICE_EXTENSION_NAMES = 96;
const MAX_INSTANCE_EXTENSION_NAMES = 64;
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
const HandleMap = gpu_vulkan.handle_map_registry.Entry;

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
    /// Family used by the guest graphics queue.  The optional pixel probe
    /// records on that same family so the readback never introduces a queue
    /// ownership transfer that the guest did not ask for.
    graphics_queue_family_index: u32 = 0,
    /// Queue family properties.
    queue_family_properties: [16]abi.QueueFamilyProperties = [_]abi.QueueFamilyProperties{.{}} ** 16,
    /// Device-level function pointers resolved after device creation.
    fn_ptrs: DeviceFnPtrs = .{},
    /// Device extensions admitted specifically for bridge-owned forwarding.
    /// Function-pointer presence alone is not enough: promoted commands can
    /// be exposed by a loader while their enabling extension/feature was not
    /// part of this device's creation chain. Proc-address queries use these
    /// bits to preserve Vulkan's null-pointer contract.
    sync2_enabled: bool = false,
    dynamic_rendering_enabled: bool = false,
    extended_dynamic_state_enabled: bool = false,
    extended_dynamic_state2_enabled: bool = false,
    push_descriptor_enabled: bool = false,
    conditional_rendering_enabled: bool = false,

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
    queue_family_indices: [MAX_REAL_QUEUES]u32 = @splat(abi.QUEUE_FAMILY_IGNORED),

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

    pub fn swapchainRecord(self: *const RealVulkanState, synthetic: u64) ?*const SwapchainRecord {
        if (synthetic == 0) return null;
        for (&self.swapchain_records) |*record| {
            if (record.synthetic == synthetic) return record;
        }
        return null;
    }

    pub fn mutableSwapchainRecord(self: *RealVulkanState, synthetic: u64) ?*SwapchainRecord {
        if (synthetic == 0) return null;
        for (&self.swapchain_records) |*record| {
            if (record.synthetic == synthetic) return record;
        }
        return null;
    }

    pub fn allocateSwapchainRecord(self: *RealVulkanState, synthetic: u64, real: abi.SwapchainKHR) ?*SwapchainRecord {
        for (&self.swapchain_records) |*record| {
            if (record.synthetic == 0) {
                record.* = .{ .synthetic = synthetic, .real = real };
                return record;
            }
        }
        return null;
    }

    pub fn releaseSwapchainImageHandles(self: *RealVulkanState, record: *const SwapchainRecord) void {
        for (record.image_handles) |image| {
            if (image != 0) _ = HandleMap.remove(&self.image_map, image);
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

    pub fn descriptorUpdateTemplateIndex(self: *const RealVulkanState, synthetic: u64) ?usize {
        for (&self.descriptor_update_template_map, 0..) |*entry, index| {
            const mapped = HandleMap.snapshot(entry) orelse continue;
            if (mapped.synthetic == synthetic and mapped.real != 0) return index;
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
    /// Native requirements are authoritative for real resources. The
    /// modelled size above is only an estimate for fallback resources and
    /// must never approve a real bind when the driver gave us a larger
    /// requirement.
    required_size: u64 = 0,
    row_pitch_bytes: u64 = 0,
    memory: u64 = 0,
    memory_offset: u64 = 0,
};

/// Bounded render-target provenance.  Vulkan command buffers do not carry a
/// "this writes the swapchain" bit; the target is reached through image views
/// and framebuffers (or through dynamic-rendering attachment views).  Keep the
/// guest handles here so the provenance can be resolved again when the command
/// is recorded, without storing host pointers or allocating in the hot path.
const MAX_TRACKED_TARGET_ATTACHMENTS: usize = 8;
const MAX_TRACKED_DESCRIPTOR_IMAGES: usize = 16;
const MAX_TRACKED_RESOURCE_TRANSFERS: usize = 16;
const MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND: usize = 32;
// Provenance is intentionally cheaper than the authoritative reverse map.
// Once this table fills, descriptor handles remain reclaimable through the
// pool owner stored in HandleMap; only detailed image provenance is bounded.
// The native reverse map can retain 16,384 sets, but each detailed row also
// carries bounded image and texel metadata and Forwarder is stack-constructed
// by several small tests.  Four thousand rows cover the long-run allocation
// frontier observed in Halo 3 without moving the diagnostic object itself
// onto a multi-megabyte stack cliff; if a title exceeds this bound, the
// classified overflow remains explicit instead of becoming a panic.
const MAX_TRACKED_DESCRIPTOR_SETS: usize = 4096;
const VK_ATTACHMENT_LOAD_OP_CLEAR: u32 = 1;
// Vulkan enum values used by the bounded graphics-state audit.  Keeping these
// local avoids turning a diagnostic into a second Vulkan registry while still
// making the two presentation topologies legible in the report.
const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: u32 = 3;
const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP: u32 = 4;
const VK_DYNAMIC_STATE_VIEWPORT: u32 = 0;
const VK_DYNAMIC_STATE_SCISSOR: u32 = 1;
const VK_SHADER_STAGE_VERTEX_BIT: u32 = 0x0000_0001;
const VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT: u32 = 0x0000_0002;
const VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT: u32 = 0x0000_0004;
const VK_PIPELINE_BIND_POINT_GRAPHICS: u32 = 0;

const RECT_EXPAND_COMMAND_STATES = 8;
const RectExpandCommandState = struct {
    command_buffer: u64 = 0,
    pipeline: u64 = 0,
    index_buffer: u64 = 0,
    index_offset: u64 = 0,
    index_type: u32 = 0,
    marked_pipeline: bool = false,
    builtin_indices: bool = false,
};

const RectForeignIndexSample = struct {
    command_buffer: u64 = 0,
    pipeline: u64 = 0,
    index_buffer: u64 = 0,
    index_offset: u64 = 0,
    index_type: u32 = 0,
    index_count: u32 = 0,
    first_index: u32 = 0,
    vertex_offset: i32 = 0,
    instance_count: u32 = 0,
};

const TrackedImageView = struct {
    synthetic: u64 = 0,
    image: u64 = 0,
    format: u32 = 0,
    components: [4]u32 = @splat(0),
    base_mip: u32 = 0,
    base_layer: u32 = 0,
    view_type: u32 = 0,
};

const TrackedDescriptorImage = struct {
    binding: u32 = 0,
    array_element: u32 = 0,
    image: u64 = 0,
    image_view: u64 = 0,
};

const TrackedDescriptorSet = struct {
    synthetic: u64 = 0,
    pool: u64 = 0,
    image_count: u8 = 0,
    unknown_image_views: bool = false,
    images: [MAX_TRACKED_DESCRIPTOR_IMAGES]TrackedDescriptorImage = [_]TrackedDescriptorImage{.{}} ** MAX_TRACKED_DESCRIPTOR_IMAGES,
    texel_count: u8 = 0,
    texels: [8]TrackedTexelBinding = @splat(.{}),
};

const TrackedTexelBinding = struct { binding: u32 = 0, element: u32 = 0, view: u64 = 0 };
const TrackedBufferView = struct {
    synthetic: u64 = 0,
    buffer: u64 = 0,
    format: u32 = 0,
    offset: u64 = 0,
    range: u64 = 0,
    observed: bool = false,
    last_hash: u64 = 0,
};

const TrackedImageTransfer = struct {
    source: u64 = 0,
    destination: u64 = 0,
    kind: rosette_gpu.PresentTransferKind = .none,
};

const TrackedCommandDescriptorSet = struct {
    set_index: u32 = 0,
    synthetic: u64 = 0,
};

const TrackedFramebuffer = struct {
    synthetic: u64 = 0,
    attachment_count: u8 = 0,
    attachments: [MAX_TRACKED_TARGET_ATTACHMENTS]u64 = [_]u64{0} ** MAX_TRACKED_TARGET_ATTACHMENTS,
};

const fsi_chain = gpu_vulkan.fsi.chain;
const fsi_timing = gpu_vulkan.fsi.timing;
const fsi_contract = gpu_vulkan.fsi.contract;

const fsi_recording_capacity = 32;
const fsi_command_buffer_directory_capacity = 512;
const fsi_render_pass_capacity = 64;
const fsi_segment_command_capacity = 256;
const fsi_block_reason_count = @typeInfo(fsi_chain.Block).@"enum".fields.len;

/// How a vkCmd* call relates to splitting an FSI recording
/// (`gpu/vulkan/fsi/chain.zig`). `recorded` commands are followed by the
/// shadow or by the recording itself, `neutral` ones leave no state a later
/// draw reads, and anything else makes the recording unsplittable until the
/// guest begins it again.
const FsiCommandClass = enum { draw, recorded, neutral, blocks };

const fsi_draw_commands = [_][]const u8{
    "vkCmdDraw",              "vkCmdDrawIndexed",              "vkCmdDrawIndirect",         "vkCmdDrawIndexedIndirect",
    "vkCmdDrawIndirectCount", "vkCmdDrawIndexedIndirectCount", "vkCmdDrawIndirectCountKHR", "vkCmdDrawIndexedIndirectCountKHR",
};
const fsi_recorded_commands = [_][]const u8{
    "vkCmdBindPipeline",               "vkCmdBindDescriptorSets",  "vkCmdPushConstants",       "vkCmdSetViewport",
    "vkCmdSetScissor",                 "vkCmdSetBlendConstants",   "vkCmdSetDepthBias",        "vkCmdSetDepthBounds",
    "vkCmdSetStencilCompareMask",      "vkCmdSetStencilWriteMask", "vkCmdSetStencilReference", "vkCmdBindIndexBuffer",
    "vkCmdBindVertexBuffers",          "vkCmdBeginRenderPass",     "vkCmdEndRenderPass",       "vkCmdEndRenderPass2",
    "vkCmdEndRenderPass2KHR",          "vkCmdBeginQuery",          "vkCmdEndQuery",            "vkCmdBeginConditionalRenderingEXT",
    "vkCmdEndConditionalRenderingEXT",
};
const fsi_neutral_commands = [_][]const u8{
    "vkCmdDispatch",               "vkCmdDispatchIndirect",  "vkCmdDispatchBase",         "vkCmdCopyBuffer",
    "vkCmdCopyImage",              "vkCmdCopyBufferToImage", "vkCmdCopyImageToBuffer",    "vkCmdBlitImage",
    "vkCmdFillBuffer",             "vkCmdUpdateBuffer",      "vkCmdResolveImage",         "vkCmdClearColorImage",
    "vkCmdClearDepthStencilImage", "vkCmdClearAttachments",  "vkCmdPipelineBarrier",      "vkCmdPipelineBarrier2",
    "vkCmdPipelineBarrier2KHR",    "vkCmdResetQueryPool",    "vkCmdCopyQueryPoolResults", "vkCmdWriteTimestamp",
    "vkCmdExecuteCommands",        "vkCmdSetEvent",          "vkCmdResetEvent",           "vkCmdWaitEvents",
};

fn fsiCommandClass(name_hash: u64, name: []const u8) FsiCommandClass {
    @setEvalBranchQuota(20_000);
    inline for (fsi_draw_commands) |entry| {
        if (name_hash == (comptime vulkanNameHash(entry)) and std.mem.eql(u8, name, entry)) return .draw;
    }
    inline for (fsi_recorded_commands) |entry| {
        if (name_hash == (comptime vulkanNameHash(entry)) and std.mem.eql(u8, name, entry)) return .recorded;
    }
    inline for (fsi_neutral_commands) |entry| {
        if (name_hash == (comptime vulkanNameHash(entry)) and std.mem.eql(u8, name, entry)) return .neutral;
    }
    return .blocks;
}

const FsiCommandBufferEntry = struct {
    guest: u64 = 0,
    guest_pool: u64 = 0,
    primary: bool = false,
};

/// What the GPU-timing watcher needs to wait on and reset a fence
/// (`gpu/vulkan/fsi/timing.zig`).
const FsiFenceContext = struct {
    device: abi.Device = null,
    wait: ?abi.PfnWaitForFences = null,
    reset: ?abi.PfnResetFences = null,
};

/// One VkSubmitInfo the guard builds from a guest submission: the guest's
/// batch boundaries and semaphores, cut again at every chunk boundary.
const FsiSegment = struct {
    wait_count: u32 = 0,
    wait_semaphores: ?[*]const abi.Semaphore = null,
    wait_stages: ?[*]const u32 = null,
    signal_count: u32 = 0,
    signal_semaphores: ?[*]const abi.Semaphore = null,
    command_count: u32 = 0,
    draws: u32 = 0,
    scissor_pixels: u64 = 0,
    max_draw_scissor_pixels: u64 = 0,
    sample_work: u64 = 0,
    max_draw_sample_work: u64 = 0,
    guest_command_buffer: u64 = 0,
    segment_in_guest: u16 = 0,
    guest_segments: u16 = 0,
    first_pipeline: u64 = 0,
    last_pipeline: u64 = 0,
    isolated: bool = false,
};

/// Two adjacent chunks from one guest command buffer can share the host
/// `vkQueueSubmit` call while remaining separate VkSubmitInfo batches (and,
/// on MoltenVK, separate Metal command buffers). Do not coalesce across a
/// guest wait/signal boundary, a mixed command-buffer batch, or an ambiguous
/// segment identity.
fn fsiCanCoalesceSegments(first: FsiSegment, second: FsiSegment) bool {
    return !first.isolated and !second.isolated and first.guest_command_buffer != 0 and
        first.guest_command_buffer == second.guest_command_buffer and
        first.command_count == 1 and second.command_count == 1 and
        @as(u32, first.segment_in_guest) + 1 == second.segment_in_guest and
        first.signal_count == 0 and second.wait_count == 0;
}

/// Rosette's guard for Xenia's FSI render backend (`gpu/vulkan/fsi`): FSI
/// command buffers are split into chunks that each become their own Metal
/// command buffer, bounded by measured time, draw count, scissor area, and
/// in-flight queue depth to reduce macOS GPU watchdog risk.
/// Allocated on the first vkAllocateCommandBuffers; armed only by Xenia's FSI
/// render pass, so a host render target run never splits or times anything.
const FsiGuard = struct {
    split_profile: @import("gpu").vulkan.fsi.split_decision.Profile = .{},
    protected_batching_enabled: bool = true,
    armed: bool = false,
    directory: [fsi_command_buffer_directory_capacity]FsiCommandBufferEntry = [_]FsiCommandBufferEntry{.{}} ** fsi_command_buffer_directory_capacity,
    directory_overflow: u64 = 0,
    recordings: [fsi_recording_capacity]fsi_chain.Recording = [_]fsi_chain.Recording{.{}} ** fsi_recording_capacity,
    recording_overflow: u64 = 0,
    splittable_render_passes: [fsi_render_pass_capacity]u64 = [_]u64{0} ** fsi_render_pass_capacity,
    splittable_render_pass_count: usize = 0,
    splittable_render_pass_overflow: u64 = 0,
    xenia_fsi_render_passes: u64 = 0,
    xenia_fsi_framebuffers: u64 = 0,
    framebuffer_width: u32 = 0,
    framebuffer_height: u32 = 0,
    chunk_pool: fsi_chain.ChunkPool = .{},
    command_pool: abi.CommandPool = 0,
    command_pool_failed: bool = false,
    monitor: fsi_timing.Monitor = .{},
    monitor_started: bool = false,
    monitor_start_failed: bool = false,
    fence_context: FsiFenceContext = .{},
    fsi_draws: u64 = 0,
    /// FSI continuation mutates Vulkan command-buffer/render-pass state. Keep
    /// that boundary serialized with all queued draw/bind work so MoltenVK
    /// never encodes a split draw concurrently with ending or reopening its
    /// pass (the observed crash was MVKCmdDrawIndexed::encode -> getSubpass).
    serialized_split_boundaries: u64 = 0,
    split_worker_drains: u64 = 0,
    /// Guest FSI recordings refused before an over-budget draw could be
    /// submitted without a safe continuation boundary.
    recording_aborts: u64 = 0,
    aborted_fsi_draws: u64 = 0,
    /// The pixels an FSI draw can touch: its scissor clipped to the
    /// 8192-square render area. Nothing else bounds an interlocked
    /// triangle, so these say whether a slow chunk drew far outside the
    /// picture.
    max_scissor_pixels: u64 = 0,
    oversized_scissor_draws: u64 = 0,
    unscissored_draws: u64 = 0,
    splits: u64 = 0,
    split_failures: u64 = 0,
    replay_missing_functions: u64 = 0,
    blocked_splits: [fsi_block_reason_count]u64 = [_]u64{0} ** fsi_block_reason_count,
    expanded_submits: u64 = 0,
    segments_submitted: u64 = 0,
    driver_queue_submit_calls: u64 = 0,
    driver_submit_infos: u64 = 0,
    coalesced_submit_groups: u64 = 0,
    max_segments_per_submit: u64 = 0,
    untimed_segments: u64 = 0,
    timing_fences_created: u64 = 0,
    timing_fence_failures: u64 = 0,
    slow_chunk_submit_aborts: u64 = 0,
    escalation_dumps: u64 = 0,
};
/// Re-issues an FSI recording's bound state into a new chunk
/// (`fsi_chain.Shadow.replay`).
const FsiReplayOps = struct {
    fns: *const DeviceFnPtrs,
    command_buffer: abi.CommandBuffer,
    missing: u32 = 0,

    pub fn bindPipeline(self: *FsiReplayOps, bind_point: u32, pipeline: u64) void {
        const function = self.fns.cmd_bind_pipeline orelse return self.noteMissing();
        function(self.command_buffer, bind_point, pipeline);
    }
    pub fn bindDescriptorSets(self: *FsiReplayOps, bind: *const fsi_chain.DescriptorBind) void {
        const function = self.fns.cmd_bind_descriptor_sets orelse return self.noteMissing();
        function(self.command_buffer, bind.bind_point, bind.layout, bind.first_set, bind.set_count, &bind.sets, bind.dynamic_count, if (bind.dynamic_count == 0) null else &bind.dynamic_offsets);
    }
    pub fn pushConstants(self: *FsiReplayOps, write: *const fsi_chain.PushConstants) void {
        const function = self.fns.cmd_push_constants orelse return self.noteMissing();
        function(self.command_buffer, write.layout, write.stages, write.offset, write.size, if (write.size == 0) null else &write.bytes);
    }
    pub fn setViewports(self: *FsiReplayOps, first: u32, viewports: []const abi.Viewport) void {
        const function = self.fns.cmd_set_viewport orelse return self.noteMissing();
        function(self.command_buffer, first, @intCast(viewports.len), viewports.ptr);
    }
    pub fn setScissors(self: *FsiReplayOps, first: u32, scissors: []const abi.Rect2D) void {
        const function = self.fns.cmd_set_scissor orelse return self.noteMissing();
        function(self.command_buffer, first, @intCast(scissors.len), scissors.ptr);
    }
    pub fn setBlendConstants(self: *FsiReplayOps, constants: *const [4]f32) void {
        const function = self.fns.cmd_set_blend_constants orelse return self.noteMissing();
        function(self.command_buffer, constants);
    }
    pub fn setDepthBias(self: *FsiReplayOps, constant: f32, clamp: f32, slope: f32) void {
        const function = self.fns.cmd_set_depth_bias orelse return self.noteMissing();
        function(self.command_buffer, constant, clamp, slope);
    }
    pub fn setDepthBounds(self: *FsiReplayOps, min: f32, max: f32) void {
        const function = self.fns.cmd_set_depth_bounds orelse return self.noteMissing();
        function(self.command_buffer, min, max);
    }
    pub fn setStencilCompareMask(self: *FsiReplayOps, face: u32, value: u32) void {
        const function = self.fns.cmd_set_stencil_compare_mask orelse return self.noteMissing();
        function(self.command_buffer, face, value);
    }
    pub fn setStencilWriteMask(self: *FsiReplayOps, face: u32, value: u32) void {
        const function = self.fns.cmd_set_stencil_write_mask orelse return self.noteMissing();
        function(self.command_buffer, face, value);
    }
    pub fn setStencilReference(self: *FsiReplayOps, face: u32, value: u32) void {
        const function = self.fns.cmd_set_stencil_reference orelse return self.noteMissing();
        function(self.command_buffer, face, value);
    }
    pub fn bindIndexBuffer(self: *FsiReplayOps, buffer: u64, offset: u64, index_type: u32) void {
        const function = self.fns.cmd_bind_index_buffer orelse return self.noteMissing();
        function(self.command_buffer, buffer, offset, index_type);
    }
    pub fn bindVertexBuffers(self: *FsiReplayOps, first: u32, buffers: []const u64, offsets: []const u64) void {
        const function = self.fns.cmd_bind_vertex_buffers orelse return self.noteMissing();
        function(self.command_buffer, first, @intCast(buffers.len), buffers.ptr, offsets.ptr);
    }
    pub fn noteMissing(self: *FsiReplayOps) void {
        self.missing += 1;
    }

    /// Check replay prerequisites before ending the live guest recording. A
    /// missing function can no longer be discovered after the old command
    /// buffer has been closed without losing guest state.
    pub fn supports(self: *const FsiReplayOps, shadow: *const fsi_chain.Shadow) bool {
        if (shadow.pipelines[0] != 0 and self.fns.cmd_bind_pipeline == null) return false;
        if (shadow.pipelines[1] != 0 and self.fns.cmd_bind_pipeline == null) return false;
        if (shadow.descriptor_bind_count != 0 and self.fns.cmd_bind_descriptor_sets == null) return false;
        if (shadow.push_constant_count != 0 and self.fns.cmd_push_constants == null) return false;
        if (shadow.viewport_mask != 0 and self.fns.cmd_set_viewport == null) return false;
        if (shadow.scissor_mask != 0 and self.fns.cmd_set_scissor == null) return false;
        if (shadow.blend_constants != null and self.fns.cmd_set_blend_constants == null) return false;
        if (shadow.depth_bias != null and self.fns.cmd_set_depth_bias == null) return false;
        if (shadow.depth_bounds != null and self.fns.cmd_set_depth_bounds == null) return false;
        if ((shadow.stencil_compare_mask[0] != null or shadow.stencil_compare_mask[1] != null) and self.fns.cmd_set_stencil_compare_mask == null) return false;
        if ((shadow.stencil_write_mask[0] != null or shadow.stencil_write_mask[1] != null) and self.fns.cmd_set_stencil_write_mask == null) return false;
        if ((shadow.stencil_reference[0] != null or shadow.stencil_reference[1] != null) and self.fns.cmd_set_stencil_reference == null) return false;
        if (shadow.index != null and self.fns.cmd_bind_index_buffer == null) return false;
        if (shadow.vertex_mask != 0 and self.fns.cmd_bind_vertex_buffers == null) return false;
        return true;
    }
};

fn fsiFenceWait(context: *anyopaque, fence: u64, timeout_ns: u64) fsi_timing.WaitResult {
    const fences: *FsiFenceContext = @ptrCast(@alignCast(context));
    const wait = fences.wait orelse return .failed;
    const handles = [_]abi.Fence{fence};
    return switch (wait(fences.device, 1, &handles, 1, timeout_ns)) {
        abi.SUCCESS => .signaled,
        abi.TIMEOUT => .timeout,
        else => .failed,
    };
}

fn fsiFenceReset(context: *anyopaque, fence: u64) bool {
    const fences: *FsiFenceContext = @ptrCast(@alignCast(context));
    const reset = fences.reset orelse return false;
    const handles = [_]abi.Fence{fence};
    return reset(fences.device, 1, &handles) == abi.SUCCESS;
}

fn fsiFenceNow(context: *anyopaque) u64 {
    _ = context;
    return transport_timing.nowNs();
}

/// Printed on the timing watcher's thread while the chunk is still running.
fn fsiWatcherReport(report: fsi_timing.Report) void {
    const meaning = switch (report.kind) {
        .risk => "submission-to-observation latency crossed the risk bound; draw ceilings remain reduced for this run; verified shader bounds and thousands of representative fast completions can recover only the original conservative sample quantum",
        .severe => if (report.completion_observed) "completion was observed beyond the severe bound; work returns to minimum and only a later protected recovery streak may earn the original conservative quantum; a completed fence alone does not pause the queue" else "an outstanding timing group crossed the severe bound; new FSI submissions wait until all outstanding fences complete and reset successfully, then resume at minimum work; draw cap stays pinned and only a later protected recovery streak may earn the original conservative work quantum; actual fence failures stop the run. Splitting cannot subdivide a single oversized draw",
        .failed => if (report.failure_stage == .reset_fences) "vkResetFences failed after completion; the fence is not recycled and later FSI queue submissions are stopped" else "vkWaitForFences failed on the timing watcher, which normally means the Metal-backed Vulkan device was lost; subsequent FSI submissions are stopped",
    };
    machoCapturePrint(
        "macho-processor: VULKAN FSI WATCHDOG {s}: serial={d} queue_submit={d} guest_command_buffer=0x{x} segment={d}/{d} timing_group_submit_infos={d} fsi_draws={d} scissor_pixels={d} max_draw_scissor_pixels={d} sample_work={d} max_draw_sample_work={d} running_ms={d} completion_observed={} cap_now={d} outstanding_groups={d} pipelines(first/last)=0x{x}/0x{x} timing_basis=submit_to_fence_observation_upper_bound; {s}\n",
        .{ @tagName(report.kind), report.entry.serial, report.entry.queue_submit, report.entry.guest_command_buffer, report.entry.segment + 1, report.entry.segments, report.entry.submit_infos, report.entry.draws, report.entry.scissor_pixels, report.entry.max_draw_scissor_pixels, report.entry.sample_work, report.entry.max_draw_sample_work, report.running_ns / 1_000_000, report.completion_observed, report.cap, report.outstanding, report.entry.first_pipeline_hash, report.entry.last_pipeline_hash, meaning },
    );
}

const TrackedRenderPass = struct {
    synthetic: u64 = 0,
    /// A color attachment with LOAD_OP_CLEAR writes its image as part of
    /// vkCmdBeginRenderPass, before any explicit draw or clear command. Keep
    /// this separate from command-shape counters so present provenance does
    /// not mistake a successful begin/end pair for actual image content.
    color_load_clear: bool = false,
    resolve_count: u8 = 0,
    resolve_sources: [MAX_TRACKED_TARGET_ATTACHMENTS]u32 = [_]u32{0} ** MAX_TRACKED_TARGET_ATTACHMENTS,
    resolve_destinations: [MAX_TRACKED_TARGET_ATTACHMENTS]u32 = [_]u32{0} ** MAX_TRACKED_TARGET_ATTACHMENTS,
};

/// The command stream can be completely accepted by Vulkan and still draw the
/// wrong shape if one of the small pieces of graphics state is translated
/// incorrectly.  Keep the state that determines Xenia's two presentation
/// draws with the command buffer rather than trying to infer it from a
/// successful present afterward.  This is deliberately bounded and only
/// populated when ROSETTE_ELF_GRAPHICS_STATE_DUMP is enabled.
const GraphicsStateTrace = struct {
    pipeline_guest: u64 = 0,
    pipeline_real: u64 = 0,
    pipeline_original_real: u64 = 0,
    pipeline_layout_real: u64 = 0,
    pipeline_repair_real: u64 = 0,
    pipeline_guest_output_candidate: bool = false,
    pipeline_repair_applied: bool = false,
    pipeline_bind_point: u32 = 0,
    pipeline_bound: bool = false,
    pipeline_topology: u32 = 0,
    pipeline_topology_known: bool = false,
    pipeline_stage_count: u32 = 0,
    pipeline_dynamic_viewport: bool = false,
    pipeline_dynamic_scissor: bool = false,
    viewport_valid: bool = false,
    viewport_first: u32 = 0,
    viewport_count: u32 = 0,
    viewport: abi.Viewport = .{},
    scissor_valid: bool = false,
    scissor_first: u32 = 0,
    scissor_count: u32 = 0,
    scissor: abi.Rect2D = .{},
    push_constants_valid: bool = false,
    push_layout_guest: u64 = 0,
    push_layout_real: u64 = 0,
    push_stage_flags: u32 = 0,
    push_offset: u32 = 0,
    push_size: u32 = 0,
    push_hash: u64 = 0,
    push_words: [4]u32 = [_]u32{0} ** 4,
    rect_push_valid: bool = false,
    rect_push_hash: u64 = 0,
    rect_push_words: [4]u32 = [_]u32{0} ** 4,
};

/// A real graphics pipeline is opaque to the command stream, but its topology
/// and dynamic-state declarations are exactly the facts needed to distinguish
/// a four-vertex triangle strip from an accidental triangle list.  Retain a
/// small fingerprint at creation time so a later draw can report both the
/// guest handle and the host pipeline contract.
const TrackedGraphicsPipeline = struct {
    real: u64 = 0,
    layout: u64 = 0,
    repair_real: u64 = 0,
    guest_output_candidate: bool = false,
    fsi: fsi_diagnostics.PipelineIdentity = .{},
    topology: u32 = 0,
    topology_known: bool = false,
    stage_count: u32 = 0,
    viewport_count: u32 = 0,
    scissor_count: u32 = 0,
    dynamic_viewport: bool = false,
    dynamic_scissor: bool = false,
    cull_mode: u32 = 0,
    front_face: u32 = 0,
};

/// Pipeline-layout metadata is kept separately from the native handle map so
/// the graphics repair can prove that a candidate pipeline actually exposes
/// Xenia's vertex rectangle push-constant contract.  This is deliberately a
/// small fingerprint, not a second Vulkan object lifetime.
const TrackedPipelineLayout = struct {
    real: u64 = 0,
    has_vertex_rect_push_constants: bool = false,
};

const TrackedCommandTargets = struct {
    synthetic: u64 = 0,
    image_count: u8 = 0,
    images: [MAX_TRACKED_TARGET_ATTACHMENTS]u64 = [_]u64{0} ** MAX_TRACKED_TARGET_ATTACHMENTS,
    bound_descriptor_set_count: u8 = 0,
    bound_descriptor_sets: [MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND]TrackedCommandDescriptorSet = [_]TrackedCommandDescriptorSet{.{}} ** MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND,
    sampled_image_count: u8 = 0,
    sampled_images: [MAX_TRACKED_DESCRIPTOR_IMAGES]u64 = [_]u64{0} ** MAX_TRACKED_DESCRIPTOR_IMAGES,
    sampled_images_unknown: bool = false,
    transfer_count: u8 = 0,
    transfers: [MAX_TRACKED_RESOURCE_TRANSFERS]TrackedImageTransfer = [_]TrackedImageTransfer{.{}} ** MAX_TRACKED_RESOURCE_TRANSFERS,
    /// The strongest thing any command recorded into this buffer can put on
    /// the screen. A boolean here was what let a render-pass load clear be
    /// counted as a frame that carried a picture.
    write_kind: WriteKind = .none,
    /// The first colour attachment of the render pass being recorded, so a
    /// descriptor set bound inside that pass can be attributed to the image
    /// the pass writes. Zero outside a render pass.
    current_pass_target: u64 = 0,
    current_pass_target_source: fsi_diagnostics.TargetSource = .unknown,
    pass_edge_count: u8 = 0,
    pass_edges: [MAX_TRACKED_PASS_EDGES]TrackedPassEdge = @splat(.{}),
    graphics_state: GraphicsStateTrace = .{},
};

/// A descriptor set bound while a render pass targeted an image. Resolved to
/// images at submission, like the per-command sampled list, and committed to
/// `present_chain` as a per-target edge so the presenter's paint and the
/// gamma pass beneath it can each be followed one link upstream.
const TrackedPassEdge = struct { target: u64 = 0, set: u64 = 0 };
const MAX_TRACKED_PASS_EDGES: usize = 16;

/// Re-exported so every call site in this file spells the classification the
/// same way `present_chain` and the contract package do.
const WriteKind = rosette_gpu.PresentWriteKind;

/// Why a guest vkUpdateDescriptorSets was not forwarded.
const DescriptorUpdateRefusal = enum(u8) {
    no_device,
    too_many_writes,
    guest_read,
    unmapped_set,
    inline_block,
    p_next,
    array_capacity,
    null_array,
    unmapped_sampler,
    unmapped_image_view,
    unmapped_buffer,
    unmapped_buffer_view,
    descriptor_type,
};

/// Exact guest-side location and handle behind a refused descriptor update.
/// `write_index` stays max when admission fails before any VkWrite is read.
const DescriptorUpdateFailureDetails = struct {
    write_index: u64 = std.math.maxInt(u64),
    descriptor_type: u32 = 0,
    binding: u32 = 0,
    descriptor_set: u64 = 0,
    resource: u64 = 0,
    element_index: u64 = std.math.maxInt(u64),
};

/// A target-overflow count is only useful when it says which bounded ledger
/// lost the edge.  These are bookkeeping failures, not Vulkan command
/// rejections: the native call can still succeed while Rosetta loses the
/// provenance needed to explain a bad picture.  Keep the categories at the
/// allocation site so the next run identifies the first pressure point.
const TargetOverflowKind = enum(u8) {
    descriptor_set_table,
    descriptor_image_entries,
    descriptor_image_array,
    descriptor_address_arithmetic,
    texel_entries,
    texel_array,
    command_sampled_images,
    command_bound_sets,
    command_pass_edges,
    command_set_array,
    command_set_index,
    command_target_table,
    command_images,
    command_transfers,
    image_view_table,
    framebuffer_attachments,
    framebuffer_table,
    render_pass_attachments,
    render_pass_resolves,
    render_pass_table,
    submission_sampled_images,
    submission_sampled_sentinel,
    submission_transfers,

    pub fn label(self: TargetOverflowKind) []const u8 {
        return @tagName(self);
    }
};
const frame_content = rosette_gpu.frame_content;

const ReadbackSample = struct {
    frame: u64,
    swapchain: u64,
    image: u64,
    width: u32,
    height: u32,
    format: u32,
    stats: frame_capture.Stats,

    pub fn pictureEvidence(self: ReadbackSample) transport_timing.PictureSequence.Sample {
        return .{ .present = self.frame, .swapchain = self.swapchain, .image = self.image, .rgb_detail = self.stats.hasRgbDetail() };
    }
};
const PendingReadbackCapture = struct {
    sample: ReadbackSample,
    bytes: []u8,
    write_kind: WriteKind,
    preview: bool,
};

fn resolvedPresentResult(batch: abi.Result, per_swapchain: abi.Result) abi.Result {
    return if (per_swapchain == abi.NOT_READY) batch else per_swapchain;
}

/// One reusable, host-visible readback path.  It is deliberately small and
/// opt-in at the capability boundary: the swapchain only receives the
/// transfer-src usage bit when the surface supports it, and the probe samples
/// a bounded subset of presents rather than synchronizing every frame.
const PixelProbeState = struct {
    staging_buffer: abi.Buffer = 0,
    staging_memory: abi.DeviceMemory = 0,
    staging_size: u64 = 0,
    mapped_coherent: bool = false,
    mapped: ?*anyopaque = null,
    command_pool: abi.CommandPool = 0,
    command_pool_family: u32 = abi.QUEUE_FAMILY_IGNORED,
    command_buffer: abi.CommandBuffer = null,
    frame: u64 = 0,
    attempts: u64 = 0,
    successes: u64 = 0,
    failures: u64 = 0,
    /// Content-frame samples have their own bounded retry budget. The startup
    /// samples can all be clears, and a single first-content sample can still
    /// be a transitional black frame; retry until detail is proven or the
    /// bounded budget is consumed.
    content_probe_attempts: u64 = 0,
    detail_observed: bool = false,
    last_result: abi.Result = abi.SUCCESS,
    last_swapchain: abi.SwapchainKHR = 0,
    capture_policy: frame_capture.Policy = .{},
    capture_configured: bool = false,
    /// Off unless `ROSETTE_VULKAN_CAPTURE` asks for it: capture keeps the
    /// steady readback cadence alive, and that readback drains the GPU queue
    /// on the thread every guest thread runs on.
    capture_enabled: bool = false,
    preview_enabled: bool = false,
    exposure_enabled: bool = true,
    preview_interval_ns: u64 = 250_000_000,
    last_preview_probe_ns: u64 = 0,
    capture_calls: u64 = 0,
    capture_saved: u64 = 0,
    capture_previewed: u64 = 0,
    capture_failures: u64 = 0,
    capture_missing: u64 = 0,
    capture_last_frame: u64 = 0,
    capture_last_stats: frame_capture.Stats = .{},
    readback_wait_handoffs: u64 = 0,
    readback_completion_failed: bool = false,
    /// The most recent successful swapchain readback, whether or not the
    /// capture callback ran for it.
    last_stats: frame_capture.Stats = .{},
    last_stats_frame: u64 = 0,
    last_stats_format: u32 = 0,
    last_sample: ?ReadbackSample = null,
    probe_schedule: transport_timing.ProbeCadence = .{},
};

/// A private Vulkan storage buffer used only if Xenia's initial FSI ZPD
/// descriptor unexpectedly names a null counter sink. It is independent of
/// guest resources and lives until the guest device is destroyed.
const FsiZpdSinkState = struct {
    buffer: abi.Buffer = 0,
    memory: abi.DeviceMemory = 0,
    range: u64 = 0,
};

/// Where along Xenia's present path the picture's brightness is lost, read
/// from three images in one present: the swap texture the texture cache hands
/// the gamma pass, the guest output image the gamma pass writes, and the
/// swapchain image the presenter paints from it.
const BrightnessLoss = enum {
    /// Nothing upstream of the swapchain could be read.
    unknown,
    /// The swap texture is already dark: the loss is in the title's own
    /// render or resolve, or in the CPU-side state Xenia computed for them.
    before_gamma_pass,
    /// Bright into the gamma pass, dark out of it: the ramp or its lookup.
    gamma_pass,
    /// Bright out of the gamma pass, dark on the swapchain: the presenter's
    /// paint (format, colour space, sampler).
    present_paint,
    /// The swapchain has at least one channel above the ladder's dark
    /// threshold. This is not a judgment that the rendered colours are right.
    swapchain_signal_present,

    pub fn label(self: BrightnessLoss) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .before_gamma_pass => "before_gamma_pass",
            .gamma_pass => "gamma_pass",
            .present_paint => "present_paint",
            .swapchain_signal_present => "swapchain_signal_present",
        };
    }

    pub fn meaning(self: BrightnessLoss) []const u8 {
        return switch (self) {
            .unknown => "no image upstream of the swapchain could be read back, so the loss cannot be placed",
            .before_gamma_pass => "the swap texture Xenia's texture cache handed to the gamma pass is already dark when read as UNORM: read the swap_texture line's as_7e3 figures first, because a 10-bit front buffer holding 7e3 float patterns is dim as UNORM by construction (1.0 is 384/1023) and the programmed ramp is what turns it into intensities; if as_7e3 is dim too, the loss is in the title's render/resolve or in the CPU-side state Xenia computed for them",
            .gamma_pass => "the swap texture is bright and the gamma pass's output is dark: read ramp_shape and ramp_out on the TEXEL CUSTODY line, the lookup table is where the brightness went",
            .present_paint => "the gamma pass's output is bright and the swapchain image is dark: the presenter's paint from guest output to swapchain (format, colour space or sampler) is where the brightness went",
            .swapchain_signal_present => "the swapchain has a channel above the ladder's dark threshold; this does not establish correct colour or identify the render pass that produced it",
        };
    }
};

const LadderStage = struct {
    label: []const u8,
    real_image: u64 = 0,
    synthetic_image: u64 = 0,
    format: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    stats: ?frame_capture.Stats = null,
    /// Optional Xenos 7e3 interpretation of the pre-gamma swap texture.
    /// `guest_output` is the gamma pass result and is measured as normalized
    /// output only, even when Vulkan stores it in the same 10-bit format.
    seven_e3: ?frame_capture.SevenE3Stats = null,
    status: []const u8 = "not_reached",
};

const BrightnessLadderState = struct {
    samples: u64 = 0,
    printed: u64 = 0,
    readbacks: u64 = 0,
    readback_failures: u64 = 0,
    verdict_counts: [5]u64 = @splat(0),
    last_verdict: BrightnessLoss = .unknown,
    last_frame: u64 = 0,
    /// Peak channel value (8-bit scale) at each stage of the last sample:
    /// swap texture, guest output, swapchain. 256 means unread.
    last_peaks: [3]u16 = .{ 256, 256, 256 },
    last_swapchain_near_white: bool = false,
    white_transitions: u64 = 0,
    probe_schedule: transport_timing.ProbeCadence = .{},
};

/// Whether the host image should gain TRANSFER_SRC for the ladder. Only a
/// single-sampled 2D colour image in a layout the probe can decode.
fn imageReadbackAugmentable(usage: u32, format: u32, image_type: u32, samples: u32) bool {
    if ((usage & abi.IMAGE_USAGE_TRANSFER_SRC_BIT) != 0) return false;
    if ((usage & (abi.IMAGE_USAGE_SAMPLED_BIT | abi.IMAGE_USAGE_COLOR_ATTACHMENT_BIT)) == 0) return false;
    if (image_type != abi.IMAGE_TYPE_2D or samples != abi.SAMPLE_COUNT_1_BIT) return false;
    return frame_capture.layoutFor(format) != null;
}

const PIXEL_PROBE_MAX_BYTES: u64 = 64 * 1024 * 1024;
const PIXEL_PROBE_INITIAL_SAMPLES: u64 = 4;

/// Bounded colour checkpoints through the title/campaign transition. The
/// previous 1536-frame first checkpoint never ran when MoltenVK hung at
/// frame 1286, leaving frame 9 as the last measured image. These checkpoints
/// are sparse because each one drains the queue for an image readback.
const render_diagnostic_frames = [_]u64{ 256, 512, 768, 896, 1024, 1152, 1280, 1536, 2048, 2304, 2560, 3072, 4608 };

fn campaignDiagnosticFrame(frame: u64) bool {
    for (render_diagnostic_frames) |checkpoint| {
        if (frame == checkpoint) return true;
    }
    return false;
}

const PIXEL_PROBE_CONTENT_SAMPLES: u64 = 8;

fn shouldForceContentPixelProbe(probe: *const PixelProbeState, write_kind: WriteKind) bool {
    return write_kind == .content and
        !probe.detail_observed and
        probe.content_probe_attempts < PIXEL_PROBE_CONTENT_SAMPLES;
}

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

const FsiGuestChainStatus = enum { absent, present, unreadable, too_deep };

const FsiGuestFeatureRequest = struct {
    status: FsiGuestChainStatus = .absent,
    sample: bool = false,
    pixel: bool = false,
    shading_rate: bool = false,
};

fn featureChainBoolAt(bytes: []const u8, index: usize) bool {
    const offset = 16 + index * 4;
    if (offset + 4 > bytes.len) return false;
    return std.mem.readInt(u32, bytes[offset..][0..4], .little) != 0;
}

/// Read only the FSI feature node from a guest-owned chain. This intentionally
/// tolerates other nodes so diagnostics can still say whether Xenia requested
/// interlock when a separate, unsupported pNext node makes device creation
/// fail.
fn fsiGuestFeatureRequest(state: anytype, guest_p_next: u64) FsiGuestFeatureRequest {
    var node = guest_p_next;
    for (0..16) |_| {
        if (node == 0) return .{ .status = .absent };
        if (state.guestMemoryConst(node, 16) == null) return .{ .status = .unreadable };
        const s_type = state.read32(node);
        const next = state.read64(node + 8);
        if (s_type == abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT) {
            const bytes = state.guestMemoryConst(node, 28) orelse return .{ .status = .unreadable };
            return .{
                .status = .present,
                .sample = featureChainBoolAt(bytes, 0),
                .pixel = featureChainBoolAt(bytes, 1),
                .shading_rate = featureChainBoolAt(bytes, 2),
            };
        }
        node = next;
    }
    return .{ .status = if (node == 0) .absent else .too_deep };
}

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

/// One ownership-oriented graphics snapshot. Handles stay separated by
/// producer: Rosette's presenter and Xenia's real Vulkan device may both be
/// healthy, but they are never the same object merely because both end at the
/// same CAMetalLayer.
pub const GraphicsOwnershipSnapshot = struct {
    rosette_presenter_ready: bool = false,
    rosette_metal_layer: u64 = 0,
    rosette_instance: u64 = 0,
    rosette_surface: u64 = 0,
    rosette_device: u64 = 0,
    rosette_queue: u64 = 0,
    rosette_swapchain: u64 = 0,
    rosette_generation: u64 = 0,
    rosette_diagnostic_frames: u64 = 0,
    rosette_host_frames: u64 = 0,
    rosette_guest_output_frames: u64 = 0,
    /// The Vulkan format of the presenter's swapchain images. Frame custody
    /// needs a format for every frame it holds, including the host clears, and
    /// this is the one the presenter actually negotiated rather than a
    /// plausible default.
    rosette_surface_format: u32 = 0,
    rosette_extent_width: u32 = 0,
    rosette_extent_height: u32 = 0,
    xenia_instance: u64 = 0,
    xenia_surface: u64 = 0,
    xenia_device: u64 = 0,
    xenia_queue: u64 = 0,
    xenia_swapchain: u64 = 0,
    xenia_submissions: u64 = 0,
    xenia_presents: u64 = 0,
    /// Xenia present requests followed by a host queue-completion edge. A
    /// request count alone is intentionally insufficient for frame evidence.
    xenia_present_completions: u64 = 0,
    latest_frame: ?rosette_gpu.FrameSource = null,
    latest_frame_consumed: bool = false,
};

/// A bounded record of Vulkan calls Rosetta refused before the native driver
/// ever saw them.
///
/// A refusal is not the same fact as a driver error, and conflating the two
/// cost a run: `vkQueueSubmit(queue, 0, NULL, fence)` is a legal fence-only
/// submission, Rosetta answered `VK_ERROR_INITIALIZATION_FAILED`, and the
/// only visible symptom was a counter climbing by powers of two while the
/// guest waited on a fence nothing would signal.
///
/// So a refusal records what was refused, *why*, and the arguments that
/// decided it -- and it says whether the reason is a limitation of this
/// bridge or a genuinely invalid call, because those two need opposite
/// responses. Nothing is emitted while the ledger is empty.
pub const VulkanRefusalLedger = struct {
    pub const capacity: usize = 24;
    pub const reason_capacity: usize = 96;
    pub const name_capacity: usize = 48;

    pub const Entry = struct {
        used: bool = false,
        name_buffer: [name_capacity]u8 = [_]u8{0} ** name_capacity,
        name_length: usize = 0,
        reason_buffer: [reason_capacity]u8 = [_]u8{0} ** reason_capacity,
        reason_length: usize = 0,
        result: i32 = 0,
        calls: u64 = 0,
        first_args: [3]u64 = [_]u64{0} ** 3,
        unreported: bool = false,

        pub fn name(self: *const Entry) []const u8 {
            return self.name_buffer[0..self.name_length];
        }

        pub fn reason(self: *const Entry) []const u8 {
            return self.reason_buffer[0..self.reason_length];
        }
    };

    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,
    total: u64 = 0,
    overflow: u64 = 0,
    unreported_count: usize = 0,

    fn store(destination: []u8, source: []const u8) usize {
        const length = @min(destination.len, source.len);
        @memcpy(destination[0..length], source[0..length]);
        return length;
    }

    /// Returns true the first time a (name, reason) pair is seen, which is
    /// the only moment worth logging eagerly.
    pub fn note(
        self: *VulkanRefusalLedger,
        entry_point: []const u8,
        why: []const u8,
        result: i32,
        args: [3]u64,
    ) bool {
        self.total +|= 1;
        for (self.entries[0..self.count]) |*existing| {
            if (!std.mem.eql(u8, existing.name(), entry_point[0..@min(entry_point.len, name_capacity)])) continue;
            if (!std.mem.eql(u8, existing.reason(), why[0..@min(why.len, reason_capacity)])) continue;
            existing.calls +|= 1;
            return false;
        }
        if (self.count == capacity) {
            self.overflow +|= 1;
            return false;
        }
        var entry = Entry{ .used = true, .calls = 1, .result = result, .first_args = args, .unreported = true };
        entry.name_length = store(&entry.name_buffer, entry_point);
        entry.reason_length = store(&entry.reason_buffer, why);
        self.entries[self.count] = entry;
        self.count += 1;
        self.unreported_count += 1;
        return true;
    }

    pub fn isEmpty(self: *const VulkanRefusalLedger) bool {
        return self.count == 0;
    }

    pub fn markReported(self: *VulkanRefusalLedger) void {
        for (self.entries[0..self.count]) |*entry| entry.unreported = false;
        self.unreported_count = 0;
    }
};

/// What became of an entry point the host device does not provide.
///
/// "Absent" on its own is not a finding: a 1.2 device is *expected* not to
/// have the 1.3 core entry points, and every one of those has a fallback the
/// bridge already takes. What matters is whether the guest ever reached one,
/// and what served it when it did -- an absence nothing reaches is settled,
/// and an absence something reaches is either a working fallback or a wall.
/// Reporting the two as the same line is what makes the absence list read
/// like a broken loader.
pub const VulkanAbsentEntryPoints = struct {
    pub const capacity: usize = 16;
    pub const name_capacity: usize = 56;
    pub const note_capacity: usize = 80;

    pub const Entry = struct {
        name_buffer: [name_capacity]u8 = [_]u8{0} ** name_capacity,
        name_length: usize = 0,
        note_buffer: [note_capacity]u8 = [_]u8{0} ** note_capacity,
        note_length: usize = 0,
        reached: u64 = 0,

        pub fn name(self: *const Entry) []const u8 {
            return self.name_buffer[0..self.name_length];
        }

        pub fn servedBy(self: *const Entry) []const u8 {
            return self.note_buffer[0..self.note_length];
        }
    };

    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,
    overflow: u64 = 0,

    fn store(destination: []u8, source: []const u8) usize {
        const length = @min(destination.len, source.len);
        @memcpy(destination[0..length], source[0..length]);
        return length;
    }

    /// Record that the guest reached an entry point this device does not
    /// have, and what answered it instead.
    pub fn note(self: *VulkanAbsentEntryPoints, entry_point: []const u8, served_by: []const u8) void {
        for (self.entries[0..self.count]) |*existing| {
            if (!std.mem.eql(u8, existing.name(), entry_point[0..@min(entry_point.len, name_capacity)])) continue;
            existing.reached +|= 1;
            return;
        }
        if (self.count == capacity) {
            self.overflow +|= 1;
            return;
        }
        var entry = Entry{ .reached = 1 };
        entry.name_length = store(&entry.name_buffer, entry_point);
        entry.note_length = store(&entry.note_buffer, served_by);
        self.entries[self.count] = entry;
        self.count += 1;
    }

    pub fn isEmpty(self: *const VulkanAbsentEntryPoints) bool {
        return self.count == 0;
    }
};

/// Fences the guest polls that Rosetta never handed to the driver.
///
/// This is the shape of a translation-layer bug that no counter catches: the
/// frame loop keeps running -- submits climb, presents climb -- while one
/// fence the guest is waiting on is never signalled, because the submission
/// that would have signalled it was refused. From the outside the emulator
/// looks alive and produces nothing.
///
/// So the two facts are kept together: how often the guest asked about a
/// fence, and whether any submission Rosetta forwarded actually carried it.
/// A fence polled many times with no submission behind it is not slow, it is
/// starved, and the refusal ledger says why.
pub const VulkanFenceWatch = struct {
    pub const capacity: usize = 16;
    /// Polls of a never-submitted fence before the guest is judged to be
    /// waiting on something that cannot arrive. High enough that an ordinary
    /// poll-before-first-submit is not a finding.
    pub const starvation_threshold: u64 = 256;

    pub const Entry = struct {
        handle: u64 = 0,
        polls: u64 = 0,
        submissions: u64 = 0,
        signalled: bool = false,
        reported: bool = false,
    };

    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,

    fn find(self: *VulkanFenceWatch, handle: u64) ?*Entry {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.handle == handle) return entry;
        }
        if (self.count == capacity) return null;
        self.entries[self.count] = .{ .handle = handle };
        self.count += 1;
        return &self.entries[self.count - 1];
    }

    pub fn notePoll(self: *VulkanFenceWatch, handle: u64) void {
        if (handle == 0) return;
        const entry = self.find(handle) orelse return;
        entry.polls +|= 1;
    }

    pub fn noteSubmission(self: *VulkanFenceWatch, handle: u64) void {
        if (handle == 0) return;
        const entry = self.find(handle) orelse return;
        entry.submissions +|= 1;
    }

    pub fn noteSignalled(self: *VulkanFenceWatch, handle: u64) void {
        if (handle == 0) return;
        const entry = self.find(handle) orelse return;
        entry.signalled = true;
    }

    /// The first fence that is being polled hard with nothing behind it, if
    /// any. Reported once per fence.
    pub fn starvedFence(self: *VulkanFenceWatch) ?*Entry {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.reported or entry.signalled) continue;
            if (entry.submissions != 0) continue;
            if (entry.polls < starvation_threshold) continue;
            entry.reported = true;
            return entry;
        }
        return null;
    }
};

/// Cumulative evidence for the guest-owned swapchain.  The PE-side Windows
/// ledger sees the names of Vulkan calls, but only this forwarder owns target
/// attribution and native completion truth.  Keeping this as a value-only
/// snapshot avoids leaking the chain's bounded storage across the ABI seam.
pub const GuestFrameEvidence = struct {
    presents_with_target: u64 = 0,
    presents_with_content: u64 = 0,
    presents_clear_only: u64 = 0,
    presents_without_target: u64 = 0,
    presents_without_write: u64 = 0,
    native_present_requests: u64 = 0,
    native_present_completions: u64 = 0,
    native_queue_submits: u64 = 0,
};

pub const Forwarder = struct {
    libraries: [MAX_LIBRARIES]Library = [_]Library{.{}} ** MAX_LIBRARIES,
    library_count: usize = 0,
    guest_libraries: [MAX_GUEST_LIBRARIES]GuestLibrary = [_]GuestLibrary{.{}} ** MAX_GUEST_LIBRARIES,
    guest_symbols: [MAX_GUEST_SYMBOLS]GuestSymbol = [_]GuestSymbol{.{}} ** MAX_GUEST_SYMBOLS,
    guest_symbol_lookup_cache: [GUEST_SYMBOL_LOOKUP_CACHE_SIZE]GuestSymbolLookupCacheEntry = [_]GuestSymbolLookupCacheEntry{.{}} ** GUEST_SYMBOL_LOOKUP_CACHE_SIZE,
    guest_symbol_lookup_cache_hits: u64 = 0,
    guest_symbol_lookup_cache_misses: u64 = 0,
    guest_open_count: u64 = 0,
    guest_close_count: u64 = 0,
    guest_lookup_count: u64 = 0,
    guest_thunk_calls: u64 = 0,
    guest_proc_queries: u64 = 0,
    guest_instance_extension_enumeration_calls: u64 = 0,
    vulkan_loader_lookup_unique: u64 = 0,
    vulkan_loader_lookup_repeats: u64 = 0,
    vulkan_loader_lookup_cache_overflows: u64 = 0,
    vulkan_surface_path: surface_path_ledger.SurfacePathLedger = .{},
    vulkan_loader_lookup_misses: [MAX_VULKAN_LOOKUP_MISSES]VulkanLookupMiss =
        [_]VulkanLookupMiss{.{}} ** MAX_VULKAN_LOOKUP_MISSES,
    guest_opaque_calls: u64 = 0,
    next_vulkan_object: u64 = 0xFFFF_F500_0000_0001,
    vulkan_logical_devices_created: u64 = 0,
    vulkan_queues_acquired: u64 = 0,
    vulkan_metal_surfaces_created: u64 = 0,
    vulkan_swapchains_created: u64 = 0,
    vulkan_swapchain_images_enumerated: u64 = 0,
    vulkan_images_acquired: u64 = 0,
    vulkan_queue_submits: u64 = 0,
    /// Legal `vkQueueSubmit(queue, 0, NULL, fence)` calls forwarded to the
    /// driver. A guest waiting on one of these fences makes no progress until
    /// it is signalled, so this being zero while the guest waits is the
    /// signature of the refusal this counter replaced.
    vulkan_fence_only_queue_submits: u64 = 0,
    vulkan_refusals: VulkanRefusalLedger = .{},
    vulkan_fence_watch: VulkanFenceWatch = .{},
    /// The window-to-compositor chain. Recorded because every counter in this
    /// struct measures a call that returned, and a black window is a chain
    /// that broke without any call failing.
    present_chain: rosette_gpu.PresentChain = .{},
    /// The last-mile screen contract. PRESENT CHAIN proves transport and
    /// topology; this ledger also requires pixel detail and a visible
    /// compositor path before it calls a frame valid on screen.
    screen_validity: rosette_gpu.ScreenValidity = .{},
    present_chain_verdict_logged: ?rosette_gpu.PresentChainVerdict = null,
    present_chain_reports: u64 = 0,
    present_chain_window_break: ??[]const u8 = null,
    present_chain_window_facts: ?rosette_gpu.WindowGeometry = null,
    present_chain_window_poll: transport_timing.ReportCadence = .{ .interval_ns = 1_000_000_000 },
    graphics_report_cadence: transport_timing.ReportCadence = .{},
    graphics_report_configured: bool = false,
    graphics_report_verbose: bool = false,
    graphics_report_anomalies: u64 = 0,
    graphics_report_brightness: ?BrightnessLoss = null,
    graphics_report_picture_started: bool = false,
    picture_sequence: transport_timing.PictureSequence = .{},
    frame_hud_last_sample_ns: u64 = 0,
    frame_hud_fps_milli: u64 = 0,
    frame_hud_callback_resolved: bool = false,
    frame_hud_bridge_reported: bool = false,
    /// `no_presents` is a real presentation failure point, but it can be
    /// provisional during Xenia startup: the guest may create the swapchain
    /// long before it submits its first draw. Keep one bounded failure episode
    /// so the first occurrence gets a full Vulkan snapshot and later polls do
    /// not flood the run log.
    present_chain_no_present_active: bool = false,
    present_chain_no_present_episode: u64 = 0,
    present_chain_no_present_reports: u64 = 0,
    /// Said once that the no-presents verdict is being held because the guest
    /// frontier is in bounded work. Cleared when it leaves, so the real
    /// episode still opens the moment the guest could have presented.
    present_chain_deferred_reported: bool = false,
    /// The PE executor reports its current guest frontier at the same cadence
    /// as the presentation snapshot. This is deliberately separate from the
    /// Vulkan call ring: a no-presents verdict must say what the guest did
    /// after the last forwarded call, not merely repeat that the host was
    /// ready.
    guest_progress_steps: u64 = 0,
    guest_progress_rip: u64 = 0,
    guest_progress_thread: u64 = 0,
    /// Whether the guest frontier sits in work that terminates on its own.
    ///
    /// A swapchain with no presents is a failure only once the guest is in a
    /// position to produce a frame. While it is translating a module,
    /// rasterizing an atlas or building pipelines, "nothing has presented" is
    /// a statement about the clock, not about the presentation chain - and
    /// calling it a live failure point sends a reader to the wrong subsystem.
    guest_frontier_is_bounded: bool = false,
    /// The frontier's opcode *and* the symbol it sits in. Sized for a fully
    /// qualified Xenia name: a 64-byte buffer clipped every interesting one
    /// to its namespace prefix.
    guest_progress_op: [224:0]u8 = [_:0]u8{0} ** 224,
    guest_progress_op_len: usize = 0,
    /// Guest-side target metadata used to connect a recorded command back to
    /// the exact image it names.  These tables are intentionally bounded like
    /// the Vulkan handle maps; an untracked target is reported as unknown
    /// rather than being promoted to proof of a visible frame.
    tracked_image_views: [MAX_REAL_IMAGE_VIEWS]TrackedImageView = [_]TrackedImageView{.{}} ** MAX_REAL_IMAGE_VIEWS,
    /// Where each tracked view lives in `tracked_image_views`; a descriptor
    /// update asks it once per image it writes.
    tracked_image_view_index: SlotIndex(MAX_REAL_IMAGE_VIEWS) = .{},
    tracked_buffer_views: [MAX_REAL_BUFFER_VIEWS]TrackedBufferView = @splat(.{}),
    texel_custody_samples: u64 = 0,
    texel_custody_missing: u64 = 0,
    texel_custody_zero: u64 = 0,
    texel_custody_printed: u64 = 0,
    /// What the most recently audited gamma ramp does, from `texel_custody`.
    texel_custody_last_format: u32 = 0,
    texel_custody_last_channel_pairs_differ: ?u32 = null,
    texel_custody_last_shape: rosette_gpu.vulkan.texel_custody.Shape = .unknown_size,
    /// Reference gamma outputs ordered as max, 7e3-one bit pattern, midpoint;
    /// each inner tuple is red/green/blue.
    texel_custody_last_out_rgb: [3][3]u16 = .{
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
    },
    texel_custody_default_samples: u64 = 0,
    texel_custody_programmed_samples: u64 = 0,
    /// Render-pass source edges committed to the present chain, and the
    /// images whose host usage gained TRANSFER_SRC so the ladder can read
    /// them. Neither changes what the guest sees.
    vulkan_pass_source_edges: u64 = 0,
    vulkan_image_usage_augmented: u64 = 0,
    brightness_ladder: BrightnessLadderState = .{},
    tracked_descriptor_sets: [MAX_TRACKED_DESCRIPTOR_SETS]TrackedDescriptorSet = [_]TrackedDescriptorSet{.{}} ** MAX_TRACKED_DESCRIPTOR_SETS,
    /// Where each tracked set lives in `tracked_descriptor_sets`. Every write
    /// to that table goes through this index; see `slot_index.zig` for why.
    tracked_descriptor_set_index: SlotIndex(MAX_TRACKED_DESCRIPTOR_SETS) = .{},
    tracked_render_passes: [MAX_REAL_RENDER_PASSES]TrackedRenderPass = [_]TrackedRenderPass{.{}} ** MAX_REAL_RENDER_PASSES,
    tracked_framebuffers: [MAX_REAL_FRAMEBUFFERS]TrackedFramebuffer = [_]TrackedFramebuffer{.{}} ** MAX_REAL_FRAMEBUFFERS,
    tracked_command_targets: [MAX_REAL_COMMAND_BUFFERS]TrackedCommandTargets = [_]TrackedCommandTargets{.{}} ** MAX_REAL_COMMAND_BUFFERS,
    tracked_graphics_pipelines: [MAX_REAL_PIPELINES]TrackedGraphicsPipeline = [_]TrackedGraphicsPipeline{.{}} ** MAX_REAL_PIPELINES,
    tracked_pipeline_lookup: forwarder_pipeline_lookup.Cache = .{},
    tracked_pipeline_layouts: [MAX_REAL_PIPELINE_LAYOUTS]TrackedPipelineLayout = [_]TrackedPipelineLayout{.{}} ** MAX_REAL_PIPELINE_LAYOUTS,
    /// State-trace counters are separate from command-shape counters.  A
    /// command can be forwarded successfully while carrying a malformed
    /// viewport, scissor, topology or push-constant rectangle.
    graphics_state_trace_configured: bool = false,
    graphics_state_trace_enabled: bool = false,
    graphics_state_trace_draws: u64 = 0,
    graphics_state_trace_push_constants: u64 = 0,
    graphics_state_trace_printed: u64 = 0,
    graphics_state_trace_missing_viewport: u64 = 0,
    graphics_state_trace_missing_scissor: u64 = 0,
    graphics_state_trace_bad_viewport: u64 = 0,
    graphics_state_trace_bad_scissor: u64 = 0,
    graphics_state_trace_bad_rect: u64 = 0,
    graphics_state_trace_rect_candidates: u64 = 0,
    graphics_state_trace_rect_non_candidates: u64 = 0,
    graphics_state_trace_topology_mismatch: u64 = 0,
    graphics_state_trace_unknown_pipeline: u64 = 0,
    graphics_state_trace_pipeline_overflow: u64 = 0,
    /// Xenia's guest-output presenter is a four-vertex triangle strip.  If a
    /// translated pipeline arrives as a triangle list, retain the original
    /// contract for diagnostics but create a strip twin and use it only after
    /// the draw proves the 16-byte rectangle push-constant signature.
    guest_output_topology_repair_configured: bool = false,
    guest_output_topology_repair_enabled: bool = true,
    graphics_topology_repair_candidates: u64 = 0,
    graphics_topology_repair_pipeline_creations: u64 = 0,
    graphics_topology_repair_create_failures: u64 = 0,
    graphics_topology_repairs: u64 = 0,
    graphics_topology_repair_bind_failures: u64 = 0,
    /// Xenos rectangle lists, expanded by Rosette because Xenia's Vulkan
    /// backend selects a vertex-shader fallback it never implemented.
    ///
    /// The switch reaches the shader in the vertex index: Vulkan defines an
    /// indexed draw's `gl_VertexIndex` as `indexBuffer[i] + vertexOffset`, so
    /// setting the tag in `vertexOffset` marks a whole draw without touching
    /// the index buffer Xenia owns and shares with its point-list fallback.
    rect_expand_configured: bool = false,
    rect_expand_enabled: bool = true,
    /// Synthetic shader-module handles this bridge rewrote.
    rect_expand_modules: [MAX_RECT_EXPAND_MODULES]u64 = [_]u64{0} ** MAX_RECT_EXPAND_MODULES,
    rect_expand_module_count: u32 = 0,
    /// Native pipeline handles built from a rewritten vertex shader with the
    /// strip-plus-restart topology the rectangle fallback uses. Pipelines are
    /// removed at destruction, so this tracks live workarounds rather than
    /// lifetime pipeline churn.
    rect_expand_pipeline_registry: gpu_vulkan.handle_set.Set(MAX_RECT_EXPAND_PIPELINES) = .{},
    rect_expand_bound_pipeline: u64 = 0,
    /// Per command buffer: is a rewritten rectangle pipeline bound, and are
    /// the bound indices the built-in expansion buffer's. Guest threads
    /// interleave their recording, so a bind in one command buffer must never
    /// decide a draw in another.
    rect_expand_command_states: [RECT_EXPAND_COMMAND_STATES]RectExpandCommandState = @splat(.{}),
    rect_expand_command_state_next: u32 = 0,
    /// Xenia's built-in index buffer (real handle): the one buffer the
    /// primitive processor binds for rectangle-list and point-list
    /// expansion, holding `(primitive << 2) | corner` strips. A rewritten
    /// vertex shader's module is also used by ordinary triangle strips with
    /// primitive restart; only a draw indexed from this buffer is a
    /// rectangle expansion.
    rect_expand_builtin_index_buffer: u64 = 0,
    rect_expand_builtin_index_buffers_seen: u64 = 0,
    /// Rectangle-shaped draws on a marked pipeline that were left untagged
    /// because their indices came from some other buffer - each was a
    /// guest triangle strip the old tagging rule decoded as rectangles.
    rect_expand_draws_declined_foreign_index: u64 = 0,
    rect_expand_first_foreign_index_sample: ?RectForeignIndexSample = null,
    rect_expand_shaders_rewritten: u64 = 0,
    rect_expand_shaders_cull_distance_stripped: u64 = 0,
    rect_expand_shaders_refused: u64 = 0,
    rect_expand_shaders_skipped_non_vertex: u64 = 0,
    rect_expand_shaders_skipped_already_expanded: u64 = 0,
    rect_expand_last_refusal: gpu_vulkan.rect_list_expand.Refusal = .none,
    rect_expand_refusal_counts: [std.enums.values(gpu_vulkan.rect_list_expand.Refusal).len]u64 = [_]u64{0} ** std.enums.values(gpu_vulkan.rect_list_expand.Refusal).len,
    rect_expand_last_refusal_module: u64 = 0,
    rect_expand_last_refusal_hash: u64 = 0,
    rect_expand_last_refusal_bytes: u32 = 0,
    rect_expand_last_cull_distance_site: ?gpu_vulkan.rect_list_expand.CullDistanceSite = null,
    rect_expand_allocation_failures: u64 = 0,
    rect_expand_last_driver_rejection_result: i32 = 0,
    rect_expand_last_driver_rejection_module: u64 = 0,
    rect_expand_last_driver_rejection_hash: u64 = 0,
    rect_expand_last_driver_rejection_bytes: u32 = 0,
    rect_expand_pipelines_marked: u64 = 0,
    rect_expand_draws_tagged: u64 = 0,
    rect_expand_module_overflow: u64 = 0,
    rect_expand_pipeline_overflow: u64 = 0,
    rect_expand_module_rejections: u64 = 0,
    rect_expand_pipelines_unmarked: u64 = 0,
    /// `gpu_vulkan.robust_access`: MoltenVK reports robustBufferAccess, which
    /// Xenia enables and relies on, but Metal bounds no shader index. Every
    /// module is hardened before the driver sees it.
    /// `ROSETTE_VULKAN_ROBUST_ACCESS=0` disables it (A/B diagnosis only).
    robust_access_configured: bool = false,
    robust_access_enabled: bool = true,
    robust_access_stats: gpu_vulkan.robust_access.Stats = .{},
    robust_access_modules_hardened: u64 = 0,
    robust_access_modules_unchanged: u64 = 0,
    robust_access_modules_refused: u64 = 0,
    robust_access_driver_rejections: u64 = 0,
    robust_access_allocation_failures: u64 = 0,
    fsi_pixel_frequency_configured: bool = false,
    fsi_pixel_frequency_enabled: bool = true,
    fsi_pixel_frequency_changed: u64 = 0,
    fsi_pixel_frequency_explicit: u64 = 0,
    fsi_pixel_frequency_complex: u64 = 0,
    fsi_pixel_frequency_allocation_failures: u64 = 0,
    fsi_pixel_frequency_driver_rejections: u64 = 0,
    hdr_resolve_configured: bool = false,
    hdr_resolve_enabled: bool = true,
    hdr_resolve_modules: u64 = 0,
    hdr_resolve_unpacks: u64 = 0,
    hdr_resolve_driver_rejections: u64 = 0,
    target_attribution_events: u64 = 0,
    target_offscreen_events: u64 = 0,
    target_unknown_events: u64 = 0,
    target_overflow_events: u64 = 0,
    target_overflow_by_kind: [std.enums.values(TargetOverflowKind).len]u64 = [_]u64{0} ** std.enums.values(TargetOverflowKind).len,
    /// Descriptor provenance is deliberately counted at each boundary. A
    /// bind can precede an update, and the command can be submitted much
    /// later, so a single bind-time snapshot cannot prove what the draw saw.
    vulkan_descriptor_update_calls: u64 = 0,
    vulkan_descriptor_update_forwarded: u64 = 0,
    vulkan_descriptor_native_writes: u64 = 0,
    vulkan_descriptor_native_copies: u64 = 0,
    vulkan_descriptor_update_refusals: [std.enums.values(DescriptorUpdateRefusal).len]u64 = [_]u64{0} ** std.enums.values(DescriptorUpdateRefusal).len,
    vulkan_descriptor_template_update_calls: u64 = 0,
    vulkan_descriptor_push_calls: u64 = 0,
    vulkan_descriptor_image_infos_observed: u64 = 0,
    vulkan_descriptor_unknown_image_views: u64 = 0,
    /// A Windows Vulkan call can reach the generic command dispatcher and
    /// still be refused before the native driver because one of its guest
    /// handles or pointer arrays cannot be translated. Keep that admission
    /// edge separate from successful binds so a black frame never reports a
    /// silently dropped bind as forwarded native work.
    vulkan_descriptor_bind_admission: DescriptorBindAdmission = .{},
    vulkan_command_admission: [forwarded_vulkan_commands.len]VulkanCommandAdmission =
        [_]VulkanCommandAdmission{.{}} ** forwarded_vulkan_commands.len,
    vulkan_command_admission_entries: u64 = 0,
    vulkan_command_admission_rejected: u64 = 0,
    vulkan_command_admission_untracked: u64 = 0,
    vulkan_command_refusal_line: u32 = 0,
    vulkan_descriptor_bind_calls: u64 = 0,
    vulkan_descriptor_sets_bound: u64 = 0,
    vulkan_descriptor_sets_resolved: u64 = 0,
    vulkan_descriptor_sets_unknown: u64 = 0,
    vulkan_descriptor_late_resolutions: u64 = 0,
    vulkan_descriptor_sampled_images_recorded: u64 = 0,
    vulkan_descriptor_sampled_unknown: u64 = 0,
    pixel_probe: PixelProbeState = .{},
    fsi_zpd_sink: FsiZpdSinkState = .{},
    /// FSI set updates whose dead-stack sink info was replaced (see
    /// `gpu/vulkan/fsi_descriptor_repair.zig`).
    fsi_zpd_descriptor_repairs: u64 = 0,
    /// Xenia's FSI render backend guard: chunked submission and GPU timing
    /// (`gpu/vulkan/fsi`, `FsiGuard`). Allocated on first use.
    fsi_guard: ?*FsiGuard = null,
    /// Correct attachment-less MSAA even when watchdog chunking is disabled.
    fsi_raster: fsi_rasterization.Registry = .{},
    fsi_evidence_io: gpu_vulkan.fsi.evidence_async.State = .{},
    shader_host_profile: gpu_vulkan.fsi.shader_profile.Stats = .{},
    /// Vulkan queue host calls are externally synchronized even while a
    /// dispatch-only runtime lock is yielded for FSI backpressure.
    vulkan_queue_api_gate: queue_api_gate.Gate = .{},
    fsi_guard_refused: bool = false,
    /// Tests drive the timing watcher by hand instead of on its thread.
    fsi_guard_watcher_thread: bool = !builtin.is_test,
    transport_cost: transport_timing.Ledger = .{},
    present_ceiling: present_pacing.Ceiling = .{},
    /// Asynchronous present completion. `present_completion_confirmed` is the
    /// count of real presents the queue is known to have finished - by a
    /// blocking wait while proof is the point, then by one host fence
    /// submitted behind a present and polled at a later one.
    present_completion_fence: abi.Fence = 0,
    present_completion_fence_pending: bool = false,
    present_completion_fence_target: u64 = 0,
    present_completion_confirmed: u64 = 0,
    present_completion_blocking: u64 = 0,
    present_completion_async: u64 = 0,
    present_completion_fence_signals: u64 = 0,
    present_completion_failures: u64 = 0,
    /// Entry points the device does not provide that the guest nevertheless
    /// reached. An absence with no entry here was never asked for.
    vulkan_absent_reached: VulkanAbsentEntryPoints = .{},
    /// The names reported absent at device-function resolution, retained so
    /// the end-of-run report can say which of them were never reached.
    vulkan_absent_names: [512]u8 = [_]u8{0} ** 512,
    vulkan_absent_names_len: usize = 0,
    vulkan_absent_count: u32 = 0,
    vulkan_presents: u64 = 0,
    /// Guest command calls that invoked a real native vkCmd entry point. The
    /// older `vulkan_modeled_command_calls` counter remains as total observed
    /// traffic for compatibility with existing diagnostics. A command accepted
    /// by the ordered worker increments this when enqueued; state snapshots
    /// drain the worker before reporting final execution counts.
    vulkan_real_command_calls: u64 = 0,
    vulkan_async_command_worker: ?*async_vulkan_command.Worker = null,
    vulkan_async_command_worker_decided: bool = false,
    vulkan_async_command_worker_enabled: bool = false,
    fsi_small_chunk_sync: bool = true,
    fsi_small_chunk_sync_commands: u64 = 0,
    vulkan_async_command_barriers: u64 = 0,
    /// A full queue falls back synchronously after draining earlier work,
    /// keeping the command stream ordered without stalling on queue space.
    vulkan_async_queue_saturated_fallbacks: u64 = 0,
    vulkan_async_worker_stopped_fallbacks: u64 = 0,
    vulkan_real_queue_submits: u64 = 0,
    vulkan_real_presents: u64 = 0,
    vulkan_real_present_completions: u64 = 0,
    vulkan_real_objects_created: u64 = 0,
    /// Per-entry-point create outcomes.
    ///
    /// The aggregate counter above says how many objects exist; it cannot say
    /// that eleven of twelve tessellation shader modules were created and one
    /// was not, which is exactly the shape of the 2026-09-11
    /// `Failed to create one or more tessellation shaders` warning. A reader
    /// with only the aggregate has to guess which call failed, and a failure
    /// that is refused before the driver is reached leaves no aggregate trace
    /// at all.
    vulkan_create_ledger: [MAX_VULKAN_CREATE_LEDGER]VulkanCreateLedgerEntry =
        [_]VulkanCreateLedgerEntry{.{}} ** MAX_VULKAN_CREATE_LEDGER,
    vulkan_create_ledger_count: usize = 0,
    vulkan_create_ledger_overflow: u64 = 0,
    /// Tessellation stage visibility at the real graphics-pipeline boundary.
    /// This distinguishes a guest shader-generator failure (no tessellation
    /// pipeline reaches Rosette) from a Rosette marshal or native-driver fail.
    vulkan_tessellation_pipeline_candidates: u64 = 0,
    vulkan_tessellation_pipeline_driver_successes: u64 = 0,
    vulkan_tessellation_pipeline_driver_failures: u64 = 0,
    vulkan_tessellation_pipeline_marshal_refusals: u64 = 0,
    vulkan_tessellation_pipeline_missing_state: u64 = 0,
    vulkan_tessellation_stage_mask_or: u32 = 0,
    /// Shader modules are created before Xenia builds tessellation pipelines.
    /// These counters show whether their SPIR-V execution models reached the
    /// native vkCreateShaderModule boundary at all.
    vulkan_tess_control_shader_modules: u64 = 0,
    vulkan_tess_control_shader_modules_native_success: u64 = 0,
    vulkan_tess_control_shader_modules_native_failure: u64 = 0,
    vulkan_tess_eval_shader_modules: u64 = 0,
    vulkan_tess_eval_shader_modules_native_success: u64 = 0,
    vulkan_tess_eval_shader_modules_native_failure: u64 = 0,
    vulkan_shader_module_spirv_unreadable: u64 = 0,
    /// Xenia's FSI setting is not reflected by vkCreateDevice alone: it can
    /// request the extension even when it later picks its framebuffer path.
    /// Count modules carrying the SPIR-V interlock capability/ops to prove
    /// that shader generation actually selected the FSI render-target path.
    vulkan_fsi_shader_modules: u64 = 0,
    vulkan_fsi_shader_modules_native_success: u64 = 0,
    vulkan_fsi_shader_modules_native_failure: u64 = 0,
    vulkan_fsi_spirv_capability_mask: u8 = 0,
    vulkan_fsi_spirv_begin_ops: u64 = 0,
    vulkan_fsi_spirv_end_ops: u64 = 0,
    /// Xenia creates this exact three-binding SSBO layout only after its
    /// Vulkan render-target cache has selected the FSI path.
    vulkan_fsi_descriptor_layouts: u64 = 0,
    vulkan_fsi_shared_memory_binding_count: u32 = 0,
    vulkan_fsi_shared_memory_binding_count_known: bool = false,
    vulkan_fsi_host_storage_buffer_limit: u32 = 0,
    vulkan_fsi_host_storage_buffer_limit_known: bool = false,
    vulkan_fsi_binding_limit_would_fallback: bool = false,
    vulkan_fsi_binding_count_matches_host_range: bool = false,
    vulkan_fsi_binding_count_matches_host_range_known: bool = false,
    vulkan_fsi_tracker: gpu_vulkan.fsi_diagnostics.Tracker = .{},
    vulkan_device_loss_evidence: device_loss_diagnostics.Evidence = .{},
    metal_backend_health: rosette_gpu.metal_backend_health.Ledger = .{},
    vulkan_guest_object_publications: u64 = 0,
    vulkan_real_objects_destroyed: u64 = 0,
    /// Handle maps are intentionally bounded because a reverse mapping is
    /// part of the ABI contract.  Keep lifecycle counters beside the maps so
    /// a long run can distinguish a legitimate live-object ceiling from a
    /// Rosetta leak or a failed reclaim, instead of ending at `@panic`.
    vulkan_handle_map_allocations: u64 = 0,
    vulkan_handle_map_replacements: u64 = 0,
    vulkan_handle_map_releases: u64 = 0,
    vulkan_handle_map_exhaustions: u64 = 0,
    vulkan_handle_map_invalid: u64 = 0,
    vulkan_descriptor_set_map_high_water: usize = 0,
    vulkan_descriptor_set_pool_reset_reclaims: u64 = 0,
    vulkan_descriptor_set_pool_destroy_reclaims: u64 = 0,
    vulkan_descriptor_set_free_reclaims: u64 = 0,
    vulkan_device_void_calls: u64 = 0,
    vulkan_device_lost_events: u64 = 0,
    vulkan_fence_completions: u64 = 0,
    vulkan_modeled_command_calls: u64 = 0,
    vulkan_surface_capability_queries: u64 = 0,
    vulkan_memory_allocations: u64 = 0,
    vulkan_memory_maps: u64 = 0,
    vulkan_memory_map_reuses: u64 = 0,
    vulkan_memory_bindings: u64 = 0,
    /// Successful batch-allocation calls are intentionally counted separately
    /// from object creation.  Their detailed call lines are sparse samples;
    /// the counters keep the run verdict complete without replaying every
    /// descriptor set or command buffer.
    vulkan_command_buffer_allocations: u64 = 0,
    vulkan_descriptor_set_allocations: u64 = 0,
    vulkan_synthetic_object_batches: u64 = 0,
    vulkan_shadow_uploads: u64 = 0,
    vulkan_shadow_upload_failures: u64 = 0,
    vulkan_shadow_upload_bytes: u64 = 0,
    vulkan_native_memory_aliases: u64 = 0,
    vulkan_shadow_unchanged: u64 = 0,
    vulkan_shadow_unmap_uploads: u64 = 0,
    /// Compact command-shape evidence for the frame-content verdict. These
    /// counters are intentionally separate from total command traffic: a
    /// successful submit is not proof that a draw, clear, or copy wrote the
    /// acquired image.
    vulkan_command_render_begin_calls: u64 = 0,
    vulkan_command_render_end_calls: u64 = 0,
    vulkan_command_draw_calls: u64 = 0,
    vulkan_command_dispatch_calls: u64 = 0,
    vulkan_command_clear_calls: u64 = 0,
    vulkan_command_copy_calls: u64 = 0,
    vulkan_command_other_calls: u64 = 0,
    vulkan_render_pass_load_clear_calls: u64 = 0,
    vulkan_command_write_marks: u64 = 0,
    /// Command buffers whose recorded work could put a picture on the
    /// screen, as opposed to a colour. Reported next to `write_marks` so a
    /// run that only ever cleared is visible in one line.
    vulkan_command_content_marks: u64 = 0,
    /// Whether the window bridge has stopped writing the CAMetalLayer's
    /// drawableSize because a Vulkan swapchain now vends its drawables.
    metal_drawable_yielded: bool = false,
    /// Extent handshakes completed before real swapchain creation. A swapchain
    /// can report success while the layer still has a different drawable
    /// size, so keep the preflight result beside the present-chain ledger.
    metal_drawable_prepare_attempts: u64 = 0,
    metal_drawable_prepare_successes: u64 = 0,
    metal_drawable_prepare_failures: u64 = 0,
    metal_drawable_prepared_width: u32 = 0,
    metal_drawable_prepared_height: u32 = 0,
    /// A drawable extent is a hard boundary, not a best-effort hint.  Keep a
    /// durable record because a native driver can return success for a
    /// swapchain whose extent no longer matches the layer and the failure
    /// would otherwise only be visible in the end-of-run geometry report.
    graphics_extent_contract_failed: bool = false,
    graphics_extent_contract_failures: u64 = 0,
    graphics_extent_requested_width: u32 = 0,
    graphics_extent_requested_height: u32 = 0,
    graphics_extent_observed_width: u32 = 0,
    graphics_extent_observed_height: u32 = 0,
    /// Which Vulkan owner currently holds drawableSize.  The C bridge only
    /// needs the boolean ownership bit, while diagnostics need to distinguish
    /// Rosette's smoke presenter from the guest swapchain during handoff.
    drawable_owner: enum { window_bridge, native_presenter, guest_swapchain } = .window_bridge,
    /// Times Rosette's own presenter was stood down because the guest built a
    /// swapchain on the layer it held.
    native_presenter_retired_for_guest: u64 = 0,
    vulkan_target_submission_events: u64 = 0,
    // ---- Vulkan call trace ring buffer (last N device-level calls) ----
    vulkan_call_trace: [64]VulkanCallTrace = [_]VulkanCallTrace{.{}} ** 64,
    vulkan_call_trace_next: u8 = 0,
    vulkan_call_trace_full: bool = false,
    vulkan_call_count: u64 = 0,
    vulkan_dispatch_trace_count: u16 = 0,
    vulkan_memory_records: [MAX_VULKAN_MEMORY_ALLOCATIONS]VulkanMemoryAllocation =
        [_]VulkanMemoryAllocation{.{}} ** MAX_VULKAN_MEMORY_ALLOCATIONS,
    vulkan_resources: [MAX_VULKAN_RESOURCES]VulkanResource =
        [_]VulkanResource{.{}} ** MAX_VULKAN_RESOURCES,
    /// Resource-table lifecycle evidence. The table is a live-object map;
    /// these counters make it possible to distinguish legitimate reuse from
    /// a table that stayed full because the guest stopped destroying objects.
    vulkan_resource_records_committed: u64 = 0,
    vulkan_resource_records_released: u64 = 0,
    vulkan_resource_high_water: u64 = 0,
    vulkan_resource_overflow: u64 = 0,
    vulkan_image_bindings: u64 = 0,
    vulkan_presenter_bind_attempts: u64 = 0,
    vulkan_presenter_bind_failures: u64 = 0,
    vulkan_presenter_off_ui_calls: u64 = 0,
    vulkan_presenter_stage: VulkanPresenterStage = .none,
    native_vulkan_library_token: u64 = 0,
    native_texture_state: ?*native_texture.State = null,
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
    native_vulkan_loader_successes: u64 = 0,
    native_vulkan_loader_path: [VULKAN_LOADER_PATH_CAPACITY]u8 = [_]u8{0} ** VULKAN_LOADER_PATH_CAPACITY,
    native_vulkan_loader_path_len: u16 = 0,
    gpu_runtime: rosette_gpu.Runtime = .{},
    gpu_handshake_response: rosette_gpu.HandshakeResponse = .{},
    gpu_handshake_updates: u64 = 0,
    gpu_handshake_probes: u64 = 0,
    /// A missing foundational capability after the guest device exists is a
    /// terminal bridge violation, not a degraded negotiation. Keep this
    /// separate from the response status so a returning signal handler cannot
    /// make the next Vulkan call look healthy.
    gpu_handshake_faulted: bool = false,
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
    cocoa_fallback_attempts: u64 = 0,
    cocoa_fallback_successes: u64 = 0,
    cocoa_fallback_failures: u64 = 0,
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
    guest_frontbuffer_format: rosette_gpu.xenos_texture.Format = .k_8_8_8_8,
    /// Converted pixels live in guest memory rather than in this struct: a
    /// 4096-square surface is sixty-seven megabytes, and a buffer that large
    /// inline would be paid for by every run whether or not a frame ever
    /// arrives. Allocated once at the first conversion and reused.
    guest_frontbuffer_scratch: u64 = 0,
    guest_frontbuffer_scratch_bytes: u64 = 0,
    guest_frontbuffer_conversions: u64 = 0,
    guest_frontbuffer_conversion_failures: u64 = 0,
    guest_frontbuffer_last_failure: ?rosette_gpu.xenos_texture.Failure = null,
    /// Whether the front buffer being converted is one Rosette supplied rather
    /// than one a swap named. Carried through to the published descriptor's
    /// producer so a frame from a harness surface can never be counted as guest
    /// output, however well founded the boundary that admitted it was.
    guest_frontbuffer_harness_supplied: bool = false,
    /// Non-zero once a conversion produced pixels that were not all zero. The
    /// distinction the whole path turns on: a mapped, addressable, entirely
    /// empty front buffer is a GPU that never ran, and presenting it would put
    /// a black window up and label it guest output.
    guest_frontbuffer_nonzero_frames: u64 = 0,
    /// A VdSwap is an explicit guest presentation boundary. Keep its
    /// generation separate from conversion/publication so a front buffer can
    /// be presented immediately even when Xenia's own RefreshGuestOutput path
    /// is absent or inlined.
    guest_frontbuffer_swap_generation: u64 = 0,
    guest_frontbuffer_presented_generation: u64 = 0,
    guest_frontbuffer_swap_pending: bool = false,
    guest_frontbuffer_present_attempts: u64 = 0,
    guest_frontbuffer_present_successes: u64 = 0,
    guest_frontbuffer_present_failures: u64 = 0,
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
    /// Large Vulkan payloads, principally generated SPIR-V modules, may need
    /// the marshaller's bounded spill arena. Keep this separate from ordinary
    /// refusals so a shader-size problem cannot masquerade as a missing handle
    /// or unreadable guest structure.
    vulkan_marshal_spill_reserves: u64 = 0,
    vulkan_marshal_spill_peak_bytes: u64 = 0,
    vulkan_marshal_spill_failures: u64 = 0,
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
    /// Live adapter for Xenia's guest-addressed direct PPC provider. Static
    /// symbol names live in pkg; this field owns bindings and callbacks.
    ppc_guest_bridge: ppc_runtime.guest_bridge.Bridge = .{},
    ppc_identity_guest: u64 = 0,
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
        return forwarder_impl_loader_symbols.deinit(self);
    }

    pub fn lookupGuest(self: *Forwarder, library_token: u64, symbol: []const u8) u64 {
        return forwarder_impl_loader_symbols.lookupGuest(self, library_token, symbol);
    }

    pub fn lookupVulkanProcGuest(self: *Forwarder, library_token: u64, symbol: []const u8) u64 {
        return forwarder_impl_loader_symbols.lookupVulkanProcGuest(self, library_token, symbol);
    }

    /// Vulkan proc-address queries must describe the device that was actually
    /// created. A loader may expose a promoted/core spelling even when this
    /// device was created without the extension that makes the command legal;
    /// returning a synthetic token in that case turns an optional capability
    /// gap into an invalid call later. Keep the command absent exactly as the
    /// native loader would.
    pub fn optionalVulkanProcUnavailable(self: *const Forwarder, symbol: []const u8) bool {
        return forwarder_impl_loader_symbols.optionalVulkanProcUnavailable(self, symbol);
    }

    pub fn allocateGuestSymbol(self: *Forwarder, library_token: u64, symbol: []const u8) u64 {
        return forwarder_impl_loader_symbols.allocateGuestSymbol(self, library_token, symbol);
    }

    /// Return true only for the first lookup of a loader variable. Repeated
    /// lookups are normal Vulkan-loader behavior (Xenia asks for command
    /// addresses throughout the frame loop), so logging every one can create
    /// megabytes of indistinguishable output and obscure the real stop point.
    /// The aggregate repeat count is retained and emitted at powers of two and
    /// in the final forwarding summary.
    pub fn shouldLogVulkanLoaderUnique(self: *const Forwarder) bool {
        return forwarder_impl_loader_symbols.shouldLogVulkanLoaderUnique(self);
    }

    pub fn noteVulkanLoaderLookup(self: *Forwarder, library_token: u64, symbol: []const u8, token: u64) bool {
        return forwarder_impl_loader_symbols.noteVulkanLoaderLookup(self, library_token, symbol, token);
    }

    pub fn noteSuppressedVulkanLoaderLookup(self: *Forwarder) void {
        return forwarder_impl_loader_symbols.noteSuppressedVulkanLoaderLookup(self);
    }

    pub fn readHostAbiStackWord(state: anytype, offset: u64) u64 {
        return forwarder_impl_loader_symbols.readHostAbiStackWord(state, offset);
    }

    /// Construct a checked guest-memory view for the direct PPC adapter. The
    /// function is generic so dyld's small test state can exercise the same
    /// boundary without importing MachOState and creating a module cycle.
    pub fn ppcGuestMemory(state: anytype) ppc_runtime.guest_bridge.GuestMemory {
        return forwarder_impl_loader_symbols.ppcGuestMemory(state);
    }

    pub fn ppcGuestCall(state: anytype) ppc_runtime.guest_bridge.GuestCall {
        return forwarder_impl_loader_symbols.ppcGuestCall(state);
    }

    pub fn materializePpcIdentity(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_loader_symbols.materializePpcIdentity(self, state);
    }

    /// Xenia passes its PageEntry vector through the translated x86 ABI. The
    /// value in RDI is therefore a guest address, not a native pointer that
    /// the ARM64 provider may dereference directly. Resolve the complete
    /// vector through Rosette's guest-memory view before handing it to the
    /// package selector. A partial or unaligned range is rejected so the
    /// optional accelerator can never turn a bad guest pointer into a host
    /// crash; Xenia will fall back to its reference scan.
    pub fn guestHeapEntries(state: anytype, guest_address: u64, total_page_count: u32) ?[*]const u64 {
        return forwarder_impl_loader_symbols.guestHeapEntries(state, guest_address, total_page_count);
    }

    /// The Xenia framework contracts cross the translated ABI as guest
    /// addresses. Never cast one of those addresses to an ARM64 pointer: the
    /// guest address may be backed by a sparse Mach-O mapping, and a malformed
    /// record must be a provider refusal rather than a native crash.
    pub fn readGuestRecord(state: anytype, address: u64, comptime T: type) ?T {
        return forwarder_impl_loader_symbols.readGuestRecord(state, address, T);
    }

    pub fn writeGuestRecord(state: anytype, address: u64, record: anytype) bool {
        return forwarder_impl_loader_symbols.writeGuestRecord(state, address, record);
    }

    pub fn enumFromRaw(comptime T: type, raw: u8) ?T {
        return forwarder_impl_loader_symbols.enumFromRaw(T, raw);
    }

    pub fn dispatchXeniaLaunchAssistQuery(__forwarder_anon_arg_0: *Forwarder, state: anytype) u64 {
        return forwarder_impl_loader_symbols.dispatchXeniaLaunchAssistQuery(__forwarder_anon_arg_0, state);
    }

    pub fn dispatchXeniaLaunchAssistReport(__forwarder_anon_arg_0: *Forwarder, state: anytype) u64 {
        return forwarder_impl_loader_symbols.dispatchXeniaLaunchAssistReport(__forwarder_anon_arg_0, state);
    }

    pub fn dispatchXeniaHostGpuCallbackQuery(__forwarder_anon_arg_0: *Forwarder, state: anytype) u64 {
        return forwarder_impl_loader_symbols.dispatchXeniaHostGpuCallbackQuery(__forwarder_anon_arg_0, state);
    }

    pub fn dispatchXeniaHostGpuCallbackReport(__forwarder_anon_arg_0: *Forwarder, state: anytype) u64 {
        return forwarder_impl_loader_symbols.dispatchXeniaHostGpuCallbackReport(__forwarder_anon_arg_0, state);
    }

    pub fn dispatchGuestSymbol(self: *Forwarder, state: anytype, token: u64) bool {
        return forwarder_impl_loader_symbols.dispatchGuestSymbol(self, state, token);
    }

    // -----------------------------------------------------------------------
    // Real physical device property writes — used when a real VkInstance exists.
    // These copy the actual MoltenVK values into guest memory instead of
    // returning synthetic limits (e.g. maxImageDimension2D: 4096) that cause
    // the guest to create resources exceeding the real device's capacity.
    // -----------------------------------------------------------------------

    /// Write the real VkPhysicalDeviceProperties to guest memory at `output`.
    pub fn writeRealPhysicalDeviceProperties(self: *Forwarder, state: anytype, output: u64) void {
        return forwarder_impl_loader_symbols.writeRealPhysicalDeviceProperties(self, state, output);
    }

    pub fn writeRealPhysicalDeviceFormatProperties(self: *Forwarder, state: anytype, format: u64, output: u64) void {
        return forwarder_impl_loader_symbols.writeRealPhysicalDeviceFormatProperties(self, state, format, output);
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
    pub fn enumerateRealDeviceExtensions(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_loader_symbols.enumerateRealDeviceExtensions(self, state);
    }

    pub fn collectFeatureChain(self: *Forwarder, state: anytype, guest_p_next: u64, scratch: *FeatureChainScratch, copy_guest: bool) bool {
        return forwarder_impl_loader_symbols.collectFeatureChain(self, state, guest_p_next, scratch, copy_guest);
    }

    pub fn queryFeatureChain(self: *Forwarder, scratch: *FeatureChainScratch) bool {
        return forwarder_impl_loader_symbols.queryFeatureChain(self, scratch);
    }

    pub fn prepareDeviceFeatureChain(self: *Forwarder, state: anytype, guest_p_next: u64, scratch: *FeatureChainScratch) bool {
        return forwarder_impl_loader_symbols.prepareDeviceFeatureChain(self, state, guest_p_next, scratch);
    }

    pub fn logFragmentShaderInterlockContract(
        self: *Forwarder,
        state: anytype,
        guest_p_next: u64,
        guest_extension_requested: ?bool,
        stage: []const u8,
    ) void {
        return forwarder_impl_loader_symbols.logFragmentShaderInterlockContract(self, state, guest_p_next, guest_extension_requested, stage);
    }

    /// Write the real VkPhysicalDeviceProperties2 (with pNext chain) to guest memory.
    pub fn writeRealPhysicalDeviceProperties2(self: *Forwarder, state: anytype, output: u64) void {
        return forwarder_impl_loader_symbols.writeRealPhysicalDeviceProperties2(self, state, output);
    }

    /// Write real VkPhysicalDeviceFeatures to guest memory.
    pub fn writeRealPhysicalDeviceFeatures(self: *Forwarder, state: anytype, output: u64) void {
        return forwarder_impl_loader_symbols.writeRealPhysicalDeviceFeatures(self, state, output);
    }

    /// Write the real VkPhysicalDeviceFeatures2 to guest memory.
    pub fn writeRealPhysicalDeviceFeatures2(self: *Forwarder, state: anytype, output: u64) void {
        return forwarder_impl_loader_symbols.writeRealPhysicalDeviceFeatures2(self, state, output);
    }

    /// Write the real VkPhysicalDeviceMemoryProperties to guest memory.
    pub fn writeRealMemoryProperties(self: *Forwarder, state: anytype, output: u64) void {
        return forwarder_impl_loader_symbols.writeRealMemoryProperties(self, state, output);
    }

    /// Write the real VkPhysicalDeviceMemoryProperties2 to guest memory.
    pub fn writeRealMemoryProperties2(self: *Forwarder, state: anytype, output: u64) void {
        return forwarder_impl_loader_symbols.writeRealMemoryProperties2(self, state, output);
    }

    /// Write the real queue family properties to guest memory.
    pub fn writeRealQueueFamilies(self: *Forwarder, state: anytype) void {
        return forwarder_impl_loader_symbols.writeRealQueueFamilies(self, state);
    }

    // -----------------------------------------------------------------------
    // End real property writes
    // -----------------------------------------------------------------------

    pub fn guestStackArg(state: anytype, index: u64) u64 {
        return forwarder_impl_loader_symbols.guestStackArg(state, index);
    }

    pub fn guestFloatArgument(state: anytype, index: usize) u32 {
        return forwarder_impl_loader_symbols.guestFloatArgument(state, index);
    }

    pub fn copyGuestStructs(comptime T: type, state: anytype, address: u64, count: u64, destination: []T) bool {
        return forwarder_impl_loader_symbols.copyGuestStructs(T, state, address, count, destination);
    }

    pub fn copyGuestBytes(state: anytype, address: u64, count: u64, destination: []u8) bool {
        return forwarder_impl_loader_symbols.copyGuestBytes(state, address, count, destination);
    }

    pub fn graphicsStateTraceEnabled(self: *Forwarder) bool {
        return forwarder_impl_loader_symbols.graphicsStateTraceEnabled(self);
    }

    pub fn guestOutputTopologyRepairEnabled(self: *Forwarder) bool {
        return forwarder_impl_loader_symbols.guestOutputTopologyRepairEnabled(self);
    }

    /// State recording is needed for the narrowly gated guest-output repair
    /// even when the verbose graphics dump is disabled.  The recorder remains
    /// bounded and the repair path itself only rebinds a pipeline immediately
    /// before the matching four-vertex draw.
    pub fn graphicsStateTrackingEnabled(self: *Forwarder) bool {
        return forwarder_impl_loader_symbols.graphicsStateTrackingEnabled(self);
    }

    pub fn graphicsStateHash(bytes: []const u8) u64 {
        return forwarder_impl_loader_symbols.graphicsStateHash(bytes);
    }

    pub fn vulkanTopologyLabel(topology: u32) []const u8 {
        return forwarder_impl_loader_symbols.vulkanTopologyLabel(topology);
    }

    pub fn trackedGraphicsPipeline(self: *const Forwarder, real: u64) ?*const TrackedGraphicsPipeline {
        return forwarder_impl_loader_symbols.trackedGraphicsPipeline(self, real);
    }

    pub fn trackedPipelineLayout(self: *const Forwarder, real: u64) ?*const TrackedPipelineLayout {
        return forwarder_impl_loader_symbols.trackedPipelineLayout(self, real);
    }

    pub fn rememberPipelineLayout(self: *Forwarder, real: u64, info: []const u8) void {
        return forwarder_impl_loader_symbols.rememberPipelineLayout(self, real, info);
    }

    pub fn forgetPipelineLayout(self: *Forwarder, real: u64) void {
        return forwarder_impl_loader_symbols.forgetPipelineLayout(self, real);
    }

    /// Recognize Xenia's guest-output paint pipeline without relying on a
    /// shader name.  The topology is the only field Rosette repairs, and every
    /// other requirement below is part of the presenter contract: two shader
    /// stages, no vertex input, one dynamic viewport/scissor, one colour
    /// attachment, no tessellation/depth work, and a vertex push range large
    /// enough for the four rectangle floats.
    /// `ROSETTE_VULKAN_RECT_EXPAND=0` turns the expansion off and restores
    /// the behaviour of every run before it existed: one shaded triangle per
    /// rectangle and a diagonal seam across the rest.
    pub fn rectExpandEnabled(self: *Forwarder) bool {
        return forwarder_impl_loader_symbols.rectExpandEnabled(self);
    }

    /// Rewrite a marshalled vertex shader in place, returning the buffer that
    /// has to outlive the driver call. A refusal leaves the module exactly as
    /// the guest wrote it.
    const RectExpansion = struct {
        words: []u32,
        original_code: ?*const anyopaque,
        original_size: usize,
    };

    pub fn noteRectangleTransformRefusal(
        self: *Forwarder,
        refusal: gpu_vulkan.rect_list_expand.Refusal,
        synthetic_module: u64,
        spirv_hash: u64,
        code_bytes: usize,
        cull_distance_site: ?gpu_vulkan.rect_list_expand.CullDistanceSite,
    ) void {
        return forwarder_impl_loader_symbols.noteRectangleTransformRefusal(self, refusal, synthetic_module, spirv_hash, code_bytes, cull_distance_site);
    }

    pub fn expandRectangleListShader(self: *Forwarder, info: []u8, synthetic_module: u64, spirv_hash: u64) ?RectExpansion {
        return forwarder_impl_loader_symbols.expandRectangleListShader(self, info, synthetic_module, spirv_hash);
    }

    pub fn robustAccessEnabled(self: *Forwarder) bool {
        return forwarder_impl_loader_symbols.robustAccessEnabled(self);
    }

    pub fn correctHdrResolve(self: *Forwarder, info: []u8) !?[]u32 {
        return forwarder_impl_loader_symbols.correctHdrResolve(self, info);
    }

    /// Restore pixel-center coordinates expected by Xenia, retaining the
    /// driver's required sample lanes, narrowed masks and atomic ordering.
    pub fn normalizeFsiPixelFrequency(self: *Forwarder, info: []u8) !?[]u32 {
        return forwarder_impl_loader_symbols.normalizeFsiPixelFrequency(self, info);
    }

    pub fn printFsiPixelFrequencyReport(self: *const Forwarder) void {
        return forwarder_impl_loader_symbols.printFsiPixelFrequencyReport(self);
    }

    const RobustHardening = struct {
        words: []u32,
    };

    /// Clamp every dynamic array, vector and matrix index of the module about
    /// to be created into its bound range (`robust_access.zig`). Runs after the
    /// rectangle rewrite, on exactly the words the driver will receive.
    pub fn hardenShaderModule(self: *Forwarder, info: []u8, synthetic_module: u64) error{UnsafeShader}!?RobustHardening {
        return forwarder_impl_loader_symbols.hardenShaderModule(self, info, synthetic_module);
    }

    pub fn fsiUpdateShaderBoundsBudget(self: *Forwarder) void {
        return forwarder_impl_loader_symbols.fsiUpdateShaderBoundsBudget(self);
    }

    pub fn printRobustAccessReport(self: *const Forwarder) void {
        return forwarder_impl_loader_symbols.printRobustAccessReport(self);
    }

    pub fn noteRectangleExpandedModule(self: *Forwarder, synthetic_module: u64) void {
        return forwarder_impl_loader_symbols.noteRectangleExpandedModule(self, synthetic_module);
    }

    pub fn rectangleExpandedModule(self: *const Forwarder, synthetic_module: u64) bool {
        return forwarder_impl_loader_symbols.rectangleExpandedModule(self, synthetic_module);
    }

    pub fn noteRectangleExpandedPipeline(self: *Forwarder, synthetic_pipeline: u64) void {
        return forwarder_impl_loader_symbols.noteRectangleExpandedPipeline(self, synthetic_pipeline);
    }

    pub fn forgetRectangleExpandedPipeline(self: *Forwarder, synthetic_pipeline: u64) void {
        return forwarder_impl_loader_symbols.forgetRectangleExpandedPipeline(self, synthetic_pipeline);
    }

    /// Prove a present's completion without waiting for it. One host fence
    /// rides behind a present in queue order; a later present polls it. When
    /// it has signalled, every present up to the one it followed is complete.
    /// The present in hand is credited now unless the queue has reported a
    /// failure: its fence is in flight, and a failure surfaces as a counted
    /// fence error and a device-loss result, never as a silent success.
    pub fn trackPresentCompletion(self: *Forwarder, queue: abi.Queue) bool {
        return forwarder_impl_loader_symbols.trackPresentCompletion(self, queue);
    }

    pub fn rectExpandCommandState(self: *Forwarder, command_buffer: u64) *RectExpandCommandState {
        return forwarder_impl_loader_symbols.rectExpandCommandState(self, command_buffer);
    }

    pub fn rectangleExpandedPipeline(self: *const Forwarder, synthetic_pipeline: u64) bool {
        return forwarder_impl_loader_symbols.rectangleExpandedPipeline(self, synthetic_pipeline);
    }

    /// The topology Xenia gives the rectangle fallback: a two-triangle strip
    /// per rectangle, separated by primitive restarts.
    pub fn isRectangleStripPipeline(root: *const abi.GraphicsPipelineCreateInfo) bool {
        return forwarder_impl_loader_symbols.isRectangleStripPipeline(root);
    }

    pub fn isGuestOutputPaintPipeline(self: *const Forwarder, root: *const abi.GraphicsPipelineCreateInfo) bool {
        return forwarder_impl_loader_symbols.isGuestOutputPaintPipeline(self, root);
    }

    pub fn rememberGraphicsPipeline(self: *Forwarder, real: u64, root: *const abi.GraphicsPipelineCreateInfo, repair_real: u64, guest_output_candidate: bool, fsi: fsi_diagnostics.PipelineIdentity) void {
        return forwarder_impl_loader_symbols.rememberGraphicsPipeline(self, real, root, repair_real, guest_output_candidate, fsi);
    }

    pub fn forgetGraphicsPipeline(self: *Forwarder, real: u64) void {
        return forwarder_impl_loader_symbols.forgetGraphicsPipeline(self, real);
    }

    pub fn noteCommandPipelineState(self: *Forwarder, command_buffer: u64, guest_pipeline: u64, real_pipeline: u64, bind_point: u64) void {
        return forwarder_impl_loader_symbols.noteCommandPipelineState(self, command_buffer, guest_pipeline, real_pipeline, bind_point);
    }

    pub fn noteCommandViewport(self: *Forwarder, command_buffer: u64, first: u64, count: u64, values: []const abi.Viewport) void {
        return forwarder_impl_loader_symbols.noteCommandViewport(self, command_buffer, first, count, values);
    }

    pub fn noteCommandScissor(self: *Forwarder, command_buffer: u64, first: u64, count: u64, values: []const abi.Rect2D) void {
        return forwarder_impl_loader_symbols.noteCommandScissor(self, command_buffer, first, count, values);
    }

    pub fn noteCommandPushConstants(self: *Forwarder, command_buffer: u64, guest_layout: u64, real_layout: u64, stage_flags: u64, offset: u64, size: u64, bytes: []const u8) void {
        return forwarder_impl_loader_symbols.noteCommandPushConstants(self, command_buffer, guest_layout, real_layout, stage_flags, offset, size, bytes);
    }

    /// Rebind the strip twin only for Xenia's exact guest-output draw shape.
    /// Vulkan bakes primitive topology into a graphics pipeline, so correcting
    /// this at the draw boundary is the smallest place that can repair a list
    /// pipeline without changing any ordinary scene geometry.
    pub fn repairGuestOutputTopology(
        self: *Forwarder,
        command_buffer_guest: u64,
        command_buffer_real: abi.CommandBuffer,
        vertex_count: u64,
        instance_count: u64,
        first_vertex: u64,
        first_instance: u64,
    ) void {
        return forwarder_impl_loader_symbols.repairGuestOutputTopology(self, command_buffer_guest, command_buffer_real, vertex_count, instance_count, first_vertex, first_instance);
    }

    /// The FSI guard's state, allocated on first use unless
    /// ROSETTE_FSI_WATCHDOG_GUARD=0 turned it off.
    pub fn fsiGuardInstance(self: *Forwarder) ?*FsiGuard {
        return forwarder_impl_loader_symbols.fsiGuardInstance(self);
    }

    pub fn fsiArmedGuard(self: *const Forwarder) ?*FsiGuard {
        return forwarder_impl_loader_symbols.fsiArmedGuard(self);
    }

    pub fn fsiDirectoryEntry(guard: *FsiGuard, guest: u64) ?*FsiCommandBufferEntry {
        return forwarder_impl_loader_symbols.fsiDirectoryEntry(guard, guest);
    }

    pub fn fsiNoteCommandBuffersAllocated(self: *Forwarder, synthetics: []const u64, guest_pool: u64, level: u32) void {
        return forwarder_impl_loader_symbols.fsiNoteCommandBuffersAllocated(self, synthetics, guest_pool, level);
    }

    pub fn fsiRecording(self: *const Forwarder, guest: u64) ?*fsi_chain.Recording {
        return forwarder_impl_loader_symbols.fsiRecording(self, guest);
    }

    pub fn fsiReleaseRecording(guard: *FsiGuard, recording: *fsi_chain.Recording) void {
        return forwarder_impl_loader_symbols.fsiReleaseRecording(guard, recording);
    }

    /// vkBeginCommandBuffer succeeded on `own`. Only command buffers begun
    /// after the guard is armed are followed, so every recorded shadow holds
    /// all the state since the begin.
    pub fn fsiBeginRecording(self: *Forwarder, guest: u64, own: abi.CommandBuffer, usage_flags: u32, has_inheritance: bool) void {
        return forwarder_impl_loader_symbols.fsiBeginRecording(self, guest, own, usage_flags, has_inheritance);
    }

    pub fn fsiForgetRecording(self: *Forwarder, guest: u64) void {
        return forwarder_impl_loader_symbols.fsiForgetRecording(self, guest);
    }

    pub fn fsiForgetCommandBuffer(self: *Forwarder, guest: u64) void {
        return forwarder_impl_loader_symbols.fsiForgetCommandBuffer(self, guest);
    }

    pub fn fsiResetCommandPool(self: *Forwarder, guest_pool: u64, destroyed: bool) void {
        return forwarder_impl_loader_symbols.fsiResetCommandPool(self, guest_pool, destroyed);
    }

    /// The real command buffer a command for `guest` is recorded into: the
    /// newest chunk once the recording has been split, otherwise `own`.
    pub fn fsiCommandTarget(self: *const Forwarder, guest: u64, own: abi.CommandBuffer) abi.CommandBuffer {
        return forwarder_impl_loader_symbols.fsiCommandTarget(self, guest, own);
    }

    pub fn fsiShadow(self: *const Forwarder, guest: u64) ?*fsi_chain.Shadow {
        return forwarder_impl_loader_symbols.fsiShadow(self, guest);
    }

    pub fn fsiNoteShadowBlock(self: *Forwarder, guest: u64, block: fsi_chain.Block) void {
        return forwarder_impl_loader_symbols.fsiNoteShadowBlock(self, guest, block);
    }

    pub fn fsiNoteRenderPassCreated(self: *Forwarder, real_render_pass: u64, info: []const u8) void {
        return forwarder_impl_loader_symbols.fsiNoteRenderPassCreated(self, real_render_pass, info);
    }

    pub fn fsiForgetRenderPass(self: *Forwarder, real_render_pass: u64) void {
        return forwarder_impl_loader_symbols.fsiForgetRenderPass(self, real_render_pass);
    }

    pub fn fsiRenderPassSplittable(guard: *const FsiGuard, real_render_pass: u64) bool {
        return forwarder_impl_loader_symbols.fsiRenderPassSplittable(guard, real_render_pass);
    }

    pub fn fsiNoteFramebufferCreated(self: *Forwarder, info: []const u8) void {
        return forwarder_impl_loader_symbols.fsiNoteFramebufferCreated(self, info);
    }

    pub fn fsiNoteBeginRenderPass(self: *Forwarder, guest: u64, begin: *const abi.RenderPassBeginInfo, contents: u32) void {
        return forwarder_impl_loader_symbols.fsiNoteBeginRenderPass(self, guest, begin, contents);
    }

    pub fn fsiRasterPipelinePass(self: *Forwarder, original: u64, samples: u32) PipelineMarshalFailure!u64 {
        return forwarder_impl_loader_symbols.fsiRasterPipelinePass(self, original, samples);
    }

    /// Restart the same command buffer, not a new submission. Vulkan state
    /// bindings persist across compatible empty passes, and MoltenVK reissues
    /// them into its new encoder. No guest shader or EDRAM buffer is changed.
    pub fn fsiRasterBeforeCommand(self: *Forwarder, guest: u64, name_hash: u64, name: []const u8) bool {
        return forwarder_impl_loader_symbols.fsiRasterBeforeCommand(self, guest, name_hash, name);
    }

    pub fn printFsiRasterReport(self: *const Forwarder) void {
        return forwarder_impl_vulkan_objects.printFsiRasterReport(self);
    }

    pub fn fsiRasterShutdown(self: *Forwarder) void {
        return forwarder_impl_vulkan_objects.fsiRasterShutdown(self);
    }

    /// Called for every vkCmd* before its target command buffer is resolved:
    /// follows the recording's splittability and, before an FSI draw that
    /// would exceed the budget, moves the recording to a new chunk.
    pub fn fsiNoteCommand(self: *Forwarder, guest: u64, name_hash: u64, name: []const u8) void {
        return forwarder_impl_vulkan_objects.fsiNoteCommand(self, guest, name_hash, name);
    }

    pub fn fsiBeforeDraw(self: *Forwarder, guard: *FsiGuard, recording: *fsi_chain.Recording, guest: u64) void {
        return forwarder_impl_vulkan_objects.fsiBeforeDraw(self, guard, recording, guest);
    }

    pub fn fsiChunkCommandPool(self: *Forwarder, guard: *FsiGuard, device: abi.Device) ?abi.CommandPool {
        return forwarder_impl_vulkan_objects.fsiChunkCommandPool(self, guard, device);
    }

    pub fn fsiAcquireChunk(self: *Forwarder, guard: *FsiGuard, device: abi.Device) ?u64 {
        return forwarder_impl_vulkan_objects.fsiAcquireChunk(self, guard, device);
    }

    /// Close the recording's current real command buffer between two FSI
    /// draws and continue in a fresh chunk (`gpu/vulkan/fsi/chain.zig`).
    pub fn fsiSplitRecording(self: *Forwarder, guard: *FsiGuard, recording: *fsi_chain.Recording) bool {
        return forwarder_impl_vulkan_objects.fsiSplitRecording(self, guard, recording);
    }

    pub fn fsiSubmitNeedsExpansion(self: *const Forwarder, synthetics: *const [8][256]u64, counts: *const [8]u32, submit_count: u32) bool {
        return forwarder_impl_vulkan_objects.fsiSubmitNeedsExpansion(self, synthetics, counts, submit_count);
    }

    pub fn fsiStartMonitor(self: *Forwarder, guard: *FsiGuard, device: abi.Device) bool {
        return forwarder_impl_vulkan_objects.fsiStartMonitor(self, guard, device);
    }

    pub fn fsiTimingFence(self: *Forwarder, guard: *FsiGuard, device: abi.Device) u64 {
        return forwarder_impl_vulkan_objects.fsiTimingFence(self, guard, device);
    }

    pub fn fsiWaitForRoom(state: anytype, monitor: *fsi_timing.Monitor, incoming_submit_infos: usize, isolated: bool) fsi_timing.RoomResult {
        return forwarder_impl_vulkan_objects.fsiWaitForRoom(state, monitor, incoming_submit_infos, isolated);
    }

    /// Submit one or two adjacent VkSubmitInfo batches under one host queue
    /// call. MoltenVK still builds one Metal command buffer per VkSubmitInfo;
    /// this only avoids repeating the host entry-point/queue-lock overhead.
    /// `guest_fence` remains a trailing empty submission so every actual
    /// segment group retains its independent timing fence.
    pub fn fsiSubmitSegmentGroup(
        self: *Forwarder,
        guard: *FsiGuard,
        queue: abi.Queue,
        submit_fn: abi.PfnQueueSubmit,
        device: abi.Device,
        segments: []const FsiSegment,
        segment_buffers: []const [fsi_segment_command_capacity]abi.CommandBuffer,
        last: bool,
        guest_fence: u64,
        queue_submit: u64,
        runtime_state: anytype,
    ) abi.Result {
        return forwarder_impl_vulkan_objects.fsiSubmitSegmentGroup(self, guard, queue, submit_fn, device, segments, segment_buffers, last, guest_fence, queue_submit, runtime_state);
    }

    /// Complete the current segment and either coalesce it with its predecessor
    /// or submit the predecessor alone before rotating the two bounded slots.
    pub fn fsiAdvanceSegmentSlots(
        self: *Forwarder,
        guard: *FsiGuard,
        queue: abi.Queue,
        submit_fn: abi.PfnQueueSubmit,
        device: abi.Device,
        segments: *[2]FsiSegment,
        segment_buffers: *[2][fsi_segment_command_capacity]abi.CommandBuffer,
        pending: *?usize,
        current: usize,
        queue_submit: u64,
        runtime_state: anytype,
    ) abi.Result {
        return forwarder_impl_vulkan_objects.fsiAdvanceSegmentSlots(self, guard, queue, submit_fn, device, segments, segment_buffers, pending, current, queue_submit, runtime_state);
    }

    /// Submit a guest vkQueueSubmit while preserving every guest batch,
    /// semaphore boundary, and FSI chunk as a distinct VkSubmitInfo. Adjacent
    /// chunks from one guest command buffer are placed in the same host
    /// vkQueueSubmit call, reducing host queue-gate/API overhead without
    /// merging their Metal command buffers. A timing fence after each group
    /// bounds and measures at most two such command buffers; the in-flight
    /// group limit keeps the actual queued command-buffer limit unchanged.
    pub fn fsiSubmitExpanded(
        self: *Forwarder,
        queue: abi.Queue,
        submit_fn: abi.PfnQueueSubmit,
        real_submits: *const [8]abi.SubmitInfo,
        synthetics: *const [8][256]u64,
        counts: *const [8]u32,
        submit_count: u32,
        guest_fence: u64,
        runtime_state: anytype,
    ) abi.Result {
        return forwarder_impl_vulkan_objects.fsiSubmitExpanded(self, queue, submit_fn, real_submits, synthetics, counts, submit_count, guest_fence, runtime_state);
    }

    pub fn fsiEvidenceEnabled(self: *Forwarder) bool {
        return forwarder_impl_vulkan_objects.fsiEvidenceEnabled(self);
    }

    pub fn fsiSaveShaderEvidence(self: *Forwarder, guest: u64, info: *const marshal.ShaderModuleCreateInfo, version: gpu_vulkan.fsi.evidence.Version) void {
        return forwarder_impl_vulkan_objects.fsiSaveShaderEvidence(self, guest, info, version);
    }

    pub fn fsiPrintEscalationContext(self: *Forwarder, guard: *FsiGuard) void {
        return forwarder_impl_vulkan_objects.fsiPrintEscalationContext(self, guard);
    }

    pub fn printFsiGuardReport(self: *const Forwarder) void {
        return forwarder_impl_vulkan_objects.printFsiGuardReport(self);
    }

    /// Stop the timing watcher and release every bridge-owned Vulkan object
    /// before the device goes away.
    pub fn fsiGuardShutdown(self: *Forwarder) void {
        return forwarder_impl_vulkan_objects.fsiGuardShutdown(self);
    }

    pub fn noteFsiDraw(self: *Forwarder, command_buffer: u64, kind: fsi_diagnostics.DrawKind) void {
        return forwarder_impl_vulkan_objects.noteFsiDraw(self, command_buffer, kind);
    }

    pub fn noteFsiDrawWithParameters(
        self: *Forwarder,
        command_buffer: u64,
        kind: fsi_diagnostics.DrawKind,
        parameters: fsi_diagnostics.DrawParameters,
    ) void {
        return forwarder_impl_vulkan_objects.noteFsiDrawWithParameters(self, command_buffer, kind, parameters);
    }

    pub fn noteGraphicsDrawState(
        self: *Forwarder,
        command_buffer: u64,
        kind: []const u8,
        vertex_count: u64,
        instance_count: u64,
        first_vertex_or_index: u64,
        auxiliary: u64,
        first_instance: u64,
    ) void {
        return forwarder_impl_vulkan_objects.noteGraphicsDrawState(self, command_buffer, kind, vertex_count, instance_count, first_vertex_or_index, auxiliary, first_instance);
    }

    pub fn copyGuestHandleArray(
        self: *Forwarder,
        state: anytype,
        address: u64,
        count: u64,
        destination: []u64,
        kind: GuestHandleKind,
    ) bool {
        return forwarder_impl_vulkan_objects.copyGuestHandleArray(self, state, address, count, destination, kind);
    }

    pub fn copyGuestImageBarriers(self: *Forwarder, state: anytype, address: u64, count: u64, destination: []abi.ImageMemoryBarrier) bool {
        return forwarder_impl_vulkan_objects.copyGuestImageBarriers(self, state, address, count, destination);
    }

    /// Keep command-shape evidence useful without turning a long-running
    /// title into a per-command log stream. The first observation of each
    /// category is actionable; the counters make the final/state snapshot
    /// answer whether that category continued afterward.
    pub fn noteVulkanCommandShape(self: *Forwarder, name: []const u8, command_buffer: u64) void {
        return forwarder_impl_vulkan_objects.noteVulkanCommandShape(self, name, command_buffer);
    }

    /// Count native work only after a typed driver entry point was invoked.
    /// The tuple has the function's declared types, so @intCast/@bitCast keep
    /// their ABI context rather than becoming untyped forwarding values.
    pub fn callNativeVulkanCommand(self: *Forwarder, function: anytype, arguments: std.meta.ArgsTuple(@typeInfo(@TypeOf(function)).pointer.child)) void {
        return forwarder_impl_vulkan_objects.callNativeVulkanCommand(self, function, arguments);
    }

    pub fn asyncVulkanWorker(self: *Forwarder) ?*async_vulkan_command.Worker {
        return forwarder_impl_vulkan_objects.asyncVulkanWorker(self);
    }

    pub fn queueAsyncVulkanCommand(self: *Forwarder, job: async_vulkan_command.Job) bool {
        return forwarder_impl_vulkan_objects.queueAsyncVulkanCommand(self, job);
    }

    pub fn drainAsyncVulkanCommands(self: *Forwarder) void {
        return forwarder_impl_vulkan_objects.drainAsyncVulkanCommands(self);
    }

    /// Complete the command-worker watermark only when it is still pending.
    /// FSI split boundaries are frequent; after the worker has caught up, the
    /// atomic completion check avoids re-entering its mutex just to discover
    /// that the barrier is already satisfied.
    pub fn drainAsyncVulkanCommandsIfPending(self: *Forwarder) bool {
        return forwarder_impl_vulkan_objects.drainAsyncVulkanCommandsIfPending(self);
    }

    pub fn stopAsyncVulkanCommandWorker(self: *Forwarder) void {
        return forwarder_impl_vulkan_objects.stopAsyncVulkanCommandWorker(self);
    }

    pub fn noteVulkanCommandRefusal(self: *Forwarder, source_line: u32) void {
        return forwarder_impl_vulkan_objects.noteVulkanCommandRefusal(self, source_line);
    }

    pub fn nativeVulkanCommandFunctionAvailable(self: *const Forwarder, name: []const u8) bool {
        return forwarder_impl_vulkan_objects.nativeVulkanCommandFunctionAvailable(self, name);
    }

    pub fn finishVulkanCommandAdmission(self: *Forwarder, state: anytype, name: []const u8, command_index: ?usize, forwarded: bool) void {
        return forwarder_impl_vulkan_objects.finishVulkanCommandAdmission(self, state, name, command_index, forwarded);
    }

    pub fn printVulkanCommandRefusal(__forwarder_anon_arg_0: *const Forwarder, name: []const u8, record: *const VulkanCommandAdmission) void {
        return forwarder_impl_vulkan_objects.printVulkanCommandRefusal(__forwarder_anon_arg_0, name, record);
    }

    pub fn printVulkanCommandAdmission(self: *const Forwarder) void {
        return forwarder_impl_vulkan_objects.printVulkanCommandAdmission(self);
    }

    pub fn forwardVulkanCommand(self: *Forwarder, state: anytype, requested_hash: u64, requested_name: []const u8) void {
        return forwarder_impl_vulkan_objects.forwardVulkanCommand(self, state, requested_hash, requested_name);
    }

    pub fn forwardPipelineBarrier2(self: *Forwarder, state: anytype, command_buffer: abi.CommandBuffer) void {
        return forwarder_impl_vulkan_objects.forwardPipelineBarrier2(self, state, command_buffer);
    }

    /// vkUpdateDescriptorSets is refused whole when any handle or array in it
    /// cannot be translated, and the refusal used to be a bare `return`: the
    /// update was counted as made, the set kept whatever it held before, and a
    /// shader sampled that. Every refusal is now counted by reason and the
    /// first of each reason is printed with its descriptor type and binding.
    pub fn updateDescriptorSets(self: *Forwarder, state: anytype) void {
        return forwarder_impl_vulkan_objects.updateDescriptorSets(self, state);
    }

    pub fn updateDescriptorSetsNative(self: *Forwarder, state: anytype, failure: *DescriptorUpdateFailureDetails) ?DescriptorUpdateRefusal {
        return forwarder_impl_command_tracking.updateDescriptorSetsNative(self, state, failure);
    }

    pub fn forwardPushDescriptorSet(self: *Forwarder, state: anytype, command_buffer: abi.CommandBuffer) void {
        return forwarder_impl_command_tracking.forwardPushDescriptorSet(self, state, command_buffer);
    }

    pub fn pipelineCachePath(self: *Forwarder) ?[]const u8 {
        return forwarder_impl_command_tracking.pipelineCachePath(self);
    }

    pub fn readPipelineCacheFile(self: *Forwarder, destination: []u8) usize {
        return forwarder_impl_command_tracking.readPipelineCacheFile(self, destination);
    }

    pub fn savePipelineCacheFile(self: *Forwarder, data: []const u8) void {
        return forwarder_impl_command_tracking.savePipelineCacheFile(self, data);
    }

    pub fn persistPipelineCache(self: *Forwarder, cache: abi.PipelineCache) void {
        return forwarder_impl_command_tracking.persistPipelineCache(self, cache);
    }

    pub fn updateDescriptorSetWithTemplate(self: *Forwarder, state: anytype) void {
        return forwarder_impl_command_tracking.updateDescriptorSetWithTemplate(self, state);
    }

    pub fn getPipelineCacheData(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_command_tracking.getPipelineCacheData(self, state);
    }

    pub fn destroyVulkanObject(self: *Forwarder, state: anytype, name: []const u8) u64 {
        return forwarder_impl_command_tracking.destroyVulkanObject(self, state, name);
    }

    pub fn nextVulkanObject(self: *Forwarder) u64 {
        return forwarder_impl_command_tracking.nextVulkanObject(self);
    }

    /// Record one reverse-handle insertion without allowing a bounded table
    /// failure to become a process-wide panic.  The map itself stays generic;
    /// this wrapper is where the forwarder can attach an entry-point name to
    /// the resource event and keep the end-of-run accounting complete.
    pub fn mapVulkanHandle(self: *Forwarder, map: []HandleMap, synthetic: u64, real: RealHandle, entry_point: []const u8) bool {
        return forwarder_impl_command_tracking.mapVulkanHandle(self, map, synthetic, real, entry_point);
    }

    pub fn mapVulkanHandleOwned(self: *Forwarder, map: []HandleMap, synthetic: u64, real: RealHandle, owner: u64, entry_point: []const u8) bool {
        return forwarder_impl_command_tracking.mapVulkanHandleOwned(self, map, synthetic, real, owner, entry_point);
    }

    pub fn releaseVulkanHandle(self: *Forwarder, map: []HandleMap, synthetic: u64) bool {
        return forwarder_impl_command_tracking.releaseVulkanHandle(self, map, synthetic);
    }

    /// Return the number of free reverse-map slots for a create entry point.
    /// A null result means that the call is modelled without this native map.
    pub fn availableVulkanMapSlots(self: *const Forwarder, entry_point: []const u8) ?usize {
        return forwarder_impl_command_tracking.availableVulkanMapSlots(self, entry_point);
    }

    pub fn noteVulkanMapCapacityRefusal(self: *Forwarder, entry_point: []const u8, required: usize, available: usize) void {
        return forwarder_impl_command_tracking.noteVulkanMapCapacityRefusal(self, entry_point, required, available);
    }

    /// Descriptor-set mappings are invalidated by both vkResetDescriptorPool
    /// and vkDestroyDescriptorPool.  Reclaim from the map's owner field first;
    /// the provenance table is a compatibility fallback for mappings created
    /// by older paths that predate owner tagging.
    pub fn reclaimDescriptorSetsForPool(self: *Forwarder, pool: u64, reason: []const u8) usize {
        return forwarder_impl_command_tracking.reclaimDescriptorSetsForPool(self, pool, reason);
    }

    /// Recover mappings left behind by an unusual destroy ordering or by a
    /// guest that reset the driver pool through an unrecognised alias.  A set
    /// whose owning pool is no longer mapped cannot be submitted safely, so
    /// retaining it only burns a slot and eventually recreates the old panic.
    pub fn reclaimOrphanedDescriptorSets(self: *Forwarder) usize {
        return forwarder_impl_command_tracking.reclaimOrphanedDescriptorSets(self);
    }

    pub fn logVulkanHandleMapState(self: *const Forwarder) void {
        return forwarder_impl_command_tracking.logVulkanHandleMapState(self);
    }

    pub fn trackedImageView(self: *const Forwarder, synthetic: u64) ?TrackedImageView {
        return forwarder_impl_command_tracking.trackedImageView(self, synthetic);
    }

    /// Remember which image a view shows. False when the table is full.
    pub fn recordImageView(self: *Forwarder, synthetic: u64, image: u64) bool {
        return forwarder_impl_command_tracking.recordImageView(self, synthetic, image);
    }

    pub fn trackedFramebuffer(self: *const Forwarder, synthetic: u64) ?TrackedFramebuffer {
        return forwarder_impl_command_tracking.trackedFramebuffer(self, synthetic);
    }

    pub fn trackedRenderPass(self: *const Forwarder, synthetic: u64) ?TrackedRenderPass {
        return forwarder_impl_command_tracking.trackedRenderPass(self, synthetic);
    }

    pub fn trackedDescriptorSet(self: *const Forwarder, synthetic: u64) ?TrackedDescriptorSet {
        return forwarder_impl_command_tracking.trackedDescriptorSet(self, synthetic);
    }

    pub fn noteTargetOverflow(self: *Forwarder, kind: TargetOverflowKind) void {
        return forwarder_impl_command_tracking.noteTargetOverflow(self, kind);
    }

    pub fn mutableDescriptorSet(self: *Forwarder, synthetic: u64) ?*TrackedDescriptorSet {
        return forwarder_impl_command_tracking.mutableDescriptorSet(self, synthetic);
    }

    pub fn noteDescriptorSetPool(self: *Forwarder, synthetic: u64, pool: u64) void {
        return forwarder_impl_command_tracking.noteDescriptorSetPool(self, synthetic, pool);
    }

    pub fn isDescriptorImageType(descriptor_type: u32) bool {
        return forwarder_impl_command_tracking.isDescriptorImageType(descriptor_type);
    }

    pub fn noteDescriptorSetImage(self: *Forwarder, set: u64, binding: u32, array_element: u32, image: u64, image_view: u64, unknown: bool) void {
        return forwarder_impl_command_tracking.noteDescriptorSetImage(self, set, binding, array_element, image, image_view, unknown);
    }

    pub fn markDescriptorSetUnknown(self: *Forwarder, set: u64) void {
        return forwarder_impl_command_tracking.markDescriptorSetUnknown(self, set);
    }

    pub fn noteDescriptorImageInfo(self: *Forwarder, set: u64, binding: u32, array_element: u32, info: abi.DescriptorImageInfo) void {
        return forwarder_impl_command_tracking.noteDescriptorImageInfo(self, set, binding, array_element, info);
    }

    pub fn trackDescriptorImageWrites(self: *Forwarder, state: anytype, writes: []const abi.WriteDescriptorSet) void {
        return forwarder_impl_command_tracking.trackDescriptorImageWrites(self, state, writes);
    }

    pub fn trackTexelDescriptorWrites(self: *Forwarder, state: anytype, writes: []const abi.WriteDescriptorSet) void {
        return forwarder_impl_command_tracking.trackTexelDescriptorWrites(self, state, writes);
    }

    pub fn auditCommandTexelCustody(self: *Forwarder, command_buffer: u64) void {
        return forwarder_impl_command_tracking.auditCommandTexelCustody(self, command_buffer);
    }

    pub fn copyDescriptorSetImages(self: *Forwarder, copy: abi.CopyDescriptorSet) void {
        return forwarder_impl_command_tracking.copyDescriptorSetImages(self, copy);
    }

    pub fn trackDescriptorSetCopies(self: *Forwarder, copies: []const abi.CopyDescriptorSet) void {
        return forwarder_impl_command_tracking.trackDescriptorSetCopies(self, copies);
    }

    pub fn trackDescriptorTemplateImages(
        self: *Forwarder,
        state: anytype,
        destination: u64,
        record: *const DescriptorUpdateTemplateRecord,
        guest_data: u64,
    ) void {
        return forwarder_impl_command_tracking.trackDescriptorTemplateImages(self, state, destination, record, guest_data);
    }

    pub fn addCommandSampledImage(self: *Forwarder, command_buffer: u64, image: u64) void {
        return forwarder_impl_command_tracking.addCommandSampledImage(self, command_buffer, image);
    }

    pub fn noteCommandSampledImageUnknown(self: *Forwarder, command_buffer: u64) void {
        return forwarder_impl_command_tracking.noteCommandSampledImageUnknown(self, command_buffer);
    }

    pub fn noteCommandDescriptorSet(self: *Forwarder, command_buffer: u64, set: u64) void {
        return forwarder_impl_command_tracking.noteCommandDescriptorSet(self, command_buffer, set);
    }

    pub fn noteCommandBoundDescriptorSet(self: *Forwarder, command_buffer: u64, set_index: u32, set: u64) void {
        return forwarder_impl_command_tracking.noteCommandBoundDescriptorSet(self, command_buffer, set_index, set);
    }

    /// The image the render pass being recorded into `command_buffer`
    /// writes, taken as the framebuffer's first attachment. Xenia's presenter
    /// paint and its gamma pass each have exactly one colour attachment, and
    /// its scene passes put colour before depth.
    pub fn noteCommandPassTarget(self: *Forwarder, command_buffer: u64, framebuffer: u64) void {
        return forwarder_impl_command_tracking.noteCommandPassTarget(self, command_buffer, framebuffer);
    }

    const CommandPassTarget = struct {
        image: u64,
        source: fsi_diagnostics.TargetSource,
    };

    pub fn commandPassTarget(self: *const Forwarder, command_buffer: u64) ?CommandPassTarget {
        return forwarder_impl_command_tracking.commandPassTarget(self, command_buffer);
    }

    pub fn noteCommandDynamicTarget(self: *Forwarder, command_buffer: u64, guest_image_view: u64) void {
        return forwarder_impl_command_tracking.noteCommandDynamicTarget(self, command_buffer, guest_image_view);
    }

    pub fn clearCommandPassTarget(self: *Forwarder, command_buffer: u64) void {
        return forwarder_impl_command_tracking.clearCommandPassTarget(self, command_buffer);
    }

    pub fn addCommandPassEdge(self: *Forwarder, record: *TrackedCommandTargets, set: u64) void {
        return forwarder_impl_command_tracking.addCommandPassEdge(self, record, set);
    }

    /// Resolve every (target, set) edge the command recorded to (target,
    /// sampled image) pairs and hand them to the present chain. Runs at
    /// submission, after descriptor writes that legally follow recording.
    pub fn commitCommandPassSources(self: *Forwarder, command_buffer: u64) void {
        return forwarder_impl_command_tracking.commitCommandPassSources(self, command_buffer);
    }

    pub fn rejectDescriptorBind(
        self: *Forwarder,
        reason: DescriptorBindRejectReason,
        command_buffer: u64,
        layout: u64,
        set_count: u64,
        sets: u64,
        dynamic_count: u64,
        dynamic_offsets: u64,
        unmapped_handle: u64,
    ) void {
        return forwarder_impl_command_tracking.rejectDescriptorBind(self, reason, command_buffer, layout, set_count, sets, dynamic_count, dynamic_offsets, unmapped_handle);
    }

    pub fn noteCommandDescriptorSets(self: *Forwarder, state: anytype, command_buffer: u64, first_set: u64, guest_sets: u64, set_count: u64) void {
        return forwarder_impl_command_tracking.noteCommandDescriptorSets(self, state, command_buffer, first_set, guest_sets, set_count);
    }

    /// Resolve the descriptor sets named by a command only when the command
    /// reaches queue submission. Descriptor writes are legal between command
    /// recording and submission, and that is the interval in which the old
    /// bind-time snapshot lost the presenter's sampled image edge.
    pub fn resolveCommandDescriptorSets(self: *Forwarder, command_buffer: u64) void {
        return forwarder_impl_command_tracking.resolveCommandDescriptorSets(self, command_buffer);
    }

    pub fn noteCommandDescriptorImages(self: *Forwarder, state: anytype, command_buffer: u64, writes: []const abi.WriteDescriptorSet) void {
        return forwarder_impl_command_tracking.noteCommandDescriptorImages(self, state, command_buffer, writes);
    }

    pub fn mutableCommandTargets(self: *Forwarder, synthetic: u64) ?*TrackedCommandTargets {
        return forwarder_impl_command_tracking.mutableCommandTargets(self, synthetic);
    }

    pub fn resetCommandTargets(self: *Forwarder, synthetic: u64) void {
        return forwarder_impl_command_tracking.resetCommandTargets(self, synthetic);
    }

    pub fn addCommandImage(self: *Forwarder, command_buffer: u64, image: u64) void {
        return forwarder_impl_command_tracking.addCommandImage(self, command_buffer, image);
    }

    pub fn addCommandImageView(self: *Forwarder, command_buffer: u64, image_view: u64) void {
        return forwarder_impl_command_tracking.addCommandImageView(self, command_buffer, image_view);
    }

    pub fn addCommandTransfer(self: *Forwarder, command_buffer: u64, source: u64, destination: u64, kind: rosette_gpu.PresentTransferKind) void {
        return forwarder_impl_command_tracking.addCommandTransfer(self, command_buffer, source, destination, kind);
    }

    pub fn noteCommandTransfer(self: *Forwarder, command_buffer: u64, source: u64, destination: u64, kind: rosette_gpu.PresentTransferKind) void {
        return forwarder_impl_command_tracking.noteCommandTransfer(self, command_buffer, source, destination, kind);
    }

    pub fn noteCommandImageViewTransfer(
        self: *Forwarder,
        command_buffer: u64,
        source_view: u64,
        destination_view: u64,
        kind: rosette_gpu.PresentTransferKind,
    ) void {
        return forwarder_impl_command_tracking.noteCommandImageViewTransfer(self, command_buffer, source_view, destination_view, kind);
    }

    pub fn noteCommandImageTarget(self: *Forwarder, command_buffer: u64, synthetic_image: u64, write: WriteKind) void {
        return forwarder_impl_command_tracking.noteCommandImageTarget(self, command_buffer, synthetic_image, write);
    }

    pub fn trackImageView(self: *Forwarder, state: anytype, synthetic: u64, create_info: u64) void {
        return forwarder_impl_command_tracking.trackImageView(self, state, synthetic, create_info);
    }

    pub fn trackFramebuffer(self: *Forwarder, state: anytype, synthetic: u64, create_info: u64) void {
        return forwarder_impl_command_tracking.trackFramebuffer(self, state, synthetic, create_info);
    }

    /// Retain only the part of VkRenderPassCreateInfo that affects whether a
    /// command buffer writes an image at begin time. Xenia's presenter uses a
    /// color attachment with LOAD_OP_CLEAR, which is a real image write even
    /// when the command buffer contains no vkCmdClear* or vkCmdDraw call.
    pub fn trackRenderPass(self: *Forwarder, state: anytype, synthetic: u64, create_info: u64) void {
        return forwarder_impl_command_tracking.trackRenderPass(self, state, synthetic, create_info);
    }

    pub fn trackFramebufferTargets(self: *Forwarder, command_buffer: u64, framebuffer: u64) void {
        return forwarder_impl_command_tracking.trackFramebufferTargets(self, command_buffer, framebuffer);
    }

    pub fn trackRenderPassTransfers(self: *Forwarder, command_buffer: u64, render_pass: u64, framebuffer: u64) void {
        return forwarder_impl_command_tracking.trackRenderPassTransfers(self, command_buffer, render_pass, framebuffer);
    }

    pub fn noteCommandTargets(self: *Forwarder, command_buffer: u64, write: WriteKind) void {
        return forwarder_impl_command_tracking.noteCommandTargets(self, command_buffer, write);
    }

    pub fn noteLoadClearTarget(self: *Forwarder, command_buffer: u64, source: []const u8) void {
        return forwarder_impl_command_tracking.noteLoadClearTarget(self, command_buffer, source);
    }

    pub fn mergeCommandTargets(self: *Forwarder, destination: u64, source: u64) void {
        return forwarder_impl_command_tracking.mergeCommandTargets(self, destination, source);
    }

    pub fn noteFsiSubmittedCommandBuffer(self: *Forwarder, command_buffer: u64, queue_submit_ordinal: u64, batch_index: u32) void {
        return forwarder_impl_command_tracking.noteFsiSubmittedCommandBuffer(self, command_buffer, queue_submit_ordinal, batch_index);
    }

    /// Commit the command buffer's retained target set at submission time.
    /// Recording can happen before the swapchain acquire, so doing this at the
    /// command call would either miss the frame or attribute it to the wrong
    /// acquired image.
    pub fn noteSubmittedCommandTargets(self: *Forwarder, command_buffer: u64) void {
        return forwarder_impl_command_tracking.noteSubmittedCommandTargets(self, command_buffer);
    }

    pub fn noteGuestImageTarget(self: *Forwarder, synthetic_image: u64, write_kind: WriteKind) void {
        return forwarder_impl_command_tracking.noteGuestImageTarget(self, synthetic_image, write_kind);
    }

    pub fn forgetImageView(self: *Forwarder, synthetic: u64) void {
        return forwarder_impl_command_tracking.forgetImageView(self, synthetic);
    }

    pub fn forgetDescriptorSet(self: *Forwarder, synthetic: u64) void {
        return forwarder_impl_command_tracking.forgetDescriptorSet(self, synthetic);
    }

    pub fn forgetRenderPass(self: *Forwarder, synthetic: u64) void {
        return forwarder_impl_command_tracking.forgetRenderPass(self, synthetic);
    }

    pub fn forgetFramebuffer(self: *Forwarder, synthetic: u64) void {
        return forwarder_impl_command_tracking.forgetFramebuffer(self, synthetic);
    }

    /// The ledger row for one entry point, created on first use.
    pub fn createLedgerEntry(self: *Forwarder, name: []const u8) ?*VulkanCreateLedgerEntry {
        return forwarder_impl_fsi_submission.createLedgerEntry(self, name);
    }

    pub fn noteCreateAttempt(self: *Forwarder, name: []const u8) void {
        return forwarder_impl_fsi_submission.noteCreateAttempt(self, name);
    }

    pub fn noteCreatePublished(self: *Forwarder, name: []const u8) void {
        return forwarder_impl_fsi_submission.noteCreatePublished(self, name);
    }

    pub fn noteCreateRefusedBeforeDriver(self: *Forwarder, name: []const u8) void {
        return forwarder_impl_fsi_submission.noteCreateRefusedBeforeDriver(self, name);
    }

    pub fn noteCreateDriverFailure(self: *Forwarder, name: []const u8, result: i32) void {
        return forwarder_impl_fsi_submission.noteCreateDriverFailure(self, name, result);
    }

    pub fn vulkanCreateLedgerHasAnomaly(self: *const Forwarder) bool {
        return forwarder_impl_fsi_submission.vulkanCreateLedgerHasAnomaly(self);
    }

    /// Print the distinct Vulkan create entry points and their outcomes. This
    /// is intentionally separate from the larger state snapshot so a create
    /// anomaly can be made visible even when the presentation chain itself is
    /// healthy. The row order is first-seen order, which is the order that
    /// makes a partially initialized pipeline easiest to reconcile with the
    /// guest call trace.
    pub fn dumpVulkanCreateLedger(self: *const Forwarder) void {
        return forwarder_impl_fsi_submission.dumpVulkanCreateLedger(self);
    }

    pub fn createVulkanObject(self: *Forwarder, state: anytype, create_info: u64, output: u64, name: []const u8) u64 {
        return forwarder_impl_fsi_submission.createVulkanObject(self, state, create_info, output, name);
    }

    pub fn realVulkanObjectMapped(self: *const Forwarder, synthetic_handle: u64, name: []const u8) bool {
        return forwarder_impl_fsi_submission.realVulkanObjectMapped(self, synthetic_handle, name);
    }

    /// Map a synthetic handle to the real driver object behind it.
    ///
    /// Reached through a function pointer so the marshaller needs no knowledge
    /// of this type. A miss is null rather than zero: `VK_NULL_HANDLE` is
    /// meaningful in some fields and catastrophic in others, so "I do not know
    /// this object" must not be spelled the same way as "there is no object".
    pub fn resolveRealHandle(context: *anyopaque, kind: marshal.HandleKind, synthetic: u64) ?u64 {
        return forwarder_impl_fsi_submission.resolveRealHandle(context, kind, synthetic);
    }

    /// Bridges the marshaller's plain callback to whatever concrete state type
    /// the forwarder was instantiated with.
    pub fn MarshalReader(comptime State: type) type {
        return forwarder_impl_fsi_submission.MarshalReader(State);
    }

    /// Produce a host-ready create-info, or nothing.
    ///
    /// "Nothing" is the safe answer and the common one: a structure with no
    /// plan, an unresolvable handle or an array that will not fit is left to
    /// the modelled path rather than handed to a driver with guest pointers
    /// still in it. That refusal is the property that keeps an undescribed
    /// structure from being able to crash the process.
    pub fn marshalCreateInfo(
        self: *Forwarder,
        state: anytype,
        create_info: u64,
        name: []const u8,
    ) ?[]u8 {
        return forwarder_impl_fsi_submission.marshalCreateInfo(self, state, create_info, name);
    }

    pub fn marshalSemaphoreCreateInfo(self: *Forwarder, state: anytype, create_info: u64) ?[]u8 {
        return forwarder_impl_fsi_submission.marshalSemaphoreCreateInfo(self, state, create_info);
    }

    pub fn marshalImageCreateInfo(self: *Forwarder, state: anytype, create_info: u64) ?[]u8 {
        return forwarder_impl_fsi_submission.marshalImageCreateInfo(self, state, create_info);
    }

    pub fn createRealVulkanObject(self: *Forwarder, state: anytype, synthetic_handle: u64, create_info: u64, name: []const u8) !void {
        return forwarder_impl_fsi_submission.createRealVulkanObject(self, state, synthetic_handle, create_info, name);
    }

    pub fn trackedResourceCount(self: *const Forwarder) usize {
        return forwarder_impl_fsi_submission.trackedResourceCount(self);
    }

    pub fn freeResourceSlotCount(self: *const Forwarder) usize {
        return forwarder_impl_fsi_submission.freeResourceSlotCount(self);
    }

    pub fn noteResourceRecordCommitted(self: *Forwarder, was_empty: bool) void {
        return forwarder_impl_fsi_submission.noteResourceRecordCommitted(self, was_empty);
    }

    pub fn releaseResource(self: *Forwarder, handle: u64) bool {
        return forwarder_impl_fsi_submission.releaseResource(self, handle);
    }

    pub fn trackedImageCount(self: *const Forwarder) u64 {
        return forwarder_impl_fsi_submission.trackedImageCount(self);
    }

    pub fn resourceSlot(self: *Forwarder, handle: u64) ?*VulkanResource {
        return forwarder_impl_fsi_submission.resourceSlot(self, handle);
    }

    pub fn resourceSlotAvailable(self: *const Forwarder) bool {
        return forwarder_impl_fsi_submission.resourceSlotAvailable(self);
    }

    pub fn findResource(self: *Forwarder, handle: u64) ?*VulkanResource {
        return forwarder_impl_fsi_submission.findResource(self, handle);
    }

    pub fn recordImage(self: *Forwarder, state: anytype, handle: u64, create_info: u64) bool {
        return forwarder_impl_fsi_submission.recordImage(self, state, handle, create_info);
    }

    pub fn recordBuffer(self: *Forwarder, state: anytype, handle: u64, create_info: u64) bool {
        return forwarder_impl_fsi_submission.recordBuffer(self, state, handle, create_info);
    }

    pub fn bindResourceMemory(self: *Forwarder, resource: u64, memory: u64, offset: u64, kind: VulkanResourceKind) u64 {
        return forwarder_impl_fsi_submission.bindResourceMemory(self, resource, memory, offset, kind);
    }

    /// Vulkan 1.1 groups resource bindings into an array. Keep the operation
    /// in Rosette's resource model and only decode the public Vulkan ABI at
    /// this edge; the resource records below remain backend-independent.
    pub fn bindResourcesMemory2(
        self: *Forwarder,
        state: anytype,
        count: u64,
        infos: u64,
        kind: VulkanResourceKind,
    ) u64 {
        return forwarder_impl_fsi_submission.bindResourcesMemory2(self, state, count, infos, kind);
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
    pub fn writeExactMemoryRequirements(
        self: *Forwarder,
        state: anytype,
        output: u64,
        reqs: abi.MemoryRequirements,
    ) u64 {
        return forwarder_impl_fsi_submission.writeExactMemoryRequirements(self, state, output, reqs);
    }

    /// Requirements for a resource the real device does not know about.
    ///
    /// The synthetic `memoryTypeBits` must still be intersected against the
    /// device's real memory types by the caller, so advertising only bit zero
    /// asserts that exactly one specific memory type is usable — a claim this
    /// layer is in no position to make. Every type the device actually reports
    /// is the honest answer: it constrains nothing and lets the caller apply
    /// its own preference.
    pub fn writeSyntheticMemoryRequirements(self: *Forwarder, state: anytype, output: u64, size: u64) u64 {
        return forwarder_impl_fsi_submission.writeSyntheticMemoryRequirements(self, state, output, size);
    }

    pub fn writeResourceMemoryRequirements(self: *Forwarder, state: anytype, resource: u64, output: u64) u64 {
        return forwarder_impl_fsi_submission.writeResourceMemoryRequirements(self, state, resource, output);
    }

    /// Vulkan 1.1 wraps both the resource and the result in extensible
    /// structures. The payload is still the same Rosette memory requirement;
    /// preserve the caller-owned sType/pNext headers and write only the nested
    /// VkMemoryRequirements at offset 16.
    pub fn writeResourceMemoryRequirements2(self: *Forwarder, state: anytype, info: u64, output: u64) u64 {
        return forwarder_impl_fsi_submission.writeResourceMemoryRequirements2(self, state, info, output);
    }

    pub fn writeDeviceBufferMemoryRequirements(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.writeDeviceBufferMemoryRequirements(self, state);
    }

    pub fn writeDeviceImageMemoryRequirements(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.writeDeviceImageMemoryRequirements(self, state);
    }

    pub fn createLogicalDevice(self: *Forwarder, state: anytype, output: u64) u64 {
        return forwarder_impl_fsi_submission.createLogicalDevice(self, state, output);
    }

    // ---- Vulkan call trace helpers ----

    pub fn recordVulkanCall(self: *Forwarder, __forwarder_anon_arg_1: anytype, name: []const u8, result: i32, arg0: u64, arg1: u64) void {
        return forwarder_impl_fsi_submission.recordVulkanCall(self, __forwarder_anon_arg_1, name, result, arg0, arg1);
    }

    /// Dump the Vulkan call trace ring buffer to the runtime log.
    pub fn dumpVulkanCallTrace(self: *Forwarder) void {
        return forwarder_impl_fsi_submission.dumpVulkanCallTrace(self);
    }

    /// Dump a snapshot of the Vulkan forwarding state to the runtime log.
    pub fn dumpVulkanStateSnapshot(self: *Forwarder) void {
        return forwarder_impl_fsi_submission.dumpVulkanStateSnapshot(self);
    }

    pub fn writeDeviceQueue(self: *Forwarder, state: anytype, output: u64, name: []const u8) u64 {
        return forwarder_impl_fsi_submission.writeDeviceQueue(self, state, output, name);
    }

    pub fn getSemaphoreCounterValue(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.getSemaphoreCounterValue(self, state);
    }

    pub fn waitSemaphores(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.waitSemaphores(self, state);
    }

    pub fn signalSemaphore(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.signalSemaphore(self, state);
    }

    pub fn writeRealSurfaceCapabilities(self: *Forwarder, state: anytype, output: u64) u64 {
        return forwarder_impl_fsi_submission.writeRealSurfaceCapabilities(self, state, output);
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
    pub fn boundSurfaceEnumeration(self: *Forwarder, driver_count: u32, kind: []const u8) u32 {
        return forwarder_impl_fsi_submission.boundSurfaceEnumeration(self, driver_count, kind);
    }

    pub fn enumerateRealSurfaceFormats(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.enumerateRealSurfaceFormats(self, state);
    }

    pub fn enumerateRealSurfacePresentModes(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.enumerateRealSurfacePresentModes(self, state);
    }

    pub fn writeRealSurfaceSupport(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.writeRealSurfaceSupport(self, state);
    }

    pub fn beginCommandBuffer(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.beginCommandBuffer(self, state);
    }

    pub fn endCommandBuffer(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.endCommandBuffer(self, state);
    }

    pub fn resetCommandBuffer(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.resetCommandBuffer(self, state);
    }

    pub fn resetCommandPool(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.resetCommandPool(self, state);
    }

    pub fn resetDescriptorPool(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_fsi_submission.resetDescriptorPool(self, state);
    }

    pub fn waitForFences(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.waitForFences(self, state);
    }

    pub fn resetFences(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.resetFences(self, state);
    }

    pub fn getFenceStatus(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.getFenceStatus(self, state);
    }

    pub fn getQueryPoolResults(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.getQueryPoolResults(self, state);
    }

    pub fn resetQueryPool(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.resetQueryPool(self, state);
    }

    const QueueApiWait = struct {
        gate: *queue_api_gate.Gate,
        lease: ?queue_api_gate.Gate.Lease = null,

        pub fn acquire(context: *@This()) void {
            context.lease = context.gate.waitAcquire();
        }
    };

    pub fn lockVulkanQueueApi(self: *Forwarder, state: anytype) ?queue_api_gate.Gate.Lease {
        return forwarder_impl_render_resources.lockVulkanQueueApi(self, state);
    }

    pub fn deviceWaitIdle(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.deviceWaitIdle(self, state);
    }

    pub fn queueWaitIdle(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.queueWaitIdle(self, state);
    }

    pub fn copyMappedBytes(self: *Forwarder, state: anytype, memory: u64, offset: u64, requested_size: u64, to_host: bool) bool {
        return forwarder_impl_render_resources.copyMappedBytes(self, state, memory, offset, requested_size, to_host);
    }

    pub fn publishCoherentShadow(self: *Forwarder, state: anytype, record: *VulkanMemoryAllocation) bool {
        return forwarder_impl_render_resources.publishCoherentShadow(self, state, record);
    }

    pub fn downloadCoherentShadowsAfterCompletion(self: *Forwarder, state: anytype) void {
        return forwarder_impl_render_resources.downloadCoherentShadowsAfterCompletion(self, state);
    }

    /// Guest mappings are Rosette-owned shadow windows, not the pointer the
    /// native driver returned.  Coherent Vulkan memory therefore still needs
    /// an explicit shadow-to-host copy before a queue submission; relying on
    /// `vkFlushMappedMemoryRanges` alone loses titles that correctly omit a
    /// flush for HOST_COHERENT allocations.
    pub fn uploadMappedMemoryBeforeSubmit(self: *Forwarder, state: anytype) bool {
        return forwarder_impl_render_resources.uploadMappedMemoryBeforeSubmit(self, state);
    }

    /// GFXReconstruct's assisted tracking records mapped memory only at
    /// vkFlushMappedMemoryRanges. Xenia maps coherent memory and never flushes
    /// it, and neither Rosette's shadow publication nor a natively aliased
    /// mapping the guest writes directly is visible to the layer, so while a
    /// capture is armed every live mapping is flushed before each submit. On
    /// Apple's unified memory a coherent flush costs the driver nothing.
    pub fn flushMappingsForCapture(self: *Forwarder) void {
        return forwarder_impl_render_resources.flushMappingsForCapture(self);
    }

    pub fn recordCaptureFlush(result: anytype) void {
        return forwarder_impl_render_resources.recordCaptureFlush(result);
    }

    pub fn flushMappedMemoryRanges(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.flushMappedMemoryRanges(self, state);
    }

    pub fn invalidateMappedMemoryRanges(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.invalidateMappedMemoryRanges(self, state);
    }

    pub fn unmapMemory(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_render_resources.unmapMemory(self, state);
    }

    pub fn ensureNativeVulkanInstance(self: *Forwarder, library_token: u64) i32 {
        return forwarder_impl_render_resources.ensureNativeVulkanInstance(self, library_token);
    }

    pub fn createNativeMetalSurface(self: *Forwarder, state: anytype, library_token: u64) NativeSurfaceResult {
        return forwarder_impl_render_resources.createNativeMetalSurface(self, state, library_token);
    }

    pub fn destroyNativeSurface(self: *Forwarder) void {
        return forwarder_impl_render_resources.destroyNativeSurface(self);
    }

    // -----------------------------------------------------------------------
    // Phase 1: Real Vulkan object creation
    // -----------------------------------------------------------------------

    /// Materialise the Vulkan library handle for the guest. This is the same
    /// dlopen the native presenter uses; both share one host library.
    pub fn materializeVulkanLibraryForReal(self: *Forwarder, library_token: u64) ?*anyopaque {
        return forwarder_impl_render_resources.materializeVulkanLibraryForReal(self, library_token);
    }

    pub fn queryHostInstanceExtensions(self: *Forwarder, library: *anyopaque) bool {
        return forwarder_impl_render_resources.queryHostInstanceExtensions(self, library);
    }

    pub fn hostInstanceExtensionAvailable(self: *const Forwarder, name: []const u8) bool {
        return forwarder_impl_render_resources.hostInstanceExtensionAvailable(self, name);
    }

    /// Guest instance extensions may describe the platform they were built
    /// for rather than the native surface API available to Rosette.  Keep
    /// those translations in a table-shaped helper so an extension is either
    /// advertised and negotiated coherently, or absent from both sides of the
    /// contract.  This is deliberately separate from hostInstanceExtensionAvailable:
    /// the latter must continue to report the loader's actual capabilities.
    pub fn guestInstanceExtensionAlias(name: []const u8) ?[]const u8 {
        return forwarder_impl_render_resources.guestInstanceExtensionAlias(name);
    }

    pub fn guestInstanceExtensionAvailable(self: *const Forwarder, name: []const u8) bool {
        return forwarder_impl_render_resources.guestInstanceExtensionAvailable(self, name);
    }

    /// Cache the selected physical device's extension list.  This is the one
    /// answer both the guest enumeration and our own vkCreateDevice
    /// negotiation need, and querying it once keeps those two views of the
    /// adapter from disagreeing.
    pub fn queryHostDeviceExtensions(self: *Forwarder) bool {
        return forwarder_impl_render_resources.queryHostDeviceExtensions(self);
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
    pub fn negotiateBridgeCapabilities(self: *Forwarder, scratch: *BridgeCapabilityScratch) void {
        return forwarder_impl_render_resources.negotiateBridgeCapabilities(self, scratch);
    }

    pub fn hostDeviceExtensions(self: *const Forwarder) []const abi.ExtensionProperties {
        return forwarder_impl_render_resources.hostDeviceExtensions(self);
    }

    pub fn hostDeviceExtensionAvailable(self: *const Forwarder, name: []const u8) bool {
        return forwarder_impl_render_resources.hostDeviceExtensionAvailable(self, name);
    }

    pub fn enumerateInstanceExtensions(self: *Forwarder, state: anytype, library_token: u64) u64 {
        return forwarder_impl_render_resources.enumerateInstanceExtensions(self, state, library_token);
    }

    /// Ensure a real VkInstance exists for the guest's rendering pipeline.
    /// Called the first time the guest invokes vkCreateInstance. The instance
    /// is created with the extensions the guest requested plus any we need
    /// internally.
    /// Name the driver that will render every guest frame. The adapter name
    /// is the GPU's for every Metal-backed driver, and which driver the loader
    /// picks depends on the launching shell (VULKAN_SDK, VK_ICD_FILENAMES,
    /// VK_DRIVER_FILES), so without this line two runs could differ silently.
    pub fn logRealDriverIdentity(self: *Forwarder, instance: abi.Instance, physical_device: abi.PhysicalDevice) void {
        return forwarder_impl_render_resources.logRealDriverIdentity(self, instance, physical_device);
    }

    pub fn ensureRealInstance(self: *Forwarder, state: anytype, library_token: u64, create_info: u64) i32 {
        return forwarder_impl_render_resources.ensureRealInstance(self, state, library_token, create_info);
    }

    /// Ensure a real VkDevice exists for the guest's rendering pipeline.
    /// Called the first time the guest invokes vkCreateDevice. Creates a real
    /// device on the physical device selected by ensureRealInstance, with the
    /// queue families the guest requested.
    pub fn ensureRealDevice(self: *Forwarder, state: anytype, library_token: u64, __forwarder_anon_arg_3: u64, device_create_info_addr: u64, output: u64) i32 {
        return forwarder_impl_render_resources.ensureRealDevice(self, state, library_token, __forwarder_anon_arg_3, device_create_info_addr, output);
    }

    /// Resolve all device-level function pointers from the real device.
    pub fn ensureRealDeviceFnPtrs(self: *Forwarder, __forwarder_anon_arg_1: u64) void {
        return forwarder_impl_render_resources.ensureRealDeviceFnPtrs(self, __forwarder_anon_arg_1);
    }

    /// Refuse one Vulkan call before the native driver sees it, and say why.
    ///
    /// This is the only way a refusal should be spelled. A bare
    /// `return vkErrorInitializationFailed()` tells a reader that something
    /// went wrong at some unspecified point in a 200-line translation
    /// function, which is how a legal fence-only submission was refused
    /// thousands of times without anybody being able to see which check had
    /// rejected it.
    pub fn refuseVulkanCall(
        self: *Forwarder,
        entry_point: []const u8,
        why: []const u8,
        result: abi.Result,
        args: [3]u64,
    ) u64 {
        return forwarder_impl_render_resources.refuseVulkanCall(self, entry_point, why, result, args);
    }

    /// Read the host window's on-screen chain, if the AppKit bridge is linked
    /// into this binary.
    ///
    /// Resolved through `dlsym` rather than declared `extern` so a test build
    /// that does not link the Objective-C bridge still compiles and simply
    /// reports the window facts as unavailable.
    pub fn describeHostWindow() ?rosette_gpu.WindowGeometry {
        return forwarder_impl_render_resources.describeHostWindow();
    }

    /// Convert a floating-point AppKit dimension into the integer pixel
    /// dimension used by the Vulkan swapchain contract.  The geometry bridge
    /// is deliberately allowed to expose fractional points, but a zero or
    /// negative value must remain zero rather than wrapping into a huge
    /// unsigned extent in the screen-validity report.
    pub fn screenExtentDimension(value: f64) u32 {
        return forwarder_impl_render_resources.screenExtentDimension(value);
    }

    pub fn screenValidityPixelEvidence(evidence: rosette_gpu.PresentPixelEvidence) rosette_gpu.ScreenValidityPixelEvidence {
        return forwarder_impl_render_resources.screenValidityPixelEvidence(evidence);
    }

    pub fn screenValiditySnapshot(
        self: *const Forwarder,
        window: ?rosette_gpu.WindowGeometry,
    ) rosette_gpu.ScreenValiditySnapshot {
        return forwarder_impl_render_resources.screenValiditySnapshot(self, window);
    }

    pub fn observeScreenValidity(
        self: *Forwarder,
        window: ?rosette_gpu.WindowGeometry,
    ) rosette_gpu.ScreenValidityEvaluation {
        return forwarder_impl_render_resources.observeScreenValidity(self, window);
    }

    /// Print the final-mile contract separately from PRESENT CHAIN.  It is
    /// intentionally verbose only on a state change or a full report, while
    /// the compact header still says exactly which stage is actionable.
    pub fn printScreenValidity(self: *const Forwarder) void {
        return forwarder_impl_graphics_observation.printScreenValidity(self);
    }

    pub fn hostWindowFactsUnavailableReason() []const u8 {
        return forwarder_impl_graphics_observation.hostWindowFactsUnavailableReason();
    }

    /// The whole presentation chain: the host window as AppKit sees it, the
    /// Vulkan topology built on it, and the first link that cannot carry a
    /// frame.
    ///
    /// State transitions get a full inventory; counters and pixel identities
    /// get a wall-clock-bounded progress report. `full` always forces the
    /// complete terminal snapshot. Neither policy changes guest execution.
    pub fn presentChainVerdict(self: *const Forwarder) rosette_gpu.PresentChainVerdict {
        return forwarder_impl_graphics_observation.presentChainVerdict(self);
    }

    pub fn noteGuestExecutionProgress(
        self: *Forwarder,
        steps: u64,
        rip: u64,
        thread: u64,
        operation: []const u8,
        frontier_is_bounded: bool,
    ) void {
        return forwarder_impl_graphics_observation.noteGuestExecutionProgress(self, steps, rip, thread, operation, frontier_is_bounded);
    }

    /// Return only guest-owned frame evidence. Rosette's diagnostic presenter
    /// may have retired swapchains in the same layer history; those must never
    /// satisfy the guest frame contract.
    pub fn guestFrameEvidence(self: *const Forwarder) GuestFrameEvidence {
        return forwarder_impl_graphics_observation.guestFrameEvidence(self);
    }

    pub fn reportPresentChain(self: *Forwarder, full: bool) void {
        return forwarder_impl_graphics_observation.reportPresentChain(self, full);
    }

    /// Pure report admission, separately testable without AppKit or Xenia.
    pub fn chooseGraphicsReport(self: *Forwarder, now: u64, verdict: rosette_gpu.PresentChainVerdict, full: bool) transport_timing.ReportKind {
        return forwarder_impl_graphics_observation.chooseGraphicsReport(self, now, verdict, full);
    }

    pub fn configureGraphicsReports(self: *Forwarder) void {
        return forwarder_impl_graphics_observation.configureGraphicsReports(self);
    }

    /// First occurrence of each anomaly class gets an immediate full report;
    /// repeated counts ride progress/final reports. The refusal/native-error
    /// sites still print the actual new reason when it happens.
    pub fn graphicsReportAnomalyMask(self: *const Forwarder) u64 {
        return forwarder_impl_graphics_observation.graphicsReportAnomalyMask(self);
    }

    pub fn guestPresentMode(self: *const Forwarder) ?u32 {
        return forwarder_impl_graphics_observation.guestPresentMode(self);
    }

    pub fn provenanceGapLabel(self: *const Forwarder) []const u8 {
        return forwarder_impl_graphics_observation.provenanceGapLabel(self);
    }

    pub fn printGraphicsProgress(self: *const Forwarder, now: u64, verdict: rosette_gpu.PresentChainVerdict) void {
        return forwarder_impl_graphics_observation.printGraphicsProgress(self, now, verdict);
    }

    pub fn printGraphicsPacing(self: *const Forwarder, now: u64) void {
        return forwarder_impl_graphics_observation.printGraphicsPacing(self, now);
    }

    pub fn printTransportCosts(self: *const Forwarder) void {
        return forwarder_impl_graphics_observation.printTransportCosts(self);
    }

    pub fn printFrameRates(self: *const Forwarder, now: u64) void {
        return forwarder_impl_graphics_observation.printFrameRates(self, now);
    }

    /// Escalate the first no-present observation into a useful failure
    /// capture. The chain remains live so a startup no_presents can resolve
    /// when Xenia reaches its first frame; resolution is logged explicitly.
    /// Repeated observations are reduced to sparse counter lines.
    pub fn notePresentChainVerdict(self: *Forwarder, verdict: rosette_gpu.PresentChainVerdict) void {
        return forwarder_impl_graphics_observation.notePresentChainVerdict(self, verdict);
    }

    /// Re-read the host window and say so if its state changed.
    ///
    /// Deliberately not on the per-present path: reading AppKit dispatches to
    /// the main thread, so doing it per frame would cost more than the frame.
    /// This rides the periodic loader-summary cadence instead, which is rare
    /// and already exists. A window that becomes hidden, miniaturised or
    /// occluded halfway through a run is otherwise invisible -- presents keep
    /// succeeding and nothing else notices.
    pub fn refreshPresentChainWindow(self: *Forwarder) void {
        return forwarder_impl_graphics_observation.refreshPresentChainWindow(self);
    }

    /// The end-of-run report, which observes a finished run and must not
    /// change it.
    pub fn printPresentChain(self: *Forwarder) void {
        return forwarder_impl_graphics_observation.printPresentChain(self);
    }

    pub fn printPresentChainBody(self: *const Forwarder, verdict: rosette_gpu.PresentChainVerdict) void {
        return forwarder_impl_graphics_observation.printPresentChainBody(self, verdict);
    }

    /// Say once when the guest is waiting on a fence nothing will signal.
    ///
    /// Cheap enough for the poll path: a bounded scan of at most sixteen
    /// entries, and each fence reports at most once.
    pub fn reportStarvedFence(self: *Forwarder) void {
        return forwarder_impl_graphics_observation.reportStarvedFence(self);
    }

    /// Report the Vulkan calls this run refused.
    ///
    /// Silent while nothing has been refused, and silent again once every
    /// refusal has been described. `full` asks for the complete set; without
    /// it only what is new since the last report is printed, so a run that
    /// refuses the same call every frame says it once.
    pub fn reportVulkanRefusals(self: *Forwarder, full: bool) void {
        return forwarder_impl_graphics_observation.reportVulkanRefusals(self, full);
    }

    /// The printing half, usable from the end-of-run summary, which observes
    /// a finished run and must not change it.
    pub fn printVulkanRefusals(self: *const Forwarder, full: bool) void {
        return forwarder_impl_graphics_observation.printVulkanRefusals(self, full);
    }

    /// Settle the device's absent entry points: which the guest reached, what
    /// served each one, and how many were never asked for at all.
    ///
    /// Emitted once at the end of a run. The resolution-time line says four
    /// entry points are missing and leaves the reader to work out whether
    /// that matters; this says which of them the guest actually touched.
    pub fn reportVulkanAbsentEntryPoints(self: *const Forwarder) void {
        return forwarder_impl_graphics_observation.reportVulkanAbsentEntryPoints(self);
    }

    pub fn noteRealVulkanResult(self: *Forwarder, result: abi.Result, operation: []const u8) void {
        return forwarder_impl_graphics_observation.noteRealVulkanResult(self, result, operation);
    }

    pub fn printDeviceLossFsiSubmission(self: *Forwarder, label: []const u8, submission: fsi_diagnostics.SubmissionEvidence) void {
        return forwarder_impl_graphics_observation.printDeviceLossFsiSubmission(self, label, submission);
    }

    pub fn realDeviceLostResult(self: *const Forwarder) ?u64 {
        return forwarder_impl_graphics_observation.realDeviceLostResult(self);
    }

    pub fn noteNativeFenceComplete(self: *Forwarder, state: anytype, synthetic_fence: u64) void {
        return forwarder_impl_graphics_observation.noteNativeFenceComplete(self, state, synthetic_fence);
    }

    pub fn clearRealVulkanObjectMaps(self: *Forwarder) void {
        return forwarder_impl_graphics_observation.clearRealVulkanObjectMaps(self);
    }

    pub fn releaseNativeMemoryAliases(self: *Forwarder, state: anytype) void {
        return forwarder_impl_graphics_observation.releaseNativeMemoryAliases(self, state);
    }

    /// Destroy the guest's real Vulkan device and all its children.
    pub fn destroyRealDevice(self: *Forwarder) void {
        return forwarder_impl_graphics_observation.destroyRealDevice(self);
    }

    pub fn destroyRealSwapchain(self: *Forwarder, synthetic: u64) void {
        return forwarder_impl_graphics_observation.destroyRealSwapchain(self, synthetic);
    }

    pub fn forgetSwapchainResourceImages(self: *Forwarder, record: *const SwapchainRecord) void {
        return forwarder_impl_graphics_observation.forgetSwapchainResourceImages(self, record);
    }

    pub fn destroyRealSurface(self: *Forwarder) void {
        return forwarder_impl_graphics_observation.destroyRealSurface(self);
    }

    /// Destroy the guest's real Vulkan instance.
    pub fn destroyRealInstance(self: *Forwarder) void {
        return forwarder_impl_graphics_observation.destroyRealInstance(self);
    }

    pub fn printNativeTextureReport(self: *const Forwarder) void {
        return forwarder_impl_graphics_observation.printNativeTextureReport(self);
    }

    pub fn shutdownNativeTextures(self: *Forwarder, destroy_native: bool) void {
        return forwarder_impl_graphics_observation.shutdownNativeTextures(self, destroy_native);
    }

    pub fn destroyNativeVulkanObjects(self: *Forwarder) void {
        return forwarder_impl_graphics_observation.destroyNativeVulkanObjects(self);
    }

    /// Hands the presenter the host loader without teaching the GPU library
    /// anything about `dlopen`: resolving symbols is dyld's job, and this is
    /// dyld.
    pub fn resolveNativeVulkanSymbol(context: ?*anyopaque, name: [*:0]const u8) callconv(.c) ?*anyopaque {
        return forwarder_impl_graphics_observation.resolveNativeVulkanSymbol(context, name);
    }

    pub fn nativeVulkanLoaderPath(self: *const Forwarder) []const u8 {
        return forwarder_impl_graphics_observation.nativeVulkanLoaderPath(self);
    }

    pub fn noteNativeVulkanLoaderResolved(self: *Forwarder, path: []const u8) void {
        return forwarder_impl_graphics_observation.noteNativeVulkanLoaderResolved(self, path);
    }

    /// Bring Rosette's own native presenter up against the window's
    /// `CAMetalLayer`. Independent of the guest's Vulkan objects: the guest's
    /// device and swapchain stay modelled, while this owns a real device, a
    /// real swapchain and real images, so something other than a host clear can
    /// reach the display.
    pub fn currentHostDrawableExtent() abi.Extent2D {
        return forwarder_impl_graphics_observation.currentHostDrawableExtent();
    }

    /// Record and escalate an extent failure at the first boundary that can
    /// still prevent a bad swapchain from becoming live. The generic state
    /// hook keeps this forwarder usable by the ELF/test state, while
    /// MachOState implements the non-bypassable process termination and crash
    /// evidence path. No caller is allowed to downgrade this to a retry:
    /// retrying would merely re-enter the same layer geometry disagreement.
    pub fn noteGraphicsExtentContractFailure(
        self: *Forwarder,
        state: anytype,
        requested_width: u32,
        requested_height: u32,
        observed_width: u32,
        observed_height: u32,
        reason: []const u8,
    ) void {
        return forwarder_impl_graphics_observation.noteGraphicsExtentContractFailure(self, state, requested_width, requested_height, observed_width, observed_height, reason);
    }

    pub fn bringUpNativePresenter(self: *Forwarder, state: anytype, library_token: u64) rosette_gpu.NativePresenterStage {
        return forwarder_impl_graphics_observation.bringUpNativePresenter(self, state, library_token);
    }

    /// Prepare the drawable before Vulkan queries the surface and creates its
    /// swapchain. The bridge owns the property during this call; the driver
    /// takes ownership only after a successful create.
    pub fn prepareMetalDrawableForSwapchain(self: *Forwarder, state: anytype, width: u32, height: u32) bool {
        return forwarder_impl_present_routing.prepareMetalDrawableForSwapchain(self, state, width, height);
    }

    /// Stop writing the `CAMetalLayer`'s `drawableSize` now that a Vulkan
    /// swapchain vends its drawables.
    ///
    /// The window bridge sizes the layer from the view on every event pump,
    /// and the guest's message loop pumps once per `GetMessage`. MoltenVK
    /// sets `drawableSize` from the swapchain's `imageExtent` at create time
    /// and watches the property afterwards, so the bridge was overwriting it
    /// on every pump with a different number - the 2026-09-11 run held
    /// `drawable=2560x1440` against a 1280x720 swapchain for its whole
    /// length. Neither side is wrong about what it wants; only one of them
    /// owns the property.
    pub fn yieldMetalDrawableToSwapchain(self: *Forwarder, state: anytype, width: u32, height: u32) void {
        return forwarder_impl_present_routing.yieldMetalDrawableToSwapchain(self, state, width, height);
    }

    /// Stand Rosette's own presenter down once the guest owns the layer.
    ///
    /// The native presenter exists so something can reach the display before
    /// the guest's Vulkan objects do. It builds a real swapchain against the
    /// window's `CAMetalLayer`, and nothing used to take it back down. On the
    /// 2026-09-12 run that left a 2560x1440 Rosette swapchain and a 1280x720
    /// guest swapchain live on layer 0x13a042920 at the same time, which the
    /// chain reported as `contested_layer` and the geometry check reported as
    /// a drawable that disagreed with the swapchain that was actually
    /// presenting. A `CAMetalLayer` vends one drawable pool; two swapchains
    /// take turns from it.
    ///
    /// Rosette's presenter had presented nothing in that run
    /// (`native_present_requests=0`), so standing it down costs no frame. Its
    /// fallback paths are all guarded on `stage.isReady()` and simply stop
    /// running once it is down, which is the correct behaviour when the guest
    /// is presenting for itself.
    pub fn retireNativePresenterForGuestSwapchain(self: *Forwarder, guest_width: u32, guest_height: u32) void {
        return forwarder_impl_present_routing.retireNativePresenterForGuestSwapchain(self, guest_width, guest_height);
    }

    /// Put Rosette's own presenter into the topology it reports on.
    ///
    /// The chain has a `contested_layer` verdict for two live swapchains on
    /// one `CAMetalLayer` - a layer vends one drawable pool, and two
    /// swapchains take turns from it. It could never fire, because only the
    /// guest's objects were ever registered. On the 2026-09-12 run Rosette's
    /// presenter held a 2560x1440 swapchain on layer 0x12d824480 and the
    /// guest then built a 1280x720 one on the same layer, and the chain
    /// reported a single swapchain and a verdict of healthy.
    ///
    /// Registering Rosette's own objects is what lets Rosette be the
    /// suspect. A diagnostic that can only accuse the other side is not a
    /// diagnostic.
    pub fn registerNativePresenterInPresentChain(self: *Forwarder, _state: anytype) void {
        return forwarder_impl_present_routing.registerNativePresenterInPresentChain(self, _state);
    }

    /// Run the host half of the presentation path before guest execution.
    ///
    /// This deliberately does not use a guest library token and does not
    /// present a clear. It loads a host Vulkan loader, binds the already
    /// attached CAMetalLayer, and asks the real presenter to create its
    /// instance, surface, device, queue, frame resources and swapchain. A
    /// successful result proves that the window can be admitted; it does not
    /// pretend that a guest frame has been produced.
    pub fn preflightNativePresenter(self: *Forwarder, state: anytype) rosette_gpu.NativePresenterStage {
        return forwarder_impl_present_routing.preflightNativePresenter(self, state);
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
    pub fn discoverGuestFrameSource(self: *Forwarder, state: anytype) void {
        return forwarder_impl_present_routing.discoverGuestFrameSource(self, state);
    }

    /// Put a frame on the window. Prefers a completed guest image, falls back to
    /// Rosette's native Vulkan presenter showing a diagnostic clear, and falls
    /// back again to the host Metal clear only when that presenter could not be
    /// brought up. Every one of those is labelled with what it actually is.
    pub fn presentWindowFrame(self: *Forwarder, state: anytype, serial: u64, width: u32, height: u32, stage_hint: u32) bool {
        return forwarder_impl_present_routing.presentWindowFrame(self, state, serial, width, height, stage_hint);
    }

    /// Fold real native presenter progress back into the backend-neutral
    /// handshake. `ready` is established before the first queue submission, so
    /// the initial handshake correctly lacks presentation. Once the driver has
    /// actually accepted a present request, leaving that early snapshot in
    /// place makes later diagnostics claim the proven path is still missing.
    /// This updates host-boundary facts only; it never marks a guest swap,
    /// publishes a ring pointer, or changes frame provenance.
    pub fn observeNativePresenterReport(self: *Forwarder, report: anytype) void {
        return forwarder_impl_present_routing.observeNativePresenterReport(self, report);
    }

    pub fn realVulkanHasMemoryProperty(self: *const Forwarder, property: u32) bool {
        return forwarder_impl_present_routing.realVulkanHasMemoryProperty(self, property);
    }

    pub fn realVulkanAdapterName(self: *const Forwarder) []const u8 {
        return forwarder_impl_present_routing.realVulkanAdapterName(self);
    }

    /// Describe the guest-created Vulkan device using only host facts already
    /// obtained from the native driver. A guest-facing synthetic handle never
    /// enters this description: it is an x86 ABI token, while these tokens are
    /// the native objects/function pointers that the forwarding layer actually
    /// uses.
    pub fn guestVulkanBoundary(self: *const Forwarder) rosette_gpu.backend.VulkanBoundary {
        return forwarder_impl_present_routing.guestVulkanBoundary(self);
    }

    pub fn logPendingGpuHandshake(self: *Forwarder, reason: []const u8) void {
        return forwarder_impl_present_routing.logPendingGpuHandshake(self, reason);
    }

    pub fn faultOnGpuHandshake(
        self: *Forwarder,
        response: *const rosette_gpu.HandshakeResponse,
        reason: []const u8,
    ) noreturn {
        return forwarder_impl_present_routing.faultOnGpuHandshake(self, response, reason);
    }

    pub fn faultOnUnavailableVulkanCommand(self: *Forwarder, name: []const u8) noreturn {
        return forwarder_impl_present_routing.faultOnUnavailableVulkanCommand(self, name);
    }

    pub fn negotiateRosetteGpuBoundary(self: *Forwarder, reason: []const u8) void {
        return forwarder_impl_present_routing.negotiateRosetteGpuBoundary(self, reason);
    }

    pub fn createMetalSurface(self: *Forwarder, state: anytype, library_token: u64, instance: u64, create_info: u64, output: u64) u64 {
        return forwarder_impl_present_routing.createMetalSurface(self, state, library_token, instance, create_info, output);
    }

    pub fn recordSurfacePathResult(self: *Forwarder, state: anytype, result: u64, output: u64) u64 {
        return forwarder_impl_present_routing.recordSurfacePathResult(self, state, result, output);
    }

    pub fn createRealGuestMetalSurface(self: *Forwarder, state: anytype, guest_instance: u64, layer_token: u64) NativeSurfaceResult {
        return forwarder_impl_present_routing.createRealGuestMetalSurface(self, state, guest_instance, layer_token);
    }

    pub fn shouldBringUpNativePresenter(real_surface: NativeSurfaceResult) bool {
        return forwarder_impl_present_routing.shouldBringUpNativePresenter(real_surface);
    }

    pub fn guestDeviceMatches(self: *const Forwarder, guest_device: u64) bool {
        return forwarder_impl_present_routing.guestDeviceMatches(self, guest_device);
    }

    pub fn createSwapchain(self: *Forwarder, state: anytype, device: u64, create_info: u64, output: u64) u64 {
        return forwarder_impl_present_routing.createSwapchain(self, state, device, create_info, output);
    }

    pub fn enumerateSwapchainImages(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_present_routing.enumerateSwapchainImages(self, state);
    }

    pub fn acquireNextImage(self: *Forwarder, state: anytype, output: u64) u64 {
        return forwarder_impl_present_routing.acquireNextImage(self, state, output);
    }

    pub fn queueSubmit(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_present_routing.queueSubmit(self, state);
    }

    pub fn queueSubmit2(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_present_routing.queueSubmit2(self, state);
    }

    pub fn queueBindSparse(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_present_routing.queueBindSparse(self, state);
    }

    pub fn pixelProbeBytesPerPixel(format: u32) ?u64 {
        return forwarder_impl_texture_capture.pixelProbeBytesPerPixel(format);
    }

    pub fn notePixelProbeResult(
        self: *Forwarder,
        swapchain: abi.SwapchainKHR,
        evidence: rosette_gpu.PresentPixelEvidence,
        hash: u64,
        frame: u64,
        uniform_value: u32,
        image: u64,
        write_kind: WriteKind,
    ) void {
        return forwarder_impl_texture_capture.notePixelProbeResult(self, swapchain, evidence, hash, frame, uniform_value, image, write_kind);
    }

    pub fn pixelProbeFailure(
        self: *Forwarder,
        swapchain: abi.SwapchainKHR,
        frame: u64,
        result: abi.Result,
        reason: []const u8,
        image: u64,
        write_kind: WriteKind,
    ) void {
        return forwarder_impl_texture_capture.pixelProbeFailure(self, swapchain, frame, result, reason, image, write_kind);
    }

    pub fn destroyFsiZpdSinkResources(self: *Forwarder) void {
        return forwarder_impl_texture_capture.destroyFsiZpdSinkResources(self);
    }

    pub fn ensureFsiZpdSink(self: *Forwarder, range: u64) ?abi.Buffer {
        return forwarder_impl_texture_capture.ensureFsiZpdSink(self, range);
    }

    pub fn destroyPixelProbeResources(self: *Forwarder) void {
        return forwarder_impl_texture_capture.destroyPixelProbeResources(self);
    }

    pub fn ensurePixelProbeResources(self: *Forwarder, size: u64, queue_family: u32) bool {
        return forwarder_impl_texture_capture.ensurePixelProbeResources(self, size, queue_family);
    }

    /// Hand presentation progress to the window bridge. Accepted native WSI
    /// presents keep the input latch clock moving and provide the HUD rate;
    /// strict RGB/completion qualification remains a separate diagnostic.
    /// The bridge updates UI at most four times a second and never
    /// synchronously hops to AppKit.
    pub fn notePresentationProgress(self: *Forwarder, now_ns: u64) void {
        return forwarder_impl_texture_capture.notePresentationProgress(self, now_ns);
    }

    pub fn configureFrameCapture(self: *Forwarder) void {
        return forwarder_impl_texture_capture.configureFrameCapture(self);
    }

    pub fn captureReadback(self: *Forwarder, capture: PendingReadbackCapture, picture_frame: u64) void {
        return forwarder_impl_texture_capture.captureReadback(self, capture, picture_frame);
    }

    pub fn probeGuestSwapchainImage(
        self: *Forwarder,
        synthetic_swapchain: u64,
        real_swapchain: abi.SwapchainKHR,
        image_index: u32,
        frame: u64,
        write_kind: WriteKind,
        force_content_probe: bool,
        present_queue: abi.Queue,
        present_waits: []const abi.Semaphore,
        waits_consumed: *bool,
        capture: *?PendingReadbackCapture,
        capture_bytes: *u64,
    ) void {
        return forwarder_impl_texture_capture.probeGuestSwapchainImage(self, synthetic_swapchain, real_swapchain, image_index, frame, write_kind, force_content_probe, present_queue, present_waits, waits_consumed, capture, capture_bytes);
    }

    /// The queue family a present queue belongs to, for a readback that must
    /// record on the same family the image was released to.
    pub fn presentQueueFamily(self: *const Forwarder, present_queue: abi.Queue) ?u32 {
        return forwarder_impl_texture_capture.presentQueueFamily(self, present_queue);
    }

    /// The guest handle behind a host image, for following a present-chain
    /// edge (which is kept in host identities) back to the resource record
    /// (which is kept by guest handle).
    pub fn syntheticImageForReal(self: *const Forwarder, real: u64) ?u64 {
        return forwarder_impl_texture_capture.syntheticImageForReal(self, real);
    }

    /// Copy one colour image, mip 0 layer 0, into the probe's staging buffer
    /// and return its bytes. The image is moved out of and back into
    /// `layout`; the caller says what layout the image rests in. Completion
    /// is the queue going idle, as for the swapchain probe, so the bytes are
    /// valid until the next readback reuses the staging buffer.
    pub fn readbackImageBytes(
        self: *Forwarder,
        image: abi.Image,
        width: u32,
        height: u32,
        format: u32,
        layout: u32,
        queue: abi.Queue,
        queue_family: u32,
    ) ?[]const u8 {
        return forwarder_impl_texture_capture.readbackImageBytes(self, image, width, height, format, layout, queue, queue_family);
    }

    /// Fill one ladder stage from a host image identity: find its guest
    /// record, read it back and measure it. Every failure is named in
    /// `status` rather than dropped, because a stage that could not be read
    /// is different from a stage that read dark.
    pub fn readLadderStage(
        self: *Forwarder,
        stage: *LadderStage,
        real_image: u64,
        queue: abi.Queue,
        queue_family: u32,
        decode_as_xenos_7e3: bool,
    ) void {
        return forwarder_impl_texture_capture.readLadderStage(self, stage, real_image, queue, queue_family, decode_as_xenos_7e3);
    }

    /// Snapshot the most recent accepted FSI command buffers at the first
    /// observed transition to a near-white swapchain image. These are
    /// temporally adjacent candidates, not pass-level causality; GFXR remains
    /// necessary to identify the draw that first wrote the bad values.
    pub fn printFsiImageTransitionCandidates(self: *Forwarder, frame: u64) void {
        return forwarder_impl_texture_capture.printFsiImageTransitionCandidates(self, frame);
    }

    /// Read the two images upstream of a just-probed swapchain image and say
    /// where the brightness went. Bounded like the swapchain probe: the first
    /// eight content frames and the sparse render checkpoints.
    pub fn probeBrightnessLadder(self: *Forwarder, real_swapchain: abi.SwapchainKHR, frame: u64, queue: abi.Queue, swapchain_stats: frame_capture.Stats, format: u32) void {
        return forwarder_impl_texture_capture.probeBrightnessLadder(self, real_swapchain, frame, queue, swapchain_stats, format);
    }

    pub fn printLadderSampling(self: *const Forwarder, frame: u64, target: u64, source: *const LadderStage) void {
        return forwarder_impl_texture_capture.printLadderSampling(self, frame, target, source);
    }

    pub fn printLadderStage(self: *const Forwarder, frame: u64, stage: *const LadderStage) void {
        return forwarder_impl_texture_capture.printLadderStage(self, frame, stage);
    }

    /// Called with queue admission held, before any present-side semaphore
    /// consumption. Other guest CPU workers can acquire the runtime mutex while
    /// this queue's presenter sleeps. A pinned runtime lock refuses the wait.
    pub fn pacePresent(self: *Forwarder, state: anytype) bool {
        return forwarder_impl_texture_capture.pacePresent(self, state);
    }

    pub fn queuePresent(self: *Forwarder, state: anytype) u64 {
        return forwarder_impl_texture_capture.queuePresent(self, state);
    }

    pub fn allocateVulkanMemory(self: *Forwarder, state: anytype, info: u64, output: u64) u64 {
        return forwarder_impl_texture_capture.allocateVulkanMemory(self, state, info, output);
    }

    pub fn mapVulkanMemory(
        self: *Forwarder,
        state: anytype,
        memory_handle: u64,
        offset: u64,
        requested_size: u64,
        output: u64,
    ) u64 {
        return forwarder_impl_texture_capture.mapVulkanMemory(self, state, memory_handle, offset, requested_size, output);
    }

    pub fn freeVulkanMemoryRecord(self: *Forwarder) ?*VulkanMemoryAllocation {
        return forwarder_impl_texture_capture.freeVulkanMemoryRecord(self);
    }

    pub fn findVulkanMemoryRecord(self: *Forwarder, handle: u64) ?*VulkanMemoryAllocation {
        return forwarder_impl_texture_capture.findVulkanMemoryRecord(self, handle);
    }

    pub fn allocateVulkanObjects(self: *Forwarder, state: anytype, info: u64, output: u64, count_offset: u64, name: []const u8) u64 {
        return forwarder_impl_texture_capture.allocateVulkanObjects(self, state, info, output, count_offset, name);
    }

    pub fn observeFsiDescriptorSetLayout(self: *Forwarder, state: anytype, create_info: u64) void {
        return forwarder_impl_texture_capture.observeFsiDescriptorSetLayout(self, state, create_info);
    }

    pub fn copyGuestValue(comptime T: type, state: anytype, address: u64, value: *T) bool {
        return forwarder_impl_texture_capture.copyGuestValue(T, state, address, value);
    }

    pub fn guestPointerValue(comptime T: type, pointer: ?[*]const T) u64 {
        return forwarder_impl_texture_capture.guestPointerValue(T, pointer);
    }

    pub fn copyPipelineName(state: anytype, guest_pointer: u64, destination: *[64]u8) bool {
        return forwarder_impl_texture_capture.copyPipelineName(state, guest_pointer, destination);
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
        TessellationStructureTypeInvalid,
        TessellationChainUnreadable,
        TessellationChainUnsupported,
        TessellationDomainOriginInvalid,
        ViewportStateUnreadable,
        ViewportCountsOutOfRange,
        ViewportsUnreadable,
        ScissorsUnreadable,
        RasterizationUnreadable,
        MultisampleUnreadable,
        FsiRasterizationUnavailable,
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
    pub fn marshalGuestArray(
        comptime T: type,
        state: anytype,
        guest: ?[*]const T,
        count: u32,
        storage: []T,
        comptime unreadable: PipelineMarshalFailure,
    ) PipelineMarshalFailure!?[*]const T {
        return forwarder_impl_texture_capture.marshalGuestArray(T, state, guest, count, storage, unreadable);
    }

    /// Host-owned storage for one shader stage's specialization constants.
    /// The map and the data blob are both guest-owned, so both are copied.
    pub const SpecializationScratch = struct {
        info: abi.SpecializationInfo = .{},
        entries: [32]abi.SpecializationMapEntry = undefined,
        data: [256]u8 = undefined,
    };

    pub fn marshalSpecializationInfo(
        state: anytype,
        guest_address: u64,
        scratch: *SpecializationScratch,
    ) PipelineMarshalFailure!*const abi.SpecializationInfo {
        return forwarder_impl_texture_capture.marshalSpecializationInfo(state, guest_address, scratch);
    }

    const NativeGraphicsPipelineCall = @import("pipeline_host_call.zig").Graphics;
    const NativeComputePipelineCall = @import("pipeline_host_call.zig").Compute;

    pub fn callNativeGraphicsPipeline(
        state: anytype,
        function: abi.PfnCreateGraphicsPipelines,
        device: abi.Device,
        cache: abi.PipelineCache,
        info: *const abi.GraphicsPipelineCreateInfo,
        output: *u64,
    ) abi.Result {
        return forwarder_impl_texture_capture.callNativeGraphicsPipeline(state, function, device, cache, info, output);
    }

    pub fn callNativeComputePipeline(
        state: anytype,
        function: abi.PfnCreateComputePipelines,
        device: abi.Device,
        cache: abi.PipelineCache,
        info: *const abi.ComputePipelineCreateInfo,
        output: *u64,
    ) abi.Result {
        return forwarder_impl_texture_capture.callNativeComputePipeline(state, function, device, cache, info, output);
    }

    pub fn createRealGraphicsPipeline(
        self: *Forwarder,
        state: anytype,
        cache: u64,
        guest_address: u64,
        real_output: *u64,
        result_output: *i32,
        tessellation_pipeline: *bool,
        reason: *[]const u8,
    ) bool {
        return forwarder_impl_runtime_dispatch.createRealGraphicsPipeline(self, state, cache, guest_address, real_output, result_output, tessellation_pipeline, reason);
    }

    pub fn marshalRealGraphicsPipeline(
        self: *Forwarder,
        state: anytype,
        cache: u64,
        guest_address: u64,
        real_output: *u64,
        result_output: *i32,
        tessellation_pipeline: *bool,
    ) PipelineMarshalFailure!void {
        return forwarder_impl_runtime_dispatch.marshalRealGraphicsPipeline(self, state, cache, guest_address, real_output, result_output, tessellation_pipeline);
    }

    pub fn createRealComputePipeline(
        self: *Forwarder,
        state: anytype,
        cache: u64,
        guest_address: u64,
        real_output: *u64,
        result_output: *i32,
        reason: *[]const u8,
    ) bool {
        return forwarder_impl_runtime_dispatch.createRealComputePipeline(self, state, cache, guest_address, real_output, result_output, reason);
    }

    /// Copy the tessellation state and its one Vulkan-defined pNext node into
    /// host-owned scratch. Forwarding the guest's nested pointer would hand a
    /// guest address to the native Vulkan driver; rejecting every non-null
    /// pNext silently disabled the legal lower-left domain-origin setting.
    pub fn marshalPipelineTessellationState(
        state: anytype,
        guest_address: u64,
        tessellation: *abi.PipelineTessellationStateCreateInfo,
        domain_origin: *abi.PipelineTessellationDomainOriginStateCreateInfo,
    ) PipelineMarshalFailure!void {
        return forwarder_impl_runtime_dispatch.marshalPipelineTessellationState(state, guest_address, tessellation, domain_origin);
    }

    pub fn marshalRealComputePipeline(
        self: *Forwarder,
        state: anytype,
        cache: u64,
        guest_address: u64,
        real_output: *u64,
        result_output: *i32,
    ) PipelineMarshalFailure!void {
        return forwarder_impl_runtime_dispatch.marshalRealComputePipeline(self, state, cache, guest_address, real_output, result_output);
    }

    /// A vkCreate*Pipelines call is atomic from the guest's perspective even
    /// though the bridge forwards one pipeline at a time so each create-info
    /// can be translated independently.  If a later item fails, dispose of
    /// every earlier native pipeline and its reverse mapping before returning
    /// the failure.  Otherwise a title that retries a partially failed batch
    /// would leak one native object per retry and eventually hit the same
    /// long-run resource wall as the old descriptor-set map.
    pub fn rollbackCreatedVulkanPipelines(self: *Forwarder, synthetic_pipelines: []const u64) void {
        return forwarder_impl_runtime_dispatch.rollbackCreatedVulkanPipelines(self, synthetic_pipelines);
    }

    pub fn createMultipleVulkanObjects(self: *Forwarder, state: anytype, count: u64, output: u64, name: []const u8) u64 {
        return forwarder_impl_runtime_dispatch.createMultipleVulkanObjects(self, state, count, output, name);
    }

    pub fn openGuest(self: *Forwarder, path: []const u8, mode: u64) u64 {
        return forwarder_impl_runtime_dispatch.openGuest(self, path, mode);
    }

    pub fn closeGuest(self: *Forwarder, token: u64) c_int {
        return forwarder_impl_runtime_dispatch.closeGuest(self, token);
    }

    pub fn forward(self: *Forwarder, state: anytype, dylib: []const u8, symbol: []const u8) ?Outcome {
        return forwarder_impl_runtime_dispatch.forward(self, state, dylib, symbol);
    }

    pub fn handleStubSignature(self: *Forwarder, state: anytype, signature: Signature) ?Outcome {
        return forwarder_impl_runtime_dispatch.handleStubSignature(self, state, signature);
    }

    pub fn virtualGuestSleep(self: *Forwarder, state: anytype) ?Outcome {
        return forwarder_impl_runtime_dispatch.virtualGuestSleep(self, state);
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
        return forwarder_impl_runtime_dispatch.presentXeniaOutputFrame(self, pixels, width, height, row_pitch_bytes, orientation, guest_swap_observed);
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
        format: rosette_gpu.xenos_texture.Format,
        harness_supplied: bool,
    ) void {
        return forwarder_impl_runtime_dispatch.noteGuestFrontBuffer(self, source, width, height, tiled, endian, format, harness_supplied);
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
    pub fn publishGuestFrontBuffer(self: *Forwarder, state: anytype) bool {
        return forwarder_impl_runtime_dispatch.publishGuestFrontBuffer(self, state);
    }

    /// Called when the guest's own bootstrap observes a `VdSwap`, so a frame
    /// discovered afterwards may be classified as guest output. Kept separate
    /// from frame delivery because a frame arriving is not a swap happening,
    /// and merging them is exactly how a host frame becomes mislabelled.
    /// Present the console-owned front buffer immediately after the PE route
    /// observes VdSwap. This is the fallback for the Xenia path whose GPU
    /// thread can consume PM4 and perform IssueSwap without entering the
    /// exported RefreshGuestOutput symbol.
    pub fn presentGuestFrontBuffer(
        self: *Forwarder,
        state: anytype,
        source: u64,
        width: u32,
        height: u32,
        tiled: bool,
        endian: rosette_gpu.xenos_texture.Endian,
        format: rosette_gpu.xenos_texture.Format,
        guest_swap_observed: bool,
    ) bool {
        return forwarder_impl_runtime_dispatch.presentGuestFrontBuffer(self, state, source, width, height, tiled, endian, format, guest_swap_observed);
    }

    pub fn noteGuestSwapObserved(self: *Forwarder) void {
        return forwarder_impl_runtime_dispatch.noteGuestSwapObserved(self);
    }

    /// The window changed size or backing scale. The swapchain is rebuilt from
    /// the surface's own capabilities at the next frame rather than from these
    /// numbers, which are only the fallback for a surface with no fixed size.
    pub fn noteNativeWindowResize(self: *Forwarder, width: u32, height: u32) void {
        return forwarder_impl_runtime_dispatch.noteNativeWindowResize(self, width, height);
    }

    pub fn nativePresenterStage(self: *const Forwarder) rosette_gpu.NativePresenterStage {
        return forwarder_impl_runtime_dispatch.nativePresenterStage(self);
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
        return forwarder_impl_runtime_dispatch.attemptScheduledRefresh(self, state);
    }

    /// Populate the descriptor inbox even when Vulkan presentation is down.
    /// Discovery is read-only and remains subject to the same non-zero pixel,
    /// mapping, extent and format checks as the Vulkan presenter path.
    pub fn refreshCocoaFallbackSource(self: *Forwarder, state: anytype) void {
        return forwarder_impl_runtime_dispatch.refreshCocoaFallbackSource(self, state);
    }

    /// Present one verified descriptor through the direct Cocoa/Metal copy.
    /// This is called only after the Cocoa control plane selected the fallback
    /// under an exclusive Rosette presenter lease. A missing or unusable source
    /// remains unconsumed so a later corrected descriptor can be retried.
    pub fn attemptCocoaFrameFallback(self: *Forwarder, state: anytype) bool {
        return forwarder_impl_runtime_dispatch.attemptCocoaFrameFallback(self, state);
    }

    pub fn logScheduledRefresh(self: *const Forwarder) void {
        return forwarder_impl_runtime_dispatch.logScheduledRefresh(self);
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
        return forwarder_impl_runtime_dispatch.nativePresenterFramesPresented(self);
    }

    /// Number of guest Vulkan present requests that actually crossed the
    /// Rosette forwarding boundary into the host driver.
    ///
    /// This is deliberately not `nativePresenterFramesPresented()`. The
    /// native presenter owns the window-frame ledger, while this counter is
    /// recorded by the guest Vulkan forwarding path immediately after it
    /// invokes the real `vkQueuePresentKHR`. A request can therefore be
    /// observed here before a drawable is completed, and a completed frame
    /// must never be used as a proxy for the request that caused it.
    pub fn guestVulkanPresentRequests(self: *const Forwarder) u64 {
        return forwarder_impl_runtime_dispatch.guestVulkanPresentRequests(self);
    }

    pub fn graphicsOwnershipSnapshot(self: *const Forwarder) GraphicsOwnershipSnapshot {
        return forwarder_impl_runtime_dispatch.graphicsOwnershipSnapshot(self);
    }

    /// Real guest Vulkan progress, kept separate from Rosette's presenter
    /// ledger.  A queue submission or command call is evidence that the
    /// guest's object mapping reached the host driver; it is not by itself
    /// evidence that a visible frame was produced.
    pub fn guestVulkanInstanceReady(self: *const Forwarder) bool {
        return forwarder_impl_runtime_dispatch.guestVulkanInstanceReady(self);
    }

    pub fn guestVulkanDeviceReady(self: *const Forwarder) bool {
        return forwarder_impl_runtime_dispatch.guestVulkanDeviceReady(self);
    }

    pub fn guestVulkanDeviceLost(self: *const Forwarder) bool {
        return forwarder_impl_runtime_dispatch.guestVulkanDeviceLost(self);
    }

    pub fn guestVulkanCommandsForwarded(self: *const Forwarder) u64 {
        return forwarder_impl_runtime_dispatch.guestVulkanCommandsForwarded(self);
    }

    pub fn guestVulkanQueueSubmits(self: *const Forwarder) u64 {
        return forwarder_impl_runtime_dispatch.guestVulkanQueueSubmits(self);
    }

    pub fn guestVulkanPresents(self: *const Forwarder) u64 {
        return forwarder_impl_runtime_dispatch.guestVulkanPresents(self);
    }

    /// Number of guest Vulkan present requests for which the forwarding layer
    /// observed a host queue-idle completion edge. This is deliberately
    /// separate from `guestVulkanPresents`: an accepted WSI request is not a
    /// completed GPU operation.
    pub fn guestVulkanPresentCompletions(self: *const Forwarder) u64 {
        return forwarder_impl_runtime_dispatch.guestVulkanPresentCompletions(self);
    }

    pub fn guestVulkanObservedCommands(self: *const Forwarder) u64 {
        return forwarder_impl_runtime_dispatch.guestVulkanObservedCommands(self);
    }

    pub fn virtualSleepCallCount(self: *const Forwarder) u64 {
        return forwarder_impl_runtime_dispatch.virtualSleepCallCount(self);
    }

    pub fn lastVirtualSleepDecision(self: *const Forwarder) guest_sleep.Decision {
        return forwarder_impl_runtime_dispatch.lastVirtualSleepDecision(self);
    }

    pub fn logSummary(self: *Forwarder) void {
        return forwarder_impl_runtime_dispatch.logSummary(self);
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
        return forwarder_impl_runtime_dispatch.guestFrontBufferAvailable(self);
    }

    /// Whether the console-framebuffer conversion has ever refused a surface
    /// for its *format*, as opposed to for its size or its mapping.
    ///
    /// The swap gate needs the distinction: a truncated read is an ordering
    /// problem that a later scan can fix, and an unsupported format is a
    /// capability Rosette does not have and will not acquire by retrying.
    /// How many frame generations any producer has published into the inbox.
    ///
    /// The output handoff invariant needs a number that is zero only when
    /// *nothing* has ever produced a frame — not a presented count, which a
    /// diagnostic clear also advances.
    /// What this host advertises for a texture format, or null when no
    /// physical device has been selected yet.
    ///
    /// Rosette's presenter owns a real `VkPhysicalDevice`, so the question of
    /// whether the host has `A2B10G10R10_SNORM_PACK32` is one Rosette answers
    /// rather than one it reads out of the emulator's log.
    pub fn presenterFormatFeatures(self: *Forwarder, format: u32) ?u32 {
        return forwarder_impl_runtime_dispatch.presenterFormatFeatures(self, format);
    }

    pub fn presenterFormatProperties(self: *Forwarder, format: u32) ?abi.FormatProperties {
        return forwarder_impl_runtime_dispatch.presenterFormatProperties(self, format);
    }

    pub fn publishedFrameGenerations(self: *const Forwarder) u64 {
        return forwarder_impl_runtime_dispatch.publishedFrameGenerations(self);
    }

    pub fn guestFrontBufferFormatRefused(self: *const Forwarder) bool {
        return forwarder_impl_runtime_dispatch.guestFrontBufferFormatRefused(self);
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
        return forwarder_impl_runtime_dispatch.logVulkanTiers(self);
    }

    pub fn logGuestFrontBuffer(self: *const Forwarder) void {
        return forwarder_impl_runtime_dispatch.logGuestFrontBuffer(self);
    }

    pub fn logGraphicsProvenance(self: *const Forwarder) void {
        return forwarder_impl_runtime_dispatch.logGraphicsProvenance(self);
    }

    pub fn libraryHandle(self: *Forwarder, dylib: []const u8) ?*anyopaque {
        return forwarder_impl_runtime_dispatch.libraryHandle(self, dylib);
    }

    pub fn guestLibraryEntry(self: *Forwarder, token: u64) ?*GuestLibrary {
        return forwarder_impl_runtime_dispatch.guestLibraryEntry(self, token);
    }

    pub fn guestLibrary(self: *Forwarder, token: u64) ?*anyopaque {
        return forwarder_impl_runtime_dispatch.guestLibrary(self, token);
    }

    pub fn materializeNativeVulkanLibrary(self: *Forwarder, token: u64) ?*anyopaque {
        return forwarder_impl_runtime_dispatch.materializeNativeVulkanLibrary(self, token);
    }

    pub fn invoke(self: *Forwarder, state: anytype, signature: Signature, address: *anyopaque) ?Outcome {
        return forwarder_impl_runtime_dispatch.invoke(self, state, signature, address);
    }
};

/// Narrow export table used only by split Mach-O process modules.
pub const __ForwarderInternals = struct {
    pub const _BridgeCapabilityScratch = BridgeCapabilityScratch;
    pub const _BridgeDeviceCapability = BridgeDeviceCapability;
    pub const _BrightnessLadderState = BrightnessLadderState;
    pub const _BrightnessLoss = BrightnessLoss;
    pub const _DescriptorBindAdmission = DescriptorBindAdmission;
    pub const _DescriptorBindRejectReason = DescriptorBindRejectReason;
    pub const _DescriptorUpdateFailureDetails = DescriptorUpdateFailureDetails;
    pub const _DescriptorUpdateRefusal = DescriptorUpdateRefusal;
    pub const _DescriptorUpdateTemplateRecord = DescriptorUpdateTemplateRecord;
    pub const _DeviceFnPtrs = DeviceFnPtrs;
    pub const _FeatureChainScratch = FeatureChainScratch;
    pub const _FsiCommandBufferEntry = FsiCommandBufferEntry;
    pub const _FsiCommandClass = FsiCommandClass;
    pub const _FsiFenceContext = FsiFenceContext;
    pub const _FsiGuard = FsiGuard;
    pub const _FsiGuestChainStatus = FsiGuestChainStatus;
    pub const _FsiGuestFeatureRequest = FsiGuestFeatureRequest;
    pub const _FsiReplayOps = FsiReplayOps;
    pub const _FsiSegment = FsiSegment;
    pub const _FsiZpdSinkState = FsiZpdSinkState;
    pub const _GUEST_LIBRARY_HANDLE_BASE = GUEST_LIBRARY_HANDLE_BASE;
    pub const _GUEST_SYMBOL_LOOKUP_CACHE_SIZE = GUEST_SYMBOL_LOOKUP_CACHE_SIZE;
    pub const _GUEST_SYMBOL_THUNK_BASE = GUEST_SYMBOL_THUNK_BASE;
    pub const _GraphicsOwnershipSnapshot = GraphicsOwnershipSnapshot;
    pub const _GraphicsStateTrace = GraphicsStateTrace;
    pub const _GuestFrameEvidence = GuestFrameEvidence;
    pub const _GuestLibrary = GuestLibrary;
    pub const _GuestSymbol = GuestSymbol;
    pub const _GuestSymbolKind = GuestSymbolKind;
    pub const _GuestSymbolLookupCacheEntry = GuestSymbolLookupCacheEntry;
    pub const _HandleMap = HandleMap;
    pub const _HostFrameCaptureFn = HostFrameCaptureFn;
    pub const _HostFrameCaptureResolver = HostFrameCaptureResolver;
    pub const _HostFrameCounterResolver = HostFrameCounterResolver;
    pub const _HostWindowDescribeFn = HostWindowDescribeFn;
    pub const _HostWindowDescribeResolver = HostWindowDescribeResolver;
    pub const _LadderStage = LadderStage;
    pub const _Library = Library;
    pub const _LibraryClass = LibraryClass;
    pub const _MAX_DEVICE_EXTENSION_NAMES = MAX_DEVICE_EXTENSION_NAMES;
    pub const _MAX_DEVICE_QUEUE_INFOS = MAX_DEVICE_QUEUE_INFOS;
    pub const _MAX_GUEST_LIBRARIES = MAX_GUEST_LIBRARIES;
    pub const _MAX_GUEST_SYMBOLS = MAX_GUEST_SYMBOLS;
    pub const _MAX_HOST_DEVICE_EXTENSIONS = MAX_HOST_DEVICE_EXTENSIONS;
    pub const _MAX_INSTANCE_EXTENSION_NAMES = MAX_INSTANCE_EXTENSION_NAMES;
    pub const _MAX_LIBRARIES = MAX_LIBRARIES;
    pub const _MAX_QUEUES_PER_CREATE_INFO = MAX_QUEUES_PER_CREATE_INFO;
    pub const _MAX_REAL_BUFFERS = MAX_REAL_BUFFERS;
    pub const _MAX_REAL_BUFFER_VIEWS = MAX_REAL_BUFFER_VIEWS;
    pub const _MAX_REAL_COMMAND_BUFFERS = MAX_REAL_COMMAND_BUFFERS;
    pub const _MAX_REAL_COMMAND_POOLS = MAX_REAL_COMMAND_POOLS;
    pub const _MAX_REAL_DESCRIPTOR_POOLS = MAX_REAL_DESCRIPTOR_POOLS;
    pub const _MAX_REAL_DESCRIPTOR_SETS = MAX_REAL_DESCRIPTOR_SETS;
    pub const _MAX_REAL_DESCRIPTOR_SET_LAYOUTS = MAX_REAL_DESCRIPTOR_SET_LAYOUTS;
    pub const _MAX_REAL_DESCRIPTOR_UPDATE_TEMPLATES = MAX_REAL_DESCRIPTOR_UPDATE_TEMPLATES;
    pub const _MAX_REAL_FENCES = MAX_REAL_FENCES;
    pub const _MAX_REAL_FRAMEBUFFERS = MAX_REAL_FRAMEBUFFERS;
    pub const _MAX_REAL_IMAGES = MAX_REAL_IMAGES;
    pub const _MAX_REAL_IMAGE_VIEWS = MAX_REAL_IMAGE_VIEWS;
    pub const _MAX_REAL_MEMORY = MAX_REAL_MEMORY;
    pub const _MAX_REAL_PIPELINES = MAX_REAL_PIPELINES;
    pub const _MAX_REAL_PIPELINE_CACHES = MAX_REAL_PIPELINE_CACHES;
    pub const _MAX_REAL_PIPELINE_LAYOUTS = MAX_REAL_PIPELINE_LAYOUTS;
    pub const _MAX_REAL_QUERY_POOLS = MAX_REAL_QUERY_POOLS;
    pub const _MAX_REAL_QUEUES = MAX_REAL_QUEUES;
    pub const _MAX_REAL_RENDER_PASSES = MAX_REAL_RENDER_PASSES;
    pub const _MAX_REAL_SAMPLERS = MAX_REAL_SAMPLERS;
    pub const _MAX_REAL_SEMAPHORES = MAX_REAL_SEMAPHORES;
    pub const _MAX_REAL_SHADER_MODULES = MAX_REAL_SHADER_MODULES;
    pub const _MAX_REAL_SWAPCHAINS = MAX_REAL_SWAPCHAINS;
    pub const _MAX_RECT_EXPAND_MODULES = MAX_RECT_EXPAND_MODULES;
    pub const _MAX_RECT_EXPAND_PIPELINES = MAX_RECT_EXPAND_PIPELINES;
    pub const _MAX_SURFACE_ENUMERATION = MAX_SURFACE_ENUMERATION;
    pub const _MAX_SWAPCHAIN_IMAGES = MAX_SWAPCHAIN_IMAGES;
    pub const _MAX_TRACKED_DESCRIPTOR_IMAGES = MAX_TRACKED_DESCRIPTOR_IMAGES;
    pub const _MAX_TRACKED_DESCRIPTOR_SETS = MAX_TRACKED_DESCRIPTOR_SETS;
    pub const _MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND = MAX_TRACKED_DESCRIPTOR_SETS_PER_COMMAND;
    pub const _MAX_TRACKED_PASS_EDGES = MAX_TRACKED_PASS_EDGES;
    pub const _MAX_TRACKED_RESOURCE_TRANSFERS = MAX_TRACKED_RESOURCE_TRANSFERS;
    pub const _MAX_TRACKED_TARGET_ATTACHMENTS = MAX_TRACKED_TARGET_ATTACHMENTS;
    pub const _MAX_VULKAN_CREATE_LEDGER = MAX_VULKAN_CREATE_LEDGER;
    pub const _MAX_VULKAN_LOADER_CANDIDATES = MAX_VULKAN_LOADER_CANDIDATES;
    pub const _MAX_VULKAN_LOOKUP_MISSES = MAX_VULKAN_LOOKUP_MISSES;
    pub const _MAX_VULKAN_MEMORY_ALLOCATIONS = MAX_VULKAN_MEMORY_ALLOCATIONS;
    pub const _MAX_VULKAN_RESOURCES = MAX_VULKAN_RESOURCES;
    pub const _MODELLED_MEMORY_TYPE_COUNT = MODELLED_MEMORY_TYPE_COUNT;
    pub const _NativeSurfaceResult = NativeSurfaceResult;
    pub const _Outcome = Outcome;
    pub const _PIXEL_PROBE_CONTENT_SAMPLES = PIXEL_PROBE_CONTENT_SAMPLES;
    pub const _PIXEL_PROBE_INITIAL_SAMPLES = PIXEL_PROBE_INITIAL_SAMPLES;
    pub const _PIXEL_PROBE_MAX_BYTES = PIXEL_PROBE_MAX_BYTES;
    pub const _PendingReadbackCapture = PendingReadbackCapture;
    pub const _PfnVkCreateInstance = PfnVkCreateInstance;
    pub const _PfnVkCreateMetalSurfaceEXT = PfnVkCreateMetalSurfaceEXT;
    pub const _PfnVkDestroyInstance = PfnVkDestroyInstance;
    pub const _PfnVkDestroySurfaceKHR = PfnVkDestroySurfaceKHR;
    pub const _PfnVkEnumerateInstanceLayerProperties = PfnVkEnumerateInstanceLayerProperties;
    pub const _PfnVkGetInstanceProcAddr = PfnVkGetInstanceProcAddr;
    pub const _PhysicalDeviceGuestHandle = PhysicalDeviceGuestHandle;
    pub const _PixelProbeState = PixelProbeState;
    pub const _PropertyChainScratch = PropertyChainScratch;
    pub const _RECT_EXPAND_COMMAND_STATES = RECT_EXPAND_COMMAND_STATES;
    pub const _RTLD_DEFAULT_HANDLE = RTLD_DEFAULT_HANDLE;
    pub const _RTLD_LAZY = RTLD_LAZY;
    pub const _RTLD_LOCAL = RTLD_LOCAL;
    pub const _ReadbackSample = ReadbackSample;
    pub const _RealHandle = RealHandle;
    pub const _RealVulkanState = RealVulkanState;
    pub const _RectExpandCommandState = RectExpandCommandState;
    pub const _RectForeignIndexSample = RectForeignIndexSample;
    pub const _SYNTHETIC_DEBUG_MESSENGER_HANDLE = SYNTHETIC_DEBUG_MESSENGER_HANDLE;
    pub const _SYNTHETIC_PHYSICAL_DEVICE_HANDLE = SYNTHETIC_PHYSICAL_DEVICE_HANDLE;
    pub const _Signature = Signature;
    pub const _SlotIndex = SlotIndex;
    pub const _Spec = Spec;
    pub const _SwapchainRecord = SwapchainRecord;
    pub const _TargetOverflowKind = TargetOverflowKind;
    pub const _TrackedBufferView = TrackedBufferView;
    pub const _TrackedCommandDescriptorSet = TrackedCommandDescriptorSet;
    pub const _TrackedCommandTargets = TrackedCommandTargets;
    pub const _TrackedDescriptorImage = TrackedDescriptorImage;
    pub const _TrackedDescriptorSet = TrackedDescriptorSet;
    pub const _TrackedFramebuffer = TrackedFramebuffer;
    pub const _TrackedGraphicsPipeline = TrackedGraphicsPipeline;
    pub const _TrackedImageTransfer = TrackedImageTransfer;
    pub const _TrackedImageView = TrackedImageView;
    pub const _TrackedPassEdge = TrackedPassEdge;
    pub const _TrackedPipelineLayout = TrackedPipelineLayout;
    pub const _TrackedRenderPass = TrackedRenderPass;
    pub const _TrackedTexelBinding = TrackedTexelBinding;
    pub const _VK_ATTACHMENT_LOAD_OP_CLEAR = VK_ATTACHMENT_LOAD_OP_CLEAR;
    pub const _VK_BUFFER_CREATE_INFO_SIZE = VK_BUFFER_CREATE_INFO_SIZE;
    pub const _VK_BUFFER_CREATE_INFO_SIZE_OFFSET = VK_BUFFER_CREATE_INFO_SIZE_OFFSET;
    pub const _VK_BUFFER_CREATE_INFO_USAGE_OFFSET = VK_BUFFER_CREATE_INFO_USAGE_OFFSET;
    pub const _VK_DRIVER_ID_MOLTENVK = VK_DRIVER_ID_MOLTENVK;
    pub const _VK_DYNAMIC_STATE_SCISSOR = VK_DYNAMIC_STATE_SCISSOR;
    pub const _VK_DYNAMIC_STATE_VIEWPORT = VK_DYNAMIC_STATE_VIEWPORT;
    pub const _VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET = VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET;
    pub const _VK_IMAGE_CREATE_INFO_EXTENT_OFFSET = VK_IMAGE_CREATE_INFO_EXTENT_OFFSET;
    pub const _VK_IMAGE_CREATE_INFO_FORMAT_OFFSET = VK_IMAGE_CREATE_INFO_FORMAT_OFFSET;
    pub const _VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET = VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET;
    pub const _VK_IMAGE_CREATE_INFO_SIZE = VK_IMAGE_CREATE_INFO_SIZE;
    pub const _VK_IMAGE_CREATE_INFO_TILING_OFFSET = VK_IMAGE_CREATE_INFO_TILING_OFFSET;
    pub const _VK_IMAGE_CREATE_INFO_USAGE_OFFSET = VK_IMAGE_CREATE_INFO_USAGE_OFFSET;
    pub const _VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    pub const _VK_PHYSICAL_DEVICE_LIMITS_OFFSET = VK_PHYSICAL_DEVICE_LIMITS_OFFSET;
    pub const _VK_PHYSICAL_DEVICE_PROPERTIES_SIZE = VK_PHYSICAL_DEVICE_PROPERTIES_SIZE;
    pub const _VK_PIPELINE_BIND_POINT_GRAPHICS = VK_PIPELINE_BIND_POINT_GRAPHICS;
    pub const _VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pub const _VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
    pub const _VK_SAMPLE_COUNT_1_BIT = VK_SAMPLE_COUNT_1_BIT;
    pub const _VK_SAMPLE_COUNT_4_BIT = VK_SAMPLE_COUNT_4_BIT;
    pub const _VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT = VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT;
    pub const _VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT = VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
    pub const _VK_SHADER_STAGE_VERTEX_BIT = VK_SHADER_STAGE_VERTEX_BIT;
    pub const _VK_STRUCTURE_TYPE_APPLICATION_INFO = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    pub const _VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    pub const _VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    pub const _VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
    pub const _VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES;
    pub const _VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    pub const _VK_SWAPCHAIN_CREATE_INFO_SIZE = VK_SWAPCHAIN_CREATE_INFO_SIZE;
    pub const _VK_SYNTHETIC_DEVICE = VK_SYNTHETIC_DEVICE;
    pub const _VK_SYNTHETIC_QUEUE = VK_SYNTHETIC_QUEUE;
    pub const _VK_SYNTHETIC_SURFACE = VK_SYNTHETIC_SURFACE;
    pub const _VULKAN_CREATE_NAME_BYTES = VULKAN_CREATE_NAME_BYTES;
    pub const _VULKAN_LOADER_PATH_CAPACITY = VULKAN_LOADER_PATH_CAPACITY;
    pub const _VkApplicationInfo = VkApplicationInfo;
    pub const _VkInstanceCreateInfo = VkInstanceCreateInfo;
    pub const _VkLayerProperties = VkLayerProperties;
    pub const _VkMetalSurfaceCreateInfoEXT = VkMetalSurfaceCreateInfoEXT;
    pub const _VulkanAbsentEntryPoints = VulkanAbsentEntryPoints;
    pub const _VulkanCallTrace = VulkanCallTrace;
    pub const _VulkanCapture = VulkanCapture;
    pub const _VulkanCaptureState = VulkanCaptureState;
    pub const _VulkanCommandAdmission = VulkanCommandAdmission;
    pub const _VulkanCommandRejectReason = VulkanCommandRejectReason;
    pub const _VulkanCreateLedgerEntry = VulkanCreateLedgerEntry;
    pub const _VulkanFenceWatch = VulkanFenceWatch;
    pub const _VulkanLoaderCandidates = VulkanLoaderCandidates;
    pub const _VulkanLookupMiss = VulkanLookupMiss;
    pub const _VulkanMemoryAllocation = VulkanMemoryAllocation;
    pub const _VulkanPresenterStage = VulkanPresenterStage;
    pub const _VulkanRefusalLedger = VulkanRefusalLedger;
    pub const _VulkanResource = VulkanResource;
    pub const _VulkanResourceKind = VulkanResourceKind;
    pub const _WriteKind = WriteKind;
    pub const _abi = abi;
    pub const _appendVulkanLayerPath = appendVulkanLayerPath;
    pub const _application_framework = application_framework;
    pub const _applyMoltenVKRuntimeDefaults = applyMoltenVKRuntimeDefaults;
    pub const _async_vulkan_command = async_vulkan_command;
    pub const _bridge_device_capabilities = bridge_device_capabilities;
    pub const _builtin = builtin;
    pub const _campaignDiagnosticFrame = campaignDiagnosticFrame;
    pub const _canonicalVulkanCommand = canonicalVulkanCommand;
    pub const _captureLayerManifestIn = captureLayerManifestIn;
    pub const _captureRunDirectory = captureRunDirectory;
    pub const _capture_plan = capture_plan;
    pub const _copyTerminated = copyTerminated;
    pub const _coreFeatureEnabled = coreFeatureEnabled;
    pub const _createHandle = createHandle;
    pub const _device_extensions = device_extensions;
    pub const _device_loss_diagnostics = device_loss_diagnostics;
    pub const _dlclose = dlclose;
    pub const _dlerror = dlerror;
    pub const _dlopen = dlopen;
    pub const _dlsym = dlsym;
    pub const _driver_identity = driver_identity;
    pub const _enumerateDeviceExtensions = enumerateDeviceExtensions;
    pub const _enumerateEmpty = enumerateEmpty;
    pub const _enumerateHandle = enumerateHandle;
    pub const _enumerateInstanceExtensionsSynthetic = enumerateInstanceExtensionsSynthetic;
    pub const _enumerateNoLayerExtensions = enumerateNoLayerExtensions;
    pub const _enumerateSurfaceFormats = enumerateSurfaceFormats;
    pub const _enumerateSurfacePresentModes = enumerateSurfacePresentModes;
    pub const _exportedOrNone = exportedOrNone;
    pub const _extension_names = extension_names;
    pub const _featureChainBoolAt = featureChainBoolAt;
    pub const _featureChainBoolCount = featureChainBoolCount;
    pub const _featureChainKind = featureChainKind;
    pub const _featureChainNext = featureChainNext;
    pub const _featureChainSType = featureChainSType;
    pub const _featureChainSize = featureChainSize;
    pub const _feature_chain_max = feature_chain_max;
    pub const _feature_chain_node_bytes = feature_chain_node_bytes;
    pub const _findCaptureLayerDirectory = findCaptureLayerDirectory;
    pub const _forwardedVulkanCommandIndex = forwardedVulkanCommandIndex;
    pub const _forwarded_vulkan_commands = forwarded_vulkan_commands;
    pub const _frame_capture = frame_capture;
    pub const _frame_content = frame_content;
    pub const _fsiCanCoalesceSegments = fsiCanCoalesceSegments;
    pub const _fsiCommandClass = fsiCommandClass;
    pub const _fsiFenceNow = fsiFenceNow;
    pub const _fsiFenceReset = fsiFenceReset;
    pub const _fsiFenceWait = fsiFenceWait;
    pub const _fsiGuestFeatureRequest = fsiGuestFeatureRequest;
    pub const _fsiWatcherReport = fsiWatcherReport;
    pub const _fsi_block_reason_count = fsi_block_reason_count;
    pub const _fsi_chain = fsi_chain;
    pub const _fsi_command_buffer_directory_capacity = fsi_command_buffer_directory_capacity;
    pub const _fsi_contract = fsi_contract;
    pub const _fsi_diagnostics = fsi_diagnostics;
    pub const _fsi_draw_commands = fsi_draw_commands;
    pub const _fsi_neutral_commands = fsi_neutral_commands;
    pub const _fsi_rasterization = fsi_rasterization;
    pub const _fsi_recorded_commands = fsi_recorded_commands;
    pub const _fsi_recording_capacity = fsi_recording_capacity;
    pub const _fsi_render_pass_capacity = fsi_render_pass_capacity;
    pub const _fsi_segment_command_capacity = fsi_segment_command_capacity;
    pub const _fsi_timing = fsi_timing;
    pub const _gpu_vulkan = gpu_vulkan;
    pub const _guestRangeAvailable = guestRangeAvailable;
    pub const _guestSymbolIndexFromToken = guestSymbolIndexFromToken;
    pub const _guestSymbolKind = guestSymbolKind;
    pub const _guestSymbolLookupCacheIndex = guestSymbolLookupCacheIndex;
    pub const _guest_context = guest_context;
    pub const _guest_instance_extension_aliases = guest_instance_extension_aliases;
    pub const _guest_memory_geometry = guest_memory_geometry;
    pub const _guest_sleep = guest_sleep;
    pub const _hostLoaderListsCaptureLayer = hostLoaderListsCaptureLayer;
    pub const _imageReadbackAugmentable = imageReadbackAugmentable;
    pub const _instance_extensions = instance_extensions;
    pub const _isForwardableVulkanSymbol = isForwardableVulkanSymbol;
    pub const _isVulkanLoaderPath = isVulkanLoaderPath;
    pub const _isXeniaFrameworkSymbol = isXeniaFrameworkSymbol;
    pub const _lastDlError = lastDlError;
    pub const _libraryMatches = libraryMatches;
    pub const _linkBridgeCapabilityChain = linkBridgeCapabilityChain;
    pub const _linkFeatureChain = linkFeatureChain;
    pub const _linkPropertyChain = linkPropertyChain;
    pub const _machoCapturePrint = machoCapturePrint;
    pub const _macos_host_contract = macos_host_contract;
    pub const _marshal = marshal;
    pub const _moltenvk_runtime_defaults = moltenvk_runtime_defaults;
    pub const _moltenvk_runtime_defaults_applied = &moltenvk_runtime_defaults_applied;
    pub const _native_texture = native_texture;
    pub const _normalizeMachOSymbol = normalizeMachOSymbol;
    pub const _nulTerminate = nulTerminate;
    pub const _physicalDeviceGuestHandle = physicalDeviceGuestHandle;
    pub const _ppc_host_symbols = ppc_host_symbols;
    pub const _ppc_runtime = ppc_runtime;
    pub const _prepareVulkanCapture = prepareVulkanCapture;
    pub const _presentDiagnosticMetalFrame = presentDiagnosticMetalFrame;
    pub const _present_pacing = present_pacing;
    pub const _propertyChainKind = propertyChainKind;
    pub const _propertyChainNode = propertyChainNode;
    pub const _propertyChainSize = propertyChainSize;
    pub const _property_chain_max = property_chain_max;
    pub const _publishVulkanDispatchableHandle = publishVulkanDispatchableHandle;
    pub const _queue_api_gate = queue_api_gate;
    pub const _rangeContains = rangeContains;
    pub const _readGuestApplicationInfo = readGuestApplicationInfo;
    pub const _rectExpansionBuiltinIndexBuffer = rectExpansionBuiltinIndexBuffer;
    pub const _registerOpaqueHandle = registerOpaqueHandle;
    pub const _render_diagnostic_frames = render_diagnostic_frames;
    pub const _resolvedPresentResult = resolvedPresentResult;
    pub const _rosette_gpu = rosette_gpu;
    pub const _setCaptureDefault = setCaptureDefault;
    pub const _setFeatureChainHeader = setFeatureChainHeader;
    pub const _setenv = setenv;
    pub const _shouldForceContentPixelProbe = shouldForceContentPixelProbe;
    pub const _sparseVulkanSuccessLog = sparseVulkanSuccessLog;
    pub const _specFor = specFor;
    pub const _specs = specs;
    pub const _spliceBridgeCapabilityChain = spliceBridgeCapabilityChain;
    pub const _std = std;
    pub const _surface_path_ledger = surface_path_ledger;
    pub const _syntheticExtensionProperties = syntheticExtensionProperties;
    pub const _tier_consistency = tier_consistency;
    pub const _transport_timing = transport_timing;
    pub const _vkErrorInitializationFailed = vkErrorInitializationFailed;
    pub const _vkErrorInitializationFailedSigned = vkErrorInitializationFailedSigned;
    pub const _vkErrorOutOfHostMemory = vkErrorOutOfHostMemory;
    pub const _vkErrorOutOfHostMemorySigned = vkErrorOutOfHostMemorySigned;
    pub const _vulkanDispatchTraceEnabled = vulkanDispatchTraceEnabled;
    pub const _forwarder_pipeline_lookup = forwarder_pipeline_lookup;
    pub const _vulkanLoaderCandidates = vulkanLoaderCandidates;
    pub const _vulkanNameHash = vulkanNameHash;
    pub const _vulkan_capture = &vulkan_capture;
    pub const _vulkan_capture_checked = &vulkan_capture_checked;
    pub const _writeApiVersion = writeApiVersion;
    pub const _writeBoolResult = writeBoolResult;
    pub const _writeCStringField = writeCStringField;
    pub const _writeExtensionPropertiesArray = writeExtensionPropertiesArray;
    pub const _writeF32 = writeF32;
    pub const _writeFormatProperties = writeFormatProperties;
    pub const _writeGuestBytes = writeGuestBytes;
    pub const _writeI32 = writeI32;
    pub const _writeMemoryProperties = writeMemoryProperties;
    pub const _writeMemoryProperties2 = writeMemoryProperties2;
    pub const _writeMemoryRequirements = writeMemoryRequirements;
    pub const _writePhysicalDeviceDriverProperties = writePhysicalDeviceDriverProperties;
    pub const _writePhysicalDeviceFeatures = writePhysicalDeviceFeatures;
    pub const _writePhysicalDeviceFeatures2 = writePhysicalDeviceFeatures2;
    pub const _writePhysicalDeviceFloatControlsProperties = writePhysicalDeviceFloatControlsProperties;
    pub const _writePhysicalDeviceLimits = writePhysicalDeviceLimits;
    pub const _writePhysicalDeviceProperties = writePhysicalDeviceProperties;
    pub const _writePhysicalDeviceProperties2 = writePhysicalDeviceProperties2;
    pub const _writePhysicalDevicePropertiesPNext = writePhysicalDevicePropertiesPNext;
    pub const _writeQueueFamilies = writeQueueFamilies;
    pub const _writeSurfaceCapabilities = writeSurfaceCapabilities;
    pub const _writeU32 = writeU32;
    pub const _writeU64 = writeU64;
    pub const _xenia_heap_range = xenia_heap_range;
    pub const _xenia_host_gpu_callback_contract = xenia_host_gpu_callback_contract;
    pub const _xenia_launch_assist_contract = xenia_launch_assist_contract;
    pub const _CommandPassTarget = Forwarder.CommandPassTarget;
    pub const _NativeComputePipelineCall = Forwarder.NativeComputePipelineCall;
    pub const _NativeGraphicsPipelineCall = Forwarder.NativeGraphicsPipelineCall;
    pub const _PipelineMarshalFailure = Forwarder.PipelineMarshalFailure;
    pub const _QueueApiWait = Forwarder.QueueApiWait;
    pub const _RectExpansion = Forwarder.RectExpansion;
    pub const _RobustHardening = Forwarder.RobustHardening;
    pub const _SpecializationScratch = Forwarder.SpecializationScratch;
};

const forwarder_impl_loader_symbols = @import("forwarder/loader_symbols.zig");
const forwarder_impl_vulkan_objects = @import("forwarder/vulkan_objects.zig");
const forwarder_impl_command_tracking = @import("forwarder/command_tracking.zig");
const forwarder_impl_fsi_submission = @import("forwarder/fsi_submission.zig");
const forwarder_impl_render_resources = @import("forwarder/render_resources.zig");
const forwarder_impl_graphics_observation = @import("forwarder/graphics_observation.zig");
const forwarder_impl_present_routing = @import("forwarder/present_routing.zig");
const forwarder_impl_texture_capture = @import("forwarder/texture_capture.zig");
const forwarder_impl_runtime_dispatch = @import("forwarder/runtime_dispatch.zig");
pub const forwarder_pipeline_lookup = @import("forwarder/pipeline_lookup.zig");

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
    if (std.mem.eql(u8, symbol, "vkGetPhysicalDeviceWin32PresentationSupportKHR")) return .get_physical_device_win32_presentation_support;
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
    if (std.mem.eql(u8, symbol, "vkResetQueryPool") or std.mem.eql(u8, symbol, "vkResetQueryPoolEXT")) return .reset_query_pool;
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
    if (std.mem.eql(u8, symbol, "rosette_xenia_heap_allocator_abi_version")) return .rosette_heap_allocator_abi_version;
    if (std.mem.eql(u8, symbol, "rosette_xenia_heap_select")) return .rosette_heap_select;
    if (std.mem.eql(u8, symbol, "rosette_ppc_host_available")) return .rosette_ppc_host_available;
    if (std.mem.eql(u8, symbol, "rosette_ppc_host_identity")) return .rosette_ppc_host_identity;
    if (std.mem.eql(u8, symbol, "rosette_ppc_bind_context")) return .rosette_ppc_bind_context;
    if (std.mem.eql(u8, symbol, "rosette_ppc_release_context")) return .rosette_ppc_release_context;
    if (std.mem.eql(u8, symbol, "rosette_ppc_set_recompiler_enabled")) return .rosette_ppc_set_recompiler_enabled;
    if (std.mem.eql(u8, symbol, "rosette_ppc_recompiler_stats")) return .rosette_ppc_recompiler_stats;
    if (std.mem.eql(u8, symbol, "rosette_ppc_invalidate_range")) return .rosette_ppc_invalidate_range;
    if (std.mem.eql(u8, symbol, "rosette_ppc_execute")) return .rosette_ppc_execute;
    if (std.mem.eql(u8, symbol, "rosette_xenia_launch_assist_abi_version")) return .rosette_xenia_launch_assist_abi_version;
    if (std.mem.eql(u8, symbol, "rosette_xenia_launch_assist_schema_version")) return .rosette_xenia_launch_assist_schema_version;
    if (std.mem.eql(u8, symbol, "rosette_xenia_launch_assist_query")) return .rosette_xenia_launch_assist_query;
    if (std.mem.eql(u8, symbol, "rosette_xenia_launch_assist_report")) return .rosette_xenia_launch_assist_report;
    if (std.mem.eql(u8, symbol, "rosette_xenia_host_gpu_callback_abi_version")) return .rosette_xenia_host_gpu_callback_abi_version;
    if (std.mem.eql(u8, symbol, "rosette_xenia_host_gpu_callback_schema_version")) return .rosette_xenia_host_gpu_callback_schema_version;
    if (std.mem.eql(u8, symbol, "rosette_xenia_host_gpu_callback_query")) return .rosette_xenia_host_gpu_callback_query;
    if (std.mem.eql(u8, symbol, "rosette_xenia_host_gpu_callback_report")) return .rosette_xenia_host_gpu_callback_report;
    if (std.mem.eql(u8, symbol, "vkResetDescriptorPool")) return .reset_descriptor_pool;
    if (std.mem.eql(u8, symbol, "vkBindImageMemory")) return .bind_image_memory;
    if (std.mem.eql(u8, symbol, "vkBindBufferMemory")) return .bind_buffer_memory;
    if (std.mem.startsWith(u8, symbol, "vkCmd")) return .command;
    if (std.mem.eql(u8, symbol, "vkUpdateDescriptorSets")) return .update_descriptor_sets;
    if (std.mem.eql(u8, symbol, "vkUpdateDescriptorSetWithTemplate")) return .update_descriptor_set_with_template;
    if (std.mem.eql(u8, symbol, "vkUnmapMemory")) return .unmap_memory;
    return .@"opaque";
}

/// Whether the Vulkan loader bridge has an explicit dispatch contract for a
/// symbol.  Windows PE imports use this query before handing a name across
/// the Microsoft-x64/SysV adapter; an opaque name must remain visible to the
/// caller instead of being mistaken for a successful native call.
fn canonicalVulkanCommand(name: []const u8) []const u8 {
    // EXT spellings share the core ABI; the function table already resolves
    // either spelling, so dispatch must use the same alias contract.
    if (std.mem.eql(u8, name, "vkCmdSetDepthTestEnableEXT")) return "vkCmdSetDepthTestEnable";
    if (std.mem.eql(u8, name, "vkCmdSetDepthWriteEnableEXT")) return "vkCmdSetDepthWriteEnable";
    if (std.mem.eql(u8, name, "vkCmdSetDepthCompareOpEXT")) return "vkCmdSetDepthCompareOp";
    if (std.mem.eql(u8, name, "vkCmdSetStencilTestEnableEXT")) return "vkCmdSetStencilTestEnable";
    if (std.mem.eql(u8, name, "vkCmdSetStencilOpEXT")) return "vkCmdSetStencilOp";
    if (std.mem.eql(u8, name, "vkCmdSetPrimitiveRestartEnableEXT")) return "vkCmdSetPrimitiveRestartEnable";
    return name;
}

const forwarded_vulkan_commands = [_][]const u8{
    "vkCmdBeginConditionalRenderingEXT",
    "vkCmdBeginQuery",
    "vkCmdBeginRenderPass",
    "vkCmdBeginRenderPass2",
    "vkCmdBeginRenderPass2KHR",
    "vkCmdBeginRendering",
    "vkCmdBeginRenderingKHR",
    "vkCmdBindDescriptorSets",
    "vkCmdBindIndexBuffer",
    "vkCmdBindPipeline",
    "vkCmdBindVertexBuffers",
    "vkCmdBlitImage",
    "vkCmdClearAttachments",
    "vkCmdClearColorImage",
    "vkCmdClearDepthStencilImage",
    "vkCmdCopyBuffer",
    "vkCmdCopyBufferToImage",
    "vkCmdCopyImage",
    "vkCmdCopyImageToBuffer",
    "vkCmdCopyQueryPoolResults",
    "vkCmdDispatch",
    "vkCmdDispatchBase",
    "vkCmdDispatchIndirect",
    "vkCmdDraw",
    "vkCmdDrawIndexed",
    "vkCmdDrawIndexedIndirect",
    "vkCmdDrawIndexedIndirectCount",
    "vkCmdDrawIndirect",
    "vkCmdDrawIndirectCount",
    "vkCmdEndConditionalRenderingEXT",
    "vkCmdEndQuery",
    "vkCmdEndRenderPass",
    "vkCmdEndRenderPass2",
    "vkCmdEndRenderPass2KHR",
    "vkCmdEndRendering",
    "vkCmdEndRenderingKHR",
    "vkCmdExecuteCommands",
    "vkCmdFillBuffer",
    "vkCmdNextSubpass",
    "vkCmdNextSubpass2",
    "vkCmdNextSubpass2KHR",
    "vkCmdPipelineBarrier",
    "vkCmdPipelineBarrier2",
    "vkCmdPipelineBarrier2KHR",
    "vkCmdPushConstants",
    "vkCmdPushDescriptorSetKHR",
    "vkCmdResetQueryPool",
    "vkCmdResolveImage",
    "vkCmdSetBlendConstants",
    "vkCmdSetDepthBias",
    "vkCmdSetDepthBounds",
    "vkCmdSetDepthCompareOp",
    "vkCmdSetDepthTestEnable",
    "vkCmdSetDepthWriteEnable",
    "vkCmdSetPrimitiveRestartEnable",
    "vkCmdSetScissor",
    "vkCmdSetStencilCompareMask",
    "vkCmdSetStencilOp",
    "vkCmdSetStencilReference",
    "vkCmdSetStencilTestEnable",
    "vkCmdSetStencilWriteMask",
    "vkCmdSetViewport",
    "vkCmdUpdateBuffer",
};

fn forwardedVulkanCommandIndex(name: []const u8) ?usize {
    const indices = comptime blk: {
        var entries: [forwarded_vulkan_commands.len]struct { []const u8, usize } = undefined;
        for (forwarded_vulkan_commands, 0..) |command, index| entries[index] = .{ command, index };
        break :blk std.StaticStringMap(usize).initComptime(entries);
    };
    return indices.get(name);
}

fn guestSymbolIndexFromToken(token: u64) ?usize {
    if (token < GUEST_SYMBOL_THUNK_BASE) return null;
    const offset = token - GUEST_SYMBOL_THUNK_BASE;
    if (offset == 0 or offset % 16 != 1) return null;
    const index: usize = @intCast((offset - 1) / 16);
    if (index >= MAX_GUEST_SYMBOLS) return null;
    return index;
}

pub fn isForwardableVulkanSymbol(symbol: []const u8) bool {
    if (!std.mem.startsWith(u8, symbol, "vk")) return false;
    if (std.mem.startsWith(u8, symbol, "vkCmd")) {
        const canonical = canonicalVulkanCommand(symbol);
        return forwardedVulkanCommandIndex(canonical) != null;
    }
    return guestSymbolKind(symbol) != .@"opaque";
}

fn isXeniaFrameworkSymbol(kind: GuestSymbolKind) bool {
    return switch (kind) {
        .rosette_xenia_launch_assist_abi_version, .rosette_xenia_launch_assist_schema_version, .rosette_xenia_launch_assist_query, .rosette_xenia_launch_assist_report, .rosette_xenia_host_gpu_callback_abi_version, .rosette_xenia_host_gpu_callback_schema_version, .rosette_xenia_host_gpu_callback_query, .rosette_xenia_host_gpu_callback_report => true,
        else => false,
    };
}

const extension_names = instance_extensions.synthetic_instance_names;
const device_extensions = instance_extensions.synthetic_device_names;
const guest_instance_extension_aliases = instance_extensions.guest_aliases;

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
    return instance_extensions.writeProperties(state, count_address, output_address, available);
}

/// A non-null pLayerName asks for the extensions a specific layer adds.  The
/// bridge enumerates no layers at all, so no layer name can be one the guest
/// enabled, and the specification's answer for that is a hard error rather
/// than an empty list — an empty list would claim the layer exists and simply
/// contributes nothing.
fn enumerateNoLayerExtensions(state: anytype, count_address: u64) u64 {
    return instance_extensions.enumerateNoLayer(state, count_address);
}

fn syntheticExtensionProperties(comptime names: []const []const u8) [names.len]abi.ExtensionProperties {
    return instance_extensions.syntheticProperties(names);
}

fn enumerateInstanceExtensionsSynthetic(state: anytype) u64 {
    return instance_extensions.enumerateSyntheticInstance(state);
}

/// Whether a Vulkan output parameter names reachable guest memory, asked
/// through the read-only resolver so the answer never depends on a mutable
/// view being handed out.
fn guestRangeAvailable(state: anytype, address: u64, length: u64) bool {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "guestMemoryConst")) {
        return state.guestMemoryConst(address, length) != null;
    }
    return state.guestMemory(address, length) != null;
}

/// Copy a whole output structure into guest memory through the state's
/// ordered writer when it has one: that is how `ElfState` publishes bytes
/// while guest threads run in parallel, and it moves an executable range's
/// generation after the bytes. A state without it takes a raw view.
///
/// The physical-device properties and features go through here. On
/// 2026-09-30 their raw views were refused in parallel mode, so Xenia read
/// an empty adapter name and no independentBlend, rejected the only GPU,
/// and faulted on a null device in `VulkanCommandProcessor::SetupContext`.
fn writeGuestBytes(state: anytype, address: u64, bytes: []const u8) bool {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "copyToGuest")) return state.copyToGuest(address, bytes);
    const destination = state.guestMemory(address, bytes.len) orelse return false;
    @memcpy(destination, bytes);
    return true;
}

fn enumerateEmpty(state: anytype, count_address: u64) u64 {
    if (count_address == 0 or !guestRangeAvailable(state, count_address, 4)) return vkErrorInitializationFailed();
    state.write32(count_address, 0);
    return 0;
}

fn writeApiVersion(state: anytype, output: u64) u64 {
    if (output == 0 or !guestRangeAvailable(state, output, 4)) return vkErrorInitializationFailed();
    state.write32(output, 0x0040_2000); // Vulkan 1.2.0
    return 0;
}

fn enumerateDeviceExtensions(state: anytype) u64 {
    return instance_extensions.enumerateSyntheticDevice(state);
}

fn coreFeatureEnabled(features: []const u8, offset: usize) bool {
    if (offset > features.len or features.len - offset < 4) return false;
    return std.mem.readInt(u32, features[offset..][0..4], .little) != 0;
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
    const count_address = guest_context.registers(state).rsi;
    if (state.guestMemory(count_address, 4) == null) return;
    if (guest_context.registers(state).rdx == 0) {
        state.write32(count_address, 1);
        return;
    }
    if (state.read32(count_address) == 0) return;
    const bytes = state.guestMemory(guest_context.registers(state).rdx, 24) orelse return;
    @memset(bytes, 0);
    // The synthetic adapter has no sparse-binding implementation. Do not
    // advertise VK_QUEUE_SPARSE_BINDING_BIT here: Xenia will otherwise select
    // sparse memory paths that this fallback cannot honor.
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
    if (state.guestMemory(guest_context.registers(state).rdx, 4) == null) return vkErrorInitializationFailed();
    if (guest_context.registers(state).rcx == 0) {
        state.write32(guest_context.registers(state).rdx, 1);
        return 0;
    }
    const bytes = state.guestMemory(guest_context.registers(state).rcx, 8) orelse return vkErrorInitializationFailed();
    std.mem.writeInt(u32, bytes[0..4], 44, .little); // VK_FORMAT_B8G8R8A8_UNORM
    std.mem.writeInt(u32, bytes[4..8], 0, .little); // SRGB nonlinear
    state.write32(guest_context.registers(state).rdx, 1);
    return 0;
}

fn enumerateSurfacePresentModes(state: anytype) u64 {
    if (state.guestMemory(guest_context.registers(state).rdx, 4) == null) return vkErrorInitializationFailed();
    if (guest_context.registers(state).rcx != 0 and state.read32(guest_context.registers(state).rdx) != 0) state.write32(guest_context.registers(state).rcx, 2); // FIFO
    state.write32(guest_context.registers(state).rdx, 1);
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
    if (output == 0 or !guestRangeAvailable(state, output, 8)) return vkErrorInitializationFailed();
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
    if (count_address == 0 or !guestRangeAvailable(state, count_address, 4)) return vkErrorInitializationFailed();
    if (output == 0) {
        state.write32(count_address, 1);
        return 0;
    }
    if (state.read32(count_address) == 0 or !guestRangeAvailable(state, output, 8)) return 5;
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
    if (!guestRangeAvailable(state, output, 8)) return false;
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

fn vkErrorOutOfHostMemorySigned() i32 {
    return -1;
}

fn vkErrorOutOfHostMemory() u64 {
    return @as(u32, @bitCast(@as(i32, -1)));
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

test {
    _ = @import("forwarder/tests.zig");
    _ = forwarder_pipeline_lookup;
}
