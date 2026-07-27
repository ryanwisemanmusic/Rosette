const std = @import("std");

/// Broad provenance classes deliberately describe memory, not applications or
/// symbols.  Initializer retries are only safe for pointer slots whose storage
/// is expected to be populated by another initializer or by the loader.
pub const SourceClass = enum {
    writable_image_data,
    import_pointer,
    other,
};

pub const Evidence = struct {
    initializer_active: bool,
    fault_address: u64,
    access_width: u8,
    store_uses_base_register: bool,
    producer_is_pointer_load: bool,
    producer_destination_matches_base: bool,
    producer_source_address: u64,
    producer_source_value: u64,
    producer_distance: usize,
    source_readable: bool,
    source_writable: bool,
    source_class: SourceClass,
};

pub const Decision = enum {
    terminate,
    defer_and_retry,
};

/// Classifies a null store as an initializer ordering dependency only when the
/// complete dataflow is proven: a nearby pointer-sized load from writable
/// loader/image storage produced the base register used by the faulting store.
/// The caller must roll back the initializer before retrying it.
pub fn classify(evidence: Evidence) Decision {
    if (!evidence.initializer_active) return .terminate;
    if (evidence.fault_address >= 0x1000 or evidence.access_width != @sizeOf(u64)) return .terminate;
    if (!evidence.store_uses_base_register) return .terminate;
    if (!evidence.producer_is_pointer_load or !evidence.producer_destination_matches_base) return .terminate;
    if (evidence.producer_source_address < 0x1000 or evidence.producer_source_value != 0) return .terminate;
    if (evidence.producer_distance == 0 or evidence.producer_distance > 8) return .terminate;
    if (!evidence.source_readable or !evidence.source_writable) return .terminate;
    return switch (evidence.source_class) {
        .writable_image_data, .import_pointer => .defer_and_retry,
        .other => .terminate,
    };
}

test "writable image pointer dependency is deferred without symbol knowledge" {
    const decision = classify(.{
        .initializer_active = true,
        .fault_address = 0,
        .access_width = 8,
        .store_uses_base_register = true,
        .producer_is_pointer_load = true,
        .producer_destination_matches_base = true,
        .producer_source_address = 0x196fff0,
        .producer_source_value = 0,
        .producer_distance = 3,
        .source_readable = true,
        .source_writable = true,
        .source_class = .writable_image_data,
    });
    try std.testing.expectEqual(Decision.defer_and_retry, decision);
}

test "heap null fields and incomplete dataflow remain fatal" {
    const base = Evidence{
        .initializer_active = true,
        .fault_address = 0,
        .access_width = 8,
        .store_uses_base_register = true,
        .producer_is_pointer_load = true,
        .producer_destination_matches_base = true,
        .producer_source_address = 0x4000,
        .producer_source_value = 0,
        .producer_distance = 2,
        .source_readable = true,
        .source_writable = true,
        .source_class = .other,
    };
    try std.testing.expectEqual(Decision.terminate, classify(base));

    var missing_producer = base;
    missing_producer.source_class = .writable_image_data;
    missing_producer.producer_is_pointer_load = false;
    try std.testing.expectEqual(Decision.terminate, classify(missing_producer));
}

test "stale producer evidence outside the local dataflow window is rejected" {
    try std.testing.expectEqual(Decision.terminate, classify(.{
        .initializer_active = true,
        .fault_address = 8,
        .access_width = 8,
        .store_uses_base_register = true,
        .producer_is_pointer_load = true,
        .producer_destination_matches_base = true,
        .producer_source_address = 0x9000,
        .producer_source_value = 0,
        .producer_distance = 9,
        .source_readable = true,
        .source_writable = true,
        .source_class = .import_pointer,
    }));
}
