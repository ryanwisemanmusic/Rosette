// SUB/PSUBSB.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/PSUBSB.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBSB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/PSUBSB.inc"
x86_handler = "x86_psubsb"
neon_lowering = "arm64_neon_subs_b"
lowering_kind = "neon_vector"


name = "PSUBSB"
category = "simd_integer_subtract"
feature = "MMX"
element_type = "i8"
legacy_width = 64
lanes_128 = 16
lanes_256 = 32
lanes_512 = 64
mxcsr_used = false

encodings = [
  { opcode = "NP 0F E8 /r", form = "PSUBSB mm1, mm2/m64", op_en = "A", feature = "MMX", mode = "V/V", handler = "arm64_sqsub_vd16b_vn16b_vm16b" },
  { opcode = "66 0F E8 /r", form = "PSUBSB xmm1, xmm2/m128", op_en = "A", feature = "SSE2", mode = "V/V", handler = "arm64_sqsub_vd16b_vn16b_vm16b" },
  { opcode = "VEX.128.66.0F.WIG E8 /r", form = "VPSUBSB xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "arm64_sqsub_vd16b_vn16b_vm16b" },
  { opcode = "VEX.256.66.0F.WIG E8 /r", form = "VPSUBSB ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", mode = "V/V", handler = "arm64_sqsub_vd16b_vn16b_vm16b" },
  { opcode = "EVEX.128.66.0F.WIG E8 /r", form = "VPSUBSB xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "arm64_sqsub_vd16b_vn16b_vm16b" },
  { opcode = "EVEX.256.66.0F.WIG E8 /r", form = "VPSUBSB ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "arm64_sqsub_vd16b_vn16b_vm16b" },
  { opcode = "EVEX.512.66.0F.WIG E8 /r", form = "VPSUBSB zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", tuple = "Full", handler = "arm64_sqsub_vd16b_vn16b_vm16b" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
for lane in 0..16:
    DEST.i8[lane] = signed_saturate(SRC1.i8[lane] - SRC2.i8[lane], 8);
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_psubsb"
jit_lowering = "arm64_neon_subs_b"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
Integer saturation flags are preserved through Rosette SIMD integer side-effect handlers.
"""

neon_assembly = """
sqsub vD.16b, vN.16b, vM.16b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON SQSUB Vd.16B matches x86 PSUBSB behavior (signed saturating 8-bit subtraction).",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
