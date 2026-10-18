# Targets owned by lib/graphics/. Keep recipes local to this folder.


.PHONY: window-lib cli-lib snake-window

# ---------------------------------------------------------------------------
# Objective-C window library — native Cocoa console-emulation window
# ---------------------------------------------------------------------------
window-lib: $(OBJC_LIB)
cli-lib: $(CLI_LIB)

$(OBJC_OBJ): $(OBJC_SRC)
	@"$(CC)" $(OBJC_FLAGS) $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(OBJC_GDI_OBJ): $(OBJC_GDI_SRC)
	@"$(CC)" $(OBJC_FLAGS) $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(TRACE_WINDOW_OBJ): $(TRACE_WINDOW_SRC)
	@"$(CC)" $(OBJC_FLAGS) $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(OBJCXX_OBJ): $(OBJCXX_SRC)
	@"$(CXX)" -std=c++11 $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(DEFAULT_OBJ): $(DEFAULT_SRC)
	@"$(CXX)" -std=c++11 $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(EXT_WIN_OBJ): $(EXT_WIN_SRC)
	@"$(CC)" -fobjc-arc $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(FB_LOGGER_OBJ): $(FB_LOGGER_SRC)
	@"$(CC)" -fobjc-arc $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(CLI_OBJ): $(CLI_C_SRC)
	@"$(CC)" -std=c11 $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(DEBUG_RUNTIME_OBJ): $(DEBUG_RUNTIME_SRC)
	@"$(CC)" -std=c11 $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(KEYBOARD_OBJ): $(KEYBOARD_SRC)
	@"$(CC)" -fobjc-arc $(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$<" -o "$@" 2>&1

$(OBJC_LIB): $(OBJC_OBJ) $(OBJC_GDI_OBJ) $(TRACE_WINDOW_OBJ) $(OBJCXX_OBJ) $(EXT_WIN_OBJ) $(DEBUG_RUNTIME_OBJ) $(KEYBOARD_OBJ) $(FB_LOGGER_OBJ)
	@ar rcs "$@" $^
	@echo "Built $(OBJC_LIB)"

$(CLI_LIB): $(CLI_OBJ) $(DEBUG_RUNTIME_OBJ)
	@ar rcs "$@" $^
	@echo "Built $(CLI_LIB)"

# ---------------------------------------------------------------------------
# Snake game with native Cocoa window (demo)
# ---------------------------------------------------------------------------
# snake.cpp is compiled directly with -Dmain=rosette_game_main so the
# library's default_main.cpp provides the real main() entry point.
# The binary is placed in the game directory so it finds game.toml.
SNAKE_DIR := app_testing/basic_snake
SNAKE_BIN := snake_game
SNAKE_OUT := $(SNAKE_DIR)/$(SNAKE_BIN)

snake-window: $(ZIG_LIB) $(OBJC_LIB) $(DEFAULT_OBJ)
	@"$(CXX)" -std=c++11 \
		-DROSETTE_WINDOW_MODE -Dmain=rosette_game_main \
		$(MACOS_SHIM_INC) $(SHIM_INC) $(INCLUDE_INC) \
		-c "$(SNAKE_DIR)/snake.cpp" -o "$(SNAKE_DIR)/$(SNAKE_BIN).o" 2>&1
	@"$(CXX)" "$(SNAKE_DIR)/$(SNAKE_BIN).o" $(DEFAULT_OBJ) $(OBJC_LIB) $(ZIG_LIB) \
		$(OBJC_FRAMEWORKS) -o "$(SNAKE_OUT)" 2>&1
	@echo "Built $(SNAKE_OUT) — run with ./$(SNAKE_OUT)"
	@rm -f "$(SNAKE_DIR)/$(SNAKE_BIN).o"
