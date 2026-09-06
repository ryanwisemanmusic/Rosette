//! Where the run's host time actually goes, sampled from the guest program
//! counter it was already printing.
//!
//! ## The gap this closes
//!
//! `RUN BUDGET` says the run is below its rate and names a *phase*
//! (`guest-execution`). That is true and it is the whole address space: on
//! 2026-09-01 the run was at two guest milliseconds per host second and the
//! phase table said the time went to running the guest, which is where it
//! always goes.
//!
//! The answer a reader needs is one level down — *which guest code* — and the
//! heartbeat has been printing it once every hundred million steps for the
//! whole run. Eighty-three lines, each naming one symbol, scattered through
//! seventy-six thousand. Aggregating them by hand is the difference between
//! "the run is slow" and "two thirds of the samples are inside the emulator's
//! own PowerPC JIT, so the cost is double translation and not a defect".
//!
//! ## What it is and is not
//!
//! It is a sampling profiler with a very low rate, and the report says the
//! sample count so nobody reads a share as a measurement. Twelve samples out of
//! eighty is a strong signal about where a run lives; three out of five is
//! nothing, and the difference has to be visible in the row rather than known
//! by the reader.
//!
//! It never allocates and never grows: a fixed table, a linear scan over it per
//! sample, and everything past the table is counted rather than dropped
//! silently. The sample site is a heartbeat that already resolved the symbol,
//! so the cost of the whole thing is a comparison per retained entry, a few
//! dozen times per run.

const std = @import("std");

/// Distinct symbols retained. Wide enough that a run with a genuinely diffuse
/// profile still shows its shape, small enough that the scan stays trivial.
pub const max_symbols: usize = 64;

/// What kind of code a sample landed in.
///
/// Deliberately coarse and derived from the symbol's own name rather than from
/// an address: an address table would be a fact about one build of one
/// emulator, and the question — is this run translating, running, waiting or
/// logging — is the same for any guest.
pub const Region = enum(u8) {
    /// Nothing matched. The honest default, and never folded into a neighbour.
    unclassified,
    /// The guest is compiling its own guest's code. Under a second translation
    /// layer this is the cost that dominates and the one most often mistaken
    /// for a defect.
    guest_code_generation,
    /// The sample landed in code the emulator *generated* and is now running,
    /// rather than in code that was linked into it. No symbol can exist for
    /// such an address, so a name-only classifier reports it as a symbol-table
    /// gap and sends the reader to fix a symbol table that is not broken.
    ///
    /// It is the counterpart of `guest_code_generation` and the pair is the
    /// whole translation story: one is paying to compile, the other is
    /// collecting on it.
    guest_generated_code,
    /// The process entry frame — `main`, or the loader's entry into it.
    /// A sample here early is the run beginning; a run whose samples stay here
    /// never left its bootstrap, which is a finding rather than a shrug.
    guest_entry,
    /// The guest is waiting: a lock, a condition variable, a spin.
    guest_waiting,
    /// The guest is inside its own diagnostic plumbing.
    guest_logging,
    /// Memory management: allocation, mapping, heap bookkeeping.
    guest_memory,
    /// The emulator's own subsystems, outside the categories above: kernel
    /// shims, GPU plumbing, filesystem. Real work rather than a shrug.
    guest_emulation,
    /// The C++ runtime and the general-purpose primitives the emulator is
    /// built on — containers, atomics, hashing, checksums. Almost always a
    /// leaf of one of the categories above, and worth separating so it does
    /// not inflate `unclassified`.
    host_runtime,
    /// The sample landed where no symbol could be resolved *and* the address
    /// is inside the image, so one should have existed. A fact about the
    /// symbol table rather than a region, and never folded into a neighbour.
    /// An unnamed address outside the image is `guest_generated_code`, not
    /// this — collapsing the two sends the reader to repair a symbol table
    /// that is working.
    unresolved_symbol,

    pub fn label(self: Region) []const u8 {
        return switch (self) {
            .unclassified => "unclassified",
            .guest_code_generation => "guest-code-generation",
            .guest_generated_code => "guest-generated-code",
            .guest_entry => "guest-entry",
            .guest_waiting => "guest-waiting",
            .guest_logging => "guest-logging",
            .guest_memory => "guest-memory",
            .guest_emulation => "guest-emulation",
            .host_runtime => "host-runtime",
            .unresolved_symbol => "unresolved-symbol",
        };
    }

    /// What a run dominated by this region means, and what it does not.
    pub fn describe(self: Region) []const u8 {
        return switch (self) {
            .unclassified => "the samples did not match a known region. That is a gap in the classifier and not a statement about the run",
            .guest_code_generation => "the run is spending itself compiling the emulator's guest code. Under a second translation layer this is the expected dominant cost and it is not a defect — it bounds how much emulated time a run can buy, and the answer is a faster translation path rather than a fix",
            .guest_generated_code => "the run is executing code the emulator generated rather than code linked into it. That is the translation layer paying off and the healthiest place for a sample to land; no symbol can exist there, so it is not a symbol-table gap",
            .guest_entry => "the samples landed in the process entry frame. Early in a run that is the run starting; samples that stay here mean the run never left its bootstrap",
            .guest_waiting => "the run is spending itself waiting. A wait that dominates the samples is either a real dependency or a spin, and the wait ledgers below distinguish them",
            .guest_logging => "the run is spending itself inside the emulator's own diagnostics. An observer at this share is changing what it observes, and turning the emulator's log level down is a measurement change rather than a code change",
            .guest_memory => "the run is spending itself on allocation and mapping. Large here usually means a working set that does not fit rather than a slow allocator",
            .guest_emulation => "the run is spending itself inside the emulator's own subsystems. This is the emulator doing its job, and the question it raises is which subsystem rather than whether anything is wrong",
            .host_runtime => "the samples resolved to the C++ runtime and general-purpose primitives the emulator is built on. That is a leaf of whatever called it, so this share bounds how much of the profile is uninformative rather than naming a cost",
            .unresolved_symbol => "the samples landed inside the image where no symbol covers them. That is a gap in the symbol table, not a region, and it bounds how much of the profile is readable at all. An address outside the image is not this: it is generated code and has its own region",
        };
    }
};

