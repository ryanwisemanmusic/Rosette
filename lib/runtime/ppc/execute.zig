//! The PowerPC instruction dispatcher and step loop.
//!
//! Routing an opcode to its execution unit is done once, at compile time, into
//! a flat table indexed by the opcode. The alternative - trying each unit until
//! one claims the instruction - would make the *unimplemented* path the slowest
//! one and would let a routing mistake hide as a silent fallthrough to a unit
//! that happens to have a handler with the same name.
//!
//! The routing cannot come from the decoder's coarse group alone: `mfspr` and
//! `sync` are grouped with the integer instructions, `lfd` and `lvx` with the
//! memory ones, and `mcrfs` with the condition-register ones. The group is the
//! default; the exceptions are listed by name so each one is a decision on the
//! record rather than an accident of grouping.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const ctx_mod = @import("context.zig");

const integer = @import("integer.zig");
const branch = @import("branch.zig");
const loadstore = @import("loadstore.zig");
const fpu = @import("fpu.zig");
const vmx = @import("vmx.zig");
const system = @import("system.zig");

pub const Context = ctx_mod.Context;
pub const Outcome = ctx_mod.Outcome;
pub const Instruction = ctx_mod.Instruction;
pub const Fault = ctx_mod.Fault;
pub const Op = ctx_mod.Op;

pub const Unit = enum {
    integer,
    branch,
    loadstore,
    floating_point,
    vector,
    system,
    /// No unit: the encoding decoded to nothing.
    none,
};

/// Instructions the coarse group would route to the wrong unit.
///
/// The Xenon table carries no supervisor instructions at all - no rfid, no
/// segment-register or TLB moves - because Xbox 360 titles run in problem
/// state. An encoding for one decodes to `.invalid`, which is the right
/// answer: it is not a gap in Rosette, it is not a valid title instruction.
const system_ops = [_]Op{
    .sc,   .sync, .isync, .eieio, .mfspr,  .mtspr,
    .mftb, .mfcr, .mtcrf, .mcrxr, .tw,     .td,
    .twi,  .tdi,  .mfmsr, .mtmsr, .mtmsrd,
};

const branch_ops = [_]Op{
    .bx,   .bcx,   .bclrx, .bcctrx, .crand, .crandc,
    .cror, .crorc, .crxor, .crnand, .crnor, .creqv,
    .mcrf,
};

/// FPSCR access instructions, which the group calls condition-register work.
const fpu_ops = [_]Op{ .mcrfs, .mffsx, .mtfsfx, .mtfsb0x, .mtfsb1x, .mtfsfix };

/// The vector status moves, which do not start with `v`.
const vector_ops = [_]Op{ .mfvscr, .mtvscr };

fn startsWith(name: []const u8, prefix: []const u8) bool {
    return name.len >= prefix.len and std.mem.eql(u8, name[0..prefix.len], prefix);
}

fn unitFor(comptime op: Op) Unit {
    if (op == .invalid) return .none;
    for (system_ops) |candidate| if (op == candidate) return .system;
    for (branch_ops) |candidate| if (op == candidate) return .branch;
    for (fpu_ops) |candidate| if (op == candidate) return .floating_point;
    for (vector_ops) |candidate| if (op == candidate) return .vector;

    const name = @tagName(op);
    // Vector memory before scalar memory: `lvx` is a load, but not a GPR load.
    if (startsWith(name, "lv") or startsWith(name, "stv")) return .vector;
    if (name[0] == 'v') return .vector;
    if (startsWith(name, "lf") or startsWith(name, "stf")) return .floating_point;
    if (name[0] == 'f') return .floating_point;

    return switch (op.info().group) {
        .memory => .loadstore,
        .vector => .vector,
        .floating_point => .floating_point,
        else => .integer,
    };
}

const unit_table = blk: {
    @setEvalBranchQuota(200_000);
    const fields = @typeInfo(Op).@"enum".fields;
    var table: [fields.len]Unit = undefined;
    for (fields) |field| {
        table[field.value] = unitFor(@field(Op, field.name));
    }
    break :blk table;
};

pub fn unitOf(op: Op) Unit {
    return unit_table[@intFromEnum(op)];
}

/// Execute one already-decoded instruction. The PC is not touched; the caller
/// applies the outcome, because a caller that is single-stepping, tracing, or
/// unwinding needs to see the outcome before the PC moves.
pub fn executeInstruction(c: *Context, insn: Instruction) Fault!Outcome {
    return switch (unitOf(insn.op)) {
        .integer => integer.execute(c, insn),
        .branch => branch.execute(c, insn),
        .loadstore => loadstore.execute(c, insn),
        .floating_point => fpu.execute(c, insn),
        .vector => vmx.execute(c, insn),
        .system => system.execute(c, insn),
        .none => .illegal,
    };
}

