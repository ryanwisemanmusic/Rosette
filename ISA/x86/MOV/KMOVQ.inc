// KMOVQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/KMOVQ.inc.
// Source contract: KMOVQ — Move 64-bit Mask.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/KMOVQ.inc"
x86_handler = "x86_kmovq"
neon_lowering = "arm64_kmovq"
lowering_kind = "arm64_documented_contract"

name = "KMOVQ"
aliases = []
category = "simd_mask_move"
feature = "AVX512BW"
element_type = "u64_mask"

encodings = [
  { opcode = "VEX.L0.0F.W1 90 /r", form = "KMOVQ k1, k2/m64", op_en = "RM", feature = "AVX512BW", vector_length = 0, encoding = "VEX" },
  { opcode = "VEX.L0.0F.W1 91 /r", form = "KMOVQ m64, k1", op_en = "MR", feature = "AVX512BW", vector_length = 0, encoding = "VEX" },
  { opcode = "VEX.L0.F2.0F.W1 92 /r", form = "KMOVQ k1, r64", op_en = "RR", feature = "AVX512BW", vector_length = 0, encoding = "VEX" },
  { opcode = "VEX.L0.F2.0F.W1 93 /r", form = "KMOVQ r64, k1", op_en = "RR", feature = "AVX512BW", vector_length = 0, encoding = "VEX" }
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
KMOVQ moves 64-bit mask data between mask registers, GPRs, and memory. Upper bits of destination mask register are zeroed.
"""

handler = "x86_kmovq"
jit_lowering = "arm64_kmovq"
fallback = "zig_kmov"

neon_register_model = "KMOVQ is an x86 mask register operation. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: KMOVQ stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
