//! Minimal x86-ASM root for the standalone trace-logger test artifact.
//!
//! The normal build intentionally uses `title_entries.zig` as its compact
//! title catalogue root. The trace logger needs the instruction-set and
//! decoder declarations, but importing the catalogue root would also pull in
//! native title entry points and their runtime symbols. This root keeps the
//! test dependency boundary precise.

pub const instruction_set = @import("instruction_set.zig");
pub const raw_decoder = @import("raw_decoder.zig");
pub const instruction_operations = @import("instruction_operations.zig");
