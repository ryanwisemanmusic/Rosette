// VARIABLE/VPSRAVD.inc
// ARM64/NEON mirror generated from ISA/x86/VARIABLE/VPSRAVD.inc.
// Source contract: VPSRAVD — Variable Bit Shift Right Arithmetic (Doubleword).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VARIABLE/VPSRAVD.inc"
x86_handler = "x86_vpsravd"
neon_lowering = "arm64_neon_shift_right_arith"
lowering_kind = "arm64_documented_contract"

name = "VPSRAVD"
aliases = []
category = "shift"
feature = "AVX2"
element_type = "i32"
element_size = 32

encodings = []

operand_encoding = { A = { operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)" }, C = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
VPSRAVD arithmetically shifts each dword right by a per-element variable count.
"""

handler = "x86_vpsravd"
jit_lowering = "arm64_neon_shift_right_arith"
fallback = "zig_vpsravd"

neon_register_model = "VPSRAVD is an AVX2/AVX512F variable dword arithmetic shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSRAVD stub"

neon_notes = [
  "VPSRAVD arithmetically shifts each dword right by per-element count; ARM64: SSHR.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
