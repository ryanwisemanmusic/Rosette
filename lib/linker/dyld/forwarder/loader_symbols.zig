// Split implementation for Forwarder; wrappers keep the public state API stable.
const process = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = process.__ForwarderInternals;
const Forwarder = process.Forwarder;
const FeatureChainScratch = __ForwarderInternals._FeatureChainScratch;
const FsiCommandBufferEntry = __ForwarderInternals._FsiCommandBufferEntry;
const FsiGuard = __ForwarderInternals._FsiGuard;
const GUEST_SYMBOL_THUNK_BASE = __ForwarderInternals._GUEST_SYMBOL_THUNK_BASE;
const MAX_GUEST_SYMBOLS = __ForwarderInternals._MAX_GUEST_SYMBOLS;
const PropertyChainScratch = __ForwarderInternals._PropertyChainScratch;
const RECT_EXPAND_COMMAND_STATES = __ForwarderInternals._RECT_EXPAND_COMMAND_STATES;
const RTLD_DEFAULT_HANDLE = __ForwarderInternals._RTLD_DEFAULT_HANDLE;
const RectExpandCommandState = __ForwarderInternals._RectExpandCommandState;
const SYNTHETIC_DEBUG_MESSENGER_HANDLE = __ForwarderInternals._SYNTHETIC_DEBUG_MESSENGER_HANDLE;
const TrackedGraphicsPipeline = __ForwarderInternals._TrackedGraphicsPipeline;
const TrackedPipelineLayout = __ForwarderInternals._TrackedPipelineLayout;
const VK_DYNAMIC_STATE_SCISSOR = __ForwarderInternals._VK_DYNAMIC_STATE_SCISSOR;
const VK_DYNAMIC_STATE_VIEWPORT = __ForwarderInternals._VK_DYNAMIC_STATE_VIEWPORT;
const VK_PHYSICAL_DEVICE_PROPERTIES_SIZE = __ForwarderInternals._VK_PHYSICAL_DEVICE_PROPERTIES_SIZE;
const VK_PIPELINE_BIND_POINT_GRAPHICS = __ForwarderInternals._VK_PIPELINE_BIND_POINT_GRAPHICS;
const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST = __ForwarderInternals._VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP = __ForwarderInternals._VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
const VK_SHADER_STAGE_VERTEX_BIT = __ForwarderInternals._VK_SHADER_STAGE_VERTEX_BIT;
const abi = __ForwarderInternals._abi;
const application_framework = __ForwarderInternals._application_framework;
const coreFeatureEnabled = __ForwarderInternals._coreFeatureEnabled;
const dlclose = __ForwarderInternals._dlclose;
const dlsym = __ForwarderInternals._dlsym;
const enumerateDeviceExtensions = __ForwarderInternals._enumerateDeviceExtensions;
const enumerateEmpty = __ForwarderInternals._enumerateEmpty;
const enumerateHandle = __ForwarderInternals._enumerateHandle;
const enumerateSurfaceFormats = __ForwarderInternals._enumerateSurfaceFormats;
const enumerateSurfacePresentModes = __ForwarderInternals._enumerateSurfacePresentModes;
const featureChainBoolAt = __ForwarderInternals._featureChainBoolAt;
const featureChainBoolCount = __ForwarderInternals._featureChainBoolCount;
const featureChainKind = __ForwarderInternals._featureChainKind;
const featureChainSType = __ForwarderInternals._featureChainSType;
const featureChainSize = __ForwarderInternals._featureChainSize;
const feature_chain_max = __ForwarderInternals._feature_chain_max;
const fsiCommandClass = __ForwarderInternals._fsiCommandClass;
const fsiGuestFeatureRequest = __ForwarderInternals._fsiGuestFeatureRequest;
const fsi_chain = __ForwarderInternals._fsi_chain;
const fsi_contract = __ForwarderInternals._fsi_contract;
const fsi_diagnostics = __ForwarderInternals._fsi_diagnostics;
const fsi_rasterization = __ForwarderInternals._fsi_rasterization;
const fsi_timing = __ForwarderInternals._fsi_timing;
const gpu_vulkan = __ForwarderInternals._gpu_vulkan;
const guestRangeAvailable = __ForwarderInternals._guestRangeAvailable;
const guestSymbolIndexFromToken = __ForwarderInternals._guestSymbolIndexFromToken;
const guestSymbolKind = __ForwarderInternals._guestSymbolKind;
const guestSymbolLookupCacheIndex = __ForwarderInternals._guestSymbolLookupCacheIndex;
const guest_context = __ForwarderInternals._guest_context;
const instance_extensions = __ForwarderInternals._instance_extensions;
const isForwardableVulkanSymbol = __ForwarderInternals._isForwardableVulkanSymbol;
const isXeniaFrameworkSymbol = __ForwarderInternals._isXeniaFrameworkSymbol;
const linkFeatureChain = __ForwarderInternals._linkFeatureChain;
const linkPropertyChain = __ForwarderInternals._linkPropertyChain;
const machoCapturePrint = __ForwarderInternals._machoCapturePrint;
const marshal = __ForwarderInternals._marshal;
const nulTerminate = __ForwarderInternals._nulTerminate;
const physicalDeviceGuestHandle = __ForwarderInternals._physicalDeviceGuestHandle;
const ppc_host_symbols = __ForwarderInternals._ppc_host_symbols;
const ppc_runtime = __ForwarderInternals._ppc_runtime;
const propertyChainKind = __ForwarderInternals._propertyChainKind;
const propertyChainNode = __ForwarderInternals._propertyChainNode;
const propertyChainSize = __ForwarderInternals._propertyChainSize;
const property_chain_max = __ForwarderInternals._property_chain_max;
const setFeatureChainHeader = __ForwarderInternals._setFeatureChainHeader;
const std = __ForwarderInternals._std;
const vkErrorInitializationFailed = __ForwarderInternals._vkErrorInitializationFailed;
const vulkanDispatchTraceEnabled = __ForwarderInternals._vulkanDispatchTraceEnabled;
const vulkanNameHash = __ForwarderInternals._vulkanNameHash;
const writeApiVersion = __ForwarderInternals._writeApiVersion;
const writeBoolResult = __ForwarderInternals._writeBoolResult;
const writeFormatProperties = __ForwarderInternals._writeFormatProperties;
const writeGuestBytes = __ForwarderInternals._writeGuestBytes;
const writeMemoryProperties = __ForwarderInternals._writeMemoryProperties;
const writeMemoryProperties2 = __ForwarderInternals._writeMemoryProperties2;
const writePhysicalDeviceFeatures = __ForwarderInternals._writePhysicalDeviceFeatures;
const writePhysicalDeviceFeatures2 = __ForwarderInternals._writePhysicalDeviceFeatures2;
const writePhysicalDeviceProperties = __ForwarderInternals._writePhysicalDeviceProperties;
const writePhysicalDeviceProperties2 = __ForwarderInternals._writePhysicalDeviceProperties2;
const writePhysicalDevicePropertiesPNext = __ForwarderInternals._writePhysicalDevicePropertiesPNext;
const writeQueueFamilies = __ForwarderInternals._writeQueueFamilies;
const writeSurfaceCapabilities = __ForwarderInternals._writeSurfaceCapabilities;
const host_page_range_selection_abi = __ForwarderInternals._host_page_range_selection_abi;
const xenia_host_gpu_callback_contract = __ForwarderInternals._xenia_host_gpu_callback_contract;
const console_launch_assist_contract = __ForwarderInternals._console_launch_assist_contract;
const PipelineMarshalFailure = __ForwarderInternals._PipelineMarshalFailure;
const RectExpansion = __ForwarderInternals._RectExpansion;
const RobustHardening = __ForwarderInternals._RobustHardening;
const acquireNextImage = Forwarder.acquireNextImage;
const allocateVulkanMemory = Forwarder.allocateVulkanMemory;
const allocateVulkanObjects = Forwarder.allocateVulkanObjects;
const beginCommandBuffer = Forwarder.beginCommandBuffer;
const bindResourceMemory = Forwarder.bindResourceMemory;
const bindResourcesMemory2 = Forwarder.bindResourcesMemory2;
const callNativeVulkanCommand = Forwarder.callNativeVulkanCommand;
const commandPassTarget = Forwarder.commandPassTarget;
const createMetalSurface = Forwarder.createMetalSurface;
const createMultipleVulkanObjects = Forwarder.createMultipleVulkanObjects;
const createSwapchain = Forwarder.createSwapchain;
const createVulkanObject = Forwarder.createVulkanObject;
const destroyNativeSurface = Forwarder.destroyNativeSurface;
const destroyNativeVulkanObjects = Forwarder.destroyNativeVulkanObjects;
const destroyRealDevice = Forwarder.destroyRealDevice;
const destroyRealSurface = Forwarder.destroyRealSurface;
const destroyRealSwapchain = Forwarder.destroyRealSwapchain;
const destroyVulkanObject = Forwarder.destroyVulkanObject;
const deviceWaitIdle = Forwarder.deviceWaitIdle;
const drainAsyncVulkanCommands = Forwarder.drainAsyncVulkanCommands;
const drainAsyncVulkanCommandsIfPending = Forwarder.drainAsyncVulkanCommandsIfPending;
const dumpVulkanCreateLedger = Forwarder.dumpVulkanCreateLedger;
const endCommandBuffer = Forwarder.endCommandBuffer;
const ensureRealDevice = Forwarder.ensureRealDevice;
const ensureRealInstance = Forwarder.ensureRealInstance;
const enumerateInstanceExtensions = Forwarder.enumerateInstanceExtensions;
const enumerateRealSurfaceFormats = Forwarder.enumerateRealSurfaceFormats;
const enumerateRealSurfacePresentModes = Forwarder.enumerateRealSurfacePresentModes;
const enumerateSwapchainImages = Forwarder.enumerateSwapchainImages;
const flushMappedMemoryRanges = Forwarder.flushMappedMemoryRanges;
const forwardVulkanCommand = Forwarder.forwardVulkanCommand;
const getFenceStatus = Forwarder.getFenceStatus;
const getPipelineCacheData = Forwarder.getPipelineCacheData;
const getQueryPoolResults = Forwarder.getQueryPoolResults;
const getSemaphoreCounterValue = Forwarder.getSemaphoreCounterValue;
const guestLibraryEntry = Forwarder.guestLibraryEntry;
const hostDeviceExtensionAvailable = Forwarder.hostDeviceExtensionAvailable;
const hostDeviceExtensions = Forwarder.hostDeviceExtensions;
const invalidateMappedMemoryRanges = Forwarder.invalidateMappedMemoryRanges;
const mapVulkanMemory = Forwarder.mapVulkanMemory;
const mutableCommandTargets = Forwarder.mutableCommandTargets;
const noteRealVulkanResult = Forwarder.noteRealVulkanResult;
const queryHostDeviceExtensions = Forwarder.queryHostDeviceExtensions;
const queueBindSparse = Forwarder.queueBindSparse;
const queuePresent = Forwarder.queuePresent;
const queueSubmit = Forwarder.queueSubmit;
const queueSubmit2 = Forwarder.queueSubmit2;
const queueWaitIdle = Forwarder.queueWaitIdle;
const recordVulkanCall = Forwarder.recordVulkanCall;
const refreshPresentChainWindow = Forwarder.refreshPresentChainWindow;
const releaseNativeMemoryAliases = Forwarder.releaseNativeMemoryAliases;
const reportPresentChain = Forwarder.reportPresentChain;
const reportVulkanRefusals = Forwarder.reportVulkanRefusals;
const resetCommandBuffer = Forwarder.resetCommandBuffer;
const resetCommandPool = Forwarder.resetCommandPool;
const resetDescriptorPool = Forwarder.resetDescriptorPool;
const resetFences = Forwarder.resetFences;
const resetQueryPool = Forwarder.resetQueryPool;
const signalSemaphore = Forwarder.signalSemaphore;
const stopAsyncVulkanCommandWorker = Forwarder.stopAsyncVulkanCommandWorker;
const unmapMemory = Forwarder.unmapMemory;
const updateDescriptorSetWithTemplate = Forwarder.updateDescriptorSetWithTemplate;
const updateDescriptorSets = Forwarder.updateDescriptorSets;
const vulkanCreateLedgerHasAnomaly = Forwarder.vulkanCreateLedgerHasAnomaly;
const waitForFences = Forwarder.waitForFences;
const waitSemaphores = Forwarder.waitSemaphores;
const writeDeviceBufferMemoryRequirements = Forwarder.writeDeviceBufferMemoryRequirements;
const writeDeviceImageMemoryRequirements = Forwarder.writeDeviceImageMemoryRequirements;
const writeDeviceQueue = Forwarder.writeDeviceQueue;
const writeRealSurfaceCapabilities = Forwarder.writeRealSurfaceCapabilities;
const writeRealSurfaceSupport = Forwarder.writeRealSurfaceSupport;
const writeResourceMemoryRequirements = Forwarder.writeResourceMemoryRequirements;
const writeResourceMemoryRequirements2 = Forwarder.writeResourceMemoryRequirements2;

