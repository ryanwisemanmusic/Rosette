const std = @import("std");

/// Itanium ABI layout used by libc++ control blocks. The vtable symbol points
/// at the offset-to-top field; object vptrs point two words beyond it.
pub const vtable_address_point_offset: u64 = 2 * @sizeOf(u64);
pub const on_zero_shared_slot_offset: u64 = 2 * @sizeOf(u64);

pub const release_shared_symbol_fragment = "__shared_count16__release_shared";
pub const atomic_bool_vtable_symbol_prefix =
    "__ZTVNSt3__120__shared_ptr_emplaceINS_6atomicIbEENS_9allocatorIS2_EEEE";

pub const Input = struct {
    operation: []const u8,
    caller_symbol: []const u8,
    operand_address: u64,
    object_address: u64,
    current_vptr: u64,
    strong_count: u64,
    weak_count: u64,
    vtable_symbol_address: u64,
    slot_target: u64,
    object_mapped: bool,
    vtable_mapped: bool,
    target_executable: bool,
};

pub const Recovery = struct {
    address_point: u64,
    slot_address: u64,
    target: u64,
};

pub const Decision = union(enum) {
    not_applicable,
    rejected: []const u8,
    recover: Recovery,
};

pub const Stats = struct {
    candidates: u64 = 0,
    recoveries: u64 = 0,
    rejected: u64 = 0,

    pub fn record(self: *Stats, decision: Decision) void {
        switch (decision) {
            .not_applicable => {},
            .rejected => {
                self.candidates +|= 1;
                self.rejected +|= 1;
            },
            .recover => {
                self.candidates +|= 1;
                self.recoveries +|= 1;
            },
        }
    }
};

/// Classifies one null indirect call. This deliberately recognizes only the
/// final strong-owner transition in libc++'s __shared_count::release_shared.
/// A general "repair any null vptr" policy would conceal stale pointers and
/// double destruction; the count and ABI-slot checks keep this recovery tied
/// to the observed, valid virtual dispatch.
pub fn assess(input: Input) Decision {
    if (!std.mem.eql(u8, input.operation, "call_mem64") or
        std.mem.indexOf(u8, input.caller_symbol, release_shared_symbol_fragment) == null)
    {
        return .not_applicable;
    }
    if (input.operand_address != on_zero_shared_slot_offset) {
        return .{ .rejected = "the null call is not the __on_zero_shared vtable slot" };
    }
    if (input.object_address == 0 or !input.object_mapped) {
        return .{ .rejected = "the shared control block is not guest-backed" };
    }
    if (input.current_vptr != 0) {
        return .{ .rejected = "the control block has a non-null vptr, so this is not the modeled loss" };
    }
    // libc++ stores owner_count - 1. release_shared calls the virtual hook
    // only after the final decrement changes 0 to -1.
    if (input.strong_count != std.math.maxInt(u64)) {
        return .{ .rejected = "the strong count is not at libc++'s final-owner sentinel" };
    }
    // A weak count is also biased by one. Values in the signed-negative range
    // indicate an already-destroyed/corrupt block and must never be repaired.
    if (input.weak_count > std.math.maxInt(i64)) {
        return .{ .rejected = "the weak count indicates an already-released control block" };
    }
    if (input.vtable_symbol_address == 0 or !input.vtable_mapped) {
        return .{ .rejected = "the binary's verified atomic<bool> control-block vtable is unavailable" };
    }
    if (input.slot_target == 0 or !input.target_executable) {
        return .{ .rejected = "the recovered __on_zero_shared slot is not executable" };
    }

    const address_point = std.math.add(u64, input.vtable_symbol_address, vtable_address_point_offset) catch
        return .{ .rejected = "the control-block vtable address point overflowed" };
    const slot_address = std.math.add(u64, address_point, on_zero_shared_slot_offset) catch
        return .{ .rejected = "the __on_zero_shared slot address overflowed" };
    return .{ .recover = .{
        .address_point = address_point,
        .slot_address = slot_address,
        .target = input.slot_target,
    } };
}

test "final atomic bool control block dispatch may restore its verified vptr" {
    const decision = assess(.{
        .operation = "call_mem64",
        .caller_symbol = "__ZNSt3__114__shared_count16__release_sharedB7v160006Ev",
        .operand_address = 0x10,
        .object_address = 0x4000,
        .current_vptr = 0,
        .strong_count = std.math.maxInt(u64),
        .weak_count = 0,
        .vtable_symbol_address = 0x19000,
        .slot_target = 0x243610,
        .object_mapped = true,
        .vtable_mapped = true,
        .target_executable = true,
    });
    const recovery = switch (decision) {
        .recover => |value| value,
        else => return error.ExpectedRecovery,
    };
    try std.testing.expectEqual(@as(u64, 0x19010), recovery.address_point);
    try std.testing.expectEqual(@as(u64, 0x19020), recovery.slot_address);
    try std.testing.expectEqual(@as(u64, 0x243610), recovery.target);
}

test "non-final or stale control blocks are not repaired" {
    const base = Input{
        .operation = "call_mem64",
        .caller_symbol = "__ZNSt3__114__shared_count16__release_sharedB7v160006Ev",
        .operand_address = 0x10,
        .object_address = 0x4000,
        .current_vptr = 0,
        .strong_count = 0,
        .weak_count = 0,
        .vtable_symbol_address = 0x19000,
        .slot_target = 0x243610,
        .object_mapped = true,
        .vtable_mapped = true,
        .target_executable = true,
    };
    try std.testing.expect(assess(base) == .rejected);

    var stale = base;
    stale.strong_count = std.math.maxInt(u64);
    stale.weak_count = std.math.maxInt(u64);
    try std.testing.expect(assess(stale) == .rejected);
}

test "unrelated null indirect calls remain outside this recovery" {
    const decision = assess(.{
        .operation = "call_mem64",
        .caller_symbol = "some_import_thunk",
        .operand_address = 0x10,
        .object_address = 0x4000,
        .current_vptr = 0,
        .strong_count = std.math.maxInt(u64),
        .weak_count = 0,
        .vtable_symbol_address = 0x19000,
        .slot_target = 0x243610,
        .object_mapped = true,
        .vtable_mapped = true,
        .target_executable = true,
    });
    try std.testing.expect(decision == .not_applicable);
}
