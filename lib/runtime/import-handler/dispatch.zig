//! Mach-O guest import routing, compatibility contracts, and import-boundary
//! scheduling.
//!
//! This implementation is intentionally state-generic. MachOState owns the
//! state; this module owns the import policy and transitions.

const std = @import("std");
const x64_decoder = @import("x64_decoder");
const macho_core = @import("macho_core");
const macho_metadata = macho_core.metadata;
const types = macho_core.types;
const utils = macho_core.utils;
const compat_runtime = @import("macho_compat_runtime");
const contract = @import("contract");
const import_resolution = @import("dyld").import_engine;
const export_table_lifecycle = @import("dyld").export_table_lifecycle;
const guest_memory_geometry = @import("dyld").guest_memory_geometry;
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const exit_diagnostics = @import("exit_diagnostics");
const guest_assertion_recovery = @import("guest_abi").guest_assertion_recovery;
const cpp_allocation = @import("guest_abi").cpp_allocation;
const libcpp_thread = @import("guest_abi").libcpp_thread;
const sdl_runtime = @import("guest_abi").sdl_runtime;
const native_window_runtime = @import("guest_abi").native_window_runtime;
const spirv_cross_diagnostics = @import("diagnostics").spirv_cross_diagnostics;
const x64_backend_diagnostics = @import("diagnostics").x64_backend_diagnostics;
const symbol_assembly_context = macho_core.symbol_assembly_context;
const scheduler = @import("scheduler");

const log = std.log.scoped(.macho_import_dispatch);
const ImportHandlerResult = types.ImportHandlerResult;
const ImportRoute = types.ImportRoute;
const ImportTraceEntry = types.ImportTraceEntry;
const classifyGuestAssertion = types.classifyGuestAssertion;
const timerQueueStateName = types.timerQueueStateName;
const idleQueueSnapshotFor = types.idleQueueSnapshotFor;
const isGtkIdleAddImport = types.isGtkIdleAddImport;
const isGtkEventsPendingImport = types.isGtkEventsPendingImport;
const isGtkMainIterationImport = types.isGtkMainIterationImport;
const importRouteCacheIndex = utils.importRouteCacheIndex;
const nextPrime = utils.nextPrime;
const decodeInsn = macho_core.decoder.decodeInsn;

const constants = macho_core.constants;
const GUEST_ATEXIT_RETURN_SENTINEL = constants.GUEST_ATEXIT_RETURN_SENTINEL;
const IMPORT_TRACE_BUFFER_LEN = constants.IMPORT_TRACE_BUFFER_LEN;
const TRACE_BUFFER_LEN = constants.TRACE_BUFFER_LEN;
const UNSUPPORTED_RUNTIME_EXIT_CODE = constants.UNSUPPORTED_RUNTIME_EXIT_CODE;

/// FNV-1a 64-bit. Computed once per `handleImportSlow` dispatch so the
/// name-compare chain costs u64 compares; the `eql` that follows each hash
/// equality remains the arbiter, so a collision can never change behavior.
/// Const-folded at comptime for the literal spellings.
fn importNameHash(name: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (name) |byte| {
        hash = (hash ^ byte) *% 1099511628211;
    }
    return hash;
}

fn guestSysconf(selector: i32) u64 {
    return guest_memory_geometry.darwinSysconf(selector) orelse
        @bitCast(@as(i64, -1));
}

/// `pthread_exit` terminates only the calling pthread.  While the intercepted
/// Cocoa/GTK main loop owns cooperative guest threads, treating it as process
/// exit drops every parked Xenia worker (including the title main thread).
/// Outside that scheduler there is no alternate register context to resume,
/// so the legacy process-exit fallback remains necessary.
fn pthreadExitIsThreadLocal(cooperative_ui_active: bool, active_thread: u64) bool {
    return cooperative_ui_active and active_thread != 0;
}

/// Return the guest call site that entered an imported allocator routine.
/// `regs.rip` is the synthetic import thunk while dispatch is active, which
/// made every invalid free appear to come from the same 0xfffffc... address.
/// The saved return address identifies the actual C++ owner/destructor.
/// Which domain an Objective-C message into Rosette's window came from.
///
/// Every one of them arrives through translated x86 executing the emulator's
/// own host code, so `xenia_host` is the honest attribution; the guest title
/// never issues an `objc_msgSend` itself. Naming it rather than defaulting to
/// `unknown` matters because `unknown` is refused for everything, which would
/// turn the whole surface into a fault the first time it was consulted.
fn windowActorForObjc() native_window_runtime.Actor {
    return .xenia_host;
}

fn importCallerAddress(self: anytype) u64 {
    if (self.regs.rsp == 0 or self.guestMemoryConst(self.regs.rsp, @sizeOf(u64)) == null) {
        return self.regs.rip;
    }
    const caller = self.read64(self.regs.rsp);
    return if (caller != 0) caller else self.regs.rip;
}

pub fn handleImportImpl(self: anytype, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
    // Forward-looking near-null signature: one compare per dispatch, and a
    // rare branch only when the receiver is below the near-null threshold.
    self.near_null_predictor.note(self, imported.name);
    if (self.tryPrimitiveDispatch(imported)) |result| {
        self.import_handler.primitive_dispatch_hits +|= 1;
        return result;
    }

    const cache_index = importRouteCacheIndex(imported.stub_address);
    const entry = &self.import_route_cache[cache_index];
    if (entry.valid and entry.stub_address == imported.stub_address) {
        // `.legacy` and `.strtoul` both dispatch straight back into
        // `handleImportSlow`, so a "hit" on either performs the entire
        // string-compare chain the cache exists to avoid. Counting them as hits
        // is what let a run report a 99% hit rate while most dispatches still
        // paid full price. Count them apart so the headline rate means what it
        // says: the slow path was skipped.
        const skips_slow_path = entry.route != .legacy and entry.route != .strtoul;
        if (dispatchImportRoute(self, entry.route, imported)) |result| {
            self.import_route_cache_hits +|= 1;
            if (!skips_slow_path) self.import_route_cache_slow_hits +|= 1;
            return result;
        }
        // The cached route declined the symbol it was cached for. That is a
        // route whose applicability is not a function of the stub address, and
        // it costs a failed dispatch plus the full slow path every time.
        // Attributed per route, because "70,725 fallbacks" names nothing.
        self.import_route_cache_fallbacks +|= 1;
        self.import_route_fallbacks[@intFromEnum(entry.route)] +|= 1;
        entry.valid = false;
    } else {
        self.import_route_cache_misses +|= 1;
        if (entry.valid) self.import_route_cache_collisions +|= 1;
    }

    self.resolving_import_route = .legacy;
    const result = handleImportSlow(self, imported);
    entry.* = .{
        .stub_address = imported.stub_address,
        .route = self.resolving_import_route,
        .valid = true,
    };
    return result;
}

