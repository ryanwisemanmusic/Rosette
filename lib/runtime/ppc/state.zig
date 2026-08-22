//! Xenon PowerPC architected state.
//!
//! Rosette's x86 path keeps guest state in a register file rather than in host
//! registers, and the PPC path does the same for the same reason: the guest's
//! architected state has to survive a host signal, a scheduler yield, and a
//! diagnostic dump, none of which can see a value that only exists in an ARM64
//! register. The cost is a load and a store per operand; the benefit is that
//! every piece of guest state is addressable at every instruction boundary.
//!
//! Three things here are easy to get subtly wrong and are therefore modelled
//! explicitly rather than as raw bit twiddling:
//!
//!   * CR is eight four-bit fields numbered from the *high* end of the word.
//!     CR0 lives in bits 28..31 of the host-order value, not bits 0..3.
//!   * XER's summary-overflow bit is sticky: OV is set per instruction, SO is
//!     set and never cleared except by mtxer/mcrxr. Treating them as one flag
//!     loses every overflow that happened before the one you are looking at.
//!   * The reservation set by lwarx is address-granular and must be cleared by
//!     any store to the reserved block, not just by a matching stwcx.

const std = @import("std");

/// A 128-bit vector register, viewed as four 32-bit lanes. AltiVec numbers its
/// lanes from the high end, so lane 0 here is the *most* significant word.
pub const Vector = [4]u32;

pub const zero_vector: Vector = .{ 0, 0, 0, 0 };

/// Condition-register field bits, in PowerPC order.
pub const CrBit = struct {
    pub const lt: u4 = 0b1000;
    pub const gt: u4 = 0b0100;
    pub const eq: u4 = 0b0010;
    pub const so: u4 = 0b0001;
};

/// The integer exception register, unpacked so the sticky bit stays visible.
pub const Xer = struct {
    /// Summary overflow. Sticky: set by any overflow, cleared only explicitly.
    so: bool = false,
    /// Overflow from the most recent OE=1 instruction.
    ov: bool = false,
    /// Carry out of the most recent carrying instruction.
    ca: bool = false,
    /// String-instruction byte count (lswx/stswx).
    byte_count: u7 = 0,

    pub fn pack(self: Xer) u64 {
        var value: u64 = self.byte_count;
        if (self.ca) value |= @as(u64, 1) << 29;
        if (self.ov) value |= @as(u64, 1) << 30;
        if (self.so) value |= @as(u64, 1) << 31;
        return value;
    }

    pub fn unpack(value: u64) Xer {
        return .{
            .so = (value >> 31) & 1 != 0,
            .ov = (value >> 30) & 1 != 0,
            .ca = (value >> 29) & 1 != 0,
            .byte_count = @truncate(value & 0x7F),
        };
    }

    /// Record an overflow: OV takes the new value, SO only ever latches on.
    pub fn recordOverflow(self: *Xer, overflowed: bool) void {
        self.ov = overflowed;
        if (overflowed) self.so = true;
    }
};

/// A reservation established by lwarx/ldarx.
pub const Reservation = struct {
    valid: bool = false,
    address: u32 = 0,
    /// The Xenon reserves a whole cache block, so a store anywhere in the block
    /// breaks the reservation even if its address is not the reserved one.
    pub const granule: u32 = 128;

    pub fn set(self: *Reservation, address: u32) void {
        self.valid = true;
        self.address = address & ~(granule - 1);
    }

    pub fn clear(self: *Reservation) void {
        self.valid = false;
        self.address = 0;
    }

    pub fn covers(self: Reservation, address: u32) bool {
        return self.valid and (address & ~(granule - 1)) == self.address;
    }
};

/// Special-purpose register numbers the Xbox 360 kernel actually uses.
pub const Spr = struct {
    pub const xer: u10 = 1;
    pub const lr: u10 = 8;
    pub const ctr: u10 = 9;
    pub const dsisr: u10 = 18;
    pub const dar: u10 = 19;
    pub const dec: u10 = 22;
    pub const srr0: u10 = 26;
    pub const srr1: u10 = 27;
    pub const sprg0: u10 = 272;
    pub const sprg1: u10 = 273;
    pub const sprg2: u10 = 274;
    pub const sprg3: u10 = 275;
    pub const tbl_read: u10 = 268;
    pub const tbu_read: u10 = 269;
    pub const pvr: u10 = 287;
};

