//! What a deterministic Windows import fallback is allowed to return.
//!
//! Rosetta models a bounded Win32/UCRT surface.  Names it recognizes but has
//! not given stateful behaviour to still have to complete their call
//! boundary, and for a long time every one of them completed it by putting
//! zero in `rax`.  That is only safe for the part of the Win32 ABI where zero
//! spells failure.  It is actively wrong for the rest: zero is `ERROR_SUCCESS`
//! for an `LSTATUS`, `S_OK` for an `HRESULT`, and `STATUS_SUCCESS` for an
//! `NTSTATUS`.  A guest that asks whether a registry key opened, whether a COM
//! object was created, or whether a WinRT factory was returned is told "yes",
//! reads the output parameter Rosetta never wrote, and carries the garbage
//! forward -- the failure then surfaces far away from the import that caused
//! it.
//!
//! So the fallback is a contract rather than a constant.  Each name is mapped
//! to the return convention its ABI actually uses, and the fallback emits the
//! value that convention defines for "this did not happen".  Where a call has
//! nothing to produce -- teardown, an initializer with no output -- reporting
//! success is the honest answer and is spelled that way explicitly.
//!
//! ## What this package proves, and what it does not
//!
//! Everything here is a pure function of a DLL name and a function name.  It
//! is derived from the shape of the name, never from one title's import
//! table, so a PE Rosetta has never seen gets the same treatment.
//!
//! It says what a guest *would* be told if a name fell through to the
//! fallback.  It cannot say whether a name did fall through: that is measured
//! at runtime by the ledger in `src/x64-ASM/windows_import_contract.zig` and
//! reported in the run log's `DEGRADED IMPORTS` block.  A classification here
//! is never evidence that an import is broken.

const std = @import("std");

/// How an import spells its return value.  Only the conventions whose failure
/// value differs from zero change what the fallback returns; the rest keep
/// the historical zero, which is already the correct refusal for them.
pub const ReturnConvention = enum {
    /// No return value the caller can read.
    void_call,
    /// Win32 `BOOL`: zero is FALSE, which is the refusal.
    bool32,
    /// A handle or pointer: zero is NULL, which is the refusal.
    handle,
    /// A handle-returning API whose documented failure value is
    /// `INVALID_HANDLE_VALUE`, not NULL.  Zero would look like a usable
    /// handle to a guest that compares against `INVALID_HANDLE_VALUE`.
    invalid_handle,
    /// A count, index, or length where zero means "none".
    zero_count,
    /// `LSTATUS`/`LONG` Win32 error code: **zero is ERROR_SUCCESS**.
    lstatus,
    /// `HRESULT`: **zero is S_OK**.
    hresult,
    /// `NTSTATUS`: **zero is STATUS_SUCCESS**.
    ntstatus,
    /// A Winsock `WSA*` routine returning a `WSA` error code where **zero is
    /// success**.
    winsock_status,

    /// Whether zero would be read by the caller as success.  These are the
    /// conventions where the historical zero-return was a false claim.
    pub fn zeroMeansSuccess(self: ReturnConvention) bool {
        return switch (self) {
            .lstatus, .hresult, .ntstatus, .winsock_status => true,
            .void_call, .bool32, .handle, .invalid_handle, .zero_count => false,
        };
    }
};

/// What the fallback claimed.  A refusal is the normal case; a success is
/// reserved for calls with no output parameter and no state to produce, where
/// claiming failure would be the dishonest answer instead.
pub const Outcome = enum {
    /// The ABI's "this did not happen" value was returned.
    refused,
    /// There was nothing to produce, so success is accurate.
    succeeded,
};

