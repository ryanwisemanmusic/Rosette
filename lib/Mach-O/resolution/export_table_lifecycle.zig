const std = @import("std");

pub const ExportTableState = enum(u8) {
    uninitialized,
    resolving,
    ready,
    deferred,
};

pub const InitializationPhase = enum(u8) {
    pre_initializers,
    initializers_in_progress,
    exports_resolved,
    running,
};

pub const ModuleClass = enum(u8) {
    normal,
    deferred_exports,
};

pub const VectorGrowthRequest = struct {
    vector_address: u64,
    needed_size: u32,
    element_size: u32,
    variable_name: [64]u8 = [_]u8{0} ** 64,
};

pub const ModuleExportProfile = struct {
    name_hint: []const u8 = "",
    class: ModuleClass = .normal,
    state: ExportTableState = .uninitialized,
    last_ordinal: u32 = 0,
    needed_size: u32 = 0,
    initializer_skips: u32 = 0,
    resolved_on_pass: u8 = 0,
};

pub const Lifecycle = struct {
    phase: InitializationPhase = .pre_initializers,
    modules: [8]ModuleExportProfile = [_]ModuleExportProfile{.{}} ** 8,
    module_count: usize = 0,
    deferred_resolutions: u32 = 0,
    deferred_initializers_skipped: u32 = 0,
    phase_transitions: u32 = 0,
    retry_pass: u8 = 0,
    growth_requests: [4]VectorGrowthRequest = [_]VectorGrowthRequest{.{ .vector_address = 0, .needed_size = 0, .element_size = 0 }} ** 4,
    growth_count: usize = 0,

    pub fn enterPhase(self: *Lifecycle, phase: InitializationPhase) void {
        if (self.phase == phase) return;
        self.phase = phase;
        self.phase_transitions += 1;
    }

    pub fn classifyModule(_: *Lifecycle, name_hint: []const u8) ModuleClass {
        if (name_hint.len == 0) return .normal;
        var buf: [64]u8 = undefined;
        var lower_buf: [64]u8 = undefined;
        const len = @min(name_hint.len, buf.len - 1);
        @memcpy(buf[0..len], name_hint[0..len]);
        const lower = std.ascii.lowerString(lower_buf[0..len], buf[0..len]);
        if (std.mem.indexOf(u8, lower, "xbdm") != null or
            std.mem.indexOf(u8, lower, "registerexport") != null or
            std.mem.indexOf(u8, lower, "xenia") != null)
        {
            return .deferred_exports;
        }
        return .normal;
    }

    pub fn findOrCreateModule(self: *Lifecycle, name_hint: []const u8) *ModuleExportProfile {
        for (0..self.module_count) |i| {
            const mod = &self.modules[i];
            if (std.mem.eql(u8, mod.name_hint, name_hint)) return mod;
        }
        if (self.module_count < self.modules.len) {
            const mod = &self.modules[self.module_count];
            mod.* = .{
                .name_hint = name_hint,
                .class = self.classifyModule(name_hint),
                .state = .uninitialized,
            };
            self.module_count += 1;
            return mod;
        }
        return &self.modules[0];
    }

    pub fn findOrCreateModuleForAddress(self: *Lifecycle, address: u64) *ModuleExportProfile {
        for (0..self.module_count) |i| {
            if (self.modules[i].last_ordinal > 0 and self.modules[i].needed_size > 0) {
                var match: bool = false;
                _ = &match;
            }
            _ = address;
        }
        if (self.module_count < self.modules.len) {
            const mod = &self.modules[self.module_count];
            mod.* = .{ .name_hint = "<export>" };
            self.module_count += 1;
            return mod;
        }
        return &self.modules[0];
    }

    pub fn recordOrdinalBounds(
        self: *Lifecycle,
        name_hint: []const u8,
        ordinal: u32,
        table_size: u32,
    ) bool {
        const mod = self.findOrCreateModule(name_hint);
        if (mod.state == .ready) return false;

        if (ordinal >= mod.needed_size) mod.needed_size = ordinal + 1;
        if (ordinal > mod.last_ordinal) mod.last_ordinal = ordinal;
        mod.initializer_skips += 1;
        self.deferred_resolutions += 1;

        if (mod.class == .deferred_exports) {
            if (mod.state == .uninitialized) {
                mod.state = .deferred;
                self.deferred_initializers_skipped += 1;
                std.debug.print(
                    "macho-processor: deferred export table classified module={s} as deferred_exports; will defer initializer and pre-populate vector before retry\n",
                    .{name_hint},
                );
                return true;
            }
            if (mod.state == .deferred) {
                std.debug.print(
                    "macho-processor: deferred export table module={s} still empty on retry pass {d}; will attempt vector growth\n",
                    .{ name_hint, self.retry_pass },
                );
                return true;
            }
        }

        if (mod.state == .uninitialized) {
            mod.state = .resolving;
            std.debug.print(
                "macho-processor: export table first bound for module={s} ordinal={d} size={d}; marking for resolution\n",
                .{ name_hint, ordinal, table_size },
            );
            return true;
        }

        return false;
    }

    pub fn requestVectorGrowth(
        self: *Lifecycle,
        vector_address: u64,
        needed_size: u32,
        element_size: u32,
        variable_name: []const u8,
    ) bool {
        for (0..self.growth_count) |i| {
            if (self.growth_requests[i].vector_address == vector_address) {
                if (needed_size > self.growth_requests[i].needed_size) {
                    self.growth_requests[i].needed_size = needed_size;
                }
                return true;
            }
        }
        if (self.growth_count < self.growth_requests.len) {
            var req = &self.growth_requests[self.growth_count];
            req.* = .{
                .vector_address = vector_address,
                .needed_size = needed_size,
                .element_size = element_size,
            };
            const name_len = @min(variable_name.len, req.variable_name.len - 1);
            @memcpy(req.variable_name[0..name_len], variable_name[0..name_len]);
            self.growth_count += 1;
            return true;
        }
        return false;
    }

    pub fn popGrowthRequests(self: *Lifecycle, buffer: []VectorGrowthRequest) usize {
        const count = @min(self.growth_count, buffer.len);
        for (0..count) |i| {
            buffer[i] = self.growth_requests[i];
        }
        self.growth_count = 0;
        return count;
    }

    pub fn onRetryPass(self: *Lifecycle, pass: u8) void {
        for (0..self.module_count) |i| {
            const mod = &self.modules[i];
            if (mod.state == .deferred) {
                mod.resolved_on_pass = pass;
                mod.state = .ready;
                std.debug.print(
                    "macho-processor: export table resolved on retry pass {d} for module={s} last_ordinal={d} needed_size={d}\n",
                    .{ pass, mod.name_hint, mod.last_ordinal, mod.needed_size },
                );
            }
        }
    }

    pub fn extractVectorName(expression: []const u8) ?[]const u8 {
        const suffix = ".size()";
        const suffix_pos = std.mem.lastIndexOf(u8, expression, suffix) orelse return null;
        if (suffix_pos < 1) return null;
        var start = suffix_pos;
        start -= 1;
        while (start > 0) {
            const c = expression[start - 1];
            if (!std.ascii.isAlphanumeric(c) and c != '_') break;
            start -= 1;
        }
        const name = expression[start..suffix_pos];
        if (name.len == 0 or name.len > 128) return null;
        return name;
    }

    pub fn logSummary(self: *const Lifecycle) void {
        if (self.deferred_resolutions == 0 and self.deferred_initializers_skipped == 0) return;
        std.debug.print(
            "macho-processor: export table lifecycle summary: modules={d} deferred={d} skips={d} phase_transitions={d}\n",
            .{ self.module_count, self.deferred_resolutions, self.deferred_initializers_skipped, self.phase_transitions },
        );
        for (0..self.module_count) |i| {
            const mod = self.modules[i];
            std.debug.print(
                "macho-processor:   module[{d}] name={s} class={s} state={s} last_ordinal={d} size={d} pass={d}\n",
                .{ i, mod.name_hint, @tagName(mod.class), @tagName(mod.state), mod.last_ordinal, mod.needed_size, mod.resolved_on_pass },
            );
        }
    }
};

