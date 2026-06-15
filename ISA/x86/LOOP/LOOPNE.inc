// LOOP/LOOPNE.inc
// ARM64/NEON translation mirror generated from ISA/x86/LOOP/LOOPNE.inc.
// Source contract: LOOPNE — Decrement count; jump short if count != 0 and ZF = 0.

semantic = """
LOOPNE: preserve the operation and form-specific semantic blocks.
Category: branch.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOOP/LOOPNE.inc"
x86_handler = "x86_loopne"
neon_lowering = "arm64_loopne"
lowering_kind = "arm64_branch"

name = "LOOPNE"
aliases = ["LOOPNZ"]
category = "branch"
feature = "x86_gpr"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "E0 cb", form = "LOOPNE rel8", op_en = "D", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  D = ["Offset (w)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#GP if offset beyond code segment limits",
  "#UD if LOCK prefix"
]

semantic_general = """
COUNT := COUNT - 1;
IF COUNT != 0 AND ZF = 0
    THEN EIP := EIP + SignExtend(rel8);
FI;
"""

handler = "x86_loopne"
jit_lowering = "arm64_loopne"
fallback = "zig_loopne"

neon_register_model = """
x86 GPR mapped to ARM64 xN. LOOPNE decrements the count register (ECX/RCX).
"""

neon_flag_model = """
No x86 flags modified by LOOPNE; ZF is tested only.
"""

neon_assembly = """
// NEON lowering: subs xCX, xCX, #1; b.ne #target
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
