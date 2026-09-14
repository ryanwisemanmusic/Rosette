//! Which guest pages fault when they are touched, answered in O(1).
//!
//! Rosette's guest memory has always been one flat, permissive mapping.
//! `VirtualProtect` said so in its own comment: every protection request was
//! "already satisfied", except no-access and guard pages, "where the guest
//! expects a later fault Rosette will not raise".
//!
//! That exception is not an edge case for an emulator; it is how one talks to
//! its hardware. Xenia maps the Xbox 360's GPU registers at guest
//! `0x7FC80000` as `PAGE_NOACCESS` and registers a vectored exception handler.
//! A title's write to `CP_RB_WPTR` faults, the handler decodes the `mov`,
//! calls `GraphicsSystem::WriteRegister`, and that is the only way
//! `CommandProcessor::UpdateWritePointer` ever learns the ring moved. With no
//! fault the write lands in plain memory, the command processor never sees
//! work, and `ExecutePrimaryBuffer` is unreachable - which is exactly the
//! wall the 2026-09-13 run stopped at, one stage after the title handed Xenia
//! its ring.
//!
//! Xenia also write-protects physical memory to learn when a title changes a
//! texture or vertex buffer. The same missing fault silently breaks that.
//!
//! ## Why this shape
//!
//! Every interpreted memory operand consults this table, so it has to cost
//! nothing when no page is protected and a constant when some are - the
//! hot-path rule this project learned from a linear allocation scan that cost
//! an order of magnitude of throughput. Two bits per 4 KiB page, grouped into
//! lazily allocated 256 MiB chunks: a lookup is a shift, a null check and a
//! mask. The window is the low 64 GiB, which is where a Windows process puts
//! the mappings it protects; a request above it is counted, never silently
//! dropped.
//!
//! ## What this proves, and what it does not
//!
//! It records the protection a guest asked for and says whether an access
//! would violate it. It raises nothing, dispatches nothing and decides
//! nothing about recovery - that is the interpreter's job, and a table that
//! reached into guest state would be impossible to test in isolation.

const std = @import("std");

pub const page_shift: u6 = 12;
pub const page_size: u64 = @as(u64, 1) << page_shift;
pub const chunk_shift: u6 = 28;
pub const chunk_count: usize = 256;
/// One past the highest address the table models.
pub const window_end: u64 = @as(u64, chunk_count) << chunk_shift;

const pages_per_chunk: usize = @as(usize, 1) << (chunk_shift - page_shift);
const pages_per_word: usize = 32;
pub const words_per_chunk: usize = pages_per_chunk / pages_per_word;

/// What an access to a page is allowed to do.
///
/// Ordered by restriction so the stricter of two pages is the larger value -
/// an access that spans a page boundary is judged by the worse one.
pub const Protection = enum(u2) {
    accessible = 0,
    /// Faults on write only.
    read_only = 1,
    /// Faults on read and on write.
    no_access = 2,

    pub fn label(self: Protection) []const u8 {
        return switch (self) {
            .accessible => "accessible",
            .read_only => "read-only",
            .no_access => "no-access",
        };
    }

    /// The Windows `PAGE_*` value a caller of `VirtualProtect` is handed back
    /// as the old protection.
    ///
    /// `accessible` answers `PAGE_EXECUTE_READWRITE` because that is what
    /// Rosette has always reported and what its flat mapping genuinely
    /// provides; answering `PAGE_READWRITE` would have a guest that restores
    /// the old value strip execute permission from its own JIT.
    pub fn toWindows(self: Protection) u32 {
        return switch (self) {
            .accessible => 0x40,
            .read_only => 0x02,
            .no_access => 0x01,
        };
    }
};

/// The protection a Windows `PAGE_*` value asks for, or null for a value this
/// table does not model.
///
/// `PAGE_GUARD` is a one-shot fault with its own status code and is not
/// modelled; a caller that asks for it is told null so it can count the
/// request rather than enforce the wrong fault.
pub fn fromWindows(protect: u32) ?Protection {
    const guard: u32 = 0x100;
    if ((protect & guard) != 0) return null;
    return switch (protect & 0xFF) {
        0x01 => .no_access,
        // Execute-only and execute-read both allow reads on x86-64.
        0x02, 0x10, 0x20 => .read_only,
        0x04, 0x08, 0x40, 0x80 => .accessible,
        else => null,
    };
}

pub const SetOutcome = struct {
    pages_changed: u64 = 0,
    /// Part of the range lay above `window_end` and was not recorded.
    outside_window: bool = false,
    allocation_failed: bool = false,
};