/// Where the sampled address lives, as the runtime already knows it.
///
/// Supplied by the caller rather than derived here: the answer needs the
/// loaded image's section table and the run's own page permissions, and this
/// module must not depend on either. It exists because a name-only classifier
/// has one blind spot it can never close on its own — an address in memory the
/// run made executable at run time has no symbol and never will, and calling
/// that "unresolved" tells the reader to go and repair a symbol table that is
/// working perfectly.
pub const Origin = enum {
    /// The caller did not say. Classification falls back to the name alone,
    /// which is what every caller did before this channel existed.
    unstated,
    /// Inside a loaded image section. A name that could not be placed here is
    /// genuine classifier debt and a missing symbol is a genuine gap.
    image,
    /// Outside every image section, in memory the run made executable at run
    /// time. Under this runtime that is the emulator's own generated code.
    generated_code,
    /// Outside every image section and not executable: heap, stack, data.
    /// Deliberately not given a region — a program counter here is a runaway
    /// that the fault machinery owns, and inventing a region for it would hide
    /// exactly the thing this enum exists to stop hiding.
    outside_image_data,
};

/// Classify a symbol name into a region.
///
/// Substring matching on purpose. The names are C++ manglings and the parts
/// that identify the region — a namespace, a class — survive the mangling
/// intact, while anything stricter would have to know the mangling scheme.
pub fn regionOf(symbol: []const u8) Region {
    if (symbol.len == 0) return .unresolved_symbol;
    // A sample the symboliser could not name. Its own answer, because "no
    // symbol here" and "a symbol no rule matched" send a reader to completely
    // different work.
    if (std.mem.eql(u8, symbol, "<unknown>")) return .unresolved_symbol;

    // The process entry frame, matched exactly. A substring test would catch
    // every symbol with `main` in it, and the entry point is the one symbol
    // whose whole meaning is that it is the entry point.
    const entry = [_][]const u8{
        "main",               "_main",      "start",       "_start",
        "__start",            "dyld_start", "_dyld_start", "__libc_start_main",
        "_mh_execute_header",
    };
    for (entry) |name| {
        if (std.mem.eql(u8, symbol, name)) return .guest_entry;
    }

    // Specific first, and the order inside this pass is the classification:
    // a compiler pass that allocates is code generation, and a logging ring
    // that spins is logging.
    const generation = [_][]const u8{
        "compiler",  "HIRBuilder", "Xbyak",   "InstrEmit",     "Frontend",
        "Assembler", "Emitter",    "3hir",    "PPCTranslator", "CodeCache",
        "Opcode",    "Translate",  "Compile",
    };
    for (generation) |needle| {
        if (std.mem.indexOf(u8, symbol, needle) != null) return .guest_code_generation;
    }
    const logging = [_][]const u8{ "disruptorplus", "Logger", "logging", "XELOG", "LogLine" };
    for (logging) |needle| {
        if (std.mem.indexOf(u8, symbol, needle) != null) return .guest_logging;
    }
    const waiting = [_][]const u8{
        "spin_wait", "unique_lock", "condition_variable", "WaitFor",
        "Sleep",     "mutex",       "MacEvent",           "Semaphore",
    };
    for (waiting) |needle| {
        if (std.mem.indexOf(u8, symbol, needle) != null) return .guest_waiting;
    }
    const memory = [_][]const u8{ "Arena", "Heap", "allocator", "Alloc", "memcpy", "memset", "operatornw" };
    for (memory) |needle| {
        if (std.mem.indexOf(u8, symbol, needle) != null) return .guest_memory;
    }

    // Then the namespace the mangling carries. This is what turned two thirds
    // of the 2026-09-01 profile from `unclassified` into an answer: a sample
    // inside `xe::kernel` or `xe::gpu` is the emulator working, and one inside
    // `std::` is a leaf of whatever called it.
    const emulation = [_][]const u8{ "2xe6kernel", "2xe3gpu", "2xe3cpu", "2xe10filesystem", "2xe3vfs", "2xe9threading", "2xe4base", "N2xe" };
    for (emulation) |needle| {
        if (std.mem.indexOf(u8, symbol, needle) != null) return .guest_emulation;
    }
    // General-purpose data primitives statically linked into the emulator —
    // hashing, checksums, stream compression. Placed after the namespace pass
    // so an emulator function that mentions one still reads as emulator work,
    // and folded into `host_runtime` for the same reason the C++ runtime is:
    // each is a leaf of whatever called it, and a leaf names no cost of its
    // own.
    const support = [_][]const u8{
        "XXH",     "xxhash",  "MurmurHash", "crc32",
        "adler32", "inflate", "deflate",    "llvm",
        "LLVM",    "3fmt",    "4utf8",
    };
    for (support) |needle| {
        if (std.mem.indexOf(u8, symbol, needle) != null) return .host_runtime;
    }

    if (std.mem.indexOf(u8, symbol, "St3__1") != null) return .host_runtime;
    if (std.mem.indexOf(u8, symbol, "_ZNSt") != null) return .host_runtime;
    return .unclassified;
}

