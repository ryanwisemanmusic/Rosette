//! Resolution of graphics meaning at typed boundaries.
//!
//! Rosette may translate x86 instructions, but a CPU instruction is not a
//! Cocoa operation. Meaning is admitted only after an intercepted import,
//! named API boundary, decoded PM4 packet, or completed native event identifies
//! the operation and its execution domain. This prevents an integer that is a
//! PowerPC callback address from becoming a translated-x86 call target, and it
//! prevents an arbitrary store from becoming a request to draw a window.

const std = @import("std");
const contract = @import("cocoa_graphics_control_contract");

pub const Domain = contract.Domain;
pub const Evidence = contract.Evidence;
pub const Operation = contract.Operation;
pub const AddressSpace = contract.AddressSpace;

pub const Source = enum(u8) {
    raw_instruction,
    intercepted_import,
    named_symbol,
    structured_callback,
    decoded_pm4,
    native_event,

    pub fn semantic(self: Source) bool {
        return self != .raw_instruction;
    }
};

pub const Import = enum(u8) {
    vd_initialize_engines,
    vd_set_graphics_interrupt_callback,
    vd_swap,
    xe_swap,
    issue_swap,
    sdl_create_window,
    sdl_pump_events,
    vk_create_metal_surface,
    vk_create_swapchain,
    vk_queue_present,
};

pub const Pm4Class = enum(u8) {
    ring_publication,
    register_write,
    draw,
    event_write,
    interrupt,
    xe_swap,
    unknown,
};

pub const NativeEvent = enum(u8) {
    application_created,
    window_created,
    layer_attached,
    drawable_acquired,
    guest_frame_offered,
    guest_frame_presented,
    diagnostic_frame_presented,
};

pub const Boundary = union(Source) {
    raw_instruction: struct {
        rip: u64,
        opcode: u32,
    },
    intercepted_import: struct {
        function: Import,
        address: u64,
        space: AddressSpace,
    },
    named_symbol: struct {
        name: []const u8,
        address: u64,
        space: AddressSpace,
    },
    structured_callback: struct {
        endpoint: contract.CallbackEndpoint,
        executor: contract.Executor,
    },
    decoded_pm4: struct {
        packet_class: Pm4Class,
        header: u32,
    },
    native_event: NativeEvent,
};

pub const Request = struct {
    run: u64 = 1,
    boundary: Boundary,
    producer: Domain,
    evidence: Evidence,
    source_identity: u64,
    generation: u64,
    sequence: u64,
};

pub const Intent = struct {
    operation: Operation,
    source: Source,
    producer: Domain,
    expected_owner: Domain,
    evidence: Evidence,
    source_identity: u64,
    generation: u64,
    sequence: u64,
};

pub const Rejection = enum(u8) {
    none,
    raw_instruction_has_no_graphics_meaning,
    unknown_symbol,
    unknown_pm4_packet,
    callback_domain_mismatch,
    insufficient_evidence,
    malformed_identity,
    producer_domain_mismatch,

    pub fn label(self: Rejection) []const u8 {
        return switch (self) {
            .none => "none",
            .raw_instruction_has_no_graphics_meaning => "raw-instruction-has-no-graphics-meaning",
            .unknown_symbol => "unknown-symbol",
            .unknown_pm4_packet => "unknown-pm4-packet",
            .callback_domain_mismatch => "callback-domain-mismatch",
            .insufficient_evidence => "insufficient-evidence",
            .malformed_identity => "malformed-identity",
            .producer_domain_mismatch => "producer-domain-mismatch",
        };
    }
};

pub const Resolution = union(enum) {
    admitted: Intent,
    rejected: Rejection,
};

pub const ObserveResult = enum(u8) {
    admitted,
    rejected,
    duplicate_observation,
    identity_conflict,
};

pub const operation_count: usize = @typeInfo(Operation).@"enum".fields.len;
pub const source_count: usize = @typeInfo(Source).@"enum".fields.len;
pub const rejection_count: usize = @typeInfo(Rejection).@"enum".fields.len;
pub const max_records: usize = 128;

