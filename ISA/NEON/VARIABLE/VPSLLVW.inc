// VARIABLE/VPSLLVW.inc
// ARM64/NEON mirror generated from ISA/x86/VARIABLE/VPSLLVW.inc.
// Source contract: VPSLLVW — Variable Bit Shift Left Logical (Word).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VARIABLE/VPSLLVW.inc"
x86_handler = "x86_vpsllvw"
neon_lowering = "arm64_neon_shift_left"
lowering_kind = "arm64_documented_contract"

name = "VPSLLVW"
aliases = []
category = "shift"
feature = "AVX512BW"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 12 /r", form = "VPSLLVW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "B", feature = "AVX512VL AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 12 /r", form = "VPSLLVW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "B", feature = "AVX512VL AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 12 /r", form = "VPSLLVW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "B", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = { B = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
VPSLLVW shifts each word element left by a per-element variable count.
"""

handler = "x86_vpsllvw"
jit_lowering = "arm64_neon_shift_left"
fallback = "zig_vpsllvw"

neon_register_model = "VPSLLVW is an AVX512BW variable word shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSLLVW stub"

neon_notes = [
  "VPSLLVW shifts each word by per-element count; ARM64: SSHL/USHL.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
