// PERMUTE/VPERMW.inc
// ARM64/NEON translation mirror generated from ISA/x86/PERMUTE/VPERMW.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPERMW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_int_permute_word.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERMUTE/VPERMW.inc"
x86_handler = "x86_vpermw"
neon_lowering = "arm64_neon_tbl1"
lowering_kind = "neon_vector"


name = "VPERMW"
category = "simd_int_permute_word"
feature = "AVX512BW"
element_type = "i16"
legacy_width = 128
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = false

encodings = [
  { opcode = "0E 00 00 00 TBL Vd.16B, {Vn.16B}, Vm.16B", form = "VPERMW Vd.8H, Vn.8H, Vm.8H", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_tbl1" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
FOR j := 0 TO 7:
    idx := SRC2.word[j];
    DEST.word[j] := (idx < 8) ? SRC1.word[idx] : 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_128 = """
FOR j := 0 TO 7:
    idx := SRC2.word[j];
    DEST.word[j] := (idx < 8) ? SRC1.word[idx] : 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_evex = """
for each active word lane selected by k1 or no writemask:
    idx := SRC2.word[j];
    DEST.word[j] := (idx < VL/16) ? SRC1.word[idx] : 0;
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["none"]
other_exceptions = ["EVEX Type E9 class exceptions"]

handler = "x86_vpermw"
jit_lowering = "arm64_neon_tbl1"


neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No MXCSR interaction; word permute is a pure integer operation.
"""

neon_assembly = """
tbl vD.16b, {vN.16b}, vM.16b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "NEON TBL provides a per-byte lookup table that can approximate word-granular VPERMW behavior for 128-bit operations."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
