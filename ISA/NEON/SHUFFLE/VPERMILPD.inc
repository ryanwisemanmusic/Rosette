// SHUFFLE/VPERMILPD.inc
// ARM64/NEON mirror of ISA/x86/SHUFFLE/VPERMILPD.inc.

semantic = """
Select packed 64-bit elements from each source 128-bit lane under immediate control.
"""
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHUFFLE/VPERMILPD.inc"
x86_handler = "x86_vpermilpd"
neon_lowering = "arm64_vpermilpd"
lowering_kind = "neon_lane_permute"
name = "VPERMILPD"
aliases = []
category = "shuffle"
feature = "AVX"
element_type = "f64"
element_size = 64
encodings = [
  { opcode = "VEX.128.66.0F3A.W0 05 /r ib", form = "VPERMILPD xmm1, xmm2/m128, imm8", op_en = "A", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F3A.W0 05 /r ib", form = "VPERMILPD ymm1, ymm2/m256, imm8", op_en = "A", feature = "AVX", vector_length = 256, encoding = "vex" }
]
operand_encoding = { A = ["ModRM:reg (w)", "ModRM:r/m (r)", "imm8"] }
lanes = { xmm = 2, ymm = 4, zmm = 0 }
flags_written = []
simd_fp_exceptions = ["None"]
semantic_general = """
Each immediate bit selects one of two doubles in the corresponding 128-bit source lane. No selection crosses a lane boundary.
"""
handler = "x86_vpermilpd"
jit_lowering = "arm64_vpermilpd"
fallback = "zig_vpermilpd"
neon_register_model = """
Map each x86 128-bit lane to a NEON vector and select 64-bit lanes with TBL or lane moves.
"""
neon_flag_model = """
VPERMILPD does not modify x86 flags.
"""
neon_assembly = """
// Lane-local TBL/INS sequence selected from imm8.
"""
neon_notes = ["Runtime ABI validation rejects cross-lane selection and preserves VEX upper-state semantics."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