/// Classify a sample from its symbol and, where the name has no answer, from
/// where the address lives.
///
/// The name outranks the address on purpose: the address only says which
/// mapping the code sits in, and the name says what the code does. The origin
/// is consulted for exactly the two outcomes that are not answers —
/// `unclassified` and `unresolved_symbol` — so it can never overwrite a
/// classification the name earned.
pub fn classifyAt(symbol: []const u8, origin: Origin) Region {
    const by_name = regionOf(symbol);
    switch (by_name) {
        .unclassified, .unresolved_symbol => {},
        else => return by_name,
    }
    return switch (origin) {
        .generated_code => .guest_generated_code,
        .unstated, .image, .outside_image_data => by_name,
    };
}

pub const Entry = struct {
    /// Borrowed from the loaded image's symbol table, which outlives the run.
    name: []const u8 = "",
    region: Region = .unclassified,
    samples: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// One address inside the symbol, so a reader can disassemble rather than
    /// only read a name.
    witness_rip: u64 = 0,
};

pub const Summary = struct {
    samples: u64 = 0,
    distinct: usize = 0,
    /// Samples whose symbol did not fit the table. Reported because a profile
    /// built from a table that silently dropped its tail would understate how
    /// diffuse the run is. The region totals below are unaffected: they cover
    /// every sample.
    unretained: u64 = 0,
    by_region: [region_count]u64 = [_]u64{0} ** region_count,

    /// Whether there are enough samples for a share to mean anything.
    ///
    /// A very low sample rate is the price of costing nothing, and the report
    /// has to carry the consequence rather than leave a reader to infer it
    /// from a percentage that looks like a measurement.
    pub fn readable(self: Summary) bool {
        return self.samples >= 20;
    }

    pub fn percentOf(self: Summary, count: u64) u64 {
        if (self.samples == 0) return 0;
        return (count *| 100) / self.samples;
    }

    /// The region holding the most samples, when one does.
    pub fn dominantRegion(self: Summary) ?Region {
        var best: ?Region = null;
        var best_count: u64 = 0;
        for (self.by_region, 0..) |count, index| {
            if (count <= best_count) continue;
            best_count = count;
            best = @enumFromInt(index);
        }
        return best;
    }

    /// Share of the samples the classifier could not place, in percent.
    ///
    /// The profile's own error bar. A dominant region announced next to a
    /// large residue is a statement about the classifier, and a reader has to
    /// see both numbers or neither.
    pub fn unaccountedPercent(self: Summary) u64 {
        const unaccounted = self.by_region[@intFromEnum(Region.unclassified)] +|
            self.by_region[@intFromEnum(Region.unresolved_symbol)];
        return self.percentOf(unaccounted);
    }

    /// Whether the dominant region outweighs what the classifier could not
    /// place. When it does not, the profile has not identified anything and
    /// saying so is the honest report.
    pub fn dominantIsDecisive(self: Summary) bool {
        if (!self.readable()) return false;
        const region = self.dominantRegion() orelse return false;
        if (region == .unclassified or region == .unresolved_symbol) return false;
        return self.percentOf(self.by_region[@intFromEnum(region)]) > self.unaccountedPercent();
    }
};

