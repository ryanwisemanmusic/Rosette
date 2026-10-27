const std = @import("std");
const testing = std.testing;
const Executor = @import("../instruction_operations.zig").Executor;
const abi = @import("../abi_handshake.zig");
const heap_trace = @import("../heap/runtime.zig");
const raw_execution = @import("../execution_engine.zig");
const text_thunks = @import("text_thunks.zig");
const gdi_thunks = @import("gdi_thunks.zig");
const resource_thunks = @import("resource_thunks.zig");
const window_thunks = @import("window_thunks.zig");
const opengl_thunks = @import("opengl_thunks.zig");
const process_priority_thunks = @import("process_priority_thunks.zig");
const local_memory_thunks = @import("local_memory_thunks.zig");

fn finishSuccess(frame: abi.CallFrame) void {
    frame.finish(1);
}

fn consoleFdForHandle(handle: u32) c_int {
    return switch (handle) {
        0xB003 => 2,
        else => 1,
    };
}

fn monotonicNanoseconds() ?u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &ts) != 0) return null;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

fn heapFreeThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 3);
    const heap = frame.arg(0);
    const flags = frame.arg(1);
    const mem_ptr = frame.arg(2);
    if (heap_trace.free("HeapFree", heap, flags, mem_ptr)) {
        finishSuccess(frame);
    } else {
        frame.finish(0);
    }
}

fn heapAllocThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 3);
    const heap = frame.arg(0);
    const flags = frame.arg(1);
    const size = frame.arg(2);
    frame.finish(heap_trace.alloc("HeapAlloc", heap, flags, size));
}

fn heapSizeThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 3);
    frame.finish(heap_trace.querySize("HeapSize", frame.arg(0), frame.arg(1), frame.arg(2)));
}

fn getProcessHeapThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(heap_trace.getProcessHeap("GetProcessHeap"));
}

fn setUnhandledExceptionFilterThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const previous = ctx.win32_unhandled_exception_filter;
    ctx.win32_unhandled_exception_filter = frame.arg(0);
    frame.finish(previous);
}

fn unhandledExceptionFilterThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    _ = frame.arg(0); // EXCEPTION_POINTERS; exception delivery is not modeled here.
    frame.finish(0); // EXCEPTION_CONTINUE_SEARCH.
}

fn getCurrentProcessThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(std.math.maxInt(u32)); // Win32 pseudo-handle for the current process.
}

fn isDebuggerPresentThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(0);
}

fn heapCreateThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 3);
    // The PE32 runner has one bounded synthetic guest heap. Separate Win32
    // heap handles share that arena until per-heap allocation ownership exists.
    _ = frame.arg(0); // options
    _ = frame.arg(1); // initial size
    _ = frame.arg(2); // maximum size
    frame.finish(heap_trace.process_heap_handle);
}

fn heapDestroyThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    frame.finish(@intFromBool(frame.arg(0) == heap_trace.process_heap_handle));
}

fn getVersionExAThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const version_info = frame.arg(0);
    if (version_info == 0 or ctx.mem.read32(version_info) < 20) {
        frame.finish(0);
        return;
    }

    ctx.mem.write32(version_info + 4, 10);
    ctx.mem.write32(version_info + 8, 0);
    ctx.mem.write32(version_info + 12, 19045);
    ctx.mem.write32(version_info + 16, 2); // VER_PLATFORM_WIN32_NT
    if (ctx.mem.read32(version_info) > 20) ctx.mem.write8(version_info + 20, 0);
    frame.finish(1);
}

fn getVersionExWThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const version_info = frame.arg(0);
    const size: usize = 276; // sizeof(OSVERSIONINFOW)
    if (version_info < ctx.mem.base) {
        frame.finish(0);
        return;
    }
    const offset: usize = @intCast(version_info - ctx.mem.base);
    if (offset > ctx.mem.data.len or size > ctx.mem.data.len - offset or ctx.mem.read32(version_info) < @as(u32, @intCast(size))) {
        frame.finish(0);
        return;
    }

    ctx.mem.write32(version_info + 4, 10);
    ctx.mem.write32(version_info + 8, 0);
    ctx.mem.write32(version_info + 12, 19045);
    ctx.mem.write32(version_info + 16, 2); // VER_PLATFORM_WIN32_NT
    @memset(ctx.mem.data[offset + 20 .. offset + size], 0); // szCSDVersion[128]
    frame.finish(1);
}

fn getVersionThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    // Match the Windows 10 compatibility version exposed by GetVersionExA:
    // major/minor occupy the low two bytes and the build number the high word.
    frame.finish((@as(u32, 19045) << 16) | 10);
}

fn getTimeZoneInformationThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const address = frame.arg(0);
    const size: usize = 172; // sizeof(TIME_ZONE_INFORMATION) for PE32
    if (address < ctx.mem.base) {
        frame.finish(std.math.maxInt(u32));
        return;
    }
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset > ctx.mem.data.len or size > ctx.mem.data.len - offset) {
        frame.finish(std.math.maxInt(u32));
        return;
    }

    // Report a fixed UTC zone: zero bias, no transition dates or names.
    @memset(ctx.mem.data[offset .. offset + size], 0);
    frame.finish(0); // TIME_ZONE_ID_UNKNOWN (no daylight-saving transition)
}

fn getSystemTimeThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const st_ptr = frame.arg(0);
    if (st_ptr != 0 and st_ptr >= ctx.mem.base) {
        const offset: usize = @intCast(st_ptr - ctx.mem.base);
        if (offset <= ctx.mem.data.len and 16 <= ctx.mem.data.len - offset) {
            var ts: std.c.timespec = undefined;
            if (std.c.clock_gettime(@as(std.c.clockid_t, .REALTIME), &ts) == 0) {
                const epoch_seconds = std.time.epoch.EpochSeconds{
                    .secs = @intCast(ts.sec),
                };
                const epoch_day = epoch_seconds.getEpochDay();
                const year_day = epoch_day.calculateYearDay();
                const month_day = year_day.calculateMonthDay();
                const day_seconds = epoch_seconds.getDaySeconds();

                ctx.mem.write16(st_ptr, year_day.year);
                ctx.mem.write16(st_ptr + 2, month_day.month.numeric());
                ctx.mem.write16(st_ptr + 4, @intCast((epoch_day.day + 4) % 7));
                ctx.mem.write16(st_ptr + 6, @intCast(month_day.day_index + 1));
                ctx.mem.write16(st_ptr + 8, day_seconds.getHoursIntoDay());
                ctx.mem.write16(st_ptr + 10, day_seconds.getMinutesIntoHour());
                ctx.mem.write16(st_ptr + 12, day_seconds.getSecondsIntoMinute());
                ctx.mem.write16(st_ptr + 14, @intCast(@divTrunc(ts.nsec, std.time.ns_per_ms)));
            }
        }
    }
    // GetSystemTime/GetLocalTime return void; the emulator's timezone thunk
    // reports UTC, so both APIs use the same clock representation.
    frame.finish(0);
}

fn getModuleFileNameAThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 3);
    const module = frame.arg(0);
    const output = frame.arg(1);
    const capacity = frame.arg(2);
    const path = ctx.pe32_image_path;
    if (module != 0 or output == 0 or capacity == 0 or path.len == 0) {
        frame.finish(0);
        return;
    }

    const copied: usize = @min(path.len, @as(usize, @intCast(capacity - 1)));
    if (output < ctx.mem.base) {
        frame.finish(0);
        return;
    }
    const offset: usize = @intCast(output - ctx.mem.base);
    const needed = copied + 1;
    if (offset > ctx.mem.data.len or needed > ctx.mem.data.len - offset) {
        frame.finish(0);
        return;
    }

    for (path[0..copied], 0..) |byte, i| {
        ctx.mem.data[offset + i] = if (byte == '/') '\\' else byte;
    }
    ctx.mem.data[offset + copied] = 0;
    frame.finish(if (copied < path.len) capacity else @intCast(copied));
}

fn readGuestCString(ctx: *const Executor, address: u32, buffer: []u8) ?[]const u8 {
    if (address < ctx.mem.base) return null;
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset >= ctx.mem.data.len) return null;
    var length: usize = 0;
    while (length < buffer.len and offset + length < ctx.mem.data.len) : (length += 1) {
        const byte = ctx.mem.data[offset + length];
        if (byte == 0) return buffer[0..length];
        buffer[length] = byte;
    }
    return null;
}

fn outputDebugStringAThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const address = frame.arg(0);
    if (std.c.getenv("ROSETTE_PE32_DEBUGSTRINGS")) |enabled| {
        if (enabled[0] != 0 and enabled[0] != '0') {
            var buffer: [512]u8 = undefined;
            if (readGuestCString(ctx, address, &buffer)) |message| {
                std.debug.print("PE32_DEBUG: {s}\n", .{message});
            }
        }
    }
    frame.finish(0);
}

