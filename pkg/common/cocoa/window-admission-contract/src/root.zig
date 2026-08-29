//! What may be forwarded into Rosette's window, by whom, and what has to hold
//! first.
//!
//! Rosette constructs the native window before the guest runs: application,
//! window, view, layer, device, event pump and presenter are all standing by
//! with the geometry and the pixel formats the emulator is going to ask for.
//! Xenia then arrives incrementally. The question this contract answers is not
//! "can the window do it" — the window can, that is the point of the
//! pre-initialization — but "is this particular forwarding one Rosette knows
//! the meaning of, from an actor allowed to make it, with its preconditions
//! actually observed".
//!
//! Three refusals are separated because they lead a reader to three different
//! places:
//!
//!   * `refused_unknown_facility` / `refused_unsupported_operation` — the
//!     forwarding names something Rosette has no semantics for. Silently
//!     returning a plausible value here is how a window ends up displaying
//!     something nobody can account for, so the policy may make it fatal.
//!   * `refused_actor_not_permitted` — the operation exists but this domain
//!     does not get to perform it. A guest title does not resize Rosette's
//!     window and Xenia does not take the presenter out from under it.
//!   * `refused_not_preinitialized` / `refused_conditions_unmet` — the request
//!     is legitimate and early. Nothing is wrong; it is refused and retried.
//!
//! Only the first class is a defect in the *forwarding*. The other two are
//! ordering, and a policy that faulted on them would abort every healthy run
//! during bring-up.
//!
//! The vocabulary is deliberately route-independent: no Vulkan handle, no
//! Objective-C selector string and no x86 register appears here. Callers map
//! their own boundary onto a `Facility`/`Operation` pair before asking.

const std = @import("std");

pub const schema_version: u16 = 1;

/// Who is forwarding.
///
/// Ordinals mirror the Cocoa graphics-control contract's `Domain` so the two
/// can be converted by numeric value rather than by a mapping table that can
/// drift. `domainOrdinalsAgree` is the standing check on that claim.
pub const Actor = enum(u8) {
    unknown,
    guest_title,
    xenia_powerpc,
    xenia_host,
    xenia_vulkan,
    sdl,
    rosette_runtime,
    cocoa_appkit,
    moltenvk,
    vulkan_driver,
    metal_driver,

    pub fn label(self: Actor) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .guest_title => "guest:title",
            .xenia_powerpc => "xenia:powerpc",
            .xenia_host => "xenia:host",
            .xenia_vulkan => "xenia:vulkan",
            .sdl => "sdl",
            .rosette_runtime => "rosette:runtime",
            .cocoa_appkit => "cocoa:appkit",
            .moltenvk => "moltenvk",
            .vulkan_driver => "vulkan:driver",
            .metal_driver => "metal:driver",
        };
    }

    /// True for the domains that speak for the emulator rather than for the
    /// host stack. These are the ones whose forwardings arrive through
    /// translation and therefore carry no compile-time guarantee at all.
    pub fn isEmulatorSide(self: Actor) bool {
        return switch (self) {
            .guest_title, .xenia_powerpc, .xenia_host, .xenia_vulkan => true,
            else => false,
        };
    }
};

pub const actor_count: usize = @typeInfo(Actor).@"enum".fields.len;

/// A capability of the window Rosette stands up before the guest runs.
pub const Facility = enum(u8) {
    /// The forwarding was addressed at something Rosette owns and named no
    /// capability this contract knows. It exists so that case is decided by the
    /// same function as every other one instead of falling out of a chain of
    /// `if`s into whatever the generic model happened to answer.
    unrecognized,
    /// NSApplication identity and activation state.
    application,
    /// NSWindow identity and lifetime.
    window,
    /// The content NSView.
    content_view,
    /// CAMetalLayer backing the view.
    layer,
    /// MTLDevice the layer draws on.
    device,
    /// retain/release/autorelease on a Rosette-owned identity.
    identity_lifetime,
    /// respondsToSelector:/isKindOfClass:/isEqual: on a Rosette-owned identity.
    identity_query,
    title,
    geometry,
    visibility,
    fullscreen,
    /// Draining the AppKit event queue.
    event_pump,
    /// A VkSurfaceKHR bound to the layer.
    surface_binding,
    /// The presenter's swapchain.
    swapchain,
    /// A single drawable acquired from the layer.
    drawable,
    /// A host clear proving the window and the presentation path are alive.
    diagnostic_present,
    /// Verified guest pixels shown on host cadence.
    verified_present,
    /// Pixels shown because the title asked for them via VdSwap.
    guest_swap_present,
    /// Pixels shown because an authentic PM4 XE_SWAP named a front buffer.
    pm4_swap_present,

    pub fn label(self: Facility) []const u8 {
        return switch (self) {
            .unrecognized => "unrecognized",
            .application => "application",
            .window => "window",
            .content_view => "content-view",
            .layer => "layer",
            .device => "device",
            .identity_lifetime => "identity-lifetime",
            .identity_query => "identity-query",
            .title => "title",
            .geometry => "geometry",
            .visibility => "visibility",
            .fullscreen => "fullscreen",
            .event_pump => "event-pump",
            .surface_binding => "surface-binding",
            .swapchain => "swapchain",
            .drawable => "drawable",
            .diagnostic_present => "diagnostic-present",
            .verified_present => "verified-present",
            .guest_swap_present => "guest-swap-present",
            .pm4_swap_present => "pm4-swap-present",
        };
    }

    /// True when Rosette brings this up before the first guest instruction, so
    /// a forwarding that finds it missing is a Rosette defect rather than an
    /// early arrival.
    pub fn preinitialized(self: Facility) bool {
        return switch (self) {
            .application,
            .window,
            .content_view,
            .layer,
            .device,
            .identity_lifetime,
            .identity_query,
            .title,
            .geometry,
            .visibility,
            .fullscreen,
            .event_pump,
            .diagnostic_present,
            => true,
            // These exist only once a producer has negotiated them; their
            // absence early in a run is ordering, not a defect.
            .unrecognized, .surface_binding, .swapchain, .drawable, .verified_present, .guest_swap_present, .pm4_swap_present => false,
        };
    }

    /// The domain that owns the facility. Every one of them is Rosette's or
    /// AppKit's: that is what "Rosette owns the window" means as a rule rather
    /// than as an intention.
    pub fn owner(self: Facility) Actor {
        return switch (self) {
            .application, .window, .content_view, .layer, .identity_lifetime, .identity_query => .cocoa_appkit,
            // Rosette still owns the identity the message was addressed to;
            // that is precisely why nobody else gets to answer for it.
            .unrecognized => .rosette_runtime,
            .device => .metal_driver,
            else => .rosette_runtime,
        };
    }

    /// Whether the facility is an object the emulator can hold a handle to,
    /// as opposed to a property of the window or an action performed on it.
    ///
    /// Only these can be *acquired*. `title`, `geometry`, `visibility`,
    /// `fullscreen` and `event_pump` are things you do to the window you
    /// already hold, not things you obtain.
    pub fn hasHandle(self: Facility) bool {
        return switch (self) {
            .application, .window, .content_view, .layer, .device => true,
            else => false,
        };
    }

    /// Whether pixels reaching the window through this facility are the
    /// guest's. A diagnostic clear is never guest output no matter how many
    /// times it succeeds.
    pub fn carriesGuestPixels(self: Facility) bool {
        return switch (self) {
            .verified_present, .guest_swap_present, .pm4_swap_present => true,
            else => false,
        };
    }
};

