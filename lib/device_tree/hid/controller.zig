//! The Xbox 360 controller, as a hardware description.
//!
//! Four ports, sixteen buttons, two sticks, two triggers, two rumble motors.
//! What the hardware fixes is the *topology* — how many of each thing exists —
//! and almost nothing about how they are read.
//!
//! ## The one constraint that matters
//!
//! A poll rate at or below the console's own sampling rate lets a short button
//! press land entirely between two guest reads and vanish. That is a genuine
//! hardware-derived constraint: the console samples at 60 Hz, so anything
//! polling slower can miss an event the hardware would have caught. Everything
//! else about the input path — dead zones, mapping, filtering — is a choice.

const std = @import("std");
const constraint = @import("../constraint.zig");

pub const name = "Xbox 360 Controller";
pub const vendor = "Microsoft";

/// Front-panel ports.
pub const port_count: u32 = 4;

/// Buttons the console assigns a meaning to.
pub const button_count: u32 = 15;

pub const thumbstick_count: u32 = 2;
pub const trigger_count: u32 = 2;
pub const rumble_motor_count: u32 = 2;

/// The rate the console samples its controllers at.
pub const console_sample_rate_hz: u32 = 60;

/// Analogue resolutions, as the hardware reports them.
pub const thumbstick_bits: u32 = 16;
pub const trigger_bits: u32 = 8;

pub fn addressesPort(index: u32) constraint.Check {
    if (index < port_count) return constraint.permitted("hid-port");
    return constraint.violation("hid-port", "no controller port at this index; the console has four");
}

/// Whether a host poll rate can catch what the console would have caught.
pub fn pollRateSufficient(rate_hz: u32) constraint.Check {
    if (rate_hz > console_sample_rate_hz) return constraint.permitted("hid-poll-rate");
    return constraint.violation(
        "hid-poll-rate",
        "polling at or below the console's 60 Hz sampling lets a short press vanish between reads",
    );
}

/// Dead zones are a driver choice, not a hardware fact.
///
/// The console's own driver applies them, but the hardware reports raw values
/// and a title is free to do its own filtering. Claiming a constraint here
/// would refuse a title that legitimately wants the raw stick.
pub fn deadzoneRuling() constraint.Check {
    return constraint.unconstrained("hid-deadzone");
}

test "there are four ports" {
    try std.testing.expect(addressesPort(0).ruling == .permitted);
    try std.testing.expect(addressesPort(3).ruling == .permitted);
    try std.testing.expect(addressesPort(4).ruling == .violates_hardware);
}

test "a poll rate must exceed the console's sampling" {
    // At or below 60 Hz a short press can land entirely between two reads.
    try std.testing.expect(pollRateSufficient(120).ruling == .permitted);
    try std.testing.expect(pollRateSufficient(61).ruling == .permitted);
    try std.testing.expect(pollRateSufficient(60).ruling == .violates_hardware);
    try std.testing.expect(pollRateSufficient(30).ruling == .violates_hardware);
    try std.testing.expect(pollRateSufficient(0).ruling == .violates_hardware);
}

test "dead zones are unconstrained" {
    // A title may legitimately want the raw stick; a constraint here would
    // refuse it.
    try std.testing.expect(deadzoneRuling().ruling == .unconstrained);
    try std.testing.expect(deadzoneRuling().ruling.allowed());
}

test "the topology matches the console" {
    try std.testing.expectEqual(@as(u32, 4), port_count);
    try std.testing.expectEqual(@as(u32, 2), thumbstick_count);
    try std.testing.expectEqual(@as(u32, 2), trigger_count);
    try std.testing.expectEqual(@as(u32, 2), rumble_motor_count);
    try std.testing.expectEqual(@as(u32, 16), thumbstick_bits);
    try std.testing.expectEqual(@as(u32, 8), trigger_bits);
}
