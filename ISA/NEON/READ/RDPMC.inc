// READ/RDPMC.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDPMC.inc.
// Source contract: RDPMC — Read Performance Monitoring Counter.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDPMC.inc"
x86_handler = "x86_rdpmc"
neon_lowering = "arm64_pmu_read"
lowering_kind = "arm64_documented_contract"

name = "RDPMC"
aliases = []
category = "system"
feature = "x86_system"
element_type = "none"
element_size = 0

encodings = []

operand_encoding = { ZO = [] }

simd_fp_exceptions = []

semantic_general = """
RDPMC reads performance monitoring counter indexed by ECX into EDX:EAX.
"""

handler = "x86_rdpmc"
jit_lowering = "arm64_pmu_read"
fallback = "zig_rdpmc"

neon_register_model = "RDPMC is a privileged system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDPMC stub — reads PMU counter via arm64 PMEVCNTR<n>_EL0"

neon_notes = [
  "RDPMC is x86-specific; ARM64 uses PMEVCNTR<n>_EL0 for performance counter reads.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
