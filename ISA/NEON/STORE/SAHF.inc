// STORE/SAHF.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/SAHF.inc"
x86_handler = "x86_sahf"
neon_lowering = "arm64_sahf"
lowering_kind = "neon_documented_contract"

name = "SAHF"
category = "flag_store"
feature = "8086"
element_type = "integer"
legacy_width = 0

encodings = [
  { opcode = "ARM64 flag_load", form = "SAHF", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_sahf" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "N/A", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
SAHF: Loads SF, ZF, AF, PF, and CF flags from AH register.
"""

flags_written = ["SF", "ZF", "AF", "PF", "CF"]
simd_fp_exceptions = []

handler = "x86_sahf"
jit_lowering = "arm64_sahf"

neon_register_model = "x86 GP registers mapped to ARM64 X registers."
neon_flag_model = "SF, ZF, AF, PF, CF loaded from AH bits via ARM64 flag synthesis."
neon_assembly = "// ARM64: flag load from X register"
neon_notes = ["ARM64/NEON lowering mirror for x86 SAHF."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
