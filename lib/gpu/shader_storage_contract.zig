//! Shader and texture bytes: exact reads, stable hashes, and bindings that
//! were actually populated.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run loaded shaders from the pipeline cache. Loading is not
//! executing, and a cache that returns the wrong bytes for the right id
//! produces a shader that runs, a draw that completes, and pixels the title
//! did not ask for — with every counter healthy.
//!
//! The same applies to textures: a sampler bound to a descriptor nobody
//! populated reads whatever the slot held, and a format converted with the
//! wrong swizzle is a picture rather than an error.
//!
//! So storage here is checked rather than trusted: bytes are hashed against
//! what the id claims, bindings are counted against what the shader declared
//! it needs, and a partially-populated binding set is its own finding.
//!
//! Cost control
//! ------------
//! Only resources on the current draw or resolve dependency chain are
//! instrumented. Hashing every texture in a title would recreate the
//! throughput problem the audit separately asks to fix.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;

pub const ResourceKind = enum(u8) {
    vertex_shader = 0,
    pixel_shader = 1,
    texture = 2,
    sampler = 3,
    vertex_fetch_constant = 4,

    pub fn label(self: ResourceKind) []const u8 {
        return switch (self) {
            .vertex_shader => "vertex-shader",
            .pixel_shader => "pixel-shader",
            .texture => "texture",
            .sampler => "sampler",
            .vertex_fetch_constant => "vertex-fetch-constant",
        };
    }
};

pub const kind_count: usize = @typeInfo(ResourceKind).@"enum".fields.len;

/// What happened when the bytes were fetched.
pub const Integrity = enum(u8) {
    /// The read returned every byte and the hash matched the id.
    verified = 0,
    /// The read returned every byte and nothing checked the hash.
    unverified = 1,
    /// The hash did not match the id.
    hash_mismatch = 2,
    /// Fewer bytes came back than the resource declares.
    short_read = 3,
    /// The resource was never fetched.
    absent = 4,

    pub fn label(self: Integrity) []const u8 {
        return switch (self) {
            .verified => "verified",
            .unverified => "unverified",
            .hash_mismatch => "HASH-MISMATCH",
            .short_read => "SHORT-READ",
            .absent => "ABSENT",
        };
    }

    pub fn describe(self: Integrity) []const u8 {
        return switch (self) {
            .verified => "every byte was read and the hash matches the id the resource was fetched under",
            .unverified => "every byte was read and nothing checked them against the id. A cache returning the wrong bytes for the right id produces a shader that runs and pixels the title did not ask for",
            .hash_mismatch => "the bytes do not hash to what the id claims. Whatever executed was not the resource the title asked for, and every conclusion about the draw that used it is unsafe",
            .short_read => "fewer bytes came back than the resource declares. A truncated shader or texture is a plausible structure with wrong contents",
            .absent => "the resource was never fetched. A draw that names it is naming something that does not exist here",
        };
    }

    pub fn usable(self: Integrity) bool {
        return self == .verified or self == .unverified;
    }

    pub fn isDefect(self: Integrity) bool {
        return self == .hash_mismatch or self == .short_read or self == .absent;
    }
};

/// One resource on the dependency chain.
pub const Resource = struct {
    kind: ResourceKind = .texture,
    id: u64 = 0,
    declared_bytes: u64 = 0,
    read_bytes: u64 = 0,
    declared_hash: u64 = 0,
    observed_hash: u64 = 0,
    hash_checked: bool = false,
    /// Guest format and the host format it was converted to. Both kept so a
    /// substitution is visible rather than inferred.
    guest_format: u32 = 0,
    host_format: u32 = 0,
    /// Bindings the shader declared it needs, and how many were populated.
    bindings_required: u32 = 0,
    bindings_populated: u32 = 0,
    source: SourceClass = .unknown,
    step: u64 = 0,

    pub fn integrity(self: Resource) Integrity {
        if (self.read_bytes == 0) return .absent;
        if (self.declared_bytes != 0 and self.read_bytes < self.declared_bytes) return .short_read;
        if (!self.hash_checked) return .unverified;
        return if (self.observed_hash == self.declared_hash) .verified else .hash_mismatch;
    }

    /// Whether every binding the shader declared was populated. A partially
    /// populated set reads whatever the slot held.
    pub fn bindingsComplete(self: Resource) bool {
        return self.bindings_populated >= self.bindings_required;
    }

    pub fn formatSubstituted(self: Resource) bool {
        return self.guest_format != 0 and self.host_format != 0 and self.guest_format != self.host_format;
    }
};

