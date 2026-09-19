#ifndef ROSETTE_MACHO_NATIVE_WINDOW_BRIDGE_H
#define ROSETTE_MACHO_NATIVE_WINDOW_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RosetteMachONativeWindowStatus {
  uintptr_t application;
  uintptr_t window;
  uintptr_t view;
  uintptr_t metal_layer;
  uintptr_t metal_device;
  uint32_t width;
  uint32_t height;
  uint32_t events_pumped;
  uint8_t application_ready;
  uint8_t window_ready;
  uint8_t layer_attached;
  uint8_t visible;
  uint8_t on_main_thread;
  uint8_t reserved[3];
} RosetteMachONativeWindowStatus;

// Everything about the on-screen chain that decides whether a presented
// swapchain image can actually be seen: the window's placement and visibility,
// the view's geometry and hidden state, and the layer's size, scale and
// attachment. A black window with a healthy present count is almost always one
// of these fields, and reading them from the host is the only way to tell
// which -- the Vulkan side reports success either way.
typedef struct RosetteMachONativeWindowGeometry {
  uintptr_t window;
  uintptr_t view;
  uintptr_t metal_layer;
  uintptr_t view_layer;
  uintptr_t layer_superlayer;
  uintptr_t layer_device;
  uintptr_t screen;

  double window_x;
  double window_y;
  double window_width;
  double window_height;
  double view_width;
  double view_height;
  double layer_width;
  double layer_height;
  double drawable_width;
  double drawable_height;
  double contents_scale;
  double backing_scale;
  double window_alpha;

  uint32_t layer_pixel_format;
  uint32_t maximum_drawable_count;
  uint32_t occlusion_state;

  uint8_t window_exists;
  uint8_t window_visible;
  uint8_t window_miniaturized;
  uint8_t window_on_screen;
  uint8_t window_key;
  uint8_t view_hidden;
  uint8_t view_hidden_or_ancestor;
  uint8_t view_wants_layer;
  uint8_t layer_is_view_layer;
  uint8_t layer_hidden;
  uint8_t layer_opaque;
  uint8_t layer_framebuffer_only;
  uint8_t layer_presents_with_transaction;
  uint8_t on_main_thread;
  uint8_t reserved[2];

  // The visible frame of the screen the window is on, in the same global
  // coordinate space as window_x/window_y. A window can be on a screen and
  // almost entirely outside the part of it a person can see; nothing above
  // distinguishes that from a window in the middle of the display.
  double screen_visible_x;
  double screen_visible_y;
  double screen_visible_width;
  double screen_visible_height;
  uint32_t screen_count;
  uint32_t reserved_screen;
} RosetteMachONativeWindowGeometry;

// A keyboard-backed virtual XInput/Xam controller. The first sixteen bytes
// intentionally match XINPUT_STATE; the trailing counters stay on the host
// side and make an input report actionable without exposing AppKit objects to
// the guest.
typedef struct RosetteMachOKeyboardControllerState {
  uint32_t packet_number;
  uint16_t buttons;
  uint8_t left_trigger;
  uint8_t right_trigger;
  int16_t thumb_lx;
  int16_t thumb_ly;
  int16_t thumb_rx;
  int16_t thumb_ry;
  uint32_t connected;
  uint32_t focused;
  uint64_t key_down_events;
  uint64_t key_up_events;
  uint64_t snapshot_reads;
  uint64_t focus_gain_events;
  uint64_t focus_loss_events;
  uint64_t rejected_key_events;
  uint32_t last_key_code;
  uint32_t input_contract_version;
} RosetteMachOKeyboardControllerState;
_Static_assert(sizeof(RosetteMachOKeyboardControllerState) == 80,
               "keyboard controller state must match the Zig input hook");

// The Zig mirror in lib/gpu/window_geometry.zig is filled by writing through
// a pointer to this type, so the two layouts have to be the same object. A
// field added on one side and not the other has no compiler that can see
// both; this pair of assertions is that compiler.
_Static_assert(sizeof(RosetteMachONativeWindowGeometry) == 232,
               "RosetteMachONativeWindowGeometry changed size; update the Zig "
               "mirror in lib/gpu/window_geometry.zig and both assertions");

