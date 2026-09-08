//! Ask what the image contains before asking what it does.
//!
//! The defect this exists for
//! --------------------------
//! The emulator is a JIT, so a subsystem's defects surface when that subsystem
//! is first reached. For the graphics path that is minutes of emulated boot
//! after launch, and the cost is paid per attempt: a build whose command
//! processor never linked and a build that simply has not got there yet look
//! the same for those minutes. The question "did this build even contain the
//! code" is answerable in milliseconds and was being answered in wall time.
//!
//! The image is mapped and its symbol table indexed before the first guest
//! instruction, so this runs at the launch-input audit — the same place the
//! media is hashed — and covers the whole subsystem surface at once rather
//! than the one boundary that happened to be instrumented.
//!
//! ## The strong statement is the negative one
//!
//! A stage that has symbols linked; it is not a stage that works. This walks
//! the symbol table and counts, and the only refusal it will make is over a
//! blocking stage containing *nothing* — which cannot work, cannot be fixed by
//! running longer, and is worth refusing before a minute is spent on it.
//!
//! Classification is separated from reading on purpose: `Auditor` is handed
//! names, so its decisions are testable without a seventy-megabyte binary.

const std = @import("std");
const contract = @import("xenia_prelaunch_audit_contract");

pub const Stage = contract.Stage;
pub const StageFacts = contract.StageFacts;
pub const Verdict = contract.Verdict;
/// The judged stages, in the order a title reaches them.
pub const contract_stages = contract.stages;

const stage_slots = @typeInfo(Stage).@"enum".fields.len;

pub const Summary = struct {
    facts: [stage_slots]StageFacts,
    verdict: Verdict = .unevaluated,
    blocking_gap: ?Stage = null,
    symbols_walked: u32 = 0,
    /// Entries in the image's `__stubs` sections — one per call site thunk, not
    /// one per distinct imported symbol. A debug build carries tens of
    /// thousands of stubs over a few hundred names, so reporting this as an
    /// import count would overstate the surface by a factor of thirty.
    import_stubs: u32 = 0,
    elapsed_ns: u64 = 0,

    /// The classified stages, in the contract's own order, so a reader sees
    /// them in the order a title reaches them.
    pub fn classified(self: *const Summary, stage: Stage) StageFacts {
        return self.facts[@intFromEnum(stage)];
    }
};

fn monotonicNanoseconds() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}

pub const Auditor = struct {
    facts: [stage_slots]StageFacts,
    symbols: u32 = 0,
    started_ns: u64 = 0,

    pub fn init() Auditor {
        var auditor = Auditor{ .facts = undefined, .started_ns = monotonicNanoseconds() };
        inline for (@typeInfo(Stage).@"enum".fields, 0..) |field, index| {
            auditor.facts[index] = .{ .stage = @enumFromInt(field.value) };
        }
        return auditor;
    }

    pub fn observe(self: *Auditor, symbol_name: []const u8, address: u64) void {
        self.symbols += 1;
        const stage = contract.classify(symbol_name);
        self.facts[@intFromEnum(stage)].observe(symbol_name, address);
    }

    pub fn finish(self: *Auditor, import_stubs: u32) Summary {
        // The unclassified bucket is not evidence about the build — most of a
        // binary is the standard library and the JIT — so it is excluded from
        // the verdict rather than allowed to make an empty image look examined.
        var judged: [stage_slots]StageFacts = undefined;
        var judged_count: usize = 0;
        for (contract.stages) |stage| {
            judged[judged_count] = self.facts[@intFromEnum(stage)];
            judged_count += 1;
        }
        const finished_ns = monotonicNanoseconds();
        return .{
            .facts = self.facts,
            .verdict = contract.verdictFor(judged[0..judged_count]),
            .blocking_gap = contract.firstBlockingGap(judged[0..judged_count]),
            .symbols_walked = self.symbols,
            .import_stubs = import_stubs,
            .elapsed_ns = if (finished_ns > self.started_ns) finished_ns - self.started_ns else 0,
        };
    }
};

/// Walk a loaded Mach-O image's symbol table. `metadata` is duck-typed so the
/// audit does not drag the Mach-O reader into every consumer.
pub fn auditImage(metadata: anytype) Summary {
    var auditor = Auditor.init();
    var symbols = metadata.definedSymbolIterator();
    while (symbols.next()) |entry| {
        auditor.observe(entry.key_ptr.*, entry.value_ptr.*);
    }
    return auditor.finish(@intCast(metadata.imports.len));
}

test "a realistic image is classified and reaches a ready verdict" {
    var auditor = Auditor.init();
    auditor.observe("xe::kernel::KernelState::BroadcastNotification", 0x1000);
    auditor.observe("xe::kernel::xboxkrnl::VdInitializeEngines", 0x2000);
    auditor.observe("xe::gpu::CommandProcessor::ExecutePacket", 0x3000);
    auditor.observe("xe::ui::Presenter::PaintAndPresent", 0x4000);
    auditor.observe("std::__1::basic_string::assign", 0x5000);

    const summary = auditor.finish(662);
    try std.testing.expectEqual(Verdict.ready, summary.verdict);
    try std.testing.expect(summary.blocking_gap == null);
    try std.testing.expectEqual(@as(u32, 5), summary.symbols_walked);
    try std.testing.expectEqual(@as(u32, 662), summary.import_stubs);
    try std.testing.expectEqual(@as(u32, 1), summary.classified(.gpu_bootstrap).symbols);
    // The standard library is classified out, not counted against any stage.
    try std.testing.expectEqual(@as(u32, 1), summary.classified(.unclassified).symbols);
}

