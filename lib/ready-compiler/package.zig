//! Safe, versioned package manifests for Ready Compiler artifacts.
//!
//! A package is a portable description of reusable *static evidence*. It is
//! not a memory image and it is not a serialized runtime. The manifest can
//! identify a contract, decoder facts, a static reference plan, or a shader
//! source index, but it refuses guest pointers, generated code, native handles,
//! thread state, and other activation products that only make sense inside the
//! process that created them.

const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

pub const format_version: u32 = 1;
pub const max_artifacts: usize = 8;
pub const serialized_size: usize = 348;
const magic = "R3RDPKG1";

pub const PackageKind = enum(u8) {
    xenia_halo3_startup,
};

pub const Architecture = enum(u8) {
    any,
    x86_64,
    ppc64,
    arm64,
};

pub const Endian = enum(u8) {
    little,
    big,
};

pub const ArtifactKind = enum(u8) {
    ready_contract,
    static_plan,
    decoder_audit,
    shader_source_index,

    pub fn label(self: ArtifactKind) []const u8 {
        return switch (self) {
            .ready_contract => "ready-contract",
            .static_plan => "static-plan",
            .decoder_audit => "decoder-audit",
            .shader_source_index => "shader-source-index",
        };
    }
};

/// Flags are deliberately restrictive. A package can describe a host-bound
/// artifact, but it may not silently become a code or state snapshot.
pub const ArtifactFlags = struct {
    pub const static_evidence: u16 = 1 << 0;
    pub const portable: u16 = 1 << 1;
    pub const host_bound: u16 = 1 << 2;
    pub const guest_code: u16 = 1 << 3;
};

pub const Artifact = struct {
    kind: ArtifactKind,
    architecture: Architecture = .any,
    flags: u16 = ArtifactFlags.static_evidence,
    size: u64 = 0,
    content_fingerprint: u64 = 0,
    dependency_fingerprint: u64 = 0,
};

pub const Manifest = struct {
    package_kind: PackageKind = .xenia_halo3_startup,
    architecture: Architecture = .x86_64,
    endian: Endian = .little,
    pointer_bits: u8 = 64,
    abi_epoch: u32 = 1,
    contract_fingerprint: u64 = 0,
    image_fingerprint: u64 = 0,

    // The static-plan package carries the same bounded evidence as the raw
    // plan cache. This makes the package independently useful on a later run;
    // it does not force the loader to trust a separate sidecar file.
    static_plan_target_fingerprint: u64 = 0,
    static_plan_target_count: u64 = 0,
    static_plan_referenced_mask: u64 = 0,
    static_plan_scanned_bytes: u64 = 0,
    static_plan_direct_call_sites: u64 = 0,

    artifacts: [max_artifacts]Artifact = [_]Artifact{.{ .kind = .ready_contract }} ** max_artifacts,
    artifact_count: usize = 0,

    pub fn init(
        package_kind: PackageKind,
        target_architecture: Architecture,
        target_endian: Endian,
        pointer_bits: u8,
        abi_epoch: u32,
        contract_fingerprint: u64,
        image_fingerprint: u64,
    ) Manifest {
        return .{
            .package_kind = package_kind,
            .architecture = target_architecture,
            .endian = target_endian,
            .pointer_bits = pointer_bits,
            .abi_epoch = abi_epoch,
            .contract_fingerprint = contract_fingerprint,
            .image_fingerprint = image_fingerprint,
        };
    }

    pub fn addArtifact(self: *Manifest, artifact: Artifact) bool {
        if (self.artifact_count >= self.artifacts.len) return false;
        for (self.artifacts[0..self.artifact_count]) |existing| {
            if (existing.kind == artifact.kind) return false;
        }
        self.artifacts[self.artifact_count] = artifact;
        self.artifact_count += 1;
        return true;
    }

    pub fn hasArtifact(self: *const Manifest, kind: ArtifactKind) bool {
        for (self.artifacts[0..self.artifact_count]) |artifact| {
            if (artifact.kind == kind) return true;
        }
        return false;
    }

    pub fn matchesStaticPlan(
        self: *const Manifest,
        image_fingerprint: u64,
        contract_fingerprint: u64,
        target_fingerprint: u64,
        target_count: usize,
    ) bool {
        return self.package_kind == .xenia_halo3_startup and
            self.image_fingerprint == image_fingerprint and
            self.contract_fingerprint == contract_fingerprint and
            self.static_plan_target_fingerprint == target_fingerprint and
            self.static_plan_target_count == target_count and
            target_count <= 64 and
            self.hasArtifact(.static_plan);
    }

    /// Reject malformed or unsafe manifests before they can become a launch
    /// input. Unknown future flags are rejected too: silently accepting a new
    /// meaning would turn a version check into a guess.
    pub fn valid(self: *const Manifest) bool {
        if (self.artifact_count == 0 or self.artifact_count > self.artifacts.len) return false;
        if (self.pointer_bits != 32 and self.pointer_bits != 64) return false;
        if (self.contract_fingerprint == 0 or self.image_fingerprint == 0) return false;
        if (self.static_plan_target_count > 64) return false;
        for (self.artifacts[0..self.artifact_count], 0..) |artifact, index| {
            if (artifact.content_fingerprint == 0) return false;
            if (artifact.size == 0) return false;
            if (artifact.flags & ArtifactFlags.guest_code != 0) return false;
            if (artifact.flags & ~(ArtifactFlags.static_evidence | ArtifactFlags.portable | ArtifactFlags.host_bound | ArtifactFlags.guest_code) != 0) return false;
            for (self.artifacts[0..index]) |previous| {
                if (previous.kind == artifact.kind) return false;
            }
        }
        return true;
    }
};

