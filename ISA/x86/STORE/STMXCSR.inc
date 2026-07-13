// STORE/STMXCSR.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/STMXCSR.inc"
x86_handler = "x86_stmxcsr"
neon_lowering = "arm64_stmxcsr"
lowering_kind = "arm64_documented_contract"

name = "STMXCSR"
category = "system_store"
feature = "SSE_AVX"
element_type = "integer"
element_size = 32

encodings = [
  { opcode = "NP 0F AE /3", form = "STMXCSR m32", op_en = "M", feature = "SSE", vector_length = 0, encoding = "legacy" },
  { opcode = "VEX.LZ.0F.WIG AE /3", form = "VSTMXCSR m32", op_en = "M", feature = "AVX", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
STMXCSR/VSTMXCSR: Stores contents of MXCSR control and status register to 32-bit memory location.
"""

handler = "x86_stmxcsr"
jit_lowering = "arm64_stmxcsr"
fallback = "zig_stmxcsr"

neon_register_model = "x86 MXCSR mapped to ARM64 FPCR/FPSR."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: MRS FPCR/FPSR"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