pub fn handleImportSlow(self: anytype, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
    const name = imported.name;
    // Hash once per dispatch so the ~120-name compare chain below becomes a
    // sequence of u64 compares instead of string walks. Every hash equality
    // is followed by the `eql` that used to stand alone: a collision can only
    // cost one extra compare on the matched name, never select the wrong
    // branch, so the chain's semantics are byte-for-byte unchanged.
    const name_hash = importNameHash(name);
    if (((name_hash == importNameHash("_exit") and std.mem.eql(u8, name, "_exit")) or
        (name_hash == importNameHash("exit") and std.mem.eql(u8, name, "exit"))) and
        self.foreign_objects.main_loop_bypasses != 0)
    {
        machoCapturePrint(
            "macho-processor: guest exit attribution: follows {d} bypassed cooperative main loop(s); this is UI event-loop shutdown, not a filesystem or config-write failure\n",
            .{self.foreign_objects.main_loop_bypasses},
        );
    }
    if ((name_hash == importNameHash("_exit") and std.mem.eql(u8, name, "_exit")) or (name_hash == importNameHash("exit") and std.mem.eql(u8, name, "exit"))) {
        const exit_code = self.regs.rdi;
        if (beginGuestExit(self, exit_code)) return .control_transferred;
        if (self.terminated) return .control_transferred;
        return .{ .terminated = exit_code };
    }
    if ((name_hash == importNameHash("_memcpy") and std.mem.eql(u8, name, "_memcpy")) or (name_hash == importNameHash("_memmove") and std.mem.eql(u8, name, "_memmove")) or
        (name_hash == importNameHash("___memcpy_chk") and std.mem.eql(u8, name, "___memcpy_chk")) or (name_hash == importNameHash("___memmove_chk") and std.mem.eql(u8, name, "___memmove_chk")))
    {
        self.resolving_import_route = .guest_memory_copy;
        return handleGuestMemoryCopy(self, name);
    }
    if ((name_hash == importNameHash("_memset") and std.mem.eql(u8, name, "_memset")) or (name_hash == importNameHash("___memset_chk") and std.mem.eql(u8, name, "___memset_chk"))) {
        self.resolving_import_route = .memset;
        const dst = self.regs.rdi;
        const val: u8 = @truncate(self.regs.rsi);
        const count = self.regs.rdx;
        if (count != 0) {
            const buf = self.guestMemory(dst, count) orelse return .{ .unsupported = 0 };
            const mutation = self.captureMemoryMutation(dst, count);
            self.noteGuestWrite(dst, count);
            @memset(buf, val);
            self.commitMemoryMutation(mutation, .bulk_fill);
        }
        return .{ .handled = dst };
    }
    if ((name_hash == importNameHash("_pthread_once") and std.mem.eql(u8, name, "_pthread_once"))) {
        self.resolving_import_route = .pthread_once;
        return handlePthreadOnce(self);
    }
    if ((name_hash == importNameHash("_bzero") and std.mem.eql(u8, name, "_bzero")) or (name_hash == importNameHash("__bzero") and std.mem.eql(u8, name, "__bzero"))) {
        self.resolving_import_route = .bzero;
        const dst = self.regs.rdi;
        const count = self.regs.rsi;
        if (count != 0) {
            const buf = self.guestMemory(dst, count) orelse return .{ .unsupported = 0 };
            const mutation = self.captureMemoryMutation(dst, count);
            self.noteGuestWrite(dst, count);
            @memset(buf, 0);
            self.commitMemoryMutation(mutation, .bulk_fill);
        }
        return .{ .handled = 0 };
    }
    if ((name_hash == importNameHash("_sysconf") and std.mem.eql(u8, name, "_sysconf"))) {
        self.resolving_import_route = .sysconf;
        const selector: i32 = @bitCast(@as(u32, @truncate(self.regs.rdi)));
        const value = guestSysconf(selector);
        if (self.verbose_trace) {
            machoCapturePrint("    [posix] sysconf({d}) -> {d}\n", .{ selector, @as(i64, @bitCast(value)) });
        }
        return .{ .handled = value };
    }
    if ((name_hash == importNameHash("_dlopen") and std.mem.eql(u8, name, "_dlopen"))) {
        const path = self.guestCString(self.regs.rdi, 1024) orelse return .{ .handled = 0 };
        const handle = self.dynamic_forwarder.openGuest(path, self.regs.rsi);
        if (self.verbose_trace or handle == 0) {
            machoCapturePrint(
                "    [dynamic loader] dlopen({s}, 0x{x}) -> 0x{x}\n",
                .{ path, self.regs.rsi, handle },
            );
        }
        return .{ .handled = handle };
    }
    if ((name_hash == importNameHash("_dlclose") and std.mem.eql(u8, name, "_dlclose"))) {
        const result = self.dynamic_forwarder.closeGuest(self.regs.rdi);
        return .{ .handled = @as(u32, @bitCast(result)) };
    }
    if ((name_hash == importNameHash("_dlsym") and std.mem.eql(u8, name, "_dlsym"))) {
        const symbol = self.guestCString(self.regs.rsi, 512) orelse return .{ .handled = 0 };
        const address = self.dynamic_forwarder.lookupGuest(self.regs.rdi, symbol);
        if (address != 0) self.registerSyntheticThunk(address, 1, symbol);
        if (self.verbose_trace or address == 0) {
            machoCapturePrint(
                "    [dynamic loader] dlsym(0x{x}, {s}) -> 0x{x}\n",
                .{ self.regs.rdi, symbol, address },
            );
        }
        return .{ .handled = address };
    }
    if (self.sdl.dispatch(self, name)) |resolution| {
        self.resolving_import_route = .sdl_compat;
        self.import_confidence_override = .modeled;
        noteSdlGraphicsImport(self, name);
        return sdlResolution(resolution);
    }
    if (self.main_loop_type == .gtk) {
        if ((name_hash == importNameHash("_gtk_main") and std.mem.eql(u8, name, "_gtk_main")) and self.beginCooperativeMainLoop()) {
            self.resolving_import_route = .coop_main;
            return .control_transferred;
        }
        if ((name_hash == importNameHash("_gtk_main_quit") and std.mem.eql(u8, name, "_gtk_main_quit")) and self.cooperative_ui_context != null) {
            self.resolving_import_route = .coop_main_quit;
            self.foreign_objects.main_loop_quits +|= 1;
            self.restoreMainLoopCaller("gtk_main_quit");
            return .control_transferred;
        }
        if (isGtkIdleAddImport(name)) {
            self.resolving_import_route = .idle_add;
            return handleIdleAdd(self, name);
        }
        if ((name_hash == importNameHash("_g_source_remove") and std.mem.eql(u8, name, "_g_source_remove"))) {
            self.resolving_import_route = .idle_source_remove;
            return handleIdleSourceRemove(self);
        }
        if (isGtkEventsPendingImport(name)) {
            self.resolving_import_route = .events_pending;
            self.pumpNativeWindowEvents();
            return .{ .handled = @intFromBool(self.pendingIdleCallbackCount() != 0) };
        }
        if (isGtkMainIterationImport(name)) {
            self.resolving_import_route = .coop_main_iteration;
            self.pumpNativeWindowEvents();
            if (self.startNextIdleCallback(name, false)) return .control_transferred;
            return .{ .handled = 0 };
        }
    }
    // The libc++ stream family dispatches BEFORE the local-definition redirect.
    // Template members such as operator<<(ostream&, function-pointer) and
    // std::endl are emitted as weak local copies inside the guest image, so the
    // redirect would hand control to native libc++ code that dereferences the
    // guest ostream — the near-null casualty vector (Xbyak's undefined-label
    // print crashed exactly there). The bridge must own these symbols; it
    // returns null for anything it does not recognize, so the redirect below
    // still runs for every other symbol.
    if (self.libcxx_streams.dispatch(self, &self.fs_forwarder, name)) |resolution| {
        self.resolving_import_route = .libcxx_stream;
        self.import_provider_override = .libcpp_stream;
        self.import_confidence_override = .modeled;
        return switch (resolution) {
            .handled => |value| .{ .handled = value },
            .handled_void => .handled_void,
        };
    }
    if (self.metadata.definedSymbolAddress(name)) |target| {
        if (target != imported.stub_address and self.isExecutableAddress(target)) {
            self.regs.rip = target;
            self.resolving_import_route = .local_definition;
            self.import_provider_override = .local_definition;
            self.import_confidence_override = .verified;
            if (self.verbose_trace) {
                machoCapturePrint("    [local definition] {s}: stub=0x{x} -> target=0x{x}\n", .{ name, imported.stub_address, target });
            }
            return .control_transferred;
        }
    }
    if (dispatchLibcppLocale(self, name)) |resolution| return resolution;
    if (self.foreign_objects.dispatch(self, name)) |resolution| {
        self.resolving_import_route = .foreign_object;
        self.import_confidence_override = .modeled;
        return switch (resolution) {
            .handled => |value| .{ .handled = value },
            .handled_void => .handled_void,
        };
    }
    if (self.pthreads.dispatchCppSynchronization(self, name)) |resolution| {
        self.resolving_import_route = .pthread_cpp_sync;
        self.import_provider_override = .pthread_runtime;
        self.import_confidence_override = .modeled;
        return switch (resolution) {
            .handled => |value| .{ .handled = value },
            .handled_void => .handled_void,
        };
    }
    if (import_resolution.dispatchContract(self, name)) |resolution| {
        self.resolving_import_route = .import_contract;
        return switch (resolution) {
            .handled => |value| .{ .handled = value },
            .handled_void => .handled_void,
            .failed => .{ .unsupported = 0 },
        };
    }

    if (self.libcxx_filesystem.dispatch(self, &self.fs_forwarder, name)) |resolution| {
        self.resolving_import_route = .libcxx_filesystem;
        self.import_provider_override = .libcpp_filesystem;
        self.import_confidence_override = .verified;
        return switch (resolution) {
            .handled => |value| .{ .handled = value },
            .handled_void => .handled_void,
        };
    }

    if (self.pthreads.dispatch(self, name)) |resolution| {
        self.resolving_import_route = .pthread;
        self.import_provider_override = .pthread_runtime;
        self.import_confidence_override = .modeled;
        return switch (resolution) {
            .handled => |value| .{ .handled = value },
            .handled_void => .handled_void,
        };
    }

    if (self.dynamic_forwarder.forward(self, imported.dylib, name)) |resolution| {
        self.resolving_import_route = .dynamic_library;
        self.import_provider_override = .dynamic_library;
        self.import_confidence_override = .verified;
        return switch (resolution) {
            .handled => |value| .{ .handled = value },
            .handled_void => .handled_void,
        };
    }

    if (contract.dispatchFromAllFamilies(name, self.regs.rdi)) |outcome| {
        self.resolving_import_route = .shared_contract;
        if (self.verbose_trace) {
            const c = contract.resolveFromAllFamilies(name);
            const tag = @tagName(outcome);
            machoCapturePrint("    [contract] {s} → {s}", .{ name, if (c) |cc| cc.name else "?" });
            switch (outcome) {
                .handled => |val| machoCapturePrint(" ({s}) handled=0x{x}\n", .{ tag, val }),
                .terminated => |code| machoCapturePrint(" ({s}) terminated={d}\n", .{ tag, code }),
            }
        }
        if (self.contract_verification) {
            if (contract.verify.verifyDispatch(name, outcome, self.regs.rdi)) {
                return switch (outcome) {
                    .handled => |val| ImportHandlerResult{ .handled = val },
                    .terminated => |code| ImportHandlerResult{ .terminated = code },
                };
            }
            if (contract.verify.resolveExpected(name, self.regs.rdi)) |expected| {
                machoCapturePrint("    [contract] WARNING: {s} verification mismatch, using expected\n", .{name});
                return switch (expected) {
                    .handled => |val| ImportHandlerResult{ .handled = val },
                    .terminated => |code| ImportHandlerResult{ .terminated = code },
                };
            }
            machoCapturePrint("    [contract] WARNING: {s} verification mismatch, no expected fallback\n", .{name});
        }
        return switch (outcome) {
            .handled => |val| ImportHandlerResult{ .handled = val },
            .terminated => |code| ImportHandlerResult{ .terminated = code },
        };
    }

    if ((name_hash == importNameHash("_objc_getClass") and std.mem.eql(u8, name, "_objc_getClass"))) {
        const class_name = self.guestCString(self.regs.rdi, 1024) orelse return .{ .unsupported = 0 };
        const handle = self.compat.classNamed(class_name);
        self.registerOpaqueHandle(handle, "objc class identity");
        machoCapturePrint("    [objc] class {s} -> 0x{x}\n", .{ class_name, handle });
        return .{ .handled = handle };
    }
    if ((name_hash == importNameHash("_sel_registerName") and std.mem.eql(u8, name, "_sel_registerName"))) {
        const selector_name = self.guestCString(self.regs.rdi, 1024) orelse return .{ .unsupported = 0 };
        const handle = self.compat.selectorNamed(selector_name);
        self.registerOpaqueHandle(handle, "Objective-C selector identity");
        machoCapturePrint("    [objc] selector {s} -> 0x{x}\n", .{ selector_name, handle });
        return .{ .handled = handle };
    }
    if ((name_hash == importNameHash("_objc_msgSend") and std.mem.eql(u8, name, "_objc_msgSend"))) {
        const selector_name = self.compat.selectorName(self.regs.rsi);
        const class_name = self.compat.className(self.regs.rdi);
        switch (self.native_window.handleObjcMessage(
            class_name,
            self.regs.rdi,
            selector_name,
            self.regs.rdx,
        )) {
            .handled => |native_result| {
                // Recorded even when it succeeds. The admission ledger is the
                // window's account of who touched it, and an account that holds
                // only the failures cannot say what a healthy run looks like.
                const outcome = self.admitWindowForwarding(
                    windowActorForObjc(),
                    native_result.binding.facility,
                    native_result.binding.operation,
                    selector_name,
                );
                // The action has already happened by the time this returns, so
                // an ordering refusal cannot retract it — recording it and then
                // answering `unsupported` would be a lie about what the window
                // did. An unaccountable verdict is different: it says the
                // forwarding should never have been performed at all, and the
                // fault policy stops the run at it.
                // Printed before the fault, not after. A fault raises SIGSEGV
                // and never returns, so a trace line placed below it is a line
                // the one run that needed it never gets.
                machoCapturePrint(
                    "    [objc/native] msgSend receiver=0x{x} class={s} selector={s} argument=0x{x} -> 0x{x} action={s} admission={s}\n",
                    .{ self.regs.rdi, class_name, selector_name, self.regs.rdx, native_result.value, native_result.action, outcome.decision.verdict.label() },
                );
                if (outcome.disposition == .fault) self.faultOnWindowAdmission(outcome);
                if (native_result.value >= 0xFFFF_0000_0000_0000) {
                    self.registerNativeWindowHandles();
                }
                return .{ .handled = native_result.value };
            },
            .unrecognized => |binding| {
                // Addressed to an identity Rosette's window owns. The generic
                // Objective-C model must not answer for it: that model has no
                // idea what this window is, and a plausible reply here is how a
                // forwarding Rosette never implemented ends up looking handled.
                const outcome = self.admitWindowForwarding(
                    windowActorForObjc(),
                    binding.facility,
                    binding.operation,
                    selector_name,
                );
                machoCapturePrint(
                    "    [objc/native] msgSend REFUSED receiver=0x{x} class={s} selector={s} argument=0x{x} verdict={s} disposition={s}; this identity is Rosette's window and nothing else may answer for it. If this selector is one Xenia legitimately sends, substantiate it in native_window_runtime.handleObjcMessage rather than letting the generic model answer for an object it does not own\n",
                    .{ self.regs.rdi, class_name, selector_name, self.regs.rdx, outcome.decision.verdict.label(), outcome.disposition.label() },
                );
                if (outcome.disposition == .fault) self.faultOnWindowAdmission(outcome);
                if (outcome.disposition != .admit) return .{ .unsupported = 0 };
            },
            .foreign => {},
        }
        const result = self.compat.sendMessage(self.regs.rdi, self.regs.rsi);
        if (result.value >= 0xFFFF_0000_0000_0000) self.registerOpaqueHandle(result.value, "Objective-C object identity");
        machoCapturePrint(
            "    [objc] msgSend receiver=0x{x} selector={s} -> 0x{x} modeled={}\n",
            .{ self.regs.rdi, result.selector_name, result.value, result.modeled },
        );
        return if (result.modeled) .{ .handled = result.value } else .{ .unsupported = result.value };
    }

    if ((name_hash == importNameHash("_objc_autoreleasePoolPush") and std.mem.eql(u8, name, "_objc_autoreleasePoolPush"))) {
        const handle = self.compat.currentThreadHandle();
        self.registerOpaqueHandle(handle, "Objective-C autorelease pool identity");
        return .{ .handled = handle };
    }
    if ((name_hash == importNameHash("___assert_rtn") and std.mem.eql(u8, name, "___assert_rtn"))) {
        self.guest_assertion_count += 1;
        const function_name = self.guestCString(self.regs.rdi, 1024) orelse "<unknown>";
        const file_name = self.guestCString(self.regs.rsi, 4096) orelse "<unknown>";
        const expression = self.guestCString(self.regs.rcx, 4096) orelse "<unknown>";
        const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
        const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
        const assertion_class = classifyGuestAssertion(function_name, expression);
        // This is execution context, not a process-wide "last assertion".
        // The scheduler snapshots it with the guest registers so a UD2 on a
        // different thread cannot inherit this assertion's provenance.
        self.last_guest_assertion = .{
            .valid = true,
            .class = assertion_class,
            .step = self.executed_steps,
            .return_address = return_address,
            .thread = self.active_guest_thread,
        };
        const backend_binding = x64_backend_diagnostics.Engine.classifyAssertion(file_name, self.regs.rdx, function_name);
        self.backend_diagnostics.noteAssertion(backend_binding, self.executed_steps, return_address);
        const assertion_symbol = if (caller) |symbol| return_address -| symbol.offset else return_address;
        const assertion_variant = (self.regs.rdx << 8) | @intFromEnum(assertion_class);
        const assertion_observation = self.diagnostic_throttler.observe(
            .guest_assertion,
            assertion_symbol,
            assertion_variant,
        );
        if (assertion_observation.disposition == .checkpoint) {
            machoCapturePrint(
                "macho-processor: repeated guest assertion checkpoint: symbol={s} occurrence={d} suppressed_since_previous={d} total_assertions={d}\n",
                .{ if (caller) |symbol| symbol.name else function_name, assertion_observation.occurrence, assertion_observation.suppressed_since_emit, self.guest_assertion_count },
            );
        } else if (assertion_observation.disposition == .detail) {
            // Recorded as well as printed. A printed assertion is a line in a
            // log nobody re-reads; a ledger entry has to be classified before
            // the run can be called clean, which is what stops a permanently
            // non-zero counter from becoming invisible.
            if (comptime @hasField(@TypeOf(self.*), "anomalies")) {
                var detail_buffer: [120]u8 = undefined;
                const detail = std.fmt.bufPrint(
                    &detail_buffer,
                    "{s}:{d} {s}",
                    .{ file_name, self.regs.rdx, function_name },
                ) catch file_name;
                _ = self.anomalies.note(
                    .host_assertion,
                    detail,
                    self.executed_steps,
                    self.active_guest_thread,
                    return_address,
                );
            }
            machoCapturePrint(
                "macho-processor: guest assertion #{d}: {s}:{d} {s}: {s}\n",
                .{ self.guest_assertion_count, file_name, self.regs.rdx, function_name, expression },
            );
            machoCapturePrint(
                "  assertion context: step={d} phase={s} active=0x{x} return=0x{x} caller={s}+0x{x} rsp=0x{x} rbp=0x{x}\n",
                .{ self.executed_steps, @tagName(self.startup.phase), self.active_guest_thread, return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0, self.regs.rsp, self.regs.rbp },
            );
            if (backend_binding != .none) {
                machoCapturePrint(
                    "  x64 backend assertion binding: kind={s} backend_phase={s}\n",
                    .{ @tagName(backend_binding), @tagName(self.backend_diagnostics.phase) },
                );
                if (backend_binding == .x64_backend_capstone) {
                    machoCapturePrint(
                        "  x64 backend assertion cause: {s}:{d} is a cs_open(CS_ARCH_X86, CS_MODE_64, ...) failure branch in the x64 backend/assembler; this indicates optional Capstone initialization failure, not absence of the backend, compiler, or code cache\n",
                        .{ file_name, self.regs.rdx },
                    );
                    machoCapturePrint(
                        "  x64 backend assertion impact: Capstone-backed disassembly/introspection is unreliable until proven otherwise; subsequent backend/code-cache/processor success events will be logged as independent readiness evidence\n",
                        .{},
                    );
                    self.dumpCapstoneCallbackState("cs_open assertion");
                } else if (backend_binding == .x64_backend_low32_thunk) {
                    const mapping = self.backend_diagnostics.last_mapping;
                    machoCapturePrint(
                        "  x64 backend assertion cause: source line 438 requires resolve_function_thunk_ to fit in uint32_t because every indirection-table entry stores a 32-bit host-code pointer; the generated code cache was placed above the low 4 GiB window\n",
                        .{},
                    );
                    machoCapturePrint(
                        "  x64 backend assertion impact: continuing would truncate the thunk address and seed every default indirection with an invalid target; backend executable mappings must be rejected unless their end is at or below 0x100000000\n",
                        .{},
                    );
                    machoCapturePrint(
                        "  x64 backend low-address correlation: latest_mmap(valid/succeeded)={}/{} requested_address=0x{x} length={d} result=0x{x} result_high32=0x{x} stage={s}\n",
                        .{ mapping.valid, mapping.succeeded, mapping.address, mapping.length, mapping.result, mapping.result >> 32, if (mapping.stage.len != 0) mapping.stage else "<pending>" },
                    );
                }
                self.dumpGuestStack();
            }
            if (assertion_class == .timer_queue_wait_item_state) {
                machoCapturePrint(
                    "  timer queue assertion cause: TimerThreadMain expected WaitItem::State::kDisarmed before its compiler-emitted UD2; this is the primary invariant failure, and a following Processor::OnThreadBreakpointHit assertion is secondary signal-handler fallout\n",
                    .{},
                );
                machoCapturePrint(
                    "  timer queue assertion context: cooperative active_thread=0x{x} deferred_threads={d} suspended_threads={d} pending_idle={d}; inspect wait-item arm/disarm transitions before treating the breakpoint handler as the root cause\n",
                    .{ self.active_guest_thread, self.pthreads.deferred_threads, self.suspended_guest_thread_count, idleQueueSnapshotFor(&self.idle_callbacks).pending },
                );
                if (guest_assertion_recovery.timerQueueSnapshot(self, self.regs.rbp)) |snapshot| {
                    machoCapturePrint(
                        "  timer queue state snapshot: frame_state[{s}]={d} at 0x{x} shared_ptr_slot=0x{x} wait_item=0x{x} object_state={s} due_ns={?d} interval_ns={?d}\n",
                        .{ timerQueueStateName(snapshot.frame_state), snapshot.frame_state, snapshot.frame_state_address, snapshot.shared_ptr_address, snapshot.wait_item, if (snapshot.object_state) |state| timerQueueStateName(state) else "<unmapped>", snapshot.due_nanoseconds, snapshot.interval_nanoseconds },
                    );
                    if (snapshot.object_state) |object_state| {
                        if (object_state != snapshot.frame_state) {
                            machoCapturePrint(
                                "  timer queue state divergence: compare_exchange expected-output={s}({d}) but live wait_item state={s}({d}); this distinguishes decoder/CAS corruption from a genuinely concurrent state transition\n",
                                .{ timerQueueStateName(snapshot.frame_state), snapshot.frame_state, timerQueueStateName(object_state), object_state },
                            );
                        }
                    }
                    if (snapshot.wait_item != 0) {
                        self.timer_queue_watch.active = true;
                        self.timer_queue_watch.wait_item_addr = snapshot.wait_item;
                        self.timer_queue_watch.state_addr = snapshot.wait_item + 0x50;
                        self.timer_queue_watch.thread = self.active_guest_thread;
                        self.timer_queue_watch.logged_writes = 0;
                        machoCapturePrint(
                            "  timer queue state watch activated: watching addr=0x{x} (wait_item+0x50) for next 32 writes on any thread\n",
                            .{snapshot.wait_item + 0x50},
                        );
                    }
                } else {
                    machoCapturePrint(
                        "  timer queue state snapshot unavailable: rbp=0x{x}; retaining the assertion as non-recoverable because the modeled CAS state cannot be proven\n",
                        .{self.regs.rbp},
                    );
                }
            } else if (assertion_class == .breakpoint_untracked_thread) {
                machoCapturePrint(
                    "  breakpoint assertion cause: Processor::OnThreadBreakpointHit could not find the current modeled thread in Xenia's thread_debug_infos_ map; the backend exists, but this SIGILL arrived on a Rosette-cooperatively scheduled thread that Xenia's debugger registry does not track\n",
                    .{},
                );
                machoCapturePrint(
                    "  breakpoint assertion impact: this is a secondary failure while handling an earlier UD2. Any subsequent __Unwind_Resume(nullptr) belongs to the failed breakpoint-handler cleanup path and must not be mistaken for the original application fault\n",
                    .{},
                );
            } else if (assertion_class == .export_ordinal_bounds) {
                machoCapturePrint(
                    "  export ordinal bounds assertion: an export_entry->ordinal >= export_table.size(); the ordinal value exceeds the registered export count\n",
                    .{},
                );
                const saved = [_]u64{ self.regs.rbx, self.regs.r12, self.regs.r13, self.regs.r14, self.regs.r15 };
                var found_pair = false;
                for (saved) |a| {
                    if (a > 65535) continue;
                    for (saved) |b| {
                        if (b > 65535 or b < a) continue;
                        const ordinal = @as(u32, @intCast(a));
                        const size = @as(u32, @intCast(b));
                        if (ordinal < size) continue;
                        found_pair = true;
                        const recovery = self.export_table_mgr.diagnoseExportOrdinalBounds(ordinal, size, 0);
                        _ = self.export_table_lc.recordOrdinalBounds("xbdm", ordinal, size);
                        self.export_registry.register(ordinal, function_name, 0, true);
                        if (ordinal < 256 or (size < 256 and ordinal - size <= 16)) {
                            machoCapturePrint(
                                "  export ordinal bounds ROOT CAUSE: ordinal={d} >= table_size={d}; values are small and consistent — this is a guest-side export table sizing issue (the export table needs more entries or the ordinal needs updating)\n",
                                .{ ordinal, size },
                            );
                            if (recovery == .table_was_resized) {
                                machoCapturePrint(
                                    "  export table sizing recovery: export table manager recorded ordinal={d} size={d}; future assertions for this table will be tracked\n",
                                    .{ ordinal, size },
                                );
                            }
                            if (self.export_table_lc.module_count > 0 and
                                self.export_table_lc.modules[0].class == .deferred_exports)
                            {
                                const var_name = export_table_lifecycle.Lifecycle.extractVectorName(expression);
                                if (var_name) |vname| {
                                    const sym_addr = self.metadata.definedSymbolAddress(vname);
                                    if (sym_addr) |addr| {
                                        machoCapturePrint(
                                            "  export table pre-population: found vector={s} at 0x{x}; scheduling growth to size {d}\n",
                                            .{ vname, addr, ordinal + 1 },
                                        );
                                        _ = self.export_table_lc.requestVectorGrowth(addr, ordinal + 1, 8, vname);
                                    } else {
                                        var sym_buf: [1]u64 = undefined;
                                        const found = self.metadata.symbolAddressesMatching("", vname, &sym_buf);
                                        if (found > 0 and sym_buf[0] != 0) {
                                            _ = self.export_table_lc.requestVectorGrowth(sym_buf[0], ordinal + 1, 8, vname);
                                            machoCapturePrint(
                                                "  export table pre-population: found vector={s} at 0x{x} via substring match; scheduling growth to size {d}\n",
                                                .{ vname, sym_buf[0], ordinal + 1 },
                                            );
                                        } else {
                                            machoCapturePrint(
                                                "  export table pre-population: vector={s} not found in symbol table; will fall back to defer+retry\n",
                                                .{vname},
                                            );
                                        }
                                    }
                                }
                            }
                        } else {
                            machoCapturePrint(
                                "  export ordinal bounds ROOT CAUSE: ordinal={d} >= table_size={d}; values are large or unexpected — this is likely emulator-level memory corruption or a data-structure initialization failure\n",
                                .{ ordinal, size },
                            );
                        }
                    }
                }
                if (!found_pair) {
                    _ = self.export_table_mgr.recordTable(0, 0, 0);
                    machoCapturePrint(
                        "  export ordinal bounds: no plausible ordinal/size pair found in callee-saved registers (rbx/r12-r15); the values were either computed per-call and not preserved, or the register state was already clobbered\n",
                        .{},
                    );
                    machoCapturePrint(
                        "  export ordinal bounds raw register state: rbx=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x}\n",
                        .{ self.regs.rbx, self.regs.r12, self.regs.r13, self.regs.r14, self.regs.r15 },
                    );
                }
            }
        }
        if (self.initializer_resolver.current()) |initializer| {
            machoCapturePrint(
                "  assertion owner: initializer [{d}/{d}] {s}\n",
                .{ initializer.index + 1, self.metadata.initializer_addresses.len, initializer.symbol },
            );
            self.initializer_abort_requested = true;
            if (self.initializer_abort_reason == .none) self.initializer_abort_reason = .assertion;
        }
        const continuation = if (return_address != 0)
            self.guestMemoryConst(return_address, 16)
        else
            null;
        if (continuation == null or
            guest_assertion_recovery.isUnsafeNoreturnContinuation(continuation.?))
        {
            machoCapturePrint(
                "macho-processor: noreturn assertion continuation rejected: return=0x{x} bytes={any}; the compiler emitted padding/trap or no readable continuation, so Rosette will not fall through into an adjacent function\n",
                .{ return_address, if (continuation) |bytes| bytes[0..@min(bytes.len, 8)] else &[_]u8{} },
            );
            self.faulted = true;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.runtime_invariant_failure);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }
        return .{ .handled = 0 };
    }

    if ((name_hash == importNameHash("_strcmp") and std.mem.eql(u8, name, "_strcmp"))) {
        const lhs = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
        const rhs = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
        const ordering = std.mem.order(u8, lhs, rhs);
        const result: i32 = switch (ordering) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
        return .{ .handled = @as(u32, @bitCast(result)) };
    }
    if ((name_hash == importNameHash("_strcasecmp") and std.mem.eql(u8, name, "_strcasecmp"))) {
        const lhs = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
        const rhs = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
        const shared = @min(lhs.len, rhs.len);
        for (0..shared) |index| {
            const left = std.ascii.toLower(lhs[index]);
            const right = std.ascii.toLower(rhs[index]);
            if (left != right) {
                const result: i32 = if (left < right) -1 else 1;
                return .{ .handled = @as(u32, @bitCast(result)) };
            }
        }
        const result: i32 = if (lhs.len < rhs.len) -1 else if (lhs.len > rhs.len) 1 else 0;
        return .{ .handled = @as(u32, @bitCast(result)) };
    }
    if ((name_hash == importNameHash("_strcpy") and std.mem.eql(u8, name, "_strcpy"))) {
        const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
        const destination = self.guestMemory(self.regs.rdi, source.len + 1) orelse return .{ .unsupported = 0 };
        const mutation = self.captureMemoryMutation(self.regs.rdi, source.len + 1);
        @memcpy(destination[0..source.len], source);
        destination[source.len] = 0;
        self.commitMemoryMutation(mutation, .bulk_copy);
        return .{ .handled = self.regs.rdi };
    }
    if ((name_hash == importNameHash("_strtoul") and std.mem.eql(u8, name, "_strtoul"))) {
        self.resolving_import_route = .strtoul;
        const nptr = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .handled = 0 };
        const endptr_ptr = self.regs.rsi;
        const base_raw = self.regs.rdx;
        if (base_raw > 36) {
            if (endptr_ptr != 0) self.write64(endptr_ptr, self.regs.rdi);
            return .{ .handled = 0 };
        }
        const base: u8 = @intCast(base_raw);
        var i: usize = 0;
        while (i < nptr.len and switch (nptr[i]) {
            ' ', '\t', '\n', '\r', '\x0c' => true,
            else => false,
        }) i += 1;
        var negate = false;
        if (i < nptr.len) {
            if (nptr[i] == '-') {
                negate = true;
                i += 1;
            } else if (nptr[i] == '+') i += 1;
        }
        var effective_base: u8 = base;
        if (effective_base == 0 or effective_base == 16) {
            if (i + 2 < nptr.len and nptr[i] == '0' and (nptr[i + 1] | 32) == 'x') {
                effective_base = 16;
                i += 2;
            }
        }
        if (effective_base == 0 and i < nptr.len and nptr[i] == '0') effective_base = 8;
        if (effective_base == 0) effective_base = 10;
        const start = i;
        var result: u64 = 0;
        var overflow = false;
        while (i < nptr.len) {
            const c = nptr[i];
            const digit: u64 = switch (c) {
                '0'...'9' => c - '0',
                'a'...'z' => c - 'a' + 10,
                'A'...'Z' => c - 'A' + 10,
                else => break,
            };
            if (digit >= effective_base) break;
            const next = result * effective_base;
            overflow = overflow or (effective_base > 0 and next / effective_base != result);
            result = next;
            const next2 = result +% digit;
            overflow = overflow or next2 < result;
            result = next2;
            i += 1;
        }
        if (i == start) {
            if (endptr_ptr != 0) self.write64(endptr_ptr, 0);
            return .{ .handled = 0 };
        }
        if (endptr_ptr != 0) self.write64(endptr_ptr, self.regs.rdi + i);
        if (overflow) return .{ .handled = std.math.maxInt(u64) };
        if (negate) return .{ .handled = @bitCast(@as(i64, -@as(i64, @bitCast(result)))) };
        return .{ .handled = result };
    }
    if ((name_hash == importNameHash("_getenv") and std.mem.eql(u8, name, "_getenv"))) {
        const key = self.guestCString(self.regs.rdi, 256) orelse return .{ .handled = 0 };
        const raw = if (std.mem.eql(u8, key, "HOME"))
            std.c.getenv("HOME")
        else if (std.mem.eql(u8, key, "XDG_DATA_HOME"))
            std.c.getenv("XDG_DATA_HOME")
        else if (std.mem.eql(u8, key, "TMPDIR"))
            std.c.getenv("TMPDIR")
        else if (std.mem.eql(u8, key, "USER"))
            std.c.getenv("USER")
        else if (std.mem.eql(u8, key, "PATH"))
            std.c.getenv("PATH")
        else
            null;
        const host_value = raw orelse return .{ .handled = 0 };
        const value = std.mem.sliceTo(host_value, 0);
        const allocation = self.guestAlloc(value.len + 1, 1) orelse return .{ .handled = 0 };
        if (!self.guestWriteCString(allocation, value)) return .{ .handled = 0 };
        return .{ .handled = allocation };
    }
    if ((name_hash == importNameHash("_getpwuid_r") and std.mem.eql(u8, name, "_getpwuid_r"))) {
        if (self.regs.r8 != 0) self.write64(self.regs.r8, 0);
        return .{ .handled = 2 };
    }
    if ((name_hash == importNameHash("___error") and std.mem.eql(u8, name, "___error"))) {
        if (self.guest_errno_address == 0) {
            self.guest_errno_address = self.guestAlloc(@sizeOf(c_int), @alignOf(c_int)) orelse return .{ .unsupported = 0 };
        }
        return .{ .handled = self.guest_errno_address };
    }

    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEPKcm") != null) {
        const ok = compat_runtime.initLibcppString(self, self.regs.rdi, self.regs.rsi, self.regs.rdx);
        if (self.verbose_trace) machoCapturePrint(
            "    [libc++] basic_string::__init(this=0x{x}, source=0x{x}, length={d}) -> {}\n",
            .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, ok },
        );
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6assignEPKc") != null) {
        const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
        const ok = compat_runtime.assignLibcppStringFromBytes(self, self.regs.rdi, self.regs.rsi, source.len);
        if (self.verbose_trace) machoCapturePrint(
            "    [libc++] basic_string::assign(this=0x{x}, source=0x{x}, length={d}) -> {}\n",
            .{ self.regs.rdi, self.regs.rsi, source.len, ok },
        );
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6resizeEmc") != null) {
        const ok = compat_runtime.resizeLibcppString(self, self.regs.rdi, self.regs.rsi, @truncate(self.regs.rdx));
        return if (ok) .handled_void else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEaSEc") != null) {
        const value = [_]u8{@truncate(self.regs.rsi)};
        const ok = compat_runtime.assignLibcppStringLiteral(self, self.regs.rdi, &value);
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKcm") != null) {
        const ok = compat_runtime.appendLibcppString(self, self.regs.rdi, self.regs.rsi, self.regs.rdx);
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKc") != null) {
        const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
        const ok = compat_runtime.appendLibcppString(self, self.regs.rdi, self.regs.rsi, source.len);
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6insertEmPKc") != null) {
        const source = self.guestCString(self.regs.rdx, 1 << 20) orelse return .{ .unsupported = 0 };
        const ok = compat_runtime.insertLibcppString(self, self.regs.rdi, self.regs.rsi, self.regs.rdx, source.len);
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE9__grow_byEmmmmmm") != null) {
        const inserted_size = self.read64(self.regs.rsp + 8);
        const ok = compat_runtime.growLibcppString(
            self,
            self.regs.rdi,
            self.regs.rsi,
            self.regs.rdx,
            self.regs.rcx,
            self.regs.r8,
            self.regs.r9,
            inserted_size,
        );
        return if (ok) .{ .handled = 0 } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEC1ERKS5_") != null or
        std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEC2ERKS5_") != null)
    {
        const ok = compat_runtime.copyLibcppString(self, self.regs.rdi, self.regs.rsi);
        if (!ok) {
            const source_view = compat_runtime.libcppStringView(self, self.regs.rsi);
            const source_data_mapped = if (source_view) |view|
                self.guestMemoryConst(view.address, view.length) != null
            else
                false;
            const State = @typeInfo(@TypeOf(self)).pointer.child;
            const heap_next = if (comptime @hasField(State, "heap_next"))
                self.heap_next
            else
                0;
            machoCapturePrint(
                "macho-processor: libc++ string copy rejected: destination=0x{x} source=0x{x} destination_mapped={} source_mapped={} source_data=0x{x} source_length={d} source_data_mapped={} heap_next=0x{x} likely_stage={s}\n",
                .{
                    self.regs.rdi,
                    self.regs.rsi,
                    self.guestMemoryConst(self.regs.rdi, 24) != null,
                    self.guestMemoryConst(self.regs.rsi, 24) != null,
                    if (source_view) |view| view.address else 0,
                    if (source_view) |view| view.length else 0,
                    source_data_mapped,
                    heap_next,
                    if (source_data_mapped and
                        (if (source_view) |view| view.length >= 23 else false))
                        "long_string_destination_allocation"
                    else
                        "source_validation",
                },
            );
        }
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEaSERKS5_") != null) {
        const ok = compat_runtime.assignLibcppString(self, self.regs.rdi, self.regs.rsi);
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "__ZNSt3__1plIcNS_11char_traitsIcEENS_9allocatorIcEEEENS_12basic_stringIT_T0_T1_EEPKS6_RKS9_") != null) {
        const left = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
        const ok = compat_runtime.concatCStringAndLibcppString(self, self.regs.rdi, self.regs.rsi, left.len, self.regs.rdx);
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev") != null or
        std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev") != null)
    {
        const ok = compat_runtime.destroyLibcppString(self, self.regs.rdi);
        return if (ok) .{ .handled = 0 } else .{ .unsupported = 0 };
    }
    if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE4findEcm") != null) {
        const string = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
        const bytes = self.guestMemoryConst(string.address, string.length) orelse return .{ .unsupported = 0 };
        const start: usize = @intCast(@min(self.regs.rdx, string.length));
        const needle: u8 = @truncate(self.regs.rsi);
        const found = std.mem.indexOfScalarPos(u8, bytes, start, needle) orelse return .{ .handled = std.math.maxInt(u64) };
        return .{ .handled = found };
    }
    if ((name_hash == importNameHash("__ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE7compareEPKc") and std.mem.eql(u8, name, "__ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE7compareEPKc"))) {
        const rhs = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
        const result = compat_runtime.compareLibcppStringWithBytes(self, self.regs.rdi, self.regs.rsi, rhs.len) orelse
            return .{ .unsupported = 0 };
        if (self.verbose_trace) {
            machoCapturePrint(
                "    [libc++] basic_string::compare(this=0x{x}, rhs=0x{x}, rhs_length={d}) -> {d}\n",
                .{ self.regs.rdi, self.regs.rsi, rhs.len, result },
            );
        }
        return .{ .handled = @as(u32, @bitCast(result)) };
    }

    if ((name_hash == importNameHash("___cxa_guard_acquire") and std.mem.eql(u8, name, "___cxa_guard_acquire"))) {
        const result = compat_runtime.cxaGuardAcquire(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
        // Track the guard address so we can clear it on initializer deferral
        self.guard_rollback.track(self.regs.rdi);
        return .{ .handled = result };
    }
    if ((name_hash == importNameHash("___cxa_guard_release") and std.mem.eql(u8, name, "___cxa_guard_release"))) {
        return if (compat_runtime.cxaGuardRelease(self, self.regs.rdi)) .{ .handled = 0 } else .{ .unsupported = 0 };
    }
    if ((name_hash == importNameHash("___cxa_guard_abort") and std.mem.eql(u8, name, "___cxa_guard_abort"))) {
        return if (compat_runtime.cxaGuardAbort(self, self.regs.rdi)) .{ .handled = 0 } else .{ .unsupported = 0 };
    }
    if ((name_hash == importNameHash("___cxa_atexit") and std.mem.eql(u8, name, "___cxa_atexit"))) {
        const registered = self.compat.registerAtexit(self.regs.rdi, self.regs.rsi, self.regs.rdx);
        if (self.verbose_trace) machoCapturePrint(
            "    [c++] __cxa_atexit(function=0x{x}, argument=0x{x}, dso=0x{x}) -> {}\n",
            .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, registered },
        );
        return .{ .handled = if (registered) 0 else 1 };
    }
    if ((name_hash == importNameHash("_atexit") and std.mem.eql(u8, name, "_atexit"))) {
        const registered = self.compat.registerPlainAtexit(self.regs.rdi);
        if (self.verbose_trace) {
            machoCapturePrint(
                "    [posix] atexit(function=0x{x}) -> {}\n",
                .{ self.regs.rdi, registered },
            );
        }
        return .{ .handled = if (registered) 0 else 1 };
    }
    if ((name_hash == importNameHash("__ZNSt3__112__next_primeEm") and std.mem.eql(u8, name, "__ZNSt3__112__next_primeEm"))) {
        return .{ .handled = nextPrime(self.regs.rdi) };
    }
    if ((name_hash == importNameHash("__ZNSt3__18ios_base6xallocEv") and std.mem.eql(u8, name, "__ZNSt3__18ios_base6xallocEv"))) {
        const slot = self.ios_xalloc_next;
        self.ios_xalloc_next +%= 1;
        return .{ .handled = slot };
    }
    if ((name_hash == importNameHash("__ZNSt3__16chrono12system_clock3nowEv") and std.mem.eql(u8, name, "__ZNSt3__16chrono12system_clock3nowEv"))) {
        return .{ .handled = self.guest_time.wallNow() };
    }
    if (libcpp_thread.classify(name)) |operation| {
        if (self.write_diagnostics_armed) {
            const caller = importCallerAddress(self);
            if (self.memory_forwarder.containingAllocation(self.regs.rdi)) |allocation| {
                machoCapturePrint(
                    "macho-processor: libc++ thread-struct ABI: operation={s} this=0x{x} size={d} allocation_base=0x{x} allocation_size={d} member_offset=0x{x} caller=0x{x} {s}+0x{x} step={d} thread=0x{x}\n",
                    .{
                        @tagName(operation),
                        self.regs.rdi,
                        libcpp_thread.storage_size,
                        allocation.base,
                        allocation.size,
                        allocation.offset,
                        caller,
                        self.metadata.symbolLabel(caller),
                        if (self.metadata.nearestSymbol(caller)) |symbol| symbol.offset else 0,
                        self.executed_steps,
                        self.active_guest_thread,
                    },
                );
            } else {
                machoCapturePrint(
                    "macho-processor: libc++ thread-struct ABI: operation={s} this=0x{x} size={d} allocation=<none> caller=0x{x} {s}+0x{x} step={d} thread=0x{x}\n",
                    .{
                        @tagName(operation),
                        self.regs.rdi,
                        libcpp_thread.storage_size,
                        caller,
                        self.metadata.symbolLabel(caller),
                        if (self.metadata.nearestSymbol(caller)) |symbol| symbol.offset else 0,
                        self.executed_steps,
                        self.active_guest_thread,
                    },
                );
            }
        }
        return switch (operation) {
            .construct => blk: {
                _ = self.fillGuestMemory(self.regs.rdi, libcpp_thread.storage_size, 0);
                break :blk .{ .handled = self.regs.rdi };
            },
            // Construction is intercepted and creates no native libc++ TLS
            // list, so destruction is intentionally empty. This closes the
            // ownership pair instead of leaving D1/D2 as unresolved imports.
            .destroy => .handled_void,
        };
    }
    if ((name_hash == importNameHash("__ZNKSt3__14__fs10filesystem4path16__root_directoryEv") and std.mem.eql(u8, name, "__ZNKSt3__14__fs10filesystem4path16__root_directoryEv"))) {
        const path = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
        const bytes = self.guestMemoryConst(path.address, path.length) orelse return .{ .unsupported = 0 };
        self.regs.rdx = @intFromBool(bytes.len != 0 and bytes[0] == '/');
        return .{ .handled = path.address };
    }
    if ((name_hash == importNameHash("__ZNKSt3__14__fs10filesystem4path10__filenameEv") and std.mem.eql(u8, name, "__ZNKSt3__14__fs10filesystem4path10__filenameEv"))) {
        const path = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
        const bytes = self.guestMemoryConst(path.address, path.length) orelse return .{ .unsupported = 0 };
        const start = if (std.mem.lastIndexOfScalar(u8, bytes, '/')) |separator| separator + 1 else 0;
        self.regs.rdx = bytes.len - start;
        return .{ .handled = path.address + start };
    }
    if ((name_hash == importNameHash("__ZNKSt3__14__fs10filesystem4path13__parent_pathEv") and std.mem.eql(u8, name, "__ZNKSt3__14__fs10filesystem4path13__parent_pathEv"))) {
        const path = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
        const bytes = self.guestMemoryConst(path.address, path.length) orelse return .{ .unsupported = 0 };
        var end = bytes.len;
        while (end > 1 and bytes[end - 1] == '/') end -= 1;
        const parent_length = if (std.mem.lastIndexOfScalar(u8, bytes[0..end], '/')) |separator|
            if (separator == 0) @as(usize, 1) else separator
        else
            0;
        self.regs.rdx = parent_length;
        return .{ .handled = path.address };
    }

    if ((name_hash == importNameHash("___dynamic_cast") and std.mem.eql(u8, name, "___dynamic_cast"))) {
        if (self.dynamic_casts.resolve(
            self,
            self.regs.rdi,
            self.regs.rsi,
            self.regs.rdx,
            self.regs.rcx,
        )) |resolution| {
            return .{ .handled = resolution.address };
        }
        const return_address = self.read64(self.regs.rsp);
        if (self.metadata.nearestSymbol(return_address)) |caller| {
            if (std.mem.indexOf(u8, caller.name, "cxxopts") != null and
                std.mem.indexOf(u8, caller.name, "OptionValue2as") != null)
            {
                return .{ .handled = self.regs.rdi };
            }
        }
        // Reached only when the engine could not decide. A cast that correctly
        // returns null — because the destination is not an unambiguous public
        // base of the dynamic type, or is only reachable privately, or is
        // reachable two ways — now resolves as `.proven_negative` and never
        // arrives here. So this message means what it says instead of firing on
        // every legitimate type test a program performs.
        const report = self.dynamic_casts.metadataFailureReportDecision(
            self.regs.rsi,
            self.regs.rdx,
            self.regs.rcx,
        );
        if (report.emit) {
            self.dynamic_casts.dumpTraceBuffer(self);
            const reason = self.dynamic_casts.undecidedReason();
            machoCapturePrint(
                "macho-processor: __dynamic_cast UNDECIDABLE: source=0x{x} source_type=0x{x} destination_type=0x{x} hint={d} reason={s} occurrence={d} suppressed_total={d}; {s}, so null is a fallback and NOT the language's answer. A caller that branches on this null is branching on a guess. Repeats of this same type pair are summarized logarithmically\n",
                .{
                    self.regs.rdi,
                    self.regs.rsi,
                    self.regs.rdx,
                    @as(i64, @bitCast(self.regs.rcx)),
                    if (reason) |value| @tagName(value) else "unrecorded",
                    report.occurrence,
                    report.suppressed_total,
                    if (reason) |value| value.describe() else "the engine recorded no reason",
                },
            );
        }
        return .{ .handled = 0 };
    }

    if ((name_hash == importNameHash("__ZNSt3__16localeC1Ev") and std.mem.eql(u8, name, "__ZNSt3__16localeC1Ev")) or (name_hash == importNameHash("__ZNSt3__16localeC2Ev") and std.mem.eql(u8, name, "__ZNSt3__16localeC2Ev"))) {
        const ok = self.compat.initLocale(self, self.regs.rdi, null);
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if ((name_hash == importNameHash("__ZNSt3__16localeC1ERKS0_") and std.mem.eql(u8, name, "__ZNSt3__16localeC1ERKS0_")) or (name_hash == importNameHash("__ZNSt3__16localeC2ERKS0_") and std.mem.eql(u8, name, "__ZNSt3__16localeC2ERKS0_"))) {
        const ok = self.compat.initLocale(self, self.regs.rdi, self.regs.rsi);
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if ((name_hash == importNameHash("__ZNSt3__16localeD1Ev") and std.mem.eql(u8, name, "__ZNSt3__16localeD1Ev")) or (name_hash == importNameHash("__ZNSt3__16localeD2Ev") and std.mem.eql(u8, name, "__ZNSt3__16localeD2Ev"))) {
        return if (self.compat.destroyLocale(self, self.regs.rdi)) .{ .handled = 0 } else .{ .unsupported = 0 };
    }
    // XModule constructors — Xenia-specific. Self-gating for non-Xenia
    // binaries (only triggered when guest has XModule symbols).
    if (self.has_xenia_compat and
        (std.mem.indexOf(u8, name, "7XModuleC1") != null or
            std.mem.indexOf(u8, name, "7XModuleC2") != null))
    {
        const xmodule_vtable = self.ensureXmoduleVtable() orelse 0;
        if (xmodule_vtable != 0) {
            self.write64(self.regs.rdi, xmodule_vtable);
        }
        return .{ .handled = self.regs.rdi };
    }
    if ((name_hash == importNameHash("__ZNKSt3__16locale9use_facetERNS0_2idE") and std.mem.eql(u8, name, "__ZNKSt3__16locale9use_facetERNS0_2idE"))) {
        const return_address = self.read64(self.regs.rsp);
        const caller_name = if (self.metadata.nearestSymbol(return_address)) |caller| caller.name else "";
        const kind: compat_runtime.LocaleFacetKind = if (std.mem.indexOf(u8, caller_name, "ctype") != null)
            .ctype
        else if (std.mem.indexOf(u8, caller_name, "collate") != null)
            .collate
        else
            .generic;
        const key = self.regs.rsi ^ (@as(u64, @intFromEnum(kind)) << 56);
        const facet = self.compat.localeFacet(self, key, kind) orelse return .{ .unsupported = 0 };
        return .{ .handled = facet };
    }
    if ((name_hash == importNameHash("__ZNKSt3__16locale4nameEv") and std.mem.eql(u8, name, "__ZNKSt3__16locale4nameEv"))) {
        const ok = compat_runtime.initLibcppStringLiteral(self, self.regs.rdi, "C");
        return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if ((name_hash == importNameHash("__ZNSt3__115__get_classnameEPKcb") and std.mem.eql(u8, name, "__ZNSt3__115__get_classnameEPKcb"))) {
        const class_name = self.guestCString(self.regs.rdi, 64) orelse return .{ .unsupported = 0 };
        const mask = compat_runtime.libcppRegexClassMask(class_name, self.regs.rsi != 0);
        return .{ .handled = mask };
    }
    if ((name_hash == importNameHash("___cxa_allocate_exception") and std.mem.eql(u8, name, "___cxa_allocate_exception"))) {
        const object_size = self.regs.rdi;
        const allocation = self.memory_forwarder.allocate(self, object_size +| 64, 16) orelse return .{ .unsupported = 0 };
        const object_address = allocation + 64;
        self.cxx_exceptions.recordAllocation(allocation, object_address, object_size, self.read64(self.regs.rsp));
        return .{ .handled = object_address };
    }
    if ((name_hash == importNameHash("___cxa_begin_catch") and std.mem.eql(u8, name, "___cxa_begin_catch"))) {
        const object_address = self.cxx_exceptions.beginCatch(self.regs.rdi);
        machoCapturePrint("macho-processor: __cxa_begin_catch object=0x{x}\n", .{object_address});
        if (comptime @hasField(@TypeOf(self.*), "guest_exceptions")) {
            self.guest_exceptions.noteCaught(self.executed_steps);
        }
        return .{ .handled = object_address };
    }
    if ((name_hash == importNameHash("___cxa_end_catch") and std.mem.eql(u8, name, "___cxa_end_catch"))) {
        const catch_result = self.cxx_exceptions.endCatch();
        if (catch_result) |ended| {
            const object = ended.object_address;
            machoCapturePrint("macho-processor: __cxa_end_catch object=0x{x}\n", .{object});
            if (ended.rethrow_in_progress) {
                machoCapturePrint(
                    "macho-processor: Itanium rethrow handler ended: object=0x{x}; phase-two checkpoint retained for _Unwind_Resume\n",
                    .{object},
                );
            } else {
                if (self.unwinder.completeCatch()) {
                    machoCapturePrint(
                        "macho-processor: Itanium catch transaction completed: object=0x{x}; phase-two checkpoint retired\n",
                        .{object},
                    );
                }
                const spirv_resolution = self.spirv_cross.noteCatch(object);
                if (spirv_resolution == .expected_dummy_probe_caught) {
                    machoCapturePrint(
                        "macho-processor: SPIRV-Cross dummy-module probe resolved: object=0x{x} entry_point_expected=false handler_completed=true; this exception is verified startup history, not a hang cause\n",
                        .{object},
                    );
                }
            }
        }
        return .handled_void;
    }
    if ((name_hash == importNameHash("___cxa_get_exception_ptr") and std.mem.eql(u8, name, "___cxa_get_exception_ptr"))) {
        return .{ .handled = self.cxx_exceptions.exceptionPointer(self.regs.rdi) };
    }
    if ((name_hash == importNameHash("___cxa_free_exception") and std.mem.eql(u8, name, "___cxa_free_exception"))) {
        if (self.cxx_exceptions.freeException(self.regs.rdi)) |allocation| {
            self.memory_forwarder.releaseFrom(allocation.storage_address, self.regs.rip);
            self.vtable_tracker.forgetAddress(allocation.storage_address);
        }
        return .handled_void;
    }
    if ((name_hash == importNameHash("__ZNSt20bad_array_new_lengthC1Ev") and std.mem.eql(u8, name, "__ZNSt20bad_array_new_lengthC1Ev"))) {
        return .{ .handled = self.regs.rdi };
    }
    if ((name_hash == importNameHash("___cxa_throw") and std.mem.eql(u8, name, "___cxa_throw"))) {
        const thrown = self.cxx_exceptions.recordThrow(
            self.regs.rdi,
            self.regs.rsi,
            self.regs.rdx,
            self.read64(self.regs.rsp),
        );
        machoCapturePrint(
            "macho-processor: guest raised C++ exception object=0x{x} type_info=0x{x} destructor=0x{x}\n",
            .{ self.regs.rdi, self.regs.rsi, self.regs.rdx },
        );
        var toml_parse_error = false;
        var exception_type_name: []const u8 = "";
        var exception_message: []const u8 = "";
        if (self.cxxExceptionTypeName(thrown.type_info_address)) |type_name| {
            exception_type_name = type_name;
            machoCapturePrint("macho-processor: C++ exception ABI type name: {s}\n", .{type_name});
            if (std.mem.eql(u8, type_name, "N5Xbyak5ErrorE")) {
                // Xbyak::Error is a 16-byte std::exception-derived object in
                // this build: vptr at +0, integer error code at +8. Reading
                // the field directly avoids requiring a synthetic virtual
                // `what()` call while the object is actively unwinding.
                const error_code: i32 = @bitCast(self.read32(thrown.object_address + 8));
                // The label errors are the ones that matter here and were the
                // ones missing: code 11 is what a run reports when the emitter
                // referenced a label it never bound, and it read as
                // "unclassified" while being the most specific diagnosis
                // available anywhere in the run.
                const error_name: []const u8 = switch (error_code) {
                    1 => "bad addressing",
                    2 => "code is too big",
                    3 => "bad scale",
                    4 => "esp cannot be an index",
                    5 => "bad combination",
                    6 => "bad register size",
                    7 => "immediate is too big",
                    8 => "bad align",
                    9 => "label is redefined",
                    10 => "label is too far",
                    11 => "label is not found — the emitter referenced a label it never bound, so the function it was assembling cannot be finalized and is abandoned",
                    13 => "bad parameter",
                    17 => "memory size is not specified",
                    18 => "bad memory size",
                    21 => "cannot allocate",
                    else => "unclassified Xbyak error",
                };
                machoCapturePrint(
                    "macho-processor: Xbyak exception detail: code={d} reason='{s}' object=0x{x}\n",
                    .{ error_code, error_name, thrown.object_address },
                );
            }
            if (std.mem.indexOf(u8, type_name, "toml") != null and
                std.mem.indexOf(u8, type_name, "parse_error") != null)
            {
                toml_parse_error = true;
            }
        }
        // Recorded here because this is the only place the type name, the
        // emulator-specific error code and the throw site all exist at once.
        // At the catch site the object is already being unwound and at the
        // crash site none of it survives.
        if (comptime @hasField(@TypeOf(self.*), "guest_exceptions")) {
            var site_buffer: [96]u8 = undefined;
            var site_text: []const u8 = "";
            if (self.diagnosticSymbol(thrown.caller_address)) |throw_site| {
                site_text = std.fmt.bufPrint(&site_buffer, "{s}+0x{x}", .{
                    throw_site.symbol,
                    throw_site.symbol_offset,
                }) catch throw_site.symbol;
            }
            const reported_code: u32 = if (std.mem.eql(u8, exception_type_name, "N5Xbyak5ErrorE"))
                self.read32(thrown.object_address + 8)
            else
                0;
            const first_sight = self.guest_exceptions.noteThrow(
                if (exception_type_name.len != 0) exception_type_name else "<unnamed>",
                site_text,
                reported_code,
                0,
                self.executed_steps,
            );
            if (first_sight) machoCapturePrint(
                "macho-processor: GUEST EXCEPTION PREDICTOR: first_sight type={s} code={d} site={s} step={d}; a type thrown for the first time is a new behaviour. Whether it is a problem depends entirely on what happens after the catch, which the exception machinery cannot see\n",
                .{ if (exception_type_name.len != 0) exception_type_name else "<unnamed>", reported_code, site_text, self.executed_steps },
            );
        }
        if (self.metadata.nearestSymbol(thrown.type_info_address)) |symbol| {
            machoCapturePrint("macho-processor: C++ exception type: {s}+0x{x}\n", .{ symbol.name, symbol.offset });
        }
        if (self.metadata.nearestSymbol(thrown.destructor_address)) |symbol| {
            machoCapturePrint("macho-processor: C++ exception destructor: {s}+0x{x}\n", .{ symbol.name, symbol.offset });
        }
        if (self.diagnosticSymbol(thrown.caller_address)) |throw_site| {
            machoCapturePrint("macho-processor: C++ exception throw site: {s}+0x{x} (0x{x})\n", .{
                throw_site.symbol,
                throw_site.symbol_offset,
                throw_site.address,
            });
        }
        if (thrown.allocation) |allocation| {
            if (self.diagnosticSymbol(allocation.caller_address)) |allocation_site| {
                machoCapturePrint("macho-processor: C++ exception allocation site: {s}+0x{x} (size={d})\n", .{
                    allocation_site.symbol,
                    allocation_site.symbol_offset,
                    allocation.object_size,
                });
            }
        }
        // Throw-site machine state. A throw says a condition was detected; it
        // does not say whether the condition was real. Deciding that needs the
        // operands the throwing frame was working from — for a range-decode
        // throw, whether the iterator and end pointers were actually degenerate
        // or merely reported so. Without this the type name and call stack are
        // the whole record, and both are identical for a genuine throw and for
        // one produced by a mismodelled operand.
        //
        // Unconditional because a throw is rare by construction: this is not on
        // any hot path, and the state is unrecoverable once phase two rewrites
        // the register file to enter a landing pad.
        machoCapturePrint(
            "macho-processor: C++ exception throw-site state: thread=0x{x} rip=0x{x} rsp=0x{x} rbp=0x{x} rdi=0x{x} rsi=0x{x} rdx=0x{x} rcx=0x{x} r8=0x{x} r9=0x{x} rax=0x{x} rbx=0x{x}\n",
            .{
                self.active_guest_thread,
                self.regs.rip,
                self.regs.rsp,
                self.regs.rbp,
                self.regs.rdi,
                self.regs.rsi,
                self.regs.rdx,
                self.regs.rcx,
                self.regs.r8,
                self.regs.r9,
                self.regs.rax,
                self.regs.rbx,
            },
        );
        if (self.cxxExceptionMessage(thrown.object_address)) |message| {
            exception_message = message;
            machoCapturePrint("macho-processor: C++ exception message: {s}\n", .{message});
            if (std.mem.indexOf(u8, message, "invalid utf-8") != null or
                std.mem.indexOf(u8, message, "invalid UTF-8") != null or
                std.mem.indexOf(u8, message, "utf-8") != null)
            {
                toml_parse_error = true;
            }
        }
        if (toml_parse_error) {
            self.libcxx_streams.dumpPatchTomlDiagnostics("toml parse_error throw");
        }
        var inspection = self.unwinder.inspectThrow(self, thrown.type_info_address);
        const exception_header = if (thrown.allocation) |allocation|
            allocation.storage_address
        else
            thrown.object_address;
        const phase_two_installed = self.unwinder.installPhaseTwo(self, &inspection, exception_header);
        const spirv_classification = self.spirv_cross.noteThrow(thrown.object_address, .{
            .type_name = exception_type_name,
            .message = exception_message,
            .verification_frame_seen = spirv_cross_diagnostics.verificationFrameSeen(&self.metadata, inspection),
            .handler_found = inspection.handler != null,
            .phase_two_installed = phase_two_installed,
            .catch_completed = false,
        });
        if (spirv_classification == .expected_dummy_probe_unwinding) {
            machoCapturePrint(
                "macho-processor: SPIRV-Cross dummy-module probe recognized: object=0x{x} missing_entry_point=true verification_frame=true handler=0x{x} phase_two_installed=true; awaiting expected catch completion\n",
                .{ thrown.object_address, if (inspection.handler) |handler| handler.landing_pad else 0 },
            );
        }
        // An exception phase one could not match is the interesting case even
        // when phase two installs cleanups and the run continues: the frames
        // unwind, some catch-all consumes it, and the thread quietly ends. The
        // only trace left was an ordinary "guest thread returned" line, which
        // is what a clean exit produces too. Remember it against the thread so
        // the return can say what actually happened.
        if (inspection.handler == null) {
            self.unhandled_cxx_thread = self.active_guest_thread;
            self.unhandled_cxx_type_info = thrown.type_info_address;
        }
        if (phase_two_installed) {
            self.last_unwind_inspection = inspection;
            return .control_transferred;
        }
        self.last_unwind_inspection = inspection;
        if (inspection.handler != null) {
            machoCapturePrint("macho-processor: stopping after verified phase-1 catch discovery because this frame layout is not phase-2 safe\n", .{});
        } else {
            machoCapturePrint("macho-processor: stopping after Itanium phase-1 found no matching catch handler\n", .{});
        }
        self.dumpGuestStack();
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
        return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
    }
    if ((name_hash == importNameHash("__Unwind_Resume") and std.mem.eql(u8, name, "__Unwind_Resume")) or (name_hash == importNameHash("__Unwind_Resume_or_Rethrow") and std.mem.eql(u8, name, "__Unwind_Resume_or_Rethrow"))) {
        if (self.unwinder.resumePhaseTwo(self)) return .control_transferred;
        if (self.unwinder.exhaustedWithoutHandler()) {
            machoCapturePrint(
                "macho-processor: Itanium phase-2 stopped after all verified cleanup pads; no matching LSDA catch exists for the guest exception\n",
                .{},
            );
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }
        if (recoverOrphanedPhaseTwoResume(self, name)) return .control_transferred;
        if (self.regs.rdi != 0 or self.cxx_exceptions.activeThrow() != null) {
            const exception_header = if (self.regs.rdi != 0) self.regs.rdi else if (self.cxx_exceptions.activeThrow()) |thrown| if (thrown.allocation) |allocation| allocation.storage_address else thrown.object_address else 0;
            machoCapturePrint(
                "macho-processor: Itanium host _Unwind_Resume fallback rejected: header=0x{x}; host addresses cannot be installed as guest RIP\n",
                .{exception_header},
            );
        }
        const signal_assertion = if (self.signal_frame_count != 0)
            self.signal_frames[self.signal_frame_count - 1].assertion_context
        else
            self.last_guest_assertion;
        if (self.regs.rdi == 0 and signal_assertion.class == .breakpoint_untracked_thread) {
            machoCapturePrint(
                "macho-processor: breakpoint cleanup chain diagnosis: __Unwind_Resume received a null exception argument after Processor::OnThreadBreakpointHit asserted on an untracked modeled thread; no C++ throw object exists to resume, so exit 125 is secondary handler-cleanup termination\n",
                .{},
            );
            machoCapturePrint(
                "macho-processor: breakpoint cleanup chain origin: assertion_step={d} assertion_return=0x{x} active_thread=0x{x} signal_depth={d} deferred_threads={d} suspended_threads={d}\n",
                .{ signal_assertion.step, signal_assertion.return_address, self.active_guest_thread, self.signal_frame_count, self.pthreads.deferred_threads, self.suspended_guest_thread_count },
            );
        }
        machoCapturePrint(
            "macho-processor: guest requested exception resume without a recoverable phase-2 cleanup chain: symbol={s} exception_arg=0x{x} rip=0x{x} rsp=0x{x} rbp=0x{x}\n",
            .{ name, self.regs.rdi, self.regs.rip, self.regs.rsp, self.regs.rbp },
        );
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
        return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
    }
    if ((name_hash == importNameHash("___cxa_rethrow") and std.mem.eql(u8, name, "___cxa_rethrow"))) {
        const object_address = self.cxx_exceptions.recordRethrow() orelse self.regs.rdi;
        machoCapturePrint("macho-processor: guest rethrew exception object=0x{x}\n", .{object_address});
        const thrown = self.cxx_exceptions.last_throw orelse {
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        };
        var inspection = self.unwinder.inspectThrow(self, thrown.type_info_address);
        const exception_header = if (thrown.allocation) |allocation| allocation.storage_address else object_address;
        if (self.unwinder.installPhaseTwo(self, &inspection, exception_header)) {
            self.last_unwind_inspection = inspection;
            return .control_transferred;
        }
        self.last_unwind_inspection = inspection;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
        return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
    }

    if (cpp_allocation.classifyNew(name)) |new_form| {
        self.resolving_import_route = .allocate;
        const alignment = new_form.alignment(self.regs.rsi);
        return .{ .handled = self.memory_forwarder.allocate(self, self.regs.rdi, alignment) orelse 0 };
    }
    if (std.mem.endsWith(u8, name, "_malloc")) {
        self.resolving_import_route = .allocate;
        return .{ .handled = self.memory_forwarder.allocate(self, self.regs.rdi, 16) orelse 0 };
    }
    if (cpp_allocation.isDelete(name) or std.mem.endsWith(u8, name, "_free")) {
        self.resolving_import_route = .release;
        self.memory_forwarder.releaseFrom(self.regs.rdi, importCallerAddress(self));
        self.vtable_tracker.forgetAddress(self.regs.rdi);
        return .handled_void;
    }
    if (std.mem.endsWith(u8, name, "_realloc")) {
        self.resolving_import_route = .reallocate;
        return .{ .handled = self.memory_forwarder.reallocate(self, self.regs.rdi, self.regs.rsi) orelse 0 };
    }
    if ((name_hash == importNameHash("_posix_memalign") and std.mem.eql(u8, name, "_posix_memalign"))) {
        self.resolving_import_route = .posix_memalign;
        const output = self.regs.rdi;
        const alignment = self.regs.rsi;
        const size = self.regs.rdx;
        if (alignment < @sizeOf(u64) or !std.math.isPowerOfTwo(alignment)) {
            return .{ .handled = 22 };
        }
        if (self.guestMemory(output, @sizeOf(u64)) == null) return .{ .unsupported = 14 };
        const allocation = self.memory_forwarder.allocate(self, size, alignment) orelse return .{ .handled = 12 };
        self.write64(output, allocation);
        return .{ .handled = 0 };
    }
    if ((name_hash == importNameHash("_aligned_alloc") and std.mem.eql(u8, name, "_aligned_alloc"))) {
        self.resolving_import_route = .aligned_alloc;
        const alignment = self.regs.rdi;
        if (!std.math.isPowerOfTwo(alignment) or self.regs.rsi % alignment != 0) return .{ .handled = 0 };
        return .{ .handled = self.memory_forwarder.allocate(self, self.regs.rsi, alignment) orelse 0 };
    }
    if (std.mem.endsWith(u8, name, "_calloc")) {
        self.resolving_import_route = .calloc;
        return .{ .handled = self.memory_forwarder.allocateZeroed(self, self.regs.rdi, self.regs.rsi) orelse 0 };
    }
    if ((name_hash == importNameHash("____chkstk_darwin") and std.mem.eql(u8, name, "____chkstk_darwin"))) {
        self.resolving_import_route = .chkstk;
        return .{ .handled = self.regs.rax };
    }

    if (std.mem.endsWith(u8, name, "_memset")) {
        const dst = self.regs.rdi;
        const value: u8 = @intCast(self.regs.rsi & 0xFF);
        const count = self.regs.rdx;
        if (count == 0) return .{ .handled = dst };
        const buf = self.guestMemory(dst, count) orelse {
            self.terminateForGuestAccess(dst, @intCast(@min(count, std.math.maxInt(u8))), .write, "_memset");
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        };
        const mutation = self.captureMemoryMutation(dst, count);
        @memset(buf, value);
        self.commitMemoryMutation(mutation, .bulk_fill);
        if (self.verbose_trace) machoCapturePrint("    [import] _memset(dst=0x{x}, value=0x{x}, count={d})\n", .{ dst, value, count });
        return .{ .handled = dst };
    }
    if ((name_hash == importNameHash("___bzero") and std.mem.eql(u8, name, "___bzero"))) {
        const dst = self.regs.rdi;
        const count = self.regs.rsi;
        if (count == 0) return .handled_void;
        const buf = self.guestMemory(dst, count) orelse {
            self.terminateForGuestAccess(dst, @intCast(@min(count, std.math.maxInt(u8))), .write, "___bzero");
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        };
        const mutation = self.captureMemoryMutation(dst, count);
        @memset(buf, 0);
        self.commitMemoryMutation(mutation, .bulk_fill);
        if (self.verbose_trace) machoCapturePrint("    [import] _bzero(dst=0x{x}, count={d})\n", .{ dst, count });
        return .handled_void;
    }

    if (std.mem.endsWith(u8, name, "_memcpy") or std.mem.endsWith(u8, name, "_memmove")) {
        const dst = self.regs.rdi;
        const src = self.regs.rsi;
        const count = self.regs.rdx;
        if (count == 0) return .{ .handled = dst };
        const src_buf = self.guestMemoryConst(src, count) orelse {
            self.terminateForGuestAccess(src, @intCast(@min(count, std.math.maxInt(u8))), .read, name);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        };
        const dst_buf = self.guestMemory(dst, count) orelse {
            self.terminateForGuestAccess(dst, @intCast(@min(count, std.math.maxInt(u8))), .write, name);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        };
        const mutation = self.captureMemoryMutation(dst, count);
        std.mem.copyForwards(u8, dst_buf, src_buf);
        self.commitMemoryMutation(mutation, .bulk_copy);
        return .{ .handled = dst };
    }

    if (std.mem.endsWith(u8, name, "_memcmp")) {
        const n = self.regs.rdx;
        if (n == 0) return .{ .handled = 0 };
        const lhs = self.guestMemoryConst(self.regs.rdi, n) orelse return .{ .handled = 0 };
        const rhs = self.guestMemoryConst(self.regs.rsi, n) orelse return .{ .handled = 0 };
        const cmp = std.mem.order(u8, lhs, rhs);
        return .{ .handled = switch (cmp) {
            .lt => @bitCast(@as(i64, -1)),
            .eq => 0,
            .gt => 1,
        } };
    }

    if (std.mem.endsWith(u8, name, "_strlen")) {
        const text = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
        return .{ .handled = text.len };
    }

    if (std.mem.endsWith(u8, name, "_clock_getres")) {
        if (self.regs.rsi != 0) {
            if (self.guestMemory(self.regs.rsi, 16) == null) return .{ .unsupported = 14 };
            self.write64(self.regs.rsi, 0);
            self.write64(self.regs.rsi + 8, 1);
        }
        return .{ .handled = 0 };
    }

    if (std.mem.endsWith(u8, name, "_clock_gettime")) {
        if (self.guestMemory(self.regs.rsi, 16) == null) return .{ .unsupported = 14 };
        const now = self.guest_time.now();
        self.write64(self.regs.rsi, now / 1_000_000_000);
        self.write64(self.regs.rsi + 8, now % 1_000_000_000);
        return .{ .handled = 0 };
    }

    if (std.mem.endsWith(u8, name, "_gettimeofday")) {
        if (self.guestMemory(self.regs.rdi, 16) == null) return .{ .unsupported = 14 };
        const wall_now = self.guest_time.wallNow();
        self.write64(self.regs.rdi, wall_now / 1_000_000_000);
        self.write64(self.regs.rdi + 8, (wall_now % 1_000_000_000) / 1000);
        return .{ .handled = 0 };
    }

    if (std.mem.endsWith(u8, name, "_time")) {
        const now_i64: i64 = 1_719_000_000;
        const now: u64 = @bitCast(now_i64);
        const out_ptr = self.regs.rdi;
        if (out_ptr != 0) {
            if (self.guestMemory(out_ptr, 8)) |buf| {
                std.mem.writeInt(u64, buf[0..8], now, .little);
            }
        }
        return .{ .handled = now };
    }
    if ((name_hash == importNameHash("__ZNSt3__16chrono12steady_clock3nowEv") and std.mem.eql(u8, name, "__ZNSt3__16chrono12steady_clock3nowEv"))) {
        return .{ .handled = self.guest_time.now() };
    }

    if ((name_hash == importNameHash("_nanosleep") and std.mem.eql(u8, name, "_nanosleep"))) {
        const req_ptr = self.regs.rdi;
        const rem_ptr = self.regs.rsi;
        const req = self.guestMemory(req_ptr, 16) orelse return .{ .handled = @bitCast(@as(i64, -1)) };
        const tv_sec = std.mem.readInt(i64, req[0..8], .little);
        const tv_nsec = std.mem.readInt(i64, req[8..16], .little);
        if (tv_sec < 0 or tv_nsec < 0 or tv_nsec >= 1_000_000_000) return .{ .handled = @bitCast(@as(i64, -1)) };
        const total_ns: u64 = (@as(u64, @intCast(tv_sec)) * 1_000_000_000) +| @as(u64, @intCast(tv_nsec));
        const requested_ns: i64 = @intCast(@min(total_ns, @as(u64, std.math.maxInt(i64))));
        self.pending_direct_sleep = scheduler.classifyGuestSleep(requested_ns);
        if (rem_ptr != 0) {
            _ = self.fillGuestMemory(rem_ptr, 16, 0);
        }
        return .{ .handled = 0 };
    }

    // S4 (perf audit): the fs_forwarder family gets its own route so a
    // cached hit jumps straight here instead of re-running the ~120-name
    // chain. The dispatch must return null for a non-fs name — this call sits
    // inside handleImportSlow, which still has names after it.
    if (dispatchFsForwarder(self, name)) |result| {
        self.resolving_import_route = .fs_forwarder;
        return result;
    }
    if (std.mem.endsWith(u8, name, "_fopen")) {
        return .{ .handled = self.handleFopen() orelse 0 };
    }
    if (std.mem.endsWith(u8, name, "_fdopen")) {
        return .{ .handled = self.handleFdopen() orelse 0 };
    }
    if (std.mem.endsWith(u8, name, "_fileno")) {
        return .{ .handled = self.handleFileno() };
    }
    if (std.mem.endsWith(u8, name, "_fclose")) {
        return .{ .handled = self.handleFclose() };
    }
    if (std.mem.endsWith(u8, name, "_fprintf")) {
        return .{ .handled = self.handleFprintf() };
    }
    if (std.mem.endsWith(u8, name, "_snprintf")) {
        return .{ .handled = self.handleSnprintf() };
    }
    if (std.mem.endsWith(u8, name, "_fputs")) {
        return .{ .handled = self.handleFputs() };
    }
    if (std.mem.endsWith(u8, name, "_fwrite")) {
        return .{ .handled = self.handleFwrite() };
    }
    if ((name_hash == importNameHash("_fread") and std.mem.eql(u8, name, "_fread"))) {
        return .{ .handled = self.handleFread() };
    }
    if (std.mem.endsWith(u8, name, "_fflush")) {
        return .{ .handled = self.handleFflush() };
    }
    if (std.mem.endsWith(u8, name, "_abort")) {
        self.terminated = true;
        self.exit_code = 1;
        machoCapturePrint("macho-processor: guest called abort()\n", .{});
        return .control_transferred;
    }
    if ((name_hash == importNameHash("__tlv_atexit") and std.mem.eql(u8, name, "__tlv_atexit"))) {
        _ = self.compat.registerAtexit(self.regs.rdi, self.regs.rsi, self.regs.rdx);
        return .{ .handled = 0 };
    }
    if (std.mem.endsWith(u8, name, "_ffs")) {
        const value = @as(u32, @truncate(self.regs.rdi));
        const result: u64 = if (value == 0) 0 else @as(u64, @ctz(value)) + 1;
        return .{ .handled = result };
    }
    if (std.mem.endsWith(u8, name, "_pthread_exit")) {
        if (pthreadExitIsThreadLocal(self.cooperative_ui_context != null, self.active_guest_thread)) {
            const exiting_thread = self.active_guest_thread;
            machoCapturePrint(
                "macho-processor: cooperative pthread_exit: completing caller thread=0x{x} while preserving the process and parked guest threads\n",
                .{exiting_thread},
            );
            self.import_provider_override = .pthread_runtime;
            self.finishActiveGuestThread();
            return .control_transferred;
        }
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
        self.terminated = true;
        self.exit_code = 0;
        return .control_transferred;
    }
    if ((name_hash == importNameHash("_ftell") and std.mem.eql(u8, name, "_ftell")) or (name_hash == importNameHash("_ftello") and std.mem.eql(u8, name, "_ftello"))) {
        return .{ .handled = self.handleFtell() };
    }
    if ((name_hash == importNameHash("_fseek") and std.mem.eql(u8, name, "_fseek")) or (name_hash == importNameHash("_fseeko") and std.mem.eql(u8, name, "_fseeko"))) {
        return .{ .handled = self.handleFseek() };
    }
    if (std.mem.endsWith(u8, name, "_ferror")) {
        return .{ .handled = self.handleFerror() };
    }
    if (std.mem.endsWith(u8, name, "_printf")) {
        const arguments = [_]u64{ self.regs.rsi, self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9 };
        return .{ .handled = self.handlePrintfLike(null, self.regs.rdi, &arguments) };
    }
    if (std.mem.endsWith(u8, name, "_putchar")) {
        return .{ .handled = self.handlePutchar() };
    }

    if ((name_hash == importNameHash("_sysctlbyname") and std.mem.eql(u8, name, "_sysctlbyname"))) {
        const sysctl_name = self.guestCString(self.regs.rdi, 256) orelse return .{ .unsupported = 0 };
        if (std.mem.startsWith(u8, sysctl_name, "hw.optional.")) {
            if (self.regs.rsi != 0 and self.regs.rdx != 0) {
                const old_len_ptr = self.guestMemory(self.regs.rdx, @sizeOf(u64)) orelse return .{ .unsupported = 0 };
                const old_len = std.mem.readInt(u64, old_len_ptr[0..8], .little);
                std.mem.writeInt(u64, old_len_ptr[0..8], @sizeOf(u32), .little);
                if (old_len >= @sizeOf(u32) and self.regs.rsi != 0) {
                    const old_buf = self.guestMemory(self.regs.rsi, @sizeOf(u32)) orelse return .{ .unsupported = 0 };
                    std.mem.writeInt(u32, old_buf[0..4], 0, .little);
                }
            }
            return .{ .handled = 0 };
        }
        return .{ .handled = @bitCast(@as(i64, -1)) };
    }
    if ((name_hash == importNameHash("_sigaction") and std.mem.eql(u8, name, "_sigaction"))) {
        return .{ .handled = self.handleSigaction() };
    }
    if ((name_hash == importNameHash("_setjmp") and std.mem.eql(u8, name, "_setjmp"))) {
        const env_bytes = self.guestMemory(self.regs.rdi, @sizeOf(u64) * 4) orelse return .{ .unsupported = 0 };
        std.mem.writeInt(u64, env_bytes[0..8], self.regs.rsp, .little);
        std.mem.writeInt(u64, env_bytes[8..16], self.regs.rbx, .little);
        std.mem.writeInt(u64, env_bytes[16..24], self.regs.rbp, .little);
        std.mem.writeInt(u64, env_bytes[24..32], self.regs.rip, .little);
        return .{ .handled = 0 };
    }

    if ((name_hash == importNameHash("__ZNSt3__16thread4joinEv") and std.mem.eql(u8, name, "__ZNSt3__16thread4joinEv"))) {
        if (self.verbose_trace) machoCapturePrint("    [import] std::thread::join(object=0x{x})\n", .{self.regs.rdi});
        return .handled_void;
    }
    if ((name_hash == importNameHash("__ZNSt3__16thread20hardware_concurrencyEv") and std.mem.eql(u8, name, "__ZNSt3__16thread20hardware_concurrencyEv"))) {
        const count = std.Thread.getCpuCount() catch 1;
        if (self.verbose_trace) machoCapturePrint("    [import] std::thread::hardware_concurrency() -> {d}\n", .{count});
        return .{ .handled = count };
    }
    if ((name_hash == importNameHash("__ZNSt3__111this_thread6get_idEv") and std.mem.eql(u8, name, "__ZNSt3__111this_thread6get_idEv"))) {
        const handle = self.pthreads.currentThreadHandle(self);
        if (self.verbose_trace) machoCapturePrint("    [import] std::this_thread::get_id() -> 0x{x}\n", .{handle});
        return .{ .handled = handle };
    }
    if ((name_hash == importNameHash("__ZNSt3__119__thread_local_dataEv") and std.mem.eql(u8, name, "__ZNSt3__119__thread_local_dataEv"))) {
        const allocation = self.guestAlloc(64, 16) orelse return .{ .unsupported = 0 };
        if (self.verbose_trace) machoCapturePrint("    [import] __thread_local_data() -> 0x{x}\n", .{allocation});
        return .{ .handled = allocation };
    }
    if ((name_hash == importNameHash("__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEEC2Ev") and std.mem.eql(u8, name, "__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEEC2Ev"))) {
        const object = self.regs.rdi;
        if (self.fillGuestMemory(object, 64, 0)) {
            if (self.libcxx_streams.object_model.ensureType(self, .basic_streambuf, null)) |record| {
                self.write64(object, record.vtable);
            }
            if (self.verbose_trace) machoCapturePrint("    [import] basic_streambuf::C2(object=0x{x})\n", .{object});
        }
        return .{ .handled = object };
    }
    if ((name_hash == importNameHash("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEPKv") and std.mem.eql(u8, name, "__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEPKv"))) {
        if (self.verbose_trace) machoCapturePrint("    [import] operator<<(void* ptr=0x{x}) -> *this\n", .{self.regs.rsi});
        return .{ .handled = self.regs.rdi };
    }
    if ((name_hash == importNameHash("__ZNKSt3__115basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE3strEv") and std.mem.eql(u8, name, "__ZNKSt3__115basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE3strEv"))) {
        const output_ptr = self.regs.rdi;
        const stringbuf_ptr = self.regs.rsi;
        if (!self.libcxx_streams.stringbufToString(self, stringbuf_ptr, output_ptr)) {
            _ = compat_runtime.initLibcppStringLiteral(self, output_ptr, "");
        }
        if (self.verbose_trace) machoCapturePrint("    [import] basic_stringbuf::str() -> modeled string at 0x{x}\n", .{output_ptr});
        return .{ .handled = output_ptr };
    }

    if (std.mem.endsWith(u8, name, "_g_type_check_instance_cast")) {
        machoCapturePrint("    [import] _g_type_check_instance_cast compatibility shim → passthrough\n", .{});
        return .{ .handled = self.regs.rdi };
    }

    if (self.smart_stubs.resolve(name, imported.weak, self.regs.rdi)) |generated| {
        self.import_provider_override = .smart_stub;
        self.import_confidence_override = switch (generated.confidence) {
            .verified => .verified,
            .modeled => .modeled,
        };
        if (self.verbose_trace) {
            machoCapturePrint(
                "    [smart stub] {s} reason={s} confidence={s}\n",
                .{ name, @tagName(generated.reason), @tagName(generated.confidence) },
            );
        }
        return switch (generated.resolution) {
            .handled => |value| .{ .handled = value },
            .handled_void => .handled_void,
        };
    }

    if ((name_hash == importNameHash("___sincosf_stret") and std.mem.eql(u8, name, "___sincosf_stret"))) {
        const angle: f32 = @bitCast(std.mem.readInt(u32, self.xmm[0][0..4], .little));
        const sin_val: f32 = @sin(angle);
        const cos_val: f32 = @cos(angle);
        if (self.guestMemory(self.regs.rdi, 8)) |buf| {
            std.mem.writeInt(u32, buf[0..4], @bitCast(sin_val), .little);
            std.mem.writeInt(u32, buf[4..8], @bitCast(cos_val), .little);
            if (self.verbose_trace) machoCapturePrint("    [import] ___sincosf_stret(angle={d}) -> sin={d} cos={d} ptr=0x{x}\n", .{ angle, sin_val, cos_val, self.regs.rdi });
        }
        return .{ .handled = self.regs.rdi };
    }
    if ((name_hash == importNameHash("_cosf") and std.mem.eql(u8, name, "_cosf"))) {
        const angle: f32 = @bitCast(std.mem.readInt(u32, self.xmm[0][0..4], .little));
        const result: f32 = @cos(angle);
        std.mem.writeInt(u32, self.xmm[0][0..4], @bitCast(result), .little);
        if (self.verbose_trace) machoCapturePrint("    [import] _cosf(angle={d}) -> {d}\n", .{ angle, result });
        return .{ .handled = 0 };
    }

    // Base-2 exponential and logarithm.
    //
    // These are worth spelling out because of how they fail when they are
    // missing. The unresolved-import fallback returns `rax = 0`, and rax is not
    // where a floating-point result lives — the SysV return register for a
    // double or a float is xmm0. So an unhandled `exp2` did not return zero to
    // its caller; it returned *whatever was already in xmm0*, which at the call
    // site is the argument the caller had just converted into it. The caller
    // then read a plausible number and carried on, and every value derived from
    // it was quietly wrong. A missing math import is not a missing value here,
    // it is a wrong one, which is why these are handled rather than left to the
    // fallback that reports itself as returning zero.
    if ((name_hash == importNameHash("_exp2") and std.mem.eql(u8, name, "_exp2"))) {
        const argument: f64 = @bitCast(std.mem.readInt(u64, self.xmm[0][0..8], .little));
        const result = exp2Double(argument);
        std.mem.writeInt(u64, self.xmm[0][0..8], @bitCast(result), .little);
        if (self.verbose_trace) machoCapturePrint("    [import] _exp2({d}) -> {d}\n", .{ argument, result });
        return .{ .handled = 0 };
    }
    if ((name_hash == importNameHash("_exp2f") and std.mem.eql(u8, name, "_exp2f"))) {
        const argument: f32 = @bitCast(std.mem.readInt(u32, self.xmm[0][0..4], .little));
        const result = exp2Single(argument);
        std.mem.writeInt(u32, self.xmm[0][0..4], @bitCast(result), .little);
        if (self.verbose_trace) machoCapturePrint("    [import] _exp2f({d}) -> {d}\n", .{ argument, result });
        return .{ .handled = 0 };
    }
    if ((name_hash == importNameHash("_log2") and std.mem.eql(u8, name, "_log2"))) {
        const argument: f64 = @bitCast(std.mem.readInt(u64, self.xmm[0][0..8], .little));
        const result = log2Double(argument);
        std.mem.writeInt(u64, self.xmm[0][0..8], @bitCast(result), .little);
        if (self.verbose_trace) machoCapturePrint("    [import] _log2({d}) -> {d}\n", .{ argument, result });
        return .{ .handled = 0 };
    }
    if (std.mem.eql(u8, name, "_log2f")) {
        const argument: f32 = @bitCast(std.mem.readInt(u32, self.xmm[0][0..4], .little));
        const result = log2Single(argument);
        std.mem.writeInt(u32, self.xmm[0][0..4], @bitCast(result), .little);
        if (self.verbose_trace) machoCapturePrint("    [import] _log2f({d}) -> {d}\n", .{ argument, result });
        return .{ .handled = 0 };
    }

    if (self.verbose_trace) machoCapturePrint("    [import] (unhandled) {s}\n", .{name});
    return .{ .unsupported = 0 };
}

pub fn recoverOrphanedPhaseTwoResume(self: anytype, symbol: []const u8) bool {
    const thrown = self.cxx_exceptions.activeThrow() orelse {
        self.unwinder.recordOrphanResume(false);
        return false;
    };
    var inspection = self.unwinder.inspectThrow(self, thrown.type_info_address);
    const tracked_header = if (thrown.allocation) |allocation| allocation.storage_address else thrown.object_address;
    // Some personality routines tail-call __Unwind_Resume after restoring
    // a signal context that no longer preserves RDI. The allocation header
    // recorded at __cxa_throw is still the ABI-correct exception pointer,
    // so do not discard an otherwise recoverable phase-two transaction.
    const supplied_header = self.regs.rdi;
    const supplied_is_tracked = supplied_header == tracked_header or supplied_header == thrown.object_address;
    const use_tracked_header = supplied_header == 0 or !supplied_is_tracked;
    const exception_header = if (use_tracked_header) tracked_header else supplied_header;
    machoCapturePrint(
        "macho-processor: Itanium orphan-resume reconstruction: symbol={s} supplied_header=0x{x} tracked_header=0x{x} using_tracked={} rip=0x{x} rsp=0x{x} frames={d} handler_found={}\n",
        .{ symbol, supplied_header, tracked_header, use_tracked_header, self.regs.rip, self.regs.rsp, inspection.frame_count, inspection.handler != null },
    );
    if (exception_header == 0) {
        self.unwinder.recordOrphanResume(false);
        self.last_unwind_inspection = inspection;
        return false;
    }
    if (!self.unwinder.installPhaseTwo(self, &inspection, exception_header)) {
        self.unwinder.recordOrphanResume(false);
        self.last_unwind_inspection = inspection;
        return false;
    }
    self.unwinder.recordOrphanResume(true);
    self.last_unwind_inspection = inspection;
    return true;
}

pub fn dispatchLibcppLocale(self: anytype, name: []const u8) ?ImportHandlerResult {
    if (std.mem.eql(u8, name, "__ZNSt3__16locale7classicEv")) {
        if (self.classic_locale_object == 0) {
            const object = self.guestAlloc(8, 8) orelse return .{ .unsupported = 0 };
            if (!self.compat.initLocale(self, object, null)) return .{ .unsupported = 0 };
            self.classic_locale_object = object;
            self.registerSyntheticRegion(object, 8, .synthetic_object, "std::locale::classic", .{
                .kind = .owned_guest,
                .may_dereference = true,
                .owner = "libc++ locale runtime",
            });
        }
        return .{ .handled = self.classic_locale_object };
    }
    if (std.mem.eql(u8, name, "__ZNSt3__16localeC1Ev") or
        std.mem.eql(u8, name, "__ZNSt3__16localeC2Ev"))
    {
        return if (self.compat.initLocale(self, self.regs.rdi, null)) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.eql(u8, name, "__ZNSt3__16localeC1ERKS0_") or
        std.mem.eql(u8, name, "__ZNSt3__16localeC2ERKS0_"))
    {
        const source: ?u64 = if (self.regs.rsi != 0 and self.guestMemoryConst(self.regs.rsi, 8) != null) self.regs.rsi else null;
        return if (self.compat.initLocale(self, self.regs.rdi, source)) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.eql(u8, name, "__ZNSt3__16localeaSERKS0_")) {
        const source: ?u64 = if (self.regs.rsi != 0 and self.guestMemoryConst(self.regs.rsi, 8) != null) self.regs.rsi else null;
        return if (self.compat.initLocale(self, self.regs.rdi, source)) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
    }
    if (std.mem.eql(u8, name, "__ZNSt3__18ios_base5imbueERKNS_6localeE")) {
        // libc++ returns the previous locale through the hidden sret object
        // in RDI; RSI is ios_base and RDX is the replacement locale.
        const previous_impl = if (self.guestMemoryConst(self.regs.rsi + 40, 8) != null) self.read64(self.regs.rsi + 40) else 0;
        if (previous_impl != 0) {
            self.write64(self.regs.rdi, previous_impl);
        } else if (!self.compat.initLocale(self, self.regs.rdi, null)) {
            return .{ .unsupported = 0 };
        }
        const replacement = if (self.regs.rdx != 0 and self.guestMemoryConst(self.regs.rdx, 8) != null)
            self.read64(self.regs.rdx)
        else blk: {
            const classic = classicLocale(self);
            if (classic == 0) return .{ .unsupported = 0 };
            break :blk self.read64(classic);
        };
        if (self.guestMemory(self.regs.rsi + 40, 8) != null) self.write64(self.regs.rsi + 40, replacement);
        return .{ .handled = self.regs.rdi };
    }
    if (std.mem.eql(u8, name, "__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE5imbueERKNS_6localeE")) {
        return .handled_void;
    }
    return null;
}

pub fn classicLocale(self: anytype) u64 {
    if (self.classic_locale_object != 0) return self.classic_locale_object;
    const object = self.guestAlloc(8, 8) orelse return 0;
    if (!self.compat.initLocale(self, object, null)) return 0;
    self.classic_locale_object = object;
    return object;
}

/// S4 (perf audit): the filesystem-forwarder family — `_open`, `_read`,
/// `_write`, `_stat`, `_mmap`, ... — extracted from `handleImportSlow` so the
/// route cache can replay it directly instead of re-running the ~120-name
/// compare chain on every hit. Returns null when `name` is not in the family;
/// the caller (either `handleImportSlow` or `dispatchImportRoute`) falls
/// through to the rest of the chain. This must stay byte-for-byte equivalent
/// to the inline block it replaced.
pub fn dispatchFsForwarder(self: anytype, name: []const u8) ?ImportHandlerResult {
    const name_hash = importNameHash(name);
    if ((name_hash == importNameHash("_open") and std.mem.eql(u8, name, "_open"))) {
        const path = self.guestCString(self.regs.rdi, 4096) orelse "";
        const result = self.fs_forwarder.open(self);
        self.noteProfileAccountOpen(path, result);
        return .{ .handled = result };
    }
    if ((name_hash == importNameHash("_write") and std.mem.eql(u8, name, "_write"))) {
        return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.write(self))) };
    }
    if ((name_hash == importNameHash("_close") and std.mem.eql(u8, name, "_close"))) {
        return .{ .handled = self.fs_forwarder.close(self) };
    }
    if ((name_hash == importNameHash("_fstatat$INODE64") and std.mem.eql(u8, name, "_fstatat$INODE64")) or (name_hash == importNameHash("_fstatat") and std.mem.eql(u8, name, "_fstatat"))) {
        return .{ .handled = self.fs_forwarder.fstatat(self) };
    }
    if ((name_hash == importNameHash("_openat") and std.mem.eql(u8, name, "_openat"))) {
        const path = self.guestCString(self.regs.rsi, 4096) orelse "";
        const result = self.fs_forwarder.openat(self);
        self.noteProfileAccountOpen(path, result);
        return .{ .handled = result };
    }
    if ((name_hash == importNameHash("_fstat$INODE64") and std.mem.eql(u8, name, "_fstat$INODE64")) or (name_hash == importNameHash("_fstat") and std.mem.eql(u8, name, "_fstat"))) {
        return .{ .handled = self.fs_forwarder.fstat(self) };
    }
    if ((name_hash == importNameHash("_ftruncate") and std.mem.eql(u8, name, "_ftruncate")) or (name_hash == importNameHash("_ftruncate64") and std.mem.eql(u8, name, "_ftruncate64"))) {
        return .{ .handled = self.fs_forwarder.ftruncate(self) };
    }
    if ((name_hash == importNameHash("_shm_open") and std.mem.eql(u8, name, "_shm_open"))) {
        return .{ .handled = self.fs_forwarder.shmOpen(self) };
    }
    if ((name_hash == importNameHash("_shm_unlink") and std.mem.eql(u8, name, "_shm_unlink"))) {
        return .{ .handled = self.fs_forwarder.shmUnlink(self) };
    }
    if ((name_hash == importNameHash("_opendir$INODE64") and std.mem.eql(u8, name, "_opendir$INODE64")) or (name_hash == importNameHash("_opendir") and std.mem.eql(u8, name, "_opendir"))) {
        return .{ .handled = self.fs_forwarder.opendir(self) };
    }
    if ((name_hash == importNameHash("_dirfd") and std.mem.eql(u8, name, "_dirfd"))) {
        return .{ .handled = self.fs_forwarder.dirfd(self) };
    }
    if ((name_hash == importNameHash("_closedir") and std.mem.eql(u8, name, "_closedir"))) {
        return .{ .handled = self.fs_forwarder.closedir(self) };
    }
    if ((name_hash == importNameHash("_readdir$INODE64") and std.mem.eql(u8, name, "_readdir$INODE64")) or (name_hash == importNameHash("_readdir") and std.mem.eql(u8, name, "_readdir"))) {
        return .{ .handled = self.fs_forwarder.readdir(self) };
    }
    if ((name_hash == importNameHash("_read") and std.mem.eql(u8, name, "_read"))) {
        const guest_fd = self.regs.rdi;
        const requested = self.regs.rdx;
        const result = self.fs_forwarder.read(self);
        self.noteProfileAccountRead(guest_fd, requested, result, 0);
        return .{ .handled = @bitCast(result) };
    }
    if ((name_hash == importNameHash("_readv") and std.mem.eql(u8, name, "_readv"))) {
        return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.readv(self))) };
    }
    if ((name_hash == importNameHash("_writev") and std.mem.eql(u8, name, "_writev"))) {
        return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.writev(self))) };
    }
    if ((name_hash == importNameHash("_pread$INODE64") and std.mem.eql(u8, name, "_pread$INODE64")) or (name_hash == importNameHash("_pread") and std.mem.eql(u8, name, "_pread"))) {
        const guest_fd = self.regs.rdi;
        const requested = self.regs.rdx;
        const offset = self.regs.rcx;
        const result = self.fs_forwarder.pread(self);
        self.noteProfileAccountRead(guest_fd, requested, result, offset);
        return .{ .handled = @bitCast(result) };
    }
    if ((name_hash == importNameHash("_pwrite$INODE64") and std.mem.eql(u8, name, "_pwrite$INODE64")) or (name_hash == importNameHash("_pwrite") and std.mem.eql(u8, name, "_pwrite"))) {
        return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.pwrite(self))) };
    }
    if ((name_hash == importNameHash("_lseek$INODE64") and std.mem.eql(u8, name, "_lseek$INODE64")) or (name_hash == importNameHash("_lseek") and std.mem.eql(u8, name, "_lseek"))) {
        return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.lseek(self))) };
    }
    if ((name_hash == importNameHash("_stat$INODE64") and std.mem.eql(u8, name, "_stat$INODE64")) or (name_hash == importNameHash("_stat") and std.mem.eql(u8, name, "_stat"))) {
        return .{ .handled = self.fs_forwarder.stat(self) };
    }
    if ((name_hash == importNameHash("_lstat$INODE64") and std.mem.eql(u8, name, "_lstat$INODE64")) or (name_hash == importNameHash("_lstat") and std.mem.eql(u8, name, "_lstat"))) {
        return .{ .handled = self.fs_forwarder.lstat(self) };
    }
    if ((name_hash == importNameHash("_access") and std.mem.eql(u8, name, "_access")) or (name_hash == importNameHash("_access$INODE64") and std.mem.eql(u8, name, "_access$INODE64"))) {
        return .{ .handled = self.fs_forwarder.access(self) };
    }
    if ((name_hash == importNameHash("_realpath$INODE64") and std.mem.eql(u8, name, "_realpath$INODE64")) or (name_hash == importNameHash("_realpath") and std.mem.eql(u8, name, "_realpath"))) {
        return .{ .handled = self.fs_forwarder.realpath(self) };
    }
    if ((name_hash == importNameHash("_getcwd") and std.mem.eql(u8, name, "_getcwd"))) {
        return .{ .handled = self.fs_forwarder.getcwd(self) };
    }
    if ((name_hash == importNameHash("_chdir") and std.mem.eql(u8, name, "_chdir"))) {
        return .{ .handled = self.fs_forwarder.chdir(self) };
    }
    if ((name_hash == importNameHash("_readlink$INODE64") and std.mem.eql(u8, name, "_readlink$INODE64")) or (name_hash == importNameHash("_readlink") and std.mem.eql(u8, name, "_readlink"))) {
        return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.readlink(self))) };
    }
    if ((name_hash == importNameHash("_dup") and std.mem.eql(u8, name, "_dup"))) {
        return .{ .handled = self.fs_forwarder.dup(self) };
    }
    if ((name_hash == importNameHash("_dup2") and std.mem.eql(u8, name, "_dup2"))) {
        return .{ .handled = self.fs_forwarder.dup2(self) };
    }
    if ((name_hash == importNameHash("_fcntl") and std.mem.eql(u8, name, "_fcntl"))) {
        return .{ .handled = self.fs_forwarder.fcntl(self) };
    }
    if ((name_hash == importNameHash("_socket") and std.mem.eql(u8, name, "_socket"))) {
        return .{ .handled = self.fs_forwarder.createSocket(self) };
    }
    if ((name_hash == importNameHash("_setsockopt") and std.mem.eql(u8, name, "_setsockopt"))) {
        return .{ .handled = self.fs_forwarder.setSocketOption(self) };
    }
    if ((name_hash == importNameHash("_connect") and std.mem.eql(u8, name, "_connect"))) {
        return .{ .handled = self.fs_forwarder.connectSocket(self) };
    }
    if ((name_hash == importNameHash("_send") and std.mem.eql(u8, name, "_send"))) {
        return .{ .handled = self.fs_forwarder.sendSocket(self) };
    }
    if ((name_hash == importNameHash("_pipe") and std.mem.eql(u8, name, "_pipe"))) {
        return .{ .handled = self.fs_forwarder.pipe(self) };
    }
    if ((name_hash == importNameHash("_mkdir") and std.mem.eql(u8, name, "_mkdir")) or (name_hash == importNameHash("_mkdir$INODE64") and std.mem.eql(u8, name, "_mkdir$INODE64"))) {
        return .{ .handled = self.fs_forwarder.mkdir(self) };
    }
    if ((name_hash == importNameHash("_unlink") and std.mem.eql(u8, name, "_unlink")) or (name_hash == importNameHash("_unlink$INODE64") and std.mem.eql(u8, name, "_unlink$INODE64"))) {
        return .{ .handled = self.fs_forwarder.unlink(self) };
    }
    if ((name_hash == importNameHash("_rename") and std.mem.eql(u8, name, "_rename")) or (name_hash == importNameHash("_rename$INODE64") and std.mem.eql(u8, name, "_rename$INODE64"))) {
        return .{ .handled = self.fs_forwarder.rename(self) };
    }
    if ((name_hash == importNameHash("_symlink") and std.mem.eql(u8, name, "_symlink")) or (name_hash == importNameHash("_symlink$INODE64") and std.mem.eql(u8, name, "_symlink$INODE64"))) {
        return .{ .handled = self.fs_forwarder.symlink(self) };
    }
    if ((name_hash == importNameHash("_mmap") and std.mem.eql(u8, name, "_mmap"))) {
        return .{ .handled = self.fs_forwarder.mmap(self) };
    }
    if ((name_hash == importNameHash("_munmap") and std.mem.eql(u8, name, "_munmap"))) {
        return .{ .handled = self.fs_forwarder.munmap(self) };
    }
    if ((name_hash == importNameHash("_mprotect") and std.mem.eql(u8, name, "_mprotect"))) {
        return .{ .handled = self.fs_forwarder.mprotect(self) };
    }
    return null;
}

