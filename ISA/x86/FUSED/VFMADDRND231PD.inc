// FUSED/VFMADDRND231PD.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFMADDRND231PD.inc"
x86_handler = "x86_vfmaddrnd231pd"
neon_lowering = "arm64_vfmaddrnd231pd"
lowering_kind = "arm64_documented_contract"

name = "VFMADDRND231PD"
aliases = []
category = "fused"
feature = "AVX512F"
element_type = "float"
element_size = 64

encodings = [
    { opcode = "EVEX.128.66.0F3A.W1 B8 /r /ib", form = "VFMADDRND231PD xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst, imm8", op_en = "B", feature = "AVX512F", vector_length = 128, encoding = "EVEX" },
    { opcode = "EVEX.256.66.0F3A.W1 B8 /r /ib", form = "VFMADDRND231PD ymm1{k1}{z}, ymm2, xmm3/m256/m64bcst, imm8", op_en = "B", feature = "AVX512F", vector_length = 256, encoding = "EVEX" },
    { opcode = "EVEX.512.66.0F3A.W1 B8 /r /ib", form = "VFMADDRND231PD zmm1{k1}{z}, zmm2, zmm3/m512/m64bcst{er}, imm8", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "EVEX" },
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = ["Invalid", "Denormal", "Overflow", "Underflow", "Precision"]

semantic_general = """
Performs a fused multiply-add with rounding override on packed double-precision floating-point values. Multiplies the second source operand with the third source operand, adds the result to the first source operand (destination), performs rounding controlled by imm8, and stores the result in the destination.
"""

handler = "x86_vfmaddrnd231pd"
jit_lowering = "arm64_vfmaddrnd231pd"
fallback = "zig_x86_vfmaddrnd231pd"

neon_register_model = "x86 SIMD/FMA registers mapped to ARM64 V registers."
neon_flag_model = "No flags updated."
neon_assembly = "// ARM64: FMLA/FMLS/FMUL/ADD/SUB sequences"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
