//! Route-independent: XNotify identifiers and the area/index encoding behind
//! them.
//!
//! A title registers an `XNotifyListener` for one or more *areas* and then
//! polls it. The kernel broadcasts notifications with a 32-bit id; the listener
//! delivers those whose area it subscribed to.
//!
//! ## Why this is on the critical path for a title that appears to hang
//!
//! A title's startup commonly waits for a notification before it will proceed —
//! `SystemUI` going away, sign-in state settling, storage devices enumerating.
//! If the emulator never broadcasts one, the title waits forever, and what an
//! observer sees is a thread parked on a condition variable with nothing
//! obviously wrong. Rosette's own `DEADLOCK PREDICTOR` describes exactly that
//! shape: `NEVER_NOTIFIED`, one waiter, zero notifiers, "waiting for a code
//! path that has not been reached".
//!
//! A notification id is not guessable from context, so having the table is the
//! difference between "something is parked" and "it is waiting for
//! `SystemSignInChanged`, which nothing has broadcast".
//!
//! ## The id is a bitfield, and the obvious reading of it is wrong
//!
//! A notification id is not an opaque number. It packs three fields:
//!
//! ```text
//!   bits  0..15  local_id    which notification within the area
//!   bits 16..24  version     minimum kernel version that raises it
//!   bits 25..30  mask_index  which subscription bit delivers it
//!   bit     31   reserved
//! ```
//!
//! The `mask_index` is at bit **25**, not at a byte boundary, and the
//! subscription mask is `1 << mask_index`. Two readings look plausible and are
//! both wrong: shifting by 24 puts Live notifications in index 2 rather than 1,
//! and shifting by 16 reads the *version* field as the index — which sends
//! every notification to a subscription nobody holds.
//!
//! The version field is the second trap. `0x00060019` is not "area 6": it is
//! version 6, local id 0x19, mask index 0. A listener created with a
//! `max_version` below 6 will not receive it, and that filtering is invisible
//! unless the field is decoded as a version.
//!
//! ## What this package is not
//!
//! * It is not a listener. It queues nothing and delivers nothing.
//! * It cannot say a notification was broadcast. Every predicate answers a
//!   question about an id it was handed.
//! * It does not decide what a title needs. Which notification a given title
//!   waits for is a property of that title.

const std = @import("std");

/// Bit 31 is reserved. Several ids set it; it is not part of any field the
/// listener consults, so it must be ignored rather than folded into one.
pub const reserved_bit: u32 = 0x8000_0000;

pub const local_id_bits: u5 = 16;
pub const local_id_mask: u32 = 0xFFFF;

pub const version_shift: u5 = 16;
pub const version_mask: u32 = 0x1FF;

/// The subscription index. Bit 25, six bits wide — not a byte boundary.
pub const mask_index_shift: u5 = 25;
pub const mask_index_mask: u32 = 0x3F;

/// Subscription areas, as `XNotifyCreateListener` takes them.
pub const AreaMask = struct {
    pub const system: u32 = 0x0000_0001;
    pub const live: u32 = 0x0000_0002;
    pub const friends: u32 = 0x0000_0004;
    pub const custom: u32 = 0x0000_0008;
    pub const xmp: u32 = 0x0000_0020;
    pub const messenger: u32 = 0x0000_0040;
    pub const party: u32 = 0x0000_0080;
    pub const all: u32 = 0x0000_00EF;
};

/// The notification ids Xenia names.
pub const Notification = enum(u32) {
    system_title_load = 0x8000_0001,
    system_time_zone = 0x8000_0002,
    system_language = 0x8000_0003,
    system_video_flags = 0x8000_0004,
    system_audio_flags = 0x8000_0005,
    system_parental_control_games = 0x8000_0006,
    system_parental_control_password = 0x8000_0007,
    system_parental_control_movies = 0x8000_0008,
    system_ui = 0x0000_0009,
    system_sign_in_changed = 0x0000_000A,
    system_storage_devices_changed = 0x0000_000B,
    system_dash_context_changed = 0x8000_000C,
    system_tray_state_changed = 0x8000_000D,
    system_profile_setting_changed = 0x0000_000E,
    system_theme_changed = 0x8000_000F,
    system_update_changed = 0x8000_0010,
    system_mute_list_changed = 0x0000_0011,
    system_input_devices_changed = 0x0000_0012,
    system_xlive_title_update = 0x0000_0015,
    system_xlive_system_update = 0x0000_0016,
    system_input_device_config_changed = 0x0001_0013,
    system_player_timer_notice = 0x0003_0015,
    system_avatar_changed = 0x0004_0017,
    system_nui_hardware_status_changed = 0x0006_0019,
    system_nui_pause = 0x0006_001A,
    system_nui_ui_approach = 0x0006_001B,
    system_device_remap = 0x0006_001C,
    system_nui_binding_changed = 0x0006_001D,
    system_audio_latency_changed = 0x0008_001E,
    system_nui_chat_binding_changed = 0x0008_001F,
    system_input_activity_changed = 0x0009_0020,
    live_connection_changed = 0x0200_0001,
    live_invite_accepted = 0x0200_0002,
    live_link_state_changed = 0x0200_0003,
    live_content_installed = 0x0200_0007,
    live_membership_purchased = 0x0200_0008,
    live_voicechat_away = 0x0200_0009,
    live_presence_changed = 0x0200_000A,
    _,

    pub fn id(self: Notification) u32 {
        return @intFromEnum(self);
    }

    /// Whether the reserved high bit is set on this id.
    pub fn hasReservedBit(self: Notification) bool {
        return @intFromEnum(self) & reserved_bit != 0;
    }

    /// The subscription index this notification routes to.
    pub fn maskIndex(self: Notification) u32 {
        return maskIndexOf(@intFromEnum(self));
    }

    pub fn version(self: Notification) u32 {
        return versionOf(@intFromEnum(self));
    }
};

