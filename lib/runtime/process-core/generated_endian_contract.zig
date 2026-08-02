//! Explicit endian conversion contracts plus the narrow recovery policy for
//! Xenia-generated code that observes a guest code address in the wrong byte
//! order.
//!
//! MOVBE itself must remain architecturally correct. Recovery is allowed only
//! when a later generated instruction proves that the byte-swapped result is
//! unusable while the original value is the exact comparison witness.

const std = @import("std");

pub const ByteWidth = enum(u8) {
    byte = 1,
    word = 2,
    dword = 4,
    qword = 8,

    pub fn fromByteCount(count: u8) ?ByteWidth {
        return switch (count) {
            1 => .byte,
            2 => .word,
            4 => .dword,
            8 => .qword,
            else => null,
        };
    }
};

pub const ByteOrder = enum {
    little,
    big,
};

pub fn maskForWidth(width: ByteWidth) u64 {
    return switch (width) {
        .byte => std.math.maxInt(u8),
        .word => std.math.maxInt(u16),
        .dword => std.math.maxInt(u32),
        .qword => std.math.maxInt(u64),
    };
}

/// Converts an integer representation between explicit byte orders. Values
/// wider than the selected contract width are truncated deliberately.
pub fn convert(value: u64, source: ByteOrder, destination: ByteOrder, width: ByteWidth) u64 {
    const narrowed = value & maskForWidth(width);
    if (source == destination or width == .byte) return narrowed;
    return switch (width) {
        .byte => narrowed,
        .word => @byteSwap(@as(u16, @truncate(narrowed))),
        .dword => @byteSwap(@as(u32, @truncate(narrowed))),
        .qword => @byteSwap(narrowed),
    };
}

pub fn swapped(value: u64, width: ByteWidth) u64 {
    return convert(value, .little, .big, width);
}

pub const ExecutionStamp = struct {
    present: bool = false,
    thread_handle: u64 = 0,
    scheduler_epoch: u64 = 0,
    step: u64 = 0,
};

pub const ExecutionRelation = enum {
    verified_same_scheduler_slice,
    unavailable,
    inconsistent_order,
    scheduler_switch_observed,
};

/// Memory events own their execution provenance. Thread identity alone is not
/// sufficient in Rosette because nested Xenia dispatch may temporarily expose
/// a worker or synthetic callback handle. A stable scheduler epoch plus strict
/// step ordering proves that no other guest context ran between the events.
pub fn executionRelation(load: ExecutionStamp, witness: ExecutionStamp, fault: ExecutionStamp) ExecutionRelation {
    if (!load.present or !witness.present or !fault.present) return .unavailable;
    if (!(load.step < witness.step and witness.step < fault.step)) return .inconsistent_order;
    if (load.scheduler_epoch != witness.scheduler_epoch or
        witness.scheduler_epoch != fault.scheduler_epoch)
    {
        return .scheduler_switch_observed;
    }
    return .verified_same_scheduler_slice;
}

pub const MovbeLoad = struct {
    execution: ExecutionStamp = .{},
    instruction_address: u64,
    source_address: u64,
    width_bytes: u8,
    destination_register: u8,
    raw_value: u64,
    swapped_value: u64,
    distance: u8,
};

pub const ComparisonWitness = struct {
    execution: ExecutionStamp = .{},
    instruction_address: u64,
    width_bytes: u8,
    compared_register: u8,
    memory_value: u64,
    distance: u8,
};

pub const Fault = struct {
    execution: ExecutionStamp = .{},
    address: u64,
    width_bytes: u8,
    base_register: u8,
    address_size_override: bool,
    base_only: bool,
    displacement: u64,
    generated_code: bool,
    original_value_readable: bool,
};

pub const Recovery = struct {
    address: u64,
    source_address: u64,
    producer_instruction: u64,
    witness_instruction: u64,
};

pub const RejectionReason = enum {
    not_generated_code,
    execution_provenance_unavailable,
    execution_order_invalid,
    cross_thread_evidence,
    fault_not_address_override_base_only,
    wrong_width,
    register_chain_mismatch,
    evidence_distance_invalid,
    swapped_value_mismatch,
    comparison_witness_mismatch,
    original_value_unreadable,
    byte_swap_relation_invalid,
    original_value_out_of_range,
};

pub const Assessment = union(enum) {
    recovery: Recovery,
    rejected: RejectionReason,
};