pub const Record = struct {
    run: u64 = 0,
    source_identity: u64 = 0,
    generation: u64 = 0,
    sequence: u64 = 0,
    source: Source = .raw_instruction,
    producer: Domain = .unknown,
    operation: ?Operation = null,
    rejection: Rejection = .none,
    observations: u64 = 0,
    conflict: bool = false,

    fn sameIdentity(self: Record, other: Record) bool {
        return self.run == other.run and self.source_identity == other.source_identity and
            self.generation == other.generation and self.sequence == other.sequence;
    }

    fn sameMeaning(self: Record, other: Record) bool {
        return self.source == other.source and self.producer == other.producer and
            self.operation == other.operation and self.rejection == other.rejection;
    }
};

pub const Summary = struct {
    observations: u64 = 0,
    admitted: u64 = 0,
    rejected: u64 = 0,
    duplicates: u64 = 0,
    conflicts: u64 = 0,
    operations: [operation_count]u64 = [_]u64{0} ** operation_count,
    sources: [source_count]u64 = [_]u64{0} ** source_count,
    rejections: [rejection_count]u64 = [_]u64{0} ** rejection_count,
};

/// Bounded runtime journal for the semantic boundary itself. It uses the same
/// identity discipline as GPU work credit: seeing one decoded packet in 148
/// reports is 148 observations of one meaning, while assigning two meanings to
/// the same `(run, source, generation, sequence)` is quarantined as conflict.
pub const Ledger = struct {
    records: [max_records]Record = [_]Record{.{}} ** max_records,
    count: usize = 0,
    next: usize = 0,
    totals: Summary = .{},

    pub fn observe(self: *Ledger, request: Request) ObserveResult {
        self.totals.observations +|= 1;
        const resolution = resolve(request);
        const source = std.meta.activeTag(request.boundary);
        const candidate = switch (resolution) {
            .admitted => |intent| Record{
                .run = request.run,
                .source_identity = request.source_identity,
                .generation = request.generation,
                .sequence = request.sequence,
                .source = source,
                .producer = request.producer,
                .operation = intent.operation,
                .observations = 1,
            },
            .rejected => |rejection| Record{
                .run = request.run,
                .source_identity = request.source_identity,
                .generation = request.generation,
                .sequence = request.sequence,
                .source = source,
                .producer = request.producer,
                .rejection = rejection,
                .observations = 1,
            },
        };

        if (self.findIdentity(candidate)) |existing| {
            existing.observations +|= 1;
            if (!existing.sameMeaning(candidate)) {
                if (!existing.conflict) self.totals.conflicts +|= 1;
                existing.conflict = true;
                return .identity_conflict;
            }
            self.totals.duplicates +|= 1;
            return .duplicate_observation;
        }

        self.store(candidate);
        self.totals.sources[@intFromEnum(source)] +|= 1;
        return switch (resolution) {
            .admitted => |intent| blk: {
                self.totals.admitted +|= 1;
                self.totals.operations[@intFromEnum(intent.operation)] +|= 1;
                break :blk .admitted;
            },
            .rejected => |rejection| blk: {
                self.totals.rejected +|= 1;
                self.totals.rejections[@intFromEnum(rejection)] +|= 1;
                break :blk .rejected;
            },
        };
    }

    pub fn summary(self: *const Ledger) Summary {
        return self.totals;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = 14_695_981_039_346_656_037;
        hash = mix(hash, self.totals.admitted);
        hash = mix(hash, self.totals.rejected);
        hash = mix(hash, self.totals.conflicts);
        inline for (0..operation_count) |index| hash = mix(hash, self.totals.operations[index]);
        inline for (0..rejection_count) |index| hash = mix(hash, self.totals.rejections[index]);
        return hash;
    }

    fn findIdentity(self: *Ledger, candidate: Record) ?*Record {
        for (self.records[0..self.count]) |*record| {
            if (record.sameIdentity(candidate)) return record;
        }
        return null;
    }

    fn store(self: *Ledger, record: Record) void {
        self.records[self.next] = record;
        self.next = (self.next + 1) % max_records;
        if (self.count < max_records) self.count += 1;
    }
};

