//! Route-independent: which subsystems a console emulator image must contain
//! for a run to be worth starting, and how to tell them apart by name.
//!
//! The defect this exists for
//! --------------------------
//! The emulator translates guest code as it runs, so a defect in a subsystem
//! is discovered when that subsystem is first *reached* — which for the
//! graphics path is several minutes of emulated boot after launch. A build
//! whose command processor did not link and a build whose command processor is
//! merely never called look identical for those minutes, and both look
//! identical to a build that is fine. The cost of finding out is paid in wall
//! time, once per attempt.
//!
//! Almost none of that has to be dynamic. The image is mapped and its symbol
//! table indexed before the first guest instruction, so whether a subsystem is
//! *present* is answerable immediately and for the whole surface at once —
//! kernel, GPU bootstrap, ring, command processor, swap, present, resources,
//! audio, input — not just the boundary that happened to be instrumented.
//!
//! ## What presence does and does not prove
//!
//! A stage with symbols is a stage that linked. It is not a stage that works,
//! and this package is careful never to say otherwise: the strong statement
//! here is the negative one. A blocking stage with **zero** symbols cannot
//! work, cannot be made to work by running longer, and is worth refusing
//! before a minute is spent on it. Everything above zero is reported as
//! observation and decided elsewhere.
//!
//! ## Fingerprints are of names, not addresses
//!
//! A stage's fingerprint mixes the names it contains, commutatively, and
//! ignores where they landed. Hashing addresses would be more precise and
//! useless: any edit anywhere shifts every later address, so every build would
//! differ in every stage and the fingerprint would answer "did anything
//! change" instead of "did *this* change".
//!
//! ## What this package is not
//!
//! It reads nothing. It is handed names and hands back classifications; the
//! symbol table, the imports and the host lookups all live in lib.

const std = @import("std");

/// A subsystem the run depends on, in roughly the order a title reaches them.
pub const Stage = enum {
    kernel,
    gpu_bootstrap,
    ring,
    command_processor,
    gpu_resources,
    swap,
    present,
    graphics_provider,
    audio,
    input,
    /// Everything else in the image. Not a defect — most of a binary is not
    /// one of the stages above.
    unclassified,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .kernel => "kernel",
            .gpu_bootstrap => "gpu-bootstrap",
            .ring => "ring",
            .command_processor => "command-processor",
            .gpu_resources => "gpu-resources",
            .swap => "swap",
            .present => "present",
            .graphics_provider => "graphics-provider",
            .audio => "audio",
            .input => "input",
            .unclassified => "unclassified",
        };
    }

    /// Whether an empty stage makes the run pointless to start.
    ///
    /// Deliberately narrow. These are the stages with no path to a frame if
    /// they contain nothing at all, so their emptiness is a link failure
    /// rather than a title that has not got there yet. Audio and input are
    /// excluded on purpose: a title can reach graphics without either, and
    /// refusing a run over them would be refusing on a guess.
    pub fn blocksLaunch(self: Stage) bool {
        return switch (self) {
            .kernel, .gpu_bootstrap, .command_processor, .present => true,
            .ring,
            .gpu_resources,
            .swap,
            .graphics_provider,
            .audio,
            .input,
            .unclassified,
            => false,
        };
    }
};

/// The classified stages, in classification order.
pub const stages = [_]Stage{
    .ring,
    .swap,
    .command_processor,
    .gpu_resources,
    .graphics_provider,
    .present,
    .gpu_bootstrap,
    .audio,
    .input,
    .kernel,
};