fn putU32(buffer: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, buffer[offset..][0..4], value, .little);
}

fn putU64(buffer: []u8, offset: usize, value: u64) void {
    std.mem.writeInt(u64, buffer[offset..][0..8], value, .little);
}

fn getU32(buffer: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, buffer[offset..][0..4], .little);
}

fn getU64(buffer: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, buffer[offset..][0..8], .little);
}

fn artifactOffset(index: usize) usize {
    return 84 + index * 32;
}

pub fn encode(manifest: Manifest, output: []u8) ?[]const u8 {
    if (output.len < serialized_size or !manifest.valid()) return null;
    @memset(output[0..serialized_size], 0);
    @memcpy(output[0..magic.len], magic);
    putU32(output, 8, format_version);
    output[12] = @intFromEnum(manifest.package_kind);
    output[13] = @intFromEnum(manifest.architecture);
    output[14] = @intFromEnum(manifest.endian);
    output[15] = manifest.pointer_bits;
    putU32(output, 16, manifest.abi_epoch);
    putU64(output, 20, manifest.contract_fingerprint);
    putU64(output, 28, manifest.image_fingerprint);
    putU64(output, 36, manifest.static_plan_target_fingerprint);
    putU64(output, 44, manifest.static_plan_target_count);
    putU64(output, 52, manifest.static_plan_referenced_mask);
    putU64(output, 60, manifest.static_plan_scanned_bytes);
    putU64(output, 68, manifest.static_plan_direct_call_sites);
    putU32(output, 76, @intCast(manifest.artifact_count));

    for (manifest.artifacts[0..manifest.artifact_count], 0..) |artifact, index| {
        const offset = artifactOffset(index);
        output[offset] = @intFromEnum(artifact.kind);
        output[offset + 1] = @intFromEnum(artifact.architecture);
        std.mem.writeInt(u16, output[offset + 2 ..][0..2], artifact.flags, .little);
        putU64(output, offset + 4, artifact.size);
        putU64(output, offset + 12, artifact.content_fingerprint);
        putU64(output, offset + 20, artifact.dependency_fingerprint);
    }
    const checksum_offset = serialized_size - 8;
    putU64(output, checksum_offset, std.hash.Wyhash.hash(0, output[0..checksum_offset]));
    return output[0..serialized_size];
}

