//! What one Windows export is, beyond its name.
//!
//! ## Why a name list was not enough
//!
//! Every `pkg/dll/win32/<dll>` package held a list of strings. A string says
//! a name exists and nothing else - not how many arguments the call takes,
//! not what its return value means, not whether Rosette serves it or refuses
//! it. Three consequences followed, and all three showed up in the
//! 2026-09-12 run:
//!
//! * The return convention had to be *guessed* from the spelling. The guess
//!   is right often enough to choose a refusal value, and wrong often enough
//!   that it cannot be used to judge one: under it `WaitForSingleObject`
//!   returning `WAIT_OBJECT_0` and `vkCreateInstance` returning `VK_SUCCESS`
//!   are both a zero that looks like failure. So two thirds of the imports in
//!   a run were classified `unjudged`, and the refusal report could only
//!   speak about the third whose convention came from an explicit rule.
//!
//! * A zero return could not be read. `VirtualProtect` returned FALSE on
//!   every call for the life of the project - a real defect - and sat
//!   indistinguishable from `IsDebuggerPresent` answering FALSE, which is
//!   correct.
//!
//! * Nothing recorded whether Rosette actually *does* the thing. "This name
//!   is known" and "this name works" were the same fact.
//!
//! A declared export fixes all three, and it does so per name, which is the
//! only granularity at which any of them is true.
//!
//! ## What a declaration is
//!
//! A statement about the Windows ABI, plus a statement about Rosette. The
//! first half - arity, convention, whether zero is an answer - is a property
//! of the platform and does not change. The second half - `behaviour` - is a
//! property of this build and goes stale if nobody maintains it, which is why
//! `not_implemented` is the default rather than something a package has to
//! remember to say.

const std = @import("std");
const return_contract = @import("dll_win32_return_contract");

pub const Convention = return_contract.ReturnConvention;

/// What Rosette does when the guest calls this export.
pub const Behaviour = enum {
    /// Rosette carries the call out for real, against the host.
    served,
    /// Rosette answers from its own model without touching the host. A
    /// synthesised handle, a counter it keeps, a value it computes. The guest
    /// cannot tell the difference and there is nothing missing.
    modelled,
    /// Rosette declines on purpose and the refusal is the correct answer -
    /// the capability does not exist on this host and the guest has a
    /// documented path for its absence.
    refused_by_policy,
    /// Rosette has no handler. The ABI contract supplies the refusal so the
    /// guest is told the call did not happen, rather than being told it
    /// succeeded and left to read an output nobody wrote.
    not_implemented,

    pub fn label(self: Behaviour) []const u8 {
        return switch (self) {
            .served => "served",
            .modelled => "modelled",
            .refused_by_policy => "refused-by-policy",
            .not_implemented => "not-implemented",
        };
    }

    /// Whether the guest gets what it asked for.
    pub fn satisfiesTheGuest(self: Behaviour) bool {
        return self == .served or self == .modelled;
    }

    /// Whether this is work Rosette owes. A deliberate refusal is not.
    pub fn isOutstandingWork(self: Behaviour) bool {
        return self == .not_implemented;
    }
};

/// Microsoft x64 passes the first four integer arguments in registers and the
/// rest on the stack. A report that wants to show a call's operands needs to
/// know how many there are, and a contract that wants to validate a pointer
/// argument needs to know which position it is in.
pub const max_declared_arity: u8 = 15;

