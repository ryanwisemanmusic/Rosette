//! Do the subsystems actually reach each other, and can the guest ask us what
//! it needs to ask?
//!
//! The defect this exists for
//! --------------------------
//! `prelaunch_audit` answers whether a subsystem is *present*. Present is not
//! connected: two stages can both link and never call one another, and a
//! refactor that empties the path from swap to the presenter leaves every
//! symbol count unchanged. Finding that out currently costs a full boot.
//!
//! ## An absent edge is not a finding
//!
//! This walks the image's direct calls, which is the honest half of the
//! question. A direct call graph cannot see indirect dispatch: a title reaches
//! the video exports through the kernel's ordinal table, and the emulator
//! reaches its backends through vtables. Neither leaves a `call rel32` behind.
//! Measured on a build that reaches graphics, `kernel -> gpu-bootstrap` is
//! **zero**, and reading that as a disconnection would be wrong.
//!
//! So the matrix is reported as observation, and the only finding raised is the
//! **loss** of a link that a working build had. That is a regression detector,
//! not a completeness prover, and it is careful not to pretend otherwise.
//!
//! ## The scan is a validated byte scan, not a disassembler
//!
//! `E8`/`E9` with a 32-bit displacement, kept only when the target is exactly
//! the address of a known symbol inside `__text`. Compiler-generated calls land
//! on function entries, so requiring an exact hit rejects essentially every
//! coincidental byte pair without needing to decode the instruction stream.
//!
//! ## What the guest asks for by name
//!
//! The same pass resolves the string operand of every `getenv` call site, which
//! turns "what does the guest need from its host" into a list read out of the
//! binary rather than a list someone remembered to maintain. That is how the
//! run-identity handshake becomes checkable before launch instead of after a
//! refusal.

const std = @import("std");
const contract = @import("xenia_prelaunch_audit_contract");

pub const Stage = contract.Stage;
/// The links a working build had, for a reader that wants them in order.
pub const contract_links = contract.observed_links;
const stage_slots = @typeInfo(Stage).@"enum".fields.len;

/// Enough for every name a guest realistically reads; the surface measured on
/// a real title is fifteen.
pub const max_environment_names: usize = 64;
/// Longest plausible environment variable name.
pub const max_environment_name_bytes: usize = 64;
/// How far back from a call site to look for the instruction that loaded its
/// argument. Compilers place it within a few instructions; beyond this the
/// answer would be a guess.
pub const argument_search_bytes: usize = 48;

pub const EnvironmentUse = struct {
    name: []const u8 = "",
    sites: u16 = 0,
    /// The guest cannot start without this one.
    required: bool = false,
    /// Rosette can answer it if asked.
    answerable: bool = false,
};

pub const Findings = struct {
    edges: [stage_slots][stage_slots]u32 = [_][stage_slots]u32{[_]u32{0} ** stage_slots} ** stage_slots,
    direct_edges: u32 = 0,
    symbols: u32 = 0,
    text_bytes: u64 = 0,
    /// Links a working build had that this one does not.
    lost_links: u8 = 0,
    first_lost: ?contract.StageLink = null,
    environment: [max_environment_names]EnvironmentUse = [_]EnvironmentUse{.{}} ** max_environment_names,
    environment_count: u8 = 0,
    /// Required names the guest asks for that Rosette could not answer.
    unanswerable_required: u8 = 0,
    first_unanswerable: []const u8 = "",
    /// More names were found than there was room to record.
    environment_overflow: bool = false,
    elapsed_ns: u64 = 0,

    pub fn edgeCount(self: *const Findings, from: Stage, to: Stage) u32 {
        return self.edges[@intFromEnum(from)][@intFromEnum(to)];
    }

    pub fn names(self: *const Findings) []const EnvironmentUse {
        return self.environment[0..self.environment_count];
    }

    /// Whether anything here should stop a launch.
    ///
    /// Only the environment contract can. A lost call edge is worth reading and
    /// worth investigating, but the graph is over-approximate in the direction
    /// that matters — it cannot see indirect dispatch — so refusing a run over
    /// one would be refusing on incomplete evidence.
    pub fn blocksLaunch(self: *const Findings) bool {
        return self.unanswerable_required != 0;
    }
};

