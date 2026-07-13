// PACK/PCMPISTRM.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PCMPISTRM.inc"
x86_handler = "x86_pcmpistrm"
neon_lowering = "arm64_pcmpistrm"
lowering_kind = "arm64_documented_contract"

name = "PCMPISTRM"
aliases = []
category = "pack"
feature = "SSE4_2"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "66 0F 3A 62 /r imm8", form = "PCMPISTRM xmm1, xmm2/m128, imm8", op_en = "RMI", feature = "SSE4_2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F3A.WIG 62 /r ib", form = "VPCMPISTRM xmm1, xmm2/m128, imm8", op_en = "RMI", feature = "AVX", vector_length = 128, encoding = "vex" }
]

operand_encoding = {
  RMI = ["ModRM:reg (r)", "ModRM:r/m (r)", "imm8"]
}

flags_written = ["CF", "ZF", "SF", "OF", "AF", "PF"]
simd_fp_exceptions = []

semantic_general = """
Performs an implicit-length (null-terminated) string comparison of two packed data arrays in xmm1 and xmm2/m128. Strings are terminated by a null character in the respective format (byte/word). The comparison operation, data format, and result format are specified by the imm8 byte. The resulting byte/word mask is written to XMM0. Flags (CF, ZF, SF, OF, AF, PF) are set to indicate the comparison result.
"""

handler = "x86_pcmpistrm"
jit_lowering = "arm64_pcmpistrm"
fallback = "zig_pcmpistrm"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "CF, ZF, SF, OF, AF, PF set according to string comparison result."
neon_assembly = "// ARM64: sequence of SIMD compare + flag synthesis"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
