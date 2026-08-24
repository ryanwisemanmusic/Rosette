//! libc++ `__thread_struct` ABI classification.
//!
//! Rosette owns guest pthread scheduling, so libc++'s per-thread bookkeeping
//! object is modeled as zero-initialized opaque storage. Its destructor must be
//! modeled by the same boundary; forwarding construction but losing D1/D2
//! splits ownership and is especially visible when `std::thread` creation
//! reports an error.

const std = @import("std");
const thread_struct_abi = @import("libcpp_thread_abi");

pub const layout = thread_struct_abi.layout;
pub const storage_size = thread_struct_abi.storage_size;
pub const storage_alignment = thread_struct_abi.storage_alignment;

pub const Operation = enum {
    construct,
    destroy,
};

pub fn classify(symbol: []const u8) ?Operation {
    if (std.mem.indexOf(u8, symbol, "__thread_structC1Ev") != null or
        std.mem.indexOf(u8, symbol, "__thread_structC2Ev") != null)
    {
        return .construct;
    }
    if (std.mem.indexOf(u8, symbol, "__thread_structD1Ev") != null or
        std.mem.indexOf(u8, symbol, "__thread_structD2Ev") != null)
    {
        return .destroy;
    }
    return null;
}

test "constructor and destructor variants share one ownership model" {
    try std.testing.expectEqual(
        Operation.construct,
        classify("__ZNSt3__115__thread_structC1Ev").?,
    );
    try std.testing.expectEqual(
        Operation.destroy,
        classify("__ZNSt3__115__thread_structD1Ev").?,
    );
    try std.testing.expect(classify("__ZNSt3__16threadD1Ev") == null);
}
