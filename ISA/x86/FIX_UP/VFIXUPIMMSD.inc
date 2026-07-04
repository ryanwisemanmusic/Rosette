// FIX_UP/VFIXUPIMMSD.inc
// ARM64/NEON translation mirror generated from ISA/x86/FIX_UP/VFIXUPIMMSD.inc.
// Source contract: VFIXUPIMMSD — Fix Up Special Scalar Float64 Value.

semantic = """
DEST[63:0] := FixUpSpecialScalarFP64(SRC1[63:0], SRC2[63:0], imm8[7:0])
DEST[127:64] := SRC1[127:64]
DEST[MAXVL-1:128] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FIX_UP/VFIXUPIMMSD.inc"
x86_handler = "x86_vfixupimmsd"
neon_lowering = "arm64_vfixupimmsd"
lowering_kind = "arm64_scalar"

name = "VFIXUPIMMSD"
aliases = []
category = "simd_fixup"
feature = "AVX512F"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.LLIG.66.0F3A.W1 55 /r ib", form = "VFIXUPIMMSD xmm1 {k1}{z}, xmm2, xmm3/m64, imm8", op_en = "A", feature = "AVX512F", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 0 }
flags_written = []
simd_fp_exceptions = [
  "Zero",
  "Invalid"
]
other_exceptions = [
  "See Table 2-47, Type E3 Class Exception Conditions."
]

semantic_general = """
Perform a scalar fix-up of the low FP64 element based on the 8-bit immediate
control word and the two source operands. The upper bits of the destination
XMM register are copied from SRC1[127:64] (legacy SSE/AVX scalar merge).
"""

handler = "x86_vfixupimmsd"
jit_lowering = "arm64_vfixupimmsd"
fallback = "zig_vfixupimmsd"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VFIXUPIMMSD is a scalar AVX512F fix-up of the
low double-precision element with an 8-bit immediate lookup table.
"""

neon_flag_model = """
No x86 flags modified by VFIXUPIMMSD.
"""

neon_assembly = """
// NEON lowering: VFIXUPIMMSD scalar fix-up stub (simd_fixup)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
