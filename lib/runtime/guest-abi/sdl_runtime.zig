//! SDL2 ABI and cooperative device runtime for interpreted Mach-O guests.
//!
//! An x86-64 guest cannot call an arm64 SDL framework function directly. This
//! module therefore owns the SDL boundary explicitly: subsystem lifetime,
//! event-watch registration, and a generation-checked virtual audio device.
//! The audio device is a clocked null sink. It invokes the guest's real SDL
//! callback at the requested cadence, so Xenia drains its own audio queue and
//! releases its own semaphore, but it never claims that audio reached native
//! hardware. Each callback owns a dedicated guest stack, matching SDL's
//! separate audio-thread contract and preventing a suspended audio callback
//! from pinning or overwriting the GTK/UI callback stack. A future CoreAudio
//! backend can replace the sink without changing the guest ABI or its
//! ownership rules.

const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

pub const compatibility_version = [3]u8{ 2, 0, 12 };
pub const audio_callback_handle_base: u64 = 0xFFFF_F910_0000_0000;

const max_audio_devices = 8;
const max_event_watches = 16;
const audio_spec_size = 32;
const audio_callback_stack_size: u32 = 256 * 1024;
const audio_f32_lsb: u16 = 0x8120;
const sdl_init_audio: u32 = 0x0000_0010;
const sdl_mix_max_volume: u32 = 128;

pub const Resolution = union(enum) {
    handled: u64,
    handled_void,
};

const AudioSpec = struct {
    frequency: i32,
    format: u16,
    channels: u8,
    silence: u8,
    samples: u16,
    padding: u16,
    size: u32,
    callback: u64,
    userdata: u64,

    fn read(bytes: []const u8) AudioSpec {
        return .{
            .frequency = @bitCast(std.mem.readInt(u32, bytes[0..4], .little)),
            .format = std.mem.readInt(u16, bytes[4..6], .little),
            .channels = bytes[6],
            .silence = bytes[7],
            .samples = std.mem.readInt(u16, bytes[8..10], .little),
            .padding = std.mem.readInt(u16, bytes[10..12], .little),
            .size = std.mem.readInt(u32, bytes[12..16], .little),
            .callback = std.mem.readInt(u64, bytes[16..24], .little),
            .userdata = std.mem.readInt(u64, bytes[24..32], .little),
        };
    }

    fn write(self: AudioSpec, bytes: []u8) void {
        std.mem.writeInt(u32, bytes[0..4], @bitCast(self.frequency), .little);
        std.mem.writeInt(u16, bytes[4..6], self.format, .little);
        bytes[6] = self.channels;
        bytes[7] = self.silence;
        std.mem.writeInt(u16, bytes[8..10], self.samples, .little);
        std.mem.writeInt(u16, bytes[10..12], self.padding, .little);
        std.mem.writeInt(u32, bytes[12..16], self.size, .little);
        std.mem.writeInt(u64, bytes[16..24], self.callback, .little);
        std.mem.writeInt(u64, bytes[24..32], self.userdata, .little);
    }
};

const AudioDevice = struct {
    active: bool = false,
    paused: bool = true,
    closing_after_callback: bool = false,
    generation: u16 = 1,
    id: u32 = 0,
    spec: AudioSpec = std.mem.zeroes(AudioSpec),
    stream_address: u64 = 0,
    stream_size: u32 = 0,
    callback_stack_address: u64 = 0,
    callback_stack_size: u32 = 0,
    next_callback_ns: u64 = 0,
    callback_dispatches: u64 = 0,
    callback_completions: u64 = 0,
};

const EventWatch = struct {
    active: bool = false,
    callback: u64 = 0,
    userdata: u64 = 0,
};

