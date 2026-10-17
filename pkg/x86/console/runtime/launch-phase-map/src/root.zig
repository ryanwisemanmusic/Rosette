//! Build-time attribution of Xenia's *silent* startup windows.
//!
//! Xenia reports named progress by logging. Two long stretches of its launch
//! path log nothing at all, and one of them is where the x86 route currently
//! dies: between `user_module_ready` and `shader_storage_requested`,
//! `Emulator::CompleteLaunch` loads the per-title TOML config, reads the XDBF
//! resource, builds the game-info database, parses XLast, and decodes the
//! title icon. None of that emits a line, so the readiness gate sees hundreds
//! of millions of retired instructions with no owner reporting anything and
//! calls the run blocked.
//!
//! The gate does not actually lack evidence there — it lacks a *name* for the
//! evidence it already has. Rosette resolves the guest instruction pointer to
//! a Mach-O symbol on every progress checkpoint. Which subsystem a Xenia
//! symbol belongs to is fixed when Xenia is compiled, so deriving it at
//! runtime is repeated work for an answer that never changes. This package is
//! that answer, resolved once at build time.
//!
//! What this package is not:
//!
//!   * It is not a progress source. Matching a symbol proves the guest is
//!     inside that subsystem's code, nothing more. The runtime half decides
//!     whether that counts as forward motion, and refuses to count a revisited
//!     symbol.
//!   * It is not a suppression switch. A run genuinely stuck inside one
//!     function exhausts this package's evidence after one credit and fails on
//!     schedule.
//!   * It never names an address. Fragments carry the Itanium length prefix so
//!     they survive a Xenia rebuild; an address-keyed table would be a
//!     different assertion that happens to work once.

const std = @import("std");

pub const host_architecture = "x86_64";
pub const host_codegen = "xbyak-x86_64";

/// A named region of Xenia's startup that Rosette can recognise from a symbol.
///
/// The order is the order a healthy launch visits them. It is not enforced —
/// Xenia interleaves worker threads through most of it — but it makes the
/// table readable in the order a reader debugging a stall will need it.
pub const Phase = enum(u8) {
    /// XEX image load: PE headers, section table, import tables, page
    /// protection. Xenia logs here, so attribution is corroboration.
    module_load,
    /// `X64CodeCache::CommitExecutableRange`. Host code-cache growth during
    /// the guest translation storm.
    code_cache_commit,
    /// `UserModule::CalculateHash`. XXH3 over the whole 6.9 MB code image.
    module_hash,
    /// `XexModule::FindSaveRest`. A 17 MB pattern scan over the code ranges.
    save_rest_scan,
    /// `XexModule::Precompile` and the discovered-function pass.
    precompile,
    /// `XexInfoCache`. On-disk executable-address flag cache.
    info_cache,
    /// `config::LoadGameConfig` and the cvar TOML reader. Silent in Xenia.
    game_config,
    /// XDBF resource, SPA info, `GameInfoDatabase`, XLast, pugixml. The window
    /// the x86 route currently dies in, and completely silent in Xenia.
    title_metadata,
    /// `UserTracker`, `XamState`. Profile and played-title bookkeeping, also
    /// silent.
    user_profile,
    /// `Window::SetIcon` and the icon block handed to the host window.
    window_icon,
    /// `GraphicsSystem`/`CommandProcessor::InitializeShaderStorage` and the
    /// Vulkan pipeline cache behind it.
    shader_storage,
    /// `KernelState::LaunchModule` and `XThread::Create` for guest main.
    module_launch,
    /// PPC frontend, HIR, and the x64 backend emitting translated guest code.
    guest_translation,
    /// A guest call into a kernel export (`xboxkrnl`/`xam` `*_entry` shims and
    /// the trampolines that reach them).
    ///
    /// This is the only in-image evidence that the title itself is running.
    /// Once guest main starts, the instruction pointer spends its time in
    /// translated PPC code, which lives outside the Mach-O image and resolves
    /// to no symbol at all — so the export shims are where a running title
    /// becomes visible to a symbol-based observer.
    guest_kernel_export,
    /// PM4 ring execution on the command-processor thread.
    gpu_ring,
    /// Presenter and swapchain work on the presentation thread.
    presentation,
    /// A libc++, libc, or UTF-8 helper with no subsystem of its own.
    ///
    /// Carriers are the majority of samples inside `title_metadata`: a Debug
    /// build of Xenia copies `std::vector<uint8_t>` one byte at a time through
    /// `__uninitialized_allocator_copy`, so the instruction pointer spends
    /// most of the window in libc++ rather than in `xe::`. A carrier names no
    /// owner; the runtime attributes it to whichever phase last identified
    /// itself on the same thread, and to nothing at all before that.
    host_runtime_carrier,
};

pub const phase_count: usize = @typeInfo(Phase).@"enum".fields.len;

