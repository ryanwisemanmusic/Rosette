// MOV/VMOVSH.inc
// ARM64/NEON mirror generated from ISA/x86/MOV/VMOVSH.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/VMOVSH.inc"
x86_handler = "x86_vmovsh"
neon_lowering = "arm64_vmovsh"
lowering_kind = "arm64_documented_contract"

// VMOVSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/VMOVSH.inc.
// Source contract: VMOVSH — Move FP16 Scalar Value.

name = "VMOVSH"
aliases = []
category = "simd_data_transfer"
instruction_family = "MOV"
feature = "AVX512_FP16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.MAP5.W0 10 /r", form = "VMOVSH xmm1{k1}{z}, m16", op_en = "RM", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.128.MAP5.W0 11 /r", form = "VMOVSH m16, xmm1", op_en = "MR", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.128.MAP5.W0 10 /r", form = "VMOVSH xmm1{k1}{z}, xmm2, xmm3", op_en = "C", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.128.MAP5.W0 11 /r", form = "VMOVSH xmm1{k1}{z}, xmm2, xmm3", op_en = "C", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  MR = ["ModRM:r/m (w)", "ModRM:reg (r)"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 1 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = ["EVEX encoded instruction uses Type E1 class exception conditions"]

semantic = """
VMOVSH moves a scalar FP16 value between XMM registers, or between XMM registers and memory.
"""

semantic_load = """
DEST[15:0] = SRC[15:0];
DEST[127:16] unchanged;
DEST[MAXVL-1:128] = 0;
"""

semantic_store = """
DEST[15:0] = SRC[15:0];
"""

semantic_3op = """
DEST[15:0] = SRC2[15:0];
DEST[127:16] = SRC1[127:16];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_vmovsh"
jit_lowering = "arm64_vmovsh"
fallback = "zig_vmovsh_fallback"

neon_register_model = """
x86 XMM scalar FP16 values mapped into ARM64 vector register lower 16 bits. Upper bits preserved per x86 merge semantics.
"""

neon_flag_model = """
No x86 flags are modified by VMOVSH.
"""

neon_assembly = """
// VMOVSH: scalar FP16 move
// ARM64: LDRH/STRH for memory; INS for vector-to-vector element move
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VMOVSH is an AVX512-FP16 scalar operation; ARM64 lowering uses scalar FP16 or 16-bit element insertion.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
