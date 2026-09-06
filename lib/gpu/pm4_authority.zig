//! Two independent accounts of one PM4 stream that have to agree.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run described the same batch twice. The Xenos packet trace
//! reported 72 packets, 5 indirect references, no unknown opcodes and no
//! truncation. A VdSwap contract sample in the same run reported packet
//! anomalies of `4/0`. One of those is wrong and nothing decided which,
//! because the two came from different decoders with different framing rules
//! and their disagreement was folded into a health percentage.
//!
//! Until that is settled, the absence of render-target state in the stream is
//! not usable evidence about the title: a decoder that miscounts packet
//! lengths also misses register writes.
//!
//! So there is one account per decoder, a structured comparison between them,
//! and an explicit source class. The read-only structural walker and the
//! stateful executor must produce the same packet, guest-encoded register,
//! draw, event and swap counts for the exact same root and indirect contents.
//! A disagreement is a named failure with both numbers printed, never an
//! average. Re-running one decoder twice is never corroboration.
//!
//! What replay never becomes
//! -------------------------
//! A replayed batch is `SourceClass.replay` for its whole life. Paired with an
//! independent structural walk it can prove decoder agreement; it can never
//! prove the guest executed anything.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;
pub const Measurement = bridge.reconcile.Measurement;
pub const Agreement = bridge.reconcile.Agreement;
pub const Domain = bridge.contract.Domain;

/// Which independently implemented parser produced an account. Source class
/// alone cannot answer this: a retained stateful execution is `.replay`, but a
/// live structural walk and live stateful execution may both be
/// `.guest_authentic` while still being two independent decoders.
pub const Decoder = enum(u8) {
    structural_walk,
    stateful_executor,
    unknown,

    pub fn label(self: Decoder) []const u8 {
        return switch (self) {
            .structural_walk => "structural-walk",
            .stateful_executor => "stateful-executor",
            .unknown => "unknown",
        };
    }
};

/// Why a packet stream stopped making sense. Named rather than counted: a
/// truncated ring and an unknown opcode need different people.
pub const DefectKind = enum(u8) {
    /// A packet declared more dwords than the buffer holds.
    truncated = 0,
    /// The header did not decode as any packet type.
    malformed_header = 1,
    /// A type-3 opcode the decoder has no semantics for.
    unknown_opcode = 2,
    /// An indirect buffer pointed somewhere unreadable.
    indirect_unreadable = 3,
    /// Indirect nesting exceeded the depth budget.
    indirect_depth = 4,
    /// A register index outside the Xenos register file.
    register_out_of_range = 5,
    /// A register index inside the file with no classification.
    register_unclassified = 6,
    /// The stream lost alignment with the packet boundaries.
    desynchronised = 7,

    pub fn label(self: DefectKind) []const u8 {
        return switch (self) {
            .truncated => "truncated",
            .malformed_header => "malformed-header",
            .unknown_opcode => "unknown-opcode",
            .indirect_unreadable => "indirect-unreadable",
            .indirect_depth => "indirect-depth",
            .register_out_of_range => "register-out-of-range",
            .register_unclassified => "register-unclassified",
            .desynchronised => "desynchronised",
        };
    }

    /// Whether continuing past this can silently change what the guest asked
    /// for. The audit's point about `gpu_ignore_unimplemented_opcode`: an
    /// unknown opcode can program state, synchronise, resolve, or kick a
    /// present, and skipping it leaves the guest waiting forever.
    pub fn continuationChangesSemantics(self: DefectKind) bool {
        return switch (self) {
            .unknown_opcode, .desynchronised, .truncated, .malformed_header => true,
            .indirect_unreadable, .indirect_depth, .register_out_of_range, .register_unclassified => false,
        };
    }
};

pub const defect_count: usize = @typeInfo(DefectKind).@"enum".fields.len;

