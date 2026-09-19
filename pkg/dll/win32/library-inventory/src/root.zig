//! Which libraries make up the Windows surface Rosetta models, and what
//! capability each one is.
//!
//! Two questions were being answered by the same flat list of DLL names, and
//! they are not the same question:
//!
//! 1. *May a name from this library be resolved against Rosetta's Win32/UCRT
//!    inventory at all?* A third-party DLL that happens to export a name
//!    spelled like a Win32 one must not borrow its implementation, so this
//!    has to be an allow-list rather than a guess.
//! 2. *What capability does this library provide?* A report that groups a
//!    degraded import under "GDI32.dll" tells you a filename. Grouping it
//!    under "legacy 2D drawing" tells you whether the run can proceed
//!    without it.
//!
//! The second question is the one that makes an import report readable: 415
//! eligible names across 26 libraries is a number nobody can act on, while
//! "the registry is unimplemented and the title reads settings from it" is.
//!
//! ## What this package proves, and what it does not
//!
//! It classifies **library identity**, from the name alone. It does not know
//! whether a library is present on the host, whether Rosetta implements any
//! particular export, or whether a run called one. Those are runtime facts and
//! live with the runtime.

const std = @import("std");
const catalogue = @import("dll_win32_catalogue");
const capability_gap = @import("dll_win32_capability_gap");

/// The capability a Windows library provides, as far as a guest is concerned.
///
/// The grouping is by what a guest loses when the library is unimplemented,
/// not by which Microsoft team shipped it -- so the registry is separate from
/// the rest of ADVAPI32's security surface, because losing one stops a title
/// reading its settings and losing the other usually does not.
pub const Subsystem = enum {
    /// Process, memory, handle, file and synchronization primitives. A guest
    /// cannot start without these.
    kernel,
    /// The C runtime: allocation, string handling, formatted I/O, math,
    /// locale. Also load-bearing for startup.
    c_runtime,
    /// Windows, messages, input and the message pump.
    windowing,
    /// Legacy 2D drawing: device contexts, bitmaps, fonts, blits.
    legacy_drawing,
    /// The registry.
    configuration_store,
    /// Access tokens, privileges, services, and the security surface that is
    /// not the registry.
    security,
    /// COM, OLE, WinRT and the activation surface.
    component_object,
    /// Direct3D, DXGI and the desktop compositor.
    graphics_stack,
    /// Sockets.
    networking,
    /// Audio, timers and the multimedia surface.
    multimedia,
    /// Game controllers: XInput and the libraries a controller stack loads
    /// dynamically. Separate from `device_enumeration` because losing this is
    /// "no controller" while losing that is "no device list", and a title
    /// notices the two at completely different points.
    game_input,
    /// Input method editors and text services.
    text_input,
    /// Shell paths, file dialogs and drag-and-drop.
    shell,
    /// Device enumeration and configuration.
    device_enumeration,
    /// Symbol lookup, stack walking and version resources -- diagnostics a
    /// guest can normally proceed without.
    diagnostics,
    /// A library Rosetta does not recognize as part of the Windows surface.
    unrecognized,

    pub fn label(self: Subsystem) []const u8 {
        return switch (self) {
            .kernel => "kernel",
            .c_runtime => "C runtime",
            .windowing => "windowing and input",
            .legacy_drawing => "legacy 2D drawing",
            .configuration_store => "registry",
            .security => "security and services",
            .component_object => "COM/OLE/WinRT",
            .graphics_stack => "Direct3D/DXGI",
            .networking => "sockets",
            .multimedia => "audio and timers",
            .game_input => "game controllers",
            .text_input => "text input",
            .shell => "shell and file dialogs",
            .device_enumeration => "device enumeration",
            .diagnostics => "diagnostics",
            .unrecognized => "unrecognized",
        };
    }

    /// Whether a guest can normally reach its main loop with this subsystem
    /// unimplemented.
    ///
    /// This is about *reaching* the loop, not about running correctly: a
    /// title with no registry still starts, it just cannot remember anything.
    /// A report uses this to sort what to implement first, never to decide
    /// that something may be skipped.
    pub fn startupCritical(self: Subsystem) bool {
        return switch (self) {
            .kernel, .c_runtime, .windowing => true,
            .legacy_drawing,
            .configuration_store,
            .security,
            .component_object,
            .graphics_stack,
            .networking,
            .multimedia,
            .game_input,
            .text_input,
            .shell,
            .device_enumeration,
            .diagnostics,
            .unrecognized,
            => false,
        };
    }
};

