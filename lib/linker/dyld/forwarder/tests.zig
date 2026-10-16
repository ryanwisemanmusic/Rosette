// Tests for the dynamic library forwarder facade and its Vulkan bridge.
const forwarder_root = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = forwarder_root.__ForwarderInternals;
const Forwarder = forwarder_root.Forwarder;
const BridgeCapabilityScratch = __ForwarderInternals._BridgeCapabilityScratch;
const FeatureChainScratch = __ForwarderInternals._FeatureChainScratch;
const FsiCommandClass = __ForwarderInternals._FsiCommandClass;
const FsiGuestChainStatus = __ForwarderInternals._FsiGuestChainStatus;
const FsiSegment = __ForwarderInternals._FsiSegment;
const GUEST_LIBRARY_HANDLE_BASE = __ForwarderInternals._GUEST_LIBRARY_HANDLE_BASE;
const GUEST_SYMBOL_THUNK_BASE = __ForwarderInternals._GUEST_SYMBOL_THUNK_BASE;
const GuestSymbolKind = __ForwarderInternals._GuestSymbolKind;
const HandleMap = __ForwarderInternals._HandleMap;
const HostFrameCaptureResolver = __ForwarderInternals._HostFrameCaptureResolver;
const LibraryClass = __ForwarderInternals._LibraryClass;
const MAX_SURFACE_ENUMERATION = __ForwarderInternals._MAX_SURFACE_ENUMERATION;
const MAX_VULKAN_RESOURCES = __ForwarderInternals._MAX_VULKAN_RESOURCES;
const PIXEL_PROBE_CONTENT_SAMPLES = __ForwarderInternals._PIXEL_PROBE_CONTENT_SAMPLES;
const PixelProbeState = __ForwarderInternals._PixelProbeState;
const RTLD_DEFAULT_HANDLE = __ForwarderInternals._RTLD_DEFAULT_HANDLE;
const RTLD_LAZY = __ForwarderInternals._RTLD_LAZY;
const RTLD_LOCAL = __ForwarderInternals._RTLD_LOCAL;
const SYNTHETIC_DEBUG_MESSENGER_HANDLE = __ForwarderInternals._SYNTHETIC_DEBUG_MESSENGER_HANDLE;
const SYNTHETIC_PHYSICAL_DEVICE_HANDLE = __ForwarderInternals._SYNTHETIC_PHYSICAL_DEVICE_HANDLE;
const Signature = __ForwarderInternals._Signature;
const VK_DYNAMIC_STATE_SCISSOR = __ForwarderInternals._VK_DYNAMIC_STATE_SCISSOR;
const VK_DYNAMIC_STATE_VIEWPORT = __ForwarderInternals._VK_DYNAMIC_STATE_VIEWPORT;
const VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET;
const VK_IMAGE_CREATE_INFO_EXTENT_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_EXTENT_OFFSET;
const VK_IMAGE_CREATE_INFO_FORMAT_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_FORMAT_OFFSET;
const VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET;
const VK_PHYSICAL_DEVICE_LIMITS_OFFSET = __ForwarderInternals._VK_PHYSICAL_DEVICE_LIMITS_OFFSET;
const VK_PHYSICAL_DEVICE_PROPERTIES_SIZE = __ForwarderInternals._VK_PHYSICAL_DEVICE_PROPERTIES_SIZE;
const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST = __ForwarderInternals._VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP = __ForwarderInternals._VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
const VK_SHADER_STAGE_VERTEX_BIT = __ForwarderInternals._VK_SHADER_STAGE_VERTEX_BIT;
const VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT = __ForwarderInternals._VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
const VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = __ForwarderInternals._VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
const VK_SYNTHETIC_DEVICE = __ForwarderInternals._VK_SYNTHETIC_DEVICE;
const VK_SYNTHETIC_QUEUE = __ForwarderInternals._VK_SYNTHETIC_QUEUE;
const VK_SYNTHETIC_SURFACE = __ForwarderInternals._VK_SYNTHETIC_SURFACE;
const VkApplicationInfo = __ForwarderInternals._VkApplicationInfo;
const VulkanAbsentEntryPoints = __ForwarderInternals._VulkanAbsentEntryPoints;
const VulkanFenceWatch = __ForwarderInternals._VulkanFenceWatch;
const VulkanPresenterStage = __ForwarderInternals._VulkanPresenterStage;
const VulkanRefusalLedger = __ForwarderInternals._VulkanRefusalLedger;
const abi = __ForwarderInternals._abi;
const async_vulkan_command = __ForwarderInternals._async_vulkan_command;
const bridge_device_capabilities = __ForwarderInternals._bridge_device_capabilities;
const builtin = __ForwarderInternals._builtin;
const campaignDiagnosticFrame = __ForwarderInternals._campaignDiagnosticFrame;
const canonicalVulkanCommand = __ForwarderInternals._canonicalVulkanCommand;
const coreFeatureEnabled = __ForwarderInternals._coreFeatureEnabled;
const device_extensions = __ForwarderInternals._device_extensions;
const enumerateDeviceExtensions = __ForwarderInternals._enumerateDeviceExtensions;
const enumerateEmpty = __ForwarderInternals._enumerateEmpty;
const enumerateHandle = __ForwarderInternals._enumerateHandle;
const enumerateInstanceExtensionsSynthetic = __ForwarderInternals._enumerateInstanceExtensionsSynthetic;
const extension_names = __ForwarderInternals._extension_names;
const featureChainBoolAt = __ForwarderInternals._featureChainBoolAt;
const featureChainBoolCount = __ForwarderInternals._featureChainBoolCount;
const featureChainKind = __ForwarderInternals._featureChainKind;
const featureChainSType = __ForwarderInternals._featureChainSType;
const featureChainSize = __ForwarderInternals._featureChainSize;
const feature_chain_node_bytes = __ForwarderInternals._feature_chain_node_bytes;
const frame_capture = __ForwarderInternals._frame_capture;
const fsiCanCoalesceSegments = __ForwarderInternals._fsiCanCoalesceSegments;
const fsiCommandClass = __ForwarderInternals._fsiCommandClass;
const fsiGuestFeatureRequest = __ForwarderInternals._fsiGuestFeatureRequest;
const fsi_chain = __ForwarderInternals._fsi_chain;
const fsi_timing = __ForwarderInternals._fsi_timing;
const gpu_vulkan = __ForwarderInternals._gpu_vulkan;
const guestRangeAvailable = __ForwarderInternals._guestRangeAvailable;
const guestSymbolKind = __ForwarderInternals._guestSymbolKind;
const guestSymbolLookupCacheIndex = __ForwarderInternals._guestSymbolLookupCacheIndex;
const guest_instance_extension_aliases = __ForwarderInternals._guest_instance_extension_aliases;
const guest_memory_geometry = __ForwarderInternals._guest_memory_geometry;
const guest_sleep = __ForwarderInternals._guest_sleep;
const imageReadbackAugmentable = __ForwarderInternals._imageReadbackAugmentable;
const isForwardableVulkanSymbol = __ForwarderInternals._isForwardableVulkanSymbol;
const libraryMatches = __ForwarderInternals._libraryMatches;
const linkBridgeCapabilityChain = __ForwarderInternals._linkBridgeCapabilityChain;
const marshal = __ForwarderInternals._marshal;
const moltenvk_runtime_defaults = __ForwarderInternals._moltenvk_runtime_defaults;
const native_texture = __ForwarderInternals._native_texture;
const normalizeMachOSymbol = __ForwarderInternals._normalizeMachOSymbol;
const physicalDeviceGuestHandle = __ForwarderInternals._physicalDeviceGuestHandle;
const present_pacing = __ForwarderInternals._present_pacing;
const publishVulkanDispatchableHandle = __ForwarderInternals._publishVulkanDispatchableHandle;
const rangeContains = __ForwarderInternals._rangeContains;
const readGuestApplicationInfo = __ForwarderInternals._readGuestApplicationInfo;
const rectExpansionBuiltinIndexBuffer = __ForwarderInternals._rectExpansionBuiltinIndexBuffer;
const render_diagnostic_frames = __ForwarderInternals._render_diagnostic_frames;
const resolvedPresentResult = __ForwarderInternals._resolvedPresentResult;
const rosette_gpu = __ForwarderInternals._rosette_gpu;
const shouldForceContentPixelProbe = __ForwarderInternals._shouldForceContentPixelProbe;
const specFor = __ForwarderInternals._specFor;
const spliceBridgeCapabilityChain = __ForwarderInternals._spliceBridgeCapabilityChain;
const std = __ForwarderInternals._std;
const transport_timing = __ForwarderInternals._transport_timing;
const vkErrorInitializationFailed = __ForwarderInternals._vkErrorInitializationFailed;
const vulkanNameHash = __ForwarderInternals._vulkanNameHash;
const writeApiVersion = __ForwarderInternals._writeApiVersion;
const writeExtensionPropertiesArray = __ForwarderInternals._writeExtensionPropertiesArray;
const writeSurfaceCapabilities = __ForwarderInternals._writeSurfaceCapabilities;
const xenia_heap_range = __ForwarderInternals._xenia_heap_range;
const xenia_host_gpu_callback_contract = __ForwarderInternals._xenia_host_gpu_callback_contract;
const xenia_launch_assist_contract = __ForwarderInternals._xenia_launch_assist_contract;
const SpecializationScratch = __ForwarderInternals._SpecializationScratch;

pub const TestState = @import("test_state.zig").TestState;

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

const FsiRasterTestDriver = struct {
    var creates: usize = 0;
    var destroys: usize = 0;
    var ends: usize = 0;
    var begins: usize = 0;
    var last_pass: u64 = 0;
    var last_buffer: usize = 0;
    var create_result: abi.Result = abi.SUCCESS;

    fn reset() void {
        creates = 0;
        destroys = 0;
        ends = 0;
        begins = 0;
        last_pass = 0;
        last_buffer = 0;
        create_result = abi.SUCCESS;
    }
    fn create(_: abi.Device, pointer: *const anyopaque, _: ?*const anyopaque, output: *u64) callconv(.c) abi.Result {
        const info: *const marshal.RenderPassCreateInfo = @ptrCast(@alignCast(pointer));
        std.debug.assert(info.attachment_count == 0 and info.subpass_count == 1 and info.dependency_count == 2);
        creates += 1;
        output.* = if (create_result == abi.SUCCESS) 0x7100 + creates else 0;
        return create_result;
    }
    fn destroy(_: abi.Device, pass: u64, _: ?*const anyopaque) callconv(.c) void {
        std.debug.assert(pass > 0x7100);
        destroys += 1;
    }
    fn createPipeline(_: abi.Device, _: abi.PipelineCache, count: u32, info: [*]const abi.GraphicsPipelineCreateInfo, _: ?*const anyopaque, output: [*]u64) callconv(.c) abi.Result {
        std.debug.assert(count == 1 and info[0].render_pass == 0x7101 and info[0].multisample_state.?.rasterization_samples == 4);
        output[0] = 0x7004;
        return abi.SUCCESS;
    }
    fn end(buffer: abi.CommandBuffer) callconv(.c) void {
        last_buffer = @intFromPtr(buffer);
        ends += 1;
    }
    fn begin(buffer: abi.CommandBuffer, info: *const abi.RenderPassBeginInfo, contents: u32) callconv(.c) void {
        std.debug.assert(info.framebuffer == 0x7200 and info.render_area.extent.width == 8192 and contents == 0 and info.clear_value_count == 0);
        last_buffer = @intFromPtr(buffer);
        last_pass = info.render_pass;
        begins += 1;
    }
};

fn fsiRasterTestPass(forwarder: *Forwarder) !void {
    FsiRasterTestDriver.reset();
    forwarder.fsi_raster.moltenvk = true;
    const subpass = marshal.SubpassDescription{};
    const dependencies = [_]marshal.SubpassDependency{
        .{ .src_subpass = 0xffff_ffff, .src_stage_mask = 0x80, .dst_stage_mask = 0x80, .src_access_mask = 0x60, .dst_access_mask = 0x60, .dependency_flags = 1 },
        .{ .dst_subpass = 0xffff_ffff, .src_stage_mask = 0x80, .dst_stage_mask = 0x80, .src_access_mask = 0x60, .dst_access_mask = 0x60, .dependency_flags = 1 },
    };
    const info = marshal.RenderPassCreateInfo{ .s_type = 38, .subpass_count = 1, .subpasses = &subpass, .dependency_count = 2, .dependencies = &dependencies };
    try std.testing.expect(forwarder.fsi_raster.capturePass(0x7100, &info));
    forwarder.real_vulkan.device = @ptrFromInt(0x1234);
    forwarder.real_vulkan.fn_ptrs.create_render_pass = FsiRasterTestDriver.create;
    forwarder.real_vulkan.fn_ptrs.destroy_render_pass = FsiRasterTestDriver.destroy;
    forwarder.real_vulkan.fn_ptrs.cmd_begin_render_pass = FsiRasterTestDriver.begin;
    forwarder.real_vulkan.fn_ptrs.cmd_end_render_pass = FsiRasterTestDriver.end;
    forwarder.fsi_raster.allocated(&.{0x501}, 0x601, true);
    try std.testing.expect(forwarder.mapVulkanHandle(&forwarder.real_vulkan.command_buffer_map, 0x501, 0x5010, "test"));
}

test "FSI raster sample count reaches native pipeline creation even without shader diagnostic identity" {
    var forwarder = Forwarder{};
    try fsiRasterTestPass(&forwarder);
    defer forwarder.fsiRasterShutdown();
    forwarder.real_vulkan.fn_ptrs.create_graphics_pipelines = FsiRasterTestDriver.createPipeline;
    try std.testing.expect(forwarder.mapVulkanHandle(&forwarder.real_vulkan.render_pass_map, 2, 0x7100, "test"));
    try std.testing.expect(forwarder.mapVulkanHandle(&forwarder.real_vulkan.pipeline_layout_map, 1, 0x7300, "test"));
    try std.testing.expect(forwarder.mapVulkanHandle(&forwarder.real_vulkan.shader_module_map, 3, 0x7500, "test"));
    var state = TestState{};
    const root = abi.GraphicsPipelineCreateInfo{ .stage_count = 1, .stages = @ptrFromInt(0x1100), .multisample_state = @ptrFromInt(0x1200), .layout = 1, .render_pass = 2 };
    const stage = abi.PipelineShaderStageCreateInfo{ .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = 3, .name = @ptrFromInt(0x1300) };
    const multisample = abi.PipelineMultisampleStateCreateInfo{ .rasterization_samples = 4 };
    try std.testing.expect(state.copyToGuest(0x1000, std.mem.asBytes(&root)));
    try std.testing.expect(state.copyToGuest(0x1100, std.mem.asBytes(&stage)));
    try std.testing.expect(state.copyToGuest(0x1200, std.mem.asBytes(&multisample)));
    try std.testing.expect(state.copyToGuest(0x1300, "main\x00"));
    var real: u64 = 0;
    var result: i32 = abi.ERROR_INITIALIZATION_FAILED;
    var tessellation = false;
    try forwarder.marshalRealGraphicsPipeline(&state, 0, 0x1000, &real, &result, &tessellation);
    try std.testing.expectEqual(abi.SUCCESS, result);
    try std.testing.expectEqual(@as(u64, 0x7101), forwarder.fsi_raster.pipelines.get(real).?);
    // The same forget path is used for guest destruction and creation-batch
    // rollback, so a retried batch cannot leave stale native-handle bindings.
    forwarder.forgetGraphicsPipeline(real);
    try std.testing.expect(forwarder.fsi_raster.pipelines.get(real) == null);
}

test "FSI pixel frequency reaches native module creation while preserving explicit sample inputs and refusal ordering" {
    const Driver = struct {
        var calls: usize = 0;
        var rate_caps: usize = 0;
        var refuse: bool = false;
        fn create(_: abi.Device, raw: *const anyopaque, _: ?*const anyopaque, out: *u64) callconv(.c) i32 {
            calls += 1;
            const info: *const marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(raw));
            const words: [*]const u32 = @ptrCast(@alignCast(info.code.?));
            var cursor: usize = 5;
            rate_caps = 0;
            while (cursor < info.code_size / 4) {
                const count = words[cursor] >> 16;
                if (@as(u16, @truncate(words[cursor])) == 17 and words[cursor + 1] == 35) rate_caps += 1;
                cursor += count;
            }
            if (refuse) return abi.ERROR_INITIALIZATION_FAILED;
            out.* = 0x4567;
            return abi.SUCCESS;
        }
    };
    // A small fragment module with a typed input mask and ordered interlock.
    const words = [_]u32{
        0x07230203,        0x00010500,        0,          32,         0,
        0x00020011,        1,                 0x00020011, 35,         0x00020011,
        5363,              0x0006000b,        17,         0x4c534c47, 0x6474732e,
        0x3035342e,        0,                 0x0003000e, 0,          1,
        0x0007000f,        4,                 10,         0x6e69616d, 0,
        6,                 16,                0x00030010, 10,         7,
        0x00030010,        10,                5367,       0x00040047, 6,
        11,                20,                0x00040047, 16,         11,
        15,                0x00020013,        1,          0x00030021, 2,
        1,                 0x00040015,        3,          32,         1,
        0x00040015,        4,                 32,         0,          0x0004002b,
        4,                 5,                 1,          0x0004001c, 7,
        3,                 5,                 0x00040020, 8,          1,
        7,                 0x0004003b,        8,          6,          1,
        0x00030016,        13,                32,         0x00040017, 14,
        13,                4,                 0x00040020, 15,         1,
        14,                0x0004003b,        15,         16,         1,
        0x00050036,        1,                 10,         0,          2,
        0x000200f8,        11,                0x0004003d, 7,          12,
        6,                 0x0004003d,        14,         18,         16,
        0x00010000 | 5364, 0x00010000 | 5365, 0x000100fd, 0x00010038,
    };
    for ([_]u8{ 0, 1, 2, 3 }) |mode| {
        var forwarder = Forwarder{};
        var state = TestState{};
        forwarder.fsi_raster.moltenvk = mode != 1;
        forwarder.fsi_pixel_frequency_configured = true;
        forwarder.robust_access_configured = true;
        forwarder.real_vulkan.device = @ptrFromInt(0x1234);
        forwarder.real_vulkan.fn_ptrs.create_shader_module = Driver.create;
        defer forwarder.vulkan_scratch.deinit();
        const sample = [_]u32{ 0x00030047, 6, 17 };
        const size = @sizeOf(@TypeOf(words)) + (if (mode == 2) @sizeOf(@TypeOf(sample)) else @as(usize, 0));
        const root = marshal.ShaderModuleCreateInfo{ .s_type = 16, .code_size = size, .code = @ptrFromInt(2048) };
        try std.testing.expect(state.copyToGuest(1024, std.mem.asBytes(&root)));
        if (mode == 2) {
            var types: usize = 5;
            while (@as(u16, @truncate(words[types])) != 19) types += words[types] >> 16;
            try std.testing.expect(state.copyToGuest(2048, std.mem.sliceAsBytes(words[0..types])));
            try std.testing.expect(state.copyToGuest(2048 + types * 4, std.mem.sliceAsBytes(&sample)));
            try std.testing.expect(state.copyToGuest(2048 + (types + 3) * 4, std.mem.sliceAsBytes(words[types..])));
        } else try std.testing.expect(state.copyToGuest(2048, std.mem.sliceAsBytes(&words)));
        Driver.calls = 0;
        Driver.refuse = mode == 3;
        try forwarder.createRealVulkanObject(&state, 0x321, 1024, "vkCreateShaderModule");
        try std.testing.expectEqual(@as(usize, 1), Driver.calls);
        try std.testing.expectEqual(@as(usize, 1), Driver.rate_caps);
        try std.testing.expectEqual(@as(u64, if (mode == 0 or mode == 3) 1 else 0), forwarder.fsi_pixel_frequency_changed);
        try std.testing.expectEqual(@as(u64, if (mode == 2) 1 else 0), forwarder.fsi_pixel_frequency_explicit);
        try std.testing.expectEqual(@as(u64, if (mode == 3) 1 else 0), forwarder.fsi_pixel_frequency_driver_rejections);
        try std.testing.expectEqual(mode != 3, forwarder.realVulkanObjectMapped(0x321, "vkCreateShaderModule"));
    }
}

