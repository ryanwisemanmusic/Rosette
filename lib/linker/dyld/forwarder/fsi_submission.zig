// Split implementation for Forwarder; wrappers keep the public state API stable.
const process = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = process.__ForwarderInternals;
const Forwarder = process.Forwarder;
const HandleMap = __ForwarderInternals._HandleMap;
const MAX_SURFACE_ENUMERATION = __ForwarderInternals._MAX_SURFACE_ENUMERATION;
const MAX_VULKAN_MEMORY_ALLOCATIONS = __ForwarderInternals._MAX_VULKAN_MEMORY_ALLOCATIONS;
const MODELLED_MEMORY_TYPE_COUNT = __ForwarderInternals._MODELLED_MEMORY_TYPE_COUNT;
const VK_BUFFER_CREATE_INFO_SIZE = __ForwarderInternals._VK_BUFFER_CREATE_INFO_SIZE;
const VK_BUFFER_CREATE_INFO_SIZE_OFFSET = __ForwarderInternals._VK_BUFFER_CREATE_INFO_SIZE_OFFSET;
const VK_BUFFER_CREATE_INFO_USAGE_OFFSET = __ForwarderInternals._VK_BUFFER_CREATE_INFO_USAGE_OFFSET;
const VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_ARRAY_LAYERS_OFFSET;
const VK_IMAGE_CREATE_INFO_EXTENT_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_EXTENT_OFFSET;
const VK_IMAGE_CREATE_INFO_FORMAT_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_FORMAT_OFFSET;
const VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_MIP_LEVELS_OFFSET;
const VK_IMAGE_CREATE_INFO_SIZE = __ForwarderInternals._VK_IMAGE_CREATE_INFO_SIZE;
const VK_IMAGE_CREATE_INFO_TILING_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_TILING_OFFSET;
const VK_IMAGE_CREATE_INFO_USAGE_OFFSET = __ForwarderInternals._VK_IMAGE_CREATE_INFO_USAGE_OFFSET;
const VK_SYNTHETIC_DEVICE = __ForwarderInternals._VK_SYNTHETIC_DEVICE;
const VK_SYNTHETIC_QUEUE = __ForwarderInternals._VK_SYNTHETIC_QUEUE;
const VulkanCreateLedgerEntry = __ForwarderInternals._VulkanCreateLedgerEntry;
const VulkanResource = __ForwarderInternals._VulkanResource;
const VulkanResourceKind = __ForwarderInternals._VulkanResourceKind;
const abi = __ForwarderInternals._abi;
const createHandle = __ForwarderInternals._createHandle;
const fsi_diagnostics = __ForwarderInternals._fsi_diagnostics;
const gpu_vulkan = __ForwarderInternals._gpu_vulkan;
const guest_context = __ForwarderInternals._guest_context;
const imageReadbackAugmentable = __ForwarderInternals._imageReadbackAugmentable;
const machoCapturePrint = __ForwarderInternals._machoCapturePrint;
const marshal = __ForwarderInternals._marshal;
const native_texture = __ForwarderInternals._native_texture;
const rangeContains = __ForwarderInternals._rangeContains;
const rectExpansionBuiltinIndexBuffer = __ForwarderInternals._rectExpansionBuiltinIndexBuffer;
const registerOpaqueHandle = __ForwarderInternals._registerOpaqueHandle;
const rosette_gpu = __ForwarderInternals._rosette_gpu;
const sparseVulkanSuccessLog = __ForwarderInternals._sparseVulkanSuccessLog;
const std = __ForwarderInternals._std;
const vkErrorInitializationFailed = __ForwarderInternals._vkErrorInitializationFailed;
const vkErrorOutOfHostMemory = __ForwarderInternals._vkErrorOutOfHostMemory;
const availableVulkanMapSlots = Forwarder.availableVulkanMapSlots;
const copyGuestStructs = Forwarder.copyGuestStructs;
const copyGuestValue = Forwarder.copyGuestValue;
const correctHdrResolve = Forwarder.correctHdrResolve;
const drainAsyncVulkanCommands = Forwarder.drainAsyncVulkanCommands;
const expandRectangleListShader = Forwarder.expandRectangleListShader;
const findVulkanMemoryRecord = Forwarder.findVulkanMemoryRecord;
const fsiBeginRecording = Forwarder.fsiBeginRecording;
const fsiCommandTarget = Forwarder.fsiCommandTarget;
const fsiForgetRecording = Forwarder.fsiForgetRecording;
const fsiNoteFramebufferCreated = Forwarder.fsiNoteFramebufferCreated;
const fsiNoteRenderPassCreated = Forwarder.fsiNoteRenderPassCreated;
const fsiRecording = Forwarder.fsiRecording;
const fsiResetCommandPool = Forwarder.fsiResetCommandPool;
const fsiSaveShaderEvidence = Forwarder.fsiSaveShaderEvidence;
const fsiUpdateShaderBoundsBudget = Forwarder.fsiUpdateShaderBoundsBudget;
const hardenShaderModule = Forwarder.hardenShaderModule;
const logVulkanHandleMapState = Forwarder.logVulkanHandleMapState;
const mapVulkanHandle = Forwarder.mapVulkanHandle;
const nextVulkanObject = Forwarder.nextVulkanObject;
const normalizeFsiPixelFrequency = Forwarder.normalizeFsiPixelFrequency;
const noteRealVulkanResult = Forwarder.noteRealVulkanResult;
const noteRectangleExpandedModule = Forwarder.noteRectangleExpandedModule;
const noteVulkanMapCapacityRefusal = Forwarder.noteVulkanMapCapacityRefusal;
const observeFsiDescriptorSetLayout = Forwarder.observeFsiDescriptorSetLayout;
const printDeviceLossFsiSubmission = Forwarder.printDeviceLossFsiSubmission;
const readPipelineCacheFile = Forwarder.readPipelineCacheFile;
const realDeviceLostResult = Forwarder.realDeviceLostResult;
const reclaimDescriptorSetsForPool = Forwarder.reclaimDescriptorSetsForPool;
const releaseVulkanHandle = Forwarder.releaseVulkanHandle;
const rememberPipelineLayout = Forwarder.rememberPipelineLayout;
const resetCommandTargets = Forwarder.resetCommandTargets;
const trackFramebuffer = Forwarder.trackFramebuffer;
const trackImageView = Forwarder.trackImageView;
const trackRenderPass = Forwarder.trackRenderPass;

pub fn createLedgerEntry(self: anytype, name: []const u8) ?*VulkanCreateLedgerEntry {
    for (self.vulkan_create_ledger[0..self.vulkan_create_ledger_count]) |*entry| {
        if (std.mem.eql(u8, entry.nameText(), name)) return entry;
    }
    if (self.vulkan_create_ledger_count >= self.vulkan_create_ledger.len) {
        self.vulkan_create_ledger_overflow +|= 1;
        return null;
    }
    var entry = &self.vulkan_create_ledger[self.vulkan_create_ledger_count];
    entry.* = .{};
    const copied = @min(name.len, entry.name.len);
    @memcpy(entry.name[0..copied], name[0..copied]);
    entry.name_len = @intCast(copied);
    self.vulkan_create_ledger_count += 1;
    return entry;
}

pub fn noteCreateAttempt(self: anytype, name: []const u8) void {
    if (self.createLedgerEntry(name)) |entry| entry.attempts +|= 1;
}

pub fn noteCreatePublished(self: anytype, name: []const u8) void {
    if (self.createLedgerEntry(name)) |entry| entry.published +|= 1;
}

pub fn noteCreateRefusedBeforeDriver(self: anytype, name: []const u8) void {
    if (self.createLedgerEntry(name)) |entry| entry.refused_before_driver +|= 1;
}

pub fn noteCreateDriverFailure(self: anytype, name: []const u8, result: i32) void {
    if (self.createLedgerEntry(name)) |entry| {
        entry.driver_failures +|= 1;
        entry.last_result = result;
    }
}

pub fn vulkanCreateLedgerHasAnomaly(self: anytype) bool {
    for (self.vulkan_create_ledger[0..self.vulkan_create_ledger_count]) |entry| {
        if (entry.refused_before_driver != 0 or entry.driver_failures != 0 or entry.published < entry.attempts) return true;
    }
    return self.vulkan_create_ledger_overflow != 0;
}

