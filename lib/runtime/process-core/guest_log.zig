//! Guest logging and profile accounting methods.
//! Extracted from MachOState (process.zig) to reduce file size.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const macho_log = @import("dyld").event_log;
const gpu = @import("gpu");
const machoCapturePrint = macho_log.machoCapturePrint;
/// The rejection structure over a fixed phrase set is a build-time artifact;
/// deciding what a matched line *means* stays here.
const phrase_filter = @import("phrase_filter");
const startup_observer = @import("diagnostics").startup_observer;
const claim_reconciliation = @import("diagnostics").claim_reconciliation;
const interrupt_callback_transaction = @import("diagnostics").interrupt_callback_transaction;
const wait_graph = @import("diagnostics").wait_graph;
const timeout_fidelity = @import("diagnostics").timeout_fidelity;
const signal_expectation = @import("diagnostics").signal_expectation;
const wait_policy = @import("diagnostics").wait_handshake_policy;
const sync_object_identity = @import("diagnostics").sync_object_identity;
const sync_object_registry = @import("diagnostics").sync_object_registry;
const guest_critical_section = @import("diagnostics").guest_critical_section;
const guest_module_map = @import("diagnostics").guest_module_map;
const guest_wait_liveness = @import("diagnostics").guest_wait_liveness;
const deferred_work = @import("diagnostics").deferred_work;
const deadlock_predictor = @import("diagnostics").deadlock_predictor;
const bringup_failure = @import("diagnostics").bringup_failure;
const xenia_gpu_causal_trace = @import("diagnostics").xenia_gpu_causal_trace;
const run_journal = @import("diagnostics").run_journal;
const wait_audit = @import("diagnostics").wait_audit;
const guest_exception_ledger = @import("diagnostics").guest_exception_ledger;
const monotone_witness = @import("diagnostics").monotone_witness;
const preflight_lib = @import("preflight");
const import_binding_predictor = @import("import_binding_predictor.zig");
const livelock_predictor = @import("livelock_predictor.zig");
const swap_health = @import("swap_health.zig");
const constants = @import("macho_core").constants;
const utils = @import("macho_core").utils;

const GUEST_LOG_BUFFER_SIZE = constants.GUEST_LOG_BUFFER_SIZE;
const GUEST_FILE_BASE = constants.GUEST_FILE_BASE;
const PROFILE_ACCOUNT_INFO_BYTES = constants.PROFILE_ACCOUNT_INFO_BYTES;
const PROFILE_ENCRYPTED_ACCOUNT_BYTES = constants.PROFILE_ENCRYPTED_ACCOUNT_BYTES;

/// Pre-wait breadcrumbs can be interleaved when more than one guest thread is
/// producing diagnostics. A single process-global pending object lets a wait
/// result consume another thread's breadcrumb and manufactures a false edge in
/// the wait graph. Keep a small fixed table in the process state instead; the
/// result line's explicit object remains authoritative when it is present.
pub const pending_wait_capacity: usize = 32;
pub const PendingWait = struct {
    active: bool = false,
    thread: u64 = 0,
    object: u64 = 0,
    entered_step: u64 = 0,
    pc: u64 = 0,
    timeout: wait_policy.TimeoutEvidence = .{},
};

const profileIdFromUserDevice = utils.profileIdFromUserDevice;
const classifyProfileDismountCaller = utils.classifyProfileDismountCaller;
const parseFopenFlags = utils.parseFopenFlags;

pub fn standardStreamPointer(self: anytype, symbol_name: []const u8) ?u64 {
    const stream: struct { slot: *u64, handle: u64 } = if (std.mem.eql(u8, symbol_name, "___stdinp"))
        .{ .slot = &self.guest_stdin_pointer_address, .handle = GUEST_FILE_BASE }
    else if (std.mem.eql(u8, symbol_name, "___stdoutp"))
        .{ .slot = &self.guest_stdout_pointer_address, .handle = GUEST_FILE_BASE + 1 }
    else if (std.mem.eql(u8, symbol_name, "___stderrp"))
        .{ .slot = &self.guest_stderr_pointer_address, .handle = GUEST_FILE_BASE + 2 }
    else
        return null;
    if (stream.slot.* == 0) {
        stream.slot.* = self.guestAlloc(@sizeOf(u64), @alignOf(u64)) orelse return null;
        self.write64(stream.slot.*, stream.handle);
    }
    return stream.slot.*;
}

pub fn configureGuestLogMirror(self: anytype, args: []const []const u8) void {
    machoCapturePrint("ROSETTE: configureGuestLogMirror called\n", .{});
    const prefix = "--log_file=";
    var found_log_file = false;
    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, prefix) or arg.len == prefix.len) continue;
        const path = arg[prefix.len..];
        machoCapturePrint("ROSETTE: Found --log_file= argument: '{s}'\n", .{path});
        found_log_file = true;
        const path_z = self.allocator.dupeZ(u8, path) catch return;
        defer self.allocator.free(path_z);
        const flags = parseFopenFlags("a") orelse return;
        const fd = std.c.open(
            path_z.ptr,
            @bitCast(@as(u32, @intCast(flags))),
            @as(c_int, 0o666),
        );
        if (fd < 0) {
            machoCapturePrint("ROSETTE: guest log mirror could not open {s}\n", .{path});
            return;
        }
        if (self.guest_log_mirror_fd >= 0) _ = std.c.close(self.guest_log_mirror_fd);
        self.guest_log_mirror_fd = fd;
        machoCapturePrint(
            "ROSETTE: guest log mirror configured: {s}; captures synchronous Xenia logs and modeled guest stdout/stderr\n",
            .{path},
        );
        return;
    }
    if (!found_log_file) {
        machoCapturePrint("ROSETTE: No --log_file= argument found - Xenia logs will not be mirrored to file\n", .{});
        machoCapturePrint("ROSETTE: Add --log_file=/path/to/log.txt to capture Xenia output\n", .{});
    }
}

pub fn hostWriteFdAll(fd: i32, bytes: []const u8) bool {
    if (fd < 0) return false;
    var written: usize = 0;
    while (written < bytes.len) {
        const result = std.c.write(fd, bytes.ptr + written, bytes.len - written);
        if (result <= 0) return false;
        written += @intCast(result);
    }
    return true;
}

/// Markers that promote an informational guest line into the summary.
///
/// Which strings these are is fixed when Rosette is compiled, so the rejection
/// structure over them is built then too — see `summary_marker_filter` below.
const summary_markers = [_][]const u8{
    "RunTitle",
    "LaunchPath",
    "LaunchDiscImage",
    "CompleteLaunch",
    "MountPath",
    "GetFileSignature",
    "DiscImage",
    "UserModule",
    "XexModule",
    "LoadUserModule",
    "LaunchModule",
    "SetExecutableModule",
    "GraphicsSystem",
    "VulkanPresenter",
    "RING BUFFER",
    "main thread",
    "stage=",
    "FAILED",
    "failed",
    "assert",
};

/// Comptime rejection filter over `summary_markers`.
///
/// This runs on every guest log line that is not already an error or warning,
/// which is nearly all of them. It used to be 21 substring searches per line to
/// establish the common answer of "no". The filter makes one pass over the line
/// and then retires each marker with a bit test.
const summary_marker_filter = phrase_filter.Filter(&summary_markers);

pub fn shouldSummarizeGuestLog(level: u8, message: []const u8) bool {
    if (level == 'F' or level == 'E' or level == 'e' or level == 'W' or level == 'w') return true;
    return summary_marker_filter.anyPresent(message);
}

pub fn shouldSuppressRuntimeGuestLog(message: []const u8) bool {
    return std.mem.startsWith(u8, message, "FRAME LIMITER heartbeat:");
}

pub fn emitRuntimeSummaryHeartbeat(self: anytype, snapshot: startup_observer.Snapshot) void {
    if (self.summary_output_fd < 0) return;
    var buffer: [2048]u8 = undefined;
    const line = std.fmt.bufPrint(
        &buffer,
        "step={d} heartbeat thread=0x{x} rip=0x{x} symbol={s}+0x{x} heap=0x{x} imports={d} fs_open/read/write={d}/{d}/{d} runnable={d} blocked={d} condvar_waits={d}\n",
        .{
            snapshot.step,
            snapshot.thread_id,
            snapshot.rip,
            snapshot.symbol,
            snapshot.symbol_offset,
            snapshot.heap_next,
            snapshot.import_calls,
            snapshot.fs_open,
            snapshot.fs_read,
            snapshot.fs_write,
            self.pthreads.activeCount(),
            snapshot.pthread_blocked,
            snapshot.pthread_waits_collapsed,
        },
    ) catch return;
    _ = hostWriteFdAll(self.summary_output_fd, line);
}

pub fn emitGuestLog(self: anytype, prefix_char_raw: u64, address: u64, length_raw: u64) bool {
    const length = @min(length_raw, GUEST_LOG_BUFFER_SIZE);
    const message = self.guestMemoryConst(address, length) orelse return false;
    // JIT health is a lower-level observation than startup readiness. Feed it
    // even when the optional readiness contract is disabled, so explicit
    // Xenia compiler/code-cache failures cannot vanish with the gate.
    if (comptime @hasDecl(@TypeOf(self.*), "observeJitHealthText")) {
        self.observeJitHealthText(message);
    }
    // Compiler failures can cross the guest log boundary before they become a
    // null-function or no-progress symptom. The ready compiler keeps this
    // recognizer cheap and inactive for non-Xenia targets.
    if (comptime @hasDecl(@TypeOf(self.*), "observeReadyCompilerText")) {
        self.observeReadyCompilerText(message);
    }
    observePreflightGuestLog(self, message);
    observeXeniaPipelineGuestLog(self, message);
    // Route callback breadcrumbs before the broad bootstrap ladder sees them.
    // Xenia can execute Rosette's host callback through the same dispatcher as
    // the title callback; the source-aware transaction ledger must classify
    // that line first so a host fallback cannot close the PowerPC milestone.
    observeInterruptCallbackTransaction(self, message);
    observeGpuBootstrapGuestLog(self, message);
    observeXeniaGpuHandoffGuestLog(self, message);
    observeXeniaGpuCausalTraceGuestLog(self, message);
    observeImportBindingAudit(self, message);
    observeGuestEventSignal(self, message);
    observeLivelockWaits(self, message);
    observeProducerWaitLine(self, message);
    observeInterruptCallbackSlot(self, message);
    observeDrawAttrition(self, message);
    observeKernelStatus(self, message);
    observeUnknownMappings(self, message);
    observeBoundaryEntryBreadcrumb(self, message);
    observeControlledVector(self, message);
    observeFaultPauseTransaction(self, message);
    observeTimeoutFidelity(self, message);
    observeSignalExpectation(self, message);
    observeEmulatorPacketCensus(self, message);
    observeReadPointerWriteBackConfig(self, message);
    observeRunHorizonClock(self, message);
    observeReconciledClaims(self, message);
    observeKernelSurfaceAddress(self, message);
    observeKernelSurfaceReport(self, message);
    observeGuestWaitLiveness(self, message);
    observeImportBindingProbe(self, message);
    observeDeferredWork(self, message);
    observeGuestSyncObjects(self, message);
    observeRegisterApertureReachability(self, message);
    observeBringupFailure(self, message);
    self.observeBackendGuestLog(message);
    const raw_char: u8 = @truncate(prefix_char_raw);
    const prefix_char: u8 = if (raw_char >= 0x20 and raw_char <= 0x7E) raw_char else '?';
    var prefix_buffer: [32]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buffer, "[xenia] {c}> ", .{prefix_char}) catch return false;

    if (!shouldSuppressRuntimeGuestLog(message)) {
        writeLineAtomic(self.diagnostic_output_fd, &.{ prefix, message });
    }
    if (self.macho_log.isOpen()) {
        var xenia_buffer: [4096]u8 = undefined;
        const xenia_line = std.fmt.bufPrint(&xenia_buffer, "{s}{s}", .{ prefix, message }) catch "";
        self.macho_log.captureLine(xenia_line);
    }
    if (self.summary_output_fd >= 0 and shouldSummarizeGuestLog(prefix_char, message)) {
        var step_buffer: [64]u8 = undefined;
        const step_prefix = std.fmt.bufPrint(&step_buffer, "step={d} ", .{self.executed_steps}) catch "";
        writeLineAtomic(self.summary_output_fd, &.{ step_prefix, prefix, message });
    }

    observeGuestModuleImages(self, message);
    if (std.mem.startsWith(u8, message, "HostPathDevice::ResolvePath(User_")) {
        const storage_root = self.fs_forwarder.storageRoot();
        machoCapturePrint(
            "macho-processor: profile resolution trace: Xenia is resolving an internal User_<profile-id>: device; storage_root={s}; this is before any host open syscall\n",
            .{if (storage_root.len != 0) storage_root else "<not configured>"},
        );
        if (profileIdFromUserDevice(message)) |profile_id| {
            self.logProfileHostPreflight(profile_id);
        }
    }
    if (std.mem.indexOf(u8, message, "Failed to open Account file: C000000F") != null) {
        if (self.profile_account_flow.active) self.profile_account_flow.stage = .open_failed;
        machoCapturePrint(
            "macho-processor: profile resolution failure: X_STATUS_NO_SUCH_FILE (0xC000000F); the Xenia User_<profile-id>: device has no Account-file backing path. Check the following fs open/status diagnostics for a host-path attempt; if none follows, the missing mapping is inside Xenia's virtual device layer.\n",
            .{},
        );
    }
    if (std.mem.indexOf(u8, message, "Failed to decrypt account data file for XUID") != null) {
        if (self.profile_account_flow.active) self.profile_account_flow.stage = .decrypt_failed;
        machoCapturePrint(
            "macho-processor: profile crypto diagnosis: both retail and devkit Account HMAC/RC4 verification paths rejected the 404-byte payload; this is a real Account failure, unlike a success-path device dismount\n",
            .{},
        );
    }
    if (std.mem.startsWith(u8, message, "Unregistered device: User_")) {
        const stage = self.profile_account_flow.stage;
        machoCapturePrint(
            "macho-processor: profile device lifecycle: temporary User_<profile-id>: mount was unregistered at stage={s}; interpretation={s}\n",
            .{ @tagName(stage), if (stage == .decrypted or stage == .inserting or stage == .completed) "expected LoadAccount cleanup after successful Account decryption; the decoded account remains eligible for accounts_ insertion" else "early cleanup associated with an incomplete Account load" },
        );
    }

    if (self.guest_log_mirror_fd >= 0) {
        // The guest's log is the guest's. When it loops, the mirror reproduces
        // every iteration, and the one line that matters ends up underneath
        // tens of thousands of copies of one that does not. Collapsing runs
        // makes the count the finding instead of the volume — and the count is
        // strictly more informative than the copies.
        switch (self.guest_log_repetition.observe(message)) {
            .suppress => {},
            .emit => writeMirroredLine(self, prefix, message),
            .emit_after_run => |repeats| {
                var buffer: [192]u8 = undefined;
                const summary = std.fmt.bufPrint(
                    &buffer,
                    "macho-processor: guest log mirror: previous line repeated {d} more time(s) consecutively and was collapsed\n",
                    .{repeats},
                ) catch "macho-processor: guest log mirror: previous line repeated and was collapsed\n";
                _ = hostWriteFdAll(self.guest_log_mirror_fd, summary);
                machoCapturePrint("{s}", .{summary});
                writeMirroredLine(self, prefix, message);
            },
        }
        // A cycle is not a run, so the collapser above correctly leaves it
        // alone. Report it anyway: a guest rotating through the same handful of
        // lines forever is a livelock, and it is indistinguishable from healthy
        // activity if nobody counts the rotations.
        if (self.guest_log_cycles.observe(message)) |cycle| {
            machoCapturePrint(
                "macho-processor: guest log cycle: the guest has repeated a {d}-line cycle {d} times with no new content (report {d}, step {d}). Interleaved lines never collapse, so the mirror keeps growing while the run makes no progress — treat this as a livelock until something outside the cycle appears\n",
                .{ cycle.period, cycle.iterations, self.guest_log_cycles.reports, self.executed_steps },
            );
        }
    }
    self.guest_log_line_count +|= 1;
    return true;
}

/// Learn where the guest's module images live, and what each completed load
/// transaction returned.
///
/// Same justification as the GPU-bootstrap observer below: the guest's own
/// kernel tracing is the only place these events are visible without
/// instrumenting the host program, and an image the guest mapped leaves no
/// other trace Rosette can see. Both facts are parsed off lines the guest
/// already emits; nothing here changes what the guest does.
///
/// Missing a line costs an attribution, never a wrong one — the map answers
/// "no image covers this" for anything it did not observe, which is the honest
/// answer rather than a guess.
fn observeGuestModuleImages(self: anytype, message: []const u8) void {
    // "...ReadImage post-decode transition path='<path>' patch=NO base=<hex> image_size=<hex>"
    if (std.mem.indexOf(u8, message, "ReadImage post-decode transition")) |_| {
        const path = guest_module_map.between(message, "path='", "'") orelse return;
        const base = guest_module_map.hexAfter(message, " base=") orelse return;
        const size = guest_module_map.hexAfter(message, " image_size=") orelse return;
        self.guest_modules.noteImage(guest_module_map.leafName(path), base, size);
        return;
    }
    // Any guest line reporting a faulting guest program counter. Attribution is
    // the difference between "the title's own code misbehaved" and "the title
    // branched somewhere no image was ever placed", and the address alone says
    // neither.
    if (guest_module_map.hexAfter(message, "guest_pc=")) |guest_pc| {
        describeGuestAddress(self, guest_pc);
        return;
    }
    // The ordinary XexLoadImage trace is emitted at function entry, so the
    // value inside its out-parameter parentheses is the caller's PRE-CALL
    // value. Only this explicit post-call line is an authoritative result.
    if (std.mem.startsWith(u8, message, "XEX MODULE LOAD RESULT:")) {
        const path = guest_module_map.between(message, "name='", "'") orelse return;
        const status_value = guest_module_map.hexAfter(message, " status=") orelse return;
        const handle = guest_module_map.hexAfter(message, " hmodule=") orelse return;
        const status: u32 = @intCast(status_value);
        const name = guest_module_map.leafName(path);
        if (name.len == 0) return;
        self.guest_modules.noteLoadResult(name, status, handle);
        if (status == 0 and handle != 0) return;
        self.guest_module_failed_loads +|= 1;
        if (self.guest_module_failed_loads <= 8 or self.guest_module_failed_loads % 64 == 0) {
            machoCapturePrint(
                "macho-processor: guest module load failed: name={s} path='{s}' status=0x{x:0>8} handle=0x{x:0>8} failure={d} step={d}; this is an authoritative post-call result, not the old value of the out parameter\n",
                .{ name, path, status, handle, self.guest_module_failed_loads, self.executed_steps },
            );
        }
        return;
    }
}

/// Name the module image containing a guest address, for fault reporting.
pub fn describeGuestAddress(self: anytype, address: u64) void {
    if (!self.guest_modules.active()) return;
    if (self.guest_modules.attribute(address)) |found| {
        machoCapturePrint(
            "macho-processor: guest address attribution: address=0x{x} module={s} base=0x{x} offset=0x{x} size=0x{x} failed_loads={d} last_status=0x{x:0>8} last_handle=0x{x}{s}\n",
            .{
                address,    found.name,         found.base,        found.offset,
                found.size, found.loads_failed, found.last_status, found.last_handle,
                if (found.loads_failed != 0)
                    "; a load of THIS image returned no handle, so the guest is executing in an image it was told it did not have"
                else
                    "",
            },
        );
        return;
    }
    machoCapturePrint(
        "macho-processor: guest address attribution: address=0x{x} module=<none> images_known={d} failed_load_transactions={d}; no image the guest mapped covers this address, so this is not a fault inside guest code — it is a branch to somewhere no code was ever placed\n",
        .{ address, self.guest_modules.count, self.guest_modules.failed_loads },
    );
}

/// Write one mirrored guest line as a single write syscall, adding the
/// newline the guest may have omitted.
///
/// The guest logs from many threads at once (each calling AppendLogLine on
/// its own stack), so a multi-part line lets another thread's bytes land
/// inside it — that is the torn-line artifact in the mirror. Coalescing each
/// line into one buffer and one write keeps lines atomic on a regular file,
/// where the kernel serialises concurrent write syscalls.
fn writeMirroredLine(self: anytype, prefix: []const u8, message: []const u8) void {
    writeLineAtomic(self.guest_log_mirror_fd, &.{ prefix, message });
}

/// Coalesce one log line (prefix + message + optional newline) into a single
/// write syscall. Lines that fit the stack buffer take the atomic fast path;
/// oversized lines (a config dump, for instance) fall back to per-part
/// writes, which are rare enough that a tear there is a cosmetic blemish
/// rather than a parser hazard.
fn writeLineAtomic(fd: i32, parts: []const []const u8) void {
    if (fd < 0) return;
    var total: usize = 0;
    for (parts) |part| total += part.len;
    const needs_newline = parts.len == 0 or parts[parts.len - 1].len == 0 or
        parts[parts.len - 1][parts[parts.len - 1].len - 1] != '\n';
    const newline_len: usize = if (needs_newline) 1 else 0;
    if (total + newline_len <= 4096) {
        var buffer: [4096]u8 = undefined;
        var used: usize = 0;
        for (parts) |part| {
            @memcpy(buffer[used..][0..part.len], part);
            used += part.len;
        }
        if (needs_newline) {
            buffer[used] = '\n';
            used += 1;
        }
        _ = hostWriteFdAll(fd, buffer[0..used]);
        return;
    }
    for (parts) |part| _ = hostWriteFdAll(fd, part);
    if (needs_newline) _ = hostWriteFdAll(fd, "\n");
}

/// Observe the guest-driven GPU bootstrap from the mirrored guest log.
///
/// The guest's own kernel-export tracing is the only place these calls are
/// visible to the runtime without instrumenting the host program, and a step the
/// guest never took leaves no other trace by construction. Matching on the
/// export name is the observation; the ordering and preconditions live in
/// `lib/gpu`, which is what turns "callback = 0" into "this step was never
/// reachable, and here is the one that blocked it".
/// Judge the guest's own XEX import binding audit rather than relaying it.
///
/// The audit reports a thunk address, and that address is the whole basis of
/// its finding. When the address is one no thunk can have, the finding says
/// nothing about the import — and a run that prints ten "kernel import failed
/// to bind" warnings sends the reader after ten imports that are bound.
///
/// Reached only by lines that already matched the audit prefix, so the parse
/// cost is paid twenty-one times in a twelve-billion-step run.
pub fn observeImportBindingAudit(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "import_binding_predictor")) return;
    const report = import_binding_predictor.parse(message) orelse return;
    _ = self.import_binding_predictor.note(report, self.executed_steps);
}

/// `was_signalled=` in the guest's event log is NOT a state.
///
/// `XEvent::Set` is `{ event_->Set(); return 1; }` — the field is the constant
/// one, on every call, forever. An observer was built here that read a hundred
/// percent `was_signalled=1` across 1742 sets as proof that waits never consume
/// their signals, and concluded the pipeline was blocked on a synchronisation
/// defect. It was reading a literal.
///
/// The counters below are kept because the *call volume* is still real evidence
/// of handshake activity, but nothing may be concluded from the value. Left as
/// a named refusal rather than deleted so the next reader does not rediscover
/// the field and draw the same conclusion.
pub fn observeGuestEventSignal(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_event_sets")) return;
    const marker = "was_signalled=";
    if (std.mem.indexOf(u8, message, marker) == null) return;
    self.guest_event_sets +|= 1;
}

/// Feed the livelock predictor from the guest's own kernel tracing.
///
/// The predictor's contract is that the *caller* decides whether the ring is
/// stalled; this observer is that caller. It recognises three operation
/// families in the mirrored guest log — KeWaitForSingleObject (consumed and
/// timed out), xeKeSetEvent, and KeReleaseSemaphore — extracts the object each
/// one operated on, and passes the ring-stalled verdict along with it.
///
/// The wait result line carries the object only after the fork's
/// instrumentation change; the detailed pre-wait line (`KeWaitForSingleObject
/// tid=... guest_obj=...`) is remembered so the result line can be paired with
/// an object even against a pre-change binary. Reached only from the guest-log
/// bridge: one string compare per line when the line is not a wait.
pub fn observeLivelockWaits(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    // The first line after a wait result is the only cheap, always-available
    // continuation witness in the mirrored guest stream. Feed it before the
    // current line is interpreted: if the current line is another wait result,
    // it closes the previous wait and the new result then arms its own slot.
    // This ordering prevents a result from being mistaken for its own
    // continuation while still observing ordinary guest log lines.
    if (comptime @hasField(State, "wait_graph")) {
        self.wait_graph.observeGuestActivityWithEvidence(
            activeGuestThread(self),
            waitPcEvidence(self, message),
            self.executed_steps,
            message,
        );
    }
    if (comptime !@hasField(State, "livelock_predictor")) return;
    const operation = livelockOperation(self, message) orelse return;
    if (comptime @hasDecl(@TypeOf(self.*), "noteReadyCompilerWait")) {
        switch (operation.op) {
            .wait => self.noteReadyCompilerWait(operation.object, true, self.executed_steps),
            .wait_timeout => self.noteReadyCompilerWait(operation.object, false, self.executed_steps),
            else => {},
        }
    }
    // The mirror runs on the guest thread that wrote the line, so the active
    // thread is the one that performed the operation. Naming it is what makes
    // "find who waits on it" answerable.
    self.livelock_predictor.note(self, operation.op, operation.object, self.active_guest_thread, livelockRingStalled(self));

    // The same event, recorded as a graph edge. The predictor answers "is this
    // signature repeating"; the graph answers "who is on each end and is the
    // pair going anywhere", which is the question a matched handshake needs and
    // a repetition count cannot reach.
    if (comptime @hasField(State, "wait_graph")) {
        const role: wait_graph.Role = switch (operation.op) {
            .wait, .wait_timeout => .waiter,
            .set_event, .release_semaphore => .signaller,
        };
        if (role == .waiter) {
            const thread = activeGuestThread(self);
            const pc = waitPcEvidence(self, message);
            // Object-family evidence is useful for successful waits too. In
            // particular, retaining Xenia type=8 here lets the policy say
            // "semaphore with unknown park timing" instead of erasing the
            // object semantics just because the result was STATUS_SUCCESS.
            self.wait_graph.observeWaitWithTimeoutEvidence(
                operation.object,
                thread,
                pc,
                self.executed_steps,
                operation.timing,
                operation.timeout,
            );
            if (operation.successful_result) {
                self.wait_graph.noteSuccessfulWaitResult(operation.object);
            }
            self.wait_graph.noteWaitCompletionWithEvidence(
                operation.object,
                thread,
                pc,
                self.executed_steps,
                operation.timing,
            );
        } else {
            self.wait_graph.observeWithEvidence(
                role,
                operation.object,
                self.active_guest_thread,
                waitPcEvidence(self, message),
                self.executed_steps,
            );
        }
    }
}

/// The guest program counter, when the state carries one. Recorded with each
/// edge so a stalled handshake names the call site rather than only the object,
/// which is the difference between a finding and a search.
fn guestProgramCounter(self: anytype) u64 {
    const State = @TypeOf(self.*);
    if (comptime @hasField(State, "regs")) return self.regs.rip;
    return 0;
}

/// Return the PC that belongs to the stream which produced a synchronization
/// breadcrumb. Rosette's own RIP is a direct observation of the translated
/// x86 process. A newer Xenia logger may additionally provide a tracked
/// PowerPC source PC; when it explicitly says that source tracking is absent,
/// do not silently substitute Rosette's RIP and call it guest control flow.
fn waitPcEvidence(self: anytype, message: []const u8) wait_graph.PcEvidence {
    const explicit_guest_pc = std.mem.indexOf(u8, message, "pc_domain=xenia_guest_ppc") != null or
        std.mem.indexOf(u8, message, "guest_pc_valid=") != null;
    if (explicit_guest_pc) {
        // An explicit provenance domain without an explicit validity bit is
        // still incomplete evidence. A producer that knows the PC is valid
        // must say so; otherwise a seeded/stale value can leak back into the
        // continuation ledger as if it were a tracked guest instruction.
        const valid = parseFlagAfter(message, "guest_pc_valid=") orelse false;
        const address = if (valid) parseHex64After(message, "guest_pc=") orelse 0 else 0;
        const quality: wait_graph.PcQuality = if (!valid or address == 0)
            .unavailable
        else if (std.mem.indexOf(u8, message, "guest_pc_quality=tracked") != null)
            .tracked
        else if (std.mem.indexOf(u8, message, "guest_pc_quality=direct") != null)
            .direct
        else if (std.mem.indexOf(u8, message, "guest_pc_quality=seeded") != null)
            .seeded
        else
            .unavailable;
        return .{
            .address = address,
            .domain = .xenia_guest_ppc,
            .quality = quality,
        };
    }

    const address = guestProgramCounter(self);
    return .{
        .address = address,
        .domain = .rosette_translated_x86,
        .quality = if (address == 0) .unavailable else .direct,
    };
}

fn activeGuestThread(self: anytype) u64 {
    const State = @TypeOf(self.*);
    if (comptime @hasField(State, "active_guest_thread")) return self.active_guest_thread;
    return 0;
}

/// Remember one pre-wait breadcrumb without allowing threads to overwrite each
/// other's pending object. This is only a compatibility path for result lines
/// that omit `guest_obj`/`obj_ptr`; modern lines are paired by their explicit
/// identity and do not depend on this table.
fn rememberPendingWait(
    self: anytype,
    object: u64,
    timeout: wait_policy.TimeoutEvidence,
) void {
    const State = @TypeOf(self.*);
    if (object == 0) return;
    const thread = activeGuestThread(self);
    if (comptime @hasField(State, "livelock_pending_waits")) {
        var empty: ?*PendingWait = null;
        for (&self.livelock_pending_waits) |*entry| {
            if (entry.active and entry.thread == thread) {
                entry.object = object;
                entry.entered_step = self.executed_steps;
                entry.pc = guestProgramCounter(self);
                entry.timeout = timeout;
                return;
            }
            if (!entry.active and empty == null) empty = entry;
        }
        if (empty) |entry| {
            entry.* = .{
                .active = true,
                .thread = thread,
                .object = object,
                .entered_step = self.executed_steps,
                .pc = guestProgramCounter(self),
                .timeout = timeout,
            };
            if (comptime @hasField(State, "livelock_pending_wait_active")) {
                self.livelock_pending_wait_active +|= 1;
            }
        } else if (comptime @hasField(State, "livelock_pending_wait_dropped")) {
            // Do not evict an older breadcrumb: an invented pairing is worse
            // than an explicitly reported missing one.
            self.livelock_pending_wait_dropped +|= 1;
        }
        return;
    }
    // Small synthetic states used by older callers still get the old behavior.
    if (comptime @hasField(State, "livelock_pending_wait_object")) {
        self.livelock_pending_wait_object = object;
    }
}

fn takePendingWait(self: anytype) ?PendingWait {
    const State = @TypeOf(self.*);
    const thread = activeGuestThread(self);
    if (comptime @hasField(State, "livelock_pending_waits")) {
        for (&self.livelock_pending_waits) |*entry| {
            if (!entry.active or entry.thread != thread) continue;
            const pending = entry.*;
            entry.* = .{};
            if (comptime @hasField(State, "livelock_pending_wait_active")) {
                self.livelock_pending_wait_active -|= 1;
            }
            return pending;
        }
        return null;
    }
    if (comptime @hasField(State, "livelock_pending_wait_object")) {
        if (self.livelock_pending_wait_object == 0) return null;
        const pending = PendingWait{
            .active = true,
            .thread = thread,
            .object = self.livelock_pending_wait_object,
        };
        self.livelock_pending_wait_object = 0;
        return pending;
    }
    return null;
}

/// Fold a synchronisation object's address onto the one a reader can act on.
///
/// The console address is canonical: it appears in the title's own memory, it
/// is stable across runs, and every other guest-side diagnostic uses it. Host
/// pointers move with the emulator's mapping base and mean nothing outside one
/// process — so a predictor keyed on a host pointer reports an object nobody
/// can find, and splits its evidence away from the same object's console name.
/// Feed one synchronisation event into the wait audit.
///
/// Shares the livelock predictor's observation points on purpose: two
/// subsystems reasoning about the same behaviour from different event streams
/// is how they end up disagreeing about what happened.
fn auditSyncOperation(
    self: anytype,
    message: []const u8,
    object: u64,
    operation: wait_audit.Operation,
    timeout: wait_policy.TimeoutEvidence,
) void {
    if (comptime !@hasField(@TypeOf(self.*), "wait_audit")) return;
    if (object == 0) return;
    const handle: u32 = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
    const type_code: u32 = parseDecimalAfterU32(message, "type=") orelse 0;
    self.wait_audit.observeWithTimeout(
        object,
        operation,
        self.active_guest_thread,
        handle,
        type_code,
        self.executed_steps,
        timeout,
    );
}

