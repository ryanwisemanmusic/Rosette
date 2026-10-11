// Split implementation for Forwarder; wrappers keep the public state API stable.
const process = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = process.__ForwarderInternals;
const Forwarder = process.Forwarder;
const GUEST_LIBRARY_HANDLE_BASE = __ForwarderInternals._GUEST_LIBRARY_HANDLE_BASE;
const GraphicsOwnershipSnapshot = __ForwarderInternals._GraphicsOwnershipSnapshot;
const GuestLibrary = __ForwarderInternals._GuestLibrary;
const HandleMap = __ForwarderInternals._HandleMap;
const Outcome = __ForwarderInternals._Outcome;
const RTLD_LAZY = __ForwarderInternals._RTLD_LAZY;
const RTLD_LOCAL = __ForwarderInternals._RTLD_LOCAL;
const Signature = __ForwarderInternals._Signature;
const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP = __ForwarderInternals._VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
const VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT = __ForwarderInternals._VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT;
const VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT = __ForwarderInternals._VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
const VK_SHADER_STAGE_VERTEX_BIT = __ForwarderInternals._VK_SHADER_STAGE_VERTEX_BIT;
const abi = __ForwarderInternals._abi;
const dlclose = __ForwarderInternals._dlclose;
const dlerror = __ForwarderInternals._dlerror;
const dlopen = __ForwarderInternals._dlopen;
const dlsym = __ForwarderInternals._dlsym;
const fsi_diagnostics = __ForwarderInternals._fsi_diagnostics;
const guest_context = __ForwarderInternals._guest_context;
const guest_memory_geometry = __ForwarderInternals._guest_memory_geometry;
const guest_sleep = __ForwarderInternals._guest_sleep;
const isVulkanLoaderPath = __ForwarderInternals._isVulkanLoaderPath;
const lastDlError = __ForwarderInternals._lastDlError;
const libraryMatches = __ForwarderInternals._libraryMatches;
const machoCapturePrint = __ForwarderInternals._machoCapturePrint;
const marshal = __ForwarderInternals._marshal;
const normalizeMachOSymbol = __ForwarderInternals._normalizeMachOSymbol;
const nulTerminate = __ForwarderInternals._nulTerminate;
const registerOpaqueHandle = __ForwarderInternals._registerOpaqueHandle;
const rosette_gpu = __ForwarderInternals._rosette_gpu;
const sparseVulkanSuccessLog = __ForwarderInternals._sparseVulkanSuccessLog;
const specFor = __ForwarderInternals._specFor;
const std = __ForwarderInternals._std;
const tier_consistency = __ForwarderInternals._tier_consistency;
const vkErrorInitializationFailed = __ForwarderInternals._vkErrorInitializationFailed;
const vkErrorOutOfHostMemory = __ForwarderInternals._vkErrorOutOfHostMemory;
const vulkanLoaderCandidates = __ForwarderInternals._vulkanLoaderCandidates;
const PipelineMarshalFailure = __ForwarderInternals._PipelineMarshalFailure;
const SpecializationScratch = __ForwarderInternals._SpecializationScratch;
const callNativeComputePipeline = Forwarder.callNativeComputePipeline;
const callNativeGraphicsPipeline = Forwarder.callNativeGraphicsPipeline;
const copyGuestStructs = Forwarder.copyGuestStructs;
const copyGuestValue = Forwarder.copyGuestValue;
const copyPipelineName = Forwarder.copyPipelineName;
const destroyNativeVulkanObjects = Forwarder.destroyNativeVulkanObjects;
const discoverGuestFrameSource = Forwarder.discoverGuestFrameSource;
const forgetGraphicsPipeline = Forwarder.forgetGraphicsPipeline;
const forgetRectangleExpandedPipeline = Forwarder.forgetRectangleExpandedPipeline;
const freeResourceSlotCount = Forwarder.freeResourceSlotCount;
const fsiRasterPipelinePass = Forwarder.fsiRasterPipelinePass;
const guestPointerValue = Forwarder.guestPointerValue;
const isGuestOutputPaintPipeline = Forwarder.isGuestOutputPaintPipeline;
const isRectangleStripPipeline = Forwarder.isRectangleStripPipeline;
const logVulkanHandleMapState = Forwarder.logVulkanHandleMapState;
const mapVulkanHandle = Forwarder.mapVulkanHandle;
const marshalGuestArray = Forwarder.marshalGuestArray;
const marshalSpecializationInfo = Forwarder.marshalSpecializationInfo;
const nativeVulkanLoaderPath = Forwarder.nativeVulkanLoaderPath;
const negotiateRosetteGpuBoundary = Forwarder.negotiateRosetteGpuBoundary;
const nextVulkanObject = Forwarder.nextVulkanObject;
const noteNativeVulkanLoaderResolved = Forwarder.noteNativeVulkanLoaderResolved;
const noteRealVulkanResult = Forwarder.noteRealVulkanResult;
const noteRectangleExpandedPipeline = Forwarder.noteRectangleExpandedPipeline;
const noteVulkanMapCapacityRefusal = Forwarder.noteVulkanMapCapacityRefusal;
const observeNativePresenterReport = Forwarder.observeNativePresenterReport;
const presentWindowFrame = Forwarder.presentWindowFrame;
const printPresentChain = Forwarder.printPresentChain;
const printVulkanRefusals = Forwarder.printVulkanRefusals;
const realDeviceLostResult = Forwarder.realDeviceLostResult;
const rectangleExpandedModule = Forwarder.rectangleExpandedModule;
const releaseVulkanHandle = Forwarder.releaseVulkanHandle;
const rememberGraphicsPipeline = Forwarder.rememberGraphicsPipeline;
const reportVulkanAbsentEntryPoints = Forwarder.reportVulkanAbsentEntryPoints;
const trackedImageCount = Forwarder.trackedImageCount;
const trackedResourceCount = Forwarder.trackedResourceCount;

pub fn createRealGraphicsPipeline(
    self: anytype,
    state: anytype,
    cache: u64,
    guest_address: u64,
    real_output: *u64,
    result_output: *i32,
    tessellation_pipeline: *bool,
    reason: *[]const u8,
) bool {
    tessellation_pipeline.* = false;
    self.marshalRealGraphicsPipeline(state, cache, guest_address, real_output, result_output, tessellation_pipeline) catch |failure| {
        if (tessellation_pipeline.*) self.vulkan_tessellation_pipeline_marshal_refusals +|= 1;
        reason.* = @errorName(failure);
        return false;
    };
    return true;
}

