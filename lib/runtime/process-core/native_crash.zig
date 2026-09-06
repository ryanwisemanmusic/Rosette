//! Native host fault capture for the Mach-O runtime.
//!
//! A fault in the emulator's *own* host code (a bug in Rosette, not in the
//! guest) used to terminate the process with no crash point at all: the default
//! disposition reaps it with `status=128+signal` and whatever the runtime log
//! happened to contain is whatever got written before the fault. The runtime
//! log opens only mid-`loadAndRun`, so a crash before that point (or during
//! `MachOState.init`, which runs before the run loop exists) left nothing to
//! inspect.
//!
//! This module installs `SA_SIGINFO` handlers for the fault signals at the very
//! top of `main()`. The handler is deliberately async-signal-safe — raw
//! `write()` syscalls into a pre-opened crash log and stderr, no allocation, no
//! locks — and captures:
//!
//!   * the signal and faulting address (`siginfo_t.addr`),
//!   * the host register file and program counter from the ucontext,
//!   * a bounded frame-pointer backtrace,
//!   * the last guest progress the interpreter recorded (step, rip, thread,
//!     symbol), so the report says where the *guest* was when the *host*
//!     faulted.
//!
//! After writing the report it restores the default disposition and re-raises,
//! so the exit status remains `128+signal` (139 for SIGSEGV) and supervisors
//! that key on that status keep working.
//!
//! The host is arm64 on Apple Silicon but the same binary can be built for
//! x86_64, so register extraction is comptime-switched on `builtin.cpu.arch`.

const std = @import("std");
const builtin = @import("builtin");

const c = std.c;

/// The crash report file. Opened at install time (normal context) so the
/// handler never has to `open`; kept process-global because the faulting
/// thread is not necessarily the one that installed the handlers.
var crash_fd: c_int = -1;
var crash_path_storage: [1024]u8 = undefined;
var crash_path_len: usize = 0;

var installed: bool = false;
var in_handler: bool = false;

// ---------------------------------------------------------------------------
// Guest progress: what the interpreter was doing when the host faulted.
// ---------------------------------------------------------------------------

const GUEST_SYMBOL_CAP = 96;
const DIAGNOSTIC_TEXT_CAP = 96;
const DIAGNOSTIC_BYTES_CAP = 15;

pub const GuestProgress = struct {
    valid: bool = false,
    step: u64 = 0,
    rip: u64 = 0,
    thread: u64 = 0,
    phase: [32]u8 = undefined,
    phase_len: usize = 0,
    symbol: [GUEST_SYMBOL_CAP]u8 = undefined,
    symbol_len: usize = 0,
};

var guest_progress: GuestProgress = .{};

/// A fail-fast diagnostic is raised from host code, so the signal context's
/// PC is the intentional `raise(SIGSEGV)` rather than the guest boundary that
/// selected the fault. Keep that boundary in a fixed, signal-readable record
/// before raising. The input uses borrowed slices only at the normal-context
/// recording call; `recordTranslationFault` copies every slice into this
/// process-global snapshot.
pub const TranslationFaultInput = struct {
    address: u64,
    step: u64,
    guest_rip: u64,
    guest_thread: u64,
    startup_phase: []const u8 = "",
    startup_phase_start_step: u64 = 0,
    cause: []const u8 = "",
    domain: []const u8 = "",
    source_symbol: []const u8 = "",
    source_symbol_offset: u64 = 0,
    source_op: []const u8 = "",
    source_len: u8 = 0,
    source_bytes: []const u8 = &.{},
    file_offset: u64 = 0,
    file_offset_valid: bool = false,
    initializer_index: u64 = 0,
    initializer_count: u64 = 0,
    initializer_address: u64 = 0,
    initializer_symbol: []const u8 = "",
    initializer_symbol_offset: u64 = 0,
    cache_set: u64 = 0,
    cache_bank_set: u64 = 0,
    cache_set_base: u64 = 0,
    cache_way: u64 = 0,
    cache_ways: u64 = 0,
    code_generation: u64 = 0,
    victim_present: bool = false,
    victim_reused: bool = false,
    stale_rejected: bool = false,
    victim_rip: u64 = 0,
    victim_domain: []const u8 = "",
    victim_code_generation: u64 = 0,
    victim_reuse_count: u64 = 0,
    victim_recently_used: bool = false,
    victim_fast_plain: bool = false,
    victim_host_image: bool = false,
    victim_op: []const u8 = "",
    victim_len: u8 = 0,
    victim_bytes: []const u8 = &.{},
};