fn outputDebugStringWThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const address = frame.arg(0);
    if (std.c.getenv("ROSETTE_PE32_DEBUGSTRINGS")) |enabled| {
        if (enabled[0] != 0 and enabled[0] != '0') {
            var buffer: [512]u8 = undefined;
            if (readGuestWideAsciiString(ctx, address, &buffer)) |message| {
                std.debug.print("PE32_DEBUG: {s}\n", .{message});
            }
        }
    }
    frame.finish(0);
}

fn getModuleHandleAThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const name_address = frame.arg(0);
    if (name_address == 0) {
        frame.finish(if (ctx.pe32_main_module_base != 0) ctx.pe32_main_module_base else ctx.mem.base);
        return;
    }
    var name_buffer: [128]u8 = undefined;
    const name = readGuestCString(ctx, name_address, &name_buffer) orelse {
        frame.finish(0);
        return;
    };
    if (std.ascii.eqlIgnoreCase(name, "kernel32.dll")) {
        frame.finish(0x77000000); // Synthetic handle used only for GetProcAddress.
    } else {
        frame.finish(0);
    }
}

fn readGuestWideAsciiString(ctx: *const Executor, address: u32, buffer: []u8) ?[]const u8 {
    if (address < ctx.mem.base) return null;
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset >= ctx.mem.data.len) return null;
    var length: usize = 0;
    while (length < buffer.len) : (length += 1) {
        const byte_offset = offset + length * 2;
        if (byte_offset > ctx.mem.data.len or 2 > ctx.mem.data.len - byte_offset) return null;
        const unit = std.mem.readInt(u16, ctx.mem.data[byte_offset..][0..2], .little);
        if (unit == 0) return buffer[0..length];
        if (unit > 0x7F) return null;
        buffer[length] = @intCast(unit);
    }
    return null;
}

fn moduleHandleForName(ctx: *const Executor, name: []const u8) u32 {
    if (std.ascii.eqlIgnoreCase(name, "kernel32.dll")) return 0x77000000;
    const main_base = if (ctx.pe32_main_module_base != 0) ctx.pe32_main_module_base else ctx.mem.base;
    const image_name = std.fs.path.basename(ctx.pe32_image_path);
    if (image_name.len != 0 and std.ascii.eqlIgnoreCase(name, image_name)) return main_base;
    return 0;
}

fn getModuleHandleWThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const name_address = frame.arg(0);
    if (name_address == 0) {
        frame.finish(if (ctx.pe32_main_module_base != 0) ctx.pe32_main_module_base else ctx.mem.base);
        return;
    }
    var name_buffer: [128]u8 = undefined;
    const name = readGuestWideAsciiString(ctx, name_address, &name_buffer) orelse {
        frame.finish(0);
        return;
    };
    frame.finish(moduleHandleForName(ctx, name));
}

fn getProcAddressThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 2);
    const module = frame.arg(0);
    const name_address = frame.arg(1);
    if (module == 0 or name_address <= 0xFFFF) {
        frame.finish(0);
        return;
    }
    var name_buffer: [256]u8 = undefined;
    const name = readGuestCString(ctx, name_address, &name_buffer) orelse {
        frame.finish(0);
        return;
    };
    // An unresolved symbol remains null, matching the Win32 GetProcAddress
    // contract. Imported functions use the runner's synthetic IAT call target.
    frame.finish(raw_execution.lookupIatFunctionPointer(ctx, name) orelse 0);
}

fn tlsAllocThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(ctx.tlsAlloc());
}

fn tlsFreeThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    frame.finish(@intFromBool(ctx.tlsFree(frame.arg(0))));
}

fn tlsGetValueThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    frame.finish(ctx.tlsGetValue(frame.arg(0)) orelse 0);
}

fn tlsSetValueThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 2);
    frame.finish(@intFromBool(ctx.tlsSetValue(frame.arg(0), frame.arg(1))));
}

/// Bounds-check a PE32 CRITICAL_SECTION before touching its six DWORD fields.
/// The current raw PE runner models one guest thread, so the lock implementation
/// below covers acquisition and recursion by that thread without host waits.
fn criticalSectionAddress(ctx: *const Executor, address: u32) ?u32 {
    if (address < ctx.mem.base or address > std.math.maxInt(u32) - 24) return null;
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset > ctx.mem.data.len or 24 > ctx.mem.data.len - offset) return null;
    return address;
}

fn initializeCriticalSection(ctx: *Executor, address: u32) bool {
    const base = criticalSectionAddress(ctx, address) orelse return false;
    ctx.mem.write32(base, 0); // DebugInfo
    ctx.mem.write32(base + 4, std.math.maxInt(u32)); // LockCount: unlocked
    ctx.mem.write32(base + 8, 0); // RecursionCount
    ctx.mem.write32(base + 12, 0); // OwningThread
    ctx.mem.write32(base + 16, 0); // LockSemaphore
    ctx.mem.write32(base + 20, 0); // SpinCount
    return true;
}

fn initializeCriticalSectionThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    frame.finish(@intFromBool(initializeCriticalSection(ctx, frame.arg(0))));
}

fn deleteCriticalSectionThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const base = criticalSectionAddress(ctx, frame.arg(0)) orelse {
        frame.finish(0);
        return;
    };
    ctx.mem.write32(base, 0);
    ctx.mem.write32(base + 4, std.math.maxInt(u32));
    ctx.mem.write32(base + 8, 0);
    ctx.mem.write32(base + 12, 0);
    ctx.mem.write32(base + 16, 0);
    ctx.mem.write32(base + 20, 0);
    frame.finish(0);
}

fn enterCriticalSectionThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const base = criticalSectionAddress(ctx, frame.arg(0)) orelse {
        frame.finish(0);
        return;
    };
    const lock_count = ctx.mem.read32(base + 4);
    const recursion = ctx.mem.read32(base + 8);
    const owner = ctx.mem.read32(base + 12);
    const guest_thread_id: u32 = 1;

    // This runner currently executes a single guest thread. Preserve Windows'
    // recursive counter layout for that thread; true contended waits require a
    // multi-thread guest scheduler and are intentionally not fabricated here.
    if (owner == 0 or owner == guest_thread_id) {
        ctx.mem.write32(base + 4, lock_count +% 1);
        ctx.mem.write32(base + 8, recursion +% 1);
        ctx.mem.write32(base + 12, guest_thread_id);
    }
    frame.finish(0);
}

fn leaveCriticalSectionThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const base = criticalSectionAddress(ctx, frame.arg(0)) orelse {
        frame.finish(0);
        return;
    };
    const recursion = ctx.mem.read32(base + 8);
    if (recursion != 0 and ctx.mem.read32(base + 12) == 1) {
        ctx.mem.write32(base + 4, ctx.mem.read32(base + 4) -% 1);
        if (recursion == 1) {
            ctx.mem.write32(base + 8, 0);
            ctx.mem.write32(base + 12, 0);
        } else {
            ctx.mem.write32(base + 8, recursion - 1);
        }
    }
    frame.finish(0);
}

fn interlockedIncrementThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const address = frame.arg(0);
    if (address < ctx.mem.base or address > std.math.maxInt(u32) - 4) {
        frame.finish(0);
        return;
    }
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset > ctx.mem.data.len or 4 > ctx.mem.data.len - offset) {
        frame.finish(0);
        return;
    }
    const value = ctx.mem.read32(address) +% 1;
    ctx.mem.write32(address, value);
    frame.finish(value);
}

fn interlockedDecrementThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const address = frame.arg(0);
    if (address < ctx.mem.base or address > std.math.maxInt(u32) - 4) {
        frame.finish(0);
        return;
    }
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset > ctx.mem.data.len or 4 > ctx.mem.data.len - offset) {
        frame.finish(0);
        return;
    }
    const value = ctx.mem.read32(address) -% 1;
    ctx.mem.write32(address, value);
    frame.finish(value);
}

fn getStartupInfoAThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const address = frame.arg(0);
    const size: usize = 68; // sizeof(STARTUPINFOA) for PE32
    if (address < ctx.mem.base or address > std.math.maxInt(u32) - size) {
        frame.finish(0);
        return;
    }
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset > ctx.mem.data.len or size > ctx.mem.data.len - offset) {
        frame.finish(0);
        return;
    }
    @memset(ctx.mem.data[offset .. offset + size], 0);
    ctx.mem.write32(address, @intCast(size));
    ctx.mem.write32(address + 56, 0xB001); // hStdInput
    ctx.mem.write32(address + 60, 0xB002); // hStdOutput
    ctx.mem.write32(address + 64, 0xB003); // hStdError
    frame.finish(0);
}

