//! Differential verification of the PowerPC block recompiler.
//!
//! A recompiler has exactly one correctness obligation: for the same starting
//! state, the compiled code and the interpreter must leave the same architected
//! state behind. Everything else - which instructions it chooses to compile,
//! how many it fits in a block, what the emitted sequence looks like - is free.
//!
//! So the tests here do not check the emitted instructions. They run both paths
//! over the same program from the same state and compare *all* of it: every
//! GPR, the condition register, XER, the reservation, the program counter, the
//! retired count, and the whole of guest memory. Checking only the registers a
//! test happens to think about is how a recompiler passes its tests and
//! corrupts a register nobody looked at.
//!
//! The last test is the one that finds things a hand-written corpus does not: a
//! seeded generator builds random well-formed encodings from the compiled
//! subset, over random starting state, and compares. A failure prints the
//! program so it can be pasted into a focused test.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const state_mod = @import("state.zig");
const memory_mod = @import("memory.zig");
const context_mod = @import("context.zig");
const execute_mod = @import("execute.zig");
const jit_mod = @import("jit/root.zig");

const State = state_mod.State;
const Memory = memory_mod.Memory;
const Context = context_mod.Context;
const testing = std.testing;

const base_address: u32 = 0;
const memory_size: usize = 4096;
/// Guest code lives at the bottom of the mapping; the data the tests load and
/// store lives above it, so a runaway store shows up as a difference in the
/// program rather than being invisible.
const data_offset: u32 = 1024;

