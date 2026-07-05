// READ/RDSEED.inc
// RDSEED — Read Random SEED.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDSEED.inc"
x86_handler = "x86_rdseed"
neon_lowering = "arm64_documented_contract"
lowering_kind = "arm64_documented_contract"

name = "RDSEED"
category = "system_random_read"
feature = "RDSEED"
element_type = "gpr"

encodings = [
  { opcode = "NFx 0F C7 /7", form = "RDSEED r16", op_en = "M", feature = "RDSEED", vector_length = 0, encoding = "legacy" },
  { opcode = "NFx 0F C7 /7", form = "RDSEED r32", op_en = "M", feature = "RDSEED", vector_length = 0, encoding = "legacy" },
  { opcode = "NFx REX.W 0F C7 /7", form = "RDSEED r64", op_en = "M", feature = "RDSEED", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { M = { operand1 = "ModRM:r/m (w)" } }

reads = []
writes = ["DST"]
flags_read = []
flags_written = ["cf"]

semantic = """
IF HW_SEED_available THEN
    DST := random_seed;
    CF := 1;
ELSE
    DST := 0;
    CF := 0;
FI;
OF := 0; SF := 0; ZF := 0; AF := 0; PF := 0;
"""

exceptions = [
  "#UD if CPUID.(EAX=07H, ECX=0):EBX.RDSEED[bit 18] = 0",
  "#UD if the LOCK prefix is used"
]

handler = "x86_rdseed"
jit_lowering = "arm64_sysreg_read"

neon_register_model = "RDSEED reads a hardware random seed. No ARM64 NEON equivalent."
neon_flag_model = "CF set if valid random seed returned; OF/SF/ZF/AF/PF cleared to 0."
neon_assembly = "// NEON lowering: RDSEED stub"
neon_notes = ["RDSEED reads a random seed value from the hardware RNG.", "NFx prefix indicates no false dependency on destination register.", "CF indicates valid random seed."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
