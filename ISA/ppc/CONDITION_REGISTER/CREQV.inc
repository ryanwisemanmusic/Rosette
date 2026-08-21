// CONDITION_REGISTER/CREQV.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XL", operand_1 = "CR[CRBD]", operand_2 = "CR[CRBA]", operand_3 = "CR[CRBB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "creqv"
mnemonic = "creqv"
category = "condition_register"
operation = "CR[crbD] = CR[crbA] xnor CR[crbB]"

form = "XL"
primary_opcode = 19
opcode_pattern = "0x4c000242"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x4c000242", form = "creqv [CRBD], [CRBA], [CRBB]", op_en = "XL" }
]

reads = ["CR[CRBA]", "CR[CRBB]"]
writes = ["CR[CRBD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
CR[crbD] <- CR[crbA] xnor CR[crbB]
"""

handler = "ppc_creqv"
jit_lowering = "arm64_ppc_creqv"

