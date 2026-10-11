const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const process_impl_run_reporting = @import("run_reporting.zig");
const process_impl_windows_sync = @import("windows_sync.zig");
const __process_SYNTHETIC_WINDOWS_AUDIO_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_AUDIO_RETURN;
const __process_SYNTHETIC_WINDOWS_MESSAGE_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_MESSAGE_RETURN;
const __process_WINDOWS_GCLP_WNDPROC = __ProcessInternals._WINDOWS_GCLP_WNDPROC;
const __process_WINDOWS_GWLP_USERDATA = __ProcessInternals._WINDOWS_GWLP_USERDATA;
const __process_WINDOWS_GWL_EXSTYLE = __ProcessInternals._WINDOWS_GWL_EXSTYLE;
const __process_WINDOWS_GWL_STYLE = __ProcessInternals._WINDOWS_GWL_STYLE;
const __process_WINDOWS_WM_PAINT = __ProcessInternals._WINDOWS_WM_PAINT;
const __process_WindowsMessage = __ProcessInternals._WindowsMessage;
const __process_WindowsWindow = __ProcessInternals._WindowsWindow;
const __process_WindowsWindowClass = __ProcessInternals._WindowsWindowClass;
const __process_concurrency = __ProcessInternals._concurrency;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_log = __ProcessInternals._log;
const __process_monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const __process_runtime_lock_released_ns = __ProcessInternals._runtime_lock_released_ns;
const __process_std = __ProcessInternals._std;
const __process_windows_guest_abi = __ProcessInternals._windows_guest_abi;
const __process_windows_message_queue = __ProcessInternals._windows_message_queue;
const __process_windows_message_wait = __ProcessInternals._windows_message_wait;
const __process_windows_runtime_locks = __ProcessInternals._windows_runtime_locks;
const __process_windows_ui_ledger = __ProcessInternals._windows_ui_ledger;
const __state_GuestWaitPark = __StateInternals._GuestWaitPark;
const __state_OwnerWaitOutcome = __StateInternals._OwnerWaitOutcome;
const __state_guest_wait_slice_ns = __StateInternals._guest_wait_slice_ns;

pub fn requestWindowsUiQuit(self: *ElfState) void {
    self.windows_ui_quit_requested = true;
    self.windows_message_event.notify();
}

pub fn captureWindowsClassName(self: *const ElfState, record: *__process_WindowsWindowClass, name_ptr: u64, wide: bool) void {
    record.name_ptr = name_ptr;
    record.name_len = 0;
    record.wide = wide;
    @memset(record.name[0..], 0);
    if (name_ptr == 0) return;

    if (wide) {
        while (record.name_len < record.name.len - 1) {
            const address = name_ptr +| @as(u64, @intCast(record.name_len * 2));
            if (process_impl_execution.guestMemoryConst(self, address, 2) == null) break;
            const unit = process_impl_guest_memory.read16(self, address);
            if (unit == 0) break;
            record.name[record.name_len] = if (unit <= 0x7f) @intCast(unit) else '?';
            record.name_len += 1;
        }
    } else {
        while (record.name_len < record.name.len - 1) {
            const address = name_ptr +| @as(u64, @intCast(record.name_len));
            if (process_impl_execution.guestMemoryConst(self, address, 1) == null) break;
            const byte = process_impl_guest_memory.read8(self, address);
            if (byte == 0) break;
            record.name[record.name_len] = byte;
            record.name_len += 1;
        }
    }
}

pub fn windowsClassMatches(self: *const ElfState, record: *const __process_WindowsWindowClass, class_name: u64, wide: bool) bool {
    if (!record.valid or class_name == 0) return false;
    if (class_name <= 0xffff and record.atom == @as(u16, @intCast(class_name))) return true;
    if (record.name_ptr == class_name) return true;
    if (record.name_len == 0) return false;

    for (0..record.name_len) |index| {
        const address = class_name +| if (wide)
            @as(u64, @intCast(index * 2))
        else
            @as(u64, @intCast(index));
        const actual: u8 = if (wide) blk: {
            if (process_impl_execution.guestMemoryConst(self, address, 2) == null) return false;
            const unit = process_impl_guest_memory.read16(self, address);
            if (unit > 0x7f) return false;
            break :blk @intCast(unit);
        } else blk: {
            if (process_impl_execution.guestMemoryConst(self, address, 1) == null) return false;
            break :blk process_impl_guest_memory.read8(self, address);
        };
        if (actual != record.name[index]) return false;
    }

    const terminator = class_name +| if (wide)
        @as(u64, @intCast(record.name_len * 2))
    else
        @as(u64, @intCast(record.name_len));
    if (process_impl_execution.guestMemoryConst(self, terminator, if (wide) 2 else 1) == null) return false;
    return if (wide) process_impl_guest_memory.read16(self, terminator) == 0 else process_impl_guest_memory.read8(self, terminator) == 0;
}