pub fn deinit(self: anytype) void {
    if (self.fsi_evidence_io.writer) |writer| {
        writer.stop();
        writer.report();
        writer.destroy();
        self.fsi_evidence_io.writer = null;
    }
    self.stopAsyncVulkanCommandWorker();
    // A guest-side all-or-nothing resource warning can otherwise be
    // reported with no per-create evidence when the run still presents
    // frames (the normal failure snapshot is only opened for a missing
    // present). Emit the bounded ledger automatically only when a create
    // contract actually lost an object; healthy runs stay quiet.
    if (self.vulkanCreateLedgerHasAnomaly()) {
        machoCapturePrint("macho-processor: VULKAN CREATE ANOMALY: one or more guest create calls did not publish a usable native object; dumping the bounded create ledger\n", .{});
        self.dumpVulkanCreateLedger();
    }
    self.destroyNativeVulkanObjects();
    self.vulkan_scratch.deinit();
    self.ppc_guest_bridge.deinit();
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

pub fn lookupGuest(self: anytype, library_token: u64, symbol: []const u8) u64 {
    if (library_token == RTLD_DEFAULT_HANDLE) {
        const kind = guestSymbolKind(symbol);
        const is_heap = kind == .rosette_heap_allocator_abi_version or kind == .rosette_heap_select;
        const is_ppc = ppc_host_symbols.Symbol.fromName(symbol) != null;
        const is_xenia_framework = isXeniaFrameworkSymbol(kind);
        if (!is_heap and !is_ppc and !is_xenia_framework) {
            return 0;
        }
        const token = self.allocateGuestSymbol(library_token, symbol);
        machoCapturePrint(
            "macho-processor: Rosette host ABI lookup: {s} -> 0x{x}\n",
            .{ symbol, token },
        );
        return token;
    }
    const entry = self.guestLibraryEntry(library_token) orelse return 0;
    if (entry.virtual_vulkan) {
        if (self.optionalVulkanProcUnavailable(symbol)) {
            // The guest asking for an entry point the device does not
            // have is the fact that separates a settled absence from a
            // wall. A real loader answers NULL here too, so this is
            // correct behaviour -- it is only worth recording.
            self.vulkan_absent_reached.note(symbol, "reported absent to the guest, as a real loader would");
            if (self.noteVulkanLoaderLookup(library_token, symbol, 0)) {
                machoCapturePrint(
                    "macho-processor: Vulkan guest loader lookup: {s} -> NULL (device capability not enabled)\n",
                    .{symbol},
                );
            }
            return 0;
        }
        const token = self.allocateGuestSymbol(library_token, symbol);
        if (self.noteVulkanLoaderLookup(library_token, symbol, token)) {
            machoCapturePrint(
                "macho-processor: Vulkan guest loader lookup: {s} -> 0x{x} ({s})\n",
                .{ symbol, token, @tagName(guestSymbolKind(symbol)) },
            );
        }
        return token;
    }
    const library = entry.handle orelse return 0;
    var symbol_buffer: [512]u8 = undefined;
    const symbol_z = nulTerminate(&symbol_buffer, symbol) orelse return 0;
    _ = dlsym(library, symbol_z) orelse return 0;
    return self.allocateGuestSymbol(library_token, symbol);
}

pub fn lookupVulkanProcGuest(self: anytype, library_token: u64, symbol: []const u8) u64 {
    const is_surface_proc = std.mem.eql(u8, symbol, "vkCreateMetalSurfaceEXT") or
        std.mem.eql(u8, symbol, "vkCreateWin32SurfaceKHR");
    if (self.guestLibraryEntry(library_token) == null) {
        if (is_surface_proc) self.vulkan_surface_path.noteProcLookup(false);
        return 0;
    }
    if (!isForwardableVulkanSymbol(symbol)) {
        if (is_surface_proc) self.vulkan_surface_path.noteProcLookup(false);
        return 0;
    }
    self.guest_proc_queries +|= 1;
    if (self.optionalVulkanProcUnavailable(symbol)) {
        if (is_surface_proc) self.vulkan_surface_path.noteProcLookup(false);
        self.vulkan_absent_reached.note(symbol, "reported absent to the guest, as a real loader would");
        machoCapturePrint(
            "macho-processor: Vulkan proc query #{d}: {s} -> NULL (device capability not enabled)\n",
            .{ self.guest_proc_queries, symbol },
        );
        return 0;
    }
    const token = self.allocateGuestSymbol(library_token, symbol);
    if (is_surface_proc) self.vulkan_surface_path.noteProcLookup(token != 0);
    if (self.guest_proc_queries == 1) {
        machoCapturePrint("macho-processor: BOOTUP MILESTONE: guest entered Vulkan library and queried first function '{s}' — GPU initialization beginning\n", .{symbol});
    }
    machoCapturePrint(
        "macho-processor: Vulkan proc query #{d}: {s} -> 0x{x} ({s})\n",
        .{ self.guest_proc_queries, symbol, token, @tagName(guestSymbolKind(symbol)) },
    );
    return token;
}

pub fn optionalVulkanProcUnavailable(self: anytype, symbol: []const u8) bool {
    if (!self.real_vulkan.hasDevice() or !self.real_vulkan.fn_ptrs.resolved) return false;
    if (std.mem.eql(u8, symbol, "vkCmdBeginConditionalRenderingEXT")) {
        return !self.real_vulkan.conditional_rendering_enabled or
            self.real_vulkan.fn_ptrs.cmd_begin_conditional_rendering == null;
    }
    if (std.mem.eql(u8, symbol, "vkCmdEndConditionalRenderingEXT")) {
        return !self.real_vulkan.conditional_rendering_enabled or
            self.real_vulkan.fn_ptrs.cmd_end_conditional_rendering == null;
    }

    if (std.mem.eql(u8, symbol, "vkCmdBeginRendering") or
        std.mem.eql(u8, symbol, "vkCmdBeginRenderingKHR"))
    {
        return !self.real_vulkan.dynamic_rendering_enabled or
            self.real_vulkan.fn_ptrs.cmd_begin_rendering == null;
    }
    if (std.mem.eql(u8, symbol, "vkCmdEndRendering") or
        std.mem.eql(u8, symbol, "vkCmdEndRenderingKHR"))
    {
        return !self.real_vulkan.dynamic_rendering_enabled or
            self.real_vulkan.fn_ptrs.cmd_end_rendering == null;
    }
    if (std.mem.eql(u8, symbol, "vkQueueSubmit2") or
        std.mem.eql(u8, symbol, "vkQueueSubmit2KHR") or
        std.mem.eql(u8, symbol, "vkCmdPipelineBarrier2") or
        std.mem.eql(u8, symbol, "vkCmdPipelineBarrier2KHR"))
    {
        return !self.real_vulkan.sync2_enabled or
            (std.mem.startsWith(u8, symbol, "vkQueue") and self.real_vulkan.fn_ptrs.queue_submit2 == null) or
            (std.mem.startsWith(u8, symbol, "vkCmd") and self.real_vulkan.fn_ptrs.cmd_pipeline_barrier2 == null);
    }
    if (std.mem.eql(u8, symbol, "vkCmdPushDescriptorSetKHR") or
        std.mem.eql(u8, symbol, "vkCmdPushDescriptorSet"))
    {
        return !self.real_vulkan.push_descriptor_enabled or
            self.real_vulkan.fn_ptrs.cmd_push_descriptor_set == null;
    }
    if (std.mem.eql(u8, symbol, "vkCmdSetDepthTestEnable") or
        std.mem.eql(u8, symbol, "vkCmdSetDepthTestEnableEXT") or
        std.mem.eql(u8, symbol, "vkCmdSetDepthWriteEnable") or
        std.mem.eql(u8, symbol, "vkCmdSetDepthWriteEnableEXT") or
        std.mem.eql(u8, symbol, "vkCmdSetDepthCompareOp") or
        std.mem.eql(u8, symbol, "vkCmdSetDepthCompareOpEXT") or
        std.mem.eql(u8, symbol, "vkCmdSetStencilTestEnable") or
        std.mem.eql(u8, symbol, "vkCmdSetStencilTestEnableEXT") or
        std.mem.eql(u8, symbol, "vkCmdSetStencilOp") or
        std.mem.eql(u8, symbol, "vkCmdSetStencilOpEXT"))
    {
        return !self.real_vulkan.extended_dynamic_state_enabled or
            (std.mem.eql(u8, symbol, "vkCmdSetDepthTestEnable") and self.real_vulkan.fn_ptrs.cmd_set_depth_test_enable == null) or
            (std.mem.eql(u8, symbol, "vkCmdSetDepthTestEnableEXT") and self.real_vulkan.fn_ptrs.cmd_set_depth_test_enable == null) or
            (std.mem.eql(u8, symbol, "vkCmdSetDepthWriteEnable") and self.real_vulkan.fn_ptrs.cmd_set_depth_write_enable == null) or
            (std.mem.eql(u8, symbol, "vkCmdSetDepthWriteEnableEXT") and self.real_vulkan.fn_ptrs.cmd_set_depth_write_enable == null) or
            (std.mem.eql(u8, symbol, "vkCmdSetDepthCompareOp") and self.real_vulkan.fn_ptrs.cmd_set_depth_compare_op == null) or
            (std.mem.eql(u8, symbol, "vkCmdSetDepthCompareOpEXT") and self.real_vulkan.fn_ptrs.cmd_set_depth_compare_op == null) or
            (std.mem.eql(u8, symbol, "vkCmdSetStencilTestEnable") and self.real_vulkan.fn_ptrs.cmd_set_stencil_test_enable == null) or
            (std.mem.eql(u8, symbol, "vkCmdSetStencilTestEnableEXT") and self.real_vulkan.fn_ptrs.cmd_set_stencil_test_enable == null) or
            (std.mem.eql(u8, symbol, "vkCmdSetStencilOp") and self.real_vulkan.fn_ptrs.cmd_set_stencil_op == null) or
            (std.mem.eql(u8, symbol, "vkCmdSetStencilOpEXT") and self.real_vulkan.fn_ptrs.cmd_set_stencil_op == null);
    }
    if (std.mem.eql(u8, symbol, "vkCmdSetPrimitiveRestartEnable") or
        std.mem.eql(u8, symbol, "vkCmdSetPrimitiveRestartEnableEXT"))
    {
        return !self.real_vulkan.extended_dynamic_state2_enabled or
            self.real_vulkan.fn_ptrs.cmd_set_primitive_restart_enable == null;
    }
    return false;
}

pub fn allocateGuestSymbol(self: anytype, library_token: u64, symbol: []const u8) u64 {
    const cacheable = symbol.len <= 95;
    const name_hash = vulkanNameHash(symbol);
    const cache_index = if (cacheable) guestSymbolLookupCacheIndex(library_token, name_hash) else 0;
    if (cacheable) {
        const cached = self.guest_symbol_lookup_cache[cache_index];
        if (cached.library_token == library_token and cached.name_hash == name_hash and cached.name_length == symbol.len) {
            const cached_index: usize = cached.symbol_index;
            if (cached_index < self.guest_symbols.len) {
                const entry = &self.guest_symbols[cached_index];
                if (entry.token != 0 and entry.library_token == library_token and
                    entry.name_hash == name_hash and entry.name_length == symbol.len and
                    std.mem.eql(u8, entry.name[0..entry.name_length], symbol))
                {
                    self.guest_symbol_lookup_cache_hits +|= 1;
                    return entry.token;
                }
            }
        }
        self.guest_symbol_lookup_cache_misses +|= 1;
    }
    for (&self.guest_symbols, 0..) |*entry, index| {
        if (entry.token == 0 or entry.library_token != library_token) continue;
        if (entry.name_length != symbol.len) continue;
        if (std.mem.eql(u8, entry.name[0..entry.name_length], symbol)) {
            if (cacheable) self.guest_symbol_lookup_cache[cache_index] = .{
                .library_token = library_token,
                .name_hash = name_hash,
                .symbol_index = @intCast(index),
                .name_length = @intCast(symbol.len),
            };
            return entry.token;
        }
    }
    // Classification is only needed when allocating a new thunk. Repeated
    // lookups dominate this path (the supplied run records 8.3M repeats),
    // so doing the long symbol-kind string match before the cache check
    // would erase most of the cache's benefit.
    const kind = guestSymbolKind(symbol);
    for (&self.guest_symbols, 0..) |*entry, index| {
        if (entry.token != 0) continue;
        const token = GUEST_SYMBOL_THUNK_BASE + @as(u64, @intCast(index)) * 16 + 1;
        const name_length: u8 = @intCast(@min(symbol.len, entry.name.len));
        entry.* = .{ .token = token, .library_token = library_token, .kind = kind, .name_length = name_length };
        @memcpy(entry.name[0..name_length], symbol[0..name_length]);
        entry.name_hash = vulkanNameHash(entry.name[0..name_length]);
        if (cacheable) self.guest_symbol_lookup_cache[cache_index] = .{
            .library_token = library_token,
            .name_hash = name_hash,
            .symbol_index = @intCast(index),
            .name_length = @intCast(symbol.len),
        };
        self.guest_lookup_count +|= 1;
        return token;
    }
    return 0;
}

pub fn shouldLogVulkanLoaderUnique(self: anytype) bool {
    const unique = self.vulkan_loader_lookup_unique;
    // Keep the boot contract visible, then let the summary carry the
    // complete inventory. A healthy title commonly resolves dozens of
    // entry points; one line for every successful resolution buries the
    // first actual refusal or stalled boundary.
    return unique <= 8 or (unique & (unique - 1)) == 0;
}

pub fn noteVulkanLoaderLookup(self: anytype, library_token: u64, symbol: []const u8, token: u64) bool {
    const name_hash = vulkanNameHash(symbol);
    if (token != 0) {
        const indexed = guestSymbolIndexFromToken(token);
        if (indexed) |index| {
            const entry = &self.guest_symbols[index];
            if (entry.token == token) {
                if (entry.loader_lookup_logged) {
                    entry.loader_lookup_repeats +|= 1;
                    self.noteSuppressedVulkanLoaderLookup();
                    return false;
                }
                entry.loader_lookup_logged = true;
                self.vulkan_loader_lookup_unique +|= 1;
                return self.shouldLogVulkanLoaderUnique();
            }
        }
        // Keep the old defensive path for malformed or stale tokens. The
        // normal token layout takes the direct indexed path above.
        for (&self.guest_symbols) |*entry| {
            if (entry.token != token) continue;
            if (entry.loader_lookup_logged) {
                entry.loader_lookup_repeats +|= 1;
                self.noteSuppressedVulkanLoaderLookup();
                return false;
            }
            entry.loader_lookup_logged = true;
            self.vulkan_loader_lookup_unique +|= 1;
            return self.shouldLogVulkanLoaderUnique();
        }
    }

    const stored_length: u8 = @intCast(@min(symbol.len, @as(usize, 95)));
    for (&self.vulkan_loader_lookup_misses) |*miss| {
        if (miss.library_token != library_token or
            miss.name_hash != name_hash or
            miss.name_length != stored_length or
            !std.mem.eql(u8, miss.name[0..miss.name_length], symbol[0..stored_length])) continue;
        miss.repeats +|= 1;
        self.noteSuppressedVulkanLoaderLookup();
        return false;
    }
    for (&self.vulkan_loader_lookup_misses) |*miss| {
        if (miss.library_token != 0) continue;
        miss.library_token = library_token;
        miss.name_hash = name_hash;
        miss.name_length = stored_length;
        @memcpy(miss.name[0..stored_length], symbol[0..stored_length]);
        self.vulkan_loader_lookup_unique +|= 1;
        return self.shouldLogVulkanLoaderUnique();
    }
    self.vulkan_loader_lookup_cache_overflows +|= 1;
    return self.vulkan_loader_lookup_cache_overflows == 1;
}

pub fn noteSuppressedVulkanLoaderLookup(self: anytype) void {
    self.vulkan_loader_lookup_repeats +|= 1;
    const repeats = self.vulkan_loader_lookup_repeats;
    if (repeats < 16 or (repeats & (repeats - 1)) != 0) return;
    // A refusal that has not been described yet rides this existing
    // cadence rather than starting a second one, so a run that is killed
    // mid-flight still carries the evidence.
    self.reportVulkanRefusals(false);
    self.refreshPresentChainWindow();
    self.reportPresentChain(false);
    machoCapturePrint(
        "macho-processor: Vulkan loader lookup summary: unique={d} repeats_suppressed={d} cache_overflows={d}\n",
        .{ self.vulkan_loader_lookup_unique, repeats, self.vulkan_loader_lookup_cache_overflows },
    );
}

pub fn readHostAbiStackWord(state: anytype, offset: u64) u64 {
    const address = guest_context.registers(state).rsp +| offset;
    if (state.guestMemoryConst(address, 8) == null) return host_page_range_selection_abi.no_page;
    return state.read64(address);
}

pub fn ppcGuestMemory(state: anytype) ppc_runtime.guest_bridge.GuestMemory {
    const State = @TypeOf(state.*);
    return .{
        .context = @ptrCast(state),
        .read = struct {
            fn read(context: *anyopaque, address: u64, output: []u8) bool {
                const inner: *State = @ptrCast(@alignCast(context));
                const bytes = inner.guestMemoryConst(address, @intCast(output.len)) orelse return false;
                @memcpy(output, bytes);
                return true;
            }
        }.read,
        .write = struct {
            fn write(context: *anyopaque, address: u64, input: []const u8) bool {
                const inner: *State = @ptrCast(@alignCast(context));
                if (comptime @hasDecl(State, "writeGuestBytes")) {
                    return inner.writeGuestBytes(address, input);
                }
                const bytes = inner.guestMemory(address, @intCast(input.len)) orelse return false;
                @memcpy(bytes, input);
                return true;
            }
        }.write,
        .read_ppc = struct {
            fn read(context: *anyopaque, address: u64, output: []u8) bool {
                const inner: *State = @ptrCast(@alignCast(context));
                const host_address = if (comptime @hasField(State, "xenia_memory_views"))
                    inner.xenia_memory_views.virtualHostAddress(address) orelse return false
                else
                    address;
                const bytes = inner.guestMemoryConst(host_address, @intCast(output.len)) orelse return false;
                @memcpy(output, bytes);
                return true;
            }
        }.read,
        .write_ppc = struct {
            fn write(context: *anyopaque, address: u64, input: []const u8) bool {
                const inner: *State = @ptrCast(@alignCast(context));
                const host_address = if (comptime @hasField(State, "xenia_memory_views"))
                    inner.xenia_memory_views.virtualHostAddress(address) orelse return false
                else
                    address;
                if (comptime @hasDecl(State, "writeGuestBytes")) {
                    return inner.writeGuestBytes(host_address, input);
                }
                const bytes = inner.guestMemory(host_address, @intCast(input.len)) orelse return false;
                @memcpy(bytes, input);
                return true;
            }
        }.write,
        .alloc = struct {
            fn alloc(context: *anyopaque, size: u64, alignment: u64) ?u64 {
                const inner: *State = @ptrCast(@alignCast(context));
                return inner.guestAlloc(size, alignment);
            }
        }.alloc,
    };
}

pub fn ppcGuestCall(state: anytype) ppc_runtime.guest_bridge.GuestCall {
    const State = @TypeOf(state.*);
    return struct {
        fn call(context: *anyopaque, address: u64, args: [6]u64) u64 {
            const inner: *State = @ptrCast(@alignCast(context));
            if (comptime @hasDecl(State, "callGuestFunction")) {
                return inner.callGuestFunction(address, args);
            }
            return 0;
        }
    }.call;
}

pub fn materializePpcIdentity(self: anytype, state: anytype) u64 {
    const text: []const u8 = ppc_runtime.host_abi.identity[0..];
    const memory = ppcGuestMemory(state);
    if (self.ppc_identity_guest != 0) {
        var probe: [1]u8 = undefined;
        if (memory.read(memory.context, self.ppc_identity_guest, &probe)) return self.ppc_identity_guest;
    }
    const address = memory.alloc(memory.context, @intCast(text.len + 1), 1) orelse return 0;
    if (!memory.write(memory.context, address, text)) return 0;
    if (!memory.write(memory.context, address + text.len, &[_]u8{0})) return 0;
    self.ppc_identity_guest = address;
    return address;
}

pub fn guestHeapEntries(state: anytype, guest_address: u64, total_page_count: u32) ?[*]const u64 {
    const byte_count = std.math.mul(
        u64,
        @as(u64, total_page_count),
        @as(u64, @sizeOf(u64)),
    ) catch return null;
    if (byte_count == 0) return null;
    const bytes = state.guestMemoryConst(guest_address, byte_count) orelse return null;
    if (@intFromPtr(bytes.ptr) % @alignOf(u64) != 0) return null;
    return @ptrCast(@alignCast(bytes.ptr));
}

pub fn readGuestRecord(state: anytype, address: u64, comptime T: type) ?T {
    if (address == 0) return null;
    const bytes = state.guestMemoryConst(address, @sizeOf(T)) orelse return null;
    var record: T = undefined;
    @memcpy(std.mem.asBytes(&record), bytes);
    return record;
}

pub fn writeGuestRecord(state: anytype, address: u64, record: anytype) bool {
    if (address == 0) return false;
    const bytes = state.guestMemory(address, @sizeOf(@TypeOf(record))) orelse return false;
    @memcpy(bytes, std.mem.asBytes(&record));
    return true;
}

pub fn enumFromRaw(comptime T: type, raw: u8) ?T {
    const fields = @typeInfo(T).@"enum".fields;
    if (raw >= fields.len) return null;
    return @enumFromInt(raw);
}

pub fn dispatchXeniaLaunchAssistQuery(_: *Forwarder, state: anytype) u64 {
    const request = readGuestRecord(
        state,
        guest_context.registers(state).rdi,
        console_launch_assist_contract.Request,
    ) orelse {
        machoCapturePrint(
            "macho-processor: Rosette host ABI: launch-assist query rejected unreadable request=0x{x}\n",
            .{guest_context.registers(state).rdi},
        );
        return 0;
    };
    if (guest_context.registers(state).rsi == 0 or
        state.guestMemory(guest_context.registers(state).rsi, @sizeOf(console_launch_assist_contract.Response)) == null)
    {
        machoCapturePrint(
            "macho-processor: Rosette host ABI: launch-assist query rejected unwritable response=0x{x}\n",
            .{guest_context.registers(state).rsi},
        );
        return 0;
    }
    const response = application_framework.defaultHandle().queryXeniaLaunchAssist(request);
    const written = writeGuestRecord(state, guest_context.registers(state).rsi, response);
    machoCapturePrint(
        "macho-processor: Rosette host ABI: launch-assist query request=0x{x} response=0x{x} decision={d} actions=0x{x} written={}\n",
        .{
            guest_context.registers(state).rdi,
            guest_context.registers(state).rsi,
            response.decision,
            response.actions,
            written,
        },
    );
    return @intFromBool(written);
}

pub fn dispatchXeniaLaunchAssistReport(_: *Forwarder, state: anytype) u64 {
    const request = readGuestRecord(
        state,
        guest_context.registers(state).rdi,
        console_launch_assist_contract.Request,
    ) orelse return 0;
    const response = readGuestRecord(
        state,
        guest_context.registers(state).rsi,
        console_launch_assist_contract.Response,
    ) orelse return 0;
    const status = enumFromRaw(
        console_launch_assist_contract.ApplyStatus,
        @truncate(guest_context.registers(state).rcx),
    ) orelse return 0;
    const coherent = application_framework.defaultHandle().reportXeniaLaunchAssist(
        request,
        response,
        @truncate(guest_context.registers(state).rdx),
        status,
    );
    machoCapturePrint(
        "macho-processor: Rosette host ABI: launch-assist report request=0x{x} response=0x{x} applied=0x{x} status={d} coherent={}\n",
        .{
            guest_context.registers(state).rdi,
            guest_context.registers(state).rsi,
            @as(u32, @truncate(guest_context.registers(state).rdx)),
            @intFromEnum(status),
            coherent,
        },
    );
    return @intFromBool(coherent);
}

pub fn dispatchXeniaHostGpuCallbackQuery(_: *Forwarder, state: anytype) u64 {
    const request = readGuestRecord(
        state,
        guest_context.registers(state).rdi,
        xenia_host_gpu_callback_contract.Request,
    ) orelse {
        machoCapturePrint(
            "macho-processor: Rosette host ABI: host-GPU-callback query rejected unreadable request=0x{x}\n",
            .{guest_context.registers(state).rdi},
        );
        return 0;
    };
    if (guest_context.registers(state).rsi == 0 or
        state.guestMemory(guest_context.registers(state).rsi, @sizeOf(xenia_host_gpu_callback_contract.Response)) == null)
    {
        machoCapturePrint(
            "macho-processor: Rosette host ABI: host-GPU-callback query rejected unwritable response=0x{x}\n",
            .{guest_context.registers(state).rsi},
        );
        return 0;
    }
    const response = application_framework.defaultHandle().queryXeniaHostGpuCallback(request);
    const written = writeGuestRecord(state, guest_context.registers(state).rsi, response);
    machoCapturePrint(
        "macho-processor: Rosette host ABI: host-GPU-callback query request=0x{x} response=0x{x} decision={d} actions=0x{x} written={}\n",
        .{
            guest_context.registers(state).rdi,
            guest_context.registers(state).rsi,
            response.decision,
            response.actions,
            written,
        },
    );
    return @intFromBool(written);
}

pub fn dispatchXeniaHostGpuCallbackReport(_: *Forwarder, state: anytype) u64 {
    const request = readGuestRecord(
        state,
        guest_context.registers(state).rdi,
        xenia_host_gpu_callback_contract.Request,
    ) orelse return 0;
    const response = readGuestRecord(
        state,
        guest_context.registers(state).rsi,
        xenia_host_gpu_callback_contract.Response,
    ) orelse return 0;
    const status = enumFromRaw(
        xenia_host_gpu_callback_contract.ApplyStatus,
        @truncate(guest_context.registers(state).rcx),
    ) orelse return 0;
    const coherent = application_framework.defaultHandle().reportXeniaHostGpuCallback(
        request,
        response,
        @truncate(guest_context.registers(state).rdx),
        status,
    );
    machoCapturePrint(
        "macho-processor: Rosette host ABI: host-GPU-callback report request=0x{x} response=0x{x} applied=0x{x} status={d} coherent={}\n",
        .{
            guest_context.registers(state).rdi,
            guest_context.registers(state).rsi,
            @as(u32, @truncate(guest_context.registers(state).rdx)),
            @intFromEnum(status),
            coherent,
        },
    );
    return @intFromBool(coherent);
}

pub fn dispatchGuestSymbol(self: anytype, state: anytype, token: u64) bool {
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
    const is_rosette_host_abi = entry.library_token == RTLD_DEFAULT_HANDLE;
    if (!is_rosette_host_abi and self.guestLibraryEntry(entry.library_token) == null) return false;
    self.guest_thunk_calls +|= 1;
    entry.calls +|= 1;
    if (is_rosette_host_abi) {
        switch (entry.kind) {
            .rosette_heap_allocator_abi_version => {
                guest_context.registers(state).rax = host_page_range_selection_abi.abiVersion();
            },
            .rosette_heap_select => {
                if (guest_context.registers(state).rsi > std.math.maxInt(u32)) {
                    guest_context.registers(state).rax = host_page_range_selection_abi.no_page;
                } else {
                    const total_page_count: u32 = @intCast(guest_context.registers(state).rsi);
                    const entries = guestHeapEntries(state, guest_context.registers(state).rdi, total_page_count);
                    guest_context.registers(state).rax = if (entries) |page_entries|
                        host_page_range_selection_abi.selectC(
                            page_entries,
                            total_page_count,
                            @truncate(guest_context.registers(state).rdx),
                            @truncate(guest_context.registers(state).rcx),
                            @truncate(guest_context.registers(state).r8),
                            @truncate(guest_context.registers(state).r9),
                            @truncate(readHostAbiStackWord(state, 8)),
                            @truncate(readHostAbiStackWord(state, 16)),
                        )
                    else
                        host_page_range_selection_abi.no_page;
                }
            },
            .rosette_ppc_host_available => {
                guest_context.registers(state).rax = 1;
            },
            .rosette_ppc_host_identity => {
                guest_context.registers(state).rax = self.materializePpcIdentity(state);
            },
            .rosette_ppc_bind_context => {
                const State = @TypeOf(state.*);
                if (comptime @hasDecl(State, "callGuestFunction")) {
                    const memory = ppcGuestMemory(state);
                    const bound = self.ppc_guest_bridge.bind(
                        guest_context.registers(state).rdi,
                        memory,
                        @ptrCast(state),
                        ppcGuestCall(state),
                    );
                    if (!bound) {
                        machoCapturePrint(
                            "macho-processor: PPC guest-state bind rejected: state=0x{x} reason={s}\n",
                            .{ guest_context.registers(state).rdi, @tagName(self.ppc_guest_bridge.last_bind_failure) },
                        );
                    }
                    guest_context.registers(state).rax = @intFromBool(bound);
                } else {
                    guest_context.registers(state).rax = 0;
                }
            },
            .rosette_ppc_release_context => {
                self.ppc_guest_bridge.release(guest_context.registers(state).rdi);
                guest_context.registers(state).rax = 0;
            },
            .rosette_ppc_set_recompiler_enabled => {
                const enabled: i32 = @bitCast(@as(u32, @truncate(guest_context.registers(state).rdi)));
                const result: i32 = ppc_runtime.host_abi.rosette_ppc_set_recompiler_enabled(enabled);
                guest_context.registers(state).rax = @intCast(@as(u32, @bitCast(result)));
            },
            .rosette_ppc_recompiler_stats => {
                guest_context.registers(state).rax = @intFromBool(self.ppc_guest_bridge.stats(
                    guest_context.registers(state).rdi,
                    guest_context.registers(state).rsi,
                    guest_context.registers(state).rdx,
                ));
            },
            .rosette_ppc_invalidate_range => {
                self.ppc_guest_bridge.invalidateRange(
                    @truncate(guest_context.registers(state).rdi),
                    @truncate(guest_context.registers(state).rsi),
                );
                guest_context.registers(state).rax = 0;
            },
            .rosette_ppc_execute => {
                guest_context.registers(state).rax = @intFromBool(self.ppc_guest_bridge.execute(
                    guest_context.registers(state).rdi,
                    @truncate(guest_context.registers(state).rsi),
                    @truncate(guest_context.registers(state).rdx),
                    guest_context.registers(state).rcx,
                ));
            },
            .rosette_xenia_launch_assist_abi_version => {
                guest_context.registers(state).rax = console_launch_assist_contract.abi_version;
            },
            .rosette_xenia_launch_assist_schema_version => {
                guest_context.registers(state).rax = console_launch_assist_contract.schema_version;
            },
            .rosette_xenia_launch_assist_query => {
                guest_context.registers(state).rax = self.dispatchXeniaLaunchAssistQuery(state);
            },
            .rosette_xenia_launch_assist_report => {
                guest_context.registers(state).rax = self.dispatchXeniaLaunchAssistReport(state);
            },
            .rosette_xenia_host_gpu_callback_abi_version => {
                guest_context.registers(state).rax = xenia_host_gpu_callback_contract.abi_version;
            },
            .rosette_xenia_host_gpu_callback_schema_version => {
                guest_context.registers(state).rax = xenia_host_gpu_callback_contract.schema_version;
            },
            .rosette_xenia_host_gpu_callback_query => {
                guest_context.registers(state).rax = self.dispatchXeniaHostGpuCallbackQuery(state);
            },
            .rosette_xenia_host_gpu_callback_report => {
                guest_context.registers(state).rax = self.dispatchXeniaHostGpuCallbackReport(state);
            },
            else => return false,
        }
        return true;
    }
    const entry_name = entry.name[0..entry.name_length];
    const asynchronous_candidate = entry.kind == .command and __ForwarderInternals._async_vulkan_command.isCandidate(entry_name);
    if (!asynchronous_candidate) self.drainAsyncVulkanCommands();
    self.frame_provenance.noteGuestVulkanCall();
    switch (entry.kind) {
        .get_instance_proc_addr, .get_device_proc_addr => {
            const symbol = state.guestCString(guest_context.registers(state).rsi, 512) orelse {
                guest_context.registers(state).rax = 0;
                return true;
            };
            const result = self.lookupVulkanProcGuest(entry.library_token, symbol);
            if (result != 0) state.registerSyntheticThunk(result, 1, symbol);
            guest_context.registers(state).rax = result;
        },
        .enumerate_instance_extensions => guest_context.registers(state).rax = self.enumerateInstanceExtensions(state, entry.library_token),
        .enumerate_instance_layers => guest_context.registers(state).rax = enumerateEmpty(state, guest_context.registers(state).rdi),
        .enumerate_instance_version => guest_context.registers(state).rax = writeApiVersion(state, guest_context.registers(state).rdi),
        .create_instance => blk: {
            machoCapturePrint("macho-processor: BOOTUP MILESTONE: guest invoked vkCreateInstance — Vulkan instance creation beginning\n", .{});
            machoCapturePrint("macho-processor: vkCreateInstance dispatch: pCreateInfo=0x{x} pInstance=0x{x}\n", .{ guest_context.registers(state).rdi, guest_context.registers(state).rdx });
            if (guest_context.registers(state).rdx == 0 or !guestRangeAvailable(state, guest_context.registers(state).rdx, 8)) {
                guest_context.registers(state).rax = @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
                machoCapturePrint(
                    "macho-processor: vkCreateInstance dispatch FAILED: pInstance=0x{x} is not writable\n",
                    .{guest_context.registers(state).rdx},
                );
                break :blk;
            }
            const inst_result = self.ensureRealInstance(state, entry.library_token, guest_context.registers(state).rdi);
            if (inst_result == 0) {
                // Write the real instance handle to the guest.
                state.write64(guest_context.registers(state).rdx, @intFromPtr(self.real_vulkan.instance.?));
                self.real_vulkan.guest_instance_handle = state.read64(guest_context.registers(state).rdx);
                guest_context.registers(state).rax = 0;
                machoCapturePrint("macho-processor: BOOTUP MILESTONE: vkCreateInstance dispatch complete — real instance ready\n", .{});
            } else {
                guest_context.registers(state).rax = @bitCast(@as(i64, inst_result));
                machoCapturePrint("macho-processor: vkCreateInstance dispatch FAILED: result={d}\n", .{inst_result});
            }
            break :blk;
        },
        .enumerate_physical_devices => blk: {
            const physical_device = physicalDeviceGuestHandle(self.real_vulkan.physical_device);
            guest_context.registers(state).rax = enumerateHandle(
                state,
                guest_context.registers(state).rsi,
                guest_context.registers(state).rdx,
                physical_device.value,
                "Vulkan physical device",
                physical_device.register_opaque,
            );
            break :blk;
        },
        .enumerate_device_extensions => guest_context.registers(state).rax = if (self.real_vulkan.hasInstance()) self.enumerateRealDeviceExtensions(state) else enumerateDeviceExtensions(state),
        .get_physical_device_features => blk: {
            if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceFeatures(state, guest_context.registers(state).rsi) else writePhysicalDeviceFeatures(state, guest_context.registers(state).rsi);
            break :blk;
        },
        .get_physical_device_format_properties => {
            if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceFormatProperties(state, guest_context.registers(state).rsi, guest_context.registers(state).rdx) else writeFormatProperties(state, guest_context.registers(state).rdx);
        },
        .get_physical_device_memory_properties => blk: {
            if (self.real_vulkan.hasInstance()) {
                self.vulkan_tiers.note(.memory_properties, .real);
                self.writeRealMemoryProperties(state, guest_context.registers(state).rsi);
            } else {
                self.vulkan_tiers.note(.memory_properties, .modelled);
                writeMemoryProperties(state, guest_context.registers(state).rsi);
            }
            break :blk;
        },
        .get_physical_device_properties => blk: {
            if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceProperties(state, guest_context.registers(state).rsi) else writePhysicalDeviceProperties(state, guest_context.registers(state).rsi);
            break :blk;
        },
        .get_physical_device_queue_families => blk: {
            if (self.real_vulkan.hasInstance()) self.writeRealQueueFamilies(state) else writeQueueFamilies(state);
            break :blk;
        },
        .get_physical_device_features2 => blk: {
            if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceFeatures2(state, guest_context.registers(state).rsi) else writePhysicalDeviceFeatures2(state, guest_context.registers(state).rsi);
            break :blk;
        },
        .get_physical_device_memory_properties2 => blk: {
            if (self.real_vulkan.hasInstance()) self.writeRealMemoryProperties2(state, guest_context.registers(state).rsi) else writeMemoryProperties2(state, guest_context.registers(state).rsi);
            break :blk;
        },
        .get_physical_device_properties2 => blk: {
            if (self.real_vulkan.hasInstance()) self.writeRealPhysicalDeviceProperties2(state, guest_context.registers(state).rsi) else writePhysicalDeviceProperties2(state, guest_context.registers(state).rsi);
            break :blk;
        },
        .create_device => blk: {
            machoCapturePrint("macho-processor: BOOTUP MILESTONE: guest invoked vkCreateDevice — GPU device creation beginning\n", .{});
            machoCapturePrint("macho-processor: vkCreateDevice dispatch: physical_device=0x{x} pCreateInfo=0x{x} pDevice=0x{x}\n", .{ guest_context.registers(state).rdi, guest_context.registers(state).rsi, guest_context.registers(state).rcx });
            const dev_result = self.ensureRealDevice(
                state,
                entry.library_token,
                guest_context.registers(state).rdi, // physical device
                guest_context.registers(state).rsi, // pCreateInfo
                guest_context.registers(state).rcx, // pDevice
            );
            guest_context.registers(state).rax = if (dev_result == 0) 0 else @bitCast(@as(i64, dev_result));
            if (dev_result == 0) {
                machoCapturePrint("macho-processor: BOOTUP MILESTONE: vkCreateDevice dispatch complete — real device ready\n", .{});
            } else {
                machoCapturePrint("macho-processor: vkCreateDevice dispatch FAILED: result={d}\n", .{dev_result});
            }
            break :blk;
        },
        .get_device_queue => guest_context.registers(state).rax = self.writeDeviceQueue(state, guest_context.registers(state).rcx, "vkGetDeviceQueue"),
        .get_device_queue2 => guest_context.registers(state).rax = self.writeDeviceQueue(state, guest_context.registers(state).rdx, "vkGetDeviceQueue2"),
        .get_semaphore_counter_value => guest_context.registers(state).rax = self.getSemaphoreCounterValue(state),
        .wait_semaphores => guest_context.registers(state).rax = self.waitSemaphores(state),
        .signal_semaphore => guest_context.registers(state).rax = self.signalSemaphore(state),
        .create_metal_surface => guest_context.registers(state).rax = self.createMetalSurface(state, entry.library_token, guest_context.registers(state).rdi, guest_context.registers(state).rsi, guest_context.registers(state).rcx),
        .get_surface_capabilities => {
            self.vulkan_surface_capability_queries +|= 1;
            guest_context.registers(state).rax = if (self.real_vulkan.surface != 0) self.writeRealSurfaceCapabilities(state, guest_context.registers(state).rdx) else writeSurfaceCapabilities(state, guest_context.registers(state).rdx);
            if (self.vulkan_surface_capability_queries == 1 and guest_context.registers(state).rax == 0) {
                const State = @typeInfo(@TypeOf(state)).pointer.child;
                const width = if (@hasDecl(State, "nativeWindowWidth")) state.nativeWindowWidth() else 0;
                const height = if (@hasDecl(State, "nativeWindowHeight")) state.nativeWindowHeight() else 0;
                machoCapturePrint(
                    "macho-processor: Vulkan surface capabilities: native_extent={d}x{d} min_extent=1x1 max_extent=16384x16384 image_count=2..3 usage=0x13\n",
                    .{ width, height },
                );
            }
        },
        .get_surface_formats => guest_context.registers(state).rax = if (self.real_vulkan.surface != 0) self.enumerateRealSurfaceFormats(state) else enumerateSurfaceFormats(state),
        .get_surface_present_modes => guest_context.registers(state).rax = if (self.real_vulkan.surface != 0) self.enumerateRealSurfacePresentModes(state) else enumerateSurfacePresentModes(state),
        .get_surface_support => guest_context.registers(state).rax = if (self.real_vulkan.surface != 0) self.writeRealSurfaceSupport(state) else writeBoolResult(state, guest_context.registers(state).rcx, true),
        // Xenia uses the platform-specific support query while deciding
        // whether a physical device can present before it creates the
        // surface.  The Windows handle itself is not transferable to
        // macOS; the adapter has already committed this route to the
        // native CAMetalLayer surface, so report support only when the
        // native Vulkan instance has supplied a physical device.
        .get_physical_device_win32_presentation_support => {
            guest_context.registers(state).rax = @intFromBool(self.real_vulkan.hasInstance() and self.real_vulkan.physical_device != null);
        },
        .destroy_surface => {
            self.destroyNativeSurface();
            self.destroyRealSurface();
            guest_context.registers(state).rax = 0;
        },
        .destroy_instance => {
            self.releaseNativeMemoryAliases(state);
            self.destroyNativeVulkanObjects();
            guest_context.registers(state).rax = 0;
        },
        .destroy_device => {
            self.releaseNativeMemoryAliases(state);
            self.destroyRealDevice();
            guest_context.registers(state).rax = 0;
        },
        .create_swapchain => guest_context.registers(state).rax = self.createSwapchain(state, guest_context.registers(state).rdi, guest_context.registers(state).rsi, guest_context.registers(state).rcx),
        .destroy_swapchain => {
            self.destroyRealSwapchain(guest_context.registers(state).rsi);
            guest_context.registers(state).rax = 0;
        },
        .get_swapchain_images => guest_context.registers(state).rax = self.enumerateSwapchainImages(state),
        .acquire_next_image => guest_context.registers(state).rax = self.acquireNextImage(state, guest_context.registers(state).r9),
        .queue_submit => guest_context.registers(state).rax = self.queueSubmit(state),
        .queue_submit2 => guest_context.registers(state).rax = self.queueSubmit2(state),
        .queue_bind_sparse => guest_context.registers(state).rax = self.queueBindSparse(state),
        .queue_present => guest_context.registers(state).rax = self.queuePresent(state),
        .queue_wait_idle => guest_context.registers(state).rax = self.queueWaitIdle(state),
        .create_pipeline_cache => guest_context.registers(state).rax = self.createVulkanObject(state, guest_context.registers(state).rsi, guest_context.registers(state).rcx, "vkCreatePipelineCache"),
        .create_descriptor_update_template => guest_context.registers(state).rax = self.createVulkanObject(state, guest_context.registers(state).rsi, guest_context.registers(state).rcx, "vkCreateDescriptorUpdateTemplate"),
        .create_device_object => guest_context.registers(state).rax = self.createVulkanObject(state, guest_context.registers(state).rsi, guest_context.registers(state).rcx, entry.name[0..entry.name_length]),
        .bind_image_memory => guest_context.registers(state).rax = self.bindResourceMemory(guest_context.registers(state).rsi, guest_context.registers(state).rdx, guest_context.registers(state).rcx, .image),
        .bind_buffer_memory => guest_context.registers(state).rax = self.bindResourceMemory(guest_context.registers(state).rsi, guest_context.registers(state).rdx, guest_context.registers(state).rcx, .buffer),
        .bind_image_memory2 => guest_context.registers(state).rax = self.bindResourcesMemory2(state, guest_context.registers(state).rsi, guest_context.registers(state).rdx, .image),
        .bind_buffer_memory2 => guest_context.registers(state).rax = self.bindResourcesMemory2(state, guest_context.registers(state).rsi, guest_context.registers(state).rdx, .buffer),
        .allocate_command_buffers => guest_context.registers(state).rax = self.allocateVulkanObjects(state, guest_context.registers(state).rsi, guest_context.registers(state).rdx, 28, entry.name[0..entry.name_length]),
        .allocate_descriptor_sets => guest_context.registers(state).rax = self.allocateVulkanObjects(state, guest_context.registers(state).rsi, guest_context.registers(state).rdx, 24, entry.name[0..entry.name_length]),
        .allocate_memory => guest_context.registers(state).rax = self.allocateVulkanMemory(state, guest_context.registers(state).rsi, guest_context.registers(state).rcx),
        .map_memory => guest_context.registers(state).rax = self.mapVulkanMemory(
            state,
            guest_context.registers(state).rsi,
            guest_context.registers(state).rdx,
            guest_context.registers(state).rcx,
            guest_context.registers(state).r9,
        ),
        .get_memory_requirements => guest_context.registers(state).rax = self.writeResourceMemoryRequirements(state, guest_context.registers(state).rsi, guest_context.registers(state).rdx),
        .get_memory_requirements2 => guest_context.registers(state).rax = self.writeResourceMemoryRequirements2(state, guest_context.registers(state).rsi, guest_context.registers(state).rdx),
        .get_device_buffer_memory_requirements => guest_context.registers(state).rax = self.writeDeviceBufferMemoryRequirements(state),
        .get_device_image_memory_requirements => guest_context.registers(state).rax = self.writeDeviceImageMemoryRequirements(state),
        .get_pipeline_cache_data => guest_context.registers(state).rax = self.getPipelineCacheData(state),
        .create_graphics_pipelines => guest_context.registers(state).rax = self.createMultipleVulkanObjects(state, guest_context.registers(state).rdx, guest_context.registers(state).r9, entry.name[0..entry.name_length]),
        .begin_command_buffer => guest_context.registers(state).rax = self.beginCommandBuffer(state),
        .end_command_buffer => guest_context.registers(state).rax = self.endCommandBuffer(state),
        .reset_command_buffer => guest_context.registers(state).rax = self.resetCommandBuffer(state),
        .reset_command_pool => guest_context.registers(state).rax = self.resetCommandPool(state),
        .reset_descriptor_pool => guest_context.registers(state).rax = self.resetDescriptorPool(state),
        .wait_for_fences => guest_context.registers(state).rax = self.waitForFences(state),
        .reset_fences => guest_context.registers(state).rax = self.resetFences(state),
        .get_fence_status => guest_context.registers(state).rax = self.getFenceStatus(state),
        .get_query_pool_results => guest_context.registers(state).rax = self.getQueryPoolResults(state),
        .reset_query_pool => guest_context.registers(state).rax = self.resetQueryPool(state),
        .device_wait_idle => guest_context.registers(state).rax = self.deviceWaitIdle(state),
        .flush_mapped_memory_ranges => guest_context.registers(state).rax = self.flushMappedMemoryRanges(state),
        .invalidate_mapped_memory_ranges => guest_context.registers(state).rax = self.invalidateMappedMemoryRanges(state),
        .unmap_memory => guest_context.registers(state).rax = self.unmapMemory(state),
        .destroy_device_object => guest_context.registers(state).rax = self.destroyVulkanObject(state, entry.name[0..entry.name_length]),
        .command => {
            self.forwardVulkanCommand(state, entry.name_hash, entry.name[0..entry.name_length]);
            guest_context.registers(state).rax = 0;
        },
        .update_descriptor_sets => {
            self.updateDescriptorSets(state);
            guest_context.registers(state).rax = 0;
        },
        .update_descriptor_set_with_template => {
            self.updateDescriptorSetWithTemplate(state);
            guest_context.registers(state).rax = 0;
        },
        .device_success => {
            const fn_name = entry.name[0..entry.name_length];
            if (self.vulkan_device_void_calls <= 3 or entry.calls == 1) {
                machoCapturePrint(
                    "macho-processor: Vulkan device_success: {s} calls={d}\n",
                    .{ fn_name, entry.calls },
                );
            }
            guest_context.registers(state).rax = 0;
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
            guest_context.registers(state).rax = 0;
        },
        // vkCreateDebugUtilsMessengerEXT(instance, pCreateInfo,
        // pAllocator, pMessenger): the output handle is rcx.  Publishing
        // it matters even though the messenger does nothing — leaving the
        // guest's VkDebugUtilsMessengerEXT untouched while returning
        // VK_SUCCESS is how an uninitialised handle reaches
        // vkDestroyDebugUtilsMessengerEXT at instance teardown.
        .create_debug_messenger => {
            if (guest_context.registers(state).rcx == 0 or !guestRangeAvailable(state, guest_context.registers(state).rcx, 8)) {
                guest_context.registers(state).rax = vkErrorInitializationFailed();
            } else {
                state.write64(guest_context.registers(state).rcx, SYNTHETIC_DEBUG_MESSENGER_HANDLE);
                self.debug_messenger_handle = SYNTHETIC_DEBUG_MESSENGER_HANDLE;
                machoCapturePrint(
                    "macho-processor: Vulkan debug utils messenger modelled as a no-op: handle=0x{x}; guest callbacks stay in the guest\n",
                    .{SYNTHETIC_DEBUG_MESSENGER_HANDLE},
                );
                guest_context.registers(state).rax = 0;
            }
        },
        .destroy_debug_messenger => {
            if (guest_context.registers(state).rsi != 0 and guest_context.registers(state).rsi != SYNTHETIC_DEBUG_MESSENGER_HANDLE) {
                machoCapturePrint(
                    "macho-processor: guest destroyed a debug utils messenger the bridge never issued: handle=0x{x}\n",
                    .{guest_context.registers(state).rsi},
                );
            }
            if (guest_context.registers(state).rsi == SYNTHETIC_DEBUG_MESSENGER_HANDLE) self.debug_messenger_handle = 0;
            guest_context.registers(state).rax = 0;
        },
        .debug_utils_success => guest_context.registers(state).rax = 0,
        .rosette_heap_allocator_abi_version, .rosette_heap_select, .rosette_ppc_host_available, .rosette_ppc_host_identity, .rosette_ppc_bind_context, .rosette_ppc_release_context, .rosette_ppc_set_recompiler_enabled, .rosette_ppc_recompiler_stats, .rosette_ppc_invalidate_range, .rosette_ppc_execute, .rosette_xenia_launch_assist_abi_version, .rosette_xenia_launch_assist_schema_version, .rosette_xenia_launch_assist_query, .rosette_xenia_launch_assist_report, .rosette_xenia_host_gpu_callback_abi_version, .rosette_xenia_host_gpu_callback_schema_version, .rosette_xenia_host_gpu_callback_query, .rosette_xenia_host_gpu_callback_report => return false,
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
            guest_context.registers(state).rax = 0;
        },
    }

    if (vulkanDispatchTraceEnabled() and self.vulkan_dispatch_trace_count < 128) {
        self.vulkan_dispatch_trace_count += 1;
        machoCapturePrint(
            "macho-processor: Vulkan dispatch trace #{d}: name={s} kind={s} result=0x{x} args=(0x{x},0x{x},0x{x},0x{x}) instance={} physical={} device={} queue={}\n",
            .{
                self.vulkan_dispatch_trace_count,
                entry.name[0..entry.name_length],
                @tagName(entry.kind),
                guest_context.registers(state).rax,
                guest_context.registers(state).rdi,
                guest_context.registers(state).rsi,
                guest_context.registers(state).rdx,
                guest_context.registers(state).rcx,
                self.real_vulkan.hasInstance(),
                self.real_vulkan.physical_device != null,
                self.real_vulkan.hasDevice(),
                self.real_vulkan.graphics_queue != null,
            },
        );
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
        const recorded_result: i32 = @bitCast(@as(u32, @truncate(guest_context.registers(state).rax)));
        self.recordVulkanCall(state, entry.name[0..entry.name_length], recorded_result, guest_context.registers(state).rdi, guest_context.registers(state).rsi);
    }
    return true;
}

