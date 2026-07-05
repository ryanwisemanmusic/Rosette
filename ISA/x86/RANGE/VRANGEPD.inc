// RANGE/VRANGEPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/RANGE/VRANGEPD.inc.
// Source contract: VRANGEPD — Range Restriction Calculation for Packed Pairs of Float64 Values.

semantic = """
VRANGEPD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_arithmetic.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RANGE/VRANGEPD.inc"
x86_handler = "x86_vrangepd"
neon_lowering = "arm64_vrangepd"
lowering_kind = "arm64_documented_contract"

name = "VRANGEPD"
aliases = []
category = "simd_arithmetic"
feature = "AVX512DQ"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F3A.W1 50 /r ib", form = "VRANGEPD xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst, imm8", op_en = "A", feature = "AVX512VL AVX512DQ", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F3A.W1 50 /r ib", form = "VRANGEPD ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst, imm8", op_en = "A", feature = "AVX512VL AVX512DQ", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F3A.W1 50 /r ib", form = "VRANGEPD zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst{sae}, imm8", op_en = "A", feature = "AVX512DQ", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Denormal"]
other_exceptions = [
  "See Table 2-46, \"Type E2 Class Exception Conditions.\""
]

handler = "x86_vrangepd"
jit_lowering = "arm64_vrangepd"
fallback = "zig_vrangepd"

neon_register_model = "documented_contract"
neon_flag_model = "documented_contract"
neon_assembly = "documented_contract"
neon_notes = ["documented_contract"]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
