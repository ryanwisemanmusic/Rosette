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
    const name = dynamicRelocationName(state, got_addr) orelse {
        if (direct_return_rip != null) return false;
        const resolver_name = dynamicPltResolverRelocationName(state) orelse return false;
        const old_rsp = state.regs.rsp;
        state.regs.rsp +%= 16;
        if (tryNamedFunctionShim(state, resolver_name, null)) return true;
        state.regs.rsp = old_rsp;
        std.log.scoped(.x64_linux_runtime).warn("unsupported lazy PLT symbol {s}", .{resolver_name});
        return false;
    };
    if (tryNamedFunctionShim(state, name, direct_return_rip)) return true;
    std.log.scoped(.x64_linux_runtime).warn("unsupported PLT symbol {s}", .{name});
    return false;
}

fn tryNamedFunctionShim(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
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
    if (symbolNameEql(name, "aligned_alloc")) {
        const alignment = state.regs.rdi;
        const size = state.regs.rsi;
        state.regs.rax = state.guestAlloc(size, alignment) orelse 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "malloc") or
        symbolNameEql(name, "_Znwm") or
        symbolNameEql(name, "_Znam"))
    {
        state.regs.rax = state.guestAlloc(state.regs.rdi, 16) orelse 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "calloc")) {
        const count = state.regs.rdi;
        const elem_size = state.regs.rsi;
        const total = std.math.mul(u64, count, elem_size) catch {
            state.regs.rax = 0;
            finishExternalReturn(state, direct_return_rip);
            return true;
        };
        state.regs.rax = state.guestAlloc(total, 16) orelse 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "free") or
        symbolNameEql(name, "_ZdlPv") or
        symbolNameEql(name, "_ZdaPv") or
        symbolNameEql(name, "_ZdlPvm") or
        symbolNameEql(name, "_ZdaPvm"))
    {
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "dlsym") or
        symbolNameEql(name, "dlopen") or
        symbolNameEql(name, "dlerror") or
        symbolNameEql(name, "dl_iterate_phdr"))
    {
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "dlclose")) {
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "pthread_mutex_lock") or
        symbolNameEql(name, "pthread_mutex_unlock") or
        symbolNameEql(name, "pthread_mutex_trylock") or
        symbolNameEql(name, "pthread_cond_broadcast") or
        symbolNameEql(name, "pthread_cond_signal") or
        symbolNameEql(name, "pthread_rwlock_rdlock") or
        symbolNameEql(name, "pthread_rwlock_wrlock") or
        symbolNameEql(name, "pthread_rwlock_unlock"))
    {
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "isatty")) {
        const fd = state.regs.rdi;
        state.regs.rax = if (fd <= 2) 1 else 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "write")) {
        handleWriteShim(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "fwrite") or symbolNameEql(name, "fwrite_unlocked")) {
        const size = state.regs.rsi;
        const count = state.regs.rdx;
        state.regs.rax = if (size == 0) 0 else count;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "fputc") or
        symbolNameEql(name, "putc") or
        symbolNameEql(name, "putchar"))
    {
        state.regs.rax = state.regs.rdi & 0xFF;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "fputs") or symbolNameEql(name, "puts")) {
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "fflush")) {
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "printf") or
        symbolNameEql(name, "fprintf") or
        symbolNameEql(name, "vfprintf") or
        symbolNameEql(name, "snprintf") or
        symbolNameEql(name, "vsnprintf"))
    {
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

fn dynamicPltResolverRelocationName(state: anytype) ?[]const u8 {
    const relocation_index = state.read64(state.regs.rsp + 8);
    var jump_slot_index: u64 = 0;
    for (state.dynamic_relocations) |reloc| {
        if (reloc.rel_type != 7) continue; // R_X86_64_JUMP_SLOT
        if (jump_slot_index == relocation_index) return reloc.name;
        jump_slot_index += 1;
    }
    return null;
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

fn handleWriteShim(state: anytype) void {
    const fd = state.regs.rdi;
    const buf = state.regs.rsi;
    const len = state.regs.rdx;
    const off = state.addrToOffset(buf) orelse {
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
    state.regs.rax = len;
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
