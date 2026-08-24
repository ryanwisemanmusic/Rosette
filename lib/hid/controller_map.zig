//! Host gamepad to Xbox 360 controller translation.
//!
//! Which physical button is "A" is a property of the pad that happens to be
//! connected, not of the console, so this mapping is runtime data rather than a
//! contract. What the mapping produces — the button word, the stick ranges — is
//! fixed by `pkg/common/xenia/input-contract`.
//!
//! ## Why the axis conversion is the subtle part
//!
//! Host APIs report sticks as a float in [-1, 1]. The console uses `i16`, whose
//! range is asymmetric: -32768 has no positive twin. Scaling by 32768 makes
//! +1.0 overflow to -32768, which reads as a stick slammed in the *opposite*
//! direction at full deflection. Scaling by 32767 loses the bottom of the
//! range. The correct conversion scales by 32767 and clamps, so full deflection
//! is representable in both directions and nothing wraps.
//!
//! Triggers have the same shape one size down: a float in [0, 1] to a `u8`.

const std = @import("std");
const contract = @import("xenia_input_contract");

/// A host button, in the vocabulary a host API reports.
pub const HostButton = enum {
    south,
    east,
    west,
    north,
    left_shoulder,
    right_shoulder,
    left_stick,
    right_stick,
    menu,
    options,
    home,
    dpad_up,
    dpad_down,
    dpad_left,
    dpad_right,
};

/// The console button a host button drives.
///
/// The south/east/west/north naming is deliberate: it is positional and does
/// not carry a letter, so a pad whose faces are labelled differently cannot
/// silently produce the wrong console button. A "B button" on a DualSense is
/// in the west position, and mapping by label rather than position is how
/// confirm and cancel end up swapped.
pub fn consoleButtonFor(host: HostButton) contract.Button {
    return switch (host) {
        .south => .a,
        .east => .b,
        .west => .x,
        .north => .y,
        .left_shoulder => .left_shoulder,
        .right_shoulder => .right_shoulder,
        .left_stick => .left_thumb,
        .right_stick => .right_thumb,
        .menu => .start,
        .options => .back,
        .home => .guide,
        .dpad_up => .dpad_up,
        .dpad_down => .dpad_down,
        .dpad_left => .dpad_left,
        .dpad_right => .dpad_right,
    };
}

/// Convert a host axis in [-1, 1] to the console's `i16`.
///
/// Scales by 32767 and clamps. Non-finite input becomes centre rather than
/// propagating: a NaN axis from a disconnecting pad must not become full
/// deflection.
pub fn axisToThumb(value: f32) i16 {
    if (!std.math.isFinite(value)) return 0;
    const clamped = std.math.clamp(value, -1.0, 1.0);
    const scaled = clamped * @as(f32, @floatFromInt(contract.thumb_max));
    return @intFromFloat(std.math.clamp(
        @round(scaled),
        @as(f32, @floatFromInt(contract.thumb_min)),
        @as(f32, @floatFromInt(contract.thumb_max)),
    ));
}

/// Convert a host trigger in [0, 1] to the console's `u8`.
pub fn axisToTrigger(value: f32) u8 {
    if (!std.math.isFinite(value)) return 0;
    const clamped = std.math.clamp(value, 0.0, 1.0);
    const scaled = clamped * @as(f32, @floatFromInt(contract.trigger_max));
    return @intFromFloat(std.math.clamp(@round(scaled), 0.0, 255.0));
}

/// A host controller reading, before translation.
pub const HostState = struct {
    buttons: std.EnumSet(HostButton) = .initEmpty(),
    left_stick_x: f32 = 0,
    left_stick_y: f32 = 0,
    right_stick_x: f32 = 0,
    right_stick_y: f32 = 0,
    left_trigger: f32 = 0,
    right_trigger: f32 = 0,
    /// Whether the host reports Y as up. Most do; the console expects up to be
    /// positive, so a pad that reports the other convention must be flipped
    /// here rather than by negating downstream — negating an `i16` hits the
    /// asymmetric-range trap.
    y_axis_points_up: bool = true,
};