pub fn writeRealPhysicalDeviceProperties(self: anytype, state: anytype, output: u64) void {
    _ = writeGuestBytes(state, output, self.real_vulkan.physical_device_properties[0..VK_PHYSICAL_DEVICE_PROPERTIES_SIZE]);
}

pub fn writeRealPhysicalDeviceFormatProperties(self: anytype, state: anytype, format: u64, output: u64) void {
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

pub fn enumerateRealDeviceExtensions(self: anytype, state: anytype) u64 {
    if (!self.queryHostDeviceExtensions()) return instance_extensions.enumerateSyntheticDevice(state);
    if (guest_context.registers(state).rsi != 0) return instance_extensions.enumerateNoLayer(state, guest_context.registers(state).rdx);
    return instance_extensions.writeProperties(state, guest_context.registers(state).rdx, guest_context.registers(state).rcx, self.hostDeviceExtensions());
}

pub fn collectFeatureChain(self: anytype, state: anytype, guest_p_next: u64, scratch: *FeatureChainScratch, copy_guest: bool) bool {
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
            // This chain is handed to the native driver during device
            // creation.  There is no safe meaning for "leave it
            // guest-owned" at that boundary: the driver would either
            // follow an x86 guest pointer or create a device missing a
            // feature the guest believes it enabled.  Refuse the whole
            // chain so an unknown node cannot turn into a split-brain
            // device.
            machoCapturePrint("macho-processor: Vulkan feature pNext sType={d} is not in the host bridge; refusing device creation\n", .{s_type});
            return false;
        }
        node = next;
    }
    linkFeatureChain(scratch);
    return true;
}

