//! Route-independent: the host C/C++/ObjC ABI contracts Rosette recognises, and
//! a comptime filter that makes resolving them cheap.
//!
//! A "contract" here is Rosette's description of a host symbol it knows how to
//! handle: which symbol spellings identify it, what kind of API it is, and
//! which resolution strategy applies. All of that is settled by the host
//! libraries Rosette was built against. None of it can change while a process
//! runs.
//!
//! It used to live in `lib/Contract/runtime.zig`, where `resolveFromAllFamilies`
//! walked eight families and 137 contracts, calling `matchesSymbol` on each,
//! which walked that contract's own pattern list. That ran on the import
//! resolution slow path — roughly 150,000 of 514,000 dispatches in a recorded
//! run — to answer a question with a constant answer.
//!
//! ## The filter
//!
//! Most symbols match no contract, and proving that was the expensive part.
//! Every pattern carries a **rare character**, chosen at comptime as the
//! character occurring in the fewest patterns overall. One pass over the symbol
//! builds a 256-bit presence set; a pattern whose rare character is absent
//! cannot match, so one bit test rejects it. This is sound for every pattern
//! kind here — `exact`, `prefix`, `suffix` and `contains` all require every
//! character of the pattern to appear in the symbol.
//!
//! ## What this package is not
//!
//! * It is not the dispatcher. What to *do* with a resolved contract —
//!   forwarding, synthesising, stubbing, terminating — stays in `lib/Contract`,
//!   because that depends on the running process.
//! * It does not rank matches. `matchPreference` and the registry's
//!   best-match selection are behaviour and stay in lib.
//! * It allocates nothing and reads no memory.

const std = @import("std");
const contract = @import("contract.zig");
/// The rejection structure is shared with the other phrase-matching packages.
const phrase_filter = @import("phrase_filter");

pub const MatchPattern = contract.MatchPattern;
pub const ContractKind = contract.ContractKind;
pub const ResolutionStrategy = contract.ResolutionStrategy;
pub const Contract = contract.Contract;
pub const Parameter = contract.Parameter;
pub const ReturnPolicy = contract.ReturnPolicy;

