//! C-ABI callbacks and value snapshots for host graphics, input and audio.
const std = @import("std");

/// The callbacks are deliberately tiny C-ABI seams.  The x86-64 state owns
/// all guest handles and Vulkan objects; a host callback can only report
/// whether Rosetta's native window boundary was reached.  In particular,
/// this type never exposes an AppKit pointer or a host Vulkan handle to the
/// guest address space.
pub const WindowsGraphicsHooks = struct {
    context: ?*anyopaque = null,
    /// Print the window-to-compositor chain. Installed by the runner when a
    /// Vulkan forwarder exists; absent when the run has no graphics path, in
    /// which case there is nothing to describe.
    report_present_chain: ?*const fn (?*anyopaque) callconv(.c) void = null,
    /// Force the complete chain at run termination. Periodic checkpoints use
    /// the collapsed callback above so a healthy run does not repeat the same
    /// topology every 50M guest steps.
    report_present_chain_full: ?*const fn (?*anyopaque) callconv(.c) void = null,
    /// Update the host forwarder's bounded guest-progress breadcrumb before
    /// the chain snapshot is printed. This makes a no-presents report name
    /// the actual guest RIP/op that ran after swapchain creation.
    update_present_diagnostics: ?*const fn (?*anyopaque, u64, u64, u64, [*]const u8, usize, c_int) callconv(.c) void = null,
    ensure_application: ?*const fn (?*anyopaque) callconv(.c) c_int = null,
    ensure_window: ?*const fn (?*anyopaque, u32, u32, [*:0]const u8) callconv(.c) c_int = null,
    show_window: ?*const fn (?*anyopaque) callconv(.c) c_int = null,
    pump_events: ?*const fn (?*anyopaque) callconv(.c) u32 = null,
    /// Run what other threads have queued for the host main thread - AppKit
    /// requests guest workers `dispatch_sync` to it - without dequeuing input.
    /// Installed as the main thread's park service, so every wait on the main
    /// thread keeps serving them (lib/concurrency/park.zig).
    service_main_thread: ?*const fn (?*anyopaque) callconv(.c) u32 = null,
    /// A separate context is intentional: the native presenter owns host
    /// Vulkan objects while the window callbacks own the native UI boundary.
    /// Neither context is ever written into guest memory.
    native_context: ?*anyopaque = null,
    native_presenter_start: ?*const fn (?*anyopaque, u32, u32) callconv(.c) c_int = null,
    native_presenter_stage: ?*const fn (?*anyopaque) callconv(.c) u32 = null,
    native_presenter_is_ready: ?*const fn (?*anyopaque) callconv(.c) c_int = null,
    native_presenter_present_diagnostic: ?*const fn (?*anyopaque, u64, u32, u32, u32) callconv(.c) u64 = null,
    /// Offer the console's own front buffer after a guest VdSwap.  The PE
    /// processor owns the Xenia address-space translation; the host graphics
    /// owner owns conversion and presentation.  Keeping this as a callback
    /// prevents a guest address or a host Vulkan object from crossing the ABI
    /// boundary accidentally.
    native_present_guest_frontbuffer: ?*const fn (?*anyopaque, *anyopaque, u64, u32, u32, c_int, u32, u32, c_int) callconv(.c) c_int = null,
    /// Optional real Vulkan dispatch supplied by the host-side Windows route.
    /// The callback receives the PE state as an opaque pointer and a bounded
    /// function-name slice. It may adapt the Microsoft x64 call into a native
    /// Rosetta forwarder, but it cannot pass a host pointer into guest memory.
    native_vulkan_dispatch: ?*const fn (?*anyopaque, *anyopaque, [*]const u8, usize, u64, c_int) callconv(.c) c_int = null,
    /// Return the host CAMetalLayer currently owned by the native window. The
    /// value is used only inside Rosetta's host Vulkan create-info and is never
    /// materialized as a guest handle.
    native_metal_layer_host_pointer: ?*const fn (?*anyopaque) callconv(.c) usize = null,
    /// Tell the window bridge whether a Vulkan swapchain now owns the
    /// `CAMetalLayer`'s `drawableSize`. Absent on a host with no AppKit
    /// bridge, where there is no layer to hand over.
    native_metal_drawable_owner: ?*const fn (?*anyopaque, c_int) callconv(.c) c_int = null,
    /// Prepare the layer's pixel extent immediately before the real Vulkan
    /// swapchain is created. This is separate from ownership: MoltenVK must
    /// see the intended drawable size during capability negotiation, while
    /// the bridge must not write it after the swapchain starts vending images.
    native_metal_drawable_prepare: ?*const fn (?*anyopaque, u32, u32) callconv(.c) c_int = null,
};

/// A host-neutral virtual controller snapshot. The first sixteen bytes match
/// XINPUT_STATE; the trailing fields are Rosetta diagnostics. The macOS bridge
/// combines focus-gated keyboard input with an optional physical GameController
/// snapshot, while the PE state owns serialization into the Win32 or Xbox ABI.
pub const WindowsInputState = extern struct {
    packet_number: u32 = 0,
    buttons: u16 = 0,
    left_trigger: u8 = 0,
    right_trigger: u8 = 0,
    thumb_lx: i16 = 0,
    thumb_ly: i16 = 0,
    thumb_rx: i16 = 0,
    thumb_ry: i16 = 0,
    connected: u32 = 0,
    focused: u32 = 0,
    key_down_events: u64 = 0,
    key_up_events: u64 = 0,
    snapshot_reads: u64 = 0,
    focus_gain_events: u64 = 0,
    focus_loss_events: u64 = 0,
    rejected_key_events: u64 = 0,
    last_key_code: u32 = 0,
    input_contract_version: u32 = 0,
    physical_controller_connected: u32 = 0,
    physical_controller_reserved: u32 = 0,
    physical_controller_events: u64 = 0,
    physical_controller_name: [64]u8 = [_]u8{0} ** 64,
};

pub const WindowsInputHooks = struct {
    context: ?*anyopaque = null,
    read_controller_state: ?*const fn (?*anyopaque, *WindowsInputState) callconv(.c) c_int = null,
};

comptime {
    std.debug.assert(@sizeOf(WindowsInputState) == 160);
    std.debug.assert(@offsetOf(WindowsInputState, "connected") == 16);
}

/// The host audio device, reached the same way the window is: optional C-ABI
/// callbacks installed by the runner.
///
/// Absent hooks are not a failure. The wave device Rosetta models works
/// without them - it just is not audible - and a test binary that has not
/// linked AudioToolbox must still be able to exercise the whole wave path.
pub const WindowsAudioHooks = struct {
    context: ?*anyopaque = null,
    /// Open the host device for a guest wave format. Non-zero on success.
    open: ?*const fn (?*anyopaque, u32, u32, u32, c_int) callconv(.c) c_int = null,
    /// Hand interleaved PCM to the device; returns the bytes accepted.
    submit: ?*const fn (?*anyopaque, [*]const u8, u32) callconv(.c) u32 = null,
    close: ?*const fn (?*anyopaque) callconv(.c) void = null,
    /// Callbacks the device has served. Zero proves the host never asked for
    /// audio, which is the one reading silence cannot supply on its own.
    callbacks_served: ?*const fn (?*anyopaque) callconv(.c) u64 = null,
    /// Bytes the device consumed and bytes dropped for back-pressure, packed
    /// as two out-parameters so a report can separate "behind" from "ahead".
    transfer_counters: ?*const fn (?*anyopaque, *u64, *u64, *u64) callconv(.c) void = null,
};
