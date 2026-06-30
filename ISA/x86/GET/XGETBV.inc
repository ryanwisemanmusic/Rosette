// GET/XGETBV.inc
// Source contract: XGETBV — Get Value of Extended Control Register.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GET/XGETBV.inc"
x86_handler = "x86_xgetbv"
neon_lowering = "arm64_xgetbv"
lowering_kind = "arm64_documented_contract"

name = "XGETBV"
aliases = []
category = "xcr_read"
feature = "xsave"

encodings = [
  { opcode = "NP 0F 01 D0", form = "XGETBV", op_en = "ZO", feature = "xsave", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A", "N/A", "N/A", "N/A"]
}

lanes = { gpr = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = [
  "#GP(0) If an invalid XCR is specified in ECX",
  "#UD If CPUID.01H:ECX.XSAVE[bit 26] = 0.",
  "#UD If CR4.OSXSAVE[bit 18] = 0.",
  "#UD If the LOCK prefix is used."
]

semantic_general = """
Reads the contents of the extended control register (XCR) specified in ECX into EDX:EAX.
"""

handler = "x86_xgetbv"
jit_lowering = "arm64_xgetbv"
fallback = "zig_xgetbv"

neon_register_model = """
XGETBV is an x86 XCR read instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
None.
"""

neon_assembly = """
// NEON lowering: XGETBV stub (XCR read)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
