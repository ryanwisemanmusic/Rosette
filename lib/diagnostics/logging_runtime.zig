const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

pub const Mode = enum {
    unavailable,
    synchronous,
};

pub const Engine = struct {
    mode: Mode = .unavailable,
    initialization_attempts: u64 = 0,
    initialization_substitutions: u64 = 0,
    shutdown_substitutions: u64 = 0,
    emitted_lines: u64 = 0,
    emitted_bytes: u64 = 0,
    rejected_lines: u64 = 0,
    initialized: bool = false,

    pub fn configure(self: *Engine, has_thread_buffer: bool, has_formatted_append: bool, has_view_append: bool) void {
        self.mode = if (has_thread_buffer and has_formatted_append and has_view_append) .synchronous else .unavailable;
    }

    pub fn initialize(self: *Engine, app_name: []const u8) bool {
        self.initialization_attempts +|= 1;
        if (self.mode != .synchronous) return false;
        self.initialization_substitutions +|= 1;
        self.initialized = true;
        machoCapturePrint(
            "macho-processor: logging runtime: synchronous transport initialized app={s}; asynchronous guest writer bypassed\n",
            .{if (app_name.len == 0) "<unnamed>" else app_name},
        );
        return true;
    }

    pub fn shutdown(self: *Engine) bool {
        if (!self.initialized or self.mode != .synchronous) return false;
        self.shutdown_substitutions +|= 1;
        self.initialized = false;
        return true;
    }

    pub fn recordEmission(self: *Engine, length: u64, success: bool) void {
        if (success) {
            self.emitted_lines +|= 1;
            self.emitted_bytes +|= length;
        } else {
            self.rejected_lines +|= 1;
        }
    }

    pub fn logSummary(self: *const Engine) void {
        if (self.initialization_attempts == 0 and self.emitted_lines == 0 and self.rejected_lines == 0) return;
        machoCapturePrint(
            "macho-processor: logging runtime: mode={s} init_attempts={d} init_substitutions={d} shutdown_substitutions={d} lines={d} bytes={d} rejected={d}\n",
            .{
                @tagName(self.mode),
                self.initialization_attempts,
                self.initialization_substitutions,
                self.shutdown_substitutions,
                self.emitted_lines,
                self.emitted_bytes,
                self.rejected_lines,
            },
        );
    }
};

test "synchronous mode requires every verified log entry point" {
    var engine = Engine{};
    engine.configure(true, true, false);
    try std.testing.expectEqual(Mode.unavailable, engine.mode);
    try std.testing.expect(!engine.initialize("partial"));

    engine.configure(true, true, true);
    try std.testing.expect(engine.initialize("complete"));
    engine.recordEmission(12, true);
    try std.testing.expectEqual(@as(u64, 1), engine.emitted_lines);
    try std.testing.expect(engine.shutdown());
}
