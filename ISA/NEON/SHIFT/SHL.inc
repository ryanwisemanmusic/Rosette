// SHIFT/SHL.inc
// ARM64/NEON mirror generated from ISA/x86/SHIFT/SHL.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/SHL.inc"
x86_handler = "x86_shl"
neon_lowering = "arm64_shl"
lowering_kind = "arm64_documented_contract"

name = "SHL"
aliases = ["SAL"]
category = "shift"
feature = "8086"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "D0 /4", form = "SHL r/m8, 1", op_en = "M1", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "REX + D0 /4", form = "SHL r/m8, 1", op_en = "M1", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "D2 /4", form = "SHL r/m8, CL", op_en = "MC", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "REX + D2 /4", form = "SHL r/m8, CL", op_en = "MC", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "C0 /4 ib", form = "SHL r/m8, imm8", op_en = "MI", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "REX + C0 /4 ib", form = "SHL r/m8, imm8", op_en = "MI", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "D1 /4", form = "SHL r/m16, 1", op_en = "M1", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "D3 /4", form = "SHL r/m16, CL", op_en = "MC", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "C1 /4 ib", form = "SHL r/m16, imm8", op_en = "MI", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "D1 /4", form = "SHL r/m32, 1", op_en = "M1", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + D1 /4", form = "SHL r/m64, 1", op_en = "M1", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "D3 /4", form = "SHL r/m32, CL", op_en = "MC", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + D3 /4", form = "SHL r/m64, CL", op_en = "MC", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "C1 /4 ib", form = "SHL r/m32, imm8", op_en = "MI", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + C1 /4 ib", form = "SHL r/m64, imm8", op_en = "MI", feature = "8086", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M1 = ["ModRM:r/m (r,w)", "1"],
  MC = ["ModRM:r/m (r,w)", "CL"],
  MI = ["ModRM:r/m (r,w)", "imm8"]
}

flags_written = ["CF", "OF", "SF", "ZF", "PF", "AF"]
simd_fp_exceptions = []

semantic_general = """
Shifts bits in destination operand to the left by count bits. Same operation as SAL.
"""

handler = "x86_shl"
jit_lowering = "arm64_shl"
fallback = "zig_shl"

neon_register_model = "x86 GP registers mapped to ARM64 X registers."
neon_flag_model = "CF, OF, SF, ZF, PF, AF set per x86 shift semantics via ARM64 shifts + flag synthesis."
neon_assembly = "// ARM64: LSL, shifted register or immediate"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
syntax_examples = [
  { syntax = "att", form = "shlq %cl, %r14", maps_to = "SHL r/m64, CL", opcode = "REX.W + D3 /4" }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
