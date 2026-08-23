//! Types for the link-set audit.
//!
//! The audit answers one question: given every translation unit that actually
//! reaches the linker, which symbol resolutions are decided by something other
//! than intent?  Those are the defects that produce no compiler diagnostic and
//! no linker error, and then fail at runtime.
//!
//! The unit of analysis is deliberately the *link set* — the objects and
//! archive members named by the final link command — and never a directory
//! walk. A build tree holds objects that are compiled but never linked, and
//! auditing those produces findings about code that does not exist in the
//! program. Measured on Xenia's own tree, a directory walk reports tens of
//! thousands of collisions that the link set does not contain at all.

/// How the linker sees one definition.
///
/// Separating `weak` from `strong` is the whole difficulty of this audit. C++
/// emits vague-linkage copies of inline functions, template instantiations,
/// implicit destructors and static guard variables into every translation unit
/// that uses them, and the linker is *required* to discard all but one. Those
/// duplicates are correct and enormously numerous. Treating them as collisions
/// buries the handful of real ones.
pub const Linkage = enum(u8) {
    /// Referenced here, defined elsewhere.
    undefined_reference,
    /// External and not weak. Two of these in one link set is a real
    /// collision: the linker picks one and the other silently disappears.
    strong,
    /// Vague linkage. Duplicates are expected and legal.
    weak,
    /// Private external or file-local. Not visible across units, so it can
    /// never collide and is not part of the audit.
    private,

    pub fn label(self: Linkage) []const u8 {
        return switch (self) {
            .undefined_reference => "undefined",
            .strong => "strong",
            .weak => "weak",
            .private => "private",
        };
    }

    /// Only definitions the linker resolves across units participate.
    pub fn isDefinition(self: Linkage) bool {
        return self == .strong or self == .weak;
    }
};

pub const FindingKind = enum(u8) {
    /// The same strong symbol is defined in more than one unit. The linker
    /// resolves it to exactly one of them and discards the rest.
    duplicate_strong_definition,
    /// Duplicate strong definitions that all live inside a single archive.
    /// Worse than the general case: the winner is chosen by member order in
    /// the archive index, which follows build order rather than intent, so the
    /// resolution can change between rebuilds without any source change.
    order_dependent_selection,
    /// More than one unit defines a program entry point.
    multiple_entry_points,
    /// A symbol is defined strongly in one unit and with vague linkage in
    /// others. Legal, but it means one unit disagrees with the rest about
    /// whether the definition is shared, which is a common shape for an
    /// inline function that drifted out of sync with an out-of-line copy.
    strong_and_weak_definition,
    /// Referenced by the link set and defined nowhere in it. Expected for
    /// system libraries and frameworks; a finding only for symbols the caller
    /// says should have been satisfied internally.
    unresolved_reference,

    pub fn label(self: FindingKind) []const u8 {
        return switch (self) {
            .duplicate_strong_definition => "DUPLICATE_STRONG_DEFINITION",
            .order_dependent_selection => "ORDER_DEPENDENT_SELECTION",
            .multiple_entry_points => "MULTIPLE_ENTRY_POINTS",
            .strong_and_weak_definition => "STRONG_AND_WEAK_DEFINITION",
            .unresolved_reference => "UNRESOLVED_REFERENCE",
        };
    }
};

pub const Severity = enum(u8) {
    note,
    warning,
    /// Something the program's behaviour depends on is not determined by the
    /// source. A run may still work; whether it works is not a property of the
    /// code.
    critical,

    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .note => "NOTE",
            .warning => "WARNING",
            .critical => "CRITICAL",
        };
    }
};

pub fn severityOf(kind: FindingKind) Severity {
    return switch (kind) {
        // Two entry points means the program's start is chosen by link order.
        .multiple_entry_points => .critical,
        // Same, restricted to one archive, and additionally unstable across
        // rebuilds.
        .order_dependent_selection => .critical,
        .duplicate_strong_definition => .warning,
        .strong_and_weak_definition => .note,
        .unresolved_reference => .note,
    };
}

/// One symbol's resolution across the whole link set.
pub const Finding = struct {
    kind: FindingKind,
    severity: Severity,
    symbol: []const u8,
    /// Units that define (or reference, for an unresolved finding) the symbol.
    /// Borrowed from the audit's own storage.
    units: []const []const u8,
    /// Archive every definition came from, when they share one. Empty when the
    /// definitions are spread across several archives or loose objects.
    shared_archive: []const u8 = "",
};

/// Names that start a program. A link set containing more than one of these
/// has more than one candidate entry point.
pub fn isEntryPoint(symbol: []const u8) bool {
    return eql(symbol, "_main") or eql(symbol, "main");
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (left != right) return false;
    }
    return true;
}