const TranslationFault = struct {
    valid: bool = false,
    address: u64 = 0,
    step: u64 = 0,
    guest_rip: u64 = 0,
    guest_thread: u64 = 0,
    startup_phase: [DIAGNOSTIC_TEXT_CAP]u8 = undefined,
    startup_phase_len: usize = 0,
    startup_phase_start_step: u64 = 0,
    cause: [DIAGNOSTIC_TEXT_CAP]u8 = undefined,
    cause_len: usize = 0,
    domain: [DIAGNOSTIC_TEXT_CAP]u8 = undefined,
    domain_len: usize = 0,
    source_symbol: [DIAGNOSTIC_TEXT_CAP]u8 = undefined,
    source_symbol_len: usize = 0,
    source_symbol_offset: u64 = 0,
    source_op: [DIAGNOSTIC_TEXT_CAP]u8 = undefined,
    source_op_len: usize = 0,
    source_len: u8 = 0,
    source_bytes: [DIAGNOSTIC_BYTES_CAP]u8 = [_]u8{0} ** DIAGNOSTIC_BYTES_CAP,
    source_byte_count: u8 = 0,
    file_offset: u64 = 0,
    file_offset_valid: bool = false,
    initializer_index: u64 = 0,
    initializer_count: u64 = 0,
    initializer_address: u64 = 0,
    initializer_symbol: [DIAGNOSTIC_TEXT_CAP]u8 = undefined,
    initializer_symbol_len: usize = 0,
    initializer_symbol_offset: u64 = 0,
    cache_set: u64 = 0,
    cache_bank_set: u64 = 0,
    cache_set_base: u64 = 0,
    cache_way: u64 = 0,
    cache_ways: u64 = 0,
    code_generation: u64 = 0,
    victim_present: bool = false,
    victim_reused: bool = false,
    stale_rejected: bool = false,
    victim_rip: u64 = 0,
    victim_domain: [DIAGNOSTIC_TEXT_CAP]u8 = undefined,
    victim_domain_len: usize = 0,
    victim_code_generation: u64 = 0,
    victim_reuse_count: u64 = 0,
    victim_recently_used: bool = false,
    victim_fast_plain: bool = false,
    victim_host_image: bool = false,
    victim_op: [DIAGNOSTIC_TEXT_CAP]u8 = undefined,
    victim_op_len: usize = 0,
    victim_len: u8 = 0,
    victim_bytes: [DIAGNOSTIC_BYTES_CAP]u8 = [_]u8{0} ** DIAGNOSTIC_BYTES_CAP,
    victim_byte_count: u8 = 0,
};

var translation_fault: TranslationFault = .{};

fn copyDiagnosticText(destination: []u8, length: *usize, source: []const u8) void {
    const count = @min(destination.len, source.len);
    if (count != 0) @memcpy(destination[0..count], source[0..count]);
    length.* = count;
}

fn copyDiagnosticBytes(destination: []u8, count_out: *u8, source: []const u8) void {
    const count = @min(destination.len, source.len);
    if (count != 0) @memcpy(destination[0..count], source[0..count]);
    count_out.* = @intCast(count);
}

