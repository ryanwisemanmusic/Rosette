// WRITE/WBNOINVD.inc
// ARM64/NEON mirror generated from ISA/x86/WRITE/WBNOINVD.inc.
// Source contract: WBNOINVD — Write Back and Do Not Invalidate Cache.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "WRITE/WBNOINVD.inc"
x86_handler = "x86_wbnoinvd"
neon_lowering = "arm64_cache_wbnoinvd"
lowering_kind = "arm64_documented_contract"

name = "WBNOINVD"
aliases = []
category = "cache"
feature = "WBNOINVD"
element_type = "none"
element_size = 0

encodings = []

operand_encoding = { ZO = [] }

simd_fp_exceptions = []

semantic_general = """
WBNOINVD writes back caches without invalidation.
"""

handler = "x86_wbnoinvd"
jit_lowering = "arm64_cache_wbnoinvd"
fallback = "zig_wbnoinvd"

neon_register_model = "WBNOINVD is a privileged cache control instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WBNOINVD stub"

neon_notes = [
  "WBNOINVD is x86-specific; ARM64 uses DC CVAC or DC CVAU.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
