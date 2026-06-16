// EXCHANGE/XADD.inc
// Source contract: XADD — arithmetic.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EXCHANGE/XADD.inc"
x86_handler = "x86_xadd"
neon_lowering = "arm64_xadd"
lowering_kind = "arm64_documented_contract"

name = "XADD"
aliases = []
category = "arithmetic"
feature = "x86_gpr"
element_type = "u8_u16_u32_u64"
element_size = 8

encodings = [
  { opcode = "0F C0 /r", form = "XADD r/m8, r8", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX + 0F C0 /r", form = "XADD r/m8*, r8*", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "0F C1 /r", form = "XADD r/m16, r16", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "0F C1 /r", form = "XADD r/m32, r32", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + 0F C1 /r", form = "XADD r/m64, r64", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  MR = ["ModRM:r/m (r, w)", "ModRM:reg (r, w)"]
}

flags_written = ["CF", "PF", "AF", "SF", "ZF", "OF"]
simd_fp_exceptions = []

semantic_general = """
Exchange the first operand with the second operand, then load the sum into the destination.
"""

handler = "x86_xadd"
jit_lowering = "arm64_xadd"
fallback = "zig_xadd"

neon_register_model = """
x86 GPR/x87 FPU mapped to ARM64 equivalents. XADD is a arithmetic instruction.
"""

neon_flag_model = """
XADD writes CF, PF, AF, SF, ZF, OF.
"""

neon_assembly = """
// NEON lowering: scalar ADD + register swap sequence
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
