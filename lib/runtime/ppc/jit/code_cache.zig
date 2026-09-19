//! Executable memory for compiled PowerPC blocks.
//!
//! The implementation lives in `lib/compiler/arm64/code_memory.zig` so the
//! x86-64 block translator on the PE64 route can share it; this file keeps
//! the recompiler's import path and names.
const shared = @import("arm64_encode").code_memory;

pub const Error = shared.Error;
pub const CodeCache = shared.CodeCache;

test {
    _ = shared;
}
