#ifndef ROSETTE_SHIMS_MACOS_COMPILER_COMPAT_H
#define ROSETTE_SHIMS_MACOS_COMPILER_COMPAT_H

/* macOS Clang compiler compat shim.
 *
 * Centralises the warning suppressions and ABI workarounds that third-party
 * libraries commonly need on Apple Clang (macOS / iOS / tvOS / watchOS).
 *
 * Many cross-platform C/C++ projects were developed primarily with MSVC
 * (ILP32: unsigned long = 32-bit) or Linux GCC/Clang (where -Wshorten-64-to-32
 * is not enabled by default).  Apple Clang on arm64 enables it in -Wall.
 *
 * Include this header first in third-party translation units (via
 * -include compiler_shims/macos/compiler_compat.h) to avoid patching
 * hundreds of sites in projects like LLVM, zlib-ng, microprofile, dxbc,
 * xbyak, frida-gum, and VMA. */

#if defined(__APPLE__) && defined(__clang__)

/* ------------------------------------------------------------------ */
/*  -Wshorten-64-to-32                                                */
/*  Triggered whenever a 64-bit value (unsigned long, size_t, …) is   */
/*  implicitly narrowed to 32 bits on LP64 (macOS arm64, x86_64).     */
/*  Libraries that target ILP32 (Win32) or were written before 64-bit */
/*  was widespread hit this in hundreds of places.                    */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wshorten-64-to-32"

/* ------------------------------------------------------------------ */
/*  -Wconversion  (subsets not suppressed by -Wshorten-64-to-32)      */
/*  Covers sign conversion, implicit integer promotion changes, and   */
/*  other implicit narrowing that -Wshorten-64-to-32 leaves alone.    */
/*  Common in microprofile, stb, and similar single-header libs.      */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wconversion"

/* ------------------------------------------------------------------ */
/*  -Wsign-conversion                                                 */
/*  Warns when an unsigned value is implicitly converted to signed    */
/*  (or vice versa).  Extremely common in game/Audio libraries that   */
/*  mix uint32_t with int for loop counters.                          */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wsign-conversion"

/* ------------------------------------------------------------------ */
/*  -Wunused-variable / -Wunused-const-variable                       */
/*  macOS enables -Wunused-variable in -Wall; many projects keep      */
/*  variables around for debug-only assertions that are stripped in   */
/*  release builds.  VMA (vk_mem_alloc) and similar projects hit      */
/*  this pattern frequently.                                          */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wunused-const-variable"

/* ------------------------------------------------------------------ */
/*  -Wdeprecated-declarations                                         */
/*  sprintf, strcpy, and other POSIX-fixed functions are deprecated   */
/*  on macOS in favour of the _s variants.  Bundled third-party code  */
/*  rarely uses the _s forms.  stb_image_write hits this.             */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* ------------------------------------------------------------------ */
/*  -Wmissing-braces / -Wmissing-field-initializers                   */
/*  Apple Clang sometimes warns about aggregate initialisation that   */
/*  is valid C/C++.  Common in C libraries ported to C++.             */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wmissing-braces"
#pragma clang diagnostic ignored "-Wmissing-field-initializers"

/* ------------------------------------------------------------------ */
/*  -Wswitch / -Wswitch-enum                                          */
/*  Enums used in switch statements that only cover a subset of       */
/*  values (e.g. opcode tables, codec dispatch).  Apple Clang enables */
/*  these in -Wall; many cross-platform projects omit default cases   */
/*  when the switch is exhaustive at the time of writing.             */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wswitch"
#pragma clang diagnostic ignored "-Wswitch-enum"

/* ------------------------------------------------------------------ */
/*  -Wlogical-op-parentheses / -Wparentheses-equality                 */
/*  Clang warns on `a && b || c` without parentheses to clarify       */
/*  intent, and on `if (a = b)` without extra parentheses.            */
/*  Common in FFmpeg, libavformat, and similar media libs.            */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wlogical-op-parentheses"
#pragma clang diagnostic ignored "-Wparentheses-equality"

/* ------------------------------------------------------------------ */
/*  -Wpointer-sign                                                    */
/*  Warns when a `char *` is implicitly converted to `unsigned char *`*/
/*  or vice versa.  Many C libraries mix raw-byte buffers (uint8_t *) */
/*  with string pointers (char *) freely.  Common in FFmpeg.          */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wpointer-sign"

/* ------------------------------------------------------------------ */
/*  asm → __asm__                                                     */
/*  Apple Clang in strict C++ modes (-std=c++17, not gnu++17) rejects */
/*  the GCC `asm` keyword.  `__asm__` is the portable ISO C spelling  */
/*  accepted by all compilers.  Many projects (frida-gum, FFmpeg,     */
/*  zlib-ng) use `asm volatile(...)` for inline assembly in TLS or    */
/*  CPU-detection code.  This define maps `asm` to `__asm__` so that  */
/*  those files compile under strict C++ without patching.            */
/*  The guard checks that `asm` is not already defined (some build    */
/*  systems pre-define it via -Dasm=__asm__).                         */
/* ------------------------------------------------------------------ */
#ifndef asm
#define asm __asm__
#endif

#endif /* __APPLE__ && __clang__ */

#endif /* ROSETTE_SHIMS_MACOS_COMPILER_COMPAT_H */
