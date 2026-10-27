//! Bounded GDI object and DIB pixel-storage shims for the PE32 compatibility
//! path. Window presentation and OpenGL rendering belong to the native bridge.
const std = @import("std");
const testing = std.testing;
const Executor = @import("../instruction_operations.zig").Executor;
const abi = @import("../abi_handshake.zig");
const heap = @import("../heap/runtime.zig");

const stock_handle_base: u32 = 0xF100_0000;
const stock_object_count: u32 = 20;
const stock_bitmap_handle: u32 = 0xF300_0001;
pub const window_dc_handle: u32 = 0xF500_0001;
const memory_dc_handle: u32 = 0xF500_0002;
const bitmap_handle_base: u32 = 0xF200_0000;
const pixel_format_count: u32 = 1;
const bitmap_info_header_size: usize = 40;
const bitmap_object_size: usize = 24;
const max_bitmap_bytes: u64 = 64 * 1024 * 1024;

fn glTraceEnabled() bool {
    const value = std.c.getenv("ROSETTE_PE32_GL_TRACE") orelse return false;
    return value[0] != 0 and value[0] != '0';
}

fn guestSlice(ex: *Executor, address: u32, length: usize) ?[]u8 {
    if (address < ex.mem.base) return null;
    const offset: usize = @intCast(address - ex.mem.base);
    if (offset > ex.mem.data.len or length > ex.mem.data.len - offset) return null;
    return ex.mem.data[offset .. offset + length];
}

fn validDeviceContext(device_context: u32) bool {
    return device_context == window_dc_handle or device_context == memory_dc_handle;
}

fn dcIndex(device_context: u32) ?usize {
    return switch (device_context) {
        window_dc_handle => 0,
        memory_dc_handle => 1,
        else => null,
    };
}

fn isStockBitmap(handle: u32) bool {
    return handle == stock_bitmap_handle;
}

fn findBitmap(ex: *Executor, handle: u32) ?*Executor.Pe32GdiBitmap {
    for (&ex.pe32_gdi_bitmaps) |*bitmap| {
        if (bitmap.active and bitmap.handle == handle) return bitmap;
    }
    return null;
}

fn makeBitmap(ex: *Executor, width: i32, height: i32, bit_count: u16, compression: u32) ?u32 {
    if (width <= 0 or height == 0 or height == std.math.minInt(i32)) return null;
    if (bit_count != 1 and bit_count != 4 and bit_count != 8 and bit_count != 16 and
        bit_count != 24 and bit_count != 32) return null;
    if (compression != 0 and compression != 3) return null; // BI_RGB / BI_BITFIELDS

    const abs_height: u64 = @intCast(if (height < 0) -@as(i64, height) else height);
    const row_bits = @as(u64, @intCast(width)) * @as(u64, bit_count);
    const row_stride = ((row_bits + 31) / 32) * 4;
    const byte_size = row_stride * abs_height;
    if (row_stride == 0 or byte_size == 0 or byte_size > max_bitmap_bytes or
        row_stride > std.math.maxInt(u32) or byte_size > std.math.maxInt(u32)) return null;

    var free_slot: ?*Executor.Pe32GdiBitmap = null;
    for (&ex.pe32_gdi_bitmaps) |*bitmap| {
        if (!bitmap.active) {
            free_slot = bitmap;
            break;
        }
    }
    const record = free_slot orelse return null;
    const allocation_size: u32 = @intCast(byte_size);
    const bits = heap.alloc("CreateDIBSection", heap.process_heap_handle, 0, allocation_size);
    const pixel_bytes = guestSlice(ex, bits, allocation_size) orelse {
        _ = heap.free("CreateDIBSection", heap.process_heap_handle, 0, bits);
        return null;
    };
    @memset(pixel_bytes, 0);

    var handle = ex.pe32_gdi_next_bitmap_handle;
    if (handle < bitmap_handle_base or handle == std.math.maxInt(u32)) handle = bitmap_handle_base | 1;
    ex.pe32_gdi_next_bitmap_handle = handle +% 1;
    record.* = .{
        .active = true,
        .handle = handle,
        .bits = bits,
        .width = @intCast(width),
        .height = height,
        .bit_count = bit_count,
        .compression = compression,
        .row_stride = @intCast(row_stride),
        .byte_size = allocation_size,
    };
    return handle;
}