pub fn dumpVulkanCreateLedger(self: anytype) void {
    machoCapturePrint(
        "macho-processor:   create_ledger: entry_points={d} overflow={d} (attempts / published / refused-before-driver / driver-failures)\n",
        .{ self.vulkan_create_ledger_count, self.vulkan_create_ledger_overflow },
    );
    machoCapturePrint(
        "macho-processor:   marshal_scratch: capacity={d} used={d} spill_reserves={d} peak_bytes={d} spill_failures={d} refusals={d}\n",
        .{ self.vulkan_scratch.capacity(), self.vulkan_scratch.used, self.vulkan_marshal_spill_reserves, self.vulkan_marshal_spill_peak_bytes, self.vulkan_marshal_spill_failures, self.vulkan_marshal_refusals },
    );
    machoCapturePrint(
        "macho-processor:   tessellation_pipeline: candidates={d} native_success={d} native_failure={d} bridge_refusal={d} missing_tessellation_state={d} stage_mask_or=0x{x}; mask bit 0=tessellation_control, bit 1=tessellation_evaluation; no candidates means the guest shader/pipeline generator did not submit a tessellation pipeline to Rosetta\n",
        .{ self.vulkan_tessellation_pipeline_candidates, self.vulkan_tessellation_pipeline_driver_successes, self.vulkan_tessellation_pipeline_driver_failures, self.vulkan_tessellation_pipeline_marshal_refusals, self.vulkan_tessellation_pipeline_missing_state, self.vulkan_tessellation_stage_mask_or },
    );
    machoCapturePrint(
        "macho-processor:   tessellation_shader_modules: control(candidate/native_success/native_failure)={d}/{d}/{d} evaluation={d}/{d}/{d} spirv_unreadable={d}; candidates come from SPIR-V OpEntryPoint before native creation and diagnose the earlier module-creation warning\n",
        .{ self.vulkan_tess_control_shader_modules, self.vulkan_tess_control_shader_modules_native_success, self.vulkan_tess_control_shader_modules_native_failure, self.vulkan_tess_eval_shader_modules, self.vulkan_tess_eval_shader_modules_native_success, self.vulkan_tess_eval_shader_modules_native_failure, self.vulkan_shader_module_spirv_unreadable },
    );
    machoCapturePrint(
        "macho-processor:   fsi_shader_modules: candidates/native_success/native_failure={d}/{d}/{d} capability_mask=0x{x} begin_ops/end_ops={d}/{d}; a nonzero SPIR-V interlock module proves Xenia generated an FSI shader, while zero means device extension negotiation alone did not select the FSI rendering path\n",
        .{ self.vulkan_fsi_shader_modules, self.vulkan_fsi_shader_modules_native_success, self.vulkan_fsi_shader_modules_native_failure, self.vulkan_fsi_spirv_capability_mask, self.vulkan_fsi_spirv_begin_ops, self.vulkan_fsi_spirv_end_ops },
    );
    machoCapturePrint(
        "macho-processor:   fsi_render_target_path: matching_edram_layouts={d} shared_memory_binding_count={s}:{d} host_maxPerStageDescriptorStorageBuffers={d} would_fallback_at_limit={s} count_matches_host_range={s}; the exact three-binding Xenia EDRAM/ZPD layout is emitted only after FSI path selection, while zero means Xenia stayed on host render targets or failed earlier\n",
        .{
            self.vulkan_fsi_descriptor_layouts,
            if (self.vulkan_fsi_shared_memory_binding_count_known) "observed" else "unknown",
            self.vulkan_fsi_shared_memory_binding_count,
            self.vulkan_fsi_host_storage_buffer_limit,
            if (!self.vulkan_fsi_host_storage_buffer_limit_known) "unknown" else if (self.vulkan_fsi_binding_limit_would_fallback) "yes" else "no",
            if (!self.vulkan_fsi_binding_count_matches_host_range_known) "unknown" else if (self.vulkan_fsi_binding_count_matches_host_range) "yes" else "no",
        },
    );
    const fsi = &self.vulkan_fsi_tracker;
    machoCapturePrint(
        "macho-processor:   fsi_flow: shaders(live/overflow/issued)={d}/{d}/{d} pipelines(candidate/native_success/native_failure/live/overflow)={d}/{d}/{d}/{d}/{d} binds={d} recorded_draws={d} accepted_command_buffers/draws={d}/{d} descriptor_updates={d} command_state_collisions={d}; this links shader identity through pipeline, target, draw and accepted queue submission without changing guest work\n",
        .{ fsi.shader_count, fsi.shader_identity_overflow, fsi.shader_ids_issued, fsi.pipeline_candidates, fsi.pipeline_native_successes, fsi.pipeline_native_failures, fsi.pipeline_count, fsi.pipeline_identity_overflow, fsi.pipeline_binds, fsi.draws, fsi.submitted_command_buffers, fsi.submitted_draws, fsi.descriptor_updates, fsi.command_state_collisions },
    );
    machoCapturePrint(
        "macho-processor:   fsi_target_routing: target_updates_before_fsi_bind={d} propagated_on_bind={d} dynamic_resolved={d} dynamic_unresolved={d} secondary_inherited={d} secondary_unresolved={d}; source identifies the forwarder's attachment provenance, not a framebuffer rewrite\n",
        .{ fsi.target_updates_before_fsi_pipeline, fsi.target_propagations_on_bind, fsi.dynamic_targets_resolved, fsi.dynamic_targets_unresolved, fsi.secondary_targets_inherited, fsi.secondary_targets_unresolved },
    );
    if (fsi.pipeline_candidates != 0) {
        machoCapturePrint(
            "macho-processor:   fsi_last_pipeline: native_success={} real=0x{x} module_id={d} shader_hash=0x{x} pipeline_hash=0x{x} stage_flags=0x{x} modules={d} capabilities=0x{x} begin/end={d}/{d}\n",
            .{ fsi.last_pipeline_native_success, fsi.last_pipeline_real, fsi.last_pipeline.module_id, fsi.last_pipeline.shader_hash, fsi.last_pipeline.combined_hash, fsi.last_pipeline.stage_flags_or, fsi.last_pipeline.shader_count, fsi.last_pipeline.capability_mask, fsi.last_pipeline.begin_ops, fsi.last_pipeline.end_ops },
        );
    }
    if (fsi.draws != 0) {
        const draw = fsi.last_draw;
        machoCapturePrint(
            "macho-processor:   fsi_last_draw: ordinal={d} kind={s} command_buffer=0x{x} pipeline=0x{x} shader_hash=0x{x} pipeline_hash=0x{x} target_image=0x{x} target_source={s}\n",
            .{ draw.draw_ordinal, @tagName(draw.kind), draw.command_buffer, draw.pipeline_real, draw.shader_hash, draw.pipeline_hash, draw.target_image, @tagName(draw.target_source) },
        );
    }
    if (fsi.submitted_command_buffers != 0) {
        const submitted = fsi.last_submission;
        machoCapturePrint(
            "macho-processor:   fsi_last_submit: queue_submit={d} batch={d} command_buffer=0x{x} fsi_draws={d} draw_ordinal={d} kind={s} target_image=0x{x} target_source={s}\n",
            .{ submitted.queue_submit_ordinal, submitted.batch_index, submitted.draw.command_buffer, submitted.fsi_draws_in_command_buffer, submitted.draw.draw_ordinal, @tagName(submitted.draw.kind), submitted.draw.target_image, @tagName(submitted.draw.target_source) },
        );
    }
    if (fsi.descriptor_updates != 0) {
        const update = fsi.last_descriptor_update;
        machoCapturePrint(
            "macho-processor:   fsi_last_descriptors: call={d} set(guest/native)=0x{x}/0x{x} bindings={d}/3 mask=0x{x}\n",
            .{ update.update_call, update.guest_set, update.native_set, update.binding_count, update.binding_mask },
        );
        for (update.bindings, 0..) |binding, index| {
            machoCapturePrint(
                "macho-processor:     fsi_descriptor_binding: slot={d} present={} binding={d} descriptors={d} buffer(guest/native)=0x{x}/0x{x} offset(guest/native)={d}/{d} range(guest/native)={d}/{d} zpd_repaired={}\n",
                .{ index, update.binding_mask & (@as(u8, 1) << @intCast(index)) != 0, binding.binding, binding.descriptor_count, binding.guest_buffer, binding.native_buffer, binding.guest_offset, binding.offset, binding.guest_range, binding.range, binding.repaired },
            );
        }
    }
    for (self.vulkan_create_ledger[0..self.vulkan_create_ledger_count]) |entry| {
        const lost = entry.attempts -| entry.published;
        machoCapturePrint(
            "macho-processor:     {s}: {d} / {d} / {d} / {d} last_result={d}{s}\n",
            .{
                entry.nameText(),
                entry.attempts,
                entry.published,
                entry.refused_before_driver,
                entry.driver_failures,
                entry.last_result,
                if (lost != 0) "  <- the guest read an unwritten handle this many times" else "",
            },
        );
    }
}

