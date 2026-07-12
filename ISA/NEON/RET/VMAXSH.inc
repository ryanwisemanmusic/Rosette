// RET/VMAXSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/MIN-MAX/VMAXSH.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VMAXSH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_arithmetic.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MIN-MAX/VMAXSH.inc"
x86_handler = "x86_vmaxsh"
neon_lowering = "arm64_neon_fmax_sh"
lowering_kind = "neon_vector"

name = "VMAXSH"
category = "simd_arithmetic"
feature = "AVX512_FP16"
element_type = "f16"
legacy_width = 128
lanes_128 = 1
lanes_256 = 1
lanes_512 = 1
mxcsr_used = true

encodings = [
  { opcode = "7E 34 80 60 FMAX Vd.4H, Vn.4H, Vm.4H", form = "VMAXSH Vd.4H, Vn.4H, Vm.4H", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_fmax_sh" }
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
DEST[15:0] = MAX(DEST[15:0], SRC[15:0]);
DEST[MAXVL-1:16] unchanged;
"""

semantic_vex = """
MAX(SRC1, SRC2) {
    IF ((SRC1 = 0.0) and (SRC2 = 0.0)) THEN result := SRC2;
    ELSE IF (SRC1 = NaN) THEN result := SRC2;
    ELSE IF (SRC2 = NaN) THEN result := SRC2;
    ELSE IF (SRC1 > SRC2) THEN result := SRC1;
    ELSE result := SRC2;
}
DEST[15:0] = MAX(SRC1[15:0], SRC2[15:0]);
DEST[MAXVL-1:16] = 0;
"""

simd_fp_exceptions = ["invalid", "denormal"]
other_exceptions = ["Type E2 class exception conditions"]

handler = "x86_vmaxsh"
jit_lowering = "arm64_neon_fmax_sh"

neon_register_model = """
x86 scalar f16 lanes are mapped onto ARM64 vector registers; the scalar result is placed in the low element.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fmax vD.4h, vN.4h, vM.4h
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "FMAX .4H provides lane-wise half-precision maximum matching VMAXSH scalar semantics."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
