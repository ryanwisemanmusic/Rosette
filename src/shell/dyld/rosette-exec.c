// rosette-exec.c - DYLD interposition library for x86-64 Linux ELF execution.
//
// When an x86-64 Linux ELF binary is exec'd on ARM macOS, this library
// intercepts execve and routes the binary through Rosette's elf_processor.
//
// Build:
//   zig cc -dynamiclib -arch arm64 \
//     -o rosette-exec.dylib rosette-exec.c \
//     -install_name @rpath/rosette-exec.dylib \
//     -current_version 1.0 -compatibility_version 1.0
//
// Install in .zshrc:
//   export DYLD_INSERT_LIBRARIES="$HOME/.rosette/lib/rosette-exec.dylib"
//   export ROSETTE_ELF_PROCESSOR="$HOME/.rosette/bin/elf_processor"

#include <dlfcn.h>
#include <unistd.h>
#include <string.h>
#include <strings.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <spawn.h>

// ── DYLD interpose macro ──────────────────────────────────────────────
#define DYLD_INTERPOSE(_replacement, _replacee)                         \
    __attribute__((used)) static struct {                                \
        const void *replacement;                                         \
        const void *replacee;                                            \
    } _interpose_##_replacee                                             \
    __attribute__((section("__DATA,__interpose"))) = {                   \
        (const void *)(unsigned long)&_replacement,                      \
        (const void *)(unsigned long)&_replacee,                         \
    };

// ── Forward declarations ──────────────────────────────────────────────
static int my_execve(const char *path, char *const argv[], char *const envp[]);
static int my_posix_spawn(pid_t *pid, const char *path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attrp,
    char *const argv[], char *const envp[]);
static int my_posix_spawnp(pid_t *pid, const char *file,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attrp,
    char *const argv[], char *const envp[]);
DYLD_INTERPOSE(my_execve, execve);
DYLD_INTERPOSE(my_posix_spawn, posix_spawn);
DYLD_INTERPOSE(my_posix_spawnp, posix_spawnp);

// ── Original function pointers ────────────────────────────────────────
typedef int (*execve_func_t)(const char *, char *const [], char *const []);
typedef int (*posix_spawn_func_t)(pid_t *, const char *,
    const posix_spawn_file_actions_t *,
    const posix_spawnattr_t *,
    char *const [], char *const []);
static execve_func_t real_execve = NULL;
static posix_spawn_func_t real_posix_spawn = NULL;
static posix_spawn_func_t real_posix_spawnp = NULL;

// ── ELF detection ─────────────────────────────────────────────────────
// Check if `path` points to an x86-64 Linux ELF executable.
// Returns 1 if yes, 0 if no or on error.
static uint32_t read_u32_le(const unsigned char *buf) {
    return ((uint32_t)buf[0]) |
        ((uint32_t)buf[1] << 8) |
        ((uint32_t)buf[2] << 16) |
        ((uint32_t)buf[3] << 24);
}

static uint32_t read_u32_be(const unsigned char *buf) {
    return ((uint32_t)buf[0] << 24) |
        ((uint32_t)buf[1] << 16) |
        ((uint32_t)buf[2] << 8) |
        ((uint32_t)buf[3]);
}

static int env_enabled(const char *name) {
    const char *value = getenv(name);
    if (!value || !*value) return 0;
    return strcmp(value, "1") == 0 ||
        strcasecmp(value, "true") == 0 ||
        strcasecmp(value, "yes") == 0 ||
        strcasecmp(value, "on") == 0 ||
        strcasecmp(value, "enabled") == 0;
}

