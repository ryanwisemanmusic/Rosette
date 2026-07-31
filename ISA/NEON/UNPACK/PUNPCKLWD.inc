// UNPACK/PUNPCKLWD.inc
// ARM64/NEON translation mirror generated from ISA/x86/UNPACK/PUNPCKLWD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PUNPCKLWD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_unpack_low.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNPACK/PUNPCKLWD.inc"
x86_handler = "x86_punpcklwd"
neon_lowering = "arm64_neon_zip_low_h"
lowering_kind = "neon_vector"


name = "PUNPCKLWD"
category = "simd_integer_unpack_low"
feature = "MMX"
element_type = "i16"
legacy_width = 64
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = false

encodings = [
  { opcode = "NP 0F 61 /r", form = "PUNPCKLWD mm1, mm2/m64", op_en = "A", feature = "MMX", mode = "V/V", handler = "x86_punpcklwd_mm_mmm64" },
  { opcode = "66 0F 61 /r", form = "PUNPCKLWD xmm1, xmm2/m128", op_en = "A", feature = "SSE2", mode = "V/V", handler = "x86_punpcklwd_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F.WIG 61 /r", form = "VPUNPCKLWD xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vpunpcklwd_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F.WIG 61 /r", form = "VPUNPCKLWD ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", mode = "V/V", handler = "x86_vpunpcklwd_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.66.0F.WIG 61 /r", form = "VPUNPCKLWD xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "x86_vpunpcklwd_evex128" },
  { opcode = "EVEX.256.66.0F.WIG 61 /r", form = "VPUNPCKLWD ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "x86_vpunpcklwd_evex256" },
  { opcode = "EVEX.512.66.0F.WIG 61 /r", form = "VPUNPCKLWD zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", tuple = "Full", handler = "x86_vpunpcklwd_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
for lane in 0..2:
    DEST.i16[lane * 2] = DEST.i16[lane];
    DEST.i16[lane * 2 + 1] = SRC.i16[lane];
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex_128 = """
for lane in 0..4:
    DEST.i16[lane * 2] = SRC1.i16[lane];
    DEST.i16[lane * 2 + 1] = SRC2.i16[lane];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..8:
    DEST.i16[lane * 2] = SRC1.i16[lane];
    DEST.i16[lane * 2 + 1] = SRC2.i16[lane];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active i16 lane group selected by k1 or no writemask:
    DEST[i * 2 + 0] = SRC1[i];
    DEST[i * 2 + 1] = SRC2[i];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["Non-EVEX: Type 4 class exceptions", "EVEX: Type E4 class exceptions"]

handler = "x86_punpcklwd"
jit_lowering = "arm64_neon_zip_low_h"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags affected.
"""

neon_assembly = """
zip1 vD.8h, vN.8h, vM.8h
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
