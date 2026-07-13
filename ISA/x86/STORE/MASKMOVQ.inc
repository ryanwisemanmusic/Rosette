// STORE/MASKMOVQ.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/MASKMOVQ.inc"
x86_handler = "x86_maskmovq"
neon_lowering = "arm64_maskmovq"
lowering_kind = "arm64_documented_contract"

name = "MASKMOVQ"
category = "masked_store"
feature = "MMX"
element_type = "integer"
element_size = 8

encodings = [
  { opcode = "NP 0F F7 /r", form = "MASKMOVQ mm1, mm2", op_en = "RM", feature = "MMX", vector_length = 64, encoding = "legacy" }
]

operand_encoding = {
  RM = ["ModRM:reg (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
MASKMOVQ: Selectively write bytes from mm1 to 64-bit memory using byte mask in mm2. Uses DS:DI/EDI/RDI addressing.
"""

handler = "x86_maskmovq"
jit_lowering = "arm64_maskmovq"
fallback = "zig_lane_loop"

neon_register_model = "x86 MMX registers mapped to ARM64 SIMD vector registers."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: bit-select + store"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
