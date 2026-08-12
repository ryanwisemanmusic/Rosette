//! Every swapchain decision, made from what the driver reported.
//!
//! The failure this exists to prevent is not a crash. It is a swapchain built
//! from constants that looked reasonable — three images, 1280×720, BGRA, FIFO —
//! which the driver accepts, and which then presents nothing useful because the
//! surface's actual capabilities said something else. Guessing produces a
//! working-looking pipeline whose output is wrong in a way no return code
//! reports.
//!
//! So the choices live here, separated from the calls that make them: given the
//! reported capabilities, formats, present modes, queue families and memory
//! types, decide, and refuse when nothing reported satisfies the requirement.
//! Refusing is the point — `null` means "the host cannot do this", which is a
//! finding, and is what stops the presenter from proceeding on an assumption.
//!
//! Separated from `presenter.zig` because this is the half that can be tested.
//! The FFI half cannot run without a `CAMetalLayer` and a driver; this half runs
//! anywhere and is where the arithmetic that silently corrupts a frame lives —
//! extent clamping, row pitch, the two sentinel values Vulkan encodes as
//! "unbounded" and "no fixed size", and the difference between a present that
//! succeeded and one that succeeded but demands recreation.

const std = @import("std");
const abi = @import("abi.zig");

/// Why the swapchain cannot be built from what the surface reported. Each of
/// these is a host-capability fact, not a Rosette bug, and each names the query
/// whose answer ruled the path out.
pub const Rejection = error{
    NoSurfaceFormat,
    NoPresentMode,
    SurfaceNotPresentable,
    UsageUnsupported,
    NoCompositeAlpha,
    NoPresentQueue,
    NoGraphicsQueue,
    NoMemoryType,
};

pub fn rejectionLabel(rejection: Rejection) []const u8 {
    return switch (rejection) {
        error.NoSurfaceFormat => "the surface reported no formats",
        error.NoPresentMode => "the surface reported no present modes",
        error.SurfaceNotPresentable => "the surface extent is zero, so it cannot hold a drawable right now",
        error.UsageUnsupported => "the surface does not support the image usage the presenter copies with",
        error.NoCompositeAlpha => "the surface reported no composite-alpha mode",
        error.NoPresentQueue => "no queue family can present to this surface",
        error.NoGraphicsQueue => "no queue family supports graphics",
        error.NoMemoryType => "no memory type satisfies the required properties",
    };
}

/// The presenter composites by copying into the acquired image, so transfer
/// destination is required rather than merely convenient. Colour attachment is
/// requested as well so a later render-pass composite does not need a swapchain
/// recreation, but its absence is not fatal.
pub const required_image_usage: u32 = abi.IMAGE_USAGE_TRANSFER_DST_BIT;
pub const desired_image_usage: u32 = abi.IMAGE_USAGE_TRANSFER_DST_BIT | abi.IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

/// Preferred in order. `UNORM` before `SRGB` deliberately: a transfer-based
/// composite writes bytes into the image unconverted while `vkCmdClearColorImage`
/// converts, so an sRGB swapchain makes the clear and the copy disagree about
/// what a given value means. Choosing UNORM keeps both paths in one colour
/// space, which is the difference between a correct frame and a frame that is
/// merely present.
const preferred_formats = [_]u32{
    abi.FORMAT_B8G8R8A8_UNORM,
    abi.FORMAT_R8G8B8A8_UNORM,
    abi.FORMAT_B8G8R8A8_SRGB,
    abi.FORMAT_R8G8B8A8_SRGB,
};

pub fn chooseSurfaceFormat(formats: []const abi.SurfaceFormatKHR) ?abi.SurfaceFormatKHR {
    if (formats.len == 0) return null;
    // A single entry of VK_FORMAT_UNDEFINED is the legacy "any format" reply.
    if (formats.len == 1 and formats[0].format == abi.FORMAT_UNDEFINED) {
        return .{ .format = abi.FORMAT_B8G8R8A8_UNORM, .color_space = abi.COLOR_SPACE_SRGB_NONLINEAR_KHR };
    }
    for (preferred_formats) |wanted| {
        for (formats) |candidate| {
            if (candidate.format == wanted and candidate.color_space == abi.COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return candidate;
            }
        }
    }
    return formats[0];
}