pub const Fallback = struct {
    convention: ReturnConvention,
    outcome: Outcome,
    /// The value placed in `rax`.
    value: u64,
    /// The value `GetLastError` should report, or null to leave the guest's
    /// last-error word untouched.
    last_error: ?u32,
    /// True when zero is a *meaningful* answer for this call rather than the
    /// absence of one: a comparison that reads as "equal", a search that
    /// reads as "not found", a pointer accessor that hands back a NULL the
    /// caller will dereference.  A stub like this is not inert -- it is a
    /// wrong answer the guest cannot tell from a right one, so it has to be
    /// reported even though the convention itself looks harmless.
    hazard: bool = false,

    /// Whether this fallback changed the guest-visible answer relative to a
    /// bare zero return.  Used by the ledger to separate "a stub that is
    /// indistinguishable from before" from "a stub whose whole point is that
    /// zero was a lie".
    pub fn differsFromZeroReturn(self: Fallback) bool {
        return self.value != 0;
    }
};

// Win32 error codes used by the refusals.
const error_success: u32 = 0;
const error_file_not_found: u32 = 2;
const error_access_denied: u32 = 5;
const error_call_not_implemented: u32 = 120;
// HRESULT E_NOTIMPL.
const e_notimpl: u64 = 0x8000_4001;
// HRESULT S_OK.
const s_ok: u64 = 0;
// NTSTATUS STATUS_NOT_IMPLEMENTED.
const status_not_implemented: u64 = 0xC000_0002;
// WSANOTINITIALISED: the honest state of a Winsock stack Rosetta never
// started.
const wsanotinitialised: u64 = 10093;
const invalid_handle_value: u64 = std.math.maxInt(u64);

/// Names whose spelling does not match the convention their family implies.
/// Kept deliberately short: every entry here is a case where the generic
/// rules below would produce a wrong answer, not a case that merely has not
/// been generalized yet.
const ConventionOverride = struct { name: []const u8, convention: ReturnConvention };

const convention_overrides = [_]ConventionOverride{
    // COM allocation and teardown do not return HRESULT despite the prefix.
    .{ .name = "CoTaskMemAlloc", .convention = .handle },
    .{ .name = "CoTaskMemRealloc", .convention = .handle },
    .{ .name = "CoTaskMemFree", .convention = .void_call },
    .{ .name = "CoUninitialize", .convention = .void_call },
    .{ .name = "CoFreeUnusedLibraries", .convention = .void_call },
    .{ .name = "OleUninitialize", .convention = .void_call },
    .{ .name = "CoDecrementMTAUsage", .convention = .hresult },
    // WinRT string readers hand back a raw pointer/length, not a status.
    .{ .name = "WindowsGetStringRawBuffer", .convention = .handle },
    .{ .name = "WindowsGetStringLen", .convention = .zero_count },
    .{ .name = "WindowsIsStringEmpty", .convention = .bool32 },
    // These open kernel objects and report failure with
    // INVALID_HANDLE_VALUE rather than NULL.
    .{ .name = "CreateFileA", .convention = .invalid_handle },
    .{ .name = "CreateFileW", .convention = .invalid_handle },
    .{ .name = "CreateFile2", .convention = .invalid_handle },
    .{ .name = "FindFirstFileA", .convention = .invalid_handle },
    .{ .name = "FindFirstFileW", .convention = .invalid_handle },
    .{ .name = "FindFirstFileExA", .convention = .invalid_handle },
    .{ .name = "FindFirstFileExW", .convention = .invalid_handle },
    .{ .name = "FindFirstVolumeW", .convention = .invalid_handle },
    .{ .name = "FindFirstChangeNotificationW", .convention = .invalid_handle },
    // ...while the mapping and device families use NULL.
    .{ .name = "CreateFileMappingA", .convention = .handle },
    .{ .name = "CreateFileMappingW", .convention = .handle },
    // Winsock's own initializer is a status word, not a BOOL.
    .{ .name = "WSAStartup", .convention = .winsock_status },
    .{ .name = "WSACleanup", .convention = .winsock_status },
    // `RegisterClass*` and friends only look like registry calls.
    .{ .name = "RegisterClassA", .convention = .zero_count },
    .{ .name = "RegisterClassW", .convention = .zero_count },
    .{ .name = "RegisterClassExA", .convention = .zero_count },
    .{ .name = "RegisterClassExW", .convention = .zero_count },
};

