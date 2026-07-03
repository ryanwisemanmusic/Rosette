// WRITE/WRPKRU.inc
// WRPKRU — Write Data to User Page Key Register.

name = "WRPKRU"
category = "system"
feature = "OSPKE"
element_type = "none"

encodings = [
  { opcode = "NP 0F 01 EF", form = "WRPKRU", op_en = "ZO", feature = "OSPKE", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { ZO = [] }

reads = ["EAX", "ECX", "EDX"]
writes = ["PKRU"]
flags_read = []
flags_written = []

semantic = """
IF (ECX = 0 AND EDX = 0)
    THEN PKRU := EAX;
    ELSE #GP(0);
FI;
"""

exceptions = [
  "#GP(0) if ECX != 0",
  "#GP(0) if EDX != 0",
  "#UD if LOCK prefix is used",
  "#UD if CR4.PKE = 0"
]

handler = "x86_wrpkru"
jit_lowering = "arm64_sysreg_write"

neon_register_model = "WRPKRU is a system instruction for PKRU register update. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WRPKRU stub"
neon_notes = ["WRPKRU writes EAX into PKRU when ECX=EDX=0.", "ARM64: no direct PKRU equivalent."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