pub fn marshalRealGraphicsPipeline(
    self: anytype,
    state: anytype,
    cache: u64,
    guest_address: u64,
    real_output: *u64,
    result_output: *i32,
    tessellation_pipeline: *bool,
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
    var tessellation_stage_mask: u32 = 0;
    var fsi_identity: fsi_diagnostics.PipelineIdentity = .{};
    for (stages[0..@as(usize, @intCast(root.stage_count))]) |stage| {
        if (stage.stage == VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT) tessellation_stage_mask |= 1;
        if (stage.stage == VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT) tessellation_stage_mask |= 2;
        if (self.vulkan_fsi_tracker.findShader(stage.module)) |shader| {
            fsi_identity.include(stage.stage, shader);
        }
    }
    tessellation_pipeline.* = tessellation_stage_mask != 0;
    if (tessellation_pipeline.*) {
        self.vulkan_tessellation_pipeline_candidates +|= 1;
        self.vulkan_tessellation_stage_mask_or |= tessellation_stage_mask;
        if (root.tessellation_state == null) self.vulkan_tessellation_pipeline_missing_state +|= 1;
    }
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
    var tessellation_domain_origin: abi.PipelineTessellationDomainOriginStateCreateInfo = .{};
    if (root.tessellation_state) |pointer| {
        try marshalPipelineTessellationState(
            state,
            @intFromPtr(pointer),
            &tessellation,
            &tessellation_domain_origin,
        );
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

    if (self.fsi_raster.moltenvk and (self.fsi_raster.findPass(root.render_pass) != null or fsi_identity.uses_fsi)) {
        const samples = if (root.multisample_state) |pointer| pointer.rasterization_samples else 0;
        fsi_identity.rasterization_samples = samples;
        fsi_identity.raster_pass = try self.fsiRasterPipelinePass(root.render_pass, samples);
        root.render_pass = fsi_identity.raster_pass;
    }
    var real_pipeline: u64 = 0;
    const result = callNativeGraphicsPipeline(state, function, self.real_vulkan.device.?, real_cache, &root, &real_pipeline);
    if (result == abi.SUCCESS) {
        self.fsi_raster.pipelineCreated(real_pipeline, fsi_identity.raster_pass) catch {
            if (self.real_vulkan.fn_ptrs.destroy_pipeline) |destroy| destroy(self.real_vulkan.device, real_pipeline, null);
            self.fsi_raster.refusals +|= 1;
            return error.FsiRasterizationUnavailable;
        };
        // The adapted pass is correctness state; shader diagnostic IDs
        // may have been evicted before this pipeline was created.
        if (fsi_identity.raster_pass != 0 and self.fsi_raster.moltenvk and root.tessellation_state != null) {
            self.fsi_raster.isolatePipeline(real_pipeline) catch {
                _ = self.fsi_raster.pipelines.remove(real_pipeline);
                if (self.real_vulkan.fn_ptrs.destroy_pipeline) |destroy| destroy(self.real_vulkan.device, real_pipeline, null);
                return error.FsiRasterizationUnavailable;
            };
            machoCapturePrint("macho-processor: VULKAN FSI ISOLATION: pipeline=0x{x} shader_hash=0x{x} reason=tessellation_interlock; splittable recordings isolate each draw and do not coalesce its timing group; a single draw can still fail\n", .{ real_pipeline, fsi_identity.shader_hash });
        }
    }
    self.vulkan_fsi_tracker.notePipelineCreated(real_pipeline, fsi_identity, result == abi.SUCCESS);
    // Always retain every FSI identity in logs: sparse creation logging
    // omitted the recurrent failed-group candidate in the Oct 7 runs.
    if (fsi_identity.uses_fsi or self.fsi_raster.findPass(root.render_pass) != null) {
        const topology = if (root.input_assembly_state) |pointer| pointer.topology else std.math.maxInt(u32);
        const samples = if (root.multisample_state) |pointer| pointer.rasterization_samples else 0;
        machoCapturePrint(
            "macho-processor: Vulkan FSI PIPELINE: ordinal={d} result={d} real=0x{x} module_id={d} shader_hash=0x{x} pipeline_hash=0x{x} stage_flags=0x{x} fsi_modules={d} interlock_caps=0x{x} begin/end={d}/{d} stages={d} topology={d} samples={d} render_pass=0x{x} layout=0x{x} fragment_identity_known={}; ties Xenia's interlock SPIR-V to the exact native pipeline outcome and render-pass compatibility inputs\n",
            .{ self.vulkan_fsi_tracker.pipeline_candidates, result, real_pipeline, fsi_identity.module_id, fsi_identity.shader_hash, fsi_identity.combined_hash, fsi_identity.stage_flags_or, fsi_identity.shader_count, fsi_identity.capability_mask, fsi_identity.begin_ops, fsi_identity.end_ops, root.stage_count, topology, samples, root.render_pass, root.layout, fsi_identity.uses_fsi },
        );
    }
    var repair_pipeline: u64 = 0;
    const guest_output_candidate = result == abi.SUCCESS and self.isGuestOutputPaintPipeline(&root);
    if (guest_output_candidate) {
        self.graphics_topology_repair_candidates +|= 1;
        const original_topology = input_assembly.topology;
        input_assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
        var repair_result: i32 = abi.ERROR_INITIALIZATION_FAILED;
        repair_result = callNativeGraphicsPipeline(state, function, self.real_vulkan.device.?, real_cache, &root, &repair_pipeline);
        input_assembly.topology = original_topology;
        if (repair_result == abi.SUCCESS and repair_pipeline != 0) {
            self.graphics_topology_repair_pipeline_creations +|= 1;
            if (sparseVulkanSuccessLog(self.graphics_topology_repair_pipeline_creations)) {
                machoCapturePrint(
                    "macho-processor: Vulkan guest-output topology twin created: original=0x{x} repair=0x{x} layout=0x{x} candidate={d}\n",
                    .{ real_pipeline, repair_pipeline, root.layout, self.graphics_topology_repair_candidates },
                );
            }
        } else {
            self.graphics_topology_repair_create_failures +|= 1;
            if (self.graphics_topology_repair_create_failures <= 8) {
                machoCapturePrint(
                    "macho-processor: Vulkan guest-output topology twin unavailable: original=0x{x} result={d} repair=0x{x}; original pipeline remains active\n",
                    .{ real_pipeline, repair_result, repair_pipeline },
                );
            }
            repair_pipeline = 0;
        }
    }
    result_output.* = result;
    real_output.* = real_pipeline;
    // A pipeline whose vertex shader this bridge rewrote, drawn as a
    // strip with primitive restart, is Xenia's rectangle-list fallback.
    // Its draws get the tag; nothing else does.
    if (result == abi.SUCCESS and real_pipeline != 0 and isRectangleStripPipeline(&root)) {
        var marked = false;
        for (stages[0..@as(usize, @intCast(root.stage_count))]) |stage| {
            if (stage.stage != VK_SHADER_STAGE_VERTEX_BIT) continue;
            if (!self.rectangleExpandedModule(stage.module)) continue;
            self.noteRectangleExpandedPipeline(real_pipeline);
            marked = true;
            break;
        }
        // A pipeline with the rectangle fallback's topology whose vertex
        // shader was *not* rewritten cannot expand anything. If a title
        // still shows the diagonal seam while draws_tagged is large, this
        // is the counter that says its rectangles took this path instead.
        if (!marked) self.rect_expand_pipelines_unmarked +|= 1;
    }
    if (result == abi.SUCCESS) self.rememberGraphicsPipeline(real_pipeline, &root, repair_pipeline, guest_output_candidate, fsi_identity);
}

pub fn createRealComputePipeline(
    self: anytype,
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

pub fn marshalPipelineTessellationState(
    state: anytype,
    guest_address: u64,
    tessellation: *abi.PipelineTessellationStateCreateInfo,
    domain_origin: *abi.PipelineTessellationDomainOriginStateCreateInfo,
) PipelineMarshalFailure!void {
    if (!copyGuestValue(abi.PipelineTessellationStateCreateInfo, state, guest_address, tessellation)) return error.TessellationUnreadable;
    if (tessellation.s_type != abi.STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO) return error.TessellationStructureTypeInvalid;
    const domain_origin_address = if (tessellation.p_next) |pointer| @intFromPtr(pointer) else 0;
    if (domain_origin_address == 0) {
        tessellation.p_next = null;
        return;
    }
    if (!copyGuestValue(abi.PipelineTessellationDomainOriginStateCreateInfo, state, domain_origin_address, domain_origin)) {
        return error.TessellationChainUnreadable;
    }
    if (domain_origin.s_type != abi.STRUCTURE_TYPE_PIPELINE_TESSELLATION_DOMAIN_ORIGIN_STATE_CREATE_INFO or domain_origin.p_next != null) {
        return error.TessellationChainUnsupported;
    }
    if (domain_origin.domain_origin > 1) return error.TessellationDomainOriginInvalid;
    domain_origin.p_next = null;
    tessellation.p_next = domain_origin;
}

pub fn marshalRealComputePipeline(
    self: anytype,
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
    const result = callNativeComputePipeline(state, function, self.real_vulkan.device.?, real_cache, &root, &real_pipeline);
    result_output.* = result;
    real_output.* = real_pipeline;
    if (result == abi.SUCCESS and real_pipeline != 0) {
        if (self.native_texture_state) |native| {
            native.addPipeline(&self.real_vulkan, real_pipeline, root);
            if (native.terminal_result != abi.SUCCESS) {
                self.noteRealVulkanResult(native.terminal_result, "native Metal texture pipeline");
                result_output.* = native.terminal_result;
            }
        }
    }
}

pub fn rollbackCreatedVulkanPipelines(self: anytype, synthetic_pipelines: []const u64) void {
    const device = self.real_vulkan.device orelse return;
    for (synthetic_pipelines) |synthetic| {
        if (synthetic == 0) continue;
        if (self.real_vulkan.realPipeline(synthetic)) |real| {
            if (self.real_vulkan.fn_ptrs.destroy_pipeline) |destroy| destroy(device, real, null);
            self.forgetGraphicsPipeline(real);
            self.forgetRectangleExpandedPipeline(real);
            self.vulkan_real_objects_destroyed +|= 1;
        }
        _ = self.releaseVulkanHandle(&self.real_vulkan.pipeline_map, synthetic);
    }
}

pub fn createMultipleVulkanObjects(self: anytype, state: anytype, count: u64, output: u64, name: []const u8) u64 {
    if (count == 0) return 0;
    if (output == 0 or state.guestMemory(output, count * 8) == null) return vkErrorInitializationFailed();
    if (self.realDeviceLostResult()) |result| return result;
    if (self.real_vulkan.hasDevice() and (std.mem.eql(u8, name, "vkCreateGraphicsPipelines") or std.mem.eql(u8, name, "vkCreateComputePipelines"))) {
        const info_size: usize = if (std.mem.eql(u8, name, "vkCreateGraphicsPipelines")) @sizeOf(abi.GraphicsPipelineCreateInfo) else @sizeOf(abi.ComputePipelineCreateInfo);
        if (count > 64 or state.guestMemoryConst(guest_context.registers(state).rcx, count * info_size) == null) return vkErrorInitializationFailed();
        const available = HandleMap.freeSlots(&self.real_vulkan.pipeline_map);
        if (available < @as(usize, @intCast(count))) {
            self.noteVulkanMapCapacityRefusal(name, @intCast(count), available);
            return vkErrorOutOfHostMemory();
        }
        var created_synthetic: [64]u64 = [_]u64{0} ** 64;
        var created_count: usize = 0;
        for (0..@as(usize, @intCast(count))) |index| {
            const guest_info = guest_context.registers(state).rcx + @as(u64, @intCast(index)) * info_size;
            var real_pipeline: u64 = 0;
            var result: i32 = 0;
            var tessellation_pipeline = false;
            var reason: []const u8 = "unknown";
            const forwarded = if (std.mem.eql(u8, name, "vkCreateGraphicsPipelines"))
                self.createRealGraphicsPipeline(state, guest_context.registers(state).rsi, guest_info, &real_pipeline, &result, &tessellation_pipeline, &reason)
            else
                self.createRealComputePipeline(state, guest_context.registers(state).rsi, guest_info, &real_pipeline, &result, &reason);
            if (forwarded) {
                self.noteRealVulkanResult(result, name);
                if (tessellation_pipeline) {
                    if (result == abi.SUCCESS) {
                        self.vulkan_tessellation_pipeline_driver_successes +|= 1;
                    } else {
                        self.vulkan_tessellation_pipeline_driver_failures +|= 1;
                    }
                }
                if (result != abi.SUCCESS) {
                    if (real_pipeline != 0) {
                        if (self.real_vulkan.fn_ptrs.destroy_pipeline) |destroy| destroy(self.real_vulkan.device.?, real_pipeline, null);
                        self.vulkan_real_objects_destroyed +|= 1;
                    }
                    self.rollbackCreatedVulkanPipelines(created_synthetic[0..created_count]);
                    return @as(u32, @bitCast(result));
                }
                const synthetic = self.nextVulkanObject();
                if (!self.mapVulkanHandle(&self.real_vulkan.pipeline_map, synthetic, real_pipeline, name)) {
                    if (real_pipeline != 0) {
                        if (self.real_vulkan.fn_ptrs.destroy_pipeline) |destroy| destroy(self.real_vulkan.device.?, real_pipeline, null);
                        self.forgetGraphicsPipeline(real_pipeline);
                        self.forgetRectangleExpandedPipeline(real_pipeline);
                        self.vulkan_real_objects_destroyed +|= 1;
                    }
                    self.rollbackCreatedVulkanPipelines(created_synthetic[0..created_count]);
                    return vkErrorOutOfHostMemory();
                }
                created_synthetic[created_count] = synthetic;
                created_count += 1;
                state.write64(output + @as(u64, @intCast(index)) * 8, synthetic);
                registerOpaqueHandle(state, synthetic, name);
                self.vulkan_real_objects_created +|= 1;
                self.vulkan_tiers.note(.pipeline, .real);
            } else {
                // Once a real guest device exists, a synthetic pipeline is
                // not a safe fallback: subsequent vkCmdBindPipeline would
                // have no host object and the command stream would be
                // silently discarded. Refuse the create instead so the
                // guest sees the actual bridge limitation at this call.
                self.rollbackCreatedVulkanPipelines(created_synthetic[0..created_count]);
                machoCapturePrint(
                    "macho-processor: REAL {s}: could not marshal pipeline index={d} ({s}); refusing synthetic fallback\n",
                    .{ name, index, reason },
                );
                return vkErrorInitializationFailed();
            }
        }
        if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) {
            machoCapturePrint("macho-processor: REAL Vulkan pipeline sample: objects={d} name={s} batch_count={d}\n", .{ self.vulkan_real_objects_created, name, count });
        }
        return 0;
    }
    for (0..count) |index| {
        const handle = self.nextVulkanObject();
        state.write64(output + index * 8, handle);
        registerOpaqueHandle(state, handle, name);
    }
    self.vulkan_synthetic_object_batches +|= 1;
    if (sparseVulkanSuccessLog(self.vulkan_synthetic_object_batches)) {
        machoCapturePrint("macho-processor: Vulkan synthetic object batch sample: call={d} kind={s} count={d} output=0x{x}\n", .{ self.vulkan_synthetic_object_batches, name, count, output });
    }
    return 0;
}

pub fn openGuest(self: anytype, path: []const u8, mode: u64) u64 {
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

pub fn closeGuest(self: anytype, token: u64) c_int {
    for (&self.guest_libraries) |*entry| {
        if (entry.token != token) continue;
        if (self.native_vulkan_library_token == token) self.destroyNativeVulkanObjects();
        const result: c_int = if (entry.handle) |handle| dlclose(handle) else if (entry.virtual_vulkan) 0 else -1;
        entry.* = .{};
        for (&self.guest_symbols) |*symbol| {
            if (symbol.library_token == token) symbol.* = .{};
        }
        for (&self.guest_symbol_lookup_cache) |*cached| {
            if (cached.library_token == token) cached.* = .{};
        }
        if (result == 0) self.guest_close_count +|= 1;
        return result;
    }
    return -1;
}

pub fn forward(self: anytype, state: anytype, dylib: []const u8, symbol: []const u8) ?Outcome {
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
        const length: usize = @intCast(guest_context.registers(state).rdx);
        if (length != 0) {
            const destination = state.guestMemory(guest_context.registers(state).rdi, guest_context.registers(state).rdx) orelse {
                self.rejected_guest_memory += 1;
                return null;
            };
            const source = state.guestMemoryConst(guest_context.registers(state).rsi, guest_context.registers(state).rdx) orelse {
                self.rejected_guest_memory += 1;
                return null;
            };
            std.mem.copyForwards(u8, destination[0..length], source[0..length]);
        }
        self.forwarded += 1;
        return .{ .handled = guest_context.registers(state).rdi };
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

pub fn handleStubSignature(self: anytype, state: anytype, signature: Signature) ?Outcome {
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
            const text: []const u8 = if (@as(u32, @truncate(guest_context.registers(state).rdi)) == 0)
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
            const buffer = state.guestMemory(guest_context.registers(state).rdi, guest_context.registers(state).rsi) orelse return null;
            if (buffer.len > 0) buffer[0] = 0;
            break :blk .{ .handled = 0 };
        },
        .connect_three_args => .{ .handled = @bitCast(@as(i64, -1)) },
        .send_four_args => .{ .handled = 0 },
        else => null,
    };
}

pub fn virtualGuestSleep(self: anytype, state: anytype) ?Outcome {
    // The Mach-O interpreter multiplexes all guest workers on one host
    // thread. Host nanosleep would freeze memory initialization, the
    // scheduler, and its watchdog together.
    const guest_duration = state.guestMemoryConst(guest_context.registers(state).rdi, 8) orelse return null;
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
        const thread = if (comptime @hasField(State, "active_guest_thread")) guest_context.field(state, "active_guest_thread").* else 0;
        const step = if (comptime @hasField(State, "executed_steps")) state.executed_steps else 0;
        machoCapturePrint(
            "scheduler: virtual guest sleep #{d}: thread=0x{x} requested_ns={d} effective_ns={d} kind={s} repair={s} cumulative_ns={d} step={d} host_blocked=false\n",
            .{ self.virtual_sleep_calls, thread, nanoseconds, ns, @tagName(decision.kind), @tagName(decision.repair), self.virtual_sleep_nanoseconds, step },
        );
    }
    return .handled_void;
}

