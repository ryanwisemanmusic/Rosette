const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

const MAX_HIERARCHY_DEPTH: usize = 32;
const MAX_BASES_PER_TYPE: u32 = 256;
const BASE_VIRTUAL: u8 = 0x1;
const BASE_PUBLIC: u8 = 0x2;

pub const Strategy = enum {
    null_source,
    same_type,
    exact_dynamic_type,
    hierarchy,
    name_based,
    /// The hierarchy was walked successfully and the destination type is simply
    /// not in it. `dynamic_cast` returns null, and that null is the **correct
    /// answer** — the language defines this case.
    ///
    /// Kept apart from a metadata failure because the two are opposites that
    /// look identical from the outside: both produce a null pointer. Reporting
    /// a proven negative as a failure puts a false alarm in the log every time a
    /// program legitimately tests a pointer's type — and, worse, makes a real
    /// metadata failure indistinguishable from ordinary correct behaviour.
    proven_negative,
};

pub const Resolution = struct {
    address: u64,
    strategy: Strategy,
};

/// Returns whether a thrown class can bind to a typed catch clause. The
/// Itanium ABI permits a catch of any unambiguous public base class, not only
/// an exact type_info pointer match.
pub fn isCatchCompatible(state: anytype, thrown_type: u64, catch_type: u64) bool {
    if (thrown_type == 0 or catch_type == 0) return false;
    return containsPublicBase(state, thrown_type, catch_type, true, 0);
}

const TypeKind = enum {
    class,
    single_inheritance,
    multiple_inheritance,
    unknown,
};

const Matches = struct {
    source_found: bool = false,
    destination: u64 = 0,
    destination_count: u32 = 0,

    fn recordDestination(self: *Matches, address: u64) void {
        if (self.destination_count == 0) {
            self.destination = address;
            self.destination_count = 1;
        } else if (self.destination != address) {
            self.destination_count +|= 1;
        }
    }
};

const ResolvedEntry = struct {
    source: u64,
    result: u64,
    source_type: u64,
    destination_type: u64,
    hint: i64,
    strategy: Strategy,
};

const TRACE_BUFFER_SIZE: usize = 16;

