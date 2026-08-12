//! Reader for Itanium C++ ABI run-time type information as it sits in guest
//! memory.
//!
//! Everything above this file — the subobject walk, the cast decision — is only
//! as good as its answer to two questions about an arbitrary guest address:
//! *is this a `type_info` record*, and *which of the three RTTI classes is it*.
//! Getting those wrong does not produce a loud failure; it produces a walk that
//! quietly stops early or wanders into an unrelated class, and then a cast that
//! reports itself undecidable for reasons that are nowhere in the log.

const std = @import("std");

/// `__base_class_type_info::__offset_flags` low bits (Itanium C++ ABI 2.9.5.6.3).
pub const base_virtual: u64 = 0x1;
pub const base_public: u64 = 0x2;

/// A base list longer than this is read as evidence that the record was
/// misidentified, not as a class with that many direct bases.
pub const max_bases_per_type: u32 = 256;

/// The three RTTI classes libc++abi emits, plus the honest fourth answer.
pub const Kind = enum {
    /// `__class_type_info`: no base classes. Sixteen bytes long, which is why
    /// it is the one that gets confused with its neighbour in the section.
    leaf,
    /// `__si_class_type_info`: exactly one base, public, non-virtual, offset 0.
    single_inheritance,
    /// `__vmi_class_type_info`: everything else — multiple, virtual, or
    /// non-public bases.
    multiple_inheritance,
    /// The record could not be classified. Distinct from `leaf`: a leaf is a
    /// class that *has* no bases, this is a class whose bases are unknown, and
    /// treating the second as the first is how a readable hierarchy turns into
    /// a false "the destination is not a base of this type".
    unknown,
};

pub const Base = struct {
    type_info: u64,
    /// Byte offset from the derived subobject, or — when `is_virtual` — the
    /// offset into the vtable holding the run-time offset.
    offset: i64,
    is_virtual: bool,
    is_public: bool,
};

/// How many distinct RTTI-class vtables the reader remembers. libc++abi has
/// exactly three; the slack absorbs a guest that carries more than one copy of
/// libc++abi without letting a misread address evict what was learned.
pub const max_tracked_vtables: usize = 16;

