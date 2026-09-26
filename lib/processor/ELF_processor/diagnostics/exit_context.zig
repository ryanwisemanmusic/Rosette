//! The causal half of the PE runner's EXIT DIAGNOSTICS block: what decided
//! the stop, how the stopped thread got there, and what went wrong just
//! before.
//!
//! Every field here is assembled from records the runtime already keeps -
//! the terminal event, the notable-event ring, the recent error lines and
//! the stopped thread's stack - through a `source` the caller supplies, so
//! this file owns the formatting and the storage and the process state owns
//! the facts. `source` answers:
//!   describe(address: u64, buffer: []u8) []const u8
//!   threadLabel(slot: ?u16) []const u8
//!   isCode(address: u64) bool
//!   bytesBefore(address: u64, storage: *[8]u8) ?[]const u8
//!   stackWord(address: u64) ?u64

const std = @import("std");
const exit_diagnostics = @import("exit_diagnostics");
const guest_backtrace = @import("guest_backtrace.zig");
const recent_log = @import("recent_log.zig");
const terminal_event = @import("terminal_event.zig");

pub const text_bytes = 224;
pub const backtrace_frames = 24;
/// How far above rsp the backtrace looks: 8 KiB of stack.
pub const backtrace_words = 1024;
pub const stack_entries = 16;
pub const preceding_events = 16;

pub const ExitContext = struct {
    terminal: ?exit_diagnostics.TerminalEventReport = null,
    terminal_rip_text: [text_bytes]u8 = undefined,
    terminal_return_text: [text_bytes]u8 = undefined,
    terminal_description_text: [text_bytes]u8 = undefined,
    terminal_description: []const u8 = "",

    stack: [stack_entries]exit_diagnostics.StackEntry = undefined,
    stack_text: [stack_entries][text_bytes]u8 = undefined,
    stack_count: usize = 0,

    frames: [backtrace_frames]exit_diagnostics.BacktraceFrame = undefined,
    frame_text: [backtrace_frames][text_bytes]u8 = undefined,
    frame_count: usize = 0,

    preceding: [preceding_events]exit_diagnostics.PrecedingEvent = undefined,
    preceding_count: usize = 0,
    preceding_total: u64 = 0,

    lines: [recent_log.capacity]recent_log.Line = undefined,
    recent: [recent_log.capacity]exit_diagnostics.RecentLogLine = undefined,
    recent_count: usize = 0,
    recent_total: u64 = 0,

    /// Fill every section. `self` must not move afterwards: the report
    /// slices point into it.
    pub fn build(
        self: *ExitContext,
        source: anytype,
        rip: u64,
        rsp: u64,
        event: *const terminal_event.TerminalEvent,
        notable: anytype,
    ) void {
        self.terminal_description = source.describe(rip, &self.terminal_description_text);
        self.buildTerminal(source, event);
        self.buildStack(source, rsp);
        self.buildBacktrace(source, rsp);
        self.buildPreceding(source, notable);
        self.buildRecent();
    }

    fn buildTerminal(self: *ExitContext, source: anytype, event: *const terminal_event.TerminalEvent) void {
        if (!event.recorded()) return;
        const site = event.site;
        self.terminal = .{
            .kind = terminal_event.kindLabel(event.kind),
            .label = event.label(),
            .detail = event.detail(),
            .step = site.step,
            .thread = source.threadLabel(site.thread_slot),
            .rip = site.rip,
            .rip_description = source.describe(site.rip, &self.terminal_rip_text),
            .return_address = site.return_address,
            .return_description = if (site.return_address == 0) "" else source.describe(site.return_address, &self.terminal_return_text),
            .decisions = event.decisions,
        };
    }

    fn buildStack(self: *ExitContext, source: anytype, rsp: u64) void {
        while (self.stack_count < stack_entries) : (self.stack_count += 1) {
            const slot = rsp +| @as(u64, @intCast(self.stack_count * 8));
            const value = source.stackWord(slot) orelse break;
            const index = self.stack_count;
            self.stack[index] = .{ .slot_address = slot, .value = value };
            if (source.isCode(value)) {
                self.stack[index].description = source.describe(value, &self.stack_text[index]);
            }
        }
    }

    fn buildBacktrace(self: *ExitContext, source: anytype, rsp: u64) void {
        var words: [backtrace_words]u64 = undefined;
        var count: usize = 0;
        while (count < words.len) : (count += 1) {
            words[count] = source.stackWord(rsp +| @as(u64, @intCast(count * 8))) orelse break;
        }
        var found: [backtrace_frames]guest_backtrace.Frame = undefined;
        const frames = guest_backtrace.scan(source, rsp, words[0..count], &found);
        for (found[0..frames], 0..) |frame, index| {
            self.frames[index] = .{
                .slot_address = frame.slot_address,
                .return_address = frame.return_address,
                .call_site = frame.call_site,
                .form = @tagName(frame.form),
                .description = source.describe(frame.return_address, &self.frame_text[index]),
            };
        }
        self.frame_count = frames;
    }

    fn buildPreceding(self: *ExitContext, source: anytype, notable: anytype) void {
        const held = notable.count();
        const shown = @min(held, preceding_events);
        const skip = held - shown;
        for (0..shown) |index| {
            const event = notable.chronological(skip + index) orelse break;
            self.preceding[index] = .{
                .kind = @tagName(event.kind),
                .step = event.site.step,
                .thread = source.threadLabel(event.site.thread_slot),
                .rip = event.site.rip,
                .text = event.text(),
            };
            self.preceding_count = index + 1;
        }
        self.preceding_total = notable.total;
    }

    fn buildRecent(self: *ExitContext) void {
        const count = recent_log.snapshot(&self.lines);
        for (0..count) |index| {
            self.recent[index] = .{
                .level = @tagName(self.lines[index].level),
                .sequence = self.lines[index].sequence,
                .text = self.lines[index].text(),
            };
        }
        self.recent_count = count;
        self.recent_total = recent_log.totalRecorded();
    }

    pub fn stackEntries(self: *const ExitContext) []const exit_diagnostics.StackEntry {
        return self.stack[0..self.stack_count];
    }

    pub fn backtrace(self: *const ExitContext) []const exit_diagnostics.BacktraceFrame {
        return self.frames[0..self.frame_count];
    }

    pub fn precedingEvents(self: *const ExitContext) []const exit_diagnostics.PrecedingEvent {
        return self.preceding[0..self.preceding_count];
    }

    pub fn recentLines(self: *const ExitContext) []const exit_diagnostics.RecentLogLine {
        return self.recent[0..self.recent_count];
    }
};

