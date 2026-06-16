// VERIFY/VERW.inc
// ARM64/NEON translation mirror generated from ISA/x86/VERIFY/VERW.inc.
// Source contract: VERW — Verify a Segment for Writing.

semantic = """
VERW: Set ZF=1 if segment can be written.
Category: protection.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VERIFY/VERW.inc"
x86_handler = "x86_verw"
neon_lowering = "arm64_verw"
lowering_kind = "arm64_scalar"

name = "VERW"
aliases = []
category = "protection"
feature = "x86_gpr"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "0F 00 /5", form = "VERW r/m16", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["ZF"]
simd_fp_exceptions = []
other_exceptions = [
  "#GP if segment/selector invalid",
  "#UD if LOCK prefix"
]

semantic_general = """
ZF := IsSegmentWritable(SRC);
"""

handler = "x86_verw"
jit_lowering = "arm64_verw"
fallback = "zig_verw"

neon_register_model = """
x86 GPR mapped to ARM64 xN. VERW is a scalar protection-check operation.
"""

neon_flag_model = """
ZF is computed in ARM64 NZCV based on segment writability.
"""

neon_assembly = """
// NEON lowering: validate segment descriptor writability via ARM64 system register access
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
