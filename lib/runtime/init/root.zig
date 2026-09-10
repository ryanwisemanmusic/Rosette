//! init — Guest binary initializer pipeline library.
//!
//! Tracks and resolves pre-main initializers (C++ static constructors, global
//! variable initializers, etc.) across the phase transition from dyld binding
//! to static initialization.
//!
//! No module-level dependencies beyond std.

pub const event_log = @import("event_log");

pub const initialization_engine = @import("initialization_engine.zig");
pub const initializer_dependency = @import("initializer_dependency.zig");

// `pub const x = @import("x.zig")` does not root x's tests: a declaration is
// only analysed when something references it, and the test runner walks the
// root file's tests rather than its imports. Both modules below carried tests
// that had never executed once — including the ABI-mismatch case that the
// 2026-09-08 `abi_mismatch=0x5` line came from.
test {
    _ = initialization_engine;
    _ = initializer_dependency;
}
