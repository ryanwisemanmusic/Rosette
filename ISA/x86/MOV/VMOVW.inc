// VMOVW.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/VMOVW.inc.
// Source contract: VMOVW — Move Word (16-bit) to/from XMM Register.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/VMOVW.inc"
x86_handler = "x86_vmovw"
neon_lowering = "arm64_vmovw"
lowering_kind = "arm64_documented_contract"

name = "VMOVW"
aliases = []
category = "simd_move"
feature = "AVX512_FP16"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.MAP5.WIG 6E /r", form = "VMOVW xmm1, reg/m16", op_en = "RM", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.128.66.MAP5.WIG 7E /r", form = "VMOVW reg/m16, xmm1", op_en = "MR", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  MR = ["ModRM:r/m (w)", "ModRM:reg (r)"]
}

flags_written = []
simd_fp_exceptions = ["None (VMOVW is a data transfer, not an arithmetic operation)"]
other_exceptions = ["EVEX encoded instruction uses Type E1 class exception conditions"]

semantic = """
VMOVW moves a 16-bit word between a GPR or memory and an XMM register. The upper bits of the XMM register remain unchanged.
"""

handler = "x86_vmovw"
jit_lowering = "arm64_vmovw"
fallback = "zig_vmovw_fallback"

neon_register_model = """
The x86 register and memory operands are read from the Rosette register file. The ARM64 lowering performs the move with 16-bit data-size handling.
"""

neon_flag_model = """
This lowering reads the preserved x86 architectural state exactly as listed in reads/flags_read. No ARM64 NZCV flags are modified unless this instruction explicitly writes x86 flags.
"""

neon_assembly = """
// VMOVW: move 16-bit word between GPR and XMM
// ARM64: FMOV H0, Wn  or  MOV W0, V0.h[0]  or  INS v0.h[0], Wn
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken x86 data-size behavior, alignment behavior, or exception behavior.",
  "Runtime ABI validation checks both the x86 table shape and this ARM64 lowering shape.",
  "VMOVW transfers 16 bits between GPR and XMM registers; ARM64 FMOV Hd, Wn / MOV Wd, Vn.h[0]."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
