//! The fixed-layout vocabulary Rosette and Xenia both write and both read.
//!
//! Why this exists
//! ---------------
//! Rosette and Xenia have separate diagnostic vocabularies, and the most
//! expensive consequence is not duplication — it is that two correct sentences
//! about one fact cannot be compared. A run says the pointer update was
//! "printed but not applied" while a different layer consumed the data that
//! update described. Both are true about what they measured and neither can be
//! joined to the other, because nothing names the same ring, the same epoch or
//! the same sequence.
//!
//! So this is not another health percentage. It is a small evidence ABI: fixed
//! widths, explicit endianness, one schema version, and one set of enums whose
//! numeric values mean the same thing on both sides of the process boundary.
//!
//! The rules the layout obeys
//! -------------------------
//! * Every field is fixed width. There is no pointer-sized field whose meaning
//!   changes between a 64-bit Rosette build and whatever Xenia was compiled as.
//! * Addresses are carried three times — guest virtual, guest physical, host —
//!   because collapsing them is how an alias bug becomes invisible.
//! * Every record carries both a guest step and a host monotonic time. Neither
//!   is sufficient: guest steps do not advance while the guest is paused, and
//!   host time does not order two guest threads.
//! * Every record states its own authenticity. A diagnostic frame and a title
//!   frame are the same shape and must never be the same fact.
//! * Absence is representable. `unknown` is a value in every classification
//!   enum, and it is never a synonym for the healthy case.

const std = @import("std");

/// Bumped when a field changes meaning or a record grows. A reader that does
/// not recognise the version reports the records as unreadable rather than
/// guessing at the layout.
// Version 3 adds route-specific custody edges and makes the journal checksum
// cover the complete fixed record rather than only its identity subset.  A
// reader must reject an older stream instead of silently treating a mutable
// field or payload as authenticated evidence.
pub const schema_version: u16 = 3;

/// Wire byte order. Both processes run on the same host, but the journal is a
/// file that outlives the run and can be read on another machine, so the
/// encoding is stated rather than inherited.
pub const wire_endian: std.builtin.Endian = .little;

/// Optional capabilities a producer declares. A reader uses this to tell "this
/// producer does not emit resolves" from "this run had no resolves", which are
/// the same zero and different facts.
pub const Feature = enum(u6) {
    ring_transport = 0,
    pm4_decode = 1,
    render_target = 2,
    edram = 3,
    resolve = 4,
    synchronization = 5,
    interrupt_effect = 6,
    frame_custody = 7,
    fault_pause = 8,
    execution_provenance = 9,
    memory_alias = 10,
    storage_integrity = 11,
    translation_budget = 12,
    vulkan_forwarding = 13,
    kernel_service = 14,
    import_integrity = 15,
    shader_pipeline = 16,

    pub fn bit(self: Feature) u64 {
        return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(self)));
    }

    pub fn label(self: Feature) []const u8 {
        return switch (self) {
            .ring_transport => "ring-transport",
            .pm4_decode => "pm4-decode",
            .render_target => "render-target",
            .edram => "edram",
            .resolve => "resolve",
            .synchronization => "synchronization",
            .interrupt_effect => "interrupt-effect",
            .frame_custody => "frame-custody",
            .fault_pause => "fault-pause",
            .execution_provenance => "execution-provenance",
            .memory_alias => "memory-alias",
            .storage_integrity => "storage-integrity",
            .translation_budget => "translation-budget",
            .vulkan_forwarding => "vulkan-forwarding",
            .kernel_service => "kernel-service",
            .import_integrity => "import-integrity",
            .shader_pipeline => "shader-pipeline",
        };
    }
};

pub const feature_count: usize = @typeInfo(Feature).@"enum".fields.len;

pub const FeatureSet = struct {
    bits: u64 = 0,

    pub fn with(self: FeatureSet, feature: Feature) FeatureSet {
        return .{ .bits = self.bits | feature.bit() };
    }

    pub fn has(self: FeatureSet, feature: Feature) bool {
        return (self.bits & feature.bit()) != 0;
    }

    pub fn count(self: FeatureSet) usize {
        return @popCount(self.bits);
    }
};

