// STORE/VPCOMPRESSW.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/VPCOMPRESSW.inc"
x86_handler = "x86_vpcompressw"
neon_lowering = "arm64_vpcompressw"
lowering_kind = "neon_documented_contract"

name = "VPCOMPRESSW"
category = "compress_store"
feature = "SSE2_AVX_AVX512"
element_type = "integer"
legacy_width = 128

encodings = [
  { opcode = "NEON compress store", form = "VPCOMPRESSW", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_vpcompressw" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
VPCOMPRESSW: Compress store words.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_vpcompressw"
jit_lowering = "arm64_vpcompressw"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: compress store"
neon_notes = ["ARM64/NEON lowering mirror for x86 VPCOMPRESSW."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
