//! Host-worker-owned counts, published only with the existing CPU ledger.
//! These count metadata work, not milliseconds or useful guest operations.
pub const Counts = struct {
    stub_lookups: u64 = 0,
    stub_hits: u64 = 0,
    stub_scanned: u64 = 0,
    dynamic_entries_peak: u64 = 0,
    callsites: u64 = 0,
    callsite_hits: u64 = 0,
    callsite_rebuilds: u64 = 0,
    callsite_fallbacks: u64 = 0,
};
threadlocal var owner: usize = 0;
threadlocal var counts: Counts = .{};
pub fn forState(state: anytype) *Counts {
    const identity = @intFromPtr(state);
    if (owner != identity) {
        owner = identity;
        counts = .{};
    }
    return &counts;
}
pub fn reset() void {
    owner = 0;
    counts = .{};
}
pub fn snapshot() Counts {
    return counts;
}
