//! Guest byte order.
//!
//! A big-endian guest on a little-endian host converts on every guest-memory
//! load and store. A missed conversion produces the right value in the wrong
//! order — and, uniquely among corruptions, it says so: reverse it and a guest
//! address appears, which almost never happens by accident.
//!
//! This owns the counting, not the conversion. `generated_endian_contract`
//! decides whether to repair one site; this decides whether the run has one bad
//! site or a bad conversion path, which is a different question with a different
//! answer and was previously unaskable.

pub const survey = @import("survey.zig");

pub const Order = survey.Order;
pub const Finding = survey.Finding;
pub const Survey = survey.Survey;
pub const Slot = survey.Slot;

test {
    _ = survey;
}
