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

#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

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

/* ------------------------------------------------------------------ */
/*  GNU 64-bit file API spellings                                     */
/*  macOS is LP64 for normal desktop builds, so off_t is already      */
/*  64-bit and the *64 entry points used by Linux-originated code are */
/*  just alternate names for the native calls.                         */
/* ------------------------------------------------------------------ */
#if !defined(__off64_t_defined) && !defined(_OFF64_T_DECLARED)
typedef off_t off64_t;
#define __off64_t_defined 1
#define _OFF64_T_DECLARED 1
#endif

#ifndef ftruncate64
#define ftruncate64 ftruncate
#endif

#ifndef lseek64
#define lseek64 lseek
#endif

#ifndef pread64
#define pread64 pread
#endif

#ifndef pwrite64
#define pwrite64 pwrite
#endif

#ifndef fseeko64
#define fseeko64 fseeko
#endif

#ifndef ftello64
#define ftello64 ftello
#endif

/* ------------------------------------------------------------------ */
/*  mmap flag compatibility                                           */
/*  macOS uses MAP_ANON, while many portable projects spell this as   */
/*  MAP_ANONYMOUS.  Linux also has MAP_FIXED_NOREPLACE, whose safety  */
/*  semantics are not equivalent to macOS MAP_FIXED.  Rosette exposes */
/*  a helper so projects can preserve "do not replace" behavior       */
/*  instead of silently weakening it with a macro alias.               */
/* ------------------------------------------------------------------ */
#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif

#ifndef ROSETTE_POSIX_COMPAT_INLINE
#define ROSETTE_POSIX_COMPAT_INLINE static inline
#endif

ROSETTE_POSIX_COMPAT_INLINE void *rosette_mmap_fixed_noreplace(
    void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
#if defined(MAP_FIXED_NOREPLACE)
  return mmap(addr, length, prot, flags | MAP_FIXED_NOREPLACE, fd, offset);
#else
  (void)addr;
  (void)length;
  (void)prot;
  (void)flags;
  (void)fd;
  (void)offset;
  errno = ENOTSUP;
  return MAP_FAILED;
#endif
}

#if !defined(MAP_FIXED_NOREPLACE)
#define ROSETTE_MISSING_MAP_FIXED_NOREPLACE 1
#endif

#if !defined(MAP_FIXED_NOREPLACE) && defined(ROSETTE_ENABLE_UNSAFE_MAP_FIXED_NOREPLACE_ALIAS)
#define MAP_FIXED_NOREPLACE MAP_FIXED
#endif

#endif /* __APPLE__ && __clang__ */

#endif /* ROSETTE_SHIMS_MACOS_POSIX_COMPAT_H */