pub const PosixContracts = struct {
    pub fn all() []const Contract {
        return &.{
            Contract{
                .name = "exit",
                .description = "Terminate the guest process with exit code",
                .kind = .posix_process,
                .strategy = .terminate,
                .matches = &.{
                    MatchPattern{ .exact = "_exit" },
                    MatchPattern{ .exact = "exit" },
                },
                .params = &.{.{
                    .index = 0,
                    .label = "exit_code",
                }},
                .returns = .{ .fixed = 0 },
            },
            Contract{
                .name = "getenv",
                .description = "Read an environment variable",
                .kind = .posix_environment,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_getenv" }},
                .params = &.{.{
                    .index = 0,
                    .is_ptr = true,
                    .is_cstring = true,
                    .label = "name",
                }},
                .returns = .{ .result_is_ptr = true },
            },
            Contract{
                .name = "getuid",
                .description = "Get user ID",
                .kind = .posix_user,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .exact = "_getuid" }},
                .returns = .{ .fixed = 501 },
            },
            Contract{
                .name = "strcmp",
                .description = "Compare two strings",
                .kind = .libc_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_strcmp" }},
                .params = &.{
                    .{ .index = 0, .is_ptr = true, .is_cstring = true, .label = "lhs" },
                    .{ .index = 1, .is_ptr = true, .is_cstring = true, .label = "rhs" },
                },
            },
            Contract{
                .name = "memcpy",
                .description = "Copy memory region",
                .kind = .libc_string,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .suffix = "_memcpy" },
                    MatchPattern{ .suffix = "_memmove" },
                },
                .params = &.{
                    .{ .index = 0, .is_ptr = true, .label = "dest" },
                    .{ .index = 1, .is_ptr = true, .label = "src" },
                    .{ .index = 2, .label = "count" },
                },
                .returns = .{ .passthrough_arg = 0 },
            },
            Contract{
                .name = "memset",
                .description = "Fill memory region with a byte value",
                .kind = .libc_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_memset" }},
                .params = &.{
                    .{ .index = 0, .is_ptr = true, .label = "dest" },
                    .{ .index = 1, .label = "value" },
                    .{ .index = 2, .label = "count" },
                },
                .returns = .{ .passthrough_arg = 0 },
            },
            Contract{
                .name = "strlen",
                .description = "Get length of a string",
                .kind = .libc_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_strlen" }},
                .params = &.{.{
                    .index = 0,
                    .is_ptr = true,
                    .is_cstring = true,
                    .label = "str",
                }},
            },
            Contract{
                .name = "malloc",
                .description = "Allocate memory from the guest heap",
                .kind = .generic_allocator,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "__Znwm" },
                    MatchPattern{ .exact = "__Znam" },
                    MatchPattern{ .suffix = "_malloc" },
                },
                .params = &.{.{
                    .index = 0,
                    .label = "size",
                }},
                .returns = .{ .result_is_ptr = true },
            },
            Contract{
                .name = "free",
                .description = "Release memory through the guest heap manager",
                .kind = .generic_allocator,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "__ZdlPv" },
                    MatchPattern{ .exact = "__ZdaPv" },
                    MatchPattern{ .suffix = "_free" },
                },
                .params = &.{.{
                    .index = 0,
                    .is_ptr = true,
                    .label = "ptr",
                }},
            },
            Contract{
                .name = "pthread_self",
                .description = "Get current thread handle",
                .kind = .posix_thread,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .exact = "_pthread_self" }},
                .returns = .{ .fixed = 0xFFFF_FE00_0000_0001 },
            },
            Contract{
                .name = "pthread_equal",
                .description = "Compare two thread handles",
                .kind = .posix_thread,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .exact = "_pthread_equal" }},
                .params = &.{
                    .{ .index = 0, .label = "lhs" },
                    .{ .index = 1, .label = "rhs" },
                },
            },
            Contract{
                .name = "pthread_create",
                .description = "Create a new thread (forward to host, has guest memory side effects)",
                .kind = .posix_thread,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_pthread_create" }},
            },
            Contract{
                .name = "clock_gettime",
                .description = "Get clock time",
                .kind = .posix_time,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_clock_gettime" }},
                .returns = .{ .fixed = 0 },
            },
            Contract{
                .name = "___error",
                .description = "Get thread-local errno pointer",
                .kind = .posix_process,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "___error" }},
                .returns = .{ .result_is_ptr = true },
            },
            Contract{
                .name = "___assert_rtn",
                .description = "Runtime assertion failure handler",
                .kind = .posix_process,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "___assert_rtn" }},
                .returns = .{ .fixed = 0 },
            },
        };
    }
};

pub const PosixExtendedContracts = struct {
    pub fn all() []const Contract {
        return &.{
            Contract{
                .name = "strcasecmp",
                .description = "Case-insensitive string comparison",
                .kind = .libc_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_strcasecmp" }},
            },
            Contract{
                .name = "strcpy",
                .description = "Copy string",
                .kind = .libc_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_strcpy" }},
            },
            Contract{
                .name = "memcmp",
                .description = "Compare memory regions",
                .kind = .libc_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_memcmp" }},
            },
            Contract{
                .name = "pthread_main_np",
                .description = "Check if running on main thread",
                .kind = .posix_thread,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .exact = "_pthread_main_np" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "pthread_threadid_np",
                .description = "Get thread ID",
                .kind = .posix_thread,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_pthread_threadid_np" }},
            },
            Contract{
                .name = "pthread_attr_init",
                .description = "Initialize thread attributes",
                .kind = .posix_thread,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_pthread_attr_init" }},
            },
            Contract{
                .name = "pthread_attr_setstacksize",
                .description = "Set thread stack size",
                .kind = .posix_thread,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .exact = "_pthread_attr_setstacksize" }},
            },
            Contract{
                .name = "pthread_attr_destroy",
                .description = "Destroy thread attributes",
                .kind = .posix_thread,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .exact = "_pthread_attr_destroy" }},
            },
            Contract{
                .name = "pthread_join",
                .description = "Join a thread (stub)",
                .kind = .posix_thread,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .exact = "_pthread_join" }},
            },
            Contract{
                .name = "pthread_detach",
                .description = "Detach a thread (stub)",
                .kind = .posix_thread,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .exact = "_pthread_detach" }},
            },
            Contract{
                .name = "getpwuid_r",
                .description = "Get password file entry for UID",
                .kind = .posix_user,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_getpwuid_r" }},
            },
            Contract{
                .name = "calloc",
                .description = "Allocate zero-initialized memory",
                .kind = .generic_allocator,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_calloc" }},
            },
            Contract{
                .name = "posix_memalign",
                .description = "Allocate aligned memory",
                .kind = .generic_allocator,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_posix_memalign" }},
            },
            Contract{
                .name = "chkstk_darwin",
                .description = "Stack probe helper",
                .kind = .posix_process,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "____chkstk_darwin" }},
            },
        };
    }
};

