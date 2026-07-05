// READ/RDFSBASE.inc
// RDFSBASE — Read FS Segment Base.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDFSBASE.inc"
x86_handler = "x86_rdfsbase"
neon_lowering = "arm64_documented_contract"
lowering_kind = "arm64_documented_contract"

name = "RDFSBASE"
category = "system_register_read"
feature = "FSGSBASE"
element_type = "gpr"

encodings = [
  { opcode = "F3 REX.W 0F AE /0", form = "RDFSBASE r64", op_en = "M", feature = "FSGSBASE", vector_length = 0, encoding = "legacy" },
  { opcode = "F3 0F AE /0", form = "RDFSBASE r32", op_en = "M", feature = "FSGSBASE", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { M = { operand1 = "ModRM:r/m (w)" } }

reads = ["FS_BASE"]
writes = ["DST"]
flags_read = []
flags_written = []

semantic = """
DST := FS_BASE;
"""

exceptions = [
  "#UD if not in 64-bit mode",
  "#UD if LOCK prefix is used",
  "#UD if CR4.FSGSBASE = 0",
  "#UD if CPUID.07H.0H:EBX.FSGSBASE = 0"
]

handler = "x86_rdfsbase"
jit_lowering = "arm64_sysreg_read"

neon_register_model = "RDFSBASE is a 64-bit mode only system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDFSBASE stub"
neon_notes = ["RDFSBASE reads the FS segment base address.", "ARM64: MRS reads from system registers."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
