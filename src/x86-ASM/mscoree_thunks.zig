const std = @import("std");
const testing = std.testing;
const Executor = @import("instruction_operations.zig").Executor;
const abi = @import("abi_handshake.zig");
const clr_runtime = @import("clr_runtime");

const RTLD_NOW = 2;

extern fn dlopen(path: [*:0]const u8, flags: i32) ?*anyopaque;
extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern fn dlclose(handle: *anyopaque) i32;

const S_OK: u32 = 0x00000000;
const S_FALSE: u32 = 0x00000001;
const E_FAIL: u32 = 0x80004005;
const E_NOTIMPL: u32 = 0x80004001;
const E_POINTER: u32 = 0x80004003;
const E_INVALIDARG: u32 = 0x80070057;
const CLASS_E_CLASSNOTAVAILABLE: u32 = 0x80040111;
const CLR_E_SHIM_RUNTIMEEXPORT: u32 = 0x80131018;

fn finishHR(frame: abi.CallFrame, hr: u32) void {
    frame.finish(hr);
}

fn finishTrue(frame: abi.CallFrame) void {
    frame.finish(1);
}

fn finishFalse(frame: abi.CallFrame) void {
    frame.finish(0);
}

fn writeMem16(ctx: *Executor, ptr: u32, val: u16) void {
    if (ptr != 0) ctx.mem.write16(ptr, val);
}

fn writeMem32(ctx: *Executor, ptr: u32, val: u32) void {
    if (ptr != 0) ctx.mem.write32(ptr, val);
}

fn envEnabled(name: [*:0]const u8) bool {
    const value_ptr = std.c.getenv(name) orelse return false;
    const value = std.mem.sliceTo(value_ptr, 0);
    return std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true");
}

