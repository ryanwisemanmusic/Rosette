#import "native_window_bridge.h"

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>

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
static uint64_t g_diagnostic_frames_presented;
static uint64_t g_guest_frames_presented;

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

int rosette_macho_native_window_hide(void) {
  __block BOOL result = NO;
  @autoreleasepool {
    RosetteMachORunOnMainThreadSync(^{
      if (RosetteMachOEnsureWindowOnMainThread(g_width, g_height, nil)) {
        [g_window orderOut:nil];
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
      g_diagnostic_frames_presented = 0;
      g_guest_frames_presented = 0;
    });
  }
}
