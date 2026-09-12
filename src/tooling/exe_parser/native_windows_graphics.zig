//! Host-side graphics companion for the Windows PE route.
//!
//! A Windows image running through Rosetta cannot pass a Win32 HWND or a
//! Vulkan dispatchable handle directly to macOS.  This small owner therefore
//! sits beside the guest ABI state: it consumes the native Cocoa/Metal window
//! status, brings up Rosetta's dependency-ordered Vulkan presenter, and can
//! issue a clearly labelled host diagnostic frame.  It never marks that frame
//! as guest output.  Actual guest Vulkan command forwarding remains a separate
//! contract and is reported as absent until the guest objects have real host
//! parents.

const builtin = @import("builtin");
const std = @import("std");
const gpu = @import("gpu");
const windows_guest_forwarder = @import("windows_guest_forwarder");

const NativeWindowStatus = extern struct {
    application: usize,
    window: usize,
    view: usize,
    metal_layer: usize,
    metal_device: usize,
    width: u32,
    height: u32,
    events_pumped: u32,
    application_ready: u8,
    window_ready: u8,
    layer_attached: u8,
    visible: u8,
    on_main_thread: u8,
    reserved: [3]u8,
};

extern fn dlopen(path: [*:0]const u8, flags: c_int) ?*anyopaque;
extern fn dlsym(handle: ?*anyopaque, name: [*:0]const u8) ?*anyopaque;
extern fn rosette_macho_native_window_status() NativeWindowStatus;

const rtld_now: c_int = 0x2;
const rtld_local: c_int = 0x4;

