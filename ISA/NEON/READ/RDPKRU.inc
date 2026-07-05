// READ/RDPKRU.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDPKRU.inc.
// Source contract: RDPKRU — Read Data from User Page Key Register.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDPKRU.inc"
x86_handler = "x86_rdpkru"
neon_lowering = "arm64_sysreg_read"
lowering_kind = "arm64_documented_contract"

name = "RDPKRU"
aliases = []
category = "system"
feature = "OSPKE"
element_type = "none"
element_size = 0

encodings = []

operand_encoding = { ZO = [] }

simd_fp_exceptions = []

semantic_general = """
RDPKRU reads PKRU register into EAX when ECX=EDX=0.
"""

handler = "x86_rdpkru"
jit_lowering = "arm64_sysreg_read"
fallback = "zig_rdpkru"

neon_register_model = "RDPKRU is a system instruction for PKRU register read. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDPKRU stub — reads PKRU via arm64 APIAKey_EL1 emulation"

neon_notes = [
  "RDPKRU is x86-specific; no ARM64 PKRU equivalent (ARM64 uses APIAKey_EL1 for pointer auth).",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