const LibraryEntry = struct { stem: []const u8, subsystem: Subsystem };

/// Libraries named exactly. The `.dll` suffix is optional at the call site:
/// a dynamic lookup does not always retain it.
const libraries = [_]LibraryEntry{
    .{ .stem = "kernel32", .subsystem = .kernel },
    .{ .stem = "kernelbase", .subsystem = .kernel },
    .{ .stem = "ntdll", .subsystem = .kernel },
    .{ .stem = "psapi", .subsystem = .kernel },
    .{ .stem = "powrprof", .subsystem = .kernel },

    .{ .stem = "msvcrt", .subsystem = .c_runtime },
    .{ .stem = "ucrtbase", .subsystem = .c_runtime },
    .{ .stem = "vcruntime140", .subsystem = .c_runtime },
    .{ .stem = "vcruntime140_1", .subsystem = .c_runtime },
    .{ .stem = "libwinpthread-1", .subsystem = .c_runtime },
    .{ .stem = "libstdc++-6", .subsystem = .c_runtime },
    .{ .stem = "libgcc_s_seh-1", .subsystem = .c_runtime },

    .{ .stem = "user32", .subsystem = .windowing },
    .{ .stem = "gdi32", .subsystem = .legacy_drawing },
    .{ .stem = "gdiplus", .subsystem = .legacy_drawing },
    .{ .stem = "uxtheme", .subsystem = .legacy_drawing },
    .{ .stem = "advapi32", .subsystem = .security },
    .{ .stem = "secur32", .subsystem = .security },
    .{ .stem = "userenv", .subsystem = .security },

    .{ .stem = "ole32", .subsystem = .component_object },
    .{ .stem = "oleaut32", .subsystem = .component_object },
    .{ .stem = "combase", .subsystem = .component_object },
    .{ .stem = "propsys", .subsystem = .component_object },

    .{ .stem = "dxgi", .subsystem = .graphics_stack },
    .{ .stem = "d3d11", .subsystem = .graphics_stack },
    .{ .stem = "d3d12", .subsystem = .graphics_stack },
    .{ .stem = "d3dcompiler_47", .subsystem = .graphics_stack },
    .{ .stem = "dwmapi", .subsystem = .graphics_stack },
    .{ .stem = "opengl32", .subsystem = .graphics_stack },
    // Rosetta virtualizes the Vulkan loader itself: a guest that loads this
    // library reaches Rosetta's typed forwarder, not a host DLL. Refusing it
    // would end the graphics path at its first call.
    .{ .stem = "vulkan-1", .subsystem = .graphics_stack },

    .{ .stem = "ws2_32", .subsystem = .networking },
    .{ .stem = "wsock32", .subsystem = .networking },
    .{ .stem = "iphlpapi", .subsystem = .networking },
    .{ .stem = "winhttp", .subsystem = .networking },

    .{ .stem = "winmm", .subsystem = .multimedia },
    .{ .stem = "avrt", .subsystem = .multimedia },
    .{ .stem = "mmdevapi", .subsystem = .multimedia },

    // Every XInput spelling a controller stack tries in turn. Rosetta serves
    // the XInput entry points, including the ordinal-100 `XInputGetStateEx`
    // that Xenia uses for the guide button.
    .{ .stem = "xinput1_4", .subsystem = .game_input },
    .{ .stem = "xinput1_3", .subsystem = .game_input },
    .{ .stem = "xinput1_2", .subsystem = .game_input },
    .{ .stem = "xinput1_1", .subsystem = .game_input },
    .{ .stem = "xinput9_1_0", .subsystem = .game_input },

    .{ .stem = "imm32", .subsystem = .text_input },
    .{ .stem = "msctf", .subsystem = .text_input },

    .{ .stem = "shell32", .subsystem = .shell },
    .{ .stem = "shlwapi", .subsystem = .shell },
    .{ .stem = "shcore", .subsystem = .shell },
    .{ .stem = "comdlg32", .subsystem = .shell },

    .{ .stem = "setupapi", .subsystem = .device_enumeration },
    .{ .stem = "cfgmgr32", .subsystem = .device_enumeration },
    .{ .stem = "hid", .subsystem = .device_enumeration },
    .{ .stem = "winusb", .subsystem = .device_enumeration },
    .{ .stem = "libusbk", .subsystem = .device_enumeration },

    .{ .stem = "dbghelp", .subsystem = .diagnostics },
    .{ .stem = "version", .subsystem = .diagnostics },
    .{ .stem = "imagehlp", .subsystem = .diagnostics },
};