/// Initializers with no output parameter, where a guest expects to be able to
/// proceed and Rosetta has nothing it failed to produce.  Reporting failure
/// here would abort a bootstrap over a call that asked for nothing.
const honest_success_names = [_][]const u8{
    "CoInitialize",
    "CoInitializeEx",
    "OleInitialize",
    "SetThreadDescription",
    "SetThreadpoolTimer",
};

/// Teardown verbs.  A resource Rosetta never handed out cannot fail to be
/// released, so a zero-is-success convention reports success for these.
const teardown_suffixes = [_][]const u8{
    "Clear",
    "Close",
    "Destroy",
    "Release",
    "Reset",
    "Uninit",
};

const teardown_prefixes = [_][]const u8{
    "Close",
    "Delete",
    "Destroy",
    "Discard",
    "Flush",
    "Free",
    "Release",
    "Uninitialize",
    "Unload",
    "Unregister",
};

fn isKnownDll(dll_name: []const u8, comptime stem: []const u8) bool {
    return std.ascii.eqlIgnoreCase(dll_name, stem ++ ".dll") or std.ascii.eqlIgnoreCase(dll_name, stem);
}

/// A registry entry point: `Reg` followed by another capital.  This is what
/// separates `RegOpenKeyExW` from `RegisterClassExW` without listing either.
fn isRegistryName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "Reg")) return false;
    if (name.len < 4) return false;
    return std.ascii.isUpper(name[3]);
}

/// Whether a name belongs to the COM/OLE/WinRT activation surface by its own
/// spelling.
///
/// This is deliberately narrower than "returns an HRESULT": every COM name
/// does, but so do `SHGetKnownFolderPath` and the compositor's, and those
/// belong to their own subsystems. Conflating the two sends a reader
/// investigating a shell path failure into COM.
pub fn isComponentObjectName(name: []const u8) bool {
    // `Co` followed by another capital: CoCreateInstance, CoInitializeEx.
    if (std.mem.startsWith(u8, name, "Co") and name.len > 2 and std.ascii.isUpper(name[2])) return true;
    if (std.mem.startsWith(u8, name, "Ole") and name.len > 3 and std.ascii.isUpper(name[3])) return true;
    // `Ro` is the WinRT runtime prefix (RoInitialize, RoGetActivationFactory).
    if (std.mem.startsWith(u8, name, "Ro") and name.len > 2 and std.ascii.isUpper(name[2])) return true;
    if (std.mem.startsWith(u8, name, "Windows") and name.len > 7 and std.ascii.isUpper(name[7])) return true;
    if (std.mem.startsWith(u8, name, "CLSIDFrom")) return true;
    if (std.mem.startsWith(u8, name, "IIDFrom")) return true;
    if (std.mem.startsWith(u8, name, "ProgIDFrom")) return true;
    return false;
}

/// Every name whose return value is an `HRESULT`, which is the COM surface
/// plus the graphics, shell and thread-description routines that adopted the
/// same convention.
fn isHresultName(name: []const u8) bool {
    if (isComponentObjectName(name)) return true;
    if (std.mem.startsWith(u8, name, "Dwm")) return true;
    if (std.mem.startsWith(u8, name, "CreateDXGIFactory")) return true;
    if (std.mem.startsWith(u8, name, "D3D")) return true;
    if (std.mem.eql(u8, name, "GetThreadDescription")) return true;
    if (std.mem.eql(u8, name, "SetThreadDescription")) return true;
    if (std.mem.startsWith(u8, name, "SHGetKnownFolderPath")) return true;
    if (std.mem.startsWith(u8, name, "SHCreateItem")) return true;
    return false;
}

