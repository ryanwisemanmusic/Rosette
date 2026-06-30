// LOGICAL_OR/VPOR.inc
// Source contract: VPOR — Bitwise Logical OR (AVX/AVX2).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/VPOR.inc"
x86_handler = "x86_vpor"
neon_lowering = "arm64_vpor"
lowering_kind = "arm64_documented_contract"

name = "VPOR"
aliases = []
category = "simd_logical"
feature = "avx"

encodings = [
  { opcode = "VEX.128.66.0F.WIG EB /r", form = "VPOR xmm1, xmm2, xmm3/m128", op_en = "B", feature = "avx", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG EB /r", form = "VPOR ymm1, ymm2, ymm3/m256", op_en = "B", feature = "avx2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "N/A"]
}

lanes = { dword = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["Non-EVEX-encoded instruction, see Table 2-21, Type 4 Class Exception Conditions."]

semantic_general = "Performs a bitwise logical OR on the first and second source operands and stores result in destination."

handler = "x86_vpor"
jit_lowering = "arm64_vpor"
fallback = "zig_vpor"

neon_register_model = "VPOR is an AVX/AVX2 bitwise OR instruction."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPOR stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