/// Save the exact translation boundary before an intentional diagnostic
/// signal. This is deliberately independent of the guest-progress heartbeat:
/// a step-zero initializer failure has no completed guest checkpoint yet.
pub fn recordTranslationFault(input: TranslationFaultInput) void {
    translation_fault.valid = true;
    translation_fault.address = input.address;
    translation_fault.step = input.step;
    translation_fault.guest_rip = input.guest_rip;
    translation_fault.guest_thread = input.guest_thread;
    translation_fault.startup_phase_start_step = input.startup_phase_start_step;
    translation_fault.source_symbol_offset = input.source_symbol_offset;
    translation_fault.source_len = input.source_len;
    translation_fault.file_offset = input.file_offset;
    translation_fault.file_offset_valid = input.file_offset_valid;
    translation_fault.initializer_index = input.initializer_index;
    translation_fault.initializer_count = input.initializer_count;
    translation_fault.initializer_address = input.initializer_address;
    translation_fault.initializer_symbol_offset = input.initializer_symbol_offset;
    translation_fault.cache_set = input.cache_set;
    translation_fault.cache_bank_set = input.cache_bank_set;
    translation_fault.cache_set_base = input.cache_set_base;
    translation_fault.cache_way = input.cache_way;
    translation_fault.cache_ways = input.cache_ways;
    translation_fault.code_generation = input.code_generation;
    translation_fault.victim_present = input.victim_present;
    translation_fault.victim_reused = input.victim_reused;
    translation_fault.stale_rejected = input.stale_rejected;
    translation_fault.victim_rip = input.victim_rip;
    translation_fault.victim_code_generation = input.victim_code_generation;
    translation_fault.victim_reuse_count = input.victim_reuse_count;
    translation_fault.victim_recently_used = input.victim_recently_used;
    translation_fault.victim_fast_plain = input.victim_fast_plain;
    translation_fault.victim_host_image = input.victim_host_image;
    translation_fault.victim_len = input.victim_len;
    copyDiagnosticText(&translation_fault.startup_phase, &translation_fault.startup_phase_len, input.startup_phase);
    copyDiagnosticText(&translation_fault.cause, &translation_fault.cause_len, input.cause);
    copyDiagnosticText(&translation_fault.domain, &translation_fault.domain_len, input.domain);
    copyDiagnosticText(&translation_fault.source_symbol, &translation_fault.source_symbol_len, input.source_symbol);
    copyDiagnosticText(&translation_fault.source_op, &translation_fault.source_op_len, input.source_op);
    copyDiagnosticText(&translation_fault.initializer_symbol, &translation_fault.initializer_symbol_len, input.initializer_symbol);
    copyDiagnosticText(&translation_fault.victim_domain, &translation_fault.victim_domain_len, input.victim_domain);
    copyDiagnosticText(&translation_fault.victim_op, &translation_fault.victim_op_len, input.victim_op);
    copyDiagnosticBytes(&translation_fault.source_bytes, &translation_fault.source_byte_count, input.source_bytes);
    copyDiagnosticBytes(&translation_fault.victim_bytes, &translation_fault.victim_byte_count, input.victim_bytes);
}

/// Called from the interpreter at every progress checkpoint and heartbeat.
/// The symbol slice is copied because it points into guest image memory which
/// may itself be the thing that faulted.
pub fn recordGuestProgress(step: u64, rip: u64, thread: u64, symbol: []const u8) void {
    guest_progress.valid = true;
    guest_progress.step = step;
    guest_progress.rip = rip;
    guest_progress.thread = thread;
    const n = @min(symbol.len, GUEST_SYMBOL_CAP);
    @memcpy(guest_progress.symbol[0..n], symbol[0..n]);
    guest_progress.symbol_len = n;
}

/// Called at phase boundaries (load, logs open, initializers, main enter,
/// run) so a crash before the first checkpoint still names the phase.
pub fn recordPhase(name: []const u8) void {
    guest_progress.valid = true;
    const n = @min(name.len, guest_progress.phase.len);
    @memcpy(guest_progress.phase[0..n], name[0..n]);
    guest_progress.phase_len = n;
}

// ---------------------------------------------------------------------------
// Signal setup
// ---------------------------------------------------------------------------