const Harness = struct {
    interpreted: State = .{},
    compiled: State = .{},
    interpreted_memory: [memory_size]u8 = [_]u8{0} ** memory_size,
    compiled_memory: [memory_size]u8 = [_]u8{0} ** memory_size,
    jit: jit_mod.Jit,

    fn init(allocator: std.mem.Allocator) !Harness {
        return .{ .jit = try jit_mod.Jit.init(allocator, 256 * 1024) };
    }

    fn deinit(self: *Harness) void {
        self.jit.deinit();
    }

    /// Load the same program and the same seeded data into both sides.
    fn load(self: *Harness, program: []const u32, seed: u64) void {
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();

        for (program, 0..) |word, i| {
            std.mem.writeInt(u32, self.interpreted_memory[i * 4 ..][0..4], word, .big);
        }
        // Fill the data region with something distinguishable so a load that
        // reads the wrong address produces a different value rather than the
        // zero it would have read anyway.
        var i: usize = data_offset;
        while (i < memory_size) : (i += 1) {
            self.interpreted_memory[i] = random.int(u8);
        }
        self.compiled_memory = self.interpreted_memory;

        // Random register state, with the address registers pointed into the
        // data region so the memory instructions reach it.
        for (&self.interpreted.gpr, 0..) |*reg, index| {
            reg.* = if (index >= 24)
                data_offset + (random.int(u32) % 256) * 8
            else
                random.int(u64);
        }
        self.interpreted.cr = random.int(u32);
        self.interpreted.xer.so = random.boolean();
        self.interpreted.xer.ov = random.boolean();
        self.interpreted.xer.ca = random.boolean();
        self.interpreted.pc = base_address;
        self.compiled = self.interpreted;
    }

    fn interpreterMemory(self: *Harness) Memory {
        return Memory.fromSlice(&self.interpreted_memory, base_address);
    }

    fn compiledMemory(self: *Harness) Memory {
        return Memory.fromSlice(&self.compiled_memory, base_address);
    }

    /// True when the program bytes themselves were modified by the run.
    ///
    /// A store into the instruction stream is where a compiled block and an
    /// interpreter legitimately disagree: the block executes what it was
    /// compiled from, the interpreter fetches what is there now, and PowerPC
    /// requires `icbi` plus `isync` before modified code may be executed at
    /// all. Comparing the two after unsynchronised self-modification is
    /// comparing two correct answers to an undefined question.
    fn codeWasModified(self: *const Harness, program: []const u32) bool {
        const bytes = program.len * 4;
        return !std.mem.eql(
            u8,
            self.interpreted_memory[0..bytes],
            self.compiled_memory[0..bytes],
        ) or !std.mem.eql(u8, self.interpreted_memory[0..bytes], self.originalCode(program));
    }

    fn originalCode(self: *const Harness, program: []const u32) []const u8 {
        _ = self;
        // Rebuilt on demand rather than stored: the comparison only needs it
        // when something went wrong.
        const holder = struct {
            var buffer: [512]u8 = undefined;
        };
        for (program, 0..) |word, i| {
            std.mem.writeInt(u32, holder.buffer[i * 4 ..][0..4], word, .big);
        }
        return holder.buffer[0 .. program.len * 4];
    }

    /// Compile the block at the base address, run both paths over exactly the
    /// instructions it covers, and compare everything.
    fn compareBlock(self: *Harness, program: []const u32) !void {
        const block = (try self.jit.compileAt(self.compiledMemory(), base_address)) orelse {
            return error.NothingCompiled;
        };
        const result = self.jit.run(block, &self.compiled, self.compiledMemory());

        var ctx = Context.init(&self.interpreted, self.interpreterMemory());
        var executed: u32 = 0;
        while (executed < block.instruction_count) : (executed += 1) {
            _ = execute_mod.step(&ctx) catch {
                // The interpreter faulted. The block must have faulted at the
                // same instruction, and neither may have advanced past it.
                if (!result.faulted) {
                    // Report the state as well: a fault that only one path
                    // takes is usually the *symptom* of an earlier divergence
                    // in an address register, and the state comparison names it.
                    std.debug.print(
                        "\ninterpreter faulted at 0x{x:0>8}, compiled did not\n",
                        .{self.interpreted.pc},
                    );
                    self.expectSameState(program) catch {};
                    return error.FaultDisagreement;
                }
                try testing.expectEqual(self.interpreted.pc, self.compiled.pc);
                try testing.expectEqual(result.retired, executed);
                try self.expectSameState(program);
                return;
            };
        }

        if (result.faulted) {
            std.debug.print(
                "\ncompiled faulted at 0x{x:0>8}, interpreter did not\n",
                .{self.compiled.pc},
            );
            self.expectSameState(program) catch {};
            return error.FaultDisagreement;
        }
        try testing.expectEqual(block.instruction_count, result.retired);
        try self.expectSameState(program);
    }

    fn expectSameState(self: *Harness, program: []const u32) !void {
        var mismatch = false;
        for (self.interpreted.gpr, self.compiled.gpr, 0..) |want, got, index| {
            if (want != got) {
                std.debug.print(
                    "\nr{d}: interpreter 0x{x:0>16}, compiled 0x{x:0>16}\n",
                    .{ index, want, got },
                );
                mismatch = true;
            }
        }
        for (self.interpreted.fpr, self.compiled.fpr, 0..) |want, got, index| {
            const want_bits: u64 = @bitCast(want);
            const got_bits: u64 = @bitCast(got);
            if (want_bits != got_bits) {
                std.debug.print(
                    "\nf{d}: interpreter 0x{x:0>16}, compiled 0x{x:0>16}\n",
                    .{ index, want_bits, got_bits },
                );
                mismatch = true;
            }
        }
        if (self.interpreted.cr != self.compiled.cr) {
            std.debug.print(
                "\ncr: interpreter 0x{x:0>8}, compiled 0x{x:0>8}\n",
                .{ self.interpreted.cr, self.compiled.cr },
            );
            mismatch = true;
        }
        if (self.interpreted.fpscr != self.compiled.fpscr) {
            std.debug.print(
                "\nfpscr: interpreter 0x{x:0>8}, compiled 0x{x:0>8}\n",
                .{ self.interpreted.fpscr, self.compiled.fpscr },
            );
            mismatch = true;
        }
        if (self.interpreted.lr != self.compiled.lr) {
            std.debug.print(
                "\nlr: interpreter 0x{x:0>16}, compiled 0x{x:0>16}\n",
                .{ self.interpreted.lr, self.compiled.lr },
            );
            mismatch = true;
        }
        if (self.interpreted.ctr != self.compiled.ctr) {
            std.debug.print(
                "\nctr: interpreter 0x{x:0>16}, compiled 0x{x:0>16}\n",
                .{ self.interpreted.ctr, self.compiled.ctr },
            );
            mismatch = true;
        }
        if (self.interpreted.xer.ca != self.compiled.xer.ca) {
            std.debug.print("\nxer.ca differs\n", .{});
            mismatch = true;
        }
        if (self.interpreted.xer.ov != self.compiled.xer.ov or
            self.interpreted.xer.so != self.compiled.xer.so)
        {
            std.debug.print("\nxer.ov/so differs\n", .{});
            mismatch = true;
        }
        if (self.interpreted.instructions_retired != self.compiled.instructions_retired) {
            std.debug.print(
                "\nretired: interpreter {}, compiled {}\n",
                .{ self.interpreted.instructions_retired, self.compiled.instructions_retired },
            );
            mismatch = true;
        }
        if (self.interpreted.pc != self.compiled.pc) {
            std.debug.print(
                "\npc: interpreter 0x{x:0>8}, compiled 0x{x:0>8}\n",
                .{ self.interpreted.pc, self.compiled.pc },
            );
            mismatch = true;
        }
        if (self.interpreted.reservation.valid != self.compiled.reservation.valid) {
            std.debug.print("\nreservation validity differs\n", .{});
            mismatch = true;
        }
        if (!std.mem.eql(u8, &self.interpreted_memory, &self.compiled_memory)) {
            for (self.interpreted_memory, self.compiled_memory, 0..) |want, got, index| {
                if (want != got) {
                    std.debug.print(
                        "\nmemory[{d}]: interpreter 0x{x:0>2}, compiled 0x{x:0>2}\n",
                        .{ index, want, got },
                    );
                    break;
                }
            }
            mismatch = true;
        }
        if (mismatch) {
            std.debug.print("program:", .{});
            for (program) |word| std.debug.print(" 0x{x:0>8}", .{word});
            std.debug.print("\n", .{});
            return error.StateDiverged;
        }
    }
};

