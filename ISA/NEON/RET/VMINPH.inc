// RET/VMINPH.inc
// ARM64/NEON translation mirror generated from ISA/x86/MIN-MAX/VMINPH.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VMINPH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_arithmetic.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MIN-MAX/VMINPH.inc"
x86_handler = "x86_vminph"
neon_lowering = "arm64_neon_fmin_ph"
lowering_kind = "neon_vector"

name = "VMINPH"
category = "simd_arithmetic"
feature = "AVX512_FP16"
element_type = "f16"
legacy_width = 128
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = true

encodings = [
  { opcode = "7E 34 80 60 FMIN Vd.8H, Vn.8H, Vm.8H", form = "VMINPH Vd.8H, Vn.8H, Vm.8H", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_fmin_ph" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
MIN(SRC1, SRC2) {
    IF ((SRC1 = 0.0) and (SRC2 = 0.0)) THEN result := SRC2;
    ELSE IF (SRC1 = NaN) THEN result := SRC2;
    ELSE IF (SRC2 = NaN) THEN result := SRC2;
    ELSE IF (SRC1 < SRC2) THEN result := SRC1;
    ELSE result := SRC2;
}
for j in 0..KL-1:
    i = j * 16;
    DEST[i+15:i] = MIN(SRC1[i+15:i], SRC2[i+15:i]);
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["invalid", "denormal"]
other_exceptions = ["Type E2 class exception conditions"]

handler = "x86_vminph"
jit_lowering = "arm64_neon_fmin_ph"

neon_register_model = """
x86 zmm f16 lanes are mapped onto ARM64 vector registers preserving lane width.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fmin vD.8h, vN.8h, vM.8h
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "FMIN .8H provides lane-wise half-precision minimum matching VMINPH packed semantics."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
