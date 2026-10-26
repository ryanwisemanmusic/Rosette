# Targets owned by app/. Keep recipes local to this folder.


.PHONY: app-wrapper installer uninstaller app-all release notarize-preflight notarize-installer notarize-uninstaller notarize-app-all codesign

# ---------------------------------------------------------------------------
# Rosette macOS .app bundle, DMG installer, and system uninstaller
# Outputs land in program/ tree at the project root.
# Keep repository-relative package paths under ASSET_PREFIX because this
# Makefile supports invocation from either the repository root or build/.
# ---------------------------------------------------------------------------
ROSETTE_APP_BUNDLE := $(ASSET_PREFIX)app/bundling/zig-out/Rosette.app
ROSETTE_APP_OUTPUT := $(ASSET_PREFIX)program/app/Rosette.app
ROSETTE_INSTALLER_BUNDLE := $(ASSET_PREFIX)app/dmg/installer/zig-out/Rosette Installer.app
ROSETTE_INSTALLER_DMG := $(ASSET_PREFIX)program/installer/RosetteInstaller.dmg
ROSETTE_UNINSTALLER_BUNDLE := $(ASSET_PREFIX)app/dmg/uninstaller/zig-out/Rosette Uninstaller.app
ROSETTE_UNINSTALLER_DMG := $(ASSET_PREFIX)program/uninstaller/RosetteUninstaller.dmg


app-wrapper: mscoree-native shell-helper-build
	@mkdir -p "$(ASSET_PREFIX)program/app"
	@echo "Building Rosette.app bundle..."
	@mkdir -p "$(ZIG_GLOBAL_CACHE_DIR)"
	@$(ZIG_BUILD_ENV) zig build bundle --build-file $(APP_BP)app/bundling/build.zig $(APP_BUNDLE_RELEASE_FLAG) 2>&1
	@rm -rf \
		"$(ROSETTE_APP_BUNDLE)/Contents/Resources/rosette-runtime/app_testing" \
		"$(ROSETTE_APP_BUNDLE)/Contents/Resources/rosette-runtime/assets/exe_examples" \
		"$(ROSETTE_APP_BUNDLE)/Contents/Resources/rosette-runtime/include/assets/exe_examples" \
		"$(ROSETTE_APP_BUNDLE)/Contents/Resources/rosette-runtime/tools/test_prodder"
	@# Source resource trees can contain local test traces and interpreter caches.
	@# They are neither runtime inputs nor release assets; remove them before copying/signing.
	@find "$(ROSETTE_APP_BUNDLE)" -type d \( -name .rosette -o -name __pycache__ -o -name .pytest_cache \) -prune -exec rm -rf {} +
	@find "$(ROSETTE_APP_BUNDLE)" -type f \( -name .DS_Store -o -name '*.pyc' -o -name '*.pyo' \) -exec rm -f {} +
	@if find "$(ROSETTE_APP_BUNDLE)" \( -type d -name app_testing -o -type d -path '*/assets/exe_examples' \) -print -quit | grep -q .; then \
		echo "error: app_testing or bundled example payload entered Rosette.app"; \
		exit 1; \
	fi
	@rm -rf "$(ROSETTE_APP_OUTPUT)"
	@cp -R "$(ROSETTE_APP_BUNDLE)" "$(ASSET_PREFIX)program/app/"
	@rm -rf \
		"$(ROSETTE_APP_OUTPUT)/Contents/Resources/rosette-runtime/app_testing" \
		"$(ROSETTE_APP_OUTPUT)/Contents/Resources/rosette-runtime/assets/exe_examples" \
		"$(ROSETTE_APP_OUTPUT)/Contents/Resources/rosette-runtime/include/assets/exe_examples" \
		"$(ROSETTE_APP_OUTPUT)/Contents/Resources/rosette-runtime/tools/test_prodder"
	@find "$(ROSETTE_APP_OUTPUT)" -type d \( -name .rosette -o -name __pycache__ -o -name .pytest_cache \) -prune -exec rm -rf {} +
	@find "$(ROSETTE_APP_OUTPUT)" -type f \( -name .DS_Store -o -name '*.pyc' -o -name '*.pyo' \) -exec rm -f {} +
	@if find "$(ROSETTE_APP_OUTPUT)" \( -type d -name app_testing -o -type d -path '*/assets/exe_examples' \) -print -quit | grep -q .; then \
		 echo "error: app_testing or bundled example payload entered the distributable Rosette.app"; \
		 exit 1; \
	fi
	@if find "$(ROSETTE_APP_OUTPUT)" \( -type d \( -name .rosette -o -name __pycache__ -o -name .pytest_cache \) -o -type f \( -name .DS_Store -o -name '*.pyc' -o -name '*.pyo' \) \) -print -quit | grep -q .; then \
		echo "error: local traces or generated cache files entered the distributable Rosette.app"; \
		exit 1; \
	fi
	@if [ -e "$(ROSETTE_APP_OUTPUT)/Contents/Resources/rosette-runtime/tools/test_prodder" ]; then \
		echo "error: development test helper entered the distributable Rosette.app"; \
		exit 1; \
	fi
	@rm -rf "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/RosetteMscoreeWindow.app"
	@cp -R "$(MSCOREE_NATIVE_HELPER_APP)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/"
	@cp "$(ELF_PROCESSOR_BIN)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/elf_processor"
	@cp "$(MACHO_PROCESSOR_BIN)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/macho_processor"
	@cp "$(DYLD_DYLIB)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/rosette-exec.dylib"
	@echo "Signing Rosette.app..."
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/RosetteMscoreeWindow.app/Contents/MacOS/rosette_mscoree_window_helper"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/RosetteMscoreeWindow.app"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/rosette-cli"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/rosette_assembler_runner"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/rosette_exe_runner"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/rosette-shell"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/rosette-router"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/elf_processor"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/macho_processor"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/rosette-exec.dylib"
	@# zig cc links the x86_64 AVX shim unsigned; the bundle signature below
	@# refuses any unsigned subcomponent, so sign it with the rest.
	@if [ -f "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/avx-shim.dylib" ]; then codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/avx-shim.dylib"; fi
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)/Contents/MacOS/rosette"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_APP_OUTPUT)"
	@codesign --verify --deep --strict --verbose=2 "$(ROSETTE_APP_OUTPUT)"
	@echo "Created: $(ROSETTE_APP_OUTPUT)"

