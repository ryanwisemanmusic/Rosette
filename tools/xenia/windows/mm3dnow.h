/* Clang/MinGW compatibility boundary, not an implementation of 3DNow!.
 * MinGW includes this obsolete umbrella even for SSE2-only x64 targets.
 * Route the supported MMX/prefetch declarations to their actual headers;
 * reject any target that asks for unsupported 3DNow instruction selection.
 * A call to a 3DNow intrinsic still fails to compile (no fake declarations).
 */
#ifndef ROSETTE_WINDOWS_MM3DNOW_COMPAT_H
#define ROSETTE_WINDOWS_MM3DNOW_COMPAT_H
#if defined(__3dNOW__) || defined(__3dNOW_A__)
#error "Rosette's Clang Windows capsule does not support 3DNow intrinsics"
#endif
#include <mmintrin.h>
#include <prfchwintrin.h>
#endif
