// READ/RDMSR.inc
// RDMSR — Read Model Specific Register.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDMSR.inc"
x86_handler = "x86_rdmsr"
neon_lowering = "arm64_documented_contract"
lowering_kind = "arm64_documented_contract"

name = "RDMSR"
category = "system_msr_read"
element_type = "u32"

encodings = [
  { opcode = "0F 32", form = "RDMSR", op_en = "ZO", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { ZO = [] }

reads = ["ECX"]
writes = ["EDX:EAX"]
flags_read = []
flags_written = []

semantic = """
EDX:EAX := MSR[ECX];
"""

exceptions = [
  "#GP(0) if the value in ECX is an invalid or reserved MSR index",
  "#GP(0) if the value in ECX is a non-architectural MSR that is not supported",
  "#UD if the LOCK prefix is used",
  "#GP(0) if CPL > 0 (privileged instruction)"
]

handler = "x86_rdmsr"
jit_lowering = "arm64_sysreg_read"

neon_register_model = "RDMSR is a privileged x86 MSR read instruction. No ARM64 NEON equivalent."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDMSR stub"
neon_notes = ["RDMSR reads an MSR specified by ECX into EDX:EAX.", "Privileged instruction (CPL=0 required)."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
