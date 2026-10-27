//! PE32 WGL/OpenGL imports backed by the host's legacy compatibility context.
//! Guest pointers are checked by the native dispatcher against the executor's
//! flat address span before any GL/GLU function receives them.
const std = @import("std");
const Executor = @import("../instruction_operations.zig").Executor;
const abi = @import("../abi_handshake.zig");
const gdi = @import("gdi_thunks.zig");
const heap = @import("../heap/runtime.zig");
const execution_engine = @import("../execution_engine.zig");

const gl_context_handle: u32 = 0xF600_0001;
const gl_string_capacity: u32 = 16 * 1024;
const max_call_arguments = 20;
var gl_tex_image_trace_count: u32 = 0;

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

fn invoke(ex: *Executor, name: [:0]const u8, args: *const [max_call_arguments]u64) u32 {
    if (!ex.pe32_gl_context_current) {
        ex.win32_last_error = 6; // ERROR_INVALID_HANDLE: no current WGL context.
        return 0;
    }
    const dispatch = ex.pe32_window_host.legacy_gl_dispatch orelse {
        ex.win32_last_error = 120; // ERROR_CALL_NOT_IMPLEMENTED.
        return 0;
    };
    const memory = ex.mem.data.ptr;
    const result = dispatch(
        ex.pe32_window_host.context,
        name,
        args,
        memory,
        ex.mem.data.len,
        ex.mem.base,
    );
    ex.win32_last_error = 0;
    return @truncate(result);
}

fn invokeFrame(ex: *Executor, count: u32, name: [:0]const u8) void {
    const frame = abi.CallFrame.raw(ex, count);
    var args = [_]u64{0} ** max_call_arguments;
    for (0..count) |index| args[index] = frame.arg(@intCast(index));
    frame.finish(invoke(ex, name, &args));
}

fn wglCreateContextThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const dc = frame.arg(0);
    if (dc != gdi.window_dc_handle or !ex.pe32_gl_pixel_format_set) {
        if (glTraceEnabled()) std.debug.print("PE32_GL: wglCreateContext rejected dc=0x{X:0>8} expected=0x{X:0>8} pixel_format_set={} error=6\n", .{
            dc,
            gdi.window_dc_handle,
            ex.pe32_gl_pixel_format_set,
        });
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    }
    const create = ex.pe32_window_host.legacy_gl_create orelse {
        if (glTraceEnabled()) std.debug.print("PE32_GL: wglCreateContext missing native callback\n", .{});
        ex.win32_last_error = 120;
        frame.finish(0);
        return;
    };
    const width = if (ex.pe32_window_width == 0) 1280 else ex.pe32_window_width;
    const height = if (ex.pe32_window_height == 0) 720 else ex.pe32_window_height;
    if (create(ex.pe32_window_host.context, width, height) == 0) {
        if (glTraceEnabled()) std.debug.print("PE32_GL: wglCreateContext native create failed size={d}x{d}\n", .{ width, height });
        ex.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY / no GL context.
        frame.finish(0);
        return;
    }
    ex.pe32_gl_context_created = true;
    if (glTraceEnabled()) std.debug.print("PE32_GL: wglCreateContext created handle=0x{X:0>8} size={d}x{d}\n", .{ gl_context_handle, width, height });
    ex.win32_last_error = 0;
    frame.finish(gl_context_handle);
}