pub const Export = struct {
    name: []const u8,
    /// Integer arguments the call takes, as the Microsoft x64 ABI counts
    /// them. `variadic` marks the printf-shaped calls where the count is
    /// decided by a format string.
    ///
    /// Optional, and null by default, because a wrong arity is worse than no
    /// arity: a report that prints four operands for a two-argument call
    /// shows the caller two words of its own stack and labels them
    /// arguments. Null says nobody has checked this one.
    arity: ?u8 = null,
    variadic: bool = false,
    convention: Convention,
    behaviour: Behaviour = .not_implemented,
    /// Whether zero is a *meaningful* answer for this call rather than the
    /// absence of one.
    ///
    /// `IsDebuggerPresent` returning FALSE means no debugger; `memcmp`
    /// returning zero means equal; `FindNextFileW` returning FALSE means the
    /// enumeration finished. None of those is a refusal, and treating them as
    /// one buries the ones that are under the most common calls in the run.
    zero_is_an_answer: bool = false,
    /// Whether a person has looked this name up.
    ///
    /// False by default and deliberately so. A row nobody has checked still
    /// carries a convention - something has to be returned - but that
    /// convention came from the spelling, and a report that judged it would
    /// be repeating the mistake the declaration exists to fix. `isDecisive`
    /// refuses an unreviewed row for exactly that reason, and the count of
    /// reviewed rows is the number that says how far this work has got.
    reviewed: bool = false,
    /// One clause on what the guest expects, where that is not obvious from
    /// the name. Deliberately optional: six hundred rows of restated names
    /// would be noise, and the rows that need a sentence are the ones a
    /// reader stops at.
    note: []const u8 = "",

    /// Whether a value this export returned means the call did not happen.
    ///
    /// The per-name answer the heuristic could not give. An export that
    /// declares `zero_is_an_answer` is never judged a refusal on a zero,
    /// whatever its convention says.
    pub fn valueIsRefusal(self: Export, value: u64) bool {
        if (self.zero_is_an_answer and (value & 0xFFFF_FFFF) == 0) return false;
        return return_contract.valueIsRefusal(self.convention, value);
    }

    /// Whether a value under this export can be judged at all.
    ///
    /// True for a reviewed export whose convention carries a failure value:
    /// the convention came from a person who looked the function up, not from
    /// its spelling. That is the whole point of declaring it, and it is what
    /// moves an import out of the `unjudged` bucket.
    pub fn isDecisive(self: Export) bool {
        if (!self.reviewed) return false;
        return switch (self.convention) {
            .void_call => false,
            // A count where zero is ordinary carries no failure value at all.
            .zero_count => !self.zero_is_an_answer and false,
            else => true,
        };
    }
};

/// One DLL's declared surface.
pub const Surface = struct {
    dll_name: []const u8,
    stem: []const u8,
    exports: []const Export,

    pub fn find(self: Surface, name: []const u8) ?Export {
        for (self.exports) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }

    pub fn count(self: Surface) usize {
        return self.exports.len;
    }

    pub fn reviewedCount(self: Surface) usize {
        var total: usize = 0;
        for (self.exports) |entry| {
            if (entry.reviewed) total += 1;
        }
        return total;
    }

    pub fn countWith(self: Surface, behaviour: Behaviour) usize {
        var total: usize = 0;
        for (self.exports) |entry| {
            if (entry.behaviour == behaviour) total += 1;
        }
        return total;
    }

    /// Exports the guest gets a real answer from, as a fraction in percent.
    /// The number a reader wants when asking how far along a library is.
    pub fn servedPercent(self: Surface) u32 {
        if (self.exports.len == 0) return 0;
        var satisfied: usize = 0;
        for (self.exports) |entry| {
            if (entry.behaviour.satisfiesTheGuest()) satisfied += 1;
        }
        return @intCast(satisfied * 100 / self.exports.len);
    }
};

/// Whether a name appears more than once in a surface.
///
/// A duplicate is not harmless: `find` returns the first, so a second row
/// with a different convention would be dead and its author would not know.
pub fn hasDuplicate(exports: []const Export) bool {
    for (exports, 0..) |entry, index| {
        for (exports[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.name, entry.name)) return true;
        }
    }
    return false;
}

test "a declared export judges its own return value" {
    const protect = Export{
        .name = "VirtualProtect",
        .arity = 4,
        .convention = .bool32,
        .behaviour = .modelled,
        .reviewed = true,
    };
    // FALSE from `VirtualProtect` is a failure, and the declaration says so
    // where the spelling could not. This exact call returned FALSE on every
    // invocation for the life of the project.
    try std.testing.expect(protect.valueIsRefusal(0));
    try std.testing.expect(!protect.valueIsRefusal(1));
    try std.testing.expect(protect.isDecisive());

    const debugger = Export{
        .name = "IsDebuggerPresent",
        .arity = 0,
        .convention = .bool32,
        .behaviour = .modelled,
        .zero_is_an_answer = true,
    };
    // FALSE here means "no debugger", which is the answer, not a refusal.
    try std.testing.expect(!debugger.valueIsRefusal(0));
    try std.testing.expect(!debugger.valueIsRefusal(1));
}

test "the two zeroes that made the heuristic unusable" {
    // Under the inferred conventions these were both refusals. Declared, they
    // are both success, and every other import in the run stops being buried
    // under them.
    const wait = Export{ .name = "WaitForSingleObject", .arity = 2, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .note = "WAIT_OBJECT_0 is zero; WAIT_TIMEOUT is 258 and WAIT_FAILED is 0xFFFFFFFF" };
    try std.testing.expect(!wait.valueIsRefusal(0));
    const create = Export{ .name = "vkCreateInstance", .arity = 3, .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .note = "VkResult: VK_SUCCESS is zero and negative values are errors" };
    try std.testing.expect(!create.valueIsRefusal(0));
}

