// FUSED/VFNMSUB213SD.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFNMSUB213SD.inc"
x86_handler = "x86_vfnmsub213sd"
neon_lowering = "arm64_vfnmsub213sd"
lowering_kind = "arm64_documented_contract"

name = "VFNMSUB213SD"
aliases = []
category = "fused"
feature = "FMA AVX512F"
element_type = "float"
element_size = 64

encodings = [
    { opcode = "VEX.LIG.66.0F38.W1 AF /r", form = "VFNMSUB213SD xmm1, xmm2, xmm3/m64", op_en = "A", feature = "FMA", vector_length = 128, encoding = "VEX" },
    { opcode = "EVEX.LLIG.66.0F38.W1 AF /r", form = "VFNMSUB213SD xmm1{k1}{z}, xmm2, xmm3/m64{er}", op_en = "B", feature = "AVX512F", vector_length = 128, encoding = "EVEX" },
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = ["Invalid", "Denormal", "Overflow", "Underflow", "Precision"]

semantic_general = """
Performs a fused negative multiply-subtract operation on scalar double-precision floating-point values. Multiplies the second source operand with the first source operand (destination), negates the product, subtracts the third source operand, performs rounding, and stores the result in the destination (first source operand).
"""

handler = "x86_vfnmsub213sd"
jit_lowering = "arm64_vfnmsub213sd"
fallback = "zig_x86_vfnmsub213sd"

neon_register_model = "x86 SIMD/FMA registers mapped to ARM64 V registers."
neon_flag_model = "No flags updated."
neon_assembly = "// ARM64: FMLA/FMLS/FMUL/ADD/SUB sequences"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
