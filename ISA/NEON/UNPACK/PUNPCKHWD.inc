// UNPACK/PUNPCKHWD.inc
// ARM64/NEON translation mirror generated from ISA/x86/UNPACK/PUNPCKHWD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PUNPCKHWD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_unpack_high.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNPACK/PUNPCKHWD.inc"
x86_handler = "x86_punpckhwd"
neon_lowering = "arm64_neon_zip_high_h"
lowering_kind = "neon_vector"


name = "PUNPCKHWD"
category = "simd_integer_unpack_high"
feature = "MMX"
element_type = "i16"
legacy_width = 64
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = false

encodings = [
  { opcode = "0E 30 80 40 ZIP2 Vd.8H, Vn.8H, Vm.8H", form = "PUNPCKHWD Vd.8H, Vn.8H, Vm.8H", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_zip_high_h" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
for lane in 0..2:
    DEST.i16[lane] = DEST.i16[lane + 4];
    DEST.i16[lane + 2] = SRC.i16[lane + 4];
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex_128 = """
for lane in 0..4:
    DEST.i16[lane * 2] = SRC1.i16[lane + 4];
    DEST.i16[lane * 2 + 1] = SRC2.i16[lane + 4];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..8:
    DEST.i16[lane * 2] = SRC1.i16[lane + 8];
    DEST.i16[lane * 2 + 1] = SRC2.i16[lane + 8];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active i16 lane group selected by k1 or no writemask:
    DEST[i * 2 + 0] = SRC1[VL/2 + i];
    DEST[i * 2 + 1] = SRC2[VL/2 + i];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["Non-EVEX: Type 4 class exceptions", "EVEX: Type E4 class exceptions"]

handler = "x86_punpckhwd"
jit_lowering = "arm64_neon_zip_high_h"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags affected.
"""

neon_assembly = """
zip2 vD.8h, vN.8h, vM.8h
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