fn parseDecimalAfterU32(message: []const u8, key: []const u8) ?u32 {
    const value = parseDecimalAfter(message, key) orelse return null;
    return if (value > std.math.maxInt(u32)) null else @intCast(value);
}

fn canonicalSyncObject(self: anytype, address: u64) u64 {
    if (comptime !@hasField(@TypeOf(self.*), "sync_object_identity")) return address;
    return self.sync_object_identity.resolve(address).canonical;
}

fn canonicalHostSyncObject(self: anytype, address: u64) u64 {
    if (comptime !@hasField(@TypeOf(self.*), "sync_object_identity")) return address;
    return self.sync_object_identity.resolveHost(address).canonical;
}

fn canonicalHostSyncObjectWithHandle(self: anytype, address: u64, handle: u32) u64 {
    if (comptime !@hasField(@TypeOf(self.*), "sync_object_identity")) return address;
    if (handle != 0) return self.sync_object_identity.resolveHandle(address, handle).canonical;
    return self.sync_object_identity.resolveHost(address).canonical;
}

fn canonicalSyncObjectWithHandle(self: anytype, address: u64, handle: u32) u64 {
    if (comptime !@hasField(@TypeOf(self.*), "sync_object_identity")) return address;
    return self.sync_object_identity.resolveHandle(address, handle).canonical;
}

/// Learn the two independent identities that a detailed wait/result record
/// supplies. Result records are more common than entry records in this run,
/// so restricting pair learning to entries left the identity table empty even
/// though every result line carried `obj_ptr`, `guest_obj`, and `handle`.
fn observeSyncObjectIdentity(self: anytype, message: []const u8) void {
    if (comptime !@hasField(@TypeOf(self.*), "sync_object_identity")) return;
    const host = parseFixedWidthHexAfter(message, "obj_ptr=", sync_object_field_width) orelse 0;
    const console = parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width) orelse 0;
    const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
    if (host != 0 and console != 0) self.sync_object_identity.observePair(host, console);
    if (handle != 0 and console != 0)
        self.sync_object_identity.observeHandleObject(handle, host, console);
}

/// Translate the Xenia object type and event-mode fields into the shared
/// policy vocabulary. The numeric type is not enough to call a timeout a poll:
/// a manual-reset event carries different guest semantics from an auto-reset
/// event, even when both are represented by the same host wait primitive.
/// The codes are `xe::kernel::XObject::Type`, in declaration order. Written out
/// in full rather than as the five cases that happened to be needed, because
/// the `else => .unknown` this replaces is what sent every Mutant wait — 1767
/// of them in the 2026-09-05 run — into an unclassified bucket that no wait
/// policy could reason about, while the report called it `unknown` and named
/// no code to add.
///
/// The types with no dispatcher header cannot be waited on at all. They get
/// their own answer rather than `unknown`: seeing one here is a finding about
/// the parse or the guest, not a request for a table entry.
fn xeniaWaitObjectKind(
    type_code: u32,
    event_mode_known: bool,
    manual_reset: bool,
) wait_policy.ObjectKind {
    return switch (type_code) {
        2 => if (!event_mode_known)
            .unknown
        else if (manual_reset)
            .guest_manual_reset_event
        else
            .guest_auto_reset_event,
        4 => .io_completion,
        6 => .guest_mutant,
        7 => .guest_notify_listener,
        8 => .guest_semaphore,
        12 => .thread_join,
        13 => .timer,
        // Undefined, Enumerator, File, Module, Session, Socket, SymbolicLink,
        // Device: no dispatcher header, so no wait can name them.
        0, 1, 3, 5, 9, 10, 11, 14 => .not_waitable,
        else => .unknown,
    };
}

/// Whether an event mode is a property this object can have.
///
/// Only an Event has one. Xenia prints `event_mode=unknown` on Semaphores,
/// Mutants, Threads and Timers because the field is in its line format, not
/// because anything failed to determine it — and Rosette echoed that word
/// seven thousand times in one run, which is most of the `unknown` in the log
/// and none of the missing mappings. "Not applicable" and "not determined" are
/// opposite states and the report must not spell them the same way.
pub fn eventModeApplies(kind: wait_policy.ObjectKind) bool {
    return switch (kind) {
        .guest_auto_reset_event, .guest_manual_reset_event => true,
        // An Event whose mode was not in the line is genuinely undetermined,
        // and `unknown` is the honest word for it there.
        .unknown => true,
        else => false,
    };
}

/// Assemble timeout evidence from a pre-wait or result line. A requested
/// timeout is stronger than an elapsed duration: the latter only proves that
/// the host waited, while the former proves the guest selected a finite
/// deadline. If only a result duration exists, retain it as non-requested
/// evidence so the policy cannot accidentally promote it to a bounded poll.
fn timeoutEvidenceFromMessage(
    message: []const u8,
    inherited: wait_policy.TimeoutEvidence,
    timed_out: bool,
) wait_policy.TimeoutEvidence {
    var evidence = inherited;
    // Result records from the wait bridge are now self-contained. Prefer the
    // guest request over the host's elapsed duration, and keep the old
    // `timeout_ms` breadcrumb as a compatibility path for pre-contract lines.
    // The requested key must be parsed first: it deliberately resembles the
    // legacy key and a substring match would silently read the wrong value.
    const requested_timeout_present = parseFlagAfter(message, "requested_timeout_present=");
    const requested_timeout_ms = parseSignedDecimalAfter(message, "requested_timeout_ms=");
    if (requested_timeout_ms) |value| {
        evidence.timeout_ms = value;
        evidence.timeout_known = true;
        evidence.requested_known = true;
        evidence.requested = requested_timeout_present orelse true;
    } else if (parseSignedDecimalAfter(message, "timeout_ms=")) |value| {
        // `timeout_ms` on a pre-wait line is the converted guest request. On a
        // result-only legacy line it is still the strongest available timing
        // field, so preserve the historical behavior and mark it requested.
        evidence.timeout_ms = value;
        evidence.timeout_known = true;
        evidence.requested_known = true;
        evidence.requested = true;
    } else if (!evidence.timeout_known and timed_out) {
        if (parseDecimalAfter(message, "duration_ms=")) |duration| {
            if (duration <= std.math.maxInt(i64)) {
                evidence.timeout_ms = @intCast(duration);
                evidence.timeout_known = true;
                // Elapsed host time is not guest deadline evidence. Leave the
                // request provenance unknown so a short host wait cannot be
                // upgraded to a bounded poll.
                evidence.requested_known = false;
                evidence.requested = false;
            }
        }
    }

    const type_code = parseDecimalAfterU32(message, "type=") orelse 0;
    const manual_reset = std.mem.indexOf(u8, message, "event_mode=manual_reset") != null;
    const auto_reset = std.mem.indexOf(u8, message, "event_mode=auto_reset") != null;
    const event_mode_known = manual_reset or auto_reset;
    if (event_mode_known) {
        evidence.event_mode_known = true;
        evidence.manual_reset = manual_reset;
    }
    if (type_code != 0) evidence.object_kind = xeniaWaitObjectKind(
        type_code,
        evidence.event_mode_known,
        evidence.manual_reset,
    );
    return evidence;
}

const LivelockOperation = struct {
    op: livelock_predictor.Operation,
    object: u64,
    /// The result code is independent from timing evidence. Keep the raw
    /// STATUS_SUCCESS fact so the graph can reconcile a successful semaphore
    /// return even when its park/ready timing remains unknown.
    successful_result: bool = false,
    /// Result timing is independent from the operation kind. A successful
    /// wait only proves a real parked-to-signalled handoff when the record also
    /// proves it was not ready on entry. Xenia's historical `blocked` label can
    /// be derived from elapsed host duration alone, so that word by itself is
    /// not enough to accuse a missing signal.
    timing: wait_graph.WaitTiming = .unknown,
    timeout: wait_policy.TimeoutEvidence = .{},
};

/// Whether a successful wait result carries causal evidence that it parked.
///
/// A future producer can emit either explicit witness flag. Current event
/// records instead carry a valid pre-wait state; zero proves the object was not
/// ready when the wait began. Semaphore records in the current Xenia log carry
/// neither fact, so their duration-derived `wait_disposition=blocked` remains
/// unknown rather than becoming an orphan-wait claim.
fn waitResultProvesBlocked(message: []const u8) bool {
    if (parseFlagAfter(message, "blocked_witness=") orelse false) return true;
    if (parseFlagAfter(message, "wait_blocked_proven=") orelse false) return true;
    if (!(parseFlagAfter(message, "entry_state_valid=") orelse false)) return false;
    return (parseFixedWidthHexAfter(message, "entry_state=", 8) orelse return false) == 0;
}

fn livelockOperation(self: anytype, message: []const u8) ?LivelockOperation {
    // Detailed pre-wait line: remember the object for the coming result line.
    // The result line alone cannot name the object against a pre-change binary.
    if (std.mem.indexOf(u8, message, "KeWaitForSingleObject tid=") != null or
        std.mem.indexOf(u8, message, "NtWaitForSingleObjectEx tid=") != null)
    {
        // This line names the object *both* ways, which is the only place the
        // two are stated together. Learning the pair here is what stops every
        // later line that prints only one of them from being attributed to a
        // second, non-existent object.
        observeSyncObjectIdentity(self, message);
        const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
        const timeout = timeoutEvidenceFromMessage(message, .{}, false);
        if (parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width)) |object| {
            rememberPendingWait(self, canonicalSyncObjectWithHandle(self, object, handle), timeout);
        } else if (parseFixedWidthHexAfter(message, "obj_ptr=", sync_object_field_width)) |object| {
            rememberPendingWait(self, canonicalHostSyncObjectWithHandle(self, object, handle), timeout);
        } else if (std.mem.indexOf(u8, message, "obj_ptr=") != null) {
            // The field is present and short: the line was spliced. Counting it
            // keeps a truncated read from silently becoming a phantom object.
            if (comptime @hasField(@TypeOf(self.*), "sync_object_identity")) {
                self.sync_object_identity.truncated_reads +|= 1;
            }
        }
        return null;
    }
    // Wait result line: the wait actually happened (or timed out). STATUS_
    // TIMEOUT is 0x102; a guest rotating through timeout waits is re-polling
    // an object nobody will ever signal.
    const is_ke_wait_result = std.mem.indexOf(u8, message, "KeWaitForSingleObject result=") != null;
    const is_nt_wait_result = std.mem.indexOf(u8, message, "NtWaitForSingleObjectEx result=") != null;
    if (is_ke_wait_result or is_nt_wait_result) {
        const result = parseHexAfter(message, "result=") orelse return null;
        const op: livelock_predictor.Operation = if (result == 0x102) .wait_timeout else .wait;
        const timing: wait_graph.WaitTiming = if (op == .wait_timeout or
            std.mem.indexOf(u8, message, "wait_disposition=timed_out") != null)
            .timed_out
        else if (std.mem.indexOf(u8, message, "wait_disposition=ready_on_entry") != null)
            .ready_on_entry
        else if (std.mem.indexOf(u8, message, "wait_disposition=blocked") != null and
            waitResultProvesBlocked(message))
            .blocked
        else
            .unknown;
        const pending = takePendingWait(self);
        const timeout = timeoutEvidenceFromMessage(
            message,
            if (pending) |breadcrumb| breadcrumb.timeout else .{},
            op == .wait_timeout,
        );
        observeSyncObjectIdentity(self, message);
        const result_handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
        const explicit_object = if (parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width)) |value|
            canonicalSyncObjectWithHandle(self, value, result_handle)
        else if (parseFixedWidthHexAfter(message, "obj_ptr=", sync_object_field_width)) |value|
            canonicalHostSyncObjectWithHandle(self, value, result_handle)
        else
            0;
        if (pending) |breadcrumb| {
            if (explicit_object != 0 and explicit_object != breadcrumb.object) {
                if (comptime @hasField(@TypeOf(self.*), "livelock_pending_wait_identity_conflicts")) {
                    self.livelock_pending_wait_identity_conflicts +|= 1;
                }
            }
        }
        const object: u64 = if (explicit_object != 0)
            explicit_object
        else if (pending) |breadcrumb|
            breadcrumb.object
        else blk: {
            if (comptime @hasField(@TypeOf(self.*), "livelock_pending_wait_unmatched_results")) {
                self.livelock_pending_wait_unmatched_results +|= 1;
            }
            break :blk 0;
        };
        if (object == 0) return null;
        auditSyncOperation(
            self,
            message,
            object,
            if (op == .wait_timeout) .wait_timeout else .wait,
            timeout,
        );
        return .{
            .op = op,
            .object = object,
            .successful_result = result == 0,
            .timing = timing,
            .timeout = timeout,
        };
    }
    if (std.mem.indexOf(u8, message, "DEBUG: xeKeSetEvent: ptr=") != null) {
        const object = parseHexAfter(message, "ptr=") orelse return null;
        if (object == 0) return null;
        const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
        if (comptime @hasField(@TypeOf(self.*), "sync_object_identity")) {
            if (handle != 0) self.sync_object_identity.observeHandleObject(handle, 0, object);
        }
        const canonical = canonicalSyncObjectWithHandle(self, object, handle);
        auditSyncOperation(self, message, canonical, .signal, .{});
        return .{ .op = .set_event, .object = canonical };
    }
    // The generic `d>`-level export trace prints `KeReleaseSemaphore(<ptr>, ...)`
    // on every call; the fork's own instrumentation prints the same shape at
    // `i>` level with the object named. Either way the pointer is the first hex
    // token after the open paren.
    if (std.mem.indexOf(u8, message, "KeReleaseSemaphore(") != null) {
        const raw = firstHexAfterOpenParen(message, "KeReleaseSemaphore(") orelse return null;
        if (raw == 0) return null;
        const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
        if (comptime @hasField(@TypeOf(self.*), "sync_object_identity")) {
            if (handle != 0) self.sync_object_identity.observeHandleObject(handle, 0, raw);
        }
        const object = canonicalSyncObjectWithHandle(self, raw, handle);
        auditSyncOperation(self, message, object, .signal, .{});
        return .{ .op = .release_semaphore, .object = object };
    }
    return null;
}

/// Whether the ring write pointer is stalled, using the same bound as
/// swap_health so the predictor and the frontier never disagree about what
/// "stalled" means. Before the ring ever publishes, a wait cycle is only a
/// livelock candidate once the run is well past the bootstrap window.
fn livelockRingStalled(self: anytype) bool {
    const publication = &self.gpu_ring_publication;
    if (publication.advances == 0) {
        return self.executed_steps > swap_health.STALL_STEPS;
    }
    const quiet = publication.stalledSteps(self.executed_steps) orelse return false;
    return quiet >= swap_health.STALL_STEPS;
}

/// The first hex token after `name(` — the object pointer in the generic
/// `Name(args)` export trace.
fn firstHexAfterOpenParen(line: []const u8, name: []const u8) ?u64 {
    const at = std.mem.indexOf(u8, line, name) orelse return null;
    var text = line[at + name.len ..];
    while (text.len != 0 and text[0] == ' ') text = text[1..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u64, text[0..length], 16) catch null;
}

/// Join the emulator's own bootstrap-ordinal report into Rosette's model of
/// the kernel surface.
///
/// The emulator already prints, per ordinal, whether the title imported it and
/// whether anything touched it. What it does not do is ask the next question:
/// for a *variable* export, is there a usable value at the address the title
/// will read? Rosette can answer that, because it owns guest memory. Parsing
/// the line the emulator already emits avoids a second, disagreeing source of
/// truth about which ordinals the title imported.
///
/// Line shape:
///   `RING BUFFER: bootstrap ordinal runtime ordinal=0x1BE name=VdGlobalDevice
///    static_imported=YES ... vd_call_count=0 variable_export=YES
///    runtime_activity=NO`
pub fn observeKernelSurfaceReport(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_kernel_surface")) return;
    if (std.mem.indexOf(u8, message, "bootstrap ordinal runtime ordinal=") == null) return;
    const ordinal_value = parseHexAfter(message, "ordinal=") orelse return;
    if (ordinal_value > std.math.maxInt(u16)) return;
    const which = gpu.kernel_surface.Surface.fromOrdinal(@intCast(ordinal_value)) orelse return;

    const imported = std.mem.indexOf(u8, message, "static_imported=YES") != null;
    const activity = std.mem.indexOf(u8, message, "runtime_activity=YES") != null;
    const calls = parseDecimalAfter(message, "vd_call_count=") orelse 0;
    self.gpu_kernel_surface.observeBinding(which, imported, activity, calls);
    if (!which.isVariable() or !imported) return;

    // A variable export is only interesting if a reader would get something
    // usable. Resolve the address from the emulator's export table dump if it
    // has been seen, then read what the title would read.
    const address = self.gpu_kernel_surface_addresses.lookup(which.ordinal()) orelse return;
    self.gpu_kernel_surface.observeAddress(which, address);
    // Xbox kernel variables are big-endian in guest memory.
    const bytes = readGuestConsoleDword(self, address) orelse return;
    self.gpu_kernel_surface.observeValue(which, bytes);
    observeKernelVariableIndirection(self, which_ordinal_u16(ordinal_value), address, bytes);
}

fn which_ordinal_u16(value: u64) u16 {
    return @intCast(value & 0xFFFF);
}

/// Read one big-endian dword out of the emulated console's virtual address
/// space.
///
/// Two translations, both already modelled: the console address resolves to the
/// address translated stores actually use, and that resolves to Rosette's own
/// guest memory. Doing it here rather than at each call site is what keeps the
/// byte order in one place — a console dword read natively is the mistake that
/// turns every pointer into a plausible-looking wrong one.
fn readGuestConsoleDword(self: anytype, console_address: u32) ?u32 {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "xenia_memory_views")) return null;
    const host = self.xenia_memory_views.virtualHostAddress(console_address) orelse return null;
    const bytes = self.guestMemoryConst(host, 4) orelse return null;
    return std.mem.readInt(u32, bytes[0..4], .big);
}

/// Follow the second dereference behind a kernel variable import.
///
/// The import slot holds the *address of* the kernel's storage, not the value.
/// Reading the slot and calling it the value cannot tell a healthy pointer from
/// the loader's unimplemented sentinel — which is a large non-zero number and
/// therefore reads as a populated variable. See `lib/gpu/kernel_variables.zig`.
fn observeKernelVariableIndirection(self: anytype, ordinal: u16, slot_address: u32, slot_value: u32) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_kernel_variables")) return;
    const which = gpu.kernel_variables.Variable.fromOrdinal(ordinal) orelse return;
    self.gpu_kernel_variables.observeImport(which, true, slot_address);
    self.gpu_kernel_variables.observeSlot(which, slot_value);
    if (!gpu.kernel_variables.plausiblePointer(slot_value)) return;
    if (gpu.kernel_variables.isUnimplementedSentinel(slot_value, ordinal)) return;
    const storage = readGuestConsoleDword(self, slot_value) orelse return;
    self.gpu_kernel_variables.observeStorage(which, storage);
}

/// Record code generation that failed and the demand that later needs it.
///
/// These two events are billions of steps apart and in different subsystems, so
/// without a ledger joining them the crash is attributed to the resolver that
/// found a null rather than to the emit that produced one. The reason — an
/// Xbyak error code and its text — exists only at the failure, so it is
/// captured there and carried forward.
pub fn observeDeferredWork(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "deferred_work")) return;

    // `X64Emitter: Xbyak error <reason> (code=N) finalizing guest function
    //  <ADDR> — function left undefined`
    if (std.mem.indexOf(u8, message, "function left undefined") != null) {
        const marker = "finalizing guest function ";
        if (std.mem.indexOf(u8, message, marker)) |at| {
            const address = parseHexAfter(message, marker) orelse return;
            _ = at;
            const reason_start = std.mem.indexOf(u8, message, "Xbyak error ");
            const reason: []const u8 = if (reason_start) |start| blk: {
                const rest = message[start..];
                const end = std.mem.indexOf(u8, rest, " finalizing") orelse rest.len;
                break :blk rest[0..end];
            } else "code generation failed";
            self.deferred_work.noteFailed(
                address,
                deferred_work.Kind.guest_function_codegen,
                reason,
                self.executed_steps,
            );
            machoCapturePrint(
                "macho-processor: DEFERRED WORK PREDICTOR: latent_failure id=0x{x} kind=guest_function_codegen reason='{s}' step={d}; the first demand re-attempts the translation once, so a transient failure can still recover; only a second failure is a decided crash whose trigger is any call to this address. {s}\n",
                .{ address, reason, self.executed_steps, deferred_work.Kind.guest_function_codegen.consequence() },
            );
            // A caught exception that produced this failure is the ledger's
            // original scenario — the unwinder completed and the handler
            // abandoned the work it was protecting. Correlate here, at the
            // failure site, rather than at the demand site where the window
            // has long since closed: the crash lands at the *call* to the
            // undefined function, far outside the exception correlation
            // window. With the fork's retry repair, the first demand
            // re-attempts the translation, so only a second failure is fatal
            // — but the abandonment is still the origin of the chain.
            if (comptime @hasField(@TypeOf(self.*), "guest_exceptions")) {
                if (self.guest_exceptions.noteDeferredFailure(self.executed_steps)) |record| {
                    machoCapturePrint(
                        "macho-processor: GUEST EXCEPTION PREDICTOR: CAUGHT_THEN_DEFERRED type={s} code={d} site={s} thrown_at_step={d} deferred_at_step={d}; {s}\n",
                        .{ record.name(), record.code, record.site(), record.first_step, self.executed_steps, record.outcome.meaning() },
                    );
                }
            }
        }
        return;
    }

    // The resolver asserts without naming the address it wanted, so the demand
    // is joined to the failure by kind rather than by identity.
    if (std.mem.indexOf(u8, message, "ResolveFunction: (fn) != nullptr") != null) {
        const suspects = self.deferred_work.noteUnaddressedDemand(
            deferred_work.Kind.guest_function_codegen,
            self.executed_steps,
        );
        // A terminal event close behind an exception is what promotes a clean
        // catch to a suspect. The distance between them is the whole of the
        // evidence, so the correlation is left to the ledger's window rather
        // than asserted here.
        if (comptime @hasField(@TypeOf(self.*), "guest_exceptions")) {
            if (self.guest_exceptions.noteTerminal(self.executed_steps)) |record| {
                machoCapturePrint(
                    "macho-processor: GUEST EXCEPTION PREDICTOR: CAUGHT_THEN_TERMINAL type={s} code={d} site={s} thrown_at_step={d} terminal_at_step={d}; {s}\n",
                    .{ record.name(), record.code, record.site(), record.first_step, self.executed_steps, record.outcome.meaning() },
                );
            }
        }
        if (suspects == 0) return;
        if (self.deferred_work.unambiguousSuspect(deferred_work.Kind.guest_function_codegen)) |item| {
            machoCapturePrint(
                "macho-processor: DEFERRED WORK PREDICTOR: FAILED_THEN_DEMANDED id=0x{x} reason='{s}' failed_at_step={d} demanded_at_step={d}; the resolver did not name the address it wanted and exactly one translation had failed, so the attribution is unambiguous. This crash belongs to that failure, not to the resolver\n",
                .{ item.id, item.reason(), item.deferred_step, self.executed_steps },
            );
        } else {
            machoCapturePrint(
                "macho-processor: DEFERRED WORK PREDICTOR: FAILED_THEN_DEMANDED suspects={d} demanded_at_step={d}; the resolver did not name the address it wanted and more than one translation had failed, so every failed translation listed above is a suspect and none can be singled out\n",
                .{ suspects, self.executed_steps },
            );
        }
    }
}

/// Record a subsystem that failed to come up, and the thread exit that makes
/// the failure permanent.
///
/// The emulator logs the reason, returns false, and its thread exits — all
/// correct, all silent from outside. Everything that was going to wait on that
/// subsystem then waits on something nothing will ever signal, and the run
/// settles into a steady spin with no error anywhere near the symptom.
pub fn observeBringupFailure(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "bringup_failures")) return;
    if (bringup_failure.classifyLine(message)) |subsystem| {
        const before = self.bringup_failures.count;
        self.bringup_failures.noteFailure(subsystem, message, self.executed_steps);
        if (self.bringup_failures.count != before) machoCapturePrint(
            "macho-processor: BRINGUP FAILURE: subsystem={s} step={d} reason='{s}'; {s}\n",
            .{ subsystem.label(), self.executed_steps, message, subsystem.blocks() },
        );
        return;
    }
    // A thread exit is what turns "may still recover" into "cannot". The
    // emulator names the thread, so the subsystem is recoverable from it.
    if (std.mem.indexOf(u8, message, "Thread is now exiting") != null or
        std.mem.indexOf(u8, message, "[ThreadExit]") != null)
    {
        if (std.mem.indexOf(u8, message, "GPU Command") != null or
            std.mem.indexOf(u8, message, "01000010") != null)
        {
            self.bringup_failures.noteThreadExit(.gpu_command_processor);
        }
    }
}

/// Learn that the Xenos register aperture is reachable.
///
/// The emulator states this directly — `MMIO handler probe CP_RB_BASE
/// addr=7FC80700 handler_registered=YES` — and it is the only evidence that
/// exists, because the aperture's pages are unreadable by design and a title
/// that programs its GPU through kernel exports never stores to them. Waiting
/// for a guest store to prove reachability conflates "could a store arrive"
/// with "did one", and the first is the precondition.
pub fn observeRegisterApertureReachability(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_register_aperture_reachable")) return;
    if (self.gpu_register_aperture_reachable) return;
    if (std.mem.indexOf(u8, message, "handler_registered=YES") == null) return;
    if (std.mem.indexOf(u8, message, "MMIO handler probe") == null and
        std.mem.indexOf(u8, message, "MMIO protection invariant") == null) return;
    self.gpu_register_aperture_reachable = true;
    machoCapturePrint(
        "macho-processor: GPU PRE-INITIALIZATION: the Xenos register aperture is reachable — the emulator has registered a handler for its pages, so a store that arrives is dispatched rather than lost. This is reachability, not usage: a title programming its GPU through kernel exports never stores here\n",
        .{},
    );
}

/// Learn guest synchronisation objects and who raises them.
///
/// The guest's own wait logging omits the object, so a guest-side wait-for graph
/// cannot be built from waits. Notifications do carry an object, and knowing
/// which objects are raised at all is what separates "nobody ever signalled
/// this" from "the signal is late".
fn lifecycleTokenAfter(message: []const u8, key: []const u8) ?[]const u8 {
    const at = fieldOffset(message, key) orelse return null;
    const rest = message[at + key.len ..];
    var end: usize = 0;
    while (end < rest.len and !std.ascii.isWhitespace(rest[end])) : (end += 1) {}
    if (end == 0) return null;
    return rest[0..end];
}

fn parseLifecycleOperation(message: []const u8) sync_object_registry.LifecycleOperation {
    const token = lifecycleTokenAfter(message, "operation=") orelse return .unknown;
    if (std.mem.eql(u8, token, "create")) return .create;
    if (std.mem.eql(u8, token, "initialize")) return .initialize;
    if (std.mem.eql(u8, token, "bind_handle")) return .bind_handle;
    if (std.mem.eql(u8, token, "reference")) return .reference;
    if (std.mem.eql(u8, token, "wait_begin")) return .wait_begin;
    if (std.mem.eql(u8, token, "wait_return")) return .wait_return;
    if (std.mem.eql(u8, token, "set") or
        std.mem.eql(u8, token, "pulse") or
        std.mem.eql(u8, token, "release") or
        std.mem.eql(u8, token, "signal"))
    {
        return .signal;
    }
    if (std.mem.eql(u8, token, "reset")) return .reset;
    return .unknown;
}

fn parseLifecycleKind(message: []const u8) sync_object_registry.ObjectKind {
    const token = lifecycleTokenAfter(message, "kind=") orelse
        lifecycleTokenAfter(message, "type=") orelse return .unknown;
    const event_mode = lifecycleTokenAfter(message, "event_mode=") orelse "";
    if (std.mem.eql(u8, token, "manual_reset_event") or
        std.mem.eql(u8, token, "manual-reset-event") or
        std.mem.eql(u8, event_mode, "manual_reset") or
        std.mem.eql(u8, event_mode, "manual-reset"))
    {
        return .manual_reset_event;
    }
    if (std.mem.eql(u8, token, "auto_reset_event") or
        std.mem.eql(u8, token, "auto-reset-event") or
        std.mem.eql(u8, event_mode, "auto_reset") or
        std.mem.eql(u8, event_mode, "auto-reset"))
    {
        return .auto_reset_event;
    }
    if (std.mem.eql(u8, token, "semaphore") or std.mem.eql(u8, token, "Semaphore")) return .semaphore;
    if (std.mem.eql(u8, token, "event") or std.mem.eql(u8, token, "Event")) return .unknown;
    if (std.mem.eql(u8, token, "mutant") or std.mem.eql(u8, token, "Mutant")) return .mutant;
    if (std.mem.eql(u8, token, "timer") or std.mem.eql(u8, token, "Timer")) return .timer;
    if (std.mem.eql(u8, token, "thread") or std.mem.eql(u8, token, "Thread")) return .thread;
    if (std.mem.eql(u8, token, "io_completion") or std.mem.eql(u8, token, "IOCompletion")) return .io_completion;
    return .unknown;
}

fn lifecycleResultSucceeded(message: []const u8) bool {
    const token = lifecycleTokenAfter(message, "result=") orelse return false;
    return std.mem.eql(u8, token, "STATUS_SUCCESS") or
        std.mem.eql(u8, token, "X_STATUS_SUCCESS") or
        std.mem.eql(u8, token, "success") or
        std.mem.eql(u8, token, "SUCCESS") or
        std.mem.eql(u8, token, "0");
}

fn lifecycleLocation(message: []const u8) sync_object_registry.CodeLocation {
    const valid = parseFlagAfter(message, "guest_pc_valid=") orelse false;
    const guest_pc = if (valid) parseHex64After(message, "guest_pc=") orelse 0 else 0;
    const guest_lr = parseHex64After(message, "lr=") orelse 0;
    const quality: sync_object_registry.CodeLocation.Quality = if (!valid or guest_pc == 0)
        .unavailable
    else if (std.mem.indexOf(u8, message, "guest_pc_quality=direct") != null)
        .direct
    else if (std.mem.indexOf(u8, message, "guest_pc_quality=tracked") != null)
        .tracked
    else if (std.mem.indexOf(u8, message, "guest_pc_quality=seeded") != null)
        .seeded
    else
        .unavailable;
    return .{
        .guest_pc = @truncate(guest_pc),
        .guest_lr = @truncate(guest_lr),
        .provenance = @intFromEnum(sync_object_registry.CodeLocation.Provenance.guest_instruction),
        .quality = @intFromEnum(quality),
    };
}

/// Retain the emulator's object lifecycle under the same identity used by the
/// wait graph. The lifecycle stream is deliberately a second authority: it
/// says what Xenia called and where, but it does not turn a successful return
/// into a proven signal handoff or assign a GPU role by address alone.
fn observeSyncLifecycle(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "audit_sync")) return;
    if (std.mem.indexOf(u8, message, "RING BUFFER: GPU SYNC LIFECYCLE ") == null and
        std.mem.indexOf(u8, message, "RING BUFFER: GPU SYNC HANDLE ") == null)
    {
        return;
    }

    const raw_object = parseHex64After(message, "object=") orelse 0;
    const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse
        parseHexAfter(message, "handle=") orelse 0;
    if (raw_object == 0 and handle == 0) return;

    if (comptime @hasField(State, "sync_object_identity")) {
        if (handle != 0) self.sync_object_identity.observeHandleObject(handle, 0, raw_object);
    }
    const object = if (handle != 0)
        canonicalSyncObjectWithHandle(self, raw_object, handle)
    else
        canonicalSyncObject(self, raw_object);
    const kind = parseLifecycleKind(message);
    var identity = sync_object_registry.ObjectIdentity{
        .address = .{ .guest_virtual = @truncate(object) },
        .handle = handle,
        .generation = 1,
        .kind = @intFromEnum(kind),
    };
    if (object == 0) identity.address = .{};
    const operation = if (std.mem.indexOf(u8, message, "GPU SYNC HANDLE ") != null)
        .bind_handle
    else
        parseLifecycleOperation(message);
    const entry = self.audit_sync.observeLifecycle(
        identity,
        operation,
        parseDecimalAfter(message, "thread_id=") orelse 0,
        lifecycleLocation(message),
        self.executed_steps,
        lifecycleResultSucceeded(message),
        parseFlagAfter(message, "state_after_valid=") orelse false,
        parseHexAfter(message, "state_after=") orelse 0,
    ) orelse return;
    if (kind != .unknown and entry.identity.kindOf() == .unknown) {
        entry.identity.kind = @intFromEnum(kind);
    }
}

