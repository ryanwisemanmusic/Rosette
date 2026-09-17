//! Where a thread is, whether it is getting anywhere, and if not, what it is
//! waiting for.
//!
//! ## The question this answers
//!
//! `Main XThread` held twenty-three percent of the 2026-09-12 run at
//! `rip=0xa000044b` and every downstream milestone was zero. The report could
//! say that much and no more, and "a thread is busy at an address" is not a
//! finding - a thread rasterizing a font atlas looks exactly the same. What
//! separates them is whether the addresses *move*, and if they do not, what
//! the unmoving code reads.
//!
//! A spin is a loop over a small span of code that reads memory somebody else
//! is supposed to write. Naming the span is the first half; naming the
//! address it reads, and the value there now, is the half that says who owes
//! the thread something.
//!
//! ## Why this is not in `process.zig`
//!
//! Because `process.zig` is eighteen thousand lines and this is a subsystem
//! with its own vocabulary. Nothing here touches interpreter state: it takes
//! a window somebody sampled, a register file, and a way to read guest bytes.
//! That also makes it testable without an interpreter, which is why the tests
//! at the bottom assemble their own loops.

const std = @import("std");
const x64_decoder = @import("x64_decoder");

/// One 4 KiB page per bit. Two hundred and fifty-six bits covers a megabyte
/// of distinct pages before it starts folding, which is enough that a thread
/// working through real code saturates it and a thread spinning does not.
///
/// The first version of this used sixty-four bits, and a thread alternating
/// between a JIT buffer at `0xa0000000` and the image at `0x140000000`
/// reported two pages - the two addresses folded onto two bits and the report
/// called a two-gigabyte span a spin. Four times the width does not remove
/// folding, but pairing it with the span below means neither number has to
/// carry the verdict alone.
pub const fingerprint_words: usize = 4;
pub const fingerprint_bits: usize = fingerprint_words * 64;

/// The most code a spin report will disassemble. A loop longer than this is
/// not the kind of loop this instrument is for.
pub const max_window_bytes: u64 = 512;
pub const max_instructions: usize = 64;

/// A window is judged a spin only once this many samples have landed in it,
/// so a thread that has just been scheduled is never called stuck.
pub const minimum_samples: u64 = 64;

/// How far apart two sampled instruction pointers can be and still count as
/// the same loop. One page: a compiler does not spread a hot loop wider, and
/// anything larger is a function making progress.
pub const spin_span_bytes: u64 = 0x1000;

/// Space-Saving heavy hitters. Counts have an explicit error bound; neither
/// a candidate nor a broad address span is a proof of useful progress.
pub const Hotspot = struct { address: u64 = 0, count: u64 = 0, error_bound: u64 = 0 };
pub const Heat = struct {
    candidates: [16]Hotspot = @splat(.{}),
    samples: u64 = 0,
    pub fn sample(self: *Heat, address: u64) void {
        const key = address & ~@as(u64, 255);
        self.samples +|= 1;
        var minimum: usize = 0;
        for (&self.candidates, 0..) |*candidate, index| {
            if (candidate.count != 0 and candidate.address == key) {
                candidate.count +|= 1;
                return;
            }
            if (candidate.count == 0) {
                candidate.* = .{ .address = key, .count = 1 };
                return;
            }
            if (candidate.count < self.candidates[minimum].count) minimum = index;
        }
        const previous = self.candidates[minimum].count;
        self.candidates[minimum] = .{ .address = key, .count = previous +| 1, .error_bound = previous };
    }
    pub fn top(self: *const Heat) [3]Hotspot {
        var result: [3]Hotspot = @splat(.{});
        for (self.candidates) |candidate| {
            for (0..3) |index| {
                if (candidate.count <= result[index].count) continue;
                var move: usize = 2;
                while (move > index) : (move -= 1) result[move] = result[move - 1];
                result[index] = candidate;
                break;
            }
        }
        return result;
    }
};