pub const facility_count: usize = @typeInfo(Facility).@"enum".fields.len;

pub const Operation = enum(u8) {
    /// Bring a genuinely new resource into existence — a swapchain, a surface
    /// binding. Never an AppKit singleton: Rosette's pre-initialization made
    /// those, and a forwarding that means to make a second one is a defect.
    create,
    /// Obtain the handle to a singleton Rosette already owns.
    ///
    /// This is the mechanism by which Rosette hands its window to the emulator,
    /// so it is the one operation that must never be refused for ownership.
    /// `[NSApplication sharedApplication]`, `[CAMetalLayer layer]` and
    /// `[NSWindow contentView]` all read as creation in Objective-C and are
    /// nothing of the kind here — they return fixed tokens whose backing
    /// objects the harness stood up before the guest ran.
    acquire,
    query,
    mutate,
    bind,
    present,
    pump,
    release,

    pub fn label(self: Operation) []const u8 {
        return switch (self) {
            .create => "create",
            .acquire => "acquire",
            .query => "query",
            .mutate => "mutate",
            .bind => "bind",
            .present => "present",
            .pump => "pump",
            .release => "release",
        };
    }

    /// Operations that change what the user sees or what the window owns.
    /// Queries and acquisitions never do — an acquisition hands back an
    /// identity that already exists — which is why both are admitted from every
    /// actor.
    pub fn isMutating(self: Operation) bool {
        return switch (self) {
            .query, .acquire => false,
            else => true,
        };
    }
};

pub const operation_count: usize = @typeInfo(Operation).@"enum".fields.len;

/// A precondition that must be *observed*, not assumed.
pub const Condition = enum(u5) {
    application_ready,
    window_ready,
    view_ready,
    layer_attached,
    device_ready,
    main_thread,
    surface_bound,
    presenter_ready,
    frame_verified,
    frontbuffer_named,
    swap_boundary_observed,
    custody_available,

    pub fn label(self: Condition) []const u8 {
        return switch (self) {
            .application_ready => "application-ready",
            .window_ready => "window-ready",
            .view_ready => "view-ready",
            .layer_attached => "layer-attached",
            .device_ready => "device-ready",
            .main_thread => "main-thread",
            .surface_bound => "surface-bound",
            .presenter_ready => "presenter-ready",
            .frame_verified => "frame-verified",
            .frontbuffer_named => "frontbuffer-named",
            .swap_boundary_observed => "swap-boundary-observed",
            .custody_available => "custody-available",
        };
    }
};

pub const condition_count: usize = @typeInfo(Condition).@"enum".fields.len;

pub const ConditionMask = u16;

pub fn conditionBit(condition: Condition) ConditionMask {
    return @as(ConditionMask, 1) << @as(u4, @intCast(@intFromEnum(condition)));
}

pub fn conditionsOf(list: []const Condition) ConditionMask {
    var mask: ConditionMask = 0;
    for (list) |condition| mask |= conditionBit(condition);
    return mask;
}

/// Conditions common to anything that puts pixels on the window.
const present_base = conditionsOf(&.{
    .application_ready,
    .window_ready,
    .view_ready,
    .layer_attached,
    .device_ready,
    .custody_available,
});

/// Whether Rosette has semantics for this pair at all. A `false` here is the
/// case the policy may treat as fatal: the forwarding named something the
/// window has no meaning for.
pub fn supports(facility: Facility, operation: Operation) bool {
    return switch (facility) {
        .unrecognized => false,
        // `create` is deliberately absent from every AppKit singleton. Rosette
        // stood them up before the guest ran, so nothing forwards in to make
        // one — and a forwarding that did would leave the process holding two
        // of something there can only be one of, which is exactly the class of
        // defect the fault policy exists to stop at.
        .application => switch (operation) {
            .acquire, .query, .mutate => true,
            else => false,
        },
        .window, .content_view => switch (operation) {
            .acquire, .query, .mutate, .bind => true,
            else => false,
        },
        .layer => switch (operation) {
            .acquire, .query, .bind => true,
            else => false,
        },
        .device => operation == .acquire or operation == .query,
        .identity_lifetime => operation == .query or operation == .release,
        .identity_query => operation == .query,
        .title, .geometry, .visibility, .fullscreen => operation == .query or operation == .mutate,
        .event_pump => operation == .pump,
        .surface_binding => operation == .bind or operation == .query,
        .swapchain => switch (operation) {
            .create, .query, .bind, .release => true,
            else => false,
        },
        .drawable => operation == .query or operation == .release,
        .diagnostic_present, .verified_present, .guest_swap_present, .pm4_swap_present => operation == .present,
    };
}

