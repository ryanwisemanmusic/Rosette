const std = @import("std");

const MAX_HIERARCHY_DEPTH: usize = 32;
const MAX_BASES_PER_TYPE: u32 = 256;
const BASE_VIRTUAL: u8 = 0x1;
const BASE_PUBLIC: u8 = 0x2;

pub const Strategy = enum {
    null_source,
    same_type,
    exact_dynamic_type,
    hierarchy,
};

pub const Resolution = struct {
    address: u64,
    strategy: Strategy,
};

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

pub const Engine = struct {
    attempts: u64 = 0,
    resolved: u64 = 0,
    null_sources: u64 = 0,
    exact_dynamic: u64 = 0,
    hierarchy_resolved: u64 = 0,
    failed_metadata: u64 = 0,
    ambiguous: u64 = 0,
    negative_hints: u64 = 0,

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
        if (matches.destination_count > 1) self.ambiguous +|= 1;
        return self.failMetadata();
    }

    pub fn logSummary(self: *const Engine) void {
        if (self.attempts == 0) return;
        std.debug.print(
            "macho-processor: Itanium dynamic cast: attempts={d} resolved={d} null={d} exact={d} hierarchy={d} negative_hints={d} metadata_failures={d} ambiguous={d}\n",
            .{
                self.attempts,
                self.resolved,
                self.null_sources,
                self.exact_dynamic,
                self.hierarchy_resolved,
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
        self: *const Engine,
        state: anytype,
        source: u64,
        result: u64,
        source_type: u64,
        destination_type: u64,
        hint: i64,
        strategy: Strategy,
    ) void {
        _ = self;
        const source_name = typeName(state, source_type) orelse "<unknown>";
        const destination_name = typeName(state, destination_type) orelse "<unknown>";
        std.debug.print(
            "macho-processor: __dynamic_cast resolved: strategy={s} source=0x{x} result=0x{x} hint={d} {s} -> {s}\n",
            .{ @tagName(strategy), source, result, hint, source_name, destination_name },
        );
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

fn typeKind(state: anytype, type_info: u64) TypeKind {
    if (readPointer(state, type_info)) |vtable| {
        if (state.metadata.nearestSymbol(vtable)) |symbol| {
            if (kindFromSymbol(symbol.name)) |kind| return kind;
        }
    }
    for (state.metadata.bindings) |binding| {
        if (binding.address == type_info) return kindFromSymbol(binding.name) orelse .unknown;
    }
    return .unknown;
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