fn bitmapHeader(ex: *Executor, address: u32) ?struct { width: i32, height: i32, bit_count: u16, compression: u32, header_size: u32, colors_used: u32 } {
    const header = guestSlice(ex, address, bitmap_info_header_size) orelse return null;
    const header_size = std.mem.readInt(u32, header[0..4], .little);
    if (header_size < bitmap_info_header_size) return null;
    const width = std.mem.readInt(i32, header[4..8], .little);
    const height = std.mem.readInt(i32, header[8..12], .little);
    const planes = std.mem.readInt(u16, header[12..14], .little);
    const bit_count = std.mem.readInt(u16, header[14..16], .little);
    const compression = std.mem.readInt(u32, header[16..20], .little);
    const colors_used = std.mem.readInt(u32, header[32..36], .little);
    if (width <= 0 or height == 0 or planes != 1) return null;
    return .{ .width = width, .height = height, .bit_count = bit_count, .compression = compression, .header_size = header_size, .colors_used = colors_used };
}

const DibColor = struct { red: u8, green: u8, blue: u8 };

fn dibStride(width: usize, bit_count: u16) ?usize {
    const row_bits = std.math.mul(usize, width, bit_count) catch return null;
    const rounded_bits = std.math.add(usize, row_bits, 31) catch return null;
    return (rounded_bits / 32) * 4;
}

fn dibSourceColor(ex: *Executor, source_row: []const u8, info_address: u32, info: anytype, x: usize, usage: u32) ?DibColor {
    const bpp = info.bit_count;
    const pixel_offset: usize = switch (bpp) {
        1 => x / 8,
        4 => x / 2,
        8 => x,
        16 => x * 2,
        24 => x * 3,
        32 => x * 4,
        else => return null,
    };
    const input_bytes: usize = if (bpp <= 8) 1 else if (bpp == 24) 3 else if (bpp == 32) 4 else 2;
    if (pixel_offset > source_row.len or input_bytes > source_row.len - pixel_offset) return null;
    switch (bpp) {
        1, 4, 8 => {
            const index: usize = switch (bpp) {
                1 => (source_row[pixel_offset] >> @as(u3, @intCast(7 - (x & 7)))) & 1,
                4 => if (x & 1 == 0) source_row[pixel_offset] >> 4 else source_row[pixel_offset] & 0x0F,
                else => source_row[pixel_offset],
            };
            if (usage == 1) return null; // DIB_PAL_COLORS needs a selected logical palette.
            const default_count: u32 = @as(u32, 1) << @intCast(bpp);
            const color_count = if (info.colors_used == 0) default_count else info.colors_used;
            if (index >= color_count) return null;
            const color_offset = std.math.mul(usize, index, 4) catch return null;
            const palette_offset = std.math.add(usize, info.header_size, color_offset) catch return null;
            const palette_address = std.math.add(u32, info_address, @intCast(palette_offset)) catch return null;
            const color = guestSlice(ex, palette_address, 4) orelse return null;
            return .{ .blue = color[0], .green = color[1], .red = color[2] };
        },
        16 => {
            const value = std.mem.readInt(u16, source_row[pixel_offset..][0..2], .little);
            // BI_RGB 16-bit DIB pixels use 5:5:5. BI_BITFIELDS masks are
            // handled by the source-mask path once a 40-byte header supplies
            // explicit channel masks; the common screen-saver bitmaps are BI_RGB.
            return .{
                .red = @intCast(((value >> 10) & 31) * 255 / 31),
                .green = @intCast(((value >> 5) & 31) * 255 / 31),
                .blue = @intCast((value & 31) * 255 / 31),
            };
        },
        24, 32 => return .{ .blue = source_row[pixel_offset], .green = source_row[pixel_offset + 1], .red = source_row[pixel_offset + 2] },
        else => unreachable,
    }
}

fn writeDibColor(destination_row: []u8, bit_count: u16, x: usize, color: DibColor) bool {
    const bytes_per_pixel: usize = switch (bit_count) {
        16 => 2,
        24 => 3,
        32 => 4,
        else => return false,
    };
    const pixel_offset = x * bytes_per_pixel;
    if (pixel_offset > destination_row.len or bytes_per_pixel > destination_row.len - pixel_offset) return false;
    const output = destination_row[pixel_offset .. pixel_offset + bytes_per_pixel];
    switch (bit_count) {
        16 => {
            const packed_value = (@as(u16, color.red >> 3) << 10) | (@as(u16, color.green >> 3) << 5) | (color.blue >> 3);
            std.mem.writeInt(u16, output[0..2], packed_value, .little);
        },
        24 => {
            output[0] = color.blue;
            output[1] = color.green;
            output[2] = color.red;
        },
        32 => {
            output[0] = color.blue;
            output[1] = color.green;
            output[2] = color.red;
            output[3] = 0xFF;
        },
        else => unreachable,
    }
    return true;
}

