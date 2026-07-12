// UNPACK/KUNPCKBW.inc
// ARM64/NEON translation mirror generated from ISA/x86/UNPACK/KUNPCKBW.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
KUNPCKBW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: mask_unpack.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNPACK/KUNPCKBW.inc"
x86_handler = "x86_kunpckbw"
neon_lowering = "arm64_neon_zip"
lowering_kind = "neon_vector"


name = "KUNPCKBW"
category = "mask_unpack"
feature = "AVX512F"
element_type = "u8"

encodings = [
  { opcode = "0E 30 80 20 ZIP Vd.16B, Vn.16B, Vm.16B", form = "KUNPCKBW k1, k2, k3", op_en = "RVR", feature = "AVX512F", mode = "V/V", handler = "arm64_neon_zip" }
]

operand_encodings = [
  { op_en = "RVR", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.1vvv (r)", operand3 = "ModRM:r/m (r, ModRM:[7:6] must be 11b)", operand4 = "N/A" }
]

semantic_general = """
Interleave 8-bit mask elements from k2 and k3 into 16-bit elements in k1.
k1[7:0] = k2[7:0], k1[15:8] = k3[7:0], etc.
Upper bits of k1 zeroed.
"""

simd_fp_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 (VEX-Encoded OpMask Instructions w/o Memory Arg)"]

handler = "x86_kunpckbw"
jit_lowering = "arm64_neon_zip"


neon_register_model = """
x86 mask registers k1/k2/k3 are mapped onto ARM64 v registers; the ZIP operation interleaves bytes.
"""

neon_flag_model = """
No flags affected.
"""

neon_assembly = """
zip vD.16b, vN.16b, vM.16b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
