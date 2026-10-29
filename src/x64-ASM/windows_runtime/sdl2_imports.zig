//! Small, explicit SDL2 import boundary for PE64 guests.
//!
//! Rosetta does not execute Windows DLL machine code as a host library. The
//! PE runner binds imported names to guest-side contracts instead. Keep the
//! inventory tied to actual SDL exports and separate names with a working
//! window bridge from names that are recognized but not implemented yet.

const std = @import("std");
const software = @import("sdl2_software.zig");
const audio = @import("sdl2_audio.zig");
const sdl2_format = @import("sdl2_format.zig");

const sdl_event_bytes = 56;
const sdl_scancode_mask: u32 = 1 << 30;

pub const Support = enum { implemented, deferred };

const implemented_imports = [_][]const u8{
    "SDL_AllocFormat",
    "SDL_BuildAudioCVT",
    "SDL_CreateRGBSurface",
    "SDL_CreateRenderer",
    "SDL_CreateTexture",
    "SDL_CreateWindow",
    "SDL_ConvertAudio",
    "SDL_CloseAudioDevice",
    "SDL_DestroyRenderer",
    "SDL_DestroyTexture",
    "SDL_DestroyWindow",
    "SDL_FillRect",
    "SDL_FreeFormat",
    "SDL_FreeSurface",
    "SDL_GetDisplayBounds",
    "SDL_GetBasePath",
    "SDL_GetError",
    "SDL_GetNumVideoDisplays",
    "SDL_GetPixelFormatName",
    "SDL_GetTicks",
    "SDL_GetWindowDisplayIndex",
    "SDL_GetWindowSize",
    "SDL_Init",
    "SDL_InitSubSystem",
    "SDL_LockTexture",
    "SDL_LogMessageV",
    "SDL_LockAudioDevice",
    "SDL_MapRGB",
    "SDL_OpenAudioDevice",
    "SDL_UpperBlit",
    "SDL_QueryTexture",
    "SDL_RenderClear",
    "SDL_RenderCopy",
    "SDL_RenderPresent",
    "SDL_SetRenderDrawColor",
    "SDL_SetWindowFullscreen",
    "SDL_SetWindowPosition",
    "SDL_ShowSimpleMessageBox",
    "SDL_free",
    "SDL_iconv_string",
    "SDL_memcpy",
    "SDL_PollEvent",
    "SDL_PauseAudioDevice",
    "SDL_PumpEvents",
    "SDL_Quit",
    "SDL_QuitSubSystem",
    "SDL_SetMainReady",
    "SDL_SetWindowSize",
    "SDL_ShowWindow",
    "SDL_strlen",
    "SDL_strlcpy",
    "SDL_vsnprintf",
    "SDL_UnlockTexture",
    "SDL_UnlockAudioDevice",
    "SDL_wcslen",
};

