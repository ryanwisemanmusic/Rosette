# Targets owned by tools/. Keep recipes local to this folder.


.PHONY: pkg-boundary-audit isa-execution-audit build-routes-audit dll-coverage-audit guest-context-audit xenia-vendor-source-audit vendor-library-audit vendor-audit diagnostic-audit test-census xenia-run-systems-check source-budget-check shell-update-system-check audit-phase-coverage xenia-fork-manifest xenia-fork-manifest-shell-update xenia-windows-prepare xenia-windows-build build-identity evidence-fixture replay-evidence

pkg-boundary-audit:
	@cd "$(ROOT_DIR)" && python3 tools/audit_pkg_boundary.py

# A decoder that can name an instruction the interpreter cannot run compiles
# cleanly and passes every test; it is only visible by running a guest. The
# 2026-09-08 `sub rsp, imm32` gap stopped initializer 1 of 724 that way.
isa-execution-audit:
	@cd "$(ROOT_DIR)" && python3 tools/audit_isa_execution.py --root "$(ROOT_DIR)"

# The ELF processor is built three times from three files that name their
# modules independently. A module wired into one route and not the others
# compiles for whoever ran that route; on 2026-09-12 it left the runner the
# Xenia launcher executes unbuildable while every other route was green.
build-routes-audit:
	@cd "$(ROOT_DIR)" && python3 tools/audit_build_routes.py

# Every name the guest imports must be declared by exactly one pkg/dll/win32
# package, and every declaration must match what the dispatcher actually
# handles. A declaration that has gone stale is worse than none, because the
# refusal report trusts it.
dll-coverage-audit:
	@cd "$(ROOT_DIR)" && python3 tools/audit_dll_coverage.py

# Code that runs on a guest thread's behalf reaches registers through
# lib/guest_context, never through the PE state's own fields, which are the
# process owner's live context. On 2026-09-26 the Windows Vulkan adapter lent
# the UI thread's register file to the Emulator thread's calls, and the UI
# thread jumped into the Emulator thread's stack.
guest-context-audit:
	@cd "$(ROOT_DIR)" && python3 tools/audit_guest_context_access.py

xenia-vendor-source-audit:
	@cd "$(ROOT_DIR)" && python3 tools/check_guest_vendor.py

vendor-library-audit: xenia-vendor-source-audit
	@if [ -d "$(XENIA_ROOT)" ]; then \
		cd "$(ROOT_DIR)" && python3 tools/check_vendor_libraries.py --xenia-root "$(XENIA_ROOT)"; \
	else \
		echo "vendor audit: Xenia source comparison SKIP (checkout unavailable at $(XENIA_ROOT)); vendored sources, host providers, and ABI probes still run"; \
		cd "$(ROOT_DIR)" && python3 tools/check_vendor_libraries.py; \
	fi

vendor-audit: vendor-library-audit

diagnostic-audit:
	@cd "$(ROOT_DIR)" && bash tools/test_native_readback_capture.sh
	@cd "$(ROOT_DIR)" && python3 tools/generate_vulkan_argument_widths.py --check
	@cd "$(ROOT_DIR)" && python3 tools/rosette_adjacent_disasm.py --self-test
	@cd "$(ROOT_DIR)" && python3 "$(WARNING_LEDGER_SCRIPT)" --self-test
	@cd "$(ROOT_DIR)" && python3 "$(GENERATED_TRACE_SCRIPT)" --self-test
	@if [ -f "$(XENIA_SOURCE_LOG)" ]; then cd "$(ROOT_DIR)" && python3 "$(WARNING_LEDGER_SCRIPT)" --log "$(XENIA_SOURCE_LOG)" --format json > "$(WARNING_LEDGER_OUT)"; else echo "diagnostic-audit: warning ledger SKIP (no Xenia source log)"; fi
	@if [ -f "$(XENIA_SOURCE_LOG)" ]; then cd "$(ROOT_DIR)" && python3 "$(GENERATED_TRACE_SCRIPT)" --log "$(XENIA_SOURCE_LOG)" --format json > "$(GENERATED_TRACE_OUT)"; else echo "diagnostic-audit: generated-code trace SKIP (no Xenia source log)"; fi
test-census:
	@cd "$(ROOT_DIR)" && python3 "$(ROOT_DIR)/tools/test_test_census.py"
	@cd "$(ROOT_DIR)" && python3 "$(TEST_CENSUS_SCRIPT)" --root "$(ROOT_DIR)" --output "$(TEST_CENSUS_OUT)" --run-check --strict

xenia-run-systems-check:
	@cd "$(ROOT_DIR)" && python3 "$(XENIA_RUN_SYSTEMS_TEST)"
	@bash -n "$(XENIA_RUN_LAUNCHER)"

source-budget-check:
	@cd "$(ROOT_DIR)" && python3 tools/audit_source_size.py

shell-update-system-check:
	@cd "$(ROOT_DIR)" && python3 "$(SHELL_UPDATE_SYSTEM_TEST)"
	@cd "$(ROOT_DIR)" && python3 tools/test_build_organization.py

# The six-phase matrix is source-only and deliberately does not inspect or
# execute Xenia. Its hash is included in build identity so a green test census
# cannot hide a stale cross-boundary contract.
audit-phase-coverage:
	@cd "$(ROOT_DIR)" && python3 "$(AUDIT_PHASE_COVERAGE_SCRIPT)" --root "$(ROOT_DIR)" --output "$(AUDIT_PHASE_COVERAGE_OUT)"

