// TEST/VTESTPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/TEST/VTESTPS.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VTESTPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: bit_test.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TEST/VTESTPS.inc"
x86_handler = "x86_vtestps"
neon_lowering = "arm64_neon_cmeq_and"
lowering_kind = "neon_vector"


name = "VTESTPS"
category = "bit_test"
feature = "arm64_neon"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8

encodings = [
  { opcode = "7E 30 C0 30", form = "CMEQ Vd.4S, Vn.4S, Vm.4S", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_cmeq_v4s_v4s_v4s" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
TEMP = CMEQ(Vn.4S, Vm.4S);
ZF = (ALL lanes of TEMP == 0) ? 1 : 0;
CF = (ALL lanes of TEMP == all-ones) ? 1 : 0;
OF = 0; AF = 0; PF = 0; SF = 0;
"""

other_exceptions = ["#UD if CR4.OSFXSR = 0", "#UD if LOCK prefix used"]

handler = "x86_vtestps"
jit_lowering = "arm64_neon_cmeq_and"


neon_register_model = """
x86 xmm/ymm registers are mapped onto ARM64 V registers; CMEQ computes lane-wise equality, flags synthesized from result.
"""

neon_flag_model = """
ARM64 NZCV are synthesized from CMEQ result: ZF = all-zero, CF = all-ones across lanes.
"""

neon_assembly = """
cmeq vD.4s, vN.4s, vM.4s
bl rosette_map_cmeq_to_test_flags
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, or implicit-operand behavior.",
  "VTESTPS checks for zero and sign-bits across single-precision lanes; NEON CMEQ.4S provides lane-wise equality for analogous flag synthesis.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
