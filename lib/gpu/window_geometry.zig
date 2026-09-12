//! What the host window looks like right now, as AppKit sees it.
//!
//! A presented swapchain image only becomes a pixel if the whole chain behind
//! it is intact, and Vulkan can see none of that chain: it reports
//! `VK_SUCCESS` for a window that is miniaturised, a view that is hidden, a
//! layer that is not the view's layer, and a `drawableSize` of zero. These are
//! the host-side facts that decide whether any of that is true.
//!
//! The layout is shared by the guest-ABI window runtime, which fills it from
//! the Objective-C bridge, and by the Vulkan forwarder, which reports it
//! beside the presentation topology. One definition so the two cannot drift.

const std = @import("std");

/// Everything about the on-screen chain that decides whether a presented
/// swapchain image can be seen. Mirrors
/// `RosetteMachONativeWindowGeometry` field for field.
///
/// A black window with a healthy present count is nearly always one of these:
/// a zero drawable size, a layer that is not the view's layer, a hidden view,
/// an occluded window, or a contents scale that does not match the surface the
/// guest was told about. Vulkan reports `VK_SUCCESS` for every one of them.
pub const Geometry = extern struct {
    window: usize = 0,
    view: usize = 0,
    metal_layer: usize = 0,
    view_layer: usize = 0,
    layer_superlayer: usize = 0,
    layer_device: usize = 0,
    screen: usize = 0,

    window_x: f64 = 0,
    window_y: f64 = 0,
    window_width: f64 = 0,
    window_height: f64 = 0,
    view_width: f64 = 0,
    view_height: f64 = 0,
    layer_width: f64 = 0,
    layer_height: f64 = 0,
    drawable_width: f64 = 0,
    drawable_height: f64 = 0,
    contents_scale: f64 = 0,
    backing_scale: f64 = 0,
    window_alpha: f64 = 0,

    layer_pixel_format: u32 = 0,
    maximum_drawable_count: u32 = 0,
    occlusion_state: u32 = 0,

    window_exists: u8 = 0,
    window_visible: u8 = 0,
    window_miniaturized: u8 = 0,
    window_on_screen: u8 = 0,
    window_key: u8 = 0,
    view_hidden: u8 = 0,
    view_hidden_or_ancestor: u8 = 0,
    view_wants_layer: u8 = 0,
    layer_is_view_layer: u8 = 0,
    layer_hidden: u8 = 0,
    layer_opaque: u8 = 0,
    layer_framebuffer_only: u8 = 0,
    layer_presents_with_transaction: u8 = 0,
    on_main_thread: u8 = 0,
    reserved: [2]u8 = [_]u8{0} ** 2,

    /// The visible frame of the screen the window is on, in the same global
    /// coordinate space as `window_x`/`window_y`.
    ///
    /// `window_on_screen` only says AppKit found *a* screen for the window.
    /// A window can be on a screen and almost entirely outside the part of
    /// it a person can see, and every other field here reads perfectly for
    /// that case: visible, unoccluded, layer attached, drawable non-zero.
    screen_visible_x: f64 = 0,
    screen_visible_y: f64 = 0,
    screen_visible_width: f64 = 0,
    screen_visible_height: f64 = 0,
    screen_count: u32 = 0,
    reserved_screen: u32 = 0,

    /// AppKit reports a window as visible while it is fully covered by another
    /// window. `NSWindowOcclusionStateVisible` is bit 1.
    pub fn occlusionVisible(self: Geometry) bool {
        return (self.occlusion_state & 0x2) != 0;
    }

    /// How much of the window lies inside its screen's visible area, in
    /// hundredths. 100 when the screen geometry is unknown, because an
    /// unmeasured window must not read as a hidden one.
    pub fn visibleFractionPercent(self: Geometry) u32 {
        if (self.screen_visible_width <= 0.0 or self.screen_visible_height <= 0.0) return 100;
        const area = self.window_width * self.window_height;
        if (area <= 0.0) return 0;
        const left = @max(self.window_x, self.screen_visible_x);
        const right = @min(self.window_x + self.window_width, self.screen_visible_x + self.screen_visible_width);
        const bottom = @max(self.window_y, self.screen_visible_y);
        const top = @min(self.window_y + self.window_height, self.screen_visible_y + self.screen_visible_height);
        const overlap = @max(right - left, 0.0) * @max(top - bottom, 0.0);
        const percent = overlap / area * 100.0;
        if (percent <= 0.0) return 0;
        if (percent >= 100.0) return 100;
        return @intFromFloat(percent);
    }

    /// Whether the window is somewhere a person is unlikely to find it.
    ///
    /// Deliberately not part of `firstBrokenLink`: a window hanging off the
    /// edge of a display still carries frames, and calling that a broken
    /// chain would send a reader to the Vulkan path for a placement problem.
    /// It is its own line, with its own threshold, and it says how much is
    /// showing rather than only that something is wrong.
    pub fn placementAdvisory(self: Geometry) ?[]const u8 {
        if (self.window_exists == 0 or self.window_on_screen == 0) return null;
        if (self.screen_visible_width <= 0.0) return null;
        const percent = self.visibleFractionPercent();
        if (percent == 0) return "the window's frame lies entirely outside its screen's visible area; AppKit still reports it on screen and unoccluded, and nothing of it can be seen";
        if (percent < 25) return "less than a quarter of the window's frame lies inside its screen's visible area; a presented frame is being drawn mostly off the edge of the display";
        return null;
    }

    /// The first link in the chain that cannot carry a frame, or null when
    /// every link is intact. Ordered from the outside in, so the answer is the
    /// outermost thing to fix rather than a symptom of it.
    pub fn firstBrokenLink(self: Geometry) ?[]const u8 {
        if (self.window_exists == 0) return "no NSWindow exists";
        if (self.window_miniaturized != 0) return "the window is miniaturized";
        if (self.window_visible == 0) return "the window is not visible (never ordered on screen, or ordered out)";
        if (self.window_on_screen == 0) return "the window is not on any screen";
        if (self.window_alpha <= 0.0) return "the window's alpha is zero";
        if (self.view == 0) return "the window has no content view";
        if (self.view_wants_layer == 0) return "the content view is not layer-backed";
        if (self.view_hidden_or_ancestor != 0) return "the content view is hidden, or has a hidden ancestor";
        if (self.metal_layer == 0) return "no CAMetalLayer exists";
        if (self.layer_is_view_layer == 0) return "the CAMetalLayer is not the content view's layer, so nothing composites it";
        if (self.layer_superlayer == 0 and self.layer_is_view_layer == 0) return "the CAMetalLayer has no superlayer";
        if (self.layer_hidden != 0) return "the CAMetalLayer is hidden";
        if (self.layer_device == 0) return "the CAMetalLayer has no MTLDevice, so it can vend no drawable";
        if (self.drawable_width <= 0.0 or self.drawable_height <= 0.0) return "the CAMetalLayer's drawableSize is zero, so every present targets nothing";
        if (self.view_width <= 0.0 or self.view_height <= 0.0) return "the content view has zero area";
        if (!self.occlusionVisible()) return "the window is fully occluded; it presents happily and shows nothing";
        return null;
    }
};