/// Name fragments that place a symbol in a stage.
///
/// Order across stages matters and is fixed by `stages` above, because these
/// overlap by construction: `IssueSwap` lives on the command processor and
/// `VdSwap` is the guest boundary, `Presenter` contains `Present`, and almost
/// everything in the emulator can be reached from `KernelState`. The narrower
/// stage is asked first and the broadest — kernel — last, so a symbol lands in
/// the most specific stage that claims it rather than the first one written.
pub fn fragmentsFor(stage: Stage) []const []const u8 {
    return switch (stage) {
        .ring => &.{ "RingBuffer", "ring_buffer" },
        .swap => &.{ "VdSwap", "IssueSwap", "XE_SWAP" },
        .command_processor => &.{ "CommandProcessor", "ExecutePacket", "ExecutePrimaryBuffer", "ExecuteIndirectBuffer" },
        .gpu_resources => &.{ "TextureCache", "PipelineCache", "RenderTargetCache", "SharedMemory", "ShaderTranslator" },
        .graphics_provider => &.{ "VulkanProvider", "VulkanContext", "VulkanSubmissionTracker" },
        .present => &.{ "Presenter", "Present", "Swapchain", "surface" },
        .gpu_bootstrap => &.{ "GraphicsSystem", "VdInitialize", "VdSetGraphics", "VdQuery", "VdGetSystem", "VdEnable", "VdPersist", "VdRetrain", "VdShutdown", "VdIsHSIO" },
        .audio => &.{ "AudioSystem", "AudioDriver", "XmaDecoder", "XmaContext", "AudioMediaPlayer" },
        .input => &.{ "InputSystem", "InputDriver", "HidDriver", "xinput" },
        .kernel => &.{ "KernelState", "XboxkrnlModule", "XamModule", "XThread", "XObject", "XamLoader" },
        .unclassified => &.{},
    };
}

/// A set of the byte values a string contains, as one word.
///
/// Used to reject a fragment before searching for it. A fragment cannot occur
/// in a name that is missing any of its bytes, and that test is an `and` where
/// the search is a scan. It matters because the answer for most of a binary is
/// `unclassified`, and reaching that answer honestly means asking every
/// fragment: a hundred and forty thousand symbols each rejecting forty
/// fragments is the whole cost of this audit.
fn byteSignature(text: []const u8) u64 {
    var bits: u64 = 0;
    for (text) |byte| bits |= @as(u64, 1) << @intCast(byte & 63);
    return bits;
}

/// Place one symbol name in a stage.
///
/// `unclassified` is the common answer and is not a finding: most of a binary
/// is the standard library, the JIT, the CPU backend and the UI.
pub fn classify(symbol_name: []const u8) Stage {
    const name_bits = byteSignature(symbol_name);
    inline for (stages) |stage| {
        inline for (comptime fragmentsFor(stage)) |fragment| {
            // The fragment's signature is comptime; the rejection is one mask
            // test against the name's.
            const fragment_bits = comptime byteSignature(fragment);
            if (fragment_bits & ~name_bits == 0) {
                if (std.mem.indexOf(u8, symbol_name, fragment) != null) return stage;
            }
        }
    }
    return .unclassified;
}

/// Where a guest import will be served from, as far as can be told without
/// running.
pub const Provider = enum {
    /// The host itself exports this name, so the forwarder can bind it.
    host,
    /// Rosette's own modelled surface answers it.
    modelled,
    /// Nothing statically claims it. It is not necessarily broken — the
    /// dispatch chain may well answer it at the first call — but nothing here
    /// can say so, and that is the set worth reading.
    unclassified,

    pub fn label(self: Provider) []const u8 {
        return switch (self) {
            .host => "host",
            .modelled => "modelled",
            .unclassified => "unclassified",
        };
    }
};

/// What was found for one stage.
pub const StageFacts = struct {
    stage: Stage = .unclassified,
    symbols: u32 = 0,
    /// Commutative mix of the stage's symbol names. Order- and
    /// address-independent by design.
    fingerprint: u64 = 0,
    lowest_address: u64 = 0,
    highest_address: u64 = 0,

    pub fn isEmpty(self: StageFacts) bool {
        return self.symbols == 0;
    }

    /// Fold one symbol in. Commutative so the symbol table may be walked in
    /// any order and still produce the same fingerprint.
    pub fn observe(self: *StageFacts, symbol_name: []const u8, address: u64) void {
        self.symbols += 1;
        self.fingerprint ^= nameHash(symbol_name);
        if (address != 0) {
            if (self.lowest_address == 0 or address < self.lowest_address) self.lowest_address = address;
            if (address > self.highest_address) self.highest_address = address;
        }
    }
};

