const std = @import("std");
const schema = @import("schema.zig");

const File = struct {
    schema_version: u32,
    profile: []const u8,
    nodes: []const FileNode,
};

const FileNode = struct {
    path: []const u8,
    kind: schema.NodeKind,
    status: schema.Status = .okay,
    source: schema.Source = .compiled_profile,
    properties: []const FileProperty = &.{},
};

const ValueKind = enum { boolean, unsigned, signed, text, range };

const FileProperty = struct {
    name: []const u8,
    value_kind: ValueKind,
    boolean_value: ?bool = null,
    unsigned_value: ?u64 = null,
    signed_value: ?i64 = null,
    text_value: ?[]const u8 = null,
    range_start: ?u64 = null,
    range_length: ?u64 = null,
    source: schema.Source = .compiled_profile,
    mutability: schema.Mutability = .read_only,
};

pub fn loadJson(allocator: std.mem.Allocator, bytes: []const u8) !schema.Tree {
    const parsed = try std.json.parseFromSlice(File, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value.schema_version != schema.schema_version) return error.UnsupportedSchemaVersion;

    var tree = try schema.Tree.init(parsed.value.profile);
    for (parsed.value.nodes) |node| {
        if (std.mem.eql(u8, node.path, "/")) {
            if (node.kind != .root) return error.InvalidRoot;
            tree.nodes[0].status = node.status;
            tree.nodes[0].source = node.source;
        } else {
            _ = try tree.addNode(node.path, node.kind, node.status, node.source);
        }
        for (node.properties) |property| {
            try tree.setProperty(
                node.path,
                property.name,
                try fileValue(property),
                property.source,
                property.mutability,
            );
        }
    }
    try tree.validate();
    return tree;
}

fn fileValue(property: FileProperty) !schema.Value {
    const scalar_count: usize = @intFromBool(property.boolean_value != null) +
        @as(usize, @intFromBool(property.unsigned_value != null)) +
        @as(usize, @intFromBool(property.signed_value != null)) +
        @as(usize, @intFromBool(property.text_value != null));
    const has_range_start = property.range_start != null;
    const has_range_length = property.range_length != null;
    if (has_range_start != has_range_length) return error.IncompleteRange;
    const field_count = scalar_count + @as(usize, @intFromBool(has_range_start));
    if (field_count != 1) return error.AmbiguousValue;

    return switch (property.value_kind) {
        .boolean => if (property.boolean_value) |value| .{ .boolean = value } else error.TypeMismatch,
        .unsigned => if (property.unsigned_value) |value| .{ .unsigned = value } else error.TypeMismatch,
        .signed => if (property.signed_value) |value| .{ .signed = value } else error.TypeMismatch,
        .text => if (property.text_value) |value| try schema.Value.fromText(value) else error.TypeMismatch,
        .range => if (property.range_start) |start| .{
            .range = .{ .start = start, .length = property.range_length.? },
        } else error.TypeMismatch,
    };
}

test "JSON format owns parsed strings and preserves provenance" {
    const text =
        \\{
        \\  "schema_version": 1,
        \\  "profile": "unit-test",
        \\  "nodes": [{
        \\    "path": "/",
        \\    "kind": "root",
        \\    "properties": [{
        \\      "name": "safe",
        \\      "value_kind": "boolean",
        \\      "boolean_value": true,
        \\      "source": "compiled_profile",
        \\      "mutability": "read_only"
        \\    }]
        \\  }]
        \\}
    ;
    const tree = try loadJson(std.testing.allocator, text);
    try std.testing.expect(tree.profile.eql("unit-test"));
    try std.testing.expect(tree.property("/", "safe").?.value.boolean);
    try std.testing.expectEqual(schema.Source.compiled_profile, tree.property("/", "safe").?.source);
}

test "JSON format rejects mixed value representations" {
    const text =
        \\{"schema_version":1,"profile":"bad","nodes":[{"path":"/","kind":"root","properties":[
        \\{"name":"ambiguous","value_kind":"boolean","boolean_value":true,"unsigned_value":1}
        \\]}]}
    ;
    try std.testing.expectError(error.AmbiguousValue, loadJson(std.testing.allocator, text));
}
