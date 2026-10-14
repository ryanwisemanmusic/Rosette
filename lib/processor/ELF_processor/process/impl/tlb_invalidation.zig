//! Cross-executor range invalidation and measured work. The caller advances
//! the existing global epoch first; owner fills still recheck that epoch.
const std = @import("std");
pub fn range(state: anytype, owner: anytype, base: u64, length: u64, reads: bool, writes: bool) void {
    const Tlb = @typeInfo(@TypeOf(owner)).pointer.child;
    var measured = owner.invalidateRangeOrderedMeasured(base, length, reads, writes);
    var table_count: u64 = 1;
    for (&state.windows_guest_thread_tlbs) |*slot| {
        if (@atomicLoad(?*Tlb, slot, .acquire)) |tlb| {
            if (tlb == owner) continue;
            const work = tlb.invalidateRangeOrderedMeasured(base, length, reads, writes);
            measured.slots += work.slots;
            measured.skipped_directions += work.skipped_directions;
            table_count += 1;
        }
    }
    const pages = if (length == 0) 0 else ((base +| (length - 1)) >> Tlb.page_shift) - (base >> Tlb.page_shift) + 1;
    state.parallel_tlb_invalidation_work.noteRangeMeasured(pages, table_count, Tlb.entries, Tlb.invalidate_scan_limit, measured.slots, measured.skipped_directions);
}
pub fn report(state: anytype) void {
    const work = state.parallel_tlb_invalidation_work.snapshot();
    std.log.info("PE64 BLOCK JIT TLB INVALIDATION WORK: range_calls={d} requested_pages={d} wide_range_flushes={d} explicit_flushes={d} table_visits={d} tag_slots_touched={d} membership_skipped_directions={d}; measured tag-slot visits; narrow absent-region directions skip scans; global epoch and raced-fill retirement retained; historical builds modeled both directions", .{ work.range_calls, work.requested_pages, work.wide_range_flushes, work.explicit_flushes, work.table_visits, work.tag_slots_touched, work.membership_skipped_directions });
}