/// Learned facts about the guest's RTTI, accumulated across casts.
///
/// The reader is deliberately *told* about records that are certainly
/// `type_info` — the arguments of `__dynamic_cast` are, by the ABI's own
/// contract — and generalizes from their vtable pointers. Three arguments per
/// call converge on the RTTI vtable set within the first few casts a program
/// performs, and from then on "is this a type_info" is a set membership test
/// rather than a guess about printable bytes.
pub const Reader = struct {
    pub const Entry = struct {
        vtable: u64 = 0,
        kind: Kind = .unknown,
        /// Proven to be one of the RTTI classes' vtables, rather than merely
        /// seen. Only trusted entries answer `isKnownVtable`, so a record that
        /// slipped past the plausibility test cannot vouch for the next one.
        trusted: bool = false,
        /// The image's symbols and bindings have already been asked about this
        /// vtable and had nothing to say. Without this the walk rescans every
        /// binding in the process once per subobject, per pass, per cast.
        metadata_consulted: bool = false,
    };

    entries: [max_tracked_vtables]Entry = [_]Entry{.{}} ** max_tracked_vtables,
    count: usize = 0,
    /// Set when a distinct vtable could not be recorded. The learned set is
    /// then a subset of the truth, so membership stays a positive signal and
    /// non-membership stops being a negative one.
    saturated: bool = false,

    /// Record `type_info` as a genuine RTTI record. Call this only for
    /// addresses the ABI guarantees are `type_info` — the static type, the
    /// destination type, and the dynamic type read out of a live vtable.
    pub fn observe(self: *Reader, state: anytype, type_info: u64) void {
        if (type_info == 0) return;
        const vtable = readPointer(state, type_info) orelse return;
        if (vtable == 0) return;
        _ = self.intern(vtable, true);
    }

    fn intern(self: *Reader, vtable: u64, trusted: bool) ?*Entry {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.vtable != vtable) continue;
            if (trusted) entry.trusted = true;
            return entry;
        }
        if (self.count < self.entries.len) {
            const entry = &self.entries[self.count];
            self.count += 1;
            entry.* = .{ .vtable = vtable, .trusted = trusted };
            return entry;
        }
        self.saturated = true;
        // A proven RTTI vtable is worth more than a merely-seen one, so it
        // takes an untrusted slot rather than being dropped.
        if (!trusted) return null;
        for (&self.entries) |*entry| {
            if (entry.trusted) continue;
            entry.* = .{ .vtable = vtable, .trusted = true };
            return entry;
        }
        return null;
    }

    pub fn isKnownVtable(self: *const Reader, vtable: u64) bool {
        if (vtable == 0) return false;
        for (self.entries[0..self.count]) |entry| {
            if (entry.vtable == vtable) return entry.trusted;
        }
        return false;
    }

    /// Whether `address` holds a `type_info` record.
    ///
    /// The case this exists for: a leaf `__class_type_info` is sixteen bytes,
    /// so the word at `+16` — where `__si_class_type_info` keeps its base — is
    /// the first word of whatever object follows it in the section, and in an
    /// RTTI section that is usually the next record's *vtable pointer*. A test
    /// that only asks "does `+8` point at a printable string?" says yes to that
    /// vtable, and the walk then treats an unrelated sibling class as a base of
    /// a class that has no bases at all.
    ///
    /// The discriminator is one indirection: a `type_info`'s first word points
    /// at a vtable, which is data. A vtable's first word is already a function
    /// pointer, which is code. So a first word that is executable proves the
    /// address is a vtable and not a record.
    pub fn plausibleTypeInfo(self: *Reader, state: anytype, address: u64) bool {
        if (address == 0) return false;
        const vtable = readPointer(state, address) orelse return false;
        if (vtable == 0) return false;
        if (!hasPrintableName(state, address)) return false;
        if (self.isKnownVtable(vtable)) return true;
        switch (executability(state, vtable)) {
            // No oracle for this state: fall back to the name test alone.
            .unknown => return true,
            .executable => return false,
            .data => {},
        }
        // A record proven structurally is as good a source of the RTTI vtable
        // set as one handed to `observe`.
        _ = self.intern(vtable, true);
        return true;
    }

    /// Which RTTI class `type_info` belongs to.
    pub fn kindOf(self: *Reader, state: anytype, type_info: u64) Kind {
        if (type_info == 0) return .unknown;
        const vtable = readPointer(state, type_info) orelse return .unknown;
        if (vtable == 0) return .unknown;

        // Interned untrusted: this call is a question about the record, not a
        // claim that it is one. The slot exists to cache the answer.
        const slot = self.intern(vtable, false);
        if (slot) |entry| {
            if (entry.kind != .unknown) return entry.kind;
            if (entry.metadata_consulted) return self.inferKind(state, type_info);
            entry.metadata_consulted = true;
        }

        if (kindFromMetadata(state, type_info, vtable)) |kind| {
            // The vtable *is* the RTTI class, so a symbol that identifies one
            // record identifies every record sharing its vtable — and proves
            // the vtable belongs to the RTTI family.
            if (self.intern(vtable, true)) |entry| entry.kind = kind;
            return kind;
        }

        return self.inferKind(state, type_info);
    }

    /// Classify by layout, for the common case where libc++abi's own RTTI
    /// vtables belong to a dylib Rosette models rather than materializes and no
    /// symbol names them.
    fn inferKind(self: *Reader, state: anytype, type_info: u64) Kind {
        const after_header = readPointer(state, type_info +| 16) orelse return .unknown;

        // A known RTTI vtable sitting where a base pointer would be is the next
        // record in the section, which means this record ended at +16.
        if (self.isKnownVtable(after_header)) return .leaf;

        // `__vmi_class_type_info` keeps flags and a base count in that word, so
        // a validated base list is the strongest evidence available. A vtable
        // pointer misread as flags almost never passes: `__flags` is two bits
        // wide, so the low half of the word has to be 0, 1, 2, or 3.
        if (vmiBaseCount(state, type_info)) |count| {
            if (count >= 1 and count <= max_bases_per_type and validVmiFlags(after_header)) {
                var index: u32 = 0;
                var validated = true;
                while (index < count) : (index += 1) {
                    const base = vmiBase(state, type_info, index) orelse {
                        // The base list itself is off the end of mapped memory.
                        // A record shaped like this one is not a leaf; it is a
                        // record whose bases could not be read.
                        return .unknown;
                    };
                    if (guestSlice(state, base.type_info, 16) == null) return .unknown;
                    if (!self.plausibleTypeInfo(state, base.type_info)) {
                        validated = false;
                        break;
                    }
                }
                if (validated) return .multiple_inheritance;
            }
        }

        if (self.plausibleTypeInfo(state, after_header)) return .single_inheritance;
        return .leaf;
    }

    /// What a record's own kind implies about its direct bases. A null return
    /// is the "hierarchy unreadable" signal; a count of zero is the "this class
    /// has no bases" answer, and merging the two is how an unwalkable graph
    /// starts reporting confident negatives.
    pub fn basesOf(self: *Reader, state: anytype, type_info: u64) ?Bases {
        const kind = self.kindOf(state, type_info);
        return switch (kind) {
            .unknown => null,
            .leaf => .{ .kind = kind, .count = 0 },
            .single_inheritance => .{ .kind = kind, .count = 1 },
            .multiple_inheritance => blk: {
                const count = vmiBaseCount(state, type_info) orelse break :blk null;
                if (count > max_bases_per_type) break :blk null;
                break :blk .{ .kind = kind, .count = count };
            },
        };
    }

    pub fn baseAt(_: *Reader, state: anytype, type_info: u64, bases: Bases, index: u32) ?Base {
        if (index >= bases.count) return null;
        return switch (bases.kind) {
            .unknown, .leaf => null,
            .single_inheritance => blk: {
                const base = readPointer(state, type_info +| 16) orelse break :blk null;
                if (base == 0) break :blk null;
                // `__si_class_type_info` is defined as one public, non-virtual
                // base at offset zero; there are no flags to read.
                break :blk .{ .type_info = base, .offset = 0, .is_virtual = false, .is_public = true };
            },
            .multiple_inheritance => vmiBase(state, type_info, index),
        };
    }
};