fn runProgram(program: []const u32, seed: u64) !void {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();
    h.load(program, seed);
    try h.compareBlock(program);
}

// ---------------------------------------------------------------------------
// Encoding helpers, so the programs below read as assembly.
// ---------------------------------------------------------------------------

fn dForm(primary: u32, rt: u32, ra: u32, imm: u16) u32 {
    return (primary << 26) | (rt << 21) | (ra << 16) | imm;
}

fn xForm(rs: u32, ra: u32, rb: u32, xo: u32, rc: u32) u32 {
    return (31 << 26) | (rs << 21) | (ra << 16) | (rb << 11) | (xo << 1) | rc;
}

fn xoForm(rd: u32, ra: u32, rb: u32, xo: u32, rc: u32) u32 {
    return (31 << 26) | (rd << 21) | (ra << 16) | (rb << 11) | (xo << 1) | rc;
}

fn aForm(fd: u32, fa: u32, fb: u32, fc: u32, xo: u32, rc: u32) u32 {
    return (63 << 26) | (fd << 21) | (fa << 16) | (fb << 11) | (fc << 6) | (xo << 1) | rc;
}

fn mForm(primary: u32, rs: u32, ra: u32, sh: u32, mb: u32, me: u32, rc: u32) u32 {
    return (primary << 26) | (rs << 21) | (ra << 16) | (sh << 11) |
        (mb << 6) | (me << 1) | rc;
}

fn bcForm(bo: u32, bi: u32, displacement: i32) u32 {
    return (16 << 26) | (bo << 21) | (bi << 16) |
        (@as(u32, @bitCast(displacement)) & 0xFFFC);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "arithmetic through the compiler matches the interpreter" {
    try runProgram(&.{
        dForm(14, 3, 0, 0x1234), // li    r3, 0x1234
        dForm(15, 4, 0, 0x8000), // lis   r4, 0x8000
        dForm(14, 5, 4, 0xFFFF), // addi  r5, r4, -1
        xoForm(6, 3, 5, 266, 0), // add   r6, r3, r5
        xoForm(7, 3, 5, 40, 0), // subf  r7, r3, r5
        xoForm(8, 6, 0, 104, 0), // neg   r8, r6
    }, 0x1111);
}

test "scalar floating point arithmetic and FPRF match the interpreter" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();
    const program = [_]u32{
        aForm(3, 1, 2, 0, 21, 0), // fadd  f3, f1, f2
        aForm(4, 3, 5, 6, 25, 0), // fmul  f4, f3, f6 (FC is the source)
        aForm(5, 4, 7, 0, 18, 0), // fdiv  f5, f4, f7
        aForm(8, 0, 5, 0, 22, 0), // fsqrt f8, f5
        aForm(9, 8, 10, 11, 29, 0), // fmadd f9, f8, f10, f11
        aForm(12, 9, 0, 0, 12, 0), // frsp  f12, f9
    };
    h.load(&program, 0x5151);
    h.interpreted.fpr[1] = 1.25;
    h.interpreted.fpr[2] = 2.5;
    h.interpreted.fpr[5] = 1.0;
    h.interpreted.fpr[6] = 3.0;
    h.interpreted.fpr[7] = 2.0;
    h.interpreted.fpr[10] = 0.5;
    h.interpreted.fpr[11] = 4.0;
    h.compiled = h.interpreted;
    try h.compareBlock(&program);

    var zero = try Harness.init(testing.allocator);
    defer zero.deinit();
    const divide_by_zero = [_]u32{
        aForm(3, 1, 2, 0, 18, 0), // fdiv f3, f1, f2
    };
    zero.load(&divide_by_zero, 0x5252);
    zero.interpreted.fpr[1] = 1.0;
    zero.interpreted.fpr[2] = 0.0;
    zero.compiled = zero.interpreted;
    try zero.compareBlock(&divide_by_zero);
}

test "scalar floating point memory forms preserve PPC big-endian bytes" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();
    const program = [_]u32{
        dForm(48, 1, 3, 0), // lfs  f1, 0(r3)
        dForm(52, 1, 3, 4), // stfs f1, 4(r3)
        dForm(50, 2, 3, 8), // lfd  f2, 8(r3)
        dForm(54, 2, 3, 16), // stfd f2, 16(r3)
    };
    h.load(&program, 0x6161);
    h.interpreted.gpr[3] = data_offset;
    h.compiled = h.interpreted;
    const single_bits: u32 = @bitCast(@as(f32, 1.5));
    const double_bits: u64 = @bitCast(@as(f64, -7.25));
    std.mem.writeInt(u32, h.interpreted_memory[data_offset..][0..4], single_bits, .big);
    std.mem.writeInt(u64, h.interpreted_memory[data_offset + 8 ..][0..8], double_bits, .big);
    h.compiled_memory = h.interpreted_memory;
    try h.compareBlock(&program);
}

