//! The Xenia functions whose first entry answers a question no counter can.
//!
//! Rosette's chains are built from things Rosette can see: Vulkan calls it
//! forwards, Win32 calls it serves, AppKit state it reads. That surface has a
//! hard edge. On the 2026-09-12 run every stage of the fourteen-stage first
//! frame chain read `met`, the presentation chain read `healthy`, and the
//! window was black - because all fourteen stages describe **transport**, and
//! the thing that had not happened was **production**: the title had not
//! drawn anything, so Xenia had nothing to put on the frame it presented.
//!
//! Nothing on Rosette's side of the boundary can distinguish "the emulator is
//! showing the title's picture" from "the emulator is showing an empty
//! window", because both look identical in Vulkan: acquire, begin a render
//! pass that clears, end it, submit, present. The difference is entirely
//! inside Xenia, and Xenia's own functions are the only witnesses.
//!
//! Since `src/tooling/exe_parser/pe_symbols.zig` reads the PE's COFF symbol
//! table, those witnesses have addresses. This package names them.
//!
//! ## Why entry, and not a log line
//!
//! Xenia is a zero-trust program to instrument: it narrates a great deal, and
//! the narration is a claim, not an observation - a line saying a swap was
//! requested is written by the same code path whether or not the swap did
//! anything. The entry of a function is not a claim. `RefreshGuestOutput` is
//! reached only when the GPU command processor has a finished front buffer to
//! hand the presenter; `AudioSystem::RegisterClient` is reached only when the
//! guest has asked for an audio port. A count of zero for either is a fact
//! about the title's progress that no amount of successful Vulkan or WinMM
//! traffic could have produced.
//!
//! ## Why the mangled name is the key
//!
//! The COFF table stores Itanium-mangled names, and Rosette's simplifier is
//! deliberately partial - it recovers the qualified path and drops the
//! parameter list, so `IssueSwap` and an overload of it would collapse to one
//! string. Matching on the mangled name makes each row name exactly one
//! function. The readable name is carried alongside for the report only.
//!
//! ## What this package proves, and what it does not
//!
//! It is a table. It does not resolve an address, arm anything, or count. A
//! name it lists that the image does not contain is reported as `unresolved`
//! by the caller rather than silently dropped, because a milestone that
//! cannot be armed is a hole in the evidence and has to look like one.

const std = @import("std");

/// Who has to act for a milestone to be reached.
///
/// The same vocabulary as the chain reports: a stage that never fires means
/// its owner never got there, and the owner decides where a reader looks.
pub const Owner = enum {
    /// The Xbox 360 title itself, running as translated PowerPC.
    guest_title,
    /// Xenia's emulator/kernel bring-up, before the title has control.
    xenia_emulator,
    /// Xenia's GPU command processor thread.
    xenia_gpu_thread,
    /// Xenia's UI thread: the window, the presenter, ImGui.
    xenia_ui_thread,
    /// Xenia's audio worker.
    xenia_audio,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .guest_title => "guest-title",
            .xenia_emulator => "xenia:emulator",
            .xenia_gpu_thread => "xenia:gpu-thread",
            .xenia_ui_thread => "xenia:ui-thread",
            .xenia_audio => "xenia:audio",
        };
    }
};

/// Which chain a milestone supplies evidence to.
///
/// A milestone belongs to exactly one chain so a reader is never shown the
/// same fact twice under two headings.
pub const Chain = enum {
    /// From "the emulator started" to "the title's picture exists".
    guest_output,
    /// From "the title asked for sound" to "bytes left the host device".
    audio,

    pub fn label(self: Chain) []const u8 {
        return switch (self) {
            .guest_output => "guest_output",
            .audio => "audio",
        };
    }
};

pub const Milestone = struct {
    /// The Itanium-mangled COFF symbol, which names exactly one function.
    mangled: []const u8,
    /// What a report calls it.
    readable: []const u8,
    owner: Owner,
    chain: Chain,
    /// What its first entry proves. Not what the function does - what a
    /// reader learns from the fact that it ran at all.
    proves: []const u8,
};

