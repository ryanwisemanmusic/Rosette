ROOT_DIR := $(CURDIR)
INCLUDE_DIR := $(ROOT_DIR)/include
SHIM_DIR := $(INCLUDE_DIR)/shims/win32
MACOS_SHIM_DIR := $(INCLUDE_DIR)/shims/macos
WIN32_DIR := $(INCLUDE_DIR)/win32

CC ?= clang
CXX ?= clang++
CFLAGS ?= -Wall -Wextra -Wno-ignored-attributes
ZIG_VERSION ?= 0.16.0
ZIG_CACHE_DIR ?= build/.zig-cache
ZIG_GLOBAL_CACHE_DIR ?= build/.zig-cache/global
ZIG_BUILD_ENV := ZIG_LOCAL_CACHE_DIR=$(ZIG_CACHE_DIR) ZIG_GLOBAL_CACHE_DIR=$(ZIG_GLOBAL_CACHE_DIR)
ZIG_LIB := zig-out/lib/librosette_zig.a
EXE_RUNNER_BIN := zig-out/bin/rosette_exe_runner
ASSEMBLER_RUNNER_BIN := zig-out/bin/rosette_assembler_runner
APP_EXE_BUILDER_SRC := src/tooling/exe_parser/rosette_app_exe.zig
APP_EXE_BUILDER_BIN := zig-out/bin/rosette_app_exe
ELF_PROCESSOR_BIN := zig-out/bin/elf_processor
ELF_PROCESSOR_SRC := lib/processor/ELF_processor/main.zig
MACHO_PROCESSOR_BIN := zig-out/bin/macho_processor
MACHO_PROCESSOR_SRC := lib/Mach-O/main.zig
DYLD_DYLIB := zig-out/lib/rosette-exec.dylib
SHELL_HELPER_SRC := src/shell/global_config/rosette_shell.zig
SHELL_HELPER_BIN := zig-out/bin/rosette-shell
COMPAT_ROUTER_SRC := src/compat/rosetta2/main.zig
COMPAT_ROUTER_BIN := zig-out/bin/rosette-router
C_FIX_BIN := zig-out/bin/rosette-c-fix
ASSETS_DIR ?= $(if $(wildcard assets/dll/mscoree),assets,include/assets)
DLL_ASSETS_DIR := $(ASSETS_DIR)/dll
EXE_EXAMPLES_DIR := $(ASSETS_DIR)/exe_examples
EXE ?= $(EXE_EXAMPLES_DIR)/Notepad.exe
EXE_LOG ?= $(EXE_EXAMPLES_DIR)/$(basename $(notdir $(EXE))).trace.log
APP_SUITE ?= basic_snake
APP_HOST_BIN ?= app_testing/$(APP_SUITE)/$(APP_SUITE).host
APP_EXE ?= $(EXE_EXAMPLES_DIR)/$(APP_SUITE).exe
APP_TRACE ?= $(EXE_EXAMPLES_DIR)/$(APP_SUITE).trace.log
BUNDLED_APP_SUITES ?= Console-Tetris basic_snake snax86
ROSETTE_RUNNER_TEMPLATE := app/bundling/zig-out/bin/rosette_exe_runner
ROSETTE_RUNNER_KILL_PATTERN := rosette_([c]li_runner|[e]xe_runner).*(assets|include/assets)/exe_examples
ROSETTE_HOST_KILL_PATTERN := [/]app_testing/.*[.]host

define RUN_ROSETTE_EXE
runner="zig-out/bin/rosette_exe_runner.run.$$$$"; \
cp "$(ROSETTE_RUNNER_TEMPLATE)" "$$runner"; \
"$$runner" --open "$(1)" $(2); \
status=$$?; \
rm -f "$$runner"; \
exit $$status
endef

# Standalone runner used by make exe-run and legacy/debug invocations.
EXE_GATE_RUNNER_SRC := src/tooling/exe_parser/rosette_exe_runner.zig
EXE_GATE_RUNNER_BIN := zig-out/bin/rosette_exe_runner

# Entitlements for codesigning (JIT, unsigned-executable-memory, etc.)
ENTITLEMENTS := build/rosette.entitlements
CODESIGN_IDENTITY ?= -
CODESIGN_EXTRA_FLAGS ?=
NOTARY_PROFILE ?=
NOTARYTOOL ?= xcrun notarytool
STAPLER ?= xcrun stapler

