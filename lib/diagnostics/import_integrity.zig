//! Imports, their ABI, and whether a graphics conclusion is allowed to rest
//! on one that fell back.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run reports import-binding audit failures for the default
//! title and several audio modules. The title reaches GPU initialisation, so
//! none of them is proven to block the first frame — and an unresolved import
//! that writes a guest flag, returns a handle, or installs a callback can
//! corrupt a later completion without ever announcing itself.
//!
//! The rule is the same as everywhere else in this pass: an import that fell
//! back is recorded, and a conclusion that depends on it is refused rather
//! than qualified. "Probably fine" is not a state this ledger has.
//!
//! The ABI half matters separately. A PowerPC export called with the wrong
//! argument registers, the wrong stack alignment, or a 64-bit structure laid
//! out differently returns a plausible value from a call that did the wrong
//! thing, and nothing downstream can tell.

const std = @import("std");

/// How an import was resolved.
pub const Binding = enum(u8) {
    /// Bound to the real implementation.
    bound = 0,
    /// Bound to a stub that returns a plausible value.
    stub = 1,
    /// Bound to a generic fallback that does nothing.
    fallback = 2,
    /// Not bound. A call reaches nothing.
    unresolved = 3,

    pub fn label(self: Binding) []const u8 {
        return switch (self) {
            .bound => "bound",
            .stub => "stub",
            .fallback => "fallback",
            .unresolved => "UNRESOLVED",
        };
    }

    pub fn describe(self: Binding) []const u8 {
        return switch (self) {
            .bound => "resolved to the real implementation",
            .stub => "resolved to a stub. It returns a plausible value and performs no side effect, which matters exactly when the title reads the value or waits on the effect",
            .fallback => "resolved to a generic fallback. A call reaches something that does nothing and returns, which is indistinguishable from success at the call site",
            .unresolved => "not bound. A call reaches nothing, and what happens next depends on the loader rather than on the title",
        };
    }

    /// Whether a conclusion may rest on a call through this binding.
    pub fn supportsConclusion(self: Binding) bool {
        return self == .bound;
    }
};

/// What an ABI probe found.
pub const AbiCheck = enum(u8) {
    /// Not probed.
    unchecked = 0,
    /// Arguments, alignment, return value and structure layout all matched.
    matched = 1,
    /// An argument arrived in the wrong place.
    argument_mismatch = 2,
    /// The stack was not aligned as the ABI requires.
    stack_misaligned = 3,
    /// The return value came back in the wrong register or width.
    return_mismatch = 4,
    /// A structure the two sides pass had different layouts.
    layout_mismatch = 5,

    pub fn label(self: AbiCheck) []const u8 {
        return switch (self) {
            .unchecked => "unchecked",
            .matched => "matched",
            .argument_mismatch => "ARGUMENT-MISMATCH",
            .stack_misaligned => "STACK-MISALIGNED",
            .return_mismatch => "RETURN-MISMATCH",
            .layout_mismatch => "LAYOUT-MISMATCH",
        };
    }

    pub fn isDefect(self: AbiCheck) bool {
        return switch (self) {
            .argument_mismatch, .stack_misaligned, .return_mismatch, .layout_mismatch => true,
            .unchecked, .matched => false,
        };
    }

    pub fn proven(self: AbiCheck) bool {
        return self == .matched;
    }
};

pub const max_imports: usize = 64;

/// One imported symbol.
pub const Import = struct {
    module_id: u32 = 0,
    ordinal: u32 = 0,
    /// The address the slot was bound to.
    target: u32 = 0,
    /// The thunk the loader wrote, when there is one.
    thunk: u32 = 0,
    binding: Binding = .unresolved,
    abi: AbiCheck = .unchecked,
    calls: u64 = 0,
    /// Set when this import sits between the producer and a frame.
    on_graphics_chain: bool = false,
    /// Whether this import writes a guest flag, returns a handle, or installs
    /// a callback — the three ways a fallback corrupts a later completion
    /// without announcing itself.
    has_guest_side_effect: bool = false,

    /// Whether a graphics conclusion may rest on this import.
    pub fn safeForGraphicsConclusion(self: Import) bool {
        if (!self.on_graphics_chain) return true;
        if (!self.binding.supportsConclusion()) return false;
        return !self.has_guest_side_effect or self.abi.proven();
    }
};

pub const Summary = struct {
    imports: usize = 0,
    dropped: u64 = 0,
    bound: usize = 0,
    stubbed: usize = 0,
    fallbacks: usize = 0,
    unresolved: usize = 0,
    abi_defects: usize = 0,
    abi_unchecked: usize = 0,
    on_chain: usize = 0,
    unsafe_on_chain: usize = 0,

    /// The audit's G0 criterion for imports: nothing on the graphics chain
    /// fell back.
    pub fn chainClean(self: Summary) bool {
        return self.unsafe_on_chain == 0;
    }
};

