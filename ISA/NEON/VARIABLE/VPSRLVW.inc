// VARIABLE/VPSRLVW.inc
// ARM64/NEON mirror generated from ISA/x86/VARIABLE/VPSRLVW.inc.
// Source contract: VPSRLVW — Variable Bit Shift Right Logical (Word).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VARIABLE/VPSRLVW.inc"
x86_handler = "x86_vpsrlvw"
neon_lowering = "arm64_neon_shift_right_logical"
lowering_kind = "arm64_documented_contract"

name = "VPSRLVW"
aliases = []
category = "shift"
feature = "AVX512BW"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 10 /r", form = "VPSRLVW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "B", feature = "AVX512VL AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 10 /r", form = "VPSRLVW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "B", feature = "AVX512VL AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 10 /r", form = "VPSRLVW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "B", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = { B = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
VPSRLVW logically shifts each word right by a per-element variable count.
"""

handler = "x86_vpsrlvw"
jit_lowering = "arm64_neon_shift_right_logical"
fallback = "zig_vpsrlvw"

neon_register_model = "VPSRLVW is an AVX512BW variable word logical shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSRLVW stub"

neon_notes = [
  "VPSRLVW logically shifts each word right by per-element count; ARM64: USHL.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