/// API-set prefixes. Windows resolves these to the libraries above, so a PE
/// that imports through them is importing the same surface -- accepting only
/// the `api-ms-win-crt-` subset made an image that uses the core sets look
/// like it was calling unknown symbols.
const ApiSetEntry = struct { prefix: []const u8, subsystem: Subsystem };

const api_sets = [_]ApiSetEntry{
    .{ .prefix = "api-ms-win-crt-", .subsystem = .c_runtime },
    .{ .prefix = "api-ms-win-core-registry-", .subsystem = .configuration_store },
    .{ .prefix = "api-ms-win-core-winrt-", .subsystem = .component_object },
    .{ .prefix = "api-ms-win-core-com-", .subsystem = .component_object },
    .{ .prefix = "api-ms-win-security-", .subsystem = .security },
    .{ .prefix = "api-ms-win-shcore-", .subsystem = .shell },
    .{ .prefix = "api-ms-win-core-", .subsystem = .kernel },
    // The generic tails. Order matters: the specific sets above have to win.
    .{ .prefix = "api-ms-win-", .subsystem = .kernel },
    .{ .prefix = "ext-ms-win-", .subsystem = .kernel },
};

fn matchesStem(dll_name: []const u8, stem: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(dll_name, stem)) return true;
    if (dll_name.len != stem.len + 4) return false;
    return std.ascii.eqlIgnoreCase(dll_name[0..stem.len], stem) and
        std.ascii.eqlIgnoreCase(dll_name[stem.len..], ".dll");
}

/// The capability a library provides, or `.unrecognized`.
///
/// An empty name is `.unrecognized` rather than a guess: a dynamic lookup
/// that lost its library still carries a real API name, and classifying *that*
/// is the return contract's job, not this one's.
pub fn subsystemFor(dll_name: []const u8) Subsystem {
    if (dll_name.len == 0) return .unrecognized;
    for (libraries) |entry| {
        if (matchesStem(dll_name, entry.stem)) return entry.subsystem;
    }
    for (api_sets) |entry| {
        if (std.ascii.startsWithIgnoreCase(dll_name, entry.prefix)) return entry.subsystem;
    }
    return .unrecognized;
}

/// Whether a name imported from this library may be resolved against
/// Rosetta's Win32/UCRT inventory.
///
/// This is the allow-list half. A third-party DLL exporting something spelled
/// like a Win32 routine must not silently receive the Win32 implementation,
/// so an unrecognized library is refused even when the name looks familiar.
pub fn isWindowsSurface(dll_name: []const u8) bool {
    return subsystemFor(dll_name) != .unrecognized;
}

/// Whether a dynamic load of this library can be honoured, and if not, why.
///
/// A `LoadLibrary` that succeeds is a promise the caller will immediately
/// collect on. Two different situations produce a broken promise and they
/// send a reader to opposite places, so a run has to name which one it hit:
///
/// * `no_backend` - the library is part of the Windows surface Rosetta
///   models, and Rosetta still has nothing to put behind it. Direct3D is the
///   whole of this set: the names have return contracts, but there is no
///   device, and a guest that loads D3D12 proceeds straight to creating one.
///   This is a *decision*, not a gap, and every caller of these has a
///   documented fallback because they are all runtime-probed.
/// * `outside_modelled_surface` - Rosetta does not model the library at all.
///   This is where a genuine gap shows up, so a run that reports one is
///   telling you a package may be missing.
pub const ModuleAvailability = enum {
    served,
    no_backend,
    outside_modelled_surface,

    pub fn label(self: ModuleAvailability) []const u8 {
        return switch (self) {
            .served => "served",
            .no_backend => "no-backend-behind-a-modelled-name",
            .outside_modelled_surface => "outside-the-modelled-Win32-surface",
        };
    }

    /// Whether a run should read this refusal as something to fix.
    ///
    /// A deliberate refusal is evidence the policy worked. Treating the two
    /// the same is how a log full of correct decisions hides the one library
    /// nobody has written yet.
    pub fn isGap(self: ModuleAvailability) bool {
        return self == .outside_modelled_surface;
    }
};