pub fn resolve(request: Request) Resolution {
    if (request.run == 0 or request.source_identity == 0 or request.generation == 0 or request.sequence == 0)
        return .{ .rejected = .malformed_identity };

    const source = std.meta.activeTag(request.boundary);
    if (!source.semantic()) return .{ .rejected = .raw_instruction_has_no_graphics_meaning };
    if (!request.evidence.provesIdentity()) return .{ .rejected = .insufficient_evidence };

    const operation = switch (request.boundary) {
        .raw_instruction => unreachable,
        .intercepted_import => |call| blk: {
            if (!importDomainValid(call.function, request.producer, call.space))
                return .{ .rejected = .producer_domain_mismatch };
            break :blk operationForImport(call.function);
        },
        .named_symbol => |call| blk: {
            const mapped = operationForSymbol(call.name) orelse return .{ .rejected = .unknown_symbol };
            if (!symbolDomainValid(mapped, request.producer, call.space))
                return .{ .rejected = .producer_domain_mismatch };
            break :blk mapped;
        },
        .structured_callback => |call| blk: {
            if (!contract.canInvoke(call.executor, call.endpoint))
                return .{ .rejected = .callback_domain_mismatch };
            break :blk .dispatch_completion;
        },
        .decoded_pm4 => |packet| operationForPm4(packet.packet_class) orelse
            return .{ .rejected = .unknown_pm4_packet },
        .native_event => |event| operationForNativeEvent(event),
    };

    const expected_owner = ownerFor(operation, request.producer);
    if (!producerMayState(operation, request.producer))
        return .{ .rejected = .producer_domain_mismatch };
    return .{ .admitted = .{
        .operation = operation,
        .source = source,
        .producer = request.producer,
        .expected_owner = expected_owner,
        .evidence = request.evidence,
        .source_identity = request.source_identity,
        .generation = request.generation,
        .sequence = request.sequence,
    } };
}

fn mix(hash: u64, value: u64) u64 {
    return (hash ^ value) *% 1_099_511_628_211;
}

pub fn operationForImport(function: Import) Operation {
    return switch (function) {
        .vd_initialize_engines => .publish_ring,
        .vd_set_graphics_interrupt_callback => .dispatch_completion,
        .vd_swap => .vd_swap,
        .xe_swap => .xe_swap,
        .issue_swap, .vk_queue_present => .issue_swap,
        .sdl_create_window => .bind_sdl_window,
        .sdl_pump_events => .pump_events,
        .vk_create_metal_surface => .create_vulkan_surface,
        .vk_create_swapchain => .create_swapchain,
    };
}

pub fn operationForSymbol(name: []const u8) ?Operation {
    const Entry = struct { name: []const u8, operation: Operation };
    const entries = [_]Entry{
        .{ .name = "VdSwap", .operation = .vd_swap },
        .{ .name = "XE_SWAP", .operation = .xe_swap },
        .{ .name = "IssueSwap", .operation = .issue_swap },
        .{ .name = "vkQueuePresentKHR", .operation = .issue_swap },
        .{ .name = "vkCreateMetalSurfaceEXT", .operation = .create_vulkan_surface },
        .{ .name = "vkCreateSwapchainKHR", .operation = .create_swapchain },
        .{ .name = "SDL_CreateWindow", .operation = .bind_sdl_window },
        .{ .name = "SDL_PumpEvents", .operation = .pump_events },
    };
    for (entries) |entry| if (std.mem.eql(u8, name, entry.name)) return entry.operation;
    return null;
}

fn operationForPm4(class: Pm4Class) ?Operation {
    return switch (class) {
        .ring_publication => .publish_ring,
        .register_write => .program_render_target,
        .draw => .submit_draw,
        .event_write => .signal_completion,
        .interrupt => .dispatch_completion,
        .xe_swap => .xe_swap,
        .unknown => null,
    };
}

