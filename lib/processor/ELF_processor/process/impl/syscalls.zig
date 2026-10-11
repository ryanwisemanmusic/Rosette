const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_execution = @import("execution.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const __process_SYS_arch_prctl = __ProcessInternals._SYS_arch_prctl;
const __process_SYS_close = __ProcessInternals._SYS_close;
const __process_SYS_creat = __ProcessInternals._SYS_creat;
const __process_SYS_exit = __ProcessInternals._SYS_exit;
const __process_SYS_gettid = __ProcessInternals._SYS_gettid;
const __process_SYS_open = __ProcessInternals._SYS_open;
const __process_SYS_read = __ProcessInternals._SYS_read;
const __process_SYS_write = __ProcessInternals._SYS_write;
const __process_hostFdFromGuest = __ProcessInternals._hostFdFromGuest;
const __process_linuxOpenFlagsToHost = __ProcessInternals._linuxOpenFlagsToHost;
const __process_log = __ProcessInternals._log;
const __process_std = __ProcessInternals._std;
const __process_syscallResult = __ProcessInternals._syscallResult;
const __process_x64_syscalls = __ProcessInternals._x64_syscalls;

pub fn invokeLinuxSyscall(self: *ElfState, number: u64, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = number;
    process_impl_lifecycle.guestContextField(self, "regs").*.rdi = arg1;
    process_impl_lifecycle.guestContextField(self, "regs").*.rsi = arg2;
    process_impl_lifecycle.guestContextField(self, "regs").*.rdx = arg3;
    process_impl_lifecycle.guestContextField(self, "regs").*.r10 = arg4;
    process_impl_lifecycle.guestContextField(self, "regs").*.r8 = arg5;
    process_impl_lifecycle.guestContextField(self, "regs").*.r9 = arg6;
    dispatchLinuxSyscall(self);
}

pub fn dispatchLinuxSyscall(self: *ElfState) void {
    switch (process_impl_lifecycle.guestContextField(self, "regs").*.rax) {
        __process_SYS_exit => {
            self.exit_code = process_impl_lifecycle.guestContextField(self, "regs").*.rdi;
            process_impl_lifecycle.markTerminated(self);
            process_impl_execution.traceSyscall(self, "exit(code={d})", .{self.exit_code});
        },
        __process_SYS_read => {
            handleReadSyscall(self);
        },
        __process_SYS_write => {
            handleWriteSyscall(self);
        },
        __process_SYS_open => {
            handleOpenSyscall(self);
        },
        __process_SYS_close => {
            handleCloseSyscall(self);
        },
        __process_SYS_creat => {
            handleCreatSyscall(self);
        },
        __process_SYS_arch_prctl => {
            handleArchPrctlSyscall(self);
        },
        __process_SYS_gettid => {
            process_impl_lifecycle.guestContextField(self, "regs").*.rax = 1;
            process_impl_execution.traceSyscall(self, "gettid() -> {d}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rax});
        },
        else => {
            __process_log.warn("unimplemented syscall {d}", .{process_impl_lifecycle.guestContextField(self, "regs").*.rax});
            process_impl_lifecycle.markFaulted(self);
            self.exit_code = 127;
            process_impl_lifecycle.markTerminated(self);
        },
    }
}

pub fn guestCString(self: *ElfState, addr: u64, maximum: usize) ?[]const u8 {
    return process_impl_execution.guestCStringConst(self, addr, maximum);
}

pub fn handleArchPrctlSyscall(self: *ElfState) void {
    const ARCH_SET_GS: u64 = 0x1001;
    const ARCH_SET_FS: u64 = 0x1002;
    const ARCH_GET_FS: u64 = 0x1003;
    const ARCH_GET_GS: u64 = 0x1004;
    const code = process_impl_lifecycle.guestContextField(self, "regs").*.rdi;
    const address = process_impl_lifecycle.guestContextField(self, "regs").*.rsi;
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = switch (code) {
        ARCH_SET_FS => blk: {
            process_impl_lifecycle.guestContextField(self, "regs").*.segments.fs.base = address;
            break :blk 0;
        },
        ARCH_SET_GS => blk: {
            process_impl_lifecycle.guestContextField(self, "regs").*.segments.gs.base = address;
            break :blk 0;
        },
        ARCH_GET_FS, ARCH_GET_GS => blk: {
            const off = process_impl_guest_memory.addrToOffset(self, address) orelse break :blk __process_x64_syscalls.errnoValue(.bad_address);
            if (off + 8 > self.mem.len) break :blk __process_x64_syscalls.errnoValue(.bad_address);
            const base = if (code == ARCH_GET_FS) process_impl_lifecycle.guestContextField(self, "regs").*.segments.fs.base else process_impl_lifecycle.guestContextField(self, "regs").*.segments.gs.base;
            process_impl_guest_memory.write64(self, address, base);
            break :blk 0;
        },
        else => __process_x64_syscalls.errnoValue(.invalid_argument),
    };
    process_impl_execution.traceSyscall(self, "arch_prctl(code=0x{x}, address=0x{x}) -> {d}", .{ code, address, __process_syscallResult(process_impl_lifecycle.guestContextField(self, "regs").*.rax) });
}

pub fn handleOpenSyscall(self: *ElfState) void {
    const path_addr = process_impl_lifecycle.guestContextField(self, "regs").*.rdi;
    const flags_raw = process_impl_lifecycle.guestContextField(self, "regs").*.rsi;
    const mode_raw = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
    const path = guestCString(self, process_impl_lifecycle.guestContextField(self, "regs").*.rdi, __process_std.math.maxInt(usize)) orelse {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.bad_address);
        process_impl_execution.traceSyscall(self, "open(path=0x{x}, flags=0x{x}, mode=0o{o}) -> {d}", .{
            path_addr,
            flags_raw,
            mode_raw & 0o7777,
            __process_syscallResult(process_impl_lifecycle.guestContextField(self, "regs").*.rax),
        });
        return;
    };
    const path_z = self.allocator.dupeZ(u8, path) catch {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.io);
        process_impl_execution.traceSyscall(self, "open(\"{s}\", flags=0x{x}, mode=0o{o}) -> {d}", .{
            path,
            flags_raw,
            mode_raw & 0o7777,
            __process_syscallResult(process_impl_lifecycle.guestContextField(self, "regs").*.rax),
        });
        return;
    };
    defer self.allocator.free(path_z);

    const fd = __process_std.c.open(path_z.ptr, __process_linuxOpenFlagsToHost(flags_raw), @as(__process_std.c.mode_t, @intCast(mode_raw & 0o7777)));
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = if (fd < 0) __process_x64_syscalls.errnoValue(.no_entry) else @as(u64, @intCast(fd));
    process_impl_execution.traceOpenResult(self, path, flags_raw, mode_raw, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
}

pub fn handleCreatSyscall(self: *ElfState) void {
    const path_addr = process_impl_lifecycle.guestContextField(self, "regs").*.rdi;
    const requested_mode = if (process_impl_lifecycle.guestContextField(self, "regs").*.rdx != 0) process_impl_lifecycle.guestContextField(self, "regs").*.rdx else process_impl_lifecycle.guestContextField(self, "regs").*.rsi;
    const path = guestCString(self, process_impl_lifecycle.guestContextField(self, "regs").*.rdi, __process_std.math.maxInt(usize)) orelse {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.bad_address);
        process_impl_execution.traceSyscall(self, "creat(path=0x{x}, mode=0o{o}) -> {d}", .{
            path_addr,
            requested_mode & 0o7777,
            __process_syscallResult(process_impl_lifecycle.guestContextField(self, "regs").*.rax),
        });
        return;
    };
    const path_z = self.allocator.dupeZ(u8, path) catch {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.io);
        process_impl_execution.traceSyscall(self, "creat(\"{s}\", mode=0o{o}) -> {d}", .{
            path,
            requested_mode & 0o7777,
            __process_syscallResult(process_impl_lifecycle.guestContextField(self, "regs").*.rax),
        });
        return;
    };
    defer self.allocator.free(path_z);
    if (self.diagnose_abi) rememberInteractiveOutputPath(self, path);

    var flags: __process_std.c.O = .{};
    flags.ACCMODE = .WRONLY;
    flags.CREAT = true;
    flags.TRUNC = true;
    const mode: __process_std.c.mode_t = @intCast(requested_mode & 0o7777);
    var fd = __process_std.c.open(path_z.ptr, flags, mode);
    if (fd < 0) {
        _ = __process_std.c.unlink(path_z.ptr);
        fd = __process_std.c.open(path_z.ptr, flags, mode);
    }
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = if (fd < 0) __process_x64_syscalls.errnoValue(.io) else @as(u64, @intCast(fd));
    process_impl_execution.traceCreatResult(self, path, requested_mode, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
}

