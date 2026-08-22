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
//!   system     - system calls, SPRs, traps, barriers
//!   execute    - opcode routing and the step loop
//!   host_abi   - the C ABI an embedder (Xenia's macOS PPC backend) calls
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
pub const system = @import("system.zig");
pub const execute = @import("execute.zig");
pub const host_abi = @import("host_abi.zig");

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
            const insn = ppc_decode.decodeWord(0, op.info().pattern);
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
                    const insn = ppc_decode.decodeWord(0, op.info().pattern);
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
    _ = system;
    _ = execute;
    _ = host_abi;
}

test "instruction coverage is measured and does not regress" {
    const summary = coverage();
    try std.testing.expectEqual(@as(usize, 455), summary.total);
    // 313/455 as of this pass: the scalar core is complete (integer 67/67,
    // branch 13/13, float 56/56) and AltiVec is 104/239. The gaps are the 75
    // VMX128 encodings, the AltiVec multiply-accumulate and pack tail, and the
    // four string load/store forms - each named individually by the dispatcher
    // rather than silently executed as something else.
    try std.testing.expect(summary.implemented >= 313);
    try std.testing.expectEqual(summary.total, summary.implemented + summary.gaps);
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
