//! Restore FSI pixel-center coordinates while retaining sample lanes and EDRAM.
//!
//! Xenia adds SampleRateShading for SampleMask even when its shader has no
//! sample-frequency inputs. SPIRV-Cross 1.3.275 treats this capability alone
//! as a request to run at sample frequency, adds SampleId, shifts FragCoord,
//! and narrows coverage. SampleMask itself is legal with Shader in SPIR-V 1.3+.
//! The live correction centers loads, preserving Z/W and all capabilities.
//! Capability removal is an exploratory negative control; it fails native
//! atomic write parity and must not be used by the live path. Actual Sample
//! inputs / SampleId / SamplePosition retain their original coordinates.
const std = @import("std");

pub const Reason = enum { changed, not_candidate, explicit_sample_input, complex_decorations, invalid };
pub const Result = struct {
    words: []u32 = &.{},
    reason: Reason = .not_candidate,
    removed: u32 = 0,
    centered_loads: u32 = 0,
};

/// Restore the coordinate convention without changing sample-rate execution.
/// MoltenVK's attachmentless atomic path may still invoke once per sample even
/// without SampleRateShading. Removing the capability then exposes the entire
/// coverage mask to each invocation and duplicates writes. Keep it; center
/// only the X/Y values loaded from an undecorated FragCoord input instead.
pub fn centerCoordinates(allocator: std.mem.Allocator, words: []const u32) !Result {
    if (words.len < 5 or words[0] != 0x07230203 or words[3] == 0 or words[3] > 1 << 20) return .{ .reason = .invalid };
    // Reuse the conservative candidate admission; discard its exploratory
    // output. The live transform never removes this capability.
    const admission = try normalize(allocator, words);
    defer allocator.free(admission.words);
    if (admission.reason != .changed) return .{ .reason = admission.reason };
    const Pointer = struct { component: i8 = -2 }; // -2 unrelated, -1 whole vec4.
    const pointers = try allocator.alloc(Pointer, words[3]);
    defer allocator.free(pointers);
    @memset(pointers, .{});
    var frag: u32 = 0;
    var float_type: u32 = 0;
    var vector_type: u32 = 0;
    var glsl: u32 = 0;
    var first_function: usize = 0;
    var cursor: usize = 5;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        const op: u16 = @truncate(words[cursor]);
        const w = words[cursor .. cursor + count]; // Admission verified framing.
        if (op == 71 and count == 4 and w[2] == 11 and w[3] == 15) frag = w[1];
        if (op == 11 and count >= 3) {
            const name = std.mem.sliceAsBytes(w[2..]);
            if (name.len >= 13 and std.mem.eql(u8, name[0..13], "GLSL.std.450\x00")) glsl = w[1];
        }
        if (op == 22 and count == 3 and w[2] == 32) float_type = w[1];
        if (op == 54 and first_function == 0) first_function = cursor;
        cursor += count;
    }
    if (frag == 0 or frag >= pointers.len or float_type == 0 or glsl == 0 or first_function == 0) return .{};
    // A Sample decoration on any input already declined admission.
    pointers[frag].component = -1;
    cursor = 5;
    var loads: u32 = 0;
    var vector_loads = false;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        const op: u16 = @truncate(words[cursor]);
        const w = words[cursor .. cursor + count];
        if (op == 23 and count == 4 and w[2] == float_type and w[3] == 4) vector_type = w[1];
        if ((op == 65 or op == 66) and count >= 4 and w[3] < pointers.len and pointers[w[3]].component != -2) {
            if (count != 5 or pointers[w[3]].component != -1 or w[2] >= pointers.len) return .{ .reason = .complex_decorations };
            const index = constantIndex(words, w[4]) orelse return .{ .reason = .complex_decorations };
            if (index > 3) return .{ .reason = .complex_decorations };
            pointers[w[2]].component = @intCast(index);
        }
        if (op == 83 and count == 4 and w[2] < pointers.len and w[3] < pointers.len) pointers[w[2]] = pointers[w[3]];
        // Do not partially center a module whose input pointers escape through
        // a form outside this bounded provenance walk.
        if (op == 57 or op == 245 or op == 169 or op == 124 or op == 67 or op == 70 or op == 63) {
            const start: usize = switch (op) {
                57 => 4, // FunctionCall arguments.
                169 => 4, // Select pointer alternatives.
                63 => 1, // CopyMemory source/destination.
                else => 3,
            };
            for (w[@min(start, w.len)..]) |operand| {
                if (operand < pointers.len and pointers[operand].component != -2) return .{ .reason = .complex_decorations };
            }
        }
        if (op == 61 and count >= 4 and w[3] < pointers.len) {
            const component = pointers[w[3]].component;
            if (component == -1) {
                if (w[1] != vector_type or vector_type == 0) return .{ .reason = .complex_decorations };
                vector_loads = true;
                loads += 1;
            } else if (component == 0 or component == 1) {
                if (w[1] != float_type) return .{ .reason = .complex_decorations };
                loads += 1;
            }
        }
        cursor += count;
    }
    if (loads == 0) return .{};
    var output: std.ArrayList(u32) = .empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator, words[0..5]);
    var id = words[3];
    const half_id = id;
    id += 1;
    const half_vector = if (vector_loads) blk: {
        const next = id;
        id += 1;
        break :blk next;
    } else 0;
    cursor = 5;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        const op: u16 = @truncate(words[cursor]);
        const w = words[cursor .. cursor + count];
        if (cursor == first_function) {
            try output.appendSlice(allocator, &.{ 0x0004002b, float_type, half_id, 0x3f000000 });
            if (vector_loads) try output.appendSlice(allocator, &.{ 0x0007002c, vector_type, half_vector, half_id, half_id, half_id, half_id });
        }
        const component: i8 = if (op == 61 and count >= 4 and w[3] < pointers.len) pointers[w[3]].component else -2;
        if (component == -1 or component == 0 or component == 1) {
            const raw = id;
            const floored = id + 1;
            const centered = id + 2;
            id += if (component == -1) @as(u32, 3) else 2;
            try output.appendSlice(allocator, w);
            output.items[output.items.len - count + 2] = raw;
            try output.appendSlice(allocator, &.{ 0x0006000c, w[1], floored, glsl, 8, raw }); // Floor.
            try output.appendSlice(allocator, &.{ 0x00050081, w[1], if (component == -1) centered else w[2], floored, if (component == -1) half_vector else half_id });
            if (component == -1) {
                // X/Y from centered; Z/W bit-for-bit from the original load.
                try output.appendSlice(allocator, &.{ 0x0009004f, vector_type, w[2], centered, raw, 0, 1, 6, 7 });
            }
        } else try output.appendSlice(allocator, w);
        cursor += count;
    }
    output.items[3] = id;
    return .{ .words = try output.toOwnedSlice(allocator), .reason = .changed, .centered_loads = loads };
}