pub fn windowsClassIndex(self: *const ElfState, class_name: u64, wide: bool) ?usize {
    for (self.windows_window_classes, 0..) |record, index| {
        if (windowsClassMatches(self, &record, class_name, wide)) return index;
    }
    return null;
}

pub fn registerWindowsWindowClass(self: *ElfState, class_info: u64, wide: bool) u64 {
    if (class_info == 0 or process_impl_execution.guestMemoryConst(self, class_info, 72) == null) return 0;
    const wnd_proc = process_impl_guest_memory.read64(self, class_info + 8);
    const class_name = process_impl_guest_memory.read64(self, class_info + 64);
    if (wnd_proc == 0 or class_name == 0) return 0;
    self.windows_ui_pipeline.noteClassRegistered();

    if (windowsClassIndex(self, class_name, wide)) |existing| {
        self.windows_window_classes[existing].wnd_proc = wnd_proc;
        return self.windows_window_classes[existing].atom;
    }

    var free_index: ?usize = null;
    for (self.windows_window_classes, 0..) |record, index| {
        if (!record.valid) {
            free_index = index;
            break;
        }
    }
    const index = free_index orelse return 0;
    const atom = self.windows_next_window_class_atom;
    self.windows_next_window_class_atom +|= 1;
    if (self.windows_next_window_class_atom == 0) self.windows_next_window_class_atom = 1;

    var record = __process_WindowsWindowClass{
        .valid = true,
        .atom = if (atom == 0) 1 else atom,
        .wnd_proc = wnd_proc,
        .wide = wide,
    };
    captureWindowsClassName(self, &record, class_name, wide);
    self.windows_window_classes[index] = record;
    return record.atom;
}

pub fn createWindowsWindow(
    self: *ElfState,
    handle: u64,
    class_name: u64,
    user_data: u64,
    message_only: bool,
    style: u64,
    ex_style: u64,
    wide: bool,
) bool {
    if (handle == 0 or windowsWindowIndex(self, handle) != null) return false;
    var free_index: ?usize = null;
    for (self.windows_windows, 0..) |record, index| {
        if (!record.valid) {
            free_index = index;
            break;
        }
    }
    const index = free_index orelse return false;
    const class_index = windowsClassIndex(self, class_name, wide);
    self.windows_windows[index] = .{
        .valid = true,
        .handle = handle,
        .class_atom = if (class_index) |class_index_value| self.windows_window_classes[class_index_value].atom else 0,
        .wnd_proc = if (class_index) |class_index_value| self.windows_window_classes[class_index_value].wnd_proc else 0,
        .user_data = user_data,
        .style = @truncate(style),
        .ex_style = @truncate(ex_style),
        .message_only = message_only,
        .creator_thread_id = process_impl_lifecycle.currentWindowsThreadId(self),
    };
    // Xenia's pending-functions window is found by its class: SDL's
    // helper window and Xenia's other message-only windows come after it,
    // and following the latest one lost every later handoff.
    const pending_functions_window = if (class_index) |class_index_value| blk: {
        const class = &self.windows_window_classes[class_index_value];
        break :blk __process_std.mem.eql(u8, class.name[0..class.name_len], __process_windows_ui_ledger.xenia_pending_function_class);
    } else false;
    self.windows_ui_pipeline.noteWindowCreated(handle, message_only, self.windows_windows[index].wnd_proc, user_data, pending_functions_window);
    if (message_only and (pending_functions_window or self.windows_message_window_handle == 0)) self.windows_message_window_handle = handle;
    return true;
}

pub fn windowsWindowIndex(self: *const ElfState, handle: u64) ?usize {
    for (self.windows_windows, 0..) |record, index| {
        if (record.valid and record.handle == handle) return index;
    }
    return null;
}

pub fn isWindowsWindowHandle(self: *const ElfState, handle: u64) bool {
    return windowsWindowIndex(self, handle) != null;
}

pub fn windowsWindowProc(self: *const ElfState, handle: u64) ?u64 {
    const index = windowsWindowIndex(self, handle) orelse return null;
    const proc = self.windows_windows[index].wnd_proc;
    return if (proc == 0) null else proc;
}

pub fn windowsWindowLong(self: *const ElfState, handle: u64, index: i64) ?u64 {
    const window_index = windowsWindowIndex(self, handle) orelse return null;
    const record = self.windows_windows[window_index];
    return switch (index) {
        __process_WINDOWS_GWLP_USERDATA => record.user_data,
        __process_WINDOWS_GWL_STYLE => record.style,
        __process_WINDOWS_GWL_EXSTYLE => record.ex_style,
        __process_WINDOWS_GCLP_WNDPROC => record.wnd_proc,
        else => null,
    };
}