# The fork manifest is source-only and never invokes Xenia.  It is kept as a
# separate artifact so an identity can bind the classification and pinned
# base without pretending that a source census is a behavior proof.
xenia-fork-manifest:
	@cd "$(ROOT_DIR)" && python3 "$(XENIA_FORK_MANIFEST_SCRIPT)" --root "$(XENIA_ROOT)" --output "$(XENIA_FORK_MANIFEST_OUT)"

# Shell updates do not need the external Xenia checkout. If its removable
# drive is absent, preserve that fact in an unavailable manifest and continue;
# build-identity and authentic run admission remain strict about Xenia source.
xenia-fork-manifest-shell-update:
	@cd "$(ROOT_DIR)" && python3 "$(XENIA_FORK_MANIFEST_SCRIPT)" --root "$(XENIA_ROOT)" --output "$(XENIA_FORK_MANIFEST_OUT)" --allow-missing-root

# Replay is a release gate even on a clean checkout. Preserve a real journal
# if one exists; otherwise create the deterministic source-only fixture so the
# verifier proves its envelope and causal-order path without running Xenia.
evidence-fixture:
	@if [ -f "$(EVIDENCE_REPLAY_JOURNAL)" ]; then \
		echo "evidence-fixture: preserving existing $(EVIDENCE_REPLAY_JOURNAL)"; \
	elif [ "$(EVIDENCE_REPLAY_JOURNAL)" = "$(ROOT_DIR)/.rosette/rosette-evidence.r3j" ]; then \
		cd "$(ROOT_DIR)" && python3 "$(EVIDENCE_FIXTURE_SCRIPT)" --output "$(EVIDENCE_REPLAY_JOURNAL)"; \
	else \
		echo "evidence-fixture: missing custom journal $(EVIDENCE_REPLAY_JOURNAL)" >&2; \
		exit 1; \
	fi

# The Windows path is deliberately isolated from the supplied Xenia checkout.
# The adapter mirrors the complete source tree before CMake generates version,
# dependency, shader, and resource artifacts, then emits a runnable PE bundle.
xenia-windows-prepare:
	@cd "$(ROOT_DIR)" && bash "$(XENIA_WINDOWS_BUILD_SCRIPT)" --source-root "$(XENIA_WINDOWS_SOURCE_ROOT)" --build-dir "$(XENIA_WINDOWS_BUILD_DIR)" --bundle-dir "$(XENIA_WINDOWS_BUNDLE_DIR)" --config "$(XENIA_WINDOWS_CONFIG)" --target "$(XENIA_WINDOWS_TARGET)" $(if $(strip $(XENIA_WINDOWS_JOBS)),--jobs "$(XENIA_WINDOWS_JOBS)",) $(if $(strip $(XENIA_WINDOWS_MEDIA_IMAGE)),--media-image "$(XENIA_WINDOWS_MEDIA_IMAGE)",) --prepare

xenia-windows-build:
	@cd "$(ROOT_DIR)" && bash "$(XENIA_WINDOWS_BUILD_SCRIPT)" --source-root "$(XENIA_WINDOWS_SOURCE_ROOT)" --build-dir "$(XENIA_WINDOWS_BUILD_DIR)" --bundle-dir "$(XENIA_WINDOWS_BUNDLE_DIR)" --config "$(XENIA_WINDOWS_CONFIG)" --target "$(XENIA_WINDOWS_TARGET)" $(if $(strip $(XENIA_WINDOWS_JOBS)),--jobs "$(XENIA_WINDOWS_JOBS)",) $(if $(strip $(XENIA_WINDOWS_MEDIA_IMAGE)),--media-image "$(XENIA_WINDOWS_MEDIA_IMAGE)",) --configure --build --bundle

# The manifest is deliberately generated after the check artifacts exist. It
# hashes their bytes and the shell-update record, while keeping filesystem
# paths as metadata only. It never invokes Xenia.
build-identity: shell-helper-build test-census xenia-run-systems-check audit-phase-coverage xenia-fork-manifest replay-evidence
	@cd "$(ROOT_DIR)" && python3 "$(BUILD_IDENTITY_SCRIPT)" --root "$(ROOT_DIR)" --xenia-root "$(XENIA_ROOT)" --helper "$(SHELL_HELPER_BIN)" --census "$(TEST_CENSUS_OUT)" --shell-update "$(SHELL_UPDATE_RECORD_OUT)" --fork-manifest "$(XENIA_FORK_MANIFEST_OUT)" --phase-coverage "$(AUDIT_PHASE_COVERAGE_OUT)" --evidence-replay "$(EVIDENCE_REPLAY_OUT)" --output "$(BUILD_IDENTITY_OUT)"

replay-evidence: evidence-fixture
	@cd "$(ROOT_DIR)" && python3 "$(EVIDENCE_REPLAY_SCRIPT)" "$(EVIDENCE_REPLAY_JOURNAL)" --json > "$(EVIDENCE_REPLAY_OUT)"
	@cd "$(ROOT_DIR)" && python3 "$(EVIDENCE_REPLAY_SCRIPT)" "$(EVIDENCE_REPLAY_JOURNAL)"

shell shell-update shell-update-all shell-update-relink shell-update-elf-processor shell-update-elf-processor-process-impl shell-update-elf-processor-windows-runtime shell-update-elf-processor-block-jit shell-update-macho-processor shell-update-dyld-forwarder: override ROSETTE_RUNTIME_OPTIMIZE := ReleaseFast
