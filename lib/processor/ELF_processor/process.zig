const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.elf);
const elf_loader = @import("elf_loader.zig");
const result_dump = @import("result_dump.zig");
const x64_guest_abi = @import("x64_guest_abi");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const x64_linux_runtime = @import("x64_linux_runtime");
const x64_syscalls = @import("x64_syscalls");

const SYS_close = x64_syscalls.SYS_close;
const SYS_creat = x64_syscalls.SYS_creat;
const SYS_exit = x64_syscalls.SYS_exit;
const SYS_gettid = x64_syscalls.SYS_gettid;
const SYS_open = x64_syscalls.SYS_open;
const SYS_read = x64_syscalls.SYS_read;
const SYS_write = x64_syscalls.SYS_write;

// ─── RFLAGS bit positions ───
const RFL_CF = x64_decoder.RFL_CF;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;

const STACK_SIZE: u64 = 1024 * 1024; // 1 MB stack
const MEM_SIZE: u64 = 64 * 1024 * 1024; // 64 MB total address space
const MEM_BASE: u64 = 0x1000000;
const SYNTHETIC_INIT_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF00;
const SYNTHETIC_MAIN_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF08;

// ─── Shared x64 execution types ───

pub const ElfRegs = x64_decoder.Regs;
pub const Size = x64_decoder.OperandSize;
pub const RegId = x64_decoder.RegId;
pub const Cond = x64_decoder.Condition;
pub const Op = x64_decoder.Op;
pub const DecodedInsn = x64_decoder.DecodedInsn;

// ─── ELF state ───