/// Register mscoree.dll thunks needed by .NET executables.
/// Based on the export surface in mscoree.spec and Wine's mscoree_main.c.
pub fn register_mscoree_thunks(ex: *Executor) void {
    const map = &ex.import_table;

    map.put("_CorExeMain", struct {
        fn handler(ctx: *Executor) void {
            if (!envEnabled("ROSETTE_ENABLE_NATIVE_MSCOREE")) {
                finishHR(abi.CallFrame.raw(ctx, 0), E_FAIL);
                return;
            }

            // Try new CLR runtime first
            if (envEnabled("ROSETTE_ENABLE_CLR_RUNTIME")) {
                if (comptime std.debug.runtime_safety) {
                    std.log.debug("_CorExeMain: CLR runtime enabled - letting guest complete normally, host will handle CLR execution after guest terminates", .{});
                }
                // Don't terminate immediately - let guest complete normal Windows initialization
                // The CLR runtime will execute managed code in host context after guest terminates
                // Fall through to fallback which will handle the native library call
            }
            // Fallback to native library
            if (comptime std.debug.runtime_safety) {
                std.log.debug("_CorExeMain: attempting native library load", .{});
            }
            const lib_path: [*:0]const u8 = "zig-out/bin/libmscoree_native.dylib";
            const sym_name: [*:0]const u8 = "_CorExeMain";
            if (dlopen(lib_path, RTLD_NOW)) |lib| {
                if (comptime std.debug.runtime_safety) {
                    std.log.debug("_CorExeMain: loaded native library", .{});
                }
                defer _ = dlclose(lib);
                if (dlsym(lib, sym_name)) |sym| {
                    if (comptime std.debug.runtime_safety) {
                        std.log.debug("_CorExeMain: found symbol, calling native function", .{});
                    }
                    const func: *const fn () callconv(.c) u32 = @ptrCast(@alignCast(sym));
                    const result = func();
                    if (comptime std.debug.runtime_safety) {
                        std.log.debug("_CorExeMain: native returned {x}, terminating guest", .{result});
                    }
                    ctx.terminate(result);
                    return;
                } else if (comptime std.debug.runtime_safety) {
                    std.log.debug("_CorExeMain: symbol not found in native library", .{});
                }
            } else if (comptime std.debug.runtime_safety) {
                std.log.debug("_CorExeMain: failed to load native library", .{});
            }
            finishHR(abi.CallFrame.raw(ctx, 0), E_FAIL);
        }
    }.handler) catch {};

    map.put("_CorExeMain2", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 5), E_FAIL);
        }
    }.handler) catch {};

    map.put("_CorValidateImage", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 2), E_FAIL);
        }
    }.handler) catch {};

    map.put("_CorImageUnloading", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 1), S_OK);
        }
    }.handler) catch {};

    map.put("_CorDllMain", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 3), S_OK);
        }
    }.handler) catch {};

    map.put("CorExitProcess", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 1);
            const code = frame.arg(0);
            ctx.terminate(code);
        }
    }.handler) catch {};

    map.put("CorBindToRuntimeEx", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 6);
            const ppv = frame.arg(5);
            writeMem32(ctx, ppv, 0);
            finishHR(frame, CLASS_E_CLASSNOTAVAILABLE);
        }
    }.handler) catch {};

    map.put("CorBindToRuntimeHost", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 8);
            const ppv = frame.arg(7);
            writeMem32(ctx, ppv, 0);
            finishHR(frame, CLASS_E_CLASSNOTAVAILABLE);
        }
    }.handler) catch {};

    map.put("CorBindToCurrentRuntime", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 4);
            const ppv = frame.arg(3);
            writeMem32(ctx, ppv, 0);
            finishHR(frame, CLASS_E_CLASSNOTAVAILABLE);
        }
    }.handler) catch {};

    map.put("CLRCreateInstance", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const ppInterface = frame.arg(2);
            writeMem32(ctx, ppInterface, 0);
            finishHR(frame, CLASS_E_CLASSNOTAVAILABLE);
        }
    }.handler) catch {};

    map.put("CreateInterface", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const ppInterface = frame.arg(2);
            writeMem32(ctx, ppInterface, 0);
            finishHR(frame, CLASS_E_CLASSNOTAVAILABLE);
        }
    }.handler) catch {};

    map.put("GetCORVersion", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const dwLength = frame.arg(2);
            writeMem32(ctx, dwLength, 0);
            finishHR(frame, E_FAIL);
        }
    }.handler) catch {};

    map.put("GetCORSystemDirectory", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const dwLength = frame.arg(2);
            writeMem32(ctx, dwLength, 0);
            finishHR(frame, E_FAIL);
        }
    }.handler) catch {};

    map.put("GetRequestedRuntimeInfo", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 11);
            const dwDirectoryLength = frame.arg(6);
            const dwlength = frame.arg(10);
            writeMem32(ctx, dwDirectoryLength, 0);
            writeMem32(ctx, dwlength, 0);
            finishHR(frame, E_FAIL);
        }
    }.handler) catch {};

    map.put("GetRequestedRuntimeVersion", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 4);
            const dwlength = frame.arg(3);
            if (dwlength == 0) {
                finishHR(frame, E_POINTER);
                return;
            }
            writeMem32(ctx, dwlength, 0);
            finishHR(frame, E_FAIL);
        }
    }.handler) catch {};

    map.put("GetRealProcAddress", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const ppv = frame.arg(1);
            writeMem32(ctx, ppv, 0);
            finishHR(frame, CLR_E_SHIM_RUNTIMEEXPORT);
        }
    }.handler) catch {};

    map.put("GetFileVersion", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 4);
            const dwLength = frame.arg(3);
            writeMem32(ctx, dwLength, 0);
            finishHR(frame, E_FAIL);
        }
    }.handler) catch {};

    map.put("LoadLibraryShim", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 4);
            const phModDll = frame.arg(3);
            writeMem32(ctx, phModDll, 0);
            finishHR(frame, E_FAIL);
        }
    }.handler) catch {};

    map.put("LoadStringRC", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 4), E_NOTIMPL);
        }
    }.handler) catch {};

    map.put("LoadStringRCEx", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 6);
            const pBufLen = frame.arg(5);
            writeMem32(ctx, pBufLen, 0);
            finishHR(frame, E_NOTIMPL);
        }
    }.handler) catch {};

    map.put("LockClrVersion", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 3), S_OK);
        }
    }.handler) catch {};

    map.put("CoInitializeCor", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 1), S_OK);
        }
    }.handler) catch {};

    map.put("CoEEShutDownCOM", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 0), S_OK);
        }
    }.handler) catch {};

    map.put("CorGetSvc", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 1), E_NOTIMPL);
        }
    }.handler) catch {};

    map.put("CorIsLatestSvc", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 2), S_OK);
        }
    }.handler) catch {};

    map.put("StrongNameSignatureVerification", struct {
        fn handler(ctx: *Executor) void {
            finishFalse(abi.CallFrame.raw(ctx, 3));
        }
    }.handler) catch {};

    map.put("StrongNameSignatureVerificationEx", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const pVerified = frame.arg(2);
            writeMem32(ctx, pVerified, 1);
            finishTrue(frame);
        }
    }.handler) catch {};

    map.put("StrongNameTokenFromAssembly", struct {
        fn handler(ctx: *Executor) void {
            finishFalse(abi.CallFrame.raw(ctx, 3));
        }
    }.handler) catch {};

    map.put("CreateDebuggingInterfaceFromVersion", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const ppv = frame.arg(2);
            writeMem32(ctx, ppv, 0);
            finishHR(frame, E_FAIL);
        }
    }.handler) catch {};

    map.put("ClrCreateManagedInstance", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const ppObject = frame.arg(2);
            writeMem32(ctx, ppObject, 0);
            finishHR(frame, E_FAIL);
        }
    }.handler) catch {};

    map.put("GetAssemblyMDImport", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const ppIUnk = frame.arg(2);
            writeMem32(ctx, ppIUnk, 0);
            finishHR(frame, E_NOTIMPL);
        }
    }.handler) catch {};

    map.put("GetVersionFromProcess", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 4), E_NOTIMPL);
        }
    }.handler) catch {};

    map.put("DllCanUnloadNow", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 0), S_OK);
        }
    }.handler) catch {};

    map.put("DllGetClassObject", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const ppv = frame.arg(2);
            writeMem32(ctx, ppv, 0);
            finishHR(frame, CLASS_E_CLASSNOTAVAILABLE);
        }
    }.handler) catch {};

    map.put("DllRegisterServer", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 0), S_OK);
        }
    }.handler) catch {};

    map.put("DllUnregisterServer", struct {
        fn handler(ctx: *Executor) void {
            finishHR(abi.CallFrame.raw(ctx, 0), S_OK);
        }
    }.handler) catch {};

    map.put("ND_RU1", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const ptr = frame.arg(0);
            const offset = frame.arg(1);
            if (ptr != 0 and offset >= 0) {
                const addr = ptr + @as(u32, @intCast(offset));
                const val = ctx.mem.read8(addr);
                frame.finish(val);
            } else {
                frame.finish(0);
            }
        }
    }.handler) catch {};

    map.put("ND_RI2", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const ptr = frame.arg(0);
            const offset = frame.arg(1);
            if (ptr != 0 and offset >= 0) {
                const addr = ptr + @as(u32, @intCast(offset));
                const val = ctx.mem.read16(addr);
                frame.finish(val);
            } else {
                frame.finish(0);
            }
        }
    }.handler) catch {};

    map.put("ND_RI4", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const ptr = frame.arg(0);
            const offset = frame.arg(1);
            if (ptr != 0 and offset >= 0) {
                const addr = ptr + @as(u32, @intCast(offset));
                const val = ctx.mem.read32(addr);
                frame.finish(val);
            } else {
                frame.finish(0);
            }
        }
    }.handler) catch {};

    map.put("ND_RI8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 2);
            const ptr = frame.arg(0);
            const offset = frame.arg(1);
            if (ptr != 0) {
                const addr = ptr + offset;
                const lo = ctx.mem.read32(addr);
                const hi = ctx.mem.read32(addr + 4);
                ctx.regs.edx = hi;
                frame.finish(lo);
            } else {
                frame.finish(0);
            }
        }
    }.handler) catch {};

    map.put("ND_WU1", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const ptr = frame.arg(0);
            const offset = frame.arg(1);
            const val: u8 = @truncate(frame.arg(2));
            if (ptr != 0 and offset >= 0) {
                ctx.mem.write8(ptr + @as(u32, @intCast(offset)), val);
            }
            frame.finish(0);
        }
    }.handler) catch {};

    map.put("ND_WI2", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const ptr = frame.arg(0);
            const offset = frame.arg(1);
            const val: u16 = @truncate(frame.arg(2));
            if (ptr != 0 and offset >= 0) {
                ctx.mem.write16(ptr + @as(u32, @intCast(offset)), val);
            }
            frame.finish(0);
        }
    }.handler) catch {};

    map.put("ND_WI4", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 3);
            const ptr = frame.arg(0);
            const offset = frame.arg(1);
            const val = frame.arg(2);
            if (ptr != 0 and offset >= 0) {
                ctx.mem.write32(ptr + @as(u32, @intCast(offset)), val);
            }
            frame.finish(0);
        }
    }.handler) catch {};

    map.put("ND_WI8", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 4);
            const ptr = frame.arg(0);
            const offset = frame.arg(1);
            const val_lo = frame.arg(2);
            const val_hi = frame.arg(3);
            if (ptr != 0 and offset >= 0) {
                ctx.mem.write32(ptr + @as(u32, @intCast(offset)), val_lo);
                ctx.mem.write32(ptr + @as(u32, @intCast(offset)) + 4, val_hi);
            }
            frame.finish(0);
        }
    }.handler) catch {};

    map.put("ND_CopyObjDst", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 4);
            const src_ptr = frame.arg(0);
            const dst_ptr = frame.arg(1);
            const offset = @as(i32, @bitCast(frame.arg(2)));
            const size = @as(i32, @bitCast(frame.arg(3)));
            if (src_ptr != 0 and dst_ptr != 0 and offset >= 0 and size >= 0) {
                const dst_addr = dst_ptr + @as(u32, @intCast(offset));
                const src_addr_rel = src_ptr - ctx.mem.base;
                const dst_addr_rel = dst_addr - ctx.mem.base;
                const src_slice = ctx.mem.data[src_addr_rel .. src_addr_rel + @as(usize, @intCast(size))];
                const dst_slice = ctx.mem.data[dst_addr_rel .. dst_addr_rel + @as(usize, @intCast(size))];
                @memcpy(dst_slice, src_slice);
            }
            frame.finish(0);
        }
    }.handler) catch {};

    map.put("ND_CopyObjSrc", struct {
        fn handler(ctx: *Executor) void {
            const frame = abi.CallFrame.raw(ctx, 4);
            const src_ptr = frame.arg(0);
            const offset = @as(i32, @bitCast(frame.arg(1)));
            const dst_ptr = frame.arg(2);
            const size = @as(i32, @bitCast(frame.arg(3)));
            if (src_ptr != 0 and dst_ptr != 0 and offset >= 0 and size >= 0) {
                const src_addr = src_ptr + @as(u32, @intCast(offset));
                const src_addr_rel = src_addr - ctx.mem.base;
                const dst_addr_rel = dst_ptr - ctx.mem.base;
                const src_slice = ctx.mem.data[src_addr_rel .. src_addr_rel + @as(usize, @intCast(size))];
                const dst_slice = ctx.mem.data[dst_addr_rel .. dst_addr_rel + @as(usize, @intCast(size))];
                @memcpy(dst_slice, src_slice);
            }
            frame.finish(0);
        }
    }.handler) catch {};
}