/// What a matched symbol establishes.
pub const Attribution = struct {
    phase: Phase,
    /// The work-unit text the readiness gate records. The first
    /// whitespace-delimited token becomes the reported owner, which is why it
    /// is spelled as a Xenia qualified name rather than prose.
    label: []const u8,
    /// The Ready Compiler subsystem spelling that owes this work.
    owner: []const u8,
    /// A second subsystem whose progress this phase's activity demonstrates
    /// once `proxy_after_stage` has been reached, or empty. See
    /// `PhaseFacts.proxy_owner`.
    proxy_owner: []const u8 = "",
    /// The contract stage after which `proxy_owner` applies. Empty whenever
    /// `proxy_owner` is empty.
    proxy_after_stage: []const u8 = "",
    /// True when the symbol identifies no subsystem of its own and must
    /// inherit the active phase instead.
    carrier: bool,
};

/// A loop that retires instructions without making progress.
///
/// Naming these is the other half of the job. Xenia's frame limiter and the
/// disruptor ring producer both spin at full speed for the entire run; without
/// this list they would look like the busiest subsystems in the image and
/// would keep a genuinely dead run alive forever.
pub const IdleLoop = enum(u8) {
    ring_producer_spin,
    frame_limiter,
};

const PhaseFacts = struct {
    label: []const u8,
    owner: []const u8,
    /// The contract stage that must already be reached for this phase to be
    /// plausible, spelled exactly as the Ready Compiler spells it. Empty means
    /// the phase can legitimately run at any point after activation opens.
    after_stage: []const u8,
    /// A second subsystem whose forward motion this phase's activity proves,
    /// once `proxy_after_stage` has been reached. Empty for most phases.
    ///
    /// `owner` answers "whose code is executing". That is the right answer for
    /// a report, and the wrong one for deciding whether the subsystem the
    /// contract is *waiting on* is alive. The two come apart in exactly one
    /// place, and it is the place that matters most: Xenia translates guest
    /// PowerPC lazily, so once guest main is running, the only thing that makes
    /// the translator allocate, build HIR, or commit a new code-cache range is
    /// the title reaching code it has never reached before. The symbols are
    /// `xenia:cpu`'s; the progress is the title's.
    ///
    /// Before guest main exists the same symbols are Xenia precompiling on its
    /// own initiative, which is why this is stage-conditional rather than a
    /// second owner outright. A proxy is a claim about causation, so it is
    /// stated per phase here instead of being inferred at runtime from a
    /// thread id, which would only ever be a guess.
    proxy_owner: []const u8 = "",
    /// The contract stage after which `proxy_owner` applies.
    proxy_after_stage: []const u8 = "",
};

const phase_facts = blk: {
    var facts: [phase_count]PhaseFacts = undefined;
    facts[@intFromEnum(Phase.module_load)] = .{
        .label = "xe::kernel::XexModule::LoadContinue phase=module-load",
        .owner = "xenia:xex_loader",
        .after_stage = "complete_launch_started",
    };
    facts[@intFromEnum(Phase.code_cache_commit)] = .{
        .label = "xe::cpu::backend::x64::X64CodeCache phase=code-cache-commit",
        .owner = "xenia:cpu",
        .after_stage = "processor_ready",
        .proxy_owner = "guest:title",
        .proxy_after_stage = "guest_main_ready",
    };
    facts[@intFromEnum(Phase.module_hash)] = .{
        .label = "xe::kernel::UserModule::CalculateHash phase=module-hash",
        .owner = "xenia:xex_loader",
        .after_stage = "user_module_loaded",
    };
    facts[@intFromEnum(Phase.save_rest_scan)] = .{
        .label = "xe::kernel::XexModule::FindSaveRest phase=save-rest-scan",
        .owner = "xenia:xex_loader",
        .after_stage = "user_module_loaded",
    };
    facts[@intFromEnum(Phase.precompile)] = .{
        .label = "xe::kernel::XexModule::Precompile phase=precompile",
        .owner = "xenia:xex_loader",
        .after_stage = "user_module_loaded",
    };
    facts[@intFromEnum(Phase.info_cache)] = .{
        .label = "xe::kernel::XexInfoCache phase=info-cache",
        .owner = "xenia:xex_loader",
        .after_stage = "user_module_loaded",
    };
    facts[@intFromEnum(Phase.game_config)] = .{
        .label = "cvar::config::LoadGameConfig phase=game-config",
        .owner = "xenia:config",
        .after_stage = "user_module_ready",
    };
    facts[@intFromEnum(Phase.title_metadata)] = .{
        .label = "xe::kernel::util::GameInfoDatabase phase=title-metadata",
        .owner = "xenia:xam",
        .after_stage = "user_module_ready",
    };
    facts[@intFromEnum(Phase.user_profile)] = .{
        .label = "xe::kernel::xam::UserTracker phase=user-profile",
        .owner = "xenia:xam",
        .after_stage = "user_module_ready",
    };
    facts[@intFromEnum(Phase.window_icon)] = .{
        .label = "xe::ui::Window::SetIcon phase=window-icon",
        .owner = "xenia:ui",
        .after_stage = "user_module_ready",
    };
    facts[@intFromEnum(Phase.shader_storage)] = .{
        .label = "xe::gpu::GraphicsSystem::InitializeShaderStorage phase=shader-storage",
        .owner = "xenia:graphics",
        .after_stage = "shader_storage_requested",
    };
    facts[@intFromEnum(Phase.module_launch)] = .{
        .label = "xe::kernel::KernelState::LaunchModule phase=module-launch",
        .owner = "xenia:kernel_state",
        .after_stage = "shader_storage_ready",
    };
    facts[@intFromEnum(Phase.guest_translation)] = .{
        .label = "xe::cpu::ppc::PPCTranslator phase=guest-translation",
        .owner = "xenia:cpu",
        .after_stage = "processor_ready",
        .proxy_owner = "guest:title",
        .proxy_after_stage = "guest_main_ready",
    };
    facts[@intFromEnum(Phase.guest_kernel_export)] = .{
        .label = "guest::title kernel-export phase=guest-execution",
        .owner = "guest:title",
        .after_stage = "guest_main_ready",
    };
    facts[@intFromEnum(Phase.gpu_ring)] = .{
        .label = "xe::gpu::CommandProcessor::ExecutePacket phase=gpu-ring",
        .owner = "xenia:command_processor",
        .after_stage = "command_processor_ready",
    };
    facts[@intFromEnum(Phase.presentation)] = .{
        .label = "xe::ui::Presenter phase=presentation",
        .owner = "xenia:presenter",
        .after_stage = "command_processor_ready",
    };
    facts[@intFromEnum(Phase.host_runtime_carrier)] = .{
        .label = "host::runtime phase=carrier",
        .owner = "",
        .after_stage = "",
    };
    break :blk facts;
};

