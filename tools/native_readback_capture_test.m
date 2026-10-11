// Codec/custody regression fixture. No Xenia, Vulkan device, or guest window.
#import "../lib/Mach-O/native_window_bridge.h"
#import <AppKit/AppKit.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "../pkg/vendor/sources/vulkan-headers/1.4.313/include/vulkan/vulkan.h"

_Static_assert(offsetof(VkPhysicalDeviceProperties, limits) +
               offsetof(VkPhysicalDeviceLimits, minMemoryMapAlignment) == 600,
               "native Vulkan minMemoryMapAlignment offset drift");
_Static_assert(sizeof(((VkPhysicalDeviceLimits *)0)->minMemoryMapAlignment) == 8,
               "native Vulkan map alignment field width drift");

int main(int argc, char **argv) {
  assert(argc == 2 || (argc == 3 && strcmp(argv[2], "--preview") == 0));
  assert(setenv("ROSETTE_VULKAN_CAPTURE_DIR", argv[1], 1) == 0);
  @autoreleasepool {
    const uint8_t rgba[16] = {255, 0, 0, 0, 0, 255, 0, 255,
                              0, 0, 255, 128, 3, 7, 12, 255};
    for (uint32_t index = 0; index < 4; index++) {
      const uint32_t formats[] = {37, 43, 44, 50};
      uint8_t pixels[16];
      for (unsigned offset = 0; offset < 16; offset += 4) {
        const BOOL bgra = formats[index] == 44 || formats[index] == 50;
        pixels[offset] = rgba[offset + (bgra ? 2 : 0)];
        pixels[offset + 1] = rgba[offset + 1];
        pixels[offset + 2] = rgba[offset + (bgra ? 0 : 2)];
        pixels[offset + 3] = rgba[offset + 3];
      }
      RosetteMachOReadbackFrame frame = {
        .pixels = pixels, .length = 16, .frame = index + 1,
        .swapchain = 0x5678, .image = 0x9abc, .hash = 0x1234,
        .width = 2, .height = 2, .format = formats[index], .flags = 13,
        .visible_pixels = 3, .bright_pixels = 3, .transparent_pixels = 2,
        .rgb_sum = {258, 262, 267}, .rgb_different_pixels = 3,
        .max_rgb = {255, 255, 255}
      };
      assert(rosette_macho_native_window_capture_frame(&frame) == 1);
      // The copy must outlive the reused staging memory.
      memset(pixels, 0, sizeof(pixels));
      NSString *stem = [NSString stringWithFormat:@"%s/frame-%06u-image-0000000000009abc", argv[1], index + 1];
      for (unsigned opaque = 0; opaque < 2; opaque++) {
        NSString *path = [stem stringByAppendingString:opaque ? @"-rgb.png" : @".png"];
        NSBitmapImageRep *decoded = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:path]];
        assert(decoded && decoded.pixelsWide == 2 && decoded.pixelsHigh == 2);
        for (unsigned y = 0; y < 2; y++) for (unsigned x = 0; x < 2; x++) {
          NSUInteger actual[4] = {0};
          [decoded getPixel:actual atX:x y:y];
          const unsigned offset = (y * 2 + x) * 4;
          for (unsigned channel = 0; channel < 4; channel++) {
            assert(actual[channel] == ((opaque && channel == 3) ? 255 : rgba[offset + channel]));
          }
        }
      }
      NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:
          [NSData dataWithContentsOfFile:[stem stringByAppendingString:@".json"]]
          options:0 error:NULL];
      assert([metadata[@"vk_format"] unsignedIntValue] == formats[index]);
      assert([metadata[@"alpha_lt_255_pixels"] unsignedIntValue] == 2);
      assert([metadata[@"raw_byte_hash_fnv1a64"] isEqual:@"0000000000001234"]);
      assert([metadata[@"diagnostic_exposure_multiplier"] unsignedIntValue] == 16);
      NSBitmapImageRep *exposure = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:[stem stringByAppendingString:@"-exposure16.png"]]];
      assert(exposure && exposure.pixelsWide == 2);
      for (unsigned y = 0; y < 2; y++) for (unsigned x = 0; x < 2; x++) {
        NSUInteger actual[4] = {0};
        [exposure getPixel:actual atX:x y:y];
        for (unsigned channel = 0; channel < 3; channel++) assert(actual[channel] == MIN(255u, (unsigned)rgba[(y * 2 + x) * 4 + channel] * 16u));
        assert(actual[3] == 255);
      }
      frame.length = 15;
      assert(rosette_macho_native_window_capture_frame(&frame) == 4);
      frame.length = 16;
      frame.width = UINT32_MAX;
      frame.height = UINT32_MAX;
      assert(rosette_macho_native_window_capture_frame(&frame) == 4);
      frame.width = 2; frame.height = 2; frame.flags = 32;
      assert(rosette_macho_native_window_capture_frame(&frame) == 4);
    }
    RosetteMachOReadbackFrame numbered = {
      .pixels = rgba, .length = 16, .frame = 200001,
      .image = 0x9abc, .width = 2, .height = 2, .format = 37,
      .flags = 17, .content_frame = 1
    };
    assert(rosette_macho_native_window_capture_frame(&numbered) == 1);
    NSString *numberedPath = [NSString stringWithFormat:
        @"%s/present-200001-image-0000000000009abc.json", argv[1]];
    NSDictionary *numberedMetadata = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithContentsOfFile:numberedPath] options:0 error:NULL];
    assert([numberedMetadata[@"content_frame"] unsignedLongLongValue] == 1);
    assert([numberedMetadata[@"raw_present_or_readback_id"] unsignedLongLongValue] == 200001);
    // Offline tools cannot promote source pixels to a native epoch.
    numbered.frame++;
    numbered.flags |= 8;
    assert(rosette_macho_native_window_capture_frame(&numbered) == 1);
    numberedPath = [NSString stringWithFormat:
        @"%s/present-200002-image-0000000000009abc.json", argv[1]];
    numberedMetadata = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithContentsOfFile:numberedPath] options:0 error:NULL];
    assert([numberedMetadata[@"content_frame"] unsignedLongLongValue] == 0);
    // Exercise the actual legacy packet boundary, not a zero-filled larger
    // struct: the callback must never inspect the appended content ID.
    uint64_t legacy[16] = {0};
    memcpy(legacy, &numbered, sizeof(legacy));
    RosetteMachOReadbackFrame *legacyFrame = (RosetteMachOReadbackFrame *)legacy;
    legacyFrame->flags = 0;
    assert(rosette_macho_native_window_capture_frame(legacyFrame) == 0);
    if (argc == 3) {
      // Optional visible fixture: never starts Xenia or interprets a guest.
      assert(rosette_macho_native_window_ensure(1280, 720,
          "Rosette readback fixture (NOT Xenia)") == 1);
      RosetteMachOReadbackFrame frame = {
        .pixels = rgba, .length = 16, .frame = 5,
        .width = 2, .height = 2, .format = 37, .flags = 22,
        .content_frame = 0
      };
      assert(rosette_macho_native_window_capture_frame(&frame) == 2);
      NSWindow *preview = nil;
      for (NSWindow *window in NSApp.windows) {
        if ([window.title hasPrefix:@"Rosette acquired-image RGB"]) preview = window;
      }
      assert(preview && preview.isVisible);
      assert([preview.title containsString:@"waiting for picture — frame 0"]);
      frame.frame = 200001;
      frame.content_frame = 1;
      assert(rosette_macho_native_window_capture_frame(&frame) == 2);
      assert([preview.title containsString:@"content frame 1"]);
      assert([preview.title containsString:@"raw present 200001"]);
      RosetteMachONativeWindowStatus status = rosette_macho_native_window_status();
      NSWindow *canonical = (__bridge NSWindow *)(void *)status.window;
      assert(canonical && canonical.level == NSNormalWindowLevel);
      assert(preview.level == NSNormalWindowLevel);
      assert(canonical.collectionBehavior == NSWindowCollectionBehaviorDefault);
      assert(preview.collectionBehavior == NSWindowCollectionBehaviorDefault);
      // A different document window owns the keyboard and front position.
      // Frame capture, event pumping, ensure, and diagnostics must not raise
      // either Rosette window or take the document's key status away.
      NSWindow *document = [[NSWindow alloc] initWithContentRect:canonical.frame
          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
          backing:NSBackingStoreBuffered defer:NO];
      document.releasedWhenClosed = NO;
      document.title = @"Backgroundability regression (NOT Xenia)";
      [document makeKeyAndOrderFront:nil];
      // A command-line fixture may be inactive, in which case AppKit keeps
      // keyWindow nil. Preserve that state too; do not activate another app
      // merely to manufacture a key-window assertion.
      NSWindow *keyBeforeFrames = NSApp.keyWindow;
      for (unsigned poll = 0; poll < 4; poll++) {
        assert(rosette_macho_native_window_ensure(1280, 720, "Fixture") == 1);
        rosette_macho_native_window_pump_events();
        (void)rosette_macho_native_window_status();
        RosetteMachONativeWindowGeometry geometry;
        assert(rosette_macho_native_window_describe(&geometry) == 1);
        assert(rosette_macho_native_window_capture_frame(&frame) == 2);
        assert(NSApp.keyWindow == keyBeforeFrames);
        assert(document.orderedIndex < canonical.orderedIndex);
        assert(document.orderedIndex < preview.orderedIndex);
      }
      [canonical miniaturize:nil];
      [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
      rosette_macho_native_window_pump_events();
      (void)rosette_macho_native_window_status();
      RosetteMachONativeWindowGeometry minimized;
      assert(rosette_macho_native_window_describe(&minimized) == 1);
      assert(canonical.isMiniaturized && minimized.window_miniaturized);
      assert(NSApp.keyWindow != canonical);
      [preview close];
      assert(rosette_macho_native_window_capture_frame(&frame) == 0);
      assert(!preview.isVisible);
      [document close];
      rosette_macho_native_window_shutdown();
      puts("native Cocoa windows: normal levels, focus/order preserved during frames/polls, minimization retained, closed preview stays closed PASS");
    }
  }
  puts("native readback capture: 4 formats, alpha/RGB, row order, copy lifetime, custody, epoch numbering, legacy packet, invalid packets PASS");
  return 0;
}
