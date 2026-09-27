//! Windows x64 callee-saved architectural state at Rosette import boundaries.
//!
//! Imported functions are called by guest code under the Microsoft x64 ABI.
//! Rosette implements many of those functions in Zig, where guest register
//! state is explicit and a helper can accidentally alter it while servicing
//! a callback, wait, or worker. This small value type lets the PE dispatcher
//! verify and contain that boundary without copying volatile state.

const std = @import("std");

pub const Difference = struct {
    /// Bits follow `gpr_names`: RBX, RBP, RSI, RDI, R12, R13, R14, R15.
    gpr_mask: u8 = 0,
    /// Bits 0..9 name XMM6..XMM15. The upper YMM/ZMM lanes are volatile under
    /// the Windows x64 ABI and are intentionally not part of this mask.
    xmm_mask: u16 = 0,

    pub fn any(self: Difference) bool {
        return self.gpr_mask != 0 or self.xmm_mask != 0;
    }
};

pub const gpr_names = [_][]const u8{ "rbx", "rbp", "rsi", "rdi", "r12", "r13", "r14", "r15" };

pub const Snapshot = struct {
    rbx: u64,
    rbp: u64,
    rsi: u64,
    rdi: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    xmm: [10][16]u8,

    pub fn capture(regs: anytype, xmm: anytype) Snapshot {
        var result = Snapshot{
            .rbx = regs.rbx,
            .rbp = regs.rbp,
            .rsi = regs.rsi,
            .rdi = regs.rdi,
            .r12 = regs.r12,
            .r13 = regs.r13,
            .r14 = regs.r14,
            .r15 = regs.r15,
            .xmm = undefined,
        };
        for (0..result.xmm.len) |index| result.xmm[index] = xmm[index + 6];
        return result;
    }

    pub fn difference(self: *const Snapshot, regs: anytype, xmm: anytype) Difference {
        var result: Difference = .{};
        const current = [_]u64{ regs.rbx, regs.rbp, regs.rsi, regs.rdi, regs.r12, regs.r13, regs.r14, regs.r15 };
        const saved = [_]u64{ self.rbx, self.rbp, self.rsi, self.rdi, self.r12, self.r13, self.r14, self.r15 };
        for (current, saved, 0..) |actual, expected, index| {
            if (actual != expected) result.gpr_mask |= @as(u8, 1) << @intCast(index);
        }
        for (self.xmm, 0..) |saved_xmm, index| {
            if (!std.mem.eql(u8, &saved_xmm, &xmm[index + 6])) {
                result.xmm_mask |= @as(u16, 1) << @intCast(index);
            }
        }
        return result;
    }

    /// Restore only the registers the Windows ABI promises to preserve.
    /// RAX and the other volatile values stay available as the function's
    /// return value and scratch state.
    pub fn restore(self: *const Snapshot, regs: anytype, xmm: anytype) void {
        regs.rbx = self.rbx;
        regs.rbp = self.rbp;
        regs.rsi = self.rsi;
        regs.rdi = self.rdi;
        regs.r12 = self.r12;
        regs.r13 = self.r13;
        regs.r14 = self.r14;
        regs.r15 = self.r15;
        for (self.xmm, 0..) |saved_xmm, index| xmm[index + 6] = saved_xmm;
    }
};

test "Windows import ABI guard restores nonvolatile registers and leaves volatile results" {
    const MockRegs = struct {
        rax: u64 = 0,
        rbx: u64 = 1,
        rbp: u64 = 2,
        rsi: u64 = 3,
        rdi: u64 = 4,
        r12: u64 = 12,
        r13: u64 = 13,
        r14: u64 = 14,
        r15: u64 = 15,
    };

    var regs: MockRegs = .{};
    var xmm: [32][16]u8 = @splat(@splat(0));
    xmm[7][3] = 0xA7;
    const saved = Snapshot.capture(&regs, &xmm);

    regs.rax = 0x1234; // An import's return value is volatile.
    regs.r14 = 0x12004fa18;
    xmm[7][3] = 0x5C;
    const difference = saved.difference(&regs, &xmm);
    try std.testing.expect(difference.any());
    try std.testing.expectEqual(@as(u8, 1 << 6), difference.gpr_mask);
    try std.testing.expectEqual(@as(u16, 1 << 1), difference.xmm_mask);

    saved.restore(&regs, &xmm);
    try std.testing.expectEqual(@as(u64, 14), regs.r14);
    try std.testing.expectEqual(@as(u64, 0x1234), regs.rax);
    try std.testing.expectEqual(@as(u8, 0xA7), xmm[7][3]);
    try std.testing.expectEqual(@as(u8, 0), xmm[0][3]);
    try std.testing.expect(!saved.difference(&regs, &xmm).any());
}