pub const TimeContracts = struct {
    pub fn all() []const Contract {
        return &.{
            Contract{
                .name = "clock_getres",
                .description = "Get clock resolution",
                .kind = .posix_time,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_clock_getres" }},
                .returns = .{ .fixed = 0 },
            },
            Contract{
                .name = "gettimeofday",
                .description = "Get time of day",
                .kind = .posix_time,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_gettimeofday" }},
                .returns = .{ .fixed = 0 },
            },
            Contract{
                .name = "time",
                .description = "Get current time in seconds",
                .kind = .posix_time,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_time" }},
            },
        };
    }
};

pub const FileIoContracts = struct {
    pub fn all() []const Contract {
        return &.{
            Contract{
                .name = "open",
                .description = "Open a file",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_open" }},
            },
            Contract{
                .name = "write",
                .description = "Write to file descriptor",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_write" }},
            },
            Contract{
                .name = "close",
                .description = "Close file descriptor",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_close" }},
            },
            Contract{
                .name = "fstatat",
                .description = "Stat file relative to directory fd",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "_fstatat$INODE64" },
                    MatchPattern{ .exact = "_fstatat" },
                },
            },
            Contract{
                .name = "openat",
                .description = "Open file relative to directory fd",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_openat" }},
            },
            Contract{
                .name = "fstat",
                .description = "Stat open file",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "_fstat$INODE64" },
                    MatchPattern{ .exact = "_fstat" },
                },
            },
            Contract{
                .name = "ftruncate",
                .description = "Resize an open file",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "_ftruncate" },
                    MatchPattern{ .exact = "_ftruncate64" },
                },
            },
            Contract{
                .name = "shm_open",
                .description = "Open POSIX shared memory object",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_shm_open" }},
            },
            Contract{
                .name = "shm_unlink",
                .description = "Unlink POSIX shared memory object",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_shm_unlink" }},
            },
            Contract{
                .name = "opendir",
                .description = "Open a directory",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "_opendir$INODE64" },
                    MatchPattern{ .exact = "_opendir" },
                },
            },
            Contract{
                .name = "dirfd",
                .description = "Get file descriptor from DIR*",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_dirfd" }},
            },
            Contract{
                .name = "closedir",
                .description = "Close a directory",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_closedir" }},
            },
            Contract{
                .name = "readdir",
                .description = "Read a directory entry into guest memory",
                .kind = .posix_file_io,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "_readdir$INODE64" },
                    MatchPattern{ .exact = "_readdir" },
                },
            },
        };
    }
};

pub const StdioContracts = struct {
    pub fn all() []const Contract {
        return &.{
            Contract{
                .name = "fopen",
                .description = "Open a file stream",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_fopen" }},
            },
            Contract{
                .name = "fclose",
                .description = "Close a file stream",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_fclose" }},
            },
            Contract{
                .name = "fprintf",
                .description = "Print formatted to file stream",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_fprintf" }},
            },
            Contract{
                .name = "fputs",
                .description = "Write string to file stream",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_fputs" }},
            },
            Contract{
                .name = "fwrite",
                .description = "Write elements to file stream",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_fwrite" }},
            },
            Contract{
                .name = "fflush",
                .description = "Flush file stream",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_fflush" }},
            },
            Contract{
                .name = "ftell",
                .description = "Get file stream position",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_ftell" }},
            },
            Contract{
                .name = "fseek",
                .description = "Seek file stream",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_fseek" }},
            },
            Contract{
                .name = "ferror",
                .description = "Check file stream error",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_ferror" }},
            },
            Contract{
                .name = "printf",
                .description = "Print formatted to stdout",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_printf" }},
            },
            Contract{
                .name = "putchar",
                .description = "Write character to stdout",
                .kind = .libc_stdio,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_putchar" }},
            },
        };
    }
};