pub const Verdict = enum(u8) {
    unobserved,
    /// Every import on the chain is bound and, where it has a side effect,
    /// ABI-proven.
    chain_clean,
    /// Something on the chain fell back or is unresolved.
    chain_compromised,
    abi_unproven,
    coverage_incomplete,
    /// An ABI probe found a mismatch.
    abi_mismatch,
    /// Imports off the chain fell back. Real and not blocking.
    peripheral_fallbacks,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .chain_clean => "chain-clean",
            .chain_compromised => "CHAIN-COMPROMISED",
            .abi_unproven => "ABI-UNPROVEN",
            .coverage_incomplete => "COVERAGE-INCOMPLETE",
            .abi_mismatch => "ABI-MISMATCH",
            .peripheral_fallbacks => "peripheral-fallbacks",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "no import has been audited. Nothing here says whether a graphics conclusion is safe",
            .chain_clean => "the declared import inventory is fully audited: bindings and required ABI probes passed",
            .abi_unproven => "a graphics import is bound but its calling convention and side effects have not been checked. A valid thunk proves routing, not ABI correctness",
            .coverage_incomplete => "the retained import subset contains no proven defect, but the graphics dependency inventory is incomplete or records were lost. This cannot certify the whole import chain",
            .chain_compromised => "an import on the path between a command and a frame is unresolved or bound to a fallback. It may write a guest flag, return a handle or install a callback, and the call site cannot tell — no graphics conclusion may rest on this run until it is fixed or proven irrelevant",
            .abi_mismatch => "a probe found an argument, alignment, return or layout mismatch. The call returns a plausible value from a call that did the wrong thing, and nothing downstream can detect it",
            .peripheral_fallbacks => "imports off the graphics chain fell back. Real, worth fixing, and not blocking a frame",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .chain_compromised or self == .abi_mismatch;
    }

    pub fn permitsGraphicsConclusion(self: Verdict) bool {
        return self == .chain_clean or self == .peripheral_fallbacks;
    }
};

pub const Ledger = struct {
    imports: [max_imports]Import = [_]Import{.{}} ** max_imports,
    count: usize = 0,
    dropped: u64 = 0,
    /// Only an enumerated dependency inventory can establish this. A few
    /// video thunk probes cannot certify every import used by Xenia.
    coverage_complete: bool = false,

    fn find(self: *Ledger, module_id: u32, ordinal: u32) ?*Import {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const entry = &self.imports[index];
            if (entry.module_id == module_id and entry.ordinal == ordinal) return entry;
        }
        return null;
    }

    pub fn record(self: *Ledger, entry: Import) ?*Import {
        if (self.find(entry.module_id, entry.ordinal)) |existing| {
            existing.* = entry;
            return existing;
        }
        if (self.count >= max_imports) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.imports[self.count];
        self.count += 1;
        slot.* = entry;
        return slot;
    }

    pub fn noteCall(self: *Ledger, module_id: u32, ordinal: u32) void {
        if (self.find(module_id, ordinal)) |entry| entry.calls +|= 1;
    }

    pub fn retained(self: *const Ledger) []const Import {
        return self.imports[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{ .imports = self.count, .dropped = self.dropped };
        for (self.retained()) |entry| {
            switch (entry.binding) {
                .bound => out.bound += 1,
                .stub => out.stubbed += 1,
                .fallback => out.fallbacks += 1,
                .unresolved => out.unresolved += 1,
            }
            if (entry.abi.isDefect()) out.abi_defects += 1;
            if (entry.abi == .unchecked) out.abi_unchecked += 1;
            if (entry.on_graphics_chain) {
                out.on_chain += 1;
                if (!entry.safeForGraphicsConclusion()) out.unsafe_on_chain += 1;
            }
        }
        return out;
    }

    pub fn verdict(self: *const Ledger) Verdict {
        if (self.count == 0) return .unobserved;
        const totals = self.summary();
        if (totals.abi_defects != 0) return .abi_mismatch;
        for (self.retained()) |entry| {
            if (entry.on_graphics_chain and !entry.binding.supportsConclusion()) return .chain_compromised;
        }
        if (!totals.chainClean()) return .abi_unproven;
        if (!self.coverage_complete or self.dropped != 0) return .coverage_incomplete;
        if (totals.fallbacks != 0 or totals.unresolved != 0 or totals.stubbed != 0) {
            return .peripheral_fallbacks;
        }
        return .chain_clean;
    }

    /// Every import on the chain that a conclusion cannot rest on.
    pub fn firstUnsafe(self: *const Ledger) ?Import {
        for (self.retained()) |entry| {
            if (!entry.safeForGraphicsConclusion()) return entry;
        }
        return null;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.imports;
        hash = hash *% 31 +% totals.unsafe_on_chain;
        hash = hash *% 31 +% totals.abi_defects;
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

fn boundImport(module_id: u32, ordinal: u32) Import {
    return .{
        .module_id = module_id,
        .ordinal = ordinal,
        .target = 0x8270_E044,
        .thunk = 0x8270_E044,
        .binding = .bound,
        .abi = .matched,
    };
}

test "a fallback off the graphics chain is real and not blocking" {
    var ledger = Ledger{ .coverage_complete = true };
    _ = ledger.record(.{ .module_id = 2, .ordinal = 0x40, .binding = .fallback, .abi = .unchecked }).?;
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.peripheral_fallbacks, verdict);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expect(verdict.permitsGraphicsConclusion());
    try std.testing.expect(ledger.summary().chainClean());
}

// The audit's rule: no graphics conclusion may rest on an unresolved import
// that could write a guest flag, return a handle or install a callback.
test "a fallback on the chain refuses every graphics conclusion" {
    var ledger = Ledger{ .coverage_complete = true };
    _ = ledger.record(.{
        .module_id = 1,
        .ordinal = 0x1D5,
        .binding = .fallback,
        .on_graphics_chain = true,
        .has_guest_side_effect = true,
    }).?;
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.chain_compromised, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expect(!verdict.permitsGraphicsConclusion());
    try std.testing.expectEqual(@as(u32, 0x1D5), ledger.firstUnsafe().?.ordinal);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "cannot tell") != null);
}

