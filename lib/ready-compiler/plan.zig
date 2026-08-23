//! The startup compile plan.
//!
//! The activation gate elsewhere in this library watches a run and reports
//! where it stopped. That is diagnosis after the fact, and it costs whatever
//! the run costs: a missing precondition four hundred million instructions
//! into startup is discovered four hundred million instructions in.
//!
//! This is the other half. Before the guest executes a single instruction, the
//! preconditions of the whole startup contract are enumerated as an ordered
//! list of units and checked against the loaded image, the filesystem, and the
//! host. Each unit is a symbol lookup, a file stat, or a capability query, so
//! the entire plan runs in the time a build system spends on one object file
//! rather than in the time a run spends reaching the failure.
//!
//! What this can and cannot do is worth stating plainly, because a gate that
//! overclaims is worse than none. It cannot prove a *behaviour* will happen —
//! that the guest will publish a swap packet, that a thread will be signalled.
//! It proves the *preconditions* of those behaviours: that the code implementing
//! them is present in the image, that something calls it, that the files it
//! reads exist and are well formed, that the host offers what it needs. Every
//! one of those, when absent, guarantees the behaviour cannot occur — and that
//! is a verdict worth having at step zero instead of at step five hundred
//! million.

const std = @import("std");

/// Upper bound on plan size. A startup contract's preconditions are counted in
/// hundreds, and a fixed array keeps the plan allocation-free so it can run
/// before the guest heap exists.
pub const max_units: usize = 512;
pub const max_detail: usize = 160;

pub const UnitCategory = enum(u8) {
    /// Structural facts about the mapped executable.
    image,
    /// A function or global the contract depends on existing.
    symbol,
    /// A call site referencing a required symbol. A function that exists and
    /// is called from nowhere is dead code, and a stage whose owner is dead
    /// can never fire however healthy the symbol looks.
    call_site,
    /// A file or directory the run reads or writes, and its health.
    asset,
    /// Something the host must provide.
    host,
    /// A contract stage's owner, resolved to the code that must implement it.
    contract,

    pub fn label(self: UnitCategory) []const u8 {
        return switch (self) {
            .image => "image",
            .symbol => "symbol",
            .call_site => "call-site",
            .asset => "asset",
            .host => "host",
            .contract => "contract",
        };
    }
};

pub const Outcome = enum(u8) {
    pending,
    ok,
    failed,
    /// Could not be evaluated. Counted apart from a pass, because a check that
    /// told us nothing must never be reported as one that told us everything
    /// is fine.
    indeterminate,
    /// Not reached because an earlier required unit failed and the plan halted.
    skipped,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .pending => "PENDING",
            .ok => "OK",
            .failed => "FAILED",
            .indeterminate => "INDETERMINATE",
            .skipped => "SKIPPED",
        };
    }
};

/// What an asset must look like to count as healthy. Xenia reads a wide range
/// of formats during startup and a truncated or wrong-typed one fails much
/// later and much less legibly than it needs to.
pub const AssetKind = enum(u8) {
    /// Presence and readability only.
    any_file,
    directory,
    /// Must be writable, and created if absent is the caller's business.
    writable_directory,
    /// Xbox 360 executable: begins "XEX2".
    xex,
    /// Disc image: readable and large enough to hold a filesystem.
    disc_image,
    /// SPIR-V module: begins with the 0x07230203 magic word.
    spirv,
    /// Text configuration.
    toml,
    /// A loadable shared library.
    dylib,

    pub fn label(self: AssetKind) []const u8 {
        return switch (self) {
            .any_file => "file",
            .directory => "directory",
            .writable_directory => "writable-directory",
            .xex => "xex",
            .disc_image => "disc-image",
            .spirv => "spirv",
            .toml => "toml",
            .dylib => "dylib",
        };
    }
};

pub const Unit = struct {
    category: UnitCategory,
    /// What is being checked. For a symbol this is the mangled name; for an
    /// asset, the path; for a contract unit, the stage name.
    name: []const u8 = "",
    /// Human-readable purpose, printed when the unit fails.
    purpose: []const u8 = "",
    /// A required unit that fails halts the plan. An optional one is recorded
    /// and the plan continues: not every precondition is fatal, and treating
    /// them alike would make the gate unusable.
    required: bool = true,
    asset_kind: AssetKind = .any_file,
    /// For a contract unit, the symbol that must implement the stage.
    implementation: []const u8 = "",
};

