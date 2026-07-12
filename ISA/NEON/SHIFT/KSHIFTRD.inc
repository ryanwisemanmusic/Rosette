// SHIFT/KSHIFTRD.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/KSHIFTRD.inc"
x86_handler = "x86_kshiftrd"
neon_lowering = "arm64_kshiftrd"
lowering_kind = "neon_documented_contract"

name = "KSHIFTRD"
category = "mask_shift"
feature = "AVX512BW"
element_type = "integer"
legacy_width = 0

encodings = [
  { opcode = "NEON lowering for mask shift", form = "KSHIFTRD k1, k2, imm8", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_kshiftrd" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "k1 (w)", operand2 = "k2 (r)", operand3 = "imm8", operand4 = "N/A" }
]

semantic_general = """
KSHIFTRD: Shift 32-bit mask right by immediate.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_kshiftrd"
jit_lowering = "arm64_kshiftrd"

neon_register_model = "x86 mask registers mapped to ARM64 SIMD vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: immediate mask shift lowering"
neon_notes = ["ARM64/NEON lowering mirror for x86 KSHIFTRD."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