pub const ElfState = struct {
    allocator: std.mem.Allocator,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    regs: ElfRegs = .{},
    xmm: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16,
    terminated: bool = false,
    exit_code: u64 = 0,
    faulted: bool = false,
    libc_start_main_trampolined: bool = false,
    dynamic_relocations: []const elf_loader.DynamicRelocation = &.{},
    local_symbols: []const elf_loader.Symbol = &.{},
    init_functions: []const u64 = &.{},
    init_index: usize = 0,
    pending_main_addr: u64 = 0,
    pending_argc: u64 = 0,
    pending_argv: u64 = 0,
    heap_next: u64 = MEM_BASE + (MEM_SIZE / 2),
    trace_syscalls: bool = false,
    trace_syscall_bytes: bool = false,
    trace_fd_filter: ?u64 = null,
    trace_calls: bool = false,
    diagnose_abi: bool = false,
    call_stack: x64_guest_abi.CallStack = .{},
    interactive_output_path: ?[]u8 = null,
    interactive_summary_printed: bool = false,

    pub fn init(allocator: std.mem.Allocator) ElfState {
        const mem = allocator.alloc(u8, MEM_SIZE) catch unreachable;
        @memset(mem, 0);
        return .{
            .allocator = allocator,
            .mem = mem,
            .mem_base = MEM_BASE,
            .mem_size = MEM_SIZE,
            .trace_syscalls = envFlag("ROSETTE_ELF_TRACE_SYSCALLS"),
            .trace_syscall_bytes = envFlag("ROSETTE_ELF_TRACE_SYSCALL_BYTES"),
            .trace_fd_filter = envU64("ROSETTE_ELF_TRACE_FD"),
            .trace_calls = envFlag("ROSETTE_ELF_TRACE_CALLS"),
            .diagnose_abi = envFlag("ROSETTE_ELF_DIAGNOSE_ABI") or envFlag("ROSETTE_ELF_INTERACTIVE_BRIDGE") or envFlag("ROSETTE_ELF_EDU_BRIDGE"),
        };
    }

    pub fn deinit(self: *ElfState) void {
        if (self.interactive_output_path) |path| self.allocator.free(path);
        self.call_stack.deinit(self.allocator);
        self.allocator.free(self.mem);
    }

    pub fn addrToOffset(self: *const ElfState, vaddr: u64) ?u64 {
        if (vaddr < self.mem_base) return null;
        const off = vaddr - self.mem_base;
        if (off >= self.mem_size) return null;
        return off;
    }

    pub fn read8(self: *const ElfState, vaddr: u64) u8 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        return self.mem[off];
    }

    pub fn read16(self: *const ElfState, vaddr: u64) u16 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 2 > self.mem.len) return 0;
        return std.mem.readInt(u16, self.mem[off..][0..2], .little);
    }

    pub fn read32(self: *const ElfState, vaddr: u64) u32 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 4 > self.mem.len) return 0;
        return std.mem.readInt(u32, self.mem[off..][0..4], .little);
    }

    pub fn read64(self: *const ElfState, vaddr: u64) u64 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 8 > self.mem.len) return 0;
        return std.mem.readInt(u64, self.mem[off..][0..8], .little);
    }

    fn write8(self: *ElfState, vaddr: u64, val: u8) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off < self.mem.len) self.mem[off] = val;
    }

    fn write16(self: *ElfState, vaddr: u64, val: u16) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 2 <= self.mem.len) std.mem.writeInt(u16, self.mem[off..][0..2], val, .little);
    }

    fn write32(self: *ElfState, vaddr: u64, val: u32) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 4 <= self.mem.len) std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
    }

    pub fn write64(self: *ElfState, vaddr: u64, val: u64) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 8 <= self.mem.len) std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
    }

    pub fn push(self: *ElfState, val: u64) void {
        self.regs.rsp -|= 8;
        self.write64(self.regs.rsp, val);
    }

    pub fn pop(self: *ElfState) u64 {
        const val = self.read64(self.regs.rsp);
        self.regs.rsp +|= 8;
        return val;
    }

    pub fn loadElf(self: *ElfState, elf_bytes: []const u8) !void {
        const plan = try elf_loader.planExecutableLoad(self.mem.len, elf_bytes, STACK_SIZE);
        self.mem_base = plan.mem_base;
        self.heap_next = plan.heap_start;
        self.regs.rip = try elf_loader.loadExecutableSegments(self.mem_base, self.mem, elf_bytes);
        log.info("load plan: guest_base=0x{x} image=[0x{x}, 0x{x}) heap=0x{x} entry=0x{x}", .{
            plan.mem_base,
            plan.image_low,
            plan.image_high,
            plan.heap_start,
            plan.entry,
        });
    }

    pub fn startLibcMain(self: *ElfState, main_addr: u64, argc: u64, argv: u64) void {
        self.pending_main_addr = main_addr;
        self.pending_argc = argc;
        self.pending_argv = argv;
        self.init_index = 0;
        self.libc_start_main_trampolined = true;
        self.scheduleNextInitOrMain();
    }

    fn scheduleNextInitOrMain(self: *ElfState) void {
        while (self.init_index < self.init_functions.len) {
            const target = self.init_functions[self.init_index];
            self.init_index += 1;
            if (target == 0 or self.addrToOffset(target) == null) continue;
            self.regs.rdi = self.pending_argc;
            self.regs.rsi = self.pending_argv;
            self.regs.rdx = 0;
            self.push(SYNTHETIC_INIT_RETURN);
            self.regs.rip = target;
            log.info("running ELF init function {d}/{d} at 0x{x}", .{
                self.init_index,
                self.init_functions.len,
                target,
            });
            return;
        }
        self.startMainAfterInit();
    }

    fn startMainAfterInit(self: *ElfState) void {
        self.regs.rdi = self.pending_argc;
        self.regs.rsi = self.pending_argv;
        self.regs.rdx = 0;
        self.push(SYNTHETIC_MAIN_RETURN);
        self.regs.rip = self.pending_main_addr;
    }

    fn handleSyntheticRip(self: *ElfState) bool {
        if (self.regs.rip == SYNTHETIC_INIT_RETURN) {
            self.scheduleNextInitOrMain();
            return true;
        }
        if (self.regs.rip == SYNTHETIC_MAIN_RETURN) {
            self.exit_code = self.regs.rax;
            self.terminated = true;
            return true;
        }
        return false;
    }

    pub fn localSymbolAddress(self: *const ElfState, name: []const u8) ?u64 {
        for (self.local_symbols) |symbol| {
            if (std.mem.eql(u8, symbol.name, name)) return symbol.value;
        }
        return null;
    }

    pub fn localSymbolNameAt(self: *const ElfState, address: u64) ?[]const u8 {
        for (self.local_symbols) |symbol| {
            if (symbol.value == address) return symbol.name;
        }
        return null;
    }

    pub fn guestAlloc(self: *ElfState, requested_size: u64, requested_alignment: u64) ?u64 {
        const size = if (requested_size == 0) 1 else requested_size;
        if (size > std.math.maxInt(usize)) return null;

        var alignment = if (requested_alignment <= 1) @as(u64, 1) else requested_alignment;
        if ((alignment & (alignment - 1)) != 0) {
            var rounded: u64 = 1;
            while (rounded < alignment) {
                if (rounded > (std.math.maxInt(u64) >> 1)) return null;
                rounded <<= 1;
            }
            alignment = rounded;
        }

        const mask = alignment - 1;
        if (self.heap_next > std.math.maxInt(u64) - mask) return null;
        const aligned = (self.heap_next + mask) & ~mask;
        const heap_limit = self.mem_base + self.mem_size - STACK_SIZE;
        if (aligned >= heap_limit or size > heap_limit - aligned) return null;
        const off = self.addrToOffset(aligned) orelse return null;
        const size_usize: usize = @intCast(size);
        if (off > self.mem.len or size_usize > self.mem.len - off) return null;

        @memset(self.mem[off..][0..size_usize], 0);
        self.heap_next = aligned + size;
        return aligned;
    }

    fn sibAddr(self: *const ElfState, d: *DecodedInsn) void {
        if (!d.sib_has_index) return;
        const scale: u3 = @as(u3, d.sib_scale);
        const index_val = self.regVal(d.sib_index_reg, .bits64);
        d.addr +%= index_val << @as(u6, scale);
    }

    fn decodeAt(self: *ElfState) ?DecodedInsn {
        const off = self.addrToOffset(self.regs.rip) orelse return null;
        const remaining = self.mem.len - off;
        if (remaining == 0) return null;
        const bytes = self.mem[off..];
        var d = decodeInsn(bytes);
        // Detect address-size override (0x67) prefix in the raw instruction
        for (bytes[0..@min(@as(usize, @intCast(d.len)), bytes.len)]) |b| {
            if (b == 0x67) {
                d.has_0x67 = true;
                break;
            }
            if (b != 0x66 and b != 0x2E and b != 0x64 and b != 0xF0 and !hasRexPrefix(b)) break;
        }
        const addr_size: Size = if (d.has_0x67) .bits32 else .bits64;
        if (d.sib_has_index) {
            const scale: u3 = @as(u3, d.sib_scale);
            const index_val = self.regVal(d.sib_index_reg, addr_size);
            d.addr +%= index_val << @as(u6, scale);
        }
        if (d.sib_has_base) {
            const base_val = self.regVal(d.sib_base_reg, addr_size);
            d.addr +%= base_val;
        }
        if (d.rip_relative) {
            d.addr +%= self.regs.rip + d.len;
        }
        return d;
    }

    fn step(self: *ElfState) bool {
        if (self.handleSyntheticRip()) return !self.terminated;
        const decoded = self.decodeAt() orelse {
            self.terminated = true;
            return false;
        };
        if (decoded.op == .invalid) {
            log.err("invalid instruction at rip=0x{x}", .{self.regs.rip});
            self.faulted = true;
            self.exit_code = 127;
            self.terminated = true;
            return false;
        }
        const trace_this = shouldTraceRip(self.regs.rip);
        if (trace_this) {
            log.info("trace before rip=0x{x} op={s} len={d} rax=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rsp=0x{x} rbp=0x{x} flags=0x{x}", .{
                self.regs.rip,
                @tagName(decoded.op),
                decoded.len,
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.rsi,
                self.regs.rdi,
                self.regs.rsp,
                self.regs.rbp,
                self.regs.rflags,
            });
        }
        x64_interpreter.execute(self, decoded);
        if (trace_this) {
            log.info("trace after  rip=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rsp=0x{x} rbp=0x{x} flags=0x{x}", .{
                self.regs.rip,
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.rsi,
                self.regs.rdi,
                self.regs.rsp,
                self.regs.rbp,
                self.regs.rflags,
            });
        }
        return !self.terminated;
    }

    pub fn run(self: *ElfState) void {
        var steps: u64 = 0;
        const max_steps: u64 = 2_000_000;
        while (!self.terminated and steps < max_steps) : (steps += 1) {
            if (steps % 100000 == 0) {
                log.info("step {d}: rip=0x{x}, rax=0x{x}, rbx=0x{x}, rcx=0x{x}, rsi=0x{x}, rdi=0x{x}", .{ steps, self.regs.rip, self.regs.rax, self.regs.rbx, self.regs.rcx, self.regs.rsi, self.regs.rdi });
            }
            if (!self.step()) break;
        }
        if (steps >= max_steps) {
            log.warn("reached max steps ({d})", .{max_steps});
            self.logRegs();
            self.faulted = true;
            self.exit_code = 124;
            self.terminated = true;
        }
    }

    fn logRegs(self: *ElfState) void {
        log.info("  regs: rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rsp=0x{x} rbp=0x{x} rip=0x{x}", .{
            self.regs.rax, self.regs.rbx, self.regs.rcx, self.regs.rdx,
            self.regs.rsi, self.regs.rdi, self.regs.rsp, self.regs.rbp,
            self.regs.rip,
        });
        log.info("  flags: cf={d} zf={d} sf={d} of={d}", .{
            @as(u1, @truncate(self.regs.rflags >> 0)),
            @as(u1, @truncate(self.regs.rflags >> 6)),
            @as(u1, @truncate(self.regs.rflags >> 7)),
            @as(u1, @truncate(self.regs.rflags >> 11)),
        });
    }

    fn regVal(self: *const ElfState, id: RegId, size: Size) u64 {
        return x64_decoder.regVal(&self.regs, id, size);
    }

    fn setReg(self: *ElfState, id: RegId, size: Size, val: u64) void {
        x64_decoder.setReg(&self.regs, id, size, val);
    }

    fn readMemVal(self: *ElfState, addr: u64, size: Size) u64 {
        return switch (size) {
            .bits8 => self.read8(addr),
            .bits16 => self.read16(addr),
            .bits32 => self.read32(addr),
            .bits64 => self.read64(addr),
        };
    }

    fn writeMemVal(self: *ElfState, addr: u64, size: Size, val: u64) void {
        switch (size) {
            .bits8 => self.write8(addr, @intCast(val & 0xFF)),
            .bits16 => self.write16(addr, @intCast(val & 0xFFFF)),
            .bits32 => self.write32(addr, @intCast(val & 0xFFFFFFFF)),
            .bits64 => self.write64(addr, val),
        }
    }

    fn readMem128(self: *const ElfState, addr: u64) [16]u8 {
        var value = [_]u8{0} ** 16;
        const off = self.addrToOffset(addr) orelse return value;
        if (off + 16 > self.mem.len) return value;
        @memcpy(value[0..], self.mem[off..][0..16]);
        return value;
    }

    fn writeMem128(self: *ElfState, addr: u64, value: [16]u8) void {
        const off = self.addrToOffset(addr) orelse return;
        if (off + 16 > self.mem.len) return;
        @memcpy(self.mem[off..][0..16], value[0..]);
    }

    pub fn guestMemory(self: *ElfState, addr: u64, count: u64) ?[]u8 {
        if (count > std.math.maxInt(usize)) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
    }

    pub fn guestMemoryConst(self: *const ElfState, addr: u64, count: u64) ?[]const u8 {
        if (count > std.math.maxInt(usize)) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
    }

    pub fn writeHostFd(self: *ElfState, fd: u64, data: []const u8) u64 {
        _ = self;
        const host_fd = hostFdFromGuest(fd) orelse return x64_syscalls.errnoValue(.bad_file_descriptor);
        var written: usize = 0;
        while (written < data.len) {
            const n = std.c.write(host_fd, data[written..].ptr, data.len - written);
            if (n <= 0) return x64_syscalls.errnoValue(.io);
            written += @intCast(n);
        }
        return @intCast(data.len);
    }

    pub fn traceGuestIo(self: *const ElfState, operation: []const u8, fd: u64, addr: u64, count: u64, result: u64) void {
        if (!self.shouldTraceFd(fd)) return;
        log.info("runtime io: {s}(fd={d}, buf=0x{x}, count={d}) -> {d}", .{
            operation,
            fd,
            addr,
            count,
            syscallResult(result),
        });
        if (!self.trace_syscall_bytes) return;
        if (syscallResult(result) <= 0) return;
        const available = @min(count, result);
        const data = self.guestMemoryConst(addr, available) orelse return;
        self.traceDataPreview(operation, fd, data);
    }

    fn traceSyscall(self: *const ElfState, comptime fmt: []const u8, args: anytype) void {
        if (!self.trace_syscalls) return;
        if (self.trace_fd_filter != null) return;
        log.info("syscall: " ++ fmt, args);
    }

    fn traceOpenResult(self: *const ElfState, path: []const u8, flags_raw: u64, mode_raw: u64, result: u64) void {
        if (!self.shouldTraceResultFd(result)) return;
        log.info("syscall: open(\"{s}\", flags=0x{x}, mode=0o{o}) -> {d}", .{
            path,
            flags_raw,
            mode_raw & 0o7777,
            syscallResult(result),
        });
    }

    fn traceCreatResult(self: *const ElfState, path: []const u8, mode_raw: u64, result: u64) void {
        if (!self.shouldTraceResultFd(result)) return;
        log.info("syscall: creat(\"{s}\", mode=0o{o}) -> {d}", .{
            path,
            mode_raw & 0o7777,
            syscallResult(result),
        });
    }

    fn shouldTraceFd(self: *const ElfState, fd: u64) bool {
        if (!self.trace_syscalls) return false;
        if (self.trace_fd_filter) |filter| return fd == filter;
        return true;
    }

    fn shouldTraceResultFd(self: *const ElfState, result: u64) bool {
        if (!self.trace_syscalls) return false;
        if (self.trace_fd_filter) |filter| {
            if (syscallResult(result) < 0) return false;
            return result == filter;
        }
        return true;
    }

    fn traceDataPreview(self: *const ElfState, operation: []const u8, fd: u64, data: []const u8) void {
        if (!self.trace_syscall_bytes) return;
        var preview: [96]u8 = undefined;
        const n = @min(preview.len, data.len);
        for (data[0..n], 0..) |byte, i| {
            preview[i] = switch (byte) {
                0x20...0x7e => byte,
                '\n' => '|',
                '\r', '\t' => ' ',
                else => '.',
            };
        }
        log.info("runtime io bytes: {s}(fd={d}) {d} byte preview \"{s}\"", .{
            operation,
            fd,
            data.len,
            preview[0..n],
        });
    }

    fn abiTraceConfig(self: *const ElfState) x64_guest_abi.TraceConfig {
        return .{
            .trace_calls = self.trace_calls,
            .diagnose = self.diagnose_abi,
        };
    }

    fn noteGuestCall(self: *ElfState, kind: x64_guest_abi.CallKind, target: u64, return_rip: u64) void {
        if (!self.trace_calls) return;
        self.call_stack.enter(self.allocator, self.abiTraceConfig(), .{
            .target = target,
            .return_rip = return_rip,
            .rsp_before_call = self.regs.rsp,
            .symbol = self.localSymbolNameAt(target),
            .kind = kind,
        });
    }

    fn noteGuestReturn(self: *ElfState, return_rip: u64) void {
        if (!self.trace_calls) return;
        self.call_stack.leave(self.abiTraceConfig(), return_rip, self.regs.rsp, self.regs.rax);
    }

    fn setFlagsSub(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applySub(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsAdd(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applyAdd(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsIncDec(self: *ElfState, input: u64, result: u64, size: Size, is_inc: bool) void {
        x64_decoder.applyIncDec(&self.regs.rflags, input, result, size, is_inc);
    }

    fn setFlagsLogic(self: *ElfState, result: u64, size: Size) void {
        x64_decoder.applyLogic(&self.regs.rflags, result, size);
    }

    fn setFlag(self: *ElfState, flag: u32, enabled: bool) void {
        if (enabled) {
            self.regs.rflags |= flag;
        } else {
            self.regs.rflags &= ~flag;
        }
    }

    fn bitWidth(size: Size) u7 {
        return switch (size) {
            .bits8 => 8,
            .bits16 => 16,
            .bits32 => 32,
            .bits64 => 64,
        };
    }

    fn maskForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0xFF,
            .bits16 => 0xFFFF,
            .bits32 => 0xFFFF_FFFF,
            .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
        };
    }

    fn signBitForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0x80,
            .bits16 => 0x8000,
            .bits32 => 0x8000_0000,
            .bits64 => 0x8000_0000_0000_0000,
        };
    }

    fn shlCount(self: *ElfState, size: Size) u6 {
        const mask: u64 = if (size == .bits64) 0x3F else 0x1F;
        return @as(u6, @intCast(self.regVal(.cl_cx_ecx_rcx, .bits8) & mask));
    }

    fn shlValue(self: *ElfState, input: u64, size: Size, count: u6) u64 {
        _ = self;
        const mask = maskForSize(size);
        const result = (input & mask) << count;
        return result & mask;
    }

    fn setFlagsShl(self: *ElfState, input: u64, result: u64, size: Size, count: u6) void {
        if (count == 0) return;

        const width = bitWidth(size);
        const mask = maskForSize(size);
        const masked_input = input & mask;
        const masked_result = result & mask;

        if (count <= width) {
            const shift: u6 = @intCast(width - count);
            self.setFlag(RFL_CF, ((masked_input >> shift) & 1) != 0);
        } else {
            self.setFlag(RFL_CF, false);
        }

        if (count == 1) {
            const sign = signBitForSize(size);
            const msb_set = (masked_result & sign) != 0;
            const cf_set = (self.regs.rflags & RFL_CF) != 0;
            self.setFlag(RFL_OF, msb_set != cf_set);
        }

        self.setFlag(RFL_SF, (masked_result & signBitForSize(size)) != 0);
        self.setFlag(RFL_ZF, masked_result == 0);
    }

    fn immShiftCount(imm: u64, size: Size) u6 {
        const mask: u64 = if (size == .bits64) 0x3F else 0x1F;
        return @as(u6, @intCast(imm & mask));
    }

    fn shrValue(self: *ElfState, input: u64, size: Size, count: u6) u64 {
        _ = self;
        const mask = maskForSize(size);
        return (input & mask) >> count;
    }

    fn setFlagsShr(self: *ElfState, input: u64, result: u64, size: Size, count: u6) void {
        if (count == 0) return;

        const masked_input = input & maskForSize(size);
        const masked_result = result & maskForSize(size);
        const shifted_out: u6 = @intCast(count - 1);
        self.setFlag(RFL_CF, ((masked_input >> shifted_out) & 1) != 0);

        if (count == 1) {
            self.setFlag(RFL_OF, (masked_input & signBitForSize(size)) != 0);
        }

        self.setFlag(RFL_SF, (masked_result & signBitForSize(size)) != 0);
        self.setFlag(RFL_ZF, masked_result == 0);
    }

    fn sarValue(self: *ElfState, input: u64, size: Size, count: u6) u64 {
        _ = self;
        if (count == 0) return input & maskForSize(size);
        const sign_set = (input & signBitForSize(size)) != 0;
        if (count >= bitWidth(size)) return if (sign_set) maskForSize(size) else 0;
        return switch (size) {
            .bits8 => @as(u64, @as(u8, @bitCast(@as(i8, @bitCast(@as(u8, @truncate(input)))) >> @as(u3, @intCast(count))))),
            .bits16 => @as(u64, @as(u16, @bitCast(@as(i16, @bitCast(@as(u16, @truncate(input)))) >> @as(u4, @intCast(count))))),
            .bits32 => @as(u64, @as(u32, @bitCast(@as(i32, @bitCast(@as(u32, @truncate(input)))) >> @as(u5, @intCast(count))))),
            .bits64 => @as(u64, @bitCast(@as(i64, @bitCast(input)) >> count)),
        };
    }

    fn setFlagsSar(self: *ElfState, input: u64, result: u64, size: Size, count: u6) void {
        if (count == 0) return;

        const masked_input = input & maskForSize(size);
        const masked_result = result & maskForSize(size);
        if (count <= bitWidth(size)) {
            const shifted_out: u6 = @intCast(count - 1);
            self.setFlag(RFL_CF, ((masked_input >> shifted_out) & 1) != 0);
        }

        if (count == 1) self.setFlag(RFL_OF, false);

        self.setFlag(RFL_SF, (masked_result & signBitForSize(size)) != 0);
        self.setFlag(RFL_ZF, masked_result == 0);
    }

    fn evalCond(rflags: u32, cond: Cond) bool {
        return x64_decoder.evalCond(rflags, cond);
    }

    pub fn execute(self: *ElfState, d: DecodedInsn) void {
        switch (d.op) {
            .invalid => unreachable,
            .nop => {},

            // ── mov reg, mem ──
            .mov_reg8_mem8 => {
                const val = self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, .bits8, val);
            },
            .mov_reg16_mem16 => {
                const val = self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, .bits16, val);
            },
            .mov_reg32_mem32 => {
                const val = self.readMemVal(d.addr, .bits32);
                self.setReg(d.dst_reg, .bits32, val);
            },
            .mov_reg64_mem64 => {
                const val = self.readMemVal(d.addr, .bits64);
                self.setReg(d.dst_reg, .bits64, val);
            },

            // ── mov mem, reg ──
            .mov_mem8_reg8 => {
                const val = self.regVal(d.src_reg, .bits8);
                self.writeMemVal(d.addr, .bits8, val);
            },
            .mov_mem16_reg16 => {
                const val = self.regVal(d.src_reg, .bits16);
                self.writeMemVal(d.addr, .bits16, val);
            },
            .mov_mem32_reg32 => {
                const val = self.regVal(d.src_reg, .bits32);
                self.writeMemVal(d.addr, .bits32, val);
            },
            .mov_mem64_reg64 => {
                const val = self.regVal(d.src_reg, .bits64);
                self.writeMemVal(d.addr, .bits64, val);
            },

            // ── mov reg, imm ──
            .mov_reg_imm => {
                self.setReg(d.dst_reg, d.size, d.imm);
            },

            // ── mov mem, imm ──
            .mov_mem8_imm8 => {
                self.writeMemVal(d.addr, .bits8, d.imm);
            },
            .mov_mem16_imm16 => {
                self.writeMemVal(d.addr, .bits16, d.imm);
            },
            .mov_mem32_imm32 => {
                self.writeMemVal(d.addr, .bits32, d.imm);
            },
            .mov_mem64_imm32 => {
                self.writeMemVal(d.addr, .bits64, d.imm);
            },

            // ── mov reg64, reg64 ──
            .mov_reg8_reg8 => {
                const val = self.regVal(d.src_reg, .bits8);
                self.setReg(d.dst_reg, .bits8, val);
            },
            .mov_reg16_reg16 => {
                const val = self.regVal(d.src_reg, .bits16);
                self.setReg(d.dst_reg, .bits16, val);
            },
            .mov_reg32_reg32 => {
                const val = self.regVal(d.src_reg, .bits32);
                self.setReg(d.dst_reg, .bits32, val);
            },
            .mov_reg64_reg64 => {
                const val = self.regVal(d.src_reg, .bits64);
                self.setReg(d.dst_reg, .bits64, val);
            },

            // ── add reg, mem (d=1) ──
            .add_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b, r, .bits8);
            },
            .add_reg16_mem16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.readMemVal(d.addr, .bits16);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsAdd(a, b, r, .bits16);
            },
            .add_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsAdd(a, b, r, .bits32);
            },
            .add_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsAdd(a, b, r, .bits64);
            },

            // ── add r/m, reg (d=0) ──
            .add_mem8_reg8 => {
                const a = self.readMemVal(d.addr, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                const r = a +% b;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsAdd(a, b, r, .bits8);
            },
            .add_mem16_reg16 => {
                const a = self.readMemVal(d.addr, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                const r = a +% b;
                self.writeMemVal(d.addr, .bits16, r);
                self.setFlagsAdd(a, b, r, .bits16);
            },
            .add_mem32_reg32 => {
                const a = self.readMemVal(d.addr, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                const r = a +% b;
                self.writeMemVal(d.addr, .bits32, r);
                self.setFlagsAdd(a, b, r, .bits32);
            },
            .add_mem64_reg64 => {
                const a = self.readMemVal(d.addr, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                const r = a +% b;
                self.writeMemVal(d.addr, .bits64, r);
                self.setFlagsAdd(a, b, r, .bits64);
            },

            // ── add reg, reg ──
            .add_reg8_reg8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b, r, .bits8);
            },
            .add_reg16_reg16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsAdd(a, b, r, .bits16);
            },
            .add_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsAdd(a, b, r, .bits32);
            },
            .add_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsAdd(a, b, r, .bits64);
            },
            .add_reg8_imm8, .add_reg16_imm8, .add_reg32_imm8, .add_reg64_imm8 => {
                const a = self.regVal(d.dst_reg, d.size);
                const imm = if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm);
                const r = a +% imm;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsAdd(a, imm, r, d.size);
            },
            .adc_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a +% b +% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .adc_reg16_imm8, .adc_reg32_imm8, .adc_reg64_imm8 => {
                const a = self.regVal(d.dst_reg, d.size);
                const imm = if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm);
                const carry: u64 = if ((self.regs.rflags & RFL_CF) != 0) 1 else 0;
                const operand = imm +% carry;
                const r = a +% operand;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsAdd(a, operand, r, d.size);
            },
            .adc_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a +% b +% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .sbb_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a -% b -% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32 => {
                const a = self.regVal(d.dst_reg, d.size);
                const imm = testImmForSize(d.imm, d.size);
                const r = a +% imm;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsAdd(a, imm, r, d.size);
            },
            .add_mem8_imm8 => {
                const a = self.readMemVal(d.addr, .bits8);
                const imm = d.imm & 0xFF;
                const r = a +% imm;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsAdd(a, imm, r, .bits8);
            },
            .add_mem16_imm8, .add_mem32_imm8, .add_mem64_imm8 => {
                const a = self.readMemVal(d.addr, d.size);
                const imm = signExtendImm8(d.imm);
                const r = a +% imm;
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsAdd(a, imm, r, d.size);
            },

            // ── sub reg, mem ──
            .sub_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b, r, .bits8);
            },
            .sub_reg16_mem16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.readMemVal(d.addr, .bits16);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsSub(a, b, r, .bits16);
            },
            .sub_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsSub(a, b, r, .bits32);
            },
            .sub_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsSub(a, b, r, .bits64);
            },

            // ── sub reg, reg ──
            .sub_reg8_reg8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b, r, .bits8);
            },
            .sub_reg16_reg16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsSub(a, b, r, .bits16);
            },
            .sub_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsSub(a, b, r, .bits32);
            },
            .sub_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsSub(a, b, r, .bits64);
            },
            .sbb_reg8_reg8, .sbb_reg16_reg16, .sbb_reg32_reg32, .sbb_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, d.size);
                const b = self.regVal(d.src_reg, d.size);
                const carry: u64 = if ((self.regs.rflags & RFL_CF) != 0) 1 else 0;
                const subtrahend = (b +% carry) & maskForSize(d.size);
                const r = a -% subtrahend;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsSub(a, subtrahend, r, d.size);
            },

            // ── sub r/m8, imm8 (0x80 /5) ──
            .sub_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const r = a -% d.imm;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, d.imm, r, .bits8);
            },
            .sbb_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a -% b -% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .sub_reg16_imm8 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const imm = signExtendImm8(d.imm);
                const r = a -% imm;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsSub(a, imm, r, .bits16);
            },
            .sub_reg32_imm8 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const imm = signExtendImm8(d.imm);
                const r = a -% imm;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsSub(a, imm, r, .bits32);
            },
            .sub_reg64_imm8 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const imm = signExtendImm8(d.imm);
                const r = a -% imm;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsSub(a, imm, r, .bits64);
            },
            .sub_mem8_imm8 => {
                const a = self.readMemVal(d.addr, .bits8);
                const r = a -% d.imm;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsSub(a, d.imm, r, .bits8);
            },
            .sub_reg16_imm32, .sub_reg32_imm32, .sub_reg64_imm32 => {
                const a = self.regVal(d.dst_reg, d.size);
                const r = a -% d.imm;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsSub(a, d.imm, r, d.size);
            },

            // ── logical register/imm operations ──
            .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, d.size);
                const b = self.regVal(d.src_reg, d.size);
                const r = a & b;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .and_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const r = a & b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsLogic(r, .bits8);
            },
            .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64 => {
                const a = self.readMemVal(d.addr, d.size);
                const b = self.regVal(d.src_reg, d.size);
                const r = a & b;
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8 => {
                const a = self.regVal(d.dst_reg, d.size);
                const imm = if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm);
                const r = a & imm;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32 => {
                const a = self.regVal(d.dst_reg, d.size);
                const imm = testImmForSize(d.imm, d.size);
                const r = a & imm;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, d.size);
                const b = self.regVal(d.src_reg, d.size);
                const r = a | b;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, d.size);
                const b = self.readMemVal(d.addr, d.size);
                const r = a | b;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64 => {
                const a = self.readMemVal(d.addr, d.size);
                const b = self.regVal(d.src_reg, d.size);
                const r = a | b;
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .or_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const r = a | b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsLogic(r, .bits8);
            },
            .or_mem8_imm8, .or_mem16_imm8, .or_mem32_imm8, .or_mem64_imm8 => {
                const a = self.readMemVal(d.addr, d.size);
                const imm = if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm);
                const r = a | imm;
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .or_mem16_imm32, .or_mem32_imm32, .or_mem64_imm32 => {
                const a = self.readMemVal(d.addr, d.size);
                const imm = testImmForSize(d.imm, d.size);
                const r = a | imm;
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .xor_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, d.size);
                const b = self.readMemVal(d.addr, d.size);
                const r = a ^ b;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, d.size);
                const b = self.regVal(d.src_reg, d.size);
                const r = a ^ b;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .xor_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const r = a ^ (d.imm & 0xFF);
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsLogic(r, .bits8);
            },
            .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8 => {
                const a = self.regVal(d.dst_reg, d.size);
                const imm = signExtendImm8(d.imm);
                const r = a ^ imm;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsLogic(r, d.size);
            },
            .shl_reg_cl => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = self.shlCount(d.size);
                const r = self.shlValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsShl(old, r, d.size, count);
            },
            .shl_mem_cl => {
                const old = self.readMemVal(d.addr, d.size);
                const count = self.shlCount(d.size);
                const r = self.shlValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsShl(old, r, d.size, count);
            },
            .shl_reg_imm => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.shlValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsShl(old, r, d.size, count);
            },
            .shl_mem_imm => {
                const old = self.readMemVal(d.addr, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.shlValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsShl(old, r, d.size, count);
            },
            .shr_reg_imm => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.shrValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsShr(old, r, d.size, count);
            },
            .shr_mem_imm => {
                const old = self.readMemVal(d.addr, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.shrValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsShr(old, r, d.size, count);
            },
            .sar_reg_imm => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.sarValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsSar(old, r, d.size, count);
            },
            .sar_mem_imm => {
                const old = self.readMemVal(d.addr, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.sarValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsSar(old, r, d.size, count);
            },
            .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64 => {
                const r = self.regVal(d.dst_reg, d.size) & self.regVal(d.src_reg, d.size);
                self.setFlagsLogic(r, d.size);
            },
            .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64 => {
                const r = self.readMemVal(d.addr, d.size) & self.regVal(d.src_reg, d.size);
                self.setFlagsLogic(r, d.size);
            },
            .test_reg8_imm8 => {
                const r = self.regVal(d.dst_reg, .bits8) & (d.imm & 0xFF);
                self.setFlagsLogic(r, .bits8);
            },
            .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => {
                const imm = testImmForSize(d.imm, d.size);
                const r = self.regVal(d.dst_reg, d.size) & imm;
                self.setFlagsLogic(r, d.size);
            },
            .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => {
                const imm = testImmForSize(d.imm, d.size);
                const r = self.readMemVal(d.addr, d.size) & imm;
                self.setFlagsLogic(r, d.size);
            },
            .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
                const a = self.regVal(d.dst_reg, d.size);
                const r = 0 -% a;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsSub(0, a, r, d.size);
            },

            // ── cmp r/m, reg (opcode 0x39) ──
            .cmp_mem8_reg8 => {
                const a = self.readMemVal(d.addr, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                self.setFlagsSub(a, b, a -% b, .bits8);
            },
            .cmp_mem16_reg16 => {
                const a = self.readMemVal(d.addr, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                self.setFlagsSub(a, b, a -% b, .bits16);
            },
            .cmp_mem32_reg32 => {
                const a = self.readMemVal(d.addr, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                self.setFlagsSub(a, b, a -% b, .bits32);
            },
            .cmp_mem64_reg64 => {
                const a = self.readMemVal(d.addr, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                self.setFlagsSub(a, b, a -% b, .bits64);
            },

            // ── cmp reg, reg (opcode 0x39, mod=3) ──
            .cmp_reg8_reg8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                self.setFlagsSub(a, b, a -% b, .bits8);
            },
            .cmp_reg16_reg16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                self.setFlagsSub(a, b, a -% b, .bits16);
            },
            .cmp_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                self.setFlagsSub(a, b, a -% b, .bits32);
            },
            .cmp_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                self.setFlagsSub(a, b, a -% b, .bits64);
            },

            // ── cmp reg, r/m (0x3A/0x3B, d=1) ──
            .cmp_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                self.setFlagsSub(a, b, a -% b, .bits8);
            },
            .cmp_reg16_mem16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.readMemVal(d.addr, .bits16);
                self.setFlagsSub(a, b, a -% b, .bits16);
            },
            .cmp_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                self.setFlagsSub(a, b, a -% b, .bits32);
            },
            .cmp_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                self.setFlagsSub(a, b, a -% b, .bits64);
            },

            // ── cmp r/m, imm8 (0x83 /7) ──
            .cmp_mem8_imm8 => {
                const a = self.readMemVal(d.addr, .bits8);
                const imm = d.imm & 0xFF;
                self.setFlagsSub(a, imm, a -% imm, .bits8);
            },
            .cmp_mem16_imm8 => {
                const a = self.readMemVal(d.addr, .bits16);
                const imm_sext = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u16, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits16);
            },
            .cmp_mem32_imm8 => {
                const a = self.readMemVal(d.addr, .bits32);
                const imm_sext = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u32, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits32);
            },
            .cmp_mem64_imm8 => {
                const a = self.readMemVal(d.addr, .bits64);
                const imm_sext = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u64, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits64);
            },
            .cmp_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const imm = d.imm & 0xFF;
                self.setFlagsSub(a, imm, a -% imm, .bits8);
            },
            .cmp_reg16_imm8 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const imm_sext = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u16, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits16);
            },
            .cmp_reg32_imm8 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const imm_sext = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u32, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits32);
            },
            .cmp_reg64_imm8 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const imm_sext = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u64, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits64);
            },

            // ── inc/dec memory ──
            .inc_mem8 => {
                const old = self.readMemVal(d.addr, .bits8);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, true);
            },
            .inc_mem16 => {
                const old = self.readMemVal(d.addr, .bits16);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, true);
            },
            .inc_mem32 => {
                const old = self.readMemVal(d.addr, .bits32);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, true);
            },
            .inc_mem64 => {
                const old = self.readMemVal(d.addr, .bits64);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, true);
            },
            .dec_mem8 => {
                const old = self.readMemVal(d.addr, .bits8);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, false);
            },
            .dec_mem16 => {
                const old = self.readMemVal(d.addr, .bits16);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, false);
            },
            .dec_mem32 => {
                const old = self.readMemVal(d.addr, .bits32);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, false);
            },
            .dec_mem64 => {
                const old = self.readMemVal(d.addr, .bits64);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, false);
            },

            // ── inc/dec register (0xFF /0, /1 with mod=3) ──
            .inc_reg8 => {
                const old = self.regVal(d.dst_reg, .bits8);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, true);
            },
            .inc_reg16 => {
                const old = self.regVal(d.dst_reg, .bits16);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, true);
            },
            .inc_reg32 => {
                const old = self.regVal(d.dst_reg, .bits32);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, true);
            },
            .inc_reg64 => {
                const old = self.regVal(d.dst_reg, .bits64);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, true);
            },
            .dec_reg8 => {
                const old = self.regVal(d.dst_reg, .bits8);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, false);
            },
            .dec_reg16 => {
                const old = self.regVal(d.dst_reg, .bits16);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, false);
            },
            .dec_reg32 => {
                const old = self.regVal(d.dst_reg, .bits32);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, false);
            },
            .dec_reg64 => {
                const old = self.regVal(d.dst_reg, .bits64);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, false);
            },

            // ── mul [mem] (unsigned, accumulator form) ──
            .mul_mem8 => {
                const b = self.readMemVal(d.addr, .bits8);
                const a = self.regVal(.al_ax_eax_rax, .bits8);
                const result = @as(u16, @intCast(a)) * @as(u16, @intCast(b));
                self.setReg(.al_ax_eax_rax, .bits16, result);
            },
            .mul_mem16 => {
                const b: u16 = @intCast(self.readMemVal(d.addr, .bits16));
                const a: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const result: u32 = @as(u32, a) * @as(u32, b);
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(result & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast((result >> 16) & 0xFFFF));
            },
            .mul_mem32 => {
                const b = self.readMemVal(d.addr, .bits32);
                const a = self.regVal(.al_ax_eax_rax, .bits32);
                const result = @as(u64, a) * @as(u64, b);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(result & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast((result >> 32) & 0xFFFFFFFF));
            },
            .mul_mem64 => {
                const b = self.readMemVal(d.addr, .bits64);
                const a = self.regVal(.al_ax_eax_rax, .bits64);
                const result: u128 = @as(u128, a) * @as(u128, b);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(result & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast((result >> 64) & 0xFFFFFFFFFFFFFFFF));
            },

            // ── imul [mem] (signed, accumulator form) ──
            .imul_mem8 => {
                const a: i8 = @bitCast(@as(u8, @intCast(self.regVal(.al_ax_eax_rax, .bits8))));
                const b: i8 = @bitCast(@as(u8, @intCast(self.readMemVal(d.addr, .bits8))));
                const result: i16 = @as(i16, a) * @as(i16, b);
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(result)));
            },
            .imul_mem16 => {
                const a: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const b: i16 = @bitCast(@as(u16, @intCast(self.readMemVal(d.addr, .bits16))));
                const result: i32 = @as(i32, a) * @as(i32, b);
                const ru: u32 = @bitCast(result);
                const lo: u16 = @truncate(ru);
                const hi: u16 = @truncate(ru >> 16);
                self.setReg(.al_ax_eax_rax, .bits16, lo);
                self.setReg(.dl_dx_edx_rdx, .bits16, hi);
            },
            .imul_mem32 => {
                const a: i32 = @bitCast(@as(u32, @intCast(self.regVal(.al_ax_eax_rax, .bits32))));
                const b: i32 = @bitCast(@as(u32, @intCast(self.readMemVal(d.addr, .bits32))));
                const result: i64 = @as(i64, a) * @as(i64, b);
                const ru: u64 = @bitCast(result);
                const lo: u32 = @truncate(ru);
                const hi: u32 = @truncate(ru >> 32);
                self.setReg(.al_ax_eax_rax, .bits32, lo);
                self.setReg(.dl_dx_edx_rdx, .bits32, hi);
            },
            .imul_mem64 => {
                const a: i64 = @bitCast(self.regVal(.al_ax_eax_rax, .bits64));
                const b: i64 = @bitCast(self.readMemVal(d.addr, .bits64));
                const result: i128 = @as(i128, a) * @as(i128, b);
                const ru: u128 = @bitCast(result);
                const lo: u64 = @truncate(ru);
                const hi: u64 = @truncate(ru >> 64);
                self.setReg(.al_ax_eax_rax, .bits64, lo);
                self.setReg(.dl_dx_edx_rdx, .bits64, hi);
            },

            // ── div [mem] (unsigned) ──
            .div_mem8 => {
                const divisor = self.readMemVal(d.addr, .bits8);
                if (divisor == 0) return;
                const dividend = self.regVal(.al_ax_eax_rax, .bits16);
                const quot = dividend / @as(u16, @truncate(divisor));
                const rem = dividend % @as(u16, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @intCast(quot & 0xFF));
                self.setReg(.dl_dx_edx_rdx, .bits8, @intCast(rem & 0xFF));
            },
            .div_mem16 => {
                const divisor = self.readMemVal(d.addr, .bits16);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits16);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits16);
                const dividend = (@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo));
                const quot = dividend / @as(u32, @truncate(divisor));
                const rem = dividend % @as(u32, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(quot & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast(rem & 0xFFFF));
            },
            .div_mem32 => {
                const divisor = self.readMemVal(d.addr, .bits32);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits32);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits32);
                const dividend = (@as(u64, dividend_hi) << 32) | dividend_lo;
                const quot = dividend / @as(u64, divisor);
                const rem = dividend % @as(u64, divisor);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(quot & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast(rem & 0xFFFFFFFF));
            },
            .div_mem64 => {
                const divisor = self.readMemVal(d.addr, .bits64);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend = (@as(u128, dividend_hi) << 64) | dividend_lo;
                const quot = dividend / @as(u128, divisor);
                const rem = dividend % @as(u128, divisor);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(quot & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast(rem & 0xFFFFFFFFFFFFFFFF));
            },

            // ── idiv [mem] (signed) ──
            .idiv_mem8 => {
                const divisor: i8 = @bitCast(@as(u8, @intCast(self.readMemVal(d.addr, .bits8))));
                if (divisor == 0) return;
                const dividend: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const quot = @divTrunc(dividend, @as(i16, divisor));
                const rem = @rem(dividend, @as(i16, divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @as(u8, @bitCast(@as(i8, @truncate(quot)))));
                self.setReg(.dl_dx_edx_rdx, .bits8, @as(u8, @bitCast(@as(i8, @truncate(rem)))));
            },
            .idiv_mem16 => {
                const divisor: i16 = @bitCast(@as(u16, @intCast(self.readMemVal(d.addr, .bits16))));
                if (divisor == 0) return;
                const dividend_lo: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const dividend_hi: u16 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits16));
                const dividend: i32 = @bitCast((@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo)));
                const quot = @divTrunc(dividend, @as(i32, divisor));
                const rem = @rem(dividend, @as(i32, divisor));
                {
                    const q: i16 = @truncate(quot);
                    const r: i16 = @truncate(rem);
                    self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(q)));
                    self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(r)));
                }
            },
            .idiv_mem32 => {
                const divisor: i32 = @bitCast(@as(u32, @intCast(self.readMemVal(d.addr, .bits32))));
                if (divisor == 0) return;
                const dividend_lo: u32 = @intCast(self.regVal(.al_ax_eax_rax, .bits32));
                const dividend_hi: u32 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits32));
                const dividend: i64 = @bitCast((@as(u64, dividend_hi) << 32) | @as(u64, dividend_lo));
                const quot = @divTrunc(dividend, @as(i64, divisor));
                const rem = @rem(dividend, @as(i64, divisor));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u64, @bitCast(quot)));
                self.setReg(.dl_dx_edx_rdx, .bits32, @as(u64, @bitCast(rem)));
            },
            .idiv_mem64 => {
                const divisor: i64 = @bitCast(self.readMemVal(d.addr, .bits64));
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend: i128 = @bitCast((@as(u128, dividend_hi) << 64) | dividend_lo);
                const quot = @divTrunc(dividend, @as(i128, divisor));
                const rem = @rem(dividend, @as(i128, divisor));
                const q64: u64 = @bitCast(@as(i64, @truncate(quot)));
                const r64: u64 = @bitCast(@as(i64, @truncate(rem)));
                self.setReg(.al_ax_eax_rax, .bits64, q64);
                self.setReg(.dl_dx_edx_rdx, .bits64, r64);
            },

            // ── mul reg (unsigned) ──
            .mul_reg8 => {
                const b = self.regVal(d.src_reg, .bits8);
                const a = self.regVal(.al_ax_eax_rax, .bits8);
                const result = @as(u16, @intCast(a)) * @as(u16, @intCast(b));
                self.setReg(.al_ax_eax_rax, .bits16, result);
            },
            .mul_reg16 => {
                const b: u16 = @intCast(self.regVal(d.src_reg, .bits16));
                const a: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const result: u32 = @as(u32, a) * @as(u32, b);
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(result & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast((result >> 16) & 0xFFFF));
            },
            .mul_reg32 => {
                const b = self.regVal(d.src_reg, .bits32);
                const a = self.regVal(.al_ax_eax_rax, .bits32);
                const result = @as(u64, a) * @as(u64, b);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(result & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast((result >> 32) & 0xFFFFFFFF));
            },
            .mul_reg64 => {
                const b = self.regVal(d.src_reg, .bits64);
                const a = self.regVal(.al_ax_eax_rax, .bits64);
                const result = @as(u128, a) * @as(u128, b);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(result & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast((result >> 64) & 0xFFFFFFFFFFFFFFFF));
            },

            // ── imul reg (signed) ──
            .imul_reg8 => {
                const a: i8 = @bitCast(@as(u8, @intCast(self.regVal(.al_ax_eax_rax, .bits8))));
                const b: i8 = @bitCast(@as(u8, @intCast(self.regVal(d.src_reg, .bits8))));
                const result: i16 = @as(i16, a) * @as(i16, b);
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(result)));
            },
            .imul_reg16 => {
                const a: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const b: i16 = @bitCast(@as(u16, @intCast(self.regVal(d.src_reg, .bits16))));
                const result: i32 = @as(i32, a) * @as(i32, b);
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @truncate(result)))));
                self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(@as(i16, @truncate(result >> 16)))));
            },
            .imul_reg32 => {
                const raw_a: u32 = @intCast(self.regVal(.al_ax_eax_rax, .bits32));
                const raw_b: u32 = @intCast(self.regVal(d.src_reg, .bits32));
                const a: i32 = @bitCast(raw_a);
                const b: i32 = @bitCast(raw_b);
                const result: i64 = @as(i64, a) * @as(i64, b);
                const ru: u64 = @bitCast(result);
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(ru));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(ru >> 32));
            },
            .imul_reg64 => {
                const a: i64 = @bitCast(self.regVal(.al_ax_eax_rax, .bits64));
                const b: i64 = @bitCast(self.regVal(d.src_reg, .bits64));
                const result: i128 = @as(i128, a) * @as(i128, b);
                const ru: u128 = @bitCast(result);
                self.setReg(.al_ax_eax_rax, .bits64, @truncate(ru));
                self.setReg(.dl_dx_edx_rdx, .bits64, @truncate(ru >> 64));
            },

            // ── div reg (unsigned) ──
            .div_reg8 => {
                const divisor = self.regVal(d.src_reg, .bits8);
                if (divisor == 0) return;
                const dividend = self.regVal(.al_ax_eax_rax, .bits16);
                const quot = dividend / @as(u16, @truncate(divisor));
                const rem = dividend % @as(u16, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @intCast(quot & 0xFF));
                self.setReg(.dl_dx_edx_rdx, .bits8, @intCast(rem & 0xFF));
            },
            .div_reg16 => {
                const divisor = self.regVal(d.src_reg, .bits16);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits16);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits16);
                const dividend = (@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo));
                const quot = dividend / @as(u32, @truncate(divisor));
                const rem = dividend % @as(u32, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(quot & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast(rem & 0xFFFF));
            },
            .div_reg32 => {
                const divisor = self.regVal(d.src_reg, .bits32);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits32);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits32);
                const dividend = (@as(u64, dividend_hi) << 32) | dividend_lo;
                const quot = dividend / @as(u64, divisor);
                const rem = dividend % @as(u64, divisor);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(quot & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast(rem & 0xFFFFFFFF));
            },
            .div_reg64 => {
                const divisor = self.regVal(d.src_reg, .bits64);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend = (@as(u128, dividend_hi) << 64) | dividend_lo;
                const quot = dividend / @as(u128, divisor);
                const rem = dividend % @as(u128, divisor);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(quot & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast(rem & 0xFFFFFFFFFFFFFFFF));
            },

            // ── idiv reg (signed) ──
            .idiv_reg8 => {
                const divisor: i8 = @bitCast(@as(u8, @intCast(self.regVal(d.src_reg, .bits8))));
                if (divisor == 0) return;
                const dividend: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const quot = @divTrunc(dividend, @as(i16, divisor));
                const rem = @rem(dividend, @as(i16, divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @as(u8, @bitCast(@as(i8, @truncate(quot)))));
                self.setReg(.dl_dx_edx_rdx, .bits8, @as(u8, @bitCast(@as(i8, @truncate(rem)))));
            },
            .idiv_reg16 => {
                const divisor: i16 = @bitCast(@as(u16, @intCast(self.regVal(d.src_reg, .bits16))));
                if (divisor == 0) return;
                const dividend_lo: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const dividend_hi: u16 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits16));
                const dividend: i32 = @bitCast((@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo)));
                const quot = @divTrunc(dividend, @as(i32, divisor));
                const rem = @rem(dividend, @as(i32, divisor));
                {
                    const q: i16 = @truncate(quot);
                    const r: i16 = @truncate(rem);
                    self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(q)));
                    self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(r)));
                }
            },
            .idiv_reg32 => {
                const divisor_raw: u32 = @intCast(self.regVal(d.src_reg, .bits32));
                const divisor: i32 = @bitCast(divisor_raw);
                if (divisor == 0) return;
                const dividend_lo: u32 = @intCast(self.regVal(.al_ax_eax_rax, .bits32));
                const dividend_hi: u32 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits32));
                const dividend: i64 = @bitCast((@as(u64, dividend_hi) << 32) | @as(u64, dividend_lo));
                const quot = @divTrunc(dividend, @as(i64, divisor));
                const rem = @rem(dividend, @as(i64, divisor));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u64, @bitCast(quot)));
                self.setReg(.dl_dx_edx_rdx, .bits32, @as(u64, @bitCast(rem)));
            },
            .idiv_reg64 => {
                const divisor: i64 = @bitCast(self.regVal(d.src_reg, .bits64));
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend: i128 = @bitCast((@as(u128, dividend_hi) << 64) | dividend_lo);
                const quot = @divTrunc(dividend, @as(i128, divisor));
                const rem = @rem(dividend, @as(i128, divisor));
                const q64b: u64 = @bitCast(@as(i64, @truncate(quot)));
                const r64b: u64 = @bitCast(@as(i64, @truncate(rem)));
                self.setReg(.al_ax_eax_rax, .bits64, q64b);
                self.setReg(.dl_dx_edx_rdx, .bits64, r64b);
            },

            // ── Sign extension ──
            .cbw => {
                // cbw: AL → AX (sign extend). With 0x66: AX → EAX. With REX.W: EAX → RAX (cdqe)
                const al = self.regVal(.al_ax_eax_rax, .bits8);
                const extended = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(al)))));
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(extended)));
            },
            .cwde => {
                const ax = self.regVal(.al_ax_eax_rax, .bits16);
                const extended = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(ax)))));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(extended)));
            },
            .cdqe => {
                const eax = self.regVal(.al_ax_eax_rax, .bits32);
                const extended = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(eax)))));
                self.setReg(.al_ax_eax_rax, .bits64, @as(u64, @bitCast(extended)));
            },
            .cwd => {
                // cwd: AX → DX:AX. With 0x66: EAX → EDX:EAX (cdq). With REX.W: RAX → RDX:RAX (cqo)
                const ax = self.regVal(.al_ax_eax_rax, .bits16);
                const sign = if (ax & 0x8000 != 0) @as(u16, 0xFFFF) else 0;
                self.setReg(.dl_dx_edx_rdx, .bits16, sign);
            },
            .cdq => {
                // cdq: EAX → EDX:EAX (sign extend eax into edx)
                const eax32 = self.regVal(.al_ax_eax_rax, .bits32);
                const sign = if (eax32 & 0x80000000 != 0) @as(u32, 0xFFFFFFFF) else 0;
                self.setReg(.dl_dx_edx_rdx, .bits32, sign);
            },
            .cqo => {
                // cqo: RAX → RDX:RAX (sign extend rax into rdx)
                const rax = self.regVal(.al_ax_eax_rax, .bits64);
                const sign = if (rax & 0x8000000000000000 != 0) @as(u64, 0xFFFFFFFFFFFFFFFF) else 0;
                self.setReg(.dl_dx_edx_rdx, .bits64, sign);
            },

            // ── Zero/sign extend loads ──
            .movzx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits8)
                else
                    self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movzx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits16)
                else
                    self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movsx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    @as(i64, @as(i8, @bitCast(@as(u8, @truncate(self.regVal(d.src_reg, .bits8))))))
                else
                    @as(i64, @as(i8, @bitCast(@as(u8, @truncate(self.readMemVal(d.addr, .bits8))))));
                const dst_size: Size = if (d.size == .bits64) .bits64 else .bits32;
                self.setReg(d.dst_reg, dst_size, @as(u64, @bitCast(val)));
            },
            .movsx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    @as(i64, @as(i16, @bitCast(@as(u16, @truncate(self.regVal(d.src_reg, .bits16))))))
                else
                    @as(i64, @as(i16, @bitCast(@as(u16, @truncate(self.readMemVal(d.addr, .bits16))))));
                const dst_size: Size = if (d.size == .bits64) .bits64 else .bits32;
                self.setReg(d.dst_reg, dst_size, @as(u64, @bitCast(val)));
            },
            .movsxd_reg64_reg32 => {
                const val = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regVal(d.src_reg, .bits32))))));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(val)));
            },
            .movsxd_reg64_mem32 => {
                const raw = self.readMemVal(d.addr, .bits32);
                const val = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(raw)))));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(val)));
            },
            .lea_reg_mem => {
                self.setReg(d.dst_reg, d.size, d.addr);
            },
            .cmovcc_reg_reg => {
                if (evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.regVal(d.src_reg, d.size));
                } else if (d.size == .bits32) {
                    self.setReg(d.dst_reg, .bits64, self.regVal(d.dst_reg, .bits32));
                }
            },
            .cmovcc_reg_mem => {
                if (evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.readMemVal(d.addr, d.size));
                } else if (d.size == .bits32) {
                    self.setReg(d.dst_reg, .bits64, self.regVal(d.dst_reg, .bits32));
                }
            },
            .setcc_reg8 => {
                self.setReg(d.dst_reg, .bits8, if (evalCond(self.regs.rflags, d.cond)) 1 else 0);
            },
            .setcc_mem8 => {
                self.writeMemVal(d.addr, .bits8, if (evalCond(self.regs.rflags, d.cond)) 1 else 0);
            },
            .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64 => {
                const size = d.size;
                const accum = self.regVal(.al_ax_eax_rax, size);
                const old = self.readMemVal(d.addr, size);
                self.setFlagsSub(accum, old, accum -% old, size);
                if ((accum & maskForSize(size)) == (old & maskForSize(size))) {
                    self.writeMemVal(d.addr, size, self.regVal(d.src_reg, size));
                    self.setFlag(RFL_ZF, true);
                } else {
                    self.setReg(.al_ax_eax_rax, size, old);
                    self.setFlag(RFL_ZF, false);
                }
            },
            .xchg_mem32_reg32, .xchg_mem64_reg64 => {
                const old_mem = self.readMemVal(d.addr, d.size);
                const old_reg = self.regVal(d.src_reg, d.size);
                self.writeMemVal(d.addr, d.size, old_reg);
                self.setReg(d.src_reg, d.size, old_mem);
            },
            .xadd_mem32_reg32, .xadd_mem64_reg64 => {
                const old_mem = self.readMemVal(d.addr, d.size);
                const old_reg = self.regVal(d.src_reg, d.size);
                const result = old_mem +% old_reg;
                self.writeMemVal(d.addr, d.size, result);
                self.setReg(d.src_reg, d.size, old_mem);
                self.setFlagsAdd(old_mem, old_reg, result, d.size);
            },
            .xorps_xmm_xmm => {
                for (0..16) |i| {
                    self.xmm[d.xmm_dst][i] ^= self.xmm[d.xmm_src][i];
                }
            },
            .movaps_xmm_xmm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            },
            .movaps_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            },
            .movaps_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            },

            // ── imul r64, r/m64 (0F AF) ──
            .imul_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                const r = @as(i64, @bitCast(a)) * @as(i64, @bitCast(b));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                const r = @as(i64, @bitCast(a)) * @as(i64, @bitCast(b));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                const r = @as(i32, @bitCast(@as(u32, @truncate(a)))) * @as(i32, @bitCast(@as(u32, @truncate(b))));
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },
            .imul_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                const r = @as(i32, @bitCast(@as(u32, @truncate(a)))) * @as(i32, @bitCast(@as(u32, @truncate(b))));
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },

            // ── imul r, r/m, imm8 (0x6B) ──
            .imul_reg64_mem64_imm8 => {
                const b = self.readMemVal(d.addr, .bits64);
                const imm = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i64, @bitCast(b)) * imm;
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg64_reg64_imm8 => {
                const b = self.regVal(d.src_reg, .bits64);
                const imm = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i64, @bitCast(b)) * imm;
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg32_mem32_imm8 => {
                const b = self.readMemVal(d.addr, .bits32);
                const imm = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i32, @bitCast(@as(u32, @truncate(b)))) * imm;
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },
            .imul_reg32_reg32_imm8 => {
                const b = self.regVal(d.src_reg, .bits32);
                const imm = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i32, @bitCast(@as(u32, @truncate(b)))) * imm;
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },

            // ── Stack and calls ──
            .call_rel32 => {
                const next_rip = self.regs.rip + d.len;
                const rel = @as(i64, @bitCast(d.imm));
                const target = @as(i64, @bitCast(self.regs.rip)) + @as(i64, d.len) + rel;
                const target_rip = @as(u64, @bitCast(target));
                if (x64_linux_runtime.tryLocalFunctionShim(self, target_rip, next_rip)) {
                    return;
                }
                self.noteGuestCall(.direct, target_rip, next_rip);
                self.push(next_rip);
                self.regs.rip = target_rip;
                return;
            },
            .call_mem64, .call_reg64 => {
                const next_rip = self.regs.rip + d.len;
                if (d.op == .call_mem64 and x64_linux_runtime.tryDynamicFunctionShim(self, d.addr, next_rip)) {
                    return;
                }
                const target = if (d.op == .call_reg64)
                    self.regVal(d.src_reg, .bits64)
                else
                    self.readMemVal(d.addr, .bits64);
                if (target == 0 and d.op == .call_mem64 and x64_linux_runtime.tryLibcStartMainTrampoline(self, d, next_rip)) {
                    return;
                }
                if (target == 0) {
                    log.err("unresolved indirect call at rip=0x{x} operand=0x{x}", .{ self.regs.rip, d.addr });
                    self.faulted = true;
                    self.exit_code = 127;
                    self.terminated = true;
                    return;
                }
                self.noteGuestCall(.indirect, target, next_rip);
                self.push(next_rip);
                self.regs.rip = target;
                return;
            },
            .ret => {
                const return_rip = self.pop();
                self.regs.rip = return_rip;
                self.noteGuestReturn(return_rip);
                return;
            },
            .push_reg => {
                self.push(self.regVal(d.src_reg, .bits64));
            },
            .push_mem64 => {
                self.push(self.readMemVal(d.addr, .bits64));
            },
            .push_imm => {
                self.push(d.imm);
            },
            .pop_reg => {
                self.setReg(d.dst_reg, .bits64, self.pop());
            },
            .pop_mem64 => {
                const val = self.pop();
                self.writeMemVal(d.addr, .bits64, val);
            },
            .hlt => {
                self.exit_code = self.regs.rax;
                self.terminated = true;
            },

            // ── Jump short rel8 ──
            .jmp_rel8 => {
                const target = @as(i64, @bitCast(self.regs.rip)) + d.len + @as(i64, @bitCast(d.imm));
                self.regs.rip = @as(u64, @bitCast(target));
                return;
            },
            .jmp_mem64, .jmp_reg64 => {
                if (d.op == .jmp_mem64 and x64_linux_runtime.tryDynamicFunctionShim(self, d.addr, null)) {
                    return;
                }
                const target = if (d.op == .jmp_reg64)
                    self.regVal(d.src_reg, .bits64)
                else
                    self.readMemVal(d.addr, .bits64);
                if (target == 0) {
                    log.err("unresolved indirect jump at rip=0x{x} operand=0x{x}", .{ self.regs.rip, d.addr });
                    self.faulted = true;
                    self.exit_code = 127;
                    self.terminated = true;
                    return;
                }
                self.regs.rip = target;
                return;
            },

            // ── Conditional jump rel8 ──
            .jcc_rel8 => {
                if (evalCond(self.regs.rflags, d.cond)) {
                    const target = @as(i64, @bitCast(self.regs.rip)) + d.len + @as(i64, @bitCast(d.imm));
                    self.regs.rip = @as(u64, @bitCast(target));
                    return;
                }
            },
            .jcc_rel32 => {
                if (evalCond(self.regs.rflags, d.cond)) {
                    const target = @as(i64, @bitCast(self.regs.rip)) + d.len + @as(i64, @bitCast(d.imm));
                    self.regs.rip = @as(u64, @bitCast(target));
                    return;
                }
            },

            // ── Syscall ──
            .syscall => {
                const syscall_number = self.regs.rax;
                const syscall_fd = self.regs.rdi;
                const syscall_buf = self.regs.rsi;
                const syscall_count = self.regs.rdx;
                self.invokeLinuxSyscall(
                    syscall_number,
                    self.regs.rdi,
                    self.regs.rsi,
                    self.regs.rdx,
                    self.regs.r10,
                    self.regs.r8,
                    self.regs.r9,
                );
                x64_guest_abi.diagnoseSyscall(self, syscall_number, syscall_fd, syscall_buf, syscall_count, self.regs.rax);
            },
        }

        if (!self.terminated) {
            self.regs.rip += d.len;
        }
    }

    pub fn invokeLinuxSyscall(self: *ElfState, number: u64, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
        self.regs.rax = number;
        self.regs.rdi = arg1;
        self.regs.rsi = arg2;
        self.regs.rdx = arg3;
        self.regs.r10 = arg4;
        self.regs.r8 = arg5;
        self.regs.r9 = arg6;
        self.dispatchLinuxSyscall();
    }

    fn dispatchLinuxSyscall(self: *ElfState) void {
        switch (self.regs.rax) {
            SYS_exit => {
                self.exit_code = self.regs.rdi;
                self.terminated = true;
                self.traceSyscall("exit(code={d})", .{self.exit_code});
            },
            SYS_read => {
                self.handleReadSyscall();
            },
            SYS_write => {
                self.handleWriteSyscall();
            },
            SYS_open => {
                self.handleOpenSyscall();
            },
            SYS_close => {
                self.handleCloseSyscall();
            },
            SYS_creat => {
                self.handleCreatSyscall();
            },
            SYS_gettid => {
                self.regs.rax = 1;
                self.traceSyscall("gettid() -> {d}", .{self.regs.rax});
            },
            else => {
                log.warn("unimplemented syscall {d}", .{self.regs.rax});
                self.faulted = true;
                self.exit_code = 127;
                self.terminated = true;
            },
        }
    }

    fn guestCString(self: *ElfState, addr: u64) ?[]const u8 {
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const rest = self.mem[off_usize..];
        const len = std.mem.indexOfScalar(u8, rest, 0) orelse return null;
        return rest[0..len];
    }

    fn handleOpenSyscall(self: *ElfState) void {
        const path_addr = self.regs.rdi;
        const flags_raw = self.regs.rsi;
        const mode_raw = self.regs.rdx;
        const path = self.guestCString(self.regs.rdi) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            self.traceSyscall("open(path=0x{x}, flags=0x{x}, mode=0o{o}) -> {d}", .{
                path_addr,
                flags_raw,
                mode_raw & 0o7777,
                syscallResult(self.regs.rax),
            });
            return;
        };
        const path_z = self.allocator.dupeZ(u8, path) catch {
            self.regs.rax = x64_syscalls.errnoValue(.io);
            self.traceSyscall("open(\"{s}\", flags=0x{x}, mode=0o{o}) -> {d}", .{
                path,
                flags_raw,
                mode_raw & 0o7777,
                syscallResult(self.regs.rax),
            });
            return;
        };
        defer self.allocator.free(path_z);

        const fd = std.c.open(path_z.ptr, linuxOpenFlagsToHost(flags_raw), @as(std.c.mode_t, @intCast(mode_raw & 0o7777)));
        self.regs.rax = if (fd < 0) x64_syscalls.errnoValue(.no_entry) else @as(u64, @intCast(fd));
        self.traceOpenResult(path, flags_raw, mode_raw, self.regs.rax);
    }

    fn handleCreatSyscall(self: *ElfState) void {
        const path_addr = self.regs.rdi;
        const requested_mode = if (self.regs.rdx != 0) self.regs.rdx else self.regs.rsi;
        const path = self.guestCString(self.regs.rdi) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            self.traceSyscall("creat(path=0x{x}, mode=0o{o}) -> {d}", .{
                path_addr,
                requested_mode & 0o7777,
                syscallResult(self.regs.rax),
            });
            return;
        };
        const path_z = self.allocator.dupeZ(u8, path) catch {
            self.regs.rax = x64_syscalls.errnoValue(.io);
            self.traceSyscall("creat(\"{s}\", mode=0o{o}) -> {d}", .{
                path,
                requested_mode & 0o7777,
                syscallResult(self.regs.rax),
            });
            return;
        };
        defer self.allocator.free(path_z);
        if (self.diagnose_abi) self.rememberInteractiveOutputPath(path);

        var flags: std.c.O = .{};
        flags.ACCMODE = .WRONLY;
        flags.CREAT = true;
        flags.TRUNC = true;
        const mode: std.c.mode_t = @intCast(requested_mode & 0o7777);
        var fd = std.c.open(path_z.ptr, flags, mode);
        if (fd < 0) {
            _ = std.c.unlink(path_z.ptr);
            fd = std.c.open(path_z.ptr, flags, mode);
        }
        self.regs.rax = if (fd < 0) x64_syscalls.errnoValue(.io) else @as(u64, @intCast(fd));
        self.traceCreatResult(path, requested_mode, self.regs.rax);
    }

    fn rememberInteractiveOutputPath(self: *ElfState, path: []const u8) void {
        const copy = self.allocator.dupe(u8, path) catch return;
        if (self.interactive_output_path) |old| self.allocator.free(old);
        self.interactive_output_path = copy;
        self.interactive_summary_printed = false;
    }

    fn handleReadSyscall(self: *ElfState) void {
        const fd_raw = self.regs.rdi;
        const fd = hostFdFromGuest(fd_raw) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_file_descriptor);
            self.traceGuestIo("read", fd_raw, self.regs.rsi, self.regs.rdx, self.regs.rax);
            return;
        };
        const addr = self.regs.rsi;
        const count = self.regs.rdx;
        const data = self.guestMemory(addr, count) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            self.traceGuestIo("read", fd_raw, addr, count, self.regs.rax);
            return;
        };

        const n = std.c.read(fd, data.ptr, data.len);
        self.regs.rax = if (n < 0) x64_syscalls.errnoValue(.io) else @as(u64, @intCast(n));
        self.traceGuestIo("read", fd_raw, addr, count, self.regs.rax);
    }

    fn handleCloseSyscall(self: *ElfState) void {
        const fd_raw = self.regs.rdi;
        const fd = hostFdFromGuest(fd_raw) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_file_descriptor);
            if (self.shouldTraceFd(fd_raw)) {
                log.info("syscall: close(fd={d}) -> {d}", .{ fd_raw, syscallResult(self.regs.rax) });
            }
            return;
        };
        if (fd <= 2) {
            self.regs.rax = 0;
            if (self.shouldTraceFd(fd_raw)) {
                log.info("syscall: close(fd={d}) -> {d}", .{ fd, syscallResult(self.regs.rax) });
            }
            return;
        }
        self.regs.rax = if (std.c.close(fd) == 0) 0 else x64_syscalls.errnoValue(.bad_file_descriptor);
        if (self.shouldTraceFd(fd_raw)) {
            log.info("syscall: close(fd={d}) -> {d}", .{ fd, syscallResult(self.regs.rax) });
        }
    }

    fn handleWriteSyscall(self: *ElfState) void {
        const fd = self.regs.rdi;
        const addr = self.regs.rsi;
        const count = self.regs.rdx;
        const data = self.guestMemoryConst(addr, count) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            self.traceGuestIo("write", fd, addr, count, self.regs.rax);
            return;
        };
        self.regs.rax = self.writeHostFd(fd, data);
        self.traceGuestIo("write", fd, addr, count, self.regs.rax);
    }
};