pub fn dispatchImportRoute(self: anytype, route: ImportRoute, imported: macho_metadata.ImportedSymbol) ?ImportHandlerResult {
    const name = imported.name;
    return switch (route) {
        .legacy => handleImportSlow(self, imported),
        .guest_memory_copy => handleGuestMemoryCopy(self, name),
        .memset => blk: {
            const destination = self.regs.rdi;
            if (self.regs.rdx != 0) {
                const bytes = self.guestMemory(destination, self.regs.rdx) orelse break :blk .{ .unsupported = 0 };
                const mutation = self.captureMemoryMutation(destination, self.regs.rdx);
                @memset(bytes, @truncate(self.regs.rsi));
                self.commitMemoryMutation(mutation, .bulk_fill);
            }
            break :blk .{ .handled = destination };
        },
        .bzero => blk: {
            if (self.regs.rsi != 0) {
                const bytes = self.guestMemory(self.regs.rdi, self.regs.rsi) orelse break :blk .{ .unsupported = 0 };
                const mutation = self.captureMemoryMutation(self.regs.rdi, self.regs.rsi);
                @memset(bytes, 0);
                self.commitMemoryMutation(mutation, .bulk_fill);
            }
            break :blk .{ .handled = 0 };
        },
        .coop_main => if (self.beginCooperativeMainLoop()) .control_transferred else null,
        .coop_main_quit => blk: {
            if (self.cooperative_ui_context == null) break :blk null;
            self.foreign_objects.main_loop_quits +|= 1;
            self.restoreMainLoopCaller("gtk_main_quit");
            break :blk .control_transferred;
        },
        .idle_add => handleIdleAdd(self, name),
        .idle_source_remove => handleIdleSourceRemove(self),
        .events_pending => blk: {
            self.pumpNativeWindowEvents();
            break :blk .{ .handled = @intFromBool(self.pendingIdleCallbackCount() != 0) };
        },
        .coop_main_iteration => blk: {
            self.pumpNativeWindowEvents();
            if (self.startNextIdleCallback(name, false)) break :blk .control_transferred;
            break :blk .{ .handled = 0 };
        },
        .sdl_compat => blk: {
            const resolution = self.sdl.dispatch(self, name) orelse break :blk null;
            self.import_confidence_override = .modeled;
            noteSdlGraphicsImport(self, name);
            break :blk sdlResolution(resolution);
        },
        .local_definition => blk: {
            const target = self.metadata.definedSymbolAddress(name) orelse break :blk null;
            if (target == imported.stub_address or !self.isExecutableAddress(target)) break :blk null;
            self.regs.rip = target;
            self.import_provider_override = .local_definition;
            self.import_confidence_override = .verified;
            break :blk .control_transferred;
        },
        .libcxx_stream => blk: {
            const resolution = self.libcxx_streams.dispatch(self, &self.fs_forwarder, name) orelse break :blk null;
            self.import_provider_override = .libcpp_stream;
            self.import_confidence_override = .modeled;
            break :blk switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        },
        .foreign_object => blk: {
            const resolution = self.foreign_objects.dispatch(self, name) orelse break :blk null;
            self.import_confidence_override = .modeled;
            break :blk switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        },
        .import_contract => blk: {
            const resolution = import_resolution.dispatchContract(self, name) orelse break :blk null;
            break :blk switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
                .failed => .{ .unsupported = 0 },
            };
        },
        .libcxx_filesystem => blk: {
            const resolution = self.libcxx_filesystem.dispatch(self, &self.fs_forwarder, name) orelse break :blk null;
            self.import_provider_override = .libcpp_filesystem;
            self.import_confidence_override = .verified;
            break :blk switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        },
        .pthread => blk: {
            const resolution = self.pthreads.dispatch(self, name) orelse break :blk null;
            self.import_provider_override = .pthread_runtime;
            self.import_confidence_override = .modeled;
            break :blk switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        },
        .pthread_cpp_sync => blk: {
            const resolution = self.pthreads.dispatchCppSynchronization(self, name) orelse break :blk null;
            self.import_provider_override = .pthread_runtime;
            self.import_confidence_override = .modeled;
            break :blk switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        },
        .pthread_once => handlePthreadOnce(self),
        .dynamic_library => blk: {
            const resolution = self.dynamic_forwarder.forward(self, imported.dylib, name) orelse break :blk null;
            self.import_provider_override = .dynamic_library;
            self.import_confidence_override = .verified;
            break :blk switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        },
        .shared_contract => dispatchSharedContract(self, name),
        .allocate => blk: {
            const alignment = if (cpp_allocation.classifyNew(name)) |new_form|
                new_form.alignment(self.regs.rsi)
            else
                16;
            break :blk .{ .handled = self.memory_forwarder.allocate(self, self.regs.rdi, alignment) orelse 0 };
        },
        .release => blk: {
            self.memory_forwarder.releaseFrom(self.regs.rdi, importCallerAddress(self));
            self.vtable_tracker.forgetAddress(self.regs.rdi);
            break :blk .handled_void;
        },
        .reallocate => .{ .handled = self.memory_forwarder.reallocate(self, self.regs.rdi, self.regs.rsi) orelse 0 },
        .posix_memalign => handleCachedPosixMemalign(self),
        .aligned_alloc => blk: {
            const alignment = self.regs.rdi;
            if (!std.math.isPowerOfTwo(alignment) or self.regs.rsi % alignment != 0) break :blk .{ .handled = 0 };
            break :blk .{ .handled = self.memory_forwarder.allocate(self, self.regs.rsi, alignment) orelse 0 };
        },
        .calloc => .{ .handled = self.memory_forwarder.allocateZeroed(self, self.regs.rdi, self.regs.rsi) orelse 0 },
        .chkstk => .{ .handled = self.regs.rax },
        .sysconf => .{ .handled = guestSysconf(@bitCast(@as(u32, @truncate(self.regs.rdi)))) },
        .strtoul => handleImportSlow(self, imported),
        .fs_forwarder => dispatchFsForwarder(self, name),
    };
}

