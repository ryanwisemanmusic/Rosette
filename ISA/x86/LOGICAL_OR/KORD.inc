// LOGICAL_OR/KORD.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/KORD.inc"
x86_handler = "x86_kord"
neon_lowering = "arm64_kord"
lowering_kind = "arm64_documented_contract"

name = "KORD"
aliases = []
category = "mask_register_logical"
feature = "avx512bw"

encodings = [
  { opcode = "VEX.L1.66.0F.W1 45 /r", form = "KORD k1, k2, k3", op_en = "RVR", feature = "avx512bw", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RVR = ["ModRM:reg (w)", "VEX.1vvv (r)", "ModRM:r/m (r, ModRM:[7:6] must be 11b)"]
}

lanes = { mask = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 Exception Definition (VEX-Encoded OpMask Instructions w/o Memory Arg)."]

semantic_general = "Bitwise OR 32 bits masks k2 and k3 and place result in k1."

handler = "x86_kord"
jit_lowering = "arm64_kord"
fallback = "zig_kord"

neon_register_model = "KORD is an AVX512 mask register operation."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: KORD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
