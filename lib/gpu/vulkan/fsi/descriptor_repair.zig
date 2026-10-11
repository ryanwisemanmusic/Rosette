//! Narrow recovery helpers for Xenia's shared-memory / EDRAM / ZPD FSI set.
//!
//! Xenia initializes that three-binding set with a real EDRAM buffer and a
//! small ZPD counter sink. In `VulkanCommandProcessor::SetupContext` the
//! sink's `VkDescriptorBufferInfo` is declared inside the
//! `if (edram_fragment_shader_interlock)` block, and `vkUpdateDescriptorSets`
//! runs after that block ends. Reading a local after its lifetime is
//! undefined, and clang deleted the stores: in the shipped xenia_canary.exe
//! (0x140a32188) write 2 points at 0x80(%rsp), which nothing in the function
//! writes, while the EDRAM info at 0x5a8(%rsp) is stored normally. Rosette
//! therefore reads whatever the stack held, usually a null buffer with an
//! arbitrary offset and range.
//!
//! Refusing that write dropped the whole call, so the FSI shaders never had
//! their shared-memory or EDRAM bindings: every draw wrote nowhere and every
//! resolve read zeros, which made the picture exactly black. The recovery
//! below is limited to that exact descriptor-set shape and substitutes a
//! zeroed sink of Xenia's own size, which is what Xenia meant to bind.

const abi = @import("../abi.zig");

/// Xenia currently sizes its temporary FSI ZPD counter sink from
/// `4 * kZPDQueryPoolCapacity`, where the capacity is 8192.
pub const XENIA_ZPD_COUNTER_SINK_BYTES: u64 = 4 * 8192;

pub fn isExpectedZpdSinkRange(offset: u64, range: u64) bool {
    return offset == 0 and range == XENIA_ZPD_COUNTER_SINK_BYTES;
}

pub fn isSharedMemoryEdramZpdSetUpdate(writes: []const abi.WriteDescriptorSet, set: u64) bool {
    if (writes.len != 3 or set == 0) return false;
    for (writes, 0..) |write, binding| {
        // Binding 0 is the shared memory, split into
        // `shared_memory_binding_count` descriptors on hosts with a small
        // maxStorageBufferRange; the EDRAM and the counter are one each.
        const count_ok = if (binding == 0) write.descriptor_count >= 1 else write.descriptor_count == 1;
        if (write.dst_set != set or
            write.dst_binding != binding or
            !count_ok or
            write.descriptor_type != abi.DESCRIPTOR_TYPE_STORAGE_BUFFER or
            write.p_next != null)
        {
            return false;
        }
    }
    return true;
}

/// Whether the guest's sink info for binding 2 of the FSI set must be
/// replaced. Only an info that is exactly Xenia's sink (a buffer the bridge
/// knows, offset 0, range 32768) is taken as written; anything else in this
/// call shape is the dead stack slot described above, and binding a random
/// handle or range from it could make the driver read out of bounds.
pub fn zpdSinkInfoNeedsRepair(buffer_known: bool, offset: u64, range: u64) bool {
    return !(buffer_known and isExpectedZpdSinkRange(offset, range));
}

pub fn isZpdSinkDescriptor(write: abi.WriteDescriptorSet, set: u64) bool {
    return write.dst_set == set and
        write.dst_binding == 2 and
        write.descriptor_count == 1 and
        write.descriptor_type == abi.DESCRIPTOR_TYPE_STORAGE_BUFFER and
        write.p_next == null;
}

pub fn isCompatibleSinkBuffer(
    descriptor_range: u64,
    candidate_size: u64,
    candidate_usage: u32,
    memory_bound: bool,
) bool {
    return descriptor_range != 0 and
        descriptor_range != abi.WHOLE_SIZE and
        candidate_size == descriptor_range and
        candidate_usage & abi.BUFFER_USAGE_STORAGE_BUFFER_BIT != 0 and
        memory_bound;
}