/// Where a thread has been executing.
///
/// Two windows are kept, current and previous, because the current one is
/// reset at every checkpoint and a thread sampled twice since the last reset
/// would otherwise look like it had never moved.
pub const Window = struct {
    /// Lowest and highest address ever sampled, for the whole run.
    low: u64 = std.math.maxInt(u64),
    high: u64 = 0,
    /// The same, since the last roll.
    recent_low: u64 = std.math.maxInt(u64),
    recent_high: u64 = 0,
    previous_low: u64 = std.math.maxInt(u64),
    previous_high: u64 = 0,
    pages: [fingerprint_words]u64 = [_]u64{0} ** fingerprint_words,
    previous_pages: [fingerprint_words]u64 = [_]u64{0} ** fingerprint_words,
    samples: u64 = 0,
    recent_samples: u64 = 0,
    heat: Heat = .{},

    pub fn sample(self: *Window, address: u64) void {
        // Window is sampled every 64 instructions. Heat is 16 times rarer:
        // about one observation per 1,024 instructions, fixed memory/cost.
        if ((self.samples & 15) == 0) self.heat.sample(address);
        if (address < self.low) self.low = address;
        if (address > self.high) self.high = address;
        if (address < self.recent_low) self.recent_low = address;
        if (address > self.recent_high) self.recent_high = address;
        const bit: usize = @intCast((address >> 12) % fingerprint_bits);
        self.pages[bit / 64] |= @as(u64, 1) << @intCast(bit % 64);
        self.samples +|= 1;
        self.recent_samples +|= 1;
    }

    /// Start a new window, keeping the last one.
    pub fn roll(self: *Window) void {
        self.previous_pages = self.pages;
        self.previous_low = self.recent_low;
        self.previous_high = self.recent_high;
        self.pages = [_]u64{0} ** fingerprint_words;
        self.recent_low = std.math.maxInt(u64);
        self.recent_high = 0;
        self.recent_samples = 0;
    }

    /// Bytes between the lowest and highest address ever sampled. Spans
    /// regions, so a thread that has run in both an image and a JIT buffer
    /// reports an enormous number - which is why it is not the spin test.
    pub fn span(self: *const Window) u64 {
        if (self.samples == 0 or self.high < self.low) return 0;
        return self.high - self.low;
    }

    /// The lowest and highest of the current window and the one before it.
    pub fn recentBounds(self: *const Window) ?struct { low: u64, high: u64 } {
        const low = @min(self.recent_low, self.previous_low);
        const high = @max(self.recent_high, self.previous_high);
        if (high < low or high == 0) return null;
        return .{ .low = low, .high = high };
    }

    pub fn recentSpan(self: *const Window) u64 {
        const bounds = self.recentBounds() orelse return 0;
        return bounds.high - bounds.low;
    }

    pub fn pageCount(self: *const Window) u32 {
        var total: u32 = 0;
        for (self.pages, self.previous_pages) |current, previous| {
            total += @popCount(current | previous);
        }
        return total;
    }

    /// Whether this thread has been going round in a small piece of code.
    ///
    /// Both tests, not either. The page count alone folds distant addresses
    /// together; the span alone cannot tell a tight loop from a thread that
    /// happened to sample twice at nearby addresses. Requiring a minimum
    /// number of samples keeps a freshly scheduled thread out of it.
    pub fn isSpin(self: *const Window) bool {
        if (self.samples < minimum_samples) return false;
        const bounds = self.recentBounds() orelse return false;
        if (bounds.high - bounds.low > spin_span_bytes) return false;
        return self.pageCount() <= 2;
    }
};

test "bounded heat identifies a hot generated-code region across widely moving callers" {
    var heat = Heat{};
    for (0..1000) |index| {
        heat.sample(0xa0000100 + index % 32);
        if (index % 8 == 0) heat.sample(0x140000000 + index * 4096);
    }
    const top = heat.top();
    try std.testing.expectEqual(@as(u64, 0xa0000100), top[0].address);
    try std.testing.expectEqual(@as(u64, 1000), top[0].count);
    try std.testing.expectEqual(@as(u64, 0), top[0].error_bound);
    for (top) |candidate| try std.testing.expect(candidate.error_bound <= candidate.count);
}