fn syscallResult(value: u64) i64 {
    return @bitCast(value);
}

fn hostFdFromGuest(fd: u64) ?std.c.fd_t {
    if (fd > std.math.maxInt(std.c.fd_t)) return null;
    return @intCast(fd);
}

fn linuxOpenFlagsToHost(flags_raw: u64) std.c.O {
    var flags: std.c.O = .{};
    flags.ACCMODE = switch (flags_raw & 0x3) {
        1 => .WRONLY,
        2 => .RDWR,
        else => .RDONLY,
    };
    flags.CREAT = (flags_raw & 0o100) != 0;
    flags.TRUNC = (flags_raw & 0o1000) != 0;
    flags.APPEND = (flags_raw & 0o2000) != 0;
    return flags;
}

fn shouldTraceRip(rip: u64) bool {
    const start_raw = std.c.getenv("ROSETTE_ELF_TRACE_START") orelse return false;
    const start = parseEnvU64(std.mem.sliceTo(start_raw, 0)) orelse return false;
    const end = if (std.c.getenv("ROSETTE_ELF_TRACE_END")) |end_raw|
        parseEnvU64(std.mem.sliceTo(end_raw, 0)) orelse start
    else
        start;
    return rip >= start and rip <= end;
}

fn parseEnvU64(text: []const u8) ?u64 {
    if (text.len >= 2 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X')) {
        return std.fmt.parseUnsigned(u64, text[2..], 16) catch null;
    }
    return std.fmt.parseUnsigned(u64, text, 10) catch null;
}

