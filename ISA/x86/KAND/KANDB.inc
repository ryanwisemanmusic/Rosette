// KAND/KANDB.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "KAND/KANDB.inc"
x86_handler = "x86_kandb"
neon_lowering = "arm64_kandb"
lowering_kind = "arm64_documented_contract"
name = "KANDB"
aliases = []
category = "mask_logical"
feature = "AVX512DQ"
encodings = [{ opcode = "VEX.L1.66.0F.W0 41 /r", form = "KANDB k1, k2, k3", op_en = "RVR", feature = "AVX512DQ", vector_length = 0, encoding = "VEX" }]
operand_encoding = { RVR = ["ModRM:reg (w)", "VEX.1vvv (r)", "ModRM:r/m (r, ModRM:[7:6] must be 11b)", "N/A"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 (VEX-Encoded OpMask Instructions w/o Memory Arg)"]
semantic_general = "Bitwise AND of 8-bit mask registers k2 and k3, result in k1. Zeroes upper bits of k1."
handler = "x86_kandb"
jit_lowering = "arm64_kandb"
fallback = "zig_kandb"
neon_register_model = "KANDB is an x86 mask register operation. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: KANDB stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
