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
//! forward — the failure then surfaces far away from the import that caused
//! it.
//!
//! So the fallback is a contract rather than a constant.  Each name is mapped
//! to the return convention its ABI actually uses, and the fallback emits the
//! value that convention defines for "this did not happen".  Where a call has
//! nothing to produce — teardown, an initializer with no output — reporting
//! success is the honest answer and is spelled that way explicitly.
//!
//! The mapping is derived from the DLL and the shape of the name, never from
//! one title's import table, so a PE Rosetta has never seen gets the same
//! treatment.  The runtime ledger at the bottom of this file records which of
//! these fallbacks a run actually took, because the static classification can
//! only say what would happen — the run says what did.

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

fn isComName(name: []const u8) bool {
    // `Co` followed by another capital: CoCreateInstance, CoInitializeEx.
    if (std.mem.startsWith(u8, name, "Co") and name.len > 2 and std.ascii.isUpper(name[2])) return true;
    if (std.mem.startsWith(u8, name, "Ole") and name.len > 3 and std.ascii.isUpper(name[3])) return true;
    // `Ro` is the WinRT runtime prefix (RoInitialize, RoGetActivationFactory).
    if (std.mem.startsWith(u8, name, "Ro") and name.len > 2 and std.ascii.isUpper(name[2])) return true;
    if (std.mem.startsWith(u8, name, "Windows") and name.len > 7 and std.ascii.isUpper(name[7])) return true;
    if (std.mem.startsWith(u8, name, "CLSIDFrom")) return true;
    if (std.mem.startsWith(u8, name, "IIDFrom")) return true;
    if (std.mem.startsWith(u8, name, "ProgIDFrom")) return true;
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
    if (isComName(name)) return .hresult;
    if (std.mem.startsWith(u8, name, "WSA")) return .winsock_status;
    if (isKnownDll(dll_name, "ole32") or isKnownDll(dll_name, "oleaut32") or
        isKnownDll(dll_name, "combase") or isKnownDll(dll_name, "dxgi") or
        isKnownDll(dll_name, "dwmapi") or isKnownDll(dll_name, "shcore") or
        isKnownDll(dll_name, "propsys")) return .hresult;

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

fn isHonestSuccess(name: []const u8) bool {
    for (honest_success_names) |known| {
        if (std.mem.eql(u8, name, known)) return true;
    }
    return hasTeardownShape(name);
}

/// The complete deterministic answer for an import Rosetta recognizes but has
/// not implemented.
pub fn fallbackFor(dll_name: []const u8, name: []const u8) Fallback {
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

/// A bounded record of the fallbacks a run actually took.
///
/// The static import classification can only say which names are *eligible*
/// for a fallback — for a large PE that is hundreds of names, most of which
/// are never called.  This records the ones that were, so a report names the
/// handful that a run actually depends on instead of the whole inventory.
pub const Ledger = struct {
    pub const capacity: usize = 96;
    pub const name_capacity: usize = 64;
    pub const dll_capacity: usize = 32;

    pub const Entry = struct {
        used: bool = false,
        name_buffer: [name_capacity]u8 = [_]u8{0} ** name_capacity,
        name_length: usize = 0,
        dll_buffer: [dll_capacity]u8 = [_]u8{0} ** dll_capacity,
        dll_length: usize = 0,
        calls: u64 = 0,
        first_step: u64 = 0,
        first_caller_rip: u64 = 0,
        convention: ReturnConvention = .zero_count,
        outcome: Outcome = .refused,
        value: u64 = 0,
        /// Set when the entry has appeared since the last report, so a
        /// checkpoint can print only what is new.
        unreported: bool = false,

        pub fn name(self: *const Entry) []const u8 {
            return self.name_buffer[0..self.name_length];
        }

        pub fn dll(self: *const Entry) []const u8 {
            return self.dll_buffer[0..self.dll_length];
        }
    };

    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,
    /// Fallbacks taken by names that did not fit the table.  Kept so a
    /// truncated report says so rather than looking complete.
    overflow_calls: u64 = 0,
    overflow_names: u64 = 0,
    total_calls: u64 = 0,
    unreported_count: usize = 0,

    fn store(destination: []u8, source: []const u8) usize {
        const length = @min(destination.len, source.len);
        @memcpy(destination[0..length], source[0..length]);
        return length;
    }

    /// Record one fallback.  Returns true when this is the first time the
    /// name has been seen, which is the only moment worth logging eagerly.
    pub fn note(
        self: *Ledger,
        dll_name: []const u8,
        name: []const u8,
        fallback: Fallback,
        step: u64,
        caller_rip: u64,
    ) bool {
        self.total_calls +|= 1;
        for (self.entries[0..self.count]) |*entry| {
            if (!std.mem.eql(u8, entry.name(), name[0..@min(name.len, name_capacity)])) continue;
            entry.calls +|= 1;
            return false;
        }
        if (self.count == capacity) {
            self.overflow_calls +|= 1;
            self.overflow_names +|= 1;
            return false;
        }
        var entry = Entry{
            .used = true,
            .calls = 1,
            .first_step = step,
            .first_caller_rip = caller_rip,
            .convention = fallback.convention,
            .outcome = fallback.outcome,
            .value = fallback.value,
            .unreported = true,
        };
        entry.name_length = store(&entry.name_buffer, name);
        entry.dll_length = store(&entry.dll_buffer, dll_name);
        self.entries[self.count] = entry;
        self.count += 1;
        self.unreported_count += 1;
        return true;
    }

    pub fn isEmpty(self: *const Ledger) bool {
        return self.count == 0;
    }

    /// Fallbacks whose returned value is something a guest can act on — the
    /// subset worth reading first when a run misbehaves.
    pub fn refusedCount(self: *const Ledger) usize {
        var total: usize = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.outcome == .refused) total += 1;
        }
        return total;
    }

    pub fn markReported(self: *Ledger) void {
        for (self.entries[0..self.count]) |*entry| entry.unreported = false;
        self.unreported_count = 0;
    }

    /// Indices ordered by call count, most-called first, so a bounded report
    /// shows the fallbacks a run leans on rather than the first ones it hit.
    pub fn rankedInto(self: *const Ledger, out: []usize) usize {
        const total = @min(out.len, self.count);
        var used: usize = 0;
        var taken = [_]bool{false} ** capacity;
        while (used < total) : (used += 1) {
            var best: ?usize = null;
            for (self.entries[0..self.count], 0..) |entry, index| {
                if (taken[index]) continue;
                const better = if (best) |current|
                    entry.calls > self.entries[current].calls
                else
                    true;
                if (better) best = index;
            }
            const chosen = best orelse break;
            taken[chosen] = true;
            out[used] = chosen;
        }
        return used;
    }
};

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

