//! NEAR NULL PREDICTOR — ReleaseFast-friendly near-null receiver signatures.
//!
//! Near-null casualties (a native/guest call dereferencing an address below
//! 0x1000) are rare, but when they fire the causality machinery has to work
//! backwards from the fault. This module works forwards instead: every import
//! dispatch costs one compare (`rdi < NEAR_NULL_LIMIT`), and only near-null
//! receivers record anything. Each distinct (symbol, caller) signature keeps a
//! hit count, the last receiver value, and a bounded chronological ring of the
//! most recent near-null dispatches, so a casualty report can show the
//! behaviors that fed into it.
//!
//! Logging is throttled: one `NEAR NULL PREDICTOR:` line on first sight, then
//! at most a few more per signature (receiver change or doubling thresholds),
//! so a hot near-null loop cannot flood the log. `dump` is called only from
//! the terminal near-null path and from exit diagnostics.

const std = @import("std");
const machoCapturePrint = @import("dyld").event_log.machoCapturePrint;

/// Receivers below this bound are "near null": dereferencing them faults on
/// the zero page or a tiny tag-like address. Matches the existing 0x1000
/// near-null convention used by the fault classifier and memory views.
pub const NEAR_NULL_LIMIT: u64 = 0x1000;
pub const SIGNATURE_CAPACITY: usize = 32;
pub const RECENT_CAPACITY: usize = 16;
/// Cap per-signature emissions so a recurring signature cannot spam the log.
pub const MAX_EMISSIONS_PER_SIGNATURE: u32 = 4;

const Signature = struct {
    valid: bool = false,
    symbol_hash: u64 = 0,
    /// Slice into the guest image's import metadata — stable for the process
    /// lifetime, so no copying is needed.
    symbol: []const u8 = "",
    caller: u64 = 0,
    receiver: u64 = 0,
    count: u32 = 0,
    emissions: u32 = 0,
    first_seen_step: u64 = 0,
    last_seen_step: u64 = 0,
};

const Recent = struct {
    symbol: []const u8 = "",
    caller: u64 = 0,
    receiver: u64 = 0,
    step: u64 = 0,
};

