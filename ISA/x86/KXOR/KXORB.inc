// KXOR/KXORB.inc
// KXORB — Bitwise Logical XOR of 8-bit Masks.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "KXOR/KXORB.inc"
x86_handler = "x86_kxorb"
neon_lowering = "arm64_kxorb"
lowering_kind = "arm64_documented_contract"

name = "KXORB"
aliases = []
category = "mask_logical"
feature = "AVX512DQ"

encodings = [
  { opcode = "VEX.L1.66.0F.W0 47 /r", form = "KXORB k1, k2, k3", op_en = "RVR", feature = "AVX512DQ", vector_length = 0, encoding = "VEX" }
]

operand_encoding = {
  RVR = ["ModRM:reg (w)", "VEX.1vvv (r)", "ModRM:r/m (r, ModRM:[7:6] must be 11b)", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 (VEX-Encoded OpMask Instructions w/o Memory Arg)"]

semantic_general = """
Bitwise XOR of 8-bit mask registers k2 and k3, result in k1. Zeroes upper bits of k1.
"""

handler = "x86_kxorb"
jit_lowering = "arm64_kxorb"
fallback = "zig_kxorb"

neon_register_model = "KXORB is an x86 mask register operation. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: KXORB stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
