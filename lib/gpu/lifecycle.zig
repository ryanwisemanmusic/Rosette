//! Explicit ownership of the graphics runtime lifecycle.
//!
//! The graphics stack has several independent clocks: guest bootstrap, the
//! command processor, host-device setup, and presentation.  A single boolean
//! such as `gpu_ready` cannot say whether a failure happened before setup, in
//! an active submission, or while draining.  This small state machine is the
//! coordinator's vocabulary.  It owns no handles and performs no I/O; callers
//! still own the real Vulkan/Metal objects and must report the transition they
//! actually observed.

const std = @import("std");

pub const State = enum(u8) {
    uninitialized,
    initializing,
    ready_idle,
    running,
    draining,
    stopped,
    failed,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .uninitialized => "UNINITIALIZED",
            .initializing => "INITIALIZING",
            .ready_idle => "READY_IDLE",
            .running => "RUNNING",
            .draining => "DRAINING",
            .stopped => "STOPPED",
            .failed => "FAILED",
        };
    }

    pub fn acceptsGuestWork(self: State) bool {
        return self == .ready_idle or self == .running;
    }
};

pub const Event = enum(u8) {
    begin_initialization,
    host_ready,
    submit,
    submission_complete,
    begin_drain,
    drain_complete,
    stop,
    fail,
    restart,

    pub fn label(self: Event) []const u8 {
        return switch (self) {
            .begin_initialization => "begin-initialization",
            .host_ready => "host-ready",
            .submit => "submit",
            .submission_complete => "submission-complete",
            .begin_drain => "begin-drain",
            .drain_complete => "drain-complete",
            .stop => "stop",
            .fail => "fail",
            .restart => "restart",
        };
    }
};

pub const Transition = struct {
    sequence: u64 = 0,
    from: State = .uninitialized,
    event: Event = .begin_initialization,
    to: State = .uninitialized,
};

pub const max_transitions: usize = 32;

pub const Controller = struct {
    state: State = .uninitialized,
    epoch: u64 = 0,
    illegal_transitions: u64 = 0,
    transitions: [max_transitions]Transition = [_]Transition{.{}} ** max_transitions,
    transition_count: usize = 0,
    dropped_transitions: u64 = 0,

    pub fn apply(self: *Controller, event: Event) bool {
        const next = nextState(self.state, event) orelse {
            self.illegal_transitions +|= 1;
            return false;
        };
        const transition = Transition{
            .sequence = self.epoch + 1,
            .from = self.state,
            .event = event,
            .to = next,
        };
        self.epoch +|= 1;
        self.state = next;
        if (self.transition_count < self.transitions.len) {
            self.transitions[self.transition_count] = transition;
            self.transition_count += 1;
        } else {
            self.dropped_transitions +|= 1;
        }
        return true;
    }

    pub fn fail(self: *Controller) bool {
        return self.apply(.fail);
    }

    pub fn history(self: *const Controller) []const Transition {
        return self.transitions[0..self.transition_count];
    }
};

fn nextState(state: State, event: Event) ?State {
    return switch (state) {
        .uninitialized => switch (event) {
            .begin_initialization => .initializing,
            else => null,
        },
        .initializing => switch (event) {
            .host_ready => .ready_idle,
            .fail => .failed,
            else => null,
        },
        .ready_idle => switch (event) {
            .submit => .running,
            .begin_drain => .draining,
            .stop => .stopped,
            .fail => .failed,
            else => null,
        },
        .running => switch (event) {
            .submit => .running,
            .submission_complete => .ready_idle,
            .begin_drain => .draining,
            .fail => .failed,
            else => null,
        },
        .draining => switch (event) {
            .drain_complete => .ready_idle,
            .stop => .stopped,
            .fail => .failed,
            else => null,
        },
        .stopped, .failed => switch (event) {
            .restart => .initializing,
            else => null,
        },
    };
}

test "lifecycle records a legal active run with epochs" {
    var controller = Controller{};
    try std.testing.expect(controller.apply(.begin_initialization));
    try std.testing.expect(controller.apply(.host_ready));
    try std.testing.expectEqual(State.ready_idle, controller.state);
    try std.testing.expect(controller.apply(.submit));
    try std.testing.expect(controller.apply(.submission_complete));
    try std.testing.expectEqual(State.ready_idle, controller.state);
    try std.testing.expectEqual(@as(u64, 4), controller.epoch);
    try std.testing.expectEqual(@as(usize, 4), controller.history().len);
}

test "illegal lifecycle transitions are refused and do not change state" {
    var controller = Controller{};
    try std.testing.expect(!controller.apply(.submit));
    try std.testing.expectEqual(State.uninitialized, controller.state);
    try std.testing.expectEqual(@as(u64, 1), controller.illegal_transitions);

    try std.testing.expect(controller.apply(.begin_initialization));
    try std.testing.expect(controller.apply(.fail));
    try std.testing.expectEqual(State.failed, controller.state);
    try std.testing.expect(!controller.apply(.host_ready));
    try std.testing.expectEqual(State.failed, controller.state);
    try std.testing.expect(controller.apply(.restart));
    try std.testing.expectEqual(State.initializing, controller.state);
}

test "draining does not accept guest work" {
    var controller = Controller{};
    _ = controller.apply(.begin_initialization);
    _ = controller.apply(.host_ready);
    _ = controller.apply(.begin_drain);
    try std.testing.expectEqual(State.draining, controller.state);
    try std.testing.expect(!controller.state.acceptsGuestWork());
    try std.testing.expect(!controller.apply(.submit));
    try std.testing.expect(controller.apply(.drain_complete));
    try std.testing.expect(controller.state.acceptsGuestWork());
}