fn isNtStatusName(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "Nt") and name.len > 2 and std.ascii.isUpper(name[2])) return true;
    if (std.mem.startsWith(u8, name, "Zw") and name.len > 2 and std.ascii.isUpper(name[2])) return true;
    if (std.mem.startsWith(u8, name, "BCrypt")) return true;
    if (std.mem.startsWith(u8, name, "NCrypt")) return true;
    return false;
}

/// Family prefixes whose verb starts after the prefix, so `RegCloseKey` and
/// `CoFreeUnusedLibraries` are recognized as teardown without matching the
/// verb in the middle of an unrelated name such as `GetFreeSpace`.
const family_prefixes = [_][]const u8{ "Reg", "Ole", "Co", "Ro", "Nt", "Zw" };

fn hasTeardownShape(name: []const u8) bool {
    for (teardown_prefixes) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }
    for (family_prefixes) |family| {
        if (!std.mem.startsWith(u8, name, family)) continue;
        const verb = name[family.len..];
        for (teardown_prefixes) |prefix| {
            if (std.mem.startsWith(u8, verb, prefix)) return true;
        }
    }
    // Some families put the verb last: PropVariantClear, VariantClear,
    // SysFreeString, IStream_Release.  A trailing verb is only a teardown
    // when it ends the name, so `CoCreateFreeThreadedMarshaler` is not one.
    for (teardown_suffixes) |suffix| {
        if (name.len > suffix.len and std.mem.endsWith(u8, name, suffix)) return true;
    }
    return false;
}

fn hasMutatingShape(name: []const u8) bool {
    const verbs = [_][]const u8{ "Set", "Create", "Save", "Restore", "Write", "Replace", "Rename" };
    for (family_prefixes) |family| {
        if (!std.mem.startsWith(u8, name, family)) continue;
        const tail = name[family.len..];
        for (verbs) |verb| {
            if (std.mem.startsWith(u8, tail, verb)) return true;
        }
    }
    return false;
}

/// The return convention an import uses, derived from its DLL and the shape
/// of its name.
pub fn returnConvention(dll_name: []const u8, name: []const u8) ReturnConvention {
    if (name.len == 0) return .zero_count;
    for (convention_overrides) |override| {
        if (std.mem.eql(u8, name, override.name)) return override.convention;
    }
    if (isRegistryName(name)) return .lstatus;
    if (isNtStatusName(name)) return .ntstatus;
    if (isHresultName(name)) return .hresult;
    if (std.mem.startsWith(u8, name, "WSA")) return .winsock_status;
    // A library-wide HRESULT rule is only safe where the library really is
    // HRESULT-dominated.  `ole32` and `oleaut32` are not: `SysAllocString`
    // returns a BSTR, `SysStringLen` a length, `StringFromGUID2` a character
    // count.  Handing any of those an E_NOTIMPL would be a pointer the guest
    // dereferences -- the exact failure mode this contract exists to remove.
    // The Co/Ole/Ro/CLSIDFrom name shapes above already cover the HRESULT
    // half of those libraries.
    if (isKnownDll(dll_name, "combase") or isKnownDll(dll_name, "dxgi") or
        isKnownDll(dll_name, "dwmapi") or isKnownDll(dll_name, "shcore") or
        isKnownDll(dll_name, "propsys")) return .hresult;
    if (std.mem.startsWith(u8, name, "SysAlloc") or std.mem.startsWith(u8, name, "SafeArrayCreate")) return .handle;

    // Everything below keeps the historical zero return; the convention is
    // recorded so a report can say what the guest actually saw.
    if (std.mem.startsWith(u8, name, "Create") or std.mem.startsWith(u8, name, "Open") or
        std.mem.startsWith(u8, name, "Load") or std.mem.endsWith(u8, name, "Alloc")) return .handle;
    // The classic Win32 DLLs are overwhelmingly BOOL-returning; the CRT and
    // anything Rosetta cannot place keep the neutral count.  Both spell
    // failure with zero, so this only decides how a report describes the
    // call, never what the guest receives.
    if (isKnownDll(dll_name, "user32") or isKnownDll(dll_name, "gdi32") or
        isKnownDll(dll_name, "kernel32") or isKnownDll(dll_name, "advapi32") or
        isKnownDll(dll_name, "shell32") or isKnownDll(dll_name, "shlwapi") or
        isKnownDll(dll_name, "comdlg32") or isKnownDll(dll_name, "imm32") or
        isKnownDll(dll_name, "setupapi") or isKnownDll(dll_name, "version") or
        isKnownDll(dll_name, "winmm")) return .bool32;
    if (std.mem.startsWith(u8, name, "Is") or std.mem.startsWith(u8, name, "Adjust") or
        std.mem.startsWith(u8, name, "Set") or std.mem.startsWith(u8, name, "Enable") or
        std.mem.startsWith(u8, name, "Show") or std.mem.startsWith(u8, name, "Update") or
        std.mem.startsWith(u8, name, "Query") or std.mem.startsWith(u8, name, "Lookup")) return .bool32;
    return .zero_count;
}