pub const Table = struct {
    /// True while any page is restricted. The interpreter tests this single
    /// byte before anything else, so a process that never protects a page
    /// pays one load per memory operand and nothing more.
    active: bool = false,
    leaves: [chunk_count]?*[words_per_chunk]u64 = [_]?*[words_per_chunk]u64{null} ** chunk_count,
    restricted_in_chunk: [chunk_count]u32 = [_]u32{0} ** chunk_count,
    no_access_pages: u64 = 0,
    read_only_pages: u64 = 0,
    requests: u64 = 0,
    requests_outside_window: u64 = 0,
    allocation_failures: u64 = 0,

    pub fn deinit(self: *Table, allocator: std.mem.Allocator) void {
        for (&self.leaves) |*leaf| {
            if (leaf.*) |words| allocator.destroy(words);
            leaf.* = null;
        }
        self.* = .{};
    }

    pub fn restrictedPages(self: *const Table) u64 {
        return self.no_access_pages + self.read_only_pages;
    }

    pub fn get(self: *const Table, address: u64) Protection {
        const chunk = address >> chunk_shift;
        if (chunk >= chunk_count) return .accessible;
        const leaf = self.leaves[@intCast(chunk)] orelse return .accessible;
        const page: usize = @intCast((address >> page_shift) & (pages_per_chunk - 1));
        const shift: u6 = @intCast((page % pages_per_word) * 2);
        return @enumFromInt(@as(u2, @truncate(leaf[page / pages_per_word] >> shift)));
    }

    /// Whether an access of `width` bytes at `address` violates protection.
    ///
    /// Both ends are checked: a four-byte store that starts on an accessible
    /// page and ends on a protected one faults on Windows, and a register
    /// block that begins mid-page is exactly where that happens.
    pub fn faults(self: *const Table, address: u64, width: u8, is_write: bool) bool {
        const first = @intFromEnum(self.get(address));
        const last = if (width > 1) @intFromEnum(self.get(address +% (width - 1))) else first;
        const worst = @max(first, last);
        return worst == @intFromEnum(Protection.no_access) or
            (is_write and worst == @intFromEnum(Protection.read_only));
    }

    pub fn set(
        self: *Table,
        allocator: std.mem.Allocator,
        address: u64,
        length: u64,
        protection: Protection,
    ) SetOutcome {
        self.requests +|= 1;
        var outcome = SetOutcome{};
        const span = @max(length, 1);
        const end = address +| span;
        var page = address >> page_shift;
        const last_page = (end - 1) >> page_shift;
        while (page <= last_page) {
            const chunk = page >> (chunk_shift - page_shift);
            if (chunk >= chunk_count) {
                outcome.outside_window = true;
                self.requests_outside_window +|= 1;
                break;
            }
            const chunk_index: usize = @intCast(chunk);
            if (self.leaves[chunk_index] == null) {
                if (protection == .accessible) {
                    // Nothing recorded here and nothing to record: skip the
                    // whole chunk rather than walking 65,536 empty pages.
                    page = (chunk + 1) << (chunk_shift - page_shift);
                    continue;
                }
                const words = allocator.create([words_per_chunk]u64) catch {
                    outcome.allocation_failed = true;
                    self.allocation_failures +|= 1;
                    break;
                };
                @memset(words, 0);
                self.leaves[chunk_index] = words;
            }
            const leaf = self.leaves[chunk_index].?;
            const index: usize = @intCast(page & (pages_per_chunk - 1));
            const shift: u6 = @intCast((index % pages_per_word) * 2);
            const word = &leaf[index / pages_per_word];
            const old: Protection = @enumFromInt(@as(u2, @truncate(word.* >> shift)));
            if (old != protection) {
                word.* = (word.* & ~(@as(u64, 3) << shift)) | (@as(u64, @intFromEnum(protection)) << shift);
                self.account(chunk_index, old, -1);
                self.account(chunk_index, protection, 1);
                outcome.pages_changed +|= 1;
            }
            if (page == std.math.maxInt(u64)) break;
            page += 1;
        }
        self.active = self.restrictedPages() != 0;
        return outcome;
    }

    fn account(self: *Table, chunk_index: usize, protection: Protection, delta: i2) void {
        const counter = switch (protection) {
            .accessible => return,
            .read_only => &self.read_only_pages,
            .no_access => &self.no_access_pages,
        };
        if (delta > 0) {
            counter.* +|= 1;
            self.restricted_in_chunk[chunk_index] +|= 1;
        } else {
            counter.* -|= 1;
            self.restricted_in_chunk[chunk_index] -|= 1;
        }
    }
};

