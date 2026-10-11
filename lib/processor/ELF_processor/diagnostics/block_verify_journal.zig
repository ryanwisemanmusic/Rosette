//! A write journal for checking a translated block that touches memory
//! against the interpreter (`ROSETTE_BLOCK_JIT_VERIFY_MEMORY=1`).
//!
//! The translator's cross-check used to cover register-only blocks alone:
//! running the interpreter first would have stored to guest memory, and the
//! translation then ran on memory the block had already changed. With a
//! journal bound to the executing context, the interpreter's pass stores
//! nothing: each store lands here, each load sees memory overlaid with what
//! the pass stored before it. The translation then runs for real, and its
//! registers and the final bytes at every address the pass stored are
//! compared with the journal's.
//!
//! An access the journal cannot model safely - the null page, a protected
//! page (a fault there is a guest-visible event), a store wider than 16
//! bytes, or more stores than it holds - fails the pass instead. A failed
//! pass is discarded: nothing reached memory, so the block simply runs.
//!
//! Written for the 2026-10-02 Halo 3 main-menu freeze, where every
//! instruction-level differential test passed and the question left was
//! whether some block of real guest code was translated wrongly.

const std = @import("std");

pub const Failure = enum {
    overflow,
    null_page,
    protected_page,
    wide_access,
    unsupported,
};

pub const Journal = struct {
    pub const capacity = 96;

    pub const Entry = struct {
        address: u64,
        width: u8,
        bytes: [16]u8,
    };

    pub const Byte = struct { address: u64, value: u8 };

    entries: [capacity]Entry = undefined,
    len: u32 = 0,
    failure: ?Failure = null,
    failure_address: u64 = 0,
    loads: u32 = 0,

    pub fn fail(self: *Journal, failure: Failure, address: u64) void {
        if (self.failure != null) return;
        self.failure = failure;
        self.failure_address = address;
    }

    pub fn store(self: *Journal, address: u64, bytes: []const u8) void {
        if (bytes.len > 16) return self.fail(.wide_access, address);
        if (self.len == capacity) return self.fail(.overflow, address);
        var entry = Entry{ .address = address, .width = @intCast(bytes.len), .bytes = @splat(0) };
        @memcpy(entry.bytes[0..bytes.len], bytes);
        self.entries[self.len] = entry;
        self.len += 1;
    }

    /// The pass's own byte at `address`: the latest store covering it.
    pub fn byteAt(self: *const Journal, address: u64) ?u8 {
        var index = self.len;
        while (index > 0) {
            index -= 1;
            const entry = &self.entries[index];
            if (address >= entry.address and address - entry.address < entry.width) return entry.bytes[@intCast(address - entry.address)];
        }
        return null;
    }

    /// `bytes`, read from memory at `address`, as the pass sees them.
    pub fn forward(self: *Journal, address: u64, bytes: []u8) void {
        self.loads +|= 1;
        if (self.len == 0) return;
        for (bytes, 0..) |*byte, offset| {
            if (self.byteAt(address +% offset)) |stored| byte.* = stored;
        }
    }

    /// A little-endian scalar read from memory, as the pass sees it.
    pub fn forwardScalar(self: *Journal, comptime T: type, address: u64, value: T) T {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        self.forward(address, &bytes);
        return std.mem.readInt(T, &bytes, .little);
    }

    pub fn storeScalar(self: *Journal, comptime T: type, address: u64, value: T) void {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        self.store(address, &bytes);
    }

    /// Every byte the pass stored with its final value, each once; at most
    /// `out.len`. The latest store to a byte is the one that counts.
    pub fn finalBytes(self: *const Journal, out: []Byte) usize {
        var count: usize = 0;
        var index = self.len;
        while (index > 0) {
            index -= 1;
            const entry = &self.entries[index];
            for (0..entry.width) |offset| {
                const address = entry.address +% offset;
                var seen = false;
                for (out[0..count]) |byte| {
                    if (byte.address == address) {
                        seen = true;
                        break;
                    }
                }
                if (seen) continue;
                if (count == out.len) return count;
                out[count] = .{ .address = address, .value = entry.bytes[offset] };
                count += 1;
            }
        }
        return count;
    }
};