installer: app-wrapper
	@mkdir -p $(ASSET_PREFIX)program/installer
	@echo "Building Rosette Installer.app..."
	@mkdir -p "$(ZIG_GLOBAL_CACHE_DIR)"
	@rm -rf "$(ROSETTE_INSTALLER_BUNDLE)"
	@$(ZIG_BUILD_ENV) zig build bundle --build-file $(APP_BP)app/dmg/installer/build.zig -Dpayload-app="$(ROOT_DIR)/program/app/Rosette.app" 2>&1
	@find "$(ROSETTE_INSTALLER_BUNDLE)" -type d \( -name .rosette -o -name __pycache__ -o -name .pytest_cache \) -prune -exec rm -rf {} +
	@find "$(ROSETTE_INSTALLER_BUNDLE)" -type f \( -name .DS_Store -o -name '*.pyc' -o -name '*.pyo' \) -exec rm -f {} +
	@if find "$(ROSETTE_INSTALLER_BUNDLE)" \( -type d -name app_testing -o -type d -path '*/assets/exe_examples' \) -print -quit | grep -q .; then \
		echo "error: app_testing or bundled example payload entered Rosette Installer.app"; \
		exit 1; \
	fi
	@if find "$(ROSETTE_INSTALLER_BUNDLE)" \( -type d \( -name .rosette -o -name __pycache__ -o -name .pytest_cache \) -o -type f \( -name .DS_Store -o -name '*.pyc' -o -name '*.pyo' \) \) -print -quit | grep -q .; then \
		echo "error: local traces or generated cache files entered Rosette Installer.app"; \
		exit 1; \
	fi
	@if [ -e "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/Resources/rosette-runtime/tools/test_prodder" ]; then \
		echo "error: development test helper entered Rosette Installer.app"; \
		exit 1; \
	fi
	@echo "Signing Rosette Installer.app..."
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "$(ROSETTE_INSTALLER_BUNDLE)/Contents/MacOS/rosette-install-helper"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "$(ROSETTE_INSTALLER_BUNDLE)/Contents/MacOS/rosette-installer"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/RosetteMscoreeWindow.app/Contents/MacOS/rosette_mscoree_window_helper"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/RosetteMscoreeWindow.app"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/rosette-cli"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/rosette_assembler_runner"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/rosette_exe_runner"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/rosette-shell"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/rosette-router"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/elf_processor"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/macho_processor"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/rosette-exec.dylib"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app/Contents/MacOS/rosette"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) --entitlements "$(ENTITLEMENTS)" "$(ROSETTE_INSTALLER_BUNDLE)/Contents/Resources/Rosette.app"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "$(ROSETTE_INSTALLER_BUNDLE)"
	@codesign --verify --deep --strict --verbose=2 "$(ROSETTE_INSTALLER_BUNDLE)"
	@rm -rf /tmp/rosette-installer-dmg
	@mkdir -p /tmp/rosette-installer-dmg
	@cp -R "$(ROSETTE_INSTALLER_BUNDLE)" /tmp/rosette-installer-dmg/
	@echo "Building Rosette DMG installer..."
	@rm -f "$(ROSETTE_INSTALLER_DMG)"
	@hdiutil create -srcfolder /tmp/rosette-installer-dmg \
		-volname "Rosette Installer" \
		-fs HFS+ -format UDZO \
		-o "$(ROSETTE_INSTALLER_DMG)" 2>&1
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(DMG_CODESIGN_FLAGS) "$(ROSETTE_INSTALLER_DMG)"
	@codesign --verify --verbose=2 "$(ROSETTE_INSTALLER_DMG)"
	@if [ "$(RELEASE_BUILD)" = "1" ] && ! codesign -dv --verbose=4 "$(ROSETTE_INSTALLER_DMG)" 2>&1 | grep -q '^Timestamp='; then \
		echo "error: release DMG was signed without a secure timestamp"; \
		exit 1; \
	fi
	@rm -rf /tmp/rosette-installer-dmg
	@echo "Created: $(ROSETTE_INSTALLER_DMG)"

