// KMOVB.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/KMOVB.inc.
// Source contract: KMOVB — Move 8-bit Mask.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/KMOVB.inc"
x86_handler = "x86_kmovb"
neon_lowering = "arm64_kmovb"
lowering_kind = "arm64_documented_contract"

name = "KMOVB"
aliases = []
category = "simd_mask_move"
feature = "AVX512DQ"
element_type = "u8_mask"

encodings = [
  { opcode = "VEX.L0.66.0F.W0 90 /r", form = "KMOVB k1, k2/m8", op_en = "RM", feature = "AVX512DQ", vector_length = 0, encoding = "VEX" },
  { opcode = "VEX.L0.66.0F.W0 91 /r", form = "KMOVB m8, k1", op_en = "MR", feature = "AVX512DQ", vector_length = 0, encoding = "VEX" },
  { opcode = "VEX.L0.66.0F.W0 92 /r", form = "KMOVB k1, r32", op_en = "RR", feature = "AVX512DQ", vector_length = 0, encoding = "VEX" },
  { opcode = "VEX.L0.66.0F.W0 93 /r", form = "KMOVB r32, k1", op_en = "RR", feature = "AVX512DQ", vector_length = 0, encoding = "VEX" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  MR = ["ModRM:r/m (w)", "ModRM:reg (r)"],
  RR = ["ModRM:reg (w)", "ModRM:r/m (r, ModRM:[7:6] must be 11b)"]
}

flags_written = []
simd_fp_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 (VEX-Encoded OpMask Instructions w/o Memory Arg)"]

semantic = """
KMOVB moves 8-bit mask data between mask registers, GPRs, and memory. Upper bits of destination mask register are zeroed.
"""

handler = "x86_kmovb"
jit_lowering = "arm64_kmovb"
fallback = "zig_kmov"

neon_register_model = "KMOVB is an x86 mask register operation. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: KMOVB stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
