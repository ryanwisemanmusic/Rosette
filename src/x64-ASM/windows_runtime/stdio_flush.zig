//! File streams here use synchronous positional writes, not a private CRT
//! output buffer. Ordinary fflush has nothing left to submit to the OS.
//! Microsoft c/n modes and _commode choose durable commit explicitly;
//! FlushFileBuffers continues to use its separate synchronous handler.
const std = @import("std");
/// Internal differential replay control only. False selects the previous
/// unconditional file.sync policy; no application/launcher flag.
pub var write_through_flush: bool = true;

pub fn initStorage(state: anytype, address: *u64) void {
    if (address.* != 0) return;
    address.* = state.guestAlloc(4, 4) orelse 0;
    if (address.* != 0) state.write32(address.*, 0);
}
pub fn commitMode(mode: []const u8, default: bool) bool {
    var commit = default;
    for (mode) |byte| switch (byte) {
        ',' => break,
        'c' => commit = true,
        'n' => commit = false,
        else => {},
    };
    return commit;
}
pub fn applyMode(state: anytype, slot: anytype, mode: []const u8) void {
    if (comptime !@hasField(@TypeOf(slot.*), "stdio_commit_on_flush")) return;
    const default = if (comptime @hasField(@TypeOf(state.*), "windows_commode_storage")) blk: {
        const address = state.windows_commode_storage;
        break :blk address != 0 and state.read32(address) != 0;
    } else false;
    slot.stdio_commit_on_flush = commitMode(mode, default);
}
fn note(state: anytype, comptime name: []const u8) void {
    if (comptime @hasField(@TypeOf(state.*), name)) _ = @atomicRmw(u64, &@field(state.*, name), .Add, 1, .monotonic);
}
fn flushOne(state: anytype, slot: anytype) bool {
    if (slot.standard_stream != null) return true;
    const commit = if (comptime @hasField(@TypeOf(slot.*), "stdio_commit_on_flush")) slot.stdio_commit_on_flush else false;
    if (write_through_flush and !commit) {
        note(state, "windows_stdio_flush_elided");
        return true;
    }
    note(state, "windows_stdio_flush_commits");
    const io = state.windows_host_io orelse unreachable;
    slot.file.?.sync(io) catch return false;
    return true;
}
pub fn call(state: anytype, direct: ?u64, comptime api: type) bool {
    note(state, "windows_stdio_flush_requests");
    const handle = api._arg(state, 0, direct);
    var ok = true;
    if (handle == 0) {
        for (&state.windows_files) |*slot| if (slot.file != null) {
            if (!flushOne(state, slot)) ok = false;
        };
    } else if (api._windowsFileSlot(state, handle)) |slot| {
        ok = flushOne(state, slot);
    } else ok = false;
    if (!ok) {
        api._failWindowsFileCall(state, direct, 1117);
        // fflush returns EOF, whereas the shared Win32 failure helper
        // returns FALSE. Preserve failure reporting with the CRT result.
        api._guestStateField(state, "regs").*.rax = std.math.maxInt(u32);
        return true;
    }
    api._guestStateField(state, "regs").*.rax = 0;
    api._finish(state, direct);
    return true;
}
