//! Why a presented frame is not on screen.
//!
//! A run can present thousands of images, get `VK_SUCCESS` from every call,
//! and show a black window. Every counter in the bridge says the GPU path is
//! healthy, because every counter measures a call that returned. What none of
//! them measure is the chain a pixel actually has to travel:
//!
//! ```text
//!   NSWindow -> NSView -> CAMetalLayer -> VkSurfaceKHR -> VkSwapchainKHR
//!            -> acquired image -> rendered into -> presented -> composited
//! ```
//!
//! Each link can be intact while the next is not, and Vulkan reports success
//! for most of the ways the chain breaks: a swapchain whose images are
//! acquired and presented but never rendered into presents black; a layer
//! whose `drawableSize` is zero swallows every present; two swapchains built
//! on one `CAMetalLayer` fight over the same drawable pool, and the one that
//! is not being driven wins about half the time.
//!
//! This module records the topology and the traffic so those states are
//! distinguishable. It holds no host pointers it can call, allocates nothing,
//! and answers one question: which link is the first that cannot carry a
//! frame.

const std = @import("std");
const window_geometry = @import("window_geometry");
const frame_content_contract = @import("frame_content_contract");

/// What a command can put into the image it targets. Owned by
/// `pkg/common/rosette/frame-content-contract`, re-exported here because the
/// Vulkan forwarder reaches the classification through the chain it feeds.
pub const WriteKind = frame_content_contract.WriteKind;

/// The classification table itself, for the forwarder's command dispatch.
pub const frame_content = frame_content_contract;

/// The on-screen chain, defined in its own file so the Vulkan forwarder and
/// the guest-ABI window runtime can share one layout without either module
/// owning the other's files.
pub const Geometry = window_geometry.Geometry;

/// Who created a presentation object. A `CAMetalLayer` with objects from both
/// owners is the contested case that produces a black window with a perfect
/// present count.
pub const Owner = enum {
    /// The translated program asked for it.
    guest,
    /// Rosetta's own presenter or diagnostic path created it.
    rosette,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .guest => "guest",
            .rosette => "rosette",
        };
    }
};

pub const max_surfaces: usize = 8;
pub const max_swapchains: usize = 8;
pub const max_swapchain_images: usize = 8;

/// The strongest target attribution Rosette can make for a command.
/// `swapchain_image` is deliberately narrower than "a Vulkan command ran":
/// it means the command named the image that was acquired for the frame being
/// presented.  Everything else must remain distinguishable from proof of a
/// guest-visible frame.
pub const TargetKind = enum {
    none,
    swapchain_image,
    offscreen_image,
    unknown,

    pub fn label(self: TargetKind) []const u8 {
        return switch (self) {
            .none => "none",
            .swapchain_image => "swapchain_image",
            .offscreen_image => "offscreen_image",
            .unknown => "unknown",
        };
    }
};

/// Pixel evidence is intentionally separate from Vulkan transport evidence.
/// A successful present with no probe is still useful, but it is not an image
/// verdict.
pub const PixelEvidence = enum {
    unprobed,
    unavailable,
    /// Every byte read back was zero.
    solid_clear,
    /// Every pixel read back held the same non-zero value. This is what a
    /// frame built only from a clear looks like, and on an opaque format it
    /// is also what a black window looks like: `0xFF000000` has non-zero
    /// bytes in it, so "non-zero" alone never distinguished a picture from a
    /// fill.
    uniform_colour,
    /// The pixels vary, and the frame hashes the same as the previous probe.
    nonzero_static,
    /// The pixels vary and the hash moved between probes.
    changing,

    pub fn label(self: PixelEvidence) []const u8 {
        return switch (self) {
            .unprobed => "unprobed",
            .unavailable => "unavailable",
            .solid_clear => "solid_clear",
            .uniform_colour => "uniform_colour",
            .nonzero_static => "nonzero_static",
            .changing => "changing",
        };
    }

    /// Whether the readback shows more than one colour. A frame that does
    /// not is a fill whatever the transport counters say.
    pub fn showsDetail(self: PixelEvidence) bool {
        return switch (self) {
            .nonzero_static, .changing => true,
            .unprobed, .unavailable, .solid_clear, .uniform_colour => false,
        };
    }
};

pub const SurfaceRecord = struct {
    /// The `VkSurfaceKHR` as the driver knows it.
    handle: u64 = 0,
    /// The `CAMetalLayer` it was created from.
    layer: u64 = 0,
    owner: Owner = .guest,
    retired: bool = false,
};

