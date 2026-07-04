// DIV/VDIVPH.inc
// ARM64/NEON mirror generated from ISA/x86/DIV/VDIVPH.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VDIVPH: preserve the operation and form-specific semantic blocks.
Category: avx512_fp16_div.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DIV/VDIVPH.inc"
x86_handler = "x86_vdivph"
neon_lowering = "arm64_vdivph"
lowering_kind = "neon_vector"

name = "VDIVPH"
aliases = []
category = "avx512_fp16_div"
feature = "avx512fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.NP.MAP5.W0 5E /r", form = "VDIVPH xmm1{k1}{z}, xmm2, xmm3/m128/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.256.NP.MAP5.W0 5E /r", form = "VDIVPH ymm1{k1}{z}, ymm2, ymm3/m256/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.512.NP.MAP5.W0 5E /r", form = "VDIVPH zmm1{k1}{z}, zmm2, zmm3/m512/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 512, encoding = "evex", broadcast = "m16bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Underflow", "Overflow", "Precision", "Denormal", "Zero"]
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Divide packed FP16 values from the first source operand by the corresponding elements in the second source operand.
"""

handler = "x86_vdivph"
jit_lowering = "arm64_vdivph"
fallback = "zig_vdivph"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VDIVPH is an AVX512-FP16 packed divide.
"""

neon_flag_model = """
No x86 flags modified by VDIVPH.
"""

neon_assembly = """
// NEON lowering: VDIVPH packed divide stub (avx512_fp16_div)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
