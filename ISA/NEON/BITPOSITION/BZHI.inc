// BITPOSITION/BZHI.inc
// ARM64/NEON mirror generated from ISA/x86/BITPOSITION/BZHI.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "BITPOSITION/BZHI.inc"
x86_handler = "x86_bzhi"
neon_lowering = "arm64_bzhi"
lowering_kind = "arm64_documented_contract"

name = "BZHI"
aliases = []
category = "bit_manipulation"
feature = "BMI2"
element_type = "u32_u64"
element_size = 32

encodings = [
  { opcode = "VEX.LZ.0F38.W0 F5 /r", form = "BZHI r32a, r/m32, r32b", op_en = "RMV", feature = "BMI2", vector_length = 0, encoding = "legacy" },
  { opcode = "VEX.LZ.0F38.W1 F5 /r", form = "BZHI r64a, r/m64, r64b", op_en = "RMV", feature = "BMI2", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RMV = ["ModRM:reg (w)", "ModRM:r/m (r)", "VEX.vvvv (r)"]
}

flags_written = ["CF", "ZF", "SF", "OF"]
simd_fp_exceptions = []

semantic_general = """
Zero high bits in source starting at the bit position specified by the index operand.
"""

handler = "x86_bzhi"
jit_lowering = "arm64_bzhi"
fallback = "zig_bzhi"

neon_register_model = """
BZHI is a bit_manipulation instruction.
"""

neon_flag_model = """
BZHI writes CF, ZF, SF, OF.
"""

neon_assembly = """
// NEON lowering: BFXIL/BFI on ARM64
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