fn constantIndex(words: []const u32, id: u32) ?u32 {
    var cursor: usize = 5;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        if (@as(u16, @truncate(words[cursor])) == 43 and count == 4 and words[cursor + 2] == id) return words[cursor + 3];
        cursor += count;
    }
    return null;
}

pub fn normalize(allocator: std.mem.Allocator, words: []const u32) !Result {
    if (words.len < 5 or words[0] != 0x07230203) return .{ .reason = .invalid };
    // Only versions whose SampleMask is covered by the Shader capability.
    if (words[1] < 0x00010300 or words[1] > 0x00010600) return .{};
    var cursor: usize = 5;
    var entries: u32 = 0;
    var fragment = false;
    var shader = false;
    var rate: u32 = 0;
    var interlock = false;
    var mask_id: u32 = 0;
    var input_mask = false;
    var begin: u32 = 0;
    var end: u32 = 0;
    var explicit = false;
    var complex = false;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        const op: u16 = @truncate(words[cursor]);
        if (count == 0 or count > words.len - cursor) return .{ .reason = .invalid };
        const w = words[cursor .. cursor + count];
        switch (op) {
            15 => { // OpEntryPoint.
                if (count < 4) return .{ .reason = .invalid };
                entries += 1;
                fragment = w[1] == 4;
            },
            17 => { // OpCapability.
                if (count != 2) return .{ .reason = .invalid };
                shader = shader or w[1] == 1;
                if (w[1] == 35) rate += 1;
                interlock = interlock or w[1] == 5363 or w[1] == 5378;
            },
            71 => { // OpDecorate.
                if (count < 3) return .{ .reason = .invalid };
                if (w[2] == 17) { // Sample.
                    if (count != 3) return .{ .reason = .invalid };
                    explicit = true;
                }
                if (w[2] == 11) { // BuiltIn.
                    if (count != 4) return .{ .reason = .invalid };
                    if (w[3] == 18 or w[3] == 19) explicit = true;
                    if (w[3] == 20) {
                        if (mask_id != 0 and mask_id != w[1]) complex = true;
                        mask_id = w[1];
                    }
                }
            },
            72 => { // OpMemberDecorate.
                if (count < 4) return .{ .reason = .invalid };
                if (w[3] == 17) {
                    if (count != 4) return .{ .reason = .invalid };
                    explicit = true;
                }
                if (w[3] == 11) {
                    if (count != 5) return .{ .reason = .invalid };
                    if (w[4] == 18 or w[4] == 19) explicit = true;
                    // Struct-member masks are outside this narrow route.
                    if (w[4] == 20) complex = true;
                }
            },
            73, 74, 75, 332 => complex = true, // Decoration groups / DecorateId.
            59 => { // OpVariable: decorations precede variables.
                if (count < 4) return .{ .reason = .invalid };
                if (w[2] == mask_id and w[3] == 1) input_mask = true;
            },
            5364 => begin += 1,
            5365 => end += 1,
            else => {},
        }
        cursor += count;
    }
    if (entries != 1 or !fragment or !shader or rate == 0 or !interlock or !input_mask or begin == 0 or end == 0) return .{};
    if (explicit) return .{ .reason = .explicit_sample_input };
    if (complex) return .{ .reason = .complex_decorations };
    const output = try allocator.alloc(u32, words.len - 2 * rate);
    @memcpy(output[0..5], words[0..5]);
    cursor = 5;
    var dest: usize = 5;
    while (cursor < words.len) {
        const count: usize = words[cursor] >> 16;
        if (@as(u16, @truncate(words[cursor])) != 17 or words[cursor + 1] != 35) {
            @memcpy(output[dest .. dest + count], words[cursor .. cursor + count]);
            dest += count;
        }
        cursor += count;
    }
    std.debug.assert(dest == output.len);
    return .{ .words = output, .reason = .changed, .removed = rate };
}