# On macOS, prepend the LLP64 override shim so it wins the include lookup
# for "win32/windows_base.h" over the upstream-mirrored shim/canonical.
ifeq ($(shell uname -s),Darwin)
MACOS_SHIM_INC := -Iinclude/shims/macos
else
MACOS_SHIM_INC :=
endif
# Reference header path (the canonical win32 headers mirrored upstream)
REFERENCE_INC := -I.rosette/include
SHIM_INC := -Iinclude/shims/win32 $(REFERENCE_INC)
INCLUDE_INC := -Iinclude
export MACOS_SHIM_INC

# ---------------------------------------------------------------------------
# Objective-C / C++ window library and CLI bridge library
# ---------------------------------------------------------------------------
OBJC_SRC      := src/graphics/Objective_C/window_main.m
OBJC_GDI_SRC  := src/graphics/Objective_C/window_gdi.m
TRACE_WINDOW_SRC := src/graphics/Objective_C/toolbar/window/trace_window.m
OBJCXX_SRC    := src/graphics/Objective_C/cout_bridge.cpp
DEFAULT_SRC    := src/graphics/Objective_C/default_main.cpp
CLI_C_SRC      := src/graphics/CLI/window_main.c
EXT_WIN_SRC   := src/graphics/CLI/extern_window.m
DEBUG_RUNTIME_SRC := src/graphics/common/debug_runtime.c
KEYBOARD_SRC := src/graphics/common/keyboard/rosette_keyboard.m
FB_LOGGER_SRC := src/graphics/fb-logger/fb_logger.m
OBJC_LIB      := librosette_window.a
CLI_LIB       := librosette_cli.a
OBJC_OBJ      := window_main.m.o
OBJC_GDI_OBJ  := window_gdi.o
TRACE_WINDOW_OBJ := trace_window.o
OBJCXX_OBJ    := cout_bridge.o
DEFAULT_OBJ    := default_main.o
CLI_OBJ       := window_main.cli.o
EXT_WIN_OBJ   := extern_window.o
DEBUG_RUNTIME_OBJ := debug_runtime.o
KEYBOARD_OBJ := rosette_keyboard.o
FB_LOGGER_OBJ := fb_logger.o
OBJC_FLAGS := -fobjc-arc -fmodules
OBJC_FRAMEWORKS := -framework Cocoa -framework Foundation

.PHONY: all help check clean zig-build run prodder prodder-all prodder-build window-lib cli-lib snake-window elf-processor-build macho-processor-build elf-processor-dylib avx-shim-build assembler-runner-build compat-router-build shell-helper-build shell shell-update shell-uninstall shell-clean-state exe-list exe-runner-build exe-runner-cleanup exe-run exe-export app-exe-builder-build app-suite-binary app-exe bundled-app-exes app-exe-run app-exe-parse app-wrapper installer uninstaller app-all notarize-installer notarize-uninstaller notarize-app-all c-fix c-fix-build

all: headers-check zig-build test-run

help:
	@printf '%s\n' \
		'Rosette make targets:' \
		'  make              Run headers, Zig, and test checks' \
		'  make headers-check  Run header checks' \
		'  make zig-build    Build Zig sources under include/win32/Zig' \
		'  make run          Build and run test/main.c' \
		'  make prodder      Launch interactive test selector' \
		'  make prodder-all  Run all suites non-interactively (CI)' \
		'  make exe-list     List .exe files available under $(EXE_EXAMPLES_DIR)/' \
		'  make exe-run EXE=$(EXE_EXAMPLES_DIR)/Notepad.exe  Parse/log one .exe intake session' \
		'  make exe-export SRC_EXE=/path/to/file.exe [OUT_EXE=$(EXE_EXAMPLES_DIR)/Game.exe]' \
		'  make app-exe APP_SUITE=basic_snake      Build a Rosette .exe wrapper for one app_testing suite' \
		'  make app-exe-parse APP_SUITE=basic_snake Build and parse one app_testing suite wrapper without launching it' \
		'  make app-exe-run APP_SUITE=basic_snake  Build, parse, and launch one app_testing suite via .exe intake' \
		'  make cli-lib     Build native CLI bridge library (librosette_cli.a)' \
		'  make window-lib  Build native Cocoa console-emulation window library (librosette_window.a)' \
		'  make snake-window Build snake game with native Cocoa window' \
		'  make shell       Install transparent Rosette make-time shell checks' \
		'  make shell-update Refresh the Rosette shell helper/snippet/wrappers' \
		'  make shell-uninstall Remove Rosette shell integration' \
		'  make shell-clean-state Kill stale Rosette shell/ELF helper processes' \
		'  make c-fix        Run C transpiler on C sources to fix implicit narrowing conversions' \
		'  make c-fix-build Build the C transpiler tool' \
		'  zig-out/bin/rosette-router run --prefer-intel /path/to/Xenia.app  Route an Intel macOS app with traced Rosetta 2 fallback' \
		'  make clean        Remove build artifacts'

