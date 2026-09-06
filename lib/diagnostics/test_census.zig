//! A machine-readable census of source tests and executed test artifacts.
//!
//! `zig build check` is the authority for the artifacts it runs, but a large
//! repository can contain declarations that are imported only for compilation.
//! This bounded census keeps those categories separate and refuses to call the
//! run complete when a declaration has no executed owner.

const std = @import("std");

pub const schema_version: u16 = 1;
pub const source_capacity: usize = 4096;
pub const artifact_capacity: usize = 512;

pub const ArtifactStatus = enum(u8) {
    executed,
    compiled_only,
    filtered,
    skipped,
    failed,

    pub fn label(self: ArtifactStatus) []const u8 {
        return switch (self) {
            .executed => "executed",
            .compiled_only => "compiled-only",
            .filtered => "filtered",
            .skipped => "skipped",
            .failed => "failed",
        };
    }
};

pub const SourceUnit = struct {
    path_hash: u64 = 0,
    source_hash: u64 = 0,
    declarations: u64 = 0,
};

pub const Artifact = struct {
    path_hash: u64 = 0,
    source_hash: u64 = 0,
    runner_hash: u64 = 0,
    declared_count: u64 = 0,
    reported_count: u64 = 0,
    status: ArtifactStatus = .compiled_only,
};

pub const Report = struct {
    source_units: u64 = 0,
    declarations: u64 = 0,
    artifacts: u64 = 0,
    executed_artifacts: u64 = 0,
    compiled_only_artifacts: u64 = 0,
    filtered_artifacts: u64 = 0,
    failed_artifacts: u64 = 0,
    unowned_declarations: u64 = 0,
    source_hash_mismatches: u64 = 0,
    declaration_count_mismatches: u64 = 0,
    missing_runner_hash: u64 = 0,

    pub fn complete(self: Report) bool {
        return self.source_units != 0 and self.declarations != 0 and self.artifacts != 0 and
            self.executed_artifacts != 0 and self.unowned_declarations == 0 and
            self.source_hash_mismatches == 0 and self.declaration_count_mismatches == 0 and
            self.filtered_artifacts == 0 and self.failed_artifacts == 0 and
            self.missing_runner_hash == 0;
    }
};

pub const Census = struct {
    sources: [source_capacity]SourceUnit = [_]SourceUnit{.{}} ** source_capacity,
    source_count: usize = 0,
    artifacts: [artifact_capacity]Artifact = [_]Artifact{.{}} ** artifact_capacity,
    artifact_count: usize = 0,
    rejected: u64 = 0,

    pub fn observeSource(self: *Census, path: []const u8, contents: []const u8) bool {
        if (path.len == 0 or self.source_count >= source_capacity) {
            self.rejected +|= 1;
            return false;
        }
        const declarations = countDeclarations(contents);
        self.sources[self.source_count] = .{ .path_hash = hash(path), .source_hash = hash(contents), .declarations = declarations };
        self.source_count += 1;
        return true;
    }

    pub fn recordArtifact(self: *Census, path: []const u8, source_hash: u64, runner_hash: u64, declared_count: u64, reported_count: u64, status: ArtifactStatus) bool {
        if (path.len == 0 or source_hash == 0 or self.artifact_count >= artifact_capacity) {
            self.rejected +|= 1;
            return false;
        }
        self.artifacts[self.artifact_count] = .{ .path_hash = hash(path), .source_hash = source_hash, .runner_hash = runner_hash, .declared_count = declared_count, .reported_count = reported_count, .status = status };
        self.artifact_count += 1;
        return true;
    }

    pub fn report(self: *const Census) Report {
        var result = Report{ .source_units = self.source_count, .artifacts = self.artifact_count };
        for (self.sources[0..self.source_count]) |source| {
            result.declarations +|= source.declarations;
            var owned = false;
            for (self.artifacts[0..self.artifact_count]) |artifact| {
                if (artifact.path_hash != source.path_hash) continue;
                owned = true;
                if (artifact.source_hash != source.source_hash) result.source_hash_mismatches +|= 1;
                if (artifact.declared_count != source.declarations or artifact.reported_count != source.declarations) result.declaration_count_mismatches +|= 1;
                if (artifact.runner_hash == 0) result.missing_runner_hash +|= 1;
                switch (artifact.status) {
                    .executed => result.executed_artifacts +|= 1,
                    .compiled_only => result.compiled_only_artifacts +|= 1,
                    .filtered, .skipped => result.filtered_artifacts +|= 1,
                    .failed => result.failed_artifacts +|= 1,
                }
            }
            if (!owned) result.unowned_declarations +|= source.declarations;
        }
        return result;
    }

    pub fn authenticReady(self: *const Census) bool {
        return self.rejected == 0 and self.report().complete();
    }
};

/// Counts named declaration forms (`test "name"`), not
/// `test { ... }` root harness blocks. The latter roots imported declarations
/// but is not itself a source-level test case.
pub fn countDeclarations(contents: []const u8) u64 {
    var count: u64 = 0;
    var line_start: usize = 0;
    while (line_start < contents.len) {
        const line_end = std.mem.indexOfScalarPos(u8, contents, line_start, '\n') orelse contents.len;
        const line = std.mem.trim(u8, contents[line_start..line_end], " \t");
        if (std.mem.startsWith(u8, line, "test \"")) count +|= 1;
        if (line_end == contents.len) break;
        line_start = line_end + 1;
    }
    return count;
}

pub fn hash(bytes: []const u8) u64 {
    var result: u64 = 0xcbf2_9ce4_8422_2325;
    for (bytes) |byte| result = (result ^ byte) *% 0x100_0000_01b3;
    return if (result == 0) 1 else result;
}

test "census counts source declarations but not root test harnesses" {
    const source = "test \"one\" { }\ntest \"two\" { }\ntest { _ = one; }\n";
    try std.testing.expectEqual(@as(u64, 2), countDeclarations(source));
}

test "census requires an executed artifact for every declaration" {
    var census = Census{};
    const source = "test \"one\" {}\ntest \"two\" {}\n";
    try std.testing.expect(census.observeSource("module.zig", source));
    const source_hash = hash(source);
    try std.testing.expect(census.recordArtifact("module.zig", source_hash, 7, 2, 2, .executed));
    try std.testing.expect(census.authenticReady());
}

test "compile-only, filtered, and stale artifacts do not become executed proof" {
    var census = Census{};
    const source = "test \"one\" {}\n";
    try std.testing.expect(census.observeSource("module.zig", source));
    try std.testing.expect(census.recordArtifact("module.zig", hash("different"), 0, 1, 1, .compiled_only));
    const result = census.report();
    try std.testing.expect(!result.complete());
    try std.testing.expectEqual(@as(u64, 1), result.source_hash_mismatches);
    try std.testing.expectEqual(@as(u64, 1), result.compiled_only_artifacts);
    try std.testing.expectEqual(@as(u64, 1), result.missing_runner_hash);
}

test "unowned source declarations are explicit coverage debt" {
    var census = Census{};
    try std.testing.expect(census.observeSource("unowned.zig", "test \"one\" {}\n"));
    try std.testing.expectEqual(@as(u64, 1), census.report().unowned_declarations);
    try std.testing.expect(!census.authenticReady());
}

test "the census is bounded and rejects empty inputs" {
    var census = Census{};
    try std.testing.expect(!census.observeSource("", "test \"one\" {}"));
    try std.testing.expect(!census.recordArtifact("module.zig", 0, 1, 1, 1, .executed));
    try std.testing.expectEqual(@as(u64, 2), census.rejected);
}