test "behaviour separates what is missing from what is declined" {
    try std.testing.expect(Behaviour.served.satisfiesTheGuest());
    try std.testing.expect(Behaviour.modelled.satisfiesTheGuest());
    try std.testing.expect(!Behaviour.refused_by_policy.satisfiesTheGuest());
    try std.testing.expect(!Behaviour.not_implemented.satisfiesTheGuest());

    // Only one of the two refusals is work Rosette owes. A report that
    // counted both would put "there is no Direct3D 12 on macOS" on a to-do
    // list next to a function nobody has written yet.
    try std.testing.expect(Behaviour.not_implemented.isOutstandingWork());
    try std.testing.expect(!Behaviour.refused_by_policy.isOutstandingWork());
}

test "a surface reports how far along it is, and refuses a duplicate name" {
    const exports = [_]Export{
        .{ .name = "A", .convention = .bool32, .behaviour = .served },
        .{ .name = "B", .convention = .bool32, .behaviour = .modelled },
        .{ .name = "C", .convention = .bool32, .behaviour = .not_implemented },
        .{ .name = "D", .convention = .bool32, .behaviour = .refused_by_policy },
    };
    const surface = Surface{ .dll_name = "test.dll", .stem = "test", .exports = &exports };
    try std.testing.expectEqual(@as(usize, 4), surface.count());
    try std.testing.expectEqual(@as(u32, 50), surface.servedPercent());
    try std.testing.expectEqual(@as(usize, 1), surface.countWith(.not_implemented));
    try std.testing.expectEqualStrings("B", surface.find("B").?.name);
    try std.testing.expectEqual(@as(?Export, null), surface.find("Z"));
    try std.testing.expect(!hasDuplicate(&exports));

    // `find` returns the first match, so a second row with the same name is
    // dead code its author would never notice.
    const duplicated = [_]Export{
        .{ .name = "A", .convention = .bool32 },
        .{ .name = "A", .convention = .hresult },
    };
    try std.testing.expect(hasDuplicate(&duplicated));

    const empty = Surface{ .dll_name = "e.dll", .stem = "e", .exports = &[_]Export{} };
    try std.testing.expectEqual(@as(u32, 0), empty.servedPercent());
}

test "an undeclared arity is null, never zero" {
    // Zero is a real answer - `IsDebuggerPresent` takes no arguments - so a
    // default of zero would make "takes nothing" and "nobody checked"
    // the same statement, and a report would show a no-argument call for
    // every name whose arity was never filled in.
    const unchecked = Export{ .name = "SomethingNobodyLookedUp", .convention = .bool32 };
    try std.testing.expectEqual(@as(?u8, null), unchecked.arity);
    const nullary = Export{ .name = "IsDebuggerPresent", .arity = 0, .convention = .bool32, .zero_is_an_answer = true };
    try std.testing.expectEqual(@as(?u8, 0), nullary.arity);
    // And a declared arity stays inside what the ABI can express.
    try std.testing.expect(nullary.arity.? <= max_declared_arity);
}

test "an unreviewed row is never judged, however plausible its convention" {
    // The whole point of declaring an export is that a person looked it up.
    // A row that carries a convention nobody checked is exactly the guess the
    // declaration replaces, and judging it would repeat the mistake.
    const guessed = Export{ .name = "SomeUncheckedName", .convention = .hresult };
    try std.testing.expect(!guessed.reviewed);
    try std.testing.expect(!guessed.isDecisive());
    // It still classifies a value when asked directly - something has to be
    // returned - it simply may not be used to accuse anyone.
    try std.testing.expect(guessed.valueIsRefusal(0x8000_4002));

    const checked = Export{ .name = "SomeUncheckedName", .convention = .hresult, .reviewed = true };
    try std.testing.expect(checked.isDecisive());
}

test "a void call and a plain count carry no failure value" {
    const free = Export{ .name = "CoTaskMemFree", .arity = 1, .convention = .void_call, .behaviour = .modelled, .reviewed = true };
    try std.testing.expect(!free.isDecisive());
    try std.testing.expect(!free.valueIsRefusal(0));
    const length = Export{ .name = "lstrlenW", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true };
    try std.testing.expect(!length.isDecisive());
}
