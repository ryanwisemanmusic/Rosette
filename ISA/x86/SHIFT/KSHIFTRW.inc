// SHIFT/KSHIFTRW.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/KSHIFTRW.inc"
x86_handler = "x86_kshiftrw"
neon_lowering = "arm64_kshiftrw"
lowering_kind = "arm64_documented_contract"

name = "KSHIFTRW"
category = "mask_shift"
feature = "AVX512F"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "VEX.L0.66.0F3A.W1 30 /r", form = "KSHIFTRW k1, k2, imm8", op_en = "RRI", feature = "AVX512F", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RRI = ["ModRM:reg (w)", "ModRM:r/m (r, ModRM:[7:6] must be 11b)", "imm8"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
KSHIFTRW: Shift right 16 bits in mask register k2 by immediate, zero-extend result to k1.
"""

handler = "x86_kshiftrw"
jit_lowering = "arm64_kshiftrw"
fallback = "zig_kshiftrw"

neon_register_model = "x86 mask registers (k1-k7) mapped to ARM64 SIMD vector registers."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: shift-right via SIMD immediate shift"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