/// FIFO is the only mode the specification requires an implementation to
/// support, and it is also the right default for an emulator presenter: it
/// paces the host to the display instead of spinning. Mailbox is taken only
/// when asked for and reported.
pub fn choosePresentMode(modes: []const u32, prefer_low_latency: bool) ?u32 {
    if (modes.len == 0) return null;
    if (prefer_low_latency) {
        for (modes) |mode| {
            if (mode == abi.PRESENT_MODE_MAILBOX_KHR) return mode;
        }
    }
    for (modes) |mode| {
        if (mode == abi.PRESENT_MODE_FIFO_KHR) return mode;
    }
    return modes[0];
}

/// One more than the minimum, so the application is not forced to wait on the
/// presentation engine to release an image before it can start the next frame.
/// `maxImageCount == 0` means unbounded; treating it as a literal ceiling would
/// clamp the count to zero.
pub fn chooseImageCount(capabilities: abi.SurfaceCapabilitiesKHR) u32 {
    const wanted = capabilities.min_image_count + 1;
    if (capabilities.max_image_count == abi.image_count_unbounded) return wanted;
    return @min(wanted, capabilities.max_image_count);
}

pub const ExtentChoice = union(enum) {
    /// The extent to build the swapchain with.
    extent: abi.Extent2D,
    /// The surface currently has no area — minimised or fully occluded. Not an
    /// error and not a frame: acquiring against it would block or fail, and
    /// reporting a zero-sized success would record a frame that never existed.
    not_presentable,
};

/// `currentExtent` of all-ones means the surface has no fixed size and the
/// application chooses; anything else is mandatory and must be used verbatim.
pub fn chooseExtent(
    capabilities: abi.SurfaceCapabilitiesKHR,
    fallback_width: u32,
    fallback_height: u32,
) ExtentChoice {
    if (capabilities.current_extent.width != abi.extent_undefined or
        capabilities.current_extent.height != abi.extent_undefined)
    {
        if (capabilities.current_extent.width == 0 or capabilities.current_extent.height == 0) {
            return .not_presentable;
        }
        return .{ .extent = capabilities.current_extent };
    }
    const width = std.math.clamp(
        fallback_width,
        capabilities.min_image_extent.width,
        capabilities.max_image_extent.width,
    );
    const height = std.math.clamp(
        fallback_height,
        capabilities.min_image_extent.height,
        capabilities.max_image_extent.height,
    );
    if (width == 0 or height == 0) return .not_presentable;
    return .{ .extent = .{ .width = width, .height = height } };
}

pub fn chooseImageUsage(capabilities: abi.SurfaceCapabilitiesKHR) ?u32 {
    if (capabilities.supported_usage_flags & required_image_usage != required_image_usage) return null;
    return desired_image_usage & capabilities.supported_usage_flags;
}

pub fn chooseCompositeAlpha(capabilities: abi.SurfaceCapabilitiesKHR) ?u32 {
    const preference = [_]u32{
        abi.COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        abi.COMPOSITE_ALPHA_INHERIT_BIT_KHR,
    };
    for (preference) |bit| {
        if (capabilities.supported_composite_alpha & bit != 0) return bit;
    }
    if (capabilities.supported_composite_alpha == 0) return null;
    // Lowest set bit: any reported mode beats inventing one.
    return capabilities.supported_composite_alpha & (~capabilities.supported_composite_alpha +% 1);
}

pub fn choosePreTransform(capabilities: abi.SurfaceCapabilitiesKHR) u32 {
    if (capabilities.supported_transforms & abi.SURFACE_TRANSFORM_IDENTITY_BIT_KHR != 0) {
        return abi.SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
    }
    return capabilities.current_transform;
}

