#ifndef ROSETTE_MACHO_NATIVE_WINDOW_BRIDGE_H
#define ROSETTE_MACHO_NATIVE_WINDOW_BRIDGE_H

#include <stdint.h>

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

int rosette_macho_native_application_ensure(void);
int rosette_macho_native_window_ensure(uint32_t width, uint32_t height,
                                      const char *title);
int rosette_macho_native_window_set_title(const char *title);
int rosette_macho_native_window_set_size(uint32_t width, uint32_t height);
int rosette_macho_native_window_show(void);
int rosette_macho_native_window_set_fullscreen(int fullscreen);
int rosette_macho_native_window_attach_metal_layer(void);
uint64_t rosette_macho_native_window_present_synthetic_vulkan_frame(
    uint64_t serial, uint32_t width, uint32_t height, uint32_t stage);
uint32_t rosette_macho_native_window_pump_events(void);
RosetteMachONativeWindowStatus rosette_macho_native_window_status(void);
void rosette_macho_native_window_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif
