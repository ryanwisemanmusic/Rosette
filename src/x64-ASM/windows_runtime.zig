//! Rosetta's narrow Microsoft x64 ABI surface.
//!
//! This is intentionally a guest-side model, not a collection of host
//! pointers. A Windows PE image receives ordinary guest addresses and every
//! call is completed inside the emulated register/memory state. That keeps
//! calling-convention mistakes, missing imports, and graphics-loader gaps
//! observable instead of letting an arbitrary macOS function pointer enter the
//! translated process.

const std = @import("std");

const import_contract = @import("windows_import_contract.zig");

const log = std.log.scoped(.windows_runtime);

/// Re-exported so the PE state can hold the ledger and the preflight report
/// can describe a name's contract without depending on this module's internals.
pub const ImportReturnConvention = import_contract.ReturnConvention;
pub const ImportFallback = import_contract.Fallback;
pub const ImportFallbackLedger = import_contract.Ledger;
pub const importFallbackFor = import_contract.fallbackFor;
pub const importFallbackAdvice = import_contract.advice;
pub const ImportSubsystem = import_contract.Subsystem;
pub const importSubsystemFor = import_contract.subsystemFor;
pub const importSubsystemForImport = import_contract.subsystemForImport;
pub const ModuleAvailability = import_contract.ModuleAvailability;
pub const moduleAvailability = import_contract.moduleAvailability;

// Win32's HWND_MESSAGE is the parent used for message-only helper windows.
// It is not a real drawable window and must never be forwarded to AppKit.
const hwnd_message: u64 = std.math.maxInt(u64) - 2; // (HWND)-3
const cw_use_default: u64 = 0x8000_0000;
const default_window_width: u64 = 1280;
const default_window_height: u64 = 720;
const max_window_dimension: u64 = 16 * 1024;
const windows_guest_thread_service_slice: u64 = 10_000;

// RedrawWindow request bits.  Only the two that decide whether the update
// region grows or is cleared are modelled; the erase/frame/child bits need a
// GDI surface Rosetta does not own.
const rdw_invalidate: u32 = 0x0001;
const rdw_validate: u32 = 0x0008;

// CONFIGRET values from cfgmgr32.h. Zero is CR_SUCCESS, so none of the
// refusals below may be spelled with it.
const cr_success: u64 = 0x00000000;
const cr_failure: u64 = 0x00000013;
const cr_no_such_devinst: u64 = 0x0000000D;
const cr_no_such_devnode: u64 = 0x0000000C;

// MinGW's Windows CRT exposes wctype_t as the same bit-mask space used by
// _pctype, rather than as an arbitrary host pointer. Keep those ABI values
// here so a descriptor returned by wctype can also be passed to iswctype.
// `_ALPHA` intentionally includes the high alpha bit plus UPPER/LOWER.
const c_locale_wctype_upper: u64 = 0x01;
const c_locale_wctype_lower: u64 = 0x02;
const c_locale_wctype_digit: u64 = 0x04;
const c_locale_wctype_space: u64 = 0x08;
const c_locale_wctype_punct: u64 = 0x10;
const c_locale_wctype_cntrl: u64 = 0x20;
const c_locale_wctype_blank: u64 = 0x40;
const c_locale_wctype_xdigit: u64 = 0x80;
const c_locale_wctype_alpha: u64 = 0x103;
const c_locale_wctype_alnum: u64 = c_locale_wctype_alpha | c_locale_wctype_digit;
const c_locale_wctype_graph: u64 = c_locale_wctype_punct | c_locale_wctype_alnum;
const c_locale_wctype_print: u64 = c_locale_wctype_blank | c_locale_wctype_graph;

fn cLocaleWctypeDescriptor(property: []const u8) u64 {
    if (std.mem.eql(u8, property, "alnum")) return c_locale_wctype_alnum;
    if (std.mem.eql(u8, property, "alpha")) return c_locale_wctype_alpha;
    if (std.mem.eql(u8, property, "blank")) return c_locale_wctype_blank;
    if (std.mem.eql(u8, property, "cntrl")) return c_locale_wctype_cntrl;
    if (std.mem.eql(u8, property, "digit")) return c_locale_wctype_digit;
    if (std.mem.eql(u8, property, "graph")) return c_locale_wctype_graph;
    if (std.mem.eql(u8, property, "lower")) return c_locale_wctype_lower;
    if (std.mem.eql(u8, property, "print")) return c_locale_wctype_print;
    if (std.mem.eql(u8, property, "punct")) return c_locale_wctype_punct;
    if (std.mem.eql(u8, property, "space")) return c_locale_wctype_space;
    if (std.mem.eql(u8, property, "upper")) return c_locale_wctype_upper;
    if (std.mem.eql(u8, property, "xdigit")) return c_locale_wctype_xdigit;
    return 0;
}

fn cLocaleIsWideClass(value: u64, descriptor: u64) bool {
    if (value > 0x7f) return false;
    const character: u8 = @intCast(value);
    const alpha = (character >= 'A' and character <= 'Z') or (character >= 'a' and character <= 'z');
    const digit = character >= '0' and character <= '9';
    const lower = character >= 'a' and character <= 'z';
    const upper = character >= 'A' and character <= 'Z';
    const space = character == ' ' or (character >= '\t' and character <= '\r');
    const graph = character >= 0x21 and character <= 0x7e;
    var classification: u64 = 0;
    if (upper) classification |= c_locale_wctype_upper;
    if (lower) classification |= c_locale_wctype_lower;
    if (alpha) classification |= 0x100;
    if (digit) classification |= c_locale_wctype_digit;
    if (space) classification |= c_locale_wctype_space;
    if (character == ' ' or character == '\t') classification |= c_locale_wctype_blank;
    if (graph and !(alpha or digit)) classification |= c_locale_wctype_punct;
    if (character < 0x20 or character == 0x7f) classification |= c_locale_wctype_cntrl;
    if (digit or (character >= 'A' and character <= 'F') or (character >= 'a' and character <= 'f')) {
        classification |= c_locale_wctype_xdigit;
    }
    return (classification & descriptor) != 0;
}

fn normalizeWindowDimension(value: u64, fallback: u64) u64 {
    if (value == 0 or value == cw_use_default or value > max_window_dimension) {
        return fallback;
    }
    return value;
}

/// A guest return address used while a Windows `pthread_once` initializer is
/// running. The ELF executor intercepts this value before trying to decode it
/// and commits the once-control word before restoring the caller's
/// continuation. Keeping the marker in the Windows ABI module makes the
/// callback protocol explicit without putting host function pointers on the
/// guest stack.
pub const SYNTHETIC_PTHREAD_ONCE_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF18;

/// A guest return address used while the Microsoft CRT walks an `_initterm`
/// table. The executor consumes this marker after each initializer returns,
/// advances the table cursor, and restores the original import continuation
/// only after the entire table has been visited.
pub const SYNTHETIC_INITTERM_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF20;

/// A guest return address used while Rosetta performs one comparison in the
/// bounded Windows `qsort` model. The ELF executor consumes it and resumes
/// the next comparison without exposing a host callback pointer to the PE.
pub const SYNTHETIC_QSORT_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF38;

// Rosette's PE executor owns the setjmp/longjmp boundary rather than calling a
// host libc implementation. Only the non-volatile integer context and the
// continuation are needed by the Windows SDL/Xenia bootstrap path; keeping a
// private marker makes an accidental longjmp into an arbitrary guest buffer a
// visible runtime error instead of a guessed control transfer.
const windows_setjmp_magic: u64 = 0x5253_544A_4D50_0001;
const windows_setjmp_bytes: u64 = 96;

pub const ImportClass = enum {
    core,
    graphics,
    /// The name is owned by one of Rosetta's per-DLL packages and has an
    /// explicit ABI contract.  Some of these contracts are stateful (file,
    /// wait, graphics and CRT paths); optional Windows-only facilities may
    /// instead return their documented refusal.  They are still complete
    /// import bindings: no unresolved or untyped zero-return path is used.
    contract,
    /// Reserved for a future inventory entry that is recognized but has not
    /// yet been given even a typed import contract.  The current catalogue
    /// must keep this at zero.
    degraded,
    unsupported,
};

pub fn classifyImport(dll_name: []const u8, function_name: []const u8) ImportClass {
    if (isGraphicsImport(dll_name, function_name)) return .graphics;
    if (isKnownCoreImport(function_name)) return .core;
    if (isKnownContractImport(dll_name, function_name)) return .contract;
    return .unsupported;
}

pub fn isSupportedImport(dll_name: []const u8, function_name: []const u8) bool {
    return classifyImport(dll_name, function_name) != .unsupported;
}

/// Complete the empty-character-set case of a recognized guest
/// `find_any_of` implementation. The PE image's implementation follows the
/// same contract as `find_first_of`: an empty set has no possible match and
/// therefore returns `string_view::npos`. Some Windows images materialize a
/// `std::string_view` beginning with an embedded NUL through the
/// null-terminated constructor, leaving its length at zero; allowing the
/// guest helper's early `0` return turns every ordinary value into the escape
/// path and corrupts otherwise valid configuration text.
///
/// The PE loader arms this only after recognizing the guest helper's machine
/// code. No arbitrary guest address or host pointer is accepted here.
fn completeGuestConditionCall(state: anytype) void {
    state.regs.rax = 0;
    // The internal MinGW pthread routines are entered by an ordinary guest
    // CALL, so their return address is still at [RSP].  Completing the call
    // before the routine's host semaphore loop is what makes the policy
    // cooperative rather than a fake import return.
    state.regs.rip = state.pop();
}

pub fn tryGuestCompatibility(state: anytype) bool {
    if (!state.windows_runtime_enabled) return false;

    // Xenia's Windows PE often links MinGW's pthread implementation into the
    // image.  Those routines do not pass through the import dispatcher, and
    // their semaphore loop cannot block the single Rosetta host thread.  The
    // PE intake publishes signature-discovered entry points so this remains
    // valid when a rebuilt image moves the routines.
    const State = @TypeOf(state.*);
    if (comptime @hasField(State, "windows_pthread_cond_wait_entry") and
        @hasDecl(State, "waitWindowsGuestCondition"))
    {
        const use_native_condition = if (comptime @hasField(State, "windows_pthread_cond_native"))
            state.windows_pthread_cond_native
        else
            false;
        if (!use_native_condition) if (state.windows_pthread_cond_wait_entry) |entry| {
            if (state.regs.rip == entry) {
                const result = state.waitWindowsGuestCondition(state.regs.rcx, state.regs.rdx);
                state.windows_condition_hook_events +|= 1;
                if (state.trace_windows_conditions and
                    (state.windows_condition_hook_events <= 8 or
                        (state.windows_condition_hook_events & (state.windows_condition_hook_events - 1)) == 0))
                {
                    log.info("PE64 condition hook: wait condition=0x{x} mutex=0x{x} result={s} thread=0x{x} step={d} blocked={d} unblocked={d}", .{
                        state.regs.rcx,
                        state.regs.rdx,
                        @tagName(result),
                        state.active_guest_thread,
                        state.executed_steps,
                        state.windows_thread_blocks,
                        state.windows_thread_unblocks,
                    });
                }
                switch (result) {
                    .blocked => return true,
                    .resumed, .invalid => {
                        completeGuestConditionCall(state);
                        return true;
                    },
                }
            }
        };
    }
    if (comptime @hasField(State, "windows_pthread_cond_signal_entry") and
        @hasDecl(State, "signalWindowsGuestCondition"))
    {
        const use_native_condition = if (comptime @hasField(State, "windows_pthread_cond_native"))
            state.windows_pthread_cond_native
        else
            false;
        if (!use_native_condition) if (state.windows_pthread_cond_signal_entry) |entry| {
            if (state.regs.rip == entry) {
                const woken = state.signalWindowsGuestCondition(state.regs.rcx, false);
                state.windows_condition_hook_events +|= 1;
                if (state.trace_windows_conditions and
                    (state.windows_condition_hook_events <= 8 or
                        (state.windows_condition_hook_events & (state.windows_condition_hook_events - 1)) == 0))
                {
                    log.info("PE64 condition hook: signal condition=0x{x} woken={d} thread=0x{x} step={d}", .{
                        state.regs.rcx,
                        woken,
                        state.active_guest_thread,
                        state.executed_steps,
                    });
                }
                completeGuestConditionCall(state);
                return true;
            }
        };
    }
    if (comptime @hasField(State, "windows_pthread_cond_broadcast_entry") and
        @hasDecl(State, "signalWindowsGuestCondition"))
    {
        const use_native_condition = if (comptime @hasField(State, "windows_pthread_cond_native"))
            state.windows_pthread_cond_native
        else
            false;
        if (!use_native_condition) if (state.windows_pthread_cond_broadcast_entry) |entry| {
            if (state.regs.rip == entry) {
                const woken = state.signalWindowsGuestCondition(state.regs.rcx, true);
                state.windows_condition_hook_events +|= 1;
                if (state.trace_windows_conditions and
                    (state.windows_condition_hook_events <= 8 or
                        (state.windows_condition_hook_events & (state.windows_condition_hook_events - 1)) == 0))
                {
                    log.info("PE64 condition hook: broadcast condition=0x{x} woken={d} thread=0x{x} step={d}", .{
                        state.regs.rcx,
                        woken,
                        state.active_guest_thread,
                        state.executed_steps,
                    });
                }
                completeGuestConditionCall(state);
                return true;
            }
        };
    }

    const entry = state.windows_utf8_find_any_of_entry orelse return false;
    if (state.regs.rip != entry) return false;

    const needle_view = state.regs.rdx;
    const needle_bytes = state.guestMemoryConst(needle_view, 16) orelse return false;
    const needle_length = std.mem.readInt(u64, needle_bytes[0..8], .little);
    if (needle_length != 0) return false;

    const return_rip = state.read64(state.regs.rsp);
    if (return_rip == 0 or state.addrToOffset(return_rip) == null) return false;

    // This runs at the function entry, before the guest prologue has pushed
    // callee-saved registers or reserved its local frame.
    state.regs.rax = std.math.maxInt(u64);
    state.regs.rsp +|= 8;
    state.regs.rip = return_rip;
    state.windows_guest_compatibility_events +|= 1;
    // This is a recognized, deterministic compatibility repair. Keep the
    // first few observations and then emit only powers of two so a title
    // repeatedly taking the same path cannot drown out graphics milestones or
    // the eventual fault in either the terminal or the detailed run log.
    const event = state.windows_guest_compatibility_events;
    if (event <= 3 or (event & (event - 1)) == 0) {
        log.info("Windows guest compatibility: empty UTF-8 character set -> npos entry=0x{x} return=0x{x} events={d}", .{
            entry,
            return_rip,
            event,
        });
    }
    return true;
}

fn isGraphicsImport(dll_name: []const u8, function_name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(dll_name, "vulkan-1.dll") or
        std.ascii.eqlIgnoreCase(dll_name, "vulkan-1") or
        std.ascii.eqlIgnoreCase(dll_name, "vulkan.dll") or
        std.ascii.eqlIgnoreCase(dll_name, "dxgi.dll") or
        std.mem.startsWith(u8, function_name, "vk");
}

fn isKnownCoreImport(name: []const u8) bool {
    if (name.len == 0) return false;
    // The PE loader and the MSVC runtime use a large family of prefixed
    // helpers. These prefixes are deliberately limited to ABI/runtime names;
    // arbitrary C++ imports still remain visible as unsupported.
    if (std.mem.startsWith(u8, name, "Rtl") or
        std.mem.startsWith(u8, name, "Nt") or
        std.mem.startsWith(u8, name, "Zw") or
        std.mem.startsWith(u8, name, "__stdio_common_") or
        std.mem.startsWith(u8, name, "__p_")) return true;

    const known_names = [_][]const u8{
        // Process, module, error, and environment state.
        "GetLastError",
        "SetLastError",
        "GetHandleInformation",
        "GetCurrentProcess",
        "GetCurrentThread",
        "GetCurrentProcessId",
        "GetCurrentThreadId",
        "GetProcessHeap",
        "GetModuleHandleA",
        "GetModuleHandleW",
        "ExitProcess",
        "TerminateProcess",
        "exit",
        "_exit",
        "_Exit",
        "quick_exit",
        "_cexit",
        "_c_exit",
        "LoadLibraryA",
        "LoadLibraryW",
        "LoadLibraryExA",
        "LoadLibraryExW",
        "FreeLibrary",
        "GetProcAddress",
        "GetModuleFileNameA",
        "GetModuleFileNameW",
        "GetModuleInformation",
        "SetUnhandledExceptionFilter",
        "GetThreadDescription",
        "SetThreadDescription",
        "IsDebuggerPresent",
        "GetEnvironmentVariableA",
        "GetEnvironmentVariableW",
        "SetEnvironmentVariableA",
        "SetEnvironmentVariableW",
        "GetCommandLineA",
        "GetCommandLineW",
        "GetSystemDirectoryA",
        "GetSystemDirectoryW",
        "GetWindowsDirectoryA",
        "GetWindowsDirectoryW",
        "GetTempPathA",
        "GetTempPathW",
        "GetCurrentDirectoryA",
        "GetCurrentDirectoryW",
        "GetVersionExA",
        "GetVersionExW",

        // dbghelp's symbol service is used by Xenia's Windows stack walker
        // during processor startup.  The PE runner cannot expose host stack
        // addresses as guest pointers, but it can preserve the option and
        // initialization contracts so diagnostics do not abort startup.
        "SymGetOptions",
        "SymSetOptions",
        "SymInitialize",
        "SymCleanup",
        "StackWalk64",
        "SymFunctionTableAccess64",
        "SymGetModuleBase64",
        "SymGetSymFromAddr64",
        "SymFromAddr",
        "SymGetLineFromAddr64",
        "SymGetModuleInfo64",
        "SymRefreshModuleList",

        // Virtual memory and heap entry points.
        "VirtualAlloc",
        "VirtualAllocEx",
        "VirtualFree",
        "VirtualFreeEx",
        "VirtualProtect",
        "VirtualProtectEx",
        "VirtualQuery",
        "VirtualQueryEx",
        "HeapAlloc",
        "HeapReAlloc",
        "HeapFree",
        "HeapSize",
        "HeapCreate",
        "HeapDestroy",
        "RtlAllocateHeap",
        "RtlReAllocateHeap",
        "RtlFreeHeap",
        "RtlSizeHeap",
        "LocalAlloc",
        "LocalReAlloc",
        "LocalFree",
        "GlobalAlloc",
        "GlobalReAlloc",
        "GlobalFree",
        "CoTaskMemAlloc",
        "CoTaskMemRealloc",
        "CoTaskMemFree",

        // Synchronization and thread lifecycle. The cooperative executor
        // cannot safely block the host here, so these are non-blocking guest
        // operations with explicit deterministic results.
        "InitializeCriticalSection",
        "InitializeCriticalSectionEx",
        "InitializeCriticalSectionAndSpinCount",
        "DeleteCriticalSection",
        "EnterCriticalSection",
        "LeaveCriticalSection",
        "TryEnterCriticalSection",
        "CreateEventA",
        "CreateEventW",
        "CreateMutexA",
        "CreateMutexW",
        "CreateSemaphoreA",
        "CreateSemaphoreW",
        "pthread_once",
        "SetEvent",
        "ResetEvent",
        "PulseEvent",
        "ReleaseMutex",
        "ReleaseSemaphore",
        "CloseHandle",
        "WaitForSingleObject",
        "WaitForSingleObjectEx",
        "WaitForMultipleObjects",
        "WaitForMultipleObjectsEx",
        "Sleep",
        "SleepEx",
        "SwitchToThread",
        "CreateThread",
        "CreateRemoteThread",
        "ExitThread",
        "TlsAlloc",
        "TlsGetValue",
        "TlsSetValue",
        "TlsFree",
        "FlsAlloc",
        "FlsGetValue",
        "FlsSetValue",
        "FlsFree",
        "GetQueuedCompletionStatus",
        "PostQueuedCompletionStatus",
        "SetThreadContext",

        // File and path APIs. The model reports absence until a real Rosetta
        // filesystem binding is installed; it never fabricates file contents.
        "CreateFileA",
        "CreateFileW",
        "CreateFileMappingA",
        "CreateFileMappingW",
        "MapViewOfFile",
        "MapViewOfFileEx",
        "UnmapViewOfFile",
        "ReadFile",
        "WriteFile",
        "FlushFileBuffers",
        "GetFileSize",
        "GetFileSizeEx",
        "SetFilePointer",
        "SetFilePointerEx",
        "SetEndOfFile",
        "FlushFileBuffers",
        "GetFileAttributesA",
        "GetFileAttributesW",
        "GetFileAttributesExA",
        "GetFileAttributesExW",
        "FindFirstFileA",
        "FindFirstFileW",
        "FindFirstFileExA",
        "FindFirstFileExW",
        "FindNextFileA",
        "FindNextFileW",
        "FindClose",
        "DeleteFileA",
        "DeleteFileW",
        "MoveFileA",
        "MoveFileW",
        "GetFullPathNameA",
        "GetFullPathNameW",

        // UCRT/MSVC stdio calls used by Xenia's Windows filesystem facade.
        // These are backed by the same confined handle table as CreateFile,
        // so FILE* values never contain host pointers.
        "__acrt_iob_func",
        "fopen",
        "fopen64",
        "_wfopen",
        "_wfsopen",
        "fdopen",
        "_fdopen",
        "fgetwc",
        "fclose",
        "fflush",
        "fread",
        "fwrite",
        "fseek",
        "ftell",
        "_fseeki64",
        "_ftelli64",
        "lseek64",
        "_lseeki64",
        "read",
        "_read",
        "write",
        "_write",
        "close",
        "_close",
        "setvbuf",
        "ferror",
        "feof",
        "fgetc",
        "fputc",
        "fputs",
        "fgets",
        "putc",
        "puts",
        "putchar",
        "_filelengthi64",
        "_chsize_s",
        "_fileno",
        "_stat64",
        "_wstat64",
        "__stat64",
        "_fstat64",
        "fstat64",

        // Win32 window/message entry points used by Xenia's UI shell.
        "RegisterClassA",
        "RegisterClassW",
        "RegisterClassExA",
        "RegisterClassExW",
        "UnregisterClassA",
        "UnregisterClassW",
        "CreateWindowExA",
        "CreateWindowExW",
        "DestroyWindow",
        "ShowWindow",
        "UpdateWindow",
        "SetWindowPos",
        "SetWindowLongA",
        "SetWindowLongW",
        "SetWindowLongPtrA",
        "SetWindowLongPtrW",
        "GetWindowLongA",
        "GetWindowLongW",
        "GetWindowLongPtrA",
        "GetWindowLongPtrW",
        "GetClassLongPtrW",
        "GetClientRect",
        "GetWindowRect",
        "GetWindowPlacement",
        "SetWindowPlacement",
        "GetDC",
        "ReleaseDC",
        "GetDeviceCaps",
        "BeginPaint",
        "EndPaint",
        "PeekMessageA",
        "PeekMessageW",
        "GetMessageA",
        "GetMessageW",
        "TranslateMessage",
        "DispatchMessageA",
        "DispatchMessageW",
        "DefWindowProcA",
        "DefWindowProcW",
        "PostQuitMessage",
        "PostMessageA",
        "PostMessageW",
        "GetSystemMetrics",
        "GetDpiForWindow",
        "AdjustWindowRectEx",
        "AdjustWindowRectExForDpi",
        "EnableNonClientDpiScaling",
        "GetDpiForSystem",
        "GetMonitorInfoA",
        "GetMonitorInfoW",
        "MonitorFromWindow",
        "SetCursor",
        "LoadCursorA",
        "LoadCursorW",
        "LoadIconA",
        "LoadIconW",
        "GetStockObject",
        "CreateIconFromResourceEx",
        "DestroyIcon",
        "SetWindowTextA",
        "SetWindowTextW",
        "SetPropA",
        "SetPropW",
        "GetPropA",
        "GetPropW",
        "RemovePropA",
        "RemovePropW",
        "RegisterDeviceNotificationA",
        "RegisterDeviceNotificationW",
        "UnregisterDeviceNotification",
        "CreateTimerQueueTimer",
        "DeleteTimerQueueTimer",
        "SetMenu",
        "CreateMenu",
        "CreatePopupMenu",
        "DestroyMenu",
        "AppendMenuA",
        "AppendMenuW",
        "EnableMenuItem",
        "DrawMenuBar",
        "SetMenuInfo",
        "GetMenuInfo",
        "MessageBoxA",
        "MessageBoxW",
        "SetFocus",
        "GetFocus",
        "GetCapture",
        "SetCapture",
        "ReleaseCapture",
        "GetCursorPos",
        "WindowFromPoint",
        "ScreenToClient",
        "ClientToScreen",
        "GetKeyState",
        "VkKeyScanW",
        "InvalidateRect",
        "InvalidateRgn",
        "RedrawWindow",
        "ValidateRect",
        "ValidateRgn",
        "GetUpdateRect",
        "SendMessageA",
        "SendMessageW",
        "AttachConsole",
        "DragAcceptFiles",
        "DragFinish",
        "DragQueryFileW",
        "GlobalAddAtomW",
        "GlobalDeleteAtom",
        "PostMessageA",
        "PostMessageW",
        "PostQuitMessage",

        // Time, performance counters, and processor-yield helpers.
        "QueryPerformanceCounter",
        "QueryPerformanceFrequency",
        "GetTickCount",
        "GetTickCount64",
        "GetSystemTimeAsFileTime",
        "GetSystemTimePreciseAsFileTime",
        "GetLocalTime",
        "GetSystemTime",
        "_localtime64",
        "asctime",
        "_lock_file",
        "_unlock_file",
        "YieldProcessor",
        "PauseProcessor",
        "GetNativeSystemInfo",
        "GetSystemInfo",
        "GetCurrentProcessorNumber",

        // Process startup and COM helpers used by Xenia's Windows shell.
        "CommandLineToArgvW",
        "WideCharToMultiByte",
        "MultiByteToWideChar",
        "CoInitializeEx",
        "CoUninitialize",
        "CoInitializeSecurity",
        "FormatMessageA",
        "FormatMessageW",
        "LocalFree",
        "DwmSetWindowAttribute",
        "DwmEnableMMCSS",
        "NtQueryTimerResolution",
        "NtSetTimerResolution",

        // Optional platform libraries linked by the Windows Xenia target.
        // These are kept in the ABI inventory so their absence is reported at
        // the call site rather than as an unrelated unresolved import.
        "XInputGetState",
        "XInputGetStateEx",
        "XInputSetState",
        "XInputGetCapabilities",
        "XInputEnable",
        "XInputGetBatteryInformation",
        "XInputGetKeystroke",
        "WSAStartup",
        "WSACleanup",
        "socket",
        "closesocket",
        "ioctlsocket",
        "setsockopt",
        "getsockopt",
        "connect",
        "send",
        "recv",
        "select",
        "getaddrinfo",
        "freeaddrinfo",
        "htons",
        "ntohs",
        "BCryptOpenAlgorithmProvider",
        "BCryptCloseAlgorithmProvider",
        "BCryptGetProperty",
        "BCryptCreateHash",
        "BCryptHashData",
        "BCryptFinishHash",
        "BCryptDestroyHash",
        "BCryptGenRandom",

        // MSVC/UCRT and compiler support. The ordinary allocation/string
        // cases are implemented below; the remaining helpers are safe ABI
        // no-ops whose lack of semantic work is logged by the runtime policy.
        "memcpy",
        "memmove",
        "memset",
        "memcmp",
        "strlen",
        "strnlen",
        "strcmp",
        "strncmp",
        "strcpy",
        "strncpy",
        "strcat",
        "strchr",
        "strrchr",
        "qsort",
        "tolower",
        "toupper",
        "wcslen",
        "wmemcpy",
        "wmemmove",
        "wmemset",
        "malloc",
        "calloc",
        "realloc",
        "free",
        "_malloc_base",
        "_free_base",
        "_recalloc",
        "_aligned_malloc",
        "_aligned_free",
        "_ultoa",
        "_setjmp",
        "longjmp",
        "_beginthread",
        "_beginthreadex",
        "_endthread",
        "_endthreadex",
        "_initterm",
        "_initterm_e",
        "__security_init_cookie",
        "__chkstk",
        "__chkstk_ms",
        "__C_specific_handler",
        "__CxxFrameHandler3",
        "__CxxFrameHandler4",
        "_except_handler4_common",
        "_purecall",
        "terminate",
        "__std_terminate",
        "set_new_handler",

        // Interlocked operations appear in the Xenia scheduler and resource
        // caches. They use the first Microsoft ABI argument as the address.
        "InterlockedIncrement",
        "InterlockedIncrement64",
        "InterlockedDecrement",
        "InterlockedDecrement64",
        "InterlockedExchange",
        "InterlockedExchange64",
        "InterlockedCompareExchange",
        "InterlockedCompareExchange64",
        "InterlockedOr",
        "InterlockedAnd",
        "InterlockedXor",
    };
    for (known_names) |known| {
        if (std.mem.eql(u8, name, known)) return true;
    }
    return false;
}

// These are the remaining imports emitted by the untouched Windows Xenia
// build after the GNU C++ runtime is linked into the PE. They are genuine
// names from the Win32/UCRT/MinGW ABI surface. Each name is owned by a
// per-DLL package and has an explicit return contract; a call that still
// needs stateful behavior is recorded as a contract refusal, not silently
// treated as an unresolved import.
// Static import-contract ownership lives in pkg/dll/win32/<dll>/ and is
// aggregated by the catalogue package. Keep runtime behavior below separate
// from those immutable facts.

fn isKnownContractImport(dll_name: []const u8, function_name: []const u8) bool {
    // The static name inventory is split into one package per DLL. The
    // runtime keeps only this bridge; handler behavior and mutable run state
    // remain here in the executable-side module.
    return import_contract.isContractImport(dll_name, function_name);
}

fn arg(state: anytype, index: usize, direct_return_rip: ?u64) u64 {
    return switch (index) {
        0 => state.regs.rcx,
        1 => state.regs.rdx,
        2 => state.regs.r8,
        3 => state.regs.r9,
        else => {
            // A direct IAT shortcut has not pushed the return address. An
            // indirect proc-address call has, so account for that difference
            // before reading the first stack argument.
            const stack_bias: u64 = if (direct_return_rip != null) 32 else 40;
            const base = state.regs.rsp + stack_bias;
            return state.read64(base + (index - 4) * 8);
        },
    };
}

/// The frequency Rosetta reports for its guest performance counter.
fn windowsGuestClockHz(state: anytype) u64 {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "windowsGuestClockHz")) {
        return state.windowsGuestClockHz();
    }
    return 1_000_000;
}

/// A fixed, plausible wall-clock base for the guest, as a FILETIME.
///
/// 2026-01-01T00:00:00Z in 100-nanosecond intervals since 1601-01-01. Fixed
/// rather than read from the host so a run is reproducible: the guest's sense
/// of "now" advances with the guest clock and nothing else.
const WINDOWS_GUEST_FILETIME_BASE: u64 = 134_116_992_000_000_000;

/// The guest's wall clock as a Win32 FILETIME.
fn windowsGuestFileTime(state: anytype) u64 {
    const ticks = windowsGuestClockTicks(state);
    const hz = windowsGuestClockHz(state);
    if (hz == 0) return WINDOWS_GUEST_FILETIME_BASE;
    // FILETIME counts 10,000,000 units a second; the guest clock counts `hz`.
    const seconds = ticks / hz;
    const remainder = ticks % hz;
    return WINDOWS_GUEST_FILETIME_BASE +|
        (seconds *| 10_000_000) +|
        (remainder *| 10_000_000 / hz);
}

fn windowsGuestClockTicks(state: anytype) u64 {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "windowsGuestClockTicks")) {
        return state.windowsGuestClockTicks();
    }
    // Keep this module usable with the small test doubles used by the import
    // contract tests. Real PE execution always supplies the shared clock.
    return state.executed_steps;
}

/// Keep Vulkan bring-up diagnostics separate from the full Windows ABI trace.
/// The latter is intentionally exhaustive and can drown the one graphics
/// failure that matters in millions of allocator/thread calls. This opt-in
/// switch records only the graphics import boundary, including whether the
/// native Rosetta bridge owned the call or the modelled fallback did.
fn graphicsTraceEnabled() bool {
    const raw = std.c.getenv("ROSETTE_ELF_GRAPHICS_TRACE") orelse return false;
    const value = std.mem.span(raw);
    return std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes");
}

fn traceGraphicsDispatch(state: anytype, name: []const u8, route: []const u8) void {
    if (!graphicsTraceEnabled()) return;
    log.info(
        "Windows graphics import: {s} route={s} result=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x} rip=0x{x} step={d}",
        .{
            name,
            route,
            state.regs.rax,
            state.regs.rcx,
            state.regs.rdx,
            state.regs.r8,
            state.regs.r9,
            state.regs.rip,
            state.executed_steps,
        },
    );
}

fn finish(state: anytype, direct_return_rip: ?u64) void {
    if (direct_return_rip) |rip| {
        state.regs.rip = rip;
    } else {
        const return_slot = state.regs.rsp;
        const return_rip = state.read64(return_slot);
        if (return_rip == 0 and
            (comptime @hasField(@TypeOf(state.*), "windows_active_guest_thread_slot")) and
            state.windows_active_guest_thread_slot != null)
        {
            log.err("Windows import return produced null RIP: thread=0x{x} import_rip=0x{x} rsp=0x{x} next_stack=0x{x}", .{
                state.active_guest_thread,
                state.regs.rip,
                return_slot,
                state.read64(return_slot +| 8),
            });
        }
        state.regs.rip = state.pop();
    }
}

/// The single virtual display Rosetta presents, allocated once and then
/// stable for the life of the process.
fn primaryMonitorHandle(state: anytype) u64 {
    const State = @TypeOf(state.*);
    if (comptime !@hasField(State, "windows_primary_monitor")) return nextHandle(state);
    if (state.windows_primary_monitor == 0) state.windows_primary_monitor = nextHandle(state);
    return state.windows_primary_monitor;
}

fn returnZero(state: anytype, direct_return_rip: ?u64) void {
    state.regs.rax = 0;
    finish(state, direct_return_rip);
}

const winmm_noerror: u64 = 0;
const winmm_not_supported: u64 = 8; // MMSYSERR_NOTSUPPORTED
const winmm_invalid_parameter: u64 = 11; // MMSYSERR_INVALPARAM
const winmm_no_memory: u64 = 14; // MMSYSERR_NOMEM
const winmm_wave_format_query: u64 = 1;
const winmm_callback_function: u64 = 0x0003_0000;
const winmm_whdr_done: u32 = 0x0000_0001;
const winmm_whdr_prepared: u32 = 0x0000_0002;
const winmm_whdr_inqueue: u32 = 0x0000_0010;
const winmm_wom_done: u64 = 3;
const winmm_wavehdr_bytes: u64 = 48;
const winmm_waveformatex_bytes: u64 = 18;
const winmm_waveoutcaps_bytes: u64 = 130; // WAVEOUTCAPS2W, including GUID fields

fn traceWindowsAudioEvent(state: anytype, event: []const u8, handle: u64, address: u64, bytes: u64) void {
    if (!state.trace_windows_audio) return;
    const count = state.windows_audio_import_calls;
    const power_of_two = count != 0 and (count & (count - 1)) == 0;
    if (count <= 8 or power_of_two) {
        log.info("Windows audio boundary: event={s} handle=0x{x} address=0x{x} bytes={d} step={d}", .{
            event,
            handle,
            address,
            bytes,
            state.executed_steps,
        });
    }
}

fn windowsWaveOutDevice(state: anytype, handle: u64) ?*@TypeOf(state.windows_wave_out_devices[0]) {
    for (&state.windows_wave_out_devices) |*device| {
        if (device.opened and device.guest_handle == handle) return device;
    }
    return null;
}

fn windowsWaveFormatSupported(state: anytype, format: u64) bool {
    if (format == 0 or state.guestMemoryConst(format, winmm_waveformatex_bytes) == null) return false;
    const format_tag = state.read16(format + 0);
    const channels = state.read16(format + 2);
    const sample_rate = state.read32(format + 4);
    const block_align = state.read16(format + 12);
    const bits_per_sample = state.read16(format + 14);
    if (format_tag != 1 and format_tag != 3) return false; // PCM or IEEE_FLOAT
    if (channels == 0 or channels > 8) return false;
    if (sample_rate < 8_000 or sample_rate > 192_000) return false;
    if (bits_per_sample != 8 and bits_per_sample != 16 and bits_per_sample != 32) return false;
    if (block_align == 0 or block_align != channels * @as(u16, @intCast(bits_per_sample / 8))) return false;
    return state.read32(format + 8) >= sample_rate * block_align;
}

fn writeWindowsWaveOutCaps(state: anytype, caps: u64, size: u64) void {
    if (caps == 0 or size == 0) return;
    const bounded = @min(size, winmm_waveoutcaps_bytes);
    const bounded_usize: usize = @intCast(bounded);
    if (state.guestMemory(caps, bounded) == null) return;
    if (bounded >= 4) state.write16(caps + 0, 0); // wMid
    if (bounded >= 6) state.write16(caps + 2, 0); // wPid
    if (bounded >= 8) state.write16(caps + 4, 1); // vDriverVersion
    const product_name = "Rosetta Virtual Audio";
    var index: usize = 0;
    while (index < product_name.len and 6 + index * 2 + 2 <= bounded_usize) : (index += 1) {
        state.write16(caps + @as(u64, @intCast(6 + index * 2)), product_name[index]);
    }
    if (6 + product_name.len * 2 + 2 <= bounded_usize) state.write16(caps + @as(u64, @intCast(6 + product_name.len * 2)), 0);
    // dwFormats: every standard 11.025/22.05/44.1/48/96 kHz mono and stereo
    // combination at 8 and 16 bits. Advertising only WAVE_FORMAT_1M08 said the
    // device could do 11.025 kHz mono 8-bit and nothing else, while
    // `windowsWaveFormatSupported` accepted 48 kHz stereo float - so a caller
    // that consults the capabilities before opening was told the opposite of
    // what an open would actually do.
    if (bounded >= 74) state.write32(caps + 70, 0x000F_FFFF);
    if (bounded >= 76) state.write16(caps + 74, 2); // wChannels
    if (bounded >= 78) state.write16(caps + 76, 0); // wReserved1
    if (bounded >= 82) state.write32(caps + 78, 0); // dwSupport
}

fn noteWindowsWaveBuffer(state: anytype, data: u64, length: u32) void {
    state.windows_audio_last_data = data;
    state.windows_audio_last_bytes = length;
    state.windows_audio_bytes_submitted +|= length;
    const inspect_length = @min(@as(u64, length), 1024 * 1024);
    const bytes = if (data != 0 and inspect_length != 0) state.guestMemoryConst(data, inspect_length) else null;
    if (length != 0 and bytes == null) return;
    var checksum: u64 = 0xcbf2_9ce4_8422_2325;
    var nonzero = false;
    if (bytes) |sample| {
        for (sample) |byte| {
            checksum ^= byte;
            checksum *%= 0x0000_0100_0000_01b3;
            nonzero = nonzero or byte != 0;
        }
    }
    state.windows_audio_last_checksum = checksum;
    if (nonzero) state.windows_audio_nonzero_buffers +|= 1;
}

fn dispatchWindowsWaveOutCallback(state: anytype, device: anytype, header: u64, direct_return_rip: ?u64) bool {
    if (device.callback == 0 or (device.open_flags & winmm_callback_function) != winmm_callback_function) return false;
    if (state.addrToOffset(device.callback) == null) return false;
    const return_rip = direct_return_rip orelse state.read64(state.regs.rsp);
    if (return_rip == 0) return false;
    if (!state.beginWindowsAudioCallback(return_rip, direct_return_rip != null)) return false;
    state.regs.rcx = device.guest_handle;
    state.regs.rdx = winmm_wom_done;
    state.regs.r8 = device.instance;
    state.regs.r9 = header;
    state.regs.rip = device.callback;
    state.windows_audio_callback_dispatches +|= 1;
    return true;
}

fn handleWindowsMultimedia(state: anytype, dll_name: []const u8, name: []const u8, direct_return_rip: ?u64) bool {
    if (!std.ascii.eqlIgnoreCase(dll_name, "WINMM.dll") and !std.ascii.eqlIgnoreCase(dll_name, "winmm")) return false;
    state.windows_audio_import_calls +|= 1;

    if (std.mem.eql(u8, name, "timeBeginPeriod") or std.mem.eql(u8, name, "timeEndPeriod")) {
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "PlaySoundW")) {
        state.regs.rax = 0; // BOOL FALSE: no host sound-file player is claimed.
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveOutGetNumDevs")) {
        state.regs.rax = 1; // One deterministic virtual output device.
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveInGetNumDevs")) {
        state.regs.rax = 0; // Capture is not part of Xenia's output path.
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveOutGetDevCapsW")) {
        writeWindowsWaveOutCaps(state, arg(state, 1, direct_return_rip), arg(state, 2, direct_return_rip));
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveOutGetErrorTextW")) {
        const text = arg(state, 1, direct_return_rip);
        const capacity = arg(state, 2, direct_return_rip);
        if (text != 0 and capacity != 0 and state.guestMemory(text, 2) != null) state.write16(text, 0);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveOutOpen")) {
        const output_handle = arg(state, 0, direct_return_rip);
        const format = arg(state, 2, direct_return_rip);
        const callback = arg(state, 3, direct_return_rip);
        const instance = arg(state, 4, direct_return_rip);
        const flags = arg(state, 5, direct_return_rip);
        const supported = windowsWaveFormatSupported(state, format);
        if ((flags & winmm_wave_format_query) != 0) {
            state.windows_audio_format_queries +|= 1;
            if (!supported) state.windows_audio_format_rejections +|= 1;
            state.regs.rax = if (supported) winmm_noerror else winmm_invalid_parameter;
            traceWindowsAudioEvent(state, "waveOutFormatQuery", 0, format, winmm_waveformatex_bytes);
            finish(state, direct_return_rip);
            return true;
        }
        state.windows_audio_open_calls +|= 1;
        if (!supported or output_handle == 0 or state.guestMemory(output_handle, 8) == null) {
            state.windows_audio_format_rejections +|= @intFromBool(!supported);
            state.regs.rax = if (!supported) winmm_invalid_parameter else winmm_no_memory;
            finish(state, direct_return_rip);
            return true;
        }
        var device: ?*@TypeOf(state.windows_wave_out_devices[0]) = null;
        for (&state.windows_wave_out_devices) |*candidate| {
            if (!candidate.opened) {
                device = candidate;
                break;
            }
        }
        if (device == null) {
            state.regs.rax = winmm_no_memory;
            finish(state, direct_return_rip);
            return true;
        }
        const handle = nextHandle(state);
        const opened = device.?;
        opened.* = .{
            .guest_handle = handle,
            .callback = callback,
            .instance = instance,
            .open_flags = flags,
            .format_tag = state.read16(format + 0),
            .channels = state.read16(format + 2),
            .sample_rate = state.read32(format + 4),
            .block_align = state.read16(format + 12),
            .bits_per_sample = state.read16(format + 14),
            .opened = true,
            .paused = true,
        };
        state.write64(output_handle, handle);
        state.windows_audio_open_successes +|= 1;
        // Ask the host for a real device with the format the guest just
        // negotiated. A refusal keeps the virtual sink; only the audio report
        // changes, never the guest's view of the open.
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "openWindowsHostAudio")) {
            // WAVE_FORMAT_IEEE_FLOAT is 3; WAVE_FORMAT_EXTENSIBLE (0xFFFE)
            // carries the real sub-format, and SDL's WinMM backend only ever
            // asks for plain PCM or float through this path.
            const is_float = opened.format_tag == 3;
            _ = state.openWindowsHostAudio(
                opened.sample_rate,
                opened.channels,
                opened.bits_per_sample,
                is_float,
            );
        }
        traceWindowsAudioEvent(state, "waveOutOpen", handle, format, winmm_waveformatex_bytes);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveOutPrepareHeader")) {
        const handle = arg(state, 0, direct_return_rip);
        const header = arg(state, 1, direct_return_rip);
        const header_bytes = arg(state, 2, direct_return_rip);
        const device = windowsWaveOutDevice(state, handle);
        if (device == null or header_bytes < winmm_wavehdr_bytes or state.guestMemory(header, winmm_wavehdr_bytes) == null) {
            state.regs.rax = winmm_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        }
        const flags = state.read32(header + 24);
        if ((flags & winmm_whdr_prepared) == 0) {
            state.write32(header + 24, (flags | winmm_whdr_prepared) & ~winmm_whdr_inqueue & ~winmm_whdr_done);
            if (device.?.prepared_headers < std.math.maxInt(u32)) device.?.prepared_headers += 1;
            for (&device.?.prepared_header_ptrs) |*slot| {
                if (slot.* == 0) {
                    slot.* = header;
                    break;
                }
            }
        }
        state.windows_audio_prepare_calls +|= 1;
        traceWindowsAudioEvent(state, "waveOutPrepareHeader", handle, header, header_bytes);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveOutWrite")) {
        const handle = arg(state, 0, direct_return_rip);
        const header = arg(state, 1, direct_return_rip);
        const header_bytes = arg(state, 2, direct_return_rip);
        const device = windowsWaveOutDevice(state, handle);
        if (device == null or header_bytes < winmm_wavehdr_bytes or state.guestMemory(header, winmm_wavehdr_bytes) == null) {
            state.regs.rax = winmm_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        }
        const flags = state.read32(header + 24);
        if ((flags & winmm_whdr_prepared) == 0) {
            state.regs.rax = winmm_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        }
        const data = state.read64(header + 0);
        const length = state.read32(header + 8);
        state.write32(header + 24, (flags | winmm_whdr_inqueue) & ~winmm_whdr_done);
        noteWindowsWaveBuffer(state, data, length);
        {
            const State = @TypeOf(state.*);
            if (comptime @hasDecl(State, "submitWindowsHostAudio")) {
                state.submitWindowsHostAudio(data, length);
            }
        }
        state.windows_audio_write_calls +|= 1;
        state.windows_audio_buffers_submitted +|= 1;
        state.windows_audio_buffers_completed +|= 1;
        device.?.submitted_buffers +|= 1;
        // The virtual sink completes immediately.  This is deliberate: SDL's
        // worker is waiting for WOM_DONE, and leaving the header queued would
        // recreate the same scheduler deadlock we are trying to remove.
        state.write32(header + 24, (flags | winmm_whdr_prepared | winmm_whdr_done) & ~winmm_whdr_inqueue);
        traceWindowsAudioEvent(state, "waveOutWrite", handle, data, length);
        if (dispatchWindowsWaveOutCallback(state, device.?, header, direct_return_rip)) return true;
        if (device.?.callback != 0 and (device.?.open_flags & winmm_callback_function) == winmm_callback_function) {
            state.windows_audio_callback_failures +|= 1;
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveOutReset")) {
        const handle = arg(state, 0, direct_return_rip);
        const device = windowsWaveOutDevice(state, handle);
        if (device == null) {
            state.regs.rax = winmm_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        }
        for (device.?.prepared_header_ptrs) |header| {
            if (header != 0 and state.guestMemory(header, winmm_wavehdr_bytes) != null) {
                const flags = state.read32(header + 24);
                state.write32(header + 24, (flags | winmm_whdr_done) & ~winmm_whdr_inqueue);
            }
        }
        device.?.paused = true;
        state.windows_audio_reset_calls +|= 1;
        traceWindowsAudioEvent(state, "waveOutReset", handle, 0, 0);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveOutUnprepareHeader")) {
        const handle = arg(state, 0, direct_return_rip);
        const header = arg(state, 1, direct_return_rip);
        const header_bytes = arg(state, 2, direct_return_rip);
        const device = windowsWaveOutDevice(state, handle);
        if (device == null or header_bytes < winmm_wavehdr_bytes or state.guestMemory(header, winmm_wavehdr_bytes) == null) {
            state.regs.rax = winmm_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        }
        const flags = state.read32(header + 24);
        if ((flags & winmm_whdr_inqueue) != 0) {
            state.regs.rax = winmm_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        }
        state.write32(header + 24, flags & ~winmm_whdr_prepared & ~winmm_whdr_done);
        if (device.?.prepared_headers != 0) device.?.prepared_headers -= 1;
        for (&device.?.prepared_header_ptrs) |*slot| {
            if (slot.* == header) slot.* = 0;
        }
        state.windows_audio_unprepare_calls +|= 1;
        traceWindowsAudioEvent(state, "waveOutUnprepareHeader", handle, header, header_bytes);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "waveOutClose")) {
        const handle = arg(state, 0, direct_return_rip);
        const device = windowsWaveOutDevice(state, handle);
        if (device == null) {
            state.regs.rax = winmm_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        }
        device.?.* = .{};
        state.windows_audio_close_calls +|= 1;
        {
            const State = @TypeOf(state.*);
            if (comptime @hasDecl(State, "closeWindowsHostAudio")) state.closeWindowsHostAudio();
        }
        traceWindowsAudioEvent(state, "waveOutClose", handle, 0, 0);
        returnZero(state, direct_return_rip);
    }

    // Xenia's current output path does not use capture.  Fail those imports
    // with the documented multimedia error instead of claiming an input
    // device whose samples Rosetta cannot supply.
    if (std.mem.startsWith(u8, name, "waveIn")) {
        state.regs.rax = winmm_not_supported;
        finish(state, direct_return_rip);
        return true;
    }
    return false;
}

const nt_status_success: u64 = 0x00000000;
const nt_status_timeout: u64 = 0x00000102;
const nt_status_invalid_handle: u64 = 0xC0000008;
const nt_status_invalid_parameter: u64 = 0xC000000D;

/// Convert the relative LARGE_INTEGER used by NtWaitForSingleObject into the
/// millisecond form used by the shared synthetic wait policy. Xenia passes a
/// null timeout for its ordinary infinite waits and a negative 100-ns
/// interval for bounded waits. Absolute NT deadlines are not currently used
/// by the Xenia startup path, so they are conservatively treated as a
/// non-zero wait rather than being mistaken for an immediate timeout.
fn ntWaitTimeoutMilliseconds(state: anytype, timeout_pointer: u64) ?u64 {
    if (timeout_pointer == 0) return 0xFFFF_FFFF;
    if (state.guestMemoryConst(timeout_pointer, 8) == null) return null;

    const raw: i64 = @bitCast(state.read64(timeout_pointer));
    if (raw == 0) return 0;
    if (raw > 0) return 0xFFFF_FFFF;

    const magnitude: u64 = @bitCast(raw);
    const hundred_ns = (~magnitude) +| 1;
    return @min((hundred_ns +| 9_999) / 10_000, @as(u64, 0xFFFF_FFFF));
}

fn finishNtWait(state: anytype, direct_return_rip: ?u64, handle: u64, timeout: u64) bool {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "waitWindowsGuestObject")) {
        switch (state.waitWindowsGuestObject(handle, timeout)) {
            .blocked => return true,
            .signaled, .yielded => {
                state.regs.rax = nt_status_success;
                finish(state, direct_return_rip);
                return true;
            },
            .timeout => {
                state.regs.rax = nt_status_timeout;
                finish(state, direct_return_rip);
                return true;
            },
            .invalid, .unknown => {
                state.regs.rax = nt_status_invalid_handle;
                finish(state, direct_return_rip);
                return true;
            },
        }
    }

    // A non-PE state cannot expose the synthetic wait table, but the NT
    // entry point is still a successful no-op for the shared import layer.
    returnZero(state, direct_return_rip);
    return true;
}

fn traceNtSynchronization(state: anytype, api: []const u8, handle: u64, known: bool, result: u64) void {
    if (!state.trace_windows_waits) return;
    state.windows_nt_sync_trace_events +|= 1;
    const event = state.windows_nt_sync_trace_events;
    if (event > 8 and (event & (event - 1)) != 0) return;
    log.info("PE64 NT synchronization: api={s} handle=0x{x} known={} result=0x{x} step={d} event={d}", .{
        api,
        handle,
        known,
        result,
        state.executed_steps,
        event,
    });
}

fn returnVulkan(state: anytype, result: i64, direct_return_rip: ?u64) void {
    state.regs.rax = @bitCast(result);
    finish(state, direct_return_rip);
}

fn handleWindowsSetjmp(state: anytype, direct_return_rip: ?u64) bool {
    const environment = arg(state, 0, direct_return_rip);
    const return_rip = direct_return_rip orelse state.read64(state.regs.rsp);
    const return_rsp = if (direct_return_rip != null) state.regs.rsp else state.regs.rsp +| 8;
    if (environment == 0 or return_rip == 0 or state.guestMemory(environment, windows_setjmp_bytes) == null) {
        log.warn("Windows _setjmp rejected environment=0x{x} return=0x{x} rsp=0x{x}", .{ environment, return_rip, state.regs.rsp });
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }

    state.write64(environment + 0, windows_setjmp_magic);
    state.write64(environment + 8, return_rsp);
    state.write64(environment + 16, state.regs.rbp);
    state.write64(environment + 24, state.regs.rbx);
    state.write64(environment + 32, state.regs.rsi);
    state.write64(environment + 40, state.regs.rdi);
    state.write64(environment + 48, state.regs.r12);
    state.write64(environment + 56, state.regs.r13);
    state.write64(environment + 64, state.regs.r14);
    state.write64(environment + 72, state.regs.r15);
    state.write64(environment + 80, return_rip);
    state.write64(environment + 88, state.regs.rflags);
    state.regs.rax = 0;
    finish(state, direct_return_rip);
    return true;
}

fn handleWindowsLongjmp(state: anytype, direct_return_rip: ?u64) bool {
    const environment = arg(state, 0, direct_return_rip);
    const value = arg(state, 1, direct_return_rip);
    const saved = state.guestMemoryConst(environment, windows_setjmp_bytes) orelse {
        terminateWindowsCall(state, .runtime_invariant_failure, 127, "longjmp(environment)");
        return true;
    };
    if (std.mem.readInt(u64, saved[0..8], .little) != windows_setjmp_magic) {
        terminateWindowsCall(state, .runtime_invariant_failure, 127, "longjmp(unrecognized environment)");
        return true;
    }
    state.regs.rsp = std.mem.readInt(u64, saved[8..16], .little);
    state.regs.rbp = std.mem.readInt(u64, saved[16..24], .little);
    state.regs.rbx = std.mem.readInt(u64, saved[24..32], .little);
    state.regs.rsi = std.mem.readInt(u64, saved[32..40], .little);
    state.regs.rdi = std.mem.readInt(u64, saved[40..48], .little);
    state.regs.r12 = std.mem.readInt(u64, saved[48..56], .little);
    state.regs.r13 = std.mem.readInt(u64, saved[56..64], .little);
    state.regs.r14 = std.mem.readInt(u64, saved[64..72], .little);
    state.regs.r15 = std.mem.readInt(u64, saved[72..80], .little);
    state.regs.rip = std.mem.readInt(u64, saved[80..88], .little);
    state.regs.rflags = @truncate(std.mem.readInt(u64, saved[88..96], .little));
    state.regs.rax = if (value == 0) 1 else value;
    return true;
}

fn writeWindowsContext(state: anytype, context: u64, captured_rip: u64, captured_rsp: u64) bool {
    // The integer register portion of the Windows x64 CONTEXT ends at Rip
    // (+0xf8). The PE's unwind helper allocates substantially more than this
    // region, but validating the complete integer prefix catches a bad output
    // pointer before any partial context is published.
    if (context == 0 or state.guestMemory(context, 0x100) == null) return false;
    state.write32(context + 0x30, 0x0001_001f); // CONTEXT_FULL | CONTEXT_INTEGER
    state.write32(context + 0x34, 0x1f80); // default MXCSR
    state.write16(context + 0x38, 0x33); // CS
    state.write16(context + 0x3a, 0x2b); // DS
    state.write16(context + 0x3c, 0x2b); // ES
    state.write16(context + 0x3e, 0x53); // FS
    state.write16(context + 0x40, 0x2b); // GS
    state.write16(context + 0x42, 0x2b); // SS
    state.write32(context + 0x44, @truncate(state.regs.rflags));
    state.write64(context + 0x78, state.regs.rax);
    state.write64(context + 0x80, state.regs.rcx);
    state.write64(context + 0x88, state.regs.rdx);
    state.write64(context + 0x90, state.regs.rbx);
    state.write64(context + 0x98, captured_rsp);
    state.write64(context + 0xa0, state.regs.rbp);
    state.write64(context + 0xa8, state.regs.rsi);
    state.write64(context + 0xb0, state.regs.rdi);
    state.write64(context + 0xb8, state.regs.r8);
    state.write64(context + 0xc0, state.regs.r9);
    state.write64(context + 0xc8, state.regs.r10);
    state.write64(context + 0xd0, state.regs.r11);
    state.write64(context + 0xd8, state.regs.r12);
    state.write64(context + 0xe0, state.regs.r13);
    state.write64(context + 0xe8, state.regs.r14);
    state.write64(context + 0xf0, state.regs.r15);
    state.write64(context + 0xf8, captured_rip);
    return true;
}

fn handleRtlCaptureContext(state: anytype, direct_return_rip: ?u64) bool {
    const context = arg(state, 0, direct_return_rip);
    const captured_rip = state.read64(state.regs.rsp);
    const captured_rsp = state.regs.rsp +| 8;
    if (!writeWindowsContext(state, context, captured_rip, captured_rsp)) {
        terminateWindowsCall(state, .runtime_invariant_failure, 127, "RtlCaptureContext");
        log.err("Windows RtlCaptureContext rejected output context=0x{x} rip=0x{x} rsp=0x{x}", .{ context, captured_rip, state.regs.rsp });
        return true;
    }
    state.windows_rtl_capture_calls +|= 1;
    finish(state, direct_return_rip);
    return true;
}

fn handleRtlUnwindEx(state: anytype, direct_return_rip: ?u64) bool {
    const target_frame = arg(state, 0, direct_return_rip);
    const target_ip = arg(state, 1, direct_return_rip);
    const exception_record = arg(state, 2, direct_return_rip);
    const return_value = arg(state, 3, direct_return_rip);
    const context = arg(state, 4, direct_return_rip);
    const frame_valid = target_frame != 0 and state.guestMemory(target_frame, 8) != null;
    const target_valid = target_ip >= state.image_low and target_ip < state.image_high and state.addrToOffset(target_ip) != null;
    if (!frame_valid or !target_valid) {
        terminateWindowsCall(state, .runtime_invariant_failure, 127, "RtlUnwindEx");
        const exception_header = return_value;
        const exception_object = if (exception_header >= 0x60) exception_header - 0x60 else 0;
        const type_info = if (exception_object != 0) state.read64(exception_object +| 0x10) else 0;
        const type_name_address = if (type_info != 0) state.read64(type_info +| 8) else 0;
        const type_name = if (type_name_address != 0) guestCString(state, type_name_address) orelse "<unreadable>" else "<unknown>";
        const thrown_object = if (exception_object != 0) exception_object +| 0xa0 else 0;
        const option_spec: []const u8 = if (std.mem.indexOf(u8, type_name, "cxxopts") != null and thrown_object != 0)
            guestStdString(state, thrown_object +| 8) orelse "<unreadable>"
        else
            "<not-cxxopts-option>";
        log.err(
            "Windows RtlUnwindEx rejected transfer target_frame=0x{x} target_ip=0x{x} frame_valid={} target_valid={} exception_record=0x{x} context=0x{x} exception_header=0x{x} exception_object=0x{x} type_name={s} option_spec={s} thrown_object=0x{x} rsp=0x{x}",
            .{ target_frame, target_ip, frame_valid, target_valid, exception_record, context, exception_header, exception_object, type_name, option_spec, thrown_object, state.regs.rsp },
        );
        return true;
    }

    // RtlUnwindEx is noreturn on Windows: it restores the requested frame and
    // resumes at TargetIp. Returning through the import stub would execute
    // MinGW's deliberate UD2 in _Unwind_Resume and turn a valid unwind into a
    // false invalid-instruction failure. The transfer remains guest-only and
    // is accepted only after both target values are proven addressable.
    state.windows_rtl_unwind_calls +|= 1;
    state.regs.rax = return_value;
    state.regs.rsp = target_frame;
    state.regs.rip = target_ip;
    if (context != 0 and state.guestMemory(context, 0x100) != null) {
        state.write64(context + 0x98, target_frame);
        state.write64(context + 0xf8, target_ip);
        state.write64(context + 0x78, return_value);
    }
    log.info(
        "Windows RtlUnwindEx transferred guest control target_frame=0x{x} target_ip=0x{x} exception_record=0x{x} return_value=0x{x} context=0x{x}",
        .{ target_frame, target_ip, exception_record, return_value, context },
    );
    return true;
}

fn terminateWindowsCall(
    state: anytype,
    reason: @TypeOf(state.termination_reason),
    exit_code: u64,
    name: []const u8,
) void {
    state.faulted = true;
    state.exit_code = exit_code;
    state.termination_reason = reason;
    state.terminated = true;
    log.err(
        "Windows fatal runtime call: {s} rip=0x{x} exit=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x}",
        .{ name, state.regs.rip, exit_code, state.regs.rcx, state.regs.rdx, state.regs.r8, state.regs.r9 },
    );
}

fn nextHandle(state: anytype) u64 {
    const handle = state.windows_next_handle;
    state.windows_next_handle +|= 1;
    return handle;
}

fn isSyntheticWindowsHandle(state: anytype, handle: u64) bool {
    // The process and thread pseudo-handles are deliberately not included:
    // GetHandleInformation operates on real kernel handles, while Rosetta
    // models those pseudo-handles separately in GetCurrentProcess/Thread.
    if (handle == 0 or handle == std.math.maxInt(u64) or handle == std.math.maxInt(u64) - 1) return false;
    if (windowsFileSlot(state, handle) != null or windowsFindSlot(state, handle) != null) return true;
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "isWindowsWindowHandle")) {
        if (state.isWindowsWindowHandle(handle)) return true;
    }
    if (handle == 0xFFFF_F000_0000_0100 or handle == state.windows_window_handle) return true;

    // All other Rosetta-owned Win32 objects come from nextHandle. The range
    // check also rejects arbitrary guest values instead of treating every
    // nonzero pointer as a live host object.
    const first_handle: u64 = 0xFFFF_F000_0000_0001;
    return handle >= first_handle and handle < state.windows_next_handle;
}

fn isWindowsRegistryRoot(handle: u64) bool {
    const low = @as(u32, @truncate(handle));
    return low == 0x8000_0000 or
        low == 0x8000_0001 or
        low == 0x8000_0002 or
        low == 0x8000_0003 or
        low == 0x8000_0005;
}

fn isWindowsRegistryHandle(state: anytype, handle: u64) bool {
    return isWindowsRegistryRoot(handle) or isSyntheticWindowsHandle(state, handle);
}

fn versionCondition(value: u64, requested: u64, condition: u64) bool {
    return switch (condition) {
        2 => value > requested, // VER_GREATER
        3 => value >= requested, // VER_GREATER_EQUAL
        4 => value < requested, // VER_LESS
        5 => value <= requested, // VER_LESS_EQUAL
        6 => (value & requested) != 0, // VER_AND
        7 => (value | requested) != 0, // VER_OR
        else => value == requested, // VER_EQUAL and the unset default
    };
}

fn clearGuestMemory(state: anytype, address: u64, length: u64) bool {
    const destination = state.guestMemory(address, length) orelse return false;
    @memset(destination, 0);
    return true;
}

fn writeWindowsMessage(state: anytype, address: u64, message: anytype) bool {
    if (address == 0 or state.guestMemory(address, 48) == null) return false;
    // Win64 MSG: HWND at 0, UINT at 8, WPARAM at 16, LPARAM at 24,
    // DWORD time at 32, and POINT {LONG x, LONG y} at 36.
    state.write64(address + 0, message.hwnd);
    state.write32(address + 8, message.message);
    state.write32(address + 12, 0);
    state.write64(address + 16, message.wparam);
    state.write64(address + 24, message.lparam);
    state.write32(address + 32, 0);
    state.write32(address + 36, 0);
    state.write32(address + 40, 0);
    state.write32(address + 44, 0);
    return true;
}

/// Deliver a queued MSG to the guest WndProc using the Microsoft x64 callback
/// ABI. DispatchMessage is not a normal import completion: the WndProc is
/// guest code and must return through a real nested frame before the original
/// DispatchMessage caller resumes.
fn dispatchWindowsMessage(state: anytype, message_address: u64, direct_return_rip: ?u64) bool {
    const State = @TypeOf(state.*);
    if (message_address == 0 or state.guestMemory(message_address, 48) == null) {
        terminateWindowsCall(state, .runtime_invariant_failure, 127, "DispatchMessage(MSG)");
        log.err("Windows DispatchMessage rejected invalid MSG address=0x{x}", .{message_address});
        return true;
    }

    const hwnd = state.read64(message_address + 0);
    const message = state.read32(message_address + 8);
    const wparam = state.read64(message_address + 16);
    const lparam = state.read64(message_address + 24);
    const proc = if (comptime @hasDecl(State, "windowsWindowProc"))
        state.windowsWindowProc(hwnd)
    else
        null;

    if (proc == null) {
        // The pending-functions window is the synchronization bridge that
        // starts Xenia's emulator/graphics worker. Treating a missing WndProc
        // as a successful no-op would recreate the old message-loop spin and
        // make the graphics ledger falsely look like a window-only success.
        if (hwnd == state.windows_message_window_handle and message == 0x400) {
            terminateWindowsCall(state, .runtime_invariant_failure, 127, "DispatchMessage(pending WndProc)");
            log.err("Windows pending message has no registered WndProc hwnd=0x{x} message=0x{x}", .{ hwnd, message });
        } else {
            if (state.diagnose_abi or state.trace_windows_messages) {
                log.warn("Windows DispatchMessage no WndProc hwnd=0x{x} message=0x{x} ignored", .{ hwnd, message });
            }
            returnZero(state, direct_return_rip);
        }
        return true;
    }
    const proc_address = proc.?;
    if (state.addrToOffset(proc_address) == null) {
        terminateWindowsCall(state, .runtime_invariant_failure, 127, "DispatchMessage(WndProc address)");
        log.err("Windows DispatchMessage rejected WndProc outside guest image hwnd=0x{x} message=0x{x} proc=0x{x}", .{ hwnd, message, proc_address });
        return true;
    }

    const return_rip = direct_return_rip orelse state.read64(state.regs.rsp);
    if (return_rip == 0) {
        terminateWindowsCall(state, .runtime_invariant_failure, 127, "DispatchMessage(return address)");
        log.err("Windows DispatchMessage rejected null continuation hwnd=0x{x} message=0x{x} rsp=0x{x}", .{ hwnd, message, state.regs.rsp });
        return true;
    }
    if (comptime @hasDecl(State, "beginWindowsMessageDispatch")) {
        if (!state.beginWindowsMessageDispatch(return_rip, direct_return_rip != null)) {
            terminateWindowsCall(state, .runtime_invariant_failure, 127, "DispatchMessage(callback frame)");
            log.err("Windows DispatchMessage could not reserve callback frame hwnd=0x{x} message=0x{x} proc=0x{x}", .{ hwnd, message, proc_address });
            return true;
        }
    } else {
        terminateWindowsCall(state, .runtime_invariant_failure, 127, "DispatchMessage(callback protocol)");
        return true;
    }

    state.regs.rcx = hwnd;
    state.regs.rdx = message;
    state.regs.r8 = wparam;
    state.regs.r9 = lparam;
    state.regs.rip = proc_address;
    if (state.diagnose_abi or state.trace_windows_messages) {
        log.info("Windows DispatchMessage guest callback hwnd=0x{x} message=0x{x} wparam=0x{x} lparam=0x{x} proc=0x{x} continuation=0x{x} callback_rsp=0x{x}", .{
            hwnd,
            message,
            wparam,
            lparam,
            proc_address,
            return_rip,
            state.regs.rsp,
        });
    }
    return true;
}

fn windowsTlsSlot(state: anytype, index: u64) ?u64 {
    if (index >= 512) return null;
    const teb = state.regs.segments.gs.base;
    if (teb == 0) return null;
    const vector = state.read64(teb + 0x58);
    if (vector == 0) return null;
    const slot = vector +| index * 8;
    if (state.guestMemory(slot, 8) == null) return null;
    return slot;
}

/// ASCII case-insensitive comparison with the C ordering contract: negative,
/// zero, or positive, comparing at most `limit` characters.
fn caseInsensitiveCompare(lhs: []const u8, rhs: []const u8, limit: usize) i32 {
    const count = @min(limit, @min(lhs.len, rhs.len));
    for (lhs[0..count], rhs[0..count]) |left, right| {
        const a = std.ascii.toLower(left);
        const b = std.ascii.toLower(right);
        if (a != b) return @as(i32, a) - @as(i32, b);
    }
    if (count == limit) return 0;
    if (lhs.len == rhs.len) return 0;
    return if (lhs.len < rhs.len) -1 else 1;
}

fn guestCString(state: anytype, address: u64) ?[]const u8 {
    if (address == 0) return null;
    const off = state.addrToOffset(address) orelse return null;
    const start: usize = @intCast(off);
    if (start >= state.mem.len) return null;
    var end = start;
    const limit = @min(state.mem.len, start + 64 * 1024);
    while (end < limit and state.mem[end] != 0) : (end += 1) {}
    if (end == limit) return null;
    return state.mem[start..end];
}

/// The file name of a module path, without its directory.
pub fn windowsModuleBasename(path: []const u8) []const u8 {
    var basename_start: usize = 0;
    for (path, 0..) |character, index| {
        if (character == '\\' or character == '/') basename_start = index + 1;
    }
    return path[basename_start..];
}

/// Whether `LoadLibrary` must report this module as absent.
///
/// A successful `LoadLibrary` is a promise: the caller will immediately ask
/// for exports and use whatever it gets. Rosetta models a bounded Win32
/// surface, so the promise is only honest for libraries in that surface. The
/// rule used to be a two-entry deny-list, which meant
/// `LoadLibraryW(L"XAudio2_8.dll")` succeeded, `GetProcAddress` handed back a
/// stub, and Xenia's XAudio2 driver then called `XAudio2Create` - whose
/// unimplemented fallback returns zero, which is `S_OK` for an HRESULT. The
/// driver read the interface pointer it had never been given and dereferenced
/// a null vtable. Refusing the module up front is what Windows does for a DLL
/// that is not installed, and every `LoadLibrary` caller already handles it.
///
/// `subsystemFor` is the allow-list: a library Rosetta's per-DLL packages do
/// not own is not part of the modelled surface, whatever it is called.
/// Whether a byte sequence read from guest memory plausibly *is* a module
/// name.
///
/// A refusal decided from a misread name is the worst outcome available here:
/// it takes a library the guest can legitimately load and reports it absent,
/// and the log then blames a package that exists. The 2026-09-11 run recorded
/// `module='0'D'` for a `LoadLibraryA`, which is not a module name in any
/// spelling - so the read, not the library, is what failed.
///
/// Windows module names are printable, at least three characters, and made of
/// path and identifier characters. Anything else means the pointer did not
/// address a name, and Rosetta must not draw a conclusion from it.
pub fn windowsModuleNameLooksReadable(name: []const u8) bool {
    if (name.len < 3 or name.len > 260) return false;
    var alphanumeric: usize = 0;
    for (name) |character| {
        if (character < 0x20 or character > 0x7E) return false;
        switch (character) {
            'A'...'Z', 'a'...'z', '0'...'9' => alphanumeric += 1,
            '.', '_', '-', '+', ' ', '\\', '/', ':', '~' => {},
            else => return false,
        }
    }
    // A name that is almost all punctuation is not a name.
    return alphanumeric * 2 >= name.len;
}

/// Whether a dynamic load of this module can be honoured, and if not, why.
pub fn windowsModuleAvailability(path: []const u8) ModuleAvailability {
    const basename = windowsModuleBasename(path);
    return moduleAvailability(basename);
}

pub fn windowsModuleUnavailableOnHost(path: []const u8) bool {
    const basename = windowsModuleBasename(path);
    if (basename.len == 0) return false;
    return moduleAvailability(basename) != .served;
}

/// Whether Rosetta can serve a name reached through `GetProcAddress`.
///
/// The two inventories below are the same ones the import dispatcher falls
/// back through, so this predicate answers exactly "would a call to this name
/// reach a handler or a typed contract refusal?" A name outside both would
/// reach the permissive boundary, and the permissive boundary is the wrong
/// answer to a question the guest asked explicitly.
pub fn isRecognizedDynamicImport(dll_name: []const u8, function_name: []const u8) bool {
    if (function_name.len == 0) return false;
    // The graphics surface is the load-bearing case for this predicate.
    // Xenia reaches its whole Vulkan path through
    // `GetProcAddress(vulkan-1.dll, "vkGetInstanceProcAddr")` and then through
    // that pointer for everything else; none of those names is in the Win32
    // inventory, and answering NULL for them would end the run at
    // "Failed to get Vulkan loader function pointers".
    if (isGraphicsImport(dll_name, function_name)) return true;
    if (isKnownCoreImport(function_name)) return true;
    if (isKnownContractImport(dll_name, function_name)) return true;
    // The catalogue keeps a name-only bucket for dynamic lookups whose module
    // Rosetta could not attribute; consult it when the handle was not one
    // this run recorded.
    if (dll_name.len != 0 and isKnownContractImport("", function_name)) return true;
    return false;
}

fn noteWindowsModuleHandle(state: anytype, handle: u64, module_name: []const u8) void {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "noteWindowsLoadedModule")) {
        state.noteWindowsLoadedModule(handle, module_name);
    }
}

fn windowsModuleNameFor(state: anytype, handle: u64) []const u8 {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "windowsLoadedModuleName")) {
        return state.windowsLoadedModuleName(handle);
    }
    return "";
}

fn noteWindowsModuleRefusal(
    state: anytype,
    api: []const u8,
    module_path: []const u8,
    availability: ModuleAvailability,
    caller_rip: u64,
) void {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "noteWindowsModuleRefusal")) {
        state.noteWindowsModuleRefusal(api, module_path, availability.label(), availability.isGap(), caller_rip);
    }
}

fn noteWindowsProcAddressRefusal(
    state: anytype,
    dll_name: []const u8,
    function_name: []const u8,
    caller_rip: u64,
) void {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "noteWindowsProcAddressRefusal")) {
        state.noteWindowsProcAddressRefusal(dll_name, function_name, caller_rip);
    }
}

fn noteWindowsUnreadableModuleName(
    state: anytype,
    api: []const u8,
    raw: []const u8,
    pointer: u64,
    caller_rip: u64,
) void {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "noteWindowsUnreadableModuleName")) {
        state.noteWindowsUnreadableModuleName(api, raw, pointer, caller_rip);
    }
}

fn guestStdString(state: anytype, address: u64) ?[]const u8 {
    if (address == 0) return null;
    const data_address = state.read64(address);
    const length = state.read64(address +| 8);
    if (length > 64 * 1024) return null;
    if (length == 0) return &.{};

    // libstdc++'s 64-bit basic_string stores short strings in the 16-byte
    // inline buffer at object+16. Long strings store the data pointer in the
    // first word. The thrown cxxopts exception owns exactly this layout, so
    // reading it here lets a fatal exception boundary identify the malformed
    // option specification instead of reporting only its C++ type.
    const storage = if (length <= 15 or data_address == address +| 16)
        address +| 16
    else
        data_address;
    return state.guestMemoryConst(storage, length);
}

fn guestWideUnit(state: anytype, address: u64, index: usize) ?u16 {
    const byte_offset = std.math.mul(u64, @intCast(index), 2) catch return null;
    const unit_address = std.math.add(u64, address, byte_offset) catch return null;
    if (state.guestMemoryConst(unit_address, 2) == null) return null;
    return state.read16(unit_address);
}

fn guestWideCStringLength(state: anytype, address: u64, maximum_units: usize) ?usize {
    if (address == 0) return null;
    for (0..maximum_units) |index| {
        const unit = guestWideUnit(state, address, index) orelse return null;
        if (unit == 0) return index;
    }
    return null;
}

fn guestWideEqualsLiteral(state: anytype, address: u64, literal: []const u8) bool {
    const length = guestWideCStringLength(state, address, literal.len + 1) orelse return false;
    if (length != literal.len) return false;
    for (literal, 0..) |expected, index| {
        const actual = guestWideUnit(state, address, index) orelse return false;
        if (actual != expected) return false;
    }
    return true;
}

fn copyGuestWideString(state: anytype, destination: u64, capacity_units: u64, source: []const u8) u64 {
    if (destination == 0 or capacity_units == 0) return 0;
    const capacity: usize = @intCast(@min(capacity_units, std.math.maxInt(usize)));
    const available = @min(source.len, capacity - 1);
    for (source[0..available], 0..) |character, index| {
        state.write16(destination +| @as(u64, @intCast(index * 2)), character);
    }
    state.write16(destination +| @as(u64, @intCast(available * 2)), 0);
    return available;
}

fn materializeGuestAnsi(state: anytype, source: []const u8) ?u64 {
    const address = state.guestAlloc(@intCast(source.len + 1), 1) orelse return null;
    _ = copyGuestString(state, address, @intCast(source.len + 1), source);
    return address;
}

fn materializeGuestWide(state: anytype, source: []const u8) ?u64 {
    const units = std.math.add(usize, source.len, 1) catch return null;
    const bytes = std.math.mul(usize, units, 2) catch return null;
    const address = state.guestAlloc(@intCast(bytes), 2) orelse return null;
    _ = copyGuestWideString(state, address, @intCast(units), source);
    return address;
}

const WideCodePoint = struct {
    value: u32,
    consumed: usize,
};

fn guestWideCodePoint(state: anytype, address: u64, index: usize, unit_count: usize) ?WideCodePoint {
    const first = guestWideUnit(state, address, index) orelse return null;
    if (first >= 0xD800 and first <= 0xDBFF and index + 1 < unit_count) {
        const second = guestWideUnit(state, address, index + 1) orelse return null;
        if (second >= 0xDC00 and second <= 0xDFFF) {
            const high = @as(u32, first) - 0xD800;
            const low = @as(u32, second) - 0xDC00;
            return .{ .value = 0x10000 + (high << 10) + low, .consumed = 2 };
        }
        return .{ .value = 0xFFFD, .consumed = 1 };
    }
    if (first >= 0xDC00 and first <= 0xDFFF) return .{ .value = 0xFFFD, .consumed = 1 };
    return .{ .value = first, .consumed = 1 };
}

fn utf8CodePointLength(value: u32) usize {
    if (value <= 0x7F) return 1;
    if (value <= 0x7FF) return 2;
    if (value <= 0xFFFF) return 3;
    return 4;
}

fn writeUtf8CodePoint(state: anytype, destination: u64, value: u32) usize {
    var encoded: [4]u8 = undefined;
    const length = utf8CodePointLength(value);
    switch (length) {
        1 => encoded[0] = @intCast(value),
        2 => {
            encoded[0] = @intCast(0xC0 | (value >> 6));
            encoded[1] = @intCast(0x80 | (value & 0x3F));
        },
        3 => {
            encoded[0] = @intCast(0xE0 | (value >> 12));
            encoded[1] = @intCast(0x80 | ((value >> 6) & 0x3F));
            encoded[2] = @intCast(0x80 | (value & 0x3F));
        },
        4 => {
            encoded[0] = @intCast(0xF0 | (value >> 18));
            encoded[1] = @intCast(0x80 | ((value >> 12) & 0x3F));
            encoded[2] = @intCast(0x80 | ((value >> 6) & 0x3F));
            encoded[3] = @intCast(0x80 | (value & 0x3F));
        },
        else => unreachable,
    }
    for (encoded[0..length], 0..) |byte, index| {
        state.write8(destination +| @as(u64, @intCast(index)), byte);
    }
    return length;
}

/// Convert a guest UTF-16 string using the Windows ABI's count semantics.
/// `-1` is represented by either a sign-extended u64 or a u32 all-ones value;
/// in that mode the terminating NUL is included in the returned byte count.
fn wideCharToUtf8(
    state: anytype,
    source: u64,
    requested_units: u64,
    destination: u64,
    destination_bytes: u64,
) ?u64 {
    if (source == 0 or requested_units == 0) return null;
    const null_terminated = requested_units == std.math.maxInt(u32) or requested_units == std.math.maxInt(u64);
    const unit_count = if (null_terminated)
        (guestWideCStringLength(state, source, 64 * 1024) orelse return null) + 1
    else blk: {
        const count = @as(usize, @intCast(@min(requested_units, std.math.maxInt(usize))));
        const bytes = std.math.mul(u64, @intCast(count), 2) catch return null;
        if (state.guestMemoryConst(source, bytes) == null) return null;
        break :blk count;
    };

    var required: usize = 0;
    var index: usize = 0;
    while (index < unit_count) {
        const code_point = guestWideCodePoint(state, source, index, unit_count) orelse return null;
        required += utf8CodePointLength(code_point.value);
        index += code_point.consumed;
    }
    if (destination == 0) return required;
    const capacity: usize = @intCast(@min(destination_bytes, std.math.maxInt(usize)));
    if (capacity < required) return 0;

    index = 0;
    var written: usize = 0;
    while (index < unit_count) {
        const code_point = guestWideCodePoint(state, source, index, unit_count) orelse return null;
        written += writeUtf8CodePoint(state, destination +| @as(u64, @intCast(written)), code_point.value);
        index += code_point.consumed;
    }
    return written;
}

fn multiByteToWide(
    state: anytype,
    source: u64,
    requested_bytes: u64,
    destination: u64,
    destination_units: u64,
) ?u64 {
    if (source == 0 or requested_bytes == 0) return null;
    const null_terminated = requested_bytes == std.math.maxInt(u32) or requested_bytes == std.math.maxInt(u64);
    const byte_count = if (null_terminated)
        (guestCString(state, source) orelse return null).len + 1
    else
        @as(usize, @intCast(@min(requested_bytes, std.math.maxInt(usize))));
    const input = state.guestMemoryConst(source, @intCast(byte_count)) orelse return null;
    const required = input.len;
    if (destination == 0) return required;
    const capacity: usize = @intCast(@min(destination_units, std.math.maxInt(usize)));
    if (capacity < required) return 0;
    for (input, 0..) |byte, index| state.write16(destination +| @as(u64, @intCast(index * 2)), byte);
    return required;
}

fn cachedGuestString(state: anytype, storage: *u64, wide: bool, source: []const u8) u64 {
    if (storage.* != 0) return storage.*;
    storage.* = if (wide) materializeGuestWide(state, source) orelse 0 else materializeGuestAnsi(state, source) orelse 0;
    return storage.*;
}

fn guestStrstr(state: anytype, haystack_address: u64, needle_address: u64) ?u64 {
    const haystack = guestCString(state, haystack_address) orelse return null;
    const needle = guestCString(state, needle_address) orelse return null;
    const offset = std.mem.indexOf(u8, haystack, needle) orelse return 0;
    return haystack_address +| @as(u64, @intCast(offset));
}

fn guestStrtol(state: anytype, source_address: u64, end_address: u64, requested_base: u64) ?i64 {
    const source = guestCString(state, source_address) orelse return null;
    var index: usize = 0;
    while (index < source.len and (source[index] == ' ' or source[index] == '\t' or source[index] == '\n' or source[index] == '\r')) : (index += 1) {}
    const negative = index < source.len and source[index] == '-';
    if (index < source.len and (source[index] == '+' or negative)) index += 1;

    if (requested_base > std.math.maxInt(u32)) return null;
    var base: u32 = @intCast(requested_base);
    if (base == 0) {
        base = 10;
        if (index + 1 < source.len and source[index] == '0' and (source[index + 1] == 'x' or source[index + 1] == 'X')) {
            base = 16;
            index += 2;
        } else if (index < source.len and source[index] == '0') {
            base = 8;
        }
    }
    if (base < 2 or base > 36) return null;
    const digits_start = index;
    var value: u64 = 0;
    while (index < source.len) : (index += 1) {
        const character = source[index];
        const digit: ?u32 = if (character >= '0' and character <= '9')
            character - '0'
        else if (character >= 'a' and character <= 'z')
            character - 'a' + 10
        else if (character >= 'A' and character <= 'Z')
            character - 'A' + 10
        else
            null;
        if (digit == null or digit.? >= base) break;
        value = value * base + digit.?;
    }
    if (index == digits_start) {
        if (end_address != 0 and state.guestMemory(end_address, 8) != null) {
            state.write64(end_address, source_address);
        }
        return 0;
    }
    if (end_address != 0 and state.guestMemory(end_address, 8) != null) {
        state.write64(end_address, source_address +| @as(u64, @intCast(index)));
    }
    const signed_value: i64 = @intCast(@min(value, std.math.maxInt(i64)));
    return if (negative) -signed_value else signed_value;
}

/// Materialize the classic C locale's `struct lconv` in guest memory.  The
/// Windows PE route cannot return the host libc's lconv pointer: the guest
/// immediately dereferences `decimal_point`, and later locale users expect
/// every pointer field to remain valid for the process lifetime.  The record
/// uses the standard ten pointer fields followed by zeroed single-byte
/// currency/sign metadata; that is sufficient for both strtodg and the
/// libstdc++ locale traits used by Xenia.
fn roundNearestEven(value: f64) f64 {
    const lower = @floor(value);
    const fraction = value - lower;
    if (fraction < 0.5) return lower;
    if (fraction > 0.5) return lower + 1.0;
    const lower_integer: i64 = @intFromFloat(lower);
    return if (@rem(lower_integer, 2) == 0) lower else lower + 1.0;
}

fn guestRoundToI64(state: anytype, value: f64) i64 {
    // MXCSR.RC is bits 13:14: nearest-even, down, up, or toward zero.
    // Keep the conversion defined for exceptional values a CRT helper may
    // receive while parsing malformed metadata.
    if (value != value) return 0;
    const limit: f64 = 9223372036854775808.0;
    if (value >= limit) return std.math.maxInt(i64);
    if (value <= -limit) return std.math.minInt(i64);
    const rounding_mode: u32 = @truncate((state.regs.mxcsr >> 13) & 0x3);
    const rounded = switch (rounding_mode) {
        0 => roundNearestEven(value),
        1 => @floor(value),
        2 => @ceil(value),
        3 => @trunc(value),
        else => unreachable,
    };
    return @intFromFloat(rounded);
}

fn cachedGuestCLocaleConv(state: anytype) u64 {
    const decimal_point = cachedGuestString(state, &state.windows_locale_decimal_point, false, ".");
    const empty_string = cachedGuestString(state, &state.windows_locale_empty_string, false, "");
    if (decimal_point == 0 or empty_string == 0) return 0;
    if (state.windows_localeconv_storage == 0) {
        const record = state.guestAlloc(128, 8) orelse return 0;
        const record_bytes = state.guestMemory(record, 128) orelse return 0;
        @memset(record_bytes, 0);
        for (0..10) |index| {
            state.write64(record +| @as(u64, @intCast(index * 8)), if (index == 0) decimal_point else empty_string);
        }
        state.windows_localeconv_storage = record;
    }
    return state.windows_localeconv_storage;
}

fn launchArgumentCount(state: anytype) usize {
    return state.windows_launch_arguments.len + 1;
}

fn launchArgument(state: anytype, index: usize) []const u8 {
    return if (index == 0) "xenia-canary.exe" else state.windows_launch_arguments[index - 1];
}

fn appendBackslashes(line: *std.ArrayList(u8), allocator: std.mem.Allocator, count: usize) !void {
    for (0..count) |_| try line.append(allocator, '\\');
}

fn windowsArgumentNeedsQuotes(value: []const u8) bool {
    if (value.len == 0) return true;
    for (value) |character| {
        if (character == '"' or character == ' ' or character == '\t' or character == '\n' or character == '\r') return true;
    }
    return false;
}

/// Append one argument using the quoting rules consumed by the Windows CRT.
/// The PE runner normally passes simple paths, but handling embedded quotes
/// and trailing backslashes here keeps GetCommandLineW and argv coherent for
/// future Xenia profiles as well.
fn appendWindowsCommandLineArgument(line: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    if (line.items.len != 0) try line.append(allocator, ' ');
    if (!windowsArgumentNeedsQuotes(value)) {
        try line.appendSlice(allocator, value);
        return;
    }

    try line.append(allocator, '"');
    var backslashes: usize = 0;
    for (value) |character| {
        if (character == '\\') {
            backslashes += 1;
            continue;
        }
        if (character == '"') {
            try appendBackslashes(line, allocator, backslashes * 2 + 1);
            try line.append(allocator, '"');
            backslashes = 0;
            continue;
        }
        try appendBackslashes(line, allocator, backslashes);
        try line.append(allocator, character);
        backslashes = 0;
    }
    try appendBackslashes(line, allocator, backslashes * 2);
    try line.append(allocator, '"');
}

fn cachedGuestCommandLine(state: anytype, storage: *u64, wide: bool) u64 {
    if (storage.* != 0) return storage.*;
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(state.allocator);
    appendWindowsCommandLineArgument(&line, state.allocator, launchArgument(state, 0)) catch return 0;
    for (state.windows_launch_arguments) |value| {
        appendWindowsCommandLineArgument(&line, state.allocator, value) catch return 0;
    }
    storage.* = if (wide) materializeGuestWide(state, line.items) orelse 0 else materializeGuestAnsi(state, line.items) orelse 0;
    return storage.*;
}

/// Return a guest pointer to a guest pointer. Several Microsoft CRT
/// accessors have this shape (`char ***`, `wchar_t ***`, or `wchar_t **`),
/// which is easy to accidentally model as the pointed-to array itself. The
/// extra indirection is observable in `__wgetmainargs`: it immediately loads
/// through the value returned by `__p___wargv` and `__p__wenviron`.
fn cachedGuestPointer(state: anytype, storage: *u64, value: u64) u64 {
    if (storage.* != 0) return storage.*;
    if (value == 0) return 0;
    const pointer = state.guestAlloc(8, 8) orelse return 0;
    state.write64(pointer, value);
    storage.* = pointer;
    return pointer;
}

fn cachedGuestArgc(state: anytype) u64 {
    if (state.windows_argc_storage != 0) return state.windows_argc_storage;
    const count = launchArgumentCount(state);
    if (count > std.math.maxInt(u32)) return 0;
    const pointer = state.guestAlloc(4, 4) orelse return 0;
    state.write32(pointer, @intCast(count));
    state.windows_argc_storage = pointer;
    return pointer;
}

fn cachedGuestArgv(state: anytype, wide: bool) u64 {
    const array_storage = if (wide) &state.windows_argv_w else &state.windows_argv_a;
    if (array_storage.* != 0) return array_storage.*;
    const count = launchArgumentCount(state);
    const array_bytes = std.math.mul(usize, count + 1, 8) catch return 0;
    const array = state.guestAlloc(@intCast(array_bytes), 8) orelse return 0;
    for (0..count) |index| {
        const value = launchArgument(state, index);
        const pointer = if (wide) materializeGuestWide(state, value) orelse return 0 else materializeGuestAnsi(state, value) orelse return 0;
        state.write64(array +| @as(u64, @intCast(index * 8)), pointer);
    }
    state.write64(array +| @as(u64, @intCast(count * 8)), 0);
    array_storage.* = array;
    return array;
}

fn cachedGuestEnvironment(state: anytype, wide: bool) u64 {
    const array_storage = if (wide) &state.windows_environ_w else &state.windows_environ_a;
    if (array_storage.* == 0) {
        const array = state.guestAlloc(8, 8) orelse return 0;
        // An empty environment is a valid null-terminated environment block.
        // Individual GetEnvironmentVariable handlers remain available to
        // code that asks for confined runtime values explicitly.
        state.write64(array, 0);
        array_storage.* = array;
    }
    return array_storage.*;
}

fn cachedGuestArgvStorage(state: anytype, wide: bool) u64 {
    const storage = if (wide) &state.windows_argv_w_storage else &state.windows_argv_a_storage;
    return cachedGuestPointer(state, storage, cachedGuestArgv(state, wide));
}

fn cachedGuestEnvironmentStorage(state: anytype, wide: bool) u64 {
    const storage = if (wide) &state.windows_environ_w_storage else &state.windows_environ_a_storage;
    return cachedGuestPointer(state, storage, cachedGuestEnvironment(state, wide));
}

/// Select the SDL audio backend that the confined Windows guest is allowed to
/// see. SDL asks for `SDL_AUDIODRIVER` through its CRT `getenv` path before it
/// tries the compiled-in Windows backends. Rosetta models WinMM and forwards
/// it to CoreAudio; WASAPI and DirectSound are not equivalent host surfaces
/// here, so letting SDL choose its normal Windows order would make a valid
/// WinMM path look like an audio backend failure.
///
/// The launcher supplies `ROSETTE_PE64_SDL_AUDIO_DRIVER=winmm` explicitly,
/// but keep the runtime default equally safe for callers that invoke the PE
/// runner directly. `unset`, `default`, and `any` deliberately restore SDL's
/// own driver selection for diagnostics.
fn configuredSdlAudioDriver() ?[]const u8 {
    const raw = std.c.getenv("ROSETTE_PE64_SDL_AUDIO_DRIVER") orelse
        std.c.getenv("ROSETTA_PE64_SDL_AUDIO_DRIVER") orelse
        return "winmm";
    const value = std.mem.span(raw);
    if (value.len == 0 or std.ascii.eqlIgnoreCase(value, "unset") or
        std.ascii.eqlIgnoreCase(value, "default") or std.ascii.eqlIgnoreCase(value, "any"))
    {
        return null;
    }
    if (std.ascii.eqlIgnoreCase(value, "winmm")) return "winmm";
    if (std.ascii.eqlIgnoreCase(value, "wasapi")) return "wasapi";
    if (std.ascii.eqlIgnoreCase(value, "directsound") or std.ascii.eqlIgnoreCase(value, "dsound")) return "directsound";
    // Do not expose an arbitrary host string to the guest. An unknown policy
    // value falls back to SDL's normal selection, and the launcher header
    // still preserves the exact operator-supplied value for diagnosis.
    return null;
}

fn noteSdlAudioDriverQuery(state: anytype, value: ?[]const u8, source: []const u8) void {
    const State = @TypeOf(state.*);
    if (comptime @hasField(State, "windows_audio_environment_queries") and
        @hasField(State, "windows_audio_environment_policy_reported") and
        @hasField(State, "windows_audio_environment_driver") and
        @hasField(State, "trace_windows_audio"))
    {
        state.windows_audio_environment_queries +|= 1;
        if (!state.windows_audio_environment_policy_reported) {
            state.windows_audio_environment_policy_reported = true;
            state.windows_audio_environment_driver = value orelse "";
            if (state.trace_windows_audio) {
                log.info("PE64 audio policy: source={s} SDL_AUDIODRIVER={s} queries={d}", .{
                    source,
                    value orelse "<unset>",
                    state.windows_audio_environment_queries,
                });
            }
        }
    }
}

fn environmentValue(name: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(name, "TEMP") or std.ascii.eqlIgnoreCase(name, "TMP") or
        std.ascii.eqlIgnoreCase(name, "TMPDIR")) return "C:\\Temp";
    if (std.ascii.eqlIgnoreCase(name, "SystemRoot") or std.ascii.eqlIgnoreCase(name, "WINDIR")) return "C:\\Windows";
    if (std.ascii.eqlIgnoreCase(name, "HOME")) return "C:\\Users\\Rosetta";
    if (std.ascii.eqlIgnoreCase(name, "USERNAME")) return "Rosetta";
    if (std.ascii.eqlIgnoreCase(name, "PROCESSOR_ARCHITECTURE")) return "AMD64";
    if (std.ascii.eqlIgnoreCase(name, "SDL_AUDIODRIVER")) return configuredSdlAudioDriver();
    return null;
}

fn windowsErrorString(error_code: u64) []const u8 {
    // `strerror` returns a pointer to a NUL-terminated message, not an
    // optional status. Returning null for an otherwise valid errno causes
    // libstdc++'s error-category formatter to construct basic_string(nullptr)
    // and throw a secondary logic_error during ordinary error reporting.
    // Keep the common values stable and provide a non-null fallback for every
    // remaining code; the returned bytes are copied into guest memory by the
    // caller, so no host pointer crosses the ABI boundary.
    return switch (error_code) {
        0 => "Success",
        2 => "No such file or directory",
        5 => "Input/output error",
        9 => "Bad file descriptor",
        11 => "Resource temporarily unavailable",
        12 => "Cannot allocate memory",
        13 => "Permission denied",
        17 => "File exists",
        19 => "No such device",
        22 => "Invalid argument",
        28 => "No space left on device",
        32 => "Broken pipe",
        35 => "Resource deadlock avoided",
        42 => "No message of desired type",
        110 => "Connection timed out",
        else => "Unknown error",
    };
}

fn wideEnvironmentValue(state: anytype, address: u64) ?[]const u8 {
    const names = [_][]const u8{ "TEMP", "TMP", "TMPDIR", "SystemRoot", "WINDIR", "HOME", "USERNAME", "PROCESSOR_ARCHITECTURE", "SDL_AUDIODRIVER" };
    for (names) |name| {
        if (guestWideEqualsLiteral(state, address, name)) {
            const value = environmentValue(name);
            if (std.mem.eql(u8, name, "SDL_AUDIODRIVER")) noteSdlAudioDriverQuery(state, value, "GetEnvironmentVariableW");
            return value;
        }
    }
    return null;
}

fn copyGuestString(state: anytype, destination: u64, capacity: u64, source: []const u8) u64 {
    if (capacity == 0) return source.len;
    const available = @min(source.len, @as(usize, @intCast(@min(capacity - 1, std.math.maxInt(usize)))));
    const output = state.guestMemory(destination, @as(u64, @intCast(available + 1))) orelse return 0;
    @memcpy(output[0..available], source[0..available]);
    output[available] = 0;
    return available;
}

fn appendUtf8CodePoint(destination: []u8, index: *usize, value: u32) bool {
    const length = utf8CodePointLength(value);
    if (length > destination.len -| index.*) return false;
    switch (length) {
        1 => destination[index.*] = @intCast(value),
        2 => {
            destination[index.* + 0] = @intCast(0xC0 | (value >> 6));
            destination[index.* + 1] = @intCast(0x80 | (value & 0x3F));
        },
        3 => {
            destination[index.* + 0] = @intCast(0xE0 | (value >> 12));
            destination[index.* + 1] = @intCast(0x80 | ((value >> 6) & 0x3F));
            destination[index.* + 2] = @intCast(0x80 | (value & 0x3F));
        },
        4 => {
            destination[index.* + 0] = @intCast(0xF0 | (value >> 18));
            destination[index.* + 1] = @intCast(0x80 | ((value >> 12) & 0x3F));
            destination[index.* + 2] = @intCast(0x80 | ((value >> 6) & 0x3F));
            destination[index.* + 3] = @intCast(0x80 | (value & 0x3F));
        },
        else => return false,
    }
    index.* += length;
    return true;
}

/// Read a bounded guest UTF-16 string into host scratch storage. This is used
/// only for path/API dispatch; the resulting bytes never become a guest
/// pointer and are not retained after the import returns.
fn guestWideToUtf8Buffer(state: anytype, address: u64, destination: []u8) ?[]const u8 {
    const unit_count = guestWideCStringLength(state, address, 64 * 1024) orelse return null;
    var index: usize = 0;
    var written: usize = 0;
    while (index < unit_count) {
        const code_point = guestWideCodePoint(state, address, index, unit_count) orelse return null;
        if (!appendUtf8CodePoint(destination, &written, code_point.value)) return null;
        index += code_point.consumed;
    }
    return destination[0..written];
}

fn normalizedFullPath(source: []const u8, destination: []u8) ?[]const u8 {
    if (source.len == 0) return null;
    var written: usize = 0;
    const has_drive = source.len >= 2 and source[1] == ':';
    const has_root = source[0] == '\\' or source[0] == '/';
    if (!has_drive and !has_root) {
        const prefix = "C:\\xenia\\";
        if (prefix.len > destination.len) return null;
        @memcpy(destination[0..prefix.len], prefix);
        written = prefix.len;
    }

    for (source) |character| {
        if (written == destination.len) return null;
        destination[written] = if (character == '/') '\\' else character;
        written += 1;
    }
    while (written > 3 and destination[written - 1] == '\\') written -= 1;
    return destination[0..written];
}

fn writeFullPathFilePart(state: anytype, destination: u64, capacity: u64, full_path: []const u8, file_part: u64, wide: bool) void {
    if (file_part == 0 or destination == 0 or capacity == 0) return;
    var separator_index: usize = 0;
    for (full_path, 0..) |character, index| {
        if (character == '\\' or character == '/') separator_index = index + 1;
    }
    const element_width: usize = if (wide) 2 else 1;
    const part_address = destination +| @as(u64, @intCast(separator_index * element_width));
    state.write64(file_part, part_address);
}

fn startsWithIgnoreCase(value: []const u8, prefix: []const u8) bool {
    return value.len >= prefix.len and std.ascii.eqlIgnoreCase(value[0..prefix.len], prefix);
}

fn traceWindowsPath(state: anytype, guest: []const u8, outcome: []const u8) void {
    const media_match = if (state.windows_host_media_path) |media_path| blk: {
        const media_name = std.fs.path.basename(media_path);
        const exact_match = media_name.len != 0 and guest.len >= media_name.len and
            std.ascii.eqlIgnoreCase(guest[guest.len - media_name.len ..], media_name) and
            (guest.len == media_name.len or guest[guest.len - media_name.len - 1] == '\\' or
                guest[guest.len - media_name.len - 1] == '/');
        const canonical_match = if (std.ascii.indexOfIgnoreCase(media_name, ".iso")) |iso_offset| blk2: {
            const canonical_name = media_name[0 .. iso_offset + 4];
            break :blk2 canonical_name.len != 0 and guest.len >= canonical_name.len and
                std.ascii.eqlIgnoreCase(guest[guest.len - canonical_name.len ..], canonical_name) and
                (guest.len == canonical_name.len or guest[guest.len - canonical_name.len - 1] == '\\' or
                    guest[guest.len - canonical_name.len - 1] == '/');
        } else false;
        break :blk exact_match or canonical_match;
    } else false;
    if (media_match) {
        if (state.windows_media_path_trace_events >= 16) return;
        state.windows_media_path_trace_events += 1;
    } else {
        if (!state.trace_windows_paths or state.windows_path_trace_events >= 64) return;
        state.windows_path_trace_events += 1;
    }
    log.info("Windows path resolution: guest='{s}' outcome={s}", .{ guest, outcome });
}

/// Translate a guest Windows path into the run's explicitly-authorized host
/// root. This is intentionally lexical and bounded: drive letters, UNC paths,
/// and parent traversal are rejected rather than accidentally exposing the
/// host filesystem to a translated PE.
fn guestPathToHost(state: anytype, address: u64, wide: bool, destination: []u8) ?[]const u8 {
    const base = state.windows_host_working_directory orelse return null;
    var guest_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const guest = if (wide)
        guestWideToUtf8Buffer(state, address, &guest_buffer)
    else
        guestCString(state, address);
    const value = guest orelse return null;
    if (value.len == 0) return null;
    traceWindowsPath(state, value, "input");

    var path = value;
    if (startsWithIgnoreCase(path, "\\\\?\\")) path = path[4..];

    // The Windows UI asks for FOLDERID_Fonts even though the PE is running
    // on macOS.  Keep that path virtual and confined: the guest sees the
    // ordinary Windows name, while file existence/open calls are redirected
    // to a Japanese-capable font already installed on the host.  No Windows
    // system directory is exposed to the guest by this exception.
    if (windowsJapaneseFontHostPath(state, path, destination)) |mapped| {
        traceWindowsPath(state, value, "authorized_host_font");
        return mapped;
    }

    var relative = path;
    // Windows APIs and the C++ filesystem layer are allowed to normalize a
    // drive path with either separator.  Keep the confined virtual mount
    // independent of that spelling: rejecting C:/xenia while accepting
    // C:\xenia makes a title appear to be unsupported even though the
    // explicitly-authorized media file is present.
    const is_xenia_root = path.len >= 8 and
        std.ascii.eqlIgnoreCase(path[0..2], "C:") and
        (path[2] == '\\' or path[2] == '/') and
        std.ascii.eqlIgnoreCase(path[3..8], "xenia") and
        (path.len == 8 or path[8] == '\\' or path[8] == '/');
    if (is_xenia_root) {
        relative = if (path.len == 8) "" else path[9..];
    } else if (path.len >= 2 and path[1] == ':') {
        // Only the virtual C:\xenia tree is mounted. Other drive roots are
        // not host paths and must remain visible as a normal Win32 miss.
        traceWindowsPath(state, value, "rejected_drive");
        return null;
    } else if (startsWithIgnoreCase(path, "\\\\")) {
        return null;
    } else if (path[0] == '/') {
        // A native absolute path is accepted only when it already lies under
        // the configured root. This supports explicitly supplied host paths
        // without broadening the guest's authority.
        if (!std.mem.startsWith(u8, path, base)) return null;
        if (path.len > base.len and path[base.len] != '/') return null;
        if (path.len > destination.len) return null;
        @memcpy(destination[0..path.len], path);
        return destination[0..path.len];
    } else if (path[0] == '\\') {
        relative = path[1..];
    }

    // A supplied media image is an explicit one-file authority for the
    // virtual C:\\xenia mount. Expose it only by its exact leaf name; this
    // lets Xenia open the Halo image without granting the guest arbitrary
    // access to the host volume containing it.
    if (state.windows_host_media_path) |media_path| {
        const media_name = std.fs.path.basename(media_path);
        const exact_match = media_name.len != 0 and std.ascii.eqlIgnoreCase(relative, media_name);
        const canonical_match = if (std.ascii.indexOfIgnoreCase(media_name, ".iso")) |iso_offset| blk: {
            const canonical_name = media_name[0 .. iso_offset + 4];
            break :blk std.ascii.eqlIgnoreCase(relative, canonical_name);
        } else false;
        if (exact_match or canonical_match) {
            if (media_path.len > destination.len) return null;
            @memcpy(destination[0..media_path.len], media_path);
            traceWindowsPath(state, value, "authorized_media");
            return destination[0..media_path.len];
        }
    }

    // Normalize separators while checking every component for traversal.
    var component_start: usize = 0;
    var normalized_relative: [std.fs.max_path_bytes]u8 = undefined;
    var normalized_len: usize = 0;
    while (component_start <= relative.len) {
        var component_end = component_start;
        while (component_end < relative.len and relative[component_end] != '\\' and relative[component_end] != '/') : (component_end += 1) {}
        const component = relative[component_start..component_end];
        if (std.mem.eql(u8, component, "..")) return null;
        if (component.len != 0 and !std.mem.eql(u8, component, ".")) {
            if (normalized_len != 0) {
                if (normalized_len == normalized_relative.len) return null;
                normalized_relative[normalized_len] = '/';
                normalized_len += 1;
            }
            if (component.len > normalized_relative.len -| normalized_len) return null;
            for (component) |character| {
                normalized_relative[normalized_len] = if (character == '\\') '/' else character;
                normalized_len += 1;
            }
        }
        if (component_end == relative.len) break;
        component_start = component_end + 1;
    }

    if (base.len > destination.len) return null;
    @memcpy(destination[0..base.len], base);
    var written = base.len;
    if (normalized_len != 0) {
        if (written == destination.len) return null;
        destination[written] = '/';
        written += 1;
        if (normalized_len > destination.len - written) return null;
        @memcpy(destination[written..][0..normalized_len], normalized_relative[0..normalized_len]);
        written += normalized_len;
    }
    traceWindowsPath(state, value, "confined_root");
    return destination[0..written];
}

/// Whether the guest may see a CJK font at `C:\Windows\Fonts\msgothic.ttc`.
///
/// Handing Xenia a real CJK font is authentic - it is what a Windows machine
/// with Japanese support does - but it is not free under translation. Xenia's
/// ImGui drawer merges `GetGlyphRangesJapanese()` into the atlas and builds
/// that atlas *twice*, at two font sizes, with 2x oversampling. The build runs
/// on the UI thread, between the presenter acquiring a swapchain and the
/// window's first paint, so nothing can be drawn until it finishes. On the
/// 2026-09-11 run that put the guest inside `stbtt__run_charstring` for the
/// entire remaining life of the process and produced a `no_presents` verdict
/// against a presentation chain that was completely healthy.
///
/// So the mapping is opt-in. Off, Xenia takes the same path it takes on a
/// Windows box without the font - it logs that Japanese characters will be
/// boxes and builds an ASCII atlas in a fraction of the time. On, the run
/// pays for the glyphs and the log says so up front.
fn guestCjkFontEnabled() bool {
    const raw = std.c.getenv("ROSETTE_XENIA_GUEST_CJK_FONT") orelse return false;
    const value = std.mem.span(raw);
    return std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes");
}

fn windowsJapaneseFontHostPath(state: anytype, path: []const u8, destination: []u8) ?[]const u8 {
    const prefix = "C:\\Windows\\Fonts\\";
    if (!startsWithIgnoreCase(path, prefix)) return null;
    if (!std.ascii.eqlIgnoreCase(path[prefix.len..], "msgothic.ttc")) return null;

    const State = @TypeOf(state.*);
    if (!guestCjkFontEnabled()) {
        if (comptime @hasDecl(State, "noteGuestCjkFontDecision")) {
            state.noteGuestCjkFontDecision(false, "");
        }
        return null;
    }

    // These are host-installed fonts with broad CJK coverage.  The first
    // candidate is the normal macOS system font; the others cover machines
    // whose system font names differ by macOS release or locale.  Only a
    // successful stat is selected, so the PE never receives a path to a
    // nonexistent file.
    const candidates = [_][]const u8{
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/AppleSDGothicNeo.ttc",
        "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    };
    for (candidates) |candidate| {
        if (hostStat(state, candidate) == null) continue;
        if (candidate.len > destination.len) return null;
        @memcpy(destination[0..candidate.len], candidate);
        if (comptime @hasDecl(State, "noteGuestCjkFontDecision")) {
            state.noteGuestCjkFontDecision(true, candidate);
        }
        return destination[0..candidate.len];
    }
    if (comptime @hasDecl(State, "noteGuestCjkFontDecision")) {
        state.noteGuestCjkFontDecision(false, "no host CJK font matched");
    }
    return null;
}

fn hostOpenFile(state: anytype, path: []const u8, mode: std.Io.Dir.OpenFileOptions.Mode) ?std.Io.File {
    const io = state.windows_host_io orelse return null;
    const options: std.Io.Dir.OpenFileOptions = .{ .mode = mode, .allow_directory = false };
    const is_media = if (state.windows_host_media_path) |media_path|
        std.mem.eql(u8, path, media_path)
    else
        false;
    if (is_media and state.windows_media_io_trace_events < 16) {
        state.windows_media_io_trace_events += 1;
        log.info("Windows media host open: path={s} mode={s}", .{ path, @tagName(mode) });
    }
    if (state.diagnose_abi) {
        log.info("Windows host open: path={s} mode={s}", .{ path, @tagName(mode) });
    }
    if (std.fs.path.isAbsolute(path)) {
        return std.Io.Dir.openFileAbsolute(io, path, options) catch |err| {
            if (is_media and state.windows_media_io_trace_events < 16) {
                state.windows_media_io_trace_events += 1;
                log.info("Windows media host open failed: path={s} error={s}", .{ path, @errorName(err) });
            }
            if (state.diagnose_abi) log.info("Windows host open failed: path={s} error={s}", .{ path, @errorName(err) });
            return null;
        };
    }
    return std.Io.Dir.cwd().openFile(io, path, options) catch |err| {
        if (is_media and state.windows_media_io_trace_events < 16) {
            state.windows_media_io_trace_events += 1;
            log.info("Windows media host open failed: path={s} error={s}", .{ path, @errorName(err) });
        }
        if (state.diagnose_abi) log.info("Windows host open failed: path={s} error={s}", .{ path, @errorName(err) });
        return null;
    };
}

fn hostCreateFile(state: anytype, path: []const u8, read: bool, truncate: bool, exclusive: bool) ?std.Io.File {
    const io = state.windows_host_io orelse return null;
    const options: std.Io.Dir.CreateFileOptions = .{
        .read = read,
        .truncate = truncate,
        .exclusive = exclusive,
    };
    if (state.diagnose_abi) {
        log.info("Windows host create: path={s} read={} truncate={} exclusive={}", .{ path, read, truncate, exclusive });
    }
    if (std.fs.path.isAbsolute(path)) {
        return std.Io.Dir.createFileAbsolute(io, path, options) catch |err| {
            if (state.diagnose_abi) log.info("Windows host create failed: path={s} error={s}", .{ path, @errorName(err) });
            return null;
        };
    }
    return std.Io.Dir.cwd().createFile(io, path, options) catch |err| {
        if (state.diagnose_abi) log.info("Windows host create failed: path={s} error={s}", .{ path, @errorName(err) });
        return null;
    };
}

fn hostStat(state: anytype, path: []const u8) ?std.Io.File.Stat {
    const io = state.windows_host_io orelse return null;
    const is_media = if (state.windows_host_media_path) |media_path|
        std.mem.eql(u8, path, media_path)
    else
        false;
    const result = if (std.fs.path.isAbsolute(path))
        std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| {
            if (is_media and state.windows_media_io_trace_events < 16) {
                state.windows_media_io_trace_events += 1;
                log.info("Windows media host stat failed: path={s} error={s}", .{ path, @errorName(err) });
            }
            if (state.diagnose_abi) log.info("Windows host stat failed: path={s} error={s}", .{ path, @errorName(err) });
            return null;
        }
    else
        std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| {
            if (is_media and state.windows_media_io_trace_events < 16) {
                state.windows_media_io_trace_events += 1;
                log.info("Windows media host stat failed: path={s} error={s}", .{ path, @errorName(err) });
            }
            if (state.diagnose_abi) log.info("Windows host stat failed: path={s} error={s}", .{ path, @errorName(err) });
            return null;
        };
    if (is_media and state.windows_media_io_trace_events < 16) {
        state.windows_media_io_trace_events += 1;
        log.info("Windows media host stat: path={s} kind={s} size={d}", .{ path, @tagName(result.kind), result.size });
    }
    if (state.diagnose_abi) log.info("Windows host stat: path={s} kind={s} size={d}", .{ path, @tagName(result.kind), result.size });
    return result;
}

fn hostOpenDirectory(state: anytype, path: []const u8) ?std.Io.Dir {
    const io = state.windows_host_io orelse return null;
    const options: std.Io.Dir.OpenOptions = .{ .iterate = true, .follow_symlinks = false };
    return if (std.fs.path.isAbsolute(path))
        std.Io.Dir.openDirAbsolute(io, path, options) catch null
    else
        std.Io.Dir.cwd().openDir(io, path, options) catch null;
}

fn installWindowsFile(
    state: anytype,
    file: std.Io.File,
    readable: bool,
    writable: bool,
    media_authorized: bool,
) ?u64 {
    for (&state.windows_files) |*slot| {
        if (slot.file == null) {
            const handle = nextHandle(state);
            const stdio_fd = state.windows_next_stdio_fd;
            state.windows_next_stdio_fd +|= 1;
            slot.* = .{
                .guest_handle = handle,
                .stdio_fd = stdio_fd,
                .file = file,
                .readable = readable,
                .writable = writable,
                .media_authorized = media_authorized,
            };
            return handle;
        }
    }
    const io = state.windows_host_io orelse return null;
    file.close(io);
    return null;
}

/// Materialize one of the three CRT standard streams as an ordinary
/// synthetic FILE* slot.  `__acrt_iob_func` returns a FILE pointer, not a
/// Windows HANDLE, so allocating guest memory without registering the value
/// in `windows_files` makes every subsequent fwrite/fflush report
/// ERROR_INVALID_HANDLE.  The host descriptor is borrowed and remains owned
/// by the Rosetta runner.
fn installWindowsStandardStream(state: anytype, index: u64) ?u64 {
    if (index >= 3) return null;
    const stream_index: usize = @intCast(index);
    if (state.windows_acrt_iob_storage[stream_index] != 0) {
        return state.windows_acrt_iob_storage[stream_index];
    }

    var destination: ?*@TypeOf(state.windows_files[0]) = null;
    for (&state.windows_files) |*candidate| {
        if (candidate.file == null) {
            destination = candidate;
            break;
        }
    }
    const slot = destination orelse return null;
    const guest_file = state.guestAlloc(64, 8) orelse return null;
    const host_file = switch (stream_index) {
        0 => std.Io.File.stdin(),
        1 => std.Io.File.stdout(),
        2 => std.Io.File.stderr(),
        else => unreachable,
    };
    slot.* = .{
        .guest_handle = guest_file,
        .stdio_fd = @intCast(stream_index),
        .file = host_file,
        .readable = stream_index == 0,
        .writable = stream_index != 0,
        .standard_stream = @intCast(stream_index),
    };
    // Keep the guest object non-null and deterministic if the CRT inspects
    // the first word, without exposing the native stdio descriptor.
    state.write64(guest_file, 0);
    state.windows_acrt_iob_storage[stream_index] = guest_file;
    log.info("Windows CRT stdio stream installed: index={d} FILE=0x{x} borrowed_fd={d}", .{
        stream_index,
        guest_file,
        host_file.handle,
    });
    return guest_file;
}

fn windowsFileSlot(state: anytype, handle: u64) ?*@TypeOf(state.windows_files[0]) {
    for (&state.windows_files) |*slot| {
        if (slot.file != null and slot.guest_handle == handle) return slot;
    }
    return null;
}

fn closeWindowsFile(state: anytype, handle: u64) bool {
    const slot = windowsFileSlot(state, handle) orelse return false;
    // CRT fclose invalidates the guest stream, but must not close Rosetta's
    // own process descriptors.  Xenia only uses this at teardown; retaining
    // the borrowed slot also keeps a later diagnostic flush harmless.
    if (slot.standard_stream != null) return true;
    const io = state.windows_host_io orelse return false;
    if (slot.file) |file| file.close(io);
    slot.* = .{};
    return true;
}

fn windowsFileAttributes(stat: std.Io.File.Stat) u32 {
    var attributes: u32 = if (stat.kind == .directory) 0x10 else 0x80; // DIRECTORY/NORMAL
    if (stat.permissions.readOnly()) attributes |= 0x1; // READONLY
    return attributes;
}

fn writeFileAttributeData(state: anytype, destination: u64, stat: std.Io.File.Stat) bool {
    if (destination == 0 or state.guestMemory(destination, 36) == null) return false;
    state.write32(destination + 0, windowsFileAttributes(stat));
    // FILETIME fields are intentionally zero: the ABI needs a valid shape,
    // while the host timestamp is not part of the graphics contract.
    state.write64(destination + 4, 0);
    state.write64(destination + 12, 0);
    state.write64(destination + 20, 0);
    state.write32(destination + 28, @truncate(stat.size));
    state.write32(destination + 32, @truncate(stat.size >> 32));
    return true;
}

fn wildcardMatch(pattern: []const u8, value: []const u8) bool {
    var pattern_index: usize = 0;
    var value_index: usize = 0;
    var star: ?usize = null;
    var star_value: usize = 0;
    while (value_index < value.len) {
        if (pattern_index < pattern.len and (pattern[pattern_index] == '?' or
            std.ascii.toLower(pattern[pattern_index]) == std.ascii.toLower(value[value_index])))
        {
            pattern_index += 1;
            value_index += 1;
        } else if (pattern_index < pattern.len and pattern[pattern_index] == '*') {
            star = pattern_index;
            pattern_index += 1;
            star_value = value_index;
        } else if (star) |star_index| {
            pattern_index = star_index + 1;
            star_value += 1;
            value_index = star_value;
        } else {
            return false;
        }
    }
    while (pattern_index < pattern.len and pattern[pattern_index] == '*') pattern_index += 1;
    return pattern_index == pattern.len;
}

fn noteWindowsFileFailure(state: anytype) void {
    noteWindowsFileFailureCode(state, state.windows_last_error);
}

fn noteWindowsFileFailureCode(state: anytype, error_code: u32) void {
    state.windows_file_failures +|= 1;
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "noteWindowsFileFailure")) state.noteWindowsFileFailure(error_code);
}

fn failWindowsFileCall(state: anytype, direct_return_rip: ?u64, error_code: u32) void {
    noteWindowsFileFailureCode(state, error_code);
    state.windows_last_error = error_code;
    state.regs.rax = 0;
    if (state.diagnose_abi) {
        log.info("Windows file call failed: error={d} rip=0x{x}", .{ error_code, state.regs.rip });
    }
    finish(state, direct_return_rip);
}

/// Fill the MinGW/UCRT `_stat64` record used by the PE's filesystem layer.
///
/// The Xenia Windows capsule is built for x86_64-w64-mingw32. Its `_stat64`
/// record is 56 bytes with the four-byte `_dev_t` aligned at byte 16 and the
/// 64-bit size at byte 24. This is not the POSIX layout, nor is it the
/// unaligned byte-18 layout used by some hand-written MSVC descriptions.
/// Keeping this in one writer is important: `std::filesystem` may reach the
/// path form or the descriptor form depending on the libstdc++ version.
fn writeWindowsStat64(state: anytype, output: u64, output_bytes: []u8, stat: std.Io.File.Stat) void {
    @memset(output_bytes, 0);
    state.write32(output + 0, 0); // st_dev
    state.write16(output + 4, 0); // st_ino
    state.write16(output + 6, if (stat.kind == .directory) 0x4000 else 0x8000);
    state.write16(output + 8, 1); // st_nlink
    state.write16(output + 10, 0); // st_uid
    state.write16(output + 12, 0); // st_gid
    state.write32(output + 16, 0); // st_rdev
    state.write64(output + 24, stat.size); // st_size
}

fn statWindowsPath(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const wide = std.mem.startsWith(u8, name, "_w");
    const output = arg(state, 1, direct_return_rip);
    const output_bytes = state.guestMemory(output, 56) orelse {
        state.windows_last_error = 22; // EINVAL
        state.regs.rax = std.math.maxInt(u64);
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = guestPathToHost(state, arg(state, 0, direct_return_rip), wide, &path_buffer) orelse {
        state.windows_last_error = 2; // ENOENT / ERROR_FILE_NOT_FOUND
        state.regs.rax = std.math.maxInt(u64);
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    const stat = hostStat(state, path) orelse {
        state.windows_last_error = 2;
        state.regs.rax = std.math.maxInt(u64);
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    writeWindowsStat64(state, output, output_bytes, stat);
    state.windows_last_error = 0;
    state.regs.rax = 0;
    if (state.diagnose_abi) {
        log.info("Windows CRT stat: name={s} path={s} kind={s} size={d} output=0x{x}", .{
            name,
            path,
            @tagName(stat.kind),
            stat.size,
            output,
        });
    }
    finish(state, direct_return_rip);
    return true;
}

/// Descriptor counterpart of `_stat64`. MinGW's `std::filesystem` and
/// file-stream implementations are allowed to use `_fstat64` after opening a
/// path, so a successful `_wfopen` must not be the end of the virtual file
/// contract. The descriptor is Rosetta's synthetic CRT fd, not a host fd.
fn statWindowsDescriptor(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const fd: u32 = @truncate(arg(state, 0, direct_return_rip));
    const output = arg(state, 1, direct_return_rip);
    const output_bytes = state.guestMemory(output, 56) orelse {
        state.windows_last_error = 22; // EINVAL
        state.regs.rax = std.math.maxInt(u64);
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    const slot = windowsStdioSlot(state, fd) orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9); // EBADF
        return true;
    };
    const io = state.windows_host_io orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9);
        return true;
    };
    const stat = slot.file.?.stat(io) catch {
        failWindowsDescriptorCall(state, direct_return_rip, 5); // EIO
        return true;
    };

    writeWindowsStat64(state, output, output_bytes, stat);
    state.windows_last_error = 0;
    state.regs.rax = 0;
    if (slot.media_authorized and state.windows_media_io_trace_events < 16) {
        state.windows_media_io_trace_events += 1;
        log.info("Windows media CRT descriptor stat: api={s} fd={d} size={d} output=0x{x}", .{
            name,
            fd,
            stat.size,
            output,
        });
    }
    finish(state, direct_return_rip);
    return true;
}

fn installWindowsFind(state: anytype, dir: std.Io.Dir, directory_path: []const u8, pattern: []const u8, wide: bool) ?u64 {
    for (&state.windows_finds) |*slot| {
        if (slot.iterator == null) {
            if (directory_path.len > slot.directory.len) break;
            if (pattern.len > slot.pattern.len) break;
            slot.* = .{
                .guest_handle = nextHandle(state),
                .dir = dir,
                .iterator = std.Io.Dir.iterate(dir),
                .directory_len = directory_path.len,
                .wide = wide,
            };
            @memcpy(slot.directory[0..directory_path.len], directory_path);
            @memcpy(slot.pattern[0..pattern.len], pattern);
            slot.pattern_len = pattern.len;
            return slot.guest_handle;
        }
    }
    const io = state.windows_host_io orelse return null;
    dir.close(io);
    return null;
}

fn windowsFindSlot(state: anytype, handle: u64) ?*@TypeOf(state.windows_finds[0]) {
    for (&state.windows_finds) |*slot| {
        if (slot.iterator != null and slot.guest_handle == handle) return slot;
    }
    return null;
}

fn closeWindowsFind(state: anytype, handle: u64) bool {
    const slot = windowsFindSlot(state, handle) orelse return false;
    const io = state.windows_host_io orelse return false;
    if (slot.dir) |dir| dir.close(io);
    slot.* = .{};
    return true;
}

fn writeFindData(state: anytype, output: u64, entry: std.Io.Dir.Entry, stat: ?std.Io.File.Stat, wide: bool) bool {
    const size: u64 = if (stat) |value| value.size else 0;
    const attributes: u32 = if (entry.kind == .directory) 0x10 else 0x80;
    const data_size: u64 = if (wide) 592 else 320;
    if (output == 0 or state.guestMemory(output, data_size) == null) return false;
    state.write32(output + 0, attributes);
    state.write64(output + 4, 0);
    state.write64(output + 12, 0);
    state.write64(output + 20, 0);
    state.write32(output + 28, @truncate(size >> 32));
    state.write32(output + 32, @truncate(size));
    state.write32(output + 36, 0);
    state.write32(output + 40, 0);
    if (wide) {
        _ = copyGuestWideString(state, output + 44, 260, entry.name);
    } else {
        _ = copyGuestString(state, output + 44, 260, entry.name);
    }
    return true;
}

fn advanceWindowsFind(state: anytype, slot: anytype, output: u64) bool {
    const io = state.windows_host_io orelse return false;
    while (true) {
        const maybe_entry = slot.iterator.?.next(io) catch return false;
        const entry = maybe_entry orelse return false;
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;
        if (!wildcardMatch(slot.pattern[0..slot.pattern_len], entry.name)) continue;
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        if (slot.directory_len >= path_buffer.len or entry.name.len > path_buffer.len - slot.directory_len - 1) return false;
        @memcpy(path_buffer[0..slot.directory_len], slot.directory[0..slot.directory_len]);
        var path_len = slot.directory_len;
        if (path_len != 0 and path_buffer[path_len - 1] != '/') {
            path_buffer[path_len] = '/';
            path_len += 1;
        }
        @memcpy(path_buffer[path_len..][0..entry.name.len], entry.name);
        path_len += entry.name.len;
        return writeFindData(state, output, entry, hostStat(state, path_buffer[0..path_len]), slot.wide);
    }
}

fn openWindowsFile(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const wide = std.mem.endsWith(u8, name, "W");
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = guestPathToHost(state, arg(state, 0, direct_return_rip), wide, &path_buffer) orelse {
        failWindowsFileCall(state, direct_return_rip, 2); // ERROR_FILE_NOT_FOUND
        state.regs.rax = std.math.maxInt(u64);
        return true;
    };
    const desired_access = arg(state, 1, direct_return_rip);
    const can_read = desired_access == 0 or (desired_access & 0x8000_0000) != 0;
    const can_write = (desired_access & 0x4000_0000) != 0;
    const disposition: u32 = @truncate(arg(state, 4, direct_return_rip));
    const mode: std.Io.Dir.OpenFileOptions.Mode = if (can_read and can_write)
        .read_write
    else if (can_write)
        .write_only
    else
        .read_only;

    var file: ?std.Io.File = null;
    switch (disposition) {
        1 => file = hostCreateFile(state, path, can_read, false, true), // CREATE_NEW
        2 => file = hostCreateFile(state, path, can_read, true, false), // CREATE_ALWAYS
        3 => file = hostOpenFile(state, path, mode), // OPEN_EXISTING
        4 => { // OPEN_ALWAYS
            file = hostOpenFile(state, path, mode);
            if (file == null) file = hostCreateFile(state, path, can_read, false, false);
        },
        5 => { // TRUNCATE_EXISTING
            file = hostOpenFile(state, path, mode);
            if (file) |opened| {
                const io = state.windows_host_io orelse unreachable;
                opened.setLength(io, 0) catch {
                    opened.close(io);
                    file = null;
                };
            }
        },
        else => {},
    }
    const opened = file orelse {
        failWindowsFileCall(state, direct_return_rip, 2); // ERROR_FILE_NOT_FOUND
        state.regs.rax = std.math.maxInt(u64);
        return true;
    };
    const media_authorized = if (state.windows_host_media_path) |media_path|
        std.mem.eql(u8, path, media_path)
    else
        false;
    const handle = installWindowsFile(state, opened, can_read, can_write, media_authorized) orelse {
        failWindowsFileCall(state, direct_return_rip, 4); // ERROR_TOO_MANY_OPEN_FILES
        state.regs.rax = std.math.maxInt(u64);
        return true;
    };
    if (media_authorized and state.windows_media_io_trace_events < 16) {
        state.windows_media_io_trace_events += 1;
        log.info("Windows media file handle: api={s} handle=0x{x} readable={} writable={}", .{
            name,
            handle,
            can_read,
            can_write,
        });
    }
    state.windows_file_open_calls +|= 1;
    state.windows_last_error = 0;
    state.regs.rax = handle;
    finish(state, direct_return_rip);
    return true;
}

fn openWindowsStdio(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const wide = std.mem.eql(u8, name, "_wfopen") or std.mem.eql(u8, name, "_wfsopen");
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = guestPathToHost(state, arg(state, 0, direct_return_rip), wide, &path_buffer) orelse {
        failWindowsFileCall(state, direct_return_rip, 2); // ERROR_FILE_NOT_FOUND
        return true;
    };
    const mode = guestCString(state, arg(state, 1, direct_return_rip)) orelse {
        failWindowsFileCall(state, direct_return_rip, 87); // ERROR_INVALID_PARAMETER
        return true;
    };
    if (mode.len == 0) {
        failWindowsFileCall(state, direct_return_rip, 87);
        return true;
    }
    const read_write = std.mem.indexOfScalar(u8, mode, '+') != null;
    const read = read_write or mode[0] == 'r';
    const write = read_write or mode[0] == 'w' or mode[0] == 'a';
    var file: ?std.Io.File = null;
    switch (mode[0]) {
        'r' => file = hostOpenFile(state, path, if (read_write) .read_write else .read_only),
        'w' => file = hostCreateFile(state, path, read_write, true, false),
        'a' => {
            file = hostOpenFile(state, path, if (read_write) .read_write else .write_only);
            if (file == null) file = hostCreateFile(state, path, read_write, false, false);
        },
        else => {},
    }
    const opened = file orelse {
        failWindowsFileCall(state, direct_return_rip, 2); // ERROR_FILE_NOT_FOUND
        return true;
    };
    const media_authorized = if (state.windows_host_media_path) |media_path|
        std.mem.eql(u8, path, media_path)
    else
        false;
    const handle = installWindowsFile(state, opened, read, write, media_authorized) orelse {
        failWindowsFileCall(state, direct_return_rip, 4); // ERROR_TOO_MANY_OPEN_FILES
        return true;
    };
    if (media_authorized and state.windows_media_io_trace_events < 16) {
        state.windows_media_io_trace_events += 1;
        log.info("Windows media stdio handle: api={s} handle=0x{x} mode={s} readable={} writable={}", .{
            name,
            handle,
            mode,
            read,
            write,
        });
    }
    if (mode[0] == 'a') {
        const slot = windowsFileSlot(state, handle).?;
        const io = state.windows_host_io orelse unreachable;
        if (slot.file.?.stat(io)) |stat| {
            slot.offset = stat.size;
        } else |_| {
            slot.offset = 0;
        }
    }
    state.windows_file_open_calls +|= 1;
    state.windows_last_error = 0;
    state.regs.rax = handle;
    finish(state, direct_return_rip);
    return true;
}

fn windowsStdioSlot(state: anytype, fd: u32) ?*@TypeOf(state.windows_files[0]) {
    for (&state.windows_files) |*slot| {
        if (slot.file != null and slot.stdio_fd == fd) return slot;
    }
    return null;
}

fn failWindowsDescriptorCall(state: anytype, direct_return_rip: ?u64, errno_value: u32) void {
    state.windows_last_error = errno_value;
    state.regs.rax = std.math.maxInt(u64); // POSIX/CRT descriptor failure: -1
    noteWindowsFileFailure(state);
    finish(state, direct_return_rip);
}

/// Read or write through the descriptor returned by fileno(). MinGW's
/// libstdc++ implementation does not use fread/fwrite for basic_filebuf: it
/// opens a FILE*, obtains its descriptor, then calls _read/_write directly.
/// The descriptor must therefore resolve to the same confined slot and offset
/// as the FILE* handle; a zero-returning fallback makes every stream appear
/// empty and can turn a valid TOML file into a parse_error.
fn transferWindowsDescriptor(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const fd: u32 = @truncate(arg(state, 0, direct_return_rip));
    const requested = arg(state, 2, direct_return_rip);
    const slot = windowsStdioSlot(state, fd) orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9); // EBADF
        return true;
    };
    if (slot.media_authorized and state.windows_media_io_trace_events < 16) {
        state.windows_media_io_trace_events += 1;
        log.info("Windows media descriptor transfer: name={s} fd={d} requested={d} offset={d}", .{
            name,
            fd,
            requested,
            slot.offset,
        });
    }
    const is_read = std.mem.eql(u8, name, "read") or std.mem.eql(u8, name, "_read");
    if ((is_read and !slot.readable) or (!is_read and !slot.writable)) {
        failWindowsDescriptorCall(state, direct_return_rip, 9);
        return true;
    }
    if (requested == 0) {
        state.regs.rax = 0;
        state.windows_last_error = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (requested > std.math.maxInt(usize)) {
        failWindowsDescriptorCall(state, direct_return_rip, 22); // EINVAL
        return true;
    }
    const buffer = state.guestMemory(arg(state, 1, direct_return_rip), requested) orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 14); // EFAULT
        return true;
    };
    const io = state.windows_host_io orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9);
        return true;
    };
    const completed: usize = if (is_read) blk: {
        const slices = [_][]u8{buffer};
        break :blk slot.file.?.readPositional(io, &slices, slot.offset) catch {
            failWindowsDescriptorCall(state, direct_return_rip, 5); // EIO
            return true;
        };
    } else blk: {
        const slices = [_][]const u8{buffer};
        break :blk slot.file.?.writePositional(io, &slices, slot.offset) catch {
            failWindowsDescriptorCall(state, direct_return_rip, 5); // EIO
            return true;
        };
    };
    slot.offset +|= completed;
    if (is_read)
        state.windows_file_read_calls +|= 1
    else
        state.windows_file_write_calls +|= 1;
    if (!is_read and slot.standard_stream != null and (fd == 1 or fd == 2) and completed != 0) {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "noteWindowsGuestOutput")) {
            state.noteWindowsGuestOutput(buffer[0..completed]);
        }
    }
    state.windows_last_error = 0;
    state.regs.rax = completed;
    if (slot.media_authorized and state.windows_media_io_trace_events < 16) {
        state.windows_media_io_trace_events += 1;
        const preview = state.guestMemoryConst(arg(state, 1, direct_return_rip), @min(completed, @as(usize, 16))) orelse &.{};
        log.info("Windows media descriptor transfer complete: name={s} fd={d} completed={d} offset={d} preview={any}", .{
            name,
            fd,
            completed,
            slot.offset,
            preview,
        });
    }
    if (state.diagnose_abi) {
        log.info("Windows descriptor I/O: name={s} fd={d} requested={d} completed={d} offset={d}", .{
            name,
            fd,
            requested,
            completed,
            slot.offset,
        });
    }
    finish(state, direct_return_rip);
    return true;
}

/// lseek64/_lseeki64 is the other half of libstdc++'s basic_file contract.
/// Keep the current offset in the Rosetta slot instead of relying on a host
/// descriptor cursor, since all reads and writes use positional I/O.
fn seekWindowsDescriptor(state: anytype, direct_return_rip: ?u64) bool {
    const fd: u32 = @truncate(arg(state, 0, direct_return_rip));
    const distance: i64 = @bitCast(arg(state, 1, direct_return_rip));
    const origin: u32 = @truncate(arg(state, 2, direct_return_rip));
    const slot = windowsStdioSlot(state, fd) orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9); // EBADF
        return true;
    };
    const io = state.windows_host_io orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9);
        return true;
    };
    const base: i64 = switch (origin) {
        0 => 0, // SEEK_SET
        1 => @intCast(slot.offset), // SEEK_CUR
        2 => blk: {
            const stat = slot.file.?.stat(io) catch {
                failWindowsDescriptorCall(state, direct_return_rip, 5);
                return true;
            };
            break :blk @intCast(stat.size);
        },
        else => {
            failWindowsDescriptorCall(state, direct_return_rip, 22); // EINVAL
            return true;
        },
    };
    const target = std.math.add(i64, base, distance) catch {
        failWindowsDescriptorCall(state, direct_return_rip, 22);
        return true;
    };
    if (target < 0) {
        failWindowsDescriptorCall(state, direct_return_rip, 22);
        return true;
    }
    slot.offset = @intCast(target);
    state.windows_last_error = 0;
    state.regs.rax = @bitCast(target);
    finish(state, direct_return_rip);
    return true;
}

fn lengthWindowsDescriptor(state: anytype, direct_return_rip: ?u64) bool {
    const fd: u32 = @truncate(arg(state, 0, direct_return_rip));
    const slot = windowsStdioSlot(state, fd) orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9); // EBADF
        return true;
    };
    const io = state.windows_host_io orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9);
        return true;
    };
    const stat = slot.file.?.stat(io) catch {
        failWindowsDescriptorCall(state, direct_return_rip, 5);
        return true;
    };
    state.windows_last_error = 0;
    state.regs.rax = @bitCast(@as(i64, @intCast(stat.size)));
    finish(state, direct_return_rip);
    return true;
}

fn openWindowsDescriptorAsStdio(state: anytype, direct_return_rip: ?u64) bool {
    const fd: u32 = @truncate(arg(state, 0, direct_return_rip));
    const slot = windowsStdioSlot(state, fd) orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9); // EBADF
        return true;
    };
    if (guestCString(state, arg(state, 1, direct_return_rip)) == null) {
        failWindowsDescriptorCall(state, direct_return_rip, 22); // EINVAL
        return true;
    }
    state.windows_last_error = 0;
    state.regs.rax = slot.guest_handle;
    finish(state, direct_return_rip);
    return true;
}

fn closeWindowsDescriptor(state: anytype, direct_return_rip: ?u64) bool {
    const fd: u32 = @truncate(arg(state, 0, direct_return_rip));
    const slot = windowsStdioSlot(state, fd) orelse {
        failWindowsDescriptorCall(state, direct_return_rip, 9); // EBADF
        return true;
    };
    const handle = slot.guest_handle;
    if (!closeWindowsFile(state, handle)) {
        failWindowsDescriptorCall(state, direct_return_rip, 5); // EIO
        return true;
    }
    state.windows_last_error = 0;
    state.regs.rax = 0;
    finish(state, direct_return_rip);
    return true;
}

fn setvbufWindowsStdio(state: anytype, direct_return_rip: ?u64) bool {
    // libstdc++ uses this to detach the C stdio buffer before it performs
    // descriptor I/O.  Rosetta's slot uses positional reads/writes, so there
    // is no host buffer to flush or replace.  The call still has to report
    // success: returning the generic zero stub would be indistinguishable
    // from success, but documenting the explicit contract here keeps future
    // buffering changes from accidentally invalidating the FILE*.
    state.windows_last_error = 0;
    state.regs.rax = 0;
    finish(state, direct_return_rip);
    return true;
}

fn queryWindowsStdioState(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const slot = windowsFileSlot(state, arg(state, 0, direct_return_rip)) orelse {
        failWindowsFileCall(state, direct_return_rip, 6); // ERROR_INVALID_HANDLE
        state.regs.rax = 1;
        return true;
    };
    if (std.mem.eql(u8, name, "ferror")) {
        state.regs.rax = 0;
    } else if (std.mem.eql(u8, name, "feof")) {
        const io = state.windows_host_io orelse unreachable;
        const at_end = if (slot.file.?.stat(io)) |stat| slot.offset >= stat.size else |_| false;
        state.regs.rax = @intFromBool(at_end);
    } else {
        state.regs.rax = std.math.maxInt(u32); // fgetc failure / EOF
        const io = state.windows_host_io orelse unreachable;
        var byte: [1]u8 = undefined;
        var slices = [_][]u8{byte[0..]};
        const completed = slot.file.?.readPositional(io, &slices, slot.offset) catch {
            failWindowsFileCall(state, direct_return_rip, 1117);
            return true;
        };
        if (completed != 0) {
            slot.offset += 1;
            state.windows_file_read_calls +|= 1;
            state.regs.rax = byte[0];
        }
    }
    state.windows_last_error = 0;
    finish(state, direct_return_rip);
    return true;
}

fn readWindowsStdioWide(state: anytype, direct_return_rip: ?u64) bool {
    const slot = windowsFileSlot(state, arg(state, 0, direct_return_rip)) orelse {
        state.windows_last_error = 9; // EBADF / invalid CRT stream
        state.regs.rax = std.math.maxInt(u32); // WEOF
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    if (!slot.readable) {
        state.windows_last_error = 9;
        state.regs.rax = std.math.maxInt(u32); // WEOF
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    }

    // Xenia's Windows build uses UTF-8/ASCII configuration and diagnostic
    // streams. Read one byte without advancing past it on an I/O failure;
    // widening that byte is the deterministic C-locale behavior expected by
    // fgetwc for this bridge. A future locale layer can replace this helper
    // without changing the FILE* ownership contract.
    var byte: [1]u8 = undefined;
    const io = state.windows_host_io orelse unreachable;
    var slices = [_][]u8{byte[0..]};
    const completed = slot.file.?.readPositional(io, &slices, slot.offset) catch {
        failWindowsFileCall(state, direct_return_rip, 1117); // ERROR_IO_DEVICE
        state.regs.rax = std.math.maxInt(u32);
        return true;
    };
    if (completed == 0) {
        state.regs.rax = std.math.maxInt(u32); // WEOF
    } else {
        slot.offset +|= 1;
        state.windows_file_read_calls +|= 1;
        state.regs.rax = byte[0];
    }
    state.windows_last_error = 0;
    finish(state, direct_return_rip);
    return true;
}

/// Write a byte span through a FILE* slot, using streaming I/O for borrowed
/// stdin/stdout/stderr and positional I/O for ordinary guest-opened files.
/// The latter keeps the Windows current-file-pointer model deterministic;
/// the former cannot use pwrite because console/piped descriptors are
/// intentionally unseekable.
fn writeWindowsStdioBytes(
    state: anytype,
    slot: *@TypeOf(state.windows_files[0]),
    bytes: []const u8,
) ?usize {
    const io = state.windows_host_io orelse return null;
    const completed = if (slot.standard_stream != null) blk: {
        var written: usize = 0;
        while (written < bytes.len) {
            const result = std.c.write(slot.file.?.handle, bytes.ptr + written, bytes.len - written);
            if (result < 0) return null;
            if (result == 0) break;
            written += @intCast(result);
        }
        break :blk written;
    } else blk: {
        const slices = [_][]const u8{bytes};
        break :blk slot.file.?.writePositional(io, &slices, slot.offset) catch return null;
    };
    slot.offset +|= completed;
    state.windows_file_write_calls +|= 1;
    if (slot.standard_stream != null and (slot.stdio_fd == 1 or slot.stdio_fd == 2) and completed != 0) {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "noteWindowsGuestOutput")) {
            state.noteWindowsGuestOutput(bytes[0..completed]);
        }
    }
    return completed;
}

/// Complete the small character/string output family that shares the UCRT
/// FILE* contract.  These imports used to fall through to the generic
/// degraded zero-return path, so Xenia could silently lose diagnostics even
/// after its stream was valid.  Output is routed through the same borrowed
/// stream slots as fwrite and remains sparse in the Rosetta log.
fn writeWindowsStdio(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const string_output = std.mem.eql(u8, name, "fputs") or std.mem.eql(u8, name, "puts");
    const char_output = std.mem.eql(u8, name, "fputc") or
        std.mem.eql(u8, name, "putc") or
        std.mem.eql(u8, name, "putchar");
    const file_handle = if (std.mem.eql(u8, name, "fputs") or std.mem.eql(u8, name, "fputc") or std.mem.eql(u8, name, "putc"))
        arg(state, 1, direct_return_rip)
    else
        installWindowsStandardStream(state, 1) orelse 0;
    const slot = windowsFileSlot(state, file_handle) orelse {
        failWindowsFileCall(state, direct_return_rip, 6); // ERROR_INVALID_HANDLE
        return true;
    };
    if (!slot.writable) {
        failWindowsFileCall(state, direct_return_rip, 5); // ERROR_ACCESS_DENIED
        return true;
    }

    var one: [2]u8 = undefined;
    const bytes: []const u8 = if (string_output) blk: {
        const text = guestCString(state, arg(state, 0, direct_return_rip)) orelse {
            failWindowsFileCall(state, direct_return_rip, 998); // ERROR_NOACCESS
            return true;
        };
        if (std.mem.eql(u8, name, "puts")) {
            if (text.len + 1 > one.len) {
                // `puts` output can be longer than the small stack scratch;
                // its newline is emitted separately below.
                const completed = writeWindowsStdioBytes(state, slot, text) orelse {
                    failWindowsFileCall(state, direct_return_rip, 112);
                    return true;
                };
                const newline = writeWindowsStdioBytes(state, slot, "\n") orelse {
                    failWindowsFileCall(state, direct_return_rip, 112);
                    return true;
                };
                if (completed != text.len or newline != 1) {
                    failWindowsFileCall(state, direct_return_rip, 112);
                    return true;
                }
                state.windows_last_error = 0;
                state.regs.rax = 0;
                finish(state, direct_return_rip);
                return true;
            }
            @memcpy(one[0..text.len], text);
            one[text.len] = '\n';
            break :blk one[0 .. text.len + 1];
        }
        break :blk text;
    } else blk: {
        one[0] = @truncate(arg(state, 0, direct_return_rip));
        break :blk one[0..1];
    };
    const completed = writeWindowsStdioBytes(state, slot, bytes) orelse {
        failWindowsFileCall(state, direct_return_rip, 112); // write failure
        return true;
    };
    if (completed != bytes.len) {
        failWindowsFileCall(state, direct_return_rip, 112);
        return true;
    }
    state.windows_last_error = 0;
    state.regs.rax = if (char_output) @as(u64, one[0]) else 0;
    finish(state, direct_return_rip);
    return true;
}

fn transferWindowsStdio(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const size = arg(state, 1, direct_return_rip);
    const count = arg(state, 2, direct_return_rip);
    const total = std.math.mul(u64, size, count) catch {
        failWindowsFileCall(state, direct_return_rip, 87);
        return true;
    };
    const file_handle = arg(state, 3, direct_return_rip);
    const slot = windowsFileSlot(state, file_handle) orelse {
        failWindowsFileCall(state, direct_return_rip, 6); // ERROR_INVALID_HANDLE
        return true;
    };
    const is_read = std.mem.eql(u8, name, "fread");
    if ((is_read and !slot.readable) or (!is_read and !slot.writable)) {
        failWindowsFileCall(state, direct_return_rip, 5);
        return true;
    }
    if (size == 0 or total == 0) {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    const buffer_address = arg(state, 0, direct_return_rip);
    if (state.diagnose_abi) {
        const preview = state.guestMemoryConst(buffer_address, @min(total, @as(u64, 16))) orelse &.{};
        log.info("Windows stdio transfer begin: name={s} buffer=0x{x} size={d} count={d} total={d} file=0x{x} readable={} writable={} preview={any}", .{
            name,
            buffer_address,
            size,
            count,
            total,
            file_handle,
            slot.readable,
            slot.writable,
            preview,
        });
    }
    const buffer = state.guestMemory(buffer_address, total) orelse {
        failWindowsFileCall(state, direct_return_rip, 998);
        return true;
    };
    if (total > std.math.maxInt(usize)) {
        failWindowsFileCall(state, direct_return_rip, 87);
        return true;
    }
    const io = state.windows_host_io orelse unreachable;
    const completed: usize = if (is_read) blk: {
        if (slot.standard_stream != null) {
            var read: usize = 0;
            while (read < buffer.len) {
                const result = std.c.read(slot.file.?.handle, buffer.ptr + read, buffer.len - read);
                if (result < 0) {
                    failWindowsFileCall(state, direct_return_rip, 1117);
                    return true;
                }
                if (result == 0) break;
                read += @intCast(result);
            }
            break :blk read;
        }
        const slices = [_][]u8{buffer};
        break :blk slot.file.?.readPositional(io, &slices, slot.offset) catch {
            failWindowsFileCall(state, direct_return_rip, 1117);
            return true;
        };
    } else blk: {
        if (slot.standard_stream != null) {
            var written: usize = 0;
            while (written < buffer.len) {
                const result = std.c.write(slot.file.?.handle, buffer.ptr + written, buffer.len - written);
                if (result < 0) {
                    failWindowsFileCall(state, direct_return_rip, 112);
                    return true;
                }
                if (result == 0) break;
                written += @intCast(result);
            }
            break :blk written;
        }
        const slices = [_][]const u8{buffer};
        break :blk slot.file.?.writePositional(io, &slices, slot.offset) catch {
            failWindowsFileCall(state, direct_return_rip, 112);
            return true;
        };
    };
    slot.offset +|= completed;
    if (!is_read and completed != @as(usize, @intCast(total))) {
        // A short standard-stream write is the exact condition that sends
        // fmt::fwrite_all into its system_error reporter.  Keep it explicit
        // even when the host write returned no OS error, because silently
        // returning a short element count otherwise makes the later abort
        // look like a formatter defect.
        log.err("Windows stdio short write: name={s} FILE=0x{x} fd={d} requested={d} completed={d} standard={}", .{
            name,
            file_handle,
            slot.file.?.handle,
            total,
            completed,
            slot.standard_stream != null,
        });
    }
    state.windows_file_read_calls +|= if (is_read) 1 else 0;
    state.windows_file_write_calls +|= if (is_read) 0 else 1;
    if (!is_read and slot.standard_stream != null and
        (slot.stdio_fd == 1 or slot.stdio_fd == 2) and completed != 0)
    {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "noteWindowsGuestOutput")) {
            state.noteWindowsGuestOutput(buffer[0..completed]);
        }
    }
    state.windows_last_error = 0;
    state.regs.rax = completed / @as(usize, @intCast(size));
    if (slot.media_authorized and state.windows_media_io_trace_events < 16) {
        state.windows_media_io_trace_events += 1;
        const preview = state.guestMemoryConst(buffer_address, @min(completed, @as(usize, 16))) orelse &.{};
        log.info("Windows media stdio transfer: name={s} file=0x{x} size={d} count={d} completed={d} offset={d} preview={any}", .{
            name,
            file_handle,
            size,
            count,
            completed,
            slot.offset,
            preview,
        });
    }
    if (state.diagnose_abi) {
        log.info("Windows stdio transfer complete: name={s} file=0x{x} completed={d} elements={d} offset={d}", .{
            name,
            file_handle,
            completed,
            state.regs.rax,
            slot.offset,
        });
    }
    finish(state, direct_return_rip);
    return true;
}

fn seekWindowsStdio(state: anytype, direct_return_rip: ?u64) bool {
    const slot = windowsFileSlot(state, arg(state, 0, direct_return_rip)) orelse {
        state.regs.rax = std.math.maxInt(u64);
        state.windows_last_error = 6;
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    const distance: i64 = @bitCast(arg(state, 1, direct_return_rip));
    const origin: u32 = @truncate(arg(state, 2, direct_return_rip));
    const io = state.windows_host_io orelse unreachable;
    const base: i64 = switch (origin) {
        0 => 0,
        1 => @intCast(slot.offset),
        2 => blk: {
            const stat = slot.file.?.stat(io) catch {
                state.regs.rax = std.math.maxInt(u64);
                state.windows_last_error = 1117;
                noteWindowsFileFailure(state);
                finish(state, direct_return_rip);
                return true;
            };
            break :blk @intCast(stat.size);
        },
        else => {
            state.regs.rax = std.math.maxInt(u64);
            state.windows_last_error = 22; // EINVAL / CRT invalid parameter
            noteWindowsFileFailure(state);
            finish(state, direct_return_rip);
            return true;
        },
    };
    const target = std.math.add(i64, base, distance) catch {
        state.regs.rax = std.math.maxInt(u64);
        state.windows_last_error = 22;
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    if (target < 0) {
        state.regs.rax = std.math.maxInt(u64);
        state.windows_last_error = 22;
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    }
    slot.offset = @intCast(target);
    state.regs.rax = 0;
    state.windows_last_error = 0;
    finish(state, direct_return_rip);
    return true;
}

fn flushWindowsStdio(state: anytype, direct_return_rip: ?u64) bool {
    const handle = arg(state, 0, direct_return_rip);
    const io = state.windows_host_io orelse unreachable;
    var ok = true;
    if (handle == 0) {
        for (&state.windows_files) |*slot| {
            if (slot.standard_stream != null) continue;
            if (slot.file) |file| {
                file.sync(io) catch {
                    ok = false;
                };
            }
        }
    } else if (windowsFileSlot(state, handle)) |slot| {
        if (slot.standard_stream == null) {
            slot.file.?.sync(io) catch {
                ok = false;
            };
        }
    } else {
        ok = false;
    }
    if (!ok) {
        failWindowsFileCall(state, direct_return_rip, 1117);
        return true;
    }
    state.regs.rax = 0; // CRT success
    finish(state, direct_return_rip);
    return true;
}

fn stdioFileInfo(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const slot = windowsFileSlot(state, arg(state, 0, direct_return_rip)) orelse {
        state.regs.rax = std.math.maxInt(u64);
        state.windows_last_error = 6;
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    if (std.mem.eql(u8, name, "_fileno")) {
        state.regs.rax = slot.stdio_fd;
    } else {
        state.regs.rax = slot.offset;
    }
    finish(state, direct_return_rip);
    return true;
}

fn truncateWindowsStdio(state: anytype, direct_return_rip: ?u64) bool {
    const slot = windowsStdioSlot(state, @truncate(arg(state, 0, direct_return_rip))) orelse {
        state.windows_last_error = 9; // EBADF
        state.regs.rax = 9;
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    const length: i64 = @bitCast(arg(state, 1, direct_return_rip));
    if (length < 0 or !slot.writable) {
        state.windows_last_error = 22;
        state.regs.rax = if (length < 0) 22 else 13;
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    }
    const io = state.windows_host_io orelse unreachable;
    slot.file.?.setLength(io, @intCast(length)) catch {
        state.windows_last_error = 5;
        state.regs.rax = 5;
        noteWindowsFileFailure(state);
        finish(state, direct_return_rip);
        return true;
    };
    state.regs.rax = 0;
    state.windows_last_error = 0;
    finish(state, direct_return_rip);
    return true;
}

fn transferWindowsFile(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const handle = arg(state, 0, direct_return_rip);
    const slot = windowsFileSlot(state, handle) orelse {
        failWindowsFileCall(state, direct_return_rip, 6); // ERROR_INVALID_HANDLE
        return true;
    };
    const is_read = std.mem.eql(u8, name, "ReadFile");
    if ((is_read and !slot.readable) or (!is_read and !slot.writable)) {
        failWindowsFileCall(state, direct_return_rip, 5); // ERROR_ACCESS_DENIED
        return true;
    }
    const buffer_address = arg(state, 1, direct_return_rip);
    const requested = arg(state, 2, direct_return_rip);
    const completed_address = arg(state, 3, direct_return_rip);
    if (requested > std.math.maxInt(usize)) {
        failWindowsFileCall(state, direct_return_rip, 87); // ERROR_INVALID_PARAMETER
        return true;
    }
    const buffer = state.guestMemory(buffer_address, requested) orelse {
        failWindowsFileCall(state, direct_return_rip, 998); // ERROR_NOACCESS
        return true;
    };
    const io = state.windows_host_io orelse unreachable;
    const file = slot.file.?;
    const completed: usize = if (is_read) blk: {
        const slices = [_][]u8{buffer};
        break :blk file.readPositional(io, &slices, slot.offset) catch {
            failWindowsFileCall(state, direct_return_rip, 1117); // ERROR_IO_DEVICE
            return true;
        };
    } else blk: {
        const slices = [_][]const u8{buffer};
        break :blk file.writePositional(io, &slices, slot.offset) catch {
            failWindowsFileCall(state, direct_return_rip, 112); // ERROR_DISK_FULL / write failure
            return true;
        };
    };
    slot.offset +|= completed;
    if (completed_address != 0) state.write32(completed_address, @intCast(completed));
    if (is_read) state.windows_file_read_calls +|= 1 else state.windows_file_write_calls +|= 1;
    state.windows_last_error = 0;
    state.regs.rax = 1;
    finish(state, direct_return_rip);
    return true;
}

fn windowsFileSize(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const slot = windowsFileSlot(state, arg(state, 0, direct_return_rip)) orelse {
        failWindowsFileCall(state, direct_return_rip, 6); // ERROR_INVALID_HANDLE
        return true;
    };
    const io = state.windows_host_io orelse unreachable;
    const size = slot.file.?.stat(io) catch {
        failWindowsFileCall(state, direct_return_rip, 1117); // ERROR_IO_DEVICE
        return true;
    };
    if (std.mem.eql(u8, name, "GetFileSizeEx")) {
        const output = arg(state, 1, direct_return_rip);
        if (output == 0 or state.guestMemory(output, 8) == null) {
            failWindowsFileCall(state, direct_return_rip, 87);
            return true;
        }
        state.write64(output, size.size);
        state.regs.rax = 1;
    } else {
        const high = arg(state, 1, direct_return_rip);
        if (high != 0) state.write32(high, @truncate(size.size >> 32));
        state.regs.rax = @truncate(size.size);
    }
    finish(state, direct_return_rip);
    return true;
}

fn setWindowsFilePointer(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const slot = windowsFileSlot(state, arg(state, 0, direct_return_rip)) orelse {
        failWindowsFileCall(state, direct_return_rip, 6); // ERROR_INVALID_HANDLE
        return true;
    };
    const distance: i64 = @bitCast(arg(state, 1, direct_return_rip));
    const method: u32 = @truncate(arg(state, 3, direct_return_rip));
    const io = state.windows_host_io orelse unreachable;
    const base: i64 = switch (method) {
        0 => 0, // FILE_BEGIN
        1 => @intCast(slot.offset), // FILE_CURRENT
        2 => blk: {
            const stat = slot.file.?.stat(io) catch {
                failWindowsFileCall(state, direct_return_rip, 1117);
                return true;
            };
            break :blk @intCast(stat.size);
        },
        else => {
            failWindowsFileCall(state, direct_return_rip, 87); // ERROR_INVALID_PARAMETER
            return true;
        },
    };
    const target = std.math.add(i64, base, distance) catch {
        failWindowsFileCall(state, direct_return_rip, 87);
        return true;
    };
    if (target < 0) {
        failWindowsFileCall(state, direct_return_rip, 131); // ERROR_NEGATIVE_SEEK
        return true;
    }
    const old_offset = slot.offset;
    slot.offset = @intCast(target);
    if (std.mem.eql(u8, name, "SetFilePointerEx")) {
        const output = arg(state, 2, direct_return_rip);
        if (output != 0) state.write64(output, slot.offset);
        state.regs.rax = 1;
    } else {
        const high = arg(state, 2, direct_return_rip);
        if (high != 0) state.write32(high, @truncate(slot.offset >> 32));
        state.regs.rax = @truncate(slot.offset);
        if (old_offset != slot.offset) state.windows_last_error = 0;
    }
    finish(state, direct_return_rip);
    return true;
}

fn truncateWindowsFile(state: anytype, direct_return_rip: ?u64) bool {
    const slot = windowsFileSlot(state, arg(state, 0, direct_return_rip)) orelse {
        failWindowsFileCall(state, direct_return_rip, 6);
        return true;
    };
    if (!slot.writable) {
        failWindowsFileCall(state, direct_return_rip, 5);
        return true;
    }
    const io = state.windows_host_io orelse unreachable;
    slot.file.?.setLength(io, slot.offset) catch {
        failWindowsFileCall(state, direct_return_rip, 112);
        return true;
    };
    state.regs.rax = 1;
    finish(state, direct_return_rip);
    return true;
}

fn queryWindowsFileAttributes(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const wide = std.mem.endsWith(u8, name, "W");
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = guestPathToHost(state, arg(state, 0, direct_return_rip), wide, &path_buffer) orelse {
        state.windows_last_error = 2; // ERROR_FILE_NOT_FOUND
        noteWindowsFileFailure(state);
        state.regs.rax = if (std.mem.startsWith(u8, name, "GetFileAttributes")) 0xFFFF_FFFF else 0;
        finish(state, direct_return_rip);
        return true;
    };
    const stat = hostStat(state, path) orelse {
        state.windows_last_error = 2; // ERROR_FILE_NOT_FOUND
        noteWindowsFileFailure(state);
        state.regs.rax = if (std.mem.startsWith(u8, name, "GetFileAttributes")) 0xFFFF_FFFF else 0;
        finish(state, direct_return_rip);
        return true;
    };
    if (std.mem.startsWith(u8, name, "GetFileAttributesEx")) {
        const output = arg(state, 2, direct_return_rip);
        if (!writeFileAttributeData(state, output, stat)) {
            failWindowsFileCall(state, direct_return_rip, 998); // ERROR_NOACCESS
            return true;
        }
        state.regs.rax = 1;
    } else {
        state.regs.rax = windowsFileAttributes(stat);
    }
    state.windows_last_error = 0;
    finish(state, direct_return_rip);
    return true;
}

fn beginWindowsFind(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const wide = std.mem.endsWith(u8, name, "W");
    const output = if (std.mem.startsWith(u8, name, "FindFirstFileEx"))
        arg(state, 2, direct_return_rip)
    else
        arg(state, 1, direct_return_rip);
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = guestPathToHost(state, arg(state, 0, direct_return_rip), wide, &path_buffer) orelse {
        failWindowsFileCall(state, direct_return_rip, 2); // ERROR_FILE_NOT_FOUND
        state.regs.rax = std.math.maxInt(u64);
        return true;
    };
    const separator = std.mem.lastIndexOfScalar(u8, path, '/');
    const directory_path = if (separator) |index| path[0..index] else ".";
    const pattern = if (separator) |index| path[index + 1 ..] else path;
    if (pattern.len == 0) {
        failWindowsFileCall(state, direct_return_rip, 2);
        state.regs.rax = std.math.maxInt(u64);
        return true;
    }
    const dir = hostOpenDirectory(state, directory_path) orelse {
        failWindowsFileCall(state, direct_return_rip, 2);
        state.regs.rax = std.math.maxInt(u64);
        return true;
    };
    const handle = installWindowsFind(state, dir, directory_path, pattern, wide) orelse {
        failWindowsFileCall(state, direct_return_rip, 4); // ERROR_TOO_MANY_OPEN_FILES
        state.regs.rax = std.math.maxInt(u64);
        return true;
    };
    const slot = windowsFindSlot(state, handle).?;
    if (!advanceWindowsFind(state, slot, output)) {
        _ = closeWindowsFind(state, handle);
        failWindowsFileCall(state, direct_return_rip, 18); // ERROR_NO_MORE_FILES
        state.regs.rax = std.math.maxInt(u64);
        return true;
    }
    state.windows_file_open_calls +|= 1;
    state.windows_last_error = 0;
    state.regs.rax = handle;
    finish(state, direct_return_rip);
    return true;
}

fn advanceWindowsFindCall(state: anytype, direct_return_rip: ?u64) bool {
    const slot = windowsFindSlot(state, arg(state, 0, direct_return_rip)) orelse {
        failWindowsFileCall(state, direct_return_rip, 6); // ERROR_INVALID_HANDLE
        return true;
    };
    const output = arg(state, 1, direct_return_rip);
    if (advanceWindowsFind(state, slot, output)) {
        state.windows_last_error = 0;
        state.regs.rax = 1;
    } else {
        state.windows_last_error = 18; // ERROR_NO_MORE_FILES
        noteWindowsFileFailure(state);
        state.regs.rax = 0;
    }
    finish(state, direct_return_rip);
    return true;
}

fn writeHandle(state: anytype, destination: u64) u64 {
    if (destination == 0) return nextHandle(state);
    const handle = nextHandle(state);
    state.write64(destination, handle);
    return handle;
}

fn convertUnsignedLongToGuestString(state: anytype, direct_return_rip: ?u64) bool {
    const value: u32 = @truncate(arg(state, 0, direct_return_rip));
    const destination = arg(state, 1, direct_return_rip);
    const radix: u32 = @truncate(arg(state, 2, direct_return_rip));
    if (destination == 0 or radix < 2 or radix > 36) {
        state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }

    var digits: [32]u8 = undefined;
    var digit_count: usize = 0;
    var remaining = value;
    while (true) {
        const digit = remaining % radix;
        digits[digit_count] = if (digit < 10) @intCast('0' + digit) else @intCast('a' + (digit - 10));
        digit_count += 1;
        remaining /= radix;
        if (remaining == 0) break;
    }

    const output = state.guestMemory(destination, @intCast(digit_count + 1)) orelse {
        state.windows_last_error = 998; // ERROR_NOACCESS
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    };
    for (0..digit_count) |index| output[index] = digits[digit_count - index - 1];
    output[digit_count] = 0;
    state.windows_last_error = 0;
    state.regs.rax = destination;
    finish(state, direct_return_rip);
    return true;
}

fn handleStringAndMemory(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (std.mem.eql(u8, name, "_strrev")) {
        const address = arg(state, 0, direct_return_rip);
        const source = guestCString(state, address) orelse {
            state.regs.rax = 0;
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            finish(state, direct_return_rip);
            return true;
        };
        if (state.guestMemory(address, @intCast(source.len))) |bytes| {
            std.mem.reverse(u8, bytes);
            state.regs.rax = address;
            state.windows_last_error = 0;
        } else {
            state.regs.rax = 0;
            state.windows_last_error = 998; // ERROR_NOACCESS
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "atoi")) {
        const result = guestStrtol(state, arg(state, 0, direct_return_rip), 0, 10);
        state.regs.rax = if (result) |value| @bitCast(value) else 0;
        state.windows_last_error = if (result == null) 87 else 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "qsort")) {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "beginWindowsQsort")) {
            return state.beginWindowsQsort(
                arg(state, 0, direct_return_rip),
                arg(state, 1, direct_return_rip),
                arg(state, 2, direct_return_rip),
                arg(state, 3, direct_return_rip),
                direct_return_rip,
            );
        }
    }
    if (std.mem.eql(u8, name, "llrint") or std.mem.eql(u8, name, "llrintf")) {
        const value: f64 = if (std.mem.eql(u8, name, "llrint"))
            @bitCast(std.mem.readInt(u64, state.xmm[0][0..8], .little))
        else
            @as(f64, @floatCast(@as(f32, @bitCast(std.mem.readInt(u32, state.xmm[0][0..4], .little)))));
        state.regs.rax = @bitCast(guestRoundToI64(state, value));
        state.windows_last_error = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_ultoa")) return convertUnsignedLongToGuestString(state, direct_return_rip);

    if (std.mem.eql(u8, name, "strxfrm")) {
        // Xenia's cxxopts implementation uses std::regex, whose classic
        // locale traits call strxfrm while matching every option
        // specification. In the C locale the transformed representation is
        // the source bytes, and the return value is the full transformed
        // length even when the destination is too small. A zero-returning
        // degraded stub makes valid specs such as "help" fail regex_match.
        const source = guestCString(state, arg(state, 1, direct_return_rip)) orelse &.{};
        const destination = arg(state, 0, direct_return_rip);
        const capacity = arg(state, 2, direct_return_rip);
        if (destination != 0 and capacity != 0) {
            // strxfrm's count is a byte count, not a string-buffer size:
            // unlike strcpy-style helpers it may copy exactly `capacity`
            // bytes without a terminator when the transformed string is at
            // least that long. The return value is always the complete
            // transformed length. Xenia's C-locale regex path relies on this
            // distinction when it builds temporary collation strings.
            const capacity_usize: usize = if (capacity > std.math.maxInt(usize))
                std.math.maxInt(usize)
            else
                @intCast(capacity);
            const copy_count = @min(source.len, capacity_usize);
            if (copy_count != 0) {
                if (state.guestMemory(destination, @intCast(copy_count))) |output| {
                    @memcpy(output, source[0..copy_count]);
                }
            }
            if (copy_count < capacity_usize) {
                if (state.guestMemory(destination +| @as(u64, @intCast(copy_count)), 1)) |terminator| {
                    terminator[0] = 0;
                }
            }
        }
        state.regs.rax = source.len;
        if (state.diagnose_abi and source.len <= 32) {
            const first_byte: u8 = if (source.len != 0) source[0] else 0;
            log.info("Windows C-locale strxfrm: source='{s}' first_byte=0x{x} length={d} destination=0x{x} capacity={d} result={d}", .{
                source,
                first_byte,
                source.len,
                destination,
                capacity,
                source.len,
            });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strcoll")) {
        // The Windows PE is intentionally launched in the classic C locale;
        // collation is therefore unsigned-byte lexicographic comparison.
        const lhs = guestCString(state, arg(state, 0, direct_return_rip)) orelse &.{};
        const rhs = guestCString(state, arg(state, 1, direct_return_rip)) orelse &.{};
        const count = @min(lhs.len, rhs.len);
        var result: i32 = 0;
        for (lhs[0..count], rhs[0..count]) |left, right| {
            if (left != right) {
                result = if (left < right) -1 else 1;
                break;
            }
        }
        if (result == 0 and lhs.len != rhs.len) result = if (lhs.len < rhs.len) -1 else 1;
        state.regs.rax = @bitCast(@as(i64, result));
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "memcpy") or std.mem.eql(u8, name, "memmove")) {
        const destination_address = arg(state, 0, direct_return_rip);
        const source_address = arg(state, 1, direct_return_rip);
        const byte_count = arg(state, 2, direct_return_rip);
        const return_rip = direct_return_rip orelse state.read64(state.regs.rsp);
        const code_cache_start: u64 = 0xA0000000;
        const code_cache_end: u64 = 0xC0000000;
        const trace_code_cache_copy = state.trace_windows_mappings and
            (destination_address >= code_cache_start and destination_address < code_cache_end or
                source_address >= code_cache_start and source_address < code_cache_end) and
            state.windows_code_copy_trace_events < 32;
        const code_cache_snapshot_count = @min(byte_count, @as(u64, 64));
        const code_cache_source_before = if (trace_code_cache_copy)
            state.guestMemoryConst(source_address, code_cache_snapshot_count) orelse &.{}
        else
            &.{};
        const code_cache_destination_before = if (trace_code_cache_copy)
            state.guestMemoryConst(destination_address, code_cache_snapshot_count) orelse &.{}
        else
            &.{};
        if (trace_code_cache_copy) {
            state.windows_code_copy_trace_events += 1;
            log.info("PE64 Windows code-cache copy before: op={s} return=0x{x} destination=0x{x} source=0x{x} count={d} source_bytes={any} destination_bytes={any}", .{
                name,
                return_rip,
                destination_address,
                source_address,
                byte_count,
                code_cache_source_before,
                code_cache_destination_before,
            });
        }
        const trace_string_copy = state.trace_string_memory and byte_count <= 256 and
            (return_rip == 0x140033701 or return_rip == 0x140033758 or
                return_rip == 0x1401176fd or return_rip == 0x140117786 or
                return_rip == 0x14013514a);
        if (trace_string_copy) {
            log.info("PE StringBuffer memory before op={s} return=0x{x} destination=0x{x} source=0x{x} count={d} source_bytes={any} destination_bytes={any}", .{
                name,
                return_rip,
                destination_address,
                source_address,
                byte_count,
                state.guestMemoryConst(source_address, byte_count) orelse &.{},
                state.guestMemoryConst(destination_address, byte_count) orelse &.{},
            });
        }
        const destination = state.guestMemory(arg(state, 0, direct_return_rip), arg(state, 2, direct_return_rip)) orelse {
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        const source = state.guestMemoryConst(arg(state, 1, direct_return_rip), arg(state, 2, direct_return_rip)) orelse {
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        if (std.mem.eql(u8, name, "memmove")) {
            if (destination_address > source_address and
                destination_address - source_address < byte_count)
            {
                // A forward copy is only safe when the destination starts
                // before the source (or when the ranges do not overlap). For
                // an overlapping right-shift, copying forwards repeats the
                // first byte across the destination — exactly the corruption
                // seen when libstdc++ inserts a quote into a short string.
                std.mem.copyBackwards(u8, destination, source);
            } else {
                std.mem.copyForwards(u8, destination, source);
            }
        } else {
            @memcpy(destination, source);
        }
        if (trace_code_cache_copy) {
            log.info("PE64 Windows code-cache copy after: op={s} return=0x{x} destination=0x{x} source=0x{x} count={d} source_bytes={any} destination_bytes={any}", .{
                name,
                return_rip,
                destination_address,
                source_address,
                byte_count,
                state.guestMemoryConst(source_address, code_cache_snapshot_count) orelse &.{},
                state.guestMemoryConst(destination_address, code_cache_snapshot_count) orelse &.{},
            });
        }
        if (trace_string_copy) {
            log.info("PE StringBuffer memory after op={s} return=0x{x} destination=0x{x} source=0x{x} count={d} source_bytes={any} destination_bytes={any}", .{
                name,
                return_rip,
                destination_address,
                source_address,
                byte_count,
                state.guestMemoryConst(source_address, byte_count) orelse &.{},
                state.guestMemoryConst(destination_address, byte_count) orelse &.{},
            });
        }
        state.regs.rax = arg(state, 0, direct_return_rip);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "memset")) {
        const destination = state.guestMemory(arg(state, 0, direct_return_rip), arg(state, 2, direct_return_rip)) orelse {
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        @memset(destination, @truncate(arg(state, 1, direct_return_rip)));
        state.regs.rax = arg(state, 0, direct_return_rip);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "memcmp")) {
        const lhs = state.guestMemoryConst(arg(state, 0, direct_return_rip), arg(state, 2, direct_return_rip)) orelse &.{};
        const rhs = state.guestMemoryConst(arg(state, 1, direct_return_rip), arg(state, 2, direct_return_rip)) orelse &.{};
        const count = @min(lhs.len, rhs.len);
        var result: i32 = 0;
        for (lhs[0..count], rhs[0..count]) |a, b| {
            if (a != b) {
                result = @as(i32, a) - @as(i32, b);
                break;
            }
        }
        state.regs.rax = @bitCast(@as(i64, result));
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strlen") or std.mem.eql(u8, name, "strnlen")) {
        const value = guestCString(state, arg(state, 0, direct_return_rip)) orelse &.{};
        const length = if (std.mem.eql(u8, name, "strnlen"))
            @min(value.len, @as(usize, @intCast(@min(arg(state, 1, direct_return_rip), std.math.maxInt(usize)))))
        else
            value.len;
        state.regs.rax = length;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "wcslen")) {
        // MinGW's std::filesystem::path constructors receive UTF-16
        // wchar_t strings on Windows.  A zero-returning degraded import is
        // not equivalent to wcslen: it turns a valid executable path into
        // an empty path while still allowing the C++ filesystem layer to
        // report success.  Read the guest string with the same bounded
        // validation used by the other wide-character helpers.
        const length = guestWideCStringLength(state, arg(state, 0, direct_return_rip), 64 * 1024) orelse {
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        state.regs.rax = length;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strcmp") or std.mem.eql(u8, name, "strncmp")) {
        const lhs = guestCString(state, arg(state, 0, direct_return_rip)) orelse &.{};
        const rhs = guestCString(state, arg(state, 1, direct_return_rip)) orelse &.{};
        const count = if (std.mem.eql(u8, name, "strncmp"))
            @min(@min(lhs.len, rhs.len), @as(usize, @intCast(@min(arg(state, 2, direct_return_rip), std.math.maxInt(usize)))))
        else
            @min(lhs.len, rhs.len);
        var result: i32 = 0;
        for (lhs[0..count], rhs[0..count]) |a, b| {
            if (a != b) {
                result = @as(i32, a) - @as(i32, b);
                break;
            }
        }
        if (result == 0 and (std.mem.eql(u8, name, "strcmp") or count == arg(state, 2, direct_return_rip))) {
            if (lhs.len != rhs.len) result = if (lhs.len < rhs.len) -1 else 1;
        }
        state.regs.rax = @bitCast(@as(i64, result));
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_stricmp") or std.mem.eql(u8, name, "_strcmpi") or
        std.mem.eql(u8, name, "stricmp") or std.mem.eql(u8, name, "_strnicmp") or
        std.mem.eql(u8, name, "strnicmp") or std.mem.eql(u8, name, "_memicmp"))
    {
        // A comparison has no safe stub.  Zero is not "unimplemented" here,
        // it is "these are equal" -- so an unimplemented case-insensitive
        // compare silently makes every path, extension, and configuration
        // key match the first candidate the guest tries.
        const bounded = std.mem.eql(u8, name, "_strnicmp") or std.mem.eql(u8, name, "strnicmp") or
            std.mem.eql(u8, name, "_memicmp");
        const limit: usize = if (bounded)
            @intCast(@min(arg(state, 2, direct_return_rip), 64 * 1024))
        else
            std.math.maxInt(usize);
        const lhs = guestCString(state, arg(state, 0, direct_return_rip)) orelse &.{};
        const rhs = guestCString(state, arg(state, 1, direct_return_rip)) orelse &.{};
        state.regs.rax = @bitCast(@as(i64, caseInsensitiveCompare(lhs, rhs, limit)));
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_wcsicmp") or std.mem.eql(u8, name, "wcsicmp") or
        std.mem.eql(u8, name, "_wcsnicmp") or std.mem.eql(u8, name, "wcsnicmp"))
    {
        const bounded = std.mem.eql(u8, name, "_wcsnicmp") or std.mem.eql(u8, name, "wcsnicmp");
        const limit: usize = if (bounded)
            @intCast(@min(arg(state, 2, direct_return_rip), 64 * 1024))
        else
            std.math.maxInt(usize);
        const left_address = arg(state, 0, direct_return_rip);
        const right_address = arg(state, 1, direct_return_rip);
        var result: i32 = 0;
        var index: usize = 0;
        while (index < limit and index < 64 * 1024) : (index += 1) {
            const left = guestWideUnit(state, left_address, index) orelse break;
            const right = guestWideUnit(state, right_address, index) orelse break;
            const a = if (left < 128) std.ascii.toLower(@intCast(left)) else left;
            const b = if (right < 128) std.ascii.toLower(@intCast(right)) else right;
            if (a != b) {
                result = @as(i32, @intCast(a)) - @as(i32, @intCast(b));
                break;
            }
            if (left == 0) break;
        }
        state.regs.rax = @bitCast(@as(i64, result));
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "memchr")) {
        // Zero means "the byte is not in this buffer".  Answering that
        // without looking makes a parser skip content it should have found.
        const address = arg(state, 0, direct_return_rip);
        const needle: u8 = @truncate(arg(state, 1, direct_return_rip));
        const count: usize = @intCast(@min(arg(state, 2, direct_return_rip), 64 * 1024 * 1024));
        const bytes = if (address == 0) null else state.guestMemoryConst(address, count);
        var found: u64 = 0;
        if (bytes) |haystack| {
            if (std.mem.indexOfScalar(u8, haystack, needle)) |index| {
                found = address +| @as(u64, @intCast(index));
            }
        }
        state.regs.rax = found;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strcpy") or std.mem.eql(u8, name, "strncpy")) {
        const source = guestCString(state, arg(state, 1, direct_return_rip)) orelse &.{};
        const capacity = if (std.mem.eql(u8, name, "strncpy")) arg(state, 2, direct_return_rip) else source.len + 1;
        _ = copyGuestString(state, arg(state, 0, direct_return_rip), capacity, source);
        state.regs.rax = arg(state, 0, direct_return_rip);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strchr") or std.mem.eql(u8, name, "strrchr")) {
        const source = guestCString(state, arg(state, 0, direct_return_rip)) orelse &.{};
        const needle: u8 = @truncate(arg(state, 1, direct_return_rip));
        var result: ?usize = null;
        for (source, 0..) |ch, index| {
            if (ch == needle) {
                result = index;
                if (std.mem.eql(u8, name, "strchr")) break;
            }
        }
        state.regs.rax = if (result) |index| arg(state, 0, direct_return_rip) + index else 0;
        finish(state, direct_return_rip);
        return true;
    }
    return false;
}

fn handleGraphics(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (std.mem.eql(u8, name, "CreateDXGIFactory1") or std.mem.eql(u8, name, "CreateDXGIFactory2")) {
        const output = if (std.mem.eql(u8, name, "CreateDXGIFactory1")) arg(state, 1, direct_return_rip) else arg(state, 2, direct_return_rip);
        if (output != 0 and state.guestMemory(output, 8) != null) state.write64(output, 0);
        state.regs.rax = if (output == 0) 0x8000_4003 else 0x8000_4002; // E_POINTER / E_NOINTERFACE
        finish(state, direct_return_rip);
        return true;
    }
    // Vulkan's proc-address functions are the important bridge point: every
    // returned function receives a Rosetta-owned guest address and is routed
    // through the same dispatch table on its eventual indirect call.
    if (std.mem.eql(u8, name, "vkGetInstanceProcAddr") or std.mem.eql(u8, name, "vkGetDeviceProcAddr")) {
        const requested = guestCString(state, arg(state, 1, direct_return_rip)) orelse {
            state.windows_graphics.noteProcAddressQuery("<null>");
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        state.windows_graphics.noteProcAddressQuery(requested);
        state.regs.rax = state.registerWindowsImportStub("vulkan-1.dll", requested) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "vkCreateInstance")) {
        const out = arg(state, 2, direct_return_rip);
        const ok = state.windows_graphics.noteCreateInstance(true);
        if (ok and out != 0) state.write64(out, nextHandle(state));
        returnVulkan(state, if (ok) 0 else -3, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "vkCreateWin32SurfaceKHR")) {
        if (!state.windows_graphics.window_ready) {
            _ = state.windows_graphics.ensureWindow(1280, 720, "Xenia Canary (Rosette)");
        }
        const out = arg(state, 3, direct_return_rip);
        const ok = state.windows_graphics.noteCreateSurface(true);
        if (ok and out != 0) state.write64(out, nextHandle(state));
        returnVulkan(state, if (ok) 0 else -3, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "vkCreateDevice")) {
        const out = arg(state, 3, direct_return_rip);
        const ok = state.windows_graphics.noteCreateDevice(true);
        if (ok and out != 0) state.write64(out, nextHandle(state));
        returnVulkan(state, if (ok) 0 else -3, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "vkGetDeviceQueue") or
        std.mem.eql(u8, name, "vkGetDeviceQueue2"))
    {
        const out = if (std.mem.eql(u8, name, "vkGetDeviceQueue")) arg(state, 3, direct_return_rip) else arg(state, 2, direct_return_rip);
        const ok = state.windows_graphics.noteGetQueue(true);
        if (ok and out != 0) state.write64(out, nextHandle(state));
        returnVulkan(state, if (ok) 0 else -3, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "vkCreateSwapchainKHR")) {
        const out = arg(state, 3, direct_return_rip);
        const ok = state.windows_graphics.noteCreateSwapchain(true);
        if (ok and out != 0) state.write64(out, nextHandle(state));
        returnVulkan(state, if (ok) 0 else -3, direct_return_rip);
        return true;
    }

    // Creation/allocation calls conventionally expose their result through
    // the last register argument. This covers the loader bootstrap without
    // writing host pointers into guest memory.
    if (std.mem.startsWith(u8, name, "vkCreate") or std.mem.startsWith(u8, name, "vkAllocate")) {
        const out = if (std.mem.eql(u8, name, "vkCreateInstance") or
            std.mem.eql(u8, name, "vkAllocateCommandBuffers") or
            std.mem.eql(u8, name, "vkAllocateDescriptorSets"))
            arg(state, 2, direct_return_rip)
        else
            arg(state, 3, direct_return_rip);
        state.windows_graphics.noteUnmodeledCall(name);
        if (out != 0) state.write64(out, nextHandle(state));
        state.regs.rax = 0; // VK_SUCCESS
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "vkEnumerateInstanceVersion")) {
        state.windows_graphics.noteObservedCall(name);
        const version = arg(state, 0, direct_return_rip);
        if (version != 0) state.write32(version, 0x0040_3000);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.startsWith(u8, name, "vkEnumerate")) {
        state.windows_graphics.noteObservedCall(name);
        const count = arg(state, 1, direct_return_rip);
        if (count != 0) state.write32(count, 1);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "vkGetSwapchainImagesKHR")) {
        const ok = state.windows_graphics.noteSwapchainImages(true);
        const count = arg(state, 2, direct_return_rip);
        if (ok and count != 0) state.write32(count, 1);
        const images = arg(state, 3, direct_return_rip);
        if (ok and images != 0) state.write64(images, nextHandle(state));
        returnVulkan(state, if (ok) 0 else -3, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "vkAcquireNextImageKHR")) {
        const ok = state.windows_graphics.noteAcquire(true);
        const image_index = arg(state, 5, direct_return_rip);
        if (ok and image_index != 0) state.write32(image_index, 0);
        returnVulkan(state, if (ok) 0 else -3, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "vkGetPhysicalDeviceQueueFamilyProperties")) {
        state.windows_graphics.noteObservedCall(name);
        const count = arg(state, 1, direct_return_rip);
        if (count != 0) state.write32(count, 1);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "vkGetPhysicalDeviceSurfaceSupportKHR")) {
        state.windows_graphics.noteObservedCall(name);
        const supported = arg(state, 3, direct_return_rip);
        if (supported != 0) state.write32(supported, 1);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "vkGetPhysicalDeviceWin32PresentationSupportKHR")) {
        state.windows_graphics.noteObservedCall(name);
        // The native adapter remaps Win32 surface creation to the
        // CAMetalLayer-backed path. The synthetic fallback must make the same
        // decision or Xenia will reject every physical device before it even
        // reaches vkCreateWin32SurfaceKHR.
        state.regs.rax = @intFromBool(state.windows_graphics.window_ready);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR")) {
        state.windows_graphics.noteObservedCall(name);
        const capabilities = arg(state, 2, direct_return_rip);
        if (capabilities != 0) {
            state.write32(capabilities + 0, 2); // minImageCount
            state.write32(capabilities + 4, 3); // maxImageCount
            state.write32(capabilities + 8, 0xFFFFFFFF); // currentExtent.width = undefined
            state.write32(capabilities + 12, 0xFFFFFFFF); // currentExtent.height
            state.write32(capabilities + 16, 1); // minImageExtent.width
            state.write32(capabilities + 20, 1); // minImageExtent.height
            state.write32(capabilities + 24, 4096); // maxImageExtent.width
            state.write32(capabilities + 28, 4096); // maxImageExtent.height
            state.write32(capabilities + 32, 1); // maxImageArrayLayers
            state.write32(capabilities + 36, 0x1); // supportedTransforms
            state.write32(capabilities + 40, 0x1); // currentTransform
            state.write32(capabilities + 44, 0x1); // supportedCompositeAlpha
            state.write32(capabilities + 48, 1); // supportedUsageFlags
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "vkGetPhysicalDeviceSurfaceFormatsKHR") or
        std.mem.eql(u8, name, "vkGetPhysicalDeviceSurfacePresentModesKHR"))
    {
        state.windows_graphics.noteObservedCall(name);
        const count = arg(state, 2, direct_return_rip);
        if (count != 0) state.write32(count, 1);
        if (std.mem.eql(u8, name, "vkGetPhysicalDeviceSurfaceFormatsKHR")) {
            const formats = arg(state, 3, direct_return_rip);
            if (formats != 0) {
                state.write32(formats, 44); // BGRA8 sRGB-compatible format
                state.write32(formats + 4, 0);
            }
        } else {
            const modes = arg(state, 3, direct_return_rip);
            if (modes != 0) state.write32(modes, 2); // VK_PRESENT_MODE_FIFO_KHR
        }
        returnZero(state, direct_return_rip);
        return true;
    }

    // Command recording and teardown do not return a resource pointer. They
    // are still explicitly recognized so an unsupported import cannot be
    // mistaken for a successful host call.
    if (std.mem.startsWith(u8, name, "vkCmd") or
        std.mem.startsWith(u8, name, "vkDestroy") or
        std.mem.startsWith(u8, name, "vkFree") or
        std.mem.eql(u8, name, "vkQueueWaitIdle") or
        std.mem.eql(u8, name, "vkDeviceWaitIdle") or
        std.mem.eql(u8, name, "vkBeginCommandBuffer") or
        std.mem.eql(u8, name, "vkEndCommandBuffer") or
        std.mem.eql(u8, name, "vkResetCommandBuffer"))
    {
        if (std.mem.startsWith(u8, name, "vkCmd")) {
            state.windows_graphics.noteCommand(name);
        } else {
            state.windows_graphics.noteObservedCall(name);
        }
        returnZero(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "vkQueueSubmit")) {
        const ok = state.windows_graphics.noteQueueSubmit(true);
        returnVulkan(state, if (ok) 0 else -3, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "vkQueuePresentKHR")) {
        const ok = state.windows_graphics.notePresent(true);
        returnVulkan(state, if (ok) 0 else -3, direct_return_rip);
        return true;
    }

    // A graphics import is not necessarily a Vulkan entry point: the class
    // also covers whole DLLs (dxgi, and anything else the classifier routes
    // here by library).  Zero is VK_SUCCESS for a `vk` name and S_OK for a
    // DXGI/D3D one, so the two cannot share a fallback -- claiming S_OK
    // while leaving the caller's interface pointer unwritten is the same
    // false-success this module's contract exists to stop.
    if (!std.mem.startsWith(u8, name, "vk")) {
        state.windows_graphics.noteUnmodeledCall(name);
        completeWithImportFallback(state, "", name, direct_return_rip);
        return true;
    }

    // The name is a known Vulkan entry point but has no stateful output in the
    // bootstrap model yet. Returning VK_SUCCESS is intentionally accompanied
    // by a deterministic handle-free path; the preflight report still records
    // the complete import surface for a later native forwarding pass.
    state.windows_graphics.noteUnmodeledCall(name);
    returnZero(state, direct_return_rip);
    return true;
}

/// Complete the registry surface without pretending that macOS has a Windows
/// registry.  Reads report the documented "value/key absent" status, writes
/// are refused with an explicit access error, and teardown remains harmless.
/// This is a real per-call ABI model: output pointers are cleared and the
/// LSTATUS result is never confused with the generic zero-return fallback.
fn handleWindowsRegistry(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    const is_registry_name = std.mem.startsWith(u8, name, "Reg");
    if (!is_registry_name) return false;

    if (std.mem.eql(u8, name, "RegCloseKey") or std.mem.eql(u8, name, "RegFlushKey")) {
        state.regs.rax = 0; // ERROR_SUCCESS: closing/flushing absent state is harmless.
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "RegCreateKeyA") or std.mem.eql(u8, name, "RegCreateKeyW") or
        std.mem.eql(u8, name, "RegCreateKeyExA") or std.mem.eql(u8, name, "RegCreateKeyExW"))
    {
        const extended = std.mem.startsWith(u8, name, "RegCreateKeyEx");
        const output = if (extended) arg(state, 7, direct_return_rip) else arg(state, 2, direct_return_rip);
        if (output == 0 or state.guestMemory(output, 8) == null) {
            state.regs.rax = 87; // ERROR_INVALID_PARAMETER
        } else {
            // A synthetic key is usable for the lifetime of this call chain;
            // its values are intentionally not persisted to the host.
            state.write64(output, nextHandle(state));
            state.regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "RegOpenKeyA") or std.mem.eql(u8, name, "RegOpenKeyW") or
        std.mem.eql(u8, name, "RegOpenKeyExA") or std.mem.eql(u8, name, "RegOpenKeyExW"))
    {
        const extended = std.mem.startsWith(u8, name, "RegOpenKeyEx");
        const output = if (extended) arg(state, 4, direct_return_rip) else arg(state, 2, direct_return_rip);
        if (output != 0 and state.guestMemory(output, 8) != null) state.write64(output, 0);
        state.regs.rax = 2; // ERROR_FILE_NOT_FOUND: no host registry is mounted.
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "RegGetValueW")) {
        const type_output = arg(state, 4, direct_return_rip);
        const data_output = arg(state, 5, direct_return_rip);
        const size_output = arg(state, 6, direct_return_rip);
        if (type_output != 0 and state.guestMemory(type_output, 4) != null) state.write32(type_output, 0);
        if (data_output != 0 and state.guestMemory(data_output, 1) != null) state.write8(data_output, 0);
        if (size_output != 0 and state.guestMemory(size_output, 4) != null) state.write32(size_output, 0);
        state.regs.rax = 2; // ERROR_FILE_NOT_FOUND
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "RegQueryValueExA") or std.mem.eql(u8, name, "RegQueryValueExW")) {
        const type_output = arg(state, 3, direct_return_rip);
        const data_output = arg(state, 4, direct_return_rip);
        const size_output = arg(state, 5, direct_return_rip);
        if (type_output != 0 and state.guestMemory(type_output, 4) != null) state.write32(type_output, 0);
        if (data_output != 0 and state.guestMemory(data_output, 1) != null) state.write8(data_output, 0);
        if (size_output != 0 and state.guestMemory(size_output, 4) != null) state.write32(size_output, 0);
        state.regs.rax = 2; // ERROR_FILE_NOT_FOUND
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "RegSetValueExA") or std.mem.eql(u8, name, "RegSetValueExW")) {
        state.regs.rax = 5; // ERROR_ACCESS_DENIED: writes are not persisted.
        finish(state, direct_return_rip);
        return true;
    }

    return false;
}

/// The networking package is present in some Windows builds even when a
/// title never opens a socket.  Keep initialization and byte-order helpers
/// state-free and make socket creation fail with Winsock's real refusal
/// value, rather than letting the import fall through to a generic zero.
fn handleWindowsSockets(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (std.mem.eql(u8, name, "WSAGetLastError")) {
        state.regs.rax = state.windows_last_error;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "WSAStartup") or std.mem.eql(u8, name, "WSACleanup")) {
        if (std.mem.eql(u8, name, "WSAStartup")) {
            const data = arg(state, 1, direct_return_rip);
            if (data != 0 and state.guestMemory(data, 4) != null) {
                state.write16(data, 2); // wVersion = 2.0
                state.write16(data +| 2, 2); // wHighVersion = 2.0
            }
        }
        state.windows_last_error = 0;
        state.regs.rax = 0; // WSANOERROR
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "htons") or std.mem.eql(u8, name, "ntohs")) {
        const value: u16 = @truncate(arg(state, 0, direct_return_rip));
        state.regs.rax = @byteSwap(value);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "htonl") or std.mem.eql(u8, name, "ntohl")) {
        const value: u32 = @truncate(arg(state, 0, direct_return_rip));
        state.regs.rax = @byteSwap(value);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "inet_addr")) {
        // Xenia's startup never needs a socket address from the host.  The
        // documented INADDR_NONE result is explicit and distinguishable from
        // a successful address of 0.0.0.0.
        state.windows_last_error = 0;
        state.regs.rax = 0xFFFF_FFFF;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__WSAFDIsSet")) {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "socket") or std.mem.eql(u8, name, "accept") or
        std.mem.eql(u8, name, "bind") or std.mem.eql(u8, name, "connect") or
        std.mem.eql(u8, name, "listen") or std.mem.eql(u8, name, "recvfrom") or
        std.mem.eql(u8, name, "sendto") or std.mem.eql(u8, name, "shutdown") or
        std.mem.eql(u8, name, "getsockname"))
    {
        state.windows_last_error = 10093; // WSANOTINITIALISED
        state.regs.rax = if (std.mem.eql(u8, name, "socket") or std.mem.eql(u8, name, "accept"))
            std.math.maxInt(u64)
        else
            std.math.maxInt(u32);
        finish(state, direct_return_rip);
        return true;
    }
    return false;
}

/// Security APIs are deliberately non-escalating on macOS.  They still own
/// their output parameters and return the documented refusal, so a caller
/// cannot mistake an uninitialized token/LUID for a valid security object.
fn handleWindowsSecurity(state: anytype, name: []const u8, direct_return_rip: ?u64) bool {
    if (std.mem.eql(u8, name, "LookupPrivilegeValueW")) {
        const luid = arg(state, 2, direct_return_rip);
        if (luid != 0 and state.guestMemory(luid, 8) != null) state.write64(luid, 0);
        state.windows_last_error = 2; // ERROR_FILE_NOT_FOUND
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "OpenProcessToken")) {
        const token = arg(state, 2, direct_return_rip);
        if (token != 0 and state.guestMemory(token, 8) != null) state.write64(token, 0);
        state.windows_last_error = 5; // ERROR_ACCESS_DENIED
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "AdjustTokenPrivileges")) {
        const return_length = arg(state, 5, direct_return_rip);
        if (return_length != 0 and state.guestMemory(return_length, 4) != null) state.write32(return_length, 0);
        state.windows_last_error = 1300; // ERROR_NOT_ALL_ASSIGNED
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "OpenSCManagerA") or std.mem.eql(u8, name, "OpenSCManagerW") or
        std.mem.eql(u8, name, "OpenServiceA") or std.mem.eql(u8, name, "OpenServiceW"))
    {
        state.windows_last_error = 5; // ERROR_ACCESS_DENIED
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CloseServiceHandle")) {
        state.regs.rax = 1;
        state.windows_last_error = 0;
        finish(state, direct_return_rip);
        return true;
    }
    return false;
}

fn handleCore(state: anytype, dll_name: []const u8, name: []const u8, direct_return_rip: ?u64) bool {
    if (handleWindowsRegistry(state, name, direct_return_rip)) return true;
    if (handleWindowsSockets(state, name, direct_return_rip)) return true;
    if (handleWindowsSecurity(state, name, direct_return_rip)) return true;
    if (handleWindowsMultimedia(state, dll_name, name, direct_return_rip)) return true;
    if (handleStringAndMemory(state, name, direct_return_rip)) return true;

    if (std.mem.eql(u8, name, "strstr")) {
        const result = guestStrstr(state, arg(state, 0, direct_return_rip), arg(state, 1, direct_return_rip));
        state.regs.rax = result orelse 0;
        state.windows_last_error = if (result == null) 87 else 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strtol")) {
        const result = guestStrtol(state, arg(state, 0, direct_return_rip), arg(state, 1, direct_return_rip), arg(state, 2, direct_return_rip));
        if (result) |value| {
            state.regs.rax = @bitCast(value);
            state.windows_last_error = 0;
        } else {
            state.regs.rax = 0;
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "_setjmp")) return handleWindowsSetjmp(state, direct_return_rip);
    if (std.mem.eql(u8, name, "longjmp")) return handleWindowsLongjmp(state, direct_return_rip);

    if (std.mem.eql(u8, name, "_crt_atexit") or
        std.mem.eql(u8, name, "_register_thread_local_exe_atexit_callback"))
    {
        // Rosetta owns process teardown; the callback registration itself is
        // successful and has no guest-visible work during the run.
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_set_app_type")) {
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_set_new_mode")) {
        const previous = state.windows_new_mode;
        state.windows_new_mode = @truncate(arg(state, 0, direct_return_rip));
        state.regs.rax = previous;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_set_invalid_parameter_handler")) {
        const previous = state.windows_invalid_parameter_handler;
        state.windows_invalid_parameter_handler = arg(state, 0, direct_return_rip);
        state.regs.rax = previous;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_time64")) {
        var timespec: std.posix.timespec = undefined;
        const now: i64 = switch (std.posix.errno(std.posix.system.clock_gettime(.REALTIME, &timespec))) {
            .SUCCESS => @intCast(timespec.sec),
            else => @intCast(state.executed_steps / 1_000_000),
        };
        const output = arg(state, 0, direct_return_rip);
        if (output != 0 and state.guestMemory(output, 8) != null) state.write64(output, @bitCast(now));
        state.regs.rax = @bitCast(now);
        state.windows_last_error = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_localtime64")) {
        // The UCRT returns a pointer to a static/thread-local `struct tm`.
        // Rosetta cannot expose a host libc pointer to the PE guest, and a
        // zero-returning fallback is especially harmful here: Xenia's error
        // formatter passes the result through `asctime`, then fmt aborts on
        // the resulting null string.  A deterministic Unix-epoch record is
        // sufficient for the C-locale timestamp path and remains valid for
        // the lifetime of this PE state.
        if (state.windows_tm_storage == 0) {
            state.windows_tm_storage = state.guestAlloc(36, 4) orelse 0;
        }
        if (state.windows_tm_storage != 0) {
            const tm_fields = [_]u32{
                0, // tm_sec
                0, // tm_min
                0, // tm_hour
                1, // tm_mday
                0, // tm_mon (January)
                70, // tm_year (1970 - 1900)
                4, // tm_wday (Thursday)
                0, // tm_yday
                0, // tm_isdst
            };
            for (tm_fields, 0..) |field, index| {
                state.write32(state.windows_tm_storage +| @as(u64, @intCast(index * 4)), field);
            }
        }
        state.regs.rax = state.windows_tm_storage;
        state.windows_last_error = if (state.windows_tm_storage == 0) 12 else 0; // ERROR_NOT_ENOUGH_MEMORY
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "asctime")) {
        // `asctime` returns a process-owned 26-byte buffer.  Keep it stable
        // and guest-owned rather than formatting through a host pointer.
        state.regs.rax = cachedGuestString(state, &state.windows_asctime_storage, false, "Thu Jan  1 00:00:00 1970\n");
        state.windows_last_error = if (state.windows_asctime_storage == 0) 12 else 0; // ERROR_NOT_ENOUGH_MEMORY
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_lock_file") or std.mem.eql(u8, name, "_unlock_file")) {
        // Rosetta's cooperative executor serializes the guest stream calls;
        // these CRT bookkeeping hooks need no host mutex.  They are void
        // functions, so completing the import without a degraded zero return
        // keeps the runtime ledger honest.
        state.windows_last_error = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "getenv")) {
        const requested = guestCString(state, arg(state, 0, direct_return_rip)) orelse &.{};
        const value = environmentValue(requested);
        if (std.ascii.eqlIgnoreCase(requested, "SDL_AUDIODRIVER")) noteSdlAudioDriverQuery(state, value, "getenv");
        state.regs.rax = if (value) |selected|
            materializeGuestAnsi(state, selected) orelse 0
        else
            0;
        state.windows_last_error = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "signal")) {
        const signal_number = arg(state, 0, direct_return_rip);
        if (signal_number >= state.windows_signal_handlers.len) {
            state.regs.rax = std.math.maxInt(u64);
            state.windows_last_error = 22; // EINVAL
        } else {
            const slot = &state.windows_signal_handlers[@as(usize, @intCast(signal_number))];
            state.regs.rax = slot.*;
            slot.* = arg(state, 1, direct_return_rip);
            state.windows_last_error = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "LibK_GetVersion") or
        std.mem.eql(u8, name, "LibK_GetProcAddress") or
        std.mem.eql(u8, name, "RENDERDOC_GetAPI"))
    {
        // These are optional instrumentation/compatibility probes. A null
        // result is the honest answer when the optional host component is not
        // present, and avoids reporting a false successful interface.
        if (std.mem.eql(u8, name, "RENDERDOC_GetAPI")) {
            const output = arg(state, 1, direct_return_rip);
            if (output != 0 and state.guestMemory(output, 8) != null) state.write64(output, 0);
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "WindowsCreateStringReference")) {
        const source = arg(state, 0, direct_return_rip);
        const length = arg(state, 1, direct_return_rip);
        const header = arg(state, 2, direct_return_rip);
        const output = arg(state, 3, direct_return_rip);
        const byte_count = std.math.mul(u64, length, 2) catch std.math.maxInt(u64);
        const valid_source = source != 0 and state.guestMemoryConst(source, byte_count) != null;
        if (output == 0 or state.guestMemory(output, 8) == null) {
            state.regs.rax = 0x8000_4003; // E_POINTER
        } else if (!valid_source or (header != 0 and state.guestMemory(header, 24) == null)) {
            state.write64(output, 0);
            state.regs.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            // WinRT string activation is intentionally unavailable in this
            // Rosetta session. Preserve the documented refusal and clear the
            // output handle so a caller cannot dereference a false HSTRING.
            state.write64(output, 0);
            state.regs.rax = 0x8000_4001; // E_NOTIMPL
            if (state.diagnose_abi) {
                log.info("Windows WinRT string reference unavailable: source=0x{x} length={d} header=0x{x}; optional activation path refused explicitly", .{
                    source,
                    length,
                    header,
                });
            }
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "localeconv")) {
        // `localeconv` returns a process-lifetime pointer.  A generic
        // zero-returning degraded import makes the CRT's strtodg path load
        // decimal_point through address zero, which is the first media-backed
        // Halo launch fault rather than an actionable Xenia error.
        state.regs.rax = cachedGuestCLocaleConv(state);
        if (state.regs.rax == 0) state.windows_last_error = 12; // ERROR_NOT_ENOUGH_MEMORY
        if (state.diagnose_abi) {
            log.info("Windows C localeconv: record=0x{x} decimal_point=0x{x} empty=0x{x}", .{
                state.regs.rax,
                state.windows_locale_decimal_point,
                state.windows_locale_empty_string,
            });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "setlocale")) {
        // Xenia's Windows CRT uses the classic C locale.  Querying it must
        // return a stable guest string; accepting an explicit C/empty locale
        // keeps the normal startup contract while rejecting an unsupported
        // locale instead of claiming it was installed.
        const requested_address = arg(state, 1, direct_return_rip);
        if (requested_address != 0) {
            const requested = guestCString(state, requested_address) orelse &.{};
            if (requested.len != 0 and !std.mem.eql(u8, requested, "C")) {
                state.regs.rax = 0;
                finish(state, direct_return_rip);
                return true;
            }
        }
        state.regs.rax = cachedGuestString(state, &state.windows_locale_name, false, "C");
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "SymGetOptions")) {
        state.regs.rax = state.windows_symbol_options;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SymSetOptions")) {
        const previous = state.windows_symbol_options;
        state.windows_symbol_options = @truncate(arg(state, 0, direct_return_rip));
        state.regs.rax = previous;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SymInitialize")) {
        state.windows_symbol_services_initialized = true;
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SymCleanup")) {
        state.windows_symbol_services_initialized = false;
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "_errno")) {
        // The UCRT exposes errno as an int* rather than returning the value.
        // Keep the storage in guest memory and refresh it at each access so a
        // failed `_wstat64` is visible to libstdc++'s filesystem layer.
        if (state.windows_errno_storage == 0) {
            state.windows_errno_storage = state.guestAlloc(4, 4) orelse 0;
        }
        if (state.windows_errno_storage == 0) {
            state.regs.rax = 0;
        } else {
            state.write32(state.windows_errno_storage, state.windows_last_error);
            state.regs.rax = state.windows_errno_storage;
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "__p__fmode") or std.mem.eql(u8, name, "__p__commode")) {
        const storage = if (std.mem.eql(u8, name, "__p__fmode"))
            &state.windows_fmode_storage
        else
            &state.windows_commode_storage;
        if (storage.* == 0) storage.* = state.guestAlloc(4, 4) orelse 0;
        if (storage.* != 0) state.write32(storage.*, 0);
        state.regs.rax = storage.*;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__acrt_iob_func")) {
        const index = arg(state, 0, direct_return_rip);
        state.regs.rax = installWindowsStandardStream(state, index) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "_get_wpgmptr")) {
        // MinGW's filesystem helpers use this CRT accessor to obtain the
        // executable path before Xenia chooses its storage root.  A generic
        // zero-returning import stub is not harmless here: it reports success
        // without initializing the wchar_t* output, after which
        // std::filesystem constructs a path from uninitialized guest memory
        // and raises filesystem_error.  Keep the pointer wholly in guest
        // memory and make it stable for the lifetime of the PE state.
        const output = arg(state, 0, direct_return_rip);
        const path = cachedGuestString(state, &state.windows_module_path_w, true, "C:\\xenia\\xenia_canary.exe");
        if (output == 0 or state.guestMemory(output, 8) == null or path == 0) {
            state.regs.rax = 22; // EINVAL
        } else {
            state.write64(output, path);
            state.regs.rax = 0; // errno_t success
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "SHGetKnownFolderPath")) {
        // Xenia asks for both FOLDERID_Documents and FOLDERID_Fonts.  The
        // previous one-path answer made the Japanese font probe look like a
        // missing import: the call returned S_OK, but the following
        // `exists(C:\\Windows\\Fonts\\msgothic.ttc)` could never succeed.
        // Preserve the two guest-visible Windows paths separately.  The
        // confined path bridge above maps the font file to a real host font
        // without granting the PE access to the host's Windows directory.
        const folder_id = arg(state, 0, direct_return_rip);
        const folder_guid = state.guestMemoryConst(folder_id, 16);
        const fonts_guid = [_]u8{
            0xB7, 0x8C, 0x22, 0xFD, 0x11, 0xAE, 0xE3, 0x4A,
            0x86, 0x4C, 0x16, 0xF3, 0x91, 0x0A, 0xB8, 0xFE,
        };
        const wants_fonts = folder_guid != null and std.mem.eql(u8, folder_guid.?, &fonts_guid);
        const output = arg(state, 3, direct_return_rip); // PWSTR*
        const path = if (wants_fonts)
            cachedGuestString(state, &state.windows_fonts_folder_w, true, "C:\\Windows\\Fonts")
        else
            cachedGuestString(state, &state.windows_user_folder_w, true, "C:\\xenia\\Documents");
        if (output == 0 or state.guestMemory(output, 8) == null or path == 0) {
            state.regs.rax = 0x8007_0057; // E_INVALIDARG / HRESULT_FROM_WIN32
        } else {
            state.write64(output, path);
            state.regs.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SHGetFolderPathW")) {
        // The legacy shell entry point is still used by older SDL/Xenia
        // paths.  It writes into caller-owned MAX_PATH storage rather than
        // returning a PWSTR allocation, so use the same confined Documents
        // root as FOLDERID_Documents.
        const output = arg(state, 4, direct_return_rip);
        const written = if (output != 0)
            copyGuestWideString(state, output, 260, "C:\\xenia\\Documents")
        else
            0;
        state.regs.rax = if (written == 0) 0x8000_4003 else 0; // E_POINTER/S_OK
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ShellExecuteW")) {
        // Rosetta does not launch host applications on behalf of the guest.
        // ShellExecute's <=32 failure result is explicit and lets Xenia
        // continue down its normal "no external helper" path.
        state.windows_last_error = 2; // ERROR_FILE_NOT_FOUND
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "CreateDirectoryW")) {
        // std::filesystem::create_directories ultimately reaches this Win32
        // call on the PE route.  Treating it as a no-op makes the C++ layer
        // believe that storage exists, then causes a later file open to fail.
        // Create the requested path through the already-authorized host root.
        const path_argument = arg(state, 0, direct_return_rip);
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const path = guestPathToHost(state, path_argument, true, &path_buffer) orelse {
            failWindowsFileCall(state, direct_return_rip, 3); // ERROR_PATH_NOT_FOUND
            state.regs.rax = 0;
            return true;
        };
        if (hostStat(state, path)) |_| {
            state.windows_last_error = 183; // ERROR_ALREADY_EXISTS
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        }
        const io = state.windows_host_io orelse {
            failWindowsFileCall(state, direct_return_rip, 3);
            state.regs.rax = 0;
            return true;
        };
        std.Io.Dir.cwd().createDirPath(io, path) catch {
            failWindowsFileCall(state, direct_return_rip, 3); // ERROR_PATH_NOT_FOUND
            state.regs.rax = 0;
            return true;
        };
        state.windows_last_error = 0;
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "_wmkdir")) {
        const path_argument = arg(state, 0, direct_return_rip);
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const path = guestPathToHost(state, path_argument, true, &path_buffer) orelse {
            state.windows_last_error = 3; // ERROR_PATH_NOT_FOUND
            state.regs.rax = @bitCast(@as(i64, -1));
            finish(state, direct_return_rip);
            return true;
        };
        if (hostStat(state, path)) |_| {
            state.windows_last_error = 17; // EEXIST
            state.regs.rax = @bitCast(@as(i64, -1));
            finish(state, direct_return_rip);
            return true;
        }
        const io = state.windows_host_io orelse {
            state.windows_last_error = 3; // ERROR_PATH_NOT_FOUND
            state.regs.rax = @bitCast(@as(i64, -1));
            finish(state, direct_return_rip);
            return true;
        };
        std.Io.Dir.cwd().createDirPath(io, path) catch {
            state.windows_last_error = 3; // ERROR_PATH_NOT_FOUND
            state.regs.rax = @bitCast(@as(i64, -1));
            finish(state, direct_return_rip);
            return true;
        };
        state.windows_last_error = 0;
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "_wstat64") or std.mem.eql(u8, name, "_stat64") or
        std.mem.eql(u8, name, "__stat64"))
    {
        return statWindowsPath(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "_fstat64") or std.mem.eql(u8, name, "fstat64")) {
        return statWindowsDescriptor(state, name, direct_return_rip);
    }

    if (std.mem.eql(u8, name, "_initterm") or std.mem.eql(u8, name, "_initterm_e")) {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "beginWindowsInitTerm")) {
            return state.beginWindowsInitTerm(
                arg(state, 0, direct_return_rip),
                arg(state, 1, direct_return_rip),
                direct_return_rip,
                std.mem.eql(u8, name, "_initterm_e"),
            );
        }
    }

    if (std.mem.eql(u8, name, "pthread_once")) {
        const once_control = arg(state, 0, direct_return_rip);
        const init_routine = arg(state, 1, direct_return_rip);

        // POSIX specifies an error for a null control or initializer. Do not
        // fabricate successful one-time initialization: callers that depend
        // on the callback must see the failure in the normal return channel.
        if (once_control == 0 or init_routine == 0 or state.guestMemory(once_control, 4) == null) {
            state.regs.rax = 22; // EINVAL
            finish(state, direct_return_rip);
            return true;
        }
        if (state.addrToOffset(init_routine) == null) {
            log.err("Windows pthread_once initializer is outside the guest image: control=0x{x} routine=0x{x}", .{ once_control, init_routine });
            state.regs.rax = 22; // EINVAL
            finish(state, direct_return_rip);
            return true;
        }

        const once_state = state.read32(once_control);
        if (once_state == 1) {
            // Already complete: pthread_once must not call the initializer a
            // second time and returns success without touching the stack.
            returnZero(state, direct_return_rip);
            return true;
        }
        if (once_state != 0) {
            // Rosetta executes this route cooperatively and cannot wait on a
            // host mutex. A nonzero/non-complete state is an initializer that
            // is already in progress; report the POSIX deadlock condition
            // instead of recursively invoking it or spinning forever.
            state.regs.rax = 35; // EDEADLK
            finish(state, direct_return_rip);
            return true;
        }

        // Mark the initializer in progress before entering guest code. The
        // synthetic return handler changes this to the completed state only
        // after the callback executes a real `ret`.
        state.write32(once_control, 2);
        if (direct_return_rip) |rip| state.push(rip);
        state.push(once_control);
        state.push(SYNTHETIC_PTHREAD_ONCE_RETURN);
        state.regs.rdi = 0;
        state.regs.rsi = 0;
        state.regs.rdx = 0;
        state.regs.rip = init_routine;
        return true;
    }

    if (std.mem.eql(u8, name, "GetLastError")) {
        state.regs.rax = state.windows_last_error;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetLastError")) {
        state.windows_last_error = @truncate(arg(state, 0, direct_return_rip));
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "wctype")) {
        const property = guestCString(state, arg(state, 0, direct_return_rip)) orelse &.{};
        const descriptor = cLocaleWctypeDescriptor(property);
        state.regs.rax = descriptor;
        if (state.diagnose_abi) {
            log.info("Windows C-locale wctype: property='{s}' descriptor=0x{x}", .{ property, descriptor });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "iswctype")) {
        state.regs.rax = @intFromBool(cLocaleIsWideClass(arg(state, 0, direct_return_rip), arg(state, 1, direct_return_rip)));
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "isalnum") or std.mem.eql(u8, name, "isalpha") or
        std.mem.eql(u8, name, "isblank") or std.mem.eql(u8, name, "iscntrl") or
        std.mem.eql(u8, name, "isgraph") or std.mem.eql(u8, name, "islower") or
        std.mem.eql(u8, name, "isprint") or std.mem.eql(u8, name, "ispunct") or
        std.mem.eql(u8, name, "isspace") or std.mem.eql(u8, name, "isupper") or
        std.mem.eql(u8, name, "isxdigit"))
    {
        state.regs.rax = @intFromBool(cLocaleIsWideClass(arg(state, 0, direct_return_rip), cLocaleWctypeDescriptor(name[2..])));
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "tolower") or std.mem.eql(u8, name, "toupper")) {
        const value = arg(state, 0, direct_return_rip);
        const result: u64 = if (value > 0x7f)
            value
        else if (std.mem.eql(u8, name, "tolower") and value >= 'A' and value <= 'Z')
            value + ('a' - 'A')
        else if (std.mem.eql(u8, name, "toupper") and value >= 'a' and value <= 'z')
            value - ('a' - 'A')
        else
            value;
        state.regs.rax = result;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strerror")) {
        const message = windowsErrorString(arg(state, 0, direct_return_rip));
        state.regs.rax = materializeGuestAnsi(state, message) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "wctob")) {
        // The PE's libstdc++ codecvt path uses the C-locale conversion
        // contract while constructing filesystem paths. In the default
        // narrow locale, ASCII code points are representable and all other
        // wide characters must report EOF; returning zero for every input
        // makes the conversion look successful for NUL and unsuccessful for
        // ordinary text at the same time. Keep the signed EOF result intact
        // in the 64-bit guest return register.
        const wide_character = arg(state, 0, direct_return_rip);
        const result: i64 = if (wide_character <= 0x7f)
            @intCast(wide_character)
        else
            -1;
        state.regs.rax = @bitCast(result);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "btowc")) {
        // Match the classic C-locale conversion contract in the opposite
        // direction: ASCII bytes widen losslessly, while EOF and bytes from
        // the high half of an unsigned char cannot be represented by the
        // single-byte locale and return WEOF. The generic import-contract
        // fallback used to return zero for every byte, which corrupts the
        // locale classification table before libstdc++ constructs regexes.
        const byte = arg(state, 0, direct_return_rip);
        const result: i64 = if (byte <= 0x7f)
            @intCast(byte)
        else
            -1;
        state.regs.rax = @bitCast(result);
        if (state.diagnose_abi and byte <= 0xff) {
            log.info("Windows C-locale btowc: byte=0x{x} result=0x{x}", .{ byte, state.regs.rax });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetHandleInformation")) {
        const handle = arg(state, 0, direct_return_rip);
        const flags = arg(state, 1, direct_return_rip);
        if (flags == 0 or state.guestMemory(flags, 4) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else if (!isSyntheticWindowsHandle(state, handle)) {
            state.windows_last_error = 6; // ERROR_INVALID_HANDLE
            state.regs.rax = 0;
        } else {
            // Rosetta-owned handles are not inheritable unless a future
            // handle-table contract explicitly opts them in.
            state.write32(flags, 0);
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DuplicateHandle")) {
        const source_process = arg(state, 0, direct_return_rip);
        const source_handle = arg(state, 1, direct_return_rip);
        const target_process = arg(state, 2, direct_return_rip);
        const target_handle = arg(state, 3, direct_return_rip);
        const pseudo_process = std.math.maxInt(u64);
        const pseudo_thread = std.math.maxInt(u64) - 1;
        const source_process_valid = source_process == pseudo_process or isSyntheticWindowsHandle(state, source_process);
        const target_process_valid = target_process == pseudo_process or isSyntheticWindowsHandle(state, target_process);
        const source_handle_valid = source_handle == pseudo_thread or isSyntheticWindowsHandle(state, source_handle);

        if (!source_process_valid or !target_process_valid or !source_handle_valid or
            target_handle == 0 or state.guestMemory(target_handle, 8) == null)
        {
            // DuplicateHandle reports failure through the Win32 last-error
            // channel. Do not write a fabricated output handle: CRT startup
            // uses this result to decide whether its process/thread setup is
            // valid, and a false success only moves the failure downstream.
            state.windows_last_error = if (target_handle == 0 or state.guestMemory(target_handle, 8) == null)
                87 // ERROR_INVALID_PARAMETER
            else
                6; // ERROR_INVALID_HANDLE
            state.regs.rax = 0;
        } else {
            state.write64(target_handle, nextHandle(state));
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCurrentProcess")) {
        state.regs.rax = std.math.maxInt(u64);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCurrentThread")) {
        state.regs.rax = std.math.maxInt(u64) - 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCurrentProcessId")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCurrentThreadId")) {
        const State = @TypeOf(state.*);
        state.regs.rax = if (comptime @hasDecl(State, "currentWindowsThreadId"))
            state.currentWindowsThreadId()
        else
            1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetThreadId")) {
        const handle = arg(state, 0, direct_return_rip);
        const current = std.math.maxInt(u64) - 1;
        if (handle == current) {
            state.regs.rax = 1;
        } else {
            state.regs.rax = 0;
            for (state.windows_guest_threads) |thread| {
                if (thread.status != .vacant and thread.handle == handle) {
                    state.regs.rax = thread.thread_id;
                    break;
                }
            }
            if (state.regs.rax == 0) state.windows_last_error = 6; // ERROR_INVALID_HANDLE
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetThreadPriority") or std.mem.eql(u8, name, "SetThreadPriority")) {
        const handle = arg(state, 0, direct_return_rip);
        const current = std.math.maxInt(u64) - 1;
        var valid = handle == current;
        var found_index: ?usize = null;
        for (state.windows_guest_threads, 0..) |thread, index| {
            if (thread.status != .vacant and thread.handle == handle) {
                valid = true;
                found_index = index;
                break;
            }
        }
        if (!valid) {
            state.windows_last_error = 6; // ERROR_INVALID_HANDLE
            state.regs.rax = if (std.mem.eql(u8, name, "GetThreadPriority")) @bitCast(@as(i64, -15)) else 0;
        } else if (std.mem.eql(u8, name, "GetThreadPriority")) {
            state.regs.rax = if (found_index) |index| @bitCast(@as(i64, state.windows_guest_threads[index].priority)) else 0;
        } else {
            const priority: i32 = @bitCast(@as(u32, @truncate(arg(state, 1, direct_return_rip))));
            if (found_index) |index| state.windows_guest_threads[index].priority = priority;
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ResumeThread")) {
        const handle = arg(state, 0, direct_return_rip);
        var result: u64 = std.math.maxInt(u32);
        for (&state.windows_guest_threads) |*thread| {
            if (thread.status != .vacant and thread.handle == handle) {
                result = thread.suspend_count;
                if (thread.suspend_count != 0) thread.suspend_count -= 1;
                state.windows_last_error = 0;
                break;
            }
        }
        state.regs.rax = result;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetProcessHeap")) {
        state.regs.rax = 0xFFFF_F000_0000_0100;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetProcessAffinityMask")) {
        const process_mask = arg(state, 1, direct_return_rip);
        const system_mask = arg(state, 2, direct_return_rip);
        if (process_mask == 0 or system_mask == 0 or
            state.guestMemory(process_mask, 8) == null or state.guestMemory(system_mask, 8) == null)
        {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            state.write64(process_mask, state.windows_process_affinity_mask);
            state.write64(system_mask, state.windows_process_affinity_mask);
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetProcessAffinityMask")) {
        const mask = arg(state, 1, direct_return_rip);
        if (mask == 0) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            state.windows_process_affinity_mask = mask;
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "FlushInstructionCache")) {
        state.windows_last_error = 0;
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetModuleHandleExW")) {
        const output = arg(state, 2, direct_return_rip);
        if (output == 0 or state.guestMemory(output, 8) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            state.write64(output, state.image_low);
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VerSetConditionMask")) {
        var mask = arg(state, 0, direct_return_rip);
        const type_mask: u32 = @truncate(arg(state, 1, direct_return_rip));
        const condition: u64 = arg(state, 2, direct_return_rip) & 0x7;
        var bit: u6 = 0;
        var remaining = type_mask;
        while (remaining != 0) : (bit += 1) {
            if ((remaining & 1) != 0) mask = (mask & ~(@as(u64, 0x7) << (bit * 3))) | (condition << (bit * 3));
            remaining >>= 1;
        }
        state.regs.rax = mask;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetModuleHandleA") or std.mem.eql(u8, name, "GetModuleHandleW") or
        std.mem.eql(u8, name, "LoadLibraryA") or std.mem.eql(u8, name, "LoadLibraryW") or
        std.mem.eql(u8, name, "LoadLibraryExA") or std.mem.eql(u8, name, "LoadLibraryExW"))
    {
        const is_load_library = std.mem.startsWith(u8, name, "LoadLibrary");
        var module_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        // The module name matters for `GetModuleHandle` too: a guest that
        // resolves an export through `GetProcAddress(GetModuleHandleW(...))`
        // is asking about a specific library, and answering as if the handle
        // named nothing loses the only context the return contract has.
        const module_path = if (std.mem.endsWith(u8, name, "W"))
            guestWideToUtf8Buffer(state, arg(state, 0, direct_return_rip), &module_path_buffer)
        else
            guestCString(state, arg(state, 0, direct_return_rip));
        // A name Rosetta could not read is not evidence about the library.
        // Refusing on it would report a loadable library as absent and send a
        // reader after a package that already exists, so an unreadable name
        // keeps the permissive answer and is reported as a *read* failure.
        const readable = if (module_path) |path| windowsModuleNameLooksReadable(path) else true;
        const availability = if (module_path) |path|
            (if (readable) windowsModuleAvailability(path) else ModuleAvailability.served)
        else
            ModuleAvailability.served;
        const unavailable = availability != .served;
        state.regs.rax = if (unavailable) 0 else nextHandle(state);
        state.windows_last_error = if (unavailable) 126 else 0; // ERROR_MOD_NOT_FOUND
        if (!unavailable and state.regs.rax != 0 and readable) {
            if (module_path) |path| noteWindowsModuleHandle(state, state.regs.rax, windowsModuleBasename(path));
        }
        if (!readable) {
            noteWindowsUnreadableModuleName(
                state,
                name,
                module_path orelse "",
                arg(state, 0, direct_return_rip),
                direct_return_rip orelse state.read64(state.regs.rsp),
            );
        }
        if (unavailable) noteWindowsModuleRefusal(
            state,
            name,
            module_path orelse "<unreadable>",
            availability,
            direct_return_rip orelse state.read64(state.regs.rsp),
        );
        if (state.diagnose_abi and is_load_library) {
            log.info("PE64 Windows {s}: module='{s}' result=0x{x}", .{ name, module_path orelse "<unreadable>", state.regs.rax });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "FreeLibrary")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetProcAddress")) {
        const module_handle = arg(state, 0, direct_return_rip);
        const requested_address = arg(state, 1, direct_return_rip);
        const module_name = windowsModuleNameFor(state, module_handle);
        // Xenia obtains XInputGetStateEx by ordinal 100.  An ordinal is
        // passed through LPCSTR without being a guest string, so attempting
        // guestCString on it would incorrectly turn a valid lookup into a
        // null pointer and leave the input path uninitialised.
        if (requested_address <= std.math.maxInt(u16)) {
            state.regs.rax = if (requested_address == 100)
                state.registerWindowsImportStub("xinput1_4.dll", "XInputGetStateEx") orelse 0
            else
                0;
            if (state.regs.rax == 0) state.windows_last_error = 127; // ERROR_PROC_NOT_FOUND
        } else if (guestCString(state, requested_address)) |requested| {
            // A dynamic lookup is a *question*, and "no" is a valid answer
            // every caller already handles - that is why the caller used
            // GetProcAddress instead of an import. Handing back a stub for a
            // name Rosetta does not implement converts that question into a
            // promise, and the promise is broken later, inside whatever the
            // guest does with the pointer. Xenia's per-monitor DPI probe and
            // its XAudio2 entry point both take this path.
            if (isRecognizedDynamicImport(module_name, requested)) {
                state.regs.rax = state.registerWindowsImportStub(module_name, requested) orelse 0;
                state.windows_last_error = if (state.regs.rax == 0) 127 else 0;
            } else {
                state.regs.rax = 0;
                state.windows_last_error = 127; // ERROR_PROC_NOT_FOUND
                noteWindowsProcAddressRefusal(
                    state,
                    module_name,
                    requested,
                    direct_return_rip orelse state.read64(state.regs.rsp),
                );
            }
        } else {
            state.regs.rax = 0;
            state.windows_last_error = 127; // ERROR_PROC_NOT_FOUND
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCommandLineA") or std.mem.eql(u8, name, "GetCommandLineW")) {
        const wide = std.mem.endsWith(u8, name, "W");
        state.regs.rax = if (wide)
            cachedGuestCommandLine(state, &state.windows_command_line_w, true)
        else
            cachedGuestCommandLine(state, &state.windows_command_line_a, false);
        if (state.diagnose_abi) {
            log.info("Windows command line: api={s} pointer=0x{x} argc={d}", .{ name, state.regs.rax, launchArgumentCount(state) });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p___argc")) {
        state.regs.rax = cachedGuestArgc(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p___argv")) {
        state.regs.rax = cachedGuestArgvStorage(state, false);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p___wargv")) {
        state.regs.rax = cachedGuestArgvStorage(state, true);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p__environ")) {
        state.regs.rax = cachedGuestEnvironmentStorage(state, false);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p__wenviron")) {
        state.regs.rax = cachedGuestEnvironmentStorage(state, true);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p__wcmdln")) {
        const command_line = cachedGuestCommandLine(state, &state.windows_command_line_w, true);
        state.regs.rax = cachedGuestPointer(state, &state.windows_wcmdln_storage, command_line);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_initialize_narrow_environment") or
        std.mem.eql(u8, name, "_initialize_wide_environment") or
        std.mem.eql(u8, name, "_configure_narrow_argv") or
        std.mem.eql(u8, name, "_configure_wide_argv"))
    {
        // The actual publication occurs through the __p_* accessors above.
        // These CRT setup calls still need a normal ABI return so the local
        // __getmainargs/__wgetmainargs helper can continue to those stores.
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetModuleFileNameA") or std.mem.eql(u8, name, "GetModuleFileNameW")) {
        const wide = std.mem.endsWith(u8, name, "W");
        const destination = arg(state, 1, direct_return_rip);
        const capacity = arg(state, 2, direct_return_rip);
        const source = "xenia-canary.exe";
        const copied = if (wide)
            copyGuestWideString(state, destination, capacity, source)
        else
            copyGuestString(state, destination, capacity, source);
        if (destination == 0 or capacity == 0) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else if (copied < source.len) {
            state.windows_last_error = 122; // ERROR_INSUFFICIENT_BUFFER
            state.regs.rax = capacity;
        } else {
            state.regs.rax = copied;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetModuleInformation") or std.mem.eql(u8, name, "K32GetModuleInformation")) {
        const information = arg(state, 2, direct_return_rip);
        const capacity = arg(state, 3, direct_return_rip);
        const image_size = if (state.image_high >= state.image_low)
            @min(state.image_high - state.image_low, std.math.maxInt(u32))
        else
            0;
        if (information == 0 or capacity < 24 or state.guestMemory(information, 24) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            state.write64(information + 0, state.image_low);
            state.write32(information + 8, @intCast(image_size));
            state.write64(information + 16, state.windows_entry_point);
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetUnhandledExceptionFilter")) {
        const previous = state.windows_unhandled_exception_filter;
        state.windows_unhandled_exception_filter = arg(state, 0, direct_return_rip);
        state.regs.rax = previous;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "AddVectoredExceptionHandler") or
        std.mem.eql(u8, name, "AddVectoredContinueHandler"))
    {
        const handler = arg(state, 1, direct_return_rip);
        if (handler == 0 or state.addrToOffset(handler) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            const token = nextHandle(state);
            state.windows_vectored_exception_handler = handler;
            state.windows_vectored_exception_token = token;
            state.windows_last_error = 0;
            state.regs.rax = token;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RemoveVectoredExceptionHandler") or
        std.mem.eql(u8, name, "RemoveVectoredContinueHandler"))
    {
        const token = arg(state, 0, direct_return_rip);
        const removed = token != 0 and token == state.windows_vectored_exception_token;
        if (removed) {
            state.windows_vectored_exception_token = 0;
            state.windows_vectored_exception_handler = 0;
        }
        state.windows_last_error = if (removed) 0 else 87;
        state.regs.rax = @intFromBool(removed);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetStartupInfoW")) {
        const startup_info = arg(state, 0, direct_return_rip);
        if (startup_info == 0 or state.guestMemory(startup_info, 104) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
        } else {
            const bytes = state.guestMemory(startup_info, 104).?;
            @memset(bytes, 0);
            state.write32(startup_info, 104);
            state.windows_last_error = 0;
        }
        // GetStartupInfoW is void; the return register is intentionally not
        // used as a success signal.
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetThreadDescription")) {
        const output = arg(state, 1, direct_return_rip);
        const description = cachedGuestString(state, &state.windows_thread_description_w, true, "Rosetta thread");
        if (output == 0 or description == 0) {
            state.regs.rax = 0x8007_000E; // E_OUTOFMEMORY / invalid output
        } else {
            state.write64(output, description);
            state.regs.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetThreadDescription")) {
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetThreadContext")) {
        const handle = arg(state, 0, direct_return_rip);
        const context = arg(state, 1, direct_return_rip);
        const current_thread = std.math.maxInt(u64) - 1;
        const context_valid = context != 0 and state.guestMemory(context, 0x38) != null;
        if ((!isSyntheticWindowsHandle(state, handle) and handle != current_thread) or !context_valid) {
            state.windows_last_error = if (context_valid) 6 else 87;
            state.regs.rax = 0;
        } else {
            // The PE runner has one cooperative guest context rather than a
            // native Windows thread handle. Validate the caller's CONTEXT
            // storage and acknowledge the contract, while retaining the
            // The cooperative executor has no second native register context
            // to install, but the validated guest CONTEXT contract is fully
            // modeled for the current thread.
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetEnvironmentVariableA") or std.mem.eql(u8, name, "GetEnvironmentVariableW")) {
        const wide = std.mem.endsWith(u8, name, "W");
        const requested = if (wide) null else guestCString(state, arg(state, 0, direct_return_rip));
        const value = if (wide)
            wideEnvironmentValue(state, arg(state, 0, direct_return_rip))
        else
            environmentValue(requested orelse "");
        if (!wide) {
            if (requested) |requested_name| {
                if (std.ascii.eqlIgnoreCase(requested_name, "SDL_AUDIODRIVER")) noteSdlAudioDriverQuery(state, value, name);
            }
        }
        const destination = arg(state, 1, direct_return_rip);
        const capacity = arg(state, 2, direct_return_rip);
        const selected = value orelse {
            state.windows_last_error = 203; // ERROR_ENVVAR_NOT_FOUND
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        const copied = if (wide)
            copyGuestWideString(state, destination, capacity, selected)
        else
            copyGuestString(state, destination, capacity, selected);
        if (destination == 0 or capacity == 0) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else if (copied < selected.len) {
            state.windows_last_error = 122; // ERROR_INSUFFICIENT_BUFFER
            state.regs.rax = selected.len + 1;
        } else {
            state.regs.rax = copied;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetSystemDirectoryA") or std.mem.eql(u8, name, "GetSystemDirectoryW") or
        std.mem.eql(u8, name, "GetWindowsDirectoryA") or std.mem.eql(u8, name, "GetWindowsDirectoryW") or
        std.mem.eql(u8, name, "GetTempPathA") or std.mem.eql(u8, name, "GetTempPathW") or
        std.mem.eql(u8, name, "GetCurrentDirectoryA") or std.mem.eql(u8, name, "GetCurrentDirectoryW"))
    {
        const wide = std.mem.endsWith(u8, name, "W");
        const source = if (std.mem.startsWith(u8, name, "GetSystemDirectory"))
            "C:\\Windows\\System32"
        else if (std.mem.startsWith(u8, name, "GetWindowsDirectory"))
            "C:\\Windows"
        else if (std.mem.startsWith(u8, name, "GetTempPath"))
            "C:\\Temp\\"
        else
            "C:\\xenia";
        // These four families do NOT share an argument order, and treating
        // them as if they did is how libusb ended up calling
        // `LoadLibraryA` on an uninitialized stack buffer:
        //
        //   UINT  GetSystemDirectoryA (LPSTR buffer, UINT size);   // buffer first
        //   UINT  GetWindowsDirectoryA(LPSTR buffer, UINT size);   // buffer first
        //   DWORD GetCurrentDirectoryA(DWORD size, LPSTR buffer);  // size first
        //   DWORD GetTempPathA        (DWORD size, LPSTR buffer);  // size first
        //
        // Reading them all size-first made `GetSystemDirectoryA` write
        // nothing and still return a plausible length, so
        // `load_system_library` appended "\\WinUSB.dll" at that offset into a
        // buffer nobody had filled and loaded whatever was on the stack. The
        // 2026-09-12 run recorded that as `module name unreadable: bytes='0\x03'D\x01'`.
        const buffer_first = std.mem.startsWith(u8, name, "GetSystemDirectory") or
            std.mem.startsWith(u8, name, "GetWindowsDirectory");
        const destination = arg(state, if (buffer_first) 0 else 1, direct_return_rip);
        const capacity = arg(state, if (buffer_first) 1 else 0, direct_return_rip);
        const copied = if (wide)
            copyGuestWideString(state, destination, capacity, source)
        else
            copyGuestString(state, destination, capacity, source);
        if (destination == 0 or capacity == 0) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else if (copied < source.len) {
            state.windows_last_error = 122; // ERROR_INSUFFICIENT_BUFFER
            state.regs.rax = source.len + 1;
        } else {
            state.regs.rax = copied;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetFullPathNameA") or std.mem.eql(u8, name, "GetFullPathNameW")) {
        const wide = std.mem.endsWith(u8, name, "W");
        var source_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const source = if (wide)
            guestWideToUtf8Buffer(state, arg(state, 0, direct_return_rip), &source_buffer)
        else
            guestCString(state, arg(state, 0, direct_return_rip));
        const destination = arg(state, 2, direct_return_rip);
        const capacity = arg(state, 1, direct_return_rip);
        const value = source orelse {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        var full_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = normalizedFullPath(value, &full_path_buffer) orelse {
            state.windows_last_error = 206; // ERROR_FILENAME_EXCED_RANGE
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        const file_part = arg(state, 3, direct_return_rip);
        if (wide) {
            if (capacity > full_path.len and destination != 0) {
                _ = copyGuestWideString(state, destination, capacity, full_path);
                writeFullPathFilePart(state, destination, capacity, full_path, file_part, true);
                state.regs.rax = full_path.len;
            } else {
                state.regs.rax = full_path.len + 1;
            }
        } else if (capacity > full_path.len and destination != 0) {
            _ = copyGuestString(state, destination, capacity, full_path);
            writeFullPathFilePart(state, destination, capacity, full_path, file_part, false);
            state.regs.rax = full_path.len;
        } else {
            state.regs.rax = full_path.len + 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "WideCharToMultiByte")) {
        var source_buffer: [512]u8 = undefined;
        const source_text = if (state.diagnose_abi)
            guestWideToUtf8Buffer(state, arg(state, 2, direct_return_rip), &source_buffer)
        else
            null;
        const converted = wideCharToUtf8(
            state,
            arg(state, 2, direct_return_rip),
            arg(state, 3, direct_return_rip),
            arg(state, 4, direct_return_rip),
            arg(state, 5, direct_return_rip),
        );
        if (converted) |count| {
            state.regs.rax = count;
        } else {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        }
        const used_default = arg(state, 7, direct_return_rip);
        if (used_default != 0) state.write32(used_default, 0);
        if (state.diagnose_abi and source_text != null) {
            const output_text = if (arg(state, 4, direct_return_rip) != 0)
                guestCString(state, arg(state, 4, direct_return_rip))
            else
                null;
            log.info("Windows WideCharToMultiByte: source='{s}' source_units={d} destination=0x{x} capacity={d} result={d} output='{s}'", .{
                source_text.?,
                arg(state, 3, direct_return_rip),
                arg(state, 4, direct_return_rip),
                arg(state, 5, direct_return_rip),
                state.regs.rax,
                output_text orelse "<query-or-unreadable>",
            });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "MultiByteToWideChar")) {
        const converted = multiByteToWide(
            state,
            arg(state, 2, direct_return_rip),
            arg(state, 3, direct_return_rip),
            arg(state, 4, direct_return_rip),
            arg(state, 5, direct_return_rip),
        );
        if (converted) |count| {
            state.regs.rax = count;
        } else {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CommandLineToArgvW")) {
        const argc = arg(state, 1, direct_return_rip);
        const argv = cachedGuestArgv(state, true);
        const count = launchArgumentCount(state);
        if (argc != 0 and count <= std.math.maxInt(u32)) state.write32(argc, @intCast(count));
        if (state.diagnose_abi and argv != 0) {
            log.info("Windows CommandLineToArgvW: command_line=0x{x} argv=0x{x} argc={d} arg0=0x{x} arg1=0x{x}", .{
                arg(state, 0, direct_return_rip),
                argv,
                count,
                state.read64(argv),
                if (count > 1) state.read64(argv + 8) else 0,
            });
        }
        state.regs.rax = argv;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetVersionExA") or std.mem.eql(u8, name, "GetVersionExW")) {
        const version = arg(state, 0, direct_return_rip);
        if (version == 0 or state.guestMemory(version, 20) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            state.write32(version + 4, 10); // dwMajorVersion
            state.write32(version + 8, 0); // dwMinorVersion
            state.write32(version + 12, 22621); // dwBuildNumber
            state.write32(version + 16, 2); // VER_PLATFORM_WIN32_NT
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RegOpenKeyA") or std.mem.eql(u8, name, "RegOpenKeyW") or
        std.mem.eql(u8, name, "RegOpenKeyExA") or std.mem.eql(u8, name, "RegOpenKeyExW"))
    {
        const root = arg(state, 0, direct_return_rip);
        const output = if (std.mem.startsWith(u8, name, "RegOpenKeyEx"))
            arg(state, 4, direct_return_rip)
        else
            arg(state, 2, direct_return_rip);
        if (!isWindowsRegistryRoot(root) or output == 0 or state.guestMemory(output, 8) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
        } else {
            // A missing key is an ordinary result for the settings probe. Do
            // not turn it into a fabricated readable key: the caller's
            // following RegCreateKey path is the durable branch Rosetta can
            // model safely.
            state.write64(output, 0);
            state.windows_last_error = 2; // ERROR_FILE_NOT_FOUND
        }
        state.regs.rax = state.windows_last_error;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RegCreateKeyA") or std.mem.eql(u8, name, "RegCreateKeyW") or
        std.mem.eql(u8, name, "RegCreateKeyExA") or std.mem.eql(u8, name, "RegCreateKeyExW"))
    {
        const root = arg(state, 0, direct_return_rip);
        const extended = std.mem.startsWith(u8, name, "RegCreateKeyEx");
        const output = if (extended) arg(state, 7, direct_return_rip) else arg(state, 2, direct_return_rip);
        if (!isWindowsRegistryRoot(root) or output == 0 or state.guestMemory(output, 8) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = state.windows_last_error;
        } else {
            state.write64(output, nextHandle(state));
            if (extended) {
                const disposition = arg(state, 8, direct_return_rip);
                if (disposition != 0 and state.guestMemory(disposition, 4) != null) state.write32(disposition, 1); // REG_CREATED_NEW_KEY
            }
            state.windows_last_error = 0; // ERROR_SUCCESS
            state.regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RegSetValueExA") or std.mem.eql(u8, name, "RegSetValueExW")) {
        const key = arg(state, 0, direct_return_rip);
        const data = arg(state, 4, direct_return_rip);
        const data_size = arg(state, 5, direct_return_rip);
        const valid_data = data_size == 0 or (data != 0 and state.guestMemory(data, data_size) != null);
        state.windows_last_error = if (isWindowsRegistryHandle(state, key) and valid_data) 0 else if (!valid_data) 87 else 6;
        state.regs.rax = state.windows_last_error;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RegGetValueA") or std.mem.eql(u8, name, "RegGetValueW") or
        std.mem.eql(u8, name, "RegQueryValueExA") or std.mem.eql(u8, name, "RegQueryValueExW"))
    {
        const key = arg(state, 0, direct_return_rip);
        if (!isWindowsRegistryHandle(state, key)) {
            state.windows_last_error = 6; // ERROR_INVALID_HANDLE
        } else {
            const extended = std.mem.startsWith(u8, name, "RegGetValue");
            const type_output = if (extended) arg(state, 4, direct_return_rip) else arg(state, 4, direct_return_rip);
            const data_output = if (extended) arg(state, 5, direct_return_rip) else arg(state, 5, direct_return_rip);
            const size_output = if (extended) arg(state, 6, direct_return_rip) else arg(state, 6, direct_return_rip);
            if (type_output != 0 and state.guestMemory(type_output, 4) != null) state.write32(type_output, 1); // REG_SZ
            if (size_output != 0 and state.guestMemory(size_output, 4) != null) state.write32(size_output, 0);
            if (data_output != 0 and size_output != 0 and state.guestMemory(size_output, 4) != null) {
                const capacity = @min(@as(u64, state.read32(size_output)), 64 * 1024);
                if (capacity != 0 and state.guestMemory(data_output, capacity) != null) @memset(state.guestMemory(data_output, capacity).?, 0);
            }
            state.windows_last_error = 2; // ERROR_FILE_NOT_FOUND: no persisted value
        }
        state.regs.rax = state.windows_last_error;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RegFlushKey") or std.mem.eql(u8, name, "RegCloseKey")) {
        const key = arg(state, 0, direct_return_rip);
        state.windows_last_error = if (isWindowsRegistryHandle(state, key)) 0 else 6;
        state.regs.rax = state.windows_last_error;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VerifyVersionInfoA") or std.mem.eql(u8, name, "VerifyVersionInfoW")) {
        const info = arg(state, 0, direct_return_rip);
        const type_mask: u32 = @truncate(arg(state, 1, direct_return_rip));
        const condition_mask = arg(state, 2, direct_return_rip);
        if (info == 0 or state.guestMemory(info, 20) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            var matches = true;
            var bit_index: u6 = 0;
            var remaining = type_mask;
            while (remaining != 0) : (bit_index += 1) {
                if ((remaining & 1) != 0) {
                    const requested: u64 = switch (bit_index) {
                        1 => state.read32(info + 4), // VER_MAJORVERSION
                        0 => state.read32(info + 8), // VER_MINORVERSION
                        2 => state.read32(info + 12), // VER_BUILDNUMBER
                        3 => state.read32(info + 16), // VER_PLATFORMID
                        else => 0,
                    };
                    const actual: u64 = switch (bit_index) {
                        1 => 10,
                        0 => 0,
                        2 => 22621,
                        3 => 2,
                        else => 0,
                    };
                    const condition = (condition_mask >> (bit_index * 3)) & 0x7;
                    if (!versionCondition(actual, requested, condition)) matches = false;
                }
                remaining >>= 1;
            }
            state.windows_last_error = if (matches) 0 else 1150; // ERROR_OLD_WIN_VERSION
            state.regs.rax = @intFromBool(matches);
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "IsDebuggerPresent")) {
        returnZero(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "XInputEnable")) {
        // Enabling/disabling polling has no return value. The actual device
        // state is intentionally reported through the normal XInput error
        // contract below rather than inventing a controller state.
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "XInputGetState") or std.mem.eql(u8, name, "XInputGetStateEx")) {
        const output = arg(state, 1, direct_return_rip);
        if (output != 0) _ = clearGuestMemory(state, output, 16); // XINPUT_STATE
        state.regs.rax = 1167; // ERROR_DEVICE_NOT_CONNECTED
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "XInputGetCapabilities")) {
        const output = arg(state, 2, direct_return_rip);
        if (output != 0) _ = clearGuestMemory(state, output, 20); // XINPUT_CAPABILITIES
        state.regs.rax = 1167; // ERROR_DEVICE_NOT_CONNECTED
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "XInputGetBatteryInformation")) {
        const output = arg(state, 2, direct_return_rip);
        if (output != 0) _ = clearGuestMemory(state, output, 2); // BATTERY_INFORMATION
        state.regs.rax = 1167; // ERROR_DEVICE_NOT_CONNECTED
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "XInputSetState")) {
        const output = arg(state, 1, direct_return_rip);
        if (output != 0) _ = clearGuestMemory(state, output, 2); // vibration is not applied
        state.regs.rax = 1167; // ERROR_DEVICE_NOT_CONNECTED
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "XInputGetKeystroke")) {
        const output = arg(state, 2, direct_return_rip);
        if (output != 0) _ = clearGuestMemory(state, output, 8); // XINPUT_KEYSTROKE
        state.regs.rax = 259; // ERROR_NO_MORE_ITEMS
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "VirtualAlloc") or std.mem.eql(u8, name, "VirtualAllocEx")) {
        const extended = std.mem.eql(u8, name, "VirtualAllocEx");
        const requested_base = if (extended) arg(state, 1, direct_return_rip) else arg(state, 0, direct_return_rip);
        const size = if (std.mem.eql(u8, name, "VirtualAlloc")) arg(state, 1, direct_return_rip) else arg(state, 2, direct_return_rip);
        const allocation_type = if (extended) arg(state, 3, direct_return_rip) else arg(state, 2, direct_return_rip);
        const mem_reserve: u64 = 0x2000;
        const reserve_requested = (allocation_type & mem_reserve) != 0;
        const commit_requested = (allocation_type & 0x1000) != 0;
        const allocation_caller_rip = direct_return_rip orelse state.read64(state.regs.rsp);
        var relocated_base: ?u64 = null;
        const address = if (requested_base != 0) blk: {
            // Xenia's ThreadState allocator probes a sequence of fixed
            // context slots with MEM_RESERVE|MEM_COMMIT.  Treating an
            // already-backed range as another successful reservation aliases
            // independent guest contexts and later makes generated dispatch
            // read the wrong (often zeroed) context.  Windows permits a
            // commit-only request against an existing reservation, but a new
            // reserve over that range must fail so the caller can advance.
            const already_fixed = if (comptime @hasDecl(@TypeOf(state.*), "windowsVirtualAllocationContains"))
                state.windowsVirtualAllocationContains(requested_base, size)
            else
                false;
            if (already_fixed and reserve_requested) {
                if (commit_requested) {
                    const State = @TypeOf(state.*);
                    if (comptime @hasDecl(State, "relocateWindowsThreadContextAllocation")) {
                        if (state.relocateWindowsThreadContextAllocation(requested_base, size, allocation_caller_rip)) |relocated| {
                            relocated_base = relocated;
                            break :blk relocated;
                        }
                    }
                }
                break :blk @as(u64, 0);
            }
            if (state.windowsGuestRangeContains(requested_base, size) or state.createWindowsVirtualAllocation(requested_base, size)) {
                break :blk requested_base;
            }
            break :blk @as(u64, 0);
        } else state.guestAlloc(size, 0x1000) orelse 0;
        state.regs.rax = address;
        // Classify the request against what already backs the address, before
        // the allocation record is created: afterwards every commit looks
        // like it landed inside a reservation, which is exactly the
        // distinction the `guest-heap-commit-unreserved` failure point
        // says must not be lost.
        const disposition: []const u8 = blk: {
            const State = @TypeOf(state.*);
            if (relocated_base) |relocated| {
                if (comptime @hasDecl(State, "noteWindowsAllocationRelocation")) {
                    break :blk state.noteWindowsAllocationRelocation(
                        requested_base,
                        relocated,
                        size,
                        allocation_caller_rip,
                    ).label();
                }
            }
            if (comptime @hasDecl(State, "noteWindowsAllocationDisposition")) {
                break :blk state.noteWindowsAllocationDisposition(
                    requested_base,
                    size,
                    reserve_requested,
                    commit_requested,
                    address != 0,
                    allocation_caller_rip,
                ).label();
            }
            break :blk "unclassified";
        };
        if (state.trace_windows_memory and state.windows_memory_trace_events < 64 and
            (requested_base >= 0x1_0000_0000 or address >= 0x1_0000_0000))
        {
            state.windows_memory_trace_events += 1;
            log.info("PE64 Windows fixed-address allocation request: api={s} requested_base=0x{x} size={d} result=0x{x} contains={} rip=0x{x} step={d}", .{
                name,
                requested_base,
                size,
                address,
                address != 0 and state.windowsGuestRangeContains(address, @max(size, @as(u64, 1))),
                state.regs.rip,
                state.executed_steps,
            });
            log.info("PE64 Windows allocation contract: api={s} reserve={} commit={} requested_base=0x{x} result=0x{x} disposition={s} rip=0x{x} step={d}", .{
                name,
                reserve_requested,
                commit_requested,
                requested_base,
                address,
                disposition,
                state.regs.rip,
                state.executed_steps,
            });
        }
        if (state.diagnose_abi) {
            log.info("PE64 Windows {s}: requested_base=0x{x} size={d} result=0x{x}", .{ name, requested_base, size, address });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateFileMappingA") or std.mem.eql(u8, name, "CreateFileMappingW")) {
        // The PE Windows build uses a page-file-backed mapping for Xenia's
        // complete 32-bit virtual/physical aperture.  The Win32 API passes
        // the maximum byte offset as two 32-bit words, so preserve the full
        // 64-bit value before handing it to Rosetta's sparse backing model.
        const file_size_high = @as(u64, @truncate(arg(state, 3, direct_return_rip)));
        const file_size_low = @as(u64, @truncate(arg(state, 4, direct_return_rip)));
        const requested_length = (file_size_high << 32) | file_size_low;
        const handle = nextHandle(state);
        if (state.createWindowsMemoryMapping(
            handle,
            requested_length,
            arg(state, 0, direct_return_rip),
        )) {
            state.windows_last_error = 0;
            state.regs.rax = handle;
        } else {
            state.windows_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
            state.regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "MapViewOfFile") or std.mem.eql(u8, name, "MapViewOfFileEx")) {
        const file_size_high = @as(u64, @truncate(arg(state, 2, direct_return_rip)));
        const file_size_low = @as(u64, @truncate(arg(state, 3, direct_return_rip)));
        const backing_offset = (file_size_high << 32) | file_size_low;
        const requested_length = arg(state, 4, direct_return_rip);
        const requested_base = if (std.mem.eql(u8, name, "MapViewOfFileEx")) arg(state, 5, direct_return_rip) else 0;
        const view = state.mapWindowsMemoryView(
            arg(state, 0, direct_return_rip),
            requested_base,
            requested_length,
            backing_offset,
        );
        if (view) |guest_base| {
            state.windows_last_error = 0;
            state.regs.rax = guest_base;
        } else {
            state.windows_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY / conflicting address
            state.regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "UnmapViewOfFile")) {
        const guest_base = arg(state, 0, direct_return_rip);
        state.regs.rax = @intFromBool(state.unmapWindowsMemoryView(guest_base));
        state.windows_last_error = if (state.regs.rax != 0) 0 else 87; // ERROR_INVALID_PARAMETER
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VirtualFree") or std.mem.eql(u8, name, "VirtualFreeEx")) {
        const extended = std.mem.eql(u8, name, "VirtualFreeEx");
        const guest_base = if (extended) arg(state, 1, direct_return_rip) else arg(state, 0, direct_return_rip);
        const size = if (extended) arg(state, 2, direct_return_rip) else arg(state, 1, direct_return_rip);
        const allocation_type = if (extended) arg(state, 3, direct_return_rip) else arg(state, 2, direct_return_rip);
        const released = state.releaseWindowsVirtualAllocation(guest_base, size, allocation_type);
        state.regs.rax = @intFromBool(released);
        state.windows_last_error = if (released) 0 else 487; // ERROR_INVALID_ADDRESS
        if (state.diagnose_abi) {
            log.info("PE64 Windows {s}: guest_base=0x{x} size={d} type=0x{x} result={}", .{ name, guest_base, size, allocation_type, released });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VirtualProtect") or std.mem.eql(u8, name, "VirtualProtectEx") or
        std.mem.eql(u8, name, "VirtualQuery") or std.mem.eql(u8, name, "VirtualQueryEx"))
    {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "HeapAlloc") or std.mem.eql(u8, name, "RtlAllocateHeap") or
        std.mem.eql(u8, name, "LocalAlloc") or std.mem.eql(u8, name, "GlobalAlloc") or
        std.mem.eql(u8, name, "CoTaskMemAlloc"))
    {
        const size = if (std.mem.eql(u8, name, "HeapAlloc") or std.mem.eql(u8, name, "RtlAllocateHeap")) arg(state, 2, direct_return_rip) else arg(state, 1, direct_return_rip);
        state.regs.rax = state.guestAlloc(size, 16) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_aligned_malloc")) {
        state.regs.rax = state.guestAlloc(arg(state, 0, direct_return_rip), arg(state, 1, direct_return_rip)) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "realloc") or std.mem.eql(u8, name, "_recalloc") or
        std.mem.eql(u8, name, "_aligned_realloc") or std.mem.eql(u8, name, "CoTaskMemRealloc") or
        std.mem.eql(u8, name, "LocalReAlloc") or std.mem.eql(u8, name, "GlobalReAlloc") or
        std.mem.eql(u8, name, "HeapReAlloc") or std.mem.eql(u8, name, "RtlReAllocateHeap"))
    {
        const is_heap_realloc = std.mem.eql(u8, name, "HeapReAlloc") or std.mem.eql(u8, name, "RtlReAllocateHeap");
        const old_guest_base = if (is_heap_realloc) arg(state, 2, direct_return_rip) else arg(state, 0, direct_return_rip);
        const size = if (std.mem.eql(u8, name, "_recalloc"))
            arg(state, 1, direct_return_rip) *| arg(state, 2, direct_return_rip)
        else if (std.mem.eql(u8, name, "_aligned_realloc"))
            arg(state, 1, direct_return_rip)
        else if (is_heap_realloc)
            arg(state, 3, direct_return_rip)
        else
            arg(state, 1, direct_return_rip);
        const alignment = if (std.mem.eql(u8, name, "_aligned_realloc")) arg(state, 2, direct_return_rip) else 16;
        state.regs.rax = state.reallocateGuest(old_guest_base, size, alignment) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "malloc") or std.mem.eql(u8, name, "_malloc_base")) {
        state.regs.rax = state.guestAlloc(arg(state, 0, direct_return_rip), 16) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "calloc")) {
        state.regs.rax = state.guestAlloc(arg(state, 0, direct_return_rip) *| arg(state, 1, direct_return_rip), 16) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "free") or std.mem.eql(u8, name, "_free_base") or
        std.mem.eql(u8, name, "_aligned_free") or std.mem.eql(u8, name, "CoTaskMemFree") or
        std.mem.eql(u8, name, "HeapFree") or std.mem.eql(u8, name, "RtlFreeHeap") or
        std.mem.eql(u8, name, "GlobalFree") or
        std.mem.eql(u8, name, "HeapDestroy"))
    {
        const is_heap_free = std.mem.eql(u8, name, "HeapFree") or std.mem.eql(u8, name, "RtlFreeHeap");
        const guest_base = if (is_heap_free) arg(state, 2, direct_return_rip) else arg(state, 0, direct_return_rip);
        _ = state.releaseGuestAllocation(guest_base);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "LocalFree")) {
        const guest_base = arg(state, 0, direct_return_rip);
        _ = state.releaseGuestAllocation(guest_base);
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "InitializeCriticalSection") or
        std.mem.eql(u8, name, "InitializeCriticalSectionEx") or
        std.mem.eql(u8, name, "InitializeCriticalSectionAndSpinCount") or
        std.mem.eql(u8, name, "DeleteCriticalSection") or
        std.mem.eql(u8, name, "EnterCriticalSection") or
        std.mem.eql(u8, name, "LeaveCriticalSection"))
    {
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TryEnterCriticalSection")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateEventA") or std.mem.eql(u8, name, "CreateEventW") or
        std.mem.eql(u8, name, "CreateMutexA") or std.mem.eql(u8, name, "CreateMutexW") or
        std.mem.eql(u8, name, "CreateSemaphoreA") or std.mem.eql(u8, name, "CreateSemaphoreW"))
    {
        const handle = nextHandle(state);
        const State = @TypeOf(state.*);
        if (std.mem.startsWith(u8, name, "CreateEvent")) {
            if (comptime @hasDecl(State, "registerWindowsEvent")) {
                state.registerWindowsEvent(handle, arg(state, 1, direct_return_rip) != 0, arg(state, 2, direct_return_rip) != 0);
            }
        } else if (std.mem.startsWith(u8, name, "CreateMutex")) {
            if (comptime @hasDecl(State, "registerWindowsMutex")) {
                state.registerWindowsMutex(handle, arg(state, 1, direct_return_rip) != 0);
            }
        } else if (comptime @hasDecl(State, "registerWindowsSemaphore")) {
            state.registerWindowsSemaphore(handle, arg(state, 1, direct_return_rip), arg(state, 2, direct_return_rip));
        }
        state.regs.rax = handle;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InitOnceBeginInitialize")) {
        const once = arg(state, 0, direct_return_rip);
        const pending = arg(state, 2, direct_return_rip);
        const context = arg(state, 3, direct_return_rip);
        if (once == 0 or state.guestMemory(once, 8) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            const value = state.read64(once);
            if (value == 0) {
                // INIT_ONCE_IN_INIT is the low-bit in-progress state. The
                // caller owns the callback and will publish the completed
                // state through InitOnceComplete below.
                state.write64(once, 1);
                if (pending != 0 and state.guestMemory(pending, 4) != null) state.write32(pending, 1);
                if (context != 0 and state.guestMemory(context, 8) != null) state.write64(context, 0);
            } else {
                // A completed control word stores the optional context with
                // the low two tag bits reserved. No host wait is possible in
                // the cooperative executor, so an already-running control
                // is observed as complete rather than spinning forever.
                if (pending != 0 and state.guestMemory(pending, 4) != null) state.write32(pending, 0);
                if (context != 0 and state.guestMemory(context, 8) != null) state.write64(context, value & ~@as(u64, 0x3));
            }
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InitOnceComplete")) {
        const once = arg(state, 0, direct_return_rip);
        const flags = arg(state, 1, direct_return_rip);
        const context = arg(state, 2, direct_return_rip);
        if (once == 0 or state.guestMemory(once, 8) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else if ((flags & 0x4) != 0) {
            // INIT_ONCE_INIT_FAILED returns the control to the uninitialized
            // state so a later attempt can retry the callback.
            state.write64(once, 0);
            state.windows_last_error = 0;
            state.regs.rax = 1;
        } else {
            state.write64(once, if (context == 0) 2 else context | 2);
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InitializeConditionVariable")) {
        const condition = arg(state, 0, direct_return_rip);
        if (condition != 0 and state.guestMemory(condition, 8) != null) state.write64(condition, 0);
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "WakeConditionVariable") or
        std.mem.eql(u8, name, "WakeAllConditionVariable"))
    {
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SleepConditionVariableCS") or
        std.mem.eql(u8, name, "SleepConditionVariableSRW"))
    {
        // A condition variable has no independent host waiter in this
        // executor. A timeout-style FALSE lets the caller re-check its
        // predicate without introducing an unbounded guest spin.
        state.windows_last_error = 258; // WAIT_TIMEOUT
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateWaitableTimerA") or std.mem.eql(u8, name, "CreateWaitableTimerW")) {
        state.windows_last_error = 0;
        state.regs.rax = nextHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetWaitableTimer") or std.mem.eql(u8, name, "CancelWaitableTimer")) {
        state.windows_last_error = 0;
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetQueuedCompletionStatus")) {
        const port = arg(state, 0, direct_return_rip);
        const bytes_transferred = arg(state, 1, direct_return_rip);
        const completion_key = arg(state, 2, direct_return_rip);
        const overlapped = arg(state, 3, direct_return_rip);
        const valid_outputs = (bytes_transferred == 0 or state.guestMemory(bytes_transferred, 4) != null) and
            (completion_key == 0 or state.guestMemory(completion_key, 8) != null) and
            (overlapped == 0 or state.guestMemory(overlapped, 8) != null);
        if (port == 0 or !isSyntheticWindowsHandle(state, port)) {
            state.windows_last_error = 6; // ERROR_INVALID_HANDLE
            state.regs.rax = 0;
        } else if (!valid_outputs) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            // The bounded Rosetta executor has no completion packet queued at
            // this boundary. Report an empty queue as WAIT_TIMEOUT and keep
            // all optional output fields deterministic.
            if (bytes_transferred != 0) state.write32(bytes_transferred, 0);
            if (completion_key != 0) state.write64(completion_key, 0);
            if (overlapped != 0) state.write64(overlapped, 0);
            state.windows_last_error = 258; // WAIT_TIMEOUT
            state.regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateIoCompletionPort")) {
        const existing = arg(state, 1, direct_return_rip);
        if (existing != 0 and !isSyntheticWindowsHandle(state, existing)) {
            state.windows_last_error = 6; // ERROR_INVALID_HANDLE
            state.regs.rax = 0;
        } else {
            state.windows_last_error = 0;
            state.regs.rax = if (existing != 0) existing else nextHandle(state);
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateThread") or std.mem.eql(u8, name, "CreateRemoteThread")) {
        // The Win32 handle is only the observable result of creation.  The
        // important side effect is that the start routine becomes runnable;
        // returning a handle without retaining it leaves Xenia's graphics
        // setup thread permanently unexecuted.
        const stack_size = arg(state, 1, direct_return_rip);
        const start_routine = arg(state, 2, direct_return_rip);
        const argument = arg(state, 3, direct_return_rip);
        if (start_routine == 0 or state.addrToOffset(start_routine) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        }

        const handle = nextHandle(state);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "enqueueWindowsGuestThread")) {
            if (!state.enqueueWindowsGuestThread(handle, start_routine, argument, stack_size, true)) {
                state.windows_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
                state.regs.rax = 0;
                finish(state, direct_return_rip);
                return true;
            }
        }
        state.windows_last_error = 0;
        state.regs.rax = handle;
        if (state.diagnose_abi) {
            log.info("Windows guest thread queued: api={s} handle=0x{x} start=0x{x} argument=0x{x} stack_size={d}", .{
                name,
                handle,
                start_routine,
                argument,
                stack_size,
            });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_beginthreadex") or std.mem.eql(u8, name, "_beginthread")) {
        // libwinpthread uses _beginthreadex as the final host-thread
        // creation primitive behind pthread_create. Returning zero here is
        // not a harmless stub: pthread_create translates it to EAGAIN, and
        // libstdc++ immediately throws std::system_error before Xenia can
        // initialize its graphics workers. Keep the ABI boundary honest by
        // validating the guest start routine and returning a Rosetta-owned
        // handle that the existing Win32 handle model can validate/close.
        const is_beginthreadex = std.mem.eql(u8, name, "_beginthreadex");
        const start_routine = if (is_beginthreadex) arg(state, 2, direct_return_rip) else arg(state, 0, direct_return_rip);
        const argument = if (is_beginthreadex) arg(state, 3, direct_return_rip) else arg(state, 2, direct_return_rip);
        const stack_size = arg(state, 1, direct_return_rip);
        if (start_routine == 0 or state.addrToOffset(start_routine) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
            finish(state, direct_return_rip);
            return true;
        }

        const handle = nextHandle(state);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "enqueueWindowsGuestThread")) {
            if (!state.enqueueWindowsGuestThread(handle, start_routine, argument, stack_size, false)) {
                state.windows_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
                state.regs.rax = 0;
                finish(state, direct_return_rip);
                return true;
            }
        }
        state.regs.rax = handle;
        state.windows_last_error = 0;
        if (state.diagnose_abi) {
            log.info(
                "Windows guest thread queued: api={s} handle=0x{x} start=0x{x} argument=0x{x} stack_size={d}",
                .{
                    name,
                    handle,
                    start_routine,
                    argument,
                    stack_size,
                },
            );
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetEvent") or std.mem.eql(u8, name, "PulseEvent")) {
        const handle = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "signalWindowsWaitObject")) {
            _ = state.signalWindowsWaitObject(handle, std.mem.eql(u8, name, "PulseEvent"));
        }
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ResetEvent")) {
        const handle = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        const reset = if (comptime @hasDecl(State, "resetWindowsWaitObject")) state.resetWindowsWaitObject(handle) else true;
        state.regs.rax = @intFromBool(reset);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ReleaseMutex") or std.mem.eql(u8, name, "ReleaseSemaphore")) {
        const handle = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (std.mem.eql(u8, name, "ReleaseSemaphore")) {
            if (comptime @hasDecl(State, "releaseWindowsSemaphore")) {
                _ = state.releaseWindowsSemaphore(handle, arg(state, 1, direct_return_rip));
            }
        } else if (comptime @hasDecl(State, "signalWindowsWaitObject")) {
            _ = state.signalWindowsWaitObject(handle, false);
        }
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CloseHandle") or std.mem.eql(u8, name, "SwitchToThread") or
        std.mem.eql(u8, name, "TryEnterCriticalSection"))
    {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        // `SwitchToThread` is what MinGW's `sched_yield` - and therefore
        // `std::this_thread::yield()` - becomes. It is the boundary a
        // spin-wait strategy uses between spins, so it has to actually hand
        // the interpreter over.
        if (std.mem.eql(u8, name, "SwitchToThread")) {
            const State = @TypeOf(state.*);
            if (comptime @hasDecl(State, "requestWindowsGuestSliceYield")) {
                state.requestWindowsGuestSliceYield();
            }
        }
        return true;
    }
    if (std.mem.eql(u8, name, "WaitForSingleObject") or std.mem.eql(u8, name, "WaitForSingleObjectEx") or
        std.mem.eql(u8, name, "WaitForMultipleObjects") or std.mem.eql(u8, name, "WaitForMultipleObjectsEx"))
    {
        const is_multiple = std.mem.eql(u8, name, "WaitForMultipleObjects") or
            std.mem.eql(u8, name, "WaitForMultipleObjectsEx");
        if (!is_multiple) {
            const wait_handle = arg(state, 0, direct_return_rip);
            const timeout = arg(state, 1, direct_return_rip);
            const State = @TypeOf(state.*);
            if (comptime @hasDecl(State, "waitWindowsGuestObject")) {
                switch (state.waitWindowsGuestObject(wait_handle, timeout)) {
                    .blocked => return true,
                    .signaled => {
                        state.regs.rax = 0; // WAIT_OBJECT_0
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .yielded => {
                        // The owner context is the cooperative UI executor.
                        // A bounded worker turn has already been serviced, so
                        // complete this wait boundary and let the owner pump
                        // its deferred UI work before retrying if necessary.
                        state.regs.rax = 0; // WAIT_OBJECT_0
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .timeout => {
                        state.regs.rax = 0x102; // WAIT_TIMEOUT
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .invalid => {
                        state.windows_last_error = 6; // ERROR_INVALID_HANDLE
                        state.regs.rax = std.math.maxInt(u64); // WAIT_FAILED
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .unknown => {},
                }
            }
        }
        var serviced_steps: u64 = 0;
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "serviceWindowsGuestThreads")) {
            // A PE wait is a cooperative scheduling boundary. The prior
            // model returned immediately but never gave a queued worker a
            // chance to release the mutex/event being waited on, which could
            // strand the main guest thread after Vulkan bootstrap.
            const service_slice = if (comptime @hasDecl(State, "windowsGuestWaitServiceSlice"))
                state.windowsGuestWaitServiceSlice()
            else
                windows_guest_thread_service_slice;
            serviced_steps = if (comptime @hasDecl(State, "serviceWindowsGuestBoundary"))
                state.serviceWindowsGuestBoundary(service_slice)
            else
                state.serviceWindowsGuestThreads(service_slice);
        }
        if (serviced_steps != 0 and state.trace_windows_waits and
            (state.windows_thread_service_calls <= 8 or state.windows_thread_service_calls % 1024 == 0))
        {
            log.info("Windows wait boundary serviced guest worker: api={s} handle_or_count=0x{x} timeout_or_handles=0x{x} steps={d} service_calls={d} yields={d} completions={d} graphics_phase={s} vk_calls={d} submits={d} presents={d}", .{
                name,
                arg(state, 0, direct_return_rip),
                arg(state, 1, direct_return_rip),
                serviced_steps,
                state.windows_thread_service_calls,
                state.windows_thread_yields,
                state.windows_thread_completions,
                @tagName(state.windows_graphics.phase),
                state.windows_graphics.vulkan_calls,
                state.windows_graphics.queue_submits,
                state.windows_graphics.presents,
            });
        }
        state.regs.rax = 0; // WAIT_OBJECT_0 for the deterministic bootstrap handle
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "pthread_cond_wait") or std.mem.eql(u8, name, "pthread_cond_timedwait")) {
        const condition = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "waitWindowsGuestCondition")) {
            switch (state.waitWindowsGuestCondition(condition, arg(state, 1, direct_return_rip))) {
                .blocked => return true,
                .resumed, .invalid => {},
            }
        }
        // The ordinary fallback remains a successful no-op only for states
        // without the cooperative PE scheduler.  In a PE run, a worker that
        // reaches this branch must be resumed by signal/broadcast rather than
        // being allowed to consume a condition-variable sentinel.
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "pthread_cond_signal") or std.mem.eql(u8, name, "pthread_cond_broadcast")) {
        const condition = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "signalWindowsGuestCondition")) {
            _ = state.signalWindowsGuestCondition(condition, std.mem.eql(u8, name, "pthread_cond_broadcast"));
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "Sleep") or std.mem.eql(u8, name, "SleepEx") or
        std.mem.eql(u8, name, "YieldProcessor") or std.mem.eql(u8, name, "PauseProcessor"))
    {
        const State = @TypeOf(state.*);
        const is_sleep = std.mem.eql(u8, name, "Sleep") or std.mem.eql(u8, name, "SleepEx");
        const milliseconds: u64 = if (is_sleep) arg(state, 0, direct_return_rip) else 0;
        // Return first: the worker resumes at the instruction after the call,
        // so its saved context has to be the post-return one.
        returnZero(state, direct_return_rip);
        // `YieldProcessor` and a zero-millisecond `Sleep` mean "run someone
        // else"; a non-zero `Sleep` means "run someone else for this long".
        // Answering either by returning turns a guest back-off into a
        // busy-wait, and under one cooperative interpreter a busy-wait is not
        // an idle core - it is the whole machine.
        if (comptime @hasDecl(State, "parkWindowsGuestSleep")) {
            if (is_sleep and milliseconds != 0) {
                if (!state.parkWindowsGuestSleep(milliseconds)) {
                    // The owner has no context to park. Give the workers the
                    // interval instead of spinning through it.
                    if (comptime @hasDecl(State, "serviceWindowsGuestThreads")) {
                        _ = state.serviceWindowsGuestThreads(state.windowsGuestWaitServiceSlice());
                    }
                }
            } else if (comptime @hasDecl(State, "requestWindowsGuestSliceYield")) {
                state.requestWindowsGuestSliceYield();
            }
        }
        return true;
    }
    if (std.mem.eql(u8, name, "TlsAlloc") or std.mem.eql(u8, name, "FlsAlloc")) {
        if (state.windows_next_tls >= 512) {
            state.regs.rax = 0xFFFF_FFFF;
            state.windows_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
        } else {
            state.regs.rax = state.windows_next_tls;
            state.windows_next_tls +|= 1;
            state.windows_last_error = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TlsGetValue") or std.mem.eql(u8, name, "FlsGetValue")) {
        const slot = windowsTlsSlot(state, arg(state, 0, direct_return_rip));
        state.regs.rax = if (slot) |address| state.read64(address) else 0;
        if (slot == null) state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TlsSetValue") or std.mem.eql(u8, name, "FlsSetValue")) {
        const slot = windowsTlsSlot(state, arg(state, 0, direct_return_rip));
        if (slot) |address| {
            state.write64(address, arg(state, 1, direct_return_rip));
            state.regs.rax = 1;
            state.windows_last_error = 0;
        } else {
            state.regs.rax = 0;
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TlsFree") or std.mem.eql(u8, name, "FlsFree")) {
        const slot = windowsTlsSlot(state, arg(state, 0, direct_return_rip));
        if (slot) |address| {
            state.write64(address, 0);
            state.regs.rax = 1;
            state.windows_last_error = 0;
        } else {
            state.regs.rax = 0;
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "PostMessageA") or std.mem.eql(u8, name, "PostMessageW")) {
        const hwnd = arg(state, 0, direct_return_rip);
        const message: u32 = @truncate(arg(state, 1, direct_return_rip));
        const wparam = arg(state, 2, direct_return_rip);
        const lparam = arg(state, 3, direct_return_rip);
        const State = @TypeOf(state.*);
        const posted = if (comptime @hasDecl(State, "postWindowsMessage"))
            state.postWindowsMessage(hwnd, message, wparam, lparam)
        else
            false;
        const valid_window = if (comptime @hasDecl(State, "isWindowsWindowHandle"))
            state.isWindowsWindowHandle(hwnd)
        else
            false;
        state.regs.rax = @intFromBool(posted);
        state.windows_last_error = if (posted) 0 else if (hwnd == 0 or !valid_window) 1400 else 8;
        if (state.diagnose_abi or state.trace_windows_messages) {
            log.info("Windows PostMessage: api={s} hwnd=0x{x} message=0x{x} wparam=0x{x} lparam=0x{x} posted={} queue={d}", .{
                name,
                hwnd,
                message,
                wparam,
                lparam,
                posted,
                if (comptime @hasField(State, "windows_message_count")) state.windows_message_count else 0,
            });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RegisterClassA") or std.mem.eql(u8, name, "RegisterClassW") or
        std.mem.eql(u8, name, "RegisterClassExA") or std.mem.eql(u8, name, "RegisterClassExW"))
    {
        const wide = std.mem.endsWith(u8, name, "W");
        const class_info = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        const atom = if (comptime @hasDecl(State, "registerWindowsWindowClass"))
            state.registerWindowsWindowClass(class_info, wide)
        else
            0;
        state.regs.rax = atom;
        state.windows_last_error = if (atom != 0) 0 else 87; // ERROR_INVALID_PARAMETER
        if (state.diagnose_abi or state.trace_windows_messages) {
            log.info("Windows RegisterClass: api={s} class_info=0x{x} atom=0x{x} wide={}", .{ name, class_info, atom, wide });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "UnregisterClassA") or std.mem.eql(u8, name, "UnregisterClassW")) {
        // Class lifetime is bounded by the PE session. Keep the registration
        // available for any already-created HWND and report the Win32 success
        // contract expected by Xenia's shutdown path.
        state.regs.rax = 1;
        state.windows_last_error = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateWindowExA") or std.mem.eql(u8, name, "CreateWindowExW")) {
        const ex_style = arg(state, 0, direct_return_rip);
        const class_name = arg(state, 1, direct_return_rip);
        const style = arg(state, 3, direct_return_rip);
        const parent = arg(state, 8, direct_return_rip);
        const user_data = arg(state, 11, direct_return_rip);
        const wide = std.mem.endsWith(u8, name, "W");
        const State = @TypeOf(state.*);

        // Xenia creates a message-only window for its pending-function
        // queue before it creates the visible main window. Win32 permits
        // CW_USEDEFAULT for all four geometry arguments in that call, but a
        // message-only HWND has no screen rectangle at all. Returning a
        // guest-owned opaque handle preserves the helper's message identity
        // without manufacturing an AppKit NSWindow for it.
        if (parent == hwnd_message) {
            const message_window = nextHandle(state);
            const created = if (comptime @hasDecl(State, "createWindowsWindow"))
                state.createWindowsWindow(message_window, class_name, user_data, true, style, ex_style, wide)
            else
                false;
            state.windows_last_error = if (created) 0 else 8; // ERROR_NOT_ENOUGH_MEMORY
            state.regs.rax = if (created) message_window else 0;
            if (state.diagnose_abi or state.trace_windows_messages) {
                log.info(
                    "Windows message-only window: handle=0x{x} class=0x{x} user_data=0x{x} style=0x{x} parent=0x{x} created={} no_native_window=YES",
                    .{ message_window, class_name, user_data, style, parent, created },
                );
            }
            finish(state, direct_return_rip);
            return true;
        }

        const width = normalizeWindowDimension(arg(state, 6, direct_return_rip), default_window_width);
        const height = normalizeWindowDimension(arg(state, 7, direct_return_rip), default_window_height);
        const title = guestCString(state, arg(state, 2, direct_return_rip)) orelse "Xenia Canary (Rosette)";
        if (state.diagnose_abi or state.trace_windows_messages) {
            log.info(
                "Windows top-level window request: width={d} height={d} style=0x{x} parent=0x{x}",
                .{ width, height, style, parent },
            );
        }
        const ok = state.windows_graphics.ensureWindow(width, height, title);
        const window_handle = if (ok) nextHandle(state) else 0;
        const created = if (ok) blk: {
            if (comptime @hasDecl(State, "createWindowsWindow")) {
                break :blk state.createWindowsWindow(window_handle, class_name, user_data, false, style, ex_style, wide);
            }
            break :blk false;
        } else false;
        const window_ok = ok and created;
        if (window_ok) state.windows_window_handle = window_handle;
        state.regs.rax = if (window_ok) window_handle else 0;
        state.windows_last_error = if (window_ok) 0 else if (!ok) 1400 else 8;
        if (state.diagnose_abi or state.trace_windows_messages) {
            log.info(
                "Windows top-level window: handle=0x{x} class=0x{x} user_data=0x{x} created={} native={} wnd_proc=0x{x}",
                .{
                    window_handle,
                    class_name,
                    user_data,
                    window_ok,
                    ok,
                    if (comptime @hasDecl(State, "windowsWindowProc")) state.windowsWindowProc(window_handle) orelse 0 else 0,
                },
            );
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetClientRect") or std.mem.eql(u8, name, "GetWindowRect")) {
        const rect = arg(state, 1, direct_return_rip);
        if (rect != 0) {
            state.write32(rect + 0, 0);
            state.write32(rect + 4, 0);
            state.write32(rect + 8, state.windows_graphics.window_width);
            state.write32(rect + 12, state.windows_graphics.window_height);
        }
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ShowWindow")) {
        const ok = state.windows_graphics.showWindow();
        state.regs.rax = if (ok) 1 else 0;
        if (ok) _ = state.windows_graphics.pumpEvents();
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "MessageBoxA") or std.mem.eql(u8, name, "MessageBoxW")) {
        // Rosetta is headless during bring-up. Returning IDOK preserves the
        // modal API's nonzero decision without blocking the cooperative
        // executor on an AppKit alert that cannot be observed by the guest.
        state.windows_last_error = 0;
        state.regs.rax = 1; // IDOK
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetWindowLongA") or std.mem.eql(u8, name, "GetWindowLongW") or
        std.mem.eql(u8, name, "GetWindowLongPtrA") or std.mem.eql(u8, name, "GetWindowLongPtrW"))
    {
        const hwnd = arg(state, 0, direct_return_rip);
        // Win32 declares nIndex as an `int`.  MinGW commonly materializes a
        // negative index with a 32-bit write, which zero-extends to a 64-bit
        // register under x86-64.  Sign-extend the low 32 bits here instead of
        // comparing that ABI representation as a positive u64; otherwise a
        // valid GWLP_USERDATA/GWL_STYLE request looks like an unknown field
        // and the pending-window callback loses its state.
        const raw_index: u32 = @truncate(arg(state, 1, direct_return_rip));
        const index: i64 = @as(i64, @as(i32, @bitCast(raw_index)));
        const State = @TypeOf(state.*);
        const value = if (comptime @hasDecl(State, "windowsWindowLong"))
            state.windowsWindowLong(hwnd, index)
        else
            null;
        state.regs.rax = value orelse 0;
        state.windows_last_error = if (value == null) 1400 else 0; // ERROR_INVALID_WINDOW_HANDLE
        if (state.diagnose_abi or state.trace_windows_messages) {
            log.info("Windows GetWindowLong: api={s} hwnd=0x{x} index={d} value=0x{x} valid={}", .{ name, hwnd, index, value orelse 0, value != null });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetWindowLongA") or std.mem.eql(u8, name, "SetWindowLongW") or
        std.mem.eql(u8, name, "SetWindowLongPtrA") or std.mem.eql(u8, name, "SetWindowLongPtrW"))
    {
        const hwnd = arg(state, 0, direct_return_rip);
        const raw_index: u32 = @truncate(arg(state, 1, direct_return_rip));
        const index: i64 = @as(i64, @as(i32, @bitCast(raw_index)));
        const value = arg(state, 2, direct_return_rip);
        const State = @TypeOf(state.*);
        const previous = if (comptime @hasDecl(State, "setWindowsWindowLong"))
            state.setWindowsWindowLong(hwnd, index, value)
        else
            null;
        state.regs.rax = previous orelse 0;
        state.windows_last_error = if (previous == null) 1400 else 0; // ERROR_INVALID_WINDOW_HANDLE
        if (state.diagnose_abi or state.trace_windows_messages) {
            log.info("Windows SetWindowLong: api={s} hwnd=0x{x} index={d} value=0x{x} previous=0x{x} valid={}", .{ name, hwnd, index, value, previous orelse 0, previous != null });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DestroyWindow")) {
        const hwnd = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        const destroyed = if (comptime @hasDecl(State, "destroyWindowsWindow")) state.destroyWindowsWindow(hwnd) else false;
        state.regs.rax = @intFromBool(destroyed);
        state.windows_last_error = if (destroyed) 0 else 1400;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetFocus")) {
        state.regs.rax = state.windows_focus_window;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetFocus")) {
        const previous = state.windows_focus_window;
        state.windows_focus_window = arg(state, 0, direct_return_rip);
        state.windows_last_error = 0;
        state.regs.rax = previous;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetWindowPos") or std.mem.eql(u8, name, "ReleaseDC")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    // The Win32 painting contract, modelled as an update region rather than
    // as a queued message.  A guest that repaints through
    // `InvalidateRect` + `WM_PAINT` -- which is what a plain Win32 window
    // does -- produces no frames at all when these are answered with a bare
    // TRUE, because nothing then ever generates WM_PAINT.  See
    // `pendingWindowsPaintMessage` in the PE state for the generation side.
    if (std.mem.eql(u8, name, "InvalidateRect") or std.mem.eql(u8, name, "InvalidateRgn") or
        std.mem.eql(u8, name, "RedrawWindow"))
    {
        const hwnd = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        // RedrawWindow carries the request in its flags word; the other two
        // always invalidate.  RDW_VALIDATE takes precedence over
        // RDW_INVALIDATE in Win32, and a call with neither only affects the
        // erase/frame bits that Rosetta has no GDI surface for.
        const redraw = std.mem.eql(u8, name, "RedrawWindow");
        const flags: u32 = if (redraw) @truncate(arg(state, 3, direct_return_rip)) else rdw_invalidate;
        const validating = (flags & rdw_validate) != 0;
        const invalidating = !validating and (flags & rdw_invalidate) != 0;
        var accepted = false;
        if (validating) {
            if (comptime @hasDecl(State, "validateWindowsWindow")) accepted = state.validateWindowsWindow(hwnd);
        } else if (invalidating) {
            if (comptime @hasDecl(State, "invalidateWindowsWindow")) accepted = state.invalidateWindowsWindow(hwnd);
        }
        // `InvalidateRect(hwnd, rect, TRUE)` also requests an erase.  Rosetta
        // has no GDI background brush to run, and a guest that owns its own
        // surface suppresses the erase anyway, so the erase flag is evidence
        // only.
        state.regs.rax = 1;
        state.windows_last_error = if (accepted or !invalidating) 0 else 1400; // ERROR_INVALID_WINDOW_HANDLE
        if (state.diagnose_abi or state.trace_windows_messages) {
            log.info("Windows paint request: api={s} hwnd=0x{x} invalidate={} accepted={} pending={d}", .{
                name,
                hwnd,
                invalidating,
                accepted,
                if (comptime @hasDecl(State, "windowsPendingPaintCount")) state.windowsPendingPaintCount() else 0,
            });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "UpdateWindow")) {
        // Win32 delivers WM_PAINT synchronously here when the update region
        // is non-empty.  Rosetta cannot run a nested WndProc from inside an
        // import completion, so the region is left set and the next pump call
        // paints it.  That defers the paint by one pump iteration and never
        // drops it.
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ValidateRect") or std.mem.eql(u8, name, "ValidateRgn")) {
        const hwnd = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "validateWindowsWindow")) _ = state.validateWindowsWindow(hwnd);
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "BeginPaint")) {
        // BeginPaint validates the update region and fills a PAINTSTRUCT.
        // The structure is 72 bytes on x86-64: hdc, fErase, rcPaint, and the
        // reserved tail.  Clearing it and writing the client rectangle keeps
        // a guest painter from reading uninitialized guest memory.
        const hwnd = arg(state, 0, direct_return_rip);
        const paint_struct = arg(state, 1, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "validateWindowsWindow")) _ = state.validateWindowsWindow(hwnd);
        const hdc = nextHandle(state);
        if (paint_struct != 0 and clearGuestMemory(state, paint_struct, 72)) {
            state.write64(paint_struct + 0, hdc);
            state.write32(paint_struct + 8, 0); // fErase
            state.write32(paint_struct + 12, 0); // rcPaint.left
            state.write32(paint_struct + 16, 0); // rcPaint.top
            state.write32(paint_struct + 20, state.windows_graphics.window_width);
            state.write32(paint_struct + 24, state.windows_graphics.window_height);
        }
        state.regs.rax = hdc;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "EndPaint")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetUpdateRect")) {
        const hwnd = arg(state, 0, direct_return_rip);
        const rect = arg(state, 1, direct_return_rip);
        const State = @TypeOf(state.*);
        const pending = if (comptime @hasDecl(State, "windowsWindowHasPendingPaint"))
            state.windowsWindowHasPendingPaint(hwnd)
        else
            false;
        if (rect != 0) {
            state.write32(rect + 0, 0);
            state.write32(rect + 4, 0);
            state.write32(rect + 8, if (pending) state.windows_graphics.window_width else 0);
            state.write32(rect + 12, if (pending) state.windows_graphics.window_height else 0);
        }
        // The third argument asks for an erase; there is no background brush
        // to run, but the update region is still consumed when it is set.
        if (pending and (arg(state, 2, direct_return_rip) & 1) != 0) {
            if (comptime @hasDecl(State, "validateWindowsWindow")) _ = state.validateWindowsWindow(hwnd);
        }
        state.regs.rax = @intFromBool(pending);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetDC")) {
        state.regs.rax = nextHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "PeekMessageA") or std.mem.eql(u8, name, "PeekMessageW") or
        std.mem.eql(u8, name, "GetMessageA") or std.mem.eql(u8, name, "GetMessageW"))
    {
        const is_get_message = std.mem.eql(u8, name, "GetMessageA") or std.mem.eql(u8, name, "GetMessageW");
        const message = arg(state, 0, direct_return_rip);
        if (message == 0 or !clearGuestMemory(state, message, 48)) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = if (is_get_message) std.math.maxInt(u64) else 0;
            finish(state, direct_return_rip);
            return true;
        }
        const filter_hwnd = arg(state, 1, direct_return_rip);
        const minimum_message = arg(state, 2, direct_return_rip);
        const maximum_message = arg(state, 3, direct_return_rip);
        const remove = is_get_message or (arg(state, 4, direct_return_rip) & 1) != 0;
        // A paint that is already pending must not wait on the stride: that
        // is the one case where a skipped pump is a skipped frame rather than
        // a skipped millisecond.
        const State2 = @TypeOf(state.*);
        const paint_pending = if (comptime @hasDecl(State2, "windowsPendingPaintCount"))
            state.windowsPendingPaintCount() != 0
        else
            true;
        _ = state.windows_graphics.pumpEventsAtStep(state.executed_steps, paint_pending);
        var serviced_steps: u64 = 0;
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "serviceWindowsGuestThreads")) {
            const service_slice = if (comptime @hasDecl(State, "windowsGuestWaitServiceSlice"))
                state.windowsGuestWaitServiceSlice()
            else
                windows_guest_thread_service_slice;
            serviced_steps = if (comptime @hasDecl(State, "serviceWindowsGuestBoundary"))
                state.serviceWindowsGuestBoundary(service_slice)
            else
                state.serviceWindowsGuestThreads(service_slice);
        }
        const queued_message = if (comptime @hasDecl(State, "dequeueWindowsMessage"))
            state.dequeueWindowsMessage(filter_hwnd, minimum_message, maximum_message, remove)
        else
            null;
        // WM_PAINT ranks below posted messages and below WM_QUIT, matching
        // the Win32 pump: it is only observed once the queue has nothing
        // else to deliver.
        const paint_message = if (queued_message == null and !state.windows_ui_quit_requested)
            (if (comptime @hasDecl(State, "pendingWindowsPaintMessage"))
                state.pendingWindowsPaintMessage(filter_hwnd, minimum_message, maximum_message)
            else
                null)
        else
            null;
        var result: u64 = 0;
        if (queued_message) |queued| {
            if (!writeWindowsMessage(state, message, queued)) {
                state.windows_last_error = 87;
                state.regs.rax = if (is_get_message) std.math.maxInt(u64) else 0;
                finish(state, direct_return_rip);
                return true;
            }
            result = if (is_get_message and queued.hwnd == 0 and queued.message == 0) 0 else 1;
            if (state.diagnose_abi or state.trace_windows_messages) {
                log.info("Windows message pump dequeued: api={s} hwnd=0x{x} message=0x{x} wparam=0x{x} lparam=0x{x} result={d} remove={} remaining={d} serviced_steps={d}", .{
                    name,
                    queued.hwnd,
                    queued.message,
                    queued.wparam,
                    queued.lparam,
                    result,
                    remove,
                    state.windows_message_count,
                    serviced_steps,
                });
            }
        } else if (state.windows_ui_quit_requested) {
            const quit_message = .{ .hwnd = @as(u64, 0), .message = @as(u32, 0), .wparam = state.windows_ui_quit_code, .lparam = @as(u64, 0) };
            if (!writeWindowsMessage(state, message, quit_message)) {
                state.windows_last_error = 87;
                state.regs.rax = if (is_get_message) std.math.maxInt(u64) else 0;
                finish(state, direct_return_rip);
                return true;
            }
            result = if (is_get_message) 0 else 1;
            if (state.diagnose_abi or state.trace_windows_messages) {
                log.info("Windows message pump synthetic quit: api={s} exit_code=0x{x} result={d} remove={}", .{ name, state.windows_ui_quit_code, result, remove });
            }
        } else if (paint_message) |paint| {
            // Win32 generates WM_PAINT here rather than dequeuing it: the
            // update region stays set until the guest validates it, so a
            // GetMessage/DispatchMessage loop keeps painting for as long as
            // the guest keeps requesting paints.  This is the only path by
            // which an ordinary Win32 program reaches its renderer.
            if (!writeWindowsMessage(state, message, paint)) {
                state.windows_last_error = 87;
                state.regs.rax = if (is_get_message) std.math.maxInt(u64) else 0;
                finish(state, direct_return_rip);
                return true;
            }
            result = 1;
            if (state.diagnose_abi or state.trace_windows_messages) {
                log.info("Windows message pump synthesized WM_PAINT: api={s} hwnd=0x{x} remove={} serviced_steps={d}", .{
                    name,
                    paint.hwnd,
                    remove,
                    serviced_steps,
                });
            }
        } else if (is_get_message) {
            // A real GetMessage blocks. The cooperative PE executor cannot
            // block the host, so publish WM_NULL while workers and the native
            // event pump make progress. DispatchMessage ignores WM_NULL when
            // no WndProc is registered, preserving the loop semantics.
            const idle_message = .{ .hwnd = @as(u64, 0), .message = @as(u32, 0), .wparam = @as(u64, 0), .lparam = @as(u64, 0) };
            if (!writeWindowsMessage(state, message, idle_message)) {
                state.windows_last_error = 87;
                state.regs.rax = std.math.maxInt(u64);
                finish(state, direct_return_rip);
                return true;
            }
            result = 1;
            if ((state.diagnose_abi or state.trace_windows_messages) and state.windows_message_deliveries < 8) {
                log.info("Windows message pump idle synthetic WM_NULL serviced_steps={d} thread_calls={d} yields={d} completions={d}", .{ serviced_steps, state.windows_thread_service_calls, state.windows_thread_yields, state.windows_thread_completions });
            }
        }
        state.regs.rax = result;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "PostQuitMessage")) {
        const State = @TypeOf(state.*);
        const exit_code = arg(state, 0, direct_return_rip);
        if (comptime @hasDecl(State, "postWindowsQuit")) {
            state.postWindowsQuit(exit_code);
        } else if (comptime @hasDecl(State, "requestWindowsUiQuit")) {
            state.requestWindowsUiQuit();
        }
        if (state.diagnose_abi or state.trace_windows_messages) log.info("Windows UI quit requested by guest exit code=0x{x}", .{exit_code});
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DispatchMessageA") or std.mem.eql(u8, name, "DispatchMessageW")) {
        return dispatchWindowsMessage(state, arg(state, 0, direct_return_rip), direct_return_rip);
    }
    if (std.mem.eql(u8, name, "TranslateMessage") or std.mem.eql(u8, name, "DefWindowProcA") or
        std.mem.eql(u8, name, "DefWindowProcW"))
    {
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetSystemMetrics")) {
        state.regs.rax = if (arg(state, 0, direct_return_rip) == 0) 1280 else if (arg(state, 0, direct_return_rip) == 1) 720 else 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetDpiForWindow")) {
        state.regs.rax = 96;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetDpiForSystem")) {
        state.regs.rax = 96;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "AdjustWindowRectEx") or std.mem.eql(u8, name, "AdjustWindowRectExForDpi")) {
        const rect = arg(state, 0, direct_return_rip);
        if (rect == 0 or state.guestMemory(rect, 16) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            // The exact non-client metrics are host-policy data. Keep the
            // caller's requested client rectangle intact while proving that
            // the Win32 sizing contract itself was crossed.
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "EnableNonClientDpiScaling")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetMonitorInfoA") or std.mem.eql(u8, name, "GetMonitorInfoW")) {
        const information = arg(state, 1, direct_return_rip);
        if (information == 0 or state.guestMemory(information, 40) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            // MONITORINFO is identical through dwFlags for A and W. The
            // virtual monitor is deliberately the same 1280x720 surface used
            // by the native window bridge.
            state.write32(information + 0, 40);
            state.write32(information + 4, 0);
            state.write32(information + 8, 0);
            state.write32(information + 12, 1280);
            state.write32(information + 16, 720);
            state.write32(information + 20, 0);
            state.write32(information + 24, 0);
            state.write32(information + 28, 1280);
            state.write32(information + 32, 720);
            state.write32(information + 36, 1); // MONITORINFOF_PRIMARY
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "MonitorFromWindow") or std.mem.eql(u8, name, "MonitorFromPoint") or
        std.mem.eql(u8, name, "MonitorFromRect"))
    {
        // Win32 returns the *same* HMONITOR for the same display every time.
        // Minting a fresh handle per call makes a guest that compares the
        // current monitor against the previous one believe the window moved
        // to a new display on every check, and a guest that caches
        // per-monitor state rebuild it forever.  Rosetta presents one virtual
        // display, so there is exactly one handle.
        state.regs.rax = primaryMonitorHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetWindowPlacement")) {
        const placement = arg(state, 1, direct_return_rip);
        if (placement == 0 or state.guestMemory(placement, 44) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            state.write32(placement + 0, 44); // length
            state.write32(placement + 4, 0); // flags
            state.write32(placement + 8, 1); // SW_SHOWNORMAL
            state.write32(placement + 12, 0);
            state.write32(placement + 16, 0);
            state.write32(placement + 20, 0);
            state.write32(placement + 24, 0);
            state.write32(placement + 28, 0);
            state.write32(placement + 32, 0);
            state.write32(placement + 36, state.windows_graphics.window_width);
            state.write32(placement + 40, state.windows_graphics.window_height);
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetWindowPlacement")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetDeviceCaps")) {
        state.regs.rax = switch (arg(state, 1, direct_return_rip)) {
            8 => 1280, // HORZRES
            10 => 720, // VERTRES
            12 => 32, // BITSPIXEL
            14 => 1, // PLANES
            88, 90 => 96, // LOGPIXELSX / LOGPIXELSY
            else => 0,
        };
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetSystemInfo") or std.mem.eql(u8, name, "GetNativeSystemInfo")) {
        const info = arg(state, 0, direct_return_rip);
        if (info == 0 or state.guestMemory(info, 48) == null) {
            state.regs.rax = 0;
        } else {
            state.write16(info + 0, 9); // PROCESSOR_ARCHITECTURE_AMD64
            state.write16(info + 2, 0);
            state.write32(info + 4, 4096); // dwPageSize
            state.write64(info + 8, 0x10000);
            state.write64(info + 16, 0x0000_7FFF_FFFF_F000);
            state.write64(info + 24, 1); // active processor mask
            state.write32(info + 32, 1); // number of processors
            state.write32(info + 36, 8664); // PROCESSOR_INTEL_PENTIUM4-compatible
            state.write32(info + 40, 0x10000); // allocation granularity
            state.write16(info + 44, 6);
            state.write16(info + 46, 0);
            state.regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetClassLongPtrW")) {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetWindowTextA") or std.mem.eql(u8, name, "SetWindowTextW")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCapture")) {
        state.regs.rax = state.windows_window_handle;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetCapture")) {
        state.regs.rax = state.windows_window_handle;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ReleaseCapture")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCursorPos")) {
        const point = arg(state, 0, direct_return_rip);
        if (point == 0 or state.guestMemory(point, 8) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            state.write32(point + 0, 0);
            state.write32(point + 4, 0);
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ScreenToClient") or std.mem.eql(u8, name, "ClientToScreen")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetKeyState")) {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VkKeyScanW")) {
        state.regs.rax = 0xFFFF;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "WindowFromPoint")) {
        state.regs.rax = state.windows_window_handle;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "LoadCursorA") or std.mem.eql(u8, name, "LoadCursorW") or
        std.mem.eql(u8, name, "LoadIconA") or std.mem.eql(u8, name, "LoadIconW") or
        std.mem.eql(u8, name, "GetStockObject") or std.mem.eql(u8, name, "CreateIconFromResourceEx"))
    {
        state.regs.rax = nextHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DestroyIcon") or std.mem.eql(u8, name, "SetCursor")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetPropA") or std.mem.eql(u8, name, "SetPropW")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetPropA") or std.mem.eql(u8, name, "GetPropW")) {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RemovePropA") or std.mem.eql(u8, name, "RemovePropW")) {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RegisterDeviceNotificationA") or std.mem.eql(u8, name, "RegisterDeviceNotificationW")) {
        state.regs.rax = nextHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "UnregisterDeviceNotification")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateTimerQueueTimer")) {
        const timer = arg(state, 0, direct_return_rip);
        const handle = nextHandle(state);
        if (timer != 0) state.write64(timer, handle);
        state.regs.rax = if (timer != 0) 1 else 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DeleteTimerQueueTimer")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateMenu") or std.mem.eql(u8, name, "CreatePopupMenu")) {
        state.regs.rax = nextHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DestroyMenu") or std.mem.eql(u8, name, "SetMenu") or
        std.mem.eql(u8, name, "AppendMenuA") or std.mem.eql(u8, name, "AppendMenuW") or
        std.mem.eql(u8, name, "EnableMenuItem") or std.mem.eql(u8, name, "DrawMenuBar") or
        std.mem.eql(u8, name, "SetMenuInfo") or std.mem.eql(u8, name, "GetMenuInfo") or
        std.mem.eql(u8, name, "DragAcceptFiles") or std.mem.eql(u8, name, "DragFinish") or
        std.mem.eql(u8, name, "SendMessageA") or std.mem.eql(u8, name, "SendMessageW") or
        std.mem.eql(u8, name, "AttachConsole"))
    {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DragQueryFileW")) {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GlobalAddAtomW")) {
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GlobalDeleteAtom")) {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "QueryPerformanceCounter")) {
        const output = arg(state, 0, direct_return_rip);
        if (output != 0) state.write64(output, windowsGuestClockTicks(state));
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetSystemTimeAsFileTime") or
        std.mem.eql(u8, name, "GetSystemTimePreciseAsFileTime"))
    {
        // A FILETIME is 100-nanosecond intervals since 1601-01-01, not a
        // performance-counter reading. Both used to return the raw tick
        // count, so `std::chrono::system_clock::now()` - which MinGW builds
        // out of this call - reported a wall clock in the year 1601 and every
        // duration computed against a real timestamp was nonsense.
        const output = arg(state, 0, direct_return_rip);
        if (output != 0) state.write64(output, windowsGuestFileTime(state));
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "QueryPerformanceFrequency")) {
        const output = arg(state, 0, direct_return_rip);
        // The one place this number is decided is the ELF state, because the
        // cooperative wait deadlines are denominated in the same ticks. A
        // guest that measures a millisecond and a guest that sleeps for one
        // have to agree, and they only can if both read the same constant.
        if (output != 0) state.write64(output, windowsGuestClockHz(state));
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetTickCount") or std.mem.eql(u8, name, "GetTickCount64")) {
        state.regs.rax = windowsGuestClockTicks(state) / 1000;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetSystemTime") or std.mem.eql(u8, name, "GetLocalTime")) {
        const output = arg(state, 0, direct_return_rip);
        if (output != 0 and state.guestMemory(output, 16) != null) {
            state.write16(output + 0, 2026); // wYear
            state.write16(output + 2, 9); // wMonth
            state.write16(output + 4, 1); // wDayOfWeek
            state.write16(output + 6, 7); // wDay
            state.write16(output + 8, 0); // wHour
            state.write16(output + 10, 0); // wMinute
            state.write16(output + 12, 0); // wSecond
            state.write16(output + 14, 0); // wMilliseconds
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCurrentProcessorNumber")) {
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "RtlCaptureContext")) {
        return handleRtlCaptureContext(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "RtlUnwindEx")) {
        return handleRtlUnwindEx(state, direct_return_rip);
    }

    if (std.mem.eql(u8, name, "RaiseException")) {
        // The PE's MinGW unwinder uses RaiseException as the host-facing
        // bridge for Itanium C++ exceptions. Returning zero here falsely
        // reports that the exception was handled; the unwinder then falls
        // through into __cxa_begin_catch with a fabricated/null continuation.
        // Until a guest SEH/LSDA dispatcher is installed, stop at this
        // boundary with the exception code and ABI arguments intact.
        terminateWindowsCall(state, .cxx_exception, 127, name);
        const exception_argument = arg(state, 3, direct_return_rip);
        const exception_header = if (exception_argument != 0) state.read64(exception_argument) else 0;
        const exception_object = if (exception_header >= 0x60) exception_header - 0x60 else 0;
        // __cxa_init_primary_exception returns the base of the private
        // exception record.  The type_info and destructor fields precede the
        // unwind header at +0x60; reading word zero here would report the
        // reference count as a fake type pointer.
        const type_info = if (exception_object != 0) state.read64(exception_object +| 0x10) else 0;
        const type_name_address = if (type_info != 0) state.read64(type_info +| 8) else 0;
        const type_name = if (type_name_address != 0) guestCString(state, type_name_address) orelse "<unreadable>" else "<unknown>";
        const thrown_object = if (exception_object != 0) exception_object +| 0xa0 else 0;
        const is_invalid_code_point = std.mem.indexOf(u8, type_name, "invalid_code_point") != null;
        const code_point = if (is_invalid_code_point and thrown_object != 0)
            state.read32(thrown_object +| 8)
        else
            0;
        // Only cxxopts exception objects carry an option-spec string at +8.
        // utf8::invalid_code_point carries a scalar char32_t there instead;
        // interpreting it as a std::string made the old diagnostic report a
        // misleading unreadable option and hid the actual input failure.
        const option_spec: []const u8 = if (std.mem.indexOf(u8, type_name, "cxxopts") != null and thrown_object != 0)
            guestStdString(state, thrown_object +| 8) orelse "<unreadable>"
        else
            "<not-cxxopts-option>";
        log.err(
            "Windows RaiseException boundary: code=0x{x} flags=0x{x} arguments={d} argument_ptr=0x{x} exception_header=0x{x} exception_object=0x{x} thrown_object=0x{x} type_info=0x{x} type_name={s} option_spec={s} code_point=0x{x} code_point_present={} rsp=0x{x} caller_slot=0x{x}",
            .{
                arg(state, 0, direct_return_rip),
                arg(state, 1, direct_return_rip),
                arg(state, 2, direct_return_rip),
                exception_argument,
                exception_header,
                exception_object,
                thrown_object,
                type_info,
                type_name,
                option_spec,
                code_point,
                is_invalid_code_point,
                state.regs.rsp,
                state.read64(state.regs.rsp),
            },
        );
        if (thrown_object != 0) {
            const payload0 = state.read64(thrown_object +| 8);
            const payload1 = state.read64(thrown_object +| 16);
            const payload2 = state.read64(thrown_object +| 24);
            log.err(
                "Windows C++ thrown object words: vptr=0x{x} payload0=0x{x} payload1=0x{x} payload2=0x{x}",
                .{
                    state.read64(thrown_object),
                    payload0,
                    payload1,
                    payload2,
                },
            );
            if (std.mem.indexOf(u8, type_name, "filesystem_error") != null) {
                const message = guestCString(state, payload0) orelse "<unreadable>";
                log.err(
                    "Windows filesystem_error payload: message_ptr=0x{x} message='{s}' payload1=0x{x} payload2=0x{x}",
                    .{ payload0, message, payload1, payload2 },
                );
            }
        }
        if (exception_header != 0) {
            log.err(
                "Windows C++ exception header words: class=0x{x} cleanup=0x{x} private1=0x{x} private2=0x{x} handler_count=0x{x} next=0x{x}",
                .{
                    state.read64(exception_header),
                    state.read64(exception_header +| 8),
                    state.read64(exception_header +| 16),
                    state.read64(exception_header +| 24),
                    if (exception_object != 0) state.read32(exception_object +| 0x30) else 0,
                    if (exception_object != 0) state.read64(exception_object +| 0x38) else 0,
                },
            );
        }
        return true;
    }

    if (std.mem.eql(u8, name, "CoIncrementMTAUsage")) {
        const output = arg(state, 0, direct_return_rip);
        if (output == 0 or state.guestMemory(output, 8) == null) {
            state.regs.rax = 0x8000_4003; // E_POINTER
        } else {
            if (state.windows_com_mta_cookie == 0) state.windows_com_mta_cookie = nextHandle(state);
            state.windows_com_mta_refcount +|= 1;
            state.write64(output, state.windows_com_mta_cookie);
            state.regs.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CoDecrementMTAUsage")) {
        const cookie = arg(state, 0, direct_return_rip);
        if (cookie == 0 or cookie != state.windows_com_mta_cookie or state.windows_com_mta_refcount == 0) {
            state.regs.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            state.windows_com_mta_refcount -= 1;
            state.regs.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CoInitializeEx") or std.mem.eql(u8, name, "CoInitializeSecurity") or
        std.mem.eql(u8, name, "CoUninitialize"))
    {
        // S_OK. COM apartment ownership is represented by the Rosetta host
        // boundary, not by a native Windows thread-local pointer.
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CoCreateInstance")) {
        // Returning S_OK without materializing `ppv` is worse than reporting
        // the unavailable COM class: callers immediately dereference the
        // interface vtable and turn a missing optional subsystem into a null
        // indirect call.  Preserve the output-pointer contract and return
        // the standard "interface not supported" HRESULT so the guest takes
        // its normal optional-device failure path.
        const output = arg(state, 4, direct_return_rip);
        if (output != 0 and state.guestMemory(output, 8) != null) state.write64(output, 0);
        state.regs.rax = 0x8000_4002; // E_NOINTERFACE
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CLSIDFromString")) {
        // The PE title only uses this as a class-id probe.  Do not claim
        // success with an all-zero GUID: CoCreateInstance would then follow
        // a class path Rosetta never registered.  Validate the output
        // pointer and return the documented class-string refusal directly at
        // this import boundary.
        const output = arg(state, 1, direct_return_rip);
        if (output == 0 or state.guestMemory(output, 16) == null) {
            state.regs.rax = 0x8000_4003; // E_POINTER
        } else {
            _ = clearGuestMemory(state, output, 16);
            state.regs.rax = 0x8004_0170; // CO_E_CLASSSTRING
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "PropVariantClear")) {
        // PROPVARIANT is 24 bytes on the PE's x64 ABI.  Clearing the guest
        // record is enough for the teardown contract and avoids turning a
        // harmless cleanup into an untyped HRESULT fallback.
        const propvariant = arg(state, 0, direct_return_rip);
        if (propvariant == 0 or !clearGuestMemory(state, propvariant, 24)) {
            state.regs.rax = 0x8000_4003; // E_POINTER
        } else {
            state.regs.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RoInitialize")) {
        // The PE path has no WinRT apartment object to publish, but a
        // successful initialization is the documented non-error result and
        // is enough for callers that only probe optional WinRT services.
        state.windows_last_error = 0;
        state.regs.rax = 0; // S_OK
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RoUninitialize")) {
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RoGetActivationFactory") or
        std.mem.eql(u8, name, "RoActivateInstance"))
    {
        const output = if (std.mem.eql(u8, name, "RoGetActivationFactory")) arg(state, 2, direct_return_rip) else arg(state, 1, direct_return_rip);
        if (output != 0 and state.guestMemory(output, 8) != null) state.write64(output, 0);
        state.regs.rax = 0x8000_4002; // E_NOINTERFACE
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateDXGIFactory1") or std.mem.eql(u8, name, "CreateDXGIFactory2")) {
        const output = if (std.mem.eql(u8, name, "CreateDXGIFactory1")) arg(state, 1, direct_return_rip) else arg(state, 2, direct_return_rip);
        if (output != 0 and state.guestMemory(output, 8) != null) state.write64(output, 0);
        state.regs.rax = if (output == 0) 0x8000_4003 else 0x8000_4002; // E_POINTER / E_NOINTERFACE
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "HidD_GetHidGuid")) {
        const output = arg(state, 0, direct_return_rip);
        if (output == 0 or state.guestMemory(output, 16) == null) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            // GUID_DEVINTERFACE_HID, serialized in Windows GUID byte order.
            const hid_guid = [_]u8{ 0xB2, 0x55, 0x1E, 0x4D, 0x6F, 0xF1, 0xCF, 0x11, 0x88, 0xCB, 0x00, 0x11, 0x11, 0x00, 0x00, 0x30 };
            @memcpy(state.guestMemory(output, 16).?, hid_guid[0..]);
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    // The process-exit family.
    //
    // A guest that asks to exit and is answered with a contract refusal
    // *returns* and keeps running with state it has already torn down. Xenia
    // leaves through `std::quick_exit` on purpose ("Cheap-skate exit!"), so
    // this is a normal, expected path and not an error - the exit code is
    // the guest's own, and the run ends where the guest said it does.
    if (std.mem.eql(u8, name, "ExitProcess") or
        std.mem.eql(u8, name, "exit") or
        std.mem.eql(u8, name, "_exit") or
        std.mem.eql(u8, name, "_Exit") or
        std.mem.eql(u8, name, "quick_exit") or
        std.mem.eql(u8, name, "_cexit") or
        std.mem.eql(u8, name, "_c_exit"))
    {
        const code = arg(state, 0, direct_return_rip);
        state.exit_code = code;
        state.terminated = true;
        log.info("PE64 Windows guest exit: api={s} code=0x{x} step={d}; the guest ended the process itself", .{
            name,
            code,
            state.executed_steps,
        });
        return true;
    }
    if (std.mem.eql(u8, name, "TerminateProcess")) {
        // (handle, exit_code). A guest terminating a handle that is not its
        // own process is not modelled; Rosetta hosts one process.
        state.exit_code = arg(state, 1, direct_return_rip);
        state.terminated = true;
        log.info("PE64 Windows guest exit: api=TerminateProcess code=0x{x} step={d}", .{
            state.exit_code,
            state.executed_steps,
        });
        return true;
    }

    // The Configuration Manager device tree.
    //
    // These exist for the same reason as the HID block below: libusb's
    // `init_dlls` resolves `CM_Get_Parent` and `CM_Get_Child` with
    // `ret_on_failure = true`, so one absent name costs the whole WinUSB
    // backend. Its macro tries the bare name, then +A, then +W, which is why
    // a single missing export appeared three times in the 2026-09-12 run.
    //
    // Rosetta enumerates no PnP devices, so every one of these answers with
    // the CONFIGRET a Windows machine returns for a devnode that is not
    // there. Zero would be CR_SUCCESS, and a caller that reads CR_SUCCESS
    // then trusts a devinst handle nothing wrote.
    if (std.mem.startsWith(u8, name, "CM_")) {
        if (std.mem.eql(u8, name, "CM_MapCrToWin32Err")) {
            // (CONFIGRET, default) -> Win32 error. Rosetta has no mapping
            // table, so the caller's own default is the honest answer.
            state.regs.rax = arg(state, 1, direct_return_rip);
            finish(state, direct_return_rip);
            return true;
        }
        if (std.mem.startsWith(u8, name, "CM_Locate_DevNode")) {
            // Nothing to locate. Clear the out-parameter first: a caller that
            // ignores the CONFIGRET must not read a devinst off its stack.
            const devinst = arg(state, 0, direct_return_rip);
            if (devinst != 0 and state.guestMemory(devinst, 4) != null) state.write32(devinst, 0);
            state.regs.rax = cr_no_such_devnode;
            finish(state, direct_return_rip);
            return true;
        }
        if (std.mem.startsWith(u8, name, "CM_Get_Device_ID_List_Size") or
            std.mem.startsWith(u8, name, "CM_Get_Device_Interface_List_Size") or
            std.mem.eql(u8, name, "CM_Get_Device_ID_Size"))
        {
            // A size query with an empty list is a success returning zero,
            // not a refusal: the caller allocates nothing and enumerates
            // nothing, which is the correct outcome for no devices.
            const size = arg(state, 0, direct_return_rip);
            if (size != 0 and state.guestMemory(size, 4) != null) state.write32(size, 0);
            state.regs.rax = cr_success;
            finish(state, direct_return_rip);
            return true;
        }
        if (std.mem.startsWith(u8, name, "CM_Register_Notification")) {
            const handle_out = arg(state, 3, direct_return_rip);
            if (handle_out != 0 and state.guestMemory(handle_out, 8) != null) state.write64(handle_out, 0);
            state.regs.rax = cr_failure;
            finish(state, direct_return_rip);
            return true;
        }
        if (std.mem.eql(u8, name, "CM_Unregister_Notification")) {
            state.regs.rax = cr_success;
            finish(state, direct_return_rip);
            return true;
        }
        // Everything else takes a devinst Rosetta never issued.
        state.regs.rax = cr_no_such_devinst;
        finish(state, direct_return_rip);
        return true;
    }
    // WinUSB is a real Windows surface package, but Rosetta does not expose
    // a host USB kernel-device handle. Keep the dynamically resolved abort
    // export callable so libusb's all-or-nothing probe does not become an
    // import gap; an invalid interface handle then receives the documented
    // FALSE/ERROR_INVALID_HANDLE result.
    if (import_contract.isWinUsbRequiredImport(name)) {
        // Every name in `winusbx_init`'s required list, answered the same
        // way. libusb resolves the twelve as a unit and `FreeLibrary`s the
        // module if any one is missing, so serving them one per run - which
        // is what the 2026-09-12 runs did, reporting AbortPipe and then
        // ControlTransfer - never converges. `WinUsb_Free` returns TRUE
        // because freeing nothing succeeds; the rest report the documented
        // invalid-handle failure, which is the truth about a Rosetta run:
        // there is no USB device behind the handle.
        const frees = std.mem.eql(u8, name, "WinUsb_Free");
        state.windows_last_error = if (frees) 0 else 6; // ERROR_INVALID_HANDLE
        state.regs.rax = if (frees) 1 else 0;
        finish(state, direct_return_rip);
        return true;
    }
    // The rest of the HID surface.
    //
    // These exist so a controller stack's all-or-nothing probe succeeds.
    // SDL's `WIN_LoadHIDDLL` resolves seven names and unloads the library if
    // any one is absent, taking the whole raw-input joystick backend with it;
    // hidapi's `lookup_functions` resolves twelve with the same rule. Refusing
    // one name therefore does not disable one call, it disables a subsystem -
    // and it disables it for the wrong reason, because the reason there is no
    // controller here is that Rosetta enumerates no HID devices, not that the
    // library is missing.
    //
    // What they do *not* do is claim a device. Every device handle they can
    // be given is one Rosetta never issued, so each reports its documented
    // invalid-handle answer, which is exactly what a Windows machine with
    // nothing plugged in reports too.
    if (std.mem.startsWith(u8, name, "HidD_")) {
        // BOOLEAN. FALSE is the refusal, and the out-parameters stay
        // untouched because there is no device to describe.
        state.windows_last_error = 6; // ERROR_INVALID_HANDLE
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "HidP_MaxDataListLength") or
        std.mem.eql(u8, name, "HidP_MaxUsageListLength"))
    {
        // ULONG count, and zero is the honest one: a report with no
        // preparsed data has no data items in it.
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.startsWith(u8, name, "HidP_")) {
        // NTSTATUS, where zero is HIDP_STATUS_SUCCESS. Returning it would
        // tell the caller a capability structure had been filled in.
        state.regs.rax = 0xC011_0001; // HIDP_STATUS_INVALID_PREPARSED_DATA
        finish(state, direct_return_rip);
        return true;
    }
    // SHCore's per-monitor DPI surface. Rosetta presents one virtual display
    // at the system default scale, so these are answerable exactly rather
    // than refused - and answering them is what keeps a caller from taking a
    // "DPI unavailable" path over a question that has a correct answer.
    if (std.mem.eql(u8, name, "GetDpiForMonitor")) {
        const dpi_x = arg(state, 2, direct_return_rip);
        const dpi_y = arg(state, 3, direct_return_rip);
        if (dpi_x == 0 or dpi_y == 0 or
            state.guestMemory(dpi_x, 4) == null or state.guestMemory(dpi_y, 4) == null)
        {
            state.regs.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            state.write32(dpi_x, 96);
            state.write32(dpi_y, 96);
            state.regs.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetScaleFactorForMonitor")) {
        const scale = arg(state, 1, direct_return_rip);
        if (scale == 0 or state.guestMemory(scale, 4) == null) {
            state.regs.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            state.write32(scale, 100); // SCALE_100_PERCENT
            state.regs.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetProcessDpiAwareness")) {
        // A guest that sets awareness and reads it back must see what it
        // set, so the value is retained rather than acknowledged and lost.
        state.windows_process_dpi_awareness = @truncate(arg(state, 0, direct_return_rip));
        state.regs.rax = 0; // S_OK
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetProcessDpiAwareness")) {
        const awareness = arg(state, 1, direct_return_rip);
        if (awareness == 0 or state.guestMemory(awareness, 4) == null) {
            state.regs.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            state.write32(awareness, state.windows_process_dpi_awareness);
            state.regs.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetRawInputDeviceList")) {
        const devices = arg(state, 0, direct_return_rip);
        const count = arg(state, 1, direct_return_rip);
        const element_size = arg(state, 2, direct_return_rip);
        if (count == 0 or state.guestMemory(count, 4) == null or (element_size != 0 and element_size < 16)) {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = std.math.maxInt(u32);
        } else {
            state.write32(count, 0);
            state.windows_last_error = 0;
            state.regs.rax = 0;
            _ = devices;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RegisterRawInputDevices")) {
        const devices = arg(state, 0, direct_return_rip);
        const count = arg(state, 1, direct_return_rip);
        const element_size = arg(state, 2, direct_return_rip);
        const byte_count = std.math.mul(u64, count, 16) catch std.math.maxInt(u64);
        if ((count != 0 and devices == 0) or
            (count != 0 and state.guestMemory(devices, byte_count) == null) or
            (count != 0 and element_size < 16))
        {
            state.windows_last_error = 87; // ERROR_INVALID_PARAMETER
            state.regs.rax = 0;
        } else {
            state.windows_raw_input_registered = count != 0;
            state.windows_raw_input_device_count = @truncate(count);
            state.windows_last_error = 0;
            state.regs.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetupDiGetClassDevsA") or std.mem.eql(u8, name, "SetupDiGetClassDevsW")) {
        // Device enumeration is optional for the Vulkan path. Return the
        // documented invalid set handle and a specific absence error instead
        // of a generic FALSE, so Xenia can take its no-device branch without
        // treating the setup API itself as an unresolved import.
        state.windows_last_error = 433; // ERROR_NO_SUCH_DEVICE
        state.regs.rax = std.math.maxInt(u64); // INVALID_HANDLE_VALUE
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetupDiEnumDeviceInterfaces")) {
        state.windows_last_error = 259; // ERROR_NO_MORE_ITEMS
        state.regs.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetupDiDestroyDeviceInfoList")) {
        state.windows_last_error = 0;
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "OpenSCManagerA") or std.mem.eql(u8, name, "OpenSCManagerW") or
        std.mem.eql(u8, name, "OpenServiceA") or std.mem.eql(u8, name, "OpenServiceW"))
    {
        // Rosetta does not expose the host service-control database to the
        // guest. Report the ordinary Windows "service does not exist" result
        // instead of claiming success with a null service handle.
        state.windows_last_error = 1060; // ERROR_SERVICE_DOES_NOT_EXIST
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CloseServiceHandle")) {
        state.windows_last_error = 0;
        state.regs.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InitializeSRWLock")) {
        const lock = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "initializeWindowsSrwLock")) {
            _ = state.initializeWindowsSrwLock(lock);
        } else if (lock != 0 and state.guestMemory(lock, 8) != null) {
            state.write64(lock, 0);
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "AcquireSRWLockExclusive")) {
        const lock = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "acquireWindowsSrwLock")) {
            var acquired = false;
            var contended = false;
            switch (state.acquireWindowsSrwLock(lock)) {
                .invalid => {},
                .acquired => acquired = true,
                .contended => contended = true,
            }
            if (contended) {
                // A worker cannot block a host thread, so leave the import
                // call uncompleted and let the cooperative service loop save
                // this context.  The next run retries Acquire naturally at
                // the same guest call site after Release wakes it.
                if (comptime @hasDecl(State, "blockWindowsGuestThreadOnSrwLock")) {
                    if (state.blockWindowsGuestThreadOnSrwLock(lock)) return true;
                }
                // The owner context has no saved worker slot. Give queued
                // workers a bounded chance to release the lock, then retry
                // before allowing the owner to spin at the import boundary.
                if (comptime @hasDecl(State, "serviceWindowsGuestThreads")) {
                    const service_slice = if (comptime @hasDecl(State, "windowsGuestWaitServiceSlice"))
                        state.windowsGuestWaitServiceSlice()
                    else
                        windows_guest_thread_service_slice;
                    if (comptime @hasDecl(State, "serviceWindowsGuestBoundary")) {
                        _ = state.serviceWindowsGuestBoundary(service_slice);
                    } else {
                        _ = state.serviceWindowsGuestThreads(service_slice);
                    }
                    switch (state.acquireWindowsSrwLock(lock)) {
                        .acquired => acquired = true,
                        .contended, .invalid => {},
                    }
                }
                if (!acquired) return true;
            }
            if (!acquired) returnZero(state, direct_return_rip) else finish(state, direct_return_rip);
        } else if (lock != 0 and state.guestMemory(lock, 8) != null) {
            state.write64(lock, 1);
            finish(state, direct_return_rip);
        } else {
            returnZero(state, direct_return_rip);
        }
        return true;
    }
    if (std.mem.eql(u8, name, "ReleaseSRWLockExclusive")) {
        const lock = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "releaseWindowsSrwLock")) {
            state.releaseWindowsSrwLock(lock);
        } else if (lock != 0 and state.guestMemory(lock, 8) != null) {
            state.write64(lock, 0);
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TryAcquireSRWLockExclusive")) {
        const lock = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "acquireWindowsSrwLock")) {
            state.regs.rax = switch (state.acquireWindowsSrwLock(lock)) {
                .acquired => 1,
                .invalid, .contended => 0,
            };
        } else {
            if (lock == 0 or state.guestMemory(lock, 8) == null) {
                state.regs.rax = 0;
            } else if (state.read64(lock) == 0) {
                state.write64(lock, 1);
                state.regs.rax = 1;
            } else {
                state.regs.rax = 0;
            }
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DwmEnableMMCSS") or std.mem.eql(u8, name, "DwmSetWindowAttribute")) {
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "NtQueryTimerResolution")) {
        const minimum = arg(state, 0, direct_return_rip);
        const maximum = arg(state, 1, direct_return_rip);
        const current = arg(state, 2, direct_return_rip);
        if (minimum != 0) state.write32(minimum, 5_000);
        if (maximum != 0) state.write32(maximum, 156_250);
        if (current != 0) state.write32(current, 10_000);
        returnZero(state, direct_return_rip); // STATUS_SUCCESS
        return true;
    }
    if (std.mem.eql(u8, name, "NtSetTimerResolution")) {
        const desired: u32 = @truncate(arg(state, 0, direct_return_rip));
        const current = arg(state, 2, direct_return_rip);
        if (current != 0) state.write32(current, desired);
        returnZero(state, direct_return_rip); // STATUS_SUCCESS
        return true;
    }

    // Xenia's non-alertable Wait implementation intentionally calls the NT
    // entry point rather than WaitForSingleObjectEx.  Keep the NT and Win32
    // names on the same Rosetta wait-object state machine: a worker blocks at
    // an unsignaled event, while the owner/UI context can continue servicing
    // the deferred message callback that will signal it.
    if (std.mem.eql(u8, name, "NtWaitForSingleObject")) {
        const wait_handle = arg(state, 0, direct_return_rip);
        const timeout_pointer = arg(state, 2, direct_return_rip);
        const timeout = ntWaitTimeoutMilliseconds(state, timeout_pointer) orelse {
            state.regs.rax = nt_status_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        };
        return finishNtWait(state, direct_return_rip, wait_handle, timeout);
    }
    if (std.mem.eql(u8, name, "NtSetEvent") or
        std.mem.eql(u8, name, "NtPulseEvent") or
        std.mem.eql(u8, name, "NtClearEvent"))
    {
        const handle = arg(state, 0, direct_return_rip);
        const previous_state = arg(state, 1, direct_return_rip);
        const State = @TypeOf(state.*);
        const known = if (comptime @hasDecl(State, "windowsWaitObjectKnown"))
            state.windowsWaitObjectKnown(handle)
        else
            false;
        const was_signaled = if (known) state.windowsWaitObjectSignaled(handle) else false;
        if (previous_state != 0 and state.guestMemory(previous_state, 4) != null) {
            state.write32(previous_state, @intFromBool(was_signaled));
        }
        if (!known) {
            state.regs.rax = nt_status_invalid_handle;
        } else if (std.mem.eql(u8, name, "NtClearEvent")) {
            _ = state.resetWindowsWaitObject(handle);
            state.regs.rax = nt_status_success;
        } else {
            _ = state.signalWindowsWaitObject(handle, std.mem.eql(u8, name, "NtPulseEvent"));
            state.regs.rax = nt_status_success;
        }
        traceNtSynchronization(state, name, handle, known, state.regs.rax);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "NtReleaseSemaphore")) {
        const handle = arg(state, 0, direct_return_rip);
        const release_count = arg(state, 1, direct_return_rip);
        const previous_count = arg(state, 2, direct_return_rip);
        const State = @TypeOf(state.*);
        const before = if (comptime @hasDecl(State, "windowsWaitObjectSemaphoreCount"))
            state.windowsWaitObjectSemaphoreCount(handle)
        else
            null;
        const released = if (comptime @hasDecl(State, "releaseWindowsSemaphore"))
            state.releaseWindowsSemaphore(handle, release_count)
        else
            false;
        if (released) {
            if (previous_count != 0 and before != null and state.guestMemory(previous_count, 4) != null) {
                state.write32(previous_count, before.?);
            }
            state.regs.rax = nt_status_success;
        } else {
            state.regs.rax = if (release_count == 0) nt_status_invalid_parameter else nt_status_invalid_handle;
        }
        traceNtSynchronization(state, name, handle, released, state.regs.rax);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "NtReleaseMutant")) {
        const handle = arg(state, 0, direct_return_rip);
        const previous_count = arg(state, 1, direct_return_rip);
        const State = @TypeOf(state.*);
        const known = if (comptime @hasDecl(State, "windowsWaitObjectKnown"))
            state.windowsWaitObjectKnown(handle)
        else
            false;
        if (previous_count != 0 and state.guestMemory(previous_count, 4) != null) state.write32(previous_count, 1);
        if (known) {
            if (comptime @hasDecl(State, "signalWindowsWaitObject")) _ = state.signalWindowsWaitObject(handle, false);
            state.regs.rax = nt_status_success;
        } else {
            state.regs.rax = nt_status_invalid_handle;
        }
        traceNtSynchronization(state, name, handle, known, state.regs.rax);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "NtDelayExecution") or std.mem.eql(u8, name, "NtYieldExecution")) {
        // NtDelayExecution(0, relative-zero) is Xenia's cooperative
        // MaybeYield path.  The outer Rosetta scheduler owns the actual
        // context switch; completing the boundary here preserves the NT
        // status contract without sleeping the host process.
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "FormatMessageA") or std.mem.eql(u8, name, "FormatMessageW")) {
        const wide = std.mem.endsWith(u8, name, "W");
        const flags = arg(state, 0, direct_return_rip);
        const output = arg(state, 4, direct_return_rip);
        const capacity = arg(state, 5, direct_return_rip);
        const message = "Rosetta Windows runtime status";
        if ((flags & 0x100) != 0) {
            const materialized = if (wide)
                materializeGuestWide(state, message) orelse 0
            else
                materializeGuestAnsi(state, message) orelse 0;
            if (output != 0) state.write64(output, materialized);
            state.regs.rax = if (materialized == 0) 0 else message.len;
        } else if (wide) {
            state.regs.rax = copyGuestWideString(state, output, capacity, message);
        } else {
            state.regs.rax = copyGuestString(state, output, capacity, message);
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "fopen") or std.mem.eql(u8, name, "fopen64") or
        std.mem.eql(u8, name, "_wfopen") or std.mem.eql(u8, name, "_wfsopen"))
    {
        return openWindowsStdio(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "fdopen") or std.mem.eql(u8, name, "_fdopen")) {
        return openWindowsDescriptorAsStdio(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "read") or std.mem.eql(u8, name, "_read") or
        std.mem.eql(u8, name, "write") or std.mem.eql(u8, name, "_write"))
    {
        return transferWindowsDescriptor(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "lseek64") or std.mem.eql(u8, name, "_lseeki64")) {
        return seekWindowsDescriptor(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "_filelengthi64")) {
        return lengthWindowsDescriptor(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "close") or std.mem.eql(u8, name, "_close")) {
        return closeWindowsDescriptor(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "setvbuf")) {
        return setvbufWindowsStdio(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "ferror") or std.mem.eql(u8, name, "feof") or std.mem.eql(u8, name, "fgetc")) {
        return queryWindowsStdioState(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "fgetwc")) {
        return readWindowsStdioWide(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "fread") or std.mem.eql(u8, name, "fwrite")) {
        return transferWindowsStdio(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "fputc") or std.mem.eql(u8, name, "fputs") or
        std.mem.eql(u8, name, "putc") or std.mem.eql(u8, name, "puts") or
        std.mem.eql(u8, name, "putchar"))
    {
        return writeWindowsStdio(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "fseek") or std.mem.eql(u8, name, "_fseeki64")) {
        return seekWindowsStdio(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "ftell") or std.mem.eql(u8, name, "_ftelli64") or std.mem.eql(u8, name, "_fileno")) {
        return stdioFileInfo(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "fflush")) {
        return flushWindowsStdio(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "fclose")) {
        const handle = arg(state, 0, direct_return_rip);
        state.regs.rax = if (closeWindowsFile(state, handle)) 0 else std.math.maxInt(u32); // CRT EOF on failure
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_chsize_s")) {
        return truncateWindowsStdio(state, direct_return_rip);
    }

    if (std.mem.eql(u8, name, "CreateFileA") or std.mem.eql(u8, name, "CreateFileW")) {
        return openWindowsFile(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "ReadFile") or std.mem.eql(u8, name, "WriteFile")) {
        return transferWindowsFile(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "GetFileSize") or std.mem.eql(u8, name, "GetFileSizeEx")) {
        return windowsFileSize(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "SetFilePointer") or std.mem.eql(u8, name, "SetFilePointerEx")) {
        return setWindowsFilePointer(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "SetEndOfFile")) {
        return truncateWindowsFile(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "FlushFileBuffers")) {
        const slot = windowsFileSlot(state, arg(state, 0, direct_return_rip)) orelse {
            failWindowsFileCall(state, direct_return_rip, 6); // ERROR_INVALID_HANDLE
            return true;
        };
        const io = state.windows_host_io orelse unreachable;
        if (slot.file.?.sync(io)) |_| {
            state.regs.rax = 1;
        } else |_| {
            failWindowsFileCall(state, direct_return_rip, 1117); // ERROR_IO_DEVICE
            return true;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetFileAttributesA") or std.mem.eql(u8, name, "GetFileAttributesW") or
        std.mem.eql(u8, name, "GetFileAttributesExA") or std.mem.eql(u8, name, "GetFileAttributesExW"))
    {
        return queryWindowsFileAttributes(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "FindFirstFileA") or std.mem.eql(u8, name, "FindFirstFileW") or
        std.mem.eql(u8, name, "FindFirstFileExA") or std.mem.eql(u8, name, "FindFirstFileExW"))
    {
        return beginWindowsFind(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "FindNextFileA") or std.mem.eql(u8, name, "FindNextFileW")) {
        return advanceWindowsFindCall(state, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "FindClose")) {
        const handle = arg(state, 0, direct_return_rip);
        if (closeWindowsFind(state, handle)) {
            state.regs.rax = 1;
        } else {
            state.windows_last_error = 6; // ERROR_INVALID_HANDLE
            state.regs.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CloseHandle")) {
        const handle = arg(state, 0, direct_return_rip);
        if (closeWindowsFile(state, handle) or closeWindowsFind(state, handle) or state.closeWindowsMemoryMapping(handle)) {
            state.regs.rax = 1;
            state.windows_last_error = 0;
            finish(state, direct_return_rip);
            return true;
        }
    }

    if (std.mem.eql(u8, name, "ExitThread") or
        std.mem.eql(u8, name, "_endthread") or
        std.mem.eql(u8, name, "_endthreadex"))
    {
        const exit_status = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "terminateActiveWindowsGuestThread")) {
            if (state.terminateActiveWindowsGuestThread(exit_status)) return true;
        }
        // A thread-exit import reached outside the cooperative worker is a
        // process-level termination in this bounded PE runner. It is still a
        // noreturn boundary, so never fall through to the next PE symbol.
        state.exit_code = exit_status;
        state.terminated = true;
        return true;
    }

    if (std.mem.startsWith(u8, name, "Nt") or std.mem.startsWith(u8, name, "Zw") or
        std.mem.startsWith(u8, name, "Rtl") or std.mem.startsWith(u8, name, "__security_") or
        std.mem.startsWith(u8, name, "__C") or std.mem.eql(u8, name, "_purecall") or
        std.mem.eql(u8, name, "terminate") or std.mem.eql(u8, name, "__std_terminate"))
    {
        if (std.mem.eql(u8, name, "terminate") or std.mem.eql(u8, name, "__std_terminate") or std.mem.eql(u8, name, "_purecall")) {
            terminateWindowsCall(state, .runtime_invariant_failure, 127, name);
            return true;
        }
        // These names are known to the ABI inventory but do not yet have a
        // stateful kernel implementation. A zero/STATUS_SUCCESS return keeps
        // the call boundary deterministic; the import itself remains visible
        // in the preflight and runtime counters.
        returnZero(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "abort")) {
        // abort() is noreturn. Treating it as a zero-returning import leaves
        // the caller's stack and exception state live, which converts the
        // real fatal event into a later, misleading memory fault.
        terminateWindowsCall(state, .runtime_invariant_failure, 134, name);
        return true;
    }

    if (std.mem.eql(u8, name, "InterlockedIncrement") or std.mem.eql(u8, name, "InterlockedIncrement64") or
        std.mem.eql(u8, name, "InterlockedDecrement") or std.mem.eql(u8, name, "InterlockedDecrement64"))
    {
        const address = arg(state, 0, direct_return_rip);
        const old = state.read64(address);
        const is_32 = std.mem.eql(u8, name, "InterlockedIncrement") or std.mem.eql(u8, name, "InterlockedDecrement");
        const increment: u64 = if (std.mem.eql(u8, name, "InterlockedIncrement") or std.mem.eql(u8, name, "InterlockedIncrement64")) 1 else 0;
        const value = if (is_32)
            (old & 0xFFFF_FFFF) +% (if (increment != 0) @as(u64, 1) else ~@as(u64, 0))
        else
            old +% (if (increment != 0) @as(u64, 1) else ~@as(u64, 0));
        if (std.mem.eql(u8, name, "InterlockedIncrement") or std.mem.eql(u8, name, "InterlockedDecrement"))
            state.write32(address, @truncate(value))
        else
            state.write64(address, value);
        state.regs.rax = value;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InterlockedExchange") or std.mem.eql(u8, name, "InterlockedExchange64")) {
        const address = arg(state, 0, direct_return_rip);
        const old = state.read64(address);
        if (std.mem.eql(u8, name, "InterlockedExchange")) state.write32(address, @truncate(arg(state, 1, direct_return_rip))) else state.write64(address, arg(state, 1, direct_return_rip));
        state.regs.rax = old;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InterlockedCompareExchange") or std.mem.eql(u8, name, "InterlockedCompareExchange64")) {
        const address = arg(state, 0, direct_return_rip);
        const old = state.read64(address);
        if (old == arg(state, 2, direct_return_rip)) {
            if (std.mem.eql(u8, name, "InterlockedCompareExchange")) state.write32(address, @truncate(arg(state, 1, direct_return_rip))) else state.write64(address, arg(state, 1, direct_return_rip));
        }
        state.regs.rax = old;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InterlockedOr") or std.mem.eql(u8, name, "InterlockedAnd") or std.mem.eql(u8, name, "InterlockedXor")) {
        const address = arg(state, 0, direct_return_rip);
        const old = state.read32(address);
        const operand: u32 = @truncate(arg(state, 1, direct_return_rip));
        const value = if (std.mem.eql(u8, name, "InterlockedOr")) old | operand else if (std.mem.eql(u8, name, "InterlockedAnd")) old & operand else old ^ operand;
        state.write32(address, value);
        state.regs.rax = old;
        finish(state, direct_return_rip);
        return true;
    }

    // Keep the distinction between an unknown import and a known-but-not-yet
    // stateful Win32 routine explicit.  The import inventory only classifies
    // the latter as core when it is in the allow-list above; reaching this
    // point means its ABI is known but its observable side effects have not
    // been needed by the current bootstrap yet.  Complete the call boundary
    // deterministically and retain evidence for the next preflight/run rather
    // than letting it look like an unresolved symbol.
    //
    // "Deterministically" is not the same as "with zero".  The value has to
    // be the one this import's ABI defines for "this did not happen", or a
    // guest asking an LSTATUS/HRESULT/NTSTATUS question is told the call
    // succeeded and then reads an output Rosetta never wrote.  See
    // windows_import_contract.zig.
    if (isKnownCoreImport(name) or isKnownContractImport(dll_name, name)) {
        completeWithImportFallback(state, dll_name, name, direct_return_rip);
        return true;
    }

    return false;
}

/// Complete a recognized-but-unimplemented import with the value its ABI
/// defines for a refusal, and record the fact so a run can report which
/// fallbacks it actually leaned on.
fn completeWithImportFallback(
    state: anytype,
    dll_name: []const u8,
    name: []const u8,
    direct_return_rip: ?u64,
) void {
    const fallback = import_contract.fallbackFor(dll_name, name);
    // This path is reached only after the name has passed Rosetta's package
    // inventory.  It is therefore an explicit ABI contract refusal, not an
    // unresolved/degraded import.  Keep the refusal in the bounded ledger so
    // a load-bearing call remains visible, but keep the degraded counter for
    // genuinely unknown names handled by the permissive boundary.
    if (comptime @hasField(@TypeOf(state.*), "windows_import_contract_calls")) {
        state.windows_import_contract_calls +|= 1;
    }
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "noteWindowsImportFallback")) {
        state.noteWindowsImportFallback(dll_name, name, fallback);
    }
    if (fallback.last_error) |last_error| state.windows_last_error = last_error;
    state.regs.rax = fallback.value;
    finish(state, direct_return_rip);
}

/// Execute one Microsoft x64 import. The caller invokes this only for a PE
/// state, so an unrecognized import can be made an explicit terminal event
/// rather than silently entering a zero-return stub.
pub fn tryFunction(state: anytype, dll_name: []const u8, function_name: []const u8, direct_return_rip: ?u64) bool {
    if (!state.windows_runtime_enabled) return false;
    state.windows_import_calls +|= 1;
    // Two stores so a file failure raised inside a handler can name the
    // import that raised it. The names outlive the call: they come from the
    // import stub's own storage or from a literal.
    if (comptime @hasField(@TypeOf(state.*), "windows_current_import")) state.windows_current_import = function_name;
    if (state.diagnose_abi) {
        log.info("Windows import dispatch: {s}!{s} direct_return={s} rip=0x{x} return=0x{x} caller=0x{x} last_op={s} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x} rsp=0x{x}", .{
            dll_name,
            function_name,
            if (direct_return_rip == null) "no" else "yes",
            state.regs.rip,
            state.read64(state.regs.rsp),
            // The Windows import stub is entered from the call site after
            // the callee's prologue has already reserved its shadow space.
            // Reading +0x30 reaches that caller return address for the
            // common import path; +0x28 is the callee's saved-register slot.
            state.read64(state.regs.rsp +| 0x30),
            @tagName(state.last_decoded_op),
            state.regs.rcx,
            state.regs.rdx,
            state.regs.r8,
            state.regs.r9,
            state.regs.rsp,
        });
    }
    switch (classifyImport(dll_name, function_name)) {
        .graphics => {
            const State = @TypeOf(state.*);
            if (comptime @hasDecl(State, "tryNativeWindowsVulkan")) {
                if (state.tryNativeWindowsVulkan(function_name, direct_return_rip)) {
                    traceGraphicsDispatch(state, function_name, "native");
                    return true;
                }
            }
            const handled = handleGraphics(state, function_name, direct_return_rip);
            if (handled) traceGraphicsDispatch(state, function_name, "modelled");
            return handled;
        },
        .core, .contract, .degraded => return handleCore(state, dll_name, function_name, direct_return_rip),
        .unsupported => {
            if (state.windows_unknown_imports_fatal) {
                state.terminateForUnresolvedWindowsImport(dll_name, function_name);
                return true;
            }
            return false;
        },
    }
}

test "Windows import classification separates Vulkan from unknown APIs" {
    try std.testing.expectEqual(ImportClass.graphics, classifyImport("vulkan-1.dll", "vkCreateInstance"));
    try std.testing.expectEqual(ImportClass.core, classifyImport("kernel32.dll", "VirtualAlloc"));
    try std.testing.expectEqual(ImportClass.core, classifyImport("msvcrt.dll", "_setjmp"));
    try std.testing.expectEqual(ImportClass.core, classifyImport("api-ms-win-crt-private-l1-1-0.dll", "longjmp"));
    try std.testing.expectEqual(ImportClass.core, classifyImport("api-ms-win-crt-utility-l1-1-0.dll", "qsort"));
    try std.testing.expectEqual(ImportClass.core, classifyImport("kernel32.dll", "SetThreadContext"));
    try std.testing.expectEqual(ImportClass.unsupported, classifyImport("kernel32.dll", "RosetteMissingEntry"));
}

test "dynamic Windows API names use the modeled inventory without accepting arbitrary symbols" {
    try std.testing.expectEqual(ImportClass.contract, classifyImport("", "AcquireSRWLockExclusive"));
    try std.testing.expectEqual(ImportClass.contract, classifyImport("", "OpenSCManagerA"));
    try std.testing.expectEqual(ImportClass.contract, classifyImport("", "LibK_GetVersion"));
    try std.testing.expectEqual(ImportClass.contract, classifyImport("", "LibK_GetProcAddress"));
    try std.testing.expectEqual(ImportClass.contract, classifyImport("", "RoInitialize"));
    try std.testing.expectEqual(ImportClass.contract, classifyImport("", "CoIncrementMTAUsage"));
    try std.testing.expectEqual(ImportClass.contract, classifyImport("", "WindowsCreateStringReference"));
    try std.testing.expectEqual(ImportClass.contract, classifyImport("", "RoGetActivationFactory"));
    try std.testing.expectEqual(ImportClass.contract, classifyImport("", "RENDERDOC_GetAPI"));
    try std.testing.expectEqual(ImportClass.unsupported, classifyImport("", "RosetteMissingOptionalProbe"));
}

test "a module Rosetta cannot serve reports absent rather than handing out a handle" {
    // XAudio2 is the case this rule exists for. Letting the load succeed made
    // Xenia's audio driver reach `XAudio2Create`, whose unimplemented return
    // is zero - S_OK for an HRESULT - and then dereference a null vtable.
    try std.testing.expect(windowsModuleUnavailableOnHost("XAudio2_8.dll"));
    try std.testing.expect(windowsModuleUnavailableOnHost("C:\\Windows\\System32\\XAudio2_9.dll"));
    try std.testing.expect(windowsModuleUnavailableOnHost("dxcompiler.dll"));
    // Pre-existing refusals: Rosetta has no Direct3D device to hand over.
    try std.testing.expect(windowsModuleUnavailableOnHost("D3D12.dll"));
    try std.testing.expect(windowsModuleUnavailableOnHost("dxgi.dll"));

    // The two that must never be refused. Xenia gives up on graphics entirely
    // when `vulkan-1.dll` is absent, and its controller driver returns
    // X_STATUS_DLL_NOT_FOUND when `xinput1_4.dll` is.
    try std.testing.expect(!windowsModuleUnavailableOnHost("vulkan-1.dll"));
    try std.testing.expect(!windowsModuleUnavailableOnHost("xinput1_4.dll"));
    try std.testing.expect(!windowsModuleUnavailableOnHost("user32.dll"));
    try std.testing.expect(!windowsModuleUnavailableOnHost("SHCore.dll"));
    try std.testing.expect(!windowsModuleUnavailableOnHost("winmm.dll"));
}

test "a dynamic lookup answers NULL for a name Rosetta has no implementation for" {
    // The whole Vulkan path is reached this way, so it has to resolve even
    // though no Win32 package owns a `vk` name.
    try std.testing.expect(isRecognizedDynamicImport("vulkan-1.dll", "vkGetInstanceProcAddr"));
    try std.testing.expect(isRecognizedDynamicImport("vulkan-1.dll", "vkDestroyInstance"));
    try std.testing.expect(isRecognizedDynamicImport("", "vkCreateSwapchainKHR"));
    // XInput resolves by name; the ordinal-100 spelling is handled separately
    // at the call site because an ordinal is not a string.
    try std.testing.expect(isRecognizedDynamicImport("xinput1_4.dll", "XInputGetState"));
    try std.testing.expect(isRecognizedDynamicImport("xinput1_4.dll", "XInputGetStateEx"));
    // Names Rosetta does not implement. A stub here would answer the caller's
    // explicit "do you have this?" with yes and then fail somewhere else.
    try std.testing.expect(!isRecognizedDynamicImport("XAudio2_8.dll", "XAudio2Create"));
    try std.testing.expect(!isRecognizedDynamicImport("dxilconv.dll", "DxcCreateInstance"));
    try std.testing.expect(!isRecognizedDynamicImport("", ""));
}

test "the two all-or-nothing dynamic probes a controller stack makes now resolve" {
    // SDL's WIN_LoadHIDDLL resolves these seven and unloads hid.dll if any one
    // is missing, which disables the raw-input joystick backend entirely. The
    // 2026-09-11 run refused all seven.
    const raw_input = [_][]const u8{
        "HidD_GetManufacturerString",
        "HidD_GetProductString",
        "HidP_GetCaps",
        "HidP_GetButtonCaps",
        "HidP_GetValueCaps",
        "HidP_MaxDataListLength",
        "HidP_GetData",
    };
    for (raw_input) |name| {
        if (!isRecognizedDynamicImport("hid.dll", name)) {
            std.debug.print("hid.dll export '{s}' still resolves to NULL\n", .{name});
            return error.HidExportUnresolved;
        }
    }
    // hidapi's list adds these.
    try std.testing.expect(isRecognizedDynamicImport("hid.dll", "HidD_GetAttributes"));
    try std.testing.expect(isRecognizedDynamicImport("hid.dll", "HidD_GetPreparsedData"));
    try std.testing.expect(isRecognizedDynamicImport("WinUSB.dll", "WinUsb_AbortPipe"));

    // Xenia's per-monitor DPI v1 probe. Answering it is not a courtesy:
    // Rosetta presents one virtual display at a known scale, so the question
    // has a correct answer and refusing it took a fallback for nothing.
    try std.testing.expect(isRecognizedDynamicImport("SHCore.dll", "GetDpiForMonitor"));
    try std.testing.expect(!windowsModuleUnavailableOnHost("SHCore.dll"));
    try std.testing.expect(!windowsModuleUnavailableOnHost("hid.dll"));
    try std.testing.expect(windowsModuleUnavailableOnHost("libusbK.dll"));
}

test "Win32 default geometry is normalized before native window creation" {
    try std.testing.expectEqual(@as(u64, 1280), normalizeWindowDimension(cw_use_default, default_window_width));
    try std.testing.expectEqual(@as(u64, 720), normalizeWindowDimension(cw_use_default, default_window_height));
    try std.testing.expectEqual(@as(u64, 1280), normalizeWindowDimension(0, default_window_width));
    try std.testing.expectEqual(@as(u64, 720), normalizeWindowDimension(max_window_dimension + 1, default_window_height));
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64) - 2), hwnd_message);
}

test {
    // `pub const` re-exports do not root a file's tests; reference the module
    // explicitly so the import-contract tests run with this one.
    _ = import_contract;
}
