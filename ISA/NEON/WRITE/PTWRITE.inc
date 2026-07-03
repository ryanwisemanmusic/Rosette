// WRITE/PTWRITE.inc
// ARM64/NEON mirror generated from ISA/x86/WRITE/PTWRITE.inc.
// Source contract: PTWRITE — Write Data to a Processor Trace Packet.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "WRITE/PTWRITE.inc"
x86_handler = "x86_ptwrite"
neon_lowering = "arm64_sys_write_ptwrite"
lowering_kind = "arm64_documented_contract"

name = "PTWRITE"
aliases = []
category = "system"
feature = "PTWRITE"
element_type = "gpr"
element_size = 0

encodings = []

operand_encoding = { RM = { operand1 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
PTWRITE sends source data to Intel Processor Trace hardware.
"""

handler = "x86_ptwrite"
jit_lowering = "arm64_sys_write_ptwrite"
fallback = "zig_ptwrite"

neon_register_model = "PTWRITE is an Intel PT system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: PTWRITE stub"

neon_notes = [
  "PTWRITE is x86-specific; no ARM64 equivalent.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
