const std = @import("std");
const x64_syscalls = @import("x64_syscalls");
const x64_interactive_bridge = @import("interactive_bridge.zig");
const windows_runtime = @import("windows_runtime");

/// Return the architectural register file belonging to this host executor's
/// bound guest context, or the traditional owner register file when the
/// caller uses a standalone state value.
fn guestRegs(state: anytype) if (@typeInfo(@TypeOf(state)).pointer.is_const)
    *const @FieldType(@TypeOf(state.*), "regs")
else
    *@FieldType(@TypeOf(state.*), "regs") {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "windowsGuestContextField")) return state.windowsGuestContextField("regs");
    return &@field(state.*, "regs");
}

pub const SYNTHETIC_PTHREAD_ONCE_RETURN = windows_runtime.SYNTHETIC_PTHREAD_ONCE_RETURN;
pub const SYNTHETIC_INITTERM_RETURN = windows_runtime.SYNTHETIC_INITTERM_RETURN;
pub const SYNTHETIC_QSORT_RETURN = windows_runtime.SYNTHETIC_QSORT_RETURN;

// The Windows import fallback contract, re-exported for the PE state that
// owns the ledger.  Routing it through this module keeps the executor's
// module graph unchanged: it already depends on the Linux/Windows runtime
// seam and does not need a direct edge to the Win32 ABI surface.
pub const ImportReturnConvention = windows_runtime.ImportReturnConvention;
pub const ImportFallback = windows_runtime.ImportFallback;
pub const ImportFallbackLedger = windows_runtime.ImportFallbackLedger;
pub const importFallbackFor = windows_runtime.importFallbackFor;
pub const importFallbackAdvice = windows_runtime.importFallbackAdvice;
pub const isDeliberateExportRefusal = windows_runtime.isDeliberateExportRefusal;
pub const ImportAnswerCache = windows_runtime.ImportAnswerCache;
pub const importValueIsRefusal = windows_runtime.importValueIsRefusal;
pub const importRefusalIsHard = windows_runtime.importRefusalIsHard;
pub const importConventionIsDecisive = windows_runtime.importConventionIsDecisive;
pub const importCapabilityGapFor = windows_runtime.importCapabilityGapFor;
pub const isCapabilityGap = windows_runtime.isCapabilityGap;
pub const ImportJudgement = windows_runtime.ImportJudgement;
pub const ImportSubsystem = windows_runtime.ImportSubsystem;
pub const importSubsystemFor = windows_runtime.importSubsystemFor;
pub const importSubsystemForImport = windows_runtime.importSubsystemForImport;
/// Re-exported so the execution state can assert the module-name and
/// availability rules without importing the Windows dispatcher directly; the
/// state already reaches this module for the import contract.
pub const windowsModuleNameLooksReadable = windows_runtime.windowsModuleNameLooksReadable;
pub const windowsModuleAvailability = windows_runtime.windowsModuleAvailability;
pub const windowsModuleFallback = windows_runtime.windowsModuleFallback;
pub const windowsModuleUnavailableOnHost = windows_runtime.windowsModuleUnavailableOnHost;
pub const isRecognizedDynamicImport = windows_runtime.isRecognizedDynamicImport;

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
        if (state.guestMemory(sp, @intCast(arg.len + 1)) == null) return error.StackOutOfRange;
        if (!state.copyToGuest(sp, arg)) return error.StackOutOfRange;
        state.write8(sp +| @as(u64, @intCast(arg.len)), 0);
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
    guestRegs(state).*.rsp = sp;
}

pub fn tryLibcStartMainTrampoline(state: anytype, d: anytype, return_rip: u64) bool {
    if (state.libc_start_main_trampolined) return false;
    if (!d.rip_relative) return false;

    const main_addr = guestRegs(state).*.rdi;
    if (main_addr == 0 or state.addrToOffset(main_addr) == null) return false;

    const first = state.read8(main_addr);
    if (first != 0x55 and first != 0x48 and first != 0xF3) return false;

    const argc = guestRegs(state).*.rsi;
    const argv = guestRegs(state).*.rdx;
    _ = return_rip;
    state.startLibcMain(main_addr, argc, argv);
    std.log.scoped(.x64_linux_runtime).info("bridged unresolved __libc_start_main to main=0x{x} argc={d} init_count={d}", .{
        main_addr,
        argc,
        state.init_functions.len,
    });
    return true;
}

