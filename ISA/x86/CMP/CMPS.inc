// CMP/CMPS.inc
// Legacy implicit string-compare contract shared by the x86 decoder and the
// ARM64/NEON lowering.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CMP/CMPS.inc"
x86_handler = "x86_cmps"
neon_lowering = "arm64_cmps_subtract_set_x86_flags"
lowering_kind = "arm64_string_compare"

name = "CMPS"
aliases = ["CMPSB", "CMPSW", "CMPSD", "CMPSQ"]
category = "string_compare"
feature = "8086"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "A6", form = "CMPSB", op_en = "ZO", mode64 = "valid", compat = "valid", handler = "x86_cmps" },
  { opcode = "A7", form = "CMPSW", op_en = "ZO", mode64 = "valid", compat = "valid", handler = "x86_cmps" },
  { opcode = "A7", form = "CMPSD (string)", op_en = "ZO", mode64 = "valid", compat = "valid", handler = "x86_cmps" },
  { opcode = "REX.W + A7", form = "CMPSQ", op_en = "ZO", mode64 = "valid", compat = "not_encodable", handler = "x86_cmps" },
]

operand_encoding = [
  { op_en = "ZO", operand_1 = "N/A (implicit DS:(E)SI/(R)SI)", operand_2 = "N/A (implicit ES:(E)DI/(R)DI)", operand_3 = "N/A", operand_4 = "N/A" },
]

reads = ["DS:(E)SI_or_(R)SI", "ES:(E)DI_or_(R)DI", "DF"]
writes = ["(E)SI_or_(R)SI", "(E)DI_or_(R)DI", "RFLAGS/EFLAGS status flags"]
flags_read = ["DF"]
flags_written = ["OF", "SF", "ZF", "AF", "PF", "CF"]
flags_affected = "OF, SF, ZF, AF, PF, and CF are set according to the subtraction of the destination string element from the source string element"
lock_allowed = false

mode_notes = [
  "The operand-size attribute selects byte, word, doubleword, or quadword elements; REX.W selects CMPSQ in 64-bit mode.",
  "The address-size attribute selects SI/DI, ESI/EDI, or RSI/RDI and wraps the selected index width.",
  "A segment override may replace DS for the source; the destination remains in ES.",
  "REP/REPE/REPZ and REPNE/REPNZ repeat while the count and equality condition permit.",
]

semantic = """
source_element = memory[DS:(E)SI_or_(R)SI];
destination_element = memory[ES:(E)DI_or_(R)DI];
temp = source_element - destination_element;
update_sub_flags(source_element, destination_element, temp, element_width);
advance SI/ESI/RSI and DI/EDI/RDI by element_width according to DF;
if REP/REPE/REPZ or REPNE/REPNZ is present, decrement the count and apply the ZF continuation condition;
"""

exceptions = {
  general = ["#GP", "#PF", "#AC", "#UD"]
}

handler = "x86_cmps"
jit_lowering = "arm64_cmps_subtract_set_x86_flags"
fallback = "zig_cmps_fallback"

neon_register_model = """
CMPS reads the source and destination implicit x86 indices and memory operands,
updates both indices according to DF, and writes only the x86 status flags.
The count and REP condition are part of the emulated x86 state.
"""

neon_flag_model = """
Use ARM64 SUBS for the element subtraction, then synthesize x86 CF, AF, and PF
from the operands and result while preserving the exact x86 SF, ZF, and OF
values. DF is consumed for index direction and is not modified.
"""

neon_assembly = """
// ARM64: load source/destination elements, subs into a temporary, pack x86 flags,
// update the two index registers, decrement the REP count, and branch on ZF/count.
"""

lowering_rules = [
  "Compute source minus destination; do not reverse the CMPS operand order.",
  "Keep source segment override behavior and the ES destination segment behavior.",
  "Apply address-size truncation and DF-controlled wrapping at the selected width.",
  "Preserve memory faults and reject LOCK with the documented invalid-instruction path.",
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
