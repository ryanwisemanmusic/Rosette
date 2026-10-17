//! x86-64-route text ABI for successful Xenia PPC guest translation.
//!
//! This package is deliberately narrower than a heartbeat. Xenia emits the
//! event only after PPCFrontend::DefineFunction has assembled a guest function
//! into host code. Rosetta may therefore use it as external progress: a loop
//! that does not produce a new translated function cannot manufacture the
//! event by retiring more instructions.

const std = @import("std");

pub const host_architecture = "x86_64";
pub const host_codegen = "xbyak-x86_64";
pub const schema_version: u64 = 1;
pub const marker = "READY COMPILER: translation-progress";

pub const Event = struct {
    schema: u64,
    generation: u64,
    guest_function: u64,

    pub fn valid(self: Event) bool {
        return self.schema == schema_version and
            self.generation != 0 and
            self.guest_function != 0 and
            self.guest_function & 3 == 0;
    }
};

pub fn parse(line: []const u8) ?Event {
    if (std.mem.indexOf(u8, line, marker) == null) return null;
    const event = Event{
        .schema = field(line, "schema=") orelse return null,
        .generation = field(line, "generation=") orelse return null,
        .guest_function = field(line, "guest_function=") orelse return null,
    };
    return if (event.valid()) event else null;
}

fn field(line: []const u8, key: []const u8) ?u64 {
    var search: usize = 0;
    while (std.mem.indexOfPos(u8, line, search, key)) |found| {
        search = found + key.len;
        if (found != 0 and line[found - 1] > ' ') continue;
        const start = found + key.len;
        var end = start;
        while (end < line.len and line[end] > ' ') end += 1;
        if (end == start) return null;
        const value = line[start..end];
        if (value.len > 2 and value[0] == '0' and
            (value[1] == 'x' or value[1] == 'X'))
        {
            return std.fmt.parseInt(u64, value[2..], 16) catch return null;
        }
        return std.fmt.parseInt(u64, value, 10) catch return null;
    }
    return null;
}

/// Ordering is a pure admission rule; the runtime owns the last observed
/// generation and the counters that record accepted or rejected events.
pub fn generationAdvances(previous: u64, next: u64) bool {
    return next > previous;
}

test "the x86 package identifies its native route" {
    try std.testing.expectEqualStrings("x86_64", host_architecture);
    try std.testing.expectEqualStrings("xbyak-x86_64", host_codegen);
}

test "the parser accepts the Xenia PPC translation ABI" {
    const event = parse(
        "[xenia] i> READY COMPILER: translation-progress schema=1 generation=8 guest_function=0x82582cc8\n",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 1), event.schema);
    try std.testing.expectEqual(@as(u64, 8), event.generation);
    try std.testing.expectEqual(@as(u64, 0x8258_2cc8), event.guest_function);
}

test "malformed or non-guest events are rejected" {
    try std.testing.expect(parse("READY COMPILER: translation-progress schema=1 generation=0 guest_function=0x1000") == null);
    try std.testing.expect(parse("READY COMPILER: translation-progress schema=2 generation=1 guest_function=0x1000") == null);
    try std.testing.expect(parse("READY COMPILER: translation-progress schema=1 generation=1 guest_function=0x1001") == null);
    try std.testing.expect(parse("READY COMPILER: translation-progress schema=1 generation=1") == null);
}

test "generation ordering is a pure package decision" {
    try std.testing.expect(generationAdvances(4, 5));
    try std.testing.expect(!generationAdvances(4, 4));
    try std.testing.expect(!generationAdvances(5, 4));
}