test "FSI shader hardening failures never create the unsafe original module" {
    const Driver = struct {
        var calls: usize = 0;
        fn create(_: abi.Device, _: *const anyopaque, _: ?*const anyopaque, out: *u64) callconv(.c) i32 {
            calls += 1;
            // An unsafe retry would succeed and conceal the safety failure.
            if (calls == 1) return abi.ERROR_INITIALIZATION_FAILED;
            out.* = 0x4567;
            return abi.SUCCESS;
        }
    };
    // Minimal uniform-array load through a computed index. The stub needs no
    // actual GPU, and a successful retry would be an observable regression.
    const words = [_]u32{
        0x07230203, 0x00010000, 0,          20,         0,
        0x0003000e, 0,          1,          0x0005000f, 5,
        12,         0x6e69616d, 0,          0x00030047, 4,
        2,          0x00020013, 9,          0x00030021, 10,
        9,          0x00040015, 1,          32,         0,
        0x0004002b, 1,          2,          4,          0x0004001c,
        3,          1,          2,          0x0003001e, 4,
        3,          0x00040020, 5,          2,          4,
        0x00040020, 6,          2,          1,          0x0004003b,
        5,          7,          2,          0x0004002b, 1,
        8,          0,          0x00050036, 9,          12,
        0,          10,         0x000200f8, 13,         0x00050080,
        1,          11,         8,          8,          0x00060041,
        6,          14,         7,          8,          11,
        0x0004003d, 1,          15,         14,         0x000100fd,
        0x00010038,
    };
    var forwarder = Forwarder{};
    var state = TestState{};
    forwarder.robust_access_configured = true;
    forwarder.robust_access_enabled = true;
    forwarder.real_vulkan.device = @ptrFromInt(0x1234);
    forwarder.real_vulkan.fn_ptrs.create_shader_module = Driver.create;
    defer forwarder.vulkan_scratch.deinit();
    const root = marshal.ShaderModuleCreateInfo{ .s_type = 16, .code_size = @sizeOf(@TypeOf(words)), .code = @ptrFromInt(2048) };
    try std.testing.expect(state.copyToGuest(1024, std.mem.asBytes(&root)));
    try std.testing.expect(state.copyToGuest(2048, std.mem.sliceAsBytes(&words)));
    Driver.calls = 0;
    try forwarder.createRealVulkanObject(&state, 0x321, 1024, "vkCreateShaderModule");
    try std.testing.expectEqual(@as(usize, 1), Driver.calls);
    try std.testing.expectEqual(abi.ERROR_INITIALIZATION_FAILED, forwarder.real_create_result);
    try std.testing.expectEqual(@as(u64, 1), forwarder.robust_access_driver_rejections);
    try std.testing.expectEqual(@as(u32, 1), forwarder.robust_access_stats.uniform_zero_loads);
    try std.testing.expect(!forwarder.realVulkanObjectMapped(0x321, "vkCreateShaderModule"));

    // An unreadable module is refused before even calling the driver.
    Driver.calls = 0;
    @memset(state.mem[2048..][0..@sizeOf(@TypeOf(words))], 0);
    forwarder.real_create_result = abi.SUCCESS;
    try forwarder.createRealVulkanObject(&state, 0x322, 1024, "vkCreateShaderModule");
    try std.testing.expectEqual(@as(usize, 0), Driver.calls);
    try std.testing.expectEqual(abi.ERROR_INITIALIZATION_FAILED, forwarder.real_create_result);
}

test "FSI raster sample-count variants restart the live buffer without the watchdog" {
    var forwarder = Forwarder{};
    try fsiRasterTestPass(&forwarder);
    defer forwarder.fsiRasterShutdown();
    try std.testing.expect(forwarder.fsi_guard == null);
    try std.testing.expectEqual(@as(u64, 0x7100), try forwarder.fsiRasterPipelinePass(0x7100, 1));
    const four = try forwarder.fsiRasterPipelinePass(0x7100, 4);
    try std.testing.expectEqual(four, try forwarder.fsiRasterPipelinePass(0x7100, 4));
    try std.testing.expectEqual(@as(usize, 1), FsiRasterTestDriver.creates);
    try forwarder.fsi_raster.pipelineCreated(0x7004, four);
    forwarder.fsiBeginRecording(0x501, @ptrFromInt(0x5010), 1, false);
    forwarder.fsi_raster.bindPipeline(0x501, 0x7004);
    const begin = abi.RenderPassBeginInfo{ .render_pass = 0x7100, .framebuffer = 0x7200, .render_area = .{ .extent = .{ .width = 8192, .height = 8192 } } };
    forwarder.fsiNoteBeginRenderPass(0x501, &begin, 0);
    try std.testing.expect(forwarder.fsiRasterBeforeCommand(0x501, vulkanNameHash("vkCmdDrawIndexed"), "vkCmdDrawIndexed"));
    try std.testing.expectEqual(four, FsiRasterTestDriver.last_pass);
    try std.testing.expectEqual(@as(usize, 0x5010), FsiRasterTestDriver.last_buffer);
    try std.testing.expectEqual(@as(usize, 1), FsiRasterTestDriver.begins);
    try std.testing.expect(forwarder.fsiRasterBeforeCommand(0x501, vulkanNameHash("vkCmdDraw"), "vkCmdDraw"));
    try std.testing.expectEqual(@as(usize, 1), FsiRasterTestDriver.begins);
    try forwarder.fsi_raster.pipelineCreated(0x7001, 0x7100);
    forwarder.fsi_raster.bindPipeline(0x501, 0x7001);
    try std.testing.expect(forwarder.fsiRasterBeforeCommand(0x501, vulkanNameHash("vkCmdDraw"), "vkCmdDraw"));
    try std.testing.expectEqual(@as(u64, 0x7100), FsiRasterTestDriver.last_pass);
    forwarder.fsiForgetRenderPass(0x7100);
    try std.testing.expectEqual(@as(usize, 1), FsiRasterTestDriver.destroys);
    try std.testing.expect(forwarder.fsi_raster.findPass(four) == null);
}

test "FSI raster sample-count adaptation refuses unsafe queries, inheritance and failed variant creation" {
    var forwarder = Forwarder{};
    try fsiRasterTestPass(&forwarder);
    defer forwarder.fsiRasterShutdown();
    FsiRasterTestDriver.create_result = abi.ERROR_OUT_OF_HOST_MEMORY;
    try std.testing.expectError(error.FsiRasterizationUnavailable, forwarder.fsiRasterPipelinePass(0x7100, 4));
    try std.testing.expectError(error.FsiRasterizationUnavailable, forwarder.fsiRasterPipelinePass(0xBAD, 4));
    FsiRasterTestDriver.create_result = abi.SUCCESS;
    const four = try forwarder.fsiRasterPipelinePass(0x7100, 4);
    try forwarder.fsi_raster.pipelineCreated(0x7004, four);
    forwarder.fsi_raster.bindPipeline(0x501, 0x7004);
    const begin = abi.RenderPassBeginInfo{ .render_pass = 0x7100, .framebuffer = 0x7200, .render_area = .{ .extent = .{ .width = 8192, .height = 8192 } } };
    forwarder.fsiNoteBeginRenderPass(0x501, &begin, 0);
    try std.testing.expect(forwarder.fsiRasterBeforeCommand(0x501, vulkanNameHash("vkCmdBeginQuery"), "vkCmdBeginQuery"));
    try std.testing.expect(!forwarder.fsiRasterBeforeCommand(0x501, vulkanNameHash("vkCmdDraw"), "vkCmdDraw"));
    try std.testing.expect(forwarder.fsi_raster.command(0x501).?.failed);
    try std.testing.expectEqual(@as(usize, 0), FsiRasterTestDriver.begins);
    forwarder.fsiBeginRecording(0x501, @ptrFromInt(0x5010), 1, false);
    try std.testing.expect(!forwarder.fsi_raster.command(0x501).?.failed);
    forwarder.fsi_raster.command(0x501).?.primary = false;
    forwarder.fsiBeginRecording(0x501, @ptrFromInt(0x5010), 1, true);
    forwarder.fsi_raster.bindPipeline(0x501, 0x7004);
    try std.testing.expect(!forwarder.fsiRasterBeforeCommand(0x501, vulkanNameHash("vkCmdDraw"), "vkCmdDraw"));
    try std.testing.expect(forwarder.fsi_raster.command(0x501).?.failed);
    try std.testing.expectEqual(@as(usize, 0), FsiRasterTestDriver.begins);
}

test "FSI raster sample-count selection is replayed into watchdog continuations" {
    var forwarder = Forwarder{};
    try fsiTestForwarder(&forwarder);
    try fsiRasterTestPass(&forwarder);
    defer forwarder.fsiRasterShutdown();
    fsiTestRecordPassState(&forwarder);
    const four = try forwarder.fsiRasterPipelinePass(0x7100, 4);
    try forwarder.fsi_raster.pipelineCreated(0x7001, four);
    forwarder.fsi_raster.bindPipeline(0x501, 0x7001);
    try std.testing.expect(forwarder.fsiRasterBeforeCommand(0x501, vulkanNameHash("vkCmdDrawIndexed"), "vkCmdDrawIndexed"));
    // Splitting must continue even when all diagnostic pipeline identities
    // have been evicted. The mandatory registry is the authority here.
    forwarder.vulkan_fsi_tracker = .{};
    for (0..20) |_| fsiTestDraw(&forwarder);
    try std.testing.expectEqual(@as(usize, 3), forwarder.fsiRecording(0x501).?.chunk_count);
    try std.testing.expectEqualSlices(u32, &.{ 6, 6, 6, 2 }, forwarder.fsiRecording(0x501).?.segment_fsi_draws[0..4]);
    try std.testing.expectEqual(@as(u64, 6 * 320 * 240 * 4), forwarder.fsiRecording(0x501).?.segment_sample_work[0]);
    try std.testing.expectEqual(four, FsiRasterTestDriver.last_pass);
    try std.testing.expectEqual(@as(usize, 0x9030), FsiRasterTestDriver.last_buffer);
    // A return to 1x after a split restarts the chunk, not the guest's old buffer.
    try forwarder.fsi_raster.pipelineCreated(0x7002, 0x7100);
    forwarder.fsi_raster.bindPipeline(0x501, 0x7002);
    try std.testing.expect(forwarder.fsiRasterBeforeCommand(0x501, vulkanNameHash("vkCmdDraw"), "vkCmdDraw"));
    try std.testing.expectEqual(@as(usize, 0x9030), FsiRasterTestDriver.last_buffer);
    try std.testing.expectEqual(@as(u64, 0x7100), FsiRasterTestDriver.last_pass);
}

const FsiTestDriver = struct {
    var calls: [512][]const u8 = undefined;
    var call_buffers: [512]usize = undefined;
    var call_count: usize = 0;
    var next_chunk: usize = 0x9000;
    var next_fence: u64 = 0xA000;
    var reset_result: abi.Result = abi.SUCCESS;
    var begin_result: abi.Result = abi.SUCCESS;
    var end_result: abi.Result = abi.SUCCESS;
    var submit_info_counts: [16]u32 = undefined;
    var submit_buffers: [16][2][4]usize = undefined;
    var submit_buffer_counts: [16][2]u32 = undefined;
    var submit_waits: [16][2]u32 = undefined;
    var submit_signals: [16][2]u32 = undefined;
    var submit_fences: [16]u64 = undefined;
    var submit_count: usize = 0;

    fn reset() void {
        call_count = 0;
        next_chunk = 0x9000;
        next_fence = 0xA000;
        reset_result = abi.SUCCESS;
        begin_result = abi.SUCCESS;
        end_result = abi.SUCCESS;
        submit_count = 0;
        submit_info_counts = [_]u32{0} ** submit_info_counts.len;
        submit_buffer_counts = [_][2]u32{.{ 0, 0 }} ** submit_buffer_counts.len;
        submit_waits = [_][2]u32{.{ 0, 0 }} ** submit_waits.len;
        submit_signals = [_][2]u32{.{ 0, 0 }} ** submit_signals.len;
        submit_fences = [_]u64{0} ** submit_fences.len;
    }
    fn note(name: []const u8, buffer: abi.CommandBuffer) void {
        calls[call_count] = name;
        call_buffers[call_count] = @intFromPtr(buffer);
        call_count += 1;
    }
    fn endPass(buffer: abi.CommandBuffer) callconv(.c) void {
        note("end_render_pass", buffer);
    }
    fn beginPass(buffer: abi.CommandBuffer, info: *const abi.RenderPassBeginInfo, contents: u32) callconv(.c) void {
        std.debug.assert(info.render_pass == 0x7100 and info.framebuffer == 0x7200 and info.render_area.extent.width == 8192 and contents == 0);
        note("begin_render_pass", buffer);
    }
    fn endBuffer(buffer: abi.CommandBuffer) callconv(.c) abi.Result {
        note("end_command_buffer", buffer);
        return end_result;
    }
    fn beginBuffer(buffer: abi.CommandBuffer, info: *const abi.CommandBufferBeginInfo) callconv(.c) abi.Result {
        std.debug.assert(info.flags == 1 and info.inheritance_info == null);
        note("begin_command_buffer", buffer);
        return begin_result;
    }
    fn bindPipeline(buffer: abi.CommandBuffer, bind_point: u32, pipeline: u64) callconv(.c) void {
        std.debug.assert(bind_point == 0 and pipeline == 0x7001);
        note("bind_pipeline", buffer);
    }
    fn bindSets(buffer: abi.CommandBuffer, bind_point: u32, layout: u64, first: u32, count: u32, sets: [*]const u64, dynamic_count: u32, dynamic: ?[*]const u32) callconv(.c) void {
        _ = dynamic;
        std.debug.assert(bind_point == 0 and layout == 0x7300 and first == 0 and count == 1 and sets[0] == 0x7400 and dynamic_count == 0);
        note("bind_descriptor_sets", buffer);
    }
    fn setScissor(buffer: abi.CommandBuffer, first: u32, count: u32, scissors: [*]const abi.Rect2D) callconv(.c) void {
        std.debug.assert(first == 0 and count == 1 and scissors[0].extent.width == 320 and scissors[0].extent.height == 240);
        note("set_scissor", buffer);
    }
    fn resetCommandBuffer(buffer: abi.CommandBuffer, flags: u32) callconv(.c) abi.Result {
        std.debug.assert(flags == 0);
        note("reset_chunk", buffer);
        return reset_result;
    }
    fn createFence(_: abi.Device, _: *const abi.FenceCreateInfo, _: ?*const anyopaque, fence: *abi.Fence) callconv(.c) abi.Result {
        next_fence += 1;
        fence.* = next_fence;
        return abi.SUCCESS;
    }
    fn createPool(device: abi.Device, info: *const abi.CommandPoolCreateInfo, allocator: ?*const anyopaque, pool: *abi.CommandPool) callconv(.c) abi.Result {
        _ = device;
        _ = allocator;
        std.debug.assert(info.flags == abi.COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT);
        pool.* = 0x7500;
        return abi.SUCCESS;
    }
    fn allocate(device: abi.Device, info: *const abi.CommandBufferAllocateInfo, buffers: [*]abi.CommandBuffer) callconv(.c) abi.Result {
        _ = device;
        std.debug.assert(info.command_pool == 0x7500 and info.command_buffer_count == 1 and info.level == abi.COMMAND_BUFFER_LEVEL_PRIMARY);
        next_chunk += 0x10;
        buffers[0] = @ptrFromInt(next_chunk);
        return abi.SUCCESS;
    }
    fn submit(queue: abi.Queue, count: u32, infos: ?[*]const abi.SubmitInfo, fence: abi.Fence) callconv(.c) abi.Result {
        _ = queue;
        std.debug.assert(count <= fsi_timing.max_submit_infos_per_timing_group);
        submit_info_counts[submit_count] = count;
        submit_buffer_counts[submit_count] = .{ 0, 0 };
        submit_waits[submit_count] = .{ 0, 0 };
        submit_signals[submit_count] = .{ 0, 0 };
        for (0..count) |info_index| {
            const info = infos.?[info_index];
            submit_buffer_counts[submit_count][info_index] = info.command_buffer_count;
            for (0..info.command_buffer_count) |index| submit_buffers[submit_count][info_index][index] = @intFromPtr(info.command_buffers.?[index]);
            submit_waits[submit_count][info_index] = info.wait_semaphore_count;
            submit_signals[submit_count][info_index] = info.signal_semaphore_count;
        }
        submit_fences[submit_count] = fence;
        submit_count += 1;
        return abi.SUCCESS;
    }
};

fn fsiTestForwarder(forwarder: *Forwarder) !void {
    FsiTestDriver.reset();
    forwarder.real_vulkan.device = @ptrFromInt(0x1234);
    const fns = &forwarder.real_vulkan.fn_ptrs;
    fns.cmd_end_render_pass = FsiTestDriver.endPass;
    fns.cmd_begin_render_pass = FsiTestDriver.beginPass;
    fns.end_command_buffer = FsiTestDriver.endBuffer;
    fns.begin_command_buffer = FsiTestDriver.beginBuffer;
    fns.cmd_bind_pipeline = FsiTestDriver.bindPipeline;
    fns.cmd_bind_descriptor_sets = FsiTestDriver.bindSets;
    fns.cmd_set_scissor = FsiTestDriver.setScissor;
    fns.reset_command_buffer = FsiTestDriver.resetCommandBuffer;
    fns.create_command_pool = FsiTestDriver.createPool;
    fns.allocate_command_buffers = FsiTestDriver.allocate;
    fns.create_fence = FsiTestDriver.createFence;
    // Xenia's FSI render pass: no attachments, one subpass, two dependencies.
    var render_pass = [_]u8{0} ** 64;
    std.mem.writeInt(u32, render_pass[32..36], 1, .little);
    std.mem.writeInt(u32, render_pass[48..52], 2, .little);
    forwarder.fsiNoteCommandBuffersAllocated(&.{0x501}, 0x601, abi.COMMAND_BUFFER_LEVEL_PRIMARY);
    forwarder.fsiNoteRenderPassCreated(0x7100, &render_pass);
    try std.testing.expect(forwarder.fsiArmedGuard() != null);
    forwarder.fsiBeginRecording(0x501, @ptrFromInt(0x5010), 1, false);
    forwarder.vulkan_fsi_tracker.notePipelineCreated(0x7001, .{ .uses_fsi = true, .module_id = 1, .combined_hash = 0xABC }, true);
}

fn fsiTestRecordPassState(forwarder: *Forwarder) void {
    forwarder.vulkan_fsi_tracker.bindPipeline(0x501, 0x7001);
    const shadow = forwarder.fsiShadow(0x501).?;
    _ = shadow.bindPipeline(0, 0x7001);
    _ = shadow.bindDescriptorSets(0, 0x7300, 0, &.{0x7400}, &.{});
    _ = shadow.setScissors(0, &.{.{ .extent = .{ .width = 320, .height = 240 } }});
    const begin = abi.RenderPassBeginInfo{ .render_pass = 0x7100, .framebuffer = 0x7200, .render_area = .{ .extent = .{ .width = 8192, .height = 8192 } } };
    forwarder.fsiNoteBeginRenderPass(0x501, &begin, 0);
}

fn fsiTestDraw(forwarder: *Forwarder) void {
    forwarder.fsiNoteCommand(0x501, vulkanNameHash("vkCmdDrawIndexed"), "vkCmdDrawIndexed");
}

test "FSI tessellation isolation splits before and after each draw" {
    var forwarder = Forwarder{};
    try fsiTestForwarder(&forwarder);
    defer std.heap.page_allocator.destroy(forwarder.fsi_guard.?);
    defer forwarder.fsi_raster.deinit();
    fsiTestRecordPassState(&forwarder);
    try forwarder.fsi_raster.isolatePipeline(0x7001);
    for (0..3) |_| fsiTestDraw(&forwarder);
    const recording = forwarder.fsiRecording(0x501).?;
    try std.testing.expectEqual(@as(usize, 2), recording.chunk_count);
    try std.testing.expectEqualSlices(u32, &.{ 1, 1, 1 }, recording.segment_fsi_draws[0..3]);
    try std.testing.expectEqualSlices(bool, &.{ true, true, true }, recording.segment_isolated[0..3]);
    _ = forwarder.fsi_raster.isolated_pipelines.remove(0x7001);
    fsiTestDraw(&forwarder);
    try std.testing.expectEqual(@as(usize, 3), recording.chunk_count);
    try std.testing.expect(!recording.segment_isolated[3]);
    fsiTestDraw(&forwarder);
    try std.testing.expectEqual(@as(u32, 2), recording.segment_fsi_draws[3]);
}

