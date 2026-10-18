# Test orchestration owned by test/. The Zig fragment is anchored at ROOT_DIR
# so both `make` and `make -C build` load the same test targets.
include $(ASSET_PREFIX)test/test.mk

.PHONY: run prodder prodder-all prodder-build

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