pub fn setWindowsWindowLong(self: *ElfState, handle: u64, index: i64, value: u64) ?u64 {
    const window_index = windowsWindowIndex(self, handle) orelse return null;
    const previous = windowsWindowLong(self, handle, index) orelse return null;
    switch (index) {
        __process_WINDOWS_GWLP_USERDATA => self.windows_windows[window_index].user_data = value,
        __process_WINDOWS_GWL_STYLE => self.windows_windows[window_index].style = @truncate(value),
        __process_WINDOWS_GWL_EXSTYLE => self.windows_windows[window_index].ex_style = @truncate(value),
        else => return null,
    }
    return previous;
}

pub fn destroyWindowsWindow(self: *ElfState, handle: u64) bool {
    const index = windowsWindowIndex(self, handle) orelse return false;
    self.windows_windows[index] = .{};
    if (self.windows_message_window_handle == handle) self.windows_message_window_handle = 0;
    return true;
}

pub fn invalidateWindowsWindow(self: *ElfState, handle: u64) bool {
    if (handle == 0) {
        var marked = false;
        for (&self.windows_windows) |*record| {
            if (!record.valid or record.message_only) continue;
            if (!record.update_region_pending) self.windows_paint_requests +|= 1;
            record.update_region_pending = true;
            marked = true;
        }
        if (marked) self.windows_message_event.notify();
        return marked;
    }
    const index = windowsWindowIndex(self, handle) orelse return false;
    if (self.windows_windows[index].message_only) return false;
    if (!self.windows_windows[index].update_region_pending) self.windows_paint_requests +|= 1;
    self.windows_windows[index].update_region_pending = true;
    self.windows_message_event.notify();
    return true;
}

pub fn validateWindowsWindow(self: *ElfState, handle: u64) bool {
    if (handle == 0) {
        var cleared = false;
        for (&self.windows_windows) |*record| {
            if (!record.valid) continue;
            if (record.update_region_pending) cleared = true;
            record.update_region_pending = false;
        }
        return cleared;
    }
    const index = windowsWindowIndex(self, handle) orelse return false;
    const cleared = self.windows_windows[index].update_region_pending;
    self.windows_windows[index].update_region_pending = false;
    return cleared;
}

pub fn windowsWindowHasPendingPaint(self: *const ElfState, handle: u64) bool {
    const index = windowsWindowIndex(self, handle) orelse return false;
    return self.windows_windows[index].update_region_pending;
}

pub fn windowsPendingPaintCount(self: *const ElfState) usize {
    var count: usize = 0;
    for (self.windows_windows) |record| {
        if (record.valid and record.update_region_pending) count += 1;
    }
    return count;
}

pub fn pendingWindowsPaintMessage(
    self: *ElfState,
    filter_hwnd: u64,
    minimum: u64,
    maximum: u64,
) ?__process_WindowsMessage {
    const minimum_message: u32 = @truncate(minimum);
    const maximum_message: u32 = @truncate(maximum);
    if (minimum_message > maximum_message and !(minimum_message == 0 and maximum_message == 0)) return null;
    for (self.windows_windows) |record| {
        if (!record.valid or !record.update_region_pending) continue;
        if (!windowBelongsToCaller(self, record)) continue;
        const message = __process_WindowsMessage{ .hwnd = record.handle, .message = __process_WINDOWS_WM_PAINT };
        if (!__process_windows_message_queue.Queue.matches(message, filter_hwnd, minimum_message, maximum_message)) continue;
        // A WM_PAINT that no WndProc can receive would spin the pump
        // forever without ever reaching the guest's painter.  Report the
        // window as having nothing to paint instead; the stall report
        // names the window if this is the reason no frame is produced.
        if (record.wnd_proc == 0) continue;
        self.windows_paint_deliveries +|= 1;
        return message;
    }
    return null;
}

pub fn enqueueWindowsMessage(self: *ElfState, message: __process_WindowsMessage) bool {
    var routed_message = message;
    routed_message.posted_by_thread_id = process_impl_lifecycle.currentWindowsThreadId(self);
    if (message.hwnd != 0) {
        if (windowsWindowIndex(self, message.hwnd)) |index| {
            routed_message.owner_thread_id = self.windows_windows[index].creator_thread_id;
        }
    }
    if (!self.windows_message_queue.post(routed_message)) return false;
    self.windows_message_event.notify();
    return true;
}

pub fn windowsMessageCount(self: *const ElfState) usize {
    return self.windows_message_queue.count();
}

pub fn windowsMessageDeliveryCount(self: *const ElfState) u64 {
    return self.windows_message_queue.snapshot().deliveries;
}

pub fn windowsMessagePostCount(self: *const ElfState) u64 {
    return self.windows_message_queue.snapshot().posts;
}

pub fn windowsMessageAffinitySkipCount(self: *const ElfState) u64 {
    return self.windows_message_queue.snapshot().affinity_skips;
}

