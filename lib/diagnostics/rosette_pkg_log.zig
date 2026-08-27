//! Package contract verification log for `.rosette/rosette-pkg.log`.
//!
//! At process startup this module imports every Xenia contract package and calls
//! `contractIsWellFormed()` on each. The results are written to the per-run log
//! file and, on failure, also piped to stderr so that the route wrapper captures
//! them in `rosette-runtime.log`.
//!
//! The log file is the detailed record: each contract gets a line with its
//! name, the verdict, and any diagnostic context. The stderr path is the
//! short-circuit that ensures failures are never silently buried in a detail
//! log nobody reads during an active session.
//!
//! ## What this module is not
//!
//! * It is not a contract. It holds no Xbox 360 facts; every fact it checks
//!   lives in the packages under `pkg/common/xenia/`.
//! * It is not a gate. A contract failure does not prevent the run from
//!   starting — it records the violation so that later symptoms can be traced
//!   to a precondition that was already known to be broken.
//! * It does not allocate beyond what the file open requires. The check is a
//!   sequence of pure boolean calls with no heap involvement.

const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

// ── Contract imports (provided via build.zig addImport) ────────────────────
const mount_contract = @import("xenia_mount_contract");
const kernel_object_contract = @import("xenia_kernel_object_contract");
const texture_contract = @import("xenia_texture_contract");
const io_completion_contract = @import("xenia_io_completion_contract");
const user_contract = @import("xenia_user_contract");
const shader_contract = @import("xenia_shader_contract");
const render_target_contract = @import("xenia_render_target_contract");
const audio_contract = @import("xenia_audio_contract");
const input_contract = @import("xenia_input_contract");
const timer_contract = @import("xenia_timer_contract");
const register_map = @import("xenos_register_map");
const kernel_export_map = @import("xenia_kernel_export_map");
const vd_ring_contract = @import("xenia_vd_ring_contract");
const pm4_contract = @import("xenia_pm4_contract");
const vd_swap_contract = @import("xenia_vd_swap_contract");
const claim_reconciliation_contract = @import("xenia_claim_reconciliation_contract");
const interrupt_callback_contract = @import("xenia_interrupt_callback_contract");
const graphics_health_contract = @import("xenia_graphics_health_contract");
const application_controller_contract = @import("xenia_application_controller_contract");
const application_framework_contract = @import("application_framework_contract");
const xex_format = @import("xenia_xex_format");
const notification_contract = @import("xenia_notification_contract");
const log_ring_contract = @import("xenia_log_ring_contract");
const xthread_contract = @import("xenia_xthread_contract");
const vfs_device_contract = @import("xenia_vfs_device_contract");
const ob_contract = @import("xenia_ob_contract");
const config_schema = @import("xenia_config_schema");
const vendor_library_contract = @import("vendor_library_contract");

// ── Route-specific contract imports ────────────────────────────────────────
const graphics_contract = @import("xenia_graphics_contract");
const surface_path_contract = @import("xenia_surface_path_contract");

// ── Contract registry ──────────────────────────────────────────────────────

const ContractCheck = struct {
    name: []const u8,
    checkFn: *const fn () bool,
};

const all_contracts = [_]ContractCheck{
    .{ .name = "mount-contract", .checkFn = mount_contract.contractIsWellFormed },
    .{ .name = "kernel-object-contract", .checkFn = kernel_object_contract.contractIsWellFormed },
    .{ .name = "texture-contract", .checkFn = texture_contract.contractIsWellFormed },
    .{ .name = "io-completion-contract", .checkFn = io_completion_contract.contractIsWellFormed },
    .{ .name = "user-contract", .checkFn = user_contract.contractIsWellFormed },
    .{ .name = "shader-contract", .checkFn = shader_contract.contractIsWellFormed },
    .{ .name = "render-target-contract", .checkFn = render_target_contract.contractIsWellFormed },
    .{ .name = "audio-contract", .checkFn = audio_contract.contractIsWellFormed },
    .{ .name = "input-contract", .checkFn = input_contract.contractIsWellFormed },
    .{ .name = "timer-contract", .checkFn = timer_contract.contractIsWellFormed },
    .{ .name = "register-map", .checkFn = register_map.contractIsWellFormed },
    .{ .name = "kernel-export-map", .checkFn = kernel_export_map.contractIsWellFormed },
    .{ .name = "vd-ring-contract", .checkFn = vd_ring_contract.contractIsWellFormed },
    .{ .name = "pm4-contract", .checkFn = pm4_contract.contractIsWellFormed },
    .{ .name = "vd-swap-contract", .checkFn = vd_swap_contract.contractIsWellFormed },
    .{ .name = "claim-reconciliation-contract", .checkFn = claim_reconciliation_contract.contractIsWellFormed },
    .{ .name = "interrupt-callback-contract", .checkFn = interrupt_callback_contract.contractIsWellFormed },
    .{ .name = "graphics-health-contract", .checkFn = graphics_health_contract.contractIsWellFormed },
    .{ .name = "application-controller-contract", .checkFn = application_controller_contract.contractIsWellFormed },
    .{ .name = "application-framework-contract", .checkFn = application_framework_contract.contractIsWellFormed },
    .{ .name = "xex-format", .checkFn = xex_format.contractIsWellFormed },
    .{ .name = "notification-contract", .checkFn = notification_contract.contractIsWellFormed },
    .{ .name = "log-ring-contract", .checkFn = log_ring_contract.contractIsWellFormed },
    .{ .name = "xthread-contract", .checkFn = xthread_contract.contractIsWellFormed },
    .{ .name = "vfs-device-contract", .checkFn = vfs_device_contract.contractIsWellFormed },
    .{ .name = "ob-contract", .checkFn = ob_contract.contractIsWellFormed },
    .{ .name = "config-schema", .checkFn = config_schema.contractIsWellFormed },
    .{ .name = "graphics-contract", .checkFn = graphics_contract.contractIsWellFormed },
    .{ .name = "surface-path-contract", .checkFn = surface_path_contract.contractIsWellFormed },
    .{ .name = "vendor-library-contract", .checkFn = vendor_library_contract.contractIsWellFormed },
};