fn wglMakeCurrentThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const dc = frame.arg(0);
    const context = frame.arg(1);
    if (dc == 0 and context == 0) {
        const clear = ex.pe32_window_host.legacy_gl_clear_current;
        const cleared = if (clear) |callback| callback(ex.pe32_window_host.context) != 0 else false;
        ex.pe32_gl_context_current = false;
        if (glTraceEnabled()) std.debug.print("PE32_GL: wglMakeCurrent clear result={}\n", .{@intFromBool(cleared)});
        ex.win32_last_error = if (cleared) 0 else 6;
        frame.finish(@intFromBool(cleared));
        return;
    }
    if (dc != gdi.window_dc_handle or context != gl_context_handle or
        !ex.pe32_gl_context_created)
    {
        if (glTraceEnabled()) std.debug.print("PE32_GL: wglMakeCurrent rejected dc=0x{X:0>8} context=0x{X:0>8} created={} error=6\n", .{
            dc,
            context,
            ex.pe32_gl_context_created,
        });
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    }
    const make_current = ex.pe32_window_host.legacy_gl_make_current orelse {
        ex.win32_last_error = 120;
        frame.finish(0);
        return;
    };
    const made_current = make_current(ex.pe32_window_host.context) != 0;
    ex.pe32_gl_context_current = made_current;
    if (made_current) {
        // The host window has a fixed presentation size, while a PE32 app may
        // create its client surface at a smaller logical resolution. Configure
        // the native compatibility dispatcher to scale its viewport/scissor
        // rectangles into the drawable without changing the guest window size.
        var scale_args = [_]u64{0} ** max_call_arguments;
        scale_args[0] = if (ex.pe32_window_width == 0) 1280 else ex.pe32_window_width;
        scale_args[1] = if (ex.pe32_window_height == 0) 720 else ex.pe32_window_height;
        const configured = invoke(ex, "rosetteConfigureViewportScale", &scale_args) != 0;
        if (glTraceEnabled()) std.debug.print(
            "PE32_GL: viewport scale configured={} logical={d}x{d}\n",
            .{ configured, scale_args[0], scale_args[1] },
        );
    }
    if (glTraceEnabled()) std.debug.print("PE32_GL: wglMakeCurrent result={} handle=0x{X:0>8}\n", .{ @intFromBool(made_current), context });
    ex.win32_last_error = if (made_current) 0 else 6;
    frame.finish(@intFromBool(made_current));
}

fn wglDeleteContextThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const context = frame.arg(0);
    if (context != gl_context_handle or !ex.pe32_gl_context_created) {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    }
    const delete = ex.pe32_window_host.legacy_gl_delete;
    const deleted = if (delete) |callback| callback(ex.pe32_window_host.context) != 0 else false;
    if (deleted) {
        ex.pe32_gl_context_created = false;
        ex.pe32_gl_context_current = false;
    }
    ex.win32_last_error = if (deleted) 0 else 6;
    frame.finish(@intFromBool(deleted));
}

fn readProcName(ex: *const Executor, address: u32, buffer: []u8) ?[]const u8 {
    if (address < ex.mem.base) return null;
    const offset: usize = @intCast(address - ex.mem.base);
    if (offset >= ex.mem.data.len) return null;
    var length: usize = 0;
    while (length < buffer.len and offset + length < ex.mem.data.len) : (length += 1) {
        const byte = ex.mem.data[offset + length];
        if (byte == 0) return buffer[0..length];
        buffer[length] = byte;
    }
    return null;
}

fn wglGetProcAddressThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    var storage: [128]u8 = undefined;
    const name = readProcName(ex, frame.arg(0), &storage) orelse {
        ex.win32_last_error = 998; // ERROR_NOACCESS.
        frame.finish(0);
        return;
    };
    const pointer = execution_engine.lookupIatDirectFunctionPointer(ex, name) orelse {
        ex.win32_last_error = 127; // ERROR_PROC_NOT_FOUND.
        frame.finish(0);
        return;
    };
    ex.win32_last_error = 0;
    frame.finish(pointer);
}

fn glGetStringThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    if (!ex.pe32_gl_context_current) {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    }
    const address = heap.alloc("glGetString", heap.process_heap_handle, 0, gl_string_capacity);
    const output = guestSlice(ex, address, gl_string_capacity) orelse {
        ex.win32_last_error = 998;
        frame.finish(0);
        return;
    };
    @memset(output, 0);
    var args = [_]u64{0} ** max_call_arguments;
    args[0] = frame.arg(0);
    args[1] = address;
    const result = invoke(ex, "glGetString", &args);
    if (result == 0) {
        ex.win32_last_error = 6;
        frame.finish(0);
        return;
    }
    frame.finish(address);
}

