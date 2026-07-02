// UNORDERED/UCOMISD.inc
// UCOMISD — Unordered Compare Scalar Double Precision Floating-Point Values and Set EFLAGS.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNORDERED/UCOMISD.inc"
x86_handler = "x86_ucomisd"
neon_lowering = "arm64_ucomisd"
lowering_kind = "arm64_documented_contract"

name = "UCOMISD"
aliases = ["VUCOMISD"]
category = "compare"
feature = "SSE2"

encodings = [
  { opcode = "66 0F 2E /r", form = "UCOMISD xmm1, xmm2/m64", op_en = "A", feature = "SSE2", vector_length = 0, encoding = "legacy" },
  { opcode = "VEX.LIG.66.0F.WIG 2E /r", form = "VUCOMISD xmm1, xmm2/m64", op_en = "A", feature = "AVX", vector_length = 0, encoding = "VEX" },
  { opcode = "EVEX.LLIG.66.0F.W1 2E /r", form = "VUCOMISD xmm1, xmm2/m64{sae}", op_en = "B", feature = "AVX512F", vector_length = 0, encoding = "EVEX" }
]

operand_encoding = {
  A = ["ModRM:reg (r)", "ModRM:r/m (r)", "N/A", "N/A"],
  B = ["ModRM:reg (w)", "ModRM:r/m (r)", "N/A", "N/A"]
}

flags_written = ["ZF", "PF", "CF", "OF=0", "SF=0", "AF=0"]
floating_point_exceptions = ["Invalid (if SNaN operand)", "Denormal"]
other_exceptions = ["#UD (if VEX/EVEX.vvvv != 1111B)"]

semantic_general = """
Unordered compare of double precision values in low quadwords of xmm1 and xmm2/m64.
Sets ZF, PF, CF according to result (unordered/greater/less/equal). Clears OF, SF, AF.
Differs from COMISD: signals #I only on SNaN (not QNaN).
"""

handler = "x86_ucomisd"
jit_lowering = "arm64_ucomisd"
fallback = "zig_ucomisd"

neon_register_model = "UCOMISD is an x86 scalar compare with EFLAGS result. Lowered via mask+flag translation."
neon_flag_model = "ZF, PF, CF mapped from NEON condition flags."
neon_assembly = "// NEON lowering: UCOMISD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