pub const region_count: usize = @typeInfo(Region).@"enum".fields.len;

pub const Ledger = struct {
    entries: [max_symbols]Entry = [_]Entry{.{}} ** max_symbols,
    count: usize = 0,
    samples: u64 = 0,
    unretained: u64 = 0,
    /// Region totals over *every* sample, retained or not.
    ///
    /// Accumulated here rather than derived from the retained entries. The
    /// first version of this summed the table, so a run whose symbol table
    /// filled contributed nothing from that point on: the 2026-09-01 report
    /// read `samples=87 unretained=53 dominant=unclassified dominant_share=20%`
    /// — a share computed from a third of the evidence, for a profile whose
    /// whole purpose is the share.
    region_samples: [region_count]u64 = [_]u64{0} ** region_count,

    /// Record one sample from a caller that cannot say where the address
    /// lives. Classification falls back to the name alone.
    pub fn observe(self: *Ledger, symbol: []const u8, rip: u64, step: u64) void {
        self.observeAt(symbol, .unstated, rip, step);
    }

    /// Record one sample. O(max_symbols) against a fixed table, called from a
    /// heartbeat that already resolved the name.
    pub fn observeAt(
        self: *Ledger,
        symbol: []const u8,
        origin: Origin,
        rip: u64,
        step: u64,
    ) void {
        self.samples +|= 1;
        const region = classifyAt(symbol, origin);
        // Classify before deciding whether to retain: the region is the answer
        // and the symbol row is only how a reader gets to it.
        self.region_samples[@intFromEnum(region)] +|= 1;
        for (self.entries[0..self.count]) |*entry| {
            if (!std.mem.eql(u8, entry.name, symbol)) continue;
            // Every address outside the image answers to the same `<unknown>`,
            // so one row can cover samples from several origins. Keep the more
            // informative region rather than whichever arrived first.
            if (entry.region == .unclassified or entry.region == .unresolved_symbol) {
                entry.region = region;
            }
            entry.samples +|= 1;
            entry.last_step = step;
            return;
        }
        if (self.count >= max_symbols) {
            self.unretained +|= 1;
            return;
        }
        self.entries[self.count] = .{
            .name = symbol,
            .region = region,
            .samples = 1,
            .first_step = step,
            .last_step = step,
            .witness_rip = rip,
        };
        self.count += 1;
    }

    pub fn retained(self: *const Ledger) []const Entry {
        return self.entries[0..self.count];
    }

    pub fn summary(self: *const Ledger) Summary {
        return .{
            .samples = self.samples,
            .distinct = self.count,
            .unretained = self.unretained,
            .by_region = self.region_samples,
        };
    }

    /// The `wanted` busiest symbols, written into `out`, most samples first.
    /// Selection sort over a fixed table: `wanted` is a handful and the table
    /// is two dozen.
    pub fn hottest(self: *const Ledger, out: []Entry) usize {
        var written: usize = 0;
        var taken = [_]bool{false} ** max_symbols;
        while (written < out.len) {
            var best: ?usize = null;
            for (self.retained(), 0..) |entry, index| {
                if (taken[index]) continue;
                const held = best orelse {
                    best = index;
                    continue;
                };
                if (entry.samples > self.entries[held].samples) best = index;
            }
            const chosen = best orelse break;
            taken[chosen] = true;
            out[written] = self.entries[chosen];
            written += 1;
        }
        return written;
    }
};