pub const MiscContracts = struct {
    pub fn all() []const Contract {
        return &.{
            Contract{
                .name = "localtime",
                .description = "Convert time to local time (stub)",
                .kind = .posix_time,
                .strategy = .stub,
                .matches = &.{
                    MatchPattern{ .suffix = "_localtime" },
                    MatchPattern{ .suffix = "_strftime" },
                },
            },
            Contract{
                .name = "g_type_check_instance_cast",
                .description = "GObject type check cast (passthrough)",
                .kind = .gtk_ui,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .suffix = "_g_type_check_instance_cast" }},
            },
            Contract{
                .name = "gtk_dialog_get_type",
                .description = "Get GTK dialog GType",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_dialog_get_type" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_init_check",
                .description = "Initialize GTK (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_init_check" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_message_dialog_new",
                .description = "Create a GTK message dialog (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_message_dialog_new" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_dialog_run",
                .description = "Run a GTK dialog (stub)",
                .kind = .gtk_ui,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .suffix = "_gtk_dialog_run" }},
            },
            Contract{
                .name = "gtk_widget_destroy",
                .description = "Destroy a GTK widget (stub)",
                .kind = .gtk_ui,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .suffix = "_gtk_widget_destroy" }},
            },
            Contract{
                .name = "gtk_menu_bar_new",
                .description = "Create a GTK menu bar (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_menu_bar_new" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_menu_item_new_with_mnemonic",
                .description = "Create a GTK menu item with mnemonic (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_menu_item_new_with_mnemonic" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_box_new",
                .description = "Create a GTK box container (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_box_new" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_box_get_type",
                .description = "Get GTK box GType (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_box_get_type" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_box_pack_start",
                .description = "Pack widget into GTK box (stub)",
                .kind = .gtk_ui,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .suffix = "_gtk_box_pack_start" }},
            },
            Contract{
                .name = "gtk_label_new_with_mnemonic",
                .description = "Create a GTK label with mnemonic (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_label_new_with_mnemonic" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_label_get_type",
                .description = "Get GTK label GType (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_label_get_type" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_label_set_xalign",
                .description = "Set GTK label x-alignment (stub)",
                .kind = .gtk_ui,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .suffix = "_gtk_label_set_xalign" }},
            },
            Contract{
                .name = "gtk_label_new",
                .description = "Create a GTK label (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_label_new" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "gtk_widget_set_margin_start",
                .description = "Set GTK widget start margin (stub)",
                .kind = .gtk_ui,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .suffix = "_gtk_widget_set_margin_start" }},
            },
            Contract{
                .name = "g_object_ref_sink",
                .description = "Sink a floating GObject reference (stub)",
                .kind = .gtk_ui,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .suffix = "_g_object_ref_sink" }},
            },
            Contract{
                .name = "gtk_menu_item_get_type",
                .description = "Get GTK menu item GType (stub)",
                .kind = .gtk_ui,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .suffix = "_gtk_menu_item_get_type" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "objc_autoreleasePoolPush",
                .description = "Push an autorelease pool (forward to host, returns thread handle)",
                .kind = .objc_memory,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_objc_autoreleasePoolPush" }},
            },
            Contract{
                .name = "objc_autoreleasePoolPop",
                .description = "Pop an autorelease pool (stub)",
                .kind = .objc_memory,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .exact = "_objc_autoreleasePoolPop" }},
            },
            Contract{
                .name = "bad_array_new_length",
                .description = "C++ bad_array_new_length constructor",
                .kind = .cxx_exception,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "__ZNSt20bad_array_new_lengthC1Ev" }},
            },
            Contract{
                .name = "shared_weak_count_release_weak",
                .description = "libc++ shared_ptr weak count release (stub)",
                .kind = .cxx_memory,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .contains = "__shared_weak_count14__release_weakEv" }},
            },
        };
    }
};