pub const SwapchainRecord = struct {
    handle: u64 = 0,
    surface: u64 = 0,
    layer: u64 = 0,
    owner: Owner = .guest,
    retired: bool = false,

    width: u32 = 0,
    height: u32 = 0,
    format: u32 = 0,
    present_mode: u32 = 0,
    image_count: u32 = 0,
    /// Usage visible in the host create request after capability filtering.
    image_usage: u32 = 0,
    /// Usage requested by the guest before host-only probe bits are added or
    /// unsupported bits are filtered.
    requested_image_usage: u32 = 0,
    image_handles: [max_swapchain_images]u64 = [_]u64{0} ** max_swapchain_images,
    actual_image_count: u32 = 0,

    /// Images taken out of the swapchain.
    acquires: u64 = 0,
    /// Images handed back to the compositor.
    presents: u64 = 0,
    /// Presents the driver did not accept.
    present_failures: u64 = 0,
    /// Presents whose acquired image received a write that could carry a
    /// picture - a draw, a dispatch, a copy, a blit or a resolve. A present
    /// of an image nothing rendered into is a black frame the driver is
    /// perfectly happy with, and so is a present of an image that was only
    /// cleared, which is why the two are counted apart.
    presents_with_content: u64 = 0,
    /// Presents whose acquired image was written, but only by a fill: a
    /// render-pass load clear, `vkCmdClearColorImage`, `vkCmdClearAttachments`.
    /// The frame is a solid colour. Nothing in the host stack is broken; the
    /// title has not drawn into it yet.
    presents_clear_only: u64 = 0,
    /// Presents for which a render target was identified, but no write was
    /// observed before present.
    presents_without_write: u64 = 0,
    /// Presents for which no command was connected to the acquired image.
    presents_without_target: u64 = 0,
    /// Presents for which the acquired image was identified as a render
    /// target, regardless of whether the target was written.
    presents_with_target: u64 = 0,
    target_events: u64 = 0,
    offscreen_events: u64 = 0,
    unknown_target_events: u64 = 0,
    acquired_image_index: u32 = 0,
    acquired_image_handle: u64 = 0,
    last_target_image: u64 = 0,
    last_target_kind: TargetKind = .none,
    /// The strongest write the most recently presented frame received.
    last_write_kind: WriteKind = .none,
    pixel_evidence: PixelEvidence = .unprobed,
    /// The colour every pixel held, when the readback found only one.
    pixel_uniform_value: u32 = 0,
    pixel_hash: u64 = 0,
    pixel_probe_frame: u64 = 0,
    last_present_result: i32 = 0,
    last_image_index: u32 = 0,
};

/// What the chain can be asked, in the order the answers matter.
pub const Verdict = enum {
    /// Nothing has tried to present yet.
    idle,
    /// A frame reached the compositor and the topology has no contested link.
    healthy,
    /// The guest never created a surface.
    no_surface,
    /// A surface exists but nothing built a swapchain on it.
    no_swapchain,
    /// A swapchain exists and nothing has presented through it.
    no_presents,
    /// More than one live swapchain is built on the same `CAMetalLayer`.
    contested_layer,
    /// Images are presented that nothing rendered into.
    presenting_empty_images,
    /// Every presented frame's only write was a fill. The transport works and
    /// the picture does not exist yet.
    presenting_clear_only_frames,
    /// The driver is rejecting the presents.
    presents_failing,
    /// Images are acquired and never handed back.
    acquires_without_presents,
    /// Presents happen, but no command was connected to the acquired guest
    /// swapchain image.
    presenting_without_target,
    /// The acquired guest swapchain image was targeted, but no write reached
    /// it before present.
    presenting_unwritten_images,
    /// AppKit reports that the host-side window chain cannot currently carry a
    /// visible frame. This is supplied by the forwarder after reading the
    /// native window; `Chain.verdict` itself only knows Vulkan traffic.
    host_window_broken,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .idle => "idle: nothing has presented yet",
            .healthy => "healthy: frames are reaching the compositor and no link is contested",
            .no_surface => "no VkSurfaceKHR was ever created; nothing can present",
            .no_swapchain => "a surface exists but no swapchain was built on it",
            .no_presents => "a swapchain exists and nothing has presented through it",
            .contested_layer => "more than one live swapchain is built on the same CAMetalLayer; they share one drawable pool and the one that is not being driven wins roughly half the frames",
            .presenting_empty_images => "images are being presented that no command buffer rendered into; the driver accepts every one of them and each is black",
            .presenting_clear_only_frames => "every presented frame's only write was a clear, so each one is a flat colour; the transport is intact and the guest has not drawn into the acquired image yet, which is the guest's progress and not a host fault",
            .presents_failing => "the driver is rejecting presents",
            .acquires_without_presents => "images are being acquired and not handed back; the pool drains and presentation stalls",
            .presenting_without_target => "presents are accepted, but no command was connected to the acquired guest swapchain image",
            .presenting_unwritten_images => "the acquired guest swapchain image was targeted, but no write reached it before present",
            .host_window_broken => "the host window chain is broken; read the HOST WINDOW BREAK line for the first broken link",
        };
    }

    /// Whether this verdict explains a black window. `idle` and `healthy` do
    /// not, and reporting them as findings is how a diagnostic becomes noise.
    pub fn isFinding(self: Verdict) bool {
        return switch (self) {
            .idle, .healthy => false,
            else => true,
        };
    }
};