fn getStartupInfoWThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const address = frame.arg(0);
    const size: usize = 68; // sizeof(STARTUPINFOW) for PE32
    if (address < ctx.mem.base or address > std.math.maxInt(u32) - size) {
        frame.finish(0);
        return;
    }
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset > ctx.mem.data.len or size > ctx.mem.data.len - offset) {
        frame.finish(0);
        return;
    }
    @memset(ctx.mem.data[offset .. offset + size], 0);
    ctx.mem.write32(address, @intCast(size));
    ctx.mem.write32(address + 56, 0xB001); // hStdInput
    ctx.mem.write32(address + 60, 0xB002); // hStdOutput
    ctx.mem.write32(address + 64, 0xB003); // hStdError
    frame.finish(0);
}

fn getFileTypeThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const handle = frame.arg(0);
    // The runner's synthetic standard handles are terminal character devices.
    // Win32 FILE_TYPE_CHAR is 0x0002; arbitrary handles remain invalid.
    const file_type: u32 = switch (handle) {
        0xB001, 0xB002, 0xB003 => 2,
        else => 0,
    };
    frame.finish(file_type);
}

fn setHandleCountThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    // SetHandleCount is a legacy compatibility API and has no effect on
    // modern Win32. The documented return value is the requested handle
    // count, so preserve that behavior without imposing a fake process limit.
    frame.finish(frame.arg(0));
}

fn getLastErrorThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(ctx.win32_last_error);
}

fn setLastErrorThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    ctx.win32_last_error = frame.arg(0);
    frame.finish(0);
}

fn getCommandLineAThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    if (ctx.pe32_command_line_address == 0 and ctx.pe32_command_line.len != 0) {
        const size = std.math.cast(u32, ctx.pe32_command_line.len + 1) orelse {
            frame.finish(0);
            return;
        };
        const address = heap_trace.alloc("GetCommandLineA", heap_trace.process_heap_handle, 0, size);
        if (address < ctx.mem.base) {
            frame.finish(0);
            return;
        }
        const offset: usize = @intCast(address - ctx.mem.base);
        if (offset > ctx.mem.data.len or size > ctx.mem.data.len - offset) {
            frame.finish(0);
            return;
        }
        @memcpy(ctx.mem.data[offset .. offset + ctx.pe32_command_line.len], ctx.pe32_command_line);
        ctx.mem.data[offset + ctx.pe32_command_line.len] = 0;
        ctx.pe32_command_line_address = address;
    }
    frame.finish(ctx.pe32_command_line_address);
}

fn getCommandLineWThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    if (ctx.pe32_command_line_w_address == 0 and ctx.pe32_command_line.len != 0) {
        const wide = std.unicode.utf8ToUtf16LeAllocZ(ctx.mem.allocator, ctx.pe32_command_line) catch {
            frame.finish(0);
            return;
        };
        defer ctx.mem.allocator.free(wide);

        const byte_length = std.math.mul(usize, wide.len + 1, @sizeOf(u16)) catch {
            frame.finish(0);
            return;
        };
        const size = std.math.cast(u32, byte_length) orelse {
            frame.finish(0);
            return;
        };
        const address = heap_trace.alloc("GetCommandLineW", heap_trace.process_heap_handle, 0, size);
        if (address < ctx.mem.base) {
            frame.finish(0);
            return;
        }
        const offset: usize = @intCast(address - ctx.mem.base);
        if (offset > ctx.mem.data.len or byte_length > ctx.mem.data.len - offset) {
            frame.finish(0);
            return;
        }

        const wide_bytes = std.mem.sliceAsBytes(wide);
        @memcpy(ctx.mem.data[offset .. offset + wide_bytes.len], wide_bytes);
        @memset(ctx.mem.data[offset + wide_bytes.len .. offset + byte_length], 0);
        ctx.pe32_command_line_w_address = address;
    }
    frame.finish(ctx.pe32_command_line_w_address);
}

fn charNextWThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const string_address = frame.arg(0);
    if (string_address == 0 or ctx.mem.read16(string_address) == 0) {
        frame.finish(string_address);
        return;
    }
    frame.finish(string_address +% 2);
}

fn processApiThunk(ctx: *Executor, api: Executor.ProcessApi, argument_count: u32) void {
    const frame = abi.CallFrame.raw(ctx, argument_count);
    const result = if (ctx.process_api_handler) |handler| blk: {
        const context = ctx.process_api_context orelse {
            ctx.win32_last_error = 50; // ERROR_NOT_SUPPORTED
            break :blk 0;
        };
        break :blk handler(context, ctx, api);
    } else blk: {
        ctx.win32_last_error = 50; // ERROR_NOT_SUPPORTED
        break :blk 0;
    };
    frame.finish(result);
}

fn createProcessAThunk(ctx: *Executor) void {
    processApiThunk(ctx, .create_process_a, 10);
}

fn virtualAllocExThunk(ctx: *Executor) void {
    processApiThunk(ctx, .virtual_alloc_ex, 5);
}

fn virtualAllocThunk(ctx: *Executor) void {
    processApiThunk(ctx, .virtual_alloc, 4);
}

fn virtualFreeThunk(ctx: *Executor) void {
    processApiThunk(ctx, .virtual_free, 3);
}

fn writeProcessMemoryThunk(ctx: *Executor) void {
    processApiThunk(ctx, .write_process_memory, 5);
}

fn createRemoteThreadThunk(ctx: *Executor) void {
    processApiThunk(ctx, .create_remote_thread, 7);
}

fn waitForSingleObjectThunk(ctx: *Executor) void {
    processApiThunk(ctx, .wait_for_single_object, 2);
}

fn getExitCodeThreadThunk(ctx: *Executor) void {
    processApiThunk(ctx, .get_exit_code_thread, 2);
}

fn resumeThreadThunk(ctx: *Executor) void {
    processApiThunk(ctx, .resume_thread, 1);
}

fn closeHandleThunk(ctx: *Executor) void {
    processApiThunk(ctx, .close_handle, 1);
}

fn virtualProtectThunk(ctx: *Executor) void {
    processApiThunk(ctx, .virtual_protect, 4);
}

fn loadLibraryAThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    _ = frame.arg(0);
    // Dynamic system-library loading is not modeled by the raw PE runner.
    // Keep the import discoverable for remote-thread bootstrap, but report a
    // real failure if guest code tries to call it in this process.
    ctx.win32_last_error = 50; // ERROR_NOT_SUPPORTED
    frame.finish(0);
}

fn getEnvironmentStrings(ctx: *Executor, wide: bool) u32 {
    const storage = if (wide) &ctx.pe32_environment_w_address else &ctx.pe32_environment_a_address;
    if (storage.* != 0) return storage.*;

    // An empty Windows environment is represented by two consecutive NUL
    // characters (two bytes for ANSI, two UTF-16 code units for wide).
    const size: u32 = if (wide) 4 else 2;
    const address = heap_trace.alloc(if (wide) "GetEnvironmentStringsW" else "GetEnvironmentStringsA", heap_trace.process_heap_handle, 0, size);
    if (address < ctx.mem.base) return 0;
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset > ctx.mem.data.len or size > ctx.mem.data.len - offset) return 0;
    @memset(ctx.mem.data[offset .. offset + size], 0);
    storage.* = address;
    return address;
}

fn getEnvironmentStringsAThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(getEnvironmentStrings(ctx, false));
}

fn getEnvironmentStringsWThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(getEnvironmentStrings(ctx, true));
}

fn freeEnvironmentStrings(ctx: *Executor, wide: bool, address: u32) bool {
    const storage = if (wide) &ctx.pe32_environment_w_address else &ctx.pe32_environment_a_address;
    if (address == 0 or address != storage.*) return false;
    storage.* = 0;
    return heap_trace.free(if (wide) "FreeEnvironmentStringsW" else "FreeEnvironmentStringsA", heap_trace.process_heap_handle, 0, address);
}

fn freeEnvironmentStringsAThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    frame.finish(@intFromBool(freeEnvironmentStrings(ctx, false, frame.arg(0))));
}

fn freeEnvironmentStringsWThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    frame.finish(@intFromBool(freeEnvironmentStrings(ctx, true, frame.arg(0))));
}

