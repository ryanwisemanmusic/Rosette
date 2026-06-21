#ifndef ROSETTE_SHIMS_MACOS_ENDIAN_H
#define ROSETTE_SHIMS_MACOS_ENDIAN_H

/* macOS <endian.h> compat shim.
 *
 * macOS does not ship <endian.h> in the standard sense.  It has
 * <machine/endian.h> which defines BYTE_ORDER / BIG_ENDIAN / LITTLE_ENDIAN
 * (without the __ prefix).  Many cross-platform libraries (crypto, LLVM,
 * zlib-ng, FFmpeg, …) include <endian.h> and use the __BYTE_ORDER /
 * __BIG_ENDIAN / __LITTLE_ENDIAN names that Linux/glibc exposes.
 *
 * This shim translates between the two conventions so that third-party
 * code can use the portable __-prefixed names on macOS without patching.
 *
 * Because include/shims/macos/ is on the -I path, #include <endian.h>
 * will resolve here first, shadowing any system-provided endian.h that
 * may exist on other platforms. */

#include <machine/endian.h>

#ifndef __BYTE_ORDER
#define __BYTE_ORDER BYTE_ORDER
#endif

#ifndef __BIG_ENDIAN
#define __BIG_ENDIAN BIG_ENDIAN
#endif

#ifndef __LITTLE_ENDIAN
#define __LITTLE_ENDIAN LITTLE_ENDIAN
#endif

/* Also provide the byte-swap helpers that glibc's <endian.h> typically
 * exposes via <byteswap.h>.  macOS provides these via <libkern/OSByteOrder.h>
 * with different names.  Bridge the common ones so third-party code that
 * uses bswap_16 / bswap_32 / bswap_64 compiles unmodified. */
#include <libkern/OSByteOrder.h>

#ifndef bswap_16
#define bswap_16(x) OSSwapInt16(x)
#endif

#ifndef bswap_32
#define bswap_32(x) OSSwapInt32(x)
#endif

#ifndef bswap_64
#define bswap_64(x) OSSwapInt64(x)
#endif

#endif /* ROSETTE_SHIMS_MACOS_ENDIAN_H */
