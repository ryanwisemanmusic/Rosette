const std = @import("std");
const x64_syscalls = @import("x64_syscalls");

pub fn setupInitialStack(state: anytype, argv: []const []const u8) !void {
    const default_argv = [_][]const u8{"program"};
    const actual_argv = if (argv.len == 0) default_argv[0..] else argv;
    var arg_ptrs = try state.allocator.alloc(u64, actual_argv.len);
    defer state.allocator.free(arg_ptrs);

    var sp = state.mem_base + state.mem_size;
    var i = actual_argv.len;
    while (i > 0) {
        i -= 1;
        const arg = actual_argv[i];
        sp -|= arg.len + 1;
        const off = state.addrToOffset(sp) orelse return error.StackOutOfRange;
        if (off + arg.len + 1 > state.mem.len) return error.StackOutOfRange;
        @memcpy(state.mem[off..][0..arg.len], arg);
        state.mem[off + arg.len] = 0;
        arg_ptrs[i] = sp;
    }

    sp &= ~@as(u64, 0xF);
    sp -|= 8;
    state.write64(sp, 0); // envp terminator
    sp -|= 8;
    state.write64(sp, 0); // argv terminator

    i = arg_ptrs.len;
    while (i > 0) {
        i -= 1;
        sp -|= 8;
        state.write64(sp, arg_ptrs[i]);
    }

    sp -|= 8;
    state.write64(sp, @intCast(actual_argv.len));
    state.regs.rsp = sp;
}

pub fn tryLibcStartMainTrampoline(state: anytype, d: anytype, return_rip: u64) bool {
    if (state.libc_start_main_trampolined) return false;
    if (!d.rip_relative) return false;

    const main_addr = state.regs.rdi;
    if (main_addr == 0 or state.addrToOffset(main_addr) == null) return false;

    const first = state.read8(main_addr);
    if (first != 0x55 and first != 0x48 and first != 0xF3) return false;

    const argc = state.regs.rsi;
    const argv = state.regs.rdx;
    state.regs.rdi = argc;
    state.regs.rsi = argv;
    state.regs.rdx = 0;
    state.push(return_rip);
    state.regs.rip = main_addr;
    state.libc_start_main_trampolined = true;
    std.log.scoped(.x64_linux_runtime).info("bridged unresolved __libc_start_main to main=0x{x} argc={d}", .{ main_addr, argc });
    return true;
}

pub fn tryDynamicFunctionShim(state: anytype, got_addr: u64, direct_return_rip: ?u64) bool {
    const name = dynamicRelocationName(state, got_addr) orelse return false;
    if (symbolNameEql(name, "remove")) {
        const path = guestCString(state, state.regs.rdi) orelse "";
        if (path.len != 0) {
            if (state.allocator.dupeZ(u8, path)) |path_z| {
                defer state.allocator.free(path_z);
                _ = std.c.unlink(path_z.ptr);
            } else |_| {}
        }
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        std.log.scoped(.x64_linux_runtime).info("shimmed remove({s})", .{path});
        return true;
    }
    if (symbolNameEql(name, "exit") or symbolNameEql(name, "_exit")) {
        state.exit_code = state.regs.rdi;
        state.terminated = true;
        std.log.scoped(.x64_linux_runtime).info("shimmed {s}({d})", .{ name, state.exit_code });
        return true;
    }
    if (symbolNameEql(name, "abort")) {
        state.exit_code = 134;
        state.faulted = true;
        state.terminated = true;
        std.log.scoped(.x64_linux_runtime).warn("shimmed abort()", .{});
        return true;
    }
    if (symbolNameEql(name, "__cxa_atexit")) {
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "writev") or symbolNameEql(name, "pwritev64")) {
        handleWritevShim(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    return false;
}

fn dynamicRelocationName(state: anytype, got_addr: u64) ?[]const u8 {
    for (state.dynamic_relocations) |reloc| {
        if (reloc.offset == got_addr) return reloc.name;
    }
    return null;
}

fn guestCString(state: anytype, addr: u64) ?[]const u8 {
    const off = state.addrToOffset(addr) orelse return null;
    const off_usize: usize = @intCast(off);
    const rest = state.mem[off_usize..];
    const len = std.mem.indexOfScalar(u8, rest, 0) orelse return null;
    return rest[0..len];
}

fn finishExternalReturn(state: anytype, direct_return_rip: ?u64) void {
    if (direct_return_rip) |rip| {
        state.regs.rip = rip;
    } else {
        state.regs.rip = state.pop();
    }
}

fn handleWritevShim(state: anytype) void {
    const fd = state.regs.rdi;
    const iov = state.regs.rsi;
    const iovcnt = state.regs.rdx;
    var total: u64 = 0;
    var index: u64 = 0;
    while (index < iovcnt) : (index += 1) {
        const entry = iov + index * 16;
        const base = state.read64(entry);
        const len = state.read64(entry + 8);
        const off = state.addrToOffset(base) orelse {
            state.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        };
        if (len > std.math.maxInt(usize)) {
            state.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        }
        const off_usize: usize = @intCast(off);
        const len_usize: usize = @intCast(len);
        if (off_usize > state.mem.len or len_usize > state.mem.len - off_usize) {
            state.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        }
        const data = state.mem[off_usize .. off_usize + len_usize];
        if (fd == 1) {
            x64_syscalls.writeHostAll(std.posix.STDOUT_FILENO, data) catch {
                state.regs.rax = x64_syscalls.errnoValue(.io);
                return;
            };
        } else if (fd == 2) {
            x64_syscalls.writeHostAll(std.posix.STDERR_FILENO, data) catch {
                state.regs.rax = x64_syscalls.errnoValue(.io);
                return;
            };
        } else {
            state.regs.rax = x64_syscalls.errnoValue(.bad_file_descriptor);
            return;
        }
        total +%= len;
    }
    state.regs.rax = total;
}

fn symbolNameEql(name: []const u8, expected: []const u8) bool {
    if (std.mem.eql(u8, name, expected)) return true;
    if (std.mem.startsWith(u8, name, expected) and name.len > expected.len and name[expected.len] == '@') return true;
    return false;
}
