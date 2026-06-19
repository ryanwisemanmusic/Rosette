# aasm

`aasm` is the Rosetta 3 assembler-normalization layer.

Its job is not to replace MASM, FASM, or NASM one-for-one. Its job is to
normalize their important differences into a single internal description that
Rosetta 3 can map onto:

- DOS / 16-bit execution profiles
- IA-32 / 32-bit execution profiles
- x86-64 execution profiles
- Zig-hosted translation and ABI bridges

Immediate next responsibilities:

1. Recognize source dialect families: MASM, Irvine32-flavored MASM, FASM, NASM.
2. Normalize directives, include styles, and calling-convention assumptions.
3. Record runtime expectations such as DOS interrupts, Win32 imports, or
   Irvine32 helper procedures.
4. Feed a future assembler-agnostic IR that Rosetta 3 can execute, translate,
   or validate.