static int is_x86_64_macho_thin(const char *path) {
    if (!path) return 0;

    unsigned char buf[32];
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    ssize_t n = read(fd, buf, sizeof(buf));
    close(fd);
    if (n < 8) return 0;

    const uint32_t magic_le = read_u32_le(buf);
    const uint32_t magic_be = read_u32_be(buf);
    uint32_t cputype = 0;
    if (magic_le == 0xFEEDFACF) {
        cputype = read_u32_le(buf + 4);
    } else if (magic_be == 0xFEEDFACF) {
        cputype = read_u32_be(buf + 4);
    } else {
        return 0;
    }

    // CPU_TYPE_X86_64 = CPU_TYPE_X86 | CPU_ARCH_ABI64 = 0x01000007.
    return cputype == 0x01000007;
}

static int is_x86_64_elf(const char *path) {
    if (!path) return 0;

    unsigned char buf[20];
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    ssize_t n = read(fd, buf, sizeof(buf));
    close(fd);
    if (n < (ssize_t)sizeof(buf)) return 0;

    // ELF magic: 0x7f, 'E', 'L', 'F'
    if (buf[0] != 0x7F || buf[1] != 'E' || buf[2] != 'L' || buf[3] != 'F')
        return 0;
    // EI_CLASS = 2 (ELFCLASS64), EI_DATA = 1 (ELFDATA2LSB)
    if (buf[4] != 2 || buf[5] != 1)
        return 0;
    // e_type at offset 16: ET_EXEC (2) or ET_DYN (3, PIE)
    uint16_t e_type = (uint16_t)buf[0x10] | ((uint16_t)buf[0x11] << 8);
    if (e_type != 2 && e_type != 3)
        return 0;
    // e_machine at offset 18: EM_X86_64 = 62
    uint16_t e_machine = (uint16_t)buf[0x12] | ((uint16_t)buf[0x13] << 8);
    return (e_machine == 62) ? 1 : 0;
}

static int maybe_block_x86_64_macho(const char *path) {
    if (!env_enabled("ROSETTE_MACHO_STRICT")) return 0;
    if (!path || !is_x86_64_macho_thin(path)) return 0;

    const char *trace_path = getenv("ROSETTE_COMPAT_TRACE");
    if (trace_path && *trace_path) {
        FILE *fp = fopen(trace_path, "ab");
        if (fp) {
            fprintf(fp,
                "# Rosette exec interpose\n"
                "event = \"blocked_x86_64_macho_exec\"\n"
                "path = \"%s\"\n\n",
                path);
            fclose(fp);
        }
    }

    fprintf(stderr,
        "rosette-exec: blocked x86_64 Mach-O launch without Apple Rosetta 2 fallback: %s\n"
        "rosette-exec: Mach-O x86_64 execution backend is not implemented yet.\n",
        path);
    errno = ENOEXEC;
    return 1;
}

// ── elf_processor path resolution ─────────────────────────────────────
// Find the elf_processor binary. Checks:
//   1. ROSETTE_ELF_PROCESSOR env var
//   2. ~/.rosette/bin/elf_processor
//   3. "elf_processor" (let PATH handle it, may fail)
static const char *elf_processor_path(void) {
    const char *env = getenv("ROSETTE_ELF_PROCESSOR");
    if (env && access(env, X_OK) == 0)
        return env;

    const char *home = getenv("HOME");
    if (home) {
        static char path[1024];
        int len = snprintf(path, sizeof(path),
            "%s/.rosette/bin/elf_processor", home);
        if (len > 0 && (size_t)len < sizeof(path) && access(path, X_OK) == 0)
            return path;
    }

    return "elf_processor";
}

static char **build_redirect_argv(const char *proc, const char *path, char *const argv[]) {
    int argc = 0;
    while (argv && argv[argc]) argc++;

    char **new_argv = malloc((size_t)(argc + 3) * sizeof(char *));
    if (!new_argv)
        return NULL;

    new_argv[0] = strdup(proc);
    new_argv[1] = strdup(path);
    if (!new_argv[0] || !new_argv[1]) {
        free(new_argv[0]);
        free(new_argv[1]);
        free(new_argv);
        return NULL;
    }

    for (int i = 0; i < argc; i++)
        new_argv[i + 2] = argv[i];
    new_argv[argc + 2] = NULL;
    return new_argv;
}

