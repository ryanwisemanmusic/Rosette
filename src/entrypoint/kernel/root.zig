pub const process_guard = @import("process_guard.zig");

test "kernel process guard module accessible" {
    _ = process_guard.RunOptions;
    _ = process_guard.RunStatus;
}
