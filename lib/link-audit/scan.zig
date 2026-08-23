//! Feed a link set into the audit.
//!
//! The caller supplies the set — the objects and archives the final link
//! command actually names. This module deliberately has no directory walk: a
//! build tree contains objects that are compiled and never linked, and
//! auditing those reports collisions in code the program does not contain.

const std = @import("std");
const types = @import("types.zig");
const audit_mod = @import("audit.zig");
const object = @import("object.zig");

pub const Scanner = struct {
    allocator: std.mem.Allocator,
    audit: audit_mod.Audit,
    objects_read: usize = 0,
    archives_read: usize = 0,
    members_read: usize = 0,
    /// Inputs that were not 64-bit little-endian Mach-O. An LTO build emits
    /// LLVM bitcode here, and an audit that silently reported nothing would be
    /// indistinguishable from a clean one, so the count is part of the result.
    skipped_inputs: usize = 0,
    unreadable_inputs: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Scanner {
        return .{ .allocator = allocator, .audit = audit_mod.Audit.init(allocator) };
    }

    pub fn deinit(self: *Scanner) void {
        self.audit.deinit();
        self.* = undefined;
    }

    /// Ingest one already-loaded input, which may be an object or an archive.
    pub fn addBuffer(self: *Scanner, path: []const u8, data: []const u8) !void {
        if (object.ArchiveIterator.init(data)) |start| {
            var iterator = start;
            self.archives_read += 1;
            while (iterator.next()) |member| {
                // Name members by archive and member together: two archives
                // routinely contain a `filesystem.cc.o`, and a report that
                // cannot tell them apart is not actionable.
                var name_buffer: std.ArrayListUnmanaged(u8) = .empty;
                defer name_buffer.deinit(self.allocator);
                try name_buffer.appendSlice(self.allocator, path);
                try name_buffer.append(self.allocator, '(');
                try name_buffer.appendSlice(self.allocator, member.name);
                try name_buffer.append(self.allocator, ')');
                try self.ingest(name_buffer.items, path, member.data);
                self.members_read += 1;
            }
            return;
        }
        try self.ingest(path, "", data);
        self.objects_read += 1;
    }

    fn ingest(self: *Scanner, unit: []const u8, archive: []const u8, data: []const u8) !void {
        var symbols: std.ArrayListUnmanaged(object.Symbol) = .empty;
        defer symbols.deinit(self.allocator);
        const recognized = try object.readObjectSymbols(self.allocator, data, &symbols);
        if (!recognized) {
            self.skipped_inputs += 1;
            return;
        }
        if (symbols.items.len == 0) return;
        const interned = try self.audit.internUnit(unit);
        for (symbols.items) |symbol| {
            try self.audit.note(interned, symbol.name, symbol.linkage, archive);
        }
    }

    /// Called by the driver when an input could not be read at all, so a
    /// missing archive cannot masquerade as a clean audit.
    pub fn noteUnreadable(self: *Scanner) void {
        self.unreadable_inputs += 1;
    }

    pub fn findings(self: *const Scanner, allocator: std.mem.Allocator) ![]types.Finding {
        return self.audit.findings(allocator);
    }

    /// A single pass/fail the ready compiler can consume as compile evidence.
    ///
    /// Only findings whose resolution is genuinely undetermined fail the
    /// verdict. Notes are reported and do not block: an audit that fails a
    /// build over a hundred thousand legal vague-linkage copies would be
    /// switched off within a day, and a gate that is switched off proves
    /// nothing.
    pub fn verdict(self: *const Scanner, allocator: std.mem.Allocator) !Verdict {
        const all = try self.findings(allocator);
        defer allocator.free(all);
        var result: Verdict = .{ .units = self.audit.units_seen };
        for (all) |finding| {
            switch (finding.severity) {
                .critical => result.critical += 1,
                .warning => result.warnings += 1,
                .note => result.notes += 1,
            }
        }
        result.passed = result.critical == 0;
        return result;
    }
};

pub const Verdict = struct {
    passed: bool = true,
    critical: usize = 0,
    warnings: usize = 0,
    notes: usize = 0,
    units: usize = 0,

    pub fn detail(self: Verdict) []const u8 {
        if (self.critical != 0) {
            return "the link set contains a symbol whose resolution is decided by link order rather than by the source";
        }
        if (self.warnings != 0) {
            return "the link set has duplicate strong definitions; one definition wins and the others are discarded";
        }
        return "every strong symbol in the link set resolves to exactly one definition";
    }
};

test "a clean link set passes and a duplicated entry point does not" {
    var scanner = Scanner.init(std.testing.allocator);
    defer scanner.deinit();
    const a = try scanner.audit.internUnit("a.o");
    try scanner.audit.note(a, "_main", .strong, "lib.a");
    {
        const clean = try scanner.verdict(std.testing.allocator);
        try std.testing.expect(clean.passed);
        try std.testing.expectEqual(@as(usize, 0), clean.critical);
    }

    const b = try scanner.audit.internUnit("b.o");
    try scanner.audit.note(b, "_main", .strong, "lib.a");
    const broken = try scanner.verdict(std.testing.allocator);
    try std.testing.expect(!broken.passed);
    try std.testing.expectEqual(@as(usize, 1), broken.critical);
    try std.testing.expect(std.mem.indexOf(u8, broken.detail(), "link order") != null);
}

test "notes and warnings are reported without failing the verdict" {
    var scanner = Scanner.init(std.testing.allocator);
    defer scanner.deinit();
    const a = try scanner.audit.internUnit("a.o");
    const b = try scanner.audit.internUnit("b.o");
    // A duplicate spread across two archives: a warning, not a hard failure.
    try scanner.audit.note(a, "_spread", .strong, "liba.a");
    try scanner.audit.note(b, "_spread", .strong, "libb.a");
    try scanner.audit.note(a, "_missing", .undefined_reference, "");

    const result = try scanner.verdict(std.testing.allocator);
    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(usize, 1), result.warnings);
    try std.testing.expectEqual(@as(usize, 1), result.notes);
}

test "an unrecognized input is counted rather than silently ignored" {
    var scanner = Scanner.init(std.testing.allocator);
    defer scanner.deinit();
    // LLVM bitcode, as an LTO build emits. An audit that reported a clean
    // result here would be lying by omission.
    try scanner.addBuffer("lto.o", "BC\xc0\xde" ++ ("\x00" ** 40));
    try std.testing.expectEqual(@as(usize, 1), scanner.skipped_inputs);
    try std.testing.expectEqual(@as(usize, 0), scanner.audit.units_seen);
}