pub fn queryFeatureChain(self: anytype, scratch: *FeatureChainScratch) bool {
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

pub fn prepareDeviceFeatureChain(self: anytype, state: anytype, guest_p_next: u64, scratch: *FeatureChainScratch) bool {
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
            if (requested != 0 and available == 0) return false;
            // Normalize nonzero guest VkBool32 values to VK_TRUE while
            // preserving the exact requested feature set. Silently
            // masking an unsupported bit creates a device whose feature
            // contract differs from what the guest negotiated.
            std.mem.writeInt(u32, scratch.nodes[kind][offset..][0..4], if (requested != 0) 1 else 0, .little);
        }
    }
    linkFeatureChain(scratch);
    return true;
}

pub fn logFragmentShaderInterlockContract(
    self: anytype,
    state: anytype,
    guest_p_next: u64,
    guest_extension_requested: ?bool,
    stage: []const u8,
) void {
    const guest = fsiGuestFeatureRequest(state, guest_p_next);
    const host_extension = if (!self.real_vulkan.host_device_extensions_known)
        "unknown"
    else if (self.hostDeviceExtensionAvailable("VK_EXT_fragment_shader_interlock"))
        "yes"
    else
        "no";
    const guest_extension = if (guest_extension_requested) |requested|
        (if (requested) "yes" else "no")
    else
        "not_scanned";
    const host_features_known = self.real_vulkan.feature_chain_valid[3] and
        self.real_vulkan.feature_chain_sizes[3] >= featureChainSize(3);
    const host_features: []const u8 = if (host_features_known)
        self.real_vulkan.feature_chain_supported[3][0..self.real_vulkan.feature_chain_sizes[3]]
    else
        &.{};
    const feature_query = if (host_features_known) "available" else "unknown";
    const core_sample_rate_shading = coreFeatureEnabled(
        &self.real_vulkan.physical_device_features,
        abi.PHYSICAL_DEVICE_FEATURES_SAMPLE_RATE_SHADING_OFFSET,
    );
    const core_fragment_stores_and_atomics = coreFeatureEnabled(
        &self.real_vulkan.physical_device_features,
        abi.PHYSICAL_DEVICE_FEATURES_FRAGMENT_STORES_AND_ATOMICS_OFFSET,
    );
    const chain_status = switch (guest.status) {
        .absent => "absent",
        .present => "present",
        .unreadable => "unreadable",
        .too_deep => "too_deep",
    };
    const limits = abi.fsiPhysicalDeviceLimits(&self.real_vulkan.physical_device_properties);
    const sample_locations: []const u8 = if (limits) |value|
        (if (value.standard_sample_locations) "true" else "false")
    else
        "unknown";
    const per_stage_storage_buffers = if (limits) |value| value.max_per_stage_storage_buffers else 0;
    const max_storage_buffer_range = if (limits) |value| value.max_storage_buffer_range else 0;
    const core_features_ready = core_sample_rate_shading and core_fragment_stores_and_atomics;
    const guest_interlock_requested = guest.sample or guest.pixel;
    const host_interlock_supported = featureChainBoolAt(host_features, 0) or featureChainBoolAt(host_features, 1);
    const known_fsi_gate = std.mem.eql(u8, guest_extension, "yes") and std.mem.eql(u8, host_extension, "yes") and
        guest.status == .present and guest_interlock_requested and host_interlock_supported and
        core_features_ready and limits != null;
    const standard_sample_locations_ready = if (limits) |value| value.standard_sample_locations else false;
    const base_gate: []const u8 = if (limits == null or !host_features_known)
        "unknown"
    else if (!known_fsi_gate or !standard_sample_locations_ready)
        "blocked"
    else
        "pass_shared_binding_count_unchecked";
    machoCapturePrint(
        "macho-processor: Vulkan FSI contract: stage={s} guest_extension={s} host_extension={s} guest_pNext={s} guest(sample/pixel/shading_rate)={}/{}/{} host_feature_query={s} host_supported(sample/pixel/shading_rate)={}/{}/{} core(sample_rate_shading/fragment_stores_and_atomics)={}/{} limits(standardSampleLocations={s} maxPerStageDescriptorStorageBuffers={d} maxStorageBufferRange={d}) base_gate={s}; Xenia can still choose FBO if its shared-memory binding count reaches the host per-stage limit\n",
        .{
            stage,
            guest_extension,
            host_extension,
            chain_status,
            guest.sample,
            guest.pixel,
            guest.shading_rate,
            feature_query,
            featureChainBoolAt(host_features, 0),
            featureChainBoolAt(host_features, 1),
            featureChainBoolAt(host_features, 2),
            core_sample_rate_shading,
            core_fragment_stores_and_atomics,
            sample_locations,
            per_stage_storage_buffers,
            max_storage_buffer_range,
            base_gate,
        },
    );
}

