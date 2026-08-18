//! IMPORT BINDING PREDICTOR — decide whether a guest's own import-binding
//! failure report is evidence or noise, before anyone acts on it.
//!
//! An emulator that audits its own XEX import table and prints failures is
//! handing Rosette a claim, not a fact. The claim is worth exactly as much as
//! the address it names, and the address arrives from the guest's parser — so
//! it can be an uninitialized field, a stale slot, or a value that was never a
//! code pointer at all. Believing such a report sends the reader after ten
//! missing kernel imports that are all bound correctly.
//!
//! The observed case: five modules reported twenty-one failures, every one of
//! them a *data* export (`KeDebugMonitorData`, `VdGlobalDevice`,
//! `XexExecutableModuleHandle`, ...), and every failure inside one module named
//! the *same* thunk address. Data imports have no thunk record, so the field
//! was never assigned and each audit read whatever the stack held. Two
//! independent proofs of that, both requiring no knowledge of any program:
//!
//!   * **Misalignment.** A PowerPC instruction address is four-byte aligned by
//!     the architecture. `0x7FFFB849` is not an address any thunk can have.
//!   * **Sharing.** N distinct imports cannot share one thunk address. Two
//!     failures naming the same thunk prove the field is not per-import,
//!     whatever the value happens to be.
//!
//! Either proof turns "ten kernel imports failed to bind" into "the auditor's
//! evidence is invalid", which is a different bug in a different program. When
//! neither fires the report survives, is counted, and is reported as genuine —
//! the point is to spend the reader's attention on real ones.
//!
//! Cost: parsing runs only on guest log lines that already matched the audit
//! prefix, which appeared twenty-one times in a twelve-billion-step run.

const std = @import("std");
const machoCapturePrint = @import("dyld").event_log.machoCapturePrint;

/// PowerPC instructions are four-byte aligned. Nothing that fails this can be
/// the address of a thunk, whatever else is true about it.
pub const THUNK_ALIGNMENT: u64 = 4;

pub const MODULE_CAPACITY: usize = 16;
pub const MAX_NAME_LEN: usize = 48;
pub const MAX_EMISSIONS_PER_MODULE: u32 = 2;

pub const Verdict = enum {
    /// The thunk address is not four-byte aligned, so it is not a code address.
    evidence_misaligned_thunk,
    /// Several imports in one audit named the same thunk address.
    evidence_shared_thunk,
    /// Nothing disproved the report. Treat it as a real unbound import.
    binding_genuinely_missing,

    pub fn invalid(self: Verdict) bool {
        return self != .binding_genuinely_missing;
    }

    pub fn reason(self: Verdict) []const u8 {
        return switch (self) {
            .evidence_misaligned_thunk => "thunk_address_is_not_four_byte_aligned",
            .evidence_shared_thunk => "one_thunk_address_reported_for_several_imports",
            .binding_genuinely_missing => "no_contradiction_found",
        };
    }
};

/// One failure report, parsed out of the guest's audit line.
pub const Report = struct {
    module: []const u8 = "",
    library: []const u8 = "",
    ordinal: u64 = 0,
    name: []const u8 = "",
    thunk: u64 = 0,
};

const Module = struct {
    valid: bool = false,
    name_buf: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN,
    name_len: usize = 0,
    /// First thunk address this module reported, and whether every later one
    /// matched it. Sharing is the property that needs no address-space model.
    first_thunk: u64 = 0,
    all_thunks_equal: bool = true,
    distinct_thunks: u32 = 0,
    failures: u32 = 0,
    misaligned: u32 = 0,
    invalidated: u32 = 0,
    genuine: u32 = 0,
    emissions: u32 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,

    fn label(self: *const Module) []const u8 {
        return self.name_buf[0..self.name_len];
    }
};