test "compiled direct and indirect branches preserve PPC control state" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;

    {
        var h = try Harness.init(testing.allocator);
        defer h.deinit();
        h.load(&.{0x48000009}, 0x1010); // bl +8
        try h.compareBlock(&.{0x48000009});
        try testing.expectEqual(@as(u32, 8), h.compiled.pc);
        try testing.expectEqual(@as(u64, 4), h.compiled.lr);
    }
    {
        var h = try Harness.init(testing.allocator);
        defer h.deinit();
        const program = [_]u32{
            dForm(11, 0, 3, 5), // cmpwi cr0, r3, 5
            bcForm(0b01100, 2, 8), // beq +8
        };
        h.load(&program, 0x1011);
        h.interpreted.gpr[3] = 5;
        h.compiled = h.interpreted;
        try h.compareBlock(&program);
        try testing.expectEqual(@as(u32, 12), h.compiled.pc);
    }
    {
        var h = try Harness.init(testing.allocator);
        defer h.deinit();
        h.load(&.{0x4E800020}, 0x1012); // blr
        h.interpreted.lr = 0x180;
        h.compiled = h.interpreted;
        try h.compareBlock(&.{0x4E800020});
        try testing.expectEqual(@as(u32, 0x180), h.compiled.pc);
    }
    {
        var h = try Harness.init(testing.allocator);
        defer h.deinit();
        h.load(&.{0x4E800420}, 0x1013); // bctr
        h.interpreted.ctr = 0x1C0;
        h.compiled = h.interpreted;
        try h.compareBlock(&.{0x4E800420});
        try testing.expectEqual(@as(u32, 0x1C0), h.compiled.pc);
        try testing.expectEqual(@as(u64, 0x1C0), h.compiled.ctr);
    }
}

test "the record bit produces the same CR0 on both paths" {
    try runProgram(&.{
        dForm(14, 3, 0, 0), // li   r3, 0
        xoForm(4, 3, 3, 266, 1), // add. r4, r3, r3   -> EQ
        dForm(14, 5, 0, 0xFFFF), // li   r5, -1
        xoForm(6, 5, 5, 266, 1), // add. r6, r5, r5   -> LT
        dForm(14, 7, 0, 5), // li   r7, 5
        xoForm(8, 7, 7, 266, 1), // add. r8, r7, r7   -> GT
    }, 0x2222);
}

test "logical operations and their immediate forms match" {
    try runProgram(&.{
        xForm(3, 4, 5, 28, 0), // and   r4, r3, r5
        xForm(3, 6, 5, 60, 0), // andc  r6, r3, r5
        xForm(3, 7, 5, 444, 0), // or    r7, r3, r5
        xForm(3, 8, 5, 412, 0), // orc   r8, r3, r5
        xForm(3, 9, 5, 316, 0), // xor   r9, r3, r5
        xForm(3, 10, 5, 476, 0), // nand  r10, r3, r5
        xForm(3, 11, 5, 124, 0), // nor   r11, r3, r5
        xForm(3, 12, 5, 284, 0), // eqv   r12, r3, r5
        dForm(28, 3, 13, 0x00FF), // andi. r13, r3, 0xFF
        dForm(29, 3, 14, 0xFF00), // andis. r14, r3, 0xFF00
        dForm(24, 3, 15, 0x1234), // ori   r15, r3, 0x1234
        dForm(26, 3, 16, 0x5678), // xori  r16, r3, 0x5678
    }, 0x3333);
}

test "a zero immediate on the logical forms is handled, not skipped" {
    try runProgram(&.{
        dForm(24, 0, 0, 0), // ori r0, r0, 0 -- the canonical nop
        dForm(28, 3, 4, 0), // andi. r4, r3, 0 -- clears and writes CR0
    }, 0x4444);
}

test "extension and bit counting match" {
    try runProgram(&.{
        xForm(3, 4, 0, 954, 0), // extsb r4, r3
        xForm(3, 5, 0, 922, 0), // extsh r5, r3
        xForm(3, 6, 0, 986, 0), // extsw r6, r3
        xForm(3, 7, 0, 26, 0), // cntlzw r7, r3
        xForm(3, 8, 0, 58, 0), // cntlzd r8, r3
    }, 0x5555);
}

test "a shift count at or past the width clears on both paths" {
    try runProgram(&.{
        dForm(14, 20, 0, 32), // li  r20, 32
        dForm(14, 21, 0, 64), // li  r21, 64
        dForm(14, 22, 0, 4), // li  r22, 4
        xForm(3, 4, 20, 24, 0), // slw r4, r3, r20   -- count 32, clears
        xForm(3, 5, 20, 536, 0), // srw r5, r3, r20   -- count 32, clears
        xForm(3, 6, 21, 27, 0), // sld r6, r3, r21   -- count 64, clears
        xForm(3, 7, 21, 539, 0), // srd r7, r3, r21   -- count 64, clears
        xForm(3, 8, 22, 24, 0), // slw r8, r3, r22   -- ordinary count
        xForm(3, 9, 22, 539, 0), // srd r9, r3, r22
    }, 0x6666);
}

