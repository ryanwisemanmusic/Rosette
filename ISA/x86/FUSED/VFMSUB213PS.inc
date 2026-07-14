// FUSED/VFMSUB213PS.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFMSUB213PS.inc"
x86_handler = "x86_vfmsub213ps"
neon_lowering = "arm64_vfmsub213ps"
lowering_kind = "arm64_documented_contract"

name = "VFMSUB213PS"
aliases = []
category = "fused"
feature = "FMA AVX512F AVX512VL"
element_type = "float"
element_size = 32

encodings = [
    { opcode = "VEX.128.66.0F38.W0 AA /r", form = "VFMSUB213PS xmm1, xmm2, xmm3/m128", op_en = "A", feature = "FMA", vector_length = 128, encoding = "VEX" },
    { opcode = "VEX.256.66.0F38.W0 AA /r", form = "VFMSUB213PS ymm1, ymm2, ymm3/m256", op_en = "A", feature = "FMA", vector_length = 256, encoding = "VEX" },
    { opcode = "EVEX.128.66.0F38.W0 AA /r", form = "VFMSUB213PS xmm1{k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "EVEX" },
    { opcode = "EVEX.256.66.0F38.W0 AA /r", form = "VFMSUB213PS ymm1{k1}{z}, ymm2, xmm3/m256/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "EVEX" },
    { opcode = "EVEX.512.66.0F38.W0 AA /r", form = "VFMSUB213PS zmm1{k1}{z}, zmm2, xmm3/m512/m32bcst{er}", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "EVEX" },
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = ["Invalid", "Denormal", "Overflow", "Underflow", "Precision"]

semantic_general = """
Performs a fused multiply-subtract operation on packed single-precision floating-point values. Multiplies the second source operand with the first source operand (destination), subtracts the third source operand, performs rounding, and stores the result in the destination (first source operand).
"""

handler = "x86_vfmsub213ps"
jit_lowering = "arm64_vfmsub213ps"
fallback = "zig_x86_vfmsub213ps"

neon_register_model = "x86 SIMD/FMA registers mapped to ARM64 V registers."
neon_flag_model = "No flags updated."
neon_assembly = "// ARM64: FMLA/FMLS/FMUL/ADD/SUB sequences"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