/// The subscription index a raw notification id routes to.
pub fn maskIndexOf(notification_id: u32) u32 {
    return (notification_id >> mask_index_shift) & mask_index_mask;
}

/// The minimum kernel version that raises this notification.
///
/// A listener is created with a `max_version`; one below this value will not
/// receive the notification. Decoding it is the only way that filtering is
/// visible — otherwise a title simply never gets a notification that is being
/// broadcast.
pub fn versionOf(notification_id: u32) u32 {
    return (notification_id >> version_shift) & version_mask;
}

/// The notification's identity within its subscription area.
pub fn localIdOf(notification_id: u32) u32 {
    return notification_id & local_id_mask;
}

/// The subscription bit for an index.
///
/// The mask is 64-bit in the kernel, so an index up to 63 is representable and
/// a `u32` shift would be undefined past 31.
pub fn maskBit(index: u32) u64 {
    if (index > 63) return 0;
    return @as(u64, 1) << @intCast(index);
}

/// Whether a listener subscribed to `mask` receives this notification.
pub fn isDelivered(mask: u64, notification_id: u32) bool {
    return mask & maskBit(maskIndexOf(notification_id)) != 0;
}

/// Whether a listener created with `max_version` receives it.
pub fn isVersionAccepted(max_version: u32, notification_id: u32) bool {
    return versionOf(notification_id) <= max_version;
}

/// Notifications a title commonly waits on during startup.
///
/// Not exhaustive and not a requirement — a list of the ones whose absence
/// most often presents as a title that never proceeds. Having them named is
/// what turns "a thread is parked" into a question with an answer.
pub const common_startup_waits = [_]Notification{
    .system_ui,
    .system_sign_in_changed,
    .system_storage_devices_changed,
    .system_input_devices_changed,
};

pub fn contractIsWellFormed() bool {
    if (maskIndexOf(0x8000_0001) != 0) return false;
    if (maskIndexOf(0x0200_0001) != 1) return false;
    if (versionOf(0x0006_0019) != 6) return false;
    if (AreaMask.all != 0xEF) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the mask index sits at bit 25, not at a byte boundary" {
    // Shifting by 24 puts Live at index 2 rather than 1; shifting by 16 reads
    // the version field as the index. Both send notifications to a
    // subscription nobody holds.
    try std.testing.expectEqual(@as(u32, 0), maskIndexOf(0x8000_0001));
    try std.testing.expectEqual(@as(u32, 1), maskIndexOf(0x0200_0001));

    // The two wrong readings, for contrast.
    try std.testing.expect(((0x0200_0001 >> 24) & 0x3F) != maskIndexOf(0x0200_0001));
    try std.testing.expect(((0x0200_0001 >> 16) & 0x3F) != maskIndexOf(0x0200_0001));
}

test "the version field is not an area" {
    // 0x00060019 is version 6, local id 0x19, mask index 0 — not "area 6".
    // A listener with max_version below 6 silently drops it.
    try std.testing.expectEqual(@as(u32, 6), versionOf(0x0006_0019));
    try std.testing.expectEqual(@as(u32, 0x19), localIdOf(0x0006_0019));
    try std.testing.expectEqual(@as(u32, 0), maskIndexOf(0x0006_0019));

    try std.testing.expectEqual(@as(u32, 6), Notification.system_nui_hardware_status_changed.version());
    try std.testing.expectEqual(@as(u32, 0), Notification.system_nui_hardware_status_changed.maskIndex());
}

test "the three fields do not overlap" {
    // Reconstructing an id from its parts must give the original back, minus
    // the reserved bit. If the widths were wrong this would not round trip.
    const ids = [_]u32{
        0x8000_0001, 0x0000_0009, 0x0001_0013, 0x0006_001A,
        0x0009_0020, 0x0200_0001, 0x0200_000A,
    };
    for (ids) |id| {
        const rebuilt = (maskIndexOf(id) << mask_index_shift) |
            (versionOf(id) << version_shift) |
            localIdOf(id);
        try std.testing.expectEqual(id & ~reserved_bit, rebuilt);
    }
}

