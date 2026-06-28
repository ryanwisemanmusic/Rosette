// NEON/CONVERT/VCVTSD2USI.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VCVTSD2USI.inc.

semantic = """
VCVTSD2USI: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTSD2USI.inc"
x86_handler = "x86_vcvtsd2usi"
neon_lowering = "arm64_vcvtsd2usi"
lowering_kind = "arm64_documented_contract"

name = "VCVTSD2USI"
aliases = []
category = "avx512_convert"
feature = "avx512f"
element_type = "u32"
element_size = 32

encodings = [
  { opcode = "EVEX.LLIG.F2.0F.W0 79 /r", form = "VCVTSD2USI r32, xmm2/m64, {er}", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.LLIG.F2.0F.W1 79 /r", form = "VCVTSD2USI r64, xmm2/m64, {er}", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = [
  "Invalid"
]
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Convert the low double-precision FP64 value to an unsigned integer, storing in GPR.
"""

handler = "x86_vcvtsd2usi"
jit_lowering = "arm64_vcvtsd2usi"
fallback = "zig_vcvtsd2usi"

neon_register_model = """
x86 XMM/GPR mapped to ARM64 Vn/xN. VCVTSD2USI is a scalar AVX512 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTSD2USI.
"""

neon_assembly = """
// NEON lowering: VCVTSD2USI conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
