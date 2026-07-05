// PERFORM/VREDUCESH.inc
// ARM64/NEON mirror generated from ISA/x86/PERFORM/VREDUCESH.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERFORM/VREDUCESH.inc"
x86_handler = "x86_vreducesh"
neon_lowering = "arm64_vreducesh"
lowering_kind = "arm64_documented_contract"

name = "VREDUCESH"
aliases = []
category = "simd_arithmetic"
feature = "AVX512-FP16"
element_type = "float"
element_size = 16

encodings = [
  { opcode = "EVEX.66.0F3A.W0 57 /r ib", form = "VREDUCESH xmm1{k1}{z}, xmm2, xmm3/m16{m16bcst}, imm8", op_en = "A", vector_length = 128, feature = "AVX512-FP16", masking = "merge+zero", broadcast = "supported" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)", "imm8"]
}

flags_written = []
simd_fp_exceptions = ["invalid", "denormal"]

semantic_general = """
Reduce the scalar half-precision floating-point value in the source operand by the reduction operation specified in imm8. The result is stored in the destination operand. The upper bits of the destination beyond the least-significant element are preserved from the first source operand.
"""

handler = "x86_vreducesh"
jit_lowering = "arm64_vreducesh"
fallback = "zig_vreducesh"

neon_register_model = "x86 XMM register lower 16 bits mapped to ARM64 H register. Upper bits preserved via merging."
neon_flag_model = "No x86 flag state is modified by VREDUCESH."
neon_assembly = """
// ARM64: FREDUCE Hd, Hn  (scalar half precision, with imm8 rounding mode).
// Upper 112 bits of Vd preserved via BFI merge with Vm.
// Requires ARMv8.2-FP16 feature.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "VREDUCESH is the scalar FP16 variant; bits 127:16 are passed through from xmm2 (first source).",
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
