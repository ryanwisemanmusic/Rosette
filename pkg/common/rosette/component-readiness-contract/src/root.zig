//! Which components a frame depends on, how each one can be *proven to work*,
//! and whether the proof arrived before the guest first relied on it.
//!
//! ## The gap this closes
//!
//! Every other ledger in this repository answers "did X happen". None of them
//! answers the question that actually decides whether a run can produce a
//! frame: **was X known to work before something depended on it?**
//!
//! Those are not the same question, and the difference is where a translated
//! emulator's failures live. A title calls thirty things during bring-up. Each
//! one either works, or returns something plausible and does not. When the
//! second happens the title carries on with a wrong value and stops somewhere
//! else entirely — and every counter along the way reads healthy, because every
//! call returned.
//!
//! The 2026-08-31 run is the whole argument. Engines initialised, ring
//! initialised, write-back enabled, interrupt callback registered, twenty-four
//! draws issued, completion routes delivering — and the title then waited on a
//! manual-reset event that nothing in the emulator ever signalled, for ten and
//! a half billion steps. Nothing had ever established that guest event
//! signalling worked end to end. It was assumed, thirty components deep, and
//! the assumption was the run.
//!
//! ## Proof, not observation
//!
//! A component is `proven` only when something *exercised* it and observed the
//! result. Three ways that can happen, and the distinction is load-bearing:
//!
//! * `self_exercised` — Rosette performs the operation itself, before the guest
//!   runs. The strongest kind, and the only kind available *ahead* of first use.
//! * `round_trip_observed` — the component was used and its effect was seen at
//!   the other end. A signal that a waiter consumed; a register write that
//!   reached the command processor. Weaker only in that it cannot happen early.
//! * `declared` — a static fact about the build or the platform. Not proof that
//!   anything works, and recorded as such.
//!
//! A call returning success is deliberately none of these. `RtlInitialize
//! CriticalSection` returned successfully every one of the times the title
//! called it in a loop.
//!
//! ## The finding
//!
//! `used_before_proven`: the guest depended on a component while its state was
//! still `unproven`. That is not always a defect — some components genuinely
//! cannot be exercised early — but it is always the list of things the run is
//! trusting blind, and it is the shortest list worth shortening.
//!
//! ## What this package must never become
//!
//! It holds no state, exercises nothing, and never says `proven`. It is the
//! component list, the proof obligations and the sentences. The ledger that
//! records proofs lives in `lib/preflight` and is the only thing allowed to
//! move a component out of `unproven`.

const std = @import("std");

/// How a component can be shown to work.
pub const Proof = enum(u8) {
    /// Rosette performs the operation itself before the guest runs. The only
    /// kind of proof that can exist *ahead* of first use.
    self_exercised,
    /// The component was used and its effect was observed at the far end.
    /// Cannot happen early, and is real proof when it happens.
    round_trip_observed,
    /// A static fact — a linked library, a platform guarantee. Never proof that
    /// anything works.
    declared,

    pub fn label(self: Proof) []const u8 {
        return switch (self) {
            .self_exercised => "self-exercised",
            .round_trip_observed => "round-trip-observed",
            .declared => "declared",
        };
    }

    /// Whether a proof of this kind can be obtained before the guest runs.
    /// A component that cannot be proven early is one the run will always be
    /// trusting blind at first use, and saying so is more useful than pretending
    /// the gap can be closed.
    pub fn availableBeforeFirstUse(self: Proof) bool {
        return self != .round_trip_observed;
    }
};

pub const State = enum(u8) {
    /// Nothing has established that this works.
    unproven,
    /// Something exercised it and it worked.
    proven,
    /// Something exercised it and it did not work.
    failed,
    /// The proof was attempted and could not be carried out here.
    unprovable,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .unproven => "UNPROVEN",
            .proven => "proven",
            .failed => "FAILED",
            .unprovable => "unprovable",
        };
    }

    pub fn dependable(self: State) bool {
        return self == .proven;
    }
};

