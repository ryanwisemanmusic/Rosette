pub const types = @import("types.zig");
pub const translator = @import("translator.zig");

pub const Ps1Translator = translator.Ps1Translator;
pub const Ps1Command = types.Ps1Command;
pub const CommandType = types.CommandType;
pub const Ps1Error = types.Ps1Error;

test {
    @import("std").testing.refAllDecls(@import("types.zig"));
    @import("std").testing.refAllDecls(@import("translator.zig"));
}
