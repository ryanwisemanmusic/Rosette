//! Decode Xenos float16 EDRAM before the shipped full-resolve shaders apply
//! their exponent bias. FSI writes finite exponent-31 values; these exact
//! kernels otherwise interpret those values as IEEE half Infinity / NaN.
//! Ordinary texture loaders, destination packing and guest shaders are untouched.
const std = @import("std");

pub const Result = struct { words: []u32 = &.{}, unpacks: u32 = 0, name: []const u8 = "" };
const Identity = struct { name: []const u8, sha: []const u8 };
pub const identities = [_]Identity{
    .{ .name = "resolve_full_8bpp", .sha = "ce1512d5127005f76cdf9974b2c3bde778b556d74e3011f2b7c0a3ea59bdd547" },
    .{ .name = "resolve_full_8bpp_scaled", .sha = "eb3bcb34851f07de2232bf0dc313296a320871604e7e6350cc411c3aba6fa55e" },
    .{ .name = "resolve_full_16bpp", .sha = "59b0d58a1e55c85b4d1f1cfb72f21f981b6ee85c4bf202ce094943ba4f6e33fd" },
    .{ .name = "resolve_full_16bpp_scaled", .sha = "7df63aedb1052879ac512c3b63e56db865f3f9afaa40d1a3615f9a5a9d95d818" },
    .{ .name = "resolve_full_32bpp", .sha = "4a6efa2c1a8dafb3671cd672715161b63bf9185df5f7c7f7fc66d6bacb5d7b86" },
    .{ .name = "resolve_full_32bpp_scaled", .sha = "93054e1aa968bb40730d1ecae4ddea5da0803dfecceb08c1e142491ae774671f" },
    .{ .name = "resolve_full_64bpp", .sha = "e8908dd87fe8a9b3b59e627586aed32584df15ec6ba92bad9ab720939211f220" },
    .{ .name = "resolve_full_64bpp_scaled", .sha = "66c731cb4c5736b010c91ab8a6ac2a9a6d16baf4dbfda33928b3744aa063d1bf" },
    .{ .name = "resolve_full_128bpp", .sha = "490cb1f18736c0bbb8caad67bb9d85f40b1dc1996b4ac3b7df95291a1883bff9" },
    .{ .name = "resolve_full_128bpp_scaled", .sha = "9b062281ff2190d4e909fa06832844af8a87c84ec07eab1fd212497f24f33cd7" },
};

pub fn identify(words: []const u32) ?[]const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(std.mem.sliceAsBytes(words), &hash, .{});
    for (identities) |identity| {
        var expected: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&expected, identity.sha) catch unreachable;
        if (std.mem.eql(u8, &hash, &expected)) return identity.name;
    }
    return null;
}

pub fn rewrite(allocator: std.mem.Allocator, words: []const u32) !Result {
    const name = identify(words) orelse return .{};
    var result = try rewriteUnpacksForProbe(allocator, words);
    result.name = name;
    if (result.unpacks == 0) return error.ResolveContractChanged;
    return result;
}