/// Names where returning zero states something the call has not earned the
/// right to state.  Derived from the shape of the name so it covers a CRT
/// Rosetta has not inventoried yet, not just the ones seen so far.
fn zeroIsAMeaningfulAnswer(name: []const u8) bool {
    // Comparisons: zero is "equal".
    if (std.mem.indexOf(u8, name, "cmp") != null) return true;
    if (std.mem.indexOf(u8, name, "coll") != null) return true;
    // Searches: zero is "not present".
    const search_families = [_][]const u8{ "mem", "str", "wcs", "_mbs" };
    const search_verbs = [_][]const u8{ "chr", "str", "spn", "brk", "tok", "find" };
    for (search_families) |family| {
        const offset = if (std.mem.startsWith(u8, name, "_")) @as(usize, 1) else 0;
        if (name.len <= offset or !std.mem.startsWith(u8, name[offset..], family)) continue;
        for (search_verbs) |verb| {
            if (std.mem.indexOf(u8, name[offset..], verb) != null) return true;
        }
    }
    // CRT state accessors hand back a pointer the caller writes through.
    if (std.mem.startsWith(u8, name, "__p_")) return true;
    if (std.mem.startsWith(u8, name, "__acrt_")) return true;
    return false;
}

fn isHonestSuccess(name: []const u8) bool {
    for (honest_success_names) |known| {
        if (std.mem.eql(u8, name, known)) return true;
    }
    return hasTeardownShape(name);
}

/// The complete deterministic answer for an import Rosetta recognizes but has
/// not implemented.
pub fn fallbackFor(dll_name: []const u8, name: []const u8) Fallback {
    var result = fallbackShape(dll_name, name);
    // A refusal already tells the guest the call did not happen, so only an
    // apparent success can be silently wrong.
    result.hazard = result.outcome == .succeeded and zeroIsAMeaningfulAnswer(name);
    return result;
}

fn fallbackShape(dll_name: []const u8, name: []const u8) Fallback {
    const convention = returnConvention(dll_name, name);
    if (convention.zeroMeansSuccess() and isHonestSuccess(name)) {
        return .{
            .convention = convention,
            .outcome = .succeeded,
            .value = 0,
            .last_error = if (convention == .lstatus) error_success else null,
        };
    }
    return switch (convention) {
        .void_call, .zero_count => .{
            .convention = convention,
            .outcome = .succeeded,
            .value = 0,
            .last_error = null,
        },
        .bool32, .handle => .{
            .convention = convention,
            .outcome = .refused,
            .value = 0,
            .last_error = error_call_not_implemented,
        },
        .invalid_handle => .{
            .convention = convention,
            .outcome = .refused,
            .value = invalid_handle_value,
            .last_error = error_file_not_found,
        },
        .lstatus => .{
            .convention = convention,
            .outcome = .refused,
            .value = if (hasMutatingShape(name)) error_access_denied else error_file_not_found,
            .last_error = null,
        },
        .hresult => .{
            .convention = convention,
            .outcome = .refused,
            .value = e_notimpl,
            .last_error = null,
        },
        .ntstatus => .{
            .convention = convention,
            .outcome = .refused,
            .value = status_not_implemented,
            .last_error = null,
        },
        .winsock_status => .{
            .convention = convention,
            .outcome = .refused,
            .value = wsanotinitialised,
            .last_error = null,
        },
    };
}

