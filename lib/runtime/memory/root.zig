//! memory — Guest virtual memory management library.
//!
//! Provides sparse virtual memory mapping, memory transaction journaling,
//! write provenance tracking, atomic compare-exchange monitoring, and
//! standalone utility functions (bytesForSize, x87 float conversion).
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - dyld       (for guest_memory_geometry in sparse_virtual_memory)
//!   - event_log  (shared logging via sparse_virtual_memory)

pub const memory_management_forwarder = @import("memory_management_forwarder.zig");
pub const memory_transaction = @import("memory_transaction.zig");
pub const memory_write_provenance = @import("memory_write_provenance.zig");
pub const sparse_virtual_memory = @import("sparse_virtual_memory.zig");
pub const atomic_compare_exchange = @import("atomic_compare_exchange.zig");
pub const bytesForSize = @import("manager.zig").bytesForSize;
pub const writeExtendedFloat80 = @import("manager.zig").writeExtendedFloat80;
pub const readExtendedFloat80 = @import("manager.zig").readExtendedFloat80;
pub const MemoryState = @import("manager.zig").MemoryState;
pub const read8 = @import("manager.zig").read8;
pub const read16 = @import("manager.zig").read16;
pub const read32 = @import("manager.zig").read32;
pub const read64 = @import("manager.zig").read64;
pub const readMemVal = @import("manager.zig").readMemVal;

test {
    _ = memory_management_forwarder;
    _ = memory_transaction;
    _ = memory_write_provenance;
    _ = sparse_virtual_memory;
    _ = atomic_compare_exchange;
    // Instantiated with a real enum rather than a bare `.bits32`. `bytesForSize`
    // takes `anytype` and switches exhaustively, and an enum *literal* has type
    // `@EnumLiteral()`, which has no exhaustive set — so the previous line
    // (`bytesForSize(.bits32)`) could never compile. It survived because this
    // module was only ever built as a dependency: its tests were analysed for
    // nothing and executed never.
    const Size = enum { bits8, bits16, bits32, bits64 };
    try @import("std").testing.expectEqual(@as(u8, 4), bytesForSize(Size.bits32));
    _ = MemoryState;
    _ = read8;
    _ = read16;
    _ = read32;
    _ = read64;
    _ = readMemVal;
}
