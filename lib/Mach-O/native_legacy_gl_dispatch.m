#import <OpenGL/gl.h>
#import <OpenGL/glu.h>

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdio.h>

// The PE32 runner passes Win32 addresses as integers. Resolve every guest
// pointer against the executor's flat-memory span before exposing it to GL.
static void *RosetteGuestPointer(uint8_t *memory, size_t memory_size,
                                 uint32_t guest_base, uint64_t address,
                                 size_t required_size) {
  if (memory == NULL || address == 0 || address < guest_base) return NULL;
  const uint64_t offset = address - guest_base;
  if (offset > memory_size || required_size > memory_size - (size_t)offset)
    return NULL;
  return memory + (size_t)offset;
}

static GLfloat RosetteFloat32(const uint64_t *args, size_t index) {
  const uint32_t bits = (uint32_t)args[index];
  GLfloat value;
  memcpy(&value, &bits, sizeof(value));
  return value;
}

static GLdouble RosetteFloat64(const uint64_t *args, size_t index) {
  const uint64_t bits = (uint64_t)(uint32_t)args[index] |
                        ((uint64_t)(uint32_t)args[index + 1] << 32);
  GLdouble value;
  memcpy(&value, &bits, sizeof(value));
  return value;
}

static int RosetteComponentCount(GLenum format) {
  switch (format) {
    case GL_RED:
    case GL_GREEN:
    case GL_BLUE:
    case GL_ALPHA:
    case GL_LUMINANCE:
    case GL_COLOR_INDEX:
    case GL_STENCIL_INDEX:
    case GL_DEPTH_COMPONENT:
      return 1;
    case GL_LUMINANCE_ALPHA:
      return 2;
    case GL_RGB:
    case GL_BGR:
      return 3;
    case GL_RGBA:
    case GL_BGRA:
      return 4;
    default:
      return 0;
  }
}

static size_t RosettePixelBytes(GLenum format, GLenum type) {
  const int components = RosetteComponentCount(format);
  if (components == 0) return 0;
  switch (type) {
    case GL_UNSIGNED_BYTE:
    case GL_BYTE:
      return (size_t)components;
    case GL_UNSIGNED_SHORT:
    case GL_SHORT:
      return (size_t)components * 2u;
    case GL_UNSIGNED_INT:
    case GL_INT:
    case GL_FLOAT:
      return (size_t)components * 4u;
    case GL_DOUBLE:
      return (size_t)components * 8u;
    case GL_UNSIGNED_SHORT_5_6_5:
    case GL_UNSIGNED_SHORT_4_4_4_4:
    case GL_UNSIGNED_SHORT_5_5_5_1:
    case GL_UNSIGNED_SHORT_4_4_4_4_REV:
    case GL_UNSIGNED_SHORT_1_5_5_5_REV:
      return 2u;
    case GL_UNSIGNED_INT_8_8_8_8:
    case GL_UNSIGNED_INT_8_8_8_8_REV:
    case GL_UNSIGNED_INT_10_10_10_2:
    case GL_UNSIGNED_INT_2_10_10_10_REV:
      return 4u;
    default:
      return 0;
  }
}

static size_t RosetteAlignedRowBytes(size_t row_bytes, GLint alignment) {
  const size_t a = alignment > 0 ? (size_t)alignment : 4u;
  return (row_bytes + a - 1u) & ~(a - 1u);
}

typedef struct {
  uint8_t colors[256][4];
  GLsizei width;
  GLenum format;
  int initialized;
} RosettePalette;

typedef struct RosetteIndexedTextureLevel {
  GLint level;
  GLsizei width;
  GLsizei height;
  GLint border;
  GLint internal_format;
  uint16_t *indices;
  struct RosetteIndexedTextureLevel *next;
} RosetteIndexedTextureLevel;

typedef struct RosetteTexturePaletteState {
  GLuint texture;
  RosettePalette palette;
  int has_local_palette;
  RosetteIndexedTextureLevel *levels;
  struct RosetteTexturePaletteState *next;
} RosetteTexturePaletteState;

static RosettePalette g_rosette_shared_palette;
static RosetteTexturePaletteState *g_rosette_texture_palettes;
static GLuint g_rosette_bound_texture_2d;
static unsigned int g_rosette_palette_trace_count;
static unsigned int g_rosette_texture_trace_count;
static unsigned int g_rosette_reupload_trace_count;
static unsigned int g_rosette_bind_trace_count;
static unsigned int g_rosette_texture_enable_trace_count;
static unsigned int g_rosette_texcoord_trace_count;
static unsigned int g_rosette_glu_scale_trace_count;
static unsigned int g_rosette_begin_trace_count;
static unsigned int g_rosette_list_trace_count;
static unsigned int g_rosette_list_call_trace_count;
static unsigned int g_rosette_gen_trace_count;
static unsigned int g_rosette_parameter_trace_count;
static GLuint g_rosette_compiling_list;
static int g_rosette_texture_2d_enabled;
static atomic_int g_rosette_gl_trace_enabled_cache = ATOMIC_VAR_INIT(-1);

static int RosetteGlTraceEnabled(void) {
  const int cached = atomic_load_explicit(&g_rosette_gl_trace_enabled_cache,
                                         memory_order_acquire);
  if (cached >= 0) return cached;
  const char *value = getenv("ROSETTE_PE32_GL_TRACE");
  const int enabled = value != NULL && value[0] != '\0' && value[0] != '0';
  int expected = -1;
  (void)atomic_compare_exchange_strong_explicit(
      &g_rosette_gl_trace_enabled_cache, &expected, enabled,
      memory_order_release, memory_order_relaxed);
  return atomic_load_explicit(&g_rosette_gl_trace_enabled_cache,
                              memory_order_acquire);
}

static unsigned int RosetteColorIndexBits(GLint internal_format);
static size_t RosetteColorIndexTypeBytes(GLenum type);
static uint16_t RosetteReadColorIndex(const uint8_t *source, GLenum type,
                                      int swap_bytes,
                                      unsigned int index_bits);

static void RosetteTracePalette(const char *operation, GLenum target,
                                GLint internal_format, GLint start,
                                GLsizei count, GLenum format, GLenum type,
                                const uint8_t *source,
                                const RosettePalette *palette) {
  if (!RosetteGlTraceEnabled() || g_rosette_palette_trace_count >= 32u) return;
  ++g_rosette_palette_trace_count;
  const size_t safe_start = start >= 0 && start < 256 ? (size_t)start : 0u;
  fprintf(stderr,
          "PE32_GL: %s target=0x%X texture=%u internal=0x%X start=%d count=%d format=0x%X type=0x%X source=%p palette_width=%d first=%02X%02X%02X%02X\n",
          operation, target, g_rosette_bound_texture_2d,
          (unsigned int)internal_format, start, count, format, type,
          (const void *)source, palette->width,
          palette->colors[safe_start][0], palette->colors[safe_start][1],
          palette->colors[safe_start][2], palette->colors[safe_start][3]);
}

