//! Route-independent: the synthetic Xbox 360 user profile Rosette presents.
//!
//! There is no signed-in account behind an emulator, but XAM is not optional:
//! a title asks who is playing before it will load a save, and Halo 3 asks
//! early. So Rosette answers with a fixed, fabricated profile, and the point of
//! this package is that the answer is *the same every time*.
//!
//! ## Why a constant profile is the contract
//!
//! A profile that varies between runs makes save data, achievements, and
//! per-user settings land in different places each launch, and the title's own
//! caching then produces a different startup path on the second run than the
//! first. That is the kind of non-determinism that gets misread as an emulator
//! bug somewhere else entirely. Fixing the XUID and gamertag at compile time
//! removes that whole class.
//!
//! ## What this package is not
//!
//! * It is not a sign-in. It cannot report that a user is present; it says what
//!   Rosette answers *if* asked.
//! * It is not a profile store. Save data, achievement unlocks and settings are
//!   mutable and live under `lib/`.
//! * It is not an entitlement. A privilege level here is a fabricated answer to
//!   a fabricated account, and grants nothing.

const std = @import("std");

/// Gamertags are a fixed 16-byte field, NUL-padded, not NUL-terminated-and-
/// then-whatever. The padding is part of the ABI: a title that hashes the
/// whole field gets a different answer if the tail is uninitialised, which is
/// how a "random" profile id appears from a constant gamertag.
pub const gamertag_bytes: usize = 16;

pub const Gamertag = [gamertag_bytes]u8;

/// The name Rosette signs in as.
pub const gamertag: Gamertag = blk: {
    var padded: Gamertag = [_]u8{0} ** gamertag_bytes;
    const name = "Rosette";
    @memcpy(padded[0..name.len], name);
    break :blk padded;
};

/// A XUID with the offline bit set.
///
/// This is the load-bearing detail of the whole package. Real Xbox Live XUIDs
/// have 0x0009 in the high word; offline profiles use 0xE000. A title that
/// sees an online-shaped XUID may try to reach Live, and the failure surfaces
/// far from here as a hang or a sign-out. Declaring the profile offline up
/// front is what keeps the title on the local path.
pub const offline_xuid_prefix: u64 = 0xE000_0000_0000_0000;
pub const xuid: u64 = offline_xuid_prefix | 0x0000_0000_0000_0001;

/// Privilege 0 is an adult account with no restrictions. Anything else asks
/// the title to enforce parental controls Rosette has no way to satisfy.
pub const privilege_level: u32 = 0;

/// LCIDs. 0x0409 is en-US for both country and locale; they are separate
/// fields because a console can be a US console running in French.
pub const country_en_us: u16 = 0x0409;
pub const locale_en_us: u16 = 0x0409;

/// The seed the avatar generator is fed. Constant for the same reason the
/// XUID is: a varying avatar is a varying cache key.
pub const avatar_seed: u32 = 42;

/// Signed-in state as XAM reports it.
pub const SignInState = enum(u32) {
    not_signed_in = 0,
    signed_in_locally = 1,
    signed_in_to_live = 2,

    /// Whether this state should make a title attempt a network round trip.
    pub fn impliesLiveConnectivity(self: SignInState) bool {
        return self == .signed_in_to_live;
    }
};

/// The state Rosette reports. Locally signed in — present enough to load a
/// save, not present enough to invite a Live call.
pub const sign_in_state: SignInState = .signed_in_locally;

/// The whole fabricated profile, as one value.
pub const SyntheticUser = struct {
    gamertag: Gamertag = gamertag,
    xuid: u64 = xuid,
    privilege_level: u32 = privilege_level,
    country: u16 = country_en_us,
    locale: u16 = locale_en_us,
    avatar_seed: u32 = avatar_seed,
    sign_in_state: SignInState = sign_in_state,

    /// The gamertag without its NUL padding, for display and comparison.
    pub fn name(self: *const SyntheticUser) []const u8 {
        const end = std.mem.indexOfScalar(u8, &self.gamertag, 0) orelse gamertag_bytes;
        return self.gamertag[0..end];
    }

    /// Whether this profile is offline-shaped.
    pub fn isOffline(self: *const SyntheticUser) bool {
        return self.xuid & 0xFFFF_0000_0000_0000 == offline_xuid_prefix and
            !self.sign_in_state.impliesLiveConnectivity();
    }
};

pub const default_user: SyntheticUser = .{};

/// Whether a user index addresses the one profile Rosette has.
///
/// Four ports exist, but only port 0 is signed in. A title that iterates all
/// four must get "not signed in" for 1..3 rather than four copies of the same
/// XUID, or it will believe four people are playing.
pub fn isSignedInUserIndex(index: u32) bool {
    return index == 0;
}

pub fn contractIsWellFormed() bool {
    if (gamertag[gamertag_bytes - 1] != 0) return false;
    if (xuid & 0xFFFF_0000_0000_0000 != offline_xuid_prefix) return false;
    if (sign_in_state.impliesLiveConnectivity()) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the XUID is offline shaped" {
    // The bug this exists to prevent: a XUID that looks like a Live account
    // sends the title down a network path that cannot complete under an
    // emulator, and the resulting stall shows up nowhere near XAM.
    try std.testing.expectEqual(offline_xuid_prefix, xuid & 0xFFFF_0000_0000_0000);
    try std.testing.expect(xuid != 1);
    try std.testing.expect(default_user.isOffline());
}

test "signing in locally does not imply Live" {
    try std.testing.expect(!SignInState.signed_in_locally.impliesLiveConnectivity());
    try std.testing.expect(!SignInState.not_signed_in.impliesLiveConnectivity());
    try std.testing.expect(SignInState.signed_in_to_live.impliesLiveConnectivity());
}

test "the gamertag is padded to its full field, not merely terminated" {
    try std.testing.expectEqual(@as(usize, 16), gamertag.len);
    try std.testing.expectEqualStrings("Rosette", default_user.name());
    // Every byte after the name is zero. A title hashing the field must get
    // the same digest on every run.
    for (gamertag[7..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "the profile is identical across constructions" {
    // Determinism is the entire point: two independently constructed default
    // users must be byte-identical, or save paths diverge between runs.
    const first = SyntheticUser{};
    const second = SyntheticUser{};
    try std.testing.expectEqual(first.xuid, second.xuid);
    try std.testing.expectEqualSlices(u8, &first.gamertag, &second.gamertag);
    try std.testing.expectEqual(first.avatar_seed, second.avatar_seed);
}

test "only port zero is signed in" {
    try std.testing.expect(isSignedInUserIndex(0));
    try std.testing.expect(!isSignedInUserIndex(1));
    try std.testing.expect(!isSignedInUserIndex(3));
}

test "the locale is en-US in both fields" {
    try std.testing.expectEqual(@as(u16, 0x0409), country_en_us);
    try std.testing.expectEqual(@as(u16, 0x0409), locale_en_us);
    try std.testing.expectEqual(@as(u32, 0), privilege_level);
}
