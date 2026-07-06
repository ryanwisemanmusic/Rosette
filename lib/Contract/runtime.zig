const std = @import("std");
const contract = @import("contract.zig");

const MatchPattern = contract.MatchPattern;
const ContractKind = contract.ContractKind;
const ResolutionStrategy = contract.ResolutionStrategy;
const Contract = contract.Contract;

pub const ContractRegistry = struct {
    allocator: std.mem.Allocator,
    contracts: []const Contract = &.{},

    pub fn init(allocator: std.mem.Allocator) ContractRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ContractRegistry) void {
        if (self.contracts.len != 0) self.allocator.free(self.contracts);
    }

    pub fn register(self: *ContractRegistry, c: Contract) !void {
        const slice = try self.allocator.alloc(Contract, self.contracts.len + 1);
        @memcpy(slice[0..self.contracts.len], self.contracts);
        slice[self.contracts.len] = c;
        if (self.contracts.len != 0) self.allocator.free(self.contracts);
        self.contracts = slice;
    }

    pub fn registerMany(self: *ContractRegistry, contracts: []const Contract) !void {
        for (contracts) |c| try self.register(c);
    }

    pub fn lookup(self: *const ContractRegistry, name: []const u8) ?Contract {
        for (self.contracts) |c| {
            if (std.mem.eql(u8, c.name, name)) return c;
        }
        return null;
    }

    pub fn resolve(self: *const ContractRegistry, symbol: []const u8) ?Contract {
        var best: ?Contract = null;
        var best_preference: usize = 0;

        for (self.contracts) |c| {
            if (!c.matchesSymbol(symbol)) continue;
            const preference = matchPreference(c, symbol);
            if (best == null or preference > best_preference) {
                best = c;
                best_preference = preference;
            }
        }
        return best;
    }
};

fn matchPreference(c: Contract, symbol: []const u8) usize {
    for (c.matches, 0..) |pattern, idx| {
        if (!pattern.matches(symbol)) continue;
        return switch (pattern) {
            .exact => 100,
            .mangled_prefix => 80 - idx,
            .prefix => 60 - idx,
            .suffix => 40 - idx,
            .contains => 20 - idx,
        };
    }
    return 0;
}

pub const DispatchOutcome = union(enum) {
    handled: u64,
    terminated: u64,
};

pub fn dispatchContract(registry: *const ContractRegistry, symbol: []const u8, rdi: u64) ?DispatchOutcome {
    const c = registry.resolve(symbol) orelse return null;
    return dispatchSingle(c, rdi);
}

fn dispatchSingle(c: Contract, rdi: u64) ?DispatchOutcome {
    return switch (c.strategy) {
        .stub => DispatchOutcome{ .handled = 0 },
        .synthesize => if (c.returns.fixed) |val| DispatchOutcome{ .handled = val } else null,
        .terminate => DispatchOutcome{ .terminated = rdi & 0xFF },
        else => null,
    };
}

pub fn resolveFromAllFamilies(name: []const u8) ?Contract {
    inline for (comptime [_][]const Contract{
        PosixContracts.all(),
        PosixExtendedContracts.all(),
        TimeContracts.all(),
        FileIoContracts.all(),
        StdioContracts.all(),
        MiscContracts.all(),
        CxxContracts.all(),
        ObjcContracts.all(),
    }) |family| {
        for (family) |c| {
            if (c.matchesSymbol(name)) return c;
        }
    }
    return null;
}

pub fn dispatchFromAllFamilies(name: []const u8, rdi: u64) ?DispatchOutcome {
    const c = resolveFromAllFamilies(name) orelse return null;
    return dispatchSingle(c, rdi);
}

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
                .matches = &.{MatchPattern{ .exact = "_ftruncate" }},
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

test "dispatchContract handles stub strategy" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "test_stub",
        .description = "",
        .kind = .posix_thread,
        .strategy = .stub,
        .matches = &.{MatchPattern{ .exact = "_pthread_join" }},
    });
    const result = dispatchContract(&registry, "_pthread_join", 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 0), result.?.handled);
}

test "dispatchContract handles synthesize with fixed value" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "test_synthesize",
        .description = "",
        .kind = .posix_user,
        .strategy = .synthesize,
        .matches = &.{MatchPattern{ .exact = "_getuid" }},
        .returns = .{ .fixed = 501 },
    });
    const result = dispatchContract(&registry, "_getuid", 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 501), result.?.handled);
}

