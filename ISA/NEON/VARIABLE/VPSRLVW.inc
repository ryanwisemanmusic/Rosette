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

encodings = []

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
