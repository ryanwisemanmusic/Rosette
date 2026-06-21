#ifndef ROSETTE_SHIMS_ROSETTE_CPU_FEATURE_PROBE_H
#define ROSETTE_SHIMS_ROSETTE_CPU_FEATURE_PROBE_H

/* Runtime CPU feature checks shared by projects that build or run x86_64
 * code on macOS.  CPUID can advertise features that are not safe under
 * translation, so callers should use rosette_cpu_feature_is_safe_to_execute()
 * for dispatch decisions instead of checking CPUID bits directly.
 */

#if defined(__APPLE__)
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/sysctl.h>
#endif

#if defined(__APPLE__) && defined(__x86_64__)
#include <setjmp.h>
#include <signal.h>
#include <string.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef enum rosette_cpu_feature {
  ROSETTE_CPU_FEATURE_SSE2 = 1,
  ROSETTE_CPU_FEATURE_SSE42 = 2,
  ROSETTE_CPU_FEATURE_AVX = 3,
  ROSETTE_CPU_FEATURE_AVX2 = 4,
} rosette_cpu_feature;

static inline int rosette_is_running_under_rosetta2(void) {
#if defined(__APPLE__)
  int translated = 0;
  size_t size = sizeof(translated);
  if (sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0) == 0) {
    return translated == 1;
  }
  return 0;
#else
  return 0;
#endif
}

#if defined(__APPLE__) && defined(__x86_64__)

static inline void rosette_x86_cpuid_count(uint32_t leaf, uint32_t subleaf,
                                           uint32_t *eax, uint32_t *ebx,
                                           uint32_t *ecx, uint32_t *edx) {
  uint32_t a = leaf;
  uint32_t b = 0;
  uint32_t c = subleaf;
  uint32_t d = 0;
  __asm__ volatile("cpuid"
                   : "+a"(a), "=b"(b), "+c"(c), "=d"(d)
                   :
                   : "cc");
  if (eax) *eax = a;
  if (ebx) *ebx = b;
  if (ecx) *ecx = c;
  if (edx) *edx = d;
}

static inline uint64_t rosette_x86_xgetbv(uint32_t xcr) {
  uint32_t eax = 0;
  uint32_t edx = 0;
  __asm__ volatile(".byte 0x0f, 0x01, 0xd0"
                   : "=a"(eax), "=d"(edx)
                   : "c"(xcr)
                   : "cc");
  return ((uint64_t)edx << 32) | eax;
}

static inline int rosette_x86_cpuid_has_leaf(uint32_t leaf) {
  uint32_t max_leaf = 0;
  rosette_x86_cpuid_count(0, 0, &max_leaf, NULL, NULL, NULL);
  return max_leaf >= leaf;
}

static inline int rosette_x86_cpuid_supports_sse2(void) {
  uint32_t edx = 0;
  rosette_x86_cpuid_count(1, 0, NULL, NULL, NULL, &edx);
  return (edx & (1u << 26)) != 0;
}

static inline int rosette_x86_cpuid_supports_sse42(void) {
  uint32_t ecx = 0;
  rosette_x86_cpuid_count(1, 0, NULL, NULL, &ecx, NULL);
  return (ecx & (1u << 20)) != 0;
}

static inline int rosette_x86_cpuid_supports_avx(void) {
  uint32_t ecx = 0;
  rosette_x86_cpuid_count(1, 0, NULL, NULL, &ecx, NULL);
  const int has_xsave = (ecx & (1u << 26)) != 0;
  const int has_osxsave = (ecx & (1u << 27)) != 0;
  const int has_avx = (ecx & (1u << 28)) != 0;
  if (!has_xsave || !has_osxsave || !has_avx) return 0;
  return (rosette_x86_xgetbv(0) & 0x6u) == 0x6u;
}

static inline int rosette_x86_cpuid_supports_avx2(void) {
  if (!rosette_x86_cpuid_supports_avx()) return 0;
  if (!rosette_x86_cpuid_has_leaf(7)) return 0;
  uint32_t ebx = 0;
  rosette_x86_cpuid_count(7, 0, NULL, &ebx, NULL, NULL);
  return (ebx & (1u << 5)) != 0;
}

static sigjmp_buf rosette_cpu_probe_jmp;
static volatile sig_atomic_t rosette_cpu_probe_armed = 0;

static void rosette_cpu_probe_sigill_handler(int signo) {
  if (signo == SIGILL && rosette_cpu_probe_armed) {
    siglongjmp(rosette_cpu_probe_jmp, 1);
  }
}

typedef void (*rosette_cpu_probe_fn)(void);

static inline int rosette_cpu_probe_instruction(rosette_cpu_probe_fn probe) {
  struct sigaction action;
  struct sigaction old_action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = rosette_cpu_probe_sigill_handler;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGILL, &action, &old_action) != 0) return 0;

  rosette_cpu_probe_armed = 1;
  const int ok = sigsetjmp(rosette_cpu_probe_jmp, 1) == 0;
  if (ok) probe();
  rosette_cpu_probe_armed = 0;

  sigaction(SIGILL, &old_action, NULL);
  return ok;
}

static void rosette_cpu_probe_avx(void) {
  __asm__ volatile(".byte 0xc5, 0xf8, 0x57, 0xc0" :::);
}

static void rosette_cpu_probe_avx2(void) {
  __asm__ volatile(".byte 0xc5, 0xfd, 0x76, 0xc0" :::);
}

#endif /* __APPLE__ && __x86_64__ */

static inline int rosette_cpu_feature_is_advertised(rosette_cpu_feature feature) {
#if defined(__APPLE__) && defined(__x86_64__)
  switch (feature) {
    case ROSETTE_CPU_FEATURE_SSE2:
      return rosette_x86_cpuid_supports_sse2();
    case ROSETTE_CPU_FEATURE_SSE42:
      return rosette_x86_cpuid_supports_sse42();
    case ROSETTE_CPU_FEATURE_AVX:
      return rosette_x86_cpuid_supports_avx();
    case ROSETTE_CPU_FEATURE_AVX2:
      return rosette_x86_cpuid_supports_avx2();
  }
#else
  (void)feature;
#endif
  return 0;
}

static inline int rosette_cpu_feature_is_safe_to_execute(rosette_cpu_feature feature) {
#if defined(__APPLE__) && defined(__x86_64__)
  if (rosette_is_running_under_rosetta2()) {
    switch (feature) {
      case ROSETTE_CPU_FEATURE_AVX:
      case ROSETTE_CPU_FEATURE_AVX2:
        return 0;
      default:
        break;
    }
  }

  if (!rosette_cpu_feature_is_advertised(feature)) return 0;

  switch (feature) {
    case ROSETTE_CPU_FEATURE_AVX:
      return rosette_cpu_probe_instruction(rosette_cpu_probe_avx);
    case ROSETTE_CPU_FEATURE_AVX2:
      return rosette_cpu_probe_instruction(rosette_cpu_probe_avx2);
    case ROSETTE_CPU_FEATURE_SSE2:
    case ROSETTE_CPU_FEATURE_SSE42:
      return 1;
  }
#else
  (void)feature;
#endif
  return 0;
}

#ifdef __cplusplus
}
#endif

#endif /* ROSETTE_SHIMS_ROSETTE_CPU_FEATURE_PROBE_H */