/// Libraries Rosetta deliberately will not load.
///
/// Two kinds live here. Direct3D is named and contracted but has no device
/// behind it. A graphics debugger's injected DLL is different: it is only
/// ever present when a human attached the debugger, and reporting it absent
/// is the *correct* answer on every machine where nobody did. Neither is a
/// gap, and a run that reports them as gaps buries the library that is one.
const no_backend_libraries = [_][]const u8{
    "d3d11",
    "d3d12",
    "dxgi",
    "d3dcompiler_47",
    "opengl32",
    // Injected by RenderDoc when a capture session is attached. Xenia probes
    // for it with `GetModuleHandleW` and proceeds without it, which is what
    // happens on any machine that is not running a capture.
    "renderdoc",
    // Xenia probes this third-party USB backend opportunistically. Rosetta
    // has no Windows USB kernel driver to put behind it, so the honest result
    // is a deliberate no-backend policy rather than an inventory gap.
    "libusbk",
    // SDL tries DirectSound before WinMM and takes WinMM when DirectSound is
    // absent. WinMM is the audio path Rosetta models end to end into
    // CoreAudio, and the launcher selects SDL for exactly that reason; a
    // DirectSound name with no device behind it would move SDL onto an API
    // that cannot make a sound. Absence is the decision here, not a hole.
    "dsound",
};

pub fn moduleAvailability(dll_name: []const u8) ModuleAvailability {
    if (dll_name.len == 0) return .outside_modelled_surface;
    for (no_backend_libraries) |stem| {
        if (matchesStem(dll_name, stem)) return .no_backend;
    }
    if (!isWindowsSurface(dll_name)) return .outside_modelled_surface;
    return .served;
}

/// The path a deliberate dynamic-module refusal leaves the caller on.
///
/// This is intentionally a short, stable token rather than a prose diagnosis:
/// the runtime includes it in the source-of-truth log, and tooling can group
/// several spellings of the same optional probe without parsing a sentence.
/// An unavailable library outside Rosetta's model has no safe fallback; that
/// distinction must remain visible instead of being hidden behind a fake
/// handle.
pub fn moduleFallback(dll_name: []const u8) []const u8 {
    if (matchesStem(dll_name, "d3d11") or
        matchesStem(dll_name, "d3d12") or
        matchesStem(dll_name, "dxgi") or
        matchesStem(dll_name, "d3dcompiler_47") or
        matchesStem(dll_name, "opengl32"))
    {
        return "vulkan-graphics-path";
    }
    if (matchesStem(dll_name, "dsound")) return "winmm-coreaudio-path";
    if (matchesStem(dll_name, "renderdoc")) return "no-capture-session";
    if (matchesStem(dll_name, "libusbk")) return "no-windows-usb-backend";
    return switch (moduleAvailability(dll_name)) {
        .served => "served",
        .no_backend => "no-backend-fallback-unclassified",
        .outside_modelled_surface => "none-outside-modelled-surface",
    };
}

/// Classify only the names owned by the per-DLL packages. An empty DLL name
/// is the GetProcAddress case: the catalogue deliberately permits its
/// name-only dynamic bucket. A non-empty unknown DLL still fails the surface
/// gate before it can borrow a familiar Win32 answer.
pub fn isContractImport(dll_name: []const u8, function_name: []const u8) bool {
    if (dll_name.len != 0 and !isWindowsSurface(dll_name)) return false;
    return catalogue.isContractImport(dll_name, function_name);
}

/// Compatibility spelling retained for package tests and older integrations.
pub const isDegradedImport = isContractImport;

/// An export Rosette declines on purpose. Distinct from a degraded import:
/// that is a name Rosette serves with a refusal value, this is a name Rosette
/// refuses to resolve at all, deliberately.
pub const isDeliberateExportRefusal = catalogue.isDeliberateExportRefusal;

/// What a declined library would have to gain before Rosette could serve it.
/// Re-exported here so a caller that already knows the inventory of names can
/// reach the inventory of missing conditions without a second dependency.
pub const capabilityGapFor = capability_gap.inventoryFor;

/// The declared ABI for one export, from the package that owns it.
pub const declaredExport = catalogue.declaredExport;
pub const CapabilityGap = capability_gap.Inventory;
pub const CapabilityCondition = capability_gap.Condition;

pub const degraded_package_count = catalogue.package_count;

/// The number of libraries named explicitly, for a report that wants to say
/// how wide the inventory is rather than only which entry matched.
pub const named_library_count: usize = libraries.len;
pub const api_set_prefix_count: usize = api_sets.len;

