# Targets owned by pkg/. Keep recipes local to this folder.


.PHONY: install-packages install-packages-all

# Package archives are fetched from the HTTPS release index and installed in
# ~/.rosette/packages after checksum and archive-path validation. The same
# manager is bundled into Rosette.app for the graphical installer. Override
# ROSETTE_PACKAGE_INDEX_URL for a staging HTTPS registry.
install-packages:
	@ROSETTE_PACKAGE_INDEX_URL="$(ROSETTE_PACKAGE_INDEX_URL)" /bin/bash "$(ROSETTE_PACKAGE_MANAGER)" install

install-packages-all:
	@ROSETTE_PACKAGE_INDEX_URL="$(ROSETTE_PACKAGE_INDEX_URL)" /bin/bash "$(ROSETTE_PACKAGE_MANAGER)" install-all