/// Which half of the system produced a record. Local sequence numbers are per
/// domain; the bridge reconciles them into one order.
pub const Domain = enum(u8) {
    rosette_scheduler = 0,
    rosette_memory = 1,
    rosette_gpu = 2,
    rosette_run_integrity = 3,
    xenia_kernel = 4,
    xenia_command_processor = 5,
    xenia_vulkan = 6,
    xenia_presenter = 7,
    guest_title = 8,
    unknown = 255,

    pub fn label(self: Domain) []const u8 {
        return switch (self) {
            .rosette_scheduler => "rosette:scheduler",
            .rosette_memory => "rosette:memory",
            .rosette_gpu => "rosette:gpu",
            .rosette_run_integrity => "rosette:run-integrity",
            .xenia_kernel => "xenia:kernel",
            .xenia_command_processor => "xenia:command-processor",
            .xenia_vulkan => "xenia:vulkan",
            .xenia_presenter => "xenia:presenter",
            .guest_title => "guest:title",
            .unknown => "unknown",
        };
    }

    /// Whether this domain executes guest instructions. A record from a domain
    /// that does not cannot claim a guest program counter as its own.
    pub fn executesGuestCode(self: Domain) bool {
        return switch (self) {
            .guest_title, .rosette_scheduler, .xenia_kernel => true,
            else => false,
        };
    }
};

pub const domain_count: usize = @typeInfo(Domain).@"enum".fields.len;

/// Where the substance of an event came from. This is the field that keeps a
/// diagnostic clear frame and a title frame apart forever.
pub const SourceClass = enum(u8) {
    /// The guest did it. The only class that may satisfy a title contract.
    guest_authentic = 0,
    /// The host forwarded a guest request. Real work, guest-initiated, but the
    /// content is the host's rendering of it.
    host_forwarded = 1,
    /// The harness produced it to keep something observable. Never a title
    /// fact.
    diagnostic = 2,
    /// The harness produced it in place of a guest action that did not happen.
    /// Its presence invalidates authenticity for everything downstream.
    synthetic = 3,
    /// A retained batch replayed against a model. Useful for agreement
    /// checking, never evidence of live execution.
    replay = 4,
    unknown = 255,

    pub fn label(self: SourceClass) []const u8 {
        return switch (self) {
            .guest_authentic => "guest-authentic",
            .host_forwarded => "host-forwarded",
            .diagnostic => "diagnostic",
            .synthetic => "synthetic",
            .replay => "replay",
            .unknown => "unknown",
        };
    }

    /// Whether a contract clause owned by the title may be satisfied by this.
    pub fn satisfiesTitleContract(self: SourceClass) bool {
        return self == .guest_authentic;
    }

    /// Whether the presence of this class anywhere upstream makes the run
    /// permanently non-authentic.
    pub fn taintsAuthenticity(self: SourceClass) bool {
        return self == .synthetic or self == .replay;
    }
};

/// What happened, as distinct from what was attempted.
pub const ResultClass = enum(u8) {
    observed = 0,
    /// Attempted and completed with the expected effect.
    applied = 1,
    /// Attempted and completed with no observable effect.
    inert = 2,
    /// Declined by a gate. A refusal is a decision and is never an error.
    refused = 3,
    /// Attempted and failed.
    failed = 4,
    /// The producer could not observe the outcome. Distinct from `inert`.
    unobserved = 5,
    /// Two observers disagreed and neither was promoted.
    unreconciled = 6,
    unknown = 255,

    pub fn label(self: ResultClass) []const u8 {
        return switch (self) {
            .observed => "observed",
            .applied => "applied",
            .inert => "inert",
            .refused => "refused",
            .failed => "failed",
            .unobserved => "unobserved",
            .unreconciled => "unreconciled",
            .unknown => "unknown",
        };
    }

    pub fn isProgress(self: ResultClass) bool {
        return self == .applied;
    }
};

/// The producer that owns the observation. `SourceClass` answers whether the
/// content may satisfy a title contract; this answers which execution domain
/// is accountable for the transition. Keeping the two separate prevents a
/// host-forwarded callback from being mistaken for a guest instruction merely
/// because it carried guest arguments.
pub const Provenance = enum(u8) {
    guest = 0,
    xenia = 1,
    rosette_control = 2,
    diagnostic = 3,
    synthetic = 4,
    replay = 5,
    unknown = 255,

    pub fn label(self: Provenance) []const u8 {
        return switch (self) {
            .guest => "guest",
            .xenia => "xenia",
            .rosette_control => "rosette-control",
            .diagnostic => "diagnostic",
            .synthetic => "synthetic",
            .replay => "replay",
            .unknown => "unknown",
        };
    }

    pub fn mayAdvanceGuestState(self: Provenance) bool {
        return self == .guest or self == .xenia;
    }
};

