//! The `__dynamic_cast` decision itself.
//!
//! The rules below are the Itanium ABI's, as libc++abi implements them, with
//! one addition: every path that ends in a null pointer says *why*. `dynamic_cast`
//! returning null is two completely different events wearing the same clothes —
//! "this object is not of that type", which is the language answering the
//! question, and "the type graph could not be read", which is Rosette failing to
//! answer it. A caller branching on the first is correct C++. A caller branching
//! on the second is branching on a guess, and the only way anyone finds out is
//! if the runtime keeps the two apart.

const std = @import("std");
const rtti = @import("type_info.zig");
const hierarchy = @import("hierarchy.zig");

/// Distinct destination subobjects considered. Two is already an ambiguous
/// cast; the rest of the room exists so overflow is reported as a bound that
/// was hit rather than silently decided.
pub const max_destination_candidates: usize = 8;

pub const Strategy = enum {
    /// A null source pointer casts to null. The language says so.
    null_source,
    /// Source and destination are the same record.
    same_type,
    /// The object's dynamic type *is* the destination type.
    exact_dynamic_type,
    /// The destination subobject was found on a path through the source
    /// subobject — an ordinary up- or downcast.
    hierarchy,
    /// The destination is a sibling base: not above or below the source
    /// subobject, but reachable from the same most-derived object. This is the
    /// case the ABI's `src2dst_offset` hint cannot describe and the one a
    /// source-first search never reaches.
    cross_cast,
    /// The object's own graph was unreadable, so the answer came from the
    /// destination type's graph plus the compiler's offset hint.
    hint_offset,
    /// The graph was walked to the end and the destination is not in it — or
    /// is in it more than once, or only behind a private edge. `dynamic_cast`
    /// yields null and that null is the **correct answer**.
    ///
    /// Held apart from an undecided cast because the two are opposites that
    /// look identical from the outside: both produce a null pointer. Reporting
    /// a proven negative as a failure puts a false alarm in the log every time
    /// a program legitimately tests a pointer's type, and — worse — makes a
    /// real metadata failure indistinguishable from ordinary correct behaviour.
    proven_negative,
};

pub const Resolution = struct {
    address: u64,
    strategy: Strategy,
    /// Settled only after falling back to comparing mangled names, because
    /// pointer identity between `type_info` records failed. Normal on Mach-O;
    /// worth counting, because it means the guest's RTTI is not coalesced and
    /// every pointer-identity fast path in the guest's own code is also
    /// failing.
    by_name: bool = false,
    /// The public path from the destination subobject to the source subobject
    /// could not be checked, so the answer is the ABI's most likely one rather
    /// than a proven one. Only ever set on the `exact_dynamic_type` short cut,
    /// where refusing to answer would be strictly worse than answering.
    verified: bool = true,
};

/// Why no answer could be reached. Every one of these means the *runtime* fell
/// short, never the program.
pub const Undecided = enum {
    source_vtable_unreadable,
    offset_to_top_unreadable,
    dynamic_type_unreadable,
    hierarchy_unreadable,
    hierarchy_truncated,
    /// The graph was readable end to end and does not contain the subobject the
    /// caller says it is casting from — by pointer or by name. The pointer and
    /// its claimed static type disagree with the object's own vtable.
    source_not_in_object,

    pub fn describe(self: Undecided) []const u8 {
        return switch (self) {
            .source_vtable_unreadable => "the source object's vtable pointer was not guest-backed",
            .offset_to_top_unreadable => "the vtable's offset-to-top slot was not guest-backed",
            .dynamic_type_unreadable => "the vtable's type_info slot was not guest-backed",
            .hierarchy_unreadable => "a base-class edge could not be followed, so the graph walked is a subset of the real one",
            .hierarchy_truncated => "the hierarchy exceeded the walk's node or depth bound",
            .source_not_in_object => "the object's own graph does not contain the source subobject, by pointer or by name",
        };
    }
};

