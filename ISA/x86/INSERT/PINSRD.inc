// INSERT/PINSRD.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/PINSRD.inc.
// Source contract: PINSRD/VPINSRD — Insert Dword.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
PINSRD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/PINSRD.inc"
x86_handler = "x86_pinsrd"
neon_lowering = "arm64_insert_u32_element"
lowering_kind = "arm64_documented_contract"

name = "PINSRD"
aliases = ["VPINSRD"]
category = "simd_insert"
feature = "SSE4_1_AVX_AVX512DQ"
element_type = "s32_insert"
element_size = 32

encodings = [
  { opcode = "66 0F 3A 22 /r ib", form = "PINSRD xmm1, r32/m32, imm8", op_en = "RMI", feature = "SSE4_1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.W0 22 /r ib", form = "VPINSRD xmm1, xmm2, r32/m32, imm8", op_en = "RVMI", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.128.66.0F3A.W0 22 /r ib", form = "VPINSRD xmm1 {k1}{z}, xmm2, r32/m32, imm8", op_en = "C", feature = "AVX512DQ", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  RMI = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8"],
  RVMI = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 4 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_128 = """
DEST[imm8 * 32 + 31 : imm8 * 32] := SRC[31:0];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST[imm8 * 32 + 31 : imm8 * 32] := SRC2[31:0];
DEST[127:0] := SRC1[127:0];
DEST[MAXVL-1:128] := 0;
"""

semantic_evex = """
if k1[imm8] == 1 or no_writemask:
    DEST[imm8 * 32 + 31 : imm8 * 32] := SRC2[31:0];
    if zeroing_masking:
        for j in 0..3:
            if j != imm8:
                DEST[j*32 + 31 : j*32] := 0;
    else:
        DEST[127:0] := SRC1[127:0];
else if zeroing_masking:
    DEST[127:0] := 0;
else:
    DEST[127:0] := SRC1[127:0];
DEST[MAXVL-1:128] := 0;
"""

handler = "x86_pinsrd"
jit_lowering = "arm64_insert_element"
fallback = "zig_insert_lane"

neon_register_model = """
x86 xmm dword lanes are mapped into ARM64 vector temporaries. PINSRD inserts a 32-bit value from GPR or memory into the XMM register at a position selected by imm8 modulo 4.
"""

neon_flag_model = """
No x86 flags are modified by PINSRD/VPINSRD.
"""

neon_assembly = """
mov vD.s[idx], wN
// imm8 selects destination dword lane idx
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