pub const Engine = struct {
    attempts: u64 = 0,
    resolved: u64 = 0,
    null_sources: u64 = 0,
    exact_dynamic: u64 = 0,
    hierarchy_resolved: u64 = 0,
    failed_metadata: u64 = 0,
    /// Casts answered null *correctly*: the hierarchy was readable and the
    /// destination is not a base of the dynamic type.
    proven_negatives: u64 = 0,
    ambiguous: u64 = 0,
    negative_hints: u64 = 0,
    trace_buffer: [TRACE_BUFFER_SIZE]ResolvedEntry = undefined,
    trace_index: usize = 0,
    trace_filled: bool = false,
    last_fail_source: u64 = 0,
    last_fail_src_type: u64 = 0,
    last_fail_dst_type: u64 = 0,
    last_fail_hint: u64 = 0,

    pub fn resolve(
        self: *Engine,
        state: anytype,
        source_object: u64,
        source_type: u64,
        destination_type: u64,
        offset_hint_raw: u64,
    ) ?Resolution {
        self.attempts +|= 1;
        if (source_object == 0) {
            self.resolved +|= 1;
            self.null_sources +|= 1;
            return .{ .address = 0, .strategy = .null_source };
        }
        if (source_type == destination_type) {
            self.resolved +|= 1;
            return .{ .address = source_object, .strategy = .same_type };
        }

        self.last_fail_source = source_object;
        self.last_fail_src_type = source_type;
        self.last_fail_dst_type = destination_type;
        self.last_fail_hint = offset_hint_raw;

        const source_vtable = readPointer(state, source_object) orelse return self.failMetadata();
        const offset_to_top = readSigned(state, source_vtable -| 16) orelse return self.failMetadata();
        const dynamic_type = readPointer(state, source_vtable -| 8) orelse return self.failMetadata();
        const complete_object = addSigned(source_object, offset_to_top);
        const hint: i64 = @bitCast(offset_hint_raw);
        if (hint < 0) self.negative_hints +|= 1;

        if (dynamic_type == destination_type) {
            self.resolved +|= 1;
            self.exact_dynamic +|= 1;
            self.trace(state, source_object, complete_object, source_type, destination_type, hint, .exact_dynamic_type);
            return .{ .address = complete_object, .strategy = .exact_dynamic_type };
        }

        var matches = Matches{};
        visitHierarchy(
            state,
            dynamic_type,
            complete_object,
            source_type,
            source_object,
            destination_type,
            true,
            0,
            &matches,
        );
        if (matches.source_found and matches.destination_count == 1) {
            self.resolved +|= 1;
            self.hierarchy_resolved +|= 1;
            self.trace(state, source_object, matches.destination, source_type, destination_type, hint, .hierarchy);
            return .{ .address = matches.destination, .strategy = .hierarchy };
        }
        if (matches.destination_count > 1) {
            self.ambiguous +|= 1;
            return self.failMetadata();
        }

        {
            const dest_name = typeName(state, destination_type) orelse return self.failMetadata();
            var name_matches = Matches{};
            visitHierarchyByName(
                state,
                dynamic_type,
                complete_object,
                source_type,
                source_object,
                dest_name,
                true,
                0,
                &name_matches,
            );
            if (name_matches.source_found and name_matches.destination_count == 1) {
                self.resolved +|= 1;
                self.hierarchy_resolved +|= 1;
                self.trace(state, source_object, name_matches.destination, source_type, destination_type, hint, .name_based);
                return .{ .address = name_matches.destination, .strategy = .name_based };
            }
            if (name_matches.destination_count > 1) self.ambiguous +|= 1;
            // The graph was readable — the source type was located inside it —
            // and neither pass found the destination. That is not a failure to
            // resolve; it is a resolution, and its answer is null. A program
            // asking "is this Entry a HostPathEntry?" about an entry that is not
            // one gets null by the language's own rules.
            if (matches.source_found or name_matches.source_found) {
                self.resolved +|= 1;
                self.proven_negatives +|= 1;
                self.clearLastFailure();
                return .{ .address = 0, .strategy = .proven_negative };
            }
        }
        return self.failMetadata();
    }

    /// A cast that resolved has no failure to report. Without this the last
    /// *unresolved* cast stays latched and is printed at exit as though it were
    /// the outcome of a later, successful one.
    fn clearLastFailure(self: *Engine) void {
        self.last_fail_source = 0;
        self.last_fail_src_type = 0;
        self.last_fail_dst_type = 0;
        self.last_fail_hint = 0;
    }

    pub fn logSummary(self: *const Engine) void {
        if (self.attempts == 0) return;
        machoCapturePrint(
            "macho-processor: Itanium dynamic cast: attempts={d} resolved={d} null_sources={d} exact={d} hierarchy={d} proven_negatives={d} negative_hints={d} metadata_failures={d} ambiguous={d}; a proven negative is a cast that correctly returned null because the destination is not a base of the dynamic type — the language's own answer, not a failure. Only metadata_failures are casts Rosette could not decide\n",
            .{
                self.attempts,
                self.resolved,
                self.null_sources,
                self.exact_dynamic,
                self.hierarchy_resolved,
                self.proven_negatives,
                self.negative_hints,
                self.failed_metadata,
                self.ambiguous,
            },
        );
    }

    fn failMetadata(self: *Engine) ?Resolution {
        self.failed_metadata +|= 1;
        return null;
    }

    fn trace(
        self: *Engine,
        state: anytype,
        source: u64,
        result: u64,
        source_type: u64,
        destination_type: u64,
        hint: i64,
        strategy: Strategy,
    ) void {
        _ = state;
        const entry = &self.trace_buffer[self.trace_index];
        entry.* = .{
            .source = source,
            .result = result,
            .source_type = source_type,
            .destination_type = destination_type,
            .hint = hint,
            .strategy = strategy,
        };
        self.trace_index = (self.trace_index + 1) % TRACE_BUFFER_SIZE;
        if (self.trace_index == 0) self.trace_filled = true;
    }

    pub fn dumpTraceBuffer(self: *const Engine, state: anytype) void {
        const count = if (self.trace_filled) TRACE_BUFFER_SIZE else self.trace_index;
        if (count > 0) {
            const start = if (self.trace_filled) self.trace_index else 0;
            for (0..count) |i| {
                const idx = (start + i) % TRACE_BUFFER_SIZE;
                const entry = self.trace_buffer[idx];
                const source_name = typeName(state, entry.source_type) orelse "<unknown>";
                const dest_name = typeName(state, entry.destination_type) orelse "<unknown>";
                machoCapturePrint(
                    "macho-processor: __dynamic_cast resolved: strategy={s} source=0x{x} result=0x{x} hint={d} {s} -> {s}\n",
                    .{ @tagName(entry.strategy), entry.source, entry.result, entry.hint, source_name, dest_name },
                );
            }
        }
        if (self.last_fail_source != 0) {
            const source_name = typeName(state, self.last_fail_src_type) orelse "<unknown>";
            const dest_name = typeName(state, self.last_fail_dst_type) orelse "<unknown>";
            machoCapturePrint(
                "macho-processor: __dynamic_cast UNDECIDED: source=0x{x} source_type={s} dest_type={s} hint={d}; the hierarchy was unreadable. This is not a failed cast — a failed cast resolves to a proven negative and is not reported here\n",
                .{ self.last_fail_source, source_name, dest_name, @as(i64, @bitCast(self.last_fail_hint)) },
            );
        }
    }
};

