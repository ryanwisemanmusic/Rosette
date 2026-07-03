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

encodings = []

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
