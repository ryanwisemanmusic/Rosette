//! Optional hosted PE32 GUI session runner.
//!
//! The ordinary PE32 runner remains bounded for offline inspection and tests.
//! When explicitly enabled, this module resumes the child until the guest exits,
//! faults, or its host window closes.
const std = @import("std");
const process_runtime = @import("pe32_process_runtime.zig");

fn enabled() bool {
    const value = std.c.getenv("ROSETTE_PE32_INTERACTIVE") orelse return false;
    return value[0] != 0 and value[0] != '0';
}

pub fn run(runtime: *process_runtime.Runtime, chunk_steps: usize) process_runtime.Summary {
    if (!enabled() or chunk_steps == 0 or !runtime.hasInteractiveWindowHost()) {
        return runtime.runResumedChild(chunk_steps);
    }

    std.debug.print("PE32_SESSION: interactive child active; close its host window to stop\n", .{});
    // A single large bound avoids pausing inside an emulated WNDPROC callback,
    // whose synthetic return address is meaningful only while that callback
    // owns the guest stack. The native window-close callback queues WM_QUIT.
    return runtime.runResumedChild(std.math.maxInt(usize));
}
