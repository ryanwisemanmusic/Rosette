// VARIABLE/VPSRLVQ.inc
// ARM64/NEON mirror generated from ISA/x86/VARIABLE/VPSRLVQ.inc.
// Source contract: VPSRLVQ — Variable Bit Shift Right Logical (Quadword).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VARIABLE/VPSRLVQ.inc"
x86_handler = "x86_vpsrlvq"
neon_lowering = "arm64_neon_shift_right_logical"
lowering_kind = "arm64_documented_contract"

name = "VPSRLVQ"
aliases = []
category = "shift"
feature = "AVX2"
element_type = "i64"
element_size = 64

encodings = []

operand_encoding = { A = { operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)" }, C = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
VPSRLVQ logically shifts each qword right by a per-element variable count.
"""

handler = "x86_vpsrlvq"
jit_lowering = "arm64_neon_shift_right_logical"
fallback = "zig_vpsrlvq"

neon_register_model = "VPSRLVQ is an AVX2/AVX512F variable qword logical shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSRLVQ stub"

neon_notes = [
  "VPSRLVQ logically shifts each qword right by per-element count; ARM64: USHL.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
