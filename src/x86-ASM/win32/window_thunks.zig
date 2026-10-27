//! Basic Win32 screen metrics used by PE32 applications before they create a window.
//! The PE64 Windows route uses the same virtual 1280x720 desktop contract.
const std = @import("std");
const Executor = @import("../instruction_operations.zig").Executor;
const abi = @import("../abi_handshake.zig");

const cursor_handle_base: u32 = 0xF200_0000;
const icon_handle_base: u32 = 0xF300_0000;
const window_class_atom_base: u16 = 0xC001;
const desktop_window_handle: u32 = 0xF400_0000;
const created_window_handle: u32 = 0xF400_0001;
const window_dc_handle: u32 = 0xF500_0001;
const wm_quit: u32 = 0x0012;
const wm_paint: u32 = 0x000F;
const wm_timer: u32 = 0x0113;
const minimum_timer_interval_ms: u32 = 10;

fn monotonicNanoseconds() u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &ts) != 0) return 0;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

fn sleepNanoseconds(nanoseconds: u64) void {
    var ts = std.c.timespec{
        .sec = @intCast(nanoseconds / std.time.ns_per_s),
        .nsec = @intCast(nanoseconds % std.time.ns_per_s),
    };
    _ = std.c.nanosleep(&ts, null);
}

fn windowTraceEnabled() bool {
    const value = std.c.getenv("ROSETTE_PE32_WINDOW_TRACE") orelse return false;
    return value[0] != 0 and value[0] != '0';
}

fn windowWaitLimitNanoseconds() u64 {
    const value = std.c.getenv("ROSETTE_PE32_WINDOW_WAIT_LIMIT_MS") orelse return 0;
    const milliseconds = std.fmt.parseInt(u64, std.mem.sliceTo(value, 0), 10) catch return 0;
    if (milliseconds == 0) return 0;
    return @min(milliseconds, 60_000) * @as(u64, std.time.ns_per_ms);
}

fn guestSlice(ex: *Executor, address: u32, count: usize) ?[]u8 {
    if (address < ex.mem.base) return null;
    const offset: usize = @intCast(address - ex.mem.base);
    if (offset > ex.mem.data.len or count > ex.mem.data.len - offset) return null;
    return ex.mem.data[offset .. offset + count];
}

fn validWideClassName(ex: *Executor, address: u32) bool {
    if (address == 0 or address & 1 != 0) return false;
    if (address < ex.mem.base) return false;
    const offset: usize = @intCast(address - ex.mem.base);
    if (offset >= ex.mem.data.len) return false;
    var cursor = offset;
    while (cursor + 1 < ex.mem.data.len) : (cursor += 2) {
        const character = std.mem.readInt(u16, ex.mem.data[cursor..][0..2], .little);
        if (character == 0) return cursor != offset;
    }
    return false;
}

fn registerClassWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const class_address = frame.arg(0);
    const class_bytes = guestSlice(ex, class_address, 40) orelse {
        ex.win32_last_error = 87; // ERROR_INVALID_PARAMETER
        frame.finish(0);
        return;
    };

    // WNDCLASSW (PE32) offsets: lpfnWndProc=4, hInstance=16,
    // lpszClassName=36. Preserve only the fields needed by later USER32 calls.
    const procedure = std.mem.readInt(u32, class_bytes[4..8], .little);
    const instance = std.mem.readInt(u32, class_bytes[16..20], .little);
    const name_address = std.mem.readInt(u32, class_bytes[36..40], .little);
    if (procedure == 0 or !validWideClassName(ex, name_address)) {
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    }

    for (ex.pe32_window_classes[0..ex.pe32_window_class_count]) |registered| {
        if (registered.instance == instance and registered.name_address == name_address) {
            ex.win32_last_error = 1410; // ERROR_CLASS_ALREADY_EXISTS
            frame.finish(0);
            return;
        }
    }
    if (ex.pe32_window_class_count == ex.pe32_window_classes.len) {
        ex.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
        frame.finish(0);
        return;
    }

    const index = ex.pe32_window_class_count;
    const atom = window_class_atom_base + @as(u16, @intCast(index));
    ex.pe32_window_classes[index] = .{
        .atom = atom,
        .instance = instance,
        .procedure = procedure,
        .name_address = name_address,
    };
    ex.pe32_window_class_count += 1;
    ex.win32_last_error = 0;
    frame.finish(atom);
}

fn guestWideAsciiZ(ex: *Executor, address: u32, buffer: []u8) [*:0]const u8 {
    var length: usize = 0;
    if (address >= ex.mem.base) {
        const offset: usize = @intCast(address - ex.mem.base);
        if (offset < ex.mem.data.len) {
            var cursor = offset;
            while (cursor + 1 < ex.mem.data.len and length + 1 < buffer.len) : (cursor += 2) {
                const character = std.mem.readInt(u16, ex.mem.data[cursor..][0..2], .little);
                if (character == 0) break;
                buffer[length] = if (character < 0x80) @intCast(character) else '?';
                length += 1;
            }
        }
    }
    if (length == 0) {
        const fallback = "Windows Application";
        const count = @min(fallback.len, buffer.len - 1);
        @memcpy(buffer[0..count], fallback[0..count]);
        length = count;
    }
    buffer[length] = 0;
    return @ptrCast(buffer.ptr);
}

fn registeredClass(ex: *const Executor, class_name: u32, instance: u32) bool {
    if (class_name <= 0xFFFF) {
        for (ex.pe32_window_classes[0..ex.pe32_window_class_count]) |registered| {
            if (registered.atom == @as(u16, @truncate(class_name)) and
                (instance == 0 or registered.instance == instance)) return true;
        }
        return false;
    }
    for (ex.pe32_window_classes[0..ex.pe32_window_class_count]) |registered| {
        if (registered.name_address == class_name and
            (instance == 0 or registered.instance == instance)) return true;
    }
    return false;
}

fn registeredProcedure(ex: *const Executor, class_name: u32, instance: u32) ?u32 {
    if (class_name <= 0xFFFF) {
        for (ex.pe32_window_classes[0..ex.pe32_window_class_count]) |registered| {
            if (registered.atom == @as(u16, @truncate(class_name)) and
                (instance == 0 or registered.instance == instance)) return registered.procedure;
        }
        return null;
    }
    for (ex.pe32_window_classes[0..ex.pe32_window_class_count]) |registered| {
        if (registered.name_address == class_name and
            (instance == 0 or registered.instance == instance)) return registered.procedure;
    }
    return null;
}

fn queueWindowCallback(ex: *Executor, window: u32, message: u32, wparam: u32, lparam: u32) void {
    const record = ex.findPe32Window(window) orelse return;
    if (record.procedure == 0) return;
    const callback: Executor.Pe32WindowMessage = .{
        .window = window,
        .message = message,
        .wparam = wparam,
        .lparam = lparam,
        .create_struct = message == 0x0081 or message == 0x0001,
    };
    if (ex.pe32_window_callback == null) {
        ex.pe32_window_callback = callback;
    } else if (ex.pe32_window_callback_followup == null) {
        ex.pe32_window_callback_followup = callback;
    }
}

