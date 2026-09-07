/* Compatibility declarations used only by the external Clang/MinGW build. */
#ifndef XENIA_CANARY_WINDOWS_COMPAT_H_
#define XENIA_CANARY_WINDOWS_COMPAT_H_

/* Older MinGW-w64 headers predate the Windows 11 corner-preference API. */
#ifndef XENIA_CANARY_DWM_CORNER_PREFERENCE
#define XENIA_CANARY_DWM_CORNER_PREFERENCE 1
typedef enum DWM_WINDOW_CORNER_PREFERENCE {
  DWMWCP_DEFAULT = 0,
  DWMWCP_DONOTROUND = 1,
  DWMWCP_ROUND = 2,
  DWMWCP_ROUNDSMALL = 3,
} DWM_WINDOW_CORNER_PREFERENCE;
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif

/* Clang provides the standard SSE2 spelling; MinGW's Windows-only x-suffix
 * alias is hidden when __GNUC__ and __SSE2__ are both defined. */
#ifndef _mm_cvtsi64x_si128
#define _mm_cvtsi64x_si128 _mm_cvtsi64_si128
#endif

/* DXC uses this Windows-SDK SAL annotation, which older MinGW headers omit. */
#ifndef _Maybenull_
#define _Maybenull_
#endif

/* MinGW's SAL header provides the other SDL annotations but not this one. */
#ifndef _Scanf_format_string_impl_
#define _Scanf_format_string_impl_
#endif

#endif
