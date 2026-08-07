//! The guest address-space model.
//!
//! Answers one question — "is this value a guest address, and where does it
//! live" — from observed mappings rather than from build-time constants, and
//! reports whether the answer is derived or defaulted.
//!
//! This was the last major piece of workload-specific determinism sitting in
//! generic runtime code. It had a single owner, so it was never a disagreement
//! problem; it was a knowledge-placement problem, which is the quieter and more
//! expensive kind.

pub const window = @import("window.zig");

pub const Model = window.Model;
pub const Region = window.Region;
pub const Classification = window.Classification;
pub const Source = window.Source;
pub const canonical32 = window.canonical32;

test {
    _ = window;
}