fn describePixelFormat(ex: *Executor, address: u32, size: usize) bool {
    const pfd = guestSlice(ex, address, size) orelse return false;
    if (size < 40) return false;
    @memset(pfd[0..40], 0);
    std.mem.writeInt(u16, pfd[0..2], 40, .little); // nSize
    std.mem.writeInt(u16, pfd[2..4], 1, .little); // nVersion
    std.mem.writeInt(u32, pfd[4..8], 0x0000_0025, .little); // draw-to-window, OpenGL, double-buffer
    pfd[8] = 0; // PFD_TYPE_RGBA
    pfd[9] = 32; // cColorBits
    pfd[10] = 8; // cRedBits
    pfd[12] = 8; // cGreenBits
    pfd[14] = 8; // cBlueBits
    pfd[16] = 8; // cAlphaBits
    pfd[23] = 24; // cDepthBits
    pfd[24] = 8; // cStencilBits
    pfd[26] = 0; // PFD_MAIN_PLANE
    return true;
}

fn getStockObjectThunk(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const object_type = frame.arg(0);
    // Win32 stock-object identifiers occupy the contiguous 0..19 range.
    // Preserve identity across calls so selection and comparison code sees
    // the same object without pretending this creates a host GDI object.
    frame.finish(if (object_type < stock_object_count) stock_handle_base | (object_type + 1) else 0);
}

fn createCompatibleDcThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const source_dc = frame.arg(0);
    // The PE32 bridge has one window DC and one off-screen memory DC.  Both
    // describe the same 32-bit display format, which is enough for the
    // screen-saver's DIB conversion path while actual presentation remains in
    // the native OpenGL view.
    const valid = source_dc == 0 or validDeviceContext(source_dc);
    if (valid and ex.pe32_gdi_selected_objects[1] == 0) {
        // Windows memory DCs begin with a selected 1x1 monochrome bitmap.
        // SelectObject returns it when the first real bitmap is selected.
        ex.pe32_gdi_selected_objects[1] = stock_bitmap_handle;
        ex.pe32_gdi_selected_bitmaps[1] = stock_bitmap_handle;
    }
    ex.win32_last_error = if (valid) 0 else 6; // ERROR_INVALID_HANDLE
    frame.finish(if (valid) memory_dc_handle else 0);
}

fn deleteDcThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const dc = frame.arg(0);
    const index = dcIndex(dc);
    const selected_bitmap = if (index) |i| ex.pe32_gdi_selected_bitmaps[i] else 0;
    const valid = dc == memory_dc_handle and index != null and
        (selected_bitmap == 0 or isStockBitmap(selected_bitmap));
    if (valid) {
        ex.pe32_gdi_selected_objects[index.?] = 0;
        ex.pe32_gdi_selected_bitmaps[index.?] = 0;
    }
    ex.win32_last_error = if (valid) 0 else 6; // ERROR_INVALID_HANDLE
    frame.finish(@intFromBool(valid));
}

fn createDibSectionThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 6);
    const dc = frame.arg(0);
    const info_address = frame.arg(1);
    const usage = frame.arg(2);
    const bits_out_address = frame.arg(3);
    const section = frame.arg(4);
    const section_offset = frame.arg(5);
    const bits_out = guestSlice(ex, bits_out_address, 4) orelse {
        ex.win32_last_error = 998; // ERROR_NOACCESS
        frame.finish(0);
        return;
    };
    const info = bitmapHeader(ex, info_address) orelse {
        ex.win32_last_error = 87; // ERROR_INVALID_PARAMETER
        frame.finish(0);
        return;
    };
    if (!validDeviceContext(dc) or (usage != 0 and usage != 1) or section != 0 or section_offset != 0) {
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    }
    const handle = makeBitmap(ex, info.width, info.height, info.bit_count, info.compression) orelse {
        ex.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY / unsupported DIB shape
        frame.finish(0);
        return;
    };
    const bitmap = findBitmap(ex, handle).?;
    std.mem.writeInt(u32, bits_out[0..4], bitmap.bits, .little);
    if (glTraceEnabled()) std.debug.print("PE32_GDI: CreateDIBSection eip=0x{X:0>8} esp=0x{X:0>8} dc=0x{X:0>8} info=0x{X:0>8} header={d} source={d}x{d}x{d}/compression={d}/colors={d} usage={d} bits_out=0x{X:0>8} handle=0x{X:0>8} bits=0x{X:0>8} size={d}x{d}x{d} stride={d}\n", .{
        ex.regs.eip,
        ex.regs.esp,
        dc,
        info_address,
        info.header_size,
        info.width,
        @abs(info.height),
        info.bit_count,
        info.compression,
        info.colors_used,
        usage,
        bits_out_address,
        handle,
        bitmap.bits,
        bitmap.width,
        @abs(bitmap.height),
        bitmap.bit_count,
        bitmap.row_stride,
    });
    ex.win32_last_error = 0;
    frame.finish(handle);
}

