//! Rosette's PowerPC execution runtime.
//!
//! This is the ARM64-native half of the direct PPC path: where ISA/ppc/decode
//! answers "what is this encoding", this answers "what does it do to guest
//! state". Nothing here goes through an x86-64 intermediate - a PowerPC load
//! becomes a bounds-checked big-endian read and a PowerPC add becomes an add,
//! rather than becoming the x86-64 a PowerPC JIT would have emitted and then
//! becoming ARM64 a second time.
//!
//!   state      - the architected register file: GPR/FPR/VR, CR, LR, CTR, XER
//!   memory     - big-endian guest memory with bounds-checked faults
//!   context    - what one instruction may touch, and what it may report back
//!   integer    - arithmetic, logical, shift, rotate, compare
//!   branch     - branches and the condition-register logical ops
//!   loadstore  - loads, stores, atomics, cache management
//!   fpu        - floating point, conversion, FPSCR
//!   vmx        - AltiVec
//!   vmx128     - the Xenon's 128-register VMX128 extension
//!   system     - system calls, SPRs, traps, barriers
//!   execute    - opcode routing and the step loop
//!   host_abi   - the C ABI an embedder (Xenia's macOS PPC backend) calls
//!   jit        - the PowerPC to ARM64 block recompiler
//!
//! Coverage is measured, not asserted: `coverage()` runs every opcode in the
//! table through the dispatcher and counts which ones reach a handler. A gap
//! shows up as a number that went down, not as a guest that behaves oddly.

const std = @import("std");
const ppc_decode = @import("ppc_decode");

pub const state = @import("state.zig");
pub const memory = @import("memory.zig");
pub const context = @import("context.zig");
pub const integer = @import("integer.zig");
pub const branch = @import("branch.zig");
pub const loadstore = @import("loadstore.zig");
pub const fpu = @import("fpu.zig");
pub const vmx = @import("vmx.zig");
pub const vmx128 = @import("vmx128.zig");
pub const system = @import("system.zig");
pub const execute = @import("execute.zig");
pub const host_abi = @import("host_abi.zig");
pub const jit = @import("jit/root.zig");
/// Differential verification of the recompiler against the interpreter.
const jit_differential = @import("jit_differential.zig");

pub const State = state.State;
pub const Xer = state.Xer;
pub const Vector = state.Vector;
pub const Memory = memory.Memory;
pub const Fault = memory.Fault;
pub const Context = context.Context;
pub const Outcome = context.Outcome;
pub const Op = ppc_decode.Op;
pub const Instruction = ppc_decode.Instruction;
pub const Unit = execute.Unit;
pub const Stop = execute.Stop;

pub const step = execute.step;
pub const run = execute.run;
pub const executeInstruction = execute.executeInstruction;
pub const unitOf = execute.unitOf;
pub const decodeWord = ppc_decode.decodeWord;
pub const decodeBytes = ppc_decode.decodeBytes;

/// How much of the Xenon instruction set currently reaches a handler.
pub const Coverage = struct {
    total: usize,
    implemented: usize,
    /// Instructions that decode but have no handler yet.
    gaps: usize,

    pub fn percent(self: Coverage) f64 {
        if (self.total == 0) return 0;
        return @as(f64, @floatFromInt(self.implemented)) * 100.0 /
            @as(f64, @floatFromInt(self.total));
    }
};

/// The encoding used to probe one opcode for coverage.
///
/// The canonical pattern has every variable field zeroed, which is a valid
/// instruction for almost everything. The exceptions are the SPR moves: SPR 0
/// and TBR 0 do not exist on any PowerPC, so probing with the zero pattern
/// would report `mfspr` as unimplemented no matter how many SPRs are modelled.
/// Probing those with a register the architecture actually defines measures the
/// handler instead of the field.
fn probeEncoding(op: Op) u32 {
    const pattern = op.info().pattern;
    // The SPR field stores its two five-bit halves swapped.
    const spr_lr: u32 = ((8 & 0x1F) << 5) | ((8 >> 5) & 0x1F);
    const tbr_tbl: u32 = ((268 & 0x1F) << 5) | ((268 >> 5) & 0x1F);
    return switch (op) {
        .mfspr, .mtspr => pattern | (spr_lr << 11),
        .mftb => pattern | (tbr_tbl << 11),
        else => pattern,
    };
}

/// Probe every opcode in the table by executing its canonical encoding against
/// scratch state, and count which ones reach a handler.
///
/// Every field in a canonical pattern is zero, so the probe reads r0 and writes
/// r0 and addresses guest zero - which is why the scratch mapping starts at
/// zero and is large enough for a 128-byte cache block and a 32-register
/// multiple-word store. A memory fault still counts as implemented: the
/// instruction ran, it just ran off the end of a deliberately small map.
pub fn coverage() Coverage {
    @setEvalBranchQuota(200_000);
    var scratch: State = .{};
    var buffer: [1024]u8 = [_]u8{0} ** 1024;
    var total: usize = 0;
    var implemented: usize = 0;

    inline for (@typeInfo(Op).@"enum".fields) |field| {
        const op: Op = @enumFromInt(field.value);
        if (op != .invalid) {
            total += 1;
            var ctx = Context.init(&scratch, Memory.fromSlice(&buffer, 0));
            const insn = ppc_decode.decodeWord(0, probeEncoding(op));
            if (execute.executeInstruction(&ctx, insn)) |outcome| {
                switch (outcome) {
                    .unimplemented, .illegal => {},
                    else => implemented += 1,
                }
            } else |_| implemented += 1;
        }
    }
    return .{ .total = total, .implemented = implemented, .gaps = total - implemented };
}

