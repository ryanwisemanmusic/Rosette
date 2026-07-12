// PERMUTE/VPERMILPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/PERMUTE/VPERMILPS.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPERMILPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_permute_single.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERMUTE/VPERMILPS.inc"
x86_handler = "x86_vpermilps"
neon_lowering = "arm64_neon_tbl1"
lowering_kind = "neon_vector"


name = "VPERMILPS"
category = "simd_float_permute_single"
feature = "AVX"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16
mxcsr_used = true

encodings = [
  { opcode = "0E 30 80 30 TBL Vd.16B, {Vn.16B}, Vm.16B", form = "VPERMILPS Vd.4S, Vn.4S, Vm.4S", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_neon_tbl1" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.f32[0] = (imm8[1:0]==0) ? SRC.f32[0] : (imm8[1:0]==1) ? SRC.f32[1] : (imm8[1:0]==2) ? SRC.f32[2] : SRC.f32[3];
DEST.f32[1] = (imm8[3:2]==0) ? SRC.f32[0] : (imm8[3:2]==1) ? SRC.f32[1] : (imm8[3:2]==2) ? SRC.f32[2] : SRC.f32[3];
DEST.f32[2] = (imm8[5:4]==0) ? SRC.f32[0] : (imm8[5:4]==1) ? SRC.f32[1] : (imm8[5:4]==2) ? SRC.f32[2] : SRC.f32[3];
DEST.f32[3] = (imm8[7:6]==0) ? SRC.f32[0] : (imm8[7:6]==1) ? SRC.f32[1] : (imm8[7:6]==2) ? SRC.f32[2] : SRC.f32[3];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_128 = """
DEST.f32[0] = (imm8[1:0]==0) ? SRC1.f32[0] : (imm8[1:0]==1) ? SRC1.f32[1] : (imm8[1:0]==2) ? SRC1.f32[2] : SRC1.f32[3];
DEST.f32[1] = (imm8[3:2]==0) ? SRC1.f32[0] : (imm8[3:2]==1) ? SRC1.f32[1] : (imm8[3:2]==2) ? SRC1.f32[2] : SRC1.f32[3];
DEST.f32[2] = (imm8[5:4]==0) ? SRC1.f32[0] : (imm8[5:4]==1) ? SRC1.f32[1] : (imm8[5:4]==2) ? SRC1.f32[2] : SRC1.f32[3];
DEST.f32[3] = (imm8[7:6]==0) ? SRC1.f32[0] : (imm8[7:6]==1) ? SRC1.f32[1] : (imm8[7:6]==2) ? SRC1.f32[2] : SRC1.f32[3];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for each 128-bit lane (i=0,1):
    DEST.f32[i*4+0] = (imm8[1:0]==0) ? SRC1.f32[i*4] : ... SRC1.f32[i*4+3];
    DEST.f32[i*4+1] = (imm8[3:2]==0) ? SRC1.f32[i*4] : ... SRC1.f32[i*4+3];
    DEST.f32[i*4+2] = (imm8[5:4]==0) ? SRC1.f32[i*4] : ... SRC1.f32[i*4+3];
    DEST.f32[i*4+3] = (imm8[7:6]==0) ? SRC1.f32[i*4] : ... SRC1.f32[i*4+3];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f32 lane in each 128-bit group selected by k1 or no writemask:
    DEST[i] = SRC1[group_base + imm8_sel[(i%4)*2 +1:(i%4)*2]];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["invalid", "denormal"]
other_exceptions = ["VEX Type 2 class exceptions", "EVEX Type E2 class exceptions"]

handler = "x86_vpermilps"
jit_lowering = "arm64_neon_tbl1"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
tbl vD.16b, {vN.16b}, vM.16b
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "NEON TBL provides a per-byte lookup table that approximates single-precision in-lane permute for 128-bit operations."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