pub fn writeRealPhysicalDeviceProperties2(self: anytype, state: anytype, output: u64) void {
    if (!guestRangeAvailable(state, output, 16)) return;
    const next = state.read64(output + 8);
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
        const source: []const u8 = switch (kind) {
            0 => std.mem.asBytes(&scratch.driver),
            1 => std.mem.asBytes(&scratch.float_controls),
            2 => std.mem.asBytes(&scratch.memory_budget),
            else => unreachable,
        };
        _ = writeGuestBytes(state, destination_address + 16, source[16..size]);
    }
}

pub fn writeRealPhysicalDeviceFeatures(self: anytype, state: anytype, output: u64) void {
    _ = writeGuestBytes(state, output, &self.real_vulkan.physical_device_features);
}

pub fn writeRealPhysicalDeviceFeatures2(self: anytype, state: anytype, output: u64) void {
    if (!writeGuestBytes(state, output + 16, &self.real_vulkan.physical_device_features)) return;
    if (!guestRangeAvailable(state, output, 16)) return;
    const guest_p_next = state.read64(output + 8);
    if (guest_p_next == 0) return;
    var scratch: FeatureChainScratch = .{};
    if (!self.collectFeatureChain(state, guest_p_next, &scratch, false)) return;
    if (!self.queryFeatureChain(&scratch)) return;
    for (scratch.order[0..scratch.count]) |kind_value| {
        const kind: usize = kind_value;
        const size = self.real_vulkan.feature_chain_sizes[kind];
        if (size <= 16) continue;
        _ = writeGuestBytes(state, scratch.addresses[kind] + 16, self.real_vulkan.feature_chain_supported[kind][16..size]);
    }
}

pub fn writeRealMemoryProperties(self: anytype, state: anytype, output: u64) void {
    const bytes = state.guestMemory(output, 520) orelse return;
    const src: []const u8 = @as([*]const u8, @ptrCast(&self.real_vulkan.physical_device_memory))[0..520];
    @memcpy(bytes[0..@min(bytes.len, src.len)], src[0..@min(bytes.len, src.len)]);
}