/// The components between a title's first graphics call and a pixel.
///
/// Deliberately crosses layers. The failures that cost weeks are never inside
/// one component: they are a component that quietly did not work being depended
/// on by one that did, and a per-layer list cannot express that.
pub const Component = enum(u8) {
    // ---- what Rosette provides ---------------------------------------------
    guest_memory_aliasing,
    register_aperture_dispatch,
    host_graphics_device,
    host_surface_presentation,
    guest_code_translation,

    // ---- what the kernel layer provides ------------------------------------
    kernel_export_table,
    guest_thread_scheduling,
    guest_event_signalling,
    guest_critical_sections,
    guest_timer_source,

    // ---- what the graphics stack provides ----------------------------------
    ring_memory_visibility,
    command_processor_drain,
    interrupt_delivery_into_guest,
    shader_translation,
    render_target_binding,
    frame_handoff_to_window,

    pub fn label(self: Component) []const u8 {
        return switch (self) {
            .guest_memory_aliasing => "guest memory aliasing",
            .register_aperture_dispatch => "register aperture dispatch",
            .host_graphics_device => "host graphics device",
            .host_surface_presentation => "host surface presentation",
            .guest_code_translation => "guest code translation",
            .kernel_export_table => "kernel export table",
            .guest_thread_scheduling => "guest thread scheduling",
            .guest_event_signalling => "guest event signalling",
            .guest_critical_sections => "guest critical sections",
            .guest_timer_source => "guest timer source",
            .ring_memory_visibility => "ring memory visibility",
            .command_processor_drain => "command processor drain",
            .interrupt_delivery_into_guest => "interrupt delivery into guest",
            .shader_translation => "shader translation",
            .render_target_binding => "render target binding",
            .frame_handoff_to_window => "frame handoff to window",
        };
    }

    pub fn owner(self: Component) []const u8 {
        return switch (self) {
            .guest_memory_aliasing,
            .register_aperture_dispatch,
            .host_graphics_device,
            .host_surface_presentation,
            .guest_code_translation,
            => "rosette",

            .kernel_export_table,
            .guest_thread_scheduling,
            .guest_event_signalling,
            .guest_critical_sections,
            .guest_timer_source,
            => "emulator:kernel",

            else => "emulator:gpu",
        };
    }

    pub fn proof(self: Component) Proof {
        return switch (self) {
            // Rosette owns these and can exercise every one of them before the
            // guest's first instruction.
            .guest_memory_aliasing,
            .host_graphics_device,
            .host_surface_presentation,
            .guest_timer_source,
            => .self_exercised,

            // These are only real when the guest's own use of them completes.
            // Rosette can watch the far end; it cannot manufacture the near one
            // without becoming the thing it is measuring.
            .register_aperture_dispatch,
            .guest_code_translation,
            .kernel_export_table,
            .guest_thread_scheduling,
            .guest_event_signalling,
            .guest_critical_sections,
            .ring_memory_visibility,
            .command_processor_drain,
            .interrupt_delivery_into_guest,
            .shader_translation,
            .render_target_binding,
            .frame_handoff_to_window,
            => .round_trip_observed,
        };
    }

    /// What has to be seen for this component to count as working. Written as
    /// the observation, not as the intent: "a call was made" is never enough.
    pub fn obligation(self: Component) []const u8 {
        return switch (self) {
            .guest_memory_aliasing => "the same console address read through the virtual and physical views returns the same bytes",
            .register_aperture_dispatch => "a store into the Xenos register window reaches the command processor's register write path",
            .host_graphics_device => "a host device and queue are created and a command buffer is submitted and completes",
            .host_surface_presentation => "a frame is presented to the host surface and the present call completes",
            .guest_code_translation => "a guest function is translated and its translated body executes",
            .kernel_export_table => "an imported export is called and reaches its shim body",
            .guest_thread_scheduling => "a guest thread is created and observed to run guest code",
            .guest_event_signalling => "an event is set and a waiter on that same event is observed to wake because of it",
            .guest_critical_sections => "a critical section is entered and left with the owner field transitioning both ways",
            .guest_timer_source => "the guest clock is read twice and advances",
            .ring_memory_visibility => "the ring's contents are readable through every alias the emulator and the guest use, and they agree",
            .command_processor_drain => "a published write pointer is followed by packets being executed from the ring",
            .interrupt_delivery_into_guest => "a graphics interrupt enters an address the title itself registered",
            .shader_translation => "a guest shader is translated and the translation is accepted by the host pipeline cache",
            .render_target_binding => "a draw reaches the render target cache and a target is bound",
            .frame_handoff_to_window => "a guest-produced image reaches the window",
        };
    }

    /// What depending on this component while it is unproven actually risks.
    /// These sentences are the deliverable: a list of unproven components is a
    /// worry, and a list of consequences is a plan.
    pub fn blindRisk(self: Component) []const u8 {
        return switch (self) {
            .guest_memory_aliasing => "every pointer the title hands the emulator resolves through this. If the views disagree, the emulator and the guest are reading different memory and nothing downstream can be trusted",
            .register_aperture_dispatch => "a register store that does not reach the command processor is silently lost, and every register-derived reading afterwards is zero for a reason unrelated to the title",
            .host_graphics_device => "no host device means no frame can exist, however far the guest gets",
            .host_surface_presentation => "frames can be produced and never shown, which is indistinguishable from frames never being produced",
            .guest_code_translation => "a function that fails to translate falls back or faults somewhere unrelated to the call site",
            .kernel_export_table => "an export bound to the wrong address jumps into unrelated code and the symptom appears wherever that code goes wrong",
            .guest_thread_scheduling => "a thread that never runs produces its absence wherever its work was needed, never at its creation",
            .guest_event_signalling => "a title that waits on an event nothing signals waits forever, and the log shows a healthy producer and a healthy consumer that never meet. This is the single most expensive unproven component in this project's history",
            .guest_critical_sections => "a lock that cannot be acquired turns into a retry loop, which reads as a livelock in title code rather than as a kernel defect",
            .guest_timer_source => "a clock that does not advance freezes every deadline built on it, and every wait becomes indistinguishable from a stall",
            .ring_memory_visibility => "the emulator and the guest disagree about what is in the ring, so packets are read that were never written or writes are missed",
            .command_processor_drain => "the title publishes work nothing consumes, and its own progress counters stop for a reason it cannot see",
            .interrupt_delivery_into_guest => "the title's frame loop has no clock, so it waits forever no matter what the GPU does",
            .shader_translation => "a draw with an untranslatable shader is dropped before it reaches a render target, and the draw counter still climbs",
            .render_target_binding => "draws are issued with nowhere to land and render nothing, which looks exactly like rendering that produced a black frame",
            .frame_handoff_to_window => "the guest renders and the window shows the host's own drawing",
        };
    }

    /// Whether a frame is impossible while this is not working, as opposed to
    /// degraded. Used to rank, never to excuse.
    pub fn essential(self: Component) bool {
        return switch (self) {
            .guest_timer_source, .shader_translation => false,
            else => true,
        };
    }
};