pub const Outcome = union(enum) {
    resolved: Resolution,
    undecided: Undecided,
};

pub const Request = struct {
    source_object: u64,
    source_type: u64,
    destination_type: u64,
    /// The ABI's `src2dst_offset`: >= 0 is the offset of the source subobject
    /// inside the destination type, -1 that the source is not a public base,
    /// -2 that it is a repeated public base, -3 that it is virtual or below a
    /// virtual base.
    hint: i64,
};

pub fn resolve(reader: *rtti.Reader, state: anytype, request: Request) Outcome {
    if (request.source_object == 0) {
        return .{ .resolved = .{ .address = 0, .strategy = .null_source } };
    }

    // The three arguments are `type_info` records by the ABI's own contract,
    // which makes them the reader's most reliable source of truth about what a
    // `type_info` looks like in this process.
    reader.observe(state, request.source_type);
    reader.observe(state, request.destination_type);

    if (request.source_type != 0 and request.source_type == request.destination_type) {
        return .{ .resolved = .{ .address = request.source_object, .strategy = .same_type } };
    }

    const source_vtable = rtti.readPointer(state, request.source_object) orelse
        return .{ .undecided = .source_vtable_unreadable };
    const offset_to_top = rtti.readSigned(state, source_vtable -| 16) orelse
        return .{ .undecided = .offset_to_top_unreadable };
    const dynamic_type = rtti.readPointer(state, source_vtable -| 8) orelse
        return .{ .undecided = .dynamic_type_unreadable };
    if (dynamic_type == 0) return .{ .undecided = .dynamic_type_unreadable };
    reader.observe(state, dynamic_type);

    const complete_object = rtti.addSigned(request.source_object, offset_to_top);

    var incomplete = false;
    var truncated = false;
    var ambiguous = false;
    var source_located = false;

    // libc++abi runs the whole search twice on Apple platforms: once comparing
    // `type_info` pointers, then — because Mach-O images that were not built to
    // coalesce their RTTI carry more than one record per class — once comparing
    // mangled names. The second pass is the standard library's own behaviour,
    // not a workaround bolted on beside it.
    var pass: u8 = 0;
    while (pass < 2) : (pass += 1) {
        const by_name = pass == 1;
        const attempt = search(reader, state, request, dynamic_type, complete_object, by_name);
        if (attempt.address) |address| {
            return .{ .resolved = .{
                .address = address,
                .strategy = attempt.strategy,
                .by_name = by_name,
                .verified = attempt.verified,
            } };
        }
        incomplete = incomplete or attempt.incomplete;
        truncated = truncated or attempt.truncated;
        ambiguous = ambiguous or attempt.ambiguous;
        source_located = source_located or attempt.source_located;
    }

    // Ambiguity is a decision, not a shortfall: a second matching subobject
    // cannot be un-found by walking further, so this holds even where the rest
    // of the walk fell short.
    if (ambiguous) return .{ .resolved = .{ .address = 0, .strategy = .proven_negative } };

    if (incomplete or truncated) {
        // A non-negative hint is the compiler's own statement of where the
        // source subobject sits inside the destination type. That makes the
        // destination type's graph a second, independent route to the answer —
        // and it is frequently readable when the object's is not.
        if (request.hint >= 0) {
            if (derivedFromHint(reader, state, request, complete_object)) |address| {
                return .{ .resolved = .{ .address = address, .strategy = .hint_offset } };
            }
        }
        return .{ .undecided = if (incomplete) .hierarchy_unreadable else .hierarchy_truncated };
    }

    if (!source_located) return .{ .undecided = .source_not_in_object };
    return .{ .resolved = .{ .address = 0, .strategy = .proven_negative } };
}

const Attempt = struct {
    address: ?u64 = null,
    strategy: Strategy = .hierarchy,
    incomplete: bool = false,
    truncated: bool = false,
    ambiguous: bool = false,
    source_located: bool = false,
    verified: bool = true,
};