/// Ordered by dependency within each chain, so a report can walk the table
/// once and print the stages in the order they must happen.
pub const milestones = [_]Milestone{
    // ---- guest output: bring-up, then the title, then the picture ----
    .{
        .mangled = "_ZN2xe3gpu6vulkan20VulkanGraphicsSystem5SetupEPNS_3cpu9ProcessorEPNS_6kernel11KernelStateEPNS_2ui18WindowedAppContextEb",
        .readable = "VulkanGraphicsSystem::Setup",
        .owner = .xenia_emulator,
        .chain = .guest_output,
        .proves = "the Vulkan GPU backend was the one selected and came up; a title cannot draw through a backend that was never set up",
    },
    .{
        .mangled = "_ZN2xe3gpu14GraphicsSystem10MarkVblankEv",
        .readable = "GraphicsSystem::MarkVblank",
        .owner = .xenia_emulator,
        .chain = .guest_output,
        .proves = "the emulated display clock is ticking; a title that waits on vblank before drawing cannot progress while this is zero",
    },
    .{
        .mangled = "_ZN2xe8Emulator14CompleteLaunchERKNSt10filesystem7__cxx114pathESt17basic_string_viewIcSt11char_traitsIcEE",
        .readable = "Emulator::CompleteLaunch",
        .owner = .xenia_emulator,
        .chain = .guest_output,
        .proves = "the module was accepted and the title is about to be given a thread; everything downstream is the title's own progress",
    },
    .{
        .mangled = "_ZN2xe6kernel7XThread7ExecuteEv",
        .readable = "XThread::Execute",
        .owner = .guest_title,
        .chain = .guest_output,
        .proves = "a guest thread began running translated PowerPC; without this no title code has executed at all",
    },
    .{
        .mangled = "_ZN2xe3gpu14GraphicsSystem20InitializeRingBufferEjj",
        .readable = "GraphicsSystem::InitializeRingBuffer",
        .owner = .guest_title,
        .chain = .guest_output,
        .proves = "the title called VdInitializeRingBuffer and handed Xenia the address of its command ring; this is the title's first GPU act",
    },
    .{
        .mangled = "_ZN2xe3gpu16CommandProcessor20ExecutePrimaryBufferEjj",
        .readable = "CommandProcessor::ExecutePrimaryBuffer",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proves = "the command processor found work in the ring and started reading it; a ring that never advances never reaches here",
    },
    .{
        .mangled = "_ZN2xe3gpu16CommandProcessor18ExecutePacketType3Ej",
        .readable = "CommandProcessor::ExecutePacketType3",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proves = "the ring carried real PM4 work rather than padding; draws, state and swaps are all type 3 packets",
    },
    .{
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor9IssueSwapEjjj",
        .readable = "VulkanCommandProcessor::IssueSwap",
        .owner = .guest_title,
        .chain = .guest_output,
        .proves = "the title asked for its front buffer to be shown; this is the exact moment a black window stops being expected",
    },
    .{
        .mangled = "_ZN2xe2ui9Presenter18RefreshGuestOutputEjjjjSt8functionIFbRNS1_25GuestOutputRefreshContextEEE",
        .readable = "Presenter::RefreshGuestOutput",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proves = "a finished guest frame was handed to the presenter's mailbox; this, and only this, is what makes the presenter paint something other than a clear",
    },
    .{
        .mangled = "_ZN2xe2ui9Presenter18ConsumeGuestOutputERjPNS1_21GuestOutputPropertiesEPNS1_22GuestOutputPaintConfigE",
        .readable = "Presenter::ConsumeGuestOutput",
        .owner = .xenia_ui_thread,
        .chain = .guest_output,
        // Deliberately not a chain stage. It is entered on every paint,
        // whether or not the mailbox had anything in it, so its count is a
        // poll count. As a stage it read `met` on the 2026-09-12 run while
        // `RefreshGuestOutput` had run zero times - the painter had polled an
        // empty mailbox once and the chain called that consumed output.
        .proves = "the painting thread reached the guest-output mailbox and looked; compared against RefreshGuestOutput it separates a painter waiting on the title from a frame the painter dropped",
    },
    .{
        .mangled = "_ZN2xe2ui9Presenter26RequestUIPaintFromUIThreadEv",
        .readable = "Presenter::RequestUIPaintFromUIThread",
        .owner = .xenia_ui_thread,
        .chain = .guest_output,
        .proves = "something asked for another paint; after the first frame Xenia paints only when asked, so a count of one here explains a single frame exactly",
    },
    .{
        .mangled = "_ZN2xe2ui9Presenter17PaintFromUIThreadEb",
        .readable = "Presenter::PaintFromUIThread",
        .owner = .xenia_ui_thread,
        .chain = .guest_output,
        .proves = "the window's paint handler ran; the count is the number of frames Xenia actually attempted, whatever the swapchain counters say",
    },

    // ---- audio: from the title asking for sound to the host device ----
    .{
        .mangled = "_ZN2xe3apu11AudioSystem5SetupEPNS_6kernel11KernelStateE",
        .readable = "AudioSystem::Setup",
        .owner = .xenia_emulator,
        .chain = .audio,
        .proves = "an audio system object exists and its worker thread started; the backend chosen by --apu is now live",
    },
    .{
        .mangled = "_ZN2xe3apu11AudioSystem14RegisterClientEjjPy",
        .readable = "AudioSystem::RegisterClient",
        .owner = .guest_title,
        .chain = .audio,
        .proves = "the title asked for an audio port. Xenia creates no driver, and therefore touches no host audio API, until this happens - so a silent run with zero here is the title's progress, not a missing backend",
    },
    .{
        .mangled = "_ZN2xe3apu3sdl14SDLAudioDriver10InitializeEv",
        .readable = "SDLAudioDriver::Initialize",
        .owner = .xenia_audio,
        .chain = .audio,
        .proves = "the SDL backend reached SDL_InitSubSystem and SDL_OpenAudioDevice; this is the first instruction on the path that ends in Rosette's WinMM surface",
    },
    .{
        .mangled = "_ZN2xe3apu11AudioSystem11SubmitFrameEyPf",
        .readable = "AudioSystem::SubmitFrame",
        .owner = .guest_title,
        .chain = .audio,
        .proves = "the title produced PCM. Frames can still be silent, but nothing before this point can be",
    },
};

