// UNPACK/UNPCKLPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/UNPACK/UNPCKLPS.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
UNPCKLPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_unpack_low.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNPACK/UNPCKLPS.inc"
x86_handler = "x86_unpcklps"
neon_lowering = "arm64_neon_zip_low_s"
lowering_kind = "neon_vector"


name = "UNPCKLPS"
category = "simd_float_unpack_low"
feature = "SSE"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16
mxcsr_used = true

encodings = [
  { opcode = "NP 0F 14 /r", form = "UNPCKLPS xmm1, xmm2/m128", op_en = "A", feature = "SSE", mode = "V/V", handler = "x86_unpcklps_xmm_xmmm128" },
  { opcode = "VEX.128.0F.WIG 14 /r", form = "VUNPCKLPS xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vunpcklps_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.0F.WIG 14 /r", form = "VUNPCKLPS ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vunpcklps_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.0F.W0 14 /r", form = "VUNPCKLPS xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", tuple = "Full", handler = "x86_vunpcklps_evex128" },
  { opcode = "EVEX.256.0F.W0 14 /r", form = "VUNPCKLPS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", tuple = "Full", handler = "x86_vunpcklps_evex256" },
  { opcode = "EVEX.512.0F.W0 14 /r", form = "VUNPCKLPS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst{er}", op_en = "C", feature = "AVX512F", tuple = "Full", handler = "x86_vunpcklps_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.f32[0] = DEST.f32[0];
DEST.f32[1] = DEST.f32[1];
DEST.f32[2] = SRC.f32[0];
DEST.f32[3] = SRC.f32[1];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.f32[0] = SRC1.f32[0];
DEST.f32[1] = SRC1.f32[1];
DEST.f32[2] = SRC2.f32[0];
DEST.f32[3] = SRC2.f32[1];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.f32[0] = SRC1.f32[0];
DEST.f32[1] = SRC1.f32[1];
DEST.f32[2] = SRC2.f32[0];
DEST.f32[3] = SRC2.f32[1];
DEST.f32[4] = SRC1.f32[4];
DEST.f32[5] = SRC1.f32[5];
DEST.f32[6] = SRC2.f32[4];
DEST.f32[7] = SRC2.f32[5];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f32 lane group selected by k1 or no writemask:
    DEST[i * 4 + 0] = SRC1[VL/4 + i * 4 + 0];
    DEST[i * 4 + 1] = SRC1[VL/4 + i * 4 + 1];
    DEST[i * 4 + 2] = SRC2[VL/4 + i * 4 + 0_or_broadcast];
    DEST[i * 4 + 3] = SRC2[VL/4 + i * 4 + 1_or_broadcast];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = ["VEX Type 2 class exceptions", "EVEX Type E2 class exceptions"]

handler = "x86_unpcklps"
jit_lowering = "arm64_neon_zip_low_s"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
zip1 vD.4s, vN.4s, vM.4s
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
