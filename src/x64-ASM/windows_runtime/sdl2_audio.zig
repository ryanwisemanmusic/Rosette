//! SDL2 audio-format conversion and guest callback dispatch for PE guests.
//!
//! Guest callbacks run on the executor that pumps SDL events. Their PCM is
//! copied to the same native output bridge used by the WinMM route; no guest
//! callback or guest pointer is passed to host SDL/CoreAudio.

const std = @import("std");

const AUDIO_U8: u16 = 0x0008;
const AUDIO_S8: u16 = 0x8008;
const AUDIO_U16LSB: u16 = 0x0010;
const AUDIO_S16LSB: u16 = 0x8010;
const AUDIO_U16MSB: u16 = 0x1010;
const AUDIO_S16MSB: u16 = 0x9010;
const AUDIO_S32LSB: u16 = 0x8020;
const AUDIO_F32LSB: u16 = 0x8120;
const SDL_INIT_AUDIO: u32 = 0x0000_0010;
const MAX_AUDIO_CVT_BYTES: u64 = 64 * 1024 * 1024;
const SDL_AUDIO_CVT_BYTES: u64 = 136;
const SDL_AUDIO_SPEC_BYTES: u64 = 32;

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

const Conversion = struct {
    src_format: u16,
    dst_format: u16,
    src_channels: u8,
    dst_channels: u8,
    src_rate: u32,
    dst_rate: u32,
};

