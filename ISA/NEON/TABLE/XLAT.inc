// TABLE/XLAT.inc
// ARM64/NEON mirror generated from ISA/x86/TABLE/XLAT.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TABLE/XLAT.inc"
x86_handler = "x86_xlat"
neon_lowering = "arm64_xlat"
lowering_kind = "arm64_documented_contract"

name = "XLAT"
aliases = ["XLATB"]
category = "table_lookup"
feature = "base"
element_type = "integer"
element_size = 8

encodings = [
  { opcode = "D7", form = "XLAT m8", op_en = "ZO", feature = "base", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Locates a byte entry in a table in memory using the contents of AL as a table index,
then copies the contents of the table entry back into AL. Table base address is DS:(E)BX (or RBX in 64-bit mode).
"""

handler = "x86_xlat"
jit_lowering = "arm64_xlat"
fallback = "zig_xlat"

neon_register_model = "x86 RBX holds the table base and AL the index; both map to ARM64 general-purpose registers. AL is zero-extended to a full register before it is used as an offset, so the index is unsigned and never sign-extends into the base."
neon_flag_model = "No flags are read or written. ARM64 NZCV is left untouched, matching the x86 contract that XLAT affects no flags."
neon_assembly = "// ARM64: AND xIDX, xAL, #0xFF ; LDRB wDST, [xBX, xIDX] ; BFI xAL, xDST, #0, #8"
neon_notes = [
  "The register-offset LDRB form is the direct ARM64 equivalent of the x86 base-plus-index byte load.",
  "Only AL is written; the upper bits of RAX are preserved, which is why the store back is a bitfield insert rather than a full register move.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
