//! A small ARM64 assembler with labels, for the PowerPC block compiler.
//!
//! The implementation lives in `lib/compiler/arm64/assembler.zig` so the
//! x86-64 block translator on the PE64 route can share it; this file keeps
//! the recompiler's import path and names.
const shared = @import("arm64_encode").assembler;

pub const Reg = shared.Reg;
pub const Cond = shared.Cond;
pub const Error = shared.Error;
pub const Label = shared.Label;
pub const Assembler = shared.Assembler;

test {
    _ = shared;
}
