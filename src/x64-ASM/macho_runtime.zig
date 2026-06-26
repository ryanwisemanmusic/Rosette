const std = @import("std");

pub const MACH_SYSCALL_BASE: u64 = 0x2000000;

pub const Syscall = enum(u32) {
    exit = MACH_SYSCALL_BASE | 1,
    fork = MACH_SYSCALL_BASE | 2,
    read = MACH_SYSCALL_BASE | 3,
    write = MACH_SYSCALL_BASE | 4,
    open = MACH_SYSCALL_BASE | 5,
    close = MACH_SYSCALL_BASE | 6,
    mmap = MACH_SYSCALL_BASE | 197,
    mprotect = MACH_SYSCALL_BASE | 74,
    munmap = MACH_SYSCALL_BASE | 73,
    issetugid = MACH_SYSCALL_BASE | 328,
    getpid = MACH_SYSCALL_BASE | 20,
    gettimeofday = MACH_SYSCALL_BASE | 116,
    thread_selfid = 0x2000072,
    bsdthread_create = 0x2000376,
    bsdthread_register = 0x2000387,
    thread_selfusage = 0x2000377,
    _
};

pub fn syscallName(number: u64) []const u8 {
    return switch (number) {
        MACH_SYSCALL_BASE | 1 => "exit",
        MACH_SYSCALL_BASE | 3 => "read",
        MACH_SYSCALL_BASE | 4 => "write",
        MACH_SYSCALL_BASE | 5 => "open",
        MACH_SYSCALL_BASE | 6 => "close",
        MACH_SYSCALL_BASE | 20 => "getpid",
        MACH_SYSCALL_BASE | 73 => "munmap",
        MACH_SYSCALL_BASE | 74 => "mprotect",
        MACH_SYSCALL_BASE | 116 => "gettimeofday",
        MACH_SYSCALL_BASE | 197 => "mmap",
        MACH_SYSCALL_BASE | 328 => "issetugid",
        0x2000072 => "thread_selfid",
        else => "unknown",
    };
}
