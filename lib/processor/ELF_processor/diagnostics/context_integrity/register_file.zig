//! Whether a worker's slice touched the process owner's register file.
//!
//! Windows guest workers run on the one host thread against their own saved
//! context; the process owner's registers stay in the state's own fields,
//! untouched, until the owner runs again. Nothing a worker executes may
//! change them. On 2026-09-25 the shared vector helpers did: every VEX
//! instruction and every VEX compare's flags a worker executed wrote the
//! owner's `xmm` and `rflags` instead of its own, so `pxor xmm0, xmm0` on
//! Xenia's Emulator thread left that thread's `xmm0` holding a stale
//! fmt argument pair, libstdc++'s path parser started from it, and the run
//! ended on a 10.8 GB allocation three frames later.
//!
//! `compare` answers exactly which registers moved between two snapshots.
//! The slice audit takes one of the owner before a worker's slice and one
//! after; any difference is a finding that names the worker, the fields and
//! the instruction the worker ended on.

const std = @import("std");

pub const gpr_names = [_][]const u8{
    "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
    "r8",  "r9",  "r10", "r11", "r12", "r13", "r14", "r15",
};

pub const Difference = struct {
    /// Bit i: GPR i (RegId order) changed.
    gprs: u16 = 0,
    first_gpr: ?u8 = null,
    first_gpr_before: u64 = 0,
    first_gpr_after: u64 = 0,
    rip: bool = false,
    rip_before: u64 = 0,
    rip_after: u64 = 0,
    rflags: bool = false,
    mxcsr: bool = false,
    /// Bit i: xmm/ymm-upper/zmm-upper register i changed (any of its parts).
    vectors: u32 = 0,
    /// Bit i: mask register k<i> changed.
    masks: u8 = 0,
    x87: bool = false,
    /// The first vector register that changed, with its low 16 bytes before
    /// and after, for the report.
    first_vector: ?u8 = null,
    first_vector_before: [16]u8 = @splat(0),
    first_vector_after: [16]u8 = @splat(0),

    pub fn any(self: Difference) bool {
        return self.gprs != 0 or self.rip or self.rflags or self.mxcsr or
            self.vectors != 0 or self.masks != 0 or self.x87;
    }

    /// `rax,rsp,rflags,xmm0,xmm2,k1,x87` - every field that moved.
    pub fn format(self: Difference, buffer: []u8) []const u8 {
        var used: usize = 0;
        const Writer = struct {
            fn put(storage: []u8, at: *usize, text: []const u8) void {
                const separator: []const u8 = if (at.* == 0) "" else ",";
                if (at.* + separator.len + text.len > storage.len) return;
                @memcpy(storage[at.*..][0..separator.len], separator);
                at.* += separator.len;
                @memcpy(storage[at.*..][0..text.len], text);
                at.* += text.len;
            }
        };
        for (gpr_names, 0..) |name, index| {
            if (self.gprs & (@as(u16, 1) << @intCast(index)) != 0) Writer.put(buffer, &used, name);
        }
        if (self.rip) Writer.put(buffer, &used, "rip");
        if (self.rflags) Writer.put(buffer, &used, "rflags");
        if (self.mxcsr) Writer.put(buffer, &used, "mxcsr");
        var index: usize = 0;
        while (index < 32) : (index += 1) {
            if (self.vectors & (@as(u32, 1) << @intCast(index)) == 0) continue;
            var name: [8]u8 = undefined;
            Writer.put(buffer, &used, std.fmt.bufPrint(&name, "xmm{d}", .{index}) catch continue);
        }
        index = 0;
        while (index < 8) : (index += 1) {
            if (self.masks & (@as(u8, 1) << @intCast(index)) == 0) continue;
            var name: [4]u8 = undefined;
            Writer.put(buffer, &used, std.fmt.bufPrint(&name, "k{d}", .{index}) catch continue);
        }
        if (self.x87) Writer.put(buffer, &used, "x87");
        if (used == 0) Writer.put(buffer, &used, "none");
        return buffer[0..used];
    }
};

/// Compare two register-file snapshots. `before` and `after` are any values
/// with the architectural fields (`regs`, `xmm`, `ymm_hi`, `zmm_hi`, `k`,
/// `x87_stack`, `x87_tags`, `x87_top`, `x87_status`, `x87_control`).
pub fn compare(before: anytype, after: anytype) Difference {
    var result: Difference = .{};
    inline for (gpr_names, 0..) |name, index| {
        const old_value = @field(before.regs, name);
        const new_value = @field(after.regs, name);
        if (old_value != new_value) {
            result.gprs |= @as(u16, 1) << index;
            if (result.first_gpr == null) {
                result.first_gpr = @intCast(index);
                result.first_gpr_before = old_value;
                result.first_gpr_after = new_value;
            }
        }
    }
    result.rip = before.regs.rip != after.regs.rip;
    result.rip_before = before.regs.rip;
    result.rip_after = after.regs.rip;
    result.rflags = before.regs.rflags != after.regs.rflags;
    result.mxcsr = before.regs.mxcsr != after.regs.mxcsr;
    for (0..32) |index| {
        const changed = !std.mem.eql(u8, &before.xmm[index], &after.xmm[index]) or
            !std.mem.eql(u8, &before.ymm_hi[index], &after.ymm_hi[index]) or
            !std.mem.eql(u8, &before.zmm_hi[index], &after.zmm_hi[index]);
        if (!changed) continue;
        result.vectors |= @as(u32, 1) << @intCast(index);
        if (result.first_vector == null) {
            result.first_vector = @intCast(index);
            result.first_vector_before = before.xmm[index];
            result.first_vector_after = after.xmm[index];
        }
    }
    for (0..8) |index| {
        if (before.k[index] != after.k[index]) result.masks |= @as(u8, 1) << @intCast(index);
    }
    result.x87 = !std.mem.eql(u8, std.mem.asBytes(&before.x87_stack), std.mem.asBytes(&after.x87_stack)) or
        !std.mem.eql(bool, &before.x87_tags, &after.x87_tags) or
        before.x87_top != after.x87_top or before.x87_status != after.x87_status or
        before.x87_control != after.x87_control;
    return result;
}