/// One decoder's account of a batch. Comparable to another account only when
/// it describes the same batch.
pub const Account = struct {
    domain: Domain = .unknown,
    source: SourceClass = .unknown,
    decoder: Decoder = .unknown,
    /// Identifies which batch this describes. Two accounts of different
    /// batches are not evidence about each other.
    batch_id: u64 = 0,
    dwords_examined: u64 = 0,
    root_packets: u64 = 0,
    nested_packets: u64 = 0,
    indirect_references: u64 = 0,
    register_writes: u64 = 0,
    draws: u64 = 0,
    event_writes: u64 = 0,
    swaps: u64 = 0,
    defects: [defect_count]u64 = [_]u64{0} ** defect_count,
    stated: bool = false,

    pub fn packets(self: Account) u64 {
        return self.root_packets +| self.nested_packets;
    }

    pub fn totalDefects(self: Account) u64 {
        var total: u64 = 0;
        for (self.defects) |count| total +|= count;
        return total;
    }

    pub fn noteDefect(self: *Account, kind: DefectKind) void {
        self.defects[@intFromEnum(kind)] +|= 1;
    }

    /// Defects that make continuing change what the guest asked for.
    pub fn semanticDefects(self: Account) u64 {
        var total: u64 = 0;
        var index: usize = 0;
        while (index < defect_count) : (index += 1) {
            const kind: DefectKind = @enumFromInt(index);
            if (kind.continuationChangesSemantics()) total +|= self.defects[index];
        }
        return total;
    }
};

/// What a field-by-field comparison of two accounts found.
pub const Field = enum(u8) {
    packets = 0,
    indirect_references = 1,
    register_writes = 2,
    draws = 3,
    event_writes = 4,
    swaps = 5,
    defects = 6,

    pub fn label(self: Field) []const u8 {
        return switch (self) {
            .packets => "packets",
            .indirect_references => "indirect references",
            .register_writes => "register writes",
            .draws => "draws",
            .event_writes => "event writes",
            .swaps => "swaps",
            .defects => "defects",
        };
    }

    pub fn valueOf(self: Field, account: Account) u64 {
        return switch (self) {
            .packets => account.packets(),
            .indirect_references => account.indirect_references,
            .register_writes => account.register_writes,
            .draws => account.draws,
            .event_writes => account.event_writes,
            .swaps => account.swaps,
            .defects => account.totalDefects(),
        };
    }
};

pub const field_count: usize = @typeInfo(Field).@"enum".fields.len;

/// The result of comparing two accounts of one batch.
pub const Comparison = struct {
    comparable: bool = false,
    /// Fields where the two disagree.
    disagreements: u32 = 0,
    first_field: ?Field = null,
    first_left: u64 = 0,
    first_right: u64 = 0,

    pub fn agrees(self: Comparison) bool {
        return self.comparable and self.disagreements == 0;
    }
};

/// Compare two accounts. Accounts of different batches are not compared at
/// all: reporting them as disagreeing would manufacture a defect out of two
/// correct decoders reading different data.
pub fn compare(left: Account, right: Account) Comparison {
    var out = Comparison{};
    if (!left.stated or !right.stated) return out;
    if (left.batch_id == 0 or left.batch_id != right.batch_id) return out;
    out.comparable = true;
    inline for (@typeInfo(Field).@"enum".fields) |field| {
        const which: Field = @enumFromInt(field.value);
        const a = which.valueOf(left);
        const b = which.valueOf(right);
        if (a != b) {
            out.disagreements += 1;
            if (out.first_field == null) {
                out.first_field = which;
                out.first_left = a;
                out.first_right = b;
            }
        }
    }
    return out;
}

