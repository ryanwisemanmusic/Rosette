// SHUFFLE/VPSHUFHW.inc
// Source contract: VPSHUFHW — shuffle high packed words.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHUFFLE/VPSHUFHW.inc"
x86_handler = "x86_vpshufhw"
neon_lowering = "arm64_vpshufhw"
lowering_kind = "arm64_documented_contract"

name = "VPSHUFHW"
aliases = []
category = "simd_shuffle"
feature = "avx"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "VEX.128.F3.0F 70 /r ib", form = "VPSHUFHW xmm1, xmm2/m128, imm8", op_en = "RMI", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.F3.0F 70 /r ib", form = "VPSHUFHW ymm1, ymm2/m256, imm8", op_en = "RMI", feature = "AVX", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RMI = ["reg", "rm", "imm8"]
}

simd_fp_exceptions = []

semantic_general = """
Shuffle the high four 16-bit words independently in each 128-bit lane;
preserve the low four words of every lane.
"""

handler = "x86_vpshufhw"
jit_lowering = "arm64_vpshufhw"
fallback = "zig_vpshufhw"

neon_register_model = """
VPSHUFHW is a lane-local 16-bit shuffle and does not modify flags.
"""

neon_flag_model = """
VPSHUFHW does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPSHUFHW uses table/select operations within each 128-bit lane.
"""

neon_notes = [
  "The immediate control is applied independently to the high four words of each lane.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