const FsiCpuRouteTestDriver = struct {
    var events = std.atomic.Value(u32).init(0);
    var errors = std.atomic.Value(u32).init(0);
    var require_pairs: bool = true;

    fn reset(pairs: bool) void {
        events.store(0, .monotonic);
        errors.store(0, .monotonic);
        require_pairs = pairs;
    }

    fn draw(command_buffer: abi.CommandBuffer, vertices: u32, instances: u32, first: u32, first_instance: u32) callconv(.c) void {
        const event = events.fetchAdd(1, .monotonic);
        if (@intFromPtr(command_buffer.?) != 0x5010 or vertices != 3 or instances != 2 or first != event or first_instance != 5) {
            _ = errors.fetchAdd(1, .monotonic);
        }
    }

    fn endPass(command_buffer: abi.CommandBuffer) callconv(.c) void {
        const event = events.fetchAdd(1, .monotonic);
        if (@intFromPtr(command_buffer.?) != 0x5010 or (require_pairs and event % 2 != 1)) {
            _ = errors.fetchAdd(1, .monotonic);
        }
    }

    fn job(first: u32) async_vulkan_command.Job {
        return .{ .draw = .{
            .function = draw,
            .command_buffer = @ptrFromInt(0x5010),
            .vertex_count = 3,
            .instance_count = 2,
            .first_vertex = first,
            .first_instance = 5,
        } };
    }

    fn issue(forwarder: *Forwarder, first: u32) void {
        if (!forwarder.queueAsyncVulkanCommand(job(first))) {
            forwarder.callNativeVulkanCommand(@as(abi.PfnCmdDraw, draw), .{ @ptrFromInt(0x5010), 3, 2, first, 5 });
        }
    }
};

test "FSI small-chunk CPU route drains older jobs and retains command payloads and order" {
    var forwarder = Forwarder{};
    try fsiTestForwarder(&forwarder);
    defer std.heap.page_allocator.destroy(forwarder.fsi_guard.?);
    forwarder.vulkan_async_command_worker_decided = true;
    forwarder.vulkan_async_command_worker_enabled = true;
    defer forwarder.stopAsyncVulkanCommandWorker();
    FsiCpuRouteTestDriver.reset(false);
    // Queue an older draw before the budget switches to tiny recordings.
    try std.testing.expect(forwarder.queueAsyncVulkanCommand(FsiCpuRouteTestDriver.job(0)));
    forwarder.fsi_guard.?.monitor.cap.store(4, .monotonic);
    FsiCpuRouteTestDriver.issue(&forwarder, 1);
    // The direct draw must first drain the older job, even without an
    // intervening end-pass barrier. Its first-vertex payload checks ordering.
    try std.testing.expectEqual(@as(u32, 2), FsiCpuRouteTestDriver.events.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 0), FsiCpuRouteTestDriver.errors.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), forwarder.fsi_small_chunk_sync_commands);
    // Retain the old route when requested, and ordinary larger recordings
    // still use the worker. Drain before reading callback results.
    forwarder.fsi_small_chunk_sync = false;
    try std.testing.expect(forwarder.queueAsyncVulkanCommand(FsiCpuRouteTestDriver.job(2)));
    forwarder.drainAsyncVulkanCommands();
    forwarder.fsi_small_chunk_sync = true;
    forwarder.fsi_guard.?.monitor.cap.store(16, .monotonic);
    try std.testing.expect(forwarder.queueAsyncVulkanCommand(FsiCpuRouteTestDriver.job(3)));
    forwarder.drainAsyncVulkanCommands();
    try std.testing.expectEqual(@as(u32, 4), FsiCpuRouteTestDriver.events.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 0), FsiCpuRouteTestDriver.errors.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 4), forwarder.vulkan_real_command_calls);
    try std.testing.expectEqual(@as(u64, 1), forwarder.fsi_small_chunk_sync_commands);
}

test "FSI CPU benchmark measures production worker and synchronous tiny-chunk routes without a GPU" {
    const benchmark = if (std.c.getenv("ROSETTE_FSI_CPU_BENCH")) |value| std.mem.eql(u8, std.mem.span(value), "1") else false;
    const iterations: u32 = if (benchmark) 20000 else 32;
    var elapsed: [2]u64 = undefined;
    var queued: [2]u64 = undefined;
    for (0..2) |mode| {
        var forwarder = Forwarder{};
        try fsiTestForwarder(&forwarder);
        defer std.heap.page_allocator.destroy(forwarder.fsi_guard.?);
        forwarder.fsi_guard.?.monitor.cap.store(4, .monotonic);
        forwarder.fsi_small_chunk_sync = mode == 1;
        forwarder.vulkan_async_command_worker_decided = true;
        forwarder.vulkan_async_command_worker_enabled = true;
        // Exclude worker creation from the measured baseline.
        _ = forwarder.asyncVulkanWorker() orelse return error.WorkerUnavailable;
        defer forwarder.stopAsyncVulkanCommandWorker();
        FsiCpuRouteTestDriver.reset(true);
        const started = transport_timing.nowNs();
        for (0..iterations) |index| {
            FsiCpuRouteTestDriver.issue(&forwarder, @intCast(index * 2));
            forwarder.callNativeVulkanCommand(@as(abi.PfnCmdEndRenderPass, FsiCpuRouteTestDriver.endPass), .{@ptrFromInt(0x5010)});
        }
        elapsed[mode] = transport_timing.nowNs() -| started;
        queued[mode] = forwarder.vulkan_async_command_worker.?.stats().submitted;
        try std.testing.expectEqual(iterations * 2, FsiCpuRouteTestDriver.events.load(.monotonic));
        try std.testing.expectEqual(@as(u32, 0), FsiCpuRouteTestDriver.errors.load(.monotonic));
        try std.testing.expectEqual(@as(u64, iterations) * 2, forwarder.vulkan_real_command_calls);
        try std.testing.expectEqual(@as(u64, if (mode == 1) iterations else 0), forwarder.fsi_small_chunk_sync_commands);
    }
    try std.testing.expectEqual(@as(u64, iterations), queued[0]);
    try std.testing.expectEqual(@as(u64, 0), queued[1]);
    if (benchmark) std.debug.print(
        "FSI CPU route benchmark: {d} draw/barrier pairs worker_ns={d} sync_ns={d} queued(old/new)={d}/{d}; stub native callbacks, production forwarding and FIFO barriers, not gameplay FPS\n",
        .{ iterations, elapsed[0], elapsed[1], queued[0], queued[1] },
    );
}

test "an FSI command buffer is split into bounded chunks that each resume the guest's bound state" {
    var forwarder = Forwarder{};
    try fsiTestForwarder(&forwarder);
    fsiTestRecordPassState(&forwarder);
    // The initial draw cap is 16. With a small test scissor, forty draws
    // become three bounded chunks without triggering the pixel-work ceiling.
    for (0..40) |_| fsiTestDraw(&forwarder);
    const recording = forwarder.fsiRecording(0x501).?;
    try std.testing.expectEqual(@as(usize, 2), recording.chunk_count);
    try std.testing.expectEqualSlices(u32, &.{ 16, 16, 8 }, recording.segment_fsi_draws[0..3]);
    try std.testing.expectEqual(@as(u64, 0xABC), recording.segment_first_pipeline[1]);
    // Later commands go to the newest chunk.
    try std.testing.expectEqual(@as(usize, 0x9020), @intFromPtr(forwarder.fsiCommandTarget(0x501, @ptrFromInt(0x5010))));
    // Each split closes the old buffer and replays pipeline, descriptor sets
    // and scissor into the new one inside the same render pass.
    const expected = [_][]const u8{ "reset_chunk", "begin_command_buffer", "end_render_pass", "end_command_buffer", "begin_render_pass", "bind_pipeline", "bind_descriptor_sets", "set_scissor" };
    try std.testing.expectEqual(expected.len * 2, FsiTestDriver.call_count);
    for (expected, 0..) |name, index| {
        try std.testing.expectEqualStrings(name, FsiTestDriver.calls[index]);
        try std.testing.expectEqualStrings(name, FsiTestDriver.calls[expected.len + index]);
    }
    try std.testing.expectEqual(@as(usize, 0x9010), FsiTestDriver.call_buffers[0]);
    try std.testing.expectEqual(@as(usize, 0x9010), FsiTestDriver.call_buffers[1]);
    try std.testing.expectEqual(@as(usize, 0x5010), FsiTestDriver.call_buffers[2]);
    try std.testing.expectEqual(@as(usize, 0x9010), FsiTestDriver.call_buffers[4]);
    try std.testing.expectEqual(@as(usize, 0x9020), FsiTestDriver.call_buffers[8]);
    try std.testing.expectEqual(@as(u64, 2), forwarder.fsi_guard.?.splits);

    // The guest submits its one command buffer in one batch with a wait and
    // a signal semaphore. The first two adjacent chunks are preserved as two
    // VkSubmitInfo batches in one timed queue call; the final chunk retains
    // the signal, followed by an empty submit that preserves the guest fence.
    var real_submits: [8]abi.SubmitInfo = [_]abi.SubmitInfo{.{}} ** 8;
    const waits = [_]abi.Semaphore{0x801};
    const stages = [_]u32{0x400};
    const signals = [_]abi.Semaphore{0x802};
    const own = [_]abi.CommandBuffer{@ptrFromInt(0x5010)};
    real_submits[0] = .{ .wait_semaphore_count = 1, .wait_semaphores = &waits, .wait_dst_stage_mask = &stages, .command_buffer_count = 1, .command_buffers = &own, .signal_semaphore_count = 1, .signal_semaphores = &signals };
    var synthetics: [8][256]u64 = [_][256]u64{[_]u64{0} ** 256} ** 8;
    synthetics[0][0] = 0x501;
    var counts: [8]u32 = [_]u32{0} ** 8;
    counts[0] = 1;
    try std.testing.expect(forwarder.fsiSubmitNeedsExpansion(&synthetics, &counts, 1));
    // The first two adjacent chunks share one host vkQueueSubmit call while
    // remaining distinct VkSubmitInfo batches; the final chunk carries the
    // guest signal and has its own timing fence. An empty submission then
    // preserves the guest fence after the last segment.
    forwarder.fsi_guard.?.monitor_started = true;
    try std.testing.expectEqual(abi.SUCCESS, forwarder.fsiSubmitExpanded(@ptrFromInt(0x99), FsiTestDriver.submit, &real_submits, &synthetics, &counts, 1, 0x803, &forwarder));
    try std.testing.expectEqual(@as(usize, 3), FsiTestDriver.submit_count);
    try std.testing.expectEqualSlices(u32, &.{ 2, 1, 0 }, FsiTestDriver.submit_info_counts[0..3]);
    try std.testing.expectEqual(@as(u32, 1), FsiTestDriver.submit_buffer_counts[0][0]);
    try std.testing.expectEqual(@as(u32, 1), FsiTestDriver.submit_buffer_counts[0][1]);
    try std.testing.expectEqual(@as(usize, 0x5010), FsiTestDriver.submit_buffers[0][0][0]);
    try std.testing.expectEqual(@as(usize, 0x9010), FsiTestDriver.submit_buffers[0][1][0]);
    try std.testing.expectEqual(@as(u32, 1), FsiTestDriver.submit_buffer_counts[1][0]);
    try std.testing.expectEqual(@as(usize, 0x9020), FsiTestDriver.submit_buffers[1][0][0]);
    try std.testing.expectEqual(@as(u32, 0), FsiTestDriver.submit_buffer_counts[2][0]);
    try std.testing.expectEqualSlices(u32, &.{ 1, 0 }, FsiTestDriver.submit_waits[0][0..]);
    try std.testing.expectEqualSlices(u32, &.{ 0, 0 }, FsiTestDriver.submit_signals[0][0..]);
    try std.testing.expectEqual(@as(u32, 0), FsiTestDriver.submit_signals[0][1]);
    try std.testing.expectEqual(@as(u32, 1), FsiTestDriver.submit_signals[1][0]);
    try std.testing.expect(FsiTestDriver.submit_fences[0] != 0 and FsiTestDriver.submit_fences[1] != 0 and FsiTestDriver.submit_fences[2] != 0);
    try std.testing.expectEqual(@as(u64, 0x803), FsiTestDriver.submit_fences[2]);
    try std.testing.expectEqual(@as(u64, 3), forwarder.fsi_guard.?.segments_submitted);
    try std.testing.expectEqual(@as(u64, 3), forwarder.fsi_guard.?.driver_queue_submit_calls);
    try std.testing.expectEqual(@as(u64, 3), forwarder.fsi_guard.?.driver_submit_infos);
    try std.testing.expectEqual(@as(u64, 1), forwarder.fsi_guard.?.coalesced_submit_groups);

    // Beginning the guest buffer again returns both chunks to the pool and
    // the next split reuses one instead of allocating.
    forwarder.fsi_guard.?.monitor.completed_serial = 3;
    var discarded_fences: [8]u64 = undefined;
    _ = forwarder.fsi_guard.?.monitor.collectFences(&discarded_fences);
    forwarder.fsiBeginRecording(0x501, @ptrFromInt(0x5010), 1, false);
    fsiTestRecordPassState(&forwarder);
    for (0..17) |_| fsiTestDraw(&forwarder);
    try std.testing.expectEqual(@as(u64, 2), forwarder.fsi_guard.?.chunk_pool.allocated);
    try std.testing.expectEqual(@as(u64, 1), forwarder.fsi_guard.?.chunk_pool.reuses);
}

test "FSI submit is refused before driver work when the watchdog cannot start" {
    var forwarder = Forwarder{};
    try fsiTestForwarder(&forwarder);
    forwarder.fsi_guard_watcher_thread = true;
    fsiTestRecordPassState(&forwarder);
    fsiTestDraw(&forwarder);
    var real_submits: [8]abi.SubmitInfo = [_]abi.SubmitInfo{.{}} ** 8;
    const own = [_]abi.CommandBuffer{@ptrFromInt(0x5010)};
    real_submits[0] = .{ .command_buffer_count = 1, .command_buffers = &own };
    var synthetics: [8][256]u64 = [_][256]u64{[_]u64{0} ** 256} ** 8;
    synthetics[0][0] = 0x501;
    var counts: [8]u32 = [_]u32{0} ** 8;
    counts[0] = 1;

    try std.testing.expectEqual(
        abi.ERROR_INITIALIZATION_FAILED,
        forwarder.fsiSubmitExpanded(@ptrFromInt(0x99), FsiTestDriver.submit, &real_submits, &synthetics, &counts, 1, 0, &forwarder),
    );
    try std.testing.expectEqual(@as(usize, 0), FsiTestDriver.submit_count);
    try std.testing.expect(forwarder.fsi_guard.?.monitor_start_failed);
}

test "FSI paused monitor without a watcher and failed timing fences stop before additional GPU work" {
    for (0..2) |case| {
        var forwarder = Forwarder{};
        try fsiTestForwarder(&forwarder);
        fsiTestRecordPassState(&forwarder);
        fsiTestDraw(&forwarder);
        const guard = forwarder.fsi_guard.?;
        guard.monitor_started = true;
        guard.monitor.submissions_paused = case == 0;
        guard.monitor.failed = case == 1;
        var real_submits: [8]abi.SubmitInfo = [_]abi.SubmitInfo{.{}} ** 8;
        const own = [_]abi.CommandBuffer{@ptrFromInt(0x5010)};
        real_submits[0] = .{ .command_buffer_count = 1, .command_buffers = &own };
        var synthetics: [8][256]u64 = [_][256]u64{[_]u64{0} ** 256} ** 8;
        synthetics[0][0] = 0x501;
        var counts: [8]u32 = [_]u32{0} ** 8;
        counts[0] = 1;
        const result = forwarder.fsiSubmitExpanded(@ptrFromInt(0x99), FsiTestDriver.submit, &real_submits, &synthetics, &counts, 1, 0, &forwarder);
        try std.testing.expectEqual(abi.ERROR_DEVICE_LOST, result);
        try std.testing.expectEqual(@as(usize, 0), FsiTestDriver.submit_count);
        forwarder.noteRealVulkanResult(result, "FSI test submit");
        try std.testing.expect(forwarder.real_vulkan.device_lost);
        try std.testing.expectEqual(@as(u64, if (case == 0) 1 else 0), guard.slow_chunk_submit_aborts);
    }
}

test "FSI campaign severe completion permits the next native submit without synthetic device loss" {
    const CompletedFence = struct {
        fn wait(context: *anyopaque, fence: u64, timeout_ns: u64) fsi_timing.WaitResult {
            _ = context;
            _ = fence;
            _ = timeout_ns;
            return .signaled;
        }
        fn reset(context: *anyopaque, fence: u64) bool {
            _ = context;
            _ = fence;
            return true;
        }
        fn now(context: *anyopaque) u64 {
            _ = context;
            return 466 * 1_000_000;
        }
    };
    var forwarder = Forwarder{};
    try fsiTestForwarder(&forwarder);
    fsiTestRecordPassState(&forwarder);
    fsiTestDraw(&forwarder);
    const guard = forwarder.fsi_guard.?;
    guard.monitor_started = true;
    guard.monitor.ops = .{ .context = guard, .wait = CompletedFence.wait, .reset = CompletedFence.reset, .now = CompletedFence.now };
    _ = guard.monitor.track(.{ .fence = 0x999, .draws = 16, .submit_infos = 2 });
    _ = guard.monitor.budget.noteOutstanding(356 * 1_000_000, .none);
    guard.monitor.submissions_paused = true;
    try std.testing.expect(guard.monitor.pollOnce());
    try std.testing.expectEqual(@as(u64, 1), guard.monitor.stats().severe_recoveries);
    try std.testing.expectEqual(@as(u32, 4), guard.monitor.capValue());
    try std.testing.expectEqual(@as(usize, 0), FsiTestDriver.submit_count);

    var real_submits: [8]abi.SubmitInfo = [_]abi.SubmitInfo{.{}} ** 8;
    const own = [_]abi.CommandBuffer{@ptrFromInt(0x5010)};
    real_submits[0] = .{ .command_buffer_count = 1, .command_buffers = &own };
    var synthetics: [8][256]u64 = [_][256]u64{[_]u64{0} ** 256} ** 8;
    synthetics[0][0] = 0x501;
    var counts: [8]u32 = [_]u32{0} ** 8;
    counts[0] = 1;
    const result = forwarder.fsiSubmitExpanded(@ptrFromInt(0x99), FsiTestDriver.submit, &real_submits, &synthetics, &counts, 1, 0, &forwarder);
    try std.testing.expectEqual(abi.SUCCESS, result);
    try std.testing.expectEqual(@as(usize, 1), FsiTestDriver.submit_count);
    forwarder.noteRealVulkanResult(result, "FSI recovery test submit");
    try std.testing.expect(!forwarder.real_vulkan.device_lost);
    try std.testing.expectEqual(@as(u64, 0), guard.slow_chunk_submit_aborts);
    try std.testing.expect(guard.monitor.stats().budget.emergency);
}

