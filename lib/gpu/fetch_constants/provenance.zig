//! Per-word write history for one aliased six-dword fetch slot.

const std = @import("std");

pub const WritePattern = enum {
    untouched,
    vertex_pair,
    texture_burst,
    mixed_or_partial,
};

pub const TextureFetchProvenance = struct {
    write_sequence: [6]u64 = [_]u64{0} ** 6,

    pub fn writtenMask(self: TextureFetchProvenance) u6 {
        var mask: u6 = 0;
        for (self.write_sequence, 0..) |sequence, word| {
            if (sequence != 0) mask |= @as(u6, 1) << @intCast(word);
        }
        return mask;
    }

    pub fn latestWrite(self: TextureFetchProvenance) u64 {
        var latest: u64 = 0;
        for (self.write_sequence) |sequence| latest = @max(latest, sequence);
        return latest;
    }

    /// Classify only exact write shapes. A vertex descriptor is two adjacent
    /// dwords in the same aperture; a texture descriptor is six adjacent
    /// dwords. Anything else remains mixed/partial instead of being guessed.
    pub fn writePattern(self: TextureFetchProvenance) WritePattern {
        const mask = self.writtenMask();
        if (mask == 0) return .untouched;

        if (mask == 0b11_1111) {
            const first = self.write_sequence[0];
            for (self.write_sequence, 0..) |sequence, index| {
                if (sequence != first + @as(u64, @intCast(index))) return .mixed_or_partial;
            }
            return .texture_burst;
        }

        for (0..3) |pair_index| {
            const first_word = pair_index * 2;
            const pair_mask = @as(u6, 0b11) << @intCast(first_word);
            if (mask != pair_mask) continue;
            if (self.write_sequence[first_word] + 1 != self.write_sequence[first_word + 1]) {
                return .mixed_or_partial;
            }
            return .vertex_pair;
        }
        return .mixed_or_partial;
    }

    pub fn vertexPairIndex(self: TextureFetchProvenance) ?u2 {
        if (self.writePattern() != .vertex_pair) return null;
        for (0..3) |pair_index| {
            const first_word = pair_index * 2;
            const pair_mask = @as(u6, 0b11) << @intCast(first_word);
            if (self.writtenMask() == pair_mask) return @intCast(pair_index);
        }
        return null;
    }
};

test "fetch provenance preserves the word write mask and latest sequence" {
    const provenance = TextureFetchProvenance{ .write_sequence = .{ 0, 2, 0, 4, 0, 0 } };
    try std.testing.expectEqual(@as(u6, 0b001010), provenance.writtenMask());
    try std.testing.expectEqual(@as(u64, 4), provenance.latestWrite());
    try std.testing.expectEqual(WritePattern.mixed_or_partial, provenance.writePattern());
}

test "fetch provenance identifies exact vertex-pair and texture-burst writes" {
    const vertex = TextureFetchProvenance{ .write_sequence = .{ 0, 0, 0, 0, 8, 9 } };
    try std.testing.expectEqual(WritePattern.vertex_pair, vertex.writePattern());
    try std.testing.expectEqual(@as(?u2, 2), vertex.vertexPairIndex());

    const texture = TextureFetchProvenance{ .write_sequence = .{ 21, 22, 23, 24, 25, 26 } };
    try std.testing.expectEqual(WritePattern.texture_burst, texture.writePattern());
    try std.testing.expect(vertex.vertexPairIndex() != null);
    try std.testing.expectEqual(@as(?u2, null), texture.vertexPairIndex());
    try std.testing.expectEqual(WritePattern.untouched, (TextureFetchProvenance{}).writePattern());
}