test "dispatchContract handles terminate strategy" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "test_terminate",
        .description = "",
        .kind = .posix_process,
        .strategy = .terminate,
        .matches = &.{MatchPattern{ .exact = "exit" }},
    });
    const result = dispatchContract(&registry, "exit", 42);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 42), result.?.terminated);
}

test "dispatchContract returns null for forward_to_host" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "test_forward",
        .description = "",
        .kind = .posix_file_io,
        .strategy = .forward_to_host,
        .matches = &.{MatchPattern{ .exact = "_open" }},
    });
    const result = dispatchContract(&registry, "_open", 0);
    try std.testing.expect(result == null);
}

test "__cxa_throw is reserved for the stateful exception handler" {
    const resolved = resolveFromAllFamilies("___cxa_throw");
    try std.testing.expect(resolved != null);
    try std.testing.expectEqual(ResolutionStrategy.custom_handler, resolved.?.strategy);
    try std.testing.expect(dispatchFromAllFamilies("___cxa_throw", 0x47c9560) == null);
}

test "dispatchContract returns null for unknown symbol" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    const result = dispatchContract(&registry, "_nonexistent", 0);
    try std.testing.expect(result == null);
}

test "ContractRegistry resolves exact match" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());

    const result = registry.resolve("_exit");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ContractKind.posix_process, result.?.kind);
    try std.testing.expectEqual(ResolutionStrategy.terminate, result.?.strategy);
}

test "ContractRegistry resolves suffix match" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());

    const result = registry.resolve("_memcpy");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ContractKind.libc_string, result.?.kind);
}

test "ContractRegistry resolves prefix match" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(ObjcContracts.all());

    const result = registry.resolve("_objc_msgSend");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ContractKind.objc_messaging, result.?.kind);
}

test "ContractRegistry resolves contains match" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(CxxContracts.all());

    const result = registry.resolve("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEPKcm");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ContractKind.cxx_string, result.?.kind);
}

test "ContractRegistry resolve prefers exact over prefix" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(Contract{
        .name = "exit_generic",
        .description = "Generic exit with prefix match",
        .kind = .posix_process,
        .strategy = .stub,
        .matches = &.{MatchPattern{ .prefix = "_exit" }},
    });
    try registry.register(Contract{
        .name = "exit",
        .description = "Exact exit match",
        .kind = .posix_process,
        .strategy = .terminate,
        .matches = &.{MatchPattern{ .exact = "_exit" }},
    });

    const result = registry.resolve("_exit");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("exit", result.?.name);
    try std.testing.expectEqual(ResolutionStrategy.terminate, result.?.strategy);
}

test "ContractRegistry returns null for unknown symbol" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());

    const result = registry.resolve("_nonexistent_function");
    try std.testing.expect(result == null);
}

test "ContractRegistry lookup by name" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());

    const c = registry.lookup("getenv");
    try std.testing.expect(c != null);
    try std.testing.expectEqualStrings("_getenv", c.?.matches[0].exact);
}

test "Contracts from all families resolve known symbols" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());
    try registry.registerMany(PosixExtendedContracts.all());
    try registry.registerMany(TimeContracts.all());
    try registry.registerMany(FileIoContracts.all());
    try registry.registerMany(StdioContracts.all());
    try registry.registerMany(MiscContracts.all());
    try registry.registerMany(CxxContracts.all());
    try registry.registerMany(ObjcContracts.all());

    try std.testing.expect(registry.resolve("_exit") != null);
    try std.testing.expect(registry.resolve("_objc_getClass") != null);
    try std.testing.expect(registry.resolve("___cxa_throw") != null);
    try std.testing.expect(registry.resolve("_gtk_init_check") != null);
    try std.testing.expect(registry.resolve("_strcmp") != null);
    try std.testing.expect(registry.resolve("_pthread_create") != null);
    try std.testing.expect(registry.resolve("_pthread_main_np") != null);
    try std.testing.expect(registry.resolve("_pthread_join") != null);
    try std.testing.expect(registry.resolve("_open") != null);
    try std.testing.expect(registry.resolve("_fopen") != null);
    try std.testing.expect(registry.resolve("_clock_gettime") != null);
    try std.testing.expect(registry.resolve("_localtime") != null);
    try std.testing.expect(registry.resolve("_gtk_dialog_run") != null);
    try std.testing.expect(registry.resolve("_objc_autoreleasePoolPop") != null);
    try std.testing.expect(registry.resolve("____chkstk_darwin") != null);
    try std.testing.expect(registry.resolve("__ZNSt20bad_array_new_lengthC1Ev") != null);
    try std.testing.expect(registry.resolve("__shared_weak_count14__release_weakEv") != null);
    try std.testing.expect(registry.resolve("__ZNSt3__16threadD1Ev") != null);
    try std.testing.expect(registry.resolve("__ZNSt3__15mutex4lockEv") != null);
    try std.testing.expect(registry.resolve("recursive_mutex4lockEv") != null);
    try std.testing.expect(registry.resolve("recursive_mutex8try_lockEv") != null);
}

