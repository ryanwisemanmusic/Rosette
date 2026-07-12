// SHIFT/KSHIFTLB.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/KSHIFTLB.inc"
x86_handler = "x86_kshiftlb"
neon_lowering = "arm64_kshiftlb"
lowering_kind = "neon_documented_contract"

name = "KSHIFTLB"
category = "mask_shift"
feature = "AVX512DQ"
element_type = "integer"
legacy_width = 0

encodings = [
  { opcode = "NEON lowering for mask shift", form = "KSHIFTLB k1, k2, imm8", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_kshiftlb" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "k1 (w)", operand2 = "k2 (r)", operand3 = "imm8", operand4 = "N/A" }
]

semantic_general = """
KSHIFTLB: Shift 8-bit mask left by immediate.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_kshiftlb"
jit_lowering = "arm64_kshiftlb"

neon_register_model = "x86 mask registers mapped to ARM64 SIMD vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: immediate mask shift lowering"
neon_notes = ["ARM64/NEON lowering mirror for x86 KSHIFTLB."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
