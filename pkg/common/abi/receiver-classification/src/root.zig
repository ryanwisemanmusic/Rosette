//! Route-independent: does a near-null RDI at an x86-64 call boundary mean
//! anything?
//!
//! Under the SysV x86-64 ABI the first integer or pointer argument arrives in
//! RDI, and for a C++ non-static member function that argument is `this`. That
//! single overload is what makes "RDI is small" a useful fault signal *and*
//! what makes it a liar: the register is equally the home of a file descriptor,
//! an allocation size, a signal number, a clock id, a `VkQueueFlags` mask, and —
//! for a function that takes no arguments at all — whatever the previous call
//! happened to leave behind.
//!
//! Deciding which of those a symbol carries is not a runtime question. It is
//! fixed by the callee's declared C or C++ signature, which was settled when
//! the host libraries were compiled and cannot change while a process runs.
//! Rosette used to answer it by walking two inline string tables on the
//! import-dispatch path; this package is the same answer resolved at build
//! time, with the classes named rather than collapsed into one boolean.
//!
//! ## Why `common/` and not a route
//!
//! Every other package under `pkg/` is mirrored per host route, because it
//! describes something about the machine Rosette was compiled for. This one
//! describes the **guest** ABI. The guest is x86-64 whether Rosette runs on
//! arm64 or on x86-64, so a mirrored copy would be two files asserting the same
//! thing with no way for them to legitimately differ — which is precisely the
//! configuration that lets one copy rot unnoticed. One file, no route
//! selection, nothing to keep in sync.
//!
//! ## What this package is not
//!
//! * It is not a suppression list. A symbol here is not "ignore faults from
//!   this"; it is "RDI is not a receiver here, so a small value in it carries
//!   no information". A genuine fault inside such a callee still faults, and is
//!   still reported by every other mechanism.
//! * It never decides that a *real* receiver is acceptably null. `Class` has no
//!   member for that, deliberately.
//! * It says nothing about arguments beyond the first. Nothing in Rosette asks.

const std = @import("std");

/// The ABI this package describes. Named so a reader who arrives from a route
/// package does not have to guess whether "x86_64" here means the host.
pub const guest_abi = "sysv-x86_64";
pub const receiver_register = "rdi";

/// What the first integer/pointer argument register actually holds.
///
/// The three classes are ordered by how strong a dismissal they represent, and
/// they are kept apart rather than merged into one predicate because a reader
/// adding a symbol needs to know which question they are answering. Merged into
/// one bag, the failure mode is adding a real receiver because "the other
/// entries looked similar".
pub const Class = enum(u8) {
    /// A C++ non-static member function, or a free function whose first
    /// parameter is a pointer that is dereferenced. RDI is a receiver and a
    /// near-null value is a real finding. This is the default for everything
    /// this package does not name.
    receiver,
    /// The callee takes no arguments at all, so RDI is register-allocation
    /// garbage left by whatever ran before. This is the strongest dismissal
    /// available: not "null is legal here" but "there is no argument here".
    no_arguments,
    /// The first parameter is a small integer, size, file descriptor, clock id,
    /// signal number, or enum. It is never dereferenced, so no value in it can
    /// produce a near-null casualty.
    scalar_first_argument,
    /// The first parameter genuinely is a pointer, and null is the API's
    /// documented way to request a default rather than a mistake. Distinct from
    /// `scalar_first_argument` because the shape check cannot dismiss these —
    /// only the API contract can.
    nullable_pointer_first_argument,

    /// Whether a near-null RDI at a call to this symbol can predict a casualty.
    ///
    /// `receiver` is the only class that can, which is the whole point: the
    /// retained signatures stay receiver-shaped.
    pub fn predictsCasualty(self: Class) bool {
        return self == .receiver;
    }

    pub fn label(self: Class) []const u8 {
        return switch (self) {
            .receiver => "receiver",
            .no_arguments => "no-arguments",
            .scalar_first_argument => "scalar-first-argument",
            .nullable_pointer_first_argument => "nullable-pointer-first-argument",
        };
    }
};

const Rule = struct {
    symbol: []const u8,
    class: Class,
};

