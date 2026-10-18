ROOT_DIR := $(CURDIR)
.DEFAULT_GOAL := all
COORD_BUILD_FILE = $(ROOT_DIR)/build.zig

# Detect invocation directory to support both
#   cd build && make  (from build/ dir) and
#   make              (from repo root)
# NB: $(abspath) splits on spaces, so we use suffix substitution instead.
ifneq ($(shell test -f "$(CURDIR)/../build.zig" && echo build-subdirectory),)
# CWD is the build/ directory: strip final /build, no BP prefix needed
ROOT_DIR := $(ROOT_DIR:/build=)
BP :=
APP_BP := ../
ASSET_PREFIX := ../
else
# CWD is the repo root: BP prefix needed for build/ paths
BP := build/
APP_BP :=
ASSET_PREFIX :=
endif

INCLUDE_DIR := $(ROOT_DIR)/include
SHIM_DIR := $(INCLUDE_DIR)/shims/win32
MACOS_SHIM_DIR := $(INCLUDE_DIR)/shims/macos
WIN32_DIR := $(INCLUDE_DIR)/win32

# Signing credentials are optional and machine-local. Keep a private default
# beside generated Rosette state; release automation can point at another file
# with ROSETTE_SIGNING_ENV without editing this Makefile.
ROSETTE_SIGNING_ENV ?= $(ASSET_PREFIX).rosette/signing.env
empty :=
space := $(empty) $(empty)
make_escape_spaces = $(subst $(space),\$(space),$(1))
# The checked-in policy in .rosette carries Rosette's macOS ABI floor into
# every Make-driven Zig/C build. It records the development SDK for context,
# but only the deployment target is enforced; a newer installed SDK is valid.
ROSETTE_BUILD_ENVIRONMENT ?= $(ASSET_PREFIX).rosette/build-environment.mk
-include $(call make_escape_spaces,$(ROSETTE_BUILD_ENVIRONMENT))
ROSETTE_MACOS_DEPLOYMENT_TARGET ?= 13.0
MACOSX_DEPLOYMENT_TARGET := $(ROSETTE_MACOS_DEPLOYMENT_TARGET)
export MACOSX_DEPLOYMENT_TARGET
-include $(call make_escape_spaces,$(ROSETTE_SIGNING_ENV))
export
# GNU make can be started with user-global MAKEFILES hooks. Keep those hooks
# in this top-level invocation instead of reloading them in nested make calls;
# their exported MAKEFILE_LIST may be split when this checkout path has spaces.
unexport MAKEFILES MAKEFILE_LIST

CC ?= clang
CXX ?= clang++
CFLAGS ?= -Wall -Wextra -Wno-ignored-attributes
ZIG_VERSION ?= 0.16.0
ZIG_CACHE_DIR := $(ROOT_DIR)/build/.zig-cache
ZIG_GLOBAL_CACHE_DIR := $(ZIG_CACHE_DIR)/global
ZIG_OUT_DIR := $(ROOT_DIR)/zig-out
# Keep the assignments shell-quoted: the repository lives in a path with a
# space on this host, and unquoted cache paths turn the next word into a
# command (which made app-wrapper fail before the bundle was produced).
ZIG_BUILD_ENV := ZIG_LOCAL_CACHE_DIR="$(ZIG_CACHE_DIR)" ZIG_GLOBAL_CACHE_DIR="$(ZIG_GLOBAL_CACHE_DIR)"
# Always use release fast since running with safety on means ~180k instructions per second
# Safety on is only useful if you want run time to take 5x times longer
ROSETTE_RUNTIME_OPTIMIZE ?= ReleaseFast