pub fn count() usize {
    return milestones.len;
}

/// How many milestones belong to one chain, so a report can size its own
/// stage list from the table rather than from a hand-copied constant.
pub fn countFor(chain: Chain) usize {
    var total: usize = 0;
    for (milestones) |milestone| {
        if (milestone.chain == chain) total += 1;
    }
    return total;
}

/// The milestone a mangled symbol names, if this table names it.
pub fn find(mangled: []const u8) ?Milestone {
    for (milestones) |milestone| {
        if (std.mem.eql(u8, milestone.mangled, mangled)) return milestone;
    }
    return null;
}

/// The table index of a mangled symbol, for a caller keeping a parallel array
/// of resolved addresses and hit counts.
pub fn indexOf(mangled: []const u8) ?usize {
    for (milestones, 0..) |milestone, index| {
        if (std.mem.eql(u8, milestone.mangled, mangled)) return index;
    }
    return null;
}

test "the table names exactly one function per row" {
    for (milestones, 0..) |milestone, index| {
        try std.testing.expect(milestone.mangled.len != 0);
        try std.testing.expect(milestone.readable.len != 0);
        try std.testing.expect(milestone.proves.len != 0);
        // Itanium mangling, not a simplified name: a simplified name cannot
        // separate overloads, and `IssueSwap` has four of them in this image.
        try std.testing.expect(std.mem.startsWith(u8, milestone.mangled, "_ZN2xe"));
        for (milestones[0..index]) |earlier| {
            try std.testing.expect(!std.mem.eql(u8, earlier.mangled, milestone.mangled));
            try std.testing.expect(!std.mem.eql(u8, earlier.readable, milestone.readable));
        }
        try std.testing.expectEqual(index, indexOf(milestone.mangled).?);
    }
}

