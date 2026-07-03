// WRITE/WRMSR.inc
// ARM64/NEON mirror generated from ISA/x86/WRITE/WRMSR.inc.
// Source contract: WRMSR — Write to Model Specific Register.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "WRITE/WRMSR.inc"
x86_handler = "x86_wrmsr"
neon_lowering = "arm64_sysreg_write"
lowering_kind = "arm64_documented_contract"

name = "WRMSR"
aliases = []
category = "system"
feature = "x86_system"
element_type = "none"
element_size = 0

encodings = []

operand_encoding = { ZO = [] }

simd_fp_exceptions = []

semantic_general = """
WRMSR writes EDX:EAX to MSR indexed by ECX.
"""

handler = "x86_wrmsr"
jit_lowering = "arm64_sysreg_write"
fallback = "zig_wrmsr"

neon_register_model = "WRMSR is a privileged system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WRMSR stub"

neon_notes = [
  "WRMSR is x86-specific; ARM64 uses MSR writes.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
