When it comes to the handling of DOS based code, we have a lot of potential errors that can pop up regarding the parsing of DOS ASM code. 

```common_errors.zig
a20_gate_error,
alignment_error,
conventional_memory_violation,
division_by_zero,
duplicate_symbol,
invalid_addressing_mode_for_mode,
invalid_effective_address,
invalid_far_call_target,
invalid_immediate_value,
invalid_instruction,
invalid_interrupt_vector,
invalid_mcb_chain,
invalid_mnemonic,
invalid_operand_type,
invalid_port_access,
invalid_register_name,
invalid_syscall_number,
label_already_defined,
memory_to_memory_invalid_move,
operand_size_mismatch,
real_mode_limit_violation,
register_overflow,
register_size_mismatch,
segmentation_fault,
stack_overflow,
stack_underflow,
undefined_label,
undefined_symbol,
```

Whenever you stumble upon an error that pops up, you must consider whether or not you are properly implementing features related to said error. For example, if you have an invalid MCB chain, the question is whether or not your setup for the memory control block is accounting for the structure that proceeds the 16-bit block is properly handled. MCB blocks can range in how and what they decode, which means a mismatch there means you are not handling all decoding contexts within a MCB