pub fn writeRealMemoryProperties2(self: anytype, state: anytype, output: u64) void {
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

pub fn writeRealQueueFamilies(self: anytype, state: anytype) void {
    const count_address = guest_context.registers(state).rsi;
    if (state.guestMemory(count_address, 4) == null) return;
    if (guest_context.registers(state).rdx == 0) {
        state.write32(count_address, self.real_vulkan.queue_family_count);
        return;
    }
    const requested = state.read32(count_address);
    if (requested == 0) return;
    const actual = @min(requested, self.real_vulkan.queue_family_count);
    const bytes_needed = @as(u64, actual) * @sizeOf(abi.QueueFamilyProperties);
    const bytes = state.guestMemory(guest_context.registers(state).rdx, bytes_needed) orelse return;
    const src: []const u8 = @ptrCast(self.real_vulkan.queue_family_properties[0..actual]);
    @memcpy(bytes[0..@min(bytes.len, src.len)], src[0..@min(bytes.len, src.len)]);
    state.write32(count_address, actual);
}

pub fn guestStackArg(state: anytype, index: u64) u64 {
    return state.read64(guest_context.registers(state).rsp + 8 + index * 8);
}

pub fn guestFloatArgument(state: anytype, index: usize) u32 {
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (@hasField(State, "xmm") and index < guest_context.vectors(state).len) return std.mem.readInt(u32, guest_context.vectors(state)[index][0..4], .little);
    // A few synthetic unit-test states model only GPRs. The fallback keeps
    // those dispatch tests deterministic; real SysV x86-64 calls always
    // arrive through XMM0..XMMn for scalar float arguments.
    return switch (index) {
        0 => @truncate(guest_context.registers(state).rsi),
        1 => @truncate(guest_context.registers(state).rdx),
        else => @truncate(guest_context.registers(state).rcx),
    };
}

pub fn copyGuestStructs(comptime T: type, state: anytype, address: u64, count: u64, destination: []T) bool {
    if (count > destination.len) return false;
    const bytes_count = std.math.mul(u64, count, @sizeOf(T)) catch return false;
    if (count == 0) return true;
    const source = state.guestMemoryConst(address, bytes_count) orelse return false;
    @memcpy(std.mem.sliceAsBytes(destination[0..@as(usize, @intCast(count))]), source);
    return true;
}

pub fn copyGuestBytes(state: anytype, address: u64, count: u64, destination: []u8) bool {
    if (count > destination.len) return false;
    if (count == 0) return true;
    const source = state.guestMemoryConst(address, count) orelse return false;
    @memcpy(destination[0..@as(usize, @intCast(count))], source);
    return true;
}

pub fn graphicsStateTraceEnabled(self: anytype) bool {
    if (!self.graphics_state_trace_configured) {
        self.graphics_state_trace_configured = true;
        if (std.c.getenv("ROSETTE_ELF_GRAPHICS_STATE_DUMP")) |raw| {
            const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
            self.graphics_state_trace_enabled = std.mem.eql(u8, value, "1") or
                std.ascii.eqlIgnoreCase(value, "true") or
                std.ascii.eqlIgnoreCase(value, "yes");
        }
    }
    return self.graphics_state_trace_enabled;
}

pub fn guestOutputTopologyRepairEnabled(self: anytype) bool {
    if (!self.guest_output_topology_repair_configured) {
        self.guest_output_topology_repair_configured = true;
        self.guest_output_topology_repair_enabled = true;
        if (std.c.getenv("ROSETTE_ELF_GUEST_OUTPUT_TOPOLOGY_REPAIR")) |raw| {
            const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
            self.guest_output_topology_repair_enabled = !(std.mem.eql(u8, value, "0") or
                std.ascii.eqlIgnoreCase(value, "false") or
                std.ascii.eqlIgnoreCase(value, "no"));
        }
    }
    return self.guest_output_topology_repair_enabled;
}

pub fn graphicsStateTrackingEnabled(self: anytype) bool {
    return self.graphicsStateTraceEnabled() or self.guestOutputTopologyRepairEnabled();
}

pub fn graphicsStateHash(bytes: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (bytes) |byte| hash = (hash ^ byte) *% 1099511628211;
    return hash;
}

pub fn vulkanTopologyLabel(topology: u32) []const u8 {
    return switch (topology) {
        0 => "point_list",
        1 => "line_list",
        2 => "line_strip",
        VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST => "triangle_list",
        VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP => "triangle_strip",
        5 => "triangle_fan",
        else => "other",
    };
}

pub fn trackedGraphicsPipeline(self: anytype, real: u64) ?*const TrackedGraphicsPipeline {
    if (real == 0) return null;
    const pipeline_lookup = __ForwarderInternals._forwarder_pipeline_lookup;
    const index = if (comptime @typeInfo(@TypeOf(self)).pointer.is_const)
        pipeline_lookup.scan(&self.tracked_graphics_pipelines, real)
    else
        self.tracked_pipeline_lookup.find(&self.tracked_graphics_pipelines, real);
    return &self.tracked_graphics_pipelines[index orelse return null];
}

pub fn trackedPipelineLayout(self: anytype, real: u64) ?*const TrackedPipelineLayout {
    if (real == 0) return null;
    for (&self.tracked_pipeline_layouts) |*record| {
        if (record.real == real) return record;
    }
    return null;
}

pub fn rememberPipelineLayout(self: anytype, real: u64, info: []const u8) void {
    if (real == 0 or info.len < @sizeOf(marshal.PipelineLayoutCreateInfo)) return;
    const root: *const marshal.PipelineLayoutCreateInfo = @ptrCast(@alignCast(info.ptr));
    var metadata: TrackedPipelineLayout = .{ .real = real };
    if (root.push_constant_range_count <= 64) {
        if (root.push_constant_ranges) |pointer| {
            const ranges: [*]const marshal.PushConstantRange = @ptrCast(@alignCast(pointer));
            for (0..@as(usize, @intCast(root.push_constant_range_count))) |index| {
                const range = ranges[index];
                if (range.offset == 0 and range.size >= 16 and
                    (range.stage_flags & VK_SHADER_STAGE_VERTEX_BIT) != 0)
                {
                    metadata.has_vertex_rect_push_constants = true;
                    break;
                }
            }
        }
    }
    for (&self.tracked_pipeline_layouts) |*record| {
        if (record.real == real or record.real == 0) {
            record.* = metadata;
            return;
        }
    }
}

pub fn forgetPipelineLayout(self: anytype, real: u64) void {
    if (real == 0) return;
    for (&self.tracked_pipeline_layouts) |*record| {
        if (record.real == real) record.* = .{};
    }
}

pub fn rectExpandEnabled(self: anytype) bool {
    if (!self.rect_expand_configured) {
        self.rect_expand_configured = true;
        if (std.c.getenv("ROSETTE_VULKAN_RECT_EXPAND")) |raw| {
            const value = std.mem.sliceTo(raw, 0);
            self.rect_expand_enabled = !(std.mem.eql(u8, value, "0") or
                std.ascii.eqlIgnoreCase(value, "false") or
                std.ascii.eqlIgnoreCase(value, "no"));
        }
    }
    return self.rect_expand_enabled;
}

pub fn noteRectangleTransformRefusal(
    self: anytype,
    refusal: gpu_vulkan.rect_list_expand.Refusal,
    synthetic_module: u64,
    spirv_hash: u64,
    code_bytes: usize,
    cull_distance_site: ?gpu_vulkan.rect_list_expand.CullDistanceSite,
) void {
    self.rect_expand_shaders_refused +|= 1;
    self.rect_expand_last_refusal = refusal;
    self.rect_expand_refusal_counts[@intFromEnum(refusal)] +|= 1;
    self.rect_expand_last_refusal_module = synthetic_module;
    self.rect_expand_last_refusal_hash = spirv_hash;
    self.rect_expand_last_refusal_bytes = @truncate(@min(code_bytes, @as(usize, std.math.maxInt(u32))));
    self.rect_expand_last_cull_distance_site = cull_distance_site;
    if (refusal == .cull_distance_output) self.metal_backend_health.noteGap(.rectangle_cull_distance_output);
}

pub fn expandRectangleListShader(self: anytype, info: []u8, synthetic_module: u64, spirv_hash: u64) ?RectExpansion {
    if (!self.rectExpandEnabled()) return null;
    if (info.len < @sizeOf(marshal.ShaderModuleCreateInfo)) return null;
    const root: *marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(info.ptr));
    const code = root.code orelse return null;
    if (root.code_size < 20 or root.code_size % 4 != 0) return null;
    const words: [*]const u32 = @ptrCast(@alignCast(code));
    const source = words[0 .. root.code_size / 4];

    const result = gpu_vulkan.rect_list_expand.expand(std.heap.c_allocator, source) catch {
        self.rect_expand_allocation_failures +|= 1;
        self.rect_expand_last_refusal_module = synthetic_module;
        self.rect_expand_last_refusal_hash = spirv_hash;
        self.rect_expand_last_refusal_bytes = @truncate(@min(root.code_size, @as(usize, std.math.maxInt(u32))));
        return null;
    };
    if (result.refusal != .none) {
        // These are expected in the same module stream as candidate
        // rectangle vertex shaders; keep them separate from transform
        // failures so the final report names actual candidates clearly.
        if (result.refusal == .not_vertex) {
            self.rect_expand_shaders_skipped_non_vertex +|= 1;
            return null;
        }
        if (result.refusal == .already_expanded) {
            self.rect_expand_shaders_skipped_already_expanded +|= 1;
            return null;
        }
        self.noteRectangleTransformRefusal(result.refusal, synthetic_module, spirv_hash, root.code_size, result.cull_distance_site);
        return null;
    }
    if (result.removed_unused_cull_distance) self.rect_expand_shaders_cull_distance_stripped +|= 1;
    const expansion = RectExpansion{
        .words = result.words,
        .original_code = root.code,
        .original_size = root.code_size,
    };
    root.code = @ptrCast(result.words.ptr);
    root.code_size = result.words.len * 4;
    self.rect_expand_shaders_rewritten +|= 1;
    if (self.rect_expand_shaders_rewritten <= 4) machoCapturePrint(
        "macho-processor: RECT EXPAND: vertex shader rewritten words={d}->{d} outputs_combined={d} index_loads_repointed={d} unused_cull_distance_removed={}; Xenia selects kRectangleListAsTriangleStrip on a host with no geometry shader and its SPIR-V translator never implemented it\n",
        .{ source.len, result.words.len, result.combined_outputs, result.repointed_loads, result.removed_unused_cull_distance },
    );
    return expansion;
}

pub fn robustAccessEnabled(self: anytype) bool {
    if (!self.robust_access_configured) {
        self.robust_access_configured = true;
        if (std.c.getenv("ROSETTE_VULKAN_ROBUST_ACCESS")) |raw| {
            const value = std.mem.sliceTo(raw, 0);
            self.robust_access_enabled = !(std.mem.eql(u8, value, "0") or
                std.ascii.eqlIgnoreCase(value, "false") or
                std.ascii.eqlIgnoreCase(value, "off"));
        }
    }
    return self.robust_access_enabled;
}

pub fn correctHdrResolve(self: anytype, info: []u8) !?[]u32 {
    if (!self.fsi_raster.moltenvk) return null;
    if (!self.hdr_resolve_configured) {
        self.hdr_resolve_configured = true;
        if (std.c.getenv("ROSETTE_HDR_RESOLVE")) |raw| {
            const value = std.mem.sliceTo(raw, 0);
            self.hdr_resolve_enabled = !(std.mem.eql(u8, value, "0") or std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "off"));
        }
    }
    if (!self.hdr_resolve_enabled or info.len < @sizeOf(marshal.ShaderModuleCreateInfo)) return null;
    const root: *marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(info.ptr));
    const code = root.code orelse return null;
    if (root.code_size < 20 or root.code_size % 4 != 0) return null;
    const words: [*]const u32 = @ptrCast(@alignCast(code));
    const corrected = try gpu_vulkan.hdr_resolve.rewrite(std.heap.c_allocator, words[0 .. root.code_size / 4]);
    if (corrected.words.len == 0) return null;
    root.code = @ptrCast(corrected.words.ptr);
    root.code_size = corrected.words.len * 4;
    self.hdr_resolve_modules +|= 1;
    self.hdr_resolve_unpacks +|= corrected.unpacks;
    machoCapturePrint("macho-processor: VULKAN HDR RESOLVE MODULE: name={s} unpacks={d}; exact shipped kernel; finite Xenos exponent-31 EDRAM decoded before resolve bias; destination packing unchanged\n", .{ corrected.name, corrected.unpacks });
    return corrected.words;
}

pub fn normalizeFsiPixelFrequency(self: anytype, info: []u8) !?[]u32 {
    if (!self.fsi_raster.moltenvk) return null;
    if (!self.fsi_pixel_frequency_configured) {
        self.fsi_pixel_frequency_configured = true;
        if (std.c.getenv("ROSETTE_FSI_PIXEL_FREQUENCY")) |raw| {
            const value = std.mem.sliceTo(raw, 0);
            self.fsi_pixel_frequency_enabled = !(std.mem.eql(u8, value, "0") or
                std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "off"));
        }
    }
    if (!self.fsi_pixel_frequency_enabled or info.len < @sizeOf(marshal.ShaderModuleCreateInfo)) return null;
    const root: *marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(info.ptr));
    const code = root.code orelse return null;
    if (root.code_size < 20 or root.code_size % 4 != 0) return null;
    const words: [*]const u32 = @ptrCast(@alignCast(code));
    const result = gpu_vulkan.fsi.pixel_frequency.centerCoordinates(std.heap.c_allocator, words[0 .. root.code_size / 4]) catch |err| {
        self.fsi_pixel_frequency_allocation_failures +|= 1;
        return err;
    };
    switch (result.reason) {
        .changed => {
            root.code = @ptrCast(result.words.ptr);
            root.code_size = result.words.len * 4;
            self.fsi_pixel_frequency_changed +|= 1;
            if (self.fsi_pixel_frequency_changed <= 4) machoCapturePrint(
                "macho-processor: VULKAN FSI PIXEL FREQUENCY: centered_coordinate_loads={d}; sample-rate execution and coverage retained; explicit sample inputs unchanged\n",
                .{result.centered_loads},
            );
            return result.words;
        },
        .explicit_sample_input => self.fsi_pixel_frequency_explicit +|= 1,
        .complex_decorations => self.fsi_pixel_frequency_complex +|= 1,
        .invalid, .not_candidate => {},
    }
    return null;
}

pub fn printFsiPixelFrequencyReport(self: anytype) void {
    machoCapturePrint(
        "macho-processor: VULKAN FSI PIXEL FREQUENCY: enabled={} moltenvk={} normalized={d} explicit_sample_preserved={d} complex_preserved={d} allocation_failures={d} driver_rejections={d}; pixel-center coordinates restored; sample capability, coverage and index protection retained\n",
        .{ self.fsi_pixel_frequency_enabled, self.fsi_raster.moltenvk, self.fsi_pixel_frequency_changed, self.fsi_pixel_frequency_explicit, self.fsi_pixel_frequency_complex, self.fsi_pixel_frequency_allocation_failures, self.fsi_pixel_frequency_driver_rejections },
    );
    machoCapturePrint("macho-processor: VULKAN HDR RESOLVE: enabled={} moltenvk={} corrected_modules={d} corrected_unpacks={d} driver_rejections={d}; exact full-resolve identities only; finite source decode before bias, ordinary destination packing retained; module creation is not orb attribution\n", .{ self.hdr_resolve_enabled, self.fsi_raster.moltenvk, self.hdr_resolve_modules, self.hdr_resolve_unpacks, self.hdr_resolve_driver_rejections });
}

pub fn hardenShaderModule(self: anytype, info: []u8, synthetic_module: u64) error{UnsafeShader}!?RobustHardening {
    if (!self.robustAccessEnabled()) return null;
    if (info.len < @sizeOf(marshal.ShaderModuleCreateInfo)) return null;
    const root: *marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(info.ptr));
    const code = root.code orelse return null;
    if (root.code_size < 20 or root.code_size % 4 != 0) return null;
    const words: [*]const u32 = @ptrCast(@alignCast(code));
    const result = gpu_vulkan.robust_access.harden(std.heap.c_allocator, words[0 .. root.code_size / 4]) catch {
        self.robust_access_allocation_failures +|= 1;
        return error.UnsafeShader;
    };
    self.robust_access_stats.add(result.stats);
    if (result.refusal != .none) {
        self.robust_access_modules_refused +|= 1;
        if (self.robust_access_modules_refused <= 8) machoCapturePrint(
            "macho-processor: VULKAN ROBUST ACCESS REFUSED: module=0x{x} reason={s}; shader creation refused before GPU use\n",
            .{ synthetic_module, result.refusal.label() },
        );
        return error.UnsafeShader;
    }
    if (result.stats.unclamped_dynamic_indices != 0) {
        std.heap.c_allocator.free(result.words);
        machoCapturePrint("macho-processor: VULKAN ROBUST ACCESS UNCLAMPED: module=0x{x} dynamic_indices={d}; shader creation refused before GPU use\n", .{ synthetic_module, result.stats.unclamped_dynamic_indices });
        return error.UnsafeShader;
    }
    if (!result.changed()) {
        self.robust_access_modules_unchanged +|= 1;
        return null;
    }
    const hardening = RobustHardening{ .words = result.words };
    root.code = @ptrCast(result.words.ptr);
    root.code_size = result.words.len * 4;
    self.robust_access_modules_hardened +|= 1;
    return hardening;
}

pub fn fsiUpdateShaderBoundsBudget(self: anytype) void {
    const guard = self.fsi_guard orelse return;
    const verified = guard.protected_batching_enabled and self.robust_access_enabled and self.robust_access_modules_hardened != 0 and
        self.robust_access_modules_refused == 0 and self.robust_access_driver_rejections == 0 and
        self.robust_access_stats.unclamped_dynamic_indices == 0 and self.robust_access_allocation_failures == 0;
    guard.monitor.setShaderBoundsVerified(verified);
}

pub fn printRobustAccessReport(self: anytype) void {
    self.shader_host_profile.report();
    if (self.fsi_evidence_io.writer) |writer| writer.report();
    const stats = self.robust_access_stats;
    machoCapturePrint(
        "macho-processor: VULKAN ROBUST ACCESS: enabled={} modules(hardened/unchanged/refused/driver_rejected)={d}/{d}/{d}/{d} clamps(runtime_array/fixed_array/component)={d}/{d}/{d} hoisted_lengths={d} unclamped_dynamic_indices={d} interface_indices={d} allocation_failures={d} uniform_zero_loads={d}; buffer indices are bounded and out-of-range uniform loads return zero; failed hardening refuses shader creation\n",
        .{ self.robust_access_enabled, self.robust_access_modules_hardened, self.robust_access_modules_unchanged, self.robust_access_modules_refused, self.robust_access_driver_rejections, stats.runtime_array_clamps, stats.fixed_array_clamps, stats.component_clamps, stats.hoisted_lengths, stats.unclamped_dynamic_indices, stats.interface_indices, self.robust_access_allocation_failures, stats.uniform_zero_loads },
    );
}

pub fn noteRectangleExpandedModule(self: anytype, synthetic_module: u64) void {
    if (self.rect_expand_module_count == self.rect_expand_modules.len) {
        self.rect_expand_module_overflow +|= 1;
        return;
    }
    self.rect_expand_modules[self.rect_expand_module_count] = synthetic_module;
    self.rect_expand_module_count += 1;
}

pub fn rectangleExpandedModule(self: anytype, synthetic_module: u64) bool {
    for (self.rect_expand_modules[0..self.rect_expand_module_count]) |handle| {
        if (handle == synthetic_module) return true;
    }
    return false;
}

pub fn noteRectangleExpandedPipeline(self: anytype, synthetic_pipeline: u64) void {
    switch (self.rect_expand_pipeline_registry.insert(synthetic_pipeline)) {
        .inserted => self.rect_expand_pipelines_marked +|= 1,
        .existing => {},
        .full => self.rect_expand_pipeline_overflow +|= 1,
    }
}

pub fn forgetRectangleExpandedPipeline(self: anytype, synthetic_pipeline: u64) void {
    _ = self.rect_expand_pipeline_registry.remove(synthetic_pipeline);
}