pub const CxxContracts = struct {
    pub fn all() []const Contract {
        return &.{
            Contract{
                .name = "__cxa_guard_acquire",
                .description = "Acquire C++ static initialisation guard",
                .kind = .cxx_guard,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "___cxa_guard_acquire" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "__cxa_guard_release",
                .description = "Release C++ static initialisation guard",
                .kind = .cxx_guard,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "___cxa_guard_release" }},
            },
            Contract{
                .name = "__cxa_guard_abort",
                .description = "Abort C++ static initialisation guard",
                .kind = .cxx_guard,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "___cxa_guard_abort" }},
            },
            Contract{
                .name = "__cxa_atexit",
                .description = "Register C++ atexit handler",
                .kind = .cxx_memory,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "___cxa_atexit" }},
                .returns = .{ .fixed = 0 },
            },
            Contract{
                .name = "__cxa_throw",
                .description = "Throw a C++ exception",
                .kind = .cxx_exception,
                .strategy = .custom_handler,
                .matches = &.{MatchPattern{ .exact = "___cxa_throw" }},
            },
            Contract{
                .name = "__cxa_allocate_exception",
                .description = "Allocate memory for a C++ exception object",
                .kind = .cxx_exception,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "___cxa_allocate_exception" }},
                .returns = .{ .result_is_ptr = true },
            },
            Contract{
                .name = "__cxa_begin_catch",
                .description = "Enter an Itanium C++ ABI catch handler",
                .kind = .cxx_exception,
                .strategy = .custom_handler,
                .matches = &.{MatchPattern{ .exact = "___cxa_begin_catch" }},
                .returns = .{ .result_is_ptr = true },
            },
            Contract{
                .name = "__cxa_end_catch",
                .description = "Leave the active Itanium C++ ABI catch handler",
                .kind = .cxx_exception,
                .strategy = .custom_handler,
                .matches = &.{MatchPattern{ .exact = "___cxa_end_catch" }},
            },
            Contract{
                .name = "__cxa_get_exception_ptr",
                .description = "Resolve an Itanium exception header to its guest object",
                .kind = .cxx_exception,
                .strategy = .custom_handler,
                .matches = &.{MatchPattern{ .exact = "___cxa_get_exception_ptr" }},
                .returns = .{ .result_is_ptr = true },
            },
            Contract{
                .name = "__cxa_free_exception",
                .description = "Release an Itanium exception allocation from the guest heap",
                .kind = .cxx_exception,
                .strategy = .custom_handler,
                .matches = &.{MatchPattern{ .exact = "___cxa_free_exception" }},
            },
            Contract{
                .name = "__cxa_rethrow",
                .description = "Resume unwinding the active Itanium C++ exception",
                .kind = .cxx_exception,
                .strategy = .custom_handler,
                .matches = &.{MatchPattern{ .exact = "___cxa_rethrow" }},
            },
            Contract{
                .name = "_Unwind_Resume",
                .description = "Resume phase-two Itanium stack unwinding",
                .kind = .cxx_exception,
                .strategy = .custom_handler,
                .matches = &.{MatchPattern{ .exact = "__Unwind_Resume" }},
            },
            Contract{
                .name = "__next_prime",
                .description = "libc++ next prime for hash table sizing",
                .kind = .cxx_algorithm,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "__ZNSt3__112__next_primeEm" }},
            },
            Contract{
                .name = "ios_base_xalloc",
                .description = "libc++ ios_base::xalloc",
                .kind = .cxx_ios,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "__ZNSt3__18ios_base6xallocEv" }},
            },
            Contract{
                .name = "system_clock_now",
                .description = "libc++ system_clock::now",
                .kind = .cxx_chrono,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "__ZNSt3__16chrono12system_clock3nowEv" }},
            },
            Contract{
                .name = "recursive_mutex_construct",
                .description = "libc++ recursive_mutex constructor",
                .kind = .cxx_mutex,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .contains = "recursive_mutexC1Ev" },
                    MatchPattern{ .contains = "recursive_mutexC2Ev" },
                },
            },
            Contract{
                .name = "recursive_mutex_try_lock",
                .description = "libc++ recursive_mutex::try_lock",
                .kind = .cxx_mutex,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .contains = "recursive_mutex8try_lockEv" }},
                .returns = .{ .fixed = 1 },
            },
            Contract{
                .name = "recursive_mutex_stub",
                .description = "libc++ recursive_mutex lock/unlock/destroy",
                .kind = .cxx_mutex,
                .strategy = .stub,
                .matches = &.{
                    MatchPattern{ .contains = "recursive_mutex4lockEv" },
                    MatchPattern{ .contains = "recursive_mutex6unlockEv" },
                    MatchPattern{ .contains = "recursive_mutexD1Ev" },
                    MatchPattern{ .contains = "recursive_mutexD2Ev" },
                },
            },
            Contract{
                .name = "__thread_struct_construct",
                .description = "libc++ __thread_struct constructor",
                .kind = .cxx_thread,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .contains = "__thread_structC1Ev" },
                    MatchPattern{ .contains = "__thread_structC2Ev" },
                },
            },
            Contract{
                .name = "mutex",
                .description = "libc++ mutex lock/unlock/destroy (stub)",
                .kind = .cxx_mutex,
                .strategy = .stub,
                .matches = &.{
                    MatchPattern{ .exact = "__ZNSt3__15mutex4lockEv" },
                    MatchPattern{ .exact = "__ZNSt3__15mutex6unlockEv" },
                    MatchPattern{ .exact = "__ZNSt3__15mutexD1Ev" },
                    MatchPattern{ .exact = "__ZNSt3__15mutexD2Ev" },
                },
            },
            Contract{
                .name = "condition_variable",
                .description = "libc++ condition_variable operations (stub)",
                .kind = .cxx_condition,
                .strategy = .stub,
                .matches = &.{
                    MatchPattern{ .contains = "condition_variable10notify_" },
                    MatchPattern{ .contains = "condition_variable4wait" },
                    MatchPattern{ .contains = "condition_variable15__do_timed_wait" },
                    MatchPattern{ .contains = "condition_variableD1Ev" },
                    MatchPattern{ .contains = "condition_variableD2Ev" },
                },
            },
            Contract{
                .name = "locale_construct",
                .description = "libc++ locale construction",
                .kind = .cxx_locale,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "__ZNSt3__16localeC1Ev" },
                    MatchPattern{ .exact = "__ZNSt3__16localeC2Ev" },
                    MatchPattern{ .exact = "__ZNSt3__16localeC1ERKS0_" },
                    MatchPattern{ .exact = "__ZNSt3__16localeC2ERKS0_" },
                },
            },
            Contract{
                .name = "locale_destroy",
                .description = "libc++ locale destruction",
                .kind = .cxx_locale,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "__ZNSt3__16localeD1Ev" },
                    MatchPattern{ .exact = "__ZNSt3__16localeD2Ev" },
                },
            },
            Contract{
                .name = "locale_name",
                .description = "libc++ locale::name()",
                .kind = .cxx_locale,
                .strategy = .synthesize,
                .matches = &.{MatchPattern{ .exact = "__ZNKSt3__16locale4nameEv" }},
                .data = "C",
            },
            Contract{
                .name = "locale_use_facet",
                .description = "libc++ locale::use_facet",
                .kind = .cxx_locale,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "__ZNKSt3__16locale9use_facetERNS0_2idE" }},
            },
            Contract{
                .name = "__get_classname",
                .description = "libc++ regex __get_classname",
                .kind = .cxx_regex,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "__ZNSt3__115__get_classnameEPKcb" }},
            },
            Contract{
                .name = "filesystem_path_root_directory",
                .description = "libc++ filesystem::path::__root_directory",
                .kind = .cxx_filesystem,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "__ZNKSt3__14__fs10filesystem4path16__root_directoryEv" }},
            },
            Contract{
                .name = "filesystem_path_filename",
                .description = "libc++ filesystem::path::__filename",
                .kind = .cxx_filesystem,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "__ZNKSt3__14__fs10filesystem4path10__filenameEv" }},
            },
            Contract{
                .name = "filesystem_path_parent_path",
                .description = "libc++ filesystem::path::__parent_path",
                .kind = .cxx_filesystem,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "__ZNKSt3__14__fs10filesystem4path13__parent_pathEv" }},
            },
            Contract{
                .name = "thread_destroy",
                .description = "libc++ thread destruction (stub)",
                .kind = .cxx_thread,
                .strategy = .stub,
                .matches = &.{
                    MatchPattern{ .exact = "__ZNSt3__16threadD1Ev" },
                    MatchPattern{ .exact = "__ZNSt3__16threadD2Ev" },
                },
            },
            Contract{
                .name = "basic_string_init",
                .description = "libc++ basic_string::__init",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEPKcm" }},
                .params = &.{
                    .{ .index = 0, .is_ptr = true, .label = "this" },
                    .{ .index = 1, .is_ptr = true, .label = "source" },
                    .{ .index = 2, .label = "length" },
                },
                .returns = .{ .passthrough_arg = 0 },
            },
            Contract{
                .name = "basic_string_init_fill",
                .description = "libc++ basic_string::__init(size, char)",
                .kind = .cxx_string,
                .strategy = .custom_handler,
                .matches = &.{MatchPattern{ .exact = "__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEmc" }},
                .params = &.{
                    .{ .index = 0, .is_ptr = true, .label = "this" },
                    .{ .index = 1, .label = "length" },
                    .{ .index = 2, .label = "value" },
                },
            },
            Contract{
                .name = "basic_string_assign_cstring",
                .description = "libc++ basic_string::assign from C string",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6assignEPKc" }},
                .params = &.{
                    .{ .index = 0, .is_ptr = true, .label = "this" },
                    .{ .index = 1, .is_ptr = true, .is_cstring = true, .label = "source" },
                },
                .returns = .{ .passthrough_arg = 0 },
            },
            Contract{
                .name = "basic_string_append_cstring_length",
                .description = "libc++ basic_string::append from pointer and length",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKcm" }},
                .returns = .{ .passthrough_arg = 0 },
            },
            Contract{
                .name = "basic_string_append_cstring",
                .description = "libc++ basic_string::append from C string",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKc" }},
                .returns = .{ .passthrough_arg = 0 },
            },
            Contract{
                .name = "basic_string_grow_by",
                .description = "libc++ basic_string::__grow_by",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE9__grow_byEmmmmmm" }},
            },
            Contract{
                .name = "basic_string_copy_construct",
                .description = "libc++ basic_string copy constructor",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEC1ERKS5_" },
                    MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEC2ERKS5_" },
                },
                .returns = .{ .passthrough_arg = 0 },
            },
            Contract{
                .name = "basic_string_assign_string",
                .description = "libc++ basic_string::operator=(const string&)",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEaSERKS5_" }},
                .returns = .{ .passthrough_arg = 0 },
            },
            Contract{
                .name = "basic_string_assign_char",
                .description = "libc++ basic_string::operator=(char)",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEaSEc" }},
                .returns = .{ .passthrough_arg = 0 },
            },
            Contract{
                .name = "basic_string_destroy",
                .description = "libc++ basic_string destructor",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev" },
                    MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev" },
                },
            },
            Contract{
                .name = "basic_string_find_char",
                .description = "libc++ basic_string::find(char, pos)",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .contains = "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE4findEcm" }},
            },
            Contract{
                .name = "string_plus_cstring",
                .description = "libc++ operator+(const char*, const string&)",
                .kind = .cxx_string,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .contains = "plIcNS_11char_traitsIcEENS_9allocatorIcEEEENS_12basic_stringIT_T0_T1_EEPKS6_RKS9_" }},
            },
            Contract{
                .name = "ios_base_clear",
                .description = "libc++ ios_base::clear(iostate) — stub",
                .kind = .cxx_ios,
                .strategy = .stub,
                .matches = &.{MatchPattern{ .exact = "__ZNSt3__18ios_base5clearEj" }},
            },
        };
    }
};