pub const Record = struct {
    unit: Unit,
    outcome: Outcome = .pending,
    detail_buffer: [max_detail]u8 = [_]u8{0} ** max_detail,
    detail_len: usize = 0,

    pub fn detail(self: *const Record) []const u8 {
        return self.detail_buffer[0..self.detail_len];
    }

    pub fn setDetail(self: *Record, text: []const u8) void {
        const copied = @min(text.len, self.detail_buffer.len);
        @memcpy(self.detail_buffer[0..copied], text[0..copied]);
        self.detail_len = copied;
    }
};

/// Verdict for one asset probe.
pub const AssetVerdict = struct {
    present: bool = false,
    readable: bool = false,
    writable: bool = false,
    /// Content matched what the declared kind requires.
    well_formed: bool = false,
    size: u64 = 0,
    /// Set when the probe itself could not run, which is different from the
    /// asset being absent.
    probe_failed: bool = false,
};

/// The world the plan asks questions of. Supplied by the caller so the plan
/// engine performs no I/O of its own and can be exercised against a fake.
pub const Probe = struct {
    context: *anyopaque,
    symbolExists: *const fn (context: *anyopaque, name: []const u8) bool,
    callSiteExists: *const fn (context: *anyopaque, name: []const u8) bool,
    assetVerdict: *const fn (context: *anyopaque, path: []const u8, kind: AssetKind) AssetVerdict,
    hostCapability: *const fn (context: *anyopaque, name: []const u8) bool,
    imageFact: *const fn (context: *anyopaque, name: []const u8) bool,
};

/// Emitted once per unit as the plan runs, so the log reads as an ordered
/// build rather than as a report that appears all at once at the end.
pub const Progress = struct {
    index: usize,
    total: usize,
    unit: Unit,
    outcome: Outcome,
    detail: []const u8,
};

pub const Emitter = struct {
    context: *anyopaque,
    emit: *const fn (context: *anyopaque, progress: Progress) void,
};

pub const Summary = struct {
    total: usize = 0,
    ok: usize = 0,
    failed: usize = 0,
    indeterminate: usize = 0,
    skipped: usize = 0,
    /// One-based index of the unit that halted the plan, or zero.
    halted_at: usize = 0,
    halted_unit: Unit = .{ .category = .image },

    pub fn passed(self: Summary) bool {
        return self.failed == 0 and self.halted_at == 0;
    }
};