/// Functions that take no arguments. RDI is whatever the last call left.
///
/// `_getpagesize` is the entry this class was added for. `int getpagesize(void)`
/// has no parameters, and a run reported it three times as a near-null receiver
/// with `rdi=0x2` — a stale value from an unrelated call — which spent a
/// signature slot and put three lines of noise directly above the one real
/// finding in the same dump. A boolean "benign" table would have fixed the
/// symptom; naming the class states why, and makes the next zero-argument
/// symbol an obvious addition rather than a judgement call.
const no_argument_symbols = [_][]const u8{
    "_getpagesize",
    "_getpid",
    "_getppid",
    "_getuid",
    "_geteuid",
    "_getgid",
    "_getegid",
    "_gettid",
    "_sched_yield",
    "_pthread_self",
    "_mach_task_self",
    "_mach_host_self",
    "_mach_thread_self",
    "_mach_absolute_time",
    "_mach_continuous_time",
    "_clock",
    "_rand",
    "_random",
    "___error",
    "_objc_autoreleasePoolPush",
    "_SDL_GetTicks",
    "_SDL_GetPerformanceCounter",
    "_SDL_GetPerformanceFrequency",
    "_SDL_GetError",
    "_SDL_Quit",
    "_SDL_GetNumAudioDevices",
    "_SDL_GetCurrentAudioDriver",
    "_SDL_NumJoysticks",
    "_gtk_main",
    "_gtk_main_quit",
    "_gtk_events_pending",
    "_gtk_main_iteration",
};

/// Functions whose first parameter is a scalar: a size, a file descriptor, a
/// clock id, a signal number, an enum, or an integer value being operated on.
const scalar_first_argument_symbols = [_][]const u8{
    // C++ allocation / deallocation — a size, or a pointer the standard
    // permits to be null (`delete nullptr` is a no-op).
    "__Znwm",
    "__Znam",
    "__ZnwmRKSt9nothrow_t",
    "__ZnamRKSt9nothrow_t",
    "__ZdlPv",
    "__ZdaPv",
    "__ZdlPvm",
    "__ZdaPvm",
    "__ZnwmSt11align_val_t",
    "__ZnamSt11align_val_t",
    "__ZnwmSt11align_val_tRKSt9nothrow_t",
    "__ZnamSt11align_val_tRKSt9nothrow_t",
    "__ZdlPvSt11align_val_t",
    "__ZdaPvSt11align_val_t",
    "_malloc",
    "_calloc",
    "_realloc",
    "_free",
    // Descriptor / dirfd first arguments — integers, never dereferenced.
    "_write",
    "_read",
    "_pwrite",
    "_pread",
    "_close",
    "_open",
    "_openat",
    "_fcntl",
    "_fstat",
    "_fstatat",
    "_ftruncate",
    "_lseek",
    "_dup",
    "_dup2",
    "_dirfd",
    "_opendir",
    "_closedir",
    "_readdir",
    "_fsync",
    "_fchmod",
    "_fchown",
    "_flock",
    "_fdopen",
    "_isatty",
    // mmap(NULL) requests any mapping; munmap/madvise of 0 is a no-op.
    "_mmap",
    "_munmap",
    "_madvise",
    "_mlock",
    "_munlock",
    "_msync",
    // clockid first argument.
    "_clock_gettime",
    "_clock_getres",
    "_clock_settime",
    "_nanosleep",
    // pthread_threadid_np(NULL) means the calling thread.
    "_pthread_threadid_np",
    // pthread_key_t is an opaque index, not a pointer.
    "_pthread_setspecific",
    // Hash-table growth size.
    "__ZNSt3__112__next_primeEm",
    // Exception object size.
    "___cxa_allocate_exception",
    // Signal numbers.
    "_sigaction",
    "_raise",
    // GtkOrientation / GtkWindowType / GType enums.
    "_gtk_box_new",
    "_gtk_window_new",
    "_gtk_window_get_type",
    "_gtk_container_get_type",
    // nl_item / sysconf name / socket domain / SDL log priority enums.
    "_nl_langinfo",
    "_sysconf",
    "_socket",
    "_SDL_LogSetAllPriority",
    // The integer being scanned or converted.
    "_ffs",
    "_abs",
    "_labs",
    "_llabs",
    "_exit",
    "__exit",
    "_srand",
    "_srandom",
    // Integer seconds / microseconds.
    "_sleep",
    "_usleep",
    "_alarm",
    // time(NULL) is the standard call form and never dereferences.
    "_time",
    // Darwin's libc returns without dereferencing a null here.
    "_asctime",
    // CCOperation enum (0 = encrypt, 1 = decrypt).
    "_CCCrypt",
    // SDL scalar first arguments: an SDL_AudioDeviceID, an SDL_INIT_* mask, or
    // a device/joystick index. A device id of 0x101 or a subsystem mask of
    // 0x10 is a correct call, not a near-null receiver.
    "_SDL_Init",
    "_SDL_InitSubSystem",
    "_SDL_QuitSubSystem",
    "_SDL_WasInit",
    "_SDL_PauseAudioDevice",
    "_SDL_CloseAudioDevice",
    "_SDL_LockAudioDevice",
    "_SDL_UnlockAudioDevice",
    "_SDL_GetAudioDeviceStatus",
    "_SDL_ClearQueuedAudio",
    "_SDL_GetQueuedAudioSize",
    "_SDL_GetAudioDeviceName",
    "_SDL_GetAudioDriver",
    "_SDL_IsGameController",
    "_SDL_GameControllerOpen",
    "_SDL_JoystickOpen",
    "_SDL_JoystickNameForIndex",
    "_SDL_Delay",
};

