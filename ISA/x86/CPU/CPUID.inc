// CPU/CPUID.inc
// Source contract: CPUID — CPU Identification.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CPU/CPUID.inc"
x86_handler = "x86_cpuid"
neon_lowering = "arm64_cpuid"
lowering_kind = "arm64_documented_contract"

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

handler = "x86_cpuid"
jit_lowering = "arm64_cpuid"
fallback = "zig_cpuid"

neon_register_model = """
CPUID is a x86-specific instruction. ARM64 uses MIDR_EL1, REVIDR_EL1,
CLIDR_EL1, CTR_EL0, and DCZID_EL0 for similar CPU identification.
"""

neon_flag_model = """
CPUID does not modify flags.
"""

neon_assembly = """
// NEON lowering: emulate via ARM64 system register reads or host call.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "CPUID leaf scope documented in Intel SDL Vol 2A Table 3-8.",
  "Serializing instruction: guarantees prior instruction completion.",
  "#UD if CPUID instruction not supported (EFLAGS.ID bit 21 = 0)."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
