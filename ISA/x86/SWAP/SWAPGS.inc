// SWAP/SWAPGS.inc
// ARM64/NEON translation mirror generated from ISA/x86/SWAP/SWAPGS.inc.
// Source contract: SWAPGS — Exchange GS base with IA32_KERNEL_GS_BASE MSR.

semantic = """
SWAPGS: preserve the operation and form-specific semantic blocks.
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
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#GP if CPL != 0",
  "#UD if not 64-bit mode",
  "#UD if LOCK prefix"
]

semantic_general = """
Exchange GS base with IA32_KERNEL_GS_BASE MSR.
"""

handler = "x86_swapgs"
jit_lowering = "arm64_swapgs"
fallback = "zig_swapgs"

neon_register_model = """
x86 GS.base mapped to ARM64 system register.
"""

neon_flag_model = """
No x86 flags modified by SWAPGS.
"""

neon_assembly = """
// ARM64 lowering: MRS xTMP, TPIDR_EL0; MRS GS_BASE, SP_EL0; MSR SP_EL0, xTMP
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
