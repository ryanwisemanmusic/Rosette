const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

pub const Confidence = enum {
    verified,
    modeled,
};

pub const Behavior = union(enum) {
    return_zero,
    preserve_rax,
    passthrough_rdi,
};

pub const Reason = enum {
    weak_import,
    sanitizer_annotation,
    optional_capability_probe,
    guest_code_cache_maintenance,
};

pub const Plan = struct {
    behavior: Behavior,
    reason: Reason,
    confidence: Confidence,
};

pub const Resolution = union(enum) {
    handled: u64,
    handled_void,
};

pub const Generated = struct {
    resolution: Resolution,
    confidence: Confidence,
    reason: Reason,
};

pub const Generator = struct {
    considered: u64 = 0,
    generated: u64 = 0,
    generated_weak: u64 = 0,
    generated_verified: u64 = 0,
    rejected_cpp: u64 = 0,
    rejected_unknown: u64 = 0,

    pub fn resolve(self: *Generator, symbol: []const u8, weak: bool, rdi: u64) ?Generated {
        self.considered += 1;
        const plan = generatePlan(symbol, weak) orelse {
            if (isCxxSymbol(symbol)) self.rejected_cpp += 1 else self.rejected_unknown += 1;
            return null;
        };
        self.generated += 1;
        if (plan.reason == .weak_import) self.generated_weak += 1;
        if (plan.confidence == .verified) self.generated_verified += 1;
        const resolution: Resolution = switch (plan.behavior) {
            .return_zero => .{ .handled = 0 },
            .preserve_rax => .handled_void,
            .passthrough_rdi => .{ .handled = rdi },
        };
        return .{ .resolution = resolution, .confidence = plan.confidence, .reason = plan.reason };
    }

    pub fn logSummary(self: *const Generator) void {
        machoCapturePrint(
            "macho-processor: smart stub generation: considered={d} generated={d} weak={d} verified={d} rejected_cpp={d} rejected_unknown={d}\n",
            .{
                self.considered,
                self.generated,
                self.generated_weak,
                self.generated_verified,
                self.rejected_cpp,
                self.rejected_unknown,
            },
        );
    }
};

pub fn generatePlan(symbol: []const u8, weak: bool) ?Plan {
    if (weak and !isCxxSymbol(symbol)) {
        return .{
            .behavior = .return_zero,
            .reason = .weak_import,
            .confidence = .modeled,
        };
    }
    if (std.mem.indexOf(u8, symbol, "sanitizer_annotate_contiguous_container") != null or
        std.mem.indexOf(u8, symbol, "sanitizer_annotate_double_ended_contiguous_container") != null)
    {
        return .{
            .behavior = .preserve_rax,
            .reason = .sanitizer_annotation,
            .confidence = .verified,
        };
    }
    if (std.mem.eql(u8, symbol, "_os_signpost_enabled") or
        std.mem.eql(u8, symbol, "_os_log_type_enabled") or
        std.mem.eql(u8, symbol, "_kdebug_is_enabled"))
    {
        return .{
            .behavior = .return_zero,
            .reason = .optional_capability_probe,
            .confidence = .modeled,
        };
    }
    if (std.mem.eql(u8, symbol, "_sys_icache_invalidate") or
        std.mem.eql(u8, symbol, "_pthread_jit_write_protect_np"))
    {
        return .{
            .behavior = .preserve_rax,
            .reason = .guest_code_cache_maintenance,
            .confidence = .verified,
        };
    }
    return null;
}

fn isCxxSymbol(symbol: []const u8) bool {
    return std.mem.startsWith(u8, symbol, "__Z") or std.mem.startsWith(u8, symbol, "_Z");
}

test "smart stubs resolve weak imports and safe instrumentation only" {
    try std.testing.expectEqual(Reason.weak_import, generatePlan("_optional_api", true).?.reason);
    try std.testing.expectEqual(Behavior.preserve_rax, generatePlan("___sanitizer_annotate_contiguous_container", false).?.behavior);
    try std.testing.expect(generatePlan("__ZNSt3__16localeD1Ev", false) == null);
    try std.testing.expect(generatePlan("__ZNSt3__16localeD1Ev", true) == null);
    try std.testing.expect(generatePlan("_unknown_required_api", false) == null);
}

test "generator reports rejected C++ inference" {
    var generator = Generator{};
    try std.testing.expect(generator.resolve("__ZNSt3__16localeD1Ev", false, 9) == null);
    try std.testing.expectEqual(@as(u64, 1), generator.rejected_cpp);
    const weak = generator.resolve("_optional_api", true, 9).?;
    try std.testing.expectEqual(@as(u64, 0), weak.resolution.handled);
}