fn packageKind(raw: u8) ?PackageKind {
    return switch (raw) {
        0 => .xenia_halo3_startup,
        else => null,
    };
}

fn architecture(raw: u8) ?Architecture {
    return switch (raw) {
        0 => .any,
        1 => .x86_64,
        2 => .ppc64,
        3 => .arm64,
        else => null,
    };
}

fn endian(raw: u8) ?Endian {
    return switch (raw) {
        0 => .little,
        1 => .big,
        else => null,
    };
}

fn artifactKind(raw: u8) ?ArtifactKind {
    return switch (raw) {
        0 => .ready_contract,
        1 => .static_plan,
        2 => .decoder_audit,
        3 => .shader_source_index,
        else => null,
    };
}

pub fn decode(input: []const u8) ?Manifest {
    if (input.len != serialized_size) return null;
    if (!std.mem.eql(u8, input[0..magic.len], magic)) return null;
    if (getU32(input, 8) != format_version) return null;
    const checksum_offset = serialized_size - 8;
    if (getU64(input, checksum_offset) != std.hash.Wyhash.hash(0, input[0..checksum_offset])) return null;
    const kind = packageKind(input[12]) orelse return null;
    const target_arch = architecture(input[13]) orelse return null;
    const target_endian = endian(input[14]) orelse return null;
    const count = getU32(input, 76);
    if (count > max_artifacts) return null;

    var manifest = Manifest{
        .package_kind = kind,
        .architecture = target_arch,
        .endian = target_endian,
        .pointer_bits = input[15],
        .abi_epoch = getU32(input, 16),
        .contract_fingerprint = getU64(input, 20),
        .image_fingerprint = getU64(input, 28),
        .static_plan_target_fingerprint = getU64(input, 36),
        .static_plan_target_count = getU64(input, 44),
        .static_plan_referenced_mask = getU64(input, 52),
        .static_plan_scanned_bytes = getU64(input, 60),
        .static_plan_direct_call_sites = getU64(input, 68),
        .artifact_count = @intCast(count),
    };
    for (manifest.artifacts[0..manifest.artifact_count], 0..) |*artifact, index| {
        const offset = artifactOffset(index);
        artifact.* = .{
            .kind = artifactKind(input[offset]) orelse return null,
            .architecture = architecture(input[offset + 1]) orelse return null,
            .flags = std.mem.readInt(u16, input[offset + 2 ..][0..2], .little),
            .size = getU64(input, offset + 4),
            .content_fingerprint = getU64(input, offset + 12),
            .dependency_fingerprint = getU64(input, offset + 20),
        };
    }
    if (!manifest.valid()) return null;
    return manifest;
}

pub fn store(path: []const u8, allocator: std.mem.Allocator, manifest: Manifest) bool {
    const directory = std.fs.path.dirname(path) orelse return false;
    makePathRecursive(directory, allocator) catch return false;
    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);
    const fd = c.open(path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
    if (fd < 0) return false;
    defer _ = c.close(fd);
    var bytes: [serialized_size]u8 = undefined;
    const encoded = encode(manifest, &bytes) orelse return false;
    var written: usize = 0;
    while (written < encoded.len) {
        const amount = c.write(fd, encoded[written..].ptr, encoded.len - written);
        if (amount <= 0) return false;
        written += @intCast(amount);
    }
    _ = c.fsync(fd);
    return true;
}