fn sdlResolution(resolution: sdl_runtime.Resolution) ImportHandlerResult {
    return switch (resolution) {
        .handled => |value| .{ .handled = value },
        .handled_void => .handled_void,
    };
}

fn noteSdlGraphicsImport(self: anytype, name: []const u8) void {
    const State = @typeInfo(@TypeOf(self)).pointer.child;
    if (@hasDecl(State, "observeSdlGraphicsImport")) self.observeSdlGraphicsImport(name);
}

/// `pthread_once`: run the initializer exactly once by transferring control to
/// it, marking the control word first so a re-entry returns immediately.
///
/// Extracted so the route cache replays the same code the slow path ran.
/// Inline in `handleImportSlow`, it was unreachable from `dispatchImportRoute`,
/// which is what made `.pthread` a tag with three owners and one replay.
pub fn handlePthreadOnce(self: anytype) ImportHandlerResult {
    const once_control = self.regs.rdi;
    const init_routine = self.regs.rsi;
    const once_value = self.readMemVal(once_control, .bits32);
    if (once_value != 0) return .{ .handled = 0 };
    self.writeMemVal(once_control, .bits32, 1);
    self.regs.rip = init_routine;
    return .control_transferred;
}

pub fn handleIdleAdd(self: anytype, name: []const u8) ImportHandlerResult {
    const full = std.mem.eql(u8, name, "_g_idle_add_full") or std.mem.eql(u8, name, "_gdk_threads_add_idle_full");
    const callback = if (full) self.regs.rsi else self.regs.rdi;
    const data = if (full) self.regs.rdx else self.regs.rsi;
    const source = self.scheduleIdleCallback(callback, data, name);
    return .{ .handled = source };
}

