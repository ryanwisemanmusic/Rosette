# ISA Highway

Rosette's loaders own file-format and operating-system behavior. They must not
own independent instruction semantics.

The highway has three layers:

1. `ISA/Math/core.zig` is the canonical implementation of arithmetic, flags,
   and width truncation.
2. `ISA/highway.zig` translates format-neutral operations into that semantic
   core and publishes honest backend capability states.
3. ELF, Mach-O, PE, and CS218 runtime adapters decode their native execution
   context into highway operations. Loader-specific memory, imports, syscalls,
   and control transfer stay in their loaders.

## Migration Contract

An instruction family is `shared` only when every listed backend routes its
execution through the highway and has a conformance test. A backend may remain
an `adapter` while its decoder is format-specific. Unsupported paths are
`pending`; they must never be advertised as executable.

For each migrated family:

- Add or reuse the canonical semantic operation in `ISA/Math/core.zig`.
- Add the format-neutral operation and flag policy in `ISA/highway.zig`.
- Keep decoding thin: bytes and relocations become registers, memory operands,
  immediates, and a highway operation.
- Add one exact-byte probe per decoder and semantic edge cases to the highway.
- Mark memory and operating-system behavior separately from CPU semantics.

## Current Shared Lane

Scalar register ADD, SUB, SBB, AND, OR, XOR, CMP, and TEST share execution
semantics across ELF64, Mach-O x86_64, raw PE32, and scripted/CS218 x86 paths.
Their decoders remain adapters while memory operands are migrated to a shared
transaction interface.