pub fn tryDynamicFunctionShim(state: anytype, got_addr: u64, direct_return_rip: ?u64) bool {
    // PE32+ indirect jumps include ordinary C++ vtable dispatch.  They do
    // not carry the ELF PLT resolver's relocation index on the guest stack;
    // letting the fallback below inspect rsp+8 would reinterpret an
    // unrelated vtable call as a random lazy import (for example, turning a
    // shared_ptr release jump into CreateFileMappingW).  A Windows IAT miss
    // must continue through the normal target read instead.
    const windows_mode = if (comptime @hasField(@TypeOf(state.*), "windows_runtime_enabled"))
        state.windows_runtime_enabled
    else
        false;
    const relocation = dynamicRelocation(state, got_addr) orelse {
        if (windows_mode or direct_return_rip != null) return false;
        const resolver_name = dynamicPltResolverRelocationName(state) orelse return false;
        const old_rsp = guestRegs(state).*.rsp;
        guestRegs(state).*.rsp +%= 16;
        if (tryNamedFunctionShim(state, resolver_name, null)) return true;
        guestRegs(state).*.rsp = old_rsp;
        if (tryWindowsLazyImport(state, resolver_name)) return true;
        std.log.scoped(.x64_linux_runtime).warn("unsupported lazy PLT symbol {s}", .{resolver_name});
        return false;
    };
    const name = relocation.name;
    // PE32+ calls use the Microsoft x64 register ABI (RCX/RDX/R8/R9), while
    // these historical named shims are SysV-only (RDI/RSI/RDX/RCX/R8/R9).
    // Running a Windows import such as calloc through the SysV branch reads
    // unrelated guest registers as its count/element size and can turn a
    // small allocation into a bogus multi-gigabyte request before the
    // Windows bridge gets a chance to handle it. Once the PE state enables
    // the Windows runtime, route the import directly to that bridge.
    if (!windows_mode and tryNamedFunctionShim(state, name, direct_return_rip)) return true;
    if (tryWindowsFunction(state, relocation.dll_name, name, direct_return_rip)) return true;
    if (symbolNameEql(name, "__libc_start_main")) return false;
    std.log.scoped(.x64_linux_runtime).warn("unsupported PLT symbol {s}", .{name});
    return false;
}

/// Route a PE proc-address target through the same Windows ABI surface used by
/// import-table calls. Keeping this wrapper here lets the ELF state own all
/// x86-64 call/return bookkeeping while the Windows layer remains reusable by
/// the static preflight and indirect-stub path.
pub fn tryWindowsFunction(state: anytype, dll_name: []const u8, name: []const u8, direct_return_rip: ?u64) bool {
    return windows_runtime.tryFunction(state, dll_name, name, direct_return_rip);
}

/// Probe only the narrow Windows imports that are safe before acquiring the
/// runtime-table lock. The caller must still prove that its target is a
/// direct static import stub.
pub fn tryWindowsFastFunction(state: anytype, dll_name: []const u8, name: []const u8, direct_return_rip: ?u64) bool {
    return windows_runtime.tryWindowsFastFunction(state, dll_name, name, direct_return_rip);
}

/// Complete a Rosetta-owned semantic compatibility boundary for a Windows
/// guest before its first instruction executes. This stays alongside the
/// Windows ABI bridge so the ELF executor only owns the architectural return
/// bookkeeping.
pub fn tryWindowsGuestCompatibility(state: anytype) bool {
    return windows_runtime.tryGuestCompatibility(state);
}

pub fn tryLocalFunctionShim(state: anytype, target: u64, direct_return_rip: u64) bool {
    const name = state.localSymbolNameAt(target) orelse return false;
    const bridge_match = x64_interactive_bridge.enabled() and x64_interactive_bridge.recognizesLocalFunction(name);
    const locale_match = symbolNameEql(name, "_ZNKSt3__16locale9use_facetERNS0_2idE");
    if (!bridge_match and !locale_match) return false;

    const State = @TypeOf(state.*);
    if (comptime @hasField(State, "parallel_guest_execution") and @hasDecl(State, "lockWindowsRuntime")) {
        if (state.parallel_guest_execution) {
            // A dispatch level: it only routes into the shim's handler.
            var runtime_guard = if (comptime @hasDecl(State, "lockWindowsRuntimeForDispatch"))
                state.lockWindowsRuntimeForDispatch()
            else
                state.lockWindowsRuntime();
            defer runtime_guard.unlock();
            return tryLocalFunctionShimResolved(state, name, direct_return_rip, bridge_match, locale_match);
        }
    }
    return tryLocalFunctionShimResolved(state, name, direct_return_rip, bridge_match, locale_match);
}