/// The presentation topology and its traffic.
pub const Chain = struct {
    surfaces: [max_surfaces]SurfaceRecord = [_]SurfaceRecord{.{}} ** max_surfaces,
    surface_count: usize = 0,
    swapchains: [max_swapchains]SwapchainRecord = [_]SwapchainRecord{.{}} ** max_swapchains,
    swapchain_count: usize = 0,
    surface_overflow: u64 = 0,
    swapchain_overflow: u64 = 0,

    /// Command-buffer writes observed against an acquired image since the last
    /// present. These are kept per swapchain because a guest can have more
    /// than one live swapchain, while the acquired image handle identifies the
    /// exact frame target.
    pending_target: [max_swapchains]bool = [_]bool{false} ** max_swapchains,
    /// The strongest write attributed to the acquired image since the last
    /// present. A boolean here is what let a render-pass load clear read as
    /// frame content on the 2026-09-12 run.
    pending_write_kind: [max_swapchains]WriteKind = [_]WriteKind{.none} ** max_swapchains,

    pub fn noteSurface(self: *Chain, handle: u64, layer: u64, owner: Owner) void {
        if (handle == 0) return;
        for (self.surfaces[0..self.surface_count]) |*record| {
            if (record.handle != handle) continue;
            record.layer = layer;
            record.owner = owner;
            record.retired = false;
            return;
        }
        if (self.surface_count == max_surfaces) {
            self.surface_overflow +|= 1;
            return;
        }
        self.surfaces[self.surface_count] = .{ .handle = handle, .layer = layer, .owner = owner };
        self.surface_count += 1;
    }

    pub fn retireSurface(self: *Chain, handle: u64) void {
        for (self.surfaces[0..self.surface_count]) |*record| {
            if (record.handle == handle) record.retired = true;
        }
    }

    fn surfaceLayer(self: *const Chain, surface: u64) u64 {
        for (self.surfaces[0..self.surface_count]) |record| {
            if (record.handle == surface) return record.layer;
        }
        return 0;
    }

    fn swapchainIndex(self: *Chain, handle: u64) ?usize {
        for (self.swapchains[0..self.swapchain_count], 0..) |record, index| {
            if (record.handle == handle) return index;
        }
        return null;
    }

    pub fn noteSwapchain(self: *Chain, record: SwapchainRecord) void {
        if (record.handle == 0) return;
        var stored = record;
        if (stored.layer == 0) stored.layer = self.surfaceLayer(stored.surface);
        if (self.swapchainIndex(stored.handle)) |index| {
            const previous = self.swapchains[index];
            stored.acquires = previous.acquires;
            stored.presents = previous.presents;
            stored.present_failures = previous.present_failures;
            stored.presents_with_content = previous.presents_with_content;
            stored.presents_clear_only = previous.presents_clear_only;
            stored.presents_without_write = previous.presents_without_write;
            stored.presents_without_target = previous.presents_without_target;
            stored.presents_with_target = previous.presents_with_target;
            stored.target_events = previous.target_events;
            stored.offscreen_events = previous.offscreen_events;
            stored.unknown_target_events = previous.unknown_target_events;
            stored.acquired_image_index = previous.acquired_image_index;
            stored.acquired_image_handle = previous.acquired_image_handle;
            stored.last_target_image = previous.last_target_image;
            stored.last_target_kind = previous.last_target_kind;
            stored.last_write_kind = previous.last_write_kind;
            stored.pixel_evidence = previous.pixel_evidence;
            stored.pixel_hash = previous.pixel_hash;
            stored.pixel_uniform_value = previous.pixel_uniform_value;
            stored.pixel_probe_frame = previous.pixel_probe_frame;
            self.swapchains[index] = stored;
            return;
        }
        if (self.swapchain_count == max_swapchains) {
            self.swapchain_overflow +|= 1;
            return;
        }
        self.swapchains[self.swapchain_count] = stored;
        self.swapchain_count += 1;
    }

    /// Associate the driver's swapchain images with the topology record. The
    /// Vulkan forwarder calls this after translating the guest image handles,
    /// so later command attribution can be made against the acquired image
    /// rather than against all live swapchains.
    pub fn noteSwapchainImages(self: *Chain, handle: u64, images: []const u64) void {
        const index = self.swapchainIndex(handle) orelse return;
        const count = @min(images.len, max_swapchain_images);
        @memset(&self.swapchains[index].image_handles, 0);
        if (count != 0) @memcpy(self.swapchains[index].image_handles[0..count], images[0..count]);
        self.swapchains[index].actual_image_count = @intCast(count);
    }

    /// A swapchain replaced through `oldSwapchain`, or destroyed. A retired
    /// swapchain no longer contests its layer.
    pub fn retireSwapchain(self: *Chain, handle: u64) void {
        for (self.swapchains[0..self.swapchain_count]) |*record| {
            if (record.handle == handle) record.retired = true;
        }
    }

    pub fn noteAcquire(self: *Chain, handle: u64, image_index: u32) void {
        const index = self.swapchainIndex(handle) orelse return;
        const record = &self.swapchains[index];
        record.acquires +|= 1;
        record.last_image_index = image_index;
        record.acquired_image_index = image_index;
        record.acquired_image_handle = if (image_index < record.actual_image_count)
            record.image_handles[image_index]
        else
            0;
        self.pending_target[index] = false;
        self.pending_write_kind[index] = .none;
    }

    /// Record an explicitly attributed write for tests and for command paths
    /// that already know the exact swapchain record. New forwarding code
    /// should prefer `noteTargetImage` so an acquired-image check is made.
    pub fn noteContent(self: *Chain, handle: u64) void {
        self.noteWrite(handle, .content);
    }

    /// The same, for a write that can only put a constant on the screen.
    pub fn noteUniformFill(self: *Chain, handle: u64) void {
        self.noteWrite(handle, .uniform_fill);
    }

    fn noteWrite(self: *Chain, handle: u64, kind: WriteKind) void {
        const index = self.swapchainIndex(handle) orelse return;
        self.pending_target[index] = true;
        self.pending_write_kind[index] = WriteKind.strongest(self.pending_write_kind[index], kind);
        self.swapchains[index].last_target_kind = .swapchain_image;
        self.swapchains[index].target_events +|= 1;
    }

    /// Record a command's image target. Only a write to the image currently
    /// acquired from a live swapchain can become frame content. A swapchain
    /// image that is not acquired belongs to another frame; an unknown image
    /// is conservatively treated as offscreen/unknown rather than as proof.
    pub fn noteTargetImage(self: *Chain, image: u64, write: WriteKind) TargetKind {
        if (image == 0) return .unknown;
        for (self.swapchains[0..self.swapchain_count], 0..) |*record, index| {
            if (record.retired) continue;
            var is_swapchain_image = false;
            for (record.image_handles[0..@as(usize, @intCast(record.actual_image_count))]) |known_image| {
                if (known_image == image) {
                    is_swapchain_image = true;
                    break;
                }
            }
            if (!is_swapchain_image) continue;
            if (record.acquired_image_handle != image) {
                record.last_target_kind = .swapchain_image;
                record.unknown_target_events +|= 1;
                return .swapchain_image;
            }
            self.pending_target[index] = true;
            self.pending_write_kind[index] = WriteKind.strongest(self.pending_write_kind[index], write);
            record.target_events +|= 1;
            record.last_target_image = image;
            record.last_target_kind = .swapchain_image;
            return .swapchain_image;
        }
        return .offscreen_image;
    }

    /// Record bounded host readback evidence separately from the command
    /// attribution verdict.  A probe can say "the image is solid clear" or
    /// "the pixels changed" without turning a successful copy into an
    /// unqualified claim that the guest rendered a visible frame.
    pub fn notePixelProbe(self: *Chain, handle: u64, evidence: PixelEvidence, hash: u64, frame: u64, uniform_value: u32) void {
        const index = self.swapchainIndex(handle) orelse return;
        const record = &self.swapchains[index];
        record.pixel_evidence = evidence;
        record.pixel_hash = hash;
        record.pixel_probe_frame = frame;
        record.pixel_uniform_value = uniform_value;
    }

    pub fn notePresent(self: *Chain, handle: u64, result: i32) void {
        const index = self.swapchainIndex(handle) orelse return;
        const record = &self.swapchains[index];
        record.presents +|= 1;
        record.last_present_result = result;
        const write_kind = self.pending_write_kind[index];
        if (result < 0) {
            record.present_failures +|= 1;
        } else {
            record.last_write_kind = write_kind;
            if (self.pending_target[index]) {
                record.presents_with_target +|= 1;
                switch (write_kind) {
                    // Only a write whose value came from the title can be a
                    // picture. A clear is a write and is not one.
                    .content => record.presents_with_content +|= 1,
                    .uniform_fill => record.presents_clear_only +|= 1,
                    .none => record.presents_without_write +|= 1,
                }
            } else {
                record.presents_without_target +|= 1;
            }
        }
        self.pending_target[index] = false;
        self.pending_write_kind[index] = .none;
    }

    pub fn liveSwapchains(self: *const Chain) usize {
        var total: usize = 0;
        for (self.swapchains[0..self.swapchain_count]) |record| {
            if (!record.retired) total += 1;
        }
        return total;
    }

    pub fn totalPresents(self: *const Chain) u64 {
        var total: u64 = 0;
        for (self.swapchains[0..self.swapchain_count]) |record| total +|= record.presents;
        return total;
    }

    pub fn totalPresentsWithContent(self: *const Chain) u64 {
        var total: u64 = 0;
        for (self.swapchains[0..self.swapchain_count]) |record| total +|= record.presents_with_content;
        return total;
    }

    /// Presents whose acquired image was written only by a fill. These are
    /// the frames that make every transport counter read healthy and leave
    /// the window a flat colour.
    pub fn totalPresentsClearOnly(self: *const Chain) u64 {
        var total: u64 = 0;
        for (self.swapchains[0..self.swapchain_count]) |record| total +|= record.presents_clear_only;
        return total;
    }

    pub fn totalPresentFailures(self: *const Chain) u64 {
        var total: u64 = 0;
        for (self.swapchains[0..self.swapchain_count]) |record| total +|= record.present_failures;
        return total;
    }

    pub fn totalAcquires(self: *const Chain) u64 {
        var total: u64 = 0;
        for (self.swapchains[0..self.swapchain_count]) |record| total +|= record.acquires;
        return total;
    }

    /// The layer a live swapchain of this owner is built on, or zero.
    ///
    /// Used to decide whether two owners are contending for one layer, which
    /// is the only case in which either of them should stand down.
    pub fn layerOfSwapchainOwnedBy(self: *const Chain, owner: Owner) u64 {
        for (self.swapchains[0..self.swapchain_count]) |record| {
            if (record.retired or record.owner != owner) continue;
            if (record.layer != 0) return record.layer;
        }
        return 0;
    }

    /// The `CAMetalLayer` that more than one live swapchain is built on, if
    /// there is one.
    pub fn contestedLayer(self: *const Chain) ?u64 {
        for (self.swapchains[0..self.swapchain_count], 0..) |first, index| {
            if (first.retired or first.layer == 0) continue;
            for (self.swapchains[index + 1 .. self.swapchain_count]) |second| {
                if (second.retired or second.layer != first.layer) continue;
                return first.layer;
            }
        }
        return null;
    }

    /// The first link that cannot carry a frame.
    ///
    /// Ordered so the answer is a cause rather than a symptom of one: a
    /// contested layer is reported before empty images, because two swapchains
    /// sharing a drawable pool is *why* half the frames look empty.
    pub fn verdict(self: *const Chain) Verdict {
        if (self.surface_count == 0) return .no_surface;
        if (self.swapchain_count == 0) return .no_swapchain;

        const presents = self.totalPresents();
        if (presents == 0) {
            // Nothing has come out yet, so a contested layer is both the
            // only thing wrong and a plausible reason nothing will.
            if (self.contestedLayer() != null) return .contested_layer;
            // Acquiring without ever presenting drains the pool; that is a
            // different fault from a swapchain that has not started yet.
            if (self.totalAcquires() >= @as(u64, max_swapchains)) return .acquires_without_presents;
            return .no_presents;
        }

        const failures = self.totalPresentFailures();
        if (failures * 2 >= presents) return .presents_failing;

        // A contested layer explains frames that were *lost*: two swapchains
        // take turns from one drawable pool and the one nobody is driving
        // wins about half of them. It cannot explain frames that were
        // *empty* - a frame with no draw recorded against it is a flat
        // colour whoever vended its drawable - so when nothing has ever
        // carried content, name what the frames actually were first. That
        // statement is stronger and its owner is different.
        if (self.totalPresentsWithContent() == 0) {
            var without_target: u64 = 0;
            var without_write: u64 = 0;
            for (self.swapchains[0..self.swapchain_count]) |record| {
                without_target +|= record.presents_without_target;
                without_write +|= record.presents_without_write;
            }
            // Ordered by how much each accuses the host: an image nothing
            // was attributed to, then an image attributed and not written -
            // both defects - and only then the fill, which is the guest's
            // progress and nobody's fault.
            if (without_target != 0) return .presenting_without_target;
            if (without_write != 0) return .presenting_unwritten_images;
            if (self.totalPresentsClearOnly() != 0) return .presenting_clear_only_frames;
            return .presenting_empty_images;
        }

        if (self.contestedLayer() != null) return .contested_layer;
        return .healthy;
    }

    pub fn isEmpty(self: *const Chain) bool {
        return self.surface_count == 0 and self.swapchain_count == 0;
    }
};