pub const Bases = struct {
    kind: Kind,
    count: u32,
};

fn validVmiFlags(after_header: u64) bool {
    // `__flags` is a two-bit field: non-diamond-repeat and diamond-shaped.
    const flags: u32 = @truncate(after_header);
    return (flags & ~@as(u32, 0x3)) == 0;
}

fn vmiBaseCount(state: anytype, type_info: u64) ?u32 {
    const header = guestSlice(state, type_info +| 16, 8) orelse return null;
    return std.mem.readInt(u32, header[4..8], .little);
}

fn vmiBase(state: anytype, type_info: u64, index: u32) ?Base {
    const entry = type_info +| 24 +| @as(u64, index) *| 16;
    const base_type = readPointer(state, entry) orelse return null;
    if (base_type == 0) return null;
    const offset_flags = readPointer(state, entry +| 8) orelse return null;
    return .{
        .type_info = base_type,
        .offset = @as(i64, @bitCast(offset_flags)) >> 8,
        .is_virtual = (offset_flags & base_virtual) != 0,
        .is_public = (offset_flags & base_public) != 0,
    };
}

fn kindFromMetadata(state: anytype, type_info: u64, vtable: u64) ?Kind {
    if (state.metadata.nearestSymbol(vtable)) |symbol| {
        if (kindFromSymbol(symbol.name)) |kind| return kind;
    }
    for (state.metadata.bindings) |binding| {
        if (binding.address == type_info) {
            if (kindFromSymbol(binding.name)) |kind| return kind;
        }
    }
    return null;
}

fn kindFromSymbol(symbol: []const u8) ?Kind {
    if (std.mem.indexOf(u8, symbol, "__vmi_class_type_info") != null) return .multiple_inheritance;
    if (std.mem.indexOf(u8, symbol, "__si_class_type_info") != null) return .single_inheritance;
    if (std.mem.indexOf(u8, symbol, "__class_type_info") != null) return .leaf;
    return null;
}