pub fn postWindowsMessage(self: *ElfState, hwnd: u64, message: u32, wparam: u64, lparam: u64, caller_return_rip: u64) bool {
    const observed_step = process_impl_run_reporting.totalInterpretedSteps(self);
    if (hwnd == 0 or !isWindowsWindowHandle(self, hwnd)) {
        self.windows_message_queue.reject();
        self.windows_ui_pipeline.notePost(
            hwnd,
            message,
            wparam,
            lparam,
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            caller_return_rip,
            observed_step,
            false,
        );
        return false;
    }
    const accepted = enqueueWindowsMessage(self, .{ .hwnd = hwnd, .message = message, .wparam = wparam, .lparam = lparam });
    self.windows_ui_pipeline.notePost(
        hwnd,
        message,
        wparam,
        lparam,
        process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
        caller_return_rip,
        observed_step,
        accepted,
    );
    if (self.windows_ui_pipeline.isPendingFunctionMessage(hwnd, message)) {
        if (accepted) self.windows_ui_pipeline.notePendingPostTime(__process_monotonicNanoseconds());
        var caller: [__process_guest_symbol_text_bytes]u8 = undefined;
        logUiCall(self, self.windows_ui_pipeline.pending_function_posts +| self.windows_ui_pipeline.pending_function_post_drops, if (accepted) "posted" else "DROPPED (queue full)", "caller={s} queued_now={d}", .{
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, caller_return_rip, &caller),
            self.windows_message_queue.count(),
        });
    }
    return accepted;
}

pub fn logUiCall(self: *const ElfState, sequence: u64, leg: []const u8, comptime detail: []const u8, args: anytype) void {
    if (comptime @import("builtin").is_test) return;
    if (sequence > 32 and (sequence & (sequence - 1)) != 0) return;
    const slot = process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").*;
    const thread_label = if (slot) |index| process_impl_guest_diagnostics.guestThreadLabel(self, @intCast(@min(index + 1, 255))) else "owner (UI thread)";
    var text: [320]u8 = undefined;
    const formatted = __process_std.fmt.bufPrint(&text, detail, args) catch text[0..];
    __process_log.info("PE64 UI CALL: #{d} {s} thread=0x{x} thread_name='{s}' t_ms={d} {s}", .{
        sequence,
        leg,
        process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
        thread_label,
        process_impl_lifecycle.runElapsedMilliseconds(self),
        formatted,
    });
}

pub fn postWindowsQuit(self: *ElfState, exit_code: u64) void {
    self.windows_ui_quit_code = exit_code;
    self.windows_ui_quit_requested = true;
    _ = enqueueWindowsMessage(self, .{ .message = 0, .wparam = exit_code });
}

pub fn waitForWindowsMessage(self: *ElfState, filter_hwnd: u64, minimum: u64, maximum: u64) u64 {
    if (!self.parallel_guest_execution) return 0;
    // The lock can be let go for the wait only when every level this
    // thread holds merely dispatched into this call; a pinned level
    // belongs to a caller whose critical section must stay closed. On
    // 2026-09-26 this refused every call - the step's dispatch and the
    // runtime's entry wrapper made the depth two - so Xenia's UI thread
    // spun through GetMessage 129,533 times in two seconds, holding the
    // runtime mutex against the Emulator thread on every lap.
    const owner: *anyopaque = @ptrCast(self);
    if (__ProcessInternals._windows_runtime_locks().*.depth(owner) == 0 or __ProcessInternals._windows_runtime_locks().*.pinnedDepth(owner) != 0) {
        if (!windowsMessageDeliverable(self, filter_hwnd, minimum, maximum)) {
            self.windows_get_message_unreleasable +|= 1;
            if (self.windows_get_message_unreleasable_depth == 0) {
                self.windows_get_message_unreleasable_depth = __ProcessInternals._windows_runtime_locks().*.depth(owner);
                self.windows_get_message_unreleasable_pinned = __ProcessInternals._windows_runtime_locks().*.pinnedDepth(owner);
            }
        }
        return 0;
    }
    const started = __process_concurrency.monotonicNanoseconds();
    var blocked = false;
    while (!process_impl_lifecycle.isTerminated(self) and !windowsMessageDeliverable(self, filter_hwnd, minimum, maximum)) {
        const now = __process_concurrency.monotonicNanoseconds();
        blocked = true;
        const observed = self.windows_message_event.current();
        if (windowsMessageDeliverable(self, filter_hwnd, minimum, maximum)) break;
        self.windows_runtime_mutex.unlock();
        var notified = false;
        {
            var region = self.guest_execution_gate.enterSafeRegion();
            defer region.leave();
            notified = self.windows_message_event.waitChange(
                observed,
                __process_windows_message_wait.default.nextPollDeadline(now),
            );
        }
        {
            var region = self.guest_execution_gate.enterSafeRegion();
            self.windows_runtime_mutex.lock();
            region.leave();
        }
        switch (__process_windows_message_wait.default.classifyWake(notified)) {
            .guest_notification => self.windows_get_message_event_wakes +|= 1,
            .host_event_poll => self.windows_get_message_host_polls +|= 1,
        }
        __ProcessInternals._runtime_lock_released_ns().* +%= __process_concurrency.monotonicNanoseconds() -| now;
        if (process_impl_lifecycle.isTerminated(self)) break;
        _ = self.windows_graphics.pumpEvents();
        _ = process_impl_windows_sync.serviceWindowsGuestThreads(self, process_impl_windows_sync.windowsGuestWaitServiceSlice(self));
    }
    if (!blocked) return 0;
    const elapsed = __process_concurrency.monotonicNanoseconds() -| started;
    self.windows_get_message_blocks +|= 1;
    self.windows_get_message_block_ns +|= elapsed;
    return elapsed;
}