pub const Plan = struct {
    records: [max_units]Record = [_]Record{.{ .unit = .{ .category = .image } }} ** max_units,
    count: usize = 0,
    dropped: usize = 0,

    pub fn add(self: *Plan, unit: Unit) void {
        if (self.count >= self.records.len) {
            self.dropped += 1;
            return;
        }
        self.records[self.count] = .{ .unit = unit };
        self.count += 1;
    }

    pub fn units(self: *const Plan) []const Record {
        return self.records[0..self.count];
    }

    /// Run every unit in order, reporting each as it completes.
    ///
    /// The plan halts at the first required failure rather than collecting all
    /// of them. Later units routinely depend on earlier ones, so continuing
    /// past a real failure produces a cascade that buries the one finding that
    /// caused it — the same reason a build stops at the first error rather
    /// than printing every consequence of it.
    pub fn run(self: *Plan, probe: Probe, emitter: ?Emitter) Summary {
        var summary: Summary = .{ .total = self.count };
        var halted = false;
        for (self.records[0..self.count], 0..) |*record, index| {
            if (halted) {
                record.outcome = .skipped;
                summary.skipped += 1;
                continue;
            }
            self.evaluate(record, probe);
            switch (record.outcome) {
                .ok => summary.ok += 1,
                .failed => summary.failed += 1,
                .indeterminate => summary.indeterminate += 1,
                .skipped, .pending => {},
            }
            if (emitter) |sink| {
                sink.emit(sink.context, .{
                    .index = index + 1,
                    .total = self.count,
                    .unit = record.unit,
                    .outcome = record.outcome,
                    .detail = record.detail(),
                });
            }
            if (record.outcome == .failed and record.unit.required) {
                halted = true;
                summary.halted_at = index + 1;
                summary.halted_unit = record.unit;
            }
        }
        return summary;
    }

    fn evaluate(self: *Plan, record: *Record, probe: Probe) void {
        _ = self;
        const unit = record.unit;
        switch (unit.category) {
            .image => {
                const present = probe.imageFact(probe.context, unit.name);
                record.outcome = if (present) .ok else .failed;
                if (!present) record.setDetail("the image does not satisfy this structural requirement");
            },
            .symbol => {
                const present = probe.symbolExists(probe.context, unit.name);
                record.outcome = if (present) .ok else .failed;
                if (!present) record.setDetail("no such symbol in the mapped image");
            },
            .call_site => {
                if (!probe.symbolExists(probe.context, unit.name)) {
                    // Nothing to be reachable from. The symbol unit for the
                    // same name reports the real problem; saying it twice
                    // would point at the wrong layer.
                    record.outcome = .indeterminate;
                    record.setDetail("symbol absent, so reachability is unanswerable");
                    return;
                }
                const called = probe.callSiteExists(probe.context, unit.name);
                record.outcome = if (called) .ok else .failed;
                if (!called) record.setDetail("symbol is present but nothing in the image calls it");
            },
            .host => {
                const available = probe.hostCapability(probe.context, unit.name);
                record.outcome = if (available) .ok else .failed;
                if (!available) record.setDetail("the host does not provide this capability");
            },
            .contract => {
                // A stage can only fire if the code that reports it exists and
                // something reaches it.  The reference probe is deliberately
                // conservative: it currently sees direct rel32 calls, while
                // C++ startup code also uses vtables, thunks, and
                // std::function.  Therefore a missing direct reference is
                // uncertainty in the probe, not proof that the stage is dead.
                const implementation = if (unit.implementation.len != 0) unit.implementation else unit.name;
                if (!probe.symbolExists(probe.context, implementation)) {
                    record.outcome = .failed;
                    record.setDetail("the stage owner's implementation is not in the image, so this stage can never be reached");
                    return;
                }
                if (!probe.callSiteExists(probe.context, implementation)) {
                    record.outcome = .indeterminate;
                    record.setDetail("the implementation exists but direct reachability was not proven; indirect or virtual dispatch remains possible");
                    return;
                }
                record.outcome = .ok;
            },
            .asset => {
                const verdict = probe.assetVerdict(probe.context, unit.name, unit.asset_kind);
                if (verdict.probe_failed) {
                    record.outcome = .indeterminate;
                    record.setDetail("the asset could not be examined");
                    return;
                }
                if (!verdict.present) {
                    record.outcome = .failed;
                    record.setDetail("the asset does not exist at this path");
                    return;
                }
                if (!verdict.readable) {
                    record.outcome = .failed;
                    record.setDetail("the asset exists but cannot be read");
                    return;
                }
                if (unit.asset_kind == .writable_directory and !verdict.writable) {
                    record.outcome = .failed;
                    record.setDetail("the directory exists but cannot be written");
                    return;
                }
                if (!verdict.well_formed) {
                    record.outcome = .failed;
                    record.setDetail("the asset is readable but its contents do not match the expected format");
                    return;
                }
                record.outcome = .ok;
            },
        }
    }
};

// --- tests ----------------------------------------------------------------

