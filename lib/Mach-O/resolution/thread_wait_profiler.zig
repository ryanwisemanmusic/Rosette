const std = @import("std");

pub const WaitCategory = enum {
    /// Thread is intentionally idle (condvar wait with no deadline, or
    /// indefinite sleep). This is expected during normal operation.
    idle,
    /// Thread is parked in a spin/poll loop (no syscall). The scheduler
    /// handles this via spin-parking; no recovery needed.
    parked,
    /// Thread has been waiting condvar/mutex beyond a healthy threshold
    /// with no signal. Possible deadlock candidate.
    deadlock,
    /// Thread is waiting but has been starved of CPU time (cooperative
    /// scheduler not yielding to it).
    starvation,
    /// Thread is waiting within an expected deadline range.
    expected,
};

pub const ProfileEntry = struct {
    handle: u64,
    state: u8,
    category: WaitCategory,
    wait_steps: u64,
    waiting_condvar: u64,
    waiting_mutex: u64,
    deadline_passed: bool,
    blocked_reason: []const u8 = "",
};

pub const Profile = struct {
    entries: [64]ProfileEntry = [_]ProfileEntry{.{ .handle = 0, .state = 0, .category = .expected, .wait_steps = 0, .waiting_condvar = 0, .waiting_mutex = 0, .deadline_passed = false }} ** 64,
    count: usize = 0,
    deadlock_count: usize = 0,
    starvation_count: usize = 0,
    idle_count: usize = 0,
};

pub const WaitProfileSystem = struct {
    last_profile_step: u64 = 0,
    profile_interval: u64 = 5_000_000,
    deadlock_warning_threshold: u64 = 10_000_000,
    starvation_warning_threshold: u64 = 5_000_000,
    idle_park_expected_threshold: u64 = 20_000_000,
    deadlock_warnings: u64 = 0,
    starvation_warnings: u64 = 0,
    nudge_actions: u64 = 0,
    last_deadlock_warning_step: u64 = 0,
    last_starvation_warning_step: u64 = 0,

    pub fn classifyWait(
        self: *const WaitProfileSystem,
        thread_state: u8,
        wait_steps: u64,
        deadline_nanoseconds: u64,
        current_step: u64,
    ) WaitCategory {
        switch (thread_state) {
            0, 1, 10, 11 => return .expected, // created, runnable, terminated, cancelled
            3, 4 => { // sleeping_until_deadline, sleeping_indefinitely
                if (wait_steps > self.idle_park_expected_threshold) return .idle;
                return .expected;
            },
            5, 6, 7, 8, 9 => { // waiting_mutex, condvar, semaphore, event, futex, join
                if (wait_steps > self.deadlock_warning_threshold) return .deadlock;
                if (wait_steps > self.starvation_warning_threshold) return .starvation;
                if (deadline_nanoseconds != 0 and deadline_nanoseconds <= current_step) return .starvation;
                return .expected;
            },
            else => return .expected,
        }
    }

    pub fn checkAndNudge(
        self: *WaitProfileSystem,
        threads_active: []const u8,
        threads_handles: []const u64,
        threads_states: []const u8,
        threads_blocked_since: []const u64,
        threads_waiting_condvar: []const u64,
        threads_waiting_mutex: []const u64,
        threads_deadlines: []const u64,
        current_step: u64,
        _: u64,
    ) void {
        if (current_step -| self.last_profile_step < self.profile_interval) return;
        self.last_profile_step = current_step;

        var profile = Profile{};
        const max_entries = @min(@as(usize, @intCast(threads_active.len)), profile.entries.len);

        for (0..max_entries) |i| {
            if (threads_active[i] == 0) continue;
            if (profile.count >= profile.entries.len) break;

            const wait_steps = current_step -| threads_blocked_since[i];
            const deadline_passed = threads_deadlines[i] != 0 and threads_deadlines[i] <= current_step;
            const category = self.classifyWait(threads_states[i], wait_steps, threads_deadlines[i], current_step);

            profile.entries[profile.count] = .{
                .handle = threads_handles[i],
                .state = threads_states[i],
                .category = category,
                .wait_steps = wait_steps,
                .waiting_condvar = threads_waiting_condvar[i],
                .waiting_mutex = threads_waiting_mutex[i],
                .deadline_passed = deadline_passed,
            };
            profile.count += 1;

            switch (category) {
                .deadlock => profile.deadlock_count += 1,
                .starvation => profile.starvation_count += 1,
                .idle => profile.idle_count += 1,
                else => {},
            }
        }

        if (profile.deadlock_count > 0 and
            current_step -| self.last_deadlock_warning_step > self.profile_interval)
        {
            self.deadlock_warnings += 1;
            self.last_deadlock_warning_step = current_step;
            std.debug.print(
                "macho-processor: THREAD WAIT PROFILE: {d} thread(s) in deadlock-wait category at step={d}; possible deadlock or missing condvar signal\n",
                .{ profile.deadlock_count, current_step },
            );
            for (profile.entries[0..profile.count]) |entry| {
                if (entry.category != .deadlock) continue;
                std.debug.print(
                    "  deadlock-thread handle=0x{x} state={d} wait_steps={d} condvar=0x{x} mutex=0x{x} deadline_passed={}\n",
                    .{ entry.handle, entry.state, entry.wait_steps, entry.waiting_condvar, entry.waiting_mutex, entry.deadline_passed },
                );
            }
        }

        if (profile.starvation_count > 0 and
            current_step -| self.last_starvation_warning_step > self.profile_interval)
        {
            self.starvation_warnings += 1;
            self.last_starvation_warning_step = current_step;
            self.nudge_actions += 1;
            std.debug.print(
                "macho-processor: THREAD WAIT PROFILE: {d} thread(s) in starvation-wait category at step={d}; scheduler nudge may be needed\n",
                .{ profile.starvation_count, current_step },
            );
        }
    }
};

test "wait profile classifies created state as expected" {
    const profile_system = WaitProfileSystem{};
    try std.testing.expectEqual(WaitCategory.expected, profile_system.classifyWait(0, 0, 0, 0));
}

test "wait profile classifies long condvar wait as deadlock" {
    const profile_system = WaitProfileSystem{};
    try std.testing.expectEqual(WaitCategory.deadlock, profile_system.classifyWait(6, 15_000_000, 0, 20_000_000));
}

test "wait profile classifies medium mutex wait as starvation" {
    const profile_system = WaitProfileSystem{};
    try std.testing.expectEqual(WaitCategory.starvation, profile_system.classifyWait(5, 6_000_000, 0, 10_000_000));
}

test "wait profile classifies short wait as expected" {
    const profile_system = WaitProfileSystem{};
    try std.testing.expectEqual(WaitCategory.expected, profile_system.classifyWait(6, 100, 0, 1000));
}