// Fills `out` with the current chain. Returns 1 when a window exists, 0 when
// there is nothing to describe. Safe to call from any thread: the AppKit reads
// are dispatched to the main thread when necessary.
int rosette_macho_native_window_describe(RosetteMachONativeWindowGeometry *out);
int rosette_macho_native_window_read_controller_state(
    RosetteMachOKeyboardControllerState *out);

int rosette_macho_native_application_ensure(void);
int rosette_macho_native_window_ensure(uint32_t width, uint32_t height,
                                      const char *title);
int rosette_macho_native_window_set_title(const char *title);
int rosette_macho_native_window_set_size(uint32_t width, uint32_t height);
int rosette_macho_native_window_show(void);
int rosette_macho_native_window_hide(void);
int rosette_macho_native_window_set_fullscreen(int fullscreen);
int rosette_macho_native_window_attach_metal_layer(void);
// Hand the CAMetalLayer's drawableSize to the Vulkan driver, or take it back.
//
// A CAMetalLayer's drawableSize belongs to whoever vends its drawables. Once
// MoltenVK has created a swapchain on the layer, it sets drawableSize from
// the swapchain's imageExtent and treats any other write as the swapchain
// going out of date, so this bridge must stop touching it. Returns 1 when the
// ownership actually changed. Idempotent.
int rosette_macho_native_window_set_drawable_owner(int owned_by_swapchain);
int rosette_macho_native_window_drawable_owned_by_swapchain(void);
// Set the drawable extent before Vulkan creates a swapchain. This is a
// preflight operation: it never changes the NSWindow or view size, and it
// refuses to write a different extent while an existing swapchain owns the
// layer. Returns 1 only when the layer already has, or now has, the requested
// extent.
int rosette_macho_native_window_prepare_drawable_size(uint32_t width,
                                                      uint32_t height);
// A host-generated Metal clear. Proves the Cocoa/Metal boundary is alive and
// nothing else: no guest image, no Vulkan command, no guest swap. The name says
// diagnostic because a frame from here must never be counted as guest output.
uint64_t rosette_macho_native_window_present_diagnostic_frame(
    uint64_t serial, uint32_t width, uint32_t height, uint32_t stage);
// Present verified CPU-visible emulator pixels directly through the canonical
// CAMetalLayer. This is a fallback for an unavailable Vulkan presenter, not a
// CPU-instruction bridge: the caller must already have a complete semantic
// frame descriptor and readable bytes.
uint64_t rosette_macho_native_window_present_frame(
    uint64_t serial, const uint8_t *pixels, uint64_t source_length,
    uint32_t source_width, uint32_t source_height, uint64_t row_pitch,
    uint32_t format, uint8_t orientation, uint8_t fit);
// A copied, completed acquired-image readback. This NEVER takes a drawable
// from MoltenVK or counts as a guest/native Vulkan present. flags: PNG=1,
// independent opaque-RGB Cocoa preview=2, diagnostic +4 EV comparison=4,
// offline CPU replay (NOT Vulkan completion evidence)=8.
// Extended picture numbering=16: content_frame is read only with that flag.
// frame always remains the raw present/readback ID; content_frame=0 waits for
// a picture. Legacy 128-byte packets do not contain the appended field.
// Return bits: saved=1, previewed=2,
// failed=4. A closed preview stays closed; it does not quit the guest.
typedef struct RosetteMachOReadbackFrame {
  const uint8_t *pixels;
  uint64_t length, frame, swapchain, image, hash;
  uint32_t width, height, format, flags;
  uint64_t visible_pixels, bright_pixels, transparent_pixels;
  uint64_t rgb_sum[3];
  uint64_t rgb_different_pixels;
  uint8_t min_rgb[3], max_rgb[3], reserved[2];
  uint64_t content_frame;
} RosetteMachOReadbackFrame;
_Static_assert(sizeof(RosetteMachOReadbackFrame) == 136,
               "readback packet must match Vulkan frame_capture.zig");
_Static_assert(offsetof(RosetteMachOReadbackFrame, width) == 48 &&
               offsetof(RosetteMachOReadbackFrame, min_rgb) == 120 &&
               offsetof(RosetteMachOReadbackFrame, content_frame) == 128,
               "readback packet offsets must match Vulkan frame_capture.zig");
uint32_t rosette_macho_native_window_capture_frame(
    const RosetteMachOReadbackFrame *frame);
uint32_t rosette_macho_native_window_pump_events(void);
RosetteMachONativeWindowStatus rosette_macho_native_window_status(void);
void rosette_macho_native_window_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif
