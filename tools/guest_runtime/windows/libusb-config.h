/* Configuration used only by the external MinGW validation build. */
#ifndef XENIA_CANARY_LIBUSB_CONFIG_H
#define XENIA_CANARY_LIBUSB_CONFIG_H

#define DEFAULT_VISIBILITY __attribute__((visibility("default")))
#define ENABLE_LOGGING 1
#define PLATFORM_WINDOWS 1
#define PRINTF_FORMAT(a, b) __attribute__((format(printf, a, b)))

#endif
