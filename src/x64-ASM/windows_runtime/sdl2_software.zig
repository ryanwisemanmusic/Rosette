//! Bounded SDL2 software surfaces and renderer for PE guests.
//!
//! This is an SDL ABI model, not host SDL. Guest pixels stay in guest memory;
//! RenderPresent asks the registered host hook to validate and present one
//! complete RGBA frame through Rosetta's native window layer.

const std = @import("std");

const SDL_PIXELFORMAT_INDEX8: u32 = 0x13000801;
const SDL_PIXELFORMAT_XRGB8888: u32 = 0x16161804;
const MAX_DIMENSION: u32 = 8192;
const MAX_BUFFER_BYTES: u64 = 128 * 1024 * 1024;
const SDL_SURFACE_BYTES: u64 = 80;
const SDL_PIXEL_FORMAT_BYTES: u64 = 56;
const SDL_PALETTE_BYTES: u64 = 24;

const PixelInfo = struct {
    bytes: u8,
    bits: u8,
    kind: u8,
    order: u8,
    layout: u8,
    rmask: u32 = 0,
    gmask: u32 = 0,
    bmask: u32 = 0,
    amask: u32 = 0,
};

const Rect = struct { x: i32, y: i32, w: i32, h: i32 };
const RGBA = struct { r: u8, g: u8, b: u8, a: u8 = 255 };

