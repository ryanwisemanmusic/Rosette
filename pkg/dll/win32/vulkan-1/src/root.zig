//! Windows Vulkan loader boundary facts. Native support remains a runtime query.
const std = @import("std");
pub const argument_widths = @import("argument_widths.zig");
pub const dll_name = "vulkan-1.dll";
pub const stem = "vulkan-1";
pub const match_prefix = "";
pub const subsystem_name = "graphics_stack";
pub const degraded_imports = [_][]const u8{};

pub fn matches(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, stem) or std.ascii.eqlIgnoreCase(name, dll_name);
}
pub fn hasDegradedImport(_: []const u8) bool {
    return false;
}
pub fn isProcLookup(name: []const u8) bool {
    return std.mem.eql(u8, name, "vkGetInstanceProcAddr") or std.mem.eql(u8, name, "vkGetDeviceProcAddr");
}

/// These commands have a command-buffer argument followed by scalar floats.
/// Microsoft x64 uses XMM1..3 (argument positions); SysV uses XMM0..2
/// (independent floating-point argument sequence). Pointer-to-float arguments
/// such as vkCmdSetBlendConstants are integer arguments and must not shift.
pub fn scalarFloatCount(name: []const u8) usize {
    if (std.mem.eql(u8, name, "vkCmdSetDepthBias")) return 3;
    if (std.mem.eql(u8, name, "vkCmdSetDepthBounds")) return 2;
    if (std.mem.eql(u8, name, "vkCmdSetLineWidth")) return 1;
    return 0;
}

pub fn isAcquire(name: []const u8) bool {
    return std.mem.eql(u8, name, "vkAcquireNextImageKHR") or std.mem.eql(u8, name, "vkAcquireNextImage2KHR");
}

/// VK_TIMEOUT / VK_NOT_READY are valid outcomes but produce no image.
/// Only SUCCESS and SUBOPTIMAL transfer an acquired image to the application.
pub fn acquiredImage(result: i32) bool {
    return result == 0 or result == 1_000_001_003;
}

pub fn completesOperation(name: []const u8, result: i32) bool {
    if (isAcquire(name) or std.mem.eql(u8, name, "vkQueuePresentKHR")) return acquiredImage(result);
    if (std.mem.eql(u8, name, "vkGetSwapchainImagesKHR")) return result == 0 or result == 5; // VK_INCOMPLETE
    return result == 0;
}

test "depth state uses positional Windows floats but pointer arguments do not" {
    try std.testing.expectEqual(@as(usize, 3), scalarFloatCount("vkCmdSetDepthBias"));
    try std.testing.expectEqual(@as(usize, 2), scalarFloatCount("vkCmdSetDepthBounds"));
    try std.testing.expectEqual(@as(usize, 0), scalarFloatCount("vkCmdSetBlendConstants"));
}
test "non-error acquire results do not necessarily acquire an image" {
    for ([_]i32{ 1, 2, -1, -1_000_001_004 }) |result| try std.testing.expect(!acquiredImage(result));
    try std.testing.expect(acquiredImage(0));
    try std.testing.expect(acquiredImage(1_000_001_003));
    try std.testing.expect(completesOperation("vkAcquireNextImage2KHR", 1_000_001_003));
    try std.testing.expect(!completesOperation("vkQueueSubmit", 2));
}

test "every Xenia Vulkan entry point has a typed argument-width contract" {
    for (xenia_entry_points) |name| {
        try std.testing.expect(argument_widths.lookup(name) != null);
    }
}