fn fixture() [31]u32 {
    return .{
        0x07230203,        0x00010500,        0,          16, 0,
        0x00020011,        1,                 0x00020011, 35, 0x00020011,
        5363,              0x0006000f,        4,          1,  0x6e69616d,
        0,                 6,                 0x00040047, 6,  11,
        20,                0x0004003b,        4,          6,  1,
        0x00010000 | 5364, 0x00010000 | 5365, 0x00040047, 7,  30,
        0,
    };
}

test "FSI unused sample capability is removed without changing instructions or ids" {
    const source = fixture();
    const result = try normalize(std.testing.allocator, &source);
    defer std.testing.allocator.free(result.words);
    try std.testing.expectEqual(Reason.changed, result.reason);
    try std.testing.expectEqual(@as(u32, 1), result.removed);
    try std.testing.expectEqualSlices(u32, source[0..7], result.words[0..7]);
    try std.testing.expectEqualSlices(u32, source[9..], result.words[7..]);
    const again = try normalize(std.testing.allocator, result.words);
    try std.testing.expectEqual(Reason.not_candidate, again.reason);
}

test "FSI actual SampleId SamplePosition and sample interpolation preserve rate" {
    for ([_]u32{ 18, 19 }) |builtin| {
        var source = fixture();
        source[30] = builtin;
        // The last instruction's operands are target=7, decoration=11.
        source[29] = 11;
        source[28] = 7;
        const result = try normalize(std.testing.allocator, &source);
        try std.testing.expectEqual(Reason.explicit_sample_input, result.reason);
    }
    var source = fixture();
    source[27] = 0x00030047;
    source[29] = 17;
    source[30] = 0x00010000; // OpNop follows the three-word decoration.
    const result = try normalize(std.testing.allocator, &source);
    try std.testing.expectEqual(Reason.explicit_sample_input, result.reason);
}

test "FSI sample normalization refuses hidden decorations malformed and other stages" {
    var source = fixture();
    source[27] = 0x0004004a; // GroupDecorate.
    try std.testing.expectEqual(Reason.complex_decorations, (try normalize(std.testing.allocator, &source)).reason);
    source = fixture();
    source[12] = 0;
    try std.testing.expectEqual(Reason.not_candidate, (try normalize(std.testing.allocator, &source)).reason);
    source = fixture();
    source[1] = 0x00010000;
    try std.testing.expectEqual(Reason.not_candidate, (try normalize(std.testing.allocator, &source)).reason);
    source = fixture();
    source[27] = 0;
    try std.testing.expectEqual(Reason.invalid, (try normalize(std.testing.allocator, &source)).reason);
    source = fixture();
    source[24] = 3; // Output mask rather than input.
    try std.testing.expectEqual(Reason.not_candidate, (try normalize(std.testing.allocator, &source)).reason);
}