pub const Runtime = struct {
    calls: u64 = 0,
    version_queries: u64 = 0,
    hint_updates: u64 = 0,
    hint_rejections: u64 = 0,
    log_callback_updates: u64 = 0,
    log_priority_updates: u64 = 0,
    subsystem_initializations: u64 = 0,
    subsystem_quits: u64 = 0,
    initialized_mask: u32 = 0,
    subsystem_refs: [32]u16 = [_]u16{0} ** 32,
    audio_open_attempts: u64 = 0,
    audio_open_successes: u64 = 0,
    audio_open_rejections: u64 = 0,
    audio_pause_updates: u64 = 0,
    audio_close_requests: u64 = 0,
    audio_subsystem_closes: u64 = 0,
    audio_invalid_handles: u64 = 0,
    audio_callbacks_dispatched: u64 = 0,
    audio_callbacks_completed: u64 = 0,
    audio_callback_dispatch_failures: u64 = 0,
    event_watch_adds: u64 = 0,
    event_watch_removes: u64 = 0,
    event_pumps: u64 = 0,
    mapping_updates: u64 = 0,
    log_callback: u64 = 0,
    log_userdata: u64 = 0,
    log_priority: i32 = 0,
    last_error: [192]u8 = [_]u8{0} ** 192,
    last_error_length: usize = 0,
    last_error_guest_address: u64 = 0,
    devices: [max_audio_devices]AudioDevice = [_]AudioDevice{.{}} ** max_audio_devices,
    event_watches: [max_event_watches]EventWatch = [_]EventWatch{.{}} ** max_event_watches,
    active_callback_slot: ?usize = null,

    pub fn dispatch(self: *Runtime, state: anytype, symbol: []const u8) ?Resolution {
        if (symbolMatches(symbol, "SDL_GetVersion")) {
            self.calls +|= 1;
            self.version_queries +|= 1;
            const output = state.guestMemory(state.regs.rdi, compatibility_version.len) orelse
                return .handled_void;
            @memcpy(output, &compatibility_version);
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_InitSubSystem")) {
            self.calls +|= 1;
            self.subsystem_initializations +|= 1;
            const requested: u32 = @truncate(state.regs.rdi);
            for (0..32) |bit_index| {
                const bit = @as(u32, 1) << @intCast(bit_index);
                if (requested & bit == 0) continue;
                self.subsystem_refs[bit_index] +|= 1;
                self.initialized_mask |= bit;
            }
            return .{ .handled = 0 };
        }

        if (symbolMatches(symbol, "SDL_WasInit")) {
            self.calls +|= 1;
            const requested: u32 = @truncate(state.regs.rdi);
            return .{ .handled = if (requested == 0) self.initialized_mask else self.initialized_mask & requested };
        }

        if (symbolMatches(symbol, "SDL_QuitSubSystem")) {
            self.calls +|= 1;
            self.subsystem_quits +|= 1;
            const requested: u32 = @truncate(state.regs.rdi);
            for (0..32) |bit_index| {
                const bit = @as(u32, 1) << @intCast(bit_index);
                if (requested & bit == 0 or self.subsystem_refs[bit_index] == 0) continue;
                self.subsystem_refs[bit_index] -= 1;
                if (self.subsystem_refs[bit_index] == 0) self.initialized_mask &= ~bit;
            }
            if (requested & sdl_init_audio != 0 and self.initialized_mask & sdl_init_audio == 0) {
                for (&self.devices, 0..) |*device, slot| {
                    if (!device.active) continue;
                    self.closeAudioDevice(device, slot);
                    self.audio_subsystem_closes +|= 1;
                }
            }
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_OpenAudioDevice")) {
            self.calls +|= 1;
            return .{ .handled = self.openAudioDevice(state) };
        }

        if (symbolMatches(symbol, "SDL_PauseAudioDevice")) {
            self.calls +|= 1;
            self.audio_pause_updates +|= 1;
            const device_id: u32 = @truncate(state.regs.rdi);
            const paused = state.regs.rsi != 0;
            const device = self.deviceForId(device_id) orelse {
                self.audio_invalid_handles +|= 1;
                self.setError("SDL_PauseAudioDevice received a stale or foreign device id");
                return .handled_void;
            };
            device.paused = paused;
            if (!paused) device.next_callback_ns = state.guest_time.now();
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_CloseAudioDevice")) {
            self.calls +|= 1;
            self.audio_close_requests +|= 1;
            const device_id: u32 = @truncate(state.regs.rdi);
            const device = self.deviceForId(device_id) orelse {
                self.audio_invalid_handles +|= 1;
                self.setError("SDL_CloseAudioDevice received a stale or foreign device id");
                return .handled_void;
            };
            const slot: usize = @intCast((device_id & 0xFF) - 1);
            self.closeAudioDevice(device, slot);
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_AddEventWatch")) {
            self.calls +|= 1;
            self.event_watch_adds +|= 1;
            const callback = state.regs.rdi;
            const userdata = state.regs.rsi;
            if (callback != 0 and state.isExecutableAddress(callback)) {
                for (&self.event_watches) |*watch| {
                    if (watch.active) continue;
                    watch.* = .{ .active = true, .callback = callback, .userdata = userdata };
                    break;
                }
            }
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_DelEventWatch")) {
            self.calls +|= 1;
            self.event_watch_removes +|= 1;
            for (&self.event_watches) |*watch| {
                if (!watch.active or watch.callback != state.regs.rdi or watch.userdata != state.regs.rsi) continue;
                watch.* = .{};
            }
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_PumpEvents")) {
            self.calls +|= 1;
            self.event_pumps +|= 1;
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_NumJoysticks")) {
            self.calls +|= 1;
            // The current backend has no native controller event source. A
            // clean zero-device result is truthful and lets Xenia retain its
            // keyboard/input fallbacks without manufacturing a controller.
            return .{ .handled = 0 };
        }

        if (symbolMatches(symbol, "SDL_GameControllerAddMapping")) {
            self.calls +|= 1;
            _ = state.guestCString(state.regs.rdi, 4096) orelse return .{ .handled = @as(u32, @bitCast(@as(i32, -1))) };
            self.mapping_updates +|= 1;
            return .{ .handled = 1 };
        }

        if (symbolMatches(symbol, "SDL_GetError")) {
            self.calls +|= 1;
            return .{ .handled = self.errorAddress(state) };
        }

        if (symbolMatches(symbol, "SDL_ClearError")) {
            self.calls +|= 1;
            self.last_error_length = 0;
            self.last_error[0] = 0;
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_MixAudioFormat")) {
            self.calls +|= 1;
            self.mixAudioFormat(state);
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_SetHintWithPriority")) {
            self.calls +|= 1;
            self.hint_updates +|= 1;
            _ = state.guestCString(state.regs.rdi, 256) orelse {
                self.hint_rejections +|= 1;
                return .{ .handled = 0 };
            };
            _ = state.guestCString(state.regs.rsi, 1024) orelse {
                self.hint_rejections +|= 1;
                return .{ .handled = 0 };
            };
            return .{ .handled = 1 };
        }

        if (symbolMatches(symbol, "SDL_LogSetOutputFunction")) {
            self.calls +|= 1;
            self.log_callback_updates +|= 1;
            self.log_callback = state.regs.rdi;
            self.log_userdata = state.regs.rsi;
            return .handled_void;
        }

        if (symbolMatches(symbol, "SDL_LogSetAllPriority")) {
            self.calls +|= 1;
            self.log_priority_updates +|= 1;
            self.log_priority = @bitCast(@as(u32, @truncate(state.regs.rdi)));
            return .handled_void;
        }

        return null;
    }

    fn openAudioDevice(self: *Runtime, state: anytype) u64 {
        self.audio_open_attempts +|= 1;
        if (self.initialized_mask & sdl_init_audio == 0)
            return self.rejectAudioOpen("SDL_OpenAudioDevice requires SDL_INIT_AUDIO ownership");
        const desired_bytes = state.guestMemory(state.regs.rdx, audio_spec_size) orelse
            return self.rejectAudioOpen("SDL_OpenAudioDevice desired SDL_AudioSpec is unreadable");
        var spec = AudioSpec.read(desired_bytes);
        if (spec.frequency < 8000 or spec.frequency > 192000)
            return self.rejectAudioOpen("SDL_OpenAudioDevice frequency is outside 8-192 kHz");
        if (spec.format != audio_f32_lsb)
            return self.rejectAudioOpen("Rosette SDL audio currently requires AUDIO_F32LSB");
        if (spec.channels != 2 and spec.channels != 6)
            return self.rejectAudioOpen("Rosette SDL audio currently supports stereo or 5.1");
        if (spec.samples == 0 or spec.samples > 8192)
            return self.rejectAudioOpen("SDL_OpenAudioDevice sample count is invalid");
        if (spec.callback == 0 or !state.isExecutableAddress(spec.callback))
            return self.rejectAudioOpen("SDL_OpenAudioDevice callback is null or non-executable");

        const stream_size_u64 = @as(u64, spec.samples) * @as(u64, spec.channels) * @sizeOf(f32);
        if (stream_size_u64 > std.math.maxInt(u32))
            return self.rejectAudioOpen("SDL_OpenAudioDevice stream size overflowed");
        spec.silence = 0;
        spec.padding = 0;
        spec.size = @intCast(stream_size_u64);

        for (&self.devices, 0..) |*device, slot| {
            if (device.active or self.active_callback_slot == slot) continue;
            const stream_address = if (device.stream_address != 0 and device.stream_size >= spec.size)
                device.stream_address
            else
                state.guestAlloc(spec.size, 16) orelse return self.rejectAudioOpen("Rosette could not allocate the SDL audio callback buffer");
            const callback_stack_address = if (device.callback_stack_address != 0 and device.callback_stack_size >= audio_callback_stack_size)
                device.callback_stack_address
            else
                state.guestAlloc(audio_callback_stack_size, 16) orelse return self.rejectAudioOpen("Rosette could not allocate the SDL audio callback stack");
            const generation = if (device.generation == 0) 1 else device.generation;
            const device_id = encodeDeviceId(slot, generation);
            device.* = .{
                .active = true,
                .paused = true,
                .closing_after_callback = false,
                .generation = generation,
                .id = device_id,
                .spec = spec,
                .stream_address = stream_address,
                .stream_size = spec.size,
                .callback_stack_address = callback_stack_address,
                .callback_stack_size = audio_callback_stack_size,
            };
            if (state.regs.rcx != 0) {
                const obtained = state.guestMemory(state.regs.rcx, audio_spec_size) orelse {
                    device.active = false;
                    return self.rejectAudioOpen("SDL_OpenAudioDevice obtained SDL_AudioSpec is unwritable");
                };
                spec.write(obtained);
            }
            self.last_error_length = 0;
            self.last_error[0] = 0;
            self.audio_open_successes +|= 1;
            machoCapturePrint(
                "macho-processor: SDL2 virtual audio opened: device={d} generation={d} backend=clocked_null_sink frequency={d} channels={d} samples={d} bytes={d} callback=0x{x} userdata=0x{x} callback_stack=0x{x}..0x{x}; queue timing and guest callback are real, audible host output is not yet implemented\n",
                .{ device_id, generation, spec.frequency, spec.channels, spec.samples, spec.size, spec.callback, spec.userdata, callback_stack_address, callback_stack_address + audio_callback_stack_size },
            );
            return device_id;
        }
        return self.rejectAudioOpen("Rosette SDL audio device table is full");
    }

    fn rejectAudioOpen(self: *Runtime, reason: []const u8) u64 {
        self.audio_open_rejections +|= 1;
        self.setError(reason);
        return 0;
    }

    fn closeAudioDevice(self: *Runtime, device: *AudioDevice, slot: usize) void {
        device.paused = true;
        if (self.active_callback_slot == slot) {
            // The callback owns its stream and saved guest context until its
            // return sentinel is reached. Defer generation retirement rather
            // than invalidating an in-flight device beneath guest code.
            device.closing_after_callback = true;
            return;
        }
        device.active = false;
        device.closing_after_callback = false;
        device.generation +%= 1;
        if (device.generation == 0) device.generation = 1;
    }

    fn deviceForId(self: *Runtime, device_id: u32) ?*AudioDevice {
        if (device_id == 0) return null;
        const slot_field = device_id & 0xFF;
        if (slot_field == 0) return null;
        const slot = slot_field - 1;
        if (slot >= self.devices.len) return null;
        const device = &self.devices[slot];
        const generation: u16 = @truncate(device_id >> 8);
        if (!device.active or device.id != device_id or device.generation != generation) return null;
        return device;
    }

    pub fn isAudioCallbackHandle(self: *const Runtime, handle: u64) bool {
        _ = self;
        return handle >= audio_callback_handle_base and handle < audio_callback_handle_base + max_audio_devices;
    }

    /// Whether an audio callback is still in flight on its dedicated stack.
    pub fn audioCallbackInFlight(self: *const Runtime) bool {
        return self.active_callback_slot != null;
    }

    /// Handle of the in-flight audio callback, or 0 when none owns the stack.
    pub fn audioCallbackHandle(self: *const Runtime) u64 {
        const slot = self.active_callback_slot orelse return 0;
        return audio_callback_handle_base + slot;
    }

    pub fn dispatchDueAudioCallback(self: *Runtime, state: anytype, return_sentinel: u64) bool {
        if (self.active_callback_slot != null or state.cooperative_ui_context == null or
            state.active_guest_thread == 0 or
            state.isSyntheticCallbackHandle(state.active_guest_thread)) return false;

        const now = state.guest_time.now();
        for (&self.devices, 0..) |*device, slot| {
            if (!device.active or device.paused or device.next_callback_ns > now) continue;
            if (!state.isExecutableAddress(device.spec.callback)) {
                self.audio_callback_dispatch_failures +|= 1;
                device.paused = true;
                self.setError("SDL audio callback became non-executable; device was paused");
                return false;
            }
            if (!state.saveActiveGuestThread("SDL audio callback dispatch")) {
                self.audio_callback_dispatch_failures +|= 1;
                return false;
            }
            const context = state.cooperative_ui_context.?;
            state.regs = context.regs;
            state.xmm = context.xmm;
            state.ymm_hi = context.ymm_hi;
            state.x87 = context.x87;
            // This is a new synthetic guest callback context. It inherits the
            // process-wide dispositions, but never the interrupted worker's
            // active signal-handler stack.
            state.resetActiveGuestSignalState();
            state.regs.rip = device.spec.callback;
            state.regs.rdi = device.spec.userdata;
            state.regs.rsi = device.stream_address;
            state.regs.rdx = device.spec.size;
            state.regs.rsp = (device.callback_stack_address + device.callback_stack_size) & ~@as(u64, 0xF);
            state.push(return_sentinel);
            state.active_guest_thread = audio_callback_handle_base + slot;
            state.noteSyntheticStackEntry(state.active_guest_thread);
            self.active_callback_slot = slot;
            device.callback_dispatches +|= 1;
            self.audio_callbacks_dispatched +|= 1;
            const frequency: u64 = @intCast(device.spec.frequency);
            const period_ns = @max(@as(u64, 1), @as(u64, device.spec.samples) * std.time.ns_per_s / frequency);
            device.next_callback_ns = now +| period_ns;
            state.cooperative_thread_switches +|= 1;
            if (self.audio_callbacks_dispatched <= 4 or self.audio_callbacks_dispatched % 1000 == 0) {
                machoCapturePrint(
                    "macho-processor: SDL2 audio callback dispatch #{d}: device={d} callback=0x{x} userdata=0x{x} stream=0x{x} bytes={d} now_ns={d} next_ns={d}\n",
                    .{ self.audio_callbacks_dispatched, device.id, device.spec.callback, device.spec.userdata, device.stream_address, device.spec.size, now, device.next_callback_ns },
                );
            }
            return true;
        }
        return false;
    }

    pub fn finishAudioCallback(self: *Runtime, handle: u64) bool {
        if (!self.isAudioCallbackHandle(handle)) return false;
        const slot = self.active_callback_slot orelse return false;
        self.active_callback_slot = null;
        self.devices[slot].callback_completions +|= 1;
        self.audio_callbacks_completed +|= 1;
        if (self.devices[slot].closing_after_callback) {
            self.closeAudioDevice(&self.devices[slot], slot);
        }
        return true;
    }

    fn mixAudioFormat(self: *Runtime, state: anytype) void {
        const format: u16 = @truncate(state.regs.rdx);
        const length: usize = @intCast(@min(state.regs.rcx, @as(u64, 64 * 1024 * 1024)));
        const volume: u32 = @truncate(state.regs.r8);
        if (format != audio_f32_lsb or length % @sizeOf(f32) != 0) {
            self.setError("SDL_MixAudioFormat received an unsupported format or length");
            return;
        }
        const destination = state.guestMemory(state.regs.rdi, length) orelse return;
        const source = state.guestMemory(state.regs.rsi, length) orelse return;
        const gain = @as(f32, @floatFromInt(@min(volume, sdl_mix_max_volume))) / @as(f32, @floatFromInt(sdl_mix_max_volume));
        var offset: usize = 0;
        while (offset < length) : (offset += 4) {
            const dst: f32 = @bitCast(std.mem.readInt(u32, destination[offset..][0..4], .little));
            const src: f32 = @bitCast(std.mem.readInt(u32, source[offset..][0..4], .little));
            const mixed = std.math.clamp(dst + src * gain, -1.0, 1.0);
            std.mem.writeInt(u32, destination[offset..][0..4], @bitCast(mixed), .little);
        }
    }

    fn setError(self: *Runtime, message: []const u8) void {
        const length = @min(message.len, self.last_error.len - 1);
        @memcpy(self.last_error[0..length], message[0..length]);
        self.last_error[length] = 0;
        self.last_error_length = length;
    }

    fn errorAddress(self: *Runtime, state: anytype) u64 {
        if (self.last_error_guest_address == 0) {
            self.last_error_guest_address = state.guestAlloc(self.last_error.len, 1) orelse return 0;
        }
        const output = state.guestMemory(self.last_error_guest_address, self.last_error_length + 1) orelse return 0;
        @memcpy(output, self.last_error[0 .. self.last_error_length + 1]);
        return self.last_error_guest_address;
    }

    pub fn logSummary(self: *const Runtime) void {
        if (self.calls == 0 and self.audio_callbacks_dispatched == 0) return;
        var active_devices: usize = 0;
        var active_watches: usize = 0;
        for (self.devices) |device| active_devices += @intFromBool(device.active);
        for (self.event_watches) |watch| active_watches += @intFromBool(watch.active);
        machoCapturePrint(
            "macho-processor: SDL2 guest ABI: version={d}.{d}.{d} calls={d} subsystems(init/quit/mask)={d}/{d}/0x{x} audio(open/ok/reject/close/subsystem_close/invalid)={d}/{d}/{d}/{d}/{d}/{d} devices={d} callbacks(dispatch/complete/fail/inflight_handle)={d}/{d}/{d}/0x{x} event_watches(add/remove/active/pumps)={d}/{d}/{d}/{d} hints={d} rejected={d} mappings={d}; backend=clocked_null_sink (guest timing and ownership active, native audible output unavailable)\n",
            .{ compatibility_version[0], compatibility_version[1], compatibility_version[2], self.calls, self.subsystem_initializations, self.subsystem_quits, self.initialized_mask, self.audio_open_attempts, self.audio_open_successes, self.audio_open_rejections, self.audio_close_requests, self.audio_subsystem_closes, self.audio_invalid_handles, active_devices, self.audio_callbacks_dispatched, self.audio_callbacks_completed, self.audio_callback_dispatch_failures, self.audioCallbackHandle(), self.event_watch_adds, self.event_watch_removes, active_watches, self.event_pumps, self.hint_updates, self.hint_rejections, self.mapping_updates },
        );
    }
};

