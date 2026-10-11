#ifndef ROSETTE_METAL_SUPPORT_H
#define ROSETTE_METAL_SUPPORT_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Native host API for bounded standalone checks and future backend consumers.
// Counts are validated before encoding; status 0 means completion observed.
// A failed command buffer makes this context terminal. No failed-work retries.
typedef void* RosetteMetalContext;
RosetteMetalContext rosette_metal_open(const char* metallib_path, char* error, size_t capacity);
void rosette_metal_close(RosetteMetalContext context);
const char* rosette_metal_device_name(RosetteMetalContext context);
const char* rosette_metal_error(RosetteMetalContext context);
int rosette_metal_color7e3(RosetteMetalContext context, uint32_t count, uint32_t* output_words);
int rosette_metal_uniform4(RosetteMetalContext context, const float* values, uint32_t rows,
                          const int32_t* indices, uint32_t requests, float* output);
int rosette_metal_ctx1(RosetteMetalContext context, const uint32_t* blocks, uint32_t block_count,
                      uint32_t width, uint32_t height, uint32_t block_pitch, uint32_t endian,
                      uint8_t* output_rg);
// format: 1=DXT1, 3=DXT3, 5=DXT5; word_count counts actual 32-bit source words.
int rosette_metal_dxt(RosetteMetalContext context, const uint32_t* words, uint32_t word_count,
                     uint32_t width, uint32_t height, uint32_t block_pitch, uint32_t endian,
                     uint32_t format, uint8_t* output_rgba);
// format: 1=DXT5A -> R8Unorm, 2=DXN -> RG8Unorm (first block half = R, second = G),
// 3=DXT3A -> R8Unorm; word_count counts actual 32-bit source words (2 per
// DXT5A/DXT3A block, 4 per DXN block). Output bytes: width*height or width*height*2.
int rosette_metal_bc45(RosetteMetalContext context, const uint32_t* words, uint32_t word_count,
                      uint32_t width, uint32_t height, uint32_t block_pitch, uint32_t endian,
                      uint32_t format, uint8_t* output);
int rosette_metal_order_probe(RosetteMetalContext context, uint32_t samples, uint32_t draws, uint32_t* output_words);
#ifdef __cplusplus
}
#endif
#endif
