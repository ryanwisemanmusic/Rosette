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
pub const contract = @import("contract.zig");
pub const kernel_surface = @import("kernel_surface.zig");
pub const import_binding = @import("import_binding.zig");
pub const kernel_variables = @import("kernel_variables.zig");
pub const pm4 = @import("pm4.zig");
pub const pm4_executor = @import("pm4_executor.zig");
pub const pm4_fault_journal = @import("pm4_fault_journal.zig");
pub const packet_trace = @import("packet_trace.zig");
pub const early_frontier = @import("early_frontier.zig");
pub const preinitialization = @import("preinitialization.zig");
pub const ring_payload = @import("ring_payload.zig");
pub const ring_scan = @import("ring_scan.zig");
pub const ring_view = @import("ring_view.zig");
pub const submission_provenance = @import("submission_provenance.zig");
pub const swap_substitution = @import("swap_substitution.zig");
pub const ring_injection = @import("ring_injection.zig");
pub const xenos_texture = @import("xenos_texture.zig");
pub const xenos_formats = @import("xenos_formats.zig");
pub const xenos_registers = @import("xenos_registers.zig");
pub const xenos_shader = @import("xenos_shader.zig");
pub const edram = @import("edram.zig");
pub const pipeline_state = @import("pipeline_state.zig");
pub const descriptor_binding = @import("descriptor_binding.zig");
pub const interrupt_controller = @import("interrupt_controller.zig");
pub const xenos_runtime = @import("xenos_runtime.zig");
pub const refresh_liveness = @import("refresh_liveness.zig");
pub const forwarding = @import("forwarding.zig");
pub const provenance = @import("provenance.zig");
pub const ring_publication = @import("ring_publication.zig");
pub const vd_swap_contract = @import("vd_swap_contract.zig");
pub const vd_swap_probe = @import("vd_swap_probe.zig");
pub const custody = @import("custody.zig");
pub const register_journal = @import("register_journal.zig");
pub const draw_dispatch = @import("draw_dispatch.zig");
pub const cocoa_control_plane = @import("cocoa_control_plane.zig");
pub const frame_handoff = @import("frame_handoff.zig");
pub const graphics_intent = @import("graphics_intent.zig");
pub const work_credit = @import("work_credit.zig");
pub const cocoa_runtime = @import("cocoa_runtime.zig");
pub const window_admission = @import("window_admission.zig");
pub const register_aperture = @import("register_aperture.zig");
pub const frame_source = @import("frame_source.zig");
pub const api = @import("api.zig");
pub const backend = @import("backend.zig");
pub const handles = @import("handles.zig");
pub const hardware_description = @import("hardware_description.zig");
pub const runtime = @import("runtime.zig");
pub const vulkan = @import("vulkan/root.zig");

pub const ContractClause = contract.Clause;
pub const ContractOwner = contract.Owner;
pub const ContractLedger = contract.Ledger;
pub const KernelSurface = kernel_surface.Surface;
pub const ImportBindingLedger = import_binding.Ledger;
pub const KernelVariable = kernel_variables.Variable;
pub const KernelVariableSurface = kernel_variables.Surface;
pub const Pm4Header = pm4.Header;
pub const PreinitElement = preinitialization.Element;
pub const PreinitLedger = preinitialization.Ledger;
pub const PreinitOwner = preinitialization.Owner;
pub const Pm4SwapDescription = pm4.SwapDescription;
pub const Pm4FetchConstant = pm4.FetchConstant;
pub const Pm4Executor = pm4_executor.Executor;
pub const Pm4FaultJournal = pm4_fault_journal.Journal;
pub const Pm4FaultRecord = pm4_fault_journal.Record;
pub const XenosTextureFormat = xenos_formats.TextureFormat;
pub const XenosRegisterFile = xenos_registers.RegisterFile;
pub const XenosShaderCache = xenos_shader.Cache;
pub const EdramStore = edram.Store;
pub const PipelineState = pipeline_state.State;
pub const DescriptorCache = descriptor_binding.Cache;
pub const GpuInterruptController = interrupt_controller.Controller;
pub const XenosRuntime = xenos_runtime.Runtime;
pub const RingScanSummary = ring_scan.Summary;
pub const RingPayloadDigest = ring_payload.Digest;
pub const SubmissionProvenance = submission_provenance.Ledger;
pub const SubmissionFinding = submission_provenance.Finding;
pub const RingProjection = ring_view.Projection;
pub const RingSurvey = ring_view.Survey;
pub const SubstitutionTier = swap_substitution.Tier;
pub const SubstitutionEvidence = swap_substitution.Evidence;
pub const SubstitutionLedger = swap_substitution.Ledger;
pub const RingInjection = ring_injection.Ledger;
pub const RingInject = ring_injection.Inject;
pub const XenosSurface = xenos_texture.Surface;
pub const KernelExport = kernel_surface.Export;

