//! Host controller discovery boundary.
//!
//! macOS exposes gamepads through GameController (modern, high level) and
//! IOKit HID (older, lower level). Which one a given pad appears on is not
//! something Rosette chooses, so this file models the *boundary*: what a
//! discovered device looks like, how it maps to a console port, and whether
//! anything was discovered at all.
//!
//! ## Why discovery is its own reportable stage
//!
//! "The controller does not work" has an answer chain, and the first link is
//! whether the host ever saw a device. That is not observable from the input
//! system's counters — a system that is polling a port nothing is attached to
//! and a system whose host framework never enumerated look identical from
//! upstream. Recording the discovery outcome makes the first link checkable.

const std = @import("std");
const contract = @import("xenia_input_contract");

/// Which host framework a device came from.
pub const HostFramework = enum {
    game_controller,
    iokit_hid,
    /// No framework has reported anything.
    none,
};

pub const DeviceClass = enum {
    gamepad,
    /// A device the host recognises but that cannot drive a console port.
    unsupported,

    pub fn canDrivePort(self: DeviceClass) bool {
        return self == .gamepad;
    }
};

pub const Device = struct {
    /// Opaque host identifier. Not a pointer: an identifier that outlives the
    /// device it names must not be dereferenceable.
    host_id: u64,
    framework: HostFramework,
    class: DeviceClass = .gamepad,
    has_rumble: bool = false,
    /// The console port this device was assigned, once it has one.
    assigned_port: ?u32 = null,
};

pub const Error = error{
    /// Every console port already has a device.
    NoFreePort,
    /// The device cannot drive a port.
    UnsupportedDevice,
    /// The device is already assigned.
    AlreadyAssigned,
};

pub const Discovery = struct {
    devices: [contract.max_controller_count]?Device = @splat(null),
    /// Devices the host reported, including ones that could not be assigned.
    devices_seen: u64 = 0,
    devices_rejected: u64 = 0,

    /// Assign a discovered device to the lowest free port.
    ///
    /// Lowest-free rather than round-robin: a title that only reads port 0
    /// must see the first pad plugged in, and a rotating assignment makes
    /// "which port am I" depend on history.
    pub fn attach(self: *Discovery, device: Device) Error!u32 {
        self.devices_seen +|= 1;
        if (!device.class.canDrivePort()) {
            self.devices_rejected +|= 1;
            return error.UnsupportedDevice;
        }
        for (self.devices) |existing| {
            if (existing) |present| {
                if (present.host_id == device.host_id) return error.AlreadyAssigned;
            }
        }
        for (&self.devices, 0..) |*slot, index| {
            if (slot.* == null) {
                var assigned = device;
                assigned.assigned_port = @intCast(index);
                slot.* = assigned;
                return @intCast(index);
            }
        }
        self.devices_rejected +|= 1;
        return error.NoFreePort;
    }

    /// Remove a device by host identifier. Returns the port it held.
    pub fn detach(self: *Discovery, host_id: u64) ?u32 {
        for (&self.devices, 0..) |*slot, index| {
            if (slot.*) |present| {
                if (present.host_id == host_id) {
                    slot.* = null;
                    return @intCast(index);
                }
            }
        }
        return null;
    }

    pub fn deviceAt(self: *const Discovery, port: u32) ?Device {
        if (!contract.isControllerPort(port)) return null;
        return self.devices[port];
    }

    pub fn attachedCount(self: *const Discovery) u32 {
        var count: u32 = 0;
        for (self.devices) |slot| {
            if (slot != null) count += 1;
        }
        return count;
    }

    /// The first link in the "controller does not work" chain.
    pub fn verdict(self: *const Discovery) []const u8 {
        if (self.devices_seen == 0) {
            return "nothing discovered: no host framework has reported a device, so no port can be driven";
        }
        if (self.attachedCount() == 0) {
            return "devices seen but none attached: every reported device was rejected or unassignable";
        }
        return "attached: at least one host device is driving a console port";
    }
};

