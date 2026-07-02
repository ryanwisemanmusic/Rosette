// KXOR/KXORD.inc
// KXORD — Bitwise Logical XOR of 32-bit Masks.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "KXOR/KXORD.inc"
x86_handler = "x86_kxord"
neon_lowering = "arm64_kxord"
lowering_kind = "arm64_documented_contract"

name = "KXORD"
aliases = []
category = "mask_logical"
feature = "AVX512BW"

encodings = [
  { opcode = "VEX.L1.66.0F.W1 47 /r", form = "KXORD k1, k2, k3", op_en = "RVR", feature = "AVX512BW", vector_length = 0, encoding = "VEX" }
]

operand_encoding = {
  RVR = ["ModRM:reg (w)", "VEX.1vvv (r)", "ModRM:r/m (r, ModRM:[7:6] must be 11b)", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 (VEX-Encoded OpMask Instructions w/o Memory Arg)"]

semantic_general = """
Bitwise XOR of 32-bit mask registers k2 and k3, result in k1. Zeroes upper bits of k1.
"""

handler = "x86_kxord"
jit_lowering = "arm64_kxord"
fallback = "zig_kxord"

neon_register_model = "KXORD is an x86 mask register operation. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: KXORD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