fn encodeDeviceId(slot: usize, generation: u16) u32 {
    return (@as(u32, generation) << 8) | @as(u32, @intCast(slot + 1));
}

fn symbolMatches(symbol: []const u8, canonical: []const u8) bool {
    if (std.mem.eql(u8, symbol, canonical)) return true;
    return symbol.len == canonical.len + 1 and symbol[0] == '_' and
        std.mem.eql(u8, symbol[1..], canonical);
}

const TestGuestTime = struct {
    value: u64 = 0,
    fn now(self: *const TestGuestTime) u64 {
        return self.value;
    }
};

const TestState = struct {
    const Registers = struct {
        rdi: u64 = 0,
        rsi: u64 = 0,
        rdx: u64 = 0,
        rcx: u64 = 0,
        r8: u64 = 0,
        rip: u64 = 0,
        rsp: u64 = 0,
    };

    const CooperativeContext = struct {
        regs: Registers = .{},
        xmm: u64 = 0,
        ymm_hi: u64 = 0,
        x87: u64 = 0,
    };

    regs: Registers = .{},
    memory: [384 * 1024]u8 = [_]u8{0} ** (384 * 1024),
    alloc_cursor: u64 = 2048,
    guest_time: TestGuestTime = .{},
    xmm: u64 = 0,
    ymm_hi: u64 = 0,
    x87: u64 = 0,
    cooperative_ui_context: ?CooperativeContext = null,
    active_guest_thread: u64 = 0,
    active_idle_source: u64 = 0,
    cooperative_thread_switches: u64 = 0,
    saved_threads: u64 = 0,
    pushed: u64 = 0,
    synthetic_stack_entry_rsp: u64 = 0,
    synthetic_stack_entry_handle: u64 = 0,
    synthetic_stack_dispatches: u64 = 0,

    fn saveActiveGuestThread(self: *TestState, reason: []const u8) bool {
        _ = reason;
        self.saved_threads += 1;
        self.active_guest_thread = 0;
        return true;
    }

    fn push(self: *TestState, value: u64) void {
        self.regs.rsp -= 8;
        self.pushed = value;
    }

    fn resetActiveGuestSignalState(self: *TestState) void {
        _ = self;
    }

    fn isSyntheticCallbackHandle(self: *const TestState, handle: u64) bool {
        _ = self;
        return handle >= audio_callback_handle_base;
    }

    fn noteSyntheticStackEntry(self: *TestState, handle: u64) void {
        self.synthetic_stack_entry_rsp = self.regs.rsp;
        self.synthetic_stack_entry_handle = handle;
        self.synthetic_stack_dispatches += 1;
    }

    fn guestMemory(self: *TestState, address: u64, length: u64) ?[]u8 {
        const start: usize = @intCast(address);
        const count: usize = @intCast(length);
        if (start > self.memory.len or count > self.memory.len - start) return null;
        return self.memory[start .. start + count];
    }

    fn guestCString(self: *TestState, address: u64, limit: usize) ?[]const u8 {
        const start: usize = @intCast(address);
        if (start >= self.memory.len) return null;
        const available = self.memory[start..@min(self.memory.len, start +| limit)];
        const end = std.mem.indexOfScalar(u8, available, 0) orelse return null;
        return available[0..end];
    }

    fn guestAlloc(self: *TestState, size: u64, alignment: u64) ?u64 {
        const address = std.mem.alignForward(u64, self.alloc_cursor, alignment);
        if (address +| size > self.memory.len) return null;
        self.alloc_cursor = address + size;
        return address;
    }

    fn isExecutableAddress(self: *const TestState, address: u64) bool {
        _ = self;
        return address >= 0x300 and address < 0x800;
    }
};

