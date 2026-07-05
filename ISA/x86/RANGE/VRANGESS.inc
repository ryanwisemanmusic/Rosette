// RANGE/VRANGESS.inc
// ARM64/NEON translation mirror generated from ISA/x86/RANGE/VRANGESS.inc.
// Source contract: VRANGESS — Range Restriction Calculation From a Pair of Scalar Float32 Values.

semantic = """
VRANGESS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_arithmetic_scalar.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RANGE/VRANGESS.inc"
x86_handler = "x86_vrangess"
neon_lowering = "arm64_vrangess"
lowering_kind = "arm64_documented_contract"

name = "VRANGESS"
aliases = []
category = "simd_arithmetic_scalar"
feature = "AVX512DQ"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.LLIG.66.0F3A.W0 51 /r ib", form = "VRANGESS xmm1 {k1}{z}, xmm2, xmm3/m32{sae}, imm8", op_en = "A", feature = "AVX512DQ", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 0 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Denormal"]
other_exceptions = [
  "See Table 2-47, \"Type E3 Class Exception Conditions.\""
]

handler = "x86_vrangess"
jit_lowering = "arm64_vrangess"
fallback = "zig_vrangess"

neon_register_model = "documented_contract"
neon_flag_model = "documented_contract"
neon_assembly = "documented_contract"
neon_notes = ["documented_contract"]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
