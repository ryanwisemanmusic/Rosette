// STORE/MASKMOVDQU.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/MASKMOVDQU.inc"
x86_handler = "x86_maskmovdqu"
neon_lowering = "arm64_maskmovdqu"
lowering_kind = "arm64_documented_contract"

name = "MASKMOVDQU"
category = "masked_store"
feature = "SSE2_AVX"
element_type = "integer"
element_size = 8

encodings = [
  { opcode = "66 0F F7 /r", form = "MASKMOVDQU xmm1, xmm2", op_en = "RM", feature = "SSE2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F.WIG F7 /r", form = "VMASKMOVDQU xmm1, xmm2", op_en = "RM", feature = "AVX", vector_length = 128, encoding = "vex" }
]

operand_encoding = {
  RM = ["ModRM:reg (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
MASKMOVDQU/VMASKMOVDQU: Selectively write bytes from xmm1 to memory using byte mask in xmm2. Uses DS:DI/EDI/RDI addressing.
"""

handler = "x86_maskmovdqu"
jit_lowering = "arm64_maskmovdqu"
fallback = "zig_lane_loop"

neon_register_model = "x86 XMM registers mapped to ARM64 SIMD vector registers."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: bit-select + store"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