/// What must hold before the pair may be admitted.
///
/// The rule that is easy to get backwards: for `create` and `bind`, the
/// facility's own readiness is the *outcome*, not the precondition. Requiring
/// `application_ready` before `sharedApplication` would refuse the call that
/// makes the application ready, and every such refusal would read as a defect
/// in the forwarding rather than in this table. Only what must already exist
/// *beneath* the facility is required.
pub fn requirements(facility: Facility, operation: Operation) ConditionMask {
    if (operation == .query and !facility.carriesGuestPixels()) {
        // A query answers with an identity Rosette already owns. Gating it on
        // readiness would make the emulator unable to discover the window it is
        // being handed.
        return switch (facility) {
            .application => conditionBit(.application_ready),
            .window, .content_view => conditionBit(.window_ready),
            .layer => conditionsOf(&.{ .window_ready, .view_ready }),
            .device => conditionBit(.device_ready),
            else => 0,
        };
    }
    if (operation == .acquire) {
        // Acquiring a singleton Rosette owns requires nothing. The handler that
        // answers the acquisition is what stands the facility up — `layerToken`
        // and `viewToken` both run `ensureWindow` on the way through — so a
        // precondition here would refuse the call that satisfies it. What is
        // still checked is `facility_present`: if the facility is *absent after*
        // the handler ran, Rosette failed to keep its own promise, and that is
        // worth stopping at.
        return 0;
    }
    if (operation == .create or operation == .bind) {
        return switch (facility) {
            .application => 0,
            .window => conditionBit(.application_ready),
            .content_view => conditionBit(.window_ready),
            .layer => conditionsOf(&.{ .window_ready, .view_ready }),
            .surface_binding => conditionsOf(&.{ .window_ready, .view_ready, .layer_attached }),
            .swapchain => conditionsOf(&.{ .layer_attached, .device_ready, .surface_bound }),
            else => 0,
        };
    }
    return switch (facility) {
        .unrecognized => 0,
        .application => conditionBit(.application_ready),
        .window => conditionsOf(&.{ .application_ready, .window_ready }),
        .content_view => conditionsOf(&.{ .window_ready, .view_ready }),
        .layer => conditionsOf(&.{ .window_ready, .view_ready }),
        .device => conditionBit(.device_ready),
        .identity_lifetime, .identity_query => 0,
        .title, .geometry, .visibility, .fullscreen => conditionsOf(&.{ .application_ready, .window_ready }),
        .event_pump => conditionsOf(&.{ .application_ready, .main_thread }),
        .surface_binding => conditionsOf(&.{ .window_ready, .view_ready, .layer_attached }),
        .swapchain => conditionsOf(&.{ .layer_attached, .device_ready, .surface_bound }),
        .drawable => conditionsOf(&.{ .layer_attached, .device_ready }),
        .diagnostic_present => present_base,
        .verified_present => present_base | conditionsOf(&.{ .presenter_ready, .frame_verified }),
        .guest_swap_present => present_base | conditionsOf(&.{
            .presenter_ready,
            .frame_verified,
            .frontbuffer_named,
            .swap_boundary_observed,
        }),
        .pm4_swap_present => present_base | conditionsOf(&.{
            .presenter_ready,
            .frame_verified,
            .frontbuffer_named,
            .swap_boundary_observed,
        }),
    };
}

/// Whether this domain gets to make this request at all.
///
/// Reads and identity traffic are open: an emulator has to be able to look at
/// the window it is being given. Everything that changes state is restricted to
/// the domains that can legitimately own that change, which is what keeps a
/// translated guest instruction from resizing, hiding or repainting a window
/// Rosette is responsible for.
pub fn mayForward(actor: Actor, facility: Facility, operation: Operation) bool {
    if (actor == .unknown) return false;
    if (!operation.isMutating()) return true;
    return switch (facility) {
        .unrecognized => false,
        // Lifetime traffic on a Rosette identity is answered for anyone; the
        // identities are tokens, not refcounted objects, so a release cannot
        // destroy anything.
        .identity_lifetime, .identity_query => true,
        // AppKit surface state. `supports` already refuses creation on these,
        // so what reaches here is `mutate` or `bind` on a singleton the
        // emulator was handed — activating the application, showing the window,
        // attaching the layer. Every one of those is behaviour Rosette
        // pre-initialized the window in order to support, and refusing them
        // would be refusing the design rather than enforcing it.
        .application, .window, .content_view, .layer => true,
        .title, .geometry, .visibility, .fullscreen => actor != .guest_title,
        .event_pump => true,
        .device => false,
        // Presentation plumbing belongs to whoever brought it up.
        .surface_binding, .swapchain, .drawable => switch (actor) {
            .rosette_runtime, .xenia_vulkan, .moltenvk, .vulkan_driver, .metal_driver, .sdl => true,
            else => false,
        },
        .diagnostic_present => actor == .rosette_runtime,
        .verified_present => actor == .rosette_runtime or actor == .xenia_host or actor == .xenia_vulkan,
        // Every domain that owns a swap boundary presenting on this facility
        // has to be permitted on it, or the gate would refuse the authentic
        // path as an ownership violation — the one refusal class the policy is
        // allowed to make fatal. `everySwapOwnerMayPresent` is the standing
        // check that this list and `SwapBoundary.owner` cannot drift apart.
        .guest_swap_present => actor == .guest_title or actor == .xenia_host or
            actor == .xenia_vulkan or actor == .rosette_runtime,
        .pm4_swap_present => actor == .guest_title or actor == .xenia_host or actor == .rosette_runtime,
    };
}