fn createCompatibleBitmapThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 3);
    const dc = frame.arg(0);
    const width = frame.arg(1);
    const height = frame.arg(2);
    if (!validDeviceContext(dc) or width == 0 or height == 0 or width > std.math.maxInt(i32) or height > std.math.maxInt(i32)) {
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    }
    const handle = makeBitmap(ex, @intCast(width), @intCast(height), 32, 0) orelse {
        ex.win32_last_error = 8;
        frame.finish(0);
        return;
    };
    ex.win32_last_error = 0;
    frame.finish(handle);
}

fn selectObjectThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const dc = frame.arg(0);
    const object = frame.arg(1);
    const index = dcIndex(dc) orelse {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    };
    const is_bitmap = findBitmap(ex, object) != null or isStockBitmap(object);
    const is_stock = (object > stock_handle_base and object <= stock_handle_base + stock_object_count) or isStockBitmap(object);
    if (!is_bitmap and !is_stock) {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    }
    const previous = ex.pe32_gdi_selected_objects[index];
    ex.pe32_gdi_selected_objects[index] = object;
    ex.pe32_gdi_selected_bitmaps[index] = if (is_bitmap) object else 0;
    ex.win32_last_error = 0;
    frame.finish(previous);
}

fn getCurrentObjectThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const index = dcIndex(frame.arg(0)) orelse {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    };
    const object_type = frame.arg(1);
    const object = if (object_type == 7) ex.pe32_gdi_selected_bitmaps[index] else ex.pe32_gdi_selected_objects[index];
    ex.win32_last_error = if (object != 0) 0 else 6;
    frame.finish(object);
}

fn getObjectTypeThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const handle = frame.arg(0);
    const kind: u32 = if (findBitmap(ex, handle) != null or isStockBitmap(handle))
        7 // OBJ_BITMAP
    else if (handle == window_dc_handle)
        3 // OBJ_DC
    else if (handle == memory_dc_handle)
        10 // OBJ_MEMDC
    else
        0;
    ex.win32_last_error = if (kind != 0) 0 else 6;
    frame.finish(kind);
}

fn getObjectWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 3);
    const handle = frame.arg(0);
    const requested = frame.arg(1);
    const output_address = frame.arg(2);
    if (isStockBitmap(handle)) {
        const output = guestSlice(ex, output_address, @min(requested, bitmap_object_size)) orelse {
            ex.win32_last_error = 998;
            frame.finish(0);
            return;
        };
        @memset(output, 0);
        if (requested >= bitmap_object_size) {
            std.mem.writeInt(i32, output[4..8], 1, .little); // 1x1 monochrome bitmap
            std.mem.writeInt(i32, output[8..12], 1, .little);
            std.mem.writeInt(i32, output[12..16], 4, .little); // DWORD-aligned row
            std.mem.writeInt(u16, output[16..18], 1, .little);
            std.mem.writeInt(u16, output[18..20], 1, .little);
            ex.win32_last_error = 0;
            frame.finish(@intCast(bitmap_object_size));
        } else {
            ex.win32_last_error = 0;
            frame.finish(requested);
        }
        return;
    }
    const bitmap = findBitmap(ex, handle) orelse {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    };
    const output = guestSlice(ex, output_address, @min(requested, bitmap_object_size)) orelse {
        ex.win32_last_error = 998;
        frame.finish(0);
        return;
    };
    @memset(output, 0);
    if (requested >= bitmap_object_size) {
        std.mem.writeInt(i32, output[0..4], 0, .little); // bmType
        std.mem.writeInt(i32, output[4..8], @intCast(bitmap.width), .little);
        std.mem.writeInt(i32, output[8..12], bitmap.height, .little);
        std.mem.writeInt(i32, output[12..16], @intCast(bitmap.row_stride), .little);
        std.mem.writeInt(u16, output[16..18], 1, .little);
        std.mem.writeInt(u16, output[18..20], bitmap.bit_count, .little);
        std.mem.writeInt(u32, output[20..24], bitmap.bits, .little);
        ex.win32_last_error = 0;
        frame.finish(@intCast(bitmap_object_size));
    } else {
        ex.win32_last_error = 0;
        frame.finish(requested);
    }
}

