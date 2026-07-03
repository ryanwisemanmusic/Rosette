// PLATFORM/PCONFIG.inc
// ARM64/NEON mirror generated from ISA/x86/PLATFORM/PCONFIG.inc.

semantic = """
PCONFIG: platform configuration (TME-MK key programming).
Category: system.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PLATFORM/PCONFIG.inc"
x86_handler = "x86_pconfig"
neon_lowering = "arm64_pconfig"
lowering_kind = "arm64_documented_contract"
name = "PCONFIG"
aliases = []
category = "system"
feature = "PCONFIG"
encodings = [
  { opcode = "NP 0F 01 C5", form = "PCONFIG", op_en = "ZO", feature = "PCONFIG", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { ZO = [] }
flags_written = ["ZF", "CF", "PF", "AF", "OF", "SF"]
floating_point_exceptions = []
other_exceptions = ["#GP if unsupported leaf or invalid key programming struct", "#UD if CPL > 0 or PCONFIG not enumerated", "#PF if page fault"]
semantic_general = "Platform configuration instruction for TME-MK key programming and other platform features."
handler = "x86_pconfig"
jit_lowering = "arm64_pconfig"
fallback = "zig_pconfig"
neon_register_model = "PCONFIG is an x86 system instruction. No NEON register effect."
neon_flag_model = "ZF set on failure; all arithmetic flags cleared on success."
neon_assembly = "// NEON lowering: PCONFIG stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
