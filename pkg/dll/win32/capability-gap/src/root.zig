//! What a DLL package would have to gain before Rosette could serve it.
//!
//! ## Why this exists
//!
//! Rosette's per-DLL packages record which names exist and what value a
//! refusal returns. Neither says what is *missing*. `dxgi.dll` reports one
//! degraded import and an HRESULT, and a reader wanting to know what standing
//! this library up would actually involve has nowhere to look but the source
//! of the dispatcher - where the answer is an absence, and absences are not
//! greppable.
//!
//! So each DLL that Rosette declines can carry an inventory of the conditions
//! it does not meet. Three fields per condition, because a gap that names only
//! what is missing is a wish list: the reader needs to know what stands in the
//! way and what the guest loses in the meantime, or they cannot tell an
//! afternoon's work from a subsystem nobody should start.
//!
//! ## What a condition is, and is not
//!
//! It is a statement about Rosette, checked by a person. Nothing here is
//! derived from a run, so a condition can be stale in a way a counter cannot -
//! which is why each one names its blocker concretely enough to re-check. An
//! empty inventory means "nobody has enumerated this", never "nothing is
//! missing", and the report has to say so in those words.

const std = @import("std");

pub const Condition = struct {
    /// What Rosette would have to be able to do. Phrased as a capability,
    /// not as a function to write: a name to implement is an implementation
    /// detail of the capability and often not the hard part.
    requirement: []const u8,
    /// What stands in the way today. The part that separates an afternoon
    /// from a subsystem.
    blocked_by: []const u8,
    /// What the guest does without it. A condition with no consequence is
    /// not worth meeting, and writing this field down is how that gets
    /// noticed.
    consequence: []const u8,
    /// Whether a title can reach a rendered frame without this. Nothing here
    /// changes what Rosette does; it decides the order a reader reads in.
    blocks_first_frame: bool = false,
};

/// One DLL's inventory.
pub const Inventory = struct {
    dll_name: []const u8,
    /// Empty means nobody has enumerated this library, which is a different
    /// statement from "this library needs nothing".
    conditions: []const Condition,
    /// One sentence on what the library is for, so a reader who has never
    /// met it can judge the conditions.
    summary: []const u8,

    pub fn isEnumerated(self: Inventory) bool {
        return self.conditions.len != 0;
    }

    pub fn blocksFirstFrame(self: Inventory) bool {
        for (self.conditions) |condition| {
            if (condition.blocks_first_frame) return true;
        }
        return false;
    }
};

/// The DXGI factory Xenia asks for on Windows.
///
/// Enumerated in full because it is the refusal the 2026-09-12 run put in
/// front of the reader, and "what would it take" is the question that follows
/// every refusal Rosette prints.
pub const dxgi = Inventory{
    .dll_name = "dxgi.dll",
    .summary = "Windows' display-adapter and swapchain interface. Xenia uses exactly one part of it: an IDXGIOutput to wait on for vertical blank, so its UI thread repaints at the monitor's rate instead of as fast as it can.",
    .conditions = &[_]Condition{
        .{
            .requirement = "A COM object model: a guest-visible vtable Rosette builds, whose slots are Rosette-owned addresses the interpreter recognises when the guest calls through them.",
            .blocked_by = "Rosette models imports as named entry points, not as objects. Every DXGI interface is reached by QueryInterface and vtable index, so serving CreateDXGIFactory1 means returning a pointer the guest will immediately call twenty methods on, none of which have names in any import table.",
            .consequence = "A factory pointer cannot be returned at all, so the refusal is the only honest answer available today.",
        },
        .{
            .requirement = "IDXGIFactory1::EnumAdapters and IDXGIAdapter::EnumOutputs, backed by the host's real displays.",
            .blocked_by = "The adapter and output list would have to come from CoreGraphics - CGGetActiveDisplayList and the display mode APIs - and be kept in the shape DXGI_OUTPUT_DESC declares, including a monitor handle Rosette does not otherwise mint.",
            .consequence = "Xenia's Presenter finds no output for its window's monitor and leaves dxgi_ui_tick_output_ null.",
        },
        .{
            .requirement = "IDXGIOutput::WaitForVBlank, blocking until the display the window is on retraces.",
            .blocked_by = "The macOS equivalent is a CVDisplayLink or a CADisplayLink callback, which is a push from the window server rather than a blocking call. Rosette would have to own the link and park the calling guest thread on it, which is a cooperative-scheduler question and not a graphics one.",
            .consequence = "Presenter::AreDXGIUITicksWaitable stays false, WaitForUITickFromUIThread returns immediately, and Xenia's UI repaints are unpaced rather than blocked. This is the only observed effect today.",
        },
        .{
            .requirement = "IDXGIFactory1::IsCurrent, so Xenia can notice a monitor being connected and rebuild the factory.",
            .blocked_by = "Needs a display-reconfiguration callback (CGDisplayRegisterReconfigurationCallback) feeding a flag the factory object reads.",
            .consequence = "A display hot-plug would not be noticed. Unobservable while the factory itself does not exist.",
        },
    },
};

