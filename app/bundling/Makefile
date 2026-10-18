# Targets owned by app/bundling/. Keep recipes local to this folder.


.PHONY: exe-list mscoree-native exe-runner-build gate-runner-build exe-runner-cleanup exe-run exe-export app-exe-builder-build app-suite-binary app-exe bundled-app-exes app-exe-parse app-exe-run

exe-list:
	@find "$(EXE_EXAMPLES_DIR)" -maxdepth 1 -type f \( -name '*.exe' -o -name '*.EXE' \) | sort

MSCOREE_NATIVE_DIR := $(DLL_ASSETS_DIR)/mscoree
MSCOREE_NATIVE_LIB := $(ASSET_PREFIX)zig-out/bin/libmscoree_native.dylib
MSCOREE_NATIVE_HELPER := $(ASSET_PREFIX)zig-out/bin/rosette_mscoree_window_helper
MSCOREE_NATIVE_HELPER_APP := $(ASSET_PREFIX)zig-out/bin/RosetteMscoreeWindow.app
MSCOREE_NATIVE_HELPER_APP_BIN := $(MSCOREE_NATIVE_HELPER_APP)/Contents/MacOS/rosette_mscoree_window_helper
MSCOREE_NATIVE_WINDOW_SRC := $(MSCOREE_NATIVE_DIR)/mscoree_window.m
MSCOREE_NATIVE_HELPER_SRC := $(MSCOREE_NATIVE_DIR)/mscoree_window_helper.m
MSCOREE_WARNINGS := -Wno-format -Wno-incompatible-pointer-types -Wno-unsequenced -Wno-visibility
MSCOREE_CFLAGS := -O2 -std=c11 $(MSCOREE_WARNINGS) $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) -I$(MSCOREE_NATIVE_DIR)
MSCOREE_OBJC_FLAGS := -O2 -fobjc-arc $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) -I$(MSCOREE_NATIVE_DIR)
MSCOREE_FRAMEWORKS := -framework Cocoa -framework Foundation

mscoree-native: $(MSCOREE_NATIVE_LIB) $(MSCOREE_NATIVE_HELPER) $(MSCOREE_NATIVE_HELPER_APP)

$(MSCOREE_NATIVE_LIB): $(MSCOREE_NATIVE_DIR)/mscoree_main.c $(MSCOREE_NATIVE_DIR)/mscoree_stubs.c $(MSCOREE_NATIVE_WINDOW_SRC) $(TRACE_WINDOW_SRC)
	@mkdir -p "$(ASSET_PREFIX)zig-out/bin"
	@"$(CC)" $(MSCOREE_CFLAGS) -c "$(MSCOREE_NATIVE_DIR)/mscoree_main.c" -o /tmp/mscoree_main.o
	@"$(CC)" $(MSCOREE_CFLAGS) -c "$(MSCOREE_NATIVE_DIR)/mscoree_stubs.c" -o /tmp/mscoree_stubs.o
	@"$(CC)" $(MSCOREE_OBJC_FLAGS) -c "$(MSCOREE_NATIVE_WINDOW_SRC)" -o /tmp/mscoree_window.o
	@"$(CC)" $(MSCOREE_OBJC_FLAGS) -c "$(TRACE_WINDOW_SRC)" -o /tmp/trace_window.o
	@"$(CC)" -shared /tmp/mscoree_main.o /tmp/mscoree_stubs.o /tmp/mscoree_window.o /tmp/trace_window.o $(MSCOREE_FRAMEWORKS) -o "$@"
	@echo "Built $(MSCOREE_NATIVE_LIB)"

$(MSCOREE_NATIVE_HELPER): $(MSCOREE_NATIVE_WINDOW_SRC) $(MSCOREE_NATIVE_HELPER_SRC) $(TRACE_WINDOW_SRC)
	@mkdir -p "$(ASSET_PREFIX)zig-out/bin"
	@"$(CC)" $(MSCOREE_OBJC_FLAGS) "$(MSCOREE_NATIVE_WINDOW_SRC)" "$(TRACE_WINDOW_SRC)" "$(MSCOREE_NATIVE_HELPER_SRC)" $(MSCOREE_FRAMEWORKS) -o "$@"
	@echo "Built $(MSCOREE_NATIVE_HELPER)"

$(MSCOREE_NATIVE_HELPER_APP): $(MSCOREE_NATIVE_WINDOW_SRC) $(MSCOREE_NATIVE_HELPER_SRC) $(TRACE_WINDOW_SRC)
	@mkdir -p "$(MSCOREE_NATIVE_HELPER_APP)/Contents/MacOS"
	@mkdir -p "$(MSCOREE_NATIVE_HELPER_APP)/Contents/Resources"
	@"$(CC)" $(MSCOREE_OBJC_FLAGS) "$(MSCOREE_NATIVE_WINDOW_SRC)" "$(TRACE_WINDOW_SRC)" "$(MSCOREE_NATIVE_HELPER_SRC)" $(MSCOREE_FRAMEWORKS) -o "$(MSCOREE_NATIVE_HELPER_APP_BIN)"
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>CFBundleExecutable</key>' \
		'  <string>rosette_mscoree_window_helper</string>' \
		'  <key>CFBundleIdentifier</key>' \
		'  <string>dev.rosette.mscoree-window-helper</string>' \
		'  <key>CFBundleName</key>' \
		'  <string>Rosette Managed Window</string>' \
		'  <key>CFBundlePackageType</key>' \
		'  <string>APPL</string>' \
		'  <key>NSHighResolutionCapable</key>' \
		'  <true/>' \
		'</dict>' \
		'</plist>' > "$(MSCOREE_NATIVE_HELPER_APP)/Contents/Info.plist"
	@printf 'APPL????' > "$(MSCOREE_NATIVE_HELPER_APP)/Contents/PkgInfo"
	@echo "Built $(MSCOREE_NATIVE_HELPER_APP)"