/// A compact summary of the effect a boundary actually committed. A return
/// from the outer host function is not one of these effects; it is only the
/// `ResultClass` of the attempt. The bit set is deliberately extensible and is
/// carried in fixed-width event records.
pub const Effect = enum(u8) {
    none = 0,
    guest_memory_write = 1,
    guest_register_write = 2,
    guest_object_signal = 3,
    ring_publication = 4,
    ring_consumption = 5,
    pm4_state_change = 6,
    render_target_write = 7,
    resolve_output = 8,
    frame_custody = 9,
    host_present = 10,
    unknown = 255,

    pub fn bit(self: Effect) u64 {
        if (self == .unknown) return 0;
        return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(self)));
    }
};

/// One canonical edge vocabulary for the event ledger. The values are stable
/// on disk and are intentionally grouped by subsystem rather than by source
/// file, so Xenia and Rosette can name the same prerequisite.
pub const ContractEdge = enum(u16) {
    none = 0,
    callback_registration = 1,
    callback_request = 2,
    callback_delivery = 3,
    callback_effect = 4,
    wait_object_signal = 5,
    ring_initialization = 10,
    ring_initialization_ack = 11,
    guest_wptr_publication = 12,
    cp_wptr_update = 13,
    pm4_execution = 14,
    draw_state = 15,
    render_target_state = 16,
    render_target_update = 17,
    output_custody = 18,
    vdswap_entry = 20,
    xe_swap_encoding = 21,
    guest_swap_publication = 22,
    xe_swap_execution = 23,
    output_refresh = 24,
    presenter_submission = 25,
    cocoa_custody = 26,
    vulkan_custody = 27,
    d3d_custody = 28,

    pub fn label(self: ContractEdge) []const u8 {
        return switch (self) {
            .none => "none",
            .callback_registration => "callback-registration",
            .callback_request => "callback-request",
            .callback_delivery => "callback-delivery",
            .callback_effect => "callback-effect",
            .wait_object_signal => "wait-object-signal",
            .ring_initialization => "ring-initialization",
            .ring_initialization_ack => "ring-initialization-ack",
            .guest_wptr_publication => "guest-wptr-publication",
            .cp_wptr_update => "cp-wptr-update",
            .pm4_execution => "pm4-execution",
            .draw_state => "draw-state",
            .render_target_state => "render-target-state",
            .render_target_update => "render-target-update",
            .output_custody => "output-custody",
            .vdswap_entry => "vdswap-entry",
            .xe_swap_encoding => "xe-swap-encoding",
            .guest_swap_publication => "guest-swap-publication",
            .xe_swap_execution => "xe-swap-execution",
            .output_refresh => "output-refresh",
            .presenter_submission => "presenter-submission",
            .cocoa_custody => "cocoa-custody",
            .vulkan_custody => "vulkan-custody",
            .d3d_custody => "d3d-custody",
        };
    }

    pub fn prerequisite(self: ContractEdge) ContractEdge {
        return switch (self) {
            .callback_request => .callback_registration,
            .callback_delivery => .callback_request,
            .callback_effect => .callback_delivery,
            .wait_object_signal => .callback_effect,
            .ring_initialization_ack => .ring_initialization,
            .guest_wptr_publication => .ring_initialization_ack,
            .cp_wptr_update => .guest_wptr_publication,
            .pm4_execution => .cp_wptr_update,
            .draw_state => .pm4_execution,
            .render_target_state => .draw_state,
            .render_target_update => .render_target_state,
            .output_custody => .render_target_update,
            .xe_swap_encoding => .vdswap_entry,
            .guest_swap_publication => .xe_swap_encoding,
            .xe_swap_execution => .guest_swap_publication,
            .output_refresh => .xe_swap_execution,
            .presenter_submission => .output_refresh,
            .cocoa_custody => .presenter_submission,
            .vulkan_custody => .presenter_submission,
            .d3d_custody => .presenter_submission,
            else => .none,
        };
    }
};