pub fn label(phase: Phase) []const u8 {
    return phase_facts[@intFromEnum(phase)].label;
}

pub fn owner(phase: Phase) []const u8 {
    return phase_facts[@intFromEnum(phase)].owner;
}

/// The contract stage this phase cannot precede. The runtime uses it to reject
/// an attribution that contradicts the stages actually reached — a presenter
/// sample during module load is a live worker thread, not launch progress.
pub fn afterStage(phase: Phase) []const u8 {
    return phase_facts[@intFromEnum(phase)].after_stage;
}

/// The subsystem whose progress this phase demonstrates once `proxyAfterStage`
/// has been reached, or empty. See `PhaseFacts.proxy_owner` for why this is not
/// simply a second owner.
pub fn proxyOwner(phase: Phase) []const u8 {
    return phase_facts[@intFromEnum(phase)].proxy_owner;
}

/// The stage after which `proxyOwner` applies, or empty when there is none.
pub fn proxyAfterStage(phase: Phase) []const u8 {
    return phase_facts[@intFromEnum(phase)].proxy_after_stage;
}

const Rule = struct {
    fragment: []const u8,
    phase: Phase,
};

/// Ordered longest-evidence-first.
///
/// Order is load-bearing where a symbol legitimately belongs to two regions:
/// `XexModule::Precompile` also contains `XexModule`, and the more specific
/// answer is the useful one. Everything here carries an Itanium length prefix
/// except the two identifiers (`Xdbf`, `XLast`) that appear in enough distinct
/// class names that a prefix would need one rule per class and would gain no
/// precision — nothing else in the image spells either word.
const rules = [_]Rule{
    // --- The silent window the x86 route dies in -------------------------
    .{ .fragment = "16GameInfoDatabase", .phase = .title_metadata },
    .{ .fragment = "Xdbf", .phase = .title_metadata },
    .{ .fragment = "7SpaInfo", .phase = .title_metadata },
    .{ .fragment = "XLast", .phase = .title_metadata },
    .{ .fragment = "4pugi", .phase = .title_metadata },
    .{ .fragment = "11module_xdbfE", .phase = .title_metadata },
    // `xe::kernel::util` also holds the object table and the kernel's native
    // list, which run for the whole process, so the namespace is not usable as
    // a rule. These two types are title metadata and nothing else.
    .{ .fragment = "23ProductInformationEntry", .phase = .title_metadata },
    .{ .fragment = "4cvar", .phase = .game_config },
    .{ .fragment = "11UserTracker", .phase = .user_profile },
    .{ .fragment = "8XamState", .phase = .user_profile },
    .{ .fragment = "7SetIconE", .phase = .window_icon },
    .{ .fragment = "14LoadGameConfig", .phase = .game_config },
    .{ .fragment = "19LoadGameConfigValue", .phase = .game_config },
    .{ .fragment = "13toml_internal", .phase = .game_config },
    .{ .fragment = "4toml2v3", .phase = .game_config },

    // --- Module load and precompile --------------------------------------
    .{ .fragment = "9XexModule10PrecompileE", .phase = .precompile },
    .{ .fragment = "9XexModule12FindSaveRestE", .phase = .save_rest_scan },
    .{ .fragment = "10UserModule13CalculateHashE", .phase = .module_hash },
    .{ .fragment = "12XexInfoCache", .phase = .info_cache },
    .{ .fragment = "9XexModule12LoadContinueE", .phase = .module_load },
    .{ .fragment = "9XexModule13ReadPEHeadersE", .phase = .module_load },
    .{ .fragment = "21CommitExecutableRangeE", .phase = .code_cache_commit },

    // --- Launch and translation ------------------------------------------
    .{ .fragment = "12LaunchModuleE", .phase = .module_launch },
    .{ .fragment = "7XThread6CreateE", .phase = .module_launch },
    // Named per translator class rather than by the `3ppc` namespace: every
    // kernel export trampoline takes a `ppc::PPCContext_s*` and would
    // otherwise be filed under translation while it is really guest execution.
    .{ .fragment = "3ppc13PPCTranslator", .phase = .guest_translation },
    .{ .fragment = "3ppc11PPCFrontend", .phase = .guest_translation },
    .{ .fragment = "3ppc10PPCScanner", .phase = .guest_translation },
    .{ .fragment = "3ppc13PPCHIRBuilder", .phase = .guest_translation },
    .{ .fragment = "3hir10HIRBuilder", .phase = .guest_translation },
    .{ .fragment = "10X64Emitter", .phase = .guest_translation },
    // `xe::Arena` is the translator's bump allocator and is reachable from
    // nowhere else: the only holders in Xenia's tree are `hir::HIRBuilder`,
    // `compiler::Compiler::scratch_arena_` and
    // `x64::X64Emitter::source_map_arena_` (`base/simple_freelist.h` mentions
    // it in a comment and does not use it). A five-character class name also
    // makes the Itanium prefix exact — a `XArena` would mangle as `6XArena`
    // and cannot collide.
    //
    // This rule is why the run that motivated it was killed. `Arena::Alloc`
    // was the single hottest site on the busiest thread — 409 of 472 samples —
    // and matched nothing, so the gate saw the one subsystem that was working
    // as silence.
    .{ .fragment = "5Arena", .phase = .guest_translation },
    .{ .fragment = "8compiler8Compiler", .phase = .guest_translation },
    .{ .fragment = "8compiler12CompilerPass", .phase = .guest_translation },
    .{ .fragment = "13X64CodeCache", .phase = .code_cache_commit },
    .{ .fragment = "10X64Backend", .phase = .guest_translation },
    .{ .fragment = "16X64ThunkEmitter", .phase = .guest_translation },
    // Declaring a guest function and rebinding its import thunk are both
    // reached only when the title branches somewhere it has not branched
    // before: `DeclareFunction` calls `RestoreImportThunkBinding` for every
    // newly declared symbol, and `UndefinedCallExtern` calls it when a guest
    // call lands on an unresolved extern. Neither can fire twice for the same
    // function, which is what makes them progress rather than activity.
    .{ .fragment = "25RestoreImportThunkBindingE", .phase = .guest_translation },
    .{ .fragment = "15DeclareFunctionE", .phase = .guest_translation },
    .{ .fragment = "13GuestFunction", .phase = .guest_translation },

    // --- Guest execution --------------------------------------------------
    // `*_entry` is Xenia's naming convention for a kernel export body, and
    // the registrar template is the trampoline that reaches one. Nothing else
    // in the image uses either spelling.
    .{ .fragment = "_entryE", .phase = .guest_kernel_export },
    .{ .fragment = "4shim21ExportRegistrerHelper", .phase = .guest_kernel_export },

    // --- Graphics ---------------------------------------------------------
    .{ .fragment = "23InitializeShaderStorageE", .phase = .shader_storage },
    .{ .fragment = "19VulkanPipelineCache", .phase = .shader_storage },
    .{ .fragment = "13ExecutePacketE", .phase = .gpu_ring },
    .{ .fragment = "20ExecutePrimaryBufferE", .phase = .gpu_ring },
    .{ .fragment = "9Presenter", .phase = .presentation },
    .{ .fragment = "15VulkanPresenter", .phase = .presentation },

    // --- Carriers ---------------------------------------------------------
    // Every one of these was a top-ranked stall site in the x86 run that this
    // package exists to explain. They own nothing; they carry whatever called
    // them.
    .{ .fragment = "__uninitialized_allocator_", .phase = .host_runtime_carrier },
    .{ .fragment = "22__base_destruct_at_end", .phase = .host_runtime_carrier },
    .{ .fragment = "12__to_address", .phase = .host_runtime_carrier },
    .{ .fragment = "22__compressed_pair_elem", .phase = .host_runtime_carrier },
    .{ .fragment = "16allocator_traits", .phase = .host_runtime_carrier },
    .{ .fragment = "4utf88internal", .phase = .host_runtime_carrier },
    .{ .fragment = "12basic_string", .phase = .host_runtime_carrier },
    .{ .fragment = "6vector", .phase = .host_runtime_carrier },
    .{ .fragment = "13__vector_base", .phase = .host_runtime_carrier },
    // The second wave, taken from the sampled sites of the run that this
    // package's guest-translation rules were added for. Every one of them was
    // an unmatched top site: an atomic load, a red-black tree walk, a byte
    // swap, a clock read. None owns a subsystem and all four are called from
    // everywhere, so each must inherit rather than name a phase — listing them
    // as owners would have credited whichever subsystem happened to be running
    // to whichever one the reader was looking at.
    .{ .fragment = "13__atomic_base", .phase = .host_runtime_carrier },
    .{ .fragment = "__cxx_atomic", .phase = .host_runtime_carrier },
    .{ .fragment = "__tree", .phase = .host_runtime_carrier },
    .{ .fragment = "__hash_table", .phase = .host_runtime_carrier },
    .{ .fragment = "10shared_ptr", .phase = .host_runtime_carrier },
    .{ .fragment = "19__shared_weak_count", .phase = .host_runtime_carrier },
    .{ .fragment = "10unique_ptr", .phase = .host_runtime_carrier },
    // `xe::byte_swap` and `xe::Clock` are Xenia's own, and are still carriers:
    // a byte swap is called by the loader, the translator, the ring reader and
    // the kernel shims alike, and a clock read by anything that measures.
    .{ .fragment = "9byte_swapI", .phase = .host_runtime_carrier },
    .{ .fragment = "5Clock", .phase = .host_runtime_carrier },
};