/// Direct3D 12, which Rosette refuses as a whole module.
pub const d3d12 = Inventory{
    .dll_name = "D3D12.dll",
    .summary = "Direct3D 12. Xenia probes for it to decide whether its D3D12 backend is available, and takes the Vulkan backend when it is not.",
    .conditions = &[_]Condition{
        .{
            .requirement = "Nothing. The refusal is the correct answer and implementing this would be wrong.",
            .blocked_by = "There is no D3D12 on macOS, and Xenia's own probe exists precisely so it can choose another backend. Serving it would take the title away from the Vulkan path Rosette does bridge.",
            .consequence = "Xenia selects its Vulkan backend, which is the path Rosette supports.",
        },
    },
};

/// The WinUSB user-mode USB surface.
pub const winusb = Inventory{
    .dll_name = "WINUSB.dll",
    .summary = "User-mode USB device access. libusb resolves it as a whole list to talk to controllers directly.",
    .conditions = &[_]Condition{
        .{
            .requirement = "A USB transport: device enumeration, pipe policy, and synchronous control and bulk transfers against real hardware.",
            .blocked_by = "Would go through IOKit's IOUSBHost family, and every handle libusb holds would have to be a Rosette-owned object with a lifetime. The twelve required names are served as refusals today, which keeps libusb's backend loadable without promising a transport.",
            .consequence = "No direct USB device access. Controllers reach the guest through XInput instead, which Rosette does serve.",
        },
        .{
            .requirement = "Isochronous pipes, if WinUsb_ReadIsochPipeAsap is ever to be served.",
            .blocked_by = "Deliberately not done: answering that optional probe with NULL is what keeps libusb from requiring four more isochronous entry points Rosette cannot honour.",
            .consequence = "None. This is a decision, not a gap.",
        },
    },
};

/// The registry, service-control, and security surface. The current Xenia
/// image only probes the registry for optional profile values; a missing key
/// is deliberately reported as data rather than converted into a fabricated
/// default handle.
pub const advapi32 = Inventory{
    .dll_name = "ADVAPI32.dll",
    .summary = "Windows registry, service-control, security-token, and event-log APIs used by optional process setup and diagnostics.",
    .conditions = &[_]Condition{
        .{
            .requirement = "A confined guest registry with key, value, type, and last-error state, rooted in the PE profile rather than the host registry.",
            .blocked_by = "Rosette serves a confined guest registry for the run: keys and values the guest creates are visible to its later calls, a key it never created reads ERROR_FILE_NOT_FOUND, and no host registry key is exposed. Persistence across runs, security descriptors, enumeration and change notification are not modelled.",
            .consequence = "Optional profile and graphics-driver settings are absent, so the title follows its built-in defaults.",
        },
        .{
            .requirement = "Guest-owned security tokens, service handles, and event-log records with Windows access-mask semantics.",
            .blocked_by = "The host has no safe one-to-one object for a Windows token or service-manager handle, and no title-owned service contract has been observed.",
            .consequence = "Service discovery and privileged diagnostics cannot create or query those Windows objects; the audited title does not use them for its first frame.",
        },
    },
};

/// The classic COM activation and marshaling surface. Xenia's SDL input
/// probe may ask for this library even when it later selects XInput.
pub const ole32 = Inventory{
    .dll_name = "ole32.dll",
    .summary = "Classic COM apartment, activation, storage, and marshaling services used by optional Windows input and shell integrations.",
    .conditions = &[_]Condition{
        .{
            .requirement = "A guest-visible COM apartment and lifetime model, including IUnknown identity, QueryInterface, AddRef/Release, activation, and marshaling boundaries.",
            .blocked_by = "Rosette's guest-only DXGI model is local to the graphics contract; a general COM object graph and class registry are not yet a shared runtime service.",
            .consequence = "SDL's optional DirectInput/COM probe receives E_NOINTERFACE and falls back; no Xenia video or Vulkan boundary is blocked.",
        },
    },
};

/// The newer Windows Runtime-flavoured COM surface. It is kept separate from
/// ole32 because HSTRING and activation-factory ownership have different
/// guest state and error contracts.
pub const combase = Inventory{
    .dll_name = "combase.dll",
    .summary = "Windows Runtime string, activation-factory, and apartment services used by optional input-device discovery.",
    .conditions = &[_]Condition{
        .{
            .requirement = "Guest-owned HSTRING buffers, Windows Runtime activation factories, and apartment/error-state semantics.",
            .blocked_by = "No general WinRT class registry or HSTRING lifetime table is shared by the PE runtime; host Foundation objects cannot be placed in guest memory.",
            .consequence = "The WGI probe receives E_NOTIMPL/E_NOINTERFACE and contributes no controller devices; the audited title continues through its neutral input path.",
        },
    },
};