/// Functions whose first parameter is a real pointer for which null is the
/// documented request for a default.
const nullable_pointer_symbols = [_][]const u8{
    // SDL_OpenAudioDevice(NULL, ...) requests the default output device;
    // passing a device name is the unusual call.
    "_SDL_OpenAudioDevice",
    // SDL_AudioInit(NULL) / SDL_VideoInit(NULL) select the default driver.
    "_SDL_AudioInit",
    "_SDL_VideoInit",
    // A null hint name is a documented no-op returning null.
    "_SDL_GetHintBoolean",
};

/// Mangled-name patterns that identify a class without naming every symbol.
///
/// Each of these would otherwise need one entry per instantiation, which is a
/// table that silently stops covering new template arguments.
const Pattern = struct {
    fragment: []const u8,
    class: Class,
    /// `suffix` matches only at the end; otherwise the fragment may appear
    /// anywhere in the mangled name.
    suffix: bool,
};

const patterns = [_]Pattern{
    // std::chrono::{steady,system,high_resolution}_clock::now() — static and
    // zero-argument on every instantiation.
    .{ .fragment = "3nowEv", .class = .no_arguments, .suffix = true },
    // libc++ `basic_ostream::sentry` destructors are modelled as no-op
    // primitives that never dereference the receiver.
    .{ .fragment = "6sentryD", .class = .scalar_first_argument, .suffix = false },
};

/// Darwin decorates some libc symbols with a variant suffix. The base name
/// carries the signature, so the decoration is stripped before lookup rather
/// than duplicated per variant.
const variant_suffixes = [_][]const u8{
    "$INODE64",
    "$UNIX2003",
    "$NOCANCEL",
    "$DARWIN_EXTSN",
};