pub const Verdict = enum(u8) {
    admitted,
    /// Rosette has no semantics for this facility/operation pair.
    refused_unsupported_operation,
    /// The domain is not permitted to perform this operation.
    refused_actor_not_permitted,
    /// A facility Rosette promises to pre-initialize was not standing.
    refused_not_preinitialized,
    /// A legitimate request that arrived before its preconditions held.
    refused_conditions_unmet,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .admitted => "admitted",
            .refused_unsupported_operation => "refused-unsupported-operation",
            .refused_actor_not_permitted => "refused-actor-not-permitted",
            .refused_not_preinitialized => "refused-not-preinitialized",
            .refused_conditions_unmet => "refused-conditions-unmet",
        };
    }

    pub fn admittedOk(self: Verdict) bool {
        return self == .admitted;
    }

    /// True when the refusal says the forwarding itself is unaccountable
    /// rather than early. Only this class is eligible to be fatal.
    pub fn isUnaccountable(self: Verdict) bool {
        return switch (self) {
            .refused_unsupported_operation, .refused_actor_not_permitted, .refused_not_preinitialized => true,
            .admitted, .refused_conditions_unmet => false,
        };
    }

    pub fn explanation(self: Verdict) []const u8 {
        return switch (self) {
            .admitted => "the window has semantics for this forwarding, the actor may make it, and every precondition was observed",
            .refused_unsupported_operation => "the forwarding names a window operation Rosette has no meaning for; answering it would put something on screen nobody can account for",
            .refused_actor_not_permitted => "the operation exists but this domain does not own it; admitting it would let a translated guest instruction change a window Rosette is responsible for",
            .refused_not_preinitialized => "Rosette promises this facility before the first guest instruction and it was not standing; this is a Rosette defect, not an early arrival",
            .refused_conditions_unmet => "a legitimate request whose preconditions have not been observed yet; refused and retried, nothing is wrong",
        };
    }
};

pub const Request = struct {
    actor: Actor = .unknown,
    facility: Facility = .window,
    operation: Operation = .query,
    /// Conditions the caller has actually observed. Never inferred here.
    observed: ConditionMask = 0,
    /// Whether the facility Rosette pre-initializes was found standing.
    facility_present: bool = true,
};

pub const Decision = struct {
    verdict: Verdict = .admitted,
    /// Conditions required but not observed. Zero unless the verdict is
    /// `refused_conditions_unmet`.
    missing: ConditionMask = 0,

    pub fn firstMissing(self: Decision) ?Condition {
        if (self.missing == 0) return null;
        var index: u8 = 0;
        while (index < condition_count) : (index += 1) {
            const condition: Condition = @enumFromInt(index);
            if (self.missing & conditionBit(condition) != 0) return condition;
        }
        return null;
    }
};

pub fn decide(request: Request) Decision {
    if (!supports(request.facility, request.operation))
        return .{ .verdict = .refused_unsupported_operation };
    if (!mayForward(request.actor, request.facility, request.operation))
        return .{ .verdict = .refused_actor_not_permitted };
    if (request.facility.preinitialized() and !request.facility_present)
        return .{ .verdict = .refused_not_preinitialized };
    const required = requirements(request.facility, request.operation);
    const missing = required & ~request.observed;
    if (missing != 0) return .{ .verdict = .refused_conditions_unmet, .missing = missing };
    return .{ .verdict = .admitted };
}

/// What the runtime does about a decision.
pub const FaultPolicy = enum(u8) {
    /// Record and answer as before. Used to establish a baseline without
    /// changing behaviour.
    observe,
    /// Record and refuse. The forwarding gets a refusal, the run continues.
    refuse,
    /// Record, refuse, and terminate on an unaccountable forwarding.
    fault,

    pub fn label(self: FaultPolicy) []const u8 {
        return switch (self) {
            .observe => "observe",
            .refuse => "refuse",
            .fault => "fault",
        };
    }
};

pub const Disposition = enum(u8) {
    admit,
    refuse,
    fault,

    pub fn label(self: Disposition) []const u8 {
        return switch (self) {
            .admit => "admit",
            .refuse => "refuse",
            .fault => "fault",
        };
    }
};

pub fn disposition(verdict: Verdict, policy: FaultPolicy) Disposition {
    if (verdict.admittedOk()) return .admit;
    return switch (policy) {
        .observe => .admit,
        .refuse => .refuse,
        .fault => if (verdict.isUnaccountable()) .fault else .refuse,
    };
}

// ---------------------------------------------------------------------------
// Swap handoff
// ---------------------------------------------------------------------------

/// The guest-owned boundaries at which Xenia hands presentation to Rosette.
///
/// These are separated from `Facility` because the question is different: a
/// facility asks whether the window can do something, a boundary asks whether
/// what arrived is really the guest's swap or a claim about one.
pub const SwapBoundary = enum(u8) {
    /// The title entered the VdSwap export.
    vd_swap_entry,
    /// VdSwap's arguments were captured, so the frame it names is knowable.
    vd_swap_arguments,
    /// The title encoded an XE_SWAP packet into the ring.
    xe_swap_encoded,
    /// The command processor consumed an authentic XE_SWAP.
    xe_swap_consumed,
    /// The emulator's presenter entered IssueSwap.
    issue_swap,

    pub fn label(self: SwapBoundary) []const u8 {
        return switch (self) {
            .vd_swap_entry => "VdSwap entry",
            .vd_swap_arguments => "VdSwap arguments",
            .xe_swap_encoded => "XE_SWAP encoded",
            .xe_swap_consumed => "XE_SWAP consumed",
            .issue_swap => "IssueSwap",
        };
    }

    pub fn owner(self: SwapBoundary) Actor {
        return switch (self) {
            .vd_swap_entry, .vd_swap_arguments, .xe_swap_encoded => .guest_title,
            .xe_swap_consumed => .xenia_host,
            .issue_swap => .xenia_vulkan,
        };
    }

    /// The facility a frame admitted through this boundary would present on.
    pub fn facility(self: SwapBoundary) Facility {
        return switch (self) {
            .vd_swap_entry, .vd_swap_arguments, .issue_swap => .guest_swap_present,
            .xe_swap_encoded, .xe_swap_consumed => .pm4_swap_present,
        };
    }
};