fn tryLocalFunctionShimResolved(
    state: anytype,
    name: []const u8,
    direct_return_rip: u64,
    bridge_match: bool,
    locale_match: bool,
) bool {
    if (bridge_match and x64_interactive_bridge.tryLocalFunctionBridge(state, name, direct_return_rip)) return true;
    if (!locale_match) return false;
    const facet = resolveLocaleFacet(state) orelse return false;
    guestRegs(state).*.rax = facet;
    finishExternalReturn(state, direct_return_rip);
    return true;
}

fn tryNamedFunctionShim(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (symbolNameEql(name, "remove")) {
        var path_storage: [4096]u8 = undefined;
        const path = state.copyGuestCString(guestRegs(state).*.rdi, path_storage.len + 1, path_storage[0..]) orelse 0;
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        std.log.scoped(.x64_linux_runtime).info("shimmed remove({s}) as no-op", .{path_storage[0..path]});
        return true;
    }
    if (symbolNameEql(name, "exit") or symbolNameEql(name, "_exit")) {
        state.exit_code = guestRegs(state).*.rdi;
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
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "aligned_alloc")) {
        const alignment = guestRegs(state).*.rdi;
        const size = guestRegs(state).*.rsi;
        guestRegs(state).*.rax = state.guestAlloc(size, alignment) orelse 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "malloc") or
        symbolNameEql(name, "_Znwm") or
        symbolNameEql(name, "_Znam"))
    {
        guestRegs(state).*.rax = state.guestAlloc(guestRegs(state).*.rdi, 16) orelse 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "calloc")) {
        const count = guestRegs(state).*.rdi;
        const elem_size = guestRegs(state).*.rsi;
        const total = std.math.mul(u64, count, elem_size) catch {
            guestRegs(state).*.rax = 0;
            finishExternalReturn(state, direct_return_rip);
            return true;
        };
        guestRegs(state).*.rax = state.guestAlloc(total, 16) orelse 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "free") or
        symbolNameEql(name, "_ZdlPv") or
        symbolNameEql(name, "_ZdaPv") or
        symbolNameEql(name, "_ZdlPvm") or
        symbolNameEql(name, "_ZdaPvm"))
    {
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "dlsym") or
        symbolNameEql(name, "dlopen") or
        symbolNameEql(name, "dlerror") or
        symbolNameEql(name, "dl_iterate_phdr"))
    {
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "dlclose")) {
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "newlocale")) {
        guestRegs(state).*.rax = state.guestAlloc(16, 8) orelse 1;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "uselocale")) {
        guestRegs(state).*.rax = 1;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "freelocale")) {
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "setlocale")) {
        guestRegs(state).*.rax = guestStringLiteral(state, "C");
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "localeconv")) {
        guestRegs(state).*.rax = guestLocaleConv(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "pthread_mutex_lock") or
        symbolNameEql(name, "pthread_mutex_unlock") or
        symbolNameEql(name, "pthread_mutex_trylock") or
        symbolNameEql(name, "pthread_attr_init") or
        symbolNameEql(name, "pthread_cond_broadcast") or
        symbolNameEql(name, "pthread_cond_signal") or
        symbolNameEql(name, "pthread_rwlock_rdlock") or
        symbolNameEql(name, "pthread_rwlock_wrlock") or
        symbolNameEql(name, "pthread_rwlock_unlock"))
    {
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "isatty")) {
        const fd = guestRegs(state).*.rdi;
        guestRegs(state).*.rax = if (fd <= 2) 1 else 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "write")) {
        handleWriteShim(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "__ctype_get_mb_cur_max")) {
        guestRegs(state).*.rax = 1;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "mbtowc") or symbolNameEql(name, "mbrtowc")) {
        handleMbrtowcShim(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "btowc")) {
        const ch = guestRegs(state).*.rdi & 0xFF;
        guestRegs(state).*.rax = if (ch == 0xFF) 0xFFFF_FFFF else ch;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "wctob")) {
        const wc = guestRegs(state).*.rdi;
        guestRegs(state).*.rax = if (wc <= 0x7F) wc else 0xFFFF_FFFF;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "wcrtomb")) {
        handleWcrtombShim(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "iswcntrl_l")) {
        const wc = guestRegs(state).*.rdi;
        guestRegs(state).*.rax = if (wc < 0x20 or wc == 0x7F) 1 else 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "towlower_l") or symbolNameEql(name, "towupper_l")) {
        var wc = guestRegs(state).*.rdi;
        if (symbolNameEql(name, "towlower_l") and wc >= 'A' and wc <= 'Z') wc += 32;
        if (symbolNameEql(name, "towupper_l") and wc >= 'a' and wc <= 'z') wc -= 32;
        guestRegs(state).*.rax = wc;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "memchr")) {
        handleMemchrShim(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "strcmp") or symbolNameEql(name, "strcoll_l")) {
        guestRegs(state).*.rax = @bitCast(@as(i64, guestStrcmp(state, guestRegs(state).*.rdi, guestRegs(state).*.rsi)));
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "syscall")) {
        state.invokeLinuxSyscall(
            guestRegs(state).*.rdi,
            guestRegs(state).*.rsi,
            guestRegs(state).*.rdx,
            guestRegs(state).*.rcx,
            guestRegs(state).*.r8,
            guestRegs(state).*.r9,
            state.read64(guestRegs(state).*.rsp + 8),
        );
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "pthread_attr_destroy") or
        symbolNameEql(name, "pthread_attr_setguardsize") or
        symbolNameEql(name, "pthread_attr_setstacksize") or
        symbolNameEql(name, "pthread_cond_wait") or
        symbolNameEql(name, "pthread_create") or
        symbolNameEql(name, "pthread_detach") or
        symbolNameEql(name, "pthread_kill"))
    {
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "pthread_self")) {
        guestRegs(state).*.rax = 1;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "fwrite") or symbolNameEql(name, "fwrite_unlocked")) {
        const size = guestRegs(state).*.rsi;
        const count = guestRegs(state).*.rdx;
        guestRegs(state).*.rax = if (size == 0) 0 else count;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "fputc") or
        symbolNameEql(name, "putc") or
        symbolNameEql(name, "putchar"))
    {
        guestRegs(state).*.rax = guestRegs(state).*.rdi & 0xFF;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "fputs") or symbolNameEql(name, "puts")) {
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "fflush")) {
        guestRegs(state).*.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "printf") or
        symbolNameEql(name, "fprintf") or
        symbolNameEql(name, "vfprintf") or
        symbolNameEql(name, "snprintf") or
        symbolNameEql(name, "vsnprintf"))
    {
        guestRegs(state).*.rax = 0;
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
    const relocation_index = state.read64(guestRegs(state).*.rsp + 8);
    var jump_slot_index: u64 = 0;
    for (state.dynamic_relocations) |reloc| {
        if (reloc.rel_type != 7) continue; // R_X86_64_JUMP_SLOT
        if (jump_slot_index == relocation_index) return reloc.name;
        jump_slot_index += 1;
    }
    return null;
}