/// What kind of thing the record is about. Deliberately coarse: the detail
/// lives in the payload structs, and a coarse kind keeps the reconciliation
/// rules small enough to reason about.
pub const EventKind = enum(u16) {
    run_started = 0,
    run_manifest = 1,
    producer_epoch = 10,
    ring_stage = 11,
    pm4_packet = 12,
    register_write = 13,
    draw = 14,
    render_target_stage = 15,
    edram_write = 16,
    resolve = 17,
    swap_request = 18,
    frame_custody = 19,
    interrupt_dispatch = 30,
    interrupt_effect = 31,
    wait_enter = 40,
    wait_result = 41,
    signal = 42,
    object_created = 43,
    object_destroyed = 44,
    fault = 50,
    pause = 51,
    resume_execution = 52,
    memory_map = 60,
    protection_watch = 61,
    storage_read = 62,
    translation_budget = 70,
    run_terminated = 90,
    journal_gap = 91,
    callback_request = 92,
    callback_delivery = 93,
    state_effect = 94,
    context_custody = 95,
    source_map = 96,
    coverage = 97,
    vulkan_custody = 98,
    d3d_custody = 99,

    pub fn label(self: EventKind) []const u8 {
        return switch (self) {
            .run_started => "run-started",
            .run_manifest => "run-manifest",
            .producer_epoch => "producer-epoch",
            .ring_stage => "ring-stage",
            .pm4_packet => "pm4-packet",
            .register_write => "register-write",
            .draw => "draw",
            .render_target_stage => "render-target-stage",
            .edram_write => "edram-write",
            .resolve => "resolve",
            .swap_request => "swap-request",
            .frame_custody => "frame-custody",
            .interrupt_dispatch => "interrupt-dispatch",
            .interrupt_effect => "interrupt-effect",
            .wait_enter => "wait-enter",
            .wait_result => "wait-result",
            .signal => "signal",
            .object_created => "object-created",
            .object_destroyed => "object-destroyed",
            .fault => "fault",
            .pause => "pause",
            .resume_execution => "resume",
            .memory_map => "memory-map",
            .protection_watch => "protection-watch",
            .storage_read => "storage-read",
            .translation_budget => "translation-budget",
            .run_terminated => "run-terminated",
            .journal_gap => "journal-gap",
            .callback_request => "callback-request",
            .callback_delivery => "callback-delivery",
            .state_effect => "state-effect",
            .context_custody => "context-custody",
            .source_map => "source-map",
            .coverage => "coverage",
            .vulkan_custody => "vulkan-custody",
            .d3d_custody => "d3d-custody",
        };
    }

    /// Kinds that must never be dropped. The journal reserves capacity for
    /// these, because their absence is what a causal claim rests on: if a
    /// fault record can be dropped, "no fault occurred" is not a fact.
    pub fn isCritical(self: EventKind) bool {
        return switch (self) {
            .run_started,
            .run_manifest,
            .producer_epoch,
            .ring_stage,
            .render_target_stage,
            .resolve,
            .swap_request,
            .frame_custody,
            .interrupt_effect,
            .wait_result,
            .signal,
            .fault,
            .pause,
            .resume_execution,
            .run_terminated,
            .journal_gap,
            .callback_request,
            .callback_delivery,
            .state_effect,
            .context_custody,
            .vulkan_custody,
            .d3d_custody,
            => true,
            else => false,
        };
    }
};

/// Decode a stored discriminant, falling back rather than trapping.
///
/// A record can arrive from an older producer, a newer one, or a corrupted
/// byte, and every one of those has to become a named `unknown` rather than
/// illegal behaviour. This is the only place in the package that turns bytes
/// into enums.
pub fn decode(comptime T: type, value: anytype, fallback: T) T {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        if (value == field.value) return @field(T, field.name);
    }
    return fallback;
}

/// A run's stable identity. Two logs belong to the same run only when all
/// three agree; the image hash alone matches every run of the same build.
pub const RunIdentity = extern struct {
    run_id: u64 = 0,
    image_hash: u64 = 0,
    media_hash: u64 = 0,
    title_id: u32 = 0,
    schema: u16 = schema_version,
    reserved: u16 = 0,

    pub fn sameRun(self: RunIdentity, other: RunIdentity) bool {
        return self.run_id == other.run_id and
            self.image_hash == other.image_hash and
            self.media_hash == other.media_hash and
            self.title_id == other.title_id and
            self.schema == other.schema;
    }

    pub fn valid(self: RunIdentity) bool {
        return self.run_id != 0 and self.schema == schema_version;
    }
};

