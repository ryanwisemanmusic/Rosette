// ADD/KADDW.inc
// ARM64/NEON translation mirror generated from ISA/x86/ADD/KADDW.inc.
// Source contract: KADDW — ADD Two 16-bit Masks.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
KADDW: add two 16-bit opmask registers.
Category: mask_arithmetic.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ADD/KADDW.inc"
x86_handler = "x86_kaddw"
neon_lowering = "arm64_kadd_simd"
lowering_kind = "arm64_scalar"

name = "KADDW"
category = "mask_arithmetic"
feature = "AVX512DQ"
element_type = "u16"
legacy_width = 0

encodings = [
  { opcode = "VEX.L1.0F.W0 4A /r", form = "KADDW k1, k2, k3", op_en = "RVR", feature = "AVX512DQ" }
]

operand_encodings = [
  { op_en = "RVR", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.1vvv (r)", operand3 = "ModRM:r/m (r, ModRM:[7:6] must be 11b)", operand4 = "N/A" }
]

semantic_general = """
DEST[15:0] = SRC1[15:0] + SRC2[15:0];
DEST[MAX_KL-1:16] = 0;
"""

handler = "x86_kaddw"
jit_lowering = "arm64_kadd_simd"

neon_register_model = """
x86 opmask registers (k0-k7) mapped to ARM64 Vn or general-purpose registers.
"""

neon_flag_model = """
No x86 flags modified by KADDW.
"""

neon_assembly = """
// NEON lowering: add for mask addition
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