pub fn observeGuestSyncObjects(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "deadlock_predictor") and
        !@hasField(State, "audit_sync")) return;

    observeSyncLifecycle(self, message);
    if (comptime !@hasField(State, "deadlock_predictor")) return;

    // Fed here rather than only at checkpoint time: the base is what validates
    // every stated pair, and a pair accepted before it is known was accepted on
    // the word of a line that may have been spliced.
    if (comptime @hasField(State, "sync_object_identity")) {
        if (self.xenia_memory_views.ready()) {
            self.sync_object_identity.observeMappingBase(self.xenia_memory_views.mapping_base);
        }
        // `StashHandle: header=0x38d854bf4, handle=F8000154` is an untruncated
        // 64-bit address next to the handle the title itself uses. It survives
        // splicing that the eight-digit fields do not, so it is the most
        // trustworthy identity channel in the log.
        if (std.mem.indexOf(u8, message, "StashHandle: header=")) |_| {
            const header = parseHex64After(message, "StashHandle: header=") orelse 0;
            const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
            self.sync_object_identity.observeHandleHeader(header, handle);
        }
    }
    if (std.mem.indexOf(u8, message, "xeKeSetEvent:") != null) {
        const raw = parseHexAfter(message, "ptr=") orelse return;
        const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
        if (comptime @hasField(State, "sync_object_identity")) {
            if (handle != 0) self.sync_object_identity.observeHandleObject(handle, 0, raw);
        }
        const object = canonicalSyncObjectWithHandle(self, raw, handle);
        self.deadlock_predictor.observeNotify(
            object,
            deadlock_predictor.ObjectKind.event,
            self.active_guest_thread,
            self.executed_steps,
        );
        return;
    }
    if (std.mem.indexOf(u8, message, "KeReleaseSemaphore(") != null) {
        const raw = parseHexAfter(message, "KeReleaseSemaphore(") orelse return;
        const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
        if (comptime @hasField(State, "sync_object_identity")) {
            if (handle != 0) self.sync_object_identity.observeHandleObject(handle, 0, raw);
        }
        const object = canonicalSyncObjectWithHandle(self, raw, handle);
        self.deadlock_predictor.observeNotify(
            object,
            deadlock_predictor.ObjectKind.semaphore,
            self.active_guest_thread,
            self.executed_steps,
        );
        return;
    }
    if (std.mem.indexOf(u8, message, "NtCreateSemaphore(") != null) {
        const object = canonicalSyncObject(self, parseHexAfter(message, "NtCreateSemaphore(") orelse return);
        self.deadlock_predictor.observeObject(object, deadlock_predictor.ObjectKind.semaphore);
    }
}

/// Join the emulator's import-binding evidence into the binding ledger.
///
/// There are two emitters for this evidence. The older callback-missing probe
/// is emitted after the emulator suspects a callback is absent. The newer
/// thunk-readiness line is emitted during bootstrap and is the stronger
/// observation: it reports the import slot and the first two words of the
/// resolved thunk before the title attempts to use the export. Both describe
/// the binding, not the success of the call, and neither is allowed to imply a
/// successful GPU bootstrap.
pub fn observeImportBindingProbe(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_import_binding")) return;
    const callback_probe = std.mem.indexOf(u8, message, "callback-missing import probe") != null;
    const thunk_readiness = std.mem.indexOf(u8, message, "thunk readiness") != null;
    if (!callback_probe and !thunk_readiness) return;

    const ordinal = parseHexAfter(message, "ordinal=") orelse return;
    if (ordinal > std.math.maxInt(u16)) return;

    // Do not turn a missing field into a negative claim. The two formats use
    // different names for the slot's committed/imported bit, but all of the
    // other fields are deliberately shared. A malformed breadcrumb therefore
    // remains unobserved instead of downgrading a binding by guesswork.
    const slot_committed = if (thunk_readiness)
        parseFlagAfter(message, "imported=") orelse return
    else
        parseFlagAfter(message, "value_committed=") orelse return;
    const slot_translated = parseFlagAfter(message, "value_translated=") orelse return;
    const thunk_translated = parseFlagAfter(message, "thunk_translated=") orelse return;
    const slot_word = parseHexAfter(message, "value_word=") orelse return;
    const slot_address = parseHexAfter(message, "value_addr=") orelse return;
    const thunk_address = parseHexAfter(message, "thunk_addr=") orelse return;
    const word0 = parseHexAfter(message, "thunk_w0=") orelse return;
    const word1 = parseHexAfter(message, "thunk_w1=") orelse return;

    self.gpu_import_binding.observe(
        @intCast(ordinal),
        slot_committed,
        slot_translated,
        slot_word,
        slot_address,
        thunk_translated,
        thunk_address,
        word0,
        word1,
    );
}

test "thunk readiness is a first-class import binding probe" {
    const State = struct {
        gpu_import_binding: gpu.ImportBindingLedger = .{},
    };
    var state = State{};
    observeImportBindingProbe(
        &state,
        "RING BUFFER: thunk readiness ordinal=0x1C2 name=VdInitializeEngines " ++
            "imported=YES value_addr=82000700 value_word=8270E044 " ++
            "value_translated=YES value_fn_behavior=Extern value_fn_status=2 " ++
            "thunk_addr=8270E044 thunk_w0=44000042 thunk_w1=4E800020 " ++
            "thunk_translated=YES thunk_sc2_stub=YES thunk_fn_behavior=Extern " ++
            "thunk_fn_status=2",
    );

    try std.testing.expectEqual(@as(usize, 1), state.gpu_import_binding.count);
    try std.testing.expectEqual(@as(u64, 1), state.gpu_import_binding.total_probes);
    try std.testing.expectEqual(gpu.import_binding.Binding.bound, state.gpu_import_binding.entries[0].binding);
    try std.testing.expectEqual(@as(u16, 0x1C2), state.gpu_import_binding.entries[0].ordinal);
    try std.testing.expectEqual(@as(u32, 0x82000700), state.gpu_import_binding.entries[0].slot_address);
    try std.testing.expectEqual(@as(u32, 0x8270E044), state.gpu_import_binding.entries[0].thunk_address);
}

test "legacy callback-missing probe remains a first-class import binding probe" {
    const State = struct {
        gpu_import_binding: gpu.ImportBindingLedger = .{},
    };
    var state = State{};
    observeImportBindingProbe(
        &state,
        "RING BUFFER: callback-missing import probe ordinal=0x1D5 " ++
            "name=VdSetGraphicsInterruptCallback value_addr=820006FC " ++
            "value_committed=YES value_translated=YES value_word=8270E034 " ++
            "value_fn_behavior=Extern value_fn_status=2 thunk_addr=8270E034 " ++
            "thunk_committed=YES thunk_translated=YES thunk_w0=44000042 " ++
            "thunk_w1=4E800020 thunk_sc2_stub=YES thunk_fn_behavior=Extern " ++
            "thunk_fn_status=2",
    );

    try std.testing.expectEqual(@as(usize, 1), state.gpu_import_binding.count);
    try std.testing.expectEqual(@as(u64, 1), state.gpu_import_binding.total_probes);
    try std.testing.expectEqual(gpu.import_binding.Binding.bound, state.gpu_import_binding.entries[0].binding);
    try std.testing.expectEqual(@as(u16, 0x1D5), state.gpu_import_binding.entries[0].ordinal);
}

test "malformed import readiness cannot downgrade or certify a binding" {
    const State = struct {
        gpu_import_binding: gpu.ImportBindingLedger = .{},
    };
    var state = State{};
    observeImportBindingProbe(
        &state,
        "RING BUFFER: thunk readiness ordinal=0x1C2 imported=YES " ++
            "value_addr=82000700 value_word=8270E044 value_translated=YES",
    );
    try std.testing.expectEqual(@as(usize, 0), state.gpu_import_binding.count);
    try std.testing.expectEqual(@as(u64, 0), state.gpu_import_binding.total_probes);
}

test "open NtWaitForSingleObjectEx evidence is paired with its completion" {
    const State = struct {
        guest_wait_liveness: guest_wait_liveness.Ledger = .{},
        executed_steps: u64 = 0,
    };
    var state = State{ .executed_steps = 1_200_000_000 };
    observeGuestWaitLiveness(
        &state,
        "RING BUFFER: NtWaitForSingleObjectEx tid=6 main=YES " ++
            "bootstrap_thread=YES handle=F8000014 guest_obj=3002E018 " ++
            "type=12 wait_mode=1 alertable=0 timeout_ms=-1 pc=82582A98 " ++
            "lr=82081740 watch_obj=00000000",
    );
    observeGuestWaitLiveness(
        &state,
        "RING BUFFER: NtWaitForSingleObjectEx wait_obj[0] ptr=3002E018 " ++
            "obj_handle=F8000014 wait_handle_valid=YES wait_handle=F8000014 " ++
            "type=Thread(12) event_state_valid=NO event_type=00000000 " ++
            "event_state=00000000 watch_obj=00000000 watch_match=NO name='<unnamed>'",
    );
    observeGuestWaitLiveness(
        &state,
        "DEBUG: MainThread Wait: obj_type=12 handle=F8000014 thread_id=6 " ++
            "wait_reason=3 alertable=0 timeout_ms=-1",
    );
    try std.testing.expectEqual(@as(usize, 1), state.guest_wait_liveness.open_wait_count);
    try std.testing.expectEqual(@as(u32, 0xF8000014), state.guest_wait_liveness.open_waits[0].handle);
    try std.testing.expectEqual(@as(u32, 6), state.guest_wait_liveness.open_waits[0].thread_id);
    try std.testing.expectEqual(@as(i64, -1), state.guest_wait_liveness.open_waits[0].timeout_ms);
    try std.testing.expect(state.guest_wait_liveness.open_waits[0].handle_valid);
    try std.testing.expectEqual(@as(u32, 3), state.guest_wait_liveness.open_waits[0].wait_reason);

    observeGuestWaitLiveness(
        &state,
        "KeWaitForSingleObject result=00000000 guest_obj=3002E018 " ++
            "handle=F8000014 wait_disposition=blocked",
    );
    try std.testing.expectEqual(@as(usize, 0), state.guest_wait_liveness.open_wait_count);
    try std.testing.expectEqual(@as(u64, 1), state.guest_wait_liveness.wait_entries_completed);
    try std.testing.expectEqual(@as(u64, 1), state.guest_wait_liveness.total_waits);
}

test "finite manual-reset timeout remains a bounded poll in both wait ledgers" {
    const State = struct {
        livelock_predictor: livelock_predictor.Predictor = .{},
        wait_graph: wait_graph.Ledger = .{},
        wait_audit: wait_audit.Ledger = .{},
        gpu_ring_publication: gpu.RingPublication = .{},
        livelock_pending_waits: [pending_wait_capacity]PendingWait =
            [_]PendingWait{.{}} ** pending_wait_capacity,
        livelock_pending_wait_active: u32 = 0,
        livelock_pending_wait_dropped: u64 = 0,
        livelock_pending_wait_unmatched_results: u64 = 0,
        livelock_pending_wait_identity_conflicts: u64 = 0,
        active_guest_thread: u64 = 0x7fff_2140,
        executed_steps: u64 = 0,
        regs: struct { rip: u64 = 0 } = .{},
    };

    var state = State{};
    var index: u64 = 0;
    while (index < 8) : (index += 1) {
        state.executed_steps = 1_000 + index * 100;
        observeLivelockWaits(
            &state,
            "RING BUFFER: KeWaitForSingleObject tid=15 obj_ptr=8F454BF4 " ++
                "guest_obj=40004BF4 type=2 handle=F8000158 timeout_ms=32 " ++
                "event_mode=manual_reset",
        );
        state.executed_steps += 32;
        observeLivelockWaits(
            &state,
            "RING BUFFER: KeWaitForSingleObject result=00000102 wait_id=15 " ++
                "obj_ptr=8F454BF4 guest_obj=40004BF4 handle=F8000158 type=2 " ++
                "event_mode=manual_reset duration_ms=32 wait_disposition=timed_out",
        );
    }

    const subject = state.wait_audit.subjects[0];
    try std.testing.expectEqual(wait_policy.TimeoutClass.bounded_poll, subject.timeout_class);
    try std.testing.expectEqual(@as(i64, 32), subject.timeout_ms);
    try std.testing.expectEqual(
        wait_audit.Classification.bounded_timeout,
        state.wait_audit.classify(subject, state.executed_steps),
    );
    try std.testing.expectEqual(@as(u32, 0), state.wait_audit.problemCount(state.executed_steps));

    const record = state.wait_graph.record(0x40004BF4).?;
    try std.testing.expectEqual(wait_policy.ObjectKind.guest_manual_reset_event, record.object_kind);
    try std.testing.expectEqual(wait_policy.TimeoutClass.bounded_poll, record.timeout_class);
    const decision = record.policyDecision();
    try std.testing.expectEqual(wait_policy.Action.await_deadline, decision.action);
    try std.testing.expectEqual(wait_policy.Severity.caution, decision.severity);
    try std.testing.expect(decision.may_resume);
    try std.testing.expect(!decision.requires_fault);
}

test "self-contained wait result prefers requested deadline over elapsed duration" {
    const State = struct {
        livelock_predictor: livelock_predictor.Predictor = .{},
        wait_graph: wait_graph.Ledger = .{},
        wait_audit: wait_audit.Ledger = .{},
        gpu_ring_publication: gpu.RingPublication = .{},
        livelock_pending_waits: [pending_wait_capacity]PendingWait =
            [_]PendingWait{.{}} ** pending_wait_capacity,
        livelock_pending_wait_active: u32 = 0,
        livelock_pending_wait_dropped: u64 = 0,
        livelock_pending_wait_unmatched_results: u64 = 0,
        livelock_pending_wait_identity_conflicts: u64 = 0,
        active_guest_thread: u64 = 0x7fff_2140,
        executed_steps: u64 = 0,
        regs: struct { rip: u64 = 0 } = .{},
    };

    var state = State{};
    var index: u64 = 0;
    while (index < 8) : (index += 1) {
        state.executed_steps = 2_000 + index * 100;
        observeLivelockWaits(
            &state,
            "RING BUFFER: KeWaitForSingleObject result=00000102 wait_id=15 " ++
                "obj_ptr=8F454BF4 guest_obj=40004BF4 handle=F8000158 type=2 " ++
                "event_mode=manual_reset requested_timeout_present=YES " ++
                "requested_timeout_ticks=0000000000000020 requested_timeout_ms=32 " ++
                "requested_timeout_kind=positive_milliseconds duration_ms=333 " ++
                "wait_disposition=timed_out",
        );
    }

    const subject = state.wait_audit.subjects[0];
    try std.testing.expectEqual(wait_policy.TimeoutClass.bounded_poll, subject.timeout_class);
    try std.testing.expectEqual(@as(i64, 32), subject.timeout_ms);
    try std.testing.expect(subject.timeout_requested_known);
    try std.testing.expect(subject.timeout_requested);
    try std.testing.expectEqual(wait_audit.Classification.bounded_timeout, state.wait_audit.classify(subject, state.executed_steps));

    const record = state.wait_graph.record(0x40004BF4).?;
    try std.testing.expectEqual(wait_policy.TimeoutClass.bounded_poll, record.timeout_class);
    try std.testing.expect(record.timeout_requested_known);
    try std.testing.expect(record.timeout_requested);
}

test "NtWaitForSingleObjectEx result keeps identity and timing evidence" {
    const State = struct {
        guest_wait_liveness: guest_wait_liveness.Ledger = .{},
        executed_steps: u64 = 0,
    };
    var state = State{ .executed_steps = 100 };
    observeGuestWaitLiveness(
        &state,
        "RING BUFFER: NtWaitForSingleObjectEx tid=24 main=NO " ++
            "bootstrap_thread=YES handle=F800015C guest_obj=827CEC14 " ++
            "type=8 wait_mode=0 alertable=0 timeout_ms=-1 pc=001BE680 " ++
            "guest_pc=82582A98 pc_domain=xenia_guest_ppc guest_pc_valid=YES " ++
            "guest_pc_quality=tracked guest_pc_source=jit_source_offset " ++
            "lr=001BE890 watch_obj=00000000",
    );
    observeGuestWaitLiveness(
        &state,
        "RING BUFFER: NtWaitForSingleObjectEx result=00000000 wait_id=1 " ++
            "handle=F800015C guest_obj=827CEC14 type=8 duration_ms=8 " ++
            "wait_disposition=blocked synthetic_recovery_enabled=NO " ++
            "pc=001BE680 pc_entry=001BE680 pc_return=001BE680 " ++
            "guest_pc=82582A98 pc_domain=xenia_guest_ppc " ++
            "guest_pc_valid=YES guest_pc_quality=tracked " ++
            "guest_pc_source=jit_source_offset guest_pc_entry=82582A98 " ++
            "guest_pc_return=82582A98 guest_pc_changed=NO " ++
            "lr_entry=001BE890 lr_return=001BE890",
    );
    try std.testing.expectEqual(@as(usize, 0), state.guest_wait_liveness.open_wait_count);
    try std.testing.expectEqual(@as(u64, 1), state.guest_wait_liveness.wait_entries_completed);
    try std.testing.expectEqual(@as(u64, 1), state.guest_wait_liveness.total_waits);
    try std.testing.expectEqual(@as(u32, 0xF800015C), state.guest_wait_liveness.objects[0].handle);
    try std.testing.expectEqual(@as(u64, 1), state.guest_wait_liveness.objects[0].signalled);
    try std.testing.expectEqual(@as(u64, 1), state.guest_wait_liveness.objects[0].blocked_signalled);
}

test "interleaved wait breadcrumbs stay with their guest thread" {
    const State = struct {
        livelock_predictor: livelock_predictor.Predictor = .{},
        wait_graph: wait_graph.Ledger = .{},
        gpu_ring_publication: gpu.RingPublication = .{},
        livelock_pending_waits: [pending_wait_capacity]PendingWait =
            [_]PendingWait{.{}} ** pending_wait_capacity,
        livelock_pending_wait_active: u32 = 0,
        livelock_pending_wait_dropped: u64 = 0,
        livelock_pending_wait_unmatched_results: u64 = 0,
        livelock_pending_wait_identity_conflicts: u64 = 0,
        active_guest_thread: u64 = 0,
        executed_steps: u64 = 0,
        regs: struct { rip: u64 = 0 } = .{},
    };

    var state = State{};
    state.active_guest_thread = 0xAAAA;
    state.executed_steps = 1;
    observeLivelockWaits(
        &state,
        "KeWaitForSingleObject tid=6 guest_obj=00001000 obj_ptr=00002000",
    );
    state.active_guest_thread = 0xBBBB;
    state.executed_steps = 2;
    observeLivelockWaits(
        &state,
        "KeWaitForSingleObject tid=7 guest_obj=00003000 obj_ptr=00004000",
    );

    // These legacy result lines intentionally omit object identity. Each must
    // consume only the breadcrumb from the thread that produced it.
    state.active_guest_thread = 0xAAAA;
    state.executed_steps = 3;
    observeLivelockWaits(&state, "KeWaitForSingleObject result=00000000 wait_disposition=blocked");
    state.active_guest_thread = 0xBBBB;
    state.executed_steps = 4;
    observeLivelockWaits(&state, "KeWaitForSingleObject result=00000000 wait_disposition=blocked");

    try std.testing.expectEqual(@as(u32, 0), state.livelock_pending_wait_active);
    try std.testing.expectEqual(@as(u64, 0), state.livelock_pending_wait_unmatched_results);
    try std.testing.expectEqual(@as(u64, 0), state.livelock_pending_wait_identity_conflicts);
    try std.testing.expectEqual(@as(u64, 1), state.wait_graph.record(0x1000).?.waits);
    try std.testing.expectEqual(@as(u64, 1), state.wait_graph.record(0x3000).?.waits);
    try std.testing.expect(state.wait_graph.record(0x2000) == null);
    try std.testing.expect(state.wait_graph.record(0x4000) == null);
}

test "wait identity keeps a guest semaphore out of the host low-word alias" {
    const State = struct {
        livelock_predictor: livelock_predictor.Predictor = .{},
        wait_graph: wait_graph.Ledger = .{},
        sync_object_identity: sync_object_identity.Table = .{},
        gpu_ring_publication: gpu.RingPublication = .{},
        livelock_pending_waits: [pending_wait_capacity]PendingWait =
            [_]PendingWait{.{}} ** pending_wait_capacity,
        livelock_pending_wait_active: u32 = 0,
        livelock_pending_wait_dropped: u64 = 0,
        livelock_pending_wait_unmatched_results: u64 = 0,
        livelock_pending_wait_identity_conflicts: u64 = 0,
        active_guest_thread: u64 = 0,
        executed_steps: u64 = 0,
        regs: struct { rip: u64 = 0 } = .{},
    };

    var state = State{};
    state.sync_object_identity.observeMappingBase(0x358000000);
    state.active_guest_thread = 0x7FFF2170;
    state.executed_steps = 4_147_000_000;
    observeLivelockWaits(&state, "KeReleaseSemaphore(827CEC14, 00000001, 00000001, 00000000)");

    state.executed_steps += 1;
    observeLivelockWaits(
        &state,
        "RING BUFFER: KeWaitForSingleObject tid=15 obj_ptr=DA7CEC14 " ++
            "guest_obj=827CEC14 type=8 handle=F800015C",
    );
    state.executed_steps += 1;
    observeLivelockWaits(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000000 wait_id=1 " ++
            "obj_ptr=DA7CEC14 guest_obj=827CEC14 handle=F800015C " ++
            "type=8 wait_disposition=blocked",
    );

    try std.testing.expectEqual(@as(u64, 1), state.wait_graph.record(0x827CEC14).?.waits);
    try std.testing.expectEqual(@as(u64, 1), state.wait_graph.record(0x827CEC14).?.signals);
    try std.testing.expect(state.wait_graph.record(0x2A7CEC14) == null);
    try std.testing.expectEqual(@as(usize, 1), state.sync_object_identity.count);
    try std.testing.expectEqual(@as(usize, 1), state.sync_object_identity.handle_count);
    try std.testing.expectEqual(@as(?u64, 0x827CEC14), state.sync_object_identity.consoleForHandle(0xF800015C));
}

test "duration-derived semaphore waits do not become orphan waits" {
    const State = struct {
        livelock_predictor: livelock_predictor.Predictor = .{},
        wait_graph: wait_graph.Ledger = .{},
        gpu_ring_publication: gpu.RingPublication = .{},
        livelock_pending_waits: [pending_wait_capacity]PendingWait =
            [_]PendingWait{.{}} ** pending_wait_capacity,
        livelock_pending_wait_active: u32 = 0,
        livelock_pending_wait_dropped: u64 = 0,
        livelock_pending_wait_unmatched_results: u64 = 0,
        livelock_pending_wait_identity_conflicts: u64 = 0,
        active_guest_thread: u64 = 0x7FFF2170,
        executed_steps: u64 = 0,
        regs: struct { rip: u64 = 0x2EF558 } = .{},
    };

    var state = State{};
    var attempt: u64 = 0;
    while (attempt < 25) : (attempt += 1) {
        state.executed_steps = attempt + 1;
        observeLivelockWaits(
            &state,
            "RING BUFFER: NtWaitForSingleObjectEx result=00000000 " ++
                "obj_ptr=DA040018 guest_obj=30040018 handle=F8000040 " ++
                "type=8 duration_ms=1 wait_disposition=blocked",
        );
    }

    const record = state.wait_graph.record(0x30040018).?;
    try std.testing.expectEqual(@as(u64, 25), record.waits);
    try std.testing.expectEqual(@as(u64, 25), record.completed_successes);
    try std.testing.expectEqual(@as(u64, 25), record.unknown_timing);
    try std.testing.expectEqual(@as(u64, 0), record.blocked_successes);
    try std.testing.expectEqual(wait_policy.ObjectKind.guest_semaphore, record.object_kind);
    try std.testing.expectEqual(wait_graph.PairState.insufficient_sample, record.state());
    try std.testing.expectEqual(@as(usize, 0), state.wait_graph.summary().orphan_waits);
    try std.testing.expect(state.wait_graph.blocking() == null);
    try std.testing.expectEqual(
        wait_policy.Classification.insufficient_evidence,
        record.policyDecision().classification,
    );
}

test "zero entry state proves a successful event wait actually blocked" {
    try std.testing.expect(!waitResultProvesBlocked(
        "type=8 duration_ms=1 wait_disposition=blocked",
    ));
    try std.testing.expect(!waitResultProvesBlocked(
        "type=8 entry_state_valid=NO entry_state=00000000 wait_disposition=blocked",
    ));
    try std.testing.expect(waitResultProvesBlocked(
        "type=2 entry_state_valid=YES entry_state=00000000 wait_disposition=blocked",
    ));
    try std.testing.expect(waitResultProvesBlocked(
        "type=8 blocked_witness=YES wait_disposition=blocked",
    ));
}

test "wait evidence rejects seeded and cross-domain continuations" {
    const State = struct {
        livelock_predictor: livelock_predictor.Predictor = .{},
        wait_graph: wait_graph.Ledger = .{},
        gpu_ring_publication: gpu.RingPublication = .{},
        livelock_pending_waits: [pending_wait_capacity]PendingWait =
            [_]PendingWait{.{}} ** pending_wait_capacity,
        livelock_pending_wait_active: u32 = 0,
        livelock_pending_wait_dropped: u64 = 0,
        livelock_pending_wait_unmatched_results: u64 = 0,
        livelock_pending_wait_identity_conflicts: u64 = 0,
        active_guest_thread: u64 = 0,
        executed_steps: u64 = 0,
        regs: struct { rip: u64 = 0 } = .{},
    };

    var state = State{};
    state.active_guest_thread = 0x24;
    state.executed_steps = 10;
    observeLivelockWaits(
        &state,
        "RING BUFFER: KeWaitForSingleObject tid=24 main=NO " ++
            "obj_ptr=DA7CEC14 guest_obj=827CEC14 type=8 handle=F800015C " ++
            "wait_reason=0 timeout_ms=-1 pc=001BE680 guest_pc=001BE680 " ++
            "pc_domain=xenia_guest_ppc guest_pc_valid=NO " ++
            "guest_pc_quality=seeded guest_pc_source=processor_entry_seed_or_stale",
    );
    state.executed_steps = 11;
    observeLivelockWaits(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000000 wait_id=1 " ++
            "obj_ptr=DA7CEC14 guest_obj=827CEC14 handle=F800015C type=8 " ++
            "event_mode=unknown entry_state_valid=NO entry_state=00000000 " ++
            "duration_ms=7 wait_disposition=blocked pc=001BE680 " ++
            "pc_entry=001BE680 pc_return=001BE680 guest_pc=001BE680 " ++
            "pc_domain=xenia_guest_ppc guest_pc_valid=NO " ++
            "guest_pc_quality=seeded guest_pc_source=processor_entry_seed_or_stale",
    );

    // The next breadcrumb is Rosette's translated x86 RIP. It is direct host
    // evidence, but it cannot be compared to a PPC guest PC as a continuation.
    state.regs.rip = 0x2ef558;
    state.executed_steps = 12;
    observeLivelockWaits(&state, "translated host activity after wait");
    const seeded_continuation = state.wait_graph.continuationFor(0x827CEC14, 0x24).?;
    try std.testing.expectEqual(wait_graph.ContinuationState.observed_untrusted_pc, seeded_continuation.state);

    // A second wait with tracked PPC evidence followed by a direct Rosette
    // breadcrumb must be called incomparable, never a guest transition.
    state.executed_steps = 20;
    observeLivelockWaits(
        &state,
        "RING BUFFER: KeWaitForSingleObject tid=24 main=NO " ++
            "obj_ptr=DA7CEC14 guest_obj=827CEC14 type=8 handle=F800015C " ++
            "wait_reason=0 timeout_ms=-1 pc=001BE680 guest_pc=82582A98 " ++
            "pc_domain=xenia_guest_ppc guest_pc_valid=YES " ++
            "guest_pc_quality=tracked guest_pc_source=jit_source_offset",
    );
    state.executed_steps = 21;
    observeLivelockWaits(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000000 wait_id=2 " ++
            "obj_ptr=DA7CEC14 guest_obj=827CEC14 handle=F800015C type=8 " ++
            "event_mode=unknown entry_state_valid=NO entry_state=00000000 " ++
            "duration_ms=7 wait_disposition=blocked pc=001BE680 " ++
            "pc_entry=001BE680 pc_return=001BE680 guest_pc=82582A98 " ++
            "pc_domain=xenia_guest_ppc guest_pc_valid=YES " ++
            "guest_pc_quality=tracked guest_pc_source=jit_source_offset",
    );
    state.regs.rip = 0x2ef558;
    state.executed_steps = 22;
    observeLivelockWaits(&state, "translated host continuation");
    const incomparable_continuation = state.wait_graph.continuationFor(0x827CEC14, 0x24).?;
    try std.testing.expectEqual(wait_graph.ContinuationState.incomparable_pc, incomparable_continuation.state);
    const summary = state.wait_graph.continuationSummary(state.executed_steps);
    try std.testing.expectEqual(@as(u64, 1), summary.observed_untrusted_pc);
    try std.testing.expectEqual(@as(u64, 1), summary.incomparable_pc);
    try std.testing.expectEqual(@as(u64, 0), summary.transitions);
}

/// Join the emulator's wait and set logging into the wait-liveness ledger.
///
/// A result code is outcome evidence, not timing evidence. New Xenia records
/// carry identity, event mode, entry state, duration and `wait_disposition` on
/// the same line. Legacy result-only lines remain unknown rather than being
/// mislabelled as immediate returns.
pub fn observeGuestWaitLiveness(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_wait_liveness")) return;
    if (std.mem.indexOf(u8, message, "RING BUFFER: NtWaitForSingleObjectEx wait_obj[") != null) {
        const handle = parseFixedWidthHexAfter(message, "obj_handle=", sync_object_field_width) orelse
            parseFixedWidthHexAfter(message, "wait_handle=", sync_object_field_width) orelse 0;
        const guest_object = parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width) orelse 0;
        self.guest_wait_liveness.observeWaitDetail(
            handle,
            guest_object,
            parseFlagAfter(message, "wait_handle_valid=") orelse false,
        );
        return;
    }
    if (std.mem.indexOf(u8, message, "RING BUFFER: NtWaitForSingleObjectEx tid=") != null) {
        const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse return;
        const pc = xeniaReportedPcEvidence(message);
        self.guest_wait_liveness.observeWaitEntry(.{
            .handle = handle,
            .guest_object = parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width) orelse 0,
            .object_type = @truncate(parseDecimalAfter(message, "type=") orelse 0),
            .wait_mode = @truncate(parseDecimalAfter(message, "wait_mode=") orelse 0),
            .alertable = (parseDecimalAfter(message, "alertable=") orelse 0) != 0,
            .timeout_ms = parseSignedDecimalAfter(message, "timeout_ms=") orelse 0,
            .thread_id = @truncate(parseDecimalAfter(message, "tid=") orelse 0),
            .pc = pc.address,
            .pc_domain = pc.domain,
            .pc_quality = pc.quality,
            .lr = parseHex64After(message, "lr=") orelse 0,
            .main_thread = parseFlagAfter(message, "main=") orelse false,
            .bootstrap_thread = parseFlagAfter(message, "bootstrap_thread=") orelse false,
            .handle_valid = parseFlagAfter(message, "wait_handle_valid=") orelse false,
            .entered_step = self.executed_steps,
        });
        return;
    }
    if (std.mem.indexOf(u8, message, "DEBUG: MainThread Wait:") != null) {
        const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse return;
        self.guest_wait_liveness.observeWaitContext(
            handle,
            @truncate(parseDecimalAfter(message, "wait_reason=") orelse 0),
        );
        return;
    }
    if (std.mem.indexOf(u8, message, "KeWaitForSingleObject result=") != null or
        std.mem.indexOf(u8, message, "NtWaitForSingleObjectEx result=") != null)
    {
        const code = if (std.mem.indexOf(u8, message, "KeWaitForSingleObject result=") != null)
            (parseHexAfter(message, "KeWaitForSingleObject result=") orelse return)
        else
            (parseHexAfter(message, "NtWaitForSingleObjectEx result=") orelse return);
        // The liveness ledger is keyed by the kernel handle. `guest_obj` is a
        // second identity used by the wait graph, not a replacement for that
        // handle. Prefer the explicit handle whenever the result line carries
        // both fields; otherwise a legacy line can still close by guest object.
        const result_handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width);
        const guest_object = parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width);
        const handle = result_handle orelse guest_object orelse 0;
        const completion_handle = result_handle orelse guest_object orelse 0;
        self.guest_wait_liveness.observeWaitCompletionForThread(completion_handle, @truncate(parseDecimalAfter(message, "tid=") orelse 0));
        const timing: guest_wait_liveness.TimingEvidence = if (std.mem.indexOf(u8, message, "wait_disposition=ready_on_entry") != null)
            .ready_on_entry
        else if (std.mem.indexOf(u8, message, "wait_disposition=blocked") != null or
            std.mem.indexOf(u8, message, "wait_disposition=timed_out") != null)
            .blocked
        else
            .unknown;
        const event_mode: guest_wait_liveness.EventMode = if (std.mem.indexOf(u8, message, "event_mode=manual_reset") != null)
            .manual_reset
        else if (std.mem.indexOf(u8, message, "event_mode=auto_reset") != null)
            .auto_reset
        else
            .unknown;
        const status = guest_wait_liveness.WaitStatus.fromCode(@truncate(code));
        const timeout = timeoutEvidenceFromMessage(
            message,
            .{},
            status == .timed_out,
        );
        self.guest_wait_liveness.observeWait(.{
            .handle = handle,
            .status = status,
            .timing = timing,
            .event_mode = event_mode,
            .timeout = timeout,
        });
        return;
    }
    if (std.mem.indexOf(u8, message, "xeKeSetEvent:") != null) {
        const handle = parseHexAfter(message, "handle=") orelse return;
        const already = std.mem.indexOf(u8, message, "was_signalled=1") != null;
        self.guest_wait_liveness.observeSet(@truncate(handle), already);
    }
}