// These are the named imports in the supplied SDL2.dll / SDL2_net.dll
// dependency surface. Names outside these bounded lists remain unsupported;
// a typo or a different SDL build cannot silently inherit a fake contract.
const imported_sdl2 = [_][]const u8{
    "SDL_AllocFormat",         "SDL_BuildAudioCVT",        "SDL_CloseAudioDevice",    "SDL_ConvertAudio",
    "SDL_CreateRGBSurface",    "SDL_CreateRenderer",       "SDL_CreateTexture",       "SDL_CreateWindow",
    "SDL_Delay",               "SDL_DestroyRenderer",      "SDL_DestroyTexture",      "SDL_DestroyWindow",
    "SDL_FillRect",            "SDL_FreeFormat",           "SDL_FreeSurface",         "SDL_GetBasePath",
    "SDL_GetDisplayBounds",    "SDL_GetError",             "SDL_GetNumVideoDisplays", "SDL_GetPixelFormatName",
    "SDL_GetScancodeFromName", "SDL_GetScancodeName",      "SDL_GetTicks",            "SDL_GetWindowDisplayIndex",
    "SDL_GetWindowSize",       "SDL_Init",                 "SDL_InitSubSystem",       "SDL_JoystickClose",
    "SDL_JoystickEventState",  "SDL_JoystickGetAxis",      "SDL_JoystickGetButton",   "SDL_JoystickGetHat",
    "SDL_JoystickName",        "SDL_JoystickNumAxes",      "SDL_JoystickNumButtons",  "SDL_JoystickNumHats",
    "SDL_JoystickOpen",        "SDL_JoystickUpdate",       "SDL_LockAudioDevice",     "SDL_LockTexture",
    "SDL_Log",                 "SDL_LogDebug",             "SDL_LogError",            "SDL_LogMessageV",
    "SDL_LogWarn",             "SDL_MapRGB",               "SDL_NumJoysticks",        "SDL_OpenAudioDevice",
    "SDL_PauseAudioDevice",    "SDL_PollEvent",            "SDL_PushEvent",           "SDL_QueryTexture",
    "SDL_Quit",                "SDL_QuitSubSystem",        "SDL_RenderClear",         "SDL_RenderCopy",
    "SDL_RenderPresent",       "SDL_SetHint",              "SDL_SetMainReady",        "SDL_SetRelativeMouseMode",
    "SDL_SetRenderDrawColor",  "SDL_SetWindowFullscreen",  "SDL_SetWindowPosition",   "SDL_SetWindowSize",
    "SDL_ShowCursor",          "SDL_ShowSimpleMessageBox", "SDL_ShowWindow",          "SDL_StartTextInput",
    "SDL_StopTextInput",       "SDL_UnlockAudioDevice",    "SDL_UnlockTexture",       "SDL_UpperBlit",
    "SDL_free",                "SDL_iconv_string",         "SDL_memcpy",              "SDL_strlcpy",
    "SDL_strlen",              "SDL_vsnprintf",            "SDL_wcslen",
};

const imported_sdl2_net = [_][]const u8{
    "SDLNet_AllocPacket", "SDLNet_FreePacket",  "SDLNet_GetError", "SDLNet_Init",
    "SDLNet_Quit",        "SDLNet_ResolveHost", "SDLNet_UDP_Bind", "SDLNet_UDP_Open",
    "SDLNet_UDP_Recv",    "SDLNet_UDP_Send",
};

pub fn classify(dll_name: []const u8, function_name: []const u8) ?Support {
    const names: []const []const u8 = if (std.ascii.eqlIgnoreCase(dll_name, "SDL2.dll"))
        &imported_sdl2
    else if (std.ascii.eqlIgnoreCase(dll_name, "SDL2_net.dll"))
        &imported_sdl2_net
    else
        return null;

    for (names) |name| {
        if (!std.mem.eql(u8, name, function_name)) continue;
        for (implemented_imports) |implemented| {
            if (std.mem.eql(u8, implemented, function_name)) return .implemented;
        }
        return .deferred;
    }
    return null;
}

