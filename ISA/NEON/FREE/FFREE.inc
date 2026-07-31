// Mirror: FREE/FFREE.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FREE/FFREE.inc"
x86_handler = "x86_ffree"
neon_lowering = "arm64_ffree"
lowering_kind = "arm64_documented_contract"

name = "FFREE"
aliases = []
category = "x87_fpu_register_tag"
feature = "x87"

encodings = [
  { opcode = "DD C0+i", form = "FFREE ST(i)", op_en = "A", vector_length = 0 }
]


neon_register_model = """
FFREE is an x87 FPU register tag manipulation instruction.
No ARM64 NEON equivalent; handled via documented contract.
"""
neon_flag_model = """
C0, C1, C2, C3: undefined.
"""
neon_assembly = """
// NEON lowering: FFREE stub (x87 FPU free register)
"""
semantic_general = """
Sets the tag in the FPU tag register associated with register ST(i) to empty (11B).
The contents of ST(i) and the FPU stack-top pointer (TOP) are not affected.
"""
flags_written = []

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