/// One address, named three ways. A record that carries only the host address
/// cannot be joined to a guest observation, and a record that carries only the
/// guest virtual address cannot be joined to a physical alias.
pub const Address = extern struct {
    guest_virtual: u32 = 0,
    guest_physical: u32 = 0,
    host: u64 = 0,

    pub fn any(self: Address) bool {
        return self.guest_virtual != 0 or self.guest_physical != 0 or self.host != 0;
    }

    /// Whether two records are talking about the same memory. Agreement on any
    /// one non-zero route is enough; disagreement on a route both state is not
    /// the same memory however well the others match.
    pub fn joins(self: Address, other: Address) bool {
        var agreed = false;
        if (self.guest_virtual != 0 and other.guest_virtual != 0) {
            if (self.guest_virtual != other.guest_virtual) return false;
            agreed = true;
        }
        if (self.guest_physical != 0 and other.guest_physical != 0) {
            if (self.guest_physical != other.guest_physical) return false;
            agreed = true;
        }
        if (self.host != 0 and other.host != 0) {
            if (self.host != other.host) return false;
            agreed = true;
        }
        return agreed;
    }
};

/// Where execution was, and how much that claim is worth. `quality` exists
/// because a seeded or stale program counter names an instruction that is not
/// the one executing, and reporting it as a location sends a reader to the
/// wrong place with more confidence than an unknown would have.
pub const CodeLocation = extern struct {
    guest_pc: u32 = 0,
    guest_lr: u32 = 0,
    host_rip: u64 = 0,
    module_id: u32 = 0,
    /// `Provenance` value. Stored as a byte so the record stays fixed-layout.
    provenance: u8 = @intFromEnum(CodeLocation.Provenance.unknown),
    quality: u8 = @intFromEnum(Quality.unavailable),
    reserved: u16 = 0,

    pub const Provenance = enum(u8) {
        /// A guest PowerPC instruction with a guest address and a module.
        guest_instruction = 0,
        /// A translated block, with the guest range it came from.
        translated_block = 1,
        rosette_runtime = 2,
        xenia_emulator = 3,
        xenia_jit = 4,
        native_library = 5,
        unknown = 255,

        pub fn label(self: CodeLocation.Provenance) []const u8 {
            return switch (self) {
                .guest_instruction => "guest-instruction",
                .translated_block => "translated-block",
                .rosette_runtime => "rosette-runtime",
                .xenia_emulator => "xenia-emulator",
                .xenia_jit => "xenia-jit",
                .native_library => "native-library",
                .unknown => "unknown",
            };
        }

        /// Whether a "the guest is stopped here" claim may cite this. A JIT
        /// compiler loop is host work; naming it as a guest location is how a
        /// throughput problem gets investigated as a deadlock.
        pub fn namesGuestCode(self: CodeLocation.Provenance) bool {
            return self == .guest_instruction or self == .translated_block;
        }
    };

    pub const Quality = enum(u8) {
        /// Read from the executing context.
        direct = 0,
        /// Resolved through a validated map.
        tracked = 1,
        /// Carried forward from an earlier observation. Names an instruction
        /// that is probably not the current one.
        seeded = 2,
        unavailable = 255,

        pub fn label(self: Quality) []const u8 {
            return switch (self) {
                .direct => "direct",
                .tracked => "tracked",
                .seeded => "seeded",
                .unavailable => "unavailable",
            };
        }

        pub fn trustworthy(self: Quality) bool {
            return self == .direct or self == .tracked;
        }
    };

    pub fn provenanceOf(self: CodeLocation) CodeLocation.Provenance {
        return decode(CodeLocation.Provenance, self.provenance, .unknown);
    }

    pub fn qualityOf(self: CodeLocation) Quality {
        return decode(Quality, self.quality, .unavailable);
    }

    /// Whether a report may say "the guest is here". Both halves are needed:
    /// a trustworthy sample of host JIT code is still not a guest location,
    /// and a guest-domain sample that was seeded is still not this instruction.
    pub fn citableAsGuestLocation(self: CodeLocation) bool {
        return self.provenanceOf().namesGuestCode() and
            self.qualityOf().trustworthy() and
            self.guest_pc != 0;
    }

    /// The link register is written by the call instruction itself, so it
    /// still names the caller even when the program counter is seeded. This is
    /// the fallback a reader can act on when the PC cannot be cited.
    pub fn fallbackCallSite(self: CodeLocation) ?u32 {
        if (self.citableAsGuestLocation()) return self.guest_pc;
        if (self.guest_lr != 0) return self.guest_lr;
        return null;
    }
};

test "a feature set reports what a producer declared, not what a run contained" {
    var set = FeatureSet{};
    try std.testing.expect(!set.has(.resolve));
    set = set.with(.ring_transport).with(.pm4_decode);
    try std.testing.expect(set.has(.ring_transport));
    try std.testing.expect(!set.has(.resolve));
    try std.testing.expectEqual(@as(usize, 2), set.count());
}

