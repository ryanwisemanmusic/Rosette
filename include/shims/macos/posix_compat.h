#ifndef ROSETTE_SHIMS_MACOS_POSIX_COMPAT_H
#define ROSETTE_SHIMS_MACOS_POSIX_COMPAT_H

/* macOS Clang POSIX compatibility shim.
 *
 * Centralises the POSIX-level workarounds that third-party C/C++ libraries
 * commonly need on macOS (which lacks several GNU extensions and C11 features
 * assumed by cross-platform code).
 *
 * Include this header (via `-include`) to avoid per-patch fixes.
 */
#if defined(__APPLE__) && defined(__clang__)

/* ------------------------------------------------------------------ */
/*  secure_getenv                                                     */
/*  macOS does not provide the GNU extension `secure_getenv`.  Many    */
/*  projects that target Linux fall back to plain `getenv` via a      */
/*  preprocessor define.  This matches the pattern used by Xenia's    */
/*  GTK windowed app (macos-gtk-project-fixes.patch) and is safe on   */
/*  macOS where the concept of "secure" environment is not separate.  */
/* ------------------------------------------------------------------ */
#ifndef secure_getenv
#define secure_getenv(name) getenv(name)
#endif

/* ------------------------------------------------------------------ */
/*  ATOMIC_VAR_INIT                                                   */
/*  This C11 macro was removed in C17 and may not be defined in Apple */
/*  Clang's <stdatomic.h>.  On macOS the macro is unnecessary (C11     */
/*  atomics can be initialised directly).  FFmpeg uses it in          */
/*  libavutil/cpu.c.                                                  */
/* ------------------------------------------------------------------ */
#ifndef ATOMIC_VAR_INIT
#define ATOMIC_VAR_INIT(x) (x)
#endif

#endif /* __APPLE__ && __clang__ */

#endif /* ROSETTE_SHIMS_MACOS_POSIX_COMPAT_H */
