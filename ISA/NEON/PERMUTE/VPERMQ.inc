// PERMUTE/VPERMQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/PERMUTE/VPERMQ.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPERMQ: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_int_permute_quadword.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERMUTE/VPERMQ.inc"
x86_handler = "x86_vpermq"
neon_lowering = "arm64_neon_tbl1"
lowering_kind = "neon_vector"


name = "VPERMQ"
category = "simd_int_permute_quadword"
feature = "AVX2"
element_type = "i64"
legacy_width = 256
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8
mxcsr_used = false

encodings = [
  { opcode = "0E 30 80 80 TBL Vd.2D, {Vn.2D}, Vm.2D", form = "VPERMQ Vd.2D, Vn.2D, Vm.2D", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_tbl1" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.qword[0] = (imm8[1:0]==0) ? SRC.qword[0] : (imm8[1:0]==1) ? SRC.qword[1] : (imm8[1:0]==2) ? SRC.qword[2] : SRC.qword[3];
DEST.qword[1] = (imm8[3:2]==0) ? SRC.qword[0] : (imm8[3:2]==1) ? SRC.qword[1] : (imm8[3:2]==2) ? SRC.qword[2] : SRC.qword[3];
DEST.qword[2] = (imm8[5:4]==0) ? SRC.qword[0] : (imm8[5:4]==1) ? SRC.qword[1] : (imm8[5:4]==2) ? SRC.qword[2] : SRC.qword[3];
DEST.qword[3] = (imm8[7:6]==0) ? SRC.qword[0] : (imm8[7:6]==1) ? SRC.qword[1] : (imm8[7:6]==2) ? SRC.qword[2] : SRC.qword[3];
DEST[MAXVL-1:256] = 0;
"""

semantic_vex_256 = """
DEST.qword[0] = (imm8[1:0]==0) ? SRC1.qword[0] : (imm8[1:0]==1) ? SRC1.qword[1] : (imm8[1:0]==2) ? SRC1.qword[2] : SRC1.qword[3];
DEST.qword[1] = (imm8[3:2]==0) ? SRC1.qword[0] : (imm8[3:2]==1) ? SRC1.qword[1] : (imm8[3:2]==2) ? SRC1.qword[2] : SRC1.qword[3];
DEST.qword[2] = (imm8[5:4]==0) ? SRC1.qword[0] : (imm8[5:4]==1) ? SRC1.qword[1] : (imm8[5:4]==2) ? SRC1.qword[2] : SRC1.qword[3];
DEST.qword[3] = (imm8[7:6]==0) ? SRC1.qword[0] : (imm8[7:6]==1) ? SRC1.qword[1] : (imm8[7:6]==2) ? SRC1.qword[2] : SRC1.qword[3];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active qword lane selected by k1 or no writemask:
    DEST.qword[i] = SRC1.qword[imm8[i*2+1:i*2]];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["none"]
other_exceptions = ["VEX Type 4 class exceptions", "EVEX Type E9 class exceptions"]

handler = "x86_vpermq"
jit_lowering = "arm64_neon_tbl1"


neon_register_model = """
x86 ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No MXCSR interaction; integer permute is a pure integer operation.
"""

neon_assembly = """
tbl vD.2d, {vN.2d}, vM.2d
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "NEON TBL on 2D registers provides a per-64-bit-element lookup across the 256-bit vector for cross-lane quadword permute."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
