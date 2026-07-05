// READ/RDRAND.inc
// RDRAND — Read Random Number.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDRAND.inc"
x86_handler = "x86_rdrand"
neon_lowering = "arm64_documented_contract"
lowering_kind = "arm64_documented_contract"

name = "RDRAND"
category = "system_random_read"
feature = "RDRAND"
element_type = "gpr"

encodings = [
  { opcode = "NFx 0F C7 /6", form = "RDRAND r16", op_en = "M", feature = "RDRAND", vector_length = 0, encoding = "legacy" },
  { opcode = "NFx 0F C7 /6", form = "RDRAND r32", op_en = "M", feature = "RDRAND", vector_length = 0, encoding = "legacy" },
  { opcode = "NFx REX.W 0F C7 /6", form = "RDRAND r64", op_en = "M", feature = "RDRAND", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { M = { operand1 = "ModRM:r/m (w)" } }

reads = []
writes = ["DST"]
flags_read = []
flags_written = ["cf"]

semantic = """
IF HW_RNG_available THEN
    DST := random_value;
    CF := 1;
ELSE
    DST := 0;
    CF := 0;
FI;
OF := 0; SF := 0; ZF := 0; AF := 0; PF := 0;
"""

exceptions = [
  "#UD if CPUID.01H:ECX.RDRAND[bit 30] = 0",
  "#UD if the LOCK prefix is used"
]

handler = "x86_rdrand"
jit_lowering = "arm64_sysreg_read"

neon_register_model = "RDRAND reads a hardware random number. No ARM64 NEON equivalent."
neon_flag_model = "CF set if valid random data returned; OF/SF/ZF/AF/PF cleared to 0."
neon_assembly = "// NEON lowering: RDRAND stub"
neon_notes = ["RDRAND reads a random value from the hardware RNG.", "NFx prefix indicates no false dependency on destination register.", "CF indicates valid random data."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
