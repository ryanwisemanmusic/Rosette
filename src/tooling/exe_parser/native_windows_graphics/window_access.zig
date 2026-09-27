//! Narrow host-window boundary used by the Windows Vulkan adapter.
//!
//! Status snapshots inspect AppKit state and must be marshalled to the main
//! thread. Vulkan surface creation only needs the already-published layer
//! pointer, so keep that lock-free read separate from the AppKit snapshot path.

const std = @import("std");

pub const Status = extern struct {
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

extern "c" fn rosette_macho_native_window_status() Status;
extern "c" fn rosette_macho_native_window_metal_layer_pointer() usize;

pub fn snapshot() Status {
    return rosette_macho_native_window_status();
}

/// Returns a host-only CAMetalLayer pointer. Zero means the AppKit bridge has
/// not published an attached, device-backed layer yet.
pub fn metalLayerPointer() ?usize {
    const pointer = rosette_macho_native_window_metal_layer_pointer();
    return if (pointer == 0) null else pointer;
}

test "native window ABI snapshot layout remains stable" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(Status));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(Status, "events_pumped"));
}
