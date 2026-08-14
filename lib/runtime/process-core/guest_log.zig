//! Guest logging and profile accounting methods.
//! Extracted from MachOState (process.zig) to reduce file size.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const macho_log = @import("dyld").event_log;
const gpu = @import("gpu");
const machoCapturePrint = macho_log.machoCapturePrint;
const startup_observer = @import("diagnostics").startup_observer;
const guest_critical_section = @import("diagnostics").guest_critical_section;
const preflight_lib = @import("preflight");
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

pub fn shouldSummarizeGuestLog(level: u8, message: []const u8) bool {
    if (level == 'F' or level == 'E' or level == 'e' or level == 'W' or level == 'w') return true;
    const markers = [_][]const u8{
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
    for (markers) |marker| {
        if (std.mem.indexOf(u8, message, marker) != null) return true;
    }
    return false;
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
    observePreflightGuestLog(self, message);
    observeXeniaPipelineGuestLog(self, message);
    observeGpuBootstrapGuestLog(self, message);
    observeXeniaGpuHandoffGuestLog(self, message);
    self.observeBackendGuestLog(message);
    const raw_char: u8 = @truncate(prefix_char_raw);
    const prefix_char: u8 = if (raw_char >= 0x20 and raw_char <= 0x7E) raw_char else '?';
    var prefix_buffer: [32]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buffer, "[xenia] {c}> ", .{prefix_char}) catch return false;

    if (!shouldSuppressRuntimeGuestLog(message)) {
        _ = hostWriteFdAll(self.diagnostic_output_fd, prefix);
        _ = hostWriteFdAll(self.diagnostic_output_fd, message);
        if (message.len == 0 or message[message.len - 1] != '\n') _ = hostWriteFdAll(self.diagnostic_output_fd, "\n");
    }
    if (self.macho_log.isOpen()) {
        var xenia_buffer: [4096]u8 = undefined;
        const xenia_line = std.fmt.bufPrint(&xenia_buffer, "{s}{s}", .{ prefix, message }) catch "";
        self.macho_log.captureLine(xenia_line);
    }
    if (self.summary_output_fd >= 0 and shouldSummarizeGuestLog(prefix_char, message)) {
        var step_buffer: [64]u8 = undefined;
        const step_prefix = std.fmt.bufPrint(&step_buffer, "step={d} ", .{self.executed_steps}) catch "";
        _ = hostWriteFdAll(self.summary_output_fd, step_prefix);
        _ = hostWriteFdAll(self.summary_output_fd, prefix);
        _ = hostWriteFdAll(self.summary_output_fd, message);
        if (message.len == 0 or message[message.len - 1] != '\n') _ = hostWriteFdAll(self.summary_output_fd, "\n");
    }

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
    }
    self.guest_log_line_count +|= 1;
    return true;
}

/// Write one mirrored guest line, adding the newline the guest may have omitted.
fn writeMirroredLine(self: anytype, prefix: []const u8, message: []const u8) void {
    _ = hostWriteFdAll(self.guest_log_mirror_fd, prefix);
    _ = hostWriteFdAll(self.guest_log_mirror_fd, message);
    if (message.len == 0 or message[message.len - 1] != '\n') {
        _ = hostWriteFdAll(self.guest_log_mirror_fd, "\n");
    }
}

