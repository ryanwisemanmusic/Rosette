// ZERO/VZEROALL.inc
// VZEROALL — Zero XMM, YMM, and ZMM Registers.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ZERO/VZEROALL.inc"
x86_handler = "x86_vzeroall"
neon_lowering = "arm64_vzeroall"
lowering_kind = "arm64_documented_contract"

name = "VZEROALL"
aliases = []
category = "register_zero"
feature = "AVX"

encodings = [
  { opcode = "VEX.256.0F.WIG 77", form = "VZEROALL", op_en = "ZO", feature = "AVX", vector_length = 256, encoding = "VEX" }
]

operand_encoding = {
  ZO = ["N/A", "N/A", "N/A", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["#UD (if VEX.vvvv != 1111B)", "See Table 2-25, Type 8 Class Exception Conditions"]

semantic_general = """
Zeroes XMM0-XMM15, YMM0-YMM15, ZMM0-ZMM15 in 64-bit mode; XMM0-XMM7, YMM0-YMM7, ZMM0-ZMM7 outside 64-bit mode.
Does not modify ZMM16-ZMM31.
"""

handler = "x86_vzeroall"
jit_lowering = "arm64_vzeroall"
fallback = "zig_vzeroall"

neon_register_model = "VZEROALL is an x86 SIMD register zeroing operation. NEON lowering may zero associated registers."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VZEROALL stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
