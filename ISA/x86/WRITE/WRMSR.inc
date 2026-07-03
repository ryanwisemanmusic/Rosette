// WRITE/WRMSR.inc
// WRMSR — Write to Model Specific Register.

name = "WRMSR"
category = "system"
feature = "x86_system"
element_type = "none"

encodings = [
  { opcode = "0F 30", form = "WRMSR", op_en = "ZO", feature = "x86_system", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { ZO = [] }

reads = ["ECX", "EDX", "EAX"]
writes = ["MSR[ECX]"]
flags_read = []
flags_written = []

semantic = """
MSR[ECX] := EDX:EAX;
"""

exceptions = [
  "#GP(0) if current privilege level is not 0",
  "#GP(0) if reserved MSR address in ECX",
  "#GP(0) if reserved bits set in EDX:EAX",
  "#GP(0) if non-canonical address for certain MSRs",
  "#UD if LOCK prefix is used"
]

handler = "x86_wrmsr"
jit_lowering = "arm64_sysreg_write"

neon_register_model = "WRMSR is a privileged system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WRMSR stub"
neon_notes = ["WRMSR writes EDX:EAX to MSR indexed by ECX.", "ARM64: MSR write to system register."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
