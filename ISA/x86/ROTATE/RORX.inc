// ROTATE/RORX.inc
// RORX — Rotate Right Logical Without Affecting Flags (BMI2).

name = "RORX"
category = "bit_rotate"
feature = "BMI2"
element_type = "gpr"

encodings = [
  { opcode = "VEX.LZ.F2.0F3A.W0 F0 /r ib", form = "RORX r32, r/m32, imm8", op_en = "RMI", feature = "BMI2", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.LZ.F2.0F3A.W1 F0 /r ib", form = "RORX r64, r/m64, imm8", op_en = "RMI", feature = "BMI2", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RMI = { operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "imm8", operand4 = "N/A" }
}

reads = ["SRC"]
writes = ["DEST"]
flags_read = []
flags_written = []
implicit_operands = []

semantic = """
IF OperandSize = 32 THEN y := imm8 AND 1FH; DEST := (SRC >> y) | (SRC << (32 - y));
ELSE (OperandSize = 64) y := imm8 AND 3FH; DEST := (SRC >> y) | (SRC << (64 - y)); FI;
"""

exceptions = {
  protected_mode = ["#UD if VEX.L != 0", "#UD if VEX.vvvv != 1111B"],
  real_address_mode = ["#UD — RORX not supported in real mode"],
  virtual_8086_mode = ["#UD — RORX not supported in virtual-8086 mode"],
  compatibility_mode = ["Same as protected mode"],
  mode64 = ["Same as protected mode"]
}

handler = "x86_rorx"
jit_lowering = "arm64_ror"

neon_register_model = "RORX is a BMI2 GPR rotate instruction. No NEON register effect."
neon_flag_model = "None — RORX does not affect arithmetic flags."
neon_assembly = "// NEON lowering: RORX stub"
neon_notes = ["RORX is a VEX-encoded BMI2 instruction; does not affect flags.", "ARM64 lowering uses ROR instruction."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
