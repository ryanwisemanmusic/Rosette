// NEON/CPU/CPUID.inc
// ARM64/NEON translation mirror generated from ISA/x86/CPU/CPUID.inc.
// Source contract: CPUID — CPU Identification.

semantic = """
Returns processor identification and feature information.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "CPUID"
aliases = []
category = "cpu_identification"
feature = "CPUID"
element_type = "u32"

encodings = [
  { opcode = "0F A2", form = "CPUID", op_en = "ZO", feature = "CPUID", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Returns processor identification and feature information to EAX, EBX, ECX, EDX
as determined by input in EAX (and ECX for sub-leaves). Serializing instruction.
"""

neon_register_model = """
CPUID is x86-specific. ARM64 uses MIDR_EL1, REVIDR_EL1, etc.
"""

neon_flag_model = """
CPUID does not modify flags.
"""

neon_assembly = """
// NEON lowering: emulate via ARM64 system register reads.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."
]
