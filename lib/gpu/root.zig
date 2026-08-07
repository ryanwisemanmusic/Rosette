//! GPU.
//!
//! The graphics stack is where a translated title's failures are least legible:
//! when nothing renders, every counter reads zero, and zero is what a working
//! pipeline reads before its first frame too. The subsystem cannot distinguish
//! "not started" from "started and stuck" from "stuck upstream of here" without
//! knowing what order things were supposed to happen in.
//!
//! So this library owns the *order and its preconditions*, not the rendering.
//! It answers one question — which step of the guest-driven bootstrap was the
//! first not to happen, and was it even reachable — because that is the question
//! that decides whether to look at the GPU at all.
//!
//! Two barriers stand between a translated title and real pixels, and they are
//! independent: the guest must drive its GPU lifecycle (`bootstrap`), and the
//! runtime must forward the graphics calls to the host driver (`forwarding`).
//! Neither is visible in the other's counters, and fixing the second while the
//! first is stalled produces a correct pipeline with nothing flowing through it.
//!
//! It deliberately never performs a step on the guest's behalf. Registering a
//! callback or priming a ring the guest never asked for would turn the one
//! honest signal in the subsystem into a fabricated one, and the frontier would
//! then report progress that did not happen.

pub const bootstrap = @import("bootstrap.zig");
pub const forwarding = @import("forwarding.zig");

pub const Step = bootstrap.Step;
pub const Contract = bootstrap.Contract;
pub const Frontier = bootstrap.Frontier;
pub const ForwardingContract = forwarding.Contract;
pub const Stage = forwarding.Stage;
pub const Fidelity = forwarding.Fidelity;

test {
    _ = bootstrap;
    _ = forwarding;
}