static void RosetteTraceTexture(GLenum target, GLint level,
                                GLint internal_format, GLsizei width,
                                GLsizei height, GLenum format, GLenum type,
                                const uint8_t *pixels) {
  if (!RosetteGlTraceEnabled() || g_rosette_texture_trace_count >= 32u) return;
  ++g_rosette_texture_trace_count;
  const unsigned int index_bits = RosetteColorIndexBits(internal_format);
  if (pixels != NULL && width > 0 && height > 0 &&
      format == GL_COLOR_INDEX && index_bits != 0u &&
      RosetteColorIndexTypeBytes(type) != 0u) {
    fprintf(stderr,
            "PE32_GL: glTexImage2D target=0x%X texture=%u level=%d internal=0x%X size=%dx%d format=0x%X type=0x%X index_bits=%u palette_width=%d index0=%u index1=%u index2=%u\n",
            target, g_rosette_bound_texture_2d, level,
            (unsigned int)internal_format, width, height,
            format, type, index_bits, g_rosette_shared_palette.width,
            RosetteReadColorIndex(pixels, type, 0, index_bits),
            width > 1 ? RosetteReadColorIndex(pixels + RosetteColorIndexTypeBytes(type), type, 0, index_bits) : 0,
            width > 2 ? RosetteReadColorIndex(pixels + 2u * RosetteColorIndexTypeBytes(type), type, 0, index_bits) : 0);
  } else {
    fprintf(stderr,
            "PE32_GL: glTexImage2D target=0x%X texture=%u level=%d internal=0x%X size=%dx%d format=0x%X type=0x%X data=%p\n",
            target, g_rosette_bound_texture_2d, level,
            (unsigned int)internal_format, width, height,
            format, type, (const void *)pixels);
  }
}

// PE32 applications render in their Win32 client-area coordinates, while the
// Rosette host drawable keeps its own fixed presentation dimensions. This
// transform is configured once after WGL makes the context current and applies
// only to viewport/scissor rectangles submitted through this dispatcher.
static double g_rosette_drawable_scale = 1.0;
static double g_rosette_drawable_offset_x;
static double g_rosette_drawable_offset_y;

static GLint RosetteScaleCoordinate(GLint value, double scale, double offset) {
  const double transformed = (double)value * scale + offset;
  if (!isfinite(transformed)) return value;
  if (transformed >= (double)INT_MAX) return INT_MAX;
  if (transformed <= (double)INT_MIN) return INT_MIN;
  return (GLint)llround(transformed);
}

static GLsizei RosetteScaleExtent(GLsizei value, double scale) {
  if (value <= 0) return value;
  const double transformed = (double)value * scale;
  if (!isfinite(transformed) || transformed >= (double)INT_MAX) return INT_MAX;
  return (GLsizei)llround(transformed);
}

static int RosetteConfigureViewportScale(const uint64_t *args) {
  const uint32_t guest_width = (uint32_t)args[0];
  const uint32_t guest_height = (uint32_t)args[1];
  if (guest_width == 0 || guest_height == 0) return 0;

  GLint drawable[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_VIEWPORT, drawable);
  if (drawable[2] <= 0 || drawable[3] <= 0) return 0;

  const double scale_x = (double)drawable[2] / (double)guest_width;
  const double scale_y = (double)drawable[3] / (double)guest_height;
  if (!isfinite(scale_x) || !isfinite(scale_y) || scale_x <= 0.0 || scale_y <= 0.0)
    return 0;

  // Preserve the guest aspect ratio when it differs from the fixed host
  // drawable. Centering leaves any unused area as letterbox/pillarbox space.
  g_rosette_drawable_scale = fmin(scale_x, scale_y);
  g_rosette_drawable_offset_x =
      ((double)drawable[2] - (double)guest_width * g_rosette_drawable_scale) * 0.5;
  g_rosette_drawable_offset_y =
      ((double)drawable[3] - (double)guest_height * g_rosette_drawable_scale) * 0.5;
  return 1;
}

static void RosetteInitPaletteTable(RosettePalette *palette) {
  if (palette->initialized) return;
  for (size_t i = 0; i < 256; ++i) {
    palette->colors[i][0] = 255;
    palette->colors[i][1] = 255;
    palette->colors[i][2] = 255;
    palette->colors[i][3] = 255;
  }
  // EXT_paletted_texture defines the initial palette as one opaque white
  // entry. A game that uploads a palette replaces this before sampling.
  palette->width = 1;
  palette->format = GL_RGBA;
  palette->initialized = 1;
}

static void RosetteInitPalette(void) {
  RosetteInitPaletteTable(&g_rosette_shared_palette);
}

static RosetteTexturePaletteState *RosetteGetTexturePaletteState(
    GLuint texture, int create) {
  for (RosetteTexturePaletteState *state = g_rosette_texture_palettes;
       state != NULL; state = state->next) {
    if (state->texture == texture) return state;
  }
  if (!create) return NULL;
  RosetteTexturePaletteState *state = calloc(1, sizeof(*state));
  if (state == NULL) return NULL;
  state->texture = texture;
  RosetteInitPaletteTable(&state->palette);
  state->next = g_rosette_texture_palettes;
  g_rosette_texture_palettes = state;
  return state;
}

static void RosetteFreeTexturePaletteState(RosetteTexturePaletteState *state) {
  RosetteIndexedTextureLevel *level = state->levels;
  while (level != NULL) {
    RosetteIndexedTextureLevel *next = level->next;
    free(level->indices);
    free(level);
    level = next;
  }
  free(state);
}