fn operationForNativeEvent(event: NativeEvent) Operation {
    return switch (event) {
        .application_created => .ensure_application,
        .window_created => .ensure_window,
        .layer_attached => .attach_metal_layer,
        .drawable_acquired => .acquire_drawable,
        .guest_frame_offered => .offer_guest_frame,
        .guest_frame_presented => .present_guest_frame,
        .diagnostic_frame_presented => .present_diagnostic_frame,
    };
}

fn ownerFor(operation: Operation, producer: Domain) Domain {
    return switch (operation) {
        .ensure_application, .ensure_window, .attach_metal_layer, .acquire_drawable => .cocoa_appkit,
        .bind_sdl_window, .pump_events => .sdl,
        .create_vulkan_surface, .create_swapchain, .issue_swap => if (producer == .rosette_runtime) .rosette_runtime else .xenia_vulkan,
        .publish_ring, .vd_swap, .xe_swap, .offer_guest_frame => .guest_title,
        .consume_pm4, .program_render_target, .submit_draw, .signal_completion => .xenia_host,
        .dispatch_completion => if (producer == .rosette_runtime) .rosette_runtime else .xenia_powerpc,
        .present_guest_frame, .present_diagnostic_frame => .rosette_runtime,
    };
}

fn producerMayState(operation: Operation, producer: Domain) bool {
    return switch (operation) {
        .ensure_application, .ensure_window, .attach_metal_layer, .acquire_drawable => producer == .cocoa_appkit,
        .bind_sdl_window, .pump_events => producer == .sdl,
        .create_vulkan_surface, .create_swapchain, .issue_swap => producer == .xenia_vulkan or producer == .rosette_runtime,
        .publish_ring, .vd_swap, .xe_swap, .offer_guest_frame => producer == .guest_title or producer == .xenia_powerpc,
        .consume_pm4, .program_render_target, .submit_draw, .signal_completion => producer == .xenia_host,
        .dispatch_completion => producer == .xenia_powerpc or producer == .rosette_runtime,
        .present_guest_frame, .present_diagnostic_frame => producer == .rosette_runtime,
    };
}

fn importDomainValid(function: Import, producer: Domain, space: AddressSpace) bool {
    const expected_space: AddressSpace = switch (function) {
        .vd_initialize_engines, .vd_set_graphics_interrupt_callback, .vd_swap, .xe_swap => .xenia_powerpc,
        .issue_swap, .sdl_create_window, .sdl_pump_events, .vk_create_metal_surface, .vk_create_swapchain, .vk_queue_present => .translated_x86,
    };
    if (space != expected_space) return false;
    return producer != .unknown;
}

fn symbolDomainValid(operation: Operation, producer: Domain, space: AddressSpace) bool {
    if (producer == .unknown) return false;
    return switch (operation) {
        .vd_swap, .xe_swap => space == .xenia_powerpc,
        else => space == .translated_x86 or space == .host_native,
    };
}

test "raw x86 bytes never resolve directly to Cocoa" {
    const result = resolve(.{
        .boundary = .{ .raw_instruction = .{ .rip = 0x1000, .opcode = 0x89 } },
        .producer = .rosette_runtime,
        .evidence = .completed_call,
        .source_identity = 1,
        .generation = 1,
        .sequence = 1,
    });
    try std.testing.expectEqual(Rejection.raw_instruction_has_no_graphics_meaning, result.rejected);
}

test "known API symbols resolve after their execution domain is known" {
    const result = resolve(.{
        .boundary = .{ .named_symbol = .{ .name = "VdSwap", .address = 0x8219_0000, .space = .xenia_powerpc } },
        .producer = .guest_title,
        .evidence = .intercepted_call,
        .source_identity = 9,
        .generation = 2,
        .sequence = 3,
    });
    try std.testing.expectEqual(Operation.vd_swap, result.admitted.operation);
    try std.testing.expectEqual(Domain.guest_title, result.admitted.expected_owner);
}

test "PowerPC callback is rejected by translated x86 executor" {
    const result = resolve(.{
        .boundary = .{ .structured_callback = .{
            .endpoint = .{ .address = 0x8219_51F8, .space = .xenia_powerpc, .owner = .xenia_powerpc, .evidence = .completed_call },
            .executor = .translated_x86,
        } },
        .producer = .rosette_runtime,
        .evidence = .completed_call,
        .source_identity = 1,
        .generation = 1,
        .sequence = 1,
    });
    try std.testing.expectEqual(Rejection.callback_domain_mismatch, result.rejected);
}