pub const QueueSelection = struct {
    graphics_family: u32,
    present_family: u32,

    /// When these differ every presented image needs a queue-family ownership
    /// transfer, which is a different command recording — not a detail the
    /// presenter can discover later from a return code.
    pub fn unified(self: QueueSelection) bool {
        return self.graphics_family == self.present_family;
    }
};

/// A family that can do both is strongly preferred: it removes the ownership
/// transfer entirely. Falling back to a split pair is correct but costs a
/// barrier per frame, so which one happened is worth recording.
pub fn selectQueueFamilies(
    families: []const abi.QueueFamilyProperties,
    present_support: []const bool,
) Rejection!QueueSelection {
    std.debug.assert(families.len == present_support.len);
    var graphics: ?u32 = null;
    var present: ?u32 = null;
    for (families, present_support, 0..) |family, presents, index| {
        if (family.queue_count == 0) continue;
        const supports_graphics = family.queue_flags & abi.QUEUE_GRAPHICS_BIT != 0;
        if (supports_graphics and presents) {
            return .{ .graphics_family = @intCast(index), .present_family = @intCast(index) };
        }
        if (supports_graphics and graphics == null) graphics = @intCast(index);
        if (presents and present == null) present = @intCast(index);
    }
    if (graphics == null) return error.NoGraphicsQueue;
    if (present == null) return error.NoPresentQueue;
    return .{ .graphics_family = graphics.?, .present_family = present.? };
}

pub fn selectMemoryType(
    properties: abi.PhysicalDeviceMemoryProperties,
    type_bits: u32,
    required_flags: u32,
) ?u32 {
    const count = @min(properties.memory_type_count, @as(u32, abi.MAX_MEMORY_TYPES));
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        if (type_bits & (@as(u32, 1) << @intCast(index)) == 0) continue;
        const flags = properties.memory_types[index].property_flags;
        if (flags & required_flags == required_flags) return index;
    }
    return null;
}

/// What to do about a `vkAcquireNextImageKHR` return code. Written as an
/// enumeration because the interesting cases are the ones that are neither
/// success nor failure: suboptimal yields a usable image *and* demands
/// recreation, and a timeout is not a frame at all.
pub const AcquireOutcome = enum {
    acquired,
    /// Usable this frame; the swapchain must be rebuilt before the next.
    acquired_suboptimal,
    /// No image this time. Not a failure and not a frame.
    retry,
    recreate,
    surface_lost,
    device_lost,
    failed,

    pub fn yieldsImage(self: AcquireOutcome) bool {
        return self == .acquired or self == .acquired_suboptimal;
    }

    pub fn demandsRecreation(self: AcquireOutcome) bool {
        return self == .acquired_suboptimal or self == .recreate or self == .surface_lost;
    }
};

pub fn classifyAcquire(result: abi.Result) AcquireOutcome {
    return switch (result) {
        abi.SUCCESS => .acquired,
        abi.SUBOPTIMAL_KHR => .acquired_suboptimal,
        abi.TIMEOUT, abi.NOT_READY => .retry,
        abi.ERROR_OUT_OF_DATE_KHR => .recreate,
        abi.ERROR_SURFACE_LOST_KHR => .surface_lost,
        abi.ERROR_DEVICE_LOST => .device_lost,
        else => .failed,
    };
}

pub const PresentOutcome = enum {
    presented,
    /// The request was accepted; the swapchain no longer matches the surface.
    presented_suboptimal,
    recreate,
    surface_lost,
    device_lost,
    failed,

    /// Whether the presentation engine accepted the request. Deliberately not
    /// named `succeeded`: acceptance is not the same as a pixel a person saw,
    /// and conflating the two is how a counter becomes evidence of rendering.
    pub fn requestAccepted(self: PresentOutcome) bool {
        return self == .presented or self == .presented_suboptimal;
    }

    pub fn demandsRecreation(self: PresentOutcome) bool {
        return self == .presented_suboptimal or self == .recreate or self == .surface_lost;
    }
};