pub const Options = struct {
    /// Whether Rosette's run identity is sealed. Only a fallback for callers
    /// that cannot supply `answer`.
    identity_sealed: bool = false,
    context: ?*anyopaque = null,
    /// Answer a name exactly as the guest's own lookup will.
    ///
    /// This exists because the first version of this audit did not have it. It
    /// decided answerability from `identity_sealed` — a proxy — and reported
    /// the run identity readable on a run where the guest could not read it,
    /// then printed PASS. An audit that concludes from anything but the
    /// answering code has only checked its own assumption.
    answer: ?*const fn (context: ?*anyopaque, name: []const u8) bool = null,
};

/// What the scan needs from an image, with the reading left to the caller.
pub const Image = struct {
    text_address: u64 = 0,
    text_bytes: []const u8 = &.{},
    /// Ascending, and the same length as `symbol_stages`.
    symbol_addresses: []const u64 = &.{},
    symbol_stages: []const Stage = &.{},
    /// Address of the `getenv` import stub, or zero when the image has none.
    getenv_stub: u64 = 0,
    context: ?*anyopaque = null,
    readCString: ?*const fn (context: ?*anyopaque, address: u64) ?[]const u8 = null,
};

fn monotonicNanoseconds() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}

/// Index of the greatest address not above `address`, or null when there is
/// none.
fn owningSymbol(addresses: []const u64, address: u64) ?usize {
    if (addresses.len == 0 or address < addresses[0]) return null;
    var low: usize = 0;
    var high: usize = addresses.len;
    while (low + 1 < high) {
        const middle = low + (high - low) / 2;
        if (addresses[middle] <= address) low = middle else high = middle;
    }
    return low;
}

fn exactSymbol(addresses: []const u64, address: u64) ?usize {
    const index = owningSymbol(addresses, address) orelse return null;
    return if (addresses[index] == address) index else null;
}

