/// Guest addresses allocated for SDL-compatible software surfaces. These
/// records keep SDL_FreeSurface constrained to allocations made by Rosetta.
const WindowsSdlSurfaceRecord = struct {
    surface: u64 = 0,
    pixels: u64 = 0,
    format: u64 = 0,
    palette: u64 = 0,
    palette_colors: u64 = 0,
};

/// Opaque guest SDL texture handle plus its guest-owned byte storage and
/// renderer metadata. Pixel format/access are SDL values, not host handles.
const WindowsSdlTextureRecord = struct {
    handle: u64 = 0,
    pixels: u64 = 0,
    format: u32 = 0,
    access: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    pitch: u32 = 0,
};

/// Rosetta-owned conversion facts for the bounded SDL_AudioCVT ABI. The guest
/// still owns the SDL_AudioCVT bytes and buffer; these records hold only the
/// rate/channel facts SDL's filter chain would otherwise encode in function
/// pointers that cannot be called as host code.
const WindowsSdlAudioCvtRecord = struct {
    cvt: u64 = 0,
    src_format: u16 = 0,
    dst_format: u16 = 0,
    src_channels: u8 = 0,
    dst_channels: u8 = 0,
    src_rate: u32 = 0,
    dst_rate: u32 = 0,
};

/// Identity for SDL devices served by the PE runner's clocked silent sink.
/// The guest owns the SDL_AudioSpec bytes; the runtime only tracks IDs so
/// close/pause calls can reject stale handles deterministically.
const WindowsSdlAudioDeviceRecord = struct {
    id: u32 = 0,
    active: bool = false,
    paused: bool = true,
    callback: u64 = 0,
    userdata: u64 = 0,
    stream_address: u64 = 0,
    stream_size: u32 = 0,
    format: u16 = 0,
    frequency: u32 = 0,
    samples: u32 = 0,
    period_ticks: u64 = 0,
    next_callback_ticks: u64 = 0,
    callbacks: u64 = 0,
};

pub const WindowsSdlState = struct {
    window: u64 = 0,
    error_message: u64 = 0,
    window_title: [256]u8 = @splat(0),
    window_title_len: usize = 0,
    renderer: u64 = 0,
    renderer_pixels: u64 = 0,
    renderer_width: u32 = 0,
    renderer_height: u32 = 0,
    renderer_pitch: u32 = 0,
    draw_color: [4]u8 = .{ 0, 0, 0, 255 },
    surface_records: [32]WindowsSdlSurfaceRecord = [_]WindowsSdlSurfaceRecord{.{}} ** 32,
    texture_records: [32]WindowsSdlTextureRecord = [_]WindowsSdlTextureRecord{.{}} ** 32,
    audio_cvt_records: [16]WindowsSdlAudioCvtRecord = [_]WindowsSdlAudioCvtRecord{.{}} ** 16,
    audio_devices: [8]WindowsSdlAudioDeviceRecord = [_]WindowsSdlAudioDeviceRecord{.{}} ** 8,
    audio_next_device_id: u32 = 1,
    subsystems: u32 = 0,
    audio_callback_dispatches: u64 = 0,
    audio_callback_failures: u64 = 0,
    present_count: u64 = 0,
};