pub fn classifyPresent(result: abi.Result) PresentOutcome {
    return switch (result) {
        abi.SUCCESS => .presented,
        abi.SUBOPTIMAL_KHR => .presented_suboptimal,
        abi.ERROR_OUT_OF_DATE_KHR => .recreate,
        abi.ERROR_SURFACE_LOST_KHR => .surface_lost,
        abi.ERROR_DEVICE_LOST => .device_lost,
        else => .failed,
    };
}

pub fn bytesPerPixel(format: u32) ?u32 {
    return switch (format) {
        abi.FORMAT_R8G8B8A8_UNORM,
        abi.FORMAT_R8G8B8A8_SRGB,
        abi.FORMAT_B8G8R8A8_UNORM,
        abi.FORMAT_B8G8R8A8_SRGB,
        abi.FORMAT_A2B10G10R10_UNORM_PACK32,
        => 4,
        else => null,
    };
}

/// Whether the two formats agree on channel order. A source and swapchain that
/// disagree need a swizzle, and a straight `vkCmdCopyBufferToImage` between
/// them produces a picture with red and blue exchanged — visually obvious, but
/// only if somebody is looking.
pub fn channelOrderMatches(source_format: u32, destination_format: u32) bool {
    const source_is_bgra = source_format == abi.FORMAT_B8G8R8A8_UNORM or source_format == abi.FORMAT_B8G8R8A8_SRGB;
    const destination_is_bgra = destination_format == abi.FORMAT_B8G8R8A8_UNORM or destination_format == abi.FORMAT_B8G8R8A8_SRGB;
    return source_is_bgra == destination_is_bgra;
}

pub const StagingLayout = struct {
    row_pitch_bytes: u64,
    /// `bufferRowLength` is measured in texels, not bytes. Passing a byte
    /// count here is a copy that reads four times too far along each row.
    buffer_row_length_texels: u32,
    total_bytes: u64,
};

pub fn stagingLayout(format: u32, width: u32, height: u32) ?StagingLayout {
    if (width == 0 or height == 0) return null;
    const texel_bytes = bytesPerPixel(format) orelse return null;
    const row_pitch = @as(u64, width) * texel_bytes;
    return .{
        .row_pitch_bytes = row_pitch,
        .buffer_row_length_texels = width,
        .total_bytes = row_pitch * height,
    };
}

test "an undefined single format is the driver saying it does not care" {
    const formats = [_]abi.SurfaceFormatKHR{.{ .format = abi.FORMAT_UNDEFINED }};
    const chosen = chooseSurfaceFormat(&formats).?;
    try std.testing.expectEqual(abi.FORMAT_B8G8R8A8_UNORM, chosen.format);
}

// The clear path and the copy path have to agree about what a byte means, and
// only a linear format makes them agree.
test "a UNORM format is preferred over an SRGB one offered alongside it" {
    const formats = [_]abi.SurfaceFormatKHR{
        .{ .format = abi.FORMAT_B8G8R8A8_SRGB },
        .{ .format = abi.FORMAT_B8G8R8A8_UNORM },
    };
    try std.testing.expectEqual(abi.FORMAT_B8G8R8A8_UNORM, chooseSurfaceFormat(&formats).?.format);
}

test "an unrecognised format is used rather than replaced with a guess" {
    const formats = [_]abi.SurfaceFormatKHR{.{ .format = abi.FORMAT_A2B10G10R10_UNORM_PACK32 }};
    try std.testing.expectEqual(abi.FORMAT_A2B10G10R10_UNORM_PACK32, chooseSurfaceFormat(&formats).?.format);
    try std.testing.expect(chooseSurfaceFormat(&.{}) == null);
}