const IdleRule = struct {
    fragment: []const u8,
    loop: IdleLoop,
};

/// Only loops that provably retire instructions without advancing belong here.
///
/// A thread's entry frame does not. `std::__thread_proxy` and
/// `MacCondition::ThreadStartRoutine` are the outermost frame of *every*
/// `std::thread` in the image — including the guest main thread — and
/// `nearestSymbol` attributes an inlined thread body to the entry frame that
/// encloses it. Listing them would have suppressed the strongest evidence
/// there is that the title is running, in exchange for silencing a watchdog.
const idle_rules = [_]IdleRule{
    .{ .fragment = "13disruptorplus", .loop = .ring_producer_spin },
    .{ .fragment = "9spin_wait", .loop = .ring_producer_spin },
    .{ .fragment = "28GetInternalDisplayResolutionE", .loop = .frame_limiter },
    .{ .fragment = "13FrameLimiter", .loop = .frame_limiter },
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

/// A loop that retires instructions without advancing anything, or null.
///
/// Checked before `classify` by every caller: a spinning ring producer sits
/// inside `xe::gpu` code and would otherwise be attributed to a GPU phase.
pub fn idleLoop(symbol_name: []const u8) ?IdleLoop {
    for (idle_rules) |rule| {
        if (contains(symbol_name, rule.fragment)) return rule.loop;
    }
    return null;
}

/// The startup region a Xenia symbol belongs to, or null when the symbol is
/// not one this package can speak for.
///
/// Returning null is the common case and the correct one. An unattributed
/// symbol must leave the readiness gate exactly as blind as it was before this
/// package existed, never slightly more confident.
pub fn classify(symbol_name: []const u8) ?Attribution {
    if (idleLoop(symbol_name) != null) return null;
    for (rules) |rule| {
        if (!contains(symbol_name, rule.fragment)) continue;
        return .{
            .phase = rule.phase,
            .label = label(rule.phase),
            .owner = owner(rule.phase),
            .proxy_owner = proxyOwner(rule.phase),
            .proxy_after_stage = proxyAfterStage(rule.phase),
            .carrier = rule.phase == .host_runtime_carrier,
        };
    }
    return null;
}

/// Attribute a generic host helper to the one silent `CompleteLaunch` window
/// whose owner is known from Xenia's source ordering but is not always present
/// in the nearest-symbol result. `std::vector`/`std::string` helpers are often
/// the innermost symbol while XDBF, XLast, or the title icon is being decoded.
///
/// This is intentionally narrower than `classify`: it is valid only while the
/// required frontier is exactly `user_module_ready`, only for a non-idle
/// carrier-shaped symbol, and it produces ordinary bounded phase evidence. The
/// generic runtime still caps distinct symbols, so this cannot turn a stuck
/// helper into an unbounded activation exemption.
pub fn frontierFallback(frontier_stage: []const u8, symbol_name: []const u8) ?Attribution {
    if (!std.mem.eql(u8, frontier_stage, "user_module_ready")) return null;
    if (idleLoop(symbol_name) != null) return null;
    if (classify(symbol_name)) |known| {
        if (!known.carrier) return null;
    } else if (!looksLikeHostCarrier(symbol_name)) {
        return null;
    }
    return .{
        .phase = .title_metadata,
        .label = label(.title_metadata),
        .owner = owner(.title_metadata),
        .proxy_owner = proxyOwner(.title_metadata),
        .proxy_after_stage = proxyAfterStage(.title_metadata),
        .carrier = false,
    };
}

fn looksLikeHostCarrier(symbol_name: []const u8) bool {
    return contains(symbol_name, "__ZNSt3__1") or
        contains(symbol_name, "__ZN4utf8") or
        contains(symbol_name, "__ZN3fmt") or
        contains(symbol_name, "__ZN8pugixml");
}

/// The phases that sit in a window where Xenia logs nothing.
///
/// A phase Xenia already narrates does not need this package to be seen; the
/// distinction matters because attribution for a narrated phase is
/// corroboration, and attribution for a silent one is the only evidence there
/// is.
pub fn isSilentInXenia(phase: Phase) bool {
    return switch (phase) {
        .game_config, .title_metadata, .user_profile, .window_icon => true,
        else => false,
    };
}

/// The Ready Compiler stage names this package refers to. The contract
/// cross-checks this at compile time so a rename on either side is a build
/// error rather than a silently dead rule.
pub fn referencedStageNames(buffer: [][]const u8) []const []const u8 {
    var count: usize = 0;
    for (phase_facts) |facts| {
        // A proxy's stage is load-bearing in the same way its phase's own is:
        // it decides when a subsystem starts speaking for another one, so a
        // rename that orphans it has to be a build error too.
        for ([_][]const u8{ facts.after_stage, facts.proxy_after_stage }) |name| {
            if (name.len == 0) continue;
            var seen = false;
            for (buffer[0..count]) |existing| {
                if (std.mem.eql(u8, existing, name)) seen = true;
            }
            if (seen) continue;
            if (count >= buffer.len) break;
            buffer[count] = name;
            count += 1;
        }
    }
    return buffer[0..count];
}

/// Every distinct subsystem this package can attribute work to, including
/// proxies. The contract cross-checks these against the owners its stages
/// declare, so a proxy naming a subsystem the contract has never heard of is a
/// build error rather than an attribution that silently never matches.
pub fn referencedOwnerNames(buffer: [][]const u8) []const []const u8 {
    var count: usize = 0;
    for (phase_facts) |facts| {
        for ([_][]const u8{ facts.owner, facts.proxy_owner }) |name| {
            if (name.len == 0) continue;
            var seen = false;
            for (buffer[0..count]) |existing| {
                if (std.mem.eql(u8, existing, name)) seen = true;
            }
            if (seen) continue;
            if (count >= buffer.len) break;
            buffer[count] = name;
            count += 1;
        }
    }
    return buffer[0..count];
}

pub fn contractIsWellFormed() bool {
    // Every non-carrier phase must name an owner and a work-unit label, or the
    // readiness report would print an attributed stall with no one to ask.
    for (phase_facts, 0..) |facts, index| {
        const phase: Phase = @enumFromInt(index);
        if (facts.label.len == 0) return false;
        if (phase == .host_runtime_carrier) {
            if (facts.owner.len != 0 or facts.after_stage.len != 0) return false;
            continue;
        }
        if (facts.owner.len == 0 or facts.after_stage.len == 0) return false;
        // The label's first token becomes the reported owner token, so a label
        // that starts with whitespace would report an empty owner.
        if (facts.label[0] <= ' ') return false;
        // A proxy is a conditional claim, so both halves must be present: a
        // proxy owner with no stage would apply from the first instruction,
        // which is the unconditional second owner this deliberately is not.
        if ((facts.proxy_owner.len == 0) != (facts.proxy_after_stage.len == 0)) return false;
        // A proxy that repeats the phase's own owner is not a proxy, and would
        // read as one in the report for no reason.
        if (facts.proxy_owner.len != 0 and
            std.mem.eql(u8, facts.proxy_owner, facts.owner)) return false;
    }
    if (rules.len == 0 or idle_rules.len == 0) return false;
    return true;
}

test "the silent title-metadata window is attributable" {
    const database = classify("__ZN2xe6kernel4util16GameInfoDatabase12GetTitleNameENS_9XLanguageE") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.title_metadata, database.phase);
    try std.testing.expectEqualStrings("xenia:xam", database.owner);
    try std.testing.expect(!database.carrier);
    try std.testing.expect(isSilentInXenia(database.phase));

    const xdbf = classify("__ZN2xe6kernel3xam10XdbfHeaderC1Ev") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.title_metadata, xdbf.phase);

    const spa = classify("__ZN2xe6kernel3xam7SpaInfo9ReadXLastERjS3_") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.title_metadata, spa.phase);

    const tracker = classify("__ZN2xe6kernel3xam11UserTracker20AddTitleToPlayedListEv") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.user_profile, tracker.phase);
    try std.testing.expect(isSilentInXenia(tracker.phase));
}

