Whenever we make changes to any aspect of the program, 'make shell-update' is the command most frequently used to ensure that the code integrates against the global shell associated with Rosette, and also checks for any significant issues that may be incompatible with the shell

This command is dependent on quite a lot of Makefile related commands:

``` Makefile
   shell-update: shell-helper-build

   @"$(SHELL_HELPER_BIN)" update "$(ROOT_DIR)"
```


Our shell helper bin is what contains the global shell, and since when we want to update the global shell, we are likely in Rosette, the ROOT_DIR is obviously referencing Rosette. To understand it, the shell-helper-build puts all integral components related to what needs to exist in the global shell. 
```Makefile

shell-helper-build: c-fix-build assembler-runner-build elf-processor-build macho-processor-build elf-processor-dylib avx-shim-build compat-router-build

@mkdir -p zig-out/bin build/.zig-cache/global

@ZIG_LOCAL_CACHE_DIR=build/.zig-cache ZIG_GLOBAL_CACHE_DIR=build/.zig-cache/global zig build-exe -lc --dep entrypoint_alignment --dep entrypoint_kernel_process_guard --dep compat_source_include_compat --dep compat_third_party_include_compat -Mroot="$(SHELL_HELPER_SRC)" -Mentrypoint_alignment=src/entrypoint/alignment/root.zig -Mentrypoint_kernel_process_guard=src/entrypoint/kernel/process_guard.zig -Mcompat_source_include_compat=src/compat/source/include_compat.zig -Mcompat_third_party_include_compat=src/compat/third_party/include_compat.zig -femit-bin="$(SHELL_HELPER_BIN)"
```

So our ELF Processor and Mach-O Processor are essential components to parsing any x86-64 project, and therefore are bundled into the shell we rely on
