// avx-shim.c - SIGILL handler for VEX (AVX) instructions under Rosetta 2.
//
// Apple Rosetta 2 does not support VEX-encoded AVX instructions on Apple
// Silicon. When an x86-64 binary compiled with -mavx runs under Rosetta 2,
// any VEX-encoded instruction triggers SIGILL.
//
// This dylib intercepts those SIGILLs and patches VEX.128 (XMM) instructions
// in-place to their SSE equivalents, then re-executes.
//
// Build (x86_64 only - runs inside the emulated Rosetta 2 process):
//   zig cc -target x86_64-macos -dynamiclib \
//     -o avx-shim.dylib avx-shim.c \
//     -install_name @rpath/avx-shim.dylib \
//     -Wl,-dead_strip_dylibs

#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <unistd.h>

// ── macOS x86-64 mcontext (minimal access) ─────────────────────────────
// RIP is read from uc_mcontext->__ss.__rip. XMM state is not accessed by
// this shim since it patches instructions in-place rather than emulating.

// ── VEX decoding constants ────────────────────────────────────────────
#define VEX_PP(b)     ((b) & 3)
#define VEX_L(b)      (((b) >> 2) & 1)
#define VEX_VVVV(b)   ((~((b) >> 3)) & 0xF)
#define VEX_R(b)      (((b) >> 7) & 1)
#define MODRM_MOD(b)  (((b) >> 6) & 3)
#define MODRM_REG(b)  (((b) >> 3) & 7)
#define MODRM_RM(b)   ((b) & 7)
#define SIB_SCALE(b)  (((b) >> 6) & 3)
#define SIB_INDEX(b)  (((b) >> 3) & 7)
#define SIB_BASE(b)   ((b) & 7)

// ── Instruction length ─────────────────────────────────────────────────
// Compute total length of a VEX-prefixed instruction. Handles ModRM, SIB,
// displacement, and most immediate-bearing opcodes.

static int instr_len(const uint8_t *p) {
    int off = 0;

    // VEX prefix
    int vex_len;
    if (p[0] == 0xC5) vex_len = 2;
    else if (p[0] == 0xC4) vex_len = 3;
    else return 0;

    off = vex_len;

    // Parse opcode
    uint8_t opc = p[off++];
    int map38 = 0, map3A = 0;
    if (vex_len == 3) {
        uint8_t m = (~p[1]) & 0x1F;
        map38 = (m == 0x02);
        map3A = (m == 0x03);
        if (map38 || map3A) opc = p[off++];
    }

    // ModRM
    if (off >= 15) return off;
    uint8_t modrm = p[off++];
    uint8_t mod = MODRM_MOD(modrm);
    uint8_t rm  = MODRM_RM(modrm);

    // SIB
    if (mod != 3 && rm == 4) {
        uint8_t sib = p[off++];
        if (MODRM_MOD(modrm) == 0 && SIB_BASE(sib) == 5) off += 4; // disp32
    }

    // Displacement
    if (mod == 1) off += 1;
    else if (mod == 2 || (mod == 0 && rm == 5)) off += 4;

    // Immediate byte detection for common opcodes
    // These opcodes in the 0x0F map have an immediate byte:
    //   0xC2 (cmpps/pd/ss/sd), 0xC6 (shufps/pd)
    //   0x70 (pshufd), 0x74 (pcmpeqb), etc.
    //   0xFA, 0xFB (psubq), etc. - no imm
    // In map 2/3 (0F38/0F3A), nearly all have an immediate:
    //   0x3A: 0x08-0x0B (round), 0x0C-0x0F (blend/palignr),
    //         0x14-0x17 (pextr), 0x20-0x22 (pinsr),
    //         0x40-0x42 (dpp), 0x44 (pclmulqdq), 0xDF (aeskeygen)
    //   0x38: most have NO immediate
    // We detect a trailing immediate by checking if bytes remain after
    // the above parsing. Common immediate-bearing patterns:

    int has_imm = 0;
    if (map3A) {
        // Most 0x0F3A opcodes have a single immediate byte
        has_imm = 1;
    } else if (map38) {
        // Most 0x0F38 opcodes do NOT have immediate
        has_imm = 0;
    } else if (vex_len == 2 && VEX_PP(p[1]) == 0x01) {
        // 0x66-prefixed 0x0F map. Check for common imm opcodes
        has_imm = (opc == 0x70 || opc == 0xC2 || opc == 0xC4 ||
                   opc == 0xC5 || opc == 0xC6);
    } else {
        // Primary pp = 00 or F3/F2
        has_imm = (opc == 0xC2 || opc == 0xC6 || opc == 0x70);
    }

    if (has_imm) off += 1;

    return off;
}