/// Install handlers for the fault signals. Safe to call once; idempotent
/// afterwards. Must be called before anything that can fault, so the very top
/// of `main()`.
pub fn install() void {
    if (installed) return;
    installed = true;

    openCrashLog();
    // Breadcrumb: proves install ran and which fd is live, in the real binary.
    if (crash_fd >= 0) {
        var b: [192]u8 = undefined;
        const line = std.fmt.bufPrint(&b, "macho-processor: native crash handler install pid={d} fd={d}\n", .{ std.c.getpid(), crash_fd }) catch "";
        _ = std.c.write(crash_fd, line.ptr, line.len);
    }

    const act: c.Sigaction = .{
        .handler = .{ .sigaction = faultHandler },
        .mask = 0,
        .flags = c.SA.SIGINFO,
    };
    const signals = [_]c.SIG{ .SEGV, .BUS, .ILL, .FPE, .ABRT };
    var results: [5]i32 = undefined;
    for (signals, 0..) |sig, i| {
        results[i] = c.sigaction(sig, &act, null);
    }
    if (crash_fd >= 0) {
        var b: [192]u8 = undefined;
        const line = std.fmt.bufPrint(&b, "  sigaction results: segv={d} bus={d} ill={d} fpe={d} abrt={d}\n", .{ results[0], results[1], results[2], results[3], results[4] }) catch "";
        _ = std.c.write(crash_fd, line.ptr, line.len);
    }
    // Diagnostic hook: ROSETTE_TEST_CRASH_HANDLER=1 raises SIGILL right after
    // install so a real run can prove whether the handler is effective in the
    // actual binary at install time.
    if (std.c.getenv("ROSETTE_TEST_CRASH_HANDLER") != null) {
        _ = std.c.raise(std.c.SIG.ILL);
    }
}

fn openCrashLog() void {
    const root = routeRoot() orelse return;
    const path = std.fmt.bufPrintZ(&crash_path_storage, "{s}/.rosette/rosette-crash.log", .{root}) catch return;
    crash_path_len = path.len;
    const directory = std.fs.path.dirname(path) orelse return;
    makePathRecursive(directory) catch return;
    crash_fd = c.open(
        path.ptr,
        c.O{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true, .CLOEXEC = true },
        @as(c_uint, 0o644),
    );
}

fn routeRoot() ?[]const u8 {
    const names = [_][*:0]const u8{
        "ROSETTE_TRACE_ROOT",
        "ROSETTE_ROUTE_ROOT",
        "ROSETTE_CALLER_CWD",
        "PWD",
    };
    for (names) |name| {
        if (std.c.getenv(name)) |value| {
            const span = std.mem.span(value);
            if (span.len != 0) return span;
        }
    }
    return null;
}

fn makePathRecursive(raw_path: []const u8) !void {
    if (raw_path.len == 0) return;
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(std.heap.page_allocator);
    if (raw_path[0] == '/') try current.append(std.heap.page_allocator, '/');
    var parts = std.mem.splitScalar(u8, raw_path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (current.items.len > 1 and current.items[current.items.len - 1] != '/') try current.append(std.heap.page_allocator, '/');
        try current.appendSlice(std.heap.page_allocator, part);
        const path_z = try std.heap.page_allocator.dupeZ(u8, current.items);
        defer std.heap.page_allocator.free(path_z);
        if (c.mkdir(path_z.ptr, 0o755) != 0 and c.access(path_z.ptr, c.F_OK) != 0) {
            return error.MakePathFailed;
        }
    }
}

// ---------------------------------------------------------------------------
// The handler. Async-signal-safe: only write(), no allocation, no locks.
// ---------------------------------------------------------------------------

