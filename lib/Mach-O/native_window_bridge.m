#import "native_window_bridge.h"

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>

static void RosetteMachOUpdateMetalDrawable(void);

@interface RosetteMachOMetalView : NSView <CALayerDelegate>
@end

// AppKit's plain NSWindow may refuse key status for a window created by a
// background guest process.  That is harmless for a screenshot-only layer
// but fatal for the keyboard-backed XInput path: events never reach the view,
// so the guest sees a permanently connected controller with packet zero.  The
// subclass opts into normal key/main-window behavior; it does not change the
// level, activation policy, size lock, or the user's ability to move the
// window.
@interface RosetteMachOInputWindow : NSWindow
@end

// Intercept key events at the window boundary.  A guest-driven window can
// change first responder as AppKit processes clicks and menus; handling keys
// only in the metal view or in the polling loop therefore leaves a gap where
// AppKit beeps and discards the event before the virtual controller sees it.
static void RosetteMachOApplyKeyboardEvent(NSEvent *event, BOOL down);

@implementation RosetteMachOInputWindow

- (BOOL)canBecomeKeyWindow {
  return YES;
}

- (BOOL)canBecomeMainWindow {
  return YES;
}

- (void)sendEvent:(NSEvent *)event {
  if (event.window == self &&
      (event.type == NSEventTypeKeyDown || event.type == NSEventTypeKeyUp)) {
    RosetteMachOApplyKeyboardEvent(event, event.type == NSEventTypeKeyDown);
    // The keyboard is a virtual XInput device, not an AppKit text target.
    // Consuming the event here prevents NSResponder's unhandled-key beep and
    // makes the result independent of which content view is first responder.
    return;
  }
  [super sendEvent:event];
}

@end

@implementation RosetteMachOMetalView

- (CALayer *)makeBackingLayer {
  return [CAMetalLayer layer];
}

