const title_runtime = @import("../title_runtime.zig");
const win32_thunks = @import("../win32/root.zig");
const program = @import("trail_program.zig");
const thunks = @import("trail_thunks.zig");

extern "C" fn rosette_cli_init() void;
extern "C" fn rosette_cli_deinit() void;

pub export fn rosette_run_snax86() void {
    rosette_cli_init();
    defer rosette_cli_deinit();
    rosette_run_snax86_core_inner();
}

fn rosette_run_snax86_core_inner() void {
    title_runtime.runTitle(.{
        .install_imports = win32_thunks.register_win32_console_thunks,
        .register_thunks = thunks.registerThunks,
        .load_program = program.loadProgram,
        // snake has no block grid rendering yet — skip grid source
    });
}

pub export fn rosette_run_snax86_core() void {
    rosette_run_snax86_core_inner();
}
