//! What Xenia is doing at a guest address, from the symbol's name alone.
//!
//! Rosette's Windows-route reports carry a guest `rip`. Once that address can
//! be named (`src/tooling/exe_parser/pe_symbols.zig` reads the PE's COFF
//! symbol table), the next question a reader has is not *where* but *what*:
//! a frontier in `xe::threading::Wait` and a frontier in `stbtt__run_charstring`
//! are the same "no frame has been presented" symptom and completely different
//! problems.
//!
//! ## Why this changes a verdict and not just a log line
//!
//! On 2026-09-11 the presentation chain reported
//! `present-chain-no-presents ... diagnosis=guest_never_reached_first_frame_frontier`
//! at step 150,000,000. The guest was inside `stbtt__run_charstring` -
//! rasterizing the ImGui font atlas, with the CJK glyph ranges Rosette's own
//! font mapping makes available. That is a *bounded* computation: it finishes,
//! and until it does no paint is possible because the atlas build happens on
//! the UI thread between "the presenter has a swapchain" and "the window
//! paints". The predictor accused the presenter for a workload that was
//! making ordinary forward progress.
//!
//! So a workload here carries `isBoundedComputation()`. A no-progress
//! predictor that finds the frontier inside one of those must report
//! "not there yet", not a failure - the same rule as
//! `rosette-predictor-suppression-rule`: a pattern is only a problem when an
//! independent progress axis has actually frozen.
//!
//! ## What this proves, and what it does not
//!
//! It is a pure function of a symbol name. It does not know whether the
//! address was reached, how long the workload has been running, or whether it
//! will finish. It cannot classify an address with no symbol, and says so
//! (`.unnamed`) rather than guessing. A name it does not recognize is
//! `.unclassified`, which is deliberately distinct from `.unnamed`: one means
//! "Rosette has no rule for this Xenia function", the other means "the image
//! did not name this address at all", and they send a reader to different
//! places.

const std = @import("std");

/// The kind of work a Xenia symbol represents.
pub const Workload = enum {
    /// The address had no symbol. Not a classification.
    unnamed,
    /// A named symbol with no rule yet.
    unclassified,

    /// TrueType/CFF glyph rasterization (stb_truetype).
    font_rasterization,
    /// Atlas rectangle packing (stb_rect_pack).
    font_atlas_packing,
    /// The rest of the ImGui font atlas build.
    font_atlas_build,
    /// ImGui drawing and layout.
    ui_drawing,

    /// Xenos shader microcode to SPIR-V/DXBC translation.
    shader_translation,
    /// Host graphics pipeline object creation.
    pipeline_creation,
    /// The PM4 command processor and its ring.
    gpu_command_processing,
    /// The presenter, swapchain and guest-output paint path.
    presentation,
    /// Render target and texture cache management.
    gpu_resource_management,

    /// PowerPC to host code translation.
    cpu_translation,
    /// The PPC interpreter and its runtime helpers.
    cpu_execution,

    /// Disc image, STFS and file system traversal.
    media_and_filesystem,
    /// XEX container parsing, decryption and import resolution.
    module_loading,

    /// The HLE kernel: objects, threads, notifications.
    kernel_services,
    /// Audio mixing, XMA decoding and the audio driver.
    audio,
    /// Controller and keyboard input.
    input,

    /// Blocking on a synchronization object.
    waiting,
    /// The host memory allocator and the guest heap.
    memory_management,
    /// Logging and profiling.
    diagnostics,
    /// Compression and cryptography helpers.
    codec_and_crypto,
    /// The C and C++ runtime.
    language_runtime,

    pub fn label(self: Workload) []const u8 {
        return switch (self) {
            .unnamed => "unnamed",
            .unclassified => "unclassified",
            .font_rasterization => "font rasterization",
            .font_atlas_packing => "font atlas packing",
            .font_atlas_build => "font atlas build",
            .ui_drawing => "UI drawing",
            .shader_translation => "shader translation",
            .pipeline_creation => "pipeline creation",
            .gpu_command_processing => "GPU command processing",
            .presentation => "presentation",
            .gpu_resource_management => "GPU resource management",
            .cpu_translation => "guest code translation",
            .cpu_execution => "guest code execution",
            .media_and_filesystem => "media and filesystem",
            .module_loading => "module loading",
            .kernel_services => "kernel services",
            .audio => "audio",
            .input => "input",
            .waiting => "waiting",
            .memory_management => "memory management",
            .diagnostics => "diagnostics",
            .codec_and_crypto => "codec and crypto",
            .language_runtime => "language runtime",
        };
    }

    /// Whether this workload finishes on its own given enough steps.
    ///
    /// A frontier parked in one of these is *slow*, never *stuck*. A
    /// predictor that treats "nothing downstream happened" as a failure has
    /// to suppress itself here, because the thing downstream is waiting on a
    /// computation that has not finished yet - which is a horizon, not a
    /// stall.
    pub fn isBoundedComputation(self: Workload) bool {
        return switch (self) {
            .font_rasterization,
            .font_atlas_packing,
            .font_atlas_build,
            .shader_translation,
            .pipeline_creation,
            .cpu_translation,
            .module_loading,
            .media_and_filesystem,
            .codec_and_crypto,
            => true,
            else => false,
        };
    }

    /// Whether reaching this workload means the guest is between two frames
    /// rather than before its first one.
    pub fn isFrameWork(self: Workload) bool {
        return switch (self) {
            .gpu_command_processing, .presentation, .ui_drawing, .gpu_resource_management => true,
            else => false,
        };
    }
};

