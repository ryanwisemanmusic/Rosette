// SUB/HSUBPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/HSUBPD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
HSUBPD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_horizontal_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/HSUBPD.inc"
x86_handler = "x86_hsubpd"
neon_lowering = "arm64_neon_hsub_pd"
lowering_kind = "neon_vector"


name = "HSUBPD"
category = "simd_float_horizontal_subtract"
feature = "SSE3"
element_type = "f64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
mxcsr_used = true

encodings = [
  { opcode = "66 0F 7D /r", form = "HSUBPD xmm1, xmm2/m128", op_en = "RM", feature = "SSE3", mode = "V/V", handler = "x86_hsubpd_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F.WIG 7D /r", form = "VHSUBPD xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vhsubpd_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F.WIG 7D /r", form = "VHSUBPD ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vhsubpd_ymm_ymm_ymmm256" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
DEST[63:0] = SRC1[127:64] - SRC1[63:0];
DEST[127:64] = SRC2[127:64] - SRC2[63:0];
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = []

handler = "x86_hsubpd"
jit_lowering = "arm64_neon_fhsub_pd"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fhsub vD.2d, vN.2d, vM.2d
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
