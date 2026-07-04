// INSERT/PINSRB.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/PINSRB.inc.
// Source contract: PINSRB/VPINSRB — Insert Byte.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
PINSRB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/PINSRB.inc"
x86_handler = "x86_pinsrb"
neon_lowering = "arm64_insert_u8_element"
lowering_kind = "arm64_documented_contract"

name = "PINSRB"
aliases = ["VPINSRB"]
category = "simd_insert"
feature = "SSE4_1_AVX_AVX512BW"
element_type = "s8_insert"
element_size = 8

encodings = [
  { opcode = "66 0F 3A 20 /r ib", form = "PINSRB xmm1, r32/m8, imm8", op_en = "RMI", feature = "SSE4_1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.W0 20 /r ib", form = "VPINSRB xmm1, xmm2, r32/m8, imm8", op_en = "RVMI", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.128.66.0F3A.WIG 20 /r ib", form = "VPINSRB xmm1 {k1}{z}, xmm2, r32/m8, imm8", op_en = "C", feature = "AVX512BW", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  RMI = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8"],
  RVMI = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_128 = """
DEST[imm8 * 8 + 7 : imm8 * 8] := SRC[7:0];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST[imm8 * 8 + 7 : imm8 * 8] := SRC2[7:0];
DEST[127:0] := SRC1[127:0];
DEST[MAXVL-1:128] := 0;
"""

semantic_evex = """
if k1[imm8] == 1 or no_writemask:
    DEST[imm8 * 8 + 7 : imm8 * 8] := SRC2[7:0];
    if zeroing_masking:
        for j in 0..15:
            if j != imm8:
                DEST[j*8 + 7 : j*8] := 0;
    else:
        DEST[127:0] := SRC1[127:0];
else if zeroing_masking:
    DEST[127:0] := 0;
else:
    DEST[127:0] := SRC1[127:0];
DEST[MAXVL-1:128] := 0;
"""

handler = "x86_pinsrb"
jit_lowering = "arm64_insert_element"
fallback = "zig_insert_lane"

neon_register_model = """
x86 xmm byte lanes are mapped into ARM64 vector temporaries. PINSRB inserts a byte from a GPR or memory into the XMM register at a position selected by imm8 modulo 16.
"""

neon_flag_model = """
No x86 flags are modified by PINSRB/VPINSRB.
"""

neon_assembly = """
mov vD.b[idx], wN
// imm8 selects destination byte lane idx
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