test "register mscoree thunks" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_mscoree_thunks(&ex);
    try testing.expect(ex.import_table.contains("_CorExeMain"));
    try testing.expect(ex.import_table.contains("CorExitProcess"));
    try testing.expect(ex.import_table.contains("CorBindToRuntimeEx"));
    try testing.expect(ex.import_table.contains("CLRCreateInstance"));
    try testing.expect(ex.import_table.contains("GetCORVersion"));
}

test "_CorExeMain returns E_FAIL" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 2048;
    register_mscoree_thunks(&ex);
    ex.dispatch_import("_CorExeMain");
    try testing.expectEqual(E_FAIL, ex.regs.eax);
}

test "StrongNameSignatureVerificationEx returns TRUE and sets pVerified" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;

    const verified_ptr: u32 = 256;
    ex.push(verified_ptr);
    ex.push(1);
    ex.push(0x1000);

    register_mscoree_thunks(&ex);
    ex.dispatch_import("StrongNameSignatureVerificationEx");

    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try testing.expectEqual(@as(u32, 1), ex.mem.read32(verified_ptr));
}

test "ND_RI4 reads from emulated memory" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.mem.write32(100, 0xDEADBEEF);

    ex.push(2);
    ex.push(100);
    register_mscoree_thunks(&ex);
    ex.dispatch_import("ND_RI4");

    try testing.expectEqual(@as(u32, 0xDEADBEEF), ex.regs.eax);
}

test "ND_WI4 writes to emulated memory" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;

    ex.push(0xCAFEBABE);
    ex.push(0);
    ex.push(200);
    register_mscoree_thunks(&ex);
    ex.dispatch_import("ND_WI4");

    try testing.expectEqual(@as(u32, 0xCAFEBABE), ex.mem.read32(200));
}
