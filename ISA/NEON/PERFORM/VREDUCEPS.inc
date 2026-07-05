// PERFORM/VREDUCEPS.inc
// ARM64/NEON mirror generated from ISA/x86/PERFORM/VREDUCEPS.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERFORM/VREDUCEPS.inc"
x86_handler = "x86_vreduceps"
neon_lowering = "arm64_vreduceps"
lowering_kind = "arm64_documented_contract"

name = "VREDUCEPS"
aliases = []
category = "simd_arithmetic"
feature = "AVX512F"
element_type = "float"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 56 /r ib", form = "VREDUCEPS xmm1{k1}{z}, xmm2/m128/m32bcst, imm8", op_en = "A", vector_length = 128, feature = "AVX512F", masking = "merge+zero", broadcast = "supported" },
  { opcode = "EVEX.256.66.0F3A.W0 56 /r ib", form = "VREDUCEPS ymm1{k1}{z}, ymm2/m256/m32bcst, imm8", op_en = "A", vector_length = 256, feature = "AVX512F", masking = "merge+zero", broadcast = "supported" },
  { opcode = "EVEX.512.66.0F3A.W0 56 /r ib", form = "VREDUCEPS zmm1{k1}{z}, zmm2/m512/m32bcst, imm8", op_en = "A", vector_length = 512, feature = "AVX512F", masking = "merge+zero", broadcast = "supported" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)", "imm8"]
}

flags_written = []
simd_fp_exceptions = ["invalid", "denormal"]

semantic_general = """
Reduce the packed single-precision floating-point values in the source operand by the reduction operation specified in imm8. The result is stored in the destination operand. If the rounded result overflows or underflows the destination precision, the result is the exact value as computed with the source precision.
"""

handler = "x86_vreduceps"
jit_lowering = "arm64_vreduceps"
fallback = "zig_vreduceps"

neon_register_model = "x86 ZMM/YMM/XMM registers map to ARM64 Q/D register pairs. EVEX masking and broadcast semantics are emulated via ARM64 NEON/SSE fallback with explicit mask logic."
neon_flag_model = "No x86 flag state is modified by VREDUCEPS."
neon_assembly = """
// ARM64 NEON reduction via scalar FRSQRTE/FRECPE sequences per lane.
// Masked lanes handled via BSL (bitwise select) with writeback gating.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "VREDUCEPS performs 2^n-based rounding reduction per IEEE 754-2008; ARM64 NEON has no direct FREDUCE, so emulation via integer rounding mode manipulation is required.",
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