/// The full architected register file.
pub const State = struct {
    gpr: [32]u64 = [_]u64{0} ** 32,
    fpr: [32]f64 = [_]f64{0} ** 32,
    /// The Xenon extends AltiVec's 32 vector registers to 128.
    vr: [128]Vector = [_]Vector{zero_vector} ** 128,

    /// Eight four-bit fields packed into one word, CR0 highest.
    cr: u32 = 0,
    lr: u64 = 0,
    ctr: u64 = 0,
    xer: Xer = .{},
    fpscr: u32 = 0,
    vscr: u32 = 0,
    msr: u64 = 0,
    /// Software-visible SPRs the kernel parks values in.
    sprg: [4]u64 = [_]u64{0} ** 4,
    srr0: u64 = 0,
    srr1: u64 = 0,
    /// The Xenon's processor version register, reported to the guest as-is.
    pvr: u32 = 0x00710200,

    /// Current instruction address. 32-bit: the Xbox 360 address space is.
    pc: u32 = 0,
    reservation: Reservation = .{},
    /// Instructions retired, for throughput accounting and watchdogs.
    instructions_retired: u64 = 0,
    /// Time base, advanced by the scheduler rather than by instruction count.
    time_base: u64 = 0,

    /// r0 is a real register everywhere except in an effective-address base,
    /// where the encoding means the literal value zero. Reading rA through this
    /// is the difference between `lwz r3, 8(0)` addressing 8 and addressing
    /// whatever r0 last held.
    pub fn ra0(self: *const State, index: u5) u64 {
        return if (index == 0) 0 else self.gpr[index];
    }

    pub fn crField(self: *const State, field: u3) u4 {
        const shift: u5 = @intCast((7 - @as(u5, field)) * 4);
        return @truncate(self.cr >> shift);
    }

    pub fn setCrField(self: *State, field: u3, value: u4) void {
        const shift: u5 = @intCast((7 - @as(u5, field)) * 4);
        const mask = @as(u32, 0xF) << shift;
        self.cr = (self.cr & ~mask) | (@as(u32, value) << shift);
    }

    /// CR bit index 0..31, numbered from the high end like the architecture.
    pub fn crBit(self: *const State, index: u5) u1 {
        return @truncate(self.cr >> (31 - index));
    }

    pub fn setCrBit(self: *State, index: u5, value: u1) void {
        const mask = @as(u32, 1) << (31 - index);
        self.cr = if (value != 0) self.cr | mask else self.cr & ~mask;
    }

    /// Set a CR field from a signed comparison, carrying XER.SO into bit 3.
    pub fn setCrCompare(self: *State, field: u3, lhs: i64, rhs: i64) void {
        var value: u4 = if (lhs < rhs) CrBit.lt else if (lhs > rhs) CrBit.gt else CrBit.eq;
        if (self.xer.so) value |= CrBit.so;
        self.setCrField(field, value);
    }

    /// Set a CR field from an unsigned comparison, carrying XER.SO into bit 3.
    pub fn setCrCompareUnsigned(self: *State, field: u3, lhs: u64, rhs: u64) void {
        var value: u4 = if (lhs < rhs) CrBit.lt else if (lhs > rhs) CrBit.gt else CrBit.eq;
        if (self.xer.so) value |= CrBit.so;
        self.setCrField(field, value);
    }

    /// The Rc=1 side effect on an integer instruction: compare the result
    /// against zero as a signed 64-bit value and write CR0.
    pub fn updateCr0(self: *State, result: u64) void {
        self.setCrCompare(0, @bitCast(result), 0);
    }

    /// The Rc=1 side effect on a floating-point instruction: CR1 takes the top
    /// four FPSCR bits (FX, FEX, VX, OX) rather than a comparison.
    pub fn updateCr1(self: *State) void {
        self.setCrField(1, @truncate(self.fpscr >> 28));
    }

    pub fn readSpr(self: *const State, number: u10) ?u64 {
        return switch (number) {
            Spr.xer => self.xer.pack(),
            Spr.lr => self.lr,
            Spr.ctr => self.ctr,
            Spr.srr0 => self.srr0,
            Spr.srr1 => self.srr1,
            Spr.sprg0 => self.sprg[0],
            Spr.sprg1 => self.sprg[1],
            Spr.sprg2 => self.sprg[2],
            Spr.sprg3 => self.sprg[3],
            Spr.tbl_read => self.time_base & 0xFFFFFFFF,
            Spr.tbu_read => self.time_base >> 32,
            Spr.pvr => self.pvr,
            else => null,
        };
    }

    pub fn writeSpr(self: *State, number: u10, value: u64) bool {
        switch (number) {
            Spr.xer => self.xer = Xer.unpack(value),
            Spr.lr => self.lr = value,
            Spr.ctr => self.ctr = value,
            Spr.srr0 => self.srr0 = value,
            Spr.srr1 => self.srr1 = value,
            Spr.sprg0 => self.sprg[0] = value,
            Spr.sprg1 => self.sprg[1] = value,
            Spr.sprg2 => self.sprg[2] = value,
            Spr.sprg3 => self.sprg[3] = value,
            else => return false,
        }
        return true;
    }
};