test "FSI continuation boundary failures never commit a partial command buffer" {
    var begin_forwarder = Forwarder{};
    try fsiTestForwarder(&begin_forwarder);
    fsiTestRecordPassState(&begin_forwarder);
    FsiTestDriver.begin_result = abi.ERROR_INITIALIZATION_FAILED;
    for (0..20) |_| fsiTestDraw(&begin_forwarder);
    const begin_recording = begin_forwarder.fsiRecording(0x501).?;
    try std.testing.expectEqual(@as(usize, 0), begin_recording.chunk_count);
    try std.testing.expectEqual(@as(u64, 0x5010), begin_recording.target());
    try std.testing.expectEqual(@as(u64, 1), begin_forwarder.fsi_guard.?.blocked_splits[@intFromEnum(fsi_chain.Block.continuation_begin_failed)]);
    try std.testing.expectEqual(@as(usize, 2), FsiTestDriver.call_count);
    try std.testing.expectEqualStrings("reset_chunk", FsiTestDriver.calls[0]);
    try std.testing.expectEqualStrings("begin_command_buffer", FsiTestDriver.calls[1]);

    var end_forwarder = Forwarder{};
    try fsiTestForwarder(&end_forwarder);
    fsiTestRecordPassState(&end_forwarder);
    FsiTestDriver.end_result = abi.ERROR_INITIALIZATION_FAILED;
    for (0..17) |_| fsiTestDraw(&end_forwarder);
    const end_recording = end_forwarder.fsiRecording(0x501).?;
    try std.testing.expect(end_recording.failed);
    try std.testing.expectEqual(@as(usize, 0), end_recording.chunk_count);
    try std.testing.expectEqual(@as(u64, 0), end_forwarder.fsi_guard.?.chunk_pool.reuses);
    var real_submits: [8]abi.SubmitInfo = [_]abi.SubmitInfo{.{}} ** 8;
    const own = [_]abi.CommandBuffer{@ptrFromInt(0x5010)};
    real_submits[0] = .{ .command_buffer_count = 1, .command_buffers = &own };
    var synthetics: [8][256]u64 = [_][256]u64{[_]u64{0} ** 256} ** 8;
    synthetics[0][0] = 0x501;
    var counts: [8]u32 = [_]u32{0} ** 8;
    counts[0] = 1;
    try std.testing.expectEqual(abi.ERROR_INITIALIZATION_FAILED, end_forwarder.fsiSubmitExpanded(@ptrFromInt(0x99), FsiTestDriver.submit, &real_submits, &synthetics, &counts, 1, 0, &end_forwarder));
    try std.testing.expectEqual(@as(usize, 0), FsiTestDriver.submit_count);
}

test "an FSI recording with state the bridge cannot replay keeps Vulkan's whole-buffer semantics" {
    var forwarder = Forwarder{};
    try fsiTestForwarder(&forwarder);
    fsiTestRecordPassState(&forwarder);
    // Extended dynamic state is not part of the shadow: once recorded, the
    // buffer is never split, but its original Vulkan command stream survives.
    forwarder.fsiNoteCommand(0x501, vulkanNameHash("vkCmdSetDepthTestEnable"), "vkCmdSetDepthTestEnable");
    for (0..100) |_| fsiTestDraw(&forwarder);
    try std.testing.expectEqual(@as(usize, 0), forwarder.fsiRecording(0x501).?.chunk_count);
    try std.testing.expect(!forwarder.fsiRecording(0x501).?.failed);
    try std.testing.expectEqual(@as(u64, 100), forwarder.fsiRecording(0x501).?.fsi_draws);
    try std.testing.expectEqual(@as(usize, 0), FsiTestDriver.call_count);
    try std.testing.expectEqual(@as(u64, 1), forwarder.fsi_guard.?.blocked_splits[@intFromEnum(fsi_chain.Block.unrecorded_command)]);
}

test "a render pass with attachments is never split, and an FSI-free buffer is never expanded" {
    var forwarder = Forwarder{};
    try fsiTestForwarder(&forwarder);
    forwarder.vulkan_fsi_tracker.bindPipeline(0x501, 0x7001);
    _ = forwarder.fsiShadow(0x501).?.bindPipeline(0, 0x7001);
    // A host render target pass: its attachments would have to be loaded
    // again by a new instance, so it is not in the splittable set.
    const begin = abi.RenderPassBeginInfo{ .render_pass = 0x7666, .framebuffer = 0x7200 };
    forwarder.fsiNoteBeginRenderPass(0x501, &begin, 0);
    for (0..100) |_| fsiTestDraw(&forwarder);
    try std.testing.expectEqual(@as(usize, 0), forwarder.fsiRecording(0x501).?.chunk_count);
    try std.testing.expectEqual(@as(u64, 1), forwarder.fsi_guard.?.blocked_splits[@intFromEnum(fsi_chain.Block.render_pass_not_splittable)]);

    var synthetics: [8][256]u64 = [_][256]u64{[_]u64{0} ** 256} ** 8;
    var counts: [8]u32 = [_]u32{0} ** 8;
    synthetics[0][0] = 0x777;
    counts[0] = 1;
    try std.testing.expect(!forwarder.fsiSubmitNeedsExpansion(&synthetics, &counts, 1));
}

test "every command Xenia records in an FSI pass is either replayed, neutral, or blocks a split" {
    try std.testing.expectEqual(FsiCommandClass.draw, fsiCommandClass(vulkanNameHash("vkCmdDrawIndexed"), "vkCmdDrawIndexed"));
    try std.testing.expectEqual(FsiCommandClass.recorded, fsiCommandClass(vulkanNameHash("vkCmdBindDescriptorSets"), "vkCmdBindDescriptorSets"));
    try std.testing.expectEqual(FsiCommandClass.recorded, fsiCommandClass(vulkanNameHash("vkCmdSetStencilReference"), "vkCmdSetStencilReference"));
    try std.testing.expectEqual(FsiCommandClass.neutral, fsiCommandClass(vulkanNameHash("vkCmdPipelineBarrier"), "vkCmdPipelineBarrier"));
    try std.testing.expectEqual(FsiCommandClass.blocks, fsiCommandClass(vulkanNameHash("vkCmdPushDescriptorSetKHR"), "vkCmdPushDescriptorSetKHR"));
    try std.testing.expectEqual(FsiCommandClass.blocks, fsiCommandClass(vulkanNameHash("vkCmdNextSubpass"), "vkCmdNextSubpass"));
    try std.testing.expectEqual(FsiCommandClass.blocks, fsiCommandClass(vulkanNameHash("vkCmdBeginRendering"), "vkCmdBeginRendering"));
}

test "Xenia's FSI set update reaches the driver whole when its dead-stack sink info is garbage" {
    // The guest bytes the shipped xenia_canary.exe produces at
    // VulkanCommandProcessor::SetupContext+0xb08 (0x140a321ce): three storage
    // writes to one set, where write 2's VkDescriptorBufferInfo lives in a
    // stack slot the compiler never stored (see fsi_descriptor_repair.zig).
    const Driver = struct {
        var forwarded: [3]abi.WriteDescriptorSet = undefined;
        var forwarded_buffers: [3]abi.DescriptorBufferInfo = undefined;
        var forwarded_count: u32 = 0;
        var host_sink: [gpu_vulkan.fsi_descriptor_repair.XENIA_ZPD_COUNTER_SINK_BYTES]u8 = undefined;
        fn update(_: abi.Device, count: u32, writes: ?[*]const abi.WriteDescriptorSet, _: u32, _: ?[*]const abi.CopyDescriptorSet) callconv(.c) void {
            forwarded_count = count;
            for (0..count) |index| {
                forwarded[index] = writes.?[index];
                forwarded_buffers[index] = writes.?[index].buffer_info.?[0];
            }
        }
        fn createBuffer(_: abi.Device, info: *const abi.BufferCreateInfo, _: ?*const anyopaque, buffer: *abi.Buffer) callconv(.c) abi.Result {
            std.debug.assert(info.size == gpu_vulkan.fsi_descriptor_repair.XENIA_ZPD_COUNTER_SINK_BYTES);
            buffer.* = 0x5150;
            return abi.SUCCESS;
        }
        fn requirements(_: abi.Device, _: abi.Buffer, out: *abi.MemoryRequirements) callconv(.c) void {
            out.* = .{ .size = gpu_vulkan.fsi_descriptor_repair.XENIA_ZPD_COUNTER_SINK_BYTES, .alignment = 256, .memory_type_bits = 1 };
        }
        fn allocate(_: abi.Device, _: *const abi.MemoryAllocateInfo, _: ?*const anyopaque, memory: *abi.DeviceMemory) callconv(.c) abi.Result {
            memory.* = 0x5160;
            return abi.SUCCESS;
        }
        fn bind(_: abi.Device, _: abi.Buffer, _: abi.DeviceMemory, _: u64) callconv(.c) abi.Result {
            return abi.SUCCESS;
        }
        fn map(_: abi.Device, _: abi.DeviceMemory, _: u64, _: u64, _: u32, out: *?*anyopaque) callconv(.c) abi.Result {
            out.* = @ptrCast(&host_sink);
            return abi.SUCCESS;
        }
        fn unmap(_: abi.Device, _: abi.DeviceMemory) callconv(.c) void {}
    };
    const sink_bytes = gpu_vulkan.fsi_descriptor_repair.XENIA_ZPD_COUNTER_SINK_BYTES;
    // Whatever the stack slot held: a null buffer with an arbitrary range,
    // and stale bytes that happen to name the EDRAM buffer.
    const dead_slots = [_]abi.DescriptorBufferInfo{
        .{ .buffer = 0, .offset = 0, .range = 0 },
        .{ .buffer = 0, .offset = 0x7ff6_0000, .range = 0x1_0000_0000 },
        .{ .buffer = 0x9c1, .offset = 0, .range = abi.WHOLE_SIZE },
    };
    for (dead_slots) |dead_slot| {
        var forwarder = Forwarder{};
        var state = TestState{};
        forwarder.real_vulkan.device = @ptrFromInt(0x1234);
        forwarder.real_vulkan.fn_ptrs.update_descriptor_sets = Driver.update;
        forwarder.real_vulkan.fn_ptrs.create_buffer = Driver.createBuffer;
        forwarder.real_vulkan.fn_ptrs.get_buffer_memory_requirements = Driver.requirements;
        forwarder.real_vulkan.fn_ptrs.allocate_memory = Driver.allocate;
        forwarder.real_vulkan.fn_ptrs.bind_buffer_memory = Driver.bind;
        forwarder.real_vulkan.fn_ptrs.map_memory = Driver.map;
        forwarder.real_vulkan.fn_ptrs.unmap_memory = Driver.unmap;
        forwarder.real_vulkan.physical_device_memory.memory_type_count = 1;
        forwarder.real_vulkan.physical_device_memory.memory_types[0].property_flags = abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT | abi.MEMORY_PROPERTY_HOST_COHERENT_BIT;
        forwarder.real_vulkan.descriptor_set_map[0] = .{ .synthetic = 0x9b1, .real = 0xA9B1 };
        forwarder.real_vulkan.buffer_map[0] = .{ .synthetic = 0x2e1, .real = 0xB2E1 }; // shared memory
        forwarder.real_vulkan.buffer_map[1] = .{ .synthetic = 0x9c1, .real = 0xB9C1 }; // EDRAM
        @memset(&Driver.host_sink, 0xAB);
        Driver.forwarded_count = 0;

        const infos = [_]abi.DescriptorBufferInfo{
            .{ .buffer = 0x2e1, .offset = 0, .range = 512 << 20 },
            .{ .buffer = 0x9c1, .offset = 0, .range = abi.WHOLE_SIZE },
            dead_slot,
        };
        try std.testing.expect(state.copyToGuest(2048, std.mem.asBytes(&infos)));
        var writes: [3]abi.WriteDescriptorSet = undefined;
        for (&writes, 0..) |*write, binding| write.* = .{
            .dst_set = 0x9b1,
            .dst_binding = @intCast(binding),
            .descriptor_count = 1,
            .descriptor_type = abi.DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .buffer_info = @ptrFromInt(2048 + binding * @sizeOf(abi.DescriptorBufferInfo)),
        };
        try std.testing.expect(state.copyToGuest(1024, std.mem.asBytes(&writes)));
        state.regs.rsi = 3;
        state.regs.rdx = 1024;
        state.regs.rcx = 0;
        state.regs.r8 = 0;

        forwarder.updateDescriptorSets(&state);

        // All three writes reach the driver: the FSI shaders get their shared
        // memory and EDRAM, and binding 2 gets a zeroed sink of Xenia's size.
        try std.testing.expectEqual(@as(u32, 3), Driver.forwarded_count);
        for (Driver.forwarded, 0..) |write, binding| {
            try std.testing.expectEqual(@as(u64, 0xA9B1), write.dst_set);
            try std.testing.expectEqual(@as(u32, @intCast(binding)), write.dst_binding);
        }
        try std.testing.expectEqual(@as(u64, 0xB2E1), Driver.forwarded_buffers[0].buffer);
        try std.testing.expectEqual(@as(u64, 0xB9C1), Driver.forwarded_buffers[1].buffer);
        try std.testing.expectEqual(abi.WHOLE_SIZE, Driver.forwarded_buffers[1].range);
        try std.testing.expectEqual(@as(u64, 0x5150), Driver.forwarded_buffers[2].buffer);
        try std.testing.expectEqual(@as(u64, 0), Driver.forwarded_buffers[2].offset);
        try std.testing.expectEqual(sink_bytes, Driver.forwarded_buffers[2].range);
        try std.testing.expect(std.mem.allEqual(u8, &Driver.host_sink, 0));
        try std.testing.expectEqual(@as(u64, 1), forwarder.fsi_zpd_descriptor_repairs);
        for (forwarder.vulkan_descriptor_update_refusals) |count| try std.testing.expectEqual(@as(u64, 0), count);
    }
}

test "lookup custody follows descriptor copies to bound native gamma bytes" {
    var forwarder = Forwarder{};
    var state = TestState{};
    var host: [8]u8 = @splat(0);
    std.mem.writeInt(u32, host[4..8], 1023 | (1023 << 10) | (1023 << 20), .little);
    forwarder.tracked_buffer_views[0] = .{ .synthetic = 0x201, .buffer = 0x101, .format = 64, .offset = 128, .range = 8 };
    forwarder.vulkan_resources[0] = .{ .handle = 0x101, .kind = .buffer, .memory = 0x401, .memory_offset = 256 };
    forwarder.vulkan_memory_records[0] = .{ .handle = 0x401, .requested_size = 392, .mapped_offset = 384, .host_mapped_ptr = &host, .host_mapped_size = 8 };
    state.write64(128, 0x201);
    const write = abi.WriteDescriptorSet{ .dst_set = 0x301, .dst_binding = 2, .descriptor_type = 4, .descriptor_count = 1, .texel_buffer_view = @ptrFromInt(128) };
    forwarder.trackTexelDescriptorWrites(&state, &.{write});
    forwarder.copyDescriptorSetImages(.{ .src_set = 0x301, .src_binding = 2, .dst_set = 0x302, .dst_binding = 3, .descriptor_count = 1 });
    forwarder.tracked_command_targets[0] = .{ .synthetic = 0x501, .bound_descriptor_set_count = 1 };
    forwarder.tracked_command_targets[0].bound_descriptor_sets[0] = .{ .synthetic = 0x302, .set_index = 0 };
    forwarder.auditCommandTexelCustody(0x501);
    try std.testing.expectEqual(@as(u64, 1), forwarder.texel_custody_samples);
    try std.testing.expectEqual(@as(u64, 0), forwarder.texel_custody_zero);
    @memset(&host, 0);
    forwarder.auditCommandTexelCustody(0x501);
    try std.testing.expectEqual(@as(u64, 1), forwarder.texel_custody_zero);
    forwarder.vulkan_memory_records[0].host_mapped_size = 7;
    forwarder.auditCommandTexelCustody(0x501);
    try std.testing.expectEqual(@as(u64, 1), forwarder.texel_custody_missing);
}

test "coherent shadow publication preserves GPU bytes and publishes writes on unmap" {
    var forwarder = Forwarder{};
    var state = TestState{};
    var host = [_]u8{ 10, 20, 30, 40 };
    @memcpy(state.mem[128..132], &host);
    const record = &forwarder.vulkan_memory_records[0];
    record.* = .{
        .handle = 0x100,
        .requested_size = 4,
        .mapped_base = 128,
        .mapped_size = 4,
        .host_mapped_size = 4,
        .host_mapped_ptr = &host,
        .memory_flags_known = true,
        .memory_flags = abi.MEMORY_PROPERTY_HOST_COHERENT_BIT,
        .shadow_baseline = try std.heap.c_allocator.dupe(u8, &host),
    };
    defer record.releaseBaseline();
    host[1] = 99; // newer GPU data; guest did not write this byte
    state.mem[128] = 11;
    try std.testing.expect(forwarder.uploadMappedMemoryBeforeSubmit(&state));
    try std.testing.expectEqualSlices(u8, &.{ 11, 99, 30, 40 }, &host);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_shadow_upload_bytes);
    forwarder.downloadCoherentShadowsAfterCompletion(&state);
    try std.testing.expectEqualSlices(u8, &.{ 11, 99, 30, 40 }, state.mem[128..132]);
    state.mem[130] = 31; // written after the last submission
    state.regs.rsi = 0x100;
    _ = forwarder.unmapMemory(&state);
    try std.testing.expectEqual(@as(u8, 31), host[2]);
    try std.testing.expect(record.shadow_baseline == null and record.host_mapped_ptr == null);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_shadow_unmap_uploads);
}

test "coherent completion merge does not erase CPU changes for a future submission" {
    var forwarder = Forwarder{};
    var state = TestState{};
    var host = [_]u8{ 1, 2, 3, 4 };
    @memcpy(state.mem[128..132], &host);
    const record = &forwarder.vulkan_memory_records[0];
    record.* = .{ .handle = 0x100, .requested_size = 4, .mapped_base = 128, .mapped_size = 4, .host_mapped_size = 4, .host_mapped_ptr = &host, .memory_flags_known = true, .memory_flags = abi.MEMORY_PROPERTY_HOST_COHERENT_BIT, .shadow_baseline = try std.heap.c_allocator.dupe(u8, &host) };
    defer record.releaseBaseline();
    state.mem[128] = 9;
    host[1] = 8;
    forwarder.downloadCoherentShadowsAfterCompletion(&state);
    try std.testing.expectEqualSlices(u8, &.{ 9, 8, 3, 4 }, state.mem[128..132]);
    try std.testing.expectEqual(@as(u8, 1), record.shadow_baseline.?[0]);
    try std.testing.expect(forwarder.uploadMappedMemoryBeforeSubmit(&state));
    try std.testing.expectEqualSlices(u8, &.{ 9, 8, 3, 4 }, &host);
    try std.testing.expect(forwarder.uploadMappedMemoryBeforeSubmit(&state));
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_shadow_unchanged);
}

test "noncoherent shadow is not implicitly flushed by submission or unmap" {
    var forwarder = Forwarder{};
    var state = TestState{};
    var host = [_]u8{ 1, 2, 3, 4 };
    const record = &forwarder.vulkan_memory_records[0];
    record.* = .{ .handle = 0x100, .requested_size = 4, .mapped_base = 128, .mapped_size = 4, .host_mapped_size = 4, .host_mapped_ptr = &host, .memory_flags_known = true, .memory_flags = abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT, .shadow_baseline = try std.heap.c_allocator.dupe(u8, &host) };
    defer record.releaseBaseline();
    @memset(state.mem[128..132], 9);
    try std.testing.expect(forwarder.uploadMappedMemoryBeforeSubmit(&state));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, &host);
    try std.testing.expect(forwarder.copyMappedBytes(&state, 0x100, 1, 2, true));
    try std.testing.expectEqualSlices(u8, &.{ 1, 9, 9, 4 }, &host);
    state.mem[128] = 7;
    state.regs.rsi = 0x100;
    _ = forwarder.unmapMemory(&state);
    try std.testing.expectEqual(@as(u8, 1), host[0]);
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

test "real guest surface does not start a competing native presenter" {
    try std.testing.expect(!Forwarder.shouldBringUpNativePresenter(.{
        .enforced = true,
        .result = 0,
        .surface = 0x1234,
    }));
    try std.testing.expect(Forwarder.shouldBringUpNativePresenter(.{
        .enforced = false,
        .result = 0,
        .surface = 0,
    }));
}

test "guest present requests stay separate from completed presenter frames" {
    var forwarder = Forwarder{};
    forwarder.frame_provenance.native_present_requests = 1;
    forwarder.native_presenter.ledger.diagnostic_frames_presented = 2;

    // A host-driver request is the witness for presenter_entry. The two
    // completed diagnostic frames answer frame_presented and must not be
    // substituted for that request.
    try std.testing.expectEqual(@as(u64, 1), forwarder.guestVulkanPresentRequests());
    try std.testing.expectEqual(@as(u64, 2), forwarder.nativePresenterFramesPresented());
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

    pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
        if (address + length > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + length)];
    }

    pub fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
        return self.guestMemory(address, length);
    }

    pub fn read32(self: *@This(), address: u64) u32 {
        return std.mem.readInt(u32, self.mem[@intCast(address)..][0..4], .little);
    }

    pub fn write32(self: *@This(), address: u64, value: u32) void {
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

test "Rosette heap selector maps guest PageEntry vectors before reading them" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    var state = TestState{};

    const selector = forwarder.lookupGuest(
        RTLD_DEFAULT_HANDLE,
        "rosette_xenia_heap_select",
    );
    try std.testing.expect(selector != 0);

    // The selector receives a guest address in RDI. Rosetta must translate
    // that address to a host slice before the ARM64 package reads it.
    const entries_address: u64 = 0x2000;
    state.write64(entries_address + 14 * 8, @as(u64, 1) << xenia_heap_range.page_state_shift);
    state.regs.rdi = entries_address;
    state.regs.rsi = 16;
    state.regs.rdx = 0;
    state.regs.rcx = 15;
    state.regs.r8 = 1;
    state.regs.r9 = 1;
    state.regs.rsp = 0x1000;
    state.write64(0x1008, 1); // top_down
    state.write64(0x1010, xenia_heap_range.no_page);

    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, selector));
    try std.testing.expectEqual(@as(u64, 13), state.regs.rax);

    // An entry vector that extends outside the mapped guest address space is
    // rejected and returns the package sentinel rather than faulting the
    // native processor.
    state.regs.rdi = state.mem.len - 8;
    state.regs.rsi = 16;
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, selector));
    try std.testing.expectEqual(@as(u64, xenia_heap_range.no_page), state.regs.rax);
}

test "RTLD_DEFAULT exposes and marshals the checked Xenia framework ABI" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    var state = TestState{};

    const launch_abi = forwarder.lookupGuest(
        RTLD_DEFAULT_HANDLE,
        "rosette_xenia_launch_assist_abi_version",
    );
    const launch_schema = forwarder.lookupGuest(
        RTLD_DEFAULT_HANDLE,
        "rosette_xenia_launch_assist_schema_version",
    );
    const launch_query = forwarder.lookupGuest(
        RTLD_DEFAULT_HANDLE,
        "rosette_xenia_launch_assist_query",
    );
    const launch_report = forwarder.lookupGuest(
        RTLD_DEFAULT_HANDLE,
        "rosette_xenia_launch_assist_report",
    );
    const callback_abi = forwarder.lookupGuest(
        RTLD_DEFAULT_HANDLE,
        "rosette_xenia_host_gpu_callback_abi_version",
    );
    const callback_schema = forwarder.lookupGuest(
        RTLD_DEFAULT_HANDLE,
        "rosette_xenia_host_gpu_callback_schema_version",
    );
    const callback_query = forwarder.lookupGuest(
        RTLD_DEFAULT_HANDLE,
        "rosette_xenia_host_gpu_callback_query",
    );
    const callback_report = forwarder.lookupGuest(
        RTLD_DEFAULT_HANDLE,
        "rosette_xenia_host_gpu_callback_report",
    );
    for ([_]u64{
        launch_abi,
        launch_schema,
        launch_query,
        launch_report,
        callback_abi,
        callback_schema,
        callback_query,
        callback_report,
    }) |token| {
        try std.testing.expect(token >= GUEST_SYMBOL_THUNK_BASE);
    }

    state.regs.rax = 0;
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, launch_abi));
    try std.testing.expectEqual(@as(u64, xenia_launch_assist_contract.abi_version), state.regs.rax);
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, launch_schema));
    try std.testing.expectEqual(@as(u64, xenia_launch_assist_contract.schema_version), state.regs.rax);
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, callback_abi));
    try std.testing.expectEqual(@as(u64, xenia_host_gpu_callback_contract.abi_version), state.regs.rax);
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, callback_schema));
    try std.testing.expectEqual(@as(u64, xenia_host_gpu_callback_contract.schema_version), state.regs.rax);

    const launch_request_address: u64 = 256;
    const launch_response_address: u64 = 320;
    const launch_request = xenia_launch_assist_contract.Request.init(
        0x4D53_07E6,
        0x8258_2A98,
        0,
        3,
    );
    @memcpy(
        state.mem[@intCast(launch_request_address)..][0..@sizeOf(xenia_launch_assist_contract.Request)],
        std.mem.asBytes(&launch_request),
    );
    state.regs.rdi = launch_request_address;
    state.regs.rsi = launch_response_address;
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, launch_query));
    try std.testing.expectEqual(@as(u64, 1), state.regs.rax);

    var launch_response: xenia_launch_assist_contract.Response = undefined;
    @memcpy(
        std.mem.asBytes(&launch_response),
        state.mem[@intCast(launch_response_address)..][0..@sizeOf(xenia_launch_assist_contract.Response)],
    );
    try std.testing.expect(xenia_launch_assist_contract.responseIsCompatible(launch_response));
    state.regs.rdx = 0;
    state.regs.rcx = @intFromEnum(xenia_launch_assist_contract.ApplyStatus.not_applied);
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, launch_report));
    try std.testing.expectEqual(@as(u64, 1), state.regs.rax);

    const callback_request_address: u64 = 512;
    const callback_response_address: u64 = 640;
    const callback_request = xenia_host_gpu_callback_contract.Request.init(
        0x4D53_07E6,
        0x8258_2A98,
        0,
        0,
        0,
        7,
        4,
        16,
    );
    @memcpy(
        state.mem[@intCast(callback_request_address)..][0..@sizeOf(xenia_host_gpu_callback_contract.Request)],
        std.mem.asBytes(&callback_request),
    );
    state.regs.rdi = callback_request_address;
    state.regs.rsi = callback_response_address;
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, callback_query));
    try std.testing.expectEqual(@as(u64, 1), state.regs.rax);

    var callback_response: xenia_host_gpu_callback_contract.Response = undefined;
    @memcpy(
        std.mem.asBytes(&callback_response),
        state.mem[@intCast(callback_response_address)..][0..@sizeOf(xenia_host_gpu_callback_contract.Response)],
    );
    try std.testing.expect(xenia_host_gpu_callback_contract.responseIsCompatible(callback_response));
    state.regs.rdx = 0;
    state.regs.rcx = @intFromEnum(xenia_host_gpu_callback_contract.ApplyStatus.not_applied);
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, callback_report));
    try std.testing.expectEqual(@as(u64, 1), state.regs.rax);

    // The provider is strict about guest memory. An invalid request pointer
    // must return false to Xenia and must not reach the native framework.
    state.regs.rdi = state.mem.len - 1;
    state.regs.rsi = callback_response_address;
    try std.testing.expect(forwarder.dispatchGuestSymbol(&state, callback_query));
    try std.testing.expectEqual(@as(u64, 0), state.regs.rax);
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

test "Windows Vulkan names used by Xenia have explicit bridge contracts" {
    // The Windows surface query has no portable Win32 object that can cross
    // into macOS, so it must be answered by the same Metal-backed route as
    // vkCreateWin32SurfaceKHR rather than falling through to an opaque token.
    // The Windows adapter remaps this name to the actual forwarder spelling
    // before querying the backend symbol table.
    try std.testing.expect(isForwardableVulkanSymbol("vkCreateMetalSurfaceEXT"));
    try std.testing.expect(isForwardableVulkanSymbol("vkGetPhysicalDeviceWin32PresentationSupportKHR"));
    // VK_EXT_host_query_reset uses the EXT spelling on loaders that have not
    // promoted the command to core Vulkan 1.2.
    try std.testing.expect(isForwardableVulkanSymbol("vkResetQueryPoolEXT"));
    try std.testing.expect(!isForwardableVulkanSymbol("vkXeniaUnimplemented"));
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

test "guest output topology repair classifier is strict" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    const layout_real: u64 = 0x101;
    forwarder.tracked_pipeline_layouts[0] = .{
        .real = layout_real,
        .has_vertex_rect_push_constants = true,
    };

    var stages: [2]abi.PipelineShaderStageCreateInfo = .{ .{}, .{} };
    var input_assembly: abi.PipelineInputAssemblyStateCreateInfo = .{ .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
    var vertex_input: abi.PipelineVertexInputStateCreateInfo = .{};
    var viewport: abi.PipelineViewportStateCreateInfo = .{ .viewport_count = 1, .scissor_count = 1 };
    var rasterization: abi.PipelineRasterizationStateCreateInfo = .{};
    var multisample: abi.PipelineMultisampleStateCreateInfo = .{};
    var depth_stencil: abi.PipelineDepthStencilStateCreateInfo = .{};
    var color_attachments: [1]abi.PipelineColorBlendAttachmentState = .{.{}};
    var color_blend: abi.PipelineColorBlendStateCreateInfo = .{
        .attachment_count = 1,
        .attachments = &color_attachments,
    };
    var dynamic_states = [_]u32{ VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
    var dynamic: abi.PipelineDynamicStateCreateInfo = .{
        .dynamic_state_count = dynamic_states.len,
        .dynamic_states = &dynamic_states,
    };
    var root: abi.GraphicsPipelineCreateInfo = .{
        .stage_count = 2,
        .stages = &stages,
        .vertex_input_state = &vertex_input,
        .input_assembly_state = &input_assembly,
        .viewport_state = &viewport,
        .rasterization_state = &rasterization,
        .multisample_state = &multisample,
        .depth_stencil_state = &depth_stencil,
        .color_blend_state = &color_blend,
        .dynamic_state = &dynamic,
        .layout = layout_real,
    };

    try std.testing.expect(forwarder.isGuestOutputPaintPipeline(&root));
    input_assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
    try std.testing.expect(!forwarder.isGuestOutputPaintPipeline(&root));
    input_assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    vertex_input.vertex_binding_description_count = 1;
    try std.testing.expect(!forwarder.isGuestOutputPaintPipeline(&root));
    vertex_input.vertex_binding_description_count = 0;
    color_blend.attachment_count = 2;
    try std.testing.expect(!forwarder.isGuestOutputPaintPipeline(&root));
    color_blend.attachment_count = 1;
    forwarder.tracked_pipeline_layouts[0].has_vertex_rect_push_constants = false;
    try std.testing.expect(!forwarder.isGuestOutputPaintPipeline(&root));
}

test "a refusal ledger names what was refused and why, and stays quiet when nothing was" {
    var ledger = VulkanRefusalLedger{};
    try std.testing.expect(ledger.isEmpty());

    // The first observation of a (call, reason) pair is the one worth
    // logging; a repeat is counted, not restated.
    try std.testing.expect(ledger.note("vkQueueSubmit", "pSubmits is null with a non-zero submitCount", -3, .{ 2, 0, 0x40 }));
    try std.testing.expect(!ledger.note("vkQueueSubmit", "pSubmits is null with a non-zero submitCount", -3, .{ 9, 9, 9 }));
    try std.testing.expectEqual(@as(u64, 2), ledger.entries[0].calls);
    // The arguments retained are the first ones, which is what identifies the
    // call site.
    try std.testing.expectEqual(@as(u64, 2), ledger.entries[0].first_args[0]);

    // The same call refused for a different reason is a different fact, and
    // must not be folded into the first.
    try std.testing.expect(ledger.note("vkQueueSubmit", "a command buffer is not one Rosetta issued", -3, .{ 1, 0, 0 }));
    try std.testing.expectEqual(@as(usize, 2), ledger.count);
    try std.testing.expectEqual(@as(u64, 3), ledger.total);
    try std.testing.expectEqualStrings("vkQueueSubmit", ledger.entries[1].name());
    try std.testing.expectEqualStrings("a command buffer is not one Rosetta issued", ledger.entries[1].reason());

    try std.testing.expectEqual(@as(usize, 2), ledger.unreported_count);
    ledger.markReported();
    try std.testing.expectEqual(@as(usize, 0), ledger.unreported_count);
    // Reporting does not forget: the end-of-run summary is still complete.
    try std.testing.expectEqual(@as(usize, 2), ledger.count);

    // The ledger is bounded, and says so rather than silently dropping.
    var overflow = VulkanRefusalLedger{};
    var index: usize = 0;
    while (index < VulkanRefusalLedger.capacity + 3) : (index += 1) {
        var name_buffer: [8]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buffer, "vk{d}", .{index}) catch unreachable;
        _ = overflow.note(name, "reason", -3, .{ 0, 0, 0 });
    }
    try std.testing.expectEqual(VulkanRefusalLedger.capacity, overflow.count);
    try std.testing.expectEqual(@as(u64, 3), overflow.overflow);
}

test "a fence is starved only when it is polled hard with no submission behind it" {
    var watch = VulkanFenceWatch{};
    const fence: u64 = 0xfffff50000001091;

    // Polling before the first submission is ordinary and must stay quiet.
    var poll: u64 = 0;
    while (poll < VulkanFenceWatch.starvation_threshold - 1) : (poll += 1) watch.notePoll(fence);
    try std.testing.expect(watch.starvedFence() == null);

    // Crossing the threshold with nothing behind the fence is the shape of a
    // submission Rosetta refused: the guest waits for work the driver never
    // received.
    watch.notePoll(fence);
    const starved = watch.starvedFence() orelse return error.ExpectedStarvedFence;
    try std.testing.expectEqual(fence, starved.handle);
    // Reported once, not on every poll.
    watch.notePoll(fence);
    try std.testing.expect(watch.starvedFence() == null);

    // A fence a submission carried is never starved however hard it is
    // polled -- that is a slow GPU, not a broken bridge.
    var submitted = VulkanFenceWatch{};
    const busy: u64 = 0xfffff50000001021;
    submitted.noteSubmission(busy);
    poll = 0;
    while (poll < VulkanFenceWatch.starvation_threshold * 2) : (poll += 1) submitted.notePoll(busy);
    try std.testing.expect(submitted.starvedFence() == null);

    // Nor is one that has been observed signalled.
    var signalled = VulkanFenceWatch{};
    const done: u64 = 0xfffff50000001031;
    signalled.noteSignalled(done);
    poll = 0;
    while (poll < VulkanFenceWatch.starvation_threshold * 2) : (poll += 1) signalled.notePoll(done);
    try std.testing.expect(signalled.starvedFence() == null);

    // A null handle is not a fence.
    var empty = VulkanFenceWatch{};
    empty.notePoll(0);
    try std.testing.expectEqual(@as(usize, 0), empty.count);
}

test "an absent entry point is only a finding once the guest reaches it" {
    var absent = VulkanAbsentEntryPoints{};
    // A device that simply does not have a 1.3 entry point has nothing to
    // report: the absence is the expected shape of a 1.2 device.
    try std.testing.expect(absent.isEmpty());

    absent.note("vkGetDeviceBufferMemoryRequirements", "the Vulkan 1.1 vkGetBufferMemoryRequirements2 path");
    absent.note("vkGetDeviceBufferMemoryRequirements", "the Vulkan 1.1 vkGetBufferMemoryRequirements2 path");
    try std.testing.expectEqual(@as(usize, 1), absent.count);
    try std.testing.expectEqual(@as(u64, 2), absent.entries[0].reached);
    // What served the call is retained with it, because "absent" and
    // "absent and unserved" need opposite responses.
    try std.testing.expectEqualStrings(
        "the Vulkan 1.1 vkGetBufferMemoryRequirements2 path",
        absent.entries[0].servedBy(),
    );

    absent.note("vkCmdBeginConditionalRenderingEXT", "reported absent to the guest, as a real loader would");
    try std.testing.expectEqual(@as(usize, 2), absent.count);
    try std.testing.expect(!absent.isEmpty());
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

test "Vulkan procedure availability requires an implemented command ABI" {
    try @import("owned_argument_tests.zig").checkAvailability();
}
test "FSI owned command flow preserves guest marshalling and synchronous boundaries" {
    try @import("owned_argument_tests.zig").check(TestState);
}

test "native command dispatch forwards EXT aliases and scalar depth state" {
    const Capture = struct {
        var enabled: u32 = 0;
        var depth: [3]f32 = @splat(0);
        fn setEnable(_: abi.CommandBuffer, value: u32) callconv(.c) void {
            enabled = value;
        }
        fn setBias(_: abi.CommandBuffer, a: f32, b: f32, c: f32) callconv(.c) void {
            depth = .{ a, b, c };
        }
    };
    var forwarder = Forwarder{};
    var state = TestState{};
    _ = HandleMap.alloc(&forwarder.real_vulkan.command_buffer_map, 0x111, 0x222);
    forwarder.real_vulkan.fn_ptrs.cmd_set_depth_test_enable = Capture.setEnable;
    forwarder.real_vulkan.fn_ptrs.cmd_set_depth_bias = Capture.setBias;
    state.regs.rdi = 0x111;
    state.regs.rsi = 1;
    const alias = "vkCmdSetDepthTestEnableEXT";
    forwarder.forwardVulkanCommand(&state, vulkanNameHash(alias), alias);
    try std.testing.expectEqual(@as(u32, 1), Capture.enabled);
    const values = [_]f32{ 1.5, -0.5, 2.0 };
    for (values, 0..) |value, index| std.mem.writeInt(u32, state.xmm[index][0..4], @bitCast(value), .little);
    forwarder.forwardVulkanCommand(&state, vulkanNameHash("vkCmdSetDepthBias"), "vkCmdSetDepthBias");
    try std.testing.expectEqualDeep(values, Capture.depth);
}

test "content pixel probing retries until detail or its bounded budget" {
    var probe = PixelProbeState{};
    try std.testing.expect(!shouldForceContentPixelProbe(&probe, .uniform_fill));
    try std.testing.expect(shouldForceContentPixelProbe(&probe, .content));
    probe.content_probe_attempts = PIXEL_PROBE_CONTENT_SAMPLES - 1;
    try std.testing.expect(shouldForceContentPixelProbe(&probe, .content));
    probe.content_probe_attempts = PIXEL_PROBE_CONTENT_SAMPLES;
    try std.testing.expect(!shouldForceContentPixelProbe(&probe, .content));
    probe.content_probe_attempts = 1;
    probe.detail_observed = true;
    try std.testing.expect(!shouldForceContentPixelProbe(&probe, .content));
}

test "render colour probes reach the campaign transition before the observed Metal hang" {
    var count: u32 = 0;
    for (1..5810) |frame| {
        if (campaignDiagnosticFrame(frame)) count += 1;
    }
    try std.testing.expectEqual(@as(u32, render_diagnostic_frames.len), count);
    try std.testing.expect(campaignDiagnosticFrame(1024));
    try std.testing.expect(campaignDiagnosticFrame(1280));
    try std.testing.expect(campaignDiagnosticFrame(4608));
    try std.testing.expect(!campaignDiagnosticFrame(4609));
}

test "restarting a command buffer clears its rectangle shader and index bindings" {
    var forwarder = Forwarder{};
    const first = forwarder.rectExpandCommandState(0x101);
    first.marked_pipeline = true;
    first.builtin_indices = true;
    first.pipeline = 0x301;
    first.index_buffer = 0x401;
    first.index_offset = 16;
    first.index_type = abi.INDEX_TYPE_UINT32;
    const second = forwarder.rectExpandCommandState(0x202);
    second.marked_pipeline = true;
    second.builtin_indices = true;

    forwarder.resetCommandTargets(0x101);
    const restarted = forwarder.rectExpandCommandState(0x101);
    try std.testing.expect(!restarted.marked_pipeline and !restarted.builtin_indices);
    try std.testing.expectEqual(@as(u64, 0), restarted.pipeline);
    try std.testing.expectEqual(@as(u64, 0), restarted.index_buffer);
    try std.testing.expectEqual(@as(u64, 0), restarted.index_offset);
    try std.testing.expectEqual(@as(u32, 0), restarted.index_type);
    const other = forwarder.rectExpandCommandState(0x202);
    try std.testing.expect(other.marked_pipeline and other.builtin_indices);
}

test "Vulkan handle maps turn capacity pressure into a recoverable result" {
    var map: [2]HandleMap = [_]HandleMap{.{}} ** 2;
    try std.testing.expectEqual(HandleMap.InsertResult.inserted, HandleMap.allocOrFind(&map, 0x11, 0x21));
    try std.testing.expectEqual(HandleMap.InsertResult.inserted, HandleMap.allocOrFind(&map, 0x12, 0x22));
    try std.testing.expectEqual(@as(usize, 0), HandleMap.freeSlots(&map));
    try std.testing.expectEqual(HandleMap.InsertResult.exhausted, HandleMap.allocOrFind(&map, 0x13, 0x23));
    // Exhaustion is observable and non-destructive: the two live mappings
    // remain resolvable for the caller that is still using them.
    try std.testing.expectEqual(@as(?u64, 0x21), HandleMap.findReal(&map, 0x11));
    try std.testing.expectEqual(@as(usize, 2), HandleMap.occupied(&map));
    try std.testing.expect(HandleMap.remove(&map, 0x11));
    try std.testing.expectEqual(@as(usize, 1), HandleMap.freeSlots(&map));
    try std.testing.expectEqual(HandleMap.InsertResult.inserted, HandleMap.allocOrFind(&map, 0x13, 0x23));
}

test "Vulkan resource provenance records reuse destroyed slots and expose pressure" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();

    for (&forwarder.vulkan_resources, 0..) |*record, index| {
        record.* = .{ .handle = @as(u64, @intCast(index)) + 1, .kind = .image };
    }
    try std.testing.expectEqual(@as(usize, MAX_VULKAN_RESOURCES), forwarder.trackedResourceCount());
    try std.testing.expectEqual(@as(usize, 0), forwarder.freeResourceSlotCount());
    try std.testing.expect(!forwarder.resourceSlotAvailable());
    try std.testing.expect(forwarder.resourceSlot(0xDEAD) == null);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_resource_overflow);

    try std.testing.expect(forwarder.releaseResource(1));
    try std.testing.expectEqual(@as(usize, 1), forwarder.freeResourceSlotCount());
    const reused = forwarder.resourceSlot(0xDEAD) orelse return error.TestUnexpectedResult;
    reused.* = .{ .handle = 0xDEAD, .kind = .image };
    try std.testing.expectEqual(@as(usize, MAX_VULKAN_RESOURCES), forwarder.trackedResourceCount());
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_resource_records_released);
}

