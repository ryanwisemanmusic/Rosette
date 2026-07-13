// PACK/PMULDQ.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PMULDQ.inc"
x86_handler = "x86_pmuldq"
neon_lowering = "arm64_pmuldq"
lowering_kind = "arm64_documented_contract"

name = "PMULDQ"
aliases = []
category = "pack"
feature = "SSE4_1"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "66 0F 38 28 /r", form = "PMULDQ xmm1, xmm2/m128", op_en = "RM", feature = "SSE4_1", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F38.W0 28 /r", form = "VPMULDQ xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 28 /r", form = "VPMULDQ ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W0 28 /r", form = "VPMULDQ xmm1{k}{z}, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX512F+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 28 /r", form = "VPMULDQ ymm1{k}{z}, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX512F+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 28 /r", form = "VPMULDQ zmm1{k}{z}, zmm2, zmm3/m512", op_en = "RVM", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  RVM = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Multiplies packed signed doubleword integers at odd-indexed positions (elements 1, 3, 5, ...) from two source operands and stores the signed quadword results in the destination. The even-indexed dword elements are ignored. For each pair of odd-indexed dwords, the 64-bit signed product is written to the corresponding qword position in the destination.
"""

handler = "x86_pmuldq"
jit_lowering = "arm64_pmuldq"
fallback = "zig_pmuldq"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "No x86 flags affected."
neon_assembly = "// ARM64 NEON: SMULL/SMULL2"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
