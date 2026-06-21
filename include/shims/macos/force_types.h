#ifndef ROSETTE_SHIMS_MACOS_FORCE_TYPES_H
#define ROSETTE_SHIMS_MACOS_FORCE_TYPES_H

/* macOS ARM/ARM64 type compat shim for capstone and similar libraries.
 *
 * On Apple Clang in C++ mode, enum types have a different ABI from plain
 * int — they can be signed/unsigned, and their size is implementation-
 * defined.  Libraries like capstone that define `arm_cc`, `arm64_cc`,
 * `arm_reg`, `arm64_reg` as enums in C headers can produce link-time
 * type mismatches when consumed from C++ translation units.
 *
 * Including this header BEFORE the library's own headers forces those
 * types to plain int / void*, matching the C ABI that the library was
 * compiled with.  Any project on macOS that uses capstone (or any library
 * with the same pattern) can include this once at the top of their
 * translation unit or force-include it via -include.
 *
 * Rosette provides this on its default include path
 * (include/shims/macos/) so it automatically resolves for any project
 * using the compat layer. */

#define arm_cc int
#define arm64_cc int
#define arm_reg int
#define arm64_reg int
#define arm void*
#define arm64 void*

#endif /* ROSETTE_SHIMS_MACOS_FORCE_TYPES_H */