test "an unsampled profile says nothing and admits it" {
    const ledger = Ledger{};
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 0), totals.samples);
    try std.testing.expect(!totals.readable());
    try std.testing.expectEqual(@as(u64, 0), totals.percentOf(5));
    var out: [4]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 0), ledger.hottest(&out));
}

// The 2026-09-01 profile: the heartbeat named the emulator's PowerPC JIT again
// and again, and the budget report said `dominant_phase=guest-execution`.
test "a run inside the emulator's own JIT is named as one" {
    var ledger = Ledger{};
    const jit = [_][]const u8{
        "__ZN2xe3cpu8compiler6passes18SimplificationPassC1Ev",
        "__ZN2xe3cpu3ppc13PPCHIRBuilderC1EPNS1_11PPCFrontendE",
        "__ZN5Xbyak4util3CpuC2Ev",
        "__ZN2xe3cpu3ppc12InstrEmit_bxERNS1_13PPCHIRBuilderERKNS1_9InstrDataE",
    };
    for (0..6) |round| {
        for (jit) |symbol| ledger.observe(symbol, 0x1000, 100 + round);
    }
    ledger.observe("__ZN13disruptorplus9spin_wait9spin_onceEv", 0x1a2420, 500);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 25), totals.samples);
    try std.testing.expect(totals.readable());
    try std.testing.expectEqual(Region.guest_code_generation, totals.dominantRegion().?);
    try std.testing.expectEqual(@as(u64, 24), totals.by_region[@intFromEnum(Region.guest_code_generation)]);
    try std.testing.expectEqual(@as(u64, 1), totals.by_region[@intFromEnum(Region.guest_logging)]);
    try std.testing.expectEqual(@as(u64, 96), totals.percentOf(24));
    try std.testing.expect(std.mem.indexOf(u8, Region.guest_code_generation.describe(), "not a defect") != null);
}

// A share computed from five samples is not a measurement, and the report has
// to be able to say so.
test "a profile with too few samples is not readable" {
    var ledger = Ledger{};
    for (0..5) |index| ledger.observe("__ZN2xe5Arena5AllocEmm", 0x2000, index);
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 5), totals.samples);
    try std.testing.expect(!totals.readable());
    // The share is still computed; the caller is told not to lean on it.
    try std.testing.expectEqual(@as(u64, 100), totals.percentOf(5));
    try std.testing.expectEqual(Region.guest_memory, totals.dominantRegion().?);
}

// A fixed table has to say what it could not hold, or a diffuse run looks
// concentrated.
// The regression the 2026-09-01 report exposed: with the region totals summed
// from the retained table, a run whose table filled contributed nothing from
// that point on, and the share the whole report exists to state was computed
// from a third of the evidence.
test "samples past the table still count toward their region" {
    var ledger = Ledger{};
    var buffer: [max_symbols + 8][64]u8 = undefined;
    for (0..max_symbols) |index| {
        const name = std.fmt.bufPrint(&buffer[index], "sym_{d}__ZN2xe6kernel4shimE", .{index}) catch unreachable;
        ledger.observe(name, index, index);
    }
    // Eight more distinct symbols, all past the table, all classifiable.
    for (max_symbols..max_symbols + 8) |index| {
        const name = std.fmt.bufPrint(&buffer[index], "over_{d}__ZN13disruptorplusE", .{index}) catch unreachable;
        ledger.observe(name, index, index);
    }

    const totals = ledger.summary();
    try std.testing.expectEqual(max_symbols, totals.distinct);
    try std.testing.expectEqual(@as(u64, 8), totals.unretained);
    try std.testing.expectEqual(@as(u64, max_symbols + 8), totals.samples);
    // The dropped rows are still in their region, which is the fix.
    try std.testing.expectEqual(@as(u64, 8), totals.by_region[@intFromEnum(Region.guest_logging)]);
    try std.testing.expectEqual(
        @as(u64, max_symbols),
        totals.by_region[@intFromEnum(Region.guest_emulation)],
    );
    // Every sample is in exactly one region.
    var total: u64 = 0;
    for (totals.by_region) |count| total += count;
    try std.testing.expectEqual(totals.samples, total);
}

