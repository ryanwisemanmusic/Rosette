//! Controller state publication and the guest-facing poll.
//!
//! The host polls a pad on one thread; the guest reads it on another, whenever
//! it likes. This file owns the handoff between them and the packet number that
//! tells a title whether anything changed.
//!
//! ## The packet number is not a counter
//!
//! `XINPUT_STATE.packet_number` exists so a title can detect "nothing changed"
//! without diffing the pad. That makes it load-bearing in a way a plain counter
//! is not:
//!
//! * Bumped every poll, every read looks like fresh input. Titles that
//!   rate-limit on it will process input every frame regardless.
//! * Never bumped, every read looks stale, and a title that skips unchanged
//!   states will ignore the controller entirely — which presents as "input
//!   does not work" with a perfectly correct button word sitting in memory.
//!
//! So it advances if and only if the gamepad actually differs.

const std = @import("std");
const contract = @import("xenia_input_contract");
const controller_map = @import("controller_map.zig");

pub const Error = error{
    /// A port index outside the console's four.
    InvalidPort,
};

/// One controller slot.
pub const Port = struct {
    connected: bool = false,
    state: contract.State = .{},
    /// Polls the host performed for this port.
    polls: u64 = 0,
    /// Polls that produced a different gamepad than the previous one.
    changes: u64 = 0,
    /// Reads the guest performed.
    guest_reads: u64 = 0,

    /// Publish a freshly polled gamepad.
    ///
    /// Returns whether anything changed. The packet number advances only then.
    pub fn publish(self: *Port, pad: contract.Gamepad) bool {
        self.polls +|= 1;
        if (std.meta.eql(self.state.gamepad, pad)) return false;
        self.state.gamepad = pad;
        self.state.packet_number +%= 1;
        self.changes +|= 1;
        return true;
    }

    /// The state the guest reads.
    pub fn read(self: *Port) contract.State {
        self.guest_reads +|= 1;
        return self.state;
    }

    /// Mark the port disconnected and release every input it was holding.
    ///
    /// Zeroing matters: a pad unplugged mid-press otherwise leaves that button
    /// latched down forever, and the title behaves as though it is still held.
    pub fn disconnect(self: *Port) void {
        self.connected = false;
        _ = self.publish(.{});
    }
};

pub const InputSystem = struct {
    ports: [contract.max_controller_count]Port = @splat(.{}),

    pub fn port(self: *InputSystem, index: u32) Error!*Port {
        if (!contract.isControllerPort(index)) return error.InvalidPort;
        return &self.ports[index];
    }

    pub fn connect(self: *InputSystem, index: u32) Error!void {
        const slot = try self.port(index);
        slot.connected = true;
    }

    /// Poll one port from a host reading.
    pub fn poll(self: *InputSystem, index: u32, host: controller_map.HostState) Error!bool {
        const slot = try self.port(index);
        if (!slot.connected) return false;
        const pad = controller_map.applyDeadzones(controller_map.translate(host));
        return slot.publish(pad);
    }

    /// The state a title's `XInputGetState` receives.
    ///
    /// A disconnected port returns a zeroed state rather than the last one it
    /// held, so an unplugged pad cannot appear to still be pressing something.
    pub fn readState(self: *InputSystem, index: u32) Error!contract.State {
        const slot = try self.port(index);
        if (!slot.connected) return .{};
        return slot.read();
    }

    pub fn connectedCount(self: *const InputSystem) u32 {
        var count: u32 = 0;
        for (self.ports) |slot| {
            if (slot.connected) count += 1;
        }
        return count;
    }

    pub const Health = struct {
        connected: u32,
        polls: u64,
        changes: u64,
        guest_reads: u64,

        /// Where the input path stops, if it does.
        ///
        /// The ordering matters: a title that never reads is a different
        /// problem from a host that never polls, and both look like "the
        /// controller does not work".
        pub fn verdict(self: Health) []const u8 {
            if (self.connected == 0) return "no controller connected";
            if (self.polls == 0) return "connected but never polled: the host input loop is not running";
            if (self.guest_reads == 0) {
                return "polled but never read: input is being published and the title is not asking for it";
            }
            if (self.changes == 0) {
                return "read but never changed: the title is asking and every poll reported the same pad";
            }
            return "input is flowing: polls change state and the title reads it";
        }
    };

    pub fn health(self: *const InputSystem) Health {
        var polls: u64 = 0;
        var changes: u64 = 0;
        var reads: u64 = 0;
        for (self.ports) |slot| {
            polls +|= slot.polls;
            changes +|= slot.changes;
            reads +|= slot.guest_reads;
        }
        return .{
            .connected = self.connectedCount(),
            .polls = polls,
            .changes = changes,
            .guest_reads = reads,
        };
    }
};

test "ports are bounded by the console's four" {
    var system = InputSystem{};
    _ = try system.port(0);
    _ = try system.port(3);
    try std.testing.expectError(error.InvalidPort, system.port(4));
    try std.testing.expectError(error.InvalidPort, system.readState(9));
}

