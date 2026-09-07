// SUB/PSUBSW.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/PSUBSW.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBSW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/PSUBSW.inc"
x86_handler = "x86_psubsw"
neon_lowering = "arm64_neon_subs_w"
lowering_kind = "neon_vector"


name = "PSUBSW"
category = "simd_integer_subtract"
feature = "MMX"
element_type = "i16"
legacy_width = 64
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = false

encodings = [
  { opcode = "NP 0F E9 /r", form = "PSUBSW mm1, mm2/m64", op_en = "A", feature = "MMX", mode = "V/V", handler = "arm64_sqsub_vd8h_vn8h_vm8h" },
  { opcode = "66 0F E9 /r", form = "PSUBSW xmm1, xmm2/m128", op_en = "A", feature = "SSE2", mode = "V/V", handler = "arm64_sqsub_vd8h_vn8h_vm8h" },
  { opcode = "VEX.128.66.0F.WIG E9 /r", form = "VPSUBSW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "arm64_sqsub_vd8h_vn8h_vm8h" },
  { opcode = "VEX.256.66.0F.WIG E9 /r", form = "VPSUBSW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", mode = "V/V", handler = "arm64_sqsub_vd8h_vn8h_vm8h" },
  { opcode = "EVEX.128.66.0F.WIG E9 /r", form = "VPSUBSW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "arm64_sqsub_vd8h_vn8h_vm8h" },
  { opcode = "EVEX.256.66.0F.WIG E9 /r", form = "VPSUBSW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "arm64_sqsub_vd8h_vn8h_vm8h" },
  { opcode = "EVEX.512.66.0F.WIG E9 /r", form = "VPSUBSW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", tuple = "Full", handler = "arm64_sqsub_vd8h_vn8h_vm8h" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
for lane in 0..8:
    DEST.i16[lane] = signed_saturate(SRC1.i16[lane] - SRC2.i16[lane], 16);
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_psubsw"
jit_lowering = "arm64_neon_subs_w"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
Integer saturation flags are preserved through Rosette SIMD integer side-effect handlers.
"""

neon_assembly = """
sqsub vD.8h, vN.8h, vM.8h
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON SQSUB Vd.8H matches x86 PSUBSW behavior (signed saturating 16-bit subtraction).",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