pub const component_count: usize = @typeInfo(Component).@"enum".fields.len;

pub fn allComponents() [component_count]Component {
    var out: [component_count]Component = undefined;
    for (&out, 0..) |*slot, index| slot.* = @enumFromInt(index);
    return out;
}

/// How a component's proof stands relative to the guest's first use of it.
pub const Standing = enum(u8) {
    /// Neither proven nor used. Nothing to say yet.
    idle,
    /// Proven, and the guest has not needed it yet. The state every component
    /// should be in when the title starts.
    ready,
    /// Proven before the guest first used it. The ordering held.
    proven_before_use,
    /// The guest used it while it was unproven, and it was proven afterwards.
    /// The run worked and it worked on trust.
    proven_after_use,
    /// The guest is depending on it and nothing has ever established that it
    /// works. Every symptom downstream of this is unattributable.
    used_unproven,
    /// It was exercised and it does not work.
    broken,

    pub fn label(self: Standing) []const u8 {
        return switch (self) {
            .idle => "idle",
            .ready => "ready",
            .proven_before_use => "proven-before-use",
            .proven_after_use => "proven-after-use",
            .used_unproven => "USED-UNPROVEN",
            .broken => "BROKEN",
        };
    }

    pub fn actionable(self: Standing) bool {
        return self == .used_unproven or self == .broken;
    }

    pub fn describe(self: Standing) []const u8 {
        return switch (self) {
            .idle => "neither proven nor depended on yet",
            .ready => "proven, and nothing has needed it yet — which is the state every component should be in when the title starts",
            .proven_before_use => "proven before the guest first depended on it, which is the ordering the whole gate exists to produce",
            .proven_after_use => "the guest depended on it before anything had established that it works, and the proof arrived later. The run happened to be fine; nothing made it fine",
            .used_unproven => "the guest is depending on this and nothing has ever shown that it works. A symptom downstream of it cannot be attributed to anything, because the thing it rests on was never checked",
            .broken => "it was exercised and it does not work. Everything that depends on it is a consequence and none of it is worth investigating first",
        };
    }
};

