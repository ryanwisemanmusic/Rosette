// PERFORM/VREDUCEPH.inc
// ARM64/NEON mirror generated from ISA/x86/PERFORM/VREDUCEPH.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERFORM/VREDUCEPH.inc"
x86_handler = "x86_vreduceph"
neon_lowering = "arm64_vreduceph"
lowering_kind = "arm64_documented_contract"

name = "VREDUCEPH"
aliases = []
category = "simd_arithmetic"
feature = "AVX512-FP16"
element_type = "float"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 56 /r ib", form = "VREDUCEPH xmm1{k1}{z}, xmm2/m128/m16bcst, imm8", op_en = "A", vector_length = 128, feature = "AVX512-FP16", masking = "merge+zero", broadcast = "supported" },
  { opcode = "EVEX.256.66.0F3A.W0 56 /r ib", form = "VREDUCEPH ymm1{k1}{z}, ymm2/m256/m16bcst, imm8", op_en = "A", vector_length = 256, feature = "AVX512-FP16", masking = "merge+zero", broadcast = "supported" },
  { opcode = "EVEX.512.66.0F3A.W0 56 /r ib", form = "VREDUCEPH zmm1{k1}{z}, zmm2/m512/m16bcst, imm8", op_en = "A", vector_length = 512, feature = "AVX512-FP16", masking = "merge+zero", broadcast = "supported" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)", "imm8"]
}

flags_written = []
simd_fp_exceptions = ["invalid", "denormal"]

semantic_general = """
Reduce the packed half-precision floating-point values in the source operand by the reduction operation specified in imm8. The result is stored in the destination operand. If the rounded result overflows or underflows the destination precision, the result is the exact value as computed with the source precision.
"""

handler = "x86_vreduceph"
jit_lowering = "arm64_vreduceph"
fallback = "zig_vreduceph"

neon_register_model = "x86 ZMM/YMM/XMM registers map to ARM64 Q/D register pairs. EVEX masking and broadcast semantics are emulated via ARM64 NEON fallback with explicit mask logic."
neon_flag_model = "No x86 flag state is modified by VREDUCEPH."
neon_assembly = """
// ARM64 FP16 reduction via scalar FRECPE/FRSQRTE sequences per half-precision lane.
// Masked lanes handled via BSL with writeback gating; FP16 conversion via FCVT.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "VREDUCEPH operates on FP16 elements; ARM64 NEON lacks native FP16 reduction, requiring FCVT to FP32 and back.",
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
