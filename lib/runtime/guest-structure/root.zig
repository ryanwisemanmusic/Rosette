//! Observed shape of guest structures.
//!
//! Answers a class of question the fault site cannot: not "what happened at
//! this instruction" but "what never happened anywhere in the run". A field
//! read and never written is a missing store; a field read and written is a
//! wrong value. Those need opposite investigations, and the difference is only
//! visible as an absence measured across the whole run.

pub const field_profile = @import("field_profile.zig");

pub const Profile = field_profile.Profile;
pub const Field = field_profile.Field;
pub const Access = field_profile.Access;

test {
    _ = field_profile;
}
