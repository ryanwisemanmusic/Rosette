// RET/VPOPCNTQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/POP/VPOPCNTQ.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPOPCNTQ: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: bitwise_count.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "POP/VPOPCNTQ.inc"
x86_handler = "x86_vpopcntq"
neon_lowering = "arm64_neon_cnt_q"
lowering_kind = "neon_vector"

name = "VPOPCNTQ"
category = "simd_bitwise"
feature = "AVX512_VPOPCNTDQ"
element_type = "u64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8
mxcsr_used = false

encodings = [
  { opcode = "0E 20 80 80 CNT Vd.2D, Vn.2D", form = "VPOPCNTQ Vd.2D, Vn.2D", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_cnt_q" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_legacy = """
for j in 0..KL-1:
    i = j * 64;
    DEST[i+63:i] = POPCOUNT(SRC[i+7:i]) + POPCOUNT(SRC[i+15:i+8]) + POPCOUNT(SRC[i+23:i+16]) + POPCOUNT(SRC[i+31:i+24]) + POPCOUNT(SRC[i+39:i+32]) + POPCOUNT(SRC[i+47:i+40]) + POPCOUNT(SRC[i+55:i+48]) + POPCOUNT(SRC[i+63:i+56]);
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["Type E2 class exception conditions"]

handler = "x86_vpopcntq"
jit_lowering = "arm64_neon_cnt_q"

neon_register_model = """
x86 zmm qword lanes are mapped onto ARM64 vector registers preserving lane width.
"""

neon_flag_model = """
No x86 flags are modified by VPOPCNTQ.
"""

neon_assembly = """
cnt vD.2d, vN.2d
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "NEON CNT .2D provides 64-bit element popcount, matching VPOPCNTQ qword-wise semantics."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
