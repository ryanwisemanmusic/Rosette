#!/bin/bash
# Runs the ELF processor test suite (Phase 1b/1c gate) against the
# ISA/decoding/ universal decoder module.
set -u
cd "$(dirname "$0")/.." || exit 1

D='--dep isa_highway --dep isa_decode --dep isa_registry --dep runtime_abi_handshake --dep flags --dep cpu_state --dep bit_test --dep capabilities'
M='-Mx64_decoder=ISA/decoding/root.zig --dep flags -Mcpu_state=src/x64-ASM/cpu_state.zig --dep flags -Mbit_test=src/x64-ASM/bit_test.zig -Mflags=src/x64-ASM/flags.zig -Mcapabilities=src/x64-ASM/capabilities.zig -Misa_highway=ISA/highway.zig -Misa_decode=ISA/decode/root.zig -Misa_registry=ISA/root.zig -Mruntime_abi_handshake=src/tooling/runtime-abi-handshake/runtime.zig'

exec zig test \
  --dep x64_decoder --dep x64_interpreter --dep x64_linux_runtime --dep x64_syscalls \
  --dep x64_guest_abi --dep exit_diagnostics --dep cleo_routing --dep arm64_encode \
  -Mroot=lib/processor/ELF_processor/process.zig \
  -Marm64_encode=lib/compiler/arm64/encode.zig \
  $D $M \
  -Mx64_interpreter=src/x64-ASM/interpreter.zig --dep x64_syscalls \
  -Mx64_linux_runtime=src/x64-ASM/linux_runtime.zig -Mx64_syscalls=src/x64-ASM/syscalls.zig \
  -Mx64_guest_abi=src/x64-ASM/guest_abi.zig -Mexit_diagnostics=src/tooling/exit_diagnostics/root.zig \
  -Mcleo_routing=lib/CLEO/cleo_routing.zig "$@"