/// Register Win32 console API thunks needed by console-mode x86 programs.
/// Each thunk pops its arguments from the x86 stack, calls the native
/// function (via the Rosette shim layer), and stores the return value in EAX.
pub fn register_win32_console_thunks(ex: *Executor) void {
    const map = &ex.import_table;
    gdi_thunks.register(ex);
    resource_thunks.register(ex);
    window_thunks.register(ex);
    opengl_thunks.register(ex);
    process_priority_thunks.register(ex);
    local_memory_thunks.register(ex);

    // Nested PE32 launches are supplied by an explicit process manager. When
    // the runner has not installed one, these calls fail as unsupported Win32
    // operations instead of fabricating process/thread handles.
    map.put("CreateProcessA", createProcessAThunk) catch {};
    map.put("VirtualAlloc", virtualAllocThunk) catch {};
    map.put("VirtualFree", virtualFreeThunk) catch {};
    map.put("VirtualAllocEx", virtualAllocExThunk) catch {};
    map.put("WriteProcessMemory", writeProcessMemoryThunk) catch {};
    map.put("CreateRemoteThread", createRemoteThreadThunk) catch {};
    map.put("WaitForSingleObject", waitForSingleObjectThunk) catch {};
    map.put("GetExitCodeThread", getExitCodeThreadThunk) catch {};
    map.put("ResumeThread", resumeThreadThunk) catch {};
    map.put("CloseHandle", closeHandleThunk) catch {};
    map.put("VirtualProtect", virtualProtectThunk) catch {};
    map.put("LoadLibraryA", loadLibraryAThunk) catch {};

    map.put("_SetConsoleTextAttribute@8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const attrs = frame.arg(1);
            const fg: u8 = @truncate(attrs & 0xF);
            const bg: u8 = @truncate((attrs >> 4) & 0x7);
            var buf: [32]u8 = undefined;
            const fg_code: u8 = if (fg < 8) 30 + fg else 82 + fg;
            const bg_code: u8 = 40 + bg;
            const seq = std.fmt.bufPrint(&buf, "\x1b[{d};{d}m", .{ fg_code, bg_code }) catch return;
            _ = std.c.write(1, seq.ptr, seq.len);
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_Sleep@4", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 1);
            abi.sleepMilliseconds(frame.arg(0));
            frame.finish(0);
        }
    }.handler) catch {};

    map.put("_GetStdHandle@4", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 1);
            const n = frame.arg(0);
            frame.finish(switch (n) {
                0xFFFFFFF6 => 0xB001,
                0xFFFFFFF5 => 0xB002,
                0xFFFFFFF4 => 0xB003,
                else => 0xB002,
            });
        }
    }.handler) catch {};

    map.put("GetConsoleMode", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const handle = frame.arg(0);
            const mode_ptr = frame.arg(1);
            if (handle < 0xB001 or handle > 0xB003) {
                ctx.win32_last_error = 6; // ERROR_INVALID_HANDLE
                frame.finish(0);
                return;
            }
            if (mode_ptr == 0) {
                ctx.win32_last_error = 87; // ERROR_INVALID_PARAMETER
                frame.finish(0);
                return;
            }
            const offset = std.math.sub(u32, mode_ptr, ctx.mem.base) catch {
                ctx.win32_last_error = 998; // ERROR_NOACCESS
                frame.finish(0);
                return;
            };
            if (@as(u64, offset) + 4 > ctx.mem.data.len) {
                ctx.win32_last_error = 998; // ERROR_NOACCESS
                frame.finish(0);
                return;
            }
            // Match the standard console modes exposed by a conventional
            // Windows console: processed/line/echo input, and processed,
            // wrapped output. The runner's standard handles are terminal
            // devices, so callers can safely take the console-specific path.
            ctx.mem.write32(mode_ptr, if (handle == 0xB001) 0x0007 else 0x0003);
            frame.finish(1);
        }
    }.handler) catch {};

    map.put("_WriteFile@20", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 5);
            const handle = frame.arg(0);
            const buffer = frame.arg(1);
            const n_bytes = frame.arg(2);
            const written_ptr = frame.arg(3);
            const overlapped = frame.arg(4);
            _ = overlapped;

            const bytes = ctx.mem.data[buffer - ctx.mem.base .. buffer - ctx.mem.base + n_bytes];
            const written = std.c.write(consoleFdForHandle(handle), bytes.ptr, bytes.len);

            if (written_ptr != 0) {
                ctx.mem.write32(written_ptr, @intCast(written));
            }
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_ExitProcess@4", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 1);
            const code = frame.arg(0);
            ctx.terminate(code);
        }
    }.handler) catch {};

    map.put("_FormatMessageA@28", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 7);
            const flags = frame.arg(0);
            const source = frame.arg(1);
            const msg_id = frame.arg(2);
            const lang_id = frame.arg(3);
            const buf_ptr = frame.arg(4);
            const n_size = frame.arg(5);
            const args_val = frame.arg(6);
            _ = args_val;
            _ = lang_id;
            _ = source;
            _ = msg_id;

            const err_msg = "System error occurred.\n";
            var written_len: u32 = 0;
            if (buf_ptr != 0) {
                const is_alloc = (flags & 0x100) != 0;
                if (is_alloc) {
                    const alloc_buf = heap_trace.alloc("FormatMessageA", heap_trace.process_heap_handle, 0, @intCast(err_msg.len + 1));
                    const dst = alloc_buf - ctx.mem.base;
                    @memcpy(ctx.mem.data[dst .. dst + err_msg.len], err_msg);
                    ctx.mem.write8(alloc_buf + @as(u32, @intCast(err_msg.len)), 0);
                    ctx.mem.write32(buf_ptr, alloc_buf);
                    written_len = @as(u32, @intCast(err_msg.len));
                } else if (n_size > 0) {
                    const dst = buf_ptr - ctx.mem.base;
                    const max_len: usize = @intCast(n_size - 1);
                    const copy_len = @min(err_msg.len, max_len);
                    @memcpy(ctx.mem.data[dst .. dst + copy_len], err_msg[0..copy_len]);
                    ctx.mem.write8(buf_ptr + @as(u32, @intCast(copy_len)), 0);
                    written_len = @intCast(copy_len);
                }
            }
            frame.finish(written_len);
        }
    }.handler) catch {};

    map.put("GetLastError", getLastErrorThunk) catch {};
    map.put("_GetLastError@0", getLastErrorThunk) catch {};
    map.put("SetLastError", setLastErrorThunk) catch {};
    map.put("_SetLastError@4", setLastErrorThunk) catch {};

    map.put("_GetSystemDefaultLangID@0", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 0);
            frame.finish(0x0409);
        }
    }.handler) catch {};

    map.put("_FillConsoleOutputCharacterA@20", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 5);
            const character = frame.arg(1);
            const length = frame.arg(2);
            const coord = frame.arg(3);
            const written_ptr = frame.arg(4);
            const ch: u8 = @truncate(character);
            const x = coord & 0xFFFF;
            const y = (coord >> 16) & 0xFFFF;
            var pos_buf: [32]u8 = undefined;
            const pos_seq = std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ y + 1, x + 1 }) catch return;
            _ = std.c.write(1, pos_seq.ptr, pos_seq.len);
            if (ch == ' ' and x == 0 and y == 0) {
                _ = std.c.write(1, "\x1b[2J\x1b[H", 7);
            } else {
                var fill_buf: [256]u8 = undefined;
                @memset(fill_buf[0..], ch);
                var remaining = length;
                while (remaining > 0) {
                    const chunk = @min(remaining, @as(u32, @intCast(fill_buf.len)));
                    _ = std.c.write(1, fill_buf[0..chunk].ptr, chunk);
                    remaining -= chunk;
                }
            }
            if (written_ptr != 0) {
                ctx.mem.write32(written_ptr, length);
            }
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_GetConsoleScreenBufferInfo@8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const handle = frame.arg(0);
            const info_ptr = frame.arg(1);
            _ = handle;

            if (info_ptr != 0) {
                const width: u16 = 80;
                const height: u16 = 25;
                ctx.mem.write16(info_ptr, width);
                ctx.mem.write16(info_ptr + 2, height);
                ctx.mem.write16(info_ptr + 4, 0);
                ctx.mem.write16(info_ptr + 6, 0);
                ctx.mem.write16(info_ptr + 8, 0x0007);
                ctx.mem.write16(info_ptr + 10, 0);
                ctx.mem.write16(info_ptr + 12, 0);
                ctx.mem.write16(info_ptr + 14, width);
                ctx.mem.write16(info_ptr + 16, height);
                ctx.mem.write16(info_ptr + 18, width);
                ctx.mem.write16(info_ptr + 20, height);
            }
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_SetConsoleCursorPosition@8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const coord = frame.arg(1);
            const x = coord & 0xFFFF;
            const y = (coord >> 16) & 0xFFFF;
            var buf: [32]u8 = undefined;
            const seq = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y + 1, x + 1 }) catch return;
            _ = std.c.write(1, seq.ptr, seq.len);
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_SetConsoleCursorInfo@8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const handle = frame.arg(0);
            const info_ptr = frame.arg(1);
            _ = info_ptr;
            _ = handle;
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_GetConsoleCursorInfo@8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const handle = frame.arg(0);
            const info_ptr = frame.arg(1);
            _ = handle;
            if (info_ptr != 0) {
                ctx.mem.write32(info_ptr, 25);
                ctx.mem.write32(info_ptr + 4, 1);
            }
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_SetConsoleCtrlHandler@8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const handler_addr = frame.arg(0);
            const add = frame.arg(1);
            _ = add;
            _ = handler_addr;
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_SetConsoleMode@8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const handle = frame.arg(0);
            const mode = frame.arg(1);
            _ = mode;
            _ = handle;
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_GetNumberOfConsoleInputEvents@8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const handle = frame.arg(0);
            const events_ptr = frame.arg(1);
            _ = handle;
            if (events_ptr != 0) {
                ctx.mem.write32(events_ptr, 0);
            }
            finishSuccess(frame);
        }
    }.handler) catch {};

    map.put("_ReadConsoleInputA@16", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 4);
            const handle = frame.arg(0);
            const buffer = frame.arg(1);
            const length = frame.arg(2);
            const events_read = frame.arg(3);
            _ = length;
            _ = buffer;
            _ = handle;
            _ = events_read;
            frame.finish(0);
        }
    }.handler) catch {};

    map.put("_HeapFree@12", heapFreeThunk) catch {};
    map.put("HeapFree", heapFreeThunk) catch {};
    map.put("_HeapAlloc@12", heapAllocThunk) catch {};
    map.put("HeapAlloc", heapAllocThunk) catch {};
    map.put("HeapSize", heapSizeThunk) catch {};
    map.put("_GetProcessHeap@0", getProcessHeapThunk) catch {};
    map.put("GetProcessHeap", getProcessHeapThunk) catch {};
    map.put("HeapCreate", heapCreateThunk) catch {};
    map.put("HeapDestroy", heapDestroyThunk) catch {};
    map.put("GetVersionExA", getVersionExAThunk) catch {};
    map.put("GetVersionExW", getVersionExWThunk) catch {};
    map.put("GetVersion", getVersionThunk) catch {};
    map.put("OutputDebugStringA", outputDebugStringAThunk) catch {};
    map.put("OutputDebugStringW", outputDebugStringWThunk) catch {};
    map.put("GetTimeZoneInformation", getTimeZoneInformationThunk) catch {};
    map.put("SetUnhandledExceptionFilter", setUnhandledExceptionFilterThunk) catch {};
    map.put("UnhandledExceptionFilter", unhandledExceptionFilterThunk) catch {};
    map.put("GetCurrentProcess", getCurrentProcessThunk) catch {};
    map.put("IsDebuggerPresent", isDebuggerPresentThunk) catch {};
    map.put("GetModuleFileNameA", getModuleFileNameAThunk) catch {};
    map.put("GetModuleHandleA", getModuleHandleAThunk) catch {};
    map.put("GetModuleHandleW", getModuleHandleWThunk) catch {};
    map.put("GetProcAddress", getProcAddressThunk) catch {};
    map.put("TlsAlloc", tlsAllocThunk) catch {};
    map.put("TlsFree", tlsFreeThunk) catch {};
    map.put("TlsGetValue", tlsGetValueThunk) catch {};
    map.put("TlsSetValue", tlsSetValueThunk) catch {};
    map.put("InitializeCriticalSection", initializeCriticalSectionThunk) catch {};
    map.put("_InitializeCriticalSection@4", initializeCriticalSectionThunk) catch {};
    map.put("DeleteCriticalSection", deleteCriticalSectionThunk) catch {};
    map.put("_DeleteCriticalSection@4", deleteCriticalSectionThunk) catch {};
    map.put("EnterCriticalSection", enterCriticalSectionThunk) catch {};
    map.put("_EnterCriticalSection@4", enterCriticalSectionThunk) catch {};
    map.put("LeaveCriticalSection", leaveCriticalSectionThunk) catch {};
    map.put("_LeaveCriticalSection@4", leaveCriticalSectionThunk) catch {};
    map.put("InterlockedIncrement", interlockedIncrementThunk) catch {};
    map.put("InterlockedDecrement", interlockedDecrementThunk) catch {};
    map.put("GetStartupInfoA", getStartupInfoAThunk) catch {};
    map.put("_GetStartupInfoA@4", getStartupInfoAThunk) catch {};
    map.put("GetStartupInfoW", getStartupInfoWThunk) catch {};
    map.put("GetFileType", getFileTypeThunk) catch {};
    map.put("_GetFileType@4", getFileTypeThunk) catch {};
    map.put("SetHandleCount", setHandleCountThunk) catch {};
    map.put("_SetHandleCount@4", setHandleCountThunk) catch {};
    map.put("GetCommandLineA", getCommandLineAThunk) catch {};
    map.put("GetCommandLineW", getCommandLineWThunk) catch {};
    map.put("CharNextW", charNextWThunk) catch {};
    map.put("GetEnvironmentStringsA", getEnvironmentStringsAThunk) catch {};
    map.put("GetEnvironmentStringsW", getEnvironmentStringsWThunk) catch {};
    map.put("FreeEnvironmentStringsA", freeEnvironmentStringsAThunk) catch {};
    map.put("FreeEnvironmentStringsW", freeEnvironmentStringsWThunk) catch {};
    text_thunks.register(ex);

    map.put("_GetTickCount@0", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 0);
            frame.finish(@truncate(@divTrunc(monotonicNanoseconds() orelse 0, std.time.ns_per_ms)));
        }
    }.handler) catch {};

    map.put("GetTickCount", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 0);
            frame.finish(@truncate(@divTrunc(monotonicNanoseconds() orelse 0, std.time.ns_per_ms)));
        }
    }.handler) catch {};

    map.put("GetCurrentProcessId", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 0);
            frame.finish(@intCast(std.c.getpid()));
        }
    }.handler) catch {};

    map.put("GetCurrentThreadId", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 0);
            frame.finish(@truncate(std.Thread.getCurrentId()));
        }
    }.handler) catch {};

    map.put("QueryPerformanceCounter", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 1);
            const counter_ptr = frame.arg(0);
            if (counter_ptr == 0) {
                frame.finish(0);
                return;
            }
            const ticks = monotonicNanoseconds() orelse {
                frame.finish(0);
                return;
            };
            ctx.mem.write32(counter_ptr, @truncate(ticks));
            ctx.mem.write32(counter_ptr + 4, @truncate(ticks >> 32));
            frame.finish(1);
        }
    }.handler) catch {};

    map.put("QueryPerformanceFrequency", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 1);
            const frequency_ptr = frame.arg(0);
            if (frequency_ptr == 0) {
                frame.finish(0);
                return;
            }
            // QueryPerformanceCounter above uses nanoseconds as its unit.
            ctx.mem.write32(frequency_ptr, @truncate(std.time.ns_per_s));
            ctx.mem.write32(frequency_ptr + 4, 0);
            frame.finish(1);
        }
    }.handler) catch {};

    // The PE32 loader's CRT startup queries this before reaching its own entry
    // point. FILETIME is a 64-bit count of 100 ns intervals since 1601-01-01.
    map.put("GetSystemTimeAsFileTime", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 1);
            const file_time_ptr = frame.arg(0);
            if (file_time_ptr != 0) {
                var ts: std.c.timespec = undefined;
                if (std.c.clock_gettime(@as(std.c.clockid_t, .REALTIME), &ts) == 0) {
                    const windows_epoch_delta_seconds: u64 = 11_644_473_600;
                    const ticks_per_second: u64 = 10_000_000;
                    const ticks = (@as(u64, @intCast(ts.sec)) + windows_epoch_delta_seconds) * ticks_per_second +
                        @as(u64, @intCast(ts.nsec)) / 100;
                    ctx.mem.write32(file_time_ptr, @truncate(ticks));
                    ctx.mem.write32(file_time_ptr + 4, @truncate(ticks >> 32));
                }
            }
            // This Win32 API returns void; preserve EAX and apply stdcall
            // cleanup for the single pointer argument.
            frame.finish(ctx.regs.eax);
        }
    }.handler) catch {};

    map.put("GetLocalTime", getSystemTimeThunk) catch {};
    map.put("GetSystemTime", getSystemTimeThunk) catch {};
    map.put("_GetSystemTime@4", getSystemTimeThunk) catch {};

    map.put("_FillConsoleOutputAttribute@20", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 5);
            const attr = frame.arg(1);
            const length = frame.arg(2);
            const coord = frame.arg(3);
            const written_ptr = frame.arg(4);
            const x = coord & 0xFFFF;
            const y = (coord >> 16) & 0xFFFF;
            var pos_buf: [32]u8 = undefined;
            const pos_seq = std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ y + 1, x + 1 }) catch return;
            _ = std.c.write(1, pos_seq.ptr, pos_seq.len);
            const fg: u8 = @truncate(attr & 0xF);
            const bg: u8 = @truncate((attr >> 4) & 0x7);
            const fg_code: u8 = if (fg < 8) 30 + fg else 82 + fg;
            const bg_code: u8 = 40 + bg;
            var attr_buf: [32]u8 = undefined;
            const attr_seq = std.fmt.bufPrint(&attr_buf, "\x1b[{d};{d}m", .{ fg_code, bg_code }) catch return;
            _ = std.c.write(1, attr_seq.ptr, attr_seq.len);
            if (written_ptr != 0) {
                ctx.mem.write32(written_ptr, length);
            }
            finishSuccess(frame);
        }
    }.handler) catch {};

    const undecorated_aliases = [_]struct { name: []const u8, decorated: []const u8 }{
        .{ .name = "ExitProcess", .decorated = "_ExitProcess@4" },
        .{ .name = "GetStdHandle", .decorated = "_GetStdHandle@4" },
        .{ .name = "WriteFile", .decorated = "_WriteFile@20" },
        .{ .name = "Sleep", .decorated = "_Sleep@4" },
        .{ .name = "GetLastError", .decorated = "_GetLastError@0" },
    };
    for (undecorated_aliases) |alias| {
        if (map.get(alias.decorated)) |handler| {
            map.put(alias.name, handler) catch {};
        }
    }
}