fn updateWindowFocus(ex: *Executor, focused: bool) void {
    const parent = ex.topLevelPe32Window() orelse return;
    if (focused == ex.pe32_window_focused) return;
    const previous = ex.pe32_window_focused;
    ex.pe32_window_focused = focused;
    const focus_window = ex.focusPe32Window() orelse parent;
    if (focused) {
        // USER32 activates the top-level window, then gives keyboard focus to
        // its focused child. Keep these in the ordinary thread message queue
        // so the guest's own GetMessage/DispatchMessage path handles them.
        _ = ex.queuePe32WindowMessage(.{ .window = parent.handle, .message = 0x001C, .wparam = 1 }); // WM_ACTIVATEAPP
        _ = ex.queuePe32WindowMessage(.{ .window = parent.handle, .message = 0x0006, .wparam = 1 }); // WM_ACTIVATE / WA_ACTIVE
        _ = ex.queuePe32WindowMessage(.{ .window = focus_window.handle, .message = 0x0007 }); // WM_SETFOCUS
    } else {
        _ = ex.queuePe32WindowMessage(.{ .window = focus_window.handle, .message = 0x0008 }); // WM_KILLFOCUS
        _ = ex.queuePe32WindowMessage(.{ .window = parent.handle, .message = 0x0006, .wparam = 0 }); // WM_ACTIVATE / WA_INACTIVE
        _ = ex.queuePe32WindowMessage(.{ .window = parent.handle, .message = 0x001C, .wparam = 0 }); // WM_ACTIVATEAPP
    }
    if (windowTraceEnabled()) std.debug.print("PE32_WINDOW: focus top=0x{X:0>8} keyboard=0x{X:0>8} previous={} now={}\n", .{
        parent.handle,
        focus_window.handle,
        previous,
        focused,
    });
}

fn hasVisibleTopLevelWindow(ex: *const Executor) bool {
    const window = ex.topLevelPe32Window() orelse return false;
    return window.visible;
}

fn nextWindowHandle(ex: *Executor) ?u32 {
    for (&ex.pe32_windows) |*window| {
        if (window.active) continue;
        var handle = ex.pe32_window_next_handle;
        if (handle < 0xF400_0001 or handle == desktop_window_handle) handle = 0xF400_0001;
        ex.pe32_window_next_handle = handle +% 1;
        window.* = .{ .active = true, .handle = handle };
        return handle;
    }
    return null;
}

fn isTopLevelWindow(window: *const Executor.Pe32WindowRecord) bool {
    return window.parent == 0 or window.parent == desktop_window_handle;
}

fn syncLegacyWindowFields(ex: *Executor, window: *const Executor.Pe32WindowRecord) void {
    if (ex.pe32_window_handle != window.handle) return;
    ex.pe32_window_procedure = window.procedure;
    ex.pe32_window_x = window.x;
    ex.pe32_window_y = window.y;
    ex.pe32_window_width = window.width;
    ex.pe32_window_height = window.height;
    ex.pe32_window_visible = window.visible;
    ex.pe32_window_paint_queued = window.paint_queued;
    ex.pe32_window_paint_active = window.paint_active;
    ex.pe32_window_create_fields = window.create_fields;
}

fn writeMessage(ex: *Executor, address: u32, message: Executor.Pe32WindowMessage) bool {
    const bytes = guestSlice(ex, address, 28) orelse return false;
    std.mem.writeInt(u32, bytes[0..4], message.window, .little);
    std.mem.writeInt(u32, bytes[4..8], message.message, .little);
    std.mem.writeInt(u32, bytes[8..12], message.wparam, .little);
    std.mem.writeInt(u32, bytes[12..16], message.lparam, .little);
    std.mem.writeInt(u32, bytes[16..20], 0, .little); // MSG.time
    std.mem.writeInt(u32, bytes[20..24], 0, .little); // MSG.pt.x
    std.mem.writeInt(u32, bytes[24..28], 0, .little); // MSG.pt.y
    return true;
}

fn acknowledgeTimerMessage(ex: *Executor, message: Executor.Pe32WindowMessage) void {
    if (message.message != wm_timer) return;
    for (&ex.pe32_window_timers) |*timer| {
        if (timer.active and timer.window == message.window and timer.id == message.wparam) {
            timer.message_queued = false;
            return;
        }
    }
}

fn queueDueTimer(ex: *Executor, now_ns: u64) bool {
    for (&ex.pe32_window_timers) |*timer| {
        if (!timer.active or timer.message_queued or now_ns < timer.next_due_ns) continue;
        const elapsed = now_ns - timer.next_due_ns;
        const periods = elapsed / timer.interval_ns + 1;
        timer.next_due_ns +|= periods * timer.interval_ns;
        if (ex.queuePe32WindowMessage(.{
            .window = timer.window,
            .message = wm_timer,
            .wparam = timer.id,
        })) {
            timer.message_queued = true;
            return true;
        }
        return false;
    }
    return false;
}

fn hasActiveTimer(ex: *const Executor) bool {
    for (ex.pe32_window_timers) |timer| if (timer.active) return true;
    return false;
}

fn getMessageWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 4);
    const message_address = frame.arg(0);
    const wait_limit_ns = windowWaitLimitNanoseconds();
    var wait_started_ns: u64 = 0;
    var wait_traced = false;
    while (true) {
        if (ex.popPe32WindowMessage()) |queued| {
            acknowledgeTimerMessage(ex, queued);
            if (!writeMessage(ex, message_address, queued)) {
                ex.win32_last_error = 998; // ERROR_NOACCESS
                frame.finish(std.math.maxInt(u32)); // GetMessage returns -1
                return;
            }
            if (windowTraceEnabled()) {
                std.debug.print("PE32_WINDOW: GetMessage delivered msg=0x{X:0>4} hwnd=0x{X:0>8} wparam=0x{X:0>8}\n", .{ queued.message, queued.window, queued.wparam });
            }
            ex.win32_last_error = 0;
            frame.finish(if (queued.message == wm_quit) 0 else 1);
            return;
        }

        const pumped_events = if (ex.pe32_window_host.pump_events) |pump|
            pump(ex.pe32_window_host.context)
        else
            0;
        if (ex.pe32_window_host.window_is_key) |is_key| {
            updateWindowFocus(ex, is_key(ex.pe32_window_host.context) != 0);
        }
        // WM_PAINT is edge-triggered by an invalidated region. EndPaint marks
        // the current region valid; only a host event can invalidate it again.
        if (pumped_events != 0) {
            if (ex.topLevelPe32Window()) |window| {
                if (window.visible and !window.paint_queued) {
                    if (ex.findPe32Window(window.handle)) |mutable_window| {
                        mutable_window.paint_queued = ex.queuePe32WindowMessage(.{
                            .window = window.handle,
                            .message = wm_paint,
                        });
                        if (ex.pe32_window_handle == window.handle) ex.pe32_window_paint_queued = mutable_window.paint_queued;
                    }
                }
            }
        }
        if (ex.pe32_window_host.window_open) |is_open| {
            if (is_open(ex.pe32_window_host.context) == 0) {
                _ = ex.queuePe32WindowMessage(.{ .message = wm_quit });
                if (ex.topLevelPe32Window()) |window| {
                    if (ex.findPe32Window(window.handle)) |mutable_window| mutable_window.visible = false;
                }
                ex.pe32_window_visible = false;
                continue;
            }
        }

        const now_ns = monotonicNanoseconds();
        if (wait_started_ns == 0) wait_started_ns = now_ns;
        if (!wait_traced and windowTraceEnabled()) {
            var active_timers: u32 = 0;
            for (ex.pe32_window_timers) |timer| if (timer.active) {
                active_timers += 1;
            };
            std.debug.print("PE32_WINDOW: GetMessage waiting hwnd=0x{X:0>8} active_timers={d} host_pump={} wait_limit_ms={d}\n", .{
                ex.pe32_window_handle,
                active_timers,
                ex.pe32_window_host.pump_events != null,
                @divTrunc(wait_limit_ns, std.time.ns_per_ms),
            });
            wait_traced = true;
        }
        if (wait_limit_ns != 0 and now_ns >= wait_started_ns and now_ns - wait_started_ns >= wait_limit_ns) {
            if (windowTraceEnabled()) std.debug.print("PE32_WINDOW: diagnostic wait limit reached; posting WM_QUIT\n", .{});
            _ = ex.queuePe32WindowMessage(.{ .message = wm_quit });
            if (ex.topLevelPe32Window()) |window| {
                if (ex.findPe32Window(window.handle)) |mutable_window| mutable_window.visible = false;
            }
            ex.pe32_window_visible = false;
            continue;
        }
        _ = queueDueTimer(ex, now_ns);
        if (ex.pe32_window_message_count != 0) continue;

        // A headless executor cannot block for OS events. Keep deterministic
        // behavior there; hosted PE32 windows follow GetMessage's blocking
        // contract and wait for a message, timer tick, or window close.
        if (ex.pe32_window_host.pump_events == null and !hasActiveTimer(ex)) {
            ex.win32_last_error = 0;
            frame.finish(0);
            return;
        }

        var sleep_ns: u64 = 8 * std.time.ns_per_ms;
        for (ex.pe32_window_timers) |timer| {
            if (!timer.active or timer.message_queued or timer.next_due_ns <= now_ns) continue;
            sleep_ns = @min(sleep_ns, timer.next_due_ns - now_ns);
        }
        sleepNanoseconds(@max(sleep_ns, 1));
    }
}

