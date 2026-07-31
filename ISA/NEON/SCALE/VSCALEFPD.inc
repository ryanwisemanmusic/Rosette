// SCALE/VSCALEFPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFPD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VSCALEFPD: preserve the operation and form-specific semantic blocks.
Category: simd_float_scale.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFPD.inc"
x86_handler = "x86_vscalefpd"
neon_lowering = "arm64_vscalefpd"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFPD"
aliases = ["VSCALEFPD"]
category = "simd_float_scale"
feature = "AVX512F"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 2C /r", form = "VSCALEFPD xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 2C /r", form = "VSCALEFPD ymm1{k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 2C /r", form = "VSCALEFPD zmm1{k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lane_type = "double_precision_float"
lanes = { xmm = 2, ymm = 4, zmm = 8 }
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

handler = "x86_vscalefpd"
jit_lowering = "arm64_documented_contract_vscalefpd"
fallback = "zig_lane_scale_f64"

neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON has no direct fused-scale equivalent for VSCALEFPD.
// The lowering computes each lane as: dst = src1 * 2^floor(src2)
// using ARM64 scalar floating-point arithmetic:
//     // For each lane:
//     //     int n = (int)floor(src2.lane);
//     //     dst.lane = src1.lane * pow(2.0, n);
//     bl rosette_apply_mxcsr_float_exceptions
// ARM64 FMUL with a power-of-two is the closest analogue but does not
// capture the explicit floor(src2) semantic in a single instruction.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, or implicit-operand behavior.",
  "VSCALEFPD is a documented-contract lowering; no single ARM64 NEON instruction provides the 2^floor(operand) scale factor.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
