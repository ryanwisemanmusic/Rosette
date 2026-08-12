//! Native macOS window management extracted from MachOState (process.zig).
//! Handles NSApplication/NSWindow lifecycle, Metal/Vulkan surface tokens,
//! and window event pumping.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const native_window_runtime = @import("guest_abi").native_window_runtime;

pub fn registerNativeWindowHandles(self: anytype) void {
    if (self.native_window_handles_registered) return;
    self.registerOpaqueHandle(native_window_runtime.APPLICATION_TOKEN, "native NSApplication identity");
    self.registerOpaqueHandle(native_window_runtime.WINDOW_TOKEN, "native NSWindow identity");
    self.registerOpaqueHandle(native_window_runtime.VIEW_TOKEN, "native NSView identity");
    self.registerOpaqueHandle(native_window_runtime.METAL_LAYER_TOKEN, "native CAMetalLayer identity");
    self.native_window_handles_registered = true;
}

pub fn ensureNativeApplication(self: anytype) bool {
    const ready = self.native_window.ensureApplication();
    if (ready) registerNativeWindowHandles(self);
    return ready;
}

pub fn ensureNativeWindow(self: anytype) bool {
    const ready = self.native_window.ensureWindow();
    if (ready) registerNativeWindowHandles(self);
    return ready;
}

pub fn setNativeWindowTitle(self: anytype, title: []const u8) bool {
    const ready = self.native_window.setTitle(title);
    if (ready) registerNativeWindowHandles(self);
    return ready;
}

pub fn setNativeWindowSize(self: anytype, width: i32, height: i32) bool {
    const ready = self.native_window.setSize(width, height);
    if (ready) registerNativeWindowHandles(self);
    return ready;
}

pub fn showNativeWindow(self: anytype) bool {
    const ready = self.native_window.show();
    if (ready) registerNativeWindowHandles(self);
    return ready;
}

pub fn setNativeWindowFullscreen(self: anytype, fullscreen: bool) bool {
    return self.native_window.setFullscreen(fullscreen);
}

pub fn nativeViewToken(self: anytype) u64 {
    const token = self.native_window.viewToken();
    if (token != 0) registerNativeWindowHandles(self);
    return token;
}

pub fn nativeWindowWidth(self: anytype) u32 {
    return self.native_window.width();
}

pub fn nativeWindowHeight(self: anytype) u32 {
    return self.native_window.height();
}

pub fn validateNativeMetalLayerToken(self: anytype, token: u64) bool {
    return self.native_window.validateLayerToken(token);
}

pub fn nativeMetalLayerHostPointer(self: anytype) usize {
    return self.native_window.hostMetalLayer();
}

pub fn noteNativeVulkanSurfaceBound(self: anytype, layer_token: u64, guest_surface: u64, host_surface: u64) void {
    self.native_window.noteSurfaceBound(layer_token, guest_surface, host_surface);
}

/// The host Metal clear fallback. Named diagnostic because that is all it is:
/// see `native_window_runtime.presentDiagnosticFrame`.
pub fn presentNativeDiagnosticFrame(
    self: anytype,
    serial: u64,
    width: u32,
    height: u32,
    stage: u32,
) bool {
    return self.native_window.presentDiagnosticFrame(serial, width, height, stage);
}

pub fn pumpNativeWindowEvents(self: anytype) void {
    if (self.native_window.application_ensure_attempts == 0) return;
    _ = self.native_window.pumpEvents();
}