# app/bundling/build.zig asks for the optimize mode with
# `standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast })`, and
# that spelling means "ReleaseFast *when the release option is set*, Debug
# otherwise" - it does not register a `-Doptimize` option at all. Both targets
# below therefore built the shipped runner with `-ODebug` and every module
# with runtime safety checks on, which for an instruction interpreter is the
# whole difference between a run that reaches a frame and one that does not.
APP_BUNDLE_RELEASE_FLAG := $(if $(filter Debug,$(ROSETTE_RUNTIME_OPTIMIZE)),,-Drelease=true)
ZIG_LIB := $(ZIG_OUT_DIR)/lib/librosette_zig.a
EXE_RUNNER_BIN := $(ZIG_OUT_DIR)/bin/rosette_exe_runner
ASSEMBLER_RUNNER_BIN := $(ZIG_OUT_DIR)/bin/rosette_assembler_runner
APP_EXE_BUILDER_SRC := $(ROOT_DIR)/src/tooling/exe_parser/rosette_app_exe.zig
APP_EXE_BUILDER_BIN := $(ZIG_OUT_DIR)/bin/rosette_app_exe
ELF_PROCESSOR_BIN := $(ZIG_OUT_DIR)/bin/elf_processor
ELF_PROCESSOR_SRC := $(ROOT_DIR)/lib/processor/ELF_processor/main.zig
MACHO_PROCESSOR_BIN := $(ZIG_OUT_DIR)/bin/macho_processor
MACHO_PROCESSOR_SRC := $(ROOT_DIR)/lib/Mach-O/main.zig
ROSETTE_PACKAGE_MANAGER := $(ROOT_DIR)/pkg/registry/rosette-package-manager.sh
# The Makefile path is also used by shell-update, outside build.zig.
# Keep its route package selection aligned with the native host that is
# compiling Rosette. The package contributes facts only; it is not executable
# Xenia code.
# Route-independent: this package describes the guest x86-64 SysV convention,
# which does not change with the host Rosette is compiled for. It has no ARM64
# mirror and therefore no entry in the `uname -m` block below.
COMMON_RECEIVER_CLASSIFICATION_SRC := pkg/common/abi/receiver-classification/src/root.zig
XENOS_REGISTER_MAP_SRC := pkg/common/xenos/register-map/src/root.zig
NEAR_NULL_SHAPE_SRC := pkg/common/abi/near-null-shape/src/root.zig
XENIA_LOG_PHRASE_MAP_SRC := pkg/common/console/log-phrase-map/src/root.zig
HOST_CONTRACT_CATALOGUE_SRC := pkg/common/abi/host-contract-catalogue/src/root.zig
LIBCPP_THREAD_ABI_SRC := pkg/common/abi/libcpp-thread-struct/src/root.zig
PHRASE_FILTER_SRC := pkg/common/text/phrase-filter/src/root.zig
XENIA_READY_PLAN_SRC := pkg/common/console/ready-plan/src/root.zig
# Console-hardware and kernel-ABI contracts. Route-independent: they describe
# the Xbox 360 and its kernel, not the host Rosette is compiled for, so they
# have no entry in the `uname -m` block below.
XENIA_AUDIO_CONTRACT_SRC := pkg/common/console/audio-contract/src/root.zig
XENIA_INPUT_CONTRACT_SRC := pkg/common/console/input-contract/src/root.zig
XENIA_USER_CONTRACT_SRC := pkg/common/console/user-contract/src/root.zig
XENIA_CONFIG_SCHEMA_SRC := pkg/common/console/config-schema/src/root.zig
XENIA_SHADER_CONTRACT_SRC := pkg/common/console/shader-contract/src/root.zig
XENIA_RENDER_TARGET_CONTRACT_SRC := pkg/common/console/render-target-contract/src/root.zig
XENIA_TEXTURE_CONTRACT_SRC := pkg/common/console/texture-contract/src/root.zig
XENIA_IO_COMPLETION_CONTRACT_SRC := pkg/common/console/io-completion-contract/src/root.zig
XENIA_TIMER_CONTRACT_SRC := pkg/common/console/timer-contract/src/root.zig
XENIA_OB_CONTRACT_SRC := pkg/common/console/ob-contract/src/root.zig
XENIA_MOUNT_CONTRACT_SRC := pkg/common/console/mount-contract/src/root.zig
XENIA_KERNEL_OBJECT_CONTRACT_SRC := pkg/common/console/kernel-object-contract/src/root.zig
# Transcribed from Xenia's own export tables, packet enums and container
# headers. Console/kernel facts, so route independent like the rest above.
XENIA_KERNEL_EXPORT_MAP_SRC := pkg/common/console/kernel-export-map/src/root.zig
XENIA_VD_RING_CONTRACT_SRC := pkg/common/console/vd-ring-contract/src/root.zig
XENIA_PM4_CONTRACT_SRC := pkg/common/console/pm4-contract/src/root.zig
XENIA_XEX_FORMAT_SRC := pkg/common/console/xex-format/src/root.zig
XENIA_NOTIFICATION_CONTRACT_SRC := pkg/common/console/notification-contract/src/root.zig
XENIA_LOG_RING_CONTRACT_SRC := pkg/common/console/log-ring-contract/src/root.zig
XENIA_XTHREAD_CONTRACT_SRC := pkg/common/console/xthread-contract/src/root.zig
XENIA_VFS_DEVICE_CONTRACT_SRC := pkg/common/console/vfs-device-contract/src/root.zig
XENIA_GRAPHICS_CONTRACT_SRC := pkg/x86/console/graphics-contract/src/root.zig
XENIA_SURFACE_PATH_CONTRACT_SRC := pkg/x86/console/graphics/surface-path-contract/src/root.zig
XENIA_SHADER_STORAGE_CONTRACT_SRC := pkg/x86/console/runtime/shader-storage-contract/src/root.zig
XENIA_PRIMITIVE_CONTRACT_SRC := pkg/x86/console/runtime/primitive-contract/src/root.zig
XENIA_LAUNCH_PHASE_MAP_SRC := pkg/x86/console/runtime/launch-phase-map/src/root.zig
XENIA_ABI_BRIDGE_SRC := pkg/x86/console/bridge/abi-bridge/src/root.zig
XENIA_GUEST_BRIDGE_SRC := pkg/x86/console/runtime/guest-bridge/src/root.zig
XENIA_CODEGEN_ACTIVATION_SRC := pkg/x86/console/runtime/codegen-activation/src/root.zig
XENIA_WAIT_CONTRACT_SRC := pkg/x86/console/runtime/wait-contract/src/root.zig
XENIA_TRANSLATION_PROGRESS_SRC := pkg/x86/console/runtime/translation-progress/src/root.zig
XENIA_HEAP_RANGE_SRC := pkg/x86/console/memory/heap-range/src/root.zig
# This package's module root is the evidence table, not a `root.zig`; the
# `main.zig` beside it is the standalone CLI and is not linked here.
XENIA_STARTUP_EVIDENCE_SRC := pkg/x86/console/diagnostics/startup-evidence/src/evidence.zig
XENIA_AUDIO_DRIVER_SRC := pkg/x86/console/audio-driver/src/root.zig
XENIA_INPUT_DRIVER_SRC := pkg/x86/console/input-driver/src/root.zig
XENIA_SIMD_SHIM_MAP_SRC := pkg/x86/console/simd-shim-map/src/root.zig
ifeq ($(shell uname -m),arm64)
XENIA_GRAPHICS_CONTRACT_SRC := pkg/ARM64/console/graphics-contract/src/root.zig
XENIA_SURFACE_PATH_CONTRACT_SRC := pkg/ARM64/console/graphics/surface-path-contract/src/root.zig
XENIA_SHADER_STORAGE_CONTRACT_SRC := pkg/ARM64/console/runtime/shader-storage-contract/src/root.zig
XENIA_PRIMITIVE_CONTRACT_SRC := pkg/ARM64/console/runtime/primitive-contract/src/root.zig
XENIA_LAUNCH_PHASE_MAP_SRC := pkg/ARM64/console/runtime/launch-phase-map/src/root.zig
XENIA_ABI_BRIDGE_SRC := pkg/ARM64/console/bridge/abi-bridge/src/root.zig
XENIA_GUEST_BRIDGE_SRC := pkg/ARM64/console/runtime/guest-bridge/src/root.zig
XENIA_CODEGEN_ACTIVATION_SRC := pkg/ARM64/console/runtime/codegen-activation/src/root.zig
XENIA_WAIT_CONTRACT_SRC := pkg/ARM64/console/runtime/wait-contract/src/root.zig
XENIA_TRANSLATION_PROGRESS_SRC := pkg/ARM64/console/runtime/translation-progress/src/root.zig
XENIA_HEAP_RANGE_SRC := pkg/ARM64/console/memory/heap-range/src/root.zig
XENIA_STARTUP_EVIDENCE_SRC := pkg/ARM64/console/diagnostics/startup-evidence/src/evidence.zig
XENIA_AUDIO_DRIVER_SRC := pkg/ARM64/console/audio-driver/src/root.zig
XENIA_INPUT_DRIVER_SRC := pkg/ARM64/console/input-driver/src/root.zig
XENIA_SIMD_SHIM_MAP_SRC := pkg/ARM64/console/simd-shim-map/src/root.zig
endif
MACHO_NATIVE_WINDOW_OBJ := $(ROOT_DIR)/$(BP)macho_native_window_bridge.o
XENIA_HEAP_ANCHOR_OBJ := $(ROOT_DIR)/$(BP)guest_heap_exports_anchor.o
ROSETTE_PPC_ANCHOR_OBJ := $(ROOT_DIR)/$(BP)rosette_ppc_exports_anchor.o
DYLD_DYLIB := $(ZIG_OUT_DIR)/lib/rosette-exec.dylib
SHELL_HELPER_SRC := $(ROOT_DIR)/src/shell/global_config/rosette_shell.zig
SHELL_HELPER_BIN := $(ZIG_OUT_DIR)/bin/rosette-shell
TEST_CENSUS_SCRIPT := $(ROOT_DIR)/tools/test_census.py
TEST_CENSUS_OUT := $(ROOT_DIR)/.rosette/test-census.json
XENIA_RUN_SYSTEMS_TEST := $(ROOT_DIR)/tools/test_guest_run_systems.py
XENIA_RUN_LAUNCHER := $(ROOT_DIR)/tools/guest_runtime/scripts/rosette-guest-run.sh
SHELL_UPDATE_RECORD_SCRIPT := $(ROOT_DIR)/tools/record_shell_update.py
SHELL_UPDATE_RECORD_OUT := $(ROOT_DIR)/.rosette/shell-update.json
SHELL_UPDATE_SMART_SCRIPT := $(ROOT_DIR)/tools/smart_shell_update.py
SHELL_UPDATE_SYSTEM_TEST := $(ROOT_DIR)/tools/test_shell_update.py
BUILD_IDENTITY_SCRIPT := $(ROOT_DIR)/tools/build_identity_manifest.py
BUILD_IDENTITY_OUT := $(ROOT_DIR)/.rosette/build-identity.json
AUDIT_PHASE_COVERAGE_SCRIPT := $(ROOT_DIR)/tools/audit_phase_coverage.py
AUDIT_PHASE_COVERAGE_OUT := $(ROOT_DIR)/.rosette/audit-phase-coverage.json
XENIA_FORK_MANIFEST_SCRIPT := $(ROOT_DIR)/tools/build_guest_fork_manifest.py
XENIA_FORK_MANIFEST_OUT := $(ROOT_DIR)/.rosette/xenia-fork-manifest.json
# The run script (tools/guest_runtime/scripts/rosette-guest-run.sh) writes the run
# log under .rosette/xenia-runs/; the older location is kept as the fallback
# so a log from before that change is still audited.
XENIA_SOURCE_LOG = $(shell if [ -f "$(XENIA_ROOT)/.rosette/xenia-runs/rosette-xenia.log" ]; then printf '%s' "$(XENIA_ROOT)/.rosette/xenia-runs/rosette-xenia.log"; else printf '%s' "$(XENIA_ROOT)/.rosette/rosette-xenia.log"; fi)
WARNING_LEDGER_SCRIPT := $(ROOT_DIR)/tools/audit_warning_ledger.py
WARNING_LEDGER_OUT := $(ROOT_DIR)/.rosette/warning-ledger.json
GENERATED_TRACE_SCRIPT := $(ROOT_DIR)/tools/analyze_generated_code_trace.py
GENERATED_TRACE_OUT := $(ROOT_DIR)/.rosette/generated-code-trace.json
# Xenia is an optional external input, never a machine-specific mount point.
# Set ROSETTE_XENIA_ROOT (or XENIA_ROOT) when a source comparison is wanted.
# The absent-source sentinel is project-relative and lets shell refreshes record
# that Xenia was unavailable without confusing the Rosetta tree for Xenia.
XENIA_ROOT ?= $(if $(strip $(ROSETTE_XENIA_ROOT)),$(ROSETTE_XENIA_ROOT),$(ROOT_DIR)/.rosette/xenia-source-unavailable)
XENIA_WINDOWS_BUILD_SCRIPT := $(ROOT_DIR)/tools/guest_runtime/scripts/rosette-guest-windows.sh
XENIA_WINDOWS_SOURCE_ROOT ?= $(XENIA_ROOT)
XENIA_WINDOWS_BUILD_DIR ?= $(ROOT_DIR)/build/xenia-windows
XENIA_WINDOWS_BUNDLE_DIR ?= $(XENIA_WINDOWS_BUILD_DIR)/bundle
XENIA_WINDOWS_CONFIG ?= Release
XENIA_WINDOWS_TARGET ?= xenia-app
XENIA_WINDOWS_JOBS ?=
XENIA_WINDOWS_MEDIA_IMAGE ?=
EVIDENCE_REPLAY_SCRIPT := $(ROOT_DIR)/tools/replay_evidence.py
EVIDENCE_FIXTURE_SCRIPT := $(ROOT_DIR)/tools/create_evidence_fixture.py
EVIDENCE_REPLAY_JOURNAL ?= $(ROOT_DIR)/.rosette/rosette-evidence.r3j
EVIDENCE_REPLAY_OUT := $(ROOT_DIR)/.rosette/evidence-replay.json
COMPAT_ROUTER_SRC := $(ROOT_DIR)/src/compat/rosetta2/main.zig
COMPAT_ROUTER_BIN := $(ZIG_OUT_DIR)/bin/rosette-router
LINK_AUDIT_SRC := src/tooling/link-audit/main.zig
LINK_AUDIT_BIN := $(ZIG_OUT_DIR)/bin/rosette-link-audit
C_FIX_BIN := $(ZIG_OUT_DIR)/bin/rosette-c-fix