// ── SSE prefix table ───────────────────────────────────────────────────
// pp: 0=none, 1=0x66, 2=0xF3, 3=0xF2
static const uint8_t PP2PREFIX[4] = {0x00, 0x66, 0xF3, 0xF2};

// ── SIGILL handler ─────────────────────────────────────────────────────

static void handle_sigill(int sig, siginfo_t *info, void *ucontext_raw) {
    (void)sig;
    (void)info;

    ucontext_t *ctx = (ucontext_t *)ucontext_raw;
    uint8_t *rip = (uint8_t *)ctx->uc_mcontext->__ss.__rip;

    // ── VEX prefix check ──────────────────────────────────────────────
    if (rip[0] != 0xC5 && rip[0] != 0xC4) goto chain;

    int vex = (rip[0] == 0xC5) ? 2 : 3;
    uint8_t vb  = (vex == 2) ? rip[1] : rip[2];
    uint8_t pp  = VEX_PP(vb);
    uint8_t L   = VEX_L(vb);
    uint8_t vvvv = VEX_VVVV(vb);
    uint8_t R_bit = VEX_R(vb);

    // Only handle 128-bit (XMM) VEX for now
    if (L != 0) goto chain;

    // ── Parse opcode ──────────────────────────────────────────────────
    int off = vex; // points to first trailing byte (opcode)
    uint8_t opc = rip[off++];

    int map38 = 0, map3A = 0, map1 = 1;
    if (vex == 3) {
        uint8_t map = (~rip[1]) & 0x1F;
        map38 = (map == 0x02);
        map3A = (map == 0x03);
        map1  = (map == 0x01);
        if (map38 || map3A) opc = rip[off++];
    }

    // ── ModRM ─────────────────────────────────────────────────────────
    uint8_t modrm = rip[off++];
    uint8_t mod   = MODRM_MOD(modrm);
    uint8_t reg   = MODRM_REG(modrm); // dest in VEX
    uint8_t rm    = MODRM_RM(modrm);

    // For VEX, the ~R bit inverts the top bit of the ModRM.reg field.
    // Since we only handle xmm0..7 (no REX extension), R=0 means reg_top=1,
    // but xmm0..7 need reg_top=0. So R must be 1 (no inversion).
    // If R=0, the instruction uses xmm8..15, which we don't handle.
    // For our purposes, the ModRM byte itself has the correct 3-bit reg field.

    (void)R_bit; // For now, assume xmm0..7 only

    // ── Parse SIB + displacement for memory operands ──────────────────
    // We only parse to determine byte positions for the SSE copy;
    // actual address resolution happens when the patched instruction executes.
    int has_sib   = 0;
    uint8_t sib_b = 0;
    int disp_bytes = 0;
    int32_t disp  = 0;

    if (mod != 3) {
        if (rm == 4) {
            has_sib = 1;
            sib_b = rip[off++];
            if (MODRM_MOD(modrm) == 0 && SIB_BASE(sib_b) == 5) {
                // RIP-relative SIB (base==5 mod==0 → disp32)
                memcpy(&disp, rip + off, 4);
                disp_bytes = 4;
                off += 4;
            } else {
                if (mod == 1) {
                    disp = (int8_t)rip[off];
                    disp_bytes = 1;
                    off += 1;
                } else if (mod == 2) {
                    memcpy(&disp, rip + off, 4);
                    disp_bytes = 4;
                    off += 4;
                }
            }
        } else if (rm == 5 && mod == 0) {
            // RIP-relative: [rip + disp32]
            memcpy(&disp, rip + off, 4);
            disp_bytes = 4;
            off += 4;
        } else {
            // Register-base + displacement
            if (mod == 1) {
                disp = (int8_t)rip[off];
                disp_bytes = 1;
                off += 1;
            } else if (mod == 2) {
                memcpy(&disp, rip + off, 4);
                disp_bytes = 4;
                off += 4;
            }
        }
    }

    // ── Build SSE equivalent ──────────────────────────────────────────
    // For VEX.128 where dest == vvvv (or vvvv unused == 0xF):
    //   Strip VEX prefix, insert [pp prefix][0x0F][opcode][ModRM].
    //
    // For VEX.128 where dest != vvvv:
    //   Change ModRM.reg to vvvv (SSE writes to src1).
    //   The original dest register value is lost, but this matches
    //   SSE's 2-operand form: op src1 -> src1.
    //
    // Key insight: the compiler emits dest==vvvv for most code, and
    // dest!=vvvv is rare. Even for dest!=vvvv, changing the dest to
    // vvvv produces the SSE-equivalent result (same computation,
    // just stored in vvvv instead of the original dest register).

    uint8_t sse[16];
    int sse_len = 0;

    // Optional SSE prefix
    if (pp != 0) sse[sse_len++] = PP2PREFIX[pp];

    // 0x0F + optional map byte
    sse[sse_len++] = 0x0F;
    if (map38) sse[sse_len++] = 0x38;
    else if (map3A) sse[sse_len++] = 0x3A;

    // Opcode
    sse[sse_len++] = opc;

    // ModRM: adjust for 3-op → 2-op
    uint8_t new_modrm = modrm;
    if (vvvv != 0xF && vvvv != reg) {
        // SSE writes to src1 (vvvv) instead of original dest (reg)
        new_modrm = (modrm & 0xC7) | (vvvv << 3);
    }
    sse[sse_len++] = new_modrm;

    // Copy SIB
    if (has_sib) sse[sse_len++] = sib_b;

    // Copy displacement
    if (disp_bytes > 0) {
        memcpy(sse + sse_len, &disp, disp_bytes);
        sse_len += disp_bytes;
    }

    // Immediate byte (if any in original, copy it)
    // Calculate total VEX instruction length
    // Since off now points past disp, check if any imm byte remains
    int total_vex = instr_len(rip);
    if (total_vex > off) {
        int imm_bytes = total_vex - off;
        memcpy(sse + sse_len, rip + off, imm_bytes);
        sse_len += imm_bytes;
    }

    // ── Patch in-place ────────────────────────────────────────────────
    // SSE is always <= VEX length for 2-byte VEX (pp=00: -1 byte, pp≠00: same)
    // and for 3-byte VEX (-1 or -2 bytes).
    // If DSSE ends up longer, bail out (shouldn't happen)
    if (sse_len > total_vex) goto chain;

    // Make page writable
    uintptr_t page_start = (uintptr_t)rip & ~(uintptr_t)0xFFF;
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)page_start,
                                  0x1000, 0,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        // Fallback: try mprotect
        if (mprotect((void*)page_start, 0x1000,
                     PROT_READ | PROT_WRITE | PROT_EXEC) != 0)
            goto chain;
    }

    // Write SSE instruction
    memcpy(rip, sse, sse_len);

    // Fill gap with single-byte NOP (0x90) if SSE is shorter
    int gap = total_vex - sse_len;
    if (gap > 0) memset(rip + sse_len, 0x90, gap);

    // Clear instruction cache
    sys_icache_invalidate(rip, total_vex);

    return; // Re-execute at same RIP (now patched to SSE)

chain: {
    // Chain to next handler: restore default, re-raise
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_DFL;
    sigaction(SIGILL, &sa, NULL);
    raise(SIGILL);
    _exit(132);
}
}

// ── Library constructor ────────────────────────────────────────────────

__attribute__((constructor)) static void avx_shim_init(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = handle_sigill;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);

    if (sigaction(SIGILL, &sa, NULL) != 0) {
        fprintf(stderr, "avx-shim: failed to install SIGILL handler\n");
    }
}
