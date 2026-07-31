pub const types = @import("types.zig");
pub const translator = @import("translator.zig");

pub const BatTranslator = translator.BatTranslator;
pub const BatCommand = types.BatCommand;
pub const CommandKind = types.CommandKind;
pub const Redirect = types.Redirect;
pub const BatError = types.BatError;

test {
    @import("std").testing.refAllDecls(@import("types.zig"));
    @import("std").testing.refAllDecls(@import("translator.zig"));
}
