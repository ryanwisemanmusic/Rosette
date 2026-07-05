// SCALE/VSCALEFSD.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFSD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VSCALEFSD: preserve the operation and form-specific semantic blocks.
Category: simd_scalar_float_scale.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFSD.inc"
x86_handler = "x86_vscalefsd"
neon_lowering = "arm64_documented_contract_vscalefsd"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFSD"
aliases = []
category = "simd_scalar_float_scale"
feature = "AVX512F"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.LLIG.66.0F38.W1 2D /r", form = "VSCALEFSD xmm1{k1}{z}, xmm2, xmm3/m64{sae}", op_en = "C", feature = "AVX512F", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

active_lane = 0
lane_type = "scalar_double_precision"
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
if k1[0] == 1 or no_writemask:
    DEST.f64[0] = SRC1.f64[0] * 2^floor(SRC2.f64[0]);
else if zeroing_masking:
    DEST.f64[0] = 0;

DEST[127:64] = SRC1[127:64];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_vscalefsd"
jit_lowering = "arm64_documented_contract_vscalefsd"
fallback = "zig_scalar_scale_f64"

neon_register_model = """
x86 xmm lanes are mapped onto ARM64 v registers; only the low f64 lane is scaled; upper lanes are preserved or zeroed per encoding.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON has no direct scalar fused-scale equivalent for VSCALEFSD.
// The lowering computes: dst.f64[0] = src1.f64[0] * 2^floor(src2.f64[0])
// using ARM64 scalar double-precision arithmetic:
//     // int n = (int)floor(src2);
//     // dst = src1 * pow(2.0, (double)n);
// ARM64 FSCALE does not exist as a single instruction; this is a
// documented-contract lowering composed from floor + FMUL.
//     bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, or implicit-operand behavior.",
  "VSCALEFSD is a scalar documented-contract lowering; no single ARM64 NEON instruction provides the 2^floor(operand) scale factor for f64.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
