# Targets owned by src/tooling/. Keep recipes local to this folder.


.PHONY: c-fix c-fix-build link-audit-build iso-build iso-run run-iso xbox360-media-self-test

# ---------------------------------------------------------------------------
# C transpiler for fixing implicit narrowing conversions
# ---------------------------------------------------------------------------
C_SOURCES := $(shell find $(ROOT_DIR)/src -name "*.c" -type f 2>/dev/null)

c-fix-build:
	@mkdir -p "$(ZIG_CACHE_DIR)/global"
	@ZIG_LOCAL_CACHE_DIR="$(ZIG_CACHE_DIR)" ZIG_GLOBAL_CACHE_DIR="$(ZIG_GLOBAL_CACHE_DIR)" zig build c-fix --build-file "$(COORD_BUILD_FILE)" --prefix "$(ZIG_OUT_DIR)" 2>&1
	@echo "Built $(C_FIX_BIN)"

c-fix: c-fix-build
	@if [ -z "$(C_SOURCES)" ]; then \
		echo "No C sources found to fix"; \
	else \
		echo "Running C transpiler on C sources..."; \
		for src in $(C_SOURCES); do \
			if [ -f "$$src" ]; then \
				echo "  Processing: $$src"; \
				"$(C_FIX_BIN)" --in-place "$$src" || echo "  Warning: Failed to process $$src"; \
			fi; \
		done; \
		echo "C transpiler complete"; \
	fi
# Compile-side companion to the runtime readiness gate. Audits a finished link
# set for symbol resolutions the source does not determine — duplicate strong
# definitions, multiple entry points, definitions picked by archive member
# order. Those produce no compiler or linker diagnostic and fail at runtime.
#
#   make link-audit-build
#   cd <xenia>/build && rosette-link-audit \
#       --ninja CMakeFiles/impl-Debug.ninja --target bin/macOS/Debug/xenia_canary.app
link-audit-build:
	@mkdir -p "$(ZIG_CACHE_DIR)/global"
	@cd "$(ROOT_DIR)" && ZIG_LOCAL_CACHE_DIR="$(ZIG_CACHE_DIR)" ZIG_GLOBAL_CACHE_DIR="$(ZIG_GLOBAL_CACHE_DIR)" zig build-exe -O "$(ROSETTE_RUNTIME_OPTIMIZE)" --dep link_audit -Mroot="$(LINK_AUDIT_SRC)" -Mlink_audit=lib/link-audit/root.zig -femit-bin="$(LINK_AUDIT_BIN)"
iso-build:
	@mkdir -p "$(ZIG_CACHE_DIR)/global"
	@cd "$(ROOT_DIR)" && ZIG_LOCAL_CACHE_DIR="$(ZIG_CACHE_DIR)" ZIG_GLOBAL_CACHE_DIR="$(ZIG_GLOBAL_CACHE_DIR)" zig build-exe -O "$(ROSETTE_RUNTIME_OPTIMIZE)" "$(ISO_SRC)" -femit-bin="$(ISO_BIN)"
	@echo "Built $(ISO_BIN)"

iso-run: iso-build
	@if [ -z "$(ISO)" ]; then \
		echo -n 'Enter path to ISO file: '; \
		read iso_path; \
		if [ -z "$$iso_path" ]; then \
			echo "No path provided."; \
			exit 1; \
		fi; \
		if [ ! -f "$$iso_path" ]; then \
			echo "File not found: $$iso_path"; \
			exit 1; \
		fi; \
		"$(ISO_BIN)" "$$iso_path" $(ARGS); \
	else \
		if [ ! -f "$(ISO)" ]; then \
			echo "ISO file not found: $(ISO)"; \
			exit 1; \
		fi; \
		"$(ISO_BIN)" "$(ISO)" $(ARGS); \
	fi

run-iso: iso-run

xbox360-media-self-test:
	@python3 "$(XBOX360_MEDIA_TOOL)" self-test