test "the observed stall sites resolve to carriers, not owners" {
    // These four were sites [1]..[4] of the run this package was written for.
    // A carrier must never claim an owner of its own; inheriting the wrong
    // subsystem is worse than reporting none.
    const observed = [_][]const u8{
        "__ZNSt3__130__uninitialized_allocator_copyB7v160006INS_9allocatorIhEEPhS3_S3_EET2_RT_T0_T1_S4_",
        "__ZNSt3__112__to_addressB7v160006IhEEPT_S2_",
        "__ZNSt3__16vectorIhNS_9allocatorIhEEE22__base_destruct_at_endB7v160006EPh",
        "__ZNSt3__122__compressed_pair_elemINS_9allocatorIhEELi1ELb1EE5__getB7v160006Ev",
        "__ZN4utf88internal13validate_nextIPKcEENS0_9utf_errorERT_S5_RDi",
    };
    for (observed) |symbol| {
        const attribution = classify(symbol) orelse {
            std.debug.print("unclassified stall site: {s}\n", .{symbol});
            return error.TestUnexpectedResult;
        };
        try std.testing.expect(attribution.carrier);
        try std.testing.expectEqual(Phase.host_runtime_carrier, attribution.phase);
        try std.testing.expectEqualStrings("", attribution.owner);
    }
}