pub fn handleIdleSourceRemove(self: anytype) ImportHandlerResult {
    const removed = self.removeIdleSource(self.regs.rdi);
    return .{ .handled = @intFromBool(removed) };
}

pub fn dispatchSharedContract(self: anytype, name: []const u8) ?ImportHandlerResult {
    const outcome = contract.dispatchFromAllFamilies(name, self.regs.rdi) orelse return null;
    if (self.contract_verification and !contract.verify.verifyDispatch(name, outcome, self.regs.rdi)) {
        if (contract.verify.resolveExpected(name, self.regs.rdi)) |expected| {
            return switch (expected) {
                .handled => |value| .{ .handled = value },
                .terminated => |code| .{ .terminated = code },
            };
        }
    }
    return switch (outcome) {
        .handled => |value| .{ .handled = value },
        .terminated => |code| .{ .terminated = code },
    };
}

pub fn handleCachedPosixMemalign(self: anytype) ImportHandlerResult {
    const alignment = self.regs.rsi;
    if (alignment < @sizeOf(u64) or !std.math.isPowerOfTwo(alignment)) return .{ .handled = 22 };
    if (self.guestMemory(self.regs.rdi, @sizeOf(u64)) == null) return .{ .unsupported = 14 };
    const allocation = self.memory_forwarder.allocate(self, self.regs.rdx, alignment) orelse return .{ .handled = 12 };
    self.write64(self.regs.rdi, allocation);
    return .{ .handled = 0 };
}