test "srawi produces the same result and the same carry" {
    try runProgram(&.{
        dForm(14, 3, 0, 0xFFF9), // li    r3, -7
        xForm(3, 4, 2, 824, 0), // srawi r4, r3, 2   -- a one bit falls off
        dForm(14, 5, 0, 0xFFF8), // li    r5, -8
        xForm(5, 6, 2, 824, 0), // srawi r6, r5, 2   -- nothing falls off
        dForm(14, 7, 0, 7), // li    r7, 7
        xForm(7, 8, 2, 824, 1), // srawi. r8, r7, 2  -- positive, with CR0
    }, 0x7777);
}

test "rlwinm rotates and masks identically" {
    try runProgram(&.{
        mForm(21, 3, 4, 0, 0, 31, 0), // rlwinm r4, r3, 0, 0, 31  -- zero-extend
        mForm(21, 3, 5, 1, 0, 31, 0), // rlwinm r5, r3, 1, 0, 31
        mForm(21, 3, 6, 8, 24, 31, 0), // rlwinm r6, r3, 8, 24, 31 -- byte extract
        mForm(21, 3, 7, 16, 16, 31, 1), // rlwinm. r7, r3, 16, 16, 31
        mForm(21, 3, 8, 4, 28, 3, 0), // rlwinm r8, r3, 4, 28, 3   -- wrapped mask
    }, 0x8888);
}

test "rlwimi merges into the destination identically" {
    try runProgram(&.{
        mForm(20, 3, 4, 8, 16, 23, 0), // rlwimi r4, r3, 8, 16, 23
        mForm(20, 3, 5, 0, 0, 31, 1), // rlwimi. r5, r3, 0, 0, 31
    }, 0x9999);
}

test "the doubleword rotate-and-clear forms match" {
    // rldicl r4, r3, 0, 32 keeps the low word; rldicr r5, r3, 0, 31 the high.
    const rldicl = (30 << 26) | (3 << 21) | (4 << 16) | (0 << 11) |
        (0 << 6) | (1 << 5) | (0 << 2);
    const rldicr = (30 << 26) | (3 << 21) | (5 << 16) | (0 << 11) |
        (31 << 6) | (0 << 5) | (1 << 2);
    // With a rotate as well.
    const rotated = (30 << 26) | (3 << 21) | (6 << 16) | (8 << 11) |
        (0 << 6) | (1 << 5) | (0 << 2);
    try runProgram(&.{ rldicl, rldicr, rotated }, 0xAAAA);
}

test "compares write the same condition register field" {
    try runProgram(&.{
        dForm(11, 0, 3, 5), // cmpwi cr0, r3, 5
        dForm(11, (1 << 2) | 1, 3, 5), // cmpdi cr1, r3, 5
        dForm(10, (2 << 2), 3, 5), // cmplwi cr2, r3, 5
        dForm(10, (3 << 2) | 1, 3, 5), // cmpldi cr3, r3, 5
        xForm((4 << 2), 3, 5, 0, 0), // cmpw cr4, r3, r5
        xForm((5 << 2) | 1, 3, 5, 0, 0), // cmpd cr5, r3, r5
        xForm((6 << 2), 3, 5, 32, 0), // cmplw cr6, r3, r5
        xForm((7 << 2) | 1, 3, 5, 32, 0), // cmpld cr7, r3, r5
    }, 0xBBBB);
}

test "a 32-bit compare of two 64-bit registers narrows on both paths" {
    try runProgram(&.{
        (15 << 26) | (3 << 21) | (0 << 16) | 0x0001, // lis r3, 1
        dForm(14, 3, 3, 5), // addi r3, r3, 5
        dForm(14, 4, 0, 5), // li   r4, 5
        xForm(0, 3, 4, 0, 0), // cmpw cr0, r3, r4  -- equal at 32 bits
        xForm(1 << 2 | 1, 3, 4, 0, 0), // cmpd cr1, r3, r4  -- not at 64
    }, 0xCCCC);
}

test "every load width converts from guest byte order identically" {
    try runProgram(&.{
        dForm(34, 3, 24, 0), // lbz r3, 0(r24)
        dForm(40, 4, 24, 2), // lhz r4, 2(r24)
        dForm(42, 5, 24, 4), // lha r5, 4(r24)
        dForm(32, 6, 24, 8), // lwz r6, 8(r24)
        xForm(7, 24, 25, 87, 0), // lbzx r7, r24, r25
        xForm(8, 24, 25, 279, 0), // lhzx r8, r24, r25
        xForm(9, 24, 25, 343, 0), // lhax r9, r24, r25
        xForm(10, 24, 25, 23, 0), // lwzx r10, r24, r25
    }, 0xDDDD);
}

test "the doubleword load forms match" {
    // ld r3, 0(r24) is DS-form: the low two displacement bits carry the opcode.
    const ld = (58 << 26) | (3 << 21) | (24 << 16) | 0;
    const lwa = (58 << 26) | (4 << 21) | (24 << 16) | 2;
    const ldx = xForm(5, 24, 25, 21, 0);
    const lwax = xForm(6, 24, 25, 341, 0);
    try runProgram(&.{ ld, lwa, ldx, lwax }, 0xEEEE);
}