- (void)viewDidChangeBackingProperties {
  [super viewDidChangeBackingProperties];
  // AppKit may revisit a layer's backing properties when the window moves
  // between displays. Re-apply the explicit Rosette extent at that boundary;
  // the function is owner-aware and therefore never fights a live Vulkan
  // swapchain.
  RosetteMachOUpdateMetalDrawable();
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (BOOL)becomeFirstResponder {
  return YES;
}

- (void)mouseDown:(NSEvent *)event {
  NSWindow *window = self.window;
  if (window != nil) {
    // A content click is the user's explicit request to interact. This is
    // deliberately not done during creation: the emulator may start behind
    // another application, but clicking it must behave like any normal Cocoa
    // window and make keyboard delivery possible.
    if (!window.isKeyWindow) {
      // This is an explicit user gesture.  Passing NO leaves a background
      // Rosetta process inactive on macOS, so AppKit can play its blocked
      // action sound while the window still appears to have been clicked.
      // Do not use this during creation: the launch path is intentionally
      // allowed to start behind another application.
      [NSApp activateIgnoringOtherApps:YES];
      [window makeKeyAndOrderFront:nil];
    }
    [window makeFirstResponder:self];
  }
  [super mouseDown:event];
}

@end

static NSApplication *g_application;
static NSWindow *g_window;
static RosetteMachOMetalView *g_view;
static CAMetalLayer *g_metal_layer;
static id<MTLDevice> g_metal_device;
static id<MTLCommandQueue> g_metal_command_queue;
static uint32_t g_width = 1280;
static uint32_t g_height = 720;
// Logical AppKit content size. This is intentionally not the same state as
// g_width/g_height: those two report the current CAMetalLayer drawable pixels,
// while this pair is the fixed window contract in points. A Retina backing
// scale or a Vulkan swapchain extent must never resize this window.
static const uint32_t kRosetteLockedWindowWidth = 1280u;
static const uint32_t kRosetteLockedWindowHeight = 720u;
static uint32_t g_events_pumped;
static BOOL g_fullscreen;
static BOOL g_reported_off_main_thread;
static uint64_t g_diagnostic_frames_presented;
static uint64_t g_guest_frames_presented;
static uint64_t g_foreground_reassertions;
static uint64_t g_window_placement_repairs;
static uint64_t g_window_placement_repair_failures;
// The current Xenia admission contract is an exact 1280x720 drawable.  Keep
// this separate from the window's backing scale: a Retina display may still
// report a 2x backing scale, but allowing that scale to flow into a
// CAMetalLayer whose swapchain is required to be 1280x720 creates the exact
// 2560x1440-vs-1280x720 split that the Vulkan driver otherwise accepts.
static const CGFloat kRosetteLockedDrawableContentsScale = 1.0;
static BOOL g_drawable_contract_active = NO;
static uint32_t g_drawable_contract_width;
static uint32_t g_drawable_contract_height;
static uint64_t g_window_size_lock_repairs;
static uint64_t g_window_size_lock_refusals;
static uint64_t g_fullscreen_lock_refusals;
static uint64_t g_window_hide_refusals;
static BOOL g_reported_placement_policy;
// CPU readback preview is a separate Cocoa window, never another consumer of
// MoltenVK's CAMetalLayer. Closing it must not become a guest WM_QUIT.
static NSWindow *g_readback_window;
static NSImageView *g_readback_view;
static NSImageView *g_readback_exposure_view;
static BOOL g_readback_closed;
static NSString *g_readback_directory;
static uint64_t g_readback_saved;

// Keyboard-to-controller state is deliberately a tiny host-side model. The
// guest sees only the value packet copied by the Zig callback; AppKit objects,
// NSEvents and the lock never cross that boundary. The event pump owns all
// mutations, while XInput/Xam polls may arrive from a guest worker thread.
static pthread_mutex_t g_keyboard_lock = PTHREAD_MUTEX_INITIALIZER;
static BOOL g_keyboard_keys[128];
static BOOL g_keyboard_window_available;
static BOOL g_keyboard_focused;
static uint32_t g_keyboard_packet;
static uint64_t g_keyboard_key_down_events;
static uint64_t g_keyboard_key_up_events;
static uint64_t g_keyboard_snapshot_reads;
static uint64_t g_keyboard_focus_gain_events;
static uint64_t g_keyboard_focus_loss_events;
static uint64_t g_keyboard_rejected_key_events;
static uint32_t g_keyboard_last_key_code;
static BOOL g_reported_keyboard_mapping;

// A press must outlive the guest's polling interval. At a few frames a second
// the guest samples its controllers once per frame, so a 100 ms tap lands
// between two samples and the title never sees it. Each down edge therefore
// latches the key until the presented frame count has advanced twice, which
// spans at least one whole inter-frame interval and so at least one poll. The
// wall-clock cap keeps a key from sticking if presents stop, and without a
// frame clock (a route that never presents through Vulkan) the latch is a
// short fixed hold instead.
static const uint64_t kRosetteKeyboardLatchFrames = 2u;
static const uint64_t kRosetteKeyboardLatchCapNs = 3000000000ull;
static const uint64_t kRosetteKeyboardLatchNoClockNs = 150000000ull;
static _Atomic uint64_t g_guest_frame_clock;
static BOOL g_keyboard_latched[128];
static uint64_t g_keyboard_press_frame[128];
static uint64_t g_keyboard_press_ns[128];
// The last state handed out, so a latch that expires between two physical
// events still changes the packet number. XInput callers may skip a packet
// they have already seen.
static uint16_t g_keyboard_reported_buttons;
static uint8_t g_keyboard_reported_triggers[2];
static int16_t g_keyboard_reported_axes[4];

static void RosetteMachOClearKeyboardStateLocked(void) {
  memset(g_keyboard_keys, 0, sizeof(g_keyboard_keys));
  memset(g_keyboard_latched, 0, sizeof(g_keyboard_latched));
}

static void RosetteMachOUpdateKeyboardFocusOnMainThread(void) {
  if (!g_window) {
    pthread_mutex_lock(&g_keyboard_lock);
    if (g_keyboard_focused) {
      ++g_keyboard_focus_loss_events;
      ++g_keyboard_packet;
    }
    g_keyboard_window_available = NO;
    g_keyboard_focused = NO;
    RosetteMachOClearKeyboardStateLocked();
    pthread_mutex_unlock(&g_keyboard_lock);
    return;
  }

  const BOOL focused = g_window.isKeyWindow;
  pthread_mutex_lock(&g_keyboard_lock);
  if (focused && !g_keyboard_focused) {
    ++g_keyboard_focus_gain_events;
    ++g_keyboard_packet;
  }
  if (!focused && g_keyboard_focused) {
    // AppKit may not deliver key-up events after focus leaves the window. Do
    // not leak a stuck virtual button into the next foreground interval.
    ++g_keyboard_focus_loss_events;
    ++g_keyboard_packet;
    RosetteMachOClearKeyboardStateLocked();
  }
  g_keyboard_window_available = YES;
  g_keyboard_focused = focused;
  pthread_mutex_unlock(&g_keyboard_lock);
}

static void RosetteMachOApplyKeyboardEvent(NSEvent *event, BOOL down) {
  if (!event || !g_window || event.window != g_window) {
    pthread_mutex_lock(&g_keyboard_lock);
    ++g_keyboard_rejected_key_events;
    pthread_mutex_unlock(&g_keyboard_lock);
    return;
  }
  const NSUInteger key_code = event.keyCode;
  if (key_code >= 128u) {
    pthread_mutex_lock(&g_keyboard_lock);
    ++g_keyboard_rejected_key_events;
    pthread_mutex_unlock(&g_keyboard_lock);
    return;
  }
  pthread_mutex_lock(&g_keyboard_lock);
  g_keyboard_last_key_code = (uint32_t)key_code;
  const BOOL was_down = g_keyboard_keys[key_code];
  if (down) {
    // Holding a key produces AppKit repeat events; a controller packet should
    // change on the transition, not on every repeat notification.
    if (!was_down) {
      g_keyboard_keys[key_code] = YES;
      g_keyboard_latched[key_code] = YES;
      g_keyboard_press_frame[key_code] =
          atomic_load_explicit(&g_guest_frame_clock, memory_order_relaxed);
      g_keyboard_press_ns[key_code] = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
      ++g_keyboard_packet;
      ++g_keyboard_key_down_events;
    }
  } else if (was_down) {
    g_keyboard_keys[key_code] = NO;
    ++g_keyboard_packet;
    ++g_keyboard_key_up_events;
  }
  pthread_mutex_unlock(&g_keyboard_lock);
}

static BOOL RosetteMachOKeyboardKeyDownLocked(NSUInteger key_code) {
  if (key_code >= 128u) return NO;
  if (g_keyboard_keys[key_code]) return YES;
  if (!g_keyboard_latched[key_code]) return NO;
  const uint64_t clock =
      atomic_load_explicit(&g_guest_frame_clock, memory_order_relaxed);
  const uint64_t held_ns =
      clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - g_keyboard_press_ns[key_code];
  const BOOL frame_clock_running = clock != 0u;
  const BOOL still_latched =
      frame_clock_running
          ? (clock - g_keyboard_press_frame[key_code] <
                 kRosetteKeyboardLatchFrames &&
             held_ns < kRosetteKeyboardLatchCapNs)
          : held_ns < kRosetteKeyboardLatchNoClockNs;
  if (!still_latched) {
    g_keyboard_latched[key_code] = NO;
    return NO;
  }
  return YES;
}

static BOOL RosetteMachOAnyKeyDownLocked(const uint16_t *key_codes,
                                         size_t count) {
  BOOL down = NO;
  // Evaluate every key: the lookup also retires expired latches.
  for (size_t i = 0; i < count; ++i) {
    if (RosetteMachOKeyboardKeyDownLocked(key_codes[i])) down = YES;
  }
  return down;
}

static int16_t RosetteMachOAxisLocked(NSUInteger negative_key, NSUInteger positive_key) {
  const BOOL negative = RosetteMachOKeyboardKeyDownLocked(negative_key);
  const BOOL positive = RosetteMachOKeyboardKeyDownLocked(positive_key);
  if (negative == positive) return 0;
  return negative ? (int16_t)-32767 : (int16_t)32767;
}

@interface RosetteReadbackWindowDelegate : NSObject <NSWindowDelegate>
@end
@implementation RosetteReadbackWindowDelegate
- (void)windowWillClose:(NSNotification *)notification {
  (void)notification;
  g_readback_closed = YES;
}
@end
static RosetteReadbackWindowDelegate *g_readback_delegate;

static const uint32_t kRosetteDefaultWindowWidth = kRosetteLockedWindowWidth;
static const uint32_t kRosetteDefaultWindowHeight = kRosetteLockedWindowHeight;
static const uint32_t kRosetteMaxWindowDimension = 16u * 1024u;
static const CGFloat kRosetteMinimumOnScreenFraction = 0.999;

static uint32_t RosetteMachONormalizeWindowDimension(uint32_t requested,
                                                     uint32_t fallback) {
  // CW_USEDEFAULT is 0x80000000. It is a placement sentinel in Win32, not a
  // dimension. The upper bound keeps malformed guest values from becoming an
  // enormous NSWindow frame and gives the caller a stable, visible fallback.
  if (requested == 0u || requested == 0x80000000u ||
      requested > kRosetteMaxWindowDimension) {
    return fallback;
  }
  return requested;
}

static BOOL RosetteMachOHasFinitePositiveRect(NSRect rect) {
  return isfinite((double)NSMinX(rect)) && isfinite((double)NSMinY(rect)) &&
         isfinite((double)NSWidth(rect)) && isfinite((double)NSHeight(rect)) &&
         NSWidth(rect) > 0.0 && NSHeight(rect) > 0.0;
}

static BOOL RosetteMachOEnsureWindowOnMainThread(uint32_t width,
                                                 uint32_t height,
                                                 NSString *title);

static void RosetteMachOEnforceLockedWindowSizeOnMainThread(const char *reason);

static CGFloat RosetteMachOClamp(CGFloat value, CGFloat low, CGFloat high) {
  if (high < low) {
    return low;
  }
  if (value < low) {
    return low;
  }
  if (value > high) {
    return high;
  }
  return value;
}

static void RosetteMachOPlaceWindowSafely(void) {
  if (!g_window) {
    return;
  }
  const NSRect frame = g_window.frame;
  // The main screen first: that is where the keyboard focus is, which is
  // where the user is looking. `g_window.screen` at creation time is only
  // whichever screen AppKit's default placement happened to overlap, and
  // centring on that puts the window on a display the user may not be
  // watching.
  NSScreen *screen = [NSScreen mainScreen] ?: g_window.screen;
  if (screen && RosetteMachOHasFinitePositiveRect(screen.visibleFrame) &&
      RosetteMachOHasFinitePositiveRect(frame)) {
    const NSRect visible = screen.visibleFrame;
    CGFloat x = NSMidX(visible) - NSWidth(frame) * 0.5;
    CGFloat y = NSMidY(visible) - NSHeight(frame) * 0.5;
    // Centring alone does not guarantee the window is on the display: a
    // frame wider or taller than the visible area, or a visible area whose
    // origin is negative on a multi-display arrangement, both put the
    // centred origin outside it. AppKit reports such a window as visible,
    // on screen and unoccluded, and a person sees a sliver of it or none.
    // Clamping keeps the whole frame inside when it fits, and pins it to the
    // corner nearest the user when it does not.
    x = RosetteMachOClamp(x, NSMinX(visible), NSMaxX(visible) - NSWidth(frame));
    y = RosetteMachOClamp(y, NSMinY(visible), NSMaxY(visible) - NSHeight(frame));
    if (isfinite((double)x) && isfinite((double)y)) {
      [g_window setFrameOrigin:NSMakePoint(x, y)];
      return;
    }
  }
  // A headless or not-yet-attached WindowServer may not expose a screen. A
  // finite origin is still valid and avoids NSWindow's internal centered-frame
  // sentinel (`INT_MIN`) while the application is becoming visible.
  [g_window setFrameOrigin:NSMakePoint(0.0, 0.0)];
}

/// Keep movement independent from the fixed logical content and drawable
/// contracts. A min/max content size prevents resizing, while the normal
/// title-bar movement remains available so the drawable follows the window.
/// The repair path is retained as a guard for an AppKit restoration or a drag
/// that leaves almost the entire frame outside the screen.
static void RosetteMachOConfigureWindowPlacementPolicyOnMainThread(void) {
  if (!g_window) {
    return;
  }
  g_window.movable = YES;
  g_window.movableByWindowBackground = NO;
  if (!g_reported_placement_policy) {
    fprintf(stderr,
            "macho-processor: WINDOW PLACEMENT POLICY: mode=user_movable movable=true movable_by_background=false logical_content=1280x720 drawable=independent repair_path=retained offscreen_guard=retained\n");
    g_reported_placement_policy = YES;
  }
}

static CGFloat RosetteMachOVisibleWindowFraction(NSRect frame,
                                                 NSRect visible_frame) {
  if (!RosetteMachOHasFinitePositiveRect(frame) ||
      !RosetteMachOHasFinitePositiveRect(visible_frame)) {
    return 0.0;
  }
  const CGFloat frame_area = NSWidth(frame) * NSHeight(frame);
  if (!(frame_area > 0.0) || !isfinite((double)frame_area)) {
    return 0.0;
  }
  const NSRect intersection = NSIntersectionRect(frame, visible_frame);
  const CGFloat intersection_area =
      MAX(NSWidth(intersection), 0.0) * MAX(NSHeight(intersection), 0.0);
  if (!(intersection_area > 0.0) || !isfinite((double)intersection_area)) {
    return 0.0;
  }
  return MIN(intersection_area / frame_area, 1.0);
}

/// AppKit's `visible`, `screen` and occlusion fields can all be true while a
/// window has only a small corner inside the screen's visibleFrame. That is a
/// real presentation failure for the standalone Xenia window: Vulkan still
/// accepts and completes the present, but the user cannot see the drawable.
/// Repair only placement, never size or drawable ownership, and only when the
/// whole frame can fit in the visible area. This keeps the strict 1280x720
/// drawable contract independent from the host window placement policy.
static void RosetteMachORepairWindowPlacementIfNeeded(void) {
  if (!g_window || g_fullscreen) {
    return;
  }

  const NSRect frame = g_window.frame;
  NSScreen *screen = g_window.screen ?: [NSScreen mainScreen];
  if (!screen) {
    ++g_window_placement_repair_failures;
    const uint64_t count = g_window_placement_repair_failures;
    if (count <= 4u || (count & (count - 1u)) == 0u) {
      fprintf(stderr,
              "macho-processor: WINDOW PLACEMENT REPAIR failed: reason=no_screen frame=%.0fx%.0f@%.0f,%.0f failures=%llu\n",
              (double)NSWidth(frame), (double)NSHeight(frame),
              (double)NSMinX(frame), (double)NSMinY(frame),
              (unsigned long long)count);
    }
    return;
  }

  const NSRect visible = screen.visibleFrame;
  if (!RosetteMachOHasFinitePositiveRect(frame) ||
      !RosetteMachOHasFinitePositiveRect(visible)) {
    ++g_window_placement_repair_failures;
    const uint64_t count = g_window_placement_repair_failures;
    if (count <= 4u || (count & (count - 1u)) == 0u) {
      fprintf(stderr,
              "macho-processor: WINDOW PLACEMENT REPAIR failed: reason=invalid_geometry frame=%.0fx%.0f@%.0f,%.0f visible=%.0fx%.0f@%.0f,%.0f failures=%llu\n",
              (double)NSWidth(frame), (double)NSHeight(frame),
              (double)NSMinX(frame), (double)NSMinY(frame),
              (double)NSWidth(visible), (double)NSHeight(visible),
              (double)NSMinX(visible), (double)NSMinY(visible),
              (unsigned long long)count);
    }
    return;
  }

  const CGFloat before_fraction =
      RosetteMachOVisibleWindowFraction(frame, visible);
  if (before_fraction >= kRosetteMinimumOnScreenFraction) {
    return;
  }

  CGFloat x = RosetteMachOClamp(NSMinX(frame), NSMinX(visible),
                                NSMaxX(visible) - NSWidth(frame));
  CGFloat y = RosetteMachOClamp(NSMinY(frame), NSMinY(visible),
                                NSMaxY(visible) - NSHeight(frame));
  if (!isfinite((double)x) || !isfinite((double)y)) {
    ++g_window_placement_repair_failures;
    const uint64_t count = g_window_placement_repair_failures;
    if (count <= 4u || (count & (count - 1u)) == 0u) {
      fprintf(stderr,
              "macho-processor: WINDOW PLACEMENT REPAIR failed: reason=nonfinite_clamp before_fraction=%.0f%% failures=%llu\n",
              (double)(before_fraction * 100.0), (unsigned long long)count);
    }
    return;
  }

  // If the window itself is larger than the screen, clamping has no better
  // origin to offer. Avoid repeatedly setting the same origin on every
  // diagnostic poll; the resulting fraction remains truthful in the next
  // geometry report.
  if (fabs((double)x - (double)NSMinX(frame)) < 0.5 &&
      fabs((double)y - (double)NSMinY(frame)) < 0.5) {
    return;
  }

  [g_window setFrameOrigin:NSMakePoint(x, y)];
  const NSRect repaired = g_window.frame;
  const CGFloat after_fraction =
      RosetteMachOVisibleWindowFraction(repaired, visible);
  ++g_window_placement_repairs;
  fprintf(stderr,
          "macho-processor: WINDOW PLACEMENT REPAIR: reason=outside_visible_frame before=%.0fx%.0f@%.0f,%.0f visible_fraction=%.0f%% after=%.0fx%.0f@%.0f,%.0f visible_fraction=%.0f%% screen=%.0fx%.0f@%.0f,%.0f repairs=%llu result=%s\n",
          (double)NSWidth(frame), (double)NSHeight(frame),
          (double)NSMinX(frame), (double)NSMinY(frame),
          (double)(before_fraction * 100.0), (double)NSWidth(repaired),
          (double)NSHeight(repaired), (double)NSMinX(repaired),
          (double)NSMinY(repaired), (double)(after_fraction * 100.0),
          (double)NSWidth(visible), (double)NSHeight(visible),
          (double)NSMinX(visible), (double)NSMinY(visible),
          (unsigned long long)g_window_placement_repairs,
          after_fraction >= kRosetteMinimumOnScreenFraction ? "on_screen"
                                                             : "still_partial");
}

static void RosetteMachOConfigureOrdinaryWindowPolicy(void) {
  if (!g_window) {
    return;
  }

  // Occlusion and minimization are user choices, not graphics faults to
  // repair by taking focus. A swapchain must not make the application float
  // above other programs or follow the user into every Space.
  g_window.level = NSNormalWindowLevel;
  g_window.collectionBehavior = NSWindowCollectionBehaviorDefault;
  g_window.hidesOnDeactivate = NO;
}

static void RosetteMachOShowWindowOnMainThread(const char *reason) {
  if (!g_window || !g_application) {
    return;
  }

  RosetteMachOConfigureOrdinaryWindowPolicy();
  if (g_window.isMiniaturized) {
    [g_window deminiaturize:nil];
  }
  // Only creation or an explicit guest ShowWindow reaches here. Neither
  // event is permission to activate over the user's currently focused app.
  // `orderFront:` is ignored for a background application on some AppKit
  // paths, which left the swapchain fully alive but the host window absent
  // from the screen. `orderFrontRegardless` performs the non-activating
  // ordering operation we need: it does not make the window always-on-top,
  // key, or immovable, and the user can still put another application above
  // it normally.
  [g_window orderFrontRegardless];
  RosetteMachOPlaceWindowSafely();
  RosetteMachOUpdateMetalDrawable();
  ++g_foreground_reassertions;
  const uint64_t count = g_foreground_reassertions;
  const BOOL sparse_report = count <= 4u || (count & (count - 1u)) == 0u;
  if (sparse_report) {
    fprintf(stderr,
            "macho-processor: AppKit window shown: reason=%s count=%llu "
            "level=normal ordering=front_regardless activation=unchanged "
            "visible=%d on_screen=%d key=%d occlusion=%lu "
            "occlusion_policy=user_owned\n",
            reason ? reason : "unspecified", (unsigned long long)count,
            g_window.isVisible ? 1 : 0, g_window.screen != nil ? 1 : 0,
            g_window.isKeyWindow ? 1 : 0,
            (unsigned long)g_window.occlusionState);
  }
}

static void RosetteMachORunOnMainThreadSync(dispatch_block_t block) {
  if (![NSThread isMainThread]) {
    if (!g_reported_off_main_thread) {
      fprintf(stderr,
              "macho-processor: native AppKit bridge marshaling an off-main-"
              "thread request to the main runloop\n");
      g_reported_off_main_thread = YES;
    }
    // A Vulkan Metal-surface request can originate from a guest worker while
    // the cooperative scheduler has parked the guest UI continuation.  AppKit
    // and CAMetalLayer must still be touched on the host main runloop.  Do not
    // silently drop that request: dispatch it synchronously so its completion
    // is observed before the guest worker is allowed to continue.
    dispatch_sync(dispatch_get_main_queue(), block);
    return;
  }
  block();
}

// Whether a VkSwapchainKHR is live on the layer.
//
// `drawableSize` belongs to whoever vends the drawables. Before a swapchain
// exists that is this bridge, which sizes the layer so the window is sane and
// the host diagnostic clear has somewhere to go. From the moment MoltenVK
// creates a swapchain on the layer it is MoltenVK's: it sets drawableSize to
// the swapchain's imageExtent, watches the property, and treats a change it
// did not make as the swapchain going out of date.
//
// This bridge used to write drawableSize from every event pump - which the
// guest's message loop calls once per GetMessage - so on the 2026-09-11 run
// the layer read 2560x1440 while the guest's swapchain was 1280x720, for the
// whole run. Fighting the driver for a property it owns cannot make a frame
// appear and can stop one.
static BOOL g_drawable_owned_by_swapchain = NO;

static BOOL RosetteMachOContentSizeMatchesLocked(void) {
  if (!g_window) {
    return YES;
  }
  const NSRect content_rect =
      [g_window contentRectForFrameRect:g_window.frame];
  return fabs((double)NSWidth(content_rect) -
                  (double)kRosetteLockedWindowWidth) < 0.5 &&
         fabs((double)NSHeight(content_rect) -
                  (double)kRosetteLockedWindowHeight) < 0.5;
}

/// Keep the logical window fixed even if an external AppKit action or a stale
/// guest resize request changed its content rectangle. This is a repair of the
/// host contract, not a resize policy: guest `set_size` and fullscreen calls
/// are rejected below, while this path repairs the one accidental/external
/// drift that caused the observed 1280x722 layer.
static void RosetteMachOEnforceLockedWindowSizeOnMainThread(const char *reason) {
  if (!g_window || g_fullscreen || RosetteMachOContentSizeMatchesLocked()) {
    return;
  }

  const NSRect before =
      [g_window contentRectForFrameRect:g_window.frame];
  [g_window setContentSize:NSMakeSize((CGFloat)kRosetteLockedWindowWidth,
                                      (CGFloat)kRosetteLockedWindowHeight)];
  if (g_view) {
    // The content view is deliberately not autoresizable. Set its frame size
    // after AppKit applies the window content rectangle so a stale backing
    // layout cannot leave the layer at 1280x722 while the window says 720p.
    [g_view setFrameSize:NSMakeSize((CGFloat)kRosetteLockedWindowWidth,
                                   (CGFloat)kRosetteLockedWindowHeight)];
    [g_view setBoundsSize:NSMakeSize((CGFloat)kRosetteLockedWindowWidth,
                                     (CGFloat)kRosetteLockedWindowHeight)];
  }
  const NSRect after =
      [g_window contentRectForFrameRect:g_window.frame];
  const BOOL repaired = RosetteMachOContentSizeMatchesLocked() &&
                        (!g_view ||
                         (fabs((double)NSWidth(g_view.bounds) -
                               (double)kRosetteLockedWindowWidth) < 0.5 &&
                          fabs((double)NSHeight(g_view.bounds) -
                               (double)kRosetteLockedWindowHeight) < 0.5));
  if (repaired) {
    ++g_window_size_lock_repairs;
  }
  fprintf(stderr,
          "macho-processor: WINDOW SIZE LOCK: decision=%s reason=%s "
          "before=%.0fx%.0f requested=%ux%u after=%.0fx%.0f "
          "repairs=%llu refusals=%llu fullscreen_refusals=%llu\n",
          repaired ? "repaired" : "repair_failed", reason ? reason : "unspecified",
          (double)NSWidth(before), (double)NSHeight(before),
          (unsigned)kRosetteLockedWindowWidth,
          (unsigned)kRosetteLockedWindowHeight, (double)NSWidth(after),
          (double)NSHeight(after), (unsigned long long)g_window_size_lock_repairs,
          (unsigned long long)g_window_size_lock_refusals,
          (unsigned long long)g_fullscreen_lock_refusals);
}

static void RosetteMachOUpdateMetalDrawable(void) {
  if (!g_window || !g_view || !g_metal_layer) {
    return;
  }
  RosetteMachOEnforceLockedWindowSizeOnMainThread("drawable_update");
  const CGFloat backing_scale = MAX(g_window.backingScaleFactor, 1.0);
  const NSRect bounds = g_view.bounds;
  // `drawableSize` is already expressed in pixels. Multiplying the content
  // size by the Retina backing scale here silently turns the default
  // 1280x720 guest surface into a 2560x1440 swapchain target before MoltenVK
  // has seen the guest's extent. The strict 720p phase pins contentsScale to
  // 1.0 as well as drawableSize so AppKit cannot re-derive a 2x drawable while
  // Vulkan is negotiating the surface. The backing scale is retained only as
  // an observation in the geometry report; it is not an output-size input.
  const uint32_t bounds_width =
      (uint32_t)MAX(ceil(MAX(bounds.size.width, 1.0)), 1.0);
  const uint32_t bounds_height =
      (uint32_t)MAX(ceil(MAX(bounds.size.height, 1.0)), 1.0);
  const uint32_t drawable_width =
      g_drawable_contract_active ? g_drawable_contract_width : bounds_width;
  const uint32_t drawable_height =
      g_drawable_contract_active ? g_drawable_contract_height : bounds_height;
  g_metal_layer.frame = bounds;
  // `drawableSize` is documented as an explicit pixel size, but the
  // CAMetalLayer/AppKit path can re-derive it from bounds*contentsScale while
  // a layer is being attached or its backing properties are changing.  The
  // strict 720p phase therefore pins both inputs: contentsScale is not used
  // as an output multiplier, and the display's native backing scale remains
  // diagnostic-only.  Upscaling can be introduced later as a distinct,
  // negotiated contract rather than appearing accidentally here.
  g_metal_layer.contentsScale = kRosetteLockedDrawableContentsScale;
  if (!g_drawable_owned_by_swapchain) {
    g_metal_layer.drawableSize =
        CGSizeMake((CGFloat)drawable_width, (CGFloat)drawable_height);
  }
  g_width = drawable_width;
  g_height = drawable_height;
  (void)backing_scale;
}

int rosette_macho_native_window_set_drawable_owner(int owned_by_swapchain) {
  __block BOOL changed = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      const BOOL requested = owned_by_swapchain != 0;
      changed = requested != g_drawable_owned_by_swapchain;
      g_drawable_owned_by_swapchain = requested;
      if (!requested) {
        // A later window admission starts a new contract from its logical
        // bounds.  Never let a stale guest extent leak into that session.
        g_drawable_contract_active = NO;
        g_drawable_contract_width = 0;
        g_drawable_contract_height = 0;
        RosetteMachOUpdateMetalDrawable();
      }
    });
  }
  return changed ? 1 : 0;
}