test "export table lifecycle classifies deferred modules" {
    var lc = Lifecycle{};
    try std.testing.expectEqual(ModuleClass.deferred_exports, lc.classifyModule("xbdm_module"));
    try std.testing.expectEqual(ModuleClass.deferred_exports, lc.classifyModule("RegisterExport_xbdm"));
    try std.testing.expectEqual(ModuleClass.deferred_exports, lc.classifyModule("xenia_core"));
    try std.testing.expectEqual(ModuleClass.normal, lc.classifyModule("kernel32"));
}

test "export table lifecycle records ordinal bounds" {
    var lc = Lifecycle{};
    try std.testing.expect(lc.recordOrdinalBounds("xbdm_module", 10, 5));
    try std.testing.expectEqual(ModuleClass.deferred_exports, lc.modules[0].class);
    try std.testing.expectEqual(@as(u32, 1), lc.deferred_resolutions);
    try std.testing.expectEqual(@as(u32, 11), lc.modules[0].needed_size);
}

test "export table lifecycle records growth request" {
    var lc = Lifecycle{};
    try std.testing.expect(lc.requestVectorGrowth(0x1000, 10, 8, "xbdm_exports"));
    try std.testing.expectEqual(@as(usize, 1), lc.growth_count);
    try std.testing.expectEqual(@as(u64, 0x1000), lc.growth_requests[0].vector_address);
}

test "export table lifecycle extracts vector name from expression" {
    const expr = "export_entry->ordinal < xbdm_exports.size()";
    const name = Lifecycle.extractVectorName(expr) orelse @panic("expected name");
    try std.testing.expectEqualStrings("xbdm_exports", name);
}

test "export table lifecycle extracts complex expression" {
    const expr = "ordinal < xbdm_exports.size() && ordinal >= 0";
    const name = Lifecycle.extractVectorName(expr) orelse @panic("expected name");
    try std.testing.expectEqualStrings("xbdm_exports", name);
}

test "export table lifecycle phase transitions" {
    var lc = Lifecycle{};
    try std.testing.expectEqual(InitializationPhase.pre_initializers, lc.phase);
    lc.enterPhase(.initializers_in_progress);
    try std.testing.expectEqual(@as(u32, 1), lc.phase_transitions);
}