fn tryWindowsLazyImport(state: anytype, name: []const u8) bool {
    const windows_mode = if (comptime @hasField(@TypeOf(state.*), "windows_runtime_enabled"))
        state.windows_runtime_enabled
    else
        false;
    if (!windows_mode or name.len == 0) return false;

    // A PE import thunk does not carry the ELF relocation's DLL alongside the
    // resolver index. Try the small set of ABI namespaces used by the Windows
    // runner, in order from the broad core namespace to the graphics ones. The
    // classifier remains authoritative: an unknown name is not made runnable
    // merely because it passed through this fallback.
    const candidate_dlls = [_][]const u8{
        "kernel32.dll",
        "gdi32.dll",
        "user32.dll",
        "vulkan-1.dll",
        "dxgi.dll",
    };
    for (candidate_dlls) |dll_name| {
        if (!windows_runtime.isSupportedImport(dll_name, name)) continue;
        if (tryWindowsFunction(state, dll_name, name, null)) return true;
    }
    return false;
}

/// Bounded call-site cache for indirect import lookup. PE games repeatedly
/// call through the same IAT slots; scanning every relocation for each
/// `call [mem]` made the import bridge pay O(import_count) on its hot path.
/// The cache is owned by the emulation state, so multiple guests do not share
/// mutable lookup state. A full address key makes direct-map collisions safe,
/// and misses are remembered too because ordinary vtable calls are common.
pub const DynamicRelocationLookup = struct {
    const entry_count = 256;
    const no_relocation = std.math.maxInt(u32);

    const Entry = struct {
        address: u64 = 0,
        index: u32 = no_relocation,
        valid: bool = false,
    };

    entries: [entry_count]Entry = [_]Entry{.{}} ** entry_count,

    pub fn clear(self: *DynamicRelocationLookup) void {
        @memset(self.entries[0..], .{});
    }

    fn slotFor(address: u64) usize {
        const mixed = (address >> 3) *% 0x9E37_79B9_7F4A_7C15;
        return @intCast(mixed & (entry_count - 1));
    }

    pub fn lookup(self: *DynamicRelocationLookup, relocations: anytype, address: u64) ?*const @TypeOf(relocations[0]) {
        if (relocations.len == 0) return null;

        const entry = &self.entries[slotFor(address)];
        if (entry.valid and entry.address == address) {
            if (entry.index == no_relocation) return null;
            const index: usize = @intCast(entry.index);
            if (index < relocations.len and relocations[index].offset == address) {
                return &relocations[index];
            }
            // The relocation slice can be replaced by another load. A stale
            // index is never trusted; fall through to the authoritative scan.
            entry.valid = false;
        }

        for (relocations, 0..) |*relocation, index| {
            if (relocation.offset != address) continue;
            if (index < @as(usize, no_relocation)) {
                entry.* = .{ .address = address, .index = @intCast(index), .valid = true };
            }
            return relocation;
        }

        entry.* = .{ .address = address, .index = no_relocation, .valid = true };
        return null;
    }
};

