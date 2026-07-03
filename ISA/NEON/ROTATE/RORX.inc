// ROTATE/RORX.inc
// ARM64/NEON mirror generated from ISA/x86/ROTATE/RORX.inc.
name = "RORX"
category = "bit_rotate"
feature = "BMI2"
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ROTATE/RORX.inc"
x86_handler = "x86_rorx"
neon_lowering = "arm64_ror"
lowering_kind = "arm64_documented_contract"
aliases = []
encodings = [
  { opcode = "VEX.LZ.F2.0F3A.W0 F0 /r ib", form = "RORX r32, r/m32, imm8", op_en = "RMI", feature = "BMI2", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.LZ.F2.0F3A.W1 F0 /r ib", form = "RORX r64, r/m64, imm8", op_en = "RMI", feature = "BMI2", vector_length = 0, encoding = "vex" }
]
operand_encoding = { RMI = ["ModRM:reg (w)", "ModRM:r/m (r)", "imm8"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#UD if VEX.L != 0", "#UD if VEX.vvvv != 1111B"]
semantic_general = "Rotate right logical without affecting flags."
handler = "x86_rorx"
jit_lowering = "arm64_ror"
fallback = "zig_rorx"
neon_register_model = "RORX is a BMI2 GPR rotate instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RORX stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