pub fn load(path: []const u8, allocator: std.mem.Allocator) ?Manifest {
    const path_z = allocator.dupeZ(u8, path) catch return null;
    defer allocator.free(path_z);
    const fd = c.open(path_z.ptr, c.O_RDONLY | c.O_CLOEXEC, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = c.close(fd);
    var bytes: [serialized_size]u8 = undefined;
    var filled: usize = 0;
    while (filled < bytes.len) {
        const amount = c.read(fd, bytes[filled..].ptr, bytes.len - filled);
        if (amount <= 0) return null;
        filled += @intCast(amount);
    }
    return decode(&bytes);
}

fn makePathRecursive(raw_path: []const u8, allocator: std.mem.Allocator) !void {
    if (raw_path.len == 0) return;
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);
    if (raw_path[0] == '/') try current.append(allocator, '/');
    var parts = std.mem.splitScalar(u8, raw_path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (current.items.len > 1 and current.items[current.items.len - 1] != '/') {
            try current.append(allocator, '/');
        }
        try current.appendSlice(allocator, part);
        const path_z = try allocator.dupeZ(u8, current.items);
        defer allocator.free(path_z);
        if (c.mkdir(path_z.ptr, 0o755) != 0 and c.access(path_z.ptr, c.F_OK) != 0) {
            return error.MakePathFailed;
        }
    }
}

test "package manifests round-trip static evidence" {
    var manifest = Manifest.init(.xenia_halo3_startup, .x86_64, .little, 64, 1, 0x1111, 0x2222);
    manifest.static_plan_target_fingerprint = 0x3333;
    manifest.static_plan_target_count = 4;
    manifest.static_plan_referenced_mask = 0x5;
    manifest.static_plan_scanned_bytes = 1234;
    manifest.static_plan_direct_call_sites = 56;
    try std.testing.expect(manifest.addArtifact(.{
        .kind = .ready_contract,
        .architecture = .any,
        .flags = ArtifactFlags.static_evidence | ArtifactFlags.portable,
        .size = 36,
        .content_fingerprint = 0x4444,
    }));
    try std.testing.expect(manifest.addArtifact(.{
        .kind = .static_plan,
        .architecture = .x86_64,
        .size = 88,
        .content_fingerprint = 0x5555,
        .dependency_fingerprint = 0x3333,
    }));
    var encoded: [serialized_size]u8 = undefined;
    const bytes = encode(manifest, &encoded) orelse return error.TestUnexpectedResult;
    const decoded = decode(bytes) orelse return error.TestUnexpectedResult;
    try std.testing.expect(decoded.valid());
    try std.testing.expect(decoded.matchesStaticPlan(0x2222, 0x1111, 0x3333, 4));
    try std.testing.expectEqual(ArtifactKind.static_plan, decoded.artifacts[1].kind);
}

test "package manifests reject unsafe artifacts and corruption" {
    var unsafe = Manifest.init(.xenia_halo3_startup, .x86_64, .little, 64, 1, 1, 2);
    try std.testing.expect(unsafe.addArtifact(.{
        .kind = .static_plan,
        .flags = ArtifactFlags.guest_code,
        .size = 1,
        .content_fingerprint = 3,
    }));
    try std.testing.expect(!unsafe.valid());

    var safe = Manifest.init(.xenia_halo3_startup, .x86_64, .little, 64, 1, 1, 2);
    try std.testing.expect(safe.addArtifact(.{ .kind = .ready_contract, .size = 1, .content_fingerprint = 3 }));
    var encoded: [serialized_size]u8 = undefined;
    _ = encode(safe, &encoded) orelse return error.TestUnexpectedResult;
    encoded[20] ^= 1;
    try std.testing.expect(decode(&encoded) == null);
}

test "package target matching rejects a different image or target set" {
    var manifest = Manifest.init(.xenia_halo3_startup, .x86_64, .little, 64, 1, 1, 2);
    manifest.static_plan_target_fingerprint = 3;
    manifest.static_plan_target_count = 4;
    try std.testing.expect(manifest.addArtifact(.{ .kind = .static_plan, .size = 1, .content_fingerprint = 5 }));
    try std.testing.expect(manifest.matchesStaticPlan(2, 1, 3, 4));
    try std.testing.expect(!manifest.matchesStaticPlan(9, 1, 3, 4));
    try std.testing.expect(!manifest.matchesStaticPlan(2, 1, 8, 4));
}
