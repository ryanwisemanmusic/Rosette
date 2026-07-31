// SUB/PHSUBSW.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/PHSUBSW.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PHSUBSW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_horizontal_subtract_saturate.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/PHSUBSW.inc"
x86_handler = "x86_phsubsw"
neon_lowering = "arm64_neon_hsub_sw"
lowering_kind = "neon_vector"


name = "PHSUBSW"
category = "simd_integer_horizontal_subtract_saturate"
feature = "SSSE3"
element_type = "i16"
legacy_width = 64
lanes_128 = 8
lanes_256 = 16
mxcsr_used = false

encodings = [
  { opcode = "NP 0F 38 07 /r", form = "PHSUBSW mm1, mm2/m64", op_en = "RM", feature = "SSSE3", mode = "V/V", handler = "x86_phsubsw_mm_mmm64" },
  { opcode = "66 0F 38 07 /r", form = "PHSUBSW xmm1, xmm2/m128", op_en = "RM", feature = "SSSE3", mode = "V/V", handler = "x86_phsubsw_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F38.WIG 07 /r", form = "VPHSUBSW xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vphsubsw_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F38.WIG 07 /r", form = "VPHSUBSW ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", mode = "V/V", handler = "x86_vphsubsw_ymm_ymm_ymmm256" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
for lane in 0..8:
    DEST.i16[lane] = signed_saturate(SRC1.i16[lane*2] - SRC1.i16[lane*2+1], 16);
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_phsubsw"
jit_lowering = "arm64_neon_hsub_sw"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
Integer saturation flags are preserved through Rosette SIMD integer side-effect handlers.
"""

neon_assembly = """
shsub vD.8b, vN.8b, vM.8b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON SHSUB with saturation is used as NEON lowering for PHSUBSW.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
