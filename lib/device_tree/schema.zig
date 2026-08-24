const std = @import("std");

pub const schema_version: u32 = 1;
pub const max_nodes: usize = 64;
pub const max_properties: usize = 256;

pub const Error = error{
    InvalidPath,
    InvalidName,
    MissingParent,
    DuplicateNode,
    DuplicateProperty,
    NodeCapacity,
    PropertyCapacity,
    TextTooLong,
    NodeNotFound,
    PropertyNotFound,
    PolicySourceRequired,
    ReadOnlyProperty,
    TypeMismatch,
    InvalidRoot,
};

pub const NodeKind = enum(u8) {
    root,
    cpu,
    memory,
    bus,
    gpu,
    adapter,
    queues,
    surface,
    consumer,
    runtime,
    // Subsystems with their own hardware boundaries. Appended rather than
    // inserted: the JSON form matches by name, but an ordinal shift would
    // still invalidate any stored tree that encoded the tag numerically.
    audio,
    input,
    timers,
    io,
    other,
};

pub const Status = enum(u8) {
    okay,
    disabled,
    reserved,
    failed,
};

/// Where a fact came from. This is part of the data rather than a comment so a
/// consumer can distinguish an observation from policy.
pub const Source = enum(u8) {
    compiled_profile,
    host_observation,
    backend_negotiation,
    user_policy,
};

pub const Mutability = enum(u8) {
    read_only,
    configurable,
};

pub fn BoundedText(comptime capacity: usize) type {
    return struct {
        bytes: [capacity]u8 = [_]u8{0} ** capacity,
        length: u16 = 0,

        const Self = @This();

        pub fn set(self: *Self, value: []const u8) Error!void {
            if (value.len > capacity) return error.TextTooLong;
            @memset(&self.bytes, 0);
            @memcpy(self.bytes[0..value.len], value);
            self.length = @intCast(value.len);
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.bytes[0..self.length];
        }

        pub fn eql(self: *const Self, value: []const u8) bool {
            return std.mem.eql(u8, self.slice(), value);
        }
    };
}

pub const ProfileName = BoundedText(64);
pub const NodePath = BoundedText(128);
pub const PropertyName = BoundedText(64);
pub const PropertyText = BoundedText(160);

pub const Range = struct {
    start: u64,
    length: u64,
};

pub const Value = union(enum) {
    boolean: bool,
    unsigned: u64,
    signed: i64,
    text: PropertyText,
    range: Range,

    pub fn fromText(text: []const u8) Error!Value {
        var result = PropertyText{};
        try result.set(text);
        return .{ .text = result };
    }
};

pub const Node = struct {
    path: NodePath = .{},
    kind: NodeKind = .other,
    status: Status = .okay,
    source: Source = .compiled_profile,
};

pub const Property = struct {
    node_index: u16 = 0,
    name: PropertyName = .{},
    value: Value = .{ .boolean = false },
    source: Source = .compiled_profile,
    mutability: Mutability = .read_only,
};

