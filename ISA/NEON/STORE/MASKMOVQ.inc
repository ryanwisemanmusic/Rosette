// STORE/MASKMOVQ.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/MASKMOVQ.inc"
x86_handler = "x86_maskmovq"
neon_lowering = "arm64_maskmovq"
lowering_kind = "neon_documented_contract"

name = "MASKMOVQ"
category = "masked_store"
feature = "SSE2_AVX_AVX512"
element_type = "integer"
legacy_width = 64

encodings = [
  { opcode = "NEON masked store", form = "MASKMOVQ", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_maskmovq" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_general = """
MASKMOVQ: Masked store.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_maskmovq"
jit_lowering = "arm64_maskmovq"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: store with masking"
neon_notes = ["ARM64/NEON lowering mirror for x86 MASKMOVQ."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