/// How guest bytes are read. A closure rather than a memory type, so this
/// module never learns what a guest is.
pub const CodeReader = struct {
    context: *const anyopaque,
    /// Fill `out` from `address`, returning how many bytes were readable.
    /// Zero means the address is not mapped.
    read: *const fn (context: *const anyopaque, address: u64, out: []u8) usize,
};

pub const Instruction = struct {
    address: u64 = 0,
    length: u8 = 0,
    op: x64_decoder.Op = .invalid,
    /// The address this instruction touches, when it has a memory operand and
    /// the register file was enough to compute one.
    memory: ?u64 = null,
    base_reg: ?x64_decoder.RegId = null,
    index_reg: ?x64_decoder.RegId = null,
    displacement: u64 = 0,
    rip_relative: bool = false,
};

pub const Listing = struct {
    instructions: [max_instructions]Instruction = [_]Instruction{.{}} ** max_instructions,
    count: usize = 0,
    /// Set when the window was longer than the instrument will read, so a
    /// reader knows the listing is a prefix rather than the whole loop.
    truncated: bool = false,
    /// The first address the decoder could not make sense of, if any. A
    /// window that will not decode is itself a finding: it means the thread
    /// is not executing what this instrument thinks it is.
    undecodable_at: ?u64 = null,

    pub fn slice(self: *const Listing) []const Instruction {
        return self.instructions[0..self.count];
    }

    /// The distinct addresses this loop reads or writes, most useful first.
    ///
    /// A polling loop reads one or two. Those are the addresses somebody else
    /// is supposed to change, and naming them is the point of the whole
    /// exercise: a spin is only diagnosable once you know what it is waiting
    /// for.
    pub fn touchedAddresses(self: *const Listing, out: []u64) usize {
        var used: usize = 0;
        for (self.slice()) |instruction| {
            const address = instruction.memory orelse continue;
            var seen = false;
            for (out[0..used]) |existing| {
                if (existing == address) seen = true;
            }
            if (seen) continue;
            if (used == out.len) return used;
            out[used] = address;
            used += 1;
        }
        return used;
    }

    /// Whether the listing ends in a branch back into itself, which is what
    /// makes a run of instructions a loop rather than a straight line the
    /// sampler happened to catch twice.
    pub fn hasBackwardBranch(self: *const Listing) bool {
        for (self.slice()) |instruction| {
            if (!isBranch(instruction.op)) continue;
            // A backward branch inside the window: the target is encoded as a
            // displacement from the next instruction, which the decoder has
            // already folded into `addr` for relative forms.
            const target = instruction.displacement;
            if (target != 0 and target <= instruction.address and target >= self.instructions[0].address) return true;
        }
        return false;
    }
};

/// Whether this instruction transfers control.
///
/// Named against the decoder's own operation vocabulary rather than by
/// pattern-matching the tag text: `jcc_rel8` and `jmp_rel32` are branches,
/// and so is anything whose name begins `jmp_`, `jcc_` or `call_`.
fn isBranch(op: x64_decoder.Op) bool {
    const name = @tagName(op);
    return std.mem.startsWith(u8, name, "jmp_") or
        std.mem.startsWith(u8, name, "jcc_") or
        std.mem.startsWith(u8, name, "call_");
}

/// Whether a decoded instruction's `addr` field is a branch target rather
/// than part of a memory operand.
///
/// The decoder puts a relative branch's destination in the same field that
/// carries a displacement, so a `jne` back into the loop reported a memory
/// operand and `touchedAddresses` returned the loop's own top as an address
/// the loop was polling. Naming a code address as the thing the thread is
/// waiting for would send a reader looking for a writer that does not exist.
fn addressFieldIsBranchTarget(op: x64_decoder.Op) bool {
    const name = @tagName(op);
    return std.mem.endsWith(u8, name, "_rel8") or std.mem.endsWith(u8, name, "_rel32");
}

