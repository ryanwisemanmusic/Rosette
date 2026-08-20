//! import-handler — Guest import dispatch and routing library.
//!
//! Extracted from MachOState (lib/Mach-O/process.zig) to make the import
//! dispatch logic independently testable and maintainable.
//!
//! ImportHandler owns primitive dispatch accounting. `dispatch.zig` owns the
//! route cache policy, compatibility contracts, cooperative import boundaries,
//! unresolved-symbol analysis, and guest-exit callback sequencing. MachOState
//! retains state ownership and exposes these operations through function
//! aliases.
//!
//! Note: This module deliberately does NOT import the `primitive` module,
//! to avoid dependency issues with different build paths (build.zig vs.
//! Makefile zig build-exe). All primitive-specific operations are passed
//! through opaque callbacks.

const std = @import("std");

pub const dispatch = @import("dispatch.zig");

/// Callbacks for MachOState-specific operations needed for primitive dispatch.
/// Uses an opaque context pointer so that the parent (e.g. MachOState)
/// can pass `self` without closure allocation.
pub const PrimitiveDispatchCallbacks = struct {
    ctx: *anyopaque,

    /// Match an import name against the primitive handler registry.
    /// Returns null if no handler matches.
    matchSymbol: *const fn (ctx: *anyopaque, name: []const u8) ?*const anyopaque,

    /// Call the matched handler with a slot and context pointer.
    /// Returns a u8 representing the result enum (0=handled, 1=handled_void,
    /// 2=unsupported, 3=fallback, 4=control_transferred).
    callHandler: *const fn (ctx: *anyopaque, slot: u32, handler: *const anyopaque) u8,

    /// Read a guest register by ABI index (0=rdi, 1=rsi, 2=rdx, 3=rcx, 4=r8, 5=r9).
    readRegister: *const fn (ctx: *anyopaque, index: u8) u64,

    /// Read the current return value (rax) after the handler has run.
    readResult: *const fn (ctx: *const anyopaque) u64,
};

/// Callbacks for logging primitive dispatch events.
/// Uses a pre-formatted string callback to avoid comptime/anytype
/// issues with function pointer types.
pub const PrimitiveLogCallbacks = struct {
    ctx: *anyopaque,

    /// Log a pre-formatted line of text.
    logLine: *const fn (ctx: *anyopaque, text: []const u8) void,
};

/// Outcome of a primitive dispatch attempt.
pub const PrimitiveOutcome = union(enum) {
    handled: u64,
    handled_void,
    control_transferred,
    unhandled,
};

/// Tracks primitive dispatch statistics and provides dispatch routing.
/// Owns the dispatch-count maps and hit counter so they can be tested
/// independently of MachOState.
pub const ImportHandler = struct {
    allocator: std.mem.Allocator,
    primitive_dispatch_hits: u64 = 0,
    primitive_dispatch_counts: std.StringHashMap(u64),
    primitive_dispatch_logged: std.AutoHashMap(u64, void),

    pub fn init(allocator: std.mem.Allocator) ImportHandler {
        return .{
            .allocator = allocator,
            .primitive_dispatch_counts = std.StringHashMap(u64).init(allocator),
            .primitive_dispatch_logged = std.AutoHashMap(u64, void).init(allocator),
        };
    }

    pub fn deinit(self: *ImportHandler) void {
        self.primitive_dispatch_counts.deinit();
        self.primitive_dispatch_logged.deinit();
    }

    pub fn reset(self: *ImportHandler) void {
        self.primitive_dispatch_hits = 0;
        self.primitive_dispatch_counts.clearRetainingCapacity();
        self.primitive_dispatch_logged.clearRetainingCapacity();
    }

    /// Attempt to dispatch an import through the primitive builtin handler
    /// registry. Returns `.unhandled` if no handler matches or the handler
    /// returns `.unsupported`/`.fallback`.
    ///
    /// Uses opaque callbacks for all primitive-specific operations so that
    /// this module has no dependency on the `primitive` module.
    pub fn tryPrimitiveDispatch(
        self: *ImportHandler,
        import_name: []const u8,
        cb: PrimitiveDispatchCallbacks,
        log_cb: PrimitiveLogCallbacks,
    ) PrimitiveOutcome {
        const handler = cb.matchSymbol(cb.ctx, import_name) orelse return .unhandled;
        const slot: u32 = 0;
        const result_byte = cb.callHandler(cb.ctx, slot, handler);

        const action = switch (result_byte) {
            0 => "handled",
            1 => "handled_void",
            // These are not final import failures: the caller immediately
            // continues through the authoritative legacy handler chain. Name
            // the transition rather than making a successful fallback look
            // like an unresolved primitive-library defect.
            2 => "declined_to_legacy",
            3 => "requested_legacy_fallback",
            4 => "control_transferred",
            else => "unknown",
        };

        const action_u8: u8 = result_byte;
        const name_hash = std.hash_map.hashString(import_name);
        const pair_key = name_hash ^ (@as(u64, action_u8) << 56);
        if (!self.primitive_dispatch_logged.contains(pair_key)) {
            self.primitive_dispatch_logged.put(pair_key, {}) catch {};
            const log_text = std.fmt.allocPrint(self.allocator, "primitive lib: slot={d} import={s} action={s}\n", .{ slot, import_name, action }) catch "";
            defer if (log_text.len > 0) self.allocator.free(log_text);
            if (log_text.len > 0) {
                log_cb.logLine(log_cb.ctx, log_text);
            }
        }

        // Track count for this import name
        const gop = self.primitive_dispatch_counts.getOrPut(import_name) catch
            return switch (result_byte) {
                0 => .{ .handled = cb.readResult(cb.ctx) },
                1 => .handled_void,
                4 => .control_transferred,
                else => .unhandled,
            };
        if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;

        return switch (result_byte) {
            0 => .{ .handled = cb.readResult(cb.ctx) },
            1 => .handled_void,
            4 => .control_transferred,
            else => .unhandled,
        };
    }

    /// Write primitive dispatch totals to the log.
    pub fn dumpTotals(self: *const ImportHandler, log_cb: PrimitiveLogCallbacks) void {
        if (self.primitive_dispatch_counts.count() == 0) return;
        const header = std.fmt.allocPrint(self.allocator, "primitive lib: === totals ===\n", .{}) catch return;
        defer self.allocator.free(header);
        log_cb.logLine(log_cb.ctx, header);

        var iter = self.primitive_dispatch_counts.iterator();
        while (iter.next()) |entry| {
            const line = std.fmt.allocPrint(self.allocator, "primitive lib:   {s}: {d} dispatch(s)\n", .{ entry.key_ptr.*, entry.value_ptr.* }) catch continue;
            log_cb.logLine(log_cb.ctx, line);
            self.allocator.free(line);
        }

        const footer = std.fmt.allocPrint(self.allocator, "primitive lib: === end totals ===\n", .{}) catch return;
        defer self.allocator.free(footer);
        log_cb.logLine(log_cb.ctx, footer);
    }
};

test {
    var handler = ImportHandler.init(std.testing.allocator);
    defer handler.deinit();
    try std.testing.expectEqual(@as(u64, 0), handler.primitive_dispatch_hits);
    try std.testing.expectEqual(@as(usize, 0), handler.primitive_dispatch_counts.count());
}
