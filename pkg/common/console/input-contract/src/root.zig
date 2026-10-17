//! Route-independent: the Xbox 360 controller's wire state layout.
//!
//! `XINPUT_GAMEPAD` is an ABI structure. The guest reads it out of memory the
//! host filled, so the bit values and field offsets are not an implementation
//! choice — they are the same on every host Rosette is compiled for, and there
//! is one copy with no route mirror.
//!
//! ## Why the button bits are the interesting part
//!
//! A wrong button bit is invisible to every automated check and obvious to a
//! person holding a controller, which is the worst combination for a bug that
//! sits under an emulator. Halo 3 reads the guide button and the two stick
//! clicks through the same word as A/B/X/Y; a mask that is off by one bit
//! turns "press A" into "press B" with no error anywhere. Fixing the bits as
//! comptime facts is the only way that mismatch becomes checkable.
//!
//! ## What this package is not
//!
//! * It is not an input system. It holds no controller state and cannot say a
//!   button is down; `lib/hid/input_system.zig` polls the host and owns that.
//! * It does not map a host device. The macOS-side translation lives in
//!   `lib/hid/controller_map.zig`, because which host button is "A" is a
//!   property of the pad that happens to be plugged in, not of the console.
//! * It does not rumble anything. A motor is an effect and belongs in lib.

const std = @import("std");

// ---------------------------------------------------------------------------
// Button bits
// ---------------------------------------------------------------------------

/// The XINPUT button word.
///
/// A non-exhaustive enum over `u16`: the console leaves 0x0800 and the 0x0C00
/// neighbourhood unassigned, and a pad that reports one must not be a checked
/// illegal value at a cast. Rosette should pass an unknown bit through to the
/// title unchanged rather than refuse it.
pub const Button = enum(u16) {
    dpad_up = 0x0001,
    dpad_down = 0x0002,
    dpad_left = 0x0004,
    dpad_right = 0x0008,
    start = 0x0010,
    back = 0x0020,
    left_thumb = 0x0040,
    right_thumb = 0x0080,
    left_shoulder = 0x0100,
    right_shoulder = 0x0200,
    guide = 0x0400,
    a = 0x1000,
    b = 0x2000,
    x = 0x4000,
    y = 0x8000,
    _,

    pub fn mask(self: Button) u16 {
        return @intFromEnum(self);
    }
};

/// Every bit the console assigns a meaning to. A bit outside this set is
/// reserved, not free: a host driver must not invent a use for one.
pub const assigned_button_mask: u16 = 0xF7FF;

/// The four face buttons, as a set. Grouped because a title that polls "any
/// face button" is asking about exactly this mask.
pub const face_button_mask: u16 =
    Button.a.mask() | Button.b.mask() | Button.x.mask() | Button.y.mask();

/// The d-pad, as a set.
pub const dpad_mask: u16 =
    Button.dpad_up.mask() | Button.dpad_down.mask() |
    Button.dpad_left.mask() | Button.dpad_right.mask();

// ---------------------------------------------------------------------------
// Analogue ranges
// ---------------------------------------------------------------------------

/// Thumbstick axes are signed 16-bit and asymmetric: -32768 has no positive
/// twin. A driver that negates an axis by flipping the sign hits this and
/// wraps to itself, which reads as a stick that sticks at full deflection.
pub const thumb_min: i16 = -32768;
pub const thumb_max: i16 = 32767;

/// Triggers are unsigned 8-bit, not signed and not 16-bit.
pub const trigger_min: u8 = 0;
pub const trigger_max: u8 = 255;

/// The dead zones the console's own driver applies. A title calibrating
/// against a raw stick will drift, because it expects these to be gone
/// already.
pub const left_thumb_deadzone: i16 = 7849;
pub const right_thumb_deadzone: i16 = 8689;
pub const trigger_threshold: u8 = 30;

/// Controller ports. Four, fixed by the console's front panel.
pub const max_controller_count: u32 = 4;

// ---------------------------------------------------------------------------
// Wire structures
// ---------------------------------------------------------------------------

/// `XINPUT_GAMEPAD`. `extern` because the guest reads these offsets directly.
pub const Gamepad = extern struct {
    buttons: u16 = 0,
    left_trigger: u8 = 0,
    right_trigger: u8 = 0,
    thumb_lx: i16 = 0,
    thumb_ly: i16 = 0,
    thumb_rx: i16 = 0,
    thumb_ry: i16 = 0,

    pub fn isPressed(self: Gamepad, button: Button) bool {
        return self.buttons & button.mask() != 0;
    }

    /// Whether any bit outside the console's assigned set is set.
    ///
    /// A diagnostic, not a gate: the answer is reported, and the bits are
    /// still delivered to the title. Refusing them here would be this package
    /// making a runtime decision, which is what `lib/` is for.
    pub fn hasReservedBits(self: Gamepad) bool {
        return self.buttons & ~assigned_button_mask != 0;
    }
};

/// `XINPUT_STATE`. The packet number is how a title detects that nothing
/// changed without diffing the gamepad; a driver that leaves it constant makes
/// every poll look stale, and one that bumps it unconditionally makes every
/// poll look like input.
pub const State = extern struct {
    packet_number: u32 = 0,
    gamepad: Gamepad = .{},
};

/// `XINPUT_VIBRATION`. Motor speeds are 16-bit unsigned; the low-frequency
/// motor is the heavy one.
pub const Vibration = extern struct {
    left_motor_speed: u16 = 0,
    right_motor_speed: u16 = 0,

    pub fn isSilent(self: Vibration) bool {
        return self.left_motor_speed == 0 and self.right_motor_speed == 0;
    }
};