# Include per-folder make fragments when present
-include include/shims/win32/shim.mk
-include include/win32/Zig/zig.mk
-include test/test.mk
# Reference-only win32 header checks (requires .rosette/include/win32)
ifneq ($(wildcard .rosette/include/win32/win32.mk),)
-include .rosette/include/win32/win32.mk
endif

# Aggregate targets that call included fragments
.PHONY: headers-check
headers-check: shim-check-all
ifneq ($(wildcard .rosette/include/win32/win32.mk),)
headers-check: win32-check-all
endif

.PHONY: zig-build
zig-build: zig-build-all

check:
	@tmp="$$(mktemp /tmp/rosette.XXXXXX.c)"; \
	trap 'rm -f "$$tmp"' EXIT INT TERM; \
	printf '%s\n' '#include "win32/windows_base.h"' 'int main(void) { return 0; }' > "$$tmp"; \
	"$(CC)" $(CFLAGS) -fsyntax-only $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) "$$tmp"

# ---------------------------------------------------------------------------
# C transpiler for fixing implicit narrowing conversions
# ---------------------------------------------------------------------------
C_SOURCES := $(shell find $(ROOT_DIR)/src -name "*.c" -type f 2>/dev/null)

c-fix-build:
	@mkdir -p zig-out/bin build/.zig-cache/global
	@$(ZIG_BUILD_ENV) zig build --build-file build/build.zig --prefix zig-out 2>&1
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


clean: exe-runner-cleanup
	rm -f test_main lib*.dylib lib*.so $(OBJC_OBJ) $(OBJC_GDI_OBJ) $(TRACE_WINDOW_OBJ) $(OBJCXX_OBJ) $(DEFAULT_OBJ) $(EXT_WIN_OBJ) $(CLI_OBJ) $(DEBUG_RUNTIME_OBJ) $(KEYBOARD_OBJ) $(FB_LOGGER_OBJ) $(OBJC_LIB) $(CLI_LIB)
	rm -rf zig-out
	rm -f snake_game app_testing/basic_snake/snake_game

elf-processor-build:
	@mkdir -p zig-out/bin build/.zig-cache/global
	@ZIG_LOCAL_CACHE_DIR=build/.zig-cache ZIG_GLOBAL_CACHE_DIR=build/.zig-cache/global zig build-exe --dep x64_decoder --dep x64_interpreter --dep x64_linux_runtime --dep x64_syscalls --dep x64_guest_abi -Mroot="$(ELF_PROCESSOR_SRC)" -Mx64_decoder=src/x64-ASM/decoder.zig -Mx64_interpreter=src/x64-ASM/interpreter.zig --dep x64_syscalls -Mx64_linux_runtime=src/x64-ASM/linux_runtime.zig -Mx64_syscalls=src/x64-ASM/syscalls.zig -Mx64_guest_abi=src/x64-ASM/guest_abi.zig -femit-bin="$(ELF_PROCESSOR_BIN)"

macho-processor-build:
	@mkdir -p zig-out/bin build/.zig-cache/global
	@ZIG_LOCAL_CACHE_DIR=build/.zig-cache ZIG_GLOBAL_CACHE_DIR=build/.zig-cache/global zig build-exe --dep x64_decoder --dep x64_interpreter --dep macho_runtime --dep exit_diagnostics -lc -Mroot="$(MACHO_PROCESSOR_SRC)" -Mx64_decoder=src/x64-ASM/decoder.zig -Mx64_interpreter=src/x64-ASM/interpreter.zig -Mmacho_runtime=src/x64-ASM/macho_runtime.zig -Mexit_diagnostics=src/tooling/exit_diagnostics/root.zig -femit-bin="$(MACHO_PROCESSOR_BIN)"

elf-processor-dylib:
	@mkdir -p zig-out/lib
	@ZIG_LOCAL_CACHE_DIR=build/.zig-cache ZIG_GLOBAL_CACHE_DIR=build/.zig-cache/global zig cc -dynamiclib -arch arm64 \
		-o "$(DYLD_DYLIB)" \
		"$(ROOT_DIR)/src/shell/dyld/rosette-exec.c" \
		-install_name @rpath/rosette-exec.dylib
	@echo "Built $(DYLD_DYLIB)"

