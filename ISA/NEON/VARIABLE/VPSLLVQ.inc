// VARIABLE/VPSLLVQ.inc
// ARM64/NEON mirror generated from ISA/x86/VARIABLE/VPSLLVQ.inc.
// Source contract: VPSLLVQ — Variable Bit Shift Left Logical (Quadword).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VARIABLE/VPSLLVQ.inc"
x86_handler = "x86_vpsllvq"
neon_lowering = "arm64_neon_shift_left"
lowering_kind = "arm64_documented_contract"

name = "VPSLLVQ"
aliases = []
category = "shift"
feature = "AVX2"
element_type = "i64"
element_size = 64

encodings = []

operand_encoding = { A = { operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)" }, C = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
VPSLLVQ shifts each qword element left by a per-element variable count.
"""

handler = "x86_vpsllvq"
jit_lowering = "arm64_neon_shift_left"
fallback = "zig_vpsllvq"

neon_register_model = "VPSLLVQ is an AVX2/AVX512F variable qword shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSLLVQ stub"

neon_notes = [
  "VPSLLVQ shifts each qword by per-element count; ARM64: SSHL/USHL.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
