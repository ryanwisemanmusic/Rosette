//! Guest memory protection.
//!
//! Owns one question: when an access is refused, *who* refused it and was that
//! correct. Three situations produce an identical observation — a deliberate
//! guest trap, a host page-size artifact, and a genuine violation — and they
//! call for opposite responses. Only one of the three is ever the runtime's bug.
//!
//! Not a protection *implementation*: the sparse manager owns placement and
//! enforcement. This owns the reading of a refusal, which the manager cannot
//! give because it only knows what the host said no to.

pub const refusal = @import("refusal.zig");

pub const Classification = refusal.Classification;
pub const Verdict = refusal.Verdict;
pub const Query = refusal.Query;
pub const Census = refusal.Census;
pub const Access = refusal.Access;

test {
    _ = refusal;
}