const FakeWorld = struct {
    symbols: []const []const u8 = &.{},
    call_sites: []const []const u8 = &.{},
    capabilities: []const []const u8 = &.{},
    image_facts: []const []const u8 = &.{},
    asset: AssetVerdict = .{ .present = true, .readable = true, .writable = true, .well_formed = true },

    fn has(list: []const []const u8, name: []const u8) bool {
        for (list) |entry| {
            if (std.mem.eql(u8, entry, name)) return true;
        }
        return false;
    }

    fn symbolExists(context: *anyopaque, name: []const u8) bool {
        const self: *FakeWorld = @ptrCast(@alignCast(context));
        return has(self.symbols, name);
    }
    fn callSiteExists(context: *anyopaque, name: []const u8) bool {
        const self: *FakeWorld = @ptrCast(@alignCast(context));
        return has(self.call_sites, name);
    }
    fn hostCapability(context: *anyopaque, name: []const u8) bool {
        const self: *FakeWorld = @ptrCast(@alignCast(context));
        return has(self.capabilities, name);
    }
    fn imageFact(context: *anyopaque, name: []const u8) bool {
        const self: *FakeWorld = @ptrCast(@alignCast(context));
        return has(self.image_facts, name);
    }
    fn assetVerdict(context: *anyopaque, path: []const u8, kind: AssetKind) AssetVerdict {
        _ = path;
        _ = kind;
        const self: *FakeWorld = @ptrCast(@alignCast(context));
        return self.asset;
    }

    fn probe(self: *FakeWorld) Probe {
        return .{
            .context = self,
            .symbolExists = symbolExists,
            .callSiteExists = callSiteExists,
            .assetVerdict = assetVerdict,
            .hostCapability = hostCapability,
            .imageFact = imageFact,
        };
    }
};

const Recorder = struct {
    lines: [max_units]Progress = undefined,
    count: usize = 0,

    fn record(context: *anyopaque, progress: Progress) void {
        const self: *Recorder = @ptrCast(@alignCast(context));
        if (self.count >= self.lines.len) return;
        self.lines[self.count] = progress;
        self.count += 1;
    }

    fn emitter(self: *Recorder) Emitter {
        return .{ .context = self, .emit = record };
    }
};

test "a plan reports every unit in order with a running index" {
    var world = FakeWorld{
        .symbols = &.{ "_alpha", "_beta" },
        .call_sites = &.{ "_alpha", "_beta" },
    };
    var plan = Plan{};
    plan.add(.{ .category = .symbol, .name = "_alpha" });
    plan.add(.{ .category = .symbol, .name = "_beta" });

    var recorder = Recorder{};
    const summary = plan.run(world.probe(), recorder.emitter());
    try std.testing.expect(summary.passed());
    try std.testing.expectEqual(@as(usize, 2), recorder.count);
    try std.testing.expectEqual(@as(usize, 1), recorder.lines[0].index);
    try std.testing.expectEqual(@as(usize, 2), recorder.lines[0].total);
    try std.testing.expectEqual(@as(usize, 2), recorder.lines[1].index);
    try std.testing.expectEqual(Outcome.ok, recorder.lines[1].outcome);
}

test "a missing symbol halts the plan and the remainder is skipped, not passed" {
    var world = FakeWorld{ .symbols = &.{"_present"}, .call_sites = &.{"_present"} };
    var plan = Plan{};
    plan.add(.{ .category = .symbol, .name = "_present" });
    plan.add(.{ .category = .symbol, .name = "_absent" });
    plan.add(.{ .category = .symbol, .name = "_never_reached" });

    var recorder = Recorder{};
    const summary = plan.run(world.probe(), recorder.emitter());
    try std.testing.expect(!summary.passed());
    try std.testing.expectEqual(@as(usize, 2), summary.halted_at);
    try std.testing.expectEqual(@as(usize, 1), summary.ok);
    try std.testing.expectEqual(@as(usize, 1), summary.failed);
    // The third unit must not be counted as a pass: it was never evaluated.
    try std.testing.expectEqual(@as(usize, 1), summary.skipped);
    try std.testing.expectEqual(@as(usize, 2), recorder.count);
}

test "an optional failure is recorded and does not halt the plan" {
    var world = FakeWorld{ .symbols = &.{"_present"}, .call_sites = &.{"_present"} };
    var plan = Plan{};
    plan.add(.{ .category = .symbol, .name = "_optional", .required = false });
    plan.add(.{ .category = .symbol, .name = "_present" });

    const summary = plan.run(world.probe(), null);
    try std.testing.expectEqual(@as(usize, 1), summary.failed);
    try std.testing.expectEqual(@as(usize, 1), summary.ok);
    try std.testing.expectEqual(@as(usize, 0), summary.halted_at);
    // A recorded failure still fails the plan even when it did not halt it.
    try std.testing.expect(!summary.passed());
}