/// A one-line description of what a guest should do about this fallback.
/// This is what makes a degraded-import report actionable rather than a list
/// of names: it says which ones can be left alone and which ones need a real
/// implementation before the guest can get further.
pub fn advice(fallback: Fallback) []const u8 {
    if (fallback.hazard) {
        return "zero is a real answer here (equal / not found / a NULL the caller writes through), not an absence of one -- implement it, a stub cannot be distinguished from a correct result";
    }
    switch (fallback.convention) {
        .void_call, .zero_count => return "no observable result; safe to leave unimplemented",
        else => {},
    }
    if (fallback.outcome == .succeeded) {
        return "nothing to produce; success is accurate and needs no implementation";
    }
    return switch (fallback.convention) {
        .lstatus => "guest sees the registry key/value as absent; implement if a setting must persist",
        .hresult => "guest sees the COM/WinRT/DXGI object as unavailable and should take its fallback path",
        .ntstatus => "guest sees the native call as not implemented; implement if the object is load-bearing",
        .winsock_status => "guest sees the socket stack as uninitialized; implement if networking is required",
        .invalid_handle => "guest sees the open as failed; implement if the file or find handle is load-bearing",
        .handle => "returns 0 -- NULL for a handle or pointer, FALSE for a BOOL; implement before the guest uses the result",
        .bool32 => "returns FALSE with ERROR_CALL_NOT_IMPLEMENTED; implement if the guest depends on the effect",
        .void_call, .zero_count => "no observable result; safe to leave unimplemented",
    };
}

test "zero is only a refusal for the conventions that spell failure with it" {
    try std.testing.expect(ReturnConvention.lstatus.zeroMeansSuccess());
    try std.testing.expect(ReturnConvention.hresult.zeroMeansSuccess());
    try std.testing.expect(ReturnConvention.ntstatus.zeroMeansSuccess());
    try std.testing.expect(!ReturnConvention.bool32.zeroMeansSuccess());
    try std.testing.expect(!ReturnConvention.handle.zeroMeansSuccess());
}

test "registry names are separated from the Register family by shape alone" {
    try std.testing.expect(isRegistryName("RegOpenKeyExW"));
    try std.testing.expect(isRegistryName("RegQueryValueExA"));
    try std.testing.expect(isRegistryName("RegCloseKey"));
    try std.testing.expect(!isRegistryName("RegisterClassExW"));
    try std.testing.expect(!isRegistryName("RegisterRawInputDevices"));
    try std.testing.expect(!isRegistryName("Reg"));
}

test "a registry lookup fallback reports absence instead of ERROR_SUCCESS" {
    const open = fallbackFor("ADVAPI32.dll", "RegOpenKeyExW");
    try std.testing.expectEqual(ReturnConvention.lstatus, open.convention);
    try std.testing.expectEqual(Outcome.refused, open.outcome);
    try std.testing.expectEqual(@as(u64, 2), open.value); // ERROR_FILE_NOT_FOUND

    // A write is refused with ERROR_ACCESS_DENIED so a guest can tell "no
    // such setting" from "the setting could not be stored".
    const set = fallbackFor("ADVAPI32.dll", "RegSetValueExW");
    try std.testing.expectEqual(@as(u64, 5), set.value);

    // Releasing a key Rosetta never handed out cannot fail.
    const close = fallbackFor("ADVAPI32.dll", "RegCloseKey");
    try std.testing.expectEqual(Outcome.succeeded, close.outcome);
    try std.testing.expectEqual(@as(u64, 0), close.value);
}