/// Which of Xenia's threads normally runs a workload.
///
/// Xenia's UI thread and its emulator thread fail in different ways and are
/// fixed in different places, so a report that names the workload without
/// naming the thread still leaves a reader guessing.
pub const Owner = enum {
    unknown,
    /// The thread that owns the window, the message pump and ImGui.
    ui_thread,
    /// The thread that runs `Emulator::Setup` and launches the title.
    emulator_thread,
    /// A guest (PPC) thread the title created.
    guest_thread,
    /// One of Xenia's own worker threads.
    worker_thread,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .ui_thread => "xenia:ui-thread",
            .emulator_thread => "xenia:emulator-thread",
            .guest_thread => "xenia:guest-thread",
            .worker_thread => "xenia:worker-thread",
        };
    }
};

pub const Classification = struct {
    workload: Workload,
    owner: Owner,
    /// The rule that matched, so a reader can see why a symbol was placed
    /// where it was rather than having to trust the answer.
    matched: []const u8,

    pub fn isBoundedComputation(self: Classification) bool {
        return self.workload.isBoundedComputation();
    }
};

const Rule = struct {
    /// Matched as a prefix of the simplified symbol name.
    prefix: []const u8,
    workload: Workload,
    owner: Owner,
};

/// Ordered most specific first. A prefix that is a prefix of another rule's
/// prefix must come after it, or the general rule swallows the specific one -
/// which is how `xe::gpu::vulkan::VulkanPipelineCache` would have been
/// reported as plain GPU work.
const rules = [_]Rule{
    // ImGui and its bundled rasterizer. The atlas build is the wall between
    // "the presenter has a swapchain" and "the window paints".
    .{ .prefix = "stbtt__", .workload = .font_rasterization, .owner = .ui_thread },
    .{ .prefix = "stbtt_", .workload = .font_rasterization, .owner = .ui_thread },
    .{ .prefix = "stbrp_", .workload = .font_atlas_packing, .owner = .ui_thread },
    .{ .prefix = "rect_height_compare", .workload = .font_atlas_packing, .owner = .ui_thread },
    .{ .prefix = "ImFontAtlas", .workload = .font_atlas_build, .owner = .ui_thread },
    .{ .prefix = "ImFont", .workload = .font_atlas_build, .owner = .ui_thread },
    .{ .prefix = "ImGui_ImplX", .workload = .ui_drawing, .owner = .ui_thread },
    .{ .prefix = "ImDrawList", .workload = .ui_drawing, .owner = .ui_thread },
    .{ .prefix = "ImGui", .workload = .ui_drawing, .owner = .ui_thread },
    .{ .prefix = "xe::ui::ImGuiDrawer", .workload = .ui_drawing, .owner = .ui_thread },

    // Graphics. Presentation before the general ui:: rule so the presenter is
    // never reported as generic windowing.
    .{ .prefix = "xe::ui::vulkan::VulkanPresenter", .workload = .presentation, .owner = .ui_thread },
    .{ .prefix = "xe::ui::Presenter", .workload = .presentation, .owner = .ui_thread },
    .{ .prefix = "xe::ui::vulkan::VulkanImmediateDrawer", .workload = .ui_drawing, .owner = .ui_thread },
    .{ .prefix = "xe::gpu::SpirvShaderTranslator", .workload = .shader_translation, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::DxbcShaderTranslator", .workload = .shader_translation, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::ShaderTranslator", .workload = .shader_translation, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::vulkan::VulkanPipelineCache", .workload = .pipeline_creation, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::vulkan::VulkanRenderTargetCache", .workload = .gpu_resource_management, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::vulkan::VulkanTextureCache", .workload = .gpu_resource_management, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::vulkan::VulkanSharedMemory", .workload = .gpu_resource_management, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::vulkan::VulkanCommandProcessor", .workload = .gpu_command_processing, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::CommandProcessor", .workload = .gpu_command_processing, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::RenderTargetCache", .workload = .gpu_resource_management, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::TextureCache", .workload = .gpu_resource_management, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::GraphicsSystem", .workload = .gpu_command_processing, .owner = .worker_thread },
    .{ .prefix = "xe::gpu::", .workload = .gpu_command_processing, .owner = .worker_thread },

    // CPU.
    .{ .prefix = "xe::cpu::backend::", .workload = .cpu_translation, .owner = .guest_thread },
    .{ .prefix = "xe::cpu::compiler::", .workload = .cpu_translation, .owner = .guest_thread },
    .{ .prefix = "xe::cpu::hir::", .workload = .cpu_translation, .owner = .guest_thread },
    .{ .prefix = "xe::cpu::ppc::", .workload = .cpu_execution, .owner = .guest_thread },
    .{ .prefix = "xe::cpu::XexModule", .workload = .module_loading, .owner = .emulator_thread },
    .{ .prefix = "xe::cpu::Module", .workload = .module_loading, .owner = .emulator_thread },
    .{ .prefix = "xe::cpu::", .workload = .cpu_execution, .owner = .guest_thread },

    // Title intake.
    .{ .prefix = "xe::vfs::", .workload = .media_and_filesystem, .owner = .emulator_thread },
    .{ .prefix = "xe::kernel::util::XexModule", .workload = .module_loading, .owner = .emulator_thread },
    .{ .prefix = "xe::kernel::UserModule", .workload = .module_loading, .owner = .emulator_thread },
    .{ .prefix = "xe::kernel::", .workload = .kernel_services, .owner = .guest_thread },

    // Audio and input.
    .{ .prefix = "xe::apu::", .workload = .audio, .owner = .worker_thread },
    .{ .prefix = "xe::hid::", .workload = .input, .owner = .ui_thread },

    // Everything else in Xenia.
    .{ .prefix = "xe::threading::Wait", .workload = .waiting, .owner = .unknown },
    .{ .prefix = "xe::threading::", .workload = .kernel_services, .owner = .unknown },
    .{ .prefix = "xe::memory::", .workload = .memory_management, .owner = .unknown },
    .{ .prefix = "xe::BaseHeap", .workload = .memory_management, .owner = .unknown },
    .{ .prefix = "xe::Memory", .workload = .memory_management, .owner = .unknown },
    .{ .prefix = "xe::logging::", .workload = .diagnostics, .owner = .unknown },
    .{ .prefix = "xe::Profiler", .workload = .diagnostics, .owner = .unknown },
    .{ .prefix = "xe::ui::", .workload = .ui_drawing, .owner = .ui_thread },

    // Third-party code Xenia links statically.
    .{ .prefix = "pthread_cond_wait", .workload = .waiting, .owner = .unknown },
    .{ .prefix = "pthread_cond_timedwait", .workload = .waiting, .owner = .unknown },
    .{ .prefix = "WaitForSingleObject", .workload = .waiting, .owner = .unknown },
    .{ .prefix = "aes_", .workload = .codec_and_crypto, .owner = .emulator_thread },
    .{ .prefix = "rijndael", .workload = .codec_and_crypto, .owner = .emulator_thread },
    .{ .prefix = "sha1::", .workload = .codec_and_crypto, .owner = .emulator_thread },
    .{ .prefix = "mz_", .workload = .codec_and_crypto, .owner = .emulator_thread },
    .{ .prefix = "lzx", .workload = .codec_and_crypto, .owner = .emulator_thread },
    .{ .prefix = "inflate", .workload = .codec_and_crypto, .owner = .emulator_thread },
    .{ .prefix = "tinflate", .workload = .codec_and_crypto, .owner = .emulator_thread },

    // The runtime under everything. Last, so a C++ name that happens to start
    // with one of these does not outrank a Xenia rule.
    .{ .prefix = "std::", .workload = .language_runtime, .owner = .unknown },
    .{ .prefix = "operator new", .workload = .memory_management, .owner = .unknown },
    .{ .prefix = "malloc", .workload = .memory_management, .owner = .unknown },
    .{ .prefix = "free", .workload = .memory_management, .owner = .unknown },
    .{ .prefix = "__cxa_", .workload = .language_runtime, .owner = .unknown },
    .{ .prefix = "_Unwind_", .workload = .language_runtime, .owner = .unknown },
};

/// Classify a simplified symbol name. An empty name is `.unnamed`.
pub fn classify(symbol: []const u8) Classification {
    if (symbol.len == 0) {
        return .{ .workload = .unnamed, .owner = .unknown, .matched = "" };
    }
    for (rules) |rule| {
        if (std.mem.startsWith(u8, symbol, rule.prefix)) {
            return .{ .workload = rule.workload, .owner = rule.owner, .matched = rule.prefix };
        }
    }
    return .{ .workload = .unclassified, .owner = .unknown, .matched = "" };
}

/// The number of classification rules, so a report can state the size of the
/// surface it is measuring against rather than implying it is complete.
pub fn ruleCount() usize {
    return rules.len;
}

test "the font atlas build is recognized and is a bounded computation" {
    // The exact frontier of the 2026-09-11 run.
    const charstring = classify("stbtt__run_charstring");
    try std.testing.expectEqual(Workload.font_rasterization, charstring.workload);
    try std.testing.expectEqual(Owner.ui_thread, charstring.owner);
    try std.testing.expect(charstring.isBoundedComputation());

    const packing = classify("rect_height_compare");
    try std.testing.expectEqual(Workload.font_atlas_packing, packing.workload);
    try std.testing.expect(packing.isBoundedComputation());
}

test "an unnamed address is not classified as unrecognized work" {
    // These two states send a reader to different places: one is a gap in
    // this table, the other is a gap in the image's symbols.
    try std.testing.expectEqual(Workload.unnamed, classify("").workload);
    try std.testing.expectEqual(Workload.unclassified, classify("SomeFunctionNobodyMapped").workload);
}

test "a specific graphics rule outranks the general one" {
    try std.testing.expectEqual(
        Workload.pipeline_creation,
        classify("xe::gpu::vulkan::VulkanPipelineCache::ConfigurePipeline").workload,
    );
    try std.testing.expectEqual(
        Workload.gpu_command_processing,
        classify("xe::gpu::vulkan::VulkanCommandProcessor::IssueDraw").workload,
    );
    try std.testing.expectEqual(
        Workload.presentation,
        classify("xe::ui::Presenter::PaintFromUIThread").workload,
    );
    // The general xe::ui:: rule must not have swallowed the presenter above.
    try std.testing.expectEqual(
        Workload.ui_drawing,
        classify("xe::ui::Window::OnPaint").workload,
    );
}

test "waiting is never a bounded computation" {
    const waiting = classify("xe::threading::Wait");
    try std.testing.expectEqual(Workload.waiting, waiting.workload);
    // A frontier parked in a wait is exactly the case a no-progress predictor
    // must still be allowed to accuse; suppressing it here would remove the
    // one signal that matters.
    try std.testing.expect(!waiting.isBoundedComputation());
}

test "every rule prefix is non-empty and no general rule precedes a rule it would swallow" {
    for (rules, 0..) |rule, index| {
        try std.testing.expect(rule.prefix.len != 0);
        for (rules[index + 1 ..]) |later| {
            // A later rule that begins with an earlier rule's prefix can never
            // match, because the earlier one always wins first.
            if (std.mem.startsWith(u8, later.prefix, rule.prefix)) {
                std.debug.print(
                    "unreachable rule: '{s}' is shadowed by the earlier '{s}'\n",
                    .{ later.prefix, rule.prefix },
                );
                return error.ShadowedRule;
            }
        }
    }
}

test "every workload has a label and the bounded set is the set a predictor may suppress on" {
    inline for (@typeInfo(Workload).@"enum".fields) |field| {
        const workload: Workload = @enumFromInt(field.value);
        try std.testing.expect(workload.label().len != 0);
    }
    // Suppression is only correct for work that terminates. Neither of the
    // two "no classification" states may ever suppress anything, or an
    // unnamed stall becomes invisible.
    try std.testing.expect(!Workload.unnamed.isBoundedComputation());
    try std.testing.expect(!Workload.unclassified.isBoundedComputation());
}