pub fn handle(comptime api: type, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (std.mem.eql(u8, name, "SDL_OpenAudioDevice")) {
        openAudioDevice(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_PauseAudioDevice") or
        std.mem.eql(u8, name, "SDL_LockAudioDevice") or
        std.mem.eql(u8, name, "SDL_UnlockAudioDevice"))
    {
        audioDeviceControl(api, state, name, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_CloseAudioDevice")) {
        closeAudioDevice(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_BuildAudioCVT")) {
        buildAudioCvt(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_ConvertAudio")) {
        convertAudio(api, state, direct_return_rip);
        return true;
    }
    return false;
}

pub fn initializeSubsystems(state: anytype, flags: u32) void {
    state.windows_sdl.subsystems |= flags;
}

pub fn shutdownSubsystems(comptime api: type, state: anytype, flags: u32) void {
    state.windows_sdl.subsystems &= ~flags;
    if ((flags & SDL_INIT_AUDIO) == 0) return;
    for (&state.windows_sdl.audio_devices) |*device| device.* = .{};
    maybeCloseHostOutput(state);
    api._log.info("PE64 SDL audio subsystem stopped", .{});
}

/// Deliver one due SDL callback without simulating a host audio thread. The
/// audio period follows the guest clock, while execution and memory remain in
/// the guest callback ABI and existing scheduler continuation machinery.
pub fn dispatchDueCallback(comptime api: type, state: anytype, direct_return_rip: ?u64) bool {
    const now = api._windowsGuestClockTicks(state);
    const regs = &api._guestStateField(state, "regs").*;
    for (&state.windows_sdl.audio_devices) |*device| {
        if (!device.active or device.paused or device.callback == 0 or now < device.next_callback_ticks) continue;
        device.next_callback_ticks = now +| device.period_ticks;

        if (!api._fillGuest(state, device.stream_address, device.stream_size, audioSilenceByte(device.format))) {
            state.windows_sdl.audio_callback_failures +|= 1;
            device.paused = true;
            api._log.err("PE64 SDL audio callback skipped: guest stream is no longer writable device={d} stream=0x{x} bytes={d}", .{
                device.id,
                device.stream_address,
                device.stream_size,
            });
            return false;
        }

        const return_rip = direct_return_rip orelse state.read64(regs.rsp);
        const State = @TypeOf(state.*);
        var callback_mapped = true;
        if (comptime @hasDecl(State, "addrToOffset")) callback_mapped = state.addrToOffset(device.callback) != null;
        if (return_rip == 0 or !callback_mapped) {
            state.windows_sdl.audio_callback_failures +|= 1;
            device.paused = true;
            api._log.err("PE64 SDL audio callback skipped: invalid guest continuation or callback device={d} callback=0x{x} return=0x{x}", .{
                device.id,
                device.callback,
                return_rip,
            });
            return false;
        }

        if (comptime @hasDecl(api, "_beginWindowsSdlAudioCallback")) {
            if (!api._beginWindowsSdlAudioCallback(
                state,
                return_rip,
                direct_return_rip != null,
                device.stream_address,
                device.stream_size,
                regs.rax,
            )) {
                state.windows_sdl.audio_callback_failures +|= 1;
                device.paused = true;
                api._log.err("PE64 SDL audio callback skipped: could not reserve a guest callback frame device={d}", .{device.id});
                return false;
            }
        } else {
            return false;
        }

        // SDL_AudioCallback(userdata, stream, len), using the Windows x64 ABI.
        regs.rcx = device.userdata;
        regs.rdx = device.stream_address;
        regs.r8 = device.stream_size;
        regs.r9 = 0;
        regs.rip = device.callback;
        device.callbacks +|= 1;
        state.windows_sdl.audio_callback_dispatches +|= 1;
        if (device.callbacks == 1) {
            api._log.info("PE64 SDL audio: first guest callback device={d} callback=0x{x} stream=0x{x} bytes={d} host_output={s}", .{
                device.id,
                device.callback,
                device.stream_address,
                device.stream_size,
                if (state.windows_audio_host_connected) "connected" else "unavailable",
            });
        }
        return true;
    }
    return false;
}

fn openAudioDevice(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const regs = &api._guestStateField(state, "regs").*;
    const desired_address = api._arg(state, 2, direct_return_rip);
    const desired_bytes = state.guestMemoryConst(desired_address, SDL_AUDIO_SPEC_BYTES) orelse {
        setError(api, state, "SDL_OpenAudioDevice received an unreadable desired SDL_AudioSpec");
        regs.rax = 0;
        api._finish(state, direct_return_rip);
        return;
    };
    var spec = AudioSpec.read(desired_bytes);
    const sample_bytes = bytesPerSample(spec.format) orelse {
        setError(api, state, "SDL_OpenAudioDevice received an unsupported PCM format");
        regs.rax = 0;
        api._finish(state, direct_return_rip);
        return;
    };
    if (api._arg(state, 1, direct_return_rip) != 0 or spec.frequency < 8000 or spec.frequency > 192000 or
        spec.channels == 0 or spec.channels > 8 or spec.samples == 0 or spec.samples > 8192)
    {
        setError(api, state, "SDL_OpenAudioDevice received unsupported capture or stream parameters");
        regs.rax = 0;
        api._finish(state, direct_return_rip);
        return;
    }
    if ((state.windows_sdl.subsystems & SDL_INIT_AUDIO) == 0) {
        setError(api, state, "SDL_INIT_AUDIO must be initialized before SDL_OpenAudioDevice");
        regs.rax = 0;
        api._finish(state, direct_return_rip);
        return;
    }
    const State = @TypeOf(state.*);
    var callback_mapped = spec.callback != 0;
    if (comptime @hasDecl(State, "addrToOffset")) callback_mapped = callback_mapped and state.addrToOffset(spec.callback) != null;
    if (!callback_mapped) {
        setError(api, state, "Rosetta SDL audio requires a mapped guest callback");
        regs.rax = 0;
        api._finish(state, direct_return_rip);
        return;
    }
    const buffer_bytes = @as(u64, spec.samples) * @as(u64, spec.channels) * sample_bytes;
    if (buffer_bytes > std.math.maxInt(u32)) {
        setError(api, state, "SDL_OpenAudioDevice stream size overflowed");
        regs.rax = 0;
        api._finish(state, direct_return_rip);
        return;
    }

    const devices = &state.windows_sdl.audio_devices;
    var slot: ?usize = null;
    for (devices, 0..) |device, index| {
        if (device.active) continue;
        slot = index;
        break;
    }
    const device_slot = slot orelse {
        setError(api, state, "Rosetta SDL audio device table is full");
        regs.rax = 0;
        api._finish(state, direct_return_rip);
        return;
    };

    const obtained_address = api._arg(state, 3, direct_return_rip);
    if (obtained_address != 0) {
        const obtained = state.guestMemory(obtained_address, SDL_AUDIO_SPEC_BYTES) orelse {
            setError(api, state, "SDL_OpenAudioDevice obtained SDL_AudioSpec is unwritable");
            regs.rax = 0;
            api._finish(state, direct_return_rip);
            return;
        };
        spec.silence = if (spec.format == AUDIO_U8) 0x80 else 0;
        spec.padding = 0;
        spec.size = @intCast(buffer_bytes);
        spec.write(obtained);
    }

    const stream_address = state.guestAlloc(buffer_bytes, 16) orelse {
        setError(api, state, "SDL_OpenAudioDevice could not allocate a guest audio stream");
        regs.rax = 0;
        api._finish(state, direct_return_rip);
        return;
    };
    const silence = audioSilenceByte(spec.format);
    if (!api._fillGuest(state, stream_address, buffer_bytes, silence)) {
        setError(api, state, "SDL_OpenAudioDevice could not initialize the guest audio stream");
        regs.rax = 0;
        api._finish(state, direct_return_rip);
        return;
    }

    var next_id = state.windows_sdl.audio_next_device_id;
    if (next_id == 0) next_id = 1;
    const period_ticks = @max(@as(u64, 1), @as(u64, spec.samples) * api._windowsGuestClockHz(state) / @as(u64, @intCast(spec.frequency)));
    devices[device_slot] = .{
        .id = next_id,
        .active = true,
        .callback = spec.callback,
        .userdata = spec.userdata,
        .stream_address = stream_address,
        .stream_size = @intCast(buffer_bytes),
        .format = spec.format,
        .frequency = @intCast(spec.frequency),
        .samples = spec.samples,
        .period_ticks = period_ticks,
    };
    state.windows_sdl.audio_next_device_id = if (next_id == std.math.maxInt(u32)) 1 else next_id + 1;
    state.windows_sdl.error_message = 0;
    regs.rax = next_id;
    const host_format = hostFormat(spec.format);
    if (host_format) |format| {
        if (comptime @hasDecl(State, "openWindowsHostAudio")) {
            _ = state.openWindowsHostAudio(@intCast(spec.frequency), spec.channels, format.bits, format.is_float);
        }
    }
    api._log.info("PE64 SDL audio device: id={d} frequency={d} format=0x{x} channels={d} samples={d} bytes={d} callback=0x{x} stream=0x{x} host_output={s}", .{
        next_id,
        spec.frequency,
        spec.format,
        spec.channels,
        spec.samples,
        buffer_bytes,
        spec.callback,
        stream_address,
        if (state.windows_audio_host_connected) "connected" else "unavailable",
    });
    api._finish(state, direct_return_rip);
}

fn audioDeviceControl(comptime api: type, state: anytype, name: []const u8, direct_return_rip: ?u64) void {
    const regs = &api._guestStateField(state, "regs").*;
    const device_id: u32 = @truncate(api._arg(state, 0, direct_return_rip));
    for (&state.windows_sdl.audio_devices) |*device| {
        if (device.active and device.id == device_id) {
            if (std.mem.eql(u8, name, "SDL_PauseAudioDevice")) {
                device.paused = api._arg(state, 1, direct_return_rip) != 0;
                if (!device.paused) device.next_callback_ticks = api._windowsGuestClockTicks(state);
                api._log.info("PE64 SDL audio device: id={d} paused={}", .{ device_id, device.paused });
            }
            regs.rax = 0;
            api._finish(state, direct_return_rip);
            return;
        }
    }
    setError(api, state, "SDL audio control received a stale or foreign device id");
    regs.rax = if (std.mem.eql(u8, name, "SDL_PauseAudioDevice")) 0 else 0;
    api._finish(state, direct_return_rip);
}

fn closeAudioDevice(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const regs = &api._guestStateField(state, "regs").*;
    const device_id: u32 = @truncate(api._arg(state, 0, direct_return_rip));
    const devices = &state.windows_sdl.audio_devices;
    for (devices) |*device| {
        if (device.active and device.id == device_id) {
            device.* = .{};
            regs.rax = 0;
            maybeCloseHostOutput(state);
            api._finish(state, direct_return_rip);
            return;
        }
    }
    setError(api, state, "SDL_CloseAudioDevice received a stale or foreign device id");
    regs.rax = 0;
    api._finish(state, direct_return_rip);
}

fn bytesPerSample(format: u16) ?u8 {
    return switch (format) {
        AUDIO_U8, AUDIO_S8 => 1,
        AUDIO_U16LSB, AUDIO_S16LSB, AUDIO_U16MSB, AUDIO_S16MSB => 2,
        AUDIO_S32LSB, AUDIO_F32LSB => 4,
        else => null,
    };
}

fn audioSilenceByte(format: u16) u8 {
    return if (format == AUDIO_U8) 0x80 else 0;
}

const HostFormat = struct { bits: u32, is_float: bool };

fn hostFormat(format: u16) ?HostFormat {
    return switch (format) {
        AUDIO_U8 => .{ .bits = 8, .is_float = false },
        AUDIO_S16LSB => .{ .bits = 16, .is_float = false },
        AUDIO_S32LSB => .{ .bits = 32, .is_float = false },
        AUDIO_F32LSB => .{ .bits = 32, .is_float = true },
        // The host bridge accepts little-endian PCM. Other SDL formats still
        // execute their guest callback, but are not mislabelled as audible.
        else => null,
    };
}

fn maybeCloseHostOutput(state: anytype) void {
    for (state.windows_sdl.audio_devices) |device| if (device.active) return;
    for (state.windows_wave_out_devices) |device| if (device.opened) return;
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "closeWindowsHostAudio")) state.closeWindowsHostAudio();
}

fn bytesPerSecondRate(src_rate: u32, dst_rate: u32) ?f64 {
    if (src_rate == 0 or dst_rate == 0 or src_rate > 192000 or dst_rate > 192000) return null;
    return @as(f64, @floatFromInt(dst_rate)) / @as(f64, @floatFromInt(src_rate));
}

fn calculateLenMult(conversion: Conversion) ?u32 {
    const source_sample_bytes = bytesPerSample(conversion.src_format) orelse return null;
    const destination_sample_bytes = bytesPerSample(conversion.dst_format) orelse return null;
    const rate_ratio = bytesPerSecondRate(conversion.src_rate, conversion.dst_rate) orelse return null;
    if (conversion.src_channels == 0 or conversion.dst_channels == 0 or
        conversion.src_channels > 8 or conversion.dst_channels > 8) return null;

    const byte_ratio = @as(f64, @floatFromInt(destination_sample_bytes)) /
        @as(f64, @floatFromInt(source_sample_bytes));
    const channel_ratio = @as(f64, @floatFromInt(conversion.dst_channels)) /
        @as(f64, @floatFromInt(conversion.src_channels));
    const worst_case = @ceil(rate_ratio * byte_ratio * channel_ratio);
    if (!std.math.isFinite(worst_case) or worst_case < 1 or worst_case > 256) return null;
    return @intFromFloat(worst_case);
}

fn buildAudioCvt(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const regs = &api._guestStateField(state, "regs").*;
    const cvt_address = api._arg(state, 0, direct_return_rip);
    const conversion = Conversion{
        .src_format = @truncate(api._arg(state, 1, direct_return_rip)),
        .src_channels = @truncate(api._arg(state, 2, direct_return_rip)),
        .src_rate = @truncate(api._arg(state, 3, direct_return_rip)),
        .dst_format = @truncate(api._arg(state, 4, direct_return_rip)),
        .dst_channels = @truncate(api._arg(state, 5, direct_return_rip)),
        .dst_rate = @truncate(api._arg(state, 6, direct_return_rip)),
    };
    const len_mult = calculateLenMult(conversion) orelse {
        api._log.err("PE64 SDL audio conversion rejected: cvt=0x{x} source={d}/{d}Hz/{d}ch destination={d}/{d}Hz/{d}ch", .{
            cvt_address,
            conversion.src_format,
            conversion.src_rate,
            conversion.src_channels,
            conversion.dst_format,
            conversion.dst_rate,
            conversion.dst_channels,
        });
        setError(api, state, "SDL_BuildAudioCVT received an unsupported PCM format, channel count, or rate");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    };
    const cvt = state.guestMemory(cvt_address, SDL_AUDIO_CVT_BYTES) orelse {
        setError(api, state, "SDL_BuildAudioCVT received an unreadable SDL_AudioCVT");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    };

    @memset(cvt, 0);
    const needed = conversion.src_format != conversion.dst_format or
        conversion.src_channels != conversion.dst_channels or conversion.src_rate != conversion.dst_rate;
    state.write32(cvt_address, @intFromBool(needed));
    state.write16(cvt_address + 4, conversion.src_format);
    state.write16(cvt_address + 6, conversion.dst_format);
    const rate_incr = @as(f64, @floatFromInt(conversion.dst_rate)) / @as(f64, @floatFromInt(conversion.src_rate));
    state.write64(cvt_address + 8, @bitCast(rate_incr));
    state.write32(cvt_address + 32, len_mult);
    const len_ratio = rate_incr *
        (@as(f64, @floatFromInt(conversion.dst_channels)) / @as(f64, @floatFromInt(conversion.src_channels))) *
        (@as(f64, @floatFromInt(bytesPerSample(conversion.dst_format).?)) /
            @as(f64, @floatFromInt(bytesPerSample(conversion.src_format).?)));
    state.write64(cvt_address + 40, @bitCast(len_ratio));

    var record_slot: ?usize = null;
    for (&state.windows_sdl.audio_cvt_records, 0..) |record, index| {
        if (record.cvt == cvt_address or record.cvt == 0) {
            record_slot = index;
            if (record.cvt == cvt_address) break;
        }
    }
    if (record_slot) |slot| {
        state.windows_sdl.audio_cvt_records[slot] = .{
            .cvt = cvt_address,
            .src_format = conversion.src_format,
            .dst_format = conversion.dst_format,
            .src_channels = conversion.src_channels,
            .dst_channels = conversion.dst_channels,
            .src_rate = conversion.src_rate,
            .dst_rate = conversion.dst_rate,
        };
    } else {
        setError(api, state, "Rosetta SDL audio conversion table is full");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    }

    regs.rax = @intFromBool(needed);
    api._log.info("PE64 SDL audio conversion: cvt=0x{x} source={d}/{d}Hz/{d}ch destination={d}/{d}Hz/{d}ch len_mult={d} needed={}", .{
        cvt_address,
        conversion.src_format,
        conversion.src_rate,
        conversion.src_channels,
        conversion.dst_format,
        conversion.dst_rate,
        conversion.dst_channels,
        len_mult,
        needed,
    });
    api._finish(state, direct_return_rip);
}

fn readPcmSample(bytes: []const u8, format: u16, offset: usize) ?i16 {
    return switch (format) {
        AUDIO_U8 => @intCast((@as(i32, bytes[offset]) - 128) << 8),
        AUDIO_S8 => @as(i16, @as(i8, @bitCast(bytes[offset]))) * 256,
        AUDIO_U16LSB => @as(i16, @intCast(@as(i32, std.mem.readInt(u16, bytes[offset..][0..2], .little)) - 32768)),
        AUDIO_S16LSB => std.mem.readInt(i16, bytes[offset..][0..2], .little),
        AUDIO_U16MSB => @as(i16, @intCast(@as(i32, std.mem.readInt(u16, bytes[offset..][0..2], .big)) - 32768)),
        AUDIO_S16MSB => std.mem.readInt(i16, bytes[offset..][0..2], .big),
        else => null,
    };
}

fn convertPcm(allocator: std.mem.Allocator, source: []const u8, conversion: Conversion) ?[]u8 {
    if (conversion.dst_format != AUDIO_S16LSB) return null;
    const source_sample_bytes: usize = bytesPerSample(conversion.src_format) orelse return null;
    const destination_sample_bytes: usize = bytesPerSample(conversion.dst_format) orelse return null;
    const source_frame_bytes = source_sample_bytes * conversion.src_channels;
    if (source_frame_bytes == 0 or source.len % source_frame_bytes != 0) return null;
    const source_frames = source.len / source_frame_bytes;
    const scaled_frames_f = @as(f64, @floatFromInt(source_frames)) *
        (@as(f64, @floatFromInt(conversion.dst_rate)) / @as(f64, @floatFromInt(conversion.src_rate)));
    if (!std.math.isFinite(scaled_frames_f) or scaled_frames_f > @as(f64, @floatFromInt(MAX_AUDIO_CVT_BYTES))) return null;
    const destination_frames: usize = @intFromFloat(@ceil(scaled_frames_f));
    const destination_frame_bytes = destination_sample_bytes * conversion.dst_channels;
    const destination_bytes = std.math.mul(usize, destination_frames, destination_frame_bytes) catch return null;
    if (destination_bytes > MAX_AUDIO_CVT_BYTES) return null;
    const output = allocator.alloc(u8, destination_bytes) catch return null;

    for (0..destination_frames) |destination_frame| {
        const source_frame = @min(
            (@as(u64, @intCast(destination_frame)) * conversion.src_rate) / conversion.dst_rate,
            @as(u64, @intCast(source_frames -| 1)),
        );
        for (0..conversion.dst_channels) |destination_channel| {
            var value: i32 = undefined;
            if (conversion.src_channels == 1) {
                value = readPcmSample(source, conversion.src_format, @as(usize, @intCast(source_frame)) * source_frame_bytes) orelse return freeNull(allocator, output);
            } else if (conversion.dst_channels == 1) {
                const frame_offset = @as(usize, @intCast(source_frame)) * source_frame_bytes;
                const left = readPcmSample(source, conversion.src_format, frame_offset) orelse return freeNull(allocator, output);
                const right = readPcmSample(source, conversion.src_format, frame_offset + source_sample_bytes) orelse return freeNull(allocator, output);
                value = @divTrunc(@as(i32, left) + right, 2);
            } else {
                const channel = @min(destination_channel, @as(usize, conversion.src_channels - 1));
                value = readPcmSample(
                    source,
                    conversion.src_format,
                    @as(usize, @intCast(source_frame)) * source_frame_bytes + channel * source_sample_bytes,
                ) orelse return freeNull(allocator, output);
            }
            const output_offset = destination_frame * destination_frame_bytes + destination_channel * destination_sample_bytes;
            std.mem.writeInt(i16, output[output_offset..][0..2], @intCast(value), .little);
        }
    }
    return output;
}

fn freeNull(allocator: std.mem.Allocator, bytes: []u8) ?[]u8 {
    allocator.free(bytes);
    return null;
}

fn convertAudio(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const regs = &api._guestStateField(state, "regs").*;
    const cvt_address = api._arg(state, 0, direct_return_rip);
    if (state.guestMemory(cvt_address, 48) == null) {
        setError(api, state, "SDL_ConvertAudio received an unreadable SDL_AudioCVT");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    }
    const record = for (state.windows_sdl.audio_cvt_records) |candidate| {
        if (candidate.cvt == cvt_address) break candidate;
    } else {
        setError(api, state, "SDL_ConvertAudio received an unknown SDL_AudioCVT");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    };
    const len: u32 = state.read32(cvt_address + 24);
    const buffer_address = state.read64(cvt_address + 16);
    if (len > MAX_AUDIO_CVT_BYTES or buffer_address == 0) {
        setError(api, state, "SDL_ConvertAudio received an invalid input buffer or length");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    }
    const input = state.guestMemoryConst(buffer_address, len) orelse {
        setError(api, state, "SDL_ConvertAudio input buffer is unreadable");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    };
    const conversion = Conversion{
        .src_format = record.src_format,
        .dst_format = record.dst_format,
        .src_channels = record.src_channels,
        .dst_channels = record.dst_channels,
        .src_rate = record.src_rate,
        .dst_rate = record.dst_rate,
    };
    const output = if (conversion.src_format == conversion.dst_format and
        conversion.src_channels == conversion.dst_channels and conversion.src_rate == conversion.dst_rate)
        state.allocator.dupe(u8, input) catch null
    else
        convertPcm(state.allocator, input, conversion);
    const output_bytes = output orelse {
        setError(api, state, "SDL_ConvertAudio could not convert the requested PCM format");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    };
    defer state.allocator.free(output_bytes);

    const len_mult = state.read32(cvt_address + 32);
    const maximum_capacity = std.math.mul(u64, len, len_mult) catch 0;
    if (output_bytes.len > maximum_capacity or output_bytes.len > MAX_AUDIO_CVT_BYTES) {
        setError(api, state, "SDL_ConvertAudio output exceeds the SDL_AudioCVT allocation bound");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    }
    const destination = state.guestMemory(buffer_address, @max(@as(u64, len), @as(u64, output_bytes.len))) orelse {
        setError(api, state, "SDL_ConvertAudio output buffer is unwritable");
        regs.rax = 0xFFFF_FFFF;
        api._finish(state, direct_return_rip);
        return;
    };
    @memcpy(destination[0..output_bytes.len], output_bytes);
    state.write32(cvt_address + 28, @intCast(output_bytes.len));
    regs.rax = 0;
    api._finish(state, direct_return_rip);
}

fn setError(comptime api: type, state: anytype, message: []const u8) void {
    state.windows_sdl.error_message = api._materializeGuestAnsi(state, message) orelse 0;
}
