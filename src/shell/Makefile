# Targets owned by src/shell/. Keep recipes local to this folder.
# Shell update target semantics are documented below; preserve the fail-closed routing.


.PHONY: shell-helper-build shell shell-update shell-update-all shell-update-relink shell-update-elf-processor shell-update-elf-processor-process-impl shell-update-elf-processor-windows-runtime shell-update-elf-processor-block-jit shell-update-macho-processor shell-update-dyld-forwarder shell-uninstall shell-clean-state

# The sanctioned Xenia launcher uses the app/bundling runner directly. Keep
# it on this gate so a shell update cannot leave that runner older than the
# processor and reports it just rebuilt. `exe-runner-build` also copies the
# same artifact to zig-out/bin for the standalone route.
shell-helper-build: pkg-boundary-audit isa-execution-audit build-routes-audit dll-coverage-audit guest-context-audit vendor-library-audit diagnostic-audit c-fix-build assembler-runner-build exe-runner-build elf-processor-build macho-processor-build elf-processor-dylib avx-shim-build compat-router-build
	@mkdir -p "$(ZIG_CACHE_DIR)/global"
	@cd "$(ROOT_DIR)" && ZIG_LOCAL_CACHE_DIR="$(ZIG_CACHE_DIR)" ZIG_GLOBAL_CACHE_DIR="$(ZIG_GLOBAL_CACHE_DIR)" zig build-exe -lc --dep entrypoint_alignment --dep entrypoint_kernel_process_guard --dep compat_source_include_compat --dep compat_third_party_include_compat -Mroot="$(SHELL_HELPER_SRC)" -Mentrypoint_alignment=src/entrypoint/alignment/root.zig -Mentrypoint_kernel_process_guard=src/entrypoint/kernel/process_guard.zig -Mcompat_source_include_compat=src/compat/source/include_compat.zig -Mcompat_third_party_include_compat=src/compat/third_party/include_compat.zig -femit-bin="$(SHELL_HELPER_BIN)"

# Keep source-level test declarations separate from the executed `check`
# artifacts. The census script is intentionally the only place that parses
# the verbose test summary; a successful process exit remains authoritative
# because several negative-path tests print "failed command" deliberately.
shell: shell-helper-build
	@"$(SHELL_HELPER_BIN)" install "$(ROOT_DIR)"

# Smart shell update model for agents and maintainers:
# - `shell-update` fingerprints Git-visible source changes and compares them
#   with `.rosette/shell-update-state.json`, plus toolchain/config/Xenia
#   identities. Known ELF/Mach-O/dyld scopes run their focused Zig regression
#   target, rebuild the affected processor, and then relink/install. Missing
#   state, changed build graphs, unknown paths, external identity changes, or
#   missing artifacts fail closed to `shell-update-all`.
# - Explicit `shell-update-elf-processor-process-impl`,
#   `shell-update-elf-processor-windows-runtime`,
#   `shell-update-elf-processor-block-jit` and sibling targets force a declared
#   scope, but still fall back to the full path if pending source changes escape
#   that scope. `shell-update-relink` refreshes shell
#   integration when source inputs match the last successful snapshot.
# - `shell-update-dyld-forwarder` runs the dyld bridge suite and rebuilds both
#   ELF and Mach-O consumers because the forwarder is shared by both roots.
# - `shell-update-all` is the old complete sanity route: full `zig build
#   check`, shell/build audits, Xenia source manifest, install, and identities.
#   Expect about 20 minutes or longer. Use it periodically and after changes
#   to the updater/dependency model; it is intentionally not the default.
# - The shell-update identity records Xenia as explicitly unavailable when
#   its external drive is unmounted. This lets Rosette's shell refresh proceed;
#   `make build-identity` and authentic Xenia run admission still require the
#   actual source checkout and will not accept an incomplete identity.
# - The vendored-library audit always checks Rosette's pinned copies, host
#   providers and ABI probes. Its comparison against Xenia's submodule commits
#   is explicitly skipped only when the configured Xenia checkout is absent.
shell-update:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SMART_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --scope auto

shell-update-relink:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SMART_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --scope relink

shell-update-elf-processor:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SMART_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --scope elf-processor

shell-update-elf-processor-process-impl:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SMART_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --scope elf-processor-process-impl

shell-update-elf-processor-windows-runtime:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SMART_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --scope elf-processor-windows-runtime

shell-update-elf-processor-block-jit:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SMART_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --scope elf-processor-block-jit

shell-update-macho-processor:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SMART_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --scope macho-processor

shell-update-dyld-forwarder:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SMART_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --scope dyld-forwarder

# Full sanity target. The Python coordinator prints the long-run warning before
# it starts prerequisites and primes the incremental baseline only on success.
shell-update-all:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SMART_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --scope all

shell-uninstall: shell-helper-build
	@"$(SHELL_HELPER_BIN)" uninstall

shell-clean-state: shell-helper-build
	@"$(SHELL_HELPER_BIN)" clean-state