/// Restore direct function-pointer mappings after a runner resets its IAT
/// registry for a newly loaded PE image.
pub fn register_dynamic_iat_targets(ex: *Executor) void {
    opengl_thunks.registerDynamicTargets(ex);
}

test "register win32 console thunks" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    ex.push(0xFFFFFFF5);
    ex.dispatch_import("_GetStdHandle@4");
    try testing.expectEqual(@as(u32, 0xB002), ex.regs.eax);
    try testing.expect(ex.import_table.contains("GetStdHandle"));
    try testing.expect(ex.import_table.contains("GetConsoleMode"));
    try testing.expect(ex.import_table.contains("GetVersionExA"));
    try testing.expect(ex.import_table.contains("VirtualAlloc"));
    try testing.expect(ex.import_table.contains("VirtualFree"));
    try testing.expect(ex.import_table.contains("SetUnhandledExceptionFilter"));
    try testing.expect(ex.import_table.contains("UnhandledExceptionFilter"));
    try testing.expect(ex.import_table.contains("GetCurrentProcess"));
    try testing.expect(ex.import_table.contains("IsDebuggerPresent"));
    try testing.expect(ex.import_table.contains("HeapSize"));
    try testing.expect(ex.import_table.contains("GetModuleFileNameA"));
    try testing.expect(ex.import_table.contains("HeapCreate"));
    try testing.expect(ex.import_table.contains("HeapDestroy"));
    try testing.expect(ex.import_table.contains("GetModuleHandleA"));
    try testing.expect(ex.import_table.contains("GetProcAddress"));
    try testing.expect(ex.import_table.contains("TlsAlloc"));
    try testing.expect(ex.import_table.contains("TlsFree"));
    try testing.expect(ex.import_table.contains("TlsGetValue"));
    try testing.expect(ex.import_table.contains("TlsSetValue"));
    try testing.expect(ex.import_table.contains("InitializeCriticalSection"));
    try testing.expect(ex.import_table.contains("EnterCriticalSection"));
    try testing.expect(ex.import_table.contains("LeaveCriticalSection"));
    try testing.expect(ex.import_table.contains("DeleteCriticalSection"));
    try testing.expect(ex.import_table.contains("InterlockedIncrement"));
    try testing.expect(ex.import_table.contains("InterlockedDecrement"));
    try testing.expect(ex.import_table.contains("GetStartupInfoA"));
    try testing.expect(ex.import_table.contains("GetFileType"));
    try testing.expect(ex.import_table.contains("SetHandleCount"));
    try testing.expect(ex.import_table.contains("GetCommandLineA"));
    try testing.expect(ex.import_table.contains("SetLastError"));
    try testing.expect(ex.import_table.contains("GetLastError"));
    try testing.expect(ex.import_table.contains("GetEnvironmentStringsA"));
    try testing.expect(ex.import_table.contains("GetEnvironmentStringsW"));
    try testing.expect(ex.import_table.contains("FreeEnvironmentStringsA"));
    try testing.expect(ex.import_table.contains("FreeEnvironmentStringsW"));
    try testing.expect(ex.import_table.contains("WideCharToMultiByte"));
    try testing.expect(ex.import_table.contains("MultiByteToWideChar"));
}