/// Restore the architectural register file after a worker has crossed the
/// context boundary. This is a containment path for a missed context-aware
/// helper: a worker must never leave the process owner with its registers.
pub fn restoreArchitecturalState(destination: anytype, source: anytype) void {
    destination.regs = source.regs;
    destination.xmm = source.xmm;
    destination.ymm_hi = source.ymm_hi;
    destination.zmm_hi = source.zmm_hi;
    destination.k = source.k;
    destination.x87_stack = source.x87_stack;
    destination.x87_tags = source.x87_tags;
    destination.x87_top = source.x87_top;
    destination.x87_status = source.x87_status;
    destination.x87_control = source.x87_control;
}

const TestRegs = struct {
    rax: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
    rbx: u64 = 0,
    rsp: u64 = 0,
    rbp: u64 = 0,
    rsi: u64 = 0,
    rdi: u64 = 0,
    r8: u64 = 0,
    r9: u64 = 0,
    r10: u64 = 0,
    r11: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,
    rip: u64 = 0,
    rflags: u32 = 2,
    mxcsr: u32 = 0x1F80,
};

const TestFile = struct {
    regs: TestRegs = .{},
    xmm: [32][16]u8 = @splat(@splat(0)),
    ymm_hi: [32][16]u8 = @splat(@splat(0)),
    zmm_hi: [32][32]u8 = @splat(@splat(0)),
    k: [8]u64 = @splat(0),
    x87_stack: [8][10]u8 = @splat(@splat(0)),
    x87_tags: [8]bool = @splat(false),
    x87_top: u3 = 0,
    x87_status: u16 = 0,
    x87_control: u16 = 0x037F,
};

test "identical register files compare equal" {
    const a: TestFile = .{};
    try std.testing.expect(!compare(a, a).any());
    var text: [32]u8 = undefined;
    try std.testing.expectEqualStrings("none", compare(a, a).format(&text));
}

test "every moved field is named, and the first vector keeps its bytes" {
    const before: TestFile = .{};
    var after = before;
    after.regs.rsp = 8;
    after.regs.rip = 0x140001234;
    after.regs.rflags = 0x43;
    after.xmm[0][3] = 0xAA;
    after.zmm_hi[5][31] = 1;
    after.k[1] = 7;
    after.x87_top = 3;
    const difference = compare(before, after);
    try std.testing.expect(difference.any());
    try std.testing.expectEqual(@as(u16, 1 << 4), difference.gprs);
    try std.testing.expectEqual(@as(?u8, 4), difference.first_gpr);
    try std.testing.expectEqual(@as(u64, 0), difference.first_gpr_before);
    try std.testing.expectEqual(@as(u64, 8), difference.first_gpr_after);
    try std.testing.expectEqual(@as(u64, 0), difference.rip_before);
    try std.testing.expectEqual(@as(u64, 0x140001234), difference.rip_after);
    try std.testing.expectEqual(@as(u32, (1 << 0) | (1 << 5)), difference.vectors);
    try std.testing.expectEqual(@as(?u8, 0), difference.first_vector);
    try std.testing.expectEqual(@as(u8, 0xAA), difference.first_vector_after[3]);
    var text: [96]u8 = undefined;
    try std.testing.expectEqualStrings("rsp,rip,rflags,xmm0,xmm5,k1,x87", difference.format(&text));
}

test "owner register-file recovery restores only architectural state" {
    var before: TestFile = .{};
    before.regs.rip = 0x1000;
    before.regs.rbx = 0xBEEF;
    before.xmm[2][7] = 0x11;
    before.k[3] = 0x44;
    var owner = before;
    owner.regs.rip = 0x2000;
    owner.regs.rbx = 1;
    owner.xmm[2][7] = 0x99;
    owner.k[3] = 0;

    restoreArchitecturalState(&owner, &before);

    try std.testing.expectEqualDeep(before.regs, owner.regs);
    try std.testing.expectEqualDeep(before.xmm, owner.xmm);
    try std.testing.expectEqualDeep(before.k, owner.k);
    try std.testing.expect(!compare(&before, &owner).any());
}