/// Decode the PC that Xenia reports beside a wait entry. Older Xenia builds
/// print only `pc=` even when `track_guest_pc` is disabled; retain that value as
/// a seeded breadcrumb, never as tracked guest control-flow evidence. Newer
/// records can make the distinction explicit with `guest_pc_valid` and
/// `guest_pc_quality`.
fn xeniaReportedPcEvidence(message: []const u8) wait_graph.PcEvidence {
    const explicit_guest_pc = std.mem.indexOf(u8, message, "guest_pc_valid=") != null or
        std.mem.indexOf(u8, message, "pc_domain=xenia_guest_ppc") != null;
    const valid = parseFlagAfter(message, "guest_pc_valid=") orelse !explicit_guest_pc;
    const address = if (valid)
        (parseHex64After(message, "guest_pc=") orelse parseHex64After(message, "pc=") orelse 0)
    else
        0;
    const quality: wait_graph.PcQuality = if (!valid or address == 0)
        .unavailable
    else if (std.mem.indexOf(u8, message, "guest_pc_quality=tracked") != null)
        .tracked
    else if (std.mem.indexOf(u8, message, "guest_pc_quality=direct") != null)
        .direct
    else if (std.mem.indexOf(u8, message, "guest_pc_quality=seeded") != null)
        .seeded
    else
        .seeded;
    return .{
        .address = address,
        .domain = .xenia_guest_ppc,
        .quality = quality,
    };
}

/// Capture `   V 820006B8          1BE ( 446)    VdGlobalDevice` from the
/// emulator's export table dump: the only place the guest address of a
/// variable export is stated.
///
/// The dump arrives as **one** log message several hundred lines long — the
/// emulator builds the whole table into a single string and logs it once. A
/// parser that tokenised the message got `Module` (the header's first word) and
/// gave up, so every variable export stayed at address zero and the kernel
/// surface reported `VdGlobalDevice UNPOPULATED` for a variable it had simply
/// never looked at. That reads as a missing kernel write and sends the next
/// hour into supplying one.
///
/// So the message is split first and each line examined. Cheap, because the
/// leading-character test rejects a line in one comparison.
/// Read the emulator's own opcode census.
///
/// Rosette walks the ring too, but its stateful executor only runs against
/// retained scans and on the 2026-08-31 run it was unarmed — `packets
/// (observed/executed)=0/0`. The command processor's own type-3 dispatch is the
/// only place that sees every packet the title encoded, so the count that
/// answers "did the title ever ask for a completion" has to come from there.
///
/// The two are kept as separate inputs to the same ledger on purpose. Rosette's
/// walk can see packets the emulator skipped for predication; the emulator's
/// census can see packets Rosette never scanned. Where they disagree, that is
/// itself worth knowing.
fn observeEmulatorPacketCensus(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_packet_census")) return;
    // The emulator commits a memory completion and says so. Rosette was not
    // reading that line, so a title that asked for two event writes and got
    // both of them read as `MEMORY_COMPLETION_REQUESTED_NOT_DELIVERED` — a
    // false accusation produced by the observer that exists to prevent exactly
    // that. The commit line carries `alias_match`, which is the part that
    // matters: a value written to one alias and not visible through the other
    // is delivered to the emulator and not to the guest.
    if (std.mem.indexOf(u8, message, "GPU COMPLETION: EVENT_WRITE") != null) {
        if (std.mem.indexOf(u8, message, "committed") == null) return;
        self.gpu_packet_census.observeMemoryCompletionDelivered();
        if (std.mem.indexOf(u8, message, "alias_match=NO") != null) {
            self.gpu_packet_census.observeMemoryCompletionAliasMismatch();
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "ROSETTE INTERRUPT DISPATCH:") != null) {
        const id = parseDecimalAfter(message, "id=") orelse return;
        if (std.mem.indexOf(u8, message, "enter id=") != null) {
            self.gpu_packet_census.observeInterruptDispatchEntered(id);
            if (comptime @hasField(State, "monotone_witness")) {
                self.monotone_witness.state(.interrupt_executor_entries, .emulator_sampled_total, parseDecimalAfter(message, "entered=") orelse id, self.executed_steps);
            }
        } else if (std.mem.indexOf(u8, message, "leave id=") != null) {
            self.gpu_packet_census.observeInterruptDispatchReturned(
                parseDecimalAfter(message, "returned=") orelse id,
            );
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "ROSETTE VBLANK FLOOR:") != null) {
        // A vblank raised by the wall-clock floor rather than by the guest
        // clock means the guest clock is not pacing the display, and every
        // deadline the title computes from it is stretched by the same factor.
        self.gpu_packet_census.observeVblankFloorRaise();
        return;
    }
    if (std.mem.indexOf(u8, message, "ROSETTE PACKET CENSUS:") == null) return;
    if (comptime @hasField(State, "monotone_witness")) {
        if (parseDecimalAfter(message, "packets=")) |packets| {
            self.monotone_witness.state(.pm4_packets_all_types, .emulator_sampled_total, packets, self.executed_steps);
        }
    }
    const interrupts = parseDecimalAfter(message, "interrupt_packets=") orelse 0;
    const events = parseDecimalAfter(message, "event_write_packets=") orelse 0;
    self.gpu_packet_census.observeEmulatorCounts(
        parseDecimalAfter(message, "packets=") orelse 0,
        interrupts,
        events,
    );
}

/// Record which objects are waited on, which are signalled, and where in the
/// title's own code each waiter is.
///
/// The wait graph already tracks edges and the notifier ledger already reports
/// never-signalled objects. What neither produces is the pair: an object waited
/// on and never signalled *beside* an object signalled and never waited on. Each
/// half on its own reads as somebody being late; together they say two ends of a
/// handshake are not meeting, and that is a different investigation.
///
/// `guest_pc` is captured only when the emulator vouches for it. A seeded or
/// stale program counter names an instruction that is not the one waiting, and
/// reporting it would send a reader to the wrong place in the disassembly with
/// more confidence than an unknown address would have.
fn observeSignalExpectation(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "signal_expectation")) return;
    const ledger = &self.signal_expectation;
    const step = self.executed_steps;

    if (std.mem.indexOf(u8, message, "WaitForSingleObject result=") != null) {
        const object = parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width) orelse
            parseFixedWidthHexAfter(message, "obj_ptr=", sync_object_field_width) orelse return;
        const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
        const timed_out = std.mem.indexOf(u8, message, "wait_disposition=timed_out") != null or
            (parseHexAfter(message, "result=") orelse 0) == 0x102;
        ledger.observeWait(object, handle, activeGuestThread(self), step, timed_out);
        if (parseSignedDecimalAfter(message, "requested_timeout_ms=")) |requested| {
            if (requested > 0) ledger.observeTimeoutRequest(object, @intCast(requested));
        }
        // Only a program counter the emulator marks valid and non-seeded is the
        // instruction that is actually waiting.
        const trusted = std.mem.indexOf(u8, message, "guest_pc_valid=YES") != null and
            std.mem.indexOf(u8, message, "guest_pc_quality=seeded") == null;
        if (parseHex64After(message, "guest_pc=")) |guest_pc| {
            ledger.observeWaitSite(
                object,
                guest_pc,
                parseHex64After(message, "lr_entry=") orelse 0,
                trusted,
            );
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "xeKeSetEvent: ptr=") != null) {
        const object = parseFixedWidthHexAfter(message, "ptr=", sync_object_field_width) orelse return;
        const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
        ledger.observeSignal(object, handle, activeGuestThread(self), guestProgramCounter(self), step);
        return;
    }
    if (std.mem.indexOf(u8, message, "KeReleaseSemaphore(") != null) {
        const at = std.mem.indexOf(u8, message, "KeReleaseSemaphore(").? + "KeReleaseSemaphore(".len;
        const object = parseFixedWidthHexAfter(message[at..], "", sync_object_field_width) orelse return;
        ledger.observeSignal(object, 0, activeGuestThread(self), guestProgramCounter(self), step);
        return;
    }
    // Creation provenance. An object the emulator built through a kernel export
    // left a breadcrumb; one that only ever appeared as a handle registration
    // did not come through that path, and "nothing signals it" weighs
    // differently for the two.
    if (std.mem.indexOf(u8, message, "NtCreateEvent created handle=") != null) {
        if (parseFixedWidthHexAfter(message, "handle=", sync_object_field_width)) |handle| {
            markProvenanceByHandle(ledger, handle, .kernel_export);
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "Added handle:") != null) {
        if (parseFixedWidthHexAfter(message, "Added handle:", sync_object_field_width)) |handle| {
            markProvenanceByHandle(ledger, handle, .bare_handle);
        }
    }
}

/// Creation lines carry a handle and no object address, and waits carry both.
/// Matching on the handle is what joins them.
fn markProvenanceByHandle(
    ledger: *signal_expectation.Ledger,
    handle: u32,
    provenance: signal_expectation.Provenance,
) void {
    for (ledger.records[0..ledger.count]) |record| {
        if (record.handle != handle) continue;
        ledger.observeProvenance(record.object, provenance);
        return;
    }
}

/// Relate a guest deadline to the time it actually consumed.
///
/// Only expiries are offered. A wait that was signalled early says nothing
/// about its deadline, and averaging it in would pull every ratio toward one
/// and hide the finding — which is the whole reason four bounded polls that
/// each expired could sit in a log next to a producer that had no chance to
/// signal, and neither fact could explain the other.
///
/// `duration_ms` is the emulator's own measure of how long the wait took. The
/// report says so: the value is only as good as the clock the emulator measured
/// it with, and naming the source is what stops a ratio derived from it being
/// read as a wall-clock fact.
fn observeTimeoutFidelity(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "timeout_fidelity")) return;
    if (std.mem.indexOf(u8, message, "WaitForSingleObject result=") == null) return;
    const timed_out = std.mem.indexOf(u8, message, "wait_disposition=timed_out") != null or
        (parseHexAfter(message, "result=") orelse 0) == 0x102;
    if (!timed_out) return;
    const requested = parseSignedDecimalAfter(message, "timeout_ms=") orelse return;
    if (requested <= 0) return;
    const observed = parseDecimalAfter(message, "duration_ms=") orelse return;
    const object = parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width) orelse
        parseFixedWidthHexAfter(message, "obj_ptr=", sync_object_field_width) orelse 0;
    self.timeout_fidelity.observeExpiry(object, @intCast(requested), observed);
}

/// Retain the result of a controlled PM4 vector executed by Xenia's real
/// command processor. The vector is diagnostic-only; it must never advance a
/// title-owned graphics boundary. `reached=none` is a valid result and means
/// the harness supplied no render-target evidence for this run.
fn parseControlledVectorReached(message: []const u8) ?gpu.controlled_vectors.Verdict {
    const token = lifecycleTokenAfter(message, "reached=") orelse return null;
    if (std.mem.eql(u8, token, "state_programmed")) return .state_programmed;
    if (std.mem.eql(u8, token, "target_memory_bound")) return .target_memory_bound;
    if (std.mem.eql(u8, token, "rasterization_executed")) return .rasterization_executed;
    if (std.mem.eql(u8, token, "edram_modified")) return .edram_modified;
    if (std.mem.eql(u8, token, "resolved_to_guest_memory")) return .resolved_to_guest_memory;
    if (std.mem.eql(u8, token, "frame_candidate_published")) return .frame_candidate_published;
    return null;
}

pub fn observeControlledVector(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "audit_vectors")) return;
    if (std.mem.indexOf(u8, message, "DIAGNOSTIC CONTROLLED VECTOR: vector=") == null) return;
    if (std.mem.indexOf(u8, message, "reached=") == null) return;
    const raw_vector = parseDecimalAfter(message, "vector=") orelse return;
    if (raw_vector >= gpu.controlled_vectors.vector_count) return;
    const vector: gpu.controlled_vectors.Vector = @enumFromInt(@as(u8, @intCast(raw_vector)));
    const reached = parseControlledVectorReached(message);
    const outcome = self.audit_vectors.record(vector, reached, self.executed_steps);
    machoCapturePrint(
        "macho-processor: CONTROLLED VECTOR OBSERVED: vector={s} reached={s} outcome={s} step={d}; this is harness evidence through Xenia's real command processor and is never title output\n",
        .{
            vector.label(),
            if (reached) |stage| stage.label() else "none",
            outcome.label(),
            self.executed_steps,
        },
    );
}

/// Learn what became of the draws that entered the command processor and never
/// reached a render target.
///
/// Rosette can already see both ends of this from the instruction pointer:
/// `IssueDraw` entered twenty-four times on 2026-08-30 and
/// `RenderTargetCache::Update` entered zero times. What it cannot see is which
/// of the nine ways out of that function took them — five of which returned
/// with no log line at all. The emulator now counts them, and this reads the
/// count.
///
/// The `defects` split is the part that matters. Leaving `IssueDraw` early is
/// normal: a draw with rasterization disabled and no memory export legitimately
/// has no effect, and a title that submits a batch of those is configuring
/// state rather than failing to render. Leaving because a shader would not
/// translate is a different thing entirely, and a total that mixed them would
/// hide the second inside the first.
/// The emulator's own count of entries into a guest GPU export.
///
/// This is the second observer for a boundary an instruction-pointer
/// tracepoint also watches, and it exists because the two disagreed with
/// nothing to catch it. On 2026-09-05 the boundary gate reported
/// `VdQueryVideoMode ... boundary_never_crossed` at step 2.1 billion while
/// this very breadcrumb said `called (count=1)` earlier in the same log. A
/// tracepoint is exact for the address it is armed on and blind to every
/// other, so when six candidate addresses exist for one export, "never
/// crossed" can mean "armed on the wrong one" — and the frontier then names a
/// boundary the title already passed.
///
/// Stated as a claim rather than folded into either ledger: the whole value is
/// in the comparison, and a merge would destroy the disagreement it exists to
/// surface.
fn observeBoundaryEntryBreadcrumb(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "claim_reconciliation")) return;
    const marker = "DEBUG: ";
    const start = std.mem.indexOf(u8, message, marker) orelse return;
    const rest = message[start + marker.len ..];
    const called = std.mem.indexOf(u8, rest, " called (count=") orelse return;
    const name = rest[0..called];
    const count = parseDecimalAfter(rest, "count=") orelse return;

    const pairs = [_]struct { name: []const u8, claim: claim_reconciliation.Claim }{
        .{ .name = "VdQueryVideoMode", .claim = .vd_query_video_mode_entries },
        .{ .name = "VdInitializeEngines", .claim = .vd_initialize_engines_entries },
        .{ .name = "VdInitializeRingBuffer", .claim = .vd_initialize_ring_buffer_entries },
        .{ .name = "VdSetGraphicsInterruptCallback", .claim = .vd_set_graphics_interrupt_callback_entries },
        .{ .name = "VdSwap", .claim = .vd_swap_entries },
    };
    for (pairs) |pair| {
        if (!std.mem.eql(u8, name, pair.name)) continue;
        self.claim_reconciliation.state(
            pair.claim,
            .xenia_export_breadcrumb,
            count,
            self.executed_steps,
        );
        return;
    }
}

/// Record the raw values Rosette's classifiers could not place.
///
/// The report that used to come out of these was the word `unknown`, thirteen
/// thousand times in one run, naming nothing. A reader cannot add a case for
/// "unknown"; they can add one for "type code 6". This records the value, so
/// the inventory can rank the gaps and each row is a patch.
///
/// `blocking` is set where a conclusion downstream actually consulted the
/// answer. A wait whose object kind is unclassified cannot support a
/// consumption verdict, which is the frontier this run keeps stopping at, so
/// an unmapped wait object is blocking by construction.
fn observeUnknownMappings(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "unknown_inventory")) return;

    // Guest kernel object types, from the wait bridge's own lines.
    if (std.mem.indexOf(u8, message, "NtWaitFor") != null or
        std.mem.indexOf(u8, message, "wait_id=") != null)
    {
        if (parseDecimalAfter(message, "type=")) |raw| {
            const type_code: u32 = @truncate(raw);
            const manual = std.mem.indexOf(u8, message, "event_mode=manual_reset") != null;
            const auto = std.mem.indexOf(u8, message, "event_mode=auto_reset") != null;
            const kind = xeniaWaitObjectKind(type_code, manual or auto, manual);
            if (kind == .unknown) {
                self.unknown_inventory.observe(
                    .guest_object_type,
                    type_code,
                    true,
                    "guest wait object type",
                    self.executed_steps,
                );
            } else if (kind == .not_waitable) {
                // A recognised type in a place it cannot appear. This accuses
                // the parse or the guest rather than asking for a table entry,
                // so it is recorded and not marked blocking.
                self.unknown_inventory.observe(
                    .guest_object_type,
                    type_code,
                    false,
                    "waited on a type with no dispatcher header",
                    self.executed_steps,
                );
            }
        }
    }

    // A VFS path that resolved to a device with no backing store. The raw
    // partition device is legitimately null-backed and is not recorded;
    // anything else answering from nothing is a silent read of zero.
    if (std.mem.indexOf(u8, message, "NtCreateFile(") != null or
        std.mem.indexOf(u8, message, "NtOpenFile(") != null)
    {
        if (std.mem.indexOfScalar(u8, message, '(')) |start| {
            const rest = message[start..];
            self.unknown_inventory.notePath(rest[0..@min(rest.len, 64)]);
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "NullDevice::ResolvePath") != null) {
        if (!self.unknown_inventory.pendingPathIsNullBackedByDesign()) {
            self.unknown_inventory.observe(
                .vfs_device,
                0,
                true,
                "null device resolved a content path",
                self.executed_steps,
            );
        }
    }
}

/// Read the guest's own admission that a kernel call failed.
///
/// `xeRtlNtStatusToDosError <status> => <dos>` is emitted where the title
/// converts a kernel refusal into the error code its caller expects, so every
/// one of these lines is a failure somewhere. Nothing read them until now: the
/// 2026-09-04 run carried fifty-eight and reported none.
///
/// The operation lines are captured first so a status has a subject. A bare
/// `NtOpenFile failed` tells a reader nothing they can act on; the same status
/// beside `cache0:\cache007.map` tells them the title is probing for a cache
/// file it is about to create, which is the difference between fifty-six
/// defects and none.
fn observeKernelStatus(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_status")) return;
    self.guest_status.noteLine();

    // A path resolution that failed names the subject of the status that
    // follows it. Retained rather than reported on its own: on its own it is
    // one more line, and joined to the status it is an explanation.
    if (std.mem.indexOf(u8, message, "Entry::ResolvePath(")) |start| {
        if (std.mem.indexOf(u8, message, "failed") != null) {
            const rest = message[start..];
            const end = @min(rest.len, 80);
            self.guest_status.noteOperation(rest[0..end]);
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "NtOpenFile(") != null or
        std.mem.indexOf(u8, message, "NtCreateFile(") != null)
    {
        const start = std.mem.indexOfScalar(u8, message, '(') orelse return;
        const rest = message[start..];
        const end = @min(rest.len, 80);
        self.guest_status.noteOperation(rest[0..end]);
        return;
    }

    const marker = "xeRtlNtStatusToDosError ";
    const start = std.mem.indexOf(u8, message, marker) orelse return;
    const rest = message[start + marker.len ..];
    const arrow = std.mem.indexOf(u8, rest, " => ") orelse return;
    const status = std.fmt.parseInt(u32, rest[0..arrow], 16) catch return;
    const tail = rest[arrow + 4 ..];
    var digits: usize = 0;
    while (digits < tail.len and tail[digits] >= '0' and tail[digits] <= '9') digits += 1;
    if (digits == 0) return;
    const dos = std.fmt.parseInt(u32, tail[0..digits], 10) catch return;
    self.guest_status.observe(status, dos, self.executed_steps);
}

fn observeDrawAttrition(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_draws_reached_render_target")) return;
    if (std.mem.indexOf(u8, message, "ROSETTE DRAW ") == null) return;

    // `ROSETTE DRAW TARGET` carries the destination the command processor
    // decoded on the way past. It is the evidence that separates "the title
    // named no target" from "the emulator failed to decode one" — two
    // findings with different owners that a draw count cannot tell apart.
    if (std.mem.indexOf(u8, message, "ROSETTE DRAW TARGET:") != null) {
        if (comptime @hasField(State, "audit_render_target")) {
            const reached = parseDecimalAfter(message, "reached_render_target=") orelse 0;
            const candidate = self.audit_render_target.begin(self.executed_steps, .guest_authentic);
            if (candidate) |entry| {
                const color_base = parseHexAfter(message, "color_base=") orelse 0;
                const depth_base = parseHexAfter(message, "depth_base=") orelse 0;
                const pitch = parseDecimalAfter(message, "surface_pitch=") orelse 0;
                entry.target = .{
                    .color_info = @truncate(color_base),
                    .depth_info = @truncate(depth_base),
                    .surface_info = @truncate(pitch),
                    // A register that was decoded is valid; a base of zero is a
                    // decoded value and not a destination, which is what
                    // `programmed()` refuses on.
                    .color_valid = color_base != 0,
                    .depth_valid = depth_base != 0,
                    .surface_valid = pitch != 0,
                    .pitch = @truncate(pitch),
                    .width = @truncate(pitch),
                    .height = if (pitch != 0) 1 else 0,
                };
                entry.raster = .{
                    .rasterization_enabled = std.mem.indexOf(u8, message, "rasterization=YES") != null,
                    .memexport_ranges = @truncate(parseDecimalAfter(message, "memexport_ranges=") orelse 0),
                    .viewport_width = @truncate(pitch),
                    .viewport_height = if (pitch != 0) 1 else 0,
                    .scissor_width = @truncate(pitch),
                    .scissor_height = if (pitch != 0) 1 else 0,
                };
                if (entry.target.programmed()) entry.note(.state_programmed);
                if (reached != 0 and entry.target.programmed()) {
                    entry.note(.target_memory_bound);
                    entry.classification = .target_backed;
                } else if (!entry.raster.couldProduceOutput()) {
                    entry.classification = .intentional_no_output;
                }
            }
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "ROSETTE DRAW LEDGER:") != null) {
        if (parseDecimalAfter(message, "draws=")) |value| {
            self.gpu_draws_entered = value;
            if (comptime @hasField(State, "monotone_witness")) {
                // Xenia restates the cumulative IssueDraw total here. It is a
                // strong total, not a line-counting breadcrumb; treating it as
                // a sampled line makes a healthy cumulative observer look like
                // an undercount as soon as the line is throttled.
                self.monotone_witness.state(
                    .draws_issued,
                    .emulator_sampled_total,
                    value,
                    self.executed_steps,
                );
            }
        }
        if (parseDecimalAfter(message, "reached_render_target=")) |value| {
            self.gpu_draws_reached_render_target = value;
            // This is the number of draws that survived to target setup, not
            // the number of RenderTargetCache::Update calls. Keep it as draw
            // attrition evidence, but never let it speak for the distinct
            // render_target_updates subject.
        }
        if (parseDecimalAfter(message, "exited_early=")) |value| {
            self.gpu_draw_early_exits = value;
        }
        if (parseDecimalAfter(message, "defects=")) |value| {
            self.gpu_draw_defect_exits = value;
        }
        return;
    }
    // `ROSETTE DRAW EXIT: draw #N left IssueDraw at <name> without ...`
    const at = std.mem.indexOf(u8, message, " at ") orelse return;
    const rest = message[at + 4 ..];
    const end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
    if (end == 0) return;
    self.gpu_draw_exits_named +|= 1;
    if (self.gpu_draw_first_exit_length != 0) return;
    const length = @min(end, self.gpu_draw_first_exit.len);
    @memcpy(self.gpu_draw_first_exit[0..length], rest[0..length]);
    self.gpu_draw_first_exit_length = @intCast(length);
    self.gpu_draw_first_exit_step = self.executed_steps;
}

/// Build the one transaction a pause is allowed to have.
///
/// The 2026-08-31 log printed `GPU PRODUCER PAUSED` and contained no
/// `GUEST FAULT FRONTIER`, no `EMULATOR PAUSED` and no `EMULATOR RESUMED`.
/// With nothing to reconcile the warning against, "the emulator paused without
/// recording why" and "the record was shed" are the same evidence, and they
/// need different fixes.
///
/// So a report that the guest is paused is counted separately from a
/// transaction that explains it. An unmatched report is `unreconciled` and can
/// never be quoted as a cause — and just as importantly, no wait observed
/// after it may be read as the guest's own behaviour until it is settled.
fn observeFaultPauseTransaction(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "audit_pause")) return;
    const ledger = &self.audit_pause;
    const step = self.executed_steps;

    if (std.mem.indexOf(u8, message, "GUEST FAULT TRANSACTION:") != null) {
        if (parseDecimalAfter(message, "id=")) |external_id| {
            ledger.noteExternalTransaction(external_id, step);
        } else {
            ledger.noteMalformedExternalTransaction(step);
        }
        return;
    }

    if (std.mem.indexOf(u8, message, "GUEST FAULT FRONTIER:") != null) {
        const transaction = ledger.begin(.guest_fault, step) orelse return;
        transaction.location = .{
            .guest_pc = @truncate(parseHex64After(message, "guest_pc=") orelse 0),
            .guest_lr = @truncate(parseHex64After(message, "guest_lr=") orelse 0),
        };
        transaction.fault_address = .{
            .host = parseHex64After(message, "fault_address=") orelse 0,
        };
        transaction.guest_thread = parseDecimalAfter(message, "thread=") orelse 0;
        transaction.note(.pause_requested, step);
        if (ensureAuditJournal(self)) {
            _ = writeStructuredJournal(self, .{
                .kind = @intFromEnum(run_journal.EventKind.fault),
                .domain = @intFromEnum(run_journal.Domain.xenia_kernel),
                .source_class = @intFromEnum(run_journal.SourceClass.guest_authentic),
                .result_class = @intFromEnum(run_journal.ResultClass.observed),
                .guest_step = step,
                .guest_thread = transaction.guest_thread,
                .location = transaction.location,
                .address = transaction.fault_address,
                .subject_id = transaction.fault_address.host,
            });
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "EMULATOR PAUSED") != null) {
        const external_id = parseDecimalAfter(message, "transaction=");
        const has_guest_fault_metadata =
            std.mem.indexOf(u8, message, "guest_fault=") != null;
        const guest_fault = std.mem.indexOf(u8, message, "guest_fault=YES") != null;
        const transaction = ledger.current() orelse
            (ledger.begin(.emulator_internal, step) orelse return);
        if (external_id != null or has_guest_fault_metadata) {
            const observed_id = external_id orelse 0;
            if (guest_fault and transaction.cause == .guest_fault) {
                if (observed_id == 0) {
                    ledger.noteProtocolDefect(
                        .producer_pause_without_transaction,
                        step,
                        transaction.external_id,
                        observed_id,
                    );
                } else if (!transaction.noteExternalId(observed_id, step)) {
                    ledger.noteProtocolDefect(
                        .external_transaction_mismatch,
                        step,
                        transaction.external_id,
                        observed_id,
                    );
                }
            } else if (guest_fault or observed_id != 0) {
                ledger.noteProtocolDefect(
                    .external_transaction_mismatch,
                    step,
                    transaction.external_id,
                    observed_id,
                );
            }
        }
        transaction.note(.pause_completed, step);
        if (ensureAuditJournal(self)) {
            _ = writeStructuredJournal(self, .{
                .kind = @intFromEnum(run_journal.EventKind.pause),
                .domain = @intFromEnum(run_journal.Domain.xenia_kernel),
                .source_class = @intFromEnum(run_journal.SourceClass.host_forwarded),
                .result_class = @intFromEnum(run_journal.ResultClass.applied),
                .guest_step = step,
                .generation = transaction.id,
            });
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "EMULATOR RESUMED") != null) {
        const external_id = parseDecimalAfter(message, "transaction=");
        const transaction = ledger.current() orelse {
            ledger.noteProtocolDefect(
                .resume_without_transaction,
                step,
                0,
                external_id orelse 0,
            );
            return;
        };
        if (transaction.cause == .guest_fault) {
            const observed_id = external_id orelse 0;
            if (observed_id == 0 or !transaction.noteExternalId(observed_id, step)) {
                ledger.noteProtocolDefect(
                    .external_transaction_mismatch,
                    step,
                    transaction.external_id,
                    observed_id,
                );
            }
        } else if (external_id) |observed_id| {
            if (observed_id != 0) {
                ledger.noteProtocolDefect(
                    .external_transaction_mismatch,
                    step,
                    transaction.external_id,
                    observed_id,
                );
            }
        }
        transaction.note(.resume_requested, step);
        transaction.note(.resume_completed, step);
        if (ensureAuditJournal(self)) {
            _ = writeStructuredJournal(self, .{
                .kind = @intFromEnum(run_journal.EventKind.resume_execution),
                .domain = @intFromEnum(run_journal.Domain.xenia_kernel),
                .source_class = @intFromEnum(run_journal.SourceClass.host_forwarded),
                .result_class = @intFromEnum(run_journal.ResultClass.applied),
                .guest_step = step,
                .generation = transaction.id,
            });
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "GPU PRODUCER PAUSED") != null) {
        // The report, not the cause. If no transaction is open this becomes an
        // unmatched report and the ledger's standing turns `unreconciled`.
        const external_id = parseDecimalAfter(message, "transaction=") orelse 0;
        const reconciled = std.mem.indexOf(u8, message, "reconciled=YES") != null;
        const matched = ledger.observePauseReportWithMetadata(
            step,
            external_id,
            reconciled,
        );
        if (ensureAuditJournal(self)) {
            _ = writeStructuredJournal(self, .{
                .kind = @intFromEnum(run_journal.EventKind.pause),
                .domain = @intFromEnum(run_journal.Domain.xenia_command_processor),
                .source_class = @intFromEnum(run_journal.SourceClass.host_forwarded),
                .result_class = @intFromEnum(if (matched)
                    run_journal.ResultClass.applied
                else
                    run_journal.ResultClass.unreconciled),
                .guest_step = step,
            });
        }
    }
}

