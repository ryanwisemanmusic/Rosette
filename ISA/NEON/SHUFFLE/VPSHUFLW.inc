// SHUFFLE/VPSHUFLW.inc
// ARM64/NEON mirror generated from ISA/x86/SHUFFLE/VPSHUFLW.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHUFFLE/VPSHUFLW.inc"
x86_handler = "x86_vpshuflw"
neon_lowering = "arm64_vpshuflw"
lowering_kind = "arm64_documented_contract"

name = "VPSHUFLW"
aliases = []
category = "simd_shuffle"
feature = "avx"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "VEX.128.F2.0F 70 /r ib", form = "VPSHUFLW xmm1, xmm2/m128, imm8", op_en = "RMI", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.F2.0F 70 /r ib", form = "VPSHUFLW ymm1, ymm2/m256, imm8", op_en = "RMI", feature = "AVX", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RMI = ["reg", "rm", "imm8"]
}

simd_fp_exceptions = []

semantic_general = """
Shuffle the low four 16-bit words independently in each 128-bit lane;
preserve the high four words of every lane.
"""

handler = "x86_vpshuflw"
jit_lowering = "arm64_vpshuflw"
fallback = "zig_vpshuflw"

neon_register_model = """
VPSHUFLW is a lane-local 16-bit shuffle and does not modify flags.
"""

neon_flag_model = """
VPSHUFLW does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPSHUFLW uses table/select operations within each 128-bit lane.
"""

neon_notes = [
  "The immediate control is applied independently to the low four words of each lane.",
  "This mirror preserves the x86 encoding scope one-for-one."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