test "every store width writes the same bytes" {
    try runProgram(&.{
        dForm(38, 3, 24, 0), // stb r3, 0(r24)
        dForm(44, 4, 24, 2), // sth r4, 2(r24)
        dForm(36, 5, 24, 8), // stw r5, 8(r24)
        xForm(6, 24, 25, 215, 0), // stbx r6, r24, r25
        xForm(7, 24, 25, 407, 0), // sthx r7, r24, r25
        xForm(8, 24, 25, 151, 0), // stwx r8, r24, r25
    }, 0xF0F0);
}

test "the doubleword store forms match" {
    const std_form = (62 << 26) | (3 << 21) | (24 << 16) | 0;
    const stdx = xForm(4, 24, 25, 149, 0);
    try runProgram(&.{ std_form, stdx }, 0xF1F1);
}

test "a load and store round-trip through memory identically" {
    try runProgram(&.{
        dForm(32, 3, 24, 0), // lwz r3, 0(r24)
        dForm(14, 3, 3, 1), // addi r3, r3, 1
        dForm(36, 3, 24, 64), // stw r3, 64(r24)
        dForm(32, 4, 24, 64), // lwz r4, 64(r24)
    }, 0xF2F2);
}

test "an out-of-range access faults at the same instruction on both paths" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();

    const program = [_]u32{
        dForm(14, 3, 0, 1), // li  r3, 1        -- retires
        (15 << 26) | (4 << 21) | 0x0100, // lis r4, 0x0100   -- far outside the map
        dForm(32, 5, 4, 0), // lwz r5, 0(r4)    -- faults
        dForm(14, 6, 0, 2), // li  r6, 2        -- must not run
    };
    h.load(&program, 0xF3F3);
    const r6_before = h.compiled.gpr[6];
    try h.compareBlock(&program);

    // The fault stopped both paths at the same instruction: the two preceding
    // it retired, and the one after it did not run at all.
    try testing.expectEqual(@as(u64, 1), h.compiled.gpr[3]);
    try testing.expectEqual(r6_before, h.compiled.gpr[6]);
}

test "a store inside a block breaks a reservation covering its address" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();

    const program = [_]u32{
        dForm(36, 3, 24, 0), // stw r3, 0(r24)
    };
    h.load(&program, 0xF4F4);
    // Reserve the block the store lands in.
    const target: u32 = @truncate(h.interpreted.gpr[24]);
    h.interpreted.reservation.set(target);
    h.compiled.reservation.set(target);
    try h.compareBlock(&program);
    try testing.expect(!h.compiled.reservation.valid);
}

test "a store outside the reserved block leaves the reservation standing" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();

    const program = [_]u32{
        dForm(36, 3, 24, 0), // stw r3, 0(r24)
    };
    h.load(&program, 0xF5F5);
    const target: u32 = @truncate(h.interpreted.gpr[24]);
    // Reserve a block well away from the store's address.
    const elsewhere = (target +% 512) & ~@as(u32, 127);
    h.interpreted.reservation.set(elsewhere);
    h.compiled.reservation.set(elsewhere);
    try h.compareBlock(&program);
    try testing.expect(h.compiled.reservation.valid);
}

test "a block stops at the first instruction outside the compiled subset" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();

    const program = [_]u32{
        dForm(14, 3, 0, 1), // li  r3, 1
        dForm(14, 4, 0, 2), // li  r4, 2
        0x4E800020, // blr -- compiled as a dispatcher exit
        dForm(14, 5, 0, 3), // li  r5, 3
    };
    h.load(&program, 0xF6F6);
    const block = (try h.jit.compileAt(h.compiledMemory(), base_address)).?;
    try testing.expectEqual(@as(u32, 3), block.instruction_count);
    try testing.expectEqual(base_address + 12, block.guest_end);
}

test "a branch-only address compiles as a dispatcher exit" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();
    const program = [_]u32{0x4E800020}; // blr
    h.load(&program, 0xF7F7);
    const block = (try h.jit.compileAt(h.compiledMemory(), base_address)).?;
    try testing.expectEqual(@as(u32, 1), block.instruction_count);
}

test "hotness gates compilation to code that runs repeatedly" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var jit = try jit_mod.Jit.init(testing.allocator, 64 * 1024);
    defer jit.deinit();

    var crossed: u32 = 0;
    var i: u32 = 0;
    while (i < jit_mod.default_hot_threshold * 3) : (i += 1) {
        if (jit.noteExecution(0x8200_0000)) crossed += 1;
    }
    // The threshold is crossed exactly once, however many times the address is
    // seen afterwards: a counter that kept climbing would retry a failed
    // compile on every pass.
    try testing.expectEqual(@as(u32, 1), crossed);
    // A different address has its own count.
    try testing.expect(!jit.noteExecution(0x8200_1000));
}