pub const max_resources: usize = 32;

pub const Summary = struct {
    resources: usize = 0,
    dropped: u64 = 0,
    verified: usize = 0,
    unverified: usize = 0,
    defects: usize = 0,
    incomplete_bindings: usize = 0,
    format_substitutions: usize = 0,
    by_kind: [kind_count]u64 = [_]u64{0} ** kind_count,

    /// The share of the chain that has actually been checked.
    pub fn verifiedPercent(self: Summary) u64 {
        if (self.resources == 0) return 0;
        return (@as(u64, self.verified) * 100) / self.resources;
    }
};

pub const Verdict = enum(u8) {
    /// Nothing on the chain has been instrumented.
    unobserved,
    /// Everything checked is intact.
    intact,
    /// Everything read and nothing verified.
    unverified,
    /// A binding set was partially populated.
    incomplete_bindings,
    /// Bytes did not match, were short, or were missing.
    corrupt,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .intact => "intact",
            .unverified => "unverified",
            .incomplete_bindings => "INCOMPLETE-BINDINGS",
            .corrupt => "CORRUPT",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "no resource on the current dependency chain has been instrumented. Nothing here supports a conclusion about what executed",
            .intact => "every instrumented resource read completely and hashed to what its id claims",
            .unverified => "resources read completely and nothing checked them against their ids. The draws that used them may have executed something else",
            .incomplete_bindings => "a shader declared bindings that were not all populated. The unpopulated slots read whatever they held, which is a picture rather than an error",
            .corrupt => "a resource's bytes do not match its id, were truncated, or were never fetched. Whatever executed was not what the title asked for",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .corrupt or self == .incomplete_bindings;
    }
};

