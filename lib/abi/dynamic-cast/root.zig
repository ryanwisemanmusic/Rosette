//! dynamic-cast — the Itanium C++ ABI `__dynamic_cast` implementation.
//!
//! Split out of `cxx-abi` because it is not one function with a lookup table
//! behind it. Answering a cast means reading a foreign process's RTTI without
//! trusting any of it, enumerating an object's base-class subobject graph from
//! a live vptr, and then applying accessibility and ambiguity rules that decide
//! between two different null pointers — the one C++ defines and the one that
//! means Rosette gave up. Each of those is its own problem with its own failure
//! modes, and each is its own file here:
//!
//!   `type_info.zig`  reading and classifying RTTI records in guest memory
//!   `hierarchy.zig`  enumerating an object's subobject graph from a live vptr
//!   `resolver.zig`   the ABI's cast rules, including why a null is a null
//!   `engine.zig`     per-process learning, counters, and reporting
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - event_log (reporting)

pub const type_info = @import("type_info.zig");
pub const hierarchy = @import("hierarchy.zig");
pub const resolver = @import("resolver.zig");
pub const engine = @import("engine.zig");

pub const Engine = engine.Engine;
pub const FailureReportDecision = engine.FailureReportDecision;
pub const Resolution = resolver.Resolution;
pub const Strategy = resolver.Strategy;
pub const Undecided = resolver.Undecided;

/// Whether a thrown class binds to a typed catch clause. Shares the RTTI reader
/// and the public-base rule with the cast, because the ABI defines them with
/// the same walk.
pub const isCatchCompatible = resolver.catchCompatible;

// Rooted in build.zig so these run rather than merely compile.
test {
    _ = type_info;
    _ = hierarchy;
    _ = resolver;
    _ = engine;
}