pub fn handle(comptime api: type, state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (std.mem.eql(u8, name, "SDL_CreateRGBSurface")) {
        createSurface(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_FreeSurface")) {
        freeSurface(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_AllocFormat")) {
        allocFormat(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_FreeFormat")) {
        freeFormat(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_MapRGB")) {
        mapRgb(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_FillRect")) {
        fillRect(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_UpperBlit")) {
        blitSurface(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_CreateRenderer")) {
        createRenderer(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_DestroyRenderer")) {
        destroyRenderer(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_CreateTexture")) {
        createTexture(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_DestroyTexture")) {
        destroyTexture(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_QueryTexture")) {
        queryTexture(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_LockTexture")) {
        lockTexture(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_UnlockTexture")) {
        unlockTexture(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_SetRenderDrawColor")) {
        setDrawColor(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_RenderClear")) {
        renderClear(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_RenderCopy")) {
        renderCopy(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_RenderPresent")) {
        renderPresent(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_GetPixelFormatName")) {
        getPixelFormatName(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_ShowSimpleMessageBox")) {
        showSimpleMessageBox(api, state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SDL_SetWindowFullscreen") or std.mem.eql(u8, name, "SDL_SetWindowPosition")) {
        // The app's borderless/fullscreen preference is advisory. Rosetta owns
        // window sizing and user-movable placement, so report a successful
        // no-op and leave the native window policy intact.
        finish(api, state, 0, direct_return_rip);
        return true;
    }
    return false;
}

fn finish(comptime api: type, state: anytype, value: u64, direct_return_rip: ?u64) void {
    api._guestStateField(state, "regs").*.rax = value;
    api._finish(state, direct_return_rip);
}

fn setError(comptime api: type, state: anytype, message: []const u8) void {
    state.windows_sdl.error_message = api._materializeGuestAnsi(state, message) orelse 0;
}

fn arg(comptime api: type, state: anytype, index: usize, direct_return_rip: ?u64) u64 {
    return api._arg(state, index, direct_return_rip);
}

fn alloc(comptime api: type, state: anytype, size: u64, alignment: u64) ?u64 {
    _ = api;
    if (size == 0 or size > MAX_BUFFER_BYTES) return null;
    return state.guestAlloc(size, alignment);
}

fn write8(state: anytype, address: u64, value: u8) bool {
    if (state.guestMemory(address, 1) == null) return false;
    state.write8(address, value);
    return true;
}

fn write32(state: anytype, address: u64, value: u32) bool {
    if (state.guestMemory(address, 4) == null) return false;
    state.write32(address, value);
    return true;
}

fn write64(state: anytype, address: u64, value: u64) bool {
    if (state.guestMemory(address, 8) == null) return false;
    state.write64(address, value);
    return true;
}

fn readRect(state: anytype, address: u64, fallback: Rect) ?Rect {
    if (address == 0) return fallback;
    if (state.guestMemoryConst(address, 16) == null) return null;
    return .{
        .x = @bitCast(state.read32(address)),
        .y = @bitCast(state.read32(address + 4)),
        .w = @bitCast(state.read32(address + 8)),
        .h = @bitCast(state.read32(address + 12)),
    };
}

fn decodePixelInfo(format: u32) ?PixelInfo {
    if ((format >> 28) != 1) return null;
    const kind: u8 = @truncate((format >> 24) & 0xF);
    const order: u8 = @truncate((format >> 20) & 0xF);
    const layout: u8 = @truncate((format >> 16) & 0xF);
    const bits: u8 = @truncate((format >> 8) & 0xFF);
    const bytes: u8 = @truncate(format & 0xFF);
    if (bytes == 0 or bytes > 4 or bits == 0) return null;
    var info: PixelInfo = .{ .bytes = bytes, .bits = bits, .kind = kind, .order = order, .layout = layout };
    if (kind == 6 and layout == 6 and bytes == 4) {
        switch (order) {
            1 => {
                info.rmask = 0x00FF0000;
                info.gmask = 0x0000FF00;
                info.bmask = 0x000000FF;
            }, // XRGB
            2 => {
                info.rmask = 0xFF000000;
                info.gmask = 0x00FF0000;
                info.bmask = 0x0000FF00;
            }, // RGBX
            3 => {
                info.rmask = 0x00FF0000;
                info.gmask = 0x0000FF00;
                info.bmask = 0x000000FF;
                info.amask = 0xFF000000;
            }, // ARGB
            4 => {
                info.rmask = 0xFF000000;
                info.gmask = 0x00FF0000;
                info.bmask = 0x0000FF00;
                info.amask = 0x000000FF;
            }, // RGBA
            5 => {
                info.bmask = 0x00FF0000;
                info.gmask = 0x0000FF00;
                info.rmask = 0x000000FF;
            }, // XBGR
            6 => {
                info.bmask = 0xFF000000;
                info.gmask = 0x00FF0000;
                info.rmask = 0x0000FF00;
            }, // BGRX
            7 => {
                info.bmask = 0x00FF0000;
                info.gmask = 0x0000FF00;
                info.rmask = 0x000000FF;
                info.amask = 0xFF000000;
            }, // ABGR
            8 => {
                info.bmask = 0xFF000000;
                info.gmask = 0x00FF0000;
                info.rmask = 0x0000FF00;
                info.amask = 0x000000FF;
            }, // BGRA
            else => return null,
        }
    } else if (kind == 5 and layout == 5 and bytes == 2) {
        if (order == 1) {
            info.rmask = 0xF800;
            info.gmask = 0x07E0;
            info.bmask = 0x001F;
        } else if (order == 4 or order == 5) {
            info.bmask = 0xF800;
            info.gmask = 0x07E0;
            info.rmask = 0x001F;
        } else return null;
    }
    return info;
}

fn formatFromMasks(bits: u8, rmask: u32, gmask: u32, bmask: u32, amask: u32) ?PixelInfo {
    if (bits == 8 and rmask == 0 and gmask == 0 and bmask == 0 and amask == 0) {
        return decodePixelInfo(SDL_PIXELFORMAT_INDEX8);
    }
    if (bits == 32 and rmask == 0 and gmask == 0 and bmask == 0 and amask == 0) {
        return decodePixelInfo(SDL_PIXELFORMAT_XRGB8888);
    }
    if (bits != 8 and bits != 16 and bits != 24 and bits != 32) return null;
    return .{
        .bytes = @intCast((bits + 7) / 8),
        .bits = bits,
        .kind = 0,
        .order = 0,
        .layout = 0,
        .rmask = rmask,
        .gmask = gmask,
        .bmask = bmask,
        .amask = amask,
    };
}

fn trailingShift(mask: u32) u8 {
    return if (mask == 0) 0 else @intCast(@ctz(mask));
}

fn channelFromMask(value: u32, mask: u32, default: u8) u8 {
    if (mask == 0) return default;
    const shift = trailingShift(mask);
    const component = (value & mask) >> @as(u5, @intCast(shift));
    const maximum = mask >> @as(u5, @intCast(shift));
    if (maximum == 0) return default;
    return @intCast((@as(u64, component) * 255 + maximum / 2) / maximum);
}

fn channelToMask(component: u8, mask: u32) u32 {
    if (mask == 0) return 0;
    const shift = trailingShift(mask);
    const maximum = mask >> @as(u5, @intCast(shift));
    return @as(u32, @intCast(((@as(u64, component) * maximum + 127) / 255) << @as(u6, @intCast(shift)))) & mask;
}

fn readPacked(state: anytype, address: u64, bytes: u8) ?u32 {
    const memory = state.guestMemoryConst(address, bytes) orelse return null;
    var value: u32 = 0;
    for (memory, 0..) |byte, index| value |= @as(u32, byte) << @intCast(index * 8);
    return value;
}

fn writePacked(state: anytype, address: u64, bytes: u8, value: u32) bool {
    const memory = state.guestMemory(address, bytes) orelse return false;
    for (memory, 0..) |*byte, index| byte.* = @truncate(value >> @intCast(index * 8));
    return true;
}

fn readFormatPixel(state: anytype, address: u64, info: PixelInfo, palette: u64) ?RGBA {
    if (info.kind == 7) {
        const raw = state.guestMemoryConst(address, info.bytes) orelse return null;
        const i = info.order;
        return switch (i) {
            1 => if (raw.len >= 3) .{ .r = raw[0], .g = raw[1], .b = raw[2] } else null, // RGB
            2 => if (raw.len >= 4) .{ .r = raw[0], .g = raw[1], .b = raw[2], .a = raw[3] } else null, // RGBA
            3 => if (raw.len >= 4) .{ .r = raw[1], .g = raw[2], .b = raw[3], .a = raw[0] } else null, // ARGB
            4 => if (raw.len >= 3) .{ .r = raw[2], .g = raw[1], .b = raw[0] } else null, // BGR
            5 => if (raw.len >= 4) .{ .r = raw[2], .g = raw[1], .b = raw[0], .a = raw[3] } else null, // BGRA
            6 => if (raw.len >= 4) .{ .r = raw[3], .g = raw[2], .b = raw[1], .a = raw[0] } else null, // ABGR
            else => null,
        };
    }
    const packed_value = readPacked(state, address, info.bytes) orelse return null;
    if (info.bytes == 1 and info.rmask == 0 and info.gmask == 0 and info.bmask == 0 and palette != 0) {
        const colors = state.read64(palette + 8);
        const color = colors + @as(u64, @truncate(packed_value)) * 4;
        if (state.guestMemoryConst(color, 4)) |rgba| return .{ .r = rgba[0], .g = rgba[1], .b = rgba[2], .a = rgba[3] };
    }
    if (info.bytes == 1 and info.rmask == 0 and info.gmask == 0 and info.bmask == 0) {
        const value: u8 = @truncate(packed_value);
        return .{ .r = value, .g = value, .b = value };
    }
    if (info.rmask == 0 and info.gmask == 0 and info.bmask == 0) return null;
    return .{
        .r = channelFromMask(packed_value, info.rmask, 0),
        .g = channelFromMask(packed_value, info.gmask, 0),
        .b = channelFromMask(packed_value, info.bmask, 0),
        .a = channelFromMask(packed_value, info.amask, 255),
    };
}

fn writeFormatPixel(state: anytype, address: u64, info: PixelInfo, palette: u64, color: RGBA) bool {
    if (info.kind == 7) {
        const raw = state.guestMemory(address, info.bytes) orelse return false;
        switch (info.order) {
            1 => if (raw.len >= 3) {
                raw[0] = color.r;
                raw[1] = color.g;
                raw[2] = color.b;
            } else return false,
            2 => if (raw.len >= 4) {
                raw[0] = color.r;
                raw[1] = color.g;
                raw[2] = color.b;
                raw[3] = color.a;
            } else return false,
            3 => if (raw.len >= 4) {
                raw[0] = color.a;
                raw[1] = color.r;
                raw[2] = color.g;
                raw[3] = color.b;
            } else return false,
            4 => if (raw.len >= 3) {
                raw[0] = color.b;
                raw[1] = color.g;
                raw[2] = color.r;
            } else return false,
            5 => if (raw.len >= 4) {
                raw[0] = color.b;
                raw[1] = color.g;
                raw[2] = color.r;
                raw[3] = color.a;
            } else return false,
            6 => if (raw.len >= 4) {
                raw[0] = color.a;
                raw[1] = color.b;
                raw[2] = color.g;
                raw[3] = color.r;
            } else return false,
            else => return false,
        }
        return true;
    }
    if (info.bytes == 1 and info.rmask == 0 and info.gmask == 0 and info.bmask == 0) {
        var index: u8 = 0;
        if (palette != 0) {
            const colors = state.read64(palette + 8);
            var best_distance: u32 = std.math.maxInt(u32);
            for (0..256) |candidate| {
                const color_address = colors + candidate * 4;
                const rgba = state.guestMemoryConst(color_address, 4) orelse break;
                const dr = @as(i32, color.r) - rgba[0];
                const dg = @as(i32, color.g) - rgba[1];
                const db = @as(i32, color.b) - rgba[2];
                const distance: u32 = @intCast(dr * dr + dg * dg + db * db);
                if (distance < best_distance) {
                    best_distance = distance;
                    index = @intCast(candidate);
                    if (distance == 0) break;
                }
            }
        } else index = color.r;
        return writePacked(state, address, info.bytes, index);
    }
    const value = channelToMask(color.r, info.rmask) | channelToMask(color.g, info.gmask) |
        channelToMask(color.b, info.bmask) | channelToMask(color.a, info.amask);
    return writePacked(state, address, info.bytes, value);
}

fn formatInfoFromGuest(state: anytype, format_address: u64) ?PixelInfo {
    if (format_address == 0 or state.guestMemoryConst(format_address, SDL_PIXEL_FORMAT_BYTES) == null) return null;
    const format = state.read32(format_address);
    const bits = state.read8(format_address + 16);
    const bytes = state.read8(format_address + 17);
    const rmask = state.read32(format_address + 20);
    const gmask = state.read32(format_address + 24);
    const bmask = state.read32(format_address + 28);
    const amask = state.read32(format_address + 32);
    if (format != 0) {
        if (decodePixelInfo(format)) |decoded| {
            if (decoded.kind == 3 or decoded.kind == 7) return decoded;
            var value = decoded;
            value.rmask = if (rmask != 0) rmask else decoded.rmask;
            value.gmask = if (gmask != 0) gmask else decoded.gmask;
            value.bmask = if (bmask != 0) bmask else decoded.bmask;
            value.amask = if (amask != 0) amask else decoded.amask;
            return value;
        }
    }
    if (bytes == 0 or bytes > 4 or bits == 0) return null;
    return .{ .bytes = bytes, .bits = bits, .kind = 0, .order = 0, .layout = 0, .rmask = rmask, .gmask = gmask, .bmask = bmask, .amask = amask };
}

fn writePixelFormat(state: anytype, address: u64, format: u32, info: PixelInfo, masks: [4]u32, palette: u64) bool {
    if (state.guestMemory(address, SDL_PIXEL_FORMAT_BYTES) == null) return false;
    state.write32(address, format);
    state.write64(address + 8, palette);
    // SDL encodes XRGB8888 as 24 meaningful RGB bits in four bytes. The
    // OpenTyrian scaler table, however, only has 16-bit and 32-bit kernels
    // and selects one from SDL_PixelFormat.BitsPerPixel. Give packed 32-bit
    // storage the 32-bit storage width that this consumer expects, while
    // keeping the enum and channel masks intact for pixel conversion.
    state.write8(address + 16, guestStorageBits(info));
    state.write8(address + 17, info.bytes);
    state.write32(address + 20, masks[0]);
    state.write32(address + 24, masks[1]);
    state.write32(address + 28, masks[2]);
    state.write32(address + 32, masks[3]);
    state.write8(address + 40, trailingShift(masks[0]));
    state.write8(address + 41, trailingShift(masks[1]));
    state.write8(address + 42, trailingShift(masks[2]));
    state.write8(address + 43, trailingShift(masks[3]));
    state.write32(address + 44, 1);
    return true;
}

fn guestStorageBits(info: PixelInfo) u8 {
    if (info.kind == 6 and info.layout == 6 and info.bytes == 4) return 32;
    return info.bits;
}

fn initializePalette(state: anytype, palette: u64, colors: u64) bool {
    if (palette == 0 or colors == 0) return false;
    if (!write32(state, palette, 256) or !write64(state, palette + 8, colors)) return false;
    if (!write32(state, palette + 16, 1) or !write32(state, palette + 20, 1)) return false;
    const bytes = state.guestMemory(colors, 1024) orelse return false;
    for (0..256) |index| {
        const shade: u8 = @intCast(index);
        const offset = index * 4;
        bytes[offset] = shade;
        bytes[offset + 1] = shade;
        bytes[offset + 2] = shade;
        bytes[offset + 3] = 255;
    }
    return true;
}

fn findSurfaceRecord(state: anytype, surface: u64) ?*std.meta.Child(@TypeOf(state.windows_sdl.surface_records)) {
    for (&state.windows_sdl.surface_records) |*record| if (record.surface == surface and surface != 0) return record;
    return null;
}

fn findFormatRecord(state: anytype, format: u64) ?*std.meta.Child(@TypeOf(state.windows_sdl.surface_records)) {
    for (&state.windows_sdl.surface_records) |*record| if (record.format == format and record.surface == 0 and format != 0) return record;
    return null;
}

fn findTextureRecord(state: anytype, texture_handle: u64) ?*std.meta.Child(@TypeOf(state.windows_sdl.texture_records)) {
    for (&state.windows_sdl.texture_records) |*record| if (record.handle == texture_handle and texture_handle != 0) return record;
    return null;
}

fn emptySurfaceRecord(state: anytype) ?*std.meta.Child(@TypeOf(state.windows_sdl.surface_records)) {
    for (&state.windows_sdl.surface_records) |*record| if (record.surface == 0 and record.format == 0) return record;
    return null;
}

fn emptyTextureRecord(state: anytype) ?*std.meta.Child(@TypeOf(state.windows_sdl.texture_records)) {
    for (&state.windows_sdl.texture_records) |*record| if (record.handle == 0) return record;
    return null;
}

fn releaseSurfaceRecord(state: anytype, record: anytype) void {
    if (record.pixels != 0) _ = state.releaseGuestAllocation(record.pixels);
    if (record.palette_colors != 0) _ = state.releaseGuestAllocation(record.palette_colors);
    if (record.palette != 0) _ = state.releaseGuestAllocation(record.palette);
    if (record.format != 0) _ = state.releaseGuestAllocation(record.format);
    if (record.surface != 0) _ = state.releaseGuestAllocation(record.surface);
    record.* = .{};
}

fn createSurface(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const width64 = arg(api, state, 1, direct_return_rip);
    const height64 = arg(api, state, 2, direct_return_rip);
    const depth64 = arg(api, state, 3, direct_return_rip);
    if (width64 == 0 or height64 == 0 or width64 > MAX_DIMENSION or height64 > MAX_DIMENSION or depth64 > 32) {
        setError(api, state, "SDL_CreateRGBSurface received an unsupported extent or depth");
        finish(api, state, 0, direct_return_rip);
        return;
    }
    const depth: u8 = @intCast(depth64);
    const masks = [4]u32{ @truncate(arg(api, state, 4, direct_return_rip)), @truncate(arg(api, state, 5, direct_return_rip)), @truncate(arg(api, state, 6, direct_return_rip)), @truncate(arg(api, state, 7, direct_return_rip)) };
    const info = formatFromMasks(depth, masks[0], masks[1], masks[2], masks[3]) orelse {
        setError(api, state, "SDL_CreateRGBSurface pixel layout is unsupported");
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const width: u32 = @intCast(width64);
    const height: u32 = @intCast(height64);
    const pitch = std.math.mul(u32, width, info.bytes) catch {
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const pixels_size = std.math.mul(u64, pitch, height) catch {
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const record = emptySurfaceRecord(state) orelse {
        setError(api, state, "Rosetta SDL surface table is full");
        finish(api, state, 0, direct_return_rip);
        return;
    };
    var fresh: @TypeOf(record.*) = .{};
    errdefer releaseSurfaceRecord(state, &fresh);
    fresh.surface = alloc(api, state, SDL_SURFACE_BYTES, 8) orelse 0;
    fresh.format = alloc(api, state, SDL_PIXEL_FORMAT_BYTES, 8) orelse 0;
    fresh.pixels = alloc(api, state, pixels_size, 16) orelse 0;
    if (fresh.surface == 0 or fresh.format == 0 or fresh.pixels == 0) {
        setError(api, state, "SDL_CreateRGBSurface could not allocate guest storage");
        finish(api, state, 0, direct_return_rip);
        return;
    }
    if (info.bits == 8 and info.rmask == 0 and info.gmask == 0 and info.bmask == 0) {
        fresh.palette = alloc(api, state, SDL_PALETTE_BYTES, 8) orelse 0;
        fresh.palette_colors = alloc(api, state, 1024, 4) orelse 0;
        if (fresh.palette == 0 or fresh.palette_colors == 0 or !initializePalette(state, fresh.palette, fresh.palette_colors)) {
            setError(api, state, "SDL_CreateRGBSurface could not allocate its indexed palette");
            finish(api, state, 0, direct_return_rip);
            return;
        }
    }
    const pixel_format = if (info.bits == 8 and fresh.palette != 0) SDL_PIXELFORMAT_INDEX8 else 0;
    if (!writePixelFormat(state, fresh.format, pixel_format, info, masks, fresh.palette)) {
        setError(api, state, "SDL_CreateRGBSurface could not initialize its pixel format");
        finish(api, state, 0, direct_return_rip);
        return;
    }
    if (state.guestMemory(fresh.surface, SDL_SURFACE_BYTES) == null) {
        setError(api, state, "SDL_CreateRGBSurface could not initialize its descriptor");
        finish(api, state, 0, direct_return_rip);
        return;
    }
    state.write64(fresh.surface + 8, fresh.format);
    state.write32(fresh.surface + 16, width);
    state.write32(fresh.surface + 20, height);
    state.write32(fresh.surface + 24, pitch);
    state.write64(fresh.surface + 32, fresh.pixels);
    record.* = fresh;
    api._log.info("PE64 SDL software surface: created={d}x{d} depth={d} pitch={d} format=0x{x} handle=0x{x}", .{ width, height, depth, pitch, pixel_format, fresh.surface });
    finish(api, state, fresh.surface, direct_return_rip);
}

fn freeSurface(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const surface = arg(api, state, 0, direct_return_rip);
    if (findSurfaceRecord(state, surface)) |record| {
        releaseSurfaceRecord(state, record);
    } else if (surface != 0) {
        setError(api, state, "SDL_FreeSurface received an unknown Rosetta surface");
    }
    finish(api, state, 0, direct_return_rip);
}

fn allocFormat(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const pixel_format = @as(u32, @truncate(arg(api, state, 0, direct_return_rip)));
    const info = decodePixelInfo(pixel_format) orelse {
        setError(api, state, "SDL_AllocFormat received an unsupported SDL pixel format");
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const record = emptySurfaceRecord(state) orelse {
        setError(api, state, "Rosetta SDL format table is full");
        finish(api, state, 0, direct_return_rip);
        return;
    };
    var fresh: @TypeOf(record.*) = .{};
    errdefer releaseSurfaceRecord(state, &fresh);
    fresh.format = alloc(api, state, SDL_PIXEL_FORMAT_BYTES, 8) orelse 0;
    if (fresh.format == 0) {
        finish(api, state, 0, direct_return_rip);
        return;
    }
    if (info.kind == 3) {
        fresh.palette = alloc(api, state, SDL_PALETTE_BYTES, 8) orelse 0;
        fresh.palette_colors = alloc(api, state, 1024, 4) orelse 0;
        if (fresh.palette == 0 or fresh.palette_colors == 0 or !initializePalette(state, fresh.palette, fresh.palette_colors)) {
            setError(api, state, "SDL_AllocFormat could not allocate its indexed palette");
            finish(api, state, 0, direct_return_rip);
            return;
        }
    }
    const masks = [4]u32{ info.rmask, info.gmask, info.bmask, info.amask };
    if (!writePixelFormat(state, fresh.format, pixel_format, info, masks, fresh.palette)) {
        finish(api, state, 0, direct_return_rip);
        return;
    }
    api._log.info("PE64 SDL pixel format: enum=0x{x} meaningful_bits={d} guest_storage_bits={d} bytes={d}", .{
        pixel_format,
        info.bits,
        guestStorageBits(info),
        info.bytes,
    });
    record.* = fresh;
    finish(api, state, fresh.format, direct_return_rip);
}

fn freeFormat(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const format = arg(api, state, 0, direct_return_rip);
    if (findFormatRecord(state, format)) |record| releaseSurfaceRecord(state, record);
    finish(api, state, 0, direct_return_rip);
}

fn mapRgb(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const format = arg(api, state, 0, direct_return_rip);
    const info = formatInfoFromGuest(state, format) orelse {
        setError(api, state, "SDL_MapRGB received an invalid pixel format");
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const masks = [4]u32{ state.read32(format + 20), state.read32(format + 24), state.read32(format + 28), state.read32(format + 32) };
    const palette = state.read64(format + 8);
    const color = RGBA{ .r = @truncate(arg(api, state, 1, direct_return_rip)), .g = @truncate(arg(api, state, 2, direct_return_rip)), .b = @truncate(arg(api, state, 3, direct_return_rip)) };
    var pixel: u32 = channelToMask(color.r, masks[0]) | channelToMask(color.g, masks[1]) | channelToMask(color.b, masks[2]);
    if (info.bytes == 1 and masks[0] == 0 and masks[1] == 0 and masks[2] == 0 and palette != 0) {
        const colors = state.read64(palette + 8);
        var best: u32 = std.math.maxInt(u32);
        for (0..256) |index| {
            const bytes = state.guestMemoryConst(colors + index * 4, 4) orelse break;
            const dr = @as(i32, color.r) - bytes[0];
            const dg = @as(i32, color.g) - bytes[1];
            const db = @as(i32, color.b) - bytes[2];
            const distance: u32 = @intCast(dr * dr + dg * dg + db * db);
            if (distance < best) {
                best = distance;
                pixel = @intCast(index);
            }
            if (distance == 0) break;
        }
    }
    finish(api, state, pixel, direct_return_rip);
}

fn surfaceDescriptor(state: anytype, surface: u64) ?struct { pixels: u64, format: u64, palette: u64, width: u32, height: u32, pitch: u32, info: PixelInfo } {
    if (findSurfaceRecord(state, surface) == null or state.guestMemoryConst(surface, SDL_SURFACE_BYTES) == null) return null;
    const format = state.read64(surface + 8);
    const pixels = state.read64(surface + 32);
    const width = state.read32(surface + 16);
    const height = state.read32(surface + 20);
    const pitch = state.read32(surface + 24);
    const info = formatInfoFromGuest(state, format) orelse return null;
    if (width == 0 or height == 0 or width > MAX_DIMENSION or height > MAX_DIMENSION or pitch < width * info.bytes) return null;
    const pixel_bytes = std.math.mul(u64, pitch, height) catch return null;
    if (state.guestMemory(pixels, pixel_bytes) == null) return null;
    return .{ .pixels = pixels, .format = format, .palette = state.read64(format + 8), .width = width, .height = height, .pitch = pitch, .info = info };
}

fn fillRect(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const surface_address = arg(api, state, 0, direct_return_rip);
    const descriptor = surfaceDescriptor(state, surface_address) orelse {
        setError(api, state, "SDL_FillRect received an invalid surface");
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const rect = readRect(state, arg(api, state, 1, direct_return_rip), .{ .x = 0, .y = 0, .w = @intCast(descriptor.width), .h = @intCast(descriptor.height) }) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const color = @as(u32, @truncate(arg(api, state, 2, direct_return_rip)));
    const x0: u32 = @intCast(@max(rect.x, 0));
    const y0: u32 = @intCast(@max(rect.y, 0));
    const x1: u32 = @intCast(@min(@as(i64, rect.x) + rect.w, descriptor.width));
    const y1: u32 = @intCast(@min(@as(i64, rect.y) + rect.h, descriptor.height));
    if (x1 > x0 and y1 > y0) {
        for (y0..y1) |y| for (x0..x1) |x| {
            const pixel = descriptor.pixels + @as(u64, y) * descriptor.pitch + @as(u64, x) * descriptor.info.bytes;
            _ = writePacked(state, pixel, descriptor.info.bytes, color);
        };
    }
    finish(api, state, 0, direct_return_rip);
}

fn blitSurface(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const source = surfaceDescriptor(state, arg(api, state, 0, direct_return_rip)) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const destination_address = arg(api, state, 2, direct_return_rip);
    const destination = surfaceDescriptor(state, destination_address) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const source_rect = readRect(state, arg(api, state, 1, direct_return_rip), .{ .x = 0, .y = 0, .w = @intCast(source.width), .h = @intCast(source.height) }) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const dest_rect_ptr = arg(api, state, 3, direct_return_rip);
    const dest_rect = readRect(state, dest_rect_ptr, .{ .x = 0, .y = 0, .w = source_rect.w, .h = source_rect.h }) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    if (source_rect.w <= 0 or source_rect.h <= 0 or dest_rect.w <= 0 or dest_rect.h <= 0) {
        finish(api, state, 0, direct_return_rip);
        return;
    }
    const copy_width: u32 = @intCast(@min(source_rect.w, dest_rect.w));
    const copy_height: u32 = @intCast(@min(source_rect.h, dest_rect.h));
    for (0..copy_height) |dy| for (0..copy_width) |dx| {
        const sx: i64 = @as(i64, source_rect.x) + @as(i64, @intCast(dx));
        const sy: i64 = @as(i64, source_rect.y) + @as(i64, @intCast(dy));
        const tx: i64 = @as(i64, dest_rect.x) + @as(i64, @intCast(dx));
        const ty: i64 = @as(i64, dest_rect.y) + @as(i64, @intCast(dy));
        if (sx < 0 or sy < 0 or tx < 0 or ty < 0 or sx >= source.width or sy >= source.height or tx >= destination.width or ty >= destination.height) continue;
        const source_pixel = source.pixels + @as(u64, @intCast(sy)) * source.pitch + @as(u64, @intCast(sx)) * source.info.bytes;
        const dest_pixel = destination.pixels + @as(u64, @intCast(ty)) * destination.pitch + @as(u64, @intCast(tx)) * destination.info.bytes;
        const color = readFormatPixel(state, source_pixel, source.info, source.palette) orelse continue;
        _ = writeFormatPixel(state, dest_pixel, destination.info, destination.palette, color);
    };
    if (dest_rect_ptr != 0 and state.guestMemory(dest_rect_ptr, 16) != null) {
        state.write32(dest_rect_ptr + 8, copy_width);
        state.write32(dest_rect_ptr + 12, copy_height);
    }
    finish(api, state, 0, direct_return_rip);
}

fn allocateRendererPixels(comptime api: type, state: anytype, width: u32, height: u32) ?struct { address: u64, pitch: u32 } {
    if (width == 0 or height == 0 or width > MAX_DIMENSION or height > MAX_DIMENSION) return null;
    const pitch = std.math.mul(u32, width, 4) catch return null;
    const size = std.math.mul(u64, pitch, height) catch return null;
    return .{ .address = alloc(api, state, size, 16) orelse return null, .pitch = pitch };
}

fn createRenderer(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const window = arg(api, state, 0, direct_return_rip);
    if (window == 0 or window != state.windows_sdl.window) {
        setError(api, state, "SDL_CreateRenderer received an invalid window");
        finish(api, state, 0, direct_return_rip);
        return;
    }
    if (state.windows_sdl.renderer != 0) {
        finish(api, state, state.windows_sdl.renderer, direct_return_rip);
        return;
    }
    const width = state.windows_graphics.window_width;
    const height = state.windows_graphics.window_height;
    const output = allocateRendererPixels(api, state, width, height) orelse {
        setError(api, state, "SDL_CreateRenderer could not allocate a bounded software target");
        finish(api, state, 0, direct_return_rip);
        return;
    };
    state.windows_sdl.renderer_pixels = output.address;
    state.windows_sdl.renderer_width = width;
    state.windows_sdl.renderer_height = height;
    state.windows_sdl.renderer_pitch = output.pitch;
    state.windows_sdl.renderer = api._nextHandle(state);
    state.windows_sdl.error_message = 0;
    api._log.info("PE64 SDL software renderer: window=0x{x} size={d}x{d} frame=0x{x} renderer=0x{x}", .{ window, width, height, output.address, state.windows_sdl.renderer });
    finish(api, state, state.windows_sdl.renderer, direct_return_rip);
}

fn destroyRenderer(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const renderer_handle = arg(api, state, 0, direct_return_rip);
    if (renderer_handle != 0 and renderer_handle == state.windows_sdl.renderer) {
        if (state.windows_sdl.renderer_pixels != 0) _ = state.releaseGuestAllocation(state.windows_sdl.renderer_pixels);
        state.windows_sdl.renderer = 0;
        state.windows_sdl.renderer_pixels = 0;
        state.windows_sdl.renderer_width = 0;
        state.windows_sdl.renderer_height = 0;
        state.windows_sdl.renderer_pitch = 0;
        for (&state.windows_sdl.texture_records) |*record| {
            if (record.pixels != 0) _ = state.releaseGuestAllocation(record.pixels);
            record.* = .{};
        }
    }
    finish(api, state, 0, direct_return_rip);
}

fn createTexture(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const renderer = arg(api, state, 0, direct_return_rip);
    const format = @as(u32, @truncate(arg(api, state, 1, direct_return_rip)));
    const access = @as(u32, @truncate(arg(api, state, 2, direct_return_rip)));
    const width64 = arg(api, state, 3, direct_return_rip);
    // The fifth Windows x64 argument occupies an eight-byte stack slot, but
    // SDL declares height as a 32-bit int. The upper half of that slot is
    // caller scratch and may be nonzero, so never validate or size from it.
    const height32: u32 = @truncate(arg(api, state, 4, direct_return_rip));
    const height64: u64 = height32;
    const info = decodePixelInfo(format) orelse {
        setError(api, state, "SDL_CreateTexture pixel format is not supported by the software renderer");
        api._log.err("PE64 SDL texture creation refused: unsupported format=0x{x} renderer=0x{x} active_renderer=0x{x}", .{ format, renderer, state.windows_sdl.renderer });
        finish(api, state, 0, direct_return_rip);
        return;
    };
    if (renderer == 0 or renderer != state.windows_sdl.renderer or width64 == 0 or height64 == 0 or width64 > MAX_DIMENSION or height64 > MAX_DIMENSION) {
        setError(api, state, "SDL_CreateTexture received an invalid renderer or extent");
        api._log.err("PE64 SDL texture creation refused: renderer=0x{x} active_renderer=0x{x} extent={d}x{d}", .{ renderer, state.windows_sdl.renderer, width64, height64 });
        finish(api, state, 0, direct_return_rip);
        return;
    }
    const width: u32 = @intCast(width64);
    const height: u32 = @intCast(height64);
    const raw_pitch = std.math.mul(u32, width, info.bytes) catch {
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const aligned_pitch = std.math.add(u32, raw_pitch, 3) catch {
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const pitch = aligned_pitch & ~@as(u32, 3);
    const size = std.math.mul(u64, pitch, height) catch {
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const record = emptyTextureRecord(state) orelse {
        setError(api, state, "Rosetta SDL texture table is full");
        api._log.err("PE64 SDL texture creation refused: texture table full format=0x{x} extent={d}x{d}", .{ format, width, height });
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const pixels = alloc(api, state, size, 16) orelse {
        setError(api, state, "SDL_CreateTexture could not allocate guest pixel storage");
        api._log.err("PE64 SDL texture creation refused: guest pixel allocation failed bytes={d}", .{size});
        finish(api, state, 0, direct_return_rip);
        return;
    };
    const texture_handle = api._nextHandle(state);
    record.* = .{ .handle = texture_handle, .pixels = pixels, .format = format, .access = access, .width = width, .height = height, .pitch = pitch };
    state.windows_sdl.error_message = 0;
    api._log.info("PE64 SDL software texture: format=0x{x} access={d} size={d}x{d} pitch={d} handle=0x{x}", .{ format, access, width, height, pitch, texture_handle });
    finish(api, state, texture_handle, direct_return_rip);
}

fn destroyTexture(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const texture_handle = arg(api, state, 0, direct_return_rip);
    if (findTextureRecord(state, texture_handle)) |record| {
        _ = state.releaseGuestAllocation(record.pixels);
        record.* = .{};
    }
    finish(api, state, 0, direct_return_rip);
}

fn showSimpleMessageBox(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const title_address = arg(api, state, 1, direct_return_rip);
    const message_address = arg(api, state, 2, direct_return_rip);
    const title = api._guestCString(state, title_address) orelse "<unreadable title>";
    const message = api._guestCString(state, message_address) orelse "<unreadable message>";
    api._log.err("PE64 SDL message box: title='{s}' message='{s}'", .{ title, message });
    // Rosetta has no modal SDL dialog for a PE software-renderer guest. Report
    // success so the guest can follow its ordinary cleanup/error path.
    finish(api, state, 0, direct_return_rip);
}

fn queryTexture(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const texture_handle = arg(api, state, 0, direct_return_rip);
    const record = findTextureRecord(state, texture_handle) orelse {
        setError(api, state, "SDL_QueryTexture received an unknown texture");
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const outputs = [4]u64{ arg(api, state, 1, direct_return_rip), arg(api, state, 2, direct_return_rip), arg(api, state, 3, direct_return_rip), arg(api, state, 4, direct_return_rip) };
    const values = [4]u32{ record.format, record.access, record.width, record.height };
    for (outputs, values) |address, value| if (address != 0 and !write32(state, address, value)) {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    finish(api, state, 0, direct_return_rip);
}

fn lockTexture(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    // SDL_LockTexture is a four-argument API: (texture, rect, pixels**, pitch*).
    // Keeping the original arg1/arg2/arg3/arg4 indexing shifted every output
    // by one, so the guest ignored the failure and used an uninitialized pixel
    // pointer in its scaler.
    const record = findTextureRecord(state, arg(api, state, 0, direct_return_rip)) orelse {
        setError(api, state, "SDL_LockTexture received an unknown texture");
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const rect = readRect(state, arg(api, state, 1, direct_return_rip), .{ .x = 0, .y = 0, .w = @intCast(record.width), .h = @intCast(record.height) }) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    if (rect.x < 0 or rect.y < 0 or rect.x >= record.width or rect.y >= record.height) {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    }
    const info = decodePixelInfo(record.format) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const pixels_out = arg(api, state, 2, direct_return_rip);
    const pitch_out = arg(api, state, 3, direct_return_rip);
    const pixel_address = record.pixels + @as(u64, @intCast(rect.y)) * record.pitch + @as(u64, @intCast(rect.x)) * info.bytes;
    if (pixels_out == 0 or pitch_out == 0 or !write64(state, pixels_out, pixel_address) or !write32(state, pitch_out, record.pitch)) {
        setError(api, state, "SDL_LockTexture output pointers are invalid");
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    }
    finish(api, state, 0, direct_return_rip);
}

fn unlockTexture(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    _ = findTextureRecord(state, arg(api, state, 0, direct_return_rip));
    finish(api, state, 0, direct_return_rip);
}

fn setDrawColor(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    if (arg(api, state, 0, direct_return_rip) != state.windows_sdl.renderer) {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    }
    state.windows_sdl.draw_color = .{ @truncate(arg(api, state, 1, direct_return_rip)), @truncate(arg(api, state, 2, direct_return_rip)), @truncate(arg(api, state, 3, direct_return_rip)), @truncate(arg(api, state, 4, direct_return_rip)) };
    finish(api, state, 0, direct_return_rip);
}

fn renderClear(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const renderer = arg(api, state, 0, direct_return_rip);
    if (renderer == 0 or renderer != state.windows_sdl.renderer or state.windows_sdl.renderer_pixels == 0) {
        setError(api, state, "SDL_RenderClear received an invalid renderer");
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    }
    const pixels = state.guestMemory(state.windows_sdl.renderer_pixels, @as(u64, state.windows_sdl.renderer_pitch) * state.windows_sdl.renderer_height) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const color = state.windows_sdl.draw_color;
    for (pixels, 0..) |*byte, index| byte.* = color[index % 4];
    finish(api, state, 0, direct_return_rip);
}

fn renderCopy(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const renderer = arg(api, state, 0, direct_return_rip);
    const texture = findTextureRecord(state, arg(api, state, 1, direct_return_rip)) orelse {
        setError(api, state, "SDL_RenderCopy received an unknown texture");
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    if (renderer == 0 or renderer != state.windows_sdl.renderer) {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    }
    const source = readRect(state, arg(api, state, 2, direct_return_rip), .{ .x = 0, .y = 0, .w = @intCast(texture.width), .h = @intCast(texture.height) }) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const destination = readRect(state, arg(api, state, 3, direct_return_rip), .{ .x = 0, .y = 0, .w = @intCast(state.windows_sdl.renderer_width), .h = @intCast(state.windows_sdl.renderer_height) }) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    if (source.w <= 0 or source.h <= 0 or destination.w <= 0 or destination.h <= 0) {
        finish(api, state, 0, direct_return_rip);
        return;
    }
    const info = decodePixelInfo(texture.format) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    const dst = state.guestMemory(state.windows_sdl.renderer_pixels, @as(u64, state.windows_sdl.renderer_pitch) * state.windows_sdl.renderer_height) orelse {
        finish(api, state, @bitCast(@as(i64, -1)), direct_return_rip);
        return;
    };
    _ = dst;
    for (0..@as(u32, @intCast(destination.h))) |dy| for (0..@as(u32, @intCast(destination.w))) |dx| {
        const tx = @as(i64, source.x) + @divTrunc(@as(i64, @intCast(dx)) * source.w, destination.w);
        const ty = @as(i64, source.y) + @divTrunc(@as(i64, @intCast(dy)) * source.h, destination.h);
        const dx_guest = @as(i64, destination.x) + @as(i64, @intCast(dx));
        const dy_guest = @as(i64, destination.y) + @as(i64, @intCast(dy));
        if (tx < 0 or ty < 0 or tx >= texture.width or ty >= texture.height or dx_guest < 0 or dy_guest < 0 or dx_guest >= state.windows_sdl.renderer_width or dy_guest >= state.windows_sdl.renderer_height) continue;
        const source_pixel = texture.pixels + @as(u64, @intCast(ty)) * texture.pitch + @as(u64, @intCast(tx)) * info.bytes;
        const rgba = readFormatPixel(state, source_pixel, info, 0) orelse continue;
        const dest_pixel = state.windows_sdl.renderer_pixels + @as(u64, @intCast(dy_guest)) * state.windows_sdl.renderer_pitch + @as(u64, @intCast(dx_guest)) * 4;
        const bytes = state.guestMemory(dest_pixel, 4) orelse continue;
        bytes[0] = rgba.r;
        bytes[1] = rgba.g;
        bytes[2] = rgba.b;
        bytes[3] = rgba.a;
    };
    finish(api, state, 0, direct_return_rip);
}

fn renderPresent(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const renderer = arg(api, state, 0, direct_return_rip);
    const callback = state.windows_graphics.hooks.native_present_guest_pixels;
    if (renderer == 0 or renderer != state.windows_sdl.renderer or state.windows_sdl.renderer_pixels == 0 or callback == null) {
        setError(api, state, "SDL_RenderPresent has no valid native pixel-present route");
        finish(api, state, 0, direct_return_rip);
        return;
    }
    state.windows_sdl.present_count +|= 1;
    const presented = callback.?(
        state.windows_graphics.hooks.native_context,
        state,
        state.windows_sdl.renderer_pixels,
        state.windows_sdl.renderer_width,
        state.windows_sdl.renderer_height,
        state.windows_sdl.renderer_pitch,
    ) != 0;
    if (presented) {
        state.windows_graphics.noteGuestFramePresented();
        if (state.windows_sdl.present_count <= 3 or state.windows_sdl.present_count % 120 == 0) {
            api._log.info("PE64 SDL software frame: present={d} size={d}x{d} pixels=0x{x}", .{ state.windows_sdl.present_count, state.windows_sdl.renderer_width, state.windows_sdl.renderer_height, state.windows_sdl.renderer_pixels });
        }
        state.windows_sdl.error_message = 0;
    } else {
        setError(api, state, "native Metal window rejected the SDL software frame");
    }
    finish(api, state, 0, direct_return_rip);
}

fn getPixelFormatName(comptime api: type, state: anytype, direct_return_rip: ?u64) void {
    const value = @as(u32, @truncate(arg(api, state, 0, direct_return_rip)));
    const name: []const u8 = switch (value) {
        SDL_PIXELFORMAT_INDEX8 => "SDL_PIXELFORMAT_INDEX8",
        SDL_PIXELFORMAT_XRGB8888 => "SDL_PIXELFORMAT_XRGB8888",
        else => if (decodePixelInfo(value) != null) "SDL_PIXELFORMAT_SUPPORTED" else "SDL_PIXELFORMAT_UNKNOWN",
    };
    finish(api, state, api._materializeGuestAnsi(state, name) orelse 0, direct_return_rip);
}

test "SDL software pixel formats decode common 8, 16, 24 and 32 bit layouts" {
    try std.testing.expectEqual(@as(u8, 1), decodePixelInfo(SDL_PIXELFORMAT_INDEX8).?.bytes);
    try std.testing.expectEqual(@as(u8, 4), decodePixelInfo(SDL_PIXELFORMAT_XRGB8888).?.bytes);
    try std.testing.expectEqual(@as(u8, 32), guestStorageBits(decodePixelInfo(SDL_PIXELFORMAT_XRGB8888).?));
    const rgb565: u32 = 0x15151002;
    try std.testing.expect(decodePixelInfo(rgb565) != null);
    try std.testing.expectEqual(@as(u8, 16), guestStorageBits(decodePixelInfo(rgb565).?));
    const rgba32: u32 = 0x16762004;
    try std.testing.expect(decodePixelInfo(rgba32) != null);
    try std.testing.expect(decodePixelInfo(0xDEADBEEF) == null);
}