uninstaller:
	@mkdir -p $(ASSET_PREFIX)program/uninstaller
	@echo "Building Rosette Uninstaller.app..."
	@mkdir -p "$(ZIG_GLOBAL_CACHE_DIR)"
	@$(ZIG_BUILD_ENV) zig build bundle --build-file $(APP_BP)app/dmg/uninstaller/build.zig 2>&1
	@find "$(ROSETTE_UNINSTALLER_BUNDLE)" -type d \( -name .rosette -o -name __pycache__ -o -name .pytest_cache \) -prune -exec rm -rf {} +
	@find "$(ROSETTE_UNINSTALLER_BUNDLE)" -type f \( -name .DS_Store -o -name '*.pyc' -o -name '*.pyo' \) -exec rm -f {} +
	@if find "$(ROSETTE_UNINSTALLER_BUNDLE)" \( -type d \( -name .rosette -o -name __pycache__ -o -name .pytest_cache \) -o -type f \( -name .DS_Store -o -name '*.pyc' -o -name '*.pyo' \) \) -print -quit | grep -q .; then \
		echo "error: local traces or generated cache files entered Rosette Uninstaller.app"; \
		exit 1; \
	fi
	@echo "Signing Rosette Uninstaller.app..."
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "$(ROSETTE_UNINSTALLER_BUNDLE)/Contents/MacOS/rosette-uninstall-helper"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "$(ROSETTE_UNINSTALLER_BUNDLE)/Contents/MacOS/rosette-uninstaller"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "$(ROSETTE_UNINSTALLER_BUNDLE)"
	@codesign --verify --deep --strict --verbose=2 "$(ROSETTE_UNINSTALLER_BUNDLE)"
	@rm -rf /tmp/rosette-uninstaller-dmg
	@mkdir -p /tmp/rosette-uninstaller-dmg
	@cp -R "$(ROSETTE_UNINSTALLER_BUNDLE)" /tmp/rosette-uninstaller-dmg/
	@rm -f "$(ROSETTE_UNINSTALLER_DMG)"
	@hdiutil create -srcfolder /tmp/rosette-uninstaller-dmg \
		-volname "Rosette Uninstaller" \
		-fs HFS+ -format UDZO \
		-o "$(ROSETTE_UNINSTALLER_DMG)" 2>&1
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(DMG_CODESIGN_FLAGS) "$(ROSETTE_UNINSTALLER_DMG)"
	@codesign --verify --verbose=2 "$(ROSETTE_UNINSTALLER_DMG)"
	@if [ "$(RELEASE_BUILD)" = "1" ] && ! codesign -dv --verbose=4 "$(ROSETTE_UNINSTALLER_DMG)" 2>&1 | grep -q '^Timestamp='; then \
		echo "error: release DMG was signed without a secure timestamp"; \
		exit 1; \
	fi
	@rm -rf /tmp/rosette-uninstaller-dmg
	@echo "Created: $(ROSETTE_UNINSTALLER_DMG)"

