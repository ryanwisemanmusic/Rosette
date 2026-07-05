// SCALE/VSCALEFSS.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFSS.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VSCALEFSS: preserve the operation and form-specific semantic blocks.
Category: simd_scalar_float_scale.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFSS.inc"
x86_handler = "x86_vscalefss"
neon_lowering = "arm64_documented_contract_vscalefss"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFSS"
aliases = []
category = "simd_scalar_float_scale"
feature = "AVX512F"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.LLIG.66.0F38.W0 2D /r", form = "VSCALEFSS xmm1{k1}{z}, xmm2, xmm3/m32{sae}", op_en = "C", feature = "AVX512F", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

active_lane = 0
lane_type = "scalar_single_precision"
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
if k1[0] == 1 or no_writemask:
    DEST.f32[0] = SRC1.f32[0] * 2^floor(SRC2.f32[0]);
else if zeroing_masking:
    DEST.f32[0] = 0;

DEST[127:32] = SRC1[127:32];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_vscalefss"
jit_lowering = "arm64_documented_contract_vscalefss"
fallback = "zig_scalar_scale_f32"

neon_register_model = """
x86 xmm lanes are mapped onto ARM64 v registers; only the low f32 lane is scaled; upper lanes are preserved or zeroed per encoding.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON has no direct scalar single-precision scale instruction.
// The lowering computes: dst.f32[0] = src1.f32[0] * 2^floor(src2.f32[0])
// using ARM64 scalar single-precision arithmetic:
//     // int n = (int)floorf(src2);
//     // dst = src1 * powf(2.0f, (float)n);
// ARM64 FSCALE does not exist as a single instruction; this is a
// documented-contract lowering composed from FRINTM + FMUL.
//     bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, or implicit-operand behavior.",
  "VSCALEFSS is a scalar documented-contract lowering; no single ARM64 NEON instruction provides the 2^floor(operand) scale factor for f32.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
