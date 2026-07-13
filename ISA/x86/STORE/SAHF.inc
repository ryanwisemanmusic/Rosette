// STORE/SAHF.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/SAHF.inc"
x86_handler = "x86_sahf"
neon_lowering = "arm64_sahf"
lowering_kind = "arm64_documented_contract"

name = "SAHF"
category = "flag_store"
feature = "8086"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "9E", form = "SAHF", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

flags_written = ["SF", "ZF", "AF", "PF", "CF"]
simd_fp_exceptions = []

semantic_general = """
SAHF: Loads SF, ZF, AF, PF, and CF flags from AH register.
"""

handler = "x86_sahf"
jit_lowering = "arm64_sahf"
fallback = "zig_sahf"

neon_register_model = "x86 GP registers mapped to ARM64 X registers."
neon_flag_model = "SF, ZF, AF, PF, CF loaded from AH bits via ARM64 flag synthesis."
neon_assembly = "// ARM64: flag load from X register"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
