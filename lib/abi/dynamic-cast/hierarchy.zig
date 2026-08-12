//! Enumeration of the base-class subobject graph of a live guest object.
//!
//! libc++abi answers a `dynamic_cast` with a pruned recursive search that
//! folds "walk the graph" and "decide the cast" into one traversal. This file
//! separates them: it enumerates the graph once, recording for every subobject
//! its address and whether *some* wholly public path reaches it, and leaves the
//! decision to `resolver.zig`. The split costs a little work on hierarchies
//! that the pruned search would have abandoned early, and buys the thing the
//! pruned search cannot express — the difference between "the destination is
//! not in this graph" and "this graph could not be read to the end".
//!
//! That distinction is the whole point. A cast that returns null because the
//! object genuinely is not of the destination type is the language working
//! correctly. A cast that returns null because a base pointer was unreadable is
//! a guess wearing the same clothes, and a caller branching on it is branching
//! on the guess.

const std = @import("std");
const rtti = @import("type_info.zig");

/// Distinct subobjects tracked per walk. A class with more than this many base
/// subobjects exists in principle; in practice exceeding it means the walk left
/// the hierarchy, and the graph is marked truncated so no negative is inferred
/// from it. The bound is also a stack budget: two of these are live at once
/// during a cast, on the thread running the interpreter.
pub const max_nodes: usize = 64;

/// Inheritance depth bound. Cycles cannot occur in a well-formed hierarchy, but
/// a misread base pointer can manufacture one.
pub const max_depth: u16 = 32;

pub const Node = struct {
    type_info: u64 = 0,
    object: u64 = 0,
    /// Whether at least one path from the walk's root to this subobject is
    /// public at every step.
    public: bool = false,
    depth: u16 = 0,
};

pub const Candidate = struct {
    type_info: u64,
    object: u64,
    public: bool,
};

pub const Graph = struct {
    nodes: [max_nodes]Node = [_]Node{.{}} ** max_nodes,
    count: usize = 0,
    queue: [max_nodes * 2]u32 = undefined,
    queue_len: usize = 0,
    /// An edge could not be followed: a base pointer was unreadable, or a
    /// record could not be classified. The graph is a subset of the truth.
    incomplete: bool = false,
    /// A bound was hit. Also a subset of the truth, and reported separately
    /// because the two call for different responses.
    truncated: bool = false,

    pub fn complete(self: *const Graph) bool {
        return !self.incomplete and !self.truncated;
    }

    fn enqueue(self: *Graph, index: u32) void {
        if (self.queue_len == self.queue.len) {
            self.truncated = true;
            return;
        }
        self.queue[self.queue_len] = index;
        self.queue_len += 1;
    }

    fn push(self: *Graph, type_info: u64, object: u64, is_public: bool, depth: u16) void {
        for (self.nodes[0..self.count], 0..) |*node, index| {
            if (node.type_info != type_info or node.object != object) continue;
            if (depth < node.depth) node.depth = depth;
            // A subobject reachable both publicly and privately is publicly
            // reachable; the more public answer wins and the node is revisited
            // so its bases inherit the upgrade.
            if (is_public and !node.public) {
                node.public = true;
                self.enqueue(@intCast(index));
            }
            return;
        }
        if (self.count == max_nodes) {
            self.truncated = true;
            return;
        }
        self.nodes[self.count] = .{
            .type_info = type_info,
            .object = object,
            .public = is_public,
            .depth = depth,
        };
        self.enqueue(@intCast(self.count));
        self.count += 1;
    }
};

/// Enumerate every base subobject of `(root_type, root_object)`.
pub fn build(
    graph: *Graph,
    reader: *rtti.Reader,
    state: anytype,
    root_type: u64,
    root_object: u64,
) void {
    graph.count = 0;
    graph.queue_len = 0;
    graph.incomplete = false;
    graph.truncated = false;
    if (root_type == 0) {
        graph.incomplete = true;
        return;
    }

    graph.push(root_type, root_object, true, 0);
    var head: usize = 0;
    while (head < graph.queue_len) : (head += 1) {
        const node = graph.nodes[graph.queue[head]];
        if (node.depth >= max_depth) {
            graph.truncated = true;
            continue;
        }
        expand(graph, reader, state, node);
    }
}

fn expand(graph: *Graph, reader: *rtti.Reader, state: anytype, node: Node) void {
    const bases = reader.basesOf(state, node.type_info) orelse {
        graph.incomplete = true;
        return;
    };
    var index: u32 = 0;
    while (index < bases.count) : (index += 1) {
        const base = reader.baseAt(state, node.type_info, bases, index) orelse {
            graph.incomplete = true;
            continue;
        };
        const base_object = subobjectAddress(state, node.object, base) orelse {
            graph.incomplete = true;
            continue;
        };
        graph.push(
            base.type_info,
            base_object,
            node.public and base.is_public,
            node.depth + 1,
        );
    }
}

fn subobjectAddress(state: anytype, object: u64, base: rtti.Base) ?u64 {
    if (!base.is_virtual) return rtti.addSigned(object, base.offset);
    // A virtual base's offset lives in the derived object's vtable, so it is
    // only knowable from a live object — which is exactly why this walk starts
    // from one rather than from the type graph alone.
    const vtable = rtti.readPointer(state, object) orelse return null;
    const dynamic_offset = rtti.readSigned(state, rtti.addSigned(vtable, base.offset)) orelse return null;
    return rtti.addSigned(object, dynamic_offset);
}

/// Whether a wholly public path reaches the subobject `(type_info, object)`
/// from the walk's root, or null when the graph does not contain it at all.
pub fn publicityOf(
    graph: *const Graph,
    state: anytype,
    type_info: u64,
    object: u64,
    use_strcmp: bool,
) ?bool {
    var found: ?bool = null;
    for (graph.nodes[0..graph.count]) |node| {
        if (node.object != object) continue;
        if (!rtti.sameType(state, node.type_info, type_info, use_strcmp)) continue;
        found = (found orelse false) or node.public;
    }
    return found;
}

/// Every distinct subobject *address* in the graph whose type is `type_info`.
///
/// Addresses, not nodes: two records naming one class at one address are one
/// subobject, and counting them twice would report an ambiguity the program
/// does not have.
pub fn collectByType(
    graph: *const Graph,
    state: anytype,
    type_info: u64,
    use_strcmp: bool,
    out: []Candidate,
) usize {
    var length: usize = 0;
    for (graph.nodes[0..graph.count]) |node| {
        if (!rtti.sameType(state, node.type_info, type_info, use_strcmp)) continue;
        var merged = false;
        for (out[0..length]) |*existing| {
            if (existing.object != node.object) continue;
            existing.public = existing.public or node.public;
            merged = true;
            break;
        }
        if (merged) continue;
        if (length == out.len) return length;
        out[length] = .{ .type_info = node.type_info, .object = node.object, .public = node.public };
        length += 1;
    }
    return length;
}

/// Whether `catch_type` is a public base of `thrown_type` — the Itanium rule
/// for binding a thrown object to a typed catch clause. Unlike a cast this
/// needs no live object: no virtual base offset is consulted, so the type graph
/// alone answers it.
pub fn hasPublicBase(
    reader: *rtti.Reader,
    state: anytype,
    type_info: u64,
    catch_type: u64,
    public_path: bool,
    depth: u16,
    use_strcmp: bool,
) bool {
    if (depth > max_depth or type_info == 0) return false;
    if (public_path and rtti.sameType(state, type_info, catch_type, use_strcmp)) return true;

    const bases = reader.basesOf(state, type_info) orelse return false;
    var index: u32 = 0;
    while (index < bases.count) : (index += 1) {
        const base = reader.baseAt(state, type_info, bases, index) orelse continue;
        if (hasPublicBase(
            reader,
            state,
            base.type_info,
            catch_type,
            public_path and base.is_public,
            depth + 1,
            use_strcmp,
        )) return true;
    }
    return false;
}

