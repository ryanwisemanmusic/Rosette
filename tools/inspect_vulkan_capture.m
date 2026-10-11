// Offline evidence replay. Never loads a PE, Vulkan provider, or guest process.
#import "../lib/Mach-O/native_window_bridge.h"
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: inspect-vulkan-capture input.png output-directory\n"); return 2; }
  @autoreleasepool {
    NSBitmapImageRep *decoded = [NSBitmapImageRep imageRepWithData:
        [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]]];
    if (!decoded || decoded.bitsPerSample != 8 || decoded.pixelsWide <= 0 ||
        decoded.pixelsHigh <= 0 || (uint64_t)decoded.pixelsWide > (64ull * 1024 * 1024) / 4 / (uint64_t)decoded.pixelsHigh ||
        decoded.samplesPerPixel < 3 || decoded.samplesPerPixel > 4) {
      fprintf(stderr, "capture inspection: unsupported/bounded PNG required\n"); return 2;
    }
    const uint64_t count = (uint64_t)decoded.pixelsWide * decoded.pixelsHigh;
    uint8_t *pixels = malloc(count * 4);
    if (!pixels) return 2;
    RosetteMachOReadbackFrame frame = {
      .pixels = pixels, .length = count * 4, .frame = 1,
      .width = (uint32_t)decoded.pixelsWide, .height = (uint32_t)decoded.pixelsHigh,
      .format = 37, .flags = 13, // PNG, exposure, explicit OFFLINE replay
      .hash = 14695981039346656037ull, .min_rgb = {255, 255, 255}
    };
    NSUInteger first[4] = {0};
    [decoded getPixel:first atX:0 y:0];
    for (NSInteger y = 0; y < decoded.pixelsHigh; y++) for (NSInteger x = 0; x < decoded.pixelsWide; x++) {
      NSUInteger color[4] = {0, 0, 0, 255};
      [decoded getPixel:color atX:x y:y];
      const uint64_t offset = ((uint64_t)y * decoded.pixelsWide + x) * 4;
      uint8_t maximum = 0;
      BOOL different = NO;
      for (unsigned channel = 0; channel < 4; channel++) {
        pixels[offset + channel] = (uint8_t)color[channel];
        frame.hash = (frame.hash ^ pixels[offset + channel]) * 1099511628211ull;
        if (channel < 3) {
          frame.rgb_sum[channel] += color[channel];
          frame.min_rgb[channel] = MIN(frame.min_rgb[channel], color[channel]);
          frame.max_rgb[channel] = MAX(frame.max_rgb[channel], color[channel]);
          maximum = MAX(maximum, color[channel]);
          different |= color[channel] != first[channel];
        }
      }
      frame.visible_pixels += maximum > 16;
      frame.bright_pixels += maximum > 64;
      frame.transparent_pixels += color[3] < 255;
      frame.rgb_different_pixels += different;
    }
    if (setenv("ROSETTE_VULKAN_CAPTURE_DIR", argv[2], 1) != 0) { free(pixels); return 2; }
    const uint32_t result = rosette_macho_native_window_capture_frame(&frame);
    fprintf(stdout, "OFFLINE CAPTURE: source=%s extent=%ux%u pixels=%llu mean=%llu/%llu/%llu min=%u/%u/%u max=%u/%u/%u visible_gt16=%llu bright_gt64=%llu different_rgb=%llu; x16 image is a diagnostic, not repaired GPU output\n",
        argv[1], frame.width, frame.height, (unsigned long long)count,
        (unsigned long long)(frame.rgb_sum[0] / count), (unsigned long long)(frame.rgb_sum[1] / count), (unsigned long long)(frame.rgb_sum[2] / count),
        frame.min_rgb[0], frame.min_rgb[1], frame.min_rgb[2], frame.max_rgb[0], frame.max_rgb[1], frame.max_rgb[2],
        (unsigned long long)frame.visible_pixels, (unsigned long long)frame.bright_pixels, (unsigned long long)frame.rgb_different_pixels);
    free(pixels);
    return result == 1 ? 0 : 1;
  }
}