/// Whether a resolved string is shaped like an environment variable name.
fn looksLikeEnvironmentName(text: []const u8) bool {
    if (text.len == 0 or text.len >= max_environment_name_bytes) return false;
    if (!std.ascii.isAlphabetic(text[0]) and text[0] != '_') return false;
    for (text) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn recordEnvironmentName(findings: *Findings, name: []const u8, options: Options) void {
    for (findings.environment[0..findings.environment_count]) |*existing| {
        if (std.mem.eql(u8, existing.name, name)) {
            existing.sites +|= 1;
            return;
        }
    }
    if (findings.environment_count >= max_environment_names) {
        findings.environment_overflow = true;
        return;
    }
    const required = contract.environmentNameIsRequired(name);
    const answerable = if (options.answer) |resolve|
        resolve(options.context, name)
    else if (required)
        options.identity_sealed
    else
        hostHasName(name);
    findings.environment[findings.environment_count] = .{
        .name = name,
        .sites = 1,
        .required = required,
        .answerable = answerable,
    };
    findings.environment_count += 1;
    if (required and !answerable) {
        findings.unanswerable_required +|= 1;
        if (findings.first_unanswerable.len == 0) findings.first_unanswerable = name;
    }
}

fn hostHasName(name: []const u8) bool {
    if (name.len >= max_environment_name_bytes) return false;
    var buffer: [max_environment_name_bytes]u8 = undefined;
    @memcpy(buffer[0..name.len], name);
    buffer[name.len] = 0;
    return std.c.getenv(buffer[0..name.len :0]) != null;
}

/// Resolve the string a `lea rdi, [rip+disp32]` before `call_site` loaded.
///
/// `48 8D 3D` is REX.W + LEA with a RIP-relative ModRM naming RDI — the first
/// integer argument. Searching backwards from nearest to furthest takes the
/// load that actually feeds this call rather than one feeding an earlier one.
fn argumentStringAddress(image: Image, call_offset: usize) ?u64 {
    var back: usize = 7;
    while (back <= argument_search_bytes) : (back += 1) {
        if (back > call_offset) return null;
        const at = call_offset - back;
        if (at + 7 > image.text_bytes.len) continue;
        if (image.text_bytes[at] != 0x48 or
            image.text_bytes[at + 1] != 0x8D or
            image.text_bytes[at + 2] != 0x3D) continue;
        const displacement = std.mem.readInt(i32, image.text_bytes[at + 3 ..][0..4], .little);
        const next = image.text_address + at + 7;
        return if (displacement < 0)
            next -% @as(u64, @intCast(-@as(i64, displacement)))
        else
            next +% @as(u64, @intCast(displacement));
    }
    return null;
}

pub fn scan(image: Image, options: Options) Findings {
    const started_ns = monotonicNanoseconds();
    var findings = Findings{
        .symbols = @intCast(image.symbol_addresses.len),
        .text_bytes = image.text_bytes.len,
    };

    const bytes = image.text_bytes;
    var offset: usize = 0;
    while (offset + 5 <= bytes.len) {
        const opcode = bytes[offset];
        if (opcode != 0xE8 and opcode != 0xE9) {
            offset += 1;
            continue;
        }
        const displacement = std.mem.readInt(i32, bytes[offset + 1 ..][0..4], .little);
        const next = image.text_address + offset + 5;
        const target = if (displacement < 0)
            next -% @as(u64, @intCast(-@as(i64, displacement)))
        else
            next +% @as(u64, @intCast(displacement));

        if (image.getenv_stub != 0 and target == image.getenv_stub) {
            if (argumentStringAddress(image, offset)) |string_address| {
                if (image.readCString) |read| {
                    if (read(image.context, string_address)) |text| {
                        if (looksLikeEnvironmentName(text)) {
                            recordEnvironmentName(&findings, text, options);
                        }
                    }
                }
            }
        } else if (exactSymbol(image.symbol_addresses, target)) |target_index| {
            if (owningSymbol(image.symbol_addresses, image.text_address + offset)) |source_index| {
                const from = image.symbol_stages[source_index];
                const to = image.symbol_stages[target_index];
                findings.edges[@intFromEnum(from)][@intFromEnum(to)] +|= 1;
                findings.direct_edges +|= 1;
            }
        }
        offset += 5;
    }

    for (contract.observed_links) |link| {
        if (findings.edgeCount(link.from, link.to) == 0) {
            findings.lost_links +|= 1;
            if (findings.first_lost == null) findings.first_lost = link;
        }
    }

    const finished_ns = monotonicNanoseconds();
    findings.elapsed_ns = if (finished_ns > started_ns) finished_ns - started_ns else 0;
    return findings;
}

/// Build an `Image` from a loaded Mach-O and scan it.
///
/// `metadata` is duck-typed so the audit does not drag the Mach-O reader into
/// every consumer. The caller owns the returned findings; the strings inside
/// them point into the mapped image, which outlives the audit.
pub fn auditImage(
    allocator: std.mem.Allocator,
    metadata: anytype,
    options: Options,
) !Findings {
    const Meta = @TypeOf(metadata);
    const Reader = struct {
        meta: Meta,

        fn read(context: ?*anyopaque, address: u64) ?[]const u8 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            const section = self.meta.sectionAtAddress(address) orelse return null;
            const bytes = self.meta.sectionBytes(section) orelse return null;
            if (address < section.address) return null;
            const start: usize = @intCast(address - section.address);
            if (start >= bytes.len) return null;
            const limit = @min(bytes.len, start + max_environment_name_bytes);
            const window = bytes[start..limit];
            const end = std.mem.indexOfScalar(u8, window, 0) orelse return null;
            return window[0..end];
        }
    };

    const text = metadata.sectionNamed("__TEXT", "__text") orelse return Findings{};
    const text_bytes = metadata.sectionBytes(text) orelse return Findings{};

    const Entry = struct {
        address: u64,
        stage: Stage,
        fn lessThan(_: void, lhs: @This(), rhs: @This()) bool {
            return lhs.address < rhs.address;
        }
    };
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(allocator);

    var symbols = metadata.definedSymbolIterator();
    while (symbols.next()) |entry| {
        const address = entry.value_ptr.*;
        if (address < text.address or address >= text.address + text.size) continue;
        try entries.append(allocator, .{
            .address = address,
            .stage = contract.classify(entry.key_ptr.*),
        });
    }
    std.mem.sort(Entry, entries.items, {}, Entry.lessThan);

    const addresses = try allocator.alloc(u64, entries.items.len);
    defer allocator.free(addresses);
    const stages = try allocator.alloc(Stage, entries.items.len);
    defer allocator.free(stages);
    for (entries.items, 0..) |entry, index| {
        addresses[index] = entry.address;
        stages[index] = entry.stage;
    }

    // The stub is what a call site actually targets; the lazy pointer is not.
    var getenv_stub: u64 = 0;
    for (metadata.imports) |imported| {
        if (std.mem.eql(u8, imported.name, "_getenv") and imported.stub_address != 0) {
            getenv_stub = imported.stub_address;
            break;
        }
    }

    var reader = Reader{ .meta = metadata };
    return scan(.{
        .text_address = text.address,
        .text_bytes = text_bytes,
        .symbol_addresses = addresses,
        .symbol_stages = stages,
        .getenv_stub = getenv_stub,
        .context = @ptrCast(&reader),
        .readCString = Reader.read,
    }, options);
}

