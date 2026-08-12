//! dyld - Dynamic linking & import resolution library.
//!
//! This module consolidates all dyld-related functionality that was previously
//! scattered across lib/Mach-O/resolution/: import resolution, ABI data
//! materialization, VTT binding, dynamic library forwarding, lazy import stubs,
//! smart stub generation, export table management, and the shared memory-safety
//! and event-logging infrastructure that those subsystems depend on.
//!
//! Consumers import via @import("dyld") from the macho_processor_mod module
//! (which has dyld_mod added as "dyld").
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - macho_compat_runtime  (used by import_engine)
//!   - scheduler             (used by dynamic_library_forwarder)
//!   - gpu                   (backend-neutral host GPU handshake/runtime)

pub const event_log = @import("event_log");
pub const pointer_firewall = @import("pointer_firewall.zig");
pub const memory_provenance = @import("memory_provenance.zig");
pub const guest_memory_geometry = @import("guest_memory_geometry.zig");

pub const import_engine = @import("import_engine.zig");
pub const abi_data_materializer = @import("abi_data_materializer.zig");
pub const vtt_resolver = @import("vtt_resolver.zig");
pub const dynamic_library_forwarder = @import("dynamic_library_forwarder.zig");
pub const lazy_import_stub = @import("lazy_import_stub.zig");
pub const smart_stub_generator = @import("smart_stub_generator.zig");
pub const export_table_manager = @import("export_table_manager.zig");
pub const export_table_lifecycle = @import("export_table_lifecycle.zig");
pub const dynamic_export_registry = @import("dynamic_export_registry.zig");
