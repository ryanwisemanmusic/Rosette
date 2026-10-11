//! First-observed Vulkan device-loss context.
//!
//! MoltenVK/Metal may report the GPU fault on stderr before Vulkan returns
//! VK_ERROR_DEVICE_LOST to a later fence, submit, or present call. Keep the
//! first API observation together with the work already accepted by the
//! driver, and label it explicitly as detection rather than fault origin.

const std = @import("std");
const fsi = @import("fsi/tracker.zig");

pub const Evidence = struct {
    first_unexpected_error: FailureEvidence = .{},
    first_api_detection: bool = false,
    occurrences: u64 = 0,
    operation: [96]u8 = [_]u8{0} ** 96,
    operation_len: u8 = 0,
    result: i32 = 0,
    guest_queue_submit_calls: u64 = 0,
    native_queue_submits_accepted: u64 = 0,
    native_presents_accepted: u64 = 0,
    native_present_completions: u64 = 0,
    fence_completions: u64 = 0,
    fsi_recorded_draws: u64 = 0,
    fsi_submitted_draws: u64 = 0,
    last_fsi_queue_submit: u64 = 0,
    last_fsi_target_image: u64 = 0,
    last_fsi_submission: fsi.SubmissionEvidence = .{},

    pub const Snapshot = struct {
        operation: []const u8,
        result: i32,
        guest_queue_submit_calls: u64,
        native_queue_submits_accepted: u64,
        native_presents_accepted: u64,
        native_present_completions: u64,
        fence_completions: u64,
        fsi_recorded_draws: u64,
        fsi_submitted_draws: u64,
        last_fsi_queue_submit: u64,
        last_fsi_target_image: u64,
        last_fsi_submission: fsi.SubmissionEvidence,
    };

    pub const FailureEvidence = struct {
        first_observed: bool = false,
        occurrences: u64 = 0,
        operation: [96]u8 = [_]u8{0} ** 96,
        operation_len: u8 = 0,
        result: i32 = 0,
        guest_queue_submit_calls: u64 = 0,
        native_queue_submits_accepted: u64 = 0,
        native_presents_accepted: u64 = 0,
        native_present_completions: u64 = 0,
        fence_completions: u64 = 0,
        fsi_recorded_draws: u64 = 0,
        fsi_submitted_draws: u64 = 0,
        last_fsi_queue_submit: u64 = 0,
        last_fsi_target_image: u64 = 0,
        last_fsi_submission: fsi.SubmissionEvidence = .{},

        pub fn observe(self: *FailureEvidence, snapshot: Snapshot) bool {
            self.occurrences +|= 1;
            if (self.first_observed) return false;
            self.first_observed = true;
            const count = @min(snapshot.operation.len, self.operation.len);
            @memcpy(self.operation[0..count], snapshot.operation[0..count]);
            self.operation_len = @intCast(count);
            self.result = snapshot.result;
            self.guest_queue_submit_calls = snapshot.guest_queue_submit_calls;
            self.native_queue_submits_accepted = snapshot.native_queue_submits_accepted;
            self.native_presents_accepted = snapshot.native_presents_accepted;
            self.native_present_completions = snapshot.native_present_completions;
            self.fence_completions = snapshot.fence_completions;
            self.fsi_recorded_draws = snapshot.fsi_recorded_draws;
            self.fsi_submitted_draws = snapshot.fsi_submitted_draws;
            self.last_fsi_queue_submit = snapshot.last_fsi_queue_submit;
            self.last_fsi_target_image = snapshot.last_fsi_target_image;
            self.last_fsi_submission = snapshot.last_fsi_submission;
            return true;
        }

        pub fn operationName(self: *const FailureEvidence) []const u8 {
            return self.operation[0..self.operation_len];
        }
    };

    /// Store the first observation once; later device-loss returns only raise
    /// the occurrence count so recovery attempts cannot erase the origin
    /// context for this run.
    pub fn observe(self: *Evidence, snapshot: Snapshot) bool {
        self.occurrences +|= 1;
        if (self.first_api_detection) return false;
        self.first_api_detection = true;
        const count = @min(snapshot.operation.len, self.operation.len);
        @memcpy(self.operation[0..count], snapshot.operation[0..count]);
        self.operation_len = @intCast(count);
        self.result = snapshot.result;
        self.guest_queue_submit_calls = snapshot.guest_queue_submit_calls;
        self.native_queue_submits_accepted = snapshot.native_queue_submits_accepted;
        self.native_presents_accepted = snapshot.native_presents_accepted;
        self.native_present_completions = snapshot.native_present_completions;
        self.fence_completions = snapshot.fence_completions;
        self.fsi_recorded_draws = snapshot.fsi_recorded_draws;
        self.fsi_submitted_draws = snapshot.fsi_submitted_draws;
        self.last_fsi_queue_submit = snapshot.last_fsi_queue_submit;
        self.last_fsi_target_image = snapshot.last_fsi_target_image;
        self.last_fsi_submission = snapshot.last_fsi_submission;
        return true;
    }

    pub fn operationName(self: *const Evidence) []const u8 {
        return self.operation[0..self.operation_len];
    }
};

