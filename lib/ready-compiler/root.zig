//! Rosette runtime readiness / activation contract library.
//!
//! `ready-compiler` is the runtime analogue of a build graph. It records what
//! was compiled, what was installed, and whether those artifacts actually
//! activated in the order required by the application. The core is guest
//! agnostic; `xenia` is the first concrete contract.

pub const types = @import("types.zig");
pub const runtime = @import("runtime.zig");
pub const xenia = @import("xenia.zig");

pub const Phase = types.Phase;
pub const CompileState = types.CompileState;
pub const FailureKind = types.FailureKind;
pub const StageSpec = types.StageSpec;
pub const Contract = types.Contract;
pub const Failure = types.Failure;
pub const Evaluation = types.Evaluation;
pub const Runtime = runtime.Runtime;

test {
    _ = types;
    _ = runtime;
    _ = xenia;
}