/// Translate a host reading into the console's gamepad structure.
pub fn translate(host: HostState) contract.Gamepad {
    var buttons: u16 = 0;
    var iterator = host.buttons.iterator();
    while (iterator.next()) |button| {
        buttons |= consoleButtonFor(button).mask();
    }

    const left_y = if (host.y_axis_points_up) host.left_stick_y else -host.left_stick_y;
    const right_y = if (host.y_axis_points_up) host.right_stick_y else -host.right_stick_y;

    return .{
        .buttons = buttons,
        .left_trigger = axisToTrigger(host.left_trigger),
        .right_trigger = axisToTrigger(host.right_trigger),
        .thumb_lx = axisToThumb(host.left_stick_x),
        .thumb_ly = axisToThumb(left_y),
        .thumb_rx = axisToThumb(host.right_stick_x),
        .thumb_ry = axisToThumb(right_y),
    };
}

/// Apply the console's dead zones to a translated gamepad.
///
/// Separate from `translate` because a title may want the raw reading. Applied
/// as a radial zone on each stick, matching the console's own driver — a
/// per-axis zone would leave a square hole and make diagonal movement stick.
pub fn applyDeadzones(pad: contract.Gamepad) contract.Gamepad {
    var result = pad;
    if (contract.isInsideDeadzone(pad.thumb_lx, pad.thumb_ly, contract.left_thumb_deadzone)) {
        result.thumb_lx = 0;
        result.thumb_ly = 0;
    }
    if (contract.isInsideDeadzone(pad.thumb_rx, pad.thumb_ry, contract.right_thumb_deadzone)) {
        result.thumb_rx = 0;
        result.thumb_ry = 0;
    }
    if (pad.left_trigger < contract.trigger_threshold) result.left_trigger = 0;
    if (pad.right_trigger < contract.trigger_threshold) result.right_trigger = 0;
    return result;
}

test "full positive deflection does not wrap to the negative rail" {
    // Scaling by 32768 would make +1.0 become -32768 — a stick reported as
    // slammed in the opposite direction at full deflection.
    try std.testing.expectEqual(contract.thumb_max, axisToThumb(1.0));
    try std.testing.expect(axisToThumb(1.0) > 0);
    try std.testing.expectEqual(@as(i16, -32767), axisToThumb(-1.0));
    try std.testing.expectEqual(@as(i16, 0), axisToThumb(0));
}

test "axis input beyond the unit range is clamped, not wrapped" {
    try std.testing.expectEqual(contract.thumb_max, axisToThumb(2.0));
    try std.testing.expectEqual(@as(i16, -32767), axisToThumb(-2.0));
    try std.testing.expectEqual(@as(i16, 0), axisToThumb(std.math.nan(f32)));
    try std.testing.expectEqual(@as(i16, 0), axisToThumb(std.math.inf(f32)));
}

test "triggers span the whole byte" {
    try std.testing.expectEqual(@as(u8, 0), axisToTrigger(0));
    try std.testing.expectEqual(@as(u8, 255), axisToTrigger(1.0));
    try std.testing.expectEqual(@as(u8, 128), axisToTrigger(0.5));
    try std.testing.expectEqual(@as(u8, 255), axisToTrigger(5.0));
    try std.testing.expectEqual(@as(u8, 0), axisToTrigger(-1.0));
    try std.testing.expectEqual(@as(u8, 0), axisToTrigger(std.math.nan(f32)));
}

test "face buttons map by position, not by printed letter" {
    // A pad whose faces are labelled differently must still produce the right
    // console button. Mapping by label is how confirm and cancel get swapped.
    try std.testing.expectEqual(contract.Button.a, consoleButtonFor(.south));
    try std.testing.expectEqual(contract.Button.b, consoleButtonFor(.east));
    try std.testing.expectEqual(contract.Button.x, consoleButtonFor(.west));
    try std.testing.expectEqual(contract.Button.y, consoleButtonFor(.north));
}