fn matchesExact(name: []const u8, table: []const []const u8) bool {
    for (table) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

/// The base symbol with any Darwin variant decoration removed.
///
/// `_fstatat$INODE64` and `_fstat$INODE64$UNIX2003` both reduce to their libc
/// name. Truncating at the first `$` handles stacked decorations in one step.
pub fn baseSymbol(name: []const u8) []const u8 {
    const dollar = std.mem.indexOfScalar(u8, name, '$') orelse return name;
    for (variant_suffixes) |suffix| {
        if (std.mem.startsWith(u8, name[dollar..], suffix)) return name[0..dollar];
    }
    return name;
}

fn classifyExact(name: []const u8) ?Class {
    if (matchesExact(name, no_argument_symbols[0..])) return .no_arguments;
    if (matchesExact(name, scalar_first_argument_symbols[0..])) return .scalar_first_argument;
    if (matchesExact(name, nullable_pointer_symbols[0..])) return .nullable_pointer_first_argument;
    return null;
}

/// What RDI holds at a call to this symbol.
///
/// Returns `.receiver` for anything not named here, which is the safe default:
/// an unknown symbol keeps its near-null finding rather than losing it. This
/// package can only ever make the predictor quieter about calls it has been
/// told about, never blinder about ones it has not.
pub fn classify(symbol_name: []const u8) Class {
    if (symbol_name.len == 0) return .receiver;
    if (classifyExact(symbol_name)) |class| return class;
    const base = baseSymbol(symbol_name);
    if (base.len != symbol_name.len) {
        if (classifyExact(base)) |class| return class;
    }
    for (patterns) |pattern| {
        const hit = if (pattern.suffix)
            std.mem.endsWith(u8, symbol_name, pattern.fragment)
        else
            std.mem.indexOf(u8, symbol_name, pattern.fragment) != null;
        if (hit) return pattern.class;
    }
    return .receiver;
}

/// Whether a near-null RDI at this call site is worth retaining as a signature.
///
/// The single predicate the import-dispatch hot path calls. It is a thin
/// wrapper over `classify` on purpose: callers that want to *report* why a
/// dispatch was dismissed use `classify` and print the class label.
pub fn predictsCasualty(symbol_name: []const u8) bool {
    return classify(symbol_name).predictsCasualty();
}

pub const symbol_count: usize =
    no_argument_symbols.len + scalar_first_argument_symbols.len + nullable_pointer_symbols.len;

/// No symbol may appear in two classes, and no table may be empty.
///
/// A duplicate across classes is not cosmetic: `classifyExact` checks the
/// tables in order, so the second entry would be unreachable and a reader
/// correcting a classification could edit the dead one and see nothing change.
pub fn contractIsWellFormed() bool {
    const tables = [_][]const []const u8{
        no_argument_symbols[0..],
        scalar_first_argument_symbols[0..],
        nullable_pointer_symbols[0..],
    };
    for (tables) |table| {
        if (table.len == 0) return false;
        for (table) |name| {
            if (name.len == 0) return false;
        }
    }
    for (tables, 0..) |table, table_index| {
        for (table) |name| {
            for (tables, 0..) |other, other_index| {
                if (other_index <= table_index) continue;
                if (matchesExact(name, other)) return false;
            }
        }
    }
    if (patterns.len == 0) return false;
    return true;
}

test "a zero-argument function is never a receiver" {
    // The regression this package was created for: three lines of noise above
    // the one real finding, because `int getpagesize(void)` was read as a
    // member call on `0x2`.
    try std.testing.expectEqual(Class.no_arguments, classify("_getpagesize"));
    try std.testing.expect(!predictsCasualty("_getpagesize"));
    try std.testing.expectEqual(Class.no_arguments, classify("_pthread_self"));
    try std.testing.expectEqual(Class.no_arguments, classify("_mach_absolute_time"));
}

test "an unnamed symbol keeps its finding" {
    // The safe default. A package that can blind the predictor to a symbol it
    // has never heard of would be worse than no package.
    try std.testing.expectEqual(Class.receiver, classify("__ZNK2xe2ui6vulkan12VulkanDevice12AcquireQueueEjj"));
    try std.testing.expect(predictsCasualty("__ZNK2xe2ui6vulkan12VulkanDevice12AcquireQueueEjj"));
    try std.testing.expectEqual(Class.receiver, classify(""));
    try std.testing.expect(predictsCasualty("_some_symbol_nobody_classified"));
}

test "scalar and nullable-pointer arguments stay distinguishable" {
    try std.testing.expectEqual(Class.scalar_first_argument, classify("_close"));
    try std.testing.expectEqual(Class.scalar_first_argument, classify("__Znwm"));
    try std.testing.expectEqual(Class.scalar_first_argument, classify("_abs"));
    // Genuinely a pointer; only the API contract dismisses it.
    try std.testing.expectEqual(Class.nullable_pointer_first_argument, classify("_SDL_OpenAudioDevice"));
    try std.testing.expect(!predictsCasualty("_SDL_OpenAudioDevice"));
    // The labels are what a report prints, so they have to survive a rename.
    try std.testing.expectEqualStrings("no-arguments", Class.no_arguments.label());
    try std.testing.expectEqualStrings("receiver", Class.receiver.label());
}

test "Darwin variant decorations reduce to their base symbol" {
    try std.testing.expectEqual(Class.scalar_first_argument, classify("_fstatat$INODE64"));
    try std.testing.expectEqual(Class.scalar_first_argument, classify("_fstat$INODE64$UNIX2003"));
    try std.testing.expectEqualStrings("_fstat", baseSymbol("_fstat$INODE64$UNIX2003"));
    // A `$` that is not a known decoration is left alone rather than guessed at.
    try std.testing.expectEqualStrings("_weird$THING", baseSymbol("_weird$THING"));
}

test "template patterns cover every instantiation" {
    try std.testing.expectEqual(
        Class.no_arguments,
        classify("__ZNSt3__16chrono12steady_clock3nowEv"),
    );
    try std.testing.expectEqual(
        Class.scalar_first_argument,
        classify("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE6sentryD1Ev"),
    );
}

test "no symbol is classified twice" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expect(symbol_count > 100);
    try std.testing.expectEqualStrings("sysv-x86_64", guest_abi);
    try std.testing.expectEqualStrings("rdi", receiver_register);
}
