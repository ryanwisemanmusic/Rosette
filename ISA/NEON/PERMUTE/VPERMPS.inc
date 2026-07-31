// PERMUTE/VPERMPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/PERMUTE/VPERMPS.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPERMPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_permute_single_lane.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERMUTE/VPERMPS.inc"
x86_handler = "x86_vpermps"
neon_lowering = "arm64_neon_tbl"
lowering_kind = "neon_vector"


name = "VPERMPS"
category = "simd_float_permute_single_lane"
feature = "AVX2"
element_type = "f32"
legacy_width = 256
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16
mxcsr_used = true

encodings = [
  { opcode = "VEX.256.66.0F38.W0 16 /r", form = "VPERMPS ymm1, ymm2, ymm3/m256", op_en = "A", feature = "AVX2", mode = "V/V", handler = "x86_vpermps_ymm_ymm_ymmm256" },
  { opcode = "EVEX.256.66.0F38.W0 16 /r", form = "VPERMPS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermps_evex256" },
  { opcode = "EVEX.512.66.0F38.W0 16 /r", form = "VPERMPS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst{er}", op_en = "B", feature = "AVX512F", mode = "V/V", tuple = "Full", handler = "x86_vpermps_evex512" },
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.f32[0] = SRC2.f32[0] < 8 ? SRC1.f32[SRC2.f32[0]] : 0;
DEST.f32[1] = SRC2.f32[1] < 8 ? SRC1.f32[SRC2.f32[1]] : 0;
DEST.f32[2] = SRC2.f32[2] < 8 ? SRC1.f32[SRC2.f32[2]] : 0;
DEST.f32[3] = SRC2.f32[3] < 8 ? SRC1.f32[SRC2.f32[3]] : 0;
DEST.f32[4] = SRC2.f32[4] < 8 ? SRC1.f32[SRC2.f32[4]] : 0;
DEST.f32[5] = SRC2.f32[5] < 8 ? SRC1.f32[SRC2.f32[5]] : 0;
DEST.f32[6] = SRC2.f32[6] < 8 ? SRC1.f32[SRC2.f32[6]] : 0;
DEST.f32[7] = SRC2.f32[7] < 8 ? SRC1.f32[SRC2.f32[7]] : 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_vex_256 = """
DEST.f32[0] = SRC2.f32[0] < 8 ? SRC1.f32[SRC2.f32[0]] : 0;
DEST.f32[1] = SRC2.f32[1] < 8 ? SRC1.f32[SRC2.f32[1]] : 0;
DEST.f32[2] = SRC2.f32[2] < 8 ? SRC1.f32[SRC2.f32[2]] : 0;
DEST.f32[3] = SRC2.f32[3] < 8 ? SRC1.f32[SRC2.f32[3]] : 0;
DEST.f32[4] = SRC2.f32[4] < 8 ? SRC1.f32[SRC2.f32[4]] : 0;
DEST.f32[5] = SRC2.f32[5] < 8 ? SRC1.f32[SRC2.f32[5]] : 0;
DEST.f32[6] = SRC2.f32[6] < 8 ? SRC1.f32[SRC2.f32[6]] : 0;
DEST.f32[7] = SRC2.f32[7] < 8 ? SRC1.f32[SRC2.f32[7]] : 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f32 lane selected by k1 or no writemask:
    idx := SRC2.f32[i];
    DEST.f32[i] := (idx < VL/32) ? SRC1.f32[idx] : 0;
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["invalid", "denormal"]
other_exceptions = ["VEX Type 2 class exceptions", "EVEX Type E2 class exceptions"]

handler = "x86_vpermps"
jit_lowering = "arm64_neon_tbl1"


neon_register_model = """
x86 ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
tbl vD.16b, {vN.16b}, vM.16b
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "NEON TBL provides a per-byte lookup table that approximates cross-lane single-precision permute for 256-bit operations."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