pub fn rememberInteractiveOutputPath(self: *ElfState, path: []const u8) void {
    const copy = self.allocator.dupe(u8, path) catch return;
    if (self.interactive_output_path) |old| self.allocator.free(old);
    self.interactive_output_path = copy;
    self.interactive_summary_printed = false;
}

pub fn handleReadSyscall(self: *ElfState) void {
    const fd_raw = process_impl_lifecycle.guestContextField(self, "regs").*.rdi;
    const fd = __process_hostFdFromGuest(fd_raw) orelse {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.bad_file_descriptor);
        process_impl_execution.traceGuestIo(self, "read", fd_raw, process_impl_lifecycle.guestContextField(self, "regs").*.rsi, process_impl_lifecycle.guestContextField(self, "regs").*.rdx, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
        return;
    };
    const addr = process_impl_lifecycle.guestContextField(self, "regs").*.rsi;
    const count = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
    const destination = process_impl_execution.guestMemoryTsoWriteTarget(self, addr, count) orelse {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.bad_address);
        process_impl_execution.traceGuestIo(self, "read", fd_raw, addr, count, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
        return;
    };
    const staging = self.allocator.alloc(u8, destination.len) catch {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.io);
        process_impl_execution.traceGuestIo(self, "read", fd_raw, addr, count, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
        return;
    };
    defer self.allocator.free(staging);

    const n = __process_std.c.read(fd, staging.ptr, staging.len);
    if (n < 0) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.io);
    } else {
        const copied: usize = @intCast(n);
        process_impl_guest_memory.copyGuestBackingForClass(
            self,
            destination[0..copied],
            staging[0..copied],
            process_impl_guest_memory.guestMemoryRangeClass(self, addr, @intCast(copied), true),
        );
        process_impl_execution.finishGuestMemoryTsoWrite(self, addr, @intCast(copied));
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = @intCast(n);
    }
    process_impl_execution.traceGuestIo(self, "read", fd_raw, addr, count, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
}

