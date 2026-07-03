// VARIABLE/VPSLLVD.inc
// ARM64/NEON mirror generated from ISA/x86/VARIABLE/VPSLLVD.inc.
// Source contract: VPSLLVD — Variable Bit Shift Left Logical (Doubleword).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VARIABLE/VPSLLVD.inc"
x86_handler = "x86_vpsllvd"
neon_lowering = "arm64_neon_shift_left"
lowering_kind = "arm64_documented_contract"

name = "VPSLLVD"
aliases = []
category = "shift"
feature = "AVX2"
element_type = "i32"
element_size = 32

encodings = []

operand_encoding = { A = { operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)" }, C = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
VPSLLVD shifts each dword element left by a per-element variable count.
"""

handler = "x86_vpsllvd"
jit_lowering = "arm64_neon_shift_left"
fallback = "zig_vpsllvd"

neon_register_model = "VPSLLVD is an AVX2/AVX512F variable dword shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSLLVD stub"

neon_notes = [
  "VPSLLVD shifts each dword by per-element count; ARM64: SSHL/USHL.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
