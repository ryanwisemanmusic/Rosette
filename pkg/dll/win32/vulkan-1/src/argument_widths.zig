//! Generated from Vulkan-Headers 1.4.313 registry/vk.xml.
//! Regenerate/check with tools/generate_vulkan_argument_widths.py.
//! These are ABI facts, not permission to advertise native support.
const std = @import("std");

pub const Signature = struct {
    argument_count: u8,
    scalar32_mask: u32,

    /// Windows' eight-byte argument slots do not widen their declared types.
    /// Preserve full pointers, handles, sizes and timeouts; only DWORD scalar
    /// values discard their unspecified upper half (including signed bits).
    pub fn normalize(self: Signature, index: usize, raw: u64) u64 {
        if (index < self.argument_count and
            self.scalar32_mask & (@as(u32, 1) << @as(u5, @intCast(index))) != 0)
        {
            return @as(u32, @truncate(raw));
        }
        return raw;
    }
};

pub const signatures = std.StaticStringMap(Signature).initComptime(.{
    .{ "vkAcquireNextImageKHR", Signature{ .argument_count = 6, .scalar32_mask = 0x0 } },
    .{ "vkAllocateCommandBuffers", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkAllocateDescriptorSets", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkAllocateMemory", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkBeginCommandBuffer", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkBindBufferMemory", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkBindBufferMemory2", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkBindBufferMemory2KHR", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkBindImageMemory", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkBindImageMemory2", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkBindImageMemory2KHR", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkCmdBeginConditionalRenderingEXT", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkCmdBeginQuery", Signature{ .argument_count = 4, .scalar32_mask = 0xc } },
    .{ "vkCmdBeginRenderPass", Signature{ .argument_count = 3, .scalar32_mask = 0x4 } },
    .{ "vkCmdBeginRenderPass2", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkCmdBeginRenderPass2KHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkCmdBeginRendering", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkCmdBeginRenderingKHR", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkCmdBindDescriptorSets", Signature{ .argument_count = 8, .scalar32_mask = 0x5a } },
    .{ "vkCmdBindIndexBuffer", Signature{ .argument_count = 4, .scalar32_mask = 0x8 } },
    .{ "vkCmdBindPipeline", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkCmdBindVertexBuffers", Signature{ .argument_count = 5, .scalar32_mask = 0x6 } },
    .{ "vkCmdBlitImage", Signature{ .argument_count = 8, .scalar32_mask = 0xb4 } },
    .{ "vkCmdClearAttachments", Signature{ .argument_count = 5, .scalar32_mask = 0xa } },
    .{ "vkCmdClearColorImage", Signature{ .argument_count = 6, .scalar32_mask = 0x14 } },
    .{ "vkCmdClearDepthStencilImage", Signature{ .argument_count = 6, .scalar32_mask = 0x14 } },
    .{ "vkCmdCopyBuffer", Signature{ .argument_count = 5, .scalar32_mask = 0x8 } },
    .{ "vkCmdCopyBufferToImage", Signature{ .argument_count = 6, .scalar32_mask = 0x18 } },
    .{ "vkCmdCopyImage", Signature{ .argument_count = 7, .scalar32_mask = 0x34 } },
    .{ "vkCmdCopyImageToBuffer", Signature{ .argument_count = 6, .scalar32_mask = 0x14 } },
    .{ "vkCmdCopyQueryPoolResults", Signature{ .argument_count = 8, .scalar32_mask = 0x8c } },
    .{ "vkCmdDispatch", Signature{ .argument_count = 4, .scalar32_mask = 0xe } },
    .{ "vkCmdDispatchBase", Signature{ .argument_count = 7, .scalar32_mask = 0x7e } },
    .{ "vkCmdDispatchIndirect", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkCmdDraw", Signature{ .argument_count = 5, .scalar32_mask = 0x1e } },
    .{ "vkCmdDrawIndexed", Signature{ .argument_count = 6, .scalar32_mask = 0x3e } },
    .{ "vkCmdDrawIndexedIndirect", Signature{ .argument_count = 5, .scalar32_mask = 0x18 } },
    .{ "vkCmdDrawIndexedIndirectCount", Signature{ .argument_count = 7, .scalar32_mask = 0x60 } },
    .{ "vkCmdDrawIndirect", Signature{ .argument_count = 5, .scalar32_mask = 0x18 } },
    .{ "vkCmdDrawIndirectCount", Signature{ .argument_count = 7, .scalar32_mask = 0x60 } },
    .{ "vkCmdEndConditionalRenderingEXT", Signature{ .argument_count = 1, .scalar32_mask = 0x0 } },
    .{ "vkCmdEndQuery", Signature{ .argument_count = 3, .scalar32_mask = 0x4 } },
    .{ "vkCmdEndRenderPass", Signature{ .argument_count = 1, .scalar32_mask = 0x0 } },
    .{ "vkCmdEndRenderPass2", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkCmdEndRenderPass2KHR", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkCmdEndRendering", Signature{ .argument_count = 1, .scalar32_mask = 0x0 } },
    .{ "vkCmdEndRenderingKHR", Signature{ .argument_count = 1, .scalar32_mask = 0x0 } },
    .{ "vkCmdExecuteCommands", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkCmdFillBuffer", Signature{ .argument_count = 5, .scalar32_mask = 0x10 } },
    .{ "vkCmdNextSubpass", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdNextSubpass2", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkCmdNextSubpass2KHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkCmdPipelineBarrier", Signature{ .argument_count = 10, .scalar32_mask = 0x15e } },
    .{ "vkCmdPipelineBarrier2", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkCmdPipelineBarrier2KHR", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkCmdPushConstants", Signature{ .argument_count = 6, .scalar32_mask = 0x1c } },
    .{ "vkCmdPushDescriptorSetKHR", Signature{ .argument_count = 6, .scalar32_mask = 0x1a } },
    .{ "vkCmdResetQueryPool", Signature{ .argument_count = 4, .scalar32_mask = 0xc } },
    .{ "vkCmdResolveImage", Signature{ .argument_count = 7, .scalar32_mask = 0x34 } },
    .{ "vkCmdSetBlendConstants", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkCmdSetDepthBias", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCmdSetDepthBounds", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkCmdSetDepthCompareOp", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetDepthCompareOpEXT", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetDepthTestEnable", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetDepthTestEnableEXT", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetDepthWriteEnable", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetDepthWriteEnableEXT", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetPrimitiveRestartEnable", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetPrimitiveRestartEnableEXT", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetScissor", Signature{ .argument_count = 4, .scalar32_mask = 0x6 } },
    .{ "vkCmdSetStencilCompareMask", Signature{ .argument_count = 3, .scalar32_mask = 0x6 } },
    .{ "vkCmdSetStencilOp", Signature{ .argument_count = 6, .scalar32_mask = 0x3e } },
    .{ "vkCmdSetStencilOpEXT", Signature{ .argument_count = 6, .scalar32_mask = 0x3e } },
    .{ "vkCmdSetStencilReference", Signature{ .argument_count = 3, .scalar32_mask = 0x6 } },
    .{ "vkCmdSetStencilTestEnable", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetStencilTestEnableEXT", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkCmdSetStencilWriteMask", Signature{ .argument_count = 3, .scalar32_mask = 0x6 } },
    .{ "vkCmdSetViewport", Signature{ .argument_count = 4, .scalar32_mask = 0x6 } },
    .{ "vkCmdUpdateBuffer", Signature{ .argument_count = 5, .scalar32_mask = 0x0 } },
    .{ "vkCreateBuffer", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateBufferView", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateCommandPool", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateComputePipelines", Signature{ .argument_count = 6, .scalar32_mask = 0x4 } },
    .{ "vkCreateDebugUtilsMessengerEXT", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateDescriptorPool", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateDescriptorSetLayout", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateDescriptorUpdateTemplate", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateDevice", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateFence", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateFramebuffer", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateGraphicsPipelines", Signature{ .argument_count = 6, .scalar32_mask = 0x4 } },
    .{ "vkCreateImage", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateImageView", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateInstance", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkCreateMetalSurfaceEXT", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreatePipelineCache", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreatePipelineLayout", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateQueryPool", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateRenderPass", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateSampler", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateSemaphore", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateShaderModule", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkCreateSwapchainKHR", Signature{ .argument_count = 5, .scalar32_mask = 0x0 } },
    .{ "vkCreateWin32SurfaceKHR", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkDestroyBuffer", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyBufferView", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyCommandPool", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyDebugUtilsMessengerEXT", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyDescriptorPool", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyDescriptorSetLayout", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyDescriptorUpdateTemplate", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyDevice", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkDestroyFence", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyFramebuffer", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyImage", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyImageView", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyInstance", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkDestroyPipeline", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyPipelineCache", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyPipelineLayout", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyQueryPool", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyRenderPass", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroySampler", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroySemaphore", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroyShaderModule", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroySurfaceKHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDestroySwapchainKHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkDeviceWaitIdle", Signature{ .argument_count = 1, .scalar32_mask = 0x0 } },
    .{ "vkEndCommandBuffer", Signature{ .argument_count = 1, .scalar32_mask = 0x0 } },
    .{ "vkEnumerateDeviceExtensionProperties", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkEnumerateInstanceExtensionProperties", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkEnumerateInstanceLayerProperties", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkEnumerateInstanceVersion", Signature{ .argument_count = 1, .scalar32_mask = 0x0 } },
    .{ "vkEnumeratePhysicalDevices", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkFlushMappedMemoryRanges", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkFreeCommandBuffers", Signature{ .argument_count = 4, .scalar32_mask = 0x4 } },
    .{ "vkFreeDescriptorSets", Signature{ .argument_count = 4, .scalar32_mask = 0x4 } },
    .{ "vkFreeMemory", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetBufferMemoryRequirements", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetBufferMemoryRequirements2", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetBufferMemoryRequirements2KHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetDeviceBufferMemoryRequirements", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetDeviceBufferMemoryRequirementsKHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetDeviceImageMemoryRequirements", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetDeviceImageMemoryRequirementsKHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetDeviceProcAddr", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetDeviceQueue", Signature{ .argument_count = 4, .scalar32_mask = 0x6 } },
    .{ "vkGetDeviceQueue2", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetFenceStatus", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetImageMemoryRequirements", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetImageMemoryRequirements2", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetImageMemoryRequirements2KHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetInstanceProcAddr", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceFeatures", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceFeatures2", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceFeatures2KHR", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceFormatProperties", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkGetPhysicalDeviceMemoryProperties", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceMemoryProperties2", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceMemoryProperties2KHR", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceProperties", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceProperties2", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceProperties2KHR", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceQueueFamilyProperties", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceSurfaceCapabilitiesKHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceSurfaceFormatsKHR", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceSurfacePresentModesKHR", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkGetPhysicalDeviceSurfaceSupportKHR", Signature{ .argument_count = 4, .scalar32_mask = 0x2 } },
    .{ "vkGetPhysicalDeviceWin32PresentationSupportKHR", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkGetPipelineCacheData", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkGetQueryPoolResults", Signature{ .argument_count = 8, .scalar32_mask = 0x8c } },
    .{ "vkGetSemaphoreCounterValue", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetSemaphoreCounterValueKHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkGetSwapchainImagesKHR", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkInvalidateMappedMemoryRanges", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkMapMemory", Signature{ .argument_count = 6, .scalar32_mask = 0x10 } },
    .{ "vkQueueBindSparse", Signature{ .argument_count = 4, .scalar32_mask = 0x2 } },
    .{ "vkQueuePresentKHR", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkQueueSubmit", Signature{ .argument_count = 4, .scalar32_mask = 0x2 } },
    .{ "vkQueueSubmit2", Signature{ .argument_count = 4, .scalar32_mask = 0x2 } },
    .{ "vkQueueSubmit2KHR", Signature{ .argument_count = 4, .scalar32_mask = 0x2 } },
    .{ "vkQueueWaitIdle", Signature{ .argument_count = 1, .scalar32_mask = 0x0 } },
    .{ "vkResetCommandBuffer", Signature{ .argument_count = 2, .scalar32_mask = 0x2 } },
    .{ "vkResetCommandPool", Signature{ .argument_count = 3, .scalar32_mask = 0x4 } },
    .{ "vkResetDescriptorPool", Signature{ .argument_count = 3, .scalar32_mask = 0x4 } },
    .{ "vkResetFences", Signature{ .argument_count = 3, .scalar32_mask = 0x2 } },
    .{ "vkResetQueryPool", Signature{ .argument_count = 4, .scalar32_mask = 0xc } },
    .{ "vkResetQueryPoolEXT", Signature{ .argument_count = 4, .scalar32_mask = 0xc } },
    .{ "vkSetDebugUtilsObjectNameEXT", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkSetDebugUtilsObjectTagEXT", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkSignalSemaphore", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkSignalSemaphoreKHR", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkUnmapMemory", Signature{ .argument_count = 2, .scalar32_mask = 0x0 } },
    .{ "vkUpdateDescriptorSetWithTemplate", Signature{ .argument_count = 4, .scalar32_mask = 0x0 } },
    .{ "vkUpdateDescriptorSets", Signature{ .argument_count = 5, .scalar32_mask = 0xa } },
    .{ "vkWaitForFences", Signature{ .argument_count = 5, .scalar32_mask = 0xa } },
    .{ "vkWaitSemaphores", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
    .{ "vkWaitSemaphoresKHR", Signature{ .argument_count = 3, .scalar32_mask = 0x0 } },
});

pub fn lookup(name: []const u8) ?Signature {
    return signatures.get(name);
}

test "descriptor and barrier scalars have their declared DWORD widths" {
    const bind = lookup("vkCmdBindDescriptorSets").?;
    try std.testing.expectEqual(@as(u8, 8), bind.argument_count);
    try std.testing.expectEqual(@as(u32, 0x5a), bind.scalar32_mask);
    try std.testing.expectEqual(@as(u64, 2), bind.normalize(4, 0x0000_0001_0000_0002));
    try std.testing.expectEqual(@as(u64, 0), bind.normalize(6, 0x0000_0800_0000_0000));
    const barrier = lookup("vkCmdPipelineBarrier").?;
    try std.testing.expectEqual(@as(u32, 0x15e), barrier.scalar32_mask);
}

test "pointer handle timeout and size arguments retain all 64 bits" {
    const raw: u64 = 0xffff_f500_1234_5678;
    const bind = lookup("vkCmdBindDescriptorSets").?;
    for ([_]usize{ 0, 2, 5, 7 }) |index| {
        try std.testing.expectEqual(raw, bind.normalize(index, raw));
    }
    const map = lookup("vkMapMemory").?;
    for ([_]usize{ 1, 2, 3, 5 }) |index| {
        try std.testing.expectEqual(raw, map.normalize(index, raw));
    }
    try std.testing.expectEqual(raw, lookup("vkWaitForFences").?.normalize(4, raw));
}

test "promoted aliases and signed DWORD values use the same width contract" {
    try std.testing.expectEqualDeep(lookup("vkCmdSetStencilOp").?, lookup("vkCmdSetStencilOpEXT").?);
    try std.testing.expectEqual(@as(u64, 0xffff_fffd), lookup("vkCmdDrawIndexed").?.normalize(4, 0xCAFE_BEEF_FFFF_FFFD));
    try std.testing.expect(lookup("vkCmdUnknownRosetteCommand") == null);
}