test "a library is recognized with or without its suffix, and case does not matter" {
    try std.testing.expectEqual(Subsystem.kernel, subsystemFor("KERNEL32.dll"));
    try std.testing.expectEqual(Subsystem.kernel, subsystemFor("kernel32"));
    try std.testing.expectEqual(Subsystem.kernel, subsystemFor("Kernel32.DLL"));
    try std.testing.expectEqual(Subsystem.legacy_drawing, subsystemFor("GDI32.dll"));
    try std.testing.expectEqual(Subsystem.windowing, subsystemFor("USER32.dll"));
    try std.testing.expectEqual(Subsystem.component_object, subsystemFor("ole32.dll"));
}

test "the libraries a guest loads dynamically to reach graphics and input are on the surface" {
    // `LoadLibrary` is an allow-list: a module outside this inventory is
    // reported absent, and every caller then takes its own missing-library
    // path. Two of those paths end a run rather than degrading it, so they
    // are pinned here rather than left to a reader to rediscover from a log.
    //
    // Vulkan: Xenia reaches its entire graphics stack through
    // `LoadLibraryW(L"vulkan-1.dll")` and gives up immediately if it fails.
    try std.testing.expect(isWindowsSurface("vulkan-1.dll"));
    try std.testing.expectEqual(Subsystem.graphics_stack, subsystemFor("vulkan-1.dll"));
    // XInput: the controller stack tries each spelling in turn, and the
    // driver returns X_STATUS_DLL_NOT_FOUND when the first one is absent.
    try std.testing.expect(isWindowsSurface("xinput1_4.dll"));
    try std.testing.expect(isWindowsSurface("XInput1_3.dll"));
    try std.testing.expect(isWindowsSurface("XInput9_1_0.dll"));
    try std.testing.expectEqual(Subsystem.game_input, subsystemFor("xinput1_4"));
}

test "a deliberate refusal and a missing package are different findings" {
    // Direct3D is named, contracted, and still unloadable: there is no device
    // behind it. That is the policy working, not a gap.
    try std.testing.expectEqual(ModuleAvailability.no_backend, moduleAvailability("D3D12.dll"));
    try std.testing.expectEqual(ModuleAvailability.no_backend, moduleAvailability("dxgi.dll"));
    try std.testing.expect(!moduleAvailability("D3D12.dll").isGap());
    // A debugger's injected DLL is absent on every machine without the
    // debugger attached, so reporting it absent is the right answer, not a
    // missing package.
    try std.testing.expectEqual(ModuleAvailability.no_backend, moduleAvailability("renderdoc.dll"));
    try std.testing.expect(!moduleAvailability("renderdoc.dll").isGap());

    // A library nobody has written a package for is a gap, and a run that
    // reports one is telling you what to add.
    try std.testing.expectEqual(
        ModuleAvailability.outside_modelled_surface,
        moduleAvailability("XAudio2_8.dll"),
    );
    try std.testing.expect(moduleAvailability("XAudio2_8.dll").isGap());

    try std.testing.expectEqual(ModuleAvailability.served, moduleAvailability("vulkan-1.dll"));
    try std.testing.expectEqual(ModuleAvailability.served, moduleAvailability("SHCore.dll"));
    try std.testing.expectEqual(ModuleAvailability.served, moduleAvailability("hid.dll"));
    try std.testing.expectEqual(ModuleAvailability.no_backend, moduleAvailability("libusbK.dll"));
    try std.testing.expect(!moduleAvailability("libusbK.dll").isGap());
    // An empty name is not a library.
    try std.testing.expectEqual(ModuleAvailability.outside_modelled_surface, moduleAvailability(""));
}

test "libraries Rosetta cannot serve stay off the surface so a load reports absent" {
    // XAudio2 is the case that motivated the allow-list. Rosetta has no
    // XAudio2 implementation, and letting the load succeed made Xenia's audio
    // driver call `XAudio2Create`, whose unimplemented return is zero - which
    // is S_OK for an HRESULT - and then dereference an interface pointer it
    // was never given.
    try std.testing.expect(!isWindowsSurface("XAudio2_8.dll"));
    try std.testing.expect(!isWindowsSurface("XAudio2_9.dll"));
    // Direct3D's shader compilers and DirectSound are optional everywhere
    // they are used, so an absent report sends each caller down a path it
    // already handles.
    try std.testing.expect(!isWindowsSurface("dxcompiler.dll"));
    try std.testing.expect(!isWindowsSurface("dxilconv.dll"));
    try std.testing.expect(!isWindowsSurface("DSOUND.DLL"));
    try std.testing.expect(!isWindowsSurface("dinput8.dll"));
}