pub const swap_boundary_count: usize = @typeInfo(SwapBoundary).@"enum".fields.len;

/// How Rosette came to believe the boundary occurred.
///
/// Ranked, because two of these have already been wrong in this codebase: a
/// log line is a claim by a subsystem that may have stopped refreshing it, and
/// a heartbeat reading is a snapshot that may predate the state it describes.
pub const SwapProvenance = enum(u8) {
    none,
    /// Parsed out of the emulator's own diagnostic text.
    emulator_log_claim,
    /// Read out of guest memory during a scan.
    guest_memory_read,
    /// The instruction pointer reached an armed address.
    intercepted_execution,

    pub fn label(self: SwapProvenance) []const u8 {
        return switch (self) {
            .none => "none",
            .emulator_log_claim => "emulator-log-claim",
            .guest_memory_read => "guest-memory-read",
            .intercepted_execution => "intercepted-execution",
        };
    }

    pub fn rank(self: SwapProvenance) u8 {
        return @intFromEnum(self);
    }

    /// A boundary Rosette will act on rather than only record. A log claim
    /// never qualifies: twice in this codebase a parsed claim was a stale
    /// snapshot of a state that had already moved.
    pub fn actionable(self: SwapProvenance) bool {
        return self.rank() >= SwapProvenance.guest_memory_read.rank();
    }
};

/// Everything Rosette must have observed before it takes custody of a swap.
///
/// Every field is a fact somebody looked at. There is no field for "the log
/// said so" other than `provenance`, which records exactly that and is ranked
/// below anything Rosette saw itself.
pub const SwapEvidence = struct {
    provenance: SwapProvenance = .none,
    /// The window facility this boundary presents on is admitted.
    facility_admitted: bool = false,
    /// A front buffer address is named by the boundary rather than supplied by
    /// Rosette to keep the ladder moving.
    frontbuffer_named: bool = false,
    /// Rosette supplied the surface itself. Admissible, but the frame it
    /// yields is never guest output.
    frontbuffer_harness_supplied: bool = false,
    /// The named range is mapped and readable for its full extent.
    frontbuffer_readable: bool = false,
    /// Width/height are non-zero and within what the window can show.
    extent_valid: bool = false,
    /// The pixel format is one Rosette can convert.
    format_supported: bool = false,
    /// The ring publication epoch that produced this boundary is the one
    /// Rosette consumed, so the packet is not being read out of a drained ring
    /// whose contents have since been overwritten.
    epoch_matched: bool = false,
    /// A custody slot is free and no other frame holds this identity.
    custody_available: bool = false,
    /// The presenter lease is held by a domain compatible with this handoff.
    lease_compatible: bool = false,

    pub fn frontbufferKnown(self: SwapEvidence) bool {
        return self.frontbuffer_named or self.frontbuffer_harness_supplied;
    }
};

pub const SwapVerdict = enum(u8) {
    admitted,
    /// Admitted, but from a surface Rosette supplied. The frame is Rosette's.
    admitted_harness_surface,
    refused_provenance_insufficient,
    refused_facility_not_admitted,
    refused_frontbuffer_unknown,
    refused_frontbuffer_unreadable,
    refused_geometry_unusable,
    refused_epoch_stale,
    refused_custody_unavailable,
    refused_lease_conflict,

    pub fn label(self: SwapVerdict) []const u8 {
        return switch (self) {
            .admitted => "admitted",
            .admitted_harness_surface => "admitted-harness-surface",
            .refused_provenance_insufficient => "refused-provenance-insufficient",
            .refused_facility_not_admitted => "refused-facility-not-admitted",
            .refused_frontbuffer_unknown => "refused-frontbuffer-unknown",
            .refused_frontbuffer_unreadable => "refused-frontbuffer-unreadable",
            .refused_geometry_unusable => "refused-geometry-unusable",
            .refused_epoch_stale => "refused-epoch-stale",
            .refused_custody_unavailable => "refused-custody-unavailable",
            .refused_lease_conflict => "refused-lease-conflict",
        };
    }

    pub fn admittedOk(self: SwapVerdict) bool {
        return self == .admitted or self == .admitted_harness_surface;
    }

    /// Whether a frame admitted under this verdict may close the authentic
    /// guest-swap stage. A harness surface never can, however well founded the
    /// boundary that named it was.
    pub fn closesAuthenticStage(self: SwapVerdict) bool {
        return self == .admitted;
    }
};

/// Decide whether a swap boundary may hand presentation to Rosette's window.
///
/// The order is the order a reader needs: provenance first, because a boundary
/// Rosette only read about in a log is not a boundary; then the window's own
/// admission; then the surface; then geometry; then the epoch that proves the
/// packet is current; then custody and the lease.
pub fn admitSwap(boundary: SwapBoundary, evidence: SwapEvidence) SwapVerdict {
    if (!evidence.provenance.actionable()) return .refused_provenance_insufficient;
    if (!evidence.facility_admitted) return .refused_facility_not_admitted;
    if (!evidence.frontbufferKnown()) return .refused_frontbuffer_unknown;
    if (!evidence.frontbuffer_readable) return .refused_frontbuffer_unreadable;
    if (!evidence.extent_valid or !evidence.format_supported) return .refused_geometry_unusable;
    // Only the packet boundaries are read out of the ring, so only they can be
    // read out of a stale epoch. An export entry is an execution fact.
    if (boundary.facility() == .pm4_swap_present and !evidence.epoch_matched) return .refused_epoch_stale;
    if (!evidence.custody_available) return .refused_custody_unavailable;
    if (!evidence.lease_compatible) return .refused_lease_conflict;
    if (evidence.frontbuffer_harness_supplied) return .admitted_harness_surface;
    return .admitted;
}