test "a build missing a blocking subsystem is refused and the gap is named" {
    var auditor = Auditor.init();
    auditor.observe("xe::kernel::KernelState::BroadcastNotification", 0x1000);
    auditor.observe("xe::gpu::CommandProcessor::ExecutePacket", 0x3000);
    auditor.observe("xe::ui::Presenter::PaintAndPresent", 0x4000);
    // Nothing from GPU bootstrap linked.

    const summary = auditor.finish(662);
    try std.testing.expectEqual(Verdict.blocked, summary.verdict);
    try std.testing.expectEqual(Stage.gpu_bootstrap, summary.blocking_gap.?);
}

test "a build with no audio is reported and still allowed to run" {
    var auditor = Auditor.init();
    auditor.observe("xe::kernel::KernelState::BroadcastNotification", 0x1000);
    auditor.observe("xe::kernel::xboxkrnl::VdInitializeEngines", 0x2000);
    auditor.observe("xe::gpu::CommandProcessor::ExecutePacket", 0x3000);
    auditor.observe("xe::ui::Presenter::PaintAndPresent", 0x4000);

    const summary = auditor.finish(0);
    try std.testing.expectEqual(Verdict.ready, summary.verdict);
    try std.testing.expectEqual(@as(u32, 0), summary.classified(.audio).symbols);
    try std.testing.expectEqual(@as(u32, 0), summary.classified(.input).symbols);
}

test "an image that produced no symbols is unevaluated rather than blocked" {
    var auditor = Auditor.init();
    const summary = auditor.finish(0);
    // A reader that never ran must not be reported as a broken build.
    try std.testing.expectEqual(Verdict.unevaluated, summary.verdict);
    try std.testing.expectEqual(@as(u32, 0), summary.symbols_walked);
}

test "the unclassified bucket alone never counts as having examined the image" {
    var auditor = Auditor.init();
    auditor.observe("std::__1::vector::push_back", 0x1000);
    auditor.observe("llvm::MCAsmBackend::relaxInstruction", 0x2000);
    const summary = auditor.finish(0);
    // Symbols were walked, but none belong to a stage the contract judges, so
    // there is still nothing to conclude about the subsystems.
    try std.testing.expectEqual(@as(u32, 2), summary.symbols_walked);
    try std.testing.expectEqual(Verdict.unevaluated, summary.verdict);
}

test "stage fingerprints separate two builds that differ in one subsystem" {
    // Both names have to belong to the stage under test. `IssueSwap` reads
    // like a command-processor method and is deliberately classified as
    // `swap`, because the swap boundary is asked before the command processor
    // — so using it here would measure the wrong stage's fingerprint.
    try std.testing.expectEqual(Stage.swap, @import("xenia_prelaunch_audit_contract").classify("xe::gpu::CommandProcessor::IssueSwap"));

    var first = Auditor.init();
    first.observe("xe::gpu::CommandProcessor::ExecutePacket", 0x3000);
    first.observe("xe::gpu::CommandProcessor::ExecutePrimaryBuffer", 0x3100);
    const before = first.finish(0);

    var second = Auditor.init();
    second.observe("xe::gpu::CommandProcessor::ExecutePacket", 0x9000);
    second.observe("xe::gpu::CommandProcessor::ExecutePrimaryBuffer", 0x9100);
    const moved = second.finish(0);

    // Same code at different addresses is the same build surface.
    try std.testing.expectEqual(
        before.classified(.command_processor).fingerprint,
        moved.classified(.command_processor).fingerprint,
    );

    var third = Auditor.init();
    third.observe("xe::gpu::CommandProcessor::ExecutePacket", 0x3000);
    const shrunk = third.finish(0);
    try std.testing.expect(
        before.classified(.command_processor).fingerprint !=
            shrunk.classified(.command_processor).fingerprint,
    );
}

test "an address range is recorded per stage for locating the subsystem" {
    var auditor = Auditor.init();
    auditor.observe("xe::gpu::CommandProcessor::ExecutePacket", 0x3000);
    auditor.observe("xe::gpu::CommandProcessor::IssueSwap", 0x8000);
    const summary = auditor.finish(0);
    // IssueSwap belongs to swap, not the command processor, so the range is
    // only over what the stage actually claimed.
    try std.testing.expectEqual(@as(u64, 0x3000), summary.classified(.command_processor).lowest_address);
    try std.testing.expectEqual(@as(u64, 0x3000), summary.classified(.command_processor).highest_address);
    try std.testing.expectEqual(@as(u64, 0x8000), summary.classified(.swap).lowest_address);
}