// ---------------------------------------------------------------------------
// Tests. The scan is driven through a synthetic image so its decisions are
// checkable without a seventy-megabyte binary or a particular build of one.
// ---------------------------------------------------------------------------

const TestStrings = struct {
    address: u64 = 0,
    text: []const u8 = "",

    fn read(context: ?*anyopaque, address: u64) ?[]const u8 {
        const self: *TestStrings = @ptrCast(@alignCast(context.?));
        return if (address == self.address) self.text else null;
    }
};

/// Append `call rel32` to `target` at the current end of `code`.
fn appendCall(code: []u8, at: usize, base: u64, target: u64) void {
    code[at] = 0xE8;
    const next: i64 = @intCast(base + at + 5);
    const delta: i32 = @intCast(@as(i64, @intCast(target)) - next);
    std.mem.writeInt(i32, code[at + 1 ..][0..4], delta, .little);
}

test "a call between two stages is counted as an edge between them" {
    const base: u64 = 0x1000;
    var code = [_]u8{0x90} ** 64;
    // A call from the body of the first symbol into the second's entry.
    appendCall(&code, 8, base, 0x1020);

    const addresses = [_]u64{ 0x1000, 0x1020 };
    const stages = [_]Stage{ .gpu_bootstrap, .command_processor };

    const findings = scan(.{
        .text_address = base,
        .text_bytes = &code,
        .symbol_addresses = &addresses,
        .symbol_stages = &stages,
    }, .{});

    try std.testing.expectEqual(@as(u32, 1), findings.direct_edges);
    try std.testing.expectEqual(@as(u32, 1), findings.edgeCount(.gpu_bootstrap, .command_processor));
    try std.testing.expectEqual(@as(u32, 0), findings.edgeCount(.command_processor, .gpu_bootstrap));
}

