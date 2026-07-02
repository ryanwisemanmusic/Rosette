// UNORDERED/VUCOMISH.inc
// VUCOMISH — Unordered Compare Scalar FP16 Values and Set EFLAGS.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNORDERED/VUCOMISH.inc"
x86_handler = "x86_vucomish"
neon_lowering = "arm64_vucomish"
lowering_kind = "arm64_documented_contract"

name = "VUCOMISH"
aliases = []
category = "compare"
feature = "AVX512-FP16"

encodings = [
  { opcode = "EVEX.LLIG.NP.MAP5.W0 2E /r", form = "VUCOMISH xmm1, xmm2/m16{sae}", op_en = "A", feature = "AVX512-FP16", vector_length = 0, encoding = "EVEX" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)", "N/A", "N/A"]
}

flags_written = ["ZF", "PF", "CF", "OF=0", "SF=0", "AF=0"]
floating_point_exceptions = ["Invalid", "Denormal"]
other_exceptions = ["#UD (if EVEX.vvvv != 1111B)"]

semantic_general = """
Unordered compare of FP16 values in low word of xmm1 and xmm2/m16.
Sets ZF, PF, CF according to result (unordered/greater/less/equal). Clears OF, SF, AF.
Differs from VCOMISH: signals #I only on SNaN (not QNaN).
"""

handler = "x86_vucomish"
jit_lowering = "arm64_vucomish"
fallback = "zig_vucomish"

neon_register_model = "VUCOMISH is an x86 scalar FP16 compare with EFLAGS result. Lowered via mask+flag translation."
neon_flag_model = "ZF, PF, CF mapped from NEON condition flags."
neon_assembly = "// NEON lowering: VUCOMISH stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