/// Offline synthetic fixture entry only. The live entry above always requires
/// an exact original kernel hash; an arbitrary UnpackHalf2x16 is IEEE half.
pub fn rewriteUnpacksForProbe(allocator: std.mem.Allocator, words: []const u32) !Result {
    if (words.len < 5 or words[0] != 0x07230203 or words[3] == 0 or words[3] > 1 << 20) return error.InvalidModule;
    var glsl: u32 = 0;
    var uint_type: u32 = 0;
    var float_type: u32 = 0;
    var float2_type: u32 = 0;
    var bool_type: u32 = 0;
    var bool2_type: u32 = 0;
    var first_function: usize = 0;
    var unpacks: u32 = 0;
    var cursor: usize = 5;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        const op: u16 = @truncate(words[cursor]);
        if (count == 0 or count > words.len - cursor) return error.InvalidModule;
        const w = words[cursor .. cursor + count];
        if (op == 11 and count >= 3) {
            const name = std.mem.sliceAsBytes(w[2..]);
            if (std.mem.startsWith(u8, name, "GLSL.std.450\x00")) glsl = w[1];
        }
        if (op == 20 and count == 2) bool_type = w[1];
        if (op == 21 and count == 4 and w[2] == 32 and w[3] == 0) uint_type = w[1];
        if (op == 22 and count == 3 and w[2] == 32) float_type = w[1];
        if (op == 54 and first_function == 0) first_function = cursor;
        cursor += count;
    }
    if (glsl == 0 or uint_type == 0 or float_type == 0 or first_function == 0) return error.ResolveContractChanged;
    cursor = 5;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        const w = words[cursor .. cursor + count];
        if (@as(u16, @truncate(w[0])) == 23 and count == 4 and w[2] == float_type and w[3] == 2) float2_type = w[1];
        if (@as(u16, @truncate(w[0])) == 23 and count == 4 and w[2] == bool_type and w[3] == 2) bool2_type = w[1];
        cursor += count;
    }
    if (float2_type == 0) return error.ResolveContractChanged;
    cursor = 5;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        const w = words[cursor .. cursor + count];
        if (@as(u16, @truncate(w[0])) == 12 and count >= 5 and w[3] == glsl and w[4] == 62) {
            if (count != 6 or w[1] != float2_type) return error.ResolveContractChanged;
            unpacks += 1;
        }
        cursor += count;
    }
    if (unpacks == 0) return .{};
    var output: std.ArrayList(u32) = .empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator, words[0..5]);
    var id = words[3];
    const bool_new = bool_type == 0;
    if (bool_new) {
        bool_type = id;
        id += 1;
    }
    const bool2_new = bool2_type == 0;
    if (bool2_new) {
        bool2_type = id;
        id += 1;
    }
    const zero = id;
    const mask = id + 1;
    const shift = id + 2;
    const lower_sub = id + 3;
    const upper_sub = id + 4;
    const two = id + 5;
    const two2 = id + 6;
    id += 7;
    cursor = 5;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        const w = words[cursor .. cursor + count];
        if (cursor == first_function) {
            if (bool_new) try output.appendSlice(allocator, &.{ 0x00020014, bool_type });
            if (bool2_new) try output.appendSlice(allocator, &.{ 0x00040017, bool2_type, bool_type, 2 });
            for ([_][2]u32{ .{ zero, 0 }, .{ mask, 0x7c00 }, .{ shift, 16 }, .{ lower_sub, 0x0400 }, .{ upper_sub, 0x04000000 } }) |c| {
                try output.appendSlice(allocator, &.{ 0x0004002b, uint_type, c[0], c[1] });
            }
            try output.appendSlice(allocator, &.{ 0x0004002b, float_type, two, 0x40000000 });
            try output.appendSlice(allocator, &.{ 0x0005002c, float2_type, two2, two, two });
        }
        if (@as(u16, @truncate(w[0])) == 12 and count == 6 and w[3] == glsl and w[4] == 62) {
            const low = id;
            const high_word = id + 1;
            const high = id + 2;
            const low_extended = id + 3;
            const high_extended = id + 4;
            const low_dec = id + 5;
            const high_dec = id + 6;
            const decrement = id + 7;
            const reduced = id + 8;
            const standard = id + 9;
            const half_reduced = id + 10;
            const extended = id + 11;
            const lanes = id + 12;
            id += 13;
            try output.appendSlice(allocator, &.{ 0x000500c7, uint_type, low, w[5], mask });
            try output.appendSlice(allocator, &.{ 0x000500c2, uint_type, high_word, w[5], shift });
            try output.appendSlice(allocator, &.{ 0x000500c7, uint_type, high, high_word, mask });
            try output.appendSlice(allocator, &.{ 0x000500aa, bool_type, low_extended, low, mask });
            try output.appendSlice(allocator, &.{ 0x000500aa, bool_type, high_extended, high, mask });
            try output.appendSlice(allocator, &.{ 0x000600a9, uint_type, low_dec, low_extended, lower_sub, zero });
            try output.appendSlice(allocator, &.{ 0x000600a9, uint_type, high_dec, high_extended, upper_sub, zero });
            try output.appendSlice(allocator, &.{ 0x000500c5, uint_type, decrement, low_dec, high_dec });
            try output.appendSlice(allocator, &.{ 0x00050082, uint_type, reduced, w[5], decrement });
            try output.appendSlice(allocator, &.{ 0x0006000c, float2_type, standard, glsl, 62, w[5] });
            try output.appendSlice(allocator, &.{ 0x0006000c, float2_type, half_reduced, glsl, 62, reduced });
            try output.appendSlice(allocator, &.{ 0x00050085, float2_type, extended, half_reduced, two2 });
            try output.appendSlice(allocator, &.{ 0x00050050, bool2_type, lanes, low_extended, high_extended });
            try output.appendSlice(allocator, &.{ 0x000600a9, float2_type, w[2], lanes, extended, standard });
        } else try output.appendSlice(allocator, w);
        cursor += count;
    }
    output.items[3] = id;
    return .{ .words = try output.toOwnedSlice(allocator), .unpacks = unpacks };
}

test "HDR resolve refuses arbitrary modules and changed identities" {
    const result = try rewrite(std.testing.allocator, &.{ 0x07230203, 0x00010500, 0, 1, 0 });
    try std.testing.expectEqual(@as(usize, 0), result.words.len);
    try std.testing.expectError(error.InvalidModule, rewriteUnpacksForProbe(std.testing.allocator, &.{ 0x07230203, 0x00010500, 0, 1, 0, 0 }));
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectEqual(@as(usize, 0), (try rewrite(failing.allocator(), &.{})).words.len);
}

test "HDR resolve probe retains original words and fails closed on allocation" {
    const words = [_]u32{
        0x07230203, 0x00010500, 0,          32,         0,
        0x0006000b, 17,         0x4c534c47, 0x6474732e, 0x3035342e,
        0,          0x00020014, 3,          0x00040017, 4,
        3,          2,          0x00040015, 5,          32,
        0,          0x00030016, 6,          32,         0x00040017,
        7,          6,          2,          0x0004002b, 5,
        8,          0x7c00fc00, 0x00050036, 1,          10,
        0,          2,          0x000200f8, 11,         0x0006000c,
        7,          12,         17,         62,         8,
        0x000100fd, 0x00010038,
    };
    const before = words;
    const corrected = try rewriteUnpacksForProbe(std.testing.allocator, &words);
    defer std.testing.allocator.free(corrected.words);
    try std.testing.expectEqual(@as(u32, 1), corrected.unpacks);
    try std.testing.expect(corrected.words.len > words.len);
    try std.testing.expectEqualSlices(u32, &before, &words);
    // Native production admission must never treat this arbitrary half
    // conversion (or an already corrected module) as an EDRAM resolve.
    try std.testing.expect(identify(&words) == null);
    try std.testing.expect(identify(corrected.words) == null);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, rewriteUnpacksForProbe(failing.allocator(), &words));
}
