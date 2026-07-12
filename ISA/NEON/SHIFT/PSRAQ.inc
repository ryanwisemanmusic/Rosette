// SHIFT/PSRAQ.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/PSRAQ.inc"
x86_handler = "x86_psraq"
neon_lowering = "arm64_psraq"
lowering_kind = "neon_documented_contract"

name = "PSRAQ"
category = "packed_shift"
feature = "AVX512F"
element_type = "integer"
legacy_width = 128

encodings = [
  { opcode = "NEON: SSHR", form = "PSRAQ Vd, Vn, Vm", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_psraq" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_general = """
PSRAQ: Shift packed quadwords right arithmetic by count.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_psraq"
jit_lowering = "arm64_psraq"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: SSHR or immediate arithmetic shift right"
neon_notes = ["ARM64/NEON lowering mirror for x86 PSRAQ."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
