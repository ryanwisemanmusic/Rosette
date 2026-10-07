#import "input_controller_bridge.h"

#import <GameController/GameController.h>
#import <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <stdatomic.h>

static pthread_mutex_t g_controller_state_lock = PTHREAD_MUTEX_INITIALIZER;
static RosetteMachOPhysicalControllerState g_controller_state;
static GCController *g_selected_controller;
static id g_connect_observer;
static id g_disconnect_observer;
static BOOL g_observers_installed;
static _Atomic uint64_t g_controller_generation = ATOMIC_VAR_INIT(1);

static float RosetteControllerClamp(float value) {
  if (value < -1.0f) return -1.0f;
  if (value > 1.0f) return 1.0f;
  return value;
}

static int16_t RosetteControllerAxis(float value) {
  value = RosetteControllerClamp(value);
  if (value <= -1.0f) return INT16_MIN;
  if (value >= 1.0f) return INT16_MAX;
  return (int16_t)(value * (value < 0.0f ? 32768.0f : 32767.0f));
}

static uint8_t RosetteControllerTrigger(float value) {
  value = value < 0.0f ? 0.0f : (value > 1.0f ? 1.0f : value);
  return (uint8_t)(value * 255.0f + 0.5f);
}

static void RosetteControllerCopyName(char out[64], NSString *name) {
  memset(out, 0, 64);
  const char *utf8 = name.UTF8String;
  if (!utf8) return;
  size_t length = strnlen(utf8, 63);
  for (size_t i = 0; i < length; ++i) {
    const unsigned char c = (unsigned char)utf8[i];
    // Keep the run summary to one line even if a device advertises a control
    // character in its product name.
    out[i] = (c < 0x20u || c == 0x7fu) ? '?' : (char)c;
  }
}

static void RosetteControllerPublish(GCExtendedGamepad *gamepad,
                                     uint64_t generation,
                                     BOOL count_event) {
  if (!gamepad) return;

  RosetteMachOPhysicalControllerState next = {0};
  next.connected = 1;
  next.buttons = 0;
  if (gamepad.buttonA.isPressed) next.buttons |= 0x1000u;
  if (gamepad.buttonB.isPressed) next.buttons |= 0x2000u;
  if (gamepad.buttonX.isPressed) next.buttons |= 0x4000u;
  if (gamepad.buttonY.isPressed) next.buttons |= 0x8000u;
  if (gamepad.dpad.up.isPressed) next.buttons |= 0x0001u;
  if (gamepad.dpad.down.isPressed) next.buttons |= 0x0002u;
  if (gamepad.dpad.left.isPressed) next.buttons |= 0x0004u;
  if (gamepad.dpad.right.isPressed) next.buttons |= 0x0008u;
  if (@available(macOS 10.15, *)) {
    if (gamepad.buttonMenu.isPressed) next.buttons |= 0x0010u;
    if (gamepad.buttonOptions.isPressed) next.buttons |= 0x0020u;
  }
  if (gamepad.leftThumbstickButton.isPressed) next.buttons |= 0x0040u;
  if (gamepad.rightThumbstickButton.isPressed) next.buttons |= 0x0080u;
  if (gamepad.leftShoulder.isPressed) next.buttons |= 0x0100u;
  if (gamepad.rightShoulder.isPressed) next.buttons |= 0x0200u;
  if (@available(macOS 11.0, *)) {
    if (gamepad.buttonHome.isPressed) next.buttons |= 0x0400u;
  }
  next.left_trigger = RosetteControllerTrigger(gamepad.leftTrigger.value);
  next.right_trigger = RosetteControllerTrigger(gamepad.rightTrigger.value);
  next.thumb_lx = RosetteControllerAxis(gamepad.leftThumbstick.xAxis.value);
  next.thumb_ly = RosetteControllerAxis(gamepad.leftThumbstick.yAxis.value);
  next.thumb_rx = RosetteControllerAxis(gamepad.rightThumbstick.xAxis.value);
  next.thumb_ry = RosetteControllerAxis(gamepad.rightThumbstick.yAxis.value);

  pthread_mutex_lock(&g_controller_state_lock);
  const uint64_t current_generation = atomic_load_explicit(
      &g_controller_generation, memory_order_acquire);
  if (generation == current_generation) {
    next.value_events = g_controller_state.value_events +
                        (count_event ? 1u : 0u);
    memcpy(next.name, g_controller_state.name, sizeof(next.name));
    g_controller_state = next;
  }
  pthread_mutex_unlock(&g_controller_state_lock);
}