test "render pass sources are attributed to the pass target and committed at submission" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    // Guest image 0x901 is the gamma pass's output, 0x902 the swap texture it
    // samples; the framebuffer attaches a view of 0x901 and descriptor set
    // 0xB001 holds a view of 0x902.
    _ = HandleMap.alloc(&forwarder.real_vulkan.image_map, 0x901, 0x1901);
    _ = HandleMap.alloc(&forwarder.real_vulkan.image_map, 0x902, 0x1902);
    try std.testing.expect(forwarder.recordImageView(0x801, 0x901));
    try std.testing.expect(forwarder.recordImageView(0x802, 0x902));
    forwarder.tracked_framebuffers[0] = .{ .synthetic = 0x701, .attachment_count = 1 };
    forwarder.tracked_framebuffers[0].attachments[0] = 0x801;
    forwarder.noteDescriptorSetImage(0xB001, 0, 0, 0x902, 0x802, false);
    const command: u64 = 0x501;
    forwarder.noteCommandPassTarget(command, 0x701);
    forwarder.noteCommandBoundDescriptorSet(command, 1, 0xB001);
    forwarder.noteCommandBoundDescriptorSet(command, 1, 0xB001);
    forwarder.clearCommandPassTarget(command);
    // A set bound outside any render pass has no target to be an edge of.
    forwarder.noteCommandBoundDescriptorSet(command, 0, 0xB001);
    try std.testing.expectEqual(@as(u8, 1), forwarder.mutableCommandTargets(command).?.pass_edge_count);
    forwarder.commitCommandPassSources(command);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_pass_source_edges);
    try std.testing.expectEqual(@as(u64, 0x1902), forwarder.present_chain.passSourcesOf(0x1901)[0]);
    try std.testing.expectEqual(@as(?u64, 0x902), forwarder.syntheticImageForReal(0x1902));
    try std.testing.expectEqual(@as(?u64, null), forwarder.syntheticImageForReal(0x1999));
    // Only a single-sampled 2D colour image the probe can decode gains
    // TRANSFER_SRC on the host, and one that already has it is left alone.
    try std.testing.expect(imageReadbackAugmentable(abi.IMAGE_USAGE_SAMPLED_BIT, abi.FORMAT_A2B10G10R10_UNORM_PACK32, abi.IMAGE_TYPE_2D, abi.SAMPLE_COUNT_1_BIT));
    try std.testing.expect(!imageReadbackAugmentable(abi.IMAGE_USAGE_SAMPLED_BIT | abi.IMAGE_USAGE_TRANSFER_SRC_BIT, abi.FORMAT_A2B10G10R10_UNORM_PACK32, abi.IMAGE_TYPE_2D, abi.SAMPLE_COUNT_1_BIT));
    try std.testing.expect(!imageReadbackAugmentable(abi.IMAGE_USAGE_SAMPLED_BIT, abi.FORMAT_A2B10G10R10_UNORM_PACK32, abi.IMAGE_TYPE_2D, 4));
    try std.testing.expect(!imageReadbackAugmentable(abi.IMAGE_USAGE_TRANSFER_DST_BIT, abi.FORMAT_B8G8R8A8_UNORM, abi.IMAGE_TYPE_2D, abi.SAMPLE_COUNT_1_BIT));
    try std.testing.expect(!imageReadbackAugmentable(abi.IMAGE_USAGE_SAMPLED_BIT, 126, abi.IMAGE_TYPE_2D, abi.SAMPLE_COUNT_1_BIT));
}

test "descriptor-set mappings are reclaimed by pool lifetime" {
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    const pool: u64 = 0xA001;
    _ = HandleMap.allocOrFindOwned(&forwarder.real_vulkan.descriptor_set_map, 0xB001, 0xC001, pool);
    _ = HandleMap.allocOrFindOwned(&forwarder.real_vulkan.descriptor_set_map, 0xB002, 0xC002, pool);
    forwarder.noteDescriptorSetPool(0xB001, pool);
    try std.testing.expectEqual(@as(usize, 2), HandleMap.occupied(&forwarder.real_vulkan.descriptor_set_map));
    try std.testing.expectEqual(@as(usize, 2), forwarder.reclaimDescriptorSetsForPool(pool, "reset"));
    try std.testing.expectEqual(@as(usize, 0), HandleMap.occupied(&forwarder.real_vulkan.descriptor_set_map));
    try std.testing.expect(forwarder.trackedDescriptorSet(0xB001) == null);
    try std.testing.expectEqual(@as(u64, 2), forwarder.vulkan_descriptor_set_pool_reset_reclaims);
}

test "graphics report admission coalesces fast samples but preserves content and failures" {
    var forwarder = Forwarder{};
    var snapshot = rosette_gpu.ScreenValiditySnapshot{
        .guest_presents = 1,
        .guest_acquires = 1,
        .presents_with_target = 1,
        .presents_clear_only = 1,
        .native_present_requests = 1,
        .native_present_completions = 1,
        .native_queue_submits = 1,
        .pixel_evidence = .uniform_colour,
    };
    for (0..17641) |frame| {
        snapshot.guest_presents = frame + 1;
        snapshot.guest_acquires = frame + 1;
        snapshot.presents_with_target = frame + 1;
        snapshot.presents_clear_only = frame + 1;
        snapshot.native_present_requests = frame + 1;
        snapshot.native_present_completions = frame + 1;
        if (frame % 34 == 0) {
            snapshot.pixel_sample_frame = frame + 1;
            snapshot.pixel_sample_image = frame % 3;
            snapshot.pixel_hash = frame;
        }
        _ = forwarder.screen_validity.observe(snapshot);
        const kind = forwarder.chooseGraphicsReport(1 + @as(u64, @intCast(frame)) * 4_550_000, .presenting_clear_only_frames, false);
        if (kind != .none) forwarder.screen_validity.markReported();
    }
    try std.testing.expectEqual(@as(u64, 1), forwarder.graphics_report_cadence.full_reports);
    try std.testing.expectEqual(@as(u64, 16), forwarder.graphics_report_cadence.progress_reports);
    try std.testing.expectEqual(@as(u64, 17641), forwarder.screen_validity.snapshot().guest_presents);
    forwarder.vulkan_descriptor_bind_admission.rejected = 1;
    try std.testing.expectEqual(transport_timing.ReportKind.full, forwarder.chooseGraphicsReport(80_400_000_000, .presenting_clear_only_frames, false));
    forwarder.screen_validity.markReported();
    forwarder.vulkan_descriptor_bind_admission.rejected = 2;
    try std.testing.expectEqual(transport_timing.ReportKind.none, forwarder.chooseGraphicsReport(80_400_000_001, .presenting_clear_only_frames, false));
    forwarder.brightness_ladder.last_verdict = .gamma_pass;
    try std.testing.expectEqual(transport_timing.ReportKind.full, forwarder.chooseGraphicsReport(80_400_000_002, .presenting_clear_only_frames, false));
    forwarder.screen_validity.markReported();
    snapshot.presents_with_content = 1;
    snapshot.pixel_sample_was_content = true;
    _ = forwarder.screen_validity.observe(snapshot);
    try std.testing.expectEqual(transport_timing.ReportKind.full, forwarder.chooseGraphicsReport(80_400_000_003, .healthy, false));
    forwarder.screen_validity.markReported();
    try std.testing.expectEqual(transport_timing.ReportKind.full, forwarder.chooseGraphicsReport(80_400_000_004, .healthy, true));
}

test "pacing report selects the live guest swapchain, not diagnostic or retired history" {
    var forwarder = Forwarder{};
    forwarder.present_chain.swapchain_count = 3;
    forwarder.present_chain.swapchains[0] = .{ .owner = .guest, .retired = true, .present_mode = 0, .presents = 17641 };
    forwarder.present_chain.swapchains[1] = .{ .owner = .rosette, .present_mode = 2, .presents = 20000 };
    forwarder.present_chain.swapchains[2] = .{ .owner = .guest, .present_mode = 1, .presents = 2 };
    try std.testing.expectEqual(@as(?u32, 1), forwarder.guestPresentMode());
    forwarder.present_chain.swapchains[2].retired = true;
    try std.testing.expectEqual(@as(?u32, null), forwarder.guestPresentMode());
}

test "native per-swapchain results are authoritative without guest pResults" {
    try std.testing.expectEqual(abi.SUCCESS, resolvedPresentResult(abi.SUCCESS, abi.NOT_READY));
    try std.testing.expectEqual(abi.ERROR_OUT_OF_DATE_KHR, resolvedPresentResult(abi.ERROR_OUT_OF_DATE_KHR, abi.NOT_READY));
    try std.testing.expectEqual(abi.ERROR_OUT_OF_DATE_KHR, resolvedPresentResult(abi.SUCCESS, abi.ERROR_OUT_OF_DATE_KHR));
    try std.testing.expectEqual(abi.SUBOPTIMAL_KHR, resolvedPresentResult(abi.SUCCESS, abi.SUBOPTIMAL_KHR));
}

test "first observed picture escalates reporting even without a transport verdict change" {
    var forwarder = Forwarder{};
    _ = forwarder.chooseGraphicsReport(1, .healthy, false);
    forwarder.screen_validity.markReported();
    forwarder.picture_sequence.frames = 1;
    try std.testing.expectEqual(transport_timing.ReportKind.full, forwarder.chooseGraphicsReport(2, .healthy, false));
    forwarder.screen_validity.markReported();
    forwarder.picture_sequence.frames = 2;
    try std.testing.expectEqual(transport_timing.ReportKind.none, forwarder.chooseGraphicsReport(3, .healthy, false));
}

test "unused startup descriptors and offscreen uploads are inventory not a picture gap" {
    var forwarder = Forwarder{};
    forwarder.vulkan_descriptor_image_infos_observed = 8;
    forwarder.target_offscreen_events = 8;
    try std.testing.expectEqualStrings("STARTUP RESOURCE INVENTORY (no picture work observed)", forwarder.provenanceGapLabel());
    forwarder.vulkan_command_draw_calls = 1;
    try std.testing.expectEqualStrings("ACTIONABLE PROVENANCE GAP", forwarder.provenanceGapLabel());
    forwarder.vulkan_command_draw_calls = 0;
    forwarder.vulkan_command_dispatch_calls = 1;
    try std.testing.expectEqualStrings("ACTIONABLE PROVENANCE GAP", forwarder.provenanceGapLabel());
}

test "picture capture follows native completion and owns pixels across staging reuse" {
    const Capture = struct {
        const original = [_]u8{ 0, 0, 0, 255, 1, 0, 0, 255, 0, 2, 0, 255, 0, 0, 3, 255 };
        var staging: [16]u8 = original;
        var presented: bool = false;
        var completed: bool = false;
        var delivered: u32 = 0;
        fn reset(_: abi.CommandBuffer, _: u32) callconv(.c) abi.Result {
            return abi.SUCCESS;
        }
        fn begin(_: abi.CommandBuffer, _: *const abi.CommandBufferBeginInfo) callconv(.c) abi.Result {
            return abi.SUCCESS;
        }
        fn end(_: abi.CommandBuffer) callconv(.c) abi.Result {
            return abi.SUCCESS;
        }
        fn barrier(_: abi.CommandBuffer, _: u32, _: u32, _: u32, _: u32, _: ?*const anyopaque, _: u32, _: ?*const anyopaque, _: u32, _: ?[*]const abi.ImageMemoryBarrier) callconv(.c) void {}
        fn copy(_: abi.CommandBuffer, _: abi.Image, _: u32, _: abi.Buffer, _: u32, _: [*]const abi.BufferImageCopy) callconv(.c) void {}
        fn submit(_: abi.Queue, _: u32, _: ?[*]const abi.SubmitInfo, _: abi.Fence) callconv(.c) abi.Result {
            return abi.SUCCESS;
        }
        fn idle(_: abi.Queue) callconv(.c) abi.Result {
            if (presented) completed = true;
            return abi.SUCCESS;
        }
        fn present(_: abi.Queue, info: *const abi.PresentInfoKHR) callconv(.c) abi.Result {
            presented = true;
            @memset(&staging, 0); // native work/staging reuse cannot erase the copied capture
            info.results.?[0] = abi.SUCCESS;
            return abi.SUCCESS;
        }
        fn capture(packet: *const frame_capture.Frame) callconv(.c) u32 {
            std.debug.assert(presented and completed);
            std.debug.assert(packet.frame == 200001 and packet.content_frame == 1);
            std.debug.assert(packet.flags & frame_capture.picture_numbering != 0);
            std.debug.assert(packet.flags & frame_capture.show_preview != 0);
            std.debug.assert(std.mem.eql(u8, packet.pixels[0..16], &original));
            delivered += 1;
            return frame_capture.result_previewed | frame_capture.result_saved;
        }
    };
    Capture.staging = Capture.original;
    Capture.presented = false;
    Capture.completed = false;
    Capture.delivered = 0;
    const previous_callback = HostFrameCaptureResolver.callback;
    const previous_resolved = HostFrameCaptureResolver.resolved;
    defer {
        HostFrameCaptureResolver.callback = previous_callback;
        HostFrameCaptureResolver.resolved = previous_resolved;
    }
    HostFrameCaptureResolver.callback = Capture.capture;
    HostFrameCaptureResolver.resolved = true;
    var forwarder = Forwarder{};
    defer forwarder.deinit();
    var state = TestState{};
    forwarder.vulkan_presents = 200000;
    forwarder.real_vulkan.device = @ptrFromInt(0x100);
    forwarder.real_vulkan.queue_map[0] = .{ .synthetic = 0x301, .real = 0x302 };
    forwarder.real_vulkan.queue_family_indices[0] = 0;
    forwarder.real_vulkan.queue_family_count = 1;
    forwarder.real_vulkan.queue_family_properties[0] = .{ .queue_flags = abi.QUEUE_GRAPHICS_BIT, .queue_count = 1 };
    forwarder.real_vulkan.swapchain_map[0] = .{ .synthetic = 0x601, .real = 0x701 };
    forwarder.real_vulkan.image_map[0] = .{ .synthetic = 0xa01, .real = 0xb01 };
    forwarder.real_vulkan.swapchain_records[0] = .{ .synthetic = 0x601, .real = 0x701, .image_count = 1 };
    forwarder.real_vulkan.swapchain_records[0].image_handles[0] = 0xa01;
    forwarder.pixel_probe.staging_buffer = 0x501;
    forwarder.pixel_probe.staging_memory = 0x502;
    forwarder.pixel_probe.staging_size = 16;
    forwarder.pixel_probe.mapped = &Capture.staging;
    forwarder.pixel_probe.mapped_coherent = true;
    forwarder.pixel_probe.command_pool = 0x503;
    forwarder.pixel_probe.command_pool_family = 0;
    forwarder.pixel_probe.command_buffer = @ptrFromInt(0x504);
    forwarder.pixel_probe.capture_configured = true;
    forwarder.pixel_probe.preview_enabled = true;
    // First picture delivery bypasses an otherwise-not-due preview timer.
    forwarder.pixel_probe.last_preview_probe_ns = transport_timing.nowNs();
    forwarder.pixel_probe.preview_interval_ns = 60_000_000_000;
    const fns = &forwarder.real_vulkan.fn_ptrs;
    fns.reset_command_buffer = Capture.reset;
    fns.begin_command_buffer = Capture.begin;
    fns.end_command_buffer = Capture.end;
    fns.cmd_pipeline_barrier = Capture.barrier;
    fns.cmd_copy_image_to_buffer = Capture.copy;
    fns.queue_submit = Capture.submit;
    fns.queue_wait_idle = Capture.idle;
    fns.queue_present = Capture.present;
    forwarder.present_chain.noteSwapchain(.{ .handle = 0x701, .width = 2, .height = 2, .format = 37, .image_count = 1, .image_usage = abi.IMAGE_USAGE_TRANSFER_SRC_BIT });
    forwarder.present_chain.noteSwapchainImages(0x701, &.{0xb01});
    forwarder.present_chain.noteAcquire(0x701, 0);
    forwarder.present_chain.noteContent(0x701);
    state.regs.rdi = 0x301;
    state.regs.rsi = 0x100;
    state.write32(0x100 + 32, 1);
    state.write64(0x100 + 40, 0x300);
    state.write64(0x100 + 48, 0x310);
    state.write64(0x300, 0x601);
    state.write32(0x310, 0);
    try std.testing.expectEqual(@as(u64, 0), forwarder.queuePresent(&state));
    try std.testing.expectEqual(@as(u32, 1), Capture.delivered);
    try std.testing.expectEqual(@as(u64, 1), forwarder.picture_sequence.frames);
    try std.testing.expectEqual(@as(u64, 1), forwarder.pixel_probe.capture_policy.picture_saved);
    try std.testing.expectEqual(@as(u64, 1), forwarder.pixel_probe.capture_previewed);
}

test "presentation ceiling sleeps through the runtime release callback and refuses pinned waits" {
    const State = struct {
        pinned: bool = false,
        releases: u32 = 0,
        pub fn tryWithWindowsRuntimeLockReleasedForVulkanQueueWait(self: *@This(), context: anytype, comptime callback: anytype) bool {
            if (self.pinned) return false;
            self.releases += 1;
            callback(context);
            return true;
        }
    };
    const forwarder = try std.testing.allocator.create(Forwarder);
    defer std.testing.allocator.destroy(forwarder);
    forwarder.* = .{};
    defer forwarder.deinit();
    var state: State = .{};
    const now = transport_timing.nowNs();
    if (now == 0) return error.SkipZigTest;
    // First and already-slow frames never invoke a sleep callback.
    try std.testing.expect(forwarder.pacePresent(&state));
    try std.testing.expectEqual(@as(u32, 0), state.releases);
    forwarder.present_ceiling.attempted(now);
    try std.testing.expect(forwarder.pacePresent(&state));
    try std.testing.expectEqual(@as(u32, 1), state.releases);
    try std.testing.expect(transport_timing.nowNs() >= now + present_pacing.Ceiling.interval_ns);
    forwarder.present_ceiling.attempted(transport_timing.nowNs());
    state.pinned = true;
    try std.testing.expect(!forwarder.pacePresent(&state));
    try std.testing.expectEqual(@as(u32, 1), state.releases);
    try std.testing.expectEqual(@as(u64, 1), forwarder.present_ceiling.refused);
}