/// Negative Vulkan results are errors except device loss (which has its own
/// detection record) and OUT_OF_DATE, the expected swapchain-rebuild signal.
pub fn isUnexpectedApiError(result: i32) bool {
    return result < 0 and result != -4 and result != -1_000_001_004;
}

test "first Vulkan device-loss observation retains accepted work context" {
    var evidence: Evidence = .{};
    try std.testing.expect(evidence.observe(.{
        .operation = "vkGetFenceStatus",
        .result = -4,
        .guest_queue_submit_calls = 240,
        .native_queue_submits_accepted = 238,
        .native_presents_accepted = 120,
        .native_present_completions = 119,
        .fence_completions = 350,
        .fsi_recorded_draws = 446_788,
        .fsi_submitted_draws = 446_700,
        .last_fsi_queue_submit = 238,
        .last_fsi_target_image = 0x1234,
        .last_fsi_submission = .{
            .queue_submit_ordinal = 238,
            .batch_index = 3,
            .draw = .{
                .command_buffer = 0xCAFE,
                .pipeline_real = 0xBEEF,
                .module_id = 9,
                .shader_hash = 0x1122,
                .pipeline_hash = 0x3344,
                .target_image = 0x1234,
                .target_source = .render_pass,
                .kind = .indexed,
                .draw_ordinal = 765,
            },
            .fsi_draws_in_command_buffer = 42,
        },
    }));
    try std.testing.expect(!evidence.observe(.{
        .operation = "vkQueuePresentKHR",
        .result = -4,
        .guest_queue_submit_calls = 900,
        .native_queue_submits_accepted = 0,
        .native_presents_accepted = 0,
        .native_present_completions = 0,
        .fence_completions = 0,
        .fsi_recorded_draws = 0,
        .fsi_submitted_draws = 0,
        .last_fsi_queue_submit = 0,
        .last_fsi_target_image = 0,
        .last_fsi_submission = .{},
    }));
    try std.testing.expectEqualStrings("vkGetFenceStatus", evidence.operationName());
    try std.testing.expectEqual(@as(u64, 2), evidence.occurrences);
    try std.testing.expectEqual(@as(u64, 238), evidence.native_queue_submits_accepted);
    try std.testing.expectEqual(@as(u64, 0x1234), evidence.last_fsi_target_image);
    try std.testing.expectEqual(@as(u64, 0xCAFE), evidence.last_fsi_submission.draw.command_buffer);
    try std.testing.expectEqual(@as(u64, 0x1122), evidence.last_fsi_submission.draw.shader_hash);
    try std.testing.expectEqual(@as(u64, 765), evidence.last_fsi_submission.draw.draw_ordinal);
}

test "first unexpected Vulkan error keeps context while normal swapchain results are excluded" {
    try std.testing.expect(!isUnexpectedApiError(0));
    try std.testing.expect(!isUnexpectedApiError(2));
    try std.testing.expect(!isUnexpectedApiError(1_000_001_003));
    try std.testing.expect(!isUnexpectedApiError(-1_000_001_004));
    try std.testing.expect(!isUnexpectedApiError(-4));
    try std.testing.expect(isUnexpectedApiError(-2));

    var evidence: Evidence = .{};
    try std.testing.expect(evidence.first_unexpected_error.observe(.{
        .operation = "vkAllocateMemory",
        .result = -2,
        .guest_queue_submit_calls = 14,
        .native_queue_submits_accepted = 13,
        .native_presents_accepted = 7,
        .native_present_completions = 6,
        .fence_completions = 29,
        .fsi_recorded_draws = 4_000,
        .fsi_submitted_draws = 3_900,
        .last_fsi_queue_submit = 13,
        .last_fsi_target_image = 0x5678,
        .last_fsi_submission = .{
            .queue_submit_ordinal = 13,
            .draw = .{ .command_buffer = 0xCAFE, .module_id = 7, .shader_hash = 0x7788, .pipeline_hash = 0x99AA },
        },
    }));
    try std.testing.expect(!evidence.first_unexpected_error.observe(.{
        .operation = "vkQueuePresentKHR",
        .result = -1_000_000_000,
        .guest_queue_submit_calls = 30,
        .native_queue_submits_accepted = 0,
        .native_presents_accepted = 0,
        .native_present_completions = 0,
        .fence_completions = 0,
        .fsi_recorded_draws = 0,
        .fsi_submitted_draws = 0,
        .last_fsi_queue_submit = 0,
        .last_fsi_target_image = 0,
        .last_fsi_submission = .{},
    }));
    try std.testing.expectEqualStrings("vkAllocateMemory", evidence.first_unexpected_error.operationName());
    try std.testing.expectEqual(@as(u64, 2), evidence.first_unexpected_error.occurrences);
    try std.testing.expectEqual(@as(i32, -2), evidence.first_unexpected_error.result);
    try std.testing.expectEqual(@as(u64, 0x5678), evidence.first_unexpected_error.last_fsi_target_image);
    try std.testing.expectEqual(@as(u64, 0x7788), evidence.first_unexpected_error.last_fsi_submission.draw.shader_hash);
}