AVX_SHIM_DYLIB := $(ZIG_OUT_DIR)/lib/avx-shim.dylib
# Keep the default asset root anchored to the repository.  This Makefile is
# intentionally invocable from either the repository root or build/, while a
# relative default here made the native DLL prerequisites disappear when the
# latter form was used.
ASSETS_DIR ?= $(if $(wildcard $(ASSET_PREFIX)assets/dll/mscoree),$(ASSET_PREFIX)assets,$(ASSET_PREFIX)include/assets)
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

# Prefer an explicitly configured Developer ID. When it is absent, discover
# the sole valid Developer ID Application certificate in the macOS keychain.
# This lets the normal `make app-all` path select release signing without a
# per-shell export, while avoiding an arbitrary choice when several identities
# are installed.
APPLE_KEYCHAIN_DEVELOPER_ID_COUNT := 0
ifeq ($(shell uname -s),Darwin)
APPLE_KEYCHAIN_DEVELOPER_ID_COUNT := $(shell /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F '"' '/Developer ID Application:/ { count++ } END { print count + 0 }')
ifeq ($(strip $(APPLE_DEVELOPER_ID)),)
ifeq ($(APPLE_KEYCHAIN_DEVELOPER_ID_COUNT),1)
APPLE_DEVELOPER_ID := $(shell /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F '"' '/Developer ID Application:/ { print $$2 }')
endif
endif
endif