/// Decode the code a thread has been going round in.
///
/// `regs` supplies the values for computing effective addresses. They are the
/// thread's registers at the moment it was last seen, so an address computed
/// from them is where the *last* iteration looked - which for a poll is the
/// same place every iteration looks, and that is exactly the case this is
/// for. For anything else the address is indicative, and the base register is
/// reported beside it so a reader can see what it was derived from.
pub fn disassemble(
    reader: CodeReader,
    regs: *const x64_decoder.Regs,
    low: u64,
    high: u64,
) Listing {
    var listing = Listing{};
    if (high < low) return listing;
    var length = high - low + 1;
    if (length > max_window_bytes) {
        length = max_window_bytes;
        listing.truncated = true;
    }

    var address = low;
    const limit = low + length;
    var bytes: [16]u8 = undefined;
    while (address < limit and listing.count < max_instructions) {
        const readable = reader.read(reader.context, address, &bytes);
        if (readable == 0) {
            listing.undecodable_at = address;
            break;
        }
        const decoded = x64_decoder.decodeLegacyInstruction(bytes[0..readable], .long64);
        if (decoded.len == 0 or decoded.op == .invalid) {
            listing.undecodable_at = address;
            break;
        }
        var instruction = Instruction{
            .address = address,
            .length = decoded.len,
            .op = decoded.op,
            .displacement = decoded.addr,
            .rip_relative = decoded.rip_relative,
        };
        if (!decoded.is_reg_form and !addressFieldIsBranchTarget(decoded.op)) {
            var effective: u64 = decoded.addr;
            if (decoded.sib_has_base) {
                instruction.base_reg = decoded.sib_base_reg;
                effective +%= x64_decoder.regVal(regs, decoded.sib_base_reg, .bits64);
            }
            if (decoded.sib_has_index) {
                instruction.index_reg = decoded.sib_index_reg;
                effective +%= x64_decoder.regVal(regs, decoded.sib_index_reg, .bits64) << @as(u6, decoded.sib_scale);
            }
            if (decoded.rip_relative) effective = address +% decoded.len +% decoded.addr;
            // Only claim an address when something contributed one. A pure
            // displacement of zero with no base is not a memory operand, it
            // is an instruction with no memory operand at all.
            if (decoded.sib_has_base or decoded.sib_has_index or decoded.rip_relative or decoded.addr != 0) {
                instruction.memory = effective;
            }
        }
        listing.instructions[listing.count] = instruction;
        listing.count += 1;
        address += decoded.len;
    }
    if (address < limit and listing.undecodable_at == null) listing.truncated = true;
    return listing;
}

// ---------------------------------------------------------------------------

const TestMemory = struct {
    base: u64,
    bytes: []const u8,

    fn read(context: *const anyopaque, address: u64, out: []u8) usize {
        const self: *const TestMemory = @ptrCast(@alignCast(context));
        if (address < self.base) return 0;
        const offset = address - self.base;
        if (offset >= self.bytes.len) return 0;
        const available = @min(out.len, self.bytes.len - offset);
        @memcpy(out[0..available], self.bytes[@intCast(offset)..][0..available]);
        return available;
    }

    fn reader(self: *const TestMemory) CodeReader {
        return .{ .context = self, .read = TestMemory.read };
    }
};

test "a window that stays in one page is a spin; one that moves is not" {
    var window = Window{};
    try std.testing.expect(!window.isSpin());

    // A tight loop: twenty-four bytes, sampled well past the minimum.
    for (0..minimum_samples * 2) |step| {
        window.sample(0xA0026000 + (step % 6) * 4);
    }
    try std.testing.expect(window.isSpin());
    try std.testing.expect(window.recentSpan() < spin_span_bytes);
    try std.testing.expectEqual(@as(u32, 1), window.pageCount());

    // The same thread, now working through code.
    var working = Window{};
    for (0..minimum_samples * 2) |step| {
        working.sample(0xA0100000 + step * 0x800);
    }
    try std.testing.expect(!working.isSpin());
    try std.testing.expect(working.recentSpan() > spin_span_bytes);
}