/// FNV-1a over a symbol name.
pub fn nameHash(name: []const u8) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (name) |byte| {
        hash ^= byte;
        hash *%= 0x0000_0100_0000_01b3;
    }
    // A zero would be indistinguishable from "nothing observed" once mixed.
    return if (hash == 0) 1 else hash;
}

pub const Verdict = enum {
    /// Every blocking stage carries code.
    ready,
    /// A blocking stage is empty. Running cannot reach a frame.
    blocked,
    /// Nothing was examined.
    unevaluated,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .ready => "ready",
            .blocked => "blocked",
            .unevaluated => "unevaluated",
        };
    }
};

/// The whole-image verdict.
///
/// Only emptiness of a blocking stage produces `blocked`, because that is the
/// one conclusion this evidence supports on its own. A stage that linked may
/// still be broken, and saying so from a symbol count would be a guess wearing
/// a verdict's clothes.
pub fn verdictFor(facts: []const StageFacts) Verdict {
    var examined = false;
    var blocked = false;
    for (facts) |stage_facts| {
        if (stage_facts.symbols != 0) examined = true;
        if (stage_facts.stage.blocksLaunch() and stage_facts.isEmpty()) blocked = true;
    }
    if (!examined) return .unevaluated;
    return if (blocked) .blocked else .ready;
}

/// The first blocking stage with nothing in it, which is the one to fix.
pub fn firstBlockingGap(facts: []const StageFacts) ?Stage {
    for (facts) |stage_facts| {
        if (stage_facts.stage.blocksLaunch() and stage_facts.isEmpty()) return stage_facts.stage;
    }
    return null;
}

/// A stage-to-stage call edge seen in a build that reaches graphics.
///
/// The assertion these carry is about **disappearance, not presence**. A direct
/// call graph cannot see indirect dispatch — a title reaches the video exports
/// through the kernel's ordinal table and the emulator reaches its backends
/// through vtables, and neither leaves a `call rel32` behind. Measured on a
/// working build, `kernel -> gpu-bootstrap` is zero for exactly that reason,
/// and reading that zero as a disconnection would be wrong.
///
/// So an absent edge is never a finding here. Only the loss of one that was
/// there is: these seven were each measured well above zero on a build known to
/// reach graphics, and a refactor that empties one has broken a link that used
/// to exist.
pub const StageLink = struct {
    from: Stage,
    to: Stage,
    /// What the link is for, in a reader's terms rather than a symbol's.
    why: []const u8,
};

pub const observed_links = [_]StageLink{
    .{ .from = .gpu_bootstrap, .to = .command_processor, .why = "the graphics system drives the command processor" },
    .{ .from = .gpu_bootstrap, .to = .ring, .why = "ring setup runs from the graphics system" },
    .{ .from = .gpu_bootstrap, .to = .present, .why = "the graphics system reaches the presenter" },
    .{ .from = .command_processor, .to = .gpu_resources, .why = "packet execution binds caches and shared memory" },
    .{ .from = .command_processor, .to = .ring, .why = "the command processor reads the ring" },
    .{ .from = .swap, .to = .present, .why = "a swap reaches the presenter" },
    .{ .from = .present, .to = .graphics_provider, .why = "the presenter draws on the provider's surface" },
};

/// Environment names the guest reads that Rosette must be able to answer.
///
/// The guest binds its run identity by asking for these by name. A name Rosette
/// cannot answer is indistinguishable, to the guest, from one that is genuinely
/// unset — and the guest treats that as grounds to refuse its own start, several
/// thousand log lines away from the cause. The backend route is also required
/// by Xenia's authentic admission path: omitting it makes graphics setup reject
/// the run after Vulkan has already initialized, moving a precondition failure
/// thousands of log lines away from the environment audit.
pub const required_environment_names = [_][]const u8{
    "ROSETTE_RUN_ID",
    "ROSETTE_MANIFEST_HASH",
    "ROSETTE_BUILD_IDENTITY_HASH",
    "ROSETTE_BACKEND",
};