# Do not silently make a local ad-hoc build when multiple release identities
# could be selected. The caller can resolve that ambiguity explicitly.
ifneq ($(filter app-all release notarize-app-all notarize-installer notarize-uninstaller,$(MAKECMDGOALS)),)
ifeq ($(strip $(APPLE_DEVELOPER_ID)$(CODESIGN_IDENTITY)),)
ifneq ($(APPLE_KEYCHAIN_DEVELOPER_ID_COUNT),0)
$(error Found $(APPLE_KEYCHAIN_DEVELOPER_ID_COUNT) valid Developer ID Application identities; set APPLE_DEVELOPER_ID or CODESIGN_IDENTITY explicitly)
endif
endif
endif

# Entitlements for codesigning (JIT, unsigned-executable-memory, etc.)
ifneq ($(APPLE_DEVELOPER_ID),)
    CODESIGN_IDENTITY ?= $(APPLE_DEVELOPER_ID)
    INSTALLER_SIGN_IDENTITY ?= $(APPLE_INSTALLER_ID)
    CODESIGN_EXTRA_FLAGS ?= --timestamp --options runtime
    BUILD_TYPE := "Official Release"
else
    CODESIGN_IDENTITY ?= -
    INSTALLER_SIGN_IDENTITY ?= -
CODESIGN_EXTRA_FLAGS ?=
    BUILD_TYPE := "Developer Build (Ad-hoc)"
