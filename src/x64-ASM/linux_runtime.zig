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
    if (symbolNameEql(name, "__libc_start_main")) return false;
    std.log.scoped(.x64_linux_runtime).warn("unsupported PLT symbol {s}", .{name});
    return false;
}

pub fn tryLocalFunctionShim(state: anytype, target: u64, direct_return_rip: u64) bool {
    const name = state.localSymbolNameAt(target) orelse return false;
    if (symbolNameEql(name, "_ZNKSt3__16locale9use_facetERNS0_2idE")) {
        const facet = resolveLocaleFacet(state) orelse return false;
        state.regs.rax = facet;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    return false;
}

fn tryNamedFunctionShim(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (symbolNameEql(name, "remove")) {
        const path = guestCString(state, state.regs.rdi) orelse "";
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        std.log.scoped(.x64_linux_runtime).info("shimmed remove({s}) as no-op", .{path});
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
    if (symbolNameEql(name, "newlocale")) {
        state.regs.rax = state.guestAlloc(16, 8) orelse 1;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "uselocale")) {
        state.regs.rax = 1;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "freelocale")) {
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "setlocale")) {
        state.regs.rax = guestStringLiteral(state, "C");
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "localeconv")) {
        state.regs.rax = guestLocaleConv(state);
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
    if (symbolNameEql(name, "__ctype_get_mb_cur_max")) {
        state.regs.rax = 1;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "mbtowc") or symbolNameEql(name, "mbrtowc")) {
        handleMbrtowcShim(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "btowc")) {
        const ch = state.regs.rdi & 0xFF;
        state.regs.rax = if (ch == 0xFF) 0xFFFF_FFFF else ch;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "wctob")) {
        const wc = state.regs.rdi;
        state.regs.rax = if (wc <= 0x7F) wc else 0xFFFF_FFFF;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "wcrtomb")) {
        handleWcrtombShim(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "iswcntrl_l")) {
        const wc = state.regs.rdi;
        state.regs.rax = if (wc < 0x20 or wc == 0x7F) 1 else 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "towlower_l") or symbolNameEql(name, "towupper_l")) {
        var wc = state.regs.rdi;
        if (symbolNameEql(name, "towlower_l") and wc >= 'A' and wc <= 'Z') wc += 32;
        if (symbolNameEql(name, "towupper_l") and wc >= 'a' and wc <= 'z') wc -= 32;
        state.regs.rax = wc;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "memchr")) {
        handleMemchrShim(state);
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "strcmp") or symbolNameEql(name, "strcoll_l")) {
        state.regs.rax = @bitCast(@as(i64, guestStrcmp(state, state.regs.rdi, state.regs.rsi)));
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "syscall")) {
        state.invokeLinuxSyscall(
            state.regs.rdi,
            state.regs.rsi,
            state.regs.rdx,
            state.regs.rcx,
            state.regs.r8,
            state.regs.r9,
            state.read64(state.regs.rsp + 8),
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
        state.regs.rax = 0;
        finishExternalReturn(state, direct_return_rip);
        return true;
    }
    if (symbolNameEql(name, "pthread_self")) {
        state.regs.rax = 1;
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

    const id_addr = state.regs.rsi;
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
    const id_addr = state.regs.rsi;
    const locale_obj = state.regs.rdi;
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
    const locale_obj = state.regs.rdi;
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

fn guestCString(state: anytype, addr: u64) ?[]const u8 {
    const off = state.addrToOffset(addr) orelse return null;
    const off_usize: usize = @intCast(off);
    const rest = state.mem[off_usize..];
    const len = std.mem.indexOfScalar(u8, rest, 0) orelse return null;
    return rest[0..len];
}

fn guestStringLiteral(state: anytype, text: []const u8) u64 {
    const addr = state.guestAlloc(text.len + 1, 1) orelse return 0;
    const off = state.addrToOffset(addr) orelse return 0;
    const off_usize: usize = @intCast(off);
    if (off_usize > state.mem.len or text.len + 1 > state.mem.len - off_usize) return 0;
    @memcpy(state.mem[off_usize..][0..text.len], text);
    state.mem[off_usize + text.len] = 0;
    return addr;
}

fn guestLocaleConv(state: anytype) u64 {
    const decimal = guestStringLiteral(state, ".");
    const empty = guestStringLiteral(state, "");
    const addr = state.guestAlloc(96, 8) orelse return 0;
    const off = state.addrToOffset(addr) orelse return 0;
    const off_usize: usize = @intCast(off);
    if (off_usize + 96 > state.mem.len) return 0;
    @memset(state.mem[off_usize..][0..96], 0);
    state.write64(addr + 0, decimal);
    state.write64(addr + 8, empty);
    return addr;
}

fn handleMbrtowcShim(state: anytype) void {
    const pwc = state.regs.rdi;
    const src = state.regs.rsi;
    const len = state.regs.rdx;
    if (src == 0) {
        state.regs.rax = 0;
        return;
    }
    if (len == 0) {
        state.regs.rax = std.math.maxInt(u64) - 1;
        return;
    }
    const ch = guestByte(state, src) orelse {
        state.regs.rax = x64_syscalls.errnoValue(.bad_address);
        return;
    };
    if (pwc != 0) writeGuest32(state, pwc, ch);
    state.regs.rax = if (ch == 0) 0 else 1;
}

fn handleWcrtombShim(state: anytype) void {
    const dst = state.regs.rdi;
    const wc = state.regs.rsi;
    if (dst != 0) {
        const off = state.addrToOffset(dst) orelse {
            state.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        };
        const off_usize: usize = @intCast(off);
        if (off_usize >= state.mem.len) {
            state.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        }
        state.mem[off_usize] = @truncate(wc);
    }
    state.regs.rax = 1;
}

fn handleMemchrShim(state: anytype) void {
    const ptr = state.regs.rdi;
    const needle: u8 = @truncate(state.regs.rsi);
    const len = state.regs.rdx;
    var index: u64 = 0;
    while (index < len) : (index += 1) {
        const ch = guestByte(state, ptr + index) orelse break;
        if (ch == needle) {
            state.regs.rax = ptr + index;
            return;
        }
    }
    state.regs.rax = 0;
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
    const off = state.addrToOffset(addr) orelse return null;
    const off_usize: usize = @intCast(off);
    if (off_usize >= state.mem.len) return null;
    return state.mem[off_usize];
}

fn writeGuest32(state: anytype, addr: u64, value: u32) void {
    const off = state.addrToOffset(addr) orelse return;
    const off_usize: usize = @intCast(off);
    if (off_usize + 4 > state.mem.len) return;
    std.mem.writeInt(u32, state.mem[off_usize..][0..4], value, .little);
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
    const data = state.guestMemoryConst(buf, len) orelse {
        state.regs.rax = x64_syscalls.errnoValue(.bad_address);
        state.traceGuestIo("libc.write", fd, buf, len, state.regs.rax);
        return;
    };
    state.regs.rax = state.writeHostFd(fd, data);
    state.traceGuestIo("libc.write", fd, buf, len, state.regs.rax);
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
            state.traceGuestIo("libc.writev", fd, base, len, state.regs.rax);
            return;
        }
        const data = state.mem[off_usize .. off_usize + len_usize];
        const result = state.writeHostFd(fd, data);
        state.traceGuestIo("libc.writev", fd, base, len, result);
        if (@as(i64, @bitCast(result)) < 0) {
            state.regs.rax = result;
            return;
        }
        total +%= len;
    }
    state.regs.rax = total;
    if (iovcnt == 0) state.traceGuestIo("libc.writev", fd, iov, 0, state.regs.rax);
}

fn symbolNameEql(name: []const u8, expected: []const u8) bool {
    if (std.mem.eql(u8, name, expected)) return true;
    if (std.mem.startsWith(u8, name, expected) and name.len > expected.len and name[expected.len] == '@') return true;
    return false;
}