test "FSI sample view follows descriptor copies and freezes late updates at submission" {
    var forwarder: Forwarder = .{};
    defer forwarder.deinit();
    _ = HandleMap.alloc(&forwarder.real_vulkan.image_map, 0x901, 0x1901);
    _ = HandleMap.alloc(&forwarder.real_vulkan.image_map, 0x902, 0x1902);
    try std.testing.expect(forwarder.recordImageView(0x802, 0x902));
    const slot = forwarder.tracked_image_view_index.find(0x802).?;
    forwarder.tracked_image_views[slot].format = 64;
    forwarder.tracked_image_views[slot].view_type = 1;
    forwarder.tracked_image_views[slot].components = .{ 5, 4, 3, 0 };
    forwarder.noteDescriptorImageInfo(0xB001, 0, 0, .{ .image_view = 0x802 });
    const command = forwarder.mutableCommandTargets(0x501).?;
    command.current_pass_target = 0x901;
    forwarder.noteCommandBoundDescriptorSet(0x501, 1, 0xB002);
    // Recording before the descriptor update is legal and remains observable.
    forwarder.copyDescriptorSetImages(.{ .src_set = 0xB001, .dst_set = 0xB002, .descriptor_count = 1 });
    forwarder.commitCommandPassSources(0x501);
    const submitted = forwarder.present_chain.passSourceViewsOf(0x1901)[0];
    try std.testing.expectEqual(@as(u64, 0x802), submitted.view);
    try std.testing.expectEqualDeep([4]u32{ 5, 4, 3, 0 }, submitted.components);
    try std.testing.expect(submitted.known);
    forwarder.tracked_image_views[slot].components = @splat(0);
    try std.testing.expectEqualDeep(submitted, forwarder.present_chain.passSourceViewsOf(0x1901)[0]);
    forwarder.commitCommandPassSources(0x501);
    try std.testing.expectEqualDeep([4]u32{ 0, 0, 0, 0 }, forwarder.present_chain.passSourceViewsOf(0x1901)[0].components);
    // Replacing with a null view clears the previously known source.
    forwarder.noteDescriptorImageInfo(0xB001, 0, 0, .{});
    forwarder.copyDescriptorSetImages(.{ .src_set = 0xB001, .dst_set = 0xB002, .descriptor_count = 1 });
    try std.testing.expectEqual(@as(u64, 0), forwarder.trackedDescriptorSet(0xB002).?.images[0].image_view);
}

const LiveTextureTestDriver = struct {
    var events: [32]u64 = @splat(0);
    var count: usize = 0;
    var result: abi.Result = abi.SUCCESS;
    var next_layout: u64 = 900;
    var destroyed: u32 = 0;
    var frees: u32 = 0;
    var original_always_succeeds: bool = false;
    fn control(_: u64, _: u32, _: u32, _: u32) callconv(.c) void {}
    fn event(value: u64) void {
        events[count] = value;
        count += 1;
    }
    fn bind(_: abi.CommandBuffer, _: u32, selected: u64) callconv(.c) void {
        event(selected);
    }
    fn sets(_: abi.CommandBuffer, _: u32, selected: u64, first: u32, n: u32, _: [*]const u64, _: u32, _: ?[*]const u32) callconv(.c) void {
        std.debug.assert(first == 2 and n == 2);
        event(selected);
    }
    fn dispatch(_: abi.CommandBuffer, _: u32, _: u32, _: u32) callconv(.c) void {
        event(777);
    }
    fn create(_: abi.Device, _: *const anyopaque, _: ?*const anyopaque, out: *u64) callconv(.c) i32 {
        out.* = 100;
        return result;
    }
    fn layout(_: abi.Device, _: *const anyopaque, _: ?*const anyopaque, out: *u64) callconv(.c) i32 {
        out.* = next_layout;
        next_layout += 1;
        return abi.SUCCESS;
    }
    fn pipeline(_: abi.Device, _: u64, _: u32, infos: [*]const abi.ComputePipelineCreateInfo, _: ?*const anyopaque, out: [*]u64) callconv(.c) i32 {
        if (original_always_succeeds and infos[0].stage.module == 200) {
            out[0] = 750;
            return abi.SUCCESS;
        }
        out[0] = if (result == abi.SUCCESS) 800 else 0;
        return result;
    }
    fn destroy(_: abi.Device, _: u64, _: ?*const anyopaque) callconv(.c) void {
        destroyed += 1;
    }
    fn allocate(_: abi.Device, _: *const abi.DescriptorSetAllocateInfo, out: [*]u64) callconv(.c) i32 {
        out[0] = 600;
        return result;
    }
    fn free(_: abi.Device, _: u64, _: u32, _: [*]const u64) callconv(.c) i32 {
        frees += 1;
        return result;
    }
    fn update(_: abi.Device, _: u32, _: ?[*]const abi.WriteDescriptorSet, _: u32, _: ?[*]const abi.CopyDescriptorSet) callconv(.c) void {}
};

fn liveTextureFixture(forwarder: *Forwarder, native: *native_texture.State, memory: []u8) !void {
    LiveTextureTestDriver.count = 0;
    LiveTextureTestDriver.result = abi.SUCCESS;
    LiveTextureTestDriver.next_layout = 900;
    LiveTextureTestDriver.destroyed = 0;
    LiveTextureTestDriver.frees = 0;
    LiveTextureTestDriver.original_always_succeeds = false;
    native.* = .{ .control = LiveTextureTestDriver.control, .module = 100, .bounds_layout = 101, .bounds_pool = 102, .bounds_buffer = 103, .mapped = memory.ptr };
    forwarder.native_texture_state = native;
    forwarder.real_vulkan.device = @ptrFromInt(0x1234);
    forwarder.real_vulkan.fn_ptrs.cmd_bind_pipeline = LiveTextureTestDriver.bind;
    forwarder.real_vulkan.fn_ptrs.cmd_bind_descriptor_sets = LiveTextureTestDriver.sets;
    forwarder.real_vulkan.fn_ptrs.cmd_dispatch = LiveTextureTestDriver.dispatch;
    forwarder.real_vulkan.fn_ptrs.create_shader_module = LiveTextureTestDriver.create;
    forwarder.real_vulkan.fn_ptrs.create_pipeline_layout = LiveTextureTestDriver.layout;
    forwarder.real_vulkan.fn_ptrs.create_compute_pipelines = LiveTextureTestDriver.pipeline;
    forwarder.real_vulkan.fn_ptrs.destroy_shader_module = LiveTextureTestDriver.destroy;
    forwarder.real_vulkan.fn_ptrs.destroy_pipeline_layout = LiveTextureTestDriver.destroy;
    forwarder.real_vulkan.fn_ptrs.destroy_pipeline = LiveTextureTestDriver.destroy;
    forwarder.real_vulkan.fn_ptrs.allocate_descriptor_sets = LiveTextureTestDriver.allocate;
    forwarder.real_vulkan.fn_ptrs.free_descriptor_sets = LiveTextureTestDriver.free;
    forwarder.real_vulkan.fn_ptrs.update_descriptor_sets = LiveTextureTestDriver.update;
    try native.layouts.put(std.heap.c_allocator, 500, .{ .sets = .{ 10, 11 } });
    native.noteShader(200, .dxt5);
    native.addPipeline(&forwarder.real_vulkan, 700, .{ .stage = .{ .module = 200, .name = "main" }, .layout = 500 });
    try std.testing.expectEqual(@as(u32, 1), native.pipelines.count());
    native.noteBuffer(300, 4096);
    native.noteBuffer(301, 4096);
    const buffers = [_]abi.DescriptorBufferInfo{ .{ .buffer = 300, .offset = 32, .range = 2048 }, .{ .buffer = 301, .offset = 64, .range = 1024 } };
    for (&buffers, 0..) |*buffer, i| native.noteWrite(.{ .dst_set = 400 + i, .descriptor_type = 7, .descriptor_count = 1, .buffer_info = @ptrCast(buffer) });
    const c = native.command(0x111).?;
    c.pipeline = 700;
    c.bind(500, 0, &.{ 400, 401 }, 0);
    const p = native_texture.Push{ .flags = 0x91, .guest_offset = 32, .guest_pitch = 32, .guest_z_rows = 32, .blocks_x = 5, .blocks_y = 3, .blocks_z = 1, .host_offset = 16, .host_pitch = 128, .height = 11 };
    c.constants(500, 0, std.mem.asBytes(&p));
    _ = HandleMap.alloc(&forwarder.real_vulkan.command_buffer_map, 0x111, 0x222);
}

test "native Metal live texture production dispatch restores original state and declines incompatible work" {
    var forwarder = Forwarder{};
    var native: native_texture.State = undefined;
    var memory: [65536]u8 = @splat(0);
    try liveTextureFixture(&forwarder, &native, &memory);
    defer native.releaseCpu();
    var state = TestState{};
    state.regs.rdi = 0x111;
    state.regs.rsi = 1;
    state.regs.rdx = 1;
    state.regs.rcx = 1;
    forwarder.forwardVulkanCommand(&state, vulkanNameHash("vkCmdDispatch"), "vkCmdDispatch");
    try std.testing.expectEqualSlices(u64, &.{ 800, 900, 777, 700 }, LiveTextureTestDriver.events[0..LiveTextureTestDriver.count]);
    try std.testing.expectEqual(@as(u64, 1), native.dispatches[3]);
    // Group mismatch must leave the original path and encode no private bind.
    state.regs.rsi = 2;
    forwarder.forwardVulkanCommand(&state, vulkanNameHash("vkCmdDispatch"), "vkCmdDispatch");
    try std.testing.expectEqual(@as(usize, 5), LiveTextureTestDriver.count);
    try std.testing.expectEqual(@as(u64, 777), LiveTextureTestDriver.events[4]);
    try std.testing.expectEqual(@as(u64, 1), native.dispatches[3]);
}

test "native Metal live texture bounds follow writes copies buffer destruction and pool lifetime" {
    var forwarder = Forwarder{};
    var native: native_texture.State = undefined;
    var memory: [65536]u8 = @splat(0);
    try liveTextureFixture(&forwarder, &native, &memory);
    defer native.releaseCpu();
    try std.testing.expect(native.dispatch(&forwarder.real_vulkan, 0x111, @ptrFromInt(0x222), .{ 1, 1, 1 }));
    const slot = native.bounds.get(400).?.slot.?;
    const buffer = abi.DescriptorBufferInfo{ .buffer = 300, .offset = 4000, .range = 64 };
    native.noteWrite(.{ .dst_set = 400, .descriptor_type = 7, .descriptor_count = 1, .buffer_info = @ptrCast(&buffer) });
    try std.testing.expectEqual(@as(u32, 64), std.mem.readInt(u32, memory[@as(usize, slot) * 16 ..][0..4], .little));
    native.noteCopy(.{ .src_set = 400, .dst_set = 401, .descriptor_count = 1 });
    try std.testing.expectEqual(@as(u32, 64), native.bounds.get(401).?.bytes);
    native.forgetBuffer(300);
    try std.testing.expectEqual(@as(u32, 0), native.bounds.get(401).?.bytes);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, memory[@as(usize, slot) * 16 ..][0..4], .little));
    _ = HandleMap.allocOrFindOwned(&forwarder.real_vulkan.descriptor_set_map, 60, 400, 70);
    _ = HandleMap.allocOrFindOwned(&forwarder.real_vulkan.descriptor_set_map, 61, 401, 70);
    _ = forwarder.reclaimDescriptorSetsForPool(70, "reset");
    try std.testing.expectEqual(@as(u32, 0), native.bounds.count());
    try std.testing.expectEqual(@as(u32, 2), LiveTextureTestDriver.frees);
    try std.testing.expect(!native.slots[slot]);
}

test "native Metal live texture rejects compiler failures but never hides real device loss" {
    var forwarder = Forwarder{};
    var native: native_texture.State = undefined;
    var memory: [65536]u8 = @splat(0);
    try liveTextureFixture(&forwarder, &native, &memory);
    defer native.releaseCpu();
    LiveTextureTestDriver.result = abi.ERROR_INITIALIZATION_FAILED;
    const info = abi.ComputePipelineCreateInfo{ .stage = .{ .module = 200, .name = "main" }, .layout = 500 };
    native.addPipeline(&forwarder.real_vulkan, 701, info);
    try std.testing.expect(native.pipelines.get(701) == null);
    try std.testing.expectEqual(abi.SUCCESS, native.terminal_result);
    LiveTextureTestDriver.result = abi.ERROR_DEVICE_LOST;
    native.addPipeline(&forwarder.real_vulkan, 702, info);
    try std.testing.expectEqual(abi.ERROR_DEVICE_LOST, native.terminal_result);
    try std.testing.expect(!native.dispatch(&forwarder.real_vulkan, 0x111, @ptrFromInt(0x222), .{ 1, 1, 1 }));
    try std.testing.expectEqual(@as(usize, 0), LiveTextureTestDriver.count);
}

test "native Metal live texture destroyed layout handle reuse keeps existing private layout" {
    var forwarder = Forwarder{};
    var native: native_texture.State = undefined;
    var memory: [65536]u8 = @splat(0);
    try liveTextureFixture(&forwarder, &native, &memory);
    defer native.releaseCpu();
    native.forgetLayout(&forwarder.real_vulkan, 500);
    try native.layouts.put(std.heap.c_allocator, 500, .{ .sets = .{ 12, 13 } });
    native.addPipeline(&forwarder.real_vulkan, 701, .{ .stage = .{ .module = 200, .name = "main" }, .layout = 500 });
    try std.testing.expectEqual(@as(u64, 900), native.pipelines.get(700).?.native_layout);
    try std.testing.expectEqual(@as(u64, 901), native.pipelines.get(701).?.native_layout);
    try std.testing.expectEqualSlices(u64, &.{ 900, 901 }, native.owned_layouts.items);
    try std.testing.expect(native.dispatch(&forwarder.real_vulkan, 0x111, @ptrFromInt(0x222), .{ 1, 1, 1 }));
    try std.testing.expectEqual(@as(u64, 900), LiveTextureTestDriver.events[1]);
    native.forgetPipeline(&forwarder.real_vulkan, 700);
    try std.testing.expectEqual(@as(u32, 1), LiveTextureTestDriver.destroyed);
}

test "native Metal live texture allocation refusal keeps baseline and failed free quarantines cell" {
    var forwarder = Forwarder{};
    var native: native_texture.State = undefined;
    var memory: [65536]u8 = @splat(0);
    try liveTextureFixture(&forwarder, &native, &memory);
    defer native.releaseCpu();
    LiveTextureTestDriver.result = abi.ERROR_INITIALIZATION_FAILED;
    var state = TestState{};
    state.regs.rdi = 0x111;
    state.regs.rsi = 1;
    state.regs.rdx = 1;
    state.regs.rcx = 1;
    forwarder.forwardVulkanCommand(&state, vulkanNameHash("vkCmdDispatch"), "vkCmdDispatch");
    try std.testing.expectEqualSlices(u64, &.{777}, LiveTextureTestDriver.events[0..LiveTextureTestDriver.count]);
    try std.testing.expectEqual(@as(u64, 0), native.bounds.get(400).?.meta);
    LiveTextureTestDriver.result = abi.SUCCESS;
    try std.testing.expect(native.dispatch(&forwarder.real_vulkan, 0x111, @ptrFromInt(0x222), .{ 1, 1, 1 }));
    const slot = native.bounds.get(400).?.slot.?;
    LiveTextureTestDriver.result = abi.ERROR_INITIALIZATION_FAILED;
    native.forgetSet(&forwarder.real_vulkan, 400);
    try std.testing.expect(native.slots[slot]);
    try std.testing.expect(native.bounds.get(400) == null);
    try std.testing.expectEqual(abi.SUCCESS, native.terminal_result);
}

test "native Metal live texture production pipeline marshalling preserves accepted baseline on native refusal" {
    var forwarder = Forwarder{};
    var native: native_texture.State = undefined;
    var memory: [65536]u8 = @splat(0);
    try liveTextureFixture(&forwarder, &native, &memory);
    defer native.releaseCpu();
    var state = TestState{};
    _ = HandleMap.alloc(&forwarder.real_vulkan.shader_module_map, 3, 200);
    _ = HandleMap.alloc(&forwarder.real_vulkan.pipeline_layout_map, 1, 500);
    const info = abi.ComputePipelineCreateInfo{ .stage = .{ .module = 3, .stage = 0x20, .name = @ptrFromInt(512) }, .layout = 1 };
    @memcpy(state.mem[64..][0..@sizeOf(@TypeOf(info))], std.mem.asBytes(&info));
    @memcpy(state.mem[512..517], "main\x00");
    LiveTextureTestDriver.original_always_succeeds = true;
    LiveTextureTestDriver.result = abi.ERROR_INITIALIZATION_FAILED;
    var output: u64 = 0;
    var result: i32 = 0;
    try forwarder.marshalRealComputePipeline(&state, 0, 64, &output, &result);
    try std.testing.expectEqual(abi.SUCCESS, result);
    try std.testing.expectEqual(@as(u64, 750), output);
    try std.testing.expect(native.pipelines.get(750) == null);
    LiveTextureTestDriver.result = abi.SUCCESS;
    try forwarder.marshalRealComputePipeline(&state, 0, 64, &output, &result);
    try std.testing.expectEqual(abi.SUCCESS, result);
    try std.testing.expectEqual(@as(u64, 800), native.pipelines.get(750).?.native);
    native.forgetPipeline(&forwarder.real_vulkan, 750);
    LiveTextureTestDriver.result = abi.ERROR_DEVICE_LOST;
    try forwarder.marshalRealComputePipeline(&state, 0, 64, &output, &result);
    try std.testing.expectEqual(abi.ERROR_DEVICE_LOST, result);
    try std.testing.expect(forwarder.real_vulkan.device_lost);
}

test "only Xenia's built-in index buffer is recognised as rectangle expansion indices" {
    // Point sprites and rectangles expanded: UINT16_MAX two-triangle strips,
    // plus the 16-bit fan and quad sections.
    try std.testing.expect(rectExpansionBuiltinIndexBuffer(4 * (5 * 0xFFFF - 1) + 393198 + 196596, 0x42));
    try std.testing.expect(rectExpansionBuiltinIndexBuffer(436896, 0x42));
    try std.testing.expect(!rectExpansionBuiltinIndexBuffer(436895, 0x42));
    // The upload twin, the converted-index pool and the shared memory.
    try std.testing.expect(!rectExpansionBuiltinIndexBuffer(1310696, 0x1));
    try std.testing.expect(!rectExpansionBuiltinIndexBuffer(2 * 1024 * 1024, 0x40));
    try std.testing.expect(!rectExpansionBuiltinIndexBuffer(512 * 1024 * 1024, 0x40 | 0x20 | 0x2 | 0x1));
}

test "FSI MoltenVK defaults preserve shader arithmetic and stop after GPU device loss" {
    for (moltenvk_runtime_defaults) |setting| {
        try std.testing.expectEqualStrings("0", std.mem.span(setting.value));
    }
}

