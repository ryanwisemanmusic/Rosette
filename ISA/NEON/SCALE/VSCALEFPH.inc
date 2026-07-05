// SCALE/VSCALEFPH.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFPH.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VSCALEFPH: preserve the operation and form-specific semantic blocks.
Category: simd_float_scale.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFPH.inc"
x86_handler = "x86_vscalefph"
neon_lowering = "arm64_documented_contract_vscalefph"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFPH"
aliases = []
category = "simd_float_scale"
feature = "AVX512_FP16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 2C /r", form = "VSCALEFPH xmm1{k1}{z}, xmm2, xmm3/m128/m16bcst", op_en = "C", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 2C /r", form = "VSCALEFPH ymm1{k1}{z}, ymm2, ymm3/m256/m16bcst", op_en = "C", feature = "AVX512_FP16", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 2C /r", form = "VSCALEFPH zmm1{k1}{z}, zmm2, zmm3/m512/m16bcst", op_en = "C", feature = "AVX512_FP16", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lane_type = "half_precision_float"
lanes = { xmm = 8, ymm = 16, zmm = 32 }
mxcsr_used = true

simd_fp_exceptions = [
  "overflow",
  "underflow",
  "invalid",
  "precision",
  "denormal"
]

flags_written = []

semantic_evex = """
for lane in VL:
    if writemask_enabled:
        DEST[lane] = SRC1[lane] * 2^floor(SRC2[lane]);
    else if zero_masking:
        DEST[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vscalefph"
jit_lowering = "arm64_documented_contract_vscalefph"
fallback = "zig_lane_scale_f16"

neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON has no direct half-precision fused-scale instruction.
// The lowering processes FP16 lanes through ARM64 scalar arithmetic:
//     // For each lane:
//     //     int n = (int)floor((double)src2.lane);
//     //     dst.lane = src1.lane * (half)pld(2.0, n);
// ARM64 provides FCVT for half-precision conversion but no HALF-PRECISION
// SCALE instruction; the VSCALEFPH semantic requires software lowering.
//     bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, or implicit-operand behavior.",
  "VSCALEFPH is an AVX512-FP16 instruction with no ARM64 NEON analogue; lowering is through documented contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
