// VARIABLE/VPSRAVQ.inc
// ARM64/NEON mirror generated from ISA/x86/VARIABLE/VPSRAVQ.inc.
// Source contract: VPSRAVQ — Variable Bit Shift Right Arithmetic (Quadword).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VARIABLE/VPSRAVQ.inc"
x86_handler = "x86_vpsravq"
neon_lowering = "arm64_neon_shift_right_arith"
lowering_kind = "arm64_documented_contract"

name = "VPSRAVQ"
aliases = []
category = "shift"
feature = "AVX512F"
element_type = "i64"
element_size = 64

encodings = []

operand_encoding = { C = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
VPSRAVQ arithmetically shifts each qword right by a per-element variable count.
"""

handler = "x86_vpsravq"
jit_lowering = "arm64_neon_shift_right_arith"
fallback = "zig_vpsravq"

neon_register_model = "VPSRAVQ is an AVX512F variable qword arithmetic shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSRAVQ stub"

neon_notes = [
  "VPSRAVQ arithmetically shifts each qword right by per-element count; ARM64: SSHR.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