fn faultHandler(sig: c.SIG, info: *const c.siginfo_t, ctx: ?*anyopaque) callconv(.c) void {
    // Breadcrumb written before anything else can fail: if this line shows up
    // in the crash log, the handler is being entered at all.
    const entered = "macho-processor: NATIVE CRASH HANDLER ENTERED\n";
    if (crash_fd >= 0) _ = std.c.write(crash_fd, entered.ptr, entered.len);
    _ = std.c.write(2, entered.ptr, entered.len);
    // A fault inside the handler (e.g. corrupted frame pointer walk) must not
    // recurse forever: restore default and die immediately.
    if (in_handler) {
        restoreAndReraise(sig);
        return;
    }
    in_handler = true;

    // The host-register dump and a bounded frame chain already consume most of
    // the old 4 KiB report. Strict translation faults now carry the cache
    // victim and source-byte provenance too; keep the report bounded, but do
    // not let that context truncate the crash path.
    var buffer: [8192]u8 = undefined;
    var used: usize = 0;

    addLine(&buffer, &used, "macho-processor: NATIVE HOST CRASH: signal={s}({d}) pid={d}\n", .{
        signalName(sig),
        @intFromEnum(sig),
        std.c.getpid(),
    });
    const fault_addr = @intFromPtr(info.addr);
    addLine(&buffer, &used, "  fault address: 0x{x} code={d}\n", .{ fault_addr, info.code });

    const regs = hostRegisters(ctx) orelse {
        addLine(&buffer, &used, "  (host register extraction failed; ucontext unavailable)\n", .{});
        writeAll(buffer[0..used]);
        restoreAndReraise(sig);
        return;
    };
    regs.dump(&buffer, &used);
    addLine(&buffer, &used, "  backtrace (frame chain):\n", .{});
    const frames = walkBacktrace(regs, &buffer, &used);

    if (translation_fault.valid) {
        addLine(&buffer, &used, "  diagnostic translation fault: address=0x{x} cause={s} domain={s} step={d} source={s}+0x{x} op={s} len={d} file_offset=0x{x} file_offset_valid={}\n", .{
            translation_fault.address,
            translation_fault.cause[0..translation_fault.cause_len],
            translation_fault.domain[0..translation_fault.domain_len],
            translation_fault.step,
            translation_fault.source_symbol[0..translation_fault.source_symbol_len],
            translation_fault.source_symbol_offset,
            translation_fault.source_op[0..translation_fault.source_op_len],
            translation_fault.source_len,
            translation_fault.file_offset,
            translation_fault.file_offset_valid,
        });
        addLine(&buffer, &used, "    startup: phase={s} phase_start_step={d} guest_rip=0x{x} guest_thread=0x{x} initializer={d}/{d} address=0x{x} symbol={s}+0x{x}\n", .{
            translation_fault.startup_phase[0..translation_fault.startup_phase_len],
            translation_fault.startup_phase_start_step,
            translation_fault.guest_rip,
            translation_fault.guest_thread,
            translation_fault.initializer_index,
            translation_fault.initializer_count,
            translation_fault.initializer_address,
            translation_fault.initializer_symbol[0..translation_fault.initializer_symbol_len],
            translation_fault.initializer_symbol_offset,
        });
        addLine(&buffer, &used, "    cache: set(global/bank)={d}/{d} set_base={d} way={d}/{d} generation={d} victim_present={} reused={} stale_rejected={}\n", .{
            translation_fault.cache_set,
            translation_fault.cache_bank_set,
            translation_fault.cache_set_base,
            translation_fault.cache_way,
            translation_fault.cache_ways,
            translation_fault.code_generation,
            translation_fault.victim_present,
            translation_fault.victim_reused,
            translation_fault.stale_rejected,
        });
        addLine(&buffer, &used, "    victim: rip=0x{x} domain={s} generation={d} reuse_count={d} recently_used={} fast_plain={} host_image={} op={s} len={d}\n", .{
            translation_fault.victim_rip,
            if (translation_fault.victim_domain_len != 0) translation_fault.victim_domain[0..translation_fault.victim_domain_len] else "<empty>",
            translation_fault.victim_code_generation,
            translation_fault.victim_reuse_count,
            translation_fault.victim_recently_used,
            translation_fault.victim_fast_plain,
            translation_fault.victim_host_image,
            if (translation_fault.victim_op_len != 0) translation_fault.victim_op[0..translation_fault.victim_op_len] else "<empty>",
            translation_fault.victim_len,
        });
        addLine(&buffer, &used, "    bytes: source={any} victim={any}\n", .{
            translation_fault.source_bytes[0..@as(usize, translation_fault.source_byte_count)],
            translation_fault.victim_bytes[0..@as(usize, translation_fault.victim_byte_count)],
        });
        addLine(&buffer, &used, "  guest progress: phase={s} step={d} rip=0x{x} thread=0x{x} symbol={s} (diagnostic boundary; signal raised before a guest-progress checkpoint)\n", .{
            translation_fault.startup_phase[0..translation_fault.startup_phase_len],
            translation_fault.step,
            translation_fault.guest_rip,
            translation_fault.guest_thread,
            translation_fault.source_symbol[0..translation_fault.source_symbol_len],
        });
    } else if (guest_progress.valid) {
        addLine(&buffer, &used, "  guest progress: phase={s} step={d} rip=0x{x} thread=0x{x} symbol={s}\n", .{
            guest_progress.phase[0..guest_progress.phase_len],
            guest_progress.step,
            guest_progress.rip,
            guest_progress.thread,
            guest_progress.symbol[0..guest_progress.symbol_len],
        });
    } else {
        addLine(&buffer, &used, "  guest progress: none recorded (crash before first checkpoint)\n", .{});
    }
    addLine(&buffer, &used, "  crash report: {s} (frames={d})\n", .{ crashPath(), frames });
    writeAll(buffer[0..used]);

    restoreAndReraise(sig);
}