/// A bounded, allocation-free hardware description. It is intentionally a
/// description and policy container only: there are no methods for MMIO,
/// interrupts, command submission, or guest-state mutation.
pub const Tree = struct {
    version: u32 = schema_version,
    revision: u64 = 0,
    profile: ProfileName = .{},
    nodes: [max_nodes]Node = [_]Node{.{}} ** max_nodes,
    properties: [max_properties]Property = [_]Property{.{}} ** max_properties,
    node_count: u16 = 0,
    property_count: u16 = 0,

    pub fn init(profile_name: []const u8) Error!Tree {
        var result = Tree{};
        try result.profile.set(profile_name);
        _ = try result.addNode("/", .root, .okay, .compiled_profile);
        return result;
    }

    pub fn addNode(
        self: *Tree,
        path: []const u8,
        kind: NodeKind,
        status: Status,
        source: Source,
    ) Error!u16 {
        if (!validPath(path)) return error.InvalidPath;
        if (self.findNode(path) != null) return error.DuplicateNode;
        if (self.node_count >= max_nodes) return error.NodeCapacity;
        if (!std.mem.eql(u8, path, "/")) {
            const parent = parentPath(path) orelse return error.InvalidPath;
            if (self.findNode(parent) == null) return error.MissingParent;
        } else if (self.node_count != 0 or kind != .root) {
            return error.InvalidRoot;
        }

        const index = self.node_count;
        var node = Node{ .kind = kind, .status = status, .source = source };
        try node.path.set(path);
        self.nodes[index] = node;
        self.node_count += 1;
        self.revision +|= 1;
        return index;
    }

    pub fn setProperty(
        self: *Tree,
        node_path: []const u8,
        name: []const u8,
        value: Value,
        source: Source,
        mutability: Mutability,
    ) Error!void {
        if (!validPropertyName(name)) return error.InvalidName;
        const node_index = self.findNode(node_path) orelse return error.NodeNotFound;
        if (self.findPropertyIndex(node_index, name) != null) return error.DuplicateProperty;
        if (self.property_count >= max_properties) return error.PropertyCapacity;

        const index = self.property_count;
        var entry = Property{
            .node_index = node_index,
            .value = value,
            .source = source,
            .mutability = mutability,
        };
        try entry.name.set(name);
        self.properties[index] = entry;
        self.property_count += 1;
        self.revision +|= 1;
    }

    pub fn findNode(self: *const Tree, path: []const u8) ?u16 {
        for (self.nodes[0..self.node_count], 0..) |*node, index| {
            if (node.path.eql(path)) return @intCast(index);
        }
        return null;
    }

    pub fn property(self: *const Tree, node_path: []const u8, name: []const u8) ?*const Property {
        const node_index = self.findNode(node_path) orelse return null;
        const index = self.findPropertyIndex(node_index, name) orelse return null;
        return &self.properties[index];
    }

    /// Applies policy without allowing it to impersonate observed hardware.
    /// The base tree decides which keys are configurable and their value type.
    pub fn applyPolicy(self: *Tree, policy: *const Tree) Error!void {
        for (policy.properties[0..policy.property_count]) |incoming| {
            if (incoming.source != .user_policy) return error.PolicySourceRequired;
            const incoming_node = &policy.nodes[incoming.node_index];
            const target_node = self.findNode(incoming_node.path.slice()) orelse return error.NodeNotFound;
            const target_index = self.findPropertyIndex(target_node, incoming.name.slice()) orelse
                return error.PropertyNotFound;
            var target = &self.properties[target_index];
            if (target.mutability != .configurable) return error.ReadOnlyProperty;
            if (std.meta.activeTag(target.value) != std.meta.activeTag(incoming.value)) return error.TypeMismatch;
            target.value = incoming.value;
            target.source = .user_policy;
            self.revision +|= 1;
        }
    }

    pub fn validate(self: *const Tree) Error!void {
        if (self.version != schema_version or self.node_count == 0) return error.InvalidRoot;
        if (!self.nodes[0].path.eql("/") or self.nodes[0].kind != .root) return error.InvalidRoot;
        for (self.nodes[1..self.node_count]) |*node| {
            if (!validPath(node.path.slice())) return error.InvalidPath;
            const parent = parentPath(node.path.slice()) orelse return error.InvalidPath;
            if (self.findNode(parent) == null) return error.MissingParent;
        }
        for (self.properties[0..self.property_count]) |*entry| {
            if (entry.node_index >= self.node_count) return error.NodeNotFound;
            if (!validPropertyName(entry.name.slice())) return error.InvalidName;
        }
    }

    /// Stable non-cryptographic identity for diagnostics and handshake logs.
    pub fn fingerprint(self: *const Tree) u64 {
        var hash: u64 = 0xcbf2_9ce4_8422_2325;
        hashBytes(&hash, self.profile.slice());
        hashInteger(&hash, self.version);
        for (self.nodes[0..self.node_count]) |*node| {
            hashBytes(&hash, node.path.slice());
            hashInteger(&hash, @intFromEnum(node.kind));
            hashInteger(&hash, @intFromEnum(node.status));
            hashInteger(&hash, @intFromEnum(node.source));
        }
        for (self.properties[0..self.property_count]) |*entry| {
            hashInteger(&hash, entry.node_index);
            hashBytes(&hash, entry.name.slice());
            hashInteger(&hash, @intFromEnum(entry.source));
            hashInteger(&hash, @intFromEnum(entry.mutability));
            hashValue(&hash, entry.value);
        }
        return hash;
    }

    fn findPropertyIndex(self: *const Tree, node_index: u16, name: []const u8) ?u16 {
        for (self.properties[0..self.property_count], 0..) |*entry, index| {
            if (entry.node_index == node_index and entry.name.eql(name)) return @intCast(index);
        }
        return null;
    }
};