test "GetConsoleMode reports bounded modes for synthetic standard handles" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    ex.push(0x0800);
    ex.push(0xB001);
    ex.dispatch_import("GetConsoleMode");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try testing.expectEqual(@as(u32, 0x0007), ex.mem.read32(0x0800));

    ex.push(0x0804);
    ex.push(0xB002);
    ex.dispatch_import("GetConsoleMode");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try testing.expectEqual(@as(u32, 0x0003), ex.mem.read32(0x0804));

    ex.push(0x0808);
    ex.push(0xDEAD);
    ex.dispatch_import("GetConsoleMode");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try testing.expectEqual(@as(u32, 6), ex.win32_last_error);

    ex.push(0);
    ex.push(0xB003);
    ex.dispatch_import("GetConsoleMode");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try testing.expectEqual(@as(u32, 87), ex.win32_last_error);
}

test "UnhandledExceptionFilter and pseudo-process queries follow Win32 contracts" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    ex.push(0x12345678);
    ex.dispatch_import("SetUnhandledExceptionFilter");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try testing.expectEqual(@as(u32, 0x12345678), ex.win32_unhandled_exception_filter);

    ex.push(0x87654321);
    ex.dispatch_import("SetUnhandledExceptionFilter");
    try testing.expectEqual(@as(u32, 0x12345678), ex.regs.eax);
    try testing.expectEqual(@as(u32, 0x87654321), ex.win32_unhandled_exception_filter);

    ex.push(0);
    ex.dispatch_import("UnhandledExceptionFilter");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
    ex.dispatch_import("GetCurrentProcess");
    try testing.expectEqual(std.math.maxInt(u32), ex.regs.eax);
    ex.dispatch_import("IsDebuggerPresent");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);

    const allocation = heap_trace.alloc("HeapSize-test", heap_trace.process_heap_handle, 0, 32);
    ex.push(allocation);
    ex.push(0);
    ex.push(heap_trace.process_heap_handle);
    ex.dispatch_import("HeapSize");
    try testing.expectEqual(@as(u32, 32), ex.regs.eax);
}

test "GetCommandLineA returns the stable guest command line address" {
    var ex = Executor.init(std.testing.allocator, 64 * 1024);
    defer ex.deinit();
    ex.regs.esp = 2048;
    ex.mem.base = 0x0200_0000;
    ex.pe32_command_line = "\"maze.exe\"";
    register_win32_console_thunks(&ex);

    ex.dispatch_import("GetCommandLineA");

    const command_line_address = ex.regs.eax;
    try testing.expect(command_line_address >= ex.mem.base);
    const command_line_offset: usize = @intCast(command_line_address - ex.mem.base);
    try testing.expectEqualStrings("\"maze.exe\"", std.mem.sliceTo(ex.mem.data[command_line_offset..], 0));

    ex.dispatch_import("GetCommandLineA");
    try testing.expectEqual(command_line_address, ex.regs.eax);
    try testing.expectEqual(@as(u32, 2048), ex.regs.esp);
}

test "GetCommandLineW returns a stable UTF-16 guest command line" {
    var ex = Executor.init(std.testing.allocator, 128 * 1024);
    defer ex.deinit();
    ex.regs.esp = 2048;
    ex.mem.base = 0x0200_0000;
    ex.pe32_command_line = "\"maze Ω.exe\"";
    register_win32_console_thunks(&ex);

    ex.dispatch_import("GetCommandLineW");

    const command_line_address = ex.regs.eax;
    try testing.expect(command_line_address >= ex.mem.base);
    const command_line_offset: usize = @intCast(command_line_address - ex.mem.base);
    const expected = try std.unicode.utf8ToUtf16LeAllocZ(std.testing.allocator, ex.pe32_command_line);
    defer std.testing.allocator.free(expected);
    for (expected, 0..) |unit, index| {
        try testing.expectEqual(unit, ex.mem.read16(command_line_address + @as(u32, @intCast(index * 2))));
    }
    try testing.expectEqual(@as(u16, 0), ex.mem.read16(command_line_address + @as(u32, @intCast(expected.len * 2))));
    try testing.expectEqual(@as(u8, 0), ex.mem.data[command_line_offset + expected.len * 2]);
    try testing.expectEqual(@as(u8, 0), ex.mem.data[command_line_offset + expected.len * 2 + 1]);

    ex.dispatch_import("GetCommandLineW");
    try testing.expectEqual(command_line_address, ex.regs.eax);
    try testing.expectEqual(@as(u32, 2048), ex.regs.esp);
}