test "FIFO is chosen by default and mailbox only when asked for" {
    const modes = [_]u32{ abi.PRESENT_MODE_IMMEDIATE_KHR, abi.PRESENT_MODE_MAILBOX_KHR, abi.PRESENT_MODE_FIFO_KHR };
    try std.testing.expectEqual(abi.PRESENT_MODE_FIFO_KHR, choosePresentMode(&modes, false).?);
    try std.testing.expectEqual(abi.PRESENT_MODE_MAILBOX_KHR, choosePresentMode(&modes, true).?);

    // Asking for low latency where mailbox is absent still lands on FIFO.
    const without_mailbox = [_]u32{ abi.PRESENT_MODE_IMMEDIATE_KHR, abi.PRESENT_MODE_FIFO_KHR };
    try std.testing.expectEqual(abi.PRESENT_MODE_FIFO_KHR, choosePresentMode(&without_mailbox, true).?);
    try std.testing.expect(choosePresentMode(&.{}, false) == null);
}

// Zero means unbounded. Read literally it clamps the swapchain to no images at
// all, and the driver rejects the create with a code that says nothing about
// where the zero came from.
test "an unbounded maximum image count is not a ceiling of zero" {
    const unbounded = abi.SurfaceCapabilitiesKHR{ .min_image_count = 2, .max_image_count = abi.image_count_unbounded };
    try std.testing.expectEqual(@as(u32, 3), chooseImageCount(unbounded));

    const capped = abi.SurfaceCapabilitiesKHR{ .min_image_count = 2, .max_image_count = 2 };
    try std.testing.expectEqual(@as(u32, 2), chooseImageCount(capped));
}

test "a fixed current extent overrides the window's own idea of its size" {
    const fixed = abi.SurfaceCapabilitiesKHR{
        .current_extent = .{ .width = 2560, .height = 1440 },
        .min_image_extent = .{ .width = 1, .height = 1 },
        .max_image_extent = .{ .width = 16384, .height = 16384 },
    };
    const chosen = chooseExtent(fixed, 1280, 720);
    try std.testing.expectEqual(@as(u32, 2560), chosen.extent.width);
    try std.testing.expectEqual(@as(u32, 1440), chosen.extent.height);
}

test "an undefined current extent clamps the requested size into the surface bounds" {
    const flexible = abi.SurfaceCapabilitiesKHR{
        .current_extent = .{ .width = abi.extent_undefined, .height = abi.extent_undefined },
        .min_image_extent = .{ .width = 640, .height = 480 },
        .max_image_extent = .{ .width = 1920, .height = 1080 },
    };
    const clamped_up = chooseExtent(flexible, 320, 240);
    try std.testing.expectEqual(@as(u32, 640), clamped_up.extent.width);
    try std.testing.expectEqual(@as(u32, 480), clamped_up.extent.height);

    const clamped_down = chooseExtent(flexible, 4096, 4096);
    try std.testing.expectEqual(@as(u32, 1920), clamped_down.extent.width);
    try std.testing.expectEqual(@as(u32, 1080), clamped_down.extent.height);
}

// A minimised window reports a zero extent. Acquiring against it is not a
// frame, and recording it as one would put a phantom in the frame log.
test "a zero extent is reported as not presentable rather than as a frame" {
    const minimised = abi.SurfaceCapabilitiesKHR{ .current_extent = .{ .width = 0, .height = 0 } };
    try std.testing.expectEqual(ExtentChoice.not_presentable, chooseExtent(minimised, 1280, 720));
}

test "usage the surface cannot provide is refused instead of requested anyway" {
    const no_transfer = abi.SurfaceCapabilitiesKHR{ .supported_usage_flags = abi.IMAGE_USAGE_COLOR_ATTACHMENT_BIT };
    try std.testing.expect(chooseImageUsage(no_transfer) == null);

    const both = abi.SurfaceCapabilitiesKHR{
        .supported_usage_flags = abi.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | abi.IMAGE_USAGE_TRANSFER_DST_BIT | abi.IMAGE_USAGE_TRANSFER_SRC_BIT,
    };
    const usage = chooseImageUsage(both).?;
    try std.testing.expect(usage & abi.IMAGE_USAGE_TRANSFER_DST_BIT != 0);
    try std.testing.expect(usage & abi.IMAGE_USAGE_TRANSFER_SRC_BIT == 0);

    // Transfer alone is enough for the copy composite.
    const transfer_only = abi.SurfaceCapabilitiesKHR{ .supported_usage_flags = abi.IMAGE_USAGE_TRANSFER_DST_BIT };
    try std.testing.expectEqual(abi.IMAGE_USAGE_TRANSFER_DST_BIT, chooseImageUsage(transfer_only).?);
}

