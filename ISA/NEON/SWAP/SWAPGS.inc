// SWAP/SWAPGS.inc
// ARM64/NEON mirror generated from ISA/x86/SWAP/SWAPGS.inc.

semantic = """
SWAPGS: exchange GS base MSR (KERNEL_GS_BASE) with the currently loaded GS base.
Category: system.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SWAP/SWAPGS.inc"
x86_handler = "x86_swapgs"
neon_lowering = "arm64_swapgs"
lowering_kind = "arm64_swapgs"

name = "SWAPGS"
aliases = []
category = "system"
feature = "x86_gpr_64"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "0F 01 F8", form = "SWAPGS", op_en = "ZO", feature = "x86_gpr_64", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if CPL != 0",
  "#GP(0) if not in 64-bit mode"
]

semantic_general = """
SWAPGS exchanges the current GS base register with the MSR KERNEL_GS_BASE.
Used by system software to swap between kernel and user GS base on entry/exit.
"""

handler = "x86_swapgs"
jit_lowering = "arm64_swapgs"
fallback = "zig_swapgs"

neon_register_model = """
ARM64: x86 GS base → TPIDR_EL1. SWAPGS reads TPIDR_EL1, swaps with KERNEL_GS_BASE stored in a reserved general-purpose register (or emulated MSR shadow).
"""

neon_flag_model = """
No x86 flags modified by SWAPGS.
"""

neon_assembly = """
// NEON lowering: mrs xTMP, tpidr_el1; msr tpidr_el1, xTMP; (swap GS base stub)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "TPIDR_EL1 is used as the canonical ARM64 shadow of the x86 GS segment base."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