pub const Ledger = struct {
    resources: [max_resources]Resource = [_]Resource{.{}} ** max_resources,
    count: usize = 0,
    dropped: u64 = 0,
    by_kind: [kind_count]u64 = [_]u64{0} ** kind_count,

    pub fn record(self: *Ledger, resource: Resource) ?*Resource {
        self.by_kind[@intFromEnum(resource.kind)] +|= 1;
        if (self.count >= max_resources) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.resources[self.count];
        self.count += 1;
        slot.* = resource;
        return slot;
    }

    pub fn retained(self: *const Ledger) []const Resource {
        return self.resources[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{ .resources = self.count, .dropped = self.dropped, .by_kind = self.by_kind };
        for (self.retained()) |resource| {
            switch (resource.integrity()) {
                .verified => out.verified += 1,
                .unverified => out.unverified += 1,
                else => out.defects += 1,
            }
            if (!resource.bindingsComplete()) out.incomplete_bindings += 1;
            if (resource.formatSubstituted()) out.format_substitutions += 1;
        }
        return out;
    }

    pub fn verdict(self: *const Ledger) Verdict {
        if (self.count == 0) return .unobserved;
        const totals = self.summary();
        if (totals.defects != 0) return .corrupt;
        if (totals.incomplete_bindings != 0) return .incomplete_bindings;
        if (totals.verified == 0) return .unverified;
        return .intact;
    }

    /// The first resource a reader should look at.
    pub fn firstSubject(self: *const Ledger) ?Resource {
        for (self.retained()) |resource| {
            if (resource.integrity().isDefect()) return resource;
        }
        for (self.retained()) |resource| {
            if (!resource.bindingsComplete()) return resource;
        }
        return null;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.resources;
        hash = hash *% 31 +% totals.verified;
        hash = hash *% 31 +% totals.defects;
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

fn readResource(kind: ResourceKind, id: u64, bytes: u64) Resource {
    return .{
        .kind = kind,
        .id = id,
        .declared_bytes = bytes,
        .read_bytes = bytes,
        .declared_hash = 0x1000 + id,
        .source = .guest_authentic,
    };
}

test "a cache hit that was never verified is not the same as a verified one" {
    var ledger = Ledger{};
    const resource = ledger.record(readResource(.vertex_shader, 1, 256)).?;
    try std.testing.expectEqual(Integrity.unverified, resource.integrity());
    try std.testing.expect(resource.integrity().usable());
    try std.testing.expectEqual(Verdict.unverified, ledger.verdict());
    try std.testing.expect(std.mem.indexOf(u8, Integrity.unverified.describe(), "did not ask for") != null);

    resource.hash_checked = true;
    resource.observed_hash = resource.declared_hash;
    try std.testing.expectEqual(Integrity.verified, resource.integrity());
    try std.testing.expectEqual(Verdict.intact, ledger.verdict());
    try std.testing.expectEqual(@as(u64, 100), ledger.summary().verifiedPercent());
}

test "bytes that do not hash to their id make the draw unsafe" {
    var ledger = Ledger{};
    const resource = ledger.record(readResource(.pixel_shader, 2, 512)).?;
    resource.hash_checked = true;
    resource.observed_hash = 0xDEAD;
    try std.testing.expectEqual(Integrity.hash_mismatch, resource.integrity());
    try std.testing.expect(!resource.integrity().usable());
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.corrupt, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expectEqual(ResourceKind.pixel_shader, ledger.firstSubject().?.kind);
}

test "a truncated read is corrupt rather than usable" {
    var ledger = Ledger{};
    const resource = ledger.record(readResource(.texture, 3, 1024)).?;
    resource.read_bytes = 512;
    try std.testing.expectEqual(Integrity.short_read, resource.integrity());
    try std.testing.expectEqual(Verdict.corrupt, ledger.verdict());
}

test "a resource nothing fetched is absent rather than empty" {
    var ledger = Ledger{};
    var missing = readResource(.texture, 4, 1024);
    missing.read_bytes = 0;
    _ = ledger.record(missing).?;
    try std.testing.expectEqual(Integrity.absent, missing.integrity());
    try std.testing.expect(Integrity.absent.isDefect());
}

test "a partially populated binding set reads whatever the slot held" {
    var ledger = Ledger{};
    const resource = ledger.record(readResource(.pixel_shader, 5, 256)).?;
    resource.hash_checked = true;
    resource.observed_hash = resource.declared_hash;
    resource.bindings_required = 4;
    resource.bindings_populated = 2;
    try std.testing.expect(!resource.bindingsComplete());
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.incomplete_bindings, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().incomplete_bindings);

    resource.bindings_populated = 4;
    try std.testing.expectEqual(Verdict.intact, ledger.verdict());
}

test "a format substitution is recorded without being a defect on its own" {
    var ledger = Ledger{};
    const resource = ledger.record(readResource(.texture, 6, 4096)).?;
    resource.hash_checked = true;
    resource.observed_hash = resource.declared_hash;
    resource.guest_format = 6;
    resource.host_format = 37;
    try std.testing.expect(resource.formatSubstituted());
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().format_substitutions);
    try std.testing.expectEqual(Verdict.intact, ledger.verdict());
}

test "an uninstrumented chain supports no conclusion" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Verdict.unobserved, ledger.verdict());
    try std.testing.expect(ledger.firstSubject() == null);
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().verifiedPercent());
}

test "the resource table is bounded and per-kind counts survive it" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_resources + 3) : (index += 1) {
        _ = ledger.record(readResource(.texture, index, 16));
    }
    try std.testing.expectEqual(max_resources, ledger.retained().len);
    try std.testing.expectEqual(@as(u64, 3), ledger.dropped);
    try std.testing.expectEqual(@as(u64, max_resources + 3), ledger.by_kind[@intFromEnum(ResourceKind.texture)]);

    inline for (@typeInfo(ResourceKind).@"enum".fields) |field| {
        const which: ResourceKind = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(Integrity).@"enum".fields) |field| {
        const which: Integrity = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
}
