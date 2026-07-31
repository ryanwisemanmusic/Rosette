// TEST/PTEST.inc
// ARM64/NEON translation mirror generated from ISA/x86/TEST/PTEST.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PTEST: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: bit_test.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TEST/PTEST.inc"
x86_handler = "x86_ptest"
neon_lowering = "arm64_neon_cmeq_and"
lowering_kind = "neon_vector"


name = "PTEST"
category = "bit_test"
feature = "arm64_neon"
element_type = "i128"
legacy_width = 128

encodings = [
  { opcode = "66 0F 38 17 /r", form = "PTEST xmm1, xmm2/m128", op_en = "RM", feature = "SSE4_1", mode = "V/V", handler = "x86_ptest_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F38.W0 17 /r", form = "VPTEST xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vptest_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F38.W0 17 /r", form = "VPTEST ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vptest_ymm_ymm_ymmm256" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
TEMP = CMEQ(Vn.16B, Vm.16B);
ZF = (ALL lanes of TEMP == 0) ? 1 : 0;
CF = (ANY lane of TEMP == 0xFF) ? 1 : 0;
OF = 0; AF = 0; PF = 0; SF = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["#UD if CR4.OSFXSR = 0", "#UD if LOCK prefix used"]

handler = "x86_ptest"
jit_lowering = "arm64_neon_cmeq_and"


neon_register_model = """
x86 xmm registers are mapped onto ARM64 V registers; CMEQ computes byte-wise equality, ANDV reduces across lanes.
"""

neon_flag_model = """
ARM64 NZCV are synthesized from CMEQ result: ZF = all-zero, CF = any-equal.
"""

neon_assembly = """
cmeq vD.16b, vN.16b, vM.16b
bl rosette_map_cmeq_to_test_flags
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "PTEST checks for zero and sign-bits; NEON CMEQ provides byte-wise equality comparison for analogous flag synthesis.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
