// CONVERT/VCVTSH2SD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VCVTSH2SD.inc.
// Source contract: VCVTSH2SD — Convert Scalar Half to Scalar Double.

semantic = """
xmm1[63:0] := Convert_Half_To_Double(xmm2/m16)
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTSH2SD.inc"
x86_handler = "x86_vcvtsh2sd"
neon_lowering = "arm64_vcvtsh2sd"
lowering_kind = "arm64_documented_contract"

name = "VCVTSH2SD"
aliases = []
category = "avx512_fp16_convert"
feature = "avx512fp16"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.LLIG.F3.MAP5.W0 5A /r", form = "VCVTSH2SD xmm1{k1}{z}, xmm2/m16, {er}", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "evex" }
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
Convert the low half-precision FP16 element to double-precision FP64.
"""

handler = "x86_vcvtsh2sd"
jit_lowering = "arm64_vcvtsh2sd"
fallback = "zig_vcvtsh2sd"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VCVTSH2SD is a scalar AVX512-FP16 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTSH2SD.
"""

neon_assembly = """
// NEON lowering: VCVTSH2SD conversion stub (avx512_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