pub const Predictor = struct {
    signatures: [SIGNATURE_CAPACITY]Signature = [_]Signature{.{}} ** SIGNATURE_CAPACITY,
    recent: [RECENT_CAPACITY]Recent = [_]Recent{.{}} ** RECENT_CAPACITY,
    recent_index: usize = 0,
    recent_filled: bool = false,
    near_null_dispatches: u64 = 0,
    distinct_signatures: u32 = 0,
    emissions: u64 = 0,

    /// Hot path — one compare for the overwhelming majority of dispatches.
    /// Only near-null receivers resolve the caller and touch the table.
    pub fn note(self: *Predictor, state: anytype, symbol: []const u8) void {
        const receiver = state.regs.rdi;
        if (receiver >= NEAR_NULL_LIMIT) return;
        self.near_null_dispatches +|= 1;

        const caller = importCallerAddress(state);
        const signature = self.findOrInsert(symbol, caller) orelse return;
        self.pushRecent(symbol, caller, receiver, state.executed_steps);

        const step = state.executed_steps;
        const first_sight = signature.count == 0;
        const receiver_changed = signature.receiver != receiver;
        signature.count +|= 1;
        const doubling_threshold = (signature.count & (signature.count - 1)) == 0;
        signature.receiver = receiver;
        signature.last_seen_step = step;
        if (first_sight) signature.first_seen_step = step;

        if (first_sight or
            (receiver_changed and signature.emissions < MAX_EMISSIONS_PER_SIGNATURE) or
            (doubling_threshold and signature.emissions < MAX_EMISSIONS_PER_SIGNATURE))
        {
            signature.emissions +|= 1;
            self.emitSignature(state, signature, first_sight);
        }
    }

    /// Dump every retained signature with readable caller names. Called from
    /// the terminal near-null path (after pinFaultContext) and teardown.
    pub fn dump(self: *Predictor, state: anytype, reason: []const u8) void {
        var retained: usize = 0;
        for (&self.signatures) |*signature| {
            if (!signature.valid) continue;
            retained += 1;
            const caller_symbol = resolveSymbolName(state, signature.caller);
            machoCapturePrint(
                "NEAR NULL PREDICTOR: signature symbol={s} caller={s} receiver=0x{x} count={d} first_seen_step={d} last_seen_step={d} emissions={d}\n",
                .{
                    signature.symbol,
                    caller_symbol,
                    signature.receiver,
                    signature.count,
                    signature.first_seen_step,
                    signature.last_seen_step,
                    signature.emissions,
                },
            );
        }
        machoCapturePrint(
            "NEAR NULL PREDICTOR: dump reason={s} distinct={d} retained={d} near_null_dispatches={d} recent_window={d} emissions={d}\n",
            .{
                reason,
                self.distinct_signatures,
                retained,
                self.near_null_dispatches,
                self.recentCount(),
                self.emissions,
            },
        );
    }

    /// The most recent near-null dispatches, oldest first, for correlation.
    pub fn dumpRecent(self: *Predictor, state: anytype) void {
        const count = self.recentCount();
        if (count == 0) return;
        machoCapturePrint(
            "NEAR NULL PREDICTOR: recent near-null dispatches ({d}):\n",
            .{count},
        );
        for (0..count) |ordinal| {
            const recent = self.recentChronological(ordinal) orelse continue;
            const caller_symbol = resolveSymbolName(state, recent.caller);
            machoCapturePrint(
                "  [{d}] symbol={s} caller={s} receiver=0x{x} step={d}\n",
                .{ ordinal, recent.symbol, caller_symbol, recent.receiver, recent.step },
            );
        }
    }

    fn emitSignature(self: *Predictor, state: anytype, signature: *const Signature, first_sight: bool) void {
        self.emissions +|= 1;
        const caller_symbol = resolveSymbolName(state, signature.caller);
        const kind: []const u8 = if (first_sight) "first_sight" else "recurrence";
        machoCapturePrint(
            "NEAR NULL PREDICTOR: {s} symbol={s} caller={s} rdi=0x{x} count={d} step={d} threshold=0x{x}\n",
            .{ kind, signature.symbol, caller_symbol, signature.receiver, signature.count, signature.last_seen_step, NEAR_NULL_LIMIT },
        );
    }

    fn findOrInsert(self: *Predictor, symbol: []const u8, caller: u64) ?*Signature {
        const hash = hashSignature(symbol, caller);
        var index: usize = @intCast(hash % SIGNATURE_CAPACITY);
        var first_empty: ?usize = null;
        var probes: usize = 0;
        while (probes < SIGNATURE_CAPACITY) : (probes += 1) {
            const signature = &self.signatures[index];
            if (!signature.valid) {
                if (first_empty == null) first_empty = index;
                break;
            }
            if (signature.symbol_hash == hash and signature.caller == caller) return signature;
            index = (index + 1) % SIGNATURE_CAPACITY;
        }
        if (first_empty) |slot| {
            self.signatures[slot] = .{
                .valid = true,
                .symbol_hash = hash,
                .symbol = symbol,
                .caller = caller,
                .receiver = 0,
                .count = 0,
                .emissions = 0,
                .first_seen_step = 0,
                .last_seen_step = 0,
            };
            self.distinct_signatures +|= 1;
            return &self.signatures[slot];
        }
        // Table full of distinct signatures: evict the least recently seen so
        // the newest behavior always has a home. O(capacity) only on a full
        // table during a near-null dispatch — negligible.
        var oldest_index: usize = 0;
        var oldest_seen: u64 = std.math.maxInt(u64);
        for (&self.signatures, 0..) |*signature, i| {
            if (!signature.valid) continue;
            if (signature.last_seen_step < oldest_seen) {
                oldest_seen = signature.last_seen_step;
                oldest_index = i;
            }
        }
        self.signatures[oldest_index] = .{
            .valid = true,
            .symbol_hash = hash,
            .symbol = symbol,
            .caller = caller,
            .receiver = 0,
            .count = 0,
            .emissions = 0,
            .first_seen_step = 0,
            .last_seen_step = 0,
        };
        return &self.signatures[oldest_index];
    }

    fn pushRecent(self: *Predictor, symbol: []const u8, caller: u64, receiver: u64, step: u64) void {
        self.recent[self.recent_index] = .{ .symbol = symbol, .caller = caller, .receiver = receiver, .step = step };
        self.recent_index += 1;
        if (self.recent_index == RECENT_CAPACITY) {
            self.recent_index = 0;
            self.recent_filled = true;
        }
    }

    fn recentCount(self: *const Predictor) usize {
        return if (self.recent_filled) RECENT_CAPACITY else self.recent_index;
    }

    fn recentChronological(self: *const Predictor, ordinal: usize) ?Recent {
        const count = self.recentCount();
        if (ordinal >= count) return null;
        const start: usize = if (self.recent_filled) self.recent_index else 0;
        return self.recent[(start + ordinal) % RECENT_CAPACITY];
    }

    fn hashSignature(symbol: []const u8, caller: u64) u64 {
        var hash: u64 = 0xcbf2_9ce4_8422_2325;
        for (symbol) |byte| {
            hash ^= byte;
            hash *%= 0x100_0000_01b3;
        }
        hash ^= caller;
        hash *%= 0x100_0000_01b3;
        return hash;
    }
};

