//! Dispatch tables.
//!
//! A translator's generated code reaches guest functions through a table of
//! code pointers indexed by guest address. When a dispatch loads zero from it,
//! the runtime has one observation and three incompatible explanations, and
//! answering "the target was null" for all three is how a diagnosis stops being
//! information.
//!
//! This owns the question, not the table: nothing here fills, allocates or
//! maintains one. It reads a bounded neighbourhood and says which of the three
//! the run is in.

pub const probe = @import("probe.zig");

pub const Probe = probe.Result;
pub const Population = probe.Population;

test {
    _ = probe;
}
