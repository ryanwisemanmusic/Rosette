//! Ownership.
//!
//! Rosette's recurring failure mode is not duplicated work — it is *duplicated
//! authority*. Several subsystems each believe they own an input, decide
//! independently, and act, so the order they happened to be written in becomes
//! the tie-break. Fixing one of them then moves a fault into another's
//! jurisdiction, and the regression appears somewhere unrelated.
//!
//! Concrete cases found in this tree: the `67 8B 03` fault had five owners;
//! retained execution history had seven; "is this rbp frame a usable host
//! continuation" had three, with three mutually inconsistent answers; and a
//! write made by a Rosette repair was indistinguishable from a guest store.
//!
//! This library owns the *arbitration*, not the work:
//!
//!   * `arbiter` — exactly one owner per input, with overlapping claims
//!     reported rather than resolved by declaration order.
//!   * `ledger` — per-family counters, log throttle and loop guard, so no
//!     family can spend, reset, or silence another's budget.
//!   * `authorship` — who wrote a piece of guest state, so a repair is never
//!     mistaken for guest behaviour.
//!   * `watch` — which guest memory is worth keeping provenance for, discovered
//!     from behaviour instead of predicted by an operator before the run.
//!   * `budget` — what instrumentation is allowed to cost, so observers cannot
//!     each decide independently to spend the run's wall clock.
//!   * `lifetime` — when Rosette discarded a guest range's backing, so
//!     address-keyed evidence is never mistaken for evidence about the guest.
//!   * `allocation` — which allocator issued an address, so a release is routed
//!     by owner rather than by the address range it happens to fall in.
//!
//! What it deliberately does not do is impose a shape on the owners themselves.
//! They differ in what they prove and what they mutate, and unifying their
//! structure would conceal exactly the differences that matter. Selection,
//! accounting and authorship are shared; judgement is not.

pub const arbiter = @import("arbiter.zig");
pub const ledger = @import("ledger.zig");
pub const authorship = @import("authorship.zig");
pub const watch = @import("watch.zig");
pub const budget = @import("budget.zig");
pub const lifetime = @import("lifetime.zig");
pub const allocation = @import("allocation.zig");

pub const Arbiter = arbiter.Arbiter;
pub const Outcome = arbiter.Outcome;
pub const Ledger = ledger.Ledger;
pub const throttled = ledger.throttled;
pub const Author = authorship.Author;
pub const AuthorScope = authorship.Scope;
pub const WatchSet = watch.Set;
pub const Budget = budget.Budget;
pub const LifetimeRegistry = lifetime.Registry;
pub const AllocationRegistry = allocation.Registry;
pub const AllocationOwner = allocation.Owner;
pub const DiscardReason = lifetime.Reason;

test {
    _ = arbiter;
    _ = ledger;
    _ = authorship;
    _ = watch;
    _ = budget;
    _ = lifetime;
    _ = allocation;
}