AVX_SHIM_DYLIB := zig-out/lib/avx-shim.dylib
avx-shim-build:
	@mkdir -p zig-out/lib
	@ZIG_LOCAL_CACHE_DIR=build/.zig-cache ZIG_GLOBAL_CACHE_DIR=build/.zig-cache/global zig cc -target x86_64-macos -dynamiclib \
		-o "$(AVX_SHIM_DYLIB)" \
		"$(ROOT_DIR)/src/compat/rosetta2/avx-shim.c" \
		-install_name @rpath/avx-shim.dylib \
		-Wl,-dead_strip_dylibs
	@echo "Built $(AVX_SHIM_DYLIB)"

assembler-runner-build:
	@mkdir -p zig-out/bin build/.zig-cache/global
	@ZIG_LOCAL_CACHE_DIR=build/.zig-cache ZIG_GLOBAL_CACHE_DIR=build/.zig-cache/global zig build-exe -lc --dep runtime_abi_handshake -Mroot=src/Assemblers/runner.zig --dep abort_trap_taxonomy --dep entrypoint_code_text_segment -Mruntime_abi_handshake=src/tooling/runtime-abi-handshake/runtime.zig -Mabort_trap_taxonomy=src/tooling/abort_trap_taxonomy/root.zig -Mentrypoint_code_text_segment=src/entrypoint/code-text-segment/root.zig -femit-bin="$(ASSEMBLER_RUNNER_BIN)"

compat-router-build:
	@mkdir -p zig-out/bin build/.zig-cache/global
	@ZIG_LOCAL_CACHE_DIR=build/.zig-cache ZIG_GLOBAL_CACHE_DIR=build/.zig-cache/global zig build-exe -lc --dep entrypoint_kernel_process_guard --dep exit_diagnostics -Mroot="$(COMPAT_ROUTER_SRC)" -Mentrypoint_kernel_process_guard=src/entrypoint/kernel/process_guard.zig -Mexit_diagnostics=src/tooling/exit_diagnostics/root.zig -femit-bin="$(COMPAT_ROUTER_BIN)"

shell-helper-build: c-fix-build assembler-runner-build elf-processor-build macho-processor-build elf-processor-dylib avx-shim-build compat-router-build
	@mkdir -p zig-out/bin build/.zig-cache/global
	@ZIG_LOCAL_CACHE_DIR=build/.zig-cache ZIG_GLOBAL_CACHE_DIR=build/.zig-cache/global zig build-exe -lc --dep entrypoint_alignment --dep entrypoint_kernel_process_guard --dep compat_source_include_compat --dep compat_third_party_include_compat -Mroot="$(SHELL_HELPER_SRC)" -Mentrypoint_alignment=src/entrypoint/alignment/root.zig -Mentrypoint_kernel_process_guard=src/entrypoint/kernel/process_guard.zig -Mcompat_source_include_compat=src/compat/source/include_compat.zig -Mcompat_third_party_include_compat=src/compat/third_party/include_compat.zig -femit-bin="$(SHELL_HELPER_BIN)"

shell: shell-helper-build
	@"$(SHELL_HELPER_BIN)" install "$(ROOT_DIR)"

shell-update: shell-helper-build
	@"$(SHELL_HELPER_BIN)" update "$(ROOT_DIR)"

shell-uninstall: shell-helper-build
	@"$(SHELL_HELPER_BIN)" uninstall

shell-clean-state: shell-helper-build
	@"$(SHELL_HELPER_BIN)" clean-state

