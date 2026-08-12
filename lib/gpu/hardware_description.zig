const std = @import("std");
const device_tree = @import("device_tree");
const api = @import("api.zig");
const backend = @import("backend.zig");

/// Converts an authoritative backend description into Rosette-native hardware
/// facts. This adapter contains no backend operations and cannot create or
/// mutate guest GPU state.
pub fn fromBackend(description: *const backend.Description) !device_tree.Tree {
    var tree = try device_tree.Tree.init("rosette-gpu-runtime");
    try tree.setProperty("/", "gpu-api-version", .{ .unsigned = api.api_version }, .backend_negotiation, .read_only);

    _ = try tree.addNode("/gpu", .gpu, .okay, .backend_negotiation);
    try setText(&tree, "/gpu", "backend", @tagName(description.kind));
    try tree.setProperty("/gpu", "capability-mask-low", .{ .unsigned = description.provided.low }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu", "capability-mask-high", .{ .unsigned = description.provided.high }, .backend_negotiation, .read_only);

    _ = try tree.addNode("/gpu/adapter", .adapter, .okay, .backend_negotiation);
    try setText(&tree, "/gpu/adapter", "name", description.adapterName());
    try tree.setProperty("/gpu/adapter", "buffer-alignment", .{ .unsigned = description.buffer_alignment }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/adapter", "image-alignment", .{ .unsigned = description.image_alignment }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/adapter", "guest-mapping-alignment", .{ .unsigned = description.guest_mapping_alignment }, .backend_negotiation, .read_only);

    _ = try tree.addNode("/gpu/queues", .queues, .okay, .backend_negotiation);
    try tree.setProperty("/gpu/queues", "graphics", .{ .unsigned = description.graphics_queue_count }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/queues", "compute", .{ .unsigned = description.compute_queue_count }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/queues", "transfer", .{ .unsigned = description.transfer_queue_count }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/queues", "sparse", .{ .unsigned = description.sparse_queue_count }, .backend_negotiation, .read_only);

    _ = try tree.addNode("/gpu/memory", .memory, .okay, .backend_negotiation);
    try tree.setProperty("/gpu/memory", "host-visible-heap-bytes", .{ .unsigned = description.host_visible_heap_bytes }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/memory", "device-local-heap-bytes", .{ .unsigned = description.device_local_heap_bytes }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/memory", "sparse-buffer-block-bytes", .{ .unsigned = description.sparse_buffer_block_bytes }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/memory", "sparse-image-block-bytes", .{ .unsigned = description.sparse_image_block_bytes }, .backend_negotiation, .read_only);

    _ = try tree.addNode("/gpu/limits", .runtime, .okay, .backend_negotiation);
    try tree.setProperty("/gpu/limits", "maximum-buffer-bytes", .{ .unsigned = description.maximum_buffer_bytes }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/limits", "maximum-image-dimension-2d", .{ .unsigned = description.maximum_image_dimension_2d }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/limits", "maximum-image-array-layers", .{ .unsigned = description.maximum_image_array_layers }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/limits", "maximum-push-constant-bytes", .{ .unsigned = description.maximum_push_constant_bytes }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/limits", "timestamp-period-picoseconds", .{ .unsigned = description.timestamp_period_picoseconds }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/limits", "maximum-timeline-value-difference", .{ .unsigned = description.maximum_timeline_value_difference }, .backend_negotiation, .read_only);

    _ = try tree.addNode("/gpu/surface", .surface, .okay, .backend_negotiation);
    try tree.setProperty("/gpu/surface", "minimum-image-count", .{ .unsigned = description.surface.minimum_image_count }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/surface", "maximum-image-count", .{ .unsigned = description.surface.maximum_image_count }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/surface", "minimum-width", .{ .unsigned = description.surface.minimum_width }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/surface", "minimum-height", .{ .unsigned = description.surface.minimum_height }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/surface", "maximum-width", .{ .unsigned = description.surface.maximum_width }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/surface", "maximum-height", .{ .unsigned = description.surface.maximum_height }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/surface", "present-mode-mask", .{ .unsigned = description.surface.present_mode_mask }, .backend_negotiation, .read_only);
    try tree.setProperty("/gpu/surface", "supported-usage", .{ .unsigned = description.surface.supported_usage }, .backend_negotiation, .read_only);

    _ = try tree.addNode("/gpu/capabilities", .runtime, .okay, .backend_negotiation);
    for (0..api.capability_count) |index| {
        const capability: api.Capability = @enumFromInt(index);
        try tree.setProperty(
            "/gpu/capabilities",
            api.capabilityName(capability),
            .{ .boolean = description.provided.contains(capability) },
            .backend_negotiation,
            .read_only,
        );
    }

    try tree.validate();
    return tree;
}

fn setText(tree: *device_tree.Tree, path: []const u8, name: []const u8, text: []const u8) !void {
    try tree.setProperty(path, name, try device_tree.Value.fromText(text), .backend_negotiation, .read_only);
}

test "backend description becomes immutable backend-neutral facts" {
    var description = backend.Description{
        .kind = .vulkan,
        .provided = api.CapabilitySet.from(&.{ .physical_adapter, .queue_graphics, .buffer }),
        .graphics_queue_count = 1,
        .buffer_alignment = 256,
        .guest_mapping_alignment = 4096,
    };
    description.setAdapterName("Observed adapter");
    const tree = try fromBackend(&description);
    try std.testing.expect(tree.property("/gpu/capabilities", "physical_adapter").?.value.boolean);
    try std.testing.expect(!tree.property("/gpu/capabilities", "presentation").?.value.boolean);
    try std.testing.expectEqual(@as(u64, 4096), tree.property("/gpu/adapter", "guest-mapping-alignment").?.value.unsigned);
    try std.testing.expectEqual(device_tree.Mutability.read_only, tree.property("/gpu", "backend").?.mutability);
}