// ─── Decoder ───

fn hasRexPrefix(byte: u8) bool {
    return byte & 0xF0 == 0x40;
}

fn rexW(rex: u8) bool {
    return rex & 0x08 != 0;
}

fn rexR(rex: u8) bool {
    return rex & 0x04 != 0;
}

fn rexX(rex: u8) bool {
    return rex & 0x02 != 0;
}

fn rexB(rex: u8) bool {
    return rex & 0x01 != 0;
}

fn regId(code: u8, extended: bool) RegId {
    const value: u4 = @as(u4, @truncate(code)) | if (extended) @as(u4, 8) else @as(u4, 0);
    return @enumFromInt(value);
}

fn modRmReg(code: u8, rex: u8) RegId {
    return regId(code, rexR(rex));
}

fn modRmRm(code: u8, rex: u8) RegId {
    return regId(code, rexB(rex));
}

fn xmmRegIndex(code: u8, extended: bool) u8 {
    return (code & 7) | if (extended) @as(u8, 8) else @as(u8, 0);
}

fn signExtendImm8(imm: u64) u64 {
    const signed: i8 = @bitCast(@as(u8, @truncate(imm)));
    return @as(u64, @bitCast(@as(i64, signed)));
}

fn signExtendDisp32(raw: u32) u64 {
    const signed: i32 = @bitCast(raw);
    return @as(u64, @bitCast(@as(i64, signed)));
}