fn dynamicRelocation(state: anytype, got_addr: u64) ?*const @TypeOf(state.dynamic_relocations[0]) {
    if (comptime @hasField(@TypeOf(state.*), "dynamic_relocation_lookup")) {
        return state.dynamic_relocation_lookup.lookup(state.dynamic_relocations, got_addr);
    }
    for (state.dynamic_relocations) |*reloc| {
        if (reloc.offset == got_addr) return reloc;
    }
    return null;
}

const LocaleFacetMap = struct {
    id_symbol: []const u8,
    facet_symbol: []const u8,
    vtable_symbol: []const u8,
};

const locale_facets = [_]LocaleFacetMap{
    .{ .id_symbol = "_ZNSt3__17collateIcE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7collateIcEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17collateIcEE" },
    .{ .id_symbol = "_ZNSt3__17collateIwE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7collateIwEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17collateIwEE" },
    .{ .id_symbol = "_ZNSt3__15ctypeIcE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_5ctypeIcEEJDnbjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__15ctypeIcEE" },
    .{ .id_symbol = "_ZNSt3__15ctypeIwE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_5ctypeIwEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__15ctypeIwEE" },
    .{ .id_symbol = "_ZNSt3__17codecvtIcc11__mbstate_tE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7codecvtIcc11__mbstate_tEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17codecvtIcc11__mbstate_tEE" },
    .{ .id_symbol = "_ZNSt3__17codecvtIwc11__mbstate_tE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7codecvtIwc11__mbstate_tEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17codecvtIwc11__mbstate_tEE" },
    .{ .id_symbol = "_ZNSt3__17codecvtIDsc11__mbstate_tE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7codecvtIDsc11__mbstate_tEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17codecvtIDsc11__mbstate_tEE" },
    .{ .id_symbol = "_ZNSt3__17codecvtIDsDu11__mbstate_tE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7codecvtIDsDu11__mbstate_tEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17codecvtIDsDu11__mbstate_tEE" },
    .{ .id_symbol = "_ZNSt3__17codecvtIDic11__mbstate_tE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7codecvtIDic11__mbstate_tEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17codecvtIDic11__mbstate_tEE" },
    .{ .id_symbol = "_ZNSt3__17codecvtIDiDu11__mbstate_tE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7codecvtIDiDu11__mbstate_tEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17codecvtIDiDu11__mbstate_tEE" },
    .{ .id_symbol = "_ZNSt3__18numpunctIcE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_8numpunctIcEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__18numpunctIcEE" },
    .{ .id_symbol = "_ZNSt3__18numpunctIwE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_8numpunctIwEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__18numpunctIwEE" },
    .{ .id_symbol = "_ZNSt3__17num_getIcNS_19istreambuf_iteratorIcNS_11char_traitsIcEEEEE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7num_getIcNS_19istreambuf_iteratorIcNS_11char_traitsIcEEEEEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17num_getIcNS_19istreambuf_iteratorIcNS_11char_traitsIcEEEEEE" },
    .{ .id_symbol = "_ZNSt3__17num_putIcNS_19ostreambuf_iteratorIcNS_11char_traitsIcEEEEE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_7num_putIcNS_19ostreambuf_iteratorIcNS_11char_traitsIcEEEEEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__17num_putIcNS_19ostreambuf_iteratorIcNS_11char_traitsIcEEEEEE" },
    .{ .id_symbol = "_ZNSt3__18messagesIcE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_8messagesIcEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__18messagesIcEE" },
    .{ .id_symbol = "_ZNSt3__18messagesIwE2idE", .facet_symbol = "_ZZNSt3__112_GLOBAL__N_14makeINS_8messagesIwEEJjEEERT_DpT0_E3buf", .vtable_symbol = "_ZTVNSt3__18messagesIwEE" },
};

