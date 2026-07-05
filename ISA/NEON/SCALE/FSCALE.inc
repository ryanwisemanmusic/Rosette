// SCALE/FSCALE.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/FSCALE.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/FSCALE.inc"
x86_handler = "x86_fscale"
neon_lowering = "arm64_documented_contract_fscale"
lowering_kind = "arm64_documented_contract"

name = "FSCALE"
aliases = []
category = "x87_fpu_scale"
feature = "x87"
element_type = "f80"
element_size = 80
lanes = 1

encodings = [
  { opcode = "D9 FC", form = "FSCALE", op_en = "ZO", feature = "x87", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["C0", "C1", "C2", "C3"]
simd_fp_exceptions = []
x87_fpu_used = true

semantic_general = """
ST(0) = ST(0) * 2^ST(1);
Scaled by exponent difference; result reflects ST(0) scaled by power-of-two from ST(1).
C1 set to 0 if underflow/overflow, C2 set to 1 if ST(1) not integer.
"""

handler = "x86_fscale"
jit_lowering = "arm64_documented_contract_fscale"
fallback = "zig_x87_fscale"

neon_register_model = """
x87 ST register stack is emulated in software on ARM64; the documented_contract preserves
the architectural x87 ST(0)/ST(1) semantic through a software FPU stack.
"""

neon_flag_model = """
x87 FPU status word C0-C3 flags are emulated in the software FPU stack;
no ARM64 NEON flags are affected.
"""

neon_assembly = """
// NEON lowering: x87 FSCALE is emulated via software FPU stack.
// No direct ARM64 NEON equivalent exists for x87 ST register scaling.
// The lowering computes: st(0) = st(0) * 2^floor(st(1))
// using ARM64 scalar floating-point arithmetic via the emulated x87 stack.
//     bl rosette_x87_emulate_fscale
"""

neon_notes = [
  "FSCALE is an x87 FPU stack instruction with no ARM64 NEON analogue.",
  "The documented_contract lowering emulates x87 behavior in software on ARM64.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
