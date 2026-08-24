//! Route-independent: reject a substring search before running it.
//!
//! Rosette matches fixed phrase sets against text on several hot paths — guest
//! log lines, host symbol names, Xenia's startup narration. In every case the
//! overwhelmingly common answer is "no phrase matches", and the expensive part
//! was proving that once per phrase.
//!
//! The phrase set is known when Rosette is compiled, so the proof can be
//! prepared then. Each phrase gets a **rare character**: the character of that
//! phrase which occurs in the fewest phrases of the set. At runtime one pass
//! over the subject builds a 256-bit presence mask; a phrase whose rare
//! character is absent from the subject cannot possibly be a substring of it,
//! so a single bit test retires it.
//!
//! ## Why it is sound
//!
//! `indexOf(subject, phrase) != null` requires **every** character of `phrase`
//! to appear somewhere in `subject`. So the absence of any one of them is a
//! proof of non-match. That argument holds for `exact`, `prefix`, `suffix` and
//! `contains` matching alike, because all four are at least as strict as
//! "contains". It does **not** hold for case-insensitive or normalising
//! comparisons, and this package does not offer those.
//!
//! Every consumer is expected to carry a test that runs its own phrase set
//! through both the filtered and the unfiltered path and asserts they agree.
//! The soundness argument above is why that test can pass; the test is why the
//! optimisation is safe to keep when someone edits the table.
//!
//! ## Why the rare character is chosen against the set, not the alphabet
//!
//! A globally rare letter like `q` is useless if it appears in the one phrase
//! being tested and nowhere else — it is already selective. What matters is how
//! many *other* phrases share it, because that decides how often the bit test
//! fails to discriminate. Choosing per-set means adding a phrase re-derives the
//! choice for every phrase automatically, at build time, with no runtime cost.
//!
//! ## What this package is not
//!
//! * It is not a matcher. It never reports a match; it only reports that one is
//!   impossible. Callers still run a real comparison on survivors.
//! * It has no opinion about what a phrase means. Stage identity, contract
//!   selection and log policy all stay with their owners.
//! * It allocates nothing and its state is entirely comptime.

const std = @import("std");

/// A 256-bit set of the byte values present in a subject.
pub const CharacterSet = struct {
    words: [4]u64 = [_]u64{0} ** 4,

    pub fn contains(self: CharacterSet, character: u8) bool {
        return self.words[character >> 6] & (@as(u64, 1) << @as(u6, @truncate(character))) != 0;
    }

    pub fn add(self: *CharacterSet, character: u8) void {
        self.words[character >> 6] |= @as(u64, 1) << @as(u6, @truncate(character));
    }
};

/// Build the presence mask in a single pass.
///
/// This is the whole per-subject cost the filter adds, and it replaces one
/// substring scan per phrase.
pub fn characterSet(subject: []const u8) CharacterSet {
    var set = CharacterSet{};
    for (subject) |character| set.add(character);
    return set;
}

/// The character of `text` occurring in the fewest members of `set`.
///
/// A space is never chosen: it appears in most phrases and in nearly every
/// subject, so it would discriminate nothing.
pub fn rarestCharacter(comptime text: []const u8, comptime set: []const []const u8) u8 {
    @setEvalBranchQuota(1_000_000);
    var best: u8 = text[0];
    var best_score: usize = std.math.maxInt(usize);
    for (text) |character| {
        if (character == ' ') continue;
        var score: usize = 0;
        for (set) |candidate| {
            if (std.mem.indexOfScalar(u8, candidate, character) != null) score += 1;
        }
        if (score < best_score) {
            best_score = score;
            best = character;
        }
    }
    return best;
}

