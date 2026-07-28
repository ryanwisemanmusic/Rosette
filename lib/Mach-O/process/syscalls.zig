//! macOS syscall dispatch extracted from MachOState (process.zig).
//! Handles guest system call dispatching via the Mach-O ABI convention.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const macho_runtime = @import("macho_runtime");
const exit_diagnostics = @import("exit_diagnostics");
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const PAGE_SIZE = @import("../constants.zig").PAGE_SIZE;
const mappedOffset = @import("../utils.zig").mappedOffset;

fn resolveSyscallFd(self: anytype, guest_fd: u64) i32 {
    if (guest_fd < self.guest_fds.len) {
        const host = self.guest_fds[@as(usize, @intCast(guest_fd))];
        if (host >= 0) return host;
    }
    if (self.fs_forwarder.fd_manager.hostFd(guest_fd)) |host| return host;
    return -1;
}

pub fn dispatchMacOSSyscall(self: anytype, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
    const number = self.regs.rax;
    std.log.info("syscall: number=0x{x} ({s}) args=({d}, {d}, {d}, {d}, {d}, {d})", .{
        number, macho_runtime.syscallName(number),
        arg1,   arg2,
        arg3,   arg4,
        arg5,   arg6,
    });

    switch (number) {
        @intFromEnum(macho_runtime.Syscall.exit) => {
            const exit_code = arg1;
            std.log.info("exit({d})", .{exit_code});
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
            self.terminated = true;
            self.exit_code = exit_code;
        },
        @intFromEnum(macho_runtime.Syscall.open) => {
            const path = self.guestCString(arg1, 4096) orelse {
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            };
            var temp_buf: [4096]u8 = undefined;
            var translated_path = path;
            if (self.fs_forwarder.resolveHostPath(path, &temp_buf)) |t| {
                translated_path = t;
            }
            var path_buf: [4096]u8 = undefined;
            const plen = @min(translated_path.len, path_buf.len - 1);
            @memcpy(path_buf[0..plen], translated_path[0..plen]);
            path_buf[plen] = 0;
            const oflags: std.c.O = @bitCast(@as(u32, @truncate(arg2)));
            const mode: std.c.mode_t = @intCast(arg3 & 0xFFFF);
            var host_fd = std.c.open(@as([*:0]const u8, @ptrCast(&path_buf)), oflags, mode);
            if (host_fd < 0) {
                const err = std.c.errno(host_fd);
                if (err == .NOENT) {
                    if (self.fs_forwarder.tryOpenFallback(translated_path, oflags, @as(u32, @intCast(arg3)), err)) |fallback_fd| {
                        host_fd = fallback_fd;
                    }
                }
                if (host_fd < 0) {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                }
            }
            const guest_fd = self.fs_forwarder.fd_manager.register(host_fd, .file) orelse {
                _ = std.c.close(host_fd);
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            };
            if (guest_fd < self.guest_fds.len) {
                self.guest_fds[@as(usize, @intCast(guest_fd))] = host_fd;
            }
            self.regs.rax = guest_fd;
        },
        @intFromEnum(macho_runtime.Syscall.close) => {
            const close_guest_fd = arg1;
            if (close_guest_fd < self.guest_fds.len) {
                self.guest_fds[@as(usize, @intCast(close_guest_fd))] = -1;
            }
            const rc = self.fs_forwarder.fd_manager.close(close_guest_fd);
            self.regs.rax = if (rc < 0) std.math.maxInt(u64) else 0;
        },
        @intFromEnum(macho_runtime.Syscall.write) => {
            const fd = arg1;
            const buf = arg2;
            const count = arg3;
            const data = self.guestMemoryConst(buf, count) orelse {
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                return;
            };
            const host_fd = resolveSyscallFd(self, fd);
            var written: usize = 0;
            if (host_fd >= 0) {
                while (written < data.len) {
                    const n = std.c.write(host_fd, data[written..].ptr, data.len - written);
                    if (n <= 0) {
                        self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                        return;
                    }
                    written += @as(usize, @intCast(n));
                }
            }
            self.regs.rax = @intCast(written);
        },
        @intFromEnum(macho_runtime.Syscall.read) => {
            const fd = arg1;
            const buf = arg2;
            const count = arg3;
            const data = self.guestMemory(buf, count) orelse {
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                return;
            };
            const host_fd = resolveSyscallFd(self, fd);
            if (host_fd >= 0) {
                const n = std.c.read(host_fd, data.ptr, data.len);
                if (n < 0) {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                }
                self.regs.rax = @intCast(@as(usize, @intCast(n)));
            } else {
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
            }
        },
        @intFromEnum(macho_runtime.Syscall.mmap) => {
            const addr = arg1;
            const length = arg2;
            const prot = arg3;
            const raw_flags: u32 = @truncate(arg4);
            const map_flags: std.c.MAP = @bitCast(raw_flags);
            const offset: i64 = @bitCast(arg6);
            self.noteBackendMmapAttempt("syscall", addr, length, prot, raw_flags, map_flags.FIXED, map_flags.ANONYMOUS);

            const alignment = PAGE_SIZE;
            const aligned_length = ((length + alignment - 1) / alignment) * alignment;

            if (self.backendMemoryDiagnosticsActive() and addr == 0 and map_flags.ANONYMOUS and length >= 64 * 1024 * 1024) {
                const mapped = self.guestMapBackendWithBacking(length, @truncate(prot), raw_flags, -1, @bitCast(offset)) orelse {
                    machoCapturePrint(
                        "macho-processor: x64 backend sparse mmap FAILED: route=syscall address=0x0 length={d} prot=0x{x} flags=0x{x}\n",
                        .{ length, prot, raw_flags },
                    );
                    self.noteBackendMmapResult(false, 0, "syscall_backend_sparse_anywhere");
                    self.regs.rax = std.math.maxInt(u64);
                    return;
                };
                machoCapturePrint(
                    "macho-processor: x64 backend sparse mmap succeeded: route=syscall guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} heap_bypassed=true\n",
                    .{ mapped, length, prot, raw_flags },
                );
                self.noteBackendMmapResult(true, mapped, "syscall_backend_sparse_anywhere");
                self.regs.rax = mapped;
                return;
            }

            if (length >= 1024 * 1024 * 1024) {
                machoCapturePrint(
                    "macho-processor: large mmap entry: route=syscall addr=0x{x} length={d} aligned_length={d} prot=0x{x} flags=0x{x} fixed={} anonymous={} guest_fd=0x{x} offset={d}\n",
                    .{ addr, length, aligned_length, prot, raw_flags, map_flags.FIXED, map_flags.ANONYMOUS, arg5, offset },
                );
            }

            if (addr == 0 and prot == 0 and length >= 1024 * 1024 * 1024) {
                const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                    -1
                else
                    self.fs_forwarder.fd_manager.hostFd(arg5) orelse {
                        machoCapturePrint("macho-processor: large mmap FAILED: route=syscall stage=fd_translation guest_fd=0x{x}\n", .{arg5});
                        self.noteBackendMmapResult(false, 0, "syscall_large_fd_translation");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    };
                const reserved = self.guestReserveAddressSpaceWithBacking(aligned_length, raw_flags, host_fd, @bitCast(offset)) orelse {
                    machoCapturePrint("macho-processor: large mmap FAILED: route=syscall stage=sparse_reserve\n", .{});
                    self.noteBackendMmapResult(false, 0, "syscall_sparse_reserve");
                    self.regs.rax = std.math.maxInt(u64);
                    return;
                };
                machoCapturePrint("macho-processor: large mmap succeeded: route=syscall guest_base=0x{x} length={d}\n", .{ reserved, aligned_length });
                self.noteBackendMmapResult(true, reserved, "syscall_sparse_reserve");
                self.regs.rax = reserved;
                return;
            }

            if (addr != 0 and map_flags.FIXED) {
                const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                    -1
                else
                    self.fs_forwarder.fd_manager.hostFd(arg5) orelse {
                        machoCapturePrint("macho-processor: fixed mmap FAILED: route=syscall stage=fd_translation guest_fd=0x{x}\n", .{arg5});
                        self.noteBackendMmapResult(false, 0, "syscall_fixed_fd_translation");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    };
                if (!self.guestMapFile(addr, aligned_length, @truncate(prot), raw_flags, host_fd, @bitCast(offset))) {
                    machoCapturePrint("macho-processor: fixed mmap FAILED: route=syscall stage=sparse_map addr=0x{x} length={d}\n", .{ addr, aligned_length });
                    self.noteBackendMmapResult(false, 0, "syscall_fixed_sparse_map");
                    self.regs.rax = std.math.maxInt(u64);
                    return;
                }
                self.noteBackendMmapResult(true, addr, "syscall_fixed_sparse_map");
                self.regs.rax = addr;
                return;
            }

            const mapped = if (addr != 0) addr else self.guestAlloc(aligned_length, alignment) orelse {
                machoCapturePrint("macho-processor: mmap FAILED: route=syscall stage=guest_heap length={d} alignment={d}\n", .{ aligned_length, alignment });
                self.noteBackendMmapResult(false, 0, "syscall_guest_heap_allocate");
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            };
            const off = mappedOffset(self.mem_base, self.mem_size, self.mapped_min, mapped) orelse {
                self.noteBackendMmapResult(false, 0, "syscall_address_translation");
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            };
            if (off + aligned_length > self.mem_size) {
                self.noteBackendMmapResult(false, 0, "syscall_backing_bounds");
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            }
            @memset(self.mem[off..][0..@as(usize, @intCast(aligned_length))], 0);
            self.setPagePermissions(mapped, aligned_length, @truncate(prot & 0x07));
            _ = self.memory_regions.register(mapped, aligned_length, .{
                .read = prot & 0x01 != 0,
                .write = prot & 0x02 != 0,
                .execute = prot & 0x04 != 0,
            }, .guest_mmap, "guest mmap", self.regs.rip);
            self.noteBackendMmapResult(true, mapped, "syscall_guest_mapping");
            self.regs.rax = mapped;
        },
        @intFromEnum(macho_runtime.Syscall.mprotect) => {
            const address = arg1;
            const length = ((arg2 + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE;
            const prot = arg3;
            if (self.guestProtectSparseMemory(address, length, @truncate(prot))) {
                machoCapturePrint("macho-processor: sparse mprotect succeeded: route=syscall address=0x{x} length={d} prot=0x{x}\n", .{ address, length, prot });
                self.noteBackendMprotect("syscall", address, length, prot, true);
                self.regs.rax = 0;
                return;
            }
            if (mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) == null) {
                machoCapturePrint("macho-processor: mprotect FAILED: route=syscall reason=address_not_mapped address=0x{x} length={d} prot=0x{x}\n", .{ address, length, prot });
                self.noteBackendMprotect("syscall", address, length, prot, false);
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                return;
            }
            self.setPagePermissions(address, length, @truncate(prot & 0x07));
            _ = self.memory_regions.register(address, length, .{
                .read = prot & 0x01 != 0,
                .write = prot & 0x02 != 0,
                .execute = prot & 0x04 != 0,
            }, .guest_mmap, "guest mprotect", self.regs.rip);
            self.noteBackendMprotect("syscall", address, length, prot, true);
            self.regs.rax = 0;
        },
        @intFromEnum(macho_runtime.Syscall.munmap) => {
            const address = arg1;
            const length = ((arg2 + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE;
            if (self.guestUnmapFile(address, length)) {
                machoCapturePrint("macho-processor: sparse munmap succeeded: route=syscall address=0x{x} length={d}\n", .{ address, length });
                self.regs.rax = 0;
                return;
            }
            self.setPagePermissions(address, length, 0);
            _ = self.memory_regions.register(address, length, .{ .read = false, .write = false }, .guest_unmapped, "guest munmap", self.regs.rip);
            self.regs.rax = 0;
        },
        @intFromEnum(macho_runtime.Syscall.getpid) => {
            self.regs.rax = 42;
        },
        @intFromEnum(macho_runtime.Syscall.issetugid) => {
            self.regs.rax = 0;
        },
        0x2000072 => {
            self.regs.rax = 1;
        },
        else => {
            std.log.warn("unimplemented syscall: 0x{x}", .{number});
            self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
        },
    }
}
