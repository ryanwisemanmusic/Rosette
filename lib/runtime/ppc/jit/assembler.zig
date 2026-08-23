//! A small ARM64 assembler with labels, for the PowerPC block compiler.
//!
//! The encoders in lib/compiler/arm64 produce one instruction word from
//! register numbers and immediates; they deliberately know nothing about where
//! an instruction will land. This adds the one thing a code generator needs on
//! top of that: a branch whose target is not known yet.
//!
//! Labels are resolved in a patch pass at the end rather than by emitting a
//! placeholder and rewriting in place, because a branch displacement that does
//! not fit is a *compile* failure the caller must handle by not compiling the
//! block - not a truncation that produces a branch to the wrong address.

const std = @import("std");
const a64 = @import("arm64_encode");

pub const Reg = a64.Reg;
pub const Cond = a64.Cond;

pub const Error = error{
    OutOfMemory,
    /// A branch target is too far away for the instruction that reaches it.
    DisplacementTooFar,
    /// A label was referenced but never placed.
    UnboundLabel,
};

pub const Label = struct { id: usize };

const FixupKind = enum {
    /// b / bl: 26-bit signed displacement in instructions.
    branch26,
    /// b.cond / cbz / cbnz: 19-bit signed displacement in instructions.
    branch19,
};

const Fixup = struct {
    at: usize,
    label: usize,
    kind: FixupKind,
};

