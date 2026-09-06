//! Preflight.
//!
//! Owns one question, asked before a guest application is allowed to run: is
//! everything this run depends on actually in place. Not "did something fail" —
//! the runtime already answers that once things go wrong — but "would we be able
//! to tell if it had", asked while the evidence is still present.
//!
//! The failures this exists for are the silent ones. A configuration option that
//! never bound, an export resolved to nothing, a graphics device that was never
//! acquired: none of them traps, none of them logs, and the run proceeds for
//! twenty minutes producing counters that describe the consequence and never the
//! cause. By the time a zero swap counter is visible, the state that would
//! explain it — that the option meant to force a swap was read as 0 rather than
//! 7500 — is an hour gone.
//!
//! So the contract is: state the precondition, evaluate it, report expected next
//! to observed, and stop the run where the evidence lives if continuing would
//! mislead. Three outcomes rather than two, because a check that could not be
//! evaluated has told you nothing and counting it as a pass is what makes a
//! green report meaningless.
//!
//! `check` is the general machinery and has no idea what it is inspecting.
//! `xenia` is the current check set, deliberately specific: its vocabulary has
//! no meaning for another guest, and generalising it early would produce an
//! abstraction that fits nothing. When a second guest needs preflight, the split
//! is already in the right place.
//!
//! Deliberately never repairs. A gate that fixes what it finds hides the defect
//! and guarantees the next person meets it too.

pub const check = @import("check.zig");
pub const host_capability = @import("host_capability.zig");
pub const component_readiness = @import("component_readiness.zig");
pub const xenia = @import("xenia.zig");
pub const observation = @import("observation.zig");
pub const collector = @import("collector.zig");

pub const Severity = check.Severity;
pub const Outcome = check.Outcome;
pub const Evidence = check.Evidence;
pub const Result = check.Result;
pub const Report = check.Report;

pub const satisfied = check.satisfied;
pub const violated = check.violated;
pub const indeterminate = check.indeterminate;
pub const expectConfigValue = check.expectConfigValue;

pub const Phase = observation.Phase;
pub const Sources = observation.Sources;
pub const ConfigReading = observation.ConfigReading;
pub const evaluate = observation.evaluate;
pub const Collector = collector.Collector;

pub const HostCapability = host_capability.Capability;
pub const HostCapabilityReport = host_capability.Report;
pub const probeHostCapabilities = host_capability.probe;

pub const Component = component_readiness.Component;
pub const ComponentReadiness = component_readiness.Ledger;
pub const ComponentStanding = component_readiness.Standing;

test {
    _ = check;
    _ = host_capability;
    _ = component_readiness;
    _ = xenia;
    _ = observation;
    _ = collector;
}