# ---------------------------------------------------------------------------
# Rosette macOS .app bundle, DMG installer, and system uninstaller
# Outputs land in program/ tree at the project root.
# ---------------------------------------------------------------------------
.PHONY: app-wrapper
app-wrapper: mscoree-native shell-helper-build bundled-app-exes
	@mkdir -p program/app
	@echo "Building Rosette.app bundle..."
	@mkdir -p "$(ZIG_GLOBAL_CACHE_DIR)"
	@$(ZIG_BUILD_ENV) zig build bundle --build-file app/bundling/build.zig 2>&1
	@rm -rf program/app/Rosette.app
	@cp -R app/bundling/zig-out/Rosette.app program/app/
	@rm -rf "program/app/Rosette.app/Contents/MacOS/RosetteMscoreeWindow.app"
	@cp -R "$(MSCOREE_NATIVE_HELPER_APP)" "program/app/Rosette.app/Contents/MacOS/"
	@cp "$(ELF_PROCESSOR_BIN)" "program/app/Rosette.app/Contents/MacOS/elf_processor"
	@cp "$(MACHO_PROCESSOR_BIN)" "program/app/Rosette.app/Contents/MacOS/macho_processor"
	@cp "$(DYLD_DYLIB)" "program/app/Rosette.app/Contents/MacOS/rosette-exec.dylib"
	@echo "Signing Rosette.app..."
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/RosetteMscoreeWindow.app/Contents/MacOS/rosette_mscoree_window_helper"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/RosetteMscoreeWindow.app"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/rosette-cli"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/rosette_exe_runner"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/rosette-shell"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/rosette-router"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/elf_processor"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/macho_processor"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/rosette-exec.dylib"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app/Contents/MacOS/rosette"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "program/app/Rosette.app"
	@codesign --verify --deep --strict --verbose=2 "program/app/Rosette.app"
	@echo "Created: program/app/Rosette.app"

.PHONY: installer
installer: app-wrapper
	@mkdir -p program/installer
	@echo "Building Rosette Installer.app..."
	@mkdir -p "$(ZIG_GLOBAL_CACHE_DIR)"
	@$(ZIG_BUILD_ENV) zig build bundle --build-file app/dmg/installer/build.zig -Dpayload-app=program/app/Rosette.app 2>&1
	@echo "Signing Rosette Installer.app..."
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "app/dmg/installer/zig-out/Rosette Installer.app/Contents/MacOS/rosette-install-helper"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "app/dmg/installer/zig-out/Rosette Installer.app/Contents/MacOS/rosette-installer"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/RosetteMscoreeWindow.app/Contents/MacOS/rosette_mscoree_window_helper"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/RosetteMscoreeWindow.app"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/rosette-cli"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/rosette_exe_runner"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/rosette-shell"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/rosette-router"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/elf_processor"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/macho_processor"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/rosette-exec.dylib"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app/Contents/MacOS/rosette"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "app/dmg/installer/zig-out/Rosette Installer.app/Contents/Resources/Rosette.app"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "app/dmg/installer/zig-out/Rosette Installer.app"
	@codesign --verify --deep --strict --verbose=2 "app/dmg/installer/zig-out/Rosette Installer.app"
	@rm -rf /tmp/rosette-installer-dmg
	@mkdir -p /tmp/rosette-installer-dmg
	@cp -R "app/dmg/installer/zig-out/Rosette Installer.app" /tmp/rosette-installer-dmg/
	@echo "Building Rosette DMG installer..."
	@rm -f program/installer/RosetteInstaller.dmg
	@hdiutil create -srcfolder /tmp/rosette-installer-dmg \
		-volname "Rosette Installer" \
		-fs HFS+ -format UDZO \
		-o program/installer/RosetteInstaller.dmg 2>&1
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "program/installer/RosetteInstaller.dmg"
	@codesign --verify --verbose=2 "program/installer/RosetteInstaller.dmg"
	@rm -rf /tmp/rosette-installer-dmg
	@echo "Created: program/installer/RosetteInstaller.dmg"

.PHONY: uninstaller
uninstaller:
	@mkdir -p program/uninstaller
	@echo "Building Rosette Uninstaller.app..."
	@mkdir -p "$(ZIG_GLOBAL_CACHE_DIR)"
	@$(ZIG_BUILD_ENV) zig build bundle --build-file app/dmg/uninstaller/build.zig 2>&1
	@echo "Signing Rosette Uninstaller.app..."
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "app/dmg/uninstaller/zig-out/Rosette Uninstaller.app/Contents/MacOS/rosette-uninstall-helper"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "app/dmg/uninstaller/zig-out/Rosette Uninstaller.app/Contents/MacOS/rosette-uninstaller"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "app/dmg/uninstaller/zig-out/Rosette Uninstaller.app"
	@codesign --verify --deep --strict --verbose=2 "app/dmg/uninstaller/zig-out/Rosette Uninstaller.app"
	@rm -rf /tmp/rosette-uninstaller-dmg
	@mkdir -p /tmp/rosette-uninstaller-dmg
	@cp -R "app/dmg/uninstaller/zig-out/Rosette Uninstaller.app" /tmp/rosette-uninstaller-dmg/
	@rm -f program/uninstaller/RosetteUninstaller.dmg
	@hdiutil create -srcfolder /tmp/rosette-uninstaller-dmg \
		-volname "Rosette Uninstaller" \
		-fs HFS+ -format UDZO \
		-o program/uninstaller/RosetteUninstaller.dmg 2>&1
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "program/uninstaller/RosetteUninstaller.dmg"
	@codesign --verify --verbose=2 "program/uninstaller/RosetteUninstaller.dmg"
	@rm -rf /tmp/rosette-uninstaller-dmg
	@echo "Created: program/uninstaller/RosetteUninstaller.dmg"