fn deleteObjectThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const handle = frame.arg(0);
    for (ex.pe32_gdi_selected_bitmaps) |selected| {
        if (selected == handle) {
            ex.win32_last_error = 6;
            frame.finish(0);
            return;
        }
    }
    const bitmap = findBitmap(ex, handle) orelse {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    };
    _ = heap.free("DeleteObject", heap.process_heap_handle, 0, bitmap.bits);
    bitmap.* = .{};
    ex.win32_last_error = 0;
    frame.finish(1);
}

fn setBitmapInfoHeader(ex: *Executor, info_address: u32, bitmap: *const Executor.Pe32GdiBitmap) bool {
    const header = guestSlice(ex, info_address, bitmap_info_header_size) orelse return false;
    const header_size = std.mem.readInt(u32, header[0..4], .little);
    if (header_size < bitmap_info_header_size) return false;
    std.mem.writeInt(i32, header[4..8], @intCast(bitmap.width), .little);
    std.mem.writeInt(i32, header[8..12], bitmap.height, .little);
    std.mem.writeInt(u16, header[12..14], 1, .little);
    std.mem.writeInt(u16, header[14..16], bitmap.bit_count, .little);
    std.mem.writeInt(u32, header[16..20], bitmap.compression, .little);
    std.mem.writeInt(u32, header[20..24], bitmap.byte_size, .little);
    return true;
}

fn getDibitsThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 7);
    const dc = frame.arg(0);
    const handle = frame.arg(1);
    const start_scan = frame.arg(2);
    const scan_lines = frame.arg(3);
    const output_address = frame.arg(4);
    const info_address = frame.arg(5);
    if (glTraceEnabled()) std.debug.print("PE32_GDI: GetDIBits call dc=0x{X:0>8} handle=0x{X:0>8} start={d} requested_lines={d} out=0x{X:0>8} info=0x{X:0>8} usage={d}\n", .{
        dc,
        handle,
        start_scan,
        scan_lines,
        output_address,
        info_address,
        frame.arg(6),
    });
    const bitmap = findBitmap(ex, handle) orelse {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    };
    if (!validDeviceContext(dc) or frame.arg(6) > 1 or start_scan > @abs(bitmap.height)) {
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    }
    if (output_address == 0) {
        const valid = setBitmapInfoHeader(ex, info_address, bitmap);
        if (glTraceEnabled()) std.debug.print("PE32_GDI: GetDIBits query handle=0x{X:0>8} bitmap={d}x{d}x{d} result={d} error={d}\n", .{
            handle,
            bitmap.width,
            @abs(bitmap.height),
            bitmap.bit_count,
            if (valid) @as(u32, 1) else 0,
            if (valid) @as(u32, 0) else 87,
        });
        ex.win32_last_error = if (valid) 0 else 87;
        frame.finish(if (valid) @as(u32, 1) else 0);
        return;
    }
    const requested = bitmapHeader(ex, info_address) orelse {
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    };
    if (requested.width != bitmap.width or requested.bit_count != bitmap.bit_count or
        requested.compression != bitmap.compression)
    {
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    }
    const lines: u32 = @min(scan_lines, @as(u32, @intCast(@abs(bitmap.height))) - start_scan);
    const copy_size_u64 = @as(u64, bitmap.row_stride) * lines;
    if (copy_size_u64 > std.math.maxInt(usize)) {
        ex.win32_last_error = 8;
        frame.finish(0);
        return;
    }
    const size: usize = @intCast(copy_size_u64);
    const destination = guestSlice(ex, output_address, size) orelse {
        ex.win32_last_error = 998;
        frame.finish(0);
        return;
    };
    const source = guestSlice(ex, bitmap.bits +% start_scan *% bitmap.row_stride, size) orelse {
        ex.win32_last_error = 998;
        frame.finish(0);
        return;
    };
    @memcpy(destination, source);
    if (glTraceEnabled()) std.debug.print("PE32_GDI: GetDIBits dc=0x{X:0>8} handle=0x{X:0>8} start={d} lines={d} out=0x{X:0>8} bitmap={d}x{d}x{d} first={X:0>2}{X:0>2}{X:0>2}{X:0>2}\n", .{
        dc,
        handle,
        start_scan,
        lines,
        output_address,
        bitmap.width,
        @abs(bitmap.height),
        bitmap.bit_count,
        if (source.len > 0) source[0] else 0,
        if (source.len > 1) source[1] else 0,
        if (source.len > 2) source[2] else 0,
        if (source.len > 3) source[3] else 0,
    });
    ex.win32_last_error = 0;
    frame.finish(lines);
}

