// MOV/VMOVW.inc
// ARM64/NEON mirror generated from ISA/x86/MOV/VMOVW.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/VMOVW.inc"
x86_handler = "x86_vmovw"
neon_lowering = "arm64_vmovw"
lowering_kind = "arm64_documented_contract"

// VMOVW.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/VMOVW.inc.
// Source contract: VMOVW — Move Packed FP16 Values.

name = "VMOVW"
aliases = []
category = "simd_data_transfer"
instruction_family = "MOV"
feature = "AVX512_FP16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.MAP6.W0 6F /r", form = "VMOVW xmm1{k1}{z}, m128", op_en = "RM", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.128.MAP6.W0 7F /r", form = "VMOVW m128, xmm1", op_en = "MR", feature = "AVX512_FP16", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  MR = ["ModRM:r/m (w)", "ModRM:reg (r)"]
}

lanes = { xmm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = ["EVEX encoded instruction uses Type E1 class exception conditions"]

semantic = """
VMOVW loads or stores 8 packed FP16 values (128 bits) from/to memory.
"""

semantic_load = """
DEST[127:0] = SRC[127:0];
DEST[MAXVL-1:128] = 0;
"""

semantic_store = """
DEST[127:0] = SRC[127:0];
"""

handler = "x86_vmovw"
jit_lowering = "arm64_vmovw"
fallback = "zig_vmovw_fallback"

neon_register_model = """
x86 XMM 128-bit packed FP16 values mapped into ARM64 Q register. No cross-lane operation; direct load/store.
"""

neon_flag_model = """
No x86 flags are modified by VMOVW.
"""

neon_assembly = """
// VMOVW: packed FP16 load/store
// ARM64: LDR Q0, [addr] / STR Q0, [addr]
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, MXCSR, writemask, or implicit-operand behavior.",
  "VMOVW is an AVX512-FP16 packed load/store operation; ARM64 lowering uses 128-bit LDR/STR.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
