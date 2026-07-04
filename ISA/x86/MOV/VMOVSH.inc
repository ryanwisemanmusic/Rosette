// VMOVSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/VMOVSH.inc.
// Source contract: VMOVSH — Move FP16 Scalar.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/VMOVSH.inc"
x86_handler = "x86_vmovsh"
neon_lowering = "arm64_vmovsh"
lowering_kind = "arm64_documented_contract"

name = "VMOVSH"
aliases = []
category = "simd_move"
feature = "AVX512_FP16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.LLIG.F3.MAP5.W0 10 /r", form = "VMOVSH xmm1{k1}{z}, m16", op_en = "U", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.LLIG.F3.MAP5.W0 11 /r", form = "VMOVSH m16{k1}, xmm1", op_en = "U", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.LLIG.F3.MAP5.W0 10 /r", form = "VMOVSH xmm1{k1}{z}, xmm2, xmm3", op_en = "V", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.LLIG.F3.MAP5.W0 11 /r", form = "VMOVSH xmm1{k1}{z}, xmm2, xmm3", op_en = "V", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  U = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  V = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = ["None (VMOVSH is a data transfer, not an arithmetic operation)"]
other_exceptions = ["EVEX encoded instruction uses Type E1 class exception conditions"]

semantic = """
VMOVSH moves a scalar FP16 value between XMM registers and memory, or between two XMM registers (3-operand form).
"""

handler = "x86_vmovsh"
jit_lowering = "arm64_vmovsh"
fallback = "zig_vmovsh_fallback"

neon_register_model = """
The x86 register and memory operands are read from the Rosette register file. The ARM64 lowering performs the move with FP16 data-size handling.
"""

neon_flag_model = """
This lowering reads the preserved x86 architectural state exactly as listed in reads/flags_read. No ARM64 NZCV flags are modified unless this instruction explicitly writes x86 flags.
"""

neon_assembly = """
// VMOVSH: move FP16 scalar
// ARM64: MOV Vd.S[0], Wn  or  FMOV Hd, Sn  or  STR Hd, [addr]
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken x86 data-size behavior, alignment behavior, or exception behavior.",
  "Runtime ABI validation checks both the x86 table shape and this ARM64 lowering shape.",
  "VMOVSH transfers a single FP16 value; ARM64 lowering uses scalar FP16 or generalize through 32-bit container."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
