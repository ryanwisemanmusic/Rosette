// VERIFY/VERR.inc
// ARM64/NEON mirror generated from ISA/x86/VERIFY/VERR.inc.

semantic = """
VERR: preserve the operation and form-specific semantic blocks.
Category: protection.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VERIFY/VERR.inc"
x86_handler = "x86_verr"
neon_lowering = "arm64_verr"
lowering_kind = "arm64_documented_contract"

name = "VERR"
aliases = []
category = "protection"
feature = "x86_gpr"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "0F 00 /4", form = "VERR r/m16", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["ZF"]
simd_fp_exceptions = []
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if source operand is a register"
]

semantic_general = """
Set ZF=1 if segment can be read.
"""

handler = "x86_verr"
jit_lowering = "arm64_verr"
fallback = "zig_verr"

neon_register_model = """
x86 GPR mapped to ARM64 xN. VERR is a scalar segment verification operation.
"""

neon_flag_model = """
ZF is set according to segment read permission check result.
"""

neon_assembly = """
// NEON lowering: segment permission check stub
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