app-all: app-wrapper installer uninstaller
	@echo "All Rosette app artifacts built."

notarize-installer:
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
		echo "Set CODESIGN_IDENTITY to your Developer ID Application identity for release downloads."; \
		echo "Example: make notarize-installer CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' CODESIGN_EXTRA_FLAGS='--timestamp --options runtime' NOTARY_PROFILE=rosette-notary"; \
		exit 1; \
	fi
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
		echo "Set NOTARY_PROFILE to an xcrun notarytool keychain profile for release downloads."; \
		echo "Example: make notarize-installer CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' CODESIGN_EXTRA_FLAGS='--timestamp --options runtime' NOTARY_PROFILE=rosette-notary"; \
		exit 1; \
	fi
	@$(MAKE) installer CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" CODESIGN_EXTRA_FLAGS="$(CODESIGN_EXTRA_FLAGS)"
	@echo "Submitting RosetteInstaller.dmg for notarization..."
	@$(NOTARYTOOL) submit "program/installer/RosetteInstaller.dmg" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@$(STAPLER) staple "program/installer/RosetteInstaller.dmg"
	@$(STAPLER) validate "program/installer/RosetteInstaller.dmg"
	@spctl --assess --type open --context context:primary-signature --verbose=2 "program/installer/RosetteInstaller.dmg"

notarize-uninstaller:
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
		echo "Set CODESIGN_IDENTITY to your Developer ID Application identity for release downloads."; \
		echo "Example: make notarize-uninstaller CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' CODESIGN_EXTRA_FLAGS='--timestamp --options runtime' NOTARY_PROFILE=rosette-notary"; \
		exit 1; \
	fi
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
		echo "Set NOTARY_PROFILE to an xcrun notarytool keychain profile for release downloads."; \
		echo "Example: make notarize-uninstaller CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' CODESIGN_EXTRA_FLAGS='--timestamp --options runtime' NOTARY_PROFILE=rosette-notary"; \
		exit 1; \
	fi
	@$(MAKE) uninstaller CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" CODESIGN_EXTRA_FLAGS="$(CODESIGN_EXTRA_FLAGS)"
	@echo "Submitting RosetteUninstaller.dmg for notarization..."
	@$(NOTARYTOOL) submit "program/uninstaller/RosetteUninstaller.dmg" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@$(STAPLER) staple "program/uninstaller/RosetteUninstaller.dmg"
	@$(STAPLER) validate "program/uninstaller/RosetteUninstaller.dmg"
	@spctl --assess --type open --context context:primary-signature --verbose=2 "program/uninstaller/RosetteUninstaller.dmg"

notarize-app-all: notarize-installer notarize-uninstaller
	@echo "Rosette DMG artifacts are signed, notarized, stapled, and ready for upload."

# ---------------------------------------------------------------------------
# Codesigning — required for JIT and unsigned-executable-memory entitlements
# ---------------------------------------------------------------------------
.PHONY: codesign
codesign:
	@if [ -d zig-out ]; then \
		echo "Codesigning zig-out artifacts with $(ENTITLEMENTS)..."; \
		find zig-out -type f \( -name '*.dylib' -o -name '*.so' -o -name '*.a' \) -exec codesign --entitlements "$(ENTITLEMENTS)" --force -s "$(CODESIGN_IDENTITY)" {} \; 2>/dev/null || echo "  (codesign skipped or not applicable)"; \
	else \
		echo "No zig-out directory found; run 'make zig-lib' first."; \
	fi
	@if [ -f "$(ZIG_LIB)" ]; then \
		codesign --entitlements "$(ENTITLEMENTS)" --force -s "$(CODESIGN_IDENTITY)" "$(ZIG_LIB)" 2>/dev/null || true; \
	fi

# ---------------------------------------------------------------------------
# Objective-C window library — native Cocoa console-emulation window
# ---------------------------------------------------------------------------
.PHONY: window-lib cli-lib
window-lib: $(OBJC_LIB)
cli-lib: $(CLI_LIB)

