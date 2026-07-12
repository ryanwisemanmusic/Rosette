// PERMUTE/VPERM2F128.inc
// ARM64/NEON translation mirror generated from ISA/x86/PERMUTE/VPERM2F128.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPERM2F128: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_permute_128_lane.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERMUTE/VPERM2F128.inc"
x86_handler = "x86_vperm2f128"
neon_lowering = "arm64_neon_ext_imm8"
lowering_kind = "neon_vector"


name = "VPERM2F128"
category = "simd_float_permute_128_lane"
feature = "AVX"
element_type = "f32"
legacy_width = 256
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8
mxcsr_used = true

encodings = [
  { opcode = "0E 00 00 00 EXT Vd.16B, Vn.16B, Vm.16B, #8", form = "VPERM2F128 Vd.2D, Vn.2D, Vm.2D, #imm", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_ext_imm8" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "imm8 (r)" }
]

semantic_legacy = """
DEST[127:0] = (imm8[0]==0) ? SRC1[127:0] : (imm8[4:1]==1) ? SRC1[255:128] : (imm8[4:1]==2) ? SRC2[127:0] : 0;
DEST[255:128] = (imm8[0]==0) ? SRC2[127:0] : (imm8[4:1]==1) ? SRC2[255:128] : (imm8[4:1]==2) ? SRC1[127:0] : 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_vex_256 = """
DEST[127:0] = (imm8[0]==0) ? SRC1[127:0] : (imm8[4:1]==1) ? SRC1[255:128] : (imm8[4:1]==2) ? SRC2[127:0] : 0;
DEST[255:128] = (imm8[0]==0) ? SRC2[127:0] : (imm8[4:1]==1) ? SRC2[255:128] : (imm8[4:1]==2) ? SRC1[127:0] : 0;
DEST[MAXVL-1:256] = 0;
"""

simd_fp_exceptions = ["invalid", "denormal"]
other_exceptions = ["VEX Type 4 class exceptions"]

handler = "x86_vperm2f128"
jit_lowering = "arm64_neon_ext_imm8"


neon_register_model = """
x86 ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
ext vD.16b, vN.16b, vM.16b, #8
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "EXT with #8 concatenates the lower half of Vm with the upper half of Vn, approximating 128-bit lane permutation."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
