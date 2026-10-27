//! PE32 process-priority APIs used by Win32 compatibility applications.
//! Guest priority state is modeled per executor and never changes Rosette's
//! host process or thread scheduling policy.
const std = @import("std");
const Executor = @import("../instruction_operations.zig").Executor;
const abi = @import("../abi_handshake.zig");

const current_process_pseudo_handle = std.math.maxInt(u32);
const valid_priority_classes = [_]u32{
    0x0000_0040, // IDLE_PRIORITY_CLASS
    0x0000_4000, // BELOW_NORMAL_PRIORITY_CLASS
    0x0000_0020, // NORMAL_PRIORITY_CLASS
    0x0000_8000, // ABOVE_NORMAL_PRIORITY_CLASS
    0x0000_0080, // HIGH_PRIORITY_CLASS
    0x0000_0100, // REALTIME_PRIORITY_CLASS
};

fn isCurrentProcess(handle: u32) bool {
    return handle == current_process_pseudo_handle;
}

fn getPriorityClassThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    if (!isCurrentProcess(frame.arg(0))) {
        ex.win32_last_error = 87; // ERROR_INVALID_PARAMETER
        frame.finish(0);
        return;
    }
    ex.win32_last_error = 0;
    frame.finish(ex.pe32_priority_class);
}

fn setPriorityClassThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const process = frame.arg(0);
    const priority_class = frame.arg(1);
    const supported = isCurrentProcess(process) and
        std.mem.indexOfScalar(u32, &valid_priority_classes, priority_class) != null;
    if (!supported) {
        ex.win32_last_error = 87; // ERROR_INVALID_PARAMETER
        frame.finish(0);
        return;
    }
    ex.pe32_priority_class = priority_class;
    ex.win32_last_error = 0;
    frame.finish(1);
}

pub fn register(ex: *Executor) void {
    ex.import_table.put("GetPriorityClass", getPriorityClassThunk) catch {};
    ex.import_table.put("SetPriorityClass", setPriorityClassThunk) catch {};
}