fn peekMessageWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 5);
    const message_address = frame.arg(0);
    const remove = (frame.arg(4) & 1) != 0; // PM_REMOVE
    const message = if (remove)
        ex.popPe32WindowMessage()
    else if (ex.pe32_window_message_count != 0)
        ex.pe32_window_messages[ex.pe32_window_message_head]
    else
        null;
    if (message) |queued| {
        if (remove) acknowledgeTimerMessage(ex, queued);
        if (!writeMessage(ex, message_address, queued)) {
            ex.win32_last_error = 998;
            frame.finish(0);
            return;
        }
        ex.win32_last_error = 0;
        frame.finish(1);
    } else {
        frame.finish(0);
    }
}

fn translateMessageThunk(ex: *Executor) void {
    const address = abi.CallFrame.raw(ex, 1).arg(0);
    const valid = guestSlice(ex, address, 28) != null;
    ex.win32_last_error = if (valid) 0 else 998;
    abi.CallFrame.raw(ex, 1).finish(@intFromBool(valid));
}

fn dispatchMessageWThunk(ex: *Executor) void {
    const address = abi.CallFrame.raw(ex, 1).arg(0);
    const bytes = guestSlice(ex, address, 28) orelse {
        ex.win32_last_error = 998;
        abi.CallFrame.raw(ex, 1).finish(0);
        return;
    };
    const message: Executor.Pe32WindowMessage = .{
        .window = std.mem.readInt(u32, bytes[0..4], .little),
        .message = std.mem.readInt(u32, bytes[4..8], .little),
        .wparam = std.mem.readInt(u32, bytes[8..12], .little),
        .lparam = std.mem.readInt(u32, bytes[12..16], .little),
        .dispatch_callback = true,
    };
    if (ex.findPe32WindowConst(message.window) != null and message.message != 0x0012) {
        if (ex.pe32_window_callback == null) {
            ex.pe32_window_callback = message;
        } else if (ex.pe32_window_callback_followup == null) {
            ex.pe32_window_callback_followup = message;
        }
    }
    ex.win32_last_error = 0;
    abi.CallFrame.raw(ex, 1).finish(0);
}

fn defWindowProcWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 4);
    const message = frame.arg(1);
    // These defaults cover the creation/paint/input messages commonly sent
    // through DefWindowProc by a PE32 window procedure. The shim deliberately
    // does not fabricate a GDI paint result or host input event.
    const result: u32 = switch (message) {
        0x0081, // WM_NCCREATE: allow window creation
        0x000C, // WM_SETTEXT
        0x0020, // WM_SETCURSOR
        0x0021, // WM_MOUSEACTIVATE
        0x0024, // WM_GETMINMAXINFO is handled elsewhere; acknowledge safely
        0x0084, // WM_NCHITTEST: HTCLIENT
        0x0086, // WM_NCACTIVATE
        0x0087, // WM_GETDLGCODE
        0x0088, // WM_SYNCPAINT
        0x0014, // WM_ERASEBKGND
        0x0011, // WM_QUERYENDSESSION
        0x0013, // WM_QUERYOPEN
        => 1,
        else => 0,
    };
    frame.finish(result);
}

fn postQuitMessageThunk(ex: *Executor) void {
    const exit_code = abi.CallFrame.raw(ex, 1).arg(0);
    _ = ex.queuePe32WindowMessage(.{ .message = 0x0012, .wparam = exit_code }); // WM_QUIT
    abi.CallFrame.raw(ex, 1).finish(0);
}

fn postMessageWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 4);
    const window = frame.arg(0);
    const message = frame.arg(1);
    const wparam = frame.arg(2);
    const lparam = frame.arg(3);

    // WM_QUIT belongs to PostQuitMessage's thread queue, not a window queue.
    // Keep this shim's USER32 contract explicit and avoid treating it as a
    // normal window callback.
    if (message == 0x0012) {
        ex.win32_last_error = 87; // ERROR_INVALID_PARAMETER
        frame.finish(0);
        return;
    }
    if (window != 0 and ex.findPe32WindowConst(window) == null) {
        ex.win32_last_error = 1400; // ERROR_INVALID_WINDOW_HANDLE
        frame.finish(0);
        return;
    }
    if (!ex.queuePe32WindowMessage(.{
        .window = window,
        .message = message,
        .wparam = wparam,
        .lparam = lparam,
    })) {
        ex.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
        frame.finish(0);
        return;
    }

    if (windowTraceEnabled()) std.debug.print("PE32_WINDOW: PostMessage hwnd=0x{X:0>8} msg=0x{X:0>4} wparam=0x{X:0>8} lparam=0x{X:0>8}\n", .{ window, message, wparam, lparam });
    ex.win32_last_error = 0;
    frame.finish(1);
}

fn sendMessageWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 4);
    const window = frame.arg(0);
    const message = frame.arg(1);
    const wparam = frame.arg(2);
    const lparam = frame.arg(3);
    if (window == 0 or ex.findPe32WindowConst(window) == null) {
        ex.win32_last_error = 1400; // ERROR_INVALID_WINDOW_HANDLE
        frame.finish(0);
        return;
    }

    // The PE32 event loop owns all guest WNDPROC execution. Queue this
    // re-entrant SendMessage request so it is dispatched immediately after
    // the current WNDPROC returns; the Maze ignores SendMessage's result for
    // its private WM_USER+1 setup notification.
    if (!ex.queuePe32WindowMessage(.{
        .window = window,
        .message = message,
        .wparam = wparam,
        .lparam = lparam,
    })) {
        ex.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
        frame.finish(0);
        return;
    }
    if (windowTraceEnabled()) std.debug.print("PE32_WINDOW: SendMessage deferred hwnd=0x{X:0>8} msg=0x{X:0>4} wparam=0x{X:0>8} lparam=0x{X:0>8}\n", .{ window, message, wparam, lparam });
    ex.win32_last_error = 0;
    frame.finish(0);
}