/// Whether an op's interpreter arm is known to reach memory only through
/// the journaled scalar and 128-bit paths. Atomic, string and x87 arms, and
/// those whose result depends on the time, are left to run unchecked.
pub fn journalSafeOp(name: []const u8) bool {
    // String instructions by their exact names: `movsx` and `movsd_load`
    // are ordinary loads and stay checked.
    const strings = [_][]const u8{ "movs", "movsq", "stos", "lods", "cmps", "scas" };
    for (strings) |string| {
        if (std.mem.eql(u8, name, string)) return false;
    }
    const unsafe = [_][]const u8{
        "xchg",     "cmpxchg",   "xadd",    "fxsave",   "fxrstor",   "xsave",   "xrstor",  "rdtsc",
        "rdrand",   "rdseed",    "cpuid",   "fld",      "fst",       "fist",    "fbld",    "fbst",
        "fnsave",   "frstor",    "fsave",   "fldenv",   "fnstenv",   "clflush", "vgather", "vpgather",
        "vscatter", "vpscatter", "maskmov", "vmaskmov", "vpmaskmov", "movnt",   "vmovnt",  "syscall",
        "int",      "ud",        "hlt",     "xgetbv",   "into",
    };
    for (unsafe) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return false;
    }
    return true;
}

test "journaled stores are forwarded to later loads and never reach memory" {
    var journal = Journal{};
    journal.storeScalar(u32, 0x1000, 0xAABBCCDD);
    // A wider load sees the pass's bytes over memory's.
    const memory: u64 = 0x1111_1111_1111_1111;
    try std.testing.expectEqual(@as(u64, 0x1111_1111_AABB_CCDD), journal.forwardScalar(u64, 0x1000, memory));
    // A later, narrower store wins over the earlier one.
    journal.storeScalar(u8, 0x1001, 0x55);
    try std.testing.expectEqual(@as(u32, 0xAABB55DD), journal.forwardScalar(u32, 0x1000, 0));
    var bytes: [8]Journal.Byte = undefined;
    const count = journal.finalBytes(&bytes);
    try std.testing.expectEqual(@as(usize, 4), count);
    var found_55 = false;
    for (bytes[0..count]) |byte| {
        if (byte.address == 0x1001) {
            try std.testing.expectEqual(@as(u8, 0x55), byte.value);
            found_55 = true;
        }
    }
    try std.testing.expect(found_55);
}

test "the journal fails rather than model what it cannot" {
    var journal = Journal{};
    var wide: [32]u8 = @splat(0);
    journal.store(0x2000, &wide);
    try std.testing.expectEqual(Failure.wide_access, journal.failure.?);
    var full = Journal{};
    for (0..Journal.capacity) |index| full.storeScalar(u8, 0x3000 + index, 1);
    try std.testing.expect(full.failure == null);
    full.storeScalar(u8, 0x4000, 1);
    try std.testing.expectEqual(Failure.overflow, full.failure.?);
}

test "atomic, string and x87 ops are left to run unchecked" {
    try std.testing.expect(journalSafeOp("mov_reg32_mem32"));
    try std.testing.expect(journalSafeOp("movbe_reg_mem"));
    try std.testing.expect(journalSafeOp("add_mem32_reg32"));
    try std.testing.expect(!journalSafeOp("cmpxchg_mem32_reg32"));
    try std.testing.expect(!journalSafeOp("xchg_mem64_reg64"));
    try std.testing.expect(!journalSafeOp("movs"));
    try std.testing.expect(!journalSafeOp("stos"));
    try std.testing.expect(journalSafeOp("movsx_reg32_mem8"));
    try std.testing.expect(journalSafeOp("movsd_load"));
    try std.testing.expect(!journalSafeOp("fld_mem80"));
    try std.testing.expect(!journalSafeOp("rdtsc"));
    // A trap raised on a racing value in a discarded pass would end the run.
    try std.testing.expect(!journalSafeOp("ud2"));
    try std.testing.expect(!journalSafeOp("hlt"));
}