test "COM, WinRT and DXGI fallbacks are refusals rather than S_OK" {
    for ([_][]const u8{
        "CoCreateInstance",
        "CoIncrementMTAUsage",
        "RoGetActivationFactory",
        "CreateDXGIFactory1",
        "CLSIDFromString",
        "WindowsCreateStringReference",
    }) |name| {
        const fallback = fallbackFor("ole32.dll", name);
        try std.testing.expectEqual(ReturnConvention.hresult, fallback.convention);
        try std.testing.expectEqual(@as(u64, 0x8000_4001), fallback.value);
    }

    // Apartment initialization asks for nothing, so refusing it would abort a
    // bootstrap over a call that produced no state.
    const initialize = fallbackFor("ole32.dll", "CoInitializeEx");
    try std.testing.expectEqual(Outcome.succeeded, initialize.outcome);
    try std.testing.expectEqual(@as(u64, 0), initialize.value);

    // ...and teardown of an apartment that was never created returns void.
    try std.testing.expectEqual(ReturnConvention.void_call, returnConvention("ole32.dll", "CoUninitialize"));
}

test "handle-shaped imports keep the zero return that already spelled failure" {
    for ([_][]const u8{ "CreateCompatibleDC", "LoadImageW", "OpenClipboard" }) |name| {
        const fallback = fallbackFor("GDI32.dll", name);
        try std.testing.expect(!fallback.differsFromZeroReturn());
    }
    // ...except where the ABI's failure value is INVALID_HANDLE_VALUE.
    const open_file = fallbackFor("kernel32.dll", "CreateFileW");
    try std.testing.expectEqual(std.math.maxInt(u64), open_file.value);
    // A mapping object really does report failure with NULL.
    try std.testing.expectEqual(@as(u64, 0), fallbackFor("kernel32.dll", "CreateFileMappingW").value);
}

test "GDI and USER refusals stay FALSE so an unimplemented draw call fails visibly" {
    const blit = fallbackFor("GDI32.dll", "BitBlt");
    try std.testing.expectEqual(@as(u64, 0), blit.value);
    try std.testing.expectEqual(@as(?u32, 120), blit.last_error);
    try std.testing.expectEqual(Outcome.refused, blit.outcome);
}

test "an OLE library keeps its own conventions rather than a library-wide HRESULT" {
    // SysAllocString hands back a BSTR.  A library-wide HRESULT rule would
    // return E_NOTIMPL, and the caller would dereference 0x80004001.
    try std.testing.expectEqual(ReturnConvention.handle, returnConvention("OLEAUT32.dll", "SysAllocString"));
    try std.testing.expectEqual(@as(u64, 0), fallbackFor("OLEAUT32.dll", "SysAllocString").value);
    // SysStringLen is a length, and StringFromGUID2 a character count.
    try std.testing.expectEqual(@as(u64, 0), fallbackFor("OLEAUT32.dll", "SysStringLen").value);
    try std.testing.expectEqual(@as(u64, 0), fallbackFor("ole32.dll", "StringFromGUID2").value);
    // Releasing something that was never allocated still succeeds.
    try std.testing.expectEqual(@as(u64, 0), fallbackFor("OLEAUT32.dll", "SysFreeString").value);
    try std.testing.expectEqual(Outcome.succeeded, fallbackFor("ole32.dll", "PropVariantClear").outcome);
    // The genuinely HRESULT-shaped names in the same library are unaffected.
    try std.testing.expectEqual(@as(u64, 0x8000_4001), fallbackFor("ole32.dll", "CLSIDFromString").value);
}

