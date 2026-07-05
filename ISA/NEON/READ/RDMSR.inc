// READ/RDMSR.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDMSR.inc.
// Source contract: RDMSR — Read Model Specific Register.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDMSR.inc"
x86_handler = "x86_rdmsr"
neon_lowering = "arm64_mrs_read"
lowering_kind = "arm64_documented_contract"

name = "RDMSR"
aliases = []
category = "system"
feature = "x86_system"
element_type = "none"
element_size = 0

encodings = []

operand_encoding = { ZO = [] }

simd_fp_exceptions = []

semantic_general = """
RDMSR reads MSR indexed by ECX into EDX:EAX.
"""

handler = "x86_rdmsr"
jit_lowering = "arm64_mrs_read"
fallback = "zig_rdmsr"

neon_register_model = "RDMSR is a privileged system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDMSR stub — reads system register via arm64 MRS"

neon_notes = [
  "RDMSR is x86-specific; ARM64 uses MRS for system register reads.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