pub fn createVulkanObject(self: anytype, state: anytype, create_info: u64, output: u64, name: []const u8) u64 {
    self.noteCreateAttempt(name);
    if (output == 0 or state.guestMemory(output, 8) == null) {
        // Previously the only silent refusal on this path. A guest that
        // reads back an untouched handle sees VK_NULL_HANDLE and reports
        // "failed to create", while every Rosette counter says the run had
        // no Vulkan failures at all.
        self.noteCreateRefusedBeforeDriver(name);
        machoCapturePrint(
            "macho-processor: REAL {s} refused: output pointer 0x{x} is not guest memory; no object was created and the guest will read an unwritten handle\n",
            .{ name, output },
        );
        return vkErrorInitializationFailed();
    }
    if (self.realDeviceLostResult()) |result| {
        self.noteCreateRefusedBeforeDriver(name);
        return result;
    }
    // Images and buffers need a Rosette resource record for later memory
    // requirements and binding. If the bounded table is full, creating a
    // native object and returning a synthetic handle would create a
    // permanently untranslatable resource. Refuse before touching the
    // driver instead of entering that split-brain state.
    if (self.real_vulkan.hasDevice() and
        (std.mem.eql(u8, name, "vkCreateImage") or std.mem.eql(u8, name, "vkCreateBuffer")) and
        !self.resourceSlotAvailable())
    {
        self.vulkan_resource_overflow +|= 1;
        self.noteCreateRefusedBeforeDriver(name);
        // Keep the complete count in the ledger, but do not turn a
        // repeated guest create loop into a second performance problem by
        // printing the same line for every failed attempt.
        if (sparseVulkanSuccessLog(self.vulkan_resource_overflow)) {
            const live = self.trackedResourceCount();
            machoCapturePrint(
                "macho-processor: REAL {s} refused: Vulkan resource provenance table exhausted; live={d} free={d} capacity={d} overflow={d}; no synthetic handle was issued\n",
                .{ name, live, self.vulkan_resources.len - live, self.vulkan_resources.len, self.vulkan_resource_overflow },
            );
        }
        return vkErrorOutOfHostMemory();
    }
    if (self.real_vulkan.hasDevice()) {
        if (self.availableVulkanMapSlots(name)) |available| {
            if (available == 0) {
                self.noteVulkanMapCapacityRefusal(name, 1, available);
                self.noteCreateRefusedBeforeDriver(name);
                return vkErrorOutOfHostMemory();
            }
        }
    }
    const handle = self.nextVulkanObject();
    // Phase 1: create real Vulkan objects when the device is available.
    if (self.real_vulkan.hasDevice()) {
        self.real_create_result = abi.SUCCESS;
        self.createRealVulkanObject(state, handle, create_info, name) catch {
            const failure = if (self.real_create_result != abi.SUCCESS) self.real_create_result else abi.ERROR_INITIALIZATION_FAILED;
            self.noteRealVulkanResult(failure, name);
            self.noteCreateDriverFailure(name, failure);
            machoCapturePrint(
                "macho-processor: REAL {s} creation failed: VkResult={d}; refusing synthetic fallback\n",
                .{ name, failure },
            );
            return @as(u32, @bitCast(failure));
        };
        if (self.real_create_result != abi.SUCCESS) {
            self.noteRealVulkanResult(self.real_create_result, name);
            self.noteCreateDriverFailure(name, self.real_create_result);
            return @as(u32, @bitCast(self.real_create_result));
        }
        if (!self.realVulkanObjectMapped(handle, name)) {
            // A successful native call without a reverse mapping is not a
            // usable success. Publishing a synthetic guest handle here
            // would create exactly the silent tier substitution this
            // boundary is intended to prevent.
            self.noteCreateRefusedBeforeDriver(name);
            machoCapturePrint(
                "macho-processor: REAL {s} creation violated handle contract: native object was not recorded for guest_token=0x{x}; refusing to publish the synthetic token\n",
                .{ name, handle },
            );
            return vkErrorInitializationFailed();
        }
    }
    if (std.mem.eql(u8, name, "vkCreateImageView")) {
        self.trackImageView(state, handle, create_info);
    } else if (std.mem.eql(u8, name, "vkCreateBufferView")) {
        var info: marshal.BufferViewCreateInfo = undefined;
        if (copyGuestValue(marshal.BufferViewCreateInfo, state, create_info, &info)) {
            for (&self.tracked_buffer_views) |*view| {
                if (view.synthetic != 0) continue;
                view.* = .{ .synthetic = handle, .buffer = info.buffer, .format = info.format, .offset = info.offset, .range = info.range };
                break;
            }
        }
    } else if (std.mem.eql(u8, name, "vkCreateRenderPass")) {
        self.trackRenderPass(state, handle, create_info);
    } else if (std.mem.eql(u8, name, "vkCreateFramebuffer")) {
        self.trackFramebuffer(state, handle, create_info);
    }
    // A native image/buffer is not useful to the bridge without the
    // guest-side resource description that lets later requirements,
    // binding, and frame discovery translate it.  Record it before
    // publishing the synthetic handle.  If bookkeeping cannot be
    // committed, destroy the native object and fail instead of returning
    // a handle that can never be mapped back to its resource.
    const tracked = if (std.mem.eql(u8, name, "vkCreateImage"))
        self.recordImage(state, handle, create_info)
    else if (std.mem.eql(u8, name, "vkCreateBuffer"))
        self.recordBuffer(state, handle, create_info)
    else
        true;
    if (!tracked and self.real_vulkan.hasDevice()) {
        const device = self.real_vulkan.device.?;
        if (std.mem.eql(u8, name, "vkCreateImage")) {
            if (self.real_vulkan.realImage(handle)) |real_image| {
                if (self.real_vulkan.fn_ptrs.destroy_image) |destroy| destroy(device, real_image, null);
                self.vulkan_real_objects_destroyed +|= 1;
            }
            _ = self.releaseVulkanHandle(&self.real_vulkan.image_map, handle);
        } else if (std.mem.eql(u8, name, "vkCreateBuffer")) {
            if (self.real_vulkan.realBuffer(handle)) |real_buffer| {
                if (self.real_vulkan.fn_ptrs.destroy_buffer) |destroy| destroy(device, real_buffer, null);
                self.vulkan_real_objects_destroyed +|= 1;
            }
            _ = self.releaseVulkanHandle(&self.real_vulkan.buffer_map, handle);
        }
        self.noteCreateRefusedBeforeDriver(name);
        machoCapturePrint(
            "macho-processor: REAL {s} refused: native object had no committed resource provenance; native object destroyed\n",
            .{name},
        );
        return vkErrorInitializationFailed();
    }
    state.write64(output, handle);
    registerOpaqueHandle(state, handle, name);
    self.noteCreatePublished(name);
    self.vulkan_guest_object_publications +|= 1;
    if (sparseVulkanSuccessLog(self.vulkan_guest_object_publications)) {
        machoCapturePrint(
            "macho-processor: Vulkan object publication sample: count={d} latest={s} handle=0x{x} output=0x{x}\n",
            .{ self.vulkan_guest_object_publications, name, handle, output },
        );
    }
    return 0;
}