pub const Predictor = struct {
    modules: [MODULE_CAPACITY]Module = [_]Module{.{}} ** MODULE_CAPACITY,
    module_count: usize = 0,
    reports: u64 = 0,
    invalidated: u64 = 0,
    genuine: u64 = 0,
    dropped_modules: u64 = 0,
    emissions: u64 = 0,

    /// Judge one parsed failure report. Returns the verdict so a caller can
    /// decide whether to propagate the guest's claim.
    pub fn note(self: *Predictor, report: Report, step: u64) Verdict {
        self.reports +|= 1;
        const module = self.findOrInsert(report.module) orelse {
            self.dropped_modules +|= 1;
            // Alignment stands on its own without any per-module history, so a
            // full table still rejects the report the architecture forbids.
            return if (misalignedThunk(report.thunk))
                .evidence_misaligned_thunk
            else
                .binding_genuinely_missing;
        };

        if (module.failures == 0) {
            module.first_thunk = report.thunk;
            module.first_step = step;
            module.distinct_thunks = 1;
        } else if (report.thunk != module.first_thunk) {
            module.all_thunks_equal = false;
            module.distinct_thunks +|= 1;
        }
        module.failures +|= 1;
        module.last_step = step;

        const verdict = judge(module, report);
        switch (verdict) {
            .evidence_misaligned_thunk => {
                module.misaligned +|= 1;
                module.invalidated +|= 1;
                self.invalidated +|= 1;
            },
            .evidence_shared_thunk => {
                module.invalidated +|= 1;
                self.invalidated +|= 1;
            },
            .binding_genuinely_missing => {
                module.genuine +|= 1;
                self.genuine +|= 1;
            },
        }
        if (module.emissions < MAX_EMISSIONS_PER_MODULE) {
            module.emissions +|= 1;
            self.emit(module, report, verdict);
        }
        return verdict;
    }

    fn emit(self: *Predictor, module: *const Module, report: Report, verdict: Verdict) void {
        self.emissions +|= 1;
        if (verdict.invalid()) {
            machoCapturePrint(
                "IMPORT BINDING PREDICTOR: verdict=audit_evidence_invalid reason={s} module={s} library={s} ordinal=0x{x} name={s} thunk=0x{x} aligned={} failures_so_far={d} distinct_thunks={d}; the auditor's own thunk address disproves its finding, so this import is not shown to be unbound — the defect is in whatever produced the address, and a data-only import never has a thunk record to produce one from. Predicted=every further failure from this module carries the same invalid evidence and none of them names a real binding gap\n",
                .{
                    verdict.reason(),
                    module.label(),
                    report.library,
                    report.ordinal,
                    report.name,
                    report.thunk,
                    !misalignedThunk(report.thunk),
                    module.failures,
                    module.distinct_thunks,
                },
            );
            return;
        }
        machoCapturePrint(
            "IMPORT BINDING PREDICTOR: verdict=binding_genuinely_missing module={s} library={s} ordinal=0x{x} name={s} thunk=0x{x} failures_so_far={d}; the thunk address is a plausible aligned code address and is not shared with another import, so nothing here contradicts the report. Predicted=a call through this import reaches an unbound thunk and faults or returns garbage\n",
            .{ module.label(), report.library, report.ordinal, report.name, report.thunk, module.failures },
        );
    }

    pub fn dump(self: *const Predictor, reason: []const u8) void {
        if (self.reports == 0) return;
        for (self.modules[0..self.module_count]) |*module| {
            if (!module.valid) continue;
            machoCapturePrint(
                "IMPORT BINDING PREDICTOR: module={s} failures={d} invalidated={d} genuine={d} misaligned={d} distinct_thunks={d} shared_thunk={} first_thunk=0x{x} steps=[{d}..{d}]\n",
                .{
                    module.label(),
                    module.failures,
                    module.invalidated,
                    module.genuine,
                    module.misaligned,
                    module.distinct_thunks,
                    module.failures > 1 and module.all_thunks_equal,
                    module.first_thunk,
                    module.first_step,
                    module.last_step,
                },
            );
        }
        machoCapturePrint(
            "IMPORT BINDING PREDICTOR: dump reason={s} modules={d} reports={d} invalidated={d} genuine={d} dropped_modules={d}; invalidated reports are the guest auditor contradicting itself and must not be counted as missing imports. Only `genuine` is a number to act on\n",
            .{ reason, self.module_count, self.reports, self.invalidated, self.genuine, self.dropped_modules },
        );
    }

    fn findOrInsert(self: *Predictor, name: []const u8) ?*Module {
        for (self.modules[0..self.module_count]) |*module| {
            if (module.valid and std.mem.eql(u8, module.label(), name)) return module;
        }
        if (self.module_count == MODULE_CAPACITY) return null;
        const module = &self.modules[self.module_count];
        const len = @min(name.len, MAX_NAME_LEN);
        @memcpy(module.name_buf[0..len], name[0..len]);
        module.* = .{
            .valid = true,
            .name_buf = module.name_buf,
            .name_len = len,
        };
        self.module_count += 1;
        return module;
    }
};