fn glBeginThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glBegin");
}
fn glEndThunk(ex: *Executor) void {
    invokeFrame(ex, 0, "glEnd");
}
fn glVertex3fThunk(ex: *Executor) void {
    invokeFrame(ex, 3, "glVertex3f");
}
fn glVertex2fThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glVertex2f");
}
fn glVertex3dvThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glVertex3dv");
}
fn glNormal3fThunk(ex: *Executor) void {
    invokeFrame(ex, 3, "glNormal3f");
}
fn glNormal3dvThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glNormal3dv");
}
fn glColor3fThunk(ex: *Executor) void {
    invokeFrame(ex, 3, "glColor3f");
}
fn glColor3fvThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glColor3fv");
}
fn glColor4fvThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glColor4fv");
}
fn glTexCoord2fThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glTexCoord2f");
}
fn glTexCoord2dThunk(ex: *Executor) void {
    invokeFrame(ex, 4, "glTexCoord2d");
}
fn glMatrixModeThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glMatrixMode");
}
fn glLoadIdentityThunk(ex: *Executor) void {
    invokeFrame(ex, 0, "glLoadIdentity");
}
fn glPushMatrixThunk(ex: *Executor) void {
    invokeFrame(ex, 0, "glPushMatrix");
}
fn glPopMatrixThunk(ex: *Executor) void {
    invokeFrame(ex, 0, "glPopMatrix");
}
fn glTranslatefThunk(ex: *Executor) void {
    invokeFrame(ex, 3, "glTranslatef");
}
fn glTranslatedThunk(ex: *Executor) void {
    invokeFrame(ex, 6, "glTranslated");
}
fn glRotatefThunk(ex: *Executor) void {
    invokeFrame(ex, 4, "glRotatef");
}
fn glRotatedThunk(ex: *Executor) void {
    invokeFrame(ex, 8, "glRotated");
}
fn glScaledThunk(ex: *Executor) void {
    invokeFrame(ex, 6, "glScaled");
}
fn glEnableThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glEnable");
}
fn glDisableThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glDisable");
}
fn glHintThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glHint");
}
fn glScissorThunk(ex: *Executor) void {
    invokeFrame(ex, 4, "glScissor");
}
fn glViewportThunk(ex: *Executor) void {
    invokeFrame(ex, 4, "glViewport");
}
fn glCullFaceThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glCullFace");
}
fn glFrontFaceThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glFrontFace");
}
fn glLightModelfvThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glLightModelfv");
}
fn glLightModeliThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glLightModeli");
}
fn glLightfvThunk(ex: *Executor) void {
    invokeFrame(ex, 3, "glLightfv");
}
fn glTexEnviThunk(ex: *Executor) void {
    invokeFrame(ex, 3, "glTexEnvi");
}
fn glGetTexEnvivThunk(ex: *Executor) void {
    invokeFrame(ex, 3, "glGetTexEnviv");
}
fn glGenTexturesThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glGenTextures");
}
fn glDeleteTexturesThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glDeleteTextures");
}
fn glBindTextureThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glBindTexture");
}
fn glTexImage2DThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 9);
    var args = [_]u64{0} ** max_call_arguments;
    for (0..9) |index| args[index] = frame.arg(@intCast(index));
    if (glTraceEnabled() and gl_tex_image_trace_count < 64) {
        gl_tex_image_trace_count += 1;
        const descriptor = guestSlice(ex, ex.regs.esi, 0x28);
        const d0 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x00..0x04], .little) else 0;
        const d4 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x04..0x08], .little) else 0;
        const d8 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x08..0x0C], .little) else 0;
        const d12 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x0C..0x10], .little) else 0;
        const d16 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x10..0x14], .little) else 0;
        const d20 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x14..0x18], .little) else 0;
        const d24 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x18..0x1C], .little) else 0;
        const d28 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x1C..0x20], .little) else 0;
        const d32 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x20..0x24], .little) else 0;
        const d36 = if (descriptor) |bytes| std.mem.readInt(u32, bytes[0x24..0x28], .little) else 0;
        std.debug.print("PE32_GL_CALL: glTexImage2D eip=0x{X:0>8} esp=0x{X:0>8} target=0x{X:0>8} level={d} internal={d} width={d} height={d} border={d} format=0x{X:0>8} type=0x{X:0>8} pixels=0x{X:0>8}\n", .{
            ex.regs.eip,
            ex.regs.esp,
            args[0],
            @as(i32, @bitCast(@as(u32, @truncate(args[1])))),
            @as(i32, @bitCast(@as(u32, @truncate(args[2])))),
            @as(i32, @bitCast(@as(u32, @truncate(args[3])))),
            @as(i32, @bitCast(@as(u32, @truncate(args[4])))),
            @as(i32, @bitCast(@as(u32, @truncate(args[5])))),
            args[6],
            args[7],
            args[8],
        });
        std.debug.print("PE32_GL_CALL: texture descriptor esi=0x{X:0>8} readable={} words={X:0>8},{X:0>8},{X:0>8},{X:0>8},{X:0>8},{X:0>8},{X:0>8},{X:0>8},{X:0>8},{X:0>8}\n", .{
            ex.regs.esi,
            descriptor != null,
            d0,
            d4,
            d8,
            d12,
            d16,
            d20,
            d24,
            d28,
            d32,
            d36,
        });
    }
    frame.finish(invoke(ex, "glTexImage2D", &args));
}
fn glTexParameteriThunk(ex: *Executor) void {
    invokeFrame(ex, 3, "glTexParameteri");
}
fn glShadeModelThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glShadeModel");
}
fn glPolygonModeThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glPolygonMode");
}
fn glClearDepthThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glClearDepth");
}
fn glPixelStoreiThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glPixelStorei");
}
fn glBlendFuncThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glBlendFunc");
}
fn glClearThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glClear");
}
fn glFlushThunk(ex: *Executor) void {
    invokeFrame(ex, 0, "glFlush");
}
fn glFinishThunk(ex: *Executor) void {
    invokeFrame(ex, 0, "glFinish");
}
fn glGetIntegervThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glGetIntegerv");
}
fn glGenListsThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glGenLists");
}
fn glNewListThunk(ex: *Executor) void {
    invokeFrame(ex, 2, "glNewList");
}
fn glEndListThunk(ex: *Executor) void {
    invokeFrame(ex, 0, "glEndList");
}
fn glCallListThunk(ex: *Executor) void {
    invokeFrame(ex, 1, "glCallList");
}
fn gluLookAtThunk(ex: *Executor) void {
    invokeFrame(ex, 18, "gluLookAt");
}
fn gluOrtho2DThunk(ex: *Executor) void {
    invokeFrame(ex, 8, "gluOrtho2D");
}
fn gluPerspectiveThunk(ex: *Executor) void {
    invokeFrame(ex, 8, "gluPerspective");
}
fn gluScaleImageThunk(ex: *Executor) void {
    // GLU's gluScaleImage has nine 32-bit arguments on PE32. Keeping this
    // count exact matters because CallFrame reads directly from the guest
    // stack; a tenth word is the caller's following stack data, not an arg.
    invokeFrame(ex, 9, "gluScaleImage");
}
fn glAddSwapHintRectWinThunk(ex: *Executor) void {
    invokeFrame(ex, 4, "glAddSwapHintRectWIN");
}
fn glColorTableExtThunk(ex: *Executor) void {
    invokeFrame(ex, 6, "glColorTableEXT");
}
fn glColorSubTableExtThunk(ex: *Executor) void {
    invokeFrame(ex, 6, "glColorSubTableEXT");
}
fn glGetColorTableParameterivExtThunk(ex: *Executor) void {
    invokeFrame(ex, 3, "glGetColorTableParameterivEXT");
}

