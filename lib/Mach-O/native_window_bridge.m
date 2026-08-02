#import "native_window_bridge.h"

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <dispatch/dispatch.h>
#include <stdio.h>

@interface RosetteMachOMetalView : NSView
@end

@implementation RosetteMachOMetalView

- (CALayer *)makeBackingLayer {
  return [CAMetalLayer layer];
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
static uint32_t g_events_pumped;
static BOOL g_fullscreen;
static BOOL g_reported_off_main_thread;
static uint64_t g_synthetic_vulkan_frames_presented;

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

static void RosetteMachOUpdateMetalDrawable(void) {
  if (!g_window || !g_view || !g_metal_layer) {
    return;
  }
  const CGFloat scale = MAX(g_window.backingScaleFactor, 1.0);
  const NSRect bounds = g_view.bounds;
  g_metal_layer.frame = bounds;
  g_metal_layer.contentsScale = scale;
  g_metal_layer.drawableSize =
      CGSizeMake(MAX(bounds.size.width, 1.0) * scale,
                 MAX(bounds.size.height, 1.0) * scale);
  g_width = (uint32_t)MAX(bounds.size.width, 1.0);
  g_height = (uint32_t)MAX(bounds.size.height, 1.0);
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
    if (title.length) {
      g_window.title = title;
    }
    return YES;
  }

  g_width = MAX(width, 1u);
  g_height = MAX(height, 1u);
  const NSRect content_rect = NSMakeRect(0.0, 0.0, g_width, g_height);
  const NSWindowStyleMask style = NSWindowStyleMaskTitled |
                                  NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable |
                                  NSWindowStyleMaskResizable;
  g_window = [[NSWindow alloc] initWithContentRect:content_rect
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

  g_view = [[RosetteMachOMetalView alloc] initWithFrame:content_rect];
  if (!g_view) {
    g_window = nil;
    return NO;
  }
  g_view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
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
  [g_window center];
  RosetteMachOUpdateMetalDrawable();
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
          width ? width : 1280, height ? height : 720, window_title);
    });
  }
  return result ? 1 : 0;
}

int rosette_macho_native_window_set_title(const char *title) {
  if (!title) {
    return 0;
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
    return 0;
  }
  __block BOOL result = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (RosetteMachOEnsureWindowOnMainThread(width, height, nil)) {
        [g_window setContentSize:NSMakeSize(width, height)];
        RosetteMachOUpdateMetalDrawable();
        result = YES;
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
        [g_window makeKeyAndOrderFront:nil];
        [g_application activateIgnoringOtherApps:YES];
        RosetteMachOUpdateMetalDrawable();
        result = YES;
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

uint64_t rosette_macho_native_window_present_synthetic_vulkan_frame(
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

      // The translated Vulkan device and command stream are still modeled,
      // so no authoritative guest pixels exist here yet. Put an unmistakable
      // frame on the real CAMetalLayer anyway: this proves the final Cocoa /
      // Metal forwarding boundary is live and prevents a permanently blank
      // window while the native Vulkan object bridge is being completed.
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
      presented = ++g_synthetic_vulkan_frames_presented;
    });
  }
  return presented;
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
      }
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

void rosette_macho_native_window_shutdown(void) {
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
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
      g_fullscreen = NO;
      g_synthetic_vulkan_frames_presented = 0;
    });
  }
}