fn validPath(path: []const u8) bool {
    if (path.len == 0 or path[0] != '/') return false;
    if (std.mem.eql(u8, path, "/")) return true;
    if (path[path.len - 1] == '/' or std.mem.indexOf(u8, path, "//") != null) return false;
    var segments = std.mem.splitScalar(u8, path[1..], '/');
    while (segments.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return false;
    }
    return true;
}

fn parentPath(path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, path, "/")) return null;
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return null;
    return if (slash == 0) "/" else path[0..slash];
}

fn validPropertyName(name: []const u8) bool {
    return name.len != 0 and
        std.mem.indexOfScalar(u8, name, '/') == null and
        !std.mem.eql(u8, name, ".") and
        !std.mem.eql(u8, name, "..");
}

fn hashBytes(hash: *u64, bytes: []const u8) void {
    for (bytes) |byte| {
        hash.* ^= byte;
        hash.* *%= 0x0000_0100_0000_01b3;
    }
    hash.* ^= 0xff;
    hash.* *%= 0x0000_0100_0000_01b3;
}

fn hashInteger(hash: *u64, value: anytype) void {
    var remaining: u64 = @intCast(value);
    for (0..8) |_| {
        hash.* ^= @as(u8, @truncate(remaining));
        hash.* *%= 0x0000_0100_0000_01b3;
        remaining >>= 8;
    }
}

fn hashValue(hash: *u64, value: Value) void {
    hashInteger(hash, @intFromEnum(std.meta.activeTag(value)));
    switch (value) {
        .boolean => |item| hashInteger(hash, @intFromBool(item)),
        .unsigned => |item| hashInteger(hash, item),
        .signed => |item| hashInteger(hash, @as(u64, @bitCast(item))),
        .text => |*item| hashBytes(hash, item.slice()),
        .range => |item| {
            hashInteger(hash, item.start);
            hashInteger(hash, item.length);
        },
    }
}

test "tree preserves hierarchy and rejects a read-only policy override" {
    var tree = try Tree.init("test");
    _ = try tree.addNode("/gpu", .gpu, .okay, .backend_negotiation);
    try tree.setProperty("/gpu", "backend", try Value.fromText("vulkan"), .backend_negotiation, .read_only);
    try tree.setProperty("/gpu", "validation", .{ .boolean = false }, .compiled_profile, .configurable);
    try tree.validate();

    var policy = try Tree.init("policy");
    _ = try policy.addNode("/gpu", .gpu, .okay, .user_policy);
    try policy.setProperty("/gpu", "validation", .{ .boolean = true }, .user_policy, .configurable);
    try tree.applyPolicy(&policy);
    try std.testing.expect(tree.property("/gpu", "validation").?.value.boolean);

    var invalid = try Tree.init("invalid-policy");
    _ = try invalid.addNode("/gpu", .gpu, .okay, .user_policy);
    try invalid.setProperty("/gpu", "backend", try Value.fromText("metal"), .user_policy, .configurable);
    try std.testing.expectError(error.ReadOnlyProperty, tree.applyPolicy(&invalid));
}

test "tree fingerprint is independent of its address" {
    var first = try Tree.init("stable");
    _ = try first.addNode("/memory", .memory, .okay, .host_observation);
    try first.setProperty("/memory", "page-bytes", .{ .unsigned = 4096 }, .host_observation, .read_only);
    const second = first;
    try std.testing.expectEqual(first.fingerprint(), second.fingerprint());
}
