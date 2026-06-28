// RESTORE/XRSTOR.inc
// Source contract: XRSTOR — Restore Processor Extended States.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RESTORE/XRSTOR.inc"
x86_handler = "x86_xrstor"
neon_lowering = "arm64_xrstor"
lowering_kind = "arm64_documented_contract"

name = "XRSTOR"
aliases = ["XRSTOR64"]
category = "system"
feature = "XSAVE"
element_type = "u8_u32_u64"

encodings = [
  { opcode = "NP 0F AE /5", form = "XRSTOR mem", op_en = "M", feature = "XSAVE", vector_length = 0, encoding = "legacy" },
  { opcode = "NP REX.W 0F AE /5", form = "XRSTOR64 mem", op_en = "M", feature = "XSAVE", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Restore processor extended states (XCR0-defined state components including
x87, SSE, AVX, MPX, AVX-512, etc.) from the XSAVE/XRSTOR memory layout.
Operand must be 64-byte aligned. Loads header and data from the save image.
"""

handler = "x86_xrstor"
jit_lowering = "arm64_xrstor"
fallback = "zig_xrstor"

neon_register_model = """
XRSTOR restores XSAVE extended state from memory. ARM64 NEON has no direct
equivalent; software emulation of the XSAVE format is required.
"""

neon_flag_model = """
XRSTOR does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated XSAVE extended state restore from memory.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Must be 64-byte aligned; #GP if misaligned.",
  "#NM if CR0.TS = 1.",
  "#UD if CPUID.01H:ECX.XSAVE[bit 26] = 0 or LOCK prefix used.",
  "Header bytes 512:575 determine which state components are restored."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