/// Learn what address is actually in the graphics interrupt callback slot, from
/// the emulator's own statement of it.
///
/// `SetInterruptCallback` is the one line that says which callback the emulator
/// will dispatch into, and Rosette was not reading it. The 2026-08-30 20:08 run
/// contains exactly three:
///
/// ```text
/// SetInterruptCallback(FFFF0010, 00000000)   <- the emulator's own host callback
/// SetInterruptCallback(825ACC80, 00000000)   <- the title
/// SetInterruptCallback(821951F8, 40001F00)   <- the title, with its user data
/// ```
///
/// Without it the completion-route ledger reported `established=NO
/// address=0x00000000` for a registration that plainly happened, and the
/// occupancy line said a host callback held the slot long after the title had
/// taken it. The slot holds one address and the **newest** statement is the one
/// that is true — every earlier one is a snapshot of a slot that has since
/// changed hands.
fn observeInterruptCallbackSlot(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_interrupt_slot_address")) return;
    const at = std.mem.indexOf(u8, message, "SetInterruptCallback(") orelse return;
    const rest = message[at + "SetInterruptCallback(".len ..];
    const callback = parseFixedWidthHexAfter(rest, "", 8) orelse return;
    const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return;
    const user_data = parseFixedWidthHexAfter(rest[comma..], " ", 8) orelse 0;

    // A guest callback lives in the console's address space. The emulator's own
    // host callback is a builtin outside it, and telling the two apart is what
    // decides whether a dispatch reaches the title or the harness.
    const is_guest = callback >= 0x8000_0000 and callback < 0xC000_0000;
    const previous_address = self.gpu_interrupt_slot_address;
    const previous_user_data = self.gpu_interrupt_slot_user_data;
    const previous_step = self.gpu_interrupt_slot_step;
    const previous_is_guest = self.gpu_interrupt_slot_is_guest;
    const had_previous = self.gpu_interrupt_slot_writes != 0;
    const changed = had_previous and
        (previous_address != callback or previous_user_data != user_data);
    if (changed) {
        if (comptime @hasField(State, "gpu_interrupt_slot_previous_address"))
            self.gpu_interrupt_slot_previous_address = previous_address;
        if (comptime @hasField(State, "gpu_interrupt_slot_previous_user_data"))
            self.gpu_interrupt_slot_previous_user_data = previous_user_data;
        if (comptime @hasField(State, "gpu_interrupt_slot_previous_step"))
            self.gpu_interrupt_slot_previous_step = previous_step;
        if (comptime @hasField(State, "gpu_interrupt_slot_previous_is_guest"))
            self.gpu_interrupt_slot_previous_is_guest = previous_is_guest;
        if (comptime @hasField(State, "gpu_interrupt_slot_transitions"))
            self.gpu_interrupt_slot_transitions +|= 1;
    }
    self.gpu_interrupt_slot_address = callback;
    self.gpu_interrupt_slot_user_data = user_data;
    self.gpu_interrupt_slot_step = self.executed_steps;
    self.gpu_interrupt_slot_writes +|= 1;
    self.gpu_interrupt_slot_is_guest = is_guest;
    if (comptime @hasField(State, "gpu_interrupt_slot_guest_writes")) {
        if (is_guest) {
            self.gpu_interrupt_slot_guest_writes +|= 1;
        } else {
            self.gpu_interrupt_slot_host_writes +|= 1;
        }
    }

    // The transaction ledgers are fed from the emulator's `GPU callback set:`
    // breadcrumb, which is rate-limited and was absent for the title's own
    // registrations. That left the PowerPC-domain ledger reporting
    // `registered=0` for a registration this very line states — a zero that is
    // the observer's and reads as the title's. This line is the authoritative
    // statement of the slot, so it feeds the ledger for the domain it belongs
    // to.
    if (comptime @hasField(State, "interrupt_callback_transaction")) {
        if (self.gpu_interrupt_slot_is_guest) {
            self.interrupt_callback_transaction.observeRegistration(
                self.gpu_interrupt_slot_writes,
                callback,
                user_data,
                self.executed_steps,
            );
        }
    }
    if (comptime @hasField(State, "host_interrupt_callback_transaction")) {
        if (!self.gpu_interrupt_slot_is_guest) {
            self.host_interrupt_callback_transaction.observeRegistration(
                self.gpu_interrupt_slot_writes,
                callback,
                user_data,
                self.executed_steps,
            );
        }
    }
}

/// Join the guest's wait records to the thread that published to the command
/// ring, so `SWAP HEALTH`'s standing instruction — *"find what the submitting
/// thread is waiting on"* — finally has an answer in the same run that asks it.
///
/// The tracker itself drops every line from a thread that is not the producer,
/// so this does not have to know which thread that is. What it must get right
/// is the disposition: a *result* line proves the wait returned, and a wait
/// that returns cannot be what is holding a producer however long the producer
/// has been quiet. Only an entry line with no result behind it is a park.
///
/// That distinction is the whole value. A parked producer and a cycling one
/// look identical in every counter the run prints — quiet write pointer,
/// drained ring, idle command processor — and they call for opposite work: a
/// park is a lost wakeup with a named object, and a cycle means the title is
/// waiting for something the waits are not about.
fn observeProducerWaitLine(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_producer_stall")) return;
    // One rejecting compare for every guest log line that is not a wait.
    if (std.mem.indexOf(u8, message, "WaitForSingleObject") == null) return;
    const entering = std.mem.indexOf(u8, message, "WaitForSingleObject tid=") != null;
    const returning = std.mem.indexOf(u8, message, "WaitForSingleObject result=") != null;
    if (!entering and !returning) return;

    const handle = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
    const object = parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width) orelse
        parseFixedWidthHexAfter(message, "obj_ptr=", sync_object_field_width) orelse 0;
    // The leading space matters: `pc=` also matches inside `guest_pc=` and
    // `pc_entry=`, and attributing a cycle to the wrong call site would make
    // two sites look like one.
    const pc = parseHex64After(message, " pc=") orelse 0;
    const duration = parseDecimalAfter(message, "duration_ms=") orelse 0;

    const Sample = @TypeOf(self.gpu_producer_stall.samples[0]);
    const disposition: @FieldType(Sample, "disposition") = if (entering)
        .parked
    else if (std.mem.indexOf(u8, message, "wait_disposition=timed_out") != null)
        .timed_out
    else if (std.mem.indexOf(u8, message, "wait_disposition=ready_on_entry") != null)
        .ready_on_entry
    else
        .blocked_then_released;

    // Every wait is offered as activity too. The tracker drops the ones from
    // other threads out of its window and counts them separately, which is what
    // stops a silent attributed thread being reported as a dead guest.
    self.gpu_producer_stall.noteActivity(activeGuestThread(self), self.executed_steps);
    self.gpu_producer_stall.observeWait(activeGuestThread(self), .{
        .object = object,
        .handle = handle,
        .pc = pc,
        .disposition = disposition,
        .step = self.executed_steps,
        .duration_ms = @truncate(duration),
    });
}

/// Learn where the command processor was told to mirror the ring read pointer.
///
/// This address is the title's only memory-side view of GPU progress. It asked
/// for it with `VdEnableRingBufferRPtrWriteBack` and it polls the word forever
/// afterwards; if the word never changes, the title's belief about how much the
/// GPU has consumed is frozen at whatever was there when it started, no matter
/// how many packets the command processor actually drained.
///
/// Only the *address* is taken from the log. Whether anything ever arrives
/// there is read out of console memory by the completion-route ledger, because
/// the emulator writing the same value repeatedly is indistinguishable from not
/// writing at all to the code that reads it — and the emulator has no way to
/// notice the difference from its own side.
fn observeReadPointerWriteBackConfig(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_read_pointer_writeback_address")) return;
    if (std.mem.indexOf(u8, message, "RPTR writeback configured") == null) return;
    const pointer = parseHexAfter(message, "ptr=") orelse return;
    self.gpu_read_pointer_writeback_address = pointer;
    if (parseDecimalAfter(message, "update_freq=")) |frequency| {
        self.gpu_read_pointer_writeback_freq = @truncate(frequency);
    }
    self.gpu_read_pointer_writeback_mapped =
        std.mem.indexOf(u8, message, "mapped=YES") != null;
    if (comptime @hasField(State, "gpu_bootstrap_provenance")) {
        self.gpu_bootstrap_provenance.observeConfiguration(
            .rptr_writeback,
            self.executed_steps,
            self.gpu_read_pointer_writeback_mapped,
        );
    }
}

/// Recover the guest's own clock from the emulator's vblank reporting.
///
/// Rosette counted guest instructions and host seconds and never knew how much
/// of the *title's* timeline a run had covered. Without that, "X never
/// happened" cannot be told apart from "the run ended before X was due", and
/// the two call for opposite responses. The emulator states it plainly and
/// nothing was reading it.
fn observeRunHorizonClock(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "run_horizon")) return;
    const vblank = parseDecimalAfter(message, "vblank_id=") orelse return;
    const emulated = parseDecimalAfter(message, "since_first_vblank=") orelse
        parseDecimalAfter(message, "since_first_vblank_ms=") orelse 0;
    self.run_horizon.observe(.{
        .step = self.executed_steps,
        .emulated_ms = emulated,
        .vblanks = vblank,
        .host_seconds = elapsedHostSeconds(self),
    });
}

fn elapsedHostSeconds(self: anytype) u64 {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "run_started_at_ns")) return 0;
    const now = startup_observer.monotonicNanoseconds();
    if (self.run_started_at_ns == 0 or now <= self.run_started_at_ns) return 0;
    return (now - self.run_started_at_ns) / std.time.ns_per_s;
}

/// Feed the emulator's own disagreeing statements to the reconciliation ledger.
///
/// Each of these lines carries a snapshot of the same handful of facts, taken
/// at the moment that code path ran, and none of them is ever retracted. The
/// bring-up diagnostics keep saying `ring_init=NO rb_base=00000000` long after
/// the startup watch has reported the ring configured, and the first of those
/// is the one a reader finds. Recording which emitter said what, and when, is
/// what lets the report name the current value instead of the loudest one.
fn observeReconciledClaims(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "claim_reconciliation")) return;
    const step = self.executed_steps;
    const ledger = &self.claim_reconciliation;

    const source: claim_reconciliation.Source =
        if (std.mem.indexOf(u8, message, "gpu_startup_watch") != null)
            .xenia_startup_watch
        else if (std.mem.indexOf(u8, message, "no-swap diagnosis") != null)
            .xenia_no_swap_diagnosis
        else if (std.mem.indexOf(u8, message, "CALLBACK WATCHDOG") != null)
            .xenia_callback_watchdog
        else if (std.mem.indexOf(u8, message, "GPU FALLBACK PROBE INPUTS") != null)
            .xenia_fallback_probe
        else if (std.mem.indexOf(u8, message, "callback-exec timing") != null or
        std.mem.indexOf(u8, message, "VdSetGraphicsInterruptCallback execution") != null)
            .xenia_callback_exec_timing
        else
            return;

    if (parseFlagAfter(message, "ring_init=")) |value| {
        ledger.stateBool(.ring_initialised, source, value, step);
    }
    if (parseFlagAfter(message, "init_ack=")) |value| {
        ledger.stateBool(.ring_init_acknowledged, source, value, step);
    }
    if (parseFlagAfter(message, "callback_set=")) |value| {
        ledger.stateBool(.interrupt_callback_set, source, value, step);
    }
    if (parseFlagAfter(message, "interrupt_callback_set=")) |value| {
        ledger.stateBool(.interrupt_callback_set, source, value, step);
    }
    if (parseFlagAfter(message, "guest_main_ready=")) |value| {
        ledger.stateBool(.guest_main_ready, source, value, step);
    }
    if (parseHexAfter(message, "rb_base=")) |value| {
        ledger.state(.ring_base_address, source, value, step);
    }
    if (parseHexAfter(message, "rb_size=")) |value| {
        ledger.state(.ring_size_bytes, source, value, step);
    }
    if (parseHexAfter(message, "read_ptr=")) |value| {
        ledger.state(.ring_read_pointer, source, value, step);
    }
    if (parseHexAfter(message, "write_ptr=")) |value| {
        ledger.state(.ring_write_pointer, source, value, step);
    }
    if (parseHexAfter(message, "callback=")) |value| {
        ledger.state(.interrupt_callback_address, source, value, step);
    }
    if (parseDecimalAfter(message, "callback_completions=")) |value| {
        ledger.state(.callback_completions, source, value, step);
    }
    if (parseDecimalAfter(message, "swap_packets=")) |value| {
        ledger.state(.swap_packets_consumed, source, value, step);
    }
}

const InterruptCallbackLogDomain = enum(u8) {
    unknown,
    powerpc,
    host,
};

/// Classify a callback breadcrumb before it is allowed to update a ledger.
///
/// Xenia's Rosette host callback deliberately travels through the same
/// `DispatchInterruptCallback` path as a title callback. The two therefore
/// share dispatch/completion wording, but they do not share ownership. Source
/// labels are preferred; callback-address continuity is the fallback for
/// completion/context lines that do not repeat the source label. An unknown
/// line remains unknown rather than being credited to the guest domain.
fn interruptCallbackLogDomain(self: anytype, message: []const u8) InterruptCallbackLogDomain {
    const State = @TypeOf(self.*);
    // Newer Xenia breadcrumbs carry an explicit domain. Consume that before
    // source labels or address continuity: a live callback slot can change
    // between an attempt and its completion, while the producer's domain is
    // immutable for the breadcrumb being parsed.
    if (std.mem.indexOf(u8, message, "callback_domain=rosette-host") != null) return .host;
    if (std.mem.indexOf(u8, message, "callback_domain=guest-title") != null) return .powerpc;
    if (std.mem.indexOf(u8, message, "callback_domain=xenia-unknown") != null) return .unknown;

    // This breadcrumb is emitted by the Rosette/Xenia bridge itself and is
    // deliberately explicit that the callback is not a guest registration.
    // It is the earliest reliable identity for the host callback, before a
    // later dispatch line repeats its address.
    if (std.mem.indexOf(u8, message, "ROSETTE HOST GPU CALLBACK: installed") != null or
        std.mem.indexOf(u8, message, "ROSETTE HOST GPU CALLBACK: guest/Xenia callback replaced") != null)
    {
        return .host;
    }
    if (std.mem.indexOf(u8, message, "source=rosette-host") != null) return .host;
    if (std.mem.indexOf(u8, message, "source=guest-or-xenia") != null) return .powerpc;

    // Xenia's concrete VdSet breadcrumb is a guest-title registration event,
    // even when an older build does not include `callback_domain=`. Without
    // this explicit classification the bootstrap contract knows the callback
    // was set while the transaction ledger still reports zero registrations.
    if (std.mem.indexOf(u8, message, "VdSetGraphicsInterruptCallback EXECUTED:") != null or
        std.mem.indexOf(u8, message, "RING BUFFER: VdSetGraphicsInterruptCallback call count=") != null)
    {
        return .powerpc;
    }

    if (parseHexAfter(message, "callback=")) |callback| {
        if (callback != 0) {
            if (comptime @hasField(State, "host_interrupt_callback_transaction")) {
                if (self.host_interrupt_callback_transaction.callback_address == callback) return .host;
            }
            if (comptime @hasField(State, "interrupt_callback_transaction")) {
                if (self.interrupt_callback_transaction.callback_address == callback) return .powerpc;
            }
        }
    }

    // Context and no-callback lines do not always carry an address. They may
    // still be retained, but only under the domain of the most recent
    // provenance-bearing callback event.
    if (std.mem.indexOf(u8, message, "GPU callback context ") != null or
        std.mem.indexOf(u8, message, "GPU callback dispatch skipped:") != null)
    {
        if (comptime @hasField(State, "last_interrupt_callback_log_domain")) {
            return switch (self.last_interrupt_callback_log_domain) {
                @intFromEnum(InterruptCallbackLogDomain.powerpc) => .powerpc,
                @intFromEnum(InterruptCallbackLogDomain.host) => .host,
                else => .unknown,
            };
        }
    }
    return .unknown;
}

/// Build execution-domain-correct transactions from Xenia's callback logs.
/// Completion lines are self-contained and carry monotonic attempts/returns,
/// so a dropped or torn earlier dispatch line cannot manufacture a missing
/// callback. Rosette's host callback is retained in its own ledger for
/// observability, but it never enters the title/PowerPC ledger.
fn observeInterruptCallbackTransaction(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "interrupt_callback_transaction")) return;
    const domain = interruptCallbackLogDomain(self, message);
    const ledger = switch (domain) {
        .powerpc => &self.interrupt_callback_transaction,
        .host => if (comptime @hasField(State, "host_interrupt_callback_transaction"))
            &self.host_interrupt_callback_transaction
        else
            return,
        .unknown => return,
    };
    const step = self.executed_steps;

    if (comptime @hasField(State, "last_interrupt_callback_log_domain")) {
        self.last_interrupt_callback_log_domain = @intFromEnum(domain);
    }

    if (std.mem.indexOf(u8, message, "ROSETTE HOST GPU CALLBACK: installed") != null) {
        const callback = parseHexAfter(message, "callback=") orelse return;
        if (callback == 0) return;
        const registration = parseDecimalAfter(message, "vblank_id=") orelse 1;
        ledger.observeRegistration(registration, callback, parseHexAfter(message, "user_data=") orelse 0, step);
        return;
    }
    // The placeholder standing down. Without this the host domain ends the run
    // reporting `registered=1 attempts=0 finding=registered_no_dispatch
    // owner=interrupt producer`, which is the shape of a producer that never
    // ran and is in fact a handover that worked.
    if (std.mem.indexOf(u8, message, "ROSETTE HOST GPU CALLBACK: guest/Xenia callback replaced") != null) {
        const successor = parseHexAfter(message, "callback=") orelse 0;
        if (comptime @hasField(State, "host_interrupt_callback_transaction")) {
            self.host_interrupt_callback_transaction.noteSuperseded(successor, step);
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "GPU callback set: count=") != null) {
        const count = parseDecimalAfter(message, "GPU callback set: count=") orelse return;
        const callback = parseHexAfter(message, "callback=") orelse 0;
        const user_data = parseHexAfter(message, "user_data=") orelse 0;
        ledger.observeRegistration(count, @truncate(callback), @truncate(user_data), step);
        return;
    }
    // Current Xenia emits both a concise execution breadcrumb and a verbose
    // ring-buffer breadcrumb. They are registration evidence, not dispatch
    // attempts. Accept only these explicit forms so a callback-shaped value in
    // VdInitializeEngines cannot open the interrupt route.
    if (std.mem.indexOf(u8, message, "VdSetGraphicsInterruptCallback EXECUTED:") != null) {
        const callback = parseHexAfter(message, "cb=") orelse return;
        if (callback == 0) return;
        const user_data = parseHexAfter(message, "arg=") orelse 0;
        ledger.observeRegistration(1, callback, user_data, step);
        return;
    }
    if (std.mem.indexOf(u8, message, "RING BUFFER: VdSetGraphicsInterruptCallback call count=") != null) {
        const count = parseDecimalAfter(message, "call count=") orelse return;
        const callback = parseHexAfter(message, "callback=") orelse return;
        if (callback == 0) return;
        const user_data = parseHexAfter(message, "user_data=") orelse 0;
        ledger.observeRegistration(count, callback, user_data, step);
        return;
    }
    // Xenia's callback executor restates its own entered/returned totals on a
    // fixed cadence, long after the completion breadcrumb below has stopped
    // being printed. Reading only the breadcrumb froze this ledger at four
    // dispatches while the callback ran two hundred and forty times, and every
    // report built on it named the wrong owner for four and a half billion
    // steps. Both carriers are read, and the monotone-witness ledger keeps the
    // disagreement visible rather than silently resolving it.
    if (std.mem.indexOf(u8, message, "ROSETTE INTERRUPT DISPATCH:") != null) {
        const id = parseDecimalAfter(message, "id=") orelse return;
        const leaving = std.mem.indexOf(u8, message, "leave id=") != null;
        const entered = parseDecimalAfter(message, "entered=") orelse id;
        const returned = if (leaving)
            (parseDecimalAfter(message, "returned=") orelse id)
        else
            0;
        ledger.observeExecutorCounters(entered, returned, step);
        if (domain == .powerpc) {
            if (comptime @hasField(State, "audit_interrupts")) {
                const callback_address: u32 = @truncate(parseHexAfter(message, "callback=") orelse 0);
                self.audit_interrupts.observeTotals(entered, returned, step);
                if (leaving) {
                    self.audit_interrupts.observeReturn(id, callback_address, step);
                } else if (std.mem.indexOf(u8, message, "enter id=") != null) {
                    self.audit_interrupts.observeEntry(id, callback_address, @truncate(parseDecimalAfter(message, "source=") orelse 0xffffffff), @truncate(parseDecimalAfter(message, "cpu=") orelse 0), step);
                }
            }
        }
        // The shared executor path also carries Rosette's host callback. Its
        // counters belong to the host ledger and must not corroborate (or
        // contradict) the title callback subject.
        if (domain == .powerpc) {
            if (comptime @hasField(State, "monotone_witness")) {
                self.monotone_witness.state(
                    .title_interrupt_callback_entries,
                    .emulator_sampled_total,
                    entered,
                    step,
                );
                if (leaving) {
                    self.monotone_witness.state(
                        .title_interrupt_callback_returns,
                        .emulator_sampled_total,
                        returned,
                        step,
                    );
                }
            }
        }
        return;
    }
    if (std.mem.indexOf(u8, message, "GPU callback dispatch completed:") != null) {
        const id = parseDecimalAfter(message, "id=") orelse return;
        // The source is what makes an interrupt readable. Source 0 is the
        // vblank pump, which fires on its own schedule; source 1 is the command
        // stream's own interrupt packet, which is how a title learns its batch
        // finished. A total that merged them would let seven hundred vblanks
        // mask a completion that never arrived.
        if (comptime @hasField(@TypeOf(self.*), "gpu_packet_census")) {
            self.gpu_packet_census.observeInterruptDelivered(
                @truncate(parseDecimalAfter(message, "source=") orelse 0),
            );
        }
        const attempts = parseDecimalAfter(message, "attempts=") orelse id;
        const completions = parseDecimalAfter(message, "completions=") orelse id;
        if (domain == .powerpc) {
            if (comptime @hasField(State, "monotone_witness")) {
                self.monotone_witness.state(
                    .title_interrupt_callback_entries,
                    .emulator_sampled_line,
                    attempts,
                    step,
                );
                self.monotone_witness.state(
                    .title_interrupt_callback_returns,
                    .emulator_sampled_line,
                    completions,
                    step,
                );
            }
        }
        ledger.observeCompletion(
            id,
            attempts,
            completions,
            @truncate(parseHexAfter(message, "callback=") orelse 0),
            @truncate(parseDecimalAfter(message, "source=") orelse 0),
            @truncate(parseDecimalAfter(message, "cpu=") orelse 0),
            parseDecimalAfter(message, "duration_ms=") orelse 0,
            parseFlagAfter(message, "payload_before=") orelse false,
            parseFlagAfter(message, "payload_after=") orelse false,
            parseFlagAfter(message, "payload_changed=") orelse false,
            step,
        );
        return;
    }
    if (std.mem.indexOf(u8, message, "GPU callback dispatch: count=") != null) {
        const count = parseDecimalAfter(message, "GPU callback dispatch: count=") orelse return;
        ledger.observeDispatch(
            count,
            @truncate(parseDecimalAfter(message, "source=") orelse 0),
            @truncate(parseDecimalAfter(message, "cpu=") orelse 0),
            step,
        );
        return;
    }
    if (std.mem.indexOf(u8, message, "GPU callback dispatch skipped:") != null) {
        ledger.observeSkip();
        return;
    }
    if (std.mem.indexOf(u8, message, "GPU interrupt dispatch deferred") != null) {
        ledger.observeDeferral(parseDecimalAfter(message, "count=") orelse 1);
        return;
    }
    if (std.mem.indexOf(u8, message, "GPU callback context before:") != null) {
        ledger.observeContextBefore();
        return;
    }
    if (std.mem.indexOf(u8, message, "GPU callback context after:") != null) {
        ledger.observeContextAfter(parseFlagAfter(message, "context_changed=") orelse false);
    }
}

/// Find a field key without accepting it as a suffix of another field. This is
/// important for `timeout_ms=` versus `requested_timeout_ms=` and for all
/// future schema extensions that add a qualified field name.
fn fieldOffset(message: []const u8, key: []const u8) ?usize {
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, message, search_from, key)) |at| {
        if (at == 0 or
            (!std.ascii.isAlphanumeric(message[at - 1]) and message[at - 1] != '_'))
        {
            return at;
        }
        search_from = at + key.len;
    }
    return null;
}

/// `YES`/`NO` as the emulator writes them. Deliberately strict: a key whose
/// value is neither must not be guessed, because a guess here becomes a claim
/// that contradicts a real observation.
fn parseFlagAfter(message: []const u8, key: []const u8) ?bool {
    const at = fieldOffset(message, key) orelse return null;
    const rest = message[at + key.len ..];
    if (std.mem.startsWith(u8, rest, "YES")) return true;
    if (std.mem.startsWith(u8, rest, "NO")) return false;
    return null;
}

pub fn observeKernelSurfaceAddress(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_kernel_surface_addresses")) return;
    var lines = std.mem.splitScalar(u8, message, '\n');
    while (lines.next()) |line| observeKernelSurfaceAddressLine(self, line);
}

fn observeKernelSurfaceAddressLine(self: anytype, line: []const u8) void {
    var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
    const kind = tokens.next() orelse return;
    if (kind.len != 1 or kind[0] != 'V') return;
    const address_token = tokens.next() orelse return;
    const address = std.fmt.parseInt(u32, address_token, 16) catch return;
    const ordinal_token = tokens.next() orelse return;
    const ordinal = std.fmt.parseInt(u16, ordinal_token, 16) catch return;
    self.gpu_kernel_surface_addresses.record(ordinal, address);
    if (comptime @hasField(@TypeOf(self.*), "gpu_kernel_variables")) {
        if (gpu.kernel_variables.Variable.fromOrdinal(ordinal)) |which| {
            // The dump lists every export the module has, imported or not, so
            // the slot address is known here and whether the title imports it
            // is settled separately by the emulator's own ordinal report.
            self.gpu_kernel_variables.observeImport(which, true, address);

            // Provision now, not on the next diagnostic heartbeat.
            //
            // This line is the first moment the slot's address exists — before
            // it there is nowhere to write — and the heartbeat that used to be
            // the only provisioning path is a hundred million guest steps away.
            // The title reads these during display bring-up, long before then,
            // and a zero sends it down an early-return branch it never
            // revisits. A correct value that arrives afterwards makes every
            // counter read healthy and changes nothing about the run.
            //
            // Owner rules are unchanged: `writeDecision` still refuses
            // title-owned variables and structured initialisers, so this is
            // earlier provisioning of exactly the same platform state, not more
            // of it.
            if (comptime @hasDecl(@TypeOf(self.*), "provisionPlatformStateNow")) {
                self.provisionPlatformStateNow();
            }
        }
    }
}

/// Read the presenter's account of the guest output it does not have.
///
/// The emulator prints the mailbox slot, the front buffer address and its own
/// refresh attempt/success counters on several differently shaped lines. Every
/// one of those numbers is a consequence of the producer, and a reader who
/// arrives at `mailbox=-1` has arrived at the end of the chain — so the numbers
/// are taken here and joined to Rosette's own frontier rather than left to be
/// read as a presenter defect.
fn observeGuestOutputMailbox(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_guest_output_mailbox")) return;
    const ledger = &self.gpu_guest_output_mailbox;

    if (std.mem.indexOf(u8, message, "force clear frame=") != null or
        std.mem.indexOf(u8, message, "forcing clear-only frame") != null)
    {
        ledger.noteForceClear();
    }

    // Any line carrying a refresh counter is a reading. The presenter writes
    // `refresh_attempt_count=` on its status lines and `refresh_attempts=` on
    // its bootstrap snapshot, and both are the same fact.
    const attempts = parseDecimalAfter(message, "refresh_attempt_count=") orelse
        parseDecimalAfter(message, "refresh_attempts=") orelse return;
    const successes = parseDecimalAfter(message, "refresh_success_count=") orelse
        parseDecimalAfter(message, "refresh_successes=") orelse 0;

    var reading = gpu.guest_output_mailbox.Observation{
        .refresh_attempts = attempts,
        .refresh_successes = successes,
        .step = self.executed_steps,
    };
    // A mailbox number is not, by itself, proof that the presenter held a
    // guest image. During bootstrap `ConsumeGuestOutput` logs the internally
    // acquired slot even though it has no ready guest frame:
    // `bootstrap-inactive ... mailbox=0`. Treating that bookkeeping slot as
    // output promoted the observed run to `guest-output-delivered` while every
    // authoritative source said refreshes and guest frames were zero.
    //
    // Only active-output lines can promote the high-water mailbox witness. A
    // missing mailbox on those lines still means no slot; a generic status
    // line with a positive number remains a status reading, not delivery.
    const authoritative_mailbox =
        std.mem.indexOf(u8, message, "Guest output consumed:") != null or
        std.mem.indexOf(u8, message, "Guest output refreshed:") != null or
        std.mem.indexOf(u8, message, "guest_output_image=YES") != null;
    reading.mailbox_index = if (authoritative_mailbox)
        parseSignedDecimalAfter(message, "mailbox=") orelse -1
    else
        -1;
    if (parseDecimalAfter(message, "acquired=")) |value| reading.mailbox_acquired = value;
    if (parseDecimalAfter(message, "ready=")) |value| reading.mailbox_ready = value;
    if (parseDecimalAfter(message, "writable=")) |value| reading.mailbox_writable = value;
    if (fieldOffset(message, "frontbuffer=0x")) |at| {
        const rest = message[at + "frontbuffer=0x".len ..];
        const end = std.mem.indexOfNone(u8, rest, "0123456789abcdefABCDEF") orelse rest.len;
        if (end != 0) {
            reading.frontbuffer = std.fmt.parseInt(u64, rest[0..end], 16) catch 0;
        }
    }
    if (fieldOffset(message, "reason=")) |at| {
        const rest = message[at + "reason=".len ..];
        const end = std.mem.indexOfAny(u8, rest, ", )\t\n") orelse rest.len;
        reading.reason = gpu.guest_output_mailbox.reasonOf(rest[0..end]);
    }
    ledger.observe(reading);
}

fn parseDecimalAfter(message: []const u8, key: []const u8) ?u64 {
    const at = fieldOffset(message, key) orelse return null;
    const rest = message[at + key.len ..];
    const end = std.mem.indexOfNone(u8, rest, "0123456789") orelse rest.len;
    if (end == 0) return null;
    return std.fmt.parseInt(u64, rest[0..end], 10) catch null;
}

fn parseSignedDecimalAfter(message: []const u8, key: []const u8) ?i64 {
    const at = fieldOffset(message, key) orelse return null;
    const rest = message[at + key.len ..];
    var end: usize = 0;
    if (end < rest.len and (rest[end] == '-' or rest[end] == '+')) end += 1;
    const digits = end;
    while (end < rest.len and std.ascii.isDigit(rest[end])) : (end += 1) {}
    if (end == digits) return null;
    return std.fmt.parseInt(i64, rest[0..end], 10) catch null;
}

/// The emulator naming the host format it settled on for a guest format.
///
/// Read from its own breadcrumb rather than inferred, because the choice is
/// the emulator's to make and Rosette must record what it actually did rather
/// than what the substitution ladder would have done. What Rosette contributes
/// is the other half: whether the host really lacked the preferred format, and
/// what it does have instead.
fn observeTextureFormatFallback(self: anytype, message: []const u8) void {
    const texture = @import("gpu").texture_format_support;
    // "Format k_2_10_10_10 (signed) is supported via a fallback format (using
    // the Vulkan format 64 instead of the preferred 65)"
    if (std.mem.indexOf(u8, message, "is supported via a fallback format") == null) return;
    const chosen = parseTrailingNumber(message, "using the Vulkan format ") orelse return;
    const signedness: texture.Signedness =
        if (std.mem.indexOf(u8, message, "(signed)") != null) .signed else .unsigned;
    // Longest label first: `k_2_10_10_10` is a prefix of
    // `k_2_10_10_10_AS_16_16_16_16`, and matching the short one first would
    // attribute every fallback to the wrong format.
    const formats = [_]texture.TextureFormat{
        .k_2_10_10_10_as_16_16_16_16,
        .k_2_10_10_10,
        .k_16_16_16_16,
    };
    const loader = parseTextureLoader(message);
    for (formats) |format| {
        if (std.mem.indexOf(u8, message, format.label()) == null) continue;
        self.texture_formats.noteEmulatorChoiceWithLoader(
            format,
            signedness,
            chosen,
            loader,
            self.executed_steps,
        );
        return;
    }
}

/// Parse only the loader vocabulary owned by the texture-format contract.
///
/// A generic fallback breadcrumb is useful evidence that the emulator chose a
/// different host format, but it does not prove that the bytes were converted.
/// Leaving an absent or unfamiliar marker as `unknown` keeps the strict gate
/// closed until the producer publishes that proof.
fn parseTextureLoader(message: []const u8) @import("gpu").texture_format_support.LoaderMode {
    const texture = @import("gpu").texture_format_support;
    if (std.mem.indexOf(u8, message, "loader=signed-widening") != null)
        return .signed_widening;
    if (std.mem.indexOf(u8, message, "loader=signed-float") != null)
        return .signed_float;
    if (std.mem.indexOf(u8, message, "loader=native-signed") != null)
        return .native_signed;
    if (std.mem.indexOf(u8, message, "loader=native-unsigned") != null)
        return .native_unsigned;
    return texture.LoaderMode.unknown;
}

fn parseTrailingNumber(message: []const u8, prefix: []const u8) ?u32 {
    const start = std.mem.indexOf(u8, message, prefix) orelse return null;
    var index = start + prefix.len;
    var value: u32 = 0;
    var digits: usize = 0;
    while (index < message.len and message[index] >= '0' and message[index] <= '9') : (index += 1) {
        value = std.math.mul(u32, value, 10) catch return null;
        value = std.math.add(u32, value, message[index] - '0') catch return null;
        digits += 1;
    }
    return if (digits == 0) null else value;
}