/// Every facility Rosette pre-initializes can be acquired, by anyone, with no
/// preconditions.
///
/// This is the invariant the first real run broke. `[NSApplication
/// sharedApplication]` was classified as `create`, `create` on an AppKit
/// singleton was an ownership violation, and an ownership violation is fatal —
/// so the gate terminated the run on the very call by which Rosette hands its
/// window to the emulator. Handing the window over is the entire point of
/// pre-initializing it; if a pre-initialized facility cannot be acquired, the
/// contract is refusing its own design.
pub fn everyPreinitializedFacilityIsAcquirable() bool {
    var index: u8 = 0;
    while (index < facility_count) : (index += 1) {
        const facility: Facility = @enumFromInt(index);
        if (!facility.preinitialized() or !facility.hasHandle()) continue;
        if (!supports(facility, .acquire)) return false;
        if (requirements(facility, .acquire) != 0) return false;
        var actor_index: u8 = 0;
        while (actor_index < actor_count) : (actor_index += 1) {
            const actor: Actor = @enumFromInt(actor_index);
            if (actor == .unknown) continue;
            if (!mayForward(actor, facility, .acquire)) return false;
        }
    }
    return true;
}

/// Every domain that owns a swap boundary is permitted to present on the
/// facility that boundary uses.
///
/// Without this the gate refuses the authentic path as `actor_not_permitted`,
/// which is the class the fault policy is allowed to terminate on — so a title
/// finally reaching `VdSwap` would crash the run at the exact moment it started
/// working.
pub fn everySwapOwnerMayPresent() bool {
    var index: u8 = 0;
    while (index < swap_boundary_count) : (index += 1) {
        const boundary: SwapBoundary = @enumFromInt(index);
        if (!mayForward(boundary.owner(), boundary.facility(), .present)) return false;
    }
    return true;
}

/// The contract is self-consistent: every supported pair has a requirement set
/// drawn from the declared conditions, every facility has an owner, and no
/// facility that carries guest pixels is answerable from a query.
pub fn contractIsWellFormed() bool {
    const all_conditions: ConditionMask = (@as(ConditionMask, 1) << condition_count) - 1;
    var facility_index: u8 = 0;
    while (facility_index < facility_count) : (facility_index += 1) {
        const facility: Facility = @enumFromInt(facility_index);
        if (facility.owner() == .unknown) return false;
        var operation_index: u8 = 0;
        while (operation_index < operation_count) : (operation_index += 1) {
            const operation: Operation = @enumFromInt(operation_index);
            const required = requirements(facility, operation);
            if (required & ~all_conditions != 0) return false;
            if (facility.carriesGuestPixels() and operation != .present and supports(facility, operation))
                return false;
        }
    }
    return true;
}

/// The mirrored-ordinal claim in `Actor`'s doc comment, checked rather than
/// asserted. The graphics-control contract cannot be imported here — the
/// package must compile standalone — so the ordinals are restated and any
/// divergence shows up as a failing test in both packages' verify runs.
pub fn domainOrdinalsAgree(names: []const []const u8) bool {
    if (names.len != actor_count) return false;
    const expected = [_][]const u8{
        "unknown",
        "guest_title",
        "xenia_powerpc",
        "xenia_host",
        "xenia_vulkan",
        "sdl",
        "rosette_runtime",
        "cocoa_appkit",
        "moltenvk",
        "vulkan_driver",
        "metal_driver",
    };
    for (names, expected) |actual, want| {
        if (!std.mem.eql(u8, actual, want)) return false;
    }
    return true;
}

test "the contract is well formed" {
    try std.testing.expect(contractIsWellFormed());
}

test "an unknown window operation is unaccountable rather than early" {
    const decision = decide(.{
        .actor = .xenia_host,
        .facility = .device,
        .operation = .mutate,
        .observed = 0xFFFF,
    });
    try std.testing.expectEqual(Verdict.refused_unsupported_operation, decision.verdict);
    try std.testing.expect(decision.verdict.isUnaccountable());
    try std.testing.expectEqual(Disposition.fault, disposition(decision.verdict, .fault));
}

test "an early legitimate request is refused but never fatal" {
    const decision = decide(.{
        .actor = .rosette_runtime,
        .facility = .swapchain,
        .operation = .create,
        .observed = conditionBit(.layer_attached),
    });
    try std.testing.expectEqual(Verdict.refused_conditions_unmet, decision.verdict);
    try std.testing.expect(!decision.verdict.isUnaccountable());
    try std.testing.expectEqual(Disposition.refuse, disposition(decision.verdict, .fault));
    try std.testing.expectEqual(Condition.device_ready, decision.firstMissing().?);
}

test "observe policy never changes the answer" {
    var facility_index: u8 = 0;
    while (facility_index < facility_count) : (facility_index += 1) {
        const facility: Facility = @enumFromInt(facility_index);
        var operation_index: u8 = 0;
        while (operation_index < operation_count) : (operation_index += 1) {
            const operation: Operation = @enumFromInt(operation_index);
            const decision = decide(.{ .actor = .guest_title, .facility = facility, .operation = operation });
            try std.testing.expectEqual(Disposition.admit, disposition(decision.verdict, .observe));
        }
    }
}