pub fn register(ex: *Executor) void {
    const map = &ex.import_table;
    map.put("wglCreateContext", wglCreateContextThunk) catch {};
    map.put("wglMakeCurrent", wglMakeCurrentThunk) catch {};
    map.put("wglDeleteContext", wglDeleteContextThunk) catch {};
    map.put("wglGetProcAddress", wglGetProcAddressThunk) catch {};
    map.put("glBegin", glBeginThunk) catch {};
    map.put("glEnd", glEndThunk) catch {};
    map.put("glVertex3f", glVertex3fThunk) catch {};
    map.put("glVertex2f", glVertex2fThunk) catch {};
    map.put("glVertex3dv", glVertex3dvThunk) catch {};
    map.put("glNormal3f", glNormal3fThunk) catch {};
    map.put("glNormal3dv", glNormal3dvThunk) catch {};
    map.put("glColor3f", glColor3fThunk) catch {};
    map.put("glColor3fv", glColor3fvThunk) catch {};
    map.put("glColor4fv", glColor4fvThunk) catch {};
    map.put("glTexCoord2f", glTexCoord2fThunk) catch {};
    map.put("glTexCoord2d", glTexCoord2dThunk) catch {};
    map.put("glMatrixMode", glMatrixModeThunk) catch {};
    map.put("glLoadIdentity", glLoadIdentityThunk) catch {};
    map.put("glPushMatrix", glPushMatrixThunk) catch {};
    map.put("glPopMatrix", glPopMatrixThunk) catch {};
    map.put("glTranslatef", glTranslatefThunk) catch {};
    map.put("glTranslated", glTranslatedThunk) catch {};
    map.put("glRotatef", glRotatefThunk) catch {};
    map.put("glRotated", glRotatedThunk) catch {};
    map.put("glScaled", glScaledThunk) catch {};
    map.put("glEnable", glEnableThunk) catch {};
    map.put("glDisable", glDisableThunk) catch {};
    map.put("glHint", glHintThunk) catch {};
    map.put("glScissor", glScissorThunk) catch {};
    map.put("glViewport", glViewportThunk) catch {};
    map.put("glCullFace", glCullFaceThunk) catch {};
    map.put("glFrontFace", glFrontFaceThunk) catch {};
    map.put("glLightModelfv", glLightModelfvThunk) catch {};
    map.put("glLightModeli", glLightModeliThunk) catch {};
    map.put("glLightfv", glLightfvThunk) catch {};
    map.put("glTexEnvi", glTexEnviThunk) catch {};
    map.put("glGetTexEnviv", glGetTexEnvivThunk) catch {};
    map.put("glGenTextures", glGenTexturesThunk) catch {};
    map.put("glDeleteTextures", glDeleteTexturesThunk) catch {};
    map.put("glBindTexture", glBindTextureThunk) catch {};
    map.put("glTexImage2D", glTexImage2DThunk) catch {};
    map.put("glTexParameteri", glTexParameteriThunk) catch {};
    map.put("glShadeModel", glShadeModelThunk) catch {};
    map.put("glPolygonMode", glPolygonModeThunk) catch {};
    map.put("glClearDepth", glClearDepthThunk) catch {};
    map.put("glPixelStorei", glPixelStoreiThunk) catch {};
    map.put("glBlendFunc", glBlendFuncThunk) catch {};
    map.put("glClear", glClearThunk) catch {};
    map.put("glFlush", glFlushThunk) catch {};
    map.put("glFinish", glFinishThunk) catch {};
    map.put("glGetString", glGetStringThunk) catch {};
    map.put("glGetIntegerv", glGetIntegervThunk) catch {};
    map.put("glGenLists", glGenListsThunk) catch {};
    map.put("glNewList", glNewListThunk) catch {};
    map.put("glEndList", glEndListThunk) catch {};
    map.put("glCallList", glCallListThunk) catch {};
    map.put("gluLookAt", gluLookAtThunk) catch {};
    map.put("gluOrtho2D", gluOrtho2DThunk) catch {};
    map.put("gluPerspective", gluPerspectiveThunk) catch {};
    map.put("gluScaleImage", gluScaleImageThunk) catch {};
    map.put("glAddSwapHintRectWIN", glAddSwapHintRectWinThunk) catch {};
    map.put("glColorTableEXT", glColorTableExtThunk) catch {};
    map.put("glColorSubTableEXT", glColorSubTableExtThunk) catch {};
    map.put("glGetColorTableParameterivEXT", glGetColorTableParameterivExtThunk) catch {};

    registerDynamicTargets(ex);
}