int rosette_macho_native_window_drawable_owned_by_swapchain(void) {
  __block BOOL owned = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      owned = g_drawable_owned_by_swapchain;
    });
  }
  return owned ? 1 : 0;
}

int rosette_macho_native_window_prepare_drawable_size(uint32_t width,
                                                      uint32_t height) {
  if (width == 0u || height == 0u || width > kRosetteMaxWindowDimension ||
      height > kRosetteMaxWindowDimension || width == 0x80000000u ||
      height == 0x80000000u) {
    return 0;
  }

  __block BOOL prepared = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (!RosetteMachOEnsureWindowOnMainThread(g_width, g_height, nil) ||
          !g_metal_layer) {
        return;
      }

      const CGSize requested = CGSizeMake((CGFloat)width, (CGFloat)height);
      const CGSize current = g_metal_layer.drawableSize;
      if (g_drawable_owned_by_swapchain) {
        // The old owner remains authoritative during a live swapchain. A
        // same-size recreate is safe and needs no write; a different request
        // is reported as a refusal instead of racing the driver's drawable
        // pool and manufacturing an out-of-date swapchain.
        prepared = fabs((double)current.width - (double)width) < 0.5 &&
                   fabs((double)current.height - (double)height) < 0.5;
        if (!prepared) {
          fprintf(stderr,
                  "macho-processor: CAMetalLayer drawable preflight refused: "
                  "owner=vulkan_swapchain current=%ux%u requested=%ux%u\n",
                  (unsigned)current.width, (unsigned)current.height,
                  (unsigned)width, (unsigned)height);
        }
        return;
      }

      g_drawable_contract_active = NO;
      g_metal_layer.drawableSize = requested;
      const CGSize actual = g_metal_layer.drawableSize;
      prepared = fabs((double)actual.width - (double)width) < 0.5 &&
                 fabs((double)actual.height - (double)height) < 0.5;
      if (prepared) {
        // Keep the exact size stable across the native-presenter capability
        // queries that follow this call.  Without a persistent contract an
        // intervening AppKit layout pass can put the layer back on its bounds
        // or its backing scale before vkCreateSwapchainKHR sees it.
        g_drawable_contract_width = width;
        g_drawable_contract_height = height;
        g_drawable_contract_active = YES;
      }
      fprintf(stderr,
              "macho-processor: CAMetalLayer drawable preflight: owner=%s "
              "requested=%ux%u actual=%ux%u contentsScale=%.2f backingScale=%.2f result=%s\n",
              g_drawable_owned_by_swapchain ? "vulkan_swapchain"
                                            : "rosette_window_bridge",
              (unsigned)width, (unsigned)height, (unsigned)actual.width,
              (unsigned)actual.height, (double)g_metal_layer.contentsScale,
              (double)g_window.backingScaleFactor,
              prepared ? "ready" : "mismatch");
    });
  }
  return prepared ? 1 : 0;
}