fn setDibitsThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 7);
    const dc = frame.arg(0);
    const handle = frame.arg(1);
    const start_scan = frame.arg(2);
    const scan_lines = frame.arg(3);
    const input_address = frame.arg(4);
    const info_address = frame.arg(5);
    if (glTraceEnabled()) std.debug.print("PE32_GDI: SetDIBits call dc=0x{X:0>8} handle=0x{X:0>8} start={d} requested_lines={d} in=0x{X:0>8} info=0x{X:0>8} usage={d}\n", .{
        dc,
        handle,
        start_scan,
        scan_lines,
        input_address,
        info_address,
        frame.arg(6),
    });
    const bitmap = findBitmap(ex, handle) orelse {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    };
    const requested = bitmapHeader(ex, info_address) orelse {
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    };
    const usage = frame.arg(6);
    const height: u32 = @intCast(@abs(bitmap.height));
    const source_height: u32 = @intCast(@abs(requested.height));
    if (!validDeviceContext(dc) or usage > 1 or start_scan > height or
        requested.width != bitmap.width or source_height != height)
    {
        if (glTraceEnabled()) std.debug.print("PE32_GDI: SetDIBits rejected handle=0x{X:0>8} reason=shape-or-argument usage={d} dest={d}x{d}x{d}/compression={d} source={d}x{d}x{d}/compression={d} start={d} requested_lines={d}\n", .{
            handle,          usage,         bitmap.width,        height,                bitmap.bit_count, bitmap.compression,
            requested.width, source_height, requested.bit_count, requested.compression, start_scan,       scan_lines,
        });
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    }
    const lines: u32 = @min(scan_lines, height - start_scan);
    if (lines == 0) {
        ex.win32_last_error = 0;
        frame.finish(0);
        return;
    }
    const same_layout = requested.bit_count == bitmap.bit_count and
        requested.compression == bitmap.compression and
        (requested.height < 0) == (bitmap.height < 0);
    if (same_layout) {
        const copy_size_u64 = @as(u64, bitmap.row_stride) * lines;
        if (copy_size_u64 > std.math.maxInt(usize)) {
            ex.win32_last_error = 8;
            frame.finish(0);
            return;
        }
        const size: usize = @intCast(copy_size_u64);
        const source = guestSlice(ex, input_address, size) orelse {
            ex.win32_last_error = 998;
            frame.finish(0);
            return;
        };
        const destination = guestSlice(ex, bitmap.bits +% start_scan *% bitmap.row_stride, size) orelse {
            ex.win32_last_error = 998;
            frame.finish(0);
            return;
        };
        @memcpy(destination, source);
        if (glTraceEnabled()) std.debug.print("PE32_GDI: SetDIBits copied handle=0x{X:0>8} start={d} lines={d} format={d}bpp compression={d} first={X:0>2}{X:0>2}{X:0>2}{X:0>2}\n", .{
            handle,                               start_scan,                           lines,                                requested.bit_count,                  requested.compression,
            if (source.len > 0) source[0] else 0, if (source.len > 1) source[1] else 0, if (source.len > 2) source[2] else 0, if (source.len > 3) source[3] else 0,
        });
        ex.win32_last_error = 0;
        frame.finish(lines);
        return;
    }
    if (requested.compression != 0 or bitmap.compression != 0 or usage != 0 or
        (bitmap.bit_count != 16 and bitmap.bit_count != 24 and bitmap.bit_count != 32))
    {
        if (glTraceEnabled()) std.debug.print("PE32_GDI: SetDIBits rejected handle=0x{X:0>8} reason=unsupported-conversion usage={d} dest={d}bpp/compression={d} source={d}bpp/compression={d}\n", .{
            handle, usage, bitmap.bit_count, bitmap.compression, requested.bit_count, requested.compression,
        });
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    }
    const source_stride = dibStride(@intCast(requested.width), requested.bit_count) orelse {
        ex.win32_last_error = 87;
        frame.finish(0);
        return;
    };
    const source_size = std.math.mul(usize, source_stride, lines) catch {
        ex.win32_last_error = 8;
        frame.finish(0);
        return;
    };
    const source = guestSlice(ex, input_address, source_size) orelse {
        ex.win32_last_error = 998;
        frame.finish(0);
        return;
    };
    const destination = guestSlice(ex, bitmap.bits, bitmap.byte_size) orelse {
        ex.win32_last_error = 998;
        frame.finish(0);
        return;
    };
    for (0..@as(usize, lines)) |line| {
        const source_start = line * source_stride;
        const source_row = source[source_start .. source_start + source_stride];
        const scan = @as(usize, start_scan) + line;
        const logical_row = if (requested.height < 0) scan else @as(usize, height) - 1 - scan;
        const destination_row_index = if (bitmap.height < 0) logical_row else @as(usize, height) - 1 - logical_row;
        const destination_start = destination_row_index * bitmap.row_stride;
        const destination_row = destination[destination_start .. destination_start + bitmap.row_stride];
        for (0..@as(usize, @intCast(bitmap.width))) |x| {
            const color = dibSourceColor(ex, source_row, info_address, requested, x, usage) orelse {
                if (glTraceEnabled()) std.debug.print("PE32_GDI: SetDIBits rejected handle=0x{X:0>8} reason=invalid-source-pixel row={d} column={d} source_bpp={d} colors_used={d}\n", .{
                    handle, line, x, requested.bit_count, requested.colors_used,
                });
                ex.win32_last_error = 87;
                frame.finish(0);
                return;
            };
            if (!writeDibColor(destination_row, bitmap.bit_count, x, color)) {
                ex.win32_last_error = 87;
                frame.finish(0);
                return;
            }
        }
    }
    if (glTraceEnabled()) std.debug.print("PE32_GDI: SetDIBits converted handle=0x{X:0>8} start={d} lines={d} source={d}bpp -> destination={d}bpp first={X:0>2}{X:0>2}{X:0>2}{X:0>2}\n", .{
        handle,                               start_scan,                           lines,                                requested.bit_count,                  bitmap.bit_count,
        if (source.len > 0) source[0] else 0, if (source.len > 1) source[1] else 0, if (source.len > 2) source[2] else 0, if (source.len > 3) source[3] else 0,
    });
    ex.win32_last_error = 0;
    frame.finish(lines);
}

