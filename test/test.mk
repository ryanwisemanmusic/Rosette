REFERENCE_INC ?= -I.rosette/include
ZIG_LIB := zig-out/lib/librosette_zig.a

.PHONY: zig-lib
zig-lib:
	@if ! command -v zig >/dev/null 2>&1; then echo "zig not found in PATH"; exit 1; fi
	@zig build --build-file build.zig install || exit $$?

.PHONY: test-run
test-run: zig-lib
	@echo "Building and running test/main.c...";
	@if [ -f test/main.c ]; then \
		clang $(MACOS_SHIM_INC) -I"include/shims/win32" $(REFERENCE_INC) -I"include" test/main.c test/host_stubs.c "$(ZIG_LIB)" -o test_main || true; \
		if [ -x ./test_main ]; then ./test_main || true; fi; \
	else \
		echo "no test/main.c found"; \
	fi

.PHONY: test-run-all
test-run-all: zig-lib
	@echo "Building and running all test/*.c files..."; \
	files=$$(find test -type f -name '*.c' ! -name 'host_stubs.c' | sort); \
	if [ -z "$$files" ]; then echo "no test sources found"; exit 0; fi; \
	for source in $$files; do \
		binary=$$(basename "$${source%.*}"); \
		clang $(MACOS_SHIM_INC) -I"include/shims/win32" $(REFERENCE_INC) -I"include" "$$source" test/host_stubs.c "$(ZIG_LIB)" -o "$$binary" || exit $$?; \
		./"$$binary" || exit $$?; \
		rm -f "$$binary"; \
	done