test "an untouched chain has nothing to say" {
    const chain = Chain{};
    try std.testing.expect(chain.isEmpty());
    try std.testing.expectEqual(Verdict.no_surface, chain.verdict());
    // ...but only `no_surface` once something has asked; an empty chain in a
    // run that never reached graphics is not a finding by itself.
    try std.testing.expect(!Verdict.idle.isFinding());
    try std.testing.expect(!Verdict.healthy.isFinding());
    try std.testing.expect(Verdict.contested_layer.isFinding());
}

test "a healthy chain is one where presented images were rendered into" {
    var chain = Chain{};
    const layer: u64 = 0x13f722eb0;
    chain.noteSurface(0x116532aa0, layer, .guest);
    chain.noteSwapchain(.{
        .handle = 0x13f9dc400,
        .surface = 0x116532aa0,
        .owner = .guest,
        .width = 1280,
        .height = 720,
        .format = 44,
        .image_count = 3,
    });
    // The layer is inherited from the surface rather than restated.
    try std.testing.expectEqual(layer, chain.swapchains[0].layer);
    try std.testing.expectEqual(Verdict.no_presents, chain.verdict());

    chain.noteAcquire(0x13f9dc400, 0);
    chain.noteContent(0x13f9dc400);
    chain.notePresent(0x13f9dc400, 0);
    try std.testing.expectEqual(Verdict.healthy, chain.verdict());
    try std.testing.expectEqual(@as(u64, 1), chain.totalPresentsWithContent());
}