test "invalidating a range drops the blocks that overlap it" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();

    const program = [_]u32{
        dForm(14, 3, 0, 1),
        dForm(14, 4, 0, 2),
        dForm(14, 5, 0, 3),
        dForm(14, 6, 0, 4),
    };
    h.load(&program, 0xF8F8);
    _ = try h.jit.compileAt(h.compiledMemory(), base_address);
    try testing.expect(h.jit.lookup(base_address) != null);

    // A range past the block leaves it alone.
    h.jit.invalidate(base_address + 64, base_address + 128);
    try testing.expect(h.jit.lookup(base_address) != null);

    // A range that overlaps it does not.
    h.jit.invalidate(base_address + 4, base_address + 8);
    try testing.expect(h.jit.lookup(base_address) == null);
}

// ---------------------------------------------------------------------------
// Randomised differential testing
// ---------------------------------------------------------------------------

/// Build one random well-formed instruction from the compiled subset.
///
/// Registers 24-31 are the ones the harness points into the data region, so the
/// memory forms draw their base from that range and everything else draws from
/// the whole file. Displacements stay small and aligned so an access lands
/// inside the mapping most of the time - but not always, because the fault path
/// needs exercising too.
fn randomInstruction(random: std.Random) u32 {
    const kind = random.uintLessThan(u32, 12);
    const rt = random.uintLessThan(u32, 32);
    const ra = random.uintLessThan(u32, 32);
    const rb = random.uintLessThan(u32, 32);
    const base = 24 + random.uintLessThan(u32, 8);
    const index = 24 + random.uintLessThan(u32, 8);
    const rc = random.uintLessThan(u32, 2);

    return switch (kind) {
        0 => dForm(14, rt, ra, random.int(u16)), // addi
        1 => dForm(15, rt, ra, random.int(u16)), // addis
        2 => switch (random.uintLessThan(u32, 3)) {
            0 => xoForm(rt, ra, rb, 266, rc), // add
            1 => xoForm(rt, ra, rb, 40, rc), // subf
            else => xoForm(rt, ra, 0, 104, rc), // neg
        },
        3 => switch (random.uintLessThan(u32, 8)) {
            0 => xForm(rt, ra, rb, 28, rc), // and
            1 => xForm(rt, ra, rb, 60, rc), // andc
            2 => xForm(rt, ra, rb, 444, rc), // or
            3 => xForm(rt, ra, rb, 412, rc), // orc
            4 => xForm(rt, ra, rb, 316, rc), // xor
            5 => xForm(rt, ra, rb, 476, rc), // nand
            6 => xForm(rt, ra, rb, 124, rc), // nor
            else => xForm(rt, ra, rb, 284, rc), // eqv
        },
        4 => switch (random.uintLessThan(u32, 6)) {
            0 => dForm(28, rt, ra, random.int(u16)), // andi.
            1 => dForm(29, rt, ra, random.int(u16)), // andis.
            2 => dForm(24, rt, ra, random.int(u16)), // ori
            3 => dForm(25, rt, ra, random.int(u16)), // oris
            4 => dForm(26, rt, ra, random.int(u16)), // xori
            else => dForm(27, rt, ra, random.int(u16)), // xoris
        },
        5 => switch (random.uintLessThan(u32, 5)) {
            0 => xForm(rt, ra, 0, 954, rc), // extsb
            1 => xForm(rt, ra, 0, 922, rc), // extsh
            2 => xForm(rt, ra, 0, 986, rc), // extsw
            3 => xForm(rt, ra, 0, 26, rc), // cntlzw
            else => xForm(rt, ra, 0, 58, rc), // cntlzd
        },
        6 => switch (random.uintLessThan(u32, 5)) {
            0 => xForm(rt, ra, rb, 24, rc), // slw
            1 => xForm(rt, ra, rb, 536, rc), // srw
            2 => xForm(rt, ra, rb, 27, rc), // sld
            3 => xForm(rt, ra, rb, 539, rc), // srd
            else => xForm(rt, ra, random.uintLessThan(u32, 32), 824, rc), // srawi
        },
        7 => mForm(
            21,
            rt,
            ra,
            random.uintLessThan(u32, 32),
            random.uintLessThan(u32, 32),
            random.uintLessThan(u32, 32),
            rc,
        ), // rlwinm
        8 => mForm(
            20,
            rt,
            ra,
            random.uintLessThan(u32, 32),
            random.uintLessThan(u32, 32),
            random.uintLessThan(u32, 32),
            rc,
        ), // rlwimi
        9 => switch (random.uintLessThan(u32, 4)) {
            0 => dForm(11, random.uintLessThan(u32, 32), ra, random.int(u16)), // cmpi
            1 => dForm(10, random.uintLessThan(u32, 32), ra, random.int(u16)), // cmpli
            2 => xForm(random.uintLessThan(u32, 32), ra, rb, 0, 0), // cmp
            else => xForm(random.uintLessThan(u32, 32), ra, rb, 32, 0), // cmpl
        },
        10 => switch (random.uintLessThan(u32, 8)) {
            0 => dForm(34, rt, base, random.uintLessThan(u16, 256)), // lbz
            1 => dForm(40, rt, base, random.uintLessThan(u16, 128) * 2), // lhz
            2 => dForm(42, rt, base, random.uintLessThan(u16, 128) * 2), // lha
            3 => dForm(32, rt, base, random.uintLessThan(u16, 64) * 4), // lwz
            4 => xForm(rt, base, index, 87, 0), // lbzx
            5 => xForm(rt, base, index, 279, 0), // lhzx
            6 => xForm(rt, base, index, 23, 0), // lwzx
            else => xForm(rt, base, index, 21, 0), // ldx
        },
        else => switch (random.uintLessThan(u32, 6)) {
            0 => dForm(38, rt, base, random.uintLessThan(u16, 256)), // stb
            1 => dForm(44, rt, base, random.uintLessThan(u16, 128) * 2), // sth
            2 => dForm(36, rt, base, random.uintLessThan(u16, 64) * 4), // stw
            3 => xForm(rt, base, index, 215, 0), // stbx
            4 => xForm(rt, base, index, 407, 0), // sthx
            else => xForm(rt, base, index, 151, 0), // stwx
        },
    };
}

