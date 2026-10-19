//! Core Windows import dispatch. Helper references arrive through a
//! compile-time API table, so the moved handler retains direct calls and does
//! not add runtime indirection.
pub fn handleCore(comptime api: type, state: anytype, dll_name: []const u8, name: []const u8, direct_return_rip: ?u64) bool {
    const std = api._std;
    const import_contract = api._import_contract;
    const log = api._log;
    const ModuleAvailability = api._ModuleAvailability;
    const hwnd_message = api._hwnd_message;
    const default_window_width = api._default_window_width;
    const default_window_height = api._default_window_height;
    const windows_guest_thread_service_slice = api._windows_guest_thread_service_slice;
    const rdw_invalidate = api._rdw_invalidate;
    const rdw_validate = api._rdw_validate;
    const cr_success = api._cr_success;
    const cr_failure = api._cr_failure;
    const cr_no_such_devinst = api._cr_no_such_devinst;
    const cr_no_such_devnode = api._cr_no_such_devnode;
    const cLocaleWctypeDescriptor = api._cLocaleWctypeDescriptor;
    const cLocaleIsWideClass = api._cLocaleIsWideClass;
    const normalizeWindowDimension = api._normalizeWindowDimension;
    const SYNTHETIC_PTHREAD_ONCE_RETURN = api._SYNTHETIC_PTHREAD_ONCE_RETURN;
    const importTraits = api._importTraits;
    const guestStateField = api._guestStateField;
    const guestErrnoStorage = api._guestErrnoStorage;
    const fillGuest = api._fillGuest;
    const guestRangeAvailable = api._guestRangeAvailable;
    const copyGuestBytes = api._copyGuestBytes;
    const writeWindowsGuestHandle = api._writeWindowsGuestHandle;
    const handleDxgiFactory = api._handleDxgiFactory;
    const windows_get_message_idle_rounds = api._windows_get_message_idle_rounds;
    const applyWindowsThreadCreationFlags = api._applyWindowsThreadCreationFlags;
    const arg = api._arg;
    const windowsGuestClockHz = api._windowsGuestClockHz;
    const windowsGuestFileTime = api._windowsGuestFileTime;
    const windowsGuestClockTicks = api._windowsGuestClockTicks;
    const lendXeniaGlobalLockForBackoff = api._lendXeniaGlobalLockForBackoff;
    const noteGuestClockRead = api._noteGuestClockRead;
    const closeWindowsHandleCall = api._closeWindowsHandleCall;
    const ntDelayTicks = api._ntDelayTicks;
    const finish = api._finish;
    const primaryMonitorHandle = api._primaryMonitorHandle;
    const returnZero = api._returnZero;
    const windows_status_access_violation = api._windows_status_access_violation;
    const windows_status_invalid_parameter = api._windows_status_invalid_parameter;
    const windows_status_info_length_mismatch = api._windows_status_info_length_mismatch;
    const windows_status_invalid_info_class = api._windows_status_invalid_info_class;
    const handleWindowsMultimedia = api._handleWindowsMultimedia;
    const nt_status_success = api._nt_status_success;
    const nt_status_invalid_handle = api._nt_status_invalid_handle;
    const nt_status_invalid_parameter = api._nt_status_invalid_parameter;
    const ntWaitTimeoutMilliseconds = api._ntWaitTimeoutMilliseconds;
    const finishNtWait = api._finishNtWait;
    const traceNtSynchronization = api._traceNtSynchronization;
    const traceWindowsNtdllLookup = api._traceWindowsNtdllLookup;
    const handleWindowsSetjmp = api._handleWindowsSetjmp;
    const handleWindowsLongjmp = api._handleWindowsLongjmp;
    const handleRtlCaptureContext = api._handleRtlCaptureContext;
    const handleRtlUnwindEx = api._handleRtlUnwindEx;
    const terminateWindowsCall = api._terminateWindowsCall;
    const nextHandle = api._nextHandle;
    const isSyntheticWindowsHandle = api._isSyntheticWindowsHandle;
    const versionCondition = api._versionCondition;
    const clearGuestMemory = api._clearGuestMemory;
    const writeWindowsMessage = api._writeWindowsMessage;
    const dispatchWindowsMessage = api._dispatchWindowsMessage;
    const windowsTlsSlot = api._windowsTlsSlot;
    const snapshotGuestBytes = api._snapshotGuestBytes;
    const guestCString = api._guestCString;
    const windowsModuleBasename = api._windowsModuleBasename;
    const windowsModuleNameLooksReadable = api._windowsModuleNameLooksReadable;
    const windowsModuleAvailability = api._windowsModuleAvailability;
    const isRecognizedDynamicImport = api._isRecognizedDynamicImport;
    const noteWindowsModuleHandle = api._noteWindowsModuleHandle;
    const windowsModuleNameFor = api._windowsModuleNameFor;
    const noteWindowsModuleRefusal = api._noteWindowsModuleRefusal;
    const noteWindowsProcAddressRefusal = api._noteWindowsProcAddressRefusal;
    const noteWindowsUnreadableModuleName = api._noteWindowsUnreadableModuleName;
    const guestStdString = api._guestStdString;
    const guestWideUnit = api._guestWideUnit;
    const copyGuestWideString = api._copyGuestWideString;
    const publishGuestPathWrites = api._publishGuestPathWrites;
    const guestSystemAffinityMask = api._guestSystemAffinityMask;
    const materializeGuestAnsi = api._materializeGuestAnsi;
    const materializeGuestWide = api._materializeGuestWide;
    const wideCharToUtf8 = api._wideCharToUtf8;
    const multiByteToWide = api._multiByteToWide;
    const cachedGuestString = api._cachedGuestString;
    const guestStrstr = api._guestStrstr;
    const guestStrtol = api._guestStrtol;
    const cachedGuestCLocaleConv = api._cachedGuestCLocaleConv;
    const launchArgumentCount = api._launchArgumentCount;
    const cachedGuestCommandLine = api._cachedGuestCommandLine;
    const cachedGuestPointer = api._cachedGuestPointer;
    const cachedGuestArgc = api._cachedGuestArgc;
    const cachedGuestArgv = api._cachedGuestArgv;
    const cachedGuestArgvStorage = api._cachedGuestArgvStorage;
    const cachedGuestEnvironmentStorage = api._cachedGuestEnvironmentStorage;
    const noteSdlAudioDriverQuery = api._noteSdlAudioDriverQuery;
    const environmentValue = api._environmentValue;
    const windowsErrorString = api._windowsErrorString;
    const wideEnvironmentValue = api._wideEnvironmentValue;
    const copyGuestString = api._copyGuestString;
    const guestWideToUtf8Buffer = api._guestWideToUtf8Buffer;
    const normalizedFullPath = api._normalizedFullPath;
    const writeFullPathFilePart = api._writeFullPathFilePart;
    const guestPathToHost = api._guestPathToHost;
    const hostStat = api._hostStat;
    const deleteWindowsFile = api._deleteWindowsFile;
    const installWindowsStandardStream = api._installWindowsStandardStream;
    const windowsFileSlot = api._windowsFileSlot;
    const closeWindowsFile = api._closeWindowsFile;
    const failWindowsFileCall = api._failWindowsFileCall;
    const statWindowsPath = api._statWindowsPath;
    const statWindowsDescriptor = api._statWindowsDescriptor;
    const closeWindowsFind = api._closeWindowsFind;
    const openWindowsFile = api._openWindowsFile;
    const openWindowsStdio = api._openWindowsStdio;
    const transferWindowsDescriptor = api._transferWindowsDescriptor;
    const seekWindowsDescriptor = api._seekWindowsDescriptor;
    const lengthWindowsDescriptor = api._lengthWindowsDescriptor;
    const openWindowsDescriptorAsStdio = api._openWindowsDescriptorAsStdio;
    const closeWindowsDescriptor = api._closeWindowsDescriptor;
    const setvbufWindowsStdio = api._setvbufWindowsStdio;
    const queryWindowsStdioState = api._queryWindowsStdioState;
    const readWindowsStdioWide = api._readWindowsStdioWide;
    const writeWindowsStdio = api._writeWindowsStdio;
    const transferWindowsStdio = api._transferWindowsStdio;
    const seekWindowsStdio = api._seekWindowsStdio;
    const flushWindowsStdio = api._flushWindowsStdio;
    const stdioFileInfo = api._stdioFileInfo;
    const truncateWindowsStdio = api._truncateWindowsStdio;
    const transferWindowsFile = api._transferWindowsFile;
    const windowsFileSize = api._windowsFileSize;
    const setWindowsFilePointer = api._setWindowsFilePointer;
    const truncateWindowsFile = api._truncateWindowsFile;
    const queryWindowsFileAttributes = api._queryWindowsFileAttributes;
    const beginWindowsFind = api._beginWindowsFind;
    const advanceWindowsFindCall = api._advanceWindowsFindCall;
    const handleStringAndMemory = api._handleStringAndMemory;
    const handleWindowsRegistry = api._handleWindowsRegistry;
    const handleWindowsSockets = api._handleWindowsSockets;
    const handleWindowsSecurity = api._handleWindowsSecurity;
    const handleWindowsCompleteness = api._handleWindowsCompleteness;
    const handleWindowsSrwLock = api._handleWindowsSrwLock;
    const completeWithImportFallback = api._completeWithImportFallback;
    // SRW lock imports are a frequent Xenia synchronization boundary. Keep
    // these four names ahead of the registry/socket/security/string handler
    // chain; the helper retains their ownership, TSO fences, waiter handoff,
    // and failure behavior.
    if (handleWindowsSrwLock(state, name, direct_return_rip)) return true;
    if (handleWindowsRegistry(state, name, direct_return_rip)) return true;
    if (handleWindowsSockets(state, name, direct_return_rip)) return true;
    if (handleWindowsSecurity(state, name, direct_return_rip)) return true;
    if (handleWindowsMultimedia(state, dll_name, name, direct_return_rip)) return true;
    if (handleStringAndMemory(state, name, direct_return_rip)) return true;
    if (handleWindowsCompleteness(state, dll_name, name, direct_return_rip)) return true;

    if (std.mem.eql(u8, name, "strstr")) {
        const result = guestStrstr(state, arg(state, 0, direct_return_rip), arg(state, 1, direct_return_rip));
        guestStateField(state, "regs").*.rax = result orelse 0;
        guestStateField(state, "windows_last_error").* = if (result == null) 87 else 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strtol")) {
        const result = guestStrtol(state, arg(state, 0, direct_return_rip), arg(state, 1, direct_return_rip), arg(state, 2, direct_return_rip));
        if (result) |value| {
            guestStateField(state, "regs").*.rax = @bitCast(value);
            guestStateField(state, "windows_last_error").* = 0;
        } else {
            guestStateField(state, "regs").*.rax = 0;
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "_setjmp")) return handleWindowsSetjmp(state, direct_return_rip);
    if (std.mem.eql(u8, name, "longjmp")) return handleWindowsLongjmp(state, direct_return_rip);

    if (std.mem.eql(u8, name, "_crt_atexit") or std.mem.eql(u8, name, "_crt_at_quick_exit")) {
        const callback = arg(state, 0, direct_return_rip);
        const quick = std.mem.eql(u8, name, "_crt_at_quick_exit");
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "registerWindowsCrtAtexit")) {
            const registered = state.registerWindowsCrtAtexit(callback, quick, false);
            guestStateField(state, "regs").*.rax = if (registered) 0 else 22; // errno_t
        } else {
            guestStateField(state, "regs").*.rax = 22; // EINVAL: no guest callback table exists
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_register_thread_local_exe_atexit_callback")) {
        const callback = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "registerWindowsCrtAtexit")) {
            _ = state.registerWindowsCrtAtexit(callback, false, true);
        }
        // This UCRT bootstrap hook is void; its callback is invoked later
        // with the Windows DLL_PROCESS_DETACH arguments during full cleanup.
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_set_app_type")) {
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_set_new_mode")) {
        const previous = state.windows_new_mode;
        state.windows_new_mode = @truncate(arg(state, 0, direct_return_rip));
        guestStateField(state, "regs").*.rax = previous;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_set_invalid_parameter_handler")) {
        const previous = state.windows_invalid_parameter_handler;
        state.windows_invalid_parameter_handler = arg(state, 0, direct_return_rip);
        guestStateField(state, "regs").*.rax = previous;
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
        guestStateField(state, "regs").*.rax = @bitCast(now);
        guestStateField(state, "windows_last_error").* = 0;
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
        guestStateField(state, "regs").*.rax = state.windows_tm_storage;
        guestStateField(state, "windows_last_error").* = if (state.windows_tm_storage == 0) 12 else 0; // ERROR_NOT_ENOUGH_MEMORY
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "asctime")) {
        // `asctime` returns a process-owned 26-byte buffer.  Keep it stable
        // and guest-owned rather than formatting through a host pointer.
        guestStateField(state, "regs").*.rax = cachedGuestString(state, &state.windows_asctime_storage, false, "Thu Jan  1 00:00:00 1970\n");
        guestStateField(state, "windows_last_error").* = if (state.windows_asctime_storage == 0) 12 else 0; // ERROR_NOT_ENOUGH_MEMORY
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_lock_file") or std.mem.eql(u8, name, "_unlock_file")) {
        // Rosetta's cooperative executor serializes the guest stream calls;
        // these CRT bookkeeping hooks need no host mutex.  They are void
        // functions, so completing the import without a degraded zero return
        // keeps the runtime ledger honest.
        guestStateField(state, "windows_last_error").* = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "getenv")) {
        const requested = guestCString(state, arg(state, 0, direct_return_rip)) orelse &.{};
        const value = environmentValue(requested);
        if (std.ascii.eqlIgnoreCase(requested, "SDL_AUDIODRIVER")) noteSdlAudioDriverQuery(state, value, "getenv");
        guestStateField(state, "regs").*.rax = if (value) |selected|
            materializeGuestAnsi(state, selected) orelse 0
        else
            0;
        guestStateField(state, "windows_last_error").* = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "signal")) {
        const signal_number = arg(state, 0, direct_return_rip);
        if (signal_number >= state.windows_signal_handlers.len) {
            guestStateField(state, "regs").*.rax = std.math.maxInt(u64);
            guestStateField(state, "windows_last_error").* = 22; // EINVAL
        } else {
            const slot = &state.windows_signal_handlers[@as(usize, @intCast(signal_number))];
            guestStateField(state, "regs").*.rax = slot.*;
            slot.* = arg(state, 1, direct_return_rip);
            guestStateField(state, "windows_last_error").* = 0;
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
            guestStateField(state, "regs").*.rax = 0x8000_4003; // E_POINTER
        } else if (!valid_source or (header != 0 and state.guestMemory(header, 24) == null)) {
            state.write64(output, 0);
            guestStateField(state, "regs").*.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            // WinRT string activation is intentionally unavailable in this
            // Rosetta session. Preserve the documented refusal and clear the
            // output handle so a caller cannot dereference a false HSTRING.
            state.write64(output, 0);
            guestStateField(state, "regs").*.rax = 0x8000_4001; // E_NOTIMPL
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
        guestStateField(state, "regs").*.rax = cachedGuestCLocaleConv(state);
        if (guestStateField(state, "regs").*.rax == 0) guestStateField(state, "windows_last_error").* = 12; // ERROR_NOT_ENOUGH_MEMORY
        if (state.diagnose_abi) {
            log.info("Windows C localeconv: record=0x{x} decimal_point=0x{x} empty=0x{x}", .{
                guestStateField(state, "regs").*.rax,
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
                guestStateField(state, "regs").*.rax = 0;
                finish(state, direct_return_rip);
                return true;
            }
        }
        guestStateField(state, "regs").*.rax = cachedGuestString(state, &state.windows_locale_name, false, "C");
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "SymGetOptions")) {
        guestStateField(state, "regs").*.rax = state.windows_symbol_options;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SymSetOptions")) {
        const previous = state.windows_symbol_options;
        state.windows_symbol_options = @truncate(arg(state, 0, direct_return_rip));
        guestStateField(state, "regs").*.rax = previous;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SymInitialize")) {
        state.windows_symbol_services_initialized = true;
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SymCleanup")) {
        state.windows_symbol_services_initialized = false;
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "_errno")) {
        // The UCRT exposes errno as an int* rather than returning the value.
        // Keep the storage in guest memory and refresh it at each access so a
        // failed `_wstat64` is visible to libstdc++'s filesystem layer.
        if (guestErrnoStorage(state).* == 0) {
            guestErrnoStorage(state).* = state.guestAlloc(4, 4) orelse 0;
        }
        if (guestErrnoStorage(state).* == 0) {
            guestStateField(state, "regs").*.rax = 0;
        } else {
            state.write32(guestErrnoStorage(state).*, guestStateField(state, "windows_last_error").*);
            guestStateField(state, "regs").*.rax = guestErrnoStorage(state).*;
        }
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "__p__fmode") or std.mem.eql(u8, name, "__p__commode")) {
        const storage = if (std.mem.eql(u8, name, "__p__fmode"))
            &state.windows_fmode_storage
        else
            &state.windows_commode_storage;
        api._stdio_flush.initStorage(state, storage);
        guestStateField(state, "regs").*.rax = storage.*;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__acrt_iob_func")) {
        const index = arg(state, 0, direct_return_rip);
        guestStateField(state, "regs").*.rax = installWindowsStandardStream(state, index) orelse 0;
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
        const path = cachedGuestString(state, &state.windows_crt_globals.module_path_w, true, "C:\\xenia\\xenia_canary.exe");
        var path_pointer: [8]u8 = undefined;
        std.mem.writeInt(u64, &path_pointer, path, .little);
        if (output == 0 or path == 0 or !copyGuestBytes(state, output, &path_pointer)) {
            guestStateField(state, "regs").*.rax = 22; // EINVAL
        } else {
            publishGuestPathWrites();
            guestStateField(state, "regs").*.rax = 0; // errno_t success
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
        const fonts_guid = [_]u8{
            0xB7, 0x8C, 0x22, 0xFD, 0x11, 0xAE, 0xE3, 0x4A,
            0x86, 0x4C, 0x16, 0xF3, 0x91, 0x0A, 0xB8, 0xFE,
        };
        var folder_guid_storage: [16]u8 = undefined;
        const folder_guid = snapshotGuestBytes(state, folder_id, &folder_guid_storage);
        const wants_fonts = folder_guid != null and std.mem.eql(u8, folder_guid.?, &fonts_guid);
        const output = arg(state, 3, direct_return_rip); // PWSTR*
        // The caller owns the string and frees it with CoTaskMemFree, so every
        // call needs its own allocation. A cached one was freed by Xenia's
        // first font probe and handed out again to the next: on 2026-09-24
        // LoadJapaneseFont freed it a second time (a refused double free), and
        // once the heap reused the block the guest would have freed whatever
        // lived there instead.
        const path = materializeGuestWide(state, if (wants_fonts) "C:\\Windows\\Fonts" else "C:\\xenia\\Documents") orelse 0;
        const output_writable = output != 0 and state.guestMemory(output, 8) != null;
        if (!output_writable or path == 0) {
            // The caller frees *ppszPath whether or not the call succeeded,
            // so a failure must leave it NULL.
            if (output_writable) state.write64(output, 0);
            guestStateField(state, "regs").*.rax = 0x8007_0057; // E_INVALIDARG / HRESULT_FROM_WIN32
        } else {
            state.write64(output, path);
            publishGuestPathWrites();
            guestStateField(state, "regs").*.rax = 0; // S_OK
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
        if (written != 0) publishGuestPathWrites();
        guestStateField(state, "regs").*.rax = if (written == 0) 0x8000_4003 else 0; // E_POINTER/S_OK
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ShellExecuteW")) {
        // Rosetta does not launch host applications on behalf of the guest.
        // ShellExecute's <=32 failure result is explicit and lets Xenia
        // continue down its normal "no external helper" path.
        guestStateField(state, "windows_last_error").* = 2; // ERROR_FILE_NOT_FOUND
        guestStateField(state, "regs").*.rax = 0;
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
            guestStateField(state, "regs").*.rax = 0;
            return true;
        };
        if (hostStat(state, path)) |_| {
            guestStateField(state, "windows_last_error").* = 183; // ERROR_ALREADY_EXISTS
            guestStateField(state, "regs").*.rax = 0;
            finish(state, direct_return_rip);
            return true;
        }
        const io = state.windows_host_io orelse {
            failWindowsFileCall(state, direct_return_rip, 3);
            guestStateField(state, "regs").*.rax = 0;
            return true;
        };
        std.Io.Dir.cwd().createDirPath(io, path) catch {
            failWindowsFileCall(state, direct_return_rip, 3); // ERROR_PATH_NOT_FOUND
            guestStateField(state, "regs").*.rax = 0;
            return true;
        };
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "_wmkdir")) {
        const path_argument = arg(state, 0, direct_return_rip);
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const path = guestPathToHost(state, path_argument, true, &path_buffer) orelse {
            guestStateField(state, "windows_last_error").* = 3; // ERROR_PATH_NOT_FOUND
            guestStateField(state, "regs").*.rax = @bitCast(@as(i64, -1));
            finish(state, direct_return_rip);
            return true;
        };
        if (hostStat(state, path)) |_| {
            guestStateField(state, "windows_last_error").* = 17; // EEXIST
            guestStateField(state, "regs").*.rax = @bitCast(@as(i64, -1));
            finish(state, direct_return_rip);
            return true;
        }
        const io = state.windows_host_io orelse {
            guestStateField(state, "windows_last_error").* = 3; // ERROR_PATH_NOT_FOUND
            guestStateField(state, "regs").*.rax = @bitCast(@as(i64, -1));
            finish(state, direct_return_rip);
            return true;
        };
        std.Io.Dir.cwd().createDirPath(io, path) catch {
            guestStateField(state, "windows_last_error").* = 3; // ERROR_PATH_NOT_FOUND
            guestStateField(state, "regs").*.rax = @bitCast(@as(i64, -1));
            finish(state, direct_return_rip);
            return true;
        };
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 0;
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
            guestStateField(state, "regs").*.rax = 22; // EINVAL
            finish(state, direct_return_rip);
            return true;
        }
        if (state.addrToOffset(init_routine) == null) {
            log.err("Windows pthread_once initializer is outside the guest image: control=0x{x} routine=0x{x}", .{ once_control, init_routine });
            guestStateField(state, "regs").*.rax = 22; // EINVAL
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
            guestStateField(state, "regs").*.rax = 35; // EDEADLK
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
        guestStateField(state, "regs").*.rdi = 0;
        guestStateField(state, "regs").*.rsi = 0;
        guestStateField(state, "regs").*.rdx = 0;
        guestStateField(state, "regs").*.rip = init_routine;
        return true;
    }

    if (std.mem.eql(u8, name, "GetLastError")) {
        guestStateField(state, "regs").*.rax = guestStateField(state, "windows_last_error").*;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetLastError")) {
        guestStateField(state, "windows_last_error").* = @truncate(arg(state, 0, direct_return_rip));
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "wctype")) {
        const property = guestCString(state, arg(state, 0, direct_return_rip)) orelse &.{};
        const descriptor = cLocaleWctypeDescriptor(property);
        guestStateField(state, "regs").*.rax = descriptor;
        if (state.diagnose_abi) {
            log.info("Windows C-locale wctype: property='{s}' descriptor=0x{x}", .{ property, descriptor });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "iswctype")) {
        guestStateField(state, "regs").*.rax = @intFromBool(cLocaleIsWideClass(arg(state, 0, direct_return_rip), arg(state, 1, direct_return_rip)));
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
        guestStateField(state, "regs").*.rax = @intFromBool(cLocaleIsWideClass(arg(state, 0, direct_return_rip), cLocaleWctypeDescriptor(name[2..])));
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
        guestStateField(state, "regs").*.rax = result;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "strerror")) {
        const message = windowsErrorString(arg(state, 0, direct_return_rip));
        guestStateField(state, "regs").*.rax = materializeGuestAnsi(state, message) orelse 0;
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
        guestStateField(state, "regs").*.rax = @bitCast(result);
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
        guestStateField(state, "regs").*.rax = @bitCast(result);
        if (state.diagnose_abi and byte <= 0xff) {
            log.info("Windows C-locale btowc: byte=0x{x} result=0x{x}", .{ byte, guestStateField(state, "regs").*.rax });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetHandleInformation")) {
        const handle = arg(state, 0, direct_return_rip);
        const flags = arg(state, 1, direct_return_rip);
        if (flags == 0 or state.guestMemory(flags, 4) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else if (!isSyntheticWindowsHandle(state, handle)) {
            guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
            guestStateField(state, "regs").*.rax = 0;
        } else {
            // Rosetta-owned handles are not inheritable unless a future
            // handle-table contract explicitly opts them in.
            state.write32(flags, 0);
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
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

        if (!source_process_valid or !target_process_valid or !source_handle_valid or target_handle == 0) {
            // DuplicateHandle reports failure through the Win32 last-error
            // channel. Do not write a fabricated output handle: CRT startup
            // uses this result to decide whether its process/thread setup is
            // valid, and a false success only moves the failure downstream.
            guestStateField(state, "windows_last_error").* = if (target_handle == 0) 87 else 6; // INVALID_PARAMETER / INVALID_HANDLE
            guestStateField(state, "regs").*.rax = 0;
        } else {
            // Stage the candidate before advancing the allocator. A failed
            // guest write must not consume a handle or claim success.
            const duplicated_handle = state.windows_next_handle;
            if (writeWindowsGuestHandle(state, target_handle, duplicated_handle)) {
                _ = nextHandle(state);
                guestStateField(state, "windows_last_error").* = 0;
                guestStateField(state, "regs").*.rax = 1;
            } else {
                guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
                guestStateField(state, "regs").*.rax = 0;
            }
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCurrentProcess")) {
        guestStateField(state, "regs").*.rax = std.math.maxInt(u64);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCurrentThread")) {
        guestStateField(state, "regs").*.rax = std.math.maxInt(u64) - 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCurrentProcessId")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCurrentThreadId")) {
        const State = @TypeOf(state.*);
        guestStateField(state, "regs").*.rax = if (comptime @hasDecl(State, "currentWindowsThreadId"))
            state.currentWindowsThreadId()
        else
            1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "QueueUserAPC")) {
        const State = @TypeOf(state.*);
        const routine = arg(state, 0, direct_return_rip);
        const thread = arg(state, 1, direct_return_rip);
        const parameter = arg(state, 2, direct_return_rip);
        const queued = if (comptime @hasDecl(State, "queueWindowsApc")) state.queueWindowsApc(thread, routine, parameter) else false;
        guestStateField(state, "regs").*.rax = @intFromBool(queued);
        guestStateField(state, "windows_last_error").* = if (queued) 0 else 6; // ERROR_INVALID_HANDLE
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetThreadId")) {
        const handle = arg(state, 0, direct_return_rip);
        const current = std.math.maxInt(u64) - 1;
        if (handle == current) {
            // The pseudo-handle names whichever thread asks. Xenia's
            // Win32Thread keeps it for every thread it did not create and
            // reads its id back through here; 1 for all of them made every
            // such thread claim the same id.
            const State = @TypeOf(state.*);
            guestStateField(state, "regs").*.rax = if (comptime @hasDecl(State, "currentWindowsThreadId")) state.currentWindowsThreadId() else 1;
        } else {
            guestStateField(state, "regs").*.rax = 0;
            for (state.windows_guest_threads) |thread| {
                if (thread.status != .vacant and thread.handle == handle) {
                    guestStateField(state, "regs").*.rax = thread.thread_id;
                    break;
                }
            }
            if (guestStateField(state, "regs").*.rax == 0) guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
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
            guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
            guestStateField(state, "regs").*.rax = if (std.mem.eql(u8, name, "GetThreadPriority")) @bitCast(@as(i64, -15)) else 0;
        } else if (std.mem.eql(u8, name, "GetThreadPriority")) {
            guestStateField(state, "regs").*.rax = if (found_index) |index| @bitCast(@as(i64, state.windows_guest_threads[index].priority)) else 0;
        } else {
            const priority: i32 = @bitCast(@as(u32, @truncate(arg(state, 1, direct_return_rip))));
            if (found_index) |index| state.windows_guest_threads[index].priority = priority;
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ResumeThread") or std.mem.eql(u8, name, "SuspendThread")) {
        // Both answer the previous suspend count, or (DWORD)-1. The count is
        // what the cooperative scheduler reads: a thread whose count is not
        // zero is never chosen, which is the whole of what suspension means
        // to the guest.
        const handle = arg(state, 0, direct_return_rip);
        const suspending = std.mem.eql(u8, name, "SuspendThread");
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "changeWindowsGuestThreadSuspension")) {
            guestStateField(state, "regs").*.rax = state.changeWindowsGuestThreadSuspension(handle, suspending);
        } else {
            var result: u64 = std.math.maxInt(u32);
            for (&state.windows_guest_threads) |*thread| {
                if (thread.status != .vacant and thread.handle == handle) {
                    result = thread.suspend_count;
                    if (suspending) {
                        thread.suspend_count +|= 1;
                    } else if (thread.suspend_count != 0) {
                        thread.suspend_count -= 1;
                    }
                    guestStateField(state, "windows_last_error").* = 0;
                    break;
                }
            }
            guestStateField(state, "regs").*.rax = result;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetProcessHeap")) {
        guestStateField(state, "regs").*.rax = 0xFFFF_F000_0000_0100;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetProcessAffinityMask")) {
        const process_mask = arg(state, 1, direct_return_rip);
        const system_mask = arg(state, 2, direct_return_rip);
        if (process_mask == 0 or system_mask == 0 or
            state.guestMemory(process_mask, 8) == null or state.guestMemory(system_mask, 8) == null)
        {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            state.write64(process_mask, state.windows_process_affinity_mask);
            state.write64(system_mask, guestSystemAffinityMask(state));
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetProcessAffinityMask")) {
        const mask = arg(state, 1, direct_return_rip);
        if (mask == 0) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            state.windows_process_affinity_mask = mask;
            const State = @TypeOf(state.*);
            if (comptime @hasField(State, "windows_process_affinity_published")) {
                state.windows_process_affinity_published.store(mask, .release);
            }
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "FlushInstructionCache")) {
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetModuleHandleExW")) {
        const output = arg(state, 2, direct_return_rip);
        if (output == 0 or state.guestMemory(output, 8) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            state.write64(output, state.image_low);
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
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
        guestStateField(state, "regs").*.rax = mask;
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
        guestStateField(state, "regs").*.rax = if (unavailable) 0 else nextHandle(state);
        guestStateField(state, "windows_last_error").* = if (unavailable) 126 else 0; // ERROR_MOD_NOT_FOUND
        if (!unavailable and guestStateField(state, "regs").*.rax != 0 and readable) {
            if (module_path) |path| noteWindowsModuleHandle(state, guestStateField(state, "regs").*.rax, windowsModuleBasename(path));
        }
        if (!readable) {
            noteWindowsUnreadableModuleName(
                state,
                name,
                module_path orelse "",
                arg(state, 0, direct_return_rip),
                direct_return_rip orelse state.read64(guestStateField(state, "regs").*.rsp),
            );
        }
        if (unavailable) noteWindowsModuleRefusal(
            state,
            name,
            module_path orelse "<unreadable>",
            availability,
            direct_return_rip orelse state.read64(guestStateField(state, "regs").*.rsp),
        );
        if (module_path) |path| {
            traceWindowsNtdllLookup(state, name, windowsModuleBasename(path), "<module-handle>", guestStateField(state, "regs").*.rax);
        }
        if (state.diagnose_abi and is_load_library) {
            log.info("PE64 Windows {s}: module='{s}' result=0x{x}", .{ name, module_path orelse "<unreadable>", guestStateField(state, "regs").*.rax });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "FreeLibrary")) {
        guestStateField(state, "regs").*.rax = 1;
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
            guestStateField(state, "regs").*.rax = if (requested_address == 100)
                state.registerWindowsImportStub("xinput1_4.dll", "XInputGetStateEx") orelse 0
            else
                0;
            if (guestStateField(state, "regs").*.rax == 0) guestStateField(state, "windows_last_error").* = 127; // ERROR_PROC_NOT_FOUND
        } else if (guestCString(state, requested_address)) |requested| {
            // A dynamic lookup is a *question*, and "no" is a valid answer
            // every caller already handles - that is why the caller used
            // GetProcAddress instead of an import. Handing back a stub for a
            // name Rosetta does not implement converts that question into a
            // promise, and the promise is broken later, inside whatever the
            // guest does with the pointer. Xenia's per-monitor DPI probe and
            // its XAudio2 entry point both take this path.
            const State = @TypeOf(state.*);
            if (comptime @hasDecl(State, "tryNativeWindowsVulkan")) {
                if (std.ascii.eqlIgnoreCase(module_name, "vulkan-1.dll") or
                    std.ascii.eqlIgnoreCase(module_name, "vulkan-1") or
                    std.ascii.eqlIgnoreCase(module_name, "vulkan.dll"))
                {
                    // Export lookup must use the same capability check as
                    // Vulkan's own proc queries, and return a Windows thunk.
                    if (state.tryNativeWindowsVulkan("vkGetInstanceProcAddr", direct_return_rip)) {
                        guestStateField(state, "windows_last_error").* = if (guestStateField(state, "regs").*.rax == 0) 127 else 0;
                        return true; // Native lookup already completed the call.
                    }
                }
            }
            if (isRecognizedDynamicImport(module_name, requested)) {
                guestStateField(state, "regs").*.rax = state.registerWindowsImportStub(module_name, requested) orelse 0;
                guestStateField(state, "windows_last_error").* = if (guestStateField(state, "regs").*.rax == 0) 127 else 0;
            } else {
                guestStateField(state, "regs").*.rax = 0;
                guestStateField(state, "windows_last_error").* = 127; // ERROR_PROC_NOT_FOUND
                noteWindowsProcAddressRefusal(
                    state,
                    module_name,
                    requested,
                    direct_return_rip orelse state.read64(guestStateField(state, "regs").*.rsp),
                );
            }
        } else {
            guestStateField(state, "regs").*.rax = 0;
            guestStateField(state, "windows_last_error").* = 127; // ERROR_PROC_NOT_FOUND
        }
        if (guestCString(state, requested_address)) |requested| {
            traceWindowsNtdllLookup(state, name, module_name, requested, guestStateField(state, "regs").*.rax);
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCommandLineA") or std.mem.eql(u8, name, "GetCommandLineW")) {
        const wide = std.mem.endsWith(u8, name, "W");
        guestStateField(state, "regs").*.rax = if (wide)
            cachedGuestCommandLine(state, &state.windows_command_line_w, true)
        else
            cachedGuestCommandLine(state, &state.windows_command_line_a, false);
        if (state.diagnose_abi) {
            log.info("Windows command line: api={s} pointer=0x{x} argc={d}", .{ name, guestStateField(state, "regs").*.rax, launchArgumentCount(state) });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p___argc")) {
        guestStateField(state, "regs").*.rax = cachedGuestArgc(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p___argv")) {
        guestStateField(state, "regs").*.rax = cachedGuestArgvStorage(state, false);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p___wargv")) {
        guestStateField(state, "regs").*.rax = cachedGuestArgvStorage(state, true);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p__environ")) {
        guestStateField(state, "regs").*.rax = cachedGuestEnvironmentStorage(state, false);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p__wenviron")) {
        guestStateField(state, "regs").*.rax = cachedGuestEnvironmentStorage(state, true);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "__p__wcmdln")) {
        const command_line = cachedGuestCommandLine(state, &state.windows_command_line_w, true);
        guestStateField(state, "regs").*.rax = cachedGuestPointer(state, &state.windows_wcmdln_storage, command_line);
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
        if (wide and destination != 0 and capacity > source.len) publishGuestPathWrites();
        if (destination == 0 or capacity == 0) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else if (copied < source.len) {
            guestStateField(state, "windows_last_error").* = 122; // ERROR_INSUFFICIENT_BUFFER
            guestStateField(state, "regs").*.rax = capacity;
        } else {
            guestStateField(state, "regs").*.rax = copied;
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
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            state.write64(information + 0, state.image_low);
            state.write32(information + 8, @intCast(image_size));
            state.write64(information + 16, state.windows_entry_point);
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetUnhandledExceptionFilter")) {
        const previous = state.windows_unhandled_exception_filter;
        state.windows_unhandled_exception_filter = arg(state, 0, direct_return_rip);
        guestStateField(state, "regs").*.rax = previous;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "AddVectoredExceptionHandler") or
        std.mem.eql(u8, name, "AddVectoredContinueHandler"))
    {
        const handler = arg(state, 1, direct_return_rip);
        if (handler == 0 or state.addrToOffset(handler) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            const token = nextHandle(state);
            state.windows_vectored_exception_handler = handler;
            state.windows_vectored_exception_token = token;
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = token;
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
        guestStateField(state, "windows_last_error").* = if (removed) 0 else 87;
        guestStateField(state, "regs").*.rax = @intFromBool(removed);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetStartupInfoW")) {
        const startup_info = arg(state, 0, direct_return_rip);
        if (startup_info == 0 or state.guestMemory(startup_info, 104) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
        } else {
            _ = fillGuest(state, startup_info, 104, 0);
            state.write32(startup_info, 104);
            guestStateField(state, "windows_last_error").* = 0;
        }
        // GetStartupInfoW is void; the return register is intentionally not
        // used as a success signal.
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetThreadDescription")) {
        const output = arg(state, 1, direct_return_rip);
        // The caller frees the description with LocalFree: one allocation
        // per call, as with SHGetKnownFolderPath.
        const description = materializeGuestWide(state, "Rosetta thread") orelse 0;
        if (output == 0 or description == 0) {
            guestStateField(state, "regs").*.rax = 0x8007_000E; // E_OUTOFMEMORY / invalid output
        } else {
            state.write64(output, description);
            guestStateField(state, "regs").*.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetThreadDescription")) {
        // The guest is telling Rosette which of its threads is which. Every
        // per-thread report in the run is otherwise a bare handle and a
        // symbol, and deciding whether the worker holding a fifth of the
        // interpreter was the GPU frame limiter or the log writer meant
        // disassembling the image to find out. Keeping the string costs one
        // bounded copy at thread creation.
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "setWindowsGuestThreadName")) {
            const handle = arg(state, 0, direct_return_rip);
            const text = arg(state, 1, direct_return_rip);
            var narrow: [64]u8 = undefined;
            var written: usize = 0;
            while (written < narrow.len) {
                const unit = guestWideUnit(state, text, written) orelse break;
                if (unit == 0) break;
                // Xenia's thread names are ASCII; anything wider is folded
                // rather than dropped so the name stays recognizable.
                narrow[written] = if (unit < 0x80) @intCast(unit) else '?';
                written += 1;
            }
            if (written != 0) _ = state.setWindowsGuestThreadName(handle, narrow[0..written]);
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetThreadContext")) {
        const handle = arg(state, 0, direct_return_rip);
        const context = arg(state, 1, direct_return_rip);
        const current_thread = std.math.maxInt(u64) - 1;
        const context_valid = context != 0 and state.guestMemory(context, 0x38) != null;
        if ((!isSyntheticWindowsHandle(state, handle) and handle != current_thread) or !context_valid) {
            guestStateField(state, "windows_last_error").* = if (context_valid) 6 else 87;
            guestStateField(state, "regs").*.rax = 0;
        } else {
            // The PE runner has one cooperative guest context rather than a
            // native Windows thread handle. Validate the caller's CONTEXT
            // storage and acknowledge the contract, while retaining the
            // The cooperative executor has no second native register context
            // to install, but the validated guest CONTEXT contract is fully
            // modeled for the current thread.
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
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
            guestStateField(state, "windows_last_error").* = 203; // ERROR_ENVVAR_NOT_FOUND
            guestStateField(state, "regs").*.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        const copied = if (wide)
            copyGuestWideString(state, destination, capacity, selected)
        else
            copyGuestString(state, destination, capacity, selected);
        if (destination == 0 or capacity == 0) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else if (copied < selected.len) {
            guestStateField(state, "windows_last_error").* = 122; // ERROR_INSUFFICIENT_BUFFER
            guestStateField(state, "regs").*.rax = selected.len + 1;
        } else {
            guestStateField(state, "regs").*.rax = copied;
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
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else if (copied < source.len) {
            guestStateField(state, "windows_last_error").* = 122; // ERROR_INSUFFICIENT_BUFFER
            guestStateField(state, "regs").*.rax = source.len + 1;
        } else {
            guestStateField(state, "regs").*.rax = copied;
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
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        var full_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = normalizedFullPath(value, &full_path_buffer) orelse {
            guestStateField(state, "windows_last_error").* = 206; // ERROR_FILENAME_EXCED_RANGE
            guestStateField(state, "regs").*.rax = 0;
            finish(state, direct_return_rip);
            return true;
        };
        const file_part = arg(state, 3, direct_return_rip);
        if (wide) {
            if (capacity > full_path.len and destination != 0) {
                _ = copyGuestWideString(state, destination, capacity, full_path);
                writeFullPathFilePart(state, destination, capacity, full_path, file_part, true);
                publishGuestPathWrites();
                guestStateField(state, "regs").*.rax = full_path.len;
            } else {
                guestStateField(state, "regs").*.rax = full_path.len + 1;
            }
        } else if (capacity > full_path.len and destination != 0) {
            _ = copyGuestString(state, destination, capacity, full_path);
            writeFullPathFilePart(state, destination, capacity, full_path, file_part, false);
            guestStateField(state, "regs").*.rax = full_path.len;
        } else {
            guestStateField(state, "regs").*.rax = full_path.len + 1;
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
            guestStateField(state, "regs").*.rax = count;
        } else {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
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
                guestStateField(state, "regs").*.rax,
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
            guestStateField(state, "regs").*.rax = count;
        } else {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
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
        guestStateField(state, "regs").*.rax = argv;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetVersionExA") or std.mem.eql(u8, name, "GetVersionExW")) {
        const version = arg(state, 0, direct_return_rip);
        if (version == 0 or state.guestMemory(version, 20) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            state.write32(version + 4, 10); // dwMajorVersion
            state.write32(version + 8, 0); // dwMinorVersion
            state.write32(version + 12, 22621); // dwBuildNumber
            state.write32(version + 16, 2); // VER_PLATFORM_WIN32_NT
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VerifyVersionInfoA") or std.mem.eql(u8, name, "VerifyVersionInfoW")) {
        const info = arg(state, 0, direct_return_rip);
        const type_mask: u32 = @truncate(arg(state, 1, direct_return_rip));
        const condition_mask = arg(state, 2, direct_return_rip);
        if (info == 0 or state.guestMemory(info, 20) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
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
            guestStateField(state, "windows_last_error").* = if (matches) 0 else 1150; // ERROR_OLD_WIN_VERSION
            guestStateField(state, "regs").*.rax = @intFromBool(matches);
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
        // The keyboard pad lives in slot 0 only, matching the Xam shim.
        const keyboard_slot = arg(state, 0, direct_return_rip) == 0;
        const bridged = if (comptime @hasDecl(@TypeOf(state.*), "writeWindowsXInputState"))
            keyboard_slot and state.writeWindowsXInputState(output)
        else
            false;
        if (!bridged) {
            if (output != 0) _ = clearGuestMemory(state, output, 16); // XINPUT_STATE
            guestStateField(state, "regs").*.rax = 1167; // ERROR_DEVICE_NOT_CONNECTED
        } else {
            guestStateField(state, "regs").*.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "XInputGetCapabilities")) {
        const output = arg(state, 2, direct_return_rip);
        if (output != 0) _ = clearGuestMemory(state, output, 20); // XINPUT_CAPABILITIES
        guestStateField(state, "regs").*.rax = 1167; // ERROR_DEVICE_NOT_CONNECTED
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "XInputGetBatteryInformation")) {
        const output = arg(state, 2, direct_return_rip);
        if (output != 0) _ = clearGuestMemory(state, output, 2); // BATTERY_INFORMATION
        guestStateField(state, "regs").*.rax = 1167; // ERROR_DEVICE_NOT_CONNECTED
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "XInputSetState")) {
        const output = arg(state, 1, direct_return_rip);
        if (output != 0) _ = clearGuestMemory(state, output, 2); // vibration is not applied
        guestStateField(state, "regs").*.rax = 1167; // ERROR_DEVICE_NOT_CONNECTED
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "XInputGetKeystroke")) {
        const output = arg(state, 2, direct_return_rip);
        if (output != 0) _ = clearGuestMemory(state, output, 8); // XINPUT_KEYSTROKE
        guestStateField(state, "regs").*.rax = 259; // ERROR_NO_MORE_ITEMS
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
        const allocation_caller_rip = direct_return_rip orelse state.read64(guestStateField(state, "regs").*.rsp);
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
        } else state.guestAlloc(std.mem.alignForward(u64, @max(size, 1), 0x1000), 0x1000) orelse 0;
        // Whole pages: a protection the guest later puts on this block must
        // not reach into the next heap allocation's bytes.
        guestStateField(state, "regs").*.rax = address;
        // An allocation the guest is allowed to execute is where a program
        // with a translator puts the code it generates. Recording it is the
        // whole mechanism behind naming a JIT: Rosette need not know what
        // Xenia is, only that the guest asked for memory it can run and
        // later turned up executing there.
        if (address != 0) {
            const State = @TypeOf(state.*);
            const protection = if (extended) arg(state, 4, direct_return_rip) else arg(state, 3, direct_return_rip);
            if (comptime @hasDecl(State, "noteGuestExecutableAllocationFrom")) {
                state.noteGuestExecutableAllocationFrom(address, size, @truncate(protection), allocation_caller_rip);
            }
            // A commit carries the protection the guest will rely on. Xenia
            // commits its GPU register block `PAGE_NOACCESS` and learns about
            // every register write from the fault; recording it here is what
            // lets that fault happen at all.
            if (commit_requested and comptime @hasDecl(State, "noteGuestPageProtection")) {
                state.noteGuestPageProtection(address, size, @truncate(protection), "VirtualAlloc", allocation_caller_rip);
            }
        }
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
        if ((requested_base >= 0x1_0000_0000 or address >= 0x1_0000_0000) and
            state.windowsMemoryTraceLive() and state.claimWindowsMemoryTraceEvent())
        {
            log.info("PE64 Windows fixed-address allocation request: api={s} requested_base=0x{x} size={d} result=0x{x} contains={} rip=0x{x} step={d}", .{
                name,
                requested_base,
                size,
                address,
                address != 0 and state.windowsGuestRangeContains(address, @max(size, @as(u64, 1))),
                guestStateField(state, "regs").*.rip,
                state.executed_steps,
            });
            log.info("PE64 Windows allocation contract: api={s} reserve={} commit={} requested_base=0x{x} result=0x{x} disposition={s} rip=0x{x} step={d}", .{
                name,
                reserve_requested,
                commit_requested,
                requested_base,
                address,
                disposition,
                guestStateField(state, "regs").*.rip,
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
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = handle;
        } else {
            guestStateField(state, "windows_last_error").* = 8; // ERROR_NOT_ENOUGH_MEMORY
            guestStateField(state, "regs").*.rax = 0;
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
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = guest_base;
        } else {
            guestStateField(state, "windows_last_error").* = 8; // ERROR_NOT_ENOUGH_MEMORY / conflicting address
            guestStateField(state, "regs").*.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "UnmapViewOfFile")) {
        const guest_base = arg(state, 0, direct_return_rip);
        guestStateField(state, "regs").*.rax = @intFromBool(state.unmapWindowsMemoryView(guest_base));
        guestStateField(state, "windows_last_error").* = if (guestStateField(state, "regs").*.rax != 0) 0 else 87; // ERROR_INVALID_PARAMETER
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VirtualFree") or std.mem.eql(u8, name, "VirtualFreeEx")) {
        const extended = std.mem.eql(u8, name, "VirtualFreeEx");
        const guest_base = if (extended) arg(state, 1, direct_return_rip) else arg(state, 0, direct_return_rip);
        const size = if (extended) arg(state, 2, direct_return_rip) else arg(state, 1, direct_return_rip);
        const allocation_type = if (extended) arg(state, 3, direct_return_rip) else arg(state, 2, direct_return_rip);
        const released = state.releaseWindowsVirtualAllocation(guest_base, size, allocation_type);
        if (released and (allocation_type & (0x8000 | 0x4000)) != 0) {
            const State = @TypeOf(state.*);
            if (comptime @hasDecl(State, "clearGuestPageProtection")) {
                state.clearGuestPageProtection(guest_base, size);
            }
        }
        guestStateField(state, "regs").*.rax = @intFromBool(released);
        guestStateField(state, "windows_last_error").* = if (released) 0 else 487; // ERROR_INVALID_ADDRESS
        if (state.diagnose_abi) {
            log.info("PE64 Windows {s}: guest_base=0x{x} size={d} type=0x{x} result={}", .{ name, guest_base, size, allocation_type, released });
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VirtualProtect") or std.mem.eql(u8, name, "VirtualProtectEx")) {
        // This returned FALSE on every call. `VirtualProtect` is a BOOL API,
        // FALSE is failure, and a guest that checks it - Xenia's code cache
        // does, before it runs anything it generated - was being told the
        // page protection it asked for had not been applied.
        //
        // No-access and read-only requests are now enforced: the interpreter
        // consults `guest_page_protection` on every memory operand and raises
        // an access violation through the guest's vectored exception
        // handler. Guard pages remain unmodelled and are counted as such.
        const extended_protect = std.mem.eql(u8, name, "VirtualProtectEx");
        const address = if (extended_protect) arg(state, 1, direct_return_rip) else arg(state, 0, direct_return_rip);
        const length = if (extended_protect) arg(state, 2, direct_return_rip) else arg(state, 1, direct_return_rip);
        const requested = if (extended_protect) arg(state, 3, direct_return_rip) else arg(state, 2, direct_return_rip);
        const old_protection_out = if (extended_protect) arg(state, 4, direct_return_rip) else arg(state, 3, direct_return_rip);
        // Windows fails the call outright when the out-parameter is null, so
        // a guest relying on the old value is not silently handed nothing.
        if (old_protection_out == 0 or !guestRangeAvailable(state, old_protection_out, 4)) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
            finish(state, direct_return_rip);
            return true;
        }
        const State = @TypeOf(state.*);
        // The old protection is whatever this run recorded for the first page,
        // because a guest that saves and later restores it must get back the
        // restriction it asked for, not a blanket "everything".
        const old_protection: u32 = if (comptime @hasDecl(State, "guestPageProtectionFlags"))
            state.guestPageProtectionFlags(address)
        else
            0x40;
        state.write32(old_protection_out, old_protection);
        if (comptime @hasDecl(State, "noteGuestPageProtection")) {
            state.noteGuestPageProtection(address, length, @truncate(requested), name, direct_return_rip orelse state.read64(guestStateField(state, "regs").*.rsp));
        }
        if (comptime @hasDecl(State, "noteGuestExecutableAllocation")) {
            state.noteGuestExecutableAllocation(address, length, @truncate(requested));
        }
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VirtualQuery") or std.mem.eql(u8, name, "VirtualQueryEx")) {
        // `VirtualQuery` returns the number of bytes it wrote, so zero with
        // nothing written is a failure the caller cannot distinguish from a
        // bad address. Rosette knows the answer for anything inside its guest
        // range: one flat, committed, executable mapping.
        const extended_query = std.mem.eql(u8, name, "VirtualQueryEx");
        const address = if (extended_query) arg(state, 1, direct_return_rip) else arg(state, 0, direct_return_rip);
        const buffer = if (extended_query) arg(state, 2, direct_return_rip) else arg(state, 1, direct_return_rip);
        const buffer_length = if (extended_query) arg(state, 3, direct_return_rip) else arg(state, 2, direct_return_rip);
        const information_bytes: u64 = 48; // sizeof(MEMORY_BASIC_INFORMATION) on x64
        if (buffer == 0 or buffer_length < information_bytes or
            !guestRangeAvailable(state, buffer, information_bytes) or
            !state.windowsGuestRangeContains(address, 1))
        {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
            finish(state, direct_return_rip);
            return true;
        }
        const page: u64 = 0x1000;
        const base = address - (address % page);
        state.write64(buffer + 0, base); // BaseAddress
        state.write64(buffer + 8, base); // AllocationBase
        state.write32(buffer + 16, 0x40); // AllocationProtect = PAGE_EXECUTE_READWRITE
        state.write32(buffer + 20, 0); // __alignment1
        state.write64(buffer + 24, page); // RegionSize
        state.write32(buffer + 32, 0x1000); // State = MEM_COMMIT
        state.write32(buffer + 36, 0x40); // Protect = PAGE_EXECUTE_READWRITE
        state.write32(buffer + 40, 0x20000); // Type = MEM_PRIVATE
        state.write32(buffer + 44, 0); // __alignment2
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = information_bytes;
        finish(state, direct_return_rip);
        return true;
    }
    // `NtProtectVirtualMemory` and `NtQueryVirtualMemory` are ntdll's
    // spellings of `VirtualProtect` and `VirtualQuery`, and on a Xenia image
    // they are the only ones that ever run: `base/platform_win.h` defines
    // `XE_USE_NTDLL_FUNCTIONS 1`, so `xe::memory::Protect` resolves
    // `NtProtectVirtualMemory` through `GetProcAddress("ntdll.dll", ...)`
    // and calls it directly, because "ntdll versions of functions often skip
    // through a lot of extra garbage in KernelBase".
    //
    // Until this pair existed both names fell through to the generic
    // `Nt`/`Zw` arm below, which returns STATUS_SUCCESS and does nothing.
    // STATUS_SUCCESS is the worst answer available here.
    // `PhysicalHeap::EnableAccessCallbacksInner` is how Xenia learns that a
    // title rewrote a texture, a vertex buffer or an index buffer: it raises
    // the page to PAGE_READONLY, ignores the return value, and has already
    // set its own `notify_on_invalidation` bit. So every write watch in the
    // emulator was armed on Xenia's side and absent on Rosette's - no store
    // ever faulted, `PhysicalHeap::TriggerCallbacks` never ran, and the GPU
    // kept drawing out of the copy of guest memory it had uploaded once.
    // The 2026-09-19 Halo 3 run protected 80 no-access pages and *zero*
    // read-only ones across 1708 seconds and 1588 frames, and its picture
    // was torn into bands of stale geometry.
    if (std.mem.eql(u8, name, "NtProtectVirtualMemory") or
        std.mem.eql(u8, name, "ZwProtectVirtualMemory"))
    {
        const State = @TypeOf(state.*);
        const base_pointer = arg(state, 1, direct_return_rip);
        const size_pointer = arg(state, 2, direct_return_rip);
        const requested: u32 = @truncate(arg(state, 3, direct_return_rip));
        const old_protection_out = arg(state, 4, direct_return_rip);
        // The two in/out parameters and the old-protection slot are all
        // mandatory; ntdll answers STATUS_ACCESS_VIOLATION for a bad one
        // rather than protecting a range it could not read back.
        if (base_pointer == 0 or size_pointer == 0 or old_protection_out == 0 or
            !guestRangeAvailable(state, base_pointer, 8) or
            !guestRangeAvailable(state, size_pointer, 8) or
            !guestRangeAvailable(state, old_protection_out, 4))
        {
            guestStateField(state, "regs").*.rax = windows_status_access_violation;
            finish(state, direct_return_rip);
            return true;
        }
        const requested_base = state.read64(base_pointer);
        const requested_length = state.read64(size_pointer);
        // The kernel rounds the base down and the end up, and writes both
        // back. A caller that protects the same range twice must see the
        // same pages covered either way, so do the rounding here and record
        // the rounded span rather than the request.
        const page: u64 = 0x1000;
        const rounded_base = requested_base & ~(page - 1);
        const rounded_end = (requested_base +| @max(requested_length, 1) +| (page - 1)) & ~(page - 1);
        const rounded_length = @max(rounded_end -| rounded_base, page);
        const old_protection: u32 = if (comptime @hasDecl(State, "guestPageProtectionFlags"))
            state.guestPageProtectionFlags(rounded_base)
        else
            0x40;
        state.write32(old_protection_out, old_protection);
        if (comptime @hasDecl(State, "noteGuestPageProtection")) {
            state.noteGuestPageProtection(
                rounded_base,
                rounded_length,
                requested,
                name,
                direct_return_rip orelse state.read64(guestStateField(state, "regs").*.rsp),
            );
        }
        if (comptime @hasDecl(State, "noteGuestExecutableAllocation")) {
            state.noteGuestExecutableAllocation(rounded_base, rounded_length, requested);
        }
        state.write64(base_pointer, rounded_base);
        state.write64(size_pointer, rounded_length);
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 0; // STATUS_SUCCESS
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "NtQueryVirtualMemory") or
        std.mem.eql(u8, name, "ZwQueryVirtualMemory"))
    {
        // `MemoryBasicInformation` (class 0) is the only class Xenia asks
        // for, through `xe::memory::QueryProtect`. Note that Xenia passes
        // its own region length as `MemoryInformationLength` rather than
        // `sizeof(MEMORY_BASIC_INFORMATION)`, so the length is checked as a
        // lower bound and never for equality.
        const State = @TypeOf(state.*);
        const address = arg(state, 1, direct_return_rip);
        const information_class = arg(state, 2, direct_return_rip);
        const buffer = arg(state, 3, direct_return_rip);
        const buffer_length = arg(state, 4, direct_return_rip);
        const result_length_out = arg(state, 5, direct_return_rip);
        const information_bytes: u64 = 48; // sizeof(MEMORY_BASIC_INFORMATION) on x64
        if (information_class != 0) {
            guestStateField(state, "regs").*.rax = windows_status_invalid_info_class;
            finish(state, direct_return_rip);
            return true;
        }
        if (buffer == 0 or buffer_length < information_bytes or
            !guestRangeAvailable(state, buffer, information_bytes))
        {
            guestStateField(state, "regs").*.rax = windows_status_info_length_mismatch;
            finish(state, direct_return_rip);
            return true;
        }
        if (!state.windowsGuestRangeContains(address, 1)) {
            guestStateField(state, "regs").*.rax = windows_status_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        }
        const page: u64 = 0x1000;
        const base = address & ~(page - 1);
        // Report the protection this run recorded, and extend the region
        // over the neighbouring pages that share it, which is what a caller
        // walking the address space by `RegionSize` expects. The walk is
        // bounded so a uniformly accessible address space cannot make one
        // query scan the whole window.
        const protection: u32 = if (comptime @hasDecl(State, "guestPageProtectionFlags"))
            state.guestPageProtectionFlags(base)
        else
            0x40;
        const region_page_limit: u64 = 4096; // 16 MiB of 4 KiB pages
        var region_pages: u64 = 1;
        if (comptime @hasDecl(State, "guestPageProtectionFlags")) {
            while (region_pages < region_page_limit) : (region_pages += 1) {
                const next = base +| (region_pages * page);
                if (next < base) break;
                if (state.guestPageProtectionFlags(next) != protection) break;
            }
        }
        state.write64(buffer + 0, base); // BaseAddress
        state.write64(buffer + 8, base); // AllocationBase
        state.write32(buffer + 16, 0x40); // AllocationProtect = PAGE_EXECUTE_READWRITE
        state.write32(buffer + 20, 0); // __alignment1
        state.write64(buffer + 24, region_pages * page); // RegionSize
        state.write32(buffer + 32, 0x1000); // State = MEM_COMMIT
        state.write32(buffer + 36, protection); // Protect
        state.write32(buffer + 40, 0x20000); // Type = MEM_PRIVATE
        state.write32(buffer + 44, 0); // __alignment2
        if (result_length_out != 0 and guestRangeAvailable(state, result_length_out, 8)) {
            state.write64(result_length_out, information_bytes);
        }
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 0; // STATUS_SUCCESS
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "HeapAlloc") or std.mem.eql(u8, name, "RtlAllocateHeap") or
        std.mem.eql(u8, name, "LocalAlloc") or std.mem.eql(u8, name, "GlobalAlloc") or
        std.mem.eql(u8, name, "CoTaskMemAlloc"))
    {
        const size = if (std.mem.eql(u8, name, "HeapAlloc") or std.mem.eql(u8, name, "RtlAllocateHeap")) arg(state, 2, direct_return_rip) else arg(state, 1, direct_return_rip);
        guestStateField(state, "regs").*.rax = state.guestAlloc(size, 16) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "_aligned_malloc")) {
        guestStateField(state, "regs").*.rax = state.guestAllocUninitialized(arg(state, 0, direct_return_rip), arg(state, 1, direct_return_rip)) orelse 0;
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
        guestStateField(state, "regs").*.rax = state.reallocateGuest(old_guest_base, size, alignment) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "malloc") or std.mem.eql(u8, name, "_malloc_base")) {
        guestStateField(state, "regs").*.rax = state.guestAllocUninitialized(arg(state, 0, direct_return_rip), 16) orelse 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "calloc")) {
        guestStateField(state, "regs").*.rax = state.guestAlloc(arg(state, 0, direct_return_rip) *| arg(state, 1, direct_return_rip), 16) orelse 0;
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
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "InitializeCriticalSection") or
        std.mem.eql(u8, name, "InitializeCriticalSectionEx") or
        std.mem.eql(u8, name, "InitializeCriticalSectionAndSpinCount"))
    {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "initializeWindowsCriticalSection")) {
            state.initializeWindowsCriticalSection(arg(state, 0, direct_return_rip));
        }
        // The Ex and SpinCount forms return BOOL; zero would say they failed.
        guestStateField(state, "regs").*.rax = @intFromBool(!std.mem.eql(u8, name, "InitializeCriticalSection"));
        guestStateField(state, "windows_last_error").* = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DeleteCriticalSection")) {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "deleteWindowsCriticalSection")) {
            state.deleteWindowsCriticalSection(arg(state, 0, direct_return_rip));
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "EnterCriticalSection")) {
        const section = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "enterWindowsCriticalSection")) {
            var entered = false;
            switch (state.enterWindowsCriticalSection(section)) {
                // Untracked: a full table or an unreadable section runs
                // without exclusion, as every enter once did; it is counted.
                .acquired, .invalid => entered = true,
                .contended => {
                    // A worker parks; the release that hands it the section
                    // wakes it, and it asks again from this call site.
                    if (comptime @hasDecl(State, "blockWindowsGuestThreadOnSrwLock")) {
                        if (state.blockWindowsGuestThreadOnSrwLock(section)) return true;
                    }
                    // The owner queues, gives the workers their turn (the
                    // cooperative executor), and looks again.
                    if (comptime @hasDecl(State, "noteWindowsOwnerCriticalSectionWait")) {
                        state.noteWindowsOwnerCriticalSectionWait(section);
                    }
                    if (comptime @hasDecl(State, "serviceWindowsGuestThreads")) {
                        _ = state.serviceWindowsGuestThreads(state.windowsGuestWaitServiceSlice());
                    }
                    entered = state.enterWindowsCriticalSection(section) != .contended;
                },
            }
            if (!entered) {
                // Parallel mode: sleep until the section changes hands, then
                // ask again from this call site.
                if (comptime @hasDecl(State, "parkForGuestWait")) _ = state.parkForGuestWait(null, .wake);
                return true;
            }
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "LeaveCriticalSection")) {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "leaveWindowsCriticalSection")) {
            state.leaveWindowsCriticalSection(arg(state, 0, direct_return_rip));
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TryEnterCriticalSection")) {
        const State = @TypeOf(state.*);
        const entered = if (comptime @hasDecl(State, "tryEnterWindowsCriticalSection"))
            state.tryEnterWindowsCriticalSection(arg(state, 0, direct_return_rip))
        else
            true;
        guestStateField(state, "regs").*.rax = @intFromBool(entered);
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
        guestStateField(state, "regs").*.rax = handle;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InitOnceBeginInitialize")) {
        const once = arg(state, 0, direct_return_rip);
        const pending = arg(state, 2, direct_return_rip);
        const context = arg(state, 3, direct_return_rip);
        const OnceState = @TypeOf(state.*);
        // A caller that finds the initialization running can wait for it: a
        // worker always (it yields or parks), the owner in parallel mode.
        const in_progress_can_wait = blk: {
            if (comptime @hasField(OnceState, "parallel_guest_execution")) {
                if (state.parallel_guest_execution) break :blk true;
            }
            if (comptime @hasField(OnceState, "windows_active_guest_thread_slot")) {
                break :blk guestStateField(state, "windows_active_guest_thread_slot").* != null;
            }
            break :blk false;
        };
        if (once == 0 or state.guestMemory(once, 8) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            const value = state.read64(once);
            if (value == 0) {
                // INIT_ONCE_IN_INIT is the low-bit in-progress state. The
                // caller owns the callback and will publish the completed
                // state through InitOnceComplete below.
                state.write64(once, 1);
                if (pending != 0 and state.guestMemory(pending, 4) != null) state.write32(pending, 1);
                if (context != 0 and state.guestMemory(context, 8) != null) state.write64(context, 0);
            } else if ((value & 0x3) == 1 and in_progress_can_wait) {
                // Another thread is running the initialization. Windows
                // makes this caller wait for its InitOnceComplete; answering
                // "complete" handed it an object still being built, which
                // parallel threads - two FFmpeg decoders, two pthread_once
                // callers - now really race to use. Ask again from this call
                // site: a parked parallel thread is woken by the complete,
                // a cooperative one yields its turn to the initializer.
                if (comptime @hasDecl(OnceState, "parkForGuestWait")) {
                    if (!state.parkForGuestWait(null, .wake)) {
                        if (comptime @hasDecl(OnceState, "requestWindowsGuestSliceYield")) state.requestWindowsGuestSliceYield();
                    }
                }
                return true;
            } else {
                // A completed control word stores the optional context with
                // the low two tag bits reserved. An in-progress one is
                // reported complete only where no thread can wait for it (the
                // cooperative owner), as it always was.
                if (pending != 0 and state.guestMemory(pending, 4) != null) state.write32(pending, 0);
                if (context != 0 and state.guestMemory(context, 8) != null) state.write64(context, value & ~@as(u64, 0x3));
            }
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InitOnceComplete")) {
        const once = arg(state, 0, direct_return_rip);
        const flags = arg(state, 1, direct_return_rip);
        const context = arg(state, 2, direct_return_rip);
        if (once == 0 or state.guestMemory(once, 8) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else if ((flags & 0x4) != 0) {
            // INIT_ONCE_INIT_FAILED returns the control to the uninitialized
            // state so a later attempt can retry the callback.
            state.write64(once, 0);
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
        } else {
            state.write64(once, if (context == 0) 2 else context | 2);
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
        }
        // Threads waiting for this initialization look again.
        const OnceState = @TypeOf(state.*);
        if (comptime @hasDecl(OnceState, "wakeGuestWaiters")) state.wakeGuestWaiters();
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
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "signalWindowsGuestCondition")) {
            _ = state.signalWindowsGuestCondition(arg(state, 0, direct_return_rip), std.mem.eql(u8, name, "WakeAllConditionVariable"));
        }
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SleepConditionVariableCS") or
        std.mem.eql(u8, name, "SleepConditionVariableSRW"))
    {
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "sleepWindowsNativeCondition")) {
            const kind: @TypeOf(state.windows_guest_threads[0].native_condition_kind) = if (std.mem.eql(u8, name, "SleepConditionVariableCS")) .critical_section else .srw;
            switch (state.sleepWindowsNativeCondition(
                arg(state, 0, direct_return_rip),
                arg(state, 1, direct_return_rip),
                kind,
                arg(state, 2, direct_return_rip),
            )) {
                // Parked (a worker) or slept for a slice (the owner): the call
                // stays here and asks again, and finishes once the lock is
                // held again.
                .blocked, .retry => return true,
                .woken => {
                    guestStateField(state, "windows_last_error").* = 0;
                    guestStateField(state, "regs").*.rax = 1;
                    finish(state, direct_return_rip);
                    return true;
                },
                .timed_out => {
                    guestStateField(state, "windows_last_error").* = 1460; // ERROR_TIMEOUT
                    guestStateField(state, "regs").*.rax = 0;
                    finish(state, direct_return_rip);
                    return true;
                },
                .invalid => {},
            }
        }
        // Not modelled (the cooperative owner, a lock the caller does not
        // hold): a timeout-style FALSE lets the caller re-check its predicate
        // without an unbounded spin inside this call.
        guestStateField(state, "windows_last_error").* = 1460; // ERROR_TIMEOUT
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateWaitableTimerA") or std.mem.eql(u8, name, "CreateWaitableTimerW") or
        std.mem.eql(u8, name, "CreateWaitableTimerExA") or std.mem.eql(u8, name, "CreateWaitableTimerExW"))
    {
        // A timer is a wait object. Handing back a bare handle made every
        // wait on it STATUS_INVALID_HANDLE; see `registerWindowsTimer`.
        const handle = nextHandle(state);
        const manual_reset = if (std.mem.indexOf(u8, name, "Ex") != null)
            (arg(state, 2, direct_return_rip) & 1) != 0 // CREATE_WAITABLE_TIMER_MANUAL_RESET
        else
            arg(state, 1, direct_return_rip) != 0;
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "registerWindowsTimer")) state.registerWindowsTimer(handle, manual_reset);
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = handle;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetWaitableTimer") or std.mem.eql(u8, name, "SetWaitableTimerEx")) {
        const handle = arg(state, 0, direct_return_rip);
        const due_address = arg(state, 1, direct_return_rip);
        const State = @TypeOf(state.*);
        if (due_address == 0 or state.guestMemoryConst(due_address, 8) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else if (comptime @hasDecl(State, "setWindowsTimer")) {
            const due: i64 = @bitCast(state.read64(due_address));
            const period: u64 = @as(u32, @truncate(arg(state, 2, direct_return_rip)));
            if (state.setWindowsTimer(handle, due, period, windowsGuestFileTime(state), arg(state, 3, direct_return_rip))) {
                guestStateField(state, "windows_last_error").* = 0;
                guestStateField(state, "regs").*.rax = 1;
            } else {
                guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
                guestStateField(state, "regs").*.rax = 0;
            }
        } else {
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CancelWaitableTimer")) {
        const State = @TypeOf(state.*);
        const cancelled = if (comptime @hasDecl(State, "cancelWindowsTimer"))
            state.cancelWindowsTimer(arg(state, 0, direct_return_rip))
        else
            true;
        guestStateField(state, "windows_last_error").* = if (cancelled) 0 else 6;
        guestStateField(state, "regs").*.rax = @intFromBool(cancelled);
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
            guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
            guestStateField(state, "regs").*.rax = 0;
        } else if (!valid_outputs) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            // The bounded Rosetta executor has no completion packet queued at
            // this boundary. Report an empty queue as WAIT_TIMEOUT and keep
            // all optional output fields deterministic.
            if (bytes_transferred != 0) state.write32(bytes_transferred, 0);
            if (completion_key != 0) state.write64(completion_key, 0);
            if (overlapped != 0) state.write64(overlapped, 0);
            guestStateField(state, "windows_last_error").* = 258; // WAIT_TIMEOUT
            guestStateField(state, "regs").*.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateIoCompletionPort")) {
        const existing = arg(state, 1, direct_return_rip);
        if (existing != 0 and !isSyntheticWindowsHandle(state, existing)) {
            guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
            guestStateField(state, "regs").*.rax = 0;
        } else {
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = if (existing != 0) existing else nextHandle(state);
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
        const creation_flags = arg(state, 4, direct_return_rip);
        const thread_id_out = arg(state, 5, direct_return_rip);
        if (start_routine == 0 or state.addrToOffset(start_routine) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
            finish(state, direct_return_rip);
            return true;
        }

        const handle = nextHandle(state);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "enqueueWindowsGuestThread")) {
            if (!state.enqueueWindowsGuestThread(handle, start_routine, argument, stack_size, true)) {
                guestStateField(state, "windows_last_error").* = 8; // ERROR_NOT_ENOUGH_MEMORY
                guestStateField(state, "regs").*.rax = 0;
                finish(state, direct_return_rip);
                return true;
            }
            applyWindowsThreadCreationFlags(state, handle, creation_flags, thread_id_out);
        }
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = handle;
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
        // `_beginthread` has no flags; libwinpthread's `_beginthreadex` passes
        // CREATE_SUSPENDED and resumes once `pthread_create` has stored the
        // handle the start routine reads.
        const creation_flags: u64 = if (is_beginthreadex) arg(state, 4, direct_return_rip) else 0;
        const thread_id_out: u64 = if (is_beginthreadex) arg(state, 5, direct_return_rip) else 0;
        if (start_routine == 0 or state.addrToOffset(start_routine) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
            finish(state, direct_return_rip);
            return true;
        }

        const handle = nextHandle(state);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "enqueueWindowsGuestThread")) {
            if (!state.enqueueWindowsGuestThread(handle, start_routine, argument, stack_size, false)) {
                guestStateField(state, "windows_last_error").* = 8; // ERROR_NOT_ENOUGH_MEMORY
                guestStateField(state, "regs").*.rax = 0;
                finish(state, direct_return_rip);
                return true;
            }
            applyWindowsThreadCreationFlags(state, handle, creation_flags, thread_id_out);
        }
        guestStateField(state, "regs").*.rax = handle;
        guestStateField(state, "windows_last_error").* = 0;
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
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ResetEvent")) {
        const handle = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        const reset = if (comptime @hasDecl(State, "resetWindowsWaitObject")) state.resetWindowsWaitObject(handle) else true;
        guestStateField(state, "regs").*.rax = @intFromBool(reset);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ReleaseMutex") or std.mem.eql(u8, name, "ReleaseSemaphore")) {
        const handle = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        var succeeded = true;
        if (std.mem.eql(u8, name, "ReleaseSemaphore")) {
            if (comptime @hasDecl(State, "releaseWindowsSemaphore")) {
                const release_count = arg(state, 1, direct_return_rip);
                const previous_out = arg(state, 2, direct_return_rip);
                const previous = if (comptime @hasDecl(State, "windowsWaitObjectSemaphoreCount"))
                    state.windowsWaitObjectSemaphoreCount(handle)
                else
                    null;
                // A release that answered TRUE for a handle Rosette never
                // created is how a semaphore stops working without anything
                // saying so: the waiter it was meant for sleeps forever and
                // the only trace is a success.
                succeeded = state.releaseWindowsSemaphore(handle, release_count);
                if (succeeded) {
                    if (previous_out != 0 and state.guestMemory(previous_out, 4) != null) {
                        state.write32(previous_out, previous orelse 0);
                    }
                    guestStateField(state, "windows_last_error").* = 0;
                } else {
                    guestStateField(state, "windows_last_error").* = if (release_count == 0) 87 else 6; // INVALID_PARAMETER / INVALID_HANDLE
                }
            }
        } else if (comptime @hasDecl(State, "releaseWindowsMutex")) {
            succeeded = state.releaseWindowsMutex(handle);
        }
        guestStateField(state, "regs").*.rax = @intFromBool(succeeded);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CloseHandle") or std.mem.eql(u8, name, "SwitchToThread") or
        std.mem.eql(u8, name, "TryEnterCriticalSection"))
    {
        if (std.mem.eql(u8, name, "CloseHandle")) return closeWindowsHandleCall(state, arg(state, 0, direct_return_rip), direct_return_rip);
        guestStateField(state, "regs").*.rax = 1;
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
        // bAlertable: third argument of WaitForSingleObjectEx, fifth of
        // WaitForMultipleObjectsEx. Queued APCs run here, before any wait,
        // and the call answers WAIT_IO_COMPLETION.
        const alertable = if (std.mem.eql(u8, name, "WaitForSingleObjectEx"))
            (arg(state, 2, direct_return_rip) & 0xFFFF_FFFF) != 0
        else if (std.mem.eql(u8, name, "WaitForMultipleObjectsEx"))
            (arg(state, 4, direct_return_rip) & 0xFFFF_FFFF) != 0
        else
            false;
        {
            const AlertState = @TypeOf(state.*);
            if (comptime @hasDecl(AlertState, "beginWindowsApcDelivery")) {
                if (alertable and state.beginWindowsApcDelivery(direct_return_rip)) return true;
                state.setWindowsWaitAlertable(alertable);
            }
        }
        if (!is_multiple) {
            const wait_handle = arg(state, 0, direct_return_rip);
            const timeout = arg(state, 1, direct_return_rip);
            const State = @TypeOf(state.*);
            if (comptime @hasDecl(State, "waitWindowsGuestObject")) {
                switch (state.waitWindowsGuestObject(wait_handle, timeout)) {
                    // Parallel mode, the owner: slept for a slice of the
                    // wait; the same call asks again (a finite wait keeps
                    // its original deadline).
                    .blocked, .retry => return true,
                    .signaled => {
                        guestStateField(state, "regs").*.rax = 0; // WAIT_OBJECT_0
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .yielded => {
                        // The owner context is the cooperative UI executor.
                        // A bounded worker turn has already been serviced.
                        // The object is still not signalled, so this must not
                        // answer WAIT_OBJECT_0: a caller joining a thread or
                        // waiting before it frees shared state would go on as
                        // if the other side were done. An infinite wait stays
                        // at its call site and is retried after the owner
                        // loop pumps its UI work; a finite one times out.
                        if ((timeout & 0xFFFF_FFFF) == 0xFFFF_FFFF) return true;
                        guestStateField(state, "regs").*.rax = 0x102; // WAIT_TIMEOUT
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .timeout => {
                        guestStateField(state, "regs").*.rax = 0x102; // WAIT_TIMEOUT
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .invalid => {
                        guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
                        guestStateField(state, "regs").*.rax = std.math.maxInt(u64); // WAIT_FAILED
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .unknown => {
                        if (comptime @hasDecl(State, "faultWindowsWaitUnknownHandle")) state.faultWindowsWaitUnknownHandle(wait_handle, name);
                    },
                }
            }
        }
        if (is_multiple) {
            // `WaitForMultipleObjects(count, handles, wait_all, timeout)`.
            //
            // This used to fall through to the boundary below and answer
            // WAIT_OBJECT_0 at once. winpthreads waits on a semaphore and the
            // thread's cancel event together, so every timed condition wait
            // in a std::thread returned immediately and spun: Discord RPC's
            // 500 ms I/O poll held a fifth of the 2026-09-13 run, and the
            // semaphore it "acquired" was never decremented.
            const MultiState = @TypeOf(state.*);
            if (comptime @hasDecl(MultiState, "waitWindowsGuestObjects")) {
                const count = arg(state, 0, direct_return_rip) & 0xFFFF_FFFF;
                const handles_address = arg(state, 1, direct_return_rip);
                const wait_all = (arg(state, 2, direct_return_rip) & 0xFFFF_FFFF) != 0;
                const timeout = arg(state, 3, direct_return_rip) & 0xFFFF_FFFF;
                const handle_bytes: ?[]const u8 = if (count == 0 or count > 64) null else state.guestMemoryConst(handles_address, count * 8);
                const bytes = handle_bytes orelse {
                    guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
                    guestStateField(state, "regs").*.rax = 0xFFFF_FFFF; // WAIT_FAILED
                    finish(state, direct_return_rip);
                    return true;
                };
                var handles: [64]u64 = undefined;
                const handle_count: usize = @intCast(count);
                _ = bytes;
                for (0..handle_count) |index| handles[index] = state.read64(handles_address +| @as(u64, @intCast(index * 8)));
                switch (state.waitWindowsGuestObjects(handles[0..handle_count], wait_all, timeout)) {
                    // `.retry`: parallel mode, the owner slept for a slice
                    // and asks again from the same call.
                    .blocked, .retry => return true,
                    .signaled => |index| {
                        guestStateField(state, "regs").*.rax = index; // WAIT_OBJECT_0 + index
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .timeout => {
                        guestStateField(state, "regs").*.rax = 0x102; // WAIT_TIMEOUT
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .invalid => {
                        guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
                        guestStateField(state, "regs").*.rax = 0xFFFF_FFFF; // WAIT_FAILED
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .yielded => {
                        // The owner is the cooperative UI executor and cannot
                        // park; this is the single-object owner rule, and like
                        // it never claims an object that was not signalled.
                        if (timeout == 0xFFFF_FFFF) return true;
                        guestStateField(state, "regs").*.rax = 0x102; // WAIT_TIMEOUT
                        finish(state, direct_return_rip);
                        return true;
                    },
                    .unknown => |unknown_handle| {
                        if (comptime @hasDecl(MultiState, "faultWindowsWaitUnknownHandle")) state.faultWindowsWaitUnknownHandle(unknown_handle, name);
                    },
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
        guestStateField(state, "regs").*.rax = 0; // WAIT_OBJECT_0 for the deterministic bootstrap handle
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "pthread_cond_wait") or std.mem.eql(u8, name, "pthread_cond_timedwait")) {
        const condition = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "waitWindowsGuestCondition")) {
            switch (state.waitWindowsGuestCondition(condition, arg(state, 1, direct_return_rip))) {
                .blocked => return true,
                .resumed, .invalid, .relock => {},
            }
        }
        // The ordinary fallback remains a successful no-op only for states
        // without the cooperative PE scheduler.  In a PE run, a worker that
        // reaches this branch must be resumed by signal/broadcast rather than
        // being allowed to consume a condition-variable sentinel.
        guestStateField(state, "regs").*.rax = 0;
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
        if (lendXeniaGlobalLockForBackoff(state)) return true;
        const State = @TypeOf(state.*);
        const is_sleep = std.mem.eql(u8, name, "Sleep") or std.mem.eql(u8, name, "SleepEx");
        const milliseconds: u64 = if (is_sleep) arg(state, 0, direct_return_rip) else 0;
        const alertable_sleep = std.mem.eql(u8, name, "SleepEx") and (arg(state, 1, direct_return_rip) & 0xFFFF_FFFF) != 0;
        if (comptime @hasDecl(State, "beginWindowsApcDelivery")) {
            // SleepEx(ms, TRUE) runs queued APCs instead of sleeping and
            // answers WAIT_IO_COMPLETION.
            if (alertable_sleep and state.beginWindowsApcDelivery(direct_return_rip)) return true;
            state.setWindowsWaitAlertable(alertable_sleep);
        }
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
                    // The owner has no worker slot to park. In parallel mode
                    // it sleeps for the interval like any host thread; the
                    // cooperative owner gives the workers the interval
                    // instead of spinning through it.
                    const slept = if (comptime @hasDecl(State, "sleepForGuestWait"))
                        state.sleepForGuestWait(milliseconds)
                    else
                        false;
                    if (!slept) {
                        if (comptime @hasDecl(State, "serviceWindowsGuestThreads")) {
                            _ = state.serviceWindowsGuestThreads(state.windowsGuestWaitServiceSlice());
                        }
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
            guestStateField(state, "regs").*.rax = 0xFFFF_FFFF;
            guestStateField(state, "windows_last_error").* = 8; // ERROR_NOT_ENOUGH_MEMORY
        } else {
            guestStateField(state, "regs").*.rax = state.windows_next_tls;
            state.windows_next_tls +|= 1;
            guestStateField(state, "windows_last_error").* = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TlsGetValue") or std.mem.eql(u8, name, "FlsGetValue")) {
        const slot = windowsTlsSlot(state, arg(state, 0, direct_return_rip));
        guestStateField(state, "regs").*.rax = if (slot) |address| state.read64(address) else 0;
        if (slot == null) guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TlsSetValue") or std.mem.eql(u8, name, "FlsSetValue")) {
        const slot = windowsTlsSlot(state, arg(state, 0, direct_return_rip));
        if (slot) |address| {
            state.write64(address, arg(state, 1, direct_return_rip));
            guestStateField(state, "regs").*.rax = 1;
            guestStateField(state, "windows_last_error").* = 0;
        } else {
            guestStateField(state, "regs").*.rax = 0;
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TlsFree") or std.mem.eql(u8, name, "FlsFree")) {
        const slot = windowsTlsSlot(state, arg(state, 0, direct_return_rip));
        if (slot) |address| {
            state.write64(address, 0);
            guestStateField(state, "regs").*.rax = 1;
            guestStateField(state, "windows_last_error").* = 0;
        } else {
            guestStateField(state, "regs").*.rax = 0;
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
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
            state.postWindowsMessage(hwnd, message, wparam, lparam, direct_return_rip orelse 0)
        else
            false;
        const valid_window = if (comptime @hasDecl(State, "isWindowsWindowHandle"))
            state.isWindowsWindowHandle(hwnd)
        else
            false;
        guestStateField(state, "regs").*.rax = @intFromBool(posted);
        guestStateField(state, "windows_last_error").* = if (posted) 0 else if (hwnd == 0 or !valid_window) 1400 else 8;
        if (state.diagnose_abi or state.trace_windows_messages) {
            const queued = if (comptime @hasDecl(State, "windowsMessageCount")) state.windowsMessageCount() else 0;
            log.info("Windows PostMessage: api={s} hwnd=0x{x} message=0x{x} wparam=0x{x} lparam=0x{x} posted={} queue={d}", .{
                name,
                hwnd,
                message,
                wparam,
                lparam,
                posted,
                queued,
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
        guestStateField(state, "regs").*.rax = atom;
        guestStateField(state, "windows_last_error").* = if (atom != 0) 0 else 87; // ERROR_INVALID_PARAMETER
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
        guestStateField(state, "regs").*.rax = 1;
        guestStateField(state, "windows_last_error").* = 0;
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
            guestStateField(state, "windows_last_error").* = if (created) 0 else 8; // ERROR_NOT_ENOUGH_MEMORY
            guestStateField(state, "regs").*.rax = if (created) message_window else 0;
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
        guestStateField(state, "regs").*.rax = if (window_ok) window_handle else 0;
        guestStateField(state, "windows_last_error").* = if (window_ok) 0 else if (!ok) 1400 else 8;
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
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ShowWindow")) {
        const ok = state.windows_graphics.showWindow();
        guestStateField(state, "regs").*.rax = if (ok) 1 else 0;
        if (ok) _ = state.windows_graphics.pumpEvents();
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "MessageBoxA") or std.mem.eql(u8, name, "MessageBoxW")) {
        // Rosetta is headless during bring-up. Returning IDOK preserves the
        // modal API's nonzero decision without blocking the cooperative
        // executor on an AppKit alert that cannot be observed by the guest.
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 1; // IDOK
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
        guestStateField(state, "regs").*.rax = value orelse 0;
        guestStateField(state, "windows_last_error").* = if (value == null) 1400 else 0; // ERROR_INVALID_WINDOW_HANDLE
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
        guestStateField(state, "regs").*.rax = previous orelse 0;
        guestStateField(state, "windows_last_error").* = if (previous == null) 1400 else 0; // ERROR_INVALID_WINDOW_HANDLE
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
        guestStateField(state, "regs").*.rax = @intFromBool(destroyed);
        guestStateField(state, "windows_last_error").* = if (destroyed) 0 else 1400;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetFocus")) {
        guestStateField(state, "regs").*.rax = state.windows_focus_window;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetFocus")) {
        const previous = state.windows_focus_window;
        state.windows_focus_window = arg(state, 0, direct_return_rip);
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = previous;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetWindowPos") or std.mem.eql(u8, name, "ReleaseDC")) {
        guestStateField(state, "regs").*.rax = 1;
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
        guestStateField(state, "regs").*.rax = 1;
        guestStateField(state, "windows_last_error").* = if (accepted or !invalidating) 0 else 1400; // ERROR_INVALID_WINDOW_HANDLE
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
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ValidateRect") or std.mem.eql(u8, name, "ValidateRgn")) {
        const hwnd = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "validateWindowsWindow")) _ = state.validateWindowsWindow(hwnd);
        guestStateField(state, "regs").*.rax = 1;
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
        guestStateField(state, "regs").*.rax = hdc;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "EndPaint")) {
        guestStateField(state, "regs").*.rax = 1;
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
        guestStateField(state, "regs").*.rax = @intFromBool(pending);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetDC")) {
        guestStateField(state, "regs").*.rax = nextHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "PeekMessageA") or std.mem.eql(u8, name, "PeekMessageW") or
        std.mem.eql(u8, name, "GetMessageA") or std.mem.eql(u8, name, "GetMessageW"))
    {
        const is_get_message = std.mem.eql(u8, name, "GetMessageA") or std.mem.eql(u8, name, "GetMessageW");
        const message = arg(state, 0, direct_return_rip);
        if (message == 0 or !clearGuestMemory(state, message, 48)) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = if (is_get_message) std.math.maxInt(u64) else 0;
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
        // A real GetMessage blocks until something is deliverable. The stride
        // gate above declines most calls, so with nothing queued the owner's
        // loop returned WM_NULL after ~93 guest instructions and came back:
        // 20.9 million TranslateMessage calls and 17% of the 2026-09-13 run
        // spent asking. Serve workers here instead, and stop the moment a
        // message, a paint or a quit exists or nothing is runnable.
        if (is_get_message and comptime (@hasDecl(State, "serviceWindowsGuestThreads") and
            @hasDecl(State, "windowsPendingPaintCount") and @hasDecl(State, "noteGetMessageIdleTurn") and
            @hasDecl(State, "windowsMessageCount")))
        {
            var round: u32 = 0;
            while (round < windows_get_message_idle_rounds and !state.terminated and
                state.windowsMessageCount() == 0 and !state.windows_ui_quit_requested and
                state.windowsPendingPaintCount() == 0) : (round += 1)
            {
                const turn = state.serviceWindowsGuestThreads(state.windowsGuestWaitServiceSlice());
                if (turn == 0) break;
                serviced_steps +|= turn;
                state.noteGetMessageIdleTurn(turn);
            }
        }
        // With guest threads on their own host threads nothing needs this
        // call to return early: block until something is deliverable, as a
        // real GetMessage does, instead of handing the loop a WM_NULL to spin
        // on. The state decides; the cooperative executor never blocks.
        if (is_get_message and comptime @hasDecl(State, "waitForWindowsMessage")) {
            _ = state.waitForWindowsMessage(filter_hwnd, minimum_message, maximum_message);
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
                guestStateField(state, "windows_last_error").* = 87;
                guestStateField(state, "regs").*.rax = if (is_get_message) std.math.maxInt(u64) else 0;
                finish(state, direct_return_rip);
                return true;
            }
            result = if (is_get_message and queued.hwnd == 0 and queued.message == 0) 0 else 1;
            if (state.diagnose_abi or state.trace_windows_messages) {
                const remaining = if (comptime @hasDecl(State, "windowsMessageCount")) state.windowsMessageCount() else 0;
                log.info("Windows message pump dequeued: api={s} hwnd=0x{x} message=0x{x} wparam=0x{x} lparam=0x{x} result={d} remove={} remaining={d} serviced_steps={d}", .{
                    name,
                    queued.hwnd,
                    queued.message,
                    queued.wparam,
                    queued.lparam,
                    result,
                    remove,
                    remaining,
                    serviced_steps,
                });
            }
        } else if (state.windows_ui_quit_requested) {
            const quit_message = .{ .hwnd = @as(u64, 0), .message = @as(u32, 0), .wparam = state.windows_ui_quit_code, .lparam = @as(u64, 0) };
            if (!writeWindowsMessage(state, message, quit_message)) {
                guestStateField(state, "windows_last_error").* = 87;
                guestStateField(state, "regs").*.rax = if (is_get_message) std.math.maxInt(u64) else 0;
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
                guestStateField(state, "windows_last_error").* = 87;
                guestStateField(state, "regs").*.rax = if (is_get_message) std.math.maxInt(u64) else 0;
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
                guestStateField(state, "windows_last_error").* = 87;
                guestStateField(state, "regs").*.rax = std.math.maxInt(u64);
                finish(state, direct_return_rip);
                return true;
            }
            result = 1;
            const deliveries = if (comptime @hasDecl(State, "windowsMessageDeliveryCount")) state.windowsMessageDeliveryCount() else 0;
            if ((state.diagnose_abi or state.trace_windows_messages) and deliveries < 8) {
                log.info("Windows message pump idle synthetic WM_NULL serviced_steps={d} thread_calls={d} yields={d} completions={d}", .{ serviced_steps, state.windows_thread_service_calls, state.windows_thread_yields, state.windows_thread_completions });
            }
        }
        guestStateField(state, "regs").*.rax = result;
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
        guestStateField(state, "regs").*.rax = if (arg(state, 0, direct_return_rip) == 0) 1280 else if (arg(state, 0, direct_return_rip) == 1) 720 else 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetDpiForWindow")) {
        guestStateField(state, "regs").*.rax = 96;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetDpiForSystem")) {
        guestStateField(state, "regs").*.rax = 96;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "AdjustWindowRectEx") or std.mem.eql(u8, name, "AdjustWindowRectExForDpi")) {
        const rect = arg(state, 0, direct_return_rip);
        if (rect == 0 or state.guestMemory(rect, 16) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            // The exact non-client metrics are host-policy data. Keep the
            // caller's requested client rectangle intact while proving that
            // the Win32 sizing contract itself was crossed.
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "EnableNonClientDpiScaling")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetMonitorInfoA") or std.mem.eql(u8, name, "GetMonitorInfoW")) {
        const information = arg(state, 1, direct_return_rip);
        if (information == 0 or state.guestMemory(information, 40) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
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
            guestStateField(state, "regs").*.rax = 1;
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
        guestStateField(state, "regs").*.rax = primaryMonitorHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetWindowPlacement")) {
        const placement = arg(state, 1, direct_return_rip);
        if (placement == 0 or state.guestMemory(placement, 44) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
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
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetWindowPlacement")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetDeviceCaps")) {
        guestStateField(state, "regs").*.rax = switch (arg(state, 1, direct_return_rip)) {
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
            guestStateField(state, "regs").*.rax = 0;
        } else {
            const processors = guestSystemAffinityMask(state);
            state.write16(info + 0, 9); // PROCESSOR_ARCHITECTURE_AMD64
            state.write16(info + 2, 0);
            state.write32(info + 4, 4096); // dwPageSize
            state.write64(info + 8, 0x10000);
            state.write64(info + 16, 0x0000_7FFF_FFFF_F000);
            state.write64(info + 24, processors); // active processor mask
            state.write32(info + 32, @popCount(processors)); // number of processors
            state.write32(info + 36, 8664); // PROCESSOR_INTEL_PENTIUM4-compatible
            state.write32(info + 40, 0x10000); // allocation granularity
            state.write16(info + 44, 6);
            state.write16(info + 46, 0);
            guestStateField(state, "regs").*.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetClassLongPtrW")) {
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetWindowTextA") or std.mem.eql(u8, name, "SetWindowTextW")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCapture")) {
        guestStateField(state, "regs").*.rax = state.windows_window_handle;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetCapture")) {
        guestStateField(state, "regs").*.rax = state.windows_window_handle;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ReleaseCapture")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetCursorPos")) {
        const point = arg(state, 0, direct_return_rip);
        if (point == 0 or state.guestMemory(point, 8) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            state.write32(point + 0, 0);
            state.write32(point + 4, 0);
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "ScreenToClient") or std.mem.eql(u8, name, "ClientToScreen")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetKeyState")) {
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "VkKeyScanW")) {
        guestStateField(state, "regs").*.rax = 0xFFFF;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "WindowFromPoint")) {
        guestStateField(state, "regs").*.rax = state.windows_window_handle;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "LoadCursorA") or std.mem.eql(u8, name, "LoadCursorW") or
        std.mem.eql(u8, name, "LoadIconA") or std.mem.eql(u8, name, "LoadIconW") or
        std.mem.eql(u8, name, "GetStockObject") or std.mem.eql(u8, name, "CreateIconFromResourceEx"))
    {
        guestStateField(state, "regs").*.rax = nextHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DestroyIcon") or std.mem.eql(u8, name, "SetCursor")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetPropA") or std.mem.eql(u8, name, "SetPropW")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetPropA") or std.mem.eql(u8, name, "GetPropW")) {
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RemovePropA") or std.mem.eql(u8, name, "RemovePropW")) {
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RegisterDeviceNotificationA") or std.mem.eql(u8, name, "RegisterDeviceNotificationW")) {
        guestStateField(state, "regs").*.rax = nextHandle(state);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "UnregisterDeviceNotification")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateTimerQueueTimer")) {
        const timer = arg(state, 0, direct_return_rip);
        const handle = nextHandle(state);
        if (timer != 0) state.write64(timer, handle);
        guestStateField(state, "regs").*.rax = if (timer != 0) 1 else 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DeleteTimerQueueTimer")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateMenu") or std.mem.eql(u8, name, "CreatePopupMenu")) {
        guestStateField(state, "regs").*.rax = nextHandle(state);
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
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DragQueryFileW")) {
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GlobalAddAtomW")) {
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GlobalDeleteAtom")) {
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }

    if (std.mem.eql(u8, name, "QueryPerformanceCounter")) {
        const output = arg(state, 0, direct_return_rip);
        if (output != 0) state.write64(output, windowsGuestClockTicks(state));
        guestStateField(state, "regs").*.rax = 1;
        noteGuestClockRead(state);
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
        guestStateField(state, "regs").*.rax = 1;
        noteGuestClockRead(state);
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
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetTickCount") or std.mem.eql(u8, name, "GetTickCount64")) {
        guestStateField(state, "regs").*.rax = windowsGuestClockTicks(state) / 1000;
        noteGuestClockRead(state);
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
        guestStateField(state, "regs").*.rax = 0;
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
                guestStateField(state, "regs").*.rsp,
                state.read64(guestStateField(state, "regs").*.rsp),
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
            if (std.mem.indexOf(u8, type_name, "invalid_utf8") != null) {
                const byte: u8 = @truncate(payload0);
                log.err("Windows C++ UTF-8 exception payload: invalid_octet=0x{x} classification={s}; check the PE64 XENIA UTF-8 INPUT record for the exact view and caller", .{
                    byte,
                    if (byte >= 0x80 and byte <= 0xbf) "standalone continuation byte" else "invalid lead or sequence byte",
                });
            }
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
            guestStateField(state, "regs").*.rax = 0x8000_4003; // E_POINTER
        } else {
            if (state.windows_com_mta_cookie == 0) state.windows_com_mta_cookie = nextHandle(state);
            state.windows_com_mta_refcount +|= 1;
            state.write64(output, state.windows_com_mta_cookie);
            guestStateField(state, "regs").*.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CoDecrementMTAUsage")) {
        const cookie = arg(state, 0, direct_return_rip);
        if (cookie == 0 or cookie != state.windows_com_mta_cookie or state.windows_com_mta_refcount == 0) {
            guestStateField(state, "regs").*.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            state.windows_com_mta_refcount -= 1;
            guestStateField(state, "regs").*.rax = 0; // S_OK
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
        guestStateField(state, "regs").*.rax = 0x8000_4002; // E_NOINTERFACE
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
            guestStateField(state, "regs").*.rax = 0x8000_4003; // E_POINTER
        } else {
            _ = clearGuestMemory(state, output, 16);
            guestStateField(state, "regs").*.rax = 0x8004_0170; // CO_E_CLASSSTRING
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
            guestStateField(state, "regs").*.rax = 0x8000_4003; // E_POINTER
        } else {
            guestStateField(state, "regs").*.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "RoInitialize")) {
        // The PE path has no WinRT apartment object to publish, but a
        // successful initialization is the documented non-error result and
        // is enough for callers that only probe optional WinRT services.
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 0; // S_OK
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
        guestStateField(state, "regs").*.rax = 0x8000_4002; // E_NOINTERFACE
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CreateDXGIFactory1") or std.mem.eql(u8, name, "CreateDXGIFactory2")) {
        return handleDxgiFactory(state, name, direct_return_rip);
    }
    if (std.mem.eql(u8, name, "HidD_GetHidGuid")) {
        const output = arg(state, 0, direct_return_rip);
        if (output == 0 or state.guestMemory(output, 16) == null) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            // GUID_DEVINTERFACE_HID, serialized in Windows GUID byte order.
            const hid_guid = [_]u8{ 0xB2, 0x55, 0x1E, 0x4D, 0x6F, 0xF1, 0xCF, 0x11, 0x88, 0xCB, 0x00, 0x11, 0x11, 0x00, 0x00, 0x30 };
            _ = copyGuestBytes(state, output, hid_guid[0..]);
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    // The process-exit family. The CRT owns callback sequencing, so normal
    // exit and quick_exit drain their guest tables while _exit/_Exit skip
    // cleanup. ExitProcess and TerminateProcess are kernel-level exits and
    // never run CRT callbacks. All of these are emulated guest termination
    // or return paths; none is allowed to call the host process exit routine.
    if (std.mem.eql(u8, name, "ExitProcess") or
        std.mem.eql(u8, name, "exit") or
        std.mem.eql(u8, name, "_exit") or
        std.mem.eql(u8, name, "_Exit") or
        std.mem.eql(u8, name, "quick_exit") or
        std.mem.eql(u8, name, "_cexit") or
        std.mem.eql(u8, name, "_c_exit"))
    {
        const is_cexit = std.mem.eql(u8, name, "_cexit");
        const is_c_exit = std.mem.eql(u8, name, "_c_exit");
        const is_quick_exit = std.mem.eql(u8, name, "quick_exit");
        const code = if (is_cexit or is_c_exit) 0 else arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "beginWindowsCrtExit")) {
            return state.beginWindowsCrtExit(
                code,
                is_quick_exit,
                !is_c_exit and !std.mem.eql(u8, name, "ExitProcess") and
                    !std.mem.eql(u8, name, "_exit") and
                    !std.mem.eql(u8, name, "_Exit"),
                is_cexit or is_c_exit,
                direct_return_rip,
            );
        }
        state.exit_code = code;
        state.terminated = !is_cexit and !is_c_exit;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "TerminateProcess")) {
        // (handle, exit_code). A guest terminating a handle that is not its
        // own process is not modelled; Rosetta hosts one process.
        const code = arg(state, 1, direct_return_rip);
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "beginWindowsCrtExit")) {
            return state.beginWindowsCrtExit(code, false, false, false, direct_return_rip);
        }
        state.exit_code = code;
        state.terminated = true;
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
            guestStateField(state, "regs").*.rax = arg(state, 1, direct_return_rip);
            finish(state, direct_return_rip);
            return true;
        }
        if (std.mem.startsWith(u8, name, "CM_Locate_DevNode")) {
            // Nothing to locate. Clear the out-parameter first: a caller that
            // ignores the CONFIGRET must not read a devinst off its stack.
            const devinst = arg(state, 0, direct_return_rip);
            if (devinst != 0 and state.guestMemory(devinst, 4) != null) state.write32(devinst, 0);
            guestStateField(state, "regs").*.rax = cr_no_such_devnode;
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
            guestStateField(state, "regs").*.rax = cr_success;
            finish(state, direct_return_rip);
            return true;
        }
        if (std.mem.startsWith(u8, name, "CM_Register_Notification")) {
            const handle_out = arg(state, 3, direct_return_rip);
            if (handle_out != 0 and state.guestMemory(handle_out, 8) != null) state.write64(handle_out, 0);
            guestStateField(state, "regs").*.rax = cr_failure;
            finish(state, direct_return_rip);
            return true;
        }
        if (std.mem.eql(u8, name, "CM_Unregister_Notification")) {
            guestStateField(state, "regs").*.rax = cr_success;
            finish(state, direct_return_rip);
            return true;
        }
        // Everything else takes a devinst Rosetta never issued.
        guestStateField(state, "regs").*.rax = cr_no_such_devinst;
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
        guestStateField(state, "windows_last_error").* = if (frees) 0 else 6; // ERROR_INVALID_HANDLE
        guestStateField(state, "regs").*.rax = if (frees) 1 else 0;
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
        guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "HidP_MaxDataListLength") or
        std.mem.eql(u8, name, "HidP_MaxUsageListLength"))
    {
        // ULONG count, and zero is the honest one: a report with no
        // preparsed data has no data items in it.
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.startsWith(u8, name, "HidP_")) {
        // NTSTATUS, where zero is HIDP_STATUS_SUCCESS. Returning it would
        // tell the caller a capability structure had been filled in.
        guestStateField(state, "regs").*.rax = 0xC011_0001; // HIDP_STATUS_INVALID_PREPARSED_DATA
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
            guestStateField(state, "regs").*.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            state.write32(dpi_x, 96);
            state.write32(dpi_y, 96);
            guestStateField(state, "regs").*.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetScaleFactorForMonitor")) {
        const scale = arg(state, 1, direct_return_rip);
        if (scale == 0 or state.guestMemory(scale, 4) == null) {
            guestStateField(state, "regs").*.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            state.write32(scale, 100); // SCALE_100_PERCENT
            guestStateField(state, "regs").*.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetProcessDpiAwareness")) {
        // A guest that sets awareness and reads it back must see what it
        // set, so the value is retained rather than acknowledged and lost.
        state.windows_process_dpi_awareness = @truncate(arg(state, 0, direct_return_rip));
        guestStateField(state, "regs").*.rax = 0; // S_OK
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetProcessDpiAwareness")) {
        const awareness = arg(state, 1, direct_return_rip);
        if (awareness == 0 or state.guestMemory(awareness, 4) == null) {
            guestStateField(state, "regs").*.rax = 0x8007_0057; // E_INVALIDARG
        } else {
            state.write32(awareness, state.windows_process_dpi_awareness);
            guestStateField(state, "regs").*.rax = 0; // S_OK
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "GetRawInputDeviceList")) {
        const devices = arg(state, 0, direct_return_rip);
        const count = arg(state, 1, direct_return_rip);
        const element_size = arg(state, 2, direct_return_rip);
        if (count == 0 or state.guestMemory(count, 4) == null or (element_size != 0 and element_size < 16)) {
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = std.math.maxInt(u32);
        } else {
            state.write32(count, 0);
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 0;
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
            guestStateField(state, "windows_last_error").* = 87; // ERROR_INVALID_PARAMETER
            guestStateField(state, "regs").*.rax = 0;
        } else {
            state.windows_raw_input_registered = count != 0;
            state.windows_raw_input_device_count = @truncate(count);
            guestStateField(state, "windows_last_error").* = 0;
            guestStateField(state, "regs").*.rax = 1;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetupDiGetClassDevsA") or std.mem.eql(u8, name, "SetupDiGetClassDevsW")) {
        // Device enumeration is optional for the Vulkan path. Return the
        // documented invalid set handle and a specific absence error instead
        // of a generic FALSE, so Xenia can take its no-device branch without
        // treating the setup API itself as an unresolved import.
        guestStateField(state, "windows_last_error").* = 433; // ERROR_NO_SUCH_DEVICE
        guestStateField(state, "regs").*.rax = std.math.maxInt(u64); // INVALID_HANDLE_VALUE
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetupDiEnumDeviceInterfaces")) {
        guestStateField(state, "windows_last_error").* = 259; // ERROR_NO_MORE_ITEMS
        guestStateField(state, "regs").*.rax = 0;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "SetupDiDestroyDeviceInfoList")) {
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 1;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "OpenSCManagerA") or std.mem.eql(u8, name, "OpenSCManagerW") or
        std.mem.eql(u8, name, "OpenServiceA") or std.mem.eql(u8, name, "OpenServiceW"))
    {
        // Rosetta does not expose the host service-control database to the
        // guest. Report the ordinary Windows "service does not exist" result
        // instead of claiming success with a null service handle.
        guestStateField(state, "windows_last_error").* = 1060; // ERROR_SERVICE_DOES_NOT_EXIST
        returnZero(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "CloseServiceHandle")) {
        guestStateField(state, "windows_last_error").* = 0;
        guestStateField(state, "regs").*.rax = 1;
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
            guestStateField(state, "regs").*.rax = nt_status_invalid_parameter;
            finish(state, direct_return_rip);
            return true;
        };
        return finishNtWait(state, direct_return_rip, wait_handle, timeout);
    }
    if (std.mem.eql(u8, name, "NtSetEventBoostPriority")) {
        // Xenia's Windows command processor calls Event::SetBoostPriority
        // immediately after publishing the GPU ring write pointer. This NT
        // entry point has one argument and no previous-state output pointer;
        // letting it reach the generic prefix fallback returns success while
        // leaving the synthetic auto-reset event unsignaled, which parks the
        // GPU worker before ExecutePrimaryBuffer forever.
        const handle = arg(state, 0, direct_return_rip);
        const State = @TypeOf(state.*);
        const known = if (comptime @hasDecl(State, "windowsWaitObjectKnown"))
            state.windowsWaitObjectKnown(handle)
        else
            false;
        if (known) {
            _ = state.signalWindowsWaitObject(handle, false);
            guestStateField(state, "regs").*.rax = nt_status_success;
        } else {
            guestStateField(state, "regs").*.rax = nt_status_invalid_handle;
        }
        traceNtSynchronization(state, name, handle, known, guestStateField(state, "regs").*.rax);
        finish(state, direct_return_rip);
        return true;
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
            guestStateField(state, "regs").*.rax = nt_status_invalid_handle;
        } else if (std.mem.eql(u8, name, "NtClearEvent")) {
            _ = state.resetWindowsWaitObject(handle);
            guestStateField(state, "regs").*.rax = nt_status_success;
        } else {
            _ = state.signalWindowsWaitObject(handle, std.mem.eql(u8, name, "NtPulseEvent"));
            guestStateField(state, "regs").*.rax = nt_status_success;
        }
        traceNtSynchronization(state, name, handle, known, guestStateField(state, "regs").*.rax);
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
            guestStateField(state, "regs").*.rax = nt_status_success;
        } else {
            guestStateField(state, "regs").*.rax = if (release_count == 0) nt_status_invalid_parameter else nt_status_invalid_handle;
        }
        traceNtSynchronization(state, name, handle, released, guestStateField(state, "regs").*.rax);
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
            guestStateField(state, "regs").*.rax = nt_status_success;
        } else {
            guestStateField(state, "regs").*.rax = nt_status_invalid_handle;
        }
        traceNtSynchronization(state, name, handle, known, guestStateField(state, "regs").*.rax);
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "NtDelayExecution") or std.mem.eql(u8, name, "NtYieldExecution")) {
        if (lendXeniaGlobalLockForBackoff(state)) return true;
        // Xenia's `NanoSleep` is NtDelayExecution, and its GPU frame limiter
        // sleeps 90% of every vblank through it. Answering by returning made
        // that thread spin through every interval instead: 24% of the
        // 2026-09-14 run. A zero interval, and NtYieldExecution, are yields.
        const ticks: u64 = if (std.mem.eql(u8, name, "NtDelayExecution"))
            ntDelayTicks(state, arg(state, 1, direct_return_rip))
        else
            0;
        // Return first: a parked worker resumes after the call.
        returnZero(state, direct_return_rip); // STATUS_SUCCESS
        const State = @TypeOf(state.*);
        if (comptime @hasDecl(State, "parkWindowsGuestDelayTicks")) {
            if (!state.parkWindowsGuestDelayTicks(ticks) and ticks != 0) {
                // The owner has no context to park; give the workers the
                // interval instead of spinning through it.
                if (comptime @hasDecl(State, "serviceWindowsGuestThreads")) {
                    _ = state.serviceWindowsGuestThreads(state.windowsGuestWaitServiceSlice());
                }
            }
        }
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
            guestStateField(state, "regs").*.rax = if (materialized == 0) 0 else message.len;
        } else if (wide) {
            guestStateField(state, "regs").*.rax = copyGuestWideString(state, output, capacity, message);
        } else {
            guestStateField(state, "regs").*.rax = copyGuestString(state, output, capacity, message);
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
        guestStateField(state, "regs").*.rax = if (closeWindowsFile(state, handle)) 0 else std.math.maxInt(u32); // CRT EOF on failure
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
            guestStateField(state, "regs").*.rax = 1;
        } else |_| {
            failWindowsFileCall(state, direct_return_rip, 1117); // ERROR_IO_DEVICE
            return true;
        }
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "DeleteFileA") or std.mem.eql(u8, name, "DeleteFileW")) {
        return deleteWindowsFile(state, name, direct_return_rip);
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
            guestStateField(state, "regs").*.rax = 1;
        } else {
            guestStateField(state, "windows_last_error").* = 6; // ERROR_INVALID_HANDLE
            guestStateField(state, "regs").*.rax = 0;
        }
        finish(state, direct_return_rip);
        return true;
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
            terminateWindowsCall(state, .guest_abort, 127, name);
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
        terminateWindowsCall(state, .guest_abort, 134, name);
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
        guestStateField(state, "regs").*.rax = value;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InterlockedExchange") or std.mem.eql(u8, name, "InterlockedExchange64")) {
        const address = arg(state, 0, direct_return_rip);
        const old = state.read64(address);
        if (std.mem.eql(u8, name, "InterlockedExchange")) state.write32(address, @truncate(arg(state, 1, direct_return_rip))) else state.write64(address, arg(state, 1, direct_return_rip));
        guestStateField(state, "regs").*.rax = old;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InterlockedCompareExchange") or std.mem.eql(u8, name, "InterlockedCompareExchange64")) {
        const address = arg(state, 0, direct_return_rip);
        const old = state.read64(address);
        if (old == arg(state, 2, direct_return_rip)) {
            if (std.mem.eql(u8, name, "InterlockedCompareExchange")) state.write32(address, @truncate(arg(state, 1, direct_return_rip))) else state.write64(address, arg(state, 1, direct_return_rip));
        }
        guestStateField(state, "regs").*.rax = old;
        finish(state, direct_return_rip);
        return true;
    }
    if (std.mem.eql(u8, name, "InterlockedOr") or std.mem.eql(u8, name, "InterlockedAnd") or std.mem.eql(u8, name, "InterlockedXor")) {
        const address = arg(state, 0, direct_return_rip);
        const old = state.read32(address);
        const operand: u32 = @truncate(arg(state, 1, direct_return_rip));
        const value = if (std.mem.eql(u8, name, "InterlockedOr")) old | operand else if (std.mem.eql(u8, name, "InterlockedAnd")) old & operand else old ^ operand;
        state.write32(address, value);
        guestStateField(state, "regs").*.rax = old;
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
    const traits = importTraits(dll_name, name);
    if (traits.core or traits.contract) {
        completeWithImportFallback(state, dll_name, name, direct_return_rip);
        return true;
    }

    return false;
}