pub fn observeGpuBootstrapGuestLog(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_bootstrap")) return;
    // Feed the strict VdSwap ledger from provenance-bearing breadcrumbs before
    // the broad bootstrap ladder is updated.  The two ledgers answer different
    // questions: bootstrap says where graphics stopped, while this observer
    // distinguishes a guest encoder, a retained ring packet and authentic CP
    // consumption.  A generic PM4 line must never close the XE_SWAP stage.
    if (comptime @hasField(State, "gpu_vd_swap_contract")) {
        _ = self.gpu_vd_swap_contract.observeLogLine(message, self.executed_steps);
    }
    if (comptime @hasField(State, "texture_formats")) {
        observeTextureFormatFallback(self, message);
    }
    const steps = [_]struct { marker: []const u8, step: gpu.Step, export_call: bool = false }{
        .{ .marker = "VdInitializeEngines", .step = .initialize_engines, .export_call = true },
        .{ .marker = "VdGetSystemCommandBuffer", .step = .system_command_buffer, .export_call = true },
        .{ .marker = "VdSetGraphicsInterruptCallback", .step = .graphics_interrupt_callback, .export_call = true },
        .{ .marker = "GPU callback dispatch completed", .step = .graphics_interrupt_dispatch },
        .{ .marker = "VdInitializeRingBuffer", .step = .ring_buffer, .export_call = true },
        .{ .marker = "VdEnableRingBufferRPtrWriteBack", .step = .rptr_writeback, .export_call = true },
        .{ .marker = "RING BUFFER: authentic payload prepared", .step = .ring_payload_prepared },
        .{ .marker = "RING BUFFER: first authentic PM4 packet consumed", .step = .pm4_packet_consumed },
        // Current Xenia emits one provenance-bearing milestone after the
        // command processor has consumed a guest-published batch. This is
        // stronger evidence than the legacy wording: consumption proves the
        // payload existed and that its write pointer was published, and
        // `observeEvidence` closes those preceding transitions without
        // synthesising any guest action.
        .{ .marker = "PM4 AUTHENTIC MILESTONE: first guest-published command batch consumed", .step = .pm4_packet_consumed },
        // This is the first provenance-bearing point that closes the final
        // bootstrap transition. VdSwap entry and packet encoding are tracked
        // separately below; neither implies that the guest published it.
        .{ .marker = "PM4 AUTHENTIC MILESTONE: first guest-published PM4_XE_SWAP consumed", .step = .swap },
    };
    // The write pointer is observed separately because a write to the register
    // is not an advance of it. The guest may store the value it already holds,
    // which publishes nothing, and counting that as a submission moves the
    // bootstrap frontier past a producer that never produced.
    observeRingWritePointer(self, message);
    observeGuestCriticalSection(self, message);
    observeBootstrapCallsiteProbe(self, message);
    observeGuestOutputMailbox(self, message);
    if (std.mem.indexOf(u8, message, "VDSWAP PATH: stage=packet_encoded") != null) {
        self.guest_vdswap_packet_encoded = true;
    }
    if (std.mem.indexOf(u8, message, "VDSWAP PATH: stage=completed") != null) {
        self.guest_vdswap_entry_completed = true;
    }
    for (steps) |candidate| {
        if (candidate.step == .graphics_interrupt_dispatch) {
            // Rosette's host callback is intentionally delivered through
            // Xenia's normal dispatcher, so its completion breadcrumb has
            // the same wording as a title callback. Only a source-aware
            // PowerPC event may advance the guest bootstrap frontier.
            if (interruptCallbackLogDomain(self, message) != .powerpc) continue;
        }
        if (candidate.step == .swap) {
            if (comptime @hasField(State, "gpu_vd_swap_contract")) {
                if (!self.gpu_vd_swap_contract.observed(.authentic_xe_swap_consumed)) {
                    // The strict ledger is authoritative for the final
                    // bootstrap step. A generic PM4 line or a decoder mention
                    // must not make the bootstrap claim authentic XE_SWAP
                    // consumed.
                    continue;
                }
            }
        }
        // The export-verification lines name these symbols without calling
        // them, so a bare occurrence is not evidence. Only the call-trace form
        // `Name(` counts.
        var buffer: [96]u8 = undefined;
        const marker = if (candidate.export_call)
            std.fmt.bufPrint(&buffer, "{s}(", .{candidate.marker}) catch continue
        else
            candidate.marker;
        if (std.mem.indexOf(u8, message, marker) == null) continue;
        const before = self.gpu_bootstrap.frontier();
        self.gpu_bootstrap.observeEvidence(candidate.step, self.executed_steps);
        if (comptime @hasField(State, "gpu_bootstrap_provenance")) {
            self.gpu_bootstrap_provenance.observeGuest(candidate.step, self.executed_steps);
        }
        const after = self.gpu_bootstrap.frontier();
        if (before.step != after.step) {
            machoCapturePrint(
                "macho-processor: gpu bootstrap: {s} observed; frontier moved to {s} (reached={d}/{d})\n",
                .{
                    candidate.step.label(),
                    if (after.step) |next| next.label() else "<complete>",
                    after.reached,
                    gpu.bootstrap.required_step_count,
                },
            );
        }
    }
    observeRingBufferAddress(self, message);
}

/// Retain the call-site probe beside, rather than above, execution evidence.
///
/// The probe is useful for explaining why a static/callsite search missed a
/// real export call, but it is not an execution authority. In the current
/// capture `entry_bctrl_hits=2` and `entry_value_ref_hits=11` coexist with the
/// concrete `VdInitializeEngines` call; the correct conclusion is
/// "callsite probe blind", not "initialization never ran".
fn observeBootstrapCallsiteProbe(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_bootstrap_provenance")) return;

    // A callsite probe is a diagnostic search over the guest module, not an
    // execution authority. Keep every GPU bootstrap export that Xenia reports
    // in the same provenance ledger so a blind probe is attributable to the
    // correct milestone instead of looking like a missing call. In
    // particular, VdSetGraphicsInterruptCallback is the route-opening event
    // in the current run and used to be the one probe that was silently
    // discarded here.
    const Probe = struct { marker: []const u8, step: gpu.Step };
    const probes = [_]Probe{
        .{ .marker = "callsite probe ordinal=0x1B6 name=VdEnableRingBufferRPtrWriteBack", .step = .rptr_writeback },
        .{ .marker = "callsite probe ordinal=0x1C2 name=VdInitializeEngines", .step = .initialize_engines },
        .{ .marker = "callsite probe ordinal=0x1C3 name=VdInitializeRingBuffer", .step = .ring_buffer },
        .{ .marker = "callsite probe ordinal=0x1D5 name=VdSetGraphicsInterruptCallback", .step = .graphics_interrupt_callback },
    };
    var matched_step: ?gpu.Step = null;
    for (probes) |probe| {
        if (std.mem.indexOf(u8, message, probe.marker) != null) {
            matched_step = probe.step;
            break;
        }
    }
    const step = matched_step orelse return;

    const pc_hit = parseFlagAfter(message, "pc_hit=") orelse return;
    const lr_hit = parseFlagAfter(message, "lr_hit=") orelse return;
    const ctr_hit = parseFlagAfter(message, "ctr_hit=") orelse return;
    const branch_probe = parseFlagAfter(message, "current_branch_targets_probe=") orelse return;
    self.gpu_bootstrap_provenance.observeCallsite(
        step,
        self.executed_steps,
        pc_hit,
        lr_hit,
        ctr_hit,
        branch_probe,
        parseDecimalAfter(message, "near_direct_bl_hits=") orelse 0,
        parseDecimalAfter(message, "entry_bctrl_hits=") orelse 0,
        parseDecimalAfter(message, "near_value_ref_hits=") orelse 0,
        parseDecimalAfter(message, "entry_value_ref_hits=") orelse 0,
    );
}

pub fn observeXeniaGpuHandoffGuestLog(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "xenia_gpu_handoff")) return;
    const observation = self.xenia_gpu_handoff.observeLine(message, self.executed_steps) orelse return;
    if (!observation.advanced) return;
    if (comptime @hasDecl(@TypeOf(self.*), "noteReadyCompilerGpuPhase")) {
        self.noteReadyCompilerGpuPhase(@intFromEnum(observation.current), self.executed_steps);
    }
    machoCapturePrint(
        "macho-processor: Xenia GPU handoff advanced: {s} -> {s} at step={d}\n",
        .{ @tagName(observation.previous), @tagName(observation.current), self.executed_steps },
    );
}

/// Feed the causal GPU observer from Xenia's own structured breadcrumbs.  The
/// observer is intentionally separate from the older handoff ledger: its
/// first-draw stage and bounded wait/signal tail answer why a title can submit
/// PM4 state and still never reach VdSwap.
pub fn observeXeniaGpuCausalTraceGuestLog(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "xenia_gpu_causal_trace")) return;
    _ = xenia_gpu_causal_trace;
    const before = self.xenia_gpu_causal_trace.total_events;
    _ = self.xenia_gpu_causal_trace.observeLine(message, self.executed_steps);
    if (comptime @hasField(State, "audit_journal")) {
        var sequence = before + 1;
        while (sequence <= self.xenia_gpu_causal_trace.total_events) : (sequence += 1) {
            const event = self.xenia_gpu_causal_trace.eventForSequence(sequence) orelse continue;
            journalXeniaCausalEvent(self, event);
        }
    }
}

fn ensureAuditJournal(self: anytype) bool {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "audit_journal")) return false;
    if (self.audit_journal.run_id == 0) {
        var run_id: u64 = 1;
        if (comptime @hasField(State, "event_stream")) {
            if (self.event_stream.run_id != 0) run_id = self.event_stream.run_id;
        }
        self.audit_journal.open(run_id);
    }
    if (self.audit_journal.written == 0) {
        _ = writeStructuredJournal(self, .{
            .kind = @intFromEnum(run_journal.EventKind.run_started),
            .domain = @intFromEnum(run_journal.Domain.rosette_run_integrity),
            .source_class = @intFromEnum(run_journal.SourceClass.host_forwarded),
            .result_class = @intFromEnum(run_journal.ResultClass.observed),
            .guest_step = self.executed_steps,
        });
    }
    return true;
}

fn writeStructuredJournal(self: anytype, record: run_journal.Record) bool {
    const State = @TypeOf(self.*);
    if (comptime @hasDecl(State, "writeAuditJournal")) {
        return self.writeAuditJournal(record);
    }
    if (comptime @hasField(State, "audit_journal")) {
        return self.audit_journal.write(record);
    }
    return false;
}

fn writeStructuredJournalCompacted(self: anytype, record: run_journal.Record) bool {
    const State = @TypeOf(self.*);
    if (comptime @hasDecl(State, "writeCompactedAuditJournal")) {
        return self.writeCompactedAuditJournal(record);
    }
    if (comptime @hasField(State, "audit_journal")) {
        return self.audit_journal.writeCompacted(record);
    }
    return false;
}

fn causalJournalKind(event: xenia_gpu_causal_trace.Event) run_journal.EventKind {
    return switch (event.kind) {
        .ring_payload, .ring_write_pointer => .ring_stage,
        .pm4_packet, .indirect_buffer => .pm4_packet,
        .draw => .draw,
        .swap => .swap_request,
        .wait => .wait_result,
        .signal => .signal,
        .scheduler => .wait_enter,
        .module_initialization, .kernel_export => .producer_epoch,
        .unproven_handoff => .frame_custody,
        .stage => if (event.stage) |stage| switch (stage) {
            .ring_payload_prepared, .ring_write_pointer_published => .ring_stage,
            .pm4_packet_consumed, .pm4_state_programmed => .pm4_packet,
            .first_draw_submitted, .first_draw_consumed => .draw,
            .frontbuffer_selected,
            .guest_vdswap_entered,
            .swap_packet_encoded,
            .guest_vdswap_completed,
            .swap_published,
            .authentic_swap_consumed,
            => .swap_request,
            .issue_swap, .output_refresh, .native_presented => .frame_custody,
        } else .producer_epoch,
    };
}

fn causalJournalDomain(event: xenia_gpu_causal_trace.Event) run_journal.Domain {
    return switch (event.kind) {
        .wait, .signal, .kernel_export => .xenia_kernel,
        .ring_payload, .ring_write_pointer, .pm4_packet, .draw, .indirect_buffer => .xenia_command_processor,
        .swap => .guest_title,
        .module_initialization => .guest_title,
        .scheduler => .rosette_scheduler,
        .unproven_handoff => .xenia_presenter,
        .stage => if (event.stage) |stage| switch (stage) {
            .ring_payload_prepared,
            .ring_write_pointer_published,
            .first_draw_submitted,
            .guest_vdswap_entered,
            .swap_packet_encoded,
            .guest_vdswap_completed,
            .swap_published,
            => .guest_title,
            .output_refresh, .native_presented => .xenia_presenter,
            else => .xenia_command_processor,
        } else .xenia_command_processor,
    };
}

fn journalXeniaCausalEvent(self: anytype, event: xenia_gpu_causal_trace.Event) void {
    if (!ensureAuditJournal(self)) return;
    const guest_owned = event.authentic or event.kind == .wait or event.kind == .signal or
        event.kind == .module_initialization or event.kind == .kernel_export;
    const journal_kind = causalJournalKind(event);
    const record = run_journal.Record{
        .kind = @intFromEnum(journal_kind),
        .domain = @intFromEnum(causalJournalDomain(event)),
        .source_class = @intFromEnum(if (guest_owned)
            run_journal.SourceClass.guest_authentic
        else
            run_journal.SourceClass.host_forwarded),
        .result_class = @intFromEnum(if (event.kind == .signal)
            run_journal.ResultClass.applied
        else
            run_journal.ResultClass.observed),
        .reason = if (event.stage) |stage| @intFromEnum(stage) + 1 else event.opcode orelse 0,
        .guest_step = event.step,
        .guest_thread = event.thread,
        .location = .{ .guest_pc = @truncate(event.program_counter) },
        .subject_id = event.object,
        // The causal-trace sequence identifies this occurrence; it is not an
        // object generation.  The journal assigns its own gapless sequence,
        // while wait/signal repetition is retained by an exact semantic
        // aggregate.  Copying the occurrence sequence here made every repeat
        // look like a distinct object generation and defeated that aggregate.
        .generation = 0,
        .expected_value = event.secondary,
        .actual_value = event.value,
    };
    _ = if (journal_kind == .wait_result or journal_kind == .signal)
        writeStructuredJournalCompacted(self, record)
    else
        writeStructuredJournal(self, record);
}

/// One candidate writer found by sweeping the lock's aliases, with enough
/// context to say which view of the page the store used. The fields are copied
/// out of the provenance entry so this file does not need to name the tracker's
/// entry type.
const CsWriter = struct {
    address: u64,
    previous_value: u64,
    value: u64,
    instruction_address: u64,
    step: u64,
    thread: u64,
    kind_name: []const u8,
    alias: []const u8,
    generation: []const u8,
};

fn csWriterFromEntry(entry: anytype, alias: []const u8, generation: []const u8) CsWriter {
    return .{
        .address = entry.address,
        .previous_value = entry.previous_value,
        .value = entry.value,
        .instruction_address = entry.instruction_address,
        .step = entry.step,
        .thread = entry.thread,
        .kind_name = @tagName(entry.kind),
        .alias = alias,
        .generation = generation,
    };
}

const AliasLockRead = struct {
    host: u64,
    lock_dword: u32 = 0,
    readable: bool = false,
};

/// Read the lock-count dword (i32, little-endian, at offset 16) through one
/// host alias. Each of Xenia's three macOS views can hold a different value
/// for the same guest lock, and that disagreement is itself the finding.
fn readCriticalSectionLock(self: anytype, host: u64) AliasLockRead {
    if (host == 0) return .{ .host = host };
    const bytes = self.guestMemoryConst(host + guest_critical_section.lock_count_offset, 4) orelse
        return .{ .host = host };
    return .{
        .host = host,
        .lock_dword = @bitCast(std.mem.readInt(i32, bytes[0..4], .little)),
        .readable = true,
    };
}

fn formatLockDword(read: AliasLockRead, buffer: []u8) []const u8 {
    if (!read.readable) return "unreadable";
    return std.fmt.bufPrint(buffer, "0x{x:0>8}", .{read.lock_dword}) catch "unreadable";
}

/// Find the most recent provenance entry touching the lock across every alias
/// the fork can use, both writer generations, and every 8-byte slot the
/// 28-byte structure overlaps. A single-alias lookup was the original gap:
/// the -1 initializer landed on the biased `TranslateVirtual` page while the
/// zeroing store used the unbiased `virtual_membase_ + address` page, and
/// nobody looked there. The sweep makes an escaped store impossible to miss
/// unless it never committed provenance at all — which is what the caller
/// reports as NOT_RETAINED with the watch truth attached.
fn sweepCriticalSectionWriter(
    self: anytype,
    host_virtual: u64,
    host_physical: u64,
    host_unbiased: u64,
) ?CsWriter {
    var best: ?CsWriter = null;
    const aliases = [_]struct { label: []const u8, host: u64 }{
        .{ .label = "virtual", .host = host_virtual },
        .{ .label = "physical", .host = host_physical },
        .{ .label = "unbiased", .host = host_unbiased },
    };
    const slots = [_]u64{ 0, 8, 16, 24 };
    for (aliases) |alias| {
        if (alias.host == 0) continue;
        for (slots) |slot| {
            const address = alias.host + slot;
            if (self.memory_writes.lookup(address)) |entry| {
                const candidate = csWriterFromEntry(entry, alias.label, "current");
                if (best == null or candidate.step > best.?.step) best = candidate;
            }
            if (self.memory_writes.lookupPrevious(address)) |entry| {
                const candidate = csWriterFromEntry(entry, alias.label, "previous");
                if (best == null or candidate.step > best.?.step) best = candidate;
            }
        }
    }
    return best;
}

/// State the coverage honestly when a sweep finds nothing, so NOT_RETAINED is
/// never a dead end: the reader needs to know whether the page was never
/// watched (a watch-set capacity problem), was watched and silently missed the
/// store (a write path that bypasses provenance), or was watched and truly has
/// no store (a field that was never written at all).
fn reportCriticalSectionWatchTruth(
    self: anytype,
    address: u64,
    host_virtual: u64,
    host_physical: u64,
    host_unbiased: u64,
) void {
    machoCapturePrint(
        "macho-processor: guest critical section watch truth: cs=0x{x} watch_virtual={s} watch_physical={s} watch_unbiased={s} watch(entries={d}/{d} overflows={d} recorded_stores={d} rejected_stores={d}) provenance(slots={d} dropped={d}) globally_armed={s}; if every alias is watched and still nothing is retained, the store bypassed writeMemVal entirely; if an alias is unwatched, that is the page the store used\n",
        .{
            address,
            if (host_virtual != 0 and self.provenance_watch.covers(host_virtual)) "YES" else "NO",
            if (host_physical != 0 and self.provenance_watch.covers(host_physical)) "YES" else "NO",
            if (host_unbiased != 0 and self.provenance_watch.covers(host_unbiased)) "YES" else "NO",
            self.provenance_watch.count,
            self.provenance_watch.entries.len,
            self.provenance_watch.overflows,
            self.provenance_watch.recorded,
            self.provenance_watch.rejected,
            self.memory_writes.entries.count(),
            self.memory_writes.dropped_slots,
            if (self.write_diagnostics_armed) "YES" else "NO",
        },
    );
}

/// Read the critical section the guest says it is contending, when the guest
/// names nobody as its owner.
///
/// `owner=00000000` on a contention is self-contradictory — no thread has id
/// zero — so the waiter is parked for a release that cannot arrive. The
/// transition log cannot say why, because it records what the guest concluded
/// rather than what the memory holds, and the two diverge in exactly the case
/// that matters: on this ABI a free lock holds -1, so a structure that reads
/// zero is not free, it is held by nobody. `lock=0->1` therefore describes a
/// lock nothing ever initialised, and looks identical to an ordinary
/// acquisition.
///
/// Rosette can settle it, because Rosette can read the bytes. It arms a write
/// watch when the guest registers the lock and dumps the structure when the
/// impossible contention appears; the two together separate "the initialiser
/// never ran" from "the initialiser wrote somewhere the waiter does not read".
/// Nothing is repaired: writing -1 into a lock the guest believes it holds
/// would trade a visible hang for a silent double-entry.
fn observeGuestCriticalSection(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "critical_section_watch_base")) return;

    if (std.mem.indexOf(u8, message, "GPU CRITICAL SECTION: registered cs=") != null) {
        const address = parseHexAfter(message, "registered cs=") orelse return;
        if (address == 0 or self.critical_section_watch_base == address) return;
        self.critical_section_watch_base = address;
        self.critical_section_initial_valid = false;

        // Xenia's macOS port exposes the same guest page through three host
        // aliases that live on three DIFFERENT host pages: `TranslateVirtual`
        // (the 4 KiB E000-heap bias), `TranslatePhysical`, and raw
        // `virtual_membase_ + address` (no bias). The guest's own inline lock
        // code uses the last form, so a watch armed only on the first two
        // loses exactly the stores that matter. All three are armed and
        // reported so a store can never again land on an unwatched page.
        const host_virtual = self.xenia_memory_views.virtualHostAddress(address) orelse 0;
        const host_physical = self.xenia_memory_views.physicalAliasHostAddress(address) orelse 0;
        const host_unbiased = self.xenia_memory_views.primaryUnbiasedHostAddress(address) orelse 0;
        self.critical_section_watch_host_virtual = host_virtual;
        self.critical_section_watch_host_physical = host_physical;
        self.critical_section_watch_host_unbiased = host_unbiased;
        const virtual_armed = host_virtual != 0 and self.provenance_watch.watchPage(host_virtual, .declared);
        const physical_armed = host_physical != 0 and self.provenance_watch.watchPage(host_physical, .declared);
        const unbiased_armed = host_unbiased != 0 and self.provenance_watch.watchPage(host_unbiased, .declared);

        if (host_virtual != 0) {
            if (self.guestMemoryConst(host_virtual, guest_critical_section.size_bytes)) |bytes| {
                @memcpy(self.critical_section_initial_image[0..], bytes[0..guest_critical_section.size_bytes]);
                self.critical_section_initial_valid = true;
            }
        }
        const initial_fields = if (self.critical_section_initial_valid)
            guest_critical_section.decode(&self.critical_section_initial_image)
        else
            null;
        machoCapturePrint(
            "macho-processor: guest critical section aliases resolved: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} host_unbiased=0x{x} watch_virtual={s} watch_physical={s} watch_unbiased={s} initial_read={s} initial_state={s}; later clearing is attributed at the address Xenia actually writes; if the views disagree the fork is reading a different alias than it initialised\n",
            .{
                address,
                host_virtual,
                host_physical,
                host_unbiased,
                if (virtual_armed or (host_virtual != 0 and self.provenance_watch.covers(host_virtual))) "armed" else "unavailable",
                if (physical_armed or (host_physical != 0 and self.provenance_watch.covers(host_physical))) "armed" else "unavailable",
                if (unbiased_armed or (host_unbiased != 0 and self.provenance_watch.covers(host_unbiased))) "armed" else "unavailable",
                if (self.critical_section_initial_valid) "YES" else "NO",
                if (initial_fields) |fields| guest_critical_section.classify(fields).label() else "unreadable",
            },
        );
        return;
    }

    // Xenia emits this checkpoint synchronously before the bounded integrity
    // repair writes a single byte. Read provenance here: waiting for the later
    // contention would never work once the repair succeeds, and reading after
    // repair would attribute the repair rather than the casualty.
    if (std.mem.indexOf(u8, message, "GPU CRITICAL SECTION INTEGRITY: exact-zero casualty detected") != null) {
        const address = parseHexAfter(message, "cs=") orelse return;
        const known = address == self.critical_section_watch_base;
        const host_virtual = if (known)
            self.critical_section_watch_host_virtual
        else
            self.xenia_memory_views.virtualHostAddress(address) orelse 0;
        const host_physical = if (known)
            self.critical_section_watch_host_physical
        else
            self.xenia_memory_views.physicalAliasHostAddress(address) orelse 0;
        const host_unbiased = if (known)
            self.critical_section_watch_host_unbiased
        else
            self.xenia_memory_views.primaryUnbiasedHostAddress(address) orelse 0;

        // Read the lock-count dword through every alias. Xenia's macOS memory
        // model exposes one guest page through three host pages, and the fork
        // has been observed to initialise one alias while the guest's inline
        // lock code spins on another. When that is the story, the aliases
        // disagree here and the disagreement IS the finding: the lock was not
        // cleared, the reader was looking at a different page.
        const virtual_read = readCriticalSectionLock(self, host_virtual);
        const physical_read = readCriticalSectionLock(self, host_physical);
        const unbiased_read = readCriticalSectionLock(self, host_unbiased);
        var virtual_text: [16]u8 = undefined;
        var physical_text: [16]u8 = undefined;
        var unbiased_text: [16]u8 = undefined;
        const virtual_lock = formatLockDword(virtual_read, &virtual_text);
        const physical_lock = formatLockDword(physical_read, &physical_text);
        const unbiased_lock = formatLockDword(unbiased_read, &unbiased_text);

        const writer = sweepCriticalSectionWriter(self, host_virtual, host_physical, host_unbiased);
        if (writer) |found| {
            machoCapturePrint(
                "macho-processor: GUEST CRITICAL SECTION PRE-REPAIR CAUSAL WRITER: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} host_unbiased=0x{x} lock_virtual={s} lock_physical={s} lock_unbiased={s} write_address=0x{x} alias={s} generation={s} previous=0x{x} value=0x{x} rip=0x{x} {s} step={d} thread=0x{x} kind={s}; this write destroyed the captured unlocked lock-count slot; if lock_virtual and lock_unbiased disagree, the zero the guest saw came from reading a different alias than the one Xenia initialised\n",
                .{ address, host_virtual, host_physical, host_unbiased, virtual_lock, physical_lock, unbiased_lock, found.address, found.alias, found.generation, found.previous_value, found.value, found.instruction_address, self.metadata.symbolLabel(found.instruction_address), found.step, found.thread, found.kind_name },
            );
        } else {
            machoCapturePrint(
                "macho-processor: GUEST CRITICAL SECTION PRE-REPAIR CAUSAL WRITER: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} host_unbiased=0x{x} lock_virtual={s} lock_physical={s} lock_unbiased={s} writer=NOT_RETAINED; the exact-zero transition is proven by Xenia, but no store to the lock-count slot was committed under bounded provenance at any alias; lock_virtual != lock_unbiased would mean the guest read a page the fork never initialised\n",
                .{ address, host_virtual, host_physical, host_unbiased, virtual_lock, physical_lock, unbiased_lock },
            );
            reportCriticalSectionWatchTruth(self, address, host_virtual, host_physical, host_unbiased);
        }
        return;
    }

    if (std.mem.indexOf(u8, message, "GPU CRITICAL SECTION: contention") == null) return;
    const owner = parseHexAfter(message, "owner=") orelse return;
    if (owner != 0) return;
    const address = parseHexAfter(message, "cs=") orelse return;
    self.critical_section_zero_owner_reports +|= 1;
    // Reported once: it repeats for as long as the thread stays parked, which
    // is the rest of the run.
    if (self.critical_section_zero_owner_reports != 1) return;

    const critical_section = guest_critical_section;
    const known = address == self.critical_section_watch_base;
    const host_virtual = if (known)
        self.critical_section_watch_host_virtual
    else
        self.xenia_memory_views.virtualHostAddress(address) orelse 0;
    const host_physical = if (known)
        self.critical_section_watch_host_physical
    else
        self.xenia_memory_views.physicalAliasHostAddress(address) orelse 0;
    const host_unbiased = if (known)
        self.critical_section_watch_host_unbiased
    else
        self.xenia_memory_views.primaryUnbiasedHostAddress(address) orelse 0;
    const bytes = if (host_virtual != 0)
        self.guestMemoryConst(host_virtual, critical_section.size_bytes)
    else
        null;
    if (bytes == null) {
        machoCapturePrint(
            "macho-processor: GUEST CRITICAL SECTION UNREADABLE: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} host_unbiased=0x{x} mapping_base=0x{x}; the Xbox address could not be resolved to readable translated backing\n",
            .{ address, host_virtual, host_physical, host_unbiased, self.xenia_memory_views.mapping_base },
        );
        return;
    }
    const fields = critical_section.decode(bytes.?) orelse return;
    const state = critical_section.classify(fields);
    const virtual_read = readCriticalSectionLock(self, host_virtual);
    const physical_read = readCriticalSectionLock(self, host_physical);
    const unbiased_read = readCriticalSectionLock(self, host_unbiased);
    var virtual_text: [16]u8 = undefined;
    var physical_text: [16]u8 = undefined;
    var unbiased_text: [16]u8 = undefined;
    const virtual_lock = formatLockDword(virtual_read, &virtual_text);
    const physical_lock = formatLockDword(physical_read, &physical_text);
    const unbiased_lock = formatLockDword(unbiased_read, &unbiased_text);
    const writer = sweepCriticalSectionWriter(self, host_virtual, host_physical, host_unbiased);
    const ever_written = writer != null;
    const changed_since_registration = self.critical_section_initial_valid and
        !std.mem.eql(u8, &self.critical_section_initial_image, bytes.?[0..critical_section.size_bytes]);
    machoCapturePrint(
        "macho-processor: GUEST CRITICAL SECTION ZERO-OWNER CONTENTION: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} host_unbiased=0x{x} lock_virtual={s} lock_physical={s} lock_unbiased={s} state={s} lock_count={d} recursion={d} owner=0x{x} header(type=0x{x} signal=0x{x} flink=0x{x} blink=0x{x}) initial_valid={s} changed_since_registration={s} writer_retained={s} impossible={s}\n",
        .{
            address,
            host_virtual,
            host_physical,
            host_unbiased,
            virtual_lock,
            physical_lock,
            unbiased_lock,
            state.label(),
            fields.lock_count,
            fields.recursion_count,
            fields.owning_thread,
            fields.type_flags,
            fields.signal_state,
            fields.wait_list_flink,
            fields.wait_list_blink,
            if (self.critical_section_initial_valid) "YES" else "NO",
            if (changed_since_registration) "YES" else "NO",
            if (ever_written) "YES" else "NO",
            if (state.impossible()) "YES" else "NO",
        },
    );
    if (writer) |found| {
        machoCapturePrint(
            "macho-processor: GUEST CRITICAL SECTION LAST WRITER: address=0x{x} alias={s} generation={s} previous=0x{x} value=0x{x} rip=0x{x} {s} step={d} thread=0x{x} kind={s}; this is the producer that changed the lock-count/recursion slot after registration\n",
            .{ found.address, found.alias, found.generation, found.previous_value, found.value, found.instruction_address, self.metadata.symbolLabel(found.instruction_address), found.step, found.thread, found.kind_name },
        );
    } else {
        reportCriticalSectionWatchTruth(self, address, host_virtual, host_physical, host_unbiased);
    }
    machoCapturePrint(
        "macho-processor: GUEST CRITICAL SECTION GUIDANCE: {s}\n",
        .{critical_section.guidance(state, ever_written)},
    );
}