// ── Logger ─────────────────────────────────────────────────────────────────

pub const Logger = struct {
    fd: i32 = -1,
    failure_count: u32 = 0,

    /// Open `.rosette/rosette-pkg.log` and run every contract check.
    ///
    /// Failures are written both to the log file (with detail) and to stderr
    /// (so the route wrapper captures them in `rosette-runtime.log`).
    /// The caller must call `deinit()` to close the file descriptor.
    pub fn open(self: *Logger, allocator: std.mem.Allocator) void {
        const root = routeRoot() orelse return;
        const path = std.fs.path.join(allocator, &.{ root, ".rosette", "rosette-pkg.log" }) catch return;
        defer allocator.free(path);

        const directory = std.fs.path.dirname(path) orelse return;
        makePathRecursive(allocator, directory) catch return;

        const path_z = allocator.dupeZ(u8, path) catch return;
        defer allocator.free(path_z);

        const fd = c.open(path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
        if (fd < 0) return;
        self.close();
        self.fd = fd;

        self.writeAll("# Rosette Package Contract Log\n");
        self.writeAll("# Checks every common Xenia contract at startup.\n");
        self.writeAll("# Failures are also piped to rosette-runtime.log.\n\n");

        self.runChecks();
    }

    pub fn close(self: *Logger) void {
        if (self.fd >= 0) _ = c.close(self.fd);
        self.fd = -1;
    }

    fn runChecks(self: *Logger) void {
        self.writeAll("=== Contract Verification ===\n\n");

        for (all_contracts) |contract| {
            const passed = contract.checkFn();
            self.writeContractResult(contract.name, passed);
            if (!passed) {
                self.failure_count +|= 1;
                self.emitFailureToStderr(contract.name);
            }
        }

        self.writeKernelExportSurface();

        self.writeAll("\n");
        var summary_buf: [256]u8 = undefined;
        const summary = std.fmt.bufPrint(
            &summary_buf,
            "=== Summary: {d} contracts checked, {d} FAILED ===\n",
            .{ all_contracts.len, self.failure_count },
        ) catch return;
        self.writeAll(summary);
    }

    /// Record that the kernel export tables are present and resolvable.
    ///
    /// A `contractIsWellFormed()` pass says the tables are sorted; it does not
    /// say the binary actually carries 2913 entries or that a lookup returns a
    /// name. This section performs real lookups so the log answers "does this
    /// build know the kernel ordinals" directly, rather than by inference.
    ///
    /// The ordinals chosen are the ones the GPU bring-up frontier depends on:
    /// if `VdInitializeRingBuffer` cannot be named here, nothing downstream can
    /// name it either.
    fn writeKernelExportSurface(self: *Logger) void {
        self.writeAll("\n=== Kernel Export Surface ===\n\n");

        var line_buf: [256]u8 = undefined;
        const totals = std.fmt.bufPrint(
            &line_buf,
            "[INFO] ordinals resolvable: xboxkrnl={d} xam={d} xbdm={d} total={d}\n",
            .{
                kernel_export_map.xboxkrnl_exports.len,
                kernel_export_map.xam_exports.len,
                kernel_export_map.xbdm_exports.len,
                kernel_export_map.xboxkrnl_exports.len +
                    kernel_export_map.xam_exports.len +
                    kernel_export_map.xbdm_exports.len,
            },
        ) catch return;
        self.writeAll(totals);

        // Live lookups, not a claim about the table's size.
        const probes = [_]struct { ordinal: u16, expected: []const u8 }{
            .{ .ordinal = 0x1C2, .expected = "VdInitializeEngines" },
            .{ .ordinal = 0x1C3, .expected = "VdInitializeRingBuffer" },
            .{ .ordinal = 0x1B6, .expected = "VdEnableRingBufferRPtrWriteBack" },
            .{ .ordinal = 0x1D5, .expected = "VdSetGraphicsInterruptCallback" },
            .{ .ordinal = 0x25B, .expected = "VdSwap" },
        };
        for (probes) |probe| {
            const resolved = kernel_export_map.nameOf(.xboxkrnl, probe.ordinal);
            const ok = resolved != null and std.mem.eql(u8, resolved.?, probe.expected);
            var probe_buf: [256]u8 = undefined;
            const line = std.fmt.bufPrint(
                &probe_buf,
                "[{s}] xboxkrnl 0x{X:0>4} -> {s}\n",
                .{
                    if (ok) "PASS" else "FAIL",
                    probe.ordinal,
                    resolved orelse "<unpublished>",
                },
            ) catch continue;
            self.writeAll(line);
            if (!ok) {
                self.failure_count +|= 1;
                self.emitFailureToStderr("kernel-export-map lookup");
            }
        }
    }

    fn writeContractResult(self: *Logger, name: []const u8, passed: bool) void {
        var line_buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(
            &line_buf,
            "[{s}] {s}\n",
            .{ if (passed) "PASS" else "FAIL", name },
        ) catch return;
        self.writeAll(line);

        if (!passed) {
            var detail_buf: [512]u8 = undefined;
            const detail = std.fmt.bufPrint(
                &detail_buf,
                "  ** VIOLATION: {s}.contractIsWellFormed() returned false **\n" ++
                    "  This contract's compile-time invariants are broken.\n" ++
                    "  The runtime may encounter undefined behaviour attributed to this module.\n",
                .{name},
            ) catch return;
            self.writeAll(detail);
        }
    }

    /// Write a contract failure to stderr so the route wrapper captures it
    /// in `rosette-runtime.log`.
    fn emitFailureToStderr(self: *Logger, name: []const u8) void {
        _ = self;
        var line_buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(
            &line_buf,
            "ROSETTE PKG VIOLATION: {s}.contractIsWellFormed() returned false\n",
            .{name},
        ) catch return;
        writeAllFd(c.STDERR_FILENO, line);
    }

    fn writeAll(self: *Logger, bytes: []const u8) void {
        if (self.fd < 0) return;
        var written: usize = 0;
        while (written < bytes.len) {
            const result = c.write(self.fd, bytes.ptr + written, bytes.len - written);
            if (result <= 0) return;
            written += @intCast(result);
        }
    }
};

// ── Helpers ────────────────────────────────────────────────────────────────

fn writeAllFd(fd: i32, bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const result = c.write(fd, bytes.ptr + written, bytes.len - written);
        if (result <= 0) return;
        written += @intCast(result);
    }
}