pub fn realVulkanObjectMapped(self: anytype, synthetic_handle: u64, name: []const u8) bool {
    const mapped = if (std.mem.eql(u8, name, "vkCreateDescriptorUpdateTemplate"))
        HandleMap.findReal(&self.real_vulkan.descriptor_update_template_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreatePipelineCache"))
        HandleMap.findReal(&self.real_vulkan.pipeline_cache_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateImage"))
        HandleMap.findReal(&self.real_vulkan.image_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateBuffer"))
        HandleMap.findReal(&self.real_vulkan.buffer_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateSampler"))
        HandleMap.findReal(&self.real_vulkan.sampler_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateShaderModule"))
        HandleMap.findReal(&self.real_vulkan.shader_module_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateRenderPass"))
        HandleMap.findReal(&self.real_vulkan.render_pass_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateFramebuffer"))
        HandleMap.findReal(&self.real_vulkan.framebuffer_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateDescriptorSetLayout"))
        HandleMap.findReal(&self.real_vulkan.descriptor_set_layout_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreatePipelineLayout"))
        HandleMap.findReal(&self.real_vulkan.pipeline_layout_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateDescriptorPool"))
        HandleMap.findReal(&self.real_vulkan.descriptor_pool_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateBufferView"))
        HandleMap.findReal(&self.real_vulkan.buffer_view_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateImageView"))
        HandleMap.findReal(&self.real_vulkan.image_view_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateCommandPool"))
        HandleMap.findReal(&self.real_vulkan.command_pool_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateFence"))
        HandleMap.findReal(&self.real_vulkan.fence_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateSemaphore"))
        HandleMap.findReal(&self.real_vulkan.semaphore_map, synthetic_handle)
    else if (std.mem.eql(u8, name, "vkCreateQueryPool"))
        HandleMap.findReal(&self.real_vulkan.query_pool_map, synthetic_handle)
    else
        null;
    return mapped != null and mapped.? != 0;
}

pub fn resolveRealHandle(context: *anyopaque, kind: marshal.HandleKind, synthetic: u64) ?u64 {
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

pub fn MarshalReader(comptime State: type) type {
    return struct {
        fn read(context: *anyopaque, address: u64, length: u64) ?[]const u8 {
            const typed: *State = @ptrCast(@alignCast(context));
            return typed.guestMemoryConst(address, length);
        }
    };
}

pub fn marshalCreateInfo(
    self: anytype,
    state: anytype,
    create_info: u64,
    name: []const u8,
) ?[]u8 {
    if (create_info == 0) return null;
    self.vulkan_scratch.reset();

    // Generated Xenia SPIR-V is the one create-info whose pointed-to
    // payload can legitimately exceed the inline marshalling arena. Read
    // its size before the generic copy so all returned pointers can live
    // in one stable backing store; growing after the root has been handed
    // out would leave pCode pointing at the old buffer.
    if (std.mem.eql(u8, name, "vkCreateShaderModule")) {
        var shader_root: marshal.ShaderModuleCreateInfo = undefined;
        if (!copyGuestValue(marshal.ShaderModuleCreateInfo, state, create_info, &shader_root)) return null;
        const required = std.math.add(usize, @sizeOf(marshal.ShaderModuleCreateInfo), shader_root.code_size) catch {
            self.vulkan_marshal_spill_failures +|= 1;
            self.vulkan_marshal_refusals +|= 1;
            return null;
        };
        if (required > marshal.scratch_bytes) {
            self.vulkan_marshal_spill_reserves +|= 1;
            if (!self.vulkan_scratch.reserve(required)) {
                self.vulkan_marshal_spill_failures +|= 1;
                self.vulkan_marshal_refusals +|= 1;
                if (self.vulkan_marshal_refusals <= 16) machoCapturePrint(
                    "macho-processor: vulkan marshal refused {s}: scratch_exhausted required={d} capacity={d} max={d}\n",
                    .{ name, required, self.vulkan_scratch.capacity(), marshal.max_spill_bytes },
                );
                return null;
            }
            self.vulkan_marshal_spill_peak_bytes = @max(
                self.vulkan_marshal_spill_peak_bytes,
                @as(u64, @intCast(self.vulkan_scratch.capacity())),
            );
        }
    }

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

pub fn marshalSemaphoreCreateInfo(self: anytype, state: anytype, create_info: u64) ?[]u8 {
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

pub fn marshalImageCreateInfo(self: anytype, state: anytype, create_info: u64) ?[]u8 {
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
    if (imageReadbackAugmentable(root.usage, root.format, root.image_type, root.samples)) {
        // The brightness ladder reads the images the presenter samples,
        // which the guest creates without TRANSFER_SRC. The host image
        // gains the bit; the guest's own view of its usage is unchanged
        // and Metal's blit path accepts any colour texture, so nothing
        // the guest does with the image can observe the difference.
        root.usage |= abi.IMAGE_USAGE_TRANSFER_SRC_BIT;
        self.vulkan_image_usage_augmented +|= 1;
    }
    return root_bytes;
}

pub fn createRealVulkanObject(self: anytype, state: anytype, synthetic_handle: u64, create_info: u64, name: []const u8) !void {
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
            _ = self.mapVulkanHandle(&self.real_vulkan.descriptor_update_template_map, synthetic_handle, real_template, "vkCreateDescriptorUpdateTemplate");
            if (self.real_vulkan.descriptorUpdateTemplateIndex(synthetic_handle)) |record_index| {
                const record = &self.real_vulkan.descriptor_update_template_records[record_index];
                record.entry_count = @intCast(guest_root.descriptor_update_entry_count);
                if (guest_root.descriptor_update_entry_count != 0) {
                    @memcpy(record.entries[0..@as(usize, @intCast(guest_root.descriptor_update_entry_count))], entries[0..@as(usize, @intCast(guest_root.descriptor_update_entry_count))]);
                }
            }
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateDescriptorUpdateTemplate synthetic=0x{x} real=0x{x} entries={d}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_template, guest_root.descriptor_update_entry_count });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.pipeline_cache_map, synthetic_handle, real_cache, "vkCreatePipelineCache");
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreatePipelineCache synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_cache });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.image_map, synthetic_handle, real_image, "vkCreateImage");
            self.vulkan_real_objects_created +|= 1;
            self.vulkan_tiers.note(.image_object, .real);
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateImage synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_image });
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
            if (self.native_texture_state) |native| native.noteBuffer(real_buffer, state.read64(create_info + VK_BUFFER_CREATE_INFO_SIZE_OFFSET));
            _ = self.mapVulkanHandle(&self.real_vulkan.buffer_map, synthetic_handle, real_buffer, "vkCreateBuffer");
            // VkBufferCreateInfo: size at +24, usage at +32.
            if (rectExpansionBuiltinIndexBuffer(state.read64(create_info + 24), state.read32(create_info + 32))) {
                self.rect_expand_builtin_index_buffer = real_buffer;
                self.rect_expand_builtin_index_buffers_seen +|= 1;
                machoCapturePrint("macho-processor: RECT EXPAND: built-in index buffer identified real=0x{x} size={d}; only draws that bind it are rectangle expansions\n", .{ real_buffer, state.read64(create_info + 24) });
            }
            self.vulkan_real_objects_created +|= 1;
            self.vulkan_tiers.note(.buffer_object, .real);
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateBuffer synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_buffer });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.sampler_map, synthetic_handle, real_sampler, "vkCreateSampler");
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateSampler synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_sampler });
        } else {
            machoCapturePrint("macho-processor: vkCreateSampler FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
            self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
        }
    } else if (std.mem.eql(u8, name, "vkCreateShaderModule")) {
        // Marshalled: every pointer and handle inside the structure is

        // translated, and a refusal keeps the modelled path rather than

        // handing the driver a guest address.

        const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
        const module_info: *marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(info.ptr));
        const ModuleInspection = struct {
            stages: gpu_vulkan.spirv_stage.ModuleStages,
            fingerprint: u64,
        };
        const module_inspection: ModuleInspection = blk: {
            if (module_info.code_size < 20 or module_info.code_size % 4 != 0) break :blk .{
                .stages = gpu_vulkan.spirv_stage.inspect(&.{}),
                .fingerprint = @as(u64, 0),
            };
            const code = module_info.code orelse break :blk .{
                .stages = gpu_vulkan.spirv_stage.inspect(&.{}),
                .fingerprint = @as(u64, 0),
            };
            const words: [*]const u32 = @ptrCast(@alignCast(code));
            const word_slice = words[0 .. module_info.code_size / 4];
            break :blk .{
                .stages = gpu_vulkan.spirv_stage.inspect(word_slice),
                .fingerprint = fsi_diagnostics.spirvFingerprint(word_slice),
            };
        };
        const module_stages = module_inspection.stages;
        if (!module_stages.valid or !module_stages.has_entry_point) {
            self.vulkan_shader_module_spirv_unreadable +|= 1;
        }
        const native_format = if (self.native_texture_state != null and module_info.code != null and module_stages.valid)
            native_texture.identify(@as([*]const u8, @ptrCast(module_info.code.?))[0..module_info.code_size])
        else
            null;
        const has_fsi_interlock = module_stages.usesFragmentShaderInterlock();
        if (has_fsi_interlock) {
            self.vulkan_fsi_shader_modules +|= 1;
            self.vulkan_fsi_spirv_capability_mask |= module_stages.fragment_interlock_capabilities;
            self.vulkan_fsi_spirv_begin_ops +|= module_stages.begin_interlock_ops;
            self.vulkan_fsi_spirv_end_ops +|= module_stages.end_interlock_ops;
        }
        const tessellation_stage_mask = module_stages.tessellationMask();
        if ((tessellation_stage_mask & 1) != 0) self.vulkan_tess_control_shader_modules +|= 1;
        if ((tessellation_stage_mask & 2) != 0) self.vulkan_tess_eval_shader_modules +|= 1;
        const create_fn = self.real_vulkan.fn_ptrs.create_shader_module orelse return error.MissingFn;
        self.fsiSaveShaderEvidence(synthetic_handle, @ptrCast(@alignCast(info.ptr)), .guest);
        const hdr_resolve = self.correctHdrResolve(info) catch {
            self.real_create_result = abi.ERROR_OUT_OF_HOST_MEMORY;
            return;
        };
        defer if (hdr_resolve) |words| std.heap.c_allocator.free(words);
        // Give a vertex shader the ability to expand a Xenos rectangle
        // list itself. Xenia's SPIR-V translator never implemented the
        // `kRectangleListAsTriangleStrip` fallback it selects on a host
        // with no geometry shader, so without this the fourth corner of
        // every rectangle is never shaded. See `rect_list_expand`.
        const expanded = self.expandRectangleListShader(info, synthetic_handle, module_inspection.fingerprint);
        defer if (expanded) |expansion| std.heap.c_allocator.free(expansion.words);
        const pixel_frequency = self.normalizeFsiPixelFrequency(info) catch {
            self.real_create_result = abi.ERROR_OUT_OF_HOST_MEMORY;
            return;
        };
        defer if (pixel_frequency) |words| std.heap.c_allocator.free(words);
        // Then bound every dynamic index: Metal has no robustBufferAccess.
        const hardened = self.hardenShaderModule(info, synthetic_handle) catch {
            self.fsiUpdateShaderBoundsBudget();
            self.real_create_result = abi.ERROR_INITIALIZATION_FAILED;
            return;
        };
        defer if (hardened) |hardening| std.heap.c_allocator.free(hardening.words);
        var real_module: u64 = 0;
        var result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_module);
        if (result != 0 and hdr_resolve != null) self.hdr_resolve_driver_rejections +|= 1;
        if (result != 0 and pixel_frequency != null) self.fsi_pixel_frequency_driver_rejections +|= 1;
        if (result != 0 and hardened != null) {
            // A failed safety transform must never fall back to the
            // original shader that can fault the GPU.
            self.robust_access_driver_rejections +|= 1;
            machoCapturePrint("macho-processor: VULKAN ROBUST ACCESS: the driver refused a hardened module (VkResult={d}); module=0x{x} refused before GPU use\n", .{ result, synthetic_handle });
        }
        var expansion_used = expanded != null;
        if (result != 0 and expanded != null and !self.robust_access_enabled) {
            // The driver would not take the rewritten module. Put the
            // guest's own SPIR-V back and create that instead: a rectangle
            // with a missing fourth corner is a far better outcome than a
            // pipeline this title cannot create at all.
            const root: *marshal.ShaderModuleCreateInfo = @ptrCast(@alignCast(info.ptr));
            self.rect_expand_last_driver_rejection_result = result;
            self.rect_expand_last_driver_rejection_module = synthetic_handle;
            self.rect_expand_last_driver_rejection_hash = module_inspection.fingerprint;
            self.rect_expand_last_driver_rejection_bytes = @truncate(@min(expanded.?.original_size, @as(usize, std.math.maxInt(u32))));
            self.metal_backend_health.noteGap(.rectangle_shader_driver_rejection);
            root.code = expanded.?.original_code;
            root.code_size = expanded.?.original_size;
            expansion_used = false;
            self.rect_expand_module_rejections +|= 1;
            if (self.rect_expand_module_rejections <= 4) machoCapturePrint(
                "macho-processor: RECT EXPAND: the driver refused the rewritten vertex shader (VkResult={d}); the guest's own module was created instead\n",
                .{result},
            );
            result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_module);
        }
        self.fsiUpdateShaderBoundsBudget();
        if (result == 0 and real_module != 0) {
            self.fsiSaveShaderEvidence(synthetic_handle, @ptrCast(@alignCast(info.ptr)), .native);
            self.metal_backend_health.noteSpirvModule();
            if (native_format) |format| if (self.native_texture_state) |native| {
                native.noteShader(real_module, format);
                machoCapturePrint("macho-processor: NATIVE METAL TEXTURES: matched_exact_loader={s} guest_module=0x{x} native_module=0x{x}\n", .{ @tagName(format), synthetic_handle, real_module });
            };
            if (has_fsi_interlock) self.vulkan_fsi_shader_modules_native_success +|= 1;
            if ((tessellation_stage_mask & 1) != 0) self.vulkan_tess_control_shader_modules_native_success +|= 1;
            if ((tessellation_stage_mask & 2) != 0) self.vulkan_tess_eval_shader_modules_native_success +|= 1;
            _ = self.mapVulkanHandle(&self.real_vulkan.shader_module_map, synthetic_handle, real_module, "vkCreateShaderModule");
            if (has_fsi_interlock) {
                if (self.vulkan_fsi_tracker.rememberShader(synthetic_handle, module_inspection.fingerprint, @truncate(module_info.code_size), module_stages)) |identity| {
                    machoCapturePrint(
                        "macho-processor: Vulkan FSI SHADER: module_id={d} guest=0x{x} native=0x{x} spirv_hash=0x{x} bytes={d} execution_models=0x{x} capabilities=0x{x} begin/end={d}/{d}; stable content identity links this SPIR-V module to later pipeline, draw and submit records\n",
                        .{ identity.id, synthetic_handle, real_module, identity.spirv_hash, identity.code_bytes, identity.execution_model_mask, identity.capability_mask, identity.begin_ops, identity.end_ops },
                    );
                }
            }
            if (expansion_used) self.noteRectangleExpandedModule(real_module);
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateShaderModule synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_module });
        } else {
            if (has_fsi_interlock) self.vulkan_fsi_shader_modules_native_failure +|= 1;
            if ((tessellation_stage_mask & 1) != 0) self.vulkan_tess_control_shader_modules_native_failure +|= 1;
            if ((tessellation_stage_mask & 2) != 0) self.vulkan_tess_eval_shader_modules_native_failure +|= 1;
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
            _ = self.mapVulkanHandle(&self.real_vulkan.render_pass_map, synthetic_handle, real_rp, "vkCreateRenderPass");
            self.fsiNoteRenderPassCreated(real_rp, info);
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateRenderPass synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_rp });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.framebuffer_map, synthetic_handle, real_fb, "vkCreateFramebuffer");
            self.fsiNoteFramebufferCreated(info);
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateFramebuffer synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_fb });
        } else {
            machoCapturePrint("macho-processor: vkCreateFramebuffer FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
            self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
        }
    } else if (std.mem.eql(u8, name, "vkCreateDescriptorSetLayout")) {
        // Marshalled: every pointer and handle inside the structure is

        // translated, and a refusal keeps the modelled path rather than

        // handing the driver a guest address.

        self.observeFsiDescriptorSetLayout(state, create_info);
        const info = self.marshalCreateInfo(state, create_info, name) orelse return error.InvalidInfo;
        const create_fn = self.real_vulkan.fn_ptrs.create_descriptor_set_layout orelse return error.MissingFn;
        var real_layout: u64 = 0;
        const result = create_fn(device, @ptrCast(@alignCast(info.ptr)), null, &real_layout);
        if (result == 0 and real_layout != 0) {
            _ = self.mapVulkanHandle(&self.real_vulkan.descriptor_set_layout_map, synthetic_handle, real_layout, "vkCreateDescriptorSetLayout");
            if (self.native_texture_state) |native| native.noteSetLayout(real_layout, @ptrCast(@alignCast(info.ptr)));
            self.vulkan_real_objects_created +|= 1;
            self.vulkan_tiers.note(.descriptor_set_layout, .real);
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateDescriptorSetLayout synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_layout });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.pipeline_layout_map, synthetic_handle, real_pl, "vkCreatePipelineLayout");
            self.rememberPipelineLayout(real_pl, info);
            if (self.native_texture_state) |native| native.noteLayout(real_pl, @ptrCast(@alignCast(info.ptr)));
            self.vulkan_real_objects_created +|= 1;
            self.vulkan_tiers.note(.pipeline_layout, .real);
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreatePipelineLayout synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_pl });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.descriptor_pool_map, synthetic_handle, real_pool, "vkCreateDescriptorPool");
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateDescriptorPool synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_pool });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.buffer_view_map, synthetic_handle, real_bv, "vkCreateBufferView");
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateBufferView synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_bv });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.image_view_map, synthetic_handle, real_iv, "vkCreateImageView");
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateImageView synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_iv });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.command_pool_map, synthetic_handle, real_pool, "vkCreateCommandPool");
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateCommandPool synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_pool });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.fence_map, synthetic_handle, real_fence, "vkCreateFence");
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateFence synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_fence });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.semaphore_map, synthetic_handle, real_sem, "vkCreateSemaphore");
            self.vulkan_real_objects_created +|= 1;
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateSemaphore synthetic=0x{x} real=0x{x}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_sem });
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
            _ = self.mapVulkanHandle(&self.real_vulkan.query_pool_map, synthetic_handle, real_pool, "vkCreateQueryPool");
            self.vulkan_real_objects_created +|= 1;
            self.vulkan_tiers.note(.command_recording, .real);
            if (sparseVulkanSuccessLog(self.vulkan_real_objects_created)) machoCapturePrint("macho-processor: REAL Vulkan object sample: count={d} name=vkCreateQueryPool synthetic=0x{x} real=0x{x} type={d} count={d}\n", .{ self.vulkan_real_objects_created, synthetic_handle, real_pool, guest_info.query_type, guest_info.query_count });
        } else {
            machoCapturePrint("macho-processor: vkCreateQueryPool FAILED: VkResult={d} info=0x{x}\n", .{ result, create_info });
            self.real_create_result = if (result != abi.SUCCESS) result else abi.ERROR_INITIALIZATION_FAILED;
        }
    }
}

