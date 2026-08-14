//! Observation of guest traffic to the Xenos memory-mapped register aperture.
//!
//! The run this exists for ended with the emulator reporting "guest has not
//! written CP_RB_BASE/CP_RB_CNTL/CP_RB_WPTR", and nothing anywhere could say
//! which of two opposite things that meant:
//!
//!   1. the title never executed those stores, so the frontier is upstream in
//!      the title's own code and the GPU path is untested rather than broken;
//!   2. the title did execute them, and the stores never reached the register
//!      handler, so the frontier is Rosette's fault delivery and the title is
//!      doing everything right.
//!
//! Those point at opposite subsystems. Absence of a log line cannot distinguish
//! them, because *both* produce no log line — and a diagnosis derived from
//! silence is a guess whichever way it lands. So this counts the traffic
//! directly, and reports the answer as a positive statement in both directions:
//! either accesses were observed, with their registers, values and outcomes, or
//! none were, and that "none" is an observation the run actually made rather
//! than a line nobody printed.
//!
//! It is *observation only*. Nothing here services a register access, supplies
//! a value, or repairs a protection — the aperture's pages are meant to be
//! unreadable, and the fault they raise is the delivery mechanism, not an
//! error. Making them accessible would let register writes land in ordinary
//! memory where the command processor never sees them, with no fault left
//! anywhere to report it.

const std = @import("std");
const xenos = @import("device_tree").gpu.xenos;

/// Distinct registers tracked individually. The register file is far larger,
/// but the traffic that decides whether a ring starts is a handful of adjacent
/// indices, and a per-register table sized for the whole file would be mostly
/// zeroes.
pub const max_tracked_registers: usize = 32;

/// What happened to a fault raised by an aperture access.
pub const Delivery = enum {
    /// The fault was handed to a guest handler, which is how a register write
    /// reaches the emulator's register file.
    delivered,
    /// No handler took it. The access executed and its effect was lost.
    undelivered,

    pub fn describe(self: Delivery) []const u8 {
        return switch (self) {
            .delivered => "handed to the guest's fault handler, which is how the emulator's register write path is reached",
            .undelivered => "no guest handler accepted it, so the register write executed and went nowhere",
        };
    }
};

pub const RegisterTraffic = struct {
    index: u32 = 0,
    reads: u64 = 0,
    writes: u64 = 0,
    delivered: u64 = 0,
    undelivered: u64 = 0,
    first_step: u64 = 0,
    first_rip: u64 = 0,
    first_thread: u64 = 0,
    last_value: u64 = 0,
    /// Whether any write to this register carried a value. A register written
    /// only with zero is a different finding from one never written.
    saw_nonzero_write: bool = false,

    pub fn touched(self: *const RegisterTraffic) bool {
        return self.reads != 0 or self.writes != 0;
    }

    pub fn name(self: *const RegisterTraffic) []const u8 {
        return xenos.registerName(self.index) orelse "<unnamed register index>";
    }
};

/// Why the ring never started, stated as an observation rather than a guess.
pub const Verdict = enum {
    /// No access to the aperture was ever observed.
    never_accessed,
    /// Accesses were observed, but none to the registers that constitute ring
    /// setup.
    accessed_but_no_ring_setup,
    /// Ring-setup registers were written and the writes reached a handler.
    ring_setup_delivered,
    /// Ring-setup registers were written and the writes reached nothing.
    ring_setup_lost,

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .never_accessed => "the guest never executed a single access to the Xenos register aperture in this run. This is an observation, not a missing log line: the aperture's pages are unreadable by design, so any access would have faulted and been counted here. The title's code never reached its register writes, which puts the frontier upstream of the GPU entirely — look at what the title is doing instead of programming the GPU, not at the ring, the command processor or the presenter",
            .accessed_but_no_ring_setup => "the guest reached the register aperture but never touched CP_RB_BASE, CP_RB_CNTL or CP_RB_WPTR. The GPU is being programmed, so the path works; the ring specifically is not being set up, which is a decision the title made and not a transport failure",
            .ring_setup_delivered => "the ring-setup registers were written and every write reached a guest handler. The register transport works end to end, so a ring that still does not start is a question for what the handler did with the values, not for whether they arrived",
            .ring_setup_lost => "the ring-setup registers were written and the writes reached no handler. The title is programming the GPU correctly and Rosette is dropping the stores on the floor — this is a fault-delivery defect in the runtime, and it is the whole reason the ring never starts",
        };
    }
};