pub fn handle(comptime api: type, state: anytype, dll_name: []const u8, name: []const u8, direct_return_rip: ?u64) bool {
    if (!std.ascii.eqlIgnoreCase(dll_name, "SDL2.dll")) return false;
    if (audio.handle(api, state, name, direct_return_rip)) return true;
    if (software.handle(api, state, name, direct_return_rip)) return true;
    if (handleFormatting(api, state, name, direct_return_rip)) return true;
    const arg = api._arg;
    const finish = api._finish;
    const guestStateField = api._guestStateField;
    const regs = &guestStateField(state, "regs").*;

    if (std.mem.eql(u8, name, "SDL_strlen")) {
        const address = arg(state, 0, direct_return_rip);
        if (api._guestCString(state, address)) |text| {
            regs.rax = text.len;
        } else {
            setError(api, state, "SDL_strlen received an invalid guest string");
            regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_wcslen")) {
        const address = arg(state, 0, direct_return_rip);
        regs.rax = api._guestWideCStringLength(state, address, 0x100000) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_memcpy")) {
        const destination = arg(state, 0, direct_return_rip);
        const source = arg(state, 1, direct_return_rip);
        const length = arg(state, 2, direct_return_rip);
        const copied = length == 0 or state.copyGuestRange(destination, source, length);
        if (copied) {
            regs.rax = destination;
        } else {
            setError(api, state, "SDL_memcpy received an invalid guest memory range");
            regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_free")) {
        const allocation = arg(state, 0, direct_return_rip);
        if (allocation != 0 and !state.releaseGuestAllocation(allocation)) {
            setError(api, state, "SDL_free received a pointer not owned by Rosetta's guest heap");
        }
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_iconv_string")) {
        const destination_encoding = api._guestCString(state, arg(state, 0, direct_return_rip)) orelse "";
        const source_encoding = api._guestCString(state, arg(state, 1, direct_return_rip)) orelse "";
        const input = arg(state, 2, direct_return_rip);
        const input_bytes = arg(state, 3, direct_return_rip);
        const converted = convertString(api, state, destination_encoding, source_encoding, input, input_bytes);
        if (converted) |value| {
            regs.rax = value;
        } else {
            setError(api, state, "SDL_iconv_string could not convert the requested encoding");
            regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "SDL_Init") or std.mem.eql(u8, name, "SDL_InitSubSystem")) {
        // The video/window and timer/event portions are provided by Rosetta's
        // host bridge. Audio and controller open calls still report their own
        // normal SDL failure values if the game requests them.
        state.windows_sdl.error_message = 0;
        audio.initializeSubsystems(state, @truncate(arg(state, 0, direct_return_rip)));
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_GetBasePath")) {
        // The PE runner confines guest file access to this explicitly selected
        // working directory, which is the executable directory for the
        // standalone launch path. Return that root so SDL-based resource
        // lookups such as `data/tyrian.snd` go through the same confinement
        // boundary instead of being resolved against an unrelated host cwd.
        if (state.windows_host_working_directory) |root| {
            var normalized_root = root;
            while (normalized_root.len > 1 and normalized_root[normalized_root.len - 1] == '/') {
                normalized_root = normalized_root[0 .. normalized_root.len - 1];
            }
            if (normalized_root.len == 0) {
                setError(api, state, "SDL_GetBasePath has no configured launch root");
                regs.rax = 0;
            } else {
                const needs_separator = normalized_root[normalized_root.len - 1] != '/';
                const length = std.math.add(usize, normalized_root.len, @intFromBool(needs_separator)) catch 0;
                const path = if (length != 0) state.allocator.alloc(u8, length) catch null else null;
                if (path) |storage| {
                    defer state.allocator.free(storage);
                    @memcpy(storage[0..normalized_root.len], normalized_root);
                    if (needs_separator) storage[normalized_root.len] = '/';
                    if (api._materializeGuestAnsi(state, storage)) |address| {
                        regs.rax = address;
                    } else {
                        setError(api, state, "SDL_GetBasePath could not allocate a guest path");
                        regs.rax = 0;
                    }
                } else {
                    setError(api, state, "SDL_GetBasePath could not allocate a host path buffer");
                    regs.rax = 0;
                }
            }
        } else {
            setError(api, state, "SDL_GetBasePath has no configured launch root");
            regs.rax = 0;
        }
        api._log.info("PE64 SDL base path: root='{s}' result=0x{x}", .{
            state.windows_host_working_directory orelse "",
            regs.rax,
        });
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_Quit")) {
        audio.shutdownSubsystems(api, state, std.math.maxInt(u32));
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_QuitSubSystem")) {
        audio.shutdownSubsystems(api, state, @truncate(arg(state, 0, direct_return_rip)));
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_SetMainReady")) {
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_CreateWindow")) {
        const width = api._normalizeWindowDimension(arg(state, 3, direct_return_rip), 1280);
        const height = api._normalizeWindowDimension(arg(state, 4, direct_return_rip), 720);
        const title_address = arg(state, 0, direct_return_rip);
        const title = api._guestCString(state, title_address) orelse "OpenTyrian (Rosetta)";
        const window_ready = state.windows_graphics.ensureWindow(@as(u64, width), @as(u64, height), title);
        const shown = window_ready and state.windows_graphics.showWindow();
        const native_visible = state.windows_graphics.snapshot().nativeWindowReady();
        if (shown and native_visible) {
            const window = api._nextHandle(state);
            state.windows_sdl.window = window;
            state.windows_sdl.window_title_len = @intCast(@min(title.len, state.windows_sdl.window_title.len));
            @memcpy(state.windows_sdl.window_title[0..state.windows_sdl.window_title_len], title[0..state.windows_sdl.window_title_len]);
            state.windows_sdl.error_message = 0;
            regs.rax = window;
        } else {
            setError(api, state, "SDL window creation did not reach a visible native window");
            regs.rax = 0;
        }
        api._log.info("PE64 SDL window: requested={d}x{d} ready={} shown={} native_visible={} handle=0x{x} title='{s}'", .{
            width,
            height,
            window_ready,
            shown,
            native_visible,
            regs.rax,
            title,
        });
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_DestroyWindow")) {
        const window = arg(state, 0, direct_return_rip);
        if (window == state.windows_sdl.window) state.windows_sdl.window = 0;
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_ShowWindow")) {
        if (state.windows_sdl.window != 0) _ = state.windows_graphics.showWindow();
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_SetWindowSize")) {
        const window = arg(state, 0, direct_return_rip);
        const width = api._normalizeWindowDimension(arg(state, 1, direct_return_rip), 1280);
        const height = api._normalizeWindowDimension(arg(state, 2, direct_return_rip), 720);
        if (window == state.windows_sdl.window and window != 0) {
            const title = state.windows_sdl.window_title[0..state.windows_sdl.window_title_len];
            if (!state.windows_graphics.ensureWindow(@as(u64, width), @as(u64, height), title)) {
                setError(api, state, "SDL window resize failed in the native window bridge");
            }
        }
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_GetWindowSize")) {
        const window = arg(state, 0, direct_return_rip);
        const width_out = arg(state, 1, direct_return_rip);
        const height_out = arg(state, 2, direct_return_rip);
        const valid_window = window != 0 and window == state.windows_sdl.window;
        if (width_out != 0 and state.guestMemory(width_out, 4) != null) {
            state.write32(width_out, if (valid_window) state.windows_graphics.window_width else 0);
        }
        if (height_out != 0 and state.guestMemory(height_out, 4) != null) {
            state.write32(height_out, if (valid_window) state.windows_graphics.window_height else 0);
        }
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_GetNumVideoDisplays")) {
        regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_GetWindowDisplayIndex")) {
        regs.rax = @bitCast(@as(i64, if (arg(state, 0, direct_return_rip) == state.windows_sdl.window and state.windows_sdl.window != 0) 0 else -1));
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_GetDisplayBounds")) {
        const rect = arg(state, 1, direct_return_rip);
        if (rect == 0 or state.guestMemory(rect, 16) == null) {
            setError(api, state, "SDL_GetDisplayBounds received an invalid rectangle pointer");
            regs.rax = @bitCast(@as(i64, -1));
        } else {
            state.write32(rect + 0, 0);
            state.write32(rect + 4, 0);
            state.write32(rect + 8, state.windows_graphics.window_width);
            state.write32(rect + 12, state.windows_graphics.window_height);
            regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_PumpEvents")) {
        // SDL's event pump is commonly called from every frame-loop poll.
        // Let the shared time/step cadence coalesce those calls while still
        // checking Rosette's already-buffered input on every SDL_PollEvent.
        _ = state.windows_graphics.pumpEventsAtStep(state.executed_steps, false);
        regs.rax = 0;
        if (audio.dispatchDueCallback(api, state, direct_return_rip)) return true;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_PollEvent")) {
        _ = state.windows_graphics.pumpEventsAtStep(state.executed_steps, false);
        const event = arg(state, 0, direct_return_rip);
        if (event == 0) {
            regs.rax = 0;
        } else if (state.guestMemory(event, sdl_event_bytes)) |bytes| {
            @memset(bytes, 0);
            if (state.windows_input_hooks.poll_keyboard_event) |poll| {
                const callback_type = @typeInfo(@TypeOf(poll)).pointer.child;
                const event_pointer_type = @typeInfo(callback_type).@"fn".params[1].type.?;
                const event_type = @typeInfo(event_pointer_type).pointer.child;
                var host_event: event_type = .{};
                if (poll(state.windows_input_hooks.context, &host_event) != 0) {
                    const timestamp: u32 = @truncate(if (@hasDecl(@TypeOf(state.*), "windowsGuestClockTicks"))
                        @divTrunc(state.windowsGuestClockTicks(), 1000)
                    else
                        @divTrunc(state.executed_steps, 1000));
                    writeSdlKeyboardEvent(bytes, host_event, timestamp, 1);
                    regs.rax = 1;
                } else {
                    regs.rax = 0;
                }
            } else {
                regs.rax = 0;
            }
        } else {
            setError(api, state, "SDL_PollEvent received an invalid guest event pointer");
            regs.rax = 0;
        }
        if (audio.dispatchDueCallback(api, state, direct_return_rip)) return true;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_GetTicks")) {
        regs.rax = if (@hasDecl(@TypeOf(state.*), "windowsGuestClockTicks"))
            @divTrunc(state.windowsGuestClockTicks(), 1000)
        else
            @divTrunc(state.executed_steps, 1000);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_GetError")) {
        if (state.windows_sdl.error_message == 0) setError(api, state, "");
        regs.rax = state.windows_sdl.error_message;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_Delay")) {
        // Do not sleep the host thread here: this is also the guest's UI
        // thread. Pump the AppKit queue and let the normal interpreter slice
        // provide cooperative progress instead.
        _ = state.windows_graphics.pumpEventsAtStep(state.executed_steps, true);
        regs.rax = 0;
        if (audio.dispatchDueCallback(api, state, direct_return_rip)) return true;
        finish(state, direct_return_rip);
        return true;
    }

    return false;
}

fn macVirtualKeyToSdlScancode(key_code: u16) u32 {
    return switch (key_code) {
        0 => 4,
        1 => 22,
        2 => 7,
        3 => 9,
        4 => 11,
        5 => 10,
        6 => 29,
        7 => 27,
        8 => 6,
        9 => 25,
        11 => 5,
        12 => 20,
        13 => 26,
        14 => 8,
        15 => 21,
        16 => 28,
        17 => 23,
        18 => 30,
        19 => 31,
        20 => 32,
        21 => 33,
        22 => 35,
        23 => 34,
        24 => 46,
        25 => 38,
        26 => 36,
        27 => 45,
        28 => 37,
        29 => 39,
        30 => 48,
        31 => 18,
        32 => 24,
        33 => 47,
        34 => 12,
        35 => 19,
        36 => 40,
        37 => 15,
        38 => 13,
        39 => 52,
        40 => 14,
        41 => 51,
        42 => 49,
        43 => 54,
        44 => 56,
        45 => 16,
        46 => 17,
        47 => 55,
        48 => 43,
        49 => 44,
        50 => 53,
        51 => 42,
        53 => 41,
        // Modifier keys use their SDL USB HID scancodes. The AppKit key
        // event's modifier flags are also carried separately in the event.
        54 => 231, // Right GUI / Command
        55 => 227, // Left GUI / Command
        56 => 225, // Left Shift
        57 => 57, // Caps Lock
        58 => 226, // Left Alt / Option
        59 => 224, // Left Ctrl
        60 => 229, // Right Shift
        61 => 230, // Right Alt / Option
        62 => 228, // Right Ctrl
        // Function keys.
        122 => 58,
        120 => 59,
        99 => 60,
        118 => 61,
        96 => 62,
        97 => 63,
        98 => 64,
        100 => 65,
        101 => 66,
        109 => 67,
        103 => 68,
        111 => 69,
        // Navigation and keypad. SDL follows USB HID usage IDs.
        115 => 74,
        116 => 75,
        117 => 76,
        119 => 77,
        121 => 78,
        123 => 80,
        124 => 79,
        125 => 81,
        126 => 82,
        65 => 99,
        67 => 85,
        69 => 87,
        71 => 83,
        75 => 84,
        76 => 88,
        78 => 86,
        81 => 103,
        82 => 98,
        83 => 89,
        84 => 90,
        85 => 91,
        86 => 92,
        87 => 93,
        88 => 94,
        89 => 95,
        91 => 96,
        92 => 97,
        else => 0,
    };
}

fn macVirtualKeyToSdlKeycode(key_code: u16, scancode: u32) u32 {
    return switch (key_code) {
        0 => 'a',
        1 => 's',
        2 => 'd',
        3 => 'f',
        4 => 'h',
        5 => 'g',
        6 => 'z',
        7 => 'x',
        8 => 'c',
        9 => 'v',
        11 => 'b',
        12 => 'q',
        13 => 'w',
        14 => 'e',
        15 => 'r',
        16 => 'y',
        17 => 't',
        18 => '1',
        19 => '2',
        20 => '3',
        21 => '4',
        22 => '6',
        23 => '5',
        24 => '=',
        25 => '9',
        26 => '7',
        27 => '-',
        28 => '8',
        29 => '0',
        30 => ']',
        31 => 'o',
        32 => 'u',
        33 => '[',
        34 => 'i',
        35 => 'p',
        36, 76 => 13,
        37 => 'l',
        38 => 'j',
        39 => '\'',
        40 => 'k',
        41 => ';',
        42 => '\\',
        43 => ',',
        44 => '/',
        45 => 'n',
        46 => 'm',
        47 => '.',
        48 => '\t',
        49 => ' ',
        50 => '`',
        51 => 8,
        53 => 27,
        else => sdl_scancode_mask | scancode,
    };
}

fn writeSdlKeyboardEvent(
    bytes: []u8,
    event: anytype,
    timestamp: u32,
    window_id: u32,
) void {
    std.debug.assert(bytes.len >= sdl_event_bytes);
    @memset(bytes[0..sdl_event_bytes], 0);
    const key_down = event.down != 0;
    const scancode = macVirtualKeyToSdlScancode(event.virtual_key_code);
    std.mem.writeInt(u32, bytes[0..4], if (key_down) 0x300 else 0x301, .little);
    std.mem.writeInt(u32, bytes[4..8], timestamp, .little);
    std.mem.writeInt(u32, bytes[8..12], window_id, .little);
    bytes[12] = @intFromBool(key_down);
    bytes[13] = @intFromBool(event.repeat != 0);
    std.mem.writeInt(u32, bytes[16..20], scancode, .little);
    std.mem.writeInt(u32, bytes[20..24], macVirtualKeyToSdlKeycode(event.virtual_key_code, scancode), .little);
    std.mem.writeInt(u16, bytes[24..26], event.modifiers, .little);
}

fn handleFormatting(comptime api: type, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const arg = api._arg;
    const finish = api._finish;
    const regs = &api._guestStateField(state, "regs").*;

    if (std.mem.eql(u8, name, "SDL_strlcpy")) {
        const destination = arg(state, 0, direct_return_rip);
        const source_address = arg(state, 1, direct_return_rip);
        const capacity = arg(state, 2, direct_return_rip);
        const source = api._guestCString(state, source_address) orelse {
            setError(api, state, "SDL_strlcpy received an invalid guest source string");
            regs.rax = std.math.maxInt(u64);
            finish(state, direct_return_rip);
            return true;
        };
        if (capacity != 0) {
            const length: usize = @intCast(@min(source.len, capacity - 1));
            const target = if (destination != 0) state.guestMemory(destination, @intCast(length + 1)) else null;
            if (target) |bytes| {
                @memcpy(bytes[0..length], source[0..length]);
                bytes[length] = 0;
            } else {
                setError(api, state, "SDL_strlcpy received an invalid guest destination buffer");
                regs.rax = std.math.maxInt(u64);
                finish(state, direct_return_rip);
                return true;
            }
        }
        regs.rax = source.len;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "SDL_vsnprintf")) {
        const destination = arg(state, 0, direct_return_rip);
        const capacity = arg(state, 1, direct_return_rip);
        const format_address = arg(state, 2, direct_return_rip);
        const varargs_address = arg(state, 3, direct_return_rip);
        const format = api._guestCString(state, format_address);
        if (format == null or (capacity != 0 and (destination == 0 or state.guestMemory(destination, capacity) == null))) {
            setError(api, state, "SDL_vsnprintf received an invalid guest format or destination buffer");
            regs.rax = @bitCast(@as(i64, -1));
            finish(state, direct_return_rip);
            return true;
        }

        var empty: [0]u8 = undefined;
        const output: []u8 = if (capacity != 0) state.guestMemory(destination, capacity).? else empty[0..];
        const writable = if (output.len == 0) output else output[0 .. output.len - 1];
        const formatted_length = sdl2_format.formatWindowsV(state, format.?, varargs_address, writable);
        if (formatted_length) |length| {
            if (output.len != 0) output[@min(length, output.len - 1)] = 0;
            regs.rax = length;
        } else {
            setError(api, state, "SDL_vsnprintf could not read the guest Win64 va_list");
            if (output.len != 0) output[0] = 0;
            regs.rax = @bitCast(@as(i64, -1));
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "SDL_LogMessageV")) {
        const category: u32 = @truncate(arg(state, 0, direct_return_rip));
        const priority: u32 = @truncate(arg(state, 1, direct_return_rip));
        const format_address = arg(state, 2, direct_return_rip);
        const varargs_address = arg(state, 3, direct_return_rip);
        if (api._guestCString(state, format_address)) |format| {
            var message: [2048]u8 = undefined;
            if (sdl2_format.formatWindowsV(state, format, varargs_address, &message)) |length| {
                api._log.info("PE64 SDL log category={d} priority={d}: {s}", .{ category, priority, message[0..@min(length, message.len)] });
            } else {
                api._log.warn("PE64 SDL log category={d} priority={d}: invalid guest Win64 va_list", .{ category, priority });
            }
        } else {
            api._log.warn("PE64 SDL log category={d} priority={d}: invalid guest format string", .{ category, priority });
        }
        regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    return false;
}

test "SDL keyboard events preserve macOS arrow and confirmation keys" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 82), macVirtualKeyToSdlScancode(126)); // Up
    try testing.expectEqual(@as(u32, 81), macVirtualKeyToSdlScancode(125)); // Down
    try testing.expectEqual(@as(u32, 80), macVirtualKeyToSdlScancode(123)); // Left
    try testing.expectEqual(@as(u32, 79), macVirtualKeyToSdlScancode(124)); // Right
    try testing.expectEqual(@as(u32, 0x40000052), macVirtualKeyToSdlKeycode(126, 82));
    try testing.expectEqual(@as(u32, 13), macVirtualKeyToSdlKeycode(36, 40)); // Return
    try testing.expectEqual(@as(u32, 32), macVirtualKeyToSdlKeycode(49, 44)); // Space
    try testing.expectEqual(@as(u32, 224), macVirtualKeyToSdlScancode(59)); // Left Ctrl
    try testing.expectEqual(@as(u32, 226), macVirtualKeyToSdlScancode(58)); // Left Alt / Option

    const key = .{ .virtual_key_code = 126, .down = 1, .repeat = 1, .modifiers = 0x0040 };
    var bytes = [_]u8{0xFF} ** sdl_event_bytes;
    writeSdlKeyboardEvent(&bytes, key, 1234, 1);
    try testing.expectEqual(@as(u32, 0x300), std.mem.readInt(u32, bytes[0..4], .little));
    try testing.expectEqual(@as(u32, 1234), std.mem.readInt(u32, bytes[4..8], .little));
    try testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, bytes[8..12], .little));
    try testing.expectEqual(@as(u8, 1), bytes[12]);
    try testing.expectEqual(@as(u8, 1), bytes[13]);
    try testing.expectEqual(@as(u32, 82), std.mem.readInt(u32, bytes[16..20], .little));
    try testing.expectEqual(@as(u32, 0x40000052), std.mem.readInt(u32, bytes[20..24], .little));
    try testing.expectEqual(@as(u16, 0x0040), std.mem.readInt(u16, bytes[24..26], .little));
    try testing.expectEqual(@as(u8, 0), bytes[14]);
    try testing.expectEqual(@as(u8, 0), bytes[15]);
    try testing.expectEqual(@as(u8, 0), bytes[26]);

    const key_up = .{ .virtual_key_code = 126, .down = 0, .repeat = 0, .modifiers = 0 };
    writeSdlKeyboardEvent(&bytes, key_up, 1235, 1);
    try testing.expectEqual(@as(u32, 0x301), std.mem.readInt(u32, bytes[0..4], .little));
    try testing.expectEqual(@as(u8, 0), bytes[12]);
    try testing.expectEqual(@as(u8, 0), bytes[13]);
}