fn getParentThunk(ex: *Executor) void {
    const hwnd = abi.CallFrame.raw(ex, 1).arg(0);
    const parent = if (ex.findPe32WindowConst(hwnd)) |window| window.parent else 0;
    ex.win32_last_error = if (hwnd == 0 or parent != 0 or ex.findPe32WindowConst(hwnd) != null) 0 else 1400;
    abi.CallFrame.raw(ex, 1).finish(parent);
}

fn createWindowExWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 12);
    const class_name = frame.arg(1);
    const title_address = frame.arg(2);
    const width_arg = frame.arg(6);
    const height_arg = frame.arg(7);
    const instance = frame.arg(10);
    const procedure = registeredProcedure(ex, class_name, instance) orelse {
        ex.win32_last_error = 1411; // ERROR_CLASS_DOES_NOT_EXIST
        frame.finish(0);
        return;
    };

    // SS_SCREENSAVER windows commonly use CW_USEDEFAULT or a negative extent;
    // this host bridge currently presents a fixed 1280x720 drawable.
    const width = if (width_arg > 0 and width_arg <= 8192) width_arg else 1280;
    const height = if (height_arg > 0 and height_arg <= 8192) height_arg else 720;
    var title_storage: [256]u8 = undefined;
    const title = guestWideAsciiZ(ex, title_address, &title_storage);
    if (windowTraceEnabled()) {
        std.debug.print("PE32_WINDOW: CreateWindowEx class=0x{X:0>8} title=\"{s}\" proc=0x{X:0>8} style=0x{X:0>8} exstyle=0x{X:0>8} parent=0x{X:0>8} requested={d}x{d}\n", .{
            class_name,
            std.mem.sliceTo(title, 0),
            procedure,
            frame.arg(3),
            frame.arg(0),
            frame.arg(8),
            width_arg,
            height_arg,
        });
    }
    const parent = frame.arg(8);
    const is_top_level = parent == 0 or parent == desktop_window_handle;
    if (is_top_level) if (ex.pe32_window_host.ensure_window) |ensure| {
        if (ensure(ex.pe32_window_host.context, width, height, title) == 0) {
            ex.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY / host window unavailable
            frame.finish(0);
            return;
        }
    };

    const created_handle = nextWindowHandle(ex) orelse {
        ex.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
        frame.finish(0);
        return;
    };
    const record = ex.findPe32Window(created_handle).?;
    record.procedure = procedure;
    record.parent = parent;
    record.x = @bitCast(frame.arg(4));
    record.y = @bitCast(frame.arg(5));
    record.width = width;
    record.height = height;
    record.visible = frame.arg(3) & 0x1000_0000 != 0; // WS_VISIBLE

    ex.pe32_window_handle = created_handle;
    ex.pe32_window_procedure = procedure;
    ex.pe32_window_x = record.x;
    ex.pe32_window_y = record.y;
    ex.pe32_window_width = width;
    ex.pe32_window_height = height;
    ex.pe32_window_visible = record.visible;
    ex.pe32_window_paint_queued = false;
    record.create_fields = .{
        frame.arg(11), // lpCreateParams
        instance,
        frame.arg(9), // hMenu
        frame.arg(8), // hwndParent
        height_arg, // cy (retain the guest-supplied value)
        width_arg, // cx
        frame.arg(5), // y
        frame.arg(4), // x
        frame.arg(3), // style
        title_address,
        class_name,
        frame.arg(0), // dwExStyle
    };
    ex.pe32_window_create_fields = record.create_fields;
    queueWindowCallback(ex, created_handle, 0x0081, 0, 0); // WM_NCCREATE
    queueWindowCallback(ex, created_handle, 0x0001, 0, 0); // WM_CREATE
    _ = ex.queuePe32WindowMessage(.{
        .window = created_handle,
        .message = 0x0005, // WM_SIZE
        .lparam = ((height & 0xFFFF) << 16) | (width & 0xFFFF),
    });
    _ = ex.queuePe32WindowMessage(.{ .window = created_handle, .message = 0x000F }); // WM_PAINT
    record.paint_queued = true;
    ex.pe32_window_paint_queued = record.paint_queued;
    ex.win32_last_error = 0;
    frame.finish(created_handle);
}

fn getDesktopWindowThunk(ex: *Executor) void {
    abi.CallFrame.raw(ex, 0).finish(desktop_window_handle);
}

fn getForegroundWindowThunk(ex: *Executor) void {
    const window = ex.topLevelPe32Window() orelse {
        abi.CallFrame.raw(ex, 0).finish(0);
        return;
    };
    abi.CallFrame.raw(ex, 0).finish(if (window.visible) window.handle else 0);
}

fn getFocusThunk(ex: *Executor) void {
    const window = if (ex.pe32_window_focused) ex.focusPe32Window() else null;
    abi.CallFrame.raw(ex, 0).finish(if (window) |focused| focused.handle else 0);
}

fn getCursorPosThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const address = frame.arg(0);
    const point = guestSlice(ex, address, 8) orelse {
        ex.win32_last_error = 998; // ERROR_NOACCESS
        frame.finish(0);
        return;
    };
    std.mem.writeInt(u32, point[0..4], @bitCast(ex.pe32_window_cursor_x), .little);
    std.mem.writeInt(u32, point[4..8], @bitCast(ex.pe32_window_cursor_y), .little);
    ex.win32_last_error = 0;
    frame.finish(1);
}

fn setCursorThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const cursor = frame.arg(0);
    const previous = ex.pe32_window_cursor_handle;
    ex.pe32_window_cursor_handle = cursor;
    ex.win32_last_error = 0;
    frame.finish(previous);
}

fn setForegroundWindowThunk(ex: *Executor) void {
    const hwnd = abi.CallFrame.raw(ex, 1).arg(0);
    const window = ex.findPe32WindowConst(hwnd);
    const valid = if (window) |record| isTopLevelWindow(record) else false;
    ex.win32_last_error = if (valid) 0 else 1400;
    abi.CallFrame.raw(ex, 1).finish(@intFromBool(valid));
}

fn showWindowThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const hwnd = frame.arg(0);
    const command = frame.arg(1);
    const window = ex.findPe32Window(hwnd) orelse {
        ex.win32_last_error = 1400; // ERROR_INVALID_WINDOW_HANDLE
        frame.finish(0);
        return;
    };
    const previously_visible = window.visible;
    if (command == 0) {
        window.visible = false;
    } else {
        if (isTopLevelWindow(window)) if (ex.pe32_window_host.show_window) |show| {
            if (show(ex.pe32_window_host.context) == 0) {
                ex.win32_last_error = 31; // ERROR_GEN_FAILURE
                frame.finish(@intFromBool(previously_visible));
                return;
            }
        };
        window.visible = true;
        queueWindowCallback(ex, hwnd, 0x0018, 1, 0); // WM_SHOWWINDOW
    }
    syncLegacyWindowFields(ex, window);
    ex.win32_last_error = 0;
    frame.finish(@intFromBool(previously_visible));
}