// A dominant region announced next to a larger residue is a statement about
// the classifier, and the report has to be able to say which it is.
test "a dominant region is only decisive when it beats what was not placed" {
    var ledger = Ledger{};
    // Twelve placed, thirteen not: nothing has been identified.
    for (0..12) |index| ledger.observe("__ZN2xe3cpu8compiler6passesE", index, index);
    for (0..13) |index| ledger.observe("mystery_symbol", index, index);
    var totals = ledger.summary();
    try std.testing.expect(totals.readable());
    try std.testing.expectEqual(Region.unclassified, totals.dominantRegion().?);
    try std.testing.expect(!totals.dominantIsDecisive());
    try std.testing.expectEqual(@as(u64, 52), totals.unaccountedPercent());

    // Tip the balance and the profile has an answer.
    for (0..20) |index| ledger.observe("__ZN2xe3cpu8compiler6passesE", index, index);
    totals = ledger.summary();
    try std.testing.expectEqual(Region.guest_code_generation, totals.dominantRegion().?);
    try std.testing.expect(totals.dominantIsDecisive());
}

// The 2026-09-01 symbols that fell through to `unclassified`, and where they
// belong.
test "the emulator's own subsystems are not unclassified" {
    try std.testing.expectEqual(
        Region.guest_code_generation,
        regionOf("__ZN2xe3cpu3hirL15UnpackOpcodeSigEjRNS1_19OpcodeSignatureTypeES3_S3_S3_"),
    );
    try std.testing.expectEqual(
        Region.guest_emulation,
        regionOf("__ZN2xe6kernel4shim17TypedPointerParamINS0_19X_OBJECT_ATTRIBUTESEEC1ERNS1_5Param4InitE"),
    );
    try std.testing.expectEqual(
        Region.guest_emulation,
        regionOf("__ZN2xe10filesystem8FileInfoC2Ev"),
    );
    try std.testing.expectEqual(
        Region.guest_waiting,
        regionOf("__ZN2xe9threading8MacEventC2Ebb"),
    );
    // A std container of HIR values is code generation, not runtime: the
    // specific pass runs before the namespace pass on purpose, because what
    // the code is doing outranks which library it is written in.
    try std.testing.expectEqual(
        Region.guest_code_generation,
        regionOf("__ZNSt3__16vectorIPN2xe3cpu3hir5ValueEEC1Ev"),
    );
    // A std symbol with no emulator subsystem in it is a leaf and says so.
    try std.testing.expectEqual(
        Region.host_runtime,
        regionOf("__ZNSt3__113__atomic_baseIbLb0EE5storeB7v160006EbNS_12memory_orderE"),
    );
    // An unresolved sample is its own answer and never a region.
    try std.testing.expectEqual(Region.unresolved_symbol, regionOf("<unknown>"));
    try std.testing.expectEqual(Region.unresolved_symbol, regionOf(""));
    // And something genuinely foreign still falls through honestly.
    try std.testing.expectEqual(Region.unclassified, regionOf("_some_c_function"));
}

// The 2026-09-03 stop: a heartbeat sampled rip=0xa000fdb4, which is inside
// Xenia's JIT code cache (0xA0000000-0xAFFFFFFF) and can never have a symbol.
// The profile called it a symbol-table gap, the integrity gate armed on the
// debt, and the remedy told the reader to extend a symbol classifier that was
// already correct.
test "an unnamed address outside the image is generated code, not a missing symbol" {
    // Name-only classification still has to say it does not know.
    try std.testing.expectEqual(Region.unresolved_symbol, regionOf("<unknown>"));
    try std.testing.expectEqual(
        Region.unresolved_symbol,
        classifyAt("<unknown>", .unstated),
    );
    // Inside the image with no symbol is a real gap and stays one.
    try std.testing.expectEqual(
        Region.unresolved_symbol,
        classifyAt("<unknown>", .image),
    );
    // Outside the image, in memory the run made executable, is the answer.
    try std.testing.expectEqual(
        Region.guest_generated_code,
        classifyAt("<unknown>", .generated_code),
    );
    // Outside the image and not executable is a runaway the fault machinery
    // owns; inventing a region for it would hide exactly what this fixes.
    try std.testing.expectEqual(
        Region.unresolved_symbol,
        classifyAt("<unknown>", .outside_image_data),
    );
}

