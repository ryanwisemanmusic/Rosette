// PERFORM/VREDUCESD.inc
// ARM64/NEON mirror generated from ISA/x86/PERFORM/VREDUCESD.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERFORM/VREDUCESD.inc"
x86_handler = "x86_vreducesd"
neon_lowering = "arm64_vreducesd"
lowering_kind = "arm64_documented_contract"

name = "VREDUCESD"
aliases = []
category = "simd_arithmetic"
feature = "AVX512F"
element_type = "float"
element_size = 64

encodings = [
  { opcode = "EVEX.66.0F3A.W1 57 /r ib", form = "VREDUCESD xmm1{k1}{z}, xmm2, xmm3/m64{m64bcst}, imm8", op_en = "A", vector_length = 128, feature = "AVX512F", masking = "merge+zero", broadcast = "supported" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)", "imm8"]
}

flags_written = []
simd_fp_exceptions = ["invalid", "denormal"]

semantic_general = """
Reduce the scalar double-precision floating-point value in the source operand by the reduction operation specified in imm8. The result is stored in the destination operand. The upper bits of the destination beyond the least-significant element are preserved from the first source operand.
"""

handler = "x86_vreducesd"
jit_lowering = "arm64_vreducesd"
fallback = "zig_vreducesd"

neon_register_model = "x86 XMM register lower 64 bits mapped to ARM64 D register. Upper bits preserved via merging."
neon_flag_model = "No x86 flag state is modified by VREDUCESD."
neon_assembly = """
// ARM64: FREDUCE Dd, Dn  (scalar double precision, with imm8 rounding mode).
// Upper 64 bits of Vd preserved via BFI merge with Vm.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "VREDUCESD is the scalar (low element) variant; bits 127:64 are passed through from xmm2 (first source).",
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