fn resolveLocaleFacet(state: anytype) ?u64 {
    if (localeTableFacet(state)) |facet| return facet;

    const id_addr = guestRegs(state).*.rsi;
    for (locale_facets) |facet| {
        const known_id = state.localSymbolAddress(facet.id_symbol) orelse continue;
        if (known_id != id_addr) continue;
        const facet_addr = state.localSymbolAddress(facet.facet_symbol) orelse return null;
        seedFacetVtable(state, facet_addr, facet.vtable_symbol);
        seedLocaleFacetTable(state, id_addr, facet_addr);
        return facet_addr;
    }
    return null;
}

fn localeTableFacet(state: anytype) ?u64 {
    const id_addr = guestRegs(state).*.rsi;
    const locale_obj = guestRegs(state).*.rdi;
    const locale_imp = state.read64(locale_obj);
    if (locale_imp == 0 or state.addrToOffset(locale_imp) == null) return null;
    const raw_index = state.read32(id_addr + 8);
    if (raw_index == 0 or raw_index == std.math.maxInt(u32)) return null;
    const begin = state.read64(locale_imp + 16);
    const end = state.read64(locale_imp + 24);
    if (begin == 0 or end < begin) return null;
    const count = (end - begin) / 8;
    if (raw_index == 0 or raw_index > count) return null;
    const facet = state.read64(begin + (@as(u64, raw_index) - 1) * 8);
    if (facet == 0) return null;
    return facet;
}

fn seedLocaleFacetTable(state: anytype, id_addr: u64, facet_addr: u64) void {
    const locale_obj = guestRegs(state).*.rdi;
    const locale_imp = state.read64(locale_obj);
    if (locale_imp == 0 or state.addrToOffset(locale_imp) == null) return;
    const raw_index = state.read32(id_addr + 8);
    if (raw_index == 0 or raw_index == std.math.maxInt(u32)) return;
    const begin = state.read64(locale_imp + 16);
    const end = state.read64(locale_imp + 24);
    if (begin == 0 or end < begin) return;
    const count = (end - begin) / 8;
    if (raw_index > count) return;
    state.write64(begin + (@as(u64, raw_index) - 1) * 8, facet_addr);
}

fn seedFacetVtable(state: anytype, facet_addr: u64, vtable_symbol: []const u8) void {
    if (facet_addr == 0 or state.read64(facet_addr) != 0) return;
    const vtable = state.localSymbolAddress(vtable_symbol) orelse return;
    state.write64(facet_addr, vtable + 16);
}

