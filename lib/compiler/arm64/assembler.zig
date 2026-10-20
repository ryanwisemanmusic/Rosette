//! A small ARM64 assembler with labels, shared by the block compilers.
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
const a64 = @import("encode.zig");

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

/// Where `emit` appends. A block's out-of-line paths go to `.cold`, so the
/// code a block runs every time it executes stays contiguous with the next
/// block's instead of sitting between kilobytes of paths that almost never
/// run; `finish` lays cold code out after hot code, `finishSplit` places the
/// two apart.
pub const Section = enum { hot, cold };

/// A position in the cold section, tagged so labels and fixups hold either.
const cold_tag: usize = 1 << (@bitSizeOf(usize) - 1);

const FixupKind = enum {
    /// b: 26-bit signed displacement in instructions.
    branch26,
    /// bl: the same displacement, keeping the link.
    call26,
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
    cold_words: std.ArrayList(u32) = .empty,
    section: Section = .hot,
    /// Where the most recent label was placed (tagged): a branch some label
    /// names is a patch site or a jump target and is never dropped.
    last_label_at: usize = std.math.maxInt(usize),

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
        self.cold_words.deinit(self.allocator);
        self.labels.deinit(self.allocator);
        self.fixups.deinit(self.allocator);
    }

    /// Words in the section being emitted into.
    pub fn len(self: *const Assembler) usize {
        return if (self.section == .cold) self.cold_words.items.len else self.words.items.len;
    }

    /// The next word's position, tagged with its section.
    fn here(self: *const Assembler) usize {
        return if (self.section == .cold) cold_tag | self.cold_words.items.len else self.words.items.len;
    }

    pub fn emit(self: *Assembler, word: u32) Error!void {
        if (self.section == .cold) {
            try self.cold_words.append(self.allocator, word);
        } else {
            try self.words.append(self.allocator, word);
        }
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
        // `b label` right before `label`: the branch goes where execution
        // already falls, so it is dropped - unless another label names it.
        if (self.fixups.items.len != 0) {
            const last = self.fixups.items[self.fixups.items.len - 1];
            if (last.kind == .branch26 and last.label == label.id and last.at + 1 == self.here() and self.last_label_at != last.at) {
                _ = self.fixups.pop();
                if (self.section == .cold) self.cold_words.items.len -= 1 else self.words.items.len -= 1;
            }
        }
        self.labels.items[label.id] = self.here();
        self.last_label_at = self.here();
    }

    pub fn branch(self: *Assembler, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.here(),
            .label = label.id,
            .kind = .branch26,
        });
        try self.emit(a64.b(0));
    }

    /// `bl label`.
    pub fn call(self: *Assembler, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.here(),
            .label = label.id,
            .kind = .call26,
        });
        try self.emit(a64.bl(0));
    }

    /// `ldr rt, label` (64-bit literal): the label names the doubleword.
    pub fn loadLiteral(self: *Assembler, rt: Reg, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.here(),
            .label = label.id,
            .kind = .branch19,
        });
        try self.emit(0x5800_0000 | @as(u32, rt));
    }

    /// The word offset of a label placed in the hot section, from the hot
    /// section's start; null for one in the cold section or never placed.
    pub fn hotWord(self: *const Assembler, label: Label) ?usize {
        const position = self.labels.items[label.id] orelse return null;
        return if (position & cold_tag != 0) null else position;
    }

    pub fn branchCond(self: *Assembler, cond: Cond, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.here(),
            .label = label.id,
            .kind = .branch19,
        });
        try self.emit(a64.bcond(cond, 0));
    }

    pub fn branchIfZero(self: *Assembler, width: a64.Width, rt: Reg, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.here(),
            .label = label.id,
            .kind = .branch19,
        });
        try self.emit(a64.cbz(width, rt, 0));
    }

    pub fn branchIfNonZero(self: *Assembler, width: a64.Width, rt: Reg, label: Label) Error!void {
        try self.fixups.append(self.allocator, .{
            .at = self.here(),
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

    /// Resolve every branch and return the finished instruction stream, the
    /// cold section laid out right after the hot one.
    pub fn finish(self: *Assembler) Error![]const u32 {
        const hot_words = self.words.items.len;
        try self.resolve(0, hot_words * @sizeOf(u32));
        try self.words.appendSlice(self.allocator, self.cold_words.items);
        self.cold_words.clearRetainingCapacity();
        return self.words.items;
    }

    pub const Split = struct { hot: []const u32, cold: []const u32 };

    /// Resolve every branch for the hot section placed at `hot_address` and
    /// the cold one at `cold_address`. A branch between them that does not
    /// reach is `DisplacementTooFar`, as within one section.
    pub fn finishSplit(self: *Assembler, hot_address: usize, cold_address: usize) Error!Split {
        try self.resolve(hot_address, cold_address);
        return .{ .hot = self.words.items, .cold = self.cold_words.items };
    }

    fn address(position: usize, hot_address: usize, cold_address: usize) i64 {
        const base = if (position & cold_tag != 0) cold_address else hot_address;
        return @as(i64, @intCast(base)) + @as(i64, @intCast((position & ~cold_tag) * @sizeOf(u32)));
    }

    fn resolve(self: *Assembler, hot_address: usize, cold_address: usize) Error!void {
        for (self.fixups.items) |fixup| {
            const target = self.labels.items[fixup.label] orelse return Error.UnboundLabel;
            const delta = @divExact(address(target, hot_address, cold_address) - address(fixup.at, hot_address, cold_address), @sizeOf(u32));
            const word = if (fixup.at & cold_tag != 0) &self.cold_words.items[fixup.at & ~cold_tag] else &self.words.items[fixup.at];
            switch (fixup.kind) {
                .branch26, .call26 => {
                    if (delta < -(1 << 25) or delta >= (1 << 25)) {
                        return Error.DisplacementTooFar;
                    }
                    word.* = if (fixup.kind == .call26) a64.bl(@intCast(delta)) else a64.b(@intCast(delta));
                },
                .branch19 => {
                    if (delta < -(1 << 18) or delta >= (1 << 18)) {
                        return Error.DisplacementTooFar;
                    }
                    // Keep the opcode and condition, replace the displacement.
                    const original = word.*;
                    const cleared = original & ~@as(u32, 0x00FF_FFE0);
                    const imm19: u32 = @as(u32, @bitCast(@as(i32, @intCast(delta)))) & 0x7FFFF;
                    word.* = cleared | (imm19 << 5);
                },
            }
        }
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

test "a call keeps its link, and a literal load and a hot label resolve to their words" {
    var asm_ = Assembler.init(testing.allocator);
    defer asm_.deinit();
    const target = try asm_.createLabel();
    const literal = try asm_.createLabel();
    try asm_.call(target);
    try asm_.loadLiteral(12, literal);
    asm_.placeLabel(target);
    try asm_.emit(a64.ret());
    asm_.placeLabel(literal);
    try asm_.emit(0x1234_5678);
    try asm_.emit(0);
    asm_.section = .cold;
    const cold = try asm_.createLabel();
    asm_.placeLabel(cold);
    try asm_.emit(a64.nop());
    try testing.expectEqual(@as(?usize, 2), asm_.hotWord(target));
    try testing.expectEqual(@as(?usize, null), asm_.hotWord(cold));
    const code = try asm_.finish();
    try testing.expectEqual(a64.bl(2), code[0]);
    // ldr x12, #+8: imm19 = 2 words.
    try testing.expectEqual(@as(u32, 0x5800_0000 | (2 << 5) | 12), code[1]);
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

test "cold code is laid out after hot code and branches between them resolve" {
    var asm_ = Assembler.init(testing.allocator);
    defer asm_.deinit();
    const slow = try asm_.createLabel();
    const back = try asm_.createLabel();
    try asm_.branchIfNonZero(.x64, 3, slow); // hot 0
    asm_.placeLabel(back);
    try asm_.emit(a64.ret()); // hot 1
    asm_.section = .cold;
    asm_.placeLabel(slow);
    try asm_.emit(a64.nop()); // cold 0
    try asm_.branch(back); // cold 1
    asm_.section = .hot;
    const code = try asm_.finish();
    try testing.expectEqual(@as(usize, 4), code.len);
    try testing.expectEqual(a64.cbnz(.x64, 3, 2), code[0]);
    try testing.expectEqual(a64.b(-2), code[3]);
}

test "split sections resolve by address and refuse a branch that cannot reach" {
    var asm_ = Assembler.init(testing.allocator);
    defer asm_.deinit();
    const slow = try asm_.createLabel();
    const back = try asm_.createLabel();
    try asm_.branchIfNonZero(.x64, 3, slow);
    asm_.placeLabel(back);
    try asm_.emit(a64.ret());
    asm_.section = .cold;
    asm_.placeLabel(slow);
    try asm_.branch(back);
    asm_.section = .hot;
    const parts = try asm_.finishSplit(0x10_0000, 0x10_0000 + 0x8000);
    try testing.expectEqual(a64.cbnz(.x64, 3, 0x8000 / 4), parts.hot[0]);
    try testing.expectEqual(a64.b(-(0x8000 / 4) + 1), parts.cold[0]);
    var far = Assembler.init(testing.allocator);
    defer far.deinit();
    const target = try far.createLabel();
    try far.branchIfZero(.x64, 1, target);
    far.section = .cold;
    far.placeLabel(target);
    try far.emit(a64.ret());
    try testing.expectError(Error.DisplacementTooFar, far.finishSplit(0, 1 << 20));
}

test "a branch to the label placed right after it is dropped unless a label names it" {
    var asm_ = Assembler.init(std.testing.allocator);
    defer asm_.deinit();
    const next = try asm_.createLabel();
    try asm_.emit(a64.nop());
    try asm_.branch(next);
    asm_.placeLabel(next);
    try std.testing.expectEqual(@as(usize, 1), asm_.words.items.len);
    try std.testing.expectEqual(@as(usize, 0), asm_.fixups.items.len);
    // A named branch (a patch site) stays.
    const site = try asm_.createLabel();
    const after = try asm_.createLabel();
    asm_.placeLabel(site);
    try asm_.branch(after);
    asm_.placeLabel(after);
    try std.testing.expectEqual(@as(usize, 2), asm_.words.items.len);
    // So does a branch over code to a later label.
    const elsewhere = try asm_.createLabel();
    try asm_.branch(elsewhere);
    try asm_.emit(a64.nop());
    asm_.placeLabel(elsewhere);
    try std.testing.expectEqual(@as(usize, 4), asm_.words.items.len);
    const words = try asm_.finish();
    try std.testing.expectEqual(a64.b(2), words[2]);
}
