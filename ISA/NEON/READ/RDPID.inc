// READ/RDPID.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDPID.inc.
// Source contract: RDPID — Read Processor ID.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDPID.inc"
x86_handler = "x86_rdpid"
neon_lowering = "arm64_sysreg_read"
lowering_kind = "arm64_documented_contract"

name = "RDPID"
aliases = []
category = "system"
feature = "RDPID"
element_type = "gpr"
element_size = 0

encodings = []

operand_encoding = { RM = { operand1 = "ModRM:r/m (w)" } }

simd_fp_exceptions = []

semantic_general = """
RDPID reads the processor ID (IA32_TSC_AUX) into a GPR.
"""

handler = "x86_rdpid"
jit_lowering = "arm64_sysreg_read"
fallback = "zig_rdpid"

neon_register_model = "RDPID reads IA32_TSC_AUX. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDPID stub — reads processor ID via arm64 MPIDR_EL1 emulation"

neon_notes = [
  "RDPID is x86-specific; ARM64 uses MPIDR_EL1 for processor ID.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