/// Append one formatted line to a report buffer. Top-level (not a closure)
/// so it can be shared by the handler, the register dump and the backtrace
/// walk without nested-function scoping issues.
fn addLine(buffer: []u8, used: *usize, comptime fmt: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(buffer[used.*..], fmt, args) catch return;
    used.* += text.len;
}

fn writeAll(bytes: []const u8) void {
    if (crash_fd >= 0) {
        var written: usize = 0;
        while (written < bytes.len) {
            const result = std.c.write(crash_fd, bytes.ptr + written, bytes.len - written);
            if (result <= 0) break;
            written += @intCast(result);
        }
    }
    // stderr may itself be the runtime log (Controller.init dup2's it), so
    // this lands in the terminal diagnostics the router captures either way.
    var written: usize = 0;
    while (written < bytes.len) {
        const result = std.c.write(2, bytes.ptr + written, bytes.len - written);
        if (result <= 0) break;
        written += @intCast(result);
    }
}

fn restoreAndReraise(sig: c.SIG) void {
    // Restore default disposition, then re-raise so the process dies with the
    // signal-compatible status (139 for SIGSEGV) supervisors already key on.
    const def: c.Sigaction = .{
        .handler = .{ .handler = c.SIG.DFL },
        .mask = 0,
        .flags = 0,
    };
    _ = c.sigaction(sig, &def, null);
    _ = c.raise(sig);
    // Fallback: if re-raise somehow returns, exit with the same status.
    c._exit(128 + @as(u8, @intCast(@intFromEnum(sig))));
}

fn crashPath() []const u8 {
    return crash_path_storage[0..crash_path_len];
}

fn signalName(sig: c.SIG) []const u8 {
    return switch (sig) {
        .SEGV => "SIGSEGV",
        .BUS => "SIGBUS",
        .ILL => "SIGILL",
        .FPE => "SIGFPE",
        .ABRT => "SIGABRT",
        else => "SIG?",
    };
}

// ---------------------------------------------------------------------------
// Host register extraction from the Darwin ucontext.
//
// Layouts are from the macOS SDK headers (Mach-O 64-bit host):
//   ucontext_t: uc_mcontext at byte 48.
//   arm64  mcontext64: __es {far,esr,exception} at 0, __ss at 16,
//                      __ss = x[29] + fp + lr + sp + pc + cpsr + pad.
//   x86_64 mcontext64: __es {trapno,err,faultvaddr} at 0, __ss at 16,
//                      __ss = 21 x u64 (rax..rip..gs).
// ---------------------------------------------------------------------------

const HostRegisters = struct {
    pc: u64,
    sp: u64,
    fp: u64,
    // Named registers, for the dump. arm64: x0..x28; x86_64: rax..r15.
    named: [29]u64 = undefined,
    named_count: usize = 0,
    named_names: [29][3]u8 = undefined,

    fn dump(self: *const HostRegisters, buffer: []u8, used: *usize) void {
        addLine(buffer, used, "  host regs: pc=0x{x} sp=0x{x} fp=0x{x}\n", .{ self.pc, self.sp, self.fp });
        if (builtin.cpu.arch == .aarch64) {
            var i: usize = 0;
            while (i < self.named_count) : (i += 1) {
                addLine(buffer, used, "    x{d:<2} = 0x{x:0>16}\n", .{ i, self.named[i] });
            }
        } else {
            var i: usize = 0;
            while (i < self.named_count) : (i += 1) {
                addLine(buffer, used, "    {s} = 0x{x:0>16}\n", .{ self.named_names[i], self.named[i] });
            }
        }
    }
};

