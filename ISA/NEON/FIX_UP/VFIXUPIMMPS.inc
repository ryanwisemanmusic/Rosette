// NEON/FIX_UP/VFIXUPIMMPS.inc
// ARM64/NEON translation mirror for VFIXUPIMMPS — Fix Up Special Packed Float32 Values.
// Source contract: ISA/x86/FIX_UP/VFIXUPIMMPS.inc

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VFIXUPIMMPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_fixup.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FIX_UP/VFIXUPIMMPS.inc"
x86_handler = "x86_vfixupimmps"
neon_lowering = "arm64_vfixupimmps"
lowering_kind = "neon_vector"

name = "VFIXUPIMMPS"
aliases = []
category = "simd_fixup"
feature = "AVX512F_AVX512VL"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 54 /r ib", form = "VFIXUPIMMPS xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst, imm8", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F3A.W0 54 /r ib", form = "VFIXUPIMMPS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst, imm8", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F3A.W0 54 /r ib", form = "VFIXUPIMMPS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = ["Zero", "Invalid"]
other_exceptions = [
  "See Table 2-46, Type E2 Class Exception Conditions."
]

semantic_evex_128 = """
(KL, VL) = (4, 128)
FOR j := 0 TO KL-1
    i := j * 32
    CASE(imm8[3:0]) OF
        0: DEST[i+31:i] := QNaN
        1: DEST[i+31:i] := -INF
        2: DEST[i+31:i] := INF
        3: DEST[i+31:i] := -0.0
        4: DEST[i+31:i] := 0.0
        5: DEST[i+31:i] := -1.0
        6: DEST[i+31:i] := 1.0
        7: DEST[i+31:i] := 0.5
        8: DEST[i+31:i] := 90.0
        9: DEST[i+31:i] := -2.0
        10..15: DEST[i+31:i] := SRC2[i+31:i]
    ESAC
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_256 = """
(KL, VL) = (8, 256)
FOR j := 0 TO KL-1
    i := j * 32
    CASE(imm8[3:0]) OF
        0: DEST[i+31:i] := QNaN
        1: DEST[i+31:i] := -INF
        2: DEST[i+31:i] := INF
        3: DEST[i+31:i] := -0.0
        4: DEST[i+31:i] := 0.0
        5: DEST[i+31:i] := -1.0
        6: DEST[i+31:i] := 1.0
        7: DEST[i+31:i] := 0.5
        8: DEST[i+31:i] := 90.0
        9: DEST[i+31:i] := -2.0
        10..15: DEST[i+31:i] := SRC2[i+31:i]
    ESAC
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_512 = """
(KL, VL) = (16, 512)
FOR j := 0 TO KL-1
    i := j * 32
    CASE(imm8[3:0]) OF
        0: DEST[i+31:i] := QNaN
        1: DEST[i+31:i] := -INF
        2: DEST[i+31:i] := INF
        3: DEST[i+31:i] := -0.0
        4: DEST[i+31:i] := 0.0
        5: DEST[i+31:i] := -1.0
        6: DEST[i+31:i] := 1.0
        7: DEST[i+31:i] := 0.5
        8: DEST[i+31:i] := 90.0
        9: DEST[i+31:i] := -2.0
        10..15: DEST[i+31:i] := SRC2[i+31:i]
    ESAC
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_vfixupimmps"
jit_lowering = "arm64_vfixupimmps"
fallback = "zig_lane_loop_fixup_32"

neon_register_model = """
x86 xmm/ymm/zmm bit lanes are mapped into ARM64 vector temporaries. VFIXUPIMMPS is a per-lane fixup using imm8 action encoding. Broadcast from 32-bit memory is supported.
"""

neon_flag_model = """
No x86 flags are modified by VFIXUPIMMPS.
"""

neon_assembly = """
// NEON lowering: per-lane fixup using imm8 action encoding
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