fn guestStringLiteral(state: anytype, text: []const u8) u64 {
    const addr = state.guestAlloc(text.len + 1, 1) orelse return 0;
    if (state.guestMemory(addr, @intCast(text.len + 1)) == null) return 0;
    if (!state.copyToGuest(addr, text)) return 0;
    state.write8(addr +| @as(u64, @intCast(text.len)), 0);
    return addr;
}

fn guestLocaleConv(state: anytype) u64 {
    const decimal = guestStringLiteral(state, ".");
    const empty = guestStringLiteral(state, "");
    const addr = state.guestAlloc(96, 8) orelse return 0;
    if (!state.fillGuestMemory(addr, 96, 0)) return 0;
    state.write64(addr + 0, decimal);
    state.write64(addr + 8, empty);
    return addr;
}

fn handleMbrtowcShim(state: anytype) void {
    const pwc = guestRegs(state).*.rdi;
    const src = guestRegs(state).*.rsi;
    const len = guestRegs(state).*.rdx;
    if (src == 0) {
        guestRegs(state).*.rax = 0;
        return;
    }
    if (len == 0) {
        guestRegs(state).*.rax = std.math.maxInt(u64) - 1;
        return;
    }
    const ch = guestByte(state, src) orelse {
        guestRegs(state).*.rax = x64_syscalls.errnoValue(.bad_address);
        return;
    };
    if (pwc != 0) writeGuest32(state, pwc, ch);
    guestRegs(state).*.rax = if (ch == 0) 0 else 1;
}

fn handleWcrtombShim(state: anytype) void {
    const dst = guestRegs(state).*.rdi;
    const wc = guestRegs(state).*.rsi;
    if (dst != 0) {
        if (state.guestMemory(dst, 1) == null) {
            guestRegs(state).*.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        }
        state.write8(dst, @truncate(wc));
    }
    guestRegs(state).*.rax = 1;
}

fn handleMemchrShim(state: anytype) void {
    const ptr = guestRegs(state).*.rdi;
    const needle: u8 = @truncate(guestRegs(state).*.rsi);
    const len = guestRegs(state).*.rdx;
    var index: u64 = 0;
    while (index < len) : (index += 1) {
        const ch = guestByte(state, ptr + index) orelse break;
        if (ch == needle) {
            guestRegs(state).*.rax = ptr + index;
            return;
        }
    }
    guestRegs(state).*.rax = 0;
}

fn guestStrcmp(state: anytype, lhs: u64, rhs: u64) i32 {
    var index: u64 = 0;
    while (true) : (index += 1) {
        const a = guestByte(state, lhs + index) orelse 0;
        const b = guestByte(state, rhs + index) orelse 0;
        if (a != b) return @as(i32, a) - @as(i32, b);
        if (a == 0) return 0;
    }
}

fn guestByte(state: anytype, addr: u64) ?u8 {
    if (state.guestMemoryConst(addr, 1) == null) return null;
    return state.read8(addr);
}

fn writeGuest32(state: anytype, addr: u64, value: u32) void {
    if (state.guestMemory(addr, 4) == null) return;
    state.write32(addr, value);
}

fn finishExternalReturn(state: anytype, direct_return_rip: ?u64) void {
    if (direct_return_rip) |rip| {
        guestRegs(state).*.rip = rip;
    } else {
        guestRegs(state).*.rip = state.pop();
    }
}

fn handleWriteShim(state: anytype) void {
    const fd = guestRegs(state).*.rdi;
    const buf = guestRegs(state).*.rsi;
    const len = guestRegs(state).*.rdx;
    if (len == 0) {
        guestRegs(state).*.rax = state.writeHostFd(fd, &.{});
        state.traceGuestIo("libc.write", fd, buf, len, guestRegs(state).*.rax);
        return;
    }
    if (len > std.math.maxInt(usize) or state.guestMemoryConst(buf, len) == null) {
        guestRegs(state).*.rax = x64_syscalls.errnoValue(.bad_address);
        state.traceGuestIo("libc.write", fd, buf, len, guestRegs(state).*.rax);
        return;
    }
    const storage = state.allocator.alloc(u8, @intCast(len)) catch {
        guestRegs(state).*.rax = x64_syscalls.errnoValue(.no_memory);
        state.traceGuestIo("libc.write", fd, buf, len, guestRegs(state).*.rax);
        return;
    };
    defer state.allocator.free(storage);
    if (!state.copyFromGuest(storage, buf)) {
        guestRegs(state).*.rax = x64_syscalls.errnoValue(.bad_address);
        state.traceGuestIo("libc.write", fd, buf, len, guestRegs(state).*.rax);
        return;
    }
    guestRegs(state).*.rax = state.writeHostFd(fd, storage);
    state.traceGuestIo("libc.write", fd, buf, len, guestRegs(state).*.rax);
}

