const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

pub const Classification = enum {
    unrelated,
    expected_dummy_probe_unwinding,
    expected_dummy_probe_caught,
    spirv_compiler_error_caught,
    spirv_compiler_error_unresolved,
};

pub const Input = struct {
    type_name: []const u8,
    message: []const u8,
    verification_frame_seen: bool,
    handler_found: bool,
    phase_two_installed: bool,
    catch_completed: bool,
};

pub fn classify(input: Input) Classification {
    const compiler_error = std.mem.indexOf(u8, input.type_name, "spirv_cross") != null and
        std.mem.indexOf(u8, input.type_name, "CompilerError") != null;
    if (!compiler_error) return .unrelated;

    const missing_entry_point = std.mem.indexOf(u8, input.message, "no entry point") != null or
        std.mem.indexOf(u8, input.message, "No entry point") != null;
    const expected_probe = input.verification_frame_seen and missing_entry_point;

    // For expected dummy probes, prioritize probe context over catch completion
    // Frame chain validity may fail due to stack bottom (rbp=0x0), but that doesn't
    // prevent the catch from completing successfully
    if (expected_probe and input.handler_found and input.phase_two_installed) {
        if (input.catch_completed) return .expected_dummy_probe_caught;
        return .expected_dummy_probe_unwinding;
    }
    if (expected_probe and input.catch_completed) return .expected_dummy_probe_caught;
    if (input.catch_completed) return .spirv_compiler_error_caught;
    return .spirv_compiler_error_unresolved;
}

pub fn verificationFrameSeen(metadata: anytype, inspection: anytype) bool {
    for (inspection.frames[0..inspection.frame_count]) |frame| {
        const symbol = metadata.nearestSymbol(frame.instruction) orelse continue;
        if (std.mem.indexOf(u8, symbol.name, "VerifyVulkanSubmodules") != null) return true;
    }
    return false;
}

pub const Tracker = struct {
    last_object: u64 = 0,
    last_classification: Classification = .unrelated,
    compiler_error_throws: u64 = 0,
    expected_probe_throws: u64 = 0,
    expected_probe_catches: u64 = 0,
    other_compiler_error_catches: u64 = 0,
    unresolved_compiler_errors: u64 = 0,

    pub fn noteThrow(self: *Tracker, object: u64, input: Input) Classification {
        const classification = classify(input);
        self.last_object = object;
        self.last_classification = classification;
        switch (classification) {
            .unrelated => {},
            .expected_dummy_probe_unwinding => {
                self.compiler_error_throws +|= 1;
                self.expected_probe_throws +|= 1;
            },
            .spirv_compiler_error_unresolved => {
                self.compiler_error_throws +|= 1;
                self.unresolved_compiler_errors +|= 1;
            },
            .expected_dummy_probe_caught, .spirv_compiler_error_caught => {},
        }
        return classification;
    }

    pub fn noteCatch(self: *Tracker, object: u64) Classification {
        if (object == 0 or object != self.last_object) return .unrelated;
        switch (self.last_classification) {
            .expected_dummy_probe_unwinding => {
                self.last_classification = .expected_dummy_probe_caught;
                self.expected_probe_catches +|= 1;
            },
            .spirv_compiler_error_unresolved => {
                self.last_classification = .spirv_compiler_error_caught;
                self.other_compiler_error_catches +|= 1;
                self.unresolved_compiler_errors -|= 1;
            },
            else => {},
        }
        return self.last_classification;
    }

    pub fn lastLabel(self: *const Tracker) []const u8 {
        return @tagName(self.last_classification);
    }

    pub fn logSummary(self: *const Tracker) void {
        if (self.compiler_error_throws == 0) return;
        machoCapturePrint(
            "macho-processor: SPIRV-Cross exception diagnostics: compiler_errors={d} expected_dummy_probe(throws/caught)={d}/{d} other_caught={d} unresolved={d} last={s}\n",
            .{
                self.compiler_error_throws,
                self.expected_probe_throws,
                self.expected_probe_catches,
                self.other_compiler_error_catches,
                self.unresolved_compiler_errors,
                self.lastLabel(),
            },
        );
    }
};

test "dummy verification module entry point failure is expected only in probe context" {
    const input = Input{
        .type_name = "N11spirv_cross13CompilerErrorE",
        .message = "There is no entry point in the SPIR-V module.",
        .verification_frame_seen = true,
        .handler_found = true,
        .phase_two_installed = true,
        .catch_completed = false,
    };
    try std.testing.expectEqual(Classification.expected_dummy_probe_unwinding, classify(input));

    var real_shader = input;
    real_shader.verification_frame_seen = false;
    try std.testing.expectEqual(Classification.spirv_compiler_error_unresolved, classify(real_shader));
}

test "tracker records expected probe catch without suppressing real errors" {
    var tracker = Tracker{};
    const classification = tracker.noteThrow(0x4000, .{
        .type_name = "N11spirv_cross13CompilerErrorE",
        .message = "There is no entry point in the SPIR-V module.",
        .verification_frame_seen = true,
        .handler_found = true,
        .phase_two_installed = true,
        .catch_completed = false,
    });
    try std.testing.expectEqual(Classification.expected_dummy_probe_unwinding, classification);
    try std.testing.expectEqual(Classification.expected_dummy_probe_caught, tracker.noteCatch(0x4000));
    try std.testing.expectEqual(@as(u64, 1), tracker.expected_probe_catches);
    try std.testing.expectEqual(@as(u64, 0), tracker.unresolved_compiler_errors);
}