test "a call that does not land on a symbol entry is rejected" {
    const base: u64 = 0x1000;
    var code = [_]u8{0x90} ** 64;
    // Lands one byte into the second symbol: not a function entry, so it is a
    // coincidence rather than a call. This is what keeps a byte scan honest.
    appendCall(&code, 8, base, 0x1021);

    const addresses = [_]u64{ 0x1000, 0x1020 };
    const stages = [_]Stage{ .gpu_bootstrap, .command_processor };

    const findings = scan(.{
        .text_address = base,
        .text_bytes = &code,
        .symbol_addresses = &addresses,
        .symbol_stages = &stages,
    }, .{});
    try std.testing.expectEqual(@as(u32, 0), findings.direct_edges);
}

test "every link a working build had is reported lost when the graph is empty" {
    const findings = scan(.{}, .{});
    // An image with no code loses all of them, which is the degenerate case and
    // still must name one rather than silently pass.
    try std.testing.expectEqual(@as(u8, contract.observed_links.len), findings.lost_links);
    try std.testing.expect(findings.first_lost != null);
    // A lost edge never refuses a run: the graph cannot see indirect dispatch.
    try std.testing.expect(!findings.blocksLaunch());
}

test "a getenv call site resolves the name its argument pointed at" {
    const base: u64 = 0x1000;
    const stub: u64 = 0x2000;
    var code = [_]u8{0x90} ** 64;
    // lea rdi, [rip+disp32] -> 0x3000, then call the getenv stub.
    code[8] = 0x48;
    code[9] = 0x8D;
    code[10] = 0x3D;
    const after_lea: i64 = @intCast(base + 15);
    std.mem.writeInt(i32, code[11..15], @intCast(@as(i64, 0x3000) - after_lea), .little);
    appendCall(&code, 15, base, stub);

    var strings = TestStrings{ .address = 0x3000, .text = "ROSETTE_RUN_ID" };
    const addresses = [_]u64{0x1000};
    const stages = [_]Stage{.kernel};

    const findings = scan(.{
        .text_address = base,
        .text_bytes = &code,
        .symbol_addresses = &addresses,
        .symbol_stages = &stages,
        .getenv_stub = stub,
        .context = @ptrCast(&strings),
        .readCString = TestStrings.read,
    }, .{ .identity_sealed = true });

    try std.testing.expectEqual(@as(u8, 1), findings.environment_count);
    try std.testing.expectEqualStrings("ROSETTE_RUN_ID", findings.names()[0].name);
    try std.testing.expect(findings.names()[0].required);
    try std.testing.expect(findings.names()[0].answerable);
    try std.testing.expectEqual(@as(u8, 0), findings.unanswerable_required);
    try std.testing.expect(!findings.blocksLaunch());
    // A getenv call is not a stage edge.
    try std.testing.expectEqual(@as(u32, 0), findings.direct_edges);
}

test "a required name the run cannot answer refuses the launch and names itself" {
    const base: u64 = 0x1000;
    const stub: u64 = 0x2000;
    var code = [_]u8{0x90} ** 64;
    code[8] = 0x48;
    code[9] = 0x8D;
    code[10] = 0x3D;
    const after_lea: i64 = @intCast(base + 15);
    std.mem.writeInt(i32, code[11..15], @intCast(@as(i64, 0x3000) - after_lea), .little);
    appendCall(&code, 15, base, stub);

    var strings = TestStrings{ .address = 0x3000, .text = "ROSETTE_MANIFEST_HASH" };
    const addresses = [_]u64{0x1000};
    const stages = [_]Stage{.kernel};

    // The identity is not sealed, so the guest would read this as unset and
    // refuse its own start — which is the failure this check exists to move
    // forward to here.
    const findings = scan(.{
        .text_address = base,
        .text_bytes = &code,
        .symbol_addresses = &addresses,
        .symbol_stages = &stages,
        .getenv_stub = stub,
        .context = @ptrCast(&strings),
        .readCString = TestStrings.read,
    }, .{ .identity_sealed = false });

    try std.testing.expectEqual(@as(u8, 1), findings.unanswerable_required);
    try std.testing.expectEqualStrings("ROSETTE_MANIFEST_HASH", findings.first_unanswerable);
    try std.testing.expect(findings.blocksLaunch());
}