endif

# Environment files may preserve literal quote characters around an identity.
# Remove them before passing the value to codesign; unlike patsubst this also
# works when the identity contains spaces.
CODESIGN_IDENTITY := $(subst ",,$(CODESIGN_IDENTITY))

# Timestamping is required only for the publish/notarize workflow. Keeping it
# separate lets `make app-all` produce locally testable signed artifacts.
RELEASE_BUILD ?= 0
DMG_CODESIGN_FLAGS := $(if $(filter 1,$(RELEASE_BUILD)),--timestamp,)

RELEASE_ENTITLEMENTS := $(BP)rosette-release.entitlements
ADHOC_ENTITLEMENTS := $(BP)rosette-adhoc.entitlements
ENTITLEMENTS := $(if $(filter -,$(CODESIGN_IDENTITY)),$(ADHOC_ENTITLEMENTS),$(RELEASE_ENTITLEMENTS))
NOTARY_PROFILE ?= rosette-notary
NOTARYTOOL ?= xcrun notarytool
STAPLER ?= xcrun stapler

# On macOS, prepend the LLP64 override shim so it wins the include lookup
# for "win32/windows_base.h" over the upstream-mirrored shim/canonical.
ifeq ($(shell uname -s),Darwin)
MACOS_SHIM_INC := -I$(ASSET_PREFIX)include/shims/macos
else
MACOS_SHIM_INC :=
endif
# Reference header path (the canonical win32 headers mirrored upstream)
REFERENCE_INC := -I$(ASSET_PREFIX).rosette/include
SHIM_INC := -I$(ASSET_PREFIX)include/shims/win32 $(REFERENCE_INC)
INCLUDE_INC := -I$(ASSET_PREFIX)include
export MACOS_SHIM_INC

# ---------------------------------------------------------------------------
# Objective-C / C++ window library and CLI bridge library
# ---------------------------------------------------------------------------
OBJC_SRC      := src/graphics/Objective_C/window_main.m
OBJC_GDI_SRC  := src/graphics/Objective_C/window_gdi.m
TRACE_WINDOW_SRC := $(ASSET_PREFIX)src/graphics/Objective_C/toolbar/window/trace_window.m
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

ISO_BIN := $(ZIG_OUT_DIR)/bin/rosette-iso
ISO_SRC := $(ROOT_DIR)/src/tooling/iso/main.zig
XBOX360_MEDIA_TOOL := $(ROOT_DIR)/tools/xbox360_media.py

.PHONY: all help check clean zig-build headers-check verify-creds

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
		'  make shell-update Smart change-aware refresh; unknown changes use the full sanity path' \
		'  make shell-update-relink Refresh installed shell integration from already-built artifacts' \
		'  make shell-update-elf-processor-process-impl Check/build/install only ELF process implementation changes' \
		'  make shell-update-elf-processor-windows-runtime Check/build/install ELF Win32 runtime changes' \
		'  make shell-update-elf-processor Check/build/install ELF processor changes' \
		'  make shell-update-elf-processor-block-jit Check/build/install block translator changes' \
		'  make shell-update-macho-processor Check/build/install Mach-O processor changes' \
		'  make shell-update-dyld-forwarder Check/build/install dyld forwarder changes' \
		'  make shell-update-all Full sanity check (complete Zig census and audits; allow 20 minutes or longer)' \
		'  make test-census  Execute zig build check and write the source/artifact test census' \
		'  make xenia-run-systems-check  Verify Rosetta run manager, benchmark, and admission tooling' \
		'  make xenia-fork-manifest  Record the pinned Xenia base and classify every fork path' \
		'  make xenia-fork-manifest-shell-update  Record an unavailable source if the external Xenia drive is unmounted' \
		'  make xenia-windows-prepare  Stage an isolated Windows Xenia source mirror and support capsule' \
		'  make xenia-windows-build    Configure/build/bundle the Rosette-owned Windows Xenia PE' \
		'  make build-identity  Hash Rosette/Xenia/build/test/shell inputs into an admission manifest' \
		'  make replay-evidence Replay a durable .r3j journal without the original runtime (or create the no-Xenia fixture)' \
		'  make vendor-audit Audit vendored library sources, target records, and host providers' \
		'  make diagnostic-audit Run bounded disassembly, warning-ledger, and generated-code checks' \
		'  make shell-uninstall Remove Rosette shell integration' \
		'  make shell-clean-state Kill stale Rosette shell/ELF helper processes' \
		'  make install-packages  Choose optional packages from the Rosette release catalog' \
		'  make install-packages-all  Install every package in the Rosette release catalog' \
		'  make c-fix        Run C transpiler on C sources to fix implicit narrowing conversions' \
		'  make c-fix-build Build the C transpiler tool' \
		'  make iso-build       Build the ISO 9660 file inspector tool\n' \
		'  make iso-run ISO=... Parse and inspect an ISO 9660 image\n' \
		'  make run-iso          Prompt for ISO path and inspect it\n' \
		'  make xbox360-media-self-test  Test GOD/XISO media validation and recovery\n' \
		'  make clean        Remove build artifacts'

# Folder-local build fragments are included at the end of this coordinator.

# Aggregate targets that call included fragments
.PHONY: headers-check
headers-check: shim-check-all
ifneq ($(wildcard $(ROOT_DIR)/.rosette/include/win32/win32.mk),)
headers-check: win32-check-all
endif

# Check to ensure that we are properly signing the application
.PHONY: verify-creds
verify-creds:
	@echo 'Build Type: $(BUILD_TYPE)'
	@echo 'CODESIGN_IDENTITY: $(CODESIGN_IDENTITY)'
	@echo 'CODESIGN_EXTRA_FLAGS: $(CODESIGN_EXTRA_FLAGS)'
	@echo 'APPLE_DEVELOPER_ID: $(APPLE_DEVELOPER_ID)'
	@echo 'APPLE_TEAM_ID: $(APPLE_TEAM_ID)'
	@echo 'APPLE_ID: $(APPLE_ID)'
	@echo 'APP_PASSWORD: [HIDDEN]'

.PHONY: zig-build
zig-build: zig-build-all

check:
	@tmp="$$(mktemp /tmp/rosette.XXXXXX.c)"; \
	trap 'rm -f "$$tmp"' EXIT INT TERM; \
	printf '%s\n' '#include "win32/windows_base.h"' 'int main(void) { return 0; }' > "$$tmp"; \
	"$(CC)" $(CFLAGS) -fsyntax-only $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) "$$tmp"


