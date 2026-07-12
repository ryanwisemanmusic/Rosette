// SHIFT/PSRLQ.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/PSRLQ.inc"
x86_handler = "x86_psrlq"
neon_lowering = "arm64_psrlq"
lowering_kind = "neon_documented_contract"

name = "PSRLQ"
category = "packed_shift"
feature = "MMX_SSE2_AVX_AVX512"
element_type = "integer"
legacy_width = 128

encodings = [
  { opcode = "NEON: USHR", form = "PSRLQ Vd, Vn, Vm", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_psrlq" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_general = """
PSRLQ: Shift packed quadwords right logical by count.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_psrlq"
jit_lowering = "arm64_psrlq"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: USHR or immediate logical shift right"
neon_notes = ["ARM64/NEON lowering mirror for x86 PSRLQ."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