pub fn environmentNameIsRequired(name: []const u8) bool {
    for (required_environment_names) |required| {
        if (std.mem.eql(u8, name, required)) return true;
    }
    return false;
}

pub fn contractIsWellFormed() bool {
    if (stages.len == 0) return false;
    // Kernel is classified last: its fragments are reachable from most of the
    // emulator and would otherwise swallow the narrower stages.
    if (stages[stages.len - 1] != .kernel) return false;
    for (stages) |stage| {
        if (fragmentsFor(stage).len == 0) return false;
    }
    // A link whose ends are the same stage says nothing about two subsystems
    // meeting, and every required name has to be one the guest could ask for.
    for (observed_links) |link| {
        if (link.from == link.to) return false;
        if (link.why.len == 0) return false;
    }
    for (required_environment_names) |name| {
        if (name.len == 0) return false;
    }
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "a symbol lands in the most specific stage that claims it" {
    // Every one of these is claimed by more than one stage's fragments, and
    // the ordering is the only thing that decides. That makes it worth
    // pinning: swapping two entries in `stages` silently re-labels thousands
    // of symbols.
    try std.testing.expectEqual(Stage.swap, classify("VulkanCommandProcessor::IssueSwap"));
    try std.testing.expectEqual(Stage.present, classify("xe::ui::Presenter::PaintAndPresent"));
    try std.testing.expectEqual(Stage.ring, classify("GraphicsSystem::InitializeRingBuffer"));
    try std.testing.expectEqual(Stage.command_processor, classify("CommandProcessor::ExecutePacket"));
    try std.testing.expectEqual(Stage.gpu_bootstrap, classify("VdInitializeEngines"));
    try std.testing.expectEqual(Stage.kernel, classify("KernelState::BroadcastNotification"));
}

test "a name no stage claims is unclassified rather than forced somewhere" {
    try std.testing.expectEqual(Stage.unclassified, classify("std::__1::basic_string"));
    try std.testing.expectEqual(Stage.unclassified, classify(""));
    try std.testing.expectEqual(Stage.unclassified, classify("llvm::MCAsmBackend"));
}

test "audio and input are classified but never block a launch" {
    try std.testing.expectEqual(Stage.audio, classify("xe::apu::AudioSystem::Setup"));
    try std.testing.expectEqual(Stage.audio, classify("XmaDecoder::Initialize"));
    try std.testing.expectEqual(Stage.input, classify("xe::hid::InputSystem::GetState"));
    // A title can reach a frame without either, so their absence is reported
    // and never refused.
    try std.testing.expect(!Stage.audio.blocksLaunch());
    try std.testing.expect(!Stage.input.blocksLaunch());
    try std.testing.expect(Stage.gpu_bootstrap.blocksLaunch());
    try std.testing.expect(Stage.command_processor.blocksLaunch());
}

test "a stage fingerprint ignores the order the symbol table is walked in" {
    var forward = StageFacts{ .stage = .swap };
    forward.observe("VdSwap", 0x1000);
    forward.observe("IssueSwap", 0x2000);
    forward.observe("XE_SWAP", 0x3000);

    var reverse = StageFacts{ .stage = .swap };
    reverse.observe("XE_SWAP", 0x3000);
    reverse.observe("IssueSwap", 0x2000);
    reverse.observe("VdSwap", 0x1000);

    try std.testing.expectEqual(forward.fingerprint, reverse.fingerprint);
    try std.testing.expectEqual(forward.symbols, reverse.symbols);
    try std.testing.expectEqual(@as(u64, 0x1000), reverse.lowest_address);
    try std.testing.expectEqual(@as(u64, 0x3000), reverse.highest_address);
}

test "a stage fingerprint changes when its contents change" {
    var before = StageFacts{ .stage = .swap };
    before.observe("VdSwap", 0x1000);
    before.observe("IssueSwap", 0x2000);

    var after = StageFacts{ .stage = .swap };
    after.observe("VdSwap", 0x1000);
    after.observe("IssueSwapDeferred", 0x2000);

    try std.testing.expect(before.fingerprint != after.fingerprint);

    // Moving code without changing it does not, which is the whole point: an
    // address-based fingerprint would differ on every build.
    var moved = StageFacts{ .stage = .swap };
    moved.observe("IssueSwap", 0x9000);
    moved.observe("VdSwap", 0xA000);
    try std.testing.expectEqual(before.fingerprint, moved.fingerprint);
}

test "an empty blocking stage is the verdict, and names itself" {
    const facts = [_]StageFacts{
        .{ .stage = .kernel, .symbols = 2510 },
        .{ .stage = .gpu_bootstrap, .symbols = 0 },
        .{ .stage = .command_processor, .symbols = 2751 },
        .{ .stage = .present, .symbols = 1423 },
        .{ .stage = .audio, .symbols = 0 },
    };
    try std.testing.expectEqual(Verdict.blocked, verdictFor(&facts));
    try std.testing.expectEqual(Stage.gpu_bootstrap, firstBlockingGap(&facts).?);
}

test "an empty non-blocking stage is reported and does not refuse the run" {
    const facts = [_]StageFacts{
        .{ .stage = .kernel, .symbols = 2510 },
        .{ .stage = .gpu_bootstrap, .symbols = 181 },
        .{ .stage = .command_processor, .symbols = 2751 },
        .{ .stage = .present, .symbols = 1423 },
        // A build with no audio still reaches a frame.
        .{ .stage = .audio, .symbols = 0 },
        .{ .stage = .input, .symbols = 0 },
    };
    try std.testing.expectEqual(Verdict.ready, verdictFor(&facts));
    try std.testing.expect(firstBlockingGap(&facts) == null);
}

test "an image nothing was read from is unevaluated, not ready" {
    const facts = [_]StageFacts{
        .{ .stage = .kernel, .symbols = 0 },
        .{ .stage = .gpu_bootstrap, .symbols = 0 },
    };
    // Nothing observed at all cannot be a pass. It is also not a link failure,
    // and calling it one would accuse a build over a reader that never ran.
    try std.testing.expectEqual(Verdict.unevaluated, verdictFor(&facts));
    try std.testing.expectEqual(Verdict.unevaluated, verdictFor(&.{}));
}

test "every stage and provider states its own vocabulary" {
    try std.testing.expectEqualStrings("gpu-bootstrap", Stage.gpu_bootstrap.label());
    try std.testing.expectEqualStrings("command-processor", Stage.command_processor.label());
    try std.testing.expectEqualStrings("unclassified", Stage.unclassified.label());
    try std.testing.expectEqualStrings("host", Provider.host.label());
    try std.testing.expectEqualStrings("blocked", Verdict.blocked.label());
}

test "a name hash is never zero, so a mixed fingerprint means something" {
    try std.testing.expect(nameHash("") != 0);
    try std.testing.expect(nameHash("VdSwap") != nameHash("VdSwapX"));
}

test "observed links are between distinct stages and carry a reason" {
    try std.testing.expect(observed_links.len > 0);
    for (observed_links) |link| {
        try std.testing.expect(link.from != link.to);
        try std.testing.expect(link.why.len != 0);
    }
}

test "the required environment names are the ones the guest cannot start without" {
    try std.testing.expect(environmentNameIsRequired("ROSETTE_RUN_ID"));
    try std.testing.expect(environmentNameIsRequired("ROSETTE_MANIFEST_HASH"));
    try std.testing.expect(environmentNameIsRequired("ROSETTE_BUILD_IDENTITY_HASH"));
    try std.testing.expect(environmentNameIsRequired("ROSETTE_BACKEND"));
    try std.testing.expect(!environmentNameIsRequired("HOME"));
    try std.testing.expect(!environmentNameIsRequired(""));
}