/// Fetch, decode, and execute the instruction at the current PC, then apply the
/// outcome to the PC. Returns the outcome so the caller can act on a system
/// call, a trap, or a gap.
pub fn step(c: *Context) Fault!Outcome {
    const word = try c.memory.fetch(c.state.pc);
    const insn = ppc_decode.decodeWord(c.state.pc, word);
    const outcome = try executeInstruction(c, insn);
    switch (outcome) {
        .advance => c.state.pc = insn.nextAddress(),
        .branch => |target| c.state.pc = target,
        // A system call, a trap, and a gap all leave the PC on the instruction
        // that produced them: the caller decides whether to resume past it,
        // and a PC that had already moved would make that undecidable.
        .system_call, .trap, .illegal, .unimplemented => {},
    }
    c.state.instructions_retired +%= 1;
    return outcome;
}

/// Why a run stopped.
pub const Stop = union(enum) {
    /// The instruction budget ran out with the guest still runnable.
    budget_exhausted,
    system_call: u7,
    trap,
    illegal: u32,
    unimplemented: struct { address: u32, op: Op },
};

/// Execute up to `budget` instructions. Stops early on anything the caller has
/// to decide about; a memory fault propagates as an error with the guest PC
/// still pointing at the faulting instruction.
pub fn run(c: *Context, budget: u64) Fault!Stop {
    var executed: u64 = 0;
    while (executed < budget) : (executed += 1) {
        const address = c.state.pc;
        const outcome = try step(c);
        switch (outcome) {
            .advance, .branch => {},
            .system_call => |lev| return .{ .system_call = lev },
            .trap => return .trap,
            .illegal => return .{ .illegal = address },
            .unimplemented => |op| return .{ .unimplemented = .{ .address = address, .op = op } },
        }
    }
    return .budget_exhausted;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const State = ctx_mod.State;
const Memory = ctx_mod.Memory;

const base_address: u32 = 0x8200_0000;

const Harness = struct {
    state: State = .{},
    buf: [512]u8 = [_]u8{0} ** 512,

    fn load(self: *Harness, words: []const u32) void {
        for (words, 0..) |word, i| {
            std.mem.writeInt(u32, self.buf[i * 4 ..][0..4], word, .big);
        }
        self.state.pc = base_address;
    }

    fn context(self: *Harness) Context {
        return Context.init(&self.state, Memory.fromSlice(&self.buf, base_address));
    }
};

test "routing sends each instruction to the unit that owns it" {
    try testing.expectEqual(Unit.integer, unitOf(.addx));
    try testing.expectEqual(Unit.branch, unitOf(.bclrx));
    try testing.expectEqual(Unit.branch, unitOf(.cror));
    try testing.expectEqual(Unit.loadstore, unitOf(.lwz));
    try testing.expectEqual(Unit.loadstore, unitOf(.stwcx));
    try testing.expectEqual(Unit.floating_point, unitOf(.faddx));
    try testing.expectEqual(Unit.vector, unitOf(.vaddubm));
    try testing.expectEqual(Unit.system, unitOf(.sc));
    try testing.expectEqual(Unit.none, unitOf(.invalid));
}

test "the routing exceptions land where the group would not put them" {
    // Grouped with the integer instructions, executed by the system unit.
    try testing.expectEqual(Unit.system, unitOf(.sync));
    try testing.expectEqual(Unit.system, unitOf(.mfspr));
    // Grouped with memory, executed by the float and vector units.
    try testing.expectEqual(Unit.floating_point, unitOf(.lfd));
    try testing.expectEqual(Unit.floating_point, unitOf(.stfiwx));
    try testing.expectEqual(Unit.vector, unitOf(.lvx));
    try testing.expectEqual(Unit.vector, unitOf(.stvewx));
    // Grouped with the condition register, executed by the float unit.
    try testing.expectEqual(Unit.floating_point, unitOf(.mcrfs));
    try testing.expectEqual(Unit.floating_point, unitOf(.mffsx));
    // Grouped with the condition register, executed by the vector unit.
    try testing.expectEqual(Unit.vector, unitOf(.mfvscr));
}

test "every opcode routes somewhere" {
    inline for (@typeInfo(Op).@"enum".fields) |field| {
        const op: Op = @enumFromInt(field.value);
        const unit = unitOf(op);
        if (op == .invalid) {
            try testing.expectEqual(Unit.none, unit);
        } else {
            try testing.expect(unit != .none);
        }
    }
}

test "a straight-line run advances the PC four bytes at a time" {
    var h = Harness{};
    h.load(&.{
        0x38600001, // li  r3, 1
        0x38800002, // li  r4, 2
        0x7C632214, // add r3, r3, r4
    });
    var c = h.context();
    const stop = try run(&c, 3);
    try testing.expectEqual(Stop.budget_exhausted, stop);
    try testing.expectEqual(@as(u64, 3), h.state.gpr[3]);
    try testing.expectEqual(base_address + 12, h.state.pc);
    try testing.expectEqual(@as(u64, 3), h.state.instructions_retired);
}

test "a loop terminates through CTR" {
    var h = Harness{};
    h.load(&.{
        0x38600000, // li    r3, 0
        0x38630001, // addi  r3, r3, 1
        0x4200FFFC, // bdnz  -4
        0x44000002, // sc            (the loop exit)
    });
    h.state.ctr = 5;
    var c = h.context();
    // A budget far larger than the loop needs: if the CTR decrement were
    // skipped on any path the run would spend the whole budget instead.
    const stop = try run(&c, 1000);
    try testing.expectEqual(@as(u7, 0), stop.system_call);
    try testing.expectEqual(@as(u64, 5), h.state.gpr[3]);
    try testing.expectEqual(@as(u64, 0), h.state.ctr);
    try testing.expectEqual(@as(u64, 12), h.state.instructions_retired);
}

test "a call and return move through LR" {
    var h = Harness{};
    h.load(&.{
        0x48000009, // bl   +8   (to word 2)
        0x38600063, // li   r3, 99  (skipped, then reached after return)
        0x38800007, // li   r4, 7
        0x4E800020, // blr
    });
    var c = h.context();
    // bl, li r4, blr, then the instruction after the call.
    _ = try step(&c);
    try testing.expectEqual(base_address + 8, h.state.pc);
    try testing.expectEqual(@as(u64, base_address + 4), h.state.lr);
    _ = try step(&c);
    _ = try step(&c);
    try testing.expectEqual(base_address + 4, h.state.pc);
    _ = try step(&c);
    try testing.expectEqual(@as(u64, 99), h.state.gpr[3]);
    try testing.expectEqual(@as(u64, 7), h.state.gpr[4]);
}

test "a system call stops the run with the PC still on the sc" {
    var h = Harness{};
    h.load(&.{
        0x38600001, // li r3, 1
        0x44000002, // sc
        0x38600002, // li r3, 2  (must not run)
    });
    var c = h.context();
    const stop = try run(&c, 10);
    try testing.expectEqual(@as(u7, 0), stop.system_call);
    try testing.expectEqual(@as(u64, 1), h.state.gpr[3]);
    try testing.expectEqual(base_address + 4, h.state.pc);
}

test "an unimplemented instruction stops the run and names itself" {
    var h = Harness{};
    h.load(&.{
        0x38600001, // li r3, 1
        0x18000210, // vpermwi128
    });
    var c = h.context();
    const stop = try run(&c, 10);
    try testing.expectEqual(Op.vpermwi128, stop.unimplemented.op);
    try testing.expectEqual(base_address + 4, stop.unimplemented.address);
    try testing.expectEqual(base_address + 4, h.state.pc);
}

test "an unallocated encoding stops as illegal, not as unimplemented" {
    var h = Harness{};
    h.load(&.{0x04000000});
    var c = h.context();
    const stop = try run(&c, 10);
    try testing.expectEqual(base_address, stop.illegal);
}

test "a memory fault leaves the PC on the faulting instruction" {
    var h = Harness{};
    h.load(&.{
        0x38800000, // li  r4, 0
        0x80640000, // lwz r3, 0(r4)   -> effective address 0, outside the map
    });
    var c = h.context();
    try testing.expectError(Fault.OutOfBounds, run(&c, 10));
    try testing.expectEqual(base_address + 4, h.state.pc);
}

test "a mixed integer, memory, float, and vector sequence runs end to end" {
    var h = Harness{};
    h.load(&.{
        0x3C608200, // lis   r3, 0x8200
        0x60630100, // ori   r3, r3, 0x0100
        0x38800005, // li    r4, 5
        0x90830000, // stw   r4, 0(r3)
        0x80A30000, // lwz   r5, 0(r3)
        0x7CA62A14, // add   r5, r6, r5
    });
    h.state.gpr[6] = 10;
    var c = h.context();
    const stop = try run(&c, 6);
    try testing.expectEqual(Stop.budget_exhausted, stop);
    // lis sign-extends on PPC64: `lis r3, 0x8200` is 0xFFFFFFFF82000000, not
    // 0x82000000. The effective address truncates back to 32 bits, which is why
    // the store below still lands where the guest meant it to.
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_8200_0100), h.state.gpr[3]);
    try testing.expectEqual(@as(u64, 15), h.state.gpr[5]);
}
