// WRITE/WBINVD.inc
// WBINVD — Write Back and Invalidate Cache.

name = "WBINVD"
category = "cache"
feature = "x86_system"
element_type = "none"

encodings = [
  { opcode = "0F 09", form = "WBINVD", op_en = "ZO", feature = "x86_system", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { ZO = [] }

reads = []
writes = []
flags_read = []
flags_written = []

semantic = """
WriteBack(InternalCaches);
Flush(InternalCaches);
SignalWriteBack(ExternalCaches);
SignalFlush(ExternalCaches);
Continue;
"""

exceptions = [
  "#GP(0) if current privilege level is not 0",
  "#UD if the LOCK prefix is used"
]

handler = "x86_wbinvd"
jit_lowering = "arm64_cache_wbinvd"

neon_register_model = "WBINVD is a privileged cache control instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WBINVD stub"
neon_notes = ["WBINVD writes back and invalidates all processor caches.", "ARM64: use DC CISW or DC CSW sequences."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