static void RosetteForgetTexture(GLuint texture) {
  RosetteTexturePaletteState **cursor = &g_rosette_texture_palettes;
  while (*cursor != NULL) {
    if ((*cursor)->texture == texture) {
      RosetteTexturePaletteState *removed = *cursor;
      *cursor = removed->next;
      RosetteFreeTexturePaletteState(removed);
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static RosetteIndexedTextureLevel *RosetteGetIndexedLevel(
    RosetteTexturePaletteState *state, GLint level, int create) {
  for (RosetteIndexedTextureLevel *image = state->levels; image != NULL;
       image = image->next) {
    if (image->level == level) return image;
  }
  if (!create) return NULL;
  RosetteIndexedTextureLevel *image = calloc(1, sizeof(*image));
  if (image == NULL) return NULL;
  image->level = level;
  image->next = state->levels;
  state->levels = image;
  return image;
}

static void RosetteForgetIndexedLevel(RosetteTexturePaletteState *state,
                                      GLint level) {
  if (state == NULL) return;
  RosetteIndexedTextureLevel **cursor = &state->levels;
  while (*cursor != NULL) {
    if ((*cursor)->level == level) {
      RosetteIndexedTextureLevel *removed = *cursor;
      *cursor = removed->next;
      free(removed->indices);
      free(removed);
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static size_t RosetteScalarTypeBytes(GLenum type) {
  switch (type) {
    case GL_BYTE:
    case GL_UNSIGNED_BYTE:
      return 1u;
    case GL_SHORT:
    case GL_UNSIGNED_SHORT:
      return 2u;
    case GL_INT:
    case GL_UNSIGNED_INT:
    case GL_FLOAT:
      return 4u;
    case GL_DOUBLE:
      return 8u;
    default:
      return 0u;
  }
}

static GLfloat RosettePaletteComponent(const uint8_t *source, GLenum type,
                                       int swap_bytes) {
  uint8_t encoded[8] = {0};
  const size_t bytes = RosetteScalarTypeBytes(type);
  if (source == NULL || bytes == 0u) return 0.0f;
  for (size_t i = 0; i < bytes; ++i)
    encoded[i] = source[swap_bytes ? bytes - i - 1u : i];
  switch (type) {
    case GL_UNSIGNED_BYTE:
      return (GLfloat)encoded[0] / 255.0f;
    case GL_BYTE: {
      int8_t value;
      memcpy(&value, encoded, sizeof(value));
      return fmaxf(-1.0f, (GLfloat)value / 127.0f);
    }
    case GL_UNSIGNED_SHORT: {
      uint16_t value;
      memcpy(&value, encoded, sizeof(value));
      return (GLfloat)value / 65535.0f;
    }
    case GL_SHORT: {
      int16_t value;
      memcpy(&value, encoded, sizeof(value));
      return fmaxf(-1.0f, (GLfloat)value / 32767.0f);
    }
    case GL_UNSIGNED_INT: {
      uint32_t value;
      memcpy(&value, encoded, sizeof(value));
      return (GLfloat)((double)value / 4294967295.0);
    }
    case GL_INT: {
      int32_t value;
      memcpy(&value, encoded, sizeof(value));
      return fmaxf(-1.0f, (GLfloat)((double)value / 2147483647.0));
    }
    case GL_FLOAT: {
      GLfloat value;
      memcpy(&value, encoded, sizeof(value));
      return value;
    }
    case GL_DOUBLE: {
      GLdouble value;
      memcpy(&value, encoded, sizeof(value));
      return (GLfloat)value;
    }
    default:
      return 0.0f;
  }
}

static void RosetteWritePaletteColor(uint8_t out[4], GLenum format,
                                     GLenum type, const uint8_t *source,
                                     int swap_bytes) {
  GLfloat components[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  const int count = RosetteComponentCount(format);
  if (count <= 0 || source == NULL) return;
  const size_t component_bytes = RosetteScalarTypeBytes(type);
  if (component_bytes == 0u || (size_t)count > SIZE_MAX / component_bytes)
    return;
  for (int i = 0; i < count && i < 4; ++i)
    components[i] = RosettePaletteComponent(
        source + (size_t)i * component_bytes, type, swap_bytes);
  GLfloat r = 0.0f, g = 0.0f, b = 0.0f, a = 1.0f;
  switch (format) {
    case GL_RED:
    case GL_LUMINANCE:
      r = g = b = components[0];
      break;
    case GL_GREEN:
      g = components[0];
      break;
    case GL_BLUE:
      b = components[0];
      break;
    case GL_ALPHA:
      a = components[0];
      break;
    case GL_LUMINANCE_ALPHA:
      r = g = b = components[0];
      a = components[1];
      break;
    case GL_RGB:
    case GL_BGR:
      if (format == GL_BGR) {
        b = components[0]; g = components[1]; r = components[2];
      } else {
        r = components[0]; g = components[1]; b = components[2];
      }
      break;
    case GL_RGBA:
    case GL_BGRA:
      if (format == GL_BGRA) {
        b = components[0]; g = components[1]; r = components[2]; a = components[3];
      } else {
        r = components[0]; g = components[1]; b = components[2]; a = components[3];
      }
      break;
    default:
      break;
  }
  const GLfloat rgba[4] = {r, g, b, a};
  for (size_t i = 0; i < 4; ++i) {
    const GLfloat value = fminf(1.0f, fmaxf(0.0f, rgba[i]));
    out[i] = (uint8_t)lrintf(value * 255.0f);
  }
}

static const RosettePalette *RosettePaletteForTexture(
    const RosetteTexturePaletteState *state) {
  return state != NULL && state->has_local_palette
             ? &state->palette
             : &g_rosette_shared_palette;
}

static unsigned int RosetteColorIndexBits(GLint internal_format) {
  switch ((GLenum)internal_format) {
    case 0x80E2u: return 1u;  // GL_COLOR_INDEX1_EXT
    case 0x80E3u: return 2u;  // GL_COLOR_INDEX2_EXT
    case 0x80E4u: return 4u;  // GL_COLOR_INDEX4_EXT
    case 0x80E5u: return 8u;  // GL_COLOR_INDEX8_EXT
    case 0x80E6u: return 12u; // GL_COLOR_INDEX12_EXT
    case 0x80E7u: return 16u; // GL_COLOR_INDEX16_EXT
    case GL_COLOR_INDEX: return 8u;
    default: return 0u;
  }
}

static size_t RosetteColorIndexTypeBytes(GLenum type) {
  switch (type) {
    case GL_BYTE:
    case GL_UNSIGNED_BYTE:
      return 1u;
    case GL_SHORT:
    case GL_UNSIGNED_SHORT:
      return 2u;
    case GL_INT:
    case GL_UNSIGNED_INT:
      return 4u;
    default:
      return 0u;
  }
}

static uint16_t RosetteReadColorIndex(const uint8_t *source, GLenum type,
                                      int swap_bytes,
                                      unsigned int index_bits) {
  uint32_t value = 0;
  const size_t bytes = RosetteColorIndexTypeBytes(type);
  if (source == NULL || bytes == 0u) return 0;
  uint8_t encoded[4] = {0, 0, 0, 0};
  for (size_t i = 0; i < bytes; ++i)
    encoded[i] = source[swap_bytes ? bytes - i - 1u : i];
  if (bytes == 1u) {
    value = encoded[0];
  } else if (bytes == 2u) {
    uint16_t short_value;
    memcpy(&short_value, encoded, sizeof(short_value));
    value = short_value;
  } else {
    memcpy(&value, encoded, sizeof(value));
  }
  const uint32_t mask = index_bits >= 16u
                           ? 0xFFFFu
                           : ((1u << index_bits) - 1u);
  return (uint16_t)(value & mask);
}

static uint16_t RosettePaletteIndex(uint16_t index,
                                    GLint internal_format,
                                    const RosettePalette *palette) {
  const unsigned int image_bits = RosetteColorIndexBits(internal_format);
  const size_t width = palette->width > 0 ? (size_t)palette->width : 1u;
  if (image_bits == 0u) return 0;
  unsigned int palette_bits = 0u;
  size_t palette_capacity = 1u;
  while (palette_capacity < width && palette_bits < 16u) {
    palette_capacity <<= 1u;
    ++palette_bits;
  }
  const unsigned int used_bits = image_bits < palette_bits
                                     ? image_bits
                                     : palette_bits;
  if (used_bits == 0u) return 0;
  if (used_bits < 16u) return (uint16_t)(index & ((1u << used_bits) - 1u));
  return index;
}

static uint8_t *RosetteExpandIndexedImage(const uint16_t *indices,
                                          GLsizei width, GLsizei height,
                                          const RosettePalette *palette,
                                          GLint internal_format) {
  if (width < 0 || height < 0 ||
      (size_t)width > SIZE_MAX / 4u / (size_t)(height ? height : 1))
    return NULL;
  const size_t pixel_count = (size_t)width * (size_t)height;
  if (pixel_count > SIZE_MAX / 4u) return NULL;
  uint8_t *rgba = malloc(pixel_count != 0 ? pixel_count * 4u : 1u);
  if (rgba == NULL) return NULL;
  const size_t palette_width = palette->width > 0 ? (size_t)palette->width : 1u;
  for (size_t i = 0; i < pixel_count; ++i) {
    size_t index = RosettePaletteIndex(indices[i], internal_format, palette);
    if (index >= palette_width) index = palette_width - 1u;
    memcpy(rgba + i * 4u, palette->colors[index], 4u);
  }
  return rgba;
}

static int RosetteUploadCachedIndexedLevel(RosetteTexturePaletteState *state,
                                           RosetteIndexedTextureLevel *image) {
  const RosettePalette *palette = RosettePaletteForTexture(state);
  uint8_t *rgba = RosetteExpandIndexedImage(image->indices, image->width,
                                             image->height, palette,
                                             image->internal_format);
  if (rgba == NULL) return 0;
  // Indexed rows were expanded into a separate tightly packed RGBA buffer.
  // Preserve the guest's unpack state, but prevent its original source-image
  // row length and skips from being applied again to this new buffer.
  GLint unpack_alignment = 4;
  GLint unpack_row_length = 0;
  GLint unpack_skip_rows = 0;
  GLint unpack_skip_pixels = 0;
  glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpack_alignment);
  glGetIntegerv(GL_UNPACK_ROW_LENGTH, &unpack_row_length);
  glGetIntegerv(GL_UNPACK_SKIP_ROWS, &unpack_skip_rows);
  glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &unpack_skip_pixels);
  glBindTexture(GL_TEXTURE_2D, state->texture);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
  glTexImage2D(GL_TEXTURE_2D, image->level, GL_RGBA, image->width,
               image->height, image->border, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
  glPixelStorei(GL_UNPACK_ALIGNMENT, unpack_alignment);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, unpack_row_length);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, unpack_skip_rows);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, unpack_skip_pixels);
  free(rgba);
  if (RosetteGlTraceEnabled() && g_rosette_reupload_trace_count < 32u) {
    ++g_rosette_reupload_trace_count;
    fprintf(stderr,
            "PE32_GL: palette_reupload texture=%u level=%d size=%dx%d palette_width=%d\n",
            state->texture, image->level, image->width, image->height,
            palette->width);
  }
  return 1;
}

static void RosetteRefreshPaletteUsers(RosetteTexturePaletteState *only_state) {
  const GLuint previous_binding = g_rosette_bound_texture_2d;
  for (RosetteTexturePaletteState *state = only_state != NULL
                                                ? only_state
                                                : g_rosette_texture_palettes;
       state != NULL; state = only_state != NULL ? NULL : state->next) {
    if (only_state == NULL && state->has_local_palette) continue;
    for (RosetteIndexedTextureLevel *image = state->levels; image != NULL;
         image = image->next) {
      (void)RosetteUploadCachedIndexedLevel(state, image);
    }
  }
  glBindTexture(GL_TEXTURE_2D, previous_binding);
}

static size_t RosetteGetVectorLength(GLenum pname) {
  switch (pname) {
    case GL_VIEWPORT:
    case GL_SCISSOR_BOX:
    case GL_COLOR_WRITEMASK:
    case GL_CURRENT_COLOR:
    case GL_CURRENT_TEXTURE_COORDS:
    case GL_CURRENT_RASTER_COLOR:
    case GL_CURRENT_RASTER_POSITION:
      return 4;
    case GL_MAX_VIEWPORT_DIMS:
      return 2;
    default:
      return 1;
  }
}

static size_t RosetteLightParameterCount(GLenum pname) {
  switch (pname) {
    case GL_AMBIENT:
    case GL_DIFFUSE:
    case GL_SPECULAR:
    case GL_POSITION:
      return 4;
    case GL_SPOT_DIRECTION:
      return 3;
    case GL_SPOT_EXPONENT:
    case GL_SPOT_CUTOFF:
    case GL_CONSTANT_ATTENUATION:
    case GL_LINEAR_ATTENUATION:
    case GL_QUADRATIC_ATTENUATION:
      return 1;
    default:
      return 4;
  }
}

static size_t RosetteTextureEnvironmentParameterCount(GLenum pname) {
  return pname == GL_TEXTURE_ENV_COLOR ? 4u : 1u;
}

static int RosetteCopyGlString(GLenum name, uint8_t *memory, size_t memory_size,
                               uint32_t guest_base, uint64_t output_address) {
  uint8_t *output = RosetteGuestPointer(memory, memory_size, guest_base,
                                        output_address, 16384u);
  if (output == NULL) return 0;
  const GLubyte *value = glGetString(name);
  if (value == NULL) return 0;
  const size_t value_len = strnlen((const char *)value, 15000u);
  memcpy(output, value, value_len);
  size_t length = value_len;
  if (name == GL_EXTENSIONS &&
      strstr((const char *)value, "GL_EXT_paletted_texture") == NULL) {
    static const char extension[] = " GL_EXT_paletted_texture";
    if (length + sizeof(extension) <= 16384u) {
      memcpy(output + length, extension, sizeof(extension));
      length += sizeof(extension) - 1u;
    }
  }
  output[length] = 0;
  return 1;
}

// One compatibility dispatcher keeps the guest-facing API small while still
// routing each fixed-function call to the platform's real OpenGL/GLU runtime.
// Return values are copied to the PE32 EAX register by the Zig thunk.
uint64_t rosette_macho_legacy_gl_dispatch(
    const char *name, const uint64_t *a, uint8_t *memory, size_t memory_size,
    uint32_t guest_base) {
  if (name == NULL || a == NULL) return 0;
  if (strcmp(name, "rosetteConfigureViewportScale") == 0)
    return (uint64_t)RosetteConfigureViewportScale(a);
  RosetteInitPalette();

  if (strcmp(name, "glBegin") == 0) {
    const GLenum mode = (GLenum)a[0];
    glBegin(mode);
    if (RosetteGlTraceEnabled() && g_rosette_begin_trace_count < 128u) {
      ++g_rosette_begin_trace_count;
      fprintf(stderr,
              "PE32_GL: glBegin list=%u mode=0x%X texture=%u texture_2d=%d\n",
              g_rosette_compiling_list, mode, g_rosette_bound_texture_2d,
              g_rosette_texture_2d_enabled);
    }
  }
  else if (strcmp(name, "glEnd") == 0) glEnd();
  else if (strcmp(name, "glVertex3f") == 0) glVertex3f(RosetteFloat32(a, 0), RosetteFloat32(a, 1), RosetteFloat32(a, 2));
  else if (strcmp(name, "glVertex2f") == 0) glVertex2f(RosetteFloat32(a, 0), RosetteFloat32(a, 1));
  else if (strcmp(name, "glVertex3dv") == 0) {
    const GLdouble *v = RosetteGuestPointer(memory, memory_size, guest_base, a[0], 3u * sizeof(GLdouble));
    if (!v) return 0; glVertex3dv(v);
  } else if (strcmp(name, "glNormal3f") == 0) glNormal3f(RosetteFloat32(a, 0), RosetteFloat32(a, 1), RosetteFloat32(a, 2));
  else if (strcmp(name, "glNormal3dv") == 0) {
    const GLdouble *v = RosetteGuestPointer(memory, memory_size, guest_base, a[0], 3u * sizeof(GLdouble));
    if (!v) return 0; glNormal3dv(v);
  } else if (strcmp(name, "glColor3f") == 0) glColor3f(RosetteFloat32(a, 0), RosetteFloat32(a, 1), RosetteFloat32(a, 2));
  else if (strcmp(name, "glColor3fv") == 0) {
    const GLfloat *v = RosetteGuestPointer(memory, memory_size, guest_base, a[0], 3u * sizeof(GLfloat));
    if (!v) return 0; glColor3fv(v);
  } else if (strcmp(name, "glColor4fv") == 0) {
    const GLfloat *v = RosetteGuestPointer(memory, memory_size, guest_base, a[0], 4u * sizeof(GLfloat));
    if (!v) return 0; glColor4fv(v);
  } else if (strcmp(name, "glTexCoord2f") == 0) {
    const GLfloat s = RosetteFloat32(a, 0);
    const GLfloat t = RosetteFloat32(a, 1);
    glTexCoord2f(s, t);
    if (RosetteGlTraceEnabled() && g_rosette_texcoord_trace_count < 256u) {
      ++g_rosette_texcoord_trace_count;
      fprintf(stderr,
              "PE32_GL: glTexCoord2f list=%u texture=%u texture_2d=%d s=%.6g t=%.6g\n",
              g_rosette_compiling_list, g_rosette_bound_texture_2d,
              g_rosette_texture_2d_enabled,
              (double)s, (double)t);
    }
  } else if (strcmp(name, "glTexCoord2d") == 0) {
    const GLdouble s = RosetteFloat64(a, 0);
    const GLdouble t = RosetteFloat64(a, 2);
    glTexCoord2d(s, t);
    if (RosetteGlTraceEnabled() && g_rosette_texcoord_trace_count < 256u) {
      ++g_rosette_texcoord_trace_count;
      fprintf(stderr,
              "PE32_GL: glTexCoord2d list=%u texture=%u texture_2d=%d s=%.9g t=%.9g\n",
              g_rosette_compiling_list, g_rosette_bound_texture_2d,
              g_rosette_texture_2d_enabled,
              s, t);
    }
  }
  else if (strcmp(name, "glMatrixMode") == 0) glMatrixMode((GLenum)a[0]);
  else if (strcmp(name, "glLoadIdentity") == 0) glLoadIdentity();
  else if (strcmp(name, "glPushMatrix") == 0) glPushMatrix();
  else if (strcmp(name, "glPopMatrix") == 0) glPopMatrix();
  else if (strcmp(name, "glTranslatef") == 0) glTranslatef(RosetteFloat32(a, 0), RosetteFloat32(a, 1), RosetteFloat32(a, 2));
  else if (strcmp(name, "glTranslated") == 0) glTranslated(RosetteFloat64(a, 0), RosetteFloat64(a, 2), RosetteFloat64(a, 4));
  else if (strcmp(name, "glRotatef") == 0) glRotatef(RosetteFloat32(a, 0), RosetteFloat32(a, 1), RosetteFloat32(a, 2), RosetteFloat32(a, 3));
  else if (strcmp(name, "glRotated") == 0) glRotated(RosetteFloat64(a, 0), RosetteFloat64(a, 2), RosetteFloat64(a, 4), RosetteFloat64(a, 6));
  else if (strcmp(name, "glScaled") == 0) glScaled(RosetteFloat64(a, 0), RosetteFloat64(a, 2), RosetteFloat64(a, 4));
  else if (strcmp(name, "glEnable") == 0) {
    glEnable((GLenum)a[0]);
    if ((GLenum)a[0] == GL_TEXTURE_2D) g_rosette_texture_2d_enabled = 1;
    if ((GLenum)a[0] == GL_TEXTURE_2D && RosetteGlTraceEnabled() &&
        g_rosette_texture_enable_trace_count < 128u) {
      ++g_rosette_texture_enable_trace_count;
      fprintf(stderr, "PE32_GL: glEnable GL_TEXTURE_2D list=%u\n",
              g_rosette_compiling_list);
    }
  } else if (strcmp(name, "glDisable") == 0) {
    glDisable((GLenum)a[0]);
    if ((GLenum)a[0] == GL_TEXTURE_2D) g_rosette_texture_2d_enabled = 0;
    if ((GLenum)a[0] == GL_TEXTURE_2D && RosetteGlTraceEnabled() &&
        g_rosette_texture_enable_trace_count < 128u) {
      ++g_rosette_texture_enable_trace_count;
      fprintf(stderr, "PE32_GL: glDisable GL_TEXTURE_2D list=%u\n",
              g_rosette_compiling_list);
    }
  }
  else if (strcmp(name, "glHint") == 0) glHint((GLenum)a[0], (GLenum)a[1]);
  else if (strcmp(name, "glScissor") == 0) glScissor(
      RosetteScaleCoordinate((GLint)a[0], g_rosette_drawable_scale,
                            g_rosette_drawable_offset_x),
      RosetteScaleCoordinate((GLint)a[1], g_rosette_drawable_scale,
                            g_rosette_drawable_offset_y),
      RosetteScaleExtent((GLsizei)a[2], g_rosette_drawable_scale),
      RosetteScaleExtent((GLsizei)a[3], g_rosette_drawable_scale));
  else if (strcmp(name, "glViewport") == 0) glViewport(
      RosetteScaleCoordinate((GLint)a[0], g_rosette_drawable_scale,
                            g_rosette_drawable_offset_x),
      RosetteScaleCoordinate((GLint)a[1], g_rosette_drawable_scale,
                            g_rosette_drawable_offset_y),
      RosetteScaleExtent((GLsizei)a[2], g_rosette_drawable_scale),
      RosetteScaleExtent((GLsizei)a[3], g_rosette_drawable_scale));
  else if (strcmp(name, "glCullFace") == 0) glCullFace((GLenum)a[0]);
  else if (strcmp(name, "glFrontFace") == 0) glFrontFace((GLenum)a[0]);
  else if (strcmp(name, "glLightModelfv") == 0) {
    const GLenum pname = (GLenum)a[0];
    const size_t count = pname == GL_LIGHT_MODEL_AMBIENT ? 4u : 1u;
    const GLfloat *v = RosetteGuestPointer(memory, memory_size, guest_base, a[1], count * sizeof(GLfloat));
    if (!v) return 0; glLightModelfv(pname, v);
  } else if (strcmp(name, "glLightModeli") == 0) glLightModeli((GLenum)a[0], (GLint)a[1]);
  else if (strcmp(name, "glLightfv") == 0) {
    const GLenum pname = (GLenum)a[1];
    const size_t count = RosetteLightParameterCount(pname);
    const GLfloat *v = RosetteGuestPointer(memory, memory_size, guest_base, a[2], count * sizeof(GLfloat));
    if (!v) return 0; glLightfv((GLenum)a[0], pname, v);
  } else if (strcmp(name, "glTexEnvi") == 0) glTexEnvi((GLenum)a[0], (GLenum)a[1], (GLint)a[2]);
  else if (strcmp(name, "glGetTexEnviv") == 0) {
    const size_t count = RosetteTextureEnvironmentParameterCount((GLenum)a[1]);
    GLint *v = RosetteGuestPointer(memory, memory_size, guest_base, a[2], count * sizeof(GLint));
    if (!v) return 0; glGetTexEnviv((GLenum)a[0], (GLenum)a[1], v);
  } else if (strcmp(name, "glGenTextures") == 0 || strcmp(name, "glDeleteTextures") == 0) {
    const GLsizei count = (GLsizei)a[0];
    if (count < 0 || count > 4096) return 0;
    GLuint *v = RosetteGuestPointer(memory, memory_size, guest_base, a[1], (size_t)count * sizeof(GLuint));
    if (!v && count != 0) return 0;
    if (name[2] == 'G') {
      glGenTextures(count, v);
      if (RosetteGlTraceEnabled() && g_rosette_gen_trace_count < 64u) {
        ++g_rosette_gen_trace_count;
        fprintf(stderr, "PE32_GL: glGenTextures count=%d output=0x%llX ids=",
                count, (unsigned long long)a[1]);
        for (GLsizei i = 0; i < count && i < 16; ++i)
          fprintf(stderr, "%s%u", i == 0 ? "" : ",", v[i]);
        fprintf(stderr, "\n");
      }
    } else {
      glDeleteTextures(count, v);
      for (GLsizei i = 0; i < count; ++i) {
        if (g_rosette_bound_texture_2d == v[i]) g_rosette_bound_texture_2d = 0;
        RosetteForgetTexture(v[i]);
      }
    }
  } else if (strcmp(name, "glBindTexture") == 0) {
    const GLenum target = (GLenum)a[0];
    const GLuint texture = (GLuint)a[1];
    glBindTexture(target, texture);
    if (target == GL_TEXTURE_2D) g_rosette_bound_texture_2d = texture;
    if (RosetteGlTraceEnabled() && g_rosette_bind_trace_count < 64u) {
      ++g_rosette_bind_trace_count;
      fprintf(stderr,
              "PE32_GL: glBindTexture list=%u target=0x%X texture=%u\n",
              g_rosette_compiling_list, target, texture);
    }
  }
  else if (strcmp(name, "glTexImage2D") == 0) {
    const GLenum target = (GLenum)a[0];
    const GLint level = (GLint)a[1];
    const GLint internal = (GLint)a[2];
    const GLsizei width = (GLsizei)a[3], height = (GLsizei)a[4];
    const GLint border = (GLint)a[5];
    const GLenum format = (GLenum)a[6], type = (GLenum)a[7];
    if (width < 0 || height < 0 || width > 16384 || height > 16384) return 0;
    const size_t pixel_bytes = RosettePixelBytes(format, type);
    const uint8_t *pixels = NULL;
    GLint unpack_alignment = 4;
    GLint unpack_row_length = 0;
    GLint unpack_skip_rows = 0;
    GLint unpack_skip_pixels = 0;
    GLint unpack_swap_bytes = 0;
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpack_alignment);
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &unpack_row_length);
    glGetIntegerv(GL_UNPACK_SKIP_ROWS, &unpack_skip_rows);
    glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &unpack_skip_pixels);
    glGetIntegerv(GL_UNPACK_SWAP_BYTES, &unpack_swap_bytes);
    if (a[8] != 0) {
      if (pixel_bytes == 0 || unpack_skip_rows < 0 || unpack_skip_pixels < 0 ||
          unpack_row_length < 0) return 0;
      const size_t source_width = unpack_row_length > 0
                                      ? (size_t)unpack_row_length
                                      : (size_t)width;
      if (source_width > SIZE_MAX / pixel_bytes ||
          (size_t)width > SIZE_MAX / pixel_bytes) return 0;
      const size_t row = RosetteAlignedRowBytes(source_width * pixel_bytes,
                                                unpack_alignment);
      const size_t active_row = (size_t)width * pixel_bytes;
      if (source_width < (size_t)width || row < active_row) return 0;
      const size_t skip_pixels = (size_t)unpack_skip_pixels * pixel_bytes;
      if ((size_t)unpack_skip_pixels != 0 &&
          skip_pixels / (size_t)unpack_skip_pixels != pixel_bytes) return 0;
      const size_t skip_rows = (size_t)unpack_skip_rows * row;
      if ((size_t)unpack_skip_rows != 0 &&
          skip_rows / (size_t)unpack_skip_rows != row) return 0;
      if (skip_rows > SIZE_MAX - skip_pixels ||
          skip_rows + skip_pixels > SIZE_MAX - active_row) return 0;
      size_t required_size = 0;
      if (height > 0 && width > 0) {
        if (row == 0 || (size_t)(height - 1) >
            (SIZE_MAX - skip_rows - skip_pixels - active_row) / row)
          return 0;
        required_size = skip_rows + skip_pixels +
                        (size_t)(height - 1) * row + active_row;
      }
      pixels = RosetteGuestPointer(memory, memory_size, guest_base, a[8],
                                   required_size);
      if (!pixels && width != 0 && height != 0) return 0;
    }
    RosetteTraceTexture(target, level, internal, width, height, format, type,
                        pixels);
    const unsigned int index_bits = RosetteColorIndexBits(internal);
    const size_t index_bytes = RosetteColorIndexTypeBytes(type);
    if (pixels != NULL && format == GL_COLOR_INDEX && index_bits != 0u) {
      if (target != GL_TEXTURE_2D || index_bytes == 0u ||
          width < 0 || height < 0 ||
          (size_t)width > SIZE_MAX / sizeof(uint16_t) /
                              (size_t)(height ? height : 1)) return 0;
      RosetteTexturePaletteState *state =
          RosetteGetTexturePaletteState(g_rosette_bound_texture_2d, 1);
      if (state == NULL) return 0;
      const size_t pixel_count = (size_t)width * (size_t)height;
      if (pixel_count > SIZE_MAX / sizeof(uint16_t)) return 0;
      uint16_t *indices = malloc(pixel_count != 0
                                     ? pixel_count * sizeof(uint16_t)
                                     : sizeof(uint16_t));
      if (indices == NULL) return 0;
      const size_t source_width = unpack_row_length > 0
                                      ? (size_t)unpack_row_length
                                      : (size_t)width;
      if (source_width < (size_t)width ||
          source_width > SIZE_MAX / index_bytes) {
        free(indices);
        return 0;
      }
      const size_t source_row_bytes = source_width * index_bytes;
      if (source_row_bytes > SIZE_MAX - 7u) {
        free(indices);
        return 0;
      }
      const size_t row_stride =
          RosetteAlignedRowBytes(source_row_bytes, unpack_alignment);
      if (row_stride != 0u &&
          (size_t)unpack_skip_rows > SIZE_MAX / row_stride) {
        free(indices);
        return 0;
      }
      if ((size_t)unpack_skip_pixels > SIZE_MAX / index_bytes) {
        free(indices);
        return 0;
      }
      const size_t skip = (size_t)unpack_skip_rows * row_stride +
                          (size_t)unpack_skip_pixels * index_bytes;
      const uint8_t *source = pixels + skip;
      for (GLsizei y = 0; y < height; ++y)
        for (GLsizei x = 0; x < width; ++x)
          indices[(size_t)y * (size_t)width + (size_t)x] =
              RosetteReadColorIndex(
                  source + (size_t)y * row_stride + (size_t)x * index_bytes,
                  type, unpack_swap_bytes, index_bits);
      RosetteIndexedTextureLevel *image =
          RosetteGetIndexedLevel(state, level, 1);
      if (image == NULL) {
        free(indices);
        return 0;
      }
      free(image->indices);
      image->width = width;
      image->height = height;
      image->border = border;
      image->internal_format = internal;
      image->indices = indices;
      if (!RosetteUploadCachedIndexedLevel(state, image)) return 0;
    } else if (format == GL_COLOR_INDEX && index_bits != 0u) {
      if (target != GL_TEXTURE_2D || index_bytes == 0u) return 0;
      RosetteTexturePaletteState *state =
          RosetteGetTexturePaletteState(g_rosette_bound_texture_2d, 0);
      RosetteForgetIndexedLevel(state, level);
      glTexImage2D(target, level, GL_RGBA, width, height, border, GL_RGBA,
                   GL_UNSIGNED_BYTE, NULL);
    } else {
      RosetteTexturePaletteState *state =
          RosetteGetTexturePaletteState(g_rosette_bound_texture_2d, 0);
      RosetteForgetIndexedLevel(state, level);
      glTexImage2D(target, level, internal, width, height, border, format, type, pixels);
    }
  } else if (strcmp(name, "glTexParameteri") == 0) {
    glTexParameteri((GLenum)a[0], (GLenum)a[1], (GLint)a[2]);
    if (RosetteGlTraceEnabled() && g_rosette_parameter_trace_count < 64u) {
      ++g_rosette_parameter_trace_count;
      fprintf(stderr,
              "PE32_GL: glTexParameteri list=%u texture=%u target=0x%X pname=0x%X value=0x%X\n",
              g_rosette_compiling_list, g_rosette_bound_texture_2d,
              (GLenum)a[0], (GLenum)a[1], (unsigned int)a[2]);
    }
  }
  else if (strcmp(name, "glShadeModel") == 0) glShadeModel((GLenum)a[0]);
  else if (strcmp(name, "glPolygonMode") == 0) glPolygonMode((GLenum)a[0], (GLenum)a[1]);
  else if (strcmp(name, "glClearDepth") == 0) glClearDepth(RosetteFloat64(a, 0));
  else if (strcmp(name, "glPixelStorei") == 0) glPixelStorei((GLenum)a[0], (GLint)a[1]);
  else if (strcmp(name, "glBlendFunc") == 0) glBlendFunc((GLenum)a[0], (GLenum)a[1]);
  else if (strcmp(name, "glClear") == 0) glClear((GLbitfield)a[0]);
  else if (strcmp(name, "glFlush") == 0) glFlush();
  else if (strcmp(name, "glFinish") == 0) glFinish();
  else if (strcmp(name, "glGetString") == 0) return RosetteCopyGlString((GLenum)a[0], memory, memory_size, guest_base, a[1]);
  else if (strcmp(name, "glGetIntegerv") == 0) {
    const GLenum pname = (GLenum)a[0];
    const size_t count = RosetteGetVectorLength(pname);
    GLint *v = RosetteGuestPointer(memory, memory_size, guest_base, a[1], count * sizeof(GLint));
    if (!v) return 0; glGetIntegerv(pname, v);
  } else if (strcmp(name, "glGenLists") == 0) return glGenLists((GLsizei)a[0]);
  else if (strcmp(name, "glNewList") == 0) {
    glNewList((GLuint)a[0], (GLenum)a[1]);
    g_rosette_compiling_list = (GLuint)a[0];
    if (RosetteGlTraceEnabled() && g_rosette_list_trace_count < 128u) {
      ++g_rosette_list_trace_count;
      fprintf(stderr, "PE32_GL: glNewList id=%u mode=0x%X\n",
              (GLuint)a[0], (GLenum)a[1]);
    }
  } else if (strcmp(name, "glEndList") == 0) {
    const GLuint list = g_rosette_compiling_list;
    glEndList();
    if (RosetteGlTraceEnabled() && g_rosette_list_trace_count < 128u) {
      ++g_rosette_list_trace_count;
      fprintf(stderr, "PE32_GL: glEndList id=%u\n", list);
    }
    g_rosette_compiling_list = 0;
  } else if (strcmp(name, "glCallList") == 0) {
    const GLuint list = (GLuint)a[0];
    if (!RosetteGlTraceEnabled()) {
      glCallList(list);
    } else {
      GLint bound_before = 0, bound_after = 0;
      const GLboolean texture_before = glIsEnabled(GL_TEXTURE_2D);
      glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound_before);
      glCallList(list);
      glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound_after);
      const GLboolean texture_after = glIsEnabled(GL_TEXTURE_2D);
      if (g_rosette_list_call_trace_count < 256u) {
        ++g_rosette_list_call_trace_count;
        fprintf(stderr,
                "PE32_GL: glCallList id=%u binding=%d->%d texture_2d=%d->%d error=0x%X\n",
                list, bound_before, bound_after, texture_before, texture_after,
                glGetError());
      }
      g_rosette_bound_texture_2d = (GLuint)bound_after;
      g_rosette_texture_2d_enabled = texture_after != GL_FALSE;
    }
  }
  else if (strcmp(name, "gluLookAt") == 0) gluLookAt(RosetteFloat64(a, 0), RosetteFloat64(a, 2), RosetteFloat64(a, 4), RosetteFloat64(a, 6), RosetteFloat64(a, 8), RosetteFloat64(a, 10), RosetteFloat64(a, 12), RosetteFloat64(a, 14), RosetteFloat64(a, 16));
  else if (strcmp(name, "gluOrtho2D") == 0) gluOrtho2D(RosetteFloat64(a, 0), RosetteFloat64(a, 2), RosetteFloat64(a, 4), RosetteFloat64(a, 6));
  else if (strcmp(name, "gluPerspective") == 0) gluPerspective(RosetteFloat64(a, 0), RosetteFloat64(a, 2), RosetteFloat64(a, 4), RosetteFloat64(a, 6));
  else if (strcmp(name, "gluScaleImage") == 0) {
    // PE32 gluScaleImage(format, widthIn, heightIn, typeIn, dataIn,
    //                    widthOut, heightOut, typeOut, dataOut) is nine
    // stack words. Keep the pointer and scalar positions aligned with GLU.
    const GLenum format = (GLenum)a[0], input_type = (GLenum)a[3], output_type = (GLenum)a[7];
    const GLsizei in_width = (GLsizei)a[1], in_height = (GLsizei)a[2];
    const GLsizei out_width = (GLsizei)a[5], out_height = (GLsizei)a[6];
    if (in_width < 0 || in_height < 0 || out_width < 0 || out_height < 0 ||
        in_width > 16384 || in_height > 16384 || out_width > 16384 || out_height > 16384) return 100901u;
    const size_t in_pixel = RosettePixelBytes(format, input_type);
    const size_t out_pixel = RosettePixelBytes(format, output_type);
    if (in_pixel == 0 || out_pixel == 0 ||
        (size_t)in_width * (size_t)in_height > SIZE_MAX / in_pixel ||
        (size_t)out_width * (size_t)out_height > SIZE_MAX / out_pixel) return 100901u;
    const void *input = RosetteGuestPointer(memory, memory_size, guest_base, a[4], (size_t)in_width * (size_t)in_height * in_pixel);
    void *output = RosetteGuestPointer(memory, memory_size, guest_base, a[8], (size_t)out_width * (size_t)out_height * out_pixel);
    if (!input || !output) return 100901u;
    const GLint result = gluScaleImage(format, in_width, in_height, input_type, input, out_width, out_height, output_type, output);
    if (RosetteGlTraceEnabled() && g_rosette_glu_scale_trace_count < 64u) {
      ++g_rosette_glu_scale_trace_count;
      fprintf(stderr,
              "PE32_GL: gluScaleImage format=0x%X in=%dx%d typeIn=0x%X dataIn=0x%llX out=%dx%d typeOut=0x%X dataOut=0x%llX result=%d\n",
              format, in_width, in_height, input_type,
              (unsigned long long)a[4], out_width, out_height, output_type,
              (unsigned long long)a[8], result);
    }
    return (uint64_t)result;
  } else if (strcmp(name, "glAddSwapHintRectWIN") == 0) {
    // The hint only guides presentation scheduling; the compatibility
    // context's double-buffer swap still presents the complete back buffer.
  } else if (strcmp(name, "glColorTableEXT") == 0 || strcmp(name, "glColorSubTableEXT") == 0) {
    const int is_sub = strcmp(name, "glColorSubTableEXT") == 0;
    const GLenum target = (GLenum)a[0];
    GLint start = is_sub ? (GLint)a[1] : 0;
    const GLsizei count = (GLsizei)a[2];
    const GLenum format = is_sub ? (GLenum)a[3] : (GLenum)a[3];
    const GLenum type = is_sub ? (GLenum)a[4] : (GLenum)a[4];
    const uint64_t source_address = is_sub ? a[5] : a[5];
    if (target != GL_TEXTURE_2D && target != 0x81FBu) return 0; // shared palette target
    if (count < 0 || count > 256 || start < 0 || start > 256 || count > 256 - start) return 0;
    const size_t bytes = RosettePixelBytes(format, type);
    if (bytes == 0 || (size_t)count > SIZE_MAX / bytes) return 0;
    GLint unpack_alignment = 4;
    GLint unpack_row_length = 0;
    GLint unpack_skip_rows = 0;
    GLint unpack_skip_pixels = 0;
    GLint unpack_swap_bytes = 0;
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpack_alignment);
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &unpack_row_length);
    glGetIntegerv(GL_UNPACK_SKIP_ROWS, &unpack_skip_rows);
    glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &unpack_skip_pixels);
    glGetIntegerv(GL_UNPACK_SWAP_BYTES, &unpack_swap_bytes);
    if (unpack_row_length < 0 || unpack_skip_rows < 0 ||
        unpack_skip_pixels < 0 ||
        (unpack_row_length > 0 && unpack_row_length < count))
      return 0;
    const size_t source_width = unpack_row_length > 0
                                    ? (size_t)unpack_row_length
                                    : (size_t)count;
    if (source_width > SIZE_MAX / bytes ||
        (size_t)unpack_skip_pixels > SIZE_MAX / bytes)
      return 0;
    const size_t source_row_bytes = source_width * bytes;
    if (source_row_bytes > SIZE_MAX - 7u) return 0;
    const size_t source_row_stride =
        RosetteAlignedRowBytes(source_row_bytes, unpack_alignment);
    if (source_row_stride != 0u &&
        (size_t)unpack_skip_rows > SIZE_MAX / source_row_stride)
      return 0;
    const size_t skip_rows_bytes =
        (size_t)unpack_skip_rows * source_row_stride;
    const size_t skip_pixels_bytes = (size_t)unpack_skip_pixels * bytes;
    if (skip_rows_bytes > SIZE_MAX - skip_pixels_bytes ||
        skip_rows_bytes + skip_pixels_bytes > SIZE_MAX - (size_t)count * bytes)
      return 0;
    const size_t source_offset = skip_rows_bytes + skip_pixels_bytes;
    const size_t source_size = source_offset + (size_t)count * bytes;
    const uint8_t *source_base =
        RosetteGuestPointer(memory, memory_size, guest_base, source_address,
                            source_size);
    const uint8_t *source = source_base != NULL ? source_base + source_offset : NULL;
    if (!source && count != 0) return 0;
    RosettePalette *palette = NULL;
    RosetteTexturePaletteState *state = NULL;
    if (target == 0x81FBu) {
      palette = &g_rosette_shared_palette;
    } else {
      state = RosetteGetTexturePaletteState(g_rosette_bound_texture_2d, 1);
      if (state == NULL) return 0;
      palette = &state->palette;
      state->has_local_palette = 1;
    }
    if (!is_sub) {
      palette->width = count;
      palette->format = (GLenum)a[1];
      if (palette->width == 0) palette->width = 1;
      start = 0;
    }
    for (GLsizei i = 0; i < count; ++i)
      RosetteWritePaletteColor(palette->colors[start + i], format, type,
                               source + (size_t)i * bytes,
                               unpack_swap_bytes != 0);
    RosetteTracePalette(is_sub ? "glColorSubTableEXT" : "glColorTableEXT",
                        target, is_sub ? 0 : (GLint)a[1], start, count, format,
                        type, source, palette);
    if (target == 0x81FBu)
      RosetteRefreshPaletteUsers(NULL);
    else
      RosetteRefreshPaletteUsers(state);
  } else if (strcmp(name, "glGetColorTableParameterivEXT") == 0) {
    const GLenum pname = (GLenum)a[1];
    GLint *value = RosetteGuestPointer(memory, memory_size, guest_base, a[2], sizeof(GLint));
    if (!value) return 0;
    const GLenum target = (GLenum)a[0];
    RosettePalette *palette = NULL;
    if (target == 0x81FBu) {
      palette = &g_rosette_shared_palette;
    } else if (target == GL_TEXTURE_2D) {
      RosetteTexturePaletteState *state =
          RosetteGetTexturePaletteState(g_rosette_bound_texture_2d, 1);
      if (state == NULL) return 0;
      palette = &state->palette;
    } else {
      return 0;
    }
    switch (pname) {
      case 0x80D9u: *value = palette->width; break; // GL_COLOR_TABLE_WIDTH
      case 0x80D8u: *value = (GLint)palette->format; break; // GL_COLOR_TABLE_FORMAT
      case 0x80DAu: *value = 8; break; // RED_SIZE
      case 0x80DBu: *value = 8; break; // GREEN_SIZE
      case 0x80DCu: *value = 8; break; // BLUE_SIZE
      case 0x80DDu: *value = 8; break; // ALPHA_SIZE
      default: *value = 0; break;
    }
  } else return 0;
  return 1;
}
