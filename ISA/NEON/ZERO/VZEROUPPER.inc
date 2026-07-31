// Mirror: ZERO/VZEROUPPER.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ZERO/VZEROUPPER.inc"
x86_handler = "x86_vzeroupper"
neon_lowering = "arm64_vzeroupper"
lowering_kind = "arm64_documented_contract"
name = "VZEROUPPER"
aliases = []
category = "register_zero"
feature = "AVX"
encodings = [{ opcode = "VEX.128.0F.WIG 77", form = "VZEROUPPER", op_en = "ZO", vector_length = 128 }]

semantic_general = """
Zeroes bits in positions 128 and higher in YMM0-YMM15 and ZMM0-ZMM15 (64-bit mode) or YMM0-YMM7 and ZMM0-ZMM7 (outside 64-bit mode).
Preserves lower 128 bits of these registers. Does not modify ZMM16-ZMM31.
"""

flags_written = []

neon_register_model = "VZEROUPPER is an x86 SIMD upper-register zeroing operation. NEON lowering may clear upper NEON lanes."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VZEROUPPER stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