test "presenting images nothing rendered into is separated from presenting nothing" {
    var chain = Chain{};
    chain.noteSurface(1, 0xAAAA, .guest);
    chain.noteSwapchain(.{ .handle = 2, .surface = 1, .owner = .guest });

    // Acquire and present without any render traffic in between: every call
    // succeeds and every frame is black.
    var frame: usize = 0;
    while (frame < 32) : (frame += 1) {
        chain.noteAcquire(2, @intCast(frame % 3));
        chain.notePresent(2, 0);
    }
    try std.testing.expectEqual(@as(u64, 32), chain.totalPresents());
    try std.testing.expectEqual(@as(u64, 0), chain.totalPresentsWithContent());
    try std.testing.expectEqual(Verdict.presenting_without_target, chain.verdict());

    // One explicitly attributed rendered frame is enough to prove the path
    // can carry content. Unattributed command traffic must not do this.
    chain.noteAcquire(2, 0);
    chain.noteContent(2);
    chain.notePresent(2, 0);
    try std.testing.expectEqual(Verdict.healthy, chain.verdict());
}

test "a successful present without a swapchain target is not healthy" {
    var chain = Chain{};
    chain.noteSurface(1, 0xAAAA, .guest);
    chain.noteSwapchain(.{ .handle = 2, .surface = 1, .image_count = 2 });
    chain.noteSwapchainImages(2, &.{ 0x200, 0x201 });
    chain.noteAcquire(2, 0);
    _ = chain.noteTargetImage(0x300, .content);
    chain.notePresent(2, 0);
    try std.testing.expectEqual(Verdict.presenting_without_target, chain.verdict());
    try std.testing.expectEqual(@as(u64, 0), chain.totalPresentsWithContent());
}