fn search(
    reader: *rtti.Reader,
    state: anytype,
    request: Request,
    dynamic_type: u64,
    complete_object: u64,
    use_strcmp: bool,
) Attempt {
    var attempt = Attempt{};
    var graph: hierarchy.Graph = .{};
    hierarchy.build(&graph, reader, state, dynamic_type, complete_object);
    attempt.incomplete = graph.incomplete;
    attempt.truncated = graph.truncated;

    const source_publicity = hierarchy.publicityOf(
        &graph,
        state,
        request.source_type,
        request.source_object,
        use_strcmp,
    );
    attempt.source_located = source_publicity != null;

    // The short cut: the object already *is* the destination type, so the
    // destination subobject is the complete object and the only open question
    // is whether the source subobject is publicly reachable from it.
    if (rtti.sameType(state, dynamic_type, request.destination_type, use_strcmp)) {
        if (source_publicity) |is_public| {
            // Proven private. Null is the language's answer, so leave the
            // address unset and let the caller record a proven negative.
            if (!is_public) return attempt;
        } else {
            // Not proven either way. Refusing to answer here would turn every
            // cast whose RTTI Rosette cannot fully read into a null the guest
            // would branch on, which is worse than the ABI's likely answer.
            attempt.verified = false;
        }
        attempt.address = complete_object;
        attempt.strategy = .exact_dynamic_type;
        return attempt;
    }

    var candidates: [max_destination_candidates]hierarchy.Candidate = undefined;
    const found = hierarchy.collectByType(
        &graph,
        state,
        request.destination_type,
        use_strcmp,
        &candidates,
    );
    if (found == candidates.len) attempt.truncated = true;

    var leading: ?hierarchy.Candidate = null;
    var leading_count: u32 = 0;
    var leading_is_public = false;
    var trailing: ?hierarchy.Candidate = null;
    var trailing_count: u32 = 0;

    for (candidates[0..found]) |candidate| {
        var above: hierarchy.Graph = .{};
        hierarchy.build(&above, reader, state, candidate.type_info, candidate.object);
        if (above.incomplete) attempt.incomplete = true;
        if (above.truncated) attempt.truncated = true;
        const reaches_source = hierarchy.publicityOf(
            &above,
            state,
            request.source_type,
            request.source_object,
            use_strcmp,
        );
        if (reaches_source) |is_public| {
            leading_count += 1;
            if (leading == null) {
                leading = candidate;
                leading_is_public = is_public;
            } else if (is_public) {
                leading_is_public = true;
            }
        } else {
            trailing_count += 1;
            if (trailing == null) trailing = candidate;
        }
    }

    const source_public_from_root = source_publicity orelse false;

    switch (leading_count) {
        0 => {
            // A cross-cast: the destination is a sibling base, not something
            // the source subobject sits inside or contains. It succeeds when
            // there is exactly one destination subobject and the most-derived
            // object reaches both it and the source publicly. A search that
            // insists on finding the destination *from the source* never gets
            // here and reports the cast as unresolvable instead.
            if (trailing_count == 1 and source_public_from_root and trailing.?.public) {
                attempt.address = trailing.?.object;
                attempt.strategy = .cross_cast;
            }
        },
        1 => {
            if (leading_is_public) {
                attempt.address = leading.?.object;
                attempt.strategy = .hierarchy;
            } else if (trailing_count == 0 and source_public_from_root and leading.?.public) {
                // The path down from the destination is private, but the whole
                // object reaches both ends publicly, so the cast still stands.
                attempt.address = leading.?.object;
                attempt.strategy = .hierarchy;
            }
        },
        else => attempt.ambiguous = true,
    }

    return attempt;
}

