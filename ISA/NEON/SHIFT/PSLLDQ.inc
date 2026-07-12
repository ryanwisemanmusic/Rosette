// SHIFT/PSLLDQ.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/PSLLDQ.inc"
x86_handler = "x86_pslldq"
neon_lowering = "arm64_pslldq"
lowering_kind = "neon_documented_contract"

name = "PSLLDQ"
category = "packed_shift"
feature = "SSE2_AVX_AVX512BW"
element_type = "integer"
legacy_width = 128

encodings = [
  { opcode = "NEON: EXT #imm", form = "PSLLDQ Vd, Vn, Vm", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_pslldq" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_general = """
PSLLDQ: Shift packed double quadword left by imm8 bytes.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_pslldq"
jit_lowering = "arm64_pslldq"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: EXT or shift-left by bytes"
neon_notes = ["ARM64/NEON lowering mirror for x86 PSLLDQ."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