static void RosetteControllerClear(uint64_t generation) {
  pthread_mutex_lock(&g_controller_state_lock);
  if (generation == atomic_load_explicit(&g_controller_generation,
                                         memory_order_acquire)) {
    const uint64_t events = g_controller_state.value_events;
    memset(&g_controller_state, 0, sizeof(g_controller_state));
    g_controller_state.value_events = events;
  }
  pthread_mutex_unlock(&g_controller_state_lock);
}

static void RosetteControllerSelectOnMainThread(void) {
  GCController *candidate = nil;
  for (GCController *controller in GCController.controllers) {
    if (controller.extendedGamepad) {
      candidate = controller;
      break;
    }
  }
  if (candidate == g_selected_controller) return;

  const uint64_t generation = atomic_fetch_add_explicit(
                                  &g_controller_generation, 1,
                                  memory_order_acq_rel) +
                              1u;
  if (g_selected_controller.extendedGamepad) {
    g_selected_controller.extendedGamepad.valueChangedHandler = nil;
  }
  g_selected_controller = candidate;
  RosetteControllerClear(generation);

  if (!candidate) {
    fprintf(stderr,
            "macho-processor: HOST GAME CONTROLLER: disconnected; keyboard "
            "virtual pad remains available on user 0\n");
    return;
  }

  pthread_mutex_lock(&g_controller_state_lock);
  RosetteControllerCopyName(g_controller_state.name, candidate.vendorName);
  pthread_mutex_unlock(&g_controller_state_lock);
  GCExtendedGamepad *gamepad = candidate.extendedGamepad;
  gamepad.valueChangedHandler = ^(GCExtendedGamepad *changed_gamepad,
                                  GCControllerElement *element) {
    (void)element;
    RosetteControllerPublish(changed_gamepad, generation, YES);
  };
  RosetteControllerPublish(gamepad, generation, NO);

  pthread_mutex_lock(&g_controller_state_lock);
  char reported_name[64];
  memcpy(reported_name, g_controller_state.name, sizeof(reported_name));
  reported_name[sizeof(reported_name) - 1] = '\0';
  pthread_mutex_unlock(&g_controller_state_lock);
  fprintf(stderr,
          "macho-processor: HOST GAME CONTROLLER: connected name='%s' "
          "route=user0 mapping=xbox360; keyboard fallback remains active\n",
          reported_name);
}

void rosette_macho_input_controller_ensure(void) {
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      rosette_macho_input_controller_ensure();
    });
    return;
  }
  if (g_observers_installed) {
    RosetteControllerSelectOnMainThread();
    return;
  }

  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  g_connect_observer = [center
      addObserverForName:GCControllerDidConnectNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification *notification) {
                (void)notification;
                dispatch_async(dispatch_get_main_queue(), ^{
                  RosetteControllerSelectOnMainThread();
                });
              }];
  g_disconnect_observer = [center
      addObserverForName:GCControllerDidDisconnectNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification *notification) {
                (void)notification;
                dispatch_async(dispatch_get_main_queue(), ^{
                  RosetteControllerSelectOnMainThread();
                });
              }];
  g_observers_installed = YES;
  RosetteControllerSelectOnMainThread();
}

int rosette_macho_input_controller_read(
    RosetteMachOPhysicalControllerState *out) {
  if (!out) return 0;
  pthread_mutex_lock(&g_controller_state_lock);
  *out = g_controller_state;
  pthread_mutex_unlock(&g_controller_state_lock);
  return out->connected ? 1 : 0;
}