pub const Step = bootstrap.Step;
pub const Contract = bootstrap.Contract;
pub const Frontier = bootstrap.Frontier;
pub const LivenessMonitor = refresh_liveness.Monitor;
pub const LivenessSample = refresh_liveness.Sample;
pub const LivenessVerdict = refresh_liveness.Verdict;
pub const LivenessReport = refresh_liveness.Report;
pub const ForwardingContract = forwarding.Contract;
pub const Stage = forwarding.Stage;
pub const Fidelity = forwarding.Fidelity;
pub const FrameSource = frame_source.Descriptor;
pub const FrameInbox = frame_source.Inbox;
pub const FrameAbsence = frame_source.Absence;
pub const RingPublication = ring_publication.Tracker;
pub const VdSwapContract = vd_swap_contract.Ledger;
pub const VdSwapStage = vd_swap_contract.Stage;
pub const VdSwapSource = vd_swap_contract.Source;
pub const VdSwapBlocker = vd_swap_contract.Blocker;
pub const VdSwapPacketObservation = vd_swap_contract.PacketObservation;
pub const VdSwapChain = vd_swap_contract.Chain;
pub const VdSwapProbe = vd_swap_contract.Probe;
pub const VdSwapProbeOutcome = vd_swap_contract.ProbeOutcome;
pub const VdSwapAttribution = vd_swap_contract.Attribution;
pub const VdSwapProbeLedger = vd_swap_probe.Ledger;
pub const VdSwapStageDiagnosis = vd_swap_probe.StageDiagnosis;
pub const VdSwapDiagnosisSummary = vd_swap_probe.Summary;
pub const CustodyLedger = custody.Ledger;
pub const CustodyRecord = custody.Record;
pub const CustodyOwner = custody.Owner;
pub const CustodyState = custody.Custody;
pub const CustodyTiming = custody.Timing;
pub const CustodyRefusal = custody.Refusal;
pub const CustodyFinding = custody.Finding;
pub const RegisterJournal = register_journal.Journal;
pub const RegisterBlock = register_journal.Block;
pub const RegisterJournalVerdict = register_journal.Verdict;
pub const DrawDispatchLedger = draw_dispatch.Ledger;
pub const DrawDispatchPolicy = draw_dispatch.Policy;
pub const DrawDispatchProvenance = draw_dispatch.Provenance;
pub const DrawDispatchOutcome = draw_dispatch.Outcome;
pub const DrawDispatchEffect = draw_dispatch.Effect;
pub const DrawDispatchFinding = draw_dispatch.Finding;
pub const SuppliedSurface = draw_dispatch.SuppliedSurface;
pub const CocoaGraphicsControlPlane = cocoa_control_plane.ControlPlane;
pub const CocoaGraphicsControlSummary = cocoa_control_plane.Summary;
pub const CocoaFrameHandoffLedger = frame_handoff.Ledger;
pub const CocoaFrameDescriptor = frame_handoff.Descriptor;
pub const GraphicsIntent = graphics_intent.Intent;
pub const GraphicsIntentResolution = graphics_intent.Resolution;
pub const GraphicsIntentLedger = graphics_intent.Ledger;
pub const GraphicsIntentRequest = graphics_intent.Request;
pub const GpuWorkCreditLedger = work_credit.Ledger;
pub const GpuWorkCreditClaim = work_credit.Claim;
pub const CocoaGraphicsRuntime = cocoa_runtime.Runtime;
pub const CocoaGraphicsSnapshot = cocoa_runtime.Snapshot;
pub const CocoaGraphicsOutcome = cocoa_runtime.Outcome;
pub const WindowAdmissionLedger = window_admission.Ledger;
pub const WindowAdmissionRequest = window_admission.Request;
pub const WindowAdmissionOutcome = window_admission.Outcome;
pub const WindowFacility = window_admission.Facility;
pub const WindowOperation = window_admission.Operation;
pub const WindowActor = window_admission.Actor;
pub const WindowCondition = window_admission.Condition;
pub const WindowAdmissionPolicy = window_admission.FaultPolicy;
pub const WindowSwapBoundary = window_admission.SwapBoundary;
pub const WindowSwapEvidence = window_admission.SwapEvidence;
pub const WindowSwapVerdict = window_admission.SwapVerdict;
pub const RegisterApertureObserver = register_aperture.Observer;
pub const RegisterApertureVerdict = register_aperture.Verdict;
pub const RegisterApertureDelivery = register_aperture.Delivery;
pub const RingGeometry = ring_publication.Geometry;
pub const FrameProvenance = provenance.Ledger;
pub const FrameProducer = provenance.Producer;
pub const FrameClassification = provenance.Classification;
pub const NativePresenter = vulkan.Presenter;
pub const NativePresenterStage = vulkan.Stage;
pub const NativeFrameSource = vulkan.Source;
pub const Runtime = runtime.Runtime;
pub const BridgeHealth = runtime.BridgeHealth;
pub const BridgeHealthStage = runtime.BridgeHealthStage;
pub const HandshakeRequest = api.HandshakeRequest;
pub const HandshakeResponse = api.HandshakeResponse;
pub const Capability = api.Capability;
pub const CapabilitySet = api.CapabilitySet;
pub const BackendKind = api.BackendKind;
pub const Handle = handles.Handle;
pub const PacketTimeline = packet_trace.Timeline;
pub const PacketObservation = packet_trace.Observation;
pub const PacketSummary = packet_trace.Summary;
pub const GpuEarlyFrontier = early_frontier.Ledger;
pub const GpuEarlyBoundary = early_frontier.Boundary;
pub const GpuEarlySource = early_frontier.Source;

