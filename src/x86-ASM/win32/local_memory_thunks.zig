//! PE32 LocalAlloc/LocalFree shims backed by Rosette's bounded guest heap.
const std = @import("std");
const Executor = @import("../instruction_operations.zig").Executor;
const abi = @import("../abi_handshake.zig");
const heap = @import("../heap/runtime.zig");

const lmem_zeroinit: u32 = 0x0040;

fn guestSlice(ex: *Executor, address: u32, length: usize) ?[]u8 {
    if (address < ex.mem.base) return null;
    const offset: usize = @intCast(address - ex.mem.base);
    if (offset > ex.mem.data.len or length > ex.mem.data.len - offset) return null;
    return ex.mem.data[offset .. offset + length];
}

fn localAllocThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const flags = frame.arg(0);
    const size = frame.arg(1);
    const address = heap.alloc("LocalAlloc", heap.process_heap_handle, flags, size);
    const allocation = guestSlice(ex, address, @intCast(@max(size, 1))) orelse {
        ex.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
        frame.finish(0);
        return;
    };
    if (flags & lmem_zeroinit != 0) @memset(allocation, 0);
    ex.win32_last_error = 0;
    frame.finish(address);
}

fn localFreeThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const address = frame.arg(0);
    if (address == 0 or heap.querySize("LocalFree", heap.process_heap_handle, 0, address) == std.math.maxInt(u32)) {
        ex.win32_last_error = if (address == 0) 0 else 6; // ERROR_INVALID_HANDLE
        frame.finish(address);
        return;
    }
    const freed = heap.free("LocalFree", heap.process_heap_handle, 0, address);
    ex.win32_last_error = if (freed) 0 else 6;
    frame.finish(if (freed) 0 else address);
}

pub fn register(ex: *Executor) void {
    ex.import_table.put("LocalAlloc", localAllocThunk) catch {};
    ex.import_table.put("LocalFree", localFreeThunk) catch {};
}
