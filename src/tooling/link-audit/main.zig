//! Driver for the link-set audit.
//!
//! Usage:
//!   link-audit <object-or-archive>...
//!   link-audit --ninja <build.ninja> --target <substring> [--root <dir>]
//!
//! The ninja mode reads the link edge for a target and audits exactly the
//! inputs that edge names. That matters more than convenience: auditing a
//! directory of object files reports collisions between translation units that
//! are never linked together, which is noise indistinguishable from a defect.

const std = @import("std");
const link_audit = @import("link_audit");

const usage_text =
    \\usage: link-audit <object-or-archive>...
    \\       link-audit --ninja <build.ninja> --target <substring> [--root <dir>]
    \\
    \\Audits a completed link set for symbol resolutions that the source does
    \\not determine: duplicate strong definitions, multiple entry points, and
    \\definitions selected by archive member order.
    \\
;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var out_buffer: [1 << 16]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &out_buffer);
    const writer = &stdout.interface;

    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) {
        try writer.writeAll(usage_text);
        try writer.flush();
        return;
    }

    var ninja_path: ?[]const u8 = null;
    var target: ?[]const u8 = null;
    var root: []const u8 = ".";
    var explicit: std.ArrayListUnmanaged([]const u8) = .empty;

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const argument = args[index];
        if (std.mem.eql(u8, argument, "--ninja") and index + 1 < args.len) {
            index += 1;
            ninja_path = args[index];
        } else if (std.mem.eql(u8, argument, "--target") and index + 1 < args.len) {
            index += 1;
            target = args[index];
        } else if (std.mem.eql(u8, argument, "--root") and index + 1 < args.len) {
            index += 1;
            root = args[index];
        } else if (std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h")) {
            try writer.writeAll(usage_text);
            try writer.flush();
            return;
        } else {
            try explicit.append(allocator, argument);
        }
    }

    var inputs: std.ArrayListUnmanaged([]const u8) = .empty;
    if (ninja_path) |path| {
        const wanted = target orelse {
            try writer.writeAll("--ninja requires --target\n");
            try writer.flush();
            return;
        };
        const text = std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(256 << 20)) catch {
            try writer.print("cannot read ninja file: {s}\n", .{path});
            try writer.flush();
            return;
        };
        try collectLinkEdge(allocator, text, wanted, &inputs);
        if (inputs.items.len == 0) {
            try writer.print("no link edge in {s} matched target '{s}'\n", .{ path, wanted });
            try writer.flush();
            return;
        }
    } else {
        inputs = explicit;
    }

    var scanner = link_audit.Scanner.init(allocator);
    defer scanner.deinit();

    for (inputs.items) |relative| {
        const full = if (std.mem.eql(u8, root, "."))
            relative
        else
            try std.fs.path.join(allocator, &.{ root, relative });
        const data = std.Io.Dir.cwd().readFileAlloc(init.io, full, allocator, .limited(512 << 20)) catch {
            scanner.noteUnreadable();
            continue;
        };
        try scanner.addBuffer(relative, data);
        allocator.free(data);
    }

    const findings = try scanner.findings(allocator);
    const verdict = try scanner.verdict(allocator);

    try writer.print(
        "link-audit: units={d} objects={d} archives={d} members={d} skipped={d} unreadable={d}\n",
        .{
            scanner.audit.units_seen,
            scanner.objects_read,
            scanner.archives_read,
            scanner.members_read,
            scanner.skipped_inputs,
            scanner.unreadable_inputs,
        },
    );
    try writer.print(
        "link-audit: symbols strong={d} weak={d} private={d} references={d}\n",
        .{
            scanner.audit.strong_definitions,
            scanner.audit.weak_definitions,
            scanner.audit.private_definitions,
            scanner.audit.reference_count,
        },
    );

    var shown: usize = 0;
    for (findings) |finding| {
        // Unresolved references are dominated by system frameworks the link
        // set legitimately does not contain, so they are counted rather than
        // listed. Listing them would bury the findings that matter.
        if (finding.kind == .unresolved_reference) continue;
        try writer.print(
            "link-audit: {s} {s} symbol={s} definitions={d}{s}{s}\n",
            .{
                finding.severity.label(),
                finding.kind.label(),
                finding.symbol,
                finding.units.len,
                if (finding.shared_archive.len != 0) " archive=" else "",
                finding.shared_archive,
            },
        );
        for (finding.units) |unit| {
            try writer.print("link-audit:     defined in {s}\n", .{unit});
        }
        shown += 1;
    }

    try writer.print(
        "link-audit: VERDICT {s} critical={d} warnings={d} notes={d} detail={s}\n",
        .{
            if (verdict.passed) "PASS" else "FAIL",
            verdict.critical,
            verdict.warnings,
            verdict.notes,
            verdict.detail(),
        },
    );
    try writer.flush();
}

/// Pull the inputs of a ninja link edge.
///
/// A ninja edge reads `build <outputs>: <rule> <explicit> | <implicit> || <order-only>`.
/// Order-only inputs are dependencies rather than link inputs, so everything
/// after `||` is dropped; the archives actually linked appear as implicit
/// inputs and must be kept.
fn collectLinkEdge(
    allocator: std.mem.Allocator,
    text: []const u8,
    target: []const u8,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "build ")) continue;
        if (std.mem.indexOf(u8, line, "LINKER") == null) continue;
        if (std.mem.indexOf(u8, line, target) == null) continue;
        const after_colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        var body = line[after_colon + 1 ..];
        if (std.mem.indexOf(u8, body, " || ")) |cut| body = body[0..cut];
        var tokens = std.mem.tokenizeAny(u8, body, " \t");
        // The first token is the rule name.
        _ = tokens.next();
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "|")) continue;
            if (!std.mem.endsWith(u8, token, ".o") and !std.mem.endsWith(u8, token, ".a")) continue;
            var duplicate = false;
            for (out.items) |existing| {
                if (std.mem.eql(u8, existing, token)) duplicate = true;
            }
            if (!duplicate) try out.append(allocator, token);
        }
        return;
    }
}

test "a ninja link edge yields objects and archives but not order-only deps" {
    const text =
        \\build other: phony x.o
        \\build bin/app: CXX_EXECUTABLE_LINKER__app_Debug a.o b.o | libone.a libtwo.a || libone.a libthree.a
        \\
    ;
    var inputs: std.ArrayListUnmanaged([]const u8) = .empty;
    defer inputs.deinit(std.testing.allocator);
    try collectLinkEdge(std.testing.allocator, text, "bin/app", &inputs);
    try std.testing.expectEqual(@as(usize, 4), inputs.items.len);
    try std.testing.expectEqualStrings("a.o", inputs.items[0]);
    try std.testing.expectEqualStrings("libtwo.a", inputs.items[3]);
    // libthree.a appears only after `||`, so it is an order-only dependency
    // and not part of the link.
    for (inputs.items) |item| {
        try std.testing.expect(!std.mem.eql(u8, item, "libthree.a"));
    }
}

test "a non-linker edge is never mistaken for a link set" {
    const text = "build bin/app: phony a.o b.o\n";
    var inputs: std.ArrayListUnmanaged([]const u8) = .empty;
    defer inputs.deinit(std.testing.allocator);
    try collectLinkEdge(std.testing.allocator, text, "bin/app", &inputs);
    try std.testing.expectEqual(@as(usize, 0), inputs.items.len);
}
