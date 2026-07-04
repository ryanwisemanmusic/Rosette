// INSERT/INSERTPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/INSERTPS.inc.
// Source contract: INSERTPS/VINSERTPS — Insert Packed Single Precision Floating-Point Value.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
INSERTPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/INSERTPS.inc"
x86_handler = "x86_insertps"
neon_lowering = "arm64_insert_f32_element"
lowering_kind = "arm64_documented_contract"

name = "INSERTPS"
aliases = ["VINSERTPS"]
category = "simd_insert"
feature = "SSE4_1_AVX_AVX512F"
element_type = "f32_packed_insert"
element_size = 32

encodings = [
  { opcode = "66 0F 3A 21 /r ib", form = "INSERTPS xmm1, xmm2/m32, imm8", op_en = "RMI", feature = "SSE4_1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.WIG 21 /r ib", form = "VINSERTPS xmm1, xmm2, xmm3/m32, imm8", op_en = "RVMI", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.128.66.0F3A.W0 21 /r ib", form = "VINSERTPS xmm1 {k1}{z}, xmm2, xmm3/m32, imm8", op_en = "C", feature = "AVX512F", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  RMI = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8"],
  RVMI = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 4 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_128 = """
COUNT_ZERO := imm8[7:6];
SELECT     := imm8[5:4];
ZERO_MASK  := imm8[3:0];
TEMP := DEST;
DEST[COUNT_ZERO*32 + 31 : COUNT_ZERO*32] := SRC[SELECT*32 + 31 : SELECT*32];
for i in 0..3:
    if ZERO_MASK[i] == 1:
        DEST[i*32 + 31 : i*32] := 0;
    else:
        DEST[i*32 + 31 : i*32] := TEMP[i*32 + 31 : i*32];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
COUNT_ZERO := imm8[7:6];
SELECT     := imm8[5:4];
ZERO_MASK  := imm8[3:0];
TEMP := SRC1;
DEST[COUNT_ZERO*32 + 31 : COUNT_ZERO*32] := SRC2[SELECT*32 + 31 : SELECT*32];
for i in 0..3:
    if ZERO_MASK[i] == 1:
        DEST[i*32 + 31 : i*32] := 0;
    else:
        DEST[i*32 + 31 : i*32] := TEMP[i*32 + 31 : i*32];
DEST[MAXVL-1:128] := 0;
"""

semantic_evex = """
COUNT_ZERO := imm8[7:6];
SELECT     := imm8[5:4];
ZERO_MASK  := imm8[3:0];
for i in 0..3:
    if k1[i] == 1 or no_writemask:
        if i == COUNT_ZERO:
            DEST[i*32 + 31 : i*32] := SRC2[SELECT*32 + 31 : SELECT*32];
        else:
            if ZERO_MASK[i] == 1:
                DEST[i*32 + 31 : i*32] := 0;
            else:
                DEST[i*32 + 31 : i*32] := SRC1[i*32 + 31 : i*32];
    else if zeroing_masking:
        DEST[i*32 + 31 : i*32] := 0;
    else:
        DEST[i*32 + 31 : i*32] unchanged;
DEST[MAXVL-1:128] := 0;
"""

handler = "x86_insertps"
jit_lowering = "arm64_insert_element"
fallback = "zig_insert_lane"

neon_register_model = """
x86 xmm 32-bit float lanes are mapped into ARM64 vector temporaries. INSERTPS inserts one float element from SRC2 into DEST at a position selected by imm8[7:6], with zero-mask control via imm8[3:0]. No MXCSR floating-point exception state is generated.
"""

neon_flag_model = """
No x86 flags are modified by INSERTPS/VINSERTPS.
"""

neon_assembly = """
ins vD.s[idx], vN.s[src_idx]
// IMM8[7:6] selects destination lane idx, IMM8[5:4] selects source element src_idx
// IMM8[3:0] zeroes specified destination lanes; implemented via bsl/movi
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