pub fn trackPresentCompletion(self: anytype, queue: abi.Queue) bool {
    const device = self.real_vulkan.device orelse return false;
    const functions = &self.real_vulkan.fn_ptrs;
    const create = functions.create_fence orelse return false;
    const status_of = functions.get_fence_status orelse return false;
    const reset = functions.reset_fences orelse return false;
    const submit = functions.queue_submit orelse return false;
    self.present_completion_async +|= 1;
    if (self.present_completion_fence == 0) {
        const info = abi.FenceCreateInfo{};
        var fence: abi.Fence = 0;
        const created = create(device, &info, null, &fence);
        if (created != abi.SUCCESS or fence == 0) {
            self.noteRealVulkanResult(created, "vkCreateFence(present-completion)");
            self.present_completion_failures +|= 1;
            return false;
        }
        self.present_completion_fence = fence;
    }
    if (self.present_completion_fence_pending) {
        const status = status_of(device, self.present_completion_fence);
        if (status == abi.SUCCESS) {
            self.present_completion_fence_pending = false;
            self.present_completion_fence_signals +|= 1;
            self.present_completion_confirmed = @max(self.present_completion_confirmed, self.present_completion_fence_target);
        } else if (status != abi.NOT_READY) {
            self.noteRealVulkanResult(status, "vkGetFenceStatus(present-completion)");
            self.present_completion_failures +|= 1;
            self.present_completion_fence_pending = false;
            return false;
        }
    }
    if (!self.present_completion_fence_pending) {
        const reset_result = reset(device, 1, @ptrCast(&self.present_completion_fence));
        const submitted = if (reset_result == abi.SUCCESS) submit(queue, 0, null, self.present_completion_fence) else reset_result;
        if (submitted != abi.SUCCESS) {
            self.noteRealVulkanResult(submitted, "vkQueueSubmit(present-completion)");
            self.present_completion_failures +|= 1;
            return false;
        }
        self.present_completion_fence_pending = true;
        // The present in hand is counted just after this returns.
        self.present_completion_fence_target = self.vulkan_real_presents +| 1;
    }
    return true;
}

pub fn rectExpandCommandState(self: anytype, command_buffer: u64) *RectExpandCommandState {
    for (&self.rect_expand_command_states) |*entry| {
        if (entry.command_buffer == command_buffer) return entry;
    }
    const slot = &self.rect_expand_command_states[self.rect_expand_command_state_next];
    self.rect_expand_command_state_next = (self.rect_expand_command_state_next + 1) % RECT_EXPAND_COMMAND_STATES;
    slot.* = .{ .command_buffer = command_buffer };
    return slot;
}

pub fn rectangleExpandedPipeline(self: anytype, synthetic_pipeline: u64) bool {
    return self.rect_expand_pipeline_registry.contains(synthetic_pipeline);
}

pub fn isRectangleStripPipeline(root: *const abi.GraphicsPipelineCreateInfo) bool {
    const input_assembly = root.input_assembly_state orelse return false;
    if (input_assembly.topology != VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP) return false;
    return input_assembly.primitive_restart_enable != 0;
}

pub fn isGuestOutputPaintPipeline(self: anytype, root: *const abi.GraphicsPipelineCreateInfo) bool {
    const input_assembly = root.input_assembly_state orelse return false;
    if (input_assembly.topology != VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) return false;
    if (root.stage_count != 2 or root.stages == null) return false;
    const vertex_input = root.vertex_input_state orelse return false;
    if (vertex_input.vertex_binding_description_count != 0 or vertex_input.vertex_attribute_description_count != 0) return false;
    if (root.tessellation_state != null) return false;
    const viewport = root.viewport_state orelse return false;
    if (viewport.viewport_count != 1 or viewport.scissor_count != 1) return false;
    var dynamic_viewport = false;
    var dynamic_scissor = false;
    if (root.dynamic_state) |dynamic| {
        if (dynamic.dynamic_states) |states| {
            for (0..@as(usize, @intCast(dynamic.dynamic_state_count))) |index| {
                switch (states[index]) {
                    VK_DYNAMIC_STATE_VIEWPORT => dynamic_viewport = true,
                    VK_DYNAMIC_STATE_SCISSOR => dynamic_scissor = true,
                    else => {},
                }
            }
        }
    }
    if (!dynamic_viewport or !dynamic_scissor) return false;
    if (root.rasterization_state) |rasterization| {
        if (rasterization.rasterizer_discard_enable != 0 or rasterization.polygon_mode != 0 or rasterization.cull_mode != 0) return false;
    }
    if (root.multisample_state) |multisample| {
        if (multisample.rasterization_samples != abi.SAMPLE_COUNT_1_BIT) return false;
    }
    if (root.depth_stencil_state) |depth_stencil| {
        if (depth_stencil.depth_test_enable != 0 or depth_stencil.depth_write_enable != 0 or depth_stencil.stencil_test_enable != 0) return false;
    }
    const color_blend = root.color_blend_state orelse return false;
    if (color_blend.attachment_count != 1) return false;
    const layout = self.trackedPipelineLayout(root.layout) orelse return false;
    return layout.has_vertex_rect_push_constants;
}

pub fn rememberGraphicsPipeline(self: anytype, real: u64, root: *const abi.GraphicsPipelineCreateInfo, repair_real: u64, guest_output_candidate: bool, fsi: fsi_diagnostics.PipelineIdentity) void {
    if (real == 0) return;
    var metadata: TrackedGraphicsPipeline = .{
        .real = real,
        .layout = root.layout,
        .repair_real = repair_real,
        .guest_output_candidate = guest_output_candidate,
        .fsi = fsi,
        .stage_count = root.stage_count,
    };
    if (root.input_assembly_state) |pointer| {
        metadata.topology = pointer.topology;
        metadata.topology_known = true;
    }
    if (root.viewport_state) |pointer| {
        metadata.viewport_count = pointer.viewport_count;
        metadata.scissor_count = pointer.scissor_count;
    }
    if (root.rasterization_state) |pointer| {
        metadata.cull_mode = pointer.cull_mode;
        metadata.front_face = pointer.front_face;
    }
    if (root.dynamic_state) |pointer| {
        if (pointer.dynamic_states) |states| {
            for (0..@as(usize, @intCast(pointer.dynamic_state_count))) |index| {
                switch (states[index]) {
                    VK_DYNAMIC_STATE_VIEWPORT => metadata.dynamic_viewport = true,
                    VK_DYNAMIC_STATE_SCISSOR => metadata.dynamic_scissor = true,
                    else => {},
                }
            }
        }
    }
    for (&self.tracked_graphics_pipelines) |*record| {
        if (record.real == real or record.real == 0) {
            record.* = metadata;
            self.tracked_pipeline_lookup.invalidate();
            return;
        }
    }
    self.graphics_state_trace_pipeline_overflow +|= 1;
}

pub fn forgetGraphicsPipeline(self: anytype, real: u64) void {
    if (self.native_texture_state) |native| native.forgetPipeline(&self.real_vulkan, real);
    if (real == 0) return;
    _ = self.fsi_raster.pipelines.remove(real);
    _ = self.fsi_raster.isolated_pipelines.remove(real);
    self.vulkan_fsi_tracker.forgetPipeline(real);
    for (&self.tracked_graphics_pipelines) |*record| {
        if (record.real == real) record.* = .{};
    }
    self.tracked_pipeline_lookup.invalidate();
}

pub fn noteCommandPipelineState(self: anytype, command_buffer: u64, guest_pipeline: u64, real_pipeline: u64, bind_point: u64) void {
    if (@as(u32, @truncate(bind_point)) == VK_PIPELINE_BIND_POINT_GRAPHICS) {
        self.vulkan_fsi_tracker.bindPipeline(command_buffer, real_pipeline);
        if (self.vulkan_fsi_tracker.isFsiPipelineBound(command_buffer)) {
            if (self.commandPassTarget(command_buffer)) |target| {
                if (target.image != 0) {
                    if (!self.vulkan_fsi_tracker.targetMatches(command_buffer, target.image, target.source)) {
                        self.vulkan_fsi_tracker.setTarget(command_buffer, target.image, target.source);
                        self.vulkan_fsi_tracker.noteTargetPropagationOnBind();
                    }
                } else if (target.source == .dynamic_rendering) {
                    self.vulkan_fsi_tracker.noteDynamicTargetUnresolved();
                }
            }
        }
    }
    if (!self.graphicsStateTrackingEnabled()) return;
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    const trace = &record.graphics_state;
    trace.pipeline_guest = guest_pipeline;
    trace.pipeline_real = real_pipeline;
    trace.pipeline_original_real = real_pipeline;
    trace.pipeline_repair_real = 0;
    trace.pipeline_guest_output_candidate = false;
    trace.pipeline_repair_applied = false;
    trace.pipeline_layout_real = 0;
    trace.pipeline_bind_point = @intCast(bind_point);
    trace.pipeline_bound = true;
    trace.pipeline_topology_known = false;
    // The module function, not the const `Forwarder` wrapper: the memo
    // needs the mutable forwarder to record what the scan found.
    if (trackedGraphicsPipeline(self, real_pipeline)) |metadata| {
        trace.pipeline_layout_real = metadata.layout;
        trace.pipeline_repair_real = metadata.repair_real;
        trace.pipeline_guest_output_candidate = metadata.guest_output_candidate;
        trace.pipeline_topology = metadata.topology;
        trace.pipeline_topology_known = metadata.topology_known;
        trace.pipeline_stage_count = metadata.stage_count;
        trace.pipeline_dynamic_viewport = metadata.dynamic_viewport;
        trace.pipeline_dynamic_scissor = metadata.dynamic_scissor;
    } else if (self.graphicsStateTraceEnabled()) {
        self.graphics_state_trace_unknown_pipeline +|= 1;
    }
}

pub fn noteCommandViewport(self: anytype, command_buffer: u64, first: u64, count: u64, values: []const abi.Viewport) void {
    if (!self.graphicsStateTraceEnabled()) return;
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    const trace = &record.graphics_state;
    trace.viewport_first = @intCast(first);
    trace.viewport_count = @intCast(count);
    if (first == 0) {
        trace.viewport_valid = count != 0 and values.len != 0;
        if (trace.viewport_valid) trace.viewport = values[0];
    }
}

pub fn noteCommandScissor(self: anytype, command_buffer: u64, first: u64, count: u64, values: []const abi.Rect2D) void {
    if (!self.graphicsStateTraceEnabled()) return;
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    const trace = &record.graphics_state;
    trace.scissor_first = @intCast(first);
    trace.scissor_count = @intCast(count);
    if (first == 0) {
        trace.scissor_valid = count != 0 and values.len != 0;
        if (trace.scissor_valid) trace.scissor = values[0];
    }
}

pub fn noteCommandPushConstants(self: anytype, command_buffer: u64, guest_layout: u64, real_layout: u64, stage_flags: u64, offset: u64, size: u64, bytes: []const u8) void {
    if (!self.graphicsStateTrackingEnabled()) return;
    const record = self.mutableCommandTargets(command_buffer) orelse return;
    const trace = &record.graphics_state;
    if (self.graphicsStateTraceEnabled()) self.graphics_state_trace_push_constants +|= 1;
    trace.push_constants_valid = true;
    trace.push_layout_guest = guest_layout;
    trace.push_layout_real = real_layout;
    trace.push_stage_flags = @intCast(stage_flags);
    trace.push_offset = @intCast(offset);
    trace.push_size = @intCast(size);
    trace.push_hash = graphicsStateHash(bytes);
    trace.push_words = [_]u32{0} ** 4;
    for (0..4) |index| {
        const at = index * 4;
        if (at + 4 <= bytes.len) trace.push_words[index] = std.mem.readInt(u32, bytes[at..][0..4], .little);
    }
    // Xenia's guest-output rectangle is the first 16 bytes of the vertex
    // push-constant range. Preserve it when a later fragment push updates
    // the same command buffer with sharpening/resampling constants.
    if (offset == 0 and size >= 16) {
        trace.rect_push_valid = true;
        trace.rect_push_hash = graphicsStateHash(bytes[0..16]);
        for (0..4) |index| trace.rect_push_words[index] = std.mem.readInt(u32, bytes[index * 4 ..][0..4], .little);
    }
}

pub fn repairGuestOutputTopology(
    self: anytype,
    command_buffer_guest: u64,
    command_buffer_real: abi.CommandBuffer,
    vertex_count: u64,
    instance_count: u64,
    first_vertex: u64,
    first_instance: u64,
) void {
    if (!self.guestOutputTopologyRepairEnabled() or vertex_count != 4 or instance_count != 1 or first_vertex != 0 or first_instance != 0) return;
    var repair_pipeline: u64 = 0;
    var bind_point: u32 = VK_PIPELINE_BIND_POINT_GRAPHICS;
    var original_pipeline: u64 = 0;
    var guest_pipeline: u64 = 0;
    var push_layout: u64 = 0;
    if (self.mutableCommandTargets(command_buffer_guest)) |record| {
        const trace = &record.graphics_state;
        if (!trace.pipeline_bound or trace.pipeline_bind_point != VK_PIPELINE_BIND_POINT_GRAPHICS or
            !trace.pipeline_guest_output_candidate or trace.pipeline_repair_real == 0 or
            trace.pipeline_repair_applied or !trace.rect_push_valid or
            trace.push_layout_real != trace.pipeline_layout_real)
        {
            return;
        }
        const rect_x: f32 = @bitCast(trace.rect_push_words[0]);
        const rect_y: f32 = @bitCast(trace.rect_push_words[1]);
        const rect_width: f32 = @bitCast(trace.rect_push_words[2]);
        const rect_height: f32 = @bitCast(trace.rect_push_words[3]);
        if (!std.math.isFinite(rect_x) or !std.math.isFinite(rect_y) or
            !std.math.isFinite(rect_width) or !std.math.isFinite(rect_height) or
            rect_width <= 0 or rect_height <= 0 or
            @abs(rect_x) > 65536 or @abs(rect_y) > 65536 or
            @abs(rect_width) > 65536 or @abs(rect_height) > 65536)
        {
            return;
        }
        repair_pipeline = trace.pipeline_repair_real;
        bind_point = trace.pipeline_bind_point;
        original_pipeline = trace.pipeline_original_real;
        guest_pipeline = trace.pipeline_guest;
        push_layout = trace.push_layout_real;
    } else return;

    const function = self.real_vulkan.fn_ptrs.cmd_bind_pipeline orelse {
        self.graphics_topology_repair_bind_failures +|= 1;
        return;
    };
    self.callNativeVulkanCommand(function, .{ command_buffer_real, bind_point, repair_pipeline });
    if (self.mutableCommandTargets(command_buffer_guest)) |record| {
        const trace = &record.graphics_state;
        // A command-buffer record can only be replaced by another bind on
        // the same guest thread. Keep the guard so a late state mutation
        // cannot label an unrelated pipeline as repaired.
        if (trace.pipeline_original_real == original_pipeline and trace.pipeline_guest == guest_pipeline and
            trace.push_layout_real == push_layout and trace.pipeline_repair_real == repair_pipeline)
        {
            trace.pipeline_real = repair_pipeline;
            trace.pipeline_topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
            trace.pipeline_topology_known = true;
            trace.pipeline_repair_applied = true;
        }
    }
    self.graphics_topology_repairs +|= 1;
    if (self.graphics_topology_repairs <= 8 or (self.graphics_topology_repairs & (self.graphics_topology_repairs - 1)) == 0) {
        machoCapturePrint(
            "macho-processor: Vulkan GUEST OUTPUT TOPOLOGY REPAIR: command_buffer=0x{x} guest_pipeline=0x{x} original_real=0x{x} repair_real=0x{x} topology=triangle_list->triangle_strip rect_push_layout=0x{x} repair_count={d}\n",
            .{ command_buffer_guest, guest_pipeline, original_pipeline, repair_pipeline, push_layout, self.graphics_topology_repairs },
        );
    }
}