test "CharNextW advances one UTF-16 code unit and stays at the terminator" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.mem.base = 0x0100_0000;
    ex.regs.esp = 2048;
    ex.mem.write16(0x0100_0100, 'A');
    ex.mem.write16(0x0100_0102, 0x03A9);
    ex.mem.write16(0x0100_0104, 0);
    register_win32_console_thunks(&ex);

    ex.push(0x0100_0100);
    ex.dispatch_import("CharNextW");
    try testing.expectEqual(@as(u32, 0x0100_0102), ex.regs.eax);
    ex.push(0x0100_0104);
    ex.dispatch_import("CharNextW");
    try testing.expectEqual(@as(u32, 0x0100_0104), ex.regs.eax);
}

test "environment string blocks have double-NUL termination and matching free contracts" {
    var ex = Executor.init(std.testing.allocator, 64 * 1024);
    defer ex.deinit();
    ex.mem.base = 0x0200_0000;
    ex.regs.esp = 4096;
    register_win32_console_thunks(&ex);

    ex.dispatch_import("GetEnvironmentStringsW");
    const wide_address = ex.regs.eax;
    try testing.expect(wide_address >= ex.mem.base);
    try testing.expectEqual(@as(u32, 0), ex.mem.read32(wide_address));

    ex.push(wide_address);
    ex.dispatch_import("FreeEnvironmentStringsW");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);

    ex.dispatch_import("GetEnvironmentStringsA");
    const ansi_address = ex.regs.eax;
    const ansi_offset: usize = @intCast(ansi_address - ex.mem.base);
    try testing.expectEqual(@as(u16, 0), ex.mem.read16(ansi_address));
    try testing.expectEqual(@as(u8, 0), ex.mem.data[ansi_offset + 1]);

    ex.push(ansi_address + 2);
    ex.dispatch_import("FreeEnvironmentStringsA");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
    ex.push(ansi_address);
    ex.dispatch_import("FreeEnvironmentStringsA");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
}

test "GetStartupInfoA initializes the PE32 startup structure and console handles" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    const startup_info: u32 = 1024;
    @memset(ex.mem.data[startup_info .. startup_info + 68], 0xA5);
    ex.push(startup_info);
    ex.dispatch_import("GetStartupInfoA");

    try testing.expectEqual(@as(u32, 68), ex.mem.read32(startup_info));
    try testing.expectEqual(@as(u32, 0xB001), ex.mem.read32(startup_info + 56));
    try testing.expectEqual(@as(u32, 0xB002), ex.mem.read32(startup_info + 60));
    try testing.expectEqual(@as(u32, 0xB003), ex.mem.read32(startup_info + 64));
    try testing.expectEqual(@as(u8, 0), ex.mem.data[startup_info + 4]);
}

test "GetStartupInfoW initializes the PE32 startup structure and console handles" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    const startup_info: u32 = 1024;
    @memset(ex.mem.data[startup_info .. startup_info + 68], 0xA5);
    ex.push(startup_info);
    ex.dispatch_import("GetStartupInfoW");

    try testing.expectEqual(@as(u32, 68), ex.mem.read32(startup_info));
    try testing.expectEqual(@as(u32, 0xB001), ex.mem.read32(startup_info + 56));
    try testing.expectEqual(@as(u32, 0xB002), ex.mem.read32(startup_info + 60));
    try testing.expectEqual(@as(u32, 0xB003), ex.mem.read32(startup_info + 64));
    try testing.expectEqual(@as(u8, 0), ex.mem.data[startup_info + 4]);
}

test "GetFileType reports synthetic standard handles as character devices" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    ex.push(0xB002);
    ex.dispatch_import("GetFileType");
    try testing.expectEqual(@as(u32, 2), ex.regs.eax);

    ex.push(0xDEAD);
    ex.dispatch_import("GetFileType");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
}

test "SetHandleCount preserves the Win32 no-op return contract" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    ex.push(256);
    ex.dispatch_import("SetHandleCount");
    try testing.expectEqual(@as(u32, 256), ex.regs.eax);
}

test "SetLastError and GetLastError preserve the per-executor Win32 error value" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    ex.push(87);
    ex.dispatch_import("SetLastError");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
    ex.dispatch_import("GetLastError");
    try testing.expectEqual(@as(u32, 87), ex.regs.eax);
}

test "PE32 interlocked counter imports return wrapped 32-bit values" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);
    const counter: u32 = 256;
    ex.mem.write32(counter, 41);

    ex.push(counter);
    ex.dispatch_import("InterlockedIncrement");
    try testing.expectEqual(@as(u32, 42), ex.regs.eax);
    try testing.expectEqual(@as(u32, 42), ex.mem.read32(counter));

    ex.push(counter);
    ex.dispatch_import("InterlockedDecrement");
    try testing.expectEqual(@as(u32, 41), ex.regs.eax);
    try testing.expectEqual(@as(u32, 41), ex.mem.read32(counter));

    ex.mem.write32(counter, std.math.maxInt(u32));
    ex.push(counter);
    ex.dispatch_import("InterlockedIncrement");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
}

test "PE32 critical section imports preserve single-thread recursive lock state" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);
    const section: u32 = 512;

    ex.push(section);
    ex.dispatch_import("InitializeCriticalSection");
    try testing.expectEqual(std.math.maxInt(u32), ex.mem.read32(section + 4));
    try testing.expectEqual(@as(u32, 0), ex.mem.read32(section + 8));

    ex.push(section);
    ex.dispatch_import("EnterCriticalSection");
    ex.push(section);
    ex.dispatch_import("EnterCriticalSection");
    try testing.expectEqual(@as(u32, 1), ex.mem.read32(section + 4));
    try testing.expectEqual(@as(u32, 2), ex.mem.read32(section + 8));
    try testing.expectEqual(@as(u32, 1), ex.mem.read32(section + 12));

    ex.push(section);
    ex.dispatch_import("LeaveCriticalSection");
    try testing.expectEqual(@as(u32, 1), ex.mem.read32(section + 8));
    try testing.expectEqual(@as(u32, 1), ex.mem.read32(section + 12));
    ex.push(section);
    ex.dispatch_import("LeaveCriticalSection");
    try testing.expectEqual(std.math.maxInt(u32), ex.mem.read32(section + 4));
    try testing.expectEqual(@as(u32, 0), ex.mem.read32(section + 8));
    try testing.expectEqual(@as(u32, 0), ex.mem.read32(section + 12));

    ex.push(section);
    ex.dispatch_import("DeleteCriticalSection");
    try testing.expectEqual(std.math.maxInt(u32), ex.mem.read32(section + 4));
}

test "HeapCreate and HeapDestroy route through the synthetic PE32 heap" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);

    ex.push(0x00100000); // max size
    ex.push(0x00010000); // initial size
    ex.push(0); // options
    ex.dispatch_import("HeapCreate");
    try testing.expectEqual(heap_trace.process_heap_handle, ex.regs.eax);

    ex.push(heap_trace.process_heap_handle);
    ex.dispatch_import("HeapDestroy");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
}

test "GetModuleHandleA and GetProcAddress provide bounded PE32 module lookup" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.mem.base = 0x00400000;
    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);
    const module_name = "KERNEL32.DLL\x00";
    const missing_name = "FlsAlloc\x00";
    @memcpy(ex.mem.data[0x100 .. 0x100 + module_name.len], module_name);
    @memcpy(ex.mem.data[0x200 .. 0x200 + missing_name.len], missing_name);

    ex.push(0x00400100);
    ex.dispatch_import("GetModuleHandleA");
    const module = ex.regs.eax;
    try testing.expectEqual(@as(u32, 0x77000000), module);

    ex.push(0x00400200);
    ex.push(module);
    ex.dispatch_import("GetProcAddress");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
}

test "GetModuleHandleW resolves the main image and synthetic kernel module" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.mem.base = 0x00400000;
    ex.pe32_main_module_base = 0x01000000;
    ex.pe32_image_path = "C:\\Games\\maze.exe";
    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);

    ex.push(0);
    ex.dispatch_import("GetModuleHandleW");
    try testing.expectEqual(@as(u32, 0x01000000), ex.regs.eax);

    const kernel32 = std.unicode.utf8ToUtf16LeStringLiteral("KERNEL32.DLL");
    @memcpy(ex.mem.data[0x100 .. 0x100 + kernel32.len * 2], std.mem.sliceAsBytes(kernel32));
    ex.push(0x00400100);
    ex.dispatch_import("GetModuleHandleW");
    try testing.expectEqual(@as(u32, 0x77000000), ex.regs.eax);

    const main_image = std.unicode.utf8ToUtf16LeStringLiteral("maze.exe");
    @memcpy(ex.mem.data[0x200 .. 0x200 + main_image.len * 2], std.mem.sliceAsBytes(main_image));
    ex.push(0x00400200);
    ex.dispatch_import("GetModuleHandleW");
    try testing.expectEqual(@as(u32, 0x01000000), ex.regs.eax);
}