exe-runner-build: mscoree-native
	@mkdir -p "$(ZIG_CACHE_DIR)/global"
	@cd "$(ROOT_DIR)" && ZIG_LOCAL_CACHE_DIR="$(ZIG_CACHE_DIR)" ZIG_GLOBAL_CACHE_DIR="$(ZIG_GLOBAL_CACHE_DIR)" zig build exe-runner --build-file app/bundling/build.zig $(APP_BUNDLE_RELEASE_FLAG) 2>&1
	@cp "$(ROOT_DIR)/app/bundling/zig-out/bin/rosette_exe_runner" "$(EXE_RUNNER_BIN)"

gate-runner-build: exe-runner-build

exe-runner-cleanup:
	@-pkill -TERM -f '$(ROSETTE_RUNNER_KILL_PATTERN)' 2>/dev/null || true
	@-pkill -TERM -f '$(ROSETTE_HOST_KILL_PATTERN)' 2>/dev/null || true
	@sleep 0.2
	@-pkill -KILL -f '$(ROSETTE_RUNNER_KILL_PATTERN)' 2>/dev/null || true
	@-pkill -KILL -f '$(ROSETTE_HOST_KILL_PATTERN)' 2>/dev/null || true
app-exe-builder-build:
	@mkdir -p "$(ZIG_CACHE_DIR)/global"
	@cd "$(ROOT_DIR)" && ZIG_LOCAL_CACHE_DIR="$(ZIG_CACHE_DIR)" ZIG_GLOBAL_CACHE_DIR="$(ZIG_GLOBAL_CACHE_DIR)" zig build-exe "$(APP_EXE_BUILDER_SRC)" -femit-bin="$(APP_EXE_BUILDER_BIN)"

exe-run: exe-runner-build
	@if [ ! -f "$(EXE)" ]; then \
		echo "EXE not found: $(EXE)"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory exe-runner-cleanup
	@$(call RUN_ROSETTE_EXE,$(EXE),)

exe-export: exe-runner-build
	@src="$(SRC_EXE)"; \
	if [ -z "$$src" ] && [ -n "$(SUITE)" ]; then \
		matches=$$(find "app_testing/$(SUITE)" -type f \( -name '*.exe' -o -name '*.EXE' \) | sort); \
		count=$$(printf '%s\n' "$$matches" | sed '/^$$/d' | wc -l | tr -d ' '); \
		if [ "$$count" -eq 1 ]; then \
			src="$$matches"; \
		elif [ "$$count" -gt 1 ]; then \
			echo "Multiple .exe files found for suite $(SUITE); pass SRC_EXE explicitly."; \
			printf '%s\n' "$$matches"; \
			exit 1; \
		fi; \
	fi; \
	if [ -z "$$src" ]; then \
		echo "Pass SRC_EXE=/path/to/file.exe or SUITE=<suite-with-one-exe>."; \
		exit 1; \
	fi; \
	out="$(OUT_EXE)"; \
	if [ -z "$$out" ]; then \
		out="$(EXE_EXAMPLES_DIR)/$$(basename "$$src")"; \
	fi; \
	mkdir -p "$$(dirname "$$out")"; \
	cp "$$src" "$$out"; \
	echo "Exported $$src -> $$out"; \
	$(MAKE) --no-print-directory exe-runner-cleanup; \
	runner="zig-out/bin/rosette_exe_runner.run.$$$$"; \
	cp "$(ROSETTE_RUNNER_TEMPLATE)" "$$runner"; \
	"$$runner" --open "$$out"; \
	status=$$?; \
	rm -f "$$runner"; \
	exit $$status

app-suite-binary: window-lib cli-lib
	@./tools/build_suite_binary.sh "$(APP_SUITE)" "$(APP_HOST_BIN)"

app-exe: app-suite-binary app-exe-builder-build
	@mkdir -p "$$(dirname "$(APP_EXE)")"
	@"$(APP_EXE_BUILDER_BIN)" "$(APP_SUITE)" "$(ROOT_DIR)/$(APP_HOST_BIN)" "$(ROOT_DIR)/app_testing/$(APP_SUITE)" "$(APP_EXE)"
	@echo "Packaged $(APP_SUITE) -> $(APP_EXE)"

bundled-app-exes: app-exe-builder-build window-lib cli-lib
	@mkdir -p "$(EXE_EXAMPLES_DIR)"
	@for suite in $(BUNDLED_APP_SUITES); do \
		host="app_testing/$$suite/$$suite.host"; \
		exe="$(EXE_EXAMPLES_DIR)/$$suite.exe"; \
		echo "Building bundled Rosette .exe wrapper for $$suite..."; \
		./tools/build_suite_binary.sh "$$suite" "$$host"; \
		"$(APP_EXE_BUILDER_BIN)" "$$suite" "$(ROOT_DIR)/$$host" "$(ROOT_DIR)/app_testing/$$suite" "$$exe"; \
	done

app-exe-parse: app-exe exe-runner-build
	@$(MAKE) --no-print-directory exe-runner-cleanup
	@$(call RUN_ROSETTE_EXE,$(APP_EXE),--parse-only)

app-exe-run: app-exe exe-runner-build
	@$(MAKE) --no-print-directory exe-runner-cleanup
	@$(call RUN_ROSETTE_EXE,$(APP_EXE),)
