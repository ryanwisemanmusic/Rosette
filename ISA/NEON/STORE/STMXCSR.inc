// STORE/STMXCSR.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/STMXCSR.inc"
x86_handler = "x86_stmxcsr"
neon_lowering = "arm64_stmxcsr"
lowering_kind = "neon_documented_contract"

name = "STMXCSR"
category = "system_store"
feature = "SSE_AVX"
element_type = "integer"
legacy_width = 32

encodings = [
  { opcode = "ARM64 mrs_fpcr_fpsr", form = "STMXCSR", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_stmxcsr" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "memory (w)", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
STMXCSR/VSTMXCSR: Stores MXCSR to 32-bit memory.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_stmxcsr"
jit_lowering = "arm64_stmxcsr"

neon_register_model = "x86 MXCSR mapped to ARM64 FPCR/FPSR."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: MRS FPCR/FPSR"
neon_notes = ["ARM64/NEON lowering mirror for x86 STMXCSR."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