test "the packet number advances only on a real change" {
    // Bumped every poll, a title cannot rate-limit. Never bumped, a title
    // that skips unchanged states ignores the controller entirely.
    var slot = Port{ .connected = true };
    const pressed = contract.Gamepad{ .buttons = contract.Button.a.mask() };

    try std.testing.expect(slot.publish(pressed));
    const first = slot.state.packet_number;

    // The same pad again: no change, no bump.
    try std.testing.expect(!slot.publish(pressed));
    try std.testing.expectEqual(first, slot.state.packet_number);

    // A different pad: bump.
    try std.testing.expect(slot.publish(.{ .buttons = contract.Button.b.mask() }));
    try std.testing.expect(slot.state.packet_number != first);
    try std.testing.expectEqual(@as(u64, 2), slot.changes);
    try std.testing.expectEqual(@as(u64, 3), slot.polls);
}

test "a stick movement counts as a change even with no buttons down" {
    // Comparing only the button word would make analogue-only input invisible.
    var slot = Port{ .connected = true };
    try std.testing.expect(slot.publish(.{ .thumb_lx = 1000 }));
    try std.testing.expect(slot.publish(.{ .thumb_lx = 2000 }));
    try std.testing.expect(!slot.publish(.{ .thumb_lx = 2000 }));
    try std.testing.expectEqual(@as(u64, 2), slot.changes);
}

test "a disconnected pad releases whatever it was holding" {
    // Otherwise a pad unplugged mid-press leaves the button latched and the
    // title behaves as though it is still held.
    var slot = Port{ .connected = true };
    _ = slot.publish(.{ .buttons = contract.Button.a.mask(), .thumb_lx = 20000 });
    try std.testing.expect(slot.state.gamepad.isPressed(.a));

    slot.disconnect();
    try std.testing.expect(!slot.connected);
    try std.testing.expect(!slot.state.gamepad.isPressed(.a));
    try std.testing.expectEqual(@as(i16, 0), slot.state.gamepad.thumb_lx);
}

test "reading a disconnected port yields a zeroed state" {
    var system = InputSystem{};
    const state = try system.readState(0);
    try std.testing.expectEqual(@as(u16, 0), state.gamepad.buttons);
    try std.testing.expectEqual(@as(u32, 0), state.packet_number);
}

test "polling an unconnected port does nothing" {
    var system = InputSystem{};
    var host = controller_map.HostState{};
    host.buttons.insert(.south);
    try std.testing.expect(!try system.poll(0, host));
    try std.testing.expectEqual(@as(u64, 0), system.health().polls);
}

test "a poll travels from host reading to guest state" {
    var system = InputSystem{};
    try system.connect(0);
    var host = controller_map.HostState{};
    host.buttons.insert(.south);
    host.left_stick_x = 1.0;

    try std.testing.expect(try system.poll(0, host));
    const state = try system.readState(0);
    try std.testing.expect(state.gamepad.isPressed(.a));
    try std.testing.expectEqual(contract.thumb_max, state.gamepad.thumb_lx);
}

test "dead zones are applied on the way through" {
    var system = InputSystem{};
    try system.connect(0);
    // 0.1 of full deflection is ~3277, inside the 7849 left dead zone.
    const host = controller_map.HostState{ .left_stick_x = 0.1 };
    _ = try system.poll(0, host);
    const state = try system.readState(0);
    try std.testing.expectEqual(@as(i16, 0), state.gamepad.thumb_lx);
}

test "the health verdict names where the path stops" {
    var system = InputSystem{};
    try std.testing.expectEqualStrings("no controller connected", system.health().verdict());

    try system.connect(0);
    try std.testing.expectEqualStrings(
        "connected but never polled: the host input loop is not running",
        system.health().verdict(),
    );

    var host = controller_map.HostState{};
    host.buttons.insert(.south);
    _ = try system.poll(0, host);
    try std.testing.expectEqualStrings(
        "polled but never read: input is being published and the title is not asking for it",
        system.health().verdict(),
    );

    _ = try system.readState(0);
    try std.testing.expectEqualStrings(
        "input is flowing: polls change state and the title reads it",
        system.health().verdict(),
    );
}

test "a title reading an unchanging pad is reported distinctly" {
    var system = InputSystem{};
    try system.connect(0);
    // Poll with a neutral pad: publish is a no-op change-wise after the first.
    _ = try system.poll(0, .{});
    _ = try system.readState(0);
    try std.testing.expectEqualStrings(
        "read but never changed: the title is asking and every poll reported the same pad",
        system.health().verdict(),
    );
}

test "several ports are counted independently" {
    var system = InputSystem{};
    try system.connect(0);
    try system.connect(2);
    try std.testing.expectEqual(@as(u32, 2), system.connectedCount());
    try std.testing.expectEqual(@as(u32, 2), system.health().connected);
}

test "the packet number wraps rather than trapping" {
    // A long session will overflow it. Wrapping is correct — a title compares
    // for inequality, not ordering — but a trap here would kill the run.
    var slot = Port{ .connected = true };
    slot.state.packet_number = std.math.maxInt(u32);
    try std.testing.expect(slot.publish(.{ .buttons = contract.Button.a.mask() }));
    try std.testing.expectEqual(@as(u32, 0), slot.state.packet_number);
}
