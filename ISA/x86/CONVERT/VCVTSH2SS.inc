// CONVERT/VCVTSH2SS.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VCVTSH2SS.inc.
// Source contract: VCVTSH2SS — Convert Scalar Half to Scalar Single.

semantic = """
xmm1[31:0] := Convert_Half_To_Single(xmm2/m16)
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTSH2SS.inc"
x86_handler = "x86_vcvtsh2ss"
neon_lowering = "arm64_vcvtsh2ss"
lowering_kind = "arm64_documented_contract"

name = "VCVTSH2SS"
aliases = []
category = "avx512_fp16_convert"
feature = "avx512fp16"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.LLIG.NP.MAP6.W0 13 /r", form = "VCVTSH2SS xmm1{k1}{z}, xmm2/m16, {er}", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "evex" }
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
Convert the low half-precision FP16 element to single-precision FP32.
"""

handler = "x86_vcvtsh2ss"
jit_lowering = "arm64_vcvtsh2ss"
fallback = "zig_vcvtsh2ss"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VCVTSH2SS is a scalar AVX512-FP16 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTSH2SS.
"""

neon_assembly = """
// NEON lowering: VCVTSH2SS conversion stub (avx512_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