fn gdiFlushThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 0);
    // DIB writes are synchronous in the guest memory model, so no deferred
    // host GDI command queue needs to be drained.
    ex.win32_last_error = 0;
    frame.finish(1);
}

fn getDeviceCapsThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const dc = frame.arg(0);
    const index = frame.arg(1);
    if (!validDeviceContext(dc)) {
        ex.win32_last_error = 6; // ERROR_INVALID_HANDLE
        frame.finish(0);
        return;
    }
    const value: i32 = switch (index) {
        0 => 1, // TECHNOLOGY = DT_RASDISPLAY
        8, 118 => 1280, // HORZRES / DESKTOPHORZRES
        10, 117 => 720, // VERTRES / DESKTOPVERTRES
        12 => 32, // BITSPIXEL
        14 => 1, // PLANES
        24 => -1, // NUMCOLORS = true color
        88, 90 => 72, // LOGPIXELSX / LOGPIXELSY
        104 => 0, // SIZEPALETTE for true color
        116 => 60, // VREFRESH
        else => 0,
    };
    ex.win32_last_error = 0;
    frame.finish(@bitCast(value));
}

fn choosePixelFormatThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const dc = frame.arg(0);
    const pfd_address = frame.arg(1);
    const pfd = guestSlice(ex, pfd_address, 40) orelse {
        ex.win32_last_error = 998; // ERROR_NOACCESS
        frame.finish(0);
        return;
    };
    const pfd_size = std.mem.readInt(u16, pfd[0..2], .little);
    const pfd_version = std.mem.readInt(u16, pfd[2..4], .little);
    const flags = std.mem.readInt(u32, pfd[4..8], .little);
    const valid = validDeviceContext(dc) and pfd_size >= 40 and pfd_version == 1 and
        pfd[8] == 0 and flags & 0x24 == 0x24;
    const pixel_format: u32 = if (valid) 1 else 0;
    if (glTraceEnabled()) std.debug.print("PE32_GL: ChoosePixelFormat dc=0x{X:0>8} pfd=0x{X:0>8} size={d} version={d} flags=0x{X:0>8} type={d} result={d} error={d}\n", .{
        dc,
        pfd_address,
        pfd_size,
        pfd_version,
        flags,
        pfd[8],
        pixel_format,
        if (valid) @as(u32, 0) else 87,
    });
    ex.win32_last_error = if (valid) 0 else 87; // ERROR_INVALID_PARAMETER
    frame.finish(if (valid) 1 else 0);
}

fn describePixelFormatThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 4);
    const dc = frame.arg(0);
    const format = frame.arg(1);
    const byte_count = frame.arg(2);
    const pfd_address = frame.arg(3);
    const valid = validDeviceContext(dc) and format == 1 and byte_count >= 40 and
        describePixelFormat(ex, pfd_address, @intCast(@min(byte_count, 40)));
    if (glTraceEnabled()) std.debug.print("PE32_GL: DescribePixelFormat dc=0x{X:0>8} format={d} bytes={d} pfd=0x{X:0>8} result={d}\n", .{
        dc,
        format,
        byte_count,
        pfd_address,
        if (valid) @as(u32, pixel_format_count) else 0,
    });
    ex.win32_last_error = if (valid) 0 else 87;
    frame.finish(if (valid) pixel_format_count else 0);
}

