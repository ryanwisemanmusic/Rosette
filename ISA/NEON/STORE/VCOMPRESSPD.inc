// STORE/VCOMPRESSPD.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/VCOMPRESSPD.inc"
x86_handler = "x86_vcompresspd"
neon_lowering = "arm64_vcompresspd"
lowering_kind = "neon_documented_contract"

name = "VCOMPRESSPD"
category = "compress_store"
feature = "SSE2_AVX_AVX512"
element_type = "f64"
legacy_width = 128

encodings = [
  { opcode = "NEON compress store", form = "VCOMPRESSPD", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_vcompresspd" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
VCOMPRESSPD: Compress store double precision.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_vcompresspd"
jit_lowering = "arm64_vcompresspd"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: compress store"
neon_notes = ["ARM64/NEON lowering mirror for x86 VCOMPRESSPD."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
