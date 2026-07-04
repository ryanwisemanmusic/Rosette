// NEON/FIX_UP/VFIXUPIMMSS.inc
// ARM64/NEON mirror generated from ISA/x86/FIX_UP/VFIXUPIMMSS.inc.

semantic = """
VFIXUPIMMSS: preserve the operation and form-specific semantic blocks.
Category: simd_fixup.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FIX_UP/VFIXUPIMMSS.inc"
x86_handler = "x86_vfixupimmss"
neon_lowering = "arm64_vfixupimmss"
lowering_kind = "arm64_scalar"

name = "VFIXUPIMMSS"
aliases = []
category = "simd_fixup"
feature = "AVX512F"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.LLIG.66.0F3A.W0 55 /r ib", form = "VFIXUPIMMSS xmm1{k1}{z}, xmm2, xmm3/m32/m32bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = [
  "Zero",
  "Invalid"
]
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Merge the low float32 element of SRC1 with the output of the fix-up function applied to SRC2 and SRC3, using imm8 to select the fix-up action. The upper bits of the destination (above bit 31) are copied from SRC1.
"""

handler = "x86_vfixupimmss"
jit_lowering = "arm64_vfixupimmss"
fallback = "zig_vfixupimmss"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VFIXUPIMMSS is a scalar AVX512F fix-up operation on the low float32 element.
"""

neon_flag_model = """
No x86 flags are modified by VFIXUPIMMSS.
"""

neon_assembly = """
// NEON lowering: scalar fix-up with imm8 action selector
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
