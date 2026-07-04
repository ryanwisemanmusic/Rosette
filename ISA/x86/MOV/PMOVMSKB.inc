// PMOVMSKB.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/PMOVMSKB.inc.
// Source contract: PMOVMSKB/VPMOVMSKB — Move Byte Mask.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/PMOVMSKB.inc"
x86_handler = "x86_pmovmskb"
neon_lowering = "arm64_pmovmskb"
lowering_kind = "arm64_documented_contract"

name = "PMOVMSKB"
aliases = ["VPMOVMSKB"]
category = "simd_move"
feature = "SSE_SSE2_AVX_AVX2"

encodings = [
  { opcode = "NP 0F D7 /r", form = "PMOVMSKB r32, mm1", op_en = "RM", feature = "SSE", vector_length = 64, encoding = "legacy_mmx" },
  { opcode = "66 0F D7 /r", form = "PMOVMSKB r32, xmm1", op_en = "RM", feature = "SSE2", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F.WIG D7 /r", form = "VPMOVMSKB r32, xmm1", op_en = "RM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG D7 /r", form = "VPMOVMSKB r32, ymm1", op_en = "RM", feature = "AVX2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []
other_exceptions = ["Type 1 (legacy SSE/SSE2); Type 4 (VEX)"]

semantic = """
Extracts the most significant bit (bit 7) of each byte in the source vector and packs them into a GPR.
"""

handler = "x86_pmovmskb"
jit_lowering = "arm64_pmovmskb"
fallback = "zig_pmovmskb_fallback"

neon_register_model = """
The x86 register and memory operands are read from the Rosette register file. The ARM64 lowering extracts byte MSBs and packs them into a GPR.
"""

neon_flag_model = """
This lowering reads the preserved x86 architectural state exactly as listed in reads/flags_read. No ARM64 NZCV flags are modified unless this instruction explicitly writes x86 flags.
"""

neon_assembly = """
// PMOVMSKB: extract MSB of each byte, pack into GPR
// ARM64: SSHR + MOV + ORR to extract and pack bit 7 of each byte into r32
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken x86 data-size behavior, alignment behavior, or exception behavior.",
  "Runtime ABI validation checks both the x86 table shape and this ARM64 lowering shape.",
  "PMOVMSKB moves byte MSBs to a GPR; ARM64 lowering must extract and pack sign bits."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
