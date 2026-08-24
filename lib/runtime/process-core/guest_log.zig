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
const guest_critical_section = @import("diagnostics").guest_critical_section;
const guest_module_map = @import("diagnostics").guest_module_map;
const guest_wait_liveness = @import("diagnostics").guest_wait_liveness;
const deferred_work = @import("diagnostics").deferred_work;
const deadlock_predictor = @import("diagnostics").deadlock_predictor;
const bringup_failure = @import("diagnostics").bringup_failure;
const wait_audit = @import("diagnostics").wait_audit;
const guest_exception_ledger = @import("diagnostics").guest_exception_ledger;
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
    // Compiler failures can cross the guest log boundary before they become a
    // null-function or no-progress symptom. The ready compiler keeps this
    // recognizer cheap and inactive for non-Xenia targets.
    if (comptime @hasDecl(@TypeOf(self.*), "observeReadyCompilerText")) {
        self.observeReadyCompilerText(message);
    }
    observePreflightGuestLog(self, message);
    observeXeniaPipelineGuestLog(self, message);
    observeGpuBootstrapGuestLog(self, message);
    observeXeniaGpuHandoffGuestLog(self, message);
    observeImportBindingAudit(self, message);
    observeGuestEventSignal(self, message);
    observeLivelockWaits(self, message);
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
) void {
    if (comptime !@hasField(@TypeOf(self.*), "wait_audit")) return;
    if (object == 0) return;
    const handle: u32 = parseFixedWidthHexAfter(message, "handle=", sync_object_field_width) orelse 0;
    const type_code: u32 = parseDecimalAfterU32(message, "type=") orelse 0;
    self.wait_audit.observe(
        object,
        operation,
        self.active_guest_thread,
        handle,
        type_code,
        self.executed_steps,
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

const LivelockOperation = struct {
    op: livelock_predictor.Operation,
    object: u64,
};

fn livelockOperation(self: anytype, message: []const u8) ?LivelockOperation {
    // Detailed pre-wait line: remember the object for the coming result line.
    // The result line alone cannot name the object against a pre-change binary.
    if (std.mem.indexOf(u8, message, "KeWaitForSingleObject tid=") != null) {
        // This line names the object *both* ways, which is the only place the
        // two are stated together. Learning the pair here is what stops every
        // later line that prints only one of them from being attributed to a
        // second, non-existent object.
        if (comptime @hasField(@TypeOf(self.*), "sync_object_identity")) {
            const host = parseFixedWidthHexAfter(message, "obj_ptr=", sync_object_field_width) orelse 0;
            const console = parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width) orelse 0;
            self.sync_object_identity.observePair(host, console);
        }
        if (parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width)) |object| {
            self.livelock_pending_wait_object = canonicalSyncObject(self, object);
        } else if (parseFixedWidthHexAfter(message, "obj_ptr=", sync_object_field_width)) |object| {
            self.livelock_pending_wait_object = canonicalSyncObject(self, object);
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
    if (std.mem.indexOf(u8, message, "KeWaitForSingleObject result=") != null) {
        const result = parseHexAfter(message, "result=") orelse return null;
        const op: livelock_predictor.Operation = if (result == 0x102) .wait_timeout else .wait;
        const object: u64 = canonicalSyncObject(self, blk: {
            if (parseFixedWidthHexAfter(message, "guest_obj=", sync_object_field_width)) |value| break :blk value;
            if (parseFixedWidthHexAfter(message, "obj_ptr=", sync_object_field_width)) |value| break :blk value;
            break :blk self.livelock_pending_wait_object;
        });
        self.livelock_pending_wait_object = 0;
        if (object == 0) return null;
        auditSyncOperation(self, message, object, if (op == .wait_timeout) .wait_timeout else .wait);
        return .{ .op = op, .object = object };
    }
    if (std.mem.indexOf(u8, message, "DEBUG: xeKeSetEvent: ptr=") != null) {
        const object = parseHexAfter(message, "ptr=") orelse return null;
        if (object == 0) return null;
        const canonical = canonicalSyncObject(self, object);
        auditSyncOperation(self, message, canonical, .signal);
        return .{ .op = .set_event, .object = canonical };
    }
    // The generic `d>`-level export trace prints `KeReleaseSemaphore(<ptr>, ...)`
    // on every call; the fork's own instrumentation prints the same shape at
    // `i>` level with the object named. Either way the pointer is the first hex
    // token after the open paren.
    if (std.mem.indexOf(u8, message, "KeReleaseSemaphore(") != null) {
        const raw = firstHexAfterOpenParen(message, "KeReleaseSemaphore(") orelse return null;
        if (raw == 0) return null;
        const object = canonicalSyncObject(self, raw);
        auditSyncOperation(self, message, object, .signal);
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
pub fn observeGuestSyncObjects(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
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
        const object = canonicalSyncObject(self, parseHexAfter(message, "ptr=") orelse return);
        self.deadlock_predictor.observeNotify(
            object,
            deadlock_predictor.ObjectKind.event,
            self.active_guest_thread,
            self.executed_steps,
        );
        return;
    }
    if (std.mem.indexOf(u8, message, "KeReleaseSemaphore(") != null) {
        const object = canonicalSyncObject(self, parseHexAfter(message, "KeReleaseSemaphore(") orelse return);
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

/// Join the emulator's callback-missing import probe into the binding ledger.
///
/// The probe fires when the emulator decides a callback has gone missing, which
/// makes it look like a report of a binding failure. It is not: it reports what
/// the binding *is*, and in the observed run every field was healthy. Parsing it
/// is what turns "the emulator is worried" into "the emulator is worried about
/// something that is correct", which points at a completely different defect.
pub fn observeImportBindingProbe(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_import_binding")) return;
    if (std.mem.indexOf(u8, message, "callback-missing import probe") == null) return;
    const ordinal = parseHexAfter(message, "ordinal=") orelse return;
    if (ordinal > std.math.maxInt(u16)) return;
    self.gpu_import_binding.observe(
        @intCast(ordinal),
        std.mem.indexOf(u8, message, "value_committed=YES") != null,
        std.mem.indexOf(u8, message, "value_translated=YES") != null,
        @truncate(parseHexAfter(message, "value_word=") orelse 0),
        @truncate(parseHexAfter(message, "value_addr=") orelse 0),
        std.mem.indexOf(u8, message, "thunk_translated=YES") != null,
        @truncate(parseHexAfter(message, "thunk_addr=") orelse 0),
        @truncate(parseHexAfter(message, "thunk_w0=") orelse 0),
        @truncate(parseHexAfter(message, "thunk_w1=") orelse 0),
    );
}

/// Join the emulator's wait and set logging into the wait-liveness ledger.
///
/// `KeWaitForSingleObject result=00000000` is the single most common line in a
/// stalled run and the least informative one: it is returned both by a wait
/// that blocked and was released, and by a wait that was satisfied on arrival
/// and never blocked at all. The first is a working handshake; the second is a
/// spin that looks like a stall in whichever subsystem it belongs to. Only the
/// ratio separates them, so the ratio is what gets counted.
///
/// The emulator logs the result without the object's handle, so most waits
/// arrive unattributed and the ledger says so rather than inventing an owner
/// for them. Set lines do carry a handle and are recorded against it.
pub fn observeGuestWaitLiveness(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "guest_wait_liveness")) return;
    if (std.mem.indexOf(u8, message, "KeWaitForSingleObject result=")) |_| {
        const code = parseHexAfter(message, "KeWaitForSingleObject result=") orelse return;
        self.guest_wait_liveness.observeWait(
            0,
            guest_wait_liveness.WaitStatus.fromCode(@truncate(code)),
        );
        return;
    }
    if (std.mem.indexOf(u8, message, "xeKeSetEvent:") != null) {
        const handle = parseHexAfter(message, "handle=") orelse return;
        const already = std.mem.indexOf(u8, message, "was_signalled=1") != null;
        self.guest_wait_liveness.observeSet(@truncate(handle), already);
    }
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
        }
    }
}

fn parseDecimalAfter(message: []const u8, key: []const u8) ?u64 {
    const at = std.mem.indexOf(u8, message, key) orelse return null;
    const rest = message[at + key.len ..];
    const end = std.mem.indexOfNone(u8, rest, "0123456789") orelse rest.len;
    if (end == 0) return null;
    return std.fmt.parseInt(u64, rest[0..end], 10) catch null;
}

pub fn observeGpuBootstrapGuestLog(self: anytype, message: []const u8) void {
    const State = @TypeOf(self.*);
    if (comptime !@hasField(State, "gpu_bootstrap")) return;
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
    if (std.mem.indexOf(u8, message, "VDSWAP PATH: stage=packet_encoded") != null) {
        self.guest_vdswap_packet_encoded = true;
    }
    if (std.mem.indexOf(u8, message, "VDSWAP PATH: stage=completed") != null) {
        self.guest_vdswap_entry_completed = true;
    }
    for (steps) |candidate| {
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

    const marker = "DEBUG: REGISTER WRITE: CP_RB_WPTR";
    if (std.mem.indexOf(u8, message, marker) == null) return;
    const value = parseHexAfter(message, "CP_RB_WPTR = ") orelse
        parseHexAfter(message, "CP_RB_WPTR=") orelse return;
    const previous = self.gpu_ring_publication.last_value;
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
        return;
    }
    if (outcome == .repeated and tracker.repeats == 1) {
        machoCapturePrint(
            "macho-processor: gpu ring publication: {s}\n",
            .{tracker.verdict()},
        );
    }
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
    self.backend_diagnostics.noteMmapResult(succeeded, result, stage);
    machoCapturePrint(
        "macho-processor: x64 backend mmap result: attempt={d} succeeded={} result=0x{x} stage={s}\n",
        .{ self.backend_diagnostics.mmap_attempts_during_backend, succeeded, result, stage },
    );
}

pub fn noteBackendMprotect(self: anytype, route: []const u8, address: u64, length: u64, prot: u64, succeeded: bool) void {
    if (!self.backend_diagnostics.noteMprotectAttempt()) return;
    machoCapturePrint(
        "macho-processor: x64 backend mprotect #{d}: route={s} phase={s} step={d} address=0x{x} length={d} prot=0x{x} succeeded={}\n",
        .{ self.backend_diagnostics.mprotect_attempts_during_backend, route, @tagName(self.backend_diagnostics.phase), self.executed_steps, address, length, prot, succeeded },
    );
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