/// Observe the guest-driven GPU bootstrap from the mirrored guest log.
///
/// The guest's own kernel-export tracing is the only place these calls are
/// visible to the runtime without instrumenting the host program, and a step the
/// guest never took leaves no other trace by construction. Matching on the
/// export name is the observation; the ordering and preconditions live in
/// `lib/gpu`, which is what turns "callback = 0" into "this step was never
/// reachable, and here is the one that blocked it".
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
    machoCapturePrint(
        "macho-processor: Xenia GPU handoff advanced: {s} -> {s} at step={d}\n",
        .{ @tagName(observation.previous), @tagName(observation.current), self.executed_steps },
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

        const host_virtual = self.xenia_memory_views.virtualHostAddress(address) orelse 0;
        const host_physical = self.xenia_memory_views.physicalAliasHostAddress(address) orelse 0;
        self.critical_section_watch_host_virtual = host_virtual;
        self.critical_section_watch_host_physical = host_physical;
        const virtual_armed = host_virtual != 0 and self.provenance_watch.watchPage(host_virtual, .declared);
        const physical_armed = host_physical != 0 and self.provenance_watch.watchPage(host_physical, .declared);

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
            "macho-processor: guest critical section aliases resolved: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} watch_virtual={s} watch_physical={s} initial_read={s} initial_state={s}; later clearing is attributed at the address Xenia actually writes\n",
            .{
                address,
                host_virtual,
                host_physical,
                if (virtual_armed or (host_virtual != 0 and self.provenance_watch.covers(host_virtual))) "armed" else "unavailable",
                if (physical_armed or (host_physical != 0 and self.provenance_watch.covers(host_physical))) "armed" else "unavailable",
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
        const host_virtual = if (address == self.critical_section_watch_base)
            self.critical_section_watch_host_virtual
        else
            self.xenia_memory_views.virtualHostAddress(address) orelse 0;
        const host_physical = if (address == self.critical_section_watch_base)
            self.critical_section_watch_host_physical
        else
            self.xenia_memory_views.physicalAliasHostAddress(address) orelse 0;
        const slot_offset = guest_critical_section.lock_count_offset;
        const virtual_writer = if (host_virtual != 0) self.memory_writes.lookup((host_virtual + slot_offset) & ~@as(u64, 7)) else null;
        const physical_writer = if (host_physical != 0) self.memory_writes.lookup((host_physical + slot_offset) & ~@as(u64, 7)) else null;
        const writer = virtual_writer orelse physical_writer;
        if (writer) |entry| {
            machoCapturePrint(
                "macho-processor: GUEST CRITICAL SECTION PRE-REPAIR CAUSAL WRITER: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} write_address=0x{x} previous=0x{x} value=0x{x} rip=0x{x} {s} step={d} thread=0x{x} kind={s}; this write destroyed the captured unlocked lock-count slot\n",
                .{ address, host_virtual, host_physical, entry.address, entry.previous_value, entry.value, entry.instruction_address, self.metadata.symbolLabel(entry.instruction_address), entry.step, entry.thread, @tagName(entry.kind) },
            );
        } else {
            machoCapturePrint(
                "macho-processor: GUEST CRITICAL SECTION PRE-REPAIR CAUSAL WRITER: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} writer=NOT_RETAINED; the exact-zero transition is proven by Xenia, but it arrived through a store path that did not commit bounded provenance\n",
                .{ address, host_virtual, host_physical },
            );
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
    const host_virtual = if (address == self.critical_section_watch_base)
        self.critical_section_watch_host_virtual
    else
        self.xenia_memory_views.virtualHostAddress(address) orelse 0;
    const host_physical = if (address == self.critical_section_watch_base)
        self.critical_section_watch_host_physical
    else
        self.xenia_memory_views.physicalAliasHostAddress(address) orelse 0;
    const bytes = if (host_virtual != 0)
        self.guestMemoryConst(host_virtual, critical_section.size_bytes)
    else
        null;
    if (bytes == null) {
        machoCapturePrint(
            "macho-processor: GUEST CRITICAL SECTION UNREADABLE: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} mapping_base=0x{x}; the Xbox address could not be resolved to readable translated backing\n",
            .{ address, host_virtual, host_physical, self.xenia_memory_views.mapping_base },
        );
        return;
    }
    const fields = critical_section.decode(bytes.?) orelse return;
    const state = critical_section.classify(fields);
    const virtual_writer = if (host_virtual != 0) self.memory_writes.lookup((host_virtual + critical_section.lock_count_offset) & ~@as(u64, 7)) else null;
    const physical_writer = if (host_physical != 0) self.memory_writes.lookup((host_physical + critical_section.lock_count_offset) & ~@as(u64, 7)) else null;
    const writer = virtual_writer orelse physical_writer;
    const ever_written = writer != null;
    const changed_since_registration = self.critical_section_initial_valid and
        !std.mem.eql(u8, &self.critical_section_initial_image, bytes.?[0..critical_section.size_bytes]);
    machoCapturePrint(
        "macho-processor: GUEST CRITICAL SECTION ZERO-OWNER CONTENTION: cs=0x{x} host_virtual=0x{x} host_physical=0x{x} state={s} lock_count={d} recursion={d} owner=0x{x} header(type=0x{x} signal=0x{x} flink=0x{x} blink=0x{x}) initial_valid={s} changed_since_registration={s} writer_retained={s} impossible={s}\n",
        .{
            address,
            host_virtual,
            host_physical,
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
    if (writer) |entry| {
        machoCapturePrint(
            "macho-processor: GUEST CRITICAL SECTION LAST WRITER: address=0x{x} previous=0x{x} value=0x{x} rip=0x{x} step={d} thread=0x{x} kind={s}; this is the producer that changed the lock-count/recursion slot after registration\n",
            .{ entry.address, entry.previous_value, entry.value, entry.instruction_address, entry.step, entry.thread, @tagName(entry.kind) },
        );
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
        self.gpu_ring_publication.observeGeometry(geometry);
        if (!before and self.gpu_ring_publication.published()) {
            machoCapturePrint(
                "macho-processor: gpu ring publication: an outstanding span appeared: rb_base=0x{x} rb_size=0x{x} read_ptr=0x{x} write_ptr=0x{x} span_dwords={d} of {d}\n",
                .{ geometry.base, geometry.size_bytes, geometry.read_pointer, geometry.write_pointer, geometry.spanDwords() orelse 0, geometry.sizeDwords() },
            );
            self.gpu_bootstrap.observe(.ring_write_pointer, self.executed_steps);
        }
    }

    const marker = "DEBUG: REGISTER WRITE: CP_RB_WPTR";
    if (std.mem.indexOf(u8, message, marker) == null) return;
    const value = parseHexAfter(message, "CP_RB_WPTR = ") orelse
        parseHexAfter(message, "CP_RB_WPTR=") orelse return;
    const previous = self.gpu_ring_publication.last_value;
    const outcome = self.gpu_ring_publication.observeWritePointer(value);
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