test "CR0 lives at the low end of the word even though it is field zero" {
    var state = State{};
    state.setCrField(0, CrBit.gt);
    try std.testing.expectEqual(@as(u32, 0x4000_0000), state.cr);
    state.setCrField(7, CrBit.eq);
    try std.testing.expectEqual(@as(u32, 0x4000_0002), state.cr);
    try std.testing.expectEqual(@as(u4, CrBit.gt), state.crField(0));
    try std.testing.expectEqual(@as(u4, CrBit.eq), state.crField(7));
}

test "CR bit indices are numbered from the high end" {
    var state = State{};
    state.setCrBit(0, 1); // CR0.LT
    try std.testing.expectEqual(@as(u32, 0x8000_0000), state.cr);
    try std.testing.expectEqual(@as(u1, 1), state.crBit(0));
    state.setCrBit(31, 1); // CR7.SO
    try std.testing.expectEqual(@as(u32, 0x8000_0001), state.cr);
}

test "a compare into CR carries the sticky overflow bit" {
    var state = State{};
    state.setCrCompare(0, -1, 0);
    try std.testing.expectEqual(@as(u4, CrBit.lt), state.crField(0));
    state.xer.so = true;
    state.setCrCompare(0, 5, 5);
    try std.testing.expectEqual(@as(u4, CrBit.eq | CrBit.so), state.crField(0));
}

test "summary overflow latches on and stays on" {
    var xer = Xer{};
    xer.recordOverflow(true);
    try std.testing.expect(xer.ov and xer.so);
    xer.recordOverflow(false);
    try std.testing.expect(!xer.ov);
    try std.testing.expect(xer.so); // sticky
}

test "XER round-trips through its packed form" {
    const xer = Xer{ .so = true, .ov = false, .ca = true, .byte_count = 9 };
    const round = Xer.unpack(xer.pack());
    try std.testing.expectEqual(xer.so, round.so);
    try std.testing.expectEqual(xer.ov, round.ov);
    try std.testing.expectEqual(xer.ca, round.ca);
    try std.testing.expectEqual(xer.byte_count, round.byte_count);
}

test "rA reads as literal zero only in an address base" {
    var state = State{};
    state.gpr[0] = 0xDEAD;
    try std.testing.expectEqual(@as(u64, 0), state.ra0(0));
    try std.testing.expectEqual(@as(u64, 0xDEAD), state.gpr[0]);
    state.gpr[3] = 7;
    try std.testing.expectEqual(@as(u64, 7), state.ra0(3));
}

test "a reservation covers its whole cache block" {
    var res = Reservation{};
    res.set(0x8200_0044);
    try std.testing.expect(res.covers(0x8200_0000));
    try std.testing.expect(res.covers(0x8200_007F));
    try std.testing.expect(!res.covers(0x8200_0080));
    res.clear();
    try std.testing.expect(!res.covers(0x8200_0000));
}

test "SPR reads and writes route to the architected slots" {
    var state = State{};
    try std.testing.expect(state.writeSpr(Spr.lr, 0x8205_1234));
    try std.testing.expectEqual(@as(u64, 0x8205_1234), state.lr);
    try std.testing.expectEqual(@as(?u64, 0x8205_1234), state.readSpr(Spr.lr));
    // An SPR Rosette does not model reports itself rather than silently
    // returning zero, so an unmodelled kernel SPR is visible as a gap.
    try std.testing.expectEqual(@as(?u64, null), state.readSpr(1013));
    try std.testing.expect(!state.writeSpr(1013, 1));
}