pub const Observer = struct {
    registers: [max_tracked_registers]RegisterTraffic =
        [_]RegisterTraffic{.{}} ** max_tracked_registers,
    count: usize = 0,
    /// Accesses to registers beyond the tracked capacity. Counted, because a
    /// table that silently stops recording implies the traffic stopped.
    untracked_accesses: u64 = 0,
    total_reads: u64 = 0,
    total_writes: u64 = 0,
    total_delivered: u64 = 0,
    total_undelivered: u64 = 0,
    /// Accesses that landed in the aperture but not on a dword boundary. Worth
    /// separating: the register file is addressed in dwords, so a misaligned
    /// access is either a decode error on Rosette's side or a title doing
    /// something the hardware does not support.
    misaligned: u64 = 0,

    pub fn observe(
        self: *Observer,
        guest_address: u64,
        is_write: bool,
        value: u64,
        delivery: Delivery,
        rip: u64,
        guest_thread: u64,
        step: u64,
    ) void {
        const index = xenos.registerIndexOf(guest_address) orelse return;
        if (guest_address % xenos.register_stride != 0) self.misaligned +|= 1;

        if (is_write) self.total_writes +|= 1 else self.total_reads +|= 1;
        switch (delivery) {
            .delivered => self.total_delivered +|= 1,
            .undelivered => self.total_undelivered +|= 1,
        }

        const entry = self.entryFor(index) orelse {
            self.untracked_accesses +|= 1;
            return;
        };
        if (!entry.touched()) {
            entry.first_step = step;
            entry.first_rip = rip;
            entry.first_thread = guest_thread;
        }
        if (is_write) {
            entry.writes +|= 1;
            entry.last_value = value;
            if (value != 0) entry.saw_nonzero_write = true;
        } else {
            entry.reads +|= 1;
        }
        switch (delivery) {
            .delivered => entry.delivered +|= 1,
            .undelivered => entry.undelivered +|= 1,
        }
    }

    fn entryFor(self: *Observer, index: u32) ?*RegisterTraffic {
        for (self.registers[0..self.count]) |*entry| {
            if (entry.index == index) return entry;
        }
        if (self.count == self.registers.len) return null;
        const entry = &self.registers[self.count];
        self.count += 1;
        entry.* = .{ .index = index };
        return entry;
    }

    pub fn anyAccess(self: *const Observer) bool {
        return self.total_reads != 0 or self.total_writes != 0 or self.untracked_accesses != 0;
    }

    /// Writes to the three registers that constitute ring setup, and how many
    /// of them reached a handler.
    pub fn ringSetupWrites(self: *const Observer) struct { writes: u64, delivered: u64 } {
        var writes: u64 = 0;
        var delivered: u64 = 0;
        for (self.registers[0..self.count]) |entry| {
            if (!xenos.isRingSetupRegister(entry.index)) continue;
            writes +|= entry.writes;
            delivered +|= entry.delivered;
        }
        return .{ .writes = writes, .delivered = delivered };
    }

    pub fn verdict(self: *const Observer) Verdict {
        if (!self.anyAccess()) return .never_accessed;
        const ring = self.ringSetupWrites();
        if (ring.writes == 0) return .accessed_but_no_ring_setup;
        return if (ring.delivered != 0) .ring_setup_delivered else .ring_setup_lost;
    }
};

const testing = std.testing;

fn addressOf(index: u32) u64 {
    return xenos.register_aperture_base + index * xenos.register_stride;
}

test "the aperture's own addresses match the registers the emulator probes" {
    // The three addresses the emulator's bootstrap probe reports. If these
    // stop agreeing, every verdict below is about the wrong memory.
    try testing.expectEqual(@as(?u32, 0x01C0), xenos.registerIndexOf(0x7FC8_0700));
    try testing.expectEqual(@as(?u32, 0x01C1), xenos.registerIndexOf(0x7FC8_0704));
    try testing.expectEqual(@as(?u32, 0x01C5), xenos.registerIndexOf(0x7FC8_0714));
    try testing.expectEqualStrings("CP_RB_BASE", xenos.registerName(0x01C0).?);
    try testing.expectEqualStrings("CP_RB_WPTR", xenos.registerName(0x01C5).?);
    try testing.expect(xenos.registerIndexOf(0x7FC7_FFFF) == null);
    try testing.expect(xenos.registerIndexOf(0x7FC9_0000) == null);
}

