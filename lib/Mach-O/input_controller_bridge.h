#ifndef ROSETTE_MACHO_INPUT_CONTROLLER_BRIDGE_H
#define ROSETTE_MACHO_INPUT_CONTROLLER_BRIDGE_H

#include <stdint.h>

// Snapshot of the first connected macOS extended game controller. This is
// kept separate from AppKit so XamInput polling can read it without a main
// queue hop. The keyboard virtual pad remains an independent fallback.
typedef struct RosetteMachOPhysicalControllerState {
  uint16_t buttons;
  uint8_t left_trigger;
  uint8_t right_trigger;
  int16_t thumb_lx;
  int16_t thumb_ly;
  int16_t thumb_rx;
  int16_t thumb_ry;
  uint32_t connected;
  uint32_t reserved;
  uint64_t value_events;
  char name[64];
} RosetteMachOPhysicalControllerState;

_Static_assert(sizeof(RosetteMachOPhysicalControllerState) == 96,
               "physical controller snapshot layout changed");

// Called on the AppKit main thread after the host application is initialized.
// It observes already-connected devices; it does not begin Bluetooth scans.
void rosette_macho_input_controller_ensure(void);

// Thread-safe snapshot read. Returns one when an extended gamepad is
// connected, otherwise zero. This function never calls AppKit or GameController
// APIs on the polling thread.
int rosette_macho_input_controller_read(
    RosetteMachOPhysicalControllerState *out);

#endif