/// Verify the compiler's offset hint against the destination type's own graph:
/// the ABI's `has_unambiguous_public_base` check, run when the object's graph
/// was the part that could not be read.
fn derivedFromHint(
    reader: *rtti.Reader,
    state: anytype,
    request: Request,
    complete_object: u64,
) ?u64 {
    if (request.hint < 0) return null;
    const offset: u64 = @intCast(request.hint);
    if (request.source_object < offset) return null;
    const candidate = request.source_object - offset;
    // The destination subobject cannot begin before the complete object does.
    if (candidate < complete_object) return null;

    // When the candidate's own vptr is readable it has to agree that this is
    // the same complete object; a hint that points outside it is not a hint
    // about this cast.
    if (rtti.readPointer(state, candidate)) |vtable| {
        if (rtti.readSigned(state, vtable -| 16)) |offset_to_top| {
            if (rtti.addSigned(candidate, offset_to_top) != complete_object) return null;
        }
    }

    var graph: hierarchy.Graph = .{};
    hierarchy.build(&graph, reader, state, request.destination_type, candidate);
    var pass: u8 = 0;
    while (pass < 2) : (pass += 1) {
        const publicity = hierarchy.publicityOf(
            &graph,
            state,
            request.source_type,
            request.source_object,
            pass == 1,
        ) orelse continue;
        if (publicity) return candidate;
    }
    return null;
}

/// Whether a thrown class can bind to a typed catch clause. The Itanium ABI
/// permits a catch of any unambiguous public base, not only an exact record
/// match, and — like the cast — falls back to names when Mach-O has left the
/// program with more than one record per class.
pub fn catchCompatible(state: anytype, thrown_type: u64, catch_type: u64) bool {
    if (thrown_type == 0 or catch_type == 0) return false;
    var reader = rtti.Reader{};
    reader.observe(state, thrown_type);
    reader.observe(state, catch_type);
    if (hierarchy.hasPublicBase(&reader, state, thrown_type, catch_type, true, 0, false)) return true;
    return hierarchy.hasPublicBase(&reader, state, thrown_type, catch_type, true, 0, true);
}

const testing = @import("testing.zig");

const rtti_vtable: u64 = 0x400;

/// `MacEvent` — the shape behind the reported failure. A most-derived class
/// with two bases, each of which derives `WaitHandle`, so `WaitHandle` is a
/// repeated public base (`src2dst_offset` = -2) and a pointer to the one under
/// `Event` has to cross-cast sideways to reach `MacWaitHandle`.
///
///     MacEvent            @ 0x1000   (vmi: Event @+0x00, MacWaitHandle @+0x20)
///       Event             @ 0x1000   (si:  WaitHandle @+0)
///         WaitHandle      @ 0x1000
///       MacWaitHandle     @ 0x1020   (si:  WaitHandle @+0)
///         WaitHandle      @ 0x1020
fn buildSiblingWaitHandles(state: *testing.State) void {
    state.writeTypeInfo(0x100, rtti_vtable, 0x700, "N2xe9threading8MacEventE");
    state.writeTypeInfo(0x140, rtti_vtable, 0x730, "N2xe9threading5EventE");
    state.writeTypeInfo(0x180, rtti_vtable, 0x760, "N2xe9threading13MacWaitHandleE");
    state.writeTypeInfo(0x1c0, rtti_vtable, 0x790, "N2xe9threading10WaitHandleE");
    state.writeVmi(0x100, 0, &.{
        .{ .type_info = 0x140, .offset = 0x00, .flags = rtti.base_public },
        .{ .type_info = 0x180, .offset = 0x20, .flags = rtti.base_public },
    });
    state.write64(0x140 + 16, 0x1c0); // Event : public WaitHandle
    state.write64(0x180 + 16, 0x1c0); // MacWaitHandle : public WaitHandle
    state.writeObject(0x1000, 0x900, 0, 0x100);
}

test "a sibling base resolves as a cross-cast instead of an unreadable hierarchy" {
    var state = testing.State{};
    buildSiblingWaitHandles(&state);

    var reader = rtti.Reader{};
    const outcome = resolve(&reader, &state, .{
        .source_object = 0x1000, // the WaitHandle under Event
        .source_type = 0x1c0,
        .destination_type = 0x180,
        .hint = -2, // repeated public base: no offset the compiler can name
    });
    try std.testing.expectEqual(Strategy.cross_cast, outcome.resolved.strategy);
    try std.testing.expectEqual(@as(u64, 0x1020), outcome.resolved.address);
}

