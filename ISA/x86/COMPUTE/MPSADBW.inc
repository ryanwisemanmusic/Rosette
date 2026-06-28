// COMPUTE/MPSADBW.inc
// ARM64/NEON translation mirror generated from ISA/x86/COMPUTE/MPSADBW.inc.
// Source contract: MPSADBW/VMPSADBW — Compute Multiple Packed Sums of Absolute Difference.

semantic = """
MPSADBW: preserve the operation and form-specific semantic blocks.
Category: simd_int.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COMPUTE/MPSADBW.inc"
x86_handler = "x86_mpsadbw"
neon_lowering = "arm64_mpsadbw"
lowering_kind = "arm64_documented_contract"

name = "MPSADBW"
aliases = ["VMPSADBW"]
category = "simd_int"
feature = "SSE4_1_AVX_AVX2"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "66 0F 3A 42 /r ib", form = "MPSADBW xmm1, xmm2/m128, imm8", op_en = "A", feature = "SSE4_1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.WIG 42 /r ib", form = "VMPSADBW xmm1, xmm2, xmm3/m128, imm8", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F3A.WIG 42 /r ib", form = "VMPSADBW ymm1, ymm2, ymm3/m256, imm8", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8 (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { xmm = 2, ymm = 4 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-VEX encoded instruction uses Type 4 class exception conditions",
  "VEX encoded instruction uses Type 4 class exception conditions"
]

semantic_legacy_128 = """
imm8 controls which byte positions from SRC1 and SRC2 are used in the SAD computation.
Four absolute-difference sums are computed, each over 8 byte positions.
DEST[15:0]   = SAD at offset selected by imm8[1:0] from SRC1 and imm8[3] from SRC2;
DEST[31:16]  = second SAD at offset+2;
DEST[63:32]  = 0;
DEST[127:64] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
imm8 controls byte-position offsets for four SAD results per 128-bit lane.
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
Two 128-bit lanes; each lane computes four SAD results per imm8 offsets.
DEST[MAXVL-1:256] = 0;
"""

handler = "x86_mpsadbw"
jit_lowering = "arm64_mpsadbw"
fallback = "zig_lane_loop_mpsad"

neon_register_model = """
x86 xmm/ymm byte lanes mapped to ARM64 V registers.
MPSADBW is lowered as sequential UABD + UADALP with shifts for each offset.
"""

neon_flag_model = """
No x86 flags are modified by MPSADBW/VMPSADBW.
"""

neon_assembly = """
// NEON lowering: uabd + uadalp sequence with immediate-controlled byte shifts
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, or implicit-operand behavior.",
  "The imm8 operand selects byte-offset positions; ARM64 lowering must preserve the exact x86 semantics of the four SAD results per 128-bit lane.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