/// Separate a write-pointer *write* from a write-pointer *advance*.
///
/// The observed run reports two guest MMIO writes to `CP_RB_WPTR` and equal
/// read and write pointers. Treating each write as a submission marked the
/// bootstrap's `ring_write_pointer` step reached, moved the frontier to PM4
/// consumption, and sent every subsequent reading of the log downstream — to
/// the command processor, and from there to the presenter. The producer, which
/// is where the stall actually is, was never implicated because the step that
/// would have implicated it had been recorded as done.
///
/// So the value is parsed and compared. The step is observed only when the
/// pointer genuinely moved, or when the ring's own geometry reports an
/// outstanding span; a rewritten value advances nothing and is logged as such.
/// Nothing here is inferred — an unobserved value stays unobserved, because the
/// whole point is to stop the runtime from crediting the guest with a step it
/// did not take.
fn observeRingWritePointer(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_ring_publication")) return;

    if (parseHexAfter(message, "rb_size=")) |size_bytes| {
        // The ring diagnosis line carries the pointers the command processor
        // and the guest actually hold, which is the only place an outstanding
        // span is directly visible.
        const geometry = gpu.RingGeometry{
            .base = parseHexAfter(message, "rb_base=") orelse 0,
            .size_bytes = size_bytes,
            .read_pointer = parseHexAfter(message, "read_ptr=") orelse 0,
            .write_pointer = parseHexAfter(message, "write_ptr=") orelse 0,
        };
        const before = self.gpu_ring_publication.published();
        // A bootstrap-incomplete snapshot reports every field as zero, and it
        // is emitted repeatedly for the rest of the run. Letting it overwrite a
        // real geometry made the outstanding span read as empty forever, which
        // is indistinguishable from a drained ring.
        const informative = geometry.base != 0 or geometry.size_bytes != 0 or
            geometry.read_pointer != 0 or geometry.write_pointer != 0;
        if (informative) self.gpu_ring_publication.observeGeometry(geometry);
        if (!before and self.gpu_ring_publication.published()) {
            machoCapturePrint(
                "macho-processor: gpu ring publication: an outstanding span appeared: rb_base=0x{x} rb_size=0x{x} read_ptr=0x{x} write_ptr=0x{x} span_dwords={d} of {d}\n",
                .{ geometry.base, geometry.size_bytes, geometry.read_pointer, geometry.write_pointer, geometry.spanDwords() orelse 0, geometry.sizeDwords() },
            );
            self.gpu_bootstrap.observe(.ring_write_pointer, self.executed_steps);
        }
    }

    // The emulator's own applied-update counter, which is a different thing
    // from the line below. The line is printed where it *decides* to update; the
    // counter is incremented where it *applies* one. In the observed run the
    // line fired twice and the counter stayed at zero, which means those are
    // different code paths and nothing downstream should trust the line alone.
    if (comptime @hasField(@TypeOf(self.*), "gpu_xenia_wptr_updates")) {
        if (std.mem.indexOf(u8, message, "wptr_updates(total=") != null) {
            if (parseDecimalAfter(message, "wptr_updates(total=")) |total| {
                self.gpu_xenia_wptr_updates = @max(self.gpu_xenia_wptr_updates, total);
                self.gpu_xenia_wptr_counter_seen = true;
            }
        }
    }

    // The diagnostic register line below proves a source write. These two
    // Xenia lines prove the later transport stages with exact old/new values,
    // so retain them separately and join by value rather than by proximity.
    if (std.mem.indexOf(u8, message, "RING BUFFER: WPTR advanced old=") != null) {
        const previous = parseHexAfter(message, "old=") orelse 0;
        const value = parseHexAfter(message, "new=") orelse 0;
        const producer = parseProducerContext(message);
        if (value != 0 or previous != 0) {
            _ = self.gpu_ring_publication.observeAppliedWithContext(
                previous,
                value,
                std.mem.indexOf(u8, message, "signaled_worker=YES") != null,
                self.executed_steps,
                producer orelse .{},
            );
        }
    }
    if (std.mem.indexOf(u8, message, "DEBUG: GPU activity: processed ") != null) {
        const dwords = parseDecimalAfterU32(message, "processed ") orelse 0;
        const read_before = parseHexAfter(message, "dwords (read ") orelse 0;
        const read_after = parseHexAfter(message, " -> ") orelse 0;
        const write_value = parseHexAfter(message, ", write ") orelse 0;
        _ = self.gpu_ring_publication.observeConsumption(
            read_before,
            read_after,
            write_value,
            dwords,
            self.executed_steps,
        );
    } else if (std.mem.indexOf(u8, message, "PM4 AUTHENTIC MILESTONE: first guest-published command batch consumed") != null) {
        const dwords = parseDecimalAfterU32(message, "dwords=") orelse 0;
        const read_before = parseHexAfter(message, "read=") orelse 0;
        const read_after = parseHexAfter(message, "->") orelse 0;
        const write_value = parseHexAfter(message, "write=") orelse 0;
        _ = self.gpu_ring_publication.observeConsumption(
            read_before,
            read_after,
            write_value,
            dwords,
            self.executed_steps,
        );
    }

    const marker = "DEBUG: REGISTER WRITE: CP_RB_WPTR";
    if (std.mem.indexOf(u8, message, marker) == null) return;
    const value = parseHexAfter(message, "CP_RB_WPTR = ") orelse
        parseHexAfter(message, "CP_RB_WPTR=") orelse return;
    const previous = self.gpu_ring_publication.referenceValue();
    const outcome = self.gpu_ring_publication.observeWritePointerAt(value, self.executed_steps);
    const tracker = &self.gpu_ring_publication;
    machoCapturePrint(
        "macho-processor: gpu ring write pointer: old={s}0x{x} new=0x{x} outcome={s} writes={d} advances={d} repeats={d} span={s} published={s}\n",
        .{
            if (previous == null) "unobserved:" else "",
            previous orelse 0,
            value,
            @tagName(outcome),
            tracker.writes,
            tracker.advances,
            tracker.repeats,
            @tagName(tracker.span()),
            if (tracker.published()) "YES" else "NO",
        },
    );
    if (outcome == .advanced) {
        self.gpu_bootstrap.observe(.ring_write_pointer, self.executed_steps);
        if (comptime @hasField(@TypeOf(self.*), "gpu_vd_swap_contract")) {
            self.gpu_vd_swap_contract.observePublication(self.executed_steps, .guest_publication);
        }
        return;
    }
    if (outcome == .repeated and tracker.repeats == 1) {
        machoCapturePrint(
            "macho-processor: gpu ring publication: {s}\n",
            .{tracker.verdict()},
        );
    }
}

/// Parse provenance attached to Xenia's actual write-pointer application
/// breadcrumb. The CP worker can print the old/new values, but it is not the
/// guest producer; only an explicitly marked context is accepted here.
fn parseProducerContext(message: []const u8) ?gpu.ring_publication.ProducerContext {
    if (!(parseFlagAfter(message, "guest_context=") orelse false)) return null;
    const guest_thread = parseHex64After(message, "guest_thread=") orelse return null;
    const guest_pc = parseHex64After(message, "guest_pc=") orelse return null;
    const guest_lr = parseHex64After(message, "guest_lr=") orelse 0;
    if (guest_thread == 0 or guest_pc == 0) return null;
    return .{
        .valid = true,
        .guest_thread = guest_thread,
        .guest_pc = guest_pc,
        .guest_lr = guest_lr,
        .publication_epoch = parseDecimalAfter(message, "publication_epoch=") orelse 0,
        .ring_base = parseHex64After(message, "ring_base=") orelse 0,
        .ring_size_bytes = parseHex64After(message, "ring_size=") orelse 0,
        .span_dwords = parseDecimalAfterU32(message, "span_dwords=") orelse 0,
    };
}

/// A hex field the emulator prints at a fixed width, refused when it is short.
///
/// The emulator's logging is not line-atomic under this runtime, so lines
/// splice: `obj_ptr=D001EC14` arrives as `obj_ptr=D001EC`, `obj_ptr=D001E0`, or
/// even `obj_ptr=D`. Parsed leniently, each truncation becomes a *different*
/// object address, and the predictors then report phantom objects nobody can
/// find — the observed run produced `0xd001ec` and `0xd001e0` alongside the
/// real `0xd001ec14` and gave all three their own recurrence counters.
///
/// The emulator formats these with an eight-digit specifier, so a shorter token
/// is a truncated read by definition. That is a precise rule rather than a
/// heuristic, which is why the field width is the thing checked.
fn parseFixedWidthHexAfter(line: []const u8, marker: []const u8, width: usize) ?u32 {
    const index = std.mem.indexOf(u8, line, marker) orelse return null;
    var text = line[index + marker.len ..];
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) text = text[2..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length != width) return null;
    return std.fmt.parseInt(u32, text[0..width], 16) catch null;
}

/// Width of the object-pointer fields in the emulator's synchronisation logging.
const sync_object_field_width: usize = 8;

/// A hex value of any width, up to 64 bits. Used for host addresses the
/// emulator prints untruncated, which the 32-bit reader would silently mangle.
fn parseHex64After(line: []const u8, marker: []const u8) ?u64 {
    const index = std.mem.indexOf(u8, line, marker) orelse return null;
    var text = line[index + marker.len ..];
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) text = text[2..];
    var length: usize = 0;
    while (length < text.len and length < 16 and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u64, text[0..length], 16) catch null;
}

fn parseHexAfter(line: []const u8, marker: []const u8) ?u32 {
    const index = std.mem.indexOf(u8, line, marker) orelse return null;
    var text = line[index + marker.len ..];
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) text = text[2..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u32, text[0..length], 16) catch null;
}

/// Learn the ring's physical address from the guest's own call and put it under
/// write provenance.
///
/// The unanswered question is not whether the write pointer advanced — that is
/// already known — but whether the guest ever *wrote a command dword into the
/// ring at all*. Those are different failures: a producer that prepared a packet
/// and did not publish it is a control-flow problem, and one that never wrote is
/// a producer that never ran. Nothing distinguished them, because nobody was
/// watching the memory.
///
/// The address only becomes knowable when the guest names it, which is exactly
/// the case `ownership.watch` exists for. It also settles the alias question:
/// provenance records the address the store actually used, so a write landing in
/// a different physical view of the same page shows up as a write to a different
/// address rather than as no write at all.
fn observeRingBufferAddress(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_ring_watch_base")) return;
    if (self.gpu_ring_watch_base != 0) return;
    const marker = "VdInitializeRingBuffer(";
    const start = std.mem.indexOf(u8, message, marker) orelse return;
    const rest = message[start + marker.len ..];
    const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return;
    const base = std.fmt.parseInt(u64, std.mem.trim(u8, rest[0..comma], " "), 16) catch return;
    if (base == 0) return;

    const tail = rest[comma + 1 ..];
    const close = std.mem.indexOfScalar(u8, tail, ')') orelse tail.len;
    const size_log2 = std.fmt.parseInt(u6, std.mem.trim(u8, tail[0..close], " "), 10) catch 12;
    // Xenia's own contract: size_bytes = 1 << (size_log2 + 3).
    const size: u64 = @as(u64, 1) << (@as(u6, @intCast(@min(@as(u32, size_log2) + 3, 40))));

    self.gpu_ring_watch_base = base;
    self.gpu_ring_watch_size = size;
    self.gpu_ring_watch_host_physical = self.xenia_memory_views.physicalHostAddress(base) orelse 0;
    // The 4 KiB physical view maps physical P at E0000000 + P - 1000.
    const virtual_alias = if (base >= 0x1000) 0xE000_0000 + base - 0x1000 else 0;
    self.gpu_ring_watch_host_virtual = if (virtual_alias != 0)
        self.xenia_memory_views.virtualHostAddress(virtual_alias) orelse 0
    else
        0;
    // Watch the head of the ring: the first packet goes at the base, and the
    // watch set is deliberately small, so covering the whole ring would evict
    // everything else it holds.
    if (self.gpu_ring_watch_host_physical != 0) {
        _ = self.provenance_watch.watchPage(self.gpu_ring_watch_host_physical, .declared);
    }
    if (self.gpu_ring_watch_host_virtual != 0) {
        _ = self.provenance_watch.watchPage(self.gpu_ring_watch_host_virtual, .declared);
    }
    machoCapturePrint(
        "macho-processor: gpu ring watch armed: physical_base=0x{x} size=0x{x} (size_log2={d}) host_physical=0x{x} host_virtual_alias=0x{x}; provenance now watches the addresses the translated stores actually use\n",
        .{ base, size, size_log2, self.gpu_ring_watch_host_physical, self.gpu_ring_watch_host_virtual },
    );
}

pub fn observeXeniaPipelineGuestLog(self: anytype, message: []const u8) void {
    const observation = self.xenia_pipeline.observeLine(message, self.executed_steps) orelse return;
    if (!observation.first_observation) return;
    if (comptime @hasDecl(@TypeOf(self.*), "noteReadyCompilerPipelineStage")) {
        self.noteReadyCompilerPipelineStage(@intFromEnum(observation.stage), observation.step);
    }

    // Reaching a new pipeline stage is the run demonstrably making progress,
    // which is the only evidence that a handler did more than log and abandon.
    if (comptime @hasField(@TypeOf(self.*), "guest_exceptions")) {
        self.guest_exceptions.noteProgress(self.executed_steps);
    }

    const spec = @import("diagnostics").xenia_pipeline_contracts.spec(observation.stage);
    // Structural progress settles every anomaly that came before it: the run
    // did not merely keep executing, it reached a new stage. Without this the
    // ledger ends every run at `unclassified=N` and blocks its own signoff.
    const settled = self.anomalies.notePipelineAdvance(observation.step);
    if (settled != 0) {
        machoCapturePrint(
            "macho-processor: anomaly ledger: {d} anomaly record(s) classified as continued-benign by reaching stage={s} at step={d}; the pipeline advanced past them, so they did not stop it\n",
            .{ settled, @tagName(observation.stage), observation.step },
        );
    }
    machoCapturePrint(
        "macho-processor: Xenia pipeline milestone: stage={s} subsystem={s} step={d} prerequisite_missing={} frontier={s} evidence={s}\n",
        .{
            @tagName(observation.stage),
            @tagName(spec.subsystem),
            observation.step,
            observation.prerequisite_missing,
            if (observation.frontier) |stage| @tagName(stage) else "none",
            spec.description,
        },
    );
    if (self.summary_output_fd < 0) return;
    var buffer: [512]u8 = undefined;
    const line = std.fmt.bufPrint(
        &buffer,
        "step={d} event=xenia_pipeline stage={s} subsystem={s} frontier={s} prerequisite_missing={}\n",
        .{
            observation.step,
            @tagName(observation.stage),
            @tagName(spec.subsystem),
            if (observation.frontier) |stage| @tagName(stage) else "none",
            observation.prerequisite_missing,
        },
    ) catch return;
    _ = hostWriteFdAll(self.summary_output_fd, line);
}

pub fn logProfileHostPreflight(self: anytype, profile_id: []const u8) void {
    self.profile_host_preflight_checks +|= 1;
    const storage_root = self.fs_forwarder.storageRoot();
    if (storage_root.len == 0) {
        machoCapturePrint(
            "macho-processor: profile host preflight #{d}: profile={s} unavailable because no storage root is configured\n",
            .{ self.profile_host_preflight_checks, profile_id },
        );
        return;
    }

    var path_buffer: [4096]u8 = undefined;
    const account_path = std.fmt.bufPrint(
        &path_buffer,
        "{s}/content/{s}/FFFE07D1/00010000/{s}/Account",
        .{ storage_root, profile_id, profile_id },
    ) catch {
        machoCapturePrint(
            "macho-processor: profile host preflight #{d}: profile={s} expected Account path exceeds diagnostic buffer\n",
            .{ self.profile_host_preflight_checks, profile_id },
        );
        return;
    };
    const file_stat = std.Io.Dir.cwd().statFile(self.io, account_path, .{}) catch |err| {
        machoCapturePrint(
            "macho-processor: profile host preflight #{d}: profile={s} account={s} host_status={s}; VFS failure may be genuine\n",
            .{ self.profile_host_preflight_checks, profile_id, account_path, @errorName(err) },
        );
        return;
    };
    machoCapturePrint(
        "macho-processor: profile host preflight #{d}: profile={s} account={s} host_status=present kind={s} bytes={d}; a later C000000F without an Account open is a guest VFS path-resolution failure\n",
        .{ self.profile_host_preflight_checks, profile_id, account_path, @tagName(file_stat.kind), file_stat.size },
    );
}

pub fn observeProfileAccountFlow(self: anytype) void {
    const load_entry = self.internal_targets.profile_manager_load_account;
    if (load_entry != 0 and self.regs.rip == load_entry) {
        const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
        self.profile_account_flow.active = true;
        self.profile_account_flow.manager = self.regs.rdi;
        self.profile_account_flow.xuid = self.regs.rsi;
        self.profile_account_flow.return_address = return_address;
        self.profile_account_flow.started_step = self.executed_steps;
        self.profile_account_flow.stage = .loading;
        self.profile_account_flow.account_guest_fd = std.math.maxInt(u64);
        self.profile_account_flow.requested_bytes = 0;
        self.profile_account_flow.bytes_read = 0;
        self.profile_account_flow.attempts +|= 1;
        const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
        machoCapturePrint(
            "macho-processor: profile Account flow #{d} started: manager=0x{x} xuid={x:0>16} return=0x{x} {s}+0x{x} step={d}\n",
            .{ self.profile_account_flow.attempts, self.regs.rdi, self.regs.rsi, return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0, self.executed_steps },
        );
        return;
    }

    if (!self.profile_account_flow.active) return;

    const dismount_entry = self.internal_targets.profile_manager_dismount_profile;
    if (dismount_entry != 0 and self.regs.rip == dismount_entry) {
        const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
        const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
        if (caller) |symbol| {
            if (classifyProfileDismountCaller(symbol.name, symbol.offset)) |stage| self.profile_account_flow.stage = stage;
        }
        machoCapturePrint(
            "macho-processor: profile temporary dismount: xuid={x:0>16} stage={s} caller=0x{x} {s}+0x{x} bytes_read={d} minimum_account_bytes={d} interpretation={s}\n",
            .{ self.profile_account_flow.xuid, @tagName(self.profile_account_flow.stage), return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0, self.profile_account_flow.bytes_read, PROFILE_ACCOUNT_INFO_BYTES, if (self.profile_account_flow.stage == .decrypted) "expected success-path cleanup before accounts_ insertion" else "early LoadAccount cleanup" },
        );
        return;
    }

    const insert_entry = self.internal_targets.profile_account_insert_or_assign;
    if (insert_entry != 0 and self.regs.rip == insert_entry) {
        self.profile_account_flow.stage = .inserting;
        const key = if (self.guestMemoryConst(self.regs.rsi, 8) != null) self.read64(self.regs.rsi) else 0;
        machoCapturePrint(
            "macho-processor: profile accounts_ insertion checkpoint: map=0x{x} key_ptr=0x{x} key={x:0>16} account=0x{x} expected_xuid={x:0>16} key_matches={}\n",
            .{ self.regs.rdi, self.regs.rsi, key, self.regs.rdx, self.profile_account_flow.xuid, key == self.profile_account_flow.xuid },
        );
        return;
    }

    if (self.profile_account_flow.return_address != 0 and
        self.regs.rip == self.profile_account_flow.return_address)
    {
        const succeeded = self.regs.rax & 1 != 0;
        if (succeeded) {
            self.profile_account_flow.successes +|= 1;
            self.profile_account_flow.stage = .completed;
        } else {
            self.profile_account_flow.failures +|= 1;
        }
        machoCapturePrint(
            "macho-processor: profile Account flow completed: xuid={x:0>16} success={} final_stage={s} bytes_read={d}/{d} elapsed_steps={d}; device dismount before this return is {s}\n",
            .{ self.profile_account_flow.xuid, succeeded, @tagName(self.profile_account_flow.stage), self.profile_account_flow.bytes_read, self.profile_account_flow.requested_bytes, self.executed_steps -| self.profile_account_flow.started_step, if (succeeded) "normal and the decoded account is now in accounts_" else "associated with an earlier load failure" },
        );
        self.profile_account_flow.active = false;
        self.profile_account_flow.account_guest_fd = std.math.maxInt(u64);
    }
}

pub fn noteProfileAccountOpen(self: anytype, path: []const u8, guest_fd: u64) void {
    const account_path = std.mem.eql(u8, path, "Account") or
        std.mem.endsWith(u8, path, "/Account") or
        std.mem.endsWith(u8, path, "\\Account");
    if (!self.profile_account_flow.active or !account_path) return;
    if (guest_fd == std.math.maxInt(u64)) {
        self.profile_account_flow.stage = .open_failed;
        return;
    }
    self.profile_account_flow.stage = .host_opened;
    self.profile_account_flow.account_guest_fd = guest_fd;
    machoCapturePrint(
        "macho-processor: profile Account host descriptor bound: xuid={x:0>16} guest_fd={d} stage=host_opened\n",
        .{ self.profile_account_flow.xuid, guest_fd },
    );
}

pub fn noteProfileAccountRead(self: anytype, guest_fd: u64, requested: u64, result: i64, offset: u64) void {
    if (!self.profile_account_flow.active or guest_fd != self.profile_account_flow.account_guest_fd) return;
    self.profile_account_flow.requested_bytes +|= requested;
    if (result > 0) self.profile_account_flow.bytes_read +|= @intCast(result);
    self.profile_account_flow.stage = .reading;
    machoCapturePrint(
        "macho-processor: profile Account read checkpoint: xuid={x:0>16} guest_fd={d} offset={d} requested={d} returned={d} cumulative={d} minimum={d} complete_encrypted_file={}\n",
        .{ self.profile_account_flow.xuid, guest_fd, offset, requested, result, self.profile_account_flow.bytes_read, PROFILE_ACCOUNT_INFO_BYTES, self.profile_account_flow.bytes_read >= PROFILE_ENCRYPTED_ACCOUNT_BYTES },
    );
}

pub fn observeBackendGuestLog(self: anytype, message: []const u8) void {
    const observation = self.backend_diagnostics.observeLine(message, self.executed_steps) orelse return;
    const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
    const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
    machoCapturePrint(
        "macho-processor: x64 backend event #{d}: event={s} phase={s}->{s} step={d} delta={d} active=0x{x} caller=0x{x} {s}+0x{x}\n",
        .{
            observation.sequence,
            @tagName(observation.event),
            @tagName(observation.previous_phase),
            @tagName(observation.phase),
            observation.step,
            observation.delta_steps,
            self.active_guest_thread,
            return_address,
            if (caller) |symbol| symbol.name else "<unknown>",
            if (caller) |symbol| symbol.offset else 0,
        },
    );

    if (observation.event == .indirection_table_failed) {
        const mapping = self.backend_diagnostics.last_mapping;
        if (!mapping.valid) {
            machoCapturePrint(
                "macho-processor: x64 code-cache warning correlation: no mmap call was observed after backend initialization began; allocation may have used an unmodeled route\n",
                .{},
            );
        } else {
            machoCapturePrint(
                "macho-processor: x64 code-cache warning correlation: latest mmap route={s} address=0x{x} length={d} prot=0x{x} flags=0x{x} result_known={} succeeded={} result=0x{x} stage={s}\n",
                .{ mapping.route, mapping.address, mapping.length, mapping.prot, mapping.flags, mapping.result_known, mapping.succeeded, mapping.result, if (mapping.stage.len != 0) mapping.stage else "<pending>" },
            );
            if (mapping.address == 0) {
                machoCapturePrint(
                    "macho-processor: x64 code-cache warning interpretation: the macOS guest requested OS-selected placement (address=0), so the guest's 0x80000000-0x9fffffff warning text does not describe the actual mmap hint used on this path\n",
                    .{},
                );
            }
        }
    }
    if (observation.event == .backend_initialize_succeeded and self.backend_diagnostics.capstone_assertions != 0) {
        machoCapturePrint(
            "macho-processor: x64 backend recovery evidence: initialization reached completed-successfully after {d} Capstone constructor assertion(s); backend object existence is proven, while Capstone-dependent diagnostics remain degraded\n",
            .{self.backend_diagnostics.capstone_assertions},
        );
    }
}

pub fn backendMemoryDiagnosticsActive(self: anytype) bool {
    return self.backend_diagnostics.mappingWindowActive();
}

pub fn noteBackendMmapAttempt(self: anytype, route: []const u8, address: u64, length: u64, prot: u64, flags: u64, fixed: bool, anonymous: bool) void {
    if (!self.backend_diagnostics.noteMmapAttempt(route, address, length, prot, flags, fixed, anonymous, self.executed_steps)) return;
    const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
    const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
    machoCapturePrint(
        "macho-processor: x64 backend mmap attempt #{d}: route={s} phase={s} step={d} address=0x{x} length={d} prot=0x{x} flags=0x{x} fixed={} anonymous={} caller=0x{x} {s}+0x{x}\n",
        .{ self.backend_diagnostics.mmap_attempts_during_backend, route, @tagName(self.backend_diagnostics.phase), self.executed_steps, address, length, prot, flags, fixed, anonymous, return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0 },
    );
}

pub fn noteBackendMmapResult(self: anytype, succeeded: bool, result: u64, stage: []const u8) void {
    if (!self.backend_diagnostics.last_mapping.valid or self.backend_diagnostics.last_mapping.step != self.executed_steps) return;
    const mapping = self.backend_diagnostics.last_mapping;
    self.backend_diagnostics.noteMmapResult(succeeded, result, stage);
    machoCapturePrint(
        "macho-processor: x64 backend mmap result: attempt={d} succeeded={} result=0x{x} stage={s}\n",
        .{ self.backend_diagnostics.mmap_attempts_during_backend, succeeded, result, stage },
    );
    if (!succeeded and comptime @hasDecl(@TypeOf(self.*), "noteJitHostMmapFailure")) {
        // Darwin's MAP_JIT bit is 0x800. The sparse-memory layer owns the
        // emulation policy; this observer only identifies whether the failed
        // backend allocation explicitly requested that host capability.
        const map_jit = mapping.flags & 0x800 != 0;
        self.noteJitHostMmapFailure(stage, mapping.address, mapping.length, mapping.prot, mapping.flags, map_jit);
    }
}

pub fn noteBackendMprotect(self: anytype, route: []const u8, address: u64, length: u64, prot: u64, succeeded: bool) void {
    if (!self.backend_diagnostics.noteMprotectAttempt()) return;
    machoCapturePrint(
        "macho-processor: x64 backend mprotect #{d}: route={s} phase={s} step={d} address=0x{x} length={d} prot=0x{x} succeeded={}\n",
        .{ self.backend_diagnostics.mprotect_attempts_during_backend, route, @tagName(self.backend_diagnostics.phase), self.executed_steps, address, length, prot, succeeded },
    );
    if (!succeeded and comptime @hasDecl(@TypeOf(self.*), "noteJitHostMprotectFailure")) {
        self.noteJitHostMprotectFailure(route, address, length, prot);
    }
}

/// Keys whose binding this run depends on, and what a failure to bind costs.
///
/// Each earned its place by having already been silently false: an option set
/// in the configuration file, read back by the guest as its compiled-in
/// default, and nothing anywhere reporting the gap. `gpu_debug_force_swap_*`
/// is the case that cost a week — the forced-swap probe was configured, never
/// enabled, and every downstream counter reported the consequence.
const watched_config_keys = [_]struct { key: []const u8, severity: preflight_lib.Severity }{
    .{ .key = "gpu_debug_force_swap_after_ms", .severity = .degraded },
    .{ .key = "gpu_debug_force_swap_interval_ms", .severity = .degraded },
    .{ .key = "gpu_debug_force_swap_once", .severity = .degraded },
    .{ .key = "gpu_debug_force_interrupt_callback_after_vblank", .severity = .degraded },
    .{ .key = "gpu_log_no_swap_after_ms", .severity = .advisory },
    .{ .key = "kernel_debug_monitor", .severity = .degraded },
    .{ .key = "gpu_mmio_cp_endian_autofix", .severity = .degraded },
    .{ .key = "inline_mmio_access", .severity = .degraded },
    .{ .key = "gpu", .severity = .fatal },
};

/// Feed a guest-printed line to preflight and, once the guest's configuration
/// dump has been seen in full, report what disagrees.
///
/// Evaluated at the dump's close rather than at a fixed step count: that is the
/// first moment both readings exist, and evaluating before then would report
/// `indeterminate` for everything — correct but useless. Reported once, because
/// a binding failure does not change during a run and restating it every line
/// would bury it in exactly the way this gate exists to prevent.
pub fn observePreflightGuestLog(self: anytype, message: []const u8) void {
    if (self.preflight.count == 0) {
        for (watched_config_keys) |entry| self.preflight.watch(entry.key, entry.severity);
    }
    // A dump Rosette built from the file restates the file. Accepting it as the
    // guest's own belief would make every key agree with itself, which is the
    // false green this library exists to refuse.
    if (!self.preflight_dump_is_accelerated) self.preflight.observeGuestLine(message);
    if (self.preflight_evaluated or self.preflight_dump_is_accelerated) return;

    // The guest's own dump ends with the closing rule after the last key.
    if (!self.preflight.guest_dump_captured) return;
    if (std.mem.indexOf(u8, message, "-----------") == null) return;
    if (std.mem.indexOf(u8, message, "CONFIG DUMP") != null) return;
    finishPreflightConfigPhase(self);
}

/// Close the configuration phase and report. Called after the dump has been
/// emitted, never during it: a verdict printed before the evidence it judges
/// reads as though it were about something else entirely.
pub fn finishPreflightConfigPhase(self: anytype) void {
    if (self.preflight_evaluated) return;
    if (!self.preflight.config_file_read) return;
    self.preflight_evaluated = true;
    reportPreflight(self);
}

fn reportPreflight(self: anytype) void {
    var storage: [preflight_lib.collector.max_watched]preflight_lib.ConfigReading = undefined;
    const readings = self.preflight.readings(&storage);

    // When this runtime builds the configuration dump itself, the guest never
    // prints its own, so the second reading does not exist. That is a limit of
    // Rosette's acceleration, not a defect in the application — blocking on it
    // would refuse every launch for a reason that has nothing to do with the
    // program being run. Report it, loudly, and let the run proceed.
    const guest_reading_unavailable = self.preflight_dump_is_accelerated;
    for (readings) |reading| {
        var adjusted = reading;
        if (guest_reading_unavailable) adjusted.severity = .advisory;
        self.preflight_report.record(preflight_lib.observation.checkConfigAgreement(
            adjusted,
            self.preflight.guest_dump_captured,
            self.preflight.config_file_read,
        ));
    }
    if (guest_reading_unavailable) {
        machoCapturePrint(
            "macho-processor: preflight: config dump is built by this runtime from the file, so the guest never states what it bound. The agreement check has one reading, not two, and is reporting UNKNOWN rather than comparing the file against itself. {d} file value(s) were read\n",
            .{countFileReadings(readings)},
        );
    }

    if (self.preflight_report.isClean()) {
        machoCapturePrint(
            "macho-processor: preflight: config agreement OK across {d} watched key(s); the values this process runs on are the values its configuration declares\n",
            .{readings.len},
        );
        return;
    }

    // Nine identical lines saying the same thing about nine keys is the wall of
    // text this gate exists to replace. Report each VIOLATION in full — those
    // differ and each is actionable — and collapse the UNKNOWNs into one line
    // naming the keys, because they share a single cause.
    var unknown_count: usize = 0;
    for (self.preflight_report.items()) |result| {
        switch (result.outcome) {
            .satisfied => {},
            .indeterminate => unknown_count += 1,
            .violated => machoCapturePrint(
                "macho-processor: preflight VIOLATED [{s}/{s}] key={s}: {s}; expected={s} observed={s}. {s}\n",
                .{
                    result.severity.label(),
                    result.subsystem,
                    result.evidence.source,
                    result.requirement,
                    result.evidence.expected,
                    result.evidence.observed,
                    result.remedy,
                },
            ),
        }
    }
    if (unknown_count != 0) {
        const first_unknown = firstUnknown(self);
        machoCapturePrint(
            "macho-processor: preflight UNKNOWN: {d} watched key(s) could not be decided — {s}. First: {s}. This is not a pass; it is the gate declining to guess\n",
            .{ unknown_count, first_unknown.evidence.observed, first_unknown.evidence.source },
        );
    }

    if (self.preflight_report.firstBlocker()) |blocker| {
        machoCapturePrint(
            "macho-processor: preflight BLOCKER [{s}] key={s}: {s}. Terminating with SIGTERM rather than running a session whose results would describe a consequence and never a cause\n",
            .{ blocker.outcome.label(), blocker.evidence.source, blocker.requirement },
        );
        terminateForPreflight(self);
    }
}

fn countFileReadings(readings: []const preflight_lib.ConfigReading) usize {
    var total: usize = 0;
    for (readings) |reading| {
        if (reading.file_present) total += 1;
    }
    return total;
}

fn firstUnknown(self: anytype) preflight_lib.Result {
    for (self.preflight_report.items()) |result| {
        if (result.outcome == .indeterminate) return result;
    }
    return self.preflight_report.items()[0];
}

/// Stop the run at the gate. Both halves matter: the runtime's own termination
/// state so the exit summary explains itself, and a real SIGTERM so anything
/// supervising this process — a shell script, a build harness — sees an ordinary
/// signalled exit rather than a silent one.
fn terminateForPreflight(self: anytype) void {
    self.faulted = true;
    self.terminated = true;
    // 128 + SIGTERM, the conventional shell encoding for a signalled exit.
    self.exit_code = 143;
    std.posix.raise(std.posix.SIG.TERM) catch |err| {
        machoCapturePrint(
            "macho-processor: preflight could not raise SIGTERM ({s}); the run is still marked terminated\n",
            .{@errorName(err)},
        );
    };
}

/// Feed the configuration file's own text, read by this runtime rather than
/// reported by the guest.
pub fn observePreflightConfigFile(self: anytype, address: u64, length: u64) void {
    if (self.preflight.count == 0) {
        for (watched_config_keys) |entry| self.preflight.watch(entry.key, entry.severity);
    }
    const text = self.guestMemoryConst(address, length) orelse return;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| self.preflight.observeFileLine(line);
}

test "an inactive bootstrap mailbox slot is not guest output evidence" {
    const State = struct {
        executed_steps: u64 = 40_782_613,
        gpu_guest_output_mailbox: gpu.guest_output_mailbox.Ledger = .{},
    };
    var state = State{};
    observeGuestOutputMailbox(
        &state,
        "DEBUG: ConsumeGuestOutput bootstrap-inactive: mailbox has no ready guest frame yet " ++
            "(expected before first RefreshGuestOutput). mailbox=0 refresh_attempt_count=0 " ++
            "refresh_success_count=0",
    );

    try std.testing.expectEqual(@as(u64, 1), state.gpu_guest_output_mailbox.observations);
    try std.testing.expectEqual(@as(i64, -1), state.gpu_guest_output_mailbox.latest.mailbox_index);
    try std.testing.expect(!state.gpu_guest_output_mailbox.everHeldGuestOutput());
    try std.testing.expectEqual(
        gpu.guest_output_mailbox.Verdict.starved_by_producer,
        state.gpu_guest_output_mailbox.verdict(false),
    );
}

