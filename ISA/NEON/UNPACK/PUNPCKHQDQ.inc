// UNPACK/PUNPCKHQDQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/UNPACK/PUNPCKHQDQ.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PUNPCKHQDQ: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_unpack_high.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNPACK/PUNPCKHQDQ.inc"
x86_handler = "x86_punpckhqdq"
neon_lowering = "arm64_neon_zip_high_d"
lowering_kind = "neon_vector"


name = "PUNPCKHQDQ"
category = "simd_integer_unpack_high"
feature = "SSE2"
element_type = "i64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8
mxcsr_used = false

encodings = [
  { opcode = "0E 30 80 80 ZIP2 Vd.2D, Vn.2D, Vm.2D", form = "PUNPCKHQDQ Vd.2D, Vn.2D, Vm.2D", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_zip_high_d" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.i64[0] = DEST.i64[1];
DEST.i64[1] = SRC.i64[1];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.i64[0] = SRC1.i64[1];
DEST.i64[1] = SRC2.i64[1];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.i64[0] = SRC1.i64[1];
DEST.i64[1] = SRC2.i64[1];
DEST.i64[2] = SRC1.i64[3];
DEST.i64[3] = SRC2.i64[3];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active i64 lane group selected by k1 or no writemask:
    DEST[i * 2 + 0] = SRC1[VL/2 + i];
    DEST[i * 2 + 1] = SRC2[VL/2 + i_or_broadcast];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["Non-EVEX: Type 4 class exceptions", "EVEX: Type E4 class exceptions"]

handler = "x86_punpckhqdq"
jit_lowering = "arm64_neon_zip_high_d"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags affected.
"""

neon_assembly = """
zip2 vD.2d, vN.2d, vM.2d
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