test "a string that is not shaped like a variable name is not recorded as one" {
    const base: u64 = 0x1000;
    const stub: u64 = 0x2000;
    var code = [_]u8{0x90} ** 64;
    code[8] = 0x48;
    code[9] = 0x8D;
    code[10] = 0x3D;
    const after_lea: i64 = @intCast(base + 15);
    std.mem.writeInt(i32, code[11..15], @intCast(@as(i64, 0x3000) - after_lea), .little);
    appendCall(&code, 15, base, stub);

    var strings = TestStrings{ .address = 0x3000, .text = "/Users/someone/a path" };
    const addresses = [_]u64{0x1000};
    const stages = [_]Stage{.kernel};

    const findings = scan(.{
        .text_address = base,
        .text_bytes = &code,
        .symbol_addresses = &addresses,
        .symbol_stages = &stages,
        .getenv_stub = stub,
        .context = @ptrCast(&strings),
        .readCString = TestStrings.read,
    }, .{});
    try std.testing.expectEqual(@as(u8, 0), findings.environment_count);
}

test "repeated reads of one name are counted as sites, not as separate names" {
    var findings = Findings{};
    recordEnvironmentName(&findings, "TMPDIR", .{});
    recordEnvironmentName(&findings, "TMPDIR", .{});
    recordEnvironmentName(&findings, "HOME", .{});
    try std.testing.expectEqual(@as(u8, 2), findings.environment_count);
    try std.testing.expectEqual(@as(u16, 2), findings.names()[0].sites);
    try std.testing.expectEqual(@as(u16, 1), findings.names()[1].sites);
}

test "owning symbol is the entry the address falls inside, not the nearest" {
    const addresses = [_]u64{ 0x1000, 0x2000, 0x3000 };
    try std.testing.expectEqual(@as(usize, 0), owningSymbol(&addresses, 0x1000).?);
    try std.testing.expectEqual(@as(usize, 0), owningSymbol(&addresses, 0x1fff).?);
    try std.testing.expectEqual(@as(usize, 1), owningSymbol(&addresses, 0x2000).?);
    try std.testing.expectEqual(@as(usize, 2), owningSymbol(&addresses, 0x9999).?);
    // Below the first symbol there is no owner to name.
    try std.testing.expect(owningSymbol(&addresses, 0x0fff) == null);
    try std.testing.expect(exactSymbol(&addresses, 0x2000) != null);
    try std.testing.expect(exactSymbol(&addresses, 0x2001) == null);
}

test "answerability comes from the answering code when one is supplied" {
    const Resolver = struct {
        // Sealed identity, and yet this name cannot be answered — exactly the
        // shape of the run this test exists for.
        fn answer(_: ?*anyopaque, name: []const u8) bool {
            return !std.mem.eql(u8, name, "ROSETTE_BACKEND");
        }
    };
    var findings = Findings{};
    const options = Options{ .identity_sealed = true, .answer = Resolver.answer };
    recordEnvironmentName(&findings, "ROSETTE_RUN_ID", options);
    recordEnvironmentName(&findings, "ROSETTE_BACKEND", options);

    try std.testing.expect(findings.names()[0].answerable);
    // The proxy would have said yes here because the identity is sealed.
    try std.testing.expect(!findings.names()[1].answerable);
    try std.testing.expect(findings.blocksLaunch());
    try std.testing.expectEqualStrings("ROSETTE_BACKEND", findings.first_unanswerable);
}

test "without a resolver the audit falls back rather than inventing an answer" {
    var findings = Findings{};
    recordEnvironmentName(&findings, "ROSETTE_RUN_ID", .{ .identity_sealed = false });
    try std.testing.expect(!findings.names()[0].answerable);
    try std.testing.expect(findings.blocksLaunch());
}