pub fn handleGuestMemoryCopy(self: anytype, name: []const u8) ImportHandlerResult {
    const destination_address = self.regs.rdi;
    const source_address = self.regs.rsi;
    const count = self.regs.rdx;
    if ((std.mem.eql(u8, name, "___memcpy_chk") or std.mem.eql(u8, name, "___memmove_chk")) and
        count > self.regs.rcx)
    {
        machoCapturePrint(
            "macho-processor: fortified memory move rejected: import={s} destination=0x{x} source=0x{x} bytes={d} destination_size={d}\n",
            .{ name, destination_address, source_address, count, self.regs.rcx },
        );
        return .{ .terminated = 134 };
    }
    if (count == 0) return .{ .handled = destination_address };

    const source = self.guestMemoryConst(source_address, count);
    const destination = self.guestMemory(destination_address, count);
    if (source != null and destination != null) {
        const mutation = self.captureMemoryMutation(destination_address, count);
        // A guest memcpy can publish executable bytes (a code-cache copy, a
        // relocation applied in bulk). Invalidate the decode cache over the
        // whole destination, exactly as a scalar store does — see
        // `noteGuestWrite`. Without this the bulk routes were the one way to
        // change instruction bytes without telling the decode cache.
        self.noteGuestWrite(destination_address, count);
        if (destination_address > source_address and destination_address - source_address < count) {
            std.mem.copyBackwards(u8, destination.?, source.?);
        } else {
            std.mem.copyForwards(u8, destination.?, source.?);
        }
        self.commitMemoryMutation(mutation, .bulk_copy);
    } else if (self.verbose_trace) {
        machoCapturePrint(
            "macho-processor: {s} skipped: source=0x{x} destination=0x{x} bytes={d} source_backed={} destination_backed={}\n",
            .{ name, source_address, destination_address, count, source != null, destination != null },
        );
    }
    return .{ .handled = destination_address };
}

