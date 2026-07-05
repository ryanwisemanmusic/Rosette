// SCALE/VSCALEFSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFSH.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VSCALEFSH: preserve the operation and form-specific semantic blocks.
Category: simd_scalar_float_scale.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFSH.inc"
x86_handler = "x86_vscalefsh"
neon_lowering = "arm64_documented_contract_vscalefsh"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFSH"
aliases = []
category = "simd_scalar_float_scale"
feature = "AVX512_FP16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.LLIG.66.0F38.W0 2D /r", form = "VSCALEFSH xmm1{k1}{z}, xmm2, xmm3/m16{sae}", op_en = "C", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

active_lane = 0
lane_type = "scalar_half_precision"
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
if k1[0] == 1 or no_writemask:
    DEST.f16[0] = SRC1.f16[0] * 2^floor(SRC2.f16[0]);
else if zeroing_masking:
    DEST.f16[0] = 0;

DEST[127:16] = SRC1[127:16];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_vscalefsh"
jit_lowering = "arm64_documented_contract_vscalefsh"
fallback = "zig_scalar_scale_f16"

neon_register_model = """
x86 xmm lanes are mapped onto ARM64 v registers; only the low f16 lane is scaled; upper lanes are preserved or zeroed per encoding.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON has no direct half-precision scalar scale instruction.
// The lowering computes: dst.f16[0] = src1.f16[0] * 2^floor(src2.f16[0])
// using ARM64 half-precision arithmetic after FCVT conversion:
//     // float tmp = (float)src2.f16[0];
//     // int n = (int)floorf(tmp);
//     // dst.f16[0] = src1.f16[0] * (__fp16)powf(2.0f, (float)n);
// ARM64 provides no H-format SCALE instruction; this is a
// documented-contract lowering composed through FP32 conversion.
//     bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, or implicit-operand behavior.",
  "VSCALEFSH is an AVX512-FP16 scalar instruction with no ARM64 NEON analogue; documented-contract lowering.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