/// The mangled name a `type_info` carries at `+8`.
pub fn typeName(state: anytype, type_info: u64) ?[]const u8 {
    if (type_info == 0) return null;
    const raw = readPointer(state, type_info +| 8) orelse return null;
    if (guestString(state, raw)) |name| {
        if (name.len != 0) return name;
    }
    // Some Itanium targets flag a non-unique name by setting the pointer's top
    // bit rather than by using a separate field.
    const masked = raw & ~(@as(u64, 1) << 63);
    if (masked == raw) return null;
    const name = guestString(state, masked) orelse return null;
    return if (name.len != 0) name else null;
}

/// Whether two records denote the same class.
///
/// `use_strcmp` mirrors libc++abi's forgiving second pass. Mach-O images that
/// were not built to coalesce their RTTI — hidden visibility, a bundle opened
/// with `RTLD_LOCAL`, a static libc++ linked into more than one image — end up
/// with several `type_info` records for one class, and every pointer identity
/// test between them is false. libc++abi answers that by rerunning the entire
/// search comparing mangled names, and so does this. It is the standard
/// library's own behaviour on Apple platforms, not a workaround layered on top
/// of it.
pub fn sameType(state: anytype, left: u64, right: u64, use_strcmp: bool) bool {
    if (left == 0 or right == 0) return false;
    if (left == right) return true;
    if (!use_strcmp) return false;
    const left_name = typeName(state, left) orelse return false;
    const right_name = typeName(state, right) orelse return false;
    return std.mem.eql(u8, left_name, right_name);
}

fn hasPrintableName(state: anytype, type_info: u64) bool {
    const name = typeName(state, type_info) orelse return false;
    if (name.len == 0) return false;
    // Itanium mangled names use a restricted alphabet; anything outside it in
    // the leading byte means the pointer landed in unrelated data.
    return std.ascii.isAlphanumeric(name[0]) or name[0] == '_';
}

const Executability = enum { unknown, executable, data };

fn executability(state: anytype, address: u64) Executability {
    // Bound at comptime so the call below is never analyzed for a state that
    // cannot answer the question — the unwinder's own fake guest, for one.
    const has_oracle = comptime hasExecutableOracle(@TypeOf(state));
    if (!has_oracle) return .unknown;
    return if (state.isExecutableAddress(address)) .executable else .data;
}

fn hasExecutableOracle(comptime State: type) bool {
    const Child = switch (@typeInfo(State)) {
        .pointer => |pointer| pointer.child,
        else => State,
    };
    return switch (@typeInfo(Child)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(Child, "isExecutableAddress"),
        else => false,
    };
}

pub fn guestSlice(state: anytype, address: u64, count: u64) ?[]const u8 {
    return state.guestMemoryConst(address, count);
}

pub fn guestString(state: anytype, address: u64) ?[]const u8 {
    if (address == 0) return null;
    return state.guestCString(address, 1024);
}

pub fn readPointer(state: anytype, address: u64) ?u64 {
    const bytes = guestSlice(state, address, 8) orelse return null;
    return std.mem.readInt(u64, bytes[0..8], .little);
}

pub fn readSigned(state: anytype, address: u64) ?i64 {
    return @bitCast(readPointer(state, address) orelse return null);
}

pub fn addSigned(address: u64, offset: i64) u64 {
    return address +% @as(u64, @bitCast(offset));
}

const testing = @import("testing.zig");

