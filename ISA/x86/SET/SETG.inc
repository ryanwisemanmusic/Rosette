// SET/SETG.inc
// Source contract: SETG — conditional_set.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/SETG.inc"
x86_handler = "x86_setg"
neon_lowering = "arm64_setg"
lowering_kind = "arm64_documented_contract"

name = "SETG"
aliases = []
category = "conditional_set"
feature = "x86_gpr"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "0F 9F /r", form = "SETG r8/m8", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
If condition (greater (signed) (ZF=0 and SF=OF)), then DEST := 1; else DEST := 0;
"""

handler = "x86_setg"
jit_lowering = "arm64_setg"
fallback = "zig_setg"

neon_register_model = """
x86 GPR mapped to ARM64 xN. SETG is a conditional_set instruction.
"""

neon_flag_model = """
No x86 flags are modified by SETG.
"""

neon_assembly = """
// NEON lowering: csinc wDEST, wzr, wzr, <inv_cond>
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