test "randomly generated blocks agree with the interpreter" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;

    var prng = std.Random.DefaultPrng.init(0x5EED_1234);
    const random = prng.random();

    var round: u32 = 0;
    var compared: u32 = 0;
    var skipped: u32 = 0;
    while (round < 400) : (round += 1) {
        var program: [16]u32 = undefined;
        const length = 1 + random.uintLessThan(usize, program.len);
        for (program[0..length]) |*word| {
            word.* = randomInstruction(random);
        }

        var h = try Harness.init(testing.allocator);
        defer h.deinit();
        h.load(program[0..length], round);
        h.compareBlock(program[0..length]) catch |err| switch (err) {
            // A generated program whose first instruction is not compilable is
            // not a failure; the generator does not promise one.
            error.NothingCompiled => continue,
            else => {
                // A store that landed in the instruction stream makes the two
                // paths incomparable rather than one of them wrong. Skipping it
                // is not sweeping it under the rug: the property is asserted
                // directly by "self-modifying code is where the two paths
                // legitimately diverge" below.
                if (h.codeWasModified(program[0..length])) {
                    skipped += 1;
                    continue;
                }
                return err;
            },
        };
        compared += 1;
    }
    // The skip path must not be swallowing most of the corpus.
    try testing.expect(compared > 200);
    try testing.expect(skipped < compared);
}

test "a long block of every compilable shape agrees with the interpreter" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;

    var prng = std.Random.DefaultPrng.init(0xA11CE);
    const random = prng.random();

    // A block at the compiler's length limit, so the block-boundary bookkeeping
    // is exercised at its edge rather than only in the middle.
    var program: [jit_mod.default_max_block]u32 = undefined;
    for (&program) |*word| word.* = randomInstruction(random);

    var h = try Harness.init(testing.allocator);
    defer h.deinit();
    h.load(&program, 0xB0B0);
    h.compareBlock(&program) catch |err| switch (err) {
        error.NothingCompiled => return,
        else => {
            if (h.codeWasModified(&program)) return;
            return err;
        },
    };
}

test "self-modifying code is where the two paths legitimately diverge" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    var h = try Harness.init(testing.allocator);
    defer h.deinit();

    // Overwrite the instruction after the store with a different one. The
    // compiled block was built before the store ran, so it executes what it
    // compiled; the interpreter fetches the replacement.
    const program = [_]u32{
        dForm(14, 20, 0, 8), // li  r20, 8       -- address of the third word
        dForm(36, 21, 20, 0), // stw r21, 0(r20)  -- overwrite it
        dForm(14, 22, 0, 1), // li  r22, 1       -- the instruction overwritten
    };
    h.load(&program, 0xC0C0);
    // Make the store write a recognisably different instruction.
    h.interpreted.gpr[21] = dForm(14, 22, 0, 99); // li r22, 99
    h.compiled.gpr[21] = h.interpreted.gpr[21];

    const block = (try h.jit.compileAt(h.compiledMemory(), base_address)).?;
    try testing.expectEqual(@as(u32, 3), block.instruction_count);
    _ = h.jit.run(block, &h.compiled, h.compiledMemory());

    var ctx = Context.init(&h.interpreted, h.interpreterMemory());
    var n: u32 = 0;
    while (n < block.instruction_count) : (n += 1) _ = try execute_mod.step(&ctx);

    // Both wrote the same bytes into the instruction stream...
    try testing.expect(std.mem.eql(u8, &h.interpreted_memory, &h.compiled_memory));
    // ...and then disagreed about what the third instruction is. PowerPC calls
    // this undefined without an intervening icbi/isync, which is exactly why a
    // recompiler has to be told when guest code changes.
    try testing.expectEqual(@as(u64, 1), h.compiled.gpr[22]);
    try testing.expectEqual(@as(u64, 99), h.interpreted.gpr[22]);
    try testing.expect(h.codeWasModified(&program));

    // Invalidating the range is the fix, and it is what `icbi` and a module
    // load are wired to.
    h.jit.invalidate(base_address, base_address + 16);
    try testing.expect(h.jit.lookup(base_address) == null);
}