test "SDL compatibility version satisfies Xenia audio and input" {
    var runtime = Runtime{};
    var state = TestState{};
    state.regs.rdi = 8;
    try std.testing.expect(runtime.dispatch(&state, "_SDL_GetVersion") != null);
    try std.testing.expectEqualSlices(u8, &compatibility_version, state.memory[8..11]);
}

test "SDL subsystem reference counts do not lose a shared owner" {
    var runtime = Runtime{};
    var state = TestState{};
    state.regs.rdi = 0x10;
    _ = runtime.dispatch(&state, "SDL_InitSubSystem").?;
    _ = runtime.dispatch(&state, "SDL_InitSubSystem").?;
    _ = runtime.dispatch(&state, "SDL_QuitSubSystem").?;
    try std.testing.expectEqual(@as(u32, 0x10), runtime.initialized_mask);
    _ = runtime.dispatch(&state, "SDL_QuitSubSystem").?;
    try std.testing.expectEqual(@as(u32, 0), runtime.initialized_mask);
}

test "SDL audio devices copy the obtained spec and reject stale ids" {
    var runtime = Runtime{};
    var state = TestState{};
    state.regs.rdi = sdl_init_audio;
    _ = runtime.dispatch(&state, "SDL_InitSubSystem").?;
    const desired_address = 64;
    const obtained_address = 128;
    const desired = AudioSpec{
        .frequency = 48000,
        .format = audio_f32_lsb,
        .channels = 6,
        .silence = 0,
        .samples = 256,
        .padding = 0,
        .size = 0,
        .callback = 0x400,
        .userdata = 0x1234,
    };
    desired.write(state.memory[desired_address .. desired_address + audio_spec_size]);
    state.regs.rdx = desired_address;
    state.regs.rcx = obtained_address;
    const opened = runtime.dispatch(&state, "_SDL_OpenAudioDevice").?.handled;
    try std.testing.expect(opened != 0);
    const obtained = AudioSpec.read(state.memory[obtained_address .. obtained_address + audio_spec_size]);
    try std.testing.expectEqual(@as(u32, 6144), obtained.size);
    try std.testing.expectEqual(@as(u8, 6), obtained.channels);

    state.regs.rdi = opened;
    _ = runtime.dispatch(&state, "SDL_CloseAudioDevice").?;
    _ = runtime.dispatch(&state, "SDL_CloseAudioDevice").?;
    try std.testing.expectEqual(@as(u64, 1), runtime.audio_invalid_handles);
}