pub fn fsiGuardInstance(self: anytype) ?*FsiGuard {
    if (self.fsi_guard) |guard| return guard;
    if (self.fsi_guard_refused) return null;
    if (std.c.getenv("ROSETTE_FSI_WATCHDOG_GUARD")) |raw| {
        const value = std.mem.span(raw);
        if (std.mem.eql(u8, value, "0") or std.ascii.eqlIgnoreCase(value, "off")) {
            self.fsi_guard_refused = true;
            machoCapturePrint("macho-processor: VULKAN FSI GUARD: disabled by ROSETTE_FSI_WATCHDOG_GUARD={s}; FSI command buffers go to the driver whole and untimed\n", .{value});
            return null;
        }
    }
    const guard = std.heap.page_allocator.create(FsiGuard) catch {
        self.fsi_guard_refused = true;
        machoCapturePrint("macho-processor: VULKAN FSI GUARD: its state could not be allocated; FSI command buffers go to the driver whole and untimed\n", .{});
        return null;
    };
    guard.* = .{};
    if (std.c.getenv("ROSETTE_FSI_SMALL_CHUNK_SYNC")) |raw| {
        const value = std.mem.span(raw);
        self.fsi_small_chunk_sync = !(std.mem.eql(u8, value, "0") or
            std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "off"));
    }
    if (std.c.getenv("ROSETTE_FSI_ADAPTIVE_BATCHING")) |raw| {
        const value = std.mem.span(raw);
        guard.protected_batching_enabled = !(std.mem.eql(u8, value, "0") or
            std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "off"));
    }
    self.fsi_guard = guard;
    self.fsiUpdateShaderBoundsBudget();
    return guard;
}

pub fn fsiArmedGuard(self: anytype) ?*FsiGuard {
    const guard = self.fsi_guard orelse return null;
    return if (guard.armed) guard else null;
}

pub fn fsiDirectoryEntry(guard: *FsiGuard, guest: u64) ?*FsiCommandBufferEntry {
    if (guest == 0) return null;
    for (&guard.directory) |*entry| {
        if (entry.guest == guest) return entry;
    }
    return null;
}

pub fn fsiNoteCommandBuffersAllocated(self: anytype, synthetics: []const u64, guest_pool: u64, level: u32) void {
    self.fsi_raster.allocated(synthetics, guest_pool, level == abi.COMMAND_BUFFER_LEVEL_PRIMARY);
    const guard = self.fsiGuardInstance() orelse return;
    outer: for (synthetics) |guest| {
        for (&guard.directory) |*entry| {
            if (entry.guest == 0 or entry.guest == guest) {
                entry.* = .{ .guest = guest, .guest_pool = guest_pool, .primary = level == abi.COMMAND_BUFFER_LEVEL_PRIMARY };
                continue :outer;
            }
        }
        guard.directory_overflow +|= 1;
    }
}

pub fn fsiRecording(self: anytype, guest: u64) ?*fsi_chain.Recording {
    const guard = self.fsi_guard orelse return null;
    if (guest == 0) return null;
    for (&guard.recordings) |*recording| {
        if (recording.guest == guest) return recording;
    }
    return null;
}

pub fn fsiReleaseRecording(guard: *FsiGuard, recording: *fsi_chain.Recording) void {
    gpu_vulkan.fsi.recycling.release(&guard.chunk_pool, recording);
}

pub fn fsiBeginRecording(self: anytype, guest: u64, own: abi.CommandBuffer, usage_flags: u32, has_inheritance: bool) void {
    if (self.fsi_raster.command(guest)) |command| command.reset(has_inheritance);
    if (self.fsi_guard) |guard| {
        // Beginning a command buffer resets it, whether or not it is followed.
        for (&guard.recordings) |*recording| {
            if (recording.guest == guest) fsiReleaseRecording(guard, recording);
        }
    }
    const guard = self.fsiArmedGuard() orelse return;
    var slot: ?*fsi_chain.Recording = null;
    for (&guard.recordings) |*recording| {
        if (recording.guest == 0) {
            slot = recording;
            break;
        }
    }
    const recording = slot orelse {
        guard.recording_overflow +|= 1;
        return;
    };
    const directory = fsiDirectoryEntry(guard, guest);
    // A command buffer the bridge did not see allocated, or one begun
    // with inheritance information, is never split.
    const primary = !has_inheritance and directory != null and directory.?.primary;
    recording.begin(guest, @intFromPtr(own), if (directory) |entry| entry.guest_pool else 0, usage_flags, primary);
}

pub fn fsiForgetRecording(self: anytype, guest: u64) void {
    if (self.fsi_raster.command(guest)) |command| command.reset(false);
    const guard = self.fsi_guard orelse return;
    if (self.fsiRecording(guest)) |recording| fsiReleaseRecording(guard, recording);
}

pub fn fsiForgetCommandBuffer(self: anytype, guest: u64) void {
    self.fsiForgetRecording(guest);
    _ = self.fsi_raster.commands.remove(guest);
    const guard = self.fsi_guard orelse return;
    if (fsiDirectoryEntry(guard, guest)) |entry| entry.* = .{};
}

pub fn fsiResetCommandPool(self: anytype, guest_pool: u64, destroyed: bool) void {
    self.fsi_raster.forgetPool(guest_pool, destroyed);
    const guard = self.fsi_guard orelse return;
    if (guest_pool == 0) return;
    for (&guard.recordings) |*recording| {
        if (recording.guest != 0 and recording.guest_pool == guest_pool) fsiReleaseRecording(guard, recording);
    }
    if (!destroyed) return;
    for (&guard.directory) |*entry| {
        if (entry.guest != 0 and entry.guest_pool == guest_pool) entry.* = .{};
    }
}

pub fn fsiCommandTarget(self: anytype, guest: u64, own: abi.CommandBuffer) abi.CommandBuffer {
    const recording = self.fsiRecording(guest) orelse return own;
    if (recording.chunk_count == 0) return own;
    return @ptrFromInt(recording.target());
}

pub fn fsiShadow(self: anytype, guest: u64) ?*fsi_chain.Shadow {
    _ = self.fsiArmedGuard() orelse return null;
    const recording = self.fsiRecording(guest) orelse return null;
    return &recording.shadow;
}

pub fn fsiNoteShadowBlock(self: anytype, guest: u64, block: fsi_chain.Block) void {
    if (block == .none) return;
    if (self.fsiRecording(guest)) |recording| recording.noteBlock(block);
}

pub fn fsiNoteRenderPassCreated(self: anytype, real_render_pass: u64, info: []const u8) void {
    if (self.fsi_raster.moltenvk and info.len >= @sizeOf(marshal.RenderPassCreateInfo)) {
        var root: marshal.RenderPassCreateInfo = undefined;
        @memcpy(std.mem.asBytes(&root), info[0..@sizeOf(marshal.RenderPassCreateInfo)]);
        if (!self.fsi_raster.capturePass(real_render_pass, &root)) {
            self.fsi_raster.allocation_failed = true;
            machoCapturePrint("macho-processor: VULKAN FSI RASTERIZATION: render-pass registry exhausted; FSI pipeline creation will refuse an untracked pass\n", .{});
        }
    }
    const shape = fsi_contract.RenderPassShape.fromCreateInfoBytes(info) orelse return;
    if (!shape.canBeSplit()) return;
    const guard = self.fsiGuardInstance() orelse return;
    if (guard.splittable_render_pass_count < guard.splittable_render_passes.len) {
        guard.splittable_render_passes[guard.splittable_render_pass_count] = real_render_pass;
        guard.splittable_render_pass_count += 1;
    } else {
        guard.splittable_render_pass_overflow +|= 1;
    }
    if (!shape.isXeniaFsi()) return;
    guard.xenia_fsi_render_passes +|= 1;
    if (guard.armed) return;
    guard.armed = true;
    machoCapturePrint(
        "macho-processor: VULKAN FSI CONTRACT: render pass recognised real=0x{x} attachments={d} subpasses={d} dependencies={d}; Xenia selected its fragment-shader-interlock backend, so the MoltenVK/Metal guard is armed: each FSI chunk has at most {d} draws and {d} sample-work units (scissor pixels times samples), with no more than {d} timed command buffers queued (ROSETTE_FSI_WATCHDOG_GUARD=0 disables this)\n",
        .{ real_render_pass, shape.attachment_count, shape.subpass_count, shape.dependency_count, guard.monitor.capValue(), guard.monitor.sampleWorkCapValue(), fsi_timing.max_in_flight_segments },
    );
}

pub fn fsiForgetRenderPass(self: anytype, real_render_pass: u64) void {
    if (self.fsi_raster.findPass(real_render_pass)) |pass| {
        if (self.real_vulkan.fn_ptrs.destroy_render_pass) |destroy| {
            for (pass.variants[1..]) |variant| {
                if (variant != 0) destroy(self.real_vulkan.device, variant, null);
            }
        }
        pass.* = .{};
    }
    const guard = self.fsi_guard orelse return;
    var index: usize = 0;
    while (index < guard.splittable_render_pass_count) {
        if (guard.splittable_render_passes[index] == real_render_pass) {
            guard.splittable_render_pass_count -= 1;
            guard.splittable_render_passes[index] = guard.splittable_render_passes[guard.splittable_render_pass_count];
            continue;
        }
        index += 1;
    }
}

pub fn fsiRenderPassSplittable(guard: *const FsiGuard, real_render_pass: u64) bool {
    for (guard.splittable_render_passes[0..guard.splittable_render_pass_count]) |handle| {
        if (handle == real_render_pass) return true;
    }
    return false;
}

pub fn fsiNoteFramebufferCreated(self: anytype, info: []const u8) void {
    const guard = self.fsi_guard orelse return;
    const shape = fsi_contract.FramebufferShape.fromCreateInfoBytes(info) orelse return;
    if (!shape.isXeniaFsi()) return;
    guard.xenia_fsi_framebuffers +|= 1;
    guard.framebuffer_width = shape.width;
    guard.framebuffer_height = shape.height;
    if (guard.xenia_fsi_framebuffers == 1) machoCapturePrint(
        "macho-processor: VULKAN FSI CONTRACT: framebuffer recognised {d}x{d} attachments=0; Xenia begins every FSI pass with this whole area as its render area, so only a draw's scissor bounds how many interlocked fragments a triangle produces ({d} pixels unclipped, against 737,280 for Halo 3's 1152x640 picture)\n",
        .{ shape.width, shape.height, shape.pixels() },
    );
}

pub fn fsiNoteBeginRenderPass(self: anytype, guest: u64, begin: *const abi.RenderPassBeginInfo, contents: u32) void {
    const original = if (self.fsi_raster.findPass(begin.render_pass)) |pass| pass.original else begin.render_pass;
    if (self.fsi_raster.command(guest)) |command| {
        command.beginPass(if (self.fsi_raster.findPass(begin.render_pass) != null) original else 0, begin, contents);
    }
    const guard = self.fsiArmedGuard() orelse return;
    const recording = self.fsiRecording(guest) orelse return;
    recording.beginPass(.{
        .render_pass = begin.render_pass,
        .framebuffer = begin.framebuffer,
        .render_area = begin.render_area,
    }, fsiRenderPassSplittable(guard, original), contents);
}

pub fn fsiRasterPipelinePass(self: anytype, original: u64, samples: u32) PipelineMarshalFailure!u64 {
    if (!self.fsi_raster.moltenvk) return 0;
    const pass = self.fsi_raster.findPass(original) orelse return error.FsiRasterizationUnavailable;
    const slot = fsi_rasterization.sampleSlot(samples) orelse return error.FsiRasterizationUnavailable;
    if (pass.variants[slot] != 0) return pass.variants[slot];
    const create = self.real_vulkan.fn_ptrs.create_render_pass orelse return error.FsiRasterizationUnavailable;
    var info = pass.createInfo();
    var variant: u64 = 0;
    const result = create(self.real_vulkan.device, &info, null, &variant);
    if (result != abi.SUCCESS or variant == 0) {
        self.fsi_raster.refusals +|= 1;
        machoCapturePrint("macho-processor: VULKAN FSI RASTERIZATION: variant creation failed samples={d} original=0x{x} VkResult={d}\n", .{ samples, original, result });
        return error.FsiRasterizationUnavailable;
    }
    pass.variants[slot] = variant;
    self.fsi_raster.variants_created +|= 1;
    machoCapturePrint("macho-processor: VULKAN FSI RASTERIZATION: samples={d} original=0x{x} native_variant=0x{x}; this attachment-less pass is used only by pipelines with this sample count, so MoltenVK's creation-time defaultRasterSampleCount cannot change other draws' coverage\n", .{ samples, original, variant });
    return variant;
}

pub fn fsiRasterBeforeCommand(self: anytype, guest: u64, name_hash: u64, name: []const u8) bool {
    if (!self.fsi_raster.moltenvk) return true;
    const command = self.fsi_raster.command(guest) orelse return !self.fsi_raster.allocation_failed;
    if (command.failed) return false;
    if (fsiCommandClass(name_hash, name) == .draw and command.bound_pass != 0 and !command.primary and command.has_inheritance) {
        command.failed = true;
        self.fsi_raster.refusals +|= 1;
        machoCapturePrint("macho-processor: VULKAN FSI RASTERIZATION: inherited secondary FSI draw refused command=0x{x}; its primary's raster sample count cannot be selected while recording a secondary buffer\n", .{guest});
        return false;
    }
    if (fsiCommandClass(name_hash, name) == .draw and command.needsRestart()) {
        const pass = self.fsi_raster.findPass(command.bound_pass);
        if (!command.canRestart() or pass == null or pass.?.original != command.original_pass or
            self.real_vulkan.fn_ptrs.cmd_end_render_pass == null or self.real_vulkan.fn_ptrs.cmd_begin_render_pass == null)
        {
            command.failed = true;
            self.fsi_raster.refusals +|= 1;
            machoCapturePrint("macho-processor: VULKAN FSI RASTERIZATION: incompatible sample-count transition refused command=0x{x} active_pass=0x{x} required_pass=0x{x} primary={} queries={d} conditional={}; vkEndCommandBuffer will reject this recording\n", .{ guest, command.active_pass, command.bound_pass, command.primary, command.active_queries, command.conditional });
            return false;
        }
        const own = self.real_vulkan.realCommandBuffer(guest) orelse return false;
        const target = self.fsiCommandTarget(guest, own);
        _ = self.drainAsyncVulkanCommandsIfPending();
        const begin = abi.RenderPassBeginInfo{ .render_pass = command.bound_pass, .framebuffer = command.framebuffer, .render_area = command.area };
        self.real_vulkan.fn_ptrs.cmd_end_render_pass.?(target);
        self.real_vulkan.fn_ptrs.cmd_begin_render_pass.?(target, &begin, 0);
        command.active_pass = command.bound_pass;
        // A later watchdog continuation must reopen the selected variant,
        // rather than returning to the guest's default 1x pass.
        if (self.fsiRecording(guest)) |recording| recording.pass.render_pass = command.active_pass;
        self.fsi_raster.restarts +|= 1;
    } else if (std.mem.eql(u8, name, "vkCmdEndRenderPass") or std.mem.startsWith(u8, name, "vkCmdEndRenderPass2")) {
        command.endPass();
    } else if (std.mem.eql(u8, name, "vkCmdBeginQuery") or std.mem.eql(u8, name, "vkCmdBeginQueryIndexedEXT")) {
        command.active_queries +|= 1;
    } else if (std.mem.eql(u8, name, "vkCmdEndQuery") or std.mem.eql(u8, name, "vkCmdEndQueryIndexedEXT")) {
        command.active_queries -|= 1;
    } else if (std.mem.eql(u8, name, "vkCmdBeginConditionalRenderingEXT")) {
        command.conditional = true;
    } else if (std.mem.eql(u8, name, "vkCmdEndConditionalRenderingEXT")) {
        command.conditional = false;
    }
    return true;
}
