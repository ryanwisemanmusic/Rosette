// SET/SETA.inc
// ARM64/NEON mirror generated from ISA/x86/SET/SETA.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/SETA.inc"
x86_handler = "x86_seta"
neon_lowering = "arm64_seta"
lowering_kind = "arm64_documented_contract"

name = "SETA"
aliases = []
category = "conditional_set"
feature = "x86_gpr"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "0F 97 /r", form = "SETA r8/m8", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = [],

semantic_general = """
If condition (above (CF=0 and ZF=0)), then DEST := 1; else DEST := 0;
"""

handler = "x86_seta"
jit_lowering = "arm64_seta"
fallback = "zig_seta"

neon_register_model = """
SETA is a conditional_set instruction. No ARM64-specific registers modified.
"""

neon_flag_model = """
No x86 flags modified by SETA.
"""

neon_assembly = """
// NEON lowering: csinc wDEST, wzr, wzr, <inv_cond>
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