pub fn parkForGuestWait(self: *ElfState, deadline_ns: ?u64, mode: __state_GuestWaitPark) bool {
    if (!self.parallel_guest_execution) return false;
    const owner: *anyopaque = @ptrCast(self);
    if (__ProcessInternals._windows_runtime_locks().*.depth(owner) == 0 or __ProcessInternals._windows_runtime_locks().*.pinnedDepth(owner) != 0) {
        self.windows_guest_wait_park_refusals +|= 1;
        return false;
    }
    const started = __process_monotonicNanoseconds();
    const until = switch (mode) {
        .wake => if (deadline_ns) |deadline| @min(deadline, started +| __state_guest_wait_slice_ns) else started +| __state_guest_wait_slice_ns,
        .until_deadline => deadline_ns orelse started,
    };
    if (until <= started) return true;
    const observed = self.parallel_guest_wake_hub.epoch();
    self.windows_runtime_mutex.unlock();
    {
        var region = self.guest_execution_gate.enterSafeRegion();
        defer region.leave();
        switch (mode) {
            .wake => _ = self.parallel_guest_wake_hub.event.waitChange(observed, until),
            .until_deadline => {
                // Other threads' wakes are not this sleep's business.
                var epoch = observed;
                while (__process_monotonicNanoseconds() < until and !process_impl_lifecycle.isTerminated(self)) {
                    _ = self.parallel_guest_wake_hub.event.waitChange(epoch, until);
                    epoch = self.parallel_guest_wake_hub.epoch();
                }
            },
        }
    }
    {
        var region = self.guest_execution_gate.enterSafeRegion();
        self.windows_runtime_mutex.lock();
        region.leave();
    }
    const slept = __process_monotonicNanoseconds() -| started;
    __ProcessInternals._runtime_lock_released_ns().* +%= slept;
    self.windows_guest_wait_parks +|= 1;
    self.windows_guest_wait_park_ns +|= slept;
    return true;
}

pub fn sleepForGuestWait(self: *ElfState, milliseconds: u64) bool {
    const bounded: u64 = @min(milliseconds & 0xFFFF_FFFF, 60 * __process_std.time.ms_per_s);
    const deadline = __process_monotonicNanoseconds() +| bounded *| __process_std.time.ns_per_ms;
    // In slices: only the owner starts new guest threads and sweeps
    // expired waits, so a long owner Sleep must keep doing both.
    var slept = false;
    while (!process_impl_lifecycle.isTerminated(self)) {
        const now = __process_monotonicNanoseconds();
        if (now >= deadline) break;
        if (!parkForGuestWait(self, @min(deadline, now +| __state_guest_wait_slice_ns), .until_deadline)) break;
        slept = true;
        _ = process_impl_windows_sync.serviceWindowsGuestThreads(self, process_impl_windows_sync.windowsGuestWaitServiceSlice(self));
    }
    if (slept) self.windows_owner_sleeps +|= 1;
    return slept;
}

pub fn sleepUntilNextVblank(self: *ElfState) bool {
    if (!self.parallel_guest_execution) return false;
    const period: u64 = __process_std.time.ns_per_s / 60;
    const now = __process_monotonicNanoseconds();
    return parkForGuestWait(self, (now / period + 1) * period, .until_deadline);
}

pub fn ownerParallelWait(self: *ElfState, handles: []const u64, wait_all: bool, timeout: u64) ?__state_OwnerWaitOutcome {
    if (process_impl_lifecycle.guestContextField(self, "windows_active_guest_thread_slot").* != null) return null;
    const now = __process_monotonicNanoseconds();
    const key = ownerWaitKey(handles, wait_all, timeout, process_impl_lifecycle.guestContextField(self, "regs").*.rsp);
    if (self.owner_wait_key != key) {
        self.owner_wait_key = key;
        self.owner_wait_handle = if (handles.len != 0) handles[0] else 0;
        const milliseconds = timeout & 0xFFFF_FFFF;
        self.owner_wait_deadline_ns = if (milliseconds == 0xFFFF_FFFF) 0 else now +| milliseconds *| __process_std.time.ns_per_ms;
        self.owner_wait_started_ns = now;
        self.windows_owner_waits +|= 1;
    }
    const deadline = self.owner_wait_deadline_ns;
    if (ownerWaitSatisfied(self, handles, wait_all)) return finishOwnerWait(self, .signaled);
    if (deadline != 0 and now >= deadline) return finishOwnerWait(self, .timeout);
    // The scheduler's sweep: start new threads, expire due waits.
    _ = process_impl_windows_sync.serviceWindowsGuestThreads(self, process_impl_windows_sync.windowsGuestWaitServiceSlice(self));
    if (ownerWaitSatisfied(self, handles, wait_all)) return finishOwnerWait(self, .signaled);
    if (!parkForGuestWait(self, if (deadline != 0) deadline else null, .wake)) {
        self.owner_wait_key = 0;
        return null;
    }
    if (ownerWaitSatisfied(self, handles, wait_all)) return finishOwnerWait(self, .signaled);
    if (deadline != 0 and __process_monotonicNanoseconds() >= deadline) return finishOwnerWait(self, .timeout);
    self.windows_owner_wait_retries +|= 1;
    return .retry;
}