fn hostRegisters(ctx: ?*anyopaque) ?HostRegisters {
    const uctx = ctx orelse return null;
    const uctx_bytes = @as([*]const u8, @ptrCast(uctx));
    const mcontext = readU64(uctx_bytes + 48) orelse return null;
    if (mcontext == 0) return null;
    const mc = @as([*]const u8, @ptrFromInt(mcontext));

    if (builtin.cpu.arch == .aarch64) {
        // __es at 0 (16 bytes), __ss at 16.
        const ss = mc + 16;
        var regs = HostRegisters{
            .pc = readU64(ss + 256) orelse 0,
            .sp = readU64(ss + 248) orelse 0,
            .fp = readU64(ss + 232) orelse 0,
        };
        regs.named_count = 29;
        var i: usize = 0;
        while (i < 29) : (i += 1) {
            regs.named[i] = readU64(ss + @as(usize, i) * 8) orelse 0;
        }
        return regs;
    }
    if (builtin.cpu.arch == .x86_64) {
        const ss = mc + 16;
        var regs = HostRegisters{
            .pc = readU64(ss + 128) orelse 0,
            .sp = readU64(ss + 56) orelse 0,
            .fp = readU64(ss + 48) orelse 0,
        };
        const names = [_][3]u8{
            "rax", "rbx", "rcx", "rdx", "rdi", "rsi",
            "r8",  "r9",  "r10", "r11", "r12", "r13",
            "r14", "r15",
        };
        regs.named_count = names.len;
        @memcpy(regs.named_names[0..names.len], &names);
        const offsets = [_]usize{ 0, 8, 16, 24, 32, 40, 64, 72, 80, 88, 96, 104, 112, 120 };
        var i: usize = 0;
        while (i < offsets.len) : (i += 1) {
            regs.named[i] = readU64(ss + offsets[i]) orelse 0;
        }
        return regs;
    }
    return null;
}

fn readU64(bytes: [*]const u8) ?u64 {
    return std.mem.readInt(u64, bytes[0..8], .little);
}

/// Walk the frame-pointer chain. `fp` and `pc` come from the ucontext; each
/// frame reads `[fp]` (previous fp) and `[fp+8]` (return address). Guarded so
/// a corrupted fp cannot re-fault inside the handler: the target must be
/// 16-byte aligned (AAPCS64), lie within a plausible stack window above sp,
/// and the page must be resident (checked with mincore).
const MAX_FRAMES = 24;
const MAX_STACK_WINDOW: u64 = 64 * 1024 * 1024;

fn walkBacktrace(regs: HostRegisters, buffer: []u8, used: *usize) usize {
    var frame_count: usize = 0;
    addLine(buffer, used, "    #0  pc=0x{x} sp=0x{x} fp=0x{x}\n", .{ regs.pc, regs.sp, regs.fp });
    frame_count += 1;

    var fp = regs.fp;
    var sp = regs.sp;
    var depth: usize = 1;
    while (depth < MAX_FRAMES) : (depth += 1) {
        if (fp == 0) break;
        if (fp & 0xF != 0) break;
        if (fp < sp or fp - sp > MAX_STACK_WINDOW) break;
        if (!pageResident(fp)) break;

        const prev_fp = readU64(@as([*]const u8, @ptrFromInt(fp))) orelse break;
        const ret = readU64(@as([*]const u8, @ptrFromInt(fp + 8))) orelse break;
        if (prev_fp != 0 and prev_fp <= fp) break; // frames must ascend
        addLine(buffer, used, "    #{d}  ret=0x{x} prev_fp=0x{x}\n", .{ depth, ret, prev_fp });
        frame_count += 1;
        if (ret == 0 and prev_fp == 0) break;
        fp = prev_fp;
        // Refine sp window so the next frame is above this one.
        sp = fp;
    }
    return frame_count;
}