const TestSource = struct {
    base: u64,
    code: []const u8,
    stack_base: u64,
    stack: []const u64,

    pub fn describe(self: TestSource, address: u64, buffer: []u8) []const u8 {
        if (self.isCode(address)) return std.fmt.bufPrint(buffer, "code+0x{x}", .{address - self.base}) catch "";
        return "<unmapped>";
    }

    pub fn threadLabel(_: TestSource, slot: ?u16) []const u8 {
        return if (slot == null) "owner-context" else "worker";
    }

    pub fn isCode(self: TestSource, address: u64) bool {
        return address >= self.base and address < self.base + self.code.len;
    }

    pub fn bytesBefore(self: TestSource, address: u64, storage: *[8]u8) ?[]const u8 {
        if (address <= self.base or address > self.base + self.code.len) return null;
        const offset: usize = @intCast(address - self.base);
        const count = @min(offset, storage.len);
        @memcpy(storage[0..count], self.code[offset - count .. offset]);
        return storage[0..count];
    }

    pub fn stackWord(self: TestSource, address: u64) ?u64 {
        if (address < self.stack_base) return null;
        const index: usize = @intCast((address - self.stack_base) / 8);
        if (index >= self.stack.len) return null;
        return self.stack[index];
    }
};

test "an exit context names the terminal event, the call chain and what came before" {
    recent_log.resetForTest();
    defer recent_log.resetForTest();
    recent_log.remember(.err, "PE64 guest allocation rejected: request={d}", .{10878423874});

    var code = [_]u8{0x90} ** 0x40;
    code[0x10] = 0xE8; // call rel32 at 0x10 -> 0x15 + 0x0B = 0x20
    std.mem.writeInt(i32, code[0x11..0x15], 0x0B, .little);
    const source = TestSource{
        .base = 0x1000,
        .code = &code,
        .stack_base = 0x8000,
        .stack = &.{ 0x1234, 0x1015, 0 },
    };

    var event: terminal_event.TerminalEvent = .{};
    _ = event.record(.guest_abort, "abort", "operator new was refused", .{ .step = 42, .rip = 0x1020, .return_address = 0x1015, .thread_slot = 3 });
    var notable: terminal_event.NotableRing(4) = .{};
    notable.push(.heap_refusal, .{ .step = 40 }, "request-exceeds-guest-heap request=10878423874");

    var context: ExitContext = .{};
    context.build(source, 0x1020, 0x8000, &event, &notable);

    const terminal = context.terminal.?;
    try std.testing.expectEqualStrings("abort", terminal.label);
    try std.testing.expectEqualStrings("worker", terminal.thread);
    try std.testing.expectEqualStrings("code+0x15", terminal.return_description);
    try std.testing.expectEqualStrings("code+0x20", context.terminal_description);
    try std.testing.expectEqual(@as(usize, 3), context.stackEntries().len);
    try std.testing.expectEqualStrings("code+0x15", context.stackEntries()[1].description);
    try std.testing.expectEqual(@as(usize, 1), context.backtrace().len);
    try std.testing.expectEqual(@as(u64, 0x1010), context.backtrace()[0].call_site);
    try std.testing.expectEqual(@as(usize, 1), context.precedingEvents().len);
    try std.testing.expectEqualStrings("heap_refusal", context.precedingEvents()[0].kind);
    try std.testing.expectEqual(@as(usize, 1), context.recentLines().len);
    try std.testing.expect(std.mem.indexOf(u8, context.recentLines()[0].text, "10878423874") != null);
}
