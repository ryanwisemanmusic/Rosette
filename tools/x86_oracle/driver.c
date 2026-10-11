#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "forms.h"

/* The input generator; process.zig's `sseOracleInput` is the same function. */
static uint64_t sm(uint64_t *s) {
    uint64_t z = (*s += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
}
static const uint32_t f32_special[16] = {0x00000000u, 0x80000000u, 0x7F800000u, 0xFF800000u, 0x7FC00000u, 0x7F800001u, 0xFFC00001u, 0x00000001u, 0x007FFFFFu, 0x80000001u, 0x7F7FFFFFu, 0x3F800000u, 0xBF800000u, 0x3F000000u, 0x4F000000u, 0xCF000000u};
static const uint64_t f64_special[16] = {0, 0x8000000000000000ull, 0x7FF0000000000000ull, 0xFFF0000000000000ull, 0x7FF8000000000000ull, 0x7FF0000000000001ull, 0xFFF8000000000001ull, 1, 0x000FFFFFFFFFFFFFull, 0x8000000000000001ull, 0x7FEFFFFFFFFFFFFFull, 0x3FF0000000000000ull, 0xBFF0000000000000ull, 0x3FE0000000000000ull, 0x41E0000000000000ull, 0xC1E0000000000000ull};
static const uint32_t int_special[16] = {0, 1, 0x7F, 0x80, 0xFF, 0x7FFF, 0x8000, 0xFFFF, 0x7FFFFFFFu, 0x80000000u, 0xFFFFFFFFu, 0x00FF00FFu, 0x80008000u, 0x7FFF8000u, 0x01010101u, 0xFFFF0000u};

static uint32_t lane32(uint64_t r) {
    uint64_t p = r >> 3;
    float f;
    uint32_t u;
    switch (r & 7) {
    case 3: f = (float)((int32_t)(p % 2001) - 1000); break;
    case 4: f = (float)((int32_t)(p % 2001) - 1000) + 0.5f; break;
    case 5: return f32_special[p % 16];
    case 6: f = (float)((int32_t)(p % 2000001) - 1000000) / 1000000.0f; break;
    case 7: return int_special[p % 16];
    default: return (uint32_t)p;
    }
    memcpy(&u, &f, 4);
    return u;
}
static uint64_t lane64(uint64_t r) {
    uint64_t p = r >> 3;
    double f;
    uint64_t u;
    switch (r & 7) {
    case 3: f = (double)((int64_t)(p % 2001) - 1000); break;
    case 4: f = (double)((int64_t)(p % 2001) - 1000) + 0.5; break;
    case 5: return f64_special[p % 16];
    case 6: f = (double)((int64_t)(p % 2000001) - 1000000) / 1000000.0; break;
    default: return r;
    }
    memcpy(&u, &f, 8);
    return u;
}
static void fill(int form, int k, int lane, uint8_t *in) {
    uint64_t s = 0x0A11CE0000000000ull + (uint64_t)form * 64 + (uint64_t)k;
    for (int r = 0; r < 16; r++) {
        if (lane == 1) {
            for (int l = 0; l < 2; l++) { uint64_t v = lane64(sm(&s)); memcpy(in + r * 16 + l * 8, &v, 8); }
        } else {
            for (int l = 0; l < 4; l++) { uint32_t v = lane32(sm(&s)); memcpy(in + r * 16 + l * 4, &v, 4); }
        }
    }
    for (int g = 0; g < 16; g++) {
        uint64_t r = sm(&s), p = r >> 3, v;
        switch (r & 7) {
        case 4: v = (uint64_t)((int64_t)(p % 2001) - 1000); break;
        case 5: v = (uint64_t)(int64_t)(int32_t)int_special[p % 16]; break;
        default: v = r; break;
        }
        memcpy(in + 256 + g * 8, &v, 8);
    }
}

int main(int argc, char **argv) {
    int inputs = 8;
    FILE *out = fopen(argv[1], "wb");
    for (int i = 0; i < FORM_COUNT; i++) {
        for (int k = 0; k < inputs; k++) {
            uint8_t in[392] __attribute__((aligned(16))), result[392] __attribute__((aligned(16)));
            memset(in, 0, sizeof in);
            memset(result, 0, sizeof result);
            fill(i, k, form_lane[i], in);
            forms[i](in, result);
            fwrite(result, 1, 392, out);
        }
    }
    fclose(out);
    printf("%d forms x %d inputs\n", FORM_COUNT, inputs);
    return 0;
}