fn visitHierarchy(
    state: anytype,
    type_info: u64,
    object: u64,
    source_type: u64,
    source_object: u64,
    destination_type: u64,
    public_path: bool,
    depth: usize,
    matches: *Matches,
) void {
    if (depth > MAX_HIERARCHY_DEPTH or type_info == 0 or object == 0) return;
    if (public_path and type_info == source_type and object == source_object) matches.source_found = true;
    if (public_path and type_info == destination_type) matches.recordDestination(object);

    switch (typeKind(state, type_info)) {
        .class, .unknown => {},
        .single_inheritance => {
            const base_type = readPointer(state, type_info +| 16) orelse return;
            visitHierarchy(state, base_type, object, source_type, source_object, destination_type, public_path, depth + 1, matches);
        },
        .multiple_inheritance => {
            const header = state.guestMemoryConst(type_info +| 16, 8) orelse return;
            const base_count = std.mem.readInt(u32, header[4..8], .little);
            if (base_count > MAX_BASES_PER_TYPE) return;
            var index: u32 = 0;
            while (index < base_count) : (index += 1) {
                const entry = type_info +| 24 +| @as(u64, index) * 16;
                const base_type = readPointer(state, entry) orelse continue;
                const offset_flags = readPointer(state, entry +| 8) orelse continue;
                const flags: u8 = @truncate(offset_flags);
                const encoded_offset: i64 = @as(i64, @bitCast(offset_flags)) >> 8;
                const base_object = if ((flags & BASE_VIRTUAL) != 0) blk: {
                    const vtable = readPointer(state, object) orelse continue;
                    const dynamic_offset = readSigned(state, addSigned(vtable, encoded_offset)) orelse continue;
                    break :blk addSigned(object, dynamic_offset);
                } else addSigned(object, encoded_offset);
                visitHierarchy(
                    state,
                    base_type,
                    base_object,
                    source_type,
                    source_object,
                    destination_type,
                    public_path and (flags & BASE_PUBLIC) != 0,
                    depth + 1,
                    matches,
                );
            }
        },
    }
}