test "spinning workers are never progress" {
    // The hot site of the failing run, on the GPU worker thread. It sits in
    // xe::gpu code; without the idle list it would read as command-processor
    // progress and would hold the quiet window open for a dead run.
    try std.testing.expectEqual(
        IdleLoop.ring_producer_spin,
        idleLoop("__ZN13disruptorplus9spin_wait15yield_processorEv") orelse return error.TestUnexpectedResult,
    );
    try std.testing.expect(classify("__ZN13disruptorplus9spin_wait15yield_processorEv") == null);
    try std.testing.expectEqual(
        IdleLoop.frame_limiter,
        idleLoop("__ZN2xe3gpu14GraphicsSystem28GetInternalDisplayResolutionEv") orelse
            return error.TestUnexpectedResult,
    );
    try std.testing.expect(classify("__ZN2xe3gpu14GraphicsSystem28GetInternalDisplayResolutionEv") == null);

    // A thread entry frame is not a spin. `nearestSymbol` attributes an
    // inlined thread body to the frame that encloses it, so calling these idle
    // would silence the guest main thread along with the watchdogs.
    const guest_thread_body = "__ZNSt3__114__thread_proxyB7v160006INS_5tupleIJNS_10unique_ptrINS_15__thread_structENS_14default_deleteIS3_EEEEZN2xe6kernel7XThread6CreateEvE3$_5EEEEEPvSC_";
    try std.testing.expect(idleLoop(guest_thread_body) == null);
    const watchdog = "__ZNSt3__114__thread_proxyB7v160006INS_5tupleIJNS_10unique_ptrINS_15__thread_structENS_14default_deleteIS3_EEEEZN12_GLOBAL__N_119ScopedStageWatchdogC1EEEEEPvSK_";
    try std.testing.expect(idleLoop(watchdog) == null);
}

