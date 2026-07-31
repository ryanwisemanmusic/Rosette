// SUB/PSUBB.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/PSUBB.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/PSUBB.inc"
x86_handler = "x86_psubb"
neon_lowering = "arm64_neon_sub_b"
lowering_kind = "neon_vector"


name = "PSUBB"
category = "simd_integer_subtract"
feature = "MMX"
element_type = "i8"
legacy_width = 64
lanes_128 = 16
lanes_256 = 32
lanes_512 = 64
mxcsr_used = false

encodings = [
  { opcode = "NP 0F F8 /r", form = "PSUBB mm1, mm2/m64", op_en = "A", feature = "MMX", mode = "V/V", handler = "x86_psubb_mm_mmm64" },
  { opcode = "66 0F F8 /r", form = "PSUBB xmm1, xmm2/m128", op_en = "A", feature = "SSE2", mode = "V/V", handler = "x86_psubb_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F.WIG F8 /r", form = "VPSUBB xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vpsubb_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F.WIG F8 /r", form = "VPSUBB ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", mode = "V/V", handler = "x86_vpsubb_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.66.0F.WIG F8 /r", form = "VPSUBB xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "x86_vpsubb_evex128" },
  { opcode = "EVEX.256.66.0F.WIG F8 /r", form = "VPSUBB ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "x86_vpsubb_evex256" },
  { opcode = "EVEX.512.66.0F.WIG F8 /r", form = "VPSUBB zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", tuple = "Full", handler = "x86_vpsubb_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
for lane in 0..16:
    DEST.i8[lane] = SRC1.i8[lane] - SRC2.i8[lane];
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_psubb"
jit_lowering = "arm64_neon_sub_b"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
Integer wrap behavior is preserved by the NEON lowering (no saturation).
"""

neon_assembly = """
sub vD.16b, vN.16b, vM.16b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON SUB Vd.16B matches x86 PSUBB behavior (wrapping 8-bit subtraction).",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