test {
    _ = bootstrap;
    _ = contract;
    _ = kernel_surface;
    _ = import_binding;
    _ = kernel_variables;
    _ = pm4;
    _ = pm4_executor;
    _ = packet_trace;
    _ = early_frontier;
    _ = preinitialization;
    _ = ring_payload;
    _ = ring_scan;
    _ = ring_view;
    _ = submission_provenance;
    _ = swap_substitution;
    _ = ring_injection;
    _ = xenos_texture;
    _ = xenos_formats;
    _ = xenos_registers;
    _ = xenos_shader;
    _ = edram;
    _ = pipeline_state;
    _ = descriptor_binding;
    _ = interrupt_controller;
    _ = xenos_runtime;
    _ = refresh_liveness;
    _ = forwarding;
    _ = provenance;
    _ = ring_publication;
    _ = vd_swap_contract;
    _ = vd_swap_probe;
    _ = custody;
    _ = register_journal;
    _ = draw_dispatch;
    _ = cocoa_control_plane;
    _ = frame_handoff;
    _ = graphics_intent;
    _ = work_credit;
    _ = cocoa_runtime;
    _ = register_aperture;
    _ = frame_source;
    _ = api;
    _ = backend;
    _ = handles;
    _ = hardware_description;
    _ = runtime;
    _ = vulkan;
}