pub const ObjcContracts = struct {
    pub fn all() []const Contract {
        return &.{
            Contract{
                .name = "objc_getClass",
                .description = "Look up an Objective-C class by name",
                .kind = .objc_runtime,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_objc_getClass" }},
                .returns = .{ .result_is_ptr = true },
            },
            Contract{
                .name = "sel_registerName",
                .description = "Register an Objective-C selector",
                .kind = .objc_runtime,
                .strategy = .forward_to_host,
                .matches = &.{MatchPattern{ .exact = "_sel_registerName" }},
                .returns = .{ .result_is_ptr = true },
            },
            Contract{
                .name = "objc_msgSend",
                .description = "Send an Objective-C message",
                .kind = .objc_messaging,
                .strategy = .forward_to_host,
                .matches = &.{
                    MatchPattern{ .exact = "_objc_msgSend" },
                    MatchPattern{ .exact = "_objc_msgSendSuper" },
                },
                .returns = .{ .result_is_ptr = true },
            },
        };
    }
};

/// Every family, in the order `resolveFromAllFamilies` has always checked them.
pub fn allFamilies() []const []const Contract {
    const families = comptime [_][]const Contract{
        PosixContracts.all(),
        PosixExtendedContracts.all(),
        TimeContracts.all(),
        FileIoContracts.all(),
        StdioContracts.all(),
        MiscContracts.all(),
        CxxContracts.all(),
        ObjcContracts.all(),
    };
    return &families;
}

