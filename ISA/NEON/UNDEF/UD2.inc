// Mirror: UNDEF/UD2.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNDEF/UD2.inc"
x86_handler = "x86_ud2"
neon_lowering = "arm64_ud2"
lowering_kind = "arm64_documented_contract"
name = "UD2"
aliases = []
category = "undefined"
feature = "general"
encodings = [{ opcode = "0F 0B", form = "UD2", op_en = "ZO", vector_length = 0 }]

semantic_general = """
Generates an invalid opcode exception (#UD). No other architectural effect.
UD2 is the two-byte undefined instruction (0F 0B). The saved instruction pointer references the UD2 instruction itself.
"""

flags_written = []

neon_register_model = "UD2 is an x86 exception-raising instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: UD2 stub — raise #UD"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
