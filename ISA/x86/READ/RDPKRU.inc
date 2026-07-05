// READ/RDPKRU.inc
// RDPKRU — Read Protection Key Rights.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDPKRU.inc"
x86_handler = "x86_rdpkru"
neon_lowering = "arm64_documented_contract"
lowering_kind = "arm64_documented_contract"

name = "RDPKRU"
category = "system_register_read"
feature = "OSPKE"
element_type = "u32"

encodings = [
  { opcode = "NP 0F 01 EE", form = "RDPKRU", op_en = "ZO", feature = "OSPKE", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { ZO = [] }

reads = ["PKRU"]
writes = ["EAX", "EDX"]
flags_read = []
flags_written = []

semantic = """
EAX := PKRU[31:0];
EDX := PKRU[63:32];
"""

exceptions = [
  "#UD if CPUID.(EAX=07H, ECX=0):ECX.OSPKE[bit 4] = 0",
  "#UD if CR4.PKE[bit 22] = 0",
  "#UD if the LOCK prefix is used"
]

handler = "x86_rdpkru"
jit_lowering = "arm64_sysreg_read"

neon_register_model = "RDPKRU reads the PKRU protection key register. No ARM64 NEON equivalent."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDPKRU stub"
neon_notes = ["RDPKRU reads the PKRU register into EDX:EAX.", "ECX must be 0; otherwise #GP(0)."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