pub fn finishOwnerWait(self: *ElfState, outcome: __state_OwnerWaitOutcome) __state_OwnerWaitOutcome {
    const waited = __process_monotonicNanoseconds() -| self.owner_wait_started_ns;
    self.windows_owner_wait_ns +|= waited;
    self.windows_owner_wait_longest_ns = @max(self.windows_owner_wait_longest_ns, waited);
    self.owner_wait_key = 0;
    self.owner_wait_deadline_ns = 0;
    self.owner_wait_handle = 0;
    return outcome;
}

pub fn ownerWaitSatisfied(self: *ElfState, handles: []const u64, wait_all: bool) bool {
    var any_ready = false;
    for (handles) |handle| {
        const ready = process_impl_windows_sync.windowsWaitObjectReady(self, handle) orelse false;
        if (ready) {
            any_ready = true;
        } else if (wait_all) {
            return false;
        }
    }
    return any_ready;
}

pub fn ownerWaitKey(handles: []const u64, wait_all: bool, timeout: u64, frame: u64) u64 {
    var hasher = __process_std.hash.Wyhash.init(0x6f776e65725f7761);
    hasher.update(__process_std.mem.sliceAsBytes(handles));
    hasher.update(__process_std.mem.asBytes(&timeout));
    hasher.update(__process_std.mem.asBytes(&frame));
    const all: u8 = @intFromBool(wait_all);
    hasher.update(__process_std.mem.asBytes(&all));
    return hasher.final() | 1;
}

pub fn windowsMessageDeliverable(self: *ElfState, filter_hwnd: u64, minimum: u64, maximum: u64) bool {
    if (self.windows_ui_quit_requested) return true;
    // Only a paint the pump would deliver: one with no WndProc is never
    // generated, and counting it would turn the wait back into a spin.
    for (self.windows_windows) |record| {
        if (record.valid and record.update_region_pending and record.wnd_proc != 0 and windowBelongsToCaller(self, record)) return true;
    }
    return self.windows_message_queue.take(
        filter_hwnd,
        minimum,
        maximum,
        process_impl_lifecycle.currentWindowsThreadId(self),
        self.parallel_guest_execution,
        false,
    ) != null;
}

pub fn windowBelongsToCaller(self: *const ElfState, record: __process_WindowsWindow) bool {
    if (!self.parallel_guest_execution or record.creator_thread_id == 0) return true;
    return record.creator_thread_id == process_impl_lifecycle.currentWindowsThreadId(self);
}

pub fn dequeueWindowsMessage(self: *ElfState, filter_hwnd: u64, minimum: u64, maximum: u64, remove: bool) ?__process_WindowsMessage {
    const message = self.windows_message_queue.take(
        filter_hwnd,
        minimum,
        maximum,
        process_impl_lifecycle.currentWindowsThreadId(self),
        self.parallel_guest_execution,
        remove,
    ) orelse return null;
    if (!remove) return message;
    self.windows_ui_pipeline.noteDequeued(
        message.hwnd,
        message.message,
        message.wparam,
        message.lparam,
        process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
    );
    if (self.windows_ui_pipeline.isPendingFunctionMessage(message.hwnd, message.message)) {
        const queued = self.windows_ui_pipeline.notePendingDequeueTime(__process_monotonicNanoseconds());
        logUiCall(self, self.windows_ui_pipeline.pending_function_dequeues, "dequeued", "waited_in_queue_ms={?d} still_queued={d}", .{
            if (queued) |value| value / __process_std.time.ns_per_ms else null,
            self.windows_message_queue.count(),
        });
    }
    return message;
}