test "a bound import with a side effect needs a proven ABI" {
    var ledger = Ledger{ .coverage_complete = true };
    const entry = ledger.record(.{
        .module_id = 1,
        .ordinal = 0x1C2,
        .binding = .bound,
        .abi = .unchecked,
        .on_graphics_chain = true,
        .has_guest_side_effect = true,
    }).?;
    try std.testing.expect(!entry.safeForGraphicsConclusion());
    try std.testing.expectEqual(Verdict.abi_unproven, ledger.verdict());

    entry.abi = .matched;
    try std.testing.expect(entry.safeForGraphicsConclusion());
    try std.testing.expectEqual(Verdict.chain_clean, ledger.verdict());
}

test "a bound import with no side effect is safe without an ABI probe" {
    var ledger = Ledger{ .coverage_complete = true };
    const entry = ledger.record(.{
        .module_id = 1,
        .ordinal = 0x1C3,
        .binding = .bound,
        .abi = .unchecked,
        .on_graphics_chain = true,
        .has_guest_side_effect = false,
    }).?;
    try std.testing.expect(entry.safeForGraphicsConclusion());
    try std.testing.expectEqual(Verdict.chain_clean, ledger.verdict());
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().abi_unchecked);
}

test "an ABI mismatch outranks everything else the ledger says" {
    var ledger = Ledger{ .coverage_complete = true };
    _ = ledger.record(boundImport(1, 0x1C2)).?;
    try std.testing.expectEqual(Verdict.chain_clean, ledger.verdict());
    const entry = ledger.record(.{ .module_id = 1, .ordinal = 0x1C3, .binding = .bound, .abi = .layout_mismatch }).?;
    try std.testing.expect(entry.abi.isDefect());
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.abi_mismatch, verdict);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "nothing downstream can detect it") != null);
}

test "re-recording an import replaces it rather than duplicating it" {
    var ledger = Ledger{ .coverage_complete = true };
    _ = ledger.record(.{ .module_id = 1, .ordinal = 0x1D5, .binding = .unresolved }).?;
    ledger.noteCall(1, 0x1D5);
    try std.testing.expectEqual(@as(usize, 1), ledger.retained().len);
    _ = ledger.record(boundImport(1, 0x1D5)).?;
    try std.testing.expectEqual(@as(usize, 1), ledger.retained().len);
    try std.testing.expectEqual(Binding.bound, ledger.retained()[0].binding);
}

test "nothing audited supports no conclusion in either direction" {
    const ledger = Ledger{};
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.unobserved, verdict);
    try std.testing.expect(!verdict.permitsGraphicsConclusion());
    try std.testing.expect(!verdict.isDefect());
}

test "the ledger is bounded and every binding and check is named" {
    var ledger = Ledger{ .coverage_complete = true };
    var index: u32 = 0;
    while (index < max_imports + 3) : (index += 1) {
        _ = ledger.record(boundImport(1, index));
    }
    try std.testing.expectEqual(max_imports, ledger.retained().len);
    try std.testing.expectEqual(@as(u64, 3), ledger.dropped);

    inline for (@typeInfo(Binding).@"enum".fields) |field| {
        const which: Binding = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
    inline for (@typeInfo(AbiCheck).@"enum".fields) |field| {
        const which: AbiCheck = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    try std.testing.expect(Binding.bound.supportsConclusion());
    try std.testing.expect(!Binding.stub.supportsConclusion());
}

test "a healthy subset of imports cannot certify the Xenia dependency chain" {
    var ledger = Ledger{};
    _ = ledger.record(boundImport(1, 0x1C2));
    try std.testing.expectEqual(Verdict.coverage_incomplete, ledger.verdict());
    try std.testing.expect(!ledger.verdict().permitsGraphicsConclusion());
    ledger.coverage_complete = true;
    try std.testing.expectEqual(Verdict.chain_clean, ledger.verdict());
    ledger.dropped = 1;
    try std.testing.expectEqual(Verdict.coverage_incomplete, ledger.verdict());
}
