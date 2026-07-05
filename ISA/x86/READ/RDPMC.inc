// READ/RDPMC.inc
// RDPMC — Read Performance-Monitoring Counters.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDPMC.inc"
x86_handler = "x86_rdpmc"
neon_lowering = "arm64_documented_contract"
lowering_kind = "arm64_documented_contract"

name = "RDPMC"
category = "system_register_read"
element_type = "u32"

encodings = [
  { opcode = "0F 33", form = "RDPMC", op_en = "ZO", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { ZO = [] }

reads = ["ECX"]
writes = ["EDX:EAX"]
flags_read = []
flags_written = []

semantic = """
EDX:EAX := PMC[ECX];
"""

exceptions = [
  "#GP(0) if the value in ECX is an invalid or disabled PMC index",
  "#UD if the LOCK prefix is used",
  "#GP(0) if CR4.PCE = 0 and CPL > 0"
]

handler = "x86_rdpmc"
jit_lowering = "arm64_sysreg_read"

neon_register_model = "RDPMC reads an x86 performance-monitoring counter. No ARM64 NEON equivalent."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDPMC stub"
neon_notes = ["RDPMC reads a performance counter specified by ECX into EDX:EAX.", "CR4.PCE controls user-mode access."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