/// Kernel32 is already broadly modelled. This inventory covers the remaining
/// optional names that are intentionally not success-valued stubs: volume and
/// console queries, process/thread control, named-pipe/APC operations, and
/// unwind metadata that has no guest-owned Windows kernel behind it.
pub const kernel32 = Inventory{
    .dll_name = "KERNEL32.dll",
    .summary = "The primary Windows process, file, memory, synchronization, console, and loader API surface; only the audited optional names remain declined.",
    .conditions = &[_]Condition{
        .{
            .requirement = "Guest-stateful volume, console, power, locale, and file-information objects with exact Windows structure layouts and last-error behavior.",
            .blocked_by = "The current PE bridge models the confined filesystem and core process services, but it has no guest volume/console device layer and does not turn host-only metadata into Windows objects.",
            .consequence = "Optional diagnostics and environment probes receive their documented unavailable/empty result; Xenia's graphics initialization does not depend on them.",
        },
        .{
            .requirement = "Safe guest thread/APC/process suspension and dynamic unwind-table services.",
            .blocked_by = "Suspending or terminating a host thread would violate Rosette's cooperative executor, while Windows unwind callbacks require a guest module registration table not present in the audited image.",
            .consequence = "Those optional control and crash-reporting paths remain unavailable instead of corrupting the scheduler; the title's live worker set and waits use Rosette-owned services.",
        },
    },
};

/// SetupAPI and Configuration Manager enumerate physical Windows devices.
/// The Xenia path uses a neutral input fallback when those probes are absent.
pub const setupapi = Inventory{
    .dll_name = "SetupAPI.dll",
    .summary = "Windows device-installation and device-interface enumeration used by optional HID/controller discovery.",
    .conditions = &[_]Condition{
        .{
            .requirement = "A guest-owned device-information set with interface detail, property, parent, and stable device-ID records.",
            .blocked_by = "Rosette has no Windows device-installation database; forwarding IOKit objects would expose host pointers and host lifetime rules to the PE guest.",
            .consequence = "The optional HID enumeration returns an empty/unavailable set and Xenia uses its neutral input path; no first-frame graphics boundary is blocked.",
        },
    },
};

/// USER32's remaining names are optional message, input, clipboard, timer,
/// monitor, and icon helpers. The core hidden-window/message bridge used by
/// the audited Xenia run is modelled separately in the Windows runtime.
pub const user32 = Inventory{
    .dll_name = "USER32.dll",
    .summary = "Windows window-manager, message, monitor, raw-input, clipboard, timer, and resource helpers.",
    .conditions = &[_]Condition{
        .{
            .requirement = "Guest-owned window/message/input/resource state for the remaining dialog, monitor, clipboard, timer, and raw-input entry points.",
            .blocked_by = "The PE bridge currently provides the Xenia message-window and graphics geometry subset, but does not emulate every desktop resource and input-device object.",
            .consequence = "Optional dialogs, clipboard operations, raw-input details, and display enumeration return neutral or unavailable results; Xenia's guest-only DXGI output remains sufficient for the audited first-frame transport.",
        },
    },
};

/// API-set runtime names are aliases exposed by the Universal CRT. The
/// audited image's fixed-width refusal ledger truncates the final `l` of this
/// DLL name in one record, so inventoryFor accepts that evidence spelling too.
pub const api_ms_win_crt_runtime = Inventory{
    .dll_name = "api-ms-win-crt-runtime-l1-1-0.dll",
    .summary = "Universal CRT process-runtime helpers, including guest-owned executable-path, errno, callback, and termination state.",
    .conditions = &[_]Condition{
        .{
            .requirement = "No additional capability for the audited CRT exports: Rosetta must own the path globals, thread-local errno pointers, bounded normal/quick-exit tables, TLS-exit callback, and return/termination sequencing.",
            .blocked_by = "None for the audited path. The state and callback protocol are implemented in the PE executor; any future export without a package row is a new capability gap and must fail closed.",
            .consequence = "None for the audited path. Process-path probes write guest-owned storage, errno is thread-local, and exit callbacks cannot be silently skipped or replaced with a host pointer.",
        },
    },
};