# Developer-ID builds are notarized and stapled as part of the normal app-all
# workflow. Ad-hoc source builds remain local-only and do not contact Apple.
ifeq ($(CODESIGN_IDENTITY),-)
app-all: app-wrapper installer uninstaller
	@echo "Built local ad-hoc artifacts (not for external distribution)."
else
app-all: notarize-app-all
	@echo "Built signed, notarized, stapled Rosette release artifacts."
endif

# Compatibility alias for release automation.
release: app-all


# Check release signing and notarization access before either DMG is rebuilt.
# `history` is a read-only API request; it validates the keychain profile and
# account access without submitting an artifact.
notarize-preflight:
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
		echo "Set CODESIGN_IDENTITY to your Developer ID Application identity for release downloads."; \
		echo "A valid identity can be selected automatically from the macOS keychain when exactly one is installed."; \
		exit 1; \
	fi
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
		echo "Set NOTARY_PROFILE to an xcrun notarytool keychain profile for release downloads."; \
		exit 1; \
	fi
	@echo "Checking Apple notarization access with profile '$(NOTARY_PROFILE)'..."
	@notary_log=$$(mktemp "$${TMPDIR:-/tmp}/rosette-notary-preflight.XXXXXX"); \
	if ! $(NOTARYTOOL) history --keychain-profile "$(NOTARY_PROFILE)" --output-format json >"$$notary_log" 2>&1; then \
		if grep -qi "A required agreement is missing or has expired" "$$notary_log"; then \
			echo "error: Apple blocked notarization because a required Developer Program agreement is missing or expired."; \
			echo "The Account Holder must review and accept current terms at https://developer.apple.com/account/"; \
		else \
			cat "$$notary_log"; \
			echo "error: Apple notarization preflight failed; check the keychain profile and developer account status."; \
		fi; \
		rm -f "$$notary_log"; \
		exit 1; \
	fi; \
	rm -f "$$notary_log"; \
	echo "Apple notarization access: ready."

notarize-installer: notarize-preflight
	@$(MAKE) installer RELEASE_BUILD=1 CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" CODESIGN_EXTRA_FLAGS="$(CODESIGN_EXTRA_FLAGS)"
	@echo "Submitting RosetteInstaller.dmg for notarization..."
	@$(NOTARYTOOL) submit "$(ROSETTE_INSTALLER_DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@$(STAPLER) staple "$(ROSETTE_INSTALLER_DMG)"
	@$(STAPLER) validate "$(ROSETTE_INSTALLER_DMG)"
	@spctl --assess --type open --context context:primary-signature --verbose=2 "$(ROSETTE_INSTALLER_DMG)"

notarize-uninstaller: notarize-preflight
	@$(MAKE) uninstaller RELEASE_BUILD=1 CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" CODESIGN_EXTRA_FLAGS="$(CODESIGN_EXTRA_FLAGS)"
	@echo "Submitting RosetteUninstaller.dmg for notarization..."
	@$(NOTARYTOOL) submit "$(ROSETTE_UNINSTALLER_DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@$(STAPLER) staple "$(ROSETTE_UNINSTALLER_DMG)"
	@$(STAPLER) validate "$(ROSETTE_UNINSTALLER_DMG)"
	@spctl --assess --type open --context context:primary-signature --verbose=2 "$(ROSETTE_UNINSTALLER_DMG)"

notarize-app-all: notarize-installer notarize-uninstaller
	@echo "Rosette DMG artifacts are signed, notarized, stapled, and ready for upload."

# ---------------------------------------------------------------------------
# Codesigning — required for JIT and unsigned-executable-memory entitlements
# ---------------------------------------------------------------------------
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