/// What the authority concluded.
pub const Verdict = enum(u8) {
    /// Nothing decoded.
    unobserved,
    /// One account. Usable, uncorroborated.
    single_account,
    /// Two accounts of one batch agreeing on every field.
    corroborated,
    /// Two accounts of one batch disagreeing. Neither may be quoted until it
    /// is resolved.
    decoder_disagreement,
    /// A defect that changes semantics if execution continues past it.
    semantic_defect,
    /// Accounts exist for different batches, so nothing was corroborated.
    uncomparable_accounts,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .single_account => "single-account",
            .corroborated => "corroborated",
            .decoder_disagreement => "DECODER-DISAGREEMENT",
            .semantic_defect => "SEMANTIC-DEFECT",
            .uncomparable_accounts => "uncomparable-accounts",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "no decoder has produced an account. The stream's contents are unknown, which is not the same as empty",
            .single_account => "one decoder, uncorroborated. Its counts are the best available and nothing has checked them",
            .corroborated => "two decoders of the same batch agree on packets, indirect references, register writes, draws, events, swaps and defects. this proves only the decoded contents of this batch, not its live execution or coverage of other batches",
            .decoder_disagreement => "two decoders of one batch disagree. Until that is resolved, absence of render-target state in this stream is not evidence about the title — a decoder that miscounts packet lengths also misses register writes. Both numbers are printed and neither is promoted",
            .semantic_defect => "the stream contains a defect that changes what the guest asked for if execution continues past it. An unknown opcode can program state, synchronise, resolve or kick a present; skipping it can leave the guest waiting forever with no crash to show for it",
            .uncomparable_accounts => "accounts exist for different batches, so they corroborate nothing. This is a hole in the comparison rather than a disagreement",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .decoder_disagreement or self == .semantic_defect;
    }

    /// Whether an absence in the stream may be quoted as the guest not having
    /// asked for something.
    pub fn absenceIsQuotable(self: Verdict) bool {
        return self == .corroborated;
    }
};

pub const max_accounts: usize = 4;

pub const Ledger = struct {
    accounts: [max_accounts]Account = [_]Account{.{}} ** max_accounts,
    count: usize = 0,
    /// Accounts offered past the capacity. Counted so a report cannot present
    /// a partial comparison as a complete one.
    dropped: u64 = 0,
    batch_id: u64 = 0,

    pub fn open(self: *Ledger, batch_id: u64) void {
        self.batch_id = batch_id;
        self.count = 0;
        self.dropped = 0;
        self.accounts = [_]Account{.{}} ** max_accounts;
    }

    pub fn record(self: *Ledger, account: Account) bool {
        if (self.count >= max_accounts) {
            self.dropped +|= 1;
            return false;
        }
        var stamped = account;
        stamped.stated = true;
        if (stamped.batch_id == 0) stamped.batch_id = self.batch_id;
        self.accounts[self.count] = stamped;
        self.count += 1;
        return true;
    }

    pub fn retained(self: *const Ledger) []const Account {
        return self.accounts[0..self.count];
    }

    /// A non-replay account, retained for source-provenance reports. Authority
    /// itself is based on decoder independence, not this source distinction.
    pub fn live(self: *const Ledger) ?Account {
        for (self.retained()) |account| {
            if (account.source != .replay) return account;
        }
        return null;
    }

    pub fn replay(self: *const Ledger) ?Account {
        for (self.retained()) |account| {
            if (account.source == .replay) return account;
        }
        return null;
    }

    pub fn comparison(self: *const Ledger) Comparison {
        const accounts = self.retained();
        for (accounts, 0..) |left, left_index| {
            if (left.decoder == .unknown) continue;
            for (accounts[left_index + 1 ..]) |right| {
                if (right.decoder == .unknown or right.decoder == left.decoder) continue;
                return compare(left, right);
            }
        }
        return .{};
    }

    pub fn verdict(self: *const Ledger) Verdict {
        if (self.count == 0) return .unobserved;
        var semantic: u64 = 0;
        for (self.retained()) |account| semantic +|= account.semanticDefects();
        if (semantic != 0) return .semantic_defect;
        if (self.count == 1) return .single_account;
        const result = self.comparison();
        if (!result.comparable) return .uncomparable_accounts;
        return if (result.agrees()) .corroborated else .decoder_disagreement;
    }

    /// Agreement over retained bytes validates decoding, not live execution.
    pub fn provesLiveExecution(self: *const Ledger) bool {
        if (self.verdict() != .corroborated) return false;
        for (self.retained()) |account| {
            if (account.decoder == .stateful_executor and account.source == .guest_authentic) return true;
        }
        return false;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = self.batch_id;
        for (self.retained()) |account| {
            hash = hash *% 31 +% account.packets();
            hash = hash *% 31 +% account.draws;
            hash = hash *% 31 +% account.totalDefects();
            hash = hash *% 31 +% @intFromEnum(account.decoder);
        }
        return hash *% 31 +% @intFromEnum(self.verdict());
    }
};