pub fn noteWindowsMessageDispatch(self: *ElfState, hwnd: u64, message: u32, wparam: u64, lparam: u64, wndproc: u64) bool {
    const pending = self.windows_ui_pipeline.noteDispatch(
        hwnd,
        message,
        wparam,
        lparam,
        process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
        wndproc,
    );
    if (pending and wndproc != 0) {
        self.windows_ui_pipeline.notePendingDispatchTime(__process_monotonicNanoseconds());
        var where: [__process_guest_symbol_text_bytes]u8 = undefined;
        logUiCall(self, self.windows_ui_pipeline.pending_function_dispatches, "dispatched", "wndproc=0x{x} ({s}) nesting={d}", .{
            wndproc,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, wndproc, &where),
            self.windows_ui_pipeline.dispatch_time_depth,
        });
    }
    return pending;
}

pub fn beginWindowsMessageDispatch(self: *ElfState, return_rip: u64, return_is_direct: bool) bool {
    return beginWindowsMessageDispatchWithKind(self, return_rip, return_is_direct, false);
}

pub fn beginWindowsMessageDispatchWithKind(self: *ElfState, return_rip: u64, return_is_direct: bool, pending_function: bool) bool {
    if (process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frame_count").* >= process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frames").*.len) {
        self.windows_ui_pipeline.noteCallbackFrameRefused(pending_function);
        return false;
    }
    const return_rsp = process_impl_lifecycle.guestContextField(self, "regs").*.rsp;
    if (return_rsp < 40) {
        self.windows_ui_pipeline.noteCallbackFrameRefused(pending_function);
        return false;
    }
    const callback_rsp = return_rsp - 40;
    if (process_impl_execution.guestMemoryConst(self, callback_rsp, 40) == null) {
        self.windows_ui_pipeline.noteCallbackFrameRefused(pending_function);
        return false;
    }

    // DispatchMessageW returns through the WndProc before its import
    // boundary completes. Keep the caller's Windows x64 nonvolatile
    // state across that nested guest execution just as the ordinary
    // import-return path does; the callback may change volatile state,
    // including RAX, which is the WndProc result.
    const message_address = process_impl_lifecycle.guestContextField(self, "regs").*.rcx;
    const message_readable = process_impl_execution.guestMemoryConst(self, message_address, 48) != null;
    const hwnd = if (message_readable) process_impl_guest_memory.read64(self, message_address) else 0;
    const message = if (message_readable) process_impl_guest_memory.read32(self, message_address + 8) else 0;
    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frame_count").*;
    process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frames").*[frame_index] = .{
        .return_rip = return_rip,
        .return_rsp = return_rsp,
        .return_is_direct = return_is_direct,
        .pending_function = pending_function,
        .saved_abi = __process_windows_guest_abi.Snapshot.capture(
            process_impl_lifecycle.guestContextField(self, "regs"),
            process_impl_lifecycle.guestContextField(self, "xmm"),
        ),
        .hwnd = hwnd,
        .message = message,
        .wndproc = windowsWindowProc(self, hwnd) orelse 0,
    };
    process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frame_count").* += 1;
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = callback_rsp;
    process_impl_guest_memory.write64(self, callback_rsp, __process_SYNTHETIC_WINDOWS_MESSAGE_RETURN);
    _ = process_impl_execution.fillGuestMemory(self, callback_rsp + 8, 32, 0);
    return true;
}

