#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_SUITES 256
#define MAX_NAME 256
#define MAX_PATH_LEN 4096

#define DEFAULT_CFLAGS "-Wall -Wextra -Wno-ignored-attributes"

typedef enum {
    GROUP_UNIT = 0,
    GROUP_APP = 1,
    GROUP_THIRD = 2,
} SuiteGroup;

typedef struct {
    char name[MAX_NAME];
    char path[MAX_PATH_LEN];
    SuiteGroup group;
} Suite;

typedef struct {
    char cc[MAX_NAME];
    char kind[32];
    char entry[512];
    char cflags[512];
    char ldflags[512];
    char link_zig[32];
    char link_cli[32];
    char interactive[32];
    char sources[512];
    char asm_family[64];
    char asm_runtime[64];
    char asm_source[512];
    char asm_invoked[32];
    char asm_tool[64];
    char asm_format[64];
    char asm_required[32];
} SuiteConfig;

static Suite suites[MAX_SUITES];
static size_t suite_count = 0;

static int is_dir(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode);
}

static int has_source_files(const char *dir_path) {
    DIR *dir = opendir(dir_path);
    if (!dir) return 0;
    struct dirent *ent;
    int found = 0;
    while ((ent = readdir(dir)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        const char *ext = strrchr(ent->d_name, '.');
        if (!ext) continue;
        if (strcmp(ext, ".c") == 0 || strcmp(ext, ".cpp") == 0) {
            found = 1;
            break;
        }
    }
    closedir(dir);
    return found;
}

static int has_suite_cfg(const char *dir_path) {
    char cfg[MAX_PATH_LEN];
    snprintf(cfg, sizeof(cfg), "%s/suite.cfg", dir_path);
    return access(cfg, R_OK) == 0;
}

static void add_suite(const char *name, const char *path, SuiteGroup group) {
    if (suite_count >= MAX_SUITES) return;
    snprintf(suites[suite_count].name, sizeof(suites[suite_count].name), "%s", name);
    snprintf(suites[suite_count].path, sizeof(suites[suite_count].path), "%s", path);
    suites[suite_count].group = group;
    suite_count++;
}

static void discover_group(const char *root, const char *subdir, SuiteGroup group) {
    char base[MAX_PATH_LEN];
    snprintf(base, sizeof(base), "%s/%s", root, subdir);
    if (!is_dir(base)) return;

    struct dirent **namelist = NULL;
    int n = scandir(base, &namelist, NULL, alphasort);
    if (n < 0) return;
    for (int i = 0; i < n; i++) {
        struct dirent *ent = namelist[i];
        if (ent->d_name[0] == '.') {
            free(ent);
            continue;
        }
        char full[MAX_PATH_LEN];
        snprintf(full, sizeof(full), "%s/%s", base, ent->d_name);
        if (is_dir(full) && (has_source_files(full) || has_suite_cfg(full))) {
            add_suite(ent->d_name, full, group);
        }
        free(ent);
    }
    free(namelist);
}

static void discover_third_party_at(const char *base, const char *label_prefix) {
    if (!is_dir(base)) return;

    struct dirent **libs = NULL;
    int n = scandir(base, &libs, NULL, alphasort);
    if (n < 0) return;
    for (int i = 0; i < n; i++) {
        struct dirent *ent = libs[i];
        if (ent->d_name[0] == '.') {
            free(ent);
            continue;
        }
        char test_dir[MAX_PATH_LEN];
        snprintf(test_dir, sizeof(test_dir), "%s/%s/test", base, ent->d_name);
        if (is_dir(test_dir) && has_source_files(test_dir)) {
            char name[MAX_NAME];
            if (label_prefix[0] != '\0')
                snprintf(name, sizeof(name), "%s:%s /test", label_prefix, ent->d_name);
            else
                snprintf(name, sizeof(name), "%s /test", ent->d_name);
            add_suite(name, test_dir, GROUP_THIRD);
        }
        free(ent);
    }
    free(libs);
}

static void discover_third_party(const char *root) {
    char base[MAX_PATH_LEN];
    snprintf(base, sizeof(base), "%s/third_party", root);
    discover_third_party_at(base, "");
}

static void discover_suites(const char *root) {
    discover_group(root, "test", GROUP_UNIT);
    discover_group(root, "app_testing", GROUP_APP);
    discover_third_party(root);
}

static void print_menu(void) {
    SuiteGroup current = -1;
    size_t idx = 1;
    for (size_t i = 0; i < suite_count; i++) {
        if (suites[i].group != current) {
            current = suites[i].group;
            switch (current) {
                case GROUP_UNIT: printf("\n  Unit / ABI Tests\n"); break;
                case GROUP_APP: printf("\n  App Tests\n"); break;
                case GROUP_THIRD: printf("\n  Third-Party Tests\n"); break;
            }
        }
        printf("    [%zu] %s\n", idx, suites[i].name);
        idx++;
    }
    printf("\n    [0] Run ALL suites\n");
    printf("    [q] Quit\n\n");
}

static void load_suite_cfg(const char *suite_dir, SuiteConfig *cfg) {
    snprintf(cfg->cc, sizeof(cfg->cc), "");
    snprintf(cfg->kind, sizeof(cfg->kind), "c");
    snprintf(cfg->entry, sizeof(cfg->entry), "");
    snprintf(cfg->cflags, sizeof(cfg->cflags), "");
    snprintf(cfg->ldflags, sizeof(cfg->ldflags), "");
    snprintf(cfg->link_zig, sizeof(cfg->link_zig), "auto");
    snprintf(cfg->link_cli, sizeof(cfg->link_cli), "auto");
    snprintf(cfg->interactive, sizeof(cfg->interactive), "no");
    snprintf(cfg->sources, sizeof(cfg->sources), "");
    snprintf(cfg->asm_family, sizeof(cfg->asm_family), "");
    snprintf(cfg->asm_runtime, sizeof(cfg->asm_runtime), "");
    snprintf(cfg->asm_source, sizeof(cfg->asm_source), "");
    snprintf(cfg->asm_invoked, sizeof(cfg->asm_invoked), "no");
    snprintf(cfg->asm_tool, sizeof(cfg->asm_tool), "");
    snprintf(cfg->asm_format, sizeof(cfg->asm_format), "");
    snprintf(cfg->asm_required, sizeof(cfg->asm_required), "no");

    char cfg_path[MAX_PATH_LEN];
    snprintf(cfg_path, sizeof(cfg_path), "%s/suite.cfg", suite_dir);
    FILE *fp = fopen(cfg_path, "r");
    if (!fp) return;

    char line[512];
    while (fgets(line, sizeof(line), fp)) {
        char *trim = line;
        while (*trim == ' ' || *trim == '\t') trim++;
        if (*trim == '#' || *trim == '\n' || *trim == '\0') continue;
        char *eq = strchr(trim, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = trim;
        char *val = eq + 1;
        char *end = val + strlen(val) - 1;
        while (end >= val && (*end == '\n' || *end == '\r')) {
            *end = '\0';
            end--;
        }

        if (strcmp(key, "SUITE_CC") == 0) snprintf(cfg->cc, sizeof(cfg->cc), "%s", val);
        else if (strcmp(key, "SUITE_KIND") == 0) snprintf(cfg->kind, sizeof(cfg->kind), "%s", val);
        else if (strcmp(key, "SUITE_ENTRY") == 0) snprintf(cfg->entry, sizeof(cfg->entry), "%s", val);
        else if (strcmp(key, "SUITE_CFLAGS") == 0) snprintf(cfg->cflags, sizeof(cfg->cflags), "%s", val);
        else if (strcmp(key, "SUITE_LDFLAGS") == 0) snprintf(cfg->ldflags, sizeof(cfg->ldflags), "%s", val);
        else if (strcmp(key, "SUITE_LINK_ZIG") == 0) snprintf(cfg->link_zig, sizeof(cfg->link_zig), "%s", val);
        else if (strcmp(key, "SUITE_LINK_CLI") == 0) snprintf(cfg->link_cli, sizeof(cfg->link_cli), "%s", val);
        else if (strcmp(key, "SUITE_INTERACTIVE") == 0) snprintf(cfg->interactive, sizeof(cfg->interactive), "%s", val);
        else if (strcmp(key, "SUITE_SOURCES") == 0) snprintf(cfg->sources, sizeof(cfg->sources), "%s", val);
        else if (strcmp(key, "ASM_FAMILY") == 0) snprintf(cfg->asm_family, sizeof(cfg->asm_family), "%s", val);
        else if (strcmp(key, "ASM_RUNTIME") == 0) snprintf(cfg->asm_runtime, sizeof(cfg->asm_runtime), "%s", val);
        else if (strcmp(key, "ASM_SOURCE") == 0) snprintf(cfg->asm_source, sizeof(cfg->asm_source), "%s", val);
        else if (strcmp(key, "ASM_INVOKED") == 0) snprintf(cfg->asm_invoked, sizeof(cfg->asm_invoked), "%s", val);
        else if (strcmp(key, "ASM_TOOL") == 0) snprintf(cfg->asm_tool, sizeof(cfg->asm_tool), "%s", val);
        else if (strcmp(key, "ASM_FORMAT") == 0) snprintf(cfg->asm_format, sizeof(cfg->asm_format), "%s", val);
        else if (strcmp(key, "ASM_REQUIRED") == 0) snprintf(cfg->asm_required, sizeof(cfg->asm_required), "%s", val);
    }
    fclose(fp);
}

static int ensure_zig_lib(const char *root, const char *zig_lib, bool run_check) {
    (void)zig_lib;
    fprintf(stdout, "  → Refreshing Zig library...\n");
    char cmd[MAX_PATH_LEN];
    snprintf(cmd, sizeof(cmd),
             "cd \"%s\" && env ZIG_LOCAL_CACHE_DIR=.zig-cache ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build --build-file build.zig %sinstall",
             root,
             run_check ? "check " : "");
    return system(cmd);
}

static int ensure_window_lib(const char *root) {
    fprintf(stdout, "  → Refreshing window library...\n");
    char cmd[MAX_PATH_LEN];
    snprintf(cmd, sizeof(cmd), "cd \"%s\" && make window-lib >/dev/null", root);
    return system(cmd);
}

static int run_command(const char *cmd) {
    int rc = system(cmd);
    if (rc != 0) return 1;
    return 0;
}

static int maybe_codesign_binary(const char *binary) {
#ifdef __APPLE__
    char cmd[MAX_PATH_LEN + 128];
    snprintf(cmd, sizeof(cmd), "codesign --force -s - \"%s\" >/dev/null 2>&1", binary);
    return run_command(cmd);
#else
    (void)binary;
    return 0;
#endif
}

static int build_and_run_suite(const char *root, const Suite *suite, bool non_interactive) {
    SuiteConfig cfg;
    load_suite_cfg(suite->path, &cfg);
    const bool is_win32_abi_suite = suite->group == GROUP_UNIT && strcmp(suite->name, "win32") == 0;

    if (cfg.asm_family[0] != '\0') {
        printf("  → Assembler profile: %s", cfg.asm_family);
        if (cfg.asm_runtime[0] != '\0') printf(" (%s)", cfg.asm_runtime);
        printf("\n");
        if (cfg.asm_source[0] != '\0') {
            printf("    source: %s\n", cfg.asm_source);
        }
        if (strcmp(cfg.asm_invoked, "yes") == 0) {
            if (cfg.asm_tool[0] != '\0') {
                printf("    invocation: external %s validation/build enabled\n", cfg.asm_tool);
            } else {
                printf("    invocation: external assembler validation/build enabled\n");
            }
        } else {
            printf("    mode: translation layer reference, no external assembler invocation\n");
        }
    }

    const char *zig_lib = "";
    char zig_path[MAX_PATH_LEN];
    snprintf(zig_path, sizeof(zig_path), "%s/zig-out/lib/librosette_zig.a", root);

    bool link_zig = false;
    if (strcmp(cfg.link_zig, "yes") == 0) link_zig = true;
    else if (strcmp(cfg.link_zig, "no") == 0) link_zig = false;
    else link_zig = (access(zig_path, R_OK) == 0);

    if (link_zig) {
        if (ensure_zig_lib(root, zig_path, suite->group == GROUP_UNIT) != 0) {
            fprintf(stderr, "  ✗ Failed to build Zig library\n");
            return 1;
        }
        zig_lib = zig_path;
        if (is_win32_abi_suite) {
            if (ensure_window_lib(root) != 0) {
                fprintf(stderr, "  ✗ Failed to build window library\n");
                return 1;
            }
        }
    }

    /* Determine whether to link the CLI bridge library. */
    char cli_lib_path[MAX_PATH_LEN];
    snprintf(cli_lib_path, sizeof(cli_lib_path), "%s/librosette_cli.a", root);
    bool link_cli = false;
    if (strcmp(cfg.link_cli, "yes") == 0) link_cli = true;
    else if (strcmp(cfg.link_cli, "no") == 0) link_cli = false;
    else link_cli = (access(cli_lib_path, R_OK) == 0);

    char common_includes[MAX_PATH_LEN];
#ifdef __APPLE__
    snprintf(common_includes, sizeof(common_includes), "-I\"%s/include/shims/macos\" -I\"%s/include/shims/win32\" -I\"%s/include\"", root, root, root);
#else
    snprintf(common_includes, sizeof(common_includes), "-I\"%s/include/shims/win32\" -I\"%s/include\"", root, root);
#endif

    int failure = 0;

    /* ---- Determine which source files to build ---- */
    unsigned int src_count = 0;
    char src_names[MAX_SUITES][MAX_NAME]; /* reuse MAX_SUITES as a count limit */

    if (cfg.sources[0] != '\0') {
        /* Tokenise SUITE_SOURCES (space-separated list of filenames). */
        char tmp[512];
        snprintf(tmp, sizeof(tmp), "%s", cfg.sources);
        char *tok = strtok(tmp, " ");
        while (tok && src_count < MAX_SUITES) {
            snprintf(src_names[src_count], sizeof(src_names[0]), "%s", tok);
            src_count++;
            tok = strtok(NULL, " ");
        }
    } else {
        /* No explicit sources — scan the directory for .c / .cpp. */
        DIR *dir = opendir(suite->path);
        if (!dir) return 1;
        struct dirent *ent;
        while ((ent = readdir(dir)) != NULL && src_count < MAX_SUITES) {
            if (ent->d_name[0] == '.') continue;
            const char *ext = strrchr(ent->d_name, '.');
            if (!ext) continue;
            if (strcmp(ext, ".c") != 0 && strcmp(ext, ".cpp") != 0) continue;
            snprintf(src_names[src_count], sizeof(src_names[0]), "%s", ent->d_name);
            src_count++;
        }
        closedir(dir);
    }

    if (suite->group == GROUP_APP) {
        const char *fname = (src_count == 1) ? src_names[0] : suite->name;
        char base[MAX_NAME];
        snprintf(base, sizeof(base), "%s", suite->name);
        for (char *p = base; *p; ++p) {
            if (*p == '/' || *p == ' ' || *p == ':') *p = '_';
        }

        char binary[MAX_PATH_LEN];
        snprintf(binary, sizeof(binary), "%s/%s", suite->path, base);

        char build_cmd[4096];
        snprintf(build_cmd, sizeof(build_cmd),
                 "cd \"%s\" && ./tools/build_suite_binary.sh \"%s\" \"%s\"",
                 root, suite->name, binary);

        printf("  → Building %s\n", fname);
        if (run_command(build_cmd) != 0) {
            fprintf(stderr, "  ✗ Build failed for %s\n", fname);
            return 1;
        }

        bool is_interactive = (strcmp(cfg.interactive, "yes") == 0);
        if (non_interactive && is_interactive) {
            printf("  ↷ Skipping run (interactive) for %s\n", fname);
        } else {
            printf("  → Running %s\n", base);
            char run_cmd[MAX_PATH_LEN + 32];
            snprintf(run_cmd, sizeof(run_cmd), "cd \"%s\" && \"%s\"", suite->path, binary);
            if (run_command(run_cmd) != 0) {
                fprintf(stderr, "  ✗ Run failed for %s\n", fname);
                unlink(binary);
                return 1;
            }
        }
        unlink(binary);
        return 0;
    }

    for (unsigned int i = 0; i < src_count; i++) {
        const char *fname = src_names[i];
        if (is_win32_abi_suite &&
            strcmp(fname, "handshake_suite_test.c") != 0) {
            continue;
        }
        char source[MAX_PATH_LEN];
        snprintf(source, sizeof(source), "%s/%s", suite->path, fname);

        char binary[MAX_PATH_LEN];
        char base[MAX_NAME];
        snprintf(base, sizeof(base), "%s", fname);
        char *dot = strrchr(base, '.');
        if (dot) *dot = '\0';
        snprintf(binary, sizeof(binary), "%s/%s", suite->path, base);

        const char *ext = strrchr(fname, '.');
        bool is_cpp = ext && strcmp(ext, ".cpp") == 0;
        bool uses_window_lib = strstr(cfg.ldflags, "librosette_window.a") != NULL;
        bool needs_objc_runtime = uses_window_lib || is_win32_abi_suite;
        const char *compile_cc = cfg.cc[0] ? cfg.cc : (is_cpp ? "clang++" : "clang");
        const char *link_cc = cfg.cc[0] ? cfg.cc : ((is_cpp || needs_objc_runtime) ? "clang++" : "clang");

        char libraries[4096];
        libraries[0] = '\0';
        if (link_cli) {
            snprintf(libraries, sizeof(libraries), "\"%s\"", cli_lib_path);
        }
        if (link_zig) {
            size_t n = strlen(libraries);
            snprintf(libraries + n, sizeof(libraries) - n, "%s\"%s\"",
                     n > 0 ? " " : "", zig_lib);
        }
        if (is_win32_abi_suite) {
            size_t n = strlen(libraries);
            snprintf(libraries + n, sizeof(libraries) - n,
                     "%s\"%s/librosette_window.a\" -lobjc -framework Cocoa -framework Foundation -framework AppKit",
                     n > 0 ? " " : "", root);
        }

        printf("  → Building %s\n", fname);
        char object[MAX_PATH_LEN];
        snprintf(object, sizeof(object), "%s/%s.o", suite->path, base);

        char compile_cmd[4096];
        snprintf(compile_cmd, sizeof(compile_cmd), "%s %s%s%s %s %s -c \"%s\" -o \"%s\"",
                 compile_cc,
                 strstr(compile_cc, "++") ? "-std=c++11 " : "",
                 DEFAULT_CFLAGS,
                 cfg.cflags[0] ? " " : "",
                 cfg.cflags,
                 common_includes,
                 source,
                 object);

        if (run_command(compile_cmd) != 0) {
            fprintf(stderr, "  ✗ Build failed for %s\n", fname);
            failure = 1;
            continue;
        }

        char link_cmd[4096];
        snprintf(link_cmd, sizeof(link_cmd), "%s %s%s\"%s\" %s %s%s%s -o \"%s\"",
                 link_cc,
                 strstr(link_cc, "++") ? "-std=c++11 " : "",
                 needs_objc_runtime ? "-fobjc-link-runtime " : "",
                 object,
                 cfg.ldflags,
                 libraries[0] ? " " : "",
                 libraries,
                 "",
                 binary);

        if (run_command(link_cmd) != 0) {
            fprintf(stderr, "  ✗ Build failed for %s\n", fname);
            failure = 1;
            unlink(object);
            continue;
        }

        if (suite->group == GROUP_UNIT) {
            if (maybe_codesign_binary(binary) != 0) {
                fprintf(stderr, "  ✗ Codesign failed for %s\n", fname);
                failure = 1;
                unlink(binary);
                unlink(object);
                continue;
            }
        }

        bool is_interactive = (strcmp(cfg.interactive, "yes") == 0);
        if (non_interactive && is_interactive) {
            printf("  ↷ Skipping run (interactive) for %s\n", fname);
        } else {
            printf("  → Running %s\n", base);
            char run_cmd[MAX_PATH_LEN + 40];
            snprintf(run_cmd, sizeof(run_cmd), "cd \"%s\" && \"%s\" 2>&1", suite->path, binary);
            if (run_command(run_cmd) != 0) {
                fprintf(stderr, "  ✗ Run failed for %s\n", fname);
                failure = 1;
            }
        }
        unlink(binary);
        unlink(object);
    }
    return failure;
}

static int run_all(const char *root, bool non_interactive) {
    int failure = 0;
    for (size_t i = 0; i < suite_count; i++) {
        printf("\n== Suite: %s ==\n", suites[i].name);
        if (build_and_run_suite(root, &suites[i], non_interactive)) {
            failure = 1;
        }
    }
    return failure;
}

static const Suite *find_suite(const char *name) {
    for (size_t i = 0; i < suite_count; i++) {
        if (strcmp(suites[i].name, name) == 0) return &suites[i];
    }
    return NULL;
}

static int run_suite_by_name(const char *root, const char *name) {
    const Suite *suite = find_suite(name);
    if (!suite) {
        fprintf(stderr, "Suite not found: %s\n", name);
        return 1;
    }
    printf("\n== Suite: %s ==\n", suite->name);
    return build_and_run_suite(root, suite, false);
}

static void list_suites(void) {
    for (size_t i = 0; i < suite_count; i++) {
        printf("%s\n", suites[i].name);
    }
}

static int get_root_dir(char *out, size_t len, const char *argv0) {
    char resolved[MAX_PATH_LEN];
    if (realpath(argv0, resolved) == NULL) {
        if (!getcwd(out, len)) return 1;
        return 0;
    }
    char *slash = strrchr(resolved, '/');
    if (!slash) return 1;
    *slash = '\0';
    slash = strrchr(resolved, '/');
    if (!slash) return 1;
    *slash = '\0';
    snprintf(out, len, "%s", resolved);
    return 0;
}

static int interactive_menu(const char *root) {
    char input[64];
    while (1) {
        printf("\nRosette — Test Prodder\n");
        print_menu();
        printf("Select a suite: ");
        if (!fgets(input, sizeof(input), stdin)) return 1;
        if (input[0] == 'q' || input[0] == 'Q') return 0;
        if (input[0] == '0') return run_all(root, true);
        char *end = NULL;
        long idx = strtol(input, &end, 10);
        if (idx <= 0 || (size_t)idx > suite_count) {
            printf("Invalid selection.\n");
            continue;
        }
        const Suite *suite = &suites[idx - 1];
        printf("\n== Suite: %s ==\n", suite->name);
        return build_and_run_suite(root, suite, false);
    }
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    char root[MAX_PATH_LEN];
    if (get_root_dir(root, sizeof(root), argv[0]) != 0) {
        fprintf(stderr, "Failed to resolve project root.\n");
        return 1;
    }

    discover_suites(root);
    if (suite_count == 0) {
        fprintf(stderr, "No suites found.\n");
        return 1;
    }

    if (argc > 1) {
        if (strcmp(argv[1], "--list") == 0) {
            list_suites();
            return 0;
        }
        if (strcmp(argv[1], "--all") == 0) {
            return run_all(root, true);
        }
        if (strcmp(argv[1], "--suite") == 0 && argc > 2) {
            return run_suite_by_name(root, argv[2]);
        }
    }

    return interactive_menu(root);
}