/// Classifies only the concrete Xenia stack-synchronization pattern:
///
///   movbe r32, [guest stack]
///   ...
///   cmp   r32, [host stackpoint]
///   je    matched
///   mov   r32, [r32]        // 0x67 address-sized guest-code probe
///
/// If the guest stack accidentally contains a host-endian code address, the
/// MOVBE result is byte-swapped and unmapped. The host stackpoint comparison
/// retains the original address and provides the required independent witness.
pub fn assess(load: MovbeLoad, witness: ComparisonWitness, fault: Fault) Assessment {
    if (!fault.generated_code) return .{ .rejected = .not_generated_code };
    switch (executionRelation(load.execution, witness.execution, fault.execution)) {
        .verified_same_scheduler_slice => {},
        .unavailable => return .{ .rejected = .execution_provenance_unavailable },
        .inconsistent_order => return .{ .rejected = .execution_order_invalid },
        .scheduler_switch_observed => return .{ .rejected = .cross_thread_evidence },
    }
    if (!fault.address_size_override or !fault.base_only or fault.displacement != 0) {
        return .{ .rejected = .fault_not_address_override_base_only };
    }
    if (fault.width_bytes != 4 or load.width_bytes != 4 or witness.width_bytes != 4) {
        return .{ .rejected = .wrong_width };
    }
    if (load.destination_register != fault.base_register or
        witness.compared_register != fault.base_register)
    {
        return .{ .rejected = .register_chain_mismatch };
    }
    if (load.distance == 0 or load.distance > 8 or
        witness.distance == 0 or witness.distance > 4 or
        witness.distance >= load.distance)
    {
        return .{ .rejected = .evidence_distance_invalid };
    }
    if (load.swapped_value != fault.address or load.raw_value == fault.address) {
        return .{ .rejected = .swapped_value_mismatch };
    }
    if (witness.memory_value != load.raw_value) {
        return .{ .rejected = .comparison_witness_mismatch };
    }
    if (!fault.original_value_readable) {
        return .{ .rejected = .original_value_unreadable };
    }
    if (@as(u32, @truncate(swapped(load.raw_value, .dword))) !=
        @as(u32, @truncate(fault.address)))
    {
        return .{ .rejected = .byte_swap_relation_invalid };
    }
    if (load.raw_value < 0x1000 or load.raw_value > std.math.maxInt(u32)) {
        return .{ .rejected = .original_value_out_of_range };
    }

    return .{ .recovery = .{
        .address = load.raw_value,
        .source_address = load.source_address,
        .producer_instruction = load.instruction_address,
        .witness_instruction = witness.instruction_address,
    } };
}

pub fn classify(load: MovbeLoad, witness: ComparisonWitness, fault: Fault) ?Recovery {
    return switch (assess(load, witness, fault)) {
        .recovery => |recovery| recovery,
        .rejected => null,
    };
}

test "accepts witnessed Xenia MOVBE return-address mismatch" {
    const recovery = classify(.{
        .execution = .{ .present = true, .thread_handle = 0x7FFF2120, .scheduler_epoch = 42, .step = 100 },
        .instruction_address = 0xA0008F69,
        .source_address = 0x3BD8EFD58,
        .width_bytes = 4,
        .destination_register = 3,
        .raw_value = 0x82582AD4,
        .swapped_value = 0xD42A5882,
        .distance = 4,
    }, .{
        .execution = .{ .present = true, .thread_handle = 0x7FFF2120, .scheduler_epoch = 42, .step = 103 },
        .instruction_address = 0xA0008F7E,
        .width_bytes = 4,
        .compared_register = 3,
        .memory_value = 0x82582AD4,
        .distance = 1,
    }, .{
        .execution = .{ .present = true, .thread_handle = 0xFFFFF90000000003, .scheduler_epoch = 42, .step = 105 },
        .address = 0xD42A5882,
        .width_bytes = 4,
        .base_register = 3,
        .address_size_override = true,
        .base_only = true,
        .displacement = 0,
        .generated_code = true,
        .original_value_readable = true,
    });

    try std.testing.expect(recovery != null);
    try std.testing.expectEqual(@as(u64, 0x82582AD4), recovery.?.address);
}