test "dispatchContract handles all trivially-dispatchable contracts" {
    var registry = ContractRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMany(PosixContracts.all());
    try registry.registerMany(PosixExtendedContracts.all());
    try registry.registerMany(MiscContracts.all());
    try registry.registerMany(CxxContracts.all());

    const stubs = [_][]const u8{
        "_pthread_attr_setstacksize",
        "_pthread_attr_destroy",
        "_pthread_join",
        "_pthread_detach",
        "_objc_autoreleasePoolPop",
        "__shared_weak_count14__release_weakEv",
        "__ZNSt3__16threadD1Ev",
        "__ZNSt3__15mutex4lockEv",
        "__ZNSt3__15mutex6unlockEv",
        "recursive_mutex4lockEv",
        "recursive_mutex6unlockEv",
        "_gtk_dialog_run",
        "_gtk_widget_destroy",
        "_localtime",
    };
    for (stubs) |name| {
        const result = dispatchContract(&registry, name, 0);
        try std.testing.expect(result != null);
        try std.testing.expectEqual(@as(u64, 0), result.?.handled);
    }

    const synthesized = [_]struct { name: []const u8, expected: u64 }{
        .{ .name = "_pthread_main_np", .expected = 1 },
        .{ .name = "_getuid", .expected = 501 },
        .{ .name = "_gtk_init_check", .expected = 1 },
        .{ .name = "_gtk_message_dialog_new", .expected = 1 },
        .{ .name = "_gtk_dialog_get_type", .expected = 1 },
        .{ .name = "recursive_mutex8try_lockEv", .expected = 1 },
    };
    for (synthesized) |pair| {
        const result = dispatchContract(&registry, pair.name, 0);
        if (result == null) {
            std.debug.print("FAIL: {s} not dispatched\n", .{pair.name});
            return error.TestUnexpectedResult;
        }
        try std.testing.expectEqual(pair.expected, result.?.handled);
    }
}

test "resolveFromAllFamilies finds known symbols without registry allocation" {
    try std.testing.expect(resolveFromAllFamilies("_exit") != null);
    try std.testing.expect(resolveFromAllFamilies("_pthread_main_np") != null);
    try std.testing.expect(resolveFromAllFamilies("_gtk_dialog_run") != null);
    try std.testing.expect(resolveFromAllFamilies("__ZNSt3__15mutex4lockEv") != null);
    try std.testing.expect(resolveFromAllFamilies("_nonexistent_sym_12345") == null);
}

test "dispatchFromAllFamilies dispatches stub and synthesize contracts" {
    const stub_result = dispatchFromAllFamilies("_pthread_attr_destroy", 0);
    try std.testing.expect(stub_result != null);
    try std.testing.expectEqual(@as(u64, 0), stub_result.?.handled);

    const synth_result = dispatchFromAllFamilies("_pthread_main_np", 0);
    try std.testing.expect(synth_result != null);
    try std.testing.expectEqual(@as(u64, 1), synth_result.?.handled);

    const term_result = dispatchFromAllFamilies("_exit", 42);
    try std.testing.expect(term_result != null);
    try std.testing.expectEqual(@as(u64, 42), term_result.?.terminated);
}

test "dispatchFromAllFamilies returns null for forward_to_host contracts" {
    const result = dispatchFromAllFamilies("_open", 0);
    try std.testing.expect(result == null);
}

test "dispatchFromAllFamilies returns null for unknown symbols" {
    const result = dispatchFromAllFamilies("_nonexistent_function", 0);
    try std.testing.expect(result == null);
}