fn setWindowPosThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 7);
    const hwnd = frame.arg(0);
    const window = ex.findPe32Window(hwnd) orelse {
        ex.win32_last_error = 1400; // ERROR_INVALID_WINDOW_HANDLE
        frame.finish(0);
        return;
    };

    const x = frame.arg(2);
    const y = frame.arg(3);
    const width = frame.arg(4);
    const height = frame.arg(5);
    const flags = frame.arg(6);
    if (flags & 0x0002 == 0) { // SWP_NOMOVE
        window.x = @bitCast(x);
        window.y = @bitCast(y);
    }
    if (flags & 0x0001 == 0) { // SWP_NOSIZE
        const size_changed = width != window.width or height != window.height;
        window.width = width;
        window.height = height;
        if (size_changed) {
            _ = ex.queuePe32WindowMessage(.{
                .window = hwnd,
                .message = 0x0005, // WM_SIZE only follows an actual size change
                .lparam = ((height & 0xFFFF) << 16) | (width & 0xFFFF),
            });
        }
    }
    if (flags & 0x0080 != 0) { // SWP_HIDEWINDOW
        window.visible = false;
    } else if (flags & 0x0040 != 0) { // SWP_SHOWWINDOW
        if (isTopLevelWindow(window)) if (ex.pe32_window_host.show_window) |show| {
            if (show(ex.pe32_window_host.context) == 0) {
                ex.win32_last_error = 31; // ERROR_GEN_FAILURE
                frame.finish(0);
                return;
            }
        };
        window.visible = true;
        queueWindowCallback(ex, hwnd, 0x0018, 1, 0); // WM_SHOWWINDOW
    }

    syncLegacyWindowFields(ex, window);
    ex.win32_last_error = 0;
    frame.finish(1);
}

fn getDcThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const hwnd = frame.arg(0);
    if (ex.findPe32WindowConst(hwnd) != null or hwnd == desktop_window_handle) {
        ex.win32_last_error = 0;
        frame.finish(window_dc_handle);
    } else {
        ex.win32_last_error = 1400;
        frame.finish(0);
    }
}

fn releaseDcThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const hwnd = frame.arg(0);
    const dc = frame.arg(1);
    const valid_window = ex.findPe32WindowConst(hwnd) != null or hwnd == desktop_window_handle;
    const valid = valid_window and dc == window_dc_handle;
    ex.win32_last_error = if (valid) 0 else 6; // ERROR_INVALID_HANDLE
    frame.finish(@intFromBool(valid));
}

fn getClientRectThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const hwnd = frame.arg(0);
    const rect_address = frame.arg(1);
    const window = ex.findPe32WindowConst(hwnd);
    const valid_window = window != null or hwnd == desktop_window_handle;
    const rect = guestSlice(ex, rect_address, 16) orelse {
        ex.win32_last_error = 998; // ERROR_NOACCESS
        frame.finish(0);
        return;
    };
    if (!valid_window) {
        ex.win32_last_error = 1400;
        frame.finish(0);
        return;
    }
    const width = if (hwnd == desktop_window_handle) 1280 else window.?.width;
    const height = if (hwnd == desktop_window_handle) 720 else window.?.height;
    std.mem.writeInt(u32, rect[0..4], 0, .little);
    std.mem.writeInt(u32, rect[4..8], 0, .little);
    std.mem.writeInt(u32, rect[8..12], width, .little);
    std.mem.writeInt(u32, rect[12..16], height, .little);
    ex.win32_last_error = 0;
    frame.finish(1);
}

fn isWindowThunk(ex: *Executor) void {
    const hwnd = abi.CallFrame.raw(ex, 1).arg(0);
    const valid = ex.findPe32WindowConst(hwnd) != null;
    abi.CallFrame.raw(ex, 1).finish(@intFromBool(valid));
}

fn destroyWindowThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const hwnd = frame.arg(0);
    const valid = ex.findPe32WindowConst(hwnd) != null;
    if (valid) {
        if (ex.findPe32Window(hwnd)) |window| {
            window.visible = false;
            window.active = false;
        }
        for (&ex.pe32_windows) |*window| {
            if (window.active and window.parent == hwnd) window.active = false;
        }
        if (ex.pe32_window_handle == hwnd or ex.findPe32Window(ex.pe32_window_handle) == null) {
            if (ex.topLevelPe32Window()) |window| {
                ex.pe32_window_handle = window.handle;
                syncLegacyWindowFields(ex, window);
            } else {
                ex.pe32_window_handle = 0;
                ex.pe32_window_procedure = 0;
                ex.pe32_window_visible = false;
            }
        }
        for (&ex.pe32_window_timers) |*timer| {
            if (timer.active and timer.window == hwnd) timer.active = false;
        }
    }
    ex.win32_last_error = if (valid) 0 else 1400;
    frame.finish(@intFromBool(valid));
}

fn setTimerThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 4);
    const window = frame.arg(0);
    var timer_id = frame.arg(1);
    const interval_ms = @max(frame.arg(2), minimum_timer_interval_ms);
    const callback = frame.arg(3);
    if ((window != 0 and ex.findPe32WindowConst(window) == null) or callback != 0) {
        ex.win32_last_error = if (callback != 0) 120 else 1400; // ERROR_CALL_NOT_IMPLEMENTED / INVALID_WINDOW_HANDLE
        frame.finish(0);
        return;
    }

    if (window == 0 or timer_id == 0) {
        timer_id = ex.pe32_window_next_timer_id;
        ex.pe32_window_next_timer_id +%= 1;
        if (timer_id == 0) {
            timer_id = ex.pe32_window_next_timer_id;
            ex.pe32_window_next_timer_id +%= 1;
        }
    }

    var free_slot: ?*Executor.Pe32WindowTimer = null;
    for (&ex.pe32_window_timers) |*timer| {
        if (timer.active and timer.window == window and timer.id == timer_id) {
            free_slot = timer;
            break;
        }
        if (!timer.active and free_slot == null) free_slot = timer;
    }
    const timer = free_slot orelse {
        ex.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
        frame.finish(0);
        return;
    };
    const interval_ns = @as(u64, interval_ms) * std.time.ns_per_ms;
    timer.* = .{
        .active = true,
        .window = window,
        .id = timer_id,
        .interval_ns = interval_ns,
        .next_due_ns = monotonicNanoseconds() +| interval_ns,
    };
    if (windowTraceEnabled()) std.debug.print("PE32_WINDOW: SetTimer hwnd=0x{X:0>8} id={d} interval_ms={d}\n", .{ window, timer_id, interval_ms });
    ex.win32_last_error = 0;
    frame.finish(timer_id);
}

fn killTimerThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const window = frame.arg(0);
    const timer_id = frame.arg(1);
    var killed = false;
    for (&ex.pe32_window_timers) |*timer| {
        if (timer.active and timer.window == window and timer.id == timer_id) {
            timer.active = false;
            timer.message_queued = false;
            killed = true;
        }
    }
    if (windowTraceEnabled()) std.debug.print("PE32_WINDOW: KillTimer hwnd=0x{X:0>8} id={d} killed={}\n", .{ window, timer_id, killed });
    ex.win32_last_error = 0;
    frame.finish(@intFromBool(killed));
}

