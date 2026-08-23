//! The execution context shared by every PowerPC instruction family.
//!
//! `Outcome` is deliberately not a bare error union. Three of its cases are
//! ordinary control flow that the caller must act on (a taken branch, a system
//! call, a trap), and two are gaps in Rosette rather than faults in the guest
//! (`illegal` and `unimplemented`). Collapsing those into one error type is how
//! a missing handler ends up reported as a guest crash, which sends the next
//! investigation to the wrong side of the boundary. `unimplemented` carries the
//! opcode so the gap names itself.

const std = @import("std");
const state_mod = @import("state.zig");
const memory_mod = @import("memory.zig");
const ppc_decode = @import("ppc_decode");

pub const State = state_mod.State;
pub const Memory = memory_mod.Memory;
pub const Fault = memory_mod.Fault;
pub const Op = ppc_decode.Op;
pub const Instruction = ppc_decode.Instruction;

/// What executing one instruction did to control flow.
pub const Outcome = union(enum) {
    /// Fall through to the next instruction.
    advance,
    /// Control transferred; the payload is the new PC.
    branch: u32,
    /// `sc` executed. The payload is the LEV field the guest passed.
    system_call: u7,
    /// A `tw`/`td` condition was met. The guest asked to trap.
    trap,
    /// The encoding decoded to no instruction at all.
    illegal,
    /// The instruction decoded, but Rosette has no handler for it yet. This is
    /// a Rosette gap, not a guest fault, and it names itself.
    unimplemented: Op,

    pub fn isGap(self: Outcome) bool {
        return switch (self) {
            .illegal, .unimplemented => true,
            else => false,
        };
    }
};

/// Everything one instruction is allowed to touch.
pub const Context = struct {
    state: *State,
    memory: Memory,

    pub fn init(state: *State, memory: Memory) Context {
        return .{ .state = state, .memory = memory };
    }

    /// Write a GPR. r0 is a normal register as a destination - only an address
    /// base treats it as literal zero (see `State.ra0`).
    pub inline fn setGpr(self: *Context, index: u5, value: u64) void {
        self.state.gpr[index] = value;
    }

    pub inline fn gpr(self: *const Context, index: u5) u64 {
        return self.state.gpr[index];
    }

    /// The record-bit side effect for an integer result.
    pub inline fn recordCr0(self: *Context, insn: Instruction, result: u64) void {
        if (insn.rc()) self.state.updateCr0(result);
    }

    /// A store anywhere in the reserved block breaks the reservation, whether
    /// or not it came from a stwcx. Losing this is how a guest spin lock stops
    /// spinning and starts corrupting.
    pub inline fn breakReservation(self: *Context, address: u32) void {
        if (self.state.reservation.covers(address)) self.state.reservation.clear();
    }
};

test "a gap names itself instead of looking like a guest fault" {
    const gap = Outcome{ .unimplemented = .vupkd3d128 };
    try std.testing.expect(gap.isGap());
    try std.testing.expectEqualStrings("vupkd3d128", gap.unimplemented.mnemonic());
    try std.testing.expect(!(Outcome{ .branch = 0x8200_0000 }).isGap());
    try std.testing.expect(!(Outcome{ .trap = {} }).isGap());
}

test "a store into a reserved block clears the reservation" {
    var st = State{};
    var buf = [_]u8{0} ** 256;
    var ctx = Context.init(&st, Memory.fromSlice(&buf, 0x8200_0000));
    st.reservation.set(0x8200_0040);
    ctx.breakReservation(0x8200_0000);
    try std.testing.expect(!st.reservation.valid);

    st.reservation.set(0x8200_0040);
    ctx.breakReservation(0x8200_0080);
    try std.testing.expect(st.reservation.valid);
}