pub fn trackedResourceCount(self: anytype) usize {
    var count: usize = 0;
    for (self.vulkan_resources) |record| {
        if (record.handle != 0) count += 1;
    }
    return count;
}

pub fn freeResourceSlotCount(self: anytype) usize {
    return self.vulkan_resources.len - self.trackedResourceCount();
}

pub fn noteResourceRecordCommitted(self: anytype, was_empty: bool) void {
    if (!was_empty) return;
    self.vulkan_resource_records_committed +|= 1;
    const live = self.trackedResourceCount();
    self.vulkan_resource_high_water = @max(self.vulkan_resource_high_water, @as(u64, @intCast(live)));
}

pub fn releaseResource(self: anytype, handle: u64) bool {
    const record = self.findResource(handle) orelse return false;
    record.* = .{};
    self.vulkan_resource_records_released +|= 1;
    return true;
}

pub fn trackedImageCount(self: anytype) u64 {
    var count: u64 = 0;
    for (self.vulkan_resources) |record| {
        if (record.handle != 0 and record.kind == .image) count += 1;
    }
    return count;
}

pub fn resourceSlot(self: anytype, handle: u64) ?*VulkanResource {
    var free: ?*VulkanResource = null;
    for (&self.vulkan_resources) |*record| {
        if (record.handle == handle) return record;
        if (record.handle == 0 and free == null) free = record;
    }
    if (free) |record| return record;
    self.vulkan_resource_overflow +|= 1;
    return null;
}

pub fn resourceSlotAvailable(self: anytype) bool {
    return self.freeResourceSlotCount() != 0;
}

pub fn findResource(self: anytype, handle: u64) ?*VulkanResource {
    if (handle == 0) return null;
    for (&self.vulkan_resources) |*record| {
        if (record.handle == handle) return record;
    }
    return null;
}

pub fn recordImage(self: anytype, state: anytype, handle: u64, create_info: u64) bool {
    if (create_info == 0 or state.guestMemoryConst(create_info, VK_IMAGE_CREATE_INFO_SIZE) == null) return false;
    const record = self.resourceSlot(handle) orelse return false;
    const was_empty = record.handle == 0;
    const format = state.read32(create_info + VK_IMAGE_CREATE_INFO_FORMAT_OFFSET);
    const width = state.read32(create_info + VK_IMAGE_CREATE_INFO_EXTENT_OFFSET);
    const height = state.read32(create_info + VK_IMAGE_CREATE_INFO_EXTENT_OFFSET + 4);
    const bytes_per_pixel = rosette_gpu.vulkan.selection.bytesPerPixel(format) orelse 0;
    const row_pitch = std.math.mul(u64, width, bytes_per_pixel) catch return false;
    const size_bytes = std.math.mul(u64, row_pitch, height) catch return false;
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
        .size_bytes = size_bytes,
    };
    self.noteResourceRecordCommitted(was_empty);
    return true;
}

pub fn recordBuffer(self: anytype, state: anytype, handle: u64, create_info: u64) bool {
    if (create_info == 0 or state.guestMemoryConst(create_info, VK_BUFFER_CREATE_INFO_SIZE) == null) return false;
    const record = self.resourceSlot(handle) orelse return false;
    const was_empty = record.handle == 0;
    record.* = .{
        .handle = handle,
        .kind = .buffer,
        .usage = state.read32(create_info + VK_BUFFER_CREATE_INFO_USAGE_OFFSET),
        .size_bytes = state.read64(create_info + VK_BUFFER_CREATE_INFO_SIZE_OFFSET),
    };
    self.noteResourceRecordCommitted(was_empty);
    return true;
}