fn judge(module: *const Module, report: Report) Verdict {
    if (misalignedThunk(report.thunk)) return .evidence_misaligned_thunk;
    // One report cannot contradict itself by sharing; it takes a second.
    if (module.failures > 1 and module.all_thunks_equal) return .evidence_shared_thunk;
    return .binding_genuinely_missing;
}

pub fn misalignedThunk(thunk: u64) bool {
    // Zero is "no thunk recorded", which is a different statement from a
    // misaligned one and is not this predicate's business.
    if (thunk == 0) return false;
    return (thunk % THUNK_ALIGNMENT) != 0;
}

/// Parse `XEX import binding audit failure: module=M library=L ordinal=0xNNN
/// name=N thunk=0xNNNNNNNN reason=...`. Returns null for any line that is not
/// one, so the caller can hand it every mirrored guest line.
pub fn parse(message: []const u8) ?Report {
    const marker = "XEX import binding audit failure:";
    const start = std.mem.indexOf(u8, message, marker) orelse return null;
    const tail = message[start + marker.len ..];
    var report = Report{};
    report.module = field(tail, "module=") orelse return null;
    report.library = field(tail, "library=") orelse "";
    report.name = field(tail, "name=") orelse "";
    report.ordinal = hexField(tail, "ordinal=") orelse 0;
    report.thunk = hexField(tail, "thunk=") orelse return null;
    return report;
}

fn field(text: []const u8, key: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, text, key) orelse return null;
    const rest = text[at + key.len ..];
    const end = std.mem.indexOfAny(u8, rest, " \t\n") orelse rest.len;
    if (end == 0) return null;
    return rest[0..end];
}

fn hexField(text: []const u8, key: []const u8) ?u64 {
    var token = field(text, key) orelse return null;
    if (std.mem.startsWith(u8, token, "0x") or std.mem.startsWith(u8, token, "0X")) {
        token = token[2..];
    }
    if (token.len == 0) return null;
    return std.fmt.parseInt(u64, token, 16) catch null;
}

test "the observed audit lines parse into their fields" {
    const line = "[xenia] w> XEX import binding audit failure: module=default library=xboxkrnl ordinal=0x1BE name=VdGlobalDevice thunk=0x7FFFB849 reason=no function symbol at thunk";
    const report = parse(line).?;
    try std.testing.expectEqualStrings("default", report.module);
    try std.testing.expectEqualStrings("xboxkrnl", report.library);
    try std.testing.expectEqualStrings("VdGlobalDevice", report.name);
    try std.testing.expectEqual(@as(u64, 0x1BE), report.ordinal);
    try std.testing.expectEqual(@as(u64, 0x7FFFB849), report.thunk);

    // Anything else is not this line.
    try std.testing.expect(parse("[xenia] i> RING BUFFER: KeWaitForSingleObject result=00000102") == null);
    try std.testing.expect(parse("XEX import binding audit failed: module=default checks=180") == null);
}