fn cleanAccount(domain: Domain, source: SourceClass, decoder: Decoder) Account {
    return .{
        .domain = domain,
        .source = source,
        .decoder = decoder,
        .batch_id = 1,
        .dwords_examined = 25,
        .root_packets = 3,
        .nested_packets = 69,
        .indirect_references = 5,
        .register_writes = 112,
        .draws = 24,
        .event_writes = 2,
        .swaps = 0,
    };
}

// The exact 2026-08-31 disagreement: one decoder reporting no truncation and
// another reporting four anomalies over the same batch.
test "two decoders that disagree are both printed and neither is promoted" {
    var ledger = Ledger{};
    ledger.open(1);
    _ = ledger.record(cleanAccount(.rosette_gpu, .guest_authentic, .structural_walk));
    var other = cleanAccount(.rosette_gpu, .replay, .stateful_executor);
    other.noteDefect(.indirect_unreadable);
    other.noteDefect(.indirect_unreadable);
    other.noteDefect(.indirect_unreadable);
    other.noteDefect(.indirect_unreadable);
    _ = ledger.record(other);

    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.decoder_disagreement, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expect(!verdict.absenceIsQuotable());

    const result = ledger.comparison();
    try std.testing.expect(result.comparable);
    try std.testing.expectEqual(@as(u32, 1), result.disagreements);
    try std.testing.expectEqual(Field.defects, result.first_field.?);
    try std.testing.expectEqual(@as(u64, 0), result.first_left);
    try std.testing.expectEqual(@as(u64, 4), result.first_right);
}

test "independent structural and stateful decoders make absences quotable" {
    var ledger = Ledger{};
    ledger.open(1);
    _ = ledger.record(cleanAccount(.rosette_gpu, .guest_authentic, .structural_walk));
    _ = ledger.record(cleanAccount(.rosette_gpu, .replay, .stateful_executor));
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.corroborated, verdict);
    try std.testing.expect(verdict.absenceIsQuotable());
    try std.testing.expect(ledger.comparison().agrees());
    // The replay never takes the live role however complete it is.
    try std.testing.expectEqual(SourceClass.guest_authentic, ledger.live().?.source);
    try std.testing.expectEqual(SourceClass.replay, ledger.replay().?.source);
}

test "running one decoder twice is not corroboration" {
    var ledger = Ledger{};
    ledger.open(1);
    _ = ledger.record(cleanAccount(.rosette_gpu, .guest_authentic, .structural_walk));
    _ = ledger.record(cleanAccount(.rosette_gpu, .replay, .structural_walk));
    try std.testing.expectEqual(Verdict.uncomparable_accounts, ledger.verdict());
    try std.testing.expect(!ledger.comparison().comparable);
    try std.testing.expect(!ledger.verdict().absenceIsQuotable());
}

