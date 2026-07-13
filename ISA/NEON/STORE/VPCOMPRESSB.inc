// STORE/VPCOMPRESSB.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/VPCOMPRESSB.inc"
x86_handler = "x86_vpcompressb"
neon_lowering = "arm64_vpcompressb"
lowering_kind = "neon_documented_contract"

name = "VPCOMPRESSB"
category = "compress_store"
feature = "SSE2_AVX_AVX512"
element_type = "integer"
legacy_width = 128

encodings = [
  { opcode = "NEON compress store", form = "VPCOMPRESSB", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_vpcompressb" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
VPCOMPRESSB: Compress store bytes.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_vpcompressb"
jit_lowering = "arm64_vpcompressb"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: compress store"
neon_notes = ["ARM64/NEON lowering mirror for x86 VPCOMPRESSB."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