test "FSI ZPD recovery recognizes only Xenia's exact three-binding storage set" {
    var writes = [_]abi.WriteDescriptorSet{
        .{ .dst_set = 0x51, .dst_binding = 0, .descriptor_count = 1, .descriptor_type = abi.DESCRIPTOR_TYPE_STORAGE_BUFFER },
        .{ .dst_set = 0x51, .dst_binding = 1, .descriptor_count = 1, .descriptor_type = abi.DESCRIPTOR_TYPE_STORAGE_BUFFER },
        .{ .dst_set = 0x51, .dst_binding = 2, .descriptor_count = 1, .descriptor_type = abi.DESCRIPTOR_TYPE_STORAGE_BUFFER },
    };
    try @import("std").testing.expect(isSharedMemoryEdramZpdSetUpdate(&writes, 0x51));
    try @import("std").testing.expect(isZpdSinkDescriptor(writes[2], 0x51));

    writes[2].dst_binding = 3;
    try @import("std").testing.expect(!isSharedMemoryEdramZpdSetUpdate(&writes, 0x51));
    try @import("std").testing.expect(!isZpdSinkDescriptor(writes[2], 0x51));
    writes[2].dst_binding = 2;
    writes[1].descriptor_type = abi.DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    try @import("std").testing.expect(!isSharedMemoryEdramZpdSetUpdate(&writes, 0x51));
}

test "FSI ZPD replacement requires an exact-size bound storage buffer" {
    try @import("std").testing.expect(isCompatibleSinkBuffer(
        4096,
        4096,
        abi.BUFFER_USAGE_STORAGE_BUFFER_BIT,
        true,
    ));
    try @import("std").testing.expect(!isCompatibleSinkBuffer(
        4096,
        8192,
        abi.BUFFER_USAGE_STORAGE_BUFFER_BIT,
        true,
    ));
    try @import("std").testing.expect(!isCompatibleSinkBuffer(
        4096,
        4096,
        abi.BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        true,
    ));
    try @import("std").testing.expect(!isCompatibleSinkBuffer(
        4096,
        4096,
        abi.BUFFER_USAGE_STORAGE_BUFFER_BIT,
        false,
    ));
    try @import("std").testing.expect(!isCompatibleSinkBuffer(
        abi.WHOLE_SIZE,
        4096,
        abi.BUFFER_USAGE_STORAGE_BUFFER_BIT,
        true,
    ));
}

test "FSI ZPD repair is pinned to Xenia's current 8192-counter sink range" {
    try @import("std").testing.expect(isExpectedZpdSinkRange(0, 32_768));
    try @import("std").testing.expect(!isExpectedZpdSinkRange(4, 32_768));
    try @import("std").testing.expect(!isExpectedZpdSinkRange(0, 16_384));
}

test "the dead-stack sink info is repaired whatever the stack held, and Xenia's real sink is kept" {
    const testing = @import("std").testing;
    // What the shipped exe leaves: a null buffer with any offset and range.
    try testing.expect(zpdSinkInfoNeedsRepair(false, 0, 0));
    try testing.expect(zpdSinkInfoNeedsRepair(false, 0, XENIA_ZPD_COUNTER_SINK_BYTES));
    try testing.expect(zpdSinkInfoNeedsRepair(false, 0x7ff6_1234, 0x1_0000_0000));
    // Stale stack bytes that happen to name a live buffer are still garbage
    // unless the offset and range are exactly the sink's.
    try testing.expect(zpdSinkInfoNeedsRepair(true, 0, abi.WHOLE_SIZE));
    try testing.expect(zpdSinkInfoNeedsRepair(true, 64, XENIA_ZPD_COUNTER_SINK_BYTES));
    // A build where the stores survive binds Xenia's own sink untouched.
    try testing.expect(!zpdSinkInfoNeedsRepair(true, 0, XENIA_ZPD_COUNTER_SINK_BYTES));
}

test "the FSI set shape accepts shared memory split across several descriptors" {
    const writes = [_]abi.WriteDescriptorSet{
        .{ .dst_set = 0x51, .dst_binding = 0, .descriptor_count = 4, .descriptor_type = abi.DESCRIPTOR_TYPE_STORAGE_BUFFER },
        .{ .dst_set = 0x51, .dst_binding = 1, .descriptor_count = 1, .descriptor_type = abi.DESCRIPTOR_TYPE_STORAGE_BUFFER },
        .{ .dst_set = 0x51, .dst_binding = 2, .descriptor_count = 1, .descriptor_type = abi.DESCRIPTOR_TYPE_STORAGE_BUFFER },
    };
    try @import("std").testing.expect(isSharedMemoryEdramZpdSetUpdate(&writes, 0x51));
    var two_edram = writes;
    two_edram[1].descriptor_count = 2;
    try @import("std").testing.expect(!isSharedMemoryEdramZpdSetUpdate(&two_edram, 0x51));
}