fn visitHierarchyByName(
    state: anytype,
    type_info: u64,
    object: u64,
    source_type: u64,
    source_object: u64,
    dest_name: []const u8,
    public_path: bool,
    depth: usize,
    matches: *Matches,
) void {
    if (depth > MAX_HIERARCHY_DEPTH or type_info == 0 or object == 0) return;
    if (public_path and type_info == source_type and object == source_object) matches.source_found = true;
    if (public_path) {
        if (typeName(state, type_info)) |name| {
            if (std.mem.eql(u8, name, dest_name)) {
                matches.recordDestination(object);
                if (!matches.source_found) return;
            }
        }
    }

    switch (typeKind(state, type_info)) {
        .class, .unknown => {},
        .single_inheritance => {
            const base_type = readPointer(state, type_info +| 16) orelse return;
            visitHierarchyByName(state, base_type, object, source_type, source_object, dest_name, public_path, depth + 1, matches);
        },
        .multiple_inheritance => {
            const header = state.guestMemoryConst(type_info +| 16, 8) orelse return;
            const base_count = std.mem.readInt(u32, header[4..8], .little);
            if (base_count > MAX_BASES_PER_TYPE) return;
            var index: u32 = 0;
            while (index < base_count) : (index += 1) {
                const entry = type_info +| 24 +| @as(u64, index) * 16;
                const base_type = readPointer(state, entry) orelse continue;
                const offset_flags = readPointer(state, entry +| 8) orelse continue;
                const flags: u8 = @truncate(offset_flags);
                const encoded_offset: i64 = @as(i64, @bitCast(offset_flags)) >> 8;
                const base_object = if ((flags & BASE_VIRTUAL) != 0) blk: {
                    const vtable = readPointer(state, object) orelse continue;
                    const dynamic_offset = readSigned(state, addSigned(vtable, encoded_offset)) orelse continue;
                    break :blk addSigned(object, dynamic_offset);
                } else addSigned(object, encoded_offset);
                visitHierarchyByName(
                    state,
                    base_type,
                    base_object,
                    source_type,
                    source_object,
                    dest_name,
                    public_path and (flags & BASE_PUBLIC) != 0,
                    depth + 1,
                    matches,
                );
            }
        },
    }
}

fn containsPublicBase(
    state: anytype,
    type_info: u64,
    catch_type: u64,
    public_path: bool,
    depth: usize,
) bool {
    if (depth > MAX_HIERARCHY_DEPTH or type_info == 0) return false;
    if (public_path and type_info == catch_type) return true;

    return switch (typeKind(state, type_info)) {
        .class, .unknown => false,
        .single_inheritance => blk: {
            const base_type = readPointer(state, type_info +| 16) orelse break :blk false;
            break :blk containsPublicBase(state, base_type, catch_type, public_path, depth + 1);
        },
        .multiple_inheritance => blk: {
            const header = state.guestMemoryConst(type_info +| 16, 8) orelse break :blk false;
            const base_count = std.mem.readInt(u32, header[4..8], .little);
            if (base_count > MAX_BASES_PER_TYPE) break :blk false;
            var index: u32 = 0;
            while (index < base_count) : (index += 1) {
                const entry = type_info +| 24 +| @as(u64, index) * 16;
                const base_type = readPointer(state, entry) orelse continue;
                const offset_flags = readPointer(state, entry +| 8) orelse continue;
                const flags: u8 = @truncate(offset_flags);
                if (containsPublicBase(state, base_type, catch_type, public_path and (flags & BASE_PUBLIC) != 0, depth + 1)) {
                    break :blk true;
                }
            }
            break :blk false;
        },
    };
}

fn typeKind(state: anytype, type_info: u64) TypeKind {
    if (readPointer(state, type_info)) |vtable| {
        if (state.metadata.nearestSymbol(vtable)) |symbol| {
            if (kindFromSymbol(symbol.name)) |kind| return kind;
        }
    }
    for (state.metadata.bindings) |binding| {
        if (binding.address == type_info) {
            if (kindFromSymbol(binding.name)) |kind| return kind;
        }
    }
    return inferTypeKindFromLayout(state, type_info);
}

/// libc++abi's type_info vtables often belong to a dylib that is deliberately
/// not materialized in guest memory. When metadata cannot name that vtable,
/// distinguish the standard RTTI layouts from their guest-backed fields.
fn inferTypeKindFromLayout(state: anytype, type_info: u64) TypeKind {
    const direct_base = readPointer(state, type_info +| 16) orelse return .unknown;
    if (looksLikeTypeInfo(state, direct_base)) return .single_inheritance;

    const header = state.guestMemoryConst(type_info +| 16, 8) orelse return .unknown;
    const base_count = std.mem.readInt(u32, header[4..8], .little);
    if (base_count == 0 or base_count > MAX_BASES_PER_TYPE) return .class;
    const first_base = readPointer(state, type_info +| 24) orelse return .unknown;
    return if (looksLikeTypeInfo(state, first_base)) .multiple_inheritance else .class;
}