/// The literal text of a pattern, whichever kind it is.
fn patternText(pattern: MatchPattern) []const u8 {
    return switch (pattern) {
        .exact => |text| text,
        .prefix => |text| text,
        .suffix => |text| text,
        .contains => |text| text,
        .mangled_prefix => |text| text,
    };
}

/// Total contracts across every family.
pub const contract_count: usize = blk: {
    @setEvalBranchQuota(100_000);
    var total: usize = 0;
    for (allFamilies()) |family| total += family.len;
    break :blk total;
};

pub const CharacterSet = phrase_filter.CharacterSet;
pub const characterSet = phrase_filter.characterSet;

/// The first pattern text of every contract, in family order.
///
/// A contract is only accelerated when it has exactly one pattern: rejecting a
/// contract requires proving that *none* of its patterns can match, and a
/// multi-pattern contract rarely has a character shared by all of them. Those
/// fall through to the full check, which is still correct. An empty string
/// marks a contract as unaccelerated, and the shared filter always lets an
/// empty phrase survive.
const contract_first_patterns: [contract_count][]const u8 = blk: {
    @setEvalBranchQuota(1_000_000);
    var table: [contract_count][]const u8 = undefined;
    var index: usize = 0;
    for (allFamilies()) |family| {
        for (family) |c| {
            table[index] = if (c.matches.len == 1) patternText(c.matches[0]) else "";
            index += 1;
        }
    }
    break :blk table;
};