test "a freshly scheduled thread is never called stuck" {
    var window = Window{};
    // Two samples at the same address is not evidence of anything.
    window.sample(0xA0026000);
    window.sample(0xA0026000);
    try std.testing.expect(!window.isSpin());
    try std.testing.expect(window.samples < minimum_samples);
}

test "rolling keeps the previous window, so a reset is not read as a stall" {
    var window = Window{};
    for (0..minimum_samples * 2) |step| window.sample(0xA0026000 + (step % 6) * 4);
    const pages_before = window.pageCount();
    window.roll();
    // Current window empty, but the verdict survives on the previous one.
    try std.testing.expectEqual(@as(u64, 0), window.recent_samples);
    try std.testing.expectEqual(pages_before, window.pageCount());
    try std.testing.expect(window.isSpin());
}

test "the two-gigabyte span that read as two pages" {
    // The shape that broke the first version: a thread seen in a JIT buffer
    // and in the loaded image. Sixty-four bits folded the two addresses onto
    // two bits, the page count said two, and the verdict called a span of
    // 2.79 GB a spin.
    var window = Window{};
    for (0..minimum_samples) |_| {
        window.sample(0xA000044B);
        window.sample(0x146C0000);
    }
    try std.testing.expect(window.span() > 1_000_000_000);
    // Whatever the fingerprint folds to, the span refuses the verdict.
    try std.testing.expect(!window.isSpin());
}

test "a polling loop names the address it is polling" {
    // cmp dword ptr [rbx+0x10], 0 ; jne -7   -- the shape of every poll.
    const code = [_]u8{
        0x83, 0x7B, 0x10, 0x00, // cmpl $0x0, 0x10(%rbx)
        0x75, 0xF9, // jne .-7
    };
    var memory = TestMemory{ .base = 0xA0026000, .bytes = &code };
    var regs = std.mem.zeroes(x64_decoder.Regs);
    regs.rbx = 0x40004BF0;

    const listing = disassemble(memory.reader(), &regs, 0xA0026000, 0xA0026005);
    try std.testing.expectEqual(@as(usize, 2), listing.count);
    try std.testing.expectEqual(@as(?u64, null), listing.undecodable_at);

    // The whole point: the address the loop reads, computed from the base
    // register the instruction actually uses.
    var touched: [4]u64 = undefined;
    const count = listing.touchedAddresses(&touched);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u64, 0x40004C00), touched[0]);
    try std.testing.expectEqual(x64_decoder.RegId.bl_bx_ebx_rbx, listing.instructions[0].base_reg.?);
}

test "a window that will not decode says where it stopped" {
    // An address the reader cannot serve is not a decode failure, and an
    // undecodable byte is not an empty window. Both have to be reported
    // rather than producing a short listing that looks complete.
    const code = [_]u8{ 0x90, 0x90, 0xFF, 0xFF, 0xFF, 0xFF };
    var memory = TestMemory{ .base = 0x1000, .bytes = &code };
    var regs = std.mem.zeroes(x64_decoder.Regs);
    const listing = disassemble(memory.reader(), &regs, 0x1000, 0x1005);
    try std.testing.expect(listing.count >= 2);
    try std.testing.expect(listing.undecodable_at != null);

    var unreadable = TestMemory{ .base = 0x9000, .bytes = &code };
    const nothing = disassemble(unreadable.reader(), &regs, 0x1000, 0x1005);
    try std.testing.expectEqual(@as(usize, 0), nothing.count);
    try std.testing.expectEqual(@as(?u64, 0x1000), nothing.undecodable_at);
}

test "a long window is truncated rather than silently cut" {
    var code: [max_window_bytes * 2]u8 = undefined;
    @memset(&code, 0x90); // nop
    var memory = TestMemory{ .base = 0x2000, .bytes = &code };
    var regs = std.mem.zeroes(x64_decoder.Regs);
    const listing = disassemble(memory.reader(), &regs, 0x2000, 0x2000 + code.len - 1);
    try std.testing.expect(listing.truncated);
    try std.testing.expect(listing.count <= max_instructions);
}
