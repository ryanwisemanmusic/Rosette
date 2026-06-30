// LOGICAL_OR/KORB.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/KORB.inc"
x86_handler = "x86_korb"
neon_lowering = "arm64_korb"
lowering_kind = "arm64_documented_contract"

name = "KORB"
aliases = []
category = "mask_register_logical"
feature = "avx512dq"

encodings = [
  { opcode = "VEX.L1.66.0F.W0 45 /r", form = "KORB k1, k2, k3", op_en = "RVR", feature = "avx512dq", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RVR = ["ModRM:reg (w)", "VEX.1vvv (r)", "ModRM:r/m (r, ModRM:[7:6] must be 11b)"]
}

lanes = { mask = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 Exception Definition (VEX-Encoded OpMask Instructions w/o Memory Arg)."]

semantic_general = "Bitwise OR 8 bits masks k2 and k3 and place result in k1."

handler = "x86_korb"
jit_lowering = "arm64_korb"
fallback = "zig_korb"

neon_register_model = "KORB is an AVX512 mask register operation."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: KORB stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