test "every host button maps to a distinct console button" {
    // A collision would make two physical buttons indistinguishable, which
    // presents as one of them "not working".
    var seen: u16 = 0;
    for (std.enums.values(HostButton)) |host| {
        const mask = consoleButtonFor(host).mask();
        try std.testing.expectEqual(@as(u16, 0), seen & mask);
        seen |= mask;
    }
    // Fifteen buttons, all inside the console's assigned set.
    try std.testing.expectEqual(@as(u16, 0), seen & ~contract.assigned_button_mask);
}

test "a translated press lands in the button word" {
    var host = HostState{};
    host.buttons.insert(.south);
    host.buttons.insert(.menu);
    const pad = translate(host);
    try std.testing.expect(pad.isPressed(.a));
    try std.testing.expect(pad.isPressed(.start));
    try std.testing.expect(!pad.isPressed(.b));
    try std.testing.expect(!pad.hasReservedBits());
}

test "an inverted host Y axis is flipped before conversion, not after" {
    // Flipping after conversion means negating an i16, which hits the
    // asymmetric range and pins the stick at full deflection.
    var host = HostState{ .left_stick_y = 1.0, .y_axis_points_up = false };
    const flipped = translate(host);
    try std.testing.expectEqual(@as(i16, -32767), flipped.thumb_ly);

    host.y_axis_points_up = true;
    const upright = translate(host);
    try std.testing.expectEqual(contract.thumb_max, upright.thumb_ly);
}

test "the dead zone is radial, not per axis" {
    // A per-axis zone leaves a square hole: a stick pushed diagonally just
    // past the zone on both axes would be zeroed, and diagonal movement
    // sticks near centre.
    const inside = contract.Gamepad{ .thumb_lx = 5000, .thumb_ly = 5000 };
    const zeroed = applyDeadzones(inside);
    try std.testing.expectEqual(@as(i16, 0), zeroed.thumb_lx);
    try std.testing.expectEqual(@as(i16, 0), zeroed.thumb_ly);

    // 7000 on each axis is a radius of ~9899, outside the 7849 zone, so a
    // radial test keeps it and a per-axis test would have discarded it.
    const diagonal = contract.Gamepad{ .thumb_lx = 7000, .thumb_ly = 7000 };
    const kept = applyDeadzones(diagonal);
    try std.testing.expectEqual(@as(i16, 7000), kept.thumb_lx);
    try std.testing.expectEqual(@as(i16, 7000), kept.thumb_ly);
}

test "the two sticks use their own dead zones" {
    // 8000 is outside the left zone (7849) and inside the right one (8689).
    const pad = contract.Gamepad{
        .thumb_lx = 8000,
        .thumb_ly = 0,
        .thumb_rx = 8000,
        .thumb_ry = 0,
    };
    const result = applyDeadzones(pad);
    try std.testing.expectEqual(@as(i16, 8000), result.thumb_lx);
    try std.testing.expectEqual(@as(i16, 0), result.thumb_rx);
}

test "triggers below the threshold read as released" {
    const pad = contract.Gamepad{ .left_trigger = 10, .right_trigger = 200 };
    const result = applyDeadzones(pad);
    try std.testing.expectEqual(@as(u8, 0), result.left_trigger);
    try std.testing.expectEqual(@as(u8, 200), result.right_trigger);
}

test "full deflection survives the dead zone" {
    const pad = contract.Gamepad{
        .thumb_lx = contract.thumb_min,
        .thumb_ly = contract.thumb_min,
    };
    const result = applyDeadzones(pad);
    try std.testing.expectEqual(contract.thumb_min, result.thumb_lx);
}