pub fn standingOf(
    proven: bool,
    failed: bool,
    proven_step: u64,
    used: bool,
    first_use_step: u64,
) Standing {
    if (failed) return .broken;
    if (!used) return if (proven) .ready else .idle;
    if (!proven) return .used_unproven;
    return if (proven_step <= first_use_step) .proven_before_use else .proven_after_use;
}

test "every component names an owner, an obligation and a risk" {
    for (allComponents()) |component| {
        try std.testing.expect(component.label().len != 0);
        try std.testing.expect(component.owner().len != 0);
        try std.testing.expect(component.obligation().len != 0);
        try std.testing.expect(component.blindRisk().len != 0);
    }
}

// The distinction the package is built on: a component the guest is depending
// on with nothing having shown that it works.
test "using an unproven component is the finding" {
    try std.testing.expectEqual(
        Standing.used_unproven,
        standingOf(false, false, 0, true, 100),
    );
    try std.testing.expect(Standing.used_unproven.actionable());
}

test "a proof that arrives after first use is not the same as one before it" {
    try std.testing.expectEqual(
        Standing.proven_before_use,
        standingOf(true, false, 50, true, 100),
    );
    try std.testing.expectEqual(
        Standing.proven_after_use,
        standingOf(true, false, 150, true, 100),
    );
    // Neither is a finding on its own; only one of them is an ordering anybody
    // arranged.
    try std.testing.expect(!Standing.proven_after_use.actionable());
}

test "a failed proof outranks everything" {
    try std.testing.expectEqual(Standing.broken, standingOf(true, true, 10, true, 100));
    try std.testing.expectEqual(Standing.broken, standingOf(false, true, 0, false, 0));
}

test "a proven component nothing has used yet is ready" {
    try std.testing.expectEqual(Standing.ready, standingOf(true, false, 10, false, 0));
    try std.testing.expectEqual(Standing.idle, standingOf(false, false, 0, false, 0));
}

// Only some components can be proven ahead of the guest. Saying which is more
// useful than pretending every gap can be closed early.
test "round-trip proofs cannot exist before first use" {
    try std.testing.expect(Proof.self_exercised.availableBeforeFirstUse());
    try std.testing.expect(!Proof.round_trip_observed.availableBeforeFirstUse());
    try std.testing.expectEqual(
        Proof.round_trip_observed,
        Component.guest_event_signalling.proof(),
    );
    try std.testing.expectEqual(
        Proof.self_exercised,
        Component.host_graphics_device.proof(),
    );
}

// The component that cost this project the most is named in the risk text, so a
// reader meeting it for the first time is told what it costs.
test "guest event signalling states what depending on it blind costs" {
    const risk = Component.guest_event_signalling.blindRisk();
    try std.testing.expect(std.mem.indexOf(u8, risk, "waits forever") != null);
    try std.testing.expect(Component.guest_event_signalling.essential());
}

test "a returning call is not one of the proof kinds" {
    // There is deliberately no `call_returned` proof: `RtlInitializeCriticalSection`
    // returned successfully every time the title called it in a loop.
    inline for (@typeInfo(Proof).@"enum".fields) |field| {
        try std.testing.expect(!std.mem.eql(u8, field.name, "call_returned"));
    }
}