test "decoded PM4 draw is semantic work rather than an opcode guess" {
    const result = resolve(.{
        .boundary = .{ .decoded_pm4 = .{ .packet_class = .draw, .header = 0xC001_2D00 } },
        .producer = .xenia_host,
        .evidence = .observed_state,
        .source_identity = 4,
        .generation = 5,
        .sequence = 6,
    });
    try std.testing.expectEqual(Operation.submit_draw, result.admitted.operation);
}

test "parallel Vulkan stacks retain their actual owner" {
    const rosette = resolve(.{
        .boundary = .{ .intercepted_import = .{
            .function = .vk_create_metal_surface,
            .address = 0x1000,
            .space = .translated_x86,
        } },
        .producer = .rosette_runtime,
        .evidence = .completed_call,
        .source_identity = 0x1111,
        .generation = 2,
        .sequence = 3,
    });
    const xenia = resolve(.{
        .boundary = .{ .intercepted_import = .{
            .function = .vk_create_metal_surface,
            .address = 0x2000,
            .space = .translated_x86,
        } },
        .producer = .xenia_vulkan,
        .evidence = .completed_call,
        .source_identity = 0x2222,
        .generation = 2,
        .sequence = 3,
    });
    try std.testing.expectEqual(Domain.rosette_runtime, rosette.admitted.expected_owner);
    try std.testing.expectEqual(Domain.xenia_vulkan, xenia.admitted.expected_owner);
}

test "semantic intent observations are deduplicated by execution identity" {
    var ledger = Ledger{};
    const request = Request{
        .run = 9,
        .boundary = .{ .decoded_pm4 = .{ .packet_class = .draw, .header = 0xC001_2D00 } },
        .producer = .xenia_host,
        .evidence = .observed_state,
        .source_identity = 0x1FC0_0000,
        .generation = 3,
        .sequence = 7,
    };
    try std.testing.expectEqual(ObserveResult.admitted, ledger.observe(request));
    var heartbeat: usize = 0;
    while (heartbeat < 147) : (heartbeat += 1)
        try std.testing.expectEqual(ObserveResult.duplicate_observation, ledger.observe(request));
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 148), totals.observations);
    try std.testing.expectEqual(@as(u64, 1), totals.admitted);
    try std.testing.expectEqual(@as(u64, 147), totals.duplicates);
    try std.testing.expectEqual(@as(u64, 1), totals.operations[@intFromEnum(Operation.submit_draw)]);
}

test "one semantic identity cannot change from draw to swap" {
    var ledger = Ledger{};
    const draw = Request{
        .boundary = .{ .decoded_pm4 = .{ .packet_class = .draw, .header = 0xC001_2D00 } },
        .producer = .xenia_host,
        .evidence = .observed_state,
        .source_identity = 4,
        .generation = 5,
        .sequence = 6,
    };
    _ = ledger.observe(draw);
    var swap = draw;
    swap.boundary = .{ .decoded_pm4 = .{ .packet_class = .xe_swap, .header = 0xC001_3F00 } };
    swap.producer = .guest_title;
    try std.testing.expectEqual(ObserveResult.identity_conflict, ledger.observe(swap));
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().conflicts);
}

test "raw-machine-code rejection is journaled as a first-class fact" {
    var ledger = Ledger{};
    const result = ledger.observe(.{
        .boundary = .{ .raw_instruction = .{ .rip = 0x1000, .opcode = 0x89 } },
        .producer = .rosette_runtime,
        .evidence = .completed_call,
        .source_identity = 0x1000,
        .generation = 1,
        .sequence = 1,
    });
    try std.testing.expectEqual(ObserveResult.rejected, result);
    try std.testing.expectEqual(
        @as(u64, 1),
        ledger.summary().rejections[@intFromEnum(Rejection.raw_instruction_has_no_graphics_meaning)],
    );
}
