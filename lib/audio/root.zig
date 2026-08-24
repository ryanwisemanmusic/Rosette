//! Audio.
//!
//! The audio path has the least legible failure mode in the runtime: silence.
//! Every stage produces silence when it is broken, and silence when the stage
//! above it is broken, so the symptom carries no information about where to
//! look. A title with no sound could be a guest that never programmed a voice,
//! a decoder Rosette does not have, a mixer that never ran, or a host device
//! that was opened and never called.
//!
//! So this library is organised around making those distinguishable. Each layer
//! carries counters that can only be advanced by that layer actually doing its
//! work, and each reports a verdict naming the *earliest* stage that failed:
//!
//! * `audio_context` — did the title program and enable a voice at all?
//! * `xma_decoder` — is the bitstream navigable, and is the codec core present?
//! * `audio_system` — did voices reach a completed mix frame?
//! * `audio_ring` — is the producer or the consumer behind?
//! * `coreaudio_driver` — did the host ever ask for audio?
//!
//! Read them in that order. The first one that reports a problem owns it, and
//! the ones after it are reporting the consequence.
//!
//! ## The honest boundary
//!
//! Rosette does not have an XMA codec core. `xma_decoder` navigates the
//! bitstream and reports `UnimplementedCodec` for the decode itself, and every
//! layer above propagates that as a named, counted state rather than as
//! silence. A half-written decoder would be worse: it would produce samples, so
//! every layer would report success, and the resulting noise would be blamed on
//! the mixer or the device.
//!
//! The console-side geometry these modules obey is
//! `pkg/common/xenia/audio-contract`; the route's mix width and denormal
//! controls are `pkg/{x86,ARM64}/xenia/audio-driver`.

pub const audio_ring = @import("audio_ring.zig");
pub const xma_decoder = @import("xma_decoder.zig");
pub const audio_context = @import("audio_context.zig");
pub const audio_system = @import("audio_system.zig");
pub const coreaudio_driver = @import("coreaudio_driver.zig");

pub const AudioRing = audio_ring.AudioRing;
pub const Context = audio_context.Context;
pub const Mixer = audio_system.Mixer;
pub const Driver = coreaudio_driver.Driver;
pub const StreamFormat = coreaudio_driver.StreamFormat;
pub const SinkKind = coreaudio_driver.SinkKind;

// A `pub const` re-export does not root a module's tests. Without this block
// every test in this library is compiled and never run, which is the quietest
// possible way for a test suite to stop being a gate.
test {
    _ = audio_ring;
    _ = xma_decoder;
    _ = audio_context;
    _ = audio_system;
    _ = coreaudio_driver;
}
