# Targets owned by src/compat/. Keep recipes local to this folder.


.PHONY: compat-router-build

compat-router-build:
	@mkdir -p "$(ZIG_CACHE_DIR)/global"
	@cd "$(ROOT_DIR)" && ZIG_LOCAL_CACHE_DIR="$(ZIG_CACHE_DIR)" ZIG_GLOBAL_CACHE_DIR="$(ZIG_GLOBAL_CACHE_DIR)" zig build-exe -lc --dep entrypoint_kernel_process_guard --dep exit_diagnostics -Mroot="$(COMPAT_ROUTER_SRC)" -Mentrypoint_kernel_process_guard=src/entrypoint/kernel/process_guard.zig -Mexit_diagnostics=src/tooling/exit_diagnostics/root.zig -femit-bin="$(COMPAT_ROUTER_BIN)"
