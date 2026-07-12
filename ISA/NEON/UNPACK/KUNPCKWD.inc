// UNPACK/KUNPCKWD.inc
// ARM64/NEON translation mirror generated from ISA/x86/UNPACK/KUNPCKWD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
KUNPCKWD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: mask_unpack.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNPACK/KUNPCKWD.inc"
x86_handler = "x86_kunpckwd"
neon_lowering = "arm64_neon_zip"
lowering_kind = "neon_vector"


name = "KUNPCKWD"
category = "mask_unpack"
feature = "AVX512BW"
element_type = "u16"

encodings = [
  { opcode = "0E 30 80 40 ZIP Vd.8H, Vn.8H, Vm.8H", form = "KUNPCKWD k1, k2, k3", op_en = "RVR", feature = "AVX512BW", mode = "V/V", handler = "arm64_neon_zip" }
]

operand_encodings = [
  { op_en = "RVR", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.1vvv (r)", operand3 = "ModRM:r/m (r, ModRM:[7:6] must be 11b)", operand4 = "N/A" }
]

semantic_general = """
Interleave 16-bit mask elements from k2 and k3 into 32-bit elements in k1.
k1[15:0] = k2[15:0], k1[31:16] = k3[15:0], etc.
Upper bits of k1 zeroed.
"""

simd_fp_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 (VEX-Encoded OpMask Instructions w/o Memory Arg)"]

handler = "x86_kunpckwd"
jit_lowering = "arm64_neon_zip"


neon_register_model = """
x86 mask registers k1/k2/k3 are mapped onto ARM64 v registers; the ZIP operation interleaves halfwords.
"""

neon_flag_model = """
No flags affected.
"""

neon_assembly = """
zip vD.8h, vN.8h, vM.8h
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