comptime {
    // The Objective-C bridge writes through a pointer to this type. Nothing
    // else compiles both definitions, so the size is pinned on both sides:
    // see the matching `_Static_assert` in lib/Mach-O/native_window_bridge.h.
    if (@sizeOf(Geometry) != 232) {
        @compileError("Geometry changed size; update RosetteMachONativeWindowGeometry and both assertions");
    }
}

test "a chain with every link intact reports no break" {
    const healthy = Geometry{
        .window = 0x1000,
        .view = 0x2000,
        .metal_layer = 0x3000,
        .view_layer = 0x3000,
        .layer_device = 0x4000,
        .window_width = 1280,
        .window_height = 720,
        .view_width = 1280,
        .view_height = 720,
        .drawable_width = 2560,
        .drawable_height = 1440,
        .contents_scale = 2.0,
        .window_alpha = 1.0,
        .occlusion_state = 0x2,
        .window_exists = 1,
        .window_visible = 1,
        .window_on_screen = 1,
        .view_wants_layer = 1,
        .layer_is_view_layer = 1,
    };
    try std.testing.expect(healthy.occlusionVisible());
    try std.testing.expect(healthy.firstBrokenLink() == null);
}

test "each way the chain breaks is named, outermost first" {
    const healthy = Geometry{
        .window = 0x1000,
        .view = 0x2000,
        .metal_layer = 0x3000,
        .view_layer = 0x3000,
        .layer_device = 0x4000,
        .view_width = 1280,
        .view_height = 720,
        .drawable_width = 2560,
        .drawable_height = 1440,
        .window_alpha = 1.0,
        .occlusion_state = 0x2,
        .window_exists = 1,
        .window_visible = 1,
        .window_on_screen = 1,
        .view_wants_layer = 1,
        .layer_is_view_layer = 1,
    };

    // The one that produced a black window with thousands of successful
    // presents: a layer that is not the view's layer composites nothing.
    var detached = healthy;
    detached.layer_is_view_layer = 0;
    try std.testing.expect(std.mem.indexOf(
        u8,
        detached.firstBrokenLink().?,
        "not the content view's layer",
    ) != null);

    // A zero drawable swallows every present without an error.
    var no_drawable = healthy;
    no_drawable.drawable_width = 0;
    try std.testing.expect(std.mem.indexOf(u8, no_drawable.firstBrokenLink().?, "drawableSize is zero") != null);

    // A fully occluded window presents happily and shows nothing.
    var occluded = healthy;
    occluded.occlusion_state = 0;
    try std.testing.expect(std.mem.indexOf(u8, occluded.firstBrokenLink().?, "occluded") != null);

    // Outermost first: a miniaturized window is reported as such rather than
    // as whatever its layer looks like underneath.
    var miniaturized = healthy;
    miniaturized.window_miniaturized = 1;
    miniaturized.layer_is_view_layer = 0;
    try std.testing.expect(std.mem.indexOf(u8, miniaturized.firstBrokenLink().?, "miniaturized") != null);

    // ...and no window at all outranks everything.
    var absent = healthy;
    absent.window_exists = 0;
    absent.window_miniaturized = 1;
    try std.testing.expect(std.mem.indexOf(u8, absent.firstBrokenLink().?, "no NSWindow") != null);

    for ([_]Geometry{ detached, no_drawable, occluded, miniaturized, absent }) |broken| {
        try std.testing.expect(broken.firstBrokenLink() != null);
    }
}

