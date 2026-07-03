// WRITE/WRFSBASE.inc
// WRFSBASE — Write FS Segment Base.

name = "WRFSBASE"
category = "system"
feature = "FSGSBASE"
element_type = "gpr"

encodings = [
  { opcode = "F3 REX.W 0F AE /2", form = "WRFSBASE r64", op_en = "M", feature = "FSGSBASE", vector_length = 0, encoding = "legacy" },
  { opcode = "F3 0F AE /2", form = "WRFSBASE r32", op_en = "M", feature = "FSGSBASE", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { M = { operand1 = "ModRM:r/m (r)" } }

reads = ["SRC"]
writes = ["FS_BASE"]
flags_read = []
flags_written = []

semantic = """
FS_BASE := SRC;
"""

exceptions = [
  "#UD if not in 64-bit mode",
  "#UD if LOCK prefix is used",
  "#UD if CR4.FSGSBASE = 0",
  "#UD if CPUID.07H.0H:EBX.FSGSBASE = 0",
  "#GP(0) if source register contains non-canonical address"
]

handler = "x86_wrfsbase"
jit_lowering = "arm64_sysreg_write"

neon_register_model = "WRFSBASE is a 64-bit mode only system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WRFSBASE stub"
neon_notes = ["WRFSBASE writes the FS segment base address.", "ARM64: MSR writes to system registers."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
