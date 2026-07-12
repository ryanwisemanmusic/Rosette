// RET/MAXSD.inc
// ARM64/NEON translation mirror generated from ISA/x86/MIN-MAX/MAXSD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
MAXSD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_arithmetic.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MIN-MAX/MAXSD.inc"
x86_handler = "x86_maxsd"
neon_lowering = "arm64_neon_fmax_sd"
lowering_kind = "neon_vector"

name = "MAXSD"
category = "simd_arithmetic"
feature = "SSE2_AVX_AVX512F"
element_type = "f64"
legacy_width = 128
lanes_128 = 1
lanes_256 = 1
lanes_512 = 1
mxcsr_used = true

encodings = [
  { opcode = "7E 34 80 F0 FMAX Vd.2D, Vn.2D, Vm.2D", form = "MAXSD Vd.2D, Vn.2D, Vm.2D", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_fmax_sd" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
MAX(SRC1, SRC2) {
    IF ((SRC1 = 0.0) and (SRC2 = 0.0)) THEN result := SRC2;
    ELSE IF (SRC1 = NaN) THEN result := SRC2;
    ELSE IF (SRC2 = NaN) THEN result := SRC2;
    ELSE IF (SRC1 > SRC2) THEN result := SRC1;
    ELSE result := SRC2;
}
DEST[63:0] = MAX(DEST[63:0], SRC[63:0]);
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex = """
MAX(SRC1, SRC2) {
    IF ((SRC1 = 0.0) and (SRC2 = 0.0)) THEN result := SRC2;
    ELSE IF (SRC1 = NaN) THEN result := SRC2;
    ELSE IF (SRC2 = NaN) THEN result := SRC2;
    ELSE IF (SRC1 > SRC2) THEN result := SRC1;
    ELSE result := SRC2;
}
DEST[63:0] = MAX(SRC1[63:0], SRC2[63:0]);
DEST[MAXVL-1:64] = 0;
"""

simd_fp_exceptions = ["invalid", "denormal"]
other_exceptions = ["Type 2 class exception conditions"]

handler = "x86_maxsd"
jit_lowering = "arm64_neon_fmax_sd"

neon_register_model = """
x86 scalar f64 lanes are mapped onto ARM64 vector registers; the scalar result is placed in the low element.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fmax vD.2d, vN.2d, vM.2d
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "FMAX .2D provides lane-wise double-precision maximum matching MAXSD scalar semantics."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