fn routeRoot() ?[]const u8 {
    const names = [_][*:0]const u8{
        "ROSETTE_TRACE_ROOT",
        "ROSETTE_ROUTE_ROOT",
        "ROSETTE_CALLER_CWD",
        "PWD",
    };
    for (names) |name| {
        const raw = c.getenv(name) orelse continue;
        const value = std.mem.span(raw);
        if (value.len != 0) return value;
    }
    return null;
}

fn makePathRecursive(allocator: std.mem.Allocator, raw_path: []const u8) !void {
    if (raw_path.len == 0) return;
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);
    if (raw_path[0] == '/') try current.append(allocator, '/');
    var parts = std.mem.splitScalar(u8, raw_path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (current.items.len > 1 and current.items[current.items.len - 1] != '/') try current.append(allocator, '/');
        try current.appendSlice(allocator, part);
        const path_z = try allocator.dupeZ(u8, current.items);
        defer allocator.free(path_z);
        if (c.mkdir(path_z.ptr, 0o755) != 0 and c.access(path_z.ptr, c.F_OK) != 0) return error.MakePathFailed;
    }
}

// ── Tests ──────────────────────────────────────────────────────────────────

test "all contracts report well-formed" {
    // Every contract must pass at comptime-defined invariants.
    for (all_contracts) |contract| {
        try std.testing.expect(contract.checkFn());
    }
}

test "contract count is non-zero" {
    try std.testing.expect(all_contracts.len > 0);
}

test "logger failure_count starts at zero" {
    const logger = Logger{};
    try std.testing.expectEqual(@as(u32, 0), logger.failure_count);
}
