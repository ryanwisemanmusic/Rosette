//! init — Guest binary initializer pipeline library.
//!
//! Tracks and resolves pre-main initializers (C++ static constructors, global
//! variable initializers, etc.) across the phase transition from dyld binding
//! to static initialization.
//!
//! No module-level dependencies beyond std.

pub const event_log = @import("event_log.zig");

pub const initialization_engine = @import("initialization_engine.zig");
pub const initializer_dependency = @import("initializer_dependency.zig");
