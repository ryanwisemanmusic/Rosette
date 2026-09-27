//! Store-buffer boundaries for translated guest memory helpers.
//!
//! In cooperative mode a TLB hit can resume direct memory access immediately
//! after a helper, so helpers must publish queued stores before returning.
//!
//! Parallel mode fills each executor's own TLB (`parallel_direct_tlb`) and
//! binds no store queue at all: a hit is one LDAR or STLR on the host page,
//! and a helper's scalar store goes straight to memory with release
//! ordering, so there is never a queued store for a direct access to miss
//! and nothing for these drains to publish. With the direct route switched
//! off (`ROSETTE_PE64_PARALLEL_TLB=0`) the per-thread queue returns and every
//! translated access takes the coordinated helper; draining at each scalar
//! helper would then defeat the queue, since loads already forward from it
//! and scalar stores stay visible at the normal TSO drain boundaries. A
//! vector bulk write still drains older scalar stores first because it
//! writes directly under the coordinator rather than queueing its bytes.

pub const Mode = enum {
    cooperative_direct_tlb,
    parallel_coordinated_helpers,
};

pub const BoundaryPolicy = struct {
    drain_before_read: bool,
    drain_before_write: bool,
    drain_after_write: bool,
    /// Vector helpers issue one coordinated bulk store instead of buffering
    /// scalar lanes, so they must publish older scalar stores first.
    drain_before_vector_write: bool,
};

pub inline fn policy(mode: Mode) BoundaryPolicy {
    return switch (mode) {
        .cooperative_direct_tlb => .{
            .drain_before_read = true,
            .drain_before_write = true,
            .drain_after_write = true,
            .drain_before_vector_write = true,
        },
        .parallel_coordinated_helpers => .{
            .drain_before_read = false,
            .drain_before_write = false,
            .drain_after_write = false,
            .drain_before_vector_write = true,
        },
    };
}

test "cooperative helper boundaries publish before direct TLB resumes" {
    const result = policy(.cooperative_direct_tlb);
    try @import("std").testing.expect(result.drain_before_read);
    try @import("std").testing.expect(result.drain_before_write);
    try @import("std").testing.expect(result.drain_after_write);
    try @import("std").testing.expect(result.drain_before_vector_write);
}

test "parallel helper boundaries keep buffered stores for forwarding and TSO drains" {
    const result = policy(.parallel_coordinated_helpers);
    try @import("std").testing.expect(!result.drain_before_read);
    try @import("std").testing.expect(!result.drain_before_write);
    try @import("std").testing.expect(!result.drain_after_write);
    try @import("std").testing.expect(result.drain_before_vector_write);
}
