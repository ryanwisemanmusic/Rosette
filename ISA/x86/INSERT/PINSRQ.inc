// INSERT/PINSRQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/PINSRQ.inc.
// Source contract: PINSRQ/VPINSRQ — Insert Qword.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
PINSRQ: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/PINSRQ.inc"
x86_handler = "x86_pinsrq"
neon_lowering = "arm64_insert_u64_element"
lowering_kind = "arm64_documented_contract"

name = "PINSRQ"
aliases = ["VPINSRQ"]
category = "simd_insert"
feature = "SSE4_1_AVX_AVX512DQ"
element_type = "s64_insert"
element_size = 64

encodings = [
  { opcode = "66 REX.W 0F 3A 22 /r ib", form = "PINSRQ xmm1, r64/m64, imm8", op_en = "RMI", feature = "SSE4_1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.W1 22 /r ib", form = "VPINSRQ xmm1, xmm2, r64/m64, imm8", op_en = "RVMI", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.128.66.0F3A.W1 22 /r ib", form = "VPINSRQ xmm1 {k1}{z}, xmm2, r64/m64, imm8", op_en = "C", feature = "AVX512DQ", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  RMI = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8"],
  RVMI = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 2 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_128 = """
DEST[imm8 * 64 + 63 : imm8 * 64] := SRC[63:0];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST[imm8 * 64 + 63 : imm8 * 64] := SRC2[63:0];
DEST[127:0] := SRC1[127:0];
DEST[MAXVL-1:128] := 0;
"""

semantic_evex = """
if k1[imm8] == 1 or no_writemask:
    DEST[imm8 * 64 + 63 : imm8 * 64] := SRC2[63:0];
    if zeroing_masking:
        for j in 0..1:
            if j != imm8:
                DEST[j*64 + 63 : j*64] := 0;
    else:
        DEST[127:0] := SRC1[127:0];
else if zeroing_masking:
    DEST[127:0] := 0;
else:
    DEST[127:0] := SRC1[127:0];
DEST[MAXVL-1:128] := 0;
"""

handler = "x86_pinsrq"
jit_lowering = "arm64_insert_element"
fallback = "zig_insert_lane"

neon_register_model = """
x86 xmm qword lanes are mapped into ARM64 vector temporaries. PINSRQ inserts a 64-bit value from GPR or memory into the XMM register at a position selected by imm8 modulo 2.
"""

neon_flag_model = """
No x86 flags are modified by PINSRQ/VPINSRQ.
"""

neon_assembly = """
mov vD.d[idx], xN
// imm8 selects destination qword lane idx
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "PINSRQ requires REX.W prefix (64-bit mode only) in legacy SSE4.1 form; VEX.W=1 for AVX; EVEX.W=1 for AVX512DQ."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