fn getAsyncKeyStateThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const virtual_key = frame.arg(0);
    const down = if (ex.pe32_window_host.async_key_state) |read|
        read(ex.pe32_window_host.context, virtual_key) != 0
    else
        false;
    // Win32 returns SHORT, sign-extended by the x86 ABI. Bit 15 means held.
    const result: i16 = if (down) -32768 else 0;
    frame.finish(@bitCast(@as(i32, result)));
}

fn getUpdateRectThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 3);
    // The host window invalidates only through AppKit's own redraw pipeline;
    // this PE32 route does not fabricate a GDI update region.
    frame.finish(0);
}

fn beginPaintThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const hwnd = frame.arg(0);
    const paint_address = frame.arg(1);
    const window = ex.findPe32Window(hwnd) orelse {
        ex.win32_last_error = 1400; // ERROR_INVALID_WINDOW_HANDLE
        frame.finish(0);
        return;
    };
    const paint = guestSlice(ex, paint_address, 64) orelse {
        ex.win32_last_error = 998; // ERROR_NOACCESS
        frame.finish(0);
        return;
    };

    // PAINTSTRUCT is 64 bytes in the PE32 ABI. The returned HDC is a stable
    // synthetic handle used by the GDI compatibility layer; it is not a
    // native drawing surface and does not claim that guest pixels were drawn.
    @memset(paint, 0);
    std.mem.writeInt(u32, paint[0..4], window_dc_handle, .little);
    std.mem.writeInt(u32, paint[8..12], 0, .little); // rcPaint.left
    std.mem.writeInt(u32, paint[12..16], 0, .little); // rcPaint.top
    std.mem.writeInt(u32, paint[16..20], window.width, .little); // rcPaint.right
    std.mem.writeInt(u32, paint[20..24], window.height, .little); // rcPaint.bottom
    window.paint_active = true;
    syncLegacyWindowFields(ex, window);
    ex.win32_last_error = 0;
    frame.finish(window_dc_handle);
}

fn endPaintThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const hwnd = frame.arg(0);
    const paint_address = frame.arg(1);
    const window = ex.findPe32Window(hwnd) orelse {
        ex.win32_last_error = 1400; // ERROR_INVALID_WINDOW_HANDLE
        frame.finish(0);
        return;
    };
    const paint = guestSlice(ex, paint_address, 64) orelse {
        ex.win32_last_error = 998; // ERROR_NOACCESS
        frame.finish(0);
        return;
    };
    const dc = std.mem.readInt(u32, paint[0..4], .little);
    const valid = window.paint_active and dc == window_dc_handle;
    window.paint_active = false;
    window.paint_queued = false;
    syncLegacyWindowFields(ex, window);
    ex.win32_last_error = if (valid) 0 else 6; // ERROR_INVALID_HANDLE
    frame.finish(@intFromBool(valid));
}

fn getSystemMetricsThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const index = frame.arg(0);
    frame.finish(switch (index) {
        0, 16, 61, 78 => 1280, // SM_CXSCREEN/CXFULLSCREEN/CXMAXIMIZED/CXVIRTUALSCREEN
        1, 17, 62, 79 => 720, // SM_CYSCREEN/CYFULLSCREEN/CYMAXIMIZED/CYVIRTUALSCREEN
        76, 77 => 0, // SM_XVIRTUALSCREEN/SM_YVIRTUALSCREEN
        80 => 1, // SM_CMONITORS
        else => 0,
    });
}

fn loadSharedResourceHandle(ex: *Executor, is_icon: bool) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const module = frame.arg(0);
    const resource = frame.arg(1);
    // A null module selects the operating-system shared resource table. The
    // supported standard IDs are integer resources, not guest pointers.
    const known_system_id = resource <= 0xFFFF and switch (resource) {
        32512...32516, 32640...32646 => true,
        else => false,
    };
    const result = if (module == 0 and known_system_id)
        (if (is_icon) icon_handle_base else cursor_handle_base) | (resource + 1)
    else
        0;
    ex.win32_last_error = if (result != 0) 0 else 1814;
    frame.finish(result);
}

fn loadCursorWThunk(ex: *Executor) void {
    loadSharedResourceHandle(ex, false);
}

fn loadIconWThunk(ex: *Executor) void {
    loadSharedResourceHandle(ex, true);
}

pub fn register(ex: *Executor) void {
    ex.import_table.put("GetSystemMetrics", getSystemMetricsThunk) catch {};
    ex.import_table.put("LoadCursorW", loadCursorWThunk) catch {};
    ex.import_table.put("LoadIconW", loadIconWThunk) catch {};
    ex.import_table.put("RegisterClassW", registerClassWThunk) catch {};
    ex.import_table.put("CreateWindowExW", createWindowExWThunk) catch {};
    ex.import_table.put("GetDesktopWindow", getDesktopWindowThunk) catch {};
    ex.import_table.put("GetForegroundWindow", getForegroundWindowThunk) catch {};
    ex.import_table.put("GetFocus", getFocusThunk) catch {};
    ex.import_table.put("GetCursorPos", getCursorPosThunk) catch {};
    ex.import_table.put("SetCursor", setCursorThunk) catch {};
    ex.import_table.put("SetForegroundWindow", setForegroundWindowThunk) catch {};
    ex.import_table.put("ShowWindow", showWindowThunk) catch {};
    ex.import_table.put("SetWindowPos", setWindowPosThunk) catch {};
    ex.import_table.put("GetDC", getDcThunk) catch {};
    ex.import_table.put("ReleaseDC", releaseDcThunk) catch {};
    ex.import_table.put("GetClientRect", getClientRectThunk) catch {};
    ex.import_table.put("IsWindow", isWindowThunk) catch {};
    ex.import_table.put("DestroyWindow", destroyWindowThunk) catch {};
    ex.import_table.put("GetUpdateRect", getUpdateRectThunk) catch {};
    ex.import_table.put("BeginPaint", beginPaintThunk) catch {};
    ex.import_table.put("EndPaint", endPaintThunk) catch {};
    ex.import_table.put("GetMessageW", getMessageWThunk) catch {};
    ex.import_table.put("PeekMessageW", peekMessageWThunk) catch {};
    ex.import_table.put("TranslateMessage", translateMessageThunk) catch {};
    ex.import_table.put("DispatchMessageW", dispatchMessageWThunk) catch {};
    ex.import_table.put("DefWindowProcW", defWindowProcWThunk) catch {};
    ex.import_table.put("PostMessageW", postMessageWThunk) catch {};
    ex.import_table.put("SendMessageW", sendMessageWThunk) catch {};
    ex.import_table.put("GetParent", getParentThunk) catch {};
    ex.import_table.put("PostQuitMessage", postQuitMessageThunk) catch {};
    ex.import_table.put("SetTimer", setTimerThunk) catch {};
    ex.import_table.put("KillTimer", killTimerThunk) catch {};
    ex.import_table.put("GetAsyncKeyState", getAsyncKeyStateThunk) catch {};
}

test "GetSystemMetrics exposes the PE64 route virtual desktop contract" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register(&ex);

    ex.push(0); // SM_CXSCREEN
    ex.dispatch_import("GetSystemMetrics");
    try std.testing.expectEqual(@as(u32, 1280), ex.regs.eax);

    ex.regs.esp = 3072;
    ex.push(1); // SM_CYSCREEN
    ex.dispatch_import("GetSystemMetrics");
    try std.testing.expectEqual(@as(u32, 720), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 3072), ex.regs.esp);

    ex.push(0x7F00); // IDC_ARROW
    ex.push(0); // Shared system cursor table
    ex.dispatch_import("LoadCursorW");
    try std.testing.expectEqual(cursor_handle_base | 0x7F01, ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 3072), ex.regs.esp);
}