test "only a write to the acquired image counts as guest content" {
    var chain = Chain{};
    chain.noteSurface(1, 0xAAAA, .guest);
    chain.noteSwapchain(.{ .handle = 2, .surface = 1, .image_count = 2 });
    chain.noteSwapchainImages(2, &.{ 0x200, 0x201 });

    chain.noteAcquire(2, 0);
    try std.testing.expectEqual(TargetKind.swapchain_image, chain.noteTargetImage(0x201, .content));
    chain.notePresent(2, 0);
    try std.testing.expectEqual(Verdict.presenting_without_target, chain.verdict());

    chain.noteAcquire(2, 1);
    try std.testing.expectEqual(TargetKind.swapchain_image, chain.noteTargetImage(0x201, .content));
    chain.notePresent(2, 0);
    try std.testing.expectEqual(Verdict.healthy, chain.verdict());
    try std.testing.expectEqual(@as(u64, 1), chain.totalPresentsWithContent());
}

test "two live swapchains on one layer are reported before anything they cause" {
    var chain = Chain{};
    const layer: u64 = 0xCAFE;
    chain.noteSurface(1, layer, .guest);
    chain.noteSurface(2, layer, .rosette);
    chain.noteSwapchain(.{ .handle = 10, .surface = 1, .owner = .guest });
    chain.noteSwapchain(.{ .handle = 11, .surface = 2, .owner = .rosette });

    try std.testing.expectEqual(@as(?u64, layer), chain.contestedLayer());
    try std.testing.expectEqual(@as(usize, 2), chain.liveSwapchains());
    // Even with healthy traffic, the contested layer is the finding: it is
    // the cause, and the traffic is the symptom.
    chain.noteAcquire(10, 0);
    chain.noteContent(10);
    chain.notePresent(10, 0);
    try std.testing.expectEqual(Verdict.contested_layer, chain.verdict());

    // Retiring the second one settles it.
    chain.retireSwapchain(11);
    try std.testing.expect(chain.contestedLayer() == null);
    try std.testing.expectEqual(@as(usize, 1), chain.liveSwapchains());
    try std.testing.expectEqual(Verdict.healthy, chain.verdict());
}

test "a swapchain recreated through oldSwapchain keeps its traffic" {
    var chain = Chain{};
    chain.noteSurface(1, 0xBEEF, .guest);
    chain.noteSwapchain(.{ .handle = 5, .surface = 1, .width = 640, .height = 480 });
    chain.noteAcquire(5, 0);
    chain.noteContent(5);
    chain.notePresent(5, 0);

    // A resize re-registers the same handle with new geometry. Losing the
    // counters here would make a resized window look like it had never
    // presented.
    chain.noteSwapchain(.{ .handle = 5, .surface = 1, .width = 1280, .height = 720 });
    try std.testing.expectEqual(@as(u32, 1280), chain.swapchains[0].width);
    try std.testing.expectEqual(@as(u64, 1), chain.swapchains[0].presents);
    try std.testing.expectEqual(@as(u64, 1), chain.swapchains[0].presents_with_content);
}

test "a driver rejecting presents is not the same as a driver accepting empty ones" {
    var chain = Chain{};
    chain.noteSurface(1, 0xF00D, .guest);
    chain.noteSwapchain(.{ .handle = 3, .surface = 1 });
    var frame: usize = 0;
    while (frame < 10) : (frame += 1) {
        chain.noteAcquire(3, 0);
        chain.noteContent(3);
        chain.notePresent(3, -1000001004); // VK_ERROR_OUT_OF_DATE_KHR
    }
    try std.testing.expectEqual(@as(u64, 10), chain.totalPresentFailures());
    try std.testing.expectEqual(Verdict.presents_failing, chain.verdict());
    // A failed present carries no content, so it can never be mistaken for a
    // frame that reached the screen.
    try std.testing.expectEqual(@as(u64, 0), chain.totalPresentsWithContent());
}

test "the tables are bounded and say so rather than dropping silently" {
    var chain = Chain{};
    var index: usize = 0;
    while (index < max_swapchains + 4) : (index += 1) {
        chain.noteSurface(@intCast(index + 1), 0x1000, .guest);
        chain.noteSwapchain(.{ .handle = @intCast(index + 100), .surface = @intCast(index + 1) });
    }
    try std.testing.expectEqual(max_surfaces, chain.surface_count);
    try std.testing.expectEqual(max_swapchains, chain.swapchain_count);
    try std.testing.expectEqual(@as(u64, 4), chain.surface_overflow);
    try std.testing.expectEqual(@as(u64, 4), chain.swapchain_overflow);
    // A zero handle is not an object.
    var empty = Chain{};
    empty.noteSurface(0, 0x1000, .guest);
    empty.noteSwapchain(.{ .handle = 0 });
    try std.testing.expect(empty.isEmpty());
}

