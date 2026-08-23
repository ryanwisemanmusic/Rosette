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
    pub const vrsave: u10 = 256;
    pub const tbl_read: u10 = 268;
    pub const tbu_read: u10 = 269;
    pub const sprg0: u10 = 272;
    pub const sprg1: u10 = 273;
    pub const sprg2: u10 = 274;
    pub const sprg3: u10 = 275;
    pub const tbl_write: u10 = 284;
    pub const tbu_write: u10 = 285;
    pub const pvr: u10 = 287;
    /// Xenon hardware-implementation registers. The kernel writes them during
    /// bring-up and reads them back; nothing in Rosette acts on their contents.
    pub const hid0: u10 = 1008;
    pub const hid1: u10 = 1009;
    pub const iabr: u10 = 1010;
    pub const hid4: u10 = 1012;
    pub const dabr: u10 = 1013;
    pub const dabrx: u10 = 1015;
    pub const buscsr: u10 = 1016;
    pub const l2cr: u10 = 1017;
    /// Processor identification. Read-only on hardware.
    pub const pir: u10 = 1023;
    /// Xenon performance monitor: one control register and six counters.
    pub const mmcr0: u10 = 952;
    pub const pmc1: u10 = 953;
    pub const pmc2: u10 = 954;
    pub const pmc3: u10 = 957;
    pub const pmc4: u10 = 958;
    pub const mmcr1: u10 = 956;
    pub const mmcra: u10 = 955;

    /// SPRs that are pure storage on the Xenon: the kernel writes a value and
    /// expects to read the same value back, and nothing else in the machine
    /// observes them.
    ///
    /// Modelling these as storage rather than refusing them is the difference
    /// between a kernel bring-up path that completes and one that stops on its
    /// first configuration write. Modelling *everything* as storage would be
    /// the opposite mistake: an SPR with real semantics would read back the
    /// value written instead of the value the hardware would have produced,
    /// which is a wrong answer rather than a missing one.
    pub const storage_backed = [_]u10{
        dsisr, dar,  dabr,   dabrx, iabr,  hid0,  hid1,
        hid4,  l2cr, buscsr, mmcr0, mmcr1, mmcra, pmc1,
        pmc2,  pmc3, pmc4,
    };

    pub fn isStorageBacked(number: u10) bool {
        for (storage_backed) |candidate| {
            if (candidate == number) return true;
        }
        return false;
    }
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
    /// Vector register save mask. The guest saves and restores it around
    /// vector code, so it has to read back what was written.
    vrsave: u32 = 0,
    /// Decrementer. Rosette does not tick it; the scheduler owns guest time.
    decrementer: u32 = 0,
    /// Backing store for the Xenon SPRs listed in `Spr.storage_backed`.
    spr_storage: [Spr.storage_backed.len]u64 = [_]u64{0} ** Spr.storage_backed.len,
    /// Processor identification, reported to the guest as-is.
    processor_id: u64 = 0,
    /// The Xenon's processor version register, reported to the guest as-is.
    pvr: u32 = 0x00710200,

    /// Current instruction address. 32-bit: the Xbox 360 address space is.
    pc: u32 = 0,
    reservation: Reservation = .{},
    /// Instructions retired, for throughput accounting and watchdogs.
    instructions_retired: u64 = 0,
    /// Set by `icbi`. The dispatcher drains it and drops any compiled code for
    /// that block: `icbi` followed by `isync` is the architected way a guest
    /// says "the instructions at this address changed", and it is the only
    /// notice a recompiler is entitled to.
    pending_icache_invalidation: ?u32 = null,
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
            Spr.vrsave => self.vrsave,
            Spr.tbl_read, Spr.tbl_write => self.time_base & 0xFFFFFFFF,
            Spr.tbu_read, Spr.tbu_write => self.time_base >> 32,
            Spr.dec => self.decrementer,
            Spr.pvr => self.pvr,
            Spr.pir => self.processor_id,
            else => if (Spr.isStorageBacked(number)) self.storageSpr(number) else null,
        };
    }

    /// Find the storage slot for an SPR, or null if it has none.
    fn storageSlot(number: u10) ?usize {
        for (Spr.storage_backed, 0..) |candidate, index| {
            if (candidate == number) return index;
        }
        return null;
    }

    fn storageSpr(self: *const State, number: u10) u64 {
        return if (storageSlot(number)) |index| self.spr_storage[index] else 0;
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
            Spr.vrsave => self.vrsave = @truncate(value),
            Spr.dec => self.decrementer = @truncate(value),
            // The time base is writable through 284/285 and read through
            // 268/269; the read-side numbers are not writable.
            Spr.tbl_write => self.time_base = (self.time_base & 0xFFFFFFFF_00000000) |
                (value & 0xFFFFFFFF),
            Spr.tbu_write => self.time_base = (self.time_base & 0xFFFFFFFF) |
                (value << 32),
            // PVR and PIR identify the processor. A write is architecturally
            // ignored rather than refused: the kernel does not expect a fault.
            Spr.pvr, Spr.pir => {},
            else => {
                const index = storageSlot(number) orelse return false;
                self.spr_storage[index] = value;
            },
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
    try std.testing.expectEqual(@as(?u64, null), state.readSpr(700));
    try std.testing.expect(!state.writeSpr(700, 1));
}

test "VRSAVE round-trips so a vector save/restore pair is not lossy" {
    var state = State{};
    try std.testing.expect(state.writeSpr(Spr.vrsave, 0xFFFF_0001));
    try std.testing.expectEqual(@as(?u64, 0xFFFF_0001), state.readSpr(Spr.vrsave));
    try std.testing.expectEqual(@as(u32, 0xFFFF_0001), state.vrsave);
}

test "a storage-backed Xenon SPR reads back exactly what was written" {
    var state = State{};
    for (Spr.storage_backed) |number| {
        const value: u64 = 0x1000 + @as(u64, number);
        try std.testing.expect(state.writeSpr(number, value));
        try std.testing.expectEqual(@as(?u64, value), state.readSpr(number));
    }
    // Each one has its own slot: writing one must not disturb another.
    try std.testing.expect(state.readSpr(Spr.hid0).? != state.readSpr(Spr.hid1).?);
}

test "the time base is written through 284/285 and read through 268/269" {
    var state = State{};
    try std.testing.expect(state.writeSpr(Spr.tbl_write, 0xAABB_CCDD));
    try std.testing.expect(state.writeSpr(Spr.tbu_write, 0x1122_3344));
    try std.testing.expectEqual(@as(u64, 0x1122_3344_AABB_CCDD), state.time_base);
    try std.testing.expectEqual(@as(?u64, 0xAABB_CCDD), state.readSpr(Spr.tbl_read));
    try std.testing.expectEqual(@as(?u64, 0x1122_3344), state.readSpr(Spr.tbu_read));
}

test "PVR and PIR accept a write without faulting and keep identifying the core" {
    var state = State{};
    const pvr_before = state.readSpr(Spr.pvr).?;
    // Hardware ignores the write; refusing it would fault a kernel that does
    // not expect one.
    try std.testing.expect(state.writeSpr(Spr.pvr, 0));
    try std.testing.expectEqual(@as(?u64, pvr_before), state.readSpr(Spr.pvr));
    try std.testing.expectEqual(@as(?u64, 0), state.readSpr(Spr.pir));
}