pub fn bindResourceMemory(self: anytype, resource: u64, memory: u64, offset: u64, kind: VulkanResourceKind) u64 {
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
    if (record.kind != kind) {
        machoCapturePrint(
            "macho-processor: Vulkan bind refused: resource=0x{x} kind mismatch expected={s} recorded={s}\n",
            .{ resource, @tagName(kind), @tagName(record.kind) },
        );
        return vkErrorInitializationFailed();
    }
    if (record.memory != 0) {
        machoCapturePrint(
            "macho-processor: Vulkan bind refused: resource=0x{x} already bound to memory=0x{x}\n",
            .{ resource, record.memory },
        );
        return vkErrorInitializationFailed();
    }
    // Phase 1: bind real Vulkan resources.
    if (self.real_vulkan.hasDevice()) {
        const device = self.real_vulkan.device.?;
        const memory_record = self.findVulkanMemoryRecord(memory) orelse {
            machoCapturePrint(
                "macho-processor: REAL vkBind resource refused: memory=0x{x} has no allocation provenance\n",
                .{memory},
            );
            return vkErrorInitializationFailed();
        };
        const required_size = record.required_size;
        if (!rangeContains(0, memory_record.requested_size, offset, required_size)) {
            machoCapturePrint(
                "macho-processor: REAL vkBind resource refused: resource=0x{x} memory=0x{x} offset={d} required_size={d} allocation_size={d}\n",
                .{ resource, memory, offset, required_size, memory_record.requested_size },
            );
            return vkErrorInitializationFailed();
        }
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
        self.vulkan_memory_bindings +|= 1;
        if (sparseVulkanSuccessLog(self.vulkan_memory_bindings)) machoCapturePrint(
            "macho-processor: REAL Vulkan bind sample: count={d} kind={s} resource=0x{x} memory=0x{x} offset={d}\n",
            .{ self.vulkan_memory_bindings, @tagName(kind), resource, real_mem, offset },
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

pub fn bindResourcesMemory2(
    self: anytype,
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

pub fn writeExactMemoryRequirements(
    self: anytype,
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

pub fn writeSyntheticMemoryRequirements(self: anytype, state: anytype, output: u64, size: u64) u64 {
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

pub fn writeResourceMemoryRequirements(self: anytype, state: anytype, resource: u64, output: u64) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    // Phase 1: query real requirements when possible.
    if (self.real_vulkan.hasDevice()) {
        const device = self.real_vulkan.device.?;
        // Check if this is a buffer or image.
        if (self.real_vulkan.realBuffer(resource)) |rb| {
            if (self.real_vulkan.fn_ptrs.get_buffer_memory_requirements) |get_fn| {
                var reqs: abi.MemoryRequirements = .{};
                get_fn(device, rb, &reqs);
                if (self.findResource(resource)) |record| record.required_size = reqs.size;
                self.vulkan_tiers.note(.memory_requirements, .real);
                return self.writeExactMemoryRequirements(state, output, reqs);
            }
        }
        if (self.real_vulkan.realImage(resource)) |ri| {
            if (self.real_vulkan.fn_ptrs.get_image_memory_requirements) |get_fn| {
                var reqs: abi.MemoryRequirements = .{};
                get_fn(device, ri, &reqs);
                if (self.findResource(resource)) |record| record.required_size = reqs.size;
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

pub fn writeResourceMemoryRequirements2(self: anytype, state: anytype, info: u64, output: u64) u64 {
    if (state.guestMemoryConst(info, 24) == null or state.guestMemory(output, 40) == null) {
        return vkErrorInitializationFailed();
    }
    const resource = state.read64(info + 16);
    return self.writeResourceMemoryRequirements(state, resource, output + 16);
}

pub fn writeDeviceBufferMemoryRequirements(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const info_address = guest_context.registers(state).rsi;
    const output = guest_context.registers(state).rdx;
    if (info_address == 0 or output == 0 or state.guestMemoryConst(info_address, @sizeOf(abi.BufferMemoryRequirementsInfo2)) == null or
        state.guestMemory(output, @sizeOf(abi.MemoryRequirements2)) == null) return 0;
    const synthetic = state.read64(info_address + 16);
    if (self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.get_device_buffer_memory_requirements != null) {
        const real_buffer = self.real_vulkan.realBuffer(synthetic) orelse return 0;
        var info = abi.BufferMemoryRequirementsInfo2{ .buffer = real_buffer };
        var result: abi.MemoryRequirements2 = .{};
        self.real_vulkan.fn_ptrs.get_device_buffer_memory_requirements.?(self.real_vulkan.device.?, &info, &result);
        if (self.findResource(synthetic)) |record| record.required_size = result.memory_requirements.size;
        self.vulkan_tiers.note(.memory_requirements, .real);
        return self.writeExactMemoryRequirements(state, output + 16, result.memory_requirements);
    }
    self.vulkan_absent_reached.note(
        "vkGetDeviceBufferMemoryRequirements",
        "the Vulkan 1.1 vkGetBufferMemoryRequirements2 path",
    );
    return self.writeResourceMemoryRequirements2(state, info_address, output);
}

pub fn writeDeviceImageMemoryRequirements(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const info_address = guest_context.registers(state).rsi;
    const output = guest_context.registers(state).rdx;
    if (info_address == 0 or output == 0 or state.guestMemoryConst(info_address, @sizeOf(abi.ImageMemoryRequirementsInfo2)) == null or
        state.guestMemory(output, @sizeOf(abi.MemoryRequirements2)) == null) return 0;
    const synthetic = state.read64(info_address + 16);
    if (self.real_vulkan.hasDevice() and self.real_vulkan.fn_ptrs.get_device_image_memory_requirements != null) {
        const real_image = self.real_vulkan.realImage(synthetic) orelse return 0;
        var info = abi.ImageMemoryRequirementsInfo2{ .image = real_image };
        var result: abi.MemoryRequirements2 = .{};
        self.real_vulkan.fn_ptrs.get_device_image_memory_requirements.?(self.real_vulkan.device.?, &info, &result);
        if (self.findResource(synthetic)) |record| record.required_size = result.memory_requirements.size;
        self.vulkan_tiers.note(.memory_requirements, .real);
        return self.writeExactMemoryRequirements(state, output + 16, result.memory_requirements);
    }
    self.vulkan_absent_reached.note(
        "vkGetDeviceImageMemoryRequirements",
        "the Vulkan 1.1 vkGetImageMemoryRequirements2 path",
    );
    return self.writeResourceMemoryRequirements2(state, info_address, output);
}

pub fn createLogicalDevice(self: anytype, state: anytype, output: u64) u64 {
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

pub fn recordVulkanCall(self: anytype, _: anytype, name: []const u8, result: i32, arg0: u64, arg1: u64) void {
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

pub fn dumpVulkanCallTrace(self: anytype) void {
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

pub fn dumpVulkanStateSnapshot(self: anytype) void {
    self.drainAsyncVulkanCommands();
    machoCapturePrint("macho-processor: VULKAN STATE SNAPSHOT BEGIN\n", .{});
    machoCapturePrint(
        "macho-processor:   loader_lookups: unique={d} repeats_suppressed={d} cache_overflows={d}\n",
        .{ self.vulkan_loader_lookup_unique, self.vulkan_loader_lookup_repeats, self.vulkan_loader_lookup_cache_overflows },
    );
    machoCapturePrint(
        "macho-processor:   real_device={} device_lost={} real_instance={} real_physical=0x{x}\n",
        .{ self.real_vulkan.hasDevice(), self.real_vulkan.device_lost, self.real_vulkan.hasInstance(), if (self.real_vulkan.physical_device) |p| @intFromPtr(p) else @as(u64, 0) },
    );
    machoCapturePrint(
        "macho-processor:   counters: device_void={d} opaque={d} memory_allocs={d} memory_maps={d} queue_submits={d} fence_only_submits={d} real_queue_submits={d} presents={d} real_presents={d} real_present_completions={d} command_calls={d} real_command_calls={d} real_objects_created={d} real_objects_destroyed={d} shadow_uploads={d} shadow_upload_failures={d} fence_completions={d} device_lost_events={d} pipeline_cache_loads={d} pipeline_cache_saves={d}\n",
        .{ self.vulkan_device_void_calls, self.guest_opaque_calls, self.vulkan_memory_allocations, self.vulkan_memory_maps, self.vulkan_queue_submits, self.vulkan_fence_only_queue_submits, self.vulkan_real_queue_submits, self.vulkan_presents, self.vulkan_real_presents, self.vulkan_real_present_completions, self.vulkan_modeled_command_calls, self.vulkan_real_command_calls, self.vulkan_real_objects_created, self.vulkan_real_objects_destroyed, self.vulkan_shadow_uploads, self.vulkan_shadow_upload_failures, self.vulkan_fence_completions, self.vulkan_device_lost_events, self.vulkan_pipeline_cache_loads, self.vulkan_pipeline_cache_saves },
    );
    if (self.vulkan_device_loss_evidence.first_api_detection) {
        const loss = &self.vulkan_device_loss_evidence;
        machoCapturePrint(
            "macho-processor:   first_device_loss: operation={s} result={d} later_observations={d} guest_submits={d} native_submits_accepted={d} native_presents_accepted={d} present_completions={d} fence_completions={d} fsi_draws(recorded/submitted)={d}/{d} last_fsi_submit(queue/target)={d}/0x{x}; first Vulkan API detection retained across device recreation\n",
            .{ loss.operationName(), loss.result, loss.occurrences, loss.guest_queue_submit_calls, loss.native_queue_submits_accepted, loss.native_presents_accepted, loss.native_present_completions, loss.fence_completions, loss.fsi_recorded_draws, loss.fsi_submitted_draws, loss.last_fsi_queue_submit, loss.last_fsi_target_image },
        );
        self.printDeviceLossFsiSubmission("device_loss_last_fsi_submission", loss.last_fsi_submission);
    }
    if (self.vulkan_device_loss_evidence.first_unexpected_error.first_observed) {
        const failure = &self.vulkan_device_loss_evidence.first_unexpected_error;
        machoCapturePrint(
            "macho-processor:   first_unexpected_vulkan_error: operation={s} result={d} occurrences={d} guest_submits={d} native_submits_accepted={d} native_presents_accepted={d} present_completions={d} fence_completions={d} fsi_draws(recorded/submitted)={d}/{d} last_fsi_submit(queue/target)={d}/0x{x}; OUT_OF_DATE swapchain results are excluded; this is the earliest unexpected API error, not proof of the underlying driver fault\n",
            .{ failure.operationName(), failure.result, failure.occurrences, failure.guest_queue_submit_calls, failure.native_queue_submits_accepted, failure.native_presents_accepted, failure.native_present_completions, failure.fence_completions, failure.fsi_recorded_draws, failure.fsi_submitted_draws, failure.last_fsi_queue_submit, failure.last_fsi_target_image },
        );
        self.printDeviceLossFsiSubmission("first_unexpected_error_last_fsi_submission", failure.last_fsi_submission);
    }
    machoCapturePrint(
        "macho-processor: METAL BACKEND HEALTH: live_translation_path={s} Vulkan_SPIR-V_modules_forwarded={d} Rosette_native_MSL_modules={d}; Xenia's live shaders use the Vulkan driver's SPIR-V-to-MSL route unless a Rosette native-MSL dispatch is explicitly recorded, so offline AIR/metallib cache state is not evidence of live shader use\n",
        .{ @tagName(self.metal_backend_health.live_translation_path), self.metal_backend_health.spirv_modules_forwarded, self.metal_backend_health.native_msl_modules },
    );
    for (std.enums.values(rosette_gpu.metal_backend_health.CapabilityGap)) |gap| {
        const count = self.metal_backend_health.gapCount(gap);
        if (count == 0) continue;
        machoCapturePrint(
            "macho-processor: METAL BACKEND GAP OBSERVED: kind={s} count={d}; this records an encountered refusal/rejection, not a guessed unsupported capability set\n",
            .{ @tagName(gap), count },
        );
    }
    machoCapturePrint(
        "macho-processor:   marshal_scratch: capacity={d} used={d} spill_reserves={d} peak_bytes={d} spill_failures={d} refusals={d}; shader/module arrays are kept intact or refused, never truncated\n",
        .{ self.vulkan_scratch.capacity(), self.vulkan_scratch.used, self.vulkan_marshal_spill_reserves, self.vulkan_marshal_spill_peak_bytes, self.vulkan_marshal_spill_failures, self.vulkan_marshal_refusals },
    );
    machoCapturePrint(
        "macho-processor:   success_samples: guest_object_publications={d} memory_bindings={d} command_buffer_alloc_calls={d} descriptor_set_alloc_calls={d} synthetic_object_batches={d}\n",
        .{ self.vulkan_guest_object_publications, self.vulkan_memory_bindings, self.vulkan_command_buffer_allocations, self.vulkan_descriptor_set_allocations, self.vulkan_synthetic_object_batches },
    );
    self.logVulkanHandleMapState();
    machoCapturePrint(
        "macho-processor:   command_shape: render_begin={d} render_end={d} draw={d} dispatch={d} clear={d} copy_or_resolve={d} other={d} loadop_clear_writes={d} write_marks={d} content_marks={d} target_submissions={d}\n",
        .{ self.vulkan_command_render_begin_calls, self.vulkan_command_render_end_calls, self.vulkan_command_draw_calls, self.vulkan_command_dispatch_calls, self.vulkan_command_clear_calls, self.vulkan_command_copy_calls, self.vulkan_command_other_calls, self.vulkan_render_pass_load_clear_calls, self.vulkan_command_write_marks, self.vulkan_command_content_marks, self.vulkan_target_submission_events },
    );
    machoCapturePrint(
        "macho-processor:   graphics_state_trace: enabled={} draws={d} push_constants={d} printed={d} missing_viewport={d} missing_scissor={d} bad_viewport={d} bad_scissor={d} rect_candidates={d} rect_non_candidates={d} bad_rect={d} topology_mismatch={d} unknown_pipeline={d} pipeline_overflow={d}\n",
        .{ self.graphics_state_trace_enabled, self.graphics_state_trace_draws, self.graphics_state_trace_push_constants, self.graphics_state_trace_printed, self.graphics_state_trace_missing_viewport, self.graphics_state_trace_missing_scissor, self.graphics_state_trace_bad_viewport, self.graphics_state_trace_bad_scissor, self.graphics_state_trace_rect_candidates, self.graphics_state_trace_rect_non_candidates, self.graphics_state_trace_bad_rect, self.graphics_state_trace_topology_mismatch, self.graphics_state_trace_unknown_pipeline, self.graphics_state_trace_pipeline_overflow },
    );
    machoCapturePrint(
        "macho-processor:   graphics_topology_repair: enabled={} candidates={d} pipeline_twins={d} twin_failures={d} draws_repaired={d} bind_failures={d}; only the Xenia 4-vertex rectangle contract can select the triangle-strip twin\n",
        .{ self.guest_output_topology_repair_enabled, self.graphics_topology_repair_candidates, self.graphics_topology_repair_pipeline_creations, self.graphics_topology_repair_create_failures, self.graphics_topology_repairs, self.graphics_topology_repair_bind_failures },
    );
    machoCapturePrint(
        "macho-processor:   queues: graphics={} compute={} transfer={}\n",
        .{ self.real_vulkan.graphics_queue != null, self.real_vulkan.compute_queue != null, self.real_vulkan.transfer_queue != null },
    );
    if (self.vulkan_create_ledger_count != 0) self.dumpVulkanCreateLedger();
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

pub fn writeDeviceQueue(self: anytype, state: anytype, output: u64, name: []const u8) u64 {
    if (output == 0 or state.guestMemory(output, 8) == null) return vkErrorInitializationFailed();
    var queue: u64 = VK_SYNTHETIC_QUEUE;
    var native_queue: u64 = 0;
    var family_index: u32 = @truncate(guest_context.registers(state).rsi);
    var queue_index: u32 = @truncate(guest_context.registers(state).rdx);
    const queue2 = std.mem.eql(u8, name, "vkGetDeviceQueue2");
    if (queue2) {
        const queue_info = guest_context.registers(state).rsi;
        // VkDeviceQueueInfo2 is a guest structure.  Treating an invalid
        // pointer as a legacy vkGetDeviceQueue call used to return the
        // synthetic queue and hide a malformed dispatch.  The only
        // queue2 form Rosette can faithfully lower is flags==0/pNext==0,
        // which is equivalent to vkGetDeviceQueue on the same device.
        if (queue_info == 0 or state.guestMemoryConst(queue_info, 32) == null or
            state.read32(queue_info) != abi.STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2 or
            state.read64(queue_info + 8) != 0 or
            state.read32(queue_info + 16) != 0)
        {
            machoCapturePrint(
                "macho-processor: Vulkan queue contract: refusing malformed vkGetDeviceQueue2 info=0x{x}\n",
                .{queue_info},
            );
            return vkErrorInitializationFailed();
        }
        family_index = state.read32(queue_info + 20);
        queue_index = state.read32(queue_info + 24);
    }
    if (self.real_vulkan.hasDevice()) {
        const guest_device = self.real_vulkan.guest_device_handle;
        const native_device = @intFromPtr(self.real_vulkan.device.?);
        if (guest_context.registers(state).rdi != guest_device and guest_context.registers(state).rdi != native_device) {
            machoCapturePrint(
                "macho-processor: Vulkan queue contract: refusing queue request for unknown device=0x{x} expected=0x{x}\n",
                .{ guest_context.registers(state).rdi, guest_device },
            );
            return vkErrorInitializationFailed();
        }
        if (family_index >= self.real_vulkan.queue_family_count or
            queue_index >= self.real_vulkan.queue_family_properties[family_index].queue_count)
        {
            machoCapturePrint(
                "macho-processor: Vulkan queue contract: refusing out-of-range queue family={d} index={d} families={d} family_count={d}\n",
                .{ family_index, queue_index, self.real_vulkan.queue_family_count, if (family_index < self.real_vulkan.queue_family_count) self.real_vulkan.queue_family_properties[family_index].queue_count else 0 },
            );
            return vkErrorInitializationFailed();
        }
        const get_queue = self.real_vulkan.fn_ptrs.get_device_queue orelse {
            machoCapturePrint(
                "macho-processor: Vulkan queue contract: vkGetDeviceQueue is absent on a live native device\n",
                .{},
            );
            return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        };
        var real_queue: abi.Queue = null;
        get_queue(self.real_vulkan.device.?, family_index, queue_index, &real_queue);
        if (real_queue == null) {
            machoCapturePrint(
                "macho-processor: Vulkan queue contract: native vkGetDeviceQueue returned NULL family={d} index={d}\n",
                .{ family_index, queue_index },
            );
            return vkErrorInitializationFailed();
        }
        native_queue = @intFromPtr(real_queue.?);
        queue = native_queue;
        _ = self.mapVulkanHandle(&self.real_vulkan.queue_map, queue, queue, "vkGetDeviceQueue");
        for (&self.real_vulkan.queue_map, 0..) |*entry, index| {
            const mapping = HandleMap.snapshot(entry) orelse continue;
            if (mapping.real == queue) {
                self.real_vulkan.queue_family_indices[index] = family_index;
                break;
            }
        }
        if (self.real_vulkan.graphics_queue == null) {
            self.real_vulkan.graphics_queue = real_queue;
            self.real_vulkan.graphics_queue_family_index = family_index;
        }
        self.vulkan_tiers.note(.queue, .real);
    }
    state.write64(output, queue);
    registerOpaqueHandle(state, queue, "Vulkan device queue");
    const stored_queue = if (state.guestMemoryConst(output, 8) != null) state.read64(output) else 0;
    machoCapturePrint(
        "macho-processor: Vulkan queue contract: call={d} device=0x{x} family={d} index={d} output=0x{x} native=0x{x} written=0x{x} via={s}\n",
        .{ self.vulkan_queues_acquired + 1, guest_context.registers(state).rdi, family_index, queue_index, output, native_queue, stored_queue, name },
    );
    if (self.real_vulkan.hasDevice() and (native_queue == 0 or stored_queue != native_queue)) {
        machoCapturePrint(
            "macho-processor: Vulkan queue contract FAULT: native queue was not published verbatim output=0x{x} native=0x{x} written=0x{x}; a synthetic queue token cannot cross into the native device path\n",
            .{ output, native_queue, stored_queue },
        );
        _ = std.c.raise(std.c.SIG.SEGV);
        std.c.abort();
    }
    self.vulkan_queues_acquired +|= 1;
    if (self.vulkan_queues_acquired == 1) {
        machoCapturePrint(
            "macho-processor: Vulkan milestone: queue_acquired queue=0x{x} output=0x{x} via={s}\n",
            .{ queue, output, name },
        );
    }
    return 0;
}

pub fn getSemaphoreCounterValue(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const function = self.real_vulkan.fn_ptrs.get_semaphore_counter_value orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const semaphore = self.real_vulkan.realSemaphore(guest_context.registers(state).rsi) orelse return vkErrorInitializationFailed();
    if (guest_context.registers(state).rdx == 0 or state.guestMemory(guest_context.registers(state).rdx, 8) == null) return vkErrorInitializationFailed();
    var value: u64 = 0;
    const result = function(self.real_vulkan.device.?, semaphore, &value);
    if (result == abi.SUCCESS) state.write64(guest_context.registers(state).rdx, value);
    return @as(u32, @bitCast(result));
}

pub fn waitSemaphores(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const function = self.real_vulkan.fn_ptrs.wait_semaphores orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const guest_info = guest_context.registers(state).rsi;
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
    const result = function(self.real_vulkan.device.?, &info, guest_context.registers(state).rdx);
    return @as(u32, @bitCast(result));
}

pub fn signalSemaphore(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const function = self.real_vulkan.fn_ptrs.signal_semaphore orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    var info: abi.SemaphoreSignalInfo = undefined;
    if (!copyGuestValue(abi.SemaphoreSignalInfo, state, guest_context.registers(state).rsi, &info)) return vkErrorInitializationFailed();
    if (info.p_next != null) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    info.semaphore = self.real_vulkan.realSemaphore(info.semaphore) orelse return vkErrorInitializationFailed();
    info.p_next = null;
    const result = function(self.real_vulkan.device.?, &info);
    return @as(u32, @bitCast(result));
}

pub fn writeRealSurfaceCapabilities(self: anytype, state: anytype, output: u64) u64 {
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

pub fn boundSurfaceEnumeration(self: anytype, driver_count: u32, kind: []const u8) u32 {
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

pub fn enumerateRealSurfaceFormats(self: anytype, state: anytype) u64 {
    const count_address = guest_context.registers(state).rdx;
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
    if (guest_context.registers(state).rcx == 0) {
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
        if (span != 0 and state.guestMemory(guest_context.registers(state).rcx, span) == null) return vkErrorInitializationFailed();
        for (0..actual) |index| {
            state.write32(guest_context.registers(state).rcx + @as(u64, @intCast(index)) * 8, formats[index].format);
            state.write32(guest_context.registers(state).rcx + @as(u64, @intCast(index)) * 8 + 4, formats[index].color_space);
        }
    }
    state.write32(count_address, actual);
    self.vulkan_tiers.note(.surface_formats, .real);
    return @as(u32, @bitCast(if (actual < available) abi.INCOMPLETE else abi.SUCCESS));
}

pub fn enumerateRealSurfacePresentModes(self: anytype, state: anytype) u64 {
    const count_address = guest_context.registers(state).rdx;
    if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();
    const get_proc = self.real_vulkan.get_instance_proc_addr orelse return vkErrorInitializationFailed();
    const address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfacePresentModesKHR") orelse return vkErrorInitializationFailed();
    const get_modes: abi.PfnGetPhysicalDeviceSurfacePresentModesKHR = @ptrCast(@alignCast(address));
    var count: u32 = 0;
    var result = get_modes(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), self.real_vulkan.surface, &count, null);
    self.noteRealVulkanResult(result, "vkGetPhysicalDeviceSurfacePresentModesKHR");
    if (result != abi.SUCCESS and result != abi.INCOMPLETE) return @as(u32, @bitCast(result));
    const available = self.boundSurfaceEnumeration(count, "surface present modes");
    if (guest_context.registers(state).rcx == 0) {
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
        if (span != 0 and state.guestMemory(guest_context.registers(state).rcx, span) == null) return vkErrorInitializationFailed();
        for (0..actual) |index| state.write32(guest_context.registers(state).rcx + @as(u64, @intCast(index)) * 4, modes[index]);
    }
    state.write32(count_address, actual);
    self.vulkan_tiers.note(.surface_present_modes, .real);
    return @as(u32, @bitCast(if (actual < available) abi.INCOMPLETE else abi.SUCCESS));
}

pub fn writeRealSurfaceSupport(self: anytype, state: anytype) u64 {
    const output = guest_context.registers(state).rcx;
    if (output == 0 or state.guestMemory(output, 4) == null) return vkErrorInitializationFailed();
    const get_proc = self.real_vulkan.get_instance_proc_addr orelse return vkErrorInitializationFailed();
    const address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfaceSupportKHR") orelse return vkErrorInitializationFailed();
    const get_support: abi.PfnGetPhysicalDeviceSurfaceSupportKHR = @ptrCast(@alignCast(address));
    var supported: u32 = 0;
    const result = get_support(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), @truncate(guest_context.registers(state).rsi), self.real_vulkan.surface, &supported);
    self.noteRealVulkanResult(result, "vkGetPhysicalDeviceSurfaceSupportKHR");
    if (result == abi.SUCCESS) state.write32(output, supported);
    return @as(u32, @bitCast(result));
}

pub fn beginCommandBuffer(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const real = self.real_vulkan.realCommandBuffer(guest_context.registers(state).rdi) orelse return 0;
    const begin = self.real_vulkan.fn_ptrs.begin_command_buffer orelse return 0;
    var info: abi.CommandBufferBeginInfo = .{};
    var inheritance: abi.CommandBufferInheritanceInfo = .{};
    var inheritance_rendering: abi.CommandBufferInheritanceRenderingInfo = .{};
    var inheritance_color_formats: [8]u32 = undefined;
    if (guest_context.registers(state).rsi != 0 and state.guestMemoryConst(guest_context.registers(state).rsi, 24) != null) {
        var guest_info: abi.CommandBufferBeginInfo = undefined;
        if (!copyGuestValue(abi.CommandBufferBeginInfo, state, guest_context.registers(state).rsi, &guest_info) or
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
    if (result == abi.SUCCESS) {
        self.resetCommandTargets(guest_context.registers(state).rdi);
        if (self.native_texture_state) |native| native.resetCommand(guest_context.registers(state).rdi);
        self.fsiBeginRecording(guest_context.registers(state).rdi, real, info.flags, info.inheritance_info != null);
        self.vulkan_tiers.note(.command_recording, .real);
    }
    return @as(u32, @bitCast(result));
}

pub fn endCommandBuffer(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const guest = guest_context.registers(state).rdi;
    if (self.fsi_raster.moltenvk and self.fsi_raster.allocation_failed) return vkErrorOutOfHostMemory();
    if (self.fsi_raster.command(guest)) |command| {
        if (command.failed) return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    }
    if (self.fsiRecording(guest)) |recording| {
        if (recording.failed) {
            if (!recording.failure_reported) {
                recording.failure_reported = true;
                machoCapturePrint("macho-processor: VULKAN FSI GUARD: vkEndCommandBuffer refused guest=0x{x}; a required continuation boundary failed, so submitting a partially replayed FSI recording is unsafe\n", .{guest});
            }
            return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        }
    }
    const real = self.real_vulkan.realCommandBuffer(guest) orelse return 0;
    const end = self.real_vulkan.fn_ptrs.end_command_buffer orelse return 0;
    // A split FSI recording ends in its newest chunk.
    const result = end(self.fsiCommandTarget(guest, real));
    self.noteRealVulkanResult(result, "vkEndCommandBuffer");
    if (result == abi.SUCCESS) self.vulkan_tiers.note(.command_recording, .real);
    return @as(u32, @bitCast(result));
}

pub fn resetCommandBuffer(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const real = self.real_vulkan.realCommandBuffer(guest_context.registers(state).rdi) orelse return 0;
    const reset = self.real_vulkan.fn_ptrs.reset_command_buffer orelse return 0;
    const result = reset(real, @truncate(guest_context.registers(state).rsi));
    self.noteRealVulkanResult(result, "vkResetCommandBuffer");
    if (result == abi.SUCCESS) {
        self.resetCommandTargets(guest_context.registers(state).rdi);
        if (self.native_texture_state) |native| native.resetCommand(guest_context.registers(state).rdi);
        self.fsiForgetRecording(guest_context.registers(state).rdi);
        self.vulkan_tiers.note(.command_recording, .real);
    }
    return @as(u32, @bitCast(result));
}

pub fn resetCommandPool(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const pool = self.real_vulkan.realCommandPool(guest_context.registers(state).rsi) orelse return 0;
    const reset = self.real_vulkan.fn_ptrs.reset_command_pool orelse return 0;
    const result = reset(self.real_vulkan.device.?, pool, @truncate(guest_context.registers(state).rdx));
    self.noteRealVulkanResult(result, "vkResetCommandPool");
    if (result == abi.SUCCESS) {
        self.fsiResetCommandPool(guest_context.registers(state).rsi, false);
        self.vulkan_tiers.note(.command_recording, .real);
    }
    return @as(u32, @bitCast(result));
}

pub fn resetDescriptorPool(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const synthetic_pool = guest_context.registers(state).rsi;
    const pool = self.real_vulkan.realDescriptorPool(synthetic_pool) orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const reset = self.real_vulkan.fn_ptrs.reset_descriptor_pool orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const result = reset(self.real_vulkan.device orelse return vkErrorInitializationFailed(), pool, @truncate(guest_context.registers(state).rdx));
    if (result == abi.SUCCESS) {
        // vkResetDescriptorPool invalidates every set from the pool.  The
        // old path cleared only the optional provenance records, leaving
        // the real-handle map occupied forever until the process hit its
        // fixed capacity on a later allocation.
        _ = self.reclaimDescriptorSetsForPool(synthetic_pool, "reset");
        self.vulkan_tiers.note(.descriptor_set, .real);
    }
    return @as(u32, @bitCast(result));
}
