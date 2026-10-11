// Split implementation for Forwarder; wrappers keep the public state API stable.
const process = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = process.__ForwarderInternals;
const Forwarder = process.Forwarder;
const BridgeCapabilityScratch = __ForwarderInternals._BridgeCapabilityScratch;
const FeatureChainScratch = __ForwarderInternals._FeatureChainScratch;
const HostWindowDescribeResolver = __ForwarderInternals._HostWindowDescribeResolver;
const MAX_DEVICE_EXTENSION_NAMES = __ForwarderInternals._MAX_DEVICE_EXTENSION_NAMES;
const MAX_DEVICE_QUEUE_INFOS = __ForwarderInternals._MAX_DEVICE_QUEUE_INFOS;
const MAX_INSTANCE_EXTENSION_NAMES = __ForwarderInternals._MAX_INSTANCE_EXTENSION_NAMES;
const MAX_QUEUES_PER_CREATE_INFO = __ForwarderInternals._MAX_QUEUES_PER_CREATE_INFO;
const NativeSurfaceResult = __ForwarderInternals._NativeSurfaceResult;
const PfnVkCreateInstance = __ForwarderInternals._PfnVkCreateInstance;
const PfnVkCreateMetalSurfaceEXT = __ForwarderInternals._PfnVkCreateMetalSurfaceEXT;
const PfnVkDestroySurfaceKHR = __ForwarderInternals._PfnVkDestroySurfaceKHR;
const PfnVkGetInstanceProcAddr = __ForwarderInternals._PfnVkGetInstanceProcAddr;
const VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR = __ForwarderInternals._VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
const VK_STRUCTURE_TYPE_APPLICATION_INFO = __ForwarderInternals._VK_STRUCTURE_TYPE_APPLICATION_INFO;
const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = __ForwarderInternals._VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
const VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT = __ForwarderInternals._VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
const VkApplicationInfo = __ForwarderInternals._VkApplicationInfo;
const VkInstanceCreateInfo = __ForwarderInternals._VkInstanceCreateInfo;
const VkMetalSurfaceCreateInfoEXT = __ForwarderInternals._VkMetalSurfaceCreateInfoEXT;
const VulkanMemoryAllocation = __ForwarderInternals._VulkanMemoryAllocation;
const abi = __ForwarderInternals._abi;
const bridge_device_capabilities = __ForwarderInternals._bridge_device_capabilities;
const capture_plan = __ForwarderInternals._capture_plan;
const coreFeatureEnabled = __ForwarderInternals._coreFeatureEnabled;
const dlsym = __ForwarderInternals._dlsym;
const driver_identity = __ForwarderInternals._driver_identity;
const exportedOrNone = __ForwarderInternals._exportedOrNone;
const guest_context = __ForwarderInternals._guest_context;
const hostLoaderListsCaptureLayer = __ForwarderInternals._hostLoaderListsCaptureLayer;
const instance_extensions = __ForwarderInternals._instance_extensions;
const linkBridgeCapabilityChain = __ForwarderInternals._linkBridgeCapabilityChain;
const machoCapturePrint = __ForwarderInternals._machoCapturePrint;
const native_texture = __ForwarderInternals._native_texture;
const publishVulkanDispatchableHandle = __ForwarderInternals._publishVulkanDispatchableHandle;
const queue_api_gate = __ForwarderInternals._queue_api_gate;
const rangeContains = __ForwarderInternals._rangeContains;
const readGuestApplicationInfo = __ForwarderInternals._readGuestApplicationInfo;
const rosette_gpu = __ForwarderInternals._rosette_gpu;
const spliceBridgeCapabilityChain = __ForwarderInternals._spliceBridgeCapabilityChain;
const std = __ForwarderInternals._std;
const transport_timing = __ForwarderInternals._transport_timing;
const vkErrorInitializationFailed = __ForwarderInternals._vkErrorInitializationFailed;
const vkErrorInitializationFailedSigned = __ForwarderInternals._vkErrorInitializationFailedSigned;
const vkErrorOutOfHostMemorySigned = __ForwarderInternals._vkErrorOutOfHostMemorySigned;
const vulkan_capture = __ForwarderInternals._vulkan_capture;
const QueueApiWait = __ForwarderInternals._QueueApiWait;
const findVulkanMemoryRecord = Forwarder.findVulkanMemoryRecord;
const guestLibrary = Forwarder.guestLibrary;
const guestStackArg = Forwarder.guestStackArg;
const hostWindowFactsUnavailableReason = Forwarder.hostWindowFactsUnavailableReason;
const invoke = Forwarder.invoke;
const logFragmentShaderInterlockContract = Forwarder.logFragmentShaderInterlockContract;
const materializeNativeVulkanLibrary = Forwarder.materializeNativeVulkanLibrary;
const negotiateRosetteGpuBoundary = Forwarder.negotiateRosetteGpuBoundary;
const noteNativeFenceComplete = Forwarder.noteNativeFenceComplete;
const noteRealVulkanResult = Forwarder.noteRealVulkanResult;
const prepareDeviceFeatureChain = Forwarder.prepareDeviceFeatureChain;
const realDeviceLostResult = Forwarder.realDeviceLostResult;
const reportStarvedFence = Forwarder.reportStarvedFence;

pub fn waitForFences(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const count: u32 = @min(@as(u32, @truncate(guest_context.registers(state).rsi)), 256);
    if (count == 0 or guest_context.registers(state).rdx == 0) return abi.SUCCESS;
    if (state.guestMemoryConst(guest_context.registers(state).rdx, @as(u64, count) * 8) == null) return vkErrorInitializationFailed();
    const wait = self.real_vulkan.fn_ptrs.wait_for_fences orelse return abi.SUCCESS;
    var fences: [256]abi.Fence = [_]abi.Fence{0} ** 256;
    var synthetic_fences: [256]u64 = [_]u64{0} ** 256;
    for (0..count) |index| {
        const synthetic = state.read64(guest_context.registers(state).rdx + @as(u64, @intCast(index)) * 8);
        synthetic_fences[index] = synthetic;
        self.vulkan_fence_watch.notePoll(synthetic);
        fences[index] = self.real_vulkan.realFence(synthetic) orelse return vkErrorInitializationFailed();
    }
    self.reportStarvedFence();
    const NativeFenceWait = struct {
        function: abi.PfnWaitForFences,
        device: abi.Device,
        count: u32,
        fences: *const [256]abi.Fence,
        wait_all: u32,
        timeout: u64,

        fn invoke(call: @This()) abi.Result {
            return call.function(call.device, call.count, @ptrCast(call.fences), call.wait_all, call.timeout);
        }
    };
    const call = NativeFenceWait{
        .function = wait,
        .device = self.real_vulkan.device.?,
        .count = count,
        .fences = &fences,
        .wait_all = @truncate(guest_context.registers(state).rcx),
        .timeout = guest_context.registers(state).r8,
    };
    const result = if (comptime @hasDecl(@TypeOf(state.*), "withWindowsRuntimeLockReleasedForGpuFenceWait"))
        state.withWindowsRuntimeLockReleasedForGpuFenceWait(call, NativeFenceWait.invoke)
    else
        NativeFenceWait.invoke(call);
    self.noteRealVulkanResult(result, "vkWaitForFences");
    if (result == abi.SUCCESS) {
        for (0..count) |index| {
            const synthetic = synthetic_fences[index];
            self.vulkan_fence_watch.noteSignalled(synthetic);
            self.noteNativeFenceComplete(state, synthetic);
        }
    }
    return @as(u32, @bitCast(result));
}

pub fn resetFences(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const count: u32 = @min(@as(u32, @truncate(guest_context.registers(state).rsi)), 256);
    if (count == 0 or guest_context.registers(state).rdx == 0) return abi.SUCCESS;
    if (state.guestMemoryConst(guest_context.registers(state).rdx, @as(u64, count) * 8) == null) return vkErrorInitializationFailed();
    const reset = self.real_vulkan.fn_ptrs.reset_fences orelse return abi.SUCCESS;
    var fences: [256]abi.Fence = [_]abi.Fence{0} ** 256;
    for (0..count) |index| fences[index] = self.real_vulkan.realFence(state.read64(guest_context.registers(state).rdx + @as(u64, @intCast(index)) * 8)) orelse return vkErrorInitializationFailed();
    const result = reset(self.real_vulkan.device.?, count, &fences);
    self.noteRealVulkanResult(result, "vkResetFences");
    return @as(u32, @bitCast(result));
}

