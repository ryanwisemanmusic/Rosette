//! Stateful C string writes that must be performed in guest memory.

const std = @import("std");

pub fn handle(comptime api: type, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (!std.mem.eql(u8, name, "strcat")) return false;

    const destination = api._arg(state, 0, direct_return_rip);
    const source_address = api._arg(state, 1, direct_return_rip);
    const destination_snapshot = api._crtCStringOrNull(state, destination) orelse {
        fail(api, state, direct_return_rip);
        return true;
    };
    defer api._deinitCrtCStringSnapshot(destination_snapshot);
    const source_snapshot = api._crtCStringOrNull(state, source_address) orelse {
        fail(api, state, direct_return_rip);
        return true;
    };
    defer api._deinitCrtCStringSnapshot(source_snapshot);

    const destination_bytes = api._crtCStringSnapshotBytes(destination_snapshot);
    const source_bytes = api._crtCStringSnapshotBytes(source_snapshot);
    const append_address = std.math.add(u64, destination, @intCast(destination_bytes.len)) catch {
        fail(api, state, direct_return_rip);
        return true;
    };
    const append_capacity = std.math.add(u64, @intCast(source_bytes.len), 1) catch {
        fail(api, state, direct_return_rip);
        return true;
    };

    // `strcat` has no capacity argument. Validate precisely the suffix it
    // writes, then use the runtime's coordinated guest writer so the append
    // stays visible to parallel guest readers and preserves guest TSO order.
    if (!api._guestRangeAvailable(state, append_address, append_capacity) or
        api._copyGuestString(state, append_address, append_capacity, source_bytes) != source_bytes.len)
    {
        api._noteCrtMemoryUnreadable(state, append_address, append_capacity, direct_return_rip);
        fail(api, state, direct_return_rip);
        return true;
    }

    api._guestStateField(state, "windows_last_error").* = 0;
    api._guestStateField(state, "regs").*.rax = destination;
    api._finish(state, direct_return_rip);
    return true;
}

fn fail(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    api._guestStateField(state, "windows_last_error").* = 998; // ERROR_NOACCESS
    api._guestStateField(state, "regs").*.rax = 0;
    api._finish(state, direct_return_rip);
}