fn handleWritevShim(state: anytype) void {
    const fd = guestRegs(state).*.rdi;
    const iov = guestRegs(state).*.rsi;
    const iovcnt = guestRegs(state).*.rdx;
    var total: u64 = 0;
    var index: u64 = 0;
    while (index < iovcnt) : (index += 1) {
        const entry_offset = std.math.mul(u64, index, 16) catch {
            guestRegs(state).*.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        };
        const entry = std.math.add(u64, iov, entry_offset) catch {
            guestRegs(state).*.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        };
        if (state.guestMemoryConst(entry, 16) == null) {
            guestRegs(state).*.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        }
        const base = state.read64(entry);
        const len = state.read64(entry + 8);
        if (len > std.math.maxInt(usize) or state.guestMemoryConst(base, len) == null) {
            guestRegs(state).*.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        }
        const data = state.allocator.alloc(u8, @intCast(len)) catch {
            guestRegs(state).*.rax = x64_syscalls.errnoValue(.no_memory);
            state.traceGuestIo("libc.writev", fd, base, len, guestRegs(state).*.rax);
            return;
        };
        defer state.allocator.free(data);
        if (!state.copyFromGuest(data, base)) {
            guestRegs(state).*.rax = x64_syscalls.errnoValue(.bad_address);
            state.traceGuestIo("libc.writev", fd, base, len, guestRegs(state).*.rax);
            return;
        }
        const result = state.writeHostFd(fd, data);
        state.traceGuestIo("libc.writev", fd, base, len, result);
        if (@as(i64, @bitCast(result)) < 0) {
            guestRegs(state).*.rax = result;
            return;
        }
        total +%= len;
    }
    guestRegs(state).*.rax = total;
    if (iovcnt == 0) state.traceGuestIo("libc.writev", fd, iov, 0, guestRegs(state).*.rax);
}

fn symbolNameEql(name: []const u8, expected: []const u8) bool {
    if (std.mem.eql(u8, name, expected)) return true;
    if (std.mem.startsWith(u8, name, expected) and name.len > expected.len and name[expected.len] == '@') return true;
    return false;
}

test "dynamic relocation lookup caches hits and misses without trusting collisions" {
    const Relocation = struct { offset: u64, name: []const u8 };
    const first_address: u64 = 0x1000;
    const colliding_address = first_address + DynamicRelocationLookup.entry_count * 8;
    try std.testing.expectEqual(
        DynamicRelocationLookup.slotFor(first_address),
        DynamicRelocationLookup.slotFor(colliding_address),
    );

    var relocations = [_]Relocation{
        .{ .offset = first_address, .name = "first" },
        .{ .offset = colliding_address, .name = "second" },
    };
    var lookup = DynamicRelocationLookup{};

    try std.testing.expectEqualStrings("first", lookup.lookup(relocations[0..], first_address).?.name);
    try std.testing.expectEqualStrings("second", lookup.lookup(relocations[0..], colliding_address).?.name);
    // The second address replaced the first direct-mapped entry. A miss in
    // the cache must search the table and recover the first exact match.
    try std.testing.expectEqualStrings("first", lookup.lookup(relocations[0..], first_address).?.name);

    const absent_address: u64 = 0x9000;
    try std.testing.expect(lookup.lookup(relocations[0..], absent_address) == null);
    const absent_entry = lookup.entries[DynamicRelocationLookup.slotFor(absent_address)];
    try std.testing.expect(absent_entry.valid);
    try std.testing.expectEqual(DynamicRelocationLookup.no_relocation, absent_entry.index);
    try std.testing.expect(lookup.lookup(relocations[0..], absent_address) == null);

    lookup.clear();
    relocations[0].offset = 0x3000;
    try std.testing.expectEqualStrings("first", lookup.lookup(relocations[0..], 0x3000).?.name);
}