test "specific regions win over the class they live in" {
    const precompile = classify("__ZN2xe6kernel9XexModule10PrecompileEv") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.precompile, precompile.phase);
    const save_rest = classify("__ZN2xe6kernel9XexModule12FindSaveRestEv") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.save_rest_scan, save_rest.phase);
    const load = classify("__ZN2xe6kernel9XexModule12LoadContinueEbb") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.module_load, load.phase);
}

test "an unknown symbol leaves the gate exactly as blind as before" {
    try std.testing.expect(classify("_some_unrelated_host_function") == null);
    try std.testing.expect(classify("") == null);
    try std.testing.expect(idleLoop("_some_unrelated_host_function") == null);
}

test "the silent frontier may name an inlined libc++ helper" {
    const fallback = frontierFallback(
        "user_module_ready",
        "__ZNSt3__112__to_addressB7v160006IhEEPT_S2_",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.title_metadata, fallback.phase);
    try std.testing.expect(!fallback.carrier);
    try std.testing.expectEqualStrings("xenia:xam", fallback.owner);
    try std.testing.expect(frontierFallback("shader_storage_requested", "__ZNSt3__112__to_addressEv") == null);
    try std.testing.expect(frontierFallback("user_module_ready", "__ZN13disruptorplus9spin_wait15yield_processorEv") == null);
}