static BOOL RosetteMachOEnsureApplicationOnMainThread(void) {
  if (g_application) {
    return YES;
  }
  g_application = [NSApplication sharedApplication];
  if (!g_application) {
    return NO;
  }
  [g_application setActivationPolicy:NSApplicationActivationPolicyRegular];
  [g_application finishLaunching];
  return YES;
}

static BOOL RosetteMachOEnsureWindowOnMainThread(uint32_t width,
                                                 uint32_t height,
                                                 NSString *title) {
  if (!RosetteMachOEnsureApplicationOnMainThread()) {
    return NO;
  }
  if (g_window && g_view && g_metal_layer && g_metal_device) {
    RosetteMachOConfigureWindowPlacementPolicyOnMainThread();
    if (title.length) {
      g_window.title = title;
    }
    RosetteMachOEnforceLockedWindowSizeOnMainThread("ensure");
    return YES;
  }

  const uint32_t requested_width = RosetteMachONormalizeWindowDimension(
      width, kRosetteDefaultWindowWidth);
  const uint32_t requested_height = RosetteMachONormalizeWindowDimension(
      height, kRosetteDefaultWindowHeight);
  if (requested_width != kRosetteLockedWindowWidth ||
      requested_height != kRosetteLockedWindowHeight) {
    fprintf(stderr,
            "macho-processor: WINDOW SIZE LOCK: decision=clamped "
            "operation=ensure requested=%ux%u admitted=%ux%u "
            "logical_content_points=locked drawable_pixels=independent\n",
            (unsigned)requested_width, (unsigned)requested_height,
            (unsigned)kRosetteLockedWindowWidth,
            (unsigned)kRosetteLockedWindowHeight);
  }
  // g_width/g_height describe the drawable before a Vulkan owner takes over;
  // the AppKit content rectangle below is always the fixed logical contract.
  g_width = kRosetteLockedWindowWidth;
  g_height = kRosetteLockedWindowHeight;
  const NSRect content_rect = NSMakeRect(0.0, 0.0, g_width, g_height);
  const NSWindowStyleMask style = NSWindowStyleMaskTitled |
                                  NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable;
  g_window = [[RosetteMachOInputWindow alloc] initWithContentRect:content_rect
                                                          styleMask:style
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
  if (!g_window) {
    return NO;
  }
  g_window.releasedWhenClosed = NO;
  g_window.title = title.length ? title : @"Xenia Canary (Rosette)";
  g_window.acceptsMouseMovedEvents = YES;
  g_window.tabbingMode = NSWindowTabbingModeDisallowed;
  // There is no resize affordance, and the min/max content contract also
  // protects against programmatic AppKit resizing. Fullscreen is disabled
  // below because it is itself a size transition.
  g_window.contentMinSize =
      NSMakeSize((CGFloat)kRosetteLockedWindowWidth,
                 (CGFloat)kRosetteLockedWindowHeight);
  g_window.contentMaxSize =
      NSMakeSize((CGFloat)kRosetteLockedWindowWidth,
                 (CGFloat)kRosetteLockedWindowHeight);
  RosetteMachOConfigureWindowPlacementPolicyOnMainThread();
  RosetteMachOConfigureOrdinaryWindowPolicy();

  g_view = [[RosetteMachOMetalView alloc] initWithFrame:content_rect];
  if (!g_view) {
    g_window = nil;
    return NO;
  }
  g_view.autoresizingMask = NSViewNotSizable;
  g_view.wantsLayer = YES;
  CALayer *backing_layer = g_view.layer;
  if (![backing_layer isKindOfClass:[CAMetalLayer class]]) {
    backing_layer = [CAMetalLayer layer];
    g_view.layer = backing_layer;
  }
  g_metal_layer = (CAMetalLayer *)backing_layer;
  g_metal_device = MTLCreateSystemDefaultDevice();
  if (!g_metal_layer || !g_metal_device) {
    g_metal_layer = nil;
    g_metal_device = nil;
    g_view = nil;
    g_window = nil;
    return NO;
  }

  g_metal_layer.device = g_metal_device;
  // MoltenVK uses the view delegate to track the display/backing properties.
  // This does not transfer drawable ownership back from the swapchain.
  g_metal_layer.delegate = g_view;
  g_metal_command_queue = [g_metal_device newCommandQueue];
  if (!g_metal_command_queue) {
    g_metal_layer = nil;
    g_metal_device = nil;
    g_view = nil;
    g_window = nil;
    return NO;
  }
  g_metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  g_metal_layer.framebufferOnly = NO;
  g_metal_layer.opaque = YES;
  g_metal_layer.presentsWithTransaction = NO;
  g_metal_layer.allowsNextDrawableTimeout = YES;
  g_metal_layer.maximumDrawableCount = 3;
  g_window.contentView = g_view;
  g_window.initialFirstResponder = g_view;
  pthread_mutex_lock(&g_keyboard_lock);
  g_keyboard_window_available = YES;
  pthread_mutex_unlock(&g_keyboard_lock);
  RosetteMachOPlaceWindowSafely();
  RosetteMachOUpdateMetalDrawable();
  RosetteMachOShowWindowOnMainThread("created");
  return YES;
}

int rosette_macho_native_application_ensure(void) {
  __block BOOL result = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      result = RosetteMachOEnsureApplicationOnMainThread();
    });
  }
  return result ? 1 : 0;
}

int rosette_macho_native_window_ensure(uint32_t width, uint32_t height,
                                      const char *title) {
  __block BOOL result = NO;
  NSString *window_title = title ? [NSString stringWithUTF8String:title] : nil;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      result = RosetteMachOEnsureWindowOnMainThread(
          width ? width : kRosetteLockedWindowWidth,
          height ? height : kRosetteLockedWindowHeight, window_title);
    });
  }
  return result ? 1 : 0;
}

/// The main window's title is Rosette's, not the guest's: "Rosette — frame N".
///
/// Once set, a guest SetWindowText no longer replaces it, because the guest
/// title (Xenia's) carries nothing the frame count does not already say and
/// the frame count is the only live progress readout on screen.
///
/// Asynchronous on purpose. Every guest thread runs on the one host thread
/// that calls this, so a synchronous hop to the main thread would stall the
/// whole emulation for however long AppKit takes to repaint a title bar.
static BOOL g_rosette_frame_title_owned = NO;
static uint64_t g_rosette_frame_title_last_ns;
void rosette_macho_native_window_set_frame_counter(uint64_t frame) {
  g_rosette_frame_title_owned = YES;
  // Every present advances the keyboard latch's clock; only the title is
  // throttled.
  atomic_store_explicit(&g_guest_frame_clock, frame, memory_order_relaxed);
  const uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
  if (g_rosette_frame_title_last_ns != 0u &&
      now - g_rosette_frame_title_last_ns < 250000000ull) {
    return;
  }
  g_rosette_frame_title_last_ns = now;
  const unsigned long long value = (unsigned long long)frame;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!g_window) return;
    g_window.title = [NSString stringWithFormat:@"Rosette — frame %llu", value];
  });
}

