//! Retained execution history.
//!
//! Extracted because it had six owners. `near_null_causality`, `memory_access`,
//! `diagnostics`, `crash_diag`, `import-handler/dispatch` and `Mach-O/process`
//! each carried their own copy of the ring index arithmetic and their own
//! per-thread filtering, and the decisions built on top of them — including
//! whether to redirect guest control flow — inherited whatever those copies
//! happened to agree or disagree about.
//!
//! `ring.zig` owns the index arithmetic. `instruction_history.zig` owns the
//! thread partitioning and, crucially, the *reporting of reach*: a bounded
//! recognizer that cannot reach its evidence must be able to say so.

pub const ring = @import("ring.zig");
pub const instruction_history = @import("instruction_history.zig");
pub const generated_block = @import("generated_block.zig");

pub const Ring = ring.Ring;
pub const History = instruction_history.History;
pub const BlockDefinition = generated_block.Definition;
pub const BlockOrigin = generated_block.Origin;

test {
    _ = ring;
    _ = instruction_history;
    _ = generated_block;
}
