// RESTORE/XRSTORS.inc
// Source contract: XRSTORS — Restore Processor Extended States Supervisor.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RESTORE/XRSTORS.inc"
x86_handler = "x86_xrstors"
neon_lowering = "arm64_xrstors"
lowering_kind = "arm64_documented_contract"

name = "XRSTORS"
aliases = ["XRSTORS64"]
category = "system"
feature = "XSS"
element_type = "u8_u32_u64"

encodings = [
  { opcode = "NP 0F C7 /3", form = "XRSTORS mem", op_en = "M", feature = "XSS", vector_length = 0, encoding = "legacy" },
  { opcode = "NP REX.W 0F C7 /3", form = "XRSTORS64 mem", op_en = "M", feature = "XSS", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Restore processor extended states including supervisor state components
(IA32_XSS-defined) from the XSAVE/XRSTOR memory layout. Requires CPL=0.
Operand must be 64-byte aligned. Loads header and data from the save image.
"""

handler = "x86_xrstors"
jit_lowering = "arm64_xrstors"
fallback = "zig_xrstors"

neon_register_model = """
XRSTORS restores supervisor XSAVE extended state from memory. ARM64 NEON
has no direct equivalent; software emulation of the XSAVE format is required.
"""

neon_flag_model = """
XRSTORS does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated supervisor XSAVE state restore.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Must be 64-byte aligned; #GP if misaligned.",
  "CPL must be 0; #GP(0) if CPL > 0.",
  "#UD if CPUID.01H:ECX.XSAVE[bit 26] = 0, XSS not enabled, or LOCK prefix used.",
  "Header bytes 512:575 determine which supervisor state components are restored."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