pub fn presentXeniaOutputFrame(
    self: anytype,
    pixels: []const u8,
    width: u32,
    height: u32,
    row_pitch_bytes: u64,
    orientation: rosette_gpu.frame_source.Orientation,
    guest_swap_observed: bool,
) rosette_gpu.FrameClassification {
    if (!self.native_presenter.stage.isReady()) return .rejected;
    const report = self.native_presenter.present(.{
        .cpu_image = .{
            .pixels = pixels,
            .width = width,
            .height = height,
            // The converted scratch is always BGRA8. When Vulkan never came
            // up there is no negotiated surface format to borrow, so state the
            // conversion's actual format instead of publishing zero and
            // making the independent Cocoa fallback reject valid pixels.
            .format = if (self.native_presenter.surface_format.format != 0)
                self.native_presenter.surface_format.format
            else
                44, // VK_FORMAT_B8G8R8A8_UNORM
            .row_pitch_bytes = row_pitch_bytes,
            .orientation = orientation,
            .fit = .letterbox,
            .producer = .xenia_host,
            .guest_swap_observed = guest_swap_observed,
        },
    });
    self.observeNativePresenterReport(report);
    return report.classification;
}

pub fn noteGuestFrontBuffer(
    self: anytype,
    source: u64,
    width: u32,
    height: u32,
    tiled: bool,
    endian: rosette_gpu.xenos_texture.Endian,
    format: rosette_gpu.xenos_texture.Format,
    harness_supplied: bool,
) void {
    const surface = rosette_gpu.XenosSurface{
        .width = width,
        .height = height,
        .format = format,
        .endian = endian,
        .tiled = tiled,
    };
    // Retain an unsupported format as evidence instead of dropping the
    // front-buffer offer.  A raw fetch value such as 26 is exactly the
    // information needed to add a converter; silently defaulting it to
    // RGBA8 makes a malformed image look like a GPU failure.
    if (width < 64 or height < 64 or width > 4096 or height > 4096) return;
    // A surface a source named always displaces one Rosette supplied. The
    // reverse would let the harness's own fallback hide the console's real
    // framebuffer the moment a swap finally names it.
    if (self.guest_frontbuffer_harness_supplied != harness_supplied and
        self.guest_frontbuffer_source != 0 and harness_supplied) return;
    self.guest_frontbuffer_source = source;
    self.guest_frontbuffer_width = width;
    self.guest_frontbuffer_height = height;
    self.guest_frontbuffer_tiled = tiled;
    self.guest_frontbuffer_endian = endian;
    self.guest_frontbuffer_format = format;
    self.guest_frontbuffer_harness_supplied = harness_supplied;
    if (!surface.format.supported()) {
        self.guest_frontbuffer_bytes = 0;
        self.guest_frontbuffer_last_failure = .unsupported_format;
        return;
    }
    self.guest_frontbuffer_bytes = surface.requiredBytes();
}

