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
/*  -Wold-style-cast                                                  */
/*  C++ projects with C heritage often use `(Type*)expr` casts.       */
/*  Apple Clang may promote this to an error under project -Werror.   */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wold-style-cast"

/* ------------------------------------------------------------------ */
/*  -Wundefined-reinterpret-cast                                       */
/*  Emulators, codecs, and graphics code often type-pun scalar bits   */
/*  via pointer casts in hot paths.  Apple Clang may flag these under  */
/*  strict warning sets even when the project accepts the upstream     */
/*  implementation.                                                   */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wundefined-reinterpret-cast"

/* ------------------------------------------------------------------ */
/*  -Wdeprecated-declarations                                         */
/*  sprintf, strcpy, and other POSIX-fixed functions are deprecated   */
/*  on macOS in favour of the _s variants.  Bundled third-party code  */
/*  rarely uses the _s forms.  stb_image_write hits this.             */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* ------------------------------------------------------------------ */
/*  -Wmissing-braces                                                  */
/*  Apple Clang sometimes warns about aggregate initialisation that   */
/*  is valid C/C++.  Common in C libraries ported to C++.             */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wmissing-braces"

/* ------------------------------------------------------------------ */
/*  -Wlogical-op-parentheses                                          */
/*  Clang warns on `a && b || c` without parentheses to clarify       */
/*  intent.  Common in FFmpeg, libavformat, and similar media libs.   */
/* ------------------------------------------------------------------ */
#pragma clang diagnostic ignored "-Wlogical-op-parentheses"

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

/* ------------------------------------------------------------------ */
/*  MoltenVK / Vulkan-Hpp platform selection                          */
/*  macOS Vulkan projects usually need VK_USE_PLATFORM_METAL_EXT      */
/*  before including Vulkan headers.  Defining it centrally avoids    */
/*  per-project *_mac API wrapper headers.                            */
/* ------------------------------------------------------------------ */
#ifndef VK_USE_PLATFORM_METAL_EXT
#define VK_USE_PLATFORM_METAL_EXT
#endif

#endif /* __APPLE__ && __clang__ */

#endif /* ROSETTE_SHIMS_MACOS_COMPILER_COMPAT_H */
