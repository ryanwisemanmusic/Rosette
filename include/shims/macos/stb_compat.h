#ifndef ROSETTE_SHIMS_MACOS_STB_COMPAT_H
#define ROSETTE_SHIMS_MACOS_STB_COMPAT_H

/* macOS Clang compat shim for stb-style single-header libraries.
 *
 * stb-style libraries use `STBTT_assert`, `STBI_ASSERT`, etc. for
 * debug assertions that abort on failure.  On macOS debug builds
 * these assertions trigger on malformed input (pathological fonts,
 * corrupt images) that real-world applications must handle gracefully.
 *
 * Include this header (via `-include`) to replace stb asserts with
 * a no-op that evaluates the condition for side effects without
 * aborting.  This matches the pattern used by the imstb_truetype
 * macOS patch (imstb_truetype-h-macos.patch).
 *
 * Each stb-style library uses a different assert macro name.
 * We neutralise all the common ones here so that no per-library
 * patching is needed.
 */
#if defined(__APPLE__) && defined(__clang__)

/* stb_truetype.h  —  STBTT_assert(expr) */
#ifdef STBTT_assert
#undef STBTT_assert
#endif
#define STBTT_assert(x) ((void)(x))

/* stb_image.h, stb_image_write.h  —  STBI_ASSERT(expr) */
#ifdef STBI_ASSERT
#undef STBI_ASSERT
#endif
#define STBI_ASSERT(x) ((void)(x))

/* stb_vorbis.h  —  STBV_ASSERT(expr) */
#ifdef STBV_ASSERT
#undef STBV_ASSERT
#endif
#define STBV_ASSERT(x) ((void)(x))

/* stb_rect_pack.h  —  STBRP_ASSERT(expr) */
#ifdef STBRP_ASSERT
#undef STBRP_ASSERT
#endif
#define STBRP_ASSERT(x) ((void)(x))

#endif /* __APPLE__ && __clang__ */

#endif /* ROSETTE_SHIMS_MACOS_STB_COMPAT_H */