pub const NativeWindowsGraphics = struct {
    presenter: gpu.vulkan.Presenter = .{},
    guest_vulkan: windows_guest_forwarder.Bridge = .{},
    loader: ?*anyopaque = null,
    loader_attempts: u64 = 0,
    loader_failures: u64 = 0,
    bring_up_attempts: u64 = 0,
    bring_up_failures: u64 = 0,
    diagnostic_attempts: u64 = 0,
    diagnostic_failures: u64 = 0,
    last_width: u32 = 0,
    last_height: u32 = 0,

    fn resolveVulkanSymbol(context: ?*anyopaque, name: [*:0]const u8) callconv(.c) ?*anyopaque {
        return dlsym(context, name);
    }

    fn loadVulkan(self: *NativeWindowsGraphics) ?*anyopaque {
        if (self.loader) |loader| return loader;
        if (comptime builtin.target.os.tag != .macos) return null;

        const candidates = [_][*:0]const u8{
            // Keep the SDK locations ahead of generic search paths.  The
            // shell audit records these as the host's validated providers, and
            // selecting the same loader here avoids accidentally mixing a
            // header/runtime pair from two Vulkan installations.
            "/Users/ryanwiseman/VulkanSDK/vulkan/macOS/lib/libvulkan.1.3.275.dylib",
            "/Users/ryanwiseman/VulkanSDK/vulkan/macOS/lib/libvulkan.1.dylib",
            "/Users/ryanwiseman/VulkanSDK/vulkan/macOS/lib/libvulkan.dylib",
            "libvulkan.1.dylib",
            "libvulkan.dylib",
            "/opt/homebrew/lib/libvulkan.1.dylib",
            "/opt/homebrew/lib/libvulkan_lvp.dylib",
            "/usr/local/lib/libvulkan.1.4.341.dylib",
            "/usr/local/lib/libvulkan.1.dylib",
            "/usr/local/lib/libvulkan.dylib",
        };
        for (candidates) |candidate| {
            self.loader_attempts +|= 1;
            const handle = dlopen(candidate, rtld_now | rtld_local) orelse {
                self.loader_failures +|= 1;
                continue;
            };
            if (dlsym(handle, "vkGetInstanceProcAddr") == null) {
                self.loader_failures +|= 1;
                continue;
            }
            self.loader = handle;
            return handle;
        }
        return null;
    }

    /// Return the presenter's public stage code.  The value is intentionally
    /// just an enum ordinal at the C-ABI seam; the caller owns the label table
    /// and can keep it stable even if the presenter gains a new stage.
    pub fn stageCode(self: *const NativeWindowsGraphics) u32 {
        return @intFromEnum(self.presenter.stage);
    }

    pub fn ready(self: *const NativeWindowsGraphics) bool {
        return self.presenter.stage.isReady();
    }

    /// Return the host layer only after the native window bridge has attached
    /// it. This is consumed by the Vulkan forwarder and never enters guest
    /// address space.
    pub fn metalLayerHostPointer(_: *const NativeWindowsGraphics) usize {
        if (comptime builtin.target.os.tag != .macos) return 0;
        const window = rosette_macho_native_window_status();
        if (window.metal_layer == 0 or window.layer_attached == 0) return 0;
        return window.metal_layer;
    }

    pub fn reportPresentChain(self: *NativeWindowsGraphics) void {
        self.guest_vulkan.reportPresentChain();
    }

    pub fn reportPresentChainFull(self: *NativeWindowsGraphics) void {
        self.guest_vulkan.reportPresentChainFull();
    }

    pub fn updateGuestProgress(
        self: *NativeWindowsGraphics,
        steps: u64,
        rip: u64,
        thread: u64,
        operation: []const u8,
        frontier_is_bounded: bool,
    ) void {
        self.guest_vulkan.updateGuestProgress(steps, rip, thread, operation, frontier_is_bounded);
    }

    pub fn dispatchVulkan(self: *NativeWindowsGraphics, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
        return self.guest_vulkan.dispatch(state, name, direct_return_rip);
    }

    /// Bring up the real host Vulkan chain against the existing native window.
    /// A failure is retained in the presenter report and is not converted into
    /// a synthetic success.
    pub fn bringUp(self: *NativeWindowsGraphics, width: u32, height: u32) bool {
        if (comptime builtin.target.os.tag != .macos) return false;
        if (self.presenter.stage == .device_lost) return false;
        if (self.presenter.stage.isReady()) return true;

        const window = rosette_macho_native_window_status();
        if (window.metal_layer == 0 or window.layer_attached == 0) return false;
        const loader = self.loadVulkan() orelse return false;

        self.bring_up_attempts +|= 1;
        const stage = self.presenter.bringUp(
            .{ .context = loader, .lookup = resolveVulkanSymbol },
            window.metal_layer,
            @max(width, 1),
            @max(height, 1),
        );
        self.last_width = @max(width, 1);
        self.last_height = @max(height, 1);
        if (!stage.isReady()) self.bring_up_failures +|= 1;
        return stage.isReady();
    }

    /// The only frame this bridge creates on its own is a presenter-owned
    /// clear.  Its ledger calls it diagnostic, which is important: this proves
    /// native Vulkan/CAMetalLayer liveness without claiming that Xenia rendered
    /// anything.
    pub fn presentDiagnostic(self: *NativeWindowsGraphics, serial: u64, width: u32, height: u32, phase: u32) u64 {
        if (!self.ready()) return 0;
        self.diagnostic_attempts +|= 1;
        const next_width = @max(width, 1);
        const next_height = @max(height, 1);
        if (next_width != self.last_width or next_height != self.last_height) {
            self.presenter.noteResize(next_width, next_height);
            self.last_width = next_width;
            self.last_height = next_height;
        }
        const t = @as(f32, @floatFromInt((serial >> 4) % 7)) / 6.0;
        const bias = @as(f32, @floatFromInt(phase % 4)) * 0.08;
        const result = self.presenter.present(.{ .clear = .{ 0.05 + bias, 0.08 + t * 0.35, 0.16 + (1.0 - t) * 0.45, 1.0 } });
        if (!result.presented) {
            self.diagnostic_failures +|= 1;
            return 0;
        }
        return self.presenter.ledger.diagnostic_frames_presented;
    }

    pub fn shutdown(self: *NativeWindowsGraphics) void {
        self.guest_vulkan.deinit();
        self.presenter.shutdown();
        self.loader = null;
    }
};

test "native Windows graphics companion stays non-guest until a frame is proved" {
    var bridge = NativeWindowsGraphics{};
    try std.testing.expect(!bridge.ready());
    try std.testing.expectEqual(@as(u64, 0), bridge.diagnostic_attempts);
    try std.testing.expectEqual(@as(u64, 0), bridge.presenter.ledger.diagnostic_frames_presented);
}