test "FSI coalesces only adjacent single-buffer chunks without a semaphore dependency crossing" {
    const first = FsiSegment{
        .command_count = 1,
        .guest_command_buffer = 0x501,
        .segment_in_guest = 0,
        .guest_segments = 3,
    };
    const second = FsiSegment{
        .command_count = 1,
        .guest_command_buffer = 0x501,
        .segment_in_guest = 1,
        .guest_segments = 3,
    };
    try std.testing.expect(fsiCanCoalesceSegments(first, second));
    var isolated = first;
    isolated.isolated = true;
    try std.testing.expect(!fsiCanCoalesceSegments(isolated, second));
    isolated = second;
    isolated.isolated = true;
    try std.testing.expect(!fsiCanCoalesceSegments(first, isolated));
    try std.testing.expect(!fsiCanCoalesceSegments(first, .{ .command_count = 1, .guest_command_buffer = 0x502, .segment_in_guest = 1 }));
    try std.testing.expect(!fsiCanCoalesceSegments(first, .{ .command_count = 1, .guest_command_buffer = 0x501, .segment_in_guest = 2 }));
    try std.testing.expect(!fsiCanCoalesceSegments(.{ .command_count = 2, .guest_command_buffer = 0x501 }, second));
    try std.testing.expect(!fsiCanCoalesceSegments(first, .{ .command_count = 2, .guest_command_buffer = 0x501, .segment_in_guest = 1 }));
    try std.testing.expect(!fsiCanCoalesceSegments(.{ .command_count = 1, .guest_command_buffer = 0x501, .signal_count = 1 }, second));
    try std.testing.expect(!fsiCanCoalesceSegments(first, .{ .command_count = 1, .guest_command_buffer = 0x501, .segment_in_guest = 1, .wait_count = 1 }));
    try std.testing.expect(!fsiCanCoalesceSegments(.{ .command_count = 1, .segment_in_guest = 0 }, .{ .command_count = 1, .segment_in_guest = 1 }));
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

test "guest Vulkan symbol lookup caches exact names and recovers from direct-map collisions" {
    var forwarder = Forwarder{};
    const library_token: u64 = GUEST_LIBRARY_HANDLE_BASE + 17;
    const first_name = "vkCmdDrawIndexed";
    const first_hash = vulkanNameHash(first_name);
    const target_slot = guestSymbolLookupCacheIndex(library_token, first_hash);
    var collision_buffer: [48]u8 = undefined;
    var collision_name: ?[]const u8 = null;
    for (0..100_000) |candidate| {
        const formatted = try std.fmt.bufPrint(&collision_buffer, "vkCmdCacheCollision{d}", .{candidate});
        if (!std.mem.eql(u8, formatted, first_name) and
            guestSymbolLookupCacheIndex(library_token, vulkanNameHash(formatted)) == target_slot)
        {
            collision_name = formatted;
            break;
        }
    }
    const colliding_name = collision_name orelse return error.TestUnexpectedResult;

    const first = forwarder.allocateGuestSymbol(library_token, first_name);
    try std.testing.expect(first != 0);
    try std.testing.expectEqual(first, forwarder.allocateGuestSymbol(library_token, first_name));
    const colliding = forwarder.allocateGuestSymbol(library_token, colliding_name);
    try std.testing.expect(colliding != 0 and colliding != first);
    try std.testing.expectEqual(first, forwarder.allocateGuestSymbol(library_token, first_name));
    try std.testing.expectEqual(first, forwarder.allocateGuestSymbol(library_token, first_name));
    try std.testing.expectEqual(@as(u64, 2), forwarder.guest_lookup_count);
    try std.testing.expectEqual(@as(u64, 2), forwarder.guest_symbol_lookup_cache_hits);
    try std.testing.expectEqual(@as(u64, 3), forwarder.guest_symbol_lookup_cache_misses);

    // The repeated loader-evidence lookup is now a direct token-slot access;
    // its first/repeated logging semantics are unchanged.
    try std.testing.expect(forwarder.noteVulkanLoaderLookup(library_token, first_name, first));
    try std.testing.expect(!forwarder.noteVulkanLoaderLookup(library_token, first_name, first));
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_loader_lookup_unique);
    try std.testing.expectEqual(@as(u64, 1), forwarder.vulkan_loader_lookup_repeats);
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

test "guest Vulkan surface extension aliases have one negotiation contract" {
    const host_name = Forwarder.guestInstanceExtensionAlias("VK_KHR_win32_surface").?;
    try std.testing.expectEqualStrings("VK_EXT_metal_surface", host_name);
    try std.testing.expect(Forwarder.guestInstanceExtensionAlias("VK_KHR_xcb_surface") == null);

    for (guest_instance_extension_aliases) |alias| {
        try std.testing.expect(alias.guest_name.len < abi.MAX_EXTENSION_NAME_SIZE);
        try std.testing.expect(alias.host_name.len < abi.MAX_EXTENSION_NAME_SIZE);
        try std.testing.expect(alias.spec_version != 0);
    }
}

test "Vulkan physical device properties model follows x64 C ABI alignment" {
    try std.testing.expectEqual(@as(usize, 296), VK_PHYSICAL_DEVICE_LIMITS_OFFSET);
    try std.testing.expectEqual(@as(u64, 824), VK_PHYSICAL_DEVICE_PROPERTIES_SIZE);
}

test "Vulkan synthetic/native range checks reject wrapped or partial ranges" {
    try std.testing.expect(rangeContains(100, 20, 100, 20));
    try std.testing.expect(rangeContains(100, 20, 119, 1));
    try std.testing.expect(rangeContains(100, 20, 120, 0));
    try std.testing.expect(!rangeContains(100, 20, 120, 1));
    try std.testing.expect(!rangeContains(100, 20, 99, 1));
    try std.testing.expect(!rangeContains(0, std.math.maxInt(u64), std.math.maxInt(u64), 1));
}

test "Vulkan queue2 refuses an unrepresentable guest request" {
    var forwarder = Forwarder{};
    var state = TestState{};
    const info: u64 = 64;
    const output: u64 = 128;
    state.regs.rdi = VK_SYNTHETIC_DEVICE;
    state.regs.rsi = info;

    // A queue2 structure with the legacy queue-info sType is not equivalent
    // to vkGetDeviceQueue. Returning a synthetic queue here would conceal a
    // guest ABI mismatch and poison the first queue submission.
    state.write32(info, abi.STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO);
    try std.testing.expectEqual(vkErrorInitializationFailed(), forwarder.writeDeviceQueue(&state, output, "vkGetDeviceQueue2"));
    try std.testing.expectEqual(@as(u64, 0), state.read64(output));

    state.write32(info, abi.STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2);
    state.write64(info + 8, 0);
    state.write32(info + 16, 0);
    state.write32(info + 20, 0);
    state.write32(info + 24, 0);
    try std.testing.expectEqual(@as(u64, 0), forwarder.writeDeviceQueue(&state, output, "vkGetDeviceQueue2"));
    try std.testing.expectEqual(VK_SYNTHETIC_QUEUE, state.read64(output));
}

test "unknown Vulkan device feature pNext nodes are refused" {
    var forwarder = Forwarder{};
    var state = TestState{};
    var scratch: FeatureChainScratch = .{};
    const node: u64 = 64;
    state.write32(node, 0xDEAD);
    state.write64(node + 8, 0);
    try std.testing.expect(!forwarder.collectFeatureChain(&state, node, &scratch, false));
    try std.testing.expectEqual(@as(usize, 0), scratch.count);
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

test "Vulkan FSI features are forwarded and unsupported interlock bits are refused" {
    try std.testing.expectEqual(@as(?usize, 3), featureChainKind(abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT));
    try std.testing.expectEqual(abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT, featureChainSType(3));

    var forwarder = Forwarder{};
    var state = TestState{};
    const node: u64 = 64;
    state.write32(node, abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT);
    state.write64(node + 8, 0);
    state.write32(node + 16, 1); // fragmentShaderSampleInterlock
    state.write32(node + 20, 1); // fragmentShaderPixelInterlock
    state.write32(node + 24, 0); // fragmentShaderShadingRateInterlock

    forwarder.real_vulkan.feature_chain_valid[3] = true;
    forwarder.real_vulkan.feature_chain_sizes[3] = featureChainSize(3);
    const host = &forwarder.real_vulkan.feature_chain_supported[3];
    std.mem.writeInt(u32, host[0..4], abi.STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT, .little);
    std.mem.writeInt(u32, host[16..20], 1, .little);
    std.mem.writeInt(u32, host[20..24], 1, .little);
    std.mem.writeInt(u32, host[24..28], 0, .little);

    const request = fsiGuestFeatureRequest(&state, node);
    try std.testing.expectEqual(FsiGuestChainStatus.present, request.status);
    try std.testing.expect(request.sample and request.pixel and !request.shading_rate);

    var scratch: FeatureChainScratch = .{};
    try std.testing.expect(forwarder.prepareDeviceFeatureChain(&state, node, &scratch));
    try std.testing.expect(featureChainBoolAt(&scratch.nodes[3], 0));
    try std.testing.expect(featureChainBoolAt(&scratch.nodes[3], 1));
    try std.testing.expect(!featureChainBoolAt(&scratch.nodes[3], 2));

    state.write32(node + 24, 1);
    try std.testing.expect(!forwarder.prepareDeviceFeatureChain(&state, node, &scratch));
}

test "native Vulkan device handles are published to guest output memory" {
    var state = TestState{};
    const device: abi.Device = @ptrFromInt(0x1234);
    try std.testing.expect(publishVulkanDispatchableHandle(&state, 8, device));
    try std.testing.expectEqual(@as(u64, 0x1234), state.read64(8));
    try std.testing.expect(!publishVulkanDispatchableHandle(&state, 0, device));
    try std.testing.expect(!publishVulkanDispatchableHandle(&state, 8, null));
}

test "Vulkan bootstrap output parameters use address-based writes in parallel mode" {
    var state = TestState{ .parallel_guest_execution = true };
    const count_address: u64 = 8;
    const version_address: u64 = 16;
    const handle_address: u64 = 24;
    const array_address: u64 = 32;

    try std.testing.expect(state.guestMemory(count_address, 4) == null);
    try std.testing.expect(guestRangeAvailable(&state, count_address, 4));
    try std.testing.expectEqual(@as(u64, 0), writeApiVersion(&state, version_address));
    try std.testing.expectEqual(@as(u32, 0x0040_2000), state.read32(version_address));
    try std.testing.expectEqual(@as(u64, 0), enumerateEmpty(&state, count_address));
    try std.testing.expectEqual(@as(u32, 0), state.read32(count_address));

    state.write32(count_address, 1);
    try std.testing.expectEqual(@as(u64, 0), enumerateHandle(&state, count_address, array_address, 0x1234, "VkPhysicalDevice", false));
    try std.testing.expectEqual(@as(u64, 0x1234), state.read64(array_address));
    try std.testing.expectEqual(@as(u32, 1), state.read32(count_address));

    const device: abi.Device = @ptrFromInt(0x5678);
    try std.testing.expect(publishVulkanDispatchableHandle(&state, handle_address, device));
    try std.testing.expectEqual(@as(u64, 0x5678), state.read64(handle_address));
}

test "physical-device properties and features reach the guest without a raw view" {
    // The 2026-09-30 crash: with raw views refused, both writes were
    // dropped, Xenia saw Vulkan device '' without independentBlend and
    // rejected the only GPU.
    var forwarder = Forwarder{};
    const name = "Apple M2 Max";
    const device_name_offset = 20;
    const independent_blend_offset = 12;
    const tessellation_shader_offset = abi.PHYSICAL_DEVICE_FEATURES_TESSELLATION_SHADER_OFFSET;
    @memcpy(forwarder.real_vulkan.physical_device_properties[device_name_offset..][0..name.len], name);
    std.mem.writeInt(u32, forwarder.real_vulkan.physical_device_features[independent_blend_offset..][0..4], 1, .little);
    std.mem.writeInt(u32, forwarder.real_vulkan.physical_device_features[tessellation_shader_offset..][0..4], 1, .little);

    var state = TestState{ .parallel_guest_execution = true };
    const properties_output: u64 = 0x1000;
    const features_output: u64 = 0x2000;
    const properties2_output: u64 = 0x3000;
    try std.testing.expect(state.guestMemory(properties_output, 8) == null);

    forwarder.writeRealPhysicalDeviceProperties(&state, properties_output);
    forwarder.writeRealPhysicalDeviceFeatures(&state, features_output);
    try std.testing.expectEqualStrings(name, std.mem.sliceTo(state.mem[properties_output + device_name_offset ..][0..256], 0));
    try std.testing.expectEqual(@as(u32, 1), state.read32(features_output + independent_blend_offset));
    try std.testing.expectEqual(@as(u32, 1), state.read32(features_output + tessellation_shader_offset));
    try std.testing.expect(coreFeatureEnabled(&forwarder.real_vulkan.physical_device_features, tessellation_shader_offset));

    // The *2 forms carry the same core structure after sType and pNext.
    forwarder.writeRealPhysicalDeviceProperties2(&state, properties2_output);
    try std.testing.expectEqualStrings(name, std.mem.sliceTo(state.mem[properties2_output + 16 + device_name_offset ..][0..256], 0));
}

test "native tessellation pipeline state forwards the legal domain-origin pNext" {
    var state = TestState{};
    const tessellation_address: u64 = 0x1000;
    const domain_origin_address: u64 = 0x1040;
    state.write32(tessellation_address, abi.STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO);
    state.write64(tessellation_address + 8, domain_origin_address);
    state.write32(tessellation_address + 16, 0);
    state.write32(tessellation_address + 20, 3);
    state.write32(domain_origin_address, abi.STRUCTURE_TYPE_PIPELINE_TESSELLATION_DOMAIN_ORIGIN_STATE_CREATE_INFO);
    state.write64(domain_origin_address + 8, 0);
    state.write32(domain_origin_address + 16, 1); // VK_TESSELLATION_DOMAIN_ORIGIN_LOWER_LEFT

    var tessellation: abi.PipelineTessellationStateCreateInfo = .{};
    var domain_origin: abi.PipelineTessellationDomainOriginStateCreateInfo = .{};
    try Forwarder.marshalPipelineTessellationState(&state, tessellation_address, &tessellation, &domain_origin);

    try std.testing.expectEqual(@as(u32, 3), tessellation.patch_control_points);
    try std.testing.expectEqual(@as(u32, 1), domain_origin.domain_origin);
    try std.testing.expectEqual(@intFromPtr(&domain_origin), @intFromPtr(tessellation.p_next.?));
}

test "tessellation feature offset and pNext validation are explicit" {
    var features = [_]u8{0} ** 220;
    try std.testing.expect(!coreFeatureEnabled(&features, abi.PHYSICAL_DEVICE_FEATURES_TESSELLATION_SHADER_OFFSET));
    std.mem.writeInt(u32, features[abi.PHYSICAL_DEVICE_FEATURES_TESSELLATION_SHADER_OFFSET..][0..4], 1, .little);
    try std.testing.expect(coreFeatureEnabled(&features, abi.PHYSICAL_DEVICE_FEATURES_TESSELLATION_SHADER_OFFSET));
    try std.testing.expect(!coreFeatureEnabled(&features, features.len - 2));
    try std.testing.expectEqual(@as(usize, 24), abi.PHYSICAL_DEVICE_FEATURES_SAMPLE_RATE_SHADING_OFFSET);
    try std.testing.expectEqual(@as(usize, 104), abi.PHYSICAL_DEVICE_FEATURES_FRAGMENT_STORES_AND_ATOMICS_OFFSET);
    std.mem.writeInt(u32, features[abi.PHYSICAL_DEVICE_FEATURES_SAMPLE_RATE_SHADING_OFFSET..][0..4], 1, .little);
    std.mem.writeInt(u32, features[abi.PHYSICAL_DEVICE_FEATURES_FRAGMENT_STORES_AND_ATOMICS_OFFSET..][0..4], 1, .little);
    try std.testing.expect(coreFeatureEnabled(&features, abi.PHYSICAL_DEVICE_FEATURES_SAMPLE_RATE_SHADING_OFFSET));
    try std.testing.expect(coreFeatureEnabled(&features, abi.PHYSICAL_DEVICE_FEATURES_FRAGMENT_STORES_AND_ATOMICS_OFFSET));

    var state = TestState{};
    const tessellation_address: u64 = 0x1000;
    const unknown_node_address: u64 = 0x1040;
    state.write32(tessellation_address, abi.STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO);
    state.write64(tessellation_address + 8, unknown_node_address);
    state.write32(unknown_node_address, 0xDEAD);
    state.write64(unknown_node_address + 8, 0);
    var tessellation: abi.PipelineTessellationStateCreateInfo = .{};
    var domain_origin: abi.PipelineTessellationDomainOriginStateCreateInfo = .{};
    try std.testing.expectError(
        error.TessellationChainUnsupported,
        Forwarder.marshalPipelineTessellationState(&state, tessellation_address, &tessellation, &domain_origin),
    );
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
    _ = HandleMap.allocOrFind(&forwarder.real_vulkan.swapchain_map, synthetic_swapchain, real_swapchain);
    _ = HandleMap.allocOrFind(&forwarder.real_vulkan.image_map, synthetic_image, real_image);
    forwarder.destroyRealSwapchain(synthetic_swapchain);
    try std.testing.expect(forwarder.real_vulkan.realSwapchain(synthetic_swapchain) == null);
    try std.testing.expect(forwarder.real_vulkan.realImage(synthetic_image) == null);
    try std.testing.expect(forwarder.real_vulkan.mutableSwapchainRecord(synthetic_swapchain) == null);
}

test "present completion is proven by a polled fence, never a wait" {
    const Driver = struct {
        var status: abi.Result = abi.NOT_READY;
        var submits: u32 = 0;
        var resets: u32 = 0;
        fn create(_: abi.Device, _: *const abi.FenceCreateInfo, _: ?*const anyopaque, fence: *abi.Fence) callconv(.c) abi.Result {
            fence.* = 0x77;
            return abi.SUCCESS;
        }
        fn fenceStatus(_: abi.Device, fence: abi.Fence) callconv(.c) abi.Result {
            std.debug.assert(fence == 0x77);
            return status;
        }
        fn reset(_: abi.Device, count: u32, fences: [*]const abi.Fence) callconv(.c) abi.Result {
            std.debug.assert(count == 1 and fences[0] == 0x77);
            resets += 1;
            return abi.SUCCESS;
        }
        fn submit(_: abi.Queue, count: u32, _: ?[*]const abi.SubmitInfo, fence: abi.Fence) callconv(.c) abi.Result {
            std.debug.assert(count == 0 and fence == 0x77);
            submits += 1;
            return abi.SUCCESS;
        }
    };
    Driver.status = abi.NOT_READY;
    Driver.submits = 0;
    Driver.resets = 0;
    var forwarder: Forwarder = .{};
    forwarder.real_vulkan.device = @ptrFromInt(0x1234);
    forwarder.real_vulkan.fn_ptrs.create_fence = Driver.create;
    forwarder.real_vulkan.fn_ptrs.get_fence_status = Driver.fenceStatus;
    forwarder.real_vulkan.fn_ptrs.reset_fences = Driver.reset;
    forwarder.real_vulkan.fn_ptrs.queue_submit = Driver.submit;
    const queue: abi.Queue = @ptrFromInt(0x302);
    // Present 1: the fence goes in behind it.
    try std.testing.expect(forwarder.trackPresentCompletion(queue));
    forwarder.vulkan_real_presents = 1;
    try std.testing.expectEqual(@as(u32, 1), Driver.submits);
    // Present 2 while the GPU is still behind: no second fence, no wait.
    try std.testing.expect(forwarder.trackPresentCompletion(queue));
    forwarder.vulkan_real_presents = 2;
    try std.testing.expectEqual(@as(u32, 1), Driver.submits);
    try std.testing.expectEqual(@as(u64, 0), forwarder.present_completion_confirmed);
    // Present 3 after the fence signalled: present 1 is confirmed and a new
    // fence follows present 3.
    Driver.status = abi.SUCCESS;
    try std.testing.expect(forwarder.trackPresentCompletion(queue));
    try std.testing.expectEqual(@as(u64, 1), forwarder.present_completion_confirmed);
    try std.testing.expectEqual(@as(u64, 3), forwarder.present_completion_fence_target);
    try std.testing.expectEqual(@as(u32, 2), Driver.submits);
    // A device loss surfaces as a failure, not a completion.
    Driver.status = abi.ERROR_DEVICE_LOST;
    try std.testing.expect(!forwarder.trackPresentCompletion(queue));
    try std.testing.expectEqual(@as(u64, 1), forwarder.present_completion_failures);
    try std.testing.expect(!forwarder.present_completion_fence_pending);
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

test {
    _ = @import("shader_compile_tests.zig");
    _ = @import("pipeline_lookup_tests.zig");
}