// The origin says which mapping the code sits in; the name says what the code
// does. A name that placed the sample must outrank the address, or every
// sample in a mapping would collapse to one region.
test "a resolved name outranks where the address lives" {
    try std.testing.expectEqual(
        Region.guest_code_generation,
        classifyAt("__ZN2xe3cpu8compiler6passes18SimplificationPassC1Ev", .generated_code),
    );
    try std.testing.expectEqual(
        Region.guest_waiting,
        classifyAt("__ZN2xe9threading8MacEventC2Ebb", .generated_code),
    );
}

// The two remaining rows of the 2026-09-03 debt, and where they belong.
test "the process entry frame and general-purpose primitives are classified" {
    // Matched exactly: `main` is the one symbol whose whole meaning is that it
    // is the entry point, and a substring test would claim every symbol with
    // `main` in it.
    try std.testing.expectEqual(Region.guest_entry, regionOf("_main"));
    try std.testing.expectEqual(Region.guest_entry, regionOf("main"));
    try std.testing.expectEqual(Region.guest_entry, regionOf("_dyld_start"));
    try std.testing.expectEqual(Region.guest_entry, regionOf("__libc_start_main"));
    // Not the entry point, and must not be claimed as one.
    try std.testing.expectEqual(
        Region.guest_emulation,
        regionOf("__ZN2xe6kernel12XMainThread5StartEv"),
    );
    // A hash is a leaf of whatever called it, like the C++ runtime beside it.
    try std.testing.expectEqual(
        Region.host_runtime,
        regionOf("__ZL24XXH3_accumulate_512_sse2PvPKvS1_"),
    );
    try std.testing.expectEqual(Region.host_runtime, regionOf("_crc32_z"));
    // LLVM support containers are linked into Xenia's compiler and are a
    // host-runtime leaf, not an unknown emulator subsystem. This exact
    // operator[] sample was the final classifier gap in the 2026-09-04 run.
    try std.testing.expectEqual(
        Region.host_runtime,
        regionOf("__ZNK4llvm9BitVectorixEj"),
    );
    // fmtlib's versioned namespace is encoded as `3fmt3v1` in the Itanium
    // mangling. This exact formatting-argument accessor was the only
    // unclassified sample in the 2026-09-04 run; it is another linked support
    // library leaf, not an unknown Rosette/Xenia subsystem.
    try std.testing.expectEqual(
        Region.host_runtime,
        regionOf("__ZNK3fmt3v1217basic_format_argsINS0_7contextEE3getEi"),
    );
    // utf8cpp's `utf8::next` is encoded with the versionless `4utf8`
    // namespace component. It is linked support code, not an unknown Xenia
    // subsystem; this was the late profile gap that stopped the current run.
    try std.testing.expectEqual(
        Region.host_runtime,
        regionOf("__ZN4utf84nextIPKcEEDiRT_S3_"),
    );
    // An emulator function that mentions one is still emulator work: the
    // namespace pass runs first on purpose.
    try std.testing.expectEqual(
        Region.guest_emulation,
        regionOf("__ZN2xe3vfs11XexDecrypt8inflateEv"),
    );
}

