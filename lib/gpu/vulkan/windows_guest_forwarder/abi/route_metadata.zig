//! Immutable ABI facts only. Loader tokens and native capability checks
//! remain live. A hit verifies a copied name, including pointer reuse.
const std = @import("std");
const widths = @import("dll_win32_catalogue").vulkan.argument_widths;
pub const Facts = struct { owned: bool, signature: ?widths.Signature, float_count: usize };
const Slot = struct { key: usize = 0, name: [80]u8 = undefined, length: usize = 0, facts: Facts = undefined };
threadlocal var slots: [128]Slot = @splat(.{});
pub threadlocal var enabled = true; // differential fixture control only
pub const Counts = struct { lookups: u64 = 0, hits: u64 = 0, misses: u64 = 0 };
pub fn lookup(comptime classify: anytype, name: []const u8, counts: *Counts) Facts {
    counts.lookups +|= 1;
    if (enabled and name.len != 0 and name.len <= 80) {
        const key = @intFromPtr(name.ptr);
        const hash = (@as(u64, @intCast(key)) ^ @as(u64, @intCast(name.len))) *% 0x9E3779B97F4A7C15;
        const slot = &slots[@intCast(hash >> 57)];
        if (slot.key == key and slot.length == name.len and std.mem.eql(u8, slot.name[0..slot.length], name)) {
            counts.hits +|= 1;
            return slot.facts;
        }
        const facts = classify(name);
        slot.key = key;
        slot.length = name.len;
        @memcpy(slot.name[0..name.len], name);
        slot.facts = facts;
        counts.misses +|= 1;
        return facts;
    }
    counts.misses +|= 1;
    return classify(name);
}