/// Names referenced by the Xenia Canary GPU/UI Vulkan sources inspected on
/// 2026-09-13. Includes optional queries: presence here is a coverage obligation,
/// never permission to advertise an unsupported host feature. Android and XCB
/// platform surface constructors are excluded from the Windows route.
pub const xenia_entry_points = [_][]const u8{
    "vkAcquireNextImageKHR",
    "vkAllocateCommandBuffers",
    "vkAllocateDescriptorSets",
    "vkAllocateMemory",
    "vkBeginCommandBuffer",
    "vkBindBufferMemory",
    "vkBindBufferMemory2",
    "vkBindBufferMemory2KHR",
    "vkBindImageMemory",
    "vkBindImageMemory2",
    "vkBindImageMemory2KHR",
    "vkCmdBeginQuery",
    "vkCmdBeginRenderPass",
    "vkCmdBindDescriptorSets",
    "vkCmdBindIndexBuffer",
    "vkCmdBindPipeline",
    "vkCmdBindVertexBuffers",
    "vkCmdBlitImage",
    "vkCmdClearAttachments",
    "vkCmdClearColorImage",
    "vkCmdCopyBuffer",
    "vkCmdCopyBufferToImage",
    "vkCmdCopyImageToBuffer",
    "vkCmdCopyQueryPoolResults",
    "vkCmdDispatch",
    "vkCmdDraw",
    "vkCmdDrawIndexed",
    "vkCmdEndQuery",
    "vkCmdEndRenderPass",
    "vkCmdFillBuffer",
    "vkCmdPipelineBarrier",
    "vkCmdPushConstants",
    "vkCmdResetQueryPool",
    "vkCmdSetBlendConstants",
    "vkCmdSetDepthBias",
    "vkCmdSetScissor",
    "vkCmdSetStencilCompareMask",
    "vkCmdSetStencilReference",
    "vkCmdSetStencilWriteMask",
    "vkCmdSetViewport",
    "vkCreateBuffer",
    "vkCreateBufferView",
    "vkCreateCommandPool",
    "vkCreateComputePipelines",
    "vkCreateDebugUtilsMessengerEXT",
    "vkCreateDescriptorPool",
    "vkCreateDescriptorSetLayout",
    "vkCreateDevice",
    "vkCreateFence",
    "vkCreateFramebuffer",
    "vkCreateGraphicsPipelines",
    "vkCreateImage",
    "vkCreateImageView",
    "vkCreateInstance",
    "vkCreatePipelineCache",
    "vkCreatePipelineLayout",
    "vkCreateQueryPool",
    "vkCreateRenderPass",
    "vkCreateSampler",
    "vkCreateSemaphore",
    "vkCreateShaderModule",
    "vkCreateSwapchainKHR",
    "vkCreateWin32SurfaceKHR",
    "vkDestroyBuffer",
    "vkDestroyBufferView",
    "vkDestroyCommandPool",
    "vkDestroyDebugUtilsMessengerEXT",
    "vkDestroyDescriptorPool",
    "vkDestroyDescriptorSetLayout",
    "vkDestroyDevice",
    "vkDestroyFence",
    "vkDestroyFramebuffer",
    "vkDestroyImage",
    "vkDestroyImageView",
    "vkDestroyInstance",
    "vkDestroyPipeline",
    "vkDestroyPipelineCache",
    "vkDestroyPipelineLayout",
    "vkDestroyQueryPool",
    "vkDestroyRenderPass",
    "vkDestroySampler",
    "vkDestroySemaphore",
    "vkDestroyShaderModule",
    "vkDestroySurfaceKHR",
    "vkDestroySwapchainKHR",
    "vkEndCommandBuffer",
    "vkEnumerateDeviceExtensionProperties",
    "vkEnumerateInstanceExtensionProperties",
    "vkEnumerateInstanceLayerProperties",
    "vkEnumerateInstanceVersion",
    "vkEnumeratePhysicalDevices",
    "vkFlushMappedMemoryRanges",
    "vkFreeMemory",
    "vkGetBufferMemoryRequirements",
    "vkGetBufferMemoryRequirements2",
    "vkGetBufferMemoryRequirements2KHR",
    "vkGetDeviceBufferMemoryRequirements",
    "vkGetDeviceImageMemoryRequirements",
    "vkGetDeviceProcAddr",
    "vkGetDeviceQueue",
    "vkGetFenceStatus",
    "vkGetImageMemoryRequirements",
    "vkGetImageMemoryRequirements2",
    "vkGetImageMemoryRequirements2KHR",
    "vkGetInstanceProcAddr",
    "vkGetPhysicalDeviceFeatures",
    "vkGetPhysicalDeviceFeatures2",
    "vkGetPhysicalDeviceFormatProperties",
    "vkGetPhysicalDeviceMemoryProperties",
    "vkGetPhysicalDeviceMemoryProperties2",
    "vkGetPhysicalDeviceMemoryProperties2KHR",
    "vkGetPhysicalDeviceProperties",
    "vkGetPhysicalDeviceProperties2",
    "vkGetPhysicalDeviceQueueFamilyProperties",
    "vkGetPhysicalDeviceSurfaceCapabilitiesKHR",
    "vkGetPhysicalDeviceSurfaceFormatsKHR",
    "vkGetPhysicalDeviceSurfacePresentModesKHR",
    "vkGetPhysicalDeviceSurfaceSupportKHR",
    "vkGetPhysicalDeviceWin32PresentationSupportKHR",
    "vkGetPipelineCacheData",
    "vkGetSwapchainImagesKHR",
    "vkInvalidateMappedMemoryRanges",
    "vkMapMemory",
    "vkQueueBindSparse",
    "vkQueuePresentKHR",
    "vkQueueSubmit",
    "vkQueueSubmit2",
    "vkQueueWaitIdle",
    "vkResetCommandPool",
    "vkResetFences",
    "vkResetQueryPool",
    "vkSetDebugUtilsObjectNameEXT",
    "vkUnmapMemory",
    "vkUpdateDescriptorSets",
    "vkWaitForFences",
};