pub fn handleCloseSyscall(self: *ElfState) void {
    const fd_raw = process_impl_lifecycle.guestContextField(self, "regs").*.rdi;
    const fd = __process_hostFdFromGuest(fd_raw) orelse {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.bad_file_descriptor);
        if (process_impl_execution.shouldTraceFd(self, fd_raw)) {
            __process_log.info("syscall: close(fd={d}) -> {d}", .{ fd_raw, __process_syscallResult(process_impl_lifecycle.guestContextField(self, "regs").*.rax) });
        }
        return;
    };
    if (fd <= 2) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = 0;
        if (process_impl_execution.shouldTraceFd(self, fd_raw)) {
            __process_log.info("syscall: close(fd={d}) -> {d}", .{ fd, __process_syscallResult(process_impl_lifecycle.guestContextField(self, "regs").*.rax) });
        }
        return;
    }
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = if (__process_std.c.close(fd) == 0) 0 else __process_x64_syscalls.errnoValue(.bad_file_descriptor);
    if (process_impl_execution.shouldTraceFd(self, fd_raw)) {
        __process_log.info("syscall: close(fd={d}) -> {d}", .{ fd, __process_syscallResult(process_impl_lifecycle.guestContextField(self, "regs").*.rax) });
    }
}

pub fn handleWriteSyscall(self: *ElfState) void {
    const fd = process_impl_lifecycle.guestContextField(self, "regs").*.rdi;
    const addr = process_impl_lifecycle.guestContextField(self, "regs").*.rsi;
    const count = process_impl_lifecycle.guestContextField(self, "regs").*.rdx;
    if (process_impl_execution.guestMemoryConst(self, addr, count) == null) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.bad_address);
        process_impl_execution.traceGuestIo(self, "write", fd, addr, count, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
        return;
    }
    const staging = self.allocator.alloc(u8, @intCast(count)) catch {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.io);
        process_impl_execution.traceGuestIo(self, "write", fd, addr, count, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
        return;
    };
    defer self.allocator.free(staging);
    if (!process_impl_execution.copyFromGuest(self, staging, addr)) {
        process_impl_lifecycle.guestContextField(self, "regs").*.rax = __process_x64_syscalls.errnoValue(.bad_address);
        process_impl_execution.traceGuestIo(self, "write", fd, addr, count, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
        return;
    }
    process_impl_lifecycle.guestContextField(self, "regs").*.rax = process_impl_execution.writeHostFd(self, fd, staging);
    process_impl_execution.traceGuestIo(self, "write", fd, addr, count, process_impl_lifecycle.guestContextField(self, "regs").*.rax);
}
