// PACK/PHMINPOSUW.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PHMINPOSUW.inc"
x86_handler = "x86_phminposuw"
neon_lowering = "arm64_phminposuw"
lowering_kind = "arm64_documented_contract"

name = "PHMINPOSUW"
aliases = []
category = "pack"
feature = "SSE4_1"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "66 0F 38 41 /r", form = "PHMINPOSUW xmm1, xmm2/m128", op_en = "RM", feature = "SSE4_1", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F38.WIG 41 /r", form = "VPHMINPOSUW xmm1, xmm2/m128", op_en = "RM", feature = "AVX", vector_length = 128, encoding = "vex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Finds the minimum unsigned word value in the source operand (xmm2/m128) and stores both the minimum value and its index (position of the first minimum element) in the lower 32 bits of the destination xmm1 register. Bits 15:0 contain the minimum value, bits 22:16 contain the index. The upper 96 bits of xmm1 are zeroed.
"""

handler = "x86_phminposuw"
jit_lowering = "arm64_phminposuw"
fallback = "zig_phminposuw"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "No x86 flags affected."
neon_assembly = "// ARM64 NEON: sequence of MINRV + index extraction"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