fn setError(comptime api: type, state: anytype, message: []const u8) void {
    state.windows_sdl.error_message = api._materializeGuestAnsi(state, message) orelse 0;
}

fn convertString(comptime api: type, state: anytype, destination: []const u8, source: []const u8, input: u64, input_bytes: u64) ?u64 {
    if (input == 0 or input_bytes > std.math.maxInt(usize)) return null;

    if (std.ascii.eqlIgnoreCase(destination, "UTF-8") and std.ascii.eqlIgnoreCase(source, "UTF-16LE")) {
        const units = api._guestWideCStringLength(state, input, 0x100000) orelse return null;
        const input_length = std.math.mul(u64, @intCast(units), 2) catch return null;
        if (input_bytes < input_length or state.guestMemory(input, input_length + 2) == null) return null;
        const capacity = std.math.mul(usize, units, 4) catch return null;
        const buffer = state.allocator.alloc(u8, capacity + 1) catch return null;
        defer state.allocator.free(buffer);
        const text = api._guestWideToUtf8Buffer(state, input, buffer) orelse return null;
        return api._materializeGuestAnsi(state, text);
    }

    if (std.ascii.eqlIgnoreCase(destination, "UTF-16LE") and std.ascii.eqlIgnoreCase(source, "UTF-8")) {
        const source_bytes = state.guestMemory(input, input_bytes) orelse return null;
        if (std.mem.indexOfScalar(u8, source_bytes, 0) != null) return null;
        const text = source_bytes;
        if (!std.unicode.utf8ValidateSlice(text)) return null;
        return api._materializeGuestWide(state, text);
    }

    return null;
}

test "SDL2 import inventory is exact and distinguishes implemented from deferred exports" {
    try std.testing.expectEqual(Support.implemented, classify("sdl2.DLL", "SDL_CreateWindow").?);
    try std.testing.expectEqual(Support.implemented, classify("SDL2.dll", "SDL_GetBasePath").?);
    try std.testing.expectEqual(Support.implemented, classify("SDL2.dll", "SDL_RenderCopy").?);
    try std.testing.expectEqual(Support.implemented, classify("SDL2.dll", "SDL_OpenAudioDevice").?);
    try std.testing.expectEqual(Support.implemented, classify("SDL2.dll", "SDL_CloseAudioDevice").?);
    try std.testing.expectEqual(Support.deferred, classify("SDL2_net.dll", "SDLNet_UDP_Open").?);
    try std.testing.expect(classify("SDL2.dll", "SDL_MissingRosettaProbe") == null);
    try std.testing.expect(classify("kernel32.dll", "SDL_CreateWindow") == null);
}
