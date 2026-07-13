// PACK/PCMPESTRI.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PCMPESTRI.inc"
x86_handler = "x86_pcmpestri"
neon_lowering = "arm64_pcmpestri"
lowering_kind = "arm64_documented_contract"

name = "PCMPESTRI"
aliases = []
category = "pack"
feature = "SSE4_2"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "66 0F 3A 61 /r imm8", form = "PCMPESTRI xmm1, xmm2/m128, imm8", op_en = "RMI", feature = "SSE4_2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F3A 61 /r ib", form = "VPCMPESTRI xmm1, xmm2/m128, imm8", op_en = "RMI", feature = "AVX", vector_length = 128, encoding = "vex" }
]

operand_encoding = {
  RMI = ["ModRM:reg (r)", "ModRM:r/m (r)", "imm8"]
}

flags_written = ["CF", "ZF", "SF", "OF", "AF", "PF"]
simd_fp_exceptions = []

semantic_general = """
Performs an explicit-length string comparison of two packed data arrays in xmm1 and xmm2/m128. Array lengths are specified in EAX and EDX. The comparison operation, data format (byte/word), and result polarity are specified by the imm8 byte. The result index is stored in ECX. Flags (CF, ZF, SF, OF, AF, PF) are set to indicate the comparison result according to the imm8 polarity field.
"""

handler = "x86_pcmpestri"
jit_lowering = "arm64_pcmpestri"
fallback = "zig_pcmpestri"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "CF, ZF, SF, OF, AF, PF set according to string comparison result."
neon_assembly = "// ARM64: sequence of SIMD compare + flag synthesis"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