test "Win32 TLS imports allocate, store, read, and free guest slots" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);

    ex.dispatch_import("TlsAlloc");
    const index = ex.regs.eax;
    try testing.expect(index < 64);
    ex.push(0x12345678);
    ex.push(index);
    ex.dispatch_import("TlsSetValue");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    ex.push(index);
    ex.dispatch_import("TlsGetValue");
    try testing.expectEqual(@as(u32, 0x12345678), ex.regs.eax);
    ex.push(index);
    ex.dispatch_import("TlsFree");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
}

test "GetVersionExA reports the emulated Windows version" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);
    const version_info: u32 = 256;
    ex.mem.write32(version_info, 148);
    ex.push(version_info);
    ex.dispatch_import("GetVersionExA");

    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try testing.expectEqual(@as(u32, 10), ex.mem.read32(version_info + 4));
    try testing.expectEqual(@as(u32, 0), ex.mem.read32(version_info + 8));
    try testing.expectEqual(@as(u32, 19045), ex.mem.read32(version_info + 12));
    try testing.expectEqual(@as(u32, 2), ex.mem.read32(version_info + 16));
}

test "GetVersionExW reports the emulated Windows version and clears its wide service-pack string" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);
    const version_info: u32 = 256;
    ex.mem.write32(version_info, 276);
    @memset(ex.mem.data[version_info + 20 .. version_info + 276], 0xA5);
    ex.push(version_info);
    ex.dispatch_import("GetVersionExW");

    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try testing.expectEqual(@as(u32, 10), ex.mem.read32(version_info + 4));
    try testing.expectEqual(@as(u32, 0), ex.mem.read32(version_info + 8));
    try testing.expectEqual(@as(u32, 19045), ex.mem.read32(version_info + 12));
    try testing.expectEqual(@as(u32, 2), ex.mem.read32(version_info + 16));
    try testing.expectEqual(@as(u16, 0), ex.mem.read16(version_info + 20));
    try testing.expectEqual(@as(u8, 0), ex.mem.data[version_info + 275]);
}

test "GetTimeZoneInformation returns a bounded zero-bias UTC structure" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);

    const zone_info: u32 = 1024;
    @memset(ex.mem.data[zone_info .. zone_info + 172], 0xA5);
    ex.push(zone_info);
    ex.dispatch_import("GetTimeZoneInformation");

    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try testing.expectEqual(@as(u32, 0), ex.mem.read32(zone_info));
    try testing.expectEqual(@as(u16, 0), ex.mem.read16(zone_info + 68));
    try testing.expectEqual(@as(u32, 0), ex.mem.read32(zone_info + 168));
}

test "GetVersion reports the matching emulated Windows version" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);
    ex.dispatch_import("GetVersion");

    try testing.expectEqual((@as(u32, 19045) << 16) | 10, ex.regs.eax);
    try testing.expectEqual(@as(u32, 3072), ex.regs.esp);
}

test "GetModuleFileNameA writes the guest module path using Windows separators" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 3072;
    ex.pe32_image_path = "/Games/Playable3DMaze/Loader.exe";
    register_win32_console_thunks(&ex);
    const output: u32 = 512;
    ex.push(64);
    ex.push(output);
    ex.push(0);
    ex.dispatch_import("GetModuleFileNameA");

    const written = std.mem.sliceTo(ex.mem.data[output..], 0);
    try testing.expectEqualStrings("\\Games\\Playable3DMaze\\Loader.exe", written);
    try testing.expectEqual(@as(u32, written.len), ex.regs.eax);
    try testing.expectEqual(@as(u32, 3072), ex.regs.esp);
}

test "Sleep thunk" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    ex.push(1);
    ex.dispatch_import("_Sleep@4");
    try testing.expect(true);
}

test "FormatMessageA writes into caller buffer" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);

    const buffer_ptr: u32 = 128;
    ex.push(0);
    ex.push(32);
    ex.push(buffer_ptr);
    ex.push(0);
    ex.push(0);
    ex.push(0);
    ex.push(0);

    ex.dispatch_import("_FormatMessageA@28");

    try testing.expect(ex.regs.eax > 0);
    try testing.expectEqual(@as(u8, 'S'), ex.mem.read8(buffer_ptr));
}

test "GetSystemTime populates a plausible UTC year" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);

    const system_time_ptr: u32 = 256;
    ex.push(system_time_ptr);
    ex.dispatch_import("_GetSystemTime@4");

    const year = ex.mem.read16(system_time_ptr);
    try testing.expect(year >= 2024);
}

test "GetLocalTime populates SYSTEMTIME using the configured UTC timezone" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);

    const system_time_ptr: u32 = 256;
    ex.push(system_time_ptr);
    ex.dispatch_import("GetLocalTime");

    try testing.expect(ex.mem.read16(system_time_ptr) >= 2024);
    try testing.expect(ex.mem.read16(system_time_ptr + 2) >= 1);
    try testing.expect(ex.mem.read16(system_time_ptr + 2) <= 12);
    try testing.expectEqual(@as(u32, 3072), ex.regs.esp);
}

test "GetSystemTimeAsFileTime writes FILETIME and cleans its argument" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 3072;
    ex.regs.eax = 0x13579BDF;
    register_win32_console_thunks(&ex);

    const file_time_ptr: u32 = 256;
    ex.push(file_time_ptr);
    ex.dispatch_import("GetSystemTimeAsFileTime");

    const low = ex.mem.read32(file_time_ptr);
    const high = ex.mem.read32(file_time_ptr + 4);
    const file_time = (@as(u64, high) << 32) | low;
    try testing.expect(file_time > 0);
    try testing.expectEqual(@as(u32, 0x13579BDF), ex.regs.eax);
    try testing.expectEqual(@as(u32, 3072), ex.regs.esp);
}

test "Kernel32 clock and identity thunks use consistent host units" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 3072;
    register_win32_console_thunks(&ex);
    ex.dispatch_import("GetCurrentProcessId");
    try testing.expect(ex.regs.eax != 0);
    ex.dispatch_import("GetCurrentThreadId");
    try testing.expect(ex.regs.eax != 0);
    ex.dispatch_import("GetTickCount");
    const tick_before = ex.regs.eax;

    const counter_ptr: u32 = 256;
    ex.push(counter_ptr);
    ex.dispatch_import("QueryPerformanceCounter");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    const counter = (@as(u64, ex.mem.read32(counter_ptr + 4)) << 32) | ex.mem.read32(counter_ptr);
    try testing.expect(counter > 0);

    const frequency_ptr: u32 = 264;
    ex.push(frequency_ptr);
    ex.dispatch_import("QueryPerformanceFrequency");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    const frequency = (@as(u64, ex.mem.read32(frequency_ptr + 4)) << 32) | ex.mem.read32(frequency_ptr);
    try testing.expectEqual(@as(u64, std.time.ns_per_s), frequency);
    try testing.expect(tick_before != 0);
}

test "ExitProcess thunk registration" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    try testing.expect(ex.import_table.contains("_ExitProcess@4"));
}

test "nested process imports fail explicitly when no process manager is attached" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    for (0..10) |_| ex.push(0);
    ex.dispatch_import("CreateProcessA");

    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try testing.expectEqual(@as(u32, 50), ex.win32_last_error); // ERROR_NOT_SUPPORTED
    try testing.expectEqual(@as(u32, 2048), ex.regs.esp);
}

const ProcessApiProbe = struct {
    seen: ?Executor.ProcessApi = null,
};

fn processApiProbe(context: *anyopaque, _: *Executor, api: Executor.ProcessApi) u32 {
    const probe: *ProcessApiProbe = @ptrCast(@alignCast(context));
    probe.seen = api;
    return 0x12345678;
}

test "process imports dispatch through the attached runtime service" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    var probe = ProcessApiProbe{};
    ex.process_api_context = &probe;
    ex.process_api_handler = processApiProbe;
    ex.regs.esp = 2048;
    register_win32_console_thunks(&ex);

    for (0..10) |_| ex.push(0);
    ex.dispatch_import("CreateProcessA");

    try testing.expectEqual(Executor.ProcessApi.create_process_a, probe.seen.?);
    try testing.expectEqual(@as(u32, 0x12345678), ex.regs.eax);
    try testing.expectEqual(@as(u32, 2048), ex.regs.esp);

    probe.seen = null;
    for (0..4) |_| ex.push(0);
    ex.dispatch_import("VirtualAlloc");
    try testing.expectEqual(Executor.ProcessApi.virtual_alloc, probe.seen.?);
    try testing.expectEqual(@as(u32, 0x12345678), ex.regs.eax);
    try testing.expectEqual(@as(u32, 2048), ex.regs.esp);

    probe.seen = null;
    for (0..3) |_| ex.push(0);
    ex.dispatch_import("VirtualFree");
    try testing.expectEqual(Executor.ProcessApi.virtual_free, probe.seen.?);
    try testing.expectEqual(@as(u32, 0x12345678), ex.regs.eax);
    try testing.expectEqual(@as(u32, 2048), ex.regs.esp);
}