test "a teardown verb is only recognized after its own family prefix" {
    try std.testing.expect(hasTeardownShape("RegCloseKey"));
    try std.testing.expect(hasTeardownShape("PropVariantClear"));
    // `SysFreeString` carries its verb in the middle and is not recognized,
    // which costs nothing: its convention already spells absence with zero,
    // so the teardown question never arises for it.
    try std.testing.expect(!returnConvention("OLEAUT32.dll", "SysFreeString").zeroMeansSuccess());
    // A trailing verb inside a longer word is not a teardown.
    try std.testing.expect(!hasTeardownShape("CoCreateFreeThreadedMarshaler"));
    try std.testing.expect(hasTeardownShape("CoFreeUnusedLibraries"));
    try std.testing.expect(hasTeardownShape("CloseHandle"));
    // The verb appearing inside an unrelated name must not make it teardown.
    try std.testing.expect(!hasTeardownShape("GetFreeSpace"));
    try std.testing.expect(!hasTeardownShape("SHGetFolderPathW"));
}

test "a stub whose zero is a real answer is separated from an inert one" {
    // A case-insensitive compare that returns zero has said "these strings
    // are equal", which is why it cannot be reported as harmless.
    const compare = fallbackFor("api-ms-win-crt-string-l1-1-0.dll", "_stricmp");
    try std.testing.expect(compare.hazard);
    try std.testing.expect(std.mem.indexOf(u8, advice(compare), "implement it") != null);
    try std.testing.expect(fallbackFor("api-ms-win-crt-string-l1-1-0.dll", "memchr").hazard);
    try std.testing.expect(fallbackFor("api-ms-win-crt-string-l1-1-0.dll", "wcsncmp").hazard);
    try std.testing.expect(fallbackFor("api-ms-win-crt-stdio-l1-1-0.dll", "__acrt_iob_func").hazard);
    try std.testing.expect(fallbackFor("api-ms-win-crt-stdio-l1-1-0.dll", "__p__fmode").hazard);

    // Registering an exit handler and reading an environment variable have
    // no such reading: zero is genuinely "nothing".
    try std.testing.expect(!fallbackFor("api-ms-win-crt-runtime-l1-1-0.dll", "_crt_atexit").hazard);
    try std.testing.expect(!fallbackFor("api-ms-win-crt-runtime-l1-1-0.dll", "_set_app_type").hazard);

    // A refusal is never a hazard -- the guest was told the call failed.
    try std.testing.expect(!fallbackFor("ADVAPI32.dll", "RegOpenKeyExW").hazard);
    try std.testing.expect(!fallbackFor("GDI32.dll", "BitBlt").hazard);
}

test "advice separates the fallbacks that need work from the ones that do not" {
    // Releasing something that was never created is genuinely a success, and
    // the advice says so rather than sending someone to implement it.
    const harmless = fallbackFor("ADVAPI32.dll", "RegCloseKey");
    try std.testing.expectEqual(Outcome.succeeded, harmless.outcome);
    try std.testing.expect(std.mem.indexOf(u8, advice(harmless), "needs no implementation") != null);

    // A call with no observable result is separated from one that refused.
    const silent = fallbackFor("ole32.dll", "CoTaskMemFree");
    try std.testing.expectEqual(ReturnConvention.void_call, silent.convention);
    try std.testing.expect(std.mem.indexOf(u8, advice(silent), "safe to leave unimplemented") != null);

    const load_bearing = fallbackFor("ole32.dll", "CoCreateInstance");
    try std.testing.expect(std.mem.indexOf(u8, advice(load_bearing), "fallback path") != null);
}

test "a COM name is recognized by spelling, not by returning an HRESULT" {
    try std.testing.expect(isComponentObjectName("CoCreateInstance"));
    try std.testing.expect(isComponentObjectName("RoGetActivationFactory"));
    try std.testing.expect(isComponentObjectName("CLSIDFromString"));
    // These return HRESULTs and belong to their own subsystems.
    try std.testing.expect(!isComponentObjectName("SHGetKnownFolderPath"));
    try std.testing.expect(!isComponentObjectName("BitBlt"));
    try std.testing.expectEqual(ReturnConvention.hresult, returnConvention("SHELL32.dll", "SHGetKnownFolderPath"));
}