test "rejects an unwitnessed or cross-thread endian guess" {
    const load = MovbeLoad{
        .execution = .{ .present = true, .thread_handle = 1, .scheduler_epoch = 10, .step = 100 },
        .instruction_address = 0xA0008F69,
        .source_address = 0x3BD8EFD58,
        .width_bytes = 4,
        .destination_register = 3,
        .raw_value = 0x82582AD4,
        .swapped_value = 0xD42A5882,
        .distance = 4,
    };
    const witness = ComparisonWitness{
        .execution = .{ .present = true, .thread_handle = 1, .scheduler_epoch = 10, .step = 103 },
        .instruction_address = 0xA0008F7E,
        .width_bytes = 4,
        .compared_register = 3,
        .memory_value = 0x82582AD0,
        .distance = 1,
    };
    const fault = Fault{
        .execution = .{ .present = true, .thread_handle = 1, .scheduler_epoch = 10, .step = 105 },
        .address = 0xD42A5882,
        .width_bytes = 4,
        .base_register = 3,
        .address_size_override = true,
        .base_only = true,
        .displacement = 0,
        .generated_code = true,
        .original_value_readable = true,
    };

    try std.testing.expect(classify(load, witness, fault) == null);
    var cross_thread = fault;
    cross_thread.execution.scheduler_epoch = 11;
    try std.testing.expect(classify(load, .{
        .execution = witness.execution,
        .instruction_address = witness.instruction_address,
        .width_bytes = witness.width_bytes,
        .compared_register = witness.compared_register,
        .memory_value = load.raw_value,
        .distance = witness.distance,
    }, cross_thread) == null);
    try std.testing.expectEqual(
        RejectionReason.cross_thread_evidence,
        assess(load, .{
            .execution = witness.execution,
            .instruction_address = witness.instruction_address,
            .width_bytes = witness.width_bytes,
            .compared_register = witness.compared_register,
            .memory_value = load.raw_value,
            .distance = witness.distance,
        }, cross_thread).rejected,
    );
}

test "reports an unreadable unswapped destination separately" {
    const result = assess(.{
        .execution = .{ .present = true, .scheduler_epoch = 10, .step = 100 },
        .instruction_address = 0xA0008F69,
        .source_address = 0x3BD8EFD58,
        .width_bytes = 4,
        .destination_register = 3,
        .raw_value = 0x82582AD4,
        .swapped_value = 0xD42A5882,
        .distance = 4,
    }, .{
        .execution = .{ .present = true, .scheduler_epoch = 10, .step = 103 },
        .instruction_address = 0xA0008F7E,
        .width_bytes = 4,
        .compared_register = 3,
        .memory_value = 0x82582AD4,
        .distance = 1,
    }, .{
        .execution = .{ .present = true, .scheduler_epoch = 10, .step = 105 },
        .address = 0xD42A5882,
        .width_bytes = 4,
        .base_register = 3,
        .address_size_override = true,
        .base_only = true,
        .displacement = 0,
        .generated_code = true,
        .original_value_readable = false,
    });
    try std.testing.expectEqual(
        RejectionReason.original_value_unreadable,
        result.rejected,
    );
}

test "explicit endian conversion is width-bounded and involutive" {
    const cases = [_]struct { value: u64, width: ByteWidth, expected: u64 }{
        .{ .value = 0xAB, .width = .byte, .expected = 0xAB },
        .{ .value = 0x1234, .width = .word, .expected = 0x3412 },
        .{ .value = 0x82582AD4, .width = .dword, .expected = 0xD42A5882 },
        .{ .value = 0x0123456789ABCDEF, .width = .qword, .expected = 0xEFCDAB8967452301 },
    };
    for (cases) |case| {
        const converted = convert(case.value, .big, .little, case.width);
        try std.testing.expectEqual(case.expected, converted);
        try std.testing.expectEqual(case.value & maskForWidth(case.width), convert(converted, .little, .big, case.width));
    }
    try std.testing.expectEqual(@as(?ByteWidth, null), ByteWidth.fromByteCount(3));
}

test "scheduler epoch proves one execution slice despite handle aliases" {
    try std.testing.expectEqual(
        ExecutionRelation.verified_same_scheduler_slice,
        executionRelation(
            .{ .present = true, .thread_handle = 0x7FFF2120, .scheduler_epoch = 77, .step = 100 },
            .{ .present = true, .thread_handle = 0x7FFF2120, .scheduler_epoch = 77, .step = 103 },
            .{ .present = true, .thread_handle = 0xFFFFF90000000003, .scheduler_epoch = 77, .step = 105 },
        ),
    );
    try std.testing.expectEqual(
        ExecutionRelation.scheduler_switch_observed,
        executionRelation(
            .{ .present = true, .scheduler_epoch = 77, .step = 100 },
            .{ .present = true, .scheduler_epoch = 78, .step = 103 },
            .{ .present = true, .scheduler_epoch = 78, .step = 105 },
        ),
    );
}