/// API-set stdio names are kept separate from the runtime package because
/// FILE*/descriptor ownership and read/write modes are stateful.
pub const api_ms_win_crt_stdio = Inventory{
    .dll_name = "api-ms-win-crt-stdio-l1-1-0.dll",
    .summary = "Universal CRT stdio and descriptor helpers used by optional text/file streams.",
    .conditions = &[_]Condition{
        .{
            .requirement = "A complete guest FILE and descriptor table with mode, position, buffering, EOF/error flags, errno, and wide-character conversion state.",
            .blocked_by = "Rosette models the confined file operations reached by Xenia, but the remaining stdio names include stream modes and descriptor adoption that cannot be represented by a bare host FILE pointer.",
            .consequence = "Optional stdio calls fail with their typed CRT result rather than fabricating a stream; the audited title's graphics path does not require them.",
        },
    },
};

pub const inventories = [_]Inventory{
    dxgi,
    d3d12,
    winusb,
    advapi32,
    ole32,
    combase,
    kernel32,
    setupapi,
    user32,
    api_ms_win_crt_runtime,
    api_ms_win_crt_stdio,
};

/// The inventory for a DLL, if one has been written.
pub fn inventoryFor(dll_name: []const u8) ?Inventory {
    for (inventories) |inventory| {
        if (std.ascii.eqlIgnoreCase(inventory.dll_name, dll_name)) return inventory;
        // Callers see both `dxgi` and `dxgi.dll` depending on how the guest
        // asked, so match the stem too.
        const stem_length = std.mem.lastIndexOfScalar(u8, inventory.dll_name, '.') orelse continue;
        if (std.ascii.eqlIgnoreCase(inventory.dll_name[0..stem_length], dll_name)) return inventory;
    }
    // The bounded refusal ledger has one historical fixed-width spelling for
    // the runtime API-set DLL. Preserve that evidence without weakening the
    // exact inventory names used by the package catalogue.
    if (std.ascii.eqlIgnoreCase(dll_name, "api-ms-win-crt-runtime-l1-1-0.dl")) {
        return api_ms_win_crt_runtime;
    }
    return null;
}

pub fn count() usize {
    return inventories.len;
}

test "every condition says what is missing, what blocks it, and what it costs" {
    for (inventories) |inventory| {
        try std.testing.expect(inventory.dll_name.len != 0);
        try std.testing.expect(inventory.summary.len != 0);
        try std.testing.expect(inventory.isEnumerated());
        for (inventory.conditions) |condition| {
            // A requirement with no blocker is a wish, and a blocker with no
            // consequence is a gap nobody needs closed. Both fields exist so
            // the reader can rank the work, and an empty one makes the row
            // unrankable.
            try std.testing.expect(condition.requirement.len != 0);
            try std.testing.expect(condition.blocked_by.len != 0);
            try std.testing.expect(condition.consequence.len != 0);
        }
    }
}

test "the DXGI inventory names the object model, not just the entry point" {
    // The refusal a reader sees is `CreateDXGIFactory1`, which reads like one
    // function to write. It is not: the function returns a COM object, and
    // the work is the object model behind it. An inventory that listed the
    // entry point would understate this by an order of magnitude.
    const inventory = inventoryFor("dxgi.dll").?;
    try std.testing.expect(std.mem.indexOf(u8, inventory.conditions[0].requirement, "vtable") != null);
    try std.testing.expect(std.mem.indexOf(u8, inventory.conditions[0].blocked_by, "QueryInterface") != null);

    // And none of it blocks a first frame, which is the fact that decides
    // whether to start.
    try std.testing.expect(!inventory.blocksFirstFrame());
    try std.testing.expectEqual(inventory.dll_name, inventoryFor("dxgi").?.dll_name);
}

test "a refusal that is the right answer says so instead of listing work" {
    // D3D12 is refused on purpose: Xenia's probe exists so it can pick
    // another backend, and serving it would move the title off the path
    // Rosette bridges. An inventory that treated every refusal as debt would
    // put this on a to-do list.
    const inventory = inventoryFor("D3D12.dll").?;
    try std.testing.expectEqual(@as(usize, 1), inventory.conditions.len);
    try std.testing.expect(std.mem.indexOf(u8, inventory.conditions[0].requirement, "Nothing") != null);
}

test "a library nobody has enumerated is not a library that needs nothing" {
    try std.testing.expect(inventoryFor("kernel32.dll") != null);
    try std.testing.expectEqualStrings("api-ms-win-crt-runtime-l1-1-0.dll", inventoryFor("api-ms-win-crt-runtime-l1-1-0.dl").?.dll_name);
    try std.testing.expectEqual(@as(?Inventory, null), inventoryFor("unwritten.dll"));
    try std.testing.expectEqual(@as(?Inventory, null), inventoryFor(""));
    // The distinction matters enough to be a method rather than a comment.
    const empty = Inventory{ .dll_name = "x.dll", .summary = "s", .conditions = &[_]Condition{} };
    try std.testing.expect(!empty.isEnumerated());
    try std.testing.expect(!empty.blocksFirstFrame());
}
