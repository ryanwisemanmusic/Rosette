//! symbol-context — Symbol assembly context (Mach-O sub-module).
//!
//! Tracks unknown-symbol assembly analysis within the Mach-O processor.
//! Tightly coupled to macho_metadata; this lives inside the Mach-O module tree.
//!
//! Domain: linker/runtime (Mach-O specific)

pub const Tracker = @import("symbol_assembly_context.zig").Tracker;
pub const Catalog = @import("symbol_assembly_context.zig").Catalog;
pub const ContextEntry = @import("symbol_assembly_context.zig").ContextEntry;