test "composite alpha and pre-transform fall back to something the surface reported" {
    const inherit_only = abi.SurfaceCapabilitiesKHR{ .supported_composite_alpha = abi.COMPOSITE_ALPHA_INHERIT_BIT_KHR };
    try std.testing.expectEqual(abi.COMPOSITE_ALPHA_INHERIT_BIT_KHR, chooseCompositeAlpha(inherit_only).?);

    const exotic = abi.SurfaceCapabilitiesKHR{ .supported_composite_alpha = 0x4 };
    try std.testing.expectEqual(@as(u32, 0x4), chooseCompositeAlpha(exotic).?);
    try std.testing.expect(chooseCompositeAlpha(.{}) == null);

    const rotated = abi.SurfaceCapabilitiesKHR{ .supported_transforms = 0x2, .current_transform = 0x2 };
    try std.testing.expectEqual(@as(u32, 0x2), choosePreTransform(rotated));
}

test "a family that both renders and presents is preferred over a split pair" {
    const families = [_]abi.QueueFamilyProperties{
        .{ .queue_flags = abi.QUEUE_GRAPHICS_BIT, .queue_count = 1 },
        .{ .queue_flags = abi.QUEUE_GRAPHICS_BIT | abi.QUEUE_COMPUTE_BIT, .queue_count = 1 },
    };
    const support = [_]bool{ false, true };
    const selection = try selectQueueFamilies(&families, &support);
    try std.testing.expectEqual(@as(u32, 1), selection.graphics_family);
    try std.testing.expect(selection.unified());
}

// A split pair is correct but changes the recorded commands, so it must be
// visible before the first frame rather than inferred from a validation error.
test "a split graphics and present pair is reported as needing an ownership transfer" {
    const families = [_]abi.QueueFamilyProperties{
        .{ .queue_flags = abi.QUEUE_GRAPHICS_BIT, .queue_count = 1 },
        .{ .queue_flags = abi.QUEUE_TRANSFER_BIT, .queue_count = 1 },
    };
    const support = [_]bool{ false, true };
    const selection = try selectQueueFamilies(&families, &support);
    try std.testing.expectEqual(@as(u32, 0), selection.graphics_family);
    try std.testing.expectEqual(@as(u32, 1), selection.present_family);
    try std.testing.expect(!selection.unified());
}

test "a surface no family can present to is a named rejection" {
    const families = [_]abi.QueueFamilyProperties{.{ .queue_flags = abi.QUEUE_GRAPHICS_BIT, .queue_count = 1 }};
    const support = [_]bool{false};
    try std.testing.expectError(error.NoPresentQueue, selectQueueFamilies(&families, &support));

    const compute_only = [_]abi.QueueFamilyProperties{.{ .queue_flags = abi.QUEUE_COMPUTE_BIT, .queue_count = 1 }};
    const presents = [_]bool{true};
    try std.testing.expectError(error.NoGraphicsQueue, selectQueueFamilies(&compute_only, &presents));
}

test "a memory type must satisfy every required property, not merely one" {
    var properties = abi.PhysicalDeviceMemoryProperties{ .memory_type_count = 3 };
    properties.memory_types[0] = .{ .property_flags = abi.MEMORY_PROPERTY_DEVICE_LOCAL_BIT };
    properties.memory_types[1] = .{ .property_flags = abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT };
    properties.memory_types[2] = .{
        .property_flags = abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT | abi.MEMORY_PROPERTY_HOST_COHERENT_BIT,
    };
    const wanted = abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT | abi.MEMORY_PROPERTY_HOST_COHERENT_BIT;
    try std.testing.expectEqual(@as(u32, 2), selectMemoryType(properties, 0b111, wanted).?);

    // A type that satisfies the flags but is excluded by the resource's type
    // bits is not a candidate.
    try std.testing.expect(selectMemoryType(properties, 0b011, wanted) == null);
}

