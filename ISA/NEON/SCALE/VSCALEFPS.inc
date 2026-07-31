// SCALE/VSCALEFPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFPS.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VSCALEFPS: preserve the operation and form-specific semantic blocks.
Category: simd_float_scale.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFPS.inc"
x86_handler = "x86_vscalefps"
neon_lowering = "arm64_vscalefps"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFPS"
aliases = []
category = "simd_float_scale"
feature = "AVX512F"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 2C /r", form = "VSCALEFPS xmm1{k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 2C /r", form = "VSCALEFPS ymm1{k1}{z}, ymm2, xmm3/m256/m32bcst", op_en = "C", feature = "AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 2C /r", form = "VSCALEFPS zmm1{k1}{z}, zmm2, xmm3/m512/m32bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lane_type = "single_precision_float"
lanes = { xmm = 4, ymm = 8, zmm = 16 }
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

handler = "x86_vscalefps"
jit_lowering = "arm64_documented_contract_vscalefps"
fallback = "zig_lane_scale_f32"

neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON has no direct fused-scale equivalent for VSCALEFPS.
// The lowering computes each lane as: dst = src1 * 2^floor(src2)
// using ARM64 scalar floating-point arithmetic:
//     // For each lane:
//     //     int n = (int)floor(src2.lane);
//     //     dst.lane = src1.lane * pow(2.0f, (float)n);
// ARM64 FMUL with a power-of-two exponent from FREXPE-style extraction
// is the closest analogue but does not capture the floor(src2) semantic.
//     bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, or implicit-operand behavior.",
  "VSCALEFPS is a documented-contract lowering; no single ARM64 NEON instruction provides the 2^floor(operand) scale factor.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
