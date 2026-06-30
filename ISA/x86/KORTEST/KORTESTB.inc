// KORTEST/KORTESTB.inc
// Source contract: KORTESTB — OR Masks and Set Flags.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "KORTEST/KORTESTB.inc"
x86_handler = "x86_kortestb"
neon_lowering = "arm64_kortestb"
lowering_kind = "arm64_documented_contract"

name = "KORTESTB"
aliases = []
category = "mask_register_test"
feature = "avx512dq"

encodings = [
  { opcode = "VEX.L0.66.0F.W0 98 /r", form = "KORTESTB k1, k2", op_en = "RR", feature = "avx512dq", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RR = ["ModRM:reg (w)", "ModRM:r/m (r, ModRM:[7:6] must be 11b)"]
}

lanes = { mask = 1 }
flags_written = ["ZF", "CF", "OF", "SF", "AF", "PF"]
floating_point_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 Exception Definition (VEX-Encoded OpMask Instructions w/o Memory Arg)."]

semantic_general = """
Bitwise OR 8 bits masks k1 and k2 and update ZF and CF accordingly.
ZF := (OR result == 0) ? 1 : 0
CF := (OR result == all 1s) ? 1 : 0
OF, SF, AF, PF := 0
"""

handler = "x86_kortestb"
jit_lowering = "arm64_kortestb"
fallback = "zig_kortestb"

neon_register_model = "KORTESTB is an AVX512 mask register test operation."
neon_flag_model = "ZF and CF set based on OR result."
neon_assembly = "// NEON lowering: KORTESTB stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
