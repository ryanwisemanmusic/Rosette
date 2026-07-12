// PERMUTE/VPERMD.inc
// ARM64/NEON translation mirror generated from ISA/x86/PERMUTE/VPERMD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPERMD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_int_permute_dword.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERMUTE/VPERMD.inc"
x86_handler = "x86_vpermd"
neon_lowering = "arm64_neon_tbl2"
lowering_kind = "neon_vector"


name = "VPERMD"
category = "simd_int_permute_dword"
feature = "AVX2"
element_type = "i32"
legacy_width = 256
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16
mxcsr_used = false

encodings = [
  { opcode = "0E 00 00 00 TBL Vd.16B, {Vn.16B-Vn.4S}, Vm.16B", form = "VPERMD Vd.4S, Vn.4S, Vm.4S", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_tbl2" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.dword[0] = SRC2.dword[0] < 8 ? SRC1.dword[SRC2.dword[0]] : 0;
DEST.dword[1] = SRC2.dword[1] < 8 ? SRC1.dword[SRC2.dword[1]] : 0;
DEST.dword[2] = SRC2.dword[2] < 8 ? SRC1.dword[SRC2.dword[2]] : 0;
DEST.dword[3] = SRC2.dword[3] < 8 ? SRC1.dword[SRC2.dword[3]] : 0;
DEST.dword[4] = SRC2.dword[4] < 8 ? SRC1.dword[SRC2.dword[4]] : 0;
DEST.dword[5] = SRC2.dword[5] < 8 ? SRC1.dword[SRC2.dword[5]] : 0;
DEST.dword[6] = SRC2.dword[6] < 8 ? SRC1.dword[SRC2.dword[6]] : 0;
DEST.dword[7] = SRC2.dword[7] < 8 ? SRC1.dword[SRC2.dword[7]] : 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_vex_256 = """
DEST.dword[0] = SRC2.dword[0] < 8 ? SRC1.dword[SRC2.dword[0]] : 0;
DEST.dword[1] = SRC2.dword[1] < 8 ? SRC1.dword[SRC2.dword[1]] : 0;
DEST.dword[2] = SRC2.dword[2] < 8 ? SRC1.dword[SRC2.dword[2]] : 0;
DEST.dword[3] = SRC2.dword[3] < 8 ? SRC1.dword[SRC2.dword[3]] : 0;
DEST.dword[4] = SRC2.dword[4] < 8 ? SRC1.dword[SRC2.dword[4]] : 0;
DEST.dword[5] = SRC2.dword[5] < 8 ? SRC1.dword[SRC2.dword[5]] : 0;
DEST.dword[6] = SRC2.dword[6] < 8 ? SRC1.dword[SRC2.dword[6]] : 0;
DEST.dword[7] = SRC2.dword[7] < 8 ? SRC1.dword[SRC2.dword[7]] : 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active dword lane selected by k1 or no writemask:
    idx := SRC2.dword[i];
    DEST.dword[i] := (idx < VL/32) ? SRC1.dword[idx] : 0;
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["none"]
other_exceptions = ["VEX Type 4 class exceptions", "EVEX Type E9 class exceptions"]

handler = "x86_vpermd"
jit_lowering = "arm64_neon_tbl2"


neon_register_model = """
x86 ymm/zmm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No MXCSR interaction; integer permute is a pure integer operation.
"""

neon_assembly = """
tbl vD.16b, {vN.16b - vN.4s}, vM.16b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "NEON TBL with two source registers provides a per-byte lookup table covering 32 bytes, sufficient for 256-bit dword permute."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