pub fn isCooperativeWaitImport(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "condition_variable15__do_timed_wait") != null or
        std.mem.indexOf(u8, name, "condition_variable4wait") != null or
        std.mem.indexOf(u8, name, "condition_variable10wait_until") != null or
        std.mem.eql(u8, name, "_pthread_cond_wait") or
        std.mem.eql(u8, name, "_pthread_cond_timedwait") or
        std.mem.eql(u8, name, "_pthread_cond_timedwait_relative_np") or
        std.mem.eql(u8, name, "_pthread_join");
}

pub fn isCooperativeYieldImport(name: []const u8) bool {
    return std.mem.eql(u8, name, "_pthread_yield_np") or std.mem.eql(u8, name, "_sched_yield");
}

pub fn handleCooperativeYieldImport(self: anytype, imported: macho_metadata.ImportedSymbol, return_address: u64) bool {
    if (!isCooperativeYieldImport(imported.name)) return false;
    self.pthreads.noteSchedulerYield();
    self.regs.rax = 0;
    if (return_address == 0 or !self.isExecutableAddress(return_address)) {
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        self.terminated = true;
        return true;
    }
    _ = self.pop();
    self.regs.rip = return_address;
    const previous_thread = self.active_guest_thread;
    const switched = self.yieldActiveGuestThreadForWait(imported.name);
    self.resolving_import_route = .pthread;
    self.import_provider_override = .pthread_runtime;
    if (self.pthreads.scheduler_yields <= 4) {
        machoCapturePrint(
            "scheduler: explicit guest yield #{d}: import={s} from=0x{x} to=0x{x} switched={} suspended={d} deferred={d}\n",
            .{ self.pthreads.scheduler_yields, imported.name, previous_thread, self.active_guest_thread, switched, self.suspended_guest_thread_count, self.pthreads.deferred_threads },
        );
    }
    return true;
}

pub fn handleCooperativeWaitImport(self: anytype, imported: macho_metadata.ImportedSymbol, return_address: u64) bool {
    if (!isCooperativeWaitImport(imported.name)) return false;
    const cpp_condvar_wait = std.mem.indexOf(u8, imported.name, "condition_variable15__do_timed_wait") != null or
        std.mem.indexOf(u8, imported.name, "condition_variable4wait") != null or
        std.mem.indexOf(u8, imported.name, "condition_variable10wait_until") != null;
    const pthread_condvar_wait = std.mem.eql(u8, imported.name, "_pthread_cond_wait") or
        std.mem.eql(u8, imported.name, "_pthread_cond_timedwait") or
        std.mem.eql(u8, imported.name, "_pthread_cond_timedwait_relative_np");
    const condvar_wait = cpp_condvar_wait or pthread_condvar_wait;
    const timed_condvar_wait = std.mem.indexOf(u8, imported.name, "condition_variable15__do_timed_wait") != null or
        std.mem.indexOf(u8, imported.name, "condition_variable10wait_until") != null or
        std.mem.eql(u8, imported.name, "_pthread_cond_timedwait") or
        std.mem.eql(u8, imported.name, "_pthread_cond_timedwait_relative_np");
    if (cpp_condvar_wait) {
        if (!self.pthreads.beginCooperativeCppCondvarWait(self, timed_condvar_wait)) return false;
    } else if (pthread_condvar_wait and !self.pthreads.beginCooperativeCondvarWait(self, timed_condvar_wait)) {
        return false;
    }
    if (!condvar_wait) self.pthreads.collapsed_waits +|= 1;
    self.regs.rax = 0;
    if (return_address != 0 and self.isExecutableAddress(return_address)) {
        _ = self.pop();
        self.regs.rip = return_address;
    } else {
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        self.terminated = true;
        return true;
    }
    if (self.yieldActiveGuestThreadForWait(imported.name)) {
        self.resolving_import_route = .pthread;
        self.import_provider_override = .pthread_runtime;
    } else if (condvar_wait) {
        // If this is the only runnable worker, the collapsed wait still
        // must return with the caller's mutex reacquired.
        _ = self.resumeSuspendedGuestThread();
    }
    return true;
}

