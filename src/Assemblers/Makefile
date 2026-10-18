# Targets owned by src/Assemblers/. Keep recipes local to this folder.


.PHONY: assembler-runner-build

assembler-runner-build:
	@mkdir -p "$(ZIG_CACHE_DIR)/global"
	@cd "$(ROOT_DIR)" && ZIG_LOCAL_CACHE_DIR="$(ZIG_CACHE_DIR)" ZIG_GLOBAL_CACHE_DIR="$(ZIG_GLOBAL_CACHE_DIR)" zig build-exe -lc --dep runtime_abi_handshake -Mroot=src/Assemblers/runner.zig --dep abort_trap_taxonomy --dep entrypoint_code_text_segment -Mruntime_abi_handshake=src/tooling/runtime-abi-handshake/runtime.zig -Mabort_trap_taxonomy=src/tooling/abort_trap_taxonomy/root.zig -Mentrypoint_code_text_segment=src/entrypoint/code-text-segment/root.zig -femit-bin="$(ASSEMBLER_RUNNER_BIN)"
