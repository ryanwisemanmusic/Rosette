.PHONY: zig-build-local
zig-build-local:
	@echo "Zig build: building include/win32/Zig sources...";
	@if ! command -v zig >/dev/null 2>&1; then echo "zig not found in PATH"; exit 1; fi
	@if [ ! -f build.zig ]; then echo "no build.zig found; nothing to build"; exit 0; fi
	@zig build --build-file build.zig install || exit $$?; \
	echo "Zig build complete"

.PHONY: zig-build-all
zig-build-all: zig-build-local