test "a duplicated type_info record resolves by name rather than reporting a failure" {
    var state = testing.State{};
    buildSiblingWaitHandles(&state);
    // A second image's copy of MacWaitHandle's record: same class, same name,
    // different address. Nothing in the object's graph points at it.
    state.writeTypeInfo(0x280, rtti_vtable, 0x7c0, "N2xe9threading13MacWaitHandleE");

    var reader = rtti.Reader{};
    const outcome = resolve(&reader, &state, .{
        .source_object = 0x1000,
        .source_type = 0x1c0,
        .destination_type = 0x280,
        .hint = -2,
    });
    try std.testing.expectEqual(Strategy.cross_cast, outcome.resolved.strategy);
    try std.testing.expect(outcome.resolved.by_name);
    try std.testing.expectEqual(@as(u64, 0x1020), outcome.resolved.address);
}

test "a duplicated source record is found by name too" {
    var state = testing.State{};
    buildSiblingWaitHandles(&state);
    // This is the half the old two-pass walk never covered: it matched the
    // destination by name but still demanded pointer identity for the source,
    // so a graph that plainly contained the source subobject reported it
    // missing and the cast came out undecidable.
    state.writeTypeInfo(0x2c0, rtti_vtable, 0x800, "N2xe9threading10WaitHandleE");

    var reader = rtti.Reader{};
    const outcome = resolve(&reader, &state, .{
        .source_object = 0x1000,
        .source_type = 0x2c0,
        .destination_type = 0x180,
        .hint = -2,
    });
    try std.testing.expectEqual(Strategy.cross_cast, outcome.resolved.strategy);
    try std.testing.expect(outcome.resolved.by_name);
    try std.testing.expectEqual(@as(u64, 0x1020), outcome.resolved.address);
}

test "an ordinary downcast to the dynamic type keeps resolving through the short cut" {
    var state = testing.State{};
    state.writeTypeInfo(0x100, rtti_vtable, 0x700, "N2xe2ui11GTKMenuItemE");
    state.writeTypeInfo(0x140, rtti_vtable, 0x730, "N2xe2ui8MenuItemE");
    state.write64(0x100 + 16, 0x140); // GTKMenuItem : public MenuItem
    state.writeObject(0x1000, 0x900, 0, 0x100);

    var reader = rtti.Reader{};
    const outcome = resolve(&reader, &state, .{
        .source_object = 0x1000,
        .source_type = 0x140,
        .destination_type = 0x100,
        .hint = 0,
    });
    try std.testing.expectEqual(Strategy.exact_dynamic_type, outcome.resolved.strategy);
    try std.testing.expectEqual(@as(u64, 0x1000), outcome.resolved.address);
    try std.testing.expect(outcome.resolved.verified);
}

test "a private base makes the short cut answer null instead of a pointer" {
    var state = testing.State{};
    state.writeTypeInfo(0x100, rtti_vtable, 0x700, "7Derived");
    state.writeTypeInfo(0x140, rtti_vtable, 0x730, "6Secret");
    state.writeVmi(0x100, 0, &.{
        .{ .type_info = 0x140, .offset = 0, .flags = 0 }, // private
    });
    state.writeObject(0x1000, 0x900, 0, 0x100);

    var reader = rtti.Reader{};
    const outcome = resolve(&reader, &state, .{
        .source_object = 0x1000,
        .source_type = 0x140,
        .destination_type = 0x100,
        .hint = -1,
    });
    try std.testing.expectEqual(Strategy.proven_negative, outcome.resolved.strategy);
    try std.testing.expectEqual(@as(u64, 0), outcome.resolved.address);
}

