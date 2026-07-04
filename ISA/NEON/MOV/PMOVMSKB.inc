// MOV/PMOVMSKB.inc
// ARM64/NEON mirror generated from ISA/x86/MOV/PMOVMSKB.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/PMOVMSKB.inc"
x86_handler = "x86_pmovmskb"
neon_lowering = "arm64_pmovmskb"
lowering_kind = "arm64_documented_contract"

// PMOVMSKB.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/PMOVMSKB.inc.
// Source contract: PMOVMSKB/VPMOVMSKB — Move Byte Mask to GPR.

name = "PMOVMSKB"
aliases = ["VPMOVMSKB"]
category = "simd_data_transfer"
instruction_family = "MOV"
feature = "SSE_SSE2_AVX_AVX2"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "0F D7 /r", form = "PMOVMSKB r32, mm", op_en = "RM", feature = "SSE", vector_length = 64, encoding = "legacy_mmx" },
  { opcode = "66 0F D7 /r", form = "PMOVMSKB r32, xmm", op_en = "RM", feature = "SSE2", vector_length = 128, encoding = "legacy_sse2" },
  { opcode = "VEX.128.66.0F D7 /r", form = "VPMOVMSKB r32, xmm", op_en = "RM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F D7 /r", form = "VPMOVMSKB r32, ymm", op_en = "RM", feature = "AVX2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { mm = 8, xmm = 16, ymm = 32 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = ["#UD if CR0.EM or CR4.OSFXSR not set for SSE encodings"]

semantic = """
GPR[7:0] = each MSB of SIMD register byte lanes packed into consecutive GPR bits.
"""

semantic_legacy_mmx = """
For j in 0..7:
    i = j * 8;
    r32[j] = mm[i+7];
r32[31:8] = 0;
"""

semantic_legacy_sse2 = """
For j in 0..15:
    i = j * 8;
    r32[j] = xmm[i+7];
r32[31:16] = 0;
"""

semantic_vex_128 = """
For j in 0..15:
    i = j * 8;
    r32[j] = xmm[i+7];
r32[31:16] = 0;
"""

semantic_vex_256 = """
For j in 0..31:
    i = j * 8;
    r32[j] = ymm[i+7];
r32[31:32] = 0;
"""

handler = "x86_pmovmskb"
jit_lowering = "arm64_pmovmskb"
fallback = "zig_pmovmskb_fallback"

neon_register_model = """
x86 MMX/XMM/YMM byte lanes are mapped into ARM64 vector temporaries. The most significant bit of each byte (bit 7) is extracted and packed into a GPR.
"""

neon_flag_model = """
No x86 flags are modified by PMOVMSKB/VPMOVMSKB.
"""

neon_assembly = """
// PMOVMSKB: pack MSB of each byte lane into GPR
// ARM64: SSHR + AND + ORR reduction to extract 8/16/32 sign bits
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "PMOVMSKB extracts MSB from each byte of a vector and packs bits into a GPR; ARM64 lowering uses vector shift and reduction.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