test "an unrecognized library is refused rather than given the Win32 surface" {
    // A third-party DLL exporting a Win32-looking name must not borrow the
    // Win32 implementation for it.
    try std.testing.expectEqual(Subsystem.unrecognized, subsystemFor("mygame_helper.dll"));
    try std.testing.expect(!isWindowsSurface("mygame_helper.dll"));
    // A partial name is not a prefix match: `kernel32x.dll` is not kernel32.
    try std.testing.expectEqual(Subsystem.unrecognized, subsystemFor("kernel32x.dll"));
    try std.testing.expectEqual(Subsystem.unrecognized, subsystemFor("kernel3"));
    // An empty name belongs to the return contract, not to this package.
    try std.testing.expectEqual(Subsystem.unrecognized, subsystemFor(""));
}

test "degraded imports are delegated to their per-DLL package" {
    try std.testing.expect(isDegradedImport("KERNEL32.dll", "GetThreadPriority"));
    try std.testing.expect(isDegradedImport("", "LibK_GetVersion"));
    try std.testing.expect(!isDegradedImport("third_party.dll", "GetThreadPriority"));
}

test "API sets resolve to the surface they forward to, most specific first" {
    try std.testing.expectEqual(Subsystem.c_runtime, subsystemFor("api-ms-win-crt-string-l1-1-0.dll"));
    try std.testing.expectEqual(
        Subsystem.configuration_store,
        subsystemFor("api-ms-win-core-registry-l1-1-0.dll"),
    );
    try std.testing.expectEqual(
        Subsystem.component_object,
        subsystemFor("api-ms-win-core-winrt-l1-1-0.dll"),
    );
    // The generic core set falls through to kernel rather than to unknown.
    try std.testing.expectEqual(
        Subsystem.kernel,
        subsystemFor("api-ms-win-core-synch-l1-2-0.dll"),
    );
    try std.testing.expect(isWindowsSurface("ext-ms-win-ntuser-window-l1-1-0.dll"));
}

test "startup-critical subsystems are the ones a guest cannot reach its loop without" {
    try std.testing.expect(Subsystem.kernel.startupCritical());
    try std.testing.expect(Subsystem.c_runtime.startupCritical());
    try std.testing.expect(Subsystem.windowing.startupCritical());
    // A title with no registry still starts; it just cannot remember
    // anything. That is a correctness problem, not a bring-up blocker, and
    // the distinction is what makes a report's ordering useful.
    try std.testing.expect(!Subsystem.configuration_store.startupCritical());
    try std.testing.expect(!Subsystem.legacy_drawing.startupCritical());
    try std.testing.expect(!Subsystem.unrecognized.startupCritical());
}

test "every named library and API set has a label" {
    for (libraries) |entry| {
        try std.testing.expect(entry.subsystem.label().len != 0);
        // A stem carrying its own suffix would never match anything.
        try std.testing.expect(!std.mem.endsWith(u8, entry.stem, ".dll"));
    }
    for (api_sets) |entry| {
        try std.testing.expect(entry.subsystem.label().len != 0);
        try std.testing.expect(std.mem.endsWith(u8, entry.prefix, "-"));
    }
    try std.testing.expect(named_library_count > 40);
    try std.testing.expectEqual(api_sets.len, api_set_prefix_count);
}

test "DirectSound is refused on purpose, because WinMM is the modelled audio path" {
    try std.testing.expectEqual(ModuleAvailability.no_backend, moduleAvailability("DSOUND.DLL"));
    try std.testing.expectEqual(ModuleAvailability.no_backend, moduleAvailability("dsound"));
    try std.testing.expect(!moduleAvailability("DSOUND.DLL").isGap());
}

test "deliberate module refusals name the safe path left for the caller" {
    try std.testing.expectEqualStrings("vulkan-graphics-path", moduleFallback("D3D12.dll"));
    try std.testing.expectEqualStrings("vulkan-graphics-path", moduleFallback("dxgi"));
    try std.testing.expectEqualStrings("winmm-coreaudio-path", moduleFallback("DSOUND.DLL"));
    try std.testing.expectEqualStrings("no-capture-session", moduleFallback("renderdoc.dll"));
    try std.testing.expectEqualStrings("no-windows-usb-backend", moduleFallback("libusbK.dll"));
    try std.testing.expectEqualStrings("none-outside-modelled-surface", moduleFallback("XAudio2_8.dll"));
}