clean: exe-runner-cleanup
	rm -f test_main lib*.dylib lib*.so $(OBJC_OBJ) $(OBJC_GDI_OBJ) $(TRACE_WINDOW_OBJ) $(OBJCXX_OBJ) $(DEFAULT_OBJ) $(EXT_WIN_OBJ) $(CLI_OBJ) $(DEBUG_RUNTIME_OBJ) $(KEYBOARD_OBJ) $(FB_LOGGER_OBJ) $(OBJC_LIB) $(CLI_LIB)
	rm -rf zig-out
	rm -f snake_game app_testing/basic_snake/snake_game

# Folder-level Makefiles own the targets that build or verify their area.
# Keep shared path/toolchain/signing setup above and high-level coordination here.
include $(ASSET_PREFIX)include/Makefile
include $(ASSET_PREFIX)lib/processor/Makefile
include $(ASSET_PREFIX)src/Assemblers/Makefile
include $(ASSET_PREFIX)src/compat/Makefile
include $(ASSET_PREFIX)src/tooling/Makefile
include $(ASSET_PREFIX)tools/Makefile
include $(ASSET_PREFIX)src/shell/Makefile
include $(ASSET_PREFIX)pkg/Makefile
include $(ASSET_PREFIX)app/Makefile
include $(ASSET_PREFIX)lib/graphics/Makefile
include $(ASSET_PREFIX)test/Makefile
include $(ASSET_PREFIX)app/bundling/Makefile