/// Whether the page containing `addr` is resident (mincore, a syscall — safe
/// in a signal handler). Prevents a dereference of unmapped memory inside the
/// handler from faulting a second time.
fn pageResident(addr: u64) bool {
    const page = std.heap.page_size_min;
    const aligned = addr & ~@as(u64, @intCast(page - 1));
    var vec: [1]u8 = undefined;
    const ptr: *align(page) anyopaque = @ptrFromInt(aligned);
    const result = std.c.mincore(ptr, page, @as([*]u8, @ptrCast(&vec)));
    if (result != 0) return false;
    return vec[0] & 1 != 0;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "signal names are stable" {
    try std.testing.expectEqualStrings("SIGSEGV", signalName(.SEGV));
    try std.testing.expectEqualStrings("SIGBUS", signalName(.BUS));
    try std.testing.expectEqualStrings("SIGILL", signalName(.ILL));
    try std.testing.expectEqualStrings("SIGFPE", signalName(.FPE));
    try std.testing.expectEqualStrings("SIGABRT", signalName(.ABRT));
}

test "guest progress records and clamps symbol" {
    var long = [_]u8{'a'} ** 300;
    recordGuestProgress(123, 0x1000, 0x7fff2000, &long);
    try std.testing.expect(guest_progress.valid);
    try std.testing.expectEqual(@as(u64, 123), guest_progress.step);
    try std.testing.expectEqual(@as(u64, 0x1000), guest_progress.rip);
    try std.testing.expectEqual(GUEST_SYMBOL_CAP, guest_progress.symbol_len);
    recordPhase("static_init");
    try std.testing.expectEqualStrings("static_init", guest_progress.phase[0..guest_progress.phase_len]);
}

test "readU64 is little endian" {
    var bytes = [_]u8{ 0x34, 0x12, 0, 0, 0, 0, 0, 0 };
    try std.testing.expectEqual(@as(u64, 0x1234), readU64(&bytes).?);
}

test "hostRegisters parses a synthetic aarch64 ucontext" {
    if (builtin.cpu.arch != .aarch64) return error.SkipZigTest;
    var uctx: [56]u8 = [_]u8{0} ** 56;
    var mcontext: [512]u8 = [_]u8{0} ** 512;
    // ucontext.uc_mcontext at byte 48.
    std.mem.writeInt(u64, uctx[48..56], @intFromPtr(&mcontext), .little);
    // mcontext.__ss at 16; pc at +256, sp at +248, fp at +232, x0 at +0.
    std.mem.writeInt(u64, mcontext[16 + 256 ..][0..8], 0x1_0000_4000, .little);
    std.mem.writeInt(u64, mcontext[16 + 248 ..][0..8], 0x7fff_f000, .little);
    std.mem.writeInt(u64, mcontext[16 + 232 ..][0..8], 0x7fff_f100, .little);
    std.mem.writeInt(u64, mcontext[16..][0..8], 0xaaaa, .little);
    const regs = hostRegisters(&uctx).?;
    try std.testing.expectEqual(@as(u64, 0x1_0000_4000), regs.pc);
    try std.testing.expectEqual(@as(u64, 0x7fff_f000), regs.sp);
    try std.testing.expectEqual(@as(u64, 0x7fff_f100), regs.fp);
    try std.testing.expectEqual(@as(u64, 0xaaaa), regs.named[0]);
    try std.testing.expectEqual(@as(usize, 29), regs.named_count);
}

test "walkBacktrace terminates on a frame chain" {
    // A synthetic frame chain: fp -> [fp] = prev_fp, [fp+8] = return address.
    var frames: [2]u64 = [_]u64{0} ** 2;
    const base = @intFromPtr(&frames);
    frames[0] = 0; // prev fp = 0 terminates
    frames[1] = 0x2000; // return address
    const regs = HostRegisters{
        .pc = 0x1000,
        .sp = base,
        .fp = base,
    };
    var buffer: [4096]u8 = undefined;
    var used: usize = 0;
    const count = walkBacktrace(regs, &buffer, &used);
    try std.testing.expect(count >= 2);
}
