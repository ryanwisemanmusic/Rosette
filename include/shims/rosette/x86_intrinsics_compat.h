#ifndef ROSETTE_X86_INTRINSICS_COMPAT_H
#define ROSETTE_X86_INTRINSICS_COMPAT_H

/*
 * Rosette x86 intrinsic compatibility header.
 *
 * When cross-compiling x86_64 code from a non-x86 host (e.g. Apple Clang on
 * ARM64), certain compiler builtins may not be available because the host
 * toolchain does not ship the x86 resource headers. This file provides
 * portable fallback definitions for x86 intrinsics using inline assembly.
 *
 * Each definition is guarded by #ifndef so the compiler's own definition
 * (when present) takes precedence.
 */

#ifdef __x86_64__

#ifndef __cpuid_count
#define __cpuid_count(leaf, subleaf, eax, ebx, ecx, edx)                   \
    __asm__("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)         \
                   :  "a"(leaf), "c"(subleaf))
#endif

#endif /* __x86_64__ */

#endif /* ROSETTE_X86_INTRINSICS_COMPAT_H */
