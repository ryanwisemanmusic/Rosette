//! cxx-abi — Itanium C++ ABI support library.
//!
//! Consolidates exception unwinding, dynamic_cast, object model, vtable
//! construction, exception diagnostics, and shared control block tracking.
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - dyld  (for pointer_firewall, memory_provenance via cxx_object_model,
//!            itanium_vtable_builder)

pub const event_log = @import("event_log");

pub const itanium_unwinder = @import("itanium_unwinder.zig");
pub const itanium_dynamic_cast = @import("itanium_dynamic_cast.zig");
pub const compact_unwind = @import("compact_unwind.zig");
pub const cxx_object_model = @import("cxx_object_model.zig");
pub const itanium_vtable_builder = @import("itanium_vtable_builder.zig");
pub const cxx_exception_diagnostics = @import("cxx_exception_diagnostics.zig");
pub const libcpp_shared_control_block = @import("libcpp_shared_control_block.zig");
