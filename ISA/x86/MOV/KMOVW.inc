// KMOVW.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/KMOVW.inc.
// Source contract: KMOVW — Move 16-bit Mask.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/KMOVW.inc"
x86_handler = "x86_kmovw"
neon_lowering = "arm64_kmovw"
lowering_kind = "arm64_documented_contract"

name = "KMOVW"
aliases = []
category = "simd_mask_move"
feature = "AVX512F"
element_type = "u16_mask"

encodings = [
  { opcode = "VEX.L0.0F.W0 90 /r", form = "KMOVW k1, k2/m16", op_en = "RM", feature = "AVX512F", vector_length = 0, encoding = "VEX" },
  { opcode = "VEX.L0.0F.W0 91 /r", form = "KMOVW m16, k1", op_en = "MR", feature = "AVX512F", vector_length = 0, encoding = "VEX" },
  { opcode = "VEX.L0.0F.W0 92 /r", form = "KMOVW k1, r32", op_en = "RR", feature = "AVX512F", vector_length = 0, encoding = "VEX" },
  { opcode = "VEX.L0.0F.W0 93 /r", form = "KMOVW r32, k1", op_en = "RR", feature = "AVX512F", vector_length = 0, encoding = "VEX" }
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
KMOVW moves 16-bit mask data between mask registers, GPRs, and memory. Upper bits of destination mask register are zeroed.
"""

handler = "x86_kmovw"
jit_lowering = "arm64_kmovw"
fallback = "zig_kmov"

neon_register_model = "KMOVW is an x86 mask register operation. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: KMOVW stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