test "only a guest-authentic source satisfies a title contract" {
    try std.testing.expect(SourceClass.guest_authentic.satisfiesTitleContract());
    inline for ([_]SourceClass{ .host_forwarded, .diagnostic, .synthetic, .replay, .unknown }) |class| {
        try std.testing.expect(!class.satisfiesTitleContract());
    }
    try std.testing.expect(SourceClass.synthetic.taintsAuthenticity());
    try std.testing.expect(SourceClass.replay.taintsAuthenticity());
    try std.testing.expect(!SourceClass.diagnostic.taintsAuthenticity());
}

test "addresses join on a shared route and refuse on a contradicted one" {
    const ring_physical = Address{ .guest_physical = 0x1FC9_B000, .host = 0x4_6F12_B000 };
    const same = Address{ .guest_physical = 0x1FC9_B000 };
    const other_alias = Address{ .guest_physical = 0x1FC9_B000, .host = 0x4_4F12_B000 };
    const unrelated = Address{ .guest_physical = 0x1FC9_C000 };

    try std.testing.expect(ring_physical.joins(same));
    // Same physical page, different host mapping: this is the alias split that
    // made one buffer look like two, and it must not read as the same memory.
    try std.testing.expect(!ring_physical.joins(other_alias));
    try std.testing.expect(!ring_physical.joins(unrelated));
    // Nothing in common is not agreement.
    try std.testing.expect(!(Address{}).joins(same));
}

test "a JIT sample is never citable as a guest location" {
    const jit = CodeLocation{
        .host_rip = 0x1_0000,
        .provenance = @intFromEnum(CodeLocation.Provenance.xenia_jit),
        .quality = @intFromEnum(CodeLocation.Quality.direct),
    };
    try std.testing.expect(!jit.citableAsGuestLocation());
    try std.testing.expect(jit.fallbackCallSite() == null);

    const seeded = CodeLocation{
        .guest_pc = 0x8258_A470,
        .guest_lr = 0x825A_E908,
        .provenance = @intFromEnum(CodeLocation.Provenance.guest_instruction),
        .quality = @intFromEnum(CodeLocation.Quality.seeded),
    };
    try std.testing.expect(!seeded.citableAsGuestLocation());
    // The link register survives the seeding and still names the caller.
    try std.testing.expectEqual(@as(u32, 0x825A_E908), seeded.fallbackCallSite().?);

    const direct = CodeLocation{
        .guest_pc = 0x8258_A470,
        .provenance = @intFromEnum(CodeLocation.Provenance.guest_instruction),
        .quality = @intFromEnum(CodeLocation.Quality.direct),
    };
    try std.testing.expect(direct.citableAsGuestLocation());
}

test "a run identity needs all three hashes to match" {
    const a = RunIdentity{ .run_id = 0x73b0_1ab4_0583_f0e8, .image_hash = 0x5ca5_bdca_5fd1_6245, .media_hash = 7, .title_id = 0x4D53_07E6 };
    var b = a;
    try std.testing.expect(a.sameRun(b));
    try std.testing.expect(a.valid());
    b.media_hash = 8;
    try std.testing.expect(!a.sameRun(b));
    b = a;
    b.title_id += 1;
    try std.testing.expect(!a.sameRun(b));
    b = a;
    b.schema += 1;
    try std.testing.expect(!a.sameRun(b));
    try std.testing.expect(!(RunIdentity{}).valid());
}

test "critical kinds are the ones a causal claim rests on" {
    try std.testing.expect(EventKind.fault.isCritical());
    try std.testing.expect(EventKind.pause.isCritical());
    try std.testing.expect(EventKind.frame_custody.isCritical());
    try std.testing.expect(EventKind.journal_gap.isCritical());
    // High-volume kinds are droppable on purpose: reserving for them would
    // crowd out the records whose absence is load-bearing.
    try std.testing.expect(!EventKind.pm4_packet.isCritical());
    try std.testing.expect(!EventKind.register_write.isCritical());
}

test "every enum value states a label and unknown is always available" {
    inline for (@typeInfo(Domain).@"enum".fields) |field| {
        const value: Domain = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
    inline for (@typeInfo(EventKind).@"enum".fields) |field| {
        const value: EventKind = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
    try std.testing.expectEqualStrings("unknown", Domain.unknown.label());
    try std.testing.expectEqualStrings("unknown", SourceClass.unknown.label());
    try std.testing.expectEqualStrings("unknown", ResultClass.unknown.label());
}
