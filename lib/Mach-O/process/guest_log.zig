//! Guest logging and profile accounting methods.
//! Extracted from MachOState (process.zig) to reduce file size.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const startup_observer = @import("diagnostics").startup_observer;
const constants = @import("../constants.zig");
const utils = @import("../utils.zig");

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
        _ = hostWriteFdAll(self.guest_log_mirror_fd, prefix);
        _ = hostWriteFdAll(self.guest_log_mirror_fd, message);
        if (message.len == 0 or message[message.len - 1] != '\n') {
            _ = hostWriteFdAll(self.guest_log_mirror_fd, "\n");
        }
    }
    self.guest_log_line_count +|= 1;
    return true;
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