static void free_redirect_argv(char **argv) {
    if (!argv)
        return;
    free(argv[0]);
    free(argv[1]);
    free(argv);
}

// ── execve interposition ──────────────────────────────────────────────
static int my_execve(const char *path, char *const argv[], char *const envp[]) {
    if (!real_execve)
        real_execve = (execve_func_t)dlsym(RTLD_NEXT, "execve");

    if (maybe_block_x86_64_macho(path)) {
        return -1;
    }

    if (path && is_x86_64_elf(path)) {
        const char *proc = elf_processor_path();

        // If elf_processor is not accessible, show a clear error
        if (access(proc, X_OK) != 0) {
            fprintf(stderr,
                "rosette-exec: x86-64 ELF binary detected at '%s'\n"
                "rosette-exec: but elf_processor not found at '%s'\n"
                "rosette-exec: Install Rosette with: rosette-shell install\n",
                path, proc);
            _exit(127);
        }

        // Build new argv: [proc, path, argv[0], ..., argv[N-1], NULL]
        char **new_argv = build_redirect_argv(proc, path, argv);
        if (!new_argv) {
            fprintf(stderr, "rosette-exec: out of memory\n");
            _exit(127);
        }

        // Attempt redirected execution. On success, execve does not return.
        int result = real_execve(proc, (char *const *)new_argv, envp);

        // Only reached if execve failed
        fprintf(stderr, "rosette-exec: failed to execute '%s': %s\n",
            proc, strerror(errno));
        free_redirect_argv(new_argv);
        _exit(127);
    }

    return real_execve(path, argv, envp);
}

static int my_posix_spawn(pid_t *pid, const char *path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attrp,
    char *const argv[], char *const envp[]) {
    if (!real_posix_spawn)
        real_posix_spawn = (posix_spawn_func_t)dlsym(RTLD_NEXT, "posix_spawn");

    if (maybe_block_x86_64_macho(path)) {
        return ENOEXEC;
    }

    if (path && is_x86_64_elf(path)) {
        const char *proc = elf_processor_path();

        if (access(proc, X_OK) != 0) {
            fprintf(stderr,
                "rosette-exec: x86-64 ELF binary detected at '%s'\n"
                "rosette-exec: but elf_processor not found at '%s'\n",
                path, proc);
            return ENOENT;
        }

        char **new_argv = build_redirect_argv(proc, path, argv);
        if (!new_argv)
            return ENOMEM;

        int result = real_posix_spawn(pid, proc, file_actions, attrp,
            (char *const *)new_argv, envp);
        free_redirect_argv(new_argv);
        return result;
    }

    return real_posix_spawn(pid, path, file_actions, attrp, argv, envp);
}

static int my_posix_spawnp(pid_t *pid, const char *file,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attrp,
    char *const argv[], char *const envp[]) {
    if (!real_posix_spawnp)
        real_posix_spawnp = (posix_spawn_func_t)dlsym(RTLD_NEXT, "posix_spawnp");

    if (maybe_block_x86_64_macho(file)) {
        return ENOEXEC;
    }

    if (file && is_x86_64_elf(file)) {
        const char *proc = elf_processor_path();

        if (access(proc, X_OK) != 0) {
            fprintf(stderr,
                "rosette-exec: x86-64 ELF binary detected at '%s'\n"
                "rosette-exec: but elf_processor not found at '%s'\n",
                file, proc);
            return ENOENT;
        }

        char **new_argv = build_redirect_argv(proc, file, argv);
        if (!new_argv)
            return ENOMEM;

        int result = real_posix_spawnp(pid, proc, file_actions, attrp,
            (char *const *)new_argv, envp);
        free_redirect_argv(new_argv);
        return result;
    }

    return real_posix_spawnp(pid, file, file_actions, attrp, argv, envp);
}