/// Whether a port index addresses a real controller port.
pub fn isControllerPort(index: u32) bool {
    return index < max_controller_count;
}

/// Whether a stick reading is inside the console's dead zone for that stick.
///
/// Pure geometry on the values handed in. It cannot read a device, and a true
/// answer says the pair is inside the radius, never that a stick is at rest.
pub fn isInsideDeadzone(axis_x: i16, axis_y: i16, deadzone: i16) bool {
    // Squared magnitude in i64: x*x + y*y overflows i32 at full deflection on
    // both axes (32768^2 * 2), and a wrapped comparison would report the
    // hardest possible push as "centred".
    const x: i64 = axis_x;
    const y: i64 = axis_y;
    const zone: i64 = deadzone;
    return x * x + y * y < zone * zone;
}

pub fn contractIsWellFormed() bool {
    if (face_button_mask & dpad_mask != 0) return false;
    if (face_button_mask & ~assigned_button_mask != 0) return false;
    if (dpad_mask & ~assigned_button_mask != 0) return false;
    if (thumb_min != -32768 or thumb_max != 32767) return false;
    if (@sizeOf(Gamepad) != 12) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "face buttons occupy the high nibble and do not overlap the d-pad" {
    try std.testing.expectEqual(@as(u16, 0xF000), face_button_mask);
    try std.testing.expectEqual(@as(u16, 0x000F), dpad_mask);
    try std.testing.expectEqual(@as(u16, 0), face_button_mask & dpad_mask);
}

test "guide and the stick clicks share the button word" {
    // The bug this guards: treating guide/thumb clicks as a separate word.
    // They are bits in the same u16 as A/B/X/Y, so a driver that masks them
    // off loses stick-click, which Halo 3 uses for crouch.
    try std.testing.expectEqual(@as(u16, 0x0400), Button.guide.mask());
    try std.testing.expectEqual(@as(u16, 0x0040), Button.left_thumb.mask());
    try std.testing.expectEqual(@as(u16, 0x0080), Button.right_thumb.mask());
    try std.testing.expect(Button.guide.mask() & assigned_button_mask != 0);
}

test "0x0800 is reserved and stays reserved" {
    // The one gap in the low twelve bits. A driver that fills it invents a
    // button the console never had.
    try std.testing.expectEqual(@as(u16, 0), assigned_button_mask & 0x0800);

    var pad = Gamepad{ .buttons = 0x0800 };
    try std.testing.expect(pad.hasReservedBits());
    // Reserved bits are reported, not stripped: the value is still there.
    try std.testing.expectEqual(@as(u16, 0x0800), pad.buttons);

    pad.buttons = Button.a.mask();
    try std.testing.expect(!pad.hasReservedBits());
}

test "press detection reads one bit, not the whole word" {
    const pad = Gamepad{ .buttons = Button.a.mask() | Button.start.mask() };
    try std.testing.expect(pad.isPressed(.a));
    try std.testing.expect(pad.isPressed(.start));
    try std.testing.expect(!pad.isPressed(.b));
    try std.testing.expect(!pad.isPressed(.guide));
}

test "the thumbstick range is asymmetric" {
    // -32768 has no positive twin. A driver that inverts Y by negation hits
    // this and wraps to -32768 again: the stick pins instead of inverting.
    try std.testing.expectEqual(@as(i16, -32768), thumb_min);
    try std.testing.expectEqual(@as(i16, 32767), thumb_max);
    try std.testing.expect(@as(i32, thumb_min) + @as(i32, thumb_max) == -1);
}

test "deadzone tests do not overflow at full deflection" {
    // Both axes at the negative rail is the case that overflows i32. If the
    // arithmetic wrapped, this would report the hardest push as centred.
    try std.testing.expect(!isInsideDeadzone(thumb_min, thumb_min, left_thumb_deadzone));
    try std.testing.expect(!isInsideDeadzone(thumb_max, thumb_max, right_thumb_deadzone));
    try std.testing.expect(isInsideDeadzone(0, 0, left_thumb_deadzone));
    // Just inside and just outside the radius on one axis.
    try std.testing.expect(isInsideDeadzone(left_thumb_deadzone - 1, 0, left_thumb_deadzone));
    try std.testing.expect(!isInsideDeadzone(left_thumb_deadzone, 0, left_thumb_deadzone));
}

test "there are four ports" {
    try std.testing.expect(isControllerPort(0));
    try std.testing.expect(isControllerPort(3));
    try std.testing.expect(!isControllerPort(4));
}

test "the wire layout is the ABI the guest reads" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Gamepad, "buttons"));
    try std.testing.expectEqual(@as(usize, 2), @offsetOf(Gamepad, "left_trigger"));
    try std.testing.expectEqual(@as(usize, 3), @offsetOf(Gamepad, "right_trigger"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(Gamepad, "thumb_lx"));
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(Gamepad));

    // XINPUT_STATE puts the packet number first, before the pad.
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(State, "packet_number"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(State, "gamepad"));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(State));

    try std.testing.expectEqual(@as(usize, 4), @sizeOf(Vibration));
}

test "silence is both motors, not either" {
    try std.testing.expect((Vibration{}).isSilent());
    try std.testing.expect(!(Vibration{ .left_motor_speed = 1 }).isSilent());
    try std.testing.expect(!(Vibration{ .right_motor_speed = 1 }).isSilent());
}