test "SDL audio open requires subsystem ownership and final quit retires devices" {
    var runtime = Runtime{};
    var state = TestState{};
    const desired_address = 64;
    const desired = AudioSpec{
        .frequency = 48000,
        .format = audio_f32_lsb,
        .channels = 2,
        .silence = 0,
        .samples = 128,
        .padding = 0,
        .size = 0,
        .callback = 0x400,
        .userdata = 0,
    };
    desired.write(state.memory[desired_address .. desired_address + audio_spec_size]);
    state.regs.rdx = desired_address;
    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&state, "SDL_OpenAudioDevice").?.handled);

    state.regs.rdi = sdl_init_audio;
    _ = runtime.dispatch(&state, "SDL_InitSubSystem").?;
    state.regs.rdx = desired_address;
    const device_id = runtime.dispatch(&state, "SDL_OpenAudioDevice").?.handled;
    try std.testing.expect(device_id != 0);
    state.regs.rdi = sdl_init_audio;
    _ = runtime.dispatch(&state, "SDL_QuitSubSystem").?;
    try std.testing.expectEqual(@as(u32, 0), runtime.initialized_mask & sdl_init_audio);
    try std.testing.expectEqual(@as(u64, 1), runtime.audio_subsystem_closes);
    try std.testing.expect(runtime.deviceForId(@truncate(device_id)) == null);
}