test "a frame whose only write was a clear is not healthy" {
    // The 2026-09-12 run, reproduced exactly. Xenia recorded two commands for
    // its only frame - vkCmdBeginRenderPass with loadOp CLEAR, and
    // vkCmdEndRenderPass - submitted once, and presented. Every transport
    // counter was correct and the window was a flat colour, but the chain
    // said `healthy` because the load clear had set the write boolean.
    var chain = Chain{};
    chain.noteSurface(0x12beed120, 0x12d824480, .guest);
    chain.noteSwapchain(.{
        .handle = 0x12d087c00,
        .surface = 0x12beed120,
        .owner = .guest,
        .width = 1280,
        .height = 720,
        .format = 44,
        .image_count = 3,
    });
    chain.noteSwapchainImages(0x12d087c00, &.{ 0x12d86aeb0, 0x12d86b000, 0x12d86b150 });

    chain.noteAcquire(0x12d087c00, 0);
    try std.testing.expectEqual(
        TargetKind.swapchain_image,
        chain.noteTargetImage(0x12d86aeb0, frame_content.renderPassLoadKind(true)),
    );
    chain.notePresent(0x12d087c00, 0);

    // The frame was written, attributed, and presented, and it is still not
    // a picture. Each of these three facts has to stay separately visible.
    try std.testing.expectEqual(@as(u64, 1), chain.totalPresents());
    try std.testing.expectEqual(@as(u64, 1), chain.swapchains[0].presents_with_target);
    try std.testing.expectEqual(@as(u64, 1), chain.totalPresentsClearOnly());
    try std.testing.expectEqual(@as(u64, 0), chain.totalPresentsWithContent());
    try std.testing.expectEqual(@as(u64, 0), chain.swapchains[0].presents_without_write);
    try std.testing.expectEqual(Verdict.presenting_clear_only_frames, chain.verdict());
    try std.testing.expect(Verdict.presenting_clear_only_frames.isFinding());
    try std.testing.expectEqual(WriteKind.uniform_fill, chain.swapchains[0].last_write_kind);
}

test "one draw in a cleared frame makes it content" {
    var chain = Chain{};
    chain.noteSurface(1, 0xAAAA, .guest);
    chain.noteSwapchain(.{ .handle = 2, .surface = 1, .image_count = 2 });
    chain.noteSwapchainImages(2, &.{ 0x200, 0x201 });

    chain.noteAcquire(2, 0);
    // The ordinary shape of a real frame: the render pass clears, then the
    // presenter blits the guest front buffer over it.
    _ = chain.noteTargetImage(0x200, frame_content.renderPassLoadKind(true));
    _ = chain.noteTargetImage(0x200, frame_content.classify("vkCmdBlitImage"));
    chain.notePresent(2, 0);

    try std.testing.expectEqual(@as(u64, 1), chain.totalPresentsWithContent());
    try std.testing.expectEqual(@as(u64, 0), chain.totalPresentsClearOnly());
    try std.testing.expectEqual(Verdict.healthy, chain.verdict());
    try std.testing.expectEqual(WriteKind.content, chain.swapchains[0].last_write_kind);
}

test "clear-only frames and unwritten frames are different findings" {
    var chain = Chain{};
    chain.noteSurface(1, 0xAAAA, .guest);
    chain.noteSwapchain(.{ .handle = 2, .surface = 1, .image_count = 2 });
    chain.noteSwapchainImages(2, &.{ 0x200, 0x201 });

    // Targeted but never written: the command attribution or the guest's
    // frame graph is the suspect.
    chain.noteAcquire(2, 0);
    _ = chain.noteTargetImage(0x200, .none);
    chain.notePresent(2, 0);
    try std.testing.expectEqual(Verdict.presenting_unwritten_images, chain.verdict());

    // Filled: nothing in the host stack is the suspect.
    chain.noteAcquire(2, 1);
    _ = chain.noteTargetImage(0x201, .uniform_fill);
    chain.notePresent(2, 0);
    try std.testing.expectEqual(@as(u64, 1), chain.totalPresentsClearOnly());
    try std.testing.expectEqual(@as(u64, 1), chain.swapchains[0].presents_without_write);
    // An unwritten frame outranks a filled one: a missing write is a defect
    // somewhere, a fill is only the title's progress.
    try std.testing.expectEqual(Verdict.presenting_unwritten_images, chain.verdict());
}

test "the write kind survives a swapchain being recreated" {
    var chain = Chain{};
    chain.noteSurface(1, 0xAAAA, .guest);
    chain.noteSwapchain(.{ .handle = 2, .surface = 1, .image_count = 2 });
    chain.noteSwapchainImages(2, &.{ 0x200, 0x201 });
    chain.noteAcquire(2, 0);
    _ = chain.noteTargetImage(0x200, .uniform_fill);
    chain.notePresent(2, 0);

    // A resize re-notes the same handle with new dimensions. Losing the
    // tallies here would let a resized run read as if it had never presented.
    chain.noteSwapchain(.{ .handle = 2, .surface = 1, .image_count = 2, .width = 1920, .height = 1080 });
    try std.testing.expectEqual(@as(u64, 1), chain.totalPresentsClearOnly());
    try std.testing.expectEqual(WriteKind.uniform_fill, chain.swapchains[0].last_write_kind);
    try std.testing.expectEqual(@as(u32, 1920), chain.swapchains[0].width);
}