// Suboptimal is the case that gets mishandled: it hands back a usable image and
// simultaneously says the swapchain is stale. Treating it as plain success
// leaves a permanently mismatched swapchain; treating it as failure drops a
// frame that was fine.
test "suboptimal yields an image and still demands recreation" {
    const outcome = classifyAcquire(abi.SUBOPTIMAL_KHR);
    try std.testing.expectEqual(AcquireOutcome.acquired_suboptimal, outcome);
    try std.testing.expect(outcome.yieldsImage());
    try std.testing.expect(outcome.demandsRecreation());

    const present = classifyPresent(abi.SUBOPTIMAL_KHR);
    try std.testing.expect(present.requestAccepted());
    try std.testing.expect(present.demandsRecreation());
}

test "a timeout is neither a frame nor a failure" {
    const timed_out = classifyAcquire(abi.TIMEOUT);
    try std.testing.expectEqual(AcquireOutcome.retry, timed_out);
    try std.testing.expect(!timed_out.yieldsImage());
    try std.testing.expect(!timed_out.demandsRecreation());
    try std.testing.expectEqual(AcquireOutcome.retry, classifyAcquire(abi.NOT_READY));
}

test "out-of-date, surface-lost and device-lost are separated by what they require" {
    try std.testing.expectEqual(AcquireOutcome.recreate, classifyAcquire(abi.ERROR_OUT_OF_DATE_KHR));
    try std.testing.expectEqual(AcquireOutcome.surface_lost, classifyAcquire(abi.ERROR_SURFACE_LOST_KHR));
    try std.testing.expectEqual(AcquireOutcome.device_lost, classifyAcquire(abi.ERROR_DEVICE_LOST));
    try std.testing.expectEqual(AcquireOutcome.failed, classifyAcquire(abi.ERROR_OUT_OF_HOST_MEMORY));

    // Device loss must never be answered by rebuilding the swapchain on the
    // dead device.
    try std.testing.expect(!classifyAcquire(abi.ERROR_DEVICE_LOST).demandsRecreation());
    try std.testing.expect(!classifyPresent(abi.ERROR_DEVICE_LOST).demandsRecreation());
}

// "Accepted" and "seen" are different claims, and the enumeration is named so
// that a caller cannot accidentally make the stronger one.
test "an accepted present is not called a success" {
    try std.testing.expect(classifyPresent(abi.SUCCESS).requestAccepted());
    try std.testing.expect(!classifyPresent(abi.ERROR_OUT_OF_DATE_KHR).requestAccepted());
}

test "buffer row length is counted in texels and total size in bytes" {
    const layout = stagingLayout(abi.FORMAT_B8G8R8A8_UNORM, 1280, 720).?;
    try std.testing.expectEqual(@as(u32, 1280), layout.buffer_row_length_texels);
    try std.testing.expectEqual(@as(u64, 1280 * 4), layout.row_pitch_bytes);
    try std.testing.expectEqual(@as(u64, 1280 * 4 * 720), layout.total_bytes);

    try std.testing.expect(stagingLayout(abi.FORMAT_B8G8R8A8_UNORM, 0, 720) == null);
    try std.testing.expect(stagingLayout(abi.FORMAT_UNDEFINED, 16, 16) == null);
}

test "a channel-order mismatch between source and swapchain is detectable" {
    try std.testing.expect(channelOrderMatches(abi.FORMAT_B8G8R8A8_UNORM, abi.FORMAT_B8G8R8A8_SRGB));
    try std.testing.expect(!channelOrderMatches(abi.FORMAT_R8G8B8A8_UNORM, abi.FORMAT_B8G8R8A8_UNORM));
}

test "every rejection explains itself in terms of what the host reported" {
    inline for (@typeInfo(Rejection).error_set.?) |field| {
        const rejection: Rejection = @field(anyerror, field.name);
        try std.testing.expect(rejectionLabel(rejection).len > 0);
    }
}
