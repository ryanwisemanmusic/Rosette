// RANGE/VRANGEPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/RANGE/VRANGEPD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VRANGEPD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_range.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RANGE/VRANGEPD.inc"
x86_handler = "x86_vrangepd"
neon_lowering = "arm64_vrangepd"
lowering_kind = "arm64_documented_contract"


name = "VRANGEPD"
aliases = []
category = "simd_float_range"
feature = "AVX512F"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F3A.W1 50 /r ib", form = "VRANGEPD xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst, imm8", op_en = "C", feature = "AVX512F", vector_length = 128, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.256.66.0F3A.W1 50 /r ib", form = "VRANGEPD ymm1{k1}{z}, ymm2, ymm3/m256/m64bcst, imm8", op_en = "C", feature = "AVX512F", vector_length = 256, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.512.66.0F3A.W1 50 /r ib", form = "VRANGEPD zmm1{k1}{z}, zmm2, zmm3/m512/m64bcst, sae, imm8", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

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
(KL, VL) = (2,128), (4,256), or (8,512);
for j in 0..KL-1:
    i = j * 64;
    if k1[j] == 1 or no_writemask:
        if EVEX.b == 1 and SRC2_is_memory:
            SRC2_lane = SRC2[63:0];
        else:
            SRC2_lane = SRC2[i+63:i];
        DEST[i+63:i] = range_restrict(SRC1[i+63:i], SRC2_lane, imm8[1:0], imm8[2]);
    else if zeroing_masking:
        DEST[i+63:i] = 0;
    else:
        DEST[i+63:i] unchanged;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vrangepd"
jit_lowering = "arm64_vrangepd"
fallback = "zig_lane_loop_range_pd"

neon_register_model = """
x86 xmm/ymm/zmm f64 lanes are mapped onto ARM64 v registers; each lane yields a range-restricted f64 result per the imm8 control byte.
"""

neon_flag_model = """
No x86 flags are modified; MXCSR invalid/denormal exception status is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON does not provide a direct range-restriction instruction.
// The lowering implements range_restrict(SRC1, SRC2, imm8[1:0], imm8[2]) as:
//   cmp with sign based on imm8[2] via fmax/fmin with conditional select
// For imm8[1:0] = 0 (LOW):  fmin vT.2d, vN.2d, vM.2d
// For imm8[1:0] = 1 (HIGH): fmax vT.2d, vN.2d, vM.2d
// For imm8[1:0] = 2 (MIN_LOW):  fmin followed by fmin with swapped src
// For imm8[1:0] = 3 (MAX_HIGH): fmax followed by fmax with swapped src
// imm8[2]: 0=signed, 1=unsigned (affects NaN sign handling)
//     bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "VRANGEPD uses EVEX.V' (high-16 register) encoding; the ARM64 lowering must preserve the full 5-bit register space."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
