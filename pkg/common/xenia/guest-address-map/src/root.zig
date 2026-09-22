//! Fixed-address policies used by Xenia's Windows CPU context allocator.
//!
//! Xenia deliberately probes one candidate per 4 GiB band. Keeping the
//! candidate shape here makes Rosetta's relocation policy auditable without
//! mixing the immutable address contract into the live PE allocation ledger.

const std = @import("std");

/// Windows' allocation granularity used by Xenia's `AllocateContext`.
pub const allocation_granularity: u64 = 0x1_0000;
/// Low 32-bit address of the page immediately preceding a context pointer.
pub const context_pre_low: u64 = 0xDFFF_0000;
pub const first_position: u64 = 0x40;
pub const position_limit: u64 = 8192;

/// Return the fixed candidate for one Xenia context position.
pub fn contextCandidate(position: u64) ?u64 {
    if (position < first_position or position >= position_limit) return null;
    return (position << 32) | context_pre_low;
}

/// Whether an address has the exact shape emitted by Xenia's
/// `((pos32 << 32) | 0xE0000000) - granularity` expression.
pub fn isContextCandidate(address: u64) bool {
    if ((address & 0xFFFF_FFFF) != context_pre_low) return false;
    const position = address >> 32;
    return position >= first_position and position < position_limit;
}

/// Return the next candidate in Xenia's sequence, if one exists.
pub fn nextContextCandidate(address: u64) ?u64 {
    if (!isContextCandidate(address)) return null;
    return contextCandidate((address >> 32) + 1);
}

test "context candidates preserve Xenia's low address contract" {
    try std.testing.expectEqual(@as(?u64, 0x40_DFFF_0000), contextCandidate(first_position));
    try std.testing.expect(isContextCandidate(0x40_DFFF_0000));
    try std.testing.expectEqual(@as(?u64, 0x41_DFFF_0000), nextContextCandidate(0x40_DFFF_0000));
    try std.testing.expect(!isContextCandidate(0x40_E000_0000));
    try std.testing.expect(nextContextCandidate(0x1FFF_DFFF_0000) == null);
}