test "each chain is contiguous and ordered by dependency" {
    // A report walks the table once. If a chain's rows were interleaved with
    // another's, walking in order would print the stages out of sequence.
    var seen_audio = false;
    for (milestones) |milestone| {
        switch (milestone.chain) {
            .audio => seen_audio = true,
            .guest_output => try std.testing.expect(!seen_audio),
        }
    }
    try std.testing.expect(countFor(.guest_output) >= 10);
    try std.testing.expect(countFor(.audio) >= 4);
    try std.testing.expectEqual(count(), countFor(.guest_output) + countFor(.audio));
}

test "a poll of the guest-output mailbox is not a frame" {
    // Entry into ConsumeGuestOutput happens on every paint. Reading it as
    // "guest output was consumed" made the 2026-09-12 chain report that
    // stage met while its producer had never run.
    const consume = find("_ZN2xe2ui9Presenter18ConsumeGuestOutputERjPNS1_21GuestOutputPropertiesEPNS1_22GuestOutputPaintConfigE").?;
    try std.testing.expectEqual(Owner.xenia_ui_thread, consume.owner);
    try std.testing.expect(std.mem.indexOf(u8, consume.proves, "looked") != null);
    // The producer is the one whose entry proves a frame exists.
    const refresh = find("_ZN2xe2ui9Presenter18RefreshGuestOutputEjjjjSt8functionIFbRNS1_25GuestOutputRefreshContextEEE").?;
    try std.testing.expectEqual(Owner.xenia_gpu_thread, refresh.owner);
}

test "the milestone that explains a black window is present and owned by the title" {
    // The 2026-09-12 run presented one frame whose only write was a clear.
    // The question that frame could not answer is whether the title ever
    // produced output at all, and this is the row that answers it.
    const refresh = find("_ZN2xe2ui9Presenter18RefreshGuestOutputEjjjjSt8functionIFbRNS1_25GuestOutputRefreshContextEEE").?;
    try std.testing.expectEqual(Chain.guest_output, refresh.chain);
    try std.testing.expectEqual(Owner.xenia_gpu_thread, refresh.owner);

    const swap = find("_ZN2xe3gpu6vulkan22VulkanCommandProcessor9IssueSwapEjjj").?;
    try std.testing.expectEqual(Owner.guest_title, swap.owner);
}

test "the audio chain starts with the title, not with the backend" {
    // Xenia calls no host audio API until the guest registers a client:
    // SDL_InitSubSystem lives inside SDLAudioDriver::Initialize, which is
    // reached only from AudioSystem::CreateDriver. Reporting "no WinMM
    // traffic" as the wall blamed Rosette for the title's progress.
    const register = find("_ZN2xe3apu11AudioSystem14RegisterClientEjjPy").?;
    try std.testing.expectEqual(Owner.guest_title, register.owner);
    try std.testing.expectEqual(Chain.audio, register.chain);

    var register_index: usize = 0;
    var driver_index: usize = 0;
    for (milestones, 0..) |milestone, index| {
        if (std.mem.eql(u8, milestone.readable, "AudioSystem::RegisterClient")) register_index = index;
        if (std.mem.eql(u8, milestone.readable, "SDLAudioDriver::Initialize")) driver_index = index;
    }
    try std.testing.expect(register_index < driver_index);
}

test "an unlisted symbol is not invented" {
    try std.testing.expectEqual(@as(?Milestone, null), find("_ZN2xe3gpu16CommandProcessor13ExecutePacketEv"));
    try std.testing.expectEqual(@as(?usize, null), indexOf(""));
}