test "a leaf record is not mistaken for single inheritance because RTTI is packed" {
    // Two records laid out back to back, exactly as a compiler emits them into
    // the RTTI section. `leaf + 16` is the *second* record's vtable pointer.
    var state = testing.State{};
    const rtti_vtable = 0x400;
    const leaf = 0x100;
    const neighbour = 0x110;
    state.write64(leaf, rtti_vtable);
    state.write64(leaf + 8, 0x300);
    state.write64(neighbour, rtti_vtable);
    state.write64(neighbour + 8, 0x310);
    state.writeString(0x300, "1A");
    state.writeString(0x310, "1B");

    // Give the vtable a word at +8 that reads back as a printable string, so
    // the cheap "does it have a name?" test says yes to it and cannot be what
    // rejects it. Only the executability of the vtable's first slot can.
    state.write64(rtti_vtable + 8, 0x320);
    state.writeString(0x320, "Zpasses_the_name_test");
    state.write64(rtti_vtable, 0x1200); // first virtual function: code
    state.executable_from = 0x1000;

    var reader = Reader{};
    try std.testing.expectEqual(Kind.leaf, reader.kindOf(&state, leaf));

    // And once the vtable is known, membership alone settles it.
    var learned = Reader{};
    learned.observe(&state, neighbour);
    try std.testing.expectEqual(Kind.leaf, learned.kindOf(&state, leaf));
}

test "single inheritance survives the same layout when the base is a real record" {
    var state = testing.State{};
    const rtti_vtable = 0x400;
    const derived = 0x100;
    const base = 0x200;
    state.write64(derived, rtti_vtable);
    state.write64(derived + 8, 0x300);
    state.write64(derived + 16, base);
    state.write64(base, rtti_vtable);
    state.write64(base + 8, 0x310);
    state.writeString(0x300, "7Derived");
    state.writeString(0x310, "4Base");
    state.executable_from = 0x1000;
    state.write64(rtti_vtable, 0x1200);

    var reader = Reader{};
    reader.observe(&state, derived);
    try std.testing.expectEqual(Kind.single_inheritance, reader.kindOf(&state, derived));
    try std.testing.expectEqual(Kind.leaf, reader.kindOf(&state, base));
}

test "a libc++abi symbol on the RTTI vtable settles the kind for every record sharing it" {
    const symbols = [_]testing.SymbolAt{
        .{ .address = 0x400, .name = "__ZTVN10__cxxabiv121__vmi_class_type_infoE" },
    };
    var state = testing.State{ .metadata = .{ .symbols = &symbols } };
    state.writeTypeInfo(0x100, 0x400, 0x700, "5First");
    state.writeTypeInfo(0x140, 0x400, 0x730, "6Second");
    // Deliberately no base list: without the symbol, layout inference would
    // read the zeroes at +16 and call both of these leaves.
    var reader = Reader{};
    try std.testing.expectEqual(Kind.multiple_inheritance, reader.kindOf(&state, 0x100));
    try std.testing.expectEqual(Kind.multiple_inheritance, reader.kindOf(&state, 0x140));
    try std.testing.expect(reader.isKnownVtable(0x400));
}

test "a binding on the record itself classifies it when no symbol names the vtable" {
    const bindings = [_]testing.Binding{
        .{ .address = 0x100, .name = "__ZTVN10__cxxabiv120__si_class_type_infoE" },
    };
    var state = testing.State{ .metadata = .{ .bindings = &bindings } };
    state.writeTypeInfo(0x100, 0x400, 0x700, "7Derived");
    state.writeTypeInfo(0x140, 0x400, 0x730, "4Base");
    state.write64(0x100 + 16, 0x140);

    var reader = Reader{};
    const bases = reader.basesOf(&state, 0x100).?;
    try std.testing.expectEqual(Kind.single_inheritance, bases.kind);
    try std.testing.expectEqual(@as(u32, 1), bases.count);
    const base = reader.baseAt(&state, 0x100, bases, 0).?;
    try std.testing.expectEqual(@as(u64, 0x140), base.type_info);
    try std.testing.expect(base.is_public and !base.is_virtual);
}

test "records that name one class compare equal only when names are consulted" {
    var state = testing.State{};
    const first = 0x100;
    const second = 0x200;
    state.write64(first + 8, 0x300);
    state.write64(second + 8, 0x340);
    state.writeString(0x300, "N2xe9threading10WaitHandleE");
    state.writeString(0x340, "N2xe9threading10WaitHandleE");

    try std.testing.expect(!sameType(&state, first, second, false));
    try std.testing.expect(sameType(&state, first, second, true));
    try std.testing.expect(sameType(&state, first, first, false));
}
