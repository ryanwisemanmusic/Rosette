// FUSED/VFNMSUB132PD.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFNMSUB132PD.inc"
x86_handler = "x86_vfnmsub132pd"
neon_lowering = "arm64_vfnmsub132pd"
lowering_kind = "arm64_documented_contract"

name = "VFNMSUB132PD"
aliases = []
category = "fused"
feature = "FMA AVX512F AVX512VL"
element_type = "float"
element_size = 64

encodings = [
    { opcode = "VEX.128.66.0F38.W1 9E /r", form = "VFNMSUB132PD xmm1, xmm2, xmm3/m128", op_en = "A", feature = "FMA", vector_length = 128, encoding = "VEX" },
    { opcode = "VEX.256.66.0F38.W1 9E /r", form = "VFNMSUB132PD ymm1, ymm2, ymm3/m256", op_en = "A", feature = "FMA", vector_length = 256, encoding = "VEX" },
    { opcode = "EVEX.128.66.0F38.W1 9E /r", form = "VFNMSUB132PD xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "EVEX" },
    { opcode = "EVEX.256.66.0F38.W1 9E /r", form = "VFNMSUB132PD ymm1{k1}{z}, ymm2, xmm3/m256/m64bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "EVEX" },
    { opcode = "EVEX.512.66.0F38.W1 9E /r", form = "VFNMSUB132PD zmm1{k1}{z}, zmm2, xmm3/m512/m64bcst{er}", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "EVEX" },
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = ["Invalid", "Denormal", "Overflow", "Underflow", "Precision"]

semantic_general = """
Performs a fused negative multiply-subtract operation on packed double-precision floating-point values. Multiplies the first source operand (destination) with the third source operand, negates the product, subtracts the second source operand, performs rounding, and stores the result in the destination (first source operand).
"""

handler = "x86_vfnmsub132pd"
jit_lowering = "arm64_vfnmsub132pd"
fallback = "zig_x86_vfnmsub132pd"

neon_register_model = "x86 SIMD/FMA registers mapped to ARM64 V registers."
neon_flag_model = "No flags updated."
neon_assembly = "// ARM64: FMLA/FMLS/FMUL/ADD/SUB sequences"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
