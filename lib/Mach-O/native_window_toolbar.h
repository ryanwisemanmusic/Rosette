#ifndef ROSETTE_MACHO_NATIVE_WINDOW_TOOLBAR_H
#define ROSETTE_MACHO_NATIVE_WINDOW_TOOLBAR_H

#ifdef __OBJC__
@class NSWindow;
void rosette_macho_native_toolbar_install(NSWindow *window);
#else
void rosette_macho_native_toolbar_install(void *window);
#endif

#endif
