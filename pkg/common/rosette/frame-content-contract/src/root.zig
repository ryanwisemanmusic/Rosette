//! Whether a presented frame carried a picture, or only a colour.
//!
//! `lib/gpu/present_chain.zig` was written around a good idea: a present is
//! only evidence of a visible frame if something wrote into the image that
//! was acquired for it, because
//!
//! > A present of an image nothing rendered into is a black frame the driver
//! > is perfectly happy with.
//!
//! The implementation carried that idea as one boolean, `writes`, and every
//! path that touched the acquired image set it - including the render pass's
//! `loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR`. So on the 2026-09-12 run Xenia
//! recorded exactly two Vulkan commands for its only frame,
//! `vkCmdBeginRenderPass` and `vkCmdEndRenderPass`, with `draw=0`, and the
//! chain reported
//!
//! ```text
//!   acquires=1 presents=1 with_target=1 with_content=1
//!   verdict=healthy -- frames are reaching the compositor
//! ```
//!
//! Every one of those numbers is true. The frame was a flat clear colour.
//! `with_content` had certified the exact state the counter exists to catch.
//!
//! ## The distinction this package draws
//!
//! A clear **is** a write. It is not **content**. The separation matters
//! because the two states have different owners and different next steps:
//!
//! * A frame with no write at all accuses Rosette's command attribution, or
//!   the guest's frame graph: something acquired an image and presented it
//!   without recording anything against it.
//! * A frame whose only write is a fill accuses nobody in the host stack.
//!   The transport works; the title has not drawn yet. Sending a reader to
//!   the Vulkan bridge for that wastes the session.
//!
//! So the classification is by *what the command can put on the screen*:
//!
//! * `.none` - the command cannot change the image's pixels (state setting,
//!   a barrier, a query).
//! * `.uniform_fill` - the command can only write a constant: a render-pass
//!   load clear, `vkCmdClearColorImage`, `vkCmdClearAttachments`. The result
//!   is a solid colour over some region, which is what a blank window is.
//! * `.content` - the command's output depends on data the title supplied:
//!   a draw, a dispatch, a copy, a blit, a resolve. Only this can put a
//!   picture on the screen.
//!
//! ## What this package proves, and what it does not
//!
//! It is a pure function of a command's identity. It does not know which
//! image the command targeted, whether the command buffer was submitted, or
//! whether the pixels that resulted were interesting - `present_chain`'s
//! attribution and the pixel probe answer those, and this classification is
//! only consulted after a command has already been attributed to the
//! acquired image. A `.content` write from a shader that outputs black still
//! produces a black frame; that is what the pixel probe is for, and the two
//! pieces of evidence are deliberately kept separate.

const std = @import("std");

/// What a command can put into the image it targets.
///
/// Ordered from weakest to strongest so a frame's accumulated evidence is the
/// strongest of its commands, and so the ordering stays meaningful if a kind
/// is ever added between two existing ones.
pub const WriteKind = enum(u2) {
    /// Cannot change the image's pixels.
    none = 0,
    /// Can only write a constant colour or depth value.
    uniform_fill = 1,
    /// Writes values derived from data the title supplied.
    content = 2,

    pub fn label(self: WriteKind) []const u8 {
        return switch (self) {
            .none => "none",
            .uniform_fill => "uniform_fill",
            .content => "content",
        };
    }

    /// The stronger of two kinds. A frame accumulates its commands this way:
    /// one draw among a hundred clears is a drawn frame.
    pub fn strongest(a: WriteKind, b: WriteKind) WriteKind {
        return if (@intFromEnum(a) >= @intFromEnum(b)) a else b;
    }

    /// Whether a frame whose accumulated writes are this kind may be called
    /// content. This is the single rule the whole package exists to state.
    pub fn isContent(self: WriteKind) bool {
        return self == .content;
    }

    /// Whether the frame was written at all. A fill is a write; the pixels
    /// did change. Kept separate from `isContent` so a reader can tell
    /// "nothing touched this image" from "something filled it".
    pub fn isWrite(self: WriteKind) bool {
        return self != .none;
    }
};

/// One command name and what it can write.
///
/// Lookup is by exact name, so ordering carries no meaning and no entry can
/// shadow another.
pub const Entry = struct {
    /// The Vulkan entry point, spelled exactly as the guest calls it.
    name: []const u8,
    kind: WriteKind,
    /// Why it is classified this way, in one clause. A bare table cannot be
    /// audited: the next reader cannot tell a considered `.uniform_fill`
    /// from a guess.
    reason: []const u8,
};

/// Commands that can reach a render target's pixels.
///
/// Only commands with a non-`.none` kind are listed. An unlisted command is
/// `.none`, which is the safe default: it can never manufacture content
/// evidence, and the worst a missing entry can do is under-report a real
/// frame, which surfaces as `presenting_unwritten_images` rather than as a
/// false `healthy`.
pub const entries = [_]Entry{
    // --- Rasterization. The output depends on vertex data, shaders and
    // descriptors, all supplied by the title.
    .{ .name = "vkCmdDraw", .kind = .content, .reason = "rasterizes title geometry into the bound attachments" },
    .{ .name = "vkCmdDrawIndexed", .kind = .content, .reason = "rasterizes indexed title geometry" },
    .{ .name = "vkCmdDrawIndirect", .kind = .content, .reason = "rasterizes geometry whose parameters the title computed" },
    .{ .name = "vkCmdDrawIndexedIndirect", .kind = .content, .reason = "rasterizes indexed geometry whose parameters the title computed" },
    .{ .name = "vkCmdDrawIndirectCount", .kind = .content, .reason = "rasterizes a title-computed number of draws" },
    .{ .name = "vkCmdDrawIndexedIndirectCount", .kind = .content, .reason = "rasterizes a title-computed number of indexed draws" },

    // --- Compute. A dispatch can write a storage image, and Xenia's
    // resolve and format-conversion paths do exactly that.
    .{ .name = "vkCmdDispatch", .kind = .content, .reason = "a compute shader may write the target as a storage image" },
    .{ .name = "vkCmdDispatchIndirect", .kind = .content, .reason = "a compute shader may write the target as a storage image" },
    .{ .name = "vkCmdDispatchBase", .kind = .content, .reason = "a compute shader may write the target as a storage image" },

    // --- Transfer. This is how Xenia's presenter usually puts the guest
    // front buffer on the swapchain image, so misclassifying these as fills
    // would hide every real frame.
    .{ .name = "vkCmdCopyImage", .kind = .content, .reason = "copies another image's pixels into the target" },
    .{ .name = "vkCmdCopyBufferToImage", .kind = .content, .reason = "copies title-supplied bytes into the target" },
    .{ .name = "vkCmdBlitImage", .kind = .content, .reason = "scales another image's pixels into the target" },
    .{ .name = "vkCmdResolveImage", .kind = .content, .reason = "resolves a multisampled image into the target" },
    .{ .name = "vkCmdCopyImage2", .kind = .content, .reason = "copies another image's pixels into the target" },
    .{ .name = "vkCmdCopyImage2KHR", .kind = .content, .reason = "copies another image's pixels into the target" },
    .{ .name = "vkCmdCopyBufferToImage2", .kind = .content, .reason = "copies title-supplied bytes into the target" },
    .{ .name = "vkCmdCopyBufferToImage2KHR", .kind = .content, .reason = "copies title-supplied bytes into the target" },
    .{ .name = "vkCmdBlitImage2", .kind = .content, .reason = "scales another image's pixels into the target" },
    .{ .name = "vkCmdBlitImage2KHR", .kind = .content, .reason = "scales another image's pixels into the target" },
    .{ .name = "vkCmdResolveImage2", .kind = .content, .reason = "resolves a multisampled image into the target" },
    .{ .name = "vkCmdResolveImage2KHR", .kind = .content, .reason = "resolves a multisampled image into the target" },

    // --- Fills. Each of these can only put one value everywhere it touches.
    // A frame built from these alone is a solid colour, which is the state
    // this package exists to keep out of `with_content`.
    .{ .name = "vkCmdClearColorImage", .kind = .uniform_fill, .reason = "writes one colour over the ranges it names" },
    .{ .name = "vkCmdClearDepthStencilImage", .kind = .uniform_fill, .reason = "writes one depth/stencil value over the ranges it names" },
    .{ .name = "vkCmdClearAttachments", .kind = .uniform_fill, .reason = "writes one value per attachment over the rects it names" },
    .{ .name = "vkCmdFillBuffer", .kind = .uniform_fill, .reason = "writes one value; reaches an image only through a later copy, which is classified on its own" },
};

/// What a Vulkan command can write into the image it targets.
///
/// An unrecognized name is `.none`. That is the conservative answer for a
/// content claim: an unmodelled command can never be the sole reason a frame
/// is called healthy.
pub fn classify(command_name: []const u8) WriteKind {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, command_name)) return entry.kind;
    }
    return .none;
}

/// The table row behind a classification, for a report that wants to print
/// why a frame was or was not counted as content.
pub fn entryFor(command_name: []const u8) ?Entry {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, command_name)) return entry;
    }
    return null;
}

/// What a render pass contributes to its attachments purely by beginning.
///
/// `vkCmdBeginRenderPass` with `loadOp = CLEAR` does write the attachment,
/// with no command of its own to classify - which is exactly how a clear
/// reached `with_content` in the first place. Making the caller ask through
/// this function keeps the answer in the same table as everything else.
pub fn renderPassLoadKind(has_color_load_clear: bool) WriteKind {
    return if (has_color_load_clear) .uniform_fill else .none;
}

pub fn entryCount() usize {
    return entries.len;
}

test "a clear is a write and is not content" {
    // The whole point of the package, stated as an assertion.
    try std.testing.expectEqual(WriteKind.uniform_fill, classify("vkCmdClearColorImage"));
    try std.testing.expect(WriteKind.uniform_fill.isWrite());
    try std.testing.expect(!WriteKind.uniform_fill.isContent());

    // The 2026-09-12 frame: a render pass whose loadOp cleared, and nothing
    // else. It had `with_content=1` and was a flat colour.
    try std.testing.expectEqual(WriteKind.uniform_fill, renderPassLoadKind(true));
    try std.testing.expect(!renderPassLoadKind(true).isContent());
    try std.testing.expectEqual(WriteKind.none, renderPassLoadKind(false));
}

test "a draw, a dispatch and a copy are content" {
    try std.testing.expect(classify("vkCmdDraw").isContent());
    try std.testing.expect(classify("vkCmdDrawIndexed").isContent());
    try std.testing.expect(classify("vkCmdDispatch").isContent());
    // Xenia's presenter puts the guest front buffer on the swapchain image
    // with a blit or a draw depending on the path; both must count.
    try std.testing.expect(classify("vkCmdBlitImage").isContent());
    try std.testing.expect(classify("vkCmdCopyImage").isContent());
    try std.testing.expect(classify("vkCmdResolveImage2KHR").isContent());
}

test "an unmodelled command cannot manufacture content" {
    try std.testing.expectEqual(WriteKind.none, classify("vkCmdSetViewport"));
    try std.testing.expectEqual(WriteKind.none, classify("vkCmdPipelineBarrier"));
    try std.testing.expectEqual(WriteKind.none, classify("vkCmdBindPipeline"));
    try std.testing.expectEqual(WriteKind.none, classify("vkCmdSomethingNobodyHasModelled"));
    try std.testing.expectEqual(WriteKind.none, classify(""));
}

test "a frame accumulates the strongest write it received" {
    // Xenia's real frame: clear the attachment, then draw into it.
    var frame = WriteKind.none;
    frame = WriteKind.strongest(frame, renderPassLoadKind(true));
    try std.testing.expectEqual(WriteKind.uniform_fill, frame);
    frame = WriteKind.strongest(frame, classify("vkCmdDraw"));
    try std.testing.expectEqual(WriteKind.content, frame);
    // A clear after the draw does not weaken it.
    frame = WriteKind.strongest(frame, classify("vkCmdClearAttachments"));
    try std.testing.expectEqual(WriteKind.content, frame);
    try std.testing.expect(frame.isContent());
}

test "every entry carries a reason and no name is listed twice" {
    for (entries, 0..) |entry, index| {
        try std.testing.expect(entry.name.len != 0);
        try std.testing.expect(entry.reason.len != 0);
        try std.testing.expect(entry.kind != .none);
        try std.testing.expect(std.mem.startsWith(u8, entry.name, "vkCmd"));
        for (entries[0..index]) |earlier| {
            try std.testing.expect(!std.mem.eql(u8, earlier.name, entry.name));
        }
        // The table row and the classifier must never disagree.
        try std.testing.expectEqual(entry.kind, classify(entry.name));
        try std.testing.expectEqual(entry.kind, (entryFor(entry.name) orelse return error.MissingEntry).kind);
    }
    try std.testing.expect(entryCount() >= 20);
}