test "a fresh discovery has seen nothing" {
    const discovery = Discovery{};
    try std.testing.expectEqual(@as(u32, 0), discovery.attachedCount());
    try std.testing.expectEqualStrings(
        "nothing discovered: no host framework has reported a device, so no port can be driven",
        discovery.verdict(),
    );
}

test "the first pad takes port zero" {
    // A title that only reads port 0 must see the first pad plugged in.
    var discovery = Discovery{};
    const port = try discovery.attach(.{ .host_id = 0xAAAA, .framework = .game_controller });
    try std.testing.expectEqual(@as(u32, 0), port);
    try std.testing.expectEqual(@as(u32, 0), discovery.deviceAt(0).?.assigned_port.?);
    try std.testing.expectEqualStrings(
        "attached: at least one host device is driving a console port",
        discovery.verdict(),
    );
}

test "ports fill in order and then refuse" {
    var discovery = Discovery{};
    var index: u64 = 0;
    while (index < contract.max_controller_count) : (index += 1) {
        const port = try discovery.attach(.{ .host_id = 0x1000 + index, .framework = .iokit_hid });
        try std.testing.expectEqual(@as(u32, @intCast(index)), port);
    }
    try std.testing.expectError(error.NoFreePort, discovery.attach(.{
        .host_id = 0x9999,
        .framework = .iokit_hid,
    }));
    try std.testing.expectEqual(@as(u32, 4), discovery.attachedCount());
}

test "a detached port is reused by the next device" {
    // Reuse rather than permanent retirement: unplugging and replugging must
    // land back on port 0, or a title reading only port 0 loses its pad.
    var discovery = Discovery{};
    _ = try discovery.attach(.{ .host_id = 0xAAAA, .framework = .game_controller });
    _ = try discovery.attach(.{ .host_id = 0xBBBB, .framework = .game_controller });

    try std.testing.expectEqual(@as(u32, 0), discovery.detach(0xAAAA).?);
    try std.testing.expect(discovery.deviceAt(0) == null);

    const port = try discovery.attach(.{ .host_id = 0xCCCC, .framework = .game_controller });
    try std.testing.expectEqual(@as(u32, 0), port);
}

test "detaching an unknown device reports nothing rather than guessing" {
    var discovery = Discovery{};
    try std.testing.expect(discovery.detach(0xDEAD) == null);
}

test "the same device cannot occupy two ports" {
    var discovery = Discovery{};
    _ = try discovery.attach(.{ .host_id = 0xAAAA, .framework = .game_controller });
    try std.testing.expectError(error.AlreadyAssigned, discovery.attach(.{
        .host_id = 0xAAAA,
        .framework = .game_controller,
    }));
    try std.testing.expectEqual(@as(u32, 1), discovery.attachedCount());
}

test "an unsupported device is rejected and counted" {
    var discovery = Discovery{};
    try std.testing.expectError(error.UnsupportedDevice, discovery.attach(.{
        .host_id = 0xAAAA,
        .framework = .iokit_hid,
        .class = .unsupported,
    }));
    try std.testing.expectEqual(@as(u64, 1), discovery.devices_seen);
    try std.testing.expectEqual(@as(u64, 1), discovery.devices_rejected);
    // Seen but not attached is its own verdict — distinct from seeing nothing.
    try std.testing.expectEqualStrings(
        "devices seen but none attached: every reported device was rejected or unassignable",
        discovery.verdict(),
    );
}

test "an out of range port has no device" {
    const discovery = Discovery{};
    try std.testing.expect(discovery.deviceAt(4) == null);
    try std.testing.expect(discovery.deviceAt(0xFFFF) == null);
}

test "both host frameworks can drive a port" {
    var discovery = Discovery{};
    _ = try discovery.attach(.{ .host_id = 1, .framework = .game_controller });
    _ = try discovery.attach(.{ .host_id = 2, .framework = .iokit_hid });
    try std.testing.expectEqual(HostFramework.game_controller, discovery.deviceAt(0).?.framework);
    try std.testing.expectEqual(HostFramework.iokit_hid, discovery.deviceAt(1).?.framework);
}