pub const Assembler = struct {
    words: std.ArrayList(u32),
    labels: std.ArrayList(?usize),
    fixups: std.ArrayList(Fixup),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Assembler {
        return .{
            .words = .empty,
            .labels = .empty,
            .fixups = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Assembler) void {
        self.words.deinit(self.allocator);
        self.labels.deinit(self.allocator);
        self.fixups.deinit(self.allocator);
    }

    pub fn len(self: *const Assembler) usize {
        return self.words.items.len;
    }

    pub fn emit(self: *Assembler, word: u32) Error!void {
        try self.words.append(self.allocator, word);
    }

    /// Emit an instruction the encoder may refuse. A null means the operands
    /// have no encoding, which the caller has to handle by choosing a different
    /// sequence rather than by emitting something close.
    pub fn emitOptional(self: *Assembler, word: ?u32) Error!bool {
        if (word) |value| {
            try self.emit(value);
            return true;
        }
        return false;
    }

    pub fn createLabel(self: *Assembler) Error!Label {
        try self.labels.append(self.allocator, null);
        return .{ .id = self.labels.items.len - 1 };
    }

    pub fn placeLabel(self: *Assembler, label: Label) void {
        self.labels.items[label.id] = self.words.items.len;
    }

    pub fn branch(self: *Assembler, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.words.items.len,
            .label = label.id,
            .kind = .branch26,
        });
        try self.emit(a64.b(0));
    }

    pub fn branchCond(self: *Assembler, cond: Cond, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.words.items.len,
            .label = label.id,
            .kind = .branch19,
        });
        try self.emit(a64.bcond(cond, 0));
    }

    pub fn branchIfZero(self: *Assembler, width: a64.Width, rt: Reg, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.words.items.len,
            .label = label.id,
            .kind = .branch19,
        });
        try self.emit(a64.cbz(width, rt, 0));
    }

    pub fn branchIfNonZero(self: *Assembler, width: a64.Width, rt: Reg, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.words.items.len,
            .label = label.id,
            .kind = .branch19,
        });
        try self.emit(a64.cbnz(width, rt, 0));
    }

    /// Materialise a 64-bit constant into `rd`, using the shortest sequence.
    pub fn loadConstant(self: *Assembler, rd: Reg, value: u64) Error!void {
        var buffer: [4]u32 = undefined;
        const count = a64.materialize(rd, value, &buffer);
        for (buffer[0..count]) |word| try self.emit(word);
    }

    /// Resolve every branch and return the finished instruction stream.
    pub fn finish(self: *Assembler) Error![]const u32 {
        for (self.fixups.items) |fixup| {
            const target = self.labels.items[fixup.label] orelse return Error.UnboundLabel;
            const delta = @as(i64, @intCast(target)) - @as(i64, @intCast(fixup.at));
            switch (fixup.kind) {
                .branch26 => {
                    if (delta < -(1 << 25) or delta >= (1 << 25)) {
                        return Error.DisplacementTooFar;
                    }
                    self.words.items[fixup.at] = a64.b(@intCast(delta));
                },
                .branch19 => {
                    if (delta < -(1 << 18) or delta >= (1 << 18)) {
                        return Error.DisplacementTooFar;
                    }
                    // Keep the opcode and condition, replace the displacement.
                    const original = self.words.items[fixup.at];
                    const cleared = original & ~@as(u32, 0x00FF_FFE0);
                    const imm19: u32 = @as(u32, @bitCast(@as(i32, @intCast(delta)))) & 0x7FFFF;
                    self.words.items[fixup.at] = cleared | (imm19 << 5);
                },
            }
        }
        return self.words.items;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "a forward branch is patched to the label's final position" {
    var asm_ = Assembler.init(testing.allocator);
    defer asm_.deinit();

    const target = try asm_.createLabel();
    try asm_.branch(target);
    try asm_.emit(a64.nop());
    try asm_.emit(a64.nop());
    asm_.placeLabel(target);
    try asm_.emit(a64.ret());

    const code = try asm_.finish();
    // Three instructions forward from the branch itself.
    try testing.expectEqual(a64.b(3), code[0]);
}

test "a backward branch gets a negative displacement" {
    var asm_ = Assembler.init(testing.allocator);
    defer asm_.deinit();

    const top = try asm_.createLabel();
    asm_.placeLabel(top);
    try asm_.emit(a64.nop());
    try asm_.emit(a64.nop());
    try asm_.branch(top);

    const code = try asm_.finish();
    try testing.expectEqual(a64.b(-2), code[2]);
}

test "a conditional branch keeps its condition through the patch" {
    var asm_ = Assembler.init(testing.allocator);
    defer asm_.deinit();

    const target = try asm_.createLabel();
    try asm_.branchCond(.hi, target);
    try asm_.emit(a64.nop());
    asm_.placeLabel(target);
    try asm_.emit(a64.ret());

    const code = try asm_.finish();
    try testing.expectEqual(a64.bcond(.hi, 2), code[0]);
    // The condition survived: a patch that rebuilt the word from scratch would
    // have lost it.
    try testing.expectEqual(@as(u32, @intFromEnum(Cond.hi)), code[0] & 0xF);
}

test "cbz keeps its register through the patch" {
    var asm_ = Assembler.init(testing.allocator);
    defer asm_.deinit();

    const target = try asm_.createLabel();
    try asm_.branchIfZero(.x64, 9, target);
    try asm_.emit(a64.nop());
    asm_.placeLabel(target);
    try asm_.emit(a64.ret());

    const code = try asm_.finish();
    try testing.expectEqual(a64.cbz(.x64, 9, 2), code[0]);
    try testing.expectEqual(@as(u32, 9), code[0] & 0x1F);
}

test "an unbound label is an error, not a branch to zero" {
    var asm_ = Assembler.init(testing.allocator);
    defer asm_.deinit();
    const target = try asm_.createLabel();
    try asm_.branch(target);
    try testing.expectError(Error.UnboundLabel, asm_.finish());
}

test "constant materialisation goes through the shortest sequence" {
    var asm_ = Assembler.init(testing.allocator);
    defer asm_.deinit();
    try asm_.loadConstant(5, 0x1234);
    try testing.expectEqual(@as(usize, 1), asm_.len());
    try asm_.loadConstant(6, 0x1111_2222_3333_4444);
    try testing.expectEqual(@as(usize, 5), asm_.len());
}