test "a guest title may look at the window but not resize it" {
    try std.testing.expect(mayForward(.guest_title, .geometry, .query));
    try std.testing.expect(!mayForward(.guest_title, .geometry, .mutate));
    try std.testing.expectEqual(
        Verdict.refused_actor_not_permitted,
        decide(.{ .actor = .guest_title, .facility = .geometry, .operation = .mutate, .observed = 0xFFFF }).verdict,
    );
}

test "nothing but Rosette presents a diagnostic frame" {
    try std.testing.expect(mayForward(.rosette_runtime, .diagnostic_present, .present));
    try std.testing.expect(!mayForward(.xenia_host, .diagnostic_present, .present));
    try std.testing.expect(!mayForward(.guest_title, .diagnostic_present, .present));
}

test "a missing pre-initialized facility is Rosette's defect" {
    const decision = decide(.{
        .actor = .xenia_host,
        .facility = .window,
        .operation = .mutate,
        .observed = 0xFFFF,
        .facility_present = false,
    });
    try std.testing.expectEqual(Verdict.refused_not_preinitialized, decision.verdict);
    try std.testing.expect(decision.verdict.isUnaccountable());
}

test "a facility Rosette does not pre-initialize is not a defect when absent" {
    const decision = decide(.{
        .actor = .rosette_runtime,
        .facility = .swapchain,
        .operation = .create,
        .observed = 0xFFFF,
        .facility_present = false,
    });
    try std.testing.expectEqual(Verdict.admitted, decision.verdict);
}

fn completeSwapEvidence() SwapEvidence {
    return .{
        .provenance = .intercepted_execution,
        .facility_admitted = true,
        .frontbuffer_named = true,
        .frontbuffer_readable = true,
        .extent_valid = true,
        .format_supported = true,
        .epoch_matched = true,
        .custody_available = true,
        .lease_compatible = true,
    };
}

test "a swap known only from a log line is not a swap" {
    var evidence = completeSwapEvidence();
    evidence.provenance = .emulator_log_claim;
    try std.testing.expectEqual(
        SwapVerdict.refused_provenance_insufficient,
        admitSwap(.vd_swap_entry, evidence),
    );
}

test "a complete VdSwap handoff is admitted and closes the authentic stage" {
    const verdict = admitSwap(.vd_swap_entry, completeSwapEvidence());
    try std.testing.expectEqual(SwapVerdict.admitted, verdict);
    try std.testing.expect(verdict.closesAuthenticStage());
}

test "a harness surface is admitted and never closes the authentic stage" {
    var evidence = completeSwapEvidence();
    evidence.frontbuffer_named = false;
    evidence.frontbuffer_harness_supplied = true;
    const verdict = admitSwap(.xe_swap_consumed, evidence);
    try std.testing.expectEqual(SwapVerdict.admitted_harness_surface, verdict);
    try std.testing.expect(verdict.admittedOk());
    try std.testing.expect(!verdict.closesAuthenticStage());
}

test "only the packet boundaries can be refused for a stale epoch" {
    var evidence = completeSwapEvidence();
    evidence.epoch_matched = false;
    try std.testing.expectEqual(SwapVerdict.admitted, admitSwap(.vd_swap_entry, evidence));
    try std.testing.expectEqual(SwapVerdict.refused_epoch_stale, admitSwap(.xe_swap_consumed, evidence));
}

test "swap admission refuses in the order a reader needs" {
    var evidence = completeSwapEvidence();
    evidence.facility_admitted = false;
    evidence.frontbuffer_named = false;
    try std.testing.expectEqual(
        SwapVerdict.refused_facility_not_admitted,
        admitSwap(.vd_swap_entry, evidence),
    );
    evidence.facility_admitted = true;
    try std.testing.expectEqual(
        SwapVerdict.refused_frontbuffer_unknown,
        admitSwap(.vd_swap_entry, evidence),
    );
}

test "custody and the presenter lease are conditions, not consequences" {
    var evidence = completeSwapEvidence();
    evidence.custody_available = false;
    try std.testing.expectEqual(SwapVerdict.refused_custody_unavailable, admitSwap(.vd_swap_entry, evidence));
    evidence.custody_available = true;
    evidence.lease_compatible = false;
    try std.testing.expectEqual(SwapVerdict.refused_lease_conflict, admitSwap(.vd_swap_entry, evidence));
}

test "every swap boundary presents on a guest-pixel facility" {
    var index: u8 = 0;
    while (index < swap_boundary_count) : (index += 1) {
        const boundary: SwapBoundary = @enumFromInt(index);
        try std.testing.expect(boundary.facility().carriesGuestPixels());
        try std.testing.expect(boundary.owner().isEmulatorSide());
    }
}

test "actor ordinals mirror the graphics-control domain" {
    const names = comptime blk: {
        var buffer: [actor_count][]const u8 = undefined;
        for (@typeInfo(Actor).@"enum".fields, 0..) |field, index| buffer[index] = field.name;
        break :blk buffer;
    };
    try std.testing.expect(domainOrdinalsAgree(&names));
}

test "an unrecognized forwarding is unaccountable for every operation" {
    var index: u8 = 0;
    while (index < operation_count) : (index += 1) {
        const operation: Operation = @enumFromInt(index);
        const decision = decide(.{
            .actor = .xenia_host,
            .facility = .unrecognized,
            .operation = operation,
            .observed = 0xFFFF,
        });
        try std.testing.expectEqual(Verdict.refused_unsupported_operation, decision.verdict);
        try std.testing.expect(decision.verdict.isUnaccountable());
        try std.testing.expectEqual(Disposition.fault, disposition(decision.verdict, .fault));
    }
}