pub fn getFenceStatus(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    self.vulkan_fence_watch.notePoll(guest_context.registers(state).rsi);
    self.reportStarvedFence();
    const fence = self.real_vulkan.realFence(guest_context.registers(state).rsi) orelse return 0;
    const status = self.real_vulkan.fn_ptrs.get_fence_status orelse return 0;
    const result = status(self.real_vulkan.device.?, fence);
    self.noteRealVulkanResult(result, "vkGetFenceStatus");
    if (result == abi.SUCCESS) {
        self.vulkan_fence_watch.noteSignalled(guest_context.registers(state).rsi);
        self.noteNativeFenceComplete(state, guest_context.registers(state).rsi);
    }
    return @as(u32, @bitCast(result));
}

pub fn getQueryPoolResults(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |lost| return lost;
    const pool = self.real_vulkan.realQueryPool(guest_context.registers(state).rsi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    const get_results = self.real_vulkan.fn_ptrs.get_query_pool_results orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const data_size: u64 = guest_context.registers(state).r8;
    const guest_output = guest_context.registers(state).r9;
    if (guest_output == 0 or data_size == 0 or data_size > 64 * 1024) return @as(u32, @bitCast(abi.ERROR_OUT_OF_HOST_MEMORY));
    const guest_bytes = state.guestMemory(guest_output, data_size) orelse return vkErrorInitializationFailed();
    var data: [64 * 1024]u8 = undefined;
    const result = get_results(
        self.real_vulkan.device orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED)),
        pool,
        @truncate(guest_context.registers(state).rdx),
        @truncate(guest_context.registers(state).rcx),
        @intCast(data_size),
        @ptrCast(&data),
        guestStackArg(state, 0),
        @truncate(guestStackArg(state, 1)),
    );
    self.noteRealVulkanResult(result, "vkGetQueryPoolResults");
    if (result == abi.SUCCESS or result == abi.INCOMPLETE) @memcpy(guest_bytes, data[0..@as(usize, @intCast(data_size))]);
    return @as(u32, @bitCast(result));
}

pub fn resetQueryPool(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const pool = self.real_vulkan.realQueryPool(guest_context.registers(state).rsi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    const reset = self.real_vulkan.fn_ptrs.reset_query_pool orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    reset(self.real_vulkan.device orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED)), pool, @truncate(guest_context.registers(state).rdx), @truncate(guest_context.registers(state).rcx));
    return abi.SUCCESS;
}

pub fn lockVulkanQueueApi(self: anytype, state: anytype) ?queue_api_gate.Gate.Lease {
    if (self.vulkan_queue_api_gate.tryAcquire()) |lease| return lease;
    var context = QueueApiWait{ .gate = &self.vulkan_queue_api_gate };
    if (comptime @hasDecl(@TypeOf(state.*), "tryWithWindowsRuntimeLockReleasedForVulkanQueueWait")) {
        if (!state.tryWithWindowsRuntimeLockReleasedForVulkanQueueWait(&context, QueueApiWait.acquire)) {
            self.vulkan_queue_api_gate.noteWaitRefusal();
            machoCapturePrint("macho-processor: VULKAN QUEUE API GATE refused contended queue call because its runtime lock is pinned; no native queue operation was issued\n", .{});
            return null;
        }
    } else {
        QueueApiWait.acquire(&context);
    }
    return context.lease;
}

pub fn deviceWaitIdle(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const wait = self.real_vulkan.fn_ptrs.device_wait_idle orelse return 0;
    var queue_lease = self.lockVulkanQueueApi(state) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    defer queue_lease.release();
    const result = wait(self.real_vulkan.device orelse return 0);
    self.noteRealVulkanResult(result, "vkDeviceWaitIdle");
    if (result == abi.SUCCESS) self.downloadCoherentShadowsAfterCompletion(state);
    return @as(u32, @bitCast(result));
}