fn importCallerAddress(state: anytype) u64 {
    if (state.regs.rsp == 0 or state.guestMemoryConst(state.regs.rsp, @sizeOf(u64)) == null) {
        return state.regs.rip;
    }
    return state.read64(state.regs.rsp);
}

fn resolveSymbolName(state: anytype, address: u64) []const u8 {
    if (address == 0) return "<null>";
    if (@hasDecl(@TypeOf(state.*), "metadata")) {
        if (state.metadata.nearestSymbol(address)) |symbol| return symbol.name;
    }
    return "<unknown>";
}

test "predictor records first sight and recurrence separately" {
    const TestState = struct {
        regs: struct {
            rdi: u64 = 0,
            rip: u64 = 0x1000,
            rsp: u64 = 0x8000,
        } = .{},
        mem: [64]u8 = [_]u8{0} ** 64,
        executed_steps: u64 = 0,

        fn guestMemoryConst(self: *const @This(), address: u64, length: u64) ?[]const u8 {
            _ = address;
            _ = length;
            return self.mem[0..1];
        }

        fn read64(self: *const @This(), address: u64) u64 {
            _ = self;
            _ = address;
            return 0x2000;
        }
    };

    var predictor = Predictor{};
    var state = TestState{};
    state.regs.rdi = 0;
    state.executed_steps = 10;
    predictor.note(&state, "_ZStls...EPKc");
    try std.testing.expectEqual(@as(u64, 1), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u32, 1), predictor.distinct_signatures);
    const signature = predictor.findOrInsert("_ZStls...EPKc", 0x2000).?;
    try std.testing.expectEqual(@as(u32, 1), signature.count);
    try std.testing.expectEqual(@as(u32, 1), signature.emissions);

    // A sane receiver is ignored entirely.
    state.regs.rdi = 0x10000;
    predictor.note(&state, "_ZStls...EPKc");
    try std.testing.expectEqual(@as(u64, 1), predictor.near_null_dispatches);

    // Recurrence with the same receiver re-emits only at a doubling threshold
    // (count 2 is a power of two) and stays quiet otherwise.
    state.regs.rdi = 0;
    state.executed_steps = 20;
    predictor.note(&state, "_ZStls...EPKc");
    try std.testing.expectEqual(@as(u32, 2), signature.count);
    try std.testing.expectEqual(@as(u32, 2), signature.emissions);

    state.executed_steps = 30;
    predictor.note(&state, "_ZStls...EPKc");
    try std.testing.expectEqual(@as(u32, 3), signature.count);
    try std.testing.expectEqual(@as(u32, 2), signature.emissions);

    // A different symbol is a new distinct signature.
    predictor.note(&state, "_ZSt4endl...");
    try std.testing.expectEqual(@as(u32, 2), predictor.distinct_signatures);
}

test "predictor records when rsp is unavailable" {
    var predictor = Predictor{};
    const TestState = struct {
        regs: struct {
            rdi: u64 = 0,
            rip: u64 = 0x1000,
            rsp: u64 = 0,
        } = .{},
        executed_steps: u64 = 0,

        fn guestMemoryConst(self: *const @This(), address: u64, length: u64) ?[]const u8 {
            _ = self;
            _ = address;
            _ = length;
            return null;
        }

        fn read64(self: *const @This(), address: u64) u64 {
            _ = self;
            _ = address;
            return 0;
        }
    };
    var state = TestState{};
    // rsp = 0 -> caller falls back to rip; still recorded.
    predictor.note(&state, "_ZNK5Xbyak12LabelManager23hasUndefinedLabel_inner...");
    try std.testing.expectEqual(@as(u64, 1), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u32, 1), predictor.distinct_signatures);
}
