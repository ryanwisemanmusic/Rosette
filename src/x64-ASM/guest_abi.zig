const std = @import("std");

const log = std.log.scoped(.x64_guest_abi);

pub const CallKind = enum {
    direct,
    indirect,
};

pub const Frame = struct {
    target: u64,
    return_rip: u64,
    rsp_before_call: u64,
    symbol: ?[]const u8,
    kind: CallKind,
};

pub const TraceConfig = struct {
    trace_calls: bool = false,
    diagnose: bool = false,
};

pub const CallStack = struct {
    frames: std.ArrayListUnmanaged(Frame) = .empty,

    pub fn deinit(self: *CallStack, allocator: std.mem.Allocator) void {
        self.frames.deinit(allocator);
        self.* = .{};
    }

    pub fn enter(self: *CallStack, allocator: std.mem.Allocator, config: TraceConfig, frame: Frame) void {
        self.frames.append(allocator, frame) catch {
            if (config.diagnose) log.warn("call stack trace allocation failed at target=0x{x}", .{frame.target});
            return;
        };
        if (config.trace_calls) {
            log.info("call {s} target=0x{x}{s}{s} return=0x{x} rsp=0x{x}", .{
                @tagName(frame.kind),
                frame.target,
                if (frame.symbol != null) " symbol=" else "",
                frame.symbol orelse "",
                frame.return_rip,
                frame.rsp_before_call,
            });
        }
    }

    pub fn leave(self: *CallStack, config: TraceConfig, return_rip: u64, rsp_after_pop: u64, rax: u64) void {
        const frame = if (self.frames.items.len > 0) blk: {
            break :blk self.frames.pop().?;
        } else null;

        if (config.trace_calls) {
            if (frame) |f| {
                log.info("ret  target=0x{x}{s}{s} expected=0x{x} actual=0x{x} rsp=0x{x} rax=0x{x}", .{
                    f.target,
                    if (f.symbol != null) " symbol=" else "",
                    f.symbol orelse "",
                    f.return_rip,
                    return_rip,
                    rsp_after_pop,
                    rax,
                });
            } else {
                log.info("ret  target=<unknown> actual=0x{x} rsp=0x{x} rax=0x{x}", .{
                    return_rip,
                    rsp_after_pop,
                    rax,
                });
            }
        }

        if (config.diagnose and config.trace_calls) {
            if (frame) |f| {
                if (f.return_rip != return_rip) {
                    log.warn("return target mismatch: symbol={s} expected=0x{x} actual=0x{x}", .{
                        f.symbol orelse "<unknown>",
                        f.return_rip,
                        return_rip,
                    });
                }
            }
        }
    }
};

pub fn looksLikeGuestPointer(state: anytype, value: u64) bool {
    return value != 0 and state.addrToOffset(value) != null;
}

pub fn diagnoseSyscall(state: anytype, number: u64, fd: u64, buf: u64, count: u64, result: u64) void {
    if (!state.diagnose_abi) return;
    const signed_result: i64 = @bitCast(result);
    if (number == 1 and signed_result < 0 and looksLikeGuestPointer(state, fd)) {
        log.warn("write syscall used a guest-pointer-looking fd=0x{x}; likely missing fd setup before syscall (buf=0x{x}, count={d}, result={d})", .{
            fd,
            buf,
            count,
            signed_result,
        });
    }
}

test "call stack records balanced call and return" {
    var stack: CallStack = .{};
    defer stack.deinit(std.testing.allocator);
    stack.enter(std.testing.allocator, .{}, .{
        .target = 0x1000,
        .return_rip = 0x2000,
        .rsp_before_call = 0x3000,
        .symbol = "demo",
        .kind = .direct,
    });
    try std.testing.expectEqual(@as(usize, 1), stack.frames.items.len);
    stack.leave(.{ .diagnose = true }, 0x2000, 0x3008, 7);
    try std.testing.expectEqual(@as(usize, 0), stack.frames.items.len);
}
