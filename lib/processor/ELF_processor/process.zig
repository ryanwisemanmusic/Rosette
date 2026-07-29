const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.elf);
const elf_loader = @import("elf_loader.zig");
const result_dump = @import("result_dump.zig");
const x64_guest_abi = @import("x64_guest_abi");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const x64_linux_runtime = @import("x64_linux_runtime");
const x64_syscalls = @import("x64_syscalls");
const exit_diagnostics = @import("exit_diagnostics");
const cleo_routing = @import("cleo_routing");

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
const BitScanKind = x64_decoder.BitScanKind;

// ─── ELF state ───

pub const ElfState = struct {
    allocator: std.mem.Allocator,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    image_low: u64 = 0,
    image_high: u64 = 0,
    regs: ElfRegs = .{},
    xmm: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16,
    // AVX-512 opmask registers (k0-k7). k0 is always all-1s when read as
    // a mask operand; k1-k7 hold actual mask values for predicated operations.
    k: [8]u64 = [_]u64{0xFFFF_FFFF_FFFF_FFFF} ** 8,
    x87_integer_top: i64 = 0,
    x87_integer_valid: bool = false,
    terminated: bool = false,
    exit_code: u64 = 0,
    faulted: bool = false,
    termination_reason: exit_diagnostics.TerminationReason = .unknown,
    executed_steps: u64 = 0,
    trace_entries: [TRACE_BUFFER_LEN]ElfTraceEntry = [_]ElfTraceEntry{.{}} ** TRACE_BUFFER_LEN,
    trace_index: usize = 0,
    trace_filled: bool = false,
    libc_start_main_trampolined: bool = false,
    dynamic_relocations: []const elf_loader.DynamicRelocation = &.{},
    local_symbols: []const elf_loader.Symbol = &.{},
    init_functions: []const u64 = &.{},
    init_index: usize = 0,
    pending_main_addr: u64 = 0,
    pending_argc: u64 = 0,
    pending_argv: u64 = 0,
    heap_next: u64 = MEM_BASE + (MEM_SIZE / 2),
    trace_syscalls: bool = false,
    trace_syscall_bytes: bool = false,
    trace_fd_filter: ?u64 = null,
    trace_calls: bool = false,
    diagnose_abi: bool = false,
    call_stack: x64_guest_abi.CallStack = .{},
    interactive_output_path: ?[]u8 = null,
    interactive_summary_printed: bool = false,

    pub fn init(allocator: std.mem.Allocator) ElfState {
        const mem = allocator.alloc(u8, MEM_SIZE) catch unreachable;
        @memset(mem, 0);
        return .{
            .allocator = allocator,
            .mem = mem,
            .mem_base = MEM_BASE,
            .mem_size = MEM_SIZE,
            .trace_syscalls = envFlag("ROSETTE_ELF_TRACE_SYSCALLS"),
            .trace_syscall_bytes = envFlag("ROSETTE_ELF_TRACE_SYSCALL_BYTES"),
            .trace_fd_filter = envU64("ROSETTE_ELF_TRACE_FD"),
            .trace_calls = envFlag("ROSETTE_ELF_TRACE_CALLS"),
            .diagnose_abi = envFlag("ROSETTE_ELF_DIAGNOSE_ABI") or envFlag("ROSETTE_ELF_INTERACTIVE_BRIDGE") or envFlag("ROSETTE_ELF_EDU_BRIDGE"),
        };
    }

    pub fn deinit(self: *ElfState) void {
        if (self.interactive_output_path) |path| self.allocator.free(path);
        self.call_stack.deinit(self.allocator);
        self.allocator.free(self.mem);
    }

    pub fn addrToOffset(self: *const ElfState, vaddr: u64) ?u64 {
        if (vaddr < self.mem_base) return null;
        const off = vaddr - self.mem_base;
        if (off >= self.mem_size) return null;
        return off;
    }

    pub fn read8(self: *const ElfState, vaddr: u64) u8 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        return self.mem[off];
    }

    pub fn read16(self: *const ElfState, vaddr: u64) u16 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 2 > self.mem.len) return 0;
        return std.mem.readInt(u16, self.mem[off..][0..2], .little);
    }

    pub fn read32(self: *const ElfState, vaddr: u64) u32 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 4 > self.mem.len) return 0;
        return std.mem.readInt(u32, self.mem[off..][0..4], .little);
    }

    pub fn read64(self: *const ElfState, vaddr: u64) u64 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 8 > self.mem.len) return 0;
        return std.mem.readInt(u64, self.mem[off..][0..8], .little);
    }

    fn write8(self: *ElfState, vaddr: u64, val: u8) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off < self.mem.len) self.mem[off] = val;
    }

    fn write16(self: *ElfState, vaddr: u64, val: u16) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 2 <= self.mem.len) std.mem.writeInt(u16, self.mem[off..][0..2], val, .little);
    }

    fn write32(self: *ElfState, vaddr: u64, val: u32) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 4 <= self.mem.len) std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
    }

    pub fn write64(self: *ElfState, vaddr: u64, val: u64) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 8 <= self.mem.len) std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
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
        if (self.regs.rip == SYNTHETIC_INIT_RETURN) {
            self.scheduleNextInitOrMain();
            return true;
        }
        if (self.regs.rip == SYNTHETIC_MAIN_RETURN) {
            self.exit_code = self.regs.rax;
            self.terminated = true;
            return true;
        }
        return false;
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
        self.trace_entries[self.trace_index] = .{
            .rip = self.regs.rip,
            .op = decoded.op,
            .len = decoded.len,
            .rsp = self.regs.rsp,
            .rax = self.regs.rax,
            .rcx = self.regs.rcx,
            .rdx = self.regs.rdx,
        };
        self.trace_index = (self.trace_index + 1) % TRACE_BUFFER_LEN;
        if (self.trace_index == 0) self.trace_filled = true;
    }

    pub fn guestAlloc(self: *ElfState, requested_size: u64, requested_alignment: u64) ?u64 {
        const size = if (requested_size == 0) 1 else requested_size;
        if (size > std.math.maxInt(usize)) return null;

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
        if (self.heap_next > std.math.maxInt(u64) - mask) return null;
        const aligned = (self.heap_next + mask) & ~mask;
        const heap_limit = self.mem_base + self.mem_size - STACK_SIZE;
        if (aligned >= heap_limit or size > heap_limit - aligned) return null;
        const off = self.addrToOffset(aligned) orelse return null;
        const size_usize: usize = @intCast(size);
        if (off > self.mem.len or size_usize > self.mem.len - off) return null;

        @memset(self.mem[off..][0..size_usize], 0);
        self.heap_next = aligned + size;
        return aligned;
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
        const off = self.addrToOffset(fetch_address) orelse return null;
        const remaining = self.mem.len - off;
        if (remaining == 0) return null;
        const bytes = self.mem[off..];
        var d = decodeInsn(bytes);
        const prefixes = x64_decoder.decodeLegacyPrefixes(bytes);
        d.has_0x67 = prefixes.address_size_override;
        const addr_size: Size = if (d.has_0x67) .bits32 else .bits64;
        const base: ?RegId = if (d.sib_has_base) d.sib_base_reg else null;
        d.segment = x64_decoder.selectSegment(.explicit_data, base, prefixes.segment_override);
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
        return d;
    }

    fn step(self: *ElfState) bool {
        if (self.handleSyntheticRip()) return !self.terminated;
        const decoded = self.decodeAt() orelse {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = .decode_failed;
            self.terminated = true;
            return false;
        };
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
        self.recordTrace(decoded);
        const trace_this = shouldTraceRip(self.regs.rip);
        if (trace_this) {
            log.info("trace before rip=0x{x} op={s} len={d} rax=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rsp=0x{x} rbp=0x{x} flags=0x{x}", .{
                self.regs.rip,
                @tagName(decoded.op),
                decoded.len,
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.rsi,
                self.regs.rdi,
                self.regs.rsp,
                self.regs.rbp,
                self.regs.rflags,
            });
        }
        x64_interpreter.execute(self, decoded);
        if (trace_this) {
            log.info("trace after  rip=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rsp=0x{x} rbp=0x{x} flags=0x{x}", .{
                self.regs.rip,
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.rsi,
                self.regs.rdi,
                self.regs.rsp,
                self.regs.rbp,
                self.regs.rflags,
            });
        }
        return !self.terminated;
    }

    pub fn run(self: *ElfState) void {
        var steps: u64 = 0;
        const max_steps: u64 = 2_000_000;
        while (!self.terminated and steps < max_steps) : (steps += 1) {
            self.executed_steps = steps;
            if (steps % 100000 == 0) {
                log.info("step {d}: rip=0x{x}, rax=0x{x}, rbx=0x{x}, rcx=0x{x}, rsi=0x{x}, rdi=0x{x}", .{ steps, self.regs.rip, self.regs.rax, self.regs.rbx, self.regs.rcx, self.regs.rsi, self.regs.rdi });
            }
            if (!self.step()) break;
        }
        if (steps >= max_steps) {
            log.warn("reached max steps ({d})", .{max_steps});
            self.logRegs();
            self.faulted = true;
            self.exit_code = 124;
            self.termination_reason = .max_steps_reached;
            self.terminated = true;
        }
        if (self.faulted) self.logExitDiagnostics();
    }

    fn logExitDiagnostics(self: *const ElfState) void {
        var terminal = exit_diagnostics.TerminalInstruction{
            .address = self.regs.rip,
            .op = if (self.termination_reason == .invalid_instruction) "invalid" else "decode_failed",
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

        const trace_count = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        var trace: [TRACE_BUFFER_LEN]exit_diagnostics.TraceEntry = undefined;
        for (0..trace_count) |index| {
            const source_index = if (self.trace_filled) (self.trace_index + index) % TRACE_BUFFER_LEN else index;
            const entry = self.trace_entries[source_index];
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

    fn regVal(self: *const ElfState, id: RegId, size: Size) u64 {
        return x64_decoder.regVal(&self.regs, id, size);
    }

    fn setReg(self: *ElfState, id: RegId, size: Size, val: u64) void {
        x64_decoder.setReg(&self.regs, id, size, val);
    }

    fn decodedRegVal(self: *const ElfState, id: RegId, high8: bool, size: Size) u64 {
        return x64_decoder.registerOperandValue(&self.regs, .{ .id = id, .high8 = high8 }, size);
    }

    fn setDecodedReg(self: *ElfState, id: RegId, high8: bool, size: Size, val: u64) void {
        x64_decoder.setRegisterOperand(&self.regs, .{ .id = id, .high8 = high8 }, size, val);
    }

    fn readMemVal(self: *ElfState, addr: u64, size: Size) u64 {
        return switch (size) {
            .bits8 => self.read8(addr),
            .bits16 => self.read16(addr),
            .bits32 => self.read32(addr),
            .bits64 => self.read64(addr),
        };
    }

    fn writeMemVal(self: *ElfState, addr: u64, size: Size, val: u64) void {
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

    fn readMem128(self: *const ElfState, addr: u64) [16]u8 {
        var value = [_]u8{0} ** 16;
        const off = self.addrToOffset(addr) orelse return value;
        if (off + 16 > self.mem.len) return value;
        @memcpy(value[0..], self.mem[off..][0..16]);
        return value;
    }

    fn writeMem128(self: *ElfState, addr: u64, value: [16]u8) void {
        const off = self.addrToOffset(addr) orelse return;
        if (off + 16 > self.mem.len) return;
        @memcpy(self.mem[off..][0..16], value[0..]);
    }

    pub fn guestMemory(self: *ElfState, addr: u64, count: u64) ?[]u8 {
        if (count > std.math.maxInt(usize)) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
    }

    pub fn guestMemoryConst(self: *const ElfState, addr: u64, count: u64) ?[]const u8 {
        if (count > std.math.maxInt(usize)) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
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

    fn executeHighwayRegisterBinary(self: *ElfState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp) void {
        const width: x64_decoder.highway.Width = switch (d.size) {
            .bits8 => .bits8,
            .bits16 => .bits16,
            .bits32 => .bits32,
            .bits64 => .bits64,
        };
        const evaluated = x64_decoder.highway.evaluate(op, width, self.regVal(d.dst_reg, d.size), self.regVal(d.src_reg, d.size), self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.writeback) self.setReg(d.dst_reg, d.size, evaluated.value);
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
        const check = x64_decoder.highway.validateRange(0, self.mem.len, d.addr, width, access, true);
        if (!check.allowed()) {
            self.faulted = true;
            self.terminated = true;
            self.exit_code = 127;
            return;
        }
        const reg = if (direction == .memory_to_register) d.dst_reg else d.src_reg;
        const evaluated = x64_decoder.highway.evaluateMemory(op, width, self.regVal(reg, d.size), self.readMemVal(d.addr, d.size), direction, self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.write_register) self.setReg(reg, d.size, evaluated.value);
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
            const check = x64_decoder.highway.validateRange(0, self.mem.len, d.addr, width, access, true);
            if (!check.allowed()) {
                self.faulted = true;
                self.terminated = true;
                self.exit_code = 127;
                return;
            }
        }
        const lhs = if (memory) self.readMemVal(d.addr, d.size) else self.regVal(d.dst_reg, d.size);
        const evaluated = x64_decoder.highway.evaluate(op, width, lhs, immediate, self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.writeback) {
            if (memory) self.writeMemVal(d.addr, d.size, evaluated.value) else self.setReg(d.dst_reg, d.size, evaluated.value);
        }
    }

    fn setFlag(self: *ElfState, flag: u32, enabled: bool) void {
        if (enabled) {
            self.regs.rflags |= flag;
        } else {
            self.regs.rflags &= ~flag;
        }
    }

    fn executeBtrRegister(self: *ElfState, d: DecodedInsn) void {
        const width = @as(u64, @intFromEnum(d.size));
        const bit_index = self.regVal(d.src_reg, d.size) & (width - 1);
        const mask = @as(u64, 1) << @as(u6, @intCast(bit_index));
        const value = self.regVal(d.dst_reg, d.size);
        self.setFlag(RFL_CF, value & mask != 0);
        self.setReg(d.dst_reg, d.size, value & ~mask);
    }

    fn executeBtrMemory(self: *ElfState, d: DecodedInsn) void {
        const width = @as(i64, @intFromEnum(d.size));
        const byte_width = @divExact(width, 8);
        const raw_index = self.regVal(d.src_reg, d.size);
        const bit_index: i64 = switch (d.size) {
            .bits16 => @as(i16, @bitCast(@as(u16, @truncate(raw_index)))),
            .bits32 => @as(i32, @bitCast(@as(u32, @truncate(raw_index)))),
            .bits64 => @bitCast(raw_index),
            .bits8 => unreachable,
        };
        const element_offset = @divFloor(bit_index, width);
        const element_address = d.addr +% @as(u64, @bitCast(element_offset * byte_width));
        const bit_in_element: u6 = @intCast(@mod(bit_index, width));
        const mask = @as(u64, 1) << bit_in_element;
        const value = self.readMemVal(element_address, d.size);
        self.setFlag(RFL_CF, value & mask != 0);
        self.writeMemVal(element_address, d.size, value & ~mask);
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

    pub fn execute(self: *ElfState, d: DecodedInsn) void {
        // Check if this instruction can be routed to CLEO for wide SIMD execution
        {
            const route = cleo_routing.CleoRouter.route(
                @tagName(d.op),
                cleo_routing.types.FeatureSet.cleoEmulated(),
                0,
            );
            if (route.can_route) {
                if (route.meta) |meta| {
                    const result_wide: ?cleo_routing.wide.Wide(128) = ternary: {
                        const is_fma = switch (meta.operation) {
                            .fma_ps, .fma_pd, .fms_ps, .fms_pd, .fnma_ps, .fnma_pd, .fnms_ps, .fnms_pd, .fma_addsub_ps, .fma_addsub_pd, .fma_subadd_ps => true,
                            else => false,
                        };
                        const mask_active = d.opmask != 0;
                        const mask_val: u64 = if (mask_active) self.k[d.opmask] else 0xFFFF_FFFF_FFFF_FFFF;
                        const mask_mode: cleo_routing.wide.MaskMode = if (d.zero_mask) .zero else .merge;
                        if (!is_fma) {
                            _ = d.evex_broadcast; // Reserved for EVEX broadcast semantics
                            if (mask_active) {
                                break :ternary cleo_routing.ops.executeBinaryMasked(
                                    128,
                                    meta,
                                    cleo_routing.wide.Wide(128).fromBytes(self.xmm[d.xmm_dst]),
                                    cleo_routing.wide.Wide(128).fromBytes(self.xmm[d.xmm_dst]),
                                    cleo_routing.wide.Wide(128).fromBytes(self.xmm[d.xmm_src]),
                                    mask_val,
                                    mask_mode,
                                    route.features,
                                ) catch null;
                            }
                            break :ternary cleo_routing.ops.executeBinary(
                                128,
                                meta,
                                cleo_routing.wide.Wide(128).fromBytes(self.xmm[d.xmm_dst]),
                                cleo_routing.wide.Wide(128).fromBytes(self.xmm[d.xmm_src]),
                                route.features,
                            ) catch null;
                        }
                        const op_name = @tagName(d.op);
                        const has_132 = std.mem.indexOf(u8, op_name, "132") != null;
                        const has_213 = std.mem.indexOf(u8, op_name, "213") != null;
                        const accum = if (has_132) d.xmm_src2 else if (has_213) d.xmm_src else d.xmm_dst;
                        const lhs = if (has_132) d.xmm_dst else if (has_213) d.xmm_src2 else d.xmm_src2;
                        const rhs = if (has_132) d.xmm_src else if (has_213) d.xmm_dst else d.xmm_src;
                        if (mask_active) {
                            break :ternary cleo_routing.ops.executeAccumulateMasked(
                                128,
                                meta,
                                cleo_routing.wide.Wide(128).fromBytes(self.xmm[d.xmm_dst]),
                                cleo_routing.wide.Wide(128).fromBytes(self.xmm[accum]),
                                cleo_routing.wide.Wide(128).fromBytes(self.xmm[lhs]),
                                cleo_routing.wide.Wide(128).fromBytes(self.xmm[rhs]),
                                mask_val,
                                mask_mode,
                                route.features,
                            ) catch null;
                        }
                        break :ternary cleo_routing.ops.executeAccumulate(
                            128,
                            meta,
                            cleo_routing.wide.Wide(128).fromBytes(self.xmm[accum]),
                            cleo_routing.wide.Wide(128).fromBytes(self.xmm[lhs]),
                            cleo_routing.wide.Wide(128).fromBytes(self.xmm[rhs]),
                            route.features,
                        ) catch null;
                    };
                    if (result_wide) |rw| {
                        self.xmm[d.xmm_dst] = rw.bytes;
                        return;
                    }
                }
                // Fall through to interpreter for unsupported operations
            }
        }
        switch (d.op) {
            .invalid => unreachable,
            .nop => {},
            .cmc => self.regs.rflags ^= RFL_CF,
            .clc => self.regs.rflags &= ~RFL_CF,
            .stc => self.regs.rflags |= RFL_CF,

            .fild_mem16, .fld_mem32, .fld_mem64, .fld_mem80, .fstp_mem32, .fstp_mem64, .fld_st, .fstp_st, .fxch_st, .ffree_st, .fninit, .fnstsw_ax, .fnstcw_mem16, .fldcw_mem16, .x87_binary, .fucomip_st => {},

            .fild_mem32 => {
                self.x87_integer_top = @bitCast(@as(i64, @bitCast(@as(u64, self.readMemVal(d.addr, .bits32)))));
                self.x87_integer_valid = true;
            },
            .fild_mem64 => {
                self.x87_integer_top = @bitCast(self.readMemVal(d.addr, .bits64));
                self.x87_integer_valid = true;
            },
            .fstp_mem80 => {
                const output = self.guestMemory(d.addr, 10) orelse return;
                if (self.x87_integer_valid) {
                    writeExtendedInt80(output, self.x87_integer_top);
                } else {
                    @memset(output[0..10], 0);
                }
                self.x87_integer_valid = false;
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

            .lods => {
                const address_size: Size = if (d.has_0x67) .bits32 else .bits64;
                const src_addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
                    .has_base = true,
                    .base_reg = .dh_si_esi_rsi,
                    .segment = d.segment,
                }, 0, address_size, .long64, true);
                switch (d.size) {
                    .bits8 => self.setReg(.al_ax_eax_rax, .bits8, self.readMemVal(src_addr, .bits8)),
                    .bits16 => self.setReg(.al_ax_eax_rax, .bits16, self.readMemVal(src_addr, .bits16)),
                    .bits32 => self.setReg(.al_ax_eax_rax, .bits32, self.readMemVal(src_addr, .bits32)),
                    .bits64 => self.setReg(.al_ax_eax_rax, .bits64, self.readMemVal(src_addr, .bits64)),
                }
                const stride: u64 = switch (d.size) {
                    .bits8 => 1,
                    .bits16 => 2,
                    .bits32 => 4,
                    .bits64 => 8,
                };
                const old_index = self.regVal(.dh_si_esi_rsi, address_size);
                const new_index = if ((self.regs.rflags & RFL_DF) != 0)
                    old_index -% stride
                else
                    old_index +% stride;
                self.setReg(.dh_si_esi_rsi, address_size, new_index);
            },

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
            .adc_reg8_mem8 => self.executeHighwayMemoryBinary(d, .adc, .memory_to_register),
            .sbb_reg8_mem8 => self.executeHighwayMemoryBinary(d, .sbb, .memory_to_register),
            .add_reg16_imm32, .add_reg32_imm32, .add_reg64_imm32 => {
                const imm = testImmForSize(d.imm, d.size);
                self.executeHighwayImmediate(d, .add, false, imm);
            },
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
            .sub_mem8_imm8 => self.executeHighwayImmediate(d, .sub, true, d.imm & 0xFF),
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

            .btr_reg_reg => self.executeBtrRegister(d),
            .btr_mem_reg => self.executeBtrMemory(d),

            // ── cmp r/m, reg (opcode 0x39) ──
            .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64 => self.executeHighwayMemoryBinary(d, .cmp, .register_to_memory),

            // ── cmp reg, reg (opcode 0x39, mod=3) ──
            .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64 => self.executeHighwayRegisterBinary(d, .cmp),

            // ── cmp reg, r/m (0x3A/0x3B, d=1) ──
            .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64 => self.executeHighwayMemoryBinary(d, .cmp, .memory_to_register),

            // ── cmp r/m, imm8 (0x83 /7) ──
            .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8 => self.executeHighwayImmediate(d, .cmp, true, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),
            .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => self.executeHighwayImmediate(d, .cmp, false, if (d.size == .bits8) d.imm & 0xFF else signExtendImm8(d.imm)),

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
                if (divisor == 0) return;
                const dividend = self.regVal(.al_ax_eax_rax, .bits16);
                const quot = dividend / @as(u16, @truncate(divisor));
                const rem = dividend % @as(u16, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @intCast(quot & 0xFF));
                self.setReg(.dl_dx_edx_rdx, .bits8, @intCast(rem & 0xFF));
            },
            .div_mem16 => {
                const divisor = self.readMemVal(d.addr, .bits16);
                if (divisor == 0) return;
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
                if (divisor == 0) return;
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
                if (divisor == 0) return;
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
                if (divisor == 0) return;
                const dividend: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const quot = @divTrunc(dividend, @as(i16, divisor));
                const rem = @rem(dividend, @as(i16, divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @as(u8, @bitCast(@as(i8, @truncate(quot)))));
                self.setReg(.dl_dx_edx_rdx, .bits8, @as(u8, @bitCast(@as(i8, @truncate(rem)))));
            },
            .idiv_mem16 => {
                const divisor: i16 = @bitCast(@as(u16, @intCast(self.readMemVal(d.addr, .bits16))));
                if (divisor == 0) return;
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
                if (divisor == 0) return;
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
                if (divisor == 0) return;
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
                if (divisor == 0) return;
                const dividend = self.regVal(.al_ax_eax_rax, .bits16);
                const quot = dividend / @as(u16, @truncate(divisor));
                const rem = dividend % @as(u16, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @intCast(quot & 0xFF));
                self.setReg(.dl_dx_edx_rdx, .bits8, @intCast(rem & 0xFF));
            },
            .div_reg16 => {
                const divisor = self.regVal(d.src_reg, .bits16);
                if (divisor == 0) return;
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
                if (divisor == 0) return;
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
                if (divisor == 0) return;
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
                if (divisor == 0) return;
                const dividend: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const quot = @divTrunc(dividend, @as(i16, divisor));
                const rem = @rem(dividend, @as(i16, divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @as(u8, @bitCast(@as(i8, @truncate(quot)))));
                self.setReg(.dl_dx_edx_rdx, .bits8, @as(u8, @bitCast(@as(i8, @truncate(rem)))));
            },
            .idiv_reg16 => {
                const divisor: i16 = @bitCast(@as(u16, @intCast(self.regVal(d.src_reg, .bits16))));
                if (divisor == 0) return;
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
                if (divisor == 0) return;
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
                if (divisor == 0) return;
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
            },
            .movups_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            },
            .movups_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            },
            .movaps_xmm_xmm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            },
            .movaps_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            },
            .movaps_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            },

            // ── imul r64, r/m64 (0F AF) ──
            .imul_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                const r = @as(i64, @bitCast(a)) * @as(i64, @bitCast(b));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                const r = @as(i64, @bitCast(a)) * @as(i64, @bitCast(b));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                const r = @as(i32, @bitCast(@as(u32, @truncate(a)))) * @as(i32, @bitCast(@as(u32, @truncate(b))));
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },
            .imul_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                const r = @as(i32, @bitCast(@as(u32, @truncate(a)))) * @as(i32, @bitCast(@as(u32, @truncate(b))));
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },

            // ── imul r, r/m, imm8 (0x6B) ──
            .imul_reg64_mem64_imm8 => {
                const b = self.readMemVal(d.addr, .bits64);
                const imm = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i64, @bitCast(b)) * imm;
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg64_reg64_imm8 => {
                const b = self.regVal(d.src_reg, .bits64);
                const imm = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i64, @bitCast(b)) * imm;
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg32_mem32_imm8 => {
                const b = self.readMemVal(d.addr, .bits32);
                const imm = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i32, @bitCast(@as(u32, @truncate(b)))) * imm;
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },
            .imul_reg32_reg32_imm8 => {
                const b = self.regVal(d.src_reg, .bits32);
                const imm = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i32, @bitCast(@as(u32, @truncate(b)))) * imm;
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },

            // ── Stack and calls ──
            .call_rel32 => {
                const rel = @as(i64, @bitCast(d.imm));
                const transfer = x64_decoder.highway.relativeControl(.call, self.regs.rip, d.len, rel, true);
                const next_rip = transfer.return_address.?;
                const target_rip = transfer.target;
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
                    self.regVal(d.src_reg, .bits64)
                else
                    self.readMemVal(d.addr, .bits64);
                if (target == 0 and d.op == .call_mem64 and x64_linux_runtime.tryLibcStartMainTrampoline(self, d, next_rip)) {
                    return;
                }
                if (target == 0) {
                    log.err("unresolved indirect call at rip=0x{x} operand=0x{x}", .{ self.regs.rip, d.addr });
                    self.faulted = true;
                    self.exit_code = 127;
                    self.terminated = true;
                    return;
                }
                self.noteGuestCall(.indirect, target, next_rip);
                self.push(next_rip);
                self.regs.rip = target;
                return;
            },
            .ret => {
                const return_rip = self.pop();
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
                    self.regVal(d.src_reg, .bits64)
                else
                    self.readMemVal(d.addr, .bits64);
                if (target == 0) {
                    log.err("unresolved indirect jump at rip=0x{x} operand=0x{x}", .{ self.regs.rip, d.addr });
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
                if (taken) {
                    self.regs.rip = x64_decoder.highway.relativeControl(.conditional_jump, self.regs.rip, d.len, @bitCast(d.imm), taken).target;
                    return;
                }
            },
            .jcc_rel32 => {
                const taken = evalCond(self.regs.rflags, d.cond);
                if (taken) {
                    self.regs.rip = x64_decoder.highway.relativeControl(.conditional_jump, self.regs.rip, d.len, @bitCast(d.imm), taken).target;
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
            .vpshufd => {
                // VPSHUFD: Shuffle packed dwords in xmm
                // For now, implement as a no-op since we don't have full SIMD execution
                // The instruction is decoded correctly, so execution can proceed
            },
            .vpmuludq,
            .vpblendw,
            .vpinsrd,
            .vpinsrq,
            .vpinsrw,
            .vpunpckhbw,
            .vpunpckhwd,
            .vpunpckhdq,
            .vpunpcklbw,
            .vpunpcklwd,
            .vpslld,
            .vpsllq,
            .vpsllw,
            .vpslldq,
            .vpsrld,
            .vpsrlq,
            .vpsrlw,
            .vpsrldq,
            .vpsubb,
            .vpsubd,
            .vpsubq,
            .vpsubw,
            .vpaddb,
            .vpaddd,
            .vpaddq,
            .vpaddw,
            .vpmullw,
            .add_accum_imm,
            .or_accum_imm,
            .adc_accum_imm,
            .sbb_accum_imm,
            .and_accum_imm,
            .sub_accum_imm,
            .xor_accum_imm,
            .cmp_accum_imm,
            .vmovdqu_xmm_xmm,
            .vmovdqu_xmm_mem,
            .vmovdqu_mem_xmm,
            .vmovdqa_xmm_xmm,
            .vmovdqa_xmm_mem,
            .vmovdqa_mem_xmm,
            .vmovups_xmm_xmm,
            .vmovups_xmm_mem,
            .vmovups_mem_xmm,
            .vmovaps_xmm_xmm,
            .vmovaps_xmm_mem,
            .vmovaps_mem_xmm,
            .vmovupd_xmm_xmm,
            .vmovupd_xmm_mem,
            .vmovupd_mem_xmm,
            .vmovapd_xmm_xmm,
            .vmovapd_xmm_mem,
            .vmovapd_mem_xmm,
            .vmovss_xmm_mem,
            .vmovss_mem_xmm,
            .vmovsd_xmm_mem,
            .vmovsd_mem_xmm,
            .vmovlps_xmm_xmm_mem64,
            .vmovlps_mem64_xmm,
            .vmovlpd_xmm_xmm_mem64,
            .vmovlpd_mem64_xmm,
            .vmovhps_xmm_xmm_mem64,
            .vmovhps_mem64_xmm,
            .vmovhpd_xmm_xmm_mem64,
            .vmovhpd_mem64_xmm,
            .vmovshdup,
            .vmovsldup,
            .vmovddup,
            .vmovdqu_ymm_ymm,
            .vmovdqu_ymm_mem,
            .vmovdqu_mem_ymm,
            .vmovdqa_ymm_ymm,
            .vmovdqa_ymm_mem,
            .vmovdqa_mem_ymm,
            .vmovups_ymm_ymm,
            .vmovups_ymm_mem,
            .vmovups_mem_ymm,
            .vmovaps_ymm_ymm,
            .vmovaps_ymm_mem,
            .vmovaps_mem_ymm,
            .vmovupd_ymm_ymm,
            .vmovupd_ymm_mem,
            .vmovupd_mem_ymm,
            .vmovapd_ymm_ymm,
            .vmovapd_ymm_mem,
            .vmovapd_mem_ymm,
            .vzeroupper,
            .pmovmskb,
            .vpmovmskb,
            .vpmovmskb_ymm,
            .vcvtsi2ss_xmm_reg,
            .vcvtsi2ss_xmm_mem,
            .vcvtsi2sd_xmm_reg,
            .vcvtsi2sd_xmm_mem,
            .vcvtss2sd,
            .vcvtsd2ss,
            .vaddss,
            .vaddsd,
            .vaddps,
            .vaddpd,
            .vmulss,
            .vmulsd,
            .vmulps,
            .vmulpd,
            .vsubss,
            .vsubsd,
            .vsubps,
            .vsubpd,
            .vdivss,
            .vdivsd,
            .vdivps,
            .vdivpd,
            .vucomiss,
            .vucomisd,
            .vroundss,
            .vroundsd,
            .vroundps,
            .vroundpd,
            .vcvttss2si,
            .vcvttsd2si,
            .vcvtss2si,
            .vcvtsd2si,
            .vandps,
            .vandpd,
            .vandnps,
            .vandnpd,
            .vorps,
            .vorpd,
            .vxorps,
            .vxorpd,
            .vpor,
            .vpand,
            .vpandn,
            .vpxor,
            .vpcmpeqb,
            .vpcmpeqw,
            .vpcmpeqd,
            .vpcmpeqq,
            .vpcmpgtb,
            .vpcmpgtw,
            .vpcmpgtd,
            .vpcmpgtq,
            .vptest,
            .vpunpckldq,
            .vpunpcklqdq,
            .vpunpckhqdq,
            .vmovhlps,
            .vmovlhps,
            .vmovmskps,
            .vmovmskpd,
            .vsqrtps,
            .vsqrtpd,
            .vsqrtss,
            .vsqrtsd,
            .vunpcklps,
            .vunpckhps,
            .vunpcklpd,
            .vunpckhpd,
            .vcvtps2pd,
            .vcvtpd2ps,
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
            .vextractf128,
            .vpextrb,
            .vpextrw,
            .vpextrd,
            .vpextrq,
            .vpminsb,
            .vpminsd,
            .vpminuw,
            .vpminud,
            .vpmaxsb,
            .vpmaxsd,
            .vpmaxuw,
            .vpmaxud,
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
            .vphminposuw,
            .vpsrlvd,
            .vpsravd,
            .vpsllvd,
            .vpblendvb,
            .vpalignr,
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
            .vrsqrtps,
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
            => unreachable,
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

    fn guestCString(self: *ElfState, addr: u64) ?[]const u8 {
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const rest = self.mem[off_usize..];
        const len = std.mem.indexOfScalar(u8, rest, 0) orelse return null;
        return rest[0..len];
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
        const path = self.guestCString(self.regs.rdi) orelse {
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
        const path = self.guestCString(self.regs.rdi) orelse {
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

fn shouldTraceRip(rip: u64) bool {
    const start_raw = std.c.getenv("ROSETTE_ELF_TRACE_START") orelse return false;
    const start = parseEnvU64(std.mem.sliceTo(start_raw, 0)) orelse return false;
    const end = if (std.c.getenv("ROSETTE_ELF_TRACE_END")) |end_raw|
        parseEnvU64(std.mem.sliceTo(end_raw, 0)) orelse start
    else
        start;
    return rip >= start and rip <= end;
}

fn parseEnvU64(text: []const u8) ?u64 {
    if (text.len >= 2 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X')) {
        return std.fmt.parseUnsigned(u64, text[2..], 16) catch null;
    }
    return std.fmt.parseUnsigned(u64, text, 10) catch null;
}

// ─── Decoder ───

fn rexW(rex: u8) bool {
    return rex & 0x08 != 0;
}

fn rexR(rex: u8) bool {
    return rex & 0x04 != 0;
}

fn rexB(rex: u8) bool {
    return rex & 0x01 != 0;
}

fn regId(code: u8, extended: bool) RegId {
    const value: u4 = @as(u4, @truncate(code)) | if (extended) @as(u4, 8) else @as(u4, 0);
    return @enumFromInt(value);
}

fn modRmReg(code: u8, rex: u8) RegId {
    return regId(code, rexR(rex));
}

fn modRmRm(code: u8, rex: u8) RegId {
    return regId(code, rexB(rex));
}

fn xmmRegIndex(code: u8, extended: bool) u8 {
    return (code & 7) | if (extended) @as(u8, 8) else @as(u8, 0);
}

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

fn readGroup3TestImm(bytes: []const u8, pos: *usize, size: Size) ?u64 {
    const imm_len: usize = switch (size) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32, .bits64 => 4,
    };
    if (pos.* + imm_len > bytes.len) return null;
    const imm = switch (size) {
        .bits8 => @as(u64, bytes[pos.*]),
        .bits16 => @as(u64, std.mem.readInt(u16, bytes[pos.*..][0..2], .little)),
        .bits32, .bits64 => @as(u64, std.mem.readInt(u32, bytes[pos.*..][0..4], .little)),
    };
    pos.* += imm_len;
    return imm;
}

const MemRef = struct {
    addr: u64,
    sib_has_index: bool,
    sib_index_reg: RegId,
    sib_scale: u2,
    sib_has_base: bool,
    sib_base_reg: RegId,
    rip_relative: bool,
};

fn parseModRmMemory(bytes: []const u8, pos: *usize, mod: u3, rm: u8, rex: u8) ?MemRef {
    const memory = x64_decoder.decodeMemoryOperand(bytes, pos, @truncate(mod), @truncate(rm), .{
        .rex = rex,
        .has_rex = rex != 0,
    }) orelse return null;
    return .{
        .addr = memory.displacement,
        .sib_has_index = memory.has_index,
        .sib_index_reg = memory.index_reg,
        .sib_scale = memory.scale,
        .sib_has_base = memory.has_base,
        .sib_base_reg = memory.base_reg,
        .rip_relative = memory.rip_relative,
    };
}

fn decodeInsn(bytes: []const u8) DecodedInsn {
    if (bytes.len == 0) return .{};

    // Check for VEX prefix first (C5 for 2-byte, C4 for 3-byte)
    if (bytes[0] == 0xC5 or bytes[0] == 0xC4) {
        if (x64_decoder.decodeVexInstruction(bytes)) |decoded| {
            return decoded;
        }
    }

    const prefixes = x64_decoder.decodeLegacyPrefixes(bytes);
    var pos = prefixes.len;
    const rex = prefixes.rex;
    const has_66 = prefixes.operand_size_override;
    const has_f3 = prefixes.repeat == .rep;

    if (pos >= bytes.len) return .{};

    const opcode = bytes[pos];
    pos += 1;

    const rex_w = rexW(rex);

    switch (opcode) {
        0xF5 => return DecodedInsn{ .op = .cmc, .len = @intCast(pos) },
        0xF8 => return DecodedInsn{ .op = .clc, .len = @intCast(pos) },
        0xF9 => return DecodedInsn{ .op = .stc, .len = @intCast(pos) },
        0x00...0x03 => {
            // ADD r/m, r or ADD r, r/m
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (d == 1) {
                    const dst_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    };
                } else {
                    const src_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_mem8_reg8, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_mem16_reg16, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_mem32_reg32, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_mem64_reg64, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    };
                }
            }

            if (mod == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .add_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .add_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .add_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .add_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x05 => {
            // ADD AX/EAX/RAX, imm16/imm32
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;
            const imm_len: usize = if (size == .bits16) 2 else 4;
            if (pos + imm_len > bytes.len) return .{};
            const imm = if (size == .bits16)
                @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
            else
                @as(u64, std.mem.readInt(u32, bytes[pos..][0..4], .little));
            pos += imm_len;
            return switch (size) {
                .bits16 => DecodedInsn{ .op = .add_reg16_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .add_reg32_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .add_reg64_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits8 => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            };
        },

        0x08...0x0B => {
            // OR r/m, r or OR r, r/m. The ELF runner currently executes
            // register destinations; memory destinations fail explicitly.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            if (d == 0 and mod_v != 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .or_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .or_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .or_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .or_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            if (d != 1) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return switch (size) {
                .bits8 => DecodedInsn{ .op = .or_reg8_mem8, .size = size, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                .bits16 => DecodedInsn{ .op = .or_reg16_mem16, .size = size, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .or_reg32_mem32, .size = size, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .or_reg64_mem64, .size = size, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
            };
        },

        0x24 => {
            // AND AL, imm8
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .and_reg8_imm8, .size = .bits8, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) };
        },

        0x25 => {
            // AND AX/EAX/RAX, imm16/imm32
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;
            const imm_len: usize = if (size == .bits16) 2 else 4;
            if (pos + imm_len > bytes.len) return .{};
            const imm = if (size == .bits16)
                @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
            else
                @as(u64, std.mem.readInt(u32, bytes[pos..][0..4], .little));
            pos += imm_len;
            return switch (size) {
                .bits16 => DecodedInsn{ .op = .and_reg16_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .and_reg32_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .and_reg64_imm32, .size = size, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) },
                .bits8 => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            };
        },

        0x18...0x1B => {
            // SBB r/m, r or SBB r, r/m. Register forms are enough for libc carry-mask idioms.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            if (mod_v != 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
            const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
            return switch (size) {
                .bits8 => DecodedInsn{ .op = .sbb_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits16 => DecodedInsn{ .op = .sbb_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .sbb_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .sbb_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
            };
        },

        0x20...0x23, 0x30...0x33 => {
            // AND/XOR r/m, r or r, r/m.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod_v != 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
            const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
            if (opcode >= 0x30) {
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .xor_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .xor_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .xor_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .xor_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }
            return switch (size) {
                .bits8 => DecodedInsn{ .op = .and_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits16 => DecodedInsn{ .op = .and_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .and_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .and_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
            };
        },
        0x34 => {
            // XOR AL, imm8
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .xor_reg8_imm8, .size = .bits8, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) };
        },
        0x3C => {
            // CMP AL, imm8
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .cmp_reg8_imm8, .size = .bits8, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) };
        },
        0x28...0x2B => {
            // SUB r/m, r or SUB r, r/m
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib_byte = bytes[pos];
                pos += 1;
                _ = (sib_byte >> 3) & 7;
                const sib_base = sib_byte & 7;
                if (sib_base == 5 and mod == 0 and d == 1) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    const dst_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .sub_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .sub_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .sub_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .sub_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                    };
                }
            }

            if (mod == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .sub_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .sub_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .sub_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .sub_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x38...0x3B => {
            // CMP r/m, r (38/39) or CMP r, r/m (3A/3B)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod_v == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .cmp_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .cmp_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .cmp_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .cmp_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (d == 0) {
                    // cmp r/m, r: source is reg, dst is [addr]
                    const src_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_mem8_reg8, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_mem16_reg16, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_mem32_reg32, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_mem64_reg64, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    };
                } else {
                    // cmp reg, r/m: dst is reg, source is [addr]
                    const dst_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    };
                }
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x63 => {
            // MOVSXD r64, r/m32 (only with REX.W)
            if (!rex_w) return .{};
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            if (mod_v == 3) {
                return DecodedInsn{
                    .op = .movsxd_reg64_reg32,
                    .dst_reg = modRmReg(reg, rex),
                    .src_reg = modRmRm(rm, rex),
                    .len = @intCast(pos),
                };
            }
            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = .movsxd_reg64_mem32, .size = .bits64, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0x50...0x57 => {
            // PUSH r64
            return DecodedInsn{
                .op = .push_reg,
                .size = .bits64,
                .src_reg = regId(opcode - 0x50, rexB(rex)),
                .len = @intCast(pos),
            };
        },

        0x58...0x5F => {
            // POP r64
            return DecodedInsn{
                .op = .pop_reg,
                .size = .bits64,
                .dst_reg = regId(opcode - 0x58, rexB(rex)),
                .len = @intCast(pos),
            };
        },

        0x68 => {
            // PUSH imm32, sign-extended to stack width.
            if (pos + 4 > bytes.len) return .{};
            const imm = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            return DecodedInsn{
                .op = .push_imm,
                .size = .bits64,
                .imm = @as(u64, @bitCast(@as(i64, imm))),
                .len = @intCast(pos),
            };
        },

        0x6B => {
            // IMUL r, r/m, imm8
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const dst_reg = modRmReg(reg, rex);
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            const size: Size = if (rex_w) .bits64 else .bits32;
            if (mod_v == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib = bytes[pos];
                pos += 1;
                const base = sib & 7;
                const sib_index = (sib >> 3) & 7;
                if (base == 5 and sib_index == 4) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    return switch (size) {
                        .bits32 => DecodedInsn{ .op = .imul_reg32_mem32_imm8, .size = size, .dst_reg = dst_reg, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_reg64_mem64_imm8, .size = size, .dst_reg = dst_reg, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                }
            } else if (mod_v == 3) {
                const src_reg = modRmRm(rm, rex);
                return switch (size) {
                    .bits32 => DecodedInsn{ .op = .imul_reg32_reg32_imm8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .imul_reg64_reg64_imm8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }
            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x6A => {
            // PUSH imm8, sign-extended to stack width.
            if (pos >= bytes.len) return .{};
            const imm = std.mem.readInt(i8, bytes[pos..][0..1], .little);
            pos += 1;
            return DecodedInsn{
                .op = .push_imm,
                .size = .bits64,
                .imm = @as(u64, @bitCast(@as(i64, imm))),
                .len = @intCast(pos),
            };
        },

        0x70...0x7F => {
            // Conditional jumps
            const cond: Cond = @enumFromInt(@as(u4, @truncate(opcode & 0x0F)));
            if (pos >= bytes.len) return .{};
            const rel = std.mem.readInt(i8, bytes[pos..][0..1], .little);
            pos += 1;
            return DecodedInsn{
                .op = .jcc_rel8,
                .cond = cond,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0x80 => {
            // Group 1: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP r/m8, imm8
            // /0 = ADD, /2 = ADC, /4 = AND, /5 = SUB, /6 = XOR, /7 = CMP
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;

            if (reg_field != 0 and reg_field != 2 and reg_field != 4 and reg_field != 5 and reg_field != 6 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                const dst_reg = modRmRm(rm, rex);
                return switch (reg_field) {
                    0 => DecodedInsn{ .op = .add_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    4 => DecodedInsn{ .op = .and_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    5 => DecodedInsn{ .op = .sub_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    6 => DecodedInsn{ .op = .xor_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    7 => DecodedInsn{ .op = .cmp_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                return switch (reg_field) {
                    0 => DecodedInsn{ .op = .add_mem8_imm8, .size = .bits8, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    5 => DecodedInsn{ .op = .sub_mem8_imm8, .size = .bits8, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    7 => DecodedInsn{ .op = .cmp_mem8_imm8, .size = .bits8, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x81 => {
            // Group 1 with imm16/32.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;
            if (reg_field != 0 and reg_field != 1 and reg_field != 5) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            const imm_len: usize = if (size == .bits16) 2 else 4;

            if (mod_v == 3) {
                if (pos + imm_len > bytes.len) return .{};
                const imm = if (size == .bits16)
                    @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
                else blk: {
                    const raw = std.mem.readInt(i32, bytes[pos..][0..4], .little);
                    break :blk if (size == .bits64) @as(u64, @bitCast(@as(i64, raw))) else @as(u64, @as(u32, @bitCast(raw)));
                };
                pos += imm_len;
                const dst_reg = modRmRm(rm, rex);
                if (reg_field == 0) {
                    return switch (size) {
                        .bits16 => DecodedInsn{ .op = .add_reg16_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_reg32_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_reg64_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits8 => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                }
                if (reg_field == 5) {
                    return switch (size) {
                        .bits16 => DecodedInsn{ .op = .sub_reg16_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .sub_reg32_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .sub_reg64_imm32, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                }
                return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            if (pos + imm_len > bytes.len) return .{};
            const imm = if (size == .bits16)
                @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
            else blk: {
                const raw = std.mem.readInt(i32, bytes[pos..][0..4], .little);
                break :blk if (size == .bits64) @as(u64, @bitCast(@as(i64, raw))) else @as(u64, @as(u32, @bitCast(raw)));
            };
            pos += imm_len;
            return switch (reg_field) {
                1 => switch (size) {
                    .bits16 => DecodedInsn{ .op = .or_mem16_imm32, .size = size, .imm = imm, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .or_mem32_imm32, .size = size, .imm = imm, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .or_mem64_imm32, .size = size, .imm = imm, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits8 => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                },
                else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            };
        },

        0x83 => {
            // Group 1: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP with imm8 sign-extended
            // /0 = ADD, /2 = ADC, /4 = AND, /5 = SUB, /6 = XOR, /7 = CMP
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (reg_field != 0 and reg_field != 2 and reg_field != 4 and reg_field != 5 and reg_field != 6 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                const dst_reg = modRmRm(rm, rex);
                return switch (reg_field) {
                    0 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    2 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .adc_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .adc_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .adc_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .adc_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    4 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .and_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .and_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .and_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .and_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    5 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .sub_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .sub_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .sub_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .sub_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    6 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .xor_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .xor_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .xor_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .xor_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                return switch (reg_field) {
                    0 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_mem8_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_mem16_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_mem32_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_mem64_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    },
                    1 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .or_mem8_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .or_mem16_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .or_mem32_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .or_mem64_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_mem8_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_mem16_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_mem32_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_mem64_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .rip_relative = sib_info.rip_relative, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0xC0, 0xC1 => {
            // Group 2, count in imm8. /4 = SHL/SAL, /5 = SHR, /7 = SAR.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (reg_field != 4 and reg_field != 5 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                return DecodedInsn{
                    .op = switch (reg_field) {
                        4 => .shl_reg_imm,
                        5 => .shr_reg_imm,
                        else => .sar_reg_imm,
                    },
                    .size = size,
                    .dst_reg = modRmRm(rm, rex),
                    .imm = imm,
                    .len = @intCast(pos),
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = switch (reg_field) {
                4 => .shl_mem_imm,
                5 => .shr_mem_imm,
                else => .sar_mem_imm,
            }, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0xD0, 0xD1 => {
            // Group 2, implicit count 1. /4 = SHL/SAL, /5 = SHR, /7 = SAR.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (reg_field != 4 and reg_field != 5 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                return DecodedInsn{
                    .op = switch (reg_field) {
                        4 => .shl_reg_imm,
                        5 => .shr_reg_imm,
                        else => .sar_reg_imm,
                    },
                    .size = size,
                    .dst_reg = modRmRm(rm, rex),
                    .imm = 1,
                    .len = @intCast(pos),
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = switch (reg_field) {
                4 => .shl_mem_imm,
                5 => .shr_mem_imm,
                else => .sar_mem_imm,
            }, .size = size, .addr = mem.addr, .imm = 1, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0xD3 => {
            // Group 2, count in CL. /4 = SHL/SAL r/m16/32/64, CL.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (reg_field != 4) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                return DecodedInsn{
                    .op = .shl_reg_cl,
                    .size = size,
                    .dst_reg = modRmRm(rm, rex),
                    .len = @intCast(pos),
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = .shl_mem_cl, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0x84, 0x85 => {
            // TEST r/m, r
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            const src_reg = modRmReg(reg, rex);
            if (mod_v != 3) {
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .test_mem8_reg8, .size = size, .src_reg = src_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .test_mem16_reg16, .size = size, .src_reg = src_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .test_mem32_reg32, .size = size, .src_reg = src_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .test_mem64_reg64, .size = size, .src_reg = src_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                };
            }
            const dst_reg = modRmRm(rm, rex);
            return switch (size) {
                .bits8 => DecodedInsn{ .op = .test_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits16 => DecodedInsn{ .op = .test_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits32 => DecodedInsn{ .op = .test_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .test_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
            };
        },

        0x87 => {
            // XCHG r/m16/32/64, r16/32/64.
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (rex_w) .bits64 else .bits32;
            if (has_66 or mod_v == 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return switch (size) {
                .bits32 => DecodedInsn{ .op = .xchg_mem32_reg32, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                .bits64 => DecodedInsn{ .op = .xchg_mem64_reg64, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            };
        },

        0x88...0x8B, 0xA0...0xA3 => return x64_decoder.decodeLegacyMov(bytes, &pos, prefixes, opcode) orelse .{ .len = @intCast(pos) },

        0x8D => {
            // LEA r, m
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            if (mod_v == 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = .lea_reg_mem, .size = if (rex_w) .bits64 else .bits32, .dst_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0x8F => {
            // POP r/m64 (Group 1, /0)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;

            if (reg_field != 0) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                return DecodedInsn{
                    .op = .pop_reg,
                    .size = .bits64,
                    .dst_reg = modRmRm(rm, rex),
                    .len = @intCast(pos),
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = .pop_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
        },

        0x90 => {
            return DecodedInsn{ .op = .nop, .len = @intCast(pos) };
        },

        0x98 => {
            // CBW/CWDE/CDQE
            if (rex_w) {
                // CDQE (RAX = sign-extend EAX)
                return DecodedInsn{ .op = .cdqe, .len = @intCast(pos) };
            } else if (has_66) {
                // CBW (AX = sign-extend AL)
                return DecodedInsn{ .op = .cbw, .len = @intCast(pos) };
            } else {
                // CWDE (EAX = sign-extend AX)
                return DecodedInsn{ .op = .cwde, .len = @intCast(pos) };
            }
        },

        0x99 => {
            // CWD/CDQ/CQO
            if (rex_w) {
                // CQO (RDX:RAX = sign-extend RAX)
                return DecodedInsn{ .op = .cqo, .len = @intCast(pos) };
            } else if (has_66) {
                // CWD (DX:AX = sign-extend AX)
                return DecodedInsn{ .op = .cwd, .len = @intCast(pos) };
            } else {
                // CDQ (EDX:EAX = sign-extend EAX)
                return DecodedInsn{ .op = .cdq, .len = @intCast(pos) };
            }
        },

        0xA8 => {
            // TEST AL, imm8
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .test_reg8_imm8, .size = .bits8, .dst_reg = .al_ax_eax_rax, .imm = imm, .len = @intCast(pos) };
        },

        0xB0...0xBF, 0xC6, 0xC7 => return x64_decoder.decodeLegacyMov(bytes, &pos, prefixes, opcode) orelse .{ .len = @intCast(pos) },

        0xC3 => {
            // RET near
            return DecodedInsn{ .op = .ret, .len = @intCast(pos) };
        },

        0xE8 => {
            // CALL rel32
            if (pos + 4 > bytes.len) return .{};
            const rel = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            return DecodedInsn{
                .op = .call_rel32,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0xE9 => {
            // JMP rel32
            if (pos + 4 > bytes.len) return .{};
            const rel = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            return DecodedInsn{
                .op = .jmp_rel8,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0xEB => {
            // JMP short rel8
            if (pos >= bytes.len) return .{};
            const rel = std.mem.readInt(i8, bytes[pos..][0..1], .little);
            pos += 1;
            return DecodedInsn{
                .op = .jmp_rel8,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0xF4 => {
            return DecodedInsn{ .op = .hlt, .len = @intCast(pos) };
        },

        0xFF => {
            // Group 5: INC / DEC / CALL / CALLF / JMP / JMPF / PUSH
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (reg_field == 0 or reg_field == 1) {
                const is_inc = reg_field == 0;
                if (mod_v == 3) {
                    const dst_reg = modRmRm(rm, rex);
                    return if (is_inc) switch (size) {
                        .bits8 => DecodedInsn{ .op = .inc_reg8, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .inc_reg16, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .inc_reg32, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .inc_reg64, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                    } else switch (size) {
                        .bits8 => DecodedInsn{ .op = .dec_reg8, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .dec_reg16, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .dec_reg32, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .dec_reg64, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return if (is_inc) switch (size) {
                    .bits8 => DecodedInsn{ .op = .inc_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .inc_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .inc_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .inc_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                } else switch (size) {
                    .bits8 => DecodedInsn{ .op = .dec_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .dec_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .dec_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .dec_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                };
            }

            if (reg_field == 2) {
                if (mod_v == 3) {
                    return DecodedInsn{
                        .op = .call_reg64,
                        .size = .bits64,
                        .src_reg = modRmRm(rm, rex),
                        .len = @intCast(pos),
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return DecodedInsn{ .op = .call_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
            }

            if (reg_field == 4) {
                if (mod_v == 3) {
                    return DecodedInsn{
                        .op = .jmp_reg64,
                        .size = .bits64,
                        .src_reg = modRmRm(rm, rex),
                        .len = @intCast(pos),
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return DecodedInsn{ .op = .jmp_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
            }

            if (reg_field == 6) {
                if (mod_v == 3) {
                    return DecodedInsn{
                        .op = .push_reg,
                        .size = .bits64,
                        .src_reg = modRmRm(rm, rex),
                        .len = @intCast(pos),
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return DecodedInsn{ .op = .push_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0xF6, 0xF7 => {
            // Group 3: TEST / NOT / NEG / MUL / IMUL / DIV / IDIV
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod_v != 3) {
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (reg_field) {
                    0 => {
                        const imm = readGroup3TestImm(bytes, &pos, size) orelse return .{};
                        return switch (size) {
                            .bits8 => DecodedInsn{ .op = .test_mem8_imm8, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                            .bits16 => DecodedInsn{ .op = .test_mem16_imm16, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                            .bits32 => DecodedInsn{ .op = .test_mem32_imm32, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .test_mem64_imm32, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        };
                    },
                    2 => DecodedInsn{
                        .op = @enumFromInt(@intFromEnum(Op.not_mem8) + @intFromEnum(size) - @intFromEnum(Size.bits8)),
                        .size = size,
                        .addr = mem.addr,
                        .sib_has_index = mem.sib_has_index,
                        .sib_index_reg = mem.sib_index_reg,
                        .sib_scale = mem.sib_scale,
                        .sib_has_base = mem.sib_has_base,
                        .sib_base_reg = mem.sib_base_reg,
                        .rip_relative = mem.rip_relative,
                        .len = @intCast(pos),
                    },
                    3 => DecodedInsn{
                        .op = @enumFromInt(@intFromEnum(Op.neg_mem8) + @intFromEnum(size) - @intFromEnum(Size.bits8)),
                        .size = size,
                        .addr = mem.addr,
                        .sib_has_index = mem.sib_has_index,
                        .sib_index_reg = mem.sib_index_reg,
                        .sib_scale = mem.sib_scale,
                        .sib_has_base = mem.sib_has_base,
                        .sib_base_reg = mem.sib_base_reg,
                        .rip_relative = mem.rip_relative,
                        .len = @intCast(pos),
                    },
                    4 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .mul_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .mul_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .mul_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .mul_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    },
                    5 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .imul_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .imul_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .imul_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    },
                    6 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .div_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .div_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .div_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .div_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .idiv_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .idiv_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .idiv_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .idiv_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            } else {
                // Register form: Group 3 with register operand
                const src_reg = modRmRm(rm, rex);
                return switch (reg_field) {
                    0 => {
                        const imm = readGroup3TestImm(bytes, &pos, size) orelse return .{};
                        return switch (size) {
                            .bits8 => DecodedInsn{ .op = .test_reg8_imm8, .size = size, .dst_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                            .bits16 => DecodedInsn{ .op = .test_reg16_imm16, .size = size, .dst_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                            .bits32 => DecodedInsn{ .op = .test_reg32_imm32, .size = size, .dst_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .test_reg64_imm32, .size = size, .dst_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                        };
                    },
                    2 => DecodedInsn{
                        .op = @enumFromInt(@intFromEnum(Op.not_reg8) + @intFromEnum(size) - @intFromEnum(Size.bits8)),
                        .size = size,
                        .dst_reg = src_reg,
                        .len = @intCast(pos),
                    },
                    3 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .neg_reg8, .size = size, .dst_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .neg_reg16, .size = size, .dst_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .neg_reg32, .size = size, .dst_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .neg_reg64, .size = size, .dst_reg = src_reg, .len = @intCast(pos) },
                    },
                    4 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .mul_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .mul_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .mul_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .mul_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    5 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .imul_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .imul_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .imul_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    6 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .div_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .div_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .div_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .div_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .idiv_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .idiv_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .idiv_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .idiv_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }
        },

        0x0F => {
            if (pos >= bytes.len) return .{};
            const op2 = bytes[pos];
            pos += 1;

            switch (op2) {
                0x05 => {
                    return DecodedInsn{ .op = .syscall, .len = @intCast(pos) };
                },
                0x1F => {
                    // Multi-byte NOP: 0F 1F /0, often with 66/2E prefixes.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg_field = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    if (reg_field != 0) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    if (mod_v != 3) {
                        _ = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    }
                    return DecodedInsn{ .op = .nop, .len = @intCast(pos) };
                },
                0x10, 0x11, 0x28, 0x29 => {
                    // MOVUPS/MOVAPS xmm, xmm/m128 or xmm/m128, xmm.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const reg_index = xmmRegIndex(reg, rexR(rex));
                    if (op2 == 0x10 or op2 == 0x28) {
                        if (mod_v == 3) {
                            return DecodedInsn{ .op = .movaps_xmm_xmm, .xmm_dst = reg_index, .xmm_src = xmmRegIndex(rm, rexB(rex)), .len = @intCast(pos) };
                        }
                        const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                        return DecodedInsn{ .op = .movaps_xmm_mem, .addr = mem.addr, .xmm_dst = reg_index, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                    }

                    if (mod_v == 3) {
                        return DecodedInsn{ .op = .movaps_xmm_xmm, .xmm_dst = xmmRegIndex(rm, rexB(rex)), .xmm_src = reg_index, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movaps_mem_xmm, .addr = mem.addr, .xmm_src = reg_index, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0x40...0x4F => {
                    // CMOVcc r16/32/64, r/m16/32/64.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;
                    const dst_reg = modRmReg(reg, rex);
                    const cond: Cond = @enumFromInt(@as(u4, @truncate(op2 & 0x0F)));

                    if (mod_v == 3) {
                        return DecodedInsn{
                            .op = .cmovcc_reg_reg,
                            .size = size,
                            .dst_reg = dst_reg,
                            .src_reg = modRmRm(rm, rex),
                            .cond = cond,
                            .len = @intCast(pos),
                        };
                    }

                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .cmovcc_reg_mem, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .cond = cond, .len = @intCast(pos) };
                },
                0x80...0x8F => {
                    // Jcc rel32
                    if (pos + 4 > bytes.len) return .{};
                    const rel = std.mem.readInt(i32, bytes[pos..][0..4], .little);
                    pos += 4;
                    return DecodedInsn{
                        .op = .jcc_rel8,
                        .cond = @enumFromInt(@as(u4, @truncate(op2 & 0x0F))),
                        .imm = @as(u64, @bitCast(@as(i64, rel))),
                        .len = @intCast(pos),
                    };
                },
                0x90...0x9F => {
                    // SETcc r/m8.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const rm = modrm & 7;
                    const cond: Cond = @enumFromInt(@as(u4, @truncate(op2 & 0x0F)));
                    if (mod_v == 3) {
                        return DecodedInsn{
                            .op = .setcc_reg8,
                            .size = .bits8,
                            .dst_reg = modRmRm(rm, rex),
                            .cond = cond,
                            .len = @intCast(pos),
                        };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .setcc_mem8, .size = .bits8, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .cond = cond, .len = @intCast(pos) };
                },
                0xAF => {
                    // IMUL r, r/m
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;

                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return switch (size) {
                            .bits32 => DecodedInsn{ .op = .imul_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .imul_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                            else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                        };
                    }

                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return switch (size) {
                        .bits32 => DecodedInsn{ .op = .imul_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                },
                0xB8 => {
                    // POPCNT r16/32/64, r/m16/32/64. F3 is a mandatory
                    // instruction prefix rather than a repeat modifier.
                    if (!has_f3 or pos >= bytes.len) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const size: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
                    const dst_reg = modRmReg(reg, rex);

                    if (mod_v == 3) {
                        return DecodedInsn{
                            .op = .popcnt_reg_reg,
                            .size = size,
                            .dst_reg = dst_reg,
                            .src_reg = modRmRm(rm, rex),
                            .len = @intCast(pos),
                        };
                    }

                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .popcnt_reg_mem, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0xBC, 0xBD => {
                    // BSF/BSR and their F3-prefixed TZCNT/LZCNT forms.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const size: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
                    const dst_reg = modRmReg(reg, rex);
                    const register_op: Op = if (has_f3)
                        if (op2 == 0xBC) .tzcnt_reg_reg else .lzcnt_reg_reg
                    else if (op2 == 0xBC)
                        .bsf_reg_reg
                    else
                        .bsr_reg_reg;
                    const memory_op: Op = if (has_f3)
                        if (op2 == 0xBC) .tzcnt_reg_mem else .lzcnt_reg_mem
                    else if (op2 == 0xBC)
                        .bsf_reg_mem
                    else
                        .bsr_reg_mem;

                    if (mod_v == 3) {
                        return DecodedInsn{
                            .op = register_op,
                            .size = size,
                            .dst_reg = dst_reg,
                            .src_reg = modRmRm(rm, rex),
                            .len = @intCast(pos),
                        };
                    }

                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = memory_op, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0xC8...0xCF => {
                    if (has_66) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{
                        .op = .bswap_reg,
                        .size = if (rex_w) .bits64 else .bits32,
                        .dst_reg = regId(op2 - 0xC8, rexB(rex)),
                        .len = @intCast(pos),
                    };
                },
                0x57 => {
                    // XORPS xmm, xmm/m128. Register form is used as a fast
                    // zeroing idiom: xorps xmm0, xmm0.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    if (mod_v != 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .xorps_xmm_xmm, .xmm_dst = xmmRegIndex(reg, rexR(rex)), .xmm_src = xmmRegIndex(rm, rexB(rex)), .len = @intCast(pos) };
                },
                0xB0, 0xB1 => {
                    // CMPXCHG r/m8,r8 (0F B0) or r/m16/32/64,r16/32/64
                    // (0F B1). libc++ uses the byte form for lock-free enum
                    // atomics, including Xenia's timer queue state.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const size: Size = if (op2 == 0xB0)
                        .bits8
                    else if (rex_w)
                        .bits64
                    else if (has_66)
                        .bits16
                    else
                        .bits32;
                    if (mod_v == 3) {
                        return DecodedInsn{
                            .op = switch (size) {
                                .bits8 => .cmpxchg_reg8_reg8,
                                .bits16 => .cmpxchg_reg16_reg16,
                                .bits32 => .cmpxchg_reg32_reg32,
                                .bits64 => .cmpxchg_reg64_reg64,
                            },
                            .size = size,
                            .src_reg = modRmReg(reg, rex),
                            .dst_reg = regId(rm, rexB(rex)),
                            .is_reg_form = true,
                            .len = @intCast(pos),
                        };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmpxchg_mem8_reg8, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmpxchg_mem16_reg16, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmpxchg_mem32_reg32, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmpxchg_mem64_reg64, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                    };
                },
                0xC1 => {
                    // XADD r/m32/64, r32/64. C++ runtime startup paths often
                    // use LOCK XADDL against RIP-relative guard counters.
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (has_66 or mod_v == 3) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return switch (size) {
                        .bits32 => DecodedInsn{ .op = .xadd_mem32_reg32, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .xadd_mem64_reg64, .size = size, .src_reg = modRmReg(reg, rex), .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                },
                0xB6 => {
                    // MOVZX r32, r/m8
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movzx_reg32_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movzx_reg32_mem8, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0xB7 => {
                    // MOVZX r32, r/m16
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movzx_reg32_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movzx_reg32_mem16, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0xBE => {
                    // MOVSX r32, r/m8
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movsx_reg32_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movsx_reg32_mem8, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                0xBF => {
                    // MOVSX r32, r/m16
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movsx_reg32_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movsx_reg32_mem16, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .rip_relative = mem.rip_relative, .len = @intCast(pos) };
                },
                else => return DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            }
        },

        else => return DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
    }
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
    try testing.expectEqual(Op.movaps_xmm_mem, load_unaligned.op);
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