test "RegisterClassW records PE32 procedure and returns a stable atom" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register(&ex);

    const class_address: u32 = 512;
    const name_address: u32 = 768;
    ex.mem.write32(class_address + 4, 0x00401234);
    ex.mem.write32(class_address + 16, 0x00400000);
    ex.mem.write32(class_address + 36, name_address);
    ex.mem.write16(name_address, 'M');
    ex.mem.write16(name_address + 2, 'a');
    ex.mem.write16(name_address + 4, 'z');
    ex.mem.write16(name_address + 6, 'e');
    ex.mem.write16(name_address + 8, 0);

    ex.push(class_address);
    ex.dispatch_import("RegisterClassW");
    try std.testing.expectEqual(window_class_atom_base, @as(u16, @truncate(ex.regs.eax)));
    try std.testing.expectEqual(@as(u32, 1), @as(u32, @intCast(ex.pe32_window_class_count)));
    try std.testing.expectEqual(@as(u32, 0x00401234), ex.pe32_window_classes[0].procedure);
    try std.testing.expectEqual(@as(u32, 0), ex.win32_last_error);

    ex.regs.esp = 3072;
    ex.push(class_address);
    ex.dispatch_import("RegisterClassW");
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 1410), ex.win32_last_error);
    try std.testing.expectEqual(@as(u32, 3072), ex.regs.esp);
}

test "CreateWindowExW resolves a registered class and exposes its client rectangle" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register(&ex);

    const class_address: u32 = 512;
    const name_address: u32 = 768;
    const title_address: u32 = 800;
    ex.mem.write32(class_address + 4, 0x00401234);
    ex.mem.write32(class_address + 16, 0x00400000);
    ex.mem.write32(class_address + 36, name_address);
    ex.mem.write16(name_address, 'M');
    ex.mem.write16(name_address + 2, 'a');
    ex.mem.write16(name_address + 4, 'z');
    ex.mem.write16(name_address + 6, 'e');
    ex.mem.write16(name_address + 8, 0);
    ex.mem.write16(title_address, 'T');
    ex.mem.write16(title_address + 2, 'e');
    ex.mem.write16(title_address + 4, 's');
    ex.mem.write16(title_address + 6, 't');
    ex.mem.write16(title_address + 8, 0);
    ex.push(class_address);
    ex.dispatch_import("RegisterClassW");
    try std.testing.expectEqual(@as(u32, window_class_atom_base), ex.regs.eax);

    // Raw Win32 argument order for CreateWindowExW, written as it appears at
    // the callee's ESP after the caller has pushed its arguments.
    const args = [_]u32{
        0, // extended style
        window_class_atom_base,
        title_address,
        0x1000_0000, // visible overlapped window
        0,
        0,
        640,
        480,
        0,
        0,
        0x0040_0000,
        0x0020_0100, // lpParam: app-owned window state expected by WM_CREATE
    };
    ex.regs.esp = 2048;
    for (args, 0..) |value, index| ex.mem.write32(2048 + @as(u32, @intCast(index * 4)), value);
    ex.dispatch_import("CreateWindowExW");
    try std.testing.expectEqual(created_window_handle, ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 640), ex.pe32_window_width);
    try std.testing.expectEqual(@as(u32, 480), ex.pe32_window_height);
    try std.testing.expectEqual(@as(u32, 0x0020_0100), ex.pe32_window_create_fields[0]);
    try std.testing.expectEqual(@as(u32, 0x0040_0000), ex.pe32_window_create_fields[1]);
    try std.testing.expectEqual(@as(u32, title_address), ex.pe32_window_create_fields[9]);
    try std.testing.expectEqual(@as(u32, window_class_atom_base), ex.pe32_window_create_fields[10]);
    try std.testing.expect(ex.pe32_window_callback.?.create_struct);
    try std.testing.expectEqual(@as(u32, 0x0081), ex.pe32_window_callback.?.message);
    try std.testing.expect(ex.pe32_window_callback_followup.?.create_struct);
    try std.testing.expectEqual(@as(u32, 0x0001), ex.pe32_window_callback_followup.?.message);

    ex.regs.esp = 2048;
    ex.mem.write32(2048, created_window_handle);
    ex.mem.write32(2052, 2200);
    ex.dispatch_import("GetClientRect");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 640), ex.mem.read32(2208));
    try std.testing.expectEqual(@as(u32, 480), ex.mem.read32(2212));
}

test "DefWindowProcW supplies standard creation and erase-background results" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register(&ex);

    ex.push(0); // lParam
    ex.push(0); // wParam
    ex.push(0x0081); // WM_NCCREATE
    ex.push(created_window_handle); // hwnd
    ex.dispatch_import("DefWindowProcW");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);

    ex.regs.esp = 3072;
    ex.push(0); // lParam
    ex.push(0); // wParam
    ex.push(0x0014); // WM_ERASEBKGND
    ex.push(created_window_handle); // hwnd
    ex.dispatch_import("DefWindowProcW");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);

    ex.regs.esp = 3072;
    ex.push(0); // lParam
    ex.push(0); // wParam
    ex.push(0x0400); // WM_USER
    ex.push(created_window_handle); // hwnd
    ex.dispatch_import("DefWindowProcW");
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
}

test "cursor calls read and update bounded PE32 window state" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register(&ex);

    ex.regs.esp = 2048;
    ex.push(1024);
    ex.dispatch_import("GetCursorPos");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0), ex.mem.read32(1024));
    try std.testing.expectEqual(@as(u32, 0), ex.mem.read32(1028));

    ex.regs.esp = 2048;
    ex.push(0xF200_7F01);
    ex.dispatch_import("SetCursor");
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0xF200_7F01), ex.pe32_window_cursor_handle);

    ex.regs.esp = 2048;
    ex.push(0);
    ex.dispatch_import("SetCursor");
    try std.testing.expectEqual(@as(u32, 0xF200_7F01), ex.regs.eax);
}