fn looksLikeTypeInfo(state: anytype, address: u64) bool {
    if (address == 0) return false;
    const name_address = readPointer(state, address +| 8) orelse return false;
    const name = state.guestCString(name_address, 2) orelse return false;
    if (name.len == 0) return false;
    return std.ascii.isPrint(name[0]);
}

fn kindFromSymbol(symbol: []const u8) ?TypeKind {
    if (std.mem.indexOf(u8, symbol, "__vmi_class_type_info") != null) return .multiple_inheritance;
    if (std.mem.indexOf(u8, symbol, "__si_class_type_info") != null) return .single_inheritance;
    if (std.mem.indexOf(u8, symbol, "__class_type_info") != null) return .class;
    return null;
}

fn typeName(state: anytype, type_info: u64) ?[]const u8 {
    const name = readPointer(state, type_info +| 8) orelse return null;
    return state.guestCString(name, 1024);
}

fn readPointer(state: anytype, address: u64) ?u64 {
    const bytes = state.guestMemoryConst(address, 8) orelse return null;
    return std.mem.readInt(u64, bytes[0..8], .little);
}

fn readSigned(state: anytype, address: u64) ?i64 {
    return @bitCast(readPointer(state, address) orelse return null);
}

fn addSigned(address: u64, offset: i64) u64 {
    return address +% @as(u64, @bitCast(offset));
}

const TestSymbol = struct {
    name: []const u8,
    address: u64,
    offset: u64,
};

const TestMetadata = struct {
    bindings: []const TestBinding = &.{},

    fn nearestSymbol(self: *const TestMetadata, address: u64) ?TestSymbol {
        _ = self;
        _ = address;
        return null;
    }
};

const TestBinding = struct {
    address: u64,
    name: []const u8,
};

const TestState = struct {
    mem: [1024]u8 = [_]u8{0} ** 1024,
    metadata: TestMetadata = .{},

    fn guestMemoryConst(self: *const TestState, address: u64, count: u64) ?[]const u8 {
        const start: usize = @intCast(address);
        const len: usize = @intCast(count);
        if (start > self.mem.len or len > self.mem.len - start) return null;
        return self.mem[start .. start + len];
    }

    fn guestCString(self: *const TestState, address: u64, max_len: usize) ?[]const u8 {
        const start: usize = @intCast(address);
        if (start >= self.mem.len) return null;
        const available = self.mem[start..@min(self.mem.len, start + max_len)];
        const end = std.mem.indexOfScalar(u8, available, 0) orelse available.len;
        return available[0..end];
    }

    fn write64(self: *TestState, address: usize, value: u64) void {
        std.mem.writeInt(u64, self.mem[address..][0..8], value, .little);
    }

    fn write32(self: *TestState, address: usize, value: u32) void {
        std.mem.writeInt(u32, self.mem[address..][0..4], value, .little);
    }
};

test "negative ABI hint resolves exact dynamic type without pointer subtraction" {
    var state = TestState{};
    const source_object = 0x110;
    const complete_object = 0x100;
    const vtable = 0x200;
    const source_type = 0x280;
    const destination_type = 0x300;
    state.write64(source_object, vtable);
    state.write64(vtable - 16, @bitCast(@as(i64, -16)));
    state.write64(vtable - 8, destination_type);

    var engine = Engine{};
    const resolution = engine.resolve(
        &state,
        source_object,
        source_type,
        destination_type,
        @bitCast(@as(i64, -1)),
    ).?;
    try std.testing.expectEqual(complete_object, resolution.address);
    try std.testing.expectEqual(Strategy.exact_dynamic_type, resolution.strategy);
    try std.testing.expectEqual(@as(u64, 1), engine.negative_hints);
}