/// A comptime-prepared filter over a fixed phrase set.
///
/// Instantiate once per set at container scope so the table is built during
/// compilation:
///
/// ```zig
/// const markers = [_][]const u8{ "RunTitle", "LaunchPath" };
/// const marker_filter = phrase_filter.Filter(&markers);
/// ```
pub fn Filter(comptime phrases: []const []const u8) type {
    return struct {
        pub const phrase_count = phrases.len;

        /// One rare character per phrase, resolved at build time.
        pub const rare_characters: [phrases.len]u8 = blk: {
            @setEvalBranchQuota(10_000_000);
            var table: [phrases.len]u8 = undefined;
            for (phrases, 0..) |phrase, index| {
                table[index] = if (phrase.len == 0) 0 else rarestCharacter(phrase, phrases);
            }
            break :blk table;
        };

        /// Whether phrase `index` is worth a real comparison against a subject
        /// whose presence mask is `set`.
        ///
        /// A zero rare character means "not accelerated" — an empty phrase —
        /// and always survives, so a caller can never lose a match by trusting
        /// this.
        pub fn survives(set: CharacterSet, index: usize) bool {
            const rare = rare_characters[index];
            return rare == 0 or set.contains(rare);
        }

        /// The index of the first phrase that is a substring of `subject`.
        pub fn firstMatch(subject: []const u8) ?usize {
            const set = characterSet(subject);
            for (phrases, 0..) |phrase, index| {
                if (!survives(set, index)) continue;
                if (std.mem.indexOf(u8, subject, phrase) != null) return index;
            }
            return null;
        }

        /// Whether any phrase is a substring of `subject`.
        pub fn anyPresent(subject: []const u8) bool {
            return firstMatch(subject) != null;
        }

        /// The same answer without the filter. Consumers use it in a test to
        /// prove the two agree; it is not meant for production paths.
        pub fn firstMatchUnfiltered(subject: []const u8) ?usize {
            for (phrases, 0..) |phrase, index| {
                if (std.mem.indexOf(u8, subject, phrase) != null) return index;
            }
            return null;
        }

        /// Every rare character must genuinely occur in its own phrase, or the
        /// filter would reject subjects that do contain it.
        pub fn isWellFormed() bool {
            for (phrases, 0..) |phrase, index| {
                if (phrase.len == 0) continue;
                const rare = rare_characters[index];
                if (rare == ' ') return false;
                if (std.mem.indexOfScalar(u8, phrase, rare) == null) return false;
            }
            return true;
        }
    };
}

const test_phrases = [_][]const u8{
    "RunTitle",
    "LaunchPath",
    "CompleteLaunch",
    "RING BUFFER",
    "stage=",
    "assert",
};
const TestFilter = Filter(&test_phrases);

test "the filter agrees with the unfiltered search on every phrase" {
    // The soundness property. Any subject containing a phrase must survive the
    // bit test for that phrase.
    for (test_phrases, 0..) |phrase, index| {
        try std.testing.expectEqual(@as(?usize, index), TestFilter.firstMatch(phrase));
        try std.testing.expectEqual(
            TestFilter.firstMatchUnfiltered(phrase),
            TestFilter.firstMatch(phrase),
        );
    }
}

test "a phrase embedded in surrounding text is still found" {
    const line = "[xenia] i> Emulator::CompleteLaunch ENTRY path=/foo";
    try std.testing.expectEqual(TestFilter.firstMatchUnfiltered(line), TestFilter.firstMatch(line));
    try std.testing.expect(TestFilter.anyPresent(line));
}

test "ordinary text is rejected without a substring scan" {
    for ([_][]const u8{
        "",
        "NtAllocateVirtualMemory(7011FBA0, 00100000)",
        "hello world",
    }) |subject| {
        try std.testing.expectEqual(
            TestFilter.firstMatchUnfiltered(subject),
            TestFilter.firstMatch(subject),
        );
        try std.testing.expect(!TestFilter.anyPresent(subject));
    }
}

test "the rare character is chosen against the set" {
    try std.testing.expect(TestFilter.isWellFormed());
    // The property that matters is selectivity, not which of several equally
    // selective characters wins the tie. `stage=` contains both `g` and `=`,
    // and neither appears in any other phrase; picking either is correct, and
    // asserting one of them would be asserting the tie-break.
    const stage_index = 4;
    const stage_rare = TestFilter.rare_characters[stage_index];
    var sharers: usize = 0;
    for (test_phrases) |phrase| {
        if (std.mem.indexOfScalar(u8, phrase, stage_rare) != null) sharers += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), sharers);

    // A subject missing that character cannot contain the phrase, and the bit
    // test says so without scanning. The subject is a single repeated letter
    // that appears in no test phrase, so it cannot accidentally contain
    // whichever character won the tie.
    try std.testing.expect(std.mem.indexOfScalar(u8, "stage=", 'z') == null);
    var set = characterSet("zzzz");
    try std.testing.expect(!TestFilter.survives(set, stage_index));
    set = characterSet("stage=Precompile.begin");
    try std.testing.expect(TestFilter.survives(set, stage_index));
}

test "an empty phrase always survives rather than being wrongly rejected" {
    const with_empty = [_][]const u8{ "alpha", "" };
    const EmptyFilter = Filter(&with_empty);
    const set = characterSet("zzz");
    try std.testing.expect(EmptyFilter.survives(set, 1));
    try std.testing.expect(EmptyFilter.isWellFormed());
}

test "character set membership is exact" {
    const set = characterSet("abc");
    try std.testing.expect(set.contains('a'));
    try std.testing.expect(set.contains('c'));
    try std.testing.expect(!set.contains('d'));
    try std.testing.expect(!set.contains(0));
    // High bytes land in the upper words rather than aliasing the low ones.
    const high = characterSet(&[_]u8{ 0x80, 0xFF });
    try std.testing.expect(high.contains(0x80));
    try std.testing.expect(high.contains(0xFF));
    try std.testing.expect(!high.contains(0x00));
}