test "SetWindowPos updates guest geometry and honors move and size flags" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.pe32_window_handle = created_window_handle;
    ex.pe32_window_width = 640;
    ex.pe32_window_height = 480;
    register(&ex);

    const args = [_]u32{ created_window_handle, 0, 14, 25, 800, 600, 0 };
    ex.regs.esp = 2048;
    for (args, 0..) |value, index| ex.mem.write32(2048 + @as(u32, @intCast(index * 4)), value);
    ex.dispatch_import("SetWindowPos");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expectEqual(@as(i32, 14), ex.pe32_window_x);
    try std.testing.expectEqual(@as(i32, 25), ex.pe32_window_y);
    try std.testing.expectEqual(@as(u32, 800), ex.pe32_window_width);
    try std.testing.expectEqual(@as(u32, 600), ex.pe32_window_height);
    try std.testing.expectEqual(@as(usize, 1), ex.pe32_window_message_count);
    try std.testing.expectEqual(@as(u32, 0x0005), ex.pe32_window_messages[0].message);

    // A window procedure may call SetWindowPos while handling WM_SIZE. If it
    // supplies the existing dimensions, Windows does not generate another
    // WM_SIZE; duplicating it here can turn layout into an endless guest loop.
    _ = ex.popPe32WindowMessage();
    const same_size_args = [_]u32{ created_window_handle, 0, 14, 25, 800, 600, 0 };
    ex.regs.esp = 2048;
    for (same_size_args, 0..) |value, index| ex.mem.write32(2048 + @as(u32, @intCast(index * 4)), value);
    ex.dispatch_import("SetWindowPos");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expectEqual(@as(usize, 0), ex.pe32_window_message_count);

    const unchanged_args = [_]u32{ created_window_handle, 0, 90, 91, 1200, 1000, 0x0003 };
    ex.regs.esp = 2048;
    for (unchanged_args, 0..) |value, index| ex.mem.write32(2048 + @as(u32, @intCast(index * 4)), value);
    ex.dispatch_import("SetWindowPos");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expectEqual(@as(i32, 14), ex.pe32_window_x);
    try std.testing.expectEqual(@as(i32, 25), ex.pe32_window_y);
    try std.testing.expectEqual(@as(u32, 800), ex.pe32_window_width);
    try std.testing.expectEqual(@as(u32, 600), ex.pe32_window_height);
    try std.testing.expectEqual(@as(usize, 0), ex.pe32_window_message_count);

    ex.regs.esp = 2048;
    ex.mem.write32(2048, desktop_window_handle);
    ex.dispatch_import("SetWindowPos");
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 1400), ex.win32_last_error);
}

test "GetMessageW does not continuously synthesize paints for a valid window" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.pe32_window_handle = created_window_handle;
    ex.pe32_window_visible = true;
    register(&ex);

    const message_address: u32 = 1024;
    ex.regs.esp = 2048;
    ex.mem.write32(2048, message_address);
    ex.mem.write32(2052, 0);
    ex.mem.write32(2056, 0);
    ex.mem.write32(2060, 0);
    ex.dispatch_import("GetMessageW");

    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(usize, 0), ex.pe32_window_message_count);
    try std.testing.expect(!ex.pe32_window_paint_queued);
}

test "PostMessageW queues the exact guest message and rejects invalid targets" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.pe32_window_handle = created_window_handle;
    register(&ex);

    const args = [_]u32{ created_window_handle, 0x0402, 0xAABBCCDD, 0x12345678 };
    ex.regs.esp = 2048;
    for (args, 0..) |value, index| ex.mem.write32(2048 + @as(u32, @intCast(index * 4)), value);
    ex.dispatch_import("PostMessageW");

    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0), ex.win32_last_error);
    try std.testing.expectEqual(@as(usize, 1), ex.pe32_window_message_count);
    const queued = ex.popPe32WindowMessage().?;
    try std.testing.expectEqual(created_window_handle, queued.window);
    try std.testing.expectEqual(@as(u32, 0x0402), queued.message);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), queued.wparam);
    try std.testing.expectEqual(@as(u32, 0x12345678), queued.lparam);

    ex.regs.esp = 2048;
    ex.mem.write32(2048, 0x9999);
    ex.mem.write32(2052, 0x0402);
    ex.mem.write32(2056, 0);
    ex.mem.write32(2060, 0);
    ex.dispatch_import("PostMessageW");
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 1400), ex.win32_last_error);
}

test "host focus transitions queue one Win32 focus callback each" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.pe32_window_handle = created_window_handle;
    ex.pe32_window_procedure = 0x00401234;

    updateWindowFocus(&ex, true);
    try std.testing.expect(ex.pe32_window_focused);
    try std.testing.expectEqual(@as(u32, 0x0007), ex.pe32_window_callback.?.message);
    updateWindowFocus(&ex, true);
    try std.testing.expect(ex.pe32_window_callback_followup == null);

    ex.pe32_window_callback = null;
    updateWindowFocus(&ex, false);
    try std.testing.expect(!ex.pe32_window_focused);
    try std.testing.expectEqual(@as(u32, 0x0008), ex.pe32_window_callback.?.message);
}

test "SetTimer delivers coalesced WM_TIMER messages and KillTimer removes the timer" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.pe32_window_handle = created_window_handle;
    register(&ex);

    const timer_args = [_]u32{ created_window_handle, 7, 10, 0 };
    ex.regs.esp = 2048;
    for (timer_args, 0..) |value, index| ex.mem.write32(2048 + @as(u32, @intCast(index * 4)), value);
    ex.dispatch_import("SetTimer");
    try std.testing.expectEqual(@as(u32, 7), ex.regs.eax);
    try std.testing.expect(ex.pe32_window_timers[0].active);

    const message_address: u32 = 1024;
    ex.regs.esp = 2048;
    ex.mem.write32(2048, message_address);
    ex.mem.write32(2052, 0);
    ex.mem.write32(2056, 0);
    ex.mem.write32(2060, 0);
    ex.dispatch_import("GetMessageW");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expectEqual(created_window_handle, ex.mem.read32(message_address));
    try std.testing.expectEqual(wm_timer, ex.mem.read32(message_address + 4));
    try std.testing.expectEqual(@as(u32, 7), ex.mem.read32(message_address + 8));

    ex.regs.esp = 2048;
    ex.mem.write32(2048, created_window_handle);
    ex.mem.write32(2052, 7);
    ex.dispatch_import("KillTimer");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expect(!ex.pe32_window_timers[0].active);
}

test "GetAsyncKeyState returns the Win32 high bit for a held virtual key" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.pe32_window_host.async_key_state = testAsyncKeyState;
    register(&ex);

    ex.regs.esp = 2048;
    ex.mem.write32(2048, 0x25); // VK_LEFT
    ex.dispatch_import("GetAsyncKeyState");
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), ex.regs.eax);

    ex.regs.esp = 2048;
    ex.mem.write32(2048, 0x41); // unsupported in this test callback
    ex.dispatch_import("GetAsyncKeyState");
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
}

fn testAsyncKeyState(_: ?*anyopaque, virtual_key: u32) callconv(.c) c_int {
    return if (virtual_key == 0x25) 1 else 0;
}

test "BeginPaint and EndPaint expose a bounded synthetic PE32 paint record" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.pe32_window_handle = created_window_handle;
    ex.pe32_window_width = 640;
    ex.pe32_window_height = 480;
    register(&ex);

    const paint_address: u32 = 1024;
    ex.regs.esp = 2048;
    ex.mem.write32(2048, created_window_handle);
    ex.mem.write32(2052, paint_address);
    ex.dispatch_import("BeginPaint");
    try std.testing.expectEqual(window_dc_handle, ex.regs.eax);
    try std.testing.expect(ex.pe32_window_paint_active);
    try std.testing.expectEqual(window_dc_handle, ex.mem.read32(paint_address));
    try std.testing.expectEqual(@as(u32, 640), ex.mem.read32(paint_address + 16));
    try std.testing.expectEqual(@as(u32, 480), ex.mem.read32(paint_address + 20));

    ex.regs.esp = 2048;
    ex.mem.write32(2048, created_window_handle);
    ex.mem.write32(2052, paint_address);
    ex.dispatch_import("EndPaint");
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expect(!ex.pe32_window_paint_active);
    try std.testing.expect(!ex.pe32_window_paint_queued);

    ex.regs.esp = 2048;
    ex.mem.write32(2048, desktop_window_handle);
    ex.mem.write32(2052, paint_address);
    ex.dispatch_import("BeginPaint");
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 1400), ex.win32_last_error);
}
