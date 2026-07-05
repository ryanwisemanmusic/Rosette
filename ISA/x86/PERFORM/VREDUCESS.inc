// PERFORM/VREDUCESS.inc
// ARM64/NEON translation mirror generated from ISA/x86/PERFORM/VREDUCESS.inc.
// Source contract: VREDUCESS — Perform Reduction Transformation on Scalar Float32 Value.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VREDUCESS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_arithmetic.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERFORM/VREDUCESS.inc"
x86_handler = "x86_vreducess"
neon_lowering = "arm64_vreducess"
lowering_kind = "arm64_documented_contract"

name = "VREDUCESS"
aliases = []
category = "simd_arithmetic"
feature = "AVX512DQ"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.LLIG.66.0F3A.W0 57 /r ib", form = "VREDUCESS xmm1 {k1}{z}, xmm2, xmm3/m32{sae}, imm8", op_en = "B", feature = "AVX512DQ", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  B = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

flags_written = []
simd_fp_exceptions = ["Invalid", "Precision"]
other_exceptions = [
  "See Table 2-46, Type E2 Class Exception Conditions.",
  "#UD if EVEX.vvvv != 1111B."
]

semantic_general = """
(KL, VL) = (1, 128)
DEST[31:0] := REDUCE(SRC2[31:0], imm8)
DEST[127:32] := SRC1[127:32]
DEST[MAXVL-1:128] := 0
"""

handler = "x86_vreducess"
jit_lowering = "arm64_vreducess"
fallback = "zig_scalar_reduce_f32"

neon_register_model = """
VREDUCESS performs a scalar reduction transformation on the low float32 element of xmm2, using xmm3/m32 as input, controlled by imm8. The upper 96 bits of xmm1 are passed through from xmm2. The result is written to xmm1.
"""

neon_flag_model = """
No x86 flags are modified by VREDUCESS.
"""

neon_assembly = """
// NEON lowering: scalar reduction of f32 value using the REDUCE primitive controlled by imm8.
// The result replaces the low 32 bits of the destination; upper bits pass through.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VREDUCESS uses opmask register k1 for merging/zeroing masking.",
  "The imm8 operand controls the reduction exponent magnitude and the range/truncation behavior.",
  "#UD is raised if EVEX.vvvv != 1111B.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