test "an unrecognized forwarding is still Rosette's identity" {
    try std.testing.expectEqual(Actor.rosette_runtime, Facility.unrecognized.owner());
    try std.testing.expect(!Facility.unrecognized.carriesGuestPixels());
    try std.testing.expect(!Facility.unrecognized.preinitialized());
}

test "creating a resource does not require the resource to be ready" {
    // Binding a layer is what attaches it, so `layer_attached` cannot gate it.
    try std.testing.expectEqual(@as(ConditionMask, 0), requirements(.layer, .bind) & conditionBit(.layer_attached));
    try std.testing.expectEqual(
        Verdict.admitted,
        decide(.{
            .actor = .xenia_host,
            .facility = .layer,
            .operation = .bind,
            .observed = conditionsOf(&.{ .window_ready, .view_ready }),
        }).verdict,
    );
    // A swapchain is not gated on there already being one.
    try std.testing.expectEqual(@as(ConditionMask, 0), requirements(.swapchain, .create) & conditionBit(.presenter_ready));
}

test "what lies beneath a resource is still required to create it" {
    try std.testing.expectEqual(
        Verdict.refused_conditions_unmet,
        decide(.{ .actor = .rosette_runtime, .facility = .swapchain, .operation = .create }).verdict,
    );
    try std.testing.expectEqual(
        Condition.window_ready,
        decide(.{ .actor = .rosette_runtime, .facility = .layer, .operation = .bind }).firstMissing().?,
    );
}

test "mutating a facility still requires it to be ready" {
    try std.testing.expectEqual(
        Verdict.refused_conditions_unmet,
        decide(.{ .actor = .xenia_host, .facility = .application, .operation = .mutate }).verdict,
    );
    try std.testing.expectEqual(
        Verdict.admitted,
        decide(.{
            .actor = .xenia_host,
            .facility = .application,
            .operation = .mutate,
            .observed = conditionBit(.application_ready),
        }).verdict,
    );
}

test "the authentic swap path is never an ownership violation" {
    try std.testing.expect(everySwapOwnerMayPresent());
    var index: u8 = 0;
    while (index < swap_boundary_count) : (index += 1) {
        const boundary: SwapBoundary = @enumFromInt(index);
        const decision = decide(.{
            .actor = boundary.owner(),
            .facility = boundary.facility(),
            .operation = .present,
            .observed = 0xFFFF,
        });
        // Every condition observed, so the only remaining reason to refuse
        // would be ownership — and that is the class that can be made fatal.
        try std.testing.expectEqual(Verdict.admitted, decision.verdict);
    }
}

test "handing the window to the emulator is never an ownership violation" {
    try std.testing.expect(everyPreinitializedFacilityIsAcquirable());
}

// The regression the first real run produced: Xenia's macOS startup sends
// `[NSApplication sharedApplication]` before anything else, and the gate
// terminated the process on it.
test "the emulator may acquire the application Rosette stood up" {
    const decision = decide(.{
        .actor = .xenia_host,
        .facility = .application,
        .operation = .acquire,
        .observed = 0,
    });
    try std.testing.expectEqual(Verdict.admitted, decision.verdict);
    try std.testing.expectEqual(Disposition.admit, disposition(decision.verdict, .fault));
}

test "the emulator may acquire the layer, view and window it was handed" {
    for ([_]Facility{ .layer, .content_view, .window, .device }) |facility| {
        const decision = decide(.{
            .actor = .xenia_host,
            .facility = facility,
            .operation = .acquire,
            .observed = 0,
        });
        try std.testing.expectEqual(Verdict.admitted, decision.verdict);
    }
}

test "acquiring a facility Rosette failed to stand up is still Rosette's defect" {
    const decision = decide(.{
        .actor = .xenia_host,
        .facility = .application,
        .operation = .acquire,
        .facility_present = false,
    });
    try std.testing.expectEqual(Verdict.refused_not_preinitialized, decision.verdict);
    try std.testing.expect(decision.verdict.isUnaccountable());
}

test "nothing forwards in to create an AppKit singleton" {
    for ([_]Facility{ .application, .window, .content_view, .layer, .device }) |facility| {
        try std.testing.expect(!supports(facility, .create));
        try std.testing.expectEqual(
            Verdict.refused_unsupported_operation,
            decide(.{
                .actor = .rosette_runtime,
                .facility = facility,
                .operation = .create,
                .observed = 0xFFFF,
            }).verdict,
        );
    }
    // Resources that really are created at runtime keep the operation.
    try std.testing.expect(supports(.swapchain, .create));
}

test "acquisition never mutates and is open to every named actor" {
    try std.testing.expect(!Operation.acquire.isMutating());
    try std.testing.expect(!mayForward(.unknown, .application, .acquire));
    try std.testing.expect(mayForward(.guest_title, .application, .acquire));
    try std.testing.expect(mayForward(.sdl, .layer, .acquire));
}

test "the emulator may still activate and show the window it was handed" {
    try std.testing.expectEqual(
        Verdict.admitted,
        decide(.{
            .actor = .xenia_host,
            .facility = .application,
            .operation = .mutate,
            .observed = conditionBit(.application_ready),
        }).verdict,
    );
    try std.testing.expectEqual(
        Verdict.admitted,
        decide(.{
            .actor = .xenia_host,
            .facility = .layer,
            .operation = .bind,
            .observed = conditionsOf(&.{ .window_ready, .view_ready }),
        }).verdict,
    );
}

test "only facilities with a handle can be acquired" {
    for ([_]Facility{ .title, .geometry, .visibility, .fullscreen, .event_pump }) |facility| {
        try std.testing.expect(!facility.hasHandle());
        try std.testing.expect(!supports(facility, .acquire));
    }
    for ([_]Facility{ .application, .window, .content_view, .layer, .device }) |facility| {
        try std.testing.expect(facility.hasHandle());
        try std.testing.expect(supports(facility, .acquire));
    }
}