int rosette_macho_native_window_set_title(const char *title) {
  if (!title) {
    return 0;
  }
  // Once Rosette's frame counter owns the title there is nothing for a guest
  // title to change, and this path is a synchronous hop to the main thread -
  // one the whole emulation waits on, every time Xenia refreshes its own
  // title. The window already exists by then, so the answer is simply yes.
  if (g_rosette_frame_title_owned && g_window) {
    return 1;
  }
  __block BOOL result = NO;
  NSString *window_title = [NSString stringWithUTF8String:title];
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (RosetteMachOEnsureWindowOnMainThread(g_width, g_height,
                                               window_title)) {
        g_window.title = window_title ?: @"Xenia Canary (Rosette)";
        result = YES;
      }
    });
  }
  return result ? 1 : 0;
}

int rosette_macho_native_window_set_size(uint32_t width, uint32_t height) {
  if (!width || !height) {
    ++g_window_size_lock_refusals;
    return 0;
  }
  if (width != kRosetteLockedWindowWidth ||
      height != kRosetteLockedWindowHeight) {
    ++g_window_size_lock_refusals;
    const uint64_t count = g_window_size_lock_refusals;
    if (count <= 4u || (count & (count - 1u)) == 0u) {
      fprintf(stderr,
              "macho-processor: WINDOW SIZE LOCK: decision=refused "
              "operation=set_size requested=%ux%u locked=%ux%u "
              "refusal_count=%llu action=keep logical content fixed; "
              "drawable pixels and backing scale remain separate\n",
              (unsigned)width, (unsigned)height,
              (unsigned)kRosetteLockedWindowWidth,
              (unsigned)kRosetteLockedWindowHeight,
              (unsigned long long)count);
    }
    return 0;
  }
  __block BOOL result = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (RosetteMachOEnsureWindowOnMainThread(
              kRosetteLockedWindowWidth, kRosetteLockedWindowHeight, nil)) {
        RosetteMachOEnforceLockedWindowSizeOnMainThread("set_size_locked");
        RosetteMachOPlaceWindowSafely();
        RosetteMachOUpdateMetalDrawable();
        result = RosetteMachOContentSizeMatchesLocked();
      }
    });
  }
  return result ? 1 : 0;
}

int rosette_macho_native_window_show(void) {
  __block BOOL result = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (RosetteMachOEnsureWindowOnMainThread(g_width, g_height, nil)) {
        RosetteMachOShowWindowOnMainThread("show");
        RosetteMachOUpdateMetalDrawable();
        result = YES;
      }
    });
  }
  return result ? 1 : 0;
}

int rosette_macho_native_window_hide(void) {
  __block BOOL result = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (RosetteMachOEnsureWindowOnMainThread(g_width, g_height, nil)) {
        // The Xenia-facing window is a persistent diagnostic/presentation
        // surface. A guest hide request is not allowed to erase a valid
        // frame chain and leave Vulkan reporting successful presents to an
        // invisible drawable. This does not pin the window above other apps:
        // the user can still background it, move it, minimize it, or close
        // the application normally.
        ++g_window_hide_refusals;
        const uint64_t count = g_window_hide_refusals;
        if (count <= 4u || (count & (count - 1u)) == 0u) {
          fprintf(stderr,
                  "macho-processor: WINDOW VISIBILITY LOCK: decision=refused operation=hide refusal_count=%llu action=keep the persistent Xenia surface ordered; backgrounding and user movement remain allowed\n",
                  (unsigned long long)count);
        }
        RosetteMachOShowWindowOnMainThread("hide_refused_persistent_surface");
        result = NO;
      }
    });
  }
  return result ? 1 : 0;
}

int rosette_macho_native_window_set_fullscreen(int fullscreen) {
  __block BOOL result = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (!RosetteMachOEnsureWindowOnMainThread(g_width, g_height, nil)) {
        return;
      }
      const BOOL requested = fullscreen != 0;
      if (requested) {
        ++g_fullscreen_lock_refusals;
        const uint64_t count = g_fullscreen_lock_refusals;
        if (count <= 4u || (count & (count - 1u)) == 0u) {
          fprintf(stderr,
                  "macho-processor: WINDOW SIZE LOCK: decision=refused "
                  "operation=fullscreen requested=true locked=%ux%u "
                  "refusal_count=%llu action=fullscreen is disabled until "
                  "the fixed-size presentation contract is lifted\n",
                  (unsigned)kRosetteLockedWindowWidth,
                  (unsigned)kRosetteLockedWindowHeight,
                  (unsigned long long)count);
        }
        return;
      }
      if (requested != g_fullscreen) {
        [g_window toggleFullScreen:nil];
        g_fullscreen = requested;
      }
      result = YES;
    });
  }
  return result ? 1 : 0;
}

int rosette_macho_native_window_attach_metal_layer(void) {
  __block BOOL result = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (RosetteMachOEnsureWindowOnMainThread(g_width, g_height, nil)) {
        g_view.wantsLayer = YES;
        g_view.layer = g_metal_layer;
        RosetteMachOUpdateMetalDrawable();
        result = g_view.layer == g_metal_layer && g_metal_layer.device != nil;
      }
    });
  }
  return result ? 1 : 0;
}

uint64_t rosette_macho_native_window_present_diagnostic_frame(
    uint64_t serial, uint32_t width, uint32_t height, uint32_t stage) {
  __block uint64_t presented = 0;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (!RosetteMachOEnsureWindowOnMainThread(
              width ? width : g_width, height ? height : g_height, nil)) {
        return;
      }
      RosetteMachOUpdateMetalDrawable();
      id<CAMetalDrawable> drawable = [g_metal_layer nextDrawable];
      id<MTLCommandBuffer> command_buffer =
          [g_metal_command_queue commandBuffer];
      if (!drawable || !command_buffer) {
        return;
      }

      // A liveness probe, not a frame. Nothing here involves a guest image, a
      // Vulkan command buffer, a swapchain image, or a guest swap: it clears
      // the drawable so a blank window can be distinguished from a dead
      // Cocoa/Metal boundary. Rosette's native Vulkan presenter is what puts
      // real frames on this layer; this exists for the case where that
      // presenter could not be brought up, and its output must only ever be
      // counted as `diagnostic_frames_presented`.
      const double phase = (double)((serial >> 4) % 7u) / 6.0;
      const double stage_bias = (double)(stage % 4u) * 0.08;
      MTLRenderPassDescriptor *pass =
          [MTLRenderPassDescriptor renderPassDescriptor];
      pass.colorAttachments[0].texture = drawable.texture;
      pass.colorAttachments[0].loadAction = MTLLoadActionClear;
      pass.colorAttachments[0].storeAction = MTLStoreActionStore;
      pass.colorAttachments[0].clearColor =
          MTLClearColorMake(0.05 + stage_bias, 0.08 + phase * 0.35,
                            0.16 + (1.0 - phase) * 0.45, 1.0);
      id<MTLRenderCommandEncoder> encoder =
          [command_buffer renderCommandEncoderWithDescriptor:pass];
      if (!encoder) {
        return;
      }
      [encoder endEncoding];
      [command_buffer presentDrawable:drawable];
      [command_buffer commit];
      // `commit` only proves that Metal accepted a command buffer. It does not
      // prove that the drawable was executed or that its presentation reached
      // the device. Diagnostic custody is deliberately stricter than the
      // guest-copy path: wait for a completed command buffer before publishing
      // a counter that the Zig ledgers will use as hardware evidence.
      [command_buffer waitUntilCompleted];
      if ([command_buffer status] != MTLCommandBufferStatusCompleted) {
        return;
      }
      presented = ++g_diagnostic_frames_presented;
    });
  }
  return presented;
}