test "the ledger keeps first-observation evidence and ranks by call count" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.isEmpty());

    const reg = fallbackFor("ADVAPI32.dll", "RegOpenKeyExW");
    try std.testing.expect(ledger.note("ADVAPI32.dll", "RegOpenKeyExW", reg, 100, 0x1400_1000));
    // A repeat is not a new observation, so nothing needs to be logged again.
    try std.testing.expect(!ledger.note("ADVAPI32.dll", "RegOpenKeyExW", reg, 200, 0x1400_2000));

    const blit = fallbackFor("GDI32.dll", "BitBlt");
    try std.testing.expect(ledger.note("GDI32.dll", "BitBlt", blit, 300, 0x1400_3000));

    try std.testing.expectEqual(@as(usize, 2), ledger.count);
    try std.testing.expectEqual(@as(u64, 3), ledger.total_calls);
    try std.testing.expectEqual(@as(u64, 100), ledger.entries[0].first_step);
    try std.testing.expectEqual(@as(u64, 0x1400_1000), ledger.entries[0].first_caller_rip);

    var order: [4]usize = undefined;
    try std.testing.expectEqual(@as(usize, 2), ledger.rankedInto(&order));
    try std.testing.expectEqualStrings("RegOpenKeyExW", ledger.entries[order[0]].name());
    try std.testing.expectEqualStrings("BitBlt", ledger.entries[order[1]].name());

    try std.testing.expectEqual(@as(usize, 2), ledger.unreported_count);
    ledger.markReported();
    try std.testing.expectEqual(@as(usize, 0), ledger.unreported_count);
    // Reporting does not forget the entry, so the exit summary is complete.
    try std.testing.expectEqual(@as(usize, 2), ledger.count);
}

test "a teardown verb is only recognized after its own family prefix" {
    try std.testing.expect(hasTeardownShape("RegCloseKey"));
    try std.testing.expect(hasTeardownShape("CoFreeUnusedLibraries"));
    try std.testing.expect(hasTeardownShape("CloseHandle"));
    // The verb appearing inside an unrelated name must not make it teardown.
    try std.testing.expect(!hasTeardownShape("GetFreeSpace"));
    try std.testing.expect(!hasTeardownShape("SHGetFolderPathW"));
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