test "accounts of different batches corroborate nothing" {
    var ledger = Ledger{};
    ledger.open(1);
    _ = ledger.record(cleanAccount(.rosette_gpu, .guest_authentic, .structural_walk));
    var other = cleanAccount(.rosette_gpu, .replay, .stateful_executor);
    other.batch_id = 2;
    _ = ledger.record(other);
    try std.testing.expectEqual(Verdict.uncomparable_accounts, ledger.verdict());
    try std.testing.expect(!ledger.comparison().comparable);
    try std.testing.expect(!ledger.verdict().absenceIsQuotable());
}

// The `gpu_ignore_unimplemented_opcode = true` hazard.
test "an unknown opcode is a semantic defect and outranks agreement" {
    var ledger = Ledger{};
    ledger.open(1);
    var live_account = cleanAccount(.rosette_gpu, .guest_authentic, .structural_walk);
    live_account.noteDefect(.unknown_opcode);
    _ = ledger.record(live_account);
    var replay_account = cleanAccount(.rosette_gpu, .replay, .stateful_executor);
    replay_account.noteDefect(.unknown_opcode);
    _ = ledger.record(replay_account);

    // The two agree exactly, and agreement is not the finding here.
    try std.testing.expect(ledger.comparison().agrees());
    try std.testing.expectEqual(Verdict.semantic_defect, ledger.verdict());
    try std.testing.expect(DefectKind.unknown_opcode.continuationChangesSemantics());
    try std.testing.expect(!DefectKind.register_unclassified.continuationChangesSemantics());
    try std.testing.expectEqual(@as(u64, 1), live_account.semanticDefects());
}

test "one account is uncorroborated and nothing decoded is unobserved" {
    var ledger = Ledger{};
    try std.testing.expectEqual(Verdict.unobserved, ledger.verdict());
    ledger.open(1);
    _ = ledger.record(cleanAccount(.rosette_gpu, .guest_authentic, .structural_walk));
    try std.testing.expectEqual(Verdict.single_account, ledger.verdict());
    try std.testing.expect(!Verdict.single_account.absenceIsQuotable());
}

test "opening a new batch clears the previous accounts" {
    var ledger = Ledger{};
    ledger.open(1);
    _ = ledger.record(cleanAccount(.rosette_gpu, .guest_authentic, .structural_walk));
    try std.testing.expectEqual(@as(usize, 1), ledger.retained().len);
    ledger.open(2);
    try std.testing.expectEqual(@as(usize, 0), ledger.retained().len);
    try std.testing.expectEqual(Verdict.unobserved, ledger.verdict());
}

test "accounts past capacity are counted rather than silently ignored" {
    var ledger = Ledger{};
    ledger.open(1);
    var index: usize = 0;
    while (index < max_accounts) : (index += 1) {
        try std.testing.expect(ledger.record(cleanAccount(.rosette_gpu, .guest_authentic, .structural_walk)));
    }
    try std.testing.expect(!ledger.record(cleanAccount(.rosette_gpu, .replay, .stateful_executor)));
    try std.testing.expectEqual(@as(u64, 1), ledger.dropped);
}

test "every defect kind and field states its own vocabulary" {
    inline for (@typeInfo(DefectKind).@"enum".fields) |field| {
        const kind: DefectKind = @enumFromInt(field.value);
        try std.testing.expect(kind.label().len != 0);
    }
    inline for (@typeInfo(Field).@"enum".fields) |field| {
        const which: Field = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    try std.testing.expectEqual(@as(usize, 8), defect_count);
    try std.testing.expectEqual(@as(usize, 7), field_count);
}

test "replay decoder agreement cannot satisfy the live execution gate" {
    var ledger = Ledger{};
    const walk = cleanAccount(.rosette_gpu, .host_forwarded, .structural_walk);
    const replayed = cleanAccount(.rosette_gpu, .replay, .stateful_executor);
    ledger.open(walk.batch_id);
    try std.testing.expect(ledger.record(walk));
    try std.testing.expect(ledger.record(replayed));
    try std.testing.expectEqual(Verdict.corroborated, ledger.verdict());
    try std.testing.expect(!ledger.provesLiveExecution());
}
