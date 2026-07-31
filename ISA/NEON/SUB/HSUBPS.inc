// SUB/HSUBPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/HSUBPS.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
HSUBPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_horizontal_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/HSUBPS.inc"
x86_handler = "x86_hsubps"
neon_lowering = "arm64_neon_hsub_ps"
lowering_kind = "neon_vector"


name = "HSUBPS"
category = "simd_float_horizontal_subtract"
feature = "SSE3"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8
mxcsr_used = true

encodings = [
  { opcode = "F2 0F 7D /r", form = "HSUBPS xmm1, xmm2/m128", op_en = "RM", feature = "SSE3", mode = "V/V", handler = "x86_hsubps_xmm_xmmm128" },
  { opcode = "VEX.128.F2.0F.WIG 7D /r", form = "VHSUBPS xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vhsubps_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.F2.0F.WIG 7D /r", form = "VHSUBPS ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vhsubps_ymm_ymm_ymmm256" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
DEST[31:0] = SRC1[63:32] - SRC1[31:0];
DEST[63:32] = SRC1[127:96] - SRC1[95:64];
DEST[95:64] = SRC2[63:32] - SRC2[31:0];
DEST[127:96] = SRC2[127:96] - SRC2[95:64];
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = []

handler = "x86_hsubps"
jit_lowering = "arm64_neon_fhsub_ps"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fhsub vD.4s, vN.4s, vM.4s
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