test "a destination absent from a fully readable graph is a proven negative" {
    var state = testing.State{};
    buildSiblingWaitHandles(&state);
    state.writeTypeInfo(0x300, rtti_vtable, 0x840, "N2xe9threading9MacMutantE");

    var reader = rtti.Reader{};
    const outcome = resolve(&reader, &state, .{
        .source_object = 0x1000,
        .source_type = 0x1c0,
        .destination_type = 0x300,
        .hint = -1,
    });
    try std.testing.expectEqual(Strategy.proven_negative, outcome.resolved.strategy);
    try std.testing.expectEqual(@as(u64, 0), outcome.resolved.address);
}

test "an unreadable graph is undecided, never a negative" {
    var state = testing.State{};
    state.writeTypeInfo(0x100, rtti_vtable, 0x700, "7Derived");
    state.writeTypeInfo(0x140, rtti_vtable, 0x730, "4Base");
    state.writeTypeInfo(0x180, rtti_vtable, 0x760, "6Target");
    // One readable base and one that points outside guest memory.
    state.writeVmi(0x100, 0, &.{
        .{ .type_info = 0x140, .offset = 0x00, .flags = rtti.base_public },
        .{ .type_info = 0xdead_0000, .offset = 0x10, .flags = rtti.base_public },
    });
    state.writeObject(0x1000, 0x900, 0, 0x100);

    var reader = rtti.Reader{};
    const outcome = resolve(&reader, &state, .{
        .source_object = 0x1000,
        .source_type = 0x140,
        .destination_type = 0x180,
        .hint = -1,
    });
    try std.testing.expectEqual(Undecided.hierarchy_unreadable, outcome.undecided);
}

test "an unreadable graph still resolves when the hint names the offset" {
    var state = testing.State{};
    // The object's dynamic type is unreadable, so nothing can be walked from
    // the object. The destination type's own graph is intact.
    state.writeTypeInfo(0x180, rtti_vtable, 0x760, "7Derived");
    state.writeTypeInfo(0x140, rtti_vtable, 0x730, "4Base");
    state.writeVmi(0x180, 0, &.{
        .{ .type_info = 0x140, .offset = 0x10, .flags = rtti.base_public },
    });
    state.writeObject(0x1000, 0x900, 0, 0x1_0000); // dynamic type off the map
    state.writeObject(0x1010, 0x980, -0x10, 0x1_0000); // the Base subobject's own vptr

    var reader = rtti.Reader{};
    const outcome = resolve(&reader, &state, .{
        .source_object = 0x1010,
        .source_type = 0x140,
        .destination_type = 0x180,
        .hint = 0x10,
    });
    try std.testing.expectEqual(Strategy.hint_offset, outcome.resolved.strategy);
    try std.testing.expectEqual(@as(u64, 0x1000), outcome.resolved.address);
}

test "a null source is the language's answer, not a failure" {
    var state = testing.State{};
    var reader = rtti.Reader{};
    const outcome = resolve(&reader, &state, .{
        .source_object = 0,
        .source_type = 0x100,
        .destination_type = 0x140,
        .hint = -1,
    });
    try std.testing.expectEqual(Strategy.null_source, outcome.resolved.strategy);
}

test "typed catch accepts a public base and rejects a private one" {
    var state = testing.State{};
    state.writeTypeInfo(0x100, rtti_vtable, 0x700, "6Thrown");
    state.writeTypeInfo(0x140, rtti_vtable, 0x730, "6Public");
    state.writeTypeInfo(0x180, rtti_vtable, 0x760, "7Private");
    state.writeVmi(0x100, 0, &.{
        .{ .type_info = 0x140, .offset = 0x00, .flags = rtti.base_public },
        .{ .type_info = 0x180, .offset = 0x10, .flags = 0 },
    });

    try std.testing.expect(catchCompatible(&state, 0x100, 0x140));
    try std.testing.expect(!catchCompatible(&state, 0x100, 0x180));
    try std.testing.expect(!catchCompatible(&state, 0x140, 0x100));
}
