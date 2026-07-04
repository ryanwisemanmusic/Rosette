// SHUFFLE/VPUNPCKLDQ.inc
// ARM64/NEON mirror of ISA/x86/SHUFFLE/VPUNPCKLDQ.inc.

semantic = """
Interleave the low two packed 32-bit elements from each source within every 128-bit lane.
"""
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHUFFLE/VPUNPCKLDQ.inc"
x86_handler = "x86_vpunpckldq"
neon_lowering = "arm64_vpunpckldq"
lowering_kind = "neon_vector_zip"
name = "VPUNPCKLDQ"
aliases = ["PUNPCKLDQ"]
category = "shuffle"
feature = "AVX"
element_type = "i32"
element_size = 32
encodings = [
  { opcode = "VEX.128.66.0F.WIG 62 /r", form = "VPUNPCKLDQ xmm1, xmm2, xmm3/m128", op_en = "A", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 62 /r", form = "VPUNPCKLDQ ymm1, ymm2, ymm3/m256", op_en = "A", feature = "AVX2", vector_length = 256, encoding = "vex" }
]
operand_encoding = { A = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"] }
lanes = { xmm = 4, ymm = 8, zmm = 0 }
flags_written = []
simd_fp_exceptions = ["None"]
semantic_general = """
For each 128-bit lane, DEST receives SRC1.dword[0], SRC2.dword[0], SRC1.dword[1], SRC2.dword[1].
The VEX.128 form clears the upper destination state; the VEX.256 form applies independently to both lanes.
"""
handler = "x86_vpunpckldq"
jit_lowering = "arm64_vpunpckldq"
fallback = "zig_vpunpckldq"
neon_register_model = """
XMM and YMM values map to one or two 128-bit NEON lanes; each lane uses ZIP1 on 32-bit elements.
"""
neon_flag_model = """
VPUNPCKLDQ does not modify x86 flags.
"""
neon_assembly = """
// ZIP1 Vd.4S, Vn.4S, Vm.4S independently for every 128-bit lane.
"""
neon_notes = ["Runtime ABI validation preserves lane-local interleaving and upper-lane clearing semantics."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
