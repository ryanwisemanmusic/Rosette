# Header and Zig helper rules owned by include/. Paths are anchored at ROOT_DIR
# because the root coordinator also supports `make -C build`.
-include $(ASSET_PREFIX)include/shims/win32/shim.mk
-include $(ASSET_PREFIX)include/win32/Zig/zig.mk
ifneq ($(wildcard $(ASSET_PREFIX).rosette/include/win32/win32.mk),)
-include $(ASSET_PREFIX).rosette/include/win32/win32.mk
endif
