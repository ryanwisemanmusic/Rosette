const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.elf);
const elf_loader = @import("elf_loader.zig");
const result_dump = @import("result_dump.zig");
const x64_guest_abi = @import("x64_guest_abi");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const evex = @import("evex_runtime");
const x64_linux_runtime = @import("x64_linux_runtime");
const x64_syscalls = @import("x64_syscalls");
const exit_diagnostics = @import("exit_diagnostics");
const cleo_routing = @import("cleo_routing");
const execution_history = @import("execution_history");
const vector_helpers = @import("x86_vector_helpers");

fn releaseMemoryBarrier() void {
    if (comptime @import("builtin").target.cpu.arch == .aarch64) {
        asm volatile ("dmb ish" ::: .{ .memory = true });
    } else {
        asm volatile ("mfence" ::: .{ .memory = true });
    }
}

const SYS_read = x64_syscalls.SYS_read; // 0
const SYS_write = x64_syscalls.SYS_write; // 1
const SYS_open = x64_syscalls.SYS_open; // 2
const SYS_close = x64_syscalls.SYS_close; // 3
const SYS_stat = x64_syscalls.SYS_stat; // 4
const SYS_fstat = x64_syscalls.SYS_fstat; // 5
const SYS_lstat = x64_syscalls.SYS_lstat; // 6
const SYS_poll = x64_syscalls.SYS_poll; // 7
const SYS_lseek = x64_syscalls.SYS_lseek; // 8
const SYS_mmap = x64_syscalls.SYS_mmap; // 9
const SYS_mprotect = x64_syscalls.SYS_mprotect; // 10
const SYS_munmap = x64_syscalls.SYS_munmap; // 11
const SYS_brk = x64_syscalls.SYS_brk; // 12
const SYS_rt_sigaction = x64_syscalls.SYS_rt_sigaction; // 13
const SYS_rt_sigprocmask = x64_syscalls.SYS_rt_sigprocmask; // 14
const SYS_rt_sigreturn = x64_syscalls.SYS_rt_sigreturn; // 15
const SYS_ioctl = x64_syscalls.SYS_ioctl; // 16
const SYS_pread64 = x64_syscalls.SYS_pread64; // 17
const SYS_pwrite64 = x64_syscalls.SYS_pwrite64; // 18
const SYS_readv = x64_syscalls.SYS_readv; // 19
const SYS_writev = x64_syscalls.SYS_writev; // 20
const SYS_access = x64_syscalls.SYS_access; // 21
const SYS_pipe = x64_syscalls.SYS_pipe; // 22
const SYS_select = x64_syscalls.SYS_select; // 23
const SYS_sched_yield = x64_syscalls.SYS_sched_yield; // 24
const SYS_mremap = x64_syscalls.SYS_mremap; // 25
const SYS_msync = x64_syscalls.SYS_msync; // 26
const SYS_mincore = x64_syscalls.SYS_mincore; // 27
const SYS_madvise = x64_syscalls.SYS_madvise; // 28
const SYS_shmget = x64_syscalls.SYS_shmget; // 29
const SYS_shmat = x64_syscalls.SYS_shmat; // 30
const SYS_shmctl = x64_syscalls.SYS_shmctl; // 31
const SYS_dup = x64_syscalls.SYS_dup; // 32
const SYS_dup2 = x64_syscalls.SYS_dup2; // 33
const SYS_pause = x64_syscalls.SYS_pause; // 34
const SYS_nanosleep = x64_syscalls.SYS_nanosleep; // 35
const SYS_getitimer = x64_syscalls.SYS_getitimer; // 36
const SYS_alarm = x64_syscalls.SYS_alarm; // 37
const SYS_setitimer = x64_syscalls.SYS_setitimer; // 38
const SYS_getpid = x64_syscalls.SYS_getpid; // 39
const SYS_sendfile = x64_syscalls.SYS_sendfile; // 40
const SYS_socket = x64_syscalls.SYS_socket; // 41
const SYS_connect = x64_syscalls.SYS_connect; // 42
const SYS_accept = x64_syscalls.SYS_accept; // 43
const SYS_sendto = x64_syscalls.SYS_sendto; // 44
const SYS_recvfrom = x64_syscalls.SYS_recvfrom; // 45
const SYS_sendmsg = x64_syscalls.SYS_sendmsg; // 46
const SYS_recvmsg = x64_syscalls.SYS_recvmsg; // 47
const SYS_shutdown = x64_syscalls.SYS_shutdown; // 48
const SYS_bind = x64_syscalls.SYS_bind; // 49
const SYS_listen = x64_syscalls.SYS_listen; // 50
const SYS_getsockname = x64_syscalls.SYS_getsockname; // 51
const SYS_getpeername = x64_syscalls.SYS_getpeername; // 52
const SYS_socketpair = x64_syscalls.SYS_socketpair; // 53
const SYS_setsockopt = x64_syscalls.SYS_setsockopt; // 54
const SYS_getsockopt = x64_syscalls.SYS_getsockopt; // 55
const SYS_clone = x64_syscalls.SYS_clone; // 56
const SYS_fork = x64_syscalls.SYS_fork; // 57
const SYS_vfork = x64_syscalls.SYS_vfork; // 58
const SYS_execve = x64_syscalls.SYS_execve; // 59
const SYS_exit = x64_syscalls.SYS_exit; // 60
const SYS_wait4 = x64_syscalls.SYS_wait4; // 61
const SYS_kill = x64_syscalls.SYS_kill; // 62
const SYS_uname = x64_syscalls.SYS_uname; // 63
const SYS_semget = x64_syscalls.SYS_semget; // 64
const SYS_semop = x64_syscalls.SYS_semop; // 65
const SYS_semctl = x64_syscalls.SYS_semctl; // 66
const SYS_shmdt = x64_syscalls.SYS_shmdt; // 67
const SYS_msgget = x64_syscalls.SYS_msgget; // 68
const SYS_msgsnd = x64_syscalls.SYS_msgsnd; // 69
const SYS_msgrcv = x64_syscalls.SYS_msgrcv; // 70
const SYS_msgctl = x64_syscalls.SYS_msgctl; // 71
const SYS_fcntl = x64_syscalls.SYS_fcntl; // 72
const SYS_flock = x64_syscalls.SYS_flock; // 73
const SYS_fsync = x64_syscalls.SYS_fsync; // 74
const SYS_fdatasync = x64_syscalls.SYS_fdatasync; // 75
const SYS_truncate = x64_syscalls.SYS_truncate; // 76
const SYS_ftruncate = x64_syscalls.SYS_ftruncate; // 77
const SYS_getdents = x64_syscalls.SYS_getdents; // 78
const SYS_getcwd = x64_syscalls.SYS_getcwd; // 79
const SYS_chdir = x64_syscalls.SYS_chdir; // 80
const SYS_fchdir = x64_syscalls.SYS_fchdir; // 81
const SYS_rename = x64_syscalls.SYS_rename; // 82
const SYS_mkdir = x64_syscalls.SYS_mkdir; // 83
const SYS_rmdir = x64_syscalls.SYS_rmdir; // 84
const SYS_creat = x64_syscalls.SYS_creat; // 85
const SYS_link = x64_syscalls.SYS_link; // 86
const SYS_unlink = x64_syscalls.SYS_unlink; // 87
const SYS_symlink = x64_syscalls.SYS_symlink; // 88
const SYS_readlink = x64_syscalls.SYS_readlink; // 89
const SYS_chmod = x64_syscalls.SYS_chmod; // 90
const SYS_fchmod = x64_syscalls.SYS_fchmod; // 91
const SYS_chown = x64_syscalls.SYS_chown; // 92
const SYS_fchown = x64_syscalls.SYS_fchown; // 93
const SYS_lchown = x64_syscalls.SYS_lchown; // 94
const SYS_umask = x64_syscalls.SYS_umask; // 95
const SYS_gettimeofday = x64_syscalls.SYS_gettimeofday; // 96
const SYS_getrlimit = x64_syscalls.SYS_getrlimit; // 97
const SYS_getrusage = x64_syscalls.SYS_getrusage; // 98
const SYS_sysinfo = x64_syscalls.SYS_sysinfo; // 99
const SYS_times = x64_syscalls.SYS_times; // 100
const SYS_ptrace = x64_syscalls.SYS_ptrace; // 101
const SYS_getuid = x64_syscalls.SYS_getuid; // 102
const SYS_syslog = x64_syscalls.SYS_syslog; // 103
const SYS_getgid = x64_syscalls.SYS_getgid; // 104
const SYS_setuid = x64_syscalls.SYS_setuid; // 105
const SYS_setgid = x64_syscalls.SYS_setgid; // 106
const SYS_geteuid = x64_syscalls.SYS_geteuid; // 107
const SYS_getegid = x64_syscalls.SYS_getegid; // 108
const SYS_setpgid = x64_syscalls.SYS_setpgid; // 109
const SYS_getppid = x64_syscalls.SYS_getppid; // 110
const SYS_getpgrp = x64_syscalls.SYS_getpgrp; // 111
const SYS_setsid = x64_syscalls.SYS_setsid; // 112
const SYS_setreuid = x64_syscalls.SYS_setreuid; // 113
const SYS_setregid = x64_syscalls.SYS_setregid; // 114
const SYS_getgroups = x64_syscalls.SYS_getgroups; // 115
const SYS_setgroups = x64_syscalls.SYS_setgroups; // 116
const SYS_setresuid = x64_syscalls.SYS_setresuid; // 117
const SYS_getresuid = x64_syscalls.SYS_getresuid; // 118
const SYS_setresgid = x64_syscalls.SYS_setresgid; // 119
const SYS_getresgid = x64_syscalls.SYS_getresgid; // 120
const SYS_getpgid = x64_syscalls.SYS_getpgid; // 121
const SYS_setfsuid = x64_syscalls.SYS_setfsuid; // 122
const SYS_setfsgid = x64_syscalls.SYS_setfsgid; // 123
const SYS_getsid = x64_syscalls.SYS_getsid; // 124
const SYS_capget = x64_syscalls.SYS_capget; // 125
const SYS_capset = x64_syscalls.SYS_capset; // 126
const SYS_rt_sigpending = x64_syscalls.SYS_rt_sigpending; // 127
const SYS_rt_sigtimedwait = x64_syscalls.SYS_rt_sigtimedwait; // 128
const SYS_rt_sigqueueinfo = x64_syscalls.SYS_rt_sigqueueinfo; // 129
const SYS_rt_sigsuspend = x64_syscalls.SYS_rt_sigsuspend; // 130
const SYS_sigaltstack = x64_syscalls.SYS_sigaltstack; // 131
const SYS_utime = x64_syscalls.SYS_utime; // 132
const SYS_mknod = x64_syscalls.SYS_mknod; // 133
const SYS_uselib = x64_syscalls.SYS_uselib; // 134
const SYS_personality = x64_syscalls.SYS_personality; // 135
const SYS_ustat = x64_syscalls.SYS_ustat; // 136
const SYS_statfs = x64_syscalls.SYS_statfs; // 137
const SYS_fstatfs = x64_syscalls.SYS_fstatfs; // 138
const SYS_sysfs = x64_syscalls.SYS_sysfs; // 139
const SYS_getpriority = x64_syscalls.SYS_getpriority; // 140
const SYS_setpriority = x64_syscalls.SYS_setpriority; // 141
const SYS_sched_setparam = x64_syscalls.SYS_sched_setparam; // 142
const SYS_sched_getparam = x64_syscalls.SYS_sched_getparam; // 143
const SYS_sched_setscheduler = x64_syscalls.SYS_sched_setscheduler; // 144
const SYS_sched_getscheduler = x64_syscalls.SYS_sched_getscheduler; // 145
const SYS_sched_get_priority_max = x64_syscalls.SYS_sched_get_priority_max; // 146
const SYS_sched_get_priority_min = x64_syscalls.SYS_sched_get_priority_min; // 147
const SYS_sched_rr_get_interval = x64_syscalls.SYS_sched_rr_get_interval; // 148
const SYS_mlock = x64_syscalls.SYS_mlock; // 149
const SYS_munlock = x64_syscalls.SYS_munlock; // 150
const SYS_mlockall = x64_syscalls.SYS_mlockall; // 151
const SYS_munlockall = x64_syscalls.SYS_munlockall; // 152
const SYS_vhangup = x64_syscalls.SYS_vhangup; // 153
const SYS_modify_ldt = x64_syscalls.SYS_modify_ldt; // 154
const SYS_pivot_root = x64_syscalls.SYS_pivot_root; // 155
const SYS__sysctl = x64_syscalls.SYS__sysctl; // 156
const SYS_prctl = x64_syscalls.SYS_prctl; // 157
const SYS_arch_prctl = x64_syscalls.SYS_arch_prctl; // 158
const SYS_adjtimex = x64_syscalls.SYS_adjtimex; // 159
const SYS_setrlimit = x64_syscalls.SYS_setrlimit; // 160
const SYS_chroot = x64_syscalls.SYS_chroot; // 161
const SYS_sync = x64_syscalls.SYS_sync; // 162
const SYS_acct = x64_syscalls.SYS_acct; // 163
const SYS_settimeofday = x64_syscalls.SYS_settimeofday; // 164
const SYS_mount = x64_syscalls.SYS_mount; // 165
const SYS_umount2 = x64_syscalls.SYS_umount2; // 166
const SYS_swapon = x64_syscalls.SYS_swapon; // 167
const SYS_swapoff = x64_syscalls.SYS_swapoff; // 168
const SYS_reboot = x64_syscalls.SYS_reboot; // 169
const SYS_sethostname = x64_syscalls.SYS_sethostname; // 170
const SYS_setdomainname = x64_syscalls.SYS_setdomainname; // 171
const SYS_iopl = x64_syscalls.SYS_iopl; // 172
const SYS_ioperm = x64_syscalls.SYS_ioperm; // 173
const SYS_create_module = x64_syscalls.SYS_create_module; // 174
const SYS_init_module = x64_syscalls.SYS_init_module; // 175
const SYS_delete_module = x64_syscalls.SYS_delete_module; // 176
const SYS_get_kernel_syms = x64_syscalls.SYS_get_kernel_syms; // 177
const SYS_query_module = x64_syscalls.SYS_query_module; // 178
const SYS_quotactl = x64_syscalls.SYS_quotactl; // 179
const SYS_nfsservctl = x64_syscalls.SYS_nfsservctl; // 180
const SYS_getpmsg = x64_syscalls.SYS_getpmsg; // 181
const SYS_putpmsg = x64_syscalls.SYS_putpmsg; // 182
const SYS_afs_syscall = x64_syscalls.SYS_afs_syscall; // 183
const SYS_tuxcall = x64_syscalls.SYS_tuxcall; // 184
const SYS_security = x64_syscalls.SYS_security; // 185
const SYS_gettid = x64_syscalls.SYS_gettid; // 186
const SYS_readahead = x64_syscalls.SYS_readahead; // 187
const SYS_setxattr = x64_syscalls.SYS_setxattr; // 188
const SYS_lsetxattr = x64_syscalls.SYS_lsetxattr; // 189
const SYS_fsetxattr = x64_syscalls.SYS_fsetxattr; // 190
const SYS_getxattr = x64_syscalls.SYS_getxattr; // 191
const SYS_lgetxattr = x64_syscalls.SYS_lgetxattr; // 192
const SYS_fgetxattr = x64_syscalls.SYS_fgetxattr; // 193
const SYS_listxattr = x64_syscalls.SYS_listxattr; // 194
const SYS_llistxattr = x64_syscalls.SYS_llistxattr; // 195
const SYS_flistxattr = x64_syscalls.SYS_flistxattr; // 196
const SYS_removexattr = x64_syscalls.SYS_removexattr; // 197
const SYS_lremovexattr = x64_syscalls.SYS_lremovexattr; // 198
const SYS_fremovexattr = x64_syscalls.SYS_fremovexattr; // 199
const SYS_tkill = x64_syscalls.SYS_tkill; // 200
const SYS_time = x64_syscalls.SYS_time; // 201
const SYS_futex = x64_syscalls.SYS_futex; // 202
const SYS_sched_setaffinity = x64_syscalls.SYS_sched_setaffinity; // 203
const SYS_sched_getaffinity = x64_syscalls.SYS_sched_getaffinity; // 204
const SYS_set_thread_area = x64_syscalls.SYS_set_thread_area; // 205
const SYS_io_setup = x64_syscalls.SYS_io_setup; // 206
const SYS_io_destroy = x64_syscalls.SYS_io_destroy; // 207
const SYS_io_getevents = x64_syscalls.SYS_io_getevents; // 208
const SYS_io_submit = x64_syscalls.SYS_io_submit; // 209
const SYS_io_cancel = x64_syscalls.SYS_io_cancel; // 210
const SYS_get_thread_area = x64_syscalls.SYS_get_thread_area; // 211
const SYS_lookup_dcookie = x64_syscalls.SYS_lookup_dcookie; // 212
const SYS_epoll_create = x64_syscalls.SYS_epoll_create; // 213
const SYS_epoll_ctl_old = x64_syscalls.SYS_epoll_ctl_old; // 214
const SYS_epoll_wait_old = x64_syscalls.SYS_epoll_wait_old; // 215
const SYS_remap_file_pages = x64_syscalls.SYS_remap_file_pages; // 216
const SYS_getdents64 = x64_syscalls.SYS_getdents64; // 217
const SYS_set_tid_address = x64_syscalls.SYS_set_tid_address; // 218
const SYS_restart_syscall = x64_syscalls.SYS_restart_syscall; // 219
const SYS_semtimedop = x64_syscalls.SYS_semtimedop; // 220
const SYS_fadvise64 = x64_syscalls.SYS_fadvise64; // 221
const SYS_timer_create = x64_syscalls.SYS_timer_create; // 222
const SYS_timer_settime = x64_syscalls.SYS_timer_settime; // 223
const SYS_timer_gettime = x64_syscalls.SYS_timer_gettime; // 224
const SYS_timer_getoverrun = x64_syscalls.SYS_timer_getoverrun; // 225
const SYS_timer_delete = x64_syscalls.SYS_timer_delete; // 226
const SYS_clock_settime = x64_syscalls.SYS_clock_settime; // 227
const SYS_clock_gettime = x64_syscalls.SYS_clock_gettime; // 228
const SYS_clock_getres = x64_syscalls.SYS_clock_getres; // 229
const SYS_clock_nanosleep = x64_syscalls.SYS_clock_nanosleep; // 230
const SYS_exit_group = x64_syscalls.SYS_exit_group; // 231
const SYS_epoll_wait = x64_syscalls.SYS_epoll_wait; // 232
const SYS_epoll_ctl = x64_syscalls.SYS_epoll_ctl; // 233
const SYS_tgkill = x64_syscalls.SYS_tgkill; // 234
const SYS_utimes = x64_syscalls.SYS_utimes; // 235
const SYS_vserver = x64_syscalls.SYS_vserver; // 236
const SYS_mbind = x64_syscalls.SYS_mbind; // 237
const SYS_set_mempolicy = x64_syscalls.SYS_set_mempolicy; // 238
const SYS_get_mempolicy = x64_syscalls.SYS_get_mempolicy; // 239
const SYS_mq_open = x64_syscalls.SYS_mq_open; // 240
const SYS_mq_unlink = x64_syscalls.SYS_mq_unlink; // 241
const SYS_mq_timedsend = x64_syscalls.SYS_mq_timedsend; // 242
const SYS_mq_timedreceive = x64_syscalls.SYS_mq_timedreceive; // 243
const SYS_mq_notify = x64_syscalls.SYS_mq_notify; // 244
const SYS_mq_getsetattr = x64_syscalls.SYS_mq_getsetattr; // 245
const SYS_kexec_load = x64_syscalls.SYS_kexec_load; // 246
const SYS_waitid = x64_syscalls.SYS_waitid; // 247
const SYS_add_key = x64_syscalls.SYS_add_key; // 248
const SYS_request_key = x64_syscalls.SYS_request_key; // 249
const SYS_keyctl = x64_syscalls.SYS_keyctl; // 250
const SYS_ioprio_set = x64_syscalls.SYS_ioprio_set; // 251
const SYS_ioprio_get = x64_syscalls.SYS_ioprio_get; // 252
const SYS_inotify_init = x64_syscalls.SYS_inotify_init; // 253
const SYS_inotify_add_watch = x64_syscalls.SYS_inotify_add_watch; // 254
const SYS_inotify_rm_watch = x64_syscalls.SYS_inotify_rm_watch; // 255
const SYS_migrate_pages = x64_syscalls.SYS_migrate_pages; // 256
const SYS_openat = x64_syscalls.SYS_openat; // 257
const SYS_mkdirat = x64_syscalls.SYS_mkdirat; // 258
const SYS_mknodat = x64_syscalls.SYS_mknodat; // 259
const SYS_fchownat = x64_syscalls.SYS_fchownat; // 260
const SYS_futimesat = x64_syscalls.SYS_futimesat; // 261
const SYS_newfstatat = x64_syscalls.SYS_newfstatat; // 262
const SYS_unlinkat = x64_syscalls.SYS_unlinkat; // 263
const SYS_renameat = x64_syscalls.SYS_renameat; // 264
const SYS_linkat = x64_syscalls.SYS_linkat; // 265
const SYS_symlinkat = x64_syscalls.SYS_symlinkat; // 266
const SYS_readlinkat = x64_syscalls.SYS_readlinkat; // 267
const SYS_fchmodat = x64_syscalls.SYS_fchmodat; // 268
const SYS_faccessat = x64_syscalls.SYS_faccessat; // 269
const SYS_pselect6 = x64_syscalls.SYS_pselect6; // 270
const SYS_ppoll = x64_syscalls.SYS_ppoll; // 271
const SYS_unshare = x64_syscalls.SYS_unshare; // 272
const SYS_set_robust_list = x64_syscalls.SYS_set_robust_list; // 273
const SYS_get_robust_list = x64_syscalls.SYS_get_robust_list; // 274
const SYS_splice = x64_syscalls.SYS_splice; // 275
const SYS_tee = x64_syscalls.SYS_tee; // 276
const SYS_sync_file_range = x64_syscalls.SYS_sync_file_range; // 277
const SYS_vmsplice = x64_syscalls.SYS_vmsplice; // 278
const SYS_move_pages = x64_syscalls.SYS_move_pages; // 279
const SYS_utimensat = x64_syscalls.SYS_utimensat; // 280
const SYS_epoll_pwait = x64_syscalls.SYS_epoll_pwait; // 281
const SYS_signalfd = x64_syscalls.SYS_signalfd; // 282
const SYS_timerfd_create = x64_syscalls.SYS_timerfd_create; // 283
const SYS_eventfd = x64_syscalls.SYS_eventfd; // 284
const SYS_fallocate = x64_syscalls.SYS_fallocate; // 285
const SYS_timerfd_settime = x64_syscalls.SYS_timerfd_settime; // 286
const SYS_timerfd_gettime = x64_syscalls.SYS_timerfd_gettime; // 287
const SYS_accept4 = x64_syscalls.SYS_accept4; // 288
const SYS_signalfd4 = x64_syscalls.SYS_signalfd4; // 289
const SYS_eventfd2 = x64_syscalls.SYS_eventfd2; // 290
const SYS_epoll_create1 = x64_syscalls.SYS_epoll_create1; // 291
const SYS_dup3 = x64_syscalls.SYS_dup3; // 292
const SYS_pipe2 = x64_syscalls.SYS_pipe2; // 293
const SYS_inotify_init1 = x64_syscalls.SYS_inotify_init1; // 294
const SYS_preadv = x64_syscalls.SYS_preadv; // 295
const SYS_pwritev = x64_syscalls.SYS_pwritev; // 296
const SYS_rt_tgsigqueueinfo = x64_syscalls.SYS_rt_tgsigqueueinfo; // 297
const SYS_perf_event_open = x64_syscalls.SYS_perf_event_open; // 298
const SYS_recvmmsg = x64_syscalls.SYS_recvmmsg; // 299
const SYS_fanotify_init = x64_syscalls.SYS_fanotify_init; // 300
const SYS_fanotify_mark = x64_syscalls.SYS_fanotify_mark; // 301
const SYS_prlimit64 = x64_syscalls.SYS_prlimit64; // 302
const SYS_name_to_handle_at = x64_syscalls.SYS_name_to_handle_at; // 303
const SYS_open_by_handle_at = x64_syscalls.SYS_open_by_handle_at; // 304
const SYS_clock_adjtime = x64_syscalls.SYS_clock_adjtime; // 305
const SYS_syncfs = x64_syscalls.SYS_syncfs; // 306
const SYS_sendmmsg = x64_syscalls.SYS_sendmmsg; // 307
const SYS_setns = x64_syscalls.SYS_setns; // 308
const SYS_getcpu = x64_syscalls.SYS_getcpu; // 309
const SYS_process_vm_readv = x64_syscalls.SYS_process_vm_readv; // 310
const SYS_process_vm_writev = x64_syscalls.SYS_process_vm_writev; // 311
const SYS_kcmp = x64_syscalls.SYS_kcmp; // 312
const SYS_finit_module = x64_syscalls.SYS_finit_module; // 313
const SYS_sched_setattr = x64_syscalls.SYS_sched_setattr; // 314
const SYS_sched_getattr = x64_syscalls.SYS_sched_getattr; // 315
const SYS_renameat2 = x64_syscalls.SYS_renameat2; // 316
const SYS_seccomp = x64_syscalls.SYS_seccomp; // 317
const SYS_getrandom = x64_syscalls.SYS_getrandom; // 318
const SYS_memfd_create = x64_syscalls.SYS_memfd_create; // 319
const SYS_kexec_file_load = x64_syscalls.SYS_kexec_file_load; // 320
const SYS_bpf = x64_syscalls.SYS_bpf; // 321
const SYS_execveat = x64_syscalls.SYS_execveat; // 322
const SYS_userfaultfd = x64_syscalls.SYS_userfaultfd; // 323
const SYS_membarrier = x64_syscalls.SYS_membarrier; // 324
const SYS_mlock2 = x64_syscalls.SYS_mlock2; // 325
const SYS_copy_file_range = x64_syscalls.SYS_copy_file_range; // 326
const SYS_preadv2 = x64_syscalls.SYS_preadv2; // 327
const SYS_pwritev2 = x64_syscalls.SYS_pwritev2; // 328
const SYS_pkey_mprotect = x64_syscalls.SYS_pkey_mprotect; // 329
const SYS_pkey_alloc = x64_syscalls.SYS_pkey_alloc; // 330
const SYS_pkey_free = x64_syscalls.SYS_pkey_free; // 331
const SYS_statx = x64_syscalls.SYS_statx; // 332
const SYS_io_pgetevents = x64_syscalls.SYS_io_pgetevents; // 333
const SYS_rseq = x64_syscalls.SYS_rseq; // 334
const SYS_pidfd_send_signal = x64_syscalls.SYS_pidfd_send_signal; // 424
const SYS_io_uring_setup = x64_syscalls.SYS_io_uring_setup; // 425
const SYS_io_uring_enter = x64_syscalls.SYS_io_uring_enter; // 426
const SYS_io_uring_register = x64_syscalls.SYS_io_uring_register; // 427
const SYS_open_tree = x64_syscalls.SYS_open_tree; // 428
const SYS_move_mount = x64_syscalls.SYS_move_mount; // 429
const SYS_fsopen = x64_syscalls.SYS_fsopen; // 430
const SYS_fsconfig = x64_syscalls.SYS_fsconfig; // 431
const SYS_fsmount = x64_syscalls.SYS_fsmount; // 432
const SYS_fspick = x64_syscalls.SYS_fspick; // 433
const SYS_pidfd_open = x64_syscalls.SYS_pidfd_open; // 434
const SYS_clone3 = x64_syscalls.SYS_clone3; // 435
const SYS_close_range = x64_syscalls.SYS_close_range; // 436
const SYS_openat2 = x64_syscalls.SYS_openat2; // 437
const SYS_pidfd_getfd = x64_syscalls.SYS_pidfd_getfd; // 438
const SYS_faccessat2 = x64_syscalls.SYS_faccessat2; // 439
const SYS_process_madvise = x64_syscalls.SYS_process_madvise; // 440
const SYS_epoll_pwait2 = x64_syscalls.SYS_epoll_pwait2; // 441
const SYS_mount_setattr = x64_syscalls.SYS_mount_setattr; // 442
const SYS_quotactl_fd = x64_syscalls.SYS_quotactl_fd; // 443
const SYS_landlock_create_ruleset = x64_syscalls.SYS_landlock_create_ruleset; // 444
const SYS_landlock_add_rule = x64_syscalls.SYS_landlock_add_rule; // 445
const SYS_landlock_restrict_self = x64_syscalls.SYS_landlock_restrict_self; // 446
const SYS_memfd_secret = x64_syscalls.SYS_memfd_secret; // 447
const SYS_process_mrelease = x64_syscalls.SYS_process_mrelease; // 448
const SYS_futex_waitv = x64_syscalls.SYS_futex_waitv; // 449
const SYS_set_mempolicy_home_node = x64_syscalls.SYS_set_mempolicy_home_node; // 450
const SYS_cachestat = x64_syscalls.SYS_cachestat; // 451
const SYS_fchmodat2 = x64_syscalls.SYS_fchmodat2; // 452
const SYS_map_shadow_stack = x64_syscalls.SYS_map_shadow_stack; // 453
const SYS_futex_wake = x64_syscalls.SYS_futex_wake; // 454
const SYS_futex_wait = x64_syscalls.SYS_futex_wait; // 455
const SYS_futex_requeue = x64_syscalls.SYS_futex_requeue; // 456
const SYS_statmount = x64_syscalls.SYS_statmount; // 457
const SYS_listmount = x64_syscalls.SYS_listmount; // 458
const SYS_lsm_get_self_attr = x64_syscalls.SYS_lsm_get_self_attr; // 459
const SYS_lsm_set_self_attr = x64_syscalls.SYS_lsm_set_self_attr; // 460
const SYS_lsm_list_modules = x64_syscalls.SYS_lsm_list_modules; // 461
const SYS_mseal = x64_syscalls.SYS_mseal; // 462
const SYS_setxattrat = x64_syscalls.SYS_setxattrat; // 463
const SYS_getxattrat = x64_syscalls.SYS_getxattrat; // 464
const SYS_listxattrat = x64_syscalls.SYS_listxattrat; // 465
const SYS_removexattrat = x64_syscalls.SYS_removexattrat; // 466

// ─── RFLAGS bit positions ───
const RFL_CF = x64_decoder.RFL_CF;
const RFL_PF = x64_decoder.RFL_PF;
const RFL_AF = x64_decoder.RFL_AF;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;
const RFL_DF: u32 = 1 << 10;

const STACK_SIZE: u64 = 1024 * 1024; // 1 MB stack
const MEM_SIZE: u64 = 64 * 1024 * 1024; // 64 MB total address space
const MEM_BASE: u64 = 0x1000000;
const SYNTHETIC_INIT_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF00;
const SYNTHETIC_MAIN_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF08;
const TRACE_BUFFER_LEN: usize = 256;
const MAX_WINDOWS_IMPORT_STUBS: usize = 8192;
const MAX_WINDOWS_FILE_HANDLES: usize = 256;
const MAX_WINDOWS_FIND_HANDLES: usize = 64;
const MAX_WINDOWS_FILE_MAPPINGS: usize = 16;
const MAX_WINDOWS_MEMORY_VIEWS: usize = 64;
const MAX_WINDOWS_VIRTUAL_ALLOCATIONS: usize = 64;
const MAX_WINDOWS_HEAP_ALLOCATIONS: usize = 65536;
const MAX_WINDOWS_INITTERM_FRAMES: usize = 16;
const MAX_WINDOWS_INITTERM_ENTRIES: u64 = 1 << 20;
const MAX_WINDOWS_GUEST_THREADS: usize = 32;
const WINDOWS_TLS_SLOT_COUNT: usize = 512;
const WINDOWS_GUEST_THREAD_STACK_SIZE: u64 = 1024 * 1024;
const WINDOWS_GUEST_THREAD_MAX_STACK_SIZE: u64 = 8 * 1024 * 1024;
const WINDOWS_PAGE_SIZE: u64 = 0x1000;
const WINDOWS_TEB_BYTES: u64 = 0x2000;
const WINDOWS_TLS_BLOCK_BYTES: u64 = 0x11000;
const WINDOWS_TEB_STACK_BASE_OFFSET: u64 = 0x08;
const WINDOWS_TEB_STACK_LIMIT_OFFSET: u64 = 0x10;
const WINDOWS_TEB_SELF_OFFSET: u64 = 0x30;
const WINDOWS_TEB_CLIENT_ID_PROCESS_OFFSET: u64 = 0x40;
const WINDOWS_TEB_CLIENT_ID_THREAD_OFFSET: u64 = 0x48;
const WINDOWS_TEB_TLS_POINTER_OFFSET: u64 = 0x58;
const WINDOWS_TEB_PEB_OFFSET: u64 = 0x60;
const WINDOWS_TEB_LAST_ERROR_OFFSET: u64 = 0x68;
// Keep a worker slice short enough that a startup worker cannot monopolize
// the single interpreter while the owner thread is waiting for it to publish
// state. This is a scheduling bound, not a correctness timeout: the worker
// context is saved and resumed at the next explicit cooperative point.
const WINDOWS_GUEST_THREAD_SERVICE_SLICE: u64 = 10_000;
const WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE: u64 = 10_000;
// A Windows x64 callee receives a return address at [RSP] and owns the
// caller-provided 32-byte home area immediately above it.  The synthetic
// thread entry used to put RSP at the very end of the allocated stack, which
// made a legal store to [RBP+0x10] land in the next guest heap allocation.
// Keep a small entry cushion inside the allocation so the home area and the
// first stack arguments never cross the stack/heap boundary.
const WINDOWS_GUEST_THREAD_ENTRY_RESERVE: u64 = 0x100;
const SYNTHETIC_WINDOWS_THREAD_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF28;
const SYNTHETIC_WINDOWS_MESSAGE_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF30;
const MAX_WINDOWS_WINDOW_CLASSES: usize = 64;
const MAX_WINDOWS_WINDOWS: usize = 128;
const MAX_WINDOWS_MESSAGES: usize = 512;
const MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES: usize = 8;
pub const WINDOWS_UNRESOLVED_IMPORT_CAPACITY: usize = 32;
/// Win32 WM_PAINT.  The pump synthesizes it from a window's update region
/// instead of holding it in the posted-message ring, matching Win32.
const WINDOWS_WM_PAINT: u32 = 0x000F;

const WINDOWS_GWLP_USERDATA: i64 = -21;
const WINDOWS_GWL_STYLE: i64 = -16;
const WINDOWS_GWL_EXSTYLE: i64 = -20;
const WINDOWS_GCLP_WNDPROC: i64 = -24;

/// Rosette-owned targets returned by a PE import or proc-address query. The
/// target is kept in the emulated state so an indirect call can be routed back
/// to the Windows ABI without modifying the inspected executable.
pub const WindowsImportStub = struct {
    address: u64,
    dll_name: []const u8,
    function_name: []const u8,
    /// Dynamic GetProcAddress results are kept distinct from the PE's direct
    /// IAT descriptors.  The distinction is diagnostic only; both paths use
    /// the same ABI dispatcher and fallback policy.
    is_dynamic: bool = false,
};

/// A bounded, value-only record for an import Rosetta could not resolve.
///
/// These records deliberately own their text.  The PE parser and dynamic
/// import table are allocator-backed state that is torn down immediately
/// after `RunResult` is produced, while the detailed runner log is written
/// afterwards.  Keeping the first context and the latest repetition context
/// here lets the log explain both the missing symbol and the guest edge that
/// requested it without enabling noisy ABI tracing for every successful call.
pub const WindowsUnresolvedImport = struct {
    dll_name: [128]u8 = [_]u8{0} ** 128,
    dll_name_len: usize = 0,
    function_name: [256]u8 = [_]u8{0} ** 256,
    function_name_len: usize = 0,
    is_dynamic: bool = false,
    stub_address: u64 = 0,
    first_return_rip: u64 = 0,
    first_caller_rip: u64 = 0,
    first_step: u64 = 0,
    first_rsp: u64 = 0,
    first_rcx: u64 = 0,
    first_rdx: u64 = 0,
    first_r8: u64 = 0,
    first_r9: u64 = 0,
    last_return_rip: u64 = 0,
    last_caller_rip: u64 = 0,
    last_step: u64 = 0,
    occurrences: u64 = 0,

    pub fn dllName(self: *const WindowsUnresolvedImport) []const u8 {
        return self.dll_name[0..self.dll_name_len];
    }

    pub fn functionName(self: *const WindowsUnresolvedImport) []const u8 {
        return self.function_name[0..self.function_name_len];
    }
};

/// Host file resources owned by a PE run. The guest sees only the synthetic
/// handle; the native descriptor remains behind the Rosetta boundary and is
/// closed with the execution state. Offsets are kept explicitly because
/// ReadFile/WriteFile use the Windows current-file-pointer contract.
pub const WindowsFileSlot = struct {
    guest_handle: u64 = 0,
    stdio_fd: u32 = 0,
    file: ?std.Io.File = null,
    offset: u64 = 0,
    readable: bool = false,
    writable: bool = false,
};

/// A page-file-backed mapping object created by a Windows PE import.  The
/// guest receives only the synthetic handle; the backing store is a lazily
/// committed host mapping so a request for Xenia's 4 GiB + physical aperture
/// does not require eagerly materializing every byte.
pub const WindowsFileMapping = struct {
    guest_handle: u64 = 0,
    length: u64 = 0,
    backing: ?[]align(std.heap.page_size_min) u8 = null,
    closed: bool = false,
};

/// One MapViewOfFile/MapViewOfFileEx alias.  Xenia deliberately maps several
/// disjoint guest ranges to different offsets of one mapping object, so a
/// single flat PE heap cannot represent this contract.  The interpreter
/// resolves these aliases only when an address is outside its ordinary PE
/// image/stack range.
pub const WindowsMemoryView = struct {
    guest_base: u64 = 0,
    length: u64 = 0,
    mapping_index: usize = 0,
    backing_offset: u64 = 0,
};

/// A fixed anonymous VirtualAlloc range.  Xenia uses these ranges for native
/// bookkeeping outside the page-file mapping, most importantly the code
/// cache indirection table at 0x80000000.  The host backing remains sparse;
/// the guest address and allocation lifetime are what the PE contract needs.
pub const WindowsVirtualAllocation = struct {
    guest_base: u64 = 0,
    length: u64 = 0,
    backing: ?[]align(std.heap.page_size_min) u8 = null,
};

/// Provenance for one allocation returned by the PE guest heap.  The PE
/// runtime must implement realloc as a content-preserving operation, but a
/// bump allocator alone does not retain the old block's size.  Keep records
/// in allocation-address order so lookups are logarithmic even when a
/// startup path performs thousands of malloc/free calls.  Freed records keep
/// their address as tombstones; preserving order makes later lookups safe.
pub const WindowsHeapAllocation = struct {
    guest_base: u64 = 0,
    length: u64 = 0,
    active: bool = false,
};

/// State for a bounded FindFirstFile/FindNextFile enumeration. The iterator
/// owns a host directory handle, while the wildcard is copied into fixed
/// storage so no guest pointer survives an import call.
pub const WindowsFindSlot = struct {
    guest_handle: u64 = 0,
    dir: ?std.Io.Dir = null,
    iterator: ?std.Io.Dir.Iterator = null,
    directory: [std.fs.max_path_bytes]u8 = [_]u8{0} ** std.fs.max_path_bytes,
    directory_len: usize = 0,
    pattern: [256]u8 = [_]u8{0} ** 256,
    pattern_len: usize = 0,
    wide: bool = false,
};

/// State for one active Microsoft CRT initializer-table walk. Initializers
/// are guest functions, not host callbacks: a synthetic guest return marker
/// lets the normal instruction executor run each callback and then resume the
/// table walk. Keeping frames in the guest state also makes nested `_initterm`
/// calls safe (some C++ runtime setup paths initialize another subsystem).
const WindowsInitTermFrame = struct {
    begin: u64,
    end: u64,
    return_rip: u64,
    return_is_direct: bool,
    returns_error: bool,
    callback_count: u64 = 0,
};

/// A Windows thread is guest execution state, not merely a successful handle
/// returned by CreateThread.  The PE runner is cooperative (there is one host
/// interpreter), so a runnable thread is saved here and serviced at explicit
/// yield points such as GetMessageW.  Keep the complete architectural state in
/// the snapshot: Xenia's thread wrapper uses AVX registers and x87 state while
/// constructing the graphics workers, and dropping either set would make a
/// context switch look like a random graphics or allocator failure.
const WindowsGuestThreadContext = struct {
    regs: ElfRegs = .{},
    xmm: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    ymm_hi: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    zmm_hi: [32][32]u8 = [_][32]u8{[_]u8{0} ** 32} ** 32,
    k: [8]u64 = [_]u64{0xFFFF_FFFF_FFFF_FFFF} ** 8,
    x87_stack: [8]X87Raw = [_]X87Raw{[_]u8{0} ** 10} ** 8,
    x87_tags: [8]bool = [_]bool{false} ** 8,
    x87_top: u3 = 0,
    x87_status: u16 = 0,
    x87_control: u16 = 0x037F,
    tls_values: [WINDOWS_TLS_SLOT_COUNT]u64 = [_]u64{0} ** WINDOWS_TLS_SLOT_COUNT,
    windows_last_error: u32 = 0,
    windows_errno_storage: u64 = 0,
    call_stack_depth: usize = 0,
    active_guest_thread: u64 = 0,
    active_idle_source: u64 = 0,
    last_decoded_op: Op = .invalid,
    last_decoded_len: u8 = 0,
};

const WindowsGuestThreadEnvironment = struct {
    teb: u64,
    tls_block: u64,
};

const WindowsGuestThreadStatus = enum(u8) {
    vacant,
    pending,
    runnable,
    running,
    completed,
    failed,
};

const WindowsGuestThread = struct {
    status: WindowsGuestThreadStatus = .vacant,
    handle: u64 = 0,
    start_routine: u64 = 0,
    argument: u64 = 0,
    thread_id: u64 = 0,
    stack_base: u64 = 0,
    stack_size: u64 = 0,
    synthetic_return_slot: u64 = 0,
    teb: u64 = 0,
    tls_block: u64 = 0,
    preferred: bool = false,
    executed_steps: u64 = 0,
    context: WindowsGuestThreadContext = .{},
};

/// One sample of everything a PE run can be observed making progress on.
///
/// Nothing here is title-specific: these are the boundaries Rosetta itself
/// owns, so a guest that is doing anything Rosetta can see moves at least one
/// of them.  A stall is declared only when every axis is frozen together --
/// a single frozen axis is a phase, not a defect.
const WindowsProgressSample = struct {
    import_calls: u64 = 0,
    graphics_calls: u64 = 0,
    graphics_frames: u64 = 0,
    message_traffic: u64 = 0,
    paint_traffic: u64 = 0,
    worker_traffic: u64 = 0,
    file_traffic: u64 = 0,
    /// Packed count of workers in each state, so a thread starting or ending
    /// counts as progress even when it does no instrumented work.
    worker_states: u64 = 0,
    /// The lowest and highest RIP the run visited during the sample window.
    /// A guest looping over a handful of addresses has a tiny span; one that
    /// is genuinely working walks the image.
    rip_low: u64 = 0,
    rip_high: u64 = 0,

    fn matches(self: WindowsProgressSample, other: WindowsProgressSample) bool {
        return self.import_calls == other.import_calls and
            self.graphics_calls == other.graphics_calls and
            self.graphics_frames == other.graphics_frames and
            self.message_traffic == other.message_traffic and
            self.paint_traffic == other.paint_traffic and
            self.worker_traffic == other.worker_traffic and
            self.file_traffic == other.file_traffic and
            self.worker_states == other.worker_states and
            self.rip_low == other.rip_low and
            self.rip_high == other.rip_high;
    }
};

/// Watchdog state for the progress sampler.  Default-off numbers are chosen
/// so a healthy run never reaches the reporting path: the sampler only costs
/// two comparisons per step and one counter comparison per window.
const WindowsProgressWatchdog = struct {
    enabled: bool = true,
    /// Steps between samples.
    interval: u64 = 2_000_000,
    /// Consecutive identical samples before a stall is declared.
    threshold: u32 = 8,
    next_sample_step: u64 = 0,
    previous: WindowsProgressSample = .{},
    have_previous: bool = false,
    frozen_samples: u32 = 0,
    /// Frozen-sample count at which the next report is emitted.  Doubles
    /// after each report so a long stall leaves a heartbeat instead of a
    /// flood.
    next_report_at: u32 = 0,
    reported: bool = false,
    episodes: u64 = 0,
    /// RIP extremes for the window currently being accumulated.
    window_rip_low: u64 = std.math.maxInt(u64),
    window_rip_high: u64 = 0,
    /// Workers unblocked by the starvation backstop.
    backstop_services: u64 = 0,
};

/// The bounded guest-side Win32 message queue.  A PE run has one interpreter,
/// so a host queue or native HWND cannot be used as the synchronization
/// authority: PostMessage must publish a message that the guest GetMessage
/// call can later remove and DispatchMessage can deliver to guest code.
pub const WindowsMessage = struct {
    hwnd: u64 = 0,
    message: u32 = 0,
    wparam: u64 = 0,
    lparam: u64 = 0,
};

const WindowsWindowClass = struct {
    valid: bool = false,
    atom: u16 = 0,
    wnd_proc: u64 = 0,
    name_ptr: u64 = 0,
    name_len: usize = 0,
    name: [128]u8 = [_]u8{0} ** 128,
    wide: bool = false,
};

const WindowsWindow = struct {
    valid: bool = false,
    handle: u64 = 0,
    class_atom: u16 = 0,
    wnd_proc: u64 = 0,
    user_data: u64 = 0,
    style: u32 = 0,
    ex_style: u32 = 0,
    message_only: bool = false,
    /// Win32 does not queue WM_PAINT.  It keeps a per-window update region
    /// and synthesizes WM_PAINT inside GetMessage/PeekMessage for as long as
    /// that region is non-empty.  A guest that paints through
    /// InvalidateRect + WM_PAINT (the normal Win32 idiom) never repaints if
    /// the update region is not modelled, so retain it here.
    update_region_pending: bool = false,
};

const WindowsMessageDispatchFrame = struct {
    return_rip: u64 = 0,
    return_rsp: u64 = 0,
    return_is_direct: bool = false,
};

/// Host operations the PE runner may use while translating a Windows UI.
///
/// The callbacks are deliberately tiny C-ABI seams.  The x86-64 state owns
/// all guest handles and Vulkan objects; a host callback can only report
/// whether Rosetta's native window boundary was reached.  In particular,
/// this type never exposes an AppKit pointer or a host Vulkan handle to the
/// guest address space.
pub const WindowsGraphicsHooks = struct {
    context: ?*anyopaque = null,
    ensure_application: ?*const fn (?*anyopaque) callconv(.c) c_int = null,
    ensure_window: ?*const fn (?*anyopaque, u32, u32, [*:0]const u8) callconv(.c) c_int = null,
    show_window: ?*const fn (?*anyopaque) callconv(.c) c_int = null,
    pump_events: ?*const fn (?*anyopaque) callconv(.c) u32 = null,
    /// A separate context is intentional: the native presenter owns host
    /// Vulkan objects while the window callbacks own the native UI boundary.
    /// Neither context is ever written into guest memory.
    native_context: ?*anyopaque = null,
    native_presenter_start: ?*const fn (?*anyopaque, u32, u32) callconv(.c) c_int = null,
    native_presenter_stage: ?*const fn (?*anyopaque) callconv(.c) u32 = null,
    native_presenter_is_ready: ?*const fn (?*anyopaque) callconv(.c) c_int = null,
    native_presenter_present_diagnostic: ?*const fn (?*anyopaque, u64, u32, u32, u32) callconv(.c) u64 = null,
    /// Optional real Vulkan dispatch supplied by the host-side Windows route.
    /// The callback receives the PE state as an opaque pointer and a bounded
    /// function-name slice. It may adapt the Microsoft x64 call into a native
    /// Rosetta forwarder, but it cannot pass a host pointer into guest memory.
    native_vulkan_dispatch: ?*const fn (?*anyopaque, *anyopaque, [*]const u8, usize, u64, c_int) callconv(.c) c_int = null,
    /// Return the host CAMetalLayer currently owned by the native window. The
    /// value is used only inside Rosetta's host Vulkan create-info and is never
    /// materialized as a guest handle.
    native_metal_layer_host_pointer: ?*const fn (?*anyopaque) callconv(.c) usize = null,
};

pub const WindowsGraphicsPhase = enum(u8) {
    cold,
    window_ready,
    instance_ready,
    surface_ready,
    device_ready,
    queue_ready,
    swapchain_ready,
    frame_resources_ready,
    present_ready,
    failed,
};

/// Win32 uses this value for position and size arguments that the window
/// manager should choose. It is not a usable Cocoa width or height. Keep the
/// policy in the guest graphics ledger so every Windows entry path agrees on
/// what can cross into the native window bridge.
pub const WINDOWS_CW_USEDEFAULT: u64 = 0x8000_0000;
pub const WINDOWS_DEFAULT_WIDTH: u32 = 1280;
pub const WINDOWS_DEFAULT_HEIGHT: u32 = 720;
pub const WINDOWS_MAX_DIMENSION: u64 = 16 * 1024;

fn normalizeWindowsWindowDimension(value: u64, fallback: u32) u32 {
    if (value == 0 or value == WINDOWS_CW_USEDEFAULT or value > WINDOWS_MAX_DIMENSION) {
        return fallback;
    }
    return @intCast(value);
}

/// A value-only report returned from a PE run.  It distinguishes a native
/// window from a real Vulkan frame: the current Rosetta Windows bridge owns a
/// native Cocoa/Metal window, but Vulkan calls are still logical guest calls
/// until a native Vulkan forwarding backend is installed.
pub const WindowsGraphicsSnapshot = struct {
    phase: WindowsGraphicsPhase = .cold,
    application_ready: bool = false,
    window_ready: bool = false,
    native_window_ready: bool = false,
    native_window_visible: bool = false,
    instance_ready: bool = false,
    surface_ready: bool = false,
    device_ready: bool = false,
    queue_ready: bool = false,
    swapchain_ready: bool = false,
    frame_resources_ready: bool = false,
    guest_present_observed: bool = false,
    native_vulkan_forwarding: bool = false,
    native_vulkan_calls: u64 = 0,
    native_vulkan_failures: u64 = 0,
    native_presenter_started: bool = false,
    native_presenter_ready: bool = false,
    native_presenter_stage: u32 = 0,
    native_presenter_attempts: u64 = 0,
    native_presenter_failures: u64 = 0,
    native_diagnostic_attempts: u64 = 0,
    native_diagnostic_frames: u64 = 0,
    native_diagnostic_failures: u64 = 0,
    window_create_attempts: u64 = 0,
    window_create_failures: u64 = 0,
    application_attempts: u64 = 0,
    show_attempts: u64 = 0,
    event_pump_calls: u64 = 0,
    vulkan_calls: u64 = 0,
    proc_queries: u64 = 0,
    instance_creations: u64 = 0,
    surface_creations: u64 = 0,
    device_creations: u64 = 0,
    queue_acquisitions: u64 = 0,
    swapchain_creations: u64 = 0,
    swapchain_image_queries: u64 = 0,
    image_acquires: u64 = 0,
    command_calls: u64 = 0,
    queue_submits: u64 = 0,
    presents: u64 = 0,
    ordering_violations: u64 = 0,
    unmodeled_calls: u64 = 0,
    window_width: u32 = 1280,
    window_height: u32 = 720,
    last_call: [64:0]u8 = [_:0]u8{0} ** 64,
    last_failure: [96:0]u8 = [_:0]u8{0} ** 96,

    pub fn contractReady(self: *const WindowsGraphicsSnapshot) bool {
        return self.window_ready and self.instance_ready and self.surface_ready and
            self.device_ready and self.queue_ready and self.swapchain_ready and
            self.frame_resources_ready and self.ordering_violations == 0;
    }

    pub fn nativeWindowReady(self: *const WindowsGraphicsSnapshot) bool {
        return self.native_window_ready and self.native_window_visible;
    }

    pub fn nativePresenterReady(self: *const WindowsGraphicsSnapshot) bool {
        return self.native_presenter_ready;
    }
};

/// State machine for the Windows UI/Vulkan contract.
///
/// Previous Windows imports returned success independently of one another, so
/// a PE could appear to have initialized graphics while no window, surface,
/// queue, or swapchain had ever been established.  This ledger makes every
/// transition observable and rejects impossible Vulkan ordering at the guest
/// ABI boundary.  It is intentionally backend-neutral; only the window
/// callbacks are host-facing in this pass.
pub const WindowsGraphicsState = struct {
    hooks: WindowsGraphicsHooks = .{},
    phase: WindowsGraphicsPhase = .cold,
    application_ready: bool = false,
    window_ready: bool = false,
    native_window_ready: bool = false,
    native_window_visible: bool = false,
    instance_ready: bool = false,
    surface_ready: bool = false,
    device_ready: bool = false,
    queue_ready: bool = false,
    swapchain_ready: bool = false,
    frame_resources_ready: bool = false,
    guest_present_observed: bool = false,
    native_vulkan_forwarding: bool = false,
    native_vulkan_calls: u64 = 0,
    native_vulkan_failures: u64 = 0,
    native_presenter_started: bool = false,
    native_presenter_ready: bool = false,
    native_presenter_stage: u32 = 0,
    native_presenter_attempts: u64 = 0,
    native_presenter_failures: u64 = 0,
    native_diagnostic_attempts: u64 = 0,
    native_diagnostic_frames: u64 = 0,
    native_diagnostic_failures: u64 = 0,
    window_create_attempts: u64 = 0,
    window_create_failures: u64 = 0,
    application_attempts: u64 = 0,
    show_attempts: u64 = 0,
    event_pump_calls: u64 = 0,
    vulkan_calls: u64 = 0,
    proc_queries: u64 = 0,
    instance_creations: u64 = 0,
    surface_creations: u64 = 0,
    device_creations: u64 = 0,
    queue_acquisitions: u64 = 0,
    swapchain_creations: u64 = 0,
    swapchain_image_queries: u64 = 0,
    image_acquires: u64 = 0,
    command_calls: u64 = 0,
    queue_submits: u64 = 0,
    presents: u64 = 0,
    ordering_violations: u64 = 0,
    unmodeled_calls: u64 = 0,
    window_width: u32 = 1280,
    window_height: u32 = 720,
    last_call: [64:0]u8 = [_:0]u8{0} ** 64,
    last_failure: [96:0]u8 = [_:0]u8{0} ** 96,

    fn copyLabel(destination: []u8, source: []const u8) void {
        @memset(destination, 0);
        const count = @min(source.len, destination.len - 1);
        @memcpy(destination[0..count], source[0..count]);
    }

    fn noteCall(self: *WindowsGraphicsState, name: []const u8) void {
        self.vulkan_calls +|= 1;
        copyLabel(&self.last_call, name);
    }

    fn advance(self: *WindowsGraphicsState, phase: WindowsGraphicsPhase) void {
        if (self.phase == .failed) return;
        if (@intFromEnum(phase) > @intFromEnum(self.phase)) self.phase = phase;
    }

    fn violation(self: *WindowsGraphicsState, name: []const u8, reason: []const u8) void {
        self.ordering_violations +|= 1;
        self.phase = .failed;
        var label_buf: [96]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{s}: {s}", .{ name, reason }) catch reason;
        copyLabel(&self.last_failure, label);
    }

    pub fn ensureApplication(self: *WindowsGraphicsState) bool {
        self.application_attempts +|= 1;
        if (self.application_ready) return true;
        if (self.hooks.ensure_application) |callback| {
            self.native_window_ready = callback(self.hooks.context) != 0;
            if (!self.native_window_ready) return false;
        }
        self.application_ready = true;
        return true;
    }

    pub fn ensureWindow(self: *WindowsGraphicsState, width: u64, height: u64, title: []const u8) bool {
        self.window_create_attempts +|= 1;
        self.window_width = normalizeWindowsWindowDimension(width, WINDOWS_DEFAULT_WIDTH);
        self.window_height = normalizeWindowsWindowDimension(height, WINDOWS_DEFAULT_HEIGHT);
        if (!self.ensureApplication()) {
            self.window_create_failures +|= 1;
            return false;
        }

        var title_buffer: [256:0]u8 = [_:0]u8{0} ** 256;
        copyLabel(&title_buffer, title);
        var ok = true;
        if (self.hooks.ensure_window) |callback| {
            ok = callback(self.hooks.context, self.window_width, self.window_height, &title_buffer) != 0;
            self.native_window_ready = ok;
        }
        if (!ok) {
            self.window_create_failures +|= 1;
            return false;
        }
        self.window_ready = true;
        self.advance(.window_ready);
        return true;
    }

    pub fn showWindow(self: *WindowsGraphicsState) bool {
        self.show_attempts +|= 1;
        if (!self.window_ready) {
            self.violation("ShowWindow", "window was not created");
            return false;
        }
        var ok = true;
        if (self.hooks.show_window) |callback| {
            ok = callback(self.hooks.context) != 0;
            self.native_window_visible = ok;
        }
        if (!ok) return false;
        if (self.hooks.show_window == null) self.native_window_visible = false;
        return true;
    }

    pub fn pumpEvents(self: *WindowsGraphicsState) u32 {
        self.event_pump_calls +|= 1;
        if (self.hooks.pump_events) |callback| return callback(self.hooks.context);
        return 0;
    }

    pub fn noteProcAddressQuery(self: *WindowsGraphicsState, name: []const u8) void {
        self.proc_queries +|= 1;
        self.noteCall(name);
    }

    pub fn noteObservedCall(self: *WindowsGraphicsState, name: []const u8) void {
        self.noteCall(name);
    }

    /// Record that a Vulkan entry crossed the Rosetta-owned native adapter.
    /// `host_objects_ready` is deliberately separate from dispatch count:
    /// reaching a bridge callback proves the adapter was selected, while a
    /// real instance/device proves the host driver accepted the ownership
    /// boundary.
    pub fn noteNativeVulkanForwarded(self: *WindowsGraphicsState, name: []const u8, host_objects_ready: bool) void {
        self.native_vulkan_calls +|= 1;
        self.noteCall(name);
        if (host_objects_ready) {
            self.native_vulkan_forwarding = true;
        } else {
            self.native_vulkan_failures +|= 1;
        }
    }

    pub fn noteUnmodeledCall(self: *WindowsGraphicsState, name: []const u8) void {
        self.unmodeled_calls +|= 1;
        self.noteCall(name);
    }

    pub fn noteCreateInstance(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkCreateInstance");
        self.instance_creations +|= 1;
        if (!ok) return false;
        self.instance_ready = true;
        self.advance(.instance_ready);
        return true;
    }

    pub fn noteCreateSurface(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkCreateWin32SurfaceKHR");
        self.surface_creations +|= 1;
        if (!self.instance_ready) {
            self.violation("vkCreateWin32SurfaceKHR", "Vulkan instance is not ready");
            return false;
        }
        if (!self.window_ready) {
            self.violation("vkCreateWin32SurfaceKHR", "Win32 window is not ready");
            return false;
        }
        if (!ok) return false;
        self.surface_ready = true;
        self.advance(.surface_ready);
        // A native guest Vulkan forwarder already owns the guest instance,
        // surface, device, and queue on this route. Starting the diagnostic
        // presenter as well would create a second Vulkan object graph against
        // the same CAMetalLayer and could make a healthy guest submission look
        // like a presenter failure. Keep the diagnostic presenter as the
        // explicit fallback for the modelled/synthetic route only.
        if (!self.native_vulkan_forwarding) self.startNativePresenter();
        return true;
    }

    /// Start the host presenter only after the guest has established the
    /// logical Win32 surface.  Failure is deliberately degraded rather than
    /// turned into a logical Vulkan success: the snapshot carries both facts
    /// so callers can distinguish "guest asked for a surface" from "native
    /// Vulkan can actually present".
    fn startNativePresenter(self: *WindowsGraphicsState) void {
        if (self.native_presenter_started) return;
        const callback = self.hooks.native_presenter_start orelse return;
        self.native_presenter_started = true;
        self.native_presenter_attempts +|= 1;
        const ok = callback(
            self.hooks.native_context,
            self.window_width,
            self.window_height,
        ) != 0;
        self.native_presenter_ready = ok;
        if (!ok) self.native_presenter_failures +|= 1;
        self.updateNativePresenterStage();
    }

    fn updateNativePresenterStage(self: *WindowsGraphicsState) void {
        if (self.hooks.native_presenter_stage) |callback| {
            self.native_presenter_stage = callback(self.hooks.native_context);
        }
        if (self.hooks.native_presenter_is_ready) |callback| {
            self.native_presenter_ready = callback(self.hooks.native_context) != 0;
        }
    }

    pub fn noteCreateDevice(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkCreateDevice");
        self.device_creations +|= 1;
        if (!self.instance_ready) {
            self.violation("vkCreateDevice", "Vulkan instance is not ready");
            return false;
        }
        if (!ok) return false;
        self.device_ready = true;
        self.advance(.device_ready);
        return true;
    }

    pub fn noteGetQueue(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkGetDeviceQueue");
        self.queue_acquisitions +|= 1;
        if (!self.device_ready) {
            self.violation("vkGetDeviceQueue", "logical device is not ready");
            return false;
        }
        if (!ok) return false;
        self.queue_ready = true;
        self.advance(.queue_ready);
        return true;
    }

    pub fn noteCreateSwapchain(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkCreateSwapchainKHR");
        self.swapchain_creations +|= 1;
        if (!self.device_ready or !self.surface_ready) {
            self.violation("vkCreateSwapchainKHR", "device and surface are both required");
            return false;
        }
        if (!ok) return false;
        self.swapchain_ready = true;
        self.advance(.swapchain_ready);
        return true;
    }

    pub fn noteSwapchainImages(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkGetSwapchainImagesKHR");
        self.swapchain_image_queries +|= 1;
        if (!self.swapchain_ready) {
            self.violation("vkGetSwapchainImagesKHR", "swapchain is not ready");
            return false;
        }
        if (!ok) return false;
        self.frame_resources_ready = true;
        self.advance(.frame_resources_ready);
        return true;
    }

    pub fn noteAcquire(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkAcquireNextImageKHR");
        self.image_acquires +|= 1;
        if (!self.swapchain_ready) {
            self.violation("vkAcquireNextImageKHR", "swapchain is not ready");
            return false;
        }
        return ok;
    }

    pub fn noteCommand(self: *WindowsGraphicsState, name: []const u8) void {
        self.command_calls +|= 1;
        self.noteCall(name);
    }

    pub fn noteQueueSubmit(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkQueueSubmit");
        self.queue_submits +|= 1;
        if (!self.queue_ready) {
            self.violation("vkQueueSubmit", "graphics queue is not ready");
            return false;
        }
        return ok;
    }

    pub fn notePresent(self: *WindowsGraphicsState, ok: bool) bool {
        self.noteCall("vkQueuePresentKHR");
        self.presents +|= 1;
        if (!self.queue_ready or !self.swapchain_ready or !self.frame_resources_ready) {
            self.violation("vkQueuePresentKHR", "queue, swapchain, and frame resources are required");
            return false;
        }
        if (!ok) return false;
        self.guest_present_observed = true;
        self.advance(.present_ready);
        // A real guest queue-present is already the evidence we want. The
        // host-generated clear is reserved for the synthetic fallback and is
        // never emitted alongside native guest forwarding.
        if (!self.native_vulkan_forwarding) self.noteNativeDiagnostic();
        return true;
    }

    /// Ask the native presenter for one host-generated liveness frame after a
    /// logical guest present.  This is not guest output and never toggles the
    /// native forwarding bit; it proves only that the host Vulkan/Metal
    /// presentation chain is alive at the time the guest reached present.
    fn noteNativeDiagnostic(self: *WindowsGraphicsState) void {
        if (!self.native_presenter_ready) return;
        const callback = self.hooks.native_presenter_present_diagnostic orelse return;
        self.native_diagnostic_attempts +|= 1;
        const before = self.native_diagnostic_frames;
        const reported = callback(
            self.hooks.native_context,
            self.presents,
            self.window_width,
            self.window_height,
            @intFromEnum(self.phase),
        );
        if (reported > before) {
            self.native_diagnostic_frames = reported;
        } else {
            self.native_diagnostic_failures +|= 1;
        }
        self.updateNativePresenterStage();
    }

    pub fn snapshot(self: *const WindowsGraphicsState) WindowsGraphicsSnapshot {
        return .{
            .phase = self.phase,
            .application_ready = self.application_ready,
            .window_ready = self.window_ready,
            .native_window_ready = self.native_window_ready,
            .native_window_visible = self.native_window_visible,
            .instance_ready = self.instance_ready,
            .surface_ready = self.surface_ready,
            .device_ready = self.device_ready,
            .queue_ready = self.queue_ready,
            .swapchain_ready = self.swapchain_ready,
            .frame_resources_ready = self.frame_resources_ready,
            .guest_present_observed = self.guest_present_observed,
            .native_vulkan_forwarding = self.native_vulkan_forwarding,
            .native_vulkan_calls = self.native_vulkan_calls,
            .native_vulkan_failures = self.native_vulkan_failures,
            .native_presenter_started = self.native_presenter_started,
            .native_presenter_ready = self.native_presenter_ready,
            .native_presenter_stage = self.native_presenter_stage,
            .native_presenter_attempts = self.native_presenter_attempts,
            .native_presenter_failures = self.native_presenter_failures,
            .native_diagnostic_attempts = self.native_diagnostic_attempts,
            .native_diagnostic_frames = self.native_diagnostic_frames,
            .native_diagnostic_failures = self.native_diagnostic_failures,
            .window_create_attempts = self.window_create_attempts,
            .window_create_failures = self.window_create_failures,
            .application_attempts = self.application_attempts,
            .show_attempts = self.show_attempts,
            .event_pump_calls = self.event_pump_calls,
            .vulkan_calls = self.vulkan_calls,
            .proc_queries = self.proc_queries,
            .instance_creations = self.instance_creations,
            .surface_creations = self.surface_creations,
            .device_creations = self.device_creations,
            .queue_acquisitions = self.queue_acquisitions,
            .swapchain_creations = self.swapchain_creations,
            .swapchain_image_queries = self.swapchain_image_queries,
            .image_acquires = self.image_acquires,
            .command_calls = self.command_calls,
            .queue_submits = self.queue_submits,
            .presents = self.presents,
            .ordering_violations = self.ordering_violations,
            .unmodeled_calls = self.unmodeled_calls,
            .window_width = self.window_width,
            .window_height = self.window_height,
            .last_call = self.last_call,
            .last_failure = self.last_failure,
        };
    }
};

const ElfTraceEntry = struct {
    rip: u64 = 0,
    op: Op = .invalid,
    len: u8 = 0,
    rsp: u64 = 0,
    rax: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
};

// ─── Shared x64 execution types ───

pub const ElfRegs = x64_decoder.Regs;
pub const Size = x64_decoder.OperandSize;
pub const RegId = x64_decoder.RegId;
pub const Cond = x64_decoder.Condition;
pub const Op = x64_decoder.Op;
pub const DecodedInsn = x64_decoder.DecodedInsn;
pub const DynamicRelocation = elf_loader.DynamicRelocation;
pub const LocalSymbol = elf_loader.Symbol;
const BitScanKind = x64_decoder.BitScanKind;

/// The x87 register file is an eight-entry circular stack of 80-bit values.
/// Keeping the bytes, rather than only an f64 approximation, matters for
/// code that uses x87 as a transport for opaque data.  MinGW's formatter does
/// exactly that while copying a 16-byte custom-format record: FLD/FSTP m80
/// must preserve every byte or a function pointer loses its low bits.
const X87Raw = [10]u8;

const PE_MAX_INSTRUCTION_LENGTH: usize = 15;
const PE_DECODE_CACHE_ENTRIES: usize = 1 << 11;

/// A small direct-mapped cache for the raw instruction decode used by the
/// PE64 runner.  The resolved effective address is deliberately not cached:
/// it depends on the live register file, while the opcode/prefix/operand
/// description does not.  Comparing the instruction bytes on a hit keeps the
/// cache safe for self-modifying Windows code without imposing a global code
/// generation barrier on every data write.
const DecodeCacheEntry = struct {
    valid: bool = false,
    fetch_address: u64 = 0,
    bytes: [PE_MAX_INSTRUCTION_LENGTH]u8 = [_]u8{0} ** PE_MAX_INSTRUCTION_LENGTH,
    decoded: DecodedInsn = .{},
};

// ─── ELF state ───

pub const ElfState = struct {
    allocator: std.mem.Allocator,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    image_low: u64 = 0,
    image_high: u64 = 0,
    regs: ElfRegs = .{},
    // Full EVEX register addressing reaches zmm16-zmm31. Keep the extended
    // vector state even though the legacy VEX executor only uses the lower
    // sixteen registers.
    xmm: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    ymm_hi: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    zmm_hi: [32][32]u8 = [_][32]u8{[_]u8{0} ** 32} ** 32,
    // AVX-512 opmask registers (k0-k7). k0 is always all-1s when read as
    // a mask operand; k1-k7 hold actual mask values for predicated operations.
    k: [8]u64 = [_]u64{0xFFFF_FFFF_FFFF_FFFF} ** 8,
    x87_stack: [8]X87Raw = [_]X87Raw{[_]u8{0} ** 10} ** 8,
    x87_tags: [8]bool = [_]bool{false} ** 8,
    x87_top: u3 = 0,
    x87_status: u16 = 0,
    x87_control: u16 = 0x037F,
    terminated: bool = false,
    exit_code: u64 = 0,
    faulted: bool = false,
    termination_reason: exit_diagnostics.TerminationReason = .unknown,
    executed_steps: u64 = 0,
    // The ring implementation is shared with the other execution paths. Its
    // backing storage is heap-owned so returning this state by value cannot
    // leave `trace_ring` pointing at a pre-return stack field.
    trace_storage: []ElfTraceEntry = &.{},
    trace_ring: execution_history.Ring(ElfTraceEntry) = execution_history.Ring(ElfTraceEntry).init(&.{}),
    decode_cache: [PE_DECODE_CACHE_ENTRIES]DecodeCacheEntry = [_]DecodeCacheEntry{.{}} ** PE_DECODE_CACHE_ENTRIES,
    libc_start_main_trampolined: bool = false,
    dynamic_relocations: []const elf_loader.DynamicRelocation = &.{},
    local_symbols: []const elf_loader.Symbol = &.{},
    init_functions: []const u64 = &.{},
    init_index: usize = 0,
    pending_main_addr: u64 = 0,
    pending_argc: u64 = 0,
    pending_argv: u64 = 0,
    heap_next: u64 = MEM_BASE + (MEM_SIZE / 2),
    // PE32+ supplies an explicit heap/stack split. Keep it separate from the
    // historical ELF cutoff: using STACK_SIZE for a PE run allows the bump
    // heap to consume the lower part of the PE's reserved main stack.
    guest_heap_limit: u64 = 0,
    trace_syscalls: bool = false,
    trace_syscall_bytes: bool = false,
    trace_fd_filter: ?u64 = null,
    trace_calls: bool = false,
    // Resolve the optional RIP trace range once at state construction.  The
    // PE interpreter checks this on every instruction; consulting the host
    // environment in that hot path turns an opt-in diagnostic into a default
    // startup tax even when tracing is disabled.
    trace_rip_start: ?u64 = null,
    trace_rip_end: ?u64 = null,
    // Optional exact guest-memory watch used while diagnosing pointer
    // corruption in the PE route.  The watch is intentionally opt-in and
    // records overlapping writes to an eight-byte slot, so a mistaken 32-bit
    // store cannot disappear from the evidence.
    trace_write_address: ?u64 = null,
    // Optional allocation provenance for the Windows PE route. The PE image
    // has its own pthread pool as well as Rosetta-owned heap-backed imports,
    // so an address-only write watch cannot identify which lifetime supplied
    // a bad pointer. Keep this diagnostic off the hot path unless requested.
    trace_allocations: bool = false,
    // Record formatter object provenance once per call without enabling the
    // instruction-wide RIP tracer.
    trace_formatter: bool = false,
    trace_formatter_address: ?u64 = null,
    // Optional byte snapshots around the PE StringBuffer append imports. This
    // is deliberately narrower than ABI tracing: it answers whether a bad
    // formatted value was already present in the source temporary or was
    // introduced while copying it into Xenia's config buffer.
    trace_string_memory: bool = false,
    // Boundary-only scheduler tracing. Unlike ABI diagnostics this emits no
    // per-import records, so it can identify a worker that repeatedly yields
    // at one guest lock without changing the hot instruction path materially.
    trace_windows_threads: bool = false,
    // Message-boundary tracing is intentionally separate from full ABI
    // diagnostics: it records class registration, PostMessage, GetMessage,
    // and guest WndProc dispatch without printing every Windows import.
    trace_windows_messages: bool = false,
    // Wait-boundary tracing records only wait calls that actually service a
    // queued guest worker. It is useful for diagnosing cooperative mutex
    // stalls without enabling per-import ABI tracing.
    trace_windows_waits: bool = false,
    // Graphics progress tracing is deliberately separate from the ordinary
    // 10M-step register sample. It adds worker and Vulkan state needed to
    // distinguish a guest wait, a completed process, and a native bridge
    // that stopped receiving calls.
    trace_graphics_progress: bool = false,
    diagnose_abi: bool = false,
    call_stack: x64_guest_abi.CallStack = .{},
    interactive_output_path: ?[]u8 = null,
    interactive_summary_printed: bool = false,
    windows_runtime_enabled: bool = false,
    windows_unknown_imports_fatal: bool = true,
    windows_unresolved_imports: [WINDOWS_UNRESOLVED_IMPORT_CAPACITY]WindowsUnresolvedImport = [_]WindowsUnresolvedImport{.{}} ** WINDOWS_UNRESOLVED_IMPORT_CAPACITY,
    windows_unresolved_import_count: usize = 0,
    // Optional PE guest-function semantic correction discovered by the PE
    // loader. Rosetta does not rewrite the Windows image; it can instead
    // complete a recognized standard-library boundary when the image's own
    // implementation exposes a provably empty character set.
    windows_utf8_find_any_of_entry: ?u64 = null,
    windows_guest_compatibility_events: u64 = 0,
    windows_last_error: u32 = 0,
    windows_symbol_options: u32 = 0,
    windows_symbol_services_initialized: bool = false,
    windows_errno_storage: u64 = 0,
    // The PE C runtime asks for the active locale while parsing numeric
    // metadata (including the XEX container reached by Xenia's media path).
    // Keep the C-locale name, decimal point, empty fields, and lconv record
    // in guest memory so localeconv never returns a host pointer or a null
    // record that the CRT immediately dereferences.
    windows_locale_name: u64 = 0,
    windows_locale_decimal_point: u64 = 0,
    windows_locale_empty_string: u64 = 0,
    windows_localeconv_storage: u64 = 0,
    windows_import_calls: u64 = 0,
    windows_unknown_import_calls: u64 = 0,
    windows_degraded_import_calls: u64 = 0,
    // Which recognized-but-unimplemented imports this run actually took the
    // deterministic fallback for.  The preflight inventory can only list the
    // names that are *eligible*; this is the far smaller set the run depends
    // on, and it is what a degraded-import report is built from.
    windows_import_fallbacks: x64_linux_runtime.ImportFallbackLedger = .{},
    windows_next_handle: u64 = 0xFFFF_F000_0000_0001,
    // The one virtual display Rosetta presents.  Allocated lazily so it uses
    // the same handle space as every other Win32 object, and then stable: a
    // guest comparing "the monitor my window is on" against a cached value
    // must not see it change on every query.
    windows_primary_monitor: u64 = 0,
    windows_next_stdio_fd: u32 = 3,
    windows_next_tls: u32 = 0,
    windows_main_teb: u64 = 0,
    windows_process_peb: u64 = 0,
    windows_next_thread_id: u64 = 2,
    windows_file_mappings: [MAX_WINDOWS_FILE_MAPPINGS]WindowsFileMapping = [_]WindowsFileMapping{.{}} ** MAX_WINDOWS_FILE_MAPPINGS,
    windows_memory_views: [MAX_WINDOWS_MEMORY_VIEWS]WindowsMemoryView = [_]WindowsMemoryView{.{}} ** MAX_WINDOWS_MEMORY_VIEWS,
    windows_virtual_allocations: [MAX_WINDOWS_VIRTUAL_ALLOCATIONS]WindowsVirtualAllocation = [_]WindowsVirtualAllocation{.{}} ** MAX_WINDOWS_VIRTUAL_ALLOCATIONS,
    windows_heap_allocations: []WindowsHeapAllocation = &.{},
    windows_heap_allocation_count: usize = 0,
    // MapViewOfFile without an address hint gets a deterministic guest-only
    // placement outside the PE image.  Fixed Xenia views retain their exact
    // requested address and never consume this cursor.
    windows_next_memory_view_base: u64 = 0x0000_4000_0000_0000,
    // PE static TLS and Win32 dynamic TLS share the TEB vector but are not
    // the same namespace in the image contract.  Keep the module slot and
    // its initialized template separate from TlsAlloc's next dynamic slot so
    // the CRT's pthread record can never be mistaken for static TLS storage.
    windows_static_tls_index: ?u32 = null,
    windows_static_tls_template_start: u64 = 0,
    windows_static_tls_template_length: u64 = 0,
    windows_static_tls_block_bytes: u64 = WINDOWS_TLS_BLOCK_BYTES,
    windows_command_line_a: u64 = 0,
    windows_command_line_w: u64 = 0,
    // Command-line arguments are supplied by the PE runner as host-owned
    // byte slices, then materialized into guest memory by the Windows ABI
    // bridge. Keeping the source slices here avoids manufacturing a second
    // argv authority inside the executor.
    windows_launch_arguments: []const []const u8 = &.{},
    windows_host_media_path: ?[]const u8 = null,
    // The MinGW startup helpers return pointers to CRT-owned globals rather
    // than the strings themselves. Keep both levels in guest memory so
    // __wgetmainargs/__getmainargs can publish a real argc/argv/environ
    // contract to wmain without exposing a host pointer.
    windows_argc_storage: u64 = 0,
    windows_argv_a: u64 = 0,
    windows_argv_w: u64 = 0,
    windows_argv_a_storage: u64 = 0,
    windows_argv_w_storage: u64 = 0,
    windows_environ_a: u64 = 0,
    windows_environ_w: u64 = 0,
    windows_environ_a_storage: u64 = 0,
    windows_environ_w_storage: u64 = 0,
    windows_wcmdln_storage: u64 = 0,
    windows_module_path_a: u64 = 0,
    windows_module_path_w: u64 = 0,
    windows_user_folder_w: u64 = 0,
    windows_thread_description_w: u64 = 0,
    windows_entry_point: u64 = 0,
    windows_window_handle: u64 = 0,
    windows_host_io: ?std.Io = null,
    windows_host_working_directory: ?[]const u8 = null,
    windows_files: [MAX_WINDOWS_FILE_HANDLES]WindowsFileSlot = [_]WindowsFileSlot{.{}} ** MAX_WINDOWS_FILE_HANDLES,
    windows_finds: [MAX_WINDOWS_FIND_HANDLES]WindowsFindSlot = [_]WindowsFindSlot{.{}} ** MAX_WINDOWS_FIND_HANDLES,
    windows_initterm_frames: [MAX_WINDOWS_INITTERM_FRAMES]WindowsInitTermFrame = undefined,
    windows_initterm_frame_count: usize = 0,
    // Windows PE execution is hosted by one interpreter thread, but the
    // image may create real worker entry points before the UI loop starts.
    // These slots are the bounded guest scheduler for those entry points.
    windows_guest_threads: [MAX_WINDOWS_GUEST_THREADS]WindowsGuestThread = [_]WindowsGuestThread{.{}} ** MAX_WINDOWS_GUEST_THREADS,
    windows_active_guest_thread_slot: ?usize = null,
    windows_last_serviced_guest_thread_slot: ?usize = null,
    windows_last_service_owner_step: ?u64 = null,
    windows_parent_guest_context: WindowsGuestThreadContext = .{},
    windows_parent_guest_context_valid: bool = false,
    windows_thread_service_calls: u64 = 0,
    windows_thread_service_steps: u64 = 0,
    windows_thread_yields: u64 = 0,
    windows_thread_completions: u64 = 0,
    windows_thread_failures: u64 = 0,
    windows_ui_quit_requested: bool = false,
    windows_ui_quit_code: u64 = 0,
    windows_progress: WindowsProgressWatchdog = .{},
    // Win32 class/window/message state is guest-owned and bounded.  These
    // records are enough for Xenia's UI shell while keeping message delivery
    // deterministic and preventing a malformed PE from growing host memory.
    windows_window_classes: [MAX_WINDOWS_WINDOW_CLASSES]WindowsWindowClass = [_]WindowsWindowClass{.{}} ** MAX_WINDOWS_WINDOW_CLASSES,
    windows_next_window_class_atom: u16 = 1,
    windows_windows: [MAX_WINDOWS_WINDOWS]WindowsWindow = [_]WindowsWindow{.{}} ** MAX_WINDOWS_WINDOWS,
    windows_message_window_handle: u64 = 0,
    windows_messages: [MAX_WINDOWS_MESSAGES]WindowsMessage = [_]WindowsMessage{.{}} ** MAX_WINDOWS_MESSAGES,
    windows_message_head: usize = 0,
    windows_message_tail: usize = 0,
    windows_message_count: usize = 0,
    windows_message_posts: u64 = 0,
    windows_message_deliveries: u64 = 0,
    windows_message_drops: u64 = 0,
    windows_paint_requests: u64 = 0,
    windows_paint_deliveries: u64 = 0,
    windows_message_dispatch_frames: [MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES]WindowsMessageDispatchFrame = [_]WindowsMessageDispatchFrame{.{}} ** MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES,
    windows_message_dispatch_frame_count: usize = 0,
    windows_file_open_calls: u64 = 0,
    windows_file_read_calls: u64 = 0,
    windows_file_write_calls: u64 = 0,
    windows_file_failures: u64 = 0,
    windows_rtl_capture_calls: u64 = 0,
    windows_rtl_unwind_calls: u64 = 0,
    windows_stub_storage: [MAX_WINDOWS_IMPORT_STUBS]WindowsImportStub = undefined,
    windows_stub_count: usize = 0,
    // PE IAT thunks are materialized as one contiguous, fixed-stride range
    // before execution starts. Keep its geometry separate from the optional
    // GetProcAddress stubs so the instruction hot path can reject ordinary
    // image addresses with two comparisons instead of scanning every import.
    windows_direct_stub_base: u64 = 0,
    windows_direct_stub_count: usize = 0,
    windows_dynamic_stub_start: usize = 0,
    windows_graphics: WindowsGraphicsState = .{},
    // The native Vulkan forwarder records these lightweight execution facts
    // for diagnostics. They are intentionally inert for the PE scheduler;
    // there is no UI-thread ownership to infer from a plain guest state.
    active_guest_thread: u64 = 0x7FFF_2020,
    active_idle_source: u64 = 1,
    last_decoded_op: Op = .invalid,
    last_decoded_len: u8 = 0,
    last_instruction_rip: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) ElfState {
        return initWithMemory(allocator, MEM_SIZE);
    }

    /// Construct an x86-64 state with an address-space size chosen by the
    /// loader.  ELF keeps the historical 64 MiB default, while PE32+ images
    /// commonly have a much larger image and must not be truncated into it.
    pub fn initWithMemory(allocator: std.mem.Allocator, memory_size: u64) ElfState {
        const memory_len: usize = @intCast(memory_size);
        const mem = allocator.alloc(u8, memory_len) catch unreachable;
        const trace_storage = allocator.alloc(ElfTraceEntry, TRACE_BUFFER_LEN) catch unreachable;
        const heap_allocations = allocator.alloc(WindowsHeapAllocation, MAX_WINDOWS_HEAP_ALLOCATIONS) catch unreachable;
        @memset(trace_storage, .{});
        @memset(heap_allocations, .{});
        @memset(mem, 0);
        var state: ElfState = .{
            .allocator = allocator,
            .mem = mem,
            .mem_base = MEM_BASE,
            .mem_size = memory_size,
            .trace_storage = trace_storage,
            .windows_heap_allocations = heap_allocations,
            .trace_syscalls = envFlag("ROSETTE_ELF_TRACE_SYSCALLS"),
            .trace_syscall_bytes = envFlag("ROSETTE_ELF_TRACE_SYSCALL_BYTES"),
            .trace_fd_filter = envU64("ROSETTE_ELF_TRACE_FD"),
            .trace_calls = envFlag("ROSETTE_ELF_TRACE_CALLS"),
            .trace_rip_start = envU64("ROSETTE_ELF_TRACE_START"),
            .trace_rip_end = envU64("ROSETTE_ELF_TRACE_END"),
            .trace_write_address = envU64("ROSETTE_ELF_TRACE_WRITE_ADDRESS"),
            .diagnose_abi = envFlag("ROSETTE_ELF_DIAGNOSE_ABI") or envFlag("ROSETTE_ELF_INTERACTIVE_BRIDGE") or envFlag("ROSETTE_ELF_EDU_BRIDGE"),
        };
        state.trace_allocations = envFlag("ROSETTA_ELF_TRACE_ALLOCATIONS");
        state.trace_formatter = envFlag("ROSETTA_ELF_TRACE_FORMATTER");
        state.trace_formatter_address = envU64("ROSETTA_ELF_TRACE_FORMATTER_ADDRESS");
        state.trace_string_memory = envFlag("ROSETTA_ELF_TRACE_STRING_MEMORY") or envFlag("ROSETTE_ELF_TRACE_STRING_MEMORY");
        state.trace_windows_threads = envFlag("ROSETTA_ELF_TRACE_WINDOWS_THREADS");
        state.trace_windows_messages = envFlag("ROSETTA_ELF_TRACE_WINDOWS_MESSAGES");
        state.trace_windows_waits = envFlag("ROSETTE_ELF_TRACE_WINDOWS_WAITS") or envFlag("ROSETTA_ELF_TRACE_WINDOWS_WAITS");
        state.trace_graphics_progress = envFlag("ROSETTE_ELF_GRAPHICS_PROGRESS_TRACE");
        // The progress watchdog is on by default because it is silent unless
        // every observable axis freezes at once; a healthy run pays two
        // comparisons per step and prints nothing.
        state.windows_progress.enabled = !envPresentAndFalse("ROSETTE_PE64_STALL_WATCHDOG");
        if (envU64("ROSETTE_PE64_STALL_SAMPLE_STEPS")) |interval| {
            if (interval != 0) state.windows_progress.interval = interval;
        }
        if (envU64("ROSETTE_PE64_STALL_SAMPLES")) |samples| {
            if (samples != 0 and samples <= std.math.maxInt(u32)) {
                state.windows_progress.threshold = @intCast(samples);
            }
        }
        state.heap_next = MEM_BASE + (memory_size / 2);
        // Bind the ring to stable heap storage. The state is returned by value,
        // but the storage address remains valid until `deinit`.
        state.trace_ring = execution_history.Ring(ElfTraceEntry).init(trace_storage);
        return state;
    }

    pub fn deinit(self: *ElfState) void {
        if (self.windows_host_io) |io| {
            for (&self.windows_files) |*slot| {
                if (slot.file) |file| file.close(io);
                slot.* = .{};
            }
            for (&self.windows_finds) |*slot| {
                if (slot.dir) |dir| dir.close(io);
                slot.* = .{};
            }
        }
        for (&self.windows_file_mappings) |*mapping| {
            if (mapping.backing) |backing| std.posix.munmap(backing);
            mapping.* = .{};
        }
        for (&self.windows_memory_views) |*view| view.* = .{};
        for (&self.windows_virtual_allocations) |*allocation| {
            if (allocation.backing) |backing| std.posix.munmap(backing);
            allocation.* = .{};
        }
        if (self.windows_heap_allocations.len != 0) self.allocator.free(self.windows_heap_allocations);
        if (self.interactive_output_path) |path| self.allocator.free(path);
        self.call_stack.deinit(self.allocator);
        if (self.trace_storage.len != 0) self.allocator.free(self.trace_storage);
        self.allocator.free(self.mem);
    }

    fn captureWindowsGuestContext(self: *const ElfState) WindowsGuestThreadContext {
        var tls_values = [_]u64{0} ** WINDOWS_TLS_SLOT_COUNT;
        const teb = self.regs.segments.gs.base;
        if (teb != 0) {
            const tls_vector = self.read64(teb + 0x58);
            if (self.guestMemoryConst(tls_vector, WINDOWS_TLS_SLOT_COUNT * 8) != null) {
                for (0..WINDOWS_TLS_SLOT_COUNT) |slot| {
                    tls_values[slot] = self.read64(tls_vector + @as(u64, @intCast(slot * 8)));
                }
            }
        }
        return .{
            .regs = self.regs,
            .xmm = self.xmm,
            .ymm_hi = self.ymm_hi,
            .zmm_hi = self.zmm_hi,
            .k = self.k,
            .x87_stack = self.x87_stack,
            .x87_tags = self.x87_tags,
            .x87_top = self.x87_top,
            .x87_status = self.x87_status,
            .x87_control = self.x87_control,
            .tls_values = tls_values,
            .windows_last_error = self.windows_last_error,
            .windows_errno_storage = self.windows_errno_storage,
            .call_stack_depth = self.call_stack.frames.items.len,
            .active_guest_thread = self.active_guest_thread,
            .active_idle_source = self.active_idle_source,
            .last_decoded_op = self.last_decoded_op,
            .last_decoded_len = self.last_decoded_len,
        };
    }

    fn restoreWindowsGuestContext(self: *ElfState, context: *const WindowsGuestThreadContext) void {
        self.regs = context.regs;
        self.xmm = context.xmm;
        self.ymm_hi = context.ymm_hi;
        self.zmm_hi = context.zmm_hi;
        self.k = context.k;
        self.x87_stack = context.x87_stack;
        self.x87_tags = context.x87_tags;
        self.x87_top = context.x87_top;
        self.x87_status = context.x87_status;
        self.x87_control = context.x87_control;
        const teb = self.regs.segments.gs.base;
        if (teb != 0) {
            const tls_vector = self.read64(teb + 0x58);
            if (self.guestMemory(tls_vector, WINDOWS_TLS_SLOT_COUNT * 8) != null) {
                for (0..WINDOWS_TLS_SLOT_COUNT) |slot| {
                    self.write64(tls_vector + @as(u64, @intCast(slot * 8)), context.tls_values[slot]);
                }
            }
        }
        self.windows_last_error = context.windows_last_error;
        self.windows_errno_storage = context.windows_errno_storage;
        if (context.call_stack_depth <= self.call_stack.frames.items.len) {
            self.call_stack.frames.items = self.call_stack.frames.items[0..context.call_stack_depth];
        }
        self.active_guest_thread = context.active_guest_thread;
        self.active_idle_source = context.active_idle_source;
        self.last_decoded_op = context.last_decoded_op;
        self.last_decoded_len = context.last_decoded_len;
    }

    /// Install the PE loader's static TLS contract before any CRT code runs.
    /// Static TLS uses the image-provided module slot, while TlsAlloc/FlsAlloc
    /// use the remaining dynamic slots.  Keeping the two authorities explicit
    /// prevents a non-null static block from being interpreted as a pthread
    /// object by __pthread_self_lite.
    pub fn configureWindowsStaticTls(
        self: *ElfState,
        module_index: u32,
        template_start: u64,
        template_length: u64,
        block_bytes: u64,
    ) bool {
        if (module_index >= WINDOWS_TLS_SLOT_COUNT or template_length > block_bytes) return false;
        if (self.guestMemoryConst(template_start, template_length) == null) return false;
        self.windows_static_tls_index = module_index;
        self.windows_static_tls_template_start = template_start;
        self.windows_static_tls_template_length = template_length;
        self.windows_static_tls_block_bytes = @max(WINDOWS_TLS_BLOCK_BYTES, block_bytes);
        self.windows_next_tls = @max(self.windows_next_tls, @as(u32, module_index) + 1);
        return true;
    }

    fn allocateWindowsGuestThreadEnvironment(
        self: *ElfState,
        stack_base: u64,
        stack_limit: u64,
        thread_id: u64,
    ) ?WindowsGuestThreadEnvironment {
        if (self.windows_process_peb == 0) {
            log.err("Windows guest thread environment rejected: process PEB is not initialized thread_id={d}", .{thread_id});
            return null;
        }
        const teb = self.guestAlloc(WINDOWS_TEB_BYTES, WINDOWS_PAGE_SIZE) orelse return null;
        const tls_block = self.guestAlloc(self.windows_static_tls_block_bytes, WINDOWS_PAGE_SIZE) orelse return null;
        const tls_vector = teb + 0x1000;

        if (self.windows_static_tls_template_length != 0) {
            const source = self.guestMemoryConst(
                self.windows_static_tls_template_start,
                self.windows_static_tls_template_length,
            ) orelse return null;
            const destination = self.guestMemory(tls_block, self.windows_static_tls_template_length) orelse return null;
            @memcpy(destination, source);
        }

        self.write64(teb + WINDOWS_TEB_STACK_BASE_OFFSET, stack_base);
        self.write64(teb + WINDOWS_TEB_STACK_LIMIT_OFFSET, stack_limit);
        self.write64(teb + WINDOWS_TEB_SELF_OFFSET, teb);
        self.write64(teb + WINDOWS_TEB_CLIENT_ID_PROCESS_OFFSET, 1);
        self.write64(teb + WINDOWS_TEB_CLIENT_ID_THREAD_OFFSET, thread_id);
        self.write64(teb + WINDOWS_TEB_TLS_POINTER_OFFSET, tls_vector);
        if (self.windows_static_tls_index) |index| {
            self.write64(tls_vector + @as(u64, index) * 8, tls_block);
        }
        self.write64(teb + WINDOWS_TEB_PEB_OFFSET, self.windows_process_peb);
        self.write32(teb + WINDOWS_TEB_LAST_ERROR_OFFSET, 0);
        return .{ .teb = teb, .tls_block = tls_block };
    }

    /// Queue a Windows thread entry point for cooperative execution.  A
    /// successful Win32 handle is not enough here: the start routine must be
    /// retained and eventually run with a private guest stack, otherwise
    /// Xenia's graphics setup thread never reaches Vulkan initialization.
    pub fn enqueueWindowsGuestThread(
        self: *ElfState,
        handle: u64,
        start_routine: u64,
        argument: u64,
        requested_stack_size: u64,
        preferred: bool,
    ) bool {
        if (handle == 0 or start_routine == 0 or self.addrToOffset(start_routine) == null) return false;
        for (self.windows_guest_threads) |slot| {
            if (slot.status != .vacant and slot.handle == handle) return false;
        }

        var free_index: ?usize = null;
        for (self.windows_guest_threads, 0..) |slot, index| {
            if (slot.status == .vacant) {
                free_index = index;
                break;
            }
        }
        const index = free_index orelse {
            if (self.diagnose_abi) {
                log.err("Windows guest thread queue full: start=0x{x} argument=0x{x} handle=0x{x}", .{ start_routine, argument, handle });
            }
            return false;
        };

        const stack_size = if (requested_stack_size == 0)
            WINDOWS_GUEST_THREAD_STACK_SIZE
        else
            std.math.clamp(requested_stack_size, 64 * 1024, WINDOWS_GUEST_THREAD_MAX_STACK_SIZE);
        const thread_id = self.windows_next_thread_id;
        self.windows_next_thread_id +|= 1;
        self.windows_guest_threads[index] = .{
            .status = .pending,
            .handle = handle,
            .start_routine = start_routine,
            .argument = argument,
            .thread_id = thread_id,
            .stack_size = stack_size,
            .preferred = preferred,
        };
        return true;
    }

    fn nextWindowsGuestThread(self: *const ElfState) ?usize {
        const start = if (self.windows_last_serviced_guest_thread_slot) |last|
            (last + 1) % self.windows_guest_threads.len
        else
            0;

        // Give a freshly-created Win32 worker the first service opportunity
        // so Xenia's graphics setup thread is not behind CRT bookkeeping.
        // Once one slot has run, use a true circular scan: a worker that
        // parks in a loop must not starve the other graphics workers forever.
        if (self.windows_last_serviced_guest_thread_slot == null) {
            for (0..self.windows_guest_threads.len) |offset| {
                const index = (start + offset) % self.windows_guest_threads.len;
                const slot = self.windows_guest_threads[index];
                if ((slot.status == .pending or slot.status == .runnable) and slot.preferred) return index;
            }
        }
        for (0..self.windows_guest_threads.len) |offset| {
            const index = (start + offset) % self.windows_guest_threads.len;
            const slot = self.windows_guest_threads[index];
            if (slot.status == .pending or slot.status == .runnable) return index;
        }
        return null;
    }

    fn finishWindowsGuestThread(self: *ElfState) void {
        const index = self.windows_active_guest_thread_slot orelse {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = .runtime_invariant_failure;
            self.terminated = true;
            log.err("Windows guest thread return without an active thread context at rip=0x{x}", .{self.regs.rip});
            return;
        };
        self.windows_guest_threads[index].status = .completed;
        self.windows_thread_completions +|= 1;
        const parent = self.windows_parent_guest_context;
        self.restoreWindowsGuestContext(&parent);
        self.windows_active_guest_thread_slot = null;
        self.windows_parent_guest_context_valid = false;
        if (self.diagnose_abi or self.trace_windows_threads) {
            log.info("Windows guest thread complete handle=0x{x} start=0x{x} steps={d} parent_rip=0x{x}", .{
                self.windows_guest_threads[index].handle,
                self.windows_guest_threads[index].start_routine,
                self.windows_guest_threads[index].executed_steps,
                self.regs.rip,
            });
        }
    }

    /// Complete the currently serviced Windows worker when a noreturn thread
    /// API such as `_endthreadex` is reached.  The API must not be modelled as
    /// an ordinary zero-returning import: returning to its next instruction
    /// falls through into the next PE symbol because the wrapper has no
    /// epilogue after the real Windows runtime terminates the thread.
    pub fn terminateActiveWindowsGuestThread(self: *ElfState, exit_code: u64) bool {
        if (self.windows_active_guest_thread_slot == null) return false;
        self.regs.rax = exit_code;
        self.finishWindowsGuestThread();
        return true;
    }

    /// Run one queued Windows thread for a bounded slice.  The slice is a
    /// cooperative scheduling point, not a second host thread: all memory,
    /// import, graphics, and exception state remains owned by the same PE
    /// state, while each runnable entry retains a complete CPU context when it
    /// yields.  This keeps startup deterministic and prevents a worker loop
    /// from making the host UI unresponsive.
    pub fn serviceWindowsGuestThreads(self: *ElfState, max_steps: u64) u64 {
        if (max_steps == 0 or self.windows_active_guest_thread_slot != null or self.terminated) return 0;
        const index = self.nextWindowsGuestThread() orelse return 0;
        self.windows_thread_service_calls +|= 1;
        self.windows_last_serviced_guest_thread_slot = index;
        self.windows_last_service_owner_step = self.executed_steps;
        self.windows_active_guest_thread_slot = index;
        self.windows_parent_guest_context = self.captureWindowsGuestContext();
        self.windows_parent_guest_context_valid = true;

        const first_run = self.windows_guest_threads[index].status == .pending;
        if (first_run) {
            const stack_base = self.guestAlloc(self.windows_guest_threads[index].stack_size, 0x1000) orelse {
                self.windows_guest_threads[index].status = .failed;
                self.windows_thread_failures +|= 1;
                self.windows_active_guest_thread_slot = null;
                self.windows_parent_guest_context_valid = false;
                log.err("Windows guest thread stack allocation failed: handle=0x{x} start=0x{x} size={d}", .{
                    self.windows_guest_threads[index].handle,
                    self.windows_guest_threads[index].start_routine,
                    self.windows_guest_threads[index].stack_size,
                });
                return 0;
            };
            const allocated_stack_end = stack_base + self.windows_guest_threads[index].stack_size;
            const stack_top = allocated_stack_end - WINDOWS_GUEST_THREAD_ENTRY_RESERVE;
            const initial_parent = self.windows_parent_guest_context;
            var context = initial_parent;
            context.regs = .{};
            context.regs.segments = initial_parent.regs.segments;
            const environment = self.allocateWindowsGuestThreadEnvironment(
                allocated_stack_end,
                stack_base,
                self.windows_guest_threads[index].thread_id,
            ) orelse {
                self.windows_guest_threads[index].status = .failed;
                self.windows_thread_failures +|= 1;
                self.windows_active_guest_thread_slot = null;
                self.windows_parent_guest_context_valid = false;
                log.err("Windows guest thread environment allocation failed: handle=0x{x} start=0x{x} thread_id={d}", .{
                    self.windows_guest_threads[index].handle,
                    self.windows_guest_threads[index].start_routine,
                    self.windows_guest_threads[index].thread_id,
                });
                return 0;
            };
            context.regs.segments.gs.base = environment.teb;
            context.regs.mxcsr = initial_parent.regs.mxcsr;
            context.regs.rflags = 2;
            context.regs.rcx = self.windows_guest_threads[index].argument;
            context.tls_values = [_]u64{0} ** WINDOWS_TLS_SLOT_COUNT;
            if (self.windows_static_tls_index) |static_index| {
                context.tls_values[static_index] = environment.tls_block;
            }
            context.windows_last_error = 0;
            context.windows_errno_storage = 0;
            // RSP must be 8 mod 16 at a normal Windows x64 callee entry:
            // [RSP] is the synthetic return address and [RSP+8..+0x27] is
            // the four-slot home area.  The reserved cushion keeps all of
            // those addresses below allocated_stack_end.
            context.regs.rsp = (stack_top & ~@as(u64, 0xF)) - 8;
            context.regs.rip = self.windows_guest_threads[index].start_routine;
            context.active_guest_thread = self.windows_guest_threads[index].handle;
            context.active_idle_source = initial_parent.active_idle_source;
            self.windows_guest_threads[index].stack_base = stack_base;
            self.windows_guest_threads[index].teb = environment.teb;
            self.windows_guest_threads[index].tls_block = environment.tls_block;
            self.windows_guest_threads[index].synthetic_return_slot = context.regs.rsp;
            self.windows_guest_threads[index].context = context;
            self.write64(context.regs.rsp, SYNTHETIC_WINDOWS_THREAD_RETURN);
        }

        self.windows_guest_threads[index].status = .running;
        const context = self.windows_guest_threads[index].context;
        self.restoreWindowsGuestContext(&context);
        if (self.diagnose_abi or self.trace_windows_threads) {
            // The Win32 wrapper receives two different opaque start records:
            // xe::threading::ThreadStartRoutine stores its std::function
            // invoker at +0x18, while the MinGW pthread wrapper stores the
            // pthread entry at +0x10 and its argument at +0x08.  Reporting
            // those targets makes a cooperative worker trace actionable
            // without walking an incomplete host stack.
            const dispatch_target = if (self.windows_guest_threads[index].start_routine == 0x1401310f0)
                self.read64(context.regs.rcx +| 0x18)
            else if (self.windows_guest_threads[index].start_routine == 0x14051502b)
                self.read64(context.regs.rcx +| 0x10)
            else
                0;
            const dispatch_argument = if (self.windows_guest_threads[index].start_routine == 0x14051502b)
                self.read64(context.regs.rcx +| 0x08)
            else
                0;
            const dispatch_vtable = if (dispatch_argument != 0) self.read64(dispatch_argument) else 0;
            log.info("Windows guest thread service start handle=0x{x} start=0x{x} argument=0x{x} dispatch=0x{x} dispatch_argument=0x{x} dispatch_vtable=0x{x} resumed={} rip=0x{x} rsp=0x{x} return_slot=0x{x} return_value=0x{x} stack=[0x{x},0x{x})", .{
                self.windows_guest_threads[index].handle,
                self.windows_guest_threads[index].start_routine,
                self.windows_guest_threads[index].argument,
                dispatch_target,
                dispatch_argument,
                dispatch_vtable,
                !first_run,
                self.regs.rip,
                self.regs.rsp,
                self.windows_guest_threads[index].synthetic_return_slot,
                self.read64(self.windows_guest_threads[index].synthetic_return_slot),
                self.windows_guest_threads[index].stack_base,
                self.windows_guest_threads[index].stack_base +| self.windows_guest_threads[index].stack_size,
            });
        }

        var executed: u64 = 0;
        while (!self.terminated and self.windows_active_guest_thread_slot != null and executed < max_steps) : (executed += 1) {
            const continue_running = self.step();
            self.windows_thread_service_steps +|= 1;
            self.windows_guest_threads[index].executed_steps +|= 1;
            if (self.regs.rip == 0) {
                const thread = self.windows_guest_threads[index];
                log.err("Windows guest thread reached null RIP: handle=0x{x} start=0x{x} last_op={s} last_len={d} rsp=0x{x} rsp_value=0x{x} rbp=0x{x} entry_slot=0x{x} entry_value=0x{x} stack=[0x{x},0x{x}) call_depth={d}", .{
                    thread.handle,
                    thread.start_routine,
                    @tagName(self.last_decoded_op),
                    self.last_decoded_len,
                    self.regs.rsp,
                    self.read64(self.regs.rsp),
                    self.regs.rbp,
                    thread.synthetic_return_slot,
                    self.read64(thread.synthetic_return_slot),
                    thread.stack_base,
                    thread.stack_base +| thread.stack_size,
                    self.call_stack.frames.items.len,
                });
            }
            if (!continue_running) break;
        }

        if (self.terminated) {
            self.windows_guest_threads[index].status = .failed;
            self.windows_thread_failures +|= 1;
            if (self.windows_parent_guest_context_valid) {
                const parent = self.windows_parent_guest_context;
                self.restoreWindowsGuestContext(&parent);
            }
            self.windows_active_guest_thread_slot = null;
            self.windows_parent_guest_context_valid = false;
            return executed;
        }
        if (self.windows_active_guest_thread_slot != null) {
            self.windows_guest_threads[index].context = self.captureWindowsGuestContext();
            self.windows_guest_threads[index].status = .runnable;
            self.windows_thread_yields +|= 1;
            const parent = self.windows_parent_guest_context;
            self.restoreWindowsGuestContext(&parent);
            self.windows_active_guest_thread_slot = null;
            self.windows_parent_guest_context_valid = false;
            if (self.diagnose_abi or self.trace_windows_threads) {
                log.info("Windows guest thread service yield handle=0x{x} slice={d} rip=0x{x} rsp=0x{x}", .{
                    self.windows_guest_threads[index].handle,
                    executed,
                    self.windows_guest_threads[index].context.regs.rip,
                    self.windows_guest_threads[index].context.regs.rsp,
                });
            }
        }
        return executed;
    }

    pub fn requestWindowsUiQuit(self: *ElfState) void {
        self.windows_ui_quit_requested = true;
    }

    fn captureWindowsClassName(self: *const ElfState, record: *WindowsWindowClass, name_ptr: u64, wide: bool) void {
        record.name_ptr = name_ptr;
        record.name_len = 0;
        record.wide = wide;
        @memset(record.name[0..], 0);
        if (name_ptr == 0) return;

        if (wide) {
            while (record.name_len < record.name.len - 1) {
                const address = name_ptr +| @as(u64, @intCast(record.name_len * 2));
                if (self.guestMemoryConst(address, 2) == null) break;
                const unit = self.read16(address);
                if (unit == 0) break;
                record.name[record.name_len] = if (unit <= 0x7f) @intCast(unit) else '?';
                record.name_len += 1;
            }
        } else {
            while (record.name_len < record.name.len - 1) {
                const address = name_ptr +| @as(u64, @intCast(record.name_len));
                if (self.guestMemoryConst(address, 1) == null) break;
                const byte = self.read8(address);
                if (byte == 0) break;
                record.name[record.name_len] = byte;
                record.name_len += 1;
            }
        }
    }

    fn windowsClassMatches(self: *const ElfState, record: *const WindowsWindowClass, class_name: u64, wide: bool) bool {
        if (!record.valid or class_name == 0) return false;
        if (class_name <= 0xffff and record.atom == @as(u16, @intCast(class_name))) return true;
        if (record.name_ptr == class_name) return true;
        if (record.name_len == 0) return false;

        for (0..record.name_len) |index| {
            const address = class_name +| if (wide)
                @as(u64, @intCast(index * 2))
            else
                @as(u64, @intCast(index));
            const actual: u8 = if (wide) blk: {
                if (self.guestMemoryConst(address, 2) == null) return false;
                const unit = self.read16(address);
                if (unit > 0x7f) return false;
                break :blk @intCast(unit);
            } else blk: {
                if (self.guestMemoryConst(address, 1) == null) return false;
                break :blk self.read8(address);
            };
            if (actual != record.name[index]) return false;
        }

        const terminator = class_name +| if (wide)
            @as(u64, @intCast(record.name_len * 2))
        else
            @as(u64, @intCast(record.name_len));
        if (self.guestMemoryConst(terminator, if (wide) 2 else 1) == null) return false;
        return if (wide) self.read16(terminator) == 0 else self.read8(terminator) == 0;
    }

    fn windowsClassIndex(self: *const ElfState, class_name: u64, wide: bool) ?usize {
        for (self.windows_window_classes, 0..) |record, index| {
            if (self.windowsClassMatches(&record, class_name, wide)) return index;
        }
        return null;
    }

    /// Register the guest WndProc carried by a WNDCLASS/WNDCLASSEX record.
    /// The structure layout is the same through `lpfnWndProc` and
    /// `lpszClassName` for the A/W and Ex/non-Ex variants on Win64.
    pub fn registerWindowsWindowClass(self: *ElfState, class_info: u64, wide: bool) u64 {
        if (class_info == 0 or self.guestMemoryConst(class_info, 72) == null) return 0;
        const wnd_proc = self.read64(class_info + 8);
        const class_name = self.read64(class_info + 64);
        if (wnd_proc == 0 or class_name == 0) return 0;

        if (self.windowsClassIndex(class_name, wide)) |existing| {
            self.windows_window_classes[existing].wnd_proc = wnd_proc;
            return self.windows_window_classes[existing].atom;
        }

        var free_index: ?usize = null;
        for (self.windows_window_classes, 0..) |record, index| {
            if (!record.valid) {
                free_index = index;
                break;
            }
        }
        const index = free_index orelse return 0;
        const atom = self.windows_next_window_class_atom;
        self.windows_next_window_class_atom +|= 1;
        if (self.windows_next_window_class_atom == 0) self.windows_next_window_class_atom = 1;

        var record = WindowsWindowClass{
            .valid = true,
            .atom = if (atom == 0) 1 else atom,
            .wnd_proc = wnd_proc,
            .wide = wide,
        };
        self.captureWindowsClassName(&record, class_name, wide);
        self.windows_window_classes[index] = record;
        return record.atom;
    }

    /// Install a synthetic HWND and retain the guest `lpParam` as its
    /// GWLP_USERDATA.  Real Win32 sends WM_NCCREATE during CreateWindowEx;
    /// recording that result here gives the guest WndProc the same state
    /// without recursively running creation messages before the import has
    /// returned its HWND.
    pub fn createWindowsWindow(
        self: *ElfState,
        handle: u64,
        class_name: u64,
        user_data: u64,
        message_only: bool,
        style: u64,
        ex_style: u64,
        wide: bool,
    ) bool {
        if (handle == 0 or self.windowsWindowIndex(handle) != null) return false;
        var free_index: ?usize = null;
        for (self.windows_windows, 0..) |record, index| {
            if (!record.valid) {
                free_index = index;
                break;
            }
        }
        const index = free_index orelse return false;
        const class_index = self.windowsClassIndex(class_name, wide);
        self.windows_windows[index] = .{
            .valid = true,
            .handle = handle,
            .class_atom = if (class_index) |class_index_value| self.windows_window_classes[class_index_value].atom else 0,
            .wnd_proc = if (class_index) |class_index_value| self.windows_window_classes[class_index_value].wnd_proc else 0,
            .user_data = user_data,
            .style = @truncate(style),
            .ex_style = @truncate(ex_style),
            .message_only = message_only,
        };
        if (message_only) self.windows_message_window_handle = handle;
        return true;
    }

    fn windowsWindowIndex(self: *const ElfState, handle: u64) ?usize {
        for (self.windows_windows, 0..) |record, index| {
            if (record.valid and record.handle == handle) return index;
        }
        return null;
    }

    pub fn isWindowsWindowHandle(self: *const ElfState, handle: u64) bool {
        return self.windowsWindowIndex(handle) != null;
    }

    pub fn windowsWindowProc(self: *const ElfState, handle: u64) ?u64 {
        const index = self.windowsWindowIndex(handle) orelse return null;
        const proc = self.windows_windows[index].wnd_proc;
        return if (proc == 0) null else proc;
    }

    pub fn windowsWindowLong(self: *const ElfState, handle: u64, index: i64) ?u64 {
        const window_index = self.windowsWindowIndex(handle) orelse return null;
        const record = self.windows_windows[window_index];
        return switch (index) {
            WINDOWS_GWLP_USERDATA => record.user_data,
            WINDOWS_GWL_STYLE => record.style,
            WINDOWS_GWL_EXSTYLE => record.ex_style,
            WINDOWS_GCLP_WNDPROC => record.wnd_proc,
            else => null,
        };
    }

    pub fn setWindowsWindowLong(self: *ElfState, handle: u64, index: i64, value: u64) ?u64 {
        const window_index = self.windowsWindowIndex(handle) orelse return null;
        const previous = self.windowsWindowLong(handle, index) orelse return null;
        switch (index) {
            WINDOWS_GWLP_USERDATA => self.windows_windows[window_index].user_data = value,
            WINDOWS_GWL_STYLE => self.windows_windows[window_index].style = @truncate(value),
            WINDOWS_GWL_EXSTYLE => self.windows_windows[window_index].ex_style = @truncate(value),
            else => return null,
        }
        return previous;
    }

    pub fn destroyWindowsWindow(self: *ElfState, handle: u64) bool {
        const index = self.windowsWindowIndex(handle) orelse return false;
        self.windows_windows[index] = .{};
        if (self.windows_message_window_handle == handle) self.windows_message_window_handle = 0;
        return true;
    }

    /// Mark a window's update region non-empty.  This is the model behind
    /// InvalidateRect/InvalidateRgn/RedrawWindow: Win32 records the request
    /// and defers WM_PAINT generation to the message pump.  A null HWND
    /// invalidates every drawable window, matching the Win32 contract for a
    /// null window handle.
    pub fn invalidateWindowsWindow(self: *ElfState, handle: u64) bool {
        if (handle == 0) {
            var marked = false;
            for (&self.windows_windows) |*record| {
                if (!record.valid or record.message_only) continue;
                if (!record.update_region_pending) self.windows_paint_requests +|= 1;
                record.update_region_pending = true;
                marked = true;
            }
            return marked;
        }
        const index = self.windowsWindowIndex(handle) orelse return false;
        if (self.windows_windows[index].message_only) return false;
        if (!self.windows_windows[index].update_region_pending) self.windows_paint_requests +|= 1;
        self.windows_windows[index].update_region_pending = true;
        return true;
    }

    /// Clear a window's update region.  ValidateRect/ValidateRgn and the
    /// BeginPaint/EndPaint pair all end the pending paint; without this the
    /// pump would keep regenerating WM_PAINT forever, exactly as real Win32
    /// does for a WndProc that never validates.
    pub fn validateWindowsWindow(self: *ElfState, handle: u64) bool {
        if (handle == 0) {
            var cleared = false;
            for (&self.windows_windows) |*record| {
                if (!record.valid) continue;
                if (record.update_region_pending) cleared = true;
                record.update_region_pending = false;
            }
            return cleared;
        }
        const index = self.windowsWindowIndex(handle) orelse return false;
        const cleared = self.windows_windows[index].update_region_pending;
        self.windows_windows[index].update_region_pending = false;
        return cleared;
    }

    pub fn windowsWindowHasPendingPaint(self: *const ElfState, handle: u64) bool {
        const index = self.windowsWindowIndex(handle) orelse return false;
        return self.windows_windows[index].update_region_pending;
    }

    pub fn windowsPendingPaintCount(self: *const ElfState) usize {
        var count: usize = 0;
        for (self.windows_windows) |record| {
            if (record.valid and record.update_region_pending) count += 1;
        }
        return count;
    }

    /// Produce the WM_PAINT a pump call should return, if any window still
    /// has a non-empty update region and the caller's filter accepts it.
    /// WM_PAINT is generated rather than dequeued, so the region stays set
    /// until the guest validates it; a PeekMessage without PM_REMOVE and a
    /// GetMessage therefore observe the same pending paint.
    pub fn pendingWindowsPaintMessage(
        self: *ElfState,
        filter_hwnd: u64,
        minimum: u64,
        maximum: u64,
    ) ?WindowsMessage {
        const minimum_message: u32 = @truncate(minimum);
        const maximum_message: u32 = @truncate(maximum);
        if (minimum_message > maximum_message and !(minimum_message == 0 and maximum_message == 0)) return null;
        for (self.windows_windows) |record| {
            if (!record.valid or !record.update_region_pending) continue;
            const message = WindowsMessage{ .hwnd = record.handle, .message = WINDOWS_WM_PAINT };
            if (!windowsMessageMatches(message, filter_hwnd, minimum_message, maximum_message)) continue;
            // A WM_PAINT that no WndProc can receive would spin the pump
            // forever without ever reaching the guest's painter.  Report the
            // window as having nothing to paint instead; the stall report
            // names the window if this is the reason no frame is produced.
            if (record.wnd_proc == 0) continue;
            self.windows_paint_deliveries +|= 1;
            return message;
        }
        return null;
    }

    fn enqueueWindowsMessage(self: *ElfState, message: WindowsMessage) bool {
        if (self.windows_message_count >= self.windows_messages.len) {
            self.windows_message_drops +|= 1;
            return false;
        }
        self.windows_messages[self.windows_message_tail] = message;
        self.windows_message_tail = (self.windows_message_tail + 1) % self.windows_messages.len;
        self.windows_message_count += 1;
        self.windows_message_posts +|= 1;
        return true;
    }

    pub fn postWindowsMessage(self: *ElfState, hwnd: u64, message: u32, wparam: u64, lparam: u64) bool {
        if (hwnd == 0 or !self.isWindowsWindowHandle(hwnd)) {
            self.windows_message_drops +|= 1;
            return false;
        }
        return self.enqueueWindowsMessage(.{ .hwnd = hwnd, .message = message, .wparam = wparam, .lparam = lparam });
    }

    pub fn postWindowsQuit(self: *ElfState, exit_code: u64) void {
        self.windows_ui_quit_code = exit_code;
        self.windows_ui_quit_requested = true;
        _ = self.enqueueWindowsMessage(.{ .message = 0, .wparam = exit_code });
    }

    fn windowsMessageMatches(message: WindowsMessage, filter_hwnd: u64, minimum: u32, maximum: u32) bool {
        if (filter_hwnd != 0 and message.hwnd != filter_hwnd) return false;
        if (minimum == 0 and maximum == 0) return true;
        return message.message >= minimum and message.message <= maximum;
    }

    pub fn dequeueWindowsMessage(self: *ElfState, filter_hwnd: u64, minimum: u64, maximum: u64, remove: bool) ?WindowsMessage {
        const minimum_message: u32 = @truncate(minimum);
        const maximum_message: u32 = @truncate(maximum);
        if (minimum_message > maximum_message and !(minimum_message == 0 and maximum_message == 0)) return null;

        for (0..self.windows_message_count) |offset| {
            const index = (self.windows_message_head + offset) % self.windows_messages.len;
            const message = self.windows_messages[index];
            if (!windowsMessageMatches(message, filter_hwnd, minimum_message, maximum_message)) continue;
            if (!remove) return message;

            var shift = offset;
            while (shift + 1 < self.windows_message_count) : (shift += 1) {
                const current = (self.windows_message_head + shift) % self.windows_messages.len;
                const next = (self.windows_message_head + shift + 1) % self.windows_messages.len;
                self.windows_messages[current] = self.windows_messages[next];
            }
            self.windows_message_tail = (self.windows_message_tail + self.windows_messages.len - 1) % self.windows_messages.len;
            self.windows_messages[self.windows_message_tail] = .{};
            self.windows_message_count -= 1;
            self.windows_message_deliveries +|= 1;
            return message;
        }
        return null;
    }

    /// Reserve a properly aligned nested Windows callback frame.  The
    /// original DispatchMessage return address stays above the callback's
    /// 32-byte home area, so a WndProc can use the normal Microsoft x64 ABI.
    pub fn beginWindowsMessageDispatch(self: *ElfState, return_rip: u64, return_is_direct: bool) bool {
        if (self.windows_message_dispatch_frame_count >= self.windows_message_dispatch_frames.len) return false;
        const return_rsp = self.regs.rsp;
        if (return_rsp < 40) return false;
        const callback_rsp = return_rsp - 40;
        if (self.guestMemory(callback_rsp, 40) == null) return false;

        const frame_index = self.windows_message_dispatch_frame_count;
        self.windows_message_dispatch_frames[frame_index] = .{
            .return_rip = return_rip,
            .return_rsp = return_rsp,
            .return_is_direct = return_is_direct,
        };
        self.windows_message_dispatch_frame_count += 1;
        self.regs.rsp = callback_rsp;
        self.write64(callback_rsp, SYNTHETIC_WINDOWS_MESSAGE_RETURN);
        if (self.guestMemory(callback_rsp + 8, 32)) |home| @memset(home, 0);
        return true;
    }

    pub fn finishWindowsMessageDispatch(self: *ElfState) bool {
        if (self.windows_message_dispatch_frame_count == 0) {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = .runtime_invariant_failure;
            self.terminated = true;
            log.err("Windows message callback returned without a dispatch frame rip=0x{x}", .{self.regs.rip});
            return false;
        }
        const frame_index = self.windows_message_dispatch_frame_count - 1;
        const frame = self.windows_message_dispatch_frames[frame_index];
        self.windows_message_dispatch_frame_count = frame_index;
        const expected_callback_rsp = (frame.return_rsp -| 40) + 8;
        if ((self.trace_windows_messages or self.diagnose_abi) and !frame.return_is_direct and self.regs.rsp != expected_callback_rsp) {
            log.warn("Windows message callback changed stack unexpectedly callback_rsp=0x{x} expected_after_ret=0x{x} return_rsp=0x{x}", .{
                self.regs.rsp,
                expected_callback_rsp,
                frame.return_rsp,
            });
        }
        self.regs.rsp = if (frame.return_is_direct) frame.return_rsp else frame.return_rsp +| 8;
        self.regs.rip = frame.return_rip;
        return true;
    }

    pub fn addrToOffset(self: *const ElfState, vaddr: u64) ?u64 {
        if (vaddr < self.mem_base) return null;
        const off = vaddr - self.mem_base;
        if (off >= self.mem_size) return null;
        return off;
    }

    fn windowsVirtualAllocationContains(self: *const ElfState, address: u64, count: u64) bool {
        const end = std.math.add(u64, address, count) catch return false;
        for (self.windows_virtual_allocations) |allocation| {
            if (allocation.length == 0 or allocation.backing == null or address < allocation.guest_base) continue;
            const allocation_end = std.math.add(u64, allocation.guest_base, allocation.length) catch continue;
            if (end <= allocation_end) return true;
        }
        return false;
    }

    fn windowsMappedRangeContains(self: *const ElfState, address: u64, count: u64) bool {
        const end = std.math.add(u64, address, count) catch return false;
        for (self.windows_memory_views) |view| {
            if (view.length == 0 or address < view.guest_base) continue;
            const view_end = std.math.add(u64, view.guest_base, view.length) catch continue;
            if (end <= view_end) return true;
        }
        return false;
    }

    pub fn windowsGuestRangeContains(self: *const ElfState, address: u64, count: u64) bool {
        if (count == 0) return true;
        if (self.addrToOffset(address)) |offset| {
            const count_usize = std.math.cast(usize, count) orelse return false;
            const offset_usize = std.math.cast(usize, offset) orelse return false;
            return offset_usize <= self.mem.len and count_usize <= self.mem.len - offset_usize;
        }
        if (self.windowsMappedRangeContains(address, count)) return true;
        if (self.windowsVirtualAllocationContains(address, count)) return true;
        return false;
    }

    fn windowsMappingIndex(self: *const ElfState, handle: u64) ?usize {
        if (handle == 0) return null;
        for (self.windows_file_mappings, 0..) |mapping, index| {
            if (mapping.guest_handle == handle and mapping.backing != null) return index;
        }
        return null;
    }

    fn windowsViewRangeIsFree(self: *const ElfState, guest_base: u64, length: u64) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        const ordinary_end = std.math.add(u64, self.mem_base, self.mem_size) catch std.math.maxInt(u64);
        if (guest_base < ordinary_end and end > self.mem_base) return false;
        for (self.windows_memory_views) |view| {
            if (view.length == 0) continue;
            const view_end = std.math.add(u64, view.guest_base, view.length) catch std.math.maxInt(u64);
            if (guest_base < view_end and end > view.guest_base) return false;
        }
        for (self.windows_virtual_allocations) |allocation| {
            if (allocation.length == 0) continue;
            const allocation_end = std.math.add(u64, allocation.guest_base, allocation.length) catch std.math.maxInt(u64);
            if (guest_base < allocation_end and end > allocation.guest_base) return false;
        }
        return true;
    }

    fn windowsMappingHasViews(self: *const ElfState, mapping_index: usize) bool {
        for (self.windows_memory_views) |view| {
            if (view.length != 0 and view.mapping_index == mapping_index) return true;
        }
        return false;
    }

    fn releaseClosedWindowsMapping(self: *ElfState, mapping_index: usize) void {
        const mapping = &self.windows_file_mappings[mapping_index];
        if (!mapping.closed or self.windowsMappingHasViews(mapping_index)) return;
        if (mapping.backing) |backing| std.posix.munmap(backing);
        mapping.* = .{};
    }

    /// Create a Rosetta-owned anonymous backing for a Windows page-file
    /// mapping.  Windows specifies the maximum byte offset for this API; the
    /// backing therefore includes the inclusive final byte.  The host mmap is
    /// intentionally left untouched so the 4 GiB+512 MiB Xenia aperture stays
    /// sparse and commits only the pages the guest actually accesses.
    pub fn createWindowsMemoryMapping(self: *ElfState, handle: u64, requested_length: u64) bool {
        if (handle == 0 or requested_length == std.math.maxInt(u64)) return false;
        const inclusive_length = std.math.add(u64, requested_length, 1) catch return false;
        const page_size: u64 = @intCast(std.heap.page_size_min);
        const rounded_length = std.math.add(u64, inclusive_length, page_size - 1) catch return false;
        const mapping_length = rounded_length & ~(page_size - 1);
        const length: usize = std.math.cast(usize, mapping_length) orelse return false;
        const prot: std.posix.PROT = @bitCast(@as(u32, 0x1 | 0x2));
        const flags: std.posix.MAP = @bitCast(@as(u32, 0x1000 | 0x2));
        const backing = std.posix.mmap(null, length, prot, flags, -1, 0) catch |err| {
            log.err("PE64 Windows CreateFileMapping failed: handle=0x{x} requested_length={d} mapped_length={d} reason={s}", .{
                handle,
                requested_length,
                mapping_length,
                @errorName(err),
            });
            return false;
        };

        for (&self.windows_file_mappings) |*mapping| {
            if (mapping.backing == null) {
                mapping.* = .{
                    .guest_handle = handle,
                    .length = mapping_length,
                    .backing = backing,
                };
                if (self.diagnose_abi) {
                    log.info("PE64 Windows CreateFileMapping: handle=0x{x} requested_length={d} mapped_length={d} backing=0x{x}", .{
                        handle,
                        requested_length,
                        mapping_length,
                        @intFromPtr(backing.ptr),
                    });
                }
                return true;
            }
        }
        std.posix.munmap(backing);
        log.err("PE64 Windows CreateFileMapping rejected: mapping table exhausted handle=0x{x}", .{handle});
        return false;
    }

    /// Reserve/commit a fixed anonymous Windows range.  The native Xenia
    /// build uses VirtualAlloc for memory outside its file mapping (the code
    /// cache's 0x80000000 indirection table is the first such allocation),
    /// so returning a normal Rosetta heap address would silently corrupt the
    /// pointer contract.  A sparse host mapping gives those exact guest
    /// addresses real storage without reserving the range in the host VM.
    pub fn createWindowsVirtualAllocation(self: *ElfState, guest_base: u64, requested_length: u64) bool {
        if (guest_base == 0 or requested_length == 0) return false;
        const page_size: u64 = @intCast(std.heap.page_size_min);
        if (guest_base % page_size != 0) return false;
        const rounded_length = std.math.add(u64, requested_length, page_size - 1) catch return false;
        const allocation_length = rounded_length & ~(page_size - 1);
        if (self.windowsGuestRangeContains(guest_base, allocation_length)) return true;
        if (!self.windowsViewRangeIsFree(guest_base, allocation_length)) return false;
        const length = std.math.cast(usize, allocation_length) orelse return false;
        const prot: std.posix.PROT = @bitCast(@as(u32, 0x1 | 0x2));
        const flags: std.posix.MAP = @bitCast(@as(u32, 0x1000 | 0x2));
        const backing = std.posix.mmap(null, length, prot, flags, -1, 0) catch |err| {
            log.err("PE64 Windows VirtualAlloc fixed mapping failed: guest_base=0x{x} requested_length={d} mapped_length={d} reason={s}", .{
                guest_base,
                requested_length,
                allocation_length,
                @errorName(err),
            });
            return false;
        };

        for (&self.windows_virtual_allocations) |*allocation| {
            if (allocation.backing == null) {
                allocation.* = .{
                    .guest_base = guest_base,
                    .length = allocation_length,
                    .backing = backing,
                };
                if (self.diagnose_abi) {
                    log.info("PE64 Windows VirtualAlloc fixed: guest_base=0x{x} requested_length={d} mapped_length={d} backing=0x{x}", .{
                        guest_base,
                        requested_length,
                        allocation_length,
                        @intFromPtr(backing.ptr),
                    });
                }
                return true;
            }
        }
        std.posix.munmap(backing);
        log.err("PE64 Windows VirtualAlloc rejected: allocation table exhausted guest_base=0x{x} length={d}", .{ guest_base, allocation_length });
        return false;
    }

    pub fn releaseWindowsVirtualAllocation(self: *ElfState, guest_base: u64, requested_length: u64, allocation_type: u64) bool {
        const release_type: u64 = 0x8000; // MEM_RELEASE
        if ((allocation_type & release_type) == 0) return self.windowsGuestRangeContains(guest_base, requested_length);
        for (&self.windows_virtual_allocations) |*allocation| {
            if (allocation.backing == null or allocation.guest_base != guest_base) continue;
            const expected_length = if (requested_length == 0) allocation.length else requested_length;
            if (requested_length != 0 and expected_length > allocation.length) return false;
            if (allocation.backing) |backing| std.posix.munmap(backing);
            allocation.* = .{};
            if (self.diagnose_abi) log.info("PE64 Windows VirtualFree release: guest_base=0x{x} length={d}", .{ guest_base, expected_length });
            return true;
        }
        return false;
    }

    /// Publish one guest view of a Windows mapping.  The returned value is a
    /// guest address, never the host backing pointer.  A fixed view that
    /// overlaps the PE's ordinary address range is rejected just as the real
    /// Windows VM would reject Xenia's first candidate; Xenia then retries at
    /// its next 8 GiB placement.
    pub fn mapWindowsMemoryView(
        self: *ElfState,
        handle: u64,
        requested_base: u64,
        requested_length: u64,
        backing_offset: u64,
    ) ?u64 {
        const mapping_index = self.windowsMappingIndex(handle) orelse return null;
        const mapping = self.windows_file_mappings[mapping_index];
        if (backing_offset % @as(u64, @intCast(std.heap.page_size_min)) != 0) return null;
        if (backing_offset >= mapping.length) return null;
        const length = if (requested_length == 0)
            mapping.length - backing_offset
        else
            requested_length;
        if (length == 0) return null;
        const end_offset = std.math.add(u64, backing_offset, length) catch return null;
        if (end_offset > mapping.length) return null;

        var guest_base = requested_base;
        if (guest_base == 0) {
            const alignment: u64 = 0x1_0000;
            guest_base = (self.windows_next_memory_view_base + alignment - 1) & ~(alignment - 1);
            while (!self.windowsViewRangeIsFree(guest_base, length)) {
                guest_base = std.math.add(u64, guest_base, alignment) catch return null;
            }
            self.windows_next_memory_view_base = std.math.add(u64, guest_base, length) catch return null;
        } else if (guest_base % @as(u64, @intCast(std.heap.page_size_min)) != 0) {
            return null;
        }
        if (!self.windowsViewRangeIsFree(guest_base, length)) return null;

        for (&self.windows_memory_views) |*view| {
            if (view.length == 0) {
                view.* = .{
                    .guest_base = guest_base,
                    .length = length,
                    .mapping_index = mapping_index,
                    .backing_offset = backing_offset,
                };
                if (self.diagnose_abi) {
                    log.info("PE64 Windows MapViewOfFile: handle=0x{x} guest_base=0x{x} length={d} backing_offset=0x{x}", .{
                        handle,
                        guest_base,
                        length,
                        backing_offset,
                    });
                }
                return guest_base;
            }
        }
        log.err("PE64 Windows MapViewOfFile rejected: view table exhausted handle=0x{x} guest_base=0x{x} length={d}", .{ handle, guest_base, length });
        return null;
    }

    pub fn unmapWindowsMemoryView(self: *ElfState, guest_base: u64) bool {
        for (&self.windows_memory_views) |*view| {
            if (view.length == 0 or view.guest_base != guest_base) continue;
            const mapping_index = view.mapping_index;
            view.* = .{};
            self.releaseClosedWindowsMapping(mapping_index);
            if (self.diagnose_abi) log.info("PE64 Windows UnmapViewOfFile: guest_base=0x{x}", .{guest_base});
            return true;
        }
        return false;
    }

    pub fn closeWindowsMemoryMapping(self: *ElfState, handle: u64) bool {
        const mapping_index = self.windowsMappingIndex(handle) orelse return false;
        self.windows_file_mappings[mapping_index].closed = true;
        self.releaseClosedWindowsMapping(mapping_index);
        if (self.diagnose_abi) log.info("PE64 Windows CloseHandle mapping: handle=0x{x} views_remaining={}", .{ handle, self.windowsMappingHasViews(mapping_index) });
        return true;
    }

    fn windowsMappedMemoryConst(self: *const ElfState, address: u64, count: u64) ?[]const u8 {
        if (count > std.math.maxInt(usize)) return null;
        const end = std.math.add(u64, address, count) catch return null;
        const count_usize: usize = @intCast(count);
        for (self.windows_memory_views) |view| {
            if (view.length == 0 or address < view.guest_base) continue;
            const view_end = std.math.add(u64, view.guest_base, view.length) catch continue;
            if (end > view_end) continue;
            const mapping = self.windows_file_mappings[view.mapping_index];
            const backing = mapping.backing orelse continue;
            const backing_offset = std.math.add(u64, view.backing_offset, address - view.guest_base) catch return null;
            const offset: usize = std.math.cast(usize, backing_offset) orelse return null;
            if (offset > backing.len or count_usize > backing.len - offset) return null;
            return backing[offset..][0..count_usize];
        }
        for (self.windows_virtual_allocations) |allocation| {
            if (allocation.length == 0 or address < allocation.guest_base) continue;
            const allocation_end = std.math.add(u64, allocation.guest_base, allocation.length) catch continue;
            if (end > allocation_end) continue;
            const backing = allocation.backing orelse continue;
            const offset = std.math.cast(usize, address - allocation.guest_base) orelse return null;
            if (offset > backing.len or count_usize > backing.len - offset) return null;
            return backing[offset..][0..count_usize];
        }
        return null;
    }

    fn windowsMappedMemory(self: *ElfState, address: u64, count: u64) ?[]u8 {
        if (count > std.math.maxInt(usize)) return null;
        const end = std.math.add(u64, address, count) catch return null;
        const count_usize: usize = @intCast(count);
        for (self.windows_memory_views) |view| {
            if (view.length == 0 or address < view.guest_base) continue;
            const view_end = std.math.add(u64, view.guest_base, view.length) catch continue;
            if (end > view_end) continue;
            const mapping = self.windows_file_mappings[view.mapping_index];
            const backing = mapping.backing orelse continue;
            const backing_offset = std.math.add(u64, view.backing_offset, address - view.guest_base) catch return null;
            const offset: usize = std.math.cast(usize, backing_offset) orelse return null;
            if (offset > backing.len or count_usize > backing.len - offset) return null;
            return backing[offset..][0..count_usize];
        }
        for (self.windows_virtual_allocations) |allocation| {
            if (allocation.length == 0 or address < allocation.guest_base) continue;
            const allocation_end = std.math.add(u64, allocation.guest_base, allocation.length) catch continue;
            if (end > allocation_end) continue;
            const backing = allocation.backing orelse continue;
            const offset = std.math.cast(usize, address - allocation.guest_base) orelse return null;
            if (offset > backing.len or count_usize > backing.len - offset) return null;
            return backing[offset..][0..count_usize];
        }
        return null;
    }

    pub fn read8(self: *const ElfState, vaddr: u64) u8 {
        if (self.addrToOffset(vaddr)) |off| return self.mem[off];
        if (self.windowsMappedMemoryConst(vaddr, 1)) |bytes| return bytes[0];
        return 0;
    }

    pub fn read16(self: *const ElfState, vaddr: u64) u16 {
        if (self.addrToOffset(vaddr)) |off| {
            if (off + 2 <= self.mem.len) return std.mem.readInt(u16, self.mem[off..][0..2], .little);
        } else if (self.windowsMappedMemoryConst(vaddr, 2)) |bytes| {
            return std.mem.readInt(u16, bytes[0..2], .little);
        }
        return 0;
    }

    pub fn read32(self: *const ElfState, vaddr: u64) u32 {
        if (self.addrToOffset(vaddr)) |off| {
            if (off + 4 <= self.mem.len) return std.mem.readInt(u32, self.mem[off..][0..4], .little);
        } else if (self.windowsMappedMemoryConst(vaddr, 4)) |bytes| {
            return std.mem.readInt(u32, bytes[0..4], .little);
        }
        return 0;
    }

    pub fn read64(self: *const ElfState, vaddr: u64) u64 {
        if (self.addrToOffset(vaddr)) |off| {
            if (off + 8 <= self.mem.len) return std.mem.readInt(u64, self.mem[off..][0..8], .little);
        } else if (self.windowsMappedMemoryConst(vaddr, 8)) |bytes| {
            return std.mem.readInt(u64, bytes[0..8], .little);
        }
        return 0;
    }

    pub fn write8(self: *ElfState, vaddr: u64, val: u8) void {
        self.traceGuestWrite(vaddr, 1, val);
        if (self.addrToOffset(vaddr)) |off| {
            if (off < self.mem.len) self.mem[off] = val;
        } else if (self.windowsMappedMemory(vaddr, 1)) |bytes| {
            bytes[0] = val;
        }
    }

    pub fn write16(self: *ElfState, vaddr: u64, val: u16) void {
        self.traceGuestWrite(vaddr, 2, val);
        if (self.addrToOffset(vaddr)) |off| {
            if (off + 2 <= self.mem.len) std.mem.writeInt(u16, self.mem[off..][0..2], val, .little);
        } else if (self.windowsMappedMemory(vaddr, 2)) |bytes| {
            std.mem.writeInt(u16, bytes[0..2], val, .little);
        }
    }

    pub fn write32(self: *ElfState, vaddr: u64, val: u32) void {
        self.traceGuestWrite(vaddr, 4, val);
        if (self.addrToOffset(vaddr)) |off| {
            if (off + 4 <= self.mem.len) std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
        } else if (self.windowsMappedMemory(vaddr, 4)) |bytes| {
            std.mem.writeInt(u32, bytes[0..4], val, .little);
        }
    }

    pub fn write64(self: *ElfState, vaddr: u64, val: u64) void {
        self.traceGuestWrite(vaddr, 8, val);
        if (self.addrToOffset(vaddr)) |off| {
            if (off + 8 <= self.mem.len) std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
        } else if (self.windowsMappedMemory(vaddr, 8)) |bytes| {
            std.mem.writeInt(u64, bytes[0..8], val, .little);
        }
    }

    fn traceGuestWrite(self: *const ElfState, vaddr: u64, width: u8, value: u64) void {
        const watch = self.trace_write_address orelse return;
        const write_end = vaddr +| @as(u64, width);
        const watch_end = watch +| 8;
        if (vaddr >= watch_end or write_end <= watch) return;
        if (comptime @import("builtin").is_test) return;

        log.info("trace guest write address=0x{x} width={d} value=0x{x} watch=0x{x} rip=0x{x} op={s} len={d} rsp=0x{x} ret=0x{x}", .{
            vaddr,
            width,
            value,
            watch,
            self.regs.rip,
            @tagName(self.last_decoded_op),
            self.last_decoded_len,
            self.regs.rsp,
            self.read64(self.regs.rsp),
        });
    }

    pub fn push(self: *ElfState, val: u64) void {
        self.regs.rsp -|= 8;
        const address = self.regs.rsp +% x64_decoder.segmentBase(&self.regs, .ss, .long64);
        self.write64(address, val);
    }

    pub fn pop(self: *ElfState) u64 {
        const address = self.regs.rsp +% x64_decoder.segmentBase(&self.regs, .ss, .long64);
        const val = self.read64(address);
        self.regs.rsp +|= 8;
        return val;
    }

    fn failWindowsInitTerm(self: *ElfState, begin: u64, end: u64, detail: []const u8) void {
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = .runtime_invariant_failure;
        self.terminated = true;
        if (comptime !@import("builtin").is_test) {
            log.err("invalid Windows CRT initializer table at rip=0x{x}: range=0x{x}..0x{x} {s}", .{ self.regs.rip, begin, end, detail });
        }
    }

    fn finishWindowsInitTerm(self: *ElfState, result: u64) void {
        if (self.windows_initterm_frame_count == 0) {
            self.failWindowsInitTerm(0, 0, "completion without an active frame");
            return;
        }
        const frame_index = self.windows_initterm_frame_count - 1;
        const frame = self.windows_initterm_frames[frame_index];
        self.windows_initterm_frame_count = frame_index;
        self.regs.rax = result;
        self.regs.rip = if (frame.return_is_direct) frame.return_rip else self.pop();
        if (self.diagnose_abi) {
            log.info("Windows CRT initializer table complete callbacks={d} result=0x{x} continuation=0x{x}", .{
                frame.callback_count,
                result,
                self.regs.rip,
            });
        }
    }

    fn continueWindowsInitTerm(self: *ElfState) void {
        if (self.windows_initterm_frame_count == 0) {
            self.failWindowsInitTerm(0, 0, "completion without an active frame");
            return;
        }

        const frame_index = self.windows_initterm_frame_count - 1;
        // `_initterm_e` stops when an initializer reports a nonzero result.
        // The normal `_initterm` callbacks are void and their RAX value is not
        // part of the contract.
        if (self.windows_initterm_frames[frame_index].returns_error and self.regs.rax != 0) {
            self.finishWindowsInitTerm(self.regs.rax);
            return;
        }

        while (self.windows_initterm_frames[frame_index].begin < self.windows_initterm_frames[frame_index].end) {
            const target_slot = self.windows_initterm_frames[frame_index].begin;
            self.windows_initterm_frames[frame_index].begin = target_slot + 8;
            const target = self.read64(target_slot);
            if (target == 0) continue;

            if (self.addrToOffset(target) == null) {
                self.failWindowsInitTerm(
                    target_slot,
                    self.windows_initterm_frames[frame_index].end,
                    "initializer target is outside the guest image",
                );
                return;
            }

            self.windows_initterm_frames[frame_index].callback_count +|= 1;
            self.push(x64_linux_runtime.SYNTHETIC_INITTERM_RETURN);
            self.regs.rip = target;
            if (self.diagnose_abi) {
                log.info("Windows CRT initializer callback {d} target=0x{x} next_slot=0x{x} end=0x{x}", .{
                    self.windows_initterm_frames[frame_index].callback_count,
                    target,
                    self.windows_initterm_frames[frame_index].begin,
                    self.windows_initterm_frames[frame_index].end,
                });
            }
            return;
        }

        self.finishWindowsInitTerm(0);
    }

    /// Start a guest-side walk of a Microsoft CRT `_initterm` table. The PE
    /// import stub has already placed its original return address on the guest
    /// stack, while the direct-call shortcut supplies the continuation here;
    /// both are preserved until every non-null initializer has returned.
    pub fn beginWindowsInitTerm(
        self: *ElfState,
        begin: u64,
        end: u64,
        direct_return_rip: ?u64,
        returns_error: bool,
    ) bool {
        if (begin > end or (begin & 7) != 0 or (end & 7) != 0) {
            self.failWindowsInitTerm(begin, end, "unaligned or reversed range");
            return true;
        }
        const byte_count = end - begin;
        if (byte_count > MAX_WINDOWS_INITTERM_ENTRIES * 8) {
            self.failWindowsInitTerm(begin, end, "initializer table exceeds bounded entry count");
            return true;
        }
        if (byte_count != 0 and self.guestMemory(begin, byte_count) == null) {
            self.failWindowsInitTerm(begin, end, "initializer table is outside guest memory");
            return true;
        }
        if (self.windows_initterm_frame_count >= self.windows_initterm_frames.len) {
            self.failWindowsInitTerm(begin, end, "initializer nesting exceeds bounded frame count");
            return true;
        }

        const frame_index = self.windows_initterm_frame_count;
        self.windows_initterm_frames[frame_index] = .{
            .begin = begin,
            .end = end,
            .return_rip = direct_return_rip orelse 0,
            .return_is_direct = direct_return_rip != null,
            .returns_error = returns_error,
        };
        self.windows_initterm_frame_count += 1;
        self.continueWindowsInitTerm();
        return true;
    }

    pub fn loadElf(self: *ElfState, elf_bytes: []const u8) !void {
        const plan = try elf_loader.planExecutableLoad(self.mem.len, elf_bytes, STACK_SIZE);
        self.mem_base = plan.mem_base;
        self.image_low = plan.image_low;
        self.image_high = plan.image_high;
        self.heap_next = plan.heap_start;
        self.regs.rip = try elf_loader.loadExecutableSegments(self.mem_base, self.mem, elf_bytes);
        log.info("load plan: guest_base=0x{x} image=[0x{x}, 0x{x}) heap=0x{x} entry=0x{x}", .{
            plan.mem_base,
            plan.image_low,
            plan.image_high,
            plan.heap_start,
            plan.entry,
        });
    }

    pub fn startLibcMain(self: *ElfState, main_addr: u64, argc: u64, argv: u64) void {
        self.pending_main_addr = main_addr;
        self.pending_argc = argc;
        self.pending_argv = argv;
        self.init_index = 0;
        self.libc_start_main_trampolined = true;
        self.scheduleNextInitOrMain();
    }

    fn scheduleNextInitOrMain(self: *ElfState) void {
        while (self.init_index < self.init_functions.len) {
            const target = self.init_functions[self.init_index];
            self.init_index += 1;
            if (target == 0 or self.addrToOffset(target) == null) continue;
            self.regs.rdi = self.pending_argc;
            self.regs.rsi = self.pending_argv;
            self.regs.rdx = 0;
            self.push(SYNTHETIC_INIT_RETURN);
            self.regs.rip = target;
            log.info("running ELF init function {d}/{d} at 0x{x}", .{
                self.init_index,
                self.init_functions.len,
                target,
            });
            return;
        }
        self.startMainAfterInit();
    }

    fn startMainAfterInit(self: *ElfState) void {
        self.regs.rdi = self.pending_argc;
        self.regs.rsi = self.pending_argv;
        self.regs.rdx = 0;
        self.push(SYNTHETIC_MAIN_RETURN);
        self.regs.rip = self.pending_main_addr;
    }

    fn handleSyntheticRip(self: *ElfState) bool {
        if (self.regs.rip == SYNTHETIC_WINDOWS_THREAD_RETURN) {
            self.finishWindowsGuestThread();
            return true;
        }
        if (self.regs.rip == SYNTHETIC_WINDOWS_MESSAGE_RETURN) {
            _ = self.finishWindowsMessageDispatch();
            return true;
        }
        if (self.regs.rip == x64_linux_runtime.SYNTHETIC_PTHREAD_ONCE_RETURN) {
            const once_control = self.pop();
            if (once_control != 0) self.write32(once_control, 1);
            self.regs.rax = 0;
            // The word below the once-control is either the original return
            // address of an import stub or the direct continuation saved by
            // the dynamic-call shortcut. Both paths therefore share the same
            // guest-only completion protocol.
            self.regs.rip = self.pop();
            return true;
        }
        if (self.regs.rip == x64_linux_runtime.SYNTHETIC_INITTERM_RETURN) {
            self.continueWindowsInitTerm();
            return true;
        }
        if (self.regs.rip == SYNTHETIC_INIT_RETURN) {
            self.scheduleNextInitOrMain();
            return true;
        }
        if (self.regs.rip == SYNTHETIC_MAIN_RETURN) {
            self.exit_code = self.regs.rax;
            self.termination_reason = .exit_syscall;
            self.terminated = true;
            return true;
        }
        return false;
    }

    fn copyUnresolvedImportName(destination: []u8, source: []const u8) usize {
        @memset(destination, 0);
        const count = @min(destination.len, source.len);
        if (count != 0) @memcpy(destination[0..count], source[0..count]);
        return count;
    }

    /// Record one unresolved import without putting an instruction-wide trace
    /// on the successful path.  Repeated calls to the same symbol are folded
    /// into one record so a bad polling loop cannot flood the terminal or the
    /// detailed `.rosette` log.
    pub fn recordUnresolvedWindowsImport(self: *ElfState, stub: WindowsImportStub) bool {
        const return_rip = self.read64(self.regs.rsp);
        const caller_rip = self.last_instruction_rip;
        for (self.windows_unresolved_imports[0..self.windows_unresolved_import_count]) |*record| {
            if (record.is_dynamic == stub.is_dynamic and
                std.mem.eql(u8, record.dllName(), stub.dll_name) and
                std.mem.eql(u8, record.functionName(), stub.function_name))
            {
                record.occurrences +|= 1;
                record.last_return_rip = return_rip;
                record.last_caller_rip = caller_rip;
                record.last_step = self.executed_steps;
                return false;
            }
        }

        if (self.windows_unresolved_import_count >= self.windows_unresolved_imports.len) return false;
        var record = &self.windows_unresolved_imports[self.windows_unresolved_import_count];
        record.* = .{
            .is_dynamic = stub.is_dynamic,
            .stub_address = self.regs.rip,
            .first_return_rip = return_rip,
            .first_caller_rip = caller_rip,
            .first_step = self.executed_steps,
            .first_rsp = self.regs.rsp,
            .first_rcx = self.regs.rcx,
            .first_rdx = self.regs.rdx,
            .first_r8 = self.regs.r8,
            .first_r9 = self.regs.r9,
            .last_return_rip = return_rip,
            .last_caller_rip = caller_rip,
            .last_step = self.executed_steps,
            .occurrences = 1,
        };
        // The whole-record assignment above intentionally clears the fixed
        // buffers as well. Copy the names afterwards; assigning the lengths
        // inside that literal would be overwritten by the zeroed arrays and
        // make every later occurrence look like a new symbol.
        record.dll_name_len = copyUnresolvedImportName(&record.dll_name, stub.dll_name);
        record.function_name_len = copyUnresolvedImportName(&record.function_name, stub.function_name);
        self.windows_unresolved_import_count += 1;
        return true;
    }

    /// Record that an import completed through the deterministic ABI
    /// fallback.  Called from the Win32 surface, which does not know how the
    /// executor wants to keep evidence.
    pub fn noteWindowsImportFallback(
        self: *ElfState,
        dll_name: []const u8,
        name: []const u8,
        fallback: x64_linux_runtime.ImportFallback,
    ) void {
        _ = self.windows_import_fallbacks.note(
            dll_name,
            name,
            fallback,
            self.executed_steps,
            self.last_instruction_rip,
        );
    }

    /// Report the imports this run completed through the ABI fallback.
    ///
    /// A healthy run says nothing here: the report is emitted only when a
    /// fallback has been taken that has not been described yet.  `full` asks
    /// for every entry (the end-of-run summary); otherwise only the entries
    /// added since the last report are printed, so a long run does not repeat
    /// what it already said.
    pub fn reportWindowsImportFallbacks(self: *ElfState, full: bool) void {
        const ledger = &self.windows_import_fallbacks;
        if (ledger.isEmpty()) return;
        if (!full and ledger.unreported_count == 0) return;

        var order: [x64_linux_runtime.ImportFallbackLedger.capacity]usize = undefined;
        const ranked = ledger.rankedInto(&order);
        log.warn(
            "DEGRADED IMPORTS: names={d} refused={d} calls={d} new_since_last_report={d} overflow_names={d}; these Windows imports were recognized but completed through the deterministic ABI fallback rather than a real implementation",
            .{
                ledger.count,
                ledger.refusedCount(),
                ledger.total_calls,
                ledger.unreported_count,
                ledger.overflow_names,
            },
        );
        for (order[0..ranked]) |index| {
            const entry = &ledger.entries[index];
            if (!full and !entry.unreported) continue;
            log.warn(
                "DEGRADED IMPORT:   {s}!{s} calls={d} convention={s} outcome={s} returned=0x{x} first_step={d} first_caller=0x{x}; {s}",
                .{
                    entry.dll(),
                    entry.name(),
                    entry.calls,
                    @tagName(entry.convention),
                    @tagName(entry.outcome),
                    entry.value,
                    entry.first_step,
                    entry.first_caller_rip,
                    x64_linux_runtime.importFallbackAdvice(.{
                        .convention = entry.convention,
                        .outcome = entry.outcome,
                        .value = entry.value,
                        .last_error = null,
                    }),
                },
            );
        }
        if (ledger.overflow_names > 0) {
            log.warn(
                "DEGRADED IMPORTS:   {d} further distinct names did not fit the bounded ledger; raise ImportFallbackLedger.capacity to see them",
                .{ledger.overflow_names},
            );
        }
        log.warn(
            "DEGRADED IMPORTS: to implement one, add its case to handleCore in src/x64-ASM/windows_runtime.zig; the convention above is what the guest is being told today, derived in src/x64-ASM/windows_import_contract.zig",
            .{},
        );
        ledger.markReported();
    }

    fn handleWindowsImportStub(self: *ElfState) bool {
        const stub = self.windowsImportStubAt(self.regs.rip) orelse return false;
        if (self.diagnose_abi) {
            log.info("PE64 Windows import: {s}!{s} rip=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x} rsp=0x{x}", .{
                stub.dll_name,
                stub.function_name,
                self.regs.rip,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.r8,
                self.regs.r9,
                self.regs.rsp,
            });
        }
        if (self.tryNativeWindowsVulkan(stub.function_name, null)) return !self.terminated;
        if (x64_linux_runtime.tryWindowsFunction(self, stub.dll_name, stub.function_name, null)) return true;
        if (!self.windows_unknown_imports_fatal) {
            // Diagnostic/non-strict mode is useful while inventorying a new
            // Windows image: keep the call boundary valid and make the
            // fallback visible through the degraded counter instead of
            // turning an intentionally permissive run into a host crash.
            const first_observation = self.recordUnresolvedWindowsImport(stub);
            self.windows_unknown_import_calls +|= 1;
            // An unresolved name has the same hazard as a recognized one:
            // a bare zero is `ERROR_SUCCESS`/`S_OK` for whole families of the
            // Win32 ABI.  The contract derives the refusal from the name's
            // shape, so an image Rosetta has never inventoried is refused
            // honestly rather than told its call worked.
            const fallback = x64_linux_runtime.importFallbackFor(stub.dll_name, stub.function_name);
            if (first_observation) {
                log.warn("unresolved Windows import continued with an ABI refusal: {s}!{s} dynamic={} convention={s} returned=0x{x} rip=0x{x} return=0x{x} caller=0x{x} step={d}", .{
                    stub.dll_name,
                    stub.function_name,
                    stub.is_dynamic,
                    @tagName(fallback.convention),
                    fallback.value,
                    self.regs.rip,
                    self.read64(self.regs.rsp),
                    self.last_instruction_rip,
                    self.executed_steps,
                });
            }
            self.windows_degraded_import_calls +|= 1;
            self.noteWindowsImportFallback(stub.dll_name, stub.function_name, fallback);
            if (fallback.last_error) |last_error| self.windows_last_error = last_error;
            self.regs.rax = fallback.value;
            self.regs.rip = self.pop();
            return true;
        }
        self.terminateForUnresolvedWindowsImport(stub.dll_name, stub.function_name);
        return true;
    }

    pub fn localSymbolAddress(self: *const ElfState, name: []const u8) ?u64 {
        for (self.local_symbols) |symbol| {
            if (std.mem.eql(u8, symbol.name, name)) return symbol.value;
        }
        return null;
    }

    pub fn localSymbolNameAt(self: *const ElfState, address: u64) ?[]const u8 {
        for (self.local_symbols) |symbol| {
            if (symbol.value == address) return symbol.name;
        }
        return null;
    }

    fn nearestLocalSymbol(self: *const ElfState, address: u64) ?exit_diagnostics.SymbolizedAddress {
        if (address < self.image_low or address >= self.image_high) return null;
        var best: ?elf_loader.Symbol = null;
        for (self.local_symbols) |symbol| {
            if (symbol.value == 0 or symbol.value > address) continue;
            if (best == null or symbol.value > best.?.value) best = symbol;
        }
        const symbol = best orelse return null;
        return .{ .address = symbol.value, .symbol = symbol.name, .symbol_offset = address - symbol.value };
    }

    fn recordTrace(self: *ElfState, decoded: DecodedInsn) void {
        self.last_instruction_rip = self.regs.rip;
        self.trace_ring.push(.{
            .rip = self.regs.rip,
            .op = decoded.op,
            .len = decoded.len,
            .rsp = self.regs.rsp,
            .rax = self.regs.rax,
            .rcx = self.regs.rcx,
            .rdx = self.regs.rdx,
        });
    }

    /// Keep the Win32 callback investigation local to a real guest callback
    /// frame. The pending-function WndProc is the hand-off from Xenia's UI
    /// loop to its graphics setup queue; tracing every PE call would drown the
    /// useful edge in CRT noise, while tracing only this frame exposes both
    /// the direct queue dispatcher and its std::function target.
    fn traceWindowsCallbackCall(self: *const ElfState, kind: []const u8, target: u64, operand: u64, next_rip: u64) void {
        if (!self.trace_windows_messages or self.windows_message_dispatch_frame_count == 0) return;
        log.info("Windows callback call: kind={s} source_rip=0x{x} target=0x{x} symbol={s} operand=0x{x} next_rip=0x{x} rsp=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x} stack0=0x{x} stack1=0x{x}", .{
            kind,
            self.regs.rip,
            target,
            self.localSymbolNameAt(target) orelse "",
            operand,
            next_rip,
            self.regs.rsp,
            self.regs.rcx,
            self.regs.rdx,
            self.regs.r8,
            self.regs.r9,
            self.read64(self.regs.rsp),
            self.read64(self.regs.rsp +| 8),
        });
    }

    pub fn guestAlloc(self: *ElfState, requested_size: u64, requested_alignment: u64) ?u64 {
        const size = if (requested_size == 0) 1 else requested_size;
        if (size > std.math.maxInt(usize)) {
            if (self.windows_runtime_enabled) log.err("PE64 guest allocation rejected: size={d} exceeds host index width rip=0x{x} op={s} len={d} rsp=0x{x} return=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x}", .{
                size,
                self.regs.rip,
                @tagName(self.last_decoded_op),
                self.last_decoded_len,
                self.regs.rsp,
                self.read64(self.regs.rsp),
                self.regs.rcx,
                self.regs.rdx,
                self.regs.r8,
                self.regs.r9,
            });
            return null;
        }

        var alignment = if (requested_alignment <= 1) @as(u64, 1) else requested_alignment;
        if ((alignment & (alignment - 1)) != 0) {
            var rounded: u64 = 1;
            while (rounded < alignment) {
                if (rounded > (std.math.maxInt(u64) >> 1)) return null;
                rounded <<= 1;
            }
            alignment = rounded;
        }

        const mask = alignment - 1;
        if (self.heap_next > std.math.maxInt(u64) - mask) {
            if (self.windows_runtime_enabled) log.err("PE64 guest allocation rejected: heap cursor overflow heap_next=0x{x} alignment={d}", .{ self.heap_next, alignment });
            return null;
        }
        const aligned = (self.heap_next + mask) & ~mask;
        const heap_limit = if (self.guest_heap_limit != 0)
            self.guest_heap_limit
        else
            self.mem_base + self.mem_size - STACK_SIZE;
        if (aligned >= heap_limit or size > heap_limit - aligned) {
            if (self.windows_runtime_enabled) log.err("PE64 guest allocation rejected: request={d} align={d} heap_next=0x{x} aligned=0x{x} limit=0x{x} mem_base=0x{x} mem_size=0x{x} rip=0x{x} op={s} rsp=0x{x} return=0x{x}", .{
                size,
                alignment,
                self.heap_next,
                aligned,
                heap_limit,
                self.mem_base,
                self.mem_size,
                self.regs.rip,
                @tagName(self.last_decoded_op),
                self.regs.rsp,
                self.read64(self.regs.rsp),
            });
            return null;
        }
        const off = self.addrToOffset(aligned) orelse {
            if (self.windows_runtime_enabled) log.err("PE64 guest allocation rejected: aligned address outside guest range aligned=0x{x} mem_base=0x{x} mem_size=0x{x}", .{ aligned, self.mem_base, self.mem_size });
            return null;
        };
        const size_usize: usize = @intCast(size);
        if (off > self.mem.len or size_usize > self.mem.len - off) {
            if (self.windows_runtime_enabled) log.err("PE64 guest allocation rejected: offset={d} size={d} backing_bytes={d}", .{ off, size_usize, self.mem.len });
            return null;
        }

        @memset(self.mem[off..][0..size_usize], 0);
        if (self.windows_heap_allocation_count < self.windows_heap_allocations.len) {
            self.windows_heap_allocations[self.windows_heap_allocation_count] = .{
                .guest_base = aligned,
                .length = size,
                .active = true,
            };
            self.windows_heap_allocation_count += 1;
        } else if (self.windows_runtime_enabled) {
            log.err("PE64 guest allocation provenance exhausted: address=0x{x} size={d}; future realloc/free validation will reject this block", .{ aligned, size });
        }
        self.heap_next = aligned + size;
        if (self.trace_allocations and !@import("builtin").is_test) {
            log.info("PE64 guest allocation address=0x{x} requested={d} alignment={d} next=0x{x} rip=0x{x} op={s} len={d} rsp=0x{x} ret=0x{x} rcx=0x{x} rdx=0x{x} r8=0x{x} r9=0x{x}", .{
                aligned,
                requested_size,
                alignment,
                self.heap_next,
                self.regs.rip,
                @tagName(self.last_decoded_op),
                self.last_decoded_len,
                self.regs.rsp,
                self.read64(self.regs.rsp),
                self.regs.rcx,
                self.regs.rdx,
                self.regs.r8,
                self.regs.r9,
            });
        }
        return aligned;
    }

    fn findGuestHeapAllocation(self: *const ElfState, guest_base: u64) ?usize {
        var lower: usize = 0;
        var upper = self.windows_heap_allocation_count;
        while (lower < upper) {
            const middle = lower + (upper - lower) / 2;
            const record = self.windows_heap_allocations[middle];
            if (record.guest_base < guest_base) {
                lower = middle + 1;
            } else {
                upper = middle;
            }
        }
        if (lower < self.windows_heap_allocation_count and self.windows_heap_allocations[lower].guest_base == guest_base) {
            return lower;
        }
        return null;
    }

    /// Release the logical ownership of a PE heap block.  The backing bytes
    /// remain in the flat guest memory because other translated code may
    /// still hold a stale pointer; the active bit is what makes a later
    /// realloc/free of that pointer diagnosable instead of silently valid.
    pub fn releaseGuestAllocation(self: *ElfState, guest_base: u64) bool {
        if (guest_base == 0) return true;
        const index = self.findGuestHeapAllocation(guest_base) orelse return false;
        if (!self.windows_heap_allocations[index].active) return false;
        self.windows_heap_allocations[index].active = false;
        self.windows_heap_allocations[index].length = 0;
        return true;
    }

    /// Implement the content-preserving realloc contract used by the PE CRT
    /// and Win32 heap APIs.  `guestAlloc` intentionally zeroes fresh blocks;
    /// that gives `_recalloc` and the newly grown tail the required zero-fill
    /// behavior, while the old bytes are copied before the old record is
    /// retired.  Shrinks stay in place and only reduce the logical extent.
    pub fn reallocateGuest(
        self: *ElfState,
        old_guest_base: u64,
        requested_size: u64,
        requested_alignment: u64,
    ) ?u64 {
        if (old_guest_base == 0) {
            if (requested_size == 0) return null;
            return self.guestAlloc(requested_size, requested_alignment);
        }
        if (requested_size == 0) {
            _ = self.releaseGuestAllocation(old_guest_base);
            return null;
        }

        const old_index = self.findGuestHeapAllocation(old_guest_base) orelse {
            if (self.windows_runtime_enabled) log.err("PE64 realloc rejected unknown block: address=0x{x} requested={d} rip=0x{x}", .{ old_guest_base, requested_size, self.regs.rip });
            return null;
        };
        const old_record = self.windows_heap_allocations[old_index];
        if (!old_record.active or old_record.length == 0) {
            if (self.windows_runtime_enabled) log.err("PE64 realloc rejected inactive block: address=0x{x} requested={d} rip=0x{x}", .{ old_guest_base, requested_size, self.regs.rip });
            return null;
        }
        if (requested_size <= old_record.length) {
            self.windows_heap_allocations[old_index].length = requested_size;
            return old_guest_base;
        }

        const new_guest_base = self.guestAlloc(requested_size, requested_alignment) orelse return null;
        const old_offset = self.addrToOffset(old_guest_base) orelse {
            _ = self.releaseGuestAllocation(new_guest_base);
            return null;
        };
        const new_offset = self.addrToOffset(new_guest_base) orelse {
            _ = self.releaseGuestAllocation(new_guest_base);
            return null;
        };
        const copy_length: usize = @intCast(@min(old_record.length, requested_size));
        @memcpy(self.mem[new_offset..][0..copy_length], self.mem[old_offset..][0..copy_length]);
        self.windows_heap_allocations[old_index].active = false;
        self.windows_heap_allocations[old_index].length = 0;
        return new_guest_base;
    }

    /// Register a Rosetta-owned address for a Windows function obtained
    /// through GetProcAddress or a Vulkan proc-address query. The executable
    /// only sees a guest address; the state intercepts that address before it
    /// attempts to decode synthetic bytes.
    pub fn registerWindowsImportStub(self: *ElfState, dll_name: []const u8, function_name: []const u8) ?u64 {
        for (self.windows_stub_storage[0..self.windows_stub_count]) |stub| {
            if (std.mem.eql(u8, stub.dll_name, dll_name) and std.mem.eql(u8, stub.function_name, function_name)) {
                return stub.address;
            }
        }
        const address = self.guestAlloc(16, 16) orelse return null;
        return if (self.registerWindowsImportStubAt(address, dll_name, function_name)) address else null;
    }

    /// Attach a Windows import descriptor to an already materialised PE IAT
    /// thunk. Direct imports and GetProcAddress results must converge on the
    /// same dispatcher; a byte stub that merely returns zero would bypass the
    /// ABI/runtime and make Vulkan initialization appear to succeed while no
    /// host call occurred.
    pub fn registerWindowsImportStubAt(self: *ElfState, address: u64, dll_name: []const u8, function_name: []const u8) bool {
        if (address == 0 or function_name.len == 0) return false;
        for (self.windows_stub_storage[0..self.windows_stub_count]) |stub| {
            if (stub.address == address) {
                return std.mem.eql(u8, stub.dll_name, dll_name) and
                    std.mem.eql(u8, stub.function_name, function_name);
            }
        }
        if (self.windows_stub_count >= self.windows_stub_storage.len) return false;
        self.windows_stub_storage[self.windows_stub_count] = .{
            .address = address,
            .dll_name = dll_name,
            .function_name = function_name,
        };
        self.windows_stub_count += 1;
        // Keep the address decodable if a caller inspects the thunk outside
        // the fast dispatcher check. F4 is the PE route's explicit import
        // sentinel and is intercepted before normal instruction execution.
        self.write8(address, 0xF4);
        return true;
    }

    pub fn windowsImportStubAt(self: *const ElfState, address: u64) ?WindowsImportStub {
        if (self.windows_direct_stub_count != 0) {
            const direct_bytes = std.math.mul(u64, @intCast(self.windows_direct_stub_count), 16) catch return null;
            const direct_end = std.math.add(u64, self.windows_direct_stub_base, direct_bytes) catch return null;
            if (address >= self.windows_direct_stub_base and address < direct_end) {
                const delta = address - self.windows_direct_stub_base;
                if ((delta & 0xF) != 0) return null;
                const index: usize = @intCast(delta >> 4);
                if (index < self.windows_direct_stub_count) {
                    const stub = self.windows_stub_storage[index];
                    return if (stub.address == address) stub else null;
                }
                return null;
            }
            // Direct PE code lives below the thunk range, while dynamically
            // published proc-address stubs are allocated after that range.
            // This early return is what keeps normal instruction dispatch
            // independent of the total import count.
            if (address < self.windows_direct_stub_base or
                self.windows_stub_count <= self.windows_dynamic_stub_start or
                address < direct_end)
            {
                return null;
            }
        }

        const dynamic_start = @min(self.windows_dynamic_stub_start, self.windows_stub_count);
        for (self.windows_stub_storage[dynamic_start..self.windows_stub_count]) |stub| {
            if (stub.address == address) {
                var dynamic_stub = stub;
                dynamic_stub.is_dynamic = true;
                return dynamic_stub;
            }
        }
        return null;
    }

    /// Compatibility hook used by the shared Mach-O Vulkan forwarder when it
    /// publishes a proc-address token. The Windows route intentionally keeps
    /// proc queries on Microsoft-ABI import stubs, so no SysV token is exposed
    /// to the PE instruction loop; retaining the hook lets the generic
    /// forwarder compile against the same state interface without fabricating
    /// an executable guest address.
    pub fn registerSyntheticThunk(_: *ElfState, _: u64, _: u64, _: []const u8) void {}

    pub fn terminateForUnresolvedWindowsImport(self: *ElfState, dll_name: []const u8, function_name: []const u8) void {
        // `tryFunction` can terminate before the import-stub dispatcher sees
        // the result. Make termination idempotent so that both routes record
        // one observation rather than inflating the inventory.
        if (self.terminated and self.termination_reason == .unresolved_import_result) return;
        const stub = WindowsImportStub{
            .address = self.regs.rip,
            .dll_name = dll_name,
            .function_name = function_name,
            .is_dynamic = self.windowsImportStubAt(self.regs.rip) != null and
                self.windowsImportStubAt(self.regs.rip).?.is_dynamic,
        };
        _ = self.recordUnresolvedWindowsImport(stub);
        self.windows_unknown_import_calls +|= 1;
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = .unresolved_import_result;
        self.terminated = true;
        log.err("unresolved Windows import: {s}!{s} dynamic={} at rip=0x{x} return=0x{x} caller=0x{x} step={d}", .{
            dll_name,
            function_name,
            stub.is_dynamic,
            self.regs.rip,
            self.read64(self.regs.rsp),
            self.last_instruction_rip,
            self.executed_steps,
        });
    }

    /// Give the host-side Windows route one opportunity to own a Vulkan
    /// import. The callback receives this state opaquely so the executor does
    /// not depend on the host forwarder's module graph; a missing callback is
    /// an ordinary fallback to the explicit modelled Windows runtime.
    pub fn tryNativeWindowsVulkan(self: *ElfState, name: []const u8, direct_return_rip: ?u64) bool {
        const callback = self.windows_graphics.hooks.native_vulkan_dispatch orelse return false;
        if (name.len == 0) return false;
        return callback(
            self.windows_graphics.hooks.native_context,
            @ptrCast(self),
            name.ptr,
            name.len,
            direct_return_rip orelse 0,
            if (direct_return_rip != null) 1 else 0,
        ) != 0;
    }

    /// Host CAMetalLayer lookup for the native Vulkan adapter. The callback is
    /// intentionally a host-only pointer-returning seam; no caller may write
    /// this value into guest memory.
    pub fn nativeMetalLayerHostPointer(self: *const ElfState) usize {
        const callback = self.windows_graphics.hooks.native_metal_layer_host_pointer orelse return 0;
        return callback(self.windows_graphics.hooks.native_context);
    }

    pub fn validateNativeMetalLayerToken(_: *const ElfState, token: u64) bool {
        return token == 0xCAFE_BABE_0000_0001;
    }

    pub fn nativeWindowWidth(self: *const ElfState) u32 {
        return self.windows_graphics.window_width;
    }

    pub fn nativeWindowHeight(self: *const ElfState) u32 {
        return self.windows_graphics.window_height;
    }

    /// Called by the real Vulkan forwarder once its guest surface is bound to
    /// the host layer. Keep this observation separate from the synthetic
    /// Windows ledger; the latter still records the guest ABI transition.
    pub fn noteNativeVulkanSurfaceBound(self: *ElfState, _: u64, _: u64, _: u64) void {
        self.windows_graphics.native_vulkan_forwarding = true;
    }

    pub fn terminateUnimplemented(self: *ElfState, d: DecodedInsn) void {
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = .unimplemented_instruction;
        self.terminated = true;
        // Keep the production failure visible, while avoiding an intentional
        // negative-path unit test being reclassified as a test-runner error
        // solely because it exercises this fatal diagnostic.
        if (comptime !@import("builtin").is_test) {
            log.err("unimplemented x86-64 instruction at rip=0x{x}: {s}", .{ self.regs.rip, @tagName(d.op) });
        }
    }

    fn raiseDivideError(self: *ElfState) void {
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = .divide_by_zero;
        self.terminated = true;
        if (comptime !@import("builtin").is_test) {
            log.err("x86 divide error at rip=0x{x} op={s}", .{ self.regs.rip, @tagName(self.last_decoded_op) });
        }
    }

    fn sibAddr(self: *const ElfState, d: *DecodedInsn) void {
        d.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
            .displacement = d.addr,
            .has_index = d.sib_has_index,
            .index_reg = d.sib_index_reg,
            .scale = d.sib_scale,
            .has_base = d.sib_has_base,
            .base_reg = d.sib_base_reg,
            .rip_relative = d.rip_relative,
            .segment = d.segment,
        }, self.regs.rip +% d.len, .bits64, .long64, true);
    }

    fn decodeAt(self: *ElfState) ?DecodedInsn {
        const fetch_address = self.regs.rip +% x64_decoder.segmentBase(&self.regs, .cs, .long64);
        const off = self.addrToOffset(fetch_address) orelse {
            if (self.windows_runtime_enabled) {
                log.err("PE64 decode fetch outside guest image: rip=0x{x} fetch=0x{x} mem=[0x{x},0x{x}) mem_len=0x{x} cs_base=0x{x} thread=0x{x}", .{
                    self.regs.rip,
                    fetch_address,
                    self.mem_base,
                    self.mem_base +| self.mem_size,
                    self.mem.len,
                    self.regs.segments.cs.base,
                    self.active_guest_thread,
                });
            }
            return null;
        };
        const remaining = self.mem.len - off;
        if (remaining == 0) {
            if (self.windows_runtime_enabled) {
                log.err("PE64 decode fetch at guest-image end: rip=0x{x} fetch=0x{x} off=0x{x} mem_len=0x{x} thread=0x{x}", .{
                    self.regs.rip,
                    fetch_address,
                    off,
                    self.mem.len,
                    self.active_guest_thread,
                });
            }
            return null;
        }
        const bytes = self.mem[off..];
        const cache_index: usize = @intCast((fetch_address >> 1) & (PE_DECODE_CACHE_ENTRIES - 1));
        const cache_entry = &self.decode_cache[cache_index];
        var d: DecodedInsn = undefined;
        const cached_len = @as(usize, cache_entry.decoded.len);
        const cache_hit = cache_entry.valid and cache_entry.fetch_address == fetch_address and
            cached_len != 0 and cached_len <= remaining and
            cached_len <= PE_MAX_INSTRUCTION_LENGTH and
            std.mem.eql(u8, cache_entry.bytes[0..cached_len], bytes[0..cached_len]);
        if (cache_hit) {
            d = cache_entry.decoded;
        } else {
            d = decodeInsn(bytes);
            const decoded_len = @as(usize, d.len);
            if (decoded_len != 0 and decoded_len <= remaining and decoded_len <= PE_MAX_INSTRUCTION_LENGTH) {
                cache_entry.* = .{
                    .valid = true,
                    .fetch_address = fetch_address,
                    .decoded = d,
                };
                @memcpy(cache_entry.bytes[0..decoded_len], bytes[0..decoded_len]);
            }
        }
        // The shared decoder records the address-size bit in `d`, but the
        // executor still needs the raw segment override to select DS versus
        // SS for an explicit memory operand.
        const prefixes = x64_decoder.decodeLegacyPrefixes(bytes);
        const addr_size: Size = if (d.has_0x67) .bits32 else .bits64;
        const base: ?RegId = if (d.sib_has_base) d.sib_base_reg else null;
        d.segment = x64_decoder.selectSegment(.explicit_data, base, prefixes.segment_override);
        // Relative control instructions keep their signed displacement in
        // `addr` (and `imm`) for highway.relativeControl.  They are marked
        // rip_relative by the legacy decoder, but that flag describes the
        // encoding rather than a data-memory operand.  Resolving them here
        // would turn the displacement into an absolute address, then the
        // executor would add RIP a second time.  Only data-memory operands
        // need effective-address resolution at this stage.
        const relative_control = switch (d.op) {
            .call_rel32, .jmp_rel8, .jcc_rel8, .jcc_rel32 => true,
            else => false,
        };
        if (!relative_control) {
            d.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
                .displacement = d.addr,
                .has_index = d.sib_has_index,
                .index_reg = d.sib_index_reg,
                .scale = d.sib_scale,
                .has_base = d.sib_has_base,
                .base_reg = d.sib_base_reg,
                .rip_relative = d.rip_relative,
                .segment = d.segment,
            }, self.regs.rip +% d.len, addr_size, .long64, d.op != .lea_reg_mem);
        }
        return d;
    }

    fn step(self: *ElfState) bool {
        if (self.handleSyntheticRip()) return !self.terminated;
        if (self.handleWindowsImportStub()) return !self.terminated;
        if (x64_linux_runtime.tryWindowsGuestCompatibility(self)) return !self.terminated;
        const decoded = self.decodeAt() orelse {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = .decode_failed;
            self.terminated = true;
            return false;
        };
        if (self.trace_string_memory) {
            switch (self.regs.rip) {
                0x14011b6f0 => {
                    const haystack_view = self.regs.rcx;
                    const needle_view = self.regs.rdx;
                    const haystack_length = self.read64(haystack_view);
                    const haystack_data = self.read64(haystack_view +| 8);
                    const needle_length = self.read64(needle_view);
                    const needle_data = self.read64(needle_view +| 8);
                    log.info("PE utf8 find_any_of entry haystack_view=0x{x} data=0x{x} length={d} bytes={any} needle_view=0x{x} data=0x{x} length={d} bytes={any}", .{
                        haystack_view,
                        haystack_data,
                        haystack_length,
                        if (haystack_length == 0) &[_]u8{} else self.guestMemoryConst(haystack_data, @min(haystack_length, 64)) orelse &[_]u8{},
                        needle_view,
                        needle_data,
                        needle_length,
                        if (needle_length == 0) &[_]u8{} else self.guestMemoryConst(needle_data, @min(needle_length, 64)) orelse &[_]u8{},
                    });
                },
                0x140134c80 => {
                    const view = self.regs.rdx;
                    const length = self.read64(view);
                    const data = self.read64(view +| 8);
                    const preview_len: usize = @intCast(@min(length, 64));
                    log.info("PE EscapeString entry result=0x{x} view=0x{x} data=0x{x} length={d} bytes={any}", .{
                        self.regs.rcx,
                        view,
                        data,
                        length,
                        if (preview_len == 0) &[_]u8{} else self.guestMemoryConst(data, preview_len) orelse &[_]u8{},
                    });
                },
                0x140134cc9,
                0x140134d06,
                0x140134e33,
                => log.info("PE EscapeString find_any_of return rip=0x{x} result=0x{x}", .{ self.regs.rip, self.regs.rax }),
                0x140134e5a => {
                    const view = self.regs.rdx;
                    const length = self.read64(view);
                    const data = self.read64(view +| 8);
                    log.info("PE EscapeString escape-basic call view=0x{x} data=0x{x} length={d} bytes={any}", .{
                        view,
                        data,
                        length,
                        if (length == 0) &[_]u8{} else self.guestMemoryConst(data, @min(length, 64)) orelse &[_]u8{},
                    });
                },
                0x140134f6d => {
                    const view = self.regs.rdi;
                    const length = self.read64(view);
                    const data = self.read64(view +| 8);
                    log.info("PE EscapeString plain-string path view=0x{x} data=0x{x} length={d} bytes={any}", .{
                        view,
                        data,
                        length,
                        if (length == 0) &[_]u8{} else self.guestMemoryConst(data, @min(length, 64)) orelse &[_]u8{},
                    });
                },
                else => {},
            }
        }
        if (decoded.op == .invalid) {
            const available: []const u8 = if (self.addrToOffset(self.regs.rip)) |off|
                if (off < self.mem.len) self.mem[@intCast(off)..] else &[_]u8{}
            else
                &[_]u8{};
            const opcode_bytes = available[0..@min(available.len, 16)];
            log.err("invalid instruction at rip=0x{x}, bytes={any}", .{ self.regs.rip, opcode_bytes });
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = .invalid_instruction;
            self.terminated = true;
            return false;
        }
        self.last_decoded_op = decoded.op;
        self.last_decoded_len = decoded.len;
        self.recordTrace(decoded);
        if (self.trace_formatter and self.regs.rip == 0x1400ccf50 and
            (self.trace_formatter_address == null or self.trace_formatter_address.? == self.regs.r8))
        {
            const appender = self.regs.r8;
            log.info("formatter entry appender=0x{x} caller=0x{x} data=0x{x} offset=0x{x} end=0x{x} callback=0x{x} rsp=0x{x} thread=0x{x}", .{
                appender,
                self.read64(self.regs.rsp),
                self.read64(appender),
                self.read64(appender +| 8),
                self.read64(appender +| 0x10),
                self.read64(appender +| 0x18),
                self.regs.rsp,
                self.active_guest_thread,
            });
        }
        // A Windows process can block before its message loop exists.  The
        // bundled Xenia runtime does exactly that: the creating thread enters
        // an internal pthread_spin_lock while the newly-created worker is
        // expected to initialize the shared state and release the lock.  A
        // single cooperative interpreter must service that worker at the
        // architectural PAUSE wait point; waiting for GetMessage here would
        // deadlock the process before any UI or Vulkan import is reachable.
        const is_pause = decoded.op == .nop and decoded.len == 2 and
            self.read8(self.regs.rip) == 0xF3 and self.read8(self.regs.rip +| 1) == 0x90;
        const worker_service_due = if (self.windows_last_service_owner_step) |last|
            self.executed_steps >= last +| WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE
        else
            true;
        if (is_pause and self.windows_runtime_enabled and
            self.windows_active_guest_thread_slot == null and worker_service_due and self.nextWindowsGuestThread() != null)
        {
            _ = self.serviceWindowsGuestThreads(WINDOWS_GUEST_THREAD_SERVICE_SLICE);
            if (self.terminated) return false;
        }
        const trace_this = shouldTraceRip(self, self.regs.rip);
        if (trace_this) {
            log.info("trace before rip=0x{x} op={s} len={d} addr=0x{x} dst={s} src={s} cond={s} rax=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} r8=0x{x} r9=0x{x} r10=0x{x} r11=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x} rsp=0x{x} ret=0x{x} rbp=0x{x} flags=0x{x}", .{
                self.regs.rip,
                @tagName(decoded.op),
                decoded.len,
                decoded.addr,
                @tagName(decoded.dst_reg),
                @tagName(decoded.src_reg),
                @tagName(decoded.cond),
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.rsi,
                self.regs.rdi,
                self.regs.r8,
                self.regs.r9,
                self.regs.r10,
                self.regs.r11,
                self.regs.r12,
                self.regs.r13,
                self.regs.r14,
                self.regs.r15,
                self.regs.rsp,
                self.read64(self.regs.rsp),
                self.regs.rbp,
                self.regs.rflags,
            });
            if (envFlag("ROSETTE_ELF_TRACE_VECTOR")) {
                switch (decoded.op) {
                    .vcvtss2sd,
                    .vcvtsi2sd_xmm_reg,
                    .vcvtsi2sd_xmm_mem,
                    .vdivsd,
                    .vucomisd,
                    => log.info("trace scalar-sse rip=0x{x} op={s} xmm0=0x{x} xmm1=0x{x} xmm2=0x{x} xmm3=0x{x} xmm4=0x{x} xmm5=0x{x} xmm6=0x{x} xmm7=0x{x}", .{
                        self.regs.rip,
                        @tagName(decoded.op),
                        std.mem.readInt(u64, self.xmm[0][0..8], .little),
                        std.mem.readInt(u64, self.xmm[1][0..8], .little),
                        std.mem.readInt(u64, self.xmm[2][0..8], .little),
                        std.mem.readInt(u64, self.xmm[3][0..8], .little),
                        std.mem.readInt(u64, self.xmm[4][0..8], .little),
                        std.mem.readInt(u64, self.xmm[5][0..8], .little),
                        std.mem.readInt(u64, self.xmm[6][0..8], .little),
                        std.mem.readInt(u64, self.xmm[7][0..8], .little),
                    }),
                    else => {},
                }
            }
            if (envFlag("ROSETTE_ELF_TRACE_UTF8")) {
                // This is intentionally opt-in and lives behind the existing
                // RIP trace gate.  The Windows PE uses the same utfcpp
                // helpers for xe::to_utf16. The Windows libstdc++ ABI stores
                // a string_view as {length, data}; logging it in the more
                // familiar {data, length} order produces a convincing but
                // completely false multi-gigabyte input diagnosis.
                if (self.regs.rip == 0x14011f930) {
                    const current = self.read64(self.regs.rcx);
                    const end = self.regs.rdx;
                    const remaining = if (end >= current) end - current else 0;
                    const preview_len: usize = @intCast(@min(remaining, 32));
                    log.info("trace utf8::next iterator=0x{x} current=0x{x} end=0x{x} remaining={d} bytes={any}", .{
                        self.regs.rcx,
                        current,
                        end,
                        remaining,
                        if (preview_len == 0) &[_]u8{} else self.guestMemoryConst(current, preview_len) orelse &[_]u8{},
                    });
                } else if (self.regs.rip == 0x1401307a0) {
                    const source_view = self.regs.rdx;
                    const length = self.read64(source_view);
                    const source = self.read64(source_view +| 8);
                    const preview_len: usize = @intCast(@min(length, 64));
                    log.info("trace threading::set_name view=0x{x} source=0x{x} length={d} bytes={any}", .{
                        source_view,
                        source,
                        length,
                        if (preview_len == 0) &[_]u8{} else self.guestMemoryConst(source, preview_len) orelse &[_]u8{},
                    });
                } else if (self.regs.rip == 0x140122950) {
                    const source_view = self.regs.rdx;
                    const length = self.read64(source_view);
                    const source = self.read64(source_view +| 8);
                    const preview_len: usize = @intCast(@min(length, 64));
                    log.info("trace xe::to_utf16 source_view=0x{x} source=0x{x} length={d} bytes={any}", .{
                        source_view,
                        source,
                        length,
                        if (preview_len == 0) &[_]u8{} else self.guestMemoryConst(source, preview_len) orelse &[_]u8{},
                    });
                }
            }
            switch (decoded.op) {
                .cmp_mem32_imm8 => {
                    log.info("trace memory rip=0x{x} op=cmp_mem32_imm8 address=0x{x} value=0x{x} immediate=0x{x}", .{
                        self.regs.rip,
                        decoded.addr,
                        self.readMemVal(decoded.addr, .bits32),
                        decoded.imm,
                    });
                    // The PE probe currently reaches libstdc++'s regex
                    // compiler.  Its scanner is embedded immediately after
                    // the compiler object; include its state only under the
                    // existing RIP trace gate so a token mismatch can be
                    // attributed without adding normal-run noise.
                    const scanner = self.regs.rsi +| 8;
                    const current = self.read64(scanner +| 0xb0);
                    const end = self.read64(scanner +| 0xb8);
                    const remaining = if (end >= current) end - current else 0;
                    const preview_len: usize = @intCast(@min(remaining, 16));
                    log.info("trace regex scanner scanner=0x{x} state=0x{x} token=0x{x} current=0x{x} end=0x{x} remaining={d} next=0x{x} preview={any}", .{
                        scanner,
                        self.read32(scanner +| 0x88),
                        self.read32(scanner +| 0x90),
                        current,
                        end,
                        remaining,
                        self.read8(current),
                        if (preview_len == 0) &[_]u8{} else self.guestMemoryConst(current, preview_len) orelse &[_]u8{},
                    });
                },
                .mov_reg32_mem32 => {
                    log.info("trace 32-bit memory-load address=0x{x} bytes={any}", .{
                        decoded.addr,
                        self.guestMemoryConst(decoded.addr, 80) orelse &[_]u8{},
                    });
                },
                else => {},
            }
            switch (decoded.op) {
                .vmovups_xmm_mem,
                .vmovups_ymm_mem,
                .vmovaps_xmm_mem,
                .vmovaps_ymm_mem,
                => {
                    const width: usize = if (decoded.vector_256) 32 else 16;
                    log.info("trace vector-load address=0x{x} width={d} xmm_dst={d} xmm_src={d} legacy_sse={} bytes={any}", .{
                        decoded.addr,
                        width,
                        decoded.xmm_dst,
                        decoded.xmm_src,
                        decoded.legacy_sse,
                        self.guestMemoryConst(decoded.addr, width) orelse &[_]u8{},
                    });
                },
                else => {},
            }
        }
        x64_interpreter.execute(self, decoded);
        if (trace_this) {
            if (decoded.op == .mov_mem8_reg8 and self.regs.rip == 0x14011f219) {
                const source_value = self.decodedRegVal(decoded.src_reg, decoded.src_high8, .bits8);
                log.info("trace byte-store rip=0x{x} address=0x{x} src={s} high8={} source=0x{x} stored=0x{x} rdi=0x{x} r13=0x{x}", .{
                    self.regs.rip -| decoded.len,
                    decoded.addr,
                    @tagName(decoded.src_reg),
                    decoded.src_high8,
                    source_value,
                    self.read8(decoded.addr),
                    self.regs.rdi,
                    self.regs.r13,
                });
            }
            log.info("trace after  rip=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} r8=0x{x} r9=0x{x} r10=0x{x} r11=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x} rsp=0x{x} rbp=0x{x} flags=0x{x}", .{
                self.regs.rip,
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.rsi,
                self.regs.rdi,
                self.regs.r8,
                self.regs.r9,
                self.regs.r10,
                self.regs.r11,
                self.regs.r12,
                self.regs.r13,
                self.regs.r14,
                self.regs.r15,
                self.regs.rsp,
                self.regs.rbp,
                self.regs.rflags,
            });
            if (envFlag("ROSETTE_ELF_TRACE_VECTOR")) {
                switch (decoded.op) {
                    .vcvtss2sd,
                    .vcvtsi2sd_xmm_reg,
                    .vcvtsi2sd_xmm_mem,
                    .vdivsd,
                    .vucomisd,
                    => log.info("trace scalar-sse after rip=0x{x} op={s} xmm0=0x{x} xmm1=0x{x} xmm2=0x{x} xmm3=0x{x} xmm4=0x{x} xmm5=0x{x} xmm6=0x{x} xmm7=0x{x} flags=0x{x}", .{
                        self.regs.rip,
                        @tagName(decoded.op),
                        std.mem.readInt(u64, self.xmm[0][0..8], .little),
                        std.mem.readInt(u64, self.xmm[1][0..8], .little),
                        std.mem.readInt(u64, self.xmm[2][0..8], .little),
                        std.mem.readInt(u64, self.xmm[3][0..8], .little),
                        std.mem.readInt(u64, self.xmm[4][0..8], .little),
                        std.mem.readInt(u64, self.xmm[5][0..8], .little),
                        std.mem.readInt(u64, self.xmm[6][0..8], .little),
                        std.mem.readInt(u64, self.xmm[7][0..8], .little),
                        self.regs.rflags,
                    }),
                    else => {},
                }
            }
            switch (decoded.op) {
                .vmovups_mem_xmm,
                .vmovups_mem_ymm,
                .vmovaps_mem_xmm,
                .vmovaps_mem_ymm,
                => {
                    const width: usize = if (decoded.vector_256) 32 else 16;
                    log.info("trace vector-store address=0x{x} width={d} xmm_dst={d} xmm_src={d} legacy_sse={} bytes={any}", .{
                        decoded.addr,
                        width,
                        decoded.xmm_dst,
                        decoded.xmm_src,
                        decoded.legacy_sse,
                        self.guestMemoryConst(decoded.addr, width) orelse &[_]u8{},
                    });
                },
                else => {},
            }
        }
        return !self.terminated;
    }

    pub fn run(self: *ElfState) void {
        self.runWithLimit(2_000_000);
    }

    fn sampleWindowsProgress(self: *const ElfState) WindowsProgressSample {
        const graphics = &self.windows_graphics;
        var vacant: u64 = 0;
        var pending: u64 = 0;
        var runnable: u64 = 0;
        var running: u64 = 0;
        var completed: u64 = 0;
        var failed: u64 = 0;
        for (self.windows_guest_threads) |thread| {
            switch (thread.status) {
                .vacant => vacant += 1,
                .pending => pending += 1,
                .runnable => runnable += 1,
                .running => running += 1,
                .completed => completed += 1,
                .failed => failed += 1,
            }
        }
        return .{
            .import_calls = self.windows_import_calls +% self.windows_unknown_import_calls,
            .graphics_calls = graphics.vulkan_calls +% graphics.native_vulkan_calls +% graphics.command_calls,
            .graphics_frames = graphics.queue_submits +% graphics.presents,
            .message_traffic = self.windows_message_posts +% self.windows_message_deliveries,
            .paint_traffic = self.windows_paint_requests +% self.windows_paint_deliveries,
            .worker_traffic = self.windows_thread_service_calls +% self.windows_thread_yields +%
                self.windows_thread_completions +% self.windows_thread_failures,
            .file_traffic = self.windows_file_open_calls +% self.windows_file_read_calls +%
                self.windows_file_write_calls,
            .worker_states = (vacant << 50) | (pending << 40) | (runnable << 30) |
                (running << 20) | (completed << 10) | failed,
            .rip_low = self.windows_progress.window_rip_low,
            .rip_high = self.windows_progress.window_rip_high,
        };
    }

    fn countWindowsWorkers(self: *const ElfState, status: WindowsGuestThreadStatus) usize {
        var total: usize = 0;
        for (self.windows_guest_threads) |thread| {
            if (thread.status == status) total += 1;
        }
        return total;
    }

    /// One bounded, actionable block describing a run that has stopped making
    /// observable progress.  Emitted at most once per escalation step of a
    /// stall episode, and never at all while any axis is still moving.
    fn reportWindowsStall(self: *ElfState, sample: WindowsProgressSample) void {
        const watchdog = &self.windows_progress;
        const frozen_steps = @as(u64, watchdog.frozen_samples) *| watchdog.interval;
        const graphics = &self.windows_graphics;
        log.warn(
            "PE64 STALL: no observable progress for {d} steps ({d} samples) episode={d} step={d} rip=0x{x} last_op={s} active_thread_slot={?d}",
            .{
                frozen_steps,
                watchdog.frozen_samples,
                watchdog.episodes,
                self.executed_steps,
                self.regs.rip,
                @tagName(self.last_decoded_op),
                self.windows_active_guest_thread_slot,
            },
        );
        log.warn(
            "PE64 STALL:   code visited in the last window: [0x{x},0x{x}] span={d} bytes",
            .{ sample.rip_low, sample.rip_high, sample.rip_high -| sample.rip_low },
        );
        log.warn(
            "PE64 STALL:   frozen axes: imports={d} vulkan_calls={d} submits={d} presents={d} messages={d} paint(requests/deliveries)={d}/{d} workers(service/yield/complete/fail)={d}/{d}/{d}/{d} file_io={d}",
            .{
                sample.import_calls,
                sample.graphics_calls,
                graphics.queue_submits,
                graphics.presents,
                sample.message_traffic,
                self.windows_paint_requests,
                self.windows_paint_deliveries,
                self.windows_thread_service_calls,
                self.windows_thread_yields,
                self.windows_thread_completions,
                self.windows_thread_failures,
                sample.file_traffic,
            },
        );
        for (self.windows_guest_threads, 0..) |thread, index| {
            if (thread.status == .vacant) continue;
            log.warn(
                "PE64 STALL:   worker[{d}] handle=0x{x} start=0x{x} status={s} steps={d}",
                .{ index, thread.handle, thread.start_routine, @tagName(thread.status), thread.executed_steps },
            );
        }

        // Verdicts.  Each is a rule about Rosetta's own boundaries, so they
        // apply to any PE, and each one names who is accountable rather than
        // just restating the symptom.
        const waiting_workers = self.countWindowsWorkers(.pending) + self.countWindowsWorkers(.runnable);
        if (waiting_workers != 0 and self.windows_active_guest_thread_slot == null) {
            log.warn(
                "PE64 STALL:   VERDICT worker starvation: {d} queued guest thread(s) are runnable and the main thread has not reached a cooperative service point (PAUSE, Wait*, or the message pump) in this window. Rosetta is servicing them now as a backstop; if that unblocks the run, the real fix is a service point on whatever the main thread is spinning on.",
                .{waiting_workers},
            );
        }
        if (self.windows_paint_requests != 0 and self.windows_paint_deliveries == 0) {
            log.warn(
                "PE64 STALL:   VERDICT paint requests are not being delivered: the guest asked for {d} repaint(s) and the pump generated none. Check that the requesting window has a registered WndProc and that the guest is pumping messages.",
                .{self.windows_paint_requests},
            );
        }
        if (self.windows_paint_deliveries != 0 and graphics.presents == 0) {
            log.warn(
                "PE64 STALL:   VERDICT the guest is being painted but never presents: {d} WM_PAINT delivered, {d} queue submits, 0 presents. The break is inside the guest's painter or the Vulkan surface it acquired, not in message delivery.",
                .{ self.windows_paint_deliveries, graphics.queue_submits },
            );
        }
        if (!self.windows_import_fallbacks.isEmpty()) {
            log.warn(
                "PE64 STALL:   NOTE {d} import name(s) completed through the deterministic ABI fallback in this run ({d} calls). If the stalled code is waiting on something one of them should have produced, the DEGRADED IMPORTS block above names them.",
                .{ self.windows_import_fallbacks.count, self.windows_import_fallbacks.total_calls },
            );
        }
        if (waiting_workers == 0 and self.windows_paint_requests == 0) {
            log.warn(
                "PE64 STALL:   VERDICT the guest is executing inside a {d}-byte code window without crossing any boundary Rosetta instruments. That is either a compute loop or a spin on guest memory; run with ROSETTE_ELF_TRACE_RIP=0x{x} to see what it reads.",
                .{ sample.rip_high -| sample.rip_low, self.regs.rip },
            );
        }
        log.warn(
            "PE64 STALL: this report repeats on an escalating schedule and stops as soon as any axis moves. Set ROSETTE_PE64_STALL_WATCHDOG=0 to silence it, ROSETTE_PE64_STALL_SAMPLE_STEPS / ROSETTE_PE64_STALL_SAMPLES to retune it.",
            .{},
        );
    }

    /// Sample the progress axes and, when every one of them has been frozen
    /// for long enough, report it once and unblock any starved worker.
    fn checkWindowsProgress(self: *ElfState) void {
        const watchdog = &self.windows_progress;
        if (!watchdog.enabled or !self.windows_runtime_enabled) return;
        if (self.executed_steps < watchdog.next_sample_step) return;
        watchdog.next_sample_step = self.executed_steps +| watchdog.interval;

        const sample = self.sampleWindowsProgress();
        watchdog.window_rip_low = std.math.maxInt(u64);
        watchdog.window_rip_high = 0;

        const frozen = watchdog.have_previous and sample.matches(watchdog.previous);
        watchdog.previous = sample;
        watchdog.have_previous = true;

        if (!frozen) {
            if (watchdog.reported) {
                log.info(
                    "PE64 STALL CLEARED: progress resumed at step {d} rip=0x{x} after {d} frozen sample(s)",
                    .{ self.executed_steps, self.regs.rip, watchdog.frozen_samples },
                );
            }
            watchdog.frozen_samples = 0;
            watchdog.reported = false;
            watchdog.next_report_at = 0;
            return;
        }

        watchdog.frozen_samples +|= 1;
        if (watchdog.frozen_samples < watchdog.threshold) return;
        if (!watchdog.reported) {
            watchdog.episodes +|= 1;
            watchdog.next_report_at = watchdog.frozen_samples;
        }
        if (watchdog.frozen_samples < watchdog.next_report_at) return;

        watchdog.reported = true;
        watchdog.next_report_at = watchdog.frozen_samples *| 2;
        self.reportWindowsStall(sample);

        // Starvation backstop.  The cooperative scheduler normally runs a
        // worker at a PAUSE, a Wait, or a message-pump call.  A main thread
        // that reaches none of those starves every worker forever, and no
        // amount of diagnostics fixes that -- so give the queue a slice here.
        // This is bounded, happens only inside a declared stall, and is
        // reported, so it can never quietly paper over a scheduling defect.
        if (self.windows_active_guest_thread_slot == null and self.nextWindowsGuestThread() != null) {
            const serviced = self.serviceWindowsGuestThreads(WINDOWS_GUEST_THREAD_SERVICE_SLICE);
            watchdog.backstop_services +|= 1;
            log.warn(
                "PE64 STALL:   starvation backstop serviced a queued worker for {d} step(s) (backstop activations: {d})",
                .{ serviced, watchdog.backstop_services },
            );
        }
    }

    fn logGraphicsProgress(self: *const ElfState, steps: u64) void {
        var vacant: u32 = 0;
        var pending: u32 = 0;
        var runnable: u32 = 0;
        var running: u32 = 0;
        var completed: u32 = 0;
        var failed: u32 = 0;
        for (self.windows_guest_threads) |thread| {
            switch (thread.status) {
                .vacant => vacant += 1,
                .pending => pending += 1,
                .runnable => runnable += 1,
                .running => running += 1,
                .completed => completed += 1,
                .failed => failed += 1,
            }
        }
        const active_thread = if (self.windows_active_guest_thread_slot) |index|
            self.windows_guest_threads[index].handle
        else
            0;
        log.info("PE64 graphics progress: steps={d} rip=0x{x} last_op={s} active_thread=0x{x} workers(vacant/pending/runnable/running/completed/failed)={d}/{d}/{d}/{d}/{d}/{d} vk_calls={d} native_vk_calls={d} native_vk_failures={d} commands={d} submits={d} presents={d} phase={s} last_call={s} ordering_violations={d} unmodeled={d}", .{
            steps,
            self.regs.rip,
            @tagName(self.last_decoded_op),
            active_thread,
            vacant,
            pending,
            runnable,
            running,
            completed,
            failed,
            self.windows_graphics.vulkan_calls,
            self.windows_graphics.native_vulkan_calls,
            self.windows_graphics.native_vulkan_failures,
            self.windows_graphics.command_calls,
            self.windows_graphics.queue_submits,
            self.windows_graphics.presents,
            @tagName(self.windows_graphics.phase),
            std.mem.sliceTo(&self.windows_graphics.last_call, 0),
            self.windows_graphics.ordering_violations,
            self.windows_graphics.unmodeled_calls,
        });
    }

    fn logGraphicsStop(self: *const ElfState) void {
        var vacant: u32 = 0;
        var pending: u32 = 0;
        var runnable: u32 = 0;
        var running: u32 = 0;
        var completed: u32 = 0;
        var failed: u32 = 0;
        for (self.windows_guest_threads) |thread| {
            switch (thread.status) {
                .vacant => vacant += 1,
                .pending => pending += 1,
                .runnable => runnable += 1,
                .running => running += 1,
                .completed => completed += 1,
                .failed => failed += 1,
            }
        }
        const active_thread = if (self.windows_active_guest_thread_slot) |index|
            self.windows_guest_threads[index].handle
        else
            0;
        log.info("PE64 execution stop: terminated={} faulted={} reason={s} exit=0x{x} steps={d} rip=0x{x} last_op={s} active_thread=0x{x} workers(vacant/pending/runnable/running/completed/failed)={d}/{d}/{d}/{d}/{d}/{d} vk_calls={d} native_vk_calls={d} native_vk_failures={d} commands={d} submits={d} presents={d} phase={s} last_call={s} last_failure={s} ui_quit={} ui_quit_code=0x{x}", .{
            self.terminated,
            self.faulted,
            @tagName(self.termination_reason),
            self.exit_code,
            self.executed_steps,
            self.regs.rip,
            @tagName(self.last_decoded_op),
            active_thread,
            vacant,
            pending,
            runnable,
            running,
            completed,
            failed,
            self.windows_graphics.vulkan_calls,
            self.windows_graphics.native_vulkan_calls,
            self.windows_graphics.native_vulkan_failures,
            self.windows_graphics.command_calls,
            self.windows_graphics.queue_submits,
            self.windows_graphics.presents,
            @tagName(self.windows_graphics.phase),
            std.mem.sliceTo(&self.windows_graphics.last_call, 0),
            std.mem.sliceTo(&self.windows_graphics.last_failure, 0),
            self.windows_ui_quit_requested,
            self.windows_ui_quit_code,
        });
    }

    /// Execute with a caller-selected bound.  The ELF command keeps its
    /// historical limit, while PE32+ launch sessions need a visible and
    /// bounded policy of their own so a Windows image cannot silently run
    /// forever during bring-up.
    pub fn runWithLimit(self: *ElfState, max_steps: u64) void {
        var steps: u64 = 0;
        const watch_progress = self.windows_runtime_enabled and self.windows_progress.enabled;
        if (watch_progress) self.windows_progress.next_sample_step = self.windows_progress.interval;
        while (!self.terminated and (max_steps == 0 or steps < max_steps)) : (steps +|= 1) {
            self.executed_steps = steps;
            if (watch_progress) {
                // Two comparisons per step is the whole per-instruction cost
                // of the watchdog; everything else happens once per sample
                // window.
                const rip = self.regs.rip;
                if (rip < self.windows_progress.window_rip_low) self.windows_progress.window_rip_low = rip;
                if (rip > self.windows_progress.window_rip_high) self.windows_progress.window_rip_high = rip;
                if (steps >= self.windows_progress.next_sample_step) self.checkWindowsProgress();
            }
            if (steps % 10_000_000 == 0) {
                log.info("step {d}: rip=0x{x}, rax=0x{x}, rbx=0x{x}, rcx=0x{x}, rsi=0x{x}, rdi=0x{x}", .{ steps, self.regs.rip, self.regs.rax, self.regs.rbx, self.regs.rcx, self.regs.rsi, self.regs.rdi });
                if (self.trace_graphics_progress and self.windows_runtime_enabled) self.logGraphicsProgress(steps);
                // Report a newly-degraded import at the checkpoint rather
                // than only at exit: a run that is killed while it is still
                // going would otherwise take that evidence with it.  A run
                // that degrades nothing new says nothing.
                if (self.windows_runtime_enabled) self.reportWindowsImportFallbacks(false);
            }
            if (!self.step()) break;
        }
        if (max_steps != 0 and steps >= max_steps) {
            log.warn("reached max steps ({d})", .{max_steps});
            self.logRegs();
            self.faulted = true;
            self.exit_code = 124;
            self.termination_reason = .max_steps_reached;
            self.terminated = true;
        }
        if (self.trace_graphics_progress and self.windows_runtime_enabled) self.logGraphicsStop();
        if (self.windows_runtime_enabled) self.reportWindowsImportFallbacks(true);
        if (self.faulted) self.logExitDiagnostics();
    }

    fn logExitDiagnostics(self: *const ElfState) void {
        var terminal = exit_diagnostics.TerminalInstruction{
            .address = self.regs.rip,
            .op = switch (self.termination_reason) {
                .invalid_instruction => "invalid",
                .decode_failed => "decode_failed",
                .unimplemented_instruction => @tagName(self.last_decoded_op),
                else => "terminated",
            },
            .length = self.last_decoded_len,
        };
        if (self.addrToOffset(self.regs.rip)) |offset| {
            terminal.byte_count = @intCast(@min(@as(usize, 16), self.mem.len - @as(usize, @intCast(offset))));
            @memcpy(terminal.bytes[0..terminal.byte_count], self.mem[@intCast(offset)..][0..terminal.byte_count]);
        }

        var stack_entries: [16]exit_diagnostics.StackEntry = undefined;
        var stack_count: usize = 0;
        while (stack_count < stack_entries.len) : (stack_count += 1) {
            const slot = self.regs.rsp +| @as(u64, @intCast(stack_count * 8));
            if (self.addrToOffset(slot) == null) break;
            const value = self.read64(slot);
            stack_entries[stack_count] = .{ .slot_address = slot, .value = value };
            if (self.nearestLocalSymbol(value)) |symbol| {
                stack_entries[stack_count].symbol = symbol.symbol;
                stack_entries[stack_count].symbol_offset = symbol.symbol_offset;
            }
        }

        const trace_count = self.trace_ring.count();
        var trace: [TRACE_BUFFER_LEN]exit_diagnostics.TraceEntry = undefined;
        for (0..trace_count) |index| {
            const entry = self.trace_ring.chronological(index) orelse continue;
            trace[index] = .{
                .rip = entry.rip,
                .op = @tagName(entry.op),
                .len = entry.len,
                .rsp = entry.rsp,
                .rax = entry.rax,
                .rcx = entry.rcx,
                .rdx = entry.rdx,
            };
        }

        exit_diagnostics.logExitReport(.{
            .exit_code = self.exit_code,
            .reason = self.termination_reason,
            .faulted = self.faulted,
            .rip = self.regs.rip,
            .regs = .{
                .rax = self.regs.rax,
                .rbx = self.regs.rbx,
                .rcx = self.regs.rcx,
                .rdx = self.regs.rdx,
                .rsi = self.regs.rsi,
                .rdi = self.regs.rdi,
                .rbp = self.regs.rbp,
                .rsp = self.regs.rsp,
                .r8 = self.regs.r8,
                .r9 = self.regs.r9,
                .r10 = self.regs.r10,
                .r11 = self.regs.r11,
                .r12 = self.regs.r12,
                .r13 = self.regs.r13,
                .r14 = self.regs.r14,
                .r15 = self.regs.r15,
            },
            .last_instructions = trace[0..trace_count],
            .terminal_instruction = terminal,
            .stack_entries = stack_entries[0..stack_count],
            .terminal_symbol = self.nearestLocalSymbol(self.regs.rip),
            .runtime_context = .{ .phase = "elf_execution", .steps = self.executed_steps },
            .detail = "Rosette stopped while executing an x86-64 ELF program.",
        });
    }

    fn logRegs(self: *ElfState) void {
        log.info("  regs: rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rsp=0x{x} rbp=0x{x} rip=0x{x}", .{
            self.regs.rax, self.regs.rbx, self.regs.rcx, self.regs.rdx,
            self.regs.rsi, self.regs.rdi, self.regs.rsp, self.regs.rbp,
            self.regs.rip,
        });
        log.info("  flags: cf={d} zf={d} sf={d} of={d}", .{
            @as(u1, @truncate(self.regs.rflags >> 0)),
            @as(u1, @truncate(self.regs.rflags >> 6)),
            @as(u1, @truncate(self.regs.rflags >> 7)),
            @as(u1, @truncate(self.regs.rflags >> 11)),
        });
    }

    pub fn regVal(self: *const ElfState, id: RegId, size: Size) u64 {
        return x64_decoder.regVal(&self.regs, id, size);
    }

    pub fn setReg(self: *ElfState, id: RegId, size: Size, val: u64) void {
        x64_decoder.setReg(&self.regs, id, size, val);
    }

    fn decodedRegVal(self: *const ElfState, id: RegId, high8: bool, size: Size) u64 {
        return x64_decoder.registerOperandValue(&self.regs, .{ .id = id, .high8 = high8 }, size);
    }

    fn setDecodedReg(self: *ElfState, id: RegId, high8: bool, size: Size, val: u64) void {
        x64_decoder.setRegisterOperand(&self.regs, .{ .id = id, .high8 = high8 }, size, val);
    }

    pub fn readMemVal(self: *ElfState, addr: u64, size: Size) u64 {
        return switch (size) {
            .bits8 => self.read8(addr),
            .bits16 => self.read16(addr),
            .bits32 => self.read32(addr),
            .bits64 => self.read64(addr),
        };
    }

    pub fn writeMemVal(self: *ElfState, addr: u64, size: Size, val: u64) void {
        switch (size) {
            .bits8 => self.write8(addr, @intCast(val & 0xFF)),
            .bits16 => self.write16(addr, @intCast(val & 0xFFFF)),
            .bits32 => self.write32(addr, @intCast(val & 0xFFFFFFFF)),
            .bits64 => self.write64(addr, val),
        }
    }

    fn writeExtendedInt80(destination: []u8, value: i64) void {
        std.debug.assert(destination.len >= 10);
        @memset(destination[0..10], 0);
        if (value == 0) return;

        const negative = value < 0;
        const raw: u64 = @bitCast(value);
        const magnitude = if (negative) (~raw +% 1) else raw;
        const leading: u6 = @intCast(@clz(magnitude));
        const msb_index: u6 = 63 - leading;
        const significand = magnitude << (63 - msb_index);
        const exponent: u16 = 16383 + @as(u16, msb_index);
        const sign_exponent: u16 = (if (negative) @as(u16, 0x8000) else 0) | exponent;
        std.mem.writeInt(u64, destination[0..8], significand, .little);
        std.mem.writeInt(u16, destination[8..10], sign_exponent, .little);
    }

    /// Encode an IEEE-754 binary64 value in the little-endian x87 80-bit
    /// memory format.  The PE runner does not need host floating-point state
    /// to survive across instructions, so values are converted at the
    /// operation boundary and the guest stack retains the exact ten bytes in
    /// between.
    fn writeExtendedFloat80(destination: []u8, value: f64) void {
        std.debug.assert(destination.len >= 10);
        @memset(destination[0..10], 0);
        const bits: u64 = @bitCast(value);
        const sign: u16 = if ((bits >> 63) != 0) 0x8000 else 0;
        const fraction = bits & 0x000F_FFFF_FFFF_FFFF;
        const exponent: u16 = @truncate((bits >> 52) & 0x7FF);
        if (exponent == 0 and fraction == 0) return;
        if (exponent == 0x7FF) {
            const significand: u64 = if (fraction == 0)
                0x8000_0000_0000_0000
            else
                0xC000_0000_0000_0000;
            std.mem.writeInt(u64, destination[0..8], significand, .little);
            std.mem.writeInt(u16, destination[8..10], sign | 0x7FFF, .little);
            return;
        }

        var significand: u64 = 0;
        var unbiased: i32 = 0;
        if (exponent == 0) {
            const shift: u6 = @intCast(@clz(fraction));
            significand = fraction << shift;
            unbiased = -1011 - @as(i32, shift);
        } else {
            significand = (fraction | (@as(u64, 1) << 52)) << 11;
            unbiased = @as(i32, exponent) - 1023;
        }
        std.mem.writeInt(u64, destination[0..8], significand, .little);
        std.mem.writeInt(u16, destination[8..10], sign | @as(u16, @intCast(unbiased + 16383)), .little);
    }

    /// Decode the x87 80-bit memory format to the binary64 precision used by
    /// the arithmetic fallback.  This is deliberately separate from the raw
    /// stack accessors: FLD/FSTP m80 use the raw path, while arithmetic and
    /// comparisons need a numerical view of the same value.
    fn readExtendedFloat80(source: []const u8) f64 {
        std.debug.assert(source.len >= 10);
        const significand = std.mem.readInt(u64, source[0..8], .little);
        const sign_exponent = std.mem.readInt(u16, source[8..10], .little);
        const negative = (sign_exponent & 0x8000) != 0;
        const exponent = sign_exponent & 0x7FFF;
        const sign_bit: u64 = if (negative) @as(u64, 1) << 63 else 0;

        if (exponent == 0x7FFF) {
            const special_bits = if ((significand & 0x7FFF_FFFF_FFFF_FFFF) == 0)
                sign_bit | 0x7FF0_0000_0000_0000
            else
                sign_bit | 0x7FF8_0000_0000_0000;
            return @bitCast(special_bits);
        }
        if (significand == 0) return @bitCast(sign_bit);

        const unbiased: i32 = if (exponent == 0) -16382 else @as(i32, exponent) - 16383;
        if (unbiased > 1023) return @bitCast(sign_bit | 0x7FF0_0000_0000_0000);
        if (unbiased >= -1022) {
            const binary64_exponent: u64 = @intCast(unbiased + 1023);
            const fraction = (significand >> 11) & 0x000F_FFFF_FFFF_FFFF;
            return @bitCast(sign_bit | (binary64_exponent << 52) | fraction);
        }
        if (unbiased < -1074) return @bitCast(sign_bit);
        const subnormal_shift: u6 = @intCast(-1011 - unbiased);
        const fraction = significand >> subnormal_shift;
        return @bitCast(sign_bit | (fraction & 0x000F_FFFF_FFFF_FFFF));
    }

    fn x87RawFromInt(value: i64) X87Raw {
        var raw: X87Raw = [_]u8{0} ** 10;
        writeExtendedInt80(&raw, value);
        return raw;
    }

    fn x87RawFromFloat(value: f64) X87Raw {
        var raw: X87Raw = [_]u8{0} ** 10;
        writeExtendedFloat80(&raw, value);
        return raw;
    }

    fn x87Physical(self: *const ElfState, logical: u3) u3 {
        return @truncate(self.x87_top +% logical);
    }

    fn x87StackFault(self: *ElfState, overflow: bool) void {
        // Invalid-operation and stack-fault bits are sticky.  C1 indicates
        // overflow, and is cleared for underflow, matching the masked x87
        // exception behavior used by the native execution path.
        self.x87_status |= 1 << 0;
        self.x87_status |= 1 << 6;
        if (overflow) {
            self.x87_status |= 1 << 9;
        } else {
            self.x87_status &= ~@as(u16, 1 << 9);
        }
    }

    fn x87PushRaw(self: *ElfState, value: X87Raw) bool {
        const next: u3 = @truncate(self.x87_top -% 1);
        if (self.x87_tags[next]) {
            self.x87StackFault(true);
            return false;
        }
        self.x87_top = next;
        self.x87_stack[next] = value;
        self.x87_tags[next] = true;
        return true;
    }

    fn x87GetRaw(self: *ElfState, logical: u3) ?X87Raw {
        const physical = self.x87Physical(logical);
        if (!self.x87_tags[physical]) {
            self.x87StackFault(false);
            return null;
        }
        return self.x87_stack[physical];
    }

    fn x87SetRaw(self: *ElfState, logical: u3, value: X87Raw) bool {
        const physical = self.x87Physical(logical);
        if (!self.x87_tags[physical]) {
            self.x87StackFault(false);
            return false;
        }
        self.x87_stack[physical] = value;
        return true;
    }

    fn x87PopRaw(self: *ElfState) ?X87Raw {
        const physical = self.x87_top;
        if (!self.x87_tags[physical]) {
            self.x87StackFault(false);
            return null;
        }
        const value = self.x87_stack[physical];
        self.x87_tags[physical] = false;
        self.x87_top +%= 1;
        return value;
    }

    fn x87StatusWord(self: *const ElfState) u16 {
        return (self.x87_status & ~@as(u16, 0x3800)) | (@as(u16, self.x87_top) << 11);
    }

    fn x87Reset(self: *ElfState) void {
        self.x87_stack = [_]X87Raw{[_]u8{0} ** 10} ** 8;
        self.x87_tags = [_]bool{false} ** 8;
        self.x87_top = 0;
        self.x87_status = 0;
        self.x87_control = 0x037F;
    }

    fn x87Exchange(self: *ElfState, logical: u3) void {
        const other = self.x87Physical(logical);
        if (!self.x87_tags[self.x87_top] or !self.x87_tags[other]) {
            self.x87StackFault(false);
            return;
        }
        std.mem.swap(X87Raw, &self.x87_stack[self.x87_top], &self.x87_stack[other]);
    }

    fn x87Free(self: *ElfState, logical: u3) void {
        self.x87_tags[self.x87Physical(logical)] = false;
    }

    fn x87Cos(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        const value = readExtendedFloat80(&raw);
        if (!std.math.isFinite(value) or @abs(value) > 0x1p63) {
            self.x87_status |= 1 << 10;
            return;
        }
        self.x87_status &= ~@as(u16, (1 << 9) | (1 << 10));
        _ = self.x87SetRaw(0, x87RawFromFloat(@cos(value)));
    }

    fn x87Sin(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        const value = readExtendedFloat80(&raw);
        if (!std.math.isFinite(value) or @abs(value) > 0x1p63) {
            self.x87_status |= 1 << 10;
            return;
        }
        self.x87_status &= ~@as(u16, (1 << 9) | (1 << 10));
        _ = self.x87SetRaw(0, x87RawFromFloat(@sin(value)));
    }

    fn x87Fchs(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        _ = self.x87SetRaw(0, x87RawFromFloat(-readExtendedFloat80(&raw)));
    }

    fn x87Fabs(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        _ = self.x87SetRaw(0, x87RawFromFloat(@abs(readExtendedFloat80(&raw))));
    }

    fn x87Test(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        const value = readExtendedFloat80(&raw);
        self.x87_status &= ~@as(u16, (1 << 8) | (1 << 10) | (1 << 14));
        if (std.math.isNan(value)) {
            self.x87_status |= (1 << 8) | (1 << 10) | (1 << 14);
        } else if (value == 0.0) {
            self.x87_status |= 1 << 14;
        } else if (value < 0.0) {
            self.x87_status |= 1 << 8;
        }
    }

    fn x87CompareStatus(self: *ElfState, lhs: f64, rhs: f64, pop_result: bool) void {
        self.x87_status &= ~@as(u16, (1 << 8) | (1 << 10) | (1 << 14));
        if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
            self.x87_status |= (1 << 8) | (1 << 10) | (1 << 14);
        } else if (lhs == rhs) {
            self.x87_status |= 1 << 14;
        } else if (lhs < rhs) {
            self.x87_status |= 1 << 8;
        }
        if (pop_result) _ = self.x87PopRaw();
    }

    fn x87F2xm1(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        const value = readExtendedFloat80(&raw);
        if (!std.math.isFinite(value) or value < -1.0 or value > 1.0) {
            self.x87_status |= 1;
            return;
        }
        _ = self.x87SetRaw(0, x87RawFromFloat(std.math.exp2(value) - 1.0));
    }

    fn x87Fyl2x(self: *ElfState, add_one: bool) void {
        const x_raw = self.x87GetRaw(0) orelse return;
        const y_raw = self.x87GetRaw(1) orelse return;
        const x = readExtendedFloat80(&x_raw);
        const y = readExtendedFloat80(&y_raw);
        const argument = if (add_one) x + 1.0 else x;
        if (!std.math.isFinite(argument) or argument <= 0.0) {
            self.x87_status |= 1;
            return;
        }
        _ = self.x87SetRaw(1, x87RawFromFloat(y * std.math.log2(argument)));
        _ = self.x87PopRaw();
    }

    fn x87Fptan(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        const value = readExtendedFloat80(&raw);
        if (!std.math.isFinite(value)) {
            self.x87_status |= 1;
            return;
        }
        _ = self.x87SetRaw(0, x87RawFromFloat(@tan(value)));
        _ = self.x87PushRaw(x87RawFromFloat(1.0));
    }

    fn x87Fpatan(self: *ElfState) void {
        const x_raw = self.x87GetRaw(0) orelse return;
        const y_raw = self.x87GetRaw(1) orelse return;
        const x = readExtendedFloat80(&x_raw);
        const y = readExtendedFloat80(&y_raw);
        _ = self.x87SetRaw(1, x87RawFromFloat(std.math.atan2(y, x)));
        _ = self.x87PopRaw();
    }

    fn x87Fxtract(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        const value = readExtendedFloat80(&raw);
        const parts = std.math.frexp(value);
        _ = self.x87SetRaw(0, x87RawFromFloat(parts.significand * 2.0));
        _ = self.x87PushRaw(x87RawFromInt(parts.exponent - 1));
    }

    fn x87PartialRemainder(self: *ElfState, nearest: bool) void {
        const numerator_raw = self.x87GetRaw(0) orelse return;
        const denominator_raw = self.x87GetRaw(1) orelse return;
        const numerator = readExtendedFloat80(&numerator_raw);
        const denominator = readExtendedFloat80(&denominator_raw);
        if (!std.math.isFinite(numerator) or !std.math.isFinite(denominator) or denominator == 0.0) {
            self.x87_status |= 1 << 10;
            return;
        }

        const quotient = if (nearest) std.math.round(numerator / denominator) else @trunc(numerator / denominator);
        const remainder = numerator - quotient * denominator;
        self.x87_status &= ~@as(u16, (1 << 8) | (1 << 9) | (1 << 10) | (1 << 14));
        const quotient_bits: u64 = @bitCast(@as(i64, @intFromFloat(quotient)));
        if ((quotient_bits & 0x4) != 0) self.x87_status |= 1 << 8;
        if ((quotient_bits & 0x2) != 0) self.x87_status |= 1 << 9;
        if ((quotient_bits & 0x1) != 0) self.x87_status |= 1 << 14;
        _ = self.x87SetRaw(0, x87RawFromFloat(remainder));
    }

    fn x87PartialRemainderNearest(self: *ElfState) void {
        self.x87PartialRemainder(true);
    }

    fn x87PartialRemainderTrunc(self: *ElfState) void {
        self.x87PartialRemainder(false);
    }

    fn x87Fsincos(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        const value = readExtendedFloat80(&raw);
        if (!std.math.isFinite(value)) {
            self.x87_status |= 1;
            return;
        }
        _ = self.x87SetRaw(0, x87RawFromFloat(@sin(value)));
        _ = self.x87PushRaw(x87RawFromFloat(@cos(value)));
    }

    fn x87Frndint(self: *ElfState) void {
        const raw = self.x87GetRaw(0) orelse return;
        const value = readExtendedFloat80(&raw);
        const rounding = (self.x87_control >> 10) & 3;
        const rounded = switch (rounding) {
            0 => std.math.round(value),
            1 => @floor(value),
            2 => @ceil(value),
            else => @trunc(value),
        };
        _ = self.x87SetRaw(0, x87RawFromFloat(rounded));
    }

    fn x87Fscale(self: *ElfState) void {
        const value_raw = self.x87GetRaw(0) orelse return;
        const scale_raw = self.x87GetRaw(1) orelse return;
        const value = readExtendedFloat80(&value_raw);
        const scale = readExtendedFloat80(&scale_raw);
        if (!std.math.isFinite(value) or !std.math.isFinite(scale)) return;
        const exponent: i32 = if (scale >= 2147483647.0)
            std.math.maxInt(i32)
        else if (scale <= -2147483648.0)
            std.math.minInt(i32)
        else
            @intFromFloat(@trunc(scale));
        _ = self.x87SetRaw(0, x87RawFromFloat(std.math.ldexp(value, exponent)));
    }

    fn x87Fclex(self: *ElfState) void {
        self.x87_status &= ~@as(u16, 0x00BF);
    }

    fn x87WriteRawMemory(self: *ElfState, addr: u64, raw: X87Raw) void {
        const output = self.guestMemory(addr, 10) orelse return;
        self.traceGuestWrite(addr, 10, std.mem.readInt(u64, raw[0..8], .little));
        @memcpy(output[0..10], raw[0..]);
    }

    fn x87Compare(self: *ElfState, source: u3, pop_result: bool) void {
        const lhs_raw = self.x87GetRaw(0) orelse return;
        const rhs_raw = self.x87GetRaw(source) orelse return;
        const lhs = readExtendedFloat80(&lhs_raw);
        const rhs = readExtendedFloat80(&rhs_raw);
        self.regs.rflags &= ~(RFL_ZF | RFL_PF | RFL_CF | RFL_OF | RFL_SF | RFL_AF);
        if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
            self.regs.rflags |= RFL_ZF | RFL_PF | RFL_CF;
        } else if (lhs < rhs) {
            self.regs.rflags |= RFL_CF;
        } else if (lhs == rhs) {
            self.regs.rflags |= RFL_ZF;
        }
        if (pop_result) _ = self.x87PopRaw();
    }

    fn x87Divide(numerator: f64, denominator: f64, status: *u16) f64 {
        if (denominator != 0.0) return numerator / denominator;
        if (numerator == 0.0 or std.math.isNan(numerator)) return std.math.nan(f64);
        status.* |= 1 << 2;
        const sign = (@as(u64, @bitCast(numerator)) ^ @as(u64, @bitCast(denominator))) & (@as(u64, 1) << 63);
        return @bitCast(sign | 0x7FF0_0000_0000_0000);
    }

    fn x87MemoryValue(self: *ElfState, d: DecodedInsn, integer: bool) f64 {
        const bits = self.readMemVal(d.addr, d.size);
        if (integer) {
            return switch (d.size) {
                .bits16 => @floatFromInt(@as(i16, @bitCast(@as(u16, @truncate(bits))))),
                .bits32 => @floatFromInt(@as(i32, @bitCast(@as(u32, @truncate(bits))))),
                else => @floatFromInt(@as(i64, @bitCast(bits))),
            };
        }
        return switch (d.size) {
            .bits32 => @floatCast(@as(f32, @bitCast(@as(u32, @truncate(bits))))),
            .bits64 => @bitCast(bits),
            else => 0.0,
        };
    }

    fn x87Memory(self: *ElfState, d: DecodedInsn) void {
        const lhs_raw = self.x87GetRaw(0) orelse return;
        const lhs = readExtendedFloat80(&lhs_raw);
        const rhs = self.x87MemoryValue(d, (d.imm & (@as(u64, 1) << 3)) != 0);
        const operation: u3 = @truncate(d.imm & 7);
        if (operation == 6 or operation == 7) {
            self.x87CompareStatus(lhs, rhs, operation == 7);
            return;
        }
        const result = switch (operation) {
            0 => lhs + rhs,
            1 => lhs * rhs,
            2 => lhs - rhs,
            3 => rhs - lhs,
            4 => x87Divide(lhs, rhs, &self.x87_status),
            5 => x87Divide(rhs, lhs, &self.x87_status),
            else => unreachable,
        };
        _ = self.x87SetRaw(0, x87RawFromFloat(result));
    }

    fn x87Binary(self: *ElfState, d: DecodedInsn) void {
        const destination: u3 = @truncate((d.imm >> 3) & 7);
        const source: u3 = @truncate((d.imm >> 6) & 7);
        const operation: u3 = @truncate(d.imm & 7);
        const lhs_raw = self.x87GetRaw(destination) orelse return;
        const rhs_raw = self.x87GetRaw(source) orelse return;
        const lhs = readExtendedFloat80(&lhs_raw);
        const rhs = readExtendedFloat80(&rhs_raw);
        const result = switch (operation) {
            0 => lhs + rhs,
            1 => lhs * rhs,
            2 => lhs - rhs,
            3 => rhs - lhs,
            4 => x87Divide(lhs, rhs, &self.x87_status),
            5 => x87Divide(rhs, lhs, &self.x87_status),
            else => unreachable,
        };
        _ = self.x87SetRaw(destination, x87RawFromFloat(result));
        if ((d.imm & (1 << 9)) != 0) _ = self.x87PopRaw();
    }

    pub fn readMem128(self: *const ElfState, addr: u64) [16]u8 {
        var value = [_]u8{0} ** 16;
        const source = self.guestMemoryConst(addr, 16) orelse return value;
        @memcpy(value[0..], source);
        return value;
    }

    pub fn writeMem128(self: *ElfState, addr: u64, value: [16]u8) void {
        self.traceGuestVectorWrite(addr, value);
        const destination = self.guestMemory(addr, 16) orelse return;
        @memcpy(destination, value[0..]);
    }

    fn traceGuestVectorWrite(self: *const ElfState, addr: u64, value: [16]u8) void {
        const watch = self.trace_write_address orelse return;
        const write_end = addr +| 16;
        const watch_end = watch +| 8;
        if (addr >= watch_end or write_end <= watch) return;
        if (comptime @import("builtin").is_test) return;

        log.info("trace guest vector write address=0x{x} bytes={any} watch=0x{x} rip=0x{x} op={s} len={d} rsp=0x{x} ret=0x{x}", .{
            addr,
            value,
            watch,
            self.regs.rip,
            @tagName(self.last_decoded_op),
            self.last_decoded_len,
            self.regs.rsp,
            self.read64(self.regs.rsp),
        });
    }

    pub fn guestMemory(self: *ElfState, addr: u64, count: u64) ?[]u8 {
        if (count > std.math.maxInt(usize)) return null;
        const count_usize: usize = @intCast(count);
        if (self.addrToOffset(addr)) |off| {
            const off_usize: usize = @intCast(off);
            if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
            return self.mem[off_usize .. off_usize + count_usize];
        }
        return self.windowsMappedMemory(addr, count);
    }

    pub fn guestMemoryConst(self: *const ElfState, addr: u64, count: u64) ?[]const u8 {
        if (count > std.math.maxInt(usize)) return null;
        const count_usize: usize = @intCast(count);
        if (self.addrToOffset(addr)) |off| {
            const off_usize: usize = @intCast(off);
            if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
            return self.mem[off_usize .. off_usize + count_usize];
        }
        return self.windowsMappedMemoryConst(addr, count);
    }

    pub fn writeHostFd(self: *ElfState, fd: u64, data: []const u8) u64 {
        _ = self;
        const host_fd = hostFdFromGuest(fd) orelse return x64_syscalls.errnoValue(.bad_file_descriptor);
        var written: usize = 0;
        while (written < data.len) {
            const n = std.c.write(host_fd, data[written..].ptr, data.len - written);
            if (n <= 0) return x64_syscalls.errnoValue(.io);
            written += @intCast(n);
        }
        return @intCast(data.len);
    }

    pub fn traceGuestIo(self: *const ElfState, operation: []const u8, fd: u64, addr: u64, count: u64, result: u64) void {
        if (!self.shouldTraceFd(fd)) return;
        log.info("runtime io: {s}(fd={d}, buf=0x{x}, count={d}) -> {d}", .{
            operation,
            fd,
            addr,
            count,
            syscallResult(result),
        });
        if (!self.trace_syscall_bytes) return;
        if (syscallResult(result) <= 0) return;
        const available = @min(count, result);
        const data = self.guestMemoryConst(addr, available) orelse return;
        self.traceDataPreview(operation, fd, data);
    }

    fn traceSyscall(self: *const ElfState, comptime fmt: []const u8, args: anytype) void {
        if (!self.trace_syscalls) return;
        if (self.trace_fd_filter != null) return;
        log.info("syscall: " ++ fmt, args);
    }

    fn traceOpenResult(self: *const ElfState, path: []const u8, flags_raw: u64, mode_raw: u64, result: u64) void {
        if (!self.shouldTraceResultFd(result)) return;
        log.info("syscall: open(\"{s}\", flags=0x{x}, mode=0o{o}) -> {d}", .{
            path,
            flags_raw,
            mode_raw & 0o7777,
            syscallResult(result),
        });
    }

    fn traceCreatResult(self: *const ElfState, path: []const u8, mode_raw: u64, result: u64) void {
        if (!self.shouldTraceResultFd(result)) return;
        log.info("syscall: creat(\"{s}\", mode=0o{o}) -> {d}", .{
            path,
            mode_raw & 0o7777,
            syscallResult(result),
        });
    }

    fn shouldTraceFd(self: *const ElfState, fd: u64) bool {
        if (!self.trace_syscalls) return false;
        if (self.trace_fd_filter) |filter| return fd == filter;
        return true;
    }

    fn shouldTraceResultFd(self: *const ElfState, result: u64) bool {
        if (!self.trace_syscalls) return false;
        if (self.trace_fd_filter) |filter| {
            if (syscallResult(result) < 0) return false;
            return result == filter;
        }
        return true;
    }

    fn traceDataPreview(self: *const ElfState, operation: []const u8, fd: u64, data: []const u8) void {
        if (!self.trace_syscall_bytes) return;
        var preview: [96]u8 = undefined;
        const n = @min(preview.len, data.len);
        for (data[0..n], 0..) |byte, i| {
            preview[i] = switch (byte) {
                0x20...0x7e => byte,
                '\n' => '|',
                '\r', '\t' => ' ',
                else => '.',
            };
        }
        log.info("runtime io bytes: {s}(fd={d}) {d} byte preview \"{s}\"", .{
            operation,
            fd,
            data.len,
            preview[0..n],
        });
    }

    fn abiTraceConfig(self: *const ElfState) x64_guest_abi.TraceConfig {
        return .{
            .trace_calls = self.trace_calls,
            .diagnose = self.diagnose_abi,
        };
    }

    fn noteGuestCall(self: *ElfState, kind: x64_guest_abi.CallKind, target: u64, return_rip: u64) void {
        if (!self.trace_calls) return;
        self.call_stack.enter(self.allocator, self.abiTraceConfig(), .{
            .target = target,
            .return_rip = return_rip,
            .rsp_before_call = self.regs.rsp,
            .symbol = self.localSymbolNameAt(target),
            .kind = kind,
        });
    }

    fn noteGuestReturn(self: *ElfState, return_rip: u64) void {
        if (!self.trace_calls) return;
        self.call_stack.leave(self.abiTraceConfig(), return_rip, self.regs.rsp, self.regs.rax);
    }

    fn setFlagsSub(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applySub(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsAdd(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applyAdd(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsIncDec(self: *ElfState, input: u64, result: u64, size: Size, is_inc: bool) void {
        x64_decoder.applyIncDec(&self.regs.rflags, input, result, size, is_inc);
    }

    fn setFlagsLogic(self: *ElfState, result: u64, size: Size) void {
        x64_decoder.applyLogic(&self.regs.rflags, result, size);
    }

    fn bmiSource(self: *ElfState, d: DecodedInsn) u64 {
        return if (d.is_reg_form) self.regVal(d.src_reg, d.size) else self.readMemVal(d.addr, d.size);
    }

    fn executeBmi(self: *ElfState, d: DecodedInsn) void {
        const mask = maskForSize(d.size);
        const width: u7 = if (d.size == .bits64) 64 else 32;

        switch (d.op) {
            .andn => {
                const source1 = self.regVal(d.src_reg2, d.size);
                const source2 = self.bmiSource(d);
                const result = (~source1 & source2) & mask;
                self.setReg(d.dst_reg, d.size, result);
                self.setFlagsLogic(result, d.size);
            },
            .bzhi => {
                const source = self.bmiSource(d) & mask;
                const index = self.regVal(d.src_reg2, d.size) & 0xFF;
                const result = if (index >= width)
                    source
                else if (index == 0)
                    0
                else
                    source & ((@as(u64, 1) << @as(u6, @intCast(index))) - 1);
                self.setReg(d.dst_reg, d.size, result);
                self.setFlag(RFL_CF, index >= width);
            },
            .mulx => {
                const multiplicand = self.regVal(.dl_dx_edx_rdx, d.size);
                const source = self.bmiSource(d);
                const product = @as(u128, multiplicand) * @as(u128, source);
                const low = @as(u64, @truncate(product)) & mask;
                const high = @as(u64, @truncate(product >> width)) & mask;
                self.setReg(d.dst_reg, d.size, high);
                self.setReg(d.dst_reg2, d.size, low);
            },
            .rorx => {
                const source = self.bmiSource(d) & mask;
                const count: u6 = @intCast(d.imm & (width - 1));
                const result = if (count == 0) blk: {
                    break :blk source;
                } else blk: {
                    const rotate_back: u6 = @intCast((width - count) & 63);
                    break :blk ((source >> count) | (source << rotate_back)) & mask;
                };
                self.setReg(d.dst_reg, d.size, result);
            },
            .shlx => {
                const source = self.bmiSource(d) & mask;
                const count: u6 = @intCast(self.regVal(d.src_reg2, d.size) & (width - 1));
                self.setReg(d.dst_reg, d.size, (source << count) & mask);
            },
            .shrx => {
                const source = self.bmiSource(d) & mask;
                const count: u6 = @intCast(self.regVal(d.src_reg2, d.size) & (width - 1));
                self.setReg(d.dst_reg, d.size, source >> count);
            },
            .sarx => {
                const source = self.bmiSource(d) & mask;
                const count: u6 = @intCast(self.regVal(d.src_reg2, d.size) & (width - 1));
                const signed: i64 = if (d.size == .bits64)
                    @bitCast(source)
                else
                    @as(i32, @bitCast(@as(u32, @truncate(source))));
                self.setReg(d.dst_reg, d.size, @as(u64, @bitCast(signed >> count)) & mask);
            },
            else => unreachable,
        }
    }

    fn vectorAndAllZero(a: [16]u8, b: [16]u8) bool {
        for (a, b) |lhs, rhs| {
            if ((lhs & rhs) != 0) return false;
        }
        return true;
    }

    fn vectorAndNotAllZero(a: [16]u8, b: [16]u8) bool {
        for (a, b) |lhs, rhs| {
            if ((~lhs & rhs) != 0) return false;
        }
        return true;
    }

    fn executeVectorTest(self: *ElfState, d: DecodedInsn) void {
        const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        const low_zf = vectorAndAllZero(self.xmm[d.xmm_src], rhs_low);
        const low_cf = vectorAndNotAllZero(self.xmm[d.xmm_src], rhs_low);
        self.regs.rflags &= ~(RFL_OF | RFL_SF | RFL_ZF | RFL_AF | RFL_PF | RFL_CF);
        if (d.vector_256) {
            const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
            if (low_zf and vectorAndAllZero(self.ymm_hi[d.xmm_src], rhs_high)) self.regs.rflags |= RFL_ZF;
            if (low_cf and vectorAndNotAllZero(self.ymm_hi[d.xmm_src], rhs_high)) self.regs.rflags |= RFL_CF;
        } else {
            if (low_zf) self.regs.rflags |= RFL_ZF;
            if (low_cf) self.regs.rflags |= RFL_CF;
        }
    }

    fn executeVpshufd(self: *ElfState, d: DecodedInsn) void {
        // VPSHUFD shuffles each independent 128-bit lane.  The VEX.128 form
        // also clears the destination's upper YMM half; legacy SSE callers
        // carry `legacy_sse` and must preserve that half.
        const source_low = if (d.is_reg_form) self.xmm[d.xmm_src] else self.readMem128(d.addr);
        var result_low = [_]u8{0} ** 16;
        for (0..4) |lane| {
            const selected: usize = @intCast((d.imm >> @intCast(lane * 2)) & 0x03);
            @memcpy(result_low[lane * 4 ..][0..4], source_low[selected * 4 ..][0..4]);
        }
        self.xmm[d.xmm_dst] = result_low;

        if (d.vector_256) {
            const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src] else self.readMem128(d.addr +% 16);
            var result_high = [_]u8{0} ** 16;
            for (0..4) |lane| {
                const selected: usize = @intCast((d.imm >> @intCast(lane * 2)) & 0x03);
                @memcpy(result_high[lane * 4 ..][0..4], source_high[selected * 4 ..][0..4]);
            }
            self.ymm_hi[d.xmm_dst] = result_high;
        } else if (!d.legacy_sse) {
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    fn vpdpbusdBlock(accumulator: [16]u8, unsigned_source: [16]u8, signed_source: [16]u8) [16]u8 {
        var result = accumulator;
        for (0..4) |lane| {
            const offset = lane * 4;
            var total: i64 = @as(i64, @as(i32, @bitCast(std.mem.readInt(u32, accumulator[offset..][0..4], .little))));
            for (0..4) |byte_index| {
                const unsigned_value: i64 = unsigned_source[offset + byte_index];
                const signed_value: i64 = @as(i8, @bitCast(signed_source[offset + byte_index]));
                total += unsigned_value * signed_value;
            }
            std.mem.writeInt(u32, result[offset..][0..4], @truncate(@as(u64, @bitCast(total))), .little);
        }
        return result;
    }

    fn executeVpdpbusd(self: *ElfState, d: DecodedInsn) void {
        const low_unsigned = self.xmm[d.xmm_src];
        const low_signed = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        self.xmm[d.xmm_dst] = vpdpbusdBlock(self.xmm[d.xmm_dst], low_unsigned, low_signed);
        if (d.vector_256) {
            const high_unsigned = self.ymm_hi[d.xmm_src];
            const high_signed = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
            self.ymm_hi[d.xmm_dst] = vpdpbusdBlock(self.ymm_hi[d.xmm_dst], high_unsigned, high_signed);
        } else {
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    fn executeVexLane128(self: *ElfState, d: DecodedInsn) void {
        if (d.op == .vextractf128) {
            const selected = if ((d.imm & 1) == 0) self.xmm[d.xmm_src] else self.ymm_hi[d.xmm_src];
            if (d.is_reg_form) {
                self.xmm[d.xmm_dst] = selected;
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            } else {
                self.writeMem128(d.addr, selected);
            }
            return;
        }

        const source2 = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        const source1_low = self.xmm[d.xmm_src];
        const source1_high = self.ymm_hi[d.xmm_src];
        const low = if ((d.imm & 1) == 0) source2 else source1_low;
        const high = if ((d.imm & 1) == 0) source1_high else source2;
        self.xmm[d.xmm_dst] = low;
        self.ymm_hi[d.xmm_dst] = high;
    }

    fn executeVexPermute2x128(self: *ElfState, d: DecodedInsn) void {
        const source1_low = self.xmm[d.xmm_src];
        const source1_high = self.ymm_hi[d.xmm_src];
        const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        const selected_low = switch (d.imm & 0x03) {
            0 => source1_low,
            1 => source1_high,
            2 => source2_low,
            3 => source2_high,
            else => unreachable,
        };
        const selected_high = switch ((d.imm >> 4) & 0x03) {
            0 => source1_low,
            1 => source1_high,
            2 => source2_low,
            3 => source2_high,
            else => unreachable,
        };
        var result_low = selected_low;
        var result_high = selected_high;
        if ((d.imm & 0x08) != 0) @memset(&result_low, 0);
        if ((d.imm & 0x80) != 0) @memset(&result_high, 0);
        self.xmm[d.xmm_dst] = result_low;
        self.ymm_hi[d.xmm_dst] = result_high;
    }

    fn executeVphminposuw(self: *ElfState, d: DecodedInsn) void {
        const source = if (d.is_reg_form) self.xmm[d.xmm_src] else self.readMem128(d.addr);
        var minimum: u16 = std.math.maxInt(u16);
        var minimum_index: u16 = 0;
        for (0..8) |lane| {
            const value = std.mem.readInt(u16, source[lane * 2 ..][0..2], .little);
            if (value < minimum) {
                minimum = value;
                minimum_index = @intCast(lane);
            }
        }
        var result = [_]u8{0} ** 16;
        std.mem.writeInt(u16, result[0..2], minimum, .little);
        std.mem.writeInt(u16, result[2..4], minimum_index, .little);
        self.xmm[d.xmm_dst] = result;
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }

    fn executeVexInsertElement(self: *ElfState, d: DecodedInsn) void {
        const element_bytes: usize = switch (d.op) {
            .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8 => 1,
            .vpinsrw => 2,
            .vpinsrd => 4,
            .vpinsrq => 8,
            else => unreachable,
        };
        const destination_lane = @as(usize, @intCast(d.imm)) & ((16 / element_bytes) - 1);
        const source_size: Size = if (d.op == .vpinsrq) .bits64 else .bits32;
        const scalar = if (d.is_reg_form)
            self.regVal(d.src_reg, source_size)
        else
            self.readMemVal(d.addr, d.size);
        var result = self.xmm[d.xmm_src];
        switch (element_bytes) {
            1 => result[destination_lane] = @truncate(scalar),
            2 => std.mem.writeInt(u16, result[destination_lane * 2 ..][0..2], @truncate(scalar), .little),
            4 => std.mem.writeInt(u32, result[destination_lane * 4 ..][0..4], @truncate(scalar), .little),
            8 => std.mem.writeInt(u64, result[destination_lane * 8 ..][0..8], scalar, .little),
            else => unreachable,
        }
        self.xmm[d.xmm_dst] = result;
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }

    fn executeVexExtractElement(self: *ElfState, d: DecodedInsn) void {
        const element_bytes: usize = switch (d.op) {
            .vpextrb => 1,
            .vpextrw => 2,
            .vpextrd => 4,
            .vpextrq => 8,
            else => unreachable,
        };
        const source_lane = @as(usize, @intCast(d.imm)) & ((16 / element_bytes) - 1);
        const value: u64 = switch (element_bytes) {
            1 => self.xmm[d.xmm_src][source_lane],
            2 => std.mem.readInt(u16, self.xmm[d.xmm_src][source_lane * 2 ..][0..2], .little),
            4 => std.mem.readInt(u32, self.xmm[d.xmm_src][source_lane * 4 ..][0..4], .little),
            8 => std.mem.readInt(u64, self.xmm[d.xmm_src][source_lane * 8 ..][0..8], .little),
            else => unreachable,
        };
        if (d.is_reg_form) {
            const destination_size: Size = if (d.op == .vpextrq) .bits64 else .bits32;
            self.setReg(d.dst_reg, destination_size, value);
        } else {
            self.writeMemVal(d.addr, d.size, value);
        }
    }

    fn executeVinsertps(self: *ElfState, d: DecodedInsn) void {
        var result = self.xmm[d.xmm_src];
        const source_lane = @as(usize, @intCast((d.imm >> 6) & 0x03));
        const destination_lane = @as(usize, @intCast((d.imm >> 4) & 0x03));
        const scalar: u32 = if (d.is_reg_form)
            std.mem.readInt(u32, self.xmm[d.xmm_src2][source_lane * 4 ..][0..4], .little)
        else
            @truncate(self.readMemVal(d.addr, .bits32));
        std.mem.writeInt(u32, result[destination_lane * 4 ..][0..4], scalar, .little);
        for (0..4) |lane| {
            if ((d.imm & (@as(u8, 1) << @intCast(lane))) != 0) {
                @memset(result[lane * 4 ..][0..4], 0);
            }
        }
        self.xmm[d.xmm_dst] = result;
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }

    fn executeVectorSpecial(self: *ElfState, d: DecodedInsn) bool {
        switch (d.op) {
            .vptest, .vtestps, .vtestpd => self.executeVectorTest(d),
            .vextractf128, .vinsertf128, .vinserti128 => self.executeVexLane128(d),
            .vperm2f128 => self.executeVexPermute2x128(d),
            .vphminposuw => self.executeVphminposuw(d),
            .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8, .vpinsrd, .vpinsrq, .vpinsrw => self.executeVexInsertElement(d),
            .vpextrb, .vpextrw, .vpextrd, .vpextrq => self.executeVexExtractElement(d),
            .vinsertps => self.executeVinsertps(d),
            else => return false,
        }
        return true;
    }

    fn isVectorOperationRuntime(op: Op) bool {
        const name = @tagName(op);
        return (name.len != 0 and name[0] == 'v') or op == .pmovmskb;
    }

    fn isLegacyVectorTransfer(op: Op) bool {
        return switch (op) {
            .vmovd_xmm_reg32,
            .vmovd_xmm_mem32,
            .vmovd_reg32_xmm,
            .vmovd_mem32_xmm,
            .vmovq_xmm_reg64,
            .vmovq_xmm_mem64,
            .vmovq_reg64_xmm,
            .vmovq_mem64_xmm,
            .vmovq_xmm_xmm,
            => true,
            else => false,
        };
    }

    fn cleoVectorFromSource(self: *ElfState, d: DecodedInsn, index: u8, memory: bool, comptime bits: usize) cleo_routing.wide.Wide(bits) {
        var result = cleo_routing.wide.Wide(bits).zero();
        const low = if (memory) self.readMem128(d.addr) else self.xmm[index];
        @memcpy(result.bytes[0..16], low[0..]);
        if (comptime bits == 256) {
            const high = if (memory) self.readMem128(d.addr +% 16) else self.ymm_hi[index];
            @memcpy(result.bytes[16..32], high[0..]);
        }
        return result;
    }

    fn writeCleoVector(self: *ElfState, d: DecodedInsn, comptime bits: usize, value: cleo_routing.wide.Wide(bits)) void {
        @memcpy(self.xmm[d.xmm_dst][0..], value.bytes[0..16]);
        if (comptime bits == 256) {
            @memcpy(self.ymm_hi[d.xmm_dst][0..], value.bytes[16..32]);
        } else if (!d.legacy_sse) {
            // VEX.128 is a zeroing form. Legacy SSE leaves the architectural
            // upper YMM half untouched, which is why the decoder carries the
            // explicit legacy_sse bit.
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    fn cleoIsFma(operation: cleo_routing.types.Operation) bool {
        return switch (operation) {
            .fma_ps,
            .fma_pd,
            .fms_ps,
            .fms_pd,
            .fnma_ps,
            .fnma_pd,
            .fnms_ps,
            .fnms_pd,
            .fma_addsub_ps,
            .fma_addsub_pd,
            .fma_subadd_ps,
            .fma_subadd_pd,
            => true,
            else => false,
        };
    }

    fn cleoIsUnary(operation: cleo_routing.types.Operation) bool {
        return switch (operation) {
            .sqrt_ps,
            .sqrt_pd,
            .cvt_pd2ps,
            .cvt_ps2pd,
            .cvt_dq2ps,
            .cvt_ps2dq,
            .cvtt_ps2dq,
            .pabs,
            .pnot,
            .compress_ps,
            .compress_pd,
            .expand_ps,
            .expand_pd,
            .cvt_pd2dq,
            .cvtt_pd2dq,
            .cvt_dq2pd,
            .cvt_ph2ps,
            .cvt_ps2ph,
            .cvt_bf16,
            => true,
            else => false,
        };
    }

    fn cleoIsImmediate(operation: cleo_routing.types.Operation) bool {
        return switch (operation) {
            .cmp_ps,
            .cmp_pd,
            .blend_ps,
            .blend_pd,
            .shuf_ps,
            .shuf_pd,
            .dpps,
            .range_ps,
            .range_pd,
            .fixup_ps,
            .fixup_pd,
            .permil,
            .byte_shift_left,
            .byte_shift_right,
            .insert_block,
            .insert_element,
            .insert_ps,
            .rotate_left,
            .rotate_right,
            .ternary_logic,
            .gf2p8_affine,
            .gf2p8_affine_inv,
            .sha1_rnds4,
            => true,
            else => false,
        };
    }

    fn cleoIsBinary(operation: cleo_routing.types.Operation) bool {
        return switch (operation) {
            .add_ps,
            .add_pd,
            .sub_ps,
            .sub_pd,
            .mul_ps,
            .mul_pd,
            .div_ps,
            .div_pd,
            .addsub_ps,
            .addsub_pd,
            .or_ps,
            .or_pd,
            .xor_ps,
            .xor_pd,
            .and_ps,
            .and_pd,
            .andn_ps,
            .andn_pd,
            .cmp_ps,
            .cmp_pd,
            .pmin_signed,
            .pmin_unsigned,
            .pmax_signed,
            .pmax_unsigned,
            .padd,
            .psub,
            .pcmpeq,
            .pcmpgt,
            .pmull,
            .psubs,
            .psubus,
            .psll,
            .psra,
            .psrl,
            .psign,
            .unpck_low,
            .unpck_high,
            .avg,
            .rotate_left_variable,
            .rotate_right_variable,
            .gf2p8_mul,
            .sha1_msg1,
            .sha1_msg2,
            .sha1_nexte,
            .sha256_msg1,
            .sha256_msg2,
            .sha256_rnds2,
            .scale_ps,
            .scale_pd,
            .permute_d,
            .permute_q,
            => true,
            else => false,
        };
    }

    fn executeCleoAtWidth(self: *ElfState, d: DecodedInsn, meta: cleo_routing.types.InstructionMeta, features: cleo_routing.types.FeatureSet, comptime bits: usize) ?cleo_routing.wide.Wide(bits) {
        if (cleoIsUnary(meta.operation)) {
            const source_is_memory = !d.is_reg_form;
            const source_index = if (d.legacy_sse) d.xmm_src2 else d.xmm_src;
            const source = self.cleoVectorFromSource(d, source_index, source_is_memory, bits);
            return cleo_routing.ops.executeUnary(bits, meta, source, features) catch null;
        }

        const source1_index = if (d.legacy_sse) d.xmm_dst else d.xmm_src;
        const source1 = self.cleoVectorFromSource(d, source1_index, false, bits);
        const source2 = self.cleoVectorFromSource(d, d.xmm_src2, !d.is_reg_form, bits);

        if (cleoIsFma(meta.operation)) {
            const op_name = @tagName(d.op);
            const has_132 = std.mem.indexOf(u8, op_name, "132") != null;
            const has_213 = std.mem.indexOf(u8, op_name, "213") != null;
            const destination = self.cleoVectorFromSource(d, d.xmm_dst, false, bits);

            // VEX FMA operand roles are encoded by the mnemonic suffix:
            //   132: dst = (dst * src2) + src1
            //   213: dst = (src1 * dst) + src2
            //   231: dst = (src1 * src2) + dst
            // `source1` is VEX.vvvv and `source2` is ModRM.r/m here.  Keep
            // the role mapping explicit because the operations are not
            // commutative once subtraction/negation is involved.
            const accum = if (has_132) source1 else if (has_213) source2 else destination;
            const lhs = if (has_132) destination else source1;
            const rhs = if (has_213) destination else source2;
            return cleo_routing.ops.executeAccumulate(bits, meta, accum, lhs, rhs, features) catch null;
        }

        if (d.uses_imm and cleoIsImmediate(meta.operation)) {
            return cleo_routing.ops.executeBinaryImmediate(bits, meta, source1, source2, @truncate(d.imm), features) catch null;
        }
        if (cleoIsBinary(meta.operation)) {
            return cleo_routing.ops.executeBinary(bits, meta, source1, source2, features) catch null;
        }
        return null;
    }

    fn executeCleoVectorMove(self: *ElfState, d: DecodedInsn) bool {
        switch (d.op) {
            .vmovss_xmm_mem => {
                // MOVSS/VEX.MOVSS from memory clears the rest of XMM.  A
                // legacy SSE form leaves the architectural YMM upper half
                // alone, while VEX.128 also clears that upper half.
                @memset(&self.xmm[d.xmm_dst], 0);
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @truncate(self.readMemVal(d.addr, .bits32)), .little);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                return true;
            },
            .vmovsd_xmm_mem => {
                // The scalar double-precision memory form has the same
                // upper-lane rule, with an eight-byte low element.
                @memset(&self.xmm[d.xmm_dst], 0);
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], self.readMemVal(d.addr, .bits64), .little);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                return true;
            },
            .vmovss_mem_xmm => {
                self.writeMemVal(d.addr, .bits32, std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little));
                return true;
            },
            .vmovsd_mem_xmm => {
                self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
                return true;
            },
            .vmovss_xmm_xmm => {
                const source = std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little);
                if (!d.legacy_sse) @memset(&self.xmm[d.xmm_dst], 0);
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], source, .little);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                return true;
            },
            .vmovsd_xmm_xmm => {
                const source = std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little);
                if (!d.legacy_sse) @memset(&self.xmm[d.xmm_dst], 0);
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], source, .little);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                return true;
            },
            .vmovq_xmm_xmm => {
                var result = self.xmm[d.xmm_src];
                @memset(result[8..16], 0);
                self.xmm[d.xmm_dst] = result;
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                return true;
            },
            .vmovlps_xmm_xmm_mem64, .vmovlpd_xmm_xmm_mem64 => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], self.readMemVal(d.addr, .bits64), .little);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                return true;
            },
            .vmovlps_mem64_xmm, .vmovlpd_mem64_xmm => {
                self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
                return true;
            },
            .vmovhps_xmm_xmm_mem64, .vmovhpd_xmm_xmm_mem64 => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][8..16], self.readMemVal(d.addr, .bits64), .little);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                return true;
            },
            .vmovhps_mem64_xmm, .vmovhpd_mem64_xmm => {
                self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][8..16], .little));
                return true;
            },
            .vmovhlps => {
                @memcpy(self.xmm[d.xmm_dst][0..8], self.xmm[d.xmm_src][8..16]);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                return true;
            },
            .vmovlhps => {
                @memcpy(self.xmm[d.xmm_dst][8..16], self.xmm[d.xmm_src][0..8]);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                return true;
            },
            else => {},
        }

        const is_load = switch (d.op) {
            .vmovdqu_xmm_mem,
            .vmovdqa_xmm_mem,
            .vmovups_xmm_mem,
            .vmovaps_xmm_mem,
            .vmovupd_xmm_mem,
            .vmovapd_xmm_mem,
            .vmovdqu_ymm_mem,
            .vmovdqa_ymm_mem,
            .vmovups_ymm_mem,
            .vmovaps_ymm_mem,
            .vmovupd_ymm_mem,
            .vmovapd_ymm_mem,
            => true,
            else => false,
        };
        const is_store = switch (d.op) {
            .vmovdqu_mem_xmm,
            .vmovdqa_mem_xmm,
            .vmovups_mem_xmm,
            .vmovaps_mem_xmm,
            .vmovupd_mem_xmm,
            .vmovapd_mem_xmm,
            .vmovdqu_mem_ymm,
            .vmovdqa_mem_ymm,
            .vmovups_mem_ymm,
            .vmovaps_mem_ymm,
            .vmovupd_mem_ymm,
            .vmovapd_mem_ymm,
            => true,
            else => false,
        };
        const is_register = switch (d.op) {
            .vmovdqu_xmm_xmm,
            .vmovdqa_xmm_xmm,
            .vmovups_xmm_xmm,
            .vmovaps_xmm_xmm,
            .vmovupd_xmm_xmm,
            .vmovapd_xmm_xmm,
            .vmovdqu_ymm_ymm,
            .vmovdqa_ymm_ymm,
            .vmovups_ymm_ymm,
            .vmovaps_ymm_ymm,
            .vmovupd_ymm_ymm,
            .vmovapd_ymm_ymm,
            => true,
            else => false,
        };
        if (!is_load and !is_store and !is_register) return false;

        if (is_load) {
            self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            if (d.vector_256) {
                self.ymm_hi[d.xmm_dst] = self.readMem128(d.addr +% 16);
            } else if (!d.legacy_sse) {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        } else if (is_store) {
            self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            if (d.vector_256) self.writeMem128(d.addr +% 16, self.ymm_hi[d.xmm_src]);
        } else {
            self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            if (d.vector_256) self.ymm_hi[d.xmm_dst] = self.ymm_hi[d.xmm_src] else @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
        return true;
    }

    fn tryExecuteCleo(self: *ElfState, d: DecodedInsn) bool {
        // CLEO is an SIMD/VEX/EVEX fallback. Scalar instructions can never
        // route to its registry, so keep them out of this hot path. Legacy
        // scalar-vector move tags are handled by the explicit executor.
        if (!isVectorOperationRuntime(d.op)) return false;
        const route = cleo_routing.CleoRouter.route(
            @tagName(d.op),
            cleo_routing.types.FeatureSet.cleoEmulated(),
            if (d.vector_256) 256 else 128,
        );
        const meta = route.meta orelse return false;
        if (!route.can_route) return false;
        if (!cleoIsFma(meta.operation) and !cleoIsUnary(meta.operation) and
            !(d.uses_imm and cleoIsImmediate(meta.operation)) and !cleoIsBinary(meta.operation)) return false;

        if (d.vector_256) {
            if (self.executeCleoAtWidth(d, meta, route.features, 256)) |result| {
                self.writeCleoVector(d, 256, result);
                return true;
            }
        } else if (self.executeCleoAtWidth(d, meta, route.features, 128)) |result| {
            self.writeCleoVector(d, 128, result);
            return true;
        }
        return false;
    }

    fn vexArithmeticForOp(op: Op) vector_helpers.VexArithmetic {
        return switch (op) {
            .vaddss, .vaddsd, .vaddps, .vaddpd => .add,
            .vmulss, .vmulsd, .vmulps, .vmulpd => .multiply,
            .vsubss, .vsubsd, .vsubps, .vsubpd => .subtract,
            .vdivss, .vdivsd, .vdivps, .vdivpd => .divide,
            .vminss, .vminsd, .vminps, .vminpd => .minimum,
            .vmaxss, .vmaxsd, .vmaxps, .vmaxpd => .maximum,
            else => unreachable,
        };
    }

    fn vexBitwiseForOp(op: Op) vector_helpers.VexBitwise {
        return switch (op) {
            .vandps, .vandpd, .vpand => .@"and",
            .vandnps, .vandnpd, .vpandn => .and_not,
            .vorps, .vorpd, .vpor => .@"or",
            .vxorps, .vxorpd, .vpxor => .xor,
            else => unreachable,
        };
    }

    fn executeVexShufflePd(self: *ElfState, d: DecodedInsn) void {
        const source1_low = self.xmm[d.xmm_src];
        const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        var result_low = [_]u8{0} ** 16;
        const low_first = if ((d.imm & 0x01) != 0) source2_low else source1_low;
        const low_second = if ((d.imm & 0x02) != 0) source2_low else source1_low;
        @memcpy(result_low[0..8], low_first[0..8]);
        @memcpy(result_low[8..16], low_second[0..8]);
        self.xmm[d.xmm_dst] = result_low;

        if (d.vector_256) {
            const source1_high = self.ymm_hi[d.xmm_src];
            const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr +% 16);
            var result_high = [_]u8{0} ** 16;
            const high_first = if ((d.imm & 0x04) != 0) source2_high else source1_high;
            const high_second = if ((d.imm & 0x08) != 0) source2_high else source1_high;
            @memcpy(result_high[0..8], high_first[0..8]);
            @memcpy(result_high[8..16], high_second[0..8]);
            self.ymm_hi[d.xmm_dst] = result_high;
        } else {
            // All VEX.128 instructions zero the destination register's YMM
            // upper half, unlike legacy SSE encodings.
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    /// Execute the VEX floating-point/bitwise subset shared with Mach-O.
    /// Keeping this before the fallback switch is important: the fallback is
    /// intentionally conservative and must never turn an arithmetic vector
    /// instruction into a flags-only operation.
    fn executeSharedVex(self: *ElfState, d: DecodedInsn) bool {
        switch (d.op) {
            .vcvtsi2ss_xmm_reg, .vcvtsi2ss_xmm_mem => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                const integer: i64 = if (d.size == .bits64)
                    @bitCast(if (d.op == .vcvtsi2ss_xmm_reg) self.regVal(d.src_reg, .bits64) else self.readMemVal(d.addr, .bits64))
                else
                    @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2ss_xmm_reg) self.regVal(d.src_reg, .bits32) else self.readMemVal(d.addr, .bits32)))));
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(@as(f32, @floatFromInt(integer))), .little);
                return true;
            },
            .vcvtsi2sd_xmm_reg, .vcvtsi2sd_xmm_mem => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                const integer: i64 = if (d.size == .bits64)
                    @bitCast(if (d.op == .vcvtsi2sd_xmm_reg) self.regVal(d.src_reg, .bits64) else self.readMemVal(d.addr, .bits64))
                else
                    @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2sd_xmm_reg) self.regVal(d.src_reg, .bits32) else self.readMemVal(d.addr, .bits32)))));
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(@as(f64, @floatFromInt(integer))), .little);
                return true;
            },
            .vcvtss2sd => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                const source_bits: u32 = if (d.is_reg_form)
                    std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
                else
                    @truncate(self.readMemVal(d.addr, .bits32));
                const converted: f64 = @floatCast(@as(f32, @bitCast(source_bits)));
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(converted), .little);
                return true;
            },
            .vcvtsd2ss => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
                const source_bits: u64 = if (d.is_reg_form)
                    std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
                else
                    self.readMemVal(d.addr, .bits64);
                const converted: f32 = @floatCast(@as(f64, @bitCast(source_bits)));
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(converted), .little);
                return true;
            },
            .vcvtps2pd => {
                vector_helpers.executeVexConvertFloatPacked(self, d, .single_to_double);
                return true;
            },
            .vcvtpd2ps => {
                vector_helpers.executeVexConvertFloatPacked(self, d, .double_to_single);
                return true;
            },
            .vaddss, .vmulss, .vsubss, .vdivss, .vminss, .vmaxss => {
                vector_helpers.executeVexScalarF32(self, d, vexArithmeticForOp(d.op));
                return true;
            },
            .vaddsd, .vmulsd, .vsubsd, .vdivsd, .vminsd, .vmaxsd => {
                vector_helpers.executeVexScalarF64(self, d, vexArithmeticForOp(d.op));
                return true;
            },
            .vaddps, .vmulps, .vsubps, .vdivps, .vminps, .vmaxps => {
                vector_helpers.executeVexPackedF32(self, d, vexArithmeticForOp(d.op));
                return true;
            },
            .vaddpd, .vmulpd, .vsubpd, .vdivpd, .vminpd, .vmaxpd => {
                vector_helpers.executeVexPackedF64(self, d, vexArithmeticForOp(d.op));
                return true;
            },
            .vpacksswb, .vpackuswb, .vpackssdw, .vpackusdw => {
                const operation: vector_helpers.PackedPackOperation = switch (d.op) {
                    .vpacksswb => .signed_words_to_bytes,
                    .vpackuswb => .unsigned_words_to_bytes,
                    .vpackssdw => .signed_dwords_to_words,
                    .vpackusdw => .unsigned_dwords_to_words,
                    else => unreachable,
                };
                vector_helpers.executeVexPackedPack(self, d, operation);
                return true;
            },
            .vsqrtss => {
                vector_helpers.executeVexSqrtScalarF32(self, d);
                return true;
            },
            .vsqrtsd => {
                vector_helpers.executeVexSqrtScalarF64(self, d);
                return true;
            },
            .vsqrtps => {
                vector_helpers.executeVexSqrtPackedF32(self, d);
                return true;
            },
            .vsqrtpd => {
                vector_helpers.executeVexSqrtPackedF64(self, d);
                return true;
            },
            .vcmpps => {
                if (!vector_helpers.executeVexComparePacked(self, d, false)) self.terminateUnimplemented(d);
                return true;
            },
            .vcmppd => {
                if (!vector_helpers.executeVexComparePacked(self, d, true)) self.terminateUnimplemented(d);
                return true;
            },
            .vcmpss => {
                if (!vector_helpers.executeVexCompareScalar(self, d, false)) self.terminateUnimplemented(d);
                return true;
            },
            .vcmpsd => {
                if (!vector_helpers.executeVexCompareScalar(self, d, true)) self.terminateUnimplemented(d);
                return true;
            },
            .vshufpd => {
                self.executeVexShufflePd(d);
                return true;
            },
            .vunpcklps, .vunpckhps, .vunpcklpd, .vunpckhpd => {
                vector_helpers.executeVexPackedUnpack(self, d);
                return true;
            },
            .vrcpps => {
                vector_helpers.executeVexReciprocalPacked(self, d, false);
                return true;
            },
            .vrsqrtps => {
                vector_helpers.executeVexReciprocalPacked(self, d, true);
                return true;
            },
            .vrcpss => {
                vector_helpers.executeVexReciprocalScalar(self, d, false);
                return true;
            },
            .vrsqrtss => {
                vector_helpers.executeVexReciprocalScalar(self, d, true);
                return true;
            },
            .vcvtdq2ps => {
                vector_helpers.executeVexConvertPacked(self, d, .dword_to_float);
                return true;
            },
            .vcvtps2dq => {
                vector_helpers.executeVexConvertPacked(self, d, .float_to_dword_round);
                return true;
            },
            .vcvttps2dq => {
                vector_helpers.executeVexConvertPacked(self, d, .float_to_dword_truncate);
                return true;
            },
            .vucomiss => {
                const lhs: f32 = @bitCast(std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little));
                const rhs_bits: u32 = if (d.is_reg_form)
                    std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
                else
                    @truncate(self.readMemVal(d.addr, .bits32));
                vector_helpers.setVexComparisonFlags(self, lhs, @as(f32, @bitCast(rhs_bits)));
                return true;
            },
            .vucomisd => {
                const lhs: f64 = @bitCast(std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
                const rhs_bits: u64 = if (d.is_reg_form)
                    std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
                else
                    self.readMemVal(d.addr, .bits64);
                vector_helpers.setVexComparisonFlags(self, lhs, @as(f64, @bitCast(rhs_bits)));
                return true;
            },
            .vandps, .vandpd, .vandnps, .vandnpd, .vorps, .vorpd, .vxorps, .vxorpd, .vpor, .vpand, .vpandn, .vpxor => {
                vector_helpers.executeVexBitwise(self, d, vexBitwiseForOp(d.op));
                return true;
            },
            .vroundss => {
                vector_helpers.executeVexRoundScalarF32(self, d);
                return true;
            },
            .vroundsd => {
                vector_helpers.executeVexRoundScalarF64(self, d);
                return true;
            },
            .vroundps => {
                vector_helpers.executeVexRoundPackedF32(self, d);
                return true;
            },
            .vroundpd => {
                vector_helpers.executeVexRoundPackedF64(self, d);
                return true;
            },
            .vcvttss2si => {
                vector_helpers.executeVexFloatToSigned(self, d, false, true);
                return true;
            },
            .vcvtss2si => {
                vector_helpers.executeVexFloatToSigned(self, d, false, false);
                return true;
            },
            .vcvttsd2si => {
                vector_helpers.executeVexFloatToSigned(self, d, true, true);
                return true;
            },
            .vcvtsd2si => {
                vector_helpers.executeVexFloatToSigned(self, d, true, false);
                return true;
            },
            .pmovmskb, .vpmovmskb, .vpmovmskb_ymm, .vmovmskps, .vmovmskpd => {
                vector_helpers.executeVexMoveMask(self, d);
                return true;
            },
            .vpmuludq => {
                vector_helpers.executeVexMultiplyUnsignedEvenDwords(self, d);
                return true;
            },
            .vpblendw => {
                vector_helpers.executeVexBlendWords(self, d);
                return true;
            },
            .vblendvps => {
                vector_helpers.executeVexBlendVariable(self, d, 32);
                return true;
            },
            .vblendvpd => {
                vector_helpers.executeVexBlendVariable(self, d, 64);
                return true;
            },
            .vpblendvb => {
                vector_helpers.executeVexBlendVariable(self, d, 8);
                return true;
            },
            .vpsllw => {
                vector_helpers.executeVexPackedShift(self, d, 16, true, false, false);
                return true;
            },
            .vpsrlw => {
                vector_helpers.executeVexPackedShift(self, d, 16, false, false, false);
                return true;
            },
            .vpsraw => {
                vector_helpers.executeVexPackedShift(self, d, 16, false, true, false);
                return true;
            },
            .vpslld => {
                vector_helpers.executeVexPackedShift(self, d, 32, true, false, false);
                return true;
            },
            .vpsrld => {
                vector_helpers.executeVexPackedShift(self, d, 32, false, false, false);
                return true;
            },
            .vpsrad => {
                vector_helpers.executeVexPackedShift(self, d, 32, false, true, false);
                return true;
            },
            .vpsllq => {
                vector_helpers.executeVexPackedShift(self, d, 64, true, false, false);
                return true;
            },
            .vpsrlq => {
                vector_helpers.executeVexPackedShift(self, d, 64, false, false, false);
                return true;
            },
            .vpslldq => {
                vector_helpers.executeVexPackedShift(self, d, 8, true, false, true);
                return true;
            },
            .vpsrldq => {
                vector_helpers.executeVexPackedShift(self, d, 8, false, false, true);
                return true;
            },
            .vpmullw => {
                vector_helpers.executeVexPackedInteger(self, d, 16, .mul_low);
                return true;
            },
            .vpmulld_38 => {
                vector_helpers.executeVexPackedInteger(self, d, 32, .mul_low);
                return true;
            },
            .vpmulhw => {
                vector_helpers.executeVexPackedMulHigh(self, d, true);
                return true;
            },
            .vpmulhuw => {
                vector_helpers.executeVexPackedMulHigh(self, d, false);
                return true;
            },
            .vpminsb => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 8, .signed = true, .take_max = false });
                return true;
            },
            .vpminsd => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 32, .signed = true, .take_max = false });
                return true;
            },
            .vpminuw => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 16, .signed = false, .take_max = false });
                return true;
            },
            .vpminud => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 32, .signed = false, .take_max = false });
                return true;
            },
            .vpminub => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 8, .signed = false, .take_max = false });
                return true;
            },
            .vpmaxsb => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 8, .signed = true, .take_max = true });
                return true;
            },
            .vpmaxsd => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 32, .signed = true, .take_max = true });
                return true;
            },
            .vpmaxuw => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 16, .signed = false, .take_max = true });
                return true;
            },
            .vpmaxud => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 32, .signed = false, .take_max = true });
                return true;
            },
            .vpmaxub => {
                vector_helpers.executeVexPackedMinMax(self, d, .{ .lane_bits = 8, .signed = false, .take_max = true });
                return true;
            },
            else => return false,
        }
    }

    fn executeHighwayRegisterBinary(self: *ElfState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp) void {
        const width: x64_decoder.highway.Width = switch (d.size) {
            .bits8 => .bits8,
            .bits16 => .bits16,
            .bits32 => .bits32,
            .bits64 => .bits64,
        };
        const lhs = self.decodedRegVal(d.dst_reg, d.dst_high8, d.size);
        const rhs = self.decodedRegVal(d.src_reg, d.src_high8, d.size);
        const evaluated = x64_decoder.highway.evaluate(op, width, lhs, rhs, self.regs.rflags);
        if (shouldTraceRip(self, self.regs.rip)) {
            log.info("trace highway binary rip=0x{x} op={s} size={s} lhs=0x{x} rhs=0x{x} input_flags=0x{x} output_flags=0x{x} writeback={}", .{
                self.regs.rip,
                @tagName(op),
                @tagName(width),
                lhs,
                rhs,
                self.regs.rflags,
                evaluated.rflags,
                evaluated.writeback,
            });
        }
        self.regs.rflags = evaluated.rflags;
        if (evaluated.writeback) self.setDecodedReg(d.dst_reg, d.dst_high8, d.size, evaluated.value);
    }

    fn terminateForMemoryAccess(self: *ElfState, d: DecodedInsn, check: x64_decoder.highway.MemoryCheck) void {
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 127;
        self.termination_reason = .memory_access_violation;
        log.err(
            "PE64 memory access violation: rip=0x{x} op={s} address=0x{x} bytes={d} access={s} fault={s} guest_range=[0x{x},0x{x}) regs(rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x} rsp=0x{x})",
            .{
                self.regs.rip,
                @tagName(d.op),
                check.address,
                check.bytes,
                @tagName(check.access),
                if (check.fault) |fault| @tagName(fault) else "none",
                self.mem_base,
                self.mem_base +| self.mem.len,
                self.regs.rax,
                self.regs.rbx,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.rsp,
            },
        );
    }

    fn validateGuestMemoryRange(
        self: *const ElfState,
        address: u64,
        width: x64_decoder.highway.Width,
        access: x64_decoder.highway.MemoryAccess,
        permitted: bool,
    ) x64_decoder.highway.MemoryCheck {
        const bytes: u8 = width.bits() / 8;
        if (self.windowsGuestRangeContains(address, bytes)) {
            return .{
                .address = address,
                .bytes = bytes,
                .access = access,
                .fault = if (permitted) null else .permission_denied,
            };
        }
        return x64_decoder.highway.validateRange(self.mem_base, self.mem.len, address, width, access, permitted);
    }

    fn executeHighwayMemoryBinary(
        self: *ElfState,
        d: DecodedInsn,
        op: x64_decoder.highway.BinaryOp,
        direction: x64_decoder.highway.MemoryDirection,
    ) void {
        const width: x64_decoder.highway.Width = switch (d.size) {
            .bits8 => .bits8,
            .bits16 => .bits16,
            .bits32 => .bits32,
            .bits64 => .bits64,
        };
        const access: x64_decoder.highway.MemoryAccess = if (direction == .register_to_memory and op != .cmp and op != .test_bits) .write else .read;
        const check = self.validateGuestMemoryRange(d.addr, width, access, true);
        if (!check.allowed()) {
            self.terminateForMemoryAccess(d, check);
            return;
        }
        const reg = if (direction == .memory_to_register) d.dst_reg else d.src_reg;
        const high8 = if (direction == .memory_to_register) d.dst_high8 else d.src_high8;
        const evaluated = x64_decoder.highway.evaluateMemory(op, width, self.decodedRegVal(reg, high8, d.size), self.readMemVal(d.addr, d.size), direction, self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.write_register) self.setDecodedReg(reg, high8, d.size, evaluated.value);
        if (evaluated.write_memory) self.writeMemVal(d.addr, d.size, evaluated.value);
    }

    fn executeHighwayImmediate(self: *ElfState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, memory: bool, immediate: u64) void {
        const width: x64_decoder.highway.Width = switch (d.size) {
            .bits8 => .bits8,
            .bits16 => .bits16,
            .bits32 => .bits32,
            .bits64 => .bits64,
        };
        if (memory) {
            const access: x64_decoder.highway.MemoryAccess = if (op == .cmp or op == .test_bits) .read else .write;
            const check = self.validateGuestMemoryRange(d.addr, width, access, true);
            if (!check.allowed()) {
                self.terminateForMemoryAccess(d, check);
                return;
            }
        }
        const lhs = if (memory) self.readMemVal(d.addr, d.size) else self.decodedRegVal(d.dst_reg, d.dst_high8, d.size);
        const evaluated = x64_decoder.highway.evaluate(op, width, lhs, immediate, self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.writeback) {
            if (memory) self.writeMemVal(d.addr, d.size, evaluated.value) else self.setDecodedReg(d.dst_reg, d.dst_high8, d.size, evaluated.value);
        }
    }

    fn executeAccumulatorImmediate(self: *ElfState, d: DecodedInsn) void {
        const op: x64_decoder.highway.BinaryOp = switch (d.op) {
            .add_accum_imm => .add,
            .or_accum_imm => .bit_or,
            .adc_accum_imm => .adc,
            .sbb_accum_imm => .sbb,
            .and_accum_imm => .bit_and,
            .sub_accum_imm => .sub,
            .xor_accum_imm => .bit_xor,
            .cmp_accum_imm => .cmp,
            else => unreachable,
        };
        self.executeHighwayImmediate(d, op, false, testImmForSize(d.imm, d.size));
    }

    fn isAccumulatorImmediate(op: Op) bool {
        return switch (op) {
            .add_accum_imm,
            .or_accum_imm,
            .adc_accum_imm,
            .sbb_accum_imm,
            .and_accum_imm,
            .sub_accum_imm,
            .xor_accum_imm,
            .cmp_accum_imm,
            => true,
            else => false,
        };
    }

    fn setFlag(self: *ElfState, flag: u32, enabled: bool) void {
        if (enabled) {
            self.regs.rflags |= flag;
        } else {
            self.regs.rflags &= ~flag;
        }
    }

    fn executeBitTestRegister(
        self: *ElfState,
        d: DecodedInsn,
        operation: x64_decoder.BitTestOperation,
        immediate_index: bool,
    ) void {
        const value = self.regVal(d.dst_reg, d.size);
        const raw_index = if (immediate_index) d.imm else self.regVal(d.src_reg, d.size);
        const result = x64_decoder.bitTestRegister(d.size, value, raw_index, operation);
        self.setFlag(RFL_CF, result.carry);
        if (operation != .probe) self.setReg(d.dst_reg, d.size, result.value);
    }

    fn executeBitTestMemory(
        self: *ElfState,
        d: DecodedInsn,
        operation: x64_decoder.BitTestOperation,
        immediate_index: bool,
    ) void {
        const operand = if (immediate_index)
            x64_decoder.bitTestMemoryOperandImmediate(d.size, d.addr, d.imm)
        else
            x64_decoder.bitTestMemoryOperand(d.size, d.addr, self.regVal(d.src_reg, d.size));
        const resolved = operand orelse {
            self.faulted = true;
            self.terminated = true;
            self.exit_code = 127;
            self.termination_reason = .memory_access_violation;
            log.err("PE64 bit-test memory operand overflow: rip=0x{x} op={s} address=0x{x} size={s} index=0x{x}", .{
                self.regs.rip,
                @tagName(d.op),
                d.addr,
                @tagName(d.size),
                if (immediate_index) d.imm else self.regVal(d.src_reg, d.size),
            });
            return;
        };
        const value = self.readMemVal(resolved.address, d.size);
        const result = x64_decoder.bitTestRegister(d.size, value, resolved.bit_index, operation);
        self.setFlag(RFL_CF, result.carry);
        if (operation != .probe) self.writeMemVal(resolved.address, d.size, result.value);
    }

    fn bitWidth(size: Size) u7 {
        return switch (size) {
            .bits8 => 8,
            .bits16 => 16,
            .bits32 => 32,
            .bits64 => 64,
        };
    }

    fn maskForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0xFF,
            .bits16 => 0xFFFF,
            .bits32 => 0xFFFF_FFFF,
            .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
        };
    }

    fn signBitForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0x80,
            .bits16 => 0x8000,
            .bits32 => 0x8000_0000,
            .bits64 => 0x8000_0000_0000_0000,
        };
    }

    fn signedInteger(value: u64, size: Size) i128 {
        return switch (size) {
            .bits8 => @as(i128, @as(i8, @bitCast(@as(u8, @truncate(value))))),
            .bits16 => @as(i128, @as(i16, @bitCast(@as(u16, @truncate(value))))),
            .bits32 => @as(i128, @as(i32, @bitCast(@as(u32, @truncate(value))))),
            .bits64 => @as(i128, @as(i64, @bitCast(value))),
        };
    }

    fn imulImmediateSize(op: Op) Size {
        return switch (op) {
            .imul_reg16_mem16_imm8,
            .imul_reg16_reg16_imm8,
            .imul_reg16_mem16_imm16,
            .imul_reg16_reg16_imm16,
            => .bits16,
            .imul_reg32_mem32_imm8,
            .imul_reg32_reg32_imm8,
            .imul_reg32_mem32_imm32,
            .imul_reg32_reg32_imm32,
            => .bits32,
            .imul_reg64_mem64_imm8,
            .imul_reg64_reg64_imm8,
            .imul_reg64_mem64_imm32,
            .imul_reg64_reg64_imm32,
            => .bits64,
            else => unreachable,
        };
    }

    fn signedImulImmediate(instruction: DecodedInsn) i128 {
        return switch (instruction.op) {
            .imul_reg16_mem16_imm8,
            .imul_reg16_reg16_imm8,
            .imul_reg32_mem32_imm8,
            .imul_reg32_reg32_imm8,
            .imul_reg64_mem64_imm8,
            .imul_reg64_reg64_imm8,
            => @as(i128, @as(i8, @bitCast(@as(u8, @truncate(instruction.imm))))),
            .imul_reg16_mem16_imm16,
            .imul_reg16_reg16_imm16,
            => @as(i128, @as(i16, @bitCast(@as(u16, @truncate(instruction.imm))))),
            .imul_reg32_mem32_imm32,
            .imul_reg32_reg32_imm32,
            .imul_reg64_mem64_imm32,
            .imul_reg64_reg64_imm32,
            => @as(i128, @as(i32, @bitCast(@as(u32, @truncate(instruction.imm))))),
            else => unreachable,
        };
    }

    fn writeImulNarrowResult(self: *ElfState, destination: RegId, size: Size, product: i128) void {
        const product_bits: u128 = @bitCast(product);
        const result: u64 = @truncate(product_bits);
        self.setReg(destination, size, result);

        // Two- and three-operand IMUL retain only the destination width. CF
        // and OF report whether the full signed product cannot be represented
        // by that width; the remaining arithmetic flags are unaffected.
        const overflow = product != signedInteger(result, size);
        self.setFlag(RFL_CF, overflow);
        self.setFlag(RFL_OF, overflow);
    }

    fn shlCount(self: *ElfState, size: Size) u6 {
        const mask: u64 = if (size == .bits64) 0x3F else 0x1F;
        return @as(u6, @intCast(self.regVal(.cl_cx_ecx_rcx, .bits8) & mask));
    }

    fn shlValue(self: *ElfState, input: u64, size: Size, count: u6) u64 {
        _ = self;
        const mask = maskForSize(size);
        const result = (input & mask) << count;
        return result & mask;
    }

    fn setFlagsShl(self: *ElfState, input: u64, result: u64, size: Size, count: u6) void {
        if (count == 0) return;

        const width = bitWidth(size);
        const mask = maskForSize(size);
        const masked_input = input & mask;
        const masked_result = result & mask;

        if (count <= width) {
            const shift: u6 = @intCast(width - count);
            self.setFlag(RFL_CF, ((masked_input >> shift) & 1) != 0);
        } else {
            self.setFlag(RFL_CF, false);
        }

        if (count == 1) {
            const sign = signBitForSize(size);
            const msb_set = (masked_result & sign) != 0;
            const cf_set = (self.regs.rflags & RFL_CF) != 0;
            self.setFlag(RFL_OF, msb_set != cf_set);
        }

        self.setFlag(RFL_SF, (masked_result & signBitForSize(size)) != 0);
        self.setFlag(RFL_ZF, masked_result == 0);
    }

    fn immShiftCount(imm: u64, size: Size) u6 {
        const mask: u64 = if (size == .bits64) 0x3F else 0x1F;
        return @as(u6, @intCast(imm & mask));
    }

    fn executeRotate(self: *ElfState, d: DecodedInsn) void {
        const is_mem = switch (d.op) {
            .rol_mem_cl, .ror_mem_cl, .rol_mem_imm, .ror_mem_imm => true,
            else => false,
        };
        const rotate_left = switch (d.op) {
            .rol_reg_cl, .rol_mem_cl, .rol_reg_imm, .rol_mem_imm => true,
            else => false,
        };
        const uses_cl = switch (d.op) {
            .rol_reg_cl, .rol_mem_cl, .ror_reg_cl, .ror_mem_cl => true,
            else => false,
        };
        const raw_count = if (uses_cl) self.regVal(.cl_cx_ecx_rcx, .bits8) else d.imm;
        const width: u64 = bitWidth(d.size);
        const count: u6 = @intCast((raw_count & @as(u64, if (d.size == .bits64) 0x3F else 0x1F)) % width);
        if (count == 0) return;
        const mask = maskForSize(d.size);
        const old = (if (is_mem) self.readMemVal(d.addr, d.size) else self.regVal(d.dst_reg, d.size)) & mask;
        const inverse: u6 = @intCast(width - count);
        const result = if (rotate_left) ((old << count) | (old >> inverse)) & mask else ((old >> count) | (old << inverse)) & mask;
        if (is_mem) self.writeMemVal(d.addr, d.size, result) else self.setReg(d.dst_reg, d.size, result);
        if (rotate_left) {
            const carry = (result & 1) != 0;
            self.setFlag(RFL_CF, carry);
            if (count == 1) self.setFlag(RFL_OF, ((result & signBitForSize(d.size)) != 0) != carry);
        } else {
            const carry = (result & signBitForSize(d.size)) != 0;
            self.setFlag(RFL_CF, carry);
            if (count == 1) self.setFlag(RFL_OF, carry != ((result & (signBitForSize(d.size) >> 1)) != 0));
        }
    }

    fn shrValue(self: *ElfState, input: u64, size: Size, count: u6) u64 {
        _ = self;
        const mask = maskForSize(size);
        return (input & mask) >> count;
    }

    fn setFlagsShr(self: *ElfState, input: u64, result: u64, size: Size, count: u6) void {
        if (count == 0) return;

        const masked_input = input & maskForSize(size);
        const masked_result = result & maskForSize(size);
        const shifted_out: u6 = @intCast(count - 1);
        self.setFlag(RFL_CF, ((masked_input >> shifted_out) & 1) != 0);

        if (count == 1) {
            self.setFlag(RFL_OF, (masked_input & signBitForSize(size)) != 0);
        }

        self.setFlag(RFL_SF, (masked_result & signBitForSize(size)) != 0);
        self.setFlag(RFL_ZF, masked_result == 0);
    }

    fn sarValue(self: *ElfState, input: u64, size: Size, count: u6) u64 {
        _ = self;
        if (count == 0) return input & maskForSize(size);
        const sign_set = (input & signBitForSize(size)) != 0;
        if (count >= bitWidth(size)) return if (sign_set) maskForSize(size) else 0;
        return switch (size) {
            .bits8 => @as(u64, @as(u8, @bitCast(@as(i8, @bitCast(@as(u8, @truncate(input)))) >> @as(u3, @intCast(count))))),
            .bits16 => @as(u64, @as(u16, @bitCast(@as(i16, @bitCast(@as(u16, @truncate(input)))) >> @as(u4, @intCast(count))))),
            .bits32 => @as(u64, @as(u32, @bitCast(@as(i32, @bitCast(@as(u32, @truncate(input)))) >> @as(u5, @intCast(count))))),
            .bits64 => @as(u64, @bitCast(@as(i64, @bitCast(input)) >> count)),
        };
    }

    fn setFlagsSar(self: *ElfState, input: u64, result: u64, size: Size, count: u6) void {
        if (count == 0) return;

        const masked_input = input & maskForSize(size);
        const masked_result = result & maskForSize(size);
        if (count <= bitWidth(size)) {
            const shifted_out: u6 = @intCast(count - 1);
            self.setFlag(RFL_CF, ((masked_input >> shifted_out) & 1) != 0);
        }

        if (count == 1) self.setFlag(RFL_OF, false);

        self.setFlag(RFL_SF, (masked_result & signBitForSize(size)) != 0);
        self.setFlag(RFL_ZF, masked_result == 0);
    }

    fn evalCond(rflags: u32, cond: Cond) bool {
        return x64_decoder.evalCond(rflags, cond);
    }

    fn executeBitScan(self: *ElfState, d: DecodedInsn) void {
        const is_memory = switch (d.op) {
            .bsf_reg_mem, .bsr_reg_mem, .tzcnt_reg_mem, .lzcnt_reg_mem => true,
            else => false,
        };
        const kind: BitScanKind = switch (d.op) {
            .bsf_reg_reg, .bsf_reg_mem => .bsf,
            .bsr_reg_reg, .bsr_reg_mem => .bsr,
            .tzcnt_reg_reg, .tzcnt_reg_mem => .tzcnt,
            .lzcnt_reg_reg, .lzcnt_reg_mem => .lzcnt,
            else => unreachable,
        };
        const source = if (is_memory) self.readMemVal(d.addr, d.size) else self.regVal(d.src_reg, d.size);
        const result = x64_decoder.bitScan(d.size, kind, source);

        if (result.write_destination) self.setReg(d.dst_reg, d.size, result.value);
        self.setFlag(RFL_ZF, result.zero_flag);
        if (result.carry_flag) |carry| self.setFlag(RFL_CF, carry);
    }

    fn stringAddress(self: *const ElfState, index: RegId, address_size: Size, segment: x64_decoder.Segment) u64 {
        return x64_decoder.resolveMemoryAddress(&self.regs, .{
            .has_base = true,
            .base_reg = index,
            .segment = segment,
        }, 0, address_size, .long64, true);
    }

    fn executeStringOperation(self: *ElfState, d: DecodedInsn) void {
        const address_size: Size = if (d.has_0x67) .bits32 else .bits64;
        const stride: u64 = switch (d.size) {
            .bits8 => 1,
            .bits16 => 2,
            .bits32 => 4,
            .bits64 => 8,
        };
        const backwards = (self.regs.rflags & RFL_DF) != 0;
        const repeated = d.repeat != .none;
        var remaining: u64 = if (repeated)
            self.regVal(.cl_cx_ecx_rcx, address_size)
        else
            1;

        if (remaining == 0) return;

        while (remaining != 0) {
            switch (d.op) {
                .movs => {
                    const source_address = self.stringAddress(.dh_si_esi_rsi, address_size, d.segment);
                    const destination_address = self.stringAddress(.bh_di_edi_rdi, address_size, .es);
                    const value = self.readMemVal(source_address, d.size);
                    self.writeMemVal(destination_address, d.size, value);
                    const next_source = if (backwards)
                        self.regVal(.dh_si_esi_rsi, address_size) -% stride
                    else
                        self.regVal(.dh_si_esi_rsi, address_size) +% stride;
                    const next_destination = if (backwards)
                        self.regVal(.bh_di_edi_rdi, address_size) -% stride
                    else
                        self.regVal(.bh_di_edi_rdi, address_size) +% stride;
                    self.setReg(.dh_si_esi_rsi, address_size, next_source);
                    self.setReg(.bh_di_edi_rdi, address_size, next_destination);
                },
                .cmps => {
                    const source_address = self.stringAddress(.dh_si_esi_rsi, address_size, d.segment);
                    const destination_address = self.stringAddress(.bh_di_edi_rdi, address_size, .es);
                    const source = self.readMemVal(source_address, d.size);
                    const destination = self.readMemVal(destination_address, d.size);
                    const result = source -% destination;
                    self.setFlagsSub(source, destination, result, d.size);
                    const next_source = if (backwards)
                        self.regVal(.dh_si_esi_rsi, address_size) -% stride
                    else
                        self.regVal(.dh_si_esi_rsi, address_size) +% stride;
                    const next_destination = if (backwards)
                        self.regVal(.bh_di_edi_rdi, address_size) -% stride
                    else
                        self.regVal(.bh_di_edi_rdi, address_size) +% stride;
                    self.setReg(.dh_si_esi_rsi, address_size, next_source);
                    self.setReg(.bh_di_edi_rdi, address_size, next_destination);
                },
                .stos => {
                    const destination_address = self.stringAddress(.bh_di_edi_rdi, address_size, .es);
                    self.writeMemVal(destination_address, d.size, self.regVal(.al_ax_eax_rax, d.size));
                    const next_destination = if (backwards)
                        self.regVal(.bh_di_edi_rdi, address_size) -% stride
                    else
                        self.regVal(.bh_di_edi_rdi, address_size) +% stride;
                    self.setReg(.bh_di_edi_rdi, address_size, next_destination);
                },
                .lods => {
                    const source_address = self.stringAddress(.dh_si_esi_rsi, address_size, d.segment);
                    self.setReg(.al_ax_eax_rax, d.size, self.readMemVal(source_address, d.size));
                    const next_source = if (backwards)
                        self.regVal(.dh_si_esi_rsi, address_size) -% stride
                    else
                        self.regVal(.dh_si_esi_rsi, address_size) +% stride;
                    self.setReg(.dh_si_esi_rsi, address_size, next_source);
                },
                .scas => {
                    const destination_address = self.stringAddress(.bh_di_edi_rdi, address_size, .es);
                    const accumulator = self.regVal(.al_ax_eax_rax, d.size);
                    const destination = self.readMemVal(destination_address, d.size);
                    const result = accumulator -% destination;
                    self.setFlagsSub(accumulator, destination, result, d.size);
                    const next_destination = if (backwards)
                        self.regVal(.bh_di_edi_rdi, address_size) -% stride
                    else
                        self.regVal(.bh_di_edi_rdi, address_size) +% stride;
                    self.setReg(.bh_di_edi_rdi, address_size, next_destination);
                },
                else => unreachable,
            }

            if (!repeated) break;
            remaining -%= 1;
            self.setReg(.cl_cx_ecx_rcx, address_size, remaining);
            if ((d.op == .cmps or d.op == .scas) and remaining != 0) {
                const equal = (self.regs.rflags & RFL_ZF) != 0;
                const continue_repeating = switch (d.repeat) {
                    .rep => equal,
                    .repne => !equal,
                    .none => false,
                };
                if (!continue_repeating) break;
            }
        }
    }

    fn advanceAfterHandled(self: *ElfState, d: DecodedInsn) void {
        if (!self.terminated) self.regs.rip += d.len;
    }

    pub fn execute(self: *ElfState, d: DecodedInsn) void {
        if (d.is_evex or d.op == .movdir64b or evex.handles(d.op)) {
            evex.execute(self, d);
            self.advanceAfterHandled(d);
            return;
        }

        // Keep vector moves and VEX.128 upper-lane clearing outside the
        // arithmetic router. These operations have architectural state
        // effects that a generic CLEO arithmetic call cannot express.
        if (self.executeCleoVectorMove(d)) {
            self.advanceAfterHandled(d);
            return;
        }
        if (d.op == .vzeroupper) {
            for (&self.ymm_hi) |*upper| @memset(upper, 0);
            self.advanceAfterHandled(d);
            return;
        }
        if (self.executeSharedVex(d)) {
            self.advanceAfterHandled(d);
            return;
        }
        if (self.executeVectorSpecial(d)) {
            self.advanceAfterHandled(d);
            return;
        }
        if (self.tryExecuteCleo(d)) {
            self.advanceAfterHandled(d);
            return;
        }
        if (isVectorOperationRuntime(d.op) and !isLegacyVectorTransfer(d.op)) {
            self.terminateUnimplemented(d);
            return;
        }

        // Accumulator-immediate forms are scalar Group-1 operations. Handle
        // them before the broad legacy fallback, whose compatibility list also
        // contains these Op tags for older vector dispatch coverage.
        if (isAccumulatorImmediate(d.op)) {
            self.executeAccumulatorImmediate(d);
            self.advanceAfterHandled(d);
            return;
        }

        switch (d.op) {
            .invalid => self.terminateUnimplemented(d),
            .nop => {},
            .cmc => self.regs.rflags ^= RFL_CF,
            .clc => self.regs.rflags &= ~RFL_CF,
            .stc => self.regs.rflags |= RFL_CF,
            // Direction flag. The string operations read it for their stride,
            // so without these the guest was subject to a flag it could not set.
            .cld => self.regs.rflags &= ~RFL_DF,
            .std => self.regs.rflags |= RFL_DF,
            .xchg_accum_reg => {
                const sz = d.size;
                const left = self.regVal(.al_ax_eax_rax, sz);
                const right = self.regVal(d.src_reg, sz);
                self.setReg(.al_ax_eax_rax, sz, right);
                self.setReg(d.src_reg, sz, left);
            },
            .loopne, .loope, .loop, .jrcxz => {
                const counter_size: Size = if (d.has_0x67) .bits32 else .bits64;
                var taken = false;
                if (d.op == .jrcxz) {
                    taken = self.regVal(.cl_cx_ecx_rcx, counter_size) == 0;
                } else {
                    const next = self.regVal(.cl_cx_ecx_rcx, counter_size) -% 1;
                    self.setReg(.cl_cx_ecx_rcx, counter_size, next);
                    const zero = (self.regs.rflags & RFL_ZF) != 0;
                    taken = next != 0 and switch (d.op) {
                        .loope => zero,
                        .loopne => !zero,
                        else => true,
                    };
                }
                if (taken) {
                    self.regs.rip = self.regs.rip +% d.len +% d.imm;
                } else {
                    self.regs.rip +%= d.len;
                }
                return;
            },
            .xlat => {
                const table = self.regVal(.bl_bx_ebx_rbx, .bits64);
                const index = self.regVal(.al_ax_eax_rax, .bits8) & 0xFF;
                const value = self.readMemVal(table +% index, .bits8);
                self.setReg(.al_ax_eax_rax, .bits8, value & 0xFF);
            },
            .lahf => {
                const ah = @as(u64, x64_decoder.statusByteForLahf(self.regs.rflags));
                self.regs.rax = (self.regs.rax & 0xFFFF_FFFF_FFFF_00FF) | (ah << 8);
            },
            .sahf => x64_decoder.applySahf(&self.regs.rflags, @truncate(self.regs.rax >> 8)),

            // The D8-DF x87 arithmetic family (fadd/fmul/fsub/fsubr/fdiv/fdivr
            // with m32/m64, plus the fi* integer forms) is decoded by the shared
            // decoder into a single .x87_binary op with the operation packed in
            // x87.imm; the per-size members below are the only x87 ops the
            // shared Op enum exposes.
            .fild_mem16 => {
                const value = @as(i16, @bitCast(@as(u16, @truncate(self.readMemVal(d.addr, .bits16)))));
                _ = self.x87PushRaw(x87RawFromInt(value));
            },
            .fild_mem32 => {
                const value = @as(i32, @bitCast(@as(u32, @truncate(self.readMemVal(d.addr, .bits32)))));
                _ = self.x87PushRaw(x87RawFromInt(value));
            },
            .fild_mem64 => {
                const value = @as(i64, @bitCast(self.readMemVal(d.addr, .bits64)));
                _ = self.x87PushRaw(x87RawFromInt(value));
            },
            .fld_mem32 => {
                const value: f32 = @bitCast(@as(u32, @truncate(self.readMemVal(d.addr, .bits32))));
                _ = self.x87PushRaw(x87RawFromFloat(@floatCast(value)));
            },
            .fld_mem64 => {
                _ = self.x87PushRaw(x87RawFromFloat(@bitCast(self.readMemVal(d.addr, .bits64))));
            },
            .fld_mem80 => {
                const input = self.guestMemoryConst(d.addr, 10) orelse {
                    return;
                };
                var raw: X87Raw = undefined;
                @memcpy(raw[0..], input[0..10]);
                _ = self.x87PushRaw(raw);
            },
            .fstp_mem80 => {
                const output = self.guestMemory(d.addr, 10) orelse return;
                if (self.x87PopRaw()) |raw| {
                    self.traceGuestWrite(d.addr, 10, std.mem.readInt(u64, raw[0..8], .little));
                    @memcpy(output[0..10], raw[0..]);
                } else {
                    @memset(output[0..10], 0);
                }
            },
            .fstp_mem32 => {
                if (self.x87PopRaw()) |raw| {
                    const value = readExtendedFloat80(&raw);
                    self.writeMemVal(d.addr, .bits32, @as(u64, @as(u32, @bitCast(@as(f32, @floatCast(value))))));
                }
            },
            .fstp_mem64 => {
                if (self.x87PopRaw()) |raw| {
                    self.writeMemVal(d.addr, .bits64, @as(u64, @bitCast(readExtendedFloat80(&raw))));
                }
            },
            .fisttp_mem64 => {
                const output = self.guestMemory(d.addr, 8) orelse {
                    return;
                };
                const raw = self.x87GetRaw(0) orelse return;
                const value = readExtendedFloat80(&raw);
                const min_i64 = -0x1p63;
                const invalid = std.math.isNan(value) or
                    !std.math.isFinite(value) or
                    value < min_i64 or
                    value >= 0x1p63;
                const integer = if (invalid)
                    std.math.minInt(i64)
                else
                    @as(i64, @intFromFloat(value));
                if (invalid) self.x87_status |= 1 << 0;
                _ = self.x87PopRaw();
                std.mem.writeInt(u64, output[0..8], @bitCast(integer), .little);
            },
            .fld_st => {
                if (self.x87GetRaw(@truncate(d.imm))) |raw| _ = self.x87PushRaw(raw);
            },
            .fstp_st => {
                if (self.x87GetRaw(0)) |raw| {
                    if (self.x87SetRaw(@truncate(d.imm), raw)) _ = self.x87PopRaw();
                }
            },
            .fxch_st => self.x87Exchange(@truncate(d.imm)),
            .ffree_st => self.x87Free(@truncate(d.imm)),
            .fninit => self.x87Reset(),
            .fchs => self.x87Fchs(),
            .fabs => self.x87Fabs(),
            .ftst => self.x87Test(),
            .fxam => {},
            .f2xm1 => self.x87F2xm1(),
            .fyl2x => self.x87Fyl2x(false),
            .fptan => self.x87Fptan(),
            .fpatan => self.x87Fpatan(),
            .fxtract => self.x87Fxtract(),
            .fdecstp => self.x87_top -%= 1,
            .fincstp => self.x87_top +%= 1,
            .fsin => self.x87Sin(),
            .fcos => self.x87Cos(),
            .fprem1 => self.x87PartialRemainderNearest(),
            .fprem => self.x87PartialRemainderTrunc(),
            .fyl2xp1 => self.x87Fyl2x(true),
            .fsqrt => {
                const raw = self.x87GetRaw(0) orelse return;
                _ = self.x87SetRaw(0, x87RawFromFloat(@sqrt(readExtendedFloat80(&raw))));
            },
            .fsincos => self.x87Fsincos(),
            .frndint => self.x87Frndint(),
            .fscale => self.x87Fscale(),
            .fnop => {},
            .fclex => self.x87Fclex(),
            .fnstsw_ax => self.setReg(.al_ax_eax_rax, .bits16, self.x87StatusWord()),
            .fnstcw_mem16 => self.writeMemVal(d.addr, .bits16, self.x87_control),
            .fldcw_mem16 => self.x87_control = @truncate(self.readMemVal(d.addr, .bits16)),
            .x87_binary => self.x87Binary(d),
            .fldz => _ = self.x87PushRaw(x87RawFromFloat(0.0)),
            .fld1 => _ = self.x87PushRaw(x87RawFromFloat(1.0)),
            .fldl2t => _ = self.x87PushRaw(x87RawFromFloat(3.32192809488736234787)),
            .fldl2e => _ = self.x87PushRaw(x87RawFromFloat(1.44269504088896340736)),
            .fldpi => _ = self.x87PushRaw(x87RawFromFloat(3.14159265358979323846)),
            .fldlg2 => _ = self.x87PushRaw(x87RawFromFloat(0.30102999566398119521)),
            .fldln2 => _ = self.x87PushRaw(x87RawFromFloat(0.69314718055994530942)),
            .x87_memory => self.x87Memory(d),
            .fucomi_st => self.x87Compare(@truncate(d.imm), false),
            .fcomi_st => self.x87Compare(@truncate(d.imm), false),
            .fucomip_st => self.x87Compare(@truncate(d.imm), true),
            .fcomip_st => self.x87Compare(@truncate(d.imm), true),
            .fcmovb_st,
            .fcmove_st,
            .fcmovbe_st,
            .fcmovu_st,
            .fcmovnb_st,
            .fcmovne_st,
            .fcmovnbe_st,
            .fcmovnu_st,
            => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    if (self.x87GetRaw(@truncate(d.imm))) |raw| _ = self.x87SetRaw(0, raw);
                }
            },

            // ── mov reg, mem ──
            .mov_reg8_mem8 => {
                const val = self.readMemVal(d.addr, .bits8);
                self.setDecodedReg(d.dst_reg, d.dst_high8, .bits8, val);
            },
            .mov_reg16_mem16 => {
                const val = self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, .bits16, val);
            },
            .mov_reg32_mem32 => {
                const val = self.readMemVal(d.addr, .bits32);
                self.setReg(d.dst_reg, .bits32, val);
            },
            .mov_reg64_mem64 => {
                const val = self.readMemVal(d.addr, .bits64);
                self.setReg(d.dst_reg, .bits64, val);
            },

            // ── mov mem, reg ──
            .mov_mem8_reg8 => {
                const val = self.decodedRegVal(d.src_reg, d.src_high8, .bits8);
                self.writeMemVal(d.addr, .bits8, val);
            },
            .mov_mem16_reg16 => {
                const val = self.regVal(d.src_reg, .bits16);
                self.writeMemVal(d.addr, .bits16, val);
            },
            .mov_mem32_reg32 => {
                const val = self.regVal(d.src_reg, .bits32);
                self.writeMemVal(d.addr, .bits32, val);
            },
            .mov_mem64_reg64 => {
                const val = self.regVal(d.src_reg, .bits64);
                self.writeMemVal(d.addr, .bits64, val);
            },

            // ── mov reg, imm ──
            .mov_reg_imm => {
                self.setDecodedReg(d.dst_reg, d.dst_high8, d.size, d.imm);
            },

            .movs, .cmps, .stos, .lods, .scas => self.executeStringOperation(d),

            // ── mov mem, imm ──
            .mov_mem8_imm8 => {
                self.writeMemVal(d.addr, .bits8, d.imm);
            },
            .mov_mem16_imm16 => {
                self.writeMemVal(d.addr, .bits16, d.imm);
            },
            .mov_mem32_imm32 => {
                self.writeMemVal(d.addr, .bits32, d.imm);
            },
            .mov_mem64_imm32 => {
                self.writeMemVal(d.addr, .bits64, d.imm);
            },

            // ── mov reg64, reg64 ──
            .mov_reg8_reg8 => {
                const val = self.decodedRegVal(d.src_reg, d.src_high8, .bits8);
                self.setDecodedReg(d.dst_reg, d.dst_high8, .bits8, val);
            },
            .mov_reg16_reg16 => {
                const val = self.regVal(d.src_reg, .bits16);
                self.setReg(d.dst_reg, .bits16, val);
            },
            .mov_reg32_reg32 => {
                const val = self.regVal(d.src_reg, .bits32);
                self.setReg(d.dst_reg, .bits32, val);
            },
            .mov_reg64_reg64 => {
                const val = self.regVal(d.src_reg, .bits64);
                self.setReg(d.dst_reg, .bits64, val);
            },

            // ── add reg, mem (d=1) ──
            .add_reg8_mem8, .add_reg16_mem16, .add_reg32_mem32, .add_reg64_mem64 => self.executeHighwayMemoryBinary(d, .add, .memory_to_register),

            // ── add r/m, reg (d=0) ──
            .add_mem8_reg8, .add_mem16_reg16, .add_mem32_reg32, .add_mem64_reg64 => self.executeHighwayMemoryBinary(d, .add, .register_to_memory),

            // ── add reg, reg ──
            .add_reg8_reg8, .add_reg16_reg16, .add_reg32_reg32, .add_reg64_reg64 => self.executeHighwayRegisterBinary(d, .add),
            .add_reg8_imm8, .add_reg16_imm8, .add_reg32_imm8, .add_reg64_imm8 => {
                const imm = if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm);
                self.executeHighwayImmediate(d, .add, false, imm);
            },
            .adc_reg8_imm8, .adc_reg16_imm8, .adc_reg32_imm8, .adc_reg64_imm8 => self.executeHighwayImmediate(d, .adc, false, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .adc_reg8_mem8, .adc_reg16_mem16, .adc_reg32_mem32, .adc_reg64_mem64 => self.executeHighwayMemoryBinary(d, .adc, .memory_to_register),
            .adc_mem8_reg8, .adc_mem16_reg16, .adc_mem32_reg32, .adc_mem64_reg64 => self.executeHighwayMemoryBinary(d, .adc, .register_to_memory),
            .adc_reg8_reg8, .adc_reg16_reg16, .adc_reg32_reg32, .adc_reg64_reg64 => self.executeHighwayRegisterBinary(d, .adc),
            .sbb_reg8_mem8 => self.executeHighwayMemoryBinary(d, .sbb, .memory_to_register),
            .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32 => {
                const imm = testImmForSize(d.imm, d.size);
                self.executeHighwayImmediate(d, .add, false, imm);
            },
            .or_reg16_imm32, .or_reg32_imm32, .or_reg64_imm32 => self.executeHighwayImmediate(d, .bit_or, false, testImmForSize(d.imm, d.size)),
            .adc_reg16_imm32, .adc_reg32_imm32, .adc_reg64_imm32 => self.executeHighwayImmediate(d, .adc, false, testImmForSize(d.imm, d.size)),
            .sbb_reg16_imm32, .sbb_reg32_imm32, .sbb_reg64_imm32 => self.executeHighwayImmediate(d, .sbb, false, testImmForSize(d.imm, d.size)),
            .xor_reg16_imm32, .xor_reg32_imm32, .xor_reg64_imm32 => self.executeHighwayImmediate(d, .bit_xor, false, testImmForSize(d.imm, d.size)),
            .add_mem8_imm8, .add_mem16_imm8, .add_mem32_imm8, .add_mem64_imm8 => self.executeHighwayImmediate(d, .add, true, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),

            // ── sub reg, mem ──
            .sub_reg8_mem8, .sub_reg16_mem16, .sub_reg32_mem32, .sub_reg64_mem64 => self.executeHighwayMemoryBinary(d, .sub, .memory_to_register),
            .sub_mem8_reg8, .sub_mem16_reg16, .sub_mem32_reg32, .sub_mem64_reg64 => self.executeHighwayMemoryBinary(d, .sub, .register_to_memory),

            // ── sub reg, reg ──
            .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64 => self.executeHighwayRegisterBinary(d, .sub),
            .sbb_reg8_reg8, .sbb_reg16_reg16, .sbb_reg32_reg32, .sbb_reg64_reg64 => self.executeHighwayRegisterBinary(d, .sbb),

            // ── sub r/m8, imm8 (0x80 /5) ──
            .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8 => self.executeHighwayImmediate(d, .sub, false, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .sbb_reg8_imm8 => self.executeHighwayImmediate(d, .sbb, false, d.imm & 0xFF),
            .sbb_reg16_imm8, .sbb_reg32_imm8, .sbb_reg64_imm8 => self.executeHighwayImmediate(d, .sbb, false, signExtendImm8(d.imm)),
            .sub_mem8_imm8, .sub_mem16_imm8, .sub_mem32_imm8, .sub_mem64_imm8 => self.executeHighwayImmediate(d, .sub, true, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .sub_reg16_imm32, .sub_reg32_imm32, .sub_reg64_imm32 => self.executeHighwayImmediate(d, .sub, false, testImmForSize(d.imm, d.size)),

            // ── logical register/imm operations ──
            .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64 => {
                self.executeHighwayRegisterBinary(d, .bit_and);
            },
            .and_reg8_mem8, .and_reg16_mem16, .and_reg32_mem32, .and_reg64_mem64 => {
                self.executeHighwayMemoryBinary(d, .bit_and, .memory_to_register);
            },
            .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64 => {
                self.executeHighwayMemoryBinary(d, .bit_and, .register_to_memory);
            },
            .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8 => {
                const imm = if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm);
                self.executeHighwayImmediate(d, .bit_and, false, imm);
            },
            .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32 => self.executeHighwayImmediate(d, .bit_and, false, testImmForSize(d.imm, d.size)),
            .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64 => {
                self.executeHighwayRegisterBinary(d, .bit_or);
            },
            .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64 => {
                self.executeHighwayMemoryBinary(d, .bit_or, .memory_to_register);
            },
            .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64 => {
                self.executeHighwayMemoryBinary(d, .bit_or, .register_to_memory);
            },
            .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8 => self.executeHighwayImmediate(d, .bit_or, false, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .or_mem8_imm8, .or_mem16_imm8, .or_mem32_imm8, .or_mem64_imm8 => self.executeHighwayImmediate(d, .bit_or, true, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .or_mem16_imm32, .or_mem32_imm32, .or_mem64_imm32 => self.executeHighwayImmediate(d, .bit_or, true, testImmForSize(d.imm, d.size)),
            // The remainder of group 1's memory matrix. `or` was the only
            // operation with every cell; the rest ranged from four to none,
            // and `adc qword ptr [rax+8], 0` decoded as invalid.
            .add_mem16_imm32, .add_mem32_imm32, .add_mem64_imm32 => self.executeHighwayImmediate(d, .add, true, testImmForSize(d.imm, d.size)),
            .adc_mem8_imm8, .adc_mem16_imm8, .adc_mem32_imm8, .adc_mem64_imm8 => self.executeHighwayImmediate(d, .adc, true, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .adc_mem16_imm32, .adc_mem32_imm32, .adc_mem64_imm32 => self.executeHighwayImmediate(d, .adc, true, testImmForSize(d.imm, d.size)),
            .sbb_mem8_imm8, .sbb_mem16_imm8, .sbb_mem32_imm8, .sbb_mem64_imm8 => self.executeHighwayImmediate(d, .sbb, true, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .sbb_mem16_imm32, .sbb_mem32_imm32, .sbb_mem64_imm32 => self.executeHighwayImmediate(d, .sbb, true, testImmForSize(d.imm, d.size)),
            .and_mem8_imm8, .and_mem16_imm8, .and_mem32_imm8, .and_mem64_imm8 => self.executeHighwayImmediate(d, .bit_and, true, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .and_mem16_imm32, .and_mem32_imm32, .and_mem64_imm32 => self.executeHighwayImmediate(d, .bit_and, true, testImmForSize(d.imm, d.size)),
            .sub_mem16_imm32, .sub_mem32_imm32, .sub_mem64_imm32 => self.executeHighwayImmediate(d, .sub, true, testImmForSize(d.imm, d.size)),
            .xor_mem8_imm8, .xor_mem16_imm8, .xor_mem32_imm8, .xor_mem64_imm8 => self.executeHighwayImmediate(d, .bit_xor, true, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .xor_mem16_imm32, .xor_mem32_imm32, .xor_mem64_imm32 => self.executeHighwayImmediate(d, .bit_xor, true, testImmForSize(d.imm, d.size)),
            .cmp_mem16_imm32, .cmp_mem32_imm32, .cmp_mem64_imm32 => self.executeHighwayImmediate(d, .cmp, true, testImmForSize(d.imm, d.size)),
            .xor_reg8_mem8, .xor_reg16_mem16, .xor_reg32_mem32, .xor_reg64_mem64 => {
                self.executeHighwayMemoryBinary(d, .bit_xor, .memory_to_register);
            },
            .xor_mem8_reg8, .xor_mem16_reg16, .xor_mem32_reg32, .xor_mem64_reg64 => {
                self.executeHighwayMemoryBinary(d, .bit_xor, .register_to_memory);
            },
            .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64 => {
                self.executeHighwayRegisterBinary(d, .bit_xor);
            },
            .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8 => self.executeHighwayImmediate(d, .bit_xor, false, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .bsf_reg_reg,
            .bsf_reg_mem,
            .bsr_reg_reg,
            .bsr_reg_mem,
            .tzcnt_reg_reg,
            .tzcnt_reg_mem,
            .lzcnt_reg_reg,
            .lzcnt_reg_mem,
            => self.executeBitScan(d),
            .andn, .bzhi, .mulx, .rorx, .shlx, .shrx, .sarx => self.executeBmi(d),
            .popcnt_reg_reg, .popcnt_reg_mem => {
                const source = if (d.op == .popcnt_reg_mem)
                    self.readMemVal(d.addr, d.size)
                else
                    self.regVal(d.src_reg, d.size);
                const result = x64_decoder.populationCount(d.size, source, self.regs.rflags);
                self.setReg(d.dst_reg, d.size, result.value);
                self.regs.rflags = result.rflags;
            },
            .bswap_reg => self.setReg(d.dst_reg, d.size, x64_decoder.byteSwap(d.size, self.regVal(d.dst_reg, d.size))),
            .movbe_reg_mem => {
                const value = self.readMemVal(d.addr, d.size);
                self.setReg(d.dst_reg, d.size, x64_decoder.byteSwap(d.size, value));
            },
            .movbe_mem_reg => {
                const value = x64_decoder.byteSwap(d.size, self.regVal(d.src_reg, d.size));
                self.writeMemVal(d.addr, d.size, value);
            },
            .ldmxcsr_mem32 => {
                self.regs.mxcsr = @truncate(self.readMemVal(d.addr, .bits32));
            },
            .stmxcsr_mem32 => {
                self.writeMemVal(d.addr, .bits32, self.regs.mxcsr);
            },
            .crc32_reg_reg, .crc32_reg_mem => {
                const source = if (d.op == .crc32_reg_mem)
                    self.readMemVal(d.addr, d.size)
                else
                    self.regVal(d.src_reg, d.size);
                const crc = x64_decoder.crc32cAccumulator(@truncate(self.regVal(d.dst_reg, .bits32)), source, d.size);
                self.setReg(d.dst_reg, d.dst_size, crc);
            },
            .rol_reg_cl,
            .rol_mem_cl,
            .ror_reg_cl,
            .ror_mem_cl,
            .rol_reg_imm,
            .rol_mem_imm,
            .ror_reg_imm,
            .ror_mem_imm,
            => self.executeRotate(d),
            // SHLD/SHRD: the vacated end is filled from a second register.
            // Shared semantics with the Mach-O path via
            // `x64_decoder.doubleShift`, so the two processors cannot drift.
            .shld_reg_imm8,
            .shld_mem_imm8,
            .shld_reg_cl,
            .shld_mem_cl,
            .shrd_reg_imm8,
            .shrd_mem_imm8,
            .shrd_reg_cl,
            .shrd_mem_cl,
            => {
                const sz = d.size;
                const is_mem = switch (d.op) {
                    .shld_mem_imm8, .shld_mem_cl, .shrd_mem_imm8, .shrd_mem_cl => true,
                    else => false,
                };
                const from_cl = switch (d.op) {
                    .shld_reg_cl, .shld_mem_cl, .shrd_reg_cl, .shrd_mem_cl => true,
                    else => false,
                };
                const left = switch (d.op) {
                    .shld_reg_imm8, .shld_mem_imm8, .shld_reg_cl, .shld_mem_cl => true,
                    else => false,
                };
                const raw = if (from_cl) self.regVal(.cl_cx_ecx_rcx, .bits8) else d.imm;
                const count: u6 = @intCast(raw & @as(u64, if (sz == .bits64) 0x3F else 0x1F));
                if (count != 0) {
                    const destination = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                    const source = self.regVal(d.src_reg, sz);
                    const shifted = x64_decoder.doubleShift(destination, source, count, sz, left);
                    if (is_mem) self.writeMemVal(d.addr, sz, shifted.value) else self.setReg(d.dst_reg, sz, shifted.value);
                    self.setFlagsLogic(shifted.value, sz);
                    self.setFlag(RFL_CF, shifted.carry);
                    if (count == 1) self.setFlag(RFL_OF, shifted.sign_changed);
                }
            },
            .shl_reg_cl => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = self.shlCount(d.size);
                const r = self.shlValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsShl(old, r, d.size, count);
            },
            .shl_mem_cl => {
                const old = self.readMemVal(d.addr, d.size);
                const count = self.shlCount(d.size);
                const r = self.shlValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsShl(old, r, d.size, count);
            },
            .shr_reg_cl => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = self.shlCount(d.size);
                const r = self.shrValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsShr(old, r, d.size, count);
            },
            .shr_mem_cl => {
                const old = self.readMemVal(d.addr, d.size);
                const count = self.shlCount(d.size);
                const r = self.shrValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsShr(old, r, d.size, count);
            },
            .sar_reg_cl => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = self.shlCount(d.size);
                const r = self.sarValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsSar(old, r, d.size, count);
            },
            .sar_mem_cl => {
                const old = self.readMemVal(d.addr, d.size);
                const count = self.shlCount(d.size);
                const r = self.sarValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsSar(old, r, d.size, count);
            },
            .shl_reg_imm => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.shlValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsShl(old, r, d.size, count);
            },
            .shl_mem_imm => {
                const old = self.readMemVal(d.addr, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.shlValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsShl(old, r, d.size, count);
            },
            .shr_reg_imm => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.shrValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsShr(old, r, d.size, count);
            },
            .shr_mem_imm => {
                const old = self.readMemVal(d.addr, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.shrValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsShr(old, r, d.size, count);
            },
            .sar_reg_imm => {
                const old = self.regVal(d.dst_reg, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.sarValue(old, d.size, count);
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsSar(old, r, d.size, count);
            },
            .sar_mem_imm => {
                const old = self.readMemVal(d.addr, d.size);
                const count = immShiftCount(d.imm, d.size);
                const r = self.sarValue(old, d.size, count);
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsSar(old, r, d.size, count);
            },
            .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64 => {
                self.executeHighwayRegisterBinary(d, .test_bits);
            },
            .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64 => {
                self.executeHighwayMemoryBinary(d, .test_bits, .register_to_memory);
            },
            .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => self.executeHighwayImmediate(d, .test_bits, false, testImmForSize(d.imm, d.size)),
            .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => self.executeHighwayImmediate(d, .test_bits, true, testImmForSize(d.imm, d.size)),
            .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
                const a = self.regVal(d.dst_reg, d.size);
                const r = 0 -% a;
                self.setReg(d.dst_reg, d.size, r);
                self.setFlagsSub(0, a, r, d.size);
            },
            .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => {
                const a = self.readMemVal(d.addr, d.size);
                const r = 0 -% a;
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsSub(0, a, r, d.size);
            },
            .not_reg8, .not_reg16, .not_reg32, .not_reg64 => {
                self.setReg(d.dst_reg, d.size, ~self.regVal(d.dst_reg, d.size));
            },
            .not_mem8, .not_mem16, .not_mem32, .not_mem64 => {
                self.writeMemVal(d.addr, d.size, ~self.readMemVal(d.addr, d.size));
            },

            .bt_reg_reg => self.executeBitTestRegister(d, .probe, false),
            .bt_mem_reg => self.executeBitTestMemory(d, .probe, false),
            .bts_reg_reg => self.executeBitTestRegister(d, .set, false),
            .bts_mem_reg => self.executeBitTestMemory(d, .set, false),
            .btr_reg_reg => self.executeBitTestRegister(d, .reset, false),
            .btr_mem_reg => self.executeBitTestMemory(d, .reset, false),
            .btc_reg_reg => self.executeBitTestRegister(d, .complement, false),
            .btc_mem_reg => self.executeBitTestMemory(d, .complement, false),
            .bt_reg_imm => self.executeBitTestRegister(d, .probe, true),
            .bt_mem_imm => self.executeBitTestMemory(d, .probe, true),
            .bts_reg_imm => self.executeBitTestRegister(d, .set, true),
            .bts_mem_imm => self.executeBitTestMemory(d, .set, true),
            .btr_reg_imm => self.executeBitTestRegister(d, .reset, true),
            .btr_mem_imm => self.executeBitTestMemory(d, .reset, true),
            .btc_reg_imm => self.executeBitTestRegister(d, .complement, true),
            .btc_mem_imm => self.executeBitTestMemory(d, .complement, true),

            // ── cmp r/m, reg (opcode 0x39) ──
            .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64 => self.executeHighwayMemoryBinary(d, .cmp, .register_to_memory),

            // ── cmp reg, reg (opcode 0x39, mod=3) ──
            .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64 => self.executeHighwayRegisterBinary(d, .cmp),

            // ── cmp reg, r/m (0x3A/0x3B, d=1) ──
            .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64 => self.executeHighwayMemoryBinary(d, .cmp, .memory_to_register),

            // ── cmp r/m, imm8 (0x83 /7) ──
            .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8 => self.executeHighwayImmediate(d, .cmp, true, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => self.executeHighwayImmediate(d, .cmp, false, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .cmp_reg16_imm32, .cmp_reg32_imm32, .cmp_reg64_imm32 => self.executeHighwayImmediate(d, .cmp, false, testImmForSize(d.imm, d.size)),

            // ── inc/dec memory ──
            .inc_mem8 => {
                const old = self.readMemVal(d.addr, .bits8);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, true);
            },
            .inc_mem16 => {
                const old = self.readMemVal(d.addr, .bits16);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, true);
            },
            .inc_mem32 => {
                const old = self.readMemVal(d.addr, .bits32);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, true);
            },
            .inc_mem64 => {
                const old = self.readMemVal(d.addr, .bits64);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, true);
            },
            .dec_mem8 => {
                const old = self.readMemVal(d.addr, .bits8);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, false);
            },
            .dec_mem16 => {
                const old = self.readMemVal(d.addr, .bits16);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, false);
            },
            .dec_mem32 => {
                const old = self.readMemVal(d.addr, .bits32);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, false);
            },
            .dec_mem64 => {
                const old = self.readMemVal(d.addr, .bits64);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, false);
            },

            // ── inc/dec register (0xFF /0, /1 with mod=3) ──
            .inc_reg8 => {
                const old = self.regVal(d.dst_reg, .bits8);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, true);
            },
            .inc_reg16 => {
                const old = self.regVal(d.dst_reg, .bits16);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, true);
            },
            .inc_reg32 => {
                const old = self.regVal(d.dst_reg, .bits32);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, true);
            },
            .inc_reg64 => {
                const old = self.regVal(d.dst_reg, .bits64);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, true);
            },
            .dec_reg8 => {
                const old = self.regVal(d.dst_reg, .bits8);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, false);
            },
            .dec_reg16 => {
                const old = self.regVal(d.dst_reg, .bits16);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, false);
            },
            .dec_reg32 => {
                const old = self.regVal(d.dst_reg, .bits32);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, false);
            },
            .dec_reg64 => {
                const old = self.regVal(d.dst_reg, .bits64);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, false);
            },

            // ── mul [mem] (unsigned, accumulator form) ──
            .mul_mem8 => {
                const b = self.readMemVal(d.addr, .bits8);
                const a = self.regVal(.al_ax_eax_rax, .bits8);
                const result = @as(u16, @intCast(a)) * @as(u16, @intCast(b));
                self.setReg(.al_ax_eax_rax, .bits16, result);
            },
            .mul_mem16 => {
                const b: u16 = @intCast(self.readMemVal(d.addr, .bits16));
                const a: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const result: u32 = @as(u32, a) * @as(u32, b);
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(result & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast((result >> 16) & 0xFFFF));
            },
            .mul_mem32 => {
                const b = self.readMemVal(d.addr, .bits32);
                const a = self.regVal(.al_ax_eax_rax, .bits32);
                const result = @as(u64, a) * @as(u64, b);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(result & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast((result >> 32) & 0xFFFFFFFF));
            },
            .mul_mem64 => {
                const b = self.readMemVal(d.addr, .bits64);
                const a = self.regVal(.al_ax_eax_rax, .bits64);
                const result: u128 = @as(u128, a) * @as(u128, b);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(result & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast((result >> 64) & 0xFFFFFFFFFFFFFFFF));
            },

            // ── imul [mem] (signed, accumulator form) ──
            .imul_mem8 => {
                const a: i8 = @bitCast(@as(u8, @intCast(self.regVal(.al_ax_eax_rax, .bits8))));
                const b: i8 = @bitCast(@as(u8, @intCast(self.readMemVal(d.addr, .bits8))));
                const result: i16 = @as(i16, a) * @as(i16, b);
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(result)));
            },
            .imul_mem16 => {
                const a: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const b: i16 = @bitCast(@as(u16, @intCast(self.readMemVal(d.addr, .bits16))));
                const result: i32 = @as(i32, a) * @as(i32, b);
                const ru: u32 = @bitCast(result);
                const lo: u16 = @truncate(ru);
                const hi: u16 = @truncate(ru >> 16);
                self.setReg(.al_ax_eax_rax, .bits16, lo);
                self.setReg(.dl_dx_edx_rdx, .bits16, hi);
            },
            .imul_mem32 => {
                const a: i32 = @bitCast(@as(u32, @intCast(self.regVal(.al_ax_eax_rax, .bits32))));
                const b: i32 = @bitCast(@as(u32, @intCast(self.readMemVal(d.addr, .bits32))));
                const result: i64 = @as(i64, a) * @as(i64, b);
                const ru: u64 = @bitCast(result);
                const lo: u32 = @truncate(ru);
                const hi: u32 = @truncate(ru >> 32);
                self.setReg(.al_ax_eax_rax, .bits32, lo);
                self.setReg(.dl_dx_edx_rdx, .bits32, hi);
            },
            .imul_mem64 => {
                const a: i64 = @bitCast(self.regVal(.al_ax_eax_rax, .bits64));
                const b: i64 = @bitCast(self.readMemVal(d.addr, .bits64));
                const result: i128 = @as(i128, a) * @as(i128, b);
                const ru: u128 = @bitCast(result);
                const lo: u64 = @truncate(ru);
                const hi: u64 = @truncate(ru >> 64);
                self.setReg(.al_ax_eax_rax, .bits64, lo);
                self.setReg(.dl_dx_edx_rdx, .bits64, hi);
            },

            // ── div [mem] (unsigned) ──
            .div_mem8 => {
                const divisor = self.readMemVal(d.addr, .bits8);
                if (divisor == 0) return self.raiseDivideError();
                const dividend = self.regVal(.al_ax_eax_rax, .bits16);
                const quot = dividend / @as(u16, @truncate(divisor));
                const rem = dividend % @as(u16, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @intCast(quot & 0xFF));
                self.setReg(.dl_dx_edx_rdx, .bits8, @intCast(rem & 0xFF));
            },
            .div_mem16 => {
                const divisor = self.readMemVal(d.addr, .bits16);
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits16);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits16);
                const dividend = (@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo));
                const quot = dividend / @as(u32, @truncate(divisor));
                const rem = dividend % @as(u32, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(quot & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast(rem & 0xFFFF));
            },
            .div_mem32 => {
                const divisor = self.readMemVal(d.addr, .bits32);
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits32);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits32);
                const dividend = (@as(u64, dividend_hi) << 32) | dividend_lo;
                const quot = dividend / @as(u64, divisor);
                const rem = dividend % @as(u64, divisor);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(quot & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast(rem & 0xFFFFFFFF));
            },
            .div_mem64 => {
                const divisor = self.readMemVal(d.addr, .bits64);
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend = (@as(u128, dividend_hi) << 64) | dividend_lo;
                const quot = dividend / @as(u128, divisor);
                const rem = dividend % @as(u128, divisor);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(quot & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast(rem & 0xFFFFFFFFFFFFFFFF));
            },

            // ── idiv [mem] (signed) ──
            .idiv_mem8 => {
                const divisor: i8 = @bitCast(@as(u8, @intCast(self.readMemVal(d.addr, .bits8))));
                if (divisor == 0) return self.raiseDivideError();
                const dividend: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const quot = @divTrunc(dividend, @as(i16, divisor));
                const rem = @rem(dividend, @as(i16, divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @as(u8, @bitCast(@as(i8, @truncate(quot)))));
                self.setReg(.dl_dx_edx_rdx, .bits8, @as(u8, @bitCast(@as(i8, @truncate(rem)))));
            },
            .idiv_mem16 => {
                const divisor: i16 = @bitCast(@as(u16, @intCast(self.readMemVal(d.addr, .bits16))));
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const dividend_hi: u16 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits16));
                const dividend: i32 = @bitCast((@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo)));
                const quot = @divTrunc(dividend, @as(i32, divisor));
                const rem = @rem(dividend, @as(i32, divisor));
                {
                    const q: i16 = @truncate(quot);
                    const r: i16 = @truncate(rem);
                    self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(q)));
                    self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(r)));
                }
            },
            .idiv_mem32 => {
                const divisor: i32 = @bitCast(@as(u32, @intCast(self.readMemVal(d.addr, .bits32))));
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo: u32 = @intCast(self.regVal(.al_ax_eax_rax, .bits32));
                const dividend_hi: u32 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits32));
                const dividend: i64 = @bitCast((@as(u64, dividend_hi) << 32) | @as(u64, dividend_lo));
                const quot = @divTrunc(dividend, @as(i64, divisor));
                const rem = @rem(dividend, @as(i64, divisor));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u64, @bitCast(quot)));
                self.setReg(.dl_dx_edx_rdx, .bits32, @as(u64, @bitCast(rem)));
            },
            .idiv_mem64 => {
                const divisor: i64 = @bitCast(self.readMemVal(d.addr, .bits64));
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend: i128 = @bitCast((@as(u128, dividend_hi) << 64) | dividend_lo);
                const quot = @divTrunc(dividend, @as(i128, divisor));
                const rem = @rem(dividend, @as(i128, divisor));
                const q64: u64 = @bitCast(@as(i64, @truncate(quot)));
                const r64: u64 = @bitCast(@as(i64, @truncate(rem)));
                self.setReg(.al_ax_eax_rax, .bits64, q64);
                self.setReg(.dl_dx_edx_rdx, .bits64, r64);
            },

            // ── mul reg (unsigned) ──
            .mul_reg8 => {
                const b = self.regVal(d.src_reg, .bits8);
                const a = self.regVal(.al_ax_eax_rax, .bits8);
                const result = @as(u16, @intCast(a)) * @as(u16, @intCast(b));
                self.setReg(.al_ax_eax_rax, .bits16, result);
            },
            .mul_reg16 => {
                const b: u16 = @intCast(self.regVal(d.src_reg, .bits16));
                const a: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const result: u32 = @as(u32, a) * @as(u32, b);
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(result & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast((result >> 16) & 0xFFFF));
            },
            .mul_reg32 => {
                const b = self.regVal(d.src_reg, .bits32);
                const a = self.regVal(.al_ax_eax_rax, .bits32);
                const result = @as(u64, a) * @as(u64, b);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(result & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast((result >> 32) & 0xFFFFFFFF));
            },
            .mul_reg64 => {
                const b = self.regVal(d.src_reg, .bits64);
                const a = self.regVal(.al_ax_eax_rax, .bits64);
                const result = @as(u128, a) * @as(u128, b);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(result & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast((result >> 64) & 0xFFFFFFFFFFFFFFFF));
            },

            // ── imul reg (signed) ──
            .imul_reg8 => {
                const a: i8 = @bitCast(@as(u8, @intCast(self.regVal(.al_ax_eax_rax, .bits8))));
                const b: i8 = @bitCast(@as(u8, @intCast(self.regVal(d.src_reg, .bits8))));
                const result: i16 = @as(i16, a) * @as(i16, b);
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(result)));
            },
            .imul_reg16 => {
                const a: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const b: i16 = @bitCast(@as(u16, @intCast(self.regVal(d.src_reg, .bits16))));
                const result: i32 = @as(i32, a) * @as(i32, b);
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @truncate(result)))));
                self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(@as(i16, @truncate(result >> 16)))));
            },
            .imul_reg32 => {
                const raw_a: u32 = @intCast(self.regVal(.al_ax_eax_rax, .bits32));
                const raw_b: u32 = @intCast(self.regVal(d.src_reg, .bits32));
                const a: i32 = @bitCast(raw_a);
                const b: i32 = @bitCast(raw_b);
                const result: i64 = @as(i64, a) * @as(i64, b);
                const ru: u64 = @bitCast(result);
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(ru));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(ru >> 32));
            },
            .imul_reg64 => {
                const a: i64 = @bitCast(self.regVal(.al_ax_eax_rax, .bits64));
                const b: i64 = @bitCast(self.regVal(d.src_reg, .bits64));
                const result: i128 = @as(i128, a) * @as(i128, b);
                const ru: u128 = @bitCast(result);
                self.setReg(.al_ax_eax_rax, .bits64, @truncate(ru));
                self.setReg(.dl_dx_edx_rdx, .bits64, @truncate(ru >> 64));
            },

            // ── div reg (unsigned) ──
            .div_reg8 => {
                const divisor = self.regVal(d.src_reg, .bits8);
                if (divisor == 0) return self.raiseDivideError();
                const dividend = self.regVal(.al_ax_eax_rax, .bits16);
                const quot = dividend / @as(u16, @truncate(divisor));
                const rem = dividend % @as(u16, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @intCast(quot & 0xFF));
                self.setReg(.dl_dx_edx_rdx, .bits8, @intCast(rem & 0xFF));
            },
            .div_reg16 => {
                const divisor = self.regVal(d.src_reg, .bits16);
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits16);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits16);
                const dividend = (@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo));
                const quot = dividend / @as(u32, @truncate(divisor));
                const rem = dividend % @as(u32, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(quot & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast(rem & 0xFFFF));
            },
            .div_reg32 => {
                const divisor = self.regVal(d.src_reg, .bits32);
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits32);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits32);
                const dividend = (@as(u64, dividend_hi) << 32) | dividend_lo;
                const quot = dividend / @as(u64, divisor);
                const rem = dividend % @as(u64, divisor);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(quot & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast(rem & 0xFFFFFFFF));
            },
            .div_reg64 => {
                const divisor = self.regVal(d.src_reg, .bits64);
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend = (@as(u128, dividend_hi) << 64) | dividend_lo;
                const quot = dividend / @as(u128, divisor);
                const rem = dividend % @as(u128, divisor);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(quot & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast(rem & 0xFFFFFFFFFFFFFFFF));
            },

            // ── idiv reg (signed) ──
            .idiv_reg8 => {
                const divisor: i8 = @bitCast(@as(u8, @intCast(self.regVal(d.src_reg, .bits8))));
                if (divisor == 0) return self.raiseDivideError();
                const dividend: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const quot = @divTrunc(dividend, @as(i16, divisor));
                const rem = @rem(dividend, @as(i16, divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @as(u8, @bitCast(@as(i8, @truncate(quot)))));
                self.setReg(.dl_dx_edx_rdx, .bits8, @as(u8, @bitCast(@as(i8, @truncate(rem)))));
            },
            .idiv_reg16 => {
                const divisor: i16 = @bitCast(@as(u16, @intCast(self.regVal(d.src_reg, .bits16))));
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const dividend_hi: u16 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits16));
                const dividend: i32 = @bitCast((@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo)));
                const quot = @divTrunc(dividend, @as(i32, divisor));
                const rem = @rem(dividend, @as(i32, divisor));
                {
                    const q: i16 = @truncate(quot);
                    const r: i16 = @truncate(rem);
                    self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(q)));
                    self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(r)));
                }
            },
            .idiv_reg32 => {
                const divisor_raw: u32 = @intCast(self.regVal(d.src_reg, .bits32));
                const divisor: i32 = @bitCast(divisor_raw);
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo: u32 = @intCast(self.regVal(.al_ax_eax_rax, .bits32));
                const dividend_hi: u32 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits32));
                const dividend: i64 = @bitCast((@as(u64, dividend_hi) << 32) | @as(u64, dividend_lo));
                const quot = @divTrunc(dividend, @as(i64, divisor));
                const rem = @rem(dividend, @as(i64, divisor));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u64, @bitCast(quot)));
                self.setReg(.dl_dx_edx_rdx, .bits32, @as(u64, @bitCast(rem)));
            },
            .idiv_reg64 => {
                const divisor: i64 = @bitCast(self.regVal(d.src_reg, .bits64));
                if (divisor == 0) return self.raiseDivideError();
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend: i128 = @bitCast((@as(u128, dividend_hi) << 64) | dividend_lo);
                const quot = @divTrunc(dividend, @as(i128, divisor));
                const rem = @rem(dividend, @as(i128, divisor));
                const q64b: u64 = @bitCast(@as(i64, @truncate(quot)));
                const r64b: u64 = @bitCast(@as(i64, @truncate(rem)));
                self.setReg(.al_ax_eax_rax, .bits64, q64b);
                self.setReg(.dl_dx_edx_rdx, .bits64, r64b);
            },

            // ── Sign extension ──
            .cbw => {
                // cbw: AL → AX (sign extend). With 0x66: AX → EAX. With REX.W: EAX → RAX (cdqe)
                const al = self.regVal(.al_ax_eax_rax, .bits8);
                const extended = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(al)))));
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(extended)));
            },
            .cwde => {
                const ax = self.regVal(.al_ax_eax_rax, .bits16);
                const extended = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(ax)))));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(extended)));
            },
            .cdqe => {
                const eax = self.regVal(.al_ax_eax_rax, .bits32);
                const extended = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(eax)))));
                self.setReg(.al_ax_eax_rax, .bits64, @as(u64, @bitCast(extended)));
            },
            .cwd => {
                // cwd: AX → DX:AX. With 0x66: EAX → EDX:EAX (cdq). With REX.W: RAX → RDX:RAX (cqo)
                const ax = self.regVal(.al_ax_eax_rax, .bits16);
                const sign = if (ax & 0x8000 != 0) @as(u16, 0xFFFF) else 0;
                self.setReg(.dl_dx_edx_rdx, .bits16, sign);
            },
            .cdq => {
                // cdq: EAX → EDX:EAX (sign extend eax into edx)
                const eax32 = self.regVal(.al_ax_eax_rax, .bits32);
                const sign = if (eax32 & 0x80000000 != 0) @as(u32, 0xFFFFFFFF) else 0;
                self.setReg(.dl_dx_edx_rdx, .bits32, sign);
            },
            .cqo => {
                // cqo: RAX → RDX:RAX (sign extend rax into rdx)
                const rax = self.regVal(.al_ax_eax_rax, .bits64);
                const sign = if (rax & 0x8000000000000000 != 0) @as(u64, 0xFFFFFFFFFFFFFFFF) else 0;
                self.setReg(.dl_dx_edx_rdx, .bits64, sign);
            },

            // ── Zero/sign extend loads ──
            .movzx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits8)
                else
                    self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movzx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits16)
                else
                    self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movsx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    @as(i64, @as(i8, @bitCast(@as(u8, @truncate(self.regVal(d.src_reg, .bits8))))))
                else
                    @as(i64, @as(i8, @bitCast(@as(u8, @truncate(self.readMemVal(d.addr, .bits8))))));
                const dst_size: Size = if (d.size == .bits64) .bits64 else .bits32;
                self.setReg(d.dst_reg, dst_size, @as(u64, @bitCast(val)));
            },
            .movsx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    @as(i64, @as(i16, @bitCast(@as(u16, @truncate(self.regVal(d.src_reg, .bits16))))))
                else
                    @as(i64, @as(i16, @bitCast(@as(u16, @truncate(self.readMemVal(d.addr, .bits16))))));
                const dst_size: Size = if (d.size == .bits64) .bits64 else .bits32;
                self.setReg(d.dst_reg, dst_size, @as(u64, @bitCast(val)));
            },
            .movsxd_reg64_reg32 => {
                const val = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regVal(d.src_reg, .bits32))))));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(val)));
            },
            .movsxd_reg64_mem32 => {
                const raw = self.readMemVal(d.addr, .bits32);
                const val = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(raw)))));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(val)));
            },
            .lea_reg_mem => {
                self.setReg(d.dst_reg, d.size, d.addr);
            },
            .cmovcc_reg_reg => {
                if (evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.regVal(d.src_reg, d.size));
                } else if (d.size == .bits32) {
                    self.setReg(d.dst_reg, .bits64, self.regVal(d.dst_reg, .bits32));
                }
            },
            .cmovcc_reg_mem => {
                if (evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.readMemVal(d.addr, d.size));
                } else if (d.size == .bits32) {
                    self.setReg(d.dst_reg, .bits64, self.regVal(d.dst_reg, .bits32));
                }
            },
            .setcc_reg8 => {
                self.setReg(d.dst_reg, .bits8, if (evalCond(self.regs.rflags, d.cond)) 1 else 0);
            },
            .setcc_mem8 => {
                self.writeMemVal(d.addr, .bits8, if (evalCond(self.regs.rflags, d.cond)) 1 else 0);
            },
            .cmpxchg_mem8_reg8, .cmpxchg_mem16_reg16, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64, .cmpxchg_reg8_reg8, .cmpxchg_reg16_reg16, .cmpxchg_reg32_reg32, .cmpxchg_reg64_reg64, .cmpxchg8b_mem, .cmpxchg16b_mem => {
                const size = d.size;
                const accum = self.regVal(.al_ax_eax_rax, size);
                const old = if (d.is_reg_form) self.regVal(d.dst_reg, size) else self.readMemVal(d.addr, size);
                self.setFlagsSub(accum, old, accum -% old, size);
                if ((accum & maskForSize(size)) == (old & maskForSize(size))) {
                    if (d.is_reg_form) {
                        self.setReg(d.dst_reg, size, self.regVal(d.src_reg, size));
                    } else {
                        self.writeMemVal(d.addr, size, self.regVal(d.src_reg, size));
                    }
                    self.setFlag(RFL_ZF, true);
                } else {
                    self.setReg(.al_ax_eax_rax, size, old);
                    self.setFlag(RFL_ZF, false);
                }
            },
            .xchg_mem32_reg32, .xchg_mem64_reg64, .xchg_reg32_reg32, .xchg_reg64_reg64 => {
                const size = d.size;
                const old_mem = if (d.is_reg_form) self.regVal(d.dst_reg, size) else self.readMemVal(d.addr, size);
                const old_reg = self.regVal(d.src_reg, size);
                if (d.is_reg_form) {
                    self.setReg(d.dst_reg, size, old_reg);
                } else {
                    self.writeMemVal(d.addr, size, old_reg);
                }
                self.setReg(d.src_reg, size, old_mem);
            },
            .xadd_mem8_reg8, .xadd_mem32_reg32, .xadd_mem64_reg64 => {
                const old_mem = self.readMemVal(d.addr, d.size);
                const old_reg = self.regVal(d.src_reg, d.size);
                const result = old_mem +% old_reg;
                self.writeMemVal(d.addr, d.size, result);
                self.setReg(d.src_reg, d.size, old_mem);
                self.setFlagsAdd(old_mem, old_reg, result, d.size);
            },
            .xorps_xmm_xmm => {
                for (0..16) |i| {
                    self.xmm[d.xmm_dst][i] ^= self.xmm[d.xmm_src][i];
                }
            },
            .movups_xmm_xmm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .movups_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .movups_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            },
            .movaps_xmm_xmm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .movaps_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
                if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .movaps_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            },

            // ── imul r64, r/m64 (0F AF) ──
            .imul_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                self.writeImulNarrowResult(d.dst_reg, .bits64, signedInteger(a, .bits64) * signedInteger(b, .bits64));
            },
            .imul_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                self.writeImulNarrowResult(d.dst_reg, .bits64, signedInteger(a, .bits64) * signedInteger(b, .bits64));
            },
            .imul_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                self.writeImulNarrowResult(d.dst_reg, .bits32, signedInteger(a, .bits32) * signedInteger(b, .bits32));
            },
            .imul_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                self.writeImulNarrowResult(d.dst_reg, .bits32, signedInteger(a, .bits32) * signedInteger(b, .bits32));
            },

            // ── imul r, r/m, imm8/imm16/imm32 (0x6B/0x69) ──
            .imul_reg16_mem16_imm8,
            .imul_reg16_reg16_imm8,
            .imul_reg16_mem16_imm16,
            .imul_reg16_reg16_imm16,
            .imul_reg32_mem32_imm8,
            .imul_reg32_reg32_imm8,
            .imul_reg32_mem32_imm32,
            .imul_reg32_reg32_imm32,
            .imul_reg64_mem64_imm8,
            .imul_reg64_reg64_imm8,
            .imul_reg64_mem64_imm32,
            .imul_reg64_reg64_imm32,
            => {
                const size = imulImmediateSize(d.op);
                const source = if (d.is_reg_form)
                    self.regVal(d.src_reg, size)
                else
                    self.readMemVal(d.addr, size);
                self.writeImulNarrowResult(d.dst_reg, size, signedInteger(source, size) * signedImulImmediate(d));
            },

            // ── Stack and calls ──
            .call_rel32 => {
                const rel = @as(i64, @bitCast(d.imm));
                const transfer = x64_decoder.highway.relativeControl(.call, self.regs.rip, d.len, rel, true);
                const next_rip = transfer.return_address.?;
                const target_rip = transfer.target;
                self.traceWindowsCallbackCall("direct", target_rip, self.regs.rip, next_rip);
                if (self.trace_windows_threads and target_rip == 0x1405151af) {
                    log.info("Windows thread call target pthread_self: source_rip=0x{x} rsp_before=0x{x} return_rip=0x{x} stack_before=0x{x}", .{
                        self.regs.rip,
                        self.regs.rsp,
                        next_rip,
                        self.read64(self.regs.rsp),
                    });
                }
                if (x64_linux_runtime.tryLocalFunctionShim(self, target_rip, next_rip)) {
                    return;
                }
                self.noteGuestCall(.direct, target_rip, next_rip);
                self.push(next_rip);
                self.regs.rip = target_rip;
                return;
            },
            .call_mem64, .call_reg64 => {
                const next_rip = self.regs.rip + d.len;
                if (d.op == .call_mem64 and x64_linux_runtime.tryDynamicFunctionShim(self, d.addr, next_rip)) {
                    return;
                }
                const target = if (d.op == .call_reg64)
                    self.regVal(d.dst_reg, .bits64)
                else
                    self.readMemVal(d.addr, .bits64);
                self.traceWindowsCallbackCall(if (d.op == .call_reg64) "indirect-register" else "indirect-memory", target, if (d.op == .call_reg64) self.regVal(d.dst_reg, .bits64) else d.addr, next_rip);
                if (shouldTraceRip(self, self.regs.rip)) {
                    log.info("trace indirect call target rip=0x{x} op={s} operand=0x{x} loaded_target=0x{x} bytes={any} next_rip=0x{x}", .{
                        self.regs.rip,
                        @tagName(d.op),
                        if (d.op == .call_reg64) self.regVal(d.dst_reg, .bits64) else d.addr,
                        target,
                        if (d.op == .call_mem64) self.guestMemoryConst(d.addr, 8) orelse &[_]u8{} else &[_]u8{},
                        next_rip,
                    });
                }
                if (target == 0 and d.op == .call_mem64 and x64_linux_runtime.tryLibcStartMainTrampoline(self, d, next_rip)) {
                    return;
                }
                if (target == 0) {
                    const is_memory_call = d.op == .call_mem64;
                    const operand = if (is_memory_call) d.addr else self.regVal(d.dst_reg, .bits64);
                    const base_name = if (is_memory_call and d.sib_has_base) @tagName(d.sib_base_reg) else "<none>";
                    const base_value = if (is_memory_call and d.sib_has_base)
                        self.regVal(d.sib_base_reg, .bits64)
                    else
                        0;
                    const index_name = if (is_memory_call and d.sib_has_index) @tagName(d.sib_index_reg) else "<none>";
                    const index_value = if (is_memory_call and d.sib_has_index)
                        self.regVal(d.sib_index_reg, .bits64)
                    else
                        0;
                    const instruction_bytes = self.guestMemoryConst(self.regs.rip, @as(usize, d.len)) orelse &[_]u8{};
                    log.err("unresolved indirect call at rip=0x{x} op={s} source={s} effective=0x{x} loaded_target=0x{x} base={s}:0x{x} index={s}:0x{x} scale={d} rip_relative={} rsp=0x{x} return=0x{x} step={d} last_rip=0x{x} regs=[rax=0x{x},rcx=0x{x},rdx=0x{x},r8=0x{x},r9=0x{x}] bytes={any}", .{
                        self.regs.rip,
                        @tagName(d.op),
                        if (is_memory_call) "memory" else "register",
                        operand,
                        target,
                        base_name,
                        base_value,
                        index_name,
                        index_value,
                        d.sib_scale,
                        d.rip_relative,
                        self.regs.rsp,
                        self.read64(self.regs.rsp),
                        self.executed_steps,
                        self.last_instruction_rip,
                        self.regs.rax,
                        self.regs.rcx,
                        self.regs.rdx,
                        self.regs.r8,
                        self.regs.r9,
                        instruction_bytes,
                    });
                    self.faulted = true;
                    self.exit_code = 127;
                    self.termination_reason = .invalid_control_flow_target;
                    self.terminated = true;
                    return;
                }
                if (self.trace_windows_threads and target == 0x1405151af) {
                    log.info("Windows thread indirect call target pthread_self: source_rip=0x{x} rsp_before=0x{x} return_rip=0x{x} stack_before=0x{x}", .{
                        self.regs.rip,
                        self.regs.rsp,
                        next_rip,
                        self.read64(self.regs.rsp),
                    });
                }
                self.noteGuestCall(.indirect, target, next_rip);
                self.push(next_rip);
                self.regs.rip = target;
                return;
            },
            .ret => {
                const return_rip = self.pop();
                if (self.trace_string_memory and
                    self.regs.rip >= 0x140134c80 and self.regs.rip < 0x140135400)
                {
                    const string_object = self.regs.rax;
                    const data_address = self.read64(string_object);
                    const string_length = self.read64(string_object +| 8);
                    const bytes = if (string_length <= 64)
                        self.guestMemoryConst(data_address, string_length) orelse &.{}
                    else
                        &.{};
                    log.info("PE EscapeString return object=0x{x} data=0x{x} length={d} bytes={any}", .{
                        string_object,
                        data_address,
                        string_length,
                        bytes,
                    });
                }
                if (return_rip == 0 and self.windows_active_guest_thread_slot != null) {
                    log.err("Windows guest ret produced null RIP: thread=0x{x} source_rip=0x{x} rsp_after_pop=0x{x} rbp=0x{x} stack_next=0x{x}", .{
                        self.active_guest_thread,
                        self.regs.rip,
                        self.regs.rsp,
                        self.regs.rbp,
                        self.read64(self.regs.rsp),
                    });
                }
                self.regs.rip = return_rip;
                self.noteGuestReturn(return_rip);
                return;
            },
            .push_reg => {
                self.push(self.regVal(d.src_reg, .bits64));
            },
            .push_mem64 => {
                self.push(self.readMemVal(d.addr, .bits64));
            },
            .push_imm => {
                self.push(d.imm);
            },
            .pop_reg => {
                self.setReg(d.dst_reg, .bits64, self.pop());
            },
            .pop_mem64 => {
                const val = self.pop();
                self.writeMemVal(d.addr, .bits64, val);
            },
            .hlt => {
                self.exit_code = self.regs.rax;
                self.terminated = true;
            },

            // ── Jump short rel8 ──
            .jmp_rel8 => {
                self.regs.rip = x64_decoder.highway.relativeControl(.jump, self.regs.rip, d.len, @bitCast(d.imm), true).target;
                return;
            },
            .jmp_mem64, .jmp_reg64 => {
                if (d.op == .jmp_mem64 and x64_linux_runtime.tryDynamicFunctionShim(self, d.addr, null)) {
                    return;
                }
                const target = if (d.op == .jmp_reg64)
                    self.regVal(d.dst_reg, .bits64)
                else
                    self.readMemVal(d.addr, .bits64);
                if (target == 0) {
                    const operand = if (d.op == .jmp_reg64)
                        self.regVal(d.dst_reg, .bits64)
                    else
                        d.addr;
                    log.err("unresolved indirect jump at rip=0x{x} operand=0x{x} source={s}", .{
                        self.regs.rip,
                        operand,
                        if (d.op == .jmp_reg64) "register" else "memory",
                    });
                    self.faulted = true;
                    self.exit_code = 127;
                    self.terminated = true;
                    return;
                }
                self.regs.rip = target;
                return;
            },

            // ── Conditional jump rel8 ──
            .jcc_rel8 => {
                const taken = evalCond(self.regs.rflags, d.cond);
                if (shouldTraceRip(self, self.regs.rip)) log.info("conditional branch rip=0x{x} cond={s} rflags=0x{x} zf={d} taken={}", .{
                    self.regs.rip,
                    @tagName(d.cond),
                    self.regs.rflags,
                    @intFromBool((self.regs.rflags & RFL_ZF) != 0),
                    taken,
                });
                if (taken) {
                    self.regs.rip = x64_decoder.highway.relativeControl(.conditional_jump, self.regs.rip, d.len, @bitCast(d.addr), taken).target;
                    return;
                }
            },
            .jcc_rel32 => {
                const taken = evalCond(self.regs.rflags, d.cond);
                if (shouldTraceRip(self, self.regs.rip)) log.info("conditional branch rip=0x{x} cond={s} rflags=0x{x} zf={d} taken={}", .{
                    self.regs.rip,
                    @tagName(d.cond),
                    self.regs.rflags,
                    @intFromBool((self.regs.rflags & RFL_ZF) != 0),
                    taken,
                });
                if (taken) {
                    self.regs.rip = x64_decoder.highway.relativeControl(.conditional_jump, self.regs.rip, d.len, @bitCast(d.addr), taken).target;
                    return;
                }
            },

            // ── Syscall ──
            .syscall => {
                const syscall_number = self.regs.rax;
                const boundary = x64_decoder.highway.systemBoundary(.elf64, .syscall, syscall_number, "");
                if (boundary.disposition != .forward) {
                    self.faulted = true;
                    self.terminated = true;
                    self.exit_code = 126;
                    return;
                }
                const syscall_fd = self.regs.rdi;
                const syscall_buf = self.regs.rsi;
                const syscall_count = self.regs.rdx;
                self.invokeLinuxSyscall(
                    syscall_number,
                    self.regs.rdi,
                    self.regs.rsi,
                    self.regs.rdx,
                    self.regs.r10,
                    self.regs.r8,
                    self.regs.r9,
                );
                x64_guest_abi.diagnoseSyscall(self, syscall_number, syscall_fd, syscall_buf, syscall_count, self.regs.rax);
            },
            .ud2 => {
                log.err("elf-processor: UD2 instruction at rip=0x{x} — intentional invalid opcode exception", .{self.regs.rip});
                self.faulted = true;
                self.terminated = true;
                self.exit_code = 127;
                return;
            },
            .cpuid => {
                const result = x64_decoder.emulatedCpuid(@truncate(self.regs.rax), @truncate(self.regs.rcx));
                self.setReg(.al_ax_eax_rax, .bits32, result.eax);
                self.setReg(.bl_bx_ebx_rbx, .bits32, result.ebx);
                self.setReg(.cl_cx_ecx_rcx, .bits32, result.ecx);
                self.setReg(.dl_dx_edx_rdx, .bits32, result.edx);
            },
            .xgetbv => {
                const value = if (@as(u32, @truncate(self.regs.rcx)) == 0) x64_decoder.emulatedXcr0() else 0;
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(value));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(value >> 32));
            },
            .rdtsc, .rdtscp => {
                const ticks = self.executed_steps;
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(ticks));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(ticks >> 32));
                if (d.op == .rdtscp) self.setReg(.cl_cx_ecx_rcx, .bits32, 0);
            },
            .mfence, .lfence, .sfence => releaseMemoryBarrier(),
            .emms, .wait => {},
            .kmovw, .kmovd, .kmovq => {
                const is_word = d.op == .kmovw;
                const register_size: Size = if (d.op == .kmovq) .bits64 else .bits32;
                const memory_size: Size = if (is_word) .bits16 else register_size;
                const mask: u64 = if (is_word) 0xFFFF else if (d.op == .kmovq) std.math.maxInt(u64) else 0xFFFF_FFFF;
                if (d.mask_to_gpr) {
                    const value = self.k[d.src_k] & mask;
                    if (d.is_reg_form)
                        self.setReg(d.dst_reg, register_size, value)
                    else
                        self.writeMemVal(d.addr, memory_size, value);
                } else {
                    const value = if (d.is_reg_form)
                        self.regVal(d.src_reg, register_size)
                    else
                        self.readMemVal(d.addr, memory_size);
                    self.k[d.dst_k] = value & mask;
                }
            },
            .vmovd_xmm_reg32, .vmovd_xmm_mem32 => {
                const value: u32 = @truncate(if (d.op == .vmovd_xmm_reg32)
                    self.regVal(d.src_reg, .bits32)
                else
                    self.readMemVal(d.addr, .bits32));
                @memset(&self.xmm[d.xmm_dst], 0);
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], value, .little);
            },
            .vmovd_reg32_xmm, .vmovd_mem32_xmm => {
                const value = std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little);
                if (d.op == .vmovd_reg32_xmm) {
                    self.setReg(d.dst_reg, .bits32, value);
                } else {
                    self.writeMemVal(d.addr, .bits32, value);
                }
            },
            .vmovq_xmm_reg64, .vmovq_xmm_mem64 => {
                const value = if (d.op == .vmovq_xmm_reg64)
                    self.regVal(d.src_reg, .bits64)
                else
                    self.readMemVal(d.addr, .bits64);
                @memset(&self.xmm[d.xmm_dst], 0);
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], value, .little);
            },
            .vmovq_reg64_xmm, .vmovq_mem64_xmm => {
                const value = std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little);
                if (d.op == .vmovq_reg64_xmm) {
                    self.setReg(d.dst_reg, .bits64, value);
                } else {
                    self.writeMemVal(d.addr, .bits64, value);
                }
            },
            .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8 => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                const value: u8 = @truncate(if (d.op == .vpinsrb_xmm_xmm_reg32)
                    self.regVal(d.src_reg, .bits32)
                else
                    self.readMemVal(d.addr, .bits8));
                self.xmm[d.xmm_dst][@intCast(d.imm & 0x0F)] = value;
            },
            .vpshufb => {
                const source = self.xmm[d.xmm_src];
                const mask = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = shuffleBytes(source, mask);
            },
            .vpshufd => self.executeVpshufd(d),
            .vshufps => {
                const lhs = self.xmm[d.xmm_src];
                const rhs = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                var result: [16]u8 = undefined;
                const control: u8 = @truncate(d.imm);
                for (0..4) |destination_lane| {
                    const shift: u3 = @intCast(destination_lane * 2);
                    const source_lane = (control >> shift) & 0x03;
                    const source = if (destination_lane < 2) lhs else rhs;
                    const destination_offset = destination_lane * 4;
                    const source_offset = @as(usize, source_lane) * 4;
                    @memcpy(result[destination_offset..][0..4], source[source_offset..][0..4]);
                }
                self.xmm[d.xmm_dst] = result;
            },
            .vpmuludq, .vpblendw, .vpinsrd, .vpinsrq, .vpinsrw, .vpunpckhbw, .vpunpckhwd, .vpunpckhdq, .vpunpcklbw, .vpunpcklwd, .vpslld, .vpsllq, .vpsllw, .vpslldq, .vpsrld, .vpsrlq, .vpsrlw, .vpsrldq, .vpsraw, .vpsrad, .vpsubb, .vpsubd, .vpsubq, .vpsubw, .vpaddb, .vpaddd, .vpaddq, .vpaddw, .vpmullw, .add_accum_imm, .or_accum_imm, .adc_accum_imm, .sbb_accum_imm, .and_accum_imm, .sub_accum_imm, .xor_accum_imm, .cmp_accum_imm, .vmovdqu_xmm_xmm, .vmovdqu_xmm_mem, .vmovdqu_mem_xmm, .vmovdqa_xmm_xmm, .vmovdqa_xmm_mem, .vmovdqa_mem_xmm, .vmovups_xmm_xmm, .vmovups_xmm_mem, .vmovups_mem_xmm, .vmovaps_xmm_xmm, .vmovaps_xmm_mem, .vmovaps_mem_xmm, .vmovupd_xmm_xmm, .vmovupd_xmm_mem, .vmovupd_mem_xmm, .vmovapd_xmm_xmm, .vmovapd_xmm_mem, .vmovapd_mem_xmm, .vmovss_xmm_mem, .vmovss_mem_xmm, .vmovsd_xmm_mem, .vmovsd_mem_xmm, .vmovlps_xmm_xmm_mem64, .vmovlps_mem64_xmm, .vmovlpd_xmm_xmm_mem64, .vmovlpd_mem64_xmm, .vmovhps_xmm_xmm_mem64, .vmovhps_mem64_xmm, .vmovhpd_xmm_xmm_mem64, .vmovhpd_mem64_xmm, .vmovshdup, .vmovsldup, .vmovddup, .vmovdqu_ymm_ymm, .vmovdqu_ymm_mem, .vmovdqu_mem_ymm, .vmovdqa_ymm_ymm, .vmovdqa_ymm_mem, .vmovdqa_mem_ymm, .vmovups_ymm_ymm, .vmovups_ymm_mem, .vmovups_mem_ymm, .vmovaps_ymm_ymm, .vmovaps_ymm_mem, .vmovaps_mem_ymm, .vmovupd_ymm_ymm, .vmovupd_ymm_mem, .vmovupd_mem_ymm, .vmovapd_ymm_ymm, .vmovapd_ymm_mem, .vmovapd_mem_ymm, .vzeroupper, .pmovmskb, .vpmovmskb, .vpmovmskb_ymm, .vcvtsi2ss_xmm_reg, .vcvtsi2ss_xmm_mem, .vcvtsi2sd_xmm_reg, .vcvtsi2sd_xmm_mem, .vcvtss2sd, .vcvtsd2ss, .vaddss, .vaddsd, .vaddps, .vaddpd, .vmulss, .vmulsd, .vmulps, .vmulpd, .vsubss, .vsubsd, .vsubps, .vsubpd, .vdivss, .vdivsd, .vdivps, .vdivpd, .vucomiss, .vucomisd, .vroundss, .vroundsd, .vroundps, .vroundpd, .vcvttss2si, .vcvttsd2si, .vcvtss2si, .vcvtsd2si, .vandps, .vandpd, .vandnps, .vandnpd, .vorps, .vorpd, .vxorps, .vxorpd, .vpor, .vpand, .vpandn, .vpxor, .vpcmpeqb, .vpcmpeqw, .vpcmpeqd, .vpcmpeqq, .vpcmpgtb, .vpcmpgtw, .vpcmpgtd, .vpcmpgtq, .vpunpckldq, .vpunpcklqdq, .vpunpckhqdq, .vmovhlps, .vmovlhps, .vmovmskps, .vmovmskpd, .vsqrtps, .vsqrtpd, .vsqrtss, .vsqrtsd, .vunpcklps, .vunpckhps, .vunpcklpd, .vunpckhpd, .vcvtps2pd, .vcvtpd2ps, .vptest, .vtestps, .vtestpd => self.executeVectorTest(d),
            // Legacy scalar register moves are consumed by
            // executeCleoVectorMove above. Keep explicit cases here because
            // this exhaustive fallback switch must still name every Op;
            // reaching either case would mean the handler's contract changed.
            .vmovss_xmm_xmm, .vmovsd_xmm_xmm => unreachable,
            .vmovq_xmm_xmm => unreachable,
            .vpdpbusd => self.executeVpdpbusd(d),
            .vextractf128, .vinsertf128, .vinserti128 => self.executeVexLane128(d),
            .vperm2f128 => self.executeVexPermute2x128(d),
            .vphminposuw => self.executeVphminposuw(d),
            .vpsadbw,
            .vpmaddubsw,
            .vpmaddwd,
            .vpcmpb,
            .vpmovqd,
            .vextracti32x4,
            .vextracti64x4,
            .movdir64b,
            .vpermilpd,
            // SSSE3/AVX2 integer 0x38 ops (not decoded for ELF)
            .vpsignb,
            .vpsignw,
            .vpsignd,
            .vpabsb,
            .vpabsw,
            .vpabsd,
            .vpsrlvw,
            .vpsravw,
            .vpsllvw,
            .vpmovsxbw,
            .vpmovsxbd,
            .vpmovsxbq,
            .vpmovsxwd,
            .vpmovsxwq,
            .vpmovsxdq,
            .vpmovzxbw,
            .vpmovzxbd,
            .vpmovzxbq,
            .vpmovzxwd,
            .vpmovzxwq,
            .vpmovzxdq,
            .vpmuldq,
            .vpacksswb,
            .vpackuswb,
            .vpackusdw,
            .vpermd,
            .vpextrb,
            .vpextrw,
            .vpextrd,
            .vpextrq,
            .vpminsb,
            .vpminsd,
            .vpminuw,
            .vpminud,
            .vpminub,
            .vpmaxsb,
            .vpmaxsd,
            .vpmaxuw,
            .vpmaxud,
            .vpmaxub,
            .vpsubsb,
            .vpsubsw,
            .vpsubusw,
            .vpaddsb,
            .vpaddsw,
            .vpmulhw,
            .vpmulhuw,
            .vpmulld_38,
            .vphaddw,
            .vphaddd,
            .vphaddsw,
            .vphsubw,
            .vphsubd,
            .vphsubsw,
            .vfmadd132ps,
            .vfmadd132pd,
            .vfmadd213ps,
            .vfmadd213pd,
            .vfmadd231ps,
            .vfmadd231pd,
            .vfmsub132ps,
            .vfmsub132pd,
            .vfmsub213ps,
            .vfmsub213pd,
            .vfmsub231ps,
            .vfmsub231pd,
            .vfmaddsub132ps,
            .vfmaddsub132pd,
            .vfmaddsub213ps,
            .vfmaddsub213pd,
            .vfmaddsub231ps,
            .vfmaddsub231pd,
            .vfmsubadd132ps,
            .vfmsubadd132pd,
            .vfmsubadd213ps,
            .vfmsubadd213pd,
            .vfmsubadd231ps,
            .vfmsubadd231pd,
            .vpsrlvd,
            .vpsravd,
            .vpsllvd,
            .vblendvps,
            .vblendvpd,
            .vpblendvb,
            .vpalignr,
            .vmaskmovps_load,
            .vmaskmovps_store,
            .vmaskmovpd_load,
            .vmaskmovpd_store,
            .vpermps,
            .vinsertps,
            // AVX SIMD float min/max
            .vminps,
            .vminpd,
            .vminss,
            .vminsd,
            .vmaxps,
            .vmaxpd,
            .vmaxss,
            .vmaxsd,
            // AVX horizontal / reciprocal
            .vhaddps,
            .vhaddpd,
            .vhsubps,
            .vhsubpd,
            .vrcpps,
            .vrcpss,
            .vrsqrtps,
            .vrsqrtss,
            // AVX SIMD compare
            .vcmpps,
            .vcmppd,
            .vcmpss,
            .vcmpsd,
            // AVX512/AVX extensions (not yet decoded for ELF execution)
            .vscalefps,
            .vscalefpd,
            .vrangeps,
            .vrangepd,
            .vfixupimmps,
            .vfixupimmpd,
            .vcompressps,
            .vcompresspd,
            .vexpandps,
            .vexpandpd,
            .vbroadcastss,
            .vbroadcastsd,
            .vbroadcastf128,
            .vbroadcasti128,
            .vpermi2d,
            .vpermi2q,
            .vpermi2ps,
            .vpermi2pd,
            .vpermt2d,
            .vpermt2q,
            .vpermt2ps,
            .vpermt2pd,
            .vgatherdps,
            .vgatherdpd,
            .vgatherqps,
            .vgatherqpd,
            .vpgatherdd,
            .vpgatherdq,
            .vscatterdps,
            .vscatterdpd,
            .vscatterqps,
            .vscatterqpd,
            .vpscatterdd,
            .vpscatterdq,
            .vpternlogd,
            .vpternlogq,
            .vcvtps2ph,
            .vcvtph2ps,
            .vcvtne2ps2bf16,
            .vcvttps2dq,
            .vcvtps2dq,
            .vcvtdq2ps,
            .vshuff32x4,
            .vshuff64x2,
            .vshufi32x4,
            .vshufi64x2,
            .valignd,
            .valignq,
            .vpmovm2d,
            .vpmovd2m,
            .vpmultishiftqb,
            .vpconflictd,
            .vpconflictq,
            .vpackssdw,
            .vpshuflw,
            .vpshufhw,
            .vblendps,
            .vshufpd,
            .vpermilps,
            .vpbroadcastw,
            .vpbroadcastd,
            .vpbroadcastq,
            .vextractps,
            .vmovntdq,
            .vmovntps,
            .vmovntdqa,
            .vpcmpistri,
            .vpmaxsw,
            .vcvtdq2pd,
            .vcvttpd2dq,
            => self.terminateUnimplemented(d),
        }

        if (!self.terminated) {
            self.regs.rip += d.len;
        }
    }

    pub fn invokeLinuxSyscall(self: *ElfState, number: u64, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
        self.regs.rax = number;
        self.regs.rdi = arg1;
        self.regs.rsi = arg2;
        self.regs.rdx = arg3;
        self.regs.r10 = arg4;
        self.regs.r8 = arg5;
        self.regs.r9 = arg6;
        self.dispatchLinuxSyscall();
    }

    fn dispatchLinuxSyscall(self: *ElfState) void {
        switch (self.regs.rax) {
            SYS_exit => {
                self.exit_code = self.regs.rdi;
                self.terminated = true;
                self.traceSyscall("exit(code={d})", .{self.exit_code});
            },
            SYS_read => {
                self.handleReadSyscall();
            },
            SYS_write => {
                self.handleWriteSyscall();
            },
            SYS_open => {
                self.handleOpenSyscall();
            },
            SYS_close => {
                self.handleCloseSyscall();
            },
            SYS_creat => {
                self.handleCreatSyscall();
            },
            SYS_arch_prctl => {
                self.handleArchPrctlSyscall();
            },
            SYS_gettid => {
                self.regs.rax = 1;
                self.traceSyscall("gettid() -> {d}", .{self.regs.rax});
            },
            else => {
                log.warn("unimplemented syscall {d}", .{self.regs.rax});
                self.faulted = true;
                self.exit_code = 127;
                self.terminated = true;
            },
        }
    }

    pub fn guestCString(self: *ElfState, addr: u64, maximum: usize) ?[]const u8 {
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const rest = self.mem[off_usize..];
        const bounded = rest[0..@min(rest.len, maximum)];
        const len = std.mem.indexOfScalar(u8, bounded, 0) orelse return null;
        return bounded[0..len];
    }

    fn handleArchPrctlSyscall(self: *ElfState) void {
        const ARCH_SET_GS: u64 = 0x1001;
        const ARCH_SET_FS: u64 = 0x1002;
        const ARCH_GET_FS: u64 = 0x1003;
        const ARCH_GET_GS: u64 = 0x1004;
        const code = self.regs.rdi;
        const address = self.regs.rsi;
        self.regs.rax = switch (code) {
            ARCH_SET_FS => blk: {
                self.regs.segments.fs.base = address;
                break :blk 0;
            },
            ARCH_SET_GS => blk: {
                self.regs.segments.gs.base = address;
                break :blk 0;
            },
            ARCH_GET_FS, ARCH_GET_GS => blk: {
                const off = self.addrToOffset(address) orelse break :blk x64_syscalls.errnoValue(.bad_address);
                if (off + 8 > self.mem.len) break :blk x64_syscalls.errnoValue(.bad_address);
                const base = if (code == ARCH_GET_FS) self.regs.segments.fs.base else self.regs.segments.gs.base;
                self.write64(address, base);
                break :blk 0;
            },
            else => x64_syscalls.errnoValue(.invalid_argument),
        };
        self.traceSyscall("arch_prctl(code=0x{x}, address=0x{x}) -> {d}", .{ code, address, syscallResult(self.regs.rax) });
    }

    fn handleOpenSyscall(self: *ElfState) void {
        const path_addr = self.regs.rdi;
        const flags_raw = self.regs.rsi;
        const mode_raw = self.regs.rdx;
        const path = self.guestCString(self.regs.rdi, std.math.maxInt(usize)) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            self.traceSyscall("open(path=0x{x}, flags=0x{x}, mode=0o{o}) -> {d}", .{
                path_addr,
                flags_raw,
                mode_raw & 0o7777,
                syscallResult(self.regs.rax),
            });
            return;
        };
        const path_z = self.allocator.dupeZ(u8, path) catch {
            self.regs.rax = x64_syscalls.errnoValue(.io);
            self.traceSyscall("open(\"{s}\", flags=0x{x}, mode=0o{o}) -> {d}", .{
                path,
                flags_raw,
                mode_raw & 0o7777,
                syscallResult(self.regs.rax),
            });
            return;
        };
        defer self.allocator.free(path_z);

        const fd = std.c.open(path_z.ptr, linuxOpenFlagsToHost(flags_raw), @as(std.c.mode_t, @intCast(mode_raw & 0o7777)));
        self.regs.rax = if (fd < 0) x64_syscalls.errnoValue(.no_entry) else @as(u64, @intCast(fd));
        self.traceOpenResult(path, flags_raw, mode_raw, self.regs.rax);
    }

    fn handleCreatSyscall(self: *ElfState) void {
        const path_addr = self.regs.rdi;
        const requested_mode = if (self.regs.rdx != 0) self.regs.rdx else self.regs.rsi;
        const path = self.guestCString(self.regs.rdi, std.math.maxInt(usize)) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            self.traceSyscall("creat(path=0x{x}, mode=0o{o}) -> {d}", .{
                path_addr,
                requested_mode & 0o7777,
                syscallResult(self.regs.rax),
            });
            return;
        };
        const path_z = self.allocator.dupeZ(u8, path) catch {
            self.regs.rax = x64_syscalls.errnoValue(.io);
            self.traceSyscall("creat(\"{s}\", mode=0o{o}) -> {d}", .{
                path,
                requested_mode & 0o7777,
                syscallResult(self.regs.rax),
            });
            return;
        };
        defer self.allocator.free(path_z);
        if (self.diagnose_abi) self.rememberInteractiveOutputPath(path);

        var flags: std.c.O = .{};
        flags.ACCMODE = .WRONLY;
        flags.CREAT = true;
        flags.TRUNC = true;
        const mode: std.c.mode_t = @intCast(requested_mode & 0o7777);
        var fd = std.c.open(path_z.ptr, flags, mode);
        if (fd < 0) {
            _ = std.c.unlink(path_z.ptr);
            fd = std.c.open(path_z.ptr, flags, mode);
        }
        self.regs.rax = if (fd < 0) x64_syscalls.errnoValue(.io) else @as(u64, @intCast(fd));
        self.traceCreatResult(path, requested_mode, self.regs.rax);
    }

    fn rememberInteractiveOutputPath(self: *ElfState, path: []const u8) void {
        const copy = self.allocator.dupe(u8, path) catch return;
        if (self.interactive_output_path) |old| self.allocator.free(old);
        self.interactive_output_path = copy;
        self.interactive_summary_printed = false;
    }

    fn handleReadSyscall(self: *ElfState) void {
        const fd_raw = self.regs.rdi;
        const fd = hostFdFromGuest(fd_raw) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_file_descriptor);
            self.traceGuestIo("read", fd_raw, self.regs.rsi, self.regs.rdx, self.regs.rax);
            return;
        };
        const addr = self.regs.rsi;
        const count = self.regs.rdx;
        const data = self.guestMemory(addr, count) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            self.traceGuestIo("read", fd_raw, addr, count, self.regs.rax);
            return;
        };

        const n = std.c.read(fd, data.ptr, data.len);
        self.regs.rax = if (n < 0) x64_syscalls.errnoValue(.io) else @as(u64, @intCast(n));
        self.traceGuestIo("read", fd_raw, addr, count, self.regs.rax);
    }

    fn handleCloseSyscall(self: *ElfState) void {
        const fd_raw = self.regs.rdi;
        const fd = hostFdFromGuest(fd_raw) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_file_descriptor);
            if (self.shouldTraceFd(fd_raw)) {
                log.info("syscall: close(fd={d}) -> {d}", .{ fd_raw, syscallResult(self.regs.rax) });
            }
            return;
        };
        if (fd <= 2) {
            self.regs.rax = 0;
            if (self.shouldTraceFd(fd_raw)) {
                log.info("syscall: close(fd={d}) -> {d}", .{ fd, syscallResult(self.regs.rax) });
            }
            return;
        }
        self.regs.rax = if (std.c.close(fd) == 0) 0 else x64_syscalls.errnoValue(.bad_file_descriptor);
        if (self.shouldTraceFd(fd_raw)) {
            log.info("syscall: close(fd={d}) -> {d}", .{ fd, syscallResult(self.regs.rax) });
        }
    }

    fn handleWriteSyscall(self: *ElfState) void {
        const fd = self.regs.rdi;
        const addr = self.regs.rsi;
        const count = self.regs.rdx;
        const data = self.guestMemoryConst(addr, count) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            self.traceGuestIo("write", fd, addr, count, self.regs.rax);
            return;
        };
        self.regs.rax = self.writeHostFd(fd, data);
        self.traceGuestIo("write", fd, addr, count, self.regs.rax);
    }
};

fn syscallResult(value: u64) i64 {
    return @bitCast(value);
}

fn hostFdFromGuest(fd: u64) ?std.c.fd_t {
    if (fd > std.math.maxInt(std.c.fd_t)) return null;
    return @intCast(fd);
}

fn linuxOpenFlagsToHost(flags_raw: u64) std.c.O {
    var flags: std.c.O = .{};
    flags.ACCMODE = switch (flags_raw & 0x3) {
        1 => .WRONLY,
        2 => .RDWR,
        else => .RDONLY,
    };
    flags.CREAT = (flags_raw & 0o100) != 0;
    flags.TRUNC = (flags_raw & 0o1000) != 0;
    flags.APPEND = (flags_raw & 0o2000) != 0;
    return flags;
}

fn shouldTraceRip(self: *const ElfState, rip: u64) bool {
    const start = self.trace_rip_start orelse return false;
    const end = self.trace_rip_end orelse start;
    return rip >= start and rip <= end;
}

fn parseEnvU64(text: []const u8) ?u64 {
    if (text.len >= 2 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X')) {
        return std.fmt.parseUnsigned(u64, text[2..], 16) catch null;
    }
    return std.fmt.parseUnsigned(u64, text, 10) catch null;
}

// ─── Decoder ───

fn signExtendImm8(imm: u64) u64 {
    const signed: i8 = @bitCast(@as(u8, @truncate(imm)));
    return @as(u64, @bitCast(@as(i64, signed)));
}

fn shuffleBytes(source: [16]u8, mask: [16]u8) [16]u8 {
    var result = [_]u8{0} ** 16;
    for (mask, 0..) |selector, index| {
        if (selector & 0x80 == 0) result[index] = source[selector & 0x0F];
    }
    return result;
}

fn testImmForSize(imm: u64, size: Size) u64 {
    return switch (size) {
        .bits8 => imm & 0xFF,
        .bits16 => imm & 0xFFFF,
        .bits32 => imm & 0xFFFF_FFFF,
        .bits64 => @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(imm))))))),
    };
}

fn decodeInsn(bytes: []const u8) DecodedInsn {
    return x64_decoder.decodeLegacyInstruction(bytes, .long64);
}

// ─── High-level API ───

pub fn loadAndRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8) !u64 {
    return loadRunElf(allocator, elf_bytes, .{});
}

pub const ElfRunOptions = struct {
    dump_results: bool = false,
    dump_all_results: bool = false,
    source_text: ?[]const u8 = null,
    argv: []const []const u8 = &.{},
};

fn loadRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8, options: ElfRunOptions) !u64 {
    var state = ElfState.init(allocator);
    defer state.deinit();

    try state.loadElf(elf_bytes);

    var local_symbols = elf_loader.collectSymbols(allocator, elf_bytes) catch |err| blk: {
        log.warn("local symbols unavailable: {s}", .{@errorName(err)});
        const empty_symbols: std.ArrayList(elf_loader.Symbol) = .empty;
        break :blk empty_symbols;
    };
    defer local_symbols.deinit(allocator);
    state.local_symbols = local_symbols.items;

    var dynamic_relocations = elf_loader.collectDynamicRelocations(allocator, elf_bytes) catch |err| blk: {
        log.warn("dynamic relocations unavailable: {s}", .{@errorName(err)});
        const empty_relocations: std.ArrayList(elf_loader.DynamicRelocation) = .empty;
        break :blk empty_relocations;
    };
    defer dynamic_relocations.deinit(allocator);
    state.dynamic_relocations = dynamic_relocations.items;

    var init_functions = elf_loader.collectInitArray(allocator, elf_bytes) catch |err| blk: {
        log.warn("ELF init array unavailable: {s}", .{@errorName(err)});
        const empty_init: std.ArrayList(u64) = .empty;
        break :blk empty_init;
    };
    defer init_functions.deinit(allocator);
    state.init_functions = init_functions.items;

    var result_symbols: std.ArrayList(result_dump.DumpSymbol) = .empty;
    defer result_dump.deinitSymbols(allocator, &result_symbols);
    if (options.dump_results) {
        result_symbols = result_dump.collect(allocator, &state, elf_bytes, options.source_text) catch |err| blk: {
            log.warn("result symbols unavailable: {s}", .{@errorName(err)});
            break :blk .empty;
        };
    }

    try x64_linux_runtime.setupInitialStack(&state, options.argv);

    state.run();

    if (options.dump_results) {
        result_dump.dump(allocator, &state, result_symbols.items, .{
            .dump_all_results = options.dump_all_results,
            .source_text = options.source_text,
        }) catch |err| {
            log.warn("result dump skipped: {s}", .{@errorName(err)});
        };
    }

    return state.exit_code;
}

/// CLI entry point: `elf_processor <path-to-elf>`
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        log.err("usage: elf_processor [--dump-results] [--dump-all-results] <elf-path>", .{});
        return;
    }

    var arg_index: usize = 1;
    var dump_results = envFlag("ROSETTE_ELF_DUMP_RESULTS");
    var dump_all_results = envFlag("ROSETTE_ELF_DUMP_ALL") or envFlag("ROSETTE_ELF_DUMP_ALL_RESULTS");
    while (arg_index < args.len and std.mem.startsWith(u8, args[arg_index], "--")) : (arg_index += 1) {
        if (std.mem.eql(u8, args[arg_index], "--dump-results")) {
            dump_results = true;
        } else if (std.mem.eql(u8, args[arg_index], "--dump-all-results")) {
            dump_results = true;
            dump_all_results = true;
        } else {
            log.err("unknown option: {s}", .{args[arg_index]});
            std.process.exit(126);
        }
    }
    if (arg_index >= args.len) {
        log.err("usage: elf_processor [--dump-results] [--dump-all-results] <elf-path>", .{});
        std.process.exit(126);
    }
    const elf_path = args[arg_index];

    const elf_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, elf_path, init.arena.allocator(), .unlimited);
    const source_text = if (dump_results)
        try readSiblingAsmSource(init.io, init.arena.allocator(), elf_path)
    else
        null;

    const exit_code = loadRunElf(init.arena.allocator(), elf_bytes, .{
        .dump_results = dump_results,
        .dump_all_results = dump_all_results,
        .source_text = source_text,
        .argv = args[arg_index..],
    }) catch |err| {
        log.err("failed to run ELF: {s}", .{@errorName(err)});
        std.process.exit(126);
    };

    if (envFlag("ROSETTE_ELF_VERBOSE")) {
        log.info("exit_code={d}", .{exit_code});
    }
    std.process.exit(@as(u8, @truncate(exit_code)));
}

fn envFlag(name: [:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.sliceTo(raw, 0);
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, "0")) return false;
    if (std.ascii.eqlIgnoreCase(value, "false")) return false;
    if (std.ascii.eqlIgnoreCase(value, "no")) return false;
    return true;
}

/// True only when the variable is set *and* set to a false value.  A default
/// -on diagnostic uses this so an unset variable keeps the default rather
/// than reading as "off".
fn envPresentAndFalse(name: [:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.sliceTo(raw, 0);
    if (value.len == 0) return false;
    return std.mem.eql(u8, value, "0") or
        std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.ascii.eqlIgnoreCase(value, "off");
}

fn envU64(name: [:0]const u8) ?u64 {
    const raw = std.c.getenv(name) orelse return null;
    return parseEnvU64(std.mem.sliceTo(raw, 0));
}

fn readSiblingAsmSource(io: std.Io, allocator: std.mem.Allocator, elf_path: []const u8) !?[]const u8 {
    const direct = try std.mem.concat(allocator, u8, &.{ elf_path, ".asm" });
    if (std.Io.Dir.cwd().readFileAlloc(io, direct, allocator, .limited(512 * 1024))) |source| return source else |_| {}

    const dir = std.fs.path.dirname(elf_path) orelse ".";
    const base = std.fs.path.basename(elf_path);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
        const stem_path = try std.fs.path.join(allocator, &.{ dir, base[0..dot] });
        const candidate = try std.mem.concat(allocator, u8, &.{ stem_path, ".asm" });
        if (std.Io.Dir.cwd().readFileAlloc(io, candidate, allocator, .limited(512 * 1024))) |source| return source else |_| {}
    }

    return null;
}

// ─── Tests ───

test "decode 0x66 0xB8 (mov ax, imm16)" {
    const bytes = [_]u8{ 0x66, 0xB8, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits16, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
}

test "decode 0xB8 (mov eax, imm32)" {
    const bytes = [_]u8{ 0xB8, 0x78, 0x56, 0x34, 0x12 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(@as(u64, 0x12345678), d.imm);
}

test "decode 0x48 0xB8 (mov rax, imm64)" {
    const bytes = [_]u8{ 0x48, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
}

test "decode 0x8A 0x04 0x25 <addr> (mov al, byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0x8A, 0x04, 0x25, 0x81, 0x26, 0x01, 0x01 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg8_mem8, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(@as(u64, 0x01012681), d.addr);
}

test "decode 0x88 0x04 0x25 <addr> (mov byte [abs], al)" {
    var bytes: [7]u8 = [_]u8{ 0x88, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_mem8_reg8, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);
}

test "decode 0x02 0x04 0x25 (add al, byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0x02, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.add_reg8_mem8, d.op);
}

test "decode 0xF6 0x24 0x25 (mul byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0xF6, 0x24, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_mem8, d.op);
}

test "decode 0xF7 0xE3 (mul ebx)" {
    var bytes: [2]u8 = [_]u8{ 0xF7, 0xE3 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_reg32, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.src_reg);
}

test "decode 0x48 0xF7 0xE3 (mul rbx)" {
    var bytes: [3]u8 = [_]u8{ 0x48, 0xF7, 0xE3 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_reg64, d.op);
}

test "decode 0x99 (cdq)" {
    var bytes: [1]u8 = [_]u8{0x99};
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cdq, d.op);
}

test "decode 0x48 0x99 (cqo)" {
    var bytes: [2]u8 = [_]u8{ 0x48, 0x99 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cqo, d.op);
}

test "decode 0x98 sign-extension variants" {
    try testing.expectEqual(Op.cwde, decodeInsn(&[_]u8{0x98}).op);
    try testing.expectEqual(Op.cbw, decodeInsn(&[_]u8{ 0x66, 0x98 }).op);
    try testing.expectEqual(Op.cdqe, decodeInsn(&[_]u8{ 0x48, 0x98 }).op);
}

test "decode 0x0F 0xB7 (movzx eax, word [abs])" {
    var bytes: [8]u8 = [_]u8{ 0x0F, 0xB7, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movzx_reg32_mem16, d.op);
}

test "decode 0x0F 0xBF (movsx eax, word [abs])" {
    var bytes: [8]u8 = [_]u8{ 0x0F, 0xBF, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movsx_reg32_mem16, d.op);
}

test "decode 0x0F 0x05 (syscall)" {
    var bytes: [2]u8 = [_]u8{ 0x0F, 0x05 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.syscall, d.op);
}

test "execute gettid syscall shim" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = SYS_gettid;
    state.execute(.{ .op = .syscall, .len = 2 });
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expect(!state.terminated);
}

test "decode call ret and extended stack forms" {
    var call_bytes: [5]u8 = [_]u8{ 0xE8, 0x64, 0x01, 0x00, 0x00 };
    var d = decodeInsn(&call_bytes);
    try testing.expectEqual(Op.call_rel32, d.op);
    try testing.expectEqual(@as(u8, 5), d.len);
    try testing.expectEqual(@as(u64, 0x164), d.imm);

    d = decodeInsn(&[_]u8{0xC3});
    try testing.expectEqual(Op.ret, d.op);

    d = decodeInsn(&[_]u8{ 0x41, 0x54 });
    try testing.expectEqual(Op.push_reg, d.op);
    try testing.expectEqual(RegId.r12b_r12w_r12d_r12, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x41, 0x5F });
    try testing.expectEqual(Op.pop_reg, d.op);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.dst_reg);
}

test "decode REX-aware arithmetic and move-extension registers" {
    var d = decodeInsn(&[_]u8{ 0x45, 0x6B, 0xFF, 0x04 });
    try testing.expectEqual(Op.imul_reg32_reg32_imm8, d.op);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.dst_reg);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x49, 0x69, 0xCD, 0xD0, 0x00, 0x00, 0x00 });
    try testing.expectEqual(Op.imul_reg64_reg64_imm32, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(@as(u8, 7), d.len);
    try testing.expectEqual(@as(u64, 0xD0), d.imm);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.dst_reg);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.r13b_r13w_r13d_r13, .bits64, 1);
    state.execute(d);
    try testing.expectEqual(@as(u64, 0xD0), state.regs.rcx);

    d = decodeInsn(&[_]u8{ 0x41, 0xF7, 0xFD });
    try testing.expectEqual(Op.idiv_reg32, d.op);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x49, 0x0F, 0xAF, 0xC5 });
    try testing.expectEqual(Op.imul_reg64_reg64, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x4C, 0x0F, 0xB6, 0xEE });
    try testing.expectEqual(Op.movzx_reg32_mem8, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.dst_reg);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.src_reg);
    try testing.expect(d.is_reg_form);
}

test "decode and execute shlq cl r14" {
    const d = decodeInsn(&[_]u8{ 0x49, 0xD3, 0xE6 });
    try testing.expectEqual(Op.shl_reg_cl, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r14b_r14w_r14d_r14, d.dst_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.r14b_r14w_r14d_r14, .bits64, 1);
    state.setReg(.cl_cx_ecx_rcx, .bits8, 7);
    state.execute(d);

    try testing.expectEqual(@as(u64, 128), state.regs.r14);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
    try testing.expect((state.regs.rflags & RFL_SF) == 0);
}

test "decode and execute LAHF and SAHF" {
    const lahf = decodeInsn(&[_]u8{0x9F});
    try testing.expectEqual(Op.lahf, lahf.op);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0xAABB_CCDD_EEFF_0011;
    state.regs.rflags = RFL_CF | RFL_AF | RFL_SF | RFL_OF | (1 << 10) | 0x02;
    state.execute(lahf);
    try testing.expectEqual(@as(u8, 0x93), @as(u8, @truncate(state.regs.rax >> 8)));
    try testing.expectEqual(@as(u64, 0xAABB_CCDD_EEFF_9311), state.regs.rax);

    const sahf = decodeInsn(&[_]u8{0x9E});
    try testing.expectEqual(Op.sahf, sahf.op);
    state.regs.rax = (state.regs.rax & 0xFFFF_FFFF_FFFF_00FF) | (@as(u64, 0x44) << 8);
    state.execute(sahf);
    try testing.expectEqual(
        RFL_ZF | RFL_PF | RFL_OF | (1 << 10) | 0x02,
        state.regs.rflags,
    );
}

test "decode and execute shlq imm r9" {
    const d = decodeInsn(&[_]u8{ 0x49, 0xC1, 0xE1, 0x04 });
    try testing.expectEqual(Op.shl_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r9b_r9w_r9d_r9, d.dst_reg);
    try testing.expectEqual(@as(u64, 4), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.r9b_r9w_r9d_r9, .bits64, 3);
    state.execute(d);

    try testing.expectEqual(@as(u64, 48), state.regs.r9);
}

test "decode and execute shr implicit one ecx" {
    const d = decodeInsn(&[_]u8{ 0xD1, 0xE9 });
    try testing.expectEqual(Op.shr_reg_imm, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.dst_reg);
    try testing.expectEqual(@as(u64, 1), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.cl_cx_ecx_rcx, .bits32, 8);
    state.execute(d);

    try testing.expectEqual(@as(u64, 4), state.regs.rcx);
}

test "CS218 short backward jump consumes its displacement byte" {
    const d = decodeInsn(&[_]u8{ 0xEB, 0xDF });
    try testing.expectEqual(Op.jmp_rel8, d.op);
    try testing.expectEqual(@as(u8, 2), d.len);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -33))), d.imm);
}

test "decode and execute sarq imm rsi" {
    const d = decodeInsn(&[_]u8{ 0x48, 0xC1, 0xFE, 0x03 });
    try testing.expectEqual(Op.sar_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.dst_reg);
    try testing.expectEqual(@as(u64, 3), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.dh_si_esi_rsi, .bits64, @as(u64, @bitCast(@as(i64, -16))));
    state.execute(d);

    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), state.regs.rsi);
    try testing.expect((state.regs.rflags & RFL_SF) != 0);
}

test "decode and execute adcq imm rbx" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x83, 0xD3, 0x00 });
    try testing.expectEqual(Op.adc_reg64_imm8, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.bl_bx_ebx_rbx, .bits64, 5);
    state.regs.rflags |= RFL_CF;
    state.execute(d);

    try testing.expectEqual(@as(u64, 6), state.regs.rbx);
    try testing.expect((state.regs.rflags & RFL_CF) == 0);
}

test "decode and execute negl esi" {
    const d = decodeInsn(&[_]u8{ 0xF7, 0xDE });
    try testing.expectEqual(Op.neg_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.dst_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.dh_si_esi_rsi, .bits32, 5);
    state.execute(d);

    try testing.expectEqual(@as(u64, 0xFFFF_FFFB), state.regs.rsi);
    try testing.expect((state.regs.rflags & RFL_CF) != 0);
    try testing.expect((state.regs.rflags & RFL_SF) != 0);
}

test "decode and execute cmovae rbx rcx" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x0F, 0x43, 0xD9 });
    try testing.expectEqual(Op.cmovcc_reg_reg, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.src_reg);
    try testing.expectEqual(Cond.ae, d.cond);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.bl_bx_ebx_rbx, .bits64, 0);
    state.setReg(.cl_cx_ecx_rcx, .bits64, 42);
    state.regs.rflags &= ~RFL_CF;
    state.execute(d);
    try testing.expectEqual(@as(u64, 42), state.regs.rbx);
}

test "decode lock add byte rip-relative immediate" {
    const d = decodeInsn(&[_]u8{ 0xF0, 0x80, 0x05, 0x28, 0x14, 0x17, 0x00, 0x01 });
    try testing.expectEqual(Op.add_mem8_imm8, d.op);
    try testing.expectEqual(Size.bits8, d.size);
    try testing.expect(d.rip_relative);
    try testing.expectEqual(@as(u64, 0x171428), d.addr);
    try testing.expectEqual(@as(u64, 1), d.imm);
}

test "decode and execute addb immediate to dl" {
    const d = decodeInsn(&[_]u8{ 0x80, 0xC2, 0x0A });
    try testing.expectEqual(Op.add_reg8_imm8, d.op);
    try testing.expectEqual(Size.bits8, d.size);
    try testing.expectEqual(RegId.dl_dx_edx_rdx, d.dst_reg);
    try testing.expectEqual(@as(u64, 10), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rdx = 0x1234_5605;
    state.execute(d);

    try testing.expectEqual(@as(u64, 0x1234_560f), state.regs.rdx);
}

test "decode and execute orl immediate SIB memory" {
    const d = decodeInsn(&[_]u8{ 0x81, 0x4C, 0x31, 0x08, 0x00, 0x20, 0x00, 0x00 });
    try testing.expectEqual(Op.or_mem32_imm32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expect(d.sib_has_base);
    try testing.expect(d.sib_has_index);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.sib_base_reg);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.sib_index_reg);
    try testing.expectEqual(@as(u64, 8), d.addr);
    try testing.expectEqual(@as(u64, 0x2000), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rcx = 8;
    state.regs.rsi = MEM_BASE;
    var resolved = d;
    state.sibAddr(&resolved);
    state.write32(resolved.addr, 0x40);
    state.execute(resolved);

    try testing.expectEqual(@as(u32, 0x2040), state.read32(resolved.addr));
}

test "decode and execute sbb eax eax carry mask" {
    const d = decodeInsn(&[_]u8{ 0x19, 0xC0 });
    try testing.expectEqual(Op.sbb_reg32_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0;
    state.regs.rflags |= RFL_CF;
    state.execute(d);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.rax);
}

test "decode lock cmpxchg memory and setne memory" {
    var d = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xB1, 0x0D, 0x8C, 0x07, 0x0C, 0x00 });
    try testing.expectEqual(Op.cmpxchg_mem32_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.src_reg);
    try testing.expect(d.rip_relative);

    d = decodeInsn(&[_]u8{ 0x0F, 0x95, 0x45, 0xC8 });
    try testing.expectEqual(Op.setcc_mem8, d.op);
    try testing.expectEqual(Cond.ne, d.cond);
    try testing.expect(d.sib_has_base);
    try testing.expectEqual(RegId.ch_bp_ebp_rbp, d.sib_base_reg);
}

test "decode lock cmpxchg byte and word atomics" {
    const byte_memory = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xB0, 0x11 });
    try testing.expectEqual(Op.cmpxchg_mem8_reg8, byte_memory.op);
    try testing.expectEqual(Size.bits8, byte_memory.size);
    try testing.expectEqual(RegId.dl_dx_edx_rdx, byte_memory.src_reg);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, byte_memory.sib_base_reg);

    const word_memory = decodeInsn(&[_]u8{ 0xF0, 0x66, 0x0F, 0xB1, 0x11 });
    try testing.expectEqual(Op.cmpxchg_mem16_reg16, word_memory.op);
    try testing.expectEqual(Size.bits16, word_memory.size);

    const byte_register = decodeInsn(&[_]u8{ 0x0F, 0xB0, 0xD1 });
    try testing.expectEqual(Op.cmpxchg_reg8_reg8, byte_register.op);
    try testing.expect(byte_register.is_reg_form);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, byte_register.dst_reg);
}

test "execute cmpxchg memory success path" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const addr = MEM_BASE;
    state.write32(addr, 0);
    state.setReg(.al_ax_eax_rax, .bits32, 0);
    state.setReg(.cl_cx_ecx_rcx, .bits32, 1);
    state.execute(.{
        .op = .cmpxchg_mem32_reg32,
        .size = .bits32,
        .src_reg = .cl_cx_ecx_rcx,
        .addr = addr,
    });
    try testing.expectEqual(@as(u32, 1), state.read32(addr));
    try testing.expect((state.regs.rflags & RFL_ZF) != 0);
}

test "decode and execute xchg memory eax" {
    const d = decodeInsn(&[_]u8{ 0x87, 0x07 });
    try testing.expectEqual(Op.xchg_mem32_reg32, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);
    try testing.expect(d.sib_has_base);
    try testing.expectEqual(RegId.bh_di_edi_rdi, d.sib_base_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const addr = MEM_BASE;
    state.write32(addr, 2);
    state.setReg(.al_ax_eax_rax, .bits32, 7);
    state.execute(.{
        .op = .xchg_mem32_reg32,
        .size = .bits32,
        .src_reg = .al_ax_eax_rax,
        .addr = addr,
    });
    try testing.expectEqual(@as(u32, 7), state.read32(addr));
    try testing.expectEqual(@as(u64, 2), state.regs.rax);
}

test "decode xchg memory rax preserves 64-bit operand size" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x87, 0x07 });
    try testing.expectEqual(Op.xchg_mem64_reg64, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);
}

test "decode and execute lock xadd memory ecx" {
    const d = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xC1, 0x0D, 0x46, 0xAA, 0x0B, 0x00 });
    try testing.expectEqual(Op.xadd_mem32_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.src_reg);
    try testing.expect(d.rip_relative);
    try testing.expectEqual(@as(u64, 0x0BAA46), d.addr);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const addr = MEM_BASE;
    state.write32(addr, 41);
    state.setReg(.cl_cx_ecx_rcx, .bits32, 1);
    state.execute(.{
        .op = .xadd_mem32_reg32,
        .size = .bits32,
        .src_reg = .cl_cx_ecx_rcx,
        .addr = addr,
    });
    try testing.expectEqual(@as(u32, 42), state.read32(addr));
    try testing.expectEqual(@as(u64, 41), state.regs.rcx);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
}

test "decode and execute xorps zero then movaps store" {
    const zero = decodeInsn(&[_]u8{ 0x0F, 0x57, 0xC0 });
    try testing.expectEqual(Op.xorps_xmm_xmm, zero.op);
    try testing.expectEqual(@as(u8, 0), zero.xmm_dst);
    try testing.expectEqual(@as(u8, 0), zero.xmm_src);

    const load_unaligned = decodeInsn(&[_]u8{ 0x0F, 0x10, 0x06 });
    try testing.expectEqual(Op.movups_xmm_mem, load_unaligned.op);
    try testing.expect(load_unaligned.sib_has_base);
    try testing.expectEqual(RegId.dh_si_esi_rsi, load_unaligned.sib_base_reg);

    const store = decodeInsn(&[_]u8{ 0x0F, 0x29, 0x43, 0x10 });
    try testing.expectEqual(Op.movaps_mem_xmm, store.op);
    try testing.expect(store.sib_has_base);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, store.sib_base_reg);
    try testing.expectEqual(@as(u64, 0x10), store.addr);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.xmm[0] = [_]u8{0xAA} ** 16;
    state.execute(zero);
    state.execute(.{
        .op = .movaps_mem_xmm,
        .addr = MEM_BASE,
        .xmm_src = 0,
    });
    const stored = state.readMem128(MEM_BASE);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), stored[0..]);
}

test "decode and execute shared bit scan instructions" {
    const bsr = decodeInsn(&[_]u8{ 0x48, 0x0F, 0xBD, 0xC0 });
    try testing.expectEqual(Op.bsr_reg_reg, bsr.op);
    try testing.expectEqual(Size.bits64, bsr.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, bsr.dst_reg);
    try testing.expectEqual(RegId.al_ax_eax_rax, bsr.src_reg);
    try testing.expectEqual(@as(u8, 4), bsr.len);

    const lzcnt = decodeInsn(&[_]u8{ 0xF3, 0x48, 0x0F, 0xBD, 0xC3 });
    try testing.expectEqual(Op.lzcnt_reg_reg, lzcnt.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, lzcnt.src_reg);
    try testing.expectEqual(@as(u8, 5), lzcnt.len);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0x8000_0000_0000_0000;
    state.execute(bsr);
    try testing.expectEqual(@as(u64, 63), state.regs.rax);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
}

test "decode and execute shared population count" {
    const exact_fbo_failure = decodeInsn(&[_]u8{ 0xF3, 0x0F, 0xB8, 0xC0, 0x5D, 0xC3 });
    try testing.expectEqual(Op.popcnt_reg_reg, exact_fbo_failure.op);
    try testing.expectEqual(Size.bits32, exact_fbo_failure.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, exact_fbo_failure.dst_reg);
    try testing.expectEqual(RegId.al_ax_eax_rax, exact_fbo_failure.src_reg);
    try testing.expectEqual(@as(u8, 4), exact_fbo_failure.len);

    const memory_16 = decodeInsn(&[_]u8{ 0x66, 0xF3, 0x0F, 0xB8, 0x48, 0x08 });
    try testing.expectEqual(Op.popcnt_reg_mem, memory_16.op);
    try testing.expectEqual(Size.bits16, memory_16.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, memory_16.dst_reg);
    try testing.expectEqual(@as(u64, 8), memory_16.addr);

    try testing.expectEqual(Op.invalid, decodeInsn(&[_]u8{ 0x0F, 0xB8, 0xC0 }).op);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0xFFFF_FFFF_0000_000B;
    state.regs.rflags = RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF | (1 << 10);
    state.execute(exact_fbo_failure);
    try testing.expectEqual(@as(u64, 3), state.regs.rax);
    try testing.expectEqual(@as(u32, 1 << 10), state.regs.rflags & (RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF | (1 << 10)));
}

test "decode and execute shared byte swap" {
    const decoded = decodeInsn(&[_]u8{ 0x0F, 0xC8 });
    try testing.expectEqual(Op.bswap_reg, decoded.op);
    try testing.expectEqual(Size.bits32, decoded.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, decoded.dst_reg);
    try testing.expectEqual(@as(u8, 2), decoded.len);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0xFFFF_FFFF_1234_5678;
    state.execute(decoded);
    try testing.expectEqual(@as(u64, 0x7856_3412), state.regs.rax);
}

test "decode 0x48 0x63 0xDB (movsxd rbx, ebx)" {
    var bytes: [3]u8 = [_]u8{ 0x48, 0x63, 0xDB };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movsxd_reg64_reg32, d.op);
}

test "decode movsxd r64 memory SIB form" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x63, 0x04, 0x81 });
    try testing.expectEqual(Op.movsxd_reg64_mem32, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expect(d.sib_has_index);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.sib_index_reg);
    try testing.expect(d.sib_has_base);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.sib_base_reg);
    try testing.expectEqual(@as(u2, 2), d.sib_scale);
}

test "decode 0x48 0xC7 0xC3 (mov rbx, imm32)" {
    var bytes: [7]u8 = [_]u8{ 0x48, 0xC7, 0xC3, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);
}

test "decode 0x48 0xC7 memory immediate sign extends to 64 bits" {
    const d = decodeInsn(&[_]u8{ 0x48, 0xC7, 0x00, 0xFF, 0xFF, 0xFF, 0xFF });
    try testing.expectEqual(Op.mov_mem64_imm32, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(@as(u64, std.math.maxInt(u64)), d.imm);
}

test "decode 0x66 0x99 (cwd)" {
    var bytes: [2]u8 = [_]u8{ 0x66, 0x99 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cwd, d.op);
}

test "mul byte [mem] and check result" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // Place operands: bNum1=34 at vaddr 0x100267c, bNum3=19 at 0x100267e
    state.write8(0x100267c, 34); // bNum1
    state.write8(0x100267e, 19); // bNum3

    // Set RIP and decode "mov al, byte [bNum1]" + "mul byte [bNum3]" + "mov word [result], ax"
    state.regs.rip = 0x1001160;
    state.regs.rax = 0;

    // Manually execute mov al, [bNum1]
    state.regs.rip = 0x1001160;
    var decoded = decodeInsn(&[_]u8{ 0x8A, 0x04, 0x25, 0x7C, 0x26, 0x00, 0x01 });
    try testing.expectEqual(Op.mov_reg8_mem8, decoded.op);
    state.execute(decoded);
    try testing.expectEqual(@as(u64, 34), state.regs.rax & 0xFF);

    // Execute mul byte [bNum3]
    decoded = decodeInsn(&[_]u8{ 0xF6, 0x24, 0x25, 0x7E, 0x26, 0x00, 0x01 });
    try testing.expectEqual(Op.mul_mem8, decoded.op);
    state.execute(decoded);
    // 34 * 19 = 646 = 0x286
    try testing.expectEqual(@as(u64, 0x286), state.regs.rax & 0xFFFF);
}

test "CS218 AST03 base-12 digit sequence decodes and executes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.regs.rdx = '9';
    state.regs.rbx = 0;

    const copy_digit = decodeInsn(&[_]u8{ 0x88, 0xD3 }); // mov bl, dl
    try testing.expectEqual(Op.mov_reg8_reg8, copy_digit.op);
    state.execute(copy_digit);

    const normalize_digit = decodeInsn(&[_]u8{ 0x80, 0xEB, 0x30 }); // sub bl, '0'
    try testing.expectEqual(Op.sub_reg8_imm8, normalize_digit.op);
    state.execute(normalize_digit);

    try testing.expectEqual(@as(u64, 9), state.regs.rbx);
}

test "shared MOV layer executes reverse direction and legacy high bytes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.regs.rdx = 0x5A;
    const reverse = decodeInsn(&[_]u8{ 0x8A, 0xDA }); // mov bl, dl
    try testing.expectEqual(Op.mov_reg8_reg8, reverse.op);
    state.execute(reverse);
    try testing.expectEqual(@as(u64, 0x5A), state.regs.rbx);

    state.regs.rax = 0x1234;
    const high_immediate = decodeInsn(&[_]u8{ 0xB4, 0xAB }); // mov ah, 0xab
    try testing.expect(high_immediate.dst_high8);
    state.execute(high_immediate);
    try testing.expectEqual(@as(u64, 0xAB34), state.regs.rax);

    state.regs.rsp = 0xFF00;
    const rex_low_immediate = decodeInsn(&[_]u8{ 0x40, 0xB4, 0x7C }); // mov spl, 0x7c
    try testing.expect(!rex_low_immediate.dst_high8);
    state.execute(rex_low_immediate);
    try testing.expectEqual(@as(u64, 0xFF7C), state.regs.rsp);
}

test "group-one byte immediate preserves legacy high-byte register aliases" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.regs.rax = 0xABFF;
    state.regs.rsp = 0x143FE42F8;
    const and_ah = decodeInsn(&[_]u8{ 0x80, 0xE4, 0x45 }); // and ah, 0x45
    try testing.expectEqual(Op.and_reg8_imm8, and_ah.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, and_ah.dst_reg);
    try testing.expect(and_ah.dst_high8);
    state.execute(and_ah);

    try testing.expectEqual(@as(u64, 0x01FF), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x143FE42F8), state.regs.rsp);
}

test "FS override participates in decoded long-mode memory addresses" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.regs.rip = MEM_BASE + 0x1000;
    state.regs.rax = 0x200;
    state.regs.segments.fs.base = MEM_BASE;
    state.write8(state.regs.rip, 0x64);
    state.write8(state.regs.rip + 1, 0x8A);
    state.write8(state.regs.rip + 2, 0x00); // mov al, fs:[rax]
    state.write8(MEM_BASE + 0x200, 0x7A);

    const decoded = state.decodeAt() orelse return error.ExpectedInstruction;
    try testing.expectEqual(x64_decoder.Segment.fs, decoded.segment);
    try testing.expectEqual(@as(u64, MEM_BASE + 0x200), decoded.addr);
    state.execute(decoded);
    try testing.expectEqual(@as(u64, 0x27A), state.regs.rax);
}

test "arch_prctl sets and reads architectural FS and GS bases" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.invokeLinuxSyscall(SYS_arch_prctl, 0x1002, MEM_BASE + 0x5000, 0, 0, 0, 0);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u64, MEM_BASE + 0x5000), state.regs.segments.fs.base);

    const output = MEM_BASE + 0x80;
    state.invokeLinuxSyscall(SYS_arch_prctl, 0x1003, output, 0, 0, 0, 0);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u64, MEM_BASE + 0x5000), state.read64(output));
    try testing.expect(!state.terminated);
    try testing.expect(!state.faulted);
}

test "CS218 file input syscall 2 is handled without terminating the guest" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const path_addr = MEM_BASE;
    const missing_path = "rosette-cs218-file-that-does-not-exist.txt\x00";
    const path_off: usize = @intCast(path_addr - state.mem_base);
    @memcpy(state.mem[path_off..][0..missing_path.len], missing_path);

    state.invokeLinuxSyscall(SYS_open, path_addr, 0, 0, 0, 0, 0);

    try testing.expect(!state.terminated);
    try testing.expect(!state.faulted);
    try testing.expectEqual(x64_syscalls.errnoValue(.no_entry), state.regs.rax);
}

test "cmp reg32 imm8 treats negative 32-bit values as signed negative" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, -2588))));
    state.execute(.{
        .op = .cmp_reg32_imm8,
        .dst_reg = .al_ax_eax_rax,
        .imm = 0,
        .len = 3,
    });

    try testing.expect((state.regs.rflags & RFL_SF) != 0);
    try testing.expect((state.regs.rflags & RFL_OF) == 0);
    try testing.expect(ElfState.evalCond(state.regs.rflags, .l));
    try testing.expect(!ElfState.evalCond(state.regs.rflags, .ge));
}

test "accumulator immediate operations use scalar Group-1 semantics" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.setReg(.al_ax_eax_rax, .bits32, 0x4C);
    state.execute(.{
        .op = .and_accum_imm,
        .size = .bits32,
        .dst_reg = .al_ax_eax_rax,
        .imm = 0x1FF800,
        .len = 5,
    });
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expect((state.regs.rflags & RFL_ZF) != 0);

    state.setReg(.al_ax_eax_rax, .bits32, 1);
    state.execute(.{
        .op = .cmp_accum_imm,
        .size = .bits32,
        .dst_reg = .al_ax_eax_rax,
        .imm = 0,
        .len = 5,
    });
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
}

test "VEX arithmetic uses NDS operands and advances the guest RIP" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const write_f32 = struct {
        fn at(vector: *[16]u8, lane: usize, value: f32) void {
            std.mem.writeInt(u32, vector[lane * 4 ..][0..4], @bitCast(value), .little);
        }
    }.at;
    for (0..4) |lane| {
        write_f32(&state.xmm[0], lane, @floatFromInt(lane + 1));
        write_f32(&state.xmm[1], lane, @floatFromInt((lane + 1) * 10));
    }
    state.regs.rip = MEM_BASE + 0x400;
    const start = state.regs.rip;
    state.execute(.{
        .op = .vsubps,
        .xmm_dst = 2,
        .xmm_src = 0,
        .xmm_src2 = 1,
        .is_reg_form = true,
        .len = 4,
    });

    try testing.expectEqual(start + 4, state.regs.rip);
    try testing.expectEqual(@as(f32, -9), @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[2][0..4], .little))));
    try testing.expectEqual(@as(f32, -36), @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[2][12..16], .little))));
    try testing.expect(!state.terminated);
}

test "VEX FMA suffix selects the architectural accumulator" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const write_f32 = struct {
        fn at(vector: *[16]u8, value: f32) void {
            std.mem.writeInt(u32, vector[0..4], @bitCast(value), .little);
        }
    }.at;
    write_f32(&state.xmm[0], 2);
    write_f32(&state.xmm[1], 3);
    write_f32(&state.xmm[2], 4);
    state.regs.rip = MEM_BASE + 0x500;

    state.execute(.{
        .op = .vfmadd132ps,
        .xmm_dst = 2,
        .xmm_src = 0,
        .xmm_src2 = 1,
        .is_reg_form = true,
        .len = 5,
    });

    // VFMADD132PS: dst = (dst * SRC2) + SRC1 = (4 * 3) + 2.
    try testing.expectEqual(@as(f32, 14), @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[2][0..4], .little))));
    try testing.expectEqual(MEM_BASE + 0x505, state.regs.rip);
    try testing.expect(!state.terminated);
}

test "unsupported vector operations terminate instead of changing flags" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rip = MEM_BASE + 0x600;
    state.execute(.{ .op = .vscalefps, .len = 6 });
    try testing.expect(state.terminated);
    try testing.expect(state.faulted);
    try testing.expectEqual(exit_diagnostics.TerminationReason.unimplemented_instruction, state.termination_reason);
    try testing.expectEqual(MEM_BASE + 0x600, state.regs.rip);
}

test "Windows graphics ledger proves the complete logical frame path" {
    var graphics = WindowsGraphicsState{};
    try testing.expect(graphics.ensureWindow(1920, 1080, "Xenia Canary"));
    try testing.expect(graphics.showWindow());
    try testing.expect(graphics.noteCreateInstance(true));
    try testing.expect(graphics.noteCreateSurface(true));
    try testing.expect(graphics.noteCreateDevice(true));
    try testing.expect(graphics.noteGetQueue(true));
    try testing.expect(graphics.noteCreateSwapchain(true));
    try testing.expect(graphics.noteSwapchainImages(true));
    try testing.expect(graphics.noteAcquire(true));
    graphics.noteCommand("vkCmdClearColorImage");
    try testing.expect(graphics.noteQueueSubmit(true));
    try testing.expect(graphics.notePresent(true));

    const snapshot = graphics.snapshot();
    try testing.expect(snapshot.contractReady());
    try testing.expect(snapshot.guest_present_observed);
    try testing.expect(!snapshot.nativeWindowReady());
    try testing.expectEqual(WindowsGraphicsPhase.present_ready, snapshot.phase);
    try testing.expectEqual(@as(u64, 0), snapshot.ordering_violations);
}

test "Windows graphics ledger rejects a present before its prerequisites" {
    var graphics = WindowsGraphicsState{};
    try testing.expect(!graphics.notePresent(true));
    const snapshot = graphics.snapshot();
    try testing.expectEqual(WindowsGraphicsPhase.failed, snapshot.phase);
    try testing.expectEqual(@as(u64, 1), snapshot.ordering_violations);
    try testing.expect(!snapshot.contractReady());
    try testing.expectEqualStrings("vkQueuePresentKHR: queue, swapchain, and frame resources are required", std.mem.sliceTo(&snapshot.last_failure, 0));
}

test "Windows graphics ledger never forwards Win32 default dimensions to the host" {
    var graphics = WindowsGraphicsState{};
    try testing.expect(graphics.ensureWindow(WINDOWS_CW_USEDEFAULT, WINDOWS_CW_USEDEFAULT, "message-safe fallback"));
    try testing.expectEqual(WINDOWS_DEFAULT_WIDTH, graphics.window_width);
    try testing.expectEqual(WINDOWS_DEFAULT_HEIGHT, graphics.window_height);

    try testing.expect(graphics.ensureWindow(WINDOWS_MAX_DIMENSION + 1, 0, "bounded fallback"));
    try testing.expectEqual(WINDOWS_DEFAULT_WIDTH, graphics.window_width);
    try testing.expectEqual(WINDOWS_DEFAULT_HEIGHT, graphics.window_height);
}

const NativeGraphicsTestHarness = struct {
    starts: u64 = 0,
    stage: u32 = 10,
    frames: u64 = 0,
};

fn testNativePresenterStart(context: ?*anyopaque, _: u32, _: u32) callconv(.c) c_int {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.starts +|= 1;
    return 1;
}

fn testNativePresenterStage(context: ?*anyopaque) callconv(.c) u32 {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    return harness.stage;
}

fn testNativePresenterReady(_: ?*anyopaque) callconv(.c) c_int {
    return 1;
}

fn testNativePresenterDiagnostic(context: ?*anyopaque, _: u64, _: u32, _: u32, _: u32) callconv(.c) u64 {
    const harness: *NativeGraphicsTestHarness = @ptrCast(@alignCast(context.?));
    harness.frames +|= 1;
    return harness.frames;
}

test "Windows graphics ledger keeps native diagnostics separate from guest output" {
    var harness = NativeGraphicsTestHarness{};
    var graphics = WindowsGraphicsState{
        .hooks = .{
            .native_context = &harness,
            .native_presenter_start = testNativePresenterStart,
            .native_presenter_stage = testNativePresenterStage,
            .native_presenter_is_ready = testNativePresenterReady,
            .native_presenter_present_diagnostic = testNativePresenterDiagnostic,
        },
    };
    try testing.expect(graphics.ensureWindow(1280, 720, "native diagnostic"));
    try testing.expect(graphics.noteCreateInstance(true));
    try testing.expect(graphics.noteCreateSurface(true));
    try testing.expectEqual(@as(u64, 1), harness.starts);
    try testing.expect(graphics.noteCreateDevice(true));
    try testing.expect(graphics.noteGetQueue(true));
    try testing.expect(graphics.noteCreateSwapchain(true));
    try testing.expect(graphics.noteSwapchainImages(true));
    try testing.expect(graphics.noteAcquire(true));
    try testing.expect(graphics.noteQueueSubmit(true));
    try testing.expect(graphics.notePresent(true));
    try testing.expect(graphics.notePresent(true));

    const snapshot = graphics.snapshot();
    try testing.expect(snapshot.contractReady());
    try testing.expect(snapshot.nativePresenterReady());
    try testing.expectEqual(@as(u64, 2), harness.frames);
    try testing.expectEqual(@as(u64, 2), snapshot.native_diagnostic_attempts);
    try testing.expectEqual(@as(u64, 2), snapshot.native_diagnostic_frames);
    try testing.expectEqual(@as(u64, 0), snapshot.native_diagnostic_failures);
    try testing.expect(!snapshot.native_vulkan_forwarding);
}

test "a recognized-but-unimplemented import is refused with its own ABI failure value" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x500;

    // A registry lookup used to return zero, which is ERROR_SUCCESS: the
    // guest was told the key opened and then read an HKEY that was never
    // written.  It must report absence instead.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ADVAPI32.dll", "RegOpenKeyExW", return_rip));
    try testing.expectEqual(@as(u64, 2), state.regs.rax); // ERROR_FILE_NOT_FOUND

    // A COM/WinRT/DXGI creation is an HRESULT, where zero is S_OK.  These
    // used to be repaired one name at a time (CoCreateInstance still has its
    // own hand-written E_NOINTERFACE); the contract covers the rest of the
    // family without needing an entry per name.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "dxgi.dll", "CreateDXGIFactory1", return_rip));
    try testing.expectEqual(@as(u64, 0x8000_4001), state.regs.rax); // E_NOTIMPL
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-core-winrt-l1-1-0.dll", "RoGetActivationFactory", return_rip));
    try testing.expectEqual(@as(u64, 0x8000_4001), state.regs.rax);

    // A BOOL-returning GDI call keeps the zero that already meant FALSE, so
    // this change cannot alter a path that was already honest.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "GDI32.dll", "BitBlt", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u32, 120), state.windows_last_error); // ERROR_CALL_NOT_IMPLEMENTED

    // Every one of them is retained, with the first caller and step, so the
    // report can name what a run actually leaned on.
    const ledger = &state.windows_import_fallbacks;
    try testing.expectEqual(@as(usize, 4), ledger.count);
    try testing.expectEqual(@as(u64, 4), ledger.total_calls);
    try testing.expectEqual(@as(usize, 4), ledger.refusedCount());
    try testing.expectEqualStrings("RegOpenKeyExW", ledger.entries[0].name());
    try testing.expectEqualStrings("ADVAPI32.dll", ledger.entries[0].dll());

    // A repeat is counted, not duplicated.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ADVAPI32.dll", "RegOpenKeyExW", return_rip));
    try testing.expectEqual(@as(usize, 4), ledger.count);
    try testing.expectEqual(@as(u64, 2), ledger.entries[0].calls);
}

test "the window's monitor handle is stable and a non-Vulkan graphics import is not told S_OK" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x600;

    // Win32 returns the same HMONITOR for the same display.  A fresh handle
    // per call makes a guest that caches "the monitor my window is on" see a
    // display change on every query.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "MonitorFromWindow", return_rip));
    const first = state.regs.rax;
    try testing.expect(first != 0);
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "MonitorFromWindow", return_rip));
    try testing.expectEqual(first, state.regs.rax);
    // MonitorFromPoint names the same single virtual display.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "MonitorFromPoint", return_rip));
    try testing.expectEqual(first, state.regs.rax);

    // The graphics import class covers whole DLLs, not just `vk` names.
    // Zero is VK_SUCCESS for a Vulkan entry and S_OK for a DXGI one, so the
    // unmodelled fallback cannot be shared between them.
    state.regs = .{};
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "dxgi.dll", "CreateDXGIFactory1", return_rip));
    try testing.expectEqual(@as(u64, 0x8000_4001), state.regs.rax); // E_NOTIMPL
}

test "the progress watchdog only fires when every observable axis is frozen" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_progress.interval = 10;
    state.windows_progress.threshold = 3;

    // A run that is doing nothing at all: repeated samples are identical.
    var step: u64 = 0;
    while (step < 10 * 6) : (step += 10) {
        state.executed_steps = step;
        state.windows_progress.next_sample_step = step;
        state.checkWindowsProgress();
    }
    try testing.expect(state.windows_progress.reported);
    try testing.expectEqual(@as(u64, 1), state.windows_progress.episodes);

    // One import call is enough to prove the guest is still crossing a
    // boundary Rosetta owns, and the episode ends.
    state.windows_import_calls += 1;
    state.executed_steps += 10;
    state.windows_progress.next_sample_step = state.executed_steps;
    state.checkWindowsProgress();
    try testing.expect(!state.windows_progress.reported);
    try testing.expectEqual(@as(u32, 0), state.windows_progress.frozen_samples);

    // ...and so is a worker starting, which moves no counter of its own.
    state.windows_guest_threads[0] = .{ .status = .pending, .handle = 1, .start_routine = MEM_BASE };
    state.executed_steps += 10;
    state.windows_progress.next_sample_step = state.executed_steps;
    state.checkWindowsProgress();
    try testing.expectEqual(@as(u32, 0), state.windows_progress.frozen_samples);

    // A disabled watchdog samples nothing at all.
    state.windows_progress.enabled = false;
    state.executed_steps += 10;
    state.windows_progress.next_sample_step = state.executed_steps;
    state.checkWindowsProgress();
    try testing.expectEqual(state.executed_steps, state.windows_progress.next_sample_step);
}

test "an invalidated window is painted through the message pump until it is validated" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    // A window with no WndProc cannot receive WM_PAINT, so the class has to
    // be registered first; otherwise the pump would spin on a paint nobody
    // can consume.
    const class_name = MEM_BASE + 0x900;
    const class_info = MEM_BASE + 0x940;
    const wnd_proc = MEM_BASE + 0x200;
    state.write8(class_name, 'X');
    state.write8(class_name + 1, 0);
    state.write64(class_info + 8, wnd_proc);
    state.write64(class_info + 64, class_name);
    try testing.expect(state.registerWindowsWindowClass(class_info, false) != 0);

    const hwnd: u64 = 0xFFFF_0000_0000_0010;
    try testing.expect(state.createWindowsWindow(hwnd, class_name, 0, false, 0, 0, false));

    // A freshly created window has an empty update region, so no paint is
    // owed and the pump must stay quiet.
    try testing.expectEqual(@as(usize, 0), state.windowsPendingPaintCount());
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) == null);

    try testing.expect(state.invalidateWindowsWindow(hwnd));
    try testing.expectEqual(@as(usize, 1), state.windowsPendingPaintCount());

    // WM_PAINT is generated, not dequeued: observing it must not consume it,
    // which is what lets a guest peek before it paints.
    const first = state.pendingWindowsPaintMessage(0, 0, 0).?;
    try testing.expectEqual(hwnd, first.hwnd);
    try testing.expectEqual(WINDOWS_WM_PAINT, first.message);
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) != null);

    // The guest's WndProc validates the region; only then does the paint stop.
    try testing.expect(state.validateWindowsWindow(hwnd));
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) == null);
    try testing.expectEqual(@as(u64, 1), state.windows_paint_requests);
    try testing.expect(state.windows_paint_deliveries >= 2);

    // A null HWND invalidates every drawable window, matching Win32.
    try testing.expect(state.invalidateWindowsWindow(0));
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) != null);

    // A pump filtered to a message range that excludes WM_PAINT, or to a
    // different window, must not observe the paint.
    try testing.expect(state.pendingWindowsPaintMessage(0, 0x0100, 0x0200) == null);
    try testing.expect(state.pendingWindowsPaintMessage(hwnd +| 1, 0, 0) == null);
}

test "the Win32 pump turns a guest paint request into a WM_PAINT the guest can dispatch" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const class_name = MEM_BASE + 0xA00;
    const class_info = MEM_BASE + 0xA40;
    const wnd_proc = MEM_BASE + 0x300;
    const message_buffer = MEM_BASE + 0xB00;
    const return_rip = MEM_BASE + 0x400;
    state.write8(class_name, 'W');
    state.write8(class_name + 1, 0);
    state.write64(class_info + 8, wnd_proc);
    state.write64(class_info + 64, class_name);
    try testing.expect(state.registerWindowsWindowClass(class_info, false) != 0);

    const hwnd: u64 = 0xFFFF_0000_0000_0040;
    try testing.expect(state.createWindowsWindow(hwnd, class_name, 0, false, 0, 0, false));

    // With no update region the pump has nothing to paint: GetMessage still
    // returns so the guest loop keeps running, but the message is WM_NULL.
    state.regs = .{};
    state.regs.rcx = message_buffer;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "GetMessageW", return_rip));
    try testing.expectEqual(@as(u32, 0), state.read32(message_buffer + 8));

    // The guest asks for a repaint the way an ordinary Win32 window does.
    state.regs = .{};
    state.regs.rcx = hwnd;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "InvalidateRect", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);

    state.regs = .{};
    state.regs.rcx = message_buffer;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "GetMessageW", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(hwnd, state.read64(message_buffer));
    try testing.expectEqual(WINDOWS_WM_PAINT, state.read32(message_buffer + 8));

    // Xenia's WndProc answers WM_PAINT with ValidateRect + its own painter.
    // After the region is validated the pump goes quiet again, which is what
    // keeps a healthy run from spinning on repaints nobody asked for.
    state.regs = .{};
    state.regs.rcx = hwnd;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "ValidateRect", return_rip));

    state.regs = .{};
    state.regs.rcx = message_buffer;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "GetMessageW", return_rip));
    try testing.expectEqual(@as(u32, 0), state.read32(message_buffer + 8));

    // BeginPaint is the other half of the Win32 contract and must also end
    // the pending paint, or a guest that uses it would repaint forever.
    state.regs = .{};
    state.regs.rcx = hwnd;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "InvalidateRect", return_rip));
    const paint_struct = MEM_BASE + 0xC00;
    state.regs = .{};
    state.regs.rcx = hwnd;
    state.regs.rdx = paint_struct;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "user32.dll", "BeginPaint", return_rip));
    try testing.expect(state.regs.rax != 0);
    try testing.expectEqual(state.regs.rax, state.read64(paint_struct));
    try testing.expectEqual(@as(usize, 0), state.windowsPendingPaintCount());
}

test "a window with no WndProc never produces a paint the pump cannot deliver" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const hwnd: u64 = 0xFFFF_0000_0000_0020;
    try testing.expect(state.createWindowsWindow(hwnd, 0, 0, false, 0, 0, false));
    try testing.expect(state.invalidateWindowsWindow(hwnd));
    // The request is recorded -- that is the evidence a stall report needs --
    // but nothing is handed to a pump that has no WndProc to run.
    try testing.expectEqual(@as(usize, 1), state.windowsPendingPaintCount());
    try testing.expect(state.pendingWindowsPaintMessage(0, 0, 0) == null);

    // A message-only window is not drawable and must never be invalidated.
    const message_only: u64 = 0xFFFF_0000_0000_0030;
    try testing.expect(state.createWindowsWindow(message_only, 0, 0, true, 0, 0, false));
    try testing.expect(!state.invalidateWindowsWindow(message_only));

    // An unknown handle is a rejected request, not a silent success.
    try testing.expect(!state.invalidateWindowsWindow(0xDEAD));
    try testing.expect(!state.validateWindowsWindow(0xDEAD));
}

test "PE IAT targets are routed through the Windows import dispatcher" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const address = MEM_BASE + 0x700;
    try testing.expect(state.registerWindowsImportStubAt(address, "kernel32.dll", "GetLastError"));
    const stub = state.windowsImportStubAt(address).?;
    try testing.expectEqualStrings("kernel32.dll", stub.dll_name);
    try testing.expectEqualStrings("GetLastError", stub.function_name);
    try testing.expectEqual(@as(u8, 0xF4), state.read8(address));

    // A second registration at the same IAT address is idempotent only when
    // it describes the original import; silently rebinding it would make a
    // stale PE thunk call a different Windows API.
    try testing.expect(state.registerWindowsImportStubAt(address, "kernel32.dll", "GetLastError"));
    try testing.expect(!state.registerWindowsImportStubAt(address, "kernel32.dll", "VirtualAlloc"));
}

test "Windows CRT realloc preserves guest bytes and zeroes grown recalloc tails" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x780;
    const original = state.guestAlloc(32, 16).?;
    for (0..32) |index| state.write8(original + @as(u64, @intCast(index)), @intCast(index + 1));

    state.regs.rcx = original;
    state.regs.rdx = 64;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-heap-l1-1-0.dll", "realloc", return_rip));
    const grown = state.regs.rax;
    try testing.expect(grown != 0);
    try testing.expect(grown != original);
    for (0..32) |index| try testing.expectEqual(@as(u8, @intCast(index + 1)), state.read8(grown + @as(u64, @intCast(index))));
    for (32..64) |index| try testing.expectEqual(@as(u8, 0), state.read8(grown + @as(u64, @intCast(index))));

    state.regs.rcx = grown;
    state.regs.rdx = 32;
    state.regs.r8 = 4;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-heap-l1-1-0.dll", "_recalloc", return_rip));
    const recalloced = state.regs.rax;
    try testing.expect(recalloced != 0);
    try testing.expect(recalloced != grown);
    for (0..32) |index| try testing.expectEqual(@as(u8, @intCast(index + 1)), state.read8(recalloced + @as(u64, @intCast(index))));
    for (32..128) |index| try testing.expectEqual(@as(u8, 0), state.read8(recalloced + @as(u64, @intCast(index))));

    state.regs.rcx = recalloced;
    state.regs.rdx = 8;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-heap-l1-1-0.dll", "realloc", return_rip));
    try testing.expectEqual(recalloced, state.regs.rax);
    try testing.expectEqual(@as(u8, 1), state.read8(recalloced));

    state.regs.rcx = recalloced;
    state.regs.rdx = 0;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "api-ms-win-crt-heap-l1-1-0.dll", "realloc", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expect(!state.releaseGuestAllocation(recalloced));
}

test "Windows CRT memmove preserves overlapping guest bytes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x880;
    const buffer = state.guestAlloc(16, 1).?;
    for ("abcdef", 0..) |character, index| state.write8(buffer + @as(u64, @intCast(index)), character);
    state.regs.rcx = buffer + 1;
    state.regs.rdx = buffer;
    state.regs.r8 = 5;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memmove", return_rip));
    try testing.expectEqualStrings("aabcde", state.mem[@intCast(state.addrToOffset(buffer).?)..][0..6]);

    for ("abcdef", 0..) |character, index| state.write8(buffer + @as(u64, @intCast(index)), character);
    state.regs.rcx = buffer;
    state.regs.rdx = buffer + 1;
    state.regs.r8 = 5;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memmove", return_rip));
    try testing.expectEqualStrings("bcdef", state.mem[@intCast(state.addrToOffset(buffer).?)..][0..5]);
}

test "Windows bootstrap materializes command line and UTF-16 conversion" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x900;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetCommandLineW", return_rip));
    const command_line = state.regs.rax;
    try testing.expect(command_line != 0);
    try testing.expectEqual(@as(u16, 'x'), state.read16(command_line));
    try testing.expectEqual(@as(u16, 0), state.read16(command_line + 16 * 2));
    try testing.expectEqual(return_rip, state.regs.rip);

    const wide_source = state.guestAlloc(14, 2).?;
    for ([_]u16{ 'H', 'a', 'l', 'o', ' ', '3', 0 }, 0..) |unit, index| {
        state.write16(wide_source + @as(u64, @intCast(index * 2)), unit);
    }
    const narrow_destination = state.guestAlloc(16, 1).?;
    state.regs.rcx = 65001; // CP_UTF8
    state.regs.rdx = 0;
    state.regs.r8 = wide_source;
    state.regs.r9 = std.math.maxInt(u32); // -1: include the terminator
    state.regs.rsp = MEM_BASE + 0x1000;
    state.write64(state.regs.rsp + 32, narrow_destination);
    state.write64(state.regs.rsp + 40, 16);
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "WideCharToMultiByte", return_rip));
    try testing.expectEqual(@as(u64, 7), state.regs.rax);
    const narrow_offset: usize = @intCast(state.addrToOffset(narrow_destination).?);
    try testing.expectEqualStrings("Halo 3", state.mem[narrow_offset..][0..6]);
    try testing.expectEqual(@as(u8, 0), state.read8(narrow_destination + 6));
}

test "Windows filesystem bootstrap supplies guest-owned executable and user paths" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x980;
    const executable_output = state.guestAlloc(8, 8).?;
    state.regs.rcx = executable_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "_get_wpgmptr", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    const executable_path = state.read64(executable_output);
    try testing.expect(executable_path != 0);
    for ([_]u16{ 'C', ':', '\\', 'x', 'e', 'n', 'i', 'a', '\\', 'x', 'e', 'n', 'i', 'a', '_', 'c', 'a', 'n', 'a', 'r', 'y', '.', 'e', 'x', 'e', 0 }, 0..) |unit, index| {
        try testing.expectEqual(unit, state.read16(executable_path + @as(u64, @intCast(index * 2))));
    }

    const known_folder_output = state.guestAlloc(8, 8).?;
    state.regs.r9 = known_folder_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "shell32.dll", "SHGetKnownFolderPath", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    const known_folder_path = state.read64(known_folder_output);
    try testing.expect(known_folder_path != 0);
    for ([_]u16{ 'C', ':', '\\', 'x', 'e', 'n', 'i', 'a', '\\', 'D', 'o', 'c', 'u', 'm', 'e', 'n', 't', 's', 0 }, 0..) |unit, index| {
        try testing.expectEqual(unit, state.read16(known_folder_path + @as(u64, @intCast(index * 2))));
    }

    const wide_string = state.guestAlloc(32, 2).?;
    for ("C:\\xenia", 0..) |unit, index| {
        state.write16(wide_string + @as(u64, @intCast(index * 2)), unit);
    }
    state.write16(wide_string + 16, 0);
    state.regs.rcx = wide_string;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "wcslen", return_rip));
    try testing.expectEqual(@as(u64, 8), state.regs.rax);
}

test "Windows path and XInput contracts preserve guest ABI semantics" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0xA00;
    const source = state.guestAlloc(32, 1).?;
    const destination = state.guestAlloc(128, 1).?;
    const file_part = state.guestAlloc(8, 8).?;
    for ("config.toml", 0..) |character, index| state.write8(source + @as(u64, @intCast(index)), character);
    state.write8(source + 11, 0);
    state.regs.rcx = source;
    state.regs.rdx = 128;
    state.regs.r8 = destination;
    state.regs.r9 = file_part;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetFullPathNameA", return_rip));
    try testing.expectEqualStrings("C:\\xenia\\config.toml", std.mem.sliceTo(state.mem[@intCast(state.addrToOffset(destination).?)..], 0));
    try testing.expectEqual(destination + 9, state.read64(file_part));
    try testing.expectEqual(return_rip, state.regs.rip);

    const state_output = state.guestAlloc(16, 4).?;
    state.regs.rcx = 0;
    state.regs.rdx = state_output;
    state.regs.r8 = 0;
    state.regs.r9 = 0;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "XInputGetState", return_rip));
    try testing.expectEqual(@as(u64, 1167), state.regs.rax);
    for (state.mem[@intCast(state.addrToOffset(state_output).?)..][0..16]) |byte| try testing.expectEqual(@as(u8, 0), byte);
}

test "Windows PE filesystem bridge reads only from its configured root" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // The check graph runs test artifacts from both the repository root and
    // the build directory. Keep the fixture in Zig's per-run temporary tree
    // so this contract tests the configured-root boundary rather than an
    // incidental process working directory.
    var temp_dir = testing.tmpDir(.{});
    defer temp_dir.cleanup();
    try temp_dir.dir.writeFile(testing.io, .{
        .sub_path = "probe.zig",
        .data = "windows runtime probe\n",
    });
    var working_directory_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const working_directory = try std.fmt.bufPrint(
        &working_directory_buffer,
        ".zig-cache/tmp/{s}",
        .{temp_dir.sub_path[0..]},
    );
    state.windows_runtime_enabled = true;
    state.windows_host_io = testing.io;
    state.windows_host_working_directory = working_directory;

    const return_rip = MEM_BASE + 0xB00;
    state.regs.rsp = MEM_BASE + 0x1000;
    const path = state.guestAlloc(64, 1).?;
    for ("C:\\xenia\\probe.zig", 0..) |character, index| state.write8(path + @as(u64, @intCast(index)), character);
    state.write8(path + 18, 0);
    state.regs.rcx = path;
    state.regs.rdx = 0x8000_0000; // GENERIC_READ
    state.regs.r8 = 1; // FILE_SHARE_READ
    state.regs.r9 = 0;
    state.write64(state.regs.rsp + 32, 3); // OPEN_EXISTING
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "CreateFileA", return_rip));
    const handle = state.regs.rax;
    try testing.expect(handle != std.math.maxInt(u64));

    const buffer = state.guestAlloc(16, 1).?;
    const completed = state.guestAlloc(4, 4).?;
    state.regs.rcx = handle;
    state.regs.rdx = buffer;
    state.regs.r8 = 8;
    state.regs.r9 = completed;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "ReadFile", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expect(state.read32(completed) > 0);

    state.regs.rcx = handle;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "CloseHandle", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);

    const outside = state.guestAlloc(64, 1).?;
    for ("C:\\Windows\\System32\\secret", 0..) |character, index| state.write8(outside + @as(u64, @intCast(index)), character);
    state.write8(outside + 29, 0);
    state.regs.rcx = outside;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetFileAttributesA", return_rip));
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.rax);

    const pattern = state.guestAlloc(64, 1).?;
    for ("C:\\xenia\\*.zig", 0..) |character, index| state.write8(pattern + @as(u64, @intCast(index)), character);
    state.write8(pattern + 15, 0);
    const find_data = state.guestAlloc(592, 8).?;
    state.regs.rcx = pattern;
    state.regs.rdx = find_data;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "FindFirstFileA", return_rip));
    const find_handle = state.regs.rax;
    try testing.expect(find_handle != std.math.maxInt(u64));
    try testing.expect(state.read32(find_data) == 0x80 or state.read32(find_data) == 0x10);
    state.regs.rcx = find_handle;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "FindClose", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
}

test "native guest forwarding does not start a duplicate diagnostic presenter" {
    var harness = NativeGraphicsTestHarness{};
    var graphics = WindowsGraphicsState{
        .hooks = .{
            .native_context = &harness,
            .native_presenter_start = testNativePresenterStart,
            .native_presenter_stage = testNativePresenterStage,
            .native_presenter_is_ready = testNativePresenterReady,
            .native_presenter_present_diagnostic = testNativePresenterDiagnostic,
        },
    };
    try testing.expect(graphics.ensureWindow(1280, 720, "native guest"));
    graphics.native_vulkan_forwarding = true;
    try testing.expect(graphics.noteCreateInstance(true));
    try testing.expect(graphics.noteCreateSurface(true));
    try testing.expectEqual(@as(u64, 0), harness.starts);
    try testing.expect(graphics.noteCreateDevice(true));
    try testing.expect(graphics.noteGetQueue(true));
    try testing.expect(graphics.noteCreateSwapchain(true));
    try testing.expect(graphics.noteSwapchainImages(true));
    try testing.expect(graphics.noteAcquire(true));
    try testing.expect(graphics.noteQueueSubmit(true));
    try testing.expect(graphics.notePresent(true));
    try testing.expectEqual(@as(u64, 0), harness.frames);
}
