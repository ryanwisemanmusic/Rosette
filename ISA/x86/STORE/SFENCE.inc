// STORE/SFENCE.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/SFENCE.inc"
x86_handler = "x86_sfence"
neon_lowering = "arm64_sfence"
lowering_kind = "arm64_documented_contract"

name = "SFENCE"
category = "fence"
feature = "SSE"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F AE F8", form = "SFENCE", op_en = "ZO", feature = "SSE", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
SFENCE: Serializes store operations. Ensures every store prior to SFENCE is globally visible before any store after SFENCE.
"""

handler = "x86_sfence"
jit_lowering = "arm64_sfence"
fallback = "zig_sfence"

neon_register_model = "x86 memory model mapped to ARM64."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: DMB ST"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
