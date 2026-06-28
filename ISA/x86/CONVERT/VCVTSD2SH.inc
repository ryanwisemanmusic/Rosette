// CONVERT/VCVTSD2SH.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VCVTSD2SH.inc.
// Source contract: VCVTSD2SH — Convert Scalar Double to Scalar Half (FP16).

semantic = """
xmm1[7:0] := Convert_Double_To_Half(xmm2/m64)
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTSD2SH.inc"
x86_handler = "x86_vcvtsd2sh"
neon_lowering = "arm64_vcvtsd2sh"
lowering_kind = "arm64_documented_contract"

name = "VCVTSD2SH"
aliases = []
category = "avx512_fp16_convert"
feature = "avx512fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.LLIG.F2.MAP5.W1 5A /r", form = "VCVTSD2SH xmm1{k1}{z}, xmm2/m64, {er}", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "evex" }
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
Convert the low double-precision FP64 element to half-precision FP16.
"""

handler = "x86_vcvtsd2sh"
jit_lowering = "arm64_vcvtsd2sh"
fallback = "zig_vcvtsd2sh"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VCVTSD2SH is a scalar AVX512-FP16 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTSD2SH.
"""

neon_assembly = """
// NEON lowering: VCVTSD2SH conversion stub (avx512_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
