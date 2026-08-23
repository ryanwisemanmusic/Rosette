//! The link-set analyzer.
//!
//! Symbols are fed in one at a time with the unit that produced them and the
//! linkage the object file recorded. Nothing here reads a file: keeping the
//! judgement separate from the parsing is what lets the interesting part be
//! tested against hand-built cases instead of against a build tree.

const std = @import("std");
const types = @import("types.zig");

pub const Audit = struct {
    allocator: std.mem.Allocator,
    /// Symbol name -> every place it was seen. Names and unit paths are owned
    /// copies: the parser's buffers do not outlive a single object file.
    symbols: std.StringHashMapUnmanaged(Record) = .{},
    /// Interned unit names, so a unit that defines 40,000 symbols stores its
    /// path once.
    units: std.StringHashMapUnmanaged(void) = .{},
    strong_definitions: usize = 0,
    weak_definitions: usize = 0,
    private_definitions: usize = 0,
    reference_count: usize = 0,
    units_seen: usize = 0,

    pub const Record = struct {
        strong_units: std.ArrayListUnmanaged([]const u8) = .empty,
        weak_units: usize = 0,
        referenced: bool = false,
        /// Archive shared by every strong definition, or empty once two
        /// different archives (or a loose object) have been seen.
        shared_archive: []const u8 = "",
        shared_archive_valid: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) Audit {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Audit) void {
        var entries = self.symbols.iterator();
        while (entries.next()) |entry| {
            entry.value_ptr.strong_units.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.symbols.deinit(self.allocator);
        var unit_names = self.units.iterator();
        while (unit_names.next()) |entry| self.allocator.free(entry.key_ptr.*);
        self.units.deinit(self.allocator);
        self.* = undefined;
    }

    /// Intern a unit path once and return the stored copy.
    pub fn internUnit(self: *Audit, unit: []const u8) ![]const u8 {
        if (self.units.getKey(unit)) |existing| return existing;
        const owned = try self.allocator.dupe(u8, unit);
        try self.units.put(self.allocator, owned, {});
        self.units_seen += 1;
        return owned;
    }

    /// Record one symbol occurrence. `unit` must already be interned.
    pub fn note(
        self: *Audit,
        unit: []const u8,
        name: []const u8,
        linkage: types.Linkage,
        archive: []const u8,
    ) !void {
        // A private or file-local definition is invisible to the linker across
        // units, so it can never take part in a collision. Counting it would
        // only inflate the totals.
        if (linkage == .private) {
            self.private_definitions += 1;
            return;
        }
        const entry = try self.symbols.getOrPut(self.allocator, name);
        if (!entry.found_existing) {
            entry.key_ptr.* = try self.allocator.dupe(u8, name);
            entry.value_ptr.* = .{};
        }
        const record = entry.value_ptr;
        switch (linkage) {
            .undefined_reference => {
                record.referenced = true;
                self.reference_count += 1;
            },
            .weak => {
                record.weak_units += 1;
                self.weak_definitions += 1;
            },
            .strong => {
                self.strong_definitions += 1;
                // The same unit listing a symbol twice is not two definitions.
                for (record.strong_units.items) |existing| {
                    if (std.mem.eql(u8, existing, unit)) return;
                }
                try record.strong_units.append(self.allocator, unit);
                if (record.strong_units.items.len == 1) {
                    record.shared_archive = archive;
                    record.shared_archive_valid = archive.len != 0;
                } else if (record.shared_archive_valid and
                    !std.mem.eql(u8, record.shared_archive, archive))
                {
                    // Definitions span more than one archive, so member order
                    // inside a single archive is no longer the deciding factor.
                    record.shared_archive_valid = false;
                    record.shared_archive = "";
                }
            },
            .private => unreachable,
        }
    }

    /// Every symbol whose resolution is not determined by the source.
    ///
    /// Vague-linkage duplicates are deliberately absent. They are the
    /// overwhelming majority of repeated symbols in any C++ link set and every
    /// one of them is correct, so reporting them would hide the few that are
    /// not.
    pub fn findings(self: *const Audit, allocator: std.mem.Allocator) ![]types.Finding {
        var collected: std.ArrayListUnmanaged(types.Finding) = .empty;
        errdefer collected.deinit(allocator);

        var entries = self.symbols.iterator();
        while (entries.next()) |entry| {
            const name = entry.key_ptr.*;
            const record = entry.value_ptr;
            const strong_count = record.strong_units.items.len;
            if (strong_count > 1) {
                const kind: types.FindingKind = if (types.isEntryPoint(name))
                    .multiple_entry_points
                else if (record.shared_archive_valid)
                    .order_dependent_selection
                else
                    .duplicate_strong_definition;
                try collected.append(allocator, .{
                    .kind = kind,
                    .severity = types.severityOf(kind),
                    .symbol = name,
                    .units = record.strong_units.items,
                    .shared_archive = if (record.shared_archive_valid) record.shared_archive else "",
                });
                continue;
            }
            if (strong_count == 1 and record.weak_units != 0) {
                try collected.append(allocator, .{
                    .kind = .strong_and_weak_definition,
                    .severity = types.severityOf(.strong_and_weak_definition),
                    .symbol = name,
                    .units = record.strong_units.items,
                });
                continue;
            }
            if (strong_count == 0 and record.weak_units == 0 and record.referenced) {
                try collected.append(allocator, .{
                    .kind = .unresolved_reference,
                    .severity = types.severityOf(.unresolved_reference),
                    .symbol = name,
                    .units = &.{},
                });
            }
        }

        const result = try collected.toOwnedSlice(allocator);
        std.mem.sort(types.Finding, result, {}, lessThan);
        return result;
    }

    /// Most severe first, then by kind and name, so a report's leading lines
    /// are the ones worth acting on and the order does not move between runs.
    fn lessThan(_: void, left: types.Finding, right: types.Finding) bool {
        const left_rank = @intFromEnum(left.severity);
        const right_rank = @intFromEnum(right.severity);
        if (left_rank != right_rank) return left_rank > right_rank;
        if (left.kind != right.kind) return @intFromEnum(left.kind) < @intFromEnum(right.kind);
        return std.mem.lessThan(u8, left.symbol, right.symbol);
    }

    pub fn countOf(self: *const Audit, allocator: std.mem.Allocator, kind: types.FindingKind) !usize {
        const all = try self.findings(allocator);
        defer allocator.free(all);
        var total: usize = 0;
        for (all) |finding| {
            if (finding.kind == kind) total += 1;
        }
        return total;
    }
};

test "vague-linkage duplicates are not collisions" {
    var audit = Audit.init(std.testing.allocator);
    defer audit.deinit();
    const a = try audit.internUnit("a.o");
    const b = try audit.internUnit("b.o");
    const c = try audit.internUnit("c.o");

    // An inline function instantiated in three translation units. The linker
    // is required to keep one. Reporting this is what drowns a real finding:
    // measured on Xenia's link set there are over a hundred thousand of them.
    try audit.note(a, "_ZN2xe6inlineEv", .weak, "");
    try audit.note(b, "_ZN2xe6inlineEv", .weak, "");
    try audit.note(c, "_ZN2xe6inlineEv", .weak, "");

    const found = try audit.findings(std.testing.allocator);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqual(@as(usize, 0), found.len);
    try std.testing.expectEqual(@as(usize, 3), audit.weak_definitions);
}

test "two strong definitions are a real collision" {
    var audit = Audit.init(std.testing.allocator);
    defer audit.deinit();
    const a = try audit.internUnit("platform_amd64.cc.o");
    const b = try audit.internUnit("platform_amd64_mac.cc.o");
    try audit.note(a, "_ZN2xe5amd6415GetFeatureFlagsEv", .strong, "libxenia-base.a");
    try audit.note(b, "_ZN2xe5amd6415GetFeatureFlagsEv", .strong, "libxenia-base.a");

    const found = try audit.findings(std.testing.allocator);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    // Both definitions live in one archive, so the winner is whichever member
    // the archive index lists first — build order, not source.
    try std.testing.expectEqual(types.FindingKind.order_dependent_selection, found[0].kind);
    try std.testing.expectEqual(types.Severity.critical, found[0].severity);
    try std.testing.expectEqualStrings("libxenia-base.a", found[0].shared_archive);
    try std.testing.expectEqual(@as(usize, 2), found[0].units.len);
}

test "definitions spread across archives are not order dependent" {
    var audit = Audit.init(std.testing.allocator);
    defer audit.deinit();
    const a = try audit.internUnit("one.o");
    const b = try audit.internUnit("two.o");
    try audit.note(a, "_shared", .strong, "liba.a");
    try audit.note(b, "_shared", .strong, "libb.a");

    const found = try audit.findings(std.testing.allocator);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqual(types.FindingKind.duplicate_strong_definition, found[0].kind);
    try std.testing.expectEqualStrings("", found[0].shared_archive);
}

test "a second entry point outranks every other finding" {
    var audit = Audit.init(std.testing.allocator);
    defer audit.deinit();
    const a = try audit.internUnit("windowed_app_main_posix.cc.o");
    const b = try audit.internUnit("test_avx_support_mac.cc.o");
    const c = try audit.internUnit("other.o");
    try audit.note(a, "_main", .strong, "libxenia-base.a");
    try audit.note(b, "_main", .strong, "libxenia-base.a");
    try audit.note(c, "_unrelated", .undefined_reference, "");

    const found = try audit.findings(std.testing.allocator);
    defer std.testing.allocator.free(found);
    try std.testing.expect(found.len >= 1);
    // Severity ordering must put the entry point first: which `main` runs is
    // not something a reader should have to scroll for.
    try std.testing.expectEqual(types.FindingKind.multiple_entry_points, found[0].kind);
    try std.testing.expectEqual(types.Severity.critical, found[0].severity);
}

test "private definitions never collide" {
    var audit = Audit.init(std.testing.allocator);
    defer audit.deinit();
    const a = try audit.internUnit("a.o");
    const b = try audit.internUnit("b.o");
    // A file-local helper of the same name in two files is ordinary C++.
    try audit.note(a, "_helper", .private, "");
    try audit.note(b, "_helper", .private, "");

    const found = try audit.findings(std.testing.allocator);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqual(@as(usize, 0), found.len);
    try std.testing.expectEqual(@as(usize, 2), audit.private_definitions);
}

test "one unit repeating a symbol is one definition" {
    var audit = Audit.init(std.testing.allocator);
    defer audit.deinit();
    const a = try audit.internUnit("a.o");
    try audit.note(a, "_once", .strong, "lib.a");
    try audit.note(a, "_once", .strong, "lib.a");

    const found = try audit.findings(std.testing.allocator);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqual(@as(usize, 0), found.len);
}

test "a reference satisfied anywhere in the set is resolved" {
    var audit = Audit.init(std.testing.allocator);
    defer audit.deinit();
    const a = try audit.internUnit("caller.o");
    const b = try audit.internUnit("callee.o");
    try audit.note(a, "_present", .undefined_reference, "");
    try audit.note(b, "_present", .strong, "lib.a");
    try audit.note(a, "_absent", .undefined_reference, "");
    // A weak definition still satisfies the reference.
    try audit.note(a, "_weakly_present", .undefined_reference, "");
    try audit.note(b, "_weakly_present", .weak, "lib.a");

    const found = try audit.findings(std.testing.allocator);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqual(types.FindingKind.unresolved_reference, found[0].kind);
    try std.testing.expectEqualStrings("_absent", found[0].symbol);
}

test "a strong definition alongside vague copies is reported quietly" {
    var audit = Audit.init(std.testing.allocator);
    defer audit.deinit();
    const a = try audit.internUnit("out_of_line.o");
    const b = try audit.internUnit("header_user.o");
    try audit.note(a, "_ZN2xe4funcEv", .strong, "lib.a");
    try audit.note(b, "_ZN2xe4funcEv", .weak, "lib.a");

    const found = try audit.findings(std.testing.allocator);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqual(types.FindingKind.strong_and_weak_definition, found[0].kind);
    try std.testing.expectEqual(types.Severity.note, found[0].severity);
}