fn setPixelFormatThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 3);
    const dc = frame.arg(0);
    const format = frame.arg(1);
    const pfd_address = frame.arg(2);
    const pfd = if (pfd_address == 0) null else guestSlice(ex, pfd_address, 40);
    // This screen-saver support library selects a format by enumerating
    // DescribePixelFormat, then calls SetPixelFormat with a null descriptor.
    // The bridge exposes one supported format (index 1); when a descriptor is
    // supplied, still validate its size before accepting the call.
    const valid = validDeviceContext(dc) and format == 1 and (pfd_address == 0 or (pfd != null and
        std.mem.readInt(u16, pfd.?[0..2], .little) >= 40));
    if (valid) ex.pe32_gl_pixel_format_set = true;
    if (glTraceEnabled()) std.debug.print("PE32_GL: SetPixelFormat dc=0x{X:0>8} format={d} pfd=0x{X:0>8} nSize={d} result={d}\n", .{
        dc,
        format,
        pfd_address,
        if (pfd) |bytes| std.mem.readInt(u16, bytes[0..2], .little) else 0,
        @intFromBool(valid),
    });
    ex.win32_last_error = if (valid) 0 else 87;
    frame.finish(@intFromBool(valid));
}

fn swapBuffersThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const valid_dc = validDeviceContext(frame.arg(0));
    const did_swap = if (valid_dc and ex.pe32_gl_context_created and ex.pe32_gl_context_current)
        if (ex.pe32_window_host.legacy_gl_swap) |swap|
            swap(ex.pe32_window_host.context) != 0
        else
            false
    else
        false;
    const valid = valid_dc and did_swap;
    ex.win32_last_error = if (valid) 0 else 6;
    frame.finish(@intFromBool(valid));
}

pub fn register(executor: *Executor) void {
    executor.import_table.put("GetStockObject", getStockObjectThunk) catch {};
    executor.import_table.put("CreateCompatibleDC", createCompatibleDcThunk) catch {};
    executor.import_table.put("DeleteDC", deleteDcThunk) catch {};
    executor.import_table.put("CreateDIBSection", createDibSectionThunk) catch {};
    executor.import_table.put("CreateCompatibleBitmap", createCompatibleBitmapThunk) catch {};
    executor.import_table.put("SelectObject", selectObjectThunk) catch {};
    executor.import_table.put("GetCurrentObject", getCurrentObjectThunk) catch {};
    executor.import_table.put("GetObjectType", getObjectTypeThunk) catch {};
    executor.import_table.put("GetObjectW", getObjectWThunk) catch {};
    executor.import_table.put("DeleteObject", deleteObjectThunk) catch {};
    executor.import_table.put("GetDIBits", getDibitsThunk) catch {};
    executor.import_table.put("SetDIBits", setDibitsThunk) catch {};
    executor.import_table.put("GdiFlush", gdiFlushThunk) catch {};
    executor.import_table.put("GetDeviceCaps", getDeviceCapsThunk) catch {};
    executor.import_table.put("ChoosePixelFormat", choosePixelFormatThunk) catch {};
    executor.import_table.put("DescribePixelFormat", describePixelFormatThunk) catch {};
    executor.import_table.put("SetPixelFormat", setPixelFormatThunk) catch {};
    executor.import_table.put("SwapBuffers", swapBuffersThunk) catch {};
}

test "GetStockObject returns stable handles only for documented stock IDs" {
    var executor = Executor.init(testing.allocator, 4096);
    defer executor.deinit();

    executor.regs.esp = 3072;
    register(&executor);

    executor.push(4); // BLACK_BRUSH
    executor.dispatch_import("GetStockObject");
    const black_brush = executor.regs.eax;
    try testing.expectEqual(stock_handle_base | 5, black_brush);
    try testing.expectEqual(@as(u32, 3072), executor.regs.esp);

    executor.regs.esp = 3072;
    executor.push(4);
    executor.dispatch_import("GetStockObject");
    try testing.expectEqual(black_brush, executor.regs.eax);

    executor.regs.esp = 3072;
    executor.push(stock_object_count);
    executor.dispatch_import("GetStockObject");
    try testing.expectEqual(@as(u32, 0), executor.regs.eax);
}
