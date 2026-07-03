// PLATFORM/PCONFIG.inc
// PCONFIG — Platform Configuration (NP 0F 01 C5).
// System-level instruction for configuring platform features (e.g., TME-MK key programming).

name = "PCONFIG"
category = "system"
feature = "PCONFIG"
element_type = "system"

encodings = [
  { opcode = "NP 0F 01 C5", form = "PCONFIG", op_en = "ZO", feature = "PCONFIG", cpl = 0, mode64 = "valid", mode_compat = "valid" }
]

operand_encoding = {
  ZO = []
}

reads = ["EAX", "EBX", "DS:RBX", "IA32_TME_ACTIVATE", "IA32_TME_CAPABILITY"]
writes = ["EAX", "RFLAGS.ZF", "RFLAGS.CF", "RFLAGS.PF", "RFLAGS.AF", "RFLAGS.OF", "RFLAGS.SF"]
flags_read = ["RFLAGS"]
flags_written = ["ZF", "CF", "PF", "AF", "OF", "SF"]
implicit_operands = ["EAX", "EBX"]

semantic = """
IF CPUID.7.0:EDX[18] = 0 OR CPL > 0 THEN #UD; FI;
IF EAX != 0 THEN #GP(0); FI;
CASE (EAX) OF
  0 (MKTME_KEY_PROGRAM):
    IF IA32_TME_ACTIVATE[0] = 0 OR IA32_TME_ACTIVATE[1] = 0 OR IA32_TME_ACTIVATE[35:32] = 0 THEN #GP(0); FI;
    IF DS:RBX not 256-byte aligned THEN #GP(0); FI;
    Load TMP_KEY_PROGRAM_STRUCT from 192 bytes at DS:RBX;
    (* validate KEYID_CTRL, KEYID, ENC_ALG *)
    IF reserved bits set OR COMMAND > 3 OR KEYID invalid OR ENC_ALG invalid THEN #GP(0); FI;
    Attempt to acquire lock on key table;
    IF unsuccessful THEN ZF := 1; RAX := DEVICE_BUSY(5); GOTO EXIT; FI;
    CASE (COMMAND) OF
      0 (KEYID_SET_KEY_DIRECT): Update key table with KEY_FIELD_1/KEY_FIELD_2;
      1 (KEYID_SET_KEY_RANDOM): Mix HW RNG key with KEY_FIELD_1/KEY_FIELD_2; update table;
      2 (KEYID_CLEAR_KEY): Update key table to use TME default behavior;
      3 (KEYID_NO_ENCRYPT): Update key table to bypass encryption;
    ESAC;
    Release lock;
ESAC;
RAX := 0; RFLAGS.ZF := 0;
EXIT:
RFLAGS.CF := 0; RFLAGS.PF := 0; RFLAGS.AF := 0; RFLAGS.OF := 0; RFLAGS.SF := 0;
"""

exceptions = {
  protected_mode = ["#GP(0) if unsupported leaf or invalid MKTME_KEY_PROGRAM_STRUCT", "#PF if page fault", "#UD if CPL>0 or CPUID.7.0:EDX[18]=0 or LOCK/REP/VEX prefix"],
  real_address_mode = ["Same as protected mode"],
  virtual_8086_mode = ["#UD — PCONFIG not recognized in virtual-8086 mode"],
  compatibility_mode = ["Same as protected mode"],
  mode64 = ["Same as protected mode; #GP(0) if non-canonical memory operand"]
}

handler = "x86_pconfig"
jit_lowering = "arm64_smc_pconfig"

neon_register_model = """
PCONFIG is a privilege-level-0-only x86 system instruction for platform configuration (TME-MK key programming). ARM64 lowering is stubbed as a documented contract with SMC or platform-specific hypervisor call.
"""

neon_flag_model = """
ZF is set on failure (with EAX containing error code); on success ZF and all arithmetic flags are cleared.
"""

neon_assembly = """
smc #0
"""

neon_notes = [
  "PCONFIG requires CPL=0 and PCONFIG CPUID feature bit.",
  "Only leaf function 0 (MKTME_KEY_PROGRAM) is defined.",
  "ARM64 lowering uses SMC (secure monitor call) with documented contract for platform integration."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
