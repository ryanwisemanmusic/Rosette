// Mirror: INITIALIZE/FNINIT.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INITIALIZE/FNINIT.inc"
x86_handler = "x86_fninit"
neon_lowering = "arm64_fninit"
lowering_kind = "arm64_documented_contract"

name = "FNINIT"
aliases = []
category = "x87_fpu_initialize"
feature = "x87"

encodings = [
  { opcode = "DB E3", form = "FNINIT", op_en = "ZO", vector_length = 0 }
]


neon_register_model = """
FNINIT is an x87 FPU initialization instruction. No ARM64 NEON equivalent; handled via documented contract.
"""
neon_flag_model = """
C0, C1, C2, C3: set to 0.
"""
neon_assembly = """
// NEON lowering: FNINIT stub (x87 FPU initialize without exception check)
"""
semantic_general = """
Sets the FPU control, status, tag, instruction pointer, and data pointer registers to their default states.
The FNINIT instruction does not check for pending unmasked floating-point exceptions before performing the initialization.
"""
flags_written = []

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
