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
 * Each public definition is guarded by #ifndef so the compiler's own
 * definition (when present) takes precedence. Some bundled projects provide
 * their own compatibility macro later in the include graph, so keep Clang's
 * macro-redefinition warning quiet for this translation unit while Rosette is
 * acting as the injected compatibility layer.
 */

#ifdef __x86_64__

#if defined(__clang__)
#pragma clang diagnostic ignored "-Wmacro-redefined"
#endif

#ifndef __rosette_cpuid_count
#define __rosette_cpuid_count(leaf, subleaf, eax, ebx, ecx, edx)             \
    __asm__ __volatile__("cpuid\n"                                          \
                         : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)       \
                         : "0"(leaf), "2"(subleaf))
#endif

#ifndef __cpuid
#define __cpuid(leaf, eax, ebx, ecx, edx)                                    \
    __rosette_cpuid_count((leaf), 0, (eax), (ebx), (ecx), (edx))
#endif

#ifndef __cpuid_count
#define __cpuid_count(leaf, subleaf, eax, ebx, ecx, edx)                    \
    __rosette_cpuid_count((leaf), (subleaf), (eax), (ebx), (ecx), (edx))
#endif

#endif /* __x86_64__ */

#endif /* ROSETTE_X86_INTRINSICS_COMPAT_H */
