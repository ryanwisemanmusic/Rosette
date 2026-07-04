// FIX_UP/VFIXUPIMMPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/FIX_UP/VFIXUPIMMPD.inc.
// Source contract: VFIXUPIMMPD — Fix Up Special Packed Float64 Values.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VFIXUPIMMPD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_fixup.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FIX_UP/VFIXUPIMMPD.inc"
x86_handler = "x86_vfixupimmpd"
neon_lowering = "arm64_vfixupimmpd"
lowering_kind = "neon_vector"

name = "VFIXUPIMMPD"
aliases = []
category = "simd_fixup"
feature = "AVX512F_AVX512VL"
element_type = "f64"
element_size = 64

// NEON lowering notes for VFIXUPIMMPD
// The imm8 fix-up classes map to ARM64 compare-and-select chains.
// Float64 special value detection requires explicit NaN/Inf/class testing via fcsel.

neon_notes = [
  "ARM64 NEON has no direct fix-up instruction; lowering uses comparison chains.",
  "Fully preserving MXCSR status bits and SSE exception behavior requires software emulation.",
  "Writing mask behavior is lowered via bit-select (bsl) with k register replication.",
  "The imm8 operand is encoded into a sequence of fcsel/fcmeq/fmin/fmax operations."
]

neon_register_model = """
ARM64 NEON V registers map directly to x86 xmm/ymm/zmm lanes for 128-bit (2x f64)
and require concatenation for 256-bit (4x f64) and 512-bit (8x f64).
"""

neon_flag_model = """
No x86 flags are modified by VFIXUPIMMPD on ARM64.
"""

neon_assembly = """
// ARM64 NEON lowering for VFIXUPIMMPD (packed f64 fix-up):
// 1. Detect special classes in src1 (QNaN, SNaN, -Inf, -Max)
// 2. Apply imm8 action selectors per class
// 3. Merge results using writemask if k1 is active
// Broadcast support: replicate f64 scalar from memory across all lanes
"""