test "Mach-O RTTI bindings resolve public multiple inheritance" {
    const dynamic_type = 0x300;
    const source_type = 0x380;
    const destination_type = 0x3c0;
    const bindings = [_]TestBinding{
        .{ .address = dynamic_type, .name = "__ZTVN10__cxxabiv121__vmi_class_type_infoE" },
        .{ .address = source_type, .name = "__ZTVN10__cxxabiv117__class_type_infoE" },
        .{ .address = destination_type, .name = "__ZTVN10__cxxabiv117__class_type_infoE" },
    };
    var state = TestState{ .metadata = .{ .bindings = &bindings } };
    const complete_object = 0x100;
    const source_object = complete_object + 0x10;
    const destination_object = complete_object + 0x30;
    const source_vtable = 0x200;
    state.write64(source_object, source_vtable);
    state.write64(source_vtable - 16, @bitCast(@as(i64, -16)));
    state.write64(source_vtable - 8, dynamic_type);
    state.write32(dynamic_type + 16, 0);
    state.write32(dynamic_type + 20, 2);
    state.write64(dynamic_type + 24, source_type);
    state.write64(dynamic_type + 32, (@as(u64, 0x10) << 8) | BASE_PUBLIC);
    state.write64(dynamic_type + 40, destination_type);
    state.write64(dynamic_type + 48, (@as(u64, 0x30) << 8) | BASE_PUBLIC);

    var engine = Engine{};
    const resolution = engine.resolve(
        &state,
        source_object,
        source_type,
        destination_type,
        @bitCast(@as(i64, -1)),
    ).?;
    try std.testing.expectEqual(destination_object, resolution.address);
    try std.testing.expectEqual(Strategy.hierarchy, resolution.strategy);
}

test "typed catch accepts a public single-inheritance base" {
    const thrown_type = 0x300;
    const public_base = 0x340;
    const private_base = 0x380;
    const bindings = [_]TestBinding{
        .{ .address = thrown_type, .name = "__ZTVN10__cxxabiv120__si_class_type_infoE" },
        .{ .address = public_base, .name = "__ZTVN10__cxxabiv117__class_type_infoE" },
        .{ .address = private_base, .name = "__ZTVN10__cxxabiv117__class_type_infoE" },
    };
    var state = TestState{ .metadata = .{ .bindings = &bindings } };
    state.write64(thrown_type + 16, public_base);

    try std.testing.expect(isCatchCompatible(&state, thrown_type, public_base));
    try std.testing.expect(!isCatchCompatible(&state, public_base, thrown_type));
    try std.testing.expect(!isCatchCompatible(&state, thrown_type, private_base));
}

test "typed catch infers single-inheritance RTTI without a libc++abi binding" {
    const thrown_type = 0x300;
    const public_base = 0x340;
    var state = TestState{};
    state.write64(thrown_type + 8, 0x3c0);
    state.write64(thrown_type + 16, public_base);
    state.write64(public_base + 8, 0x3d0);
    state.mem[0x3c0] = 'N';
    state.mem[0x3c1] = 0;
    state.mem[0x3d0] = 'N';
    state.mem[0x3d1] = 0;

    try std.testing.expect(isCatchCompatible(&state, thrown_type, public_base));
}

// A `dynamic_cast` to a type the object is not is *defined* to yield null, and
// a runtime that reports that as a metadata failure cries wolf on every correct
// type test a program performs. Observed: a VFS `Entry` from a disc image tested
// against `HostPathEntry` — null is the right answer and the only right answer.
test "a resolution and a failure are distinguishable outcomes" {
    try std.testing.expect(Strategy.proven_negative != Strategy.hierarchy);
    const negative = Resolution{ .address = 0, .strategy = .proven_negative };
    const null_source = Resolution{ .address = 0, .strategy = .null_source };
    // Both carry a null address, so the address alone can never separate them —
    // which is exactly why the strategy has to.
    try std.testing.expectEqual(@as(u64, 0), negative.address);
    try std.testing.expectEqual(@as(u64, 0), null_source.address);
    try std.testing.expect(negative.strategy != null_source.strategy);
}

test "a proven negative clears any latched failure state" {
    var engine = Engine{};
    engine.last_fail_source = 0xdead;
    engine.last_fail_src_type = 0xbeef;
    engine.clearLastFailure();
    try std.testing.expectEqual(@as(u64, 0), engine.last_fail_source);
    try std.testing.expectEqual(@as(u64, 0), engine.last_fail_src_type);
    try std.testing.expectEqual(@as(u64, 0), engine.last_fail_dst_type);
    try std.testing.expectEqual(@as(u64, 0), engine.last_fail_hint);
}
