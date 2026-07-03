// WRITE/WBNOINVD.inc
// WBNOINVD — Write Back and Do Not Invalidate Cache.

name = "WBNOINVD"
category = "cache"
feature = "WBNOINVD"
element_type = "none"

encodings = [
  { opcode = "F3 0F 09", form = "WBNOINVD", op_en = "ZO", feature = "WBNOINVD", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { ZO = [] }

reads = []
writes = []
flags_read = []
flags_written = []

semantic = """
WriteBack(InternalCaches);
Continue;
"""

exceptions = [
  "#GP(0) if current privilege level is not 0",
  "#UD if the LOCK prefix is used"
]

handler = "x86_wbnoinvd"
jit_lowering = "arm64_cache_wbnoinvd"

neon_register_model = "WBNOINVD is a privileged cache control instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WBNOINVD stub"
neon_notes = ["WBNOINVD writes back caches without invalidation.", "ARM64: use DC CVAC or DC CVAU."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