/// Write a human-readable coverage report, grouped by execution unit.
pub fn reportCoverage(writer: anytype) !void {
    @setEvalBranchQuota(400_000);
    const summary = coverage();
    try writer.print(
        "PPC instruction coverage: {d}/{d} ({d:.1}%), {d} gap(s)\n",
        .{ summary.implemented, summary.total, summary.percent(), summary.gaps },
    );

    var scratch: State = .{};
    var buffer: [1024]u8 = [_]u8{0} ** 1024;
    inline for (@typeInfo(Unit).@"enum".fields) |unit_field| {
        const unit: Unit = @enumFromInt(unit_field.value);
        if (unit != .none) {
            var unit_total: usize = 0;
            var unit_done: usize = 0;
            inline for (@typeInfo(Op).@"enum".fields) |field| {
                const op: Op = @enumFromInt(field.value);
                if (op != .invalid and execute.unitOf(op) == unit) {
                    unit_total += 1;
                    var ctx = Context.init(&scratch, Memory.fromSlice(&buffer, 0));
                    const insn = ppc_decode.decodeWord(0, probeEncoding(op));
                    if (execute.executeInstruction(&ctx, insn)) |outcome| {
                        switch (outcome) {
                            .unimplemented, .illegal => {},
                            else => unit_done += 1,
                        }
                    } else |_| unit_done += 1;
                }
            }
            try writer.print("  {s:<16} {d:>3}/{d:<3}\n", .{
                unit_field.name, unit_done, unit_total,
            });
        }
    }
}

test {
    std.testing.refAllDecls(@This());
    _ = state;
    _ = memory;
    _ = context;
    _ = integer;
    _ = branch;
    _ = loadstore;
    _ = fpu;
    _ = vmx;
    _ = vmx128;
    _ = system;
    _ = execute;
    _ = host_abi;
    _ = jit;
    _ = jit_differential;
}

test "instruction coverage is measured and does not regress" {
    const summary = coverage();
    try std.testing.expectEqual(@as(usize, 455), summary.total);
    // Every Xenon encoding reaches a handler. The measurement is a probe, not
    // an assertion in a comment: it executes each opcode's canonical encoding
    // through the dispatcher, so a handler that is deleted or misrouted shows
    // up here rather than as a guest that behaves oddly.
    try std.testing.expectEqual(@as(usize, 455), summary.implemented);
    try std.testing.expectEqual(@as(usize, 0), summary.gaps);
}

test "the 4-20-20-20 vertex sub-format reaches the VMX128 handler" {
    var scratch: State = .{};
    var buffer: [256]u8 = [_]u8{0} ** 256;
    var ctx = Context.init(&scratch, Memory.fromSlice(&buffer, 0));

    const four_twenty = @as(u32, 6) << 2; // type 6 in the VX128_3/4 immediate
    const unpack_word = Op.vupkd3d128.info().pattern | (four_twenty << 16);
    const high = (@as(u32, 0xA) << 28) | (@as(u32, 0x34567) << 8) | 0xFF;
    const low = (@as(u32, 0xFFFFF) << 20) | 0x12345;
    scratch.vr[0] = .{ 0, 0, high, low };
    const outcome = try executeInstruction(&ctx, decodeWord(0, unpack_word));
    try std.testing.expectEqual(Outcome.advance, outcome);
    try std.testing.expectEqual(@as(u32, 0x40412345), scratch.vr[0][0]);
    try std.testing.expectEqual(@as(u32, 0x403FFFFF), scratch.vr[0][1]);
    try std.testing.expectEqual(@as(u32, 0x40434567), scratch.vr[0][2]);
    try std.testing.expectEqual(@as(u32, 0x3F80000A), scratch.vr[0][3]);
}

test "every implemented instruction belongs to a real execution unit" {
    inline for (@typeInfo(Op).@"enum".fields) |field| {
        const op: Op = @enumFromInt(field.value);
        if (op != .invalid) {
            try std.testing.expect(execute.unitOf(op) != .none);
        }
    }
}

test "a PowerPC program runs end to end through the public entry points" {
    var scratch: State = .{};
    var buffer: [256]u8 = [_]u8{0} ** 256;
    const program = [_]u32{
        0x3860000A, // li   r3, 10
        0x38800020, // li   r4, 32
        0x7C632214, // add  r3, r3, r4
        0x44000002, // sc
    };
    for (program, 0..) |word, i| {
        std.mem.writeInt(u32, buffer[i * 4 ..][0..4], word, .big);
    }
    scratch.pc = 0;

    var ctx = Context.init(&scratch, Memory.fromSlice(&buffer, 0));
    const stop = try run(&ctx, 16);
    try std.testing.expectEqual(@as(u7, 0), stop.system_call);
    try std.testing.expectEqual(@as(u64, 42), scratch.gpr[3]);
    try std.testing.expectEqual(@as(u64, 4), scratch.instructions_retired);
}