const testing = @import("testing.zig");

/// Two bases, one of them reached only through a private edge.
fn buildPrivateBaseFixture(state: *testing.State) void {
    const rtti_vtable = 0x400;
    state.writeTypeInfo(0x100, rtti_vtable, 0x700, "7Derived"); // vmi
    state.writeTypeInfo(0x200, rtti_vtable, 0x720, "6Public");
    state.writeTypeInfo(0x280, rtti_vtable, 0x740, "7Private");
    state.writeVmi(0x100, 0, &.{
        .{ .type_info = 0x200, .offset = 0x00, .flags = rtti.base_public },
        .{ .type_info = 0x280, .offset = 0x10, .flags = 0 },
    });
}

test "the graph records a private edge as a subobject that is not publicly reachable" {
    var state = testing.State{};
    buildPrivateBaseFixture(&state);

    var reader = rtti.Reader{};
    reader.observe(&state, 0x100);
    var graph = Graph{};
    build(&graph, &reader, &state, 0x100, 0x1000);

    try std.testing.expect(graph.complete());
    try std.testing.expectEqual(@as(usize, 3), graph.count);
    try std.testing.expectEqual(@as(?bool, true), publicityOf(&graph, &state, 0x200, 0x1000, false));
    try std.testing.expectEqual(@as(?bool, false), publicityOf(&graph, &state, 0x280, 0x1010, false));
    // Absent is not the same answer as present-but-private.
    try std.testing.expectEqual(@as(?bool, null), publicityOf(&graph, &state, 0x280, 0x1000, false));
}

test "an unreadable base marks the graph incomplete instead of ending the walk quietly" {
    var state = testing.State{};
    const rtti_vtable = 0x400;
    state.writeTypeInfo(0x100, rtti_vtable, 0x700, "7Derived");
    state.writeVmi(0x100, 0, &.{
        .{ .type_info = 0xdead_0000, .offset = 0, .flags = rtti.base_public },
    });

    var reader = rtti.Reader{};
    reader.observe(&state, 0x100);
    var graph = Graph{};
    build(&graph, &reader, &state, 0x100, 0x1000);

    // The base pointer is outside the fake guest's memory, so the record for
    // 0x100 cannot even be classified as multiple inheritance.
    try std.testing.expect(!graph.complete());
}

test "a subobject reached publicly and privately is publicly reachable" {
    var state = testing.State{};
    const rtti_vtable = 0x400;
    state.writeTypeInfo(0x100, rtti_vtable, 0x700, "4Most"); // vmi, two bases
    state.writeTypeInfo(0x200, rtti_vtable, 0x720, "5Left"); // si -> shared
    state.writeTypeInfo(0x280, rtti_vtable, 0x740, "6Right"); // si -> shared
    state.writeTypeInfo(0x300, rtti_vtable, 0x760, "6Shared");
    state.writeVmi(0x100, 0, &.{
        // The left edge is private, the right edge public; both land on the
        // same shared virtual base address.
        .{ .type_info = 0x200, .offset = 0x00, .flags = rtti.base_virtual },
        .{ .type_info = 0x280, .offset = 0x00, .flags = rtti.base_public | rtti.base_virtual },
    });
    // Virtual base offsets both resolve to +0x20 off the object's vtable.
    state.write64(0x200 + 16, 0x300);
    state.write64(0x280 + 16, 0x300);
    state.write64(0x1000, 0x900); // object vptr
    state.write64(0x900, 0x20); // vbase offset slot at vtable+0

    var reader = rtti.Reader{};
    reader.observe(&state, 0x100);
    var graph = Graph{};
    build(&graph, &reader, &state, 0x100, 0x1000);

    try std.testing.expectEqual(@as(?bool, true), publicityOf(&graph, &state, 0x300, 0x1020, false));
}
