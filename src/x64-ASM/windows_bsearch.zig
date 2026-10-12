const std = @import("std");

pub const SYNTHETIC_BSEARCH_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF68;

pub fn tryFunction(state: anytype, name: []const u8, direct_return_rip: ?u64, comptime argument: anytype) bool {
    if (!std.mem.eql(u8, name, "bsearch")) return false;

    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "beginWindowsBsearch")) {
        return state.beginWindowsBsearch(
            argument(state, 0, direct_return_rip),
            argument(state, 1, direct_return_rip),
            argument(state, 2, direct_return_rip),
            argument(state, 3, direct_return_rip),
            argument(state, 4, direct_return_rip),
            direct_return_rip,
        );
    }
    return false;
}