uint64_t rosette_macho_native_window_present_frame(
    uint64_t serial, const uint8_t *pixels, uint64_t source_length,
    uint32_t source_width, uint32_t source_height, uint64_t row_pitch,
    uint32_t format, uint8_t orientation, uint8_t fit) {
  if (!serial || !pixels || !source_width || !source_height ||
      source_width > 8192u || source_height > 8192u) {
    return 0;
  }
  const BOOL source_is_rgba = format == 37u || format == 43u;
  const BOOL source_is_bgra = format == 44u || format == 50u;
  if (!source_is_rgba && !source_is_bgra) {
    return 0;
  }
  const uint64_t tight_pitch = (uint64_t)source_width * 4u;
  const uint64_t effective_pitch = row_pitch ? row_pitch : tight_pitch;
  if (effective_pitch < tight_pitch ||
      source_height > UINT64_MAX / effective_pitch ||
      source_length < effective_pitch * source_height) {
    return 0;
  }

  __block uint64_t presented = 0;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (!RosetteMachOEnsureWindowOnMainThread(g_width, g_height, nil)) {
        return;
      }
      RosetteMachOUpdateMetalDrawable();
      id<CAMetalDrawable> drawable = [g_metal_layer nextDrawable];
      id<MTLCommandBuffer> command_buffer =
          [g_metal_command_queue commandBuffer];
      if (!drawable || !command_buffer) {
        return;
      }
      const NSUInteger destination_width = drawable.texture.width;
      const NSUInteger destination_height = drawable.texture.height;
      if (!destination_width || !destination_height ||
          destination_width > 8192u || destination_height > 8192u ||
          destination_height > NSUIntegerMax / destination_width / 4u) {
        return;
      }
      const NSUInteger destination_length =
          destination_width * destination_height * 4u;
      NSMutableData *converted =
          [NSMutableData dataWithLength:destination_length];
      if (!converted) {
        return;
      }
      uint8_t *destination = converted.mutableBytes;
      memset(destination, 0, destination_length);

      uint32_t output_x = 0;
      uint32_t output_y = 0;
      uint32_t output_width = (uint32_t)destination_width;
      uint32_t output_height = (uint32_t)destination_height;
      uint32_t source_x = 0;
      uint32_t source_y = 0;
      BOOL scale = YES;
      if (fit == 2u) {
        // Centre without scaling. A source larger than the drawable is cropped
        // symmetrically instead of being read past either edge.
        scale = NO;
        output_width = MIN(source_width, (uint32_t)destination_width);
        output_height = MIN(source_height, (uint32_t)destination_height);
        output_x = ((uint32_t)destination_width - output_width) / 2u;
        output_y = ((uint32_t)destination_height - output_height) / 2u;
        source_x = (source_width - output_width) / 2u;
        source_y = (source_height - output_height) / 2u;
      } else if (fit == 1u) {
        // Letterbox with integer cross-products. This preserves 4:3 exactly
        // and leaves the zeroed staging texture visible as bars.
        const uint64_t source_product =
            (uint64_t)source_width * destination_height;
        const uint64_t destination_product =
            (uint64_t)destination_width * source_height;
        if (source_product > destination_product) {
          output_width = (uint32_t)destination_width;
          output_height = MAX(
              1u, (uint32_t)((uint64_t)destination_width * source_height /
                             source_width));
          output_y = ((uint32_t)destination_height - output_height) / 2u;
        } else {
          output_height = (uint32_t)destination_height;
          output_width = MAX(
              1u, (uint32_t)((uint64_t)destination_height * source_width /
                             source_height));
          output_x = ((uint32_t)destination_width - output_width) / 2u;
        }
      } else if (fit != 0u) {
        return;
      }

      for (uint32_t y = 0; y < output_height; ++y) {
        uint32_t sampled_y = scale
                                 ? (uint32_t)((uint64_t)y * source_height /
                                              output_height)
                                 : source_y + y;
        if (orientation == 1u) {
          sampled_y = source_height - 1u - sampled_y;
        } else if (orientation != 0u) {
          return;
        }
        const uint8_t *source_row =
            pixels + (uint64_t)sampled_y * effective_pitch;
        uint8_t *destination_row =
            destination +
            ((uint64_t)(output_y + y) * destination_width + output_x) * 4u;
        for (uint32_t x = 0; x < output_width; ++x) {
          const uint32_t sampled_x = scale
                                         ? (uint32_t)((uint64_t)x *
                                                      source_width /
                                                      output_width)
                                         : source_x + x;
          const uint8_t *source_pixel = source_row + (uint64_t)sampled_x * 4u;
          uint8_t *destination_pixel = destination_row + (uint64_t)x * 4u;
          if (source_is_rgba) {
            destination_pixel[0] = source_pixel[2];
            destination_pixel[1] = source_pixel[1];
            destination_pixel[2] = source_pixel[0];
            destination_pixel[3] = source_pixel[3];
          } else {
            memcpy(destination_pixel, source_pixel, 4u);
          }
        }
      }

      MTLTextureDescriptor *description =
          [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
                                    MTLPixelFormatBGRA8Unorm
                                                        width:destination_width
                                                       height:destination_height
                                                    mipmapped:NO];
      description.usage = MTLTextureUsageShaderRead;
      id<MTLTexture> source_texture =
          [g_metal_device newTextureWithDescriptor:description];
      if (!source_texture) {
        return;
      }
      [source_texture
          replaceRegion:MTLRegionMake2D(0, 0, destination_width,
                                       destination_height)
            mipmapLevel:0
              withBytes:destination
            bytesPerRow:destination_width * 4u];
      id<MTLBlitCommandEncoder> encoder =
          [command_buffer blitCommandEncoder];
      if (!encoder) {
        return;
      }
      [encoder copyFromTexture:source_texture
                   sourceSlice:0
                   sourceLevel:0
                  sourceOrigin:MTLOriginMake(0, 0, 0)
                    sourceSize:MTLSizeMake(destination_width,
                                           destination_height, 1)
                     toTexture:drawable.texture
              destinationSlice:0
              destinationLevel:0
             destinationOrigin:MTLOriginMake(0, 0, 0)];
      [encoder endEncoding];
      [command_buffer presentDrawable:drawable];
      [command_buffer commit];
      [command_buffer waitUntilCompleted];
      if (command_buffer.status == MTLCommandBufferStatusCompleted) {
        presented = ++g_guest_frames_presented;
      }
    });
  }
  return presented;
}

// The one keyboard layout, stated once for the reader and the report. Keys are
// macOS virtual key codes. Enter and Space both confirm (A) and Escape backs
// out (B), because the first thing any title asks of a player is a menu.
#define ROSETTE_KEYBOARD_MAPPING_TEXT                                        \
  "Space/Return:A Escape/C:B X:X Y:Y P:Start Backspace/Tab:Back "           \
  "Home:Guide WASD:left-stick IJKL:right-stick arrows:dpad Q:LB R:RB "      \
  "Z:LT E:RT F:left-thumb V:right-thumb"
static const uint16_t kRosetteKeysA[] = {49u, 36u, 76u};      // Space, Return, keypad Enter
static const uint16_t kRosetteKeysB[] = {53u, 8u};            // Escape, C
static const uint16_t kRosetteKeysX[] = {7u};                 // X
static const uint16_t kRosetteKeysY[] = {16u};                // Y
static const uint16_t kRosetteKeysStart[] = {35u};            // P
static const uint16_t kRosetteKeysBack[] = {51u, 48u};        // Backspace, Tab
static const uint16_t kRosetteKeysGuide[] = {115u};           // Home
static const uint16_t kRosetteKeysLB[] = {12u};               // Q
static const uint16_t kRosetteKeysRB[] = {15u};               // R
static const uint16_t kRosetteKeysLT[] = {6u};                // Z
static const uint16_t kRosetteKeysRT[] = {14u};               // E
static const uint16_t kRosetteKeysLThumb[] = {3u};            // F
static const uint16_t kRosetteKeysRThumb[] = {9u};            // V
static const uint16_t kRosetteKeysDpadUp[] = {126u};
static const uint16_t kRosetteKeysDpadDown[] = {125u};
static const uint16_t kRosetteKeysDpadLeft[] = {123u};
static const uint16_t kRosetteKeysDpadRight[] = {124u};
#define ROSETTE_KEYS_DOWN(keys) \
  RosetteMachOAnyKeyDownLocked((keys), sizeof(keys) / sizeof((keys)[0]))

int rosette_macho_native_window_read_controller_state(
    RosetteMachOKeyboardControllerState *out) {
  if (!out) {
    return 0;
  }
  memset(out, 0, sizeof(*out));
  pthread_mutex_lock(&g_keyboard_lock);
  ++g_keyboard_snapshot_reads;
  out->connected = g_keyboard_window_available ? 1u : 0u;
  out->focused = g_keyboard_focused ? 1u : 0u;
  out->key_down_events = g_keyboard_key_down_events;
  out->key_up_events = g_keyboard_key_up_events;
  out->snapshot_reads = g_keyboard_snapshot_reads;
  out->focus_gain_events = g_keyboard_focus_gain_events;
  out->focus_loss_events = g_keyboard_focus_loss_events;
  out->rejected_key_events = g_keyboard_rejected_key_events;
  out->last_key_code = g_keyboard_last_key_code;
  out->input_contract_version = 2u;
  if (g_keyboard_window_available && g_keyboard_focused) {
    // Left stick: WASD. XInput's positive Y is up.
    out->thumb_lx = RosetteMachOAxisLocked(0u, 2u);   // A / D
    out->thumb_ly = RosetteMachOAxisLocked(1u, 13u);  // S / W
    // Right stick: IJKL.
    out->thumb_rx = RosetteMachOAxisLocked(38u, 37u); // J / L
    out->thumb_ry = RosetteMachOAxisLocked(40u, 34u); // K / I

    if (ROSETTE_KEYS_DOWN(kRosetteKeysDpadUp)) out->buttons |= 0x0001u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysDpadDown)) out->buttons |= 0x0002u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysDpadLeft)) out->buttons |= 0x0004u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysDpadRight)) out->buttons |= 0x0008u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysStart)) out->buttons |= 0x0010u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysBack)) out->buttons |= 0x0020u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysLThumb)) out->buttons |= 0x0040u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysRThumb)) out->buttons |= 0x0080u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysLB)) out->buttons |= 0x0100u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysRB)) out->buttons |= 0x0200u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysGuide)) out->buttons |= 0x0400u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysA)) out->buttons |= 0x1000u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysB)) out->buttons |= 0x2000u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysX)) out->buttons |= 0x4000u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysY)) out->buttons |= 0x8000u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysLT)) out->left_trigger = 255u;
    if (ROSETTE_KEYS_DOWN(kRosetteKeysRT)) out->right_trigger = 255u;
  }
  const BOOL changed =
      out->buttons != g_keyboard_reported_buttons ||
      out->left_trigger != g_keyboard_reported_triggers[0] ||
      out->right_trigger != g_keyboard_reported_triggers[1] ||
      out->thumb_lx != g_keyboard_reported_axes[0] ||
      out->thumb_ly != g_keyboard_reported_axes[1] ||
      out->thumb_rx != g_keyboard_reported_axes[2] ||
      out->thumb_ry != g_keyboard_reported_axes[3];
  if (changed) {
    ++g_keyboard_packet;
    g_keyboard_reported_buttons = out->buttons;
    g_keyboard_reported_triggers[0] = out->left_trigger;
    g_keyboard_reported_triggers[1] = out->right_trigger;
    g_keyboard_reported_axes[0] = out->thumb_lx;
    g_keyboard_reported_axes[1] = out->thumb_ly;
    g_keyboard_reported_axes[2] = out->thumb_rx;
    g_keyboard_reported_axes[3] = out->thumb_ry;
  }
  out->packet_number = g_keyboard_packet;
  const BOOL available = g_keyboard_window_available;
  pthread_mutex_unlock(&g_keyboard_lock);

  if (!g_reported_keyboard_mapping && available) {
    fprintf(stderr,
            "macho-processor: INPUT BRIDGE: virtual keyboard controller active on user 0 only; mapping=" ROSETTE_KEYBOARD_MAPPING_TEXT "; a press is held until two frames have been presented so a slow guest still polls it; the controller reports zero state when unfocused\n");
    g_reported_keyboard_mapping = YES;
  }
  return available ? 1 : 0;
}

uint32_t rosette_macho_native_window_pump_events(void) {
  __block uint32_t count = 0;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (!g_application) {
        return;
      }
      for (; count < 64; ++count) {
        NSEvent *event = [g_application
            nextEventMatchingMask:NSEventMaskAny
                         untilDate:[NSDate distantPast]
                            inMode:NSDefaultRunLoopMode
                           dequeue:YES];
        if (!event) {
          break;
        }
        [g_application sendEvent:event];
        RosetteMachOUpdateKeyboardFocusOnMainThread();
      }
      RosetteMachOUpdateKeyboardFocusOnMainThread();
      [g_application updateWindows];
      RosetteMachOUpdateMetalDrawable();
      g_events_pumped += count;
    });
  }
  return count;
}

