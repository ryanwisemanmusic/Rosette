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
    /// Public UI boundaries, independent of the title's output chain.
    ui_output,

    pub fn label(self: Chain) []const u8 {
        return switch (self) {
            .guest_output => "guest_output",
            .audio => "audio",
            .ui_output => "ui_output",
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
    /// Another row in this table whose entry proves the same thing when this
    /// symbol's body has been inlined into its callers.
    ///
    /// An out-of-line copy of a function exists in the COFF table whether or
    /// not anything calls it, so arming its address measures calls, and an
    /// optimizer that inlined the only call site makes a live function read
    /// zero. On the 2026-09-12 image `GraphicsSystem::MarkVblank` is exactly
    /// that: its four-instruction body was inlined into the frame limiter
    /// lambda in `GraphicsSystem::Setup`, the out-of-line copy at
    /// `0x1401b7380` is unreachable, and the chain called the display clock
    /// stopped while it was running.
    ///
    /// The proxy has to be a function the inlined body still *calls*, so it
    /// survives being inlined into. `MarkVblank`'s is
    /// `KernelState::EmulateCPInterruptDPC`: it is the vblank's whole
    /// observable effect, and the inlined copy calls it at the same place
    /// the out-of-line one does.
    ///
    /// Empty when the row stands alone. Never a symbol outside this table -
    /// a proxy that is not itself armed cannot be counted.
    inline_proxy: []const u8 = "",
    /// Whether this row exists only to back another row's `inline_proxy`.
    ///
    /// A proxy is armed and counted like any other milestone, but it is not
    /// a stage of its own: `EmulateCPInterruptDPC` is also reached from
    /// `DispatchInterruptCallback`, so its count answers "did a CP interrupt
    /// reach the guest", not "which one". Reports list it; chains read it
    /// only through the row that names it.
    proxy_only: bool = false,
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
        .mangled = "_ZN2xe3gpu16CommandProcessor10InitializeEv",
        .readable = "CommandProcessor::Initialize",
        .owner = .xenia_emulator,
        .chain = .guest_output,
        .proves = "Xenia's command processor came up and started its worker thread; until this happens there is nothing on the other end of the ring for a title to write to",
    },
    .{
        .mangled = "_ZN2xe3gpu16CommandProcessor16WorkerThreadMainEv",
        .readable = "CommandProcessor::WorkerThreadMain",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proves = "the GPU thread entered its read loop and is waiting on the ring's write pointer. A run where this is met and ExecutePrimaryBuffer is not has a consumer with nothing to consume, which points at the title rather than at Xenia",
    },
    .{
        .mangled = "_ZN2xe3gpu14GraphicsSystem10MarkVblankEv",
        .readable = "GraphicsSystem::MarkVblank",
        .owner = .xenia_emulator,
        .chain = .guest_output,
        .proves = "the emulated display clock is ticking; a title that waits on vblank before drawing cannot progress while this is zero",
        .inline_proxy = "_ZN2xe6kernel11KernelState21EmulateCPInterruptDPCEjjjj",
    },
    .{
        // Not a stage. It is what `MarkVblank` does, and the reason the
        // vblank is observable at all once `MarkVblank` itself has been
        // inlined out of existence.
        .mangled = "_ZN2xe6kernel11KernelState21EmulateCPInterruptDPCEjjjj",
        .readable = "KernelState::EmulateCPInterruptDPC",
        .owner = .xenia_emulator,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "a command-processor interrupt was delivered to the guest. The frame limiter raises one on every vertical blank, so this counts vblanks even in an image where MarkVblank was inlined away",
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
        .mangled = "_ZN2xe6kernel8xboxkrnl16VdQueryVideoModeEPNS0_12X_VIDEO_MODEEb",
        .readable = "xboxkrnl::VdQueryVideoMode",
        .owner = .guest_title,
        .chain = .guest_output,
        .proves = "the title asked the kernel what display it has. This is usually a title's first graphics-related act, so a zero here places it before GPU bring-up entirely rather than stuck inside it",
    },
    .{
        .mangled = "_ZN2xe3gpu14GraphicsSystem20SetInterruptCallbackEjj",
        .readable = "GraphicsSystem::SetInterruptCallback",
        .owner = .guest_title,
        .chain = .guest_output,
        .proves = "the title registered its GPU interrupt handler through VdSetGraphicsInterruptCallback. Vertical blanks are delivered to that handler, so a title that never registers one is not waiting on vblank however many the emulator raises",
    },
    .{
        .mangled = "_ZN2xe3gpu14GraphicsSystem20InitializeRingBufferEjj",
        .readable = "GraphicsSystem::InitializeRingBuffer",
        .owner = .guest_title,
        .chain = .guest_output,
        .proves = "the title called VdInitializeRingBuffer and handed Xenia the address of its command ring; this is the title's first GPU act",
    },
    .{
        // Not a chain stage. Titles that poll the read pointer instead of
        // having it written back never call this, so making it a stage would
        // put a wall in front of a title doing nothing wrong.
        .mangled = "_ZN2xe3gpu14GraphicsSystem26EnableReadPointerWriteBackEjj",
        .readable = "GraphicsSystem::EnableReadPointerWriteBack",
        .owner = .guest_title,
        .chain = .guest_output,
        .proves = "the title asked for the ring's read pointer to be written back into its own memory. Optional, and its absence is not a fault - but paired with a ring that never advances it says which of the two ways the title is watching the GPU",
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
        // `ExecutePrimaryBuffer` is virtual. The PE image's Vulkan command
        // processor dispatches through this override, so the base symbol can
        // be present, armed and still remain at zero while real ring work is
        // executing. This row is a witness for the same chain stage, not a
        // sixteenth stage of its own.
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor20ExecutePrimaryBufferEjj",
        .readable = "VulkanCommandProcessor::ExecutePrimaryBuffer",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the Vulkan command processor's virtual override consumed ring work. C++ virtual dispatch can bypass the base CommandProcessor symbol, so this is the implementation-level witness for ring_carried_work",
    },
    .{
        // As with the primary-buffer override, PM4 dispatch lands in the
        // Vulkan implementation in a Vulkan-backed image. Keep it paired
        // with the base row so the chain observes either legal virtual route.
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType3Ej",
        .readable = "VulkanCommandProcessor::ExecutePacketType3",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the Vulkan command processor's virtual override decoded a type 3 PM4 packet; the base symbol alone is not sufficient evidence when the vtable selects this implementation",
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

    // ---- the title's own code: is it being translated, and does it trap? ----
    //
    // Every row above measures something the title *asked Xenia for*. None of
    // them can tell a title working steadily through its own start-up from a
    // title spinning on one branch, because between two kernel calls the
    // title executes translated PowerPC that Rosette cannot name: on the
    // 2026-09-12 run `Main XThread` held 22% of the interpreter at an address
    // inside Xenia's JIT cache and the report could say nothing else about
    // it. These four are witnesses, never stages - a title that is running
    // correctly and a title that is stuck both reach them.
    .{
        .mangled = "_ZN2xe3cpu3ppc11PPCFrontend14DefineFunctionEPNS0_13GuestFunctionEj",
        .readable = "PPCFrontend::DefineFunction",
        .owner = .guest_title,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "one more of the title's own PowerPC functions was translated to host code. This is the title's progress axis: a count that keeps rising is a title walking through its program, and a count that stopped while the thread still burns instructions is a title looping inside code it already has",
    },
    .{
        .mangled = "_ZN2xe3cpu9Processor15ResolveFunctionEj",
        .readable = "Processor::ResolveFunction",
        .owner = .guest_title,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "translated code branched to a guest address the JIT had not seen before. Compared against DefineFunction it separates a title reaching new code from a title re-entering code it has already run",
    },
    .{
        .mangled = "_ZN2xe3cpu7backend3x6414TrapDebugBreakEPvy",
        .readable = "x64::TrapDebugBreak",
        .owner = .guest_title,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the title executed a PowerPC trap instruction, which is what its own assertions compile to. A non-zero count here is the title reporting a failure of its own, and it is the one witness in this table whose zero is the good outcome",
    },
    .{
        .mangled = "_ZN2xe3gpu16CommandProcessor22HitUnimplementedOpcodeEjj",
        .readable = "CommandProcessor::HitUnimplementedOpcode",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the ring carried a PM4 packet this build of Xenia cannot decode. Reached only after ExecutePacketType3, so a zero while that stage is unmet says nothing; a non-zero is Xenia's gap and not the title's",
    },

    // ---- GPU register delivery: how a title's register write reaches the ring ----
    //
    // A title talks to the GPU by reading and writing registers at guest
    // 0x7FC80000. Xenia commits that block no-access and serves every access
    // from an access violation: the vectored handler hands the fault to the
    // MMIO handler, which decodes the instruction and calls the register
    // callback. On the 2026-09-13 run the title handed Xenia its ring and
    // `ExecutePrimaryBuffer` never ran, and nothing could say whether the
    // title had written the write pointer, because Rosette raised no fault
    // and none of these five had ever been counted. Witnesses, not stages:
    // the chain's `ring_carried_work` stage reads them through its guidance.
    .{
        .mangled = "_ZN2xe24ExceptionHandlerCallbackEP19_EXCEPTION_POINTERS",
        .readable = "ExceptionHandlerCallback",
        .owner = .xenia_emulator,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "Rosette delivered an access violation to Xenia's vectored exception handler. Registered by address, so it cannot be inlined away; zero here while register pages are protected means no GPU register access has ever reached Xenia",
    },
    .{
        .mangled = "_ZN2xe3cpu11MMIOHandler17ExceptionCallbackEPNS_9ExceptionE",
        .readable = "MMIOHandler::ExceptionCallback",
        .owner = .xenia_emulator,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the fault was offered to the MMIO handler, which decodes the faulting mov or movbe and calls the register callback for its range",
    },
    .{
        .mangled = "_ZN2xe3gpu14GraphicsSystem18WriteRegisterThunkEPvPS1_jj",
        .readable = "GraphicsSystem::WriteRegisterThunk",
        .owner = .guest_title,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "a GPU register store from the title arrived at the graphics system. Installed as the MMIO write callback by address, so its count is every delivered store",
    },
    .{
        .mangled = "_ZN2xe3gpu14GraphicsSystem17ReadRegisterThunkEPvPS1_j",
        .readable = "GraphicsSystem::ReadRegisterThunk",
        .owner = .guest_title,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "a GPU register read from the title was answered by the emulated GPU rather than by whatever bytes sat in plain memory - a title polling a status register reads zero forever without this",
    },
    .{
        .mangled = "_ZN2xe3gpu16CommandProcessor18UpdateWritePointerEj",
        .readable = "CommandProcessor::UpdateWritePointer",
        .owner = .guest_title,
        .chain = .guest_output,
        .proves = "the title moved the ring's write pointer and the command processor was told. This is the event ExecutePrimaryBuffer waits for",
        .proxy_only = true,
    },

    // ---- What the ring actually carried ----
    //
    // On the 2026-09-13 run `ExecutePrimaryBuffer` ran twice and
    // `ExecutePacketType3` never did, and the chain's guidance said "padding
    // or type 0 register writes". Nothing had counted type 0. Xenia's
    // `ExecutePacket` skips a header of 0, 0x0BADF00D or 0xCDCDCDCD without
    // calling any executor, so a ring page that reads as zeros where the
    // write pointer says commands are looks exactly like a title that asked
    // for nothing. These rows separate the cases.
    .{
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor13ExecutePacketEv",
        .readable = "VulkanCommandProcessor::ExecutePacket",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the command processor read one ring dword as a packet header. With Type0, Type1 and Type3 all at zero while this is not, every header it read was 0, 0x0BADF00D or 0xCDCDCDCD: the dwords the write pointer covered held no commands",
    },
    .{
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType0Ej",
        .readable = "VulkanCommandProcessor::ExecutePacketType0",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the ring carried a type 0 packet: a run of register writes. A title that writes registers through the ring is configuring the GPU, not yet asking it to draw",
    },
    .{
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType1Ej",
        .readable = "VulkanCommandProcessor::ExecutePacketType1",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the ring carried a type 1 packet: two register writes in one header",
    },
    .{
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor26ExecutePacketType3_ME_INITEjj",
        .readable = "VulkanCommandProcessor::ExecutePacketType3_ME_INIT",
        .owner = .guest_title,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the title initialised the GPU micro-engine: the first type 3 packet a Direct3D device puts on a fresh ring",
    },
    .{
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor34ExecutePacketType3_INDIRECT_BUFFEREjj",
        .readable = "VulkanCommandProcessor::ExecutePacketType3_INDIRECT_BUFFER",
        .owner = .guest_title,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the ring pointed the processor at a title command buffer. Draws live in indirect buffers, so a title that renders reaches this every frame",
    },
    .{
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor21ExecuteIndirectBufferEjj",
        .readable = "VulkanCommandProcessor::ExecuteIndirectBuffer",
        .owner = .xenia_gpu_thread,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "an indirect buffer was walked. Non-zero here with INDIRECT_BUFFER at zero means another packet (a primary-ring IB2) reached it",
    },
    .{
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor31ExecutePacketType3_WAIT_REG_MEMEjj",
        .readable = "VulkanCommandProcessor::ExecutePacketType3_WAIT_REG_MEM",
        .owner = .guest_title,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the title asked the GPU to wait on a register or memory value, usually vsync or its own read pointer; a stall inside this packet is a wait the emulated GPU has to satisfy",
    },
    .{
        .mangled = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor28ExecutePacketType3_INTERRUPTEjj",
        .readable = "VulkanCommandProcessor::ExecutePacketType3_INTERRUPT",
        .owner = .guest_title,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "the title asked the GPU to raise an interrupt back to it, which is how a Direct3D driver learns a command batch finished",
    },

    // ---- Module and file lookups the title's loader makes ----
    .{
        .mangled = "_ZN2xe3vfs17VirtualFileSystem11ResolvePathESt17basic_string_viewIcSt11char_traitsIcEE",
        .readable = "VirtualFileSystem::ResolvePath",
        .owner = .xenia_emulator,
        .chain = .guest_output,
        .proxy_only = true,
        .proves = "Xenia resolved a guest path against its mounted devices. Rosette records the path at entry and the result at return, so a 'device not found' line is joined to the exact path, caller and kernel export that asked, rather than to whatever the thread did by the time the asynchronous logger printed it",
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

    // ---- XMA: the title's compressed audio ----
    //
    // A title's music and most of its effects are XMA. The title writes an
    // XMA context into physical memory and kicks it through the APU register
    // block; Xenia's decoder thread wakes, decodes, and the title mixes the
    // result into the frames it submits. With none of these, every submitted
    // frame can be silence while every stage above reads met.
    .{
        .mangled = "_ZN2xe3apu10XmaDecoder13WriteRegisterEjj",
        .readable = "XmaDecoder::WriteRegister",
        .owner = .guest_title,
        .chain = .audio,
        .proxy_only = true,
        .proves = "the title wrote an XMA decoder register - a context kick, lock or clear. Zero here means the title has not asked for compressed audio to be decoded",
    },
    .{
        .mangled = "_ZN2xe3apu10XmaDecoder16WorkerThreadMainEv",
        .readable = "XmaDecoder::WorkerThreadMain",
        .owner = .xenia_audio,
        .chain = .audio,
        .proxy_only = true,
        .proves = "Xenia's XMA decoder thread started",
    },
    .{
        .mangled = "_ZN2xe3apu10XmaContext4WorkEv",
        .readable = "XmaContext::Work",
        .owner = .xenia_audio,
        .chain = .audio,
        .proxy_only = true,
        .proves = "an XMA context had work: the decoder was kicked and ran for a context the title enabled",
    },
    // ---- UI: entry is not completion; the processor captures selected returns ----
    .{
        .mangled = "_ZN11ImFontAtlas18GetTexDataAsRGBA32EPPhPiS2_S2_",
        .readable = "ImFontAtlas::GetTexDataAsRGBA32",
        .owner = .xenia_ui_thread,
        .chain = .ui_output,
        .proxy_only = true,
        .proves = "the UI requested CPU atlas bytes; only its returned output pointers and dimensions prove availability, not GPU upload or font visibility",
    },
    .{
        .mangled = "_ZN2xe2ui11ImGuiDrawer15RenderDrawListsEP10ImDrawDataRNS0_13UIDrawContextE",
        .readable = "ImGuiDrawer::RenderDrawLists",
        .owner = .xenia_ui_thread,
        .chain = .ui_output,
        .proxy_only = true,
        .proves = "ImGui handed its public geometry and display-size snapshot to the drawer; an empty or invalid snapshot is reported separately",
    },
    .{
        .mangled = "_ZN2xe2ui6vulkan21VulkanImmediateDrawer42EnsurePipelinesCreatedForCurrentRenderPassEv",
        .readable = "VulkanImmediateDrawer::EnsurePipelinesCreatedForCurrentRenderPass",
        .owner = .xenia_ui_thread,
        .chain = .ui_output,
        .proxy_only = true,
        .proves = "the drawer checked its pipelines; its boolean return distinguishes readiness from an early return",
    },
    .{
        .mangled = "_ZN2xe2ui6vulkan21VulkanImmediateDrawer4DrawERKNS0_13ImmediateDrawE",
        .readable = "VulkanImmediateDrawer::Draw",
        .owner = .xenia_ui_thread,
        .chain = .ui_output,
        .proxy_only = true,
        .proves = "the UI requested a draw; public count, primitive, texture and clip are read without modifying Xenia",
    },
    .{
        .mangled = "_ZN2xe2ui15ImmediateDrawer21ScissorToRenderTargetERKNS0_13ImmediateDrawERjS5_S5_S5_",
        .readable = "ImmediateDrawer::ScissorToRenderTarget",
        .owner = .xenia_ui_thread,
        .chain = .ui_output,
        .proxy_only = true,
        .proves = "the draw reached clipping; its boolean return and successful output rectangle show whether clipping rejected it before vkCmdSetScissor",
    },
};

pub fn count() usize {
    return milestones.len;
}

/// The row that still proves `mangled`'s stage when `mangled` was inlined
/// away, or an empty slice when the row stands alone.
pub fn inlineProxyOf(mangled: []const u8) []const u8 {
    const milestone = find(mangled) orelse return "";
    return milestone.inline_proxy;
}

/// Whether a row is a stage in its own right, or only a witness for another.
pub fn isStageRow(mangled: []const u8) bool {
    const milestone = find(mangled) orelse return false;
    return !milestone.proxy_only;
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
        try std.testing.expect(std.mem.startsWith(u8, milestone.mangled, "_ZN"));
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
    var seen_ui = false;
    for (milestones) |milestone| {
        switch (milestone.chain) {
            .audio => {
                try std.testing.expect(!seen_ui);
                seen_audio = true;
            },
            .ui_output => seen_ui = true,
            .guest_output => try std.testing.expect(!seen_audio and !seen_ui),
        }
    }
    try std.testing.expect(countFor(.guest_output) >= 10);
    try std.testing.expect(countFor(.audio) >= 4);
    try std.testing.expectEqual(count(), countFor(.guest_output) + countFor(.audio) + countFor(.ui_output));
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

test "a milestone that can be inlined away names a witness that cannot" {
    // The 2026-09-12 image inlined `GraphicsSystem::MarkVblank` into the
    // frame limiter lambda: the out-of-line body at 0x1401b7380 has no call
    // site anywhere in the 18 MB of .text, so its armed entry count stayed
    // zero for 4.6 billion instructions while the loop that contains its
    // inlined copy held twenty percent of the run. The chain read that zero
    // as "the display clock is stopped" and made it the wall.
    const vblank = find("_ZN2xe3gpu14GraphicsSystem10MarkVblankEv").?;
    try std.testing.expect(vblank.inline_proxy.len != 0);
    try std.testing.expect(!vblank.proxy_only);

    // The proxy has to be in the table, or nothing arms it.
    const proxy = find(vblank.inline_proxy).?;
    try std.testing.expect(proxy.proxy_only);
    try std.testing.expectEqual(vblank.chain, proxy.chain);
    try std.testing.expectEqualStrings(vblank.inline_proxy, inlineProxyOf("_ZN2xe3gpu14GraphicsSystem10MarkVblankEv"));

    // A proxy is a witness, never a stage: `EmulateCPInterruptDPC` is also
    // reached from `DispatchInterruptCallback`.
    try std.testing.expect(!isStageRow(vblank.inline_proxy));
    try std.testing.expect(isStageRow("_ZN2xe3gpu14GraphicsSystem10MarkVblankEv"));
}

test "every declared proxy resolves to a proxy row, and no row proxies itself" {
    for (milestones) |milestone| {
        if (milestone.inline_proxy.len == 0) continue;
        try std.testing.expect(!std.mem.eql(u8, milestone.inline_proxy, milestone.mangled));
        const proxy = find(milestone.inline_proxy) orelse {
            // A proxy outside the table would never be armed, so a row
            // naming one is a hole that reads as evidence.
            try std.testing.expect(false);
            unreachable;
        };
        try std.testing.expect(proxy.proxy_only);
        try std.testing.expect(proxy.inline_proxy.len == 0);
    }
}

test "Vulkan virtual command-processor overrides are witnesses, not extra stages" {
    const primary = find("_ZN2xe3gpu16CommandProcessor20ExecutePrimaryBufferEjj").?;
    const primary_vulkan = find("_ZN2xe3gpu6vulkan22VulkanCommandProcessor20ExecutePrimaryBufferEjj").?;
    const packet = find("_ZN2xe3gpu16CommandProcessor18ExecutePacketType3Ej").?;
    const packet_vulkan = find("_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType3Ej").?;

    try std.testing.expect(!primary.proxy_only);
    try std.testing.expect(!packet.proxy_only);
    try std.testing.expect(primary_vulkan.proxy_only);
    try std.testing.expect(packet_vulkan.proxy_only);
    try std.testing.expectEqual(Chain.guest_output, primary_vulkan.chain);
    try std.testing.expectEqual(Chain.guest_output, packet_vulkan.chain);
    try std.testing.expect(std.mem.indexOf(u8, primary_vulkan.proves, "virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, packet_vulkan.proves, "vtable") != null);
}

test "the ring's packet witnesses and the VFS ledger row are witnesses, not stages" {
    const names = [_][]const u8{
        "_ZN2xe3gpu6vulkan22VulkanCommandProcessor13ExecutePacketEv",
        "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType0Ej",
        "_ZN2xe3gpu6vulkan22VulkanCommandProcessor18ExecutePacketType1Ej",
        "_ZN2xe3gpu6vulkan22VulkanCommandProcessor26ExecutePacketType3_ME_INITEjj",
        "_ZN2xe3gpu6vulkan22VulkanCommandProcessor34ExecutePacketType3_INDIRECT_BUFFEREjj",
        "_ZN2xe3vfs17VirtualFileSystem11ResolvePathESt17basic_string_viewIcSt11char_traitsIcEE",
        "_ZN2xe3apu10XmaDecoder13WriteRegisterEjj",
        "_ZN2xe3apu10XmaContext4WorkEv",
    };
    for (names) |name| {
        const row = find(name).?;
        try std.testing.expect(row.proxy_only);
        try std.testing.expect(!isStageRow(name));
    }
    // A header Xenia skips is the case the whole block exists to expose.
    try std.testing.expect(std.mem.indexOf(u8, find(names[0]).?.proves, "0x0BADF00D") != null);
}

test "an unlisted symbol is not invented" {
    try std.testing.expectEqual(@as(?Milestone, null), find("_ZN2xe3gpu16CommandProcessor13ExecutePacketEv"));
    try std.testing.expectEqual(@as(?usize, null), indexOf(""));
}