// The whole point of the fix: the run that stopped no longer carries debt.
test "the profile that stopped the 2026-09-03 run now classifies every sample" {
    var ledger = Ledger{};
    ledger.observeAt("_main", .image, 0x13e260, 0);
    ledger.observeAt(
        "__ZN2xe3cpu7backend3x6412X64CodeCache21CommitExecutableRangeEjj",
        .image,
        0xde45b4,
        100_000_000,
    );
    ledger.observeAt("__ZL24XXH3_accumulate_512_sse2PvPKvS1_", .image, 0x2bf37b, 300_000_000);
    ledger.observeAt(
        "__ZNK3fmt3v1217basic_format_argsINS0_7contextEE3getEi",
        .image,
        0x9a318,
        4_300_000_000,
    );
    ledger.observeAt("<unknown>", .generated_code, 0xa000fdb4, 1_700_000_000);
    // Enough emulator samples to make the profile readable and decisive.
    for (0..17) |index| {
        ledger.observeAt("__ZN2xe3cpu3ppc11PPCFrontend14DefineFunctionEv", .image, 0x33b73c, index);
    }

    const totals = ledger.summary();
    try std.testing.expect(totals.readable());
    try std.testing.expect(totals.dominantIsDecisive());
    try std.testing.expectEqual(
        @as(u64, 0),
        totals.by_region[@intFromEnum(Region.unclassified)],
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        totals.by_region[@intFromEnum(Region.unresolved_symbol)],
    );
    try std.testing.expectEqual(@as(u64, 0), totals.unaccountedPercent());
    try std.testing.expectEqual(
        @as(u64, 1),
        totals.by_region[@intFromEnum(Region.guest_generated_code)],
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        totals.by_region[@intFromEnum(Region.guest_entry)],
    );
    // Still every sample in exactly one region.
    var total: u64 = 0;
    for (totals.by_region) |count| total += count;
    try std.testing.expectEqual(totals.samples, total);
}

// Every address outside the image answers to the same `<unknown>`, so one row
// can collect samples that arrived with different origins. A row that kept the
// first origin would report generated code as a symbol-table gap whenever the
// gap happened to be sampled first.
test "a shared unnamed row keeps the more informative region" {
    var ledger = Ledger{};
    ledger.observeAt("<unknown>", .image, 0x1000, 1);
    ledger.observeAt("<unknown>", .generated_code, 0xa000fdb4, 2);
    try std.testing.expectEqual(@as(usize, 1), ledger.retained().len);
    try std.testing.expectEqual(Region.guest_generated_code, ledger.retained()[0].region);
    // The region totals count each sample where it actually landed.
    const totals = ledger.summary();
    try std.testing.expectEqual(
        @as(u64, 1),
        totals.by_region[@intFromEnum(Region.unresolved_symbol)],
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        totals.by_region[@intFromEnum(Region.guest_generated_code)],
    );
}

// The hottest rows are what gets printed, so the ordering is the report.
test "the hottest symbols come back most samples first" {
    var ledger = Ledger{};
    ledger.observe("cold", 1, 1);
    for (0..9) |index| ledger.observe("hot", 2, index);
    for (0..4) |index| ledger.observe("warm", 3, index);

    var out: [3]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 3), ledger.hottest(&out));
    try std.testing.expectEqualStrings("hot", out[0].name);
    try std.testing.expectEqualStrings("warm", out[1].name);
    try std.testing.expectEqualStrings("cold", out[2].name);
    try std.testing.expectEqual(@as(u64, 9), out[0].samples);
    try std.testing.expectEqual(@as(u64, 2), out[0].witness_rip);

    // Asking for more rows than exist returns what exists.
    var wide: [8]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 3), ledger.hottest(&wide));
}

test "every region names itself and a consequence" {
    inline for (@typeInfo(Region).@"enum".fields) |field| {
        const region: Region = @enumFromInt(field.value);
        try std.testing.expect(region.label().len != 0);
        try std.testing.expect(region.describe().len != 0);
    }
    // The classifier answers from the name and never guesses. An empty or
    // unresolvable name is its own answer rather than a region.
    try std.testing.expectEqual(Region.unresolved_symbol, regionOf(""));
    try std.testing.expectEqual(Region.guest_emulation, regionOf("__ZN2xe6kernel4shim5ParamE"));
    try std.testing.expectEqual(Region.guest_logging, regionOf("__ZN13disruptorplus9spin_wait9spin_onceEv"));
    try std.testing.expectEqual(Region.guest_waiting, regionOf("__ZNSt3__111unique_lockINS_5mutexEEC1Ev"));
    try std.testing.expectEqual(Region.guest_memory, regionOf("__ZN2xe12PhysicalHeap10InitializeEv"));
    // A compiler pass that allocates is code generation: the order of the
    // tables is part of the answer.
    try std.testing.expectEqual(
        Region.guest_code_generation,
        regionOf("__ZN2xe3cpu8compiler6passes18SimplificationPass5AllocEv"),
    );
}
