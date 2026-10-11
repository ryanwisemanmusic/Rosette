//! VPTEST examines all bits; VTESTPS/PD examine only each floating lane's sign.
const std = @import("std");
const Op = @import("types.zig").Op;

pub fn predicates(op: Op, lhs: [16]u8, rhs: [16]u8) struct { zf: bool, cf: bool } {
    var zf = true;
    var cf = true;
    for (lhs, rhs, 0..) |a, b, i| {
        const mask: u8 = switch (op) {
            .vtestps => if (i % 4 == 3) 0x80 else 0,
            .vtestpd => if (i % 8 == 7) 0x80 else 0,
            else => 0xFF,
        };
        zf = zf and (a & b & mask) == 0;
        cf = cf and (~a & b & mask) == 0;
    }
    return .{ .zf = zf, .cf = cf };
}

test "VTEST sign predicates ignore payload bits and VPTEST preserves them" {
    var a: [16]u8 = @splat(1);
    var b = a;
    try std.testing.expect(predicates(.vtestps, a, b).zf);
    try std.testing.expect(predicates(.vtestpd, a, b).zf);
    try std.testing.expect(!predicates(.vptest, a, b).zf);
    b[3] = 0x80;
    try std.testing.expect(!predicates(.vtestps, a, b).cf);
    try std.testing.expect(predicates(.vtestpd, a, b).cf);
    a[7] = 0x80;
    b[7] = 0x80;
    try std.testing.expect(!predicates(.vtestpd, a, b).zf);
    try std.testing.expect(predicates(.vtestpd, a, b).cf);
}
