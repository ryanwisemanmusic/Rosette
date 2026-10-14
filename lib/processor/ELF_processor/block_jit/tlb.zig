//! Software TLB used by emitted probes.
const std = @import("std");
pub const Tlb = extern struct {
    /// GPU Commands reported 727 million admitted-page fills in the
    /// 2026-10-06 run. Keep the table at 32K entries: growing the inline
    /// read/write pair beyond 1 MiB per executor makes test and worker stack
    /// frames too large, while the folded index addresses the observed
    /// aliasing without increasing the hot-path footprint.
    pub const entries: usize = 32768;
    /// A range wider than this is flushed rather than walked. Without it a
    /// larger table turns every wide protection change - and Xenia's write
    /// watch makes those constantly - into thousands of iterations.
    pub const invalidate_scan_limit: usize = 1024;
    pub const page_shift: u6 = 12;
    pub const page_bytes: u64 = 1 << page_shift;
    pub const invalid_tag: u64 = std.math.maxInt(u64);

    /// Bits of the page number folded into the index. Direct-mapping on the
    /// low bits alone made every page 32 MiB apart share an entry, and
    /// Xenia's layout is built of exactly such strides: its physical views
    /// at 0xA0000000, 0xC0000000 and 0xE0000000 are one set of pages seen
    /// 512 MiB apart, and its heaps begin on 32 MiB boundaries. On
    /// 2026-09-21 the table took 815 million fills in a 514 s run.
    pub const fold_shift: u6 = 13;

    /// The entry a page number lives in: the emitted probe computes the same
    /// thing as one `eor` with a shifted operand and one `and`.
    pub fn index(tag: u64) usize {
        return @intCast((tag ^ (tag >> fold_shift)) & (entries - 1));
    }

    pub const Entry = extern struct {
        tag: u64 = invalid_tag,
        delta: u64 = 0,
    };

    read: [entries]Entry,
    write: [entries]Entry,
    membership: @import("tlb_membership.zig").Summary = .{},

    pub const empty: Tlb = .{
        .read = [_]Entry{.{}} ** entries,
        .write = [_]Entry{.{}} ** entries,
    };

    pub fn flush(self: *Tlb, reads: bool, writes: bool) void {
        if (reads) @memset(&self.read, .{});
        if (writes) @memset(&self.write, .{});
    }

    /// Admit `page` (page-aligned guest address) backed by `host`.
    pub fn fill(self: *Tlb, is_write: bool, page: u64, host: [*]u8) void {
        const tag = page >> page_shift;
        const table = if (is_write) &self.write else &self.read;
        self.membership.note(is_write, tag, false);
        table[index(tag)] = .{ .tag = tag, .delta = @intFromPtr(host) -% page };
    }

    /// Drop every entry covering `[base, base + length)`.
    pub fn invalidateRange(self: *Tlb, base: u64, length: u64) void {
        self.invalidateRangeTables(base, length, true, true);
    }

    /// The same for the read table, the write table, or both: a page made
    /// read-only keeps its read entries.
    pub fn invalidateRangeTables(self: *Tlb, base: u64, length: u64, reads: bool, writes: bool) void {
        if (length == 0 or !(reads or writes)) return;
        const first = base >> page_shift;
        const last = (base +| (length - 1)) >> page_shift;
        if (last - first + 1 >= @min(entries, invalidate_scan_limit)) {
            self.flush(reads, writes);
            return;
        }
        var tag = first;
        while (true) : (tag += 1) {
            const slot = index(tag);
            if (reads and self.read[slot].tag == tag) self.read[slot] = .{};
            if (writes and self.write[slot].tag == tag) self.write[slot] = .{};
            if (tag == last) break;
        }
    }

    pub fn lookup(self: *const Tlb, is_write: bool, address: u64) ?[*]u8 {
        const tag = address >> page_shift;
        const table = if (is_write) &self.write else &self.read;
        const entry = table[index(tag)];
        if (entry.tag != tag) return null;
        return @ptrFromInt(address +% entry.delta);
    }

    // -- parallel mode --------------------------------------------------------
    //
    // Each executor fills only its own table, but a protection or mapping
    // change made by one thread invalidates every thread's table while its
    // owner may be probing it. The emitted probe reads `tag` and then
    // `delta` with plain loads, so another thread must never write a delta:
    // it only ever retires a tag. A probe then sees either the old tag with
    // its old, still-valid delta, or a miss. The owner's own fill writes the
    // delta before the tag, and its own later probes see both in program
    // order.

    /// The owner's fill in parallel mode: the delta, then the tag, the tag
    /// sequentially consistent so the caller's epoch re-check that follows
    /// cannot be ordered before it.
    pub fn fillOrdered(self: *Tlb, is_write: bool, page: u64, host: [*]u8) void {
        const tag = page >> page_shift;
        const table = if (is_write) &self.write else &self.read;
        const entry = &table[index(tag)];
        self.membership.note(is_write, tag, true);
        @atomicStore(u64, &entry.delta, @intFromPtr(host) -% page, .monotonic);
        @atomicStore(u64, &entry.tag, tag, .seq_cst);
    }

    /// Retire the tag `fillOrdered` just wrote for `page`, if it is still
    /// that page's: the fill raced an invalidation.
    pub fn retireOrdered(self: *Tlb, is_write: bool, page: u64) void {
        const tag = page >> page_shift;
        const table = if (is_write) &self.write else &self.read;
        const entry = &table[index(tag)];
        if (@atomicLoad(u64, &entry.tag, .seq_cst) == tag) @atomicStore(u64, &entry.tag, invalid_tag, .seq_cst);
    }

    /// `flush` from a thread other than this table's owner: tags only.
    pub fn flushOrdered(self: *Tlb, reads: bool, writes: bool) void {
        if (reads) {
            for (&self.read) |*entry| @atomicStore(u64, &entry.tag, invalid_tag, .seq_cst);
        }
        if (writes) {
            for (&self.write) |*entry| @atomicStore(u64, &entry.tag, invalid_tag, .seq_cst);
        }
    }

    /// `invalidateRange` from a thread other than this table's owner.
    pub fn invalidateRangeOrdered(self: *Tlb, base: u64, length: u64) void {
        self.invalidateRangeOrderedTables(base, length, true, true);
    }

    pub fn invalidateRangeOrderedTables(self: *Tlb, base: u64, length: u64, reads: bool, writes: bool) void {
        _ = self.invalidateRangeOrderedMeasured(base, length, reads, writes);
    }

    pub const InvalidationResult = struct { slots: u64 = 0, skipped_directions: u64 = 0 };
    pub fn invalidateRangeOrderedMeasured(self: *Tlb, base: u64, length: u64, reads: bool, writes: bool) InvalidationResult {
        var result: InvalidationResult = .{};
        if (length == 0 or !(reads or writes)) return result;
        const first = base >> page_shift;
        const last = (base +| (length - 1)) >> page_shift;
        if (last - first + 1 >= @min(entries, invalidate_scan_limit)) {
            self.flushOrdered(reads, writes);
            result.slots = entries * (@as(u64, @intFromBool(reads)) + @as(u64, @intFromBool(writes)));
            return result;
        }
        const probe_reads = reads and self.membership.mightContain(false, first, last, true);
        const probe_writes = writes and self.membership.mightContain(true, first, last, true);
        result.skipped_directions = @as(u64, @intFromBool(reads and !probe_reads)) + @as(u64, @intFromBool(writes and !probe_writes));
        if (!probe_reads and !probe_writes) return result;
        var tag = first;
        while (true) : (tag += 1) {
            const slot = index(tag);
            if (probe_reads) {
                result.slots += 1;
                if (@atomicLoad(u64, &self.read[slot].tag, .seq_cst) == tag) @atomicStore(u64, &self.read[slot].tag, invalid_tag, .seq_cst);
            }
            if (probe_writes) {
                result.slots += 1;
                if (@atomicLoad(u64, &self.write[slot].tag, .seq_cst) == tag) @atomicStore(u64, &self.write[slot].tag, invalid_tag, .seq_cst);
            }
            if (tag == last) break;
        }
        return result;
    }
};
