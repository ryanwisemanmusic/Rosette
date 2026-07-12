// RET/VPOPCNTB.inc
// ARM64/NEON translation mirror generated from ISA/x86/POP/VPOPCNTB.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPOPCNTB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: bitwise_count.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "POP/VPOPCNTB.inc"
x86_handler = "x86_vpopcntb"
neon_lowering = "arm64_neon_cnt_b"
lowering_kind = "neon_vector"

name = "VPOPCNTB"
category = "simd_bitwise"
feature = "AVX512_BITALG"
element_type = "u8"
legacy_width = 128
lanes_128 = 16
lanes_256 = 32
lanes_512 = 64
mxcsr_used = false

encodings = [
  { opcode = "0E 20 80 20 CNT Vd.16B, Vn.16B", form = "VPOPCNTB Vd.16B, Vn.16B", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_cnt_b" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_legacy = """
for j in 0..KL-1:
    i = j * 8;
    DEST[i+7:i] = POPCOUNT(SRC[i+7:i]);
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["Type E2 class exception conditions"]

handler = "x86_vpopcntb"
jit_lowering = "arm64_neon_cnt_b"

neon_register_model = """
x86 zmm byte lanes are mapped onto ARM64 vector registers preserving lane width.
"""

neon_flag_model = """
No x86 flags are modified by VPOPCNTB.
"""

neon_assembly = """
cnt vD.16b, vN.16b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "NEON CNT counts bits per byte, matching VPOPCNTB byte-wise popcount semantics exactly."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
