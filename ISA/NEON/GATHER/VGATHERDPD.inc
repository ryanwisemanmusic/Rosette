// GATHER/VGATHERDPD.inc
// ARM64/NEON mirror generated from ISA/x86/GATHER/VGATHERDPD.inc.
// Source contract: VGATHERDPD — avx512_gather.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GATHER/VGATHERDPD.inc"
x86_handler = "x86_vgatherdpd"
neon_lowering = "arm64_vgatherdpd"
lowering_kind = "arm64_documented_contract"

name = "VGATHERDPD"
aliases = []
category = "avx512_gather"
feature = "avx512f"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F38.W1 92 /r", form = "VGATHERDPD xmm1, vm32x, xmm2", op_en = "A", feature = "avx2", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F38.W1 92 /r", form = "VGATHERDPD ymm1, vm32x, ymm2", op_en = "A", feature = "avx2", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.128.66.0F38.W1 92 /vsib", form = "VGATHERDPD xmm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.256.66.0F38.W1 92 /vsib", form = "VGATHERDPD ymm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.512.66.0F38.W1 92 /vsib", form = "VGATHERDPD zmm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Gather Packed Double-Precision Floating-Point Values with Signed Dword Indices.
"""

handler = "x86_vgatherdpd"
jit_lowering = "arm64_vgatherdpd"
fallback = "zig_vgatherdpd"

neon_register_model = """
VGATHERDPD is a gather instruction.
"""

neon_flag_model = """
VGATHERDPD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VGATHERDPD stub (avx512_gather)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