pub fn queueWaitIdle(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const wait = self.real_vulkan.fn_ptrs.queue_wait_idle orelse return 0;
    const queue = self.real_vulkan.realQueue(guest_context.registers(state).rdi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    var queue_lease = self.lockVulkanQueueApi(state) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    defer queue_lease.release();
    const result = wait(queue);
    self.noteRealVulkanResult(result, "vkQueueWaitIdle");
    // Another queue may still own writes to an unrelated shadow. Native
    // PE aliases need no CPU copy; do not claim all memory completed here.
    return @as(u32, @bitCast(result));
}

pub fn copyMappedBytes(self: anytype, state: anytype, memory: u64, offset: u64, requested_size: u64, to_host: bool) bool {
    const record = self.findVulkanMemoryRecord(memory) orelse return false;
    const host_ptr = record.host_mapped_ptr orelse return false;
    if (offset > record.requested_size) return false;
    const allocation_available = record.requested_size - offset;
    if (requested_size != abi.WHOLE_SIZE and requested_size > allocation_available) return false;
    if (offset < record.mapped_offset) return false;
    const host_offset = offset - record.mapped_offset;
    if (!rangeContains(record.mapped_offset, record.host_mapped_size, offset, 0)) return false;
    const available = record.host_mapped_size - host_offset;
    if (requested_size != abi.WHOLE_SIZE and requested_size > available) return false;
    const size = if (requested_size == abi.WHOLE_SIZE) @min(available, allocation_available) else requested_size;
    if (size == 0) return true;
    const length: usize = @intCast(size);
    const host_bytes: []u8 = @as([*]u8, @ptrCast(host_ptr))[host_offset..][0..length];
    // The PE path exposes these very same driver bytes. In particular,
    // never issue overlapping memcpy or apply a shadow-difference policy
    // to coherent native aliases.
    if (record.native_alias_base != 0) return true;
    const guest_address = std.math.add(u64, record.mapped_base, offset) catch return false;
    if (to_host) {
        const guest = state.guestMemoryConst(guest_address, size) orelse return false;
        @memcpy(host_bytes, guest[0..length]);
        if (record.shadow_baseline) |baseline| @memcpy(baseline[host_offset..][0..length], guest[0..length]);
        self.vulkan_shadow_upload_bytes +|= size;
    } else {
        const guest = state.guestMemory(guest_address, size) orelse return false;
        @memcpy(guest[0..length], host_bytes);
        if (record.shadow_baseline) |baseline| @memcpy(baseline[host_offset..][0..length], host_bytes);
    }
    return true;
}

pub fn publishCoherentShadow(self: anytype, state: anytype, record: *VulkanMemoryAllocation) bool {
    if (record.native_alias_base != 0) return true;
    if (record.memory_flags_known and (record.memory_flags & abi.MEMORY_PROPERTY_HOST_COHERENT_BIT) == 0) return true;
    const baseline = record.shadow_baseline orelse return self.copyMappedBytes(state, record.handle, record.mapped_offset, record.host_mapped_size, true);
    const address = std.math.add(u64, record.mapped_base, record.mapped_offset) catch return false;
    const guest = state.guestMemoryConst(address, record.host_mapped_size) orelse return false;
    if (guest.len < baseline.len or record.host_mapped_ptr == null) return false;
    if (std.mem.eql(u8, guest[0..baseline.len], baseline)) {
        self.vulkan_shadow_unchanged +|= 1;
        return true;
    }
    const host: []u8 = @as([*]u8, @ptrCast(record.host_mapped_ptr.?))[0..baseline.len];
    // Publish ONLY bytes changed by the guest. An unchanged shadow is not
    // an instruction to erase newer GPU-produced data in native memory.
    var start: usize = 0;
    while (start < baseline.len) : (start += 4096) {
        const end = @min(start + 4096, baseline.len);
        if (std.mem.eql(u8, guest[start..end], baseline[start..end])) continue;
        if (std.mem.eql(u8, host[start..end], baseline[start..end])) {
            // No GPU change in this chunk: vectorized copies are safe.
            @memcpy(host[start..end], guest[start..end]);
            @memcpy(baseline[start..end], guest[start..end]);
            self.vulkan_shadow_upload_bytes +|= end - start;
            continue;
        }
        for (guest[start..end], baseline[start..end], start..) |byte, previous, index| {
            if (byte == previous) continue;
            host[index] = byte;
            baseline[index] = byte;
            self.vulkan_shadow_upload_bytes +|= 1;
        }
    }
    return true;
}

pub fn downloadCoherentShadowsAfterCompletion(self: anytype, state: anytype) void {
    for (&self.vulkan_memory_records) |*record| {
        if (record.native_alias_base != 0) continue;
        if (!record.memory_flags_known or (record.memory_flags & abi.MEMORY_PROPERTY_HOST_COHERENT_BIT) == 0 or record.host_mapped_ptr == null) continue;
        const baseline = record.shadow_baseline orelse continue;
        const address = std.math.add(u64, record.mapped_base, record.mapped_offset) catch continue;
        const guest = state.guestMemory(address, record.host_mapped_size) orelse continue;
        if (guest.len < baseline.len) continue;
        const host = @as([*]const u8, @ptrCast(record.host_mapped_ptr.?))[0..baseline.len];
        // Three-way merge: GPU changes become CPU-visible after completion,
        // while new CPU writes for future submissions remain pending.
        for (baseline, 0..) |previous, index| {
            if (guest[index] != previous) continue;
            guest[index] = host[index];
            baseline[index] = host[index];
        }
    }
}

pub fn uploadMappedMemoryBeforeSubmit(self: anytype, state: anytype) bool {
    const started = transport_timing.nowNs();
    defer self.transport_cost.finish(.shadow_upload, started);
    for (&self.vulkan_memory_records) |*record| {
        if (record.native_alias_base != 0) continue;
        if (record.handle == 0 or record.host_mapped_ptr == null or record.host_mapped_size == 0) continue;
        // Noncoherent writes are published by explicit flush, not by a
        // submit implicitly flushing ranges the guest never flushed.
        if (record.memory_flags_known and (record.memory_flags & abi.MEMORY_PROPERTY_HOST_COHERENT_BIT) == 0) continue;
        if (!self.publishCoherentShadow(state, record)) {
            self.vulkan_shadow_upload_failures +|= 1;
            return false;
        }
        self.vulkan_shadow_uploads +|= 1;
    }
    if (vulkan_capture.active) self.flushMappingsForCapture();
    return true;
}

pub fn flushMappingsForCapture(self: anytype) void {
    const flush = self.real_vulkan.fn_ptrs.flush_mapped_memory_ranges orelse return;
    const device = self.real_vulkan.device orelse return;
    var ranges: [32]abi.MappedMemoryRange = undefined;
    var count: usize = 0;
    for (&self.vulkan_memory_records) |*record| {
        if (record.handle == 0 or record.host_mapped_ptr == null) continue;
        const real = self.real_vulkan.realMemory(record.handle) orelse continue;
        ranges[count] = .{ .memory = real, .offset = record.mapped_offset, .size = abi.WHOLE_SIZE };
        count += 1;
        if (count == ranges.len) {
            recordCaptureFlush(flush(device, @intCast(count), &ranges));
            count = 0;
        }
    }
    if (count != 0) recordCaptureFlush(flush(device, @intCast(count), &ranges));
}

pub fn recordCaptureFlush(result: anytype) void {
    vulkan_capture.flush_calls +|= 1;
    if (result != abi.SUCCESS) vulkan_capture.flush_failures +|= 1;
}

pub fn flushMappedMemoryRanges(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |lost| return lost;
    const count: u32 = @truncate(guest_context.registers(state).rsi);
    if (count > 32) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    if (count == 0) return abi.SUCCESS;
    if (guest_context.registers(state).rdx == 0 or state.guestMemoryConst(guest_context.registers(state).rdx, @as(u64, count) * @sizeOf(abi.MappedMemoryRange)) == null) return vkErrorInitializationFailed();
    var ranges: [32]abi.MappedMemoryRange = [_]abi.MappedMemoryRange{.{}} ** 32;
    for (0..count) |index| {
        const address = guest_context.registers(state).rdx + @as(u64, @intCast(index)) * @sizeOf(abi.MappedMemoryRange);
        const memory = state.read64(address + 16);
        const offset = state.read64(address + 24);
        const size = state.read64(address + 32);
        if (!self.copyMappedBytes(state, memory, offset, size, true)) return vkErrorInitializationFailed();
        ranges[index] = .{ .memory = self.real_vulkan.realMemory(memory) orelse return vkErrorInitializationFailed(), .offset = offset, .size = size };
    }
    const flush = self.real_vulkan.fn_ptrs.flush_mapped_memory_ranges orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const result = flush(self.real_vulkan.device.?, count, &ranges);
    self.noteRealVulkanResult(result, "vkFlushMappedMemoryRanges");
    return @as(u32, @bitCast(result));
}

pub fn invalidateMappedMemoryRanges(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |lost| return lost;
    const count: u32 = @truncate(guest_context.registers(state).rsi);
    if (count > 32) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    if (count == 0) return abi.SUCCESS;
    if (guest_context.registers(state).rdx == 0 or state.guestMemoryConst(guest_context.registers(state).rdx, @as(u64, count) * @sizeOf(abi.MappedMemoryRange)) == null) return vkErrorInitializationFailed();
    var ranges: [32]abi.MappedMemoryRange = [_]abi.MappedMemoryRange{.{}} ** 32;
    for (0..count) |index| {
        const address = guest_context.registers(state).rdx + @as(u64, @intCast(index)) * @sizeOf(abi.MappedMemoryRange);
        const memory = state.read64(address + 16);
        const offset = state.read64(address + 24);
        const size = state.read64(address + 32);
        ranges[index] = .{ .memory = self.real_vulkan.realMemory(memory) orelse return vkErrorInitializationFailed(), .offset = offset, .size = size };
    }
    const invalidate = self.real_vulkan.fn_ptrs.invalidate_mapped_memory_ranges orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const result = invalidate(self.real_vulkan.device.?, count, &ranges);
    self.noteRealVulkanResult(result, "vkInvalidateMappedMemoryRanges");
    if (result != abi.SUCCESS) return @as(u32, @bitCast(result));
    for (0..count) |index| {
        const address = guest_context.registers(state).rdx + @as(u64, @intCast(index)) * @sizeOf(abi.MappedMemoryRange);
        if (!self.copyMappedBytes(state, state.read64(address + 16), state.read64(address + 24), state.read64(address + 32), false)) return vkErrorInitializationFailed();
    }
    return 0;
}

pub fn unmapMemory(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const memory = guest_context.registers(state).rsi;
    if (self.findVulkanMemoryRecord(memory)) |record| {
        if (comptime @hasDecl(@TypeOf(state.*), "releaseNativeMemory")) {
            if (record.native_alias_base != 0) state.releaseNativeMemory(record.native_alias_base);
        }
        if (record.host_mapped_ptr != null) {
            if (!self.publishCoherentShadow(state, record)) {
                self.vulkan_shadow_upload_failures +|= 1;
                machoCapturePrint("macho-processor: SHADOW MEMORY FAILURE: operation=coherent_unmap memory=0x{x}; guest writes could not be published before native unmap\n", .{memory});
            } else if (record.native_alias_base == 0 and (!record.memory_flags_known or (record.memory_flags & abi.MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0)) self.vulkan_shadow_unmap_uploads +|= 1;
            if (self.real_vulkan.realMemory(memory)) |real_memory| {
                if (self.real_vulkan.fn_ptrs.unmap_memory) |unmap| unmap(self.real_vulkan.device.?, real_memory);
            }
        }
        record.releaseBaseline();
        record.native_alias_base = 0;
        // A Vulkan mapping is single-use until vkUnmapMemory. Clearing
        // every shadow-range field prevents a later map from returning a
        // stale guest pointer or from treating an old native range as
        // still valid.
        record.mapped_base = 0;
        record.mapped_size = 0;
        record.mapped_offset = 0;
        record.host_mapped_ptr = null;
        record.host_mapped_size = 0;
    }
    return 0;
}

pub fn ensureNativeVulkanInstance(self: anytype, library_token: u64) i32 {
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

pub fn createNativeMetalSurface(self: anytype, state: anytype, library_token: u64) NativeSurfaceResult {
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

pub fn destroyNativeSurface(self: anytype) void {
    if (self.native_vulkan_surface == 0 or self.native_vulkan_instance == null) return;
    const library = self.guestLibrary(self.native_vulkan_library_token) orelse return;
    const get_proc_address = dlsym(library, "vkGetInstanceProcAddr") orelse return;
    const get_proc: PfnVkGetInstanceProcAddr = @ptrCast(@alignCast(get_proc_address));
    const destroy_address = get_proc(self.native_vulkan_instance, "vkDestroySurfaceKHR") orelse return;
    const destroy_surface: PfnVkDestroySurfaceKHR = @ptrCast(@alignCast(destroy_address));
    destroy_surface(self.native_vulkan_instance, self.native_vulkan_surface, null);
    self.native_vulkan_surface = 0;
}

pub fn materializeVulkanLibraryForReal(self: anytype, library_token: u64) ?*anyopaque {
    return self.materializeNativeVulkanLibrary(library_token);
}

pub fn queryHostInstanceExtensions(self: anytype, library: *anyopaque) bool {
    return instance_extensions.queryHost(&self.real_vulkan, library);
}

pub fn hostInstanceExtensionAvailable(self: anytype, name: []const u8) bool {
    return instance_extensions.hostAvailable(&self.real_vulkan, name);
}

pub fn guestInstanceExtensionAlias(name: []const u8) ?[]const u8 {
    return instance_extensions.guestAlias(name);
}

pub fn guestInstanceExtensionAvailable(self: anytype, name: []const u8) bool {
    return instance_extensions.guestAvailable(&self.real_vulkan, name);
}

pub fn queryHostDeviceExtensions(self: anytype) bool {
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
            "macho-processor: refusing Vulkan device extension discovery: host reports {d} entries but the bridge table holds {d}; a partial capability view is unsafe\n",
            .{ count, capacity },
        );
        return false;
    }
    var requested: u32 = count;
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

pub fn negotiateBridgeCapabilities(self: anytype, scratch: *BridgeCapabilityScratch) void {
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

pub fn hostDeviceExtensions(self: anytype) []const abi.ExtensionProperties {
    if (!self.real_vulkan.host_device_extensions_known) return &.{};
    return self.real_vulkan.host_device_extensions[0..self.real_vulkan.host_device_extension_count];
}

pub fn hostDeviceExtensionAvailable(self: anytype, name: []const u8) bool {
    if (!self.real_vulkan.host_device_extensions_known) return true;
    for (self.hostDeviceExtensions()) |*property| {
        if (std.mem.eql(u8, property.name(), name)) return true;
    }
    return false;
}

pub fn enumerateInstanceExtensions(self: anytype, state: anytype, library_token: u64) u64 {
    const library = self.materializeVulkanLibraryForReal(library_token);
    if (library) |handle| _ = self.queryHostInstanceExtensions(handle);
    self.guest_instance_extension_enumeration_calls +|= 1;
    return instance_extensions.enumerateGuest(
        &self.real_vulkan,
        state,
        self.guest_instance_extension_enumeration_calls,
    );
}

pub fn logRealDriverIdentity(self: anytype, instance: abi.Instance, physical_device: abi.PhysicalDevice) void {
    const get_proc = self.real_vulkan.get_instance_proc_addr orelse return;
    const address = get_proc(instance, "vkGetPhysicalDeviceProperties2") orelse
        get_proc(instance, "vkGetPhysicalDeviceProperties2KHR") orelse {
        machoCapturePrint("macho-processor: VULKAN DRIVER: vkGetPhysicalDeviceProperties2 is unavailable; the driver cannot be named\n", .{});
        return;
    };
    const get_properties: abi.PfnGetPhysicalDeviceProperties2 = @ptrCast(@alignCast(address));
    var driver = abi.PhysicalDeviceDriverProperties{};
    var properties = abi.PhysicalDeviceProperties2{ .p_next = @ptrCast(&driver) };
    get_properties(physical_device, &properties);
    const api_version = std.mem.readInt(u32, properties.properties[0..4], .little);
    const identity = driver_identity.Identity.fromProperties(&driver, api_version);
    const driver_version = std.mem.readInt(u32, properties.properties[4..8], .little);
    const uniform_alignment = std.mem.readInt(u64, properties.properties[616..624], .little);
    if (self.native_texture_state == null) {
        if (native_texture.resolveControl(instance, identity.driver_id, driver_version, uniform_alignment)) |control| {
            const native = std.heap.c_allocator.create(native_texture.State) catch null;
            if (native) |owned| {
                owned.* = .{ .control = control, .bounds_stride = @intCast(@max(uniform_alignment, 16)) };
                self.native_texture_state = owned;
                machoCapturePrint("macho-processor: NATIVE METAL TEXTURES: enabled=true profile=MoltenVK-1.2.7-discrete route=MSL-in-Vulkan-command-stream formats=CTX1/DXT1/DXT3/DXT5 bounds=explicit-descriptor-ranges; ROSETTE_NATIVE_METAL_TEXTURES=0 retains the hardened SPIR-V route\n", .{});
            }
        } else machoCapturePrint("macho-processor: NATIVE METAL TEXTURES: enabled=false; profile/control/configuration unavailable or opted out; hardened SPIR-V route retained\n", .{});
    }
    self.fsi_raster.moltenvk = identity.isMoltenVK();
    machoCapturePrint(
        "macho-processor: VULKAN DRIVER: name={s} info={s} id={d}({s}) api={d}.{d}.{d} conformance={d}.{d}.{d}.{d} VULKAN_SDK={s} VK_ICD_FILENAMES={s} VK_DRIVER_FILES={s}; every Metal-backed driver reports the GPU as its adapter name, so this line is the record of which driver rendered\n",
        .{
            identity.name(),                    identity.info(),
            identity.driver_id,                 driver_identity.driverIdName(identity.driver_id) orelse "unnamed",
            identity.api.major,                 identity.api.minor,
            identity.api.patch,                 identity.conformance.major,
            identity.conformance.minor,         identity.conformance.subminor,
            identity.conformance.patch,         exportedOrNone("VULKAN_SDK"),
            exportedOrNone("VK_ICD_FILENAMES"), exportedOrNone("VK_DRIVER_FILES"),
        },
    );
}

pub fn ensureRealInstance(self: anytype, state: anytype, library_token: u64, create_info: u64) i32 {
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
    if (create_info == 0 or state.guestMemoryConst(create_info, @sizeOf(abi.InstanceCreateInfo)) == null) {
        machoCapturePrint(
            "macho-processor: ensureRealInstance: refusing unreadable/null VkInstanceCreateInfo at 0x{x}\n",
            .{create_info},
        );
        return abi.ERROR_INITIALIZATION_FAILED;
    }
    const create_info_type = state.read32(create_info);
    if (create_info_type != abi.STRUCTURE_TYPE_INSTANCE_CREATE_INFO) {
        machoCapturePrint("macho-processor: ensureRealInstance: unexpected VkInstanceCreateInfo sType={d}\n", .{create_info_type});
        return abi.ERROR_INITIALIZATION_FAILED;
    }
    const guest_instance_flags = state.read32(create_info + 16);
    if (guest_instance_flags & ~abi.INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR != 0) {
        machoCapturePrint(
            "macho-processor: ensureRealInstance: refusing unsupported VkInstanceCreateInfo flags=0x{x}\n",
            .{guest_instance_flags},
        );
        return abi.ERROR_INITIALIZATION_FAILED;
    }
    const guest_layer_count = state.read32(create_info + @offsetOf(abi.InstanceCreateInfo, "enabled_layer_count"));
    if (guest_layer_count != 0) {
        machoCapturePrint(
            "macho-processor: ensureRealInstance: refusing {d} guest instance layers; Rosette exposes no layers\n",
            .{guest_layer_count},
        );
        return abi.ERROR_LAYER_NOT_PRESENT;
    }
    const guest_extension_count = state.read32(create_info + @offsetOf(abi.InstanceCreateInfo, "enabled_extension_count"));
    if (guest_extension_count > MAX_INSTANCE_EXTENSION_NAMES) {
        machoCapturePrint(
            "macho-processor: ensureRealInstance: refusing {d} guest instance extensions; bridge capacity is {d} and truncation would change the instance contract\n",
            .{ guest_extension_count, MAX_INSTANCE_EXTENSION_NAMES },
        );
        return abi.ERROR_OUT_OF_HOST_MEMORY;
    }
    const guest_extension_array = state.read64(create_info + @offsetOf(abi.InstanceCreateInfo, "enabled_extension_names"));
    const guest_extension_bytes = std.math.mul(u64, guest_extension_count, 8) catch return abi.ERROR_INITIALIZATION_FAILED;
    if (guest_extension_count != 0 and
        (guest_extension_array == 0 or state.guestMemoryConst(guest_extension_array, guest_extension_bytes) == null))
    {
        machoCapturePrint(
            "macho-processor: ensureRealInstance: refusing unreadable pEnabledExtensionNames=0x{x} count={d}\n",
            .{ guest_extension_array, guest_extension_count },
        );
        return abi.ERROR_INITIALIZATION_FAILED;
    }
    const guest_p_next = state.read64(create_info + 8);
    if (guest_p_next != 0) {
        machoCapturePrint("macho-processor: ensureRealInstance: omitting unsupported instance pNext chain at 0x{x}; core instance creation remains safe\n", .{guest_p_next});
    }
    const app_info_addr = state.read64(create_info + @offsetOf(abi.InstanceCreateInfo, "application_info"));
    var app_info: abi.ApplicationInfo = .{};
    if (readGuestApplicationInfo(state, app_info_addr)) |guest_app_info| {
        app_info = guest_app_info;
        machoCapturePrint("macho-processor: ensureRealInstance: guest api_version=0x{x}\n", .{app_info.api_version});
    } else if (app_info_addr != 0) {
        machoCapturePrint(
            "macho-processor: ensureRealInstance: refusing unreadable VkApplicationInfo=0x{x}\n",
            .{app_info_addr},
        );
        return abi.ERROR_INITIALIZATION_FAILED;
    } else {
        machoCapturePrint("macho-processor: ensureRealInstance: no guest VkApplicationInfo, using defaults\n", .{});
    }
    if (!self.queryHostInstanceExtensions(library)) {
        machoCapturePrint(
            "macho-processor: ensureRealInstance: refusing instance creation because host extension discovery is incomplete\n",
            .{},
        );
        return abi.ERROR_INITIALIZATION_FAILED;
    }
    // Build a host-owned extension array.  Never pass the guest's string
    // pointers to the loader: they point into the translated address
    // space.  The two surface extensions are hard requirements for the
    // guest-backed path; portability and properties2 are optional because
    // recent Vulkan loaders promote or omit them.
    var extension_storage: [MAX_INSTANCE_EXTENSION_NAMES][256]u8 = [_][256]u8{[_]u8{0} ** 256} ** MAX_INSTANCE_EXTENSION_NAMES;
    var host_extension_names: [MAX_INSTANCE_EXTENSION_NAMES][*:0]const u8 = undefined;
    var extension_count: usize = 0;
    const add_extension = struct {
        fn add(
            owner: *Forwarder,
            name: []const u8,
            storage: *[MAX_INSTANCE_EXTENSION_NAMES][256]u8,
            names: *[MAX_INSTANCE_EXTENSION_NAMES][*:0]const u8,
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
    if (!add_extension(self, "VK_KHR_surface", &extension_storage, &host_extension_names, &extension_count) or
        !add_extension(self, "VK_EXT_metal_surface", &extension_storage, &host_extension_names, &extension_count))
    {
        return abi.ERROR_OUT_OF_HOST_MEMORY;
    }
    if (self.hostInstanceExtensionAvailable("VK_KHR_portability_enumeration")) {
        if (!add_extension(self, "VK_KHR_portability_enumeration", &extension_storage, &host_extension_names, &extension_count)) return abi.ERROR_OUT_OF_HOST_MEMORY;
    }
    if (self.hostInstanceExtensionAvailable("VK_KHR_get_physical_device_properties2")) {
        if (!add_extension(self, "VK_KHR_get_physical_device_properties2", &extension_storage, &host_extension_names, &extension_count)) return abi.ERROR_OUT_OF_HOST_MEMORY;
    }
    for (0..@as(usize, @intCast(guest_extension_count))) |index| {
        const extension_address = state.read64(guest_extension_array + @as(u64, @intCast(index)) * 8);
        const requested = state.guestCString(extension_address, 255) orelse {
            machoCapturePrint(
                "macho-processor: ensureRealInstance: refusing unreadable guest instance extension name[{d}] address=0x{x}\n",
                .{ index, extension_address },
            );
            return abi.ERROR_INITIALIZATION_FAILED;
        };
        const host_alias = guestInstanceExtensionAlias(requested);
        if (!self.guestInstanceExtensionAvailable(requested)) {
            machoCapturePrint("macho-processor: ensureRealInstance: guest instance extension unavailable on host, refusing {s}\n", .{requested});
            return abi.ERROR_EXTENSION_NOT_PRESENT;
        }
        // The guest-facing extension is a capability contract, not a
        // string that can be passed to the native loader.  Metal is
        // enabled below as the host implementation of the Windows
        // surface path; omitting the guest alias here keeps
        // vkCreateInstance valid on macOS.
        if (host_alias != null and !self.hostInstanceExtensionAvailable(requested)) {
            machoCapturePrint(
                "macho-processor: ensureRealInstance: virtualizing guest instance extension {s} through host {s}\n",
                .{ requested, host_alias.? },
            );
            continue;
        }
        if (!add_extension(self, requested, &extension_storage, &host_extension_names, &extension_count)) {
            machoCapturePrint(
                "macho-processor: ensureRealInstance: refusing guest instance extension {s}; host-owned extension storage is exhausted\n",
                .{requested},
            );
            return abi.ERROR_OUT_OF_HOST_MEMORY;
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
    // GFXReconstruct sits between this instance and the driver, so it
    // records exactly the stream Rosette hands MoltenVK.
    const capture_layers = [_][*:0]const u8{capture_plan.layer_name};
    var capture_layer_enabled = false;
    if (vulkan_capture.prepared) {
        vulkan_capture.loader_layer_listed = hostLoaderListsCaptureLayer(library);
        if (vulkan_capture.loader_layer_listed) {
            instance_create_info.enabled_layer_count = capture_layers.len;
            instance_create_info.enabled_layer_names = &capture_layers;
            capture_layer_enabled = true;
            vulkan_capture.instance_layer_requested = true;
        } else {
            vulkan_capture.state = .loader_layer_missing;
            machoCapturePrint("macho-processor: VULKAN CAPTURE: the native loader does not list {s} (VK_LAYER_PATH={s}; VK_ADD_LAYER_PATH={s}); capture disabled\n", .{ capture_plan.layer_name, exportedOrNone("VK_LAYER_PATH"), exportedOrNone("VK_ADD_LAYER_PATH") });
        }
    }
    machoCapturePrint("macho-processor: ensureRealInstance: calling vkCreateInstance: extensions={d} host_extensions_known={s} layers={d}\n", .{ extension_count, if (self.real_vulkan.host_instance_extensions_known) "YES" else "NO", instance_create_info.enabled_layer_count });
    // Call the real vkCreateInstance.
    const create_fn: abi.PfnCreateInstance = @ptrCast(@alignCast(dlsym(library, "vkCreateInstance") orelse {
        machoCapturePrint("macho-processor: ensureRealInstance: FAILED to find vkCreateInstance\n", .{});
        return vkErrorInitializationFailedSigned();
    }));
    var real_instance: abi.Instance = null;
    var result = create_fn(&instance_create_info, null, &real_instance);
    if (capture_layer_enabled and (result != 0 or real_instance == null)) {
        // A capture must never cost the run its device.
        vulkan_capture.instance_create_failures +|= 1;
        vulkan_capture.state = .instance_create_failed;
        machoCapturePrint("macho-processor: VULKAN CAPTURE: vkCreateInstance with {s} failed (VkResult={d}); retrying without it\n", .{ capture_plan.layer_name, result });
        capture_layer_enabled = false;
        instance_create_info.enabled_layer_count = 0;
        instance_create_info.enabled_layer_names = null;
        real_instance = null;
        result = create_fn(&instance_create_info, null, &real_instance);
    }
    if (capture_layer_enabled and result == 0 and real_instance != null) {
        vulkan_capture.active = true;
        vulkan_capture.state = .active;
        machoCapturePrint(
            "macho-processor: VULKAN CAPTURE: {s} enabled on the real instance; {s}. Every mapping is flushed before each submit for assisted tracking. Replay: gfxrecon-replay <file>; dump passes: tools/vulkan/capture_replay.py\n",
            .{
                capture_plan.layer_name,
                switch (vulkan_capture.plan.mode) {
                    .hotkey => "press the trigger key in game to capture one frame",
                    .frames => "the listed present frames are captured",
                    .off => "no capture",
                },
            },
        );
    }
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
    self.logRealDriverIdentity(real_instance, phys_devices[0]);
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

pub fn ensureRealDevice(self: anytype, state: anytype, library_token: u64, _: u64, device_create_info_addr: u64, output: u64) i32 {
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
    if (device_create_info_addr == 0 or
        state.guestMemoryConst(device_create_info_addr, @sizeOf(abi.DeviceCreateInfo)) == null)
    {
        machoCapturePrint(
            "macho-processor: ensureRealDevice: refusing unreadable/null VkDeviceCreateInfo at 0x{x}\n",
            .{device_create_info_addr},
        );
        return vkErrorInitializationFailedSigned();
    }
    if (state.read32(device_create_info_addr) != abi.STRUCTURE_TYPE_DEVICE_CREATE_INFO) {
        machoCapturePrint(
            "macho-processor: ensureRealDevice: refusing VkDeviceCreateInfo with sType={d}\n",
            .{state.read32(device_create_info_addr)},
        );
        return vkErrorInitializationFailedSigned();
    }
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
    var queue_create_infos: [MAX_DEVICE_QUEUE_INFOS]abi.DeviceQueueCreateInfo = undefined;
    var queue_count: u32 = 0;
    var priority_storage: [MAX_DEVICE_QUEUE_INFOS][MAX_QUEUES_PER_CREATE_INFO]f32 = [_][MAX_QUEUES_PER_CREATE_INFO]f32{[_]f32{1.0} ** MAX_QUEUES_PER_CREATE_INFO} ** MAX_DEVICE_QUEUE_INFOS;
    const guest_device_p_next = state.read64(device_create_info_addr + 8);
    const qci_count = state.read32(device_create_info_addr + device_create_info_queue_count_offset);
    const qci_addr = state.read64(device_create_info_addr + device_create_info_queue_infos_offset);
    machoCapturePrint("macho-processor: ensureRealDevice: VkDeviceCreateInfo qci_count={d} pQueueCreateInfos=0x{x}\n", .{ qci_count, qci_addr });
    if (qci_count == 0 or qci_count > MAX_DEVICE_QUEUE_INFOS or qci_addr == 0) {
        machoCapturePrint(
            "macho-processor: ensureRealDevice: refusing invalid queue-create array count={d} address=0x{x}\n",
            .{ qci_count, qci_addr },
        );
        return vkErrorInitializationFailedSigned();
    }
    const qci_size: u64 = @sizeOf(abi.DeviceQueueCreateInfo);
    const qci_bytes = std.math.mul(u64, qci_count, qci_size) catch return vkErrorInitializationFailedSigned();
    if (state.guestMemoryConst(qci_addr, qci_bytes) == null) {
        machoCapturePrint(
            "macho-processor: ensureRealDevice: refusing unreadable queue-create array address=0x{x} bytes={d}\n",
            .{ qci_addr, qci_bytes },
        );
        return vkErrorInitializationFailedSigned();
    }
    for (0..qci_count) |i| {
        const qci_offset = std.math.mul(u64, @as(u64, @intCast(i)), qci_size) catch return vkErrorInitializationFailedSigned();
        const qci = std.math.add(u64, qci_addr, qci_offset) catch return vkErrorInitializationFailedSigned();
        // VkDeviceQueueCreateInfo layout (64-bit):
        //   +0: sType (4) +8: pNext (8), +16: flags, +20: family, +24: count,
        //   +32: pQueuePriorities.
        const s_type = state.read32(qci);
        const p_next = state.read64(qci + 8);
        const flags = state.read32(qci + 16);
        const qf_idx = state.read32(qci + 20);
        const q_cnt = state.read32(qci + 24);
        machoCapturePrint("macho-processor: ensureRealDevice: QCI[{d}] family={d} count={d}\n", .{ i, qf_idx, q_cnt });
        if (s_type != abi.STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO or
            p_next != 0 or
            flags != 0 or
            qf_idx >= self.real_vulkan.queue_family_count or
            q_cnt == 0 or
            q_cnt > MAX_QUEUES_PER_CREATE_INFO or
            queue_count >= MAX_DEVICE_QUEUE_INFOS)
        {
            machoCapturePrint(
                "macho-processor: ensureRealDevice: refusing invalid QCI[{d}] sType={d} pNext=0x{x} family={d} count={d}\n",
                .{ i, s_type, p_next, qf_idx, q_cnt },
            );
            return vkErrorInitializationFailedSigned();
        }
        var duplicate = false;
        for (queue_create_infos[0..queue_count]) |existing| {
            if (existing.queue_family_index == qf_idx) duplicate = true;
        }
        if (duplicate) {
            machoCapturePrint("macho-processor: ensureRealDevice: refusing duplicate queue family={d}\n", .{qf_idx});
            return vkErrorInitializationFailedSigned();
        }
        const available = self.real_vulkan.queue_family_properties[qf_idx].queue_count;
        if (q_cnt > available) {
            machoCapturePrint(
                "macho-processor: ensureRealDevice: refusing QCI[{d}] family={d} requests {d} queues but host exposes {d}\n",
                .{ i, qf_idx, q_cnt, available },
            );
            return vkErrorInitializationFailedSigned();
        }
        const pri_addr = state.read64(qci + 32);
        const priority_bytes = std.math.mul(u64, q_cnt, 4) catch return vkErrorInitializationFailedSigned();
        if (pri_addr == 0 or state.guestMemoryConst(pri_addr, priority_bytes) == null) {
            machoCapturePrint(
                "macho-processor: ensureRealDevice: refusing QCI[{d}] without a readable priority array\n",
                .{i},
            );
            return vkErrorInitializationFailedSigned();
        }
        const destination_index = queue_count;
        queue_create_infos[destination_index] = .{
            .queue_family_index = qf_idx,
            .queue_count = q_cnt,
            .queue_priorities = &priority_storage[destination_index],
        };
        for (0..@as(usize, @intCast(q_cnt))) |priority_index| {
            const priority_offset = std.math.mul(u64, @as(u64, @intCast(priority_index)), 4) catch return vkErrorInitializationFailedSigned();
            const priority: f32 = @bitCast(state.read32(std.math.add(u64, pri_addr, priority_offset) catch return vkErrorInitializationFailedSigned()));
            if (!(priority >= 0.0 and priority <= 1.0)) {
                machoCapturePrint(
                    "macho-processor: ensureRealDevice: refusing QCI[{d}] priority[{d}] value={d}\n",
                    .{ i, priority_index, priority },
                );
                return vkErrorInitializationFailedSigned();
            }
            priority_storage[destination_index][priority_index] = priority;
        }
        queue_count += 1;
    }
    // Build the real VkDeviceCreateInfo.
    var real_device_info: abi.DeviceCreateInfo = .{};
    real_device_info.queue_create_info_count = queue_count;
    if (queue_count > 0) {
        real_device_info.queue_create_infos = &queue_create_infos;
    }
    var requested_features: [220]u8 = undefined;
    var guest_enabled_feature_count: usize = 0;
    var host_supported_feature_count: usize = 0;
    var host_feature_offset: usize = 0;
    while (host_feature_offset + 4 <= self.real_vulkan.physical_device_features.len) : (host_feature_offset += 4) {
        if (std.mem.readInt(u32, self.real_vulkan.physical_device_features[host_feature_offset..][0..4], .little) != 0) {
            host_supported_feature_count += 1;
        }
    }
    const host_tessellation_shader = coreFeatureEnabled(
        &self.real_vulkan.physical_device_features,
        abi.PHYSICAL_DEVICE_FEATURES_TESSELLATION_SHADER_OFFSET,
    );
    var guest_tessellation_shader_enabled = false;
    const guest_features_addr = state.read64(device_create_info_addr + device_create_info_features_offset);
    if (guest_features_addr != 0) {
        const guest_features = state.guestMemoryConst(guest_features_addr, requested_features.len) orelse {
            machoCapturePrint(
                "macho-processor: ensureRealDevice: refusing unreadable pEnabledFeatures=0x{x}\n",
                .{guest_features_addr},
            );
            return vkErrorInitializationFailedSigned();
        };
        @memcpy(&requested_features, guest_features);
        guest_tessellation_shader_enabled = coreFeatureEnabled(
            &requested_features,
            abi.PHYSICAL_DEVICE_FEATURES_TESSELLATION_SHADER_OFFSET,
        );
        var feature_offset: usize = 0;
        while (feature_offset + 4 <= requested_features.len) : (feature_offset += 4) {
            const requested = std.mem.readInt(u32, requested_features[feature_offset..][0..4], .little);
            const supported = std.mem.readInt(u32, self.real_vulkan.physical_device_features[feature_offset..][0..4], .little);
            if (requested != 0 and supported == 0) {
                machoCapturePrint(
                    "macho-processor: ensureRealDevice: requested unsupported core feature at byte_offset={d}\n",
                    .{feature_offset},
                );
                return abi.ERROR_FEATURE_NOT_PRESENT;
            }
            std.mem.writeInt(u32, requested_features[feature_offset..][0..4], if (requested != 0) 1 else 0, .little);
        }
        real_device_info.enabled_features = &requested_features;
        var enabled_feature_count: usize = 0;
        var offset: usize = 0;
        while (offset + 4 <= requested_features.len) : (offset += 4) {
            if (std.mem.readInt(u32, requested_features[offset..][0..4], .little) != 0) enabled_feature_count += 1;
        }
        guest_enabled_feature_count = enabled_feature_count;
        machoCapturePrint(
            "macho-processor: ensureRealDevice: guest VkPhysicalDeviceFeatures at 0x{x}: {d} enabled and verified against the host\n",
            .{ guest_features_addr, enabled_feature_count },
        );
    }
    var feature_chain: FeatureChainScratch = .{};
    if (guest_device_p_next != 0) {
        if (!self.prepareDeviceFeatureChain(state, guest_device_p_next, &feature_chain)) {
            _ = self.queryHostDeviceExtensions();
            self.logFragmentShaderInterlockContract(state, guest_device_p_next, null, "feature_chain_refused");
            machoCapturePrint("macho-processor: ensureRealDevice: unsupported or unreadable device feature pNext chain at 0x{x}\n", .{guest_device_p_next});
            return abi.ERROR_FEATURE_NOT_PRESENT;
        }
        if (feature_chain.count != 0) real_device_info.p_next = @ptrCast(&feature_chain.nodes[feature_chain.order[0]]);
    }
    machoCapturePrint(
        "macho-processor: Vulkan feature contract: core_host_supported={d}/{d} guest_core_enabled={d} tessellation_shader(host/guest)={}/{} pNext_nodes={d} verified=YES unsupported_requested=NO; tessellationShader is VkPhysicalDeviceFeatures byte offset 20 and every enabled guest bit was checked against the native physical-device feature set before vkCreateDevice\n",
        .{ host_supported_feature_count, requested_features.len / 4, guest_enabled_feature_count, host_tessellation_shader, guest_tessellation_shader_enabled, feature_chain.count },
    );
    // Request only extensions the host actually exposes.  Passing a guest
    // extension-name pointer through is unsafe for the same reason as a
    // guest array pointer anywhere else in Vulkan: it is an address in the
    // translated address space, not a host C string.
    // Use the same cached device extension table the guest enumeration
    // answers from.  A short local probe here silently disables the
    // availability filter on any driver with a longer list than the probe
    // buffer, which is exactly when the filter matters.
    if (!self.queryHostDeviceExtensions()) {
        machoCapturePrint(
            "macho-processor: ensureRealDevice: refusing device creation because host extension discovery is incomplete\n",
            .{},
        );
        return vkErrorInitializationFailedSigned();
    }
    const host_extensions_known = true;
    const available_extensions = self.hostDeviceExtensions();
    var extension_storage: [MAX_DEVICE_EXTENSION_NAMES][256]u8 = [_][256]u8{[_]u8{0} ** 256} ** MAX_DEVICE_EXTENSION_NAMES;
    var device_extension_names: [MAX_DEVICE_EXTENSION_NAMES][*:0]const u8 = undefined;
    var extension_count: usize = 0;
    const add_extension = struct {
        fn add(
            name: []const u8,
            known: bool,
            available: []const abi.ExtensionProperties,
            storage: *[MAX_DEVICE_EXTENSION_NAMES][256]u8,
            names: *[MAX_DEVICE_EXTENSION_NAMES][*:0]const u8,
            count: *usize,
        ) bool {
            if (name.len == 0 or count.* >= names.len or name.len >= storage[0].len) return false;
            for (names[0..count.*]) |existing| if (std.mem.eql(u8, std.mem.sliceTo(existing, 0), name)) return true;
            if (known) {
                var found = false;
                for (available) |property| {
                    if (std.mem.eql(u8, property.name(), name)) found = true;
                }
                if (!found) return false;
            }
            @memset(&storage[count.*], 0);
            @memcpy(storage[count.*][0..name.len], name);
            names[count.*] = @ptrCast(&storage[count.*]);
            count.* += 1;
            return true;
        }
    }.add;
    _ = add_extension("VK_KHR_swapchain", host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count);
    _ = add_extension("VK_KHR_portability_subset", host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count);
    _ = add_extension("VK_KHR_maintenance1", host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count);
    const requested_extension_count = state.read32(device_create_info_addr + device_create_info_extension_count_offset);
    if (requested_extension_count > @as(u32, @intCast(device_extension_names.len))) {
        machoCapturePrint(
            "macho-processor: ensureRealDevice: refusing {d} guest device extensions; bridge capacity is {d} and truncation would change the device contract\n",
            .{ requested_extension_count, device_extension_names.len },
        );
        return vkErrorOutOfHostMemorySigned();
    }
    const guest_extension_array = state.read64(device_create_info_addr + device_create_info_extension_names_offset);
    const guest_extension_bytes = std.math.mul(u64, requested_extension_count, 8) catch return vkErrorInitializationFailedSigned();
    if (requested_extension_count != 0 and
        (guest_extension_array == 0 or state.guestMemoryConst(guest_extension_array, guest_extension_bytes) == null))
    {
        machoCapturePrint(
            "macho-processor: ensureRealDevice: refusing unreadable pEnabledExtensionNames=0x{x} count={d}\n",
            .{ guest_extension_array, requested_extension_count },
        );
        return vkErrorInitializationFailedSigned();
    }
    var guest_fsi_extension_requested = false;
    for (0..@as(usize, @intCast(requested_extension_count))) |index| {
        const string_address = state.read64(guest_extension_array + @as(u64, @intCast(index)) * 8);
        const string = state.guestCString(string_address, 255) orelse {
            machoCapturePrint(
                "macho-processor: ensureRealDevice: refusing unreadable guest device extension name[{d}] address=0x{x}\n",
                .{ index, string_address },
            );
            return vkErrorInitializationFailedSigned();
        };
        if (std.mem.eql(u8, string, "VK_EXT_fragment_shader_interlock")) {
            guest_fsi_extension_requested = true;
        }
        if (host_extensions_known and !self.hostDeviceExtensionAvailable(string)) {
            if (std.mem.eql(u8, string, "VK_EXT_fragment_shader_interlock")) {
                self.logFragmentShaderInterlockContract(state, guest_device_p_next, true, "guest_extension_unavailable");
            }
            machoCapturePrint("macho-processor: ensureRealDevice: guest device extension unavailable on host, refusing {s}\n", .{string});
            return abi.ERROR_EXTENSION_NOT_PRESENT;
        }
        if (!add_extension(string, host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count)) {
            machoCapturePrint(
                "macho-processor: ensureRealDevice: refusing guest device extension {s}; host-owned extension storage could not represent it\n",
                .{string},
            );
            return vkErrorOutOfHostMemorySigned();
        }
    }
    self.logFragmentShaderInterlockContract(state, guest_device_p_next, guest_fsi_extension_requested, "device_create");
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
            if (!add_extension(capability.extension, host_extensions_known, available_extensions, &extension_storage, &device_extension_names, &extension_count)) {
                machoCapturePrint(
                    "macho-processor: ensureRealDevice: refusing bridge capability {s}; host-owned extension storage is exhausted\n",
                    .{capability.extension},
                );
                return vkErrorOutOfHostMemorySigned();
            }
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
    var bridge_extensions_enabled = extension_count != guest_extension_boundary;
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
        bridge_extensions_enabled = false;
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
    self.real_vulkan.sync2_enabled = bridge_extensions_enabled and bridge_capabilities.admitted[0];
    self.real_vulkan.dynamic_rendering_enabled = bridge_extensions_enabled and bridge_capabilities.admitted[1];
    self.real_vulkan.extended_dynamic_state_enabled = bridge_extensions_enabled and bridge_capabilities.admitted[2];
    self.real_vulkan.extended_dynamic_state2_enabled = bridge_extensions_enabled and bridge_capabilities.admitted[3];
    self.real_vulkan.push_descriptor_enabled = bridge_extensions_enabled and bridge_capabilities.admitted[4];
    self.real_vulkan.conditional_rendering_enabled = bridge_extensions_enabled and bridge_capabilities.admitted[5];
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
            self.real_vulkan.graphics_queue_family_index = queue_create_infos[0].queue_family_index;
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
    // This is the first point at which a guest-driven Vulkan execution
    // contract can be authoritative. The handshake uses the native
    // device/function-pointer/memory facts above and terminates on any
    // missing foundational capability instead of falling back to a
    // synthetic execution path.
    self.negotiateRosetteGpuBoundary("guest_device_ready");
    return 0;
}

pub fn ensureRealDeviceFnPtrs(self: anytype, _: u64) void {
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
        const retained = @min(absent_len, self.vulkan_absent_names.len);
        @memcpy(self.vulkan_absent_names[0..retained], absent_names[0..retained]);
        self.vulkan_absent_names_len = retained;
        self.vulkan_absent_count = absent_count;
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

pub fn refuseVulkanCall(
    self: anytype,
    entry_point: []const u8,
    why: []const u8,
    result: abi.Result,
    args: [3]u64,
) u64 {
    const first = self.vulkan_refusals.note(entry_point, why, result, args);
    if (first) {
        machoCapturePrint(
            "macho-processor: Vulkan call refused by Rosetta: {s} reason={s} result={d} args=0x{x},0x{x},0x{x}; the native driver never saw this call\n",
            .{ entry_point, why, result, args[0], args[1], args[2] },
        );
    }
    return @as(u32, @bitCast(result));
}

pub fn describeHostWindow() ?rosette_gpu.WindowGeometry {
    HostWindowDescribeResolver.resolve();
    const describe = HostWindowDescribeResolver.describe orelse return null;
    var geometry: rosette_gpu.WindowGeometry = .{};
    if (describe(&geometry) == 0) return null;
    return geometry;
}

pub fn screenExtentDimension(value: f64) u32 {
    if (!(value > 0.0)) return 0;
    if (value >= @as(f64, @floatFromInt(std.math.maxInt(u32)))) return std.math.maxInt(u32);
    return @intFromFloat(value);
}

pub fn screenValidityPixelEvidence(evidence: rosette_gpu.PresentPixelEvidence) rosette_gpu.ScreenValidityPixelEvidence {
    return switch (evidence) {
        .unprobed => .unknown,
        .unavailable => .unavailable,
        .solid_clear => .solid_clear,
        .uniform_colour => .uniform_colour,
        .nonzero_static => .nonzero_static,
        .changing => .changing,
    };
}

pub fn screenValiditySnapshot(
    self: anytype,
    window: ?rosette_gpu.WindowGeometry,
) rosette_gpu.ScreenValiditySnapshot {
    const chain = &self.present_chain;
    var guest_presents: u64 = 0;
    var guest_acquires: u64 = 0;
    var guest_present_failures: u64 = 0;
    var presents_with_target: u64 = 0;
    var presents_with_content: u64 = 0;
    var presents_clear_only: u64 = 0;
    var presents_without_target: u64 = 0;
    var presents_without_write: u64 = 0;
    var presents_with_sampled_source: u64 = 0;
    var presents_with_propagated_transfer: u64 = 0;
    var presents_with_buffer_upload: u64 = 0;
    var presents_with_unresolved_source: u64 = 0;
    var expected_width: u32 = 0;
    var expected_height: u32 = 0;
    var selected_guest_presents: u64 = 0;
    var latest_pixel_frame: u64 = 0;
    var latest_pixel = rosette_gpu.ScreenValidityPixelEvidence.unknown;
    var latest_pixel_uniform: u32 = 0;
    var latest_pixel_hash: u64 = 0;
    var latest_pixel_image: u64 = 0;
    var latest_pixel_was_content = false;
    var latest_content_pixel_frame: u64 = 0;
    var latest_content_pixel = rosette_gpu.ScreenValidityPixelEvidence.unknown;
    var latest_content_pixel_uniform: u32 = 0;
    var latest_content_pixel_hash: u64 = 0;
    var latest_content_pixel_image: u64 = 0;

    // Rosette's diagnostic presenter can have its own retired history.
    // Only guest-owned records are allowed to satisfy the guest screen
    // contract; otherwise a diagnostic frame could make a missing guest
    // write look valid.
    for (chain.swapchains[0..chain.swapchain_count]) |record| {
        if (record.owner != .guest) continue;
        guest_presents +|= record.presents;
        guest_acquires +|= record.acquires;
        guest_present_failures +|= record.present_failures;
        presents_with_target +|= record.presents_with_target;
        presents_with_content +|= record.presents_with_content;
        presents_clear_only +|= record.presents_clear_only;
        presents_without_target +|= record.presents_without_target;
        presents_without_write +|= record.presents_without_write;
        presents_with_sampled_source +|= record.presents_with_sampled_source;
        presents_with_propagated_transfer +|= record.presents_with_propagated_transfer;
        presents_with_buffer_upload +|= record.presents_with_buffer_upload;
        presents_with_unresolved_source +|= record.presents_with_unresolved_source;
        if (record.width != 0 and record.height != 0 and
            (expected_width == 0 or record.presents >= selected_guest_presents))
        {
            expected_width = record.width;
            expected_height = record.height;
            selected_guest_presents = record.presents;
        }
        if (record.pixel_probe_frame >= latest_pixel_frame and record.pixel_probe_frame != 0) {
            latest_pixel_frame = record.pixel_probe_frame;
            latest_pixel = screenValidityPixelEvidence(record.pixel_evidence);
            latest_pixel_uniform = record.pixel_uniform_value;
            latest_pixel_hash = record.pixel_hash;
            latest_pixel_image = record.pixel_probe_image;
            latest_pixel_was_content = record.pixel_probe_write_kind == .content;
        }
        if (record.pixel_content_probe_frame >= latest_content_pixel_frame and record.pixel_content_probe_frame != 0) {
            latest_content_pixel_frame = record.pixel_content_probe_frame;
            latest_content_pixel = screenValidityPixelEvidence(record.pixel_content_probe_evidence);
            latest_content_pixel_uniform = record.pixel_content_probe_uniform_value;
            latest_content_pixel_hash = record.pixel_content_probe_hash;
            latest_content_pixel_image = record.pixel_content_probe_image;
        }
    }
    // A later periodic sample can legitimately land on a clear-only
    // image. Once a title has presented content, the screen verdict must
    // stay anchored to the newest sample that was captured from a
    // content-marked acquired image, not silently regress to that clear.
    if (latest_content_pixel_frame != 0 and presents_with_content != 0) {
        latest_pixel_frame = latest_content_pixel_frame;
        latest_pixel = latest_content_pixel;
        latest_pixel_uniform = latest_content_pixel_uniform;
        latest_pixel_hash = latest_content_pixel_hash;
        latest_pixel_image = latest_content_pixel_image;
        latest_pixel_was_content = true;
    }
    if (expected_width == 0 or expected_height == 0) {
        expected_width = self.graphics_extent_requested_width;
        expected_height = self.graphics_extent_requested_height;
    }

    var snapshot = rosette_gpu.ScreenValiditySnapshot{
        .step = self.guest_progress_steps,
        .guest_presents = guest_presents,
        .guest_acquires = guest_acquires,
        .guest_present_failures = guest_present_failures,
        .presents_with_target = presents_with_target,
        .presents_with_content = presents_with_content,
        .presents_clear_only = presents_clear_only,
        .presents_without_target = presents_without_target,
        .presents_without_write = presents_without_write,
        .presents_with_sampled_source = presents_with_sampled_source,
        .presents_with_propagated_transfer = presents_with_propagated_transfer,
        .presents_with_buffer_upload = presents_with_buffer_upload,
        .presents_with_unresolved_source = presents_with_unresolved_source,
        .content_commands = self.vulkan_command_content_marks,
        .draw_commands = self.vulkan_command_draw_calls,
        .dispatch_commands = self.vulkan_command_dispatch_calls,
        .target_resolved = self.target_attribution_events,
        .target_offscreen = self.target_offscreen_events,
        .target_unknown = self.target_unknown_events,
        .target_overflow = self.target_overflow_events,
        .descriptor_image_infos = self.vulkan_descriptor_image_infos_observed,
        .descriptor_sampled_images = self.vulkan_descriptor_sampled_images_recorded,
        .descriptor_unknown_image_views = self.vulkan_descriptor_unknown_image_views,
        .descriptor_sets_unknown = self.vulkan_descriptor_sets_unknown,
        .resource_transfer_events = chain.resource_transfer_events,
        .resource_buffer_to_image = chain.resource_transfer_kind_counts[@intFromEnum(rosette_gpu.PresentTransferKind.buffer_to_image)],
        .resource_transfer_sources_resolved = chain.resource_transfer_resolved,
        .resource_transfer_sources_unresolved = chain.resource_transfer_unresolved,
        .resource_graph_overflow = chain.resource_image_overflow,
        .native_present_requests = self.vulkan_real_presents,
        .native_present_completions = self.vulkan_real_present_completions,
        .native_queue_submits = self.vulkan_real_queue_submits,
        .expected_width = expected_width,
        .expected_height = expected_height,
        .extent_contract_failed = self.graphics_extent_contract_failed or self.graphics_extent_contract_failures != 0,
        .drawable_owner = switch (self.drawable_owner) {
            .window_bridge => .window_bridge,
            .native_presenter => .native_presenter,
            .guest_swapchain => .guest_swapchain,
        },
        .live_swapchains = @intCast(chain.liveSwapchains()),
        .contested_layer = chain.contestedLayer() != null,
        .pixel_probe_attempts = self.pixel_probe.attempts,
        .pixel_probe_successes = self.pixel_probe.successes,
        .pixel_probe_failures = self.pixel_probe.failures,
        .pixel_evidence = latest_pixel,
        .pixel_uniform_value = latest_pixel_uniform,
        .pixel_hash = latest_pixel_hash,
        .pixel_sample_frame = latest_pixel_frame,
        .pixel_sample_image = latest_pixel_image,
        .pixel_sample_was_content = latest_pixel_was_content,
    };

    if (window) |facts| {
        const user_visible = facts.window_visible != 0 and facts.window_on_screen != 0 and
            facts.window_miniaturized == 0 and facts.view_hidden_or_ancestor == 0 and
            facts.layer_hidden == 0 and facts.drawable_width > 0 and facts.drawable_height > 0;
        snapshot.drawable_width = screenExtentDimension(facts.drawable_width);
        snapshot.drawable_height = screenExtentDimension(facts.drawable_height);
        snapshot.layer_width = screenExtentDimension(facts.layer_width);
        snapshot.layer_height = screenExtentDimension(facts.layer_height);
        snapshot.extent_observed = snapshot.drawable_width != 0 and snapshot.drawable_height != 0 and
            snapshot.layer_width != 0 and snapshot.layer_height != 0;
        snapshot.window_available = true;
        snapshot.window_chain_intact = facts.firstBrokenLink() == null;
        snapshot.window_user_visible = user_visible;
        snapshot.window_visible_fraction_percent = facts.visibleFractionPercent();
        snapshot.window_break_reason = facts.firstBrokenLink() orelse "";
    } else {
        snapshot.window_break_reason = hostWindowFactsUnavailableReason();
    }
    return snapshot;
}

pub fn observeScreenValidity(
    self: anytype,
    window: ?rosette_gpu.WindowGeometry,
) rosette_gpu.ScreenValidityEvaluation {
    return self.screen_validity.observe(self.screenValiditySnapshot(window));
}
