pub const memory_management_forwarder = @import("memory_management_forwarder.zig");
pub const memory_transaction = @import("memory_transaction.zig");
pub const memory_write_provenance = @import("memory_write_provenance.zig");
pub const sparse_virtual_memory = @import("sparse_virtual_memory.zig");
pub const atomic_compare_exchange = @import("atomic_compare_exchange.zig");
pub const bytesForSize = @import("manager.zig").bytesForSize;
pub const writeExtendedFloat80 = @import("manager.zig").writeExtendedFloat80;
pub const readExtendedFloat80 = @import("manager.zig").readExtendedFloat80;
