//! cxx-abi — Itanium C++ ABI support library.
//!
//! Consolidates exception unwinding, dynamic_cast, object model, vtable
//! construction, exception diagnostics, and shared control block tracking.
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - dyld  (for pointer_firewall, memory_provenance via cxx_object_model,
//!            itanium_vtable_builder)
//!   - dynamic_cast (the `__dynamic_cast` library, re-exported below)

pub const event_log = @import("event_log");

/// `dynamic_cast` grew out of this library into its own — reading a foreign
/// process's RTTI, walking a live object's subobject graph, and telling the
/// language's null apart from the runtime's is more than a sibling of
/// unwinding. Re-exported under the old name so callers keep one import.
pub const itanium_dynamic_cast = @import("dynamic_cast");

pub const itanium_unwinder = @import("itanium_unwinder.zig");
pub const compact_unwind = @import("compact_unwind.zig");
pub const cxx_object_model = @import("cxx_object_model.zig");
pub const itanium_vtable_builder = @import("itanium_vtable_builder.zig");
pub const cxx_exception_diagnostics = @import("cxx_exception_diagnostics.zig");
pub const libcpp_shared_control_block = @import("libcpp_shared_control_block.zig");

// Rooted in build.zig so these run rather than merely compile. `dynamic_cast`
// is rooted as its own test artifact and is deliberately not pulled in here.
test {
    _ = itanium_unwinder;
    _ = compact_unwind;
    _ = cxx_object_model;
    _ = itanium_vtable_builder;
    _ = cxx_exception_diagnostics;
    _ = libcpp_shared_control_block;
}
