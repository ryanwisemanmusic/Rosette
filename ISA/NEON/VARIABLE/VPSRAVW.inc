// VARIABLE/VPSRAVW.inc
// ARM64/NEON mirror generated from ISA/x86/VARIABLE/VPSRAVW.inc.
// Source contract: VPSRAVW — Variable Bit Shift Right Arithmetic (Word).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VARIABLE/VPSRAVW.inc"
x86_handler = "x86_vpsravw"
neon_lowering = "arm64_neon_shift_right_arith"
lowering_kind = "arm64_documented_contract"

name = "VPSRAVW"
aliases = []
category = "shift"
feature = "AVX512BW"
element_type = "i16"
element_size = 16

encodings = []

operand_encoding = { B = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
VPSRAVW arithmetically shifts each word right by a per-element variable count.
"""

handler = "x86_vpsravw"
jit_lowering = "arm64_neon_shift_right_arith"
fallback = "zig_vpsravw"

neon_register_model = "VPSRAVW is an AVX512BW variable word arithmetic shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSRAVW stub"

neon_notes = [
  "VPSRAVW arithmetically shifts each word right by per-element count; ARM64: SSHR.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