const filter = phrase_filter.Filter(&contract_first_patterns);
pub const contract_rare_characters = filter.rare_characters;

/// Resolve a symbol to its contract, or null.
///
/// Same ordering and same answer as the linear walk it replaces; only the cost
/// of reaching "no match" changes.
pub fn resolve(symbol: []const u8) ?Contract {
    const set = phrase_filter.characterSet(symbol);
    var index: usize = 0;
    for (allFamilies()) |family| {
        for (family) |c| {
            const accelerated = index;
            index += 1;
            // A multi-pattern contract carries an empty phrase and always
            // survives, so the full check runs for it.
            if (!filter.survives(set, accelerated)) continue;
            if (c.matchesSymbol(symbol)) return c;
        }
    }
    return null;
}

/// The filter must never reject a symbol the unaccelerated walk would match.
fn resolveUnfiltered(symbol: []const u8) ?Contract {
    for (allFamilies()) |family| {
        for (family) |c| {
            if (c.matchesSymbol(symbol)) return c;
        }
    }
    return null;
}

pub fn contractIsWellFormed() bool {
    if (contract_count == 0) return false;
    for (allFamilies()) |family| {
        if (family.len == 0) return false;
        for (family) |c| {
            if (c.name.len == 0 or c.matches.len == 0) return false;
        }
    }
    // The shared filter proves every accelerated pattern's rare character is
    // genuinely in that pattern.
    return filter.isWellFormed();
}

test "the filter agrees with the unaccelerated walk on known symbols" {
    for ([_][]const u8{
        "_exit",
        "_pthread_main_np",
        "_gtk_dialog_run",
        "__ZNSt3__15mutex4lockEv",
        "___cxa_throw",
        "_nonexistent_sym_12345",
        "",
        "_malloc",
        "_objc_msgSend",
    }) |symbol| {
        const filtered = resolve(symbol);
        const unfiltered = resolveUnfiltered(symbol);
        try std.testing.expectEqual(unfiltered == null, filtered == null);
        if (unfiltered) |expected| {
            try std.testing.expectEqualStrings(expected.name, filtered.?.name);
        }
    }
}

test "every pattern still resolves through the filter" {
    // Exhaustive soundness: for each contract, its own first pattern text must
    // still resolve to something. This is what proves the rare-character
    // rejection never drops a real match.
    for (allFamilies()) |family| {
        for (family) |c| {
            for (c.matches) |pattern| {
                const text = patternText(pattern);
                if (text.len == 0) continue;
                // `exact` and `prefix` match their own text directly; `suffix`
                // and `contains` do too, since the text contains itself.
                try std.testing.expect(resolve(text) != null);
                const filtered = resolve(text);
                const unfiltered = resolveUnfiltered(text);
                try std.testing.expectEqualStrings(unfiltered.?.name, filtered.?.name);
            }
        }
    }
}

test "the catalogue is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expect(contract_count > 100);
    try std.testing.expectEqual(@as(usize, 8), allFamilies().len);
}