$(OBJC_OBJ): $(OBJC_SRC)
	@"$(CC)" $(OBJC_FLAGS) $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(OBJC_GDI_OBJ): $(OBJC_GDI_SRC)
	@"$(CC)" $(OBJC_FLAGS) $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(TRACE_WINDOW_OBJ): $(TRACE_WINDOW_SRC)
	@"$(CC)" $(OBJC_FLAGS) $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(OBJCXX_OBJ): $(OBJCXX_SRC)
	@"$(CXX)" -std=c++11 $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(DEFAULT_OBJ): $(DEFAULT_SRC)
	@"$(CXX)" -std=c++11 $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(EXT_WIN_OBJ): $(EXT_WIN_SRC)
	@"$(CC)" -fobjc-arc $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(FB_LOGGER_OBJ): $(FB_LOGGER_SRC)
	@"$(CC)" -fobjc-arc $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(CLI_OBJ): $(CLI_C_SRC)
	@"$(CC)" -std=c11 $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(DEBUG_RUNTIME_OBJ): $(DEBUG_RUNTIME_SRC)
	@"$(CC)" -std=c11 $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(KEYBOARD_OBJ): $(KEYBOARD_SRC)
	@"$(CC)" -fobjc-arc $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(OBJC_LIB): $(OBJC_OBJ) $(OBJC_GDI_OBJ) $(TRACE_WINDOW_OBJ) $(OBJCXX_OBJ) $(EXT_WIN_OBJ) $(DEBUG_RUNTIME_OBJ) $(KEYBOARD_OBJ) $(FB_LOGGER_OBJ)
	@ar rcs "$@" $^
	@echo "Built $(OBJC_LIB)"

$(CLI_LIB): $(CLI_OBJ) $(DEBUG_RUNTIME_OBJ)
	@ar rcs "$@" $^
	@echo "Built $(CLI_LIB)"

# ---------------------------------------------------------------------------
# Snake game with native Cocoa window (demo)
# ---------------------------------------------------------------------------
# snake.cpp is compiled directly with -Dmain=rosette_game_main so the
# library's default_main.cpp provides the real main() entry point.
# The binary is placed in the game directory so it finds game.toml.
SNAKE_DIR := app_testing/basic_snake
SNAKE_BIN := snake_game
SNAKE_OUT := $(SNAKE_DIR)/$(SNAKE_BIN)

