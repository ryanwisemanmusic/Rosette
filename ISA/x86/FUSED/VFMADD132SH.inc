// FUSED/VFMADD132SH.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFMADD132SH.inc"
x86_handler = "x86_vfmadd132sh"
neon_lowering = "arm64_vfmadd132sh"
lowering_kind = "arm64_documented_contract"

name = "VFMADD132SH"
aliases = []
category = "fused"
feature = "AVX512-FP16"
element_type = "float"
element_size = 16

encodings = [
    { opcode = "EVEX.LLIG.66.MAP6.W0 99 /r", form = "VFMADD132SH xmm1{k1}{z}, xmm2, xmm3/m16 {er}", op_en = "B", feature = "AVX512-FP16", vector_length = 128, encoding = "EVEX" },
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = ["Invalid", "Denormal", "Overflow", "Underflow", "Precision"]

semantic_general = """
Performs a fused multiply-add operation on scalar FP16 floating-point values. Multiplies the first source operand (destination) with the third source operand, adds the second source operand, performs rounding, and stores the result in the destination (first source operand).
"""

handler = "x86_vfmadd132sh"
jit_lowering = "arm64_vfmadd132sh"
fallback = "zig_x86_vfmadd132sh"

neon_register_model = "x86 SIMD/FMA registers mapped to ARM64 V registers."
neon_flag_model = "No flags updated."
neon_assembly = "// ARM64: FMLA/FMLS/FMUL/ADD/SUB sequences"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