const testing = std.testing;

test "an untouched table is inactive and permits everything" {
    var table = Table{};
    defer table.deinit(testing.allocator);
    try testing.expect(!table.active);
    try testing.expectEqual(Protection.accessible, table.get(0x2_7FC8_0714));
    try testing.expect(!table.faults(0x2_7FC8_0714, 4, true));
}

test "a GPU register page faults on read and write, and nothing beside it does" {
    var table = Table{};
    defer table.deinit(testing.allocator);
    // Xenia's register block: guest 0x7FC80000 at membase 0x200000000, one
    // 64 KiB range committed no-access.
    const outcome = table.set(testing.allocator, 0x2_7FC8_0000, 0xFFFF, .no_access);
    try testing.expectEqual(@as(u64, 16), outcome.pages_changed);
    try testing.expect(table.active);
    try testing.expect(table.faults(0x2_7FC8_0714, 4, true)); // CP_RB_WPTR store
    try testing.expect(table.faults(0x2_7FC8_0710, 4, false)); // CP_RB_RPTR load
    try testing.expect(!table.faults(0x2_7FC7_FFF8, 4, true));
    try testing.expect(!table.faults(0x2_7FC9_0000, 4, false));
    try testing.expectEqual(@as(u64, 16), table.no_access_pages);
}

test "a read-only page faults only on write" {
    var table = Table{};
    defer table.deinit(testing.allocator);
    _ = table.set(testing.allocator, 0x3_0000_1000, 0x1000, .read_only);
    try testing.expect(!table.faults(0x3_0000_1000, 8, false));
    try testing.expect(table.faults(0x3_0000_1000, 8, true));
}

test "an access is judged by both of the pages it touches" {
    var table = Table{};
    defer table.deinit(testing.allocator);
    _ = table.set(testing.allocator, 0x1000_2000, 0x1000, .no_access);
    // Starts on the accessible page below, ends on the protected one.
    try testing.expect(table.faults(0x1000_1FFE, 4, false));
    try testing.expect(!table.faults(0x1000_1FFC, 4, false));
}

test "restoring access clears the page and deactivates the table" {
    var table = Table{};
    defer table.deinit(testing.allocator);
    _ = table.set(testing.allocator, 0x4000_0000, 0x3000, .read_only);
    try testing.expectEqual(@as(u64, 3), table.read_only_pages);
    _ = table.set(testing.allocator, 0x4000_0000, 0x3000, .accessible);
    try testing.expectEqual(@as(u64, 0), table.restrictedPages());
    try testing.expect(!table.active);
    // Setting a page to what it already is changes nothing and counts nothing.
    try testing.expectEqual(@as(u64, 0), table.set(testing.allocator, 0x4000_0000, 0x3000, .accessible).pages_changed);
}

test "clearing a huge untouched range is cheap and allocates nothing" {
    var table = Table{};
    defer table.deinit(testing.allocator);
    const outcome = table.set(testing.allocator, 0, window_end, .accessible);
    try testing.expectEqual(@as(u64, 0), outcome.pages_changed);
    for (table.leaves) |leaf| try testing.expect(leaf == null);
}

test "a request above the modelled window is counted, never silently enforced" {
    var table = Table{};
    defer table.deinit(testing.allocator);
    const outcome = table.set(testing.allocator, 0x40_E000_0000, 0x1000, .no_access);
    try testing.expect(outcome.outside_window);
    try testing.expectEqual(@as(u64, 1), table.requests_outside_window);
    try testing.expect(!table.active);
    try testing.expect(!table.faults(0x40_E000_0000, 8, true));
}

test "Windows protection values map onto the three states, and guard pages are refused" {
    try testing.expectEqual(Protection.no_access, fromWindows(0x01).?);
    try testing.expectEqual(Protection.read_only, fromWindows(0x02).?);
    try testing.expectEqual(Protection.read_only, fromWindows(0x20).?);
    try testing.expectEqual(Protection.accessible, fromWindows(0x04).?);
    try testing.expectEqual(Protection.accessible, fromWindows(0x40).?);
    try testing.expectEqual(@as(?Protection, null), fromWindows(0x104));
    try testing.expectEqual(@as(?Protection, null), fromWindows(0));
    try testing.expectEqual(@as(u32, 0x01), Protection.no_access.toWindows());
    try testing.expectEqual(@as(u32, 0x40), Protection.accessible.toWindows());
}
