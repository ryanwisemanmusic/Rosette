//! Recovery of generated-code control transfers, as a measured population.
//!
//! Individual recoveries each report themselves, and each report reads like the
//! last one. What no single report can say is how much of the generated code the
//! bounded machine can get through — whether a run met one stubborn site or
//! forty, and whether the sites it stops on are the sites it always stops on.
//! Without that, the same investigation is repeated at every occurrence, because
//! every occurrence looks like the first.
//!
//! This owns the population, not the recoveries. It does not decide what any
//! family does; it records which family acted, whether execution got through,
//! and where — so "x traversed, y halted, of z distinct sites" is answerable.

pub const census = @import("census.zig");

pub const Census = census.Census;
pub const Family = census.Family;
pub const Outcome = census.Outcome;
pub const Site = census.Site;
pub const Coverage = census.Census.Coverage;

test {
    _ = census;
}