snake-window: $(ZIG_LIB) $(OBJC_LIB) $(DEFAULT_OBJ)
	@"$(CXX)" -std=c++11 \
		-DROSETTE_WINDOW_MODE -Dmain=rosette_game_main \
		$(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$(SNAKE_DIR)/snake.cpp" -o "$(SNAKE_DIR)/$(SNAKE_BIN).o" 2>&1
	@"$(CXX)" "$(SNAKE_DIR)/$(SNAKE_BIN).o" $(DEFAULT_OBJ) $(OBJC_LIB) $(ZIG_LIB) \
		$(OBJC_FRAMEWORKS) -o "$(SNAKE_OUT)" 2>&1
	@echo "Built $(SNAKE_OUT) — run with ./$(SNAKE_OUT)"
	@rm -f "$(SNAKE_DIR)/$(SNAKE_BIN).o"

.PHONY: run
run: test-run-all

# ---------------------------------------------------------------------------
# Test Prodder — interactive and non-interactive suite selector
# ---------------------------------------------------------------------------

prodder-build:
	@"$(CC)" $(CFLAGS) -o tools/test_prodder tools/test_prodder.c

# Interactive menu: make prodder
# Run a specific suite: make prodder SUITE=win32
prodder: window-lib cli-lib
	@$(MAKE) prodder-build
	@if [ -n "$(SUITE)" ]; then \
		./tools/test_prodder --suite "$(SUITE)"; \
	else \
		./tools/test_prodder; \
	fi

# Non-interactive: runs every suite (good for CI / make all)
prodder-all: window-lib cli-lib
	@$(MAKE) prodder-build
	@./tools/test_prodder --all

exe-list:
	@find "$(EXE_EXAMPLES_DIR)" -maxdepth 1 -type f \( -name '*.exe' -o -name '*.EXE' \) | sort

MSCOREE_NATIVE_DIR := $(DLL_ASSETS_DIR)/mscoree
MSCOREE_NATIVE_LIB := zig-out/bin/libmscoree_native.dylib
MSCOREE_NATIVE_HELPER := zig-out/bin/rosette_mscoree_window_helper
MSCOREE_NATIVE_HELPER_APP := zig-out/bin/RosetteMscoreeWindow.app
MSCOREE_NATIVE_HELPER_APP_BIN := $(MSCOREE_NATIVE_HELPER_APP)/Contents/MacOS/rosette_mscoree_window_helper
MSCOREE_NATIVE_WINDOW_SRC := $(MSCOREE_NATIVE_DIR)/mscoree_window.m
MSCOREE_NATIVE_HELPER_SRC := $(MSCOREE_NATIVE_DIR)/mscoree_window_helper.m
MSCOREE_WARNINGS := -Wno-format -Wno-incompatible-pointer-types -Wno-unsequenced -Wno-visibility
MSCOREE_CFLAGS := -O2 -std=c11 $(MSCOREE_WARNINGS) $(MACOS_SHIM_INC) -Iinclude/shims/win32 $(REFERENCE_INC) -Iinclude -I$(MSCOREE_NATIVE_DIR)
MSCOREE_OBJC_FLAGS := -O2 -fobjc-arc $(MACOS_SHIM_INC) -Iinclude/shims/win32 $(REFERENCE_INC) -Iinclude -I$(MSCOREE_NATIVE_DIR)
MSCOREE_FRAMEWORKS := -framework Cocoa -framework Foundation

mscoree-native: $(MSCOREE_NATIVE_LIB) $(MSCOREE_NATIVE_HELPER) $(MSCOREE_NATIVE_HELPER_APP)

$(MSCOREE_NATIVE_LIB): $(MSCOREE_NATIVE_DIR)/mscoree_main.c $(MSCOREE_NATIVE_DIR)/mscoree_stubs.c $(MSCOREE_NATIVE_WINDOW_SRC) $(TRACE_WINDOW_SRC)
	@mkdir -p zig-out/bin
	@"$(CC)" $(MSCOREE_CFLAGS) -c "$(MSCOREE_NATIVE_DIR)/mscoree_main.c" -o /tmp/mscoree_main.o
	@"$(CC)" $(MSCOREE_CFLAGS) -c "$(MSCOREE_NATIVE_DIR)/mscoree_stubs.c" -o /tmp/mscoree_stubs.o
	@"$(CC)" $(MSCOREE_OBJC_FLAGS) -c "$(MSCOREE_NATIVE_WINDOW_SRC)" -o /tmp/mscoree_window.o
	@"$(CC)" $(MSCOREE_OBJC_FLAGS) -c "$(TRACE_WINDOW_SRC)" -o /tmp/trace_window.o
	@"$(CC)" -shared /tmp/mscoree_main.o /tmp/mscoree_stubs.o /tmp/mscoree_window.o /tmp/trace_window.o $(MSCOREE_FRAMEWORKS) -o "$@"
	@echo "Built $(MSCOREE_NATIVE_LIB)"

$(MSCOREE_NATIVE_HELPER): $(MSCOREE_NATIVE_WINDOW_SRC) $(MSCOREE_NATIVE_HELPER_SRC) $(TRACE_WINDOW_SRC)
	@mkdir -p zig-out/bin
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
	@mkdir -p zig-out/bin
	@mkdir -p "$(ZIG_GLOBAL_CACHE_DIR)"
	@$(ZIG_BUILD_ENV) zig build exe-runner --build-file app/bundling/build.zig 2>&1
	@cp app/bundling/zig-out/bin/rosette_exe_runner "$(EXE_RUNNER_BIN)"

gate-runner-build: exe-runner-build

exe-runner-cleanup:
	@-pkill -TERM -f '$(ROSETTE_RUNNER_KILL_PATTERN)' 2>/dev/null || true
	@-pkill -TERM -f '$(ROSETTE_HOST_KILL_PATTERN)' 2>/dev/null || true
	@sleep 0.2
	@-pkill -KILL -f '$(ROSETTE_RUNNER_KILL_PATTERN)' 2>/dev/null || true
	@-pkill -KILL -f '$(ROSETTE_HOST_KILL_PATTERN)' 2>/dev/null || true

app-exe-builder-build:
	@mkdir -p zig-out/bin
	@ZIG_LOCAL_CACHE_DIR=build/.zig-cache ZIG_GLOBAL_CACHE_DIR=build/.zig-cache/global zig build-exe "$(APP_EXE_BUILDER_SRC)" -femit-bin="$(APP_EXE_BUILDER_BIN)"

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