test "every phase names an owner and a stage it cannot precede" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expectEqualStrings("xenia:graphics", owner(.shader_storage));
    try std.testing.expectEqualStrings("shader_storage_requested", afterStage(.shader_storage));
    try std.testing.expectEqualStrings("user_module_ready", afterStage(.title_metadata));
    try std.testing.expectEqualStrings("", afterStage(.host_runtime_carrier));
    var buffer: [phase_count * 2][]const u8 = undefined;
    const names = referencedStageNames(buffer[0..]);
    try std.testing.expect(names.len != 0);
    for (names) |name| try std.testing.expect(name.len != 0);
}

test "the translator's allocator is guest translation, not an unnamed site" {
    // The regression this package exists to prevent a second time: the hottest
    // site of the run that stalled at `ring_buffer_ready` matched no rule, so
    // the one subsystem doing work read as silence.
    const arena = classify("__ZN2xe5Arena5AllocEmm") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.guest_translation, arena.phase);
    try std.testing.expect(!arena.carrier);
    // A class whose name merely ends in "Arena" carries a different Itanium
    // length prefix and must not match.
    try std.testing.expect(classify("__ZN2xe12ScratchArena5AllocEmm") == null);

    const restore = classify(
        "__ZN2xe3cpu9XexModule25RestoreImportThunkBindingEPNS0_13GuestFunctionEb",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.guest_translation, restore.phase);

    const commit = classify(
        "__ZN2xe3cpu7backend3x6412X64CodeCache21CommitExecutableRangeEjj",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.code_cache_commit, commit.phase);
}

test "translation proxies the title once guest main is running" {
    const arena = classify("__ZN2xe5Arena5AllocEmm") orelse
        return error.TestUnexpectedResult;
    // Whose code it is, and whose progress it proves, are different answers.
    try std.testing.expectEqualStrings("xenia:cpu", arena.owner);
    try std.testing.expectEqualStrings("guest:title", arena.proxy_owner);
    try std.testing.expectEqualStrings("guest_main_ready", arena.proxy_after_stage);
    // The proxy is stage-conditional; before guest main the same symbols are
    // Xenia precompiling on its own initiative, and the phase's own
    // prerequisite is the earlier stage.
    try std.testing.expectEqualStrings("processor_ready", afterStage(arena.phase));
}

test "phases without a proxy declare neither half of one" {
    try std.testing.expectEqualStrings("", proxyOwner(.title_metadata));
    try std.testing.expectEqualStrings("", proxyAfterStage(.title_metadata));
    try std.testing.expectEqualStrings("", proxyOwner(.guest_kernel_export));
    // The export phase is already owned by the title; a proxy would be a
    // duplicate rather than a second claim.
    try std.testing.expectEqualStrings("guest:title", owner(.guest_kernel_export));
    var buffer: [phase_count * 2][]const u8 = undefined;
    const owners = referencedOwnerNames(buffer[0..]);
    var saw_title = false;
    for (owners) |name| {
        try std.testing.expect(name.len != 0);
        if (std.mem.eql(u8, name, "guest:title")) saw_title = true;
    }
    try std.testing.expect(saw_title);
}

test "the second wave of carriers inherit rather than name a phase" {
    for ([_][]const u8{
        "__ZNKSt3__113__atomic_baseIbLb0EEcvbB7v160006Ev",
        "__ZNSt3__117__cxx_atomic_loadB7v160006IbEET_PKNS_22__cxx_atomic_base_implIS1_EENS_12memory_orderE",
        "__ZNKSt3__116__tree_node_baseIPvE15__parent_unsafeB7v160006Ev",
        "__ZN2xe9byte_swapIjEET_S1_",
        "__ZN2xe5Clock24host_tick_count_platformEv",
    }) |symbol| {
        const carrier = classify(symbol) orelse return error.TestUnexpectedResult;
        try std.testing.expect(carrier.carrier);
        try std.testing.expectEqualStrings("", carrier.owner);
    }
}

test "a running title is visible through its kernel exports" {
    // Past guest main the instruction pointer is mostly in translated PPC
    // code, which is outside the image and resolves to no symbol. The export
    // shims are the in-image evidence that the title is executing at all.
    const export_body = classify("__ZN2xe6kernel8xboxkrnl28VdInitializeRingBuffer_entryERKNS0_4shim12PointerParamERKNS2_9ParamBaseIiEE") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(Phase.guest_kernel_export, export_body.phase);
    try std.testing.expectEqualStrings("guest:title", export_body.owner);
    try std.testing.expectEqualStrings("guest_main_ready", afterStage(.guest_kernel_export));
    try std.testing.expect(!export_body.carrier);
}

test "package identity is the x86 Xbyak route" {
    try std.testing.expectEqualStrings("x86_64", host_architecture);
    try std.testing.expectEqualStrings("xbyak-x86_64", host_codegen);
}