test "a window on a screen can still be almost entirely off it" {
    // The 2026-09-12 run: frame=1280x748@-1140,-130 with visible=1,
    // on_screen=1 and occlusion_visible=true. Every existing field reads
    // perfectly and about a tenth of the window is on the display.
    const displaced = Geometry{
        .window = 0x12be2f610,
        .view = 0x12d81f1f0,
        .metal_layer = 0x12d824480,
        .view_layer = 0x12d824480,
        .layer_device = 0x12d026800,
        .window_x = -1140,
        .window_y = -130,
        .window_width = 1280,
        .window_height = 748,
        .view_width = 1280,
        .view_height = 720,
        .drawable_width = 2560,
        .drawable_height = 1440,
        .window_alpha = 1.0,
        .occlusion_state = 0x2,
        .window_exists = 1,
        .window_visible = 1,
        .window_on_screen = 1,
        .view_wants_layer = 1,
        .layer_is_view_layer = 1,
        .screen_visible_x = 0,
        .screen_visible_y = 0,
        .screen_visible_width = 1512,
        .screen_visible_height = 945,
        .screen_count = 1,
    };
    // Not a broken chain: it can carry a frame, and calling it a break would
    // send a reader to the Vulkan path.
    try std.testing.expect(displaced.firstBrokenLink() == null);
    try std.testing.expect(displaced.visibleFractionPercent() < 25);
    try std.testing.expect(displaced.placementAdvisory() != null);

    var centred = displaced;
    centred.window_x = 116;
    centred.window_y = 98;
    try std.testing.expectEqual(@as(u32, 100), centred.visibleFractionPercent());
    try std.testing.expectEqual(@as(?[]const u8, null), centred.placementAdvisory());

    // Entirely outside is its own sentence, because it is the case where a
    // perfect present count and an invisible window are both true.
    var gone = displaced;
    gone.window_x = -4000;
    try std.testing.expectEqual(@as(u32, 0), gone.visibleFractionPercent());
    try std.testing.expect(std.mem.indexOf(u8, gone.placementAdvisory().?, "entirely outside") != null);

    // An unmeasured screen must never read as a hidden window.
    var unmeasured = displaced;
    unmeasured.screen_visible_width = 0;
    unmeasured.screen_visible_height = 0;
    try std.testing.expectEqual(@as(u32, 100), unmeasured.visibleFractionPercent());
    try std.testing.expectEqual(@as(?[]const u8, null), unmeasured.placementAdvisory());
}