// A contended mutex must be retried after the owner gets a time slice.
// Unlike condition waits, keep the guest call frame intact so resuming the
// worker re-enters pthread_mutex_lock rather than falsely reporting that
// it acquired the mutex.
fn isCooperativeMutexLockSymbol(name: []const u8) bool {
    return std.mem.eql(u8, name, "_pthread_mutex_lock") or
        std.mem.eql(u8, name, "__ZNSt3__15mutex4lockEv") or
        std.mem.indexOf(u8, name, "recursive_mutex4lockEv") != null;
}

pub fn handleCooperativeMutexContention(self: anytype, imported: macho_metadata.ImportedSymbol) bool {
    if (!isCooperativeMutexLockSymbol(imported.name)) return false;
    const owner = self.pthreads.currentThreadHandle(self);
    if (!self.pthreads.mutexWouldBlock(self.regs.rdi, owner)) return false;
    self.pthreads.collapsed_waits +|= 1;
    return self.yieldActiveGuestThreadForWait("pthread mutex contention");
}

pub fn handleSleepSchedulingBoundary(self: anytype, decision: scheduler.GuestSleepDecision, reason: []const u8) bool {
    const sleeping_thread = self.active_guest_thread;
    var parked = false;
    switch (decision.kind) {
        .yield => _ = self.guest_time.advanceBy(decision.effective_nanoseconds),
        .invalid => return false,
        .timed => {
            const deadline = self.guest_time.now() +| decision.effective_nanoseconds;
            const sequence = self.scheduleGuestWaitDeadline(sleeping_thread, 0, 0, deadline);
            parked = self.pthreads.beginCooperativeSleep(
                sleeping_thread,
                self.executed_steps,
                deadline,
                sequence,
            );
            if (!parked) {
                _ = self.guest_time.cancel(sequence);
                _ = self.guest_time.advanceBy(decision.effective_nanoseconds);
            }
        },
        .indefinite => {
            parked = self.pthreads.beginCooperativeSleep(
                sleeping_thread,
                self.executed_steps,
                null,
                0,
            );
        },
    }
    const switched = self.yieldActiveGuestThreadForWait(reason);
    if (switched) self.cooperative_sleep_yields +|= 1;
    if (self.cooperative_sleep_yields <= 4 or decision.kind == .indefinite) {
        machoCapturePrint(
            "scheduler: virtual sleep boundary: sleeper=0x{x} resumed=0x{x} kind={s} parked={} switched={} deadline_ns={d} suspended={d} deferred={d}\n",
            .{ sleeping_thread, self.active_guest_thread, @tagName(decision.kind), parked, switched, if (decision.kind == .timed) self.guest_time.now() +| decision.effective_nanoseconds else 0, self.suspended_guest_thread_count, self.pthreads.deferred_threads },
        );
    }
    return switched;
}

pub fn handleVirtualSleepSchedulingBoundary(self: anytype, reason: []const u8) bool {
    return handleSleepSchedulingBoundary(self, self.dynamic_forwarder.lastVirtualSleepDecision(), reason);
}

pub fn handleDirectImportCall(self: anytype, imported: macho_metadata.ImportedSymbol) void {
    const boundary = x64_decoder.highway.systemBoundary(.macho64, .import, imported.stub_address, imported.name);
    if (boundary.disposition != .forward) {
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 126;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.system_policy_rejected);
        return;
    }
    const return_address = self.read64(self.regs.rsp);
    if (handleCooperativeYieldImport(self, imported, return_address)) return;
    if (handleCooperativeMutexContention(self, imported)) return;
    if (handleCooperativeWaitImport(self, imported, return_address)) return;
    const virtual_sleep_calls_before = self.dynamic_forwarder.virtualSleepCallCount();
    self.pending_direct_sleep = null;
    var import_completed = false;
    switch (self.handleImport(imported)) {
        .handled => |result| {
            import_completed = true;
            self.regs.rax = result;
            if (self.verbose_trace) {
                machoCapturePrint(
                    "  [handled direct import] {s} from {s}; stub=0x{x} return=0x{x} -> rax=0x{x}\n",
                    .{ imported.name, imported.dylib, imported.stub_address, return_address, result },
                );
            }
        },
        .handled_void => {
            import_completed = true;
            if (self.verbose_trace) {
                machoCapturePrint(
                    "  [handled void direct import] {s} from {s}; stub=0x{x} return=0x{x}\n",
                    .{ imported.name, imported.dylib, imported.stub_address, return_address },
                );
            }
        },
        .control_transferred => {
            if (self.verbose_trace) {
                machoCapturePrint(
                    "  [handled direct control transfer] {s} from {s}; landing_pad=0x{x}\n",
                    .{ imported.name, imported.dylib, self.regs.rip },
                );
            }
            return;
        },
        .unsupported => |result| {
            self.regs.rax = result;
            recordUnresolvedImport(self, imported, return_address, result);
            // Distinguish "no handler exists for this symbol" from "a handler
            // (e.g. the primitive lib's strlen) exists but declined this call
            // because the argument was not guest-readable". The latter is an
            // input edge case, not an unhandled import.
            const primitive_declined = self.primitiveMatches(imported.name);
            machoCapturePrint(
                "  [unresolved direct import #{d}] {s} from {s}; stub=0x{x} return=0x{x} -> rax=0x{x}{s}\n",
                .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, return_address, result, if (primitive_declined) " (primitive handler matched but declined: argument not guest-readable)" else "" },
            );
            if (self.strict_imports) {
                self.terminateForUnresolvedImport();
                return;
            }
        },
        .terminated => |exit_code| {
            self.exit_code = exit_code;
            if (exit_diagnostics.reasonFromValue(self.termination_reason) == .unknown) {
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
            }
            self.terminated = true;
            machoCapturePrint("  [handled terminal direct import] {s}({d})\n", .{ imported.name, exit_code });
            return;
        },
    }

    if (return_address != 0 and self.isExecutableAddress(return_address)) {
        _ = self.pop();
        self.regs.rip = return_address;
        if (import_completed) {
            if (self.pending_direct_sleep) |decision| {
                self.pending_direct_sleep = null;
                _ = handleSleepSchedulingBoundary(self, decision, "POSIX nanosleep");
            } else if (self.dynamic_forwarder.virtualSleepCallCount() != virtual_sleep_calls_before) {
                _ = handleVirtualSleepSchedulingBoundary(self, "libc++ virtual sleep");
            }
        }
    } else {
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
        self.terminated = true;
    }
}

pub fn recordUnresolvedImport(
    self: anytype,
    imported: macho_metadata.ImportedSymbol,
    return_address: u64,
    synthetic_result: u64,
) void {
    var entry = ImportTraceEntry{
        .symbol = imported.name,
        .dylib = imported.dylib,
        .stub_address = imported.stub_address,
        .return_address = return_address,
        .synthetic_result = synthetic_result,
    };
    if (self.metadata.nearestSymbol(return_address)) |caller_sym| {
        entry.caller_symbol = caller_sym.name;
        entry.caller_offset = caller_sym.offset;
    }
    analyzeUnknownSymbol(self, imported, return_address);
    self.import_trace_entries[self.import_trace_index] = entry;
    self.import_trace_index = (self.import_trace_index + 1) % IMPORT_TRACE_BUFFER_LEN;
    if (self.import_trace_index == 0) self.import_trace_filled = true;
    self.unresolved_import_count += 1;
}

pub fn analyzeUnknownSymbol(
    self: anytype,
    imported: macho_metadata.ImportedSymbol,
    return_address: u64,
) void {
    const use_site = traceCallSite(self, return_address) orelse return_address;
    const observation = self.symbol_assembly.observe(imported.name, use_site) catch |err| {
        machoCapturePrint(
            "  [unknown-symbol assembly] tracking failed for {s}: {s}\n",
            .{ imported.name, @errorName(err) },
        );
        return;
    };

    if (observation.first_symbol) {
        if (self.symbol_assembly_catalog == null) {
            self.symbol_assembly_catalog = symbol_assembly_context.Catalog.build(
                self.allocator,
                &self.metadata,
                decodeInsn,
            ) catch |err| {
                machoCapturePrint(
                    "  [unknown-symbol assembly] static index failed for {s}: {s}\n",
                    .{ imported.name, @errorName(err) },
                );
                return;
            };
        }
        self.symbol_assembly_catalog.?.logImport(&self.metadata, imported, decodeInsn);
    }

    if (observation.first_use_site) {
        logDynamicUnknownSymbolContext(self, imported, use_site, observation.symbol_hits);
    } else if (observation.site_hits == 2) {
        machoCapturePrint(
            "  [unknown-symbol assembly] repeated symbol={s} use_site=0x{x}; identical context is deduplicated\n",
            .{ imported.name, use_site },
        );
    }
}

pub fn traceCallSite(self: anytype, return_address: u64) ?u64 {
    const count: usize = self.execution_history.countFor(self.active_guest_thread);
    var ordinal = count;
    while (ordinal != 0) {
        ordinal -= 1;
        const entry = self.execution_history.chronological(self.active_guest_thread, ordinal) orelse continue;
        if (entry.rip +% entry.len != return_address) continue;
        switch (entry.op) {
            .call_rel32, .call_reg64, .call_mem64 => return entry.rip,
            else => {},
        }
    }
    return null;
}

pub fn logDynamicUnknownSymbolContext(
    self: anytype,
    imported: macho_metadata.ImportedSymbol,
    use_site: u64,
    symbol_hits: u64,
) void {
    const count: usize = self.execution_history.countFor(self.active_guest_thread);
    if (count == 0) return;
    var selected_ordinal: ?usize = null;
    for (0..count) |ordinal| {
        const entry = self.execution_history.chronological(self.active_guest_thread, ordinal) orelse continue;
        if (entry.rip == use_site) selected_ordinal = ordinal;
    }
    const selected = selected_ordinal orelse return;
    const start = selected -| symbol_assembly_context.CONTEXT_BEFORE;
    const end = @min(count, selected + 1 + symbol_assembly_context.CONTEXT_AFTER);
    if (self.metadata.nearestSymbol(use_site)) |caller| {
        machoCapturePrint(
            "  [unknown-symbol runtime block] symbol={s} occurrence={d} use_site=0x{x} caller={s}+0x{x}\n",
            .{ imported.name, symbol_hits, use_site, caller.name, caller.offset },
        );
    } else {
        machoCapturePrint(
            "  [unknown-symbol runtime block] symbol={s} occurrence={d} use_site=0x{x} caller=<unknown>\n",
            .{ imported.name, symbol_hits, use_site },
        );
    }
    machoCapturePrint(
        "    entry-registers: rdi=0x{x} rsi=0x{x} rdx=0x{x} rcx=0x{x} r8=0x{x} r9=0x{x} rsp=0x{x}\n",
        .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9, self.regs.rsp },
    );
    for (self.xmm[0..4], 0..) |value, index| {
        machoCapturePrint(
            "    entry-xmm{d}: low=0x{x} high=0x{x}\n",
            .{
                index,
                std.mem.readInt(u64, value[0..8], .little),
                std.mem.readInt(u64, value[8..16], .little),
            },
        );
    }

    for (start..end) |ordinal| {
        const entry = self.execution_history.chronological(self.active_guest_thread, ordinal) orelse continue;
        const offset = self.addrToOffset(entry.rip) orelse continue;
        if (offset >= self.mem.len) continue;
        const available = @min(@as(usize, entry.len), self.mem.len - offset);
        if (available == 0) continue;
        const decoded = decodeInsn(self.mem[offset..]);
        const instruction = symbol_assembly_context.Instruction.init(
            entry.rip,
            self.mem[offset..],
            decoded,
            available,
        );
        symbol_assembly_context.logDynamicInstruction(
            &self.metadata,
            instruction,
            ordinal == selected,
            .{ .rsp = entry.rsp, .rax = entry.rax, .rcx = entry.rcx, .rdx = entry.rdx },
        );
    }
}

pub fn beginGuestExit(self: anytype, exit_code: u64) bool {
    if (self.atexit_running or self.compat.atexit_count == 0) return false;
    self.atexit_running = true;
    self.pending_exit_code = exit_code;
    // Model the call boundary that libc would establish before invoking
    // the first callback. Each callback then enters with rsp % 16 == 8.
    self.regs.rsp &= ~@as(u64, 0xF);
    dispatchNextAtexit(self);
    return self.atexit_running and !self.terminated;
}

pub fn dispatchNextAtexit(self: anytype) void {
    while (self.compat.takeLastAtexit()) |entry| {
        if (entry.function == 0 or !self.isExecutableAddress(entry.function)) {
            if (self.compat.atexit_invalid_skipped <= 5) {
                machoCapturePrint(
                    "macho-processor: skipping invalid atexit callback 0x{x} argument=0x{x} dso=0x{x}\n",
                    .{ entry.function, entry.argument, entry.dso },
                );
            }
            continue;
        }
        self.push(GUEST_ATEXIT_RETURN_SENTINEL);
        if (self.terminated) return;
        self.regs.rdi = if (entry.takes_argument) entry.argument else 0;
        self.regs.rip = entry.function;
        self.atexit_callbacks_invoked +|= 1;
        if (self.verbose_trace) {
            machoCapturePrint(
                "macho-processor: invoking atexit callback #{d}: function=0x{x} argument=0x{x} dso=0x{x} takes_argument={}\n",
                .{ self.atexit_callbacks_invoked, entry.function, entry.argument, entry.dso, entry.takes_argument },
            );
        }
        return;
    }
    self.atexit_running = false;
    self.exit_code = self.pending_exit_code;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
    self.terminated = true;
    machoCapturePrint(
        "macho-processor: guest exit callbacks complete: invoked={d} exit_code={d}\n",
        .{ self.atexit_callbacks_invoked, self.exit_code },
    );
    if (self.compat.atexit_invalid_skipped > 5) {
        machoCapturePrint(
            "macho-processor: {d} additional invalid atexit callback(s) suppressed\n",
            .{self.compat.atexit_invalid_skipped - 5},
        );
    }
}

pub fn continueGuestExit(self: anytype) bool {
    if (!self.atexit_running) {
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        return false;
    }
    dispatchNextAtexit(self);
    return !self.terminated;
}

/// Base-2 math, one function per (operation, width).
///
/// Split out from the dispatch arms so the part that is easy to get wrong is
/// reachable from a test: the *width*. `exp2` takes and returns a double,
/// `exp2f` a single, and they occupy different halves of xmm0. Handling a
/// single-precision import with the double-precision reader would consume eight
/// bytes of a register holding four meaningful ones and produce a number with
/// no relationship to the argument.
fn exp2Double(argument: f64) f64 {
    return @exp2(argument);
}

fn exp2Single(argument: f32) f32 {
    return @exp2(argument);
}

fn log2Double(argument: f64) f64 {
    return @log2(argument);
}

fn log2Single(argument: f32) f32 {
    return @log2(argument);
}

test "pthread exit is thread-local only with an active cooperative context" {
    try std.testing.expect(pthreadExitIsThreadLocal(true, 0x7fff_2140));
    try std.testing.expect(!pthreadExitIsThreadLocal(true, 0));
    try std.testing.expect(!pthreadExitIsThreadLocal(false, 0x7fff_2140));
}

test "import name hash separates the slow chain's literals" {
    // The hash-fast-fail chain relies on this property: distinct literals
    // must hash apart, or a name that matches one literal would pay an extra
    // eql on its hash-twin (correct but slower). A regression here — e.g. a
    // hash that degenerates to a constant — would turn every dispatch back
    // into a full string walk.
    try std.testing.expectEqual(importNameHash("_exit"), importNameHash("_exit"));
    try std.testing.expect(importNameHash("_exit") != importNameHash("_memcpy"));
    try std.testing.expect(importNameHash("_memcpy") != importNameHash("_memmove"));
    try std.testing.expect(importNameHash("_memset") != importNameHash("___memset_chk"));
    try std.testing.expect(importNameHash("_objc_msgSend") != importNameHash("_sel_registerName"));
    try std.testing.expect(importNameHash("_objc_msgSend") != importNameHash("_objc_getClass"));
    try std.testing.expect(importNameHash("_strtoul") != importNameHash("_sysconf"));
    try std.testing.expect(importNameHash("___cxa_throw") != importNameHash("___cxa_end_catch"));
    // The two spellings of a name that the chain treats as one must agree.
    try std.testing.expectEqual(importNameHash("exit"), importNameHash("exit"));
}

// The failure these replaced was not a missing value but a wrong one: the
// unresolved-import fallback reports `rax = 0`, and a floating-point result is
// returned in xmm0, so the caller read back whatever it had just placed there —
// its own argument — and treated it as the answer.
test "base-2 math imports return the value, at the width the ABI expects" {
    // Exact at powers of two, in both widths.
    try std.testing.expectEqual(@as(f64, 8.0), exp2Double(3.0));
    try std.testing.expectEqual(@as(f64, 0.25), exp2Double(-2.0));
    try std.testing.expectEqual(@as(f32, 8.0), exp2Single(3.0));
    try std.testing.expectEqual(@as(f64, 3.0), log2Double(8.0));
    try std.testing.expectEqual(@as(f32, 10.0), log2Single(1024.0));

    // Round-trip, which is what the callers in the log actually do: a critical
    // frequency divided into a log domain and exponentiated back out.
    try std.testing.expectApproxEqRel(@as(f64, 440.0), exp2Double(log2Double(440.0)), 1e-12);
    try std.testing.expectApproxEqRel(@as(f32, 440.0), exp2Single(log2Single(440.0)), 1e-6);

    // Identity at 1.0 and 0.0 — the arguments most likely to make a wrong
    // implementation look right, so they are pinned rather than assumed.
    try std.testing.expectEqual(@as(f64, 1.0), exp2Double(0.0));
    try std.testing.expectEqual(@as(f64, 0.0), log2Double(1.0));

    // Domain edges match libm rather than trapping.
    try std.testing.expect(std.math.isNegativeInf(log2Double(0.0)));
    try std.testing.expect(std.math.isNan(log2Double(-1.0)));
}
