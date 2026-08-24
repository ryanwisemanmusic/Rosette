//! Xbox 360 rumble to host haptics.
//!
//! The console has two motors of different weights: a low-frequency one for
//! heavy rumble and a high-frequency one for detail. Host haptic APIs vary in
//! what they accept, so the forwarder's job is to carry intent across without
//! either dropping a motor or leaving one running.
//!
//! ## A motor left running is the failure that matters
//!
//! Every other rumble bug is cosmetic. This one is not: if a title sets a motor
//! and Rosette loses the stop — a disconnect, a state change, a title exit —
//! the pad vibrates until its battery dies. So `stop` is unconditional, the
//! forwarder tracks whether it believes a motor is live, and a disconnect
//! always emits a stop rather than assuming the device took care of it.

const std = @import("std");
const contract = @import("xenia_input_contract");

/// The strongest a motor can be driven.
pub const motor_max: u16 = 65535;

/// A host haptic command.
pub const HapticCommand = struct {
    /// Normalised [0, 1] intensities, which is what host APIs take.
    low_frequency: f32,
    high_frequency: f32,

    pub fn isSilent(self: HapticCommand) bool {
        return self.low_frequency == 0 and self.high_frequency == 0;
    }
};

pub const Forwarder = struct {
    /// The last vibration the title asked for.
    requested: contract.Vibration = .{},
    /// Whether the forwarder believes a motor is currently running.
    motors_live: bool = false,

    commands_sent: u64 = 0,
    stops_sent: u64 = 0,
    /// Stops emitted because the port went away rather than because the title
    /// asked. A non-zero count here means titles are relying on Rosette to
    /// clean up after them.
    safety_stops: u64 = 0,

    /// Translate a guest vibration request into a host command.
    pub fn setVibration(self: *Forwarder, vibration: contract.Vibration) HapticCommand {
        self.requested = vibration;
        self.motors_live = !vibration.isSilent();
        self.commands_sent +|= 1;
        if (vibration.isSilent()) self.stops_sent +|= 1;
        return .{
            .low_frequency = normalise(vibration.left_motor_speed),
            .high_frequency = normalise(vibration.right_motor_speed),
        };
    }

    /// Stop both motors, whatever the forwarder believes their state to be.
    ///
    /// Unconditional on purpose. A stop skipped because the forwarder thought
    /// the motors were already off is how a pad ends up buzzing until its
    /// battery dies — the one rumble bug that is not cosmetic.
    pub fn stop(self: *Forwarder) HapticCommand {
        self.requested = .{};
        self.motors_live = false;
        self.commands_sent +|= 1;
        self.stops_sent +|= 1;
        return .{ .low_frequency = 0, .high_frequency = 0 };
    }

    /// Stop because the port is going away.
    pub fn stopForDisconnect(self: *Forwarder) HapticCommand {
        self.safety_stops +|= 1;
        return self.stop();
    }

    fn normalise(speed: u16) f32 {
        return @as(f32, @floatFromInt(speed)) / @as(f32, @floatFromInt(motor_max));
    }
};

test "a motor request normalises across the full range" {
    var forwarder = Forwarder{};
    const full = forwarder.setVibration(.{ .left_motor_speed = motor_max, .right_motor_speed = 0 });
    try std.testing.expectEqual(@as(f32, 1.0), full.low_frequency);
    try std.testing.expectEqual(@as(f32, 0.0), full.high_frequency);
    try std.testing.expect(!full.isSilent());
    try std.testing.expect(forwarder.motors_live);
}

test "the two motors stay distinct" {
    // Collapsing them to one intensity loses the detail motor entirely, and
    // the rumble feels wrong in a way that is hard to describe or report.
    var forwarder = Forwarder{};
    const command = forwarder.setVibration(.{ .left_motor_speed = motor_max, .right_motor_speed = 0 });
    try std.testing.expect(command.low_frequency != command.high_frequency);

    const swapped = forwarder.setVibration(.{ .left_motor_speed = 0, .right_motor_speed = motor_max });
    try std.testing.expectEqual(@as(f32, 0.0), swapped.low_frequency);
    try std.testing.expectEqual(@as(f32, 1.0), swapped.high_frequency);
}

test "a zero request is a stop and is counted as one" {
    var forwarder = Forwarder{};
    _ = forwarder.setVibration(.{ .left_motor_speed = 30000 });
    try std.testing.expect(forwarder.motors_live);

    const command = forwarder.setVibration(.{});
    try std.testing.expect(command.isSilent());
    try std.testing.expect(!forwarder.motors_live);
    try std.testing.expectEqual(@as(u64, 1), forwarder.stops_sent);
}

test "stop is unconditional even when nothing is believed to be running" {
    // A stop skipped on a stale belief is how a pad buzzes forever.
    var forwarder = Forwarder{};
    try std.testing.expect(!forwarder.motors_live);
    const command = forwarder.stop();
    try std.testing.expect(command.isSilent());
    try std.testing.expectEqual(@as(u64, 1), forwarder.stops_sent);
    try std.testing.expectEqual(@as(u64, 1), forwarder.commands_sent);
}

test "a disconnect always emits a stop and is counted separately" {
    var forwarder = Forwarder{};
    _ = forwarder.setVibration(.{ .left_motor_speed = motor_max });
    const command = forwarder.stopForDisconnect();
    try std.testing.expect(command.isSilent());
    try std.testing.expect(!forwarder.motors_live);
    try std.testing.expectEqual(@as(u64, 1), forwarder.safety_stops);
    // Counted separately so "titles rely on us to clean up" is visible.
    try std.testing.expect(forwarder.safety_stops < forwarder.stops_sent + 1);
}

test "intensities stay inside the unit range" {
    var forwarder = Forwarder{};
    const half = forwarder.setVibration(.{ .left_motor_speed = 32768, .right_motor_speed = 16384 });
    try std.testing.expect(half.low_frequency > 0.49 and half.low_frequency < 0.51);
    try std.testing.expect(half.high_frequency > 0.24 and half.high_frequency < 0.26);
    try std.testing.expect(half.low_frequency <= 1.0);
    try std.testing.expect(half.high_frequency >= 0.0);
}