test "a stage whose owner lacks a direct call site is indeterminate" {
    // This is the case a direct-reference scan cannot decide: the code is in
    // the image, but C++ may reach it through a vtable, thunk, or function
    // table that the scan does not model.
    var world = FakeWorld{
        .symbols = &.{"_ZN2xe3gpu14GraphicsSystem23InitializeShaderStorageE"},
        .call_sites = &.{},
    };
    var plan = Plan{};
    plan.add(.{
        .category = .contract,
        .name = "shader_storage_ready",
        .implementation = "_ZN2xe3gpu14GraphicsSystem23InitializeShaderStorageE",
    });

    var recorder = Recorder{};
    const summary = plan.run(world.probe(), recorder.emitter());
    try std.testing.expect(summary.passed());
    try std.testing.expectEqual(Outcome.indeterminate, recorder.lines[0].outcome);
    try std.testing.expect(std.mem.indexOf(u8, recorder.lines[0].detail, "indirect or virtual dispatch") != null);
}

test "reachability of an absent symbol is unanswerable, not a second failure" {
    var world = FakeWorld{ .symbols = &.{}, .call_sites = &.{} };
    var plan = Plan{};
    plan.add(.{ .category = .call_site, .name = "_gone", .required = false });

    const summary = plan.run(world.probe(), null);
    // Indeterminate rather than failed: the symbol unit for the same name is
    // where that finding belongs, and reporting it twice points at the wrong
    // layer.
    try std.testing.expectEqual(@as(usize, 1), summary.indeterminate);
    try std.testing.expectEqual(@as(usize, 0), summary.failed);
}

test "asset health separates absent, unreadable, and malformed" {
    var plan = Plan{};
    plan.add(.{ .category = .asset, .name = "/disc.iso", .asset_kind = .disc_image, .required = false });

    var absent = FakeWorld{ .asset = .{ .present = false } };
    var run_absent = plan;
    _ = run_absent.run(absent.probe(), null);
    try std.testing.expect(std.mem.indexOf(u8, run_absent.records[0].detail(), "does not exist") != null);

    var unreadable = FakeWorld{ .asset = .{ .present = true, .readable = false } };
    var run_unreadable = plan;
    _ = run_unreadable.run(unreadable.probe(), null);
    try std.testing.expect(std.mem.indexOf(u8, run_unreadable.records[0].detail(), "cannot be read") != null);

    var malformed = FakeWorld{ .asset = .{ .present = true, .readable = true, .well_formed = false } };
    var run_malformed = plan;
    _ = run_malformed.run(malformed.probe(), null);
    try std.testing.expect(std.mem.indexOf(u8, run_malformed.records[0].detail(), "do not match the expected format") != null);
}

test "an unexaminable asset is indeterminate rather than a pass" {
    var world = FakeWorld{ .asset = .{ .probe_failed = true } };
    var plan = Plan{};
    plan.add(.{ .category = .asset, .name = "/unknown", .required = false });
    const summary = plan.run(world.probe(), null);
    try std.testing.expectEqual(@as(usize, 1), summary.indeterminate);
    try std.testing.expectEqual(@as(usize, 0), summary.ok);
}

test "a writable directory requirement is distinct from a readable one" {
    var world = FakeWorld{
        .asset = .{ .present = true, .readable = true, .writable = false, .well_formed = true },
    };
    var plan = Plan{};
    plan.add(.{ .category = .asset, .name = "/cache", .asset_kind = .writable_directory, .required = false });
    _ = plan.run(world.probe(), null);
    try std.testing.expect(std.mem.indexOf(u8, plan.records[0].detail(), "cannot be written") != null);
}

test "plan capacity overflow is counted rather than silently truncating" {
    var plan = Plan{};
    var index: usize = 0;
    while (index < max_units + 3) : (index += 1) {
        plan.add(.{ .category = .symbol, .name = "_x" });
    }
    try std.testing.expectEqual(max_units, plan.count);
    try std.testing.expectEqual(@as(usize, 3), plan.dropped);
}
