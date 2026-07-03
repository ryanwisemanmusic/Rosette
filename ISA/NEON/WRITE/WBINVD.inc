// WRITE/WBINVD.inc
// ARM64/NEON mirror generated from ISA/x86/WRITE/WBINVD.inc.
// Source contract: WBINVD — Write Back and Invalidate Cache.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "WRITE/WBINVD.inc"
x86_handler = "x86_wbinvd"
neon_lowering = "arm64_cache_wbinvd"
lowering_kind = "arm64_documented_contract"

name = "WBINVD"
aliases = []
category = "cache"
feature = "x86_system"
element_type = "none"
element_size = 0

encodings = []

operand_encoding = { ZO = [] }

simd_fp_exceptions = []

semantic_general = """
WBINVD writes back and invalidates all processor caches.
"""

handler = "x86_wbinvd"
jit_lowering = "arm64_cache_wbinvd"
fallback = "zig_wbinvd"

neon_register_model = "WBINVD is a privileged cache control instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WBINVD stub"

neon_notes = [
  "WBINVD is x86-specific; ARM64 uses DC CISW/CSW sequences.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