RosetteMachONativeWindowStatus rosette_macho_native_window_status(void) {
  __block RosetteMachONativeWindowStatus status = {0};
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      RosetteMachOUpdateMetalDrawable();
      // Status is observational: a backgrounded or minimized window stays
      // where the user put it. In particular, do not turn a diagnostic poll
      // into an application activation.
      RosetteMachORepairWindowPlacementIfNeeded();
      status.application = (uintptr_t)(__bridge void *)g_application;
      status.window = (uintptr_t)(__bridge void *)g_window;
      status.view = (uintptr_t)(__bridge void *)g_view;
      status.metal_layer = (uintptr_t)(__bridge void *)g_metal_layer;
      status.metal_device = (uintptr_t)(__bridge void *)g_metal_device;
      status.width = g_width;
      status.height = g_height;
      status.events_pumped = g_events_pumped;
      status.application_ready = g_application != nil;
      status.window_ready = g_window != nil && g_view != nil;
      status.layer_attached = g_view != nil && g_view.wantsLayer &&
                              g_view.layer == g_metal_layer &&
                              g_metal_layer.device != nil;
      status.visible = g_window.visible;
      status.on_main_thread = [NSThread isMainThread];
    });
  }
  return status;
}

int rosette_macho_native_window_describe(
    RosetteMachONativeWindowGeometry *out) {
  if (out == NULL) {
    return 0;
  }
  memset(out, 0, sizeof(*out));
  __block int described = 0;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      out->on_main_thread = [NSThread isMainThread];
      if (g_window == nil) {
        return;
      }
      // Report actual occlusion/minimization without changing window order.
      RosetteMachORepairWindowPlacementIfNeeded();
      described = 1;
      out->window_exists = 1;
      out->window = (uintptr_t)(__bridge void *)g_window;
      out->view = (uintptr_t)(__bridge void *)g_view;
      out->metal_layer = (uintptr_t)(__bridge void *)g_metal_layer;
      out->screen = (uintptr_t)(__bridge void *)g_window.screen;
      out->screen_count = (uint32_t)[NSScreen screens].count;
      // The visible frame, not the full frame: the menu bar and the Dock are
      // not places a window can be seen, and a window centred on a screen's
      // full frame can still have its title bar behind the menu bar.
      NSScreen *const describing_screen = g_window.screen ?: [NSScreen mainScreen];
      if (describing_screen != nil) {
        const NSRect visible = describing_screen.visibleFrame;
        out->screen_visible_x = (double)NSMinX(visible);
        out->screen_visible_y = (double)NSMinY(visible);
        out->screen_visible_width = (double)NSWidth(visible);
        out->screen_visible_height = (double)NSHeight(visible);
      }

      const NSRect window_frame = g_window.frame;
      out->window_x = (double)NSMinX(window_frame);
      out->window_y = (double)NSMinY(window_frame);
      out->window_width = (double)NSWidth(window_frame);
      out->window_height = (double)NSHeight(window_frame);
      out->window_alpha = (double)g_window.alphaValue;
      out->window_visible = g_window.isVisible ? 1 : 0;
      out->window_miniaturized = g_window.isMiniaturized ? 1 : 0;
      out->window_on_screen = g_window.screen != nil ? 1 : 0;
      out->window_key = g_window.isKeyWindow ? 1 : 0;
      // NSWindowOcclusionStateVisible is bit 1. A window that is on screen but
      // fully occluded still presents happily and shows nothing.
      out->occlusion_state = (uint32_t)g_window.occlusionState;
      out->backing_scale = (double)g_window.backingScaleFactor;

      if (g_view != nil) {
        const NSRect view_frame = g_view.frame;
        out->view_width = (double)NSWidth(view_frame);
        out->view_height = (double)NSHeight(view_frame);
        out->view_hidden = g_view.isHidden ? 1 : 0;
        out->view_hidden_or_ancestor = g_view.isHiddenOrHasHiddenAncestor ? 1 : 0;
        out->view_wants_layer = g_view.wantsLayer ? 1 : 0;
        out->view_layer = (uintptr_t)(__bridge void *)g_view.layer;
        out->layer_is_view_layer =
            (g_metal_layer != nil && g_view.layer == g_metal_layer) ? 1 : 0;
      }

      if (g_metal_layer != nil) {
        const CGRect layer_bounds = g_metal_layer.bounds;
        out->layer_width = (double)CGRectGetWidth(layer_bounds);
        out->layer_height = (double)CGRectGetHeight(layer_bounds);
        const CGSize drawable = g_metal_layer.drawableSize;
        out->drawable_width = (double)drawable.width;
        out->drawable_height = (double)drawable.height;
        out->contents_scale = (double)g_metal_layer.contentsScale;
        out->layer_pixel_format = (uint32_t)g_metal_layer.pixelFormat;
        out->maximum_drawable_count =
            (uint32_t)g_metal_layer.maximumDrawableCount;
        out->layer_hidden = g_metal_layer.hidden ? 1 : 0;
        out->layer_opaque = g_metal_layer.opaque ? 1 : 0;
        out->layer_framebuffer_only = g_metal_layer.framebufferOnly ? 1 : 0;
        out->layer_presents_with_transaction =
            g_metal_layer.presentsWithTransaction ? 1 : 0;
        out->layer_superlayer =
            (uintptr_t)(__bridge void *)g_metal_layer.superlayer;
        out->layer_device = (uintptr_t)(__bridge void *)g_metal_layer.device;
      }
    });
  }
  return described;
}

static NSString *RosetteReadbackDirectory(void) {
  if (g_readback_directory) return g_readback_directory;
  const char *configured = getenv("ROSETTE_VULKAN_CAPTURE_DIR");
  if (configured && configured[0]) {
    g_readback_directory = [NSString stringWithUTF8String:configured];
  } else {
    NSString *cache = NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (!cache) return nil;
    g_readback_directory = [[cache stringByAppendingPathComponent:
        @"Rosette/frame-captures"] stringByAppendingPathComponent:
        NSProcessInfo.processInfo.globallyUniqueString];
  }
  NSError *error = nil;
  if (!g_readback_directory || ![NSFileManager.defaultManager
      createDirectoryAtPath:g_readback_directory
      withIntermediateDirectories:YES attributes:nil error:&error]) {
    fprintf(stderr, "macho-processor: FRAME CAPTURE: directory failure: %s\n",
            error.localizedDescription.UTF8String ?: "invalid capture path");
    g_readback_directory = nil;
    return nil;
  }
  fprintf(stderr, "macho-processor: FRAME CAPTURE: directory=%s limit=24 "
          "raw_alpha_and_opaque_rgb=YES source=completed-acquired-image\n",
          g_readback_directory.fileSystemRepresentation);
  return g_readback_directory;
}

static NSBitmapImageRep *RosetteReadbackBitmap(
    const RosetteMachOReadbackFrame *frame, BOOL opaque) {
  NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL pixelsWide:frame->width
      pixelsHigh:frame->height bitsPerSample:8 samplesPerPixel:4
      hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
      bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
      bytesPerRow:(NSInteger)frame->width * 4 bitsPerPixel:32];
  if (!bitmap || !bitmap.bitmapData) return nil;
  const BOOL bgra = frame->format == 44 || frame->format == 50;
  uint8_t *destination = bitmap.bitmapData;
  for (uint64_t offset = 0; offset < frame->length; offset += 4) {
    destination[offset] = frame->pixels[offset + (bgra ? 2 : 0)];
    destination[offset + 1] = frame->pixels[offset + 1];
    destination[offset + 2] = frame->pixels[offset + (bgra ? 0 : 2)];
    destination[offset + 3] = opaque ? 255 : frame->pixels[offset + 3];
  }
  // The pixels are already encoded according to the Vulkan image format.
  // Tag, don't transform them: UNORM and SRGB must not be gamma-converted twice.
  NSColorSpace *space = (frame->format == 43 || frame->format == 50)
      ? NSColorSpace.sRGBColorSpace : NSColorSpace.deviceRGBColorSpace;
  return [bitmap bitmapImageRepByRetaggingWithColorSpace:space];
}

static NSBitmapImageRep *RosetteReadbackExposure(NSBitmapImageRep *source) {
  NSBitmapImageRep *exposed = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL pixelsWide:source.pixelsWide pixelsHigh:source.pixelsHigh
      bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
      colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
      bytesPerRow:source.pixelsWide * 4 bitsPerPixel:32];
  if (!exposed || !exposed.bitmapData) return nil;
  // Fixed diagnostic gain, NOT a replacement gamma ramp or a title fix.
  // No per-channel normalization, black-level subtraction, or source edits.
  for (NSInteger y = 0; y < exposed.pixelsHigh; y++) {
    uint8_t *row = exposed.bitmapData + y * exposed.bytesPerRow;
    const uint8_t *original = source.bitmapData + y * source.bytesPerRow;
    for (NSInteger x = 0; x < exposed.pixelsWide; x++) {
      for (unsigned channel = 0; channel < 3; channel++) {
        row[x * 4 + channel] = (uint8_t)MIN(255u, (unsigned)original[x * 4 + channel] * 16u);
      }
      row[x * 4 + 3] = 255;
    }
  }
  return [exposed bitmapImageRepByRetaggingWithColorSpace:source.colorSpace];
}