test "only an active guest-output line can promote a mailbox slot" {
    const State = struct {
        executed_steps: u64 = 90,
        gpu_guest_output_mailbox: gpu.guest_output_mailbox.Ledger = .{},
    };
    var state = State{};
    observeGuestOutputMailbox(
        &state,
        "DEBUG: VulkanPresenter: guest_output_image=YES mailbox=1 frontbuffer=0x1234 " ++
            "refresh_attempt_count=2 refresh_success_count=1",
    );

    try std.testing.expectEqual(@as(i64, 1), state.gpu_guest_output_mailbox.latest.mailbox_index);
    try std.testing.expect(state.gpu_guest_output_mailbox.everHeldGuestOutput());
    try std.testing.expectEqual(
        gpu.guest_output_mailbox.Verdict.guest_output_delivered,
        state.gpu_guest_output_mailbox.verdict(false),
    );
}

test "the read-pointer write-back address is learned from the emulator's own line" {
    const State = struct {
        gpu_read_pointer_writeback_address: u32 = 0,
        gpu_read_pointer_writeback_freq: u32 = 0,
        gpu_read_pointer_writeback_mapped: bool = false,
    };
    var state = State{};
    observeReadPointerWriteBackConfig(
        &state,
        "RING BUFFER: RPTR writeback configured ptr=8200A100 block_size_log2=6 " ++
            "update_freq=16 host_ptr=0x1234 mapped=YES",
    );
    try std.testing.expectEqual(@as(u32, 0x8200A100), state.gpu_read_pointer_writeback_address);
    try std.testing.expectEqual(@as(u32, 16), state.gpu_read_pointer_writeback_freq);
    try std.testing.expect(state.gpu_read_pointer_writeback_mapped);
}

// The emulator resolving the address and the word ever changing are different
// facts, and only the second one is a completion. A configuration line that
// says `mapped=NO` is the emulator telling us in advance that it cannot write.
test "an unmapped write-back address is recorded as unmapped" {
    const State = struct {
        gpu_read_pointer_writeback_address: u32 = 0,
        gpu_read_pointer_writeback_freq: u32 = 0,
        gpu_read_pointer_writeback_mapped: bool = true,
    };
    var state = State{};
    observeReadPointerWriteBackConfig(
        &state,
        "RING BUFFER: RPTR writeback configured ptr=8200A100 block_size_log2=6 " ++
            "update_freq=16 host_ptr=0x0 mapped=NO",
    );
    try std.testing.expect(!state.gpu_read_pointer_writeback_mapped);
}

test "producer waits are attributed only to the publishing thread" {
    const State = struct {
        gpu_producer_stall: gpu.ProducerStall = .{},
        active_guest_thread: u64 = 0,
        executed_steps: u64 = 0,
    };
    var state = State{};
    state.gpu_producer_stall.attribute(0x7FFF20F0, 3_407_441_654);
    state.gpu_producer_stall.notePublication(3_407_441_654);

    // A wait on another thread is dropped, however similar the line looks.
    state.active_guest_thread = 0x7FFF2040;
    state.executed_steps = 3_500_000_000;
    observeProducerWaitLine(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000000 guest_obj=827CEC14 " ++
            "handle=F800015C pc=826C72F0 duration_ms=5 wait_disposition=blocked",
    );
    try std.testing.expectEqual(@as(usize, 0), state.gpu_producer_stall.retained().len);

    state.active_guest_thread = 0x7FFF20F0;
    observeProducerWaitLine(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000000 guest_obj=827CEC14 " ++
            "handle=F800015C pc=826C72F0 duration_ms=5 wait_disposition=blocked",
    );
    const retained = state.gpu_producer_stall.retained();
    try std.testing.expectEqual(@as(usize, 1), retained.len);
    try std.testing.expectEqual(@as(u64, 0x827CEC14), retained[0].object);
    try std.testing.expectEqual(@as(u64, 0x826C72F0), retained[0].pc);
    try std.testing.expectEqual(@as(u32, 5), retained[0].duration_ms);
    // A result line proves the wait returned, so it can never be the thing
    // holding the producer.
    try std.testing.expect(retained[0].disposition.returned());
    try std.testing.expect(state.gpu_producer_stall.outstanding == null);
}

// The distinction the whole tracker exists for: an entry line with no result
// behind it is a park, and a park names an object somebody owed a signal to.
test "an entry line with no result is recorded as a park" {
    const State = struct {
        gpu_producer_stall: gpu.ProducerStall = .{},
        active_guest_thread: u64 = 0x7FFF20F0,
        executed_steps: u64 = 3_500_000_000,
    };
    var state = State{};
    state.gpu_producer_stall.attribute(0x7FFF20F0, 3_407_441_654);
    state.gpu_producer_stall.notePublication(3_407_441_654);
    observeProducerWaitLine(
        &state,
        "RING BUFFER: KeWaitForSingleObject tid=15 obj_ptr=DA7CEC14 " ++
            "guest_obj=827CEC14 type=8 handle=F800015C pc=826C72F0",
    );
    try std.testing.expect(state.gpu_producer_stall.outstanding != null);
    try std.testing.expectEqual(
        @as(u64, 0x827CEC14),
        state.gpu_producer_stall.outstanding.?.object,
    );
    try std.testing.expectEqual(
        gpu.producer_stall.Verdict.parked,
        state.gpu_producer_stall.verdict(5_000_000_000),
    );
}

// A guest log line that is not a wait must cost one rejecting compare and
// change nothing: this runs on every mirrored line in the run.
test "a non-wait line does not reach the producer tracker" {
    const State = struct {
        gpu_producer_stall: gpu.ProducerStall = .{},
        active_guest_thread: u64 = 0x7FFF20F0,
        executed_steps: u64 = 1,
    };
    var state = State{};
    state.gpu_producer_stall.attribute(0x7FFF20F0, 0);
    state.gpu_producer_stall.notePublication(0);
    observeProducerWaitLine(&state, "DEBUG: xeKeSetEvent: ptr=827CEC28 handle=F800016C");
    try std.testing.expectEqual(@as(usize, 0), state.gpu_producer_stall.retained().len);
}

// Rosette read `established=NO address=0x00000000` for a registration that
// plainly happened, because nothing parsed the one line that states it.
test "the interrupt callback slot is learned from the emulator's own line" {
    const State = struct {
        gpu_interrupt_slot_address: u32 = 0,
        gpu_interrupt_slot_user_data: u32 = 0,
        gpu_interrupt_slot_step: u64 = 0,
        gpu_interrupt_slot_writes: u64 = 0,
        gpu_interrupt_slot_is_guest: bool = false,
        gpu_interrupt_slot_previous_address: u32 = 0,
        gpu_interrupt_slot_previous_user_data: u32 = 0,
        gpu_interrupt_slot_previous_step: u64 = 0,
        gpu_interrupt_slot_previous_is_guest: bool = false,
        gpu_interrupt_slot_transitions: u64 = 0,
        gpu_interrupt_slot_guest_writes: u64 = 0,
        gpu_interrupt_slot_host_writes: u64 = 0,
        executed_steps: u64 = 0,
    };
    var state = State{};

    state.executed_steps = 731_000_000;
    observeInterruptCallbackSlot(&state, "SetInterruptCallback(FFFF0010, 00000000)");
    try std.testing.expectEqual(@as(u32, 0xFFFF0010), state.gpu_interrupt_slot_address);
    try std.testing.expect(!state.gpu_interrupt_slot_is_guest);

    // The slot holds one address and the newest statement is the true one.
    state.executed_steps = 3_005_381_071;
    observeInterruptCallbackSlot(&state, "SetInterruptCallback(821951F8, 40001F00)");
    try std.testing.expectEqual(@as(u32, 0x821951F8), state.gpu_interrupt_slot_address);
    try std.testing.expectEqual(@as(u32, 0x40001F00), state.gpu_interrupt_slot_user_data);
    try std.testing.expectEqual(@as(u64, 3_005_381_071), state.gpu_interrupt_slot_step);
    try std.testing.expectEqual(@as(u64, 2), state.gpu_interrupt_slot_writes);
    try std.testing.expect(state.gpu_interrupt_slot_is_guest);
    try std.testing.expectEqual(@as(u32, 0xFFFF0010), state.gpu_interrupt_slot_previous_address);
    try std.testing.expectEqual(@as(u64, 731_000_000), state.gpu_interrupt_slot_previous_step);
    try std.testing.expect(!state.gpu_interrupt_slot_previous_is_guest);
    try std.testing.expectEqual(@as(u64, 1), state.gpu_interrupt_slot_transitions);
    try std.testing.expectEqual(@as(u64, 1), state.gpu_interrupt_slot_guest_writes);
    try std.testing.expectEqual(@as(u64, 1), state.gpu_interrupt_slot_host_writes);
}

test "a line that is not a slot write leaves the slot alone" {
    const State = struct {
        gpu_interrupt_slot_address: u32 = 0x821951F8,
        gpu_interrupt_slot_user_data: u32 = 0,
        gpu_interrupt_slot_step: u64 = 0,
        gpu_interrupt_slot_writes: u64 = 0,
        gpu_interrupt_slot_is_guest: bool = true,
        executed_steps: u64 = 0,
    };
    var state = State{};
    observeInterruptCallbackSlot(&state, "DEBUG: BREADCRUMB: xeKeSetEvent handle=F800016C");
    try std.testing.expectEqual(@as(u32, 0x821951F8), state.gpu_interrupt_slot_address);
    try std.testing.expectEqual(@as(u64, 0), state.gpu_interrupt_slot_writes);
}

test "callback domain breadcrumbs keep host and title transactions separate" {
    const State = struct {
        interrupt_callback_transaction: interrupt_callback_transaction.Ledger = .{},
        host_interrupt_callback_transaction: interrupt_callback_transaction.Ledger = .{ .domain = .xenia_host },
        monotone_witness: monotone_witness.Ledger = .{},
        last_interrupt_callback_log_domain: u8 = 0,
        executed_steps: u64 = 0,
    };
    var state = State{};

    state.executed_steps = 10;
    observeInterruptCallbackTransaction(
        &state,
        "DEBUG: GPU callback set: count=1 callback=FFFF0010 user_data=00000000 " ++
            "source=rosette-host callback_domain=rosette-host timestamp_ms=10",
    );
    try std.testing.expectEqual(@as(u64, 1), state.host_interrupt_callback_transaction.registrations);
    try std.testing.expectEqual(@as(u64, 0), state.interrupt_callback_transaction.registrations);

    state.executed_steps = 15;
    observeInterruptCallbackTransaction(
        &state,
        "ROSETTE HOST GPU CALLBACK: guest/Xenia callback replaced the host callback " ++
            "(callback=821951F8); host provenance is closed",
    );
    try std.testing.expect(state.host_interrupt_callback_transaction.superseded);
    try std.testing.expectEqual(
        @as(u32, 0x821951F8),
        state.host_interrupt_callback_transaction.successor_callback,
    );

    state.executed_steps = 20;
    observeInterruptCallbackTransaction(
        &state,
        "DEBUG: GPU callback set: count=2 callback=821951F8 user_data=40001F00 " ++
            "source=guest-or-xenia callback_domain=guest-title timestamp_ms=20",
    );
    try std.testing.expectEqual(@as(u64, 2), state.interrupt_callback_transaction.registrations);
    try std.testing.expectEqual(@as(u64, 1), state.host_interrupt_callback_transaction.registrations);

    state.executed_steps = 30;
    observeInterruptCallbackTransaction(
        &state,
        "GPU callback dispatch completed: id=7 attempts=1 completions=1 " ++
            "callback=821951F8 callback_domain=guest-title source=1 cpu=2 " ++
            "duration_ms=0 payload_before=NO payload_after=NO payload_changed=NO",
    );
    try std.testing.expectEqual(@as(u64, 1), state.interrupt_callback_transaction.dispatch_attempts);
    try std.testing.expectEqual(@as(u64, 1), state.interrupt_callback_transaction.callback_returns);
    try std.testing.expectEqual(@as(u64, 0), state.host_interrupt_callback_transaction.dispatch_attempts);
    try std.testing.expectEqual(@as(u64, 20), state.interrupt_callback_transaction.first_registration_step);
    try std.testing.expectEqual(@as(u64, 30), state.interrupt_callback_transaction.first_dispatch_step);
    try std.testing.expectEqual(@as(u64, 30), state.interrupt_callback_transaction.first_return_step);
    try std.testing.expect(
        state.monotone_witness.reading(
            .title_interrupt_callback_entries,
            .emulator_sampled_line,
        ).stated,
    );

    // A host completion through the same textual path must remain host-owned.
    state.executed_steps = 40;
    observeInterruptCallbackTransaction(
        &state,
        "GPU callback dispatch completed: id=8 attempts=2 completions=2 " ++
            "callback=FFFF0010 callback_domain=rosette-host source=0 cpu=0 " ++
            "duration_ms=0 payload_before=NO payload_after=NO payload_changed=NO",
    );
    try std.testing.expectEqual(@as(u64, 2), state.host_interrupt_callback_transaction.dispatch_attempts);
    try std.testing.expectEqual(@as(u64, 1), state.interrupt_callback_transaction.callback_returns);
    try std.testing.expectEqual(
        @as(u64, 1),
        state.monotone_witness.reading(
            .title_interrupt_callback_entries,
            .emulator_sampled_line,
        ).count,
    );

    // The shared executor breadcrumb is also host-owned when it carries the
    // host domain explicitly; it must not create a second title witness.
    state.executed_steps = 50;
    observeInterruptCallbackTransaction(
        &state,
        "ROSETTE INTERRUPT DISPATCH: leave id=9 entered=2 returned=2 " ++
            "callback=FFFF0010 callback_domain=rosette-host",
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        state.monotone_witness.reading(
            .title_interrupt_callback_entries,
            .emulator_sampled_total,
        ).count,
    );
}

test "concrete Xenia VdSet breadcrumbs register the title transaction" {
    const State = struct {
        interrupt_callback_transaction: interrupt_callback_transaction.Ledger = .{},
        host_interrupt_callback_transaction: interrupt_callback_transaction.Ledger = .{ .domain = .xenia_host },
        last_interrupt_callback_log_domain: u8 = 0,
        executed_steps: u64 = 0,
    };
    var state = State{};

    state.executed_steps = 2_864_415_597;
    observeInterruptCallbackTransaction(
        &state,
        "[xenia] i> VdSetGraphicsInterruptCallback EXECUTED: cb=821951F8 arg=40001F00",
    );
    try std.testing.expectEqual(@as(u64, 1), state.interrupt_callback_transaction.registrations);
    try std.testing.expectEqual(@as(u32, 0x821951F8), state.interrupt_callback_transaction.callback_address);
    try std.testing.expectEqual(@as(u32, 0x40001F00), state.interrupt_callback_transaction.user_data);
    try std.testing.expectEqual(@as(u64, 2_864_415_597), state.interrupt_callback_transaction.first_registration_step);
    try std.testing.expectEqual(@as(u8, 1), state.last_interrupt_callback_log_domain);

    state.executed_steps += 1;
    observeInterruptCallbackTransaction(
        &state,
        "[xenia] w> RING BUFFER: VdSetGraphicsInterruptCallback call count=1 " ++
            "callback=821951F8 user_data=40001F00",
    );
    try std.testing.expectEqual(@as(u64, 1), state.interrupt_callback_transaction.registrations);
    try std.testing.expectEqual(@as(u64, 2_864_415_597), state.interrupt_callback_transaction.first_registration_step);
}

test "GPU bootstrap callsite probes are retained by their milestone" {
    const State = struct {
        gpu_bootstrap_provenance: gpu.BootstrapProvenance = .{},
        executed_steps: u64 = 0,
    };
    var state = State{ .executed_steps = 100 };
    const suffix = " value_addr=82000000 thunk_addr=82700000 pc_hit=NO " ++
        "lr_hit=NO ctr_hit=NO current_branch_targets_probe=NO " ++
        "near_direct_bl_hits=0 entry_bctrl_hits=2 near_value_ref_hits=0 " ++
        "entry_value_ref_hits=11";

    observeBootstrapCallsiteProbe(&state, "callsite probe ordinal=0x1B6 name=VdEnableRingBufferRPtrWriteBack" ++ suffix);
    observeBootstrapCallsiteProbe(&state, "callsite probe ordinal=0x1C2 name=VdInitializeEngines" ++ suffix);
    observeBootstrapCallsiteProbe(&state, "callsite probe ordinal=0x1C3 name=VdInitializeRingBuffer" ++ suffix);
    observeBootstrapCallsiteProbe(&state, "callsite probe ordinal=0x1D5 name=VdSetGraphicsInterruptCallback" ++ suffix);

    try std.testing.expect(state.gpu_bootstrap_provenance.record(.rptr_writeback).callsiteObserved());
    try std.testing.expect(state.gpu_bootstrap_provenance.record(.initialize_engines).callsiteObserved());
    try std.testing.expect(state.gpu_bootstrap_provenance.record(.ring_buffer).callsiteObserved());
    try std.testing.expect(state.gpu_bootstrap_provenance.record(.graphics_interrupt_callback).callsiteObserved());
    try std.testing.expectEqual(@as(u64, 4), state.gpu_bootstrap_provenance.summary().callsite_blind);
}

// Rosette sees both ends of the draw path from the instruction pointer and
// cannot see which of nine exits took the draws in between. The emulator counts
// them; this reads the count, and keeps the defects separate from the draws
// that legitimately had no effect.
test "draw attrition is read from the emulator's ledger" {
    const State = struct {
        monotone_witness: monotone_witness.Ledger = .{},
        gpu_draws_entered: u64 = 0,
        gpu_draws_reached_render_target: u64 = 0,
        gpu_draw_early_exits: u64 = 0,
        gpu_draw_defect_exits: u64 = 0,
        gpu_draw_exits_named: u64 = 0,
        gpu_draw_first_exit: [48]u8 = [_]u8{0} ** 48,
        gpu_draw_first_exit_length: u8 = 0,
        gpu_draw_first_exit_step: u64 = 0,
        executed_steps: u64 = 3_399_870_297,
    };
    var state = State{};
    observeDrawAttrition(
        &state,
        "ROSETTE DRAW EXIT: draw #1 left IssueDraw at no_rasterization_no_memexport " ++
            "without reaching the render target cache; ...",
    );
    try std.testing.expectEqual(@as(u64, 1), state.gpu_draw_exits_named);
    try std.testing.expectEqualStrings(
        "no_rasterization_no_memexport",
        state.gpu_draw_first_exit[0..state.gpu_draw_first_exit_length],
    );

    observeDrawAttrition(
        &state,
        "ROSETTE DRAW LEDGER: draws=24 reached_render_target=0 exited_early=24 " ++
            "of which defects=0; a draw that never reaches ...",
    );
    try std.testing.expectEqual(@as(u64, 24), state.gpu_draws_entered);
    try std.testing.expectEqual(@as(u64, 0), state.gpu_draws_reached_render_target);
    try std.testing.expectEqual(@as(u64, 24), state.gpu_draw_early_exits);
    try std.testing.expectEqual(@as(u64, 0), state.gpu_draw_defect_exits);
    try std.testing.expect(
        state.monotone_witness.reading(.draws_issued, .emulator_sampled_total).stated,
    );
    try std.testing.expectEqual(
        @as(u64, 24),
        state.monotone_witness.reading(.draws_issued, .emulator_sampled_total).count,
    );
    try std.testing.expect(
        !state.monotone_witness.reading(.render_target_updates, .emulator_sampled_line).stated,
    );
}

// The first exit named is retained; later ones only advance the count, so the
// reason a run first dropped a draw survives a thousand later ones.
test "the first named draw exit is retained" {
    const State = struct {
        gpu_draws_entered: u64 = 0,
        gpu_draws_reached_render_target: u64 = 0,
        gpu_draw_early_exits: u64 = 0,
        gpu_draw_defect_exits: u64 = 0,
        gpu_draw_exits_named: u64 = 0,
        gpu_draw_first_exit: [48]u8 = [_]u8{0} ** 48,
        gpu_draw_first_exit_length: u8 = 0,
        gpu_draw_first_exit_step: u64 = 0,
        executed_steps: u64 = 10,
    };
    var state = State{};
    observeDrawAttrition(&state, "ROSETTE DRAW EXIT: draw #1 left IssueDraw at shader_translation_failed x");
    observeDrawAttrition(&state, "ROSETTE DRAW EXIT: draw #2 left IssueDraw at no_host_vertices x");
    try std.testing.expectEqual(@as(u64, 2), state.gpu_draw_exits_named);
    try std.testing.expectEqualStrings(
        "shader_translation_failed",
        state.gpu_draw_first_exit[0..state.gpu_draw_first_exit_length],
    );
}

// Four bounded polls with a thirty-millisecond guest deadline, each consuming
// six seconds: the reading the ledger exists to relate.
test "an expired guest deadline is related to the time it consumed" {
    const State = struct {
        timeout_fidelity: timeout_fidelity.Ledger = .{},
    };
    var state = State{};
    var index: usize = 0;
    while (index < 4) : (index += 1) {
        observeTimeoutFidelity(
            &state,
            "RING BUFFER: KeWaitForSingleObject result=00000102 guest_obj=40004BF4 " ++
                "handle=F8000158 timeout_ms=30 duration_ms=6000 wait_disposition=timed_out",
        );
    }
    try std.testing.expectEqual(@as(u64, 4), state.timeout_fidelity.samples);
    try std.testing.expectEqual(
        timeout_fidelity.Verdict.dilated,
        state.timeout_fidelity.verdict(),
    );
    try std.testing.expectEqual(@as(u64, 0x40004BF4), state.timeout_fidelity.worst_object);
}

// A wait that was signalled says nothing about its deadline.
test "a satisfied wait is not a timeout sample" {
    const State = struct {
        timeout_fidelity: timeout_fidelity.Ledger = .{},
    };
    var state = State{};
    observeTimeoutFidelity(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000000 guest_obj=827CEC14 " ++
            "timeout_ms=30 duration_ms=5 wait_disposition=blocked",
    );
    try std.testing.expectEqual(@as(u64, 0), state.timeout_fidelity.samples);
}

// An infinite wait has no deadline to relate anything to.
test "an infinite timeout is not a sample" {
    const State = struct {
        timeout_fidelity: timeout_fidelity.Ledger = .{},
    };
    var state = State{};
    observeTimeoutFidelity(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000102 guest_obj=40004BF4 " ++
            "timeout_ms=-1 duration_ms=6000 wait_disposition=timed_out",
    );
    try std.testing.expectEqual(@as(u64, 0), state.timeout_fidelity.samples);
}

// The 2026-08-31 shape: one object is polled through a finite deadline beside
// another signalled repeatedly with nobody waiting. The poll is retained, but
// must not be reported as a parked half of an unmatched pair.
test "a bounded poll is kept separate from an orphan signal" {
    const State = struct {
        signal_expectation: signal_expectation.Ledger = .{},
        active_guest_thread: u64 = 0x7fff2140,
        executed_steps: u64 = 3_402_556_936,
        regs: struct { rip: u64 = 0x1bf400 } = .{},
    };
    var state = State{};
    observeSignalExpectation(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000102 wait_id=15 obj_ptr=8F474BF4 " ++
            "guest_obj=40004BF4 handle=F8000158 type=2 event_mode=manual_reset " ++
            "requested_timeout_ms=30 duration_ms=333 wait_disposition=timed_out " ++
            "guest_pc=8258A470 pc_domain=xenia_guest_ppc guest_pc_valid=YES " ++
            "guest_pc_quality=direct lr_entry=825AE908",
    );
    state.active_guest_thread = 0x7fff2160;
    observeSignalExpectation(
        &state,
        "DEBUG: xeKeSetEvent: ptr=827CEC28 handle=F800016C was_signalled=0 wait=0",
    );

    try std.testing.expectEqual(
        signal_expectation.Verdict.signal_without_consumer,
        state.signal_expectation.verdict(),
    );
    try std.testing.expect(state.signal_expectation.worstOrphanWait() == null);
    const waited = state.signal_expectation.worstPollingOrphan().?;
    try std.testing.expectEqual(@as(u64, 0x40004BF4), waited.object);
    try std.testing.expectEqual(@as(u64, 0x8258A470), waited.guest_pc);
    try std.testing.expectEqual(@as(u64, 0x825AE908), waited.guest_lr);
    try std.testing.expect(waited.guest_pc_trusted);
    try std.testing.expect(waited.polling());
    const signalled = state.signal_expectation.worstOrphanSignal().?;
    try std.testing.expectEqual(@as(u64, 0x827CEC28), signalled.object);
}

// A seeded program counter names an instruction that is not the one waiting.
test "a seeded guest program counter is not trusted" {
    const State = struct {
        signal_expectation: signal_expectation.Ledger = .{},
        active_guest_thread: u64 = 1,
        executed_steps: u64 = 1,
        regs: struct { rip: u64 = 0 } = .{},
    };
    var state = State{};
    observeSignalExpectation(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000000 guest_obj=827CEC14 " ++
            "handle=F800015C guest_pc=826C72F0 guest_pc_valid=NO " ++
            "guest_pc_quality=seeded lr_entry=826C7370 wait_disposition=blocked",
    );
    const record = state.signal_expectation.worstOrphanWait().?;
    try std.testing.expect(!record.guest_pc_trusted);
}

// A creation line carries a handle and no address; a wait carries both. The
// handle is what joins them.
test "creation provenance reaches the object through its handle" {
    const State = struct {
        signal_expectation: signal_expectation.Ledger = .{},
        active_guest_thread: u64 = 1,
        executed_steps: u64 = 1,
        regs: struct { rip: u64 = 0 } = .{},
    };
    var state = State{};
    observeSignalExpectation(
        &state,
        "RING BUFFER: KeWaitForSingleObject result=00000102 guest_obj=40004BF4 " ++
            "handle=F8000158 wait_disposition=timed_out",
    );
    observeSignalExpectation(&state, "Added handle:F8000158 for N2xe6kernel7XObjectE");
    try std.testing.expectEqual(
        signal_expectation.Provenance.bare_handle,
        state.signal_expectation.worstOrphanWait().?.provenance,
    );
}

// Rosette's stateful executor was unarmed on the run this was written for, so
// the only count that could answer "did the title ask for a completion" came
// from the command processor's own dispatch.
test "the emulator's packet census reaches the ledger" {
    const State = struct {
        gpu_packet_census: gpu.packet_census.Ledger = .{},
    };
    var state = State{};
    observeEmulatorPacketCensus(
        &state,
        "ROSETTE PACKET CENSUS: packets=72 interrupt_packets=0 " ++
            "event_write_packets=0 completion_requests=0; a batch with no ...",
    );
    try std.testing.expectEqual(@as(u64, 72), state.gpu_packet_census.emulator_packets);
    try std.testing.expectEqual(
        gpu.packet_census.Verdict.no_completion_requested,
        state.gpu_packet_census.verdict(),
    );

    observeEmulatorPacketCensus(
        &state,
        "ROSETTE PACKET CENSUS: packets=90 interrupt_packets=1 " ++
            "event_write_packets=0 completion_requests=1; ...",
    );
    try std.testing.expectEqual(
        gpu.packet_census.Verdict.interrupt_requested_not_delivered,
        state.gpu_packet_census.verdict(),
    );
}

// The PowerPC-domain ledger reported `registered=0` for a registration the
// `SetInterruptCallback` line plainly states — a zero that was the observer's
// and read as the title's.
test "a guest slot write registers in the PowerPC callback ledger" {
    const State = struct {
        gpu_interrupt_slot_address: u32 = 0,
        gpu_interrupt_slot_user_data: u32 = 0,
        gpu_interrupt_slot_step: u64 = 0,
        gpu_interrupt_slot_writes: u64 = 0,
        gpu_interrupt_slot_is_guest: bool = false,
        interrupt_callback_transaction: interrupt_callback_transaction.Ledger = .{},
        host_interrupt_callback_transaction: interrupt_callback_transaction.Ledger =
            .{ .domain = .xenia_host },
        executed_steps: u64 = 3_017_581_071,
    };
    var state = State{};
    observeInterruptCallbackSlot(&state, "SetInterruptCallback(FFFF0010, 00000000)");
    try std.testing.expectEqual(@as(u64, 0), state.interrupt_callback_transaction.registrations);
    try std.testing.expectEqual(
        @as(u32, 0xFFFF0010),
        state.host_interrupt_callback_transaction.callback_address,
    );

    observeInterruptCallbackSlot(&state, "SetInterruptCallback(821951F8, 40001F00)");
    try std.testing.expect(state.interrupt_callback_transaction.registrations != 0);
    try std.testing.expectEqual(
        @as(u32, 0x821951F8),
        state.interrupt_callback_transaction.callback_address,
    );
    try std.testing.expectEqual(
        @as(u32, 0x40001F00),
        state.interrupt_callback_transaction.user_data,
    );
}

test "controlled vector results are retained as diagnostic evidence" {
    const State = struct {
        audit_vectors: gpu.controlled_vectors.Suite = .{},
        executed_steps: u64 = 0,
    };
    var state = State{ .executed_steps = 400 };
    observeControlledVector(
        &state,
        "DIAGNOSTIC CONTROLLED VECTOR: vector=0 (color_clear) completion=YES " ++
            "state_programmed=YES reached=state_programmed",
    );
    try std.testing.expectEqual(
        gpu.controlled_vectors.Outcome.fell_short,
        state.audit_vectors.results[0].outcome,
    );
    try std.testing.expectEqual(
        gpu.controlled_vectors.Verdict.state_programmed,
        state.audit_vectors.results[0].reached.?,
    );

    state.executed_steps = 500;
    observeControlledVector(
        &state,
        "DIAGNOSTIC CONTROLLED VECTOR: vector=4 (resolve_to_memory) " ++
            "completion=YES reached=resolved_to_guest_memory",
    );
    try std.testing.expectEqual(
        gpu.controlled_vectors.Outcome.skipped_prerequisite,
        state.audit_vectors.results[4].outcome,
    );
    try std.testing.expectEqual(@as(usize, 1), state.audit_vectors.summary().run);
    try std.testing.expectEqual(@as(usize, 1), state.audit_vectors.summary().skipped);
}

test "attached callback log preserves admission scope and real delivery times" {
    const State = struct {
        executed_steps: u64 = 100,
        gpu_packet_census: gpu.packet_census.Ledger = .{},
        monotone_witness: monotone_witness.Ledger = .{},
        interrupt_callback_transaction: interrupt_callback_transaction.Ledger = .{ .callback_address = 0x821951F8 },
        audit_interrupts: gpu.interrupt_effect.Ledger = .{},
    };
    var state = State{};
    state.monotone_witness.state(.graphics_interrupt_dispatches, .rosette_tracepoint, 128, 90);
    const enter = "ROSETTE INTERRUPT DISPATCH: enter id=3 callback=821951F8 source=0 cpu=2 outstanding=1";
    observeEmulatorPacketCensus(&state, enter);
    observeInterruptCallbackTransaction(&state, enter);
    state.executed_steps = 150;
    const leave = "ROSETTE INTERRUPT DISPATCH: leave id=3 callback=821951F8 entered=3 returned=3 outstanding=0";
    observeEmulatorPacketCensus(&state, leave);
    observeInterruptCallbackTransaction(&state, leave);
    try std.testing.expectEqual(@as(u64, 128), state.monotone_witness.floor(.graphics_interrupt_dispatches).?);
    try std.testing.expectEqual(@as(u64, 3), state.monotone_witness.floor(.interrupt_executor_entries).?);
    try std.testing.expectEqual(@as(usize, 0), state.monotone_witness.summary().unexplained);
    try std.testing.expectEqual(@as(usize, 1), state.audit_interrupts.count);
    const delivery = state.audit_interrupts.retained()[0];
    try std.testing.expectEqual(@as(u64, 100), delivery.entered_step);
    try std.testing.expectEqual(@as(u64, 150), delivery.returned_step);
    try std.testing.expect(!delivery.has(.gpu_event));
    state.executed_steps = 200;
    observeEmulatorPacketCensus(&state, "ROSETTE PACKET CENSUS: packets=19 interrupt_packets=0 event_write_packets=0");
    try std.testing.expectEqual(@as(u64, 19), state.monotone_witness.floor(.pm4_packets_all_types).?);
    try std.testing.expect(state.monotone_witness.floor(.pm4_packets_consumed) == null);
}
