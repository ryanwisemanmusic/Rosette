// RANGE/VRANGESD.inc
// ARM64/NEON translation mirror generated from ISA/x86/RANGE/VRANGESD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VRANGESD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_scalar_float_range.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RANGE/VRANGESD.inc"
x86_handler = "x86_vrangesd"
neon_lowering = "arm64_vrangesd"
lowering_kind = "arm64_documented_contract"


name = "VRANGESD"
aliases = []
category = "simd_scalar_float_range"
feature = "AVX512F"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.LLIG.66.0F3A.W1 51 /r ib", form = "VRANGESD xmm1{k1}{z}, xmm2, xmm3/m64, sae, imm8", op_en = "C", feature = "AVX512F", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

element_size = 64
active_lane = 0
lane_type = "scalar_double_precision"

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
mxcsr_used = true

simd_fp_exceptions = [
  "invalid",
  "denormal"
]

range_control = {
  imm8_range = "0..15",
  predicates = {
    0 = "LOW (low range: [SRC1_{min}, SRC2_{max}])",
    1 = "HIGH (high range: [SRC2_{min}, SRC1_{max}])",
    2 = "MIN_LOW (signed min of low range result)",
    3 = "MAX_HIGH (signed max of high range result)"
  },
  sign_args = {
    0 = "signed_args: true",
    1 = "signed_args: false"
  }
}

semantic_general = """
if k1[0] == 1 or no_writemask:
    DEST.f64[0] = range_restrict(SRC1.f64[0], SRC2.f64[0], imm8[1:0], imm8[2]);
else if zeroing_masking:
    DEST.f64[0] = 0;

DEST[127:64] = SRC1[127:64];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_vrangesd"
jit_lowering = "arm64_vrangesd"
fallback = "zig_scalar_range_d"

neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 v registers; only the low f64 lane is range-restricted; upper lanes are preserved or zeroed per encoding.
"""

neon_flag_model = """
No x86 flags are modified; MXCSR invalid/denormal exception status is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON does not provide a direct scalar range-restriction instruction.
// The lowering implements scalar_range_restrict(SRC1.f64[0], SRC2.f64[0], imm8[1:0], imm8[2]) as:
//   fmin/fmax on d registers with conditional select
// For imm8[1:0] = 0 (LOW):  fmin dD, dN, dM
// For imm8[1:0] = 1 (HIGH): fmax dD, dN, dM
// For imm8[1:0] = 2 (MIN_LOW):  fmin followed by fmin with swapped src
// For imm8[1:0] = 3 (MAX_HIGH): fmax followed by fmax with swapped src
// imm8[2]: 0=signed, 1=unsigned (affects NaN sign handling)
//     bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