fn testImmForSize(imm: u64, size: Size) u64 {
    return switch (size) {
        .bits8 => imm & 0xFF,
        .bits16 => imm & 0xFFFF,
        .bits32 => imm & 0xFFFF_FFFF,
        .bits64 => @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(imm))))))),
    };
}

fn readGroup3TestImm(bytes: []const u8, pos: *usize, size: Size) ?u64 {
    const imm_len: usize = switch (size) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32, .bits64 => 4,
    };
    if (pos.* + imm_len > bytes.len) return null;
    const imm = switch (size) {
        .bits8 => @as(u64, bytes[pos.*]),
        .bits16 => @as(u64, std.mem.readInt(u16, bytes[pos.*..][0..2], .little)),
        .bits32, .bits64 => @as(u64, std.mem.readInt(u32, bytes[pos.*..][0..4], .little)),
    };
    pos.* += imm_len;
    return imm;
}

const MemRef = struct {
    addr: u64,
    sib_has_index: bool,
    sib_index_reg: RegId,
    sib_scale: u2,
    sib_has_base: bool,
    sib_base_reg: RegId,
    rip_relative: bool,
};

fn parseModRmMemory(bytes: []const u8, pos: *usize, mod: u3, rm: u8, rex: u8) ?MemRef {
    if (rm == 4) return parseSib(bytes, pos, mod, rex);

    var addr: u64 = 0;
    var has_base = true;
    var rip_relative = false;
    if (mod == 0 and rm == 5) {
        if (pos.* + 4 > bytes.len) return null;
        const disp = std.mem.readInt(i32, bytes[pos.*..][0..4], .little);
        addr = @as(u64, @bitCast(@as(i64, disp)));
        pos.* += 4;
        has_base = false;
        rip_relative = true;
    } else if (mod == 1) {
        if (pos.* + 1 > bytes.len) return null;
        addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i8, bytes[pos.*..][0..1], .little))));
        pos.* += 1;
    } else if (mod == 2) {
        if (pos.* + 4 > bytes.len) return null;
        addr = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
        pos.* += 4;
    }

    return .{
        .addr = addr,
        .sib_has_index = false,
        .sib_index_reg = .al_ax_eax_rax,
        .sib_scale = 0,
        .sib_has_base = has_base,
        .sib_base_reg = modRmRm(rm, rex),
        .rip_relative = rip_relative,
    };
}

fn parseSib(bytes: []const u8, pos: *usize, mod: u3, rex: u8) ?MemRef {
    if (pos.* >= bytes.len) return null;
    const sib_byte = bytes[pos.*];
    pos.* += 1;
    const base = sib_byte & 7;
    const index = (sib_byte >> 3) & 7;
    const scale: u2 = @as(u2, @truncate(sib_byte >> 6));

    // Absolute disp32: mod=00, base=5, index=4
    if (mod == 0 and base == 5 and index == 4) {
        if (pos.* + 4 > bytes.len) return null;
        const addr = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
        pos.* += 4;
        return .{
            .addr = addr,
            .sib_has_index = false,
            .sib_index_reg = .al_ax_eax_rax,
            .sib_scale = 0,
            .sib_has_base = false,
            .sib_base_reg = .al_ax_eax_rax,
            .rip_relative = false,
        };
    }

    // SIB with register components — read displacement
    var addr: u64 = 0;
    if (mod == 0 and base == 5) {
        // [index*scale + disp32], no base register
        if (pos.* + 4 > bytes.len) return null;
        addr = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
        pos.* += 4;
    } else if (mod == 1) {
        if (pos.* + 1 > bytes.len) return null;
        addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i8, bytes[pos.*..][0..1], .little))));
        pos.* += 1;
    } else if (mod == 2) {
        if (pos.* + 4 > bytes.len) return null;
        addr = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
        pos.* += 4;
    }

    return .{
        .addr = addr,
        .sib_has_index = (index != 4),
        .sib_index_reg = regId(index, rexX(rex)),
        .sib_scale = scale,
        .sib_has_base = !(mod == 0 and base == 5),
        .sib_base_reg = modRmRm(base, rex),
        .rip_relative = false,
    };
}

