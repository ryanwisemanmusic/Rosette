//! Rosette runtime readiness / activation contract library.
//!
//! `ready-compiler` is the runtime analogue of a build graph. It records what
//! was compiled, what was installed, and whether those artifacts actually
//! activated in the order required by the application. The core is guest
//! agnostic; `xenia` is the first concrete contract. Keep this root as the
//! dependency anchor so changes in the concrete contract invalidate the
//! processor's linked readiness module as well as its standalone tests.

pub const types = @import("types.zig");
pub const runtime = @import("runtime.zig");
pub const plan = @import("plan.zig");
pub const cache = @import("cache.zig");
pub const package = @import("package.zig");
pub const xenia_plan = @import("xenia_plan.zig");
pub const xenia = @import("xenia.zig");

pub const Phase = types.Phase;
pub const CompileState = types.CompileState;
pub const FailureKind = types.FailureKind;
pub const StageSpec = types.StageSpec;
pub const Contract = types.Contract;
pub const Failure = types.Failure;
pub const Evaluation = types.Evaluation;
pub const Runtime = runtime.Runtime;
pub const Plan = plan.Plan;
pub const PlanCache = cache.Snapshot;

test {
    _ = types;
    _ = runtime;
    _ = plan;
    _ = cache;
    _ = package;
    _ = xenia_plan;
    _ = xenia;
}