test "system notifications route to index zero and Live to index one" {
    try std.testing.expectEqual(@as(u32, 0), Notification.system_ui.maskIndex());
    try std.testing.expectEqual(@as(u32, 0), Notification.system_title_load.maskIndex());
    try std.testing.expectEqual(@as(u32, 0), Notification.system_input_activity_changed.maskIndex());
    try std.testing.expectEqual(@as(u32, 1), Notification.live_connection_changed.maskIndex());
    try std.testing.expectEqual(@as(u32, 1), Notification.live_presence_changed.maskIndex());
}

test "the subscription masks line up with the indices" {
    // kXNotifySystem is bit 0 and kXNotifyLive is bit 1, which is exactly
    // 1 << mask_index for each.
    try std.testing.expectEqual(@as(u64, AreaMask.system), maskBit(0));
    try std.testing.expectEqual(@as(u64, AreaMask.live), maskBit(1));
    try std.testing.expectEqual(@as(u64, AreaMask.friends), maskBit(2));
    try std.testing.expectEqual(@as(u64, AreaMask.custom), maskBit(3));
}

test "delivery follows the subscription mask" {
    try std.testing.expect(isDelivered(AreaMask.system, Notification.system_ui.id()));
    try std.testing.expect(!isDelivered(AreaMask.system, Notification.live_connection_changed.id()));
    try std.testing.expect(isDelivered(AreaMask.live, Notification.live_connection_changed.id()));
    try std.testing.expect(isDelivered(AreaMask.all, Notification.system_ui.id()));
    try std.testing.expect(isDelivered(AreaMask.all, Notification.live_connection_changed.id()));
}

test "an empty subscription receives nothing" {
    try std.testing.expect(!isDelivered(0, Notification.system_ui.id()));
    try std.testing.expect(!isDelivered(0, Notification.live_connection_changed.id()));
}

test "version filtering is separate from mask filtering" {
    // A notification can be correctly routed and still dropped for being
    // newer than the listener asked for. Conflating the two makes a
    // version-filtered notification look like a routing bug.
    const nui_pause = Notification.system_nui_pause.id();
    try std.testing.expect(isDelivered(AreaMask.system, nui_pause));
    try std.testing.expect(!isVersionAccepted(0, nui_pause));
    try std.testing.expect(!isVersionAccepted(5, nui_pause));
    try std.testing.expect(isVersionAccepted(6, nui_pause));
    try std.testing.expect(isVersionAccepted(99, nui_pause));

    // A version-zero notification reaches even the oldest listener.
    try std.testing.expect(isVersionAccepted(0, Notification.system_ui.id()));
}

test "the startup waits reach a version-zero system listener" {
    // They are the notifications whose absence presents as a title that never
    // proceeds, so all of them must reach the plainest possible listener.
    for (common_startup_waits) |notification| {
        try std.testing.expect(isDelivered(AreaMask.system, notification.id()));
        try std.testing.expect(isVersionAccepted(0, notification.id()));
    }
    try std.testing.expectEqual(@as(usize, 4), common_startup_waits.len);
}

test "the all mask does not cover every index" {
    // 0xEF has a hole at bit 4. A listener asking for "all" is not asking for
    // literally everything, so an undelivered index-4 notification is correct
    // rather than a listener bug.
    try std.testing.expectEqual(@as(u64, 0), AreaMask.all & maskBit(4));
    try std.testing.expect(AreaMask.all & maskBit(0) != 0);
    try std.testing.expect(AreaMask.all & maskBit(5) != 0);
}

test "the reserved bit does not affect routing" {
    // Several ids set bit 31. Folding it into any field changes where the
    // notification goes; ignoring it is what keeps SystemTitleLoad in index 0.
    try std.testing.expect(Notification.system_title_load.hasReservedBit());
    try std.testing.expect(!Notification.system_ui.hasReservedBit());
    try std.testing.expectEqual(
        maskIndexOf(0x0000_0001),
        maskIndexOf(0x8000_0001),
    );
    try std.testing.expect(isDelivered(AreaMask.system, Notification.system_title_load.id()));
}

test "an unnamed notification still routes" {
    // The kernel can broadcast an id Xenia does not name; a listener must
    // route it rather than trapping on a checked cast.
    const unnamed: Notification = @enumFromInt(0x0200_0099);
    try std.testing.expectEqual(@as(u32, 1), unnamed.maskIndex());
    try std.testing.expect(isDelivered(AreaMask.live, unnamed.id()));
}

test "mask bits are bounded by the kernel's 64-bit mask" {
    try std.testing.expectEqual(@as(u64, 1), maskBit(0));
    try std.testing.expectEqual(@as(u64, 1) << 63, maskBit(63));
    // Past the mask width yields no bit rather than an undefined shift.
    try std.testing.expectEqual(@as(u64, 0), maskBit(64));
    try std.testing.expectEqual(@as(u64, 0), maskBit(0xFFFF));
    // The field is six bits, so no real id can exceed 63 anyway.
    try std.testing.expect(mask_index_mask == 0x3F);
}