// The finding the run actually produced, and the one that was previously
// indistinguishable from a missing log line.
test "no traffic at all is a positive finding about the title, not about the GPU" {
    const observer = Observer{};
    try testing.expectEqual(Verdict.never_accessed, observer.verdict());
    try testing.expect(std.mem.indexOf(u8, observer.verdict().describe(), "upstream of the GPU") != null);
}

test "ring setup that reaches a handler is separated from ring setup that does not" {
    var delivered = Observer{};
    delivered.observe(addressOf(0x01C0), true, 0x1000_0000, .delivered, 0x8245_0000, 5, 100);
    delivered.observe(addressOf(0x01C1), true, 0x0000_001B, .delivered, 0x8245_0004, 5, 101);
    delivered.observe(addressOf(0x01C5), true, 0x20, .delivered, 0x8245_0008, 5, 102);
    try testing.expectEqual(Verdict.ring_setup_delivered, delivered.verdict());

    // Same traffic, nothing accepting the faults. The title is doing its job
    // and the runtime is losing the writes — the opposite conclusion, and the
    // one that used to be reported identically.
    var lost = Observer{};
    lost.observe(addressOf(0x01C0), true, 0x1000_0000, .undelivered, 0x8245_0000, 5, 100);
    lost.observe(addressOf(0x01C5), true, 0x20, .undelivered, 0x8245_0008, 5, 102);
    try testing.expectEqual(Verdict.ring_setup_lost, lost.verdict());
    try testing.expect(std.mem.indexOf(u8, lost.verdict().describe(), "fault-delivery defect") != null);
}

test "aperture traffic that avoids the ring registers is its own finding" {
    var observer = Observer{};
    observer.observe(addressOf(0x01CC), true, 0x2000, .delivered, 0x8245_0100, 5, 200);
    try testing.expectEqual(Verdict.accessed_but_no_ring_setup, observer.verdict());
    try testing.expectEqual(@as(u64, 1), observer.total_writes);
    try testing.expectEqual(@as(u64, 0), observer.total_reads);
}

test "per-register traffic keeps first evidence and the last value written" {
    var observer = Observer{};
    observer.observe(addressOf(0x01C5), true, 0x20, .delivered, 0xaaaa, 7, 1000);
    observer.observe(addressOf(0x01C5), true, 0x40, .delivered, 0xbbbb, 7, 2000);
    observer.observe(addressOf(0x01C5), false, 0, .delivered, 0xcccc, 7, 3000);

    const entry = observer.registers[0];
    try testing.expectEqual(@as(u32, 0x01C5), entry.index);
    try testing.expectEqual(@as(u64, 2), entry.writes);
    try testing.expectEqual(@as(u64, 1), entry.reads);
    try testing.expectEqual(@as(u64, 0x40), entry.last_value);
    try testing.expectEqual(@as(u64, 1000), entry.first_step);
    try testing.expectEqual(@as(u64, 0xaaaa), entry.first_rip);
    try testing.expect(entry.saw_nonzero_write);
    try testing.expectEqualStrings("CP_RB_WPTR", entry.name());
}

// A ring pointer written only with zero advances nothing, and reads exactly
// like a ring pointer that was written properly if only the count is kept.
test "a register written only with zero is distinguishable from one written with a value" {
    var observer = Observer{};
    observer.observe(addressOf(0x01C0), true, 0, .delivered, 0xaaaa, 7, 1000);
    try testing.expect(!observer.registers[0].saw_nonzero_write);
    try testing.expectEqual(Verdict.ring_setup_delivered, observer.verdict());
}

test "addresses outside the aperture are not counted as register traffic" {
    var observer = Observer{};
    observer.observe(0x8245_0390, true, 1, .delivered, 0, 0, 0);
    try testing.expect(!observer.anyAccess());
    try testing.expectEqual(Verdict.never_accessed, observer.verdict());
}

test "the protection this aperture needs is the one that looks like corruption" {
    const Ruling = @import("device_tree").constraint.Ruling;
    // A no-access page here is the design. Saying so is what stops a mapping
    // repair from quietly turning register writes into writes to RAM.
    try testing.expectEqual(
        Ruling.permitted,
        xenos.checkRegisterProtection(0x7FC8_0700, false).ruling,
    );
    try testing.expectEqual(
        Ruling.violates_hardware,
        xenos.checkRegisterProtection(0x7FC8_0700, true).ruling,
    );
    // Outside the aperture the question does not apply, and "unconstrained"
    // must never be read as approval.
    try testing.expectEqual(
        Ruling.unconstrained,
        xenos.checkRegisterProtection(0x8245_0390, true).ruling,
    );
}