test "an audio callback owns a dedicated stack until its return sentinel" {
    var runtime = Runtime{};
    var state = TestState{};
    state.regs.rdi = sdl_init_audio;
    _ = runtime.dispatch(&state, "SDL_InitSubSystem").?;

    const desired_address = 64;
    const desired = AudioSpec{
        .frequency = 48000,
        .format = audio_f32_lsb,
        .channels = 2,
        .silence = 0,
        .samples = 128,
        .padding = 0,
        .size = 0,
        .callback = 0x400,
        .userdata = 0x1234,
    };
    desired.write(state.memory[desired_address .. desired_address + audio_spec_size]);
    state.regs.rdx = desired_address;
    state.regs.rcx = 0;
    const opened = runtime.dispatch(&state, "_SDL_OpenAudioDevice").?.handled;
    try std.testing.expect(opened != 0);
    state.regs.rdi = opened;
    state.regs.rsi = 0;
    _ = runtime.dispatch(&state, "SDL_PauseAudioDevice").?;

    try std.testing.expect(!runtime.audioCallbackInFlight());
    try std.testing.expectEqual(@as(u64, 0), runtime.audioCallbackHandle());

    state.cooperative_ui_context = .{ .regs = .{ .rsp = 0x1000 } };
    state.active_guest_thread = 0x7FFF_2000;
    // A suspended GTK callback may retain its own UI stack while the ordinary
    // worker dispatches audio on the device's independent stack.
    state.active_idle_source = 7;
    const sentinel: u64 = 0xDEAD_BEEF;
    try std.testing.expect(runtime.dispatchDueAudioCallback(&state, sentinel));

    // Entered on its dedicated audio stack, with the sentinel pushed and the
    // entry window recorded for crash attribution.
    try std.testing.expectEqual(sentinel, state.pushed);
    try std.testing.expectEqual(
        runtime.devices[0].callback_stack_address + runtime.devices[0].callback_stack_size - 8,
        state.regs.rsp,
    );
    try std.testing.expectEqual(state.active_guest_thread, state.synthetic_stack_entry_handle);
    try std.testing.expectEqual(@as(u64, 1), state.synthetic_stack_dispatches);

    // Ownership spans dispatch to sentinel. A suspension clears the active
    // context but must not release the audio device: its frames are still live
    // on its dedicated stack.
    try std.testing.expect(runtime.audioCallbackInFlight());
    try std.testing.expectEqual(state.synthetic_stack_entry_handle, runtime.audioCallbackHandle());
    _ = state.saveActiveGuestThread("suspended mid-callback");
    try std.testing.expectEqual(@as(u64, 0), state.active_guest_thread);
    try std.testing.expect(runtime.audioCallbackInFlight());

    // A second dispatch is refused while the first still owns the stack.
    try std.testing.expect(!runtime.dispatchDueAudioCallback(&state, sentinel));
    try std.testing.expectEqual(@as(u64, 1), state.synthetic_stack_dispatches);

    try std.testing.expect(runtime.finishAudioCallback(runtime.audioCallbackHandle()));
    try std.testing.expect(!runtime.audioCallbackInFlight());
    try std.testing.expectEqual(@as(u64, 0), runtime.audioCallbackHandle());
}

test "SDL hint success requires two complete guest strings" {
    var runtime = Runtime{};
    var state = TestState{};
    @memcpy(state.memory[8..17], "hint-name");
    state.memory[17] = 0;
    @memcpy(state.memory[32..37], "value");
    state.memory[37] = 0;
    state.regs.rdi = 8;
    state.regs.rsi = 32;

    const valid = runtime.dispatch(&state, "SDL_SetHintWithPriority").?;
    try std.testing.expectEqual(@as(u64, 1), valid.handled);

    state.regs.rsi = state.memory.len - 1;
    state.memory[state.memory.len - 1] = 'x';
    const invalid = runtime.dispatch(&state, "_SDL_SetHintWithPriority").?;
    try std.testing.expectEqual(@as(u64, 0), invalid.handled);
    try std.testing.expectEqual(@as(u64, 1), runtime.hint_rejections);
}