uint32_t rosette_macho_native_window_capture_frame(
    const RosetteMachOReadbackFrame *frame) {
  if (!frame || !frame->pixels || !frame->width || !frame->height ||
      frame->width > (64ull * 1024 * 1024) / 4 / frame->height ||
      frame->length != (uint64_t)frame->width * frame->height * 4 ||
      !(frame->format == 37 || frame->format == 43 ||
        frame->format == 44 || frame->format == 50) || (frame->flags & ~31u)) {
    return 4;
  }
  @autoreleasepool {
    uint32_t result = 0;
    const BOOL numbered = (frame->flags & 16u) && !(frame->flags & 8u);
    // Never read beyond the legacy 128-byte packet without the extension
    // bit. Offline RGB replay cannot fabricate a native picture epoch.
    const uint64_t contentFrame = numbered ? frame->content_frame : 0;
    // Copy before returning: the caller reuses its mapped Vulkan staging area.
    NSBitmapImageRep *opaque = RosetteReadbackBitmap(frame, YES);
    if (!opaque) return 4;
    NSBitmapImageRep *exposed = (frame->flags & 4u) ? RosetteReadbackExposure(opaque) : nil;
    if ((frame->flags & 4u) && !exposed) return 4;
    if ((frame->flags & 1u) && g_readback_saved < 24) {
      g_readback_saved++;
      NSString *directory = RosetteReadbackDirectory();
      NSBitmapImageRep *raw = RosetteReadbackBitmap(frame, NO);
      NSString *stem = [NSString stringWithFormat:
          (frame->flags & 16u) ? @"present-%06llu-image-%016llx" : @"frame-%06llu-image-%016llx", (unsigned long long)frame->frame,
          (unsigned long long)frame->image];
      NSString *path = [directory stringByAppendingPathComponent:stem];
      NSError *error = nil;
      NSData *rawPNG = [raw representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
      NSData *rgbPNG = [opaque representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
      NSData *exposurePNG = exposed ? [exposed representationUsingType:NSBitmapImageFileTypePNG properties:@{}] : nil;
      NSDictionary *metadata = @{
        @"source": (frame->flags & 8u) ? @"offline CPU replay; no Vulkan completion verified" : @"completed acquired swapchain image before WSI",
        @"frame": @(frame->frame), @"swapchain": @(frame->swapchain),
        @"raw_present_or_readback_id": @(frame->frame),
        @"content_frame": @(contentFrame),
        @"content_numbering": numbered ? @"native-completed content since first observed RGB detail; zero waits for picture; not game FPS or scanout proof" : @"unclassified/offline readback; no native picture epoch",
        @"image": @(frame->image), @"width": @(frame->width),
        @"height": @(frame->height), @"vk_format": @(frame->format),
        @"raw_byte_hash_fnv1a64": [NSString stringWithFormat:@"%016llx", (unsigned long long)frame->hash],
        @"row_order": @"Vulkan rows, top to bottom; no vertical flip",
        @"raw_png": @"straight source alpha; BGRA converted to RGBA without color conversion",
        @"rgb_png_and_raw_preview": @"source RGB with alpha forced to 255; no exposure boost",
        @"diagnostic_exposure_multiplier": exposed ? @16 : @1,
        @"diagnostic_exposure_formula": @"min(source_rgb * 16, 255); alpha=255; NOT rendered-image correctness evidence",
        @"visible_pixels_max_rgb_gt_16": @(frame->visible_pixels),
        @"bright_pixels_max_rgb_gt_64": @(frame->bright_pixels),
        @"alpha_lt_255_pixels": @(frame->transparent_pixels),
        @"rgb_different_from_first_pixels": @(frame->rgb_different_pixels),
        @"rgb_sum": @[@(frame->rgb_sum[0]), @(frame->rgb_sum[1]), @(frame->rgb_sum[2])],
        @"min_rgb": @[@(frame->min_rgb[0]), @(frame->min_rgb[1]), @(frame->min_rgb[2])],
        @"max_rgb": @[@(frame->max_rgb[0]), @(frame->max_rgb[1]), @(frame->max_rgb[2])]
      };
      NSData *json = [NSJSONSerialization dataWithJSONObject:metadata
          options:NSJSONWritingPrettyPrinted error:&error];
      if (path && rawPNG && rgbPNG && json &&
          [rawPNG writeToFile:[path stringByAppendingString:@".png"] options:NSDataWritingAtomic error:&error] &&
          [rgbPNG writeToFile:[path stringByAppendingString:@"-rgb.png"] options:NSDataWritingAtomic error:&error] &&
          (!exposed || (exposurePNG && [exposurePNG writeToFile:[path stringByAppendingString:@"-exposure16.png"] options:NSDataWritingAtomic error:&error])) &&
          [json writeToFile:[path stringByAppendingString:@".json"] options:NSDataWritingAtomic error:&error]) {
        result |= 1;
        fprintf(stderr, "macho-processor: FRAME CAPTURE: saved=%s.png "
            "opaque_rgb=%s-rgb.png custody=%s.json\n",
            path.fileSystemRepresentation, path.fileSystemRepresentation,
            path.fileSystemRepresentation);
        if (exposed) fprintf(stderr, "macho-processor: FRAME EXPOSURE DIAGNOSTIC: path=%s-exposure16.png gain=16 source_unchanged=YES not_a_gamma_fix=YES\n", path.fileSystemRepresentation);
      } else {
        result |= 4;
        fprintf(stderr, "macho-processor: FRAME CAPTURE: frame=%llu save failed: %s\n",
            (unsigned long long)frame->frame,
            error.localizedDescription.UTF8String ?: "bitmap/path unavailable");
      }
    }
    if (frame->flags & 2u) {
      __block BOOL previewed = NO;
      RosetteMachORunOnMainThreadSync(^{
        if (g_readback_closed || !RosetteMachOEnsureApplicationOnMainThread()) return;
        if (!g_readback_window) {
          g_readback_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 300)
              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                        NSWindowStyleMaskMiniaturizable
              backing:NSBackingStoreBuffered defer:NO];
          g_readback_window.releasedWhenClosed = NO;
          g_readback_window.level = NSNormalWindowLevel;
          g_readback_window.hidesOnDeactivate = NO;
          g_readback_window.collectionBehavior =
              NSWindowCollectionBehaviorDefault;
          // The debug surface is movable, but its split preview geometry is
          // deliberately fixed until the presentation contract is repaired.
          // Resizing it changes neither the guest drawable nor the readback;
          // it only makes the diagnostic comparison harder to interpret.
          g_readback_window.contentMinSize = NSMakeSize(960.0, 300.0);
          g_readback_window.contentMaxSize = NSMakeSize(960.0, 300.0);
          g_readback_window.tabbingMode = NSWindowTabbingModeDisallowed;
          g_readback_delegate = [RosetteReadbackWindowDelegate new];
          g_readback_window.delegate = g_readback_delegate;
          NSView *comparison = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960, 300)];
          g_readback_view = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 480, 300)];
          g_readback_view.imageScaling = NSImageScaleProportionallyUpOrDown;
          g_readback_view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable | NSViewMaxXMargin;
          g_readback_exposure_view = [[NSImageView alloc] initWithFrame:NSMakeRect(480, 0, 480, 300)];
          g_readback_exposure_view.imageScaling = NSImageScaleProportionallyUpOrDown;
          g_readback_exposure_view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable | NSViewMinXMargin;
          [comparison addSubview:g_readback_view];
          [comparison addSubview:g_readback_exposure_view];
          g_readback_window.contentView = comparison;
          [g_readback_window center];
          // Do not steal the keyboard focus or mutate the guest window/layer.
          // As with the guest window, the preview may be created while the
          // process is backgrounded. Order it without activating the app so
          // the debug surface is actually observable while retaining normal
          // user-controlled stacking and movement.
          [g_readback_window orderFrontRegardless];
          fprintf(stderr, "macho-processor: COCOA READBACK: independent preview opened; "
              "no CAMetalLayer drawables consumed; RGB alpha forced opaque\n");
        }
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(frame->width, frame->height)];
        [image addRepresentation:opaque];
        g_readback_view.image = image;
        NSImage *exposureImage = [[NSImage alloc] initWithSize:NSMakeSize(frame->width, frame->height)];
        if (exposed) [exposureImage addRepresentation:exposed];
        g_readback_exposure_view.image = exposed ? exposureImage : image;
        NSString *numbering = numbered ? (contentFrame ?
            [NSString stringWithFormat:@"content frame %llu", (unsigned long long)contentFrame] :
            @"waiting for picture — frame 0") : @"unclassified readback";
        g_readback_window.title = [NSString stringWithFormat:
            @"Rosette acquired-image RGB — %@ | raw present %llu | RAW / %@ (not WSI)",
            numbering, (unsigned long long)frame->frame, exposed ? @"x16 DIAGNOSTIC" : @"RAW"];
        [g_readback_view displayIfNeeded];
        previewed = g_readback_window && g_readback_view;
      });
      if (previewed) result |= 2;
    }
    return result;
  }
}

void rosette_macho_native_window_shutdown(void) {
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      g_readback_window.delegate = nil;
      [g_readback_window close];
      g_readback_window = nil;
      g_readback_view = nil;
      g_readback_exposure_view = nil;
      g_readback_delegate = nil;
      g_readback_closed = NO;
      g_readback_directory = nil;
      g_readback_saved = 0;
      if (g_fullscreen && g_window) {
        [g_window toggleFullScreen:nil];
      }
      [g_window orderOut:nil];
      g_metal_layer.device = nil;
      g_window.contentView = nil;
      g_metal_command_queue = nil;
      g_metal_layer = nil;
      g_metal_device = nil;
      g_view = nil;
      g_window = nil;
      g_drawable_owned_by_swapchain = NO;
      g_drawable_contract_active = NO;
      g_drawable_contract_width = 0;
      g_drawable_contract_height = 0;
      g_fullscreen = NO;
      g_diagnostic_frames_presented = 0;
      g_guest_frames_presented = 0;
      g_window_hide_refusals = 0;
      g_foreground_reassertions = 0;
      g_window_placement_repairs = 0;
      g_window_placement_repair_failures = 0;
      g_window_size_lock_repairs = 0;
      g_window_size_lock_refusals = 0;
      g_fullscreen_lock_refusals = 0;
      g_reported_placement_policy = NO;
      pthread_mutex_lock(&g_keyboard_lock);
      g_keyboard_window_available = NO;
      g_keyboard_focused = NO;
      RosetteMachOClearKeyboardStateLocked();
      g_keyboard_packet = 0;
      g_keyboard_key_down_events = 0;
      g_keyboard_key_up_events = 0;
      g_keyboard_snapshot_reads = 0;
      g_keyboard_focus_gain_events = 0;
      g_keyboard_focus_loss_events = 0;
      g_keyboard_rejected_key_events = 0;
      g_keyboard_last_key_code = 0;
      pthread_mutex_unlock(&g_keyboard_lock);
      g_reported_keyboard_mapping = NO;
    });
  }
}

// The Zig forwarder discovers this callback through dlsym so test binaries
// can omit the AppKit bridge.  ReleaseFast is otherwise free to dead-strip a
// callback that has no ordinary C call edge, which makes a linked bridge look
// exactly like a missing window to the presentation report.  Keep one typed,
// retained edge in the Mach-O image so the callback remains discoverable.
typedef int (*RosetteMachONativeWindowDescribeFn)(
    RosetteMachONativeWindowGeometry *);
__attribute__((used, retain)) static const RosetteMachONativeWindowDescribeFn
    rosette_macho_native_window_describe_anchor =
        rosette_macho_native_window_describe;
__attribute__((used, retain)) static uint32_t (*const
    rosette_macho_native_window_capture_frame_anchor)(const RosetteMachOReadbackFrame *) =
        rosette_macho_native_window_capture_frame;