test "an empty frame outranks a contested layer, because a shared pool cannot empty one" {
    // Both states were live on the 2026-09-12 run: Rosette's own presenter
    // held a 2560x1440 swapchain on the window's CAMetalLayer, the guest
    // built a 1280x720 one on the same layer, and the guest's only frame was
    // a clear. Reporting the layer first would send a reader to the drawable
    // pool for a frame that had nothing in it to lose.
    var chain = Chain{};
    const layer: u64 = 0x12d824480;
    chain.noteSurface(1, layer, .rosette);
    chain.noteSurface(2, layer, .guest);
    chain.noteSwapchain(.{ .handle = 10, .surface = 1, .owner = .rosette, .width = 2560, .height = 1440 });
    chain.noteSwapchain(.{ .handle = 11, .surface = 2, .owner = .guest, .width = 1280, .height = 720, .image_count = 3 });
    chain.noteSwapchainImages(11, &.{ 0x300, 0x301, 0x302 });
    try std.testing.expectEqual(@as(?u64, layer), chain.contestedLayer());

    // Before anything presents, the contested layer is the finding: it is
    // the only thing wrong yet.
    try std.testing.expectEqual(Verdict.contested_layer, chain.verdict());

    chain.noteAcquire(11, 0);
    _ = chain.noteTargetImage(0x300, frame_content.renderPassLoadKind(true));
    chain.notePresent(11, 0);
    try std.testing.expectEqual(Verdict.presenting_clear_only_frames, chain.verdict());

    // Once a frame carries a draw, the layer is the finding again - now it
    // really can be costing frames.
    chain.noteAcquire(11, 1);
    _ = chain.noteTargetImage(0x301, frame_content.classify("vkCmdDraw"));
    chain.notePresent(11, 0);
    try std.testing.expectEqual(Verdict.contested_layer, chain.verdict());
}

test "a black frame on an opaque format is not evidence of a picture" {
    // 0xFF000000 has non-zero bytes in it, so the old "any byte non-zero"
    // test called an opaque black window `nonzero_static` - the same reading
    // a real image produces.
    try std.testing.expect(!PixelEvidence.uniform_colour.showsDetail());
    try std.testing.expect(!PixelEvidence.solid_clear.showsDetail());
    try std.testing.expect(PixelEvidence.nonzero_static.showsDetail());
    try std.testing.expect(PixelEvidence.changing.showsDetail());
    // An unprobed frame is not a claim in either direction.
    try std.testing.expect(!PixelEvidence.unprobed.showsDetail());
    try std.testing.expect(!PixelEvidence.unavailable.showsDetail());

    var chain = Chain{};
    chain.noteSurface(1, 0xAAAA, .guest);
    chain.noteSwapchain(.{ .handle = 2, .surface = 1, .image_count = 2 });
    chain.notePixelProbe(2, .uniform_colour, 0x52bda05e66a4a325, 1, 0xFF000000);
    try std.testing.expectEqual(PixelEvidence.uniform_colour, chain.swapchains[0].pixel_evidence);
    try std.testing.expectEqual(@as(u32, 0xFF000000), chain.swapchains[0].pixel_uniform_value);

    // A resize must not lose the colour: it is the one number that says what
    // the window is actually showing.
    chain.noteSwapchain(.{ .handle = 2, .surface = 1, .image_count = 2, .width = 1920 });
    try std.testing.expectEqual(@as(u32, 0xFF000000), chain.swapchains[0].pixel_uniform_value);
}

test "one owner standing down settles a contested layer" {
    // The 2026-09-12 run: Rosette's presenter held a 2560x1440 swapchain on
    // the window's layer and the guest built a 1280x720 one on the same
    // layer. Rosette is the one with nothing to show, so Rosette yields.
    var chain = Chain{};
    const layer: u64 = 0x13a042920;
    chain.noteSurface(0xA1, layer, .rosette);
    chain.noteSurface(0xB1, layer, .guest);
    chain.noteSwapchain(.{ .handle = 0xA2, .surface = 0xA1, .owner = .rosette, .width = 2560, .height = 1440 });
    chain.noteSwapchain(.{ .handle = 0xB2, .surface = 0xB1, .owner = .guest, .width = 1280, .height = 720 });

    try std.testing.expectEqual(layer, chain.layerOfSwapchainOwnedBy(.guest));
    try std.testing.expectEqual(layer, chain.layerOfSwapchainOwnedBy(.rosette));
    try std.testing.expectEqual(@as(?u64, layer), chain.contestedLayer());

    chain.retireSwapchain(0xA2);
    chain.retireSurface(0xA1);
    try std.testing.expect(chain.contestedLayer() == null);
    try std.testing.expectEqual(@as(u64, 0), chain.layerOfSwapchainOwnedBy(.rosette));
    try std.testing.expectEqual(layer, chain.layerOfSwapchainOwnedBy(.guest));
    try std.testing.expectEqual(@as(usize, 1), chain.liveSwapchains());
}
