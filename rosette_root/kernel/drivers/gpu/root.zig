//! Earliest build-time GPU facts used by the Rosette framework.
//!
//! This root is intentionally tiny and dependency-free at runtime. It is the
//! place where the framework selects the immutable observation envelope before
//! Mach-O state, Xenia adapters, or the PM4 executor are constructed.

const contract = @import("xenia_gpu_observation_contract");

pub const profile = struct {
    pub const schema_version = contract.schema_version;
    pub const max_ring_dwords = contract.max_ring_dwords;
    pub const max_indirect_depth = contract.max_indirect_depth;
    pub const max_indirect_dwords = contract.max_indirect_dwords;
    pub const max_indirect_references = contract.max_indirect_references;
    pub const max_indirect_execution_dwords = contract.max_indirect_execution_dwords;
    pub const packet_timeline_capacity = contract.packet_timeline_capacity;
    pub const pm4_dword_bytes = contract.pm4_dword_bytes;
    pub const xe_swap_opcode = contract.xe_swap_opcode;
    pub const xe_swap_signature = contract.xe_swap_signature;
    pub const xe_swap_reservation_dwords = contract.xe_swap_reservation_dwords;
    pub const front_buffer_fetch_dwords = contract.front_buffer_fetch_dwords;
};

comptime {
    if (!contract.contractIsWellFormed()) {
        @compileError("Rosette GPU root selected an invalid Xenia observation contract");
    }
    if (profile.max_ring_dwords == 0 or profile.max_indirect_depth == 0 or
        profile.packet_timeline_capacity == 0)
    {
        @compileError("Rosette GPU root selected an empty observation envelope");
    }
}

test "the earliest GPU root is backed by immutable package facts" {
    try @import("std").testing.expectEqual(@as(u8, 0x64), profile.xe_swap_opcode);
    try @import("std").testing.expectEqual(@as(usize, 16 * 1024), profile.max_ring_dwords);
}
