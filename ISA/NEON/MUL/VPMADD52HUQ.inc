// MUL/VPMADD52HUQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/VPMADD52HUQ.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPMADD52HUQ: preserve the operation and form-specific semantic blocks.
Category: simd_int_mul_add_52.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/VPMADD52HUQ.inc"
x86_handler = "x86_vpmadd52huq"
neon_lowering = "arm64_neon_ifma_high"
lowering_kind = "neon_vector"

name = "VPMADD52HUQ"
category = "simd_int_mul_add_52"
feature = "AVX512IFMA"
element_type = "u64"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 B5 /r", form = "VPMADD52HUQ xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512IFMA AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W1 B5 /r", form = "VPMADD52HUQ ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512IFMA AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W1 B5 /r", form = "VPMADD52HUQ zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512IFMA" },
]

element_size = 64
lane_type = "qword"

lanes = {
  xmm = 2,
  ymm = 4,
  zmm = 8
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
// No legacy SSE variant; AVX512IFMA only.
"""

semantic_vex_128 = """
// No VEX variant; AVX512IFMA only.
"""

semantic_vex_256 = """
// No VEX variant; AVX512IFMA only.
"""

semantic_evex = """
for lane in VL:
    if writemask_enabled:
        DEST.u64[lane] = DEST.u64[lane] + (SRC1.u64[lane] * SRC2.u64[lane])[103:52];
    else if zero_masking:
        DEST.u64[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpmadd52huq"
jit_lowering = "arm64_neon_ifma_high"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags are written by VPMADD52HUQ.
"""

neon_assembly = """
// ARM64 NEON: 52-bit multiply high via umulh
umulh vTMP.2d, vN.2d, vM.2d
add vD.2d, vD.2d, vTMP.2d
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
