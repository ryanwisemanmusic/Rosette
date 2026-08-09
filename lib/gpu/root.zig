//! GPU.
//!
//! The graphics stack is where a translated title's failures are least legible:
//! when nothing renders, every counter reads zero, and zero is what a working
//! pipeline reads before its first frame too. The subsystem cannot distinguish
//! "not started" from "started and stuck" from "stuck upstream of here" without
//! knowing what order things were supposed to happen in.
//!
//! So this library owns both the guest-bootstrap observation contract and the
//! backend-neutral host execution boundary. It answers which guest-driven step
//! was first not to happen, then — only after authentic work arrives — provides
//! Rosette-native devices, queues, resources, synchronization and presentation
//! without exposing Vulkan or Metal handles to the emulator frontend.
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
pub const api = @import("api.zig");
pub const backend = @import("backend.zig");
pub const handles = @import("handles.zig");
pub const runtime = @import("runtime.zig");

pub const Step = bootstrap.Step;
pub const Contract = bootstrap.Contract;
pub const Frontier = bootstrap.Frontier;
pub const ForwardingContract = forwarding.Contract;
pub const Stage = forwarding.Stage;
pub const Fidelity = forwarding.Fidelity;
pub const Runtime = runtime.Runtime;
pub const HandshakeRequest = api.HandshakeRequest;
pub const HandshakeResponse = api.HandshakeResponse;
pub const Capability = api.Capability;
pub const CapabilitySet = api.CapabilitySet;
pub const BackendKind = api.BackendKind;
pub const Handle = handles.Handle;

test {
    _ = bootstrap;
    _ = forwarding;
    _ = api;
    _ = backend;
    _ = handles;
    _ = runtime;
}