fn decodeInsn(bytes: []const u8) DecodedInsn {
    if (bytes.len == 0) return .{};

    var pos: usize = 0;
    var rex: u8 = 0;
    var has_66: bool = false;
    var has_0x67: bool = false;

    // Parse prefixes
    while (pos < bytes.len and pos < 15) {
        const b = bytes[pos];
        if (b == 0x66) {
            has_66 = true;
            pos += 1;
        } else if (b == 0x67) {
            has_0x67 = true;
            pos += 1;
        } else if (b == 0x2E) {
            // CS segment override, used in long NOP encodings.
            pos += 1;
        } else if (b == 0x64) {
            // FS segment override. The emulator currently maps the low TLS canary
            // slot as zero, which is enough for compiler-generated stack checks.
            pos += 1;
        } else if (b == 0xF0) {
            // LOCK prefix. The ELF runner is single-threaded, so accept it and
            // let the memory operation execute normally.
            pos += 1;
        } else if (hasRexPrefix(b)) {
            rex = b;
            pos += 1;
        } else {
            break;
        }
    }

    if (pos >= bytes.len) return .{};

    const opcode = bytes[pos];
    pos += 1;

    const rex_w = rexW(rex);

    switch (opcode) {
        0x00...0x03 => {
            // ADD r/m, r or ADD r, r/m
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (d == 1) {
                    const dst_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    };
                } else {
                    const src_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_mem8_reg8, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_mem16_reg16, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_mem32_reg32, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_mem64_reg64, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    };
                }
            }

            if (mod == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .add_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .add_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .add_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .add_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x05 => {
            // ADD AX/EAX/RAX, imm16/imm32
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;
            const imm_len: usize = if (size == .bits16) 2 else 4;
            if (pos + imm_len > bytes.len) return .{};
            const imm = if (size == .bits16)
                @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
            else
                @as(u64, std.mem.readInt(u32, bytes[pos..][0..4], .little));
            pos += imm_len;
            return switch (size) {
                .bits16 => DecodedInsn{ .op = .add_reg16_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .add_reg32_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .add_reg64_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits8 => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            };
        },

        0x08...0x0B => {
            // OR r/m, r or OR r, r/m. The ELF runner currently executes
            // register destinations; memory destinations fail explicitly.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            if (d == 0 and mod_v != 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .or_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .or_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .or_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .or_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            if (d != 1) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return switch (size) {
                .bits8 => DecodedInsn{ .op = .or_reg8_mem8, .size = size, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                .bits16 => DecodedInsn{ .op = .or_reg16_mem16, .size = size, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .or_reg32_mem32, .size = size, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .or_reg64_mem64, .size = size, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
            };
        },

        0x24 => {
            // AND AL, imm8
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .and_reg8_imm8, .size = .bits8, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) };
        },

        0x25 => {
            // AND AX/EAX/RAX, imm16/imm32
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;
            const imm_len: usize = if (size == .bits16) 2 else 4;
            if (pos + imm_len > bytes.len) return .{};
            const imm = if (size == .bits16)
                @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
            else
                @as(u64, std.mem.readInt(u32, bytes[pos..][0..4], .little));
            pos += imm_len;
            return switch (size) {
                .bits16 => DecodedInsn{ .op = .and_reg16_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .and_reg32_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .and_reg64_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits8 => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            };
        },

        0x18...0x1B => {
            // SBB r/m, r or SBB r, r/m. Register forms are enough for libc carry-mask idioms.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            if (mod_v != 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
            const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
            return switch (size) {
                .bits8 => DecodedInsn{ .op = .sbb_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits16 => DecodedInsn{ .op = .sbb_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .sbb_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .sbb_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
            };
        },

        0x20...0x23, 0x30...0x33 => {
            // AND/XOR r/m, r or r, r/m.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod_v != 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
            const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
            if (opcode >= 0x30) {
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .xor_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .xor_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .xor_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .xor_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }
            return switch (size) {
                .bits8 => DecodedInsn{ .op = .and_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits16 => DecodedInsn{ .op = .and_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .and_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .and_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
            };
        },
        0x34 => {
            // XOR AL, imm8
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .xor_reg8_imm8, .size = .bits8, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) };
        },
        0x3C => {
            // CMP AL, imm8
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .cmp_reg8_imm8, .size = .bits8, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) };
        },
        0x28...0x2B => {
            // SUB r/m, r or SUB r, r/m
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib_byte = bytes[pos];
                pos += 1;
                _ = (sib_byte >> 3) & 7;
                const sib_base = sib_byte & 7;
                if (sib_base == 5 and mod == 0 and d == 1) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    const dst_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .sub_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .sub_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .sub_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .sub_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                    };
                }
            }

            if (mod == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .sub_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .sub_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .sub_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .sub_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x38...0x3B => {
            // CMP r/m, r (38/39) or CMP r, r/m (3A/3B)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod_v == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .cmp_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .cmp_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .cmp_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .cmp_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (d == 0) {
                    // cmp r/m, r: source is reg, dst is [addr]
                    const src_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_mem8_reg8, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_mem16_reg16, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_mem32_reg32, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_mem64_reg64, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    };
                } else {
                    // cmp reg, r/m: dst is reg, source is [addr]
                    const dst_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    };
                }
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x63 => {
            // MOVSXD r64, r/m32 (only with REX.W)
            if (!rex_w) return .{};
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            if (mod_v == 3) {
                return DecodedInsn{
                    .op = .movsxd_reg64_reg32,
                    .dst_reg = modRmReg(reg, rex),
                    .src_reg = modRmRm(rm, rex),
                    .len = @intCast(pos),
                };
            }
            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = .movsxd_reg64_mem32, .size = .bits64, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0x50...0x57 => {
            // PUSH r64
            return DecodedInsn{
                .op = .push_reg,
                .size = .bits64,
                .src_reg = regId(opcode - 0x50, rexB(rex)),
                .len = @intCast(pos),
            };
        },

        0x58...0x5F => {
            // POP r64
            return DecodedInsn{
                .op = .pop_reg,
                .size = .bits64,
                .dst_reg = regId(opcode - 0x58, rexB(rex)),
                .len = @intCast(pos),
            };
        },

        0x68 => {
            // PUSH imm32, sign-extended to stack width.
            if (pos + 4 > bytes.len) return .{};
            const imm = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            return DecodedInsn{
                .op = .push_imm,
                .size = .bits64,
                .imm = @as(u64, @bitCast(@as(i64, imm))),
                .len = @intCast(pos),
            };
        },

        0x6B => {
            // IMUL r, r/m, imm8
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const dst_reg = modRmReg(reg, rex);
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            const size: Size = if (rex_w) .bits64 else .bits32;
            if (mod_v == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib = bytes[pos];
                pos += 1;
                const base = sib & 7;
                const sib_index = (sib >> 3) & 7;
                if (base == 5 and sib_index == 4) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    return switch (size) {
                        .bits32 => DecodedInsn{ .op = .imul_reg32_mem32_imm8, .size = size, .dst_reg = dst_reg, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_reg64_mem64_imm8, .size = size, .dst_reg = dst_reg, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                }
            } else if (mod_v == 3) {
                const src_reg = modRmRm(rm, rex);
                return switch (size) {
                    .bits32 => DecodedInsn{ .op = .imul_reg32_reg32_imm8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .imul_reg64_reg64_imm8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }
            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x6A => {
            // PUSH imm8, sign-extended to stack width.
            if (pos >= bytes.len) return .{};
            const imm = std.mem.readInt(i8, bytes[pos..][0..1], .little);
            pos += 1;
            return DecodedInsn{
                .op = .push_imm,
                .size = .bits64,
                .imm = @as(u64, @bitCast(@as(i64, imm))),
                .len = @intCast(pos),
            };
        },

        0x70...0x7F => {
            // Conditional jumps
            const cond: Cond = @enumFromInt(@as(u4, @truncate(opcode & 0x0F)));
            if (pos >= bytes.len) return .{};
            const rel = std.mem.readInt(i8, bytes[pos..][0..1], .little);
            pos += 1;
            return DecodedInsn{
                .op = .jcc_rel8,
                .cond = cond,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0x80 => {
            // Group 1: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP r/m8, imm8
            // /0 = ADD, /2 = ADC, /4 = AND, /5 = SUB, /6 = XOR, /7 = CMP
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;

            if (reg_field != 0 and reg_field != 2 and reg_field != 4 and reg_field != 5 and reg_field != 6 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                const dst_reg = modRmRm(rm, rex);
                return switch (reg_field) {
                    0 => DecodedInsn{ .op = .add_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    4 => DecodedInsn{ .op = .and_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    5 => DecodedInsn{ .op = .sub_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    6 => DecodedInsn{ .op = .xor_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    7 => DecodedInsn{ .op = .cmp_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                return switch (reg_field) {
                    0 => DecodedInsn{ .op = .add_mem8_imm8, .size = .bits8, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    5 => DecodedInsn{ .op = .sub_mem8_imm8, .size = .bits8, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    7 => DecodedInsn{ .op = .cmp_mem8_imm8, .size = .bits8, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x81 => {
            // Group 1 with imm16/32.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;
            if (reg_field != 0 and reg_field != 1 and reg_field != 5) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            const imm_len: usize = if (size == .bits16) 2 else 4;

            if (mod_v == 3) {
                if (pos + imm_len > bytes.len) return .{};
                const imm = if (size == .bits16)
                    @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
                else blk: {
                    const raw = std.mem.readInt(i32, bytes[pos..][0..4], .little);
                    break :blk if (size == .bits64) @as(u64, @bitCast(@as(i64, raw))) else @as(u64, @as(u32, @bitCast(raw)));
                };
                pos += imm_len;
                const dst_reg = modRmRm(rm, rex);
                if (reg_field == 0) {
                    return switch (size) {
                        .bits16 => DecodedInsn{ .op = .add_reg16_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_reg32_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_reg64_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits8 => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                }
                if (reg_field == 5) {
                    return switch (size) {
                        .bits16 => DecodedInsn{ .op = .sub_reg16_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .sub_reg32_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .sub_reg64_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                }
                return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            if (pos + imm_len > bytes.len) return .{};
            const imm = if (size == .bits16)
                @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
            else blk: {
                const raw = std.mem.readInt(i32, bytes[pos..][0..4], .little);
                break :blk if (size == .bits64) @as(u64, @bitCast(@as(i64, raw))) else @as(u64, @as(u32, @bitCast(raw)));
            };
            pos += imm_len;
            return switch (reg_field) {
                1 => switch (size) {
                    .bits16 => DecodedInsn{ .op = .or_mem16_imm32, .size = size, .imm = imm, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .or_mem32_imm32, .size = size, .imm = imm, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .or_mem64_imm32, .size = size, .imm = imm, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits8 => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                },
                else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            };
        },

        0x83 => {
            // Group 1: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP with imm8 sign-extended
            // /0 = ADD, /2 = ADC, /4 = AND, /5 = SUB, /6 = XOR, /7 = CMP
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (reg_field != 0 and reg_field != 2 and reg_field != 4 and reg_field != 5 and reg_field != 6 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                const dst_reg = modRmRm(rm, rex);
                return switch (reg_field) {
                    0 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    2 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .adc_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .adc_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .adc_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .adc_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    4 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .and_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .and_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .and_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .and_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    5 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .sub_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .sub_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .sub_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .sub_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    6 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .xor_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .xor_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .xor_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .xor_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                return switch (reg_field) {
                    0 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_mem8_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_mem16_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_mem32_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_mem64_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    },
                    1 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .or_mem8_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .or_mem16_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .or_mem32_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .or_mem64_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_mem8_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_mem16_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_mem32_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_mem64_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0xC0, 0xC1 => {
            // Group 2, count in imm8. /4 = SHL/SAL, /5 = SHR, /7 = SAR.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (reg_field != 4 and reg_field != 5 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                return DecodedInsn{
                    .op = switch (reg_field) {
                        4 => .shl_reg_imm,
                        5 => .shr_reg_imm,
                        else => .sar_reg_imm,
                    },
                    .size = size,
                    .dst_reg = modRmRm(rm, rex),
                    .imm = imm,
                    .len = @intCast(pos),
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = switch (reg_field) {
                4 => .shl_mem_imm,
                5 => .shr_mem_imm,
                else => .sar_mem_imm,
            }, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0xD0, 0xD1 => {
            // Group 2, implicit count 1. /4 = SHL/SAL, /5 = SHR, /7 = SAR.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (reg_field != 4 and reg_field != 5 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                return DecodedInsn{
                    .op = switch (reg_field) {
                        4 => .shl_reg_imm,
                        5 => .shr_reg_imm,
                        else => .sar_reg_imm,
                    },
                    .size = size,
                    .dst_reg = modRmRm(rm, rex),
                    .imm = 1,
                    .len = @intCast(pos),
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = switch (reg_field) {
                4 => .shl_mem_imm,
                5 => .shr_mem_imm,
                else => .sar_mem_imm,
            }, .size = size, .addr = mem.addr, .imm = 1, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0xD3 => {
            // Group 2, count in CL. /4 = SHL/SAL r/m16/32/64, CL.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (reg_field != 4) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                return DecodedInsn{
                    .op = .shl_reg_cl,
                    .size = size,
                    .dst_reg = modRmRm(rm, rex),
                    .len = @intCast(pos),
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = .shl_mem_cl, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0x84, 0x85 => {
            // TEST r/m, r
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            const src_reg = modRmReg(reg, rex);
            if (mod_v != 3) {
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .test_mem8_reg8, .size = size, .src_reg = src_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .test_mem16_reg16, .size = size, .src_reg = src_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .test_mem32_reg32, .size = size, .src_reg = src_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .test_mem64_reg64, .size = size, .src_reg = src_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                };
            }
            const dst_reg = modRmRm(rm, rex);
            return switch (size) {
                .bits8 => DecodedInsn{ .op = .test_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits16 => DecodedInsn{ .op = .test_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .test_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .test_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
            };
        },

        0x87 => {
            // XCHG r/m16/32/64, r16/32/64.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (rex_w) .bits64 else .bits32;
            if (has_66 or mod_v == 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return switch (size) {
                .bits32 => DecodedInsn{ .op = .xchg_mem32_reg32, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .xchg_mem64_reg64, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            };
        },

        0x88, 0x89 => {
            // MOV r/m, r  (88=byte, 89=dword/qword)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            const src_reg = modRmReg(reg, rex);

            if (mod_v == 3) {
                const dst_reg = modRmRm(rm, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_mem8_reg8, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_mem16_reg16, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_mem32_reg32, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_mem64_reg64, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x8A, 0x8B => {
            // MOV r, r/m  (8A=byte, 8B=dword/qword)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            const dst_reg = modRmReg(reg, rex);

            if (mod_v == 3) {
                const src_reg = modRmRm(rm, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_reg8_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_reg16_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_reg32_mem32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_reg64_mem64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x8D => {
            // LEA r, m
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            if (mod_v == 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = .lea_reg_mem, .size = if (rex_w) .bits64 else .bits32, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0x8F => {
            // POP r/m64 (Group 1, /0)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;

            if (reg_field != 0) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                return DecodedInsn{
                    .op = .pop_reg,
                    .size = .bits64,
                    .dst_reg = modRmRm(rm, rex),
                    .len = @intCast(pos),
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = .pop_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0x90 => {
            return DecodedInsn{ .op = .nop, .len = @intCast(pos) };
        },

        0x98 => {
            // CBW/CWDE/CDQE
            if (rex_w) {
                // CDQE (RAX = sign-extend EAX)
                return DecodedInsn{ .op = .cdqe, .len = @intCast(pos) };
            } else if (has_66) {
                // CBW (AX = sign-extend AL)
                return DecodedInsn{ .op = .cbw, .len = @intCast(pos) };
            } else {
                // CWDE (EAX = sign-extend AX)
                return DecodedInsn{ .op = .cwde, .len = @intCast(pos) };
            }
        },

        0x99 => {
            // CWD/CDQ/CQO
            if (rex_w) {
                // CQO (RDX:RAX = sign-extend RAX)
                return DecodedInsn{ .op = .cqo, .len = @intCast(pos) };
            } else if (has_66) {
                // CWD (DX:AX = sign-extend AX)
                return DecodedInsn{ .op = .cwd, .len = @intCast(pos) };
            } else {
                // CDQ (EDX:EAX = sign-extend EAX)
                return DecodedInsn{ .op = .cdq, .len = @intCast(pos) };
            }
        },

        0xA8 => {
            // TEST AL, imm8
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .test_reg8_imm8, .size = .bits8, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) };
        },

        0xB0...0xB7 => {
            // MOV r8, imm8
            const reg = regId(opcode - 0xB0, rexB(rex));
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .mov_reg_imm, .size = .bits8, .dst_reg = reg, .imm = imm, .len = @intCast(pos) };
        },

        0xB8...0xBF => {
            // MOV r, imm32 (with REX.W: imm32 sign-extended)
            const reg_bits = opcode - 0xB8;
            const reg = regId(reg_bits, rexB(rex));
            if (has_66) {
                if (pos + 2 > bytes.len) return .{};
                const imm = std.mem.readInt(u16, bytes[pos..][0..2], .little);
                pos += 2;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits16, .dst_reg = reg, .imm = imm, .len = @intCast(pos) };
            } else if (rex_w) {
                if (pos + 8 > bytes.len) return .{};
                const imm = std.mem.readInt(u64, bytes[pos..][0..8], .little);
                pos += 8;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits64, .dst_reg = reg, .imm = imm, .len = @intCast(pos) };
            } else {
                if (pos + 4 > bytes.len) return .{};
                const imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                pos += 4;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits32, .dst_reg = reg, .imm = imm, .len = @intCast(pos) };
            }
        },

        0xC6 => {
            // MOV r/m8, imm8 (Group 11, /0)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            if (reg_field != 0) return .{};
            if (pos >= bytes.len) return .{};
            if (mod_v == 3) {
                const imm = bytes[pos];
                pos += 1;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits8, .dst_reg = modRmRm(rm, rex), .imm = imm, .len = @intCast(pos) };
            }
            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .mov_mem8_imm8, .size = .bits8, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0xC7 => {
            // MOV r/m, imm32 (Group 11, /0)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;

            if (reg_field != 0) return .{};

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (mod_v == 3) {
                // MOV reg, imm32
                if (pos + 4 > bytes.len) return .{};
                const imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                pos += 4;
                return DecodedInsn{
                    .op = .mov_reg_imm,
                    .size = size,
                    .dst_reg = modRmRm(rm, rex),
                    .imm = if (size == .bits64) @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(imm))))) else imm,
                    .len = @intCast(pos),
                };
            }

            // Memory form
            if (mod_v != 3) {
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                const imm_len: usize = if (size == .bits16) 2 else 4;
                if (pos + imm_len > bytes.len) return .{};
                const imm = if (size == .bits16)
                    @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
                else
                    @as(u64, std.mem.readInt(u32, bytes[pos..][0..4], .little));
                pos += imm_len;
                return switch (size) {
                    .bits16 => DecodedInsn{ .op = .mov_mem16_imm16, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_mem32_imm32, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_mem64_imm32, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0xC3 => {
            // RET near
            return DecodedInsn{ .op = .ret, .len = @intCast(pos) };
        },

        0xE8 => {
            // CALL rel32
            if (pos + 4 > bytes.len) return .{};
            const rel = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            return DecodedInsn{
                .op = .call_rel32,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0xE9 => {
            // JMP rel32
            if (pos + 4 > bytes.len) return .{};
            const rel = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            return DecodedInsn{
                .op = .jmp_rel8,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0xEB => {
            // JMP short rel8
            if (pos >= bytes.len) return .{};
            const rel = std.mem.readInt(i8, bytes[pos..][0..1], .little);
            pos += 1;
            return DecodedInsn{
                .op = .jmp_rel8,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0xF4 => {
            return DecodedInsn{ .op = .hlt, .len = @intCast(pos) };
        },

        0xFF => {
            // Group 5: INC / DEC / CALL / CALLF / JMP / JMPF / PUSH
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (reg_field == 0 or reg_field == 1) {
                const is_inc = reg_field == 0;
                if (mod_v == 3) {
                    const dst_reg = modRmRm(rm, rex);
                    return if (is_inc) switch (size) {
                        .bits8 => DecodedInsn{ .op = .inc_reg8, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .inc_reg16, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .inc_reg32, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .inc_reg64, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                    } else switch (size) {
                        .bits8 => DecodedInsn{ .op = .dec_reg8, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .dec_reg16, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .dec_reg32, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .dec_reg64, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return if (is_inc) switch (size) {
                    .bits8 => DecodedInsn{ .op = .inc_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .inc_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .inc_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .inc_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                } else switch (size) {
                    .bits8 => DecodedInsn{ .op = .dec_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .dec_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .dec_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .dec_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                };
            }

            if (reg_field == 2) {
                if (mod_v == 3) {
                    return DecodedInsn{
                        .op = .call_reg64,
                        .size = .bits64,
                        .src_reg = modRmRm(rm, rex),
                        .len = @intCast(pos),
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return DecodedInsn{ .op = .call_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
            }

            if (reg_field == 4) {
                if (mod_v == 3) {
                    return DecodedInsn{
                        .op = .jmp_reg64,
                        .size = .bits64,
                        .src_reg = modRmRm(rm, rex),
                        .len = @intCast(pos),
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return DecodedInsn{ .op = .jmp_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
            }

            if (reg_field == 6) {
                if (mod_v == 3) {
                    return DecodedInsn{
                        .op = .push_reg,
                        .size = .bits64,
                        .src_reg = modRmRm(rm, rex),
                        .len = @intCast(pos),
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return DecodedInsn{ .op = .push_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0xF6, 0xF7 => {
            // Group 3: TEST / NOT / NEG / MUL / IMUL / DIV / IDIV
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod_v != 3) {
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (reg_field) {
                    0 => {
                        const imm = readGroup3TestImm(bytes, &pos, size) orelse return .{};
                        return switch (size) {
                            .bits8 => DecodedInsn{ .op = .test_mem8_imm8, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                            .bits16 => DecodedInsn{ .op = .test_mem16_imm16, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                            .bits32 => DecodedInsn{ .op = .test_mem32_imm32, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .test_mem64_imm32, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        };
                    },
                    4 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .mul_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .mul_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .mul_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .mul_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    },
                    5 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .imul_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .imul_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .imul_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    },
                    6 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .div_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .div_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .div_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .div_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .idiv_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .idiv_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .idiv_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .idiv_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            } else {
                // Register form: Group 3 with register operand
                const src_reg = modRmRm(rm, rex);
                return switch (reg_field) {
                    0 => {
                        const imm = readGroup3TestImm(bytes, &pos, size) orelse return .{};
                        return switch (size) {
                            .bits8 => DecodedInsn{ .op = .test_reg8_imm8, .size = size, .dst_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                            .bits16 => DecodedInsn{ .op = .test_reg16_imm16, .size = size, .dst_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                            .bits32 => DecodedInsn{ .op = .test_reg32_imm32, .size = size, .dst_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .test_reg64_imm32, .size = size, .dst_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                        };
                    },
                    3 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .neg_reg8, .size = size, .dst_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .neg_reg16, .size = size, .dst_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .neg_reg32, .size = size, .dst_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .neg_reg64, .size = size, .dst_reg = src_reg, .len = @intCast(pos) },
                    },
                    4 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .mul_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .mul_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .mul_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .mul_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    5 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .imul_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .imul_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .imul_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    6 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .div_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .div_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .div_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .div_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .idiv_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .idiv_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .idiv_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .idiv_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }
        },

        0x0F => {
            if (pos >= bytes.len) return .{};
            const op2 = bytes[pos];
            pos += 1;

            switch (op2) {
                0x05 => {
                    return DecodedInsn{ .op = .syscall, .len = @intCast(pos) };
                },
                0x1F => {
                    // Multi-byte NOP: 0F 1F /0, often with 66/2E prefixes.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg_field = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    if (reg_field != 0) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    if (mod_v != 3) {
                        _ = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    }
                    return DecodedInsn{ .op = .nop, .len = @intCast(pos) };
                },
                0x10, 0x11, 0x28, 0x29 => {
                    // MOVUPS/MOVAPS xmm, xmm/m128 or xmm/m128, xmm.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const reg_index = xmmRegIndex(reg, rexR(rex));
                    if (op2 == 0x10 or op2 == 0x28) {
                        if (mod_v == 3) {
                            return DecodedInsn{ .op = .movaps_xmm_xmm, .xmm_dst = reg_index, .xmm_src = xmmRegIndex(rm, rexB(rex)), .len = @intCast(pos) };
                        }
                        const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                        return DecodedInsn{ .op = .movaps_xmm_mem, .addr = mem.addr, .xmm_dst = reg_index, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                    }

                    if (mod_v == 3) {
                        return DecodedInsn{ .op = .movaps_xmm_xmm, .xmm_dst = xmmRegIndex(rm, rexB(rex)), .xmm_src = reg_index, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movaps_mem_xmm, .addr = mem.addr, .xmm_src = reg_index, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0x40...0x4F => {
                    // CMOVcc r16/32/64, r/m16/32/64.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;
                    const dst_reg = modRmReg(reg, rex);
                    const cond: Cond = @enumFromInt(@as(u4, @truncate(op2 & 0x0F)));

                    if (mod_v == 3) {
                        return DecodedInsn{
                            .op = .cmovcc_reg_reg,
                            .size = size,
                            .dst_reg = dst_reg,
                            .src_reg = modRmRm(rm, rex),
                            .cond = cond,
                            .len = @intCast(pos),
                        };
                    }

                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .cmovcc_reg_mem, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .cond = cond, .len = @intCast(pos) };
                },
                0x80...0x8F => {
                    // Jcc rel32
                    if (pos + 4 > bytes.len) return .{};
                    const rel = std.mem.readInt(i32, bytes[pos..][0..4], .little);
                    pos += 4;
                    return DecodedInsn{
                        .op = .jcc_rel8,
                        .cond = @enumFromInt(@as(u4, @truncate(op2 & 0x0F))),
                        .imm = @as(u64, @bitCast(@as(i64, rel))),
                        .len = @intCast(pos),
                    };
                },
                0x90...0x9F => {
                    // SETcc r/m8.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const rm = modrm & 7;
                    const cond: Cond = @enumFromInt(@as(u4, @truncate(op2 & 0x0F)));
                    if (mod_v == 3) {
                        return DecodedInsn{
                            .op = .setcc_reg8,
                            .size = .bits8,
                            .dst_reg = modRmRm(rm, rex),
                            .cond = cond,
                            .len = @intCast(pos),
                        };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .setcc_mem8, .size = .bits8, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .cond = cond, .len = @intCast(pos) };
                },
                0xAF => {
                    // IMUL r, r/m
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;

                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return switch (size) {
                            .bits32 => DecodedInsn{ .op = .imul_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .imul_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                            else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                        };
                    }

                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return switch (size) {
                        .bits32 => DecodedInsn{ .op = .imul_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                },
                0x57 => {
                    // XORPS xmm, xmm/m128. Register form is used as a fast
                    // zeroing idiom: xorps xmm0, xmm0.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    if (mod_v != 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .xorps_xmm_xmm, .xmm_dst = xmmRegIndex(reg, rexR(rex)), .xmm_src = xmmRegIndex(rm, rexB(rex)), .len = @intCast(pos) };
                },
                0xB1 => {
                    // CMPXCHG r/m16/32/64, r16/32/64. Register destination is
                    // not needed yet; the runtime lock path uses memory.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (has_66 or mod_v == 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return switch (size) {
                        .bits32 => DecodedInsn{ .op = .cmpxchg_mem32_reg32, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmpxchg_mem64_reg64, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                },
                0xC1 => {
                    // XADD r/m32/64, r32/64. C++ runtime startup paths often
                    // use LOCK XADDL against RIP-relative guard counters.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (has_66 or mod_v == 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return switch (size) {
                        .bits32 => DecodedInsn{ .op = .xadd_mem32_reg32, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .xadd_mem64_reg64, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                },
                0xB6 => {
                    // MOVZX r32, r/m8
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movzx_reg32_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movzx_reg32_mem8, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0xB7 => {
                    // MOVZX r32, r/m16
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movzx_reg32_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movzx_reg32_mem16, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0xBE => {
                    // MOVSX r32, r/m8
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movsx_reg32_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movsx_reg32_mem8, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0xBF => {
                    // MOVSX r32, r/m16
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movsx_reg32_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movsx_reg32_mem16, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                else => return DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            }
        },

        else => return DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
    }
}

// ─── High-level API ───

pub fn loadAndRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8) !u64 {
    return loadRunElf(allocator, elf_bytes, .{});
}

pub const ElfRunOptions = struct {
    dump_results: bool = false,
    dump_all_results: bool = false,
    source_text: ?[]const u8 = null,
    argv: []const []const u8 = &.{},
};

fn loadRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8, options: ElfRunOptions) !u64 {
    var state = ElfState.init(allocator);
    defer state.deinit();

    try state.loadElf(elf_bytes);

    var local_symbols = elf_loader.collectSymbols(allocator, elf_bytes) catch |err| blk: {
        log.warn("local symbols unavailable: {s}", .{@errorName(err)});
        const empty_symbols: std.ArrayList(elf_loader.Symbol) = .empty;
        break :blk empty_symbols;
    };
    defer local_symbols.deinit(allocator);
    state.local_symbols = local_symbols.items;

    var dynamic_relocations = elf_loader.collectDynamicRelocations(allocator, elf_bytes) catch |err| blk: {
        log.warn("dynamic relocations unavailable: {s}", .{@errorName(err)});
        const empty_relocations: std.ArrayList(elf_loader.DynamicRelocation) = .empty;
        break :blk empty_relocations;
    };
    defer dynamic_relocations.deinit(allocator);
    state.dynamic_relocations = dynamic_relocations.items;

    var init_functions = elf_loader.collectInitArray(allocator, elf_bytes) catch |err| blk: {
        log.warn("ELF init array unavailable: {s}", .{@errorName(err)});
        const empty_init: std.ArrayList(u64) = .empty;
        break :blk empty_init;
    };
    defer init_functions.deinit(allocator);
    state.init_functions = init_functions.items;

    var result_symbols: std.ArrayList(result_dump.DumpSymbol) = .empty;
    defer result_dump.deinitSymbols(allocator, &result_symbols);
    if (options.dump_results) {
        result_symbols = result_dump.collect(allocator, &state, elf_bytes, options.source_text) catch |err| blk: {
            log.warn("result symbols unavailable: {s}", .{@errorName(err)});
            break :blk .empty;
        };
    }

    try x64_linux_runtime.setupInitialStack(&state, options.argv);

    state.run();

    if (options.dump_results) {
        result_dump.dump(allocator, &state, result_symbols.items, .{
            .dump_all_results = options.dump_all_results,
            .source_text = options.source_text,
        }) catch |err| {
            log.warn("result dump skipped: {s}", .{@errorName(err)});
        };
    }

    return state.exit_code;
}

/// CLI entry point: `elf_processor <path-to-elf>`
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        log.err("usage: elf_processor [--dump-results] [--dump-all-results] <elf-path>", .{});
        return;
    }

    var arg_index: usize = 1;
    var dump_results = envFlag("ROSETTE_ELF_DUMP_RESULTS");
    var dump_all_results = envFlag("ROSETTE_ELF_DUMP_ALL") or envFlag("ROSETTE_ELF_DUMP_ALL_RESULTS");
    while (arg_index < args.len and std.mem.startsWith(u8, args[arg_index], "--")) : (arg_index += 1) {
        if (std.mem.eql(u8, args[arg_index], "--dump-results")) {
            dump_results = true;
        } else if (std.mem.eql(u8, args[arg_index], "--dump-all-results")) {
            dump_results = true;
            dump_all_results = true;
        } else {
            log.err("unknown option: {s}", .{args[arg_index]});
            std.process.exit(126);
        }
    }
    if (arg_index >= args.len) {
        log.err("usage: elf_processor [--dump-results] [--dump-all-results] <elf-path>", .{});
        std.process.exit(126);
    }
    const elf_path = args[arg_index];

    const elf_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, elf_path, init.arena.allocator(), .unlimited);
    const source_text = if (dump_results)
        try readSiblingAsmSource(init.io, init.arena.allocator(), elf_path)
    else
        null;

    const exit_code = loadRunElf(init.arena.allocator(), elf_bytes, .{
        .dump_results = dump_results,
        .dump_all_results = dump_all_results,
        .source_text = source_text,
        .argv = args[arg_index..],
    }) catch |err| {
        log.err("failed to run ELF: {s}", .{@errorName(err)});
        std.process.exit(126);
    };

    if (envFlag("ROSETTE_ELF_VERBOSE")) {
        log.info("exit_code={d}", .{exit_code});
    }
    std.process.exit(@as(u8, @truncate(exit_code)));
}

fn envFlag(name: [:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.sliceTo(raw, 0);
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, "0")) return false;
    if (std.ascii.eqlIgnoreCase(value, "false")) return false;
    if (std.ascii.eqlIgnoreCase(value, "no")) return false;
    return true;
}

fn envU64(name: [:0]const u8) ?u64 {
    const raw = std.c.getenv(name) orelse return null;
    return parseEnvU64(std.mem.sliceTo(raw, 0));
}

fn readSiblingAsmSource(io: std.Io, allocator: std.mem.Allocator, elf_path: []const u8) !?[]const u8 {
    const direct = try std.mem.concat(allocator, u8, &.{ elf_path, ".asm" });
    if (std.Io.Dir.cwd().readFileAlloc(io, direct, allocator, .limited(512 * 1024))) |source| return source else |_| {}

    const dir = std.fs.path.dirname(elf_path) orelse ".";
    const base = std.fs.path.basename(elf_path);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
        const stem_path = try std.fs.path.join(allocator, &.{ dir, base[0..dot] });
        const candidate = try std.mem.concat(allocator, u8, &.{ stem_path, ".asm" });
        if (std.Io.Dir.cwd().readFileAlloc(io, candidate, allocator, .limited(512 * 1024))) |source| return source else |_| {}
    }

    return null;
}

// ─── Tests ───

test "decode 0x66 0xB8 (mov ax, imm16)" {
    const bytes = [_]u8{ 0x66, 0xB8, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits16, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
}

test "decode 0xB8 (mov eax, imm32)" {
    const bytes = [_]u8{ 0xB8, 0x78, 0x56, 0x34, 0x12 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(@as(u64, 0x12345678), d.imm);
}

test "decode 0x48 0xB8 (mov rax, imm64)" {
    const bytes = [_]u8{ 0x48, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
}

test "decode 0x8A 0x04 0x25 <addr> (mov al, byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0x8A, 0x04, 0x25, 0x81, 0x26, 0x01, 0x01 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg8_mem8, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(@as(u64, 0x01012681), d.addr);
}

test "decode 0x88 0x04 0x25 <addr> (mov byte [abs], al)" {
    var bytes: [7]u8 = [_]u8{ 0x88, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_mem8_reg8, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);
}

test "decode 0x02 0x04 0x25 (add al, byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0x02, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.add_reg8_mem8, d.op);
}

test "decode 0xF6 0x24 0x25 (mul byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0xF6, 0x24, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_mem8, d.op);
}

test "decode 0xF7 0xE3 (mul ebx)" {
    var bytes: [2]u8 = [_]u8{ 0xF7, 0xE3 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_reg32, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.src_reg);
}

test "decode 0x48 0xF7 0xE3 (mul rbx)" {
    var bytes: [3]u8 = [_]u8{ 0x48, 0xF7, 0xE3 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_reg64, d.op);
}

test "decode 0x99 (cdq)" {
    var bytes: [1]u8 = [_]u8{0x99};
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cdq, d.op);
}

test "decode 0x48 0x99 (cqo)" {
    var bytes: [2]u8 = [_]u8{ 0x48, 0x99 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cqo, d.op);
}

test "decode 0x98 sign-extension variants" {
    try testing.expectEqual(Op.cwde, decodeInsn(&[_]u8{0x98}).op);
    try testing.expectEqual(Op.cbw, decodeInsn(&[_]u8{ 0x66, 0x98 }).op);
    try testing.expectEqual(Op.cdqe, decodeInsn(&[_]u8{ 0x48, 0x98 }).op);
}

test "decode 0x0F 0xB7 (movzx eax, word [abs])" {
    var bytes: [8]u8 = [_]u8{ 0x0F, 0xB7, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movzx_reg32_mem16, d.op);
}

test "decode 0x0F 0xBF (movsx eax, word [abs])" {
    var bytes: [8]u8 = [_]u8{ 0x0F, 0xBF, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movsx_reg32_mem16, d.op);
}

test "decode 0x0F 0x05 (syscall)" {
    var bytes: [2]u8 = [_]u8{ 0x0F, 0x05 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.syscall, d.op);
}

test "execute gettid syscall shim" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = SYS_gettid;
    state.execute(.{ .op = .syscall, .len = 2 });
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expect(!state.terminated);
}

test "decode call ret and extended stack forms" {
    var call_bytes: [5]u8 = [_]u8{ 0xE8, 0x64, 0x01, 0x00, 0x00 };
    var d = decodeInsn(&call_bytes);
    try testing.expectEqual(Op.call_rel32, d.op);
    try testing.expectEqual(@as(u8, 5), d.len);
    try testing.expectEqual(@as(u64, 0x164), d.imm);

    d = decodeInsn(&[_]u8{0xC3});
    try testing.expectEqual(Op.ret, d.op);

    d = decodeInsn(&[_]u8{ 0x41, 0x54 });
    try testing.expectEqual(Op.push_reg, d.op);
    try testing.expectEqual(RegId.r12b_r12w_r12d_r12, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x41, 0x5F });
    try testing.expectEqual(Op.pop_reg, d.op);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.dst_reg);
}

test "decode REX-aware arithmetic and move-extension registers" {
    var d = decodeInsn(&[_]u8{ 0x45, 0x6B, 0xFF, 0x04 });
    try testing.expectEqual(Op.imul_reg32_reg32_imm8, d.op);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.dst_reg);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x41, 0xF7, 0xFD });
    try testing.expectEqual(Op.idiv_reg32, d.op);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x49, 0x0F, 0xAF, 0xC5 });
    try testing.expectEqual(Op.imul_reg64_reg64, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x4C, 0x0F, 0xB6, 0xEE });
    try testing.expectEqual(Op.movzx_reg32_mem8, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.dst_reg);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.src_reg);
    try testing.expect(d.is_reg_form);
}

test "decode and execute shlq cl r14" {
    const d = decodeInsn(&[_]u8{ 0x49, 0xD3, 0xE6 });
    try testing.expectEqual(Op.shl_reg_cl, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r14b_r14w_r14d_r14, d.dst_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.r14b_r14w_r14d_r14, .bits64, 1);
    state.setReg(.cl_cx_ecx_rcx, .bits8, 7);
    state.execute(d);

    try testing.expectEqual(@as(u64, 128), state.regs.r14);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
    try testing.expect((state.regs.rflags & RFL_SF) == 0);
}

test "decode and execute shlq imm r9" {
    const d = decodeInsn(&[_]u8{ 0x49, 0xC1, 0xE1, 0x04 });
    try testing.expectEqual(Op.shl_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r9b_r9w_r9d_r9, d.dst_reg);
    try testing.expectEqual(@as(u64, 4), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.r9b_r9w_r9d_r9, .bits64, 3);
    state.execute(d);

    try testing.expectEqual(@as(u64, 48), state.regs.r9);
}

test "decode and execute shr implicit one ecx" {
    const d = decodeInsn(&[_]u8{ 0xD1, 0xE9 });
    try testing.expectEqual(Op.shr_reg_imm, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.dst_reg);
    try testing.expectEqual(@as(u64, 1), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.cl_cx_ecx_rcx, .bits32, 8);
    state.execute(d);

    try testing.expectEqual(@as(u64, 4), state.regs.rcx);
}

test "decode and execute sarq imm rsi" {
    const d = decodeInsn(&[_]u8{ 0x48, 0xC1, 0xFE, 0x03 });
    try testing.expectEqual(Op.sar_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.dst_reg);
    try testing.expectEqual(@as(u64, 3), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.dh_si_esi_rsi, .bits64, @as(u64, @bitCast(@as(i64, -16))));
    state.execute(d);

    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), state.regs.rsi);
    try testing.expect((state.regs.rflags & RFL_SF) != 0);
}

test "decode and execute adcq imm rbx" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x83, 0xD3, 0x00 });
    try testing.expectEqual(Op.adc_reg64_imm8, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.bl_bx_ebx_rbx, .bits64, 5);
    state.regs.rflags |= RFL_CF;
    state.execute(d);

    try testing.expectEqual(@as(u64, 6), state.regs.rbx);
    try testing.expect((state.regs.rflags & RFL_CF) == 0);
}

test "decode and execute negl esi" {
    const d = decodeInsn(&[_]u8{ 0xF7, 0xDE });
    try testing.expectEqual(Op.neg_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.dst_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.dh_si_esi_rsi, .bits32, 5);
    state.execute(d);

    try testing.expectEqual(@as(u64, 0xFFFF_FFFB), state.regs.rsi);
    try testing.expect((state.regs.rflags & RFL_CF) != 0);
    try testing.expect((state.regs.rflags & RFL_SF) != 0);
}

test "decode and execute cmovae rbx rcx" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x0F, 0x43, 0xD9 });
    try testing.expectEqual(Op.cmovcc_reg_reg, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.src_reg);
    try testing.expectEqual(Cond.ae, d.cond);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.bl_bx_ebx_rbx, .bits64, 0);
    state.setReg(.cl_cx_ecx_rcx, .bits64, 42);
    state.regs.rflags &= ~RFL_CF;
    state.execute(d);
    try testing.expectEqual(@as(u64, 42), state.regs.rbx);
}

test "decode lock add byte rip-relative immediate" {
    const d = decodeInsn(&[_]u8{ 0xF0, 0x80, 0x05, 0x28, 0x14, 0x17, 0x00, 0x01 });
    try testing.expectEqual(Op.add_mem8_imm8, d.op);
    try testing.expectEqual(Size.bits8, d.size);
    try testing.expect(d.rip_relative);
    try testing.expectEqual(@as(u64, 0x171428), d.addr);
    try testing.expectEqual(@as(u64, 1), d.imm);
}

test "decode and execute addb immediate to dl" {
    const d = decodeInsn(&[_]u8{ 0x80, 0xC2, 0x0A });
    try testing.expectEqual(Op.add_reg8_imm8, d.op);
    try testing.expectEqual(Size.bits8, d.size);
    try testing.expectEqual(RegId.dl_dx_edx_rdx, d.dst_reg);
    try testing.expectEqual(@as(u64, 10), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rdx = 0x1234_5605;
    state.execute(d);

    try testing.expectEqual(@as(u64, 0x1234_560f), state.regs.rdx);
}

test "decode and execute orl immediate SIB memory" {
    const d = decodeInsn(&[_]u8{ 0x81, 0x4C, 0x31, 0x08, 0x00, 0x20, 0x00, 0x00 });
    try testing.expectEqual(Op.or_mem32_imm32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expect(d.sib_has_base);
    try testing.expect(d.sib_has_index);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.sib_base_reg);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.sib_index_reg);
    try testing.expectEqual(@as(u64, 8), d.addr);
    try testing.expectEqual(@as(u64, 0x2000), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rcx = 8;
    state.regs.rsi = MEM_BASE;
    var resolved = d;
    state.sibAddr(&resolved);
    state.write32(resolved.addr, 0x40);
    state.execute(resolved);

    try testing.expectEqual(@as(u32, 0x2040), state.read32(resolved.addr));
}

test "decode and execute sbb eax eax carry mask" {
    const d = decodeInsn(&[_]u8{ 0x19, 0xC0 });
    try testing.expectEqual(Op.sbb_reg32_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0;
    state.regs.rflags |= RFL_CF;
    state.execute(d);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.rax);
}

test "decode lock cmpxchg memory and setne memory" {
    var d = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xB1, 0x0D, 0x8C, 0x07, 0x0C, 0x00 });
    try testing.expectEqual(Op.cmpxchg_mem32_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.src_reg);
    try testing.expect(d.rip_relative);

    d = decodeInsn(&[_]u8{ 0x0F, 0x95, 0x45, 0xC8 });
    try testing.expectEqual(Op.setcc_mem8, d.op);
    try testing.expectEqual(Cond.ne, d.cond);
    try testing.expect(d.sib_has_base);
    try testing.expectEqual(RegId.ch_bp_ebp_rbp, d.sib_base_reg);
}

test "execute cmpxchg memory success path" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const addr = MEM_BASE;
    state.write32(addr, 0);
    state.setReg(.al_ax_eax_rax, .bits32, 0);
    state.setReg(.cl_cx_ecx_rcx, .bits32, 1);
    state.execute(.{
        .op = .cmpxchg_mem32_reg32,
        .size = .bits32,
        .src_reg = .cl_cx_ecx_rcx,
        .addr = addr,
    });
    try testing.expectEqual(@as(u32, 1), state.read32(addr));
    try testing.expect((state.regs.rflags & RFL_ZF) != 0);
}

test "decode and execute xchg memory eax" {
    const d = decodeInsn(&[_]u8{ 0x87, 0x07 });
    try testing.expectEqual(Op.xchg_mem32_reg32, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);
    try testing.expect(d.sib_has_base);
    try testing.expectEqual(RegId.bh_di_edi_rdi, d.sib_base_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const addr = MEM_BASE;
    state.write32(addr, 2);
    state.setReg(.al_ax_eax_rax, .bits32, 7);
    state.execute(.{
        .op = .xchg_mem32_reg32,
        .size = .bits32,
        .src_reg = .al_ax_eax_rax,
        .addr = addr,
    });
    try testing.expectEqual(@as(u32, 7), state.read32(addr));
    try testing.expectEqual(@as(u64, 2), state.regs.rax);
}

test "decode and execute lock xadd memory ecx" {
    const d = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xC1, 0x0D, 0x46, 0xAA, 0x0B, 0x00 });
    try testing.expectEqual(Op.xadd_mem32_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.src_reg);
    try testing.expect(d.rip_relative);
    try testing.expectEqual(@as(u64, 0x0BAA46), d.addr);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const addr = MEM_BASE;
    state.write32(addr, 41);
    state.setReg(.cl_cx_ecx_rcx, .bits32, 1);
    state.execute(.{
        .op = .xadd_mem32_reg32,
        .size = .bits32,
        .src_reg = .cl_cx_ecx_rcx,
        .addr = addr,
    });
    try testing.expectEqual(@as(u32, 42), state.read32(addr));
    try testing.expectEqual(@as(u64, 41), state.regs.rcx);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
}

test "decode and execute xorps zero then movaps store" {
    const zero = decodeInsn(&[_]u8{ 0x0F, 0x57, 0xC0 });
    try testing.expectEqual(Op.xorps_xmm_xmm, zero.op);
    try testing.expectEqual(@as(u8, 0), zero.xmm_dst);
    try testing.expectEqual(@as(u8, 0), zero.xmm_src);

    const load_unaligned = decodeInsn(&[_]u8{ 0x0F, 0x10, 0x06 });
    try testing.expectEqual(Op.movaps_xmm_mem, load_unaligned.op);
    try testing.expect(load_unaligned.sib_has_base);
    try testing.expectEqual(RegId.dh_si_esi_rsi, load_unaligned.sib_base_reg);

    const store = decodeInsn(&[_]u8{ 0x0F, 0x29, 0x43, 0x10 });
    try testing.expectEqual(Op.movaps_mem_xmm, store.op);
    try testing.expect(store.sib_has_base);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, store.sib_base_reg);
    try testing.expectEqual(@as(u64, 0x10), store.addr);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.xmm[0] = [_]u8{0xAA} ** 16;
    state.execute(zero);
    state.execute(.{
        .op = .movaps_mem_xmm,
        .addr = MEM_BASE,
        .xmm_src = 0,
    });
    const stored = state.readMem128(MEM_BASE);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), stored[0..]);
}

test "decode 0x48 0x63 0xDB (movsxd rbx, ebx)" {
    var bytes: [3]u8 = [_]u8{ 0x48, 0x63, 0xDB };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movsxd_reg64_reg32, d.op);
}

test "decode movsxd r64 memory SIB form" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x63, 0x04, 0x81 });
    try testing.expectEqual(Op.movsxd_reg64_mem32, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expect(d.sib_has_index);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.sib_index_reg);
    try testing.expect(d.sib_has_base);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.sib_base_reg);
    try testing.expectEqual(@as(u2, 2), d.sib_scale);
}

test "decode 0x48 0xC7 0xC3 (mov rbx, imm32)" {
    var bytes: [7]u8 = [_]u8{ 0x48, 0xC7, 0xC3, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);
}

test "decode 0x66 0x99 (cwd)" {
    var bytes: [2]u8 = [_]u8{ 0x66, 0x99 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cwd, d.op);
}

test "mul byte [mem] and check result" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // Place operands: bNum1=34 at vaddr 0x100267c, bNum3=19 at 0x100267e
    state.write8(0x100267c, 34); // bNum1
    state.write8(0x100267e, 19); // bNum3

    // Set RIP and decode "mov al, byte [bNum1]" + "mul byte [bNum3]" + "mov word [result], ax"
    state.regs.rip = 0x1001160;
    state.regs.rax = 0;

    // Manually execute mov al, [bNum1]
    state.regs.rip = 0x1001160;
    var decoded = decodeInsn(&[_]u8{ 0x8A, 0x04, 0x25, 0x7C, 0x26, 0x00, 0x01 });
    try testing.expectEqual(Op.mov_reg8_mem8, decoded.op);
    state.execute(decoded);
    try testing.expectEqual(@as(u64, 34), state.regs.rax & 0xFF);

    // Execute mul byte [bNum3]
    decoded = decodeInsn(&[_]u8{ 0xF6, 0x24, 0x25, 0x7E, 0x26, 0x00, 0x01 });
    try testing.expectEqual(Op.mul_mem8, decoded.op);
    state.execute(decoded);
    // 34 * 19 = 646 = 0x286
    try testing.expectEqual(@as(u64, 0x286), state.regs.rax & 0xFFFF);
}

test "cmp reg32 imm8 treats negative 32-bit values as signed negative" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, -2588))));
    state.execute(.{
        .op = .cmp_reg32_imm8,
        .dst_reg = .al_ax_eax_rax,
        .imm = 0,
        .len = 3,
    });

    try testing.expect((state.regs.rflags & RFL_SF) != 0);
    try testing.expect((state.regs.rflags & RFL_OF) == 0);
    try testing.expect(ElfState.evalCond(state.regs.rflags, .l));
    try testing.expect(!ElfState.evalCond(state.regs.rflags, .ge));
}
