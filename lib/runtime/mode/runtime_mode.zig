const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

/// Runtime execution mode
pub const RuntimeMode = enum {
    /// Strict mode: stop on architectural or ABI mismatch
    strict,
    /// Diagnostic mode: record and optionally recover once
    diagnostic,
    /// Compatibility mode: apply explicitly documented application-specific workarounds
    compatibility,
};

/// Runtime mode configuration
pub const RuntimeModeConfig = struct {
    /// Current runtime mode
    mode: RuntimeMode = .strict,

    /// Maximum number of semantic repairs allowed in diagnostic mode
    max_repairs: u64 = 1,

    /// Whether to log diagnostic information
    log_diagnostics: bool = true,

    /// Whether to apply compatibility workarounds
    apply_workarounds: bool = false,

    /// Repair counter per repair type
    repair_counts: std.AutoHashMap([]const u8, u64),

    /// Allocator
    allocator: std.mem.Allocator,

    /// Initialize runtime mode configuration
    pub fn init(allocator: std.mem.Allocator) RuntimeModeConfig {
        return .{
            .repair_counts = std.AutoHashMap([]const u8, u64).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize runtime mode configuration
    pub fn deinit(self: *RuntimeModeConfig) void {
        var iter = self.repair_counts.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.repair_counts.deinit();
    }

    /// Set runtime mode
    pub fn setMode(self: *RuntimeModeConfig, mode: RuntimeMode) void {
        self.mode = mode;
    }

    /// Check if semantic repair is allowed
    pub fn allowRepair(self: *RuntimeModeConfig, repair_type: []const u8) bool {
        return switch (self.mode) {
            .strict => false,
            .diagnostic => {
                const count = self.repair_counts.get(repair_type) orelse 0;
                return count < self.max_repairs;
            },
            .compatibility => self.apply_workarounds,
        };
    }

    /// Record a semantic repair
    pub fn recordRepair(self: *RuntimeModeConfig, repair_type: []const u8) !void {
        const key = try self.allocator.dupe(u8, repair_type);
        errdefer self.allocator.free(key);

        const result = try self.repair_counts.getOrPut(key);
        if (!result.found_existing) {
            result.value_ptr.* = 0;
        } else {
            self.allocator.free(key);
        }

        result.value_ptr.* +|= 1;

        if (self.log_diagnostics) {
            machoCapturePrint(
                "runtime: semantic repair performed: type={s} count={d}/{d} mode={s}\n",
                .{ repair_type, result.value_ptr.*, self.max_repairs, @tagName(self.mode) },
            );
        }
    }

    /// Get repair count for a type
    pub fn getRepairCount(self: *const RuntimeModeConfig, repair_type: []const u8) u64 {
        return self.repair_counts.get(repair_type) orelse 0;
    }

    /// Get total repair count
    pub fn getTotalRepairCount(self: *const RuntimeModeConfig) u64 {
        var total: u64 = 0;
        var iter = self.repair_counts.valueIterator();
        while (iter.next()) |count| {
            total +|= count.*;
        }
        return total;
    }

    /// Reset repair counts
    pub fn resetRepairCounts(self: *RuntimeModeConfig) void {
        var iter = self.repair_counts.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.repair_counts.clearRetainingCapacity();
    }

    /// Log summary
    pub fn logSummary(self: *const RuntimeModeConfig) void {
        machoCapturePrint(
            "runtime: mode={s} max_repairs={d} total_repairs={d}\n",
            .{ @tagName(self.mode), self.max_repairs, self.getTotalRepairCount() },
        );

        if (self.repair_counts.count() > 0) {
            machoCapturePrint("runtime: repair counts:\n", .{});
            var iter = self.repair_counts.iterator();
            while (iter.next()) |entry| {
                machoCapturePrint("  {s}: {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }
    }
};

/// Global runtime mode configuration
var global_runtime_mode: ?RuntimeModeConfig = null;
var runtime_mode_initialized: bool = false;

/// Get global runtime mode configuration
pub fn getGlobalRuntimeMode() ?*RuntimeModeConfig {
    if (!runtime_mode_initialized) return null;
    return &global_runtime_mode.?;
}

/// Initialize global runtime mode configuration
pub fn initGlobalRuntimeMode(allocator: std.mem.Allocator, mode: RuntimeMode) !void {
    if (runtime_mode_initialized) return;

    global_runtime_mode = RuntimeModeConfig.init(allocator);
    global_runtime_mode.?.setMode(mode);

    runtime_mode_initialized = true;
}

/// Shutdown global runtime mode configuration
pub fn shutdownGlobalRuntimeMode() void {
    if (!runtime_mode_initialized) return;

    if (global_runtime_mode) |*config| {
        config.deinit();
    }
    global_runtime_mode = null;
    runtime_mode_initialized = false;
}

/// Check if semantic repair is allowed (global)
pub fn allowGlobalRepair(repair_type: []const u8) bool {
    const config = getGlobalRuntimeMode() orelse return false;
    return config.allowRepair(repair_type);
}

/// Record a semantic repair (global)
pub fn recordGlobalRepair(repair_type: []const u8) !void {
    const config = getGlobalRuntimeMode() orelse return error.NotInitialized;
    try config.recordRepair(repair_type);
}
