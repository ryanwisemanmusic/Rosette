# JIT Compiler Library

Zig library for monitoring and profiling JIT-compiled guest code in Rosetta 3.

## Modules

| Module | Description |
|--------|-------------|
| `types.zig` | Core types: GuestAddress, HostAddress, JitEvent, GuestFunction, CodeCacheRegion, CompileStats |
| `monitor.zig` | Event recording and querying for JIT compilation and execution events |
| `profiler.zig` | Performance profiling: hot function detection, execution counting, timing |
| `xenia.zig` | Xenia-specific JIT architecture constants (thunks, code cache layout, known modules) |

## Usage

```zig
const jit = @import("jit");

// Monitor JIT events
var mon = jit.Monitor.init(allocator);
mon.startRecording();
// ... record events via bridge or manual injection ...
try mon.recordEvent(.{
    .kind = .function_compiled,
    .timestamp_ns = timestamp,
    .guest_addr = 0x82000000,
});
defer mon.deinit();

// Profile hot functions
var prof = jit.Profiler.init(allocator);
try prof.recordCompilation(0x82000000, host_addr, code_size, compile_ns);
prof.recordExecution(0x82000000, exec_ns);
defer prof.deinit();

// Query Xenia-specific constants
const sentinel = jit.XeniaConstants.sentinel_return_address;
const trampoline_base = jit.XeniaConstants.trampoline_base;
```

## Xenia JIT Architecture (for context)

Xenia uses a pure JIT approach:
1. Guest PowerPC functions are compiled to x64 machine code on-demand
2. Compiled code is stored in a code cache (RWX pages)
3. Host-to-guest thunks bridge from Xenia's C++ code to JIT'd guest code
4. Guest-to-host thunks handle callbacks (MMIO, syscalls, HLE functions)
5. The sentinel return address 0xBCBCBCBC identifies guest→guest calls
6. xboxkrnl.exe trampolines are allocated at 0x80040000–0x801C0000