pub fn publishGuestFrontBuffer(self: anytype, state: anytype) bool {
    if (self.guest_frontbuffer_source == 0 or self.guest_frontbuffer_bytes == 0) return false;
    const surface = rosette_gpu.XenosSurface{
        .width = self.guest_frontbuffer_width,
        .height = self.guest_frontbuffer_height,
        .format = self.guest_frontbuffer_format,
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

    const content = rosette_gpu.frame_source.inspectContent(destination);
    if (!content.nonzero) {
        // Named precisely: the buffer exists, is mapped, converted cleanly,
        // and holds no picture. That is a statement about the emulator's
        // rendering, not about this path.
        self.frame_inbox.noteUnusable(.never_published);
        return false;
    }
    const publication = self.frame_inbox.publishIfChanged(.{
        .source_address = self.guest_frontbuffer_scratch,
        .source_length = needed,
        .width = surface.width,
        .height = surface.height,
        // `convertToBgra8` defines the bytes independently of Vulkan. If
        // the native presenter never initialized, no surface format was
        // negotiated; publish the conversion's actual format explicitly.
        .format = if (self.native_presenter.surface_format.format != 0)
            self.native_presenter.surface_format.format
        else
            44, // VK_FORMAT_B8G8R8A8_UNORM
        .row_pitch_bytes = @as(u64, surface.width) * 4,
        .orientation = .top_down,
        .fit = .letterbox,
        // A harness surface is Rosette's. Publishing it as `xenia_host`
        // would put Rosette's own fallback into the counter a reader
        // consults to find out whether the emulator produced a picture.
        .producer = if (self.guest_frontbuffer_harness_supplied) .diagnostic else .xenia_host,
        // Set by the swap observation, never by a frame having arrived.
        // The pending generation is what lets the PE/Xenia path publish
        // its console surface even when Xenia never reaches
        // RefreshGuestOutput.
        .guest_swap_observed = self.guest_frontbuffer_swap_pending,
    }, self.guest_frontbuffer_source, content.digest);
    if (publication.disposition == .rejected) return false;
    if (publication.disposition == .unchanged) return true;
    self.guest_frontbuffer_nonzero_frames +|= 1;
    const serial = publication.serial;
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

pub fn presentGuestFrontBuffer(
    self: anytype,
    state: anytype,
    source: u64,
    width: u32,
    height: u32,
    tiled: bool,
    endian: rosette_gpu.xenos_texture.Endian,
    format: rosette_gpu.xenos_texture.Format,
    guest_swap_observed: bool,
) bool {
    self.guest_frontbuffer_present_attempts +|= 1;
    if (guest_swap_observed) self.noteGuestSwapObserved();
    self.noteGuestFrontBuffer(source, width, height, tiled, endian, format, false);

    if (!self.native_presenter.stage.isReady()) {
        self.guest_frontbuffer_present_failures +|= 1;
        return false;
    }
    if (!self.publishGuestFrontBuffer(state)) {
        self.guest_frontbuffer_present_failures +|= 1;
        return false;
    }
    const descriptor = self.frame_inbox.acquire() orelse {
        self.guest_frontbuffer_present_failures +|= 1;
        return false;
    };
    if (descriptor.producer != .xenia_host or !descriptor.guest_swap_observed) {
        self.frame_inbox.release(false);
        self.guest_frontbuffer_present_failures +|= 1;
        return false;
    }
    const pixels = state.guestMemoryConst(descriptor.source_address, descriptor.source_length) orelse {
        self.frame_inbox.release(false);
        self.frame_inbox.noteUnusable(.source_unmapped);
        self.guest_frontbuffer_present_failures +|= 1;
        return false;
    };
    const report = self.native_presenter.present(.{ .cpu_image = .{
        .pixels = pixels,
        .width = descriptor.width,
        .height = descriptor.height,
        .format = if (self.native_presenter.surface_format.format != 0)
            self.native_presenter.surface_format.format
        else
            44,
        .row_pitch_bytes = descriptor.row_pitch_bytes,
        .orientation = descriptor.orientation,
        .fit = descriptor.fit,
        .producer = descriptor.producer,
        .guest_swap_observed = descriptor.guest_swap_observed,
    } });
    self.observeNativePresenterReport(report);
    const consumed = report.presented and report.source_copied;
    self.frame_inbox.release(consumed);
    if (!consumed) {
        self.guest_frontbuffer_present_failures +|= 1;
        return false;
    }

    self.guest_frontbuffer_presented_generation = self.guest_frontbuffer_swap_generation;
    self.guest_frontbuffer_swap_pending = false;
    self.guest_frontbuffer_present_successes +|= 1;
    const count = self.guest_frontbuffer_present_successes;
    if (count <= 4 or (count & (count - 1)) == 0) {
        machoCapturePrint(
            "macho-processor: PE64 GUEST FRONT BUFFER PRESENT: success={d} attempt={d} generation={d} extent={d}x{d} format={s}(raw={d}) native_present={} source_copied={} classification={s}; VdSwap-owned console pixels reached the drawable\n",
            .{
                count,
                self.guest_frontbuffer_present_attempts,
                self.guest_frontbuffer_swap_generation,
                descriptor.width,
                descriptor.height,
                self.guest_frontbuffer_format.label(),
                @intFromEnum(self.guest_frontbuffer_format),
                report.presented,
                report.source_copied,
                report.classification.label(),
            },
        );
    }
    return true;
}

pub fn noteGuestSwapObserved(self: anytype) void {
    self.guest_frontbuffer_swap_generation +|= 1;
    self.guest_frontbuffer_swap_pending = true;
    self.frame_provenance.noteGuestRingPacket();
    self.native_presenter.ledger.noteGuestRingPacket();
}

pub fn noteNativeWindowResize(self: anytype, width: u32, height: u32) void {
    if (self.native_presenter.stage.isReady()) self.native_presenter.noteResize(width, height);
}

pub fn nativePresenterStage(self: anytype) rosette_gpu.NativePresenterStage {
    return self.native_presenter.stage;
}

pub fn attemptScheduledRefresh(self: anytype, state: anytype) bool {
    if (!self.native_presenter.stage.isReady()) return false;
    self.scheduled_refresh_attempts +|= 1;
    const presented = self.presentWindowFrame(state, self.scheduled_refresh_attempts, 0, 0, 4);
    if (presented) self.scheduled_refresh_successes +|= 1;
    return presented;
}

pub fn refreshCocoaFallbackSource(self: anytype, state: anytype) void {
    if (self.native_presenter.stage.isReady()) return;
    self.discoverGuestFrameSource(state);
}

pub fn attemptCocoaFrameFallback(self: anytype, state: anytype) bool {
    if (self.native_presenter.stage.isReady()) return false;
    self.cocoa_fallback_attempts +|= 1;
    const descriptor = self.frame_inbox.acquire() orelse {
        self.cocoa_fallback_failures +|= 1;
        return false;
    };
    const pixels = state.guestMemoryConst(descriptor.source_address, descriptor.source_length) orelse {
        self.frame_inbox.release(false);
        self.frame_inbox.noteUnusable(.source_unmapped);
        self.cocoa_fallback_failures +|= 1;
        return false;
    };
    // The window decides whether these pixels may reach it. Every fact the
    // gate needs about the frame has just been established: the source is
    // mapped for its whole extent, the descriptor passed the inbox's own
    // validation, and a swap boundary either was or was not observed.
    // Presenting first and recording afterwards would make the ledger an
    // account of what already happened rather than the thing that decided.
    if (comptime @hasDecl(@TypeOf(state.*), "admitWindowPresentation")) {
        const outcome = state.admitWindowPresentation(
            if (descriptor.guest_swap_observed) .guest_title else .xenia_host,
            if (descriptor.guest_swap_observed) .guest_swap_present else .verified_present,
            .{
                .frame_verified = true,
                .frontbuffer_named = true,
                .swap_boundary_observed = descriptor.guest_swap_observed,
            },
            "cocoa-metal-guest-copy",
        );
        if (outcome.disposition == .fault) state.faultOnWindowAdmission(outcome);
        if (outcome.disposition != .admit) {
            // Unconsumed: a later checkpoint whose conditions do hold gets
            // to retry the same descriptor.
            self.frame_inbox.release(false);
            self.cocoa_fallback_failures +|= 1;
            return false;
        }
    }
    const presented = state.native_window.presentVerifiedFrame(
        descriptor.serial,
        pixels,
        descriptor.width,
        descriptor.height,
        descriptor.row_pitch_bytes,
        descriptor.format,
        @intFromEnum(descriptor.orientation),
        @intFromEnum(descriptor.fit),
        descriptor.guest_swap_observed,
    );
    self.frame_inbox.release(presented);
    if (!presented) {
        self.cocoa_fallback_failures +|= 1;
        return false;
    }
    self.cocoa_fallback_successes +|= 1;
    return true;
}

pub fn logScheduledRefresh(self: anytype) void {
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

pub fn nativePresenterFramesPresented(self: anytype) u64 {
    const ledger = &self.native_presenter.ledger;
    return ledger.diagnostic_frames_presented +|
        ledger.host_frames_presented +|
        ledger.guest_output_frames_presented;
}

pub fn guestVulkanPresentRequests(self: anytype) u64 {
    return self.frame_provenance.native_present_requests;
}

pub fn graphicsOwnershipSnapshot(self: anytype) GraphicsOwnershipSnapshot {
    const presenter = &self.native_presenter;
    const xenia = &self.real_vulkan;
    const latest = self.frame_inbox.latest();
    return .{
        .rosette_presenter_ready = presenter.stage.isReady(),
        .rosette_metal_layer = presenter.metal_layer,
        .rosette_instance = if (presenter.instance) |value| @intFromPtr(value) else 0,
        .rosette_surface = presenter.surface,
        .rosette_device = if (presenter.device) |value| @intFromPtr(value) else 0,
        .rosette_queue = if (presenter.graphics_queue) |value| @intFromPtr(value) else 0,
        .rosette_swapchain = presenter.swapchain,
        .rosette_generation = @as(u64, presenter.ring.generation) + 1,
        .rosette_diagnostic_frames = presenter.ledger.diagnostic_frames_presented,
        .rosette_host_frames = presenter.ledger.host_frames_presented,
        .rosette_guest_output_frames = presenter.ledger.guest_output_frames_presented,
        .rosette_surface_format = presenter.surface_format.format,
        .rosette_extent_width = presenter.extent.width,
        .rosette_extent_height = presenter.extent.height,
        .xenia_instance = if (xenia.instance) |value| @intFromPtr(value) else 0,
        .xenia_surface = xenia.surface,
        .xenia_device = if (xenia.device) |value| @intFromPtr(value) else 0,
        .xenia_queue = if (xenia.graphics_queue) |value| @intFromPtr(value) else 0,
        .xenia_swapchain = xenia.swapchain,
        .xenia_submissions = self.vulkan_real_queue_submits,
        .xenia_presents = self.vulkan_real_presents,
        .xenia_present_completions = self.vulkan_real_present_completions,
        .latest_frame = latest,
        .latest_frame_consumed = if (latest) |frame_value| self.frame_inbox.consumed_serial >= frame_value.serial else false,
    };
}

pub fn guestVulkanInstanceReady(self: anytype) bool {
    return self.real_vulkan.hasInstance();
}

pub fn guestVulkanDeviceReady(self: anytype) bool {
    return self.real_vulkan.deviceUsable();
}

pub fn guestVulkanDeviceLost(self: anytype) bool {
    return self.real_vulkan.device_lost;
}

pub fn guestVulkanCommandsForwarded(self: anytype) u64 {
    return self.vulkan_real_command_calls;
}

pub fn guestVulkanQueueSubmits(self: anytype) u64 {
    return self.vulkan_real_queue_submits;
}

pub fn guestVulkanPresents(self: anytype) u64 {
    return self.vulkan_real_presents;
}

pub fn guestVulkanPresentCompletions(self: anytype) u64 {
    return self.vulkan_real_present_completions;
}

pub fn guestVulkanObservedCommands(self: anytype) u64 {
    return self.vulkan_modeled_command_calls;
}

pub fn virtualSleepCallCount(self: anytype) u64 {
    return self.virtual_sleep_calls;
}

pub fn lastVirtualSleepDecision(self: anytype) guest_sleep.Decision {
    return self.last_virtual_sleep_decision;
}

pub fn logSummary(self: anytype) void {
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
    if (self.graphics_extent_contract_failures != 0) {
        machoCapturePrint(
            "macho-processor: GRAPHICS EXTENT CONTRACT: failed={} failures={d} required={d}x{d} observed={d}x{d}; extent admission is non-bypassable and a failed bridge/presenter handshake must terminate the Mach-O process\n",
            .{
                self.graphics_extent_contract_failed,
                self.graphics_extent_contract_failures,
                self.graphics_extent_requested_width,
                self.graphics_extent_requested_height,
                self.graphics_extent_observed_width,
                self.graphics_extent_observed_height,
            },
        );
    }
    self.printVulkanRefusals(true);
    self.reportVulkanAbsentEntryPoints();
    self.printPresentChain();
    if (self.vulkan_loader_lookup_unique != 0 or self.vulkan_loader_lookup_repeats != 0) {
        machoCapturePrint(
            "macho-processor: Vulkan loader lookup summary: unique={d} repeats_suppressed={d} cache_overflows={d}\n",
            .{ self.vulkan_loader_lookup_unique, self.vulkan_loader_lookup_repeats, self.vulkan_loader_lookup_cache_overflows },
        );
    }
    if (self.guest_symbol_lookup_cache_hits != 0 or self.guest_symbol_lookup_cache_misses != 0) {
        machoCapturePrint(
            "macho-processor: Vulkan guest-symbol lookup cache: hits={d} misses={d}; hits validate library, hash, length and exact symbol bytes before returning the cached thunk\n",
            .{ self.guest_symbol_lookup_cache_hits, self.guest_symbol_lookup_cache_misses },
        );
    }
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
            "macho-processor: Vulkan lifecycle: device={d} queue={d} metal_surface={d} swapchain={d} swapchain_images={d} acquired={d} submits={d} fence_only_submits={d} presents(calls/accepted/completed)={d}/{d}/{d} memory(alloc/maps/reuses/bindings)={d}/{d}/{d}/{d} object_success(publications/command_alloc_calls/descriptor_alloc_calls/synthetic_batches)={d}/{d}/{d}/{d} opaque={d} presenter(stage/attempts/failures/off_ui_calls)={s}/{d}/{d}/{d}\n",
            .{
                self.vulkan_logical_devices_created,
                self.vulkan_queues_acquired,
                self.vulkan_metal_surfaces_created,
                self.vulkan_swapchains_created,
                self.vulkan_swapchain_images_enumerated,
                self.vulkan_images_acquired,
                self.vulkan_queue_submits,
                self.vulkan_fence_only_queue_submits,
                self.vulkan_presents,
                self.vulkan_real_presents,
                self.vulkan_real_present_completions,
                self.vulkan_memory_allocations,
                self.vulkan_memory_maps,
                self.vulkan_memory_map_reuses,
                self.vulkan_memory_bindings,
                self.vulkan_guest_object_publications,
                self.vulkan_command_buffer_allocations,
                self.vulkan_descriptor_set_allocations,
                self.vulkan_synthetic_object_batches,
                self.guest_opaque_calls,
                @tagName(self.vulkan_presenter_stage),
                self.vulkan_presenter_bind_attempts,
                self.vulkan_presenter_bind_failures,
                self.vulkan_presenter_off_ui_calls,
            },
        );
        machoCapturePrint(
            "macho-processor: native Vulkan surface backing: loader(attempts/failures/successes)={d}/{d}/{d} selected_path={s} instance_attempts={d} surface_attempts={d} failures={d} instance=0x{x} host_surface=0x{x} library_token=0x{x}\n",
            .{ self.native_vulkan_loader_attempts, self.native_vulkan_loader_failures, self.native_vulkan_loader_successes, self.nativeVulkanLoaderPath(), self.native_vulkan_instance_attempts, self.native_vulkan_surface_attempts, self.native_vulkan_failures, if (self.native_vulkan_instance) |instance| @intFromPtr(instance) else 0, self.native_vulkan_surface, self.native_vulkan_library_token },
        );
        machoCapturePrint(
            "macho-processor: Vulkan forwarding contract: guest_objects=REAL_WHEN_DEVICE_READY fallback=MODELLED real_device={} device_lost={} real_objects(created/destroyed)={d}/{d} object_success(publications/command_alloc_calls/descriptor_alloc_calls/synthetic_batches)={d}/{d}/{d}/{d} commands(real/observed)={d}/{d} queue_submits(real/observed)={d}/{d} presents(real/observed/completed)={d}/{d}/{d} memory_bindings={d} fence_completions={d} rosette_presenter={s} capability_queries={d} device_void_calls={d}\n",
            .{
                self.real_vulkan.hasDevice(),
                self.real_vulkan.device_lost,
                self.vulkan_real_objects_created,
                self.vulkan_real_objects_destroyed,
                self.vulkan_guest_object_publications,
                self.vulkan_command_buffer_allocations,
                self.vulkan_descriptor_set_allocations,
                self.vulkan_synthetic_object_batches,
                self.vulkan_real_command_calls,
                self.vulkan_modeled_command_calls,
                self.vulkan_real_queue_submits,
                self.vulkan_queue_submits,
                self.vulkan_real_presents,
                self.vulkan_presents,
                self.vulkan_real_present_completions,
                self.vulkan_memory_bindings,
                self.vulkan_fence_completions,
                @tagName(self.native_presenter.stage),
                self.vulkan_surface_capability_queries,
                self.vulkan_device_void_calls,
            },
        );
        self.logVulkanHandleMapState();
        self.logGuestFrontBuffer();
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

pub fn guestFrontBufferAvailable(self: anytype) bool {
    return self.guest_frontbuffer_nonzero_frames != 0;
}

pub fn presenterFormatFeatures(self: anytype, format: u32) ?u32 {
    return self.native_presenter.formatFeatures(format);
}

pub fn presenterFormatProperties(self: anytype, format: u32) ?abi.FormatProperties {
    return self.native_presenter.formatProperties(format);
}

pub fn publishedFrameGenerations(self: anytype) u64 {
    return self.frame_inbox.published;
}

pub fn guestFrontBufferFormatRefused(self: anytype) bool {
    return self.guest_frontbuffer_conversion_failures != 0 and
        self.guest_frontbuffer_last_failure == .unsupported_format;
}

pub fn logVulkanTiers(self: anytype) void {
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
    // A wholly real stack has no seam, and the seam is the only thing the
    // per-facet list exists to locate. Nineteen lines saying `real` on
    // every checkpoint is the success case printing itself out; the header
    // above already carries `real=19 modelled=0`, which is the whole fact.
    // The list returns in full the instant one facet is served the other
    // way, which is exactly when a reader needs to know which one.
    if (ledger.whollyReal()) {
        machoCapturePrint(
            "  facet detail collapsed: all {d} facets served real, no facet served both ways. The per-facet list prints in full the moment any facet is served modelled or both ways\n",
            .{tier_consistency.facet_count},
        );
    } else {
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

pub fn logGuestFrontBuffer(self: anytype) void {
    machoCapturePrint(
        "macho-processor: PE64 GUEST FRONT BUFFER HANDOFF: swap_generation={d} presented_generation={d} pending={} present_attempts={d} present_successes={d} present_failures={d}\n",
        .{
            self.guest_frontbuffer_swap_generation,
            self.guest_frontbuffer_presented_generation,
            self.guest_frontbuffer_swap_pending,
            self.guest_frontbuffer_present_attempts,
            self.guest_frontbuffer_present_successes,
            self.guest_frontbuffer_present_failures,
        },
    );
    if (self.guest_frontbuffer_source == 0) {
        machoCapturePrint(
            "macho-processor: GUEST FRONT BUFFER: never offered. No swap packet has named a front buffer, so the console's framebuffer address is unknown and nothing but a diagnostic frame can reach the window\n",
            .{},
        );
        return;
    }
    machoCapturePrint(
        "macho-processor: GUEST FRONT BUFFER: source=0x{x} bytes={d} extent={d}x{d} format={s}(raw={d}) tiled={s} endian={s} conversions={d} failures={d} unique_nonzero_generations={d} retained_observations={d} last_failure={s}; {s}\n",
        .{
            self.guest_frontbuffer_source,
            self.guest_frontbuffer_bytes,
            self.guest_frontbuffer_width,
            self.guest_frontbuffer_height,
            self.guest_frontbuffer_format.label(),
            @intFromEnum(self.guest_frontbuffer_format),
            if (self.guest_frontbuffer_tiled) "YES" else "NO",
            self.guest_frontbuffer_endian.label(),
            self.guest_frontbuffer_conversions,
            self.guest_frontbuffer_conversion_failures,
            self.guest_frontbuffer_nonzero_frames,
            self.frame_inbox.unchanged_observations,
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

pub fn logGraphicsProvenance(self: anytype) void {
    const presenter = &self.native_presenter;
    const presenter_ledger = &presenter.ledger;
    {
        // The counters the audit requires never to be conflated. Each
        // answers a different question and none is a sum of the others.
        machoCapturePrint(
            "macho-processor: PRESENTATION PROVENANCE: guest_vulkan_calls_seen={d} native_driver_calls={d} native_submissions={d} native_present_requests={d} xenia_gpu_completions={d} presenter_incomplete={d} diagnostic_metal_frames={d} native_diagnostic_frames={d} xenia_host_frames={d} guest_output_frames={d} cocoa_verified_guest_frames={d} claims_demoted={d} guest_ring_packets={d}\n",
            .{
                self.frame_provenance.guest_vulkan_calls_seen,
                presenter_ledger.native_driver_calls,
                presenter_ledger.native_submissions,
                presenter_ledger.native_present_requests,
                self.vulkan_real_present_completions,
                presenter_ledger.frames_incomplete,
                self.frame_provenance.diagnostic_frames_presented,
                presenter_ledger.diagnostic_frames_presented,
                presenter_ledger.host_frames_presented,
                presenter_ledger.guest_output_frames_presented,
                self.cocoa_fallback_successes,
                presenter_ledger.claims_demoted + self.frame_provenance.claims_demoted,
                presenter_ledger.guest_ring_packets,
            },
        );
        // The Phase 5 handoff, reported as a chain so the first broken link
        // is visible rather than inferred from a frame count of zero.
        machoCapturePrint(
            "macho-processor: GUEST FRAME SOURCE: resources_live/free/capacity={d}/{d}/{d} images_tracked={d} image_bindings={d} resource_records(committed/released/high_water)={d}/{d}/{d} resource_overflow={d} scans={d} discoveries={d} content_observations={d} published_generations={d} unchanged_observations={d} content_changes={d} source_changes={d} consumed={d} dropped={d} cocoa_fallback(attempts/successes/failures)={d}/{d}/{d} blit_supported={s} filter={d} absence={s}\n",
            .{
                self.trackedResourceCount(),
                self.freeResourceSlotCount(),
                self.vulkan_resources.len,
                self.trackedImageCount(),
                self.vulkan_image_bindings,
                self.vulkan_resource_records_committed,
                self.vulkan_resource_records_released,
                self.vulkan_resource_high_water,
                self.vulkan_resource_overflow,
                self.frame_source_scans,
                self.frame_source_discoveries,
                self.frame_inbox.content_observations,
                self.frame_inbox.published,
                self.frame_inbox.unchanged_observations,
                self.frame_inbox.content_changes,
                self.frame_inbox.source_changes,
                self.frame_inbox.consumed,
                self.frame_inbox.dropped,
                self.cocoa_fallback_attempts,
                self.cocoa_fallback_successes,
                self.cocoa_fallback_failures,
                if (presenter.report.blit_supported) "YES" else "NO",
                presenter.report.blit_filter,
                self.frame_inbox.absence().label(),
            },
        );
        machoCapturePrint(
            "macho-processor: graphics visibility: guest_output={s} first_non_native_pixel_stage={s} next={s} display_note={s}\n",
            .{
                if (presenter_ledger.host_frames_presented != 0 or
                    presenter_ledger.guest_output_frames_presented != 0 or
                    self.cocoa_fallback_successes != 0) "YES" else "NO",
                if (self.forwarding_contract.firstNonNativePixelStage()) |stage| stage.label() else "none",
                presenter.blockingReason(),
                presenter_ledger.displayNote(),
            },
        );
    }
}

pub fn libraryHandle(self: anytype, dylib: []const u8) ?*anyopaque {
    for (self.libraries[0..self.library_count]) |loaded_library| {
        if (std.mem.eql(u8, loaded_library.path[0..loaded_library.path_length], dylib)) return loaded_library.handle;
    }
    if (self.library_count >= self.libraries.len) return null;

    var path_buffer: [1024]u8 = undefined;
    const path_z = nulTerminate(&path_buffer, dylib) orelse return null;
    const handle = dlopen(path_z, RTLD_LAZY | RTLD_LOCAL);
    if (dylib.len > self.libraries[self.library_count].path.len) return null;
    self.libraries[self.library_count] = .{ .path_length = @intCast(dylib.len), .handle = handle };
    @memcpy(self.libraries[self.library_count].path[0..dylib.len], dylib);
    self.library_count += 1;
    return handle;
}

pub fn guestLibraryEntry(self: anytype, token: u64) ?*GuestLibrary {
    for (&self.guest_libraries) |*entry| {
        if (entry.token == token) return entry;
    }
    return null;
}

pub fn guestLibrary(self: anytype, token: u64) ?*anyopaque {
    const entry = self.guestLibraryEntry(token) orelse return null;
    return entry.handle;
}

pub fn materializeNativeVulkanLibrary(self: anytype, token: u64) ?*anyopaque {
    const entry = self.guestLibraryEntry(token) orelse return null;
    if (entry.handle) |handle| return handle;
    if (!entry.virtual_vulkan or entry.path_length == 0) return null;
    const requested_path = entry.path[0..entry.path_length];
    var candidates = vulkanLoaderCandidates(requested_path);
    for (candidates.paths[0..candidates.count]) |path| {
        var path_buffer: [1024]u8 = undefined;
        const path_z = nulTerminate(&path_buffer, path) orelse continue;
        self.native_vulkan_loader_attempts +|= 1;
        machoCapturePrint(
            "macho-processor: native Vulkan loader begin: attempt={d} requested={s} path={s}; entering host dlopen/dyld initializers\n",
            .{ self.native_vulkan_loader_attempts, requested_path, path },
        );
        const handle = dlopen(path_z, RTLD_LAZY | RTLD_LOCAL) orelse {
            self.native_vulkan_loader_failures +|= 1;
            machoCapturePrint(
                "macho-processor: native Vulkan loader unavailable: attempt={d} requested={s} path={s} dlerror={s}\n",
                .{ self.native_vulkan_loader_attempts, requested_path, path, lastDlError() },
            );
            continue;
        };
        if (dlsym(handle, "vkGetInstanceProcAddr") == null) {
            self.native_vulkan_loader_failures +|= 1;
            _ = dlclose(handle);
            machoCapturePrint(
                "macho-processor: native Vulkan loader missing vkGetInstanceProcAddr: attempt={d} requested={s} path={s} dlerror={s}\n",
                .{ self.native_vulkan_loader_attempts, requested_path, path, lastDlError() },
            );
            continue;
        }
        entry.handle = handle;
        self.noteNativeVulkanLoaderResolved(path);
        machoCapturePrint("macho-processor: BOOTUP MILESTONE: native Vulkan library loaded via host dlopen — requested={s} path={s} handle=0x{x}\n", .{ requested_path, path, @intFromPtr(handle) });
        machoCapturePrint(
            "macho-processor: native Vulkan loader ready: attempt={d} requested={s} path={s} host_handle=0x{x}\n",
            .{ self.native_vulkan_loader_attempts, requested_path, path, @intFromPtr(handle) },
        );
        return handle;
    }
    machoCapturePrint(
        "macho-processor: native Vulkan loader exhausted candidates: requested={s} candidates={d} attempts={d} failures={d}\n",
        .{ requested_path, candidates.count, self.native_vulkan_loader_attempts, self.native_vulkan_loader_failures },
    );
    return null;
}

pub fn invoke(self: anytype, state: anytype, signature: Signature, address: *anyopaque) ?Outcome {
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
            const bytes = state.guestMemoryConst(guest_context.registers(state).rdi, guest_context.registers(state).rsi) orelse return null;
            const function: *const fn ([*]const u8, usize) callconv(.c) usize = @ptrCast(@alignCast(address));
            break :blk .{ .handled = function(bytes.ptr, bytes.len) };
        },
        .two_buffers_length_i32 => blk: {
            const lhs = state.guestMemoryConst(guest_context.registers(state).rdi, guest_context.registers(state).rdx) orelse return null;
            const rhs = state.guestMemoryConst(guest_context.registers(state).rsi, guest_context.registers(state).rdx) orelse return null;
            const function: *const fn ([*]const u8, [*]const u8, usize) callconv(.c) c_int = @ptrCast(@alignCast(address));
            break :blk .{ .handled = @bitCast(@as(i64, function(lhs.ptr, rhs.ptr, lhs.len))) };
        },
        .buffer_byte_length_pointer => blk: {
            const bytes = state.guestMemoryConst(guest_context.registers(state).rdi, guest_context.registers(state).rdx) orelse return null;
            const function: *const fn ([*]const u8, c_int, usize) callconv(.c) ?*const u8 = @ptrCast(@alignCast(address));
            const found = function(bytes.ptr, @intCast(guest_context.registers(state).rsi & 0xFF), bytes.len) orelse break :blk .{ .handled = 0 };
            const offset = @intFromPtr(found) - @intFromPtr(bytes.ptr);
            if (offset >= bytes.len) return null;
            break :blk .{ .handled = guest_context.registers(state).rdi + offset };
        },
        .guest_memory_copy => blk: {
            const length: usize = @intCast(guest_context.registers(state).rdx);
            if (length != 0) {
                const destination = state.guestMemory(guest_context.registers(state).rdi, guest_context.registers(state).rdx) orelse return null;
                const source = state.guestMemoryConst(guest_context.registers(state).rsi, guest_context.registers(state).rdx) orelse return null;
                std.mem.copyForwards(u8, destination[0..length], source[0..length]);
            }
            break :blk .{ .handled = guest_context.registers(state).rdi };
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
            const sentry_bytes = state.guestMemory(guest_context.registers(state).rdi, 16) orelse return null;
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
            const key = state.guestMemoryConst(guest_context.registers(state).rcx, 16) orelse return null;
            const iv = state.guestMemoryConst(guest_context.registers(state).r9, 16) orelse return null;
            const data_in_addr = state.read64(guest_context.registers(state).rsp + 8);
            const data_in_length = state.read64(guest_context.registers(state).rsp + 16);
            const data_out_addr = state.read64(guest_context.registers(state).rsp + 24);
            const data_out_avail = state.read64(guest_context.registers(state).rsp + 32);
            const data_out_moved_addr = state.read64(guest_context.registers(state).rsp + 40);
            const data_in = state.guestMemoryConst(data_in_addr, data_in_length) orelse return null;
            const data_out = state.guestMemory(data_out_addr, data_out_avail) orelse return null;
            const CCCryptFn = *const fn (c_uint, c_uint, c_uint, *const anyopaque, usize, *const anyopaque, *const anyopaque, usize, *anyopaque, usize, *usize) callconv(.c) c_int;
            const function: CCCryptFn = @ptrCast(@alignCast(address));
            var moved: usize = 0;
            const result = function(
                @as(c_uint, @truncate(guest_context.registers(state).rdi)),
                @as(c_uint, @truncate(guest_context.registers(state).rsi)),
                @as(c_uint, @truncate(guest_context.registers(state).rdx)),
                @ptrCast(key.ptr),
                @as(usize, @intCast(guest_context.registers(state).r8)),
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
            const tm = state.guestMemoryConst(guest_context.registers(state).rdi, 64) orelse {
                const fallback = state.guestMemory(guest_context.registers(state).rsp - 64, 4) orelse break :blk .{ .handled = 0 };
                @memcpy(fallback, "???\x00");
                break :blk .{ .handled = guest_context.registers(state).rsp - 64 };
            };
            const function: *const fn ([*]const u8) callconv(.c) [*:0]const u8 = @ptrCast(@alignCast(address));
            const result = function(tm.ptr);
            const result_bytes = std.mem.sliceTo(result, 0);
            const buf_len = @min(result_bytes.len + 1, 256);
            const guest_buf = state.guestMemory(guest_context.registers(state).rsp - 64, buf_len) orelse break :blk .{ .handled = 0 };
            @memcpy(guest_buf[0..result_bytes.len], result_bytes);
            if (result_bytes.len < buf_len) guest_buf[result_bytes.len] = 0;
            break :blk .{ .handled = guest_context.registers(state).rsp - 64 };
        },
    };
}