pub fn finishWindowsMessageDispatch(self: *ElfState) bool {
    if (process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frame_count").* == 0) {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        __process_log.err("Windows message callback returned without a dispatch frame rip=0x{x}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rip});
        return false;
    }
    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frame_count").* - 1;
    const frame = process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frames").*[frame_index];
    self.windows_ui_pipeline.noteCallbackReturned(frame.pending_function);
    if (frame.pending_function) {
        const ran = self.windows_ui_pipeline.notePendingReturnTime(__process_monotonicNanoseconds());
        logUiCall(self, self.windows_ui_pipeline.pending_function_returns, "returned", "ran_ms={?d} result=0x{x}", .{
            if (ran) |value| value / __process_std.time.ns_per_ms else null,
            process_impl_lifecycle.guestContextField(self, "regs").*.rax,
        });
    }
    process_impl_lifecycle.guestContextField(self, "windows_message_dispatch_frame_count").* = frame_index;

    self.windows_callback_abi_calls +|= 1;
    if (frame.saved_abi) |saved| {
        const regs = process_impl_lifecycle.guestContextField(self, "regs");
        const xmm = process_impl_lifecycle.guestContextField(self, "xmm");
        const difference = saved.difference(regs, xmm);
        if (difference.any()) {
            self.windows_callback_abi_clobber_calls +|= 1;
            if (difference.gpr_mask != 0) self.windows_callback_abi_gpr_clobbers +|= 1;
            if (difference.xmm_mask != 0) self.windows_callback_abi_xmm_clobbers +|= 1;
            self.windows_callback_abi_repairs +|= 1;
            const occurrences = self.windows_callback_abi_clobber_calls;
            if (comptime !@import("builtin").is_test) {
                if (process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrences)) {
                    __process_log.err("PE64 WINDOWS CALLBACK ABI VIOLATION: api=DispatchMessageW hwnd=0x{x} message=0x{x} wndproc=0x{x} continuation=0x{x} gpr_mask=0x{x} xmm6_15_mask=0x{x} saved=[rbx=0x{x},rbp=0x{x},rsi=0x{x},rdi=0x{x},r12=0x{x},r13=0x{x},r14=0x{x},r15=0x{x}] returned=[rbx=0x{x},rbp=0x{x},rsi=0x{x},rdi=0x{x},r12=0x{x},r13=0x{x},r14=0x{x},r15=0x{x}] step={d} action=restored Windows x64 nonvolatile GPRs and XMM6-XMM15 while preserving volatile callback result", .{
                        frame.hwnd,
                        frame.message,
                        frame.wndproc,
                        frame.return_rip,
                        difference.gpr_mask,
                        difference.xmm_mask,
                        saved.rbx,
                        saved.rbp,
                        saved.rsi,
                        saved.rdi,
                        saved.r12,
                        saved.r13,
                        saved.r14,
                        saved.r15,
                        regs.rbx,
                        regs.rbp,
                        regs.rsi,
                        regs.rdi,
                        regs.r12,
                        regs.r13,
                        regs.r14,
                        regs.r15,
                        process_impl_lifecycle.observedExecutionSteps(self),
                    });
                }
            }
            saved.restore(regs, xmm);
        }
    }
    const expected_callback_rsp = (frame.return_rsp -| 40) + 8;
    if ((self.trace_windows_messages or self.diagnose_abi) and !frame.return_is_direct and process_impl_lifecycle.guestContextField(self, "regs").*.rsp != expected_callback_rsp) {
        __process_log.warn("Windows message callback changed stack unexpectedly callback_rsp=0x{x} expected_after_ret=0x{x} return_rsp=0x{x}", .{
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            expected_callback_rsp,
            frame.return_rsp,
        });
    }
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = if (frame.return_is_direct) frame.return_rsp else frame.return_rsp +| 8;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = frame.return_rip;
    return true;
}

pub fn beginWindowsAudioCallback(self: *ElfState, return_rip: u64, return_is_direct: bool) bool {
    if (process_impl_lifecycle.guestContextField(self, "windows_audio_callback_frame_count").* >= process_impl_lifecycle.guestContextField(self, "windows_audio_callback_frames").*.len) return false;
    const return_rsp = process_impl_lifecycle.guestContextField(self, "regs").*.rsp;
    if (return_rsp < 48) return false;
    const callback_rsp = return_rsp - 48;
    if (process_impl_execution.guestMemoryConst(self, callback_rsp, 48) == null) return false;

    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_audio_callback_frame_count").*;
    process_impl_lifecycle.guestContextField(self, "windows_audio_callback_frames").*[frame_index] = .{
        .return_rip = return_rip,
        .return_rsp = return_rsp,
        .return_is_direct = return_is_direct,
    };
    process_impl_lifecycle.guestContextField(self, "windows_audio_callback_frame_count").* += 1;
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = callback_rsp;
    process_impl_guest_memory.write64(self, callback_rsp, __process_SYNTHETIC_WINDOWS_AUDIO_RETURN);
    _ = process_impl_execution.fillGuestMemory(self, callback_rsp + 8, 32, 0);
    process_impl_guest_memory.write64(self, callback_rsp + 40, 0);
    return true;
}

pub fn finishWindowsAudioCallback(self: *ElfState) bool {
    if (process_impl_lifecycle.guestContextField(self, "windows_audio_callback_frame_count").* == 0) {
        process_impl_lifecycle.markFaulted(self);
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        process_impl_lifecycle.markTerminated(self);
        __process_log.err("Windows audio callback returned without a callback frame rip=0x{x}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rip});
        return false;
    }
    const frame_index = process_impl_lifecycle.guestContextField(self, "windows_audio_callback_frame_count").* - 1;
    const frame = process_impl_lifecycle.guestContextField(self, "windows_audio_callback_frames").*[frame_index];
    process_impl_lifecycle.guestContextField(self, "windows_audio_callback_frame_count").* = frame_index;
    const expected_callback_rsp = (frame.return_rsp -| 48) + 8;
    if ((self.trace_windows_audio or self.diagnose_abi) and !frame.return_is_direct and process_impl_lifecycle.guestContextField(self, "regs").*.rsp != expected_callback_rsp) {
        __process_log.warn("Windows audio callback changed stack unexpectedly callback_rsp=0x{x} expected_after_ret=0x{x} return_rsp=0x{x}", .{
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            expected_callback_rsp,
            frame.return_rsp,
        });
    }
    process_impl_lifecycle.guestContextField(self, "regs").*.rsp = if (frame.return_is_direct) frame.return_rsp else frame.return_rsp +| 8;
    process_impl_lifecycle.guestContextField(self, "regs").*.rip = frame.return_rip;
    // waveOutWrite's return value is independent of the callback's
    // internal semaphore operation.
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
    return true;
}