test "a misaligned thunk address disproves the report on its own" {
    // Every thunk the observed run named was odd-aligned, which no PowerPC
    // instruction address can be.
    try std.testing.expect(misalignedThunk(0x7FFFB849));
    try std.testing.expect(misalignedThunk(0x1B386629));
    try std.testing.expect(misalignedThunk(0x1B3865C9));
    // A real thunk address is four-byte aligned.
    try std.testing.expect(!misalignedThunk(0x8270E034));
    // Zero means "no thunk recorded" and is a different statement.
    try std.testing.expect(!misalignedThunk(0));

    var predictor = Predictor{};
    const verdict = predictor.note(.{
        .module = "default",
        .library = "xboxkrnl",
        .ordinal = 0x1BE,
        .name = "VdGlobalDevice",
        .thunk = 0x7FFFB849,
    }, 100);
    try std.testing.expectEqual(Verdict.evidence_misaligned_thunk, verdict);
    try std.testing.expect(verdict.invalid());
    try std.testing.expectEqual(@as(u64, 1), predictor.invalidated);
    try std.testing.expectEqual(@as(u64, 0), predictor.genuine);
}

test "several imports sharing one thunk address disproves the report without any address model" {
    // Aligned addresses, so only the sharing argument is available. Two
    // distinct ordinals cannot have the same thunk.
    var predictor = Predictor{};
    const first = predictor.note(.{ .module = "L360", .name = "ExThreadObjectType", .ordinal = 0x01B, .thunk = 0x1B386628 }, 1);
    // One report alone proves nothing.
    try std.testing.expectEqual(Verdict.binding_genuinely_missing, first);

    const second = predictor.note(.{ .module = "L360", .name = "KeDebugMonitorData", .ordinal = 0x059, .thunk = 0x1B386628 }, 2);
    try std.testing.expectEqual(Verdict.evidence_shared_thunk, second);
    const third = predictor.note(.{ .module = "L360", .name = "XexExecutableModuleHandle", .ordinal = 0x193, .thunk = 0x1B386628 }, 3);
    try std.testing.expectEqual(Verdict.evidence_shared_thunk, third);
    try std.testing.expectEqual(@as(u64, 2), predictor.invalidated);
}

test "a report nothing contradicts survives as a real binding gap" {
    var predictor = Predictor{};
    // Distinct, aligned thunk addresses: exactly what a genuine unbound import
    // looks like. Widening the invalidation rules until this stops being
    // reported would make the predictor worse than having none.
    const a = predictor.note(.{ .module = "game", .name = "SomeExport", .ordinal = 0x10, .thunk = 0x82001000 }, 1);
    const b = predictor.note(.{ .module = "game", .name = "OtherExport", .ordinal = 0x11, .thunk = 0x82001010 }, 2);
    try std.testing.expectEqual(Verdict.binding_genuinely_missing, a);
    try std.testing.expectEqual(Verdict.binding_genuinely_missing, b);
    try std.testing.expectEqual(@as(u64, 2), predictor.genuine);
    try std.testing.expectEqual(@as(u64, 0), predictor.invalidated);
}

test "modules are judged independently and a full table still rejects the impossible" {
    var predictor = Predictor{};
    // The observed run: five modules, each with its own shared garbage value.
    const modules = [_][]const u8{ "default", "WaveShell-Xbox", "WavesLibDLL", "L360", "Q10" };
    for (modules, 0..) |module, index| {
        const thunk: u64 = 0x1B386629 + @as(u64, index) * 0x40;
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            _ = predictor.note(.{ .module = module, .name = "Data", .ordinal = 0x59, .thunk = thunk }, i);
        }
    }
    try std.testing.expectEqual(@as(usize, modules.len), predictor.module_count);
    // All misaligned, so every one is invalidated and none survives as genuine.
    try std.testing.expectEqual(@as(u64, 15), predictor.invalidated);
    try std.testing.expectEqual(@as(u64, 0), predictor.genuine);

    // Overflow the table; alignment still decides without a record.
    var extra: usize = 0;
    while (extra < MODULE_CAPACITY) : (extra += 1) {
        var buf: [8]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "m{d}", .{extra}) catch unreachable;
        _ = predictor.note(.{ .module = name, .name = "x", .thunk = 0x82000000 }, 0);
    }
    try std.testing.expect(predictor.dropped_modules > 0);
}
