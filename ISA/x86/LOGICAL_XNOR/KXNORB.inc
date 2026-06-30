// LOGICAL_XNOR/KXNORB.inc
// Source contract: KXNORB — Bitwise Logical XNOR 8-bit Masks.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_XNOR/KXNORB.inc"
x86_handler = "x86_kxnorb"
neon_lowering = "arm64_kxnorb"
lowering_kind = "arm64_documented_contract"

name = "KXNORB"
aliases = []
category = "mask_register_logical"
feature = "avx512dq"

encodings = [
  { opcode = "VEX.L1.66.0F.W0 46 /r", form = "KXNORB k1, k2, k3", op_en = "RVR", feature = "avx512dq", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RVR = ["ModRM:reg (w)", "VEX.1vvv (r)", "ModRM:r/m (r, ModRM:[7:6] must be 11b)"]
}

lanes = { mask = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = [
  "See Table 2-63, TYPE K20 Exception Definition (VEX-Encoded OpMask Instructions w/o Memory Arg)."
]

semantic_general = """
Performs a bitwise XNOR between the vector mask k2 and the vector mask k3, and writes the result into vector mask k1.
DEST[7:0] := NOT (SRC1[7:0] BITWISE XOR SRC2[7:0]); DEST[MAX_KL-1:8] := 0
"""

handler = "x86_kxnorb"
jit_lowering = "arm64_kxnorb"
fallback = "zig_kxnorb"

neon_register_model = """
KXNORB is an AVX512 mask register operation. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
None.
"""

neon_assembly = """
// NEON lowering: KXNORB stub (AVX512 mask XNOR)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
