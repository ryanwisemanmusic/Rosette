// SHIFT/PSRAW.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/PSRAW.inc"
x86_handler = "x86_psraw"
neon_lowering = "arm64_psraw"
lowering_kind = "neon_documented_contract"

name = "PSRAW"
category = "packed_shift"
feature = "MMX_SSE2_AVX_AVX512"
element_type = "integer"
legacy_width = 128

encodings = [
  { opcode = "NEON: SSHR", form = "PSRAW Vd, Vn, Vm", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_psraw" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_general = """
PSRAW: Shift packed words right arithmetic by count.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_psraw"
jit_lowering = "arm64_psraw"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: SSHR or immediate arithmetic shift right"
neon_notes = ["ARM64/NEON lowering mirror for x86 PSRAW."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
