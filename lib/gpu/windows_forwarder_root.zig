//! The smallest GPU module surface required by the native Windows Vulkan
//! forwarder.
//!
//! The complete `lib/gpu/root.zig` is the console/Xenos contract library. A
//! standalone PE runner does not need to compile every console subsystem just
//! to reuse the Vulkan object forwarder, so this root exports only the shared
//! host-GPU records that the forwarder actually consumes. The types remain the
//! canonical implementations from `lib/gpu`; this is only a narrower module
//! boundary for the Windows route.

pub const api = @import("api.zig");
pub const backend = @import("backend.zig");
pub const frame_source = @import("frame_source.zig");
pub const forwarding = @import("forwarding.zig");
pub const provenance = @import("provenance.zig");
pub const runtime = @import("runtime.zig");
pub const xenos_texture = @import("xenos_texture.zig");
pub const vulkan = @import("vulkan/root.zig");

pub const ForwardingContract = forwarding.Contract;
pub const FrameSource = frame_source.Descriptor;
pub const FrameInbox = frame_source.Inbox;
pub const FrameAbsence = frame_source.Absence;
pub const FrameProvenance = provenance.Ledger;
pub const FrameClassification = provenance.Classification;
pub const NativePresenter = vulkan.Presenter;

const present_chain = @import("present_chain.zig");
pub const PresentChain = present_chain.Chain;
pub const PresentChainVerdict = present_chain.Verdict;
pub const PresentChainOwner = present_chain.Owner;
pub const PresentSwapchainRecord = present_chain.SwapchainRecord;
pub const PresentTargetKind = present_chain.TargetKind;
pub const PresentPixelEvidence = present_chain.PixelEvidence;
/// What a Vulkan command can put into the image it targets. The forwarder
/// classifies each command it forwards so a frame built only from clears is
/// never counted as a frame that carried a picture.
pub const PresentWriteKind = present_chain.WriteKind;
pub const frame_content = present_chain.frame_content;
pub const WindowGeometry = present_chain.Geometry;

test {
    _ = present_chain;
}
pub const NativePresenterStage = vulkan.Stage;
pub const Runtime = runtime.Runtime;
pub const HandshakeRequest = api.HandshakeRequest;
pub const HandshakeResponse = api.HandshakeResponse;
pub const XenosSurface = xenos_texture.Surface;

test {
    _ = api;
    _ = backend;
    _ = frame_source;
    _ = forwarding;
    _ = provenance;
    _ = runtime;
    _ = xenos_texture;
    _ = vulkan;
}