pub fn registerDynamicTargets(ex: *Executor) void {
    execution_engine.addIatDirectTargetForExecutor(ex, 0x7F00_0001, "glAddSwapHintRectWIN");
    execution_engine.addIatDirectTargetForExecutor(ex, 0x7F00_0002, "glColorTableEXT");
    execution_engine.addIatDirectTargetForExecutor(ex, 0x7F00_0003, "glColorSubTableEXT");
    execution_engine.addIatDirectTargetForExecutor(ex, 0x7F00_0004, "glGetColorTableParameterivEXT");
}

test "WGL extension lookup exposes only registered native extension thunks" {
    var executor = Executor.init(std.testing.allocator, 4096);
    defer executor.deinit();
    executor.regs.esp = 2048;
    execution_engine.clearIatEntries();
    register(&executor);

    executor.mem.write32(1024, 'g' | (@as(u32, 'l') << 8) | (@as(u32, 'C') << 16) | (@as(u32, 'o') << 24));
    executor.mem.write32(1028, 'l' | (@as(u32, 'o') << 8) | (@as(u32, 'r') << 16) | (@as(u32, 'T') << 24));
    executor.mem.write32(1032, 'a' | (@as(u32, 'b') << 8) | (@as(u32, 'l') << 16) | (@as(u32, 'e') << 24));
    executor.mem.write32(1036, 'E' | (@as(u32, 'X') << 8) | (@as(u32, 'T') << 16));
    executor.mem.write8(1040, 0);
    executor.push(1024);
    executor.dispatch_import("wglGetProcAddress");
    try std.testing.expectEqual(@as(u32, 0x7F00_0002), executor.regs.eax);
    try std.testing.expectEqual(@as(?u32, 0x7F00_0002), execution_engine.lookupIatDirectFunctionPointer(&executor, "glColorTableEXT"));
}
